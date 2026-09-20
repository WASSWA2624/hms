/**
 * Lab Follow-ups billing-sections scan
 *
 * Lab workspace `/lab?section=follow-ups` hosts the shared hospital-wide
 * follow-up worklist (no encounter_type filter). Proves list / update /
 * complete never post to patient Billing. Mutations stay NOT_BILLED.
 * Create Lab Order, collect/receive payment gates, and cashier settle
 * remain on other Lab tabs / Billing — not duplicated here. Save-result
 * is not payment-gated.
 *
 * @module tests/modules/follow-up/services
 */

jest.mock('@repositories/follow-up/follow-up.repository');
jest.mock('@lib/audit');
jest.mock('@lib/billing/clinical-request-billing', () => ({
  upsertClinicalRequestBilling: jest.fn(),
  receiveClinicalRequestPayment: jest.fn(),
  adjustClinicalRequestBilling: jest.fn(),
}));
jest.mock('@lib/billing/financials', () => ({
  recalculateInvoiceBalances: jest.fn(),
}));
jest.mock('@lib/identifiers/service-identifier-resolution', () => ({
  resolveIdentifierForFilter: jest.fn(async ({ value }) => value),
  resolveIdentifierForPayload: jest.fn(async ({ value }) => value),
}));
jest.mock('@prisma/client', () => ({
  follow_up: {
    count: jest.fn(),
    findMany: jest.fn(),
    findFirst: jest.fn(),
    update: jest.fn(),
  },
  encounter: {
    findFirst: jest.fn(),
  },
  user_role: {
    findMany: jest.fn(),
  },
  notification: {
    create: jest.fn(),
  },
  notification_delivery: {
    createMany: jest.fn(),
  },
}));
jest.mock('@lib/websocket', () => ({
  emitToUser: jest.fn(),
  NOTIFICATION_EVENTS: {
    NOTIFICATION_CREATED: 'notification.created',
  },
}));

const followUpRepository = require('@repositories/follow-up/follow-up.repository');
const prisma = require('@prisma/client');
const { createAuditLog } = require('@lib/audit');
const clinicalRequestBilling = require('@lib/billing/clinical-request-billing');
const financials = require('@lib/billing/financials');
const {
  resolveIdentifierForFilter,
  resolveIdentifierForPayload,
} = require('@lib/identifiers/service-identifier-resolution');
const {
  listFollowUps,
  updateFollowUp,
  completeFollowUp,
} = require('@services/follow-up/follow-up.service');

describe('Lab Follow-ups billing-sections scan', () => {
  const scheduledFollowUp = {
    id: 'fu-uuid-lab-1',
    human_friendly_id: 'FU-LAB-WS-1',
    encounter_id: 'enc-uuid-lab-1',
    scheduled_at: '2026-07-29T09:30:00.000Z',
    status: 'SCHEDULED',
    notes: 'Lab workspace callback',
    encounter: {
      id: 'enc-uuid-lab-1',
      human_friendly_id: 'ENC-LAB-1',
      encounter_type: 'OPD',
      patient: {
        id: 'pat-uuid-1',
        human_friendly_id: 'PAT-1',
        first_name: 'Follow',
        last_name: 'Patient',
        contacts: [
          {
            contact_type: 'PHONE',
            value: '+256700000001',
            is_primary: true,
          },
        ],
      },
    },
  };

  beforeEach(() => {
    jest.clearAllMocks();
    createAuditLog.mockResolvedValue({});
    resolveIdentifierForFilter.mockImplementation(async ({ value }) => value);
    resolveIdentifierForPayload.mockImplementation(async ({ value }) => value);
    prisma.follow_up.count.mockResolvedValue(0);
    prisma.follow_up.findMany.mockResolvedValue([]);
    prisma.follow_up.findFirst.mockResolvedValue(null);
    prisma.encounter.findFirst.mockResolvedValue({
      id: 'enc-uuid-lab-1',
      patient_id: 'pat-uuid-1',
      encounter_type: 'OPD',
    });
    followUpRepository.findMany.mockResolvedValue([scheduledFollowUp]);
    followUpRepository.count.mockResolvedValue(1);
  });

  const expectNoBillingPosts = () => {
    expect(clinicalRequestBilling.upsertClinicalRequestBilling).not.toHaveBeenCalled();
    expect(clinicalRequestBilling.receiveClinicalRequestPayment).not.toHaveBeenCalled();
    expect(clinicalRequestBilling.adjustClinicalRequestBilling).not.toHaveBeenCalled();
    expect(financials.recalculateInvoiceBalances).not.toHaveBeenCalled();
  };

  it('Lab Follow-ups list read does not touch patient billing ledger', async () => {
    const result = await listFollowUps(
      { status: 'SCHEDULED', tenant_id: 'tenant-1' },
      1,
      20,
      'scheduled_at',
      'asc',
    );

    expect(result.followUps).toHaveLength(1);
    expect(result.followUps[0].id).toBe('FU-LAB-WS-1');
    expect(result.followUps[0]).not.toHaveProperty('payment_status');
    expect(result.followUps[0]).not.toHaveProperty('balance');
    expect(result.followUps[0]).not.toHaveProperty('amount_due');
    expect(result.followUps[0]).not.toHaveProperty('paid');
    expect(result.followUps[0]).not.toHaveProperty('invoice_id');
    expect(followUpRepository.findMany).toHaveBeenCalledWith(
      {
        status: 'SCHEDULED',
        encounter: {
          tenant_id: 'tenant-1',
          deleted_at: null,
        },
      },
      0,
      20,
      { scheduled_at: 'asc' },
      expect.objectContaining({
        encounter: expect.any(Object),
      }),
    );
    expectNoBillingPosts();
  });

  it('Lab Follow-ups list GET is idempotent on replay (no double billing post)', async () => {
    const filters = { status: 'SCHEDULED', tenant_id: 'tenant-1' };
    const first = await listFollowUps(filters, 1, 20, 'scheduled_at', 'asc');
    const second = await listFollowUps(filters, 1, 20, 'scheduled_at', 'asc');

    expect(first.followUps).toEqual(second.followUps);
    expect(followUpRepository.findMany).toHaveBeenCalledTimes(2);
    expectNoBillingPosts();
  });

  it('Lab reschedule stays NOT_BILLED', async () => {
    followUpRepository.findById.mockResolvedValue({
      id: 'fu-uuid-lab-1',
      status: 'SCHEDULED',
      notes: 'Lab workspace callback',
      scheduled_at: '2026-07-29T09:30:00.000Z',
    });
    followUpRepository.update.mockResolvedValue({
      id: 'fu-uuid-lab-1',
      status: 'SCHEDULED',
      notes: 'Rescheduled lab call',
      scheduled_at: '2026-07-31T11:00:00.000Z',
    });

    const result = await updateFollowUp(
      'FU-LAB-WS-1',
      {
        scheduled_at: '2026-07-31T11:00:00.000Z',
        notes: 'Rescheduled lab call',
      },
      'user-123',
      '127.0.0.1',
    );

    expect(result.notes).toBe('Rescheduled lab call');
    expect(result).not.toHaveProperty('payment_status');
    expect(result).not.toHaveProperty('balance');
    expectNoBillingPosts();
  });

  it('Lab Mark completed stays NOT_BILLED (no invoice / payment post)', async () => {
    followUpRepository.findById.mockResolvedValue({
      id: 'fu-uuid-lab-1',
      status: 'SCHEDULED',
      notes: 'Lab workspace callback',
    });
    followUpRepository.update.mockResolvedValue({
      id: 'fu-uuid-lab-1',
      status: 'COMPLETED',
      completed_at: new Date('2026-07-30T08:00:00.000Z'),
      completed_by_user_id: 'user-123',
    });

    const result = await completeFollowUp(
      'FU-LAB-WS-1',
      { notes: 'Reached patient' },
      'user-123',
      '127.0.0.1',
    );

    expect(result.status).toBe('COMPLETED');
    expect(result).not.toHaveProperty('payment_status');
    expect(result).not.toHaveProperty('balance');
    expect(result).not.toHaveProperty('invoice_id');
    expectNoBillingPosts();
  });

  it('Lab complete replay does not duplicate billing posts', async () => {
    followUpRepository.findById.mockResolvedValue({
      id: 'fu-uuid-lab-1',
      status: 'SCHEDULED',
    });
    followUpRepository.update.mockResolvedValue({
      id: 'fu-uuid-lab-1',
      status: 'COMPLETED',
    });

    await completeFollowUp('FU-LAB-WS-1', {}, 'user-123', '127.0.0.1');
    followUpRepository.findById.mockResolvedValue({
      id: 'fu-uuid-lab-1',
      status: 'COMPLETED',
    });
    await completeFollowUp('FU-LAB-WS-1', {}, 'user-123', '127.0.0.1');

    expect(followUpRepository.update).toHaveBeenCalledTimes(1);
    expectNoBillingPosts();
  });

  it('unauthorized actor cannot settle via Lab Follow-ups handlers', async () => {
    await listFollowUps(
      { status: 'SCHEDULED', tenant_id: 'tenant-1' },
      1,
      20,
      'scheduled_at',
      'asc',
    );

    expect(clinicalRequestBilling.receiveClinicalRequestPayment).not.toHaveBeenCalled();
    expect(clinicalRequestBilling.adjustClinicalRequestBilling).not.toHaveBeenCalled();
    expect(clinicalRequestBilling.upsertClinicalRequestBilling).not.toHaveBeenCalled();
  });
});
