/**
 * User service tests
 *
 * @module tests/modules/user/services
 * @description Tests for user service
 * Per testing.mdc: Mock repository, test business logic
 */

const userService = require('@services/user/user.service');
const userRepository = require('@repositories/user/user.repository');
const { createAuditLog } = require('@lib/audit');
const { hashPassword } = require('@lib/crypto');
const { HttpError } = require('@lib/errors');

// Mock dependencies
jest.mock('@repositories/user/user.repository');
jest.mock('@lib/audit');
jest.mock('@lib/crypto');
jest.mock('@prisma/client', () => ({
  user_role: { findMany: jest.fn().mockResolvedValue([]) },
  permission: { findMany: jest.fn().mockResolvedValue([]) }}));
jest.mock('@lib/authorization/assignable-access', () => ({
  PLATFORM_ADMIN_MANAGED_ROLES: new Set(['PLATFORM_ADMIN', 'PLATFORM_OWNER']),
  assertPermissionIdsAssignable: jest.fn(async (ids) => ids),
  assertRoleIdAssignable: jest.fn(),
  canActorCreatePlatformRole: jest.fn(() => false),
  canActorCreateTenantWideRole: jest.fn(() => true),
  canActorManagePlatformAdmins: jest.fn(() => false)}));
jest.mock('@lib/websocket/crud-realtime', () => ({
  publishCrudRealtimeEvent: jest.fn().mockResolvedValue(undefined)}));
jest.mock('@lib/realtime/platform-realtime', () => ({
  publishPlatformRealtimeEvent: jest.fn().mockResolvedValue(undefined)}));

const prisma = require('@prisma/client');
const assignableAccess = require('@lib/authorization/assignable-access');
const { publishCrudRealtimeEvent } = require('@lib/websocket/crud-realtime');
const { publishPlatformRealtimeEvent } = require('@lib/realtime/platform-realtime');

describe('User Service', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    hashPassword.mockResolvedValue('$2b$10$hashedpasswordplaceholder');
    prisma.user_role.findMany.mockResolvedValue([]);
    prisma.permission.findMany.mockResolvedValue([]);
    assignableAccess.assertPermissionIdsAssignable.mockImplementation(async (ids) => ids);
    assignableAccess.canActorCreatePlatformRole.mockReturnValue(false);
    assignableAccess.canActorCreateTenantWideRole.mockReturnValue(true);
    assignableAccess.canActorManagePlatformAdmins.mockReturnValue(false);
    publishCrudRealtimeEvent.mockResolvedValue(undefined);
    publishPlatformRealtimeEvent.mockResolvedValue(undefined);
  });

  describe('listUsers', () => {
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

    it('should list users with pagination', async () => {
      userRepository.findMany.mockResolvedValue(mockUsers);
      userRepository.count.mockResolvedValue(2);

      const result = await userService.listUsers({}, 1, 20, null, 'asc', 'user-id', '127.0.0.1');

      expect(result).toHaveProperty('users', mockUsers);
      expect(result).toHaveProperty('pagination');
      expect(result.pagination).toMatchObject({
        page: 1,
        limit: 20,
        total: 2,
        totalPages: 1,
        hasNextPage: false,
        hasPreviousPage: false
      });
    });

    it('should apply filters correctly', async () => {
      const filters = {
        tenant_id: '550e8400-e29b-41d4-a716-446655440002',
        status: 'ACTIVE'
      };
      userRepository.findMany.mockResolvedValue(mockUsers);
      userRepository.count.mockResolvedValue(2);

      await userService.listUsers(filters, 1, 20, null, 'asc', 'user-id', '127.0.0.1');

      expect(userRepository.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          tenant_id: filters.tenant_id,
          status: filters.status
        }),
        expect.any(Number),
        expect.any(Number),
        expect.any(Object),
        expect.any(Object),
        expect.any(Object)
      );
    });

    it('should apply search filter with OR clause', async () => {
      const filters = { search: 'john' };
      userRepository.findMany.mockResolvedValue(mockUsers);
      userRepository.count.mockResolvedValue(2);

      await userService.listUsers(filters, 1, 20, null, 'asc', 'user-id', '127.0.0.1');

      expect(userRepository.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          OR: expect.arrayContaining([
            { email: { contains: 'john' } },
            { phone: { contains: 'john' } },
            { position_title: { contains: 'john' } }
          ])
        }),
        expect.any(Number),
        expect.any(Number),
        expect.any(Object),
        expect.any(Object),
        expect.any(Object)
      );
    });

    it('should calculate pagination correctly', async () => {
      userRepository.findMany.mockResolvedValue(mockUsers);
      userRepository.count.mockResolvedValue(42);

      const result = await userService.listUsers({}, 2, 10, null, 'asc', 'user-id', '127.0.0.1');

      expect(result.pagination).toMatchObject({
        page: 2,
        limit: 10,
        total: 42,
        totalPages: 5,
        hasNextPage: true,
        hasPreviousPage: true
      });
      expect(userRepository.findMany).toHaveBeenCalledWith(
        expect.any(Object),
        10, // skip: (2-1) * 10
        10,
        expect.any(Object),
        expect.any(Object),
        expect.any(Object)
      );
    });

    it('should apply custom sorting', async () => {
      userRepository.findMany.mockResolvedValue(mockUsers);
      userRepository.count.mockResolvedValue(2);

      await userService.listUsers({}, 1, 20, 'email', 'desc', 'user-id', '127.0.0.1');

      expect(userRepository.findMany).toHaveBeenCalledWith(
        expect.any(Object),
        expect.any(Number),
        expect.any(Number),
        { email: 'desc' },
        expect.any(Object),
        expect.any(Object)
      );
    });

    it('should use default sorting when sortBy not provided', async () => {
      userRepository.findMany.mockResolvedValue(mockUsers);
      userRepository.count.mockResolvedValue(2);

      await userService.listUsers({}, 1, 20, null, 'asc', 'user-id', '127.0.0.1');

      expect(userRepository.findMany).toHaveBeenCalledWith(
        expect.any(Object),
        expect.any(Number),
        expect.any(Number),
        { created_at: 'desc' },
        expect.any(Object),
        expect.any(Object)
      );
    });

    it('should handle repository errors', async () => {
      userRepository.findMany.mockRejectedValue(new Error('DB Error'));

      await expect(
        userService.listUsers({}, 1, 20, null, 'asc', 'user-id', '127.0.0.1')
      ).rejects.toThrow(HttpError);
    });

    it('should propagate HttpError from repository', async () => {
      const httpError = new HttpError('errors.database.unexpected', 500);
      userRepository.findMany.mockRejectedValue(httpError);

      await expect(
        userService.listUsers({}, 1, 20, null, 'asc', 'user-id', '127.0.0.1')
      ).rejects.toThrow(httpError);
    });
  });

  describe('getUserById', () => {
    const userId = '550e8400-e29b-41d4-a716-446655440000';
    const mockUser = {
      id: userId,
      email: 'test@example.com',
      status: 'ACTIVE'
    };

    it('should get user by ID', async () => {
      userRepository.findById.mockResolvedValue(mockUser);

      const result = await userService.getUserById(userId, 'requester-id', '127.0.0.1');

      expect(result).toEqual(mockUser);
      expect(userRepository.findById).toHaveBeenCalledWith(
        userId,
        expect.objectContaining({
          facility: expect.objectContaining({
            select: expect.objectContaining({
              id: true,
              human_friendly_id: true,
              name: true})})})
      );
      expect(userRepository.findById.mock.calls[0][1].facility.select.code).toBeUndefined();
      expect(userRepository.findById.mock.calls[0][1].facility.select.slug).toBeUndefined();
    });

    it('should throw HttpError if user not found', async () => {
      userRepository.findById.mockResolvedValue(null);

      await expect(
        userService.getUserById(userId, 'requester-id', '127.0.0.1')
      ).rejects.toThrow(HttpError);
      await expect(
        userService.getUserById(userId, 'requester-id', '127.0.0.1')
      ).rejects.toMatchObject({
        messageKey: 'errors.user.not_found',
        statusCode: 404
      });
    });

    it('should handle repository errors', async () => {
      userRepository.findById.mockRejectedValue(new Error('DB Error'));

      await expect(
        userService.getUserById(userId, 'requester-id', '127.0.0.1')
      ).rejects.toThrow(HttpError);
    });

    it('should propagate HttpError from repository', async () => {
      const httpError = new HttpError('errors.database.unexpected', 500);
      userRepository.findById.mockRejectedValue(httpError);

      await expect(
        userService.getUserById(userId, 'requester-id', '127.0.0.1')
      ).rejects.toThrow(httpError);
    });
  });

  describe('createUser', () => {
    const userData = {
      tenant_id: '550e8400-e29b-41d4-a716-446655440000',
      position_title: 'Charge Nurse',
      email: 'newuser@example.com',
      first_name: 'New',
      last_name: 'User',
      password_hash: '$2b$10$abcdefghijklmnopqrstuvwxyz',
      status: 'ACTIVE'
    };

    // The repository row never reaches callers with its hash; see user.lifecycle tests.
    const { password_hash: _passwordHash, ...publicUserData } = userData;
    const createdUser = {
      id: '550e8400-e29b-41d4-a716-446655440001',
      ...publicUserData,
      created_at: new Date(),
      updated_at: new Date()
    };

    beforeEach(() => {
      // Uniqueness now scans tenant peers via findMany; default to no peers.
      userRepository.findMany.mockResolvedValue([]);
    });

    it('should create new user', async () => {
      userRepository.create.mockResolvedValue(createdUser);
      createAuditLog.mockResolvedValue(true);

      const result = await userService.createUser(userData, 'creator-id', '127.0.0.1');

      expect(result).toEqual(createdUser);
      // first_name/last_name are folded into a nested profile on persistence.
      expect(userRepository.create).toHaveBeenCalledWith(
        expect.objectContaining({
          tenant_id: userData.tenant_id,
          position_title: 'Charge Nurse',
          email: 'newuser@example.com',
          status: 'ACTIVE',
          profile: { first_name: 'New', last_name: 'User' }
        })
      );
      expect(userRepository.create.mock.calls[0][0].first_name).toBeUndefined();
    });

    it('should trim position_title before persistence', async () => {
      userRepository.create.mockResolvedValue(createdUser);
      createAuditLog.mockResolvedValue(true);

      await userService.createUser(
        { ...userData, position_title: '  Charge Nurse  ' },
        'creator-id',
        '127.0.0.1'
      );

      expect(userRepository.create).toHaveBeenCalledWith(
        expect.objectContaining({ position_title: 'Charge Nurse' })
      );
    });

    it('should normalize permission_ids before persistence', async () => {
      userRepository.create.mockResolvedValue(createdUser);
      createAuditLog.mockResolvedValue(true);

      await userService.createUser(
        {
          ...userData,
          permission_ids: [
            '550e8400-e29b-41d4-a716-446655440010',
            ' 550e8400-e29b-41d4-a716-446655440010 ',
            '550e8400-e29b-41d4-a716-446655440011']},
        'creator-id',
        '127.0.0.1'
      );

      expect(userRepository.create).toHaveBeenCalledWith(
        expect.objectContaining({
          permission_ids: [
            '550e8400-e29b-41d4-a716-446655440010',
            '550e8400-e29b-41d4-a716-446655440011']})
      );
    });

    it('should hash non-bcrypt password_hash values before persistence', async () => {
      const plainPasswordPayload = {
        ...userData,
        password_hash: 'PlainPassword123!'};
      userRepository.create.mockResolvedValue(createdUser);
      createAuditLog.mockResolvedValue(true);

      await userService.createUser(plainPasswordPayload, 'creator-id', '127.0.0.1');

      expect(hashPassword).toHaveBeenCalledWith('PlainPassword123!');
      expect(userRepository.create).toHaveBeenCalledWith(
        expect.objectContaining({
          password_hash: '$2b$10$hashedpasswordplaceholder'})
      );
    });

    it('should create audit log for user creation', async () => {
      userRepository.create.mockResolvedValue(createdUser);
      createAuditLog.mockResolvedValue(true);

      await userService.createUser(userData, 'creator-id', '127.0.0.1');

      // Wait for non-blocking audit log
      await new Promise(resolve => setImmediate(resolve));

      expect(createAuditLog).toHaveBeenCalledWith({
        user_id: 'creator-id',
        action: 'CREATE',
        entity: 'user',
        entity_id: createdUser.id,
        diff: { after: createdUser },
        ip_address: '127.0.0.1'
      });
    });

    it('should not fail if audit log fails', async () => {
      userRepository.create.mockResolvedValue(createdUser);
      createAuditLog.mockRejectedValue(new Error('Audit Error'));

      const result = await userService.createUser(userData, 'creator-id', '127.0.0.1');

      expect(result).toEqual(createdUser);
    });

    it('should require position_title on create', async () => {
      await expect(
        userService.createUser(
          { ...userData, position_title: '   ' },
          'creator-id',
          '127.0.0.1'
        )
      ).rejects.toThrow(HttpError);
    });

    it('should handle repository errors', async () => {
      userRepository.create.mockRejectedValue(new Error('DB Error'));

      await expect(
        userService.createUser(userData, 'creator-id', '127.0.0.1')
      ).rejects.toThrow(HttpError);
    });

    it('should propagate HttpError from repository', async () => {
      const httpError = new HttpError('errors.database.unique_field', 409);
      userRepository.create.mockRejectedValue(httpError);

      await expect(
        userService.createUser(userData, 'creator-id', '127.0.0.1')
      ).rejects.toThrow(httpError);
    });

    it('should reject duplicate email within the same tenant', async () => {
      userRepository.findMany.mockResolvedValue([
        {
          id: 'existing-user',
          human_friendly_id: 'USR9001',
          tenant_id: userData.tenant_id,
          email: 'existing@example.com',
          phone: null,
          position_title: 'Nurse'
        }
      ]);

      await expect(
        userService.createUser(
          { ...userData, email: 'Existing@Example.com', phone: '783230321' },
          'creator-id',
          '127.0.0.1'
        )
      ).rejects.toMatchObject({
        messageKey: 'errors.user.email_exists_in_tenant',
        statusCode: 409,
        errors: [expect.objectContaining({ field: 'email' })]});
      expect(userRepository.create).not.toHaveBeenCalled();
    });

    it('should reject duplicate phone within the same tenant', async () => {
      userRepository.findMany.mockResolvedValue([
        {
          id: 'existing-user',
          human_friendly_id: 'USR9002',
          tenant_id: userData.tenant_id,
          email: 'someoneelse@example.com',
          phone: '256783230321',
          position_title: 'Nurse'
        }
      ]);

      await expect(
        userService.createUser(
          { ...userData, phone: '+256 783 230 321' },
          'creator-id',
          '127.0.0.1'
        )
      ).rejects.toMatchObject({
        messageKey: 'errors.user.phone_exists_in_tenant',
        statusCode: 409,
        errors: [expect.objectContaining({ field: 'phone' })]});
      expect(userRepository.create).not.toHaveBeenCalled();
    });

    it('should include the conflicting match payload on exact contact conflicts', async () => {
      userRepository.findMany.mockResolvedValue([
        {
          id: 'existing-user',
          human_friendly_id: 'USR9003',
          tenant_id: userData.tenant_id,
          email: 'newuser@example.com',
          phone: null,
          position_title: 'Nurse'
        }
      ]);

      await expect(
        userService.createUser(userData, 'creator-id', '127.0.0.1')
      ).rejects.toMatchObject({
        messageKey: 'errors.user.email_exists_in_tenant',
        statusCode: 409,
        errors: [
          expect.objectContaining({
            field: 'email',
            matches: expect.arrayContaining([
              expect.objectContaining({ exactEmailConflict: true })
            ])
          })
        ]
      });
    });

    it('should reject a near-duplicate user with similar_exists when not confirmed', async () => {
      userRepository.findMany.mockResolvedValue([
        {
          id: 'existing-user',
          human_friendly_id: 'USR9004',
          tenant_id: userData.tenant_id,
          email: 'someoneelse@example.com',
          phone: '256999888777',
          position_title: 'Charge Nurses'
        }
      ]);

      await expect(
        userService.createUser(
          { ...userData, phone: '256111222333', position_title: 'Charge Nurse' },
          'creator-id',
          '127.0.0.1'
        )
      ).rejects.toMatchObject({
        messageKey: 'errors.user.similar_exists',
        statusCode: 409,
        errors: [expect.objectContaining({ field: 'email' })]});
      expect(userRepository.create).not.toHaveBeenCalled();
    });

    it('should create a near-duplicate user when confirm_similar is set', async () => {
      userRepository.findMany.mockResolvedValue([
        {
          id: 'existing-user',
          human_friendly_id: 'USR9005',
          tenant_id: userData.tenant_id,
          email: 'someoneelse@example.com',
          phone: '256999888777',
          position_title: 'Charge Nurses'
        }
      ]);
      userRepository.create.mockResolvedValue(createdUser);
      createAuditLog.mockResolvedValue(true);

      const result = await userService.createUser(
        {
          ...userData,
          phone: '256111222333',
          position_title: 'Charge Nurse',
          confirm_similar: true
        },
        'creator-id',
        '127.0.0.1'
      );

      expect(result).toEqual(createdUser);
      // confirm_similar must be stripped before persistence.
      expect(userRepository.create).toHaveBeenCalledWith(
        expect.not.objectContaining({ confirm_similar: expect.anything() })
      );
    });

    it('should still block an exact contact conflict even with confirm_similar', async () => {
      userRepository.findMany.mockResolvedValue([
        {
          id: 'existing-user',
          human_friendly_id: 'USR9006',
          tenant_id: userData.tenant_id,
          email: 'newuser@example.com',
          phone: null,
          position_title: 'Nurse'
        }
      ]);

      await expect(
        userService.createUser(
          { ...userData, confirm_similar: true },
          'creator-id',
          '127.0.0.1'
        )
      ).rejects.toMatchObject({
        messageKey: 'errors.user.email_exists_in_tenant',
        statusCode: 409
      });
      expect(userRepository.create).not.toHaveBeenCalled();
    });
  });

  describe('updateUser', () => {
    const userId = '550e8400-e29b-41d4-a716-446655440000';
    const updateData = { status: 'INACTIVE' };
    const beforeUser = {
      id: userId,
      email: 'test@example.com',
      status: 'ACTIVE'
    };
    const afterUser = {
      id: userId,
      email: 'test@example.com',
      status: 'INACTIVE'
    };

    it('should update user', async () => {
      userRepository.findById.mockResolvedValue(beforeUser);
      userRepository.update.mockResolvedValue(afterUser);
      createAuditLog.mockResolvedValue(true);

      const result = await userService.updateUser(userId, updateData, 'updater-id', '127.0.0.1');

      expect(result).toEqual(afterUser);
      expect(userRepository.findById.mock.calls[0][1].facility.select.code).toBeUndefined();
      expect(userRepository.findById.mock.calls[0][1].facility.select.slug).toBeUndefined();
      // Deactivation ends every session in the same write.
      expect(userRepository.update).toHaveBeenCalledWith(userId, updateData, {
        revokeSessions: true
      });
    });

    it('should trim position_title on update', async () => {
      userRepository.findById.mockResolvedValue(beforeUser);
      userRepository.update.mockResolvedValue({
        ...afterUser,
        position_title: 'Head Nurse'
      });
      createAuditLog.mockResolvedValue(true);

      await userService.updateUser(
        userId,
        { position_title: '  Head Nurse  ' },
        'updater-id',
        '127.0.0.1'
      );

      expect(userRepository.update).toHaveBeenCalledWith(
        userId,
        { position_title: 'Head Nurse' },
        { revokeSessions: false }
      );
    });

    it('should normalize permission_ids on update', async () => {
      userRepository.findById.mockResolvedValue(beforeUser);
      userRepository.update.mockResolvedValue(afterUser);
      createAuditLog.mockResolvedValue(true);

      await userService.updateUser(
        userId,
        {
          permission_ids: [
            '550e8400-e29b-41d4-a716-446655440010',
            ' 550e8400-e29b-41d4-a716-446655440010 ',
            '550e8400-e29b-41d4-a716-446655440011']},
        'updater-id',
        '127.0.0.1'
      );

      expect(userRepository.update).toHaveBeenCalledWith(
        userId,
        {
          permission_ids: [
            '550e8400-e29b-41d4-a716-446655440010',
            '550e8400-e29b-41d4-a716-446655440011']},
        { revokeSessions: false }
      );
    });

    it('should throw HttpError if user not found', async () => {
      userRepository.findById.mockResolvedValue(null);

      await expect(
        userService.updateUser(userId, updateData, 'updater-id', '127.0.0.1')
      ).rejects.toThrow(HttpError);
      await expect(
        userService.updateUser(userId, updateData, 'updater-id', '127.0.0.1')
      ).rejects.toMatchObject({
        messageKey: 'errors.user.not_found',
        statusCode: 404
      });
    });

    it('should create audit log with before and after states', async () => {
      userRepository.findById.mockResolvedValue(beforeUser);
      userRepository.update.mockResolvedValue(afterUser);
      createAuditLog.mockResolvedValue(true);

      await userService.updateUser(userId, updateData, 'updater-id', '127.0.0.1');

      // Wait for non-blocking audit log
      await new Promise(resolve => setImmediate(resolve));

      expect(createAuditLog).toHaveBeenCalledWith({
        user_id: 'updater-id',
        action: 'UPDATE',
        entity: 'user',
        entity_id: userId,
        diff: { before: beforeUser, after: afterUser },
        ip_address: '127.0.0.1',
        details: { sessions_revoked: true }
      });
    });

    it('should not fail if audit log fails', async () => {
      userRepository.findById.mockResolvedValue(beforeUser);
      userRepository.update.mockResolvedValue(afterUser);
      createAuditLog.mockRejectedValue(new Error('Audit Error'));

      const result = await userService.updateUser(userId, updateData, 'updater-id', '127.0.0.1');

      expect(result).toEqual(afterUser);
    });

    it('should handle repository errors', async () => {
      userRepository.findById.mockResolvedValue(beforeUser);
      userRepository.update.mockRejectedValue(new Error('DB Error'));

      await expect(
        userService.updateUser(userId, updateData, 'updater-id', '127.0.0.1')
      ).rejects.toThrow(HttpError);
    });

    it('should propagate HttpError from repository', async () => {
      userRepository.findById.mockResolvedValue(beforeUser);
      const httpError = new HttpError('errors.database.unique_field', 409);
      userRepository.update.mockRejectedValue(httpError);

      await expect(
        userService.updateUser(userId, updateData, 'updater-id', '127.0.0.1')
      ).rejects.toThrow(httpError);
    });
  });

  describe('deleteUser', () => {
    const userId = '550e8400-e29b-41d4-a716-446655440000';
    const mockUser = {
      id: userId,
      email: 'test@example.com',
      status: 'ACTIVE'
    };

    it('should soft delete user', async () => {
      userRepository.findById.mockResolvedValue(mockUser);
      userRepository.softDelete.mockResolvedValue({ ...mockUser, deleted_at: new Date() });
      createAuditLog.mockResolvedValue(true);

      await userService.deleteUser(userId, 'deleter-id', '127.0.0.1');

      expect(userRepository.softDelete).toHaveBeenCalledWith(userId);
    });

    it('should throw HttpError if user not found', async () => {
      userRepository.findById.mockResolvedValue(null);

      await expect(
        userService.deleteUser(userId, 'deleter-id', '127.0.0.1')
      ).rejects.toThrow(HttpError);
      await expect(
        userService.deleteUser(userId, 'deleter-id', '127.0.0.1')
      ).rejects.toMatchObject({
        messageKey: 'errors.user.not_found',
        statusCode: 404
      });
    });

    it('should create audit log with before state', async () => {
      userRepository.findById.mockResolvedValue(mockUser);
      userRepository.softDelete.mockResolvedValue({ ...mockUser, deleted_at: new Date() });
      createAuditLog.mockResolvedValue(true);

      await userService.deleteUser(userId, 'deleter-id', '127.0.0.1');

      // Wait for non-blocking audit log
      await new Promise(resolve => setImmediate(resolve));

      expect(createAuditLog).toHaveBeenCalledWith({
        user_id: 'deleter-id',
        action: 'DELETE',
        entity: 'user',
        entity_id: userId,
        diff: { before: mockUser },
        ip_address: '127.0.0.1'
      });
    });

    it('should not fail if audit log fails', async () => {
      userRepository.findById.mockResolvedValue(mockUser);
      userRepository.softDelete.mockResolvedValue({ ...mockUser, deleted_at: new Date() });
      createAuditLog.mockRejectedValue(new Error('Audit Error'));

      await expect(
        userService.deleteUser(userId, 'deleter-id', '127.0.0.1')
      ).resolves.not.toThrow();
    });

    it('should handle repository errors', async () => {
      userRepository.findById.mockResolvedValue(mockUser);
      userRepository.softDelete.mockRejectedValue(new Error('DB Error'));

      await expect(
        userService.deleteUser(userId, 'deleter-id', '127.0.0.1')
      ).rejects.toThrow(HttpError);
    });

    it('should propagate HttpError from repository', async () => {
      userRepository.findById.mockResolvedValue(mockUser);
      const httpError = new HttpError('errors.user.not_found', 404);
      userRepository.softDelete.mockRejectedValue(httpError);

      await expect(
        userService.deleteUser(userId, 'deleter-id', '127.0.0.1')
      ).rejects.toThrow(httpError);
    });
  });

  describe('permanentDeleteUser', () => {
    const userId = '550e8400-e29b-41d4-a716-446655440000';
    const deletedUser = {
      id: userId,
      tenant_id: '550e8400-e29b-41d4-a716-446655440001',
      email: 'test@example.com',
      status: 'ACTIVE',
      password_hash: '$2b$10$hashedpasswordplaceholder',
      deleted_at: new Date('2026-09-01T00:00:00.000Z')
    };

    it('should purge a soft-deleted user and audit it by identifiers only', async () => {
      userRepository.findById.mockResolvedValue(deletedUser);
      userRepository.permanentDelete.mockResolvedValue({
        removed_access_rows: 3,
        anonymized: true,
        history_tables: ['audit_log']
      });
      createAuditLog.mockResolvedValue(true);

      await userService.permanentDeleteUser(userId, 'deleter-id', '127.0.0.1');
      await new Promise((resolve) => setImmediate(resolve));

      expect(userRepository.findById).toHaveBeenCalledWith(userId, undefined, {
        includeDeleted: true
      });
      expect(userRepository.permanentDelete).toHaveBeenCalledWith(userId, {
        unusablePasswordHash: '$2b$10$hashedpasswordplaceholder'
      });
      expect(createAuditLog).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'USER_PERMANENTLY_DELETED',
          entity: 'user',
          entity_id: userId,
          diff: expect.objectContaining({
            irreversible: true,
            anonymized: true,
            history_tables: ['audit_log'],
            removed_access_rows: 3
          })
        })
      );
      // The purge erased the email; the audit trail must not keep it.
      expect(createAuditLog.mock.calls[0][0].diff.before).toEqual({
        id: userId,
        human_friendly_id: null,
        tenant_id: deletedUser.tenant_id,
        facility_id: null
      });
      expect(publishCrudRealtimeEvent).toHaveBeenCalledWith(
        expect.objectContaining({ event: 'user.permanently_deleted' })
      );
    });

    it('should refuse a user that is not soft-deleted', async () => {
      userRepository.findById.mockResolvedValue({ ...deletedUser, deleted_at: null });

      await expect(
        userService.permanentDeleteUser(userId, 'deleter-id', '127.0.0.1')
      ).rejects.toMatchObject({
        messageKey: 'errors.user.permanent_delete_not_soft_deleted',
        statusCode: 400
      });
      expect(userRepository.permanentDelete).not.toHaveBeenCalled();
    });

    it('should throw not found when the user does not exist', async () => {
      userRepository.findById.mockResolvedValue(null);

      await expect(
        userService.permanentDeleteUser(userId, 'deleter-id', '127.0.0.1')
      ).rejects.toMatchObject({
        messageKey: 'errors.user.not_found',
        statusCode: 404
      });
    });

    it('should treat an already purged account as not found', async () => {
      userRepository.findById.mockResolvedValue({
        ...deletedUser,
        email: `deleted-user-${userId}@purged.invalid`
      });

      await expect(
        userService.permanentDeleteUser(userId, 'deleter-id', '127.0.0.1')
      ).rejects.toMatchObject({
        messageKey: 'errors.user.not_found',
        statusCode: 404
      });
      expect(userRepository.permanentDelete).not.toHaveBeenCalled();
    });

    it('should propagate a repository failure', async () => {
      userRepository.findById.mockResolvedValue(deletedUser);
      userRepository.permanentDelete.mockRejectedValue(
        new HttpError('errors.user.permanent_delete_has_history', 409)
      );

      await expect(
        userService.permanentDeleteUser(userId, 'deleter-id', '127.0.0.1')
      ).rejects.toMatchObject({
        messageKey: 'errors.user.permanent_delete_has_history',
        statusCode: 409
      });
    });
  });
});
