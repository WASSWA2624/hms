/**
 * Actor permission ceiling helpers for role create / assign flows.
 *
 * Admins may only grant permissions (and assign roles) within the union of
 * permissions implied by their own roles — never above their level.
 */

const prisma = require('@prisma/client');
const { ROLES } = require('@config/roles');
const { PERMISSIONS, ROLE_PERMISSIONS } = require('@config/permissions');
const { HttpError } = require('@lib/errors');
const { getUserPermissions } = require('@middlewares/auth.middleware');
const {
  getRoleNames,
  userHasSuperAdminRole,
  userHasPlatformOwnerRole,
} = require('@lib/authorization/effective-access');
const { resolveIdentifierForPayload } = require('@lib/billing/identifiers');
const { isUuidLike } = require('@lib/identifiers/sanitize-friendly-ids');
const {
  filterPermissionRecordsByPlanModules,
  isPermissionAllowedByPlan,
  normalizeEnabledModuleSet,
} = require('@lib/authorization/permission-module-map');
const {
  assertPermissionNamesIncludeRequiredReads,
} = require('@lib/authorization/permission-read-dependency');
const {
  resolveTenantModuleEntitlements,
} = require('@lib/subscriptions/tenant-entitlements');

const ACCESS_ADMIN_ROLES = new Set([
  ROLES.PLATFORM_OWNER,
  ROLES.PLATFORM_ADMIN,
  ROLES.TENANT_ADMIN,
  ROLES.FACILITY_ADMIN,
  ROLES.OPERATIONS,
  ROLES.HR,
]);

const ROLE_RANK = Object.freeze({
  [ROLES.PLATFORM_OWNER]: 120,
  [ROLES.PLATFORM_ADMIN]: 100,
  [ROLES.TENANT_ADMIN]: 80,
  // HR manages facility access like facility admin (assignment ceiling / rank).
  [ROLES.FACILITY_ADMIN]: 60,
  [ROLES.HR]: 60,
  [ROLES.OPERATIONS]: 40,
});

const PLATFORM_ADMIN_MANAGED_ROLES = new Set([
  ROLES.PLATFORM_OWNER,
  ROLES.PLATFORM_ADMIN,
]);

/** Elevation keys that facility managers (HR / facility admin) must not grant. */
const ADMIN_RIGHTS_PERMISSIONS = new Set([
  PERMISSIONS.PLATFORM_OWNER,
  PERMISSIONS.PLATFORM_ADMIN,
  PERMISSIONS.TENANT_ADMIN,
  PERMISSIONS.FACILITY_ADMIN,
]);

/** Built-in admin roles facility managers must not assign. */
const ADMIN_RIGHTS_ROLES = new Set([
  ROLES.PLATFORM_OWNER,
  ROLES.PLATFORM_ADMIN,
  ROLES.TENANT_ADMIN,
  ROLES.FACILITY_ADMIN,
]);

const CATALOG_PERMISSION_NAMES = new Set(Object.values(PERMISSIONS));

const nonAdminPermissionNames = () =>
  Object.values(PERMISSIONS).filter(
    (name) => !ADMIN_RIGHTS_PERMISSIONS.has(name)
  );

const text = (value) => String(value || '').trim();

const loadPermissionByIdentifier = async (permissionId) => {
  const resolvedId = await resolveIdentifierForPayload({
    value: permissionId,
    model: 'permission',
    field: 'permission_id',
  });
  const permission = await prisma.permission.findFirst({
    where: { id: resolvedId, deleted_at: null },
    select: { id: true, name: true, tenant_id: true },
  });
  if (!permission) {
    throw new HttpError('errors.permission.not_found', 404);
  }
  return permission;
};

/**
 * Read-dependency guard without actor ceiling (incremental assign).
 */
const assertPermissionIdHasRequiredRead = async (
  permissionId,
  existingPermissionNames = []
) => {
  const permission = await loadPermissionByIdentifier(permissionId);
  assertPermissionNamesIncludeRequiredReads([permission.name], {
    existingPermissionNames,
  });
  return permission;
};

const normalizeRoleName = (entry) => {
  if (typeof entry === 'string') {
    return entry.trim().toUpperCase();
  }
  if (entry && typeof entry === 'object') {
    return text(entry.name || entry.role_name || entry.role?.name).toUpperCase();
  }
  return text(entry).toUpperCase();
};

const resolveActorRoleNames = (user = {}) => {
  const roles = Array.isArray(user.roles) ? user.roles : [user.role];
  return [...new Set(roles.map(normalizeRoleName).filter(Boolean))];
};

const hasElevatedAccessAdminRole = (roleNames = []) => {
  const roles = roleNames instanceof Set ? roleNames : new Set(roleNames);
  return (
    roles.has(ROLES.PLATFORM_OWNER) ||
    roles.has(ROLES.PLATFORM_ADMIN) ||
    roles.has(ROLES.TENANT_ADMIN)
  );
};

/**
 * Facility-bound access managers (facility admin / HR) — not tenant/platform.
 * Pins role mutations to the actor facility and allows reuse of tenant defaults.
 */
const isFacilityScopedAccessActor = (user = {}) => {
  const roles = new Set(resolveActorRoleNames(user));
  if (hasElevatedAccessAdminRole(roles)) {
    return false;
  }
  if (roles.has(ROLES.FACILITY_ADMIN) || roles.has(ROLES.HR)) {
    return true;
  }
  // Prefer explicit JWT permission strings — avoid getUserPermissions here so
  // workspace lookups cannot recurse through effective-access during list loads.
  const tokenPermissions = new Set(
    (Array.isArray(user.permissions) ? user.permissions : [])
      .map((entry) =>
        typeof entry === 'string'
          ? text(entry)
          : text(entry?.name || entry?.permission?.name || entry?.code)
      )
      .filter(Boolean)
  );
  return (
    tokenPermissions.has(PERMISSIONS.HR_WRITE) ||
    tokenPermissions.has(PERMISSIONS.FACILITY_ADMIN)
  );
};

const isCatalogProtectedRoleName = (roleName) => {
  const normalized = normalizeRoleName(roleName);
  return Boolean(normalized && ROLE_PERMISSIONS[normalized]);
};

const isCatalogProtectedPermissionName = (permissionName) => {
  const name = text(permissionName);
  return Boolean(name && CATALOG_PERMISSION_NAMES.has(name));
};

const resolveActorMaxRank = (user = {}) => {
  const ranks = resolveActorRoleNames(user).map((role) => ROLE_RANK[role] || 0);
  return ranks.length > 0 ? Math.max(...ranks) : 0;
};

const resolveActorAssignablePermissionNames = (user = {}) => {
  const roleNames = resolveActorRoleNames(user);
  // Platform owners keep the full assignment ceiling, including rights that
  // manage super/platform admins. Super admins stay below that owner tier.
  if (roleNames.includes(ROLES.PLATFORM_OWNER)) {
    return new Set(ROLE_PERMISSIONS[ROLES.PLATFORM_OWNER] || []);
  }
  if (roleNames.includes(ROLES.PLATFORM_ADMIN)) {
    return new Set(ROLE_PERMISSIONS[ROLES.PLATFORM_ADMIN] || []);
  }

  // Tenant admins outrank facility managers, so they grant at least the same
  // non-admin catalog; their own session rights keep tenant and facility admin
  // grantable. Plan modules still gate the catalog.
  if (roleNames.includes(ROLES.TENANT_ADMIN)) {
    return new Set([...nonAdminPermissionNames(), ...getUserPermissions(user)]);
  }

  // Facility HR / facility admin: grant any non-admin permission (plan modules
  // still gate the catalog). Do not fall through to JWT shell packs.
  if (isFacilityScopedAccessActor(user)) {
    return new Set(nonAdminPermissionNames());
  }

  const fromContext = getUserPermissions(user);
  if (fromContext.length > 0) {
    return new Set(fromContext);
  }

  return new Set(
    roleNames.flatMap((role) => ROLE_PERMISSIONS[role] || [])
  );
};

const canActorManagePlatformAdmins = (user = {}) => {
  if (userHasPlatformOwnerRole(user)) {
    return true;
  }
  const tokenPermissions = new Set(
    (Array.isArray(user.permissions) ? user.permissions : [])
      .map((entry) =>
        typeof entry === 'string'
          ? text(entry)
          : text(entry?.name || entry?.permission?.name || entry?.code)
      )
      .filter(Boolean)
  );
  if (tokenPermissions.has(PERMISSIONS.PLATFORM_OWNER)) {
    return true;
  }
  return getUserPermissions(user).includes(PERMISSIONS.PLATFORM_OWNER);
};

const canActorGrantAdminRights = (user = {}) => {
  const roles = new Set(resolveActorRoleNames(user));
  return hasElevatedAccessAdminRole(roles) || canActorManagePlatformAdmins(user);
};

const canActorCreateTenantWideRole = (user = {}) => {
  const roles = new Set(resolveActorRoleNames(user));
  if (
    roles.has(ROLES.PLATFORM_OWNER) ||
    roles.has(ROLES.PLATFORM_ADMIN) ||
    roles.has(ROLES.TENANT_ADMIN)
  ) {
    return true;
  }
  // Facility admins (and below) may only create facility-scoped roles.
  return false;
};

const canActorCreatePlatformRole = (user = {}) => {
  // Match FE canCreateTenant / Platform radio: elevated role or platform:admin.
  if (userHasSuperAdminRole(user)) {
    return true;
  }
  if (getRoleNames(user).includes(ROLES.PLATFORM_ADMIN)) {
    return true;
  }

  const tokenPermissions = new Set(
    (Array.isArray(user.permissions) ? user.permissions : [])
      .map((entry) =>
        typeof entry === 'string'
          ? text(entry)
          : text(entry?.name || entry?.permission?.name || entry?.code)
      )
      .filter(Boolean)
  );
  if (tokenPermissions.has(PERMISSIONS.PLATFORM_ADMIN)) {
    return true;
  }

  const permissions = new Set(getUserPermissions(user));
  return permissions.has(PERMISSIONS.PLATFORM_ADMIN);
};

const isPermissionNameAssignable = (permissionName, assignableSet) => {
  const name = text(permissionName);
  if (!name) {
    return false;
  }
  return assignableSet.has(name);
};

const filterPermissionRecordsByCeiling = (
  permissions = [],
  user = {},
  enabledModules = null
) => {
  const assignable = resolveActorAssignablePermissionNames(user);
  if (assignable.size === 0) {
    return [];
  }
  const withinCeiling = permissions.filter((entry) =>
    isPermissionNameAssignable(entry?.name || entry?.label, assignable)
  );
  return filterPermissionRecordsByPlanModules(withinCeiling, enabledModules);
};

/**
 * Resolve enabled module slugs for a tenant (Plan gate for assignable rights).
 * @param {string|null|undefined} tenantId
 * @returns {Promise<Set<string>|null>} null when tenant is unknown (skip plan filter)
 */
const resolveAssignablePlanModules = async (tenantId) => {
  if (!tenantId) {
    return null;
  }
  const entitlements = await resolveTenantModuleEntitlements(tenantId);
  return normalizeEnabledModuleSet(entitlements);
};

const collectRolePermissionNames = (role = {}) => {
  // When permission joins were loaded (even if empty), trust the DB — do not
  // invent built-in packs for custom roles that happen to share a name.
  if (Array.isArray(role.permissions)) {
    return role.permissions
      .map((entry) => entry?.permission?.name || entry?.name || entry?.permission_name)
      .map(text)
      .filter(Boolean);
  }

  const roleName = normalizeRoleName(role.name);
  return ROLE_PERMISSIONS[roleName] || [];
};

const isRoleWithinActorCeiling = (role = {}, user = {}) => {
  const assignable = resolveActorAssignablePermissionNames(user);
  if (assignable.size === 0) {
    return false;
  }

  const roleName = normalizeRoleName(role.name);
  if (ADMIN_RIGHTS_ROLES.has(roleName) && !canActorGrantAdminRights(user)) {
    return false;
  }

  if (
    PLATFORM_ADMIN_MANAGED_ROLES.has(roleName) &&
    !canActorManagePlatformAdmins(user)
  ) {
    return false;
  }

  const roleRank = ROLE_RANK[roleName];
  if (roleRank != null && roleRank > resolveActorMaxRank(user)) {
    return false;
  }

  const permissionNames = collectRolePermissionNames(role);
  if (permissionNames.length === 0) {
    return true;
  }

  return permissionNames.every((name) => assignable.has(name));
};

const filterRoleRecordsByCeiling = (roles = [], user = {}) =>
  roles.filter((role) => isRoleWithinActorCeiling(role, user));

const assertPermissionNamesAssignable = (
  permissionNames = [],
  user = {},
  enabledModules = null,
  { existingPermissionNames = [] } = {}
) => {
  const assignable = resolveActorAssignablePermissionNames(user);
  const uniqueNames = [
    ...new Set(permissionNames.map(text).filter(Boolean)),
  ];
  const aboveCeiling = uniqueNames.filter((name) => !assignable.has(name));
  if (aboveCeiling.length > 0) {
    throw new HttpError('errors.auth.insufficient_permissions', 403, [
      {
        field: 'permission_id',
        reason: 'above_actor_ceiling',
        denied: aboveCeiling,
      },
    ]);
  }

  const outsidePlan = uniqueNames.filter(
    (name) => !isPermissionAllowedByPlan(name, enabledModules)
  );
  if (outsidePlan.length > 0) {
    throw new HttpError('errors.auth.insufficient_permissions', 403, [
      {
        field: 'permission_id',
        reason: 'module_not_entitled',
        denied: outsidePlan,
      },
    ]);
  }

  assertPermissionNamesIncludeRequiredReads(uniqueNames, {
    existingPermissionNames,
  });
};

const assertPermissionIdAssignable = async (
  permissionId,
  user = {},
  {
    tenantId = null,
    enabledModules = null,
    existingPermissionNames = [],
  } = {}
) => {
  const permission = await loadPermissionByIdentifier(permissionId);
  const planModules =
    enabledModules ??
    (await resolveAssignablePlanModules(
      tenantId || permission.tenant_id || user.tenant_id || user.tenantId || null
    ));
  assertPermissionNamesAssignable([permission.name], user, planModules, {
    existingPermissionNames,
  });
  return permission;
};

/**
 * Resolve and ceiling-check many permission identifiers in one query.
 * @returns {Promise<string[]>} Deduped permission UUIDs
 */
const assertPermissionIdsAssignable = async (
  permissionIds = [],
  user = {},
  {
    tenantId = null,
    enabledModules = null,
    existingPermissionNames = [],
  } = {}
) => {
  const unique = [
    ...new Set(
      (Array.isArray(permissionIds) ? permissionIds : [])
        .map(text)
        .filter(Boolean)
    ),
  ];
  if (unique.length === 0) {
    return [];
  }

  const uuidIds = unique.filter((id) => isUuidLike(id));
  const friendlyIds = unique.filter((id) => !isUuidLike(id));
  const orFilters = [];
  if (uuidIds.length > 0) {
    orFilters.push({ id: { in: uuidIds } });
  }
  if (friendlyIds.length > 0) {
    orFilters.push({ human_friendly_id: { in: friendlyIds } });
  }

  const permissions = await prisma.permission.findMany({
    where: {
      deleted_at: null,
      OR: orFilters,
    },
    select: { id: true, name: true, human_friendly_id: true, tenant_id: true },
  });

  const byId = new Map(permissions.map((entry) => [entry.id, entry]));
  const byFriendly = new Map(
    permissions
      .filter((entry) => entry.human_friendly_id)
      .map((entry) => [entry.human_friendly_id, entry])
  );

  const resolved = [];
  const missing = [];
  for (const identifier of unique) {
    const match = byId.get(identifier) || byFriendly.get(identifier);
    if (!match) {
      missing.push(identifier);
      continue;
    }
    resolved.push(match);
  }

  if (missing.length > 0) {
    throw new HttpError('errors.permission.not_found', 404, [
      { field: 'permission_ids', missing },
    ]);
  }

  const inferredTenantId =
    tenantId ||
    user.tenant_id ||
    user.tenantId ||
    resolved.find((entry) => entry.tenant_id)?.tenant_id ||
    null;
  const planModules =
    enabledModules ?? (await resolveAssignablePlanModules(inferredTenantId));
  assertPermissionNamesAssignable(
    resolved.map((entry) => entry.name),
    user,
    planModules,
    { existingPermissionNames }
  );

  return [...new Set(resolved.map((entry) => entry.id))];
};

const assertRoleIdAssignable = async (roleId, user = {}) => {
  const resolvedId = await resolveIdentifierForPayload({
    value: roleId,
    model: 'role',
    field: 'role_id',
  });
  const role = await prisma.role.findFirst({
    where: { id: resolvedId, deleted_at: null },
    include: {
      permissions: {
        where: { deleted_at: null },
        include: {
          permission: {
            select: { name: true },
          },
        },
      },
    },
  });
  if (!role) {
    throw new HttpError('errors.role.not_found', 404);
  }
  if (!isRoleWithinActorCeiling(role, user)) {
    throw new HttpError('errors.auth.insufficient_permissions', 403, [
      { field: 'role_id', reason: 'above_actor_ceiling' },
    ]);
  }
  return role;
};

const assertRoleScopeAllowed = async (payload = {}, user = {}) => {
  const facilityId = payload.facility_id;
  const hasFacility =
    facilityId != null && String(facilityId).trim() !== '';
  const hasTenant =
    payload.tenant_id != null && String(payload.tenant_id).trim() !== '';

  // Platform-scoped role: no tenant, no facility.
  if (!hasFacility && !hasTenant) {
    if (!canActorCreatePlatformRole(user)) {
      throw new HttpError('errors.auth.insufficient_permissions', 403, [
        { field: 'tenant_id', reason: 'platform_scope_forbidden' },
      ]);
    }
    return {
      ...payload,
      tenant_id: null,
      facility_id: null,
    };
  }

  if (!hasFacility && !canActorCreateTenantWideRole(user)) {
    throw new HttpError('errors.auth.insufficient_permissions', 403, [
      { field: 'facility_id', reason: 'facility_scope_required' },
    ]);
  }

  if (!hasFacility) {
    assertActorTenantMatches(payload.tenant_id, user);
    return payload;
  }

  const resolvedFacilityId = await resolveIdentifierForPayload({
    value: facilityId,
    model: 'facility',
    field: 'facility_id',
    nullable: true,
  });

  const facility = await prisma.facility.findFirst({
    where: { id: resolvedFacilityId, deleted_at: null },
    select: { id: true, tenant_id: true },
  });
  if (!facility) {
    throw new HttpError('errors.facility.not_found', 404);
  }

  const tenantId = payload.tenant_id;
  if (tenantId && facility.tenant_id !== tenantId) {
    throw new HttpError('errors.auth.scope_mismatch', 403, [
      { field: 'facility_id', reason: 'facility_tenant_mismatch' },
    ]);
  }

  if (isFacilityScopedAccessActor(user)) {
    const actorFacilityId = user.facility_id || user.facilityId || null;
    if (!actorFacilityId) {
      throw new HttpError('errors.auth.scope_mismatch', 403, [
        { field: 'facility_id', reason: 'actor_facility_required' },
      ]);
    }
    if (actorFacilityId !== facility.id) {
      throw new HttpError('errors.auth.scope_mismatch', 403, [
        { field: 'facility_id', reason: 'outside_actor_facility' },
      ]);
    }
  }

  const nextPayload = {
    ...payload,
    facility_id: facility.id,
    tenant_id: payload.tenant_id || facility.tenant_id,
  };
  assertActorTenantMatches(nextPayload.tenant_id, user);
  return nextPayload;
};

const assertActorTenantMatches = (tenantId, user = {}) => {
  if (userHasSuperAdminRole(user)) {
    return;
  }
  const actorTenantId = user.tenant_id || user.tenantId || null;
  if (!tenantId || !actorTenantId || tenantId !== actorTenantId) {
    throw new HttpError('errors.auth.scope_mismatch', 403, [
      { field: 'tenant_id', reason: 'outside_actor_tenant' },
    ]);
  }
};

/**
 * Ensure the actor may mutate an existing role record (ceiling + tenant/facility).
 * @param {Object} role
 * @param {Object} user
 */
const assertActorCanManageRoleRecord = (role = {}, user = {}) => {
  if (!role || !role.id) {
    throw new HttpError('errors.role.not_found', 404);
  }

  if (userHasSuperAdminRole(user)) {
    if (!isRoleWithinActorCeiling(role, user)) {
      throw new HttpError('errors.auth.insufficient_permissions', 403, [
        { field: 'role_id', reason: 'above_actor_ceiling' },
      ]);
    }
    return role;
  }

  const isPlatformRole =
    (role.tenant_id == null || String(role.tenant_id).trim() === '') &&
    (role.facility_id == null || String(role.facility_id).trim() === '');
  if (isPlatformRole) {
    if (!canActorCreatePlatformRole(user)) {
      throw new HttpError('errors.auth.insufficient_permissions', 403, [
        { field: 'tenant_id', reason: 'platform_scope_forbidden' },
      ]);
    }
    if (!isRoleWithinActorCeiling(role, user)) {
      throw new HttpError('errors.auth.insufficient_permissions', 403, [
        { field: 'role_id', reason: 'above_actor_ceiling' },
      ]);
    }
    return role;
  }

  const actorTenantId = user.tenant_id || user.tenantId || null;
  if (!actorTenantId || role.tenant_id !== actorTenantId) {
    throw new HttpError('errors.auth.scope_mismatch', 403, [
      { field: 'tenant_id', reason: 'outside_actor_tenant' },
    ]);
  }

  if (isFacilityScopedAccessActor(user)) {
    const actorFacilityId = user.facility_id || user.facilityId || null;
    if (!actorFacilityId) {
      throw new HttpError('errors.auth.scope_mismatch', 403, [
        { field: 'facility_id', reason: 'actor_facility_required' },
      ]);
    }
    if (role.facility_id !== actorFacilityId) {
      throw new HttpError('errors.auth.scope_mismatch', 403, [
        { field: 'role_id', reason: 'outside_actor_facility' },
      ]);
    }
  }

  if (!isRoleWithinActorCeiling(role, user)) {
    throw new HttpError('errors.auth.insufficient_permissions', 403, [
      { field: 'role_id', reason: 'above_actor_ceiling' },
    ]);
  }

  return role;
};

/**
 * Block mutation of seeded/system roles that catalog sync owns.
 * Platform admins may update or delete; all other actors are blocked.
 * @param {Object} role
 * @param {'update'|'delete'} [operation='delete']
 * @param {Object} [actor]
 */
const assertRoleNotSystemProtected = (
  role = {},
  operation = 'delete',
  actor = null
) => {
  const roleName = normalizeRoleName(role.name);
  const isPlatformScoped = role.tenant_id == null || role.tenant_id === undefined;
  if (!isCatalogProtectedRoleName(roleName) && !isPlatformScoped) {
    return;
  }
  if (actor && canActorCreatePlatformRole(actor)) {
    return;
  }
  throw new HttpError('errors.auth.insufficient_permissions', 403, [
    {
      field: 'role_id',
      reason: 'system_role_protected',
      role: roleName,
      operation,
    },
  ]);
};

/**
 * Block mutation of canonical / platform catalog permissions.
 * Platform admins may update or delete; all other actors are blocked.
 * @param {Object} permission
 * @param {'update'|'delete'} [operation='delete']
 * @param {Object} [actor]
 */
const assertPermissionNotSystemProtected = (
  permission = {},
  operation = 'delete',
  actor = null
) => {
  const permissionName = text(permission.name);
  const isPlatformScoped =
    permission.tenant_id == null || permission.tenant_id === undefined;
  if (!isCatalogProtectedPermissionName(permissionName) && !isPlatformScoped) {
    return;
  }
  if (actor && canActorCreatePlatformRole(actor)) {
    return;
  }
  throw new HttpError('errors.auth.insufficient_permissions', 403, [
    {
      field: 'permission_id',
      reason: 'system_permission_protected',
      permission: permissionName,
      operation,
    },
  ]);
};

/**
 * Role list/lookup where.
 *
 * - Facility-only actors: exact facility_id match (no tenant-wide roles).
 * - Tenant/platform admins: facility roles for the scope plus tenant-wide (null),
 *   unless roleScope filter narrows to tenant or facility only.
 *
 * @param {Object} scope
 * @param {Object} [options]
 * @param {boolean} [options.includeDeleted=false]
 * @param {boolean} [options.includeTenantWide=true]
 * @param {'tenant'|'facility'|null} [options.roleScope]
 */
const buildRoleScopeWhere = (
  scope = {},
  {
    includeDeleted = false,
    includeTenantWide = true,
    roleScope = null,
    includePlatformCatalog = true,
  } = {}
) => {
  const where = {};
  if (!includeDeleted) {
    where.deleted_at = null;
  }

  const normalizedScope = String(roleScope || '')
    .trim()
    .toLowerCase();

  const platformClause =
    includePlatformCatalog && normalizedScope !== 'facility'
      ? { tenant_id: null, facility_id: null }
      : null;

  if (normalizedScope === 'platform') {
    where.tenant_id = null;
    where.facility_id = null;
    return where;
  }

  if (normalizedScope === 'tenant') {
    if (scope.tenant_id) {
      const tenantClause = { tenant_id: scope.tenant_id, facility_id: null };
      if (platformClause) {
        where.OR = [platformClause, tenantClause];
      } else {
        Object.assign(where, tenantClause);
      }
    } else if (platformClause) {
      Object.assign(where, platformClause);
    }
    return where;
  }

  if (normalizedScope === 'facility') {
    if (scope.facility_id) {
      where.facility_id = scope.facility_id;
      if (scope.tenant_id) {
        where.tenant_id = scope.tenant_id;
      }
    } else {
      where.NOT = { facility_id: null };
      if (scope.tenant_id) {
        where.tenant_id = scope.tenant_id;
      }
    }
    return where;
  }

  if (scope.facility_id) {
    const facilityClause = includeTenantWide
      ? {
          OR: [
            { facility_id: scope.facility_id },
            ...(scope.tenant_id
              ? [{ tenant_id: scope.tenant_id, facility_id: null }]
              : []),
          ],
        }
      : { facility_id: scope.facility_id };
    if (platformClause) {
      where.OR = [platformClause, facilityClause];
    } else {
      Object.assign(where, facilityClause);
      if (scope.tenant_id && !includeTenantWide) {
        where.tenant_id = scope.tenant_id;
      }
    }
    return where;
  }

  if (scope.tenant_id) {
    const tenantClause = { tenant_id: scope.tenant_id };
    if (platformClause) {
      where.OR = [platformClause, tenantClause];
    } else {
      where.tenant_id = scope.tenant_id;
    }
    return where;
  }

  if (platformClause) {
    Object.assign(where, platformClause);
  }
  return where;
};

module.exports = {
  ACCESS_ADMIN_ROLES,
  ADMIN_RIGHTS_PERMISSIONS,
  ADMIN_RIGHTS_ROLES,
  ROLE_RANK,
  PLATFORM_ADMIN_MANAGED_ROLES,
  assertActorCanManageRoleRecord,
  assertPermissionIdAssignable,
  assertPermissionIdHasRequiredRead,
  assertPermissionIdsAssignable,
  assertPermissionNamesAssignable,
  assertPermissionNotSystemProtected,
  assertRoleIdAssignable,
  assertRoleNotSystemProtected,
  assertRoleScopeAllowed,
  assertActorTenantMatches,
  buildRoleScopeWhere,
  canActorCreatePlatformRole,
  canActorCreateTenantWideRole,
  canActorGrantAdminRights,
  canActorManagePlatformAdmins,
  collectRolePermissionNames,
  filterPermissionRecordsByCeiling,
  filterRoleRecordsByCeiling,
  isCatalogProtectedPermissionName,
  isCatalogProtectedRoleName,
  isFacilityScopedAccessActor,
  isRoleWithinActorCeiling,
  resolveActorAssignablePermissionNames,
  resolveActorMaxRank,
  resolveActorRoleNames,
  resolveAssignablePlanModules,
};
