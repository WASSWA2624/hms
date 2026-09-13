jest.mock('@repositories/role/role.repository');
jest.mock('@lib/authorization/platform-access-catalog', () => ({
  findActivePlatformRoleByName: jest.fn().mockResolvedValue(null)}));
jest.mock('@lib/billing/clinical-request-billing', () => ({
  upsertClinicalRequestBilling: jest.fn(),
  receiveClinicalRequestPayment: jest.fn(),
  adjustClinicalRequestBilling: jest.fn(),
}));
jest.mock('@lib/billing/identifiers', () => ({
  ...jest.requireActual('@lib/billing/identifiers'),
  resolveIdentifierForPayload: jest.fn(async ({ value }) => value),
  resolvePublicIdentifier: jest.fn((...values) => values.find((value) => value) || null),
  resolveEntityId: jest.fn(async ({ identifier }) => identifier),
}));
jest.mock('@lib/audit', () => ({
  createAuditLog: jest.fn().mockResolvedValue({}),
}));
jest.mock('@lib/websocket/crud-realtime', () => ({
  publishCrudRealtimeEvent: jest.fn().mockResolvedValue(undefined),
}));
jest.mock('@lib/realtime/platform-realtime', () => ({
  publishPlatformRealtimeEvent: jest.fn().mockResolvedValue(undefined),
}));
jest.mock('@lib/authorization/assignable-access', () => {
  const actual = jest.requireActual('@lib/authorization/assignable-access');
  return {
    ...actual,
    assertPermissionIdsAssignable: jest.fn(async (ids = []) =>
      Array.isArray(ids) ? [...ids] : []
    ),
  };
});

const roleRepository = require('@repositories/role/role.repository');
const clinicalRequestBilling = require('@lib/billing/clinical-request-billing');
const { assertPermissionIdsAssignable } = require('@lib/authorization/assignable-access');
const {
  createRole,
  updateRole,
  deleteRole,
} = require('@services/role/role.service');

describe('role service billing-sections scan (Roles tab)', () => {
  const tenantActor = {
    id: 'user-123',
    roles: ['TENANT_ADMIN'],
    tenant_id: 'tenant-1',
    permissions: ['tenant:admin'],
  };

  const billingPermissionIds = ['perm-billing-read', 'perm-billing-write'];

  beforeEach(() => {
    jest.clearAllMocks();
    roleRepository.findMany.mockResolvedValue([]);
    assertPermissionIdsAssignable.mockImplementation(async (ids = []) =>
      Array.isArray(ids) ? [...ids] : []
    );
  });

  it('createRole with billing permission_ids does not touch patient billing ledger', async () => {
    const mockRole = {
      id: 'role-123',
      human_friendly_id: 'ROL0001',
      name: 'BILLING CLERK',
      display_name: 'Billing Clerk',
      tenant_id: 'tenant-1',
      facility_id: null,
    };
    roleRepository.create.mockResolvedValue(mockRole);

    const result = await createRole(
      {
        name: 'BILLING CLERK',
        display_name: 'Billing Clerk',
        tenant_id: 'tenant-1',
        permission_ids: billingPermissionIds,
      },
      'user-123',
      '127.0.0.1',
      tenantActor
    );

    expect(result).toEqual(
      expect.objectContaining({
        id: 'ROL0001',
        resource_uuid: 'role-123',
      })
    );
    expect(roleRepository.create).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'BILLING CLERK' }),
      billingPermissionIds
    );
    expect(clinicalRequestBilling.upsertClinicalRequestBilling).not.toHaveBeenCalled();
    expect(clinicalRequestBilling.receiveClinicalRequestPayment).not.toHaveBeenCalled();
    expect(clinicalRequestBilling.adjustClinicalRequestBilling).not.toHaveBeenCalled();
  });

  it('updateRole permission sync does not mutate billing ledger rows', async () => {
    const before = {
      id: 'role-123',
      human_friendly_id: 'ROL0001',
      name: 'CUSTOM CLERK',
      display_name: 'Custom Clerk',
      tenant_id: 'tenant-1',
      facility_id: null,
      permissions: [],
    };
    const after = { ...before, display_name: 'Senior Custom Clerk' };
    roleRepository.findById.mockResolvedValue(before);
    roleRepository.findMany.mockResolvedValue([]);
    roleRepository.update.mockResolvedValue(after);
    roleRepository.syncPermissions.mockResolvedValue(undefined);

    await updateRole(
      'role-123',
      {
        display_name: 'Senior Doctor',
        permission_ids: billingPermissionIds,
      },
      'user-123',
      '127.0.0.1',
      tenantActor
    );

    expect(roleRepository.syncPermissions).toHaveBeenCalledWith(
      'role-123',
      billingPermissionIds
    );
    expect(clinicalRequestBilling.upsertClinicalRequestBilling).not.toHaveBeenCalled();
    expect(clinicalRequestBilling.receiveClinicalRequestPayment).not.toHaveBeenCalled();
    expect(clinicalRequestBilling.adjustClinicalRequestBilling).not.toHaveBeenCalled();
  });

  it('createRole is idempotent on billing bypass — replay does not double-post', async () => {
    const mockRole = {
      id: 'role-123',
      human_friendly_id: 'ROL0001',
      name: 'CASHIER',
      display_name: 'Cashier',
      tenant_id: 'tenant-1',
      facility_id: null,
    };
    roleRepository.create.mockResolvedValue(mockRole);

    const payload = {
      name: 'CASHIER',
      display_name: 'Cashier',
      tenant_id: 'tenant-1',
      permission_ids: billingPermissionIds,
    };

    await createRole(payload, 'user-123', '127.0.0.1', tenantActor);
    await createRole(payload, 'user-123', '127.0.0.1', tenantActor);

    expect(roleRepository.create).toHaveBeenCalledTimes(2);
    expect(clinicalRequestBilling.upsertClinicalRequestBilling).not.toHaveBeenCalled();
    expect(clinicalRequestBilling.receiveClinicalRequestPayment).not.toHaveBeenCalled();
  });

  it('deleteRole does not invoke billing settlement paths', async () => {
    const before = {
      id: 'role-123',
      human_friendly_id: 'ROL0001',
      name: 'CUSTOM',
      display_name: 'Custom',
      tenant_id: 'tenant-1',
      facility_id: null,
    };
    roleRepository.findById.mockResolvedValue(before);
    roleRepository.softDelete.mockResolvedValue({
      role: { ...before, deleted_at: new Date().toISOString() },
      detached_user_assignments: 0,
    });

    await deleteRole('role-123', 'user-123', '127.0.0.1', tenantActor);

    expect(roleRepository.softDelete).toHaveBeenCalledWith('role-123');
    expect(clinicalRequestBilling.receiveClinicalRequestPayment).not.toHaveBeenCalled();
    expect(clinicalRequestBilling.adjustClinicalRequestBilling).not.toHaveBeenCalled();
  });

  it('serializes role entity without orphan payment fields', async () => {
    const mockRole = {
      id: 'role-123',
      human_friendly_id: 'ROL0001',
      name: 'NURSE',
      display_name: 'Nurse',
      tenant_id: 'tenant-1',
      facility_id: null,
    };
    roleRepository.create.mockResolvedValue(mockRole);

    const result = await createRole(
      {
        name: 'NURSE',
        display_name: 'Nurse',
        tenant_id: 'tenant-1',
      },
      'user-123',
      '127.0.0.1',
      tenantActor
    );

    expect(result).not.toHaveProperty('payment_status');
    expect(result).not.toHaveProperty('balance');
    expect(result).not.toHaveProperty('amount');
    expect(result).not.toHaveProperty('paid');
  });

  it('unauthorized clinical actor cannot create role or collect/adjust billing', async () => {
    await expect(
      createRole(
        {
          name: 'CASHIER',
          display_name: 'Cashier',
          tenant_id: 'tenant-1',
          permission_ids: billingPermissionIds,
        },
        'user-clinical',
        '127.0.0.1',
        {
          id: 'user-clinical',
          roles: ['DOCTOR'],
          tenant_id: 'tenant-1',
          permissions: ['clinical:read'],
        }
      )
    ).rejects.toMatchObject({ statusCode: 403 });

    expect(roleRepository.create).not.toHaveBeenCalled();
    expect(clinicalRequestBilling.upsertClinicalRequestBilling).not.toHaveBeenCalled();
    expect(clinicalRequestBilling.receiveClinicalRequestPayment).not.toHaveBeenCalled();
    expect(clinicalRequestBilling.adjustClinicalRequestBilling).not.toHaveBeenCalled();
  });

  it('unauthorized clinical actor cannot update role above ceiling or settle billing', async () => {
    roleRepository.findById.mockResolvedValue({
      id: 'role-123',
      human_friendly_id: 'ROL0001',
      name: 'CUSTOM CLERK',
      display_name: 'Custom Clerk',
      tenant_id: 'tenant-1',
      facility_id: null,
      permissions: [
        {
          permission: {
            id: 'perm-billing-write',
            name: 'billing:write',
          },
        },
      ],
    });

    await expect(
      updateRole(
        'role-123',
        { display_name: 'Senior Custom Clerk' },
        'user-clinical',
        '127.0.0.1',
        {
          id: 'user-clinical',
          roles: ['DOCTOR'],
          tenant_id: 'tenant-1',
          permissions: ['clinical:read'],
        }
      )
    ).rejects.toMatchObject({ statusCode: 403 });

    expect(roleRepository.update).not.toHaveBeenCalled();
    expect(roleRepository.syncPermissions).not.toHaveBeenCalled();
    expect(clinicalRequestBilling.receiveClinicalRequestPayment).not.toHaveBeenCalled();
    expect(clinicalRequestBilling.adjustClinicalRequestBilling).not.toHaveBeenCalled();
  });
});
