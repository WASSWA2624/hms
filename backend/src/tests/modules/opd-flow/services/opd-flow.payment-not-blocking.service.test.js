/**
 * Payment is a parallel fact about an OPD visit, not a workflow position.
 *
 * An outstanding consultation balance must not overwrite the clinical status a
 * surface shows, and must not drag a visit that has already been triaged or
 * seen back to "Payment due".
 */

jest.mock('@repositories/opd-flow/opd-flow.repository');
jest.mock('@lib/audit', () => ({ createAuditLog: jest.fn().mockResolvedValue({}) }));
jest.mock('@services/ipd-flow/ipd-flow.service', () => ({
  emitAdmissionRefreshEvent: jest.fn().mockResolvedValue(null)}));
jest.mock(
  '@services/clinical-alert-threshold/clinical-alert-threshold.service',
  () => ({ evaluateVitalAndCreateAlerts: jest.fn().mockResolvedValue(null) })
);
jest.mock('@lib/websocket', () => ({
  emitToUser: jest.fn(),
  emitToUsers: jest.fn(),
  OPD_EVENTS: { OPD_FLOW_UPDATED: 'opd.flow.updated' },
  NOTIFICATION_EVENTS: { NOTIFICATION_CREATED: 'notification.created' }}));
jest.mock('@prisma/client', () => ({
  $transaction: jest.fn(),
  encounter: { findFirst: jest.fn(), update: jest.fn() },
  user_role: { findMany: jest.fn().mockResolvedValue([]) },
  notification: { create: jest.fn() },
  notification_delivery: { createMany: jest.fn() }}));

const { resolveOpdDisplayState } = require('@services/opd-flow/opd-flow.service');

const UNPAID_CONSULTATION = {
  require_payment: true,
  is_paid: false,
  payment_status: 'PENDING'};

const buildEncounter = (overrides = {}) => ({
  id: 'enc-1',
  status: 'OPEN',
  provider_user_id: null,
  vital_signs: [],
  lab_orders: [],
  radiology_orders: [],
  pharmacy_orders: [],
  ...overrides});

describe('OPD display state does not let billing mask clinical progress', () => {
  it('shows Payment due only while nothing clinical has started', () => {
    const resolved = resolveOpdDisplayState(buildEncounter(), {
      stage: 'WAITING_CONSULTATION_PAYMENT',
      consultation: UNPAID_CONSULTATION});

    expect(resolved.display_code).toBe('PAYMENT_DUE');
    expect(resolved.payment_due).toBe(true);
  });

  it('keeps reporting the clinical step once vitals exist, with the balance flagged', () => {
    const resolved = resolveOpdDisplayState(
      buildEncounter({
        vital_signs: [{ id: 'vital-1', vital_type: 'TEMPERATURE', deleted_at: null }]}),
      {
        stage: 'WAITING_DOCTOR_ASSIGNMENT',
        consultation: UNPAID_CONSULTATION}
    );

    expect(resolved.display_code).toBe('DOCTOR_NEEDED');
    expect(resolved.stage).toBe('WAITING_DOCTOR_ASSIGNMENT');
    // The balance is still reported, just not as the headline status.
    expect(resolved.payment_due).toBe(true);
  });

  it('keeps an unpaid but attended patient with the doctor', () => {
    const resolved = resolveOpdDisplayState(
      buildEncounter({
        provider_user_id: 'doc-1',
        vital_signs: [{ id: 'vital-1', vital_type: 'TEMPERATURE', deleted_at: null }]}),
      {
        stage: 'WAITING_DOCTOR_REVIEW',
        consultation: UNPAID_CONSULTATION}
    );

    expect(resolved.display_code).toBe('WITH_DOCTOR');
    expect(resolved.payment_due).toBe(true);
  });

  it('reports a settled consultation as not payment due', () => {
    const resolved = resolveOpdDisplayState(buildEncounter(), {
      stage: 'WAITING_VITALS',
      consultation: { require_payment: true, is_paid: true, payment_status: 'PAID' }});

    expect(resolved.payment_due).toBe(false);
    expect(resolved.display_code).toBe('VITALS_NEEDED');
  });
});
