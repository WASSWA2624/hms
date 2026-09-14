/**
 * User service
 *
 * @module modules/user/services
 * @description Business logic layer for user operations.
 * Per module-creation.mdc: Services only import/use their own repository.
 * Per prisma.mdc: All mutations call createAuditLog.
 */

const crypto = require('crypto');
const userRepository = require('@repositories/user/user.repository');
const { createAuditLog } = require('@lib/audit');
const { hashPassword } = require('@lib/crypto');
const { HttpError } = require('@lib/errors');
const { publishCrudRealtimeEvent } = require('@lib/websocket/crud-realtime');
const { PLATFORM_ADMIN_EVENTS } = require('@lib/websocket/events');
const { ROLES } = require('@config/roles');
const { PERMISSIONS } = require('@config/permissions');
const { publishPlatformRealtimeEvent } = require('@lib/realtime/platform-realtime');
const {
  buildRealtimeEntityEnvelope,
  REALTIME_SYNC_ACTIONS
} = require('@lib/realtime/entity-envelope');
const { serializeAccessAdminUserEntity } = require('@lib/realtime/access-admin-realtime');
const {
  resolveEntityId,
  resolveIdentifierForPayload,
  resolvePublicIdentifier
} = require('@lib/billing/identifiers');
const { resolveModelIdByIdentifier } = require('@lib/identifiers/resolve-entity-id');
const { checkUserDuplicates } = require('@lib/user/user-similarity');
const { isPurgedAccount } = require('@lib/user/purged-account');
const {
  assertPermissionNamesIncludeRequiredReads,
} = require('@lib/authorization/permission-read-dependency');
const {
  PLATFORM_ADMIN_MANAGED_ROLES,
  assertPermissionIdsAssignable,
  assertRoleIdAssignable,
  canActorCreatePlatformRole,
  canActorCreateTenantWideRole,
  canActorManagePlatformAdmins,
} = require('@lib/authorization/assignable-access');
const { resolveRequestPermissionNames } = require('@lib/authorization/effective-access');
const { assertDemoUserNotMutable, assertUserIdNotDemoProtected } = require('@lib/authorization/demo-user-guard');
const { generateStaffNumber } = require('@lib/hr/staff-number');
const { normalizeRoleName } = require('@config/roles');
const prisma = require('@prisma/client');

const USER_SIMILARITY_LOOKUP_LIMIT = 500;
const ACTIVE_STATUS = 'ACTIVE';
const MAX_STAFF_NUMBER_ATTEMPTS = 3;

const text = (value) => String(value ?? '').trim();

/**
 * Strip credential material before a user record leaves the service, whether
 * in a response, an audit diff, or a realtime payload.
 */
const toPublicUser = (record) => {
  if (!record || typeof record !== 'object') {
    return record;
  }
  const { password_hash: _passwordHash, ...safe } = record;
  return safe;
};

const actorUserId = (actor) => actor?.id || actor?.user_id || actor?.userId || null;
const actorTenantId = (actor) => actor?.tenant_id || actor?.tenantId || null;
const actorFacilityId = (actor) => actor?.facility_id || actor?.facilityId || null;

/**
 * Only an authenticated request carries roles or permissions. Internal callers
 * (seeders, scripts) pass no actor and are not scope-checked here.
 */
const hasActorContext = (actor) =>
  Boolean(actor) &&
  typeof actor === 'object' &&
  (Array.isArray(actor.roles) || Array.isArray(actor.permissions));

const fieldError = (messageKey, statusCode, field, extra = {}) =>
  new HttpError(messageKey, statusCode, [{ field, message: messageKey, ...extra }]);

const loadTargetRoleNames = async (userId) => {
  const rows = await prisma.user_role.findMany({
    where: { user_id: userId, deleted_at: null },
    select: { role: { select: { name: true } } },
  });
  return rows
    .map((row) => normalizeRoleName(row?.role?.name))
    .filter(Boolean);
};

/**
 * Platform owners may CRUD every account. Non-owners cannot mutate users that
 * hold PLATFORM_ADMIN / PLATFORM_OWNER roles.
 */
const assertActorCanMutateTargetAccount = async (targetUserId, actor = {}) => {
  if (!targetUserId || canActorManagePlatformAdmins(actor)) {
    return;
  }
  const roleNames = await loadTargetRoleNames(targetUserId);
  if (roleNames.some((name) => PLATFORM_ADMIN_MANAGED_ROLES.has(name))) {
    throw new HttpError('errors.auth.insufficient_permissions', 403, [
      { field: 'user_id', reason: 'platform_admin_account_forbidden' },
    ]);
  }
};

/**
 * Non cross-tenant actors only manage accounts inside their own tenant.
 */
const assertActorWithinTenant = (tenantId, actor) => {
  if (!hasActorContext(actor) || canActorCreatePlatformRole(actor)) {
    return;
  }
  const ownTenantId = actorTenantId(actor);
  if (!ownTenantId || text(ownTenantId) !== text(tenantId)) {
    throw fieldError('errors.auth.scope_mismatch', 403, 'tenant_id', {
      reason: 'outside_actor_tenant',
    });
  }
};

const canActorPlaceTenantWideUser = (actor) =>
  canActorCreateTenantWideRole(actor) ||
  resolveRequestPermissionNames(actor).includes(PERMISSIONS.TENANT_ADMIN);

/**
 * Enforce where the actor may place an account.
 *
 * Mirrors the Flutter create form: cross-tenant admins choose any tenant;
 * tenant-wide admins stay in their tenant and may leave the facility blank for
 * an organization-wide account; facility-scoped admins (facility admin, HR)
 * must use their own facility.
 */
const assertActorCanPlaceUser = ({ tenantId, facilityId }, actor) => {
  if (!hasActorContext(actor) || canActorCreatePlatformRole(actor)) {
    return;
  }

  assertActorWithinTenant(tenantId, actor);

  if (canActorPlaceTenantWideUser(actor)) {
    return;
  }

  if (!text(facilityId)) {
    throw fieldError('errors.user.facility_required_for_scope', 400, 'facility_id');
  }
  const ownFacilityId = actorFacilityId(actor);
  if (!ownFacilityId || text(ownFacilityId) !== text(facilityId)) {
    throw fieldError('errors.user.facility_required_for_scope', 403, 'facility_id', {
      reason: 'outside_actor_facility',
    });
  }
};

const assertFacilityBelongsToTenant = async (facilityId, tenantId) => {
  if (!text(facilityId)) {
    return;
  }
  const facility = await userRepository.findFacilityScope(facilityId);
  if (!facility) {
    throw fieldError('errors.user.facility_not_found', 400, 'facility_id');
  }
  if (text(facility.tenant_id) !== text(tenantId)) {
    throw fieldError('errors.user.facility_tenant_mismatch', 400, 'facility_id');
  }
};

/**
 * A soft-deleted user still owns its email under the (tenant_id, email) index.
 * Report that against the email field instead of letting the insert fail.
 */
const assertEmailNotHeldByDeletedUser = async ({ tenantId, email, excludeUserId = null }) => {
  if (!text(tenantId) || !text(email)) {
    return;
  }
  const holder = await userRepository.findDeletedByTenantEmail(tenantId, email, excludeUserId);
  if (holder) {
    throw fieldError('errors.user.email_exists_deleted_in_tenant', 409, 'email', {
      restorable: true,
    });
  }
};

const toRoleFieldError = (error, roleId) => {
  if (!(error instanceof HttpError)) {
    return error;
  }
  const messageKey = error.messageKey || error.message;
  return new HttpError(messageKey, error.statusCode, [
    { field: 'role_ids', message: messageKey, role_id: roleId },
  ]);
};

/**
 * Validate requested roles before anything is written.
 *
 * Each role must be within the actor's assignment ceiling and belong to the new
 * account's tenant (or be a platform catalog role) and facility, so a created
 * user can never receive access from another tenant or facility.
 */
const resolveRoleAssignments = async (roleIds, { tenantId, facilityId }, actor) => {
  const requested = [
    ...new Set((Array.isArray(roleIds) ? roleIds : []).map(text).filter(Boolean))
  ];
  const assignments = new Map();

  for (const roleId of requested) {
    let role;
    try {
      role = await assertRoleIdAssignable(roleId, actor || {});
    } catch (error) {
      throw toRoleFieldError(error, roleId);
    }

    if (role.tenant_id && text(role.tenant_id) !== text(tenantId)) {
      throw fieldError('errors.user_role.role_tenant_mismatch', 400, 'role_ids', {
        role_id: roleId,
      });
    }
    if (role.facility_id && text(role.facility_id) !== text(facilityId)) {
      throw fieldError('errors.user_role.role_facility_mismatch', 400, 'role_ids', {
        role_id: roleId,
      });
    }

    assignments.set(role.id, { role_id: role.id, facility_id: facilityId || null });
  }

  return [...assignments.values()];
};

const buildStaffProfileSeed = async (input, { tenantId, positionTitle }) => {
  if (!input) {
    return null;
  }
  const { staff_number: staffNumber } = await generateStaffNumber({ tenantId });
  return {
    position: text(input.position) || positionTitle || null,
    staff_number: staffNumber
  };
};

/**
 * Create the account, retrying only when another staff record claimed the
 * generated staff number between generation and commit. Each attempt is a
 * complete transaction, so a failed attempt leaves nothing behind.
 */
const persistNewUser = async (payload, tenantId) => {
  let nextPayload = payload;
  for (let attempt = 1; attempt <= MAX_STAFF_NUMBER_ATTEMPTS; attempt += 1) {
    try {
      return await userRepository.create(nextPayload);
    } catch (error) {
      const staffNumberTaken =
        Boolean(nextPayload.staff_profile) &&
        error instanceof HttpError &&
        error.messageKey === 'errors.user.staff_number_conflict';
      if (!staffNumberTaken || attempt === MAX_STAFF_NUMBER_ATTEMPTS) {
        throw error;
      }
      const { staff_number: staffNumber } = await generateStaffNumber({ tenantId });
      nextPayload = {
        ...nextPayload,
        staff_profile: { ...nextPayload.staff_profile, staff_number: staffNumber }
      };
    }
  }
  return null;
};

const stripSimilarityPayloadFields = (data = {}) => {
  const { confirm_similar: _confirmSimilar, ...payload } = data;
  return payload;
};

const resolveUserId = async (identifier, { includeDeleted = false } = {}) => {
  const normalized = String(identifier ?? '').trim();
  if (!normalized) return normalized;

  if (includeDeleted) {
    const resolved = await resolveModelIdByIdentifier({
      model: 'user',
      identifier: normalized,
      includeDeleted: true});
    return resolved || normalized;
  }

  return resolveEntityId({ model: 'user', identifier: normalized });
};

const USER_REALTIME_RECIPIENT_ROLES = Object.freeze([
  ROLES.FACILITY_ADMIN,
  ROLES.TENANT_ADMIN
]);

const resolveUserRealtimeAction = (event) => {
  if (String(event || '').includes('deleted')) {
    return REALTIME_SYNC_ACTIONS.REMOVE;
  }
  return REALTIME_SYNC_ACTIONS.UPSERT;
};

const publishUserRealtimeEvent = async (event, user, actorUserIdValue) => {
  const action = resolveUserRealtimeAction(event);
  const entity =
    action === REALTIME_SYNC_ACTIONS.REMOVE
      ? {
          id: user?.human_friendly_id || user?.id || null
        }
      : serializeAccessAdminUserEntity(user);
  const envelope = buildRealtimeEntityEnvelope(action, entity, {
    resource_type: 'user'
  });

  await Promise.all([
    publishCrudRealtimeEvent({
      event,
      resource: toPublicUser(user),
      resource_type: 'user',
      actor_user_id: actorUserIdValue,
      recipient_roles: USER_REALTIME_RECIPIENT_ROLES,
      payload: envelope
    }),
    publishPlatformRealtimeEvent({
      event,
      resource_type: 'user',
      resource_id: user?.id || null,
      actor_user_id: actorUserIdValue,
      tenant_id: user?.tenant_id || null,
      facility_id: user?.facility_id || null,
      payload: {
        ...envelope,
        email: user?.email || null
      }
    })
  ]);
};

const BCRYPT_PREFIX_REGEX = /^\$2[aby]\$\d{2}\$/;
const USER_LIST_INCLUDE = Object.freeze({
  tenant: {
    select: {
      id: true,
      human_friendly_id: true,
      name: true,
      slug: true}},
  facility: {
    select: {
      id: true,
      human_friendly_id: true,
      name: true}},
  profile: {
    select: {
      first_name: true,
      middle_name: true,
      last_name: true}}});

const USER_DETAIL_INCLUDE = Object.freeze({
  tenant: {
    select: {
      id: true,
      human_friendly_id: true,
      name: true,
      slug: true}},
  facility: {
    select: {
      id: true,
      human_friendly_id: true,
      name: true}},
  profile: {
    select: {
      first_name: true,
      middle_name: true,
      last_name: true}},
  permissions: {
    where: { deleted_at: null },
    include: {
      permission: {
        select: {
          id: true,
          human_friendly_id: true,
          name: true,
          description: true}}}}});

const normalizeEmail = (value) => String(value || '').trim().toLowerCase();

const normalizePhoneDigits = (value) => {
  const digits = String(value || '').replace(/[^\d]/g, '');
  return digits || null;
};

/**
 * True when an update touches a detail that identifies the person, so
 * uniqueness and similarity review must run again. Status changes and
 * permission syncs never re-run it.
 */
const hasIdentityChange = (normalizedPayload, before = {}) => {
  if (
    normalizedPayload.email !== undefined &&
    normalizeEmail(normalizedPayload.email) !== normalizeEmail(before.email)
  ) {
    return true;
  }
  if (
    normalizedPayload.phone !== undefined &&
    normalizePhoneDigits(normalizedPayload.phone) !== normalizePhoneDigits(before.phone)
  ) {
    return true;
  }
  if (
    normalizedPayload.position_title !== undefined &&
    text(normalizedPayload.position_title) !== text(before.position_title)
  ) {
    return true;
  }
  if (
    normalizedPayload.facility_id !== undefined &&
    text(normalizedPayload.facility_id) !== text(before.facility_id)
  ) {
    return true;
  }
  const profile = normalizedPayload.profile;
  if (profile) {
    if (
      profile.first_name !== undefined &&
      text(profile.first_name) !== text(before.profile?.first_name)
    ) {
      return true;
    }
    if (
      profile.last_name !== undefined &&
      text(profile.last_name) !== text(before.profile?.last_name)
    ) {
      return true;
    }
  }
  return false;
};

/**
 * Load a broad, tenant-scoped peer set for user similarity review.
 *
 * Combines an alphabetical window with search-biased pages on email / phone /
 * position so strong identity matches past the alphabetical limit still surface.
 */
const loadUserSimilarityPeers = async ({
  tenantId,
  email,
  phone,
  positionTitle,
  firstName = null,
  lastName = null
}) => {
  const peerFilters = { tenant_id: tenantId };

  const alphabetical = await userRepository.findMany(
    peerFilters,
    0,
    USER_SIMILARITY_LOOKUP_LIMIT,
    { email: 'asc' },
    USER_LIST_INCLUDE
  );

  const emailTerm = String(email || '').trim();
  const phoneTerm = normalizePhoneDigits(phone) || '';
  const positionTerm = String(positionTitle || '').trim();
  const firstNameTerm = String(firstName || '').trim();
  const lastNameTerm = String(lastName || '').trim();
  const fullNameTerm = [firstNameTerm, lastNameTerm].filter(Boolean).join(' ').trim();
  const searchTerms = [
    ...new Set(
      [emailTerm, phoneTerm, positionTerm, firstNameTerm, lastNameTerm, fullNameTerm].filter(
        (term) => term.length > 0
      )
    )
  ];

  const searched = [];
  for (const term of searchTerms) {
    const page = await userRepository.findMany(
      {
        ...peerFilters,
        OR: [
          { email: { contains: term } },
          { phone: { contains: term } },
          { position_title: { contains: term } },
          { profile: { is: { first_name: { contains: term } } } },
          { profile: { is: { last_name: { contains: term } } } }
        ]
      },
      0,
      USER_SIMILARITY_LOOKUP_LIMIT,
      { email: 'asc' },
      USER_LIST_INCLUDE
    );
    if (Array.isArray(page)) {
      searched.push(...page);
    }
  }

  const seen = new Set();
  const existing = [];
  const combined = [
    ...searched,
    ...(Array.isArray(alphabetical) ? alphabetical : [])
  ];
  for (const user of combined) {
    const key = String(user?.id || user?.human_friendly_id || '').trim();
    if (!key || seen.has(key)) continue;
    seen.add(key);
    existing.push(user);
    if (existing.length >= USER_SIMILARITY_LOOKUP_LIMIT) break;
  }

  return existing;
};

const assertUserUniqueness = async ({
  tenantId,
  email,
  phone,
  positionTitle,
  firstName = null,
  middleName = null,
  lastName = null,
  facilityId = null,
  confirmSimilar = false,
  excludeUserId = null
}) => {
  const resolvedTenantId = String(tenantId || '').trim();
  if (!resolvedTenantId) {
    return null;
  }

  const existing = await loadUserSimilarityPeers({
    tenantId: resolvedTenantId,
    email,
    phone,
    positionTitle,
    firstName,
    lastName
  });

  const duplicateCheck = checkUserDuplicates({
    email,
    phone,
    positionTitle,
    firstName,
    middleName,
    lastName,
    facilityId,
    tenantId: resolvedTenantId,
    existing,
    excludeUserId
  });

  // Same-tenant exact email/phone is a hard uniqueness conflict that cannot be
  // overridden with confirm_similar. Keep the existing contact message keys but
  // attach the conflicting match payload so the client can hydrate the dialog.
  if (duplicateCheck.exactEmailConflict || duplicateCheck.exactPhoneConflict) {
    const exactMatches = duplicateCheck.similarMatches
      .filter((match) => match.exactEmailConflict || match.exactPhoneConflict)
      .slice(0, 5);
    const bothConflict =
      duplicateCheck.exactEmailConflict && duplicateCheck.exactPhoneConflict;
    const messageKey = bothConflict
      ? 'errors.user.contact_exists_in_tenant'
      : duplicateCheck.exactEmailConflict
        ? 'errors.user.email_exists_in_tenant'
        : 'errors.user.phone_exists_in_tenant';
    const field = duplicateCheck.exactEmailConflict ? 'email' : 'phone';
    throw new HttpError(messageKey, 409, [
      {
        field,
        message: messageKey,
        matches: exactMatches
      }
    ]);
  }

  const reviewMatches = duplicateCheck.overridableMatches.slice(0, 5);
  if (reviewMatches.length > 0 && !confirmSimilar) {
    throw new HttpError('errors.user.similar_exists', 409, [
      {
        field: 'email',
        matches: reviewMatches
      }
    ]);
  }

  return duplicateCheck;
};

const normalizeUserPayload = async (data, isUpdate = false, actor = null) => {
  const next = { ...(data || {}) };
  const normalizedPositionTitle = typeof next.position_title === 'string' ? next.position_title.trim() : '';
  const rawPassword = typeof next.password === 'string' ? next.password.trim() : '';
  const providedHash = typeof next.password_hash === 'string' ? next.password_hash.trim() : '';
  const permissionIds = Array.isArray(next.permission_ids)
    ? [...new Set(next.permission_ids.map((entry) => String(entry ?? '').trim()).filter(Boolean))]
    : undefined;

  const hasFirstName = Object.prototype.hasOwnProperty.call(next, 'first_name');
  const hasLastName = Object.prototype.hasOwnProperty.call(next, 'last_name');
  const normalizedFirstName = hasFirstName
    ? String(next.first_name || '').trim()
    : undefined;
  const normalizedLastName = hasLastName
    ? (next.last_name == null || String(next.last_name).trim() === ''
        ? null
        : String(next.last_name).trim())
    : undefined;

  if (!isUpdate) {
    if (!normalizedPositionTitle) {
      throw new HttpError('errors.validation.field.required', 400, [{ field: 'position_title' }]);
    }
    next.position_title = normalizedPositionTitle;
    if (!normalizedFirstName) {
      throw new HttpError('errors.validation.field.required', 400, [{ field: 'first_name' }]);
    }
  } else if (next.position_title !== undefined) {
    next.position_title = normalizedPositionTitle;
  }

  if (rawPassword) {
    next.password_hash = await hashPassword(rawPassword);
  } else if (providedHash) {
    next.password_hash = BCRYPT_PREFIX_REGEX.test(providedHash)
      ? providedHash
      : await hashPassword(providedHash);
  } else if (!isUpdate) {
    next.password_hash = await hashPassword(crypto.randomBytes(16).toString('hex'));
  }

  if (permissionIds !== undefined) {
    if (actor) {
      next.permission_ids = await assertPermissionIdsAssignable(
        permissionIds,
        actor,
        {
          tenantId: next.tenant_id || actor.tenant_id || actor.tenantId || null,
        }
      );
    } else {
      next.permission_ids = await Promise.all(
        permissionIds.map((permissionId) =>
          resolveIdentifierForPayload({
            value: permissionId,
            model: 'permission',
            field: 'permission_ids'})
        )
      );
      if (next.permission_ids.length > 0) {
        const permissionRecords = await prisma.permission.findMany({
          where: {
            id: { in: next.permission_ids },
            deleted_at: null,
          },
          select: { name: true },
        });
        assertPermissionNamesIncludeRequiredReads(
          permissionRecords.map((entry) => entry.name)
        );
      }
    }
  }

  if (next.tenant_id !== undefined) {
    next.tenant_id = await resolveIdentifierForPayload({
      value: next.tenant_id,
      model: 'tenant',
      field: 'tenant_id'});
  }

  if (next.facility_id !== undefined) {
    next.facility_id = await resolveIdentifierForPayload({
      value: next.facility_id,
      model: 'facility',
      field: 'facility_id',
      nullable: true});
  }

  if (typeof next.email === 'string') {
    next.email = normalizeEmail(next.email);
  }

  if (next.phone !== undefined && next.phone !== null) {
    const normalizedPhone = normalizePhoneDigits(next.phone);
    next.phone = normalizedPhone;
  }

  delete next.password;
  delete next.first_name;
  delete next.last_name;

  if (!isUpdate || hasFirstName || hasLastName) {
    next.profile = {
      ...(hasFirstName || !isUpdate ? { first_name: normalizedFirstName } : {}),
      ...(hasLastName || !isUpdate ? { last_name: normalizedLastName ?? null } : {})
    };
  }

  return next;
};

/**
 * List users with pagination and filtering
 *
 * @param {Object} filters - Query filters
 * @param {number} page - Page number
 * @param {number} limit - Items per page
 * @param {string} sortBy - Sort field
 * @param {string} order - Sort order
 * @param {string} userId - User ID for audit
 * @param {string} ipAddress - User IP for audit
 * @returns {Promise<Object>} Users and pagination data
 */
const listUsers = async (filters, page, limit, sortBy, order, userId, ipAddress) => {
  try {
    const includeDeleted =
      filters.include_deleted === true || filters.include_deleted === 'true';
    const skip = (page - 1) * limit;
    const orderBy = includeDeleted
      ? [{ deleted_at: 'asc' }, { [sortBy || 'created_at']: order || 'desc' }]
      : (sortBy ? { [sortBy]: order } : { created_at: 'desc' });

    // Build filter object
    const whereClause = {};

    if (filters.tenant_id) {
      whereClause.tenant_id = await resolveIdentifierForPayload({
        value: filters.tenant_id,
        model: 'tenant',
        field: 'tenant_id'});
    }
    if (filters.facility_id) {
      whereClause.facility_id = await resolveIdentifierForPayload({
        value: filters.facility_id,
        model: 'facility',
        field: 'facility_id'});
    }
    if (filters.position_title) whereClause.position_title = { contains: filters.position_title };
    if (filters.status) whereClause.status = filters.status;
    if (filters.email) whereClause.email = { contains: filters.email };

    // Search filter supports provider lookup by public ID, name, email, phone, and role/title.
    if (filters.search) {
      const searchTerm = String(filters.search).trim();
      const upperSearchTerm = searchTerm.toUpperCase();
      whereClause.OR = [
        { human_friendly_id: { contains: upperSearchTerm } },
        { email: { contains: searchTerm } },
        { phone: { contains: searchTerm } },
        { position_title: { contains: searchTerm } },
        {
          profile: {
            is: {
              OR: [
                { first_name: { contains: searchTerm } },
                { middle_name: { contains: searchTerm } },
                { last_name: { contains: searchTerm } }]}}}];
    }

    const listOptions = { includeDeleted };

    const [users, total] = await Promise.all([
      userRepository.findMany(whereClause, skip, limit, orderBy, USER_LIST_INCLUDE, listOptions),
      userRepository.count(whereClause, listOptions)
    ]);

    return {
      users: (Array.isArray(users) ? users : []).map(toPublicUser),
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
        hasNextPage: page < Math.ceil(total / limit),
        hasPreviousPage: page > 1
      }
    };
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Get user by ID
 *
 * @param {string} id - User ID
 * @param {string} userId - User ID for audit
 * @param {string} ipAddress - User IP for audit
 * @returns {Promise<Object>} User data
 */
const getUserById = async (id, userId, ipAddress) => {
  try {
    const resolvedUserId = await resolveUserId(id);
    const user = await userRepository.findById(resolvedUserId, USER_DETAIL_INCLUDE);

    if (!user) {
      throw new HttpError('errors.user.not_found', 404);
    }

    return toPublicUser(user);
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Create new user
 * Per prisma.mdc: Mutations must create audit logs
 *
 * Every check runs before the first write, and the user, profile, staff
 * profile, role assignments and direct permissions are persisted in one
 * transaction, so a rejected or failed create never leaves a partial account.
 *
 * @param {Object} data - User data
 * @param {string} userId - User ID for audit
 * @param {string} ipAddress - User IP for audit
 * @param {Object} [actor] - Authenticated actor (req.user)
 * @returns {Promise<Object>} Created user
 */
const createUser = async (data, userId, ipAddress, actor = null) => {
  try {
    const confirmSimilar = data?.confirm_similar === true;
    const {
      role_ids: roleIds,
      staff_profile: staffProfileInput,
      ...userInput
    } = stripSimilarityPayloadFields(data || {});
    const normalizedPayload = await normalizeUserPayload(
      userInput,
      false,
      actor || { id: userId }
    );
    const tenantId = normalizedPayload.tenant_id;
    const facilityId = normalizedPayload.facility_id ?? null;

    assertActorCanPlaceUser({ tenantId, facilityId }, actor);
    await assertFacilityBelongsToTenant(facilityId, tenantId);
    await assertEmailNotHeldByDeletedUser({ tenantId, email: normalizedPayload.email });
    await assertUserUniqueness({
      tenantId,
      email: normalizedPayload.email,
      phone: normalizedPayload.phone,
      positionTitle: normalizedPayload.position_title,
      firstName: normalizedPayload.profile?.first_name,
      middleName: normalizedPayload.profile?.middle_name,
      lastName: normalizedPayload.profile?.last_name,
      facilityId,
      confirmSimilar});
    const roleAssignments = await resolveRoleAssignments(
      roleIds,
      { tenantId, facilityId },
      actor
    );
    const staffProfile = await buildStaffProfileSeed(staffProfileInput, {
      tenantId,
      positionTitle: normalizedPayload.position_title
    });

    const created = await persistNewUser(
      {
        ...normalizedPayload,
        ...(roleAssignments.length > 0 ? { role_assignments: roleAssignments } : {}),
        ...(staffProfile ? { staff_profile: staffProfile } : {})
      },
      tenantId
    );
    const user = toPublicUser(created);

    // Create audit log (non-blocking)
    createAuditLog({
      user_id: userId,
      action: 'CREATE',
      entity: 'user',
      entity_id: user.id,
      diff: { after: user },
      ip_address: ipAddress
    }).catch(() => {});

    await publishUserRealtimeEvent(
      PLATFORM_ADMIN_EVENTS.USER_CREATED,
      user,
      userId
    );

    return user;
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Update user
 * Per prisma.mdc: Mutations must create audit logs
 *
 * @param {string} id - User ID
 * @param {Object} data - Update data
 * @param {string} userId - User ID for audit
 * @param {string} ipAddress - User IP for audit
 * @param {Object} [actor] - Authenticated actor (req.user)
 * @returns {Promise<Object>} Updated user
 */
const updateUser = async (id, data, userId, ipAddress, actor = {}) => {
  try {
    const resolvedUserId = await resolveUserId(id);
    // Get current state for audit
    const before = await userRepository.findById(resolvedUserId, USER_DETAIL_INCLUDE);

    if (!before) {
      throw new HttpError('errors.user.not_found', 404);
    }

    assertDemoUserNotMutable(before, 'update');
    await assertActorCanMutateTargetAccount(resolvedUserId, actor);
    assertActorWithinTenant(before.tenant_id, actor);

    const confirmSimilar = data?.confirm_similar === true;
    const strippedData = stripSimilarityPayloadFields(data || {});
    const normalizedPayload = await normalizeUserPayload(
      strippedData,
      true,
      actor
    );

    if (normalizedPayload.facility_id !== undefined) {
      if (text(normalizedPayload.facility_id) === text(before.facility_id)) {
        delete normalizedPayload.facility_id;
      } else {
        assertActorCanPlaceUser(
          { tenantId: before.tenant_id, facilityId: normalizedPayload.facility_id },
          actor
        );
        await assertFacilityBelongsToTenant(normalizedPayload.facility_id, before.tenant_id);
      }
    }

    const leavesActive =
      normalizedPayload.status !== undefined && normalizedPayload.status !== ACTIVE_STATUS;
    if (leavesActive && text(actorUserId(actor)) === text(resolvedUserId)) {
      throw fieldError('errors.user.cannot_deactivate_self', 400, 'status');
    }

    if (
      normalizedPayload.email !== undefined &&
      normalizeEmail(normalizedPayload.email) !== normalizeEmail(before.email)
    ) {
      await assertEmailNotHeldByDeletedUser({
        tenantId: before.tenant_id,
        email: normalizedPayload.email,
        excludeUserId: resolvedUserId
      });
    }

    // Status toggles and permission syncs must not be blocked by near-duplicate
    // review; only a change to identifying details re-runs uniqueness.
    if (hasIdentityChange(normalizedPayload, before)) {
      await assertUserUniqueness({
        tenantId: before.tenant_id,
        email: normalizedPayload.email ?? before.email,
        phone: normalizedPayload.phone ?? before.phone,
        positionTitle: normalizedPayload.position_title ?? before.position_title,
        firstName:
          normalizedPayload.profile?.first_name ?? before.profile?.first_name,
        middleName:
          normalizedPayload.profile?.middle_name ?? before.profile?.middle_name,
        lastName: normalizedPayload.profile?.last_name ?? before.profile?.last_name,
        facilityId: normalizedPayload.facility_id ?? before.facility_id,
        confirmSimilar,
        excludeUserId: resolvedUserId});
    }

    // An account that stops being ACTIVE loses every session in the same
    // transaction as the status change.
    const updated = await userRepository.update(resolvedUserId, normalizedPayload, {
      revokeSessions: leavesActive
    });
    const user = toPublicUser(updated);

    // Create audit log (non-blocking)
    createAuditLog({
      user_id: userId,
      action: 'UPDATE',
      entity: 'user',
      entity_id: user.id,
      diff: { before: toPublicUser(before), after: user },
      ip_address: ipAddress,
      ...(leavesActive ? { details: { sessions_revoked: true } } : {})
    }).catch(() => {});

    await publishUserRealtimeEvent(
      PLATFORM_ADMIN_EVENTS.USER_UPDATED,
      user,
      userId
    );

    return user;
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Delete user (soft delete)
 * Per prisma.mdc: Mutations must create audit logs
 *
 * @param {string} id - User ID
 * @param {string} userId - User ID for audit
 * @param {string} ipAddress - User IP for audit
 * @returns {Promise<void>}
 */
const deleteUser = async (id, userId, ipAddress, actor = {}) => {
  try {
    const resolvedUserId = await resolveUserId(id);
    // Get current state for audit
    const before = await userRepository.findById(resolvedUserId);

    if (!before) {
      throw new HttpError('errors.user.not_found', 404);
    }

    assertDemoUserNotMutable(before, 'delete');
    await assertActorCanMutateTargetAccount(resolvedUserId, actor);
    assertActorWithinTenant(before.tenant_id, actor);

    await userRepository.softDelete(resolvedUserId);

    // Create audit log (non-blocking)
    createAuditLog({
      user_id: userId,
      action: 'DELETE',
      entity: 'user',
      entity_id: resolvedUserId,
      diff: { before: toPublicUser(before) },
      ip_address: ipAddress
    }).catch(() => {});

    await publishUserRealtimeEvent(
      PLATFORM_ADMIN_EVENTS.USER_DELETED,
      before,
      userId
    );
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Restore soft-deleted user
 */
const restoreUser = async (id, userId, ipAddress, actor = {}) => {
  try {
    const resolvedUserId = await resolveUserId(id, { includeDeleted: true });
    const before = await userRepository.findById(resolvedUserId, {}, {
      includeDeleted: true,
    });
    if (before) {
      assertDemoUserNotMutable(before, 'restore');
    } else {
      await assertUserIdNotDemoProtected(resolvedUserId, 'restore');
    }
    await assertActorCanMutateTargetAccount(resolvedUserId, actor);
    const user = toPublicUser(await userRepository.restore(resolvedUserId));

    createAuditLog({
      user_id: userId,
      action: 'USER_RESTORED',
      entity: 'user',
      entity_id: resolvedUserId,
      diff: { after: user },
      ip_address: ipAddress}).catch(() => {});

    await publishUserRealtimeEvent(
      PLATFORM_ADMIN_EVENTS.USER_RESTORED,
      user,
      userId
    );

    return user;
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Permanently delete a soft-deleted user
 * Per prisma.mdc: Mutations must create audit logs
 *
 * History never blocks it: an account that records still reference is kept
 * only as their author, with every personal detail erased (see the repository).
 * The audit entry names the account by identifiers alone, so it keeps nothing
 * the purge erased.
 *
 * @param {string} id - User ID
 * @param {string} userId - User ID for audit
 * @param {string} ipAddress - User IP for audit
 * @param {Object} [actor] - Authenticated actor (req.user)
 * @returns {Promise<void>}
 */
const permanentDeleteUser = async (id, userId, ipAddress, actor = {}) => {
  try {
    const resolvedUserId = await resolveUserId(id, { includeDeleted: true });
    const before = await userRepository.findById(resolvedUserId, undefined, {
      includeDeleted: true
    });

    if (!before || isPurgedAccount(before)) {
      throw new HttpError('errors.user.not_found', 404);
    }
    if (!before.deleted_at) {
      throw new HttpError('errors.user.permanent_delete_not_soft_deleted', 400);
    }

    assertDemoUserNotMutable(before, 'delete');
    await assertActorCanMutateTargetAccount(resolvedUserId, actor);
    assertActorWithinTenant(before.tenant_id, actor);

    // Stored only if the row has to stay: a hash of random bytes nobody holds.
    const unusablePasswordHash = await hashPassword(crypto.randomBytes(32).toString('hex'));
    const {
      removed_access_rows: removedAccessRows,
      anonymized,
      history_tables: historyTables
    } = await userRepository.permanentDelete(resolvedUserId, { unusablePasswordHash });

    createAuditLog({
      user_id: userId,
      action: 'USER_PERMANENTLY_DELETED',
      entity: 'user',
      entity_id: resolvedUserId,
      diff: {
        before: {
          id: before.id,
          human_friendly_id: before.human_friendly_id ?? null,
          tenant_id: before.tenant_id,
          facility_id: before.facility_id ?? null
        },
        irreversible: true,
        anonymized,
        history_tables: historyTables,
        removed_access_rows: removedAccessRows
      },
      ip_address: ipAddress
    }).catch(() => {});

    await publishUserRealtimeEvent(
      PLATFORM_ADMIN_EVENTS.USER_PERMANENTLY_DELETED,
      before,
      userId
    );
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Issue a single-use credential reset for another account.
 *
 * The reset link and code reach the user only by email: nothing secret is
 * returned, logged, or written to the audit trail. The current password keeps
 * working until the link is used, and completing the reset revokes every
 * session for the account.
 *
 * @param {string} id - Target user identifier
 * @param {Object} actor - Authenticated actor (req.user)
 * @param {Object} [options]
 * @param {string} [options.ipAddress] - Actor IP for audit
 * @param {Object} [options.requestContext] - Origin, locale, timezone for the email
 * @returns {Promise<Object>} Masked destination, delivery status and expiry
 */
const resetUserCredentials = async (id, actor = {}, { ipAddress = null, requestContext = {} } = {}) => {
  try {
    const resolvedUserId = await resolveUserId(id);
    const target = await userRepository.findById(resolvedUserId, USER_LIST_INCLUDE);

    if (!target) {
      throw new HttpError('errors.user.not_found', 404);
    }

    assertDemoUserNotMutable(target, 'reset_credentials');
    await assertActorCanMutateTargetAccount(resolvedUserId, actor);
    assertActorWithinTenant(target.tenant_id, actor);

    if (!text(target.email)) {
      throw fieldError('errors.user.reset_requires_email', 400, 'email');
    }

    // Required lazily: the auth service owns the reset tokens and mail
    // templates, and loading it eagerly would couple every user import to them.
    const { issuePasswordReset } = require('@services/auth/auth.service');
    const issued = await issuePasswordReset({
      user: target,
      request_context: requestContext,
      context: 'admin_credentials_reset'
    });

    createAuditLog({
      user_id: actorUserId(actor),
      tenant_id: target.tenant_id,
      facility_id: target.facility_id || null,
      action: 'USER_CREDENTIALS_RESET_ISSUED',
      entity: 'user',
      entity_id: target.id,
      ip_address: ipAddress,
      details: {
        delivery_status: issued.delivery_status,
        expires_at: issued.expires_at
      }
    }).catch(() => {});

    return {
      user_id: resolvePublicIdentifier(target.human_friendly_id, target.id) || target.id,
      masked_email: issued.masked_email,
      delivery_status: issued.delivery_status,
      expires_at: issued.expires_at
    };
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Set another account's password directly, without emailing a reset link.
 *
 * The route schema enforces the password policy. Every session for the account
 * ends and any reset link already emailed stops working. The password and its
 * hash never reach the response or the audit trail. An actor's own password
 * changes through the change-password flow, which asks for the current one.
 *
 * @param {string} id - Target user identifier
 * @param {string} password - New password, already policy-checked
 * @param {Object} actor - Authenticated actor (req.user)
 * @param {Object} [options]
 * @param {string} [options.ipAddress] - Actor IP for audit
 * @returns {Promise<Object>} Public user identifier and sessions_revoked
 */
const setUserPassword = async (id, password, actor = {}, { ipAddress = null } = {}) => {
  try {
    const resolvedUserId = await resolveUserId(id);
    const target = await userRepository.findById(resolvedUserId);

    if (!target) {
      throw new HttpError('errors.user.not_found', 404);
    }

    assertDemoUserNotMutable(target, 'set_password');
    await assertActorCanMutateTargetAccount(resolvedUserId, actor);
    assertActorWithinTenant(target.tenant_id, actor);

    if (text(actorUserId(actor)) === text(resolvedUserId)) {
      throw fieldError('errors.user.set_password_self', 400, 'password');
    }

    await userRepository.setPassword(resolvedUserId, await hashPassword(password));

    createAuditLog({
      user_id: actorUserId(actor),
      tenant_id: target.tenant_id,
      facility_id: target.facility_id || null,
      action: 'USER_PASSWORD_SET',
      entity: 'user',
      entity_id: target.id,
      ip_address: ipAddress,
      details: { sessions_revoked: true }
    }).catch(() => {});

    return {
      user_id: resolvePublicIdentifier(target.human_friendly_id, target.id) || target.id,
      sessions_revoked: true
    };
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

module.exports = {
  listUsers,
  getUserById,
  createUser,
  updateUser,
  deleteUser,
  restoreUser,
  permanentDeleteUser,
  resetUserCredentials,
  setUserPassword};
