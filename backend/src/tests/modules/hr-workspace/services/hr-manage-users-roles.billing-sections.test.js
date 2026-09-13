/**
 * HR Manage users and roles (`/hr?section=access`) billing-sections scan.
 *
 * Access mutations (user / role / permission / user-role / role-permission /
 * staff-profile onboarding with compensation & consultation fee catalog)
 * must not post to patient Billing ledgers. Patient charges remain on
 * clinical-request Billing when services are later ordered.
 */

jest.mock('@repositories/user/user.repository');
jest.mock('@repositories/role/role.repository');
jest.mock('@repositories/permission/permission.repository');
jest.mock('@repositories/user-role/user-role.repository');
jest.mock('@repositories/role-permission/role-permission.repository');
jest.mock('@repositories/staff-profile/staff-profile.repository');
jest.mock('@lib/authorization/platform-access-catalog', () => ({
  findActivePlatformRoleByName: jest.fn().mockResolvedValue(null),
  findActivePlatformPermissionByName: jest.fn().mockResolvedValue(null),
}));
jest.mock('@lib/audit', () => ({
  createAuditLog: jest.fn().mockResolvedValue({}),
}));
jest.mock('@lib/crypto', () => ({
  hashPassword: jest.fn().mockResolvedValue('$2b$10$hashedpasswordplaceholder'),
}));
jest.mock('@lib/billing/clinical-request-billing', () => ({
  upsertClinicalRequestBilling: jest.fn(),
  receiveClinicalRequestPayment: jest.fn(),
  adjustClinicalRequestBilling: jest.fn(),
  persistClinicalRequestBilling: jest.fn(),
}));
jest.mock('@services/billing/billing.service', () => ({
  receivePayment: jest.fn(),
  requestAdjustment: jest.fn(),
  reconcilePayment: jest.fn(),
  createInvoice: jest.fn(),
}));
jest.mock('@lib/billing/identifiers', () => ({
  ...jest.requireActual('@lib/billing/identifiers'),
  sanitizeIdentifier: jest.fn((value) =>
    value == null ? '' : String(value).trim()
  ),
  resolveIdentifierForPayload: jest.fn(async ({ value }) => value),
  resolvePublicIdentifier: jest.fn((...values) => values.find((value) => value) || null),
  resolveEntityId: jest.fn(async ({ identifier }) => identifier),
  resolveIdentifierForFilter: jest.fn(async ({ value }) => value || null),
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
      (Array.isArray(ids) ? [...ids] : [])
    ),
    assertRoleIdAssignable: jest.fn().mockResolvedValue(undefined),
    assertPermissionIdAssignable: jest.fn().mockResolvedValue(undefined),
    assertPermissionIdHasRequiredRead: jest.fn().mockResolvedValue(undefined),
  };
});
jest.mock('@lib/hr/staff-number', () => ({
  generateStaffNumber: jest.fn().mockResolvedValue({ staff_number: 'STF-001' }),
}));
jest.mock('@lib/hr/staff-department-sync', () => ({
  syncStaffProfilePrimaryDepartment: jest.fn().mockResolvedValue(undefined),
}));
jest.mock('@prisma/client', () => ({
  user: { findFirst: jest.fn() },
  staff_position: {
    findFirst: jest.fn(),
    create: jest.fn(),
  },
  $transaction: jest.fn((callback) =>
    callback({
      staff_compensation: {
        updateMany: jest.fn().mockResolvedValue({ count: 0 }),
        create: jest.fn().mockResolvedValue({ id: 'comp-1' }),
      },
    })
  ),
}));

const userRepository = require('@repositories/user/user.repository');
const roleRepository = require('@repositories/role/role.repository');
const permissionRepository = require('@repositories/permission/permission.repository');
const userRoleRepository = require('@repositories/user-role/user-role.repository');
const rolePermissionRepository = require('@repositories/role-permission/role-permission.repository');
const staffProfileRepository = require('@repositories/staff-profile/staff-profile.repository');
const clinicalRequestBilling = require('@lib/billing/clinical-request-billing');
const billingService = require('@services/billing/billing.service');
const prisma = require('@prisma/client');
const { hashPassword } = require('@lib/crypto');
const { assertPermissionIdsAssignable } = require('@lib/authorization/assignable-access');

const userService = require('@services/user/user.service');
const { createRole, updateRole } = require('@services/role/role.service');
const { createPermission } = require('@services/permission/permission.service');
const { createUserRole, deleteUserRole } = require('@services/user-role/user-role.service');
const {
  createRolePermission,
} = require('@services/role-permission/role-permission.service');
const staffProfileService = require('@services/staff-profile/staff-profile.service');

function expectNoPatientBillingPosts() {
  expect(clinicalRequestBilling.upsertClinicalRequestBilling).not.toHaveBeenCalled();
  expect(clinicalRequestBilling.receiveClinicalRequestPayment).not.toHaveBeenCalled();
  expect(clinicalRequestBilling.adjustClinicalRequestBilling).not.toHaveBeenCalled();
  expect(clinicalRequestBilling.persistClinicalRequestBilling).not.toHaveBeenCalled();
  expect(billingService.receivePayment).not.toHaveBeenCalled();
  expect(billingService.createInvoice).not.toHaveBeenCalled();
  expect(billingService.requestAdjustment).not.toHaveBeenCalled();
  expect(billingService.reconcilePayment).not.toHaveBeenCalled();
}

describe('HR manage-users-roles billing-sections scan', () => {
  const tenantId = '550e8400-e29b-41d4-a716-446655440000';
  const userId = '550e8400-e29b-41d4-a716-446655440001';
  const roleId = '550e8400-e29b-41d4-a716-446655440002';
  const permissionId = '550e8400-e29b-41d4-a716-446655440003';
  const tenantActor = {
    id: 'actor-1',
    roles: ['TENANT_ADMIN'],
    tenant_id: tenantId,
    permissions: ['tenant:admin', 'hr:write'],
  };

  beforeEach(() => {
    jest.clearAllMocks();
    hashPassword.mockResolvedValue('$2b$10$hashedpasswordplaceholder');
    assertPermissionIdsAssignable.mockImplementation(async (ids = []) =>
      (Array.isArray(ids) ? [...ids] : [])
    );
    prisma.user.findFirst.mockResolvedValue({ id: userId });
    prisma.staff_position.findFirst.mockResolvedValue(null);
    prisma.staff_position.create.mockResolvedValue({ id: 'pos-1', name: 'Nurse' });
  });

  it('updateUser (access edit) does not post to patient Billing', async () => {
    const before = {
      id: userId,
      tenant_id: tenantId,
      email: 'hr.admin@example.com',
      position_title: 'Nurse',
      status: 'ACTIVE',
      profile: { first_name: 'HR', last_name: 'Admin' },
    };
    userRepository.findById.mockResolvedValue(before);
    userRepository.update.mockResolvedValue({
      ...before,
      position_title: 'Charge Nurse',
      status: 'SUSPENDED',
    });

    const result = await userService.updateUser(
      userId,
      { position_title: 'Charge Nurse', status: 'SUSPENDED' },
      'actor-1',
      '127.0.0.1'
    );

    expect(result.position_title).toBe('Charge Nurse');
    expectNoPatientBillingPosts();
  });

  it('updateUser replay is idempotent without Billing side effects', async () => {
    const before = {
      id: userId,
      tenant_id: tenantId,
      email: 'hr.admin@example.com',
      status: 'ACTIVE',
      profile: { first_name: 'HR', last_name: 'Admin' },
    };
    userRepository.findById.mockResolvedValue(before);
    userRepository.update.mockResolvedValue({ ...before, status: 'INACTIVE' });

    await userService.updateUser(userId, { status: 'INACTIVE' }, 'actor-1', '127.0.0.1');
    await userService.updateUser(userId, { status: 'INACTIVE' }, 'actor-1', '127.0.0.1');

    expect(userRepository.update).toHaveBeenCalledTimes(2);
    expectNoPatientBillingPosts();
  });

  it('createRole / updateRole with billing permission_ids do not touch ledgers', async () => {
    const billingPermissionIds = ['perm-billing-read', 'perm-billing-write'];
    const mockRole = {
      id: roleId,
      human_friendly_id: 'ROL0001',
      name: 'BILLING CLERK',
      display_name: 'Billing Clerk',
      tenant_id: tenantId,
      facility_id: null,
    };
    roleRepository.findMany.mockResolvedValue([]);
    roleRepository.create.mockResolvedValue(mockRole);
    roleRepository.findById.mockResolvedValue({ ...mockRole, permissions: [] });
    roleRepository.update.mockResolvedValue(mockRole);
    roleRepository.syncPermissions.mockResolvedValue(undefined);

    await createRole(
      {
        name: 'BILLING CLERK',
        display_name: 'Billing Clerk',
        tenant_id: tenantId,
        permission_ids: billingPermissionIds,
      },
      'actor-1',
      '127.0.0.1',
      tenantActor
    );
    await updateRole(
      roleId,
      { permission_ids: billingPermissionIds },
      'actor-1',
      '127.0.0.1',
      tenantActor
    );

    expect(roleRepository.syncPermissions).toHaveBeenCalledWith(roleId, billingPermissionIds);
    expectNoPatientBillingPosts();
  });

  it('createPermission for billing:write does not create invoice rows', async () => {
    const created = {
      id: permissionId,
      human_friendly_id: 'PRM0099',
      name: 'billing:write',
      description: 'Billing write',
      tenant_id: tenantId,
    };
    permissionRepository.create.mockResolvedValue(created);

    const result = await createPermission(
      {
        tenant_id: tenantId,
        name: 'billing:write',
        description: 'Billing write',
      },
      'actor-1',
      '127.0.0.1'
    );

    expect(result).toEqual(expect.objectContaining({ name: 'billing:write' }));
    expectNoPatientBillingPosts();
  });

  it('createUserRole / deleteUserRole do not settle or reverse Billing', async () => {
    const assignment = {
      id: 'ur-1',
      user_id: userId,
      role_id: roleId,
      tenant_id: tenantId,
    };
    userRoleRepository.create.mockResolvedValue(assignment);
    userRoleRepository.findById.mockResolvedValue(assignment);
    userRoleRepository.softDelete.mockResolvedValue(assignment);

    await createUserRole(
      { user_id: userId, role_id: roleId, tenant_id: tenantId },
      'actor-1',
      '127.0.0.1'
    );
    await deleteUserRole('ur-1', 'actor-1', '127.0.0.1');

    expect(userRoleRepository.softDelete).toHaveBeenCalledWith('ur-1');
    expectNoPatientBillingPosts();
  });

  it('createRolePermission (assign billing:*) does not mutate patient balances', async () => {
    const link = {
      id: 'rp-1',
      role_id: roleId,
      permission_id: permissionId,
    };
    rolePermissionRepository.findMany.mockResolvedValue([]);
    rolePermissionRepository.create.mockResolvedValue(link);

    await createRolePermission(
      { role_id: roleId, permission_id: permissionId },
      'actor-1',
      '127.0.0.1',
      tenantActor
    );

    expectNoPatientBillingPosts();
  });

  it('createStaffProfile with compensation + consultation_fee is catalog-only (no Billing post)', async () => {
    const createdProfile = {
      id: 'staff-1',
      human_friendly_id: 'STF0001',
      tenant_id: tenantId,
      user_id: userId,
      staff_number: 'STF-001',
      position: 'Medical Officer',
      practitioner_type: 'SPECIALIST',
      consultation_fee: 50,
      consultation_currency: 'USD',
    };
    staffProfileRepository.create.mockResolvedValue(createdProfile);
    staffProfileRepository.findById.mockResolvedValue(createdProfile);

    const result = await staffProfileService.createStaffProfile(
      {
        tenant_id: tenantId,
        user_id: userId,
        staff_number: 'STF-001',
        position: 'Medical Officer',
        practitioner_type: 'SPECIALIST',
        consultation_fee: 50,
        consultation_currency: 'USD',
        compensations: [
          {
            pay_type: 'PER_MONTH',
            rate: 1200,
            currency: 'USD',
            effective_from: new Date('2026-01-01'),
          },
        ],
      },
      'actor-1',
      '127.0.0.1'
    );

    expect(result).toEqual(
      expect.objectContaining({
        consultation_fee: 50,
        staff_number: 'STF-001',
      })
    );
    expect(result).not.toHaveProperty('payment_status');
    expect(result).not.toHaveProperty('balance');
    expect(result).not.toHaveProperty('paid');
    expectNoPatientBillingPosts();
  });

  it('createStaffProfile with fee catalog is idempotent on Billing bypass', async () => {
    const createdProfile = {
      id: 'staff-1',
      human_friendly_id: 'STF0001',
      tenant_id: tenantId,
      user_id: userId,
      staff_number: 'STF-001',
      practitioner_type: 'SPECIALIST',
      consultation_fee: 75,
      consultation_currency: 'UGX',
    };
    staffProfileRepository.create.mockResolvedValue(createdProfile);
    staffProfileRepository.findById.mockResolvedValue(createdProfile);

    const payload = {
      tenant_id: tenantId,
      user_id: userId,
      staff_number: 'STF-001',
      position: 'MO',
      practitioner_type: 'SPECIALIST',
      consultation_fee: 75,
      consultation_currency: 'UGX',
    };

    await staffProfileService.createStaffProfile(payload, 'actor-1', '127.0.0.1');
    await staffProfileService.createStaffProfile(payload, 'actor-1', '127.0.0.1');

    expect(staffProfileRepository.create).toHaveBeenCalledTimes(2);
    expectNoPatientBillingPosts();
  });
});
