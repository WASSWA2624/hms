/**
 * Permission service tests
 *
 * @module tests/modules/permission/services
 * Per testing.mdc: Mock repository and audit log
 */

const { HttpError } = require('@lib/errors');

jest.mock('@repositories/permission/permission.repository');
jest.mock('@lib/authorization/platform-access-catalog', () => ({
  findActivePlatformPermissionByName: jest.fn().mockResolvedValue(null)}));
jest.mock('@lib/audit', () => ({
  createAuditLog: jest.fn().mockResolvedValue({})
}));

const permissionRepository = require('@repositories/permission/permission.repository');
const { createAuditLog } = require('@lib/audit');
const {
  listPermissions,
  getPermissionById,
  createPermission,
  updatePermission,
  deletePermission
} = require('@services/permission/permission.service');

describe('Permission Service', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    createAuditLog.mockResolvedValue({});
  });

  describe('listPermissions', () => {
    it('should list permissions with pagination', async () => {
      const mockPermissions = [{ id: 'permission-1', name: 'view_users' }];
      permissionRepository.findMany.mockResolvedValue(mockPermissions);
      permissionRepository.count.mockResolvedValue(1);

      const result = await listPermissions({}, 1, 20, 'name', 'asc', 'user-123', '127.0.0.1');

      expect(result.permissions).toEqual(mockPermissions);
      expect(result.pagination.total).toBe(1);
    });
  });

  describe('getPermissionById', () => {
    it('should get permission by ID', async () => {
      const mockPermission = { id: 'permission-123', name: 'view_users' };
      permissionRepository.findById.mockResolvedValue(mockPermission);

      const result = await getPermissionById('permission-123', 'user-123', '127.0.0.1');

      expect(result).toEqual(mockPermission);
    });

    it('should throw HttpError when not found', async () => {
      permissionRepository.findById.mockResolvedValue(null);

      await expect(getPermissionById('permission-123', 'user-123', '127.0.0.1'))
        .rejects.toThrow(HttpError);
    });
  });

  describe('createPermission', () => {
    it('should create permission and audit log', async () => {
      const mockPermission = { id: 'permission-123', name: 'view_users' };
      permissionRepository.create.mockResolvedValue(mockPermission);

      const result = await createPermission({ name: 'view_users' }, 'user-123', '127.0.0.1');

      expect(result).toEqual(mockPermission);
      expect(createAuditLog).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'CREATE',
          entity: 'permission'
        })
      );
    });
  });

  describe('updatePermission', () => {
    it('should update permission and audit log', async () => {
      const before = { id: 'permission-123', name: 'old_name' };
      const after = { id: 'permission-123', name: 'new_name' };
      permissionRepository.findById.mockResolvedValue(before);
      permissionRepository.update.mockResolvedValue(after);

      const result = await updatePermission('permission-123', { name: 'new_name' }, 'user-123', '127.0.0.1');

      expect(result).toEqual(after);
      expect(createAuditLog).toHaveBeenCalled();
    });

    it('should throw HttpError when not found', async () => {
      permissionRepository.findById.mockResolvedValue(null);

      await expect(updatePermission('permission-123', {}, 'user-123', '127.0.0.1'))
        .rejects.toThrow(HttpError);
    });
  });

  describe('deletePermission', () => {
    it('should soft delete permission and audit log', async () => {
      const before = { id: 'permission-123', name: 'view_users' };
      permissionRepository.findById.mockResolvedValue(before);
      permissionRepository.softDelete.mockResolvedValue({});

      await deletePermission('permission-123', 'user-123', '127.0.0.1');

      expect(permissionRepository.softDelete).toHaveBeenCalledWith('permission-123');
      expect(createAuditLog).toHaveBeenCalled();
    });
  });
});
