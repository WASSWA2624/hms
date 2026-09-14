/**
 * User repository tests
 *
 * @module tests/modules/user/repositories
 * @description Tests for user repository
 * Per testing.mdc: Mock all Prisma calls, test error handling
 */

const userRepository = require('@repositories/user/user.repository');
const prisma = require('@prisma/client');
const { HttpError } = require('@lib/errors');

jest.mock('../../../../prisma/tenant-guard', () => ({
  runWithoutTenantGuard: jest.fn(async (callback) => callback()),
}));

jest.mock('@lib/database/foreign-key-references', () => ({
  listForeignKeyReferences: jest.fn(),
  countReferencingRows: jest.fn(),
  deleteReferencingRows: jest.fn()}));

// Mock Prisma client
jest.mock('@prisma/client', () => {
  const prismaMock = {
    $transaction: jest.fn(async (callback) => callback(prismaMock)),
    user: {
      findFirst: jest.fn(),
      findMany: jest.fn(),
      count: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      delete: jest.fn()
    },
    user_permission: {
      findMany: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      updateMany: jest.fn()},
    user_role: {
      create: jest.fn()},
    user_session: {
      updateMany: jest.fn()},
    user_profile: {
      findMany: jest.fn(),
      updateMany: jest.fn()},
    verification_token: {
      updateMany: jest.fn()},
    tenant: {
      findFirst: jest.fn()},
    facility: {
      findFirst: jest.fn()},
    staff_profile: {
      create: jest.fn(),
      updateMany: jest.fn(),
      findMany: jest.fn()}};

  return prismaMock;
});

describe('User Repository', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('findById', () => {
    const userId = '550e8400-e29b-41d4-a716-446655440000';
    const mockUser = {
      id: userId,
      tenant_id: '550e8400-e29b-41d4-a716-446655440001',
      email: 'test@example.com',
      status: 'ACTIVE'
    };

    it('should find user by ID', async () => {
      prisma.user.findFirst.mockResolvedValue(mockUser);

      const result = await userRepository.findById(userId);

      expect(result).toEqual(mockUser);
      expect(prisma.user.findFirst).toHaveBeenCalledWith({
        where: { id: userId, deleted_at: null },
        include: undefined
      });
    });

    it('should return null if user not found', async () => {
      prisma.user.findFirst.mockResolvedValue(null);

      const result = await userRepository.findById(userId);

      expect(result).toBeNull();
    });

    it('should filter out soft-deleted users', async () => {
      prisma.user.findFirst.mockResolvedValue(null);

      await userRepository.findById(userId);

      expect(prisma.user.findFirst).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({ deleted_at: null })
        })
      );
    });

    it('should accept include parameter', async () => {
      const include = { profile: true };
      prisma.user.findFirst.mockResolvedValue(mockUser);

      await userRepository.findById(userId, include);

      expect(prisma.user.findFirst).toHaveBeenCalledWith({
        where: { id: userId, deleted_at: null },
        include
      });
    });

    it('should throw HttpError on database error', async () => {
      prisma.user.findFirst.mockRejectedValue(new Error('DB Error'));

      await expect(userRepository.findById(userId)).rejects.toThrow(HttpError);
      await expect(userRepository.findById(userId)).rejects.toMatchObject({
        messageKey: 'errors.database.unexpected',
        statusCode: 500
      });
    });
  });

  describe('findMany', () => {
    const mockUsers = [
      {
        id: '550e8400-e29b-41d4-a716-446655440000',
        email: 'user1@example.com',
        status: 'ACTIVE'
      },
      {
        id: '550e8400-e29b-41d4-a716-446655440001',
        email: 'user2@example.com',
        status: 'INACTIVE'
      }
    ];

    it('should find many users with default params', async () => {
      prisma.user.findMany.mockResolvedValue(mockUsers);

      const result = await userRepository.findMany();

      expect(result).toEqual(mockUsers);
      expect(prisma.user.findMany).toHaveBeenCalledWith({
        where: { deleted_at: null },
        skip: 0,
        take: 20,
        orderBy: { created_at: 'desc' },
        include: undefined
      });
    });

    it('should apply filters', async () => {
      const filters = { tenant_id: '550e8400-e29b-41d4-a716-446655440002', status: 'ACTIVE' };
      prisma.user.findMany.mockResolvedValue(mockUsers);

      await userRepository.findMany(filters);

      expect(prisma.user.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { deleted_at: null, ...filters }
        })
      );
    });

    it('should apply pagination', async () => {
      prisma.user.findMany.mockResolvedValue(mockUsers);

      await userRepository.findMany({}, 20, 10);

      expect(prisma.user.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          skip: 20,
          take: 10
        })
      );
    });

    it('should apply custom ordering', async () => {
      const orderBy = { email: 'asc' };
      prisma.user.findMany.mockResolvedValue(mockUsers);

      await userRepository.findMany({}, 0, 20, orderBy);

      expect(prisma.user.findMany).toHaveBeenCalledWith(
        expect.objectContaining({ orderBy })
      );
    });

    it('should apply include parameter', async () => {
      const include = { profile: true, sessions: true };
      prisma.user.findMany.mockResolvedValue(mockUsers);

      await userRepository.findMany({}, 0, 20, { created_at: 'desc' }, include);

      expect(prisma.user.findMany).toHaveBeenCalledWith(
        expect.objectContaining({ include })
      );
    });

    it('should return empty array if no users found', async () => {
      prisma.user.findMany.mockResolvedValue([]);

      const result = await userRepository.findMany();

      expect(result).toEqual([]);
    });

    it('should throw HttpError on database error', async () => {
      prisma.user.findMany.mockRejectedValue(new Error('DB Error'));

      await expect(userRepository.findMany()).rejects.toThrow(HttpError);
    });
  });

  describe('count', () => {
    it('should count users with default filters', async () => {
      prisma.user.count.mockResolvedValue(42);

      const result = await userRepository.count();

      expect(result).toBe(42);
      expect(prisma.user.count).toHaveBeenCalledWith({
        where: { deleted_at: null }
      });
    });

    it('should count users with filters', async () => {
      const filters = { status: 'ACTIVE', tenant_id: '550e8400-e29b-41d4-a716-446655440000' };
      prisma.user.count.mockResolvedValue(10);

      const result = await userRepository.count(filters);

      expect(result).toBe(10);
      expect(prisma.user.count).toHaveBeenCalledWith({
        where: { deleted_at: null, ...filters }
      });
    });

    it('should return 0 if no users found', async () => {
      prisma.user.count.mockResolvedValue(0);

      const result = await userRepository.count();

      expect(result).toBe(0);
    });

    it('should throw HttpError on database error', async () => {
      prisma.user.count.mockRejectedValue(new Error('DB Error'));

      await expect(userRepository.count()).rejects.toThrow(HttpError);
    });
  });

  describe('create', () => {
    const userData = {
      tenant_id: '550e8400-e29b-41d4-a716-446655440000',
      email: 'newuser@example.com',
      password_hash: '$2b$10$abcdefghijklmnopqrstuvwxyz',
      status: 'ACTIVE'
    };

    const createdUser = {
      id: '550e8400-e29b-41d4-a716-446655440001',
      ...userData,
      created_at: new Date(),
      updated_at: new Date()
    };

    it('should create new user', async () => {
      prisma.user.create.mockResolvedValue(createdUser);
      prisma.user.findFirst.mockResolvedValue(createdUser);
      prisma.user_permission.findMany.mockResolvedValue([]);

      const result = await userRepository.create(userData);

      expect(result).toEqual(createdUser);
      expect(prisma.user.create).toHaveBeenCalledWith({ data: userData });
      expect(prisma.user.findFirst).toHaveBeenCalledWith({
        where: {
          id: createdUser.id,
          deleted_at: null},
        include: expect.objectContaining({
          facility: expect.objectContaining({
            select: expect.objectContaining({
              id: true,
              human_friendly_id: true,
              name: true})})})});
      expect(prisma.user.findFirst.mock.calls[0][0].include.facility.select.code).toBeUndefined();
      expect(prisma.user.findFirst.mock.calls[0][0].include.facility.select.slug).toBeUndefined();
    });

    it('should create permission links when permission_ids are provided', async () => {
      prisma.user.create.mockResolvedValue(createdUser);
      prisma.user.findFirst.mockResolvedValue(createdUser);
      prisma.user_permission.findMany.mockResolvedValue([]);
      prisma.user_permission.create.mockResolvedValue({});

      await userRepository.create({
        ...userData,
        permission_ids: ['perm-1', 'perm-2']});

      expect(prisma.user_permission.create).toHaveBeenCalledTimes(2);
      expect(prisma.user_permission.create).toHaveBeenNthCalledWith(1, {
        data: {
          user_id: createdUser.id,
          permission_id: 'perm-1'}});
      expect(prisma.user_permission.create).toHaveBeenNthCalledWith(2, {
        data: {
          user_id: createdUser.id,
          permission_id: 'perm-2'}});
    });

    it('should throw HttpError on unique constraint violation', async () => {
      const error = { code: 'P2002', meta: { target: ['email'] } };
      prisma.user.create.mockRejectedValue(error);

      await expect(userRepository.create(userData)).rejects.toThrow(HttpError);
      await expect(userRepository.create(userData)).rejects.toMatchObject({
        messageKey: 'errors.user.email_exists_in_tenant',
        statusCode: 409,
        errors: [expect.objectContaining({ field: 'email' })]});
    });

    it('should throw HttpError on foreign key violation', async () => {
      const error = { code: 'P2003', meta: { field_name: 'tenant_id' } };
      prisma.user.create.mockRejectedValue(error);

      await expect(userRepository.create(userData)).rejects.toThrow(HttpError);
      await expect(userRepository.create(userData)).rejects.toMatchObject({
        messageKey: 'errors.database.foreign_key_field',
        statusCode: 400
      });
    });

    it('should throw HttpError on other database errors', async () => {
      prisma.user.create.mockRejectedValue(new Error('DB Error'));

      await expect(userRepository.create(userData)).rejects.toThrow(HttpError);
      await expect(userRepository.create(userData)).rejects.toMatchObject({
        messageKey: 'errors.database.unexpected',
        statusCode: 500
      });
    });

    it('should fall back to a generic unique conflict when the constraint is unknown', async () => {
      const error = { code: 'P2002', meta: {} };
      prisma.user.create.mockRejectedValue(error);

      await expect(userRepository.create(userData)).rejects.toThrow(HttpError);
      await expect(userRepository.create(userData)).rejects.toMatchObject({
        messageKey: 'errors.database.unique_field',
        statusCode: 409,
        errors: [expect.objectContaining({ field: 'field' })]});
    });

    it('should read the violated constraint from the MariaDB driver adapter error', async () => {
      const error = {
        code: 'P2002',
        meta: {
          modelName: 'user',
          driverAdapterError: {
            cause: {
              kind: 'UniqueConstraintViolation',
              constraint: { index: 'user_tenant_id_email_key' }}}}};
      prisma.user.create.mockRejectedValue(error);

      await expect(userRepository.create(userData)).rejects.toMatchObject({
        messageKey: 'errors.user.email_exists_in_tenant',
        statusCode: 409,
        errors: [expect.objectContaining({ field: 'email' })]});
    });

    it('should map a staff number collision to a retryable conflict', async () => {
      const error = {
        code: 'P2002',
        meta: { target: 'staff_profile_tenant_id_staff_number_key' }};
      prisma.user.create.mockResolvedValue(createdUser);
      prisma.staff_profile.create.mockRejectedValue(error);

      await expect(
        userRepository.create({
          ...userData,
          staff_profile: { position: 'Nurse', staff_number: 'FMC-0001' }})
      ).rejects.toMatchObject({
        messageKey: 'errors.user.staff_number_conflict',
        statusCode: 409});
    });

    it('should handle P2003 error without meta.field_name', async () => {
      const error = { code: 'P2003', meta: {} };
      prisma.user.create.mockRejectedValue(error);

      await expect(userRepository.create(userData)).rejects.toThrow(HttpError);
      await expect(userRepository.create(userData)).rejects.toMatchObject({
        messageKey: 'errors.database.foreign_key_field',
        statusCode: 400
      });
    });

    it('should create the user, staff profile and role assignments in one transaction', async () => {
      prisma.user.create.mockResolvedValue(createdUser);
      prisma.staff_profile.create.mockResolvedValue({ id: 'staff-1' });
      prisma.user_role.create.mockResolvedValue({ id: 'user-role-1' });
      prisma.user.findFirst.mockResolvedValue(createdUser);

      await userRepository.create({
        ...userData,
        facility_id: 'facility-1',
        staff_profile: { position: 'Charge Nurse', staff_number: 'FMC-0001' },
        role_assignments: [
          { role_id: 'role-1', facility_id: 'facility-1' },
          { role_id: 'role-2', facility_id: null }]});

      expect(prisma.$transaction).toHaveBeenCalledTimes(1);
      expect(prisma.user.create).toHaveBeenCalledWith({
        data: { ...userData, facility_id: 'facility-1' }});
      expect(prisma.staff_profile.create).toHaveBeenCalledWith({
        data: {
          tenant_id: userData.tenant_id,
          user_id: createdUser.id,
          position: 'Charge Nurse',
          staff_number: 'FMC-0001'}});
      expect(prisma.user_role.create).toHaveBeenNthCalledWith(1, {
        data: {
          user_id: createdUser.id,
          role_id: 'role-1',
          tenant_id: userData.tenant_id,
          facility_id: 'facility-1'}});
      expect(prisma.user_role.create).toHaveBeenNthCalledWith(2, {
        data: {
          user_id: createdUser.id,
          role_id: 'role-2',
          tenant_id: userData.tenant_id,
          facility_id: null}});
      expect(prisma.user.findFirst.mock.calls[0][0].include).toEqual(
        expect.objectContaining({
          roles: expect.any(Object),
          staff_profile: expect.any(Object)})
      );
    });

    it('should roll the whole create back when a role assignment fails', async () => {
      prisma.user.create.mockResolvedValue(createdUser);
      prisma.staff_profile.create.mockResolvedValue({ id: 'staff-1' });
      prisma.user_role.create.mockRejectedValue({ code: 'P2003', meta: { field_name: 'role_id' } });

      await expect(
        userRepository.create({
          ...userData,
          staff_profile: { position: 'Nurse', staff_number: 'FMC-0002' },
          role_assignments: [{ role_id: 'missing-role', facility_id: null }]})
      ).rejects.toMatchObject({
        messageKey: 'errors.database.foreign_key_field',
        statusCode: 400});

      // Every write ran inside the one rejected transaction callback, so Prisma
      // discards them together and no created user is ever read back.
      expect(prisma.$transaction).toHaveBeenCalledTimes(1);
      expect(prisma.user.create).toHaveBeenCalledTimes(1);
      expect(prisma.user.findFirst).not.toHaveBeenCalled();
    });
  });

  describe('update', () => {
    const userId = '550e8400-e29b-41d4-a716-446655440000';
    const updateData = { status: 'INACTIVE', phone: '+256700000000' };
    const updatedUser = {
      id: userId,
      tenant_id: '550e8400-e29b-41d4-a716-446655440001',
      email: 'test@example.com',
      ...updateData,
      updated_at: new Date()
    };

    it('should update user', async () => {
      prisma.user.update.mockResolvedValue(updatedUser);
      prisma.user.findFirst.mockResolvedValue(updatedUser);

      const result = await userRepository.update(userId, updateData);

      expect(result).toEqual(updatedUser);
      expect(prisma.user.update).toHaveBeenCalledWith({
        where: { id: userId },
        data: updateData
      });
      expect(prisma.user.findFirst).toHaveBeenCalledWith({
        where: {
          id: userId,
          deleted_at: null},
        include: expect.objectContaining({
          facility: expect.objectContaining({
            select: expect.objectContaining({
              id: true,
              human_friendly_id: true,
              name: true})})})});
      expect(prisma.user.findFirst.mock.calls[0][0].include.facility.select.code).toBeUndefined();
      expect(prisma.user.findFirst.mock.calls[0][0].include.facility.select.slug).toBeUndefined();
    });

    it('should sync permission assignments on update', async () => {
      prisma.user.findFirst.mockResolvedValue(updatedUser);
      prisma.user_permission.findMany.mockResolvedValue([
        { id: 'up-1', user_id: userId, permission_id: 'perm-1', deleted_at: null },
        { id: 'up-2', user_id: userId, permission_id: 'perm-2', deleted_at: new Date('2025-01-01T00:00:00Z') }]);
      prisma.user_permission.update.mockResolvedValue({});
      prisma.user_permission.create.mockResolvedValue({});

      await userRepository.update(userId, { permission_ids: ['perm-2', 'perm-3'] });

      expect(prisma.user_permission.update).toHaveBeenCalledTimes(2);
      expect(prisma.user_permission.create).toHaveBeenCalledWith({
        data: {
          user_id: userId,
          permission_id: 'perm-3'}});
    });

    it('should throw HttpError if user not found', async () => {
      const error = { code: 'P2025' };
      prisma.user.update.mockRejectedValue(error);

      await expect(userRepository.update(userId, updateData)).rejects.toThrow(HttpError);
      await expect(userRepository.update(userId, updateData)).rejects.toMatchObject({
        messageKey: 'errors.user.not_found',
        statusCode: 404
      });
    });

    it('should throw HttpError on unique constraint violation', async () => {
      const error = { code: 'P2002', meta: { target: ['email'] } };
      prisma.user.update.mockRejectedValue(error);

      await expect(userRepository.update(userId, updateData)).rejects.toThrow(HttpError);
      await expect(userRepository.update(userId, updateData)).rejects.toMatchObject({
        messageKey: 'errors.user.email_exists_in_tenant',
        statusCode: 409,
        errors: [expect.objectContaining({ field: 'email' })]});
    });

    it('should throw HttpError on foreign key violation', async () => {
      const error = { code: 'P2003', meta: { field_name: 'facility_id' } };
      prisma.user.update.mockRejectedValue(error);

      await expect(userRepository.update(userId, updateData)).rejects.toThrow(HttpError);
      await expect(userRepository.update(userId, updateData)).rejects.toMatchObject({
        messageKey: 'errors.database.foreign_key_field',
        statusCode: 400
      });
    });

    it('should throw HttpError on other database errors', async () => {
      prisma.user.update.mockRejectedValue(new Error('DB Error'));

      await expect(userRepository.update(userId, updateData)).rejects.toThrow(HttpError);
    });

    it('should revoke active sessions in the same transaction when asked', async () => {
      prisma.user.update.mockResolvedValue(updatedUser);
      prisma.user_session.updateMany.mockResolvedValue({ count: 2 });
      prisma.user.findFirst.mockResolvedValue(updatedUser);

      await userRepository.update(userId, { status: 'INACTIVE' }, { revokeSessions: true });

      expect(prisma.$transaction).toHaveBeenCalledTimes(1);
      expect(prisma.user_session.updateMany).toHaveBeenCalledWith({
        where: { user_id: userId, revoked_at: null, deleted_at: null },
        data: { revoked_at: expect.any(Date) }});
    });

    it('should leave sessions alone by default', async () => {
      prisma.user.update.mockResolvedValue(updatedUser);
      prisma.user.findFirst.mockResolvedValue(updatedUser);

      await userRepository.update(userId, { position_title: 'Head Nurse' });

      expect(prisma.user_session.updateMany).not.toHaveBeenCalled();
    });
  });

  describe('findDeletedByTenantEmail', () => {
    it('only matches soft-deleted users in the tenant, excluding the edited user', async () => {
      prisma.user.findFirst.mockResolvedValue({ id: 'deleted-user' });

      const result = await userRepository.findDeletedByTenantEmail(
        'tenant-1',
        'jane@example.com',
        'self-id'
      );

      expect(result).toEqual({ id: 'deleted-user' });
      expect(prisma.user.findFirst).toHaveBeenCalledWith({
        where: {
          tenant_id: 'tenant-1',
          email: 'jane@example.com',
          deleted_at: { not: null },
          NOT: { id: 'self-id' }},
        select: { id: true, human_friendly_id: true }});
    });

    it('skips the lookup without a tenant or email', async () => {
      await expect(
        userRepository.findDeletedByTenantEmail(null, 'jane@example.com')
      ).resolves.toBeNull();
      expect(prisma.user.findFirst).not.toHaveBeenCalled();
    });
  });

  describe('softDelete', () => {
    const userId = '550e8400-e29b-41d4-a716-446655440000';
    const deletedUser = {
      id: userId,
      tenant_id: '550e8400-e29b-41d4-a716-446655440001',
      email: 'test@example.com',
      deleted_at: new Date()
    };

    it('should soft delete user', async () => {
      prisma.user.update.mockResolvedValue(deletedUser);
      prisma.user_permission.updateMany.mockResolvedValue({ count: 1 });

      const result = await userRepository.softDelete(userId);

      expect(result).toEqual(deletedUser);
      expect(prisma.user.update).toHaveBeenCalledWith({
        where: { id: userId },
        data: { deleted_at: expect.any(Date) }
      });
      expect(prisma.user_permission.updateMany).toHaveBeenCalledWith({
        where: {
          user_id: userId,
          deleted_at: null},
        data: {
          deleted_at: expect.any(Date)}});
      expect(prisma.user_session.updateMany).toHaveBeenCalledWith({
        where: {
          user_id: userId,
          revoked_at: null,
          deleted_at: null},
        data: { revoked_at: expect.any(Date) }});
    });

    it('should throw HttpError if user not found', async () => {
      const error = { code: 'P2025' };
      prisma.user.update.mockRejectedValue(error);

      await expect(userRepository.softDelete(userId)).rejects.toThrow(HttpError);
      await expect(userRepository.softDelete(userId)).rejects.toMatchObject({
        messageKey: 'errors.user.not_found',
        statusCode: 404
      });
    });

    it('should throw HttpError on other database errors', async () => {
      prisma.user.update.mockRejectedValue(new Error('DB Error'));

      await expect(userRepository.softDelete(userId)).rejects.toThrow(HttpError);
      await expect(userRepository.softDelete(userId)).rejects.toMatchObject({
        messageKey: 'errors.database.unexpected',
        statusCode: 500
      });
    });
  });

  describe('restore', () => {
    const userId = '550e8400-e29b-41d4-a716-446655440000';
    const tenantId = '550e8400-e29b-41d4-a716-446655440001';
    const facilityId = '550e8400-e29b-41d4-a716-446655440002';
    const deletedAt = new Date('2026-08-01T00:00:00.000Z');
    const existing = {
      id: userId,
      tenant_id: tenantId,
      facility_id: facilityId,
      deleted_at: deletedAt,
    };
    const restoredUser = {
      id: userId,
      tenant_id: tenantId,
      facility_id: facilityId,
      deleted_at: null,
    };

    it('should restore a soft-deleted user, matching permissions, and staff profile', async () => {
      prisma.user.findFirst.mockResolvedValue(existing);
      prisma.tenant.findFirst.mockResolvedValue({ id: tenantId });
      prisma.facility.findFirst.mockResolvedValue({ id: facilityId });
      prisma.user_permission.updateMany.mockResolvedValue({ count: 1 });
      prisma.staff_profile.updateMany.mockResolvedValue({ count: 1 });
      prisma.user.update.mockResolvedValue(restoredUser);

      const result = await userRepository.restore(userId);

      expect(result).toEqual(restoredUser);
      expect(prisma.user.findFirst).toHaveBeenCalledWith({
        where: {
          id: userId,
          OR: [{ deleted_at: null }, { deleted_at: { not: null } }],
        },
        select: {
          id: true,
          email: true,
          tenant_id: true,
          facility_id: true,
          deleted_at: true,
        },
      });
      expect(prisma.user_permission.updateMany).toHaveBeenCalledWith({
        where: {
          user_id: userId,
          deleted_at: deletedAt,
        },
        data: { deleted_at: null },
      });
      expect(prisma.staff_profile.updateMany).toHaveBeenCalledWith({
        where: {
          user_id: userId,
          deleted_at: { not: null },
        },
        data: { deleted_at: null },
      });
      expect(prisma.user.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: userId },
          data: { deleted_at: null },
        })
      );
    });

    it('should throw not_found when the user is missing or not soft-deleted', async () => {
      prisma.user.findFirst.mockResolvedValue({
        ...existing,
        deleted_at: null,
      });

      await expect(userRepository.restore(userId)).rejects.toMatchObject({
        messageKey: 'errors.user.not_found',
        statusCode: 404,
      });
    });

    it('should throw not_found for a purged account', async () => {
      prisma.user.findFirst.mockResolvedValue({
        ...existing,
        email: `deleted-user-${userId}@purged.invalid`,
      });

      await expect(userRepository.restore(userId)).rejects.toMatchObject({
        messageKey: 'errors.user.not_found',
        statusCode: 404,
      });
      expect(prisma.tenant.findFirst).not.toHaveBeenCalled();
    });

    it('should throw when the tenant is inactive', async () => {
      prisma.user.findFirst.mockResolvedValue(existing);
      prisma.tenant.findFirst.mockResolvedValue(null);

      await expect(userRepository.restore(userId)).rejects.toMatchObject({
        messageKey: 'errors.user.restore_requires_active_tenant',
        statusCode: 409,
      });
    });
  });

  describe('permanentDelete', () => {
    const userId = '550e8400-e29b-41d4-a716-446655440000';
    const deletedAt = new Date('2026-09-01T00:00:00.000Z');

    const foreignKeys = require('@lib/database/foreign-key-references');
    const referencesByTable = {
      user: [
        { table: 'audit_log', column: 'user_id' },
        { table: 'notification', column: 'user_id' },
        { table: 'staff_profile', column: 'user_id' },
        { table: 'user_profile', column: 'user_id' },
        { table: 'user_role', column: 'user_id' }],
      user_profile: [
        { table: 'address', column: 'user_profile_id' },
        { table: 'signed_form', column: 'user_profile_id' }],
      staff_profile: [
        { table: 'address', column: 'staff_profile_id' },
        { table: 'staff_leave', column: 'staff_profile_id' }]};
    const unusablePasswordHash = '$2b$10$unusablehashplaceholder';

    const arrangeDeletedUser = ({ counts = {} } = {}) => {
      prisma.user.findFirst.mockResolvedValue({
        id: userId,
        email: 'grace@example.com',
        deleted_at: deletedAt
      });
      prisma.user_profile.findMany.mockResolvedValue([{ id: 'profile-1' }]);
      prisma.staff_profile.findMany.mockResolvedValue([{ id: 'staff-1' }]);
      foreignKeys.listForeignKeyReferences.mockImplementation((client, table) =>
        Promise.resolve(referencesByTable[table] || [])
      );
      foreignKeys.countReferencingRows.mockImplementation((client, reference) =>
        Promise.resolve(counts[reference.table] || 0)
      );
      foreignKeys.deleteReferencingRows.mockResolvedValue(1);
      prisma.user.delete.mockResolvedValue({ id: userId });
      prisma.user.update.mockResolvedValue({ id: userId });
      prisma.user_profile.updateMany.mockResolvedValue({ count: 1 });
    };

    it('should delete a user whose only references grant it access', async () => {
      arrangeDeletedUser();

      const result = await userRepository.permanentDelete(userId, { unusablePasswordHash });

      // address x2 (profile details) + staff_profile + user_profile + user_role
      expect(result).toEqual({ removed_access_rows: 5, anonymized: false, history_tables: [] });
      expect(prisma.user.findFirst).toHaveBeenCalledWith({
        where: {
          id: userId,
          OR: [{ deleted_at: null }, { deleted_at: { not: null } }],
        },
        select: { id: true, email: true, deleted_at: true },
      });
      expect(foreignKeys.countReferencingRows).toHaveBeenCalledWith(
        prisma,
        { table: 'audit_log', column: 'user_id' },
        [userId]
      );
      // Inbox rows are detached by the database, never counted as history.
      expect(foreignKeys.countReferencingRows).not.toHaveBeenCalledWith(
        prisma,
        { table: 'notification', column: 'user_id' },
        expect.anything()
      );
      expect(foreignKeys.deleteReferencingRows).toHaveBeenCalledWith(
        prisma,
        { table: 'address', column: 'user_profile_id' },
        ['profile-1']
      );
      expect(foreignKeys.deleteReferencingRows).toHaveBeenCalledWith(
        prisma,
        { table: 'user_role', column: 'user_id' },
        [userId]
      );
      expect(foreignKeys.deleteReferencingRows).not.toHaveBeenCalledWith(
        prisma,
        { table: 'audit_log', column: 'user_id' },
        expect.anything()
      );
      expect(prisma.user.delete).toHaveBeenCalledWith({ where: { id: userId } });
      expect(prisma.user.update).not.toHaveBeenCalled();
    });

    it('should keep an anonymized row when history still references the user', async () => {
      arrangeDeletedUser({ counts: { audit_log: 4 } });

      const result = await userRepository.permanentDelete(userId, { unusablePasswordHash });

      expect(result).toEqual({
        removed_access_rows: 5,
        anonymized: true,
        history_tables: ['audit_log']
      });
      // Access rows still go.
      expect(foreignKeys.deleteReferencingRows).toHaveBeenCalledWith(
        prisma,
        { table: 'user_role', column: 'user_id' },
        [userId]
      );
      expect(foreignKeys.deleteReferencingRows).toHaveBeenCalledWith(
        prisma,
        { table: 'user_profile', column: 'user_id' },
        [userId]
      );
      expect(prisma.user.delete).not.toHaveBeenCalled();
      expect(prisma.user.update).toHaveBeenCalledWith({
        where: { id: userId },
        data: {
          email: `deleted-user-${userId}@purged.invalid`,
          phone: null,
          password_hash: unusablePasswordHash,
          status: 'INACTIVE'
        }
      });
      expect(prisma.user_profile.updateMany).not.toHaveBeenCalled();
    });

    it('should keep a staff profile that carries HR history', async () => {
      arrangeDeletedUser({ counts: { staff_leave: 1 } });

      const result = await userRepository.permanentDelete(userId, { unusablePasswordHash });

      expect(result).toMatchObject({ anonymized: true, history_tables: ['staff_leave'] });
      expect(foreignKeys.deleteReferencingRows).not.toHaveBeenCalledWith(
        prisma,
        { table: 'staff_profile', column: 'user_id' },
        expect.anything()
      );
      // Its address is a personal detail and still goes.
      expect(foreignKeys.deleteReferencingRows).toHaveBeenCalledWith(
        prisma,
        { table: 'address', column: 'staff_profile_id' },
        ['staff-1']
      );
      expect(prisma.user.delete).not.toHaveBeenCalled();
    });

    it('should erase the name on a profile that records point at', async () => {
      arrangeDeletedUser({ counts: { signed_form: 1 } });

      await userRepository.permanentDelete(userId, { unusablePasswordHash });

      expect(foreignKeys.deleteReferencingRows).not.toHaveBeenCalledWith(
        prisma,
        { table: 'user_profile', column: 'user_id' },
        expect.anything()
      );
      expect(prisma.user_profile.updateMany).toHaveBeenCalledWith({
        where: { user_id: userId },
        data: {
          first_name: 'Deleted user',
          middle_name: null,
          last_name: null,
          gender: null,
          date_of_birth: null
        }
      });
      expect(prisma.user.update).toHaveBeenCalled();
    });

    it('should refuse a user that is not soft-deleted', async () => {
      prisma.user.findFirst.mockResolvedValue({ id: userId, deleted_at: null });

      await expect(
        userRepository.permanentDelete(userId, { unusablePasswordHash })
      ).rejects.toMatchObject({
        messageKey: 'errors.user.permanent_delete_not_soft_deleted',
        statusCode: 400,
      });
      expect(prisma.user.delete).not.toHaveBeenCalled();
    });

    it('should throw not_found when the user is missing', async () => {
      prisma.user.findFirst.mockResolvedValue(null);

      await expect(
        userRepository.permanentDelete(userId, { unusablePasswordHash })
      ).rejects.toMatchObject({
        messageKey: 'errors.user.not_found',
        statusCode: 404,
      });
    });

    it('should treat an already purged account as missing', async () => {
      prisma.user.findFirst.mockResolvedValue({
        id: userId,
        email: `deleted-user-${userId}@purged.invalid`,
        deleted_at: deletedAt
      });

      await expect(
        userRepository.permanentDelete(userId, { unusablePasswordHash })
      ).rejects.toMatchObject({
        messageKey: 'errors.user.not_found',
        statusCode: 404,
      });
      expect(prisma.user.delete).not.toHaveBeenCalled();
    });

    it('should report a restricting reference the scan missed as history', async () => {
      arrangeDeletedUser();
      prisma.user.delete.mockRejectedValue({ code: 'P2003' });

      await expect(
        userRepository.permanentDelete(userId, { unusablePasswordHash })
      ).rejects.toMatchObject({
        messageKey: 'errors.user.permanent_delete_has_history',
        statusCode: 409,
      });
    });
  });

  describe('setPassword', () => {
    const userId = '550e8400-e29b-41d4-a716-446655440000';

    it('should replace the hash, end every session and void reset links together', async () => {
      prisma.user.update.mockResolvedValue({ id: userId });
      prisma.user_session.updateMany.mockResolvedValue({ count: 2 });
      prisma.verification_token.updateMany.mockResolvedValue({ count: 1 });

      await userRepository.setPassword(userId, '$2b$10$newhash');

      expect(prisma.$transaction).toHaveBeenCalled();
      expect(prisma.user.update).toHaveBeenCalledWith({
        where: { id: userId },
        data: { password_hash: '$2b$10$newhash' }
      });
      expect(prisma.user_session.updateMany).toHaveBeenCalledWith({
        where: { user_id: userId, revoked_at: null, deleted_at: null },
        data: { revoked_at: expect.any(Date) }
      });
      expect(prisma.verification_token.updateMany).toHaveBeenCalledWith({
        where: { user_id: userId, type: 'PASSWORD_RESET', deleted_at: null },
        data: { deleted_at: expect.any(Date) }
      });
    });

    it('should throw not_found when the user is missing', async () => {
      prisma.user.update.mockRejectedValue({ code: 'P2025' });

      await expect(userRepository.setPassword(userId, '$2b$10$newhash')).rejects.toMatchObject({
        messageKey: 'errors.user.not_found',
        statusCode: 404
      });
    });
  });
});
