/**
 * Registration attempt repository tests
 *
 * @module tests/modules/auth/repositories
 * @description Covers the transactional facility-owner bootstrap and the
 * durable registration-attempt records that make registration idempotent.
 */

const { HttpError } = require('@lib/errors');

jest.mock('@prisma/client', () => {
  const delegate = () => ({
    create: jest.fn(),
    update: jest.fn(),
    delete: jest.fn(),
    deleteMany: jest.fn(),
    findFirst: jest.fn(),
    findUnique: jest.fn(),
  });

  return {
    $connect: jest.fn(),
    $disconnect: jest.fn(),
    $transaction: jest.fn(),
    tenant: delegate(),
    facility: delegate(),
    role: delegate(),
    user: delegate(),
    user_profile: delegate(),
    user_role: delegate(),
    registration_attempt: delegate(),
  };
});

jest.mock('@lib/tenant/resolve-tenant-contact', () => ({
  buildRegistrationContactExtension: jest.fn().mockReturnValue({}),
}));

jest.mock('@lib/authorization/platform-access-catalog', () => ({
  resolvePlatformRole: jest.fn(),
}));

const prisma = require('@prisma/client');
const { resolvePlatformRole } = require('@lib/authorization/platform-access-catalog');
const {
  registerFacilityOwner,
  beginRegistrationAttempt,
  findRegistrationAttemptByKey,
  completeRegistrationAttempt,
  releaseRegistrationAttempt,
} = require('@repositories/auth/auth.repository');

const buildTx = () => ({
  tenant: { create: jest.fn().mockResolvedValue({ id: 'tenant-1' }) },
  facility: { create: jest.fn().mockResolvedValue({ id: 'facility-1' }) },
  role: { create: jest.fn().mockResolvedValue({ id: 'role-1' }) },
  user: {
    create: jest.fn().mockResolvedValue({ id: 'user-1' }),
    findFirst: jest.fn().mockResolvedValue({ id: 'user-1', email: 'owner@example.com' }),
  },
  user_profile: { create: jest.fn().mockResolvedValue({ id: 'profile-1' }) },
  user_role: { create: jest.fn().mockResolvedValue({ id: 'user-role-1' }) },
  registration_attempt: { update: jest.fn().mockResolvedValue({ id: 'attempt-1' }) },
});

const registrationPayload = {
  email: 'owner@example.com',
  phone: '256701234567',
  password_hash: 'hashed',
  facility_name: 'Mirembe Clinic',
  tenant_name: 'Mirembe Clinic',
  facility_type: 'CLINIC',
  admin_name: 'Jane Doe',
  status: 'PENDING',
};

describe('Auth repository - registration bootstrap', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    resolvePlatformRole.mockResolvedValue({ id: 'platform-tenant-admin' });
  });

  describe('registerFacilityOwner', () => {
    it('creates tenant, facility, user, and profile inside one transaction', async () => {
      const tx = buildTx();
      prisma.$transaction.mockImplementation((callback) => callback(tx));

      await registerFacilityOwner(registrationPayload);

      expect(prisma.$transaction).toHaveBeenCalledTimes(1);
      expect(tx.tenant.create).toHaveBeenCalledTimes(1);
      expect(tx.facility.create).toHaveBeenCalledTimes(1);
      expect(tx.user.create).toHaveBeenCalledTimes(1);
      expect(tx.user_profile.create).toHaveBeenCalledTimes(1);
      expect(tx.user_role.create).toHaveBeenCalledTimes(1);
      // The owner holds the platform TENANT_ADMIN role; no tenant copy is created.
      expect(resolvePlatformRole).toHaveBeenCalledWith('TENANT_ADMIN', tx);
      expect(tx.role.create).not.toHaveBeenCalled();
      expect(tx.user_role.create).toHaveBeenCalledWith({
        data: expect.objectContaining({ role_id: 'platform-tenant-admin' }),
      });

      // Nothing is written outside the transaction, so a later failure cannot
      // leave an orphaned tenant or facility behind.
      expect(prisma.tenant.create).not.toHaveBeenCalled();
      expect(prisma.facility.create).not.toHaveBeenCalled();
      expect(prisma.user.create).not.toHaveBeenCalled();
    });

    it('claims the registration email on the attempt row inside the same transaction', async () => {
      const tx = buildTx();
      prisma.$transaction.mockImplementation((callback) => callback(tx));

      await registerFacilityOwner({
        ...registrationPayload,
        registration_attempt_id: 'attempt-1',
      });

      expect(tx.registration_attempt.update).toHaveBeenCalledWith({
        where: { id: 'attempt-1' },
        data: {
          claimed_email: 'owner@example.com',
          user_id: 'user-1',
          tenant_id: 'tenant-1',
          facility_id: 'facility-1',
        },
      });
    });

    it('skips the claim when no attempt is tracked', async () => {
      const tx = buildTx();
      prisma.$transaction.mockImplementation((callback) => callback(tx));

      await registerFacilityOwner(registrationPayload);

      expect(tx.registration_attempt.update).not.toHaveBeenCalled();
    });

    it('reports a duplicate email when the claim conflicts, so nothing is committed', async () => {
      const tx = buildTx();
      tx.registration_attempt.update.mockRejectedValue(
        Object.assign(new Error('Unique constraint failed'), {
          code: 'P2002',
          meta: { target: ['claimed_email'] },
        })
      );
      prisma.$transaction.mockImplementation((callback) => callback(tx));

      await expect(
        registerFacilityOwner({
          ...registrationPayload,
          registration_attempt_id: 'attempt-1',
        })
      ).rejects.toMatchObject({
        messageKey: 'errors.auth.user_exists',
        statusCode: 409,
      });
    });

    it('surfaces a mid-transaction failure instead of returning a partial account', async () => {
      const tx = buildTx();
      tx.user.create.mockRejectedValue(new Error('connection lost'));
      prisma.$transaction.mockImplementation((callback) => callback(tx));

      await expect(registerFacilityOwner(registrationPayload)).rejects.toBeInstanceOf(HttpError);
      expect(tx.user_profile.create).not.toHaveBeenCalled();
      expect(tx.user_role.create).not.toHaveBeenCalled();
    });
  });

  describe('beginRegistrationAttempt', () => {
    const claim = {
      idempotency_key: 'key-1',
      email: 'owner@example.com',
      expires_at: new Date('2026-09-12T00:00:00.000Z'),
      request_hash: 'hash-1',
    };

    it('records a fresh attempt for an unseen key', async () => {
      prisma.registration_attempt.create.mockResolvedValue({
        id: 'attempt-1',
        status: 'IN_PROGRESS',
      });

      const result = await beginRegistrationAttempt(claim);

      expect(result).toEqual({
        attempt: { id: 'attempt-1', status: 'IN_PROGRESS' },
        replayed: false,
      });
    });

    it('returns the stored attempt for a repeated key', async () => {
      prisma.registration_attempt.create.mockRejectedValue(
        Object.assign(new Error('Unique constraint failed'), {
          code: 'P2002',
          meta: { target: ['idempotency_key'] },
        })
      );
      prisma.registration_attempt.findUnique.mockResolvedValue({
        id: 'attempt-1',
        status: 'SUCCEEDED',
        started_at: new Date(),
      });

      const result = await beginRegistrationAttempt(claim);

      expect(result.replayed).toBe(true);
      expect(result.attempt.status).toBe('SUCCEEDED');
      expect(prisma.registration_attempt.update).not.toHaveBeenCalled();
    });

    it('takes over an attempt abandoned in progress by a dead process', async () => {
      prisma.registration_attempt.create.mockRejectedValue(
        Object.assign(new Error('Unique constraint failed'), { code: 'P2002' })
      );
      prisma.registration_attempt.findUnique.mockResolvedValue({
        id: 'attempt-1',
        status: 'IN_PROGRESS',
        claimed_email: null,
        started_at: new Date(Date.now() - 10 * 60 * 1000),
      });
      prisma.registration_attempt.update.mockResolvedValue({
        id: 'attempt-1',
        status: 'IN_PROGRESS',
      });

      const result = await beginRegistrationAttempt(claim);

      expect(result.replayed).toBe(false);
      expect(prisma.registration_attempt.update).toHaveBeenCalledTimes(1);
    });

    it('does not take over an attempt that is still running', async () => {
      prisma.registration_attempt.create.mockRejectedValue(
        Object.assign(new Error('Unique constraint failed'), { code: 'P2002' })
      );
      prisma.registration_attempt.findUnique.mockResolvedValue({
        id: 'attempt-1',
        status: 'IN_PROGRESS',
        claimed_email: null,
        started_at: new Date(),
      });

      const result = await beginRegistrationAttempt(claim);

      expect(result.replayed).toBe(true);
      expect(prisma.registration_attempt.update).not.toHaveBeenCalled();
    });

    it('degrades to null when the table is not migrated yet', async () => {
      prisma.registration_attempt.create.mockRejectedValue(
        Object.assign(new Error('table missing'), { code: 'P2021' })
      );

      await expect(beginRegistrationAttempt(claim)).resolves.toBeNull();
    });
  });

  describe('attempt lookup and completion', () => {
    it('reads an attempt by its idempotency key', async () => {
      prisma.registration_attempt.findUnique.mockResolvedValue({ id: 'attempt-1' });

      await expect(findRegistrationAttemptByKey('key-1')).resolves.toEqual({ id: 'attempt-1' });
      expect(prisma.registration_attempt.findUnique).toHaveBeenCalledWith({
        where: { idempotency_key: 'key-1' },
      });
    });

    it('stamps the outcome on completion', async () => {
      prisma.registration_attempt.update.mockResolvedValue({ id: 'attempt-1' });

      await completeRegistrationAttempt('attempt-1', {
        status: 'SUCCEEDED',
        outcome_code: 'ACCOUNT_CREATED_EMAIL_SENT',
        email_status: 'SENT',
        user_id: 'user-1',
        result_json: { outcome: 'ACCOUNT_CREATED_EMAIL_SENT' },
      });

      expect(prisma.registration_attempt.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: 'attempt-1' },
          data: expect.objectContaining({
            status: 'SUCCEEDED',
            outcome_code: 'ACCOUNT_CREATED_EMAIL_SENT',
            email_status: 'SENT',
            completed_at: expect.any(Date),
          }),
        })
      );
    });

    it('frees the key only while no email is claimed', async () => {
      prisma.registration_attempt.deleteMany.mockResolvedValue({ count: 1 });

      await releaseRegistrationAttempt('attempt-1');

      // Filtered on claimed_email: an attempt that already created an account
      // must keep its claim even when a later step failed.
      expect(prisma.registration_attempt.deleteMany).toHaveBeenCalledWith({
        where: { id: 'attempt-1', claimed_email: null },
      });
    });

    it('ignores an already-removed attempt on release', async () => {
      prisma.registration_attempt.deleteMany.mockRejectedValue(
        Object.assign(new Error('not found'), { code: 'P2025' })
      );

      await expect(releaseRegistrationAttempt('attempt-1')).resolves.toBeUndefined();
    });
  });
});
