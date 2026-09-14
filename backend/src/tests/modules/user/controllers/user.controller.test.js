/**
 * User controller tests
 *
 * @module tests/modules/user/controllers
 * @description Tests for user controller
 * Per testing.mdc: Mock service, test HTTP handling
 */

const userController = require('@controllers/user/user.controller');
const userService = require('@services/user/user.service');
const { sendSuccess, sendPaginated, sendNoContent } = require('@lib/response');
const { DEFAULT_PAGE, DEFAULT_PAGE_LIMIT } = require('@config/constants');

// Mock dependencies
jest.mock('@services/user/user.service');
jest.mock('@lib/response');

describe('User Controller', () => {
  let req, res;

  beforeEach(() => {
    jest.clearAllMocks();
    
    req = {
      query: {},
      params: {},
      body: {},
      user: { id: 'requester-id' },
      ip: '127.0.0.1'
    };

    res = {
      status: jest.fn().mockReturnThis(),
      json: jest.fn().mockReturnThis()
    };
  });

  describe('listUsers', () => {
    const mockResult = {
      users: [
        { id: '1', email: 'user1@example.com', status: 'ACTIVE' },
        { id: '2', email: 'user2@example.com', status: 'INACTIVE' }
      ],
      pagination: {
        page: 1,
        limit: 20,
        total: 2,
        totalPages: 1,
        hasNextPage: false,
        hasPreviousPage: false
      }
    };

    it('should list users with default pagination', async () => {
      userService.listUsers.mockResolvedValue(mockResult);

      await userController.listUsers(req, res);

      expect(userService.listUsers).toHaveBeenCalledWith(
        expect.any(Object),
        DEFAULT_PAGE,
        DEFAULT_PAGE_LIMIT,
        undefined,
        'asc',
        'requester-id',
        '127.0.0.1'
      );
      expect(sendPaginated).toHaveBeenCalledWith(
        res,
        'messages.user.list.success',
        mockResult.users,
        mockResult.pagination
      );
    });

    it('should apply filters from query params', async () => {
      req.query = {
        tenant_id: '550e8400-e29b-41d4-a716-446655440000',
        facility_id: '550e8400-e29b-41d4-a716-446655440001',
        status: 'ACTIVE',
        email: 'test@example.com',
        search: 'john',
        page: '2',
        limit: '10',
        sort_by: 'email',
        order: 'desc'
      };
      userService.listUsers.mockResolvedValue(mockResult);

      await userController.listUsers(req, res);

      expect(userService.listUsers).toHaveBeenCalledWith(
        {
          tenant_id: '550e8400-e29b-41d4-a716-446655440000',
          facility_id: '550e8400-e29b-41d4-a716-446655440001',
          status: 'ACTIVE',
          email: 'test@example.com',
          search: 'john'
        },
        2,
        10,
        'email',
        'desc',
        'requester-id',
        '127.0.0.1'
      );
    });

    it('should handle missing user in request', async () => {
      req.user = undefined;
      userService.listUsers.mockResolvedValue(mockResult);

      await userController.listUsers(req, res);

      expect(userService.listUsers).toHaveBeenCalledWith(
        expect.any(Object),
        expect.any(Number),
        expect.any(Number),
        undefined,
        'asc',
        undefined,
        '127.0.0.1'
      );
    });

    it('should handle service errors', async () => {
      const error = new Error('Service error');
      userService.listUsers.mockRejectedValue(error);

      await expect(userController.listUsers(req, res)).rejects.toThrow(error);
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
      req.params = { id: userId };
      userService.getUserById.mockResolvedValue(mockUser);

      await userController.getUserById(req, res);

      expect(userService.getUserById).toHaveBeenCalledWith(
        userId,
        'requester-id',
        '127.0.0.1'
      );
      expect(sendSuccess).toHaveBeenCalledWith(
        res,
        200,
        'messages.user.get.success',
        mockUser
      );
    });

    it('should handle missing user in request', async () => {
      req.user = undefined;
      req.params = { id: userId };
      userService.getUserById.mockResolvedValue(mockUser);

      await userController.getUserById(req, res);

      expect(userService.getUserById).toHaveBeenCalledWith(
        userId,
        undefined,
        '127.0.0.1'
      );
    });

    it('should handle service errors', async () => {
      req.params = { id: userId };
      const error = new Error('Service error');
      userService.getUserById.mockRejectedValue(error);

      await expect(userController.getUserById(req, res)).rejects.toThrow(error);
    });
  });

  describe('createUser', () => {
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
      req.body = userData;
      userService.createUser.mockResolvedValue(createdUser);

      await userController.createUser(req, res);

      expect(userService.createUser).toHaveBeenCalledWith(
        userData,
        'requester-id',
        '127.0.0.1',
        { id: 'requester-id' }
      );
      expect(sendSuccess).toHaveBeenCalledWith(
        res,
        201,
        'messages.user.create.success',
        createdUser
      );
    });

    it('should handle missing user in request', async () => {
      req.user = undefined;
      req.body = userData;
      userService.createUser.mockResolvedValue(createdUser);

      await userController.createUser(req, res);

      expect(userService.createUser).toHaveBeenCalledWith(
        userData,
        undefined,
        '127.0.0.1',
        undefined
      );
    });

    it('should handle service errors', async () => {
      req.body = userData;
      const error = new Error('Service error');
      userService.createUser.mockRejectedValue(error);

      await expect(userController.createUser(req, res)).rejects.toThrow(error);
    });
  });

  describe('updateUser', () => {
    const userId = '550e8400-e29b-41d4-a716-446655440000';
    const updateData = { status: 'INACTIVE', phone: '+256700000000' };
    const updatedUser = {
      id: userId,
      email: 'test@example.com',
      ...updateData,
      updated_at: new Date()
    };

    it('should update user', async () => {
      req.params = { id: userId };
      req.body = updateData;
      userService.updateUser.mockResolvedValue(updatedUser);

      await userController.updateUser(req, res);

      expect(userService.updateUser).toHaveBeenCalledWith(
        userId,
        updateData,
        'requester-id',
        '127.0.0.1',
        { id: 'requester-id' }
      );
      expect(sendSuccess).toHaveBeenCalledWith(
        res,
        200,
        'messages.user.update.success',
        updatedUser
      );
    });

    it('should handle missing user in request', async () => {
      req.user = undefined;
      req.params = { id: userId };
      req.body = updateData;
      userService.updateUser.mockResolvedValue(updatedUser);

      await userController.updateUser(req, res);

      expect(userService.updateUser).toHaveBeenCalledWith(
        userId,
        updateData,
        undefined,
        '127.0.0.1',
        undefined
      );
    });

    it('should handle service errors', async () => {
      req.params = { id: userId };
      req.body = updateData;
      const error = new Error('Service error');
      userService.updateUser.mockRejectedValue(error);

      await expect(userController.updateUser(req, res)).rejects.toThrow(error);
    });
  });

  describe('deleteUser', () => {
    const userId = '550e8400-e29b-41d4-a716-446655440000';

    it('should delete user', async () => {
      req.params = { id: userId };
      userService.deleteUser.mockResolvedValue(undefined);

      await userController.deleteUser(req, res);

      expect(userService.deleteUser).toHaveBeenCalledWith(
        userId,
        'requester-id',
        '127.0.0.1',
        { id: 'requester-id' }
      );
      expect(sendNoContent).toHaveBeenCalledWith(res);
    });

    it('should handle missing user in request', async () => {
      req.user = undefined;
      req.params = { id: userId };
      userService.deleteUser.mockResolvedValue(undefined);

      await userController.deleteUser(req, res);

      expect(userService.deleteUser).toHaveBeenCalledWith(
        userId,
        undefined,
        '127.0.0.1',
        undefined
      );
    });

    it('should handle service errors', async () => {
      req.params = { id: userId };
      const error = new Error('Service error');
      userService.deleteUser.mockRejectedValue(error);

      await expect(userController.deleteUser(req, res)).rejects.toThrow(error);
    });
  });

  describe('permanentDeleteUser', () => {
    const userId = '550e8400-e29b-41d4-a716-446655440000';

    it('should permanently delete user', async () => {
      req.params = { id: userId };
      userService.permanentDeleteUser.mockResolvedValue(undefined);

      await userController.permanentDeleteUser(req, res);

      expect(userService.permanentDeleteUser).toHaveBeenCalledWith(
        userId,
        'requester-id',
        '127.0.0.1',
        { id: 'requester-id' }
      );
      expect(sendNoContent).toHaveBeenCalledWith(res);
    });

    it('should handle service errors', async () => {
      req.params = { id: userId };
      const error = new Error('Service error');
      userService.permanentDeleteUser.mockRejectedValue(error);

      await expect(userController.permanentDeleteUser(req, res)).rejects.toThrow(error);
    });
  });

  describe('resetUserCredentials', () => {
    const userId = '550e8400-e29b-41d4-a716-446655440000';
    const issued = {
      user_id: 'USR-0001',
      masked_email: 'ja***@e***.com',
      delivery_status: 'SENT',
      expires_at: '2026-09-13T12:00:00.000Z'
    };

    it('passes the actor and request context and returns only the issued summary', async () => {
      const headers = {
        origin: 'https://app.example.com',
        'x-timezone': 'Africa/Kampala',
        'accept-language': 'en'
      };
      req.params = { id: userId };
      req.get = jest.fn((name) => headers[name]);
      userService.resetUserCredentials.mockResolvedValue(issued);

      await userController.resetUserCredentials(req, res);

      expect(userService.resetUserCredentials).toHaveBeenCalledWith(userId, req.user, {
        ipAddress: '127.0.0.1',
        requestContext: {
          locale: 'en',
          timezone: 'Africa/Kampala',
          origin: 'https://app.example.com'
        }
      });
      expect(sendSuccess).toHaveBeenCalledWith(
        res,
        200,
        'messages.user.reset_credentials.success',
        issued
      );
    });

    it('should handle service errors', async () => {
      req.params = { id: userId };
      const error = new Error('Service error');
      userService.resetUserCredentials.mockRejectedValue(error);

      await expect(userController.resetUserCredentials(req, res)).rejects.toThrow(error);
    });
  });

  describe('setUserPassword', () => {
    const userId = '550e8400-e29b-41d4-a716-446655440000';

    it('passes the new password and actor and returns the summary', async () => {
      const summary = { user_id: 'USR-0001', sessions_revoked: true };
      req.params = { id: userId };
      req.body = { password: 'NewStrong123!' };
      userService.setUserPassword.mockResolvedValue(summary);

      await userController.setUserPassword(req, res);

      expect(userService.setUserPassword).toHaveBeenCalledWith(userId, 'NewStrong123!', req.user, {
        ipAddress: '127.0.0.1'
      });
      expect(sendSuccess).toHaveBeenCalledWith(
        res,
        200,
        'messages.user.password_set.success',
        summary
      );
    });

    it('should handle service errors', async () => {
      req.params = { id: userId };
      req.body = { password: 'NewStrong123!' };
      const error = new Error('Service error');
      userService.setUserPassword.mockRejectedValue(error);

      await expect(userController.setUserPassword(req, res)).rejects.toThrow(error);
    });
  });
});
