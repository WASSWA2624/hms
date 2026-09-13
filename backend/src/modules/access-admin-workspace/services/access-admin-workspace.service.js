const { HttpError } = require('@lib/errors');
const { hashPassword } = require('@lib/crypto/hashPassword');
const { resolvePublicIdentifier, resolveIdentifierForFilter } = require('@lib/billing/identifiers');
const { ROLES } = require('@config/roles');
const { ROLE_PERMISSIONS, PERMISSIONS } = require('@config/permissions');
const { resolveRequestPermissionNames } = require('@lib/authorization/effective-access');
const {
  ensureTenantAccessCatalog,
  ensureTenantPermissionCatalog,
  restoreTenantRolePermissionDefaults,
} = require('@lib/authorization/permission-catalog-sync');
const { clearLiveAccessCaches } = require('@middlewares/live-access.middleware');
const {
  filterPermissionRecordsByCeiling,
  filterRoleRecordsByCeiling,
  canActorCreateTenantWideRole,
  isFacilityScopedAccessActor,
  isCatalogProtectedRoleName,
  isCatalogProtectedPermissionName,
  resolveAssignablePlanModules,
} = require('@lib/authorization/assignable-access');
const { createAuditLog } = require('@lib/audit');
const { provisionTrialSubscription } = require('@lib/subscriptions/tenant-onboarding');
const { listPendingPaymentRequests, activatePaymentRequest, rejectPaymentRequest } = require('@lib/subscriptions/subscription-payment-request');
const authRepository = require('@repositories/auth/auth.repository');
const repository = require('@repositories/access-admin-workspace/access-admin-workspace.repository');
const { logger } = require('@lib/logging');
const { sendAccountApprovedEmail } = require('@services/auth/auth.service');

const DEFAULT_DEMO_RESET_PASSWORD = process.env.DEMO_RESET_PASSWORD || 'Hosspi@2624.';

const ACCESS_RESOURCES = [
  'users',
  'roles',
  'permissions',
  'user-roles',
  'role-permissions',
  'demo-users',
  'module-entitlements',
  'registration-follow-ups',
  'subscription-payment-requests',
];

const ACCESS_PANELS = [
  { id: 'overview', label_key: 'access_admin.panels.overview', default_resource: 'users' },
  { id: 'directory', label_key: 'access_admin.panels.directory', default_resource: 'users' },
  { id: 'roles', label_key: 'access_admin.panels.roles', default_resource: 'roles' },
  { id: 'permissions', label_key: 'access_admin.panels.permissions', default_resource: 'permissions' },
  { id: 'entitlements', label_key: 'access_admin.panels.entitlements', default_resource: 'module-entitlements' },
  { id: 'registrations', label_key: 'access_admin.panels.registrations', default_resource: 'registration-follow-ups' },
  { id: 'payments', label_key: 'access_admin.panels.payments', default_resource: 'subscription-payment-requests' },
  { id: 'demo', label_key: 'access_admin.panels.demo', default_resource: 'demo-users' },
];

const PANEL_RESOURCE_MAP = ACCESS_PANELS.reduce((acc, panel) => {
  acc[panel.id] = panel.default_resource;
  return acc;
}, {});

const RESOURCE_PANEL_MAP = {
  users: 'directory',
  roles: 'roles',
  permissions: 'permissions',
  'user-roles': 'roles',
  'role-permissions': 'permissions',
  'demo-users': 'demo',
  'module-entitlements': 'entitlements',
  'registration-follow-ups': 'registrations',
  'subscription-payment-requests': 'payments',
};

const CLINICAL_FLOW_ROLES = new Set([
  ROLES.RECEPTIONIST,
  ROLES.NURSE,
  ROLES.DOCTOR,
  ROLES.OPD_DOCTOR,
  ROLES.ICU_DOCTOR,
  ROLES.SURGEON,
  ROLES.BILLING,
  ROLES.PHARMACY_BILLING,
  ROLES.LAB_TECH,
  ROLES.RADIOLOGY_TECH,
  ROLES.PHARMACIST,
  ROLES.WARD_MANAGER,
  ROLES.ICU_MANAGER,
]);

const SYSTEM_CRITICAL_ROLES = new Set(Object.keys(ROLE_PERMISSIONS));

const text = (value) => String(value || '').trim();
const safePublicId = (...values) => resolvePublicIdentifier(...values) || null;

/** Prefer friendly IDs for UI, but never drop the raw UUID (needed for mutations). */
const publicOrRawId = (...values) => {
  const publicId = safePublicId(...values);
  if (publicId) {
    return publicId;
  }
  for (const value of values) {
    const normalized = String(value || '').trim();
    if (normalized) {
      return normalized;
    }
  }
  return null;
};

const roleList = (user = {}) => {
  const roles = Array.isArray(user.roles) ? user.roles : [user.role];
  return roles
    .map((entry) => {
      if (typeof entry === 'string') {
        return entry.trim().toUpperCase();
      }
      if (entry && typeof entry === 'object') {
        return String(entry.name || entry.role_name || entry.role?.name || '').trim().toUpperCase();
      }
      return String(entry || '').trim().toUpperCase();
    })
    .filter(Boolean);
};

const buildPagination = (page, limit, total) => ({
  page,
  limit,
  total,
  totalPages: limit > 0 ? Math.ceil(total / limit) : 0,
  hasNextPage: page * limit < total,
  hasPreviousPage: page > 1,
});

// Permissions are the only determinant of access: custom roles carrying the
// same grants as predefined admin roles must behave identically.
const permissionList = (user = {}) => resolveRequestPermissionNames(user);

const ADMIN_WRITE_PERMISSIONS = new Set([
  PERMISSIONS.PLATFORM_OWNER,
  PERMISSIONS.PLATFORM_ADMIN,
  PERMISSIONS.TENANT_ADMIN,
  PERMISSIONS.FACILITY_ADMIN,
  PERMISSIONS.HR_WRITE,
]);

const canWriteAccess = (user = {}) => {
  const writeRoles = new Set([
    ROLES.PLATFORM_OWNER,
    ROLES.PLATFORM_ADMIN,
    ROLES.TENANT_ADMIN,
    ROLES.FACILITY_ADMIN,
    ROLES.OPERATIONS,
    ROLES.HR,
  ]);
  return (
    roleList(user).some((entry) => writeRoles.has(entry)) ||
    permissionList(user).some((permission) => ADMIN_WRITE_PERMISSIONS.has(permission))
  );
};

const isSuperAdmin = (user = {}) =>
  roleList(user).includes(ROLES.PLATFORM_OWNER) ||
  roleList(user).includes(ROLES.PLATFORM_ADMIN) ||
  permissionList(user).includes(PERMISSIONS.PLATFORM_ADMIN) ||
  permissionList(user).includes(PERMISSIONS.PLATFORM_OWNER);

const hasTenantAdminScope = (user = {}) =>
  roleList(user).includes(ROLES.TENANT_ADMIN) ||
  permissionList(user).includes(PERMISSIONS.TENANT_ADMIN);

const requireSuperAdmin = (user = {}) => {
  if (!isSuperAdmin(user)) {
    throw new HttpError('errors.auth.insufficient_permissions', 403);
  }
};

const serializeUser = (record) => {
  if (!record) return null;

  const profile = record.profile || null;
  const staffProfile = record.staff_profile || null;
  const roleAssignments = Array.isArray(record.roles) ? record.roles : [];
  const roles = roleAssignments
    .map((entry) => {
      const role = entry?.role;
      if (!role) return null;
      return {
        id: safePublicId(role.human_friendly_id, role.id),
        name: role.name,
        user_role_id: safePublicId(entry.human_friendly_id, entry.id),
        resource_uuid: role.id,
      };
    })
    .filter(Boolean);

  return {
    id: safePublicId(record.human_friendly_id, record.id),
    resource_uuid: record.id,
    display_id: safePublicId(record.human_friendly_id, record.id),
    email: record.email,
    phone: record.phone || null,
    position_title: record.position_title,
    status: record.status,
    tenant_id: record.tenant_id || null,
    tenant_name: record.tenant?.name || null,
    facility_id: record.facility_id || null,
    facility_name: record.facility?.name || null,
    profile_name: profile
      ? [profile.first_name, profile.last_name].filter(Boolean).join(' ').trim() || null
      : null,
    first_name: profile?.first_name || null,
    last_name: profile?.last_name || null,
    staff_profile_id: staffProfile
      ? safePublicId(staffProfile.human_friendly_id, staffProfile.id)
      : null,
    roles,
    role_count: roles.length,
    is_demo: repository.isDemoUser(record),
    is_active: !record.deleted_at && String(record.status || '').toUpperCase() === 'ACTIVE',
    deleted_at: record.deleted_at || null,
    updated_at: record.updated_at,
  };
};

const serializeRole = (record) => {
  if (!record) return null;

  const permissions = (record.permissions || [])
    .map((entry) => entry.permission)
    .filter(Boolean)
    .map((permission) => ({
      id: safePublicId(permission.human_friendly_id, permission.id),
      name: permission.name,
    }));

  const roleName = String(record.name || '').trim().toUpperCase();
  const permissionCount =
    typeof record._count?.permissions === 'number'
      ? record._count.permissions
      : permissions.length;

  return {
    id: safePublicId(record.human_friendly_id, record.id),
    resource_uuid: record.id,
    display_id: safePublicId(record.human_friendly_id, record.id),
    name: record.name,
    display_name: record.display_name || record.name,
    description: record.description || null,
    tenant_id: record.tenant_id || null,
    tenant_name: record.tenant_name || null,
    facility_id: record.facility_id || null,
    facility_name: record.facility_name || null,
    scope: record.facility_id
      ? 'facility'
      : record.tenant_id
        ? 'tenant'
        : 'platform',
    permission_count: permissionCount,
    // List payloads stay lean; load permission rows on edit via role-permissions.
    permissions,
    user_count: record._count?.users || 0,
    is_clinical_flow_role: CLINICAL_FLOW_ROLES.has(roleName),
    is_system_critical:
      SYSTEM_CRITICAL_ROLES.has(roleName) || isCatalogProtectedRoleName(roleName),
    is_platform_catalog: record.tenant_id == null,
    deleted_at: record.deleted_at || null,
    updated_at: record.updated_at,
  };
};

const serializePermission = (record) => {
  if (!record) return null;

  return {
    id: safePublicId(record.human_friendly_id, record.id),
    resource_uuid: record.id,
    display_id: safePublicId(record.human_friendly_id, record.id),
    name: record.name,
    display_name: record.display_name || record.name,
    description: record.description || null,
    tenant_id: record.tenant_id || null,
    tenant_name: record.tenant_name || null,
    role_count: record._count?.roles || 0,
    user_count: record._count?.users || 0,
    is_system_critical: isCatalogProtectedPermissionName(record.name),
    is_platform_catalog: record.tenant_id == null,
    updated_at: record.updated_at,
  };
};

const serializeUserRole = (record) => {
  if (!record) return null;

  return {
    id: safePublicId(record.human_friendly_id, record.id),
    resource_uuid: record.id,
    display_id: safePublicId(record.human_friendly_id, record.id),
    user_id: safePublicId(record.user?.human_friendly_id, record.user_id),
    user_label: record.user?.email || record.user?.position_title || null,
    role_id: safePublicId(record.role?.human_friendly_id, record.role_id),
    role_name: record.role?.name || null,
    tenant_id: record.tenant_id || null,
    facility_id: record.facility_id || null,
    updated_at: record.updated_at,
  };
};

const serializeRolePermission = (record) => {
  if (!record) return null;

  return {
    id: safePublicId(record.human_friendly_id, record.id),
    resource_uuid: record.id,
    display_id: safePublicId(record.human_friendly_id, record.id),
    role_id: safePublicId(record.role?.human_friendly_id, record.role_id),
    role_name: record.role?.name || null,
    permission_id: safePublicId(record.permission?.human_friendly_id, record.permission_id),
    permission_name: record.permission?.name || null,
    updated_at: record.updated_at,
  };
};

const serializeModuleEntitlement = (record, subscription = null) => {
  if (!record) return null;

  const module = record.module || {};

  return {
    id: safePublicId(record.human_friendly_id, record.id),
    resource_uuid: record.id,
    display_id: safePublicId(record.human_friendly_id, record.id),
    module_id: safePublicId(module.human_friendly_id, record.module_id),
    module_label: module.name || null,
    module_slug: module.slug || null,
    module_group: module.module_group || null,
    subscription_id: subscription
      ? safePublicId(subscription.human_friendly_id, subscription.id)
      : null,
    plan_label: subscription?.plan?.name || null,
    is_active: Boolean(record.is_active),
    entitlement_denied: Boolean(record.entitlement_denied),
    entitlement_denial_reason: record.entitlement_denial_reason || null,
    updated_at: record.updated_at,
  };
};

const serializeRegistrationFollowUp = (record = {}) => {
  const user = record.user || {};
  const tenant = record.tenant || user.tenant || null;
  const facility = record.facility || user.facility || null;
  const rawStatus =
    record.account_status || record.status || user.status || 'PENDING';
  const normalizedStatus = String(rawStatus).trim().toUpperCase();
  const status =
    normalizedStatus === 'ACTIVE'
      ? 'ACTIVE'
      : normalizedStatus === 'INACTIVE'
        ? 'INACTIVE'
        : 'PENDING_APPROVAL';
  const userPublicId = publicOrRawId(user.human_friendly_id, user.id);
  const followUpPublicId = publicOrRawId(record.human_friendly_id, record.id);

  return {
    id: userPublicId,
    display_id: followUpPublicId,
    user_id: userPublicId,
    resource_uuid: user.id || null,
    email: record.email || user.email || null,
    phone: record.phone || user.phone || null,
    admin_name: record.admin_name || null,
    facility_name: record.facility_name || facility?.name || null,
    tenant_name: tenant?.name || record.facility_name || null,
    facility_type: record.facility_type || facility?.facility_type || null,
    status,
    registered_at: record.first_registered_at || record.created_at || null,
    email_verified_at: user.email_verified_at || null,
    location: record.location || null,
    interests: record.interests || null,
    updated_at: record.updated_at || user.updated_at || null,
  };
};

const collectAssignedRolePermissionNames = (role = {}) => {
  if (Array.isArray(role.permissions)) {
    return role.permissions
      .map((entry) => entry?.permission?.name || entry?.name || entry?.permission_name)
      .map((value) => String(value || '').trim())
      .filter(Boolean);
  }

  const roleName = String(role.name || '').trim().toUpperCase();
  return ROLE_PERMISSIONS[roleName] || [];
};

const serializeUserDetail = (record) => {
  const base = serializeUser(record);
  if (!base) return null;

  const directPermissions = (record.permissions || [])
    .map((entry) => entry.permission)
    .filter(Boolean)
    .map((permission) => ({
      id: safePublicId(permission.human_friendly_id, permission.id),
      name: permission.name,
      resource_uuid: permission.id,
    }));

  const permissionsByRole = (record.roles || [])
    .map((entry) => {
      const role = entry?.role;
      if (!role) return null;
      const roleName = String(role.name || '').trim().toUpperCase();
      const permissionNames = collectAssignedRolePermissionNames(role);
      return {
        role_id: safePublicId(role.human_friendly_id, role.id),
        role_name: roleName,
        user_role_id: safePublicId(entry.human_friendly_id, entry.id),
        resource_uuid: role.id,
        permissions: permissionNames.map((name) => ({
          name,
          source_role: roleName,
        })),
      };
    })
    .filter(Boolean);

  const rolePermissions = permissionsByRole.flatMap((group) => group.permissions);

  const effectivePermissionNames = new Set([
    ...directPermissions.map((entry) => entry.name),
    ...rolePermissions.map((entry) => entry.name),
  ]);

  return {
    ...base,
    roles: permissionsByRole.map((group) => ({
      id: group.role_id,
      name: group.role_name,
      user_role_id: group.user_role_id,
      resource_uuid: group.resource_uuid,
    })),
    direct_permissions: directPermissions,
    effective_permissions: [...effectivePermissionNames].sort(),
    role_permission_preview: rolePermissions,
    permissions_by_role: permissionsByRole,
  };
};

const buildLookups = (records = {}, user = null, enabledModules = null) => {
  // Assigners only see roles they can grant; read-only viewers keep the full
  // in-scope directory for filtering (assignment APIs re-check ceiling).
  const roles =
    user && (isFacilityScopedAccessActor(user) || canWriteAccess(user))
      ? filterRoleRecordsByCeiling(records.roles || [], user)
      : records.roles || [];
  const permissions = user
    ? filterPermissionRecordsByCeiling(
        records.permissions || [],
        user,
        enabledModules
      )
    : records.permissions || [];

  return {
    tenants: (records.tenants || []).map((entry) => ({
      id: safePublicId(entry.human_friendly_id, entry.id),
      label: entry.name,
    })),
    facilities: (records.facilities || []).map((entry) => ({
      id: safePublicId(entry.human_friendly_id, entry.id),
      label: entry.name,
      tenant_id: safePublicId(entry.tenant_id),
      facility_type: entry.facility_type || null,
    })),
    roles: roles.map((entry) => ({
      // UUID like permissions: role friendly ids restart per tenant and collide
      // with platform catalog roles, so assigning by them can pick another role.
      id: entry.id,
      human_friendly_id: safePublicId(entry.human_friendly_id, entry.id),
      label: entry.name,
      display_name: entry.display_name || entry.name,
      facility_id: safePublicId(entry.facility_id),
      scope: entry.facility_id ? 'facility' : 'tenant',
      permission_count:
        entry._count?.permissions ??
        (Array.isArray(entry.permissions) ? entry.permissions.length : 0),
    })),
    permissions: permissions.map((entry) => ({
      // Prefer UUID for assignment/sync. Friendly ids can collide and break PUT.
      id: entry.id,
      label: entry.name,
      display_name: entry.display_name || entry.name,
      description: entry.description || null,
      human_friendly_id: safePublicId(entry.human_friendly_id, entry.id),
    })),
    user_statuses: ['ACTIVE', 'INACTIVE', 'SUSPENDED', 'PENDING'],
    clinical_flow_roles: [...CLINICAL_FLOW_ROLES],
  };
};

const buildOverview = (summary = {}, subscriptionRecord = null) => ({
  active_users: summary.active_users || 0,
  inactive_users: summary.inactive_users || 0,
  total_roles: summary.total_roles || 0,
  total_permissions: summary.total_permissions || 0,
  total_assignments: summary.total_assignments || 0,
  demo_users: summary.demo_users || 0,
  subscription_plan: subscriptionRecord?.plan?.name || null,
  active_modules_count: (subscriptionRecord?.module_subscriptions || []).filter(
    (entry) => entry.is_active && !entry.entitlement_denied
  ).length,
});

const resolveResource = (query = {}) => {
  const panel = text(query.panel).toLowerCase() || 'overview';
  const resource = text(query.resource).toLowerCase() || PANEL_RESOURCE_MAP[panel] || 'users';
  if (!ACCESS_RESOURCES.includes(resource)) {
    throw new HttpError('errors.validation.invalid', 400, [{ field: 'resource' }]);
  }
  return { panel, resource };
};

const serializeItems = (resource, items = [], subscription = null) => {
  switch (resource) {
    case 'users':
    case 'demo-users':
      return items.map(serializeUser);
    case 'roles':
      return items.map(serializeRole);
    case 'permissions':
      return items.map(serializePermission);
    case 'user-roles':
      return items.map(serializeUserRole);
    case 'role-permissions':
      return items.map(serializeRolePermission);
    case 'module-entitlements':
      return items.map((entry) => serializeModuleEntitlement(entry, subscription));
    case 'registration-follow-ups':
      return items.map(serializeRegistrationFollowUp);
    case 'subscription-payment-requests':
      return items;
    default:
      return [];
  }
};

const findItemsForResource = async (
  resource,
  scope,
  filters,
  skip,
  take,
  options = {}
) => {
  if (resource === 'demo-users') {
    return repository.findUsers({
      scope,
      filters: { ...filters, is_demo: true },
      skip,
      take,
    });
  }

  if (resource === 'module-entitlements') {
    const result = await repository.findModuleEntitlements(scope);
    const items = result.items || [];
    return {
      items,
      total: result.total || items.length,
      subscription: result.subscription || null,
    };
  }

  if (resource === 'registration-follow-ups') {
    const result = await authRepository.findPendingRegistrationApprovals({
      skip,
      take,
      search: filters.search,
    });
    return {
      items: result.items || [],
      total: result.total || 0,
    };
  }

  if (resource === 'subscription-payment-requests') {
    const items = await listPendingPaymentRequests();
    const search = String(filters.search || '').trim().toLowerCase();
    const filtered = search
      ? items.filter((entry) => {
          const haystack = [
            entry.tenant_label,
            entry.plan_label,
            entry.reference,
            entry.submitted_by_email,
          ]
            .filter(Boolean)
            .join(' ')
            .toLowerCase();
          return haystack.includes(search);
        })
      : items;
    return {
      items: filtered.slice(skip, skip + take),
      total: filtered.length,
    };
  }

  if (resource === 'roles') {
    return repository.findRoles({
      scope,
      filters,
      skip,
      take,
      includeTenantWide: options.includeTenantWide !== false,
      roleScope: options.roleScope || null,
      includeDeleted:
        filters.include_deleted === true || filters.include_deleted === 'true',
    });
  }

  const finderMap = {
    users: repository.findUsers,
    permissions: repository.findPermissions,
    'user-roles': repository.findUserRoles,
    'role-permissions': repository.findRolePermissions,
  };

  const finder = finderMap[resource];
  if (!finder) {
    return { items: [], total: 0 };
  }

  return finder({ scope, filters, skip, take });
};

const maybeSyncTenantAccessCatalog = async (scope = {}) => {
  // Platform catalog is global; keep it warm for any access-admin session.
  await ensureTenantAccessCatalog(scope?.tenant_id || null);
};

const getWorkspace = async (query = {}, page = 1, limit = 20, user = {}) => {
  const { panel, resource } = resolveResource(query);
  const isRegistrationQueue = resource === 'registration-follow-ups';
  const isPaymentRequestQueue = resource === 'subscription-payment-requests';

  if (isRegistrationQueue || isPaymentRequestQueue) {
    requireSuperAdmin(user);
  }

  const scopeResult = isRegistrationQueue || isPaymentRequestQueue
    ? { state: 'ready', scope: { tenant_id: null, facility_id: null } }
    : await repository.resolveWorkspaceScope({ filters: query, user });
  const includeAllTenants = isSuperAdmin(user);

  if (!isRegistrationQueue && !isPaymentRequestQueue && scopeResult.state === 'tenant_context_required') {
    const lookups = await repository.findLookups(null, includeAllTenants);
    return {
      state: 'tenant_context_required',
      generated_at: new Date().toISOString(),
      summary: {},
      panel_summaries: ACCESS_PANELS.map((entry) => ({
        id: entry.id,
        label_key: entry.label_key,
        default_resource: entry.default_resource,
      })),
      filters: { panel, resource, tenant_id: null, facility_id: null },
      lookups: buildLookups(lookups, user),
      items: [],
      pagination: buildPagination(page, limit, 0),
      overview: buildOverview(),
      permissions: {
        can_read: true,
        can_write: canWriteAccess(user),
        can_reset_demo_passwords:
          canWriteAccess(user) && process.env.NODE_ENV !== 'production',
      },
    };
  }

  const scope = scopeResult.scope;
  const canManageTenantWideRoles = canActorCreateTenantWideRole(user);
  // Facility admin / HR reuse tenant default roles for assignment; create stays facility-only.
  const includeTenantWideRoles =
    canManageTenantWideRoles || isFacilityScopedAccessActor(user);
  const requestedRoleScope = text(query.role_scope || query.roleScope).toLowerCase();
  const roleScope =
    requestedRoleScope === 'tenant' || requestedRoleScope === 'facility'
      ? requestedRoleScope
      : null;
  // Facility-only actors cannot manage tenant-wide roles, but may list them for reuse.
  const effectiveRoleScope =
    !canManageTenantWideRoles && roleScope === 'tenant' ? null : roleScope;

  const filters = {
    search: text(query.search),
    status: text(query.status).toUpperCase() || null,
    user_id: text(query.userId || query.user_id) || null,
    role_id: text(query.roleId || query.role_id) || null,
    include_deleted:
      query.include_deleted === true ||
      query.include_deleted === 'true' ||
      query.includeDeleted === true ||
      query.includeDeleted === 'true',
  };

  const roleListOptions = {
    includeTenantWide: includeTenantWideRoles,
    roleScope: effectiveRoleScope,
  };

  const skip = (page - 1) * limit;
  const lean =
    query.lean === true ||
    query.lean === 'true' ||
    query.lean === '1';
  const skipLookups =
    lean &&
    (query.skip_lookups === true ||
      query.skip_lookups === 'true' ||
      query.skipLookups === true ||
      query.skipLookups === 'true' ||
      query.skipLookups === '1');

  // Catalog sync is expensive; lean management lists do not need it on every page.
  if (!isRegistrationQueue && !isPaymentRequestQueue && !lean) {
    await maybeSyncTenantAccessCatalog(scope);
  }

  const [summary, lookups, itemsResult] = isRegistrationQueue
    ? [
        {},
        { tenants: [], facilities: [], roles: [], permissions: [] },
        await findItemsForResource(resource, scope, filters, skip, limit),
      ]
    : await Promise.all([
        lean ? Promise.resolve({}) : repository.findSummary(scope),
        skipLookups
          ? Promise.resolve({
              tenants: [],
              facilities: [],
              roles: [],
              permissions: [],
            })
          : lean
            ? repository.findLookups(scope, includeAllTenants, {
                includeTenantWide: includeTenantWideRoles,
                includePermissions: false,
                includeRolePermissions: false,
              })
            : repository.findLookups(scope, includeAllTenants, {
                includeTenantWide: includeTenantWideRoles,
                includeRolePermissions: false,
              }),
        findItemsForResource(
          resource,
          scope,
          filters,
          skip,
          limit,
          roleListOptions
        ),
      ]);

  const subscription = itemsResult.subscription || null;
  const needsOverviewSubscription =
    !lean &&
    !isRegistrationQueue &&
    (panel === 'overview' ||
      panel === 'entitlements' ||
      resource === 'module-entitlements');
  const overviewSubscription = !needsOverviewSubscription
    ? null
    : resource === 'module-entitlements'
      ? subscription
      : (await repository.findModuleEntitlements(scope)).subscription;

  const visiblePanels = isSuperAdmin(user)
    ? ACCESS_PANELS
    : ACCESS_PANELS.filter((entry) => entry.id !== 'registrations');

  return {
    state: 'ready',
    generated_at: new Date().toISOString(),
    summary,
    panel_summaries: visiblePanels.map((entry) => ({
      id: entry.id,
      label_key: entry.label_key,
      default_resource: entry.default_resource,
    })),
    filters: {
      panel,
      resource,
      search: filters.search,
      status: filters.status,
      tenant_id: safePublicId(undefined, scope.tenant_id),
      facility_id: safePublicId(undefined, scope.facility_id),
      user_id: filters.user_id,
      role_id: filters.role_id,
      role_scope: effectiveRoleScope,
      record_id: text(query.id || query.recordId) || null,
      can_view_tenant_roles: canManageTenantWideRoles,
    },
    lookups: buildLookups(lookups, user),
    items: serializeItems(resource, itemsResult.items || [], subscription),
    pagination: buildPagination(page, limit, Number(itemsResult.total || 0)),
    overview: buildOverview(summary, overviewSubscription),
    permissions: {
      can_read: true,
      can_write: canWriteAccess(user),
      can_reset_demo_passwords:
        canWriteAccess(user) && process.env.NODE_ENV !== 'production',
    },
  };
};

const parseIncludeSet = (query = {}) => {
  const raw = text(query.include || query.resources || '');
  if (!raw) {
    return null;
  }
  const values = new Set(
    raw
      .split(',')
      .map((entry) => entry.trim().toLowerCase())
      .filter(Boolean)
  );
  return values.size > 0 ? values : null;
};

const buildLookupIncludeOptions = (includeSet) => {
  if (!includeSet) {
    return {
      includeTenants: true,
      includeFacilities: true,
      includeRoles: true,
      includePermissions: true,
      includeRolePermissions: true,
    };
  }
  return {
    includeTenants: includeSet.has('tenants') || includeSet.has('all'),
    includeFacilities: includeSet.has('facilities') || includeSet.has('all'),
    includeRoles: includeSet.has('roles') || includeSet.has('all'),
    includePermissions: includeSet.has('permissions') || includeSet.has('all'),
    includeRolePermissions:
      includeSet.has('role_permissions') || includeSet.has('all'),
  };
};

const loadAssignablePermissionCatalog = async (tenantId, user = {}) => {
  if (!tenantId) {
    return [];
  }
  const [permissions, enabledModules] = await Promise.all([
    ensureTenantPermissionCatalog(tenantId),
    resolveAssignablePlanModules(tenantId),
  ]);
  return filterPermissionRecordsByCeiling(permissions, user, enabledModules);
};

const getReferenceData = async (query = {}, user = {}) => {
  const includeAllTenants = isSuperAdmin(user);
  const requestedTenantId = text(query.tenant_id || query.tenantId);
  const requestedFacilityId = text(query.facility_id || query.facilityId) || null;
  const canAssignPermissions = canWriteAccess(user);
  const includeTenantWideRoles =
    canActorCreateTenantWideRole(user) || isFacilityScopedAccessActor(user);
  const includeOptions = {
    ...buildLookupIncludeOptions(parseIncludeSet(query)),
    includeTenantWide: includeTenantWideRoles,
  };

  if (requestedTenantId && canAssignPermissions) {
    const tenantId = await resolveIdentifierForFilter({
      value: requestedTenantId,
      model: 'tenant',
    });
    const facilityId = requestedFacilityId
      ? await resolveIdentifierForFilter({
          value: requestedFacilityId,
          model: 'facility',
        })
      : null;
    if (tenantId) {
      const [permissions, lookups] = await Promise.all([
        includeOptions.includePermissions
          ? loadAssignablePermissionCatalog(tenantId, user)
          : Promise.resolve([]),
        repository.findLookups(
          { tenant_id: tenantId, facility_id: facilityId || null },
          includeAllTenants,
          {
            ...includeOptions,
            // Permissions come from the assignable catalog above.
            includePermissions: false,
          }
        ),
      ]);
      return buildLookups(
        {
          ...lookups,
          permissions,
        },
        user
      );
    }
  }

  const scopeResult = await repository.resolveWorkspaceScope({ filters: query, user });

  if (scopeResult.state === 'tenant_context_required') {
    const lookups = await repository.findLookups(
      null,
      includeAllTenants,
      includeOptions
    );
    return {
      ...buildLookups(lookups, user),
      permissions: includeOptions.includePermissions ? [] : (lookups.permissions || []),
    };
  }

  const scope = scopeResult.scope;
  const [permissions, lookups] = await Promise.all([
    canAssignPermissions && includeOptions.includePermissions
      ? loadAssignablePermissionCatalog(scope.tenant_id, user)
      : Promise.resolve([]),
    repository.findLookups(scope, includeAllTenants, {
      ...includeOptions,
      includePermissions:
        includeOptions.includePermissions &&
        !(canAssignPermissions && includeOptions.includePermissions),
    }),
  ]);

  return buildLookups(
    {
      ...lookups,
      permissions:
        canAssignPermissions && permissions.length > 0
          ? permissions
          : lookups.permissions,
    },
    user
  );
};

const getUserDetail = async (identifier, query = {}, user = {}) => {
  // Detail lookup must not be trapped by the list's session facility/tenant
  // defaults. Super admins can open any user; tenant admins any user in their
  // tenant; facility-scoped actors stay within their facility.
  let lookupScope = { tenant_id: null, facility_id: null };

  if (!isSuperAdmin(user)) {
    const scopeResult = await repository.resolveWorkspaceScope({
      filters: {
        ...query,
        allFacilities:
          hasTenantAdminScope(user) ||
          query.allFacilities === true ||
          query.allFacilities === 'true' ||
          query.all_facilities === true ||
          query.all_facilities === 'true'
            ? 'true'
            : query.allFacilities || query.all_facilities,
      },
      user,
    });
    if (scopeResult.state === 'tenant_context_required') {
      throw new HttpError('errors.auth.scope_mismatch', 403);
    }
    lookupScope = {
      tenant_id: scopeResult.scope.tenant_id,
      facility_id: hasTenantAdminScope(user)
        ? null
        : scopeResult.scope.facility_id,
    };
  }

  // Prefer an explicit tenant hint from the client (row's tenant) when resolving
  // friendly IDs that are only unique per tenant.
  const requestedTenantId = text(query.tenant_id || query.tenantId);
  if (requestedTenantId && !lookupScope.tenant_id) {
    const tenantId = await resolveIdentifierForFilter({
      value: requestedTenantId,
      model: 'tenant',
    });
    if (tenantId) {
      lookupScope = { ...lookupScope, tenant_id: tenantId };
    }
  }

  let record = await repository.findUserByIdentifier(identifier, lookupScope);

  // Friendly IDs are tenant-scoped; if the first pass used a tenant hint and
  // missed (e.g. UUID path), retry without tenant for elevated actors.
  if (!record && isSuperAdmin(user) && lookupScope.tenant_id) {
    record = await repository.findUserByIdentifier(identifier, {
      tenant_id: null,
      facility_id: null,
    });
  }

  if (!record) {
    throw new HttpError('errors.not_found', 404);
  }

  return serializeUserDetail(record);
};

const resetDemoUserPassword = async (identifier, user = {}) => {
  if (process.env.NODE_ENV === 'production') {
    throw new HttpError('errors.access_admin.demo_reset_not_allowed', 403);
  }

  if (!canWriteAccess(user)) {
    throw new HttpError('errors.auth.forbidden', 403);
  }

  const scopeResult = await repository.resolveWorkspaceScope({ filters: {}, user });
  if (scopeResult.state === 'tenant_context_required') {
    throw new HttpError('errors.auth.scope_mismatch', 403);
  }

  const record = await repository.findUserByIdentifier(identifier, scopeResult.scope);
  if (!record) {
    throw new HttpError('errors.not_found', 404);
  }

  if (!repository.isDemoUser(record)) {
    throw new HttpError('errors.access_admin.not_demo_user', 400);
  }

  const passwordHash = await hashPassword(DEFAULT_DEMO_RESET_PASSWORD);
  await repository.resetDemoUserPassword(record.id, passwordHash);

  return {
    user_id: safePublicId(record.human_friendly_id, record.id),
    email: record.email,
    reset_at: new Date().toISOString(),
    environment: process.env.NODE_ENV || 'development',
  };
};

const resolveLegacyRoute = async (resource, identifier) => {
  const normalizedResource = text(resource).toLowerCase();
  if (!ACCESS_RESOURCES.includes(normalizedResource)) {
    throw new HttpError('errors.not_found', 404);
  }

  return {
    panel: RESOURCE_PANEL_MAP[normalizedResource] || 'directory',
    resource: normalizedResource,
    id: text(identifier) || null,
    action: 'view',
  };
};

const loadRegistrationUser = async (userIdentifier) => {
  const identifier = text(userIdentifier);
  let scopedUser = identifier
    ? await repository.findUserByIdentifier(identifier, {
        tenant_id: null,
        facility_id: null,
      })
    : null;

  // Clients may send the registration follow-up display id; resolve to the user.
  if (!scopedUser?.id && identifier) {
    const linkedUserId = await repository.findRegistrationFollowUpUserId(
      identifier,
    );
    if (linkedUserId) {
      scopedUser = await repository.findUserByIdentifier(linkedUserId, {
        tenant_id: null,
        facility_id: null,
      });
    }
  }

  // Last resort: resolve by email when the client sent a blank/invalid id.
  if (!scopedUser?.id && identifier && identifier.includes('@')) {
    scopedUser = await authRepository.findUserByEmail(identifier.toLowerCase());
  }

  if (!scopedUser?.id) {
    throw new HttpError('errors.auth.registration_not_pending', 404);
  }

  const user = await authRepository.findUserById(scopedUser.id);
  if (!user || user.status !== 'PENDING' || !user.email_verified_at) {
    throw new HttpError('errors.auth.registration_not_pending', 404);
  }

  return user;
};

const approveRegistration = async (userIdentifier, actor = {}, ip = null) => {
  requireSuperAdmin(actor);
  const user = await loadRegistrationUser(userIdentifier);

  await authRepository.updateUserStatus(user.id, 'ACTIVE');
  await authRepository.updateRegistrationFollowUpStatus(user.id, 'ACTIVE').catch(() => {});
  await provisionTrialSubscription(user.tenant_id);

  await createAuditLog({
    action: 'TENANT_REGISTRATION_APPROVED',
    entity: 'user',
    entity_id: user.id,
    user_id: actor.id || null,
    tenant_id: user.tenant_id,
    facility_id: user.facility_id,
    ip_address: ip,
    details: {
      email: user.email,
      phone: user.phone || null,
    },
  }).catch(() => {});

  if (user.email) {
    const adminName = [
      user.profile?.first_name,
      user.profile?.last_name,
    ]
      .map((part) => String(part || '').trim())
      .filter(Boolean)
      .join(' ')
      .trim() || user.email.split('@')[0] || 'Admin';
    const facilityName =
      user.facility?.name || user.tenant?.name || 'your facility';

    // Approval is already committed; do not block the API on SMTP.
    void sendAccountApprovedEmail({
      email: user.email,
      adminName,
      facilityName,
    })
      .then((deliveryResult) => {
        if (!deliveryResult?.sent) {
          logger.warn('Account-approved email was not delivered.', {
            context: 'approve_registration_approved',
            email: user.email,
            provider: deliveryResult?.provider || null,
          });
        }
      })
      .catch((error) => {
        logger.warn('Account-approved email send failed.', {
          context: 'approve_registration_approved',
          email: user.email,
          error: error?.message || String(error),
        });
      });
  }

  return serializeRegistrationFollowUp({
    email: user.email,
    phone: user.phone,
    user: { ...user, status: 'ACTIVE' },
    facility_name: user.facility?.name || null,
    facility_type: user.facility?.facility_type || null,
    tenant: user.tenant || null,
    facility: user.facility || null,
    account_status: 'ACTIVE',
    status: 'ACTIVE',
    updated_at: new Date(),
  });
};

/** @deprecated Prefer approveRegistration — kept for older clients. */
const activateRegistration = approveRegistration;

const rejectRegistration = async (userIdentifier, actor = {}, ip = null) => {
  requireSuperAdmin(actor);
  const user = await loadRegistrationUser(userIdentifier);

  await authRepository.updateUserStatus(user.id, 'INACTIVE');
  await authRepository.updateRegistrationFollowUpStatus(user.id, 'INACTIVE').catch(() => {});

  await createAuditLog({
    action: 'TENANT_REGISTRATION_REJECTED',
    entity: 'user',
    entity_id: user.id,
    user_id: actor.id || null,
    tenant_id: user.tenant_id,
    facility_id: user.facility_id,
    ip_address: ip,
    details: {
      email: user.email,
      phone: user.phone || null,
    },
  }).catch(() => {});

  return { status: 'INACTIVE' };
};

const restoreAccessDefaults = async (payload = {}, actor = {}, ip = null) => {
  if (!canWriteAccess(actor)) {
    throw new HttpError('errors.auth.insufficient_permissions', 403);
  }

  const tenantId =
    payload.tenant_id ||
    payload.tenantId ||
    actor.tenant_id ||
    actor.tenantId ||
    null;
  if (!tenantId) {
    throw new HttpError('errors.validation.field.required', 400, [{ field: 'tenant_id' }]);
  }

  if (
    !isSuperAdmin(actor) &&
    String(actor.tenant_id || actor.tenantId || '') !== String(tenantId)
  ) {
    throw new HttpError('errors.auth.insufficient_permissions', 403);
  }

  const reason = text(payload.reason);
  if (!reason) {
    throw new HttpError('errors.validation.field.required', 400, [{ field: 'reason' }]);
  }

  const result = await restoreTenantRolePermissionDefaults(tenantId, {
    roleNames: Array.isArray(payload.role_names)
        ? payload.role_names
        : Array.isArray(payload.roleNames)
        ? payload.roleNames
        : undefined,
  });

  clearLiveAccessCaches(tenantId);

  await createAuditLog({
    action: 'ACCESS_DEFAULTS_RESTORED',
    entity: 'access_catalog',
    entity_id: tenantId,
    user_id: actor.id || actor.user_id || null,
    tenant_id: tenantId,
    facility_id: actor.facility_id || actor.facilityId || null,
    ip_address: ip,
    diff: {
      before: result.before,
      after: result.after,
      reason,
      role_permissions_added: result.role_permissions_added,
      role_permissions_removed: result.role_permissions_removed,
    },
  }).catch(() => {});

  return {
    tenant_id: tenantId,
    permissions: result.permissions,
    roles: result.roles,
    role_permissions_added: result.role_permissions_added,
    role_permissions_removed: result.role_permissions_removed,
    restored_at: new Date().toISOString(),
  };
};

module.exports = {
  approveRegistration,
  activateRegistration,
  activatePaymentRequest: (requestId, actor, ip) =>
    activatePaymentRequest(requestId, actor, ip),
  rejectPaymentRequest: (requestId, payload, actor, ip) =>
    rejectPaymentRequest(requestId, payload, actor, ip),
  getReferenceData,
  getUserDetail,
  getWorkspace,
  rejectRegistration,
  resetDemoUserPassword,
  resolveLegacyRoute,
  restoreAccessDefaults,
};
