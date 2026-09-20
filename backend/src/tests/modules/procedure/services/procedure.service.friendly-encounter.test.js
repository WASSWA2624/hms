/**
 * Procedures accept a human-friendly encounter id (ENC…) like the lab and
 * radiology request endpoints, so a procedure can be requested from any surface
 * without first looking the encounter UUID up.
 */

jest.mock('@repositories/procedure/procedure.repository');
jest.mock('@lib/audit', () => ({
  createAuditLog: jest.fn().mockResolvedValue(undefined)}));
jest.mock('@prisma/client', () => ({
  encounter: {
    findFirst: jest.fn()},
  procedure: {
    update: jest.fn()},
  $transaction: jest.fn()}));
jest.mock('@lib/billing/clinical-request-billing', () => {
  const actual = jest.requireActual('@lib/billing/clinical-request-billing');
  return {
    ...actual,
    persistProcedureBilling: jest.fn().mockResolvedValue(null),
    reverseClinicalRequestBilling: jest.fn().mockResolvedValue(null),
    extractStoredClinicalBilling: jest.fn().mockReturnValue(null),
    buildProcedureBillingFromRequest: jest.fn().mockResolvedValue(null)};
});

const prisma = require('@prisma/client');
const procedureRepository = require('@repositories/procedure/procedure.repository');
const procedureService = require('@services/procedure/procedure.service');
const { HttpError } = require('@lib/errors');

const ENCOUNTER_UUID = '550e8400-e29b-41d4-a716-446655440000';

describe('procedure.service encounter identifier resolution', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    prisma.$transaction.mockImplementation(async (fn) => fn(prisma));
  });

  it('resolves a human-friendly encounter id before persisting', async () => {
    prisma.encounter.findFirst.mockResolvedValue({ id: ENCOUNTER_UUID });
    procedureRepository.create.mockResolvedValue({
      id: 'proc-1',
      encounter_id: ENCOUNTER_UUID,
      description: 'Wound dressing'});

    await procedureService.createProcedure(
      {
        encounter_id: 'ENC000123',
        description: 'Wound dressing'},
      'user-1',
      '127.0.0.1'
    );

    expect(procedureRepository.create).toHaveBeenCalledWith(
      expect.objectContaining({ encounter_id: ENCOUNTER_UUID })
    );
  });

  it('reports an unresolvable encounter as not found rather than a server error', async () => {
    prisma.encounter.findFirst.mockResolvedValue(null);

    await expect(
      procedureService.createProcedure(
        { encounter_id: 'ENC999999', description: 'Suture' },
        'user-1',
        '127.0.0.1'
      )
    ).rejects.toBeInstanceOf(HttpError);
    expect(procedureRepository.create).not.toHaveBeenCalled();
  });
});
