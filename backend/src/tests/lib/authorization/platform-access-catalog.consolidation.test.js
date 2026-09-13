/**
 * @jest-environment node
 */

jest.mock('../../../prisma/tenant-guard', () => ({
  runWithoutTenantGuard: jest.fn(async (callback) => callback()),
}));

jest.mock('@lib/database/foreign-key-references', () => ({
  listForeignKeyReferences: jest.fn(),
  countReferencingRows: jest.fn(),
}));

jest.mock('@prisma/client', () => {
  const linkDelegate = () => ({
    findMany: jest.fn(),
    findFirst: jest.fn(),
    update: jest.fn(),
    delete: jest.fn(),
    deleteMany: jest.fn(),
    count: jest.fn(),
  });
  const prismaMock = {
    $transaction: jest.fn(async (callback) => callback(prismaMock)),
    role: { findMany: jest.fn(), delete: jest.fn() },
    permission: { findMany: jest.fn(), delete: jest.fn() },
    user_role: linkDelegate(),
    role_permission: linkDelegate(),
    user_permission: linkDelegate(),
    api_key_permission: linkDelegate(),
  };
  return prismaMock;
});

const prisma = require('@prisma/client');
const foreignKeys = require('@lib/database/foreign-key-references');
const { consolidateTenantCatalogDuplicates } = require('@lib/authorization/platform-access-catalog');

const grants = (...names) => names.map((name) => ({ permission: { name } }));

const platformTenantAdmin = {
  id: 'platform-tenant-admin',
  name: 'TENANT_ADMIN',
  tenant_id: null,
  facility_id: null,
  permissions: grants('tenant:admin', 'hr:write'),
};

const arrangeCatalog = ({
  platformRoles = [platformTenantAdmin],
  platformPermissions = [],
  tenantRoles = [],
  tenantPermissions = [],
} = {}) => {
  prisma.role.findMany.mockImplementation(({ where }) =>
    Promise.resolve(where.tenant_id === null ? platformRoles : tenantRoles)
  );
  prisma.permission.findMany.mockImplementation(({ where }) =>
    Promise.resolve(where.tenant_id === null ? platformPermissions : tenantPermissions)
  );
};

describe('consolidateTenantCatalogDuplicates', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    foreignKeys.listForeignKeyReferences.mockImplementation((client, table) =>
      Promise.resolve(
        table === 'role'
          ? [
              { table: 'role_permission', column: 'role_id' },
              { table: 'user_role', column: 'role_id' },
            ]
          : [
              { table: 'api_key_permission', column: 'permission_id' },
              { table: 'role_permission', column: 'permission_id' },
              { table: 'user_permission', column: 'permission_id' },
            ]
      )
    );
    foreignKeys.countReferencingRows.mockResolvedValue(0);
    for (const table of ['user_role', 'role_permission', 'user_permission', 'api_key_permission']) {
      prisma[table].findMany.mockResolvedValue([]);
      prisma[table].findFirst.mockResolvedValue(null);
      prisma[table].deleteMany.mockResolvedValue({ count: 0 });
      prisma[table].count.mockResolvedValue(0);
    }
  });

  it('moves assignments from a tenant copy to the platform role and deletes the copy', async () => {
    arrangeCatalog({
      tenantRoles: [
        {
          id: 'tenant-copy',
          name: 'tenant_admin ',
          tenant_id: 'tenant-1',
          facility_id: 'facility-1',
          permissions: [],
          tenant: { name: 'Fairbanks' },
        },
      ],
    });
    prisma.user_role.findMany.mockResolvedValue([
      { id: 'ur-1', user_id: 'user-1', tenant_id: 'tenant-1', facility_id: 'facility-1', deleted_at: null },
    ]);
    prisma.role_permission.deleteMany.mockResolvedValue({ count: 0 });

    const result = await consolidateTenantCatalogDuplicates();

    expect(prisma.user_role.findFirst).toHaveBeenCalledWith({
      where: {
        user_id: 'user-1',
        role_id: 'platform-tenant-admin',
        tenant_id: 'tenant-1',
        facility_id: 'facility-1',
      },
    });
    expect(prisma.user_role.update).toHaveBeenCalledWith({
      where: { id: 'ur-1' },
      data: { role_id: 'platform-tenant-admin' },
    });
    expect(prisma.role.delete).toHaveBeenCalledWith({ where: { id: 'tenant-copy' } });
    expect(result).toMatchObject({
      dry_run: false,
      tenants_affected: ['Fairbanks'],
      roles: { copies: 1, merged: 1, remapped_user_roles: 1, removed_user_roles: 0, needs_review: [] },
    });
  });

  it('keeps the platform assignment when the user already has it', async () => {
    arrangeCatalog({
      tenantRoles: [
        { id: 'tenant-copy', name: 'TENANT_ADMIN', tenant_id: 'tenant-1', facility_id: null, permissions: [] },
      ],
    });
    prisma.user_role.findMany.mockResolvedValue([
      { id: 'ur-copy', user_id: 'user-1', tenant_id: 'tenant-1', facility_id: null, deleted_at: null },
    ]);
    prisma.user_role.findFirst.mockResolvedValue({ id: 'ur-platform', deleted_at: new Date() });

    const result = await consolidateTenantCatalogDuplicates();

    expect(prisma.user_role.update).toHaveBeenCalledWith({
      where: { id: 'ur-platform' },
      data: { deleted_at: null },
    });
    expect(prisma.user_role.delete).toHaveBeenCalledWith({ where: { id: 'ur-copy' } });
    expect(result.roles).toMatchObject({ restored_user_roles: 1, removed_user_roles: 1, remapped_user_roles: 0 });
  });

  it('reports a copy that grants more than the platform role instead of merging it', async () => {
    arrangeCatalog({
      tenantRoles: [
        {
          id: 'tenant-extension',
          name: 'TENANT_ADMIN',
          tenant_id: 'tenant-1',
          facility_id: null,
          permissions: grants('tenant:admin', 'billing:write'),
          tenant: { name: 'Fairbanks' },
        },
      ],
    });

    const result = await consolidateTenantCatalogDuplicates();

    expect(prisma.role.delete).not.toHaveBeenCalled();
    expect(prisma.user_role.update).not.toHaveBeenCalled();
    expect(result.roles.merged).toBe(0);
    expect(result.roles.needs_review).toEqual([
      expect.objectContaining({
        role_id: 'tenant-extension',
        reason: 'extends_platform_role',
        extra_permissions: ['billing:write'],
      }),
    ]);
  });

  it('reports a copy referenced by tables it cannot remap', async () => {
    arrangeCatalog({
      tenantRoles: [
        { id: 'tenant-copy', name: 'TENANT_ADMIN', tenant_id: 'tenant-1', facility_id: null, permissions: [] },
      ],
    });
    foreignKeys.listForeignKeyReferences.mockResolvedValue([
      { table: 'user_role', column: 'role_id' },
      { table: 'staff_position', column: 'default_role_id' },
    ]);
    foreignKeys.countReferencingRows.mockResolvedValue(2);

    const result = await consolidateTenantCatalogDuplicates();

    expect(prisma.role.delete).not.toHaveBeenCalled();
    expect(result.roles.needs_review).toEqual([
      expect.objectContaining({ reason: 'referenced_elsewhere', tables: ['staff_position'] }),
    ]);
  });

  it('leaves custom tenant roles alone', async () => {
    arrangeCatalog({
      tenantRoles: [
        { id: 'custom', name: 'WARD_CLERK_PLUS', tenant_id: 'tenant-1', facility_id: null, permissions: [] },
      ],
    });

    const result = await consolidateTenantCatalogDuplicates();

    expect(prisma.role.delete).not.toHaveBeenCalled();
    expect(result.roles.copies).toBe(0);
  });

  it('moves tenant permission links to the platform permission and deletes the copy', async () => {
    arrangeCatalog({
      platformPermissions: [{ id: 'platform-clinical-read', name: 'clinical:read', tenant_id: null }],
      tenantPermissions: [
        { id: 'tenant-clinical-read', name: 'clinical:read', tenant_id: 'tenant-1', tenant: { name: 'DemoCare' } },
      ],
    });
    prisma.role_permission.findMany.mockResolvedValue([
      { id: 'rp-1', role_id: 'custom-role', permission_id: 'tenant-clinical-read', deleted_at: null },
    ]);
    prisma.user_permission.findMany.mockResolvedValue([
      { id: 'up-1', user_id: 'user-1', permission_id: 'tenant-clinical-read', deleted_at: null },
    ]);
    prisma.user_permission.findFirst.mockResolvedValue({ id: 'up-platform', deleted_at: null });

    const result = await consolidateTenantCatalogDuplicates();

    expect(prisma.role_permission.update).toHaveBeenCalledWith({
      where: { id: 'rp-1' },
      data: { permission_id: 'platform-clinical-read' },
    });
    expect(prisma.user_permission.delete).toHaveBeenCalledWith({ where: { id: 'up-1' } });
    expect(prisma.permission.delete).toHaveBeenCalledWith({ where: { id: 'tenant-clinical-read' } });
    expect(result.permissions).toMatchObject({ copies: 1, merged: 1, remapped_links: 1, removed_links: 1 });
  });

  it('writes nothing on a dry run', async () => {
    arrangeCatalog({
      platformPermissions: [{ id: 'platform-clinical-read', name: 'clinical:read', tenant_id: null }],
      tenantRoles: [
        { id: 'tenant-copy', name: 'TENANT_ADMIN', tenant_id: 'tenant-1', facility_id: null, permissions: [] },
      ],
      tenantPermissions: [
        { id: 'tenant-clinical-read', name: 'clinical:read', tenant_id: 'tenant-1' },
      ],
    });
    prisma.user_role.count.mockResolvedValue(3);

    const result = await consolidateTenantCatalogDuplicates({ dryRun: true });

    expect(prisma.$transaction).not.toHaveBeenCalled();
    expect(prisma.role.delete).not.toHaveBeenCalled();
    expect(prisma.permission.delete).not.toHaveBeenCalled();
    expect(result).toMatchObject({
      dry_run: true,
      roles: { merged: 1, remapped_user_roles: 3 },
      permissions: { merged: 1 },
    });
  });
});
