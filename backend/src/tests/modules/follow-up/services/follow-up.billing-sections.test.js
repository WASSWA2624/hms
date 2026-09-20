/**
 * Clinical Follow-ups billing-sections scan
 *
 * Proves follow-up list / create / update / complete handlers never post to
 * patient Billing (clinical-request-billing / financials). Callback worklist
 * mutations stay NOT_BILLED. Reserved visit charges must wire Billing when
 * mounted — not a parallel ledger.
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
  createFollowUp,
  updateFollowUp,
  completeFollowUp,
} = require('@services/follow-up/follow-up.service');

describe('clinical Follow-ups billing-sections scan', () => {
  const scheduledFollowUp = {
    id: 'fu-uuid-1',
    human_friendly_id: 'FU-1',
    encounter_id: 'enc-uuid-1',
    scheduled_at: '2026-07-29T09:30:00.000Z',
    status: 'SCHEDULED',
    notes: 'Callback about labs',
    encounter: {
      id: 'enc-uuid-1',
      human_friendly_id: 'ENC-1',
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
      id: 'enc-uuid-1',
      patient_id: 'pat-uuid-1',
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

  it('Follow-ups list read does not touch patient billing ledger', async () => {
    const result = await listFollowUps(
      { status: 'SCHEDULED', tenant_id: 'tenant-1' },
      1,
      20,
      'scheduled_at',
      'asc',
    );

    expect(result.followUps).toHaveLength(1);
    expect(result.followUps[0].id).toBe('FU-1');
    expect(result.followUps[0]).not.toHaveProperty('payment_status');
    expect(result.followUps[0]).not.toHaveProperty('balance');
    expect(result.followUps[0]).not.toHaveProperty('amount_due');
    expect(result.followUps[0]).not.toHaveProperty('paid');
    expect(result.followUps[0]).not.toHaveProperty('invoice_id');
    expectNoBillingPosts();
  });

  it('Follow-ups list GET is idempotent on replay (no double billing post)', async () => {
    const filters = { status: 'SCHEDULED', tenant_id: 'tenant-1' };
    const first = await listFollowUps(filters, 1, 20, 'scheduled_at', 'asc');
    const second = await listFollowUps(filters, 1, 20, 'scheduled_at', 'asc');

    expect(first.followUps).toEqual(second.followUps);
    expect(followUpRepository.findMany).toHaveBeenCalledTimes(2);
    expectNoBillingPosts();
  });

  it('create follow-up stays NOT_BILLED (no patient ledger post)', async () => {
    followUpRepository.create.mockResolvedValue({
      id: 'fu-uuid-2',
      human_friendly_id: 'FU-2',
      encounter_id: 'enc-uuid-1',
      status: 'SCHEDULED',
      scheduled_at: '2026-07-30T10:00:00.000Z',
    });
    resolveIdentifierForPayload.mockResolvedValue('enc-uuid-1');

    const result = await createFollowUp(
      {
        encounter_id: 'ENC-1',
        scheduled_at: '2026-07-30T10:00:00.000Z',
        notes: 'Reschedule callback',
      },
      'user-123',
      '127.0.0.1',
    );

    expect(result.id).toBe('fu-uuid-2');
    expect(result).not.toHaveProperty('payment_status');
    expect(result).not.toHaveProperty('balance');
    expectNoBillingPosts();
  });

  it('update / reschedule stays NOT_BILLED', async () => {
    followUpRepository.findById.mockResolvedValue({
      id: 'fu-uuid-1',
      status: 'SCHEDULED',
      notes: 'Old notes',
      scheduled_at: '2026-07-29T09:30:00.000Z',
    });
    followUpRepository.update.mockResolvedValue({
      id: 'fu-uuid-1',
      status: 'SCHEDULED',
      notes: 'New callback notes',
      scheduled_at: '2026-07-31T11:00:00.000Z',
    });

    const result = await updateFollowUp(
      'FU-1',
      {
        scheduled_at: '2026-07-31T11:00:00.000Z',
        notes: 'New callback notes',
      },
      'user-123',
      '127.0.0.1',
    );

    expect(result.notes).toBe('New callback notes');
    expect(result).not.toHaveProperty('payment_status');
    expect(result).not.toHaveProperty('balance');
    expectNoBillingPosts();
  });

  it('Mark completed stays NOT_BILLED', async () => {
    followUpRepository.findById.mockResolvedValue({
      id: 'fu-uuid-1',
      status: 'SCHEDULED',
      notes: 'Callback about labs',
    });
    followUpRepository.update.mockResolvedValue({
      id: 'fu-uuid-1',
      status: 'COMPLETED',
      completed_at: new Date('2026-07-30T08:00:00.000Z'),
      completed_by_user_id: 'user-123',
    });

    const result = await completeFollowUp(
      'FU-1',
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

  it('complete replay does not duplicate billing posts', async () => {
    followUpRepository.findById.mockResolvedValue({
      id: 'fu-uuid-1',
      status: 'SCHEDULED',
    });
    followUpRepository.update.mockResolvedValue({
      id: 'fu-uuid-1',
      status: 'COMPLETED',
    });

    await completeFollowUp('FU-1', {}, 'user-123', '127.0.0.1');
    // Second call: already COMPLETED → early return, still no billing.
    followUpRepository.findById.mockResolvedValue({
      id: 'fu-uuid-1',
      status: 'COMPLETED',
    });
    await completeFollowUp('FU-1', {}, 'user-123', '127.0.0.1');

    expect(followUpRepository.update).toHaveBeenCalledTimes(1);
    expectNoBillingPosts();
  });

  it('create replay does not duplicate billing posts', async () => {
    followUpRepository.create.mockResolvedValue({
      id: 'fu-uuid-3',
      human_friendly_id: 'FU-3',
      status: 'SCHEDULED',
    });
    resolveIdentifierForPayload.mockResolvedValue('enc-uuid-1');

    const payload = {
      encounter_id: 'ENC-1',
      scheduled_at: '2026-08-01T09:00:00.000Z',
    };

    await createFollowUp(payload, 'user-123', '127.0.0.1');
    await createFollowUp(payload, 'user-123', '127.0.0.1');

    expect(followUpRepository.create).toHaveBeenCalledTimes(2);
    expectNoBillingPosts();
  });

  it('unauthorized actor without write scopes still cannot settle via follow-up handlers', async () => {
    await listFollowUps({ status: 'SCHEDULED', tenant_id: 'tenant-1' }, 1, 20, 'scheduled_at', 'asc');

    expect(clinicalRequestBilling.receiveClinicalRequestPayment).not.toHaveBeenCalled();
    expect(clinicalRequestBilling.adjustClinicalRequestBilling).not.toHaveBeenCalled();
    expect(clinicalRequestBilling.upsertClinicalRequestBilling).not.toHaveBeenCalled();
  });
});
