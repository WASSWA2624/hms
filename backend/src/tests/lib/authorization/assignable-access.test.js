/**
 * @jest-environment node
 */

const {
  canActorCreatePlatformRole,
  canActorCreateTenantWideRole,
  filterPermissionRecordsByCeiling,
  isRoleWithinActorCeiling,
  resolveActorAssignablePermissionNames,
  buildRoleScopeWhere} = require('@lib/authorization/assignable-access');
const { ROLES } = require('@config/roles');
const { PERMISSIONS, ROLE_PERMISSIONS } = require('@config/permissions');

describe('assignable-access', () => {
  describe('canActorCreateTenantWideRole', () => {
    it('allows platform owners and platform admins', () => {
      expect(canActorCreateTenantWideRole({ roles: [ROLES.PLATFORM_OWNER] })).toBe(true);
      expect(canActorCreateTenantWideRole({ roles: [ROLES.PLATFORM_ADMIN] })).toBe(true);
      expect(canActorCreateTenantWideRole({ roles: [ROLES.TENANT_ADMIN] })).toBe(true);
    });

    it('blocks facility admins', () => {
      expect(canActorCreateTenantWideRole({ roles: [ROLES.FACILITY_ADMIN] })).toBe(false);
    });
  });

  describe('canActorCreatePlatformRole', () => {
    it('allows elevated platform roles', () => {
      expect(canActorCreatePlatformRole({ roles: [ROLES.PLATFORM_OWNER] })).toBe(true);
      expect(canActorCreatePlatformRole({ roles: [ROLES.PLATFORM_ADMIN] })).toBe(true);
      expect(canActorCreatePlatformRole({ roles: [ROLES.TENANT_ADMIN] })).toBe(false);
      expect(canActorCreatePlatformRole({ roles: [ROLES.FACILITY_ADMIN] })).toBe(false);
    });

    it('allows platform:admin permission holders', () => {
      expect(
        canActorCreatePlatformRole({
          roles: [],
          permissions: [PERMISSIONS.PLATFORM_ADMIN]
        })
      ).toBe(true);
    });
  });

  describe('resolveActorAssignablePermissionNames', () => {
    it('gives facility admins every non-admin permission', () => {
      const names = resolveActorAssignablePermissionNames({
        roles: [ROLES.FACILITY_ADMIN]});
      expect(names.has(PERMISSIONS.FACILITY_ADMIN)).toBe(false);
      expect(names.has(PERMISSIONS.TENANT_ADMIN)).toBe(false);
      expect(names.has(PERMISSIONS.PLATFORM_ADMIN)).toBe(false);
      expect(names.has(PERMISSIONS.CLINICAL_READ)).toBe(true);
      expect(names.has(PERMISSIONS.HR_WRITE)).toBe(true);
      // Custom roles can be granted Accounts keys (02-roles AC7).
      expect(names.has(PERMISSIONS.ACCOUNTS_READ)).toBe(true);
      expect(names.has(PERMISSIONS.ACCOUNTS_WRITE)).toBe(true);
    });

    it('gives HR every non-admin permission, not the JWT shell pack', () => {
      const names = resolveActorAssignablePermissionNames({
        roles: [ROLES.HR],
        permissions: [PERMISSIONS.HR_READ, PERMISSIONS.HR_WRITE],
      });
      expect(names.has(PERMISSIONS.FACILITY_ADMIN)).toBe(false);
      expect(names.has(PERMISSIONS.CLINICAL_READ)).toBe(true);
      expect(names.has(PERMISSIONS.LAB_WRITE)).toBe(true);
      expect(names.has(PERMISSIONS.TENANT_ADMIN)).toBe(false);
      expect(names.has(PERMISSIONS.PLATFORM_ADMIN)).toBe(false);
    });

    it('treats hr:write without an HR role as a facility assignment ceiling', () => {
      const names = resolveActorAssignablePermissionNames({
        roles: [],
        permissions: [PERMISSIONS.HR_READ, PERMISSIONS.HR_WRITE, PERMISSIONS.PROFILE_READ],
      });
      expect(names.has(PERMISSIONS.CLINICAL_READ)).toBe(true);
      expect(names.has(PERMISSIONS.FACILITY_ADMIN)).toBe(false);
    });

    it('includes tenant:admin for tenant admins', () => {
      const names = resolveActorAssignablePermissionNames({
        roles: [ROLES.TENANT_ADMIN]});
      expect(names.has(PERMISSIONS.TENANT_ADMIN)).toBe(true);
      expect(names.has(PERMISSIONS.PLATFORM_ADMIN)).toBe(false);
    });

    it('gives tenant admins every non-admin permission beyond their session pack', () => {
      const actor = {
        roles: [ROLES.TENANT_ADMIN],
        permissions: [PERMISSIONS.TENANT_ADMIN, PERMISSIONS.PROFILE_READ],
      };
      const names = resolveActorAssignablePermissionNames(actor);
      expect(names.has(PERMISSIONS.TENANT_ADMIN)).toBe(true);
      expect(names.has(PERMISSIONS.ACCOUNTS_WRITE)).toBe(true);
      expect(names.has(PERMISSIONS.HR_WRITE)).toBe(true);
      expect(names.has(PERMISSIONS.PLATFORM_ADMIN)).toBe(false);
      expect(
        isRoleWithinActorCeiling(
          {
            name: 'ACCOUNTANT',
            permissions: [{ permission: { name: PERMISSIONS.ACCOUNTS_WRITE } }]},
          actor
        )
      ).toBe(true);
      expect(isRoleWithinActorCeiling({ name: ROLES.PLATFORM_ADMIN }, actor)).toBe(false);
    });

    it('keeps a full ceiling for platform admins even when JWT permissions are plan-gated', () => {
      const names = resolveActorAssignablePermissionNames({
        roles: [ROLES.PLATFORM_ADMIN],
        permissions: [PERMISSIONS.PROFILE_READ, PERMISSIONS.PATIENT_READ]});
      expect(names.has(PERMISSIONS.PLATFORM_ADMIN)).toBe(true);
      expect(names.has(PERMISSIONS.MORTUARY_READ)).toBe(true);
      expect(names.has(PERMISSIONS.LAB_WRITE)).toBe(true);
      expect(names.has(PERMISSIONS.PLATFORM_OWNER)).toBe(false);
    });

    it('includes platform:owner only for platform owners', () => {
      const ownerNames = resolveActorAssignablePermissionNames({
        roles: [ROLES.PLATFORM_OWNER],
      });
      expect(ownerNames.has(PERMISSIONS.PLATFORM_OWNER)).toBe(true);
      expect(ownerNames.has(PERMISSIONS.PLATFORM_ADMIN)).toBe(true);
    });
  });

  describe('isFacilityScopedAccessActor', () => {
    const {
      isFacilityScopedAccessActor,
    } = require('@lib/authorization/assignable-access');

    it('treats facility admin and HR as facility-scoped', () => {
      expect(isFacilityScopedAccessActor({ roles: [ROLES.FACILITY_ADMIN] })).toBe(true);
      expect(isFacilityScopedAccessActor({ roles: [ROLES.HR] })).toBe(true);
    });

    it('excludes tenant and platform admins', () => {
      expect(isFacilityScopedAccessActor({ roles: [ROLES.TENANT_ADMIN] })).toBe(false);
      expect(isFacilityScopedAccessActor({ roles: [ROLES.PLATFORM_ADMIN] })).toBe(false);
      expect(
        isFacilityScopedAccessActor({
          roles: [ROLES.HR, ROLES.TENANT_ADMIN],
        })
      ).toBe(false);
    });
  });

  describe('isRoleWithinActorCeiling HR reuse', () => {
    it('allows HR to assign built-in clinical roles within facility-admin ceiling', () => {
      expect(
        isRoleWithinActorCeiling(
          {
            name: ROLES.DOCTOR,
            permissions: (ROLE_PERMISSIONS[ROLES.DOCTOR] || []).map((name) => ({
              name,
            })),
          },
          { roles: [ROLES.HR] }
        )
      ).toBe(true);
    });

    it('blocks HR from assigning tenant admin', () => {
      expect(
        isRoleWithinActorCeiling(
          { name: ROLES.TENANT_ADMIN },
          { roles: [ROLES.HR] }
        )
      ).toBe(false);
    });

    it('blocks HR from assigning facility admin', () => {
      expect(
        isRoleWithinActorCeiling(
          { name: ROLES.FACILITY_ADMIN },
          { roles: [ROLES.HR] }
        )
      ).toBe(false);
    });
  });

  describe('isRoleWithinActorCeiling platform admin management', () => {
    it('blocks platform admins from assigning PLATFORM_ADMIN', () => {
      expect(
        isRoleWithinActorCeiling(
          { name: ROLES.PLATFORM_ADMIN, permissions: ROLE_PERMISSIONS[ROLES.PLATFORM_ADMIN].map((name) => ({ name })) },
          { roles: [ROLES.PLATFORM_ADMIN] }
        )
      ).toBe(false);
    });

    it('allows platform owners to assign PLATFORM_ADMIN', () => {
      expect(
        isRoleWithinActorCeiling(
          { name: ROLES.PLATFORM_ADMIN, permissions: ROLE_PERMISSIONS[ROLES.PLATFORM_ADMIN].map((name) => ({ name })) },
          { roles: [ROLES.PLATFORM_OWNER] }
        )
      ).toBe(true);
    });
  });

  describe('filterPermissionRecordsByCeiling', () => {
    it('keeps only permissions within the actor ceiling', () => {
      const filtered = filterPermissionRecordsByCeiling(
        [
          { id: '1', name: PERMISSIONS.FACILITY_ADMIN },
          { id: '2', name: PERMISSIONS.TENANT_ADMIN },
          { id: '3', name: PERMISSIONS.PLATFORM_ADMIN },
          { id: '4', name: PERMISSIONS.CLINICAL_READ }],
        { roles: [ROLES.FACILITY_ADMIN] }
      );
      expect(filtered.map((entry) => entry.name)).toEqual([PERMISSIONS.CLINICAL_READ]);
    });

    it('also drops module-scoped permissions outside the plan', () => {
      const filtered = filterPermissionRecordsByCeiling(
        [
          { id: '1', name: PERMISSIONS.LAB_READ },
          { id: '2', name: PERMISSIONS.PROFILE_READ },
          { id: '3', name: PERMISSIONS.PHARMACY_READ }],
        { roles: [ROLES.FACILITY_ADMIN] },
        new Set(['lab-workflows'])
      );
      expect(filtered.map((entry) => entry.name)).toEqual([
        PERMISSIONS.LAB_READ,
        PERMISSIONS.PROFILE_READ]);
    });
  });

  describe('isRoleWithinActorCeiling', () => {
    it('rejects higher-ranked built-in roles', () => {
      expect(
        isRoleWithinActorCeiling(
          { name: ROLES.TENANT_ADMIN },
          { roles: [ROLES.FACILITY_ADMIN] }
        )
      ).toBe(false);
    });

    it('accepts custom roles whose permissions are within the ceiling', () => {
      expect(
        isRoleWithinActorCeiling(
          {
            name: 'WARD_CLERK',
            permissions: [
              { permission: { name: PERMISSIONS.PATIENT_READ } },
              { permission: { name: PERMISSIONS.PROFILE_READ } }]},
          { roles: [ROLES.FACILITY_ADMIN] }
        )
      ).toBe(true);
    });

    it('does not invent built-in packs for empty custom roles named like system roles', () => {
      expect(
        isRoleWithinActorCeiling(
          {
            name: 'DOCTOR',
            permissions: []},
          { roles: [ROLES.FACILITY_ADMIN] }
        )
      ).toBe(true);
    });

    it('rejects custom roles that include above-ceiling permissions', () => {
      expect(
        isRoleWithinActorCeiling(
          {
            name: 'CUSTOM_ADMIN',
            permissions: [{ permission: { name: PERMISSIONS.PLATFORM_ADMIN } }]},
          { roles: [ROLES.TENANT_ADMIN] }
        )
      ).toBe(false);
    });
  });

  describe('buildRoleScopeWhere', () => {
    it('includes tenant-wide and facility roles when facility scoped', () => {
      expect(
        buildRoleScopeWhere({
          tenant_id: 'tenant-1',
          facility_id: 'facility-1'})
      ).toEqual({
        deleted_at: null,
        tenant_id: 'tenant-1',
        OR: [{ facility_id: 'facility-1' }, { facility_id: null }]});
    });

    it('filters by tenant only when facility is absent', () => {
      expect(buildRoleScopeWhere({ tenant_id: 'tenant-1' })).toEqual({
        deleted_at: null,
        tenant_id: 'tenant-1'});
    });

    it('excludes tenant-wide roles for facility-only actors', () => {
      expect(
        buildRoleScopeWhere(
          { tenant_id: 'tenant-1', facility_id: 'facility-1' },
          { includeTenantWide: false }
        )
      ).toEqual({
        deleted_at: null,
        tenant_id: 'tenant-1',
        facility_id: 'facility-1'});
    });

    it('supports explicit tenant and facility roleScope filters', () => {
      expect(
        buildRoleScopeWhere(
          { tenant_id: 'tenant-1', facility_id: 'facility-1' },
          { roleScope: 'tenant' }
        )
      ).toEqual({
        deleted_at: null,
        tenant_id: 'tenant-1',
        facility_id: null});
      expect(
        buildRoleScopeWhere(
          { tenant_id: 'tenant-1', facility_id: 'facility-1' },
          { roleScope: 'facility' }
        )
      ).toEqual({
        deleted_at: null,
        tenant_id: 'tenant-1',
        facility_id: 'facility-1'});
    });
  });

  describe('ROLE_PERMISSIONS hierarchy', () => {
    it('keeps facility admin below tenant admin', () => {
      const facility = new Set(ROLE_PERMISSIONS[ROLES.FACILITY_ADMIN] || []);
      const tenant = new Set(ROLE_PERMISSIONS[ROLES.TENANT_ADMIN] || []);
      expect(facility.has(PERMISSIONS.TENANT_ADMIN)).toBe(false);
      expect(tenant.has(PERMISSIONS.TENANT_ADMIN)).toBe(true);
      expect(tenant.has(PERMISSIONS.PLATFORM_ADMIN)).toBe(false);
    });
  });
});
