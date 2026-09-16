/**
 * Tenant service
 *
 * @module modules/tenant/services
 * @description Business logic for tenant operations.
 * Per module-creation.mdc: Services contain business logic and call repositories.
 * Per module-creation.mdc: All mutations must call createAuditLog.
 */

const tenantRepository = require('@repositories/tenant/tenant.repository');
const prisma = require('@prisma/client');
const { createAuditLog } = require('@lib/audit');
const { HttpError } = require('@lib/errors');
const { resolvePublicIdentifier } = require('@lib/billing/identifiers');
const { DEFAULT_PAGE, DEFAULT_PAGE_LIMIT, MAX_PAGE_LIMIT } = require('@config/constants');
const { PERMISSIONS } = require('@config/permissions');
const { PLATFORM_ADMIN_EVENTS } = require('@lib/websocket/events');
const { publishCrudRealtimeEvent } = require('@lib/websocket/crud-realtime');
const { ROLES } = require('@config/roles');
const {
  publishPlatformRealtimeEvent,
  buildTenantDashboardDeltas,
  buildFacilityDashboardDeltas
} = require('@lib/realtime/platform-realtime');
const { resolveModelIdByIdentifier, resolveModelRecordByIdentifier } = require('@lib/identifiers/resolve-entity-id');
const {
  checkTenantDuplicates
} = require('@lib/tenant/tenant-similarity');
const {
  resolveTenantContact,
  hasResolvedContact,
  DEFAULT_TENANT_CURRENCY,
  DEFAULT_TENANT_CONSULTATION_FEE,
  resolveDefaultConsultationFee,
  normalizeText,
} = require('@lib/tenant/resolve-tenant-contact');

const TENANT_SIMILARITY_LOOKUP_LIMIT = 7500;

// Subscription states that count as "this tenant has a subscription".
const LIVE_SUBSCRIPTION_STATUSES = ['ACTIVE', 'TRIAL', 'PAST_DUE'];

const isSystemAdminContext = (context = {}) =>
  Array.isArray(context.permissions)
  && context.permissions.includes(PERMISSIONS.PLATFORM_ADMIN);

const assertCanAccessTenantRecord = (tenant, context = {}) => {
  // Trusted internal callers omit permissions.
  if (!Array.isArray(context.permissions)) {
    return;
  }
  if (isSystemAdminContext(context)) {
    return;
  }
  const actorTenantId = String(context.tenant_id || '').trim();
  const targetTenantId = String(tenant?.id || '').trim();
  if (!actorTenantId || !targetTenantId || actorTenantId !== targetTenantId) {
    throw new HttpError('errors.auth.insufficient_permissions', 403);
  }
};

const extractTenantSimilarityInput = (data = {}) => {
  const extension = data.extension_json && typeof data.extension_json === 'object'
    ? data.extension_json
    : {};
  const contact = extension.contact && typeof extension.contact === 'object'
    ? extension.contact
    : {};
  const billing = extension.billing && typeof extension.billing === 'object'
    ? extension.billing
    : {};

  return {
    name: data.name,
    slug: data.slug,
    contactName: contact.name,
    contactEmail: contact.email,
    contactPhone: contact.phone,
    currency: extension.currency,
    standardConsultationFee: billing.standard_consultation_fee
  };
};

const assertTenantUniqueness = async ({
  data,
  confirmSimilar = false,
  excludeTenantId = null
}) => {
  const existing = await tenantRepository.findMany(
    {},
    0,
    TENANT_SIMILARITY_LOOKUP_LIMIT,
    { name: 'asc' }
  );
  const input = extractTenantSimilarityInput(data);
  const duplicateCheck = checkTenantDuplicates({
    ...input,
    existing,
    excludeTenantId
  });

  if (duplicateCheck.exactSlugConflict) {
    throw new HttpError('errors.tenant.duplicate_slug', 409, [
      {
        field: 'slug',
        matches: duplicateCheck.similarMatches
          .filter((match) => match.exactSlugConflict)
          .slice(0, 5)
      }
    ]);
  }

  const reviewMatches = duplicateCheck.overridableMatches.slice(0, 5);
  if (reviewMatches.length > 0 && !confirmSimilar) {
    throw new HttpError('errors.tenant.similar_exists', 409, [
      {
        field: 'name',
        matches: reviewMatches
      }
    ]);
  }

  return duplicateCheck;
};

const publishTenantRealtimeEvent = async (
  event,
  tenant,
  actorUserId,
  operation = 'create',
  before = null
) => {
  await publishPlatformRealtimeEvent({
    event,
    resource_type: 'tenant',
    resource_id: tenant?.id || null,
    actor_user_id: actorUserId || null,
    dashboard_deltas: buildTenantDashboardDeltas(tenant, operation, before),
    payload: {
      is_active: tenant?.is_active !== false,
      name: tenant?.name || null
    }
  });
};

// Tenant-scoped admins see facility contacts inherited from the tenant contact.
const TENANT_REALTIME_RECIPIENT_ROLES = Object.freeze([
  ROLES.TENANT_ADMIN,
  ROLES.FACILITY_ADMIN
]);

/**
 * Tell the tenant's own admins that the tenant changed, so open facility
 * details and print branding refresh inherited phone/email.
 *
 * @param {Object} tenant - Updated tenant
 * @param {string|null} actorUserId - User who made the change
 * @returns {Promise<number>} Delivered event count
 */
const publishTenantScopedRealtimeEvent = (tenant, actorUserId) =>
  publishCrudRealtimeEvent({
    event: PLATFORM_ADMIN_EVENTS.TENANT_UPDATED,
    resource: { id: tenant?.id, tenant_id: tenant?.id },
    resource_type: 'tenant',
    actor_user_id: actorUserId || null,
    recipient_roles: TENANT_REALTIME_RECIPIENT_ROLES,
    payload: {
      is_active: tenant?.is_active !== false,
      name: tenant?.name || null
    }
  });

const resolveTenantId = async (identifier) => {
  const normalized = String(identifier ?? '').trim();
  if (!normalized) {
    return normalized;
  }

  const resolved = await resolveModelIdByIdentifier({
    model: 'tenant',
    identifier: normalized,
    additionalFriendlyMatchers: [
      (value) => ({ slug: value.toLowerCase() })]});

  return resolved || normalized;
};

const buildDefaultFacilityName = (tenantName) => {
  const normalized = String(tenantName || '').trim();
  if (!normalized) {
    return 'Main Facility';
  }
  return `${normalized} Main Facility`;
};

const normalizeString = (value) => {
  const normalized = String(value ?? '').trim();
  return normalized || null;
};

const toPositiveInt = (value, fallback, max = Number.POSITIVE_INFINITY) => {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  const normalized = Math.trunc(parsed);
  if (normalized <= 0) return fallback;
  return Math.min(normalized, max);
};

const normalizeSortOrder = (value) => {
  const normalized = String(value || 'desc').toLowerCase();
  return normalized === 'asc' ? 'asc' : 'desc';
};

const buildFullName = (...parts) => {
  const tokens = parts.map(normalizeString).filter(Boolean);
  return tokens.length > 0 ? tokens.join(' ') : null;
};

const buildPrimaryTenantAdmin = (userRole = null) => {
  const user = userRole?.user;
  if (!user || typeof user !== 'object') return null;

  const profile = user.profile || {};
  const role = userRole?.role || {};

  return {
    id: normalizeString(user.id),
    human_friendly_id: normalizeString(user.human_friendly_id),
    email: normalizeString(user.email),
    phone: normalizeString(user.phone),
    status: normalizeString(user.status),
    first_name: normalizeString(profile.first_name),
    middle_name: normalizeString(profile.middle_name),
    last_name: normalizeString(profile.last_name),
    full_name: buildFullName(profile.first_name, profile.middle_name, profile.last_name),
    facility_id: normalizeString(user.facility_id || userRole?.facility_id),
    facility_name: normalizeString(user?.facility?.name),
    role_id: normalizeString(role.id || userRole?.role_id),
    role_human_friendly_id: normalizeString(role.human_friendly_id),
    role_name: normalizeString(role.name || 'TENANT_ADMIN'),
    user_role_id: normalizeString(userRole?.id),
    user_role_human_friendly_id: normalizeString(userRole?.human_friendly_id)};
};

/**
 * Flattens the included live subscription (if any) into a list-friendly shape.
 * Returns null when the tenant has no live subscription.
 */
const buildCurrentSubscription = (subscriptions) => {
  if (!Array.isArray(subscriptions) || subscriptions.length === 0) {
    return null;
  }

  const subscription = subscriptions[0];
  if (!subscription || typeof subscription !== 'object') {
    return null;
  }

  const plan = subscription.plan || {};
  return {
    id: subscription.id || null,
    display_id: resolvePublicIdentifier(subscription.human_friendly_id, subscription.id) || null,
    status: subscription.status || null,
    start_date: subscription.start_date || null,
    end_date: subscription.end_date || null,
    plan_id: plan.id || null,
    plan_display_id: resolvePublicIdentifier(plan.human_friendly_id, plan.id) || null,
    plan_name: normalizeText(plan.name) || null,
    plan_code: normalizeText(plan.code) || null,
    plan_tier_code: plan.tier_code || null
  };
};

const normalizeTenantRecord = (tenant) => {
  if (!tenant || typeof tenant !== 'object') return tenant;

  // `subscriptions` is a query-shaped relation - expose the current one only.
  const { subscriptions, ...tenantFields } = tenant;
  const currentSubscription = buildCurrentSubscription(subscriptions);

  const normalized = {
    ...tenantFields,
    resource_uuid: tenant.id,
    display_id:
      resolvePublicIdentifier(tenant.human_friendly_id, tenant.id) || tenant.id,
    ...(Array.isArray(subscriptions)
      ? { current_subscription: currentSubscription }
      : {})};

  if (!Array.isArray(tenant.user_roles)) {
    return normalized;
  }

  const { user_roles, ...tenantRecord } = normalized;
  const primaryTenantAdmin = buildPrimaryTenantAdmin(user_roles[0] || null);
  const resolvedContact = resolveTenantContact({
    ...tenantRecord,
    primary_tenant_admin: primaryTenantAdmin,
    user_roles,
  });
  const existingExtension =
    tenantRecord.extension_json && typeof tenantRecord.extension_json === 'object'
      ? tenantRecord.extension_json
      : {};

  return {
    ...tenantRecord,
    extension_json: hasResolvedContact(resolvedContact)
      ? {
          ...existingExtension,
          contact: resolvedContact,
        }
      : tenantRecord.extension_json ?? null,
    primary_tenant_admin: primaryTenantAdmin};
};

/**
 * List tenants with pagination and filters
 *
 * @param {Object} filters - Filter criteria
 * @param {boolean} [filters.is_active] - Filter by active status
 * @param {string} [filters.search] - Search by name or slug
 * @param {'none'|'active'} [filters.subscription] - Filter by live subscription presence
 * @param {number} page - Page number
 * @param {number} limit - Items per page
 * @param {string} [sort_by] - Field to sort by
 * @param {string} [order] - Sort order (asc/desc)
 * @returns {Promise<Object>} Paginated tenants
 */
const listTenants = async (filters = {}, page = 1, limit = 20, sort_by = 'created_at', order = 'desc') => {
  const resolvedPage = toPositiveInt(page, DEFAULT_PAGE);
  const resolvedLimit = toPositiveInt(limit, DEFAULT_PAGE_LIMIT, MAX_PAGE_LIMIT);
  const resolvedSortBy = typeof sort_by === 'string' && sort_by.trim()
    ? sort_by.trim()
    : 'created_at';
  const resolvedOrder = normalizeSortOrder(order);
  const includeDeleted =
    filters.include_deleted === true || filters.include_deleted === 'true';

  // Build repository filters
  const repoFilters = {};

  if (filters.is_active !== undefined) {
    repoFilters.is_active = filters.is_active === true || filters.is_active === 'true';
  }

  // Handle search filter
  if (filters.search) {
    repoFilters.OR = [
      { name: { contains: filters.search } },
      { slug: { contains: filters.search } }
    ];
  }

  // Subscription presence filter - mirrors the platform dashboard
  // "tenants without subscription" alert so the deep link and the badge agree.
  if (filters.subscription === 'none' || filters.subscription === 'active') {
    const liveSubscription = {
      deleted_at: null,
      status: { in: LIVE_SUBSCRIPTION_STATUSES }
    };
    repoFilters.subscriptions =
      filters.subscription === 'none'
        ? { none: liveSubscription }
        : { some: liveSubscription };
  }

  // Calculate pagination
  const skip = (resolvedPage - 1) * resolvedLimit;

  // Build sort order
  const orderBy = includeDeleted
    ? [
        { deleted_at: 'asc' },
        { [resolvedSortBy]: resolvedOrder }]
    : { [resolvedSortBy]: resolvedOrder };

  const listOptions = { includeDeleted };

  // Fetch tenants and count
  const [tenants, total] = await Promise.all([
    tenantRepository.findMany(repoFilters, skip, resolvedLimit, orderBy, listOptions),
    tenantRepository.count(repoFilters, listOptions)
  ]);

  // Calculate pagination metadata
  const totalPages = Math.ceil(total / resolvedLimit);
  const hasNextPage = resolvedPage < totalPages;
  const hasPreviousPage = resolvedPage > 1;

  return {
    tenants: tenants.map((tenant) => normalizeTenantRecord(tenant)),
    pagination: {
      page: resolvedPage,
      limit: resolvedLimit,
      total,
      totalPages,
      hasNextPage,
      hasPreviousPage
    }
  };
};

/**
 * Get tenant by ID
 *
 * @param {string} id - Tenant ID
 * @returns {Promise<Object>} Tenant data
 */
const getTenantById = async (id, context = {}) => {
  const tenantId = await resolveTenantId(id);
  const tenant = await tenantRepository.findById(tenantId);
  
  if (!tenant) {
    throw new HttpError('errors.tenant.not_found', 404);
  }

  assertCanAccessTenantRecord(tenant, context);

  return normalizeTenantRecord(tenant);
};

/**
 * Create new tenant
 *
 * @param {Object} data - Tenant data
 * @param {string} data.name - Tenant name
 * @param {string} [data.slug] - Tenant slug
 * @param {boolean} [data.is_active] - Active status
 * @param {Object} context - Request context for audit
 * @param {string} [context.user_id] - User ID performing the action
 * @param {string} [context.tenant_id] - Tenant ID
 * @param {string} [context.facility_id] - Facility ID
 * @param {string} [context.ip_address] - IP address
 * @param {string} [context.user_agent] - User agent
 * @returns {Promise<Object>} Created tenant
 */
const createTenant = async (data, context = {}) => {
  const confirmSimilar = data?.confirm_similar === true;
  const payload = { ...data };
  delete payload.confirm_similar;

  const existingExtension =
    payload.extension_json && typeof payload.extension_json === 'object'
      ? { ...payload.extension_json }
      : {};
  const existingCurrency = normalizeText(existingExtension.currency)?.toUpperCase();
  const existingBilling =
    existingExtension.billing && typeof existingExtension.billing === 'object'
      ? { ...existingExtension.billing }
      : {};
  const hasExplicitFee =
    existingBilling.standard_consultation_fee !== undefined &&
    existingBilling.standard_consultation_fee !== null &&
    String(existingBilling.standard_consultation_fee).trim() !== '';
  payload.extension_json = {
    ...existingExtension,
    currency:
      existingCurrency && /^[A-Z]{3}$/.test(existingCurrency)
        ? existingCurrency
        : DEFAULT_TENANT_CURRENCY,
    billing: {
      ...existingBilling,
      standard_consultation_fee: hasExplicitFee
        ? resolveDefaultConsultationFee(existingBilling.standard_consultation_fee)
        : DEFAULT_TENANT_CONSULTATION_FEE,
    },
  };

  const duplicateCheck = await assertTenantUniqueness({
    data: payload,
    confirmSimilar
  });

  if (payload?.slug) {
    await tenantRepository.releaseSlugFromSoftDeletedTenants(payload.slug);
  }

  const { tenant, facility } = await tenantRepository.createWithDefaultFacility(
    payload,
    {
      facilityName: buildDefaultFacilityName(payload?.name)},
  );

  // Create audit log
  await createAuditLog({
    action: 'TENANT_CREATED',
    entity: 'tenant',
    entity_id: tenant.id,
    user_id: context.user_id,
    tenant_id: context.tenant_id,
    facility_id: context.facility_id,
    ip_address: context.ip_address,
    user_agent: context.user_agent,
    details: {
      name: tenant.name,
      slug: tenant.slug,
      is_active: tenant.is_active,
      default_facility_id: facility.id,
      confirm_similar: confirmSimilar,
      similar_match_ids: confirmSimilar
        ? duplicateCheck.overridableMatches
          .slice(0, 5)
          .map((match) => match.id)
          .filter(Boolean)
        : []}
  });

  await createAuditLog({
    action: 'FACILITY_CREATED',
    entity: 'facility',
    entity_id: facility.id,
    user_id: context.user_id,
    tenant_id: tenant.id,
    facility_id: facility.id,
    ip_address: context.ip_address,
    user_agent: context.user_agent,
    details: {
      tenant_id: facility.tenant_id,
      name: facility.name,
      facility_type: facility.facility_type,
      is_active: facility.is_active,
      bootstrap: true}
  });

  await publishTenantRealtimeEvent(
    PLATFORM_ADMIN_EVENTS.TENANT_CREATED,
    tenant,
    context.user_id,
    'create'
  );

  await publishPlatformRealtimeEvent({
    event: PLATFORM_ADMIN_EVENTS.FACILITY_CREATED,
    resource_type: 'facility',
    resource_id: facility.id,
    actor_user_id: context.user_id || null,
    tenant_id: facility.tenant_id,
    facility_id: facility.id,
    dashboard_deltas: buildFacilityDashboardDeltas(facility, 'create'),
    payload: {
      is_active: facility.is_active !== false,
      name: facility.name || null,
      bootstrap: true}
  });

  return normalizeTenantRecord(tenant);
};

/**
 * Update tenant
 *
 * @param {string} id - Tenant ID
 * @param {Object} data - Update data
 * @param {string} [data.name] - Tenant name
 * @param {string} [data.slug] - Tenant slug
 * @param {boolean} [data.is_active] - Active status
 * @param {Object} context - Request context for audit
 * @param {string} [context.user_id] - User ID performing the action
 * @param {string} [context.tenant_id] - Tenant ID
 * @param {string} [context.facility_id] - Facility ID
 * @param {string} [context.ip_address] - IP address
 * @param {string} [context.user_agent] - User agent
 * @returns {Promise<Object>} Updated tenant
 */
const updateTenant = async (id, data, context = {}) => {
  const tenantId = await resolveTenantId(id);
  // Check if tenant exists and get before state
  const beforeTenant = await tenantRepository.findById(tenantId);
  
  if (!beforeTenant) {
    throw new HttpError('errors.tenant.not_found', 404);
  }

  assertCanAccessTenantRecord(beforeTenant, context);

  const confirmSimilar = data?.confirm_similar === true;
  let payload = { ...data };
  delete payload.confirm_similar;

  if (payload?.slug) {
    await tenantRepository.releaseSlugFromSoftDeletedTenants(payload.slug, tenantId);
  }

  // Merge extension_json so partial updates (e.g. currency) do not wipe other keys.
  if (payload.extension_json && typeof payload.extension_json === 'object') {
    const previousExtension =
      beforeTenant.extension_json && typeof beforeTenant.extension_json === 'object'
        ? beforeTenant.extension_json
        : {};
    const mergedExtension = {
      ...previousExtension,
      ...payload.extension_json};
    for (const [key, value] of Object.entries(mergedExtension)) {
      if (value === null || value === undefined) {
        delete mergedExtension[key];
      }
    }
    payload = {
      ...payload,
      extension_json: mergedExtension};
  }

  const uniquenessData = {
    name: Object.prototype.hasOwnProperty.call(payload, 'name')
      ? payload.name
      : beforeTenant.name,
    slug: Object.prototype.hasOwnProperty.call(payload, 'slug')
      ? payload.slug
      : beforeTenant.slug,
    extension_json: Object.prototype.hasOwnProperty.call(payload, 'extension_json')
      ? payload.extension_json
      : beforeTenant.extension_json
  };

  const duplicateCheck = await assertTenantUniqueness({
    data: uniquenessData,
    confirmSimilar,
    excludeTenantId: tenantId
  });

  // Update tenant
  const tenant = await tenantRepository.update(tenantId, payload);

  // Create audit log
  await createAuditLog({
    action: 'TENANT_UPDATED',
    entity: 'tenant',
    entity_id: tenantId,
    user_id: context.user_id,
    tenant_id: context.tenant_id,
    facility_id: context.facility_id,
    ip_address: context.ip_address,
    user_agent: context.user_agent,
    details: {
      before: {
        name: beforeTenant.name,
        slug: beforeTenant.slug,
        is_active: beforeTenant.is_active
      },
      after: {
        name: tenant.name,
        slug: tenant.slug,
        is_active: tenant.is_active
      },
      confirm_similar: confirmSimilar,
      similar_match_ids: confirmSimilar
        ? duplicateCheck.overridableMatches
          .slice(0, 5)
          .map((match) => match.id)
          .filter(Boolean)
        : []
    }
  });

  await Promise.all([
    publishTenantRealtimeEvent(
      PLATFORM_ADMIN_EVENTS.TENANT_UPDATED,
      tenant,
      context.user_id,
      'update',
      beforeTenant
    ),
    publishTenantScopedRealtimeEvent(tenant, context.user_id)
  ]);

  return normalizeTenantRecord(tenant);
};

/**
 * Delete tenant (soft delete) and cascade soft-delete to facilities and
 * facility structure (departments, units, wards, rooms, beds).
 *
 * @param {string} id - Tenant ID
 * @param {Object} context - Request context for audit
 * @param {string} [context.user_id] - User ID performing the action
 * @param {string} [context.tenant_id] - Tenant ID
 * @param {string} [context.facility_id] - Facility ID
 * @param {string} [context.ip_address] - IP address
 * @param {string} [context.user_agent] - User agent
 * @returns {Promise<void>}
 */
const deleteTenant = async (id, context = {}) => {
  const normalizedId = String(id ?? '').trim();
  const tenantId = await resolveTenantId(normalizedId);
  const tenant = await tenantRepository.findById(tenantId);

  if (!tenant) {
    const lookupIds = [...new Set([tenantId, normalizedId].filter(Boolean))];
    for (const candidate of lookupIds) {
      const deletedTenant = await resolveModelRecordByIdentifier({
        model: 'tenant',
        identifier: candidate,
        includeDeleted: true,
        select: { id: true, deleted_at: true },
        additionalFriendlyMatchers: [
          (value) => ({ slug: value.toLowerCase() })]});
      if (deletedTenant?.deleted_at) {
        return;
      }
    }
    throw new HttpError('errors.tenant.not_found', 404);
  }

  const { tenant: deletedTenant, facilities } = await tenantRepository.softDelete(tenantId);

  await createAuditLog({
    action: 'TENANT_DELETED',
    entity: 'tenant',
    entity_id: tenantId,
    user_id: context.user_id,
    tenant_id: context.tenant_id,
    facility_id: context.facility_id,
    ip_address: context.ip_address,
    user_agent: context.user_agent,
    details: {
      name: tenant.name,
      slug: tenant.slug,
      cascaded_facility_ids: facilities.map((facility) => facility.id)}
  });

  for (const facility of facilities) {
    await createAuditLog({
      action: 'FACILITY_DELETED',
      entity: 'facility',
      entity_id: facility.id,
      user_id: context.user_id,
      tenant_id: tenantId,
      facility_id: facility.id,
      ip_address: context.ip_address,
      user_agent: context.user_agent,
      details: {
        name: facility.name,
        facility_type: facility.facility_type,
        cascaded_from_tenant: true}
    });

    await publishPlatformRealtimeEvent({
      event: PLATFORM_ADMIN_EVENTS.FACILITY_DELETED,
      resource_type: 'facility',
      resource_id: facility.id,
      actor_user_id: context.user_id || null,
      tenant_id: facility.tenant_id || tenantId,
      facility_id: facility.id,
      dashboard_deltas: buildFacilityDashboardDeltas(facility, 'delete'),
      payload: {
        is_active: facility.is_active !== false,
        name: facility.name || null,
        cascaded_from_tenant: true}
    });
  }

  await publishTenantRealtimeEvent(
    PLATFORM_ADMIN_EVENTS.TENANT_DELETED,
    deletedTenant || tenant,
    context.user_id,
    'delete'
  );
};

const resolveTenantIdIncludingDeleted = async (identifier) => {
  const normalized = String(identifier ?? '').trim();
  if (!normalized) {
    return normalized;
  }

  const resolved = await resolveModelIdByIdentifier({
    model: 'tenant',
    identifier: normalized,
    includeDeleted: true,
    additionalFriendlyMatchers: [
      (value) => ({ slug: value.toLowerCase() })]});

  return resolved || normalized;
};

const assertNoActiveSubscriptions = async (tenantId) => {
  const activeSubscriptions = await prisma.subscription.count({
    where: {
      tenant_id: tenantId,
      deleted_at: null,
      status: { in: ['ACTIVE', 'TRIAL', 'PAST_DUE'] }}});

  if (activeSubscriptions > 0) {
    throw new HttpError('errors.tenant.permanent_delete_blocked', 409, [
      { reason: 'active_subscription' }]);
  }
};

/**
 * Restore soft-deleted tenant and cascade-restore facilities and structure
 * soft-deleted with it.
 */
const restoreTenant = async (id, context = {}) => {
  const normalizedId = String(id ?? '').trim();
  const tenantId = await resolveTenantIdIncludingDeleted(normalizedId);
  const { tenant, facilities } = await tenantRepository.restore(tenantId);

  await createAuditLog({
    action: 'TENANT_RESTORED',
    entity: 'tenant',
    entity_id: tenantId,
    user_id: context.user_id,
    tenant_id: context.tenant_id,
    facility_id: context.facility_id,
    ip_address: context.ip_address,
    user_agent: context.user_agent,
    details: {
      name: tenant.name,
      slug: tenant.slug,
      cascaded_facility_ids: facilities.map((facility) => facility.id)}});

  for (const facility of facilities) {
    await createAuditLog({
      action: 'FACILITY_RESTORED',
      entity: 'facility',
      entity_id: facility.id,
      user_id: context.user_id,
      tenant_id: tenantId,
      facility_id: facility.id,
      ip_address: context.ip_address,
      user_agent: context.user_agent,
      details: {
        name: facility.name,
        facility_type: facility.facility_type,
        cascaded_from_tenant: true}});

    await publishPlatformRealtimeEvent({
      event: PLATFORM_ADMIN_EVENTS.FACILITY_CREATED,
      resource_type: 'facility',
      resource_id: facility.id,
      actor_user_id: context.user_id || null,
      tenant_id: facility.tenant_id || tenantId,
      facility_id: facility.id,
      dashboard_deltas: buildFacilityDashboardDeltas(facility, 'create'),
      payload: {
        is_active: facility.is_active !== false,
        name: facility.name || null,
        cascaded_from_tenant_restore: true}});
  }

  await publishTenantRealtimeEvent(
    PLATFORM_ADMIN_EVENTS.TENANT_RESTORED,
    tenant,
    context.user_id,
    'create'
  );

  return normalizeTenantRecord(tenant);
};

/**
 * Permanently delete a soft-deleted tenant, its facilities, and related data.
 * Pass `{ force: true }` to override the active-subscription guard.
 */
const permanentDeleteTenant = async (id, context = {}, options = {}) => {
  const force = options.force === true;
  const normalizedId = String(id ?? '').trim();
  const tenantId = await resolveTenantIdIncludingDeleted(normalizedId);
  const tenant = await tenantRepository.findById(tenantId, { includeDeleted: true });

  if (!tenant) {
    // Idempotent: already purged from the database.
    return;
  }
  if (!tenant.deleted_at) {
    throw new HttpError('errors.tenant.permanent_delete_requires_soft_delete', 400);
  }

  if (!force) {
    await assertNoActiveSubscriptions(tenantId);
  }

  await createAuditLog({
    action: 'TENANT_PERMANENTLY_DELETED',
    entity: 'tenant',
    entity_id: tenantId,
    user_id: context.user_id,
    tenant_id: context.tenant_id,
    facility_id: context.facility_id,
    ip_address: context.ip_address,
    user_agent: context.user_agent,
    details: {
      name: tenant.name,
      slug: tenant.slug,
      irreversible: true,
      forced: force}});

  const { facilityIds } = await tenantRepository.permanentDelete(tenantId);

  await publishPlatformRealtimeEvent({
    event: PLATFORM_ADMIN_EVENTS.TENANT_PERMANENTLY_DELETED,
    resource_type: 'tenant',
    resource_id: tenantId,
    actor_user_id: context.user_id || null,
    payload: {
      name: tenant.name,
      permanent: true,
      forced: force,
      cascaded_facility_ids: facilityIds}});
};

module.exports = {
  listTenants,
  getTenantById,
  createTenant,
  updateTenant,
  deleteTenant,
  restoreTenant,
  permanentDeleteTenant};
