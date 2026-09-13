/**
 * Role service tests
 *
 * @module tests/modules/role/services
 * Per testing.mdc: Mock repository and audit log
 */

const { HttpError } = require('@lib/errors');

// Mock repository
jest.mock('@repositories/role/role.repository');
jest.mock('@lib/authorization/platform-access-catalog', () => ({
  findActivePlatformRoleByName: jest.fn().mockResolvedValue(null)}));
jest.mock('@lib/billing/identifiers', () => ({
  ...jest.requireActual('@lib/billing/identifiers'),
  resolveIdentifierForPayload: jest.fn(async ({ value }) => value),
  resolvePublicIdentifier: jest.fn((...values) => values.find((value) => value) || null),
  resolveEntityId: jest.fn(async ({ identifier }) => identifier)}));
// Mock audit log
jest.mock('@lib/audit', () => ({
  createAuditLog: jest.fn().mockResolvedValue({})
}));
jest.mock('@lib/websocket/crud-realtime', () => ({
  publishCrudRealtimeEvent: jest.fn().mockResolvedValue(undefined)
}));
jest.mock('@lib/realtime/platform-realtime', () => ({
  publishPlatformRealtimeEvent: jest.fn().mockResolvedValue(undefined)
}));
jest.mock('@lib/authorization/assignable-access', () => {
  const actual = jest.requireActual('@lib/authorization/assignable-access');
  return {
    ...actual,
    assertPermissionIdsAssignable: jest.fn(async (ids = []) =>
      Array.isArray(ids) ? [...ids] : []
    )};
});

const roleRepository = require('@repositories/role/role.repository');
const { createAuditLog } = require('@lib/audit');
const { assertPermissionIdsAssignable } = require('@lib/authorization/assignable-access');
const {
  listRoles,
  getRoleById,
  createRole,
  updateRole,
  deleteRole,
  restoreRole,
  permanentDeleteRole
} = require('@services/role/role.service');

describe('Role Service', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    createAuditLog.mockResolvedValue({});
    assertPermissionIdsAssignable.mockImplementation(async (ids = []) =>
      Array.isArray(ids) ? [...ids] : []
    );
  });

  describe('listRoles', () => {
    it('should list roles with pagination', async () => {
      const mockRoles = [
        { id: 'role-1', name: 'Admin' },
        { id: 'role-2', name: 'User' }
      ];
      roleRepository.findMany.mockResolvedValue(mockRoles);
      roleRepository.count.mockResolvedValue(2);

      const result = await listRoles({}, 1, 20, 'name', 'asc', 'user-123', '127.0.0.1');

      expect(result.roles).toEqual(mockRoles);
      expect(result.pagination).toEqual({
        page: 1,
        limit: 20,
        total: 2,
        totalPages: 1,
        hasNextPage: false,
        hasPreviousPage: false
      });
    });

    it('should apply filters correctly', async () => {
      roleRepository.findMany.mockResolvedValue([]);
      roleRepository.count.mockResolvedValue(0);

      await listRoles({ tenant_id: 'tenant-123' }, 1, 20, 'name', 'asc', 'user-123', '127.0.0.1');

      expect(roleRepository.findMany).toHaveBeenCalledWith(
        { tenant_id: 'tenant-123' },
        0,
        20,
        { name: 'asc' }
      );
    });

    it('should apply search filter correctly', async () => {
      roleRepository.findMany.mockResolvedValue([]);
      roleRepository.count.mockResolvedValue(0);

      await listRoles({ search: 'admin' }, 1, 20, null, 'asc', 'user-123', '127.0.0.1');

      expect(roleRepository.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          OR: expect.arrayContaining([
            { name: { contains: 'admin' } },
            { description: { contains: 'admin' } }
          ])
        }),
        0,
        20,
        { created_at: 'desc' }
      );
    });
  });

  describe('getRoleById', () => {
    it('should get role by ID', async () => {
      const mockRole = {
        id: 'role-123',
        human_friendly_id: 'ROL0001',
        name: 'Admin',
        display_name: 'Admin',
        tenant_id: 'tenant-1',
        facility_id: null
      };
      roleRepository.findById.mockResolvedValue(mockRole);

      const result = await getRoleById('role-123', 'user-123', '127.0.0.1');

      expect(result).toEqual(
        expect.objectContaining({
          id: 'ROL0001',
          resource_uuid: 'role-123',
          display_id: 'ROL0001',
          name: 'Admin',
          scope: 'tenant'
        })
      );
    });

    it('should throw HttpError when role not found', async () => {
      roleRepository.findById.mockResolvedValue(null);

      await expect(getRoleById('role-123', 'user-123', '127.0.0.1'))
        .rejects.toThrow(HttpError);
    });
  });

  describe('createRole', () => {
    it('should create role and audit log', async () => {
      const mockRole = {
        id: 'role-123',
        human_friendly_id: 'ROL0001',
        name: 'New Role',
        display_name: 'New Role',
        tenant_id: 'tenant-1',
        facility_id: null
      };
      roleRepository.findMany.mockResolvedValue([]);
      roleRepository.create.mockResolvedValue(mockRole);

      const result = await createRole(
        {
          name: 'New Role',
          display_name: 'New Role',
          tenant_id: 'tenant-1'
        },
        'user-123',
        '127.0.0.1',
        { id: 'user-123', roles: ['TENANT_ADMIN'], tenant_id: 'tenant-1' }
      );

      expect(result).toEqual(
        expect.objectContaining({
          id: 'ROL0001',
          resource_uuid: 'role-123',
          display_id: 'ROL0001',
          name: 'New Role',
          scope: 'tenant'
        })
      );
      expect(createAuditLog).toHaveBeenCalledWith({
        user_id: 'user-123',
        action: 'CREATE',
        entity: 'role',
        entity_id: 'role-123',
        diff: { after: mockRole, permission_ids: [] },
        ip_address: '127.0.0.1'
      });
    });

    it('should create role with batched permission_ids', async () => {
      const mockRole = {
        id: 'role-123',
        human_friendly_id: 'ROL0001',
        name: 'New Role',
        display_name: 'New Role',
        tenant_id: 'tenant-1',
        facility_id: null
      };
      roleRepository.findMany.mockResolvedValue([]);
      roleRepository.create.mockResolvedValue(mockRole);
      assertPermissionIdsAssignable.mockResolvedValue(['perm-1', 'perm-2']);

      const result = await createRole(
        {
          name: 'New Role',
          display_name: 'New Role',
          tenant_id: 'tenant-1',
          permission_ids: ['perm-1', 'perm-2']},
        'user-123',
        '127.0.0.1',
        { id: 'user-123', roles: ['TENANT_ADMIN'], tenant_id: 'tenant-1' }
      );

      expect(result).toEqual(
        expect.objectContaining({
          id: 'ROL0001',
          resource_uuid: 'role-123',
          display_id: 'ROL0001'
        })
      );
      expect(assertPermissionIdsAssignable).toHaveBeenCalledWith(
        ['perm-1', 'perm-2'],
        expect.objectContaining({ id: 'user-123' }),
        { tenantId: 'tenant-1' }
      );
      expect(roleRepository.create).toHaveBeenCalledWith(
        expect.objectContaining({ name: 'New Role', tenant_id: 'tenant-1' }),
        ['perm-1', 'perm-2']
      );
    });

    it('should reject similar roles unless confirm_similar is true', async () => {
      roleRepository.findMany.mockResolvedValue([
        {
          id: 'role-1',
          human_friendly_id: 'ROL0001',
          tenant_id: 'tenant-1',
          facility_id: null,
          name: 'WARD CLERK',
          display_name: 'Ward Clerk',
          description: 'Front desk'
        }
      ]);

      await expect(
        createRole(
          {
            name: 'WARD CLRCK',
            display_name: 'Ward Clerck',
            description: 'Front desk',
            tenant_id: 'tenant-1'
          },
          'user-123',
          '127.0.0.1',
          { id: 'user-123', roles: ['TENANT_ADMIN'], tenant_id: 'tenant-1' }
        )
      ).rejects.toMatchObject({
        messageKey: 'errors.role.similar_exists',
        statusCode: 409
      });
      expect(roleRepository.create).not.toHaveBeenCalled();
      expect(roleRepository.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          OR: expect.arrayContaining([
            { tenant_id: 'tenant-1' },
            { tenant_id: null, facility_id: null }
          ])
        }),
        0,
        500,
        { name: 'asc' }
      );
    });

    it('should require confirm_similar for platform create when tenant peers match', async () => {
      roleRepository.findMany.mockResolvedValue([
        {
          id: 'role-org',
          human_friendly_id: 'ROL0001',
          tenant_id: 'tenant-1',
          facility_id: null,
          name: 'TESTING',
          display_name: 'Testing',
          description: null
        }
      ]);

      await expect(
        createRole(
          {
            name: 'Testing',
            display_name: 'Testing',
            tenant_id: null,
            scope: 'platform'
          },
          'user-123',
          '127.0.0.1',
          { id: 'user-123', roles: ['PLATFORM_ADMIN'] }
        )
      ).rejects.toMatchObject({
        messageKey: 'errors.role.similar_exists',
        statusCode: 409
      });
      expect(roleRepository.create).not.toHaveBeenCalled();
      expect(roleRepository.findMany).toHaveBeenCalledWith(
        {},
        0,
        500,
        { name: 'asc' }
      );
    });

    it('should prioritize identity search matches beyond the alphabetical peer window', async () => {
      const alphabetical = Array.from({ length: 500 }, (_, index) => ({
        id: `role-${index}`,
        human_friendly_id: `ROL${String(index).padStart(4, '0')}`,
        tenant_id: `tenant-${index}`,
        facility_id: null,
        name: `ALPHA ROLE ${index}`,
        display_name: `Alpha Role ${index}`,
        description: null
      }));
      roleRepository.findMany
        .mockResolvedValueOnce(alphabetical)
        .mockResolvedValueOnce([
          {
            id: 'role-testing',
            human_friendly_id: 'ROL9999',
            tenant_id: 'tenant-1',
            facility_id: null,
            name: 'TESTING',
            display_name: 'Testing',
            description: null
          }
        ]);

      await expect(
        createRole(
          {
            name: 'Testing',
            display_name: 'Testing',
            scope: 'platform'
          },
          'user-123',
          '127.0.0.1',
          { id: 'user-123', roles: ['PLATFORM_ADMIN'] }
        )
      ).rejects.toMatchObject({
        messageKey: 'errors.role.similar_exists',
        statusCode: 409
      });
      expect(roleRepository.findMany).toHaveBeenNthCalledWith(
        2,
        {
          OR: [
            { name: { contains: 'Testing' } },
            { display_name: { contains: 'Testing' } }
          ]
        },
        0,
        500,
        { name: 'asc' }
      );
      expect(roleRepository.create).not.toHaveBeenCalled();
    });

    it('should create anyway when confirm_similar is true', async () => {
      const mockRole = {
        id: 'role-123',
        human_friendly_id: 'ROL0123',
        name: 'WARD CLRCK',
        display_name: 'Ward Clerck',
        tenant_id: 'tenant-1',
        facility_id: null
      };
      roleRepository.findMany.mockResolvedValue([
        {
          id: 'role-1',
          human_friendly_id: 'ROL0001',
          tenant_id: 'tenant-1',
          facility_id: null,
          name: 'WARD CLERK',
          display_name: 'Ward Clerk',
          description: 'Front desk'
        }
      ]);
      roleRepository.create.mockResolvedValue(mockRole);

      const result = await createRole(
        {
          name: 'WARD CLRCK',
          display_name: 'Ward Clerck',
          description: 'Front desk',
          tenant_id: 'tenant-1',
          confirm_similar: true
        },
        'user-123',
        '127.0.0.1',
        { id: 'user-123', roles: ['TENANT_ADMIN'], tenant_id: 'tenant-1' }
      );

      expect(result).toEqual(
        expect.objectContaining({
          id: 'ROL0123',
          resource_uuid: 'role-123',
          display_id: 'ROL0123'
        })
      );
      expect(roleRepository.create).toHaveBeenCalledWith(
        expect.not.objectContaining({ confirm_similar: true }),
        []
      );
    });

    it('should reject tenant-wide role create for facility admins', async () => {
      await expect(
        createRole(
          {
            name: 'Ward Clerk',
            display_name: 'Ward Clerk',
            tenant_id: 'tenant-1'
          },
          'user-123',
          '127.0.0.1',
          { id: 'user-123', roles: ['FACILITY_ADMIN'], facility_id: 'facility-1' }
        )
      ).rejects.toThrow(HttpError);
      expect(roleRepository.create).not.toHaveBeenCalled();
    });

    it('should create platform-scoped role for platform admin', async () => {
      const mockRole = {
        id: 'role-platform',
        human_friendly_id: 'ROLPLAT',
        name: 'PLATFORM SUPPORT',
        display_name: 'Platform Support',
        tenant_id: null,
        facility_id: null
      };
      roleRepository.findMany.mockResolvedValue([]);
      roleRepository.create.mockResolvedValue(mockRole);

      const result = await createRole(
        {
          name: 'PLATFORM SUPPORT',
          display_name: 'Platform Support',
          tenant_id: null,
          facility_id: null
        },
        'user-123',
        '127.0.0.1',
        { id: 'user-123', roles: ['PLATFORM_ADMIN'] }
      );

      expect(result).toEqual(
        expect.objectContaining({
          id: 'ROLPLAT',
          resource_uuid: 'role-platform',
          scope: 'platform'
        })
      );
      expect(roleRepository.create).toHaveBeenCalledWith(
        expect.objectContaining({
          tenant_id: null,
          facility_id: null,
          name: 'PLATFORM SUPPORT'
        }),
        []
      );
    });

    it('should honor scope=platform even when tenant_id was injected', async () => {
      const mockRole = {
        id: 'role-platform',
        human_friendly_id: 'ROLPLAT',
        name: 'PLATFORM SUPPORT',
        display_name: 'Platform Support',
        tenant_id: null,
        facility_id: null
      };
      roleRepository.findMany.mockResolvedValue([]);
      roleRepository.create.mockResolvedValue(mockRole);

      const result = await createRole(
        {
          scope: 'platform',
          name: 'PLATFORM SUPPORT',
          display_name: 'Platform Support',
          tenant_id: 'tenant-injected',
          facility_id: null
        },
        'user-123',
        '127.0.0.1',
        {
          id: 'user-123',
          roles: [],
          permissions: ['platform:admin']
        }
      );

      expect(result).toEqual(
        expect.objectContaining({
          id: 'ROLPLAT',
          resource_uuid: 'role-platform',
          scope: 'platform'
        })
      );
      expect(roleRepository.create).toHaveBeenCalledWith(
        expect.objectContaining({
          tenant_id: null,
          facility_id: null
        }),
        []
      );
    });

    it('should reject platform-scoped role create for tenant admins', async () => {
      await expect(
        createRole(
          {
            name: 'PLATFORM SUPPORT',
            display_name: 'Platform Support',
            tenant_id: null,
            facility_id: null
          },
          'user-123',
          '127.0.0.1',
          { id: 'user-123', roles: ['TENANT_ADMIN'], tenant_id: 'tenant-1' }
        )
      ).rejects.toThrow(HttpError);
      expect(roleRepository.create).not.toHaveBeenCalled();
    });
  });

  describe('updateRole', () => {
    it('should update role and audit log', async () => {
      const before = {
        id: 'role-123',
        name: 'Old Name',
        display_name: 'Old Name',
        description: null,
        facility_id: null,
        tenant_id: 'tenant-1',
        permissions: []};
      const after = {
        id: 'role-123',
        human_friendly_id: 'ROL0001',
        name: 'New Name',
        display_name: 'Old Name',
        description: null,
        facility_id: null,
        tenant_id: 'tenant-1',
        permissions: []};
      roleRepository.findById.mockResolvedValue(before);
      roleRepository.findMany.mockResolvedValue([]);
      roleRepository.update.mockResolvedValue(after);

      const result = await updateRole(
        'role-123',
        { name: 'New Name' },
        'user-123',
        '127.0.0.1',
        { id: 'user-123', roles: ['TENANT_ADMIN'], tenant_id: 'tenant-1' }
      );

      expect(result).toEqual(
        expect.objectContaining({
          id: 'ROL0001',
          resource_uuid: 'role-123',
          display_id: 'ROL0001',
          name: 'New Name',
          scope: 'tenant'
        })
      );
      expect(createAuditLog).toHaveBeenCalledWith({
        user_id: 'user-123',
        action: 'UPDATE',
        entity: 'role',
        entity_id: 'role-123',
        diff: { before, after },
        ip_address: '127.0.0.1'
      });
    });

    it('should throw HttpError when role not found', async () => {
      roleRepository.findById.mockResolvedValue(null);

      await expect(updateRole('role-123', {}, 'user-123', '127.0.0.1'))
        .rejects.toThrow(HttpError);
    });

    it('should sync empty permission_ids to clear all grants', async () => {
      const before = {
        id: 'role-123',
        name: 'Clerk',
        display_name: 'Clerk',
        description: null,
        facility_id: null,
        tenant_id: 'tenant-1',
        permissions: [{ permission_id: 'perm-1' }]
      };
      roleRepository.findById.mockResolvedValue(before);
      roleRepository.findMany.mockResolvedValue([]);
      roleRepository.syncPermissions = jest.fn().mockResolvedValue(undefined);
      roleRepository.update.mockResolvedValue(before);

      await updateRole(
        'role-123',
        { permission_ids: [] },
        'user-123',
        '127.0.0.1',
        { id: 'user-123', roles: ['TENANT_ADMIN'], tenant_id: 'tenant-1' }
      );

      expect(assertPermissionIdsAssignable).toHaveBeenCalledWith(
        [],
        expect.any(Object),
        expect.objectContaining({ tenantId: 'tenant-1' })
      );
      expect(roleRepository.syncPermissions).toHaveBeenCalledWith('role-123', []);
    });

    it('should exclude the edited role from uniqueness peers', async () => {
      const before = {
        id: 'role-123',
        name: 'Accountant',
        display_name: 'Accountant',
        description: null,
        facility_id: null,
        tenant_id: 'tenant-1',
        permissions: []
      };
      const after = {
        ...before,
        human_friendly_id: 'ROL0001',
        description: 'Updated'
      };
      roleRepository.findById.mockResolvedValue(before);
      roleRepository.findMany.mockResolvedValue([
        before,
        {
          id: 'role-other',
          name: 'Billing Clerk',
          display_name: 'Billing Clerk',
          description: null,
          facility_id: null,
          tenant_id: 'tenant-1'
        }
      ]);
      roleRepository.update.mockResolvedValue(after);

      await updateRole(
        'role-123',
        { description: 'Updated' },
        'user-123',
        '127.0.0.1',
        { id: 'user-123', roles: ['TENANT_ADMIN'], tenant_id: 'tenant-1' }
      );

      expect(roleRepository.update).toHaveBeenCalled();
    });
  });

  describe('deleteRole', () => {
    it('should soft delete role, detach assignments, and audit log', async () => {
      const before = {
        id: 'role-123',
        name: 'Custom Clerk',
        tenant_id: 'tenant-1',
        permissions: []};
      const deleted = {
        id: 'role-123',
        name: 'Custom Clerk',
        tenant_id: 'tenant-1',
        deleted_at: new Date()};
      roleRepository.findById.mockResolvedValue(before);
      roleRepository.softDelete.mockResolvedValue({
        role: deleted,
        detached_user_assignments: 3});

      await deleteRole('role-123', 'user-123', '127.0.0.1', {
        id: 'user-123',
        roles: ['TENANT_ADMIN'],
        tenant_id: 'tenant-1'});

      expect(roleRepository.softDelete).toHaveBeenCalledWith('role-123');
      expect(createAuditLog).toHaveBeenCalledWith({
        user_id: 'user-123',
        action: 'DELETE',
        entity: 'role',
        entity_id: 'role-123',
        diff: {
          before,
          after: deleted,
          detached_user_assignments: 3},
        ip_address: '127.0.0.1'
      });
    });

    it('should throw HttpError when role not found', async () => {
      roleRepository.findById.mockResolvedValue(null);

      await expect(deleteRole('role-123', 'user-123', '127.0.0.1'))
        .rejects.toThrow(HttpError);
    });
  });

  describe('restoreRole', () => {
    it('should restore soft-deleted role and permission links', async () => {
      const deletedAt = new Date('2026-07-27T10:00:00.000Z');
      const before = {
        id: 'role-123',
        human_friendly_id: 'ROL0001',
        name: 'Custom Clerk',
        display_name: 'Custom Clerk',
        tenant_id: 'tenant-1',
        facility_id: null,
        deleted_at: deletedAt
      };
      const restored = { ...before, deleted_at: null };
      roleRepository.findById.mockResolvedValue(before);
      roleRepository.restore.mockResolvedValue({
        role: restored,
        restored_permissions: 4,
        restored_user_assignments: 2
      });

      const result = await restoreRole('role-123', 'user-123', '127.0.0.1', {
        id: 'user-123',
        roles: ['TENANT_ADMIN'],
        tenant_id: 'tenant-1'
      });

      expect(roleRepository.restore).toHaveBeenCalledWith('role-123');
      expect(result).toEqual(
        expect.objectContaining({
          id: 'ROL0001',
          resource_uuid: 'role-123',
          name: 'Custom Clerk'
        })
      );
      expect(createAuditLog).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'ROLE_RESTORED',
          entity_id: 'role-123',
          diff: expect.objectContaining({
            restored_permissions: 4,
            restored_user_assignments: 2
          })
        })
      );
    });
  });

  describe('permanentDeleteRole', () => {
    it('should permanently delete a soft-deleted role and detach all users', async () => {
      const before = {
        id: 'role-123',
        name: 'Custom Clerk',
        tenant_id: 'tenant-1',
        deleted_at: new Date()
      };
      roleRepository.findById.mockResolvedValue(before);
      roleRepository.permanentDelete.mockResolvedValue({
        removed_user_ids: ['user-a', 'user-b'],
        removed_user_assignments: 2,
        removed_permissions: 5
      });

      await permanentDeleteRole('role-123', 'user-123', '127.0.0.1', {
        id: 'user-123',
        roles: ['TENANT_ADMIN'],
        tenant_id: 'tenant-1'
      });

      expect(roleRepository.permanentDelete).toHaveBeenCalledWith('role-123');
      expect(createAuditLog).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'ROLE_PERMANENTLY_DELETED',
          entity_id: 'role-123',
          diff: expect.objectContaining({
            irreversible: true,
            removed_user_ids: ['user-a', 'user-b'],
            removed_user_assignments: 2,
            removed_permissions: 5
          })
        })
      );
    });

    it('should require soft-delete before permanent delete', async () => {
      roleRepository.findById.mockResolvedValue({
        id: 'role-123',
        name: 'Custom Clerk',
        tenant_id: 'tenant-1',
        deleted_at: null
      });

      await expect(
        permanentDeleteRole('role-123', 'user-123', '127.0.0.1', {
          id: 'user-123',
          roles: ['TENANT_ADMIN'],
          tenant_id: 'tenant-1'
        })
      ).rejects.toThrow(HttpError);
      expect(roleRepository.permanentDelete).not.toHaveBeenCalled();
    });
  });
});
