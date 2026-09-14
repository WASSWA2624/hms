/**
 * User lifecycle service tests
 *
 * @module tests/modules/user/services/user.lifecycle
 * @description Administrator-managed account rules: atomic create with roles,
 * scope and staff profile; scope enforcement; status changes and session
 * revocation; and credential resets that never expose a secret.
 */

jest.mock('@repositories/user/user.repository');
jest.mock('@lib/audit');
jest.mock('@lib/crypto');
jest.mock('@prisma/client', () => ({
  user_role: { findMany: jest.fn() },
  permission: { findMany: jest.fn() }}));
jest.mock('@lib/authorization/assignable-access', () => ({
  PLATFORM_ADMIN_MANAGED_ROLES: new Set(['PLATFORM_ADMIN', 'PLATFORM_OWNER']),
  assertPermissionIdsAssignable: jest.fn(),
  assertRoleIdAssignable: jest.fn(),
  canActorCreatePlatformRole: jest.fn(),
  canActorCreateTenantWideRole: jest.fn(),
  canActorManagePlatformAdmins: jest.fn()}));
jest.mock('@lib/authorization/effective-access', () => ({
  resolveRequestPermissionNames: jest.fn()}));
jest.mock('@lib/authorization/demo-user-guard', () => ({
  assertDemoUserNotMutable: jest.fn(),
  assertUserIdNotDemoProtected: jest.fn()}));
jest.mock('@lib/billing/identifiers', () => ({
  ...jest.requireActual('@lib/billing/identifiers'),
  resolveEntityId: jest.fn(),
  resolveIdentifierForPayload: jest.fn(),
  resolvePublicIdentifier: jest.fn()}));
jest.mock('@lib/hr/staff-number', () => ({ generateStaffNumber: jest.fn() }));
jest.mock('@lib/websocket/crud-realtime', () => ({ publishCrudRealtimeEvent: jest.fn() }));
jest.mock('@lib/realtime/platform-realtime', () => ({ publishPlatformRealtimeEvent: jest.fn() }));
jest.mock('@services/auth/auth.service', () => ({ issuePasswordReset: jest.fn() }));

const userService = require('@services/user/user.service');
const userRepository = require('@repositories/user/user.repository');
const prisma = require('@prisma/client');
const { createAuditLog } = require('@lib/audit');
const { hashPassword } = require('@lib/crypto');
const { HttpError } = require('@lib/errors');
const {
  assertPermissionIdsAssignable,
  assertRoleIdAssignable,
  canActorCreatePlatformRole,
  canActorCreateTenantWideRole,
  canActorManagePlatformAdmins} = require('@lib/authorization/assignable-access');
const { resolveRequestPermissionNames } = require('@lib/authorization/effective-access');
const { assertDemoUserNotMutable } = require('@lib/authorization/demo-user-guard');
const {
  resolveEntityId,
  resolveIdentifierForPayload,
  resolvePublicIdentifier} = require('@lib/billing/identifiers');
const { generateStaffNumber } = require('@lib/hr/staff-number');
const { publishCrudRealtimeEvent } = require('@lib/websocket/crud-realtime');
const { publishPlatformRealtimeEvent } = require('@lib/realtime/platform-realtime');
const { issuePasswordReset } = require('@services/auth/auth.service');

const TENANT_ID = '11111111-1111-4111-8111-111111111111';
const OTHER_TENANT_ID = '22222222-2222-4222-8222-222222222222';
const FACILITY_ID = '33333333-3333-4333-8333-333333333333';
const OTHER_FACILITY_ID = '44444444-4444-4444-8444-444444444444';
const USER_ID = '55555555-5555-4555-8555-555555555555';
const ROLE_ID = '66666666-6666-4666-8666-666666666666';
const IP = '127.0.0.1';
const PERSISTED_HASH = '$2b$10$persistedhashvalue';

const tenantAdmin = {
  id: 'actor-tenant-admin',
  tenant_id: TENANT_ID,
  facility_id: FACILITY_ID,
  roles: ['TENANT_ADMIN'],
  permissions: ['tenant:admin']};
const facilityAdmin = {
  id: 'actor-facility-admin',
  tenant_id: TENANT_ID,
  facility_id: FACILITY_ID,
  roles: ['FACILITY_ADMIN'],
  permissions: ['facility:admin']};
const platformAdmin = {
  id: 'actor-platform-admin',
  tenant_id: null,
  roles: ['PLATFORM_ADMIN'],
  permissions: ['platform:admin']};

const createPayload = (overrides = {}) => ({
  tenant_id: TENANT_ID,
  facility_id: FACILITY_ID,
  first_name: 'Grace',
  last_name: 'Nakato',
  email: 'grace.nakato@example.com',
  phone: '+256 700 111222',
  position_title: 'Charge Nurse',
  password: 'StrongPass123!',
  status: 'ACTIVE',
  ...overrides});

const persistedUser = (overrides = {}) => ({
  id: USER_ID,
  human_friendly_id: 'USR-0042',
  tenant_id: TENANT_ID,
  facility_id: FACILITY_ID,
  email: 'grace.nakato@example.com',
  phone: '256700111222',
  position_title: 'Charge Nurse',
  status: 'ACTIVE',
  password_hash: PERSISTED_HASH,
  profile: { first_name: 'Grace', last_name: 'Nakato' },
  roles: [],
  ...overrides});

const flushAudit = () => new Promise((resolve) => setImmediate(resolve));

describe('User lifecycle', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    hashPassword.mockResolvedValue('$2b$10$hashedpasswordplaceholder');
    createAuditLog.mockResolvedValue(true);
    prisma.user_role.findMany.mockResolvedValue([]);
    prisma.permission.findMany.mockResolvedValue([]);
    assertPermissionIdsAssignable.mockImplementation(async (ids) => ids);
    assertRoleIdAssignable.mockImplementation(async (roleId) => ({
      id: roleId,
      tenant_id: TENANT_ID,
      facility_id: null}));
    canActorCreatePlatformRole.mockImplementation((actor = {}) =>
      (actor.roles || []).includes('PLATFORM_ADMIN'));
    canActorCreateTenantWideRole.mockImplementation((actor = {}) =>
      ['PLATFORM_ADMIN', 'TENANT_ADMIN'].some((role) => (actor.roles || []).includes(role)));
    canActorManagePlatformAdmins.mockReturnValue(false);
    resolveRequestPermissionNames.mockReturnValue([]);
    assertDemoUserNotMutable.mockImplementation(() => {});
    resolveEntityId.mockImplementation(async ({ identifier }) => identifier);
    resolveIdentifierForPayload.mockImplementation(async ({ value }) => value);
    resolvePublicIdentifier.mockImplementation((...values) =>
      values.find((value) => typeof value === 'string' && value.startsWith('USR')) || null);
    generateStaffNumber.mockResolvedValue({ staff_number: 'FMC-0007', tenant_id: TENANT_ID });
    publishCrudRealtimeEvent.mockResolvedValue(undefined);
    publishPlatformRealtimeEvent.mockResolvedValue(undefined);

    userRepository.findMany.mockResolvedValue([]);
    userRepository.findFacilityScope.mockResolvedValue({ id: FACILITY_ID, tenant_id: TENANT_ID });
    userRepository.findDeletedByTenantEmail.mockResolvedValue(null);
    userRepository.create.mockImplementation(async () => persistedUser());
    userRepository.findById.mockResolvedValue(persistedUser());
    userRepository.update.mockImplementation(async (id, payload) =>
      persistedUser({ ...payload }));
  });

  describe('createUser', () => {
    it('persists the user, staff profile and roles in one create and never returns the password hash', async () => {
      const result = await userService.createUser(
        createPayload({ role_ids: [ROLE_ID], staff_profile: { position: 'Ward Nurse' } }),
        tenantAdmin.id,
        IP,
        tenantAdmin
      );

      expect(userRepository.create).toHaveBeenCalledTimes(1);
      expect(userRepository.create).toHaveBeenCalledWith(
        expect.objectContaining({
          tenant_id: TENANT_ID,
          facility_id: FACILITY_ID,
          email: 'grace.nakato@example.com',
          password_hash: '$2b$10$hashedpasswordplaceholder',
          role_assignments: [{ role_id: ROLE_ID, facility_id: FACILITY_ID }],
          staff_profile: { position: 'Ward Nurse', staff_number: 'FMC-0007' }})
      );
      const persisted = userRepository.create.mock.calls[0][0];
      expect(persisted.password).toBeUndefined();
      expect(persisted.role_ids).toBeUndefined();

      expect(result.password_hash).toBeUndefined();
      expect(JSON.stringify(result)).not.toContain('StrongPass123!');

      await flushAudit();
      expect(createAuditLog.mock.calls[0][0].diff.after.password_hash).toBeUndefined();
      expect(JSON.stringify(publishCrudRealtimeEvent.mock.calls)).not.toContain(PERSISTED_HASH);
      expect(JSON.stringify(publishPlatformRealtimeEvent.mock.calls)).not.toContain(PERSISTED_HASH);
    });

    it('rejects a role from another tenant before writing anything', async () => {
      assertRoleIdAssignable.mockResolvedValue({
        id: ROLE_ID,
        tenant_id: OTHER_TENANT_ID,
        facility_id: null});

      await expect(
        userService.createUser(createPayload({ role_ids: [ROLE_ID] }), tenantAdmin.id, IP, tenantAdmin)
      ).rejects.toMatchObject({
        messageKey: 'errors.user_role.role_tenant_mismatch',
        statusCode: 400,
        errors: [expect.objectContaining({ field: 'role_ids', role_id: ROLE_ID })]});
      expect(userRepository.create).not.toHaveBeenCalled();
      expect(createAuditLog).not.toHaveBeenCalled();
    });

    it('rejects a role limited to a different facility', async () => {
      assertRoleIdAssignable.mockResolvedValue({
        id: ROLE_ID,
        tenant_id: TENANT_ID,
        facility_id: OTHER_FACILITY_ID});

      await expect(
        userService.createUser(createPayload({ role_ids: [ROLE_ID] }), tenantAdmin.id, IP, tenantAdmin)
      ).rejects.toMatchObject({
        messageKey: 'errors.user_role.role_facility_mismatch',
        errors: [expect.objectContaining({ field: 'role_ids' })]});
      expect(userRepository.create).not.toHaveBeenCalled();
    });

    it('reports a role above the actor ceiling against the roles field', async () => {
      assertRoleIdAssignable.mockRejectedValue(
        new HttpError('errors.auth.insufficient_permissions', 403, [{ field: 'role_id' }])
      );

      await expect(
        userService.createUser(createPayload({ role_ids: [ROLE_ID] }), tenantAdmin.id, IP, tenantAdmin)
      ).rejects.toMatchObject({
        messageKey: 'errors.auth.insufficient_permissions',
        statusCode: 403,
        errors: [expect.objectContaining({ field: 'role_ids', role_id: ROLE_ID })]});
      expect(userRepository.create).not.toHaveBeenCalled();
    });

    it('rejects a facility that belongs to another tenant', async () => {
      userRepository.findFacilityScope.mockResolvedValue({
        id: OTHER_FACILITY_ID,
        tenant_id: OTHER_TENANT_ID});

      await expect(
        userService.createUser(
          createPayload({ facility_id: OTHER_FACILITY_ID }),
          platformAdmin.id,
          IP,
          platformAdmin
        )
      ).rejects.toMatchObject({
        messageKey: 'errors.user.facility_tenant_mismatch',
        statusCode: 400,
        errors: [expect.objectContaining({ field: 'facility_id' })]});
      expect(userRepository.create).not.toHaveBeenCalled();
    });

    it('reports an email still held by a deleted user against the email field', async () => {
      userRepository.findDeletedByTenantEmail.mockResolvedValue({ id: 'deleted-user' });

      await expect(
        userService.createUser(createPayload(), tenantAdmin.id, IP, tenantAdmin)
      ).rejects.toMatchObject({
        messageKey: 'errors.user.email_exists_deleted_in_tenant',
        statusCode: 409,
        errors: [expect.objectContaining({ field: 'email', restorable: true })]});
      expect(userRepository.findDeletedByTenantEmail).toHaveBeenCalledWith(
        TENANT_ID,
        'grace.nakato@example.com',
        null
      );
      expect(userRepository.create).not.toHaveBeenCalled();
    });

    it('stops a tenant admin from creating a user in another tenant', async () => {
      await expect(
        userService.createUser(
          createPayload({ tenant_id: OTHER_TENANT_ID }),
          tenantAdmin.id,
          IP,
          tenantAdmin
        )
      ).rejects.toMatchObject({
        messageKey: 'errors.auth.scope_mismatch',
        statusCode: 403,
        errors: [expect.objectContaining({ field: 'tenant_id' })]});
      expect(userRepository.create).not.toHaveBeenCalled();
    });

    it('keeps a facility admin inside their own facility', async () => {
      await expect(
        userService.createUser(
          createPayload({ facility_id: OTHER_FACILITY_ID }),
          facilityAdmin.id,
          IP,
          facilityAdmin
        )
      ).rejects.toMatchObject({
        messageKey: 'errors.user.facility_required_for_scope',
        statusCode: 403,
        errors: [expect.objectContaining({ field: 'facility_id' })]});

      await expect(
        userService.createUser(
          createPayload({ facility_id: null }),
          facilityAdmin.id,
          IP,
          facilityAdmin
        )
      ).rejects.toMatchObject({
        messageKey: 'errors.user.facility_required_for_scope',
        statusCode: 400});
      expect(userRepository.create).not.toHaveBeenCalled();
    });

    it('lets a tenant admin create an organization-wide user without a facility', async () => {
      await userService.createUser(
        createPayload({ facility_id: null }),
        tenantAdmin.id,
        IP,
        tenantAdmin
      );

      expect(userRepository.findFacilityScope).not.toHaveBeenCalled();
      expect(userRepository.create).toHaveBeenCalledWith(
        expect.objectContaining({ tenant_id: TENANT_ID, facility_id: null })
      );
    });

    it('lets a platform admin create a user in any tenant', async () => {
      userRepository.findFacilityScope.mockResolvedValue({
        id: OTHER_FACILITY_ID,
        tenant_id: OTHER_TENANT_ID});

      await userService.createUser(
        createPayload({ tenant_id: OTHER_TENANT_ID, facility_id: OTHER_FACILITY_ID }),
        platformAdmin.id,
        IP,
        platformAdmin
      );

      expect(userRepository.create).toHaveBeenCalledWith(
        expect.objectContaining({ tenant_id: OTHER_TENANT_ID, facility_id: OTHER_FACILITY_ID })
      );
    });

    it('retries with a fresh staff number when the generated one was taken', async () => {
      userRepository.create
        .mockRejectedValueOnce(
          new HttpError('errors.user.staff_number_conflict', 409, [{ field: 'staff_number' }])
        )
        .mockImplementationOnce(async () => persistedUser());
      generateStaffNumber
        .mockResolvedValueOnce({ staff_number: 'FMC-0007' })
        .mockResolvedValueOnce({ staff_number: 'FMC-0008' });

      await userService.createUser(
        createPayload({ staff_profile: {} }),
        tenantAdmin.id,
        IP,
        tenantAdmin
      );

      expect(userRepository.create).toHaveBeenCalledTimes(2);
      expect(userRepository.create.mock.calls[0][0].staff_profile).toEqual({
        position: 'Charge Nurse',
        staff_number: 'FMC-0007'});
      expect(userRepository.create.mock.calls[1][0].staff_profile.staff_number).toBe('FMC-0008');
    });

    it('surfaces a failed transaction without audit or realtime side effects', async () => {
      userRepository.create.mockRejectedValue(
        new HttpError('errors.database.foreign_key_field', 400, [{ field: 'role_id' }])
      );

      await expect(
        userService.createUser(createPayload({ role_ids: [ROLE_ID] }), tenantAdmin.id, IP, tenantAdmin)
      ).rejects.toMatchObject({ messageKey: 'errors.database.foreign_key_field' });

      await flushAudit();
      expect(createAuditLog).not.toHaveBeenCalled();
      expect(publishCrudRealtimeEvent).not.toHaveBeenCalled();
      expect(publishPlatformRealtimeEvent).not.toHaveBeenCalled();
    });
  });

  describe('updateUser', () => {
    const similarPeer = {
      id: 'peer-user',
      human_friendly_id: 'USR-0099',
      tenant_id: TENANT_ID,
      email: 'grace.n@example.com',
      phone: null,
      position_title: 'Charge Nurse',
      profile: { first_name: 'Grace', last_name: 'Nakato' }};

    it('changes status without re-running similarity review and revokes sessions', async () => {
      userRepository.findMany.mockResolvedValue([similarPeer]);

      const result = await userService.updateUser(
        USER_ID,
        { status: 'INACTIVE' },
        tenantAdmin.id,
        IP,
        tenantAdmin
      );

      expect(result.status).toBe('INACTIVE');
      expect(result.password_hash).toBeUndefined();
      expect(userRepository.findMany).not.toHaveBeenCalled();
      expect(userRepository.update).toHaveBeenCalledWith(
        USER_ID,
        { status: 'INACTIVE' },
        { revokeSessions: true }
      );
    });

    it('reactivates without touching sessions', async () => {
      userRepository.findById.mockResolvedValue(persistedUser({ status: 'INACTIVE' }));

      await userService.updateUser(USER_ID, { status: 'ACTIVE' }, tenantAdmin.id, IP, tenantAdmin);

      expect(userRepository.update).toHaveBeenCalledWith(
        USER_ID,
        { status: 'ACTIVE' },
        { revokeSessions: false }
      );
    });

    it('stops an administrator from deactivating their own account', async () => {
      const self = { ...tenantAdmin, id: USER_ID };

      await expect(
        userService.updateUser(USER_ID, { status: 'SUSPENDED' }, USER_ID, IP, self)
      ).rejects.toMatchObject({
        messageKey: 'errors.user.cannot_deactivate_self',
        statusCode: 400,
        errors: [expect.objectContaining({ field: 'status' })]});
      expect(userRepository.update).not.toHaveBeenCalled();
    });

    it('re-runs uniqueness when an identifying detail changes', async () => {
      await userService.updateUser(
        USER_ID,
        { position_title: 'Head Nurse' },
        tenantAdmin.id,
        IP,
        tenantAdmin
      );

      expect(userRepository.findMany).toHaveBeenCalled();
    });

    it('treats an unchanged facility as no change and validates a moved one', async () => {
      await userService.updateUser(
        USER_ID,
        { facility_id: FACILITY_ID, first_name: 'Grace' },
        tenantAdmin.id,
        IP,
        tenantAdmin
      );
      expect(userRepository.update.mock.calls[0][1].facility_id).toBeUndefined();
      expect(userRepository.findFacilityScope).not.toHaveBeenCalled();

      userRepository.findFacilityScope.mockResolvedValue({
        id: OTHER_FACILITY_ID,
        tenant_id: OTHER_TENANT_ID});
      await expect(
        userService.updateUser(
          USER_ID,
          { facility_id: OTHER_FACILITY_ID },
          tenantAdmin.id,
          IP,
          tenantAdmin
        )
      ).rejects.toMatchObject({
        messageKey: 'errors.user.facility_tenant_mismatch',
        errors: [expect.objectContaining({ field: 'facility_id' })]});
      expect(userRepository.update).toHaveBeenCalledTimes(1);
    });

    it('reports an email change onto a deleted user address against the email field', async () => {
      userRepository.findDeletedByTenantEmail.mockResolvedValue({ id: 'deleted-user' });

      await expect(
        userService.updateUser(
          USER_ID,
          { email: 'retired.nurse@example.com' },
          tenantAdmin.id,
          IP,
          tenantAdmin
        )
      ).rejects.toMatchObject({
        messageKey: 'errors.user.email_exists_deleted_in_tenant',
        errors: [expect.objectContaining({ field: 'email' })]});
      expect(userRepository.findDeletedByTenantEmail).toHaveBeenCalledWith(
        TENANT_ID,
        'retired.nurse@example.com',
        USER_ID
      );
      expect(userRepository.update).not.toHaveBeenCalled();
    });

    it('refuses to change a user in another tenant', async () => {
      userRepository.findById.mockResolvedValue(persistedUser({ tenant_id: OTHER_TENANT_ID }));

      await expect(
        userService.updateUser(USER_ID, { status: 'INACTIVE' }, tenantAdmin.id, IP, tenantAdmin)
      ).rejects.toMatchObject({ messageKey: 'errors.auth.scope_mismatch', statusCode: 403 });
      expect(userRepository.update).not.toHaveBeenCalled();
    });

    it('keeps the password hash out of the audit diff', async () => {
      await userService.updateUser(USER_ID, { status: 'INACTIVE' }, tenantAdmin.id, IP, tenantAdmin);
      await flushAudit();

      const audit = createAuditLog.mock.calls[0][0];
      expect(audit.diff.before.password_hash).toBeUndefined();
      expect(audit.diff.after.password_hash).toBeUndefined();
      expect(audit.details).toEqual({ sessions_revoked: true });
    });
  });

  describe('resetUserCredentials', () => {
    const issued = {
      delivery_status: 'SENT',
      expires_at: '2026-09-13T13:00:00.000Z',
      masked_email: 'gr***@e***.com'};

    beforeEach(() => {
      issuePasswordReset.mockResolvedValue(issued);
    });

    it('issues a reset and returns only the masked destination, delivery status and expiry', async () => {
      const result = await userService.resetUserCredentials(USER_ID, tenantAdmin, {
        ipAddress: IP,
        requestContext: { origin: 'https://app.example.com' }});

      expect(result).toEqual({
        user_id: 'USR-0042',
        masked_email: 'gr***@e***.com',
        delivery_status: 'SENT',
        expires_at: '2026-09-13T13:00:00.000Z'});
      expect(issuePasswordReset).toHaveBeenCalledWith({
        user: expect.objectContaining({ id: USER_ID, email: 'grace.nakato@example.com' }),
        request_context: { origin: 'https://app.example.com' },
        context: 'admin_credentials_reset'});

      await flushAudit();
      const audit = createAuditLog.mock.calls[0][0];
      expect(audit).toEqual(
        expect.objectContaining({
          action: 'USER_CREDENTIALS_RESET_ISSUED',
          entity: 'user',
          entity_id: USER_ID,
          user_id: tenantAdmin.id,
          tenant_id: TENANT_ID,
          details: { delivery_status: 'SENT', expires_at: '2026-09-13T13:00:00.000Z' }})
      );
      expect(JSON.stringify({ result, audit })).not.toMatch(/password|token|code|hash/i);
    });

    it('refuses demo accounts without issuing anything', async () => {
      assertDemoUserNotMutable.mockImplementation(() => {
        throw new HttpError('errors.user.demo_protected', 403, [{ field: 'user_id' }]);
      });

      await expect(
        userService.resetUserCredentials(USER_ID, tenantAdmin, { ipAddress: IP })
      ).rejects.toMatchObject({ messageKey: 'errors.user.demo_protected', statusCode: 403 });
      expect(issuePasswordReset).not.toHaveBeenCalled();
    });

    it('refuses accounts outside the actor tenant', async () => {
      userRepository.findById.mockResolvedValue(persistedUser({ tenant_id: OTHER_TENANT_ID }));

      await expect(
        userService.resetUserCredentials(USER_ID, tenantAdmin, { ipAddress: IP })
      ).rejects.toMatchObject({ messageKey: 'errors.auth.scope_mismatch', statusCode: 403 });
      expect(issuePasswordReset).not.toHaveBeenCalled();
    });

    it('refuses platform admin accounts for actors who cannot manage them', async () => {
      prisma.user_role.findMany.mockResolvedValue([{ role: { name: 'PLATFORM_ADMIN' } }]);

      await expect(
        userService.resetUserCredentials(USER_ID, tenantAdmin, { ipAddress: IP })
      ).rejects.toMatchObject({ messageKey: 'errors.auth.insufficient_permissions', statusCode: 403 });
      expect(issuePasswordReset).not.toHaveBeenCalled();
    });

    it('reports a user without an email address against the email field', async () => {
      userRepository.findById.mockResolvedValue(persistedUser({ email: '' }));

      await expect(
        userService.resetUserCredentials(USER_ID, tenantAdmin, { ipAddress: IP })
      ).rejects.toMatchObject({
        messageKey: 'errors.user.reset_requires_email',
        statusCode: 400,
        errors: [expect.objectContaining({ field: 'email' })]});
      expect(issuePasswordReset).not.toHaveBeenCalled();
    });

    it('returns not found for an unknown user', async () => {
      userRepository.findById.mockResolvedValue(null);

      await expect(
        userService.resetUserCredentials(USER_ID, tenantAdmin, { ipAddress: IP })
      ).rejects.toMatchObject({ messageKey: 'errors.user.not_found', statusCode: 404 });
      expect(issuePasswordReset).not.toHaveBeenCalled();
    });
  });

  describe('setUserPassword', () => {
    const NEW_PASSWORD = 'NewStrong123!';

    beforeEach(() => {
      userRepository.setPassword.mockResolvedValue(undefined);
    });

    it('stores a hash of the new password and audits without the secret', async () => {
      hashPassword.mockResolvedValue('$2b$10$adminsetpasswordhash');

      const result = await userService.setUserPassword(USER_ID, NEW_PASSWORD, tenantAdmin, {
        ipAddress: IP});

      expect(result).toEqual({ user_id: 'USR-0042', sessions_revoked: true });
      expect(hashPassword).toHaveBeenCalledWith(NEW_PASSWORD);
      expect(userRepository.setPassword).toHaveBeenCalledWith(USER_ID, '$2b$10$adminsetpasswordhash');

      await flushAudit();
      const audit = createAuditLog.mock.calls[0][0];
      expect(audit).toEqual(
        expect.objectContaining({
          action: 'USER_PASSWORD_SET',
          entity: 'user',
          entity_id: USER_ID,
          user_id: tenantAdmin.id,
          tenant_id: TENANT_ID,
          ip_address: IP,
          details: { sessions_revoked: true }})
      );
      expect(JSON.stringify({ result, audit })).not.toMatch(/NewStrong123!|\$2b\$/);
    });

    it("refuses the actor's own account", async () => {
      await expect(
        userService.setUserPassword(USER_ID, NEW_PASSWORD, { ...tenantAdmin, id: USER_ID }, {
          ipAddress: IP})
      ).rejects.toMatchObject({
        messageKey: 'errors.user.set_password_self',
        statusCode: 400,
        errors: [expect.objectContaining({ field: 'password' })]});
      expect(userRepository.setPassword).not.toHaveBeenCalled();
    });

    it('refuses demo accounts', async () => {
      assertDemoUserNotMutable.mockImplementation(() => {
        throw new HttpError('errors.user.demo_protected', 403, [{ field: 'user_id' }]);
      });

      await expect(
        userService.setUserPassword(USER_ID, NEW_PASSWORD, tenantAdmin, { ipAddress: IP })
      ).rejects.toMatchObject({ messageKey: 'errors.user.demo_protected', statusCode: 403 });
      expect(userRepository.setPassword).not.toHaveBeenCalled();
    });

    it('refuses accounts outside the actor tenant', async () => {
      userRepository.findById.mockResolvedValue(persistedUser({ tenant_id: OTHER_TENANT_ID }));

      await expect(
        userService.setUserPassword(USER_ID, NEW_PASSWORD, tenantAdmin, { ipAddress: IP })
      ).rejects.toMatchObject({ messageKey: 'errors.auth.scope_mismatch', statusCode: 403 });
      expect(userRepository.setPassword).not.toHaveBeenCalled();
    });

    it('refuses platform admin accounts for actors who cannot manage them', async () => {
      prisma.user_role.findMany.mockResolvedValue([{ role: { name: 'PLATFORM_ADMIN' } }]);

      await expect(
        userService.setUserPassword(USER_ID, NEW_PASSWORD, tenantAdmin, { ipAddress: IP })
      ).rejects.toMatchObject({ messageKey: 'errors.auth.insufficient_permissions', statusCode: 403 });
      expect(userRepository.setPassword).not.toHaveBeenCalled();
    });

    it('returns not found for an unknown user', async () => {
      userRepository.findById.mockResolvedValue(null);

      await expect(
        userService.setUserPassword(USER_ID, NEW_PASSWORD, tenantAdmin, { ipAddress: IP })
      ).rejects.toMatchObject({ messageKey: 'errors.user.not_found', statusCode: 404 });
      expect(userRepository.setPassword).not.toHaveBeenCalled();
    });
  });
});
