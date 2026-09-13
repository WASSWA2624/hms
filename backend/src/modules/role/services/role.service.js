/**
 * Role service
 *
 * @module modules/role/services
 * @description Business logic layer for role operations.
 * Per module-creation.mdc: Services only import/use their own repository.
 * Per prisma.mdc: All mutations call createAuditLog.
 */

const roleRepository = require('@repositories/role/role.repository');
const { createAuditLog } = require('@lib/audit');
const { HttpError } = require('@lib/errors');
const { resolveIdentifierForPayload, resolveEntityId } = require('@lib/billing/identifiers');
const { publishCrudRealtimeEvent } = require('@lib/websocket/crud-realtime');
const { PLATFORM_ADMIN_EVENTS } = require('@lib/websocket/events');
const { ROLES } = require('@config/roles');
const { publishPlatformRealtimeEvent } = require('@lib/realtime/platform-realtime');
const {
  buildRealtimeEntityEnvelope,
  REALTIME_SYNC_ACTIONS
} = require('@lib/realtime/entity-envelope');
const { serializeAccessAdminRoleEntity } = require('@lib/realtime/access-admin-realtime');
const {
  assertActorCanManageRoleRecord,
  assertRoleNotSystemProtected,
  assertRoleScopeAllowed,
  assertPermissionIdsAssignable,
  isCatalogProtectedRoleName,
} = require('@lib/authorization/assignable-access');
const { checkRoleDuplicates } = require('@lib/role/role-similarity');
const { findActivePlatformRoleByName } = require('@lib/authorization/platform-access-catalog');

const ROLE_REALTIME_RECIPIENT_ROLES = Object.freeze([ROLES.TENANT_ADMIN]);
const ROLE_SIMILARITY_LOOKUP_LIMIT = 500;

const stripSimilarityPayloadFields = (data = {}) => {
  const { confirm_similar: _confirmSimilar, ...payload } = data;
  return payload;
};

const assertRoleUniqueness = async ({
  data,
  tenantId,
  facilityId = null,
  confirmSimilar = false,
  excludeRoleId = null,
  includeDeletedPeers = true
}) => {
  const scopeTenantId =
    tenantId == null || String(tenantId).trim() === ''
      ? null
      : String(tenantId).trim();
  const scopeFacilityId =
    facilityId == null || String(facilityId).trim() === ''
      ? null
      : String(facilityId).trim();

  // Organizations use or extend platform roles; a same-name tenant role is a copy.
  if (scopeTenantId != null && (await findActivePlatformRoleByName(data?.name))) {
    throw new HttpError('errors.role.catalog_duplicate', 409, [
      { field: 'name', reason: 'platform_catalog_exists' },
    ]);
  }

  // Broad peer set for similarity: platform proposals scan all roles; tenant
  // proposals include every facility/org role in that tenant (not only the
  // exact facility_id). Same-scope hard conflicts stay in checkRoleDuplicates.
  // Soft-deleted peers are included on create so a soft-deleted same-scope
  // identity cannot be recreated as a second active role.
  const peerFilters =
    scopeTenantId == null
      ? {}
      : {
          OR: [
            { tenant_id: scopeTenantId },
            { tenant_id: null, facility_id: null }
          ]
        };

  const alphabetical = await roleRepository.findMany(
    peerFilters,
    0,
    ROLE_SIMILARITY_LOOKUP_LIMIT,
    { name: 'asc' },
    { includeDeleted: includeDeletedPeers }
  );

  // Search-biased peers catch identity matches that sit past the alphabetical
  // lookup window (e.g. TESTING when many earlier names fill the limit).
  const nameTerm = String(data?.name || '').trim();
  const displayTerm = String(data?.display_name || data?.displayName || '').trim();
  const searchTerms = [...new Set(
    [nameTerm, displayTerm].filter((term) => term.length > 0)
  )];
  const searched = [];
  for (const term of searchTerms) {
    const searchOr = [
      { name: { contains: term } },
      { display_name: { contains: term } }
    ];
    const searchFilters = peerFilters.OR
      ? {
          AND: [{ OR: peerFilters.OR }, { OR: searchOr }]
        }
      : { OR: searchOr };
    const page = await roleRepository.findMany(
      searchFilters,
      0,
      ROLE_SIMILARITY_LOOKUP_LIMIT,
      { name: 'asc' },
      { includeDeleted: includeDeletedPeers }
    );
    searched.push(...page);
  }

  const seen = new Set();
  const existing = [];
  for (const role of [...searched, ...alphabetical]) {
    const key = String(role?.id || role?.human_friendly_id || '').trim();
    if (!key || seen.has(key)) continue;
    seen.add(key);
    existing.push(role);
    if (existing.length >= ROLE_SIMILARITY_LOOKUP_LIMIT) break;
  }

  const duplicateCheck = checkRoleDuplicates({
    name: data.name,
    displayName: data.display_name,
    description: data.description,
    tenantId: scopeTenantId,
    facilityId: scopeFacilityId,
    existing,
    excludeRoleId
  });

  if (duplicateCheck.exactNameConflict) {
    throw new HttpError('errors.role.duplicate_name', 409, [
      {
        field: 'name',
        matches: duplicateCheck.similarMatches
          .filter((match) => match.exactNameConflict)
          .slice(0, 5)
      }
    ]);
  }

  const reviewMatches = duplicateCheck.overridableMatches.slice(0, 5);
  if (reviewMatches.length > 0 && !confirmSimilar) {
    throw new HttpError('errors.role.similar_exists', 409, [
      {
        field: 'name',
        matches: reviewMatches
      }
    ]);
  }

  return duplicateCheck;
};

const resolveRoleRealtimeAction = (event) => {
  if (String(event || '').includes('deleted')) {
    return REALTIME_SYNC_ACTIONS.REMOVE;
  }
  return REALTIME_SYNC_ACTIONS.UPSERT;
};

const publishRoleRealtimeEvent = async (event, role, actorUserId) => {
  const action = resolveRoleRealtimeAction(event);
  const entity =
    action === REALTIME_SYNC_ACTIONS.REMOVE
      ? {
          id: role?.human_friendly_id || role?.id || null
        }
      : serializeAccessAdminRoleEntity(role);
  const envelope = buildRealtimeEntityEnvelope(action, entity, {
    resource_type: 'role'
  });

  await Promise.all([
    publishCrudRealtimeEvent({
      event,
      resource: role,
      resource_type: 'role',
      actor_user_id: actorUserId,
      recipient_roles: ROLE_REALTIME_RECIPIENT_ROLES,
      payload: envelope
    }),
    publishPlatformRealtimeEvent({
      event,
      resource_type: 'role',
      resource_id: role?.id || null,
      actor_user_id: actorUserId,
      tenant_id: role?.tenant_id || null,
      facility_id: role?.facility_id || null,
      payload: {
        ...envelope,
        name: role?.name || null
      }
    })
  ]);
};

const resolveRoleId = async (identifier, { includeDeleted = false } = {}) =>
  resolveEntityId({
    model: 'role',
    identifier,
    where: includeDeleted ? {} : { deleted_at: null },
    includeDeleted
  });

const normalizeCreateRolePayload = async (data = {}) => {
  const { scope, ...fields } = data || {};
  const payload = { ...fields };
  const normalizedScope = String(scope || '').trim().toLowerCase();

  // Explicit platform scope wins over any tenant_id injected by middleware.
  if (normalizedScope === 'platform') {
    payload.tenant_id = null;
    payload.facility_id = null;
    return payload;
  }

  if (data.tenant_id == null || String(data.tenant_id).trim() === '') {
    payload.tenant_id = null;
  } else {
    payload.tenant_id = await resolveIdentifierForPayload({
      value: data.tenant_id,
      model: 'tenant',
      field: 'tenant_id',
      nullable: true
    });
  }

  if (data.facility_id != null && String(data.facility_id).trim() !== '') {
    payload.facility_id = await resolveIdentifierForPayload({
      value: data.facility_id,
      model: 'facility',
      field: 'facility_id',
      nullable: true});
  } else {
    payload.facility_id = null;
  }

  return payload;
};

/**
 * List roles with pagination and filtering
 *
 * @param {Object} filters - Query filters
 * @param {number} page - Page number
 * @param {number} limit - Items per page
 * @param {string} sortBy - Sort field
 * @param {string} order - Sort order
 * @param {string} userId - User ID for audit
 * @param {string} ipAddress - User IP for audit
 * @returns {Promise<Object>} Roles and pagination data
 */
const listRoles = async (filters, page, limit, sortBy, order, userId, ipAddress) => {
  try {
    const skip = (page - 1) * limit;
    const orderBy = sortBy ? { [sortBy]: order } : { created_at: 'desc' };

    // Build filter object
    const whereClause = {};
    
    if (filters.tenant_id) whereClause.tenant_id = filters.tenant_id;
    if (filters.facility_id) whereClause.facility_id = filters.facility_id;
    if (filters.name) whereClause.name = { contains: filters.name };
    
    // Search filter (searches in name, display name, and description)
    if (filters.search) {
      whereClause.OR = [
        { name: { contains: filters.search } },
        { display_name: { contains: filters.search } },
        { description: { contains: filters.search } }
      ];
    }

    const [roles, total] = await Promise.all([
      roleRepository.findMany(whereClause, skip, limit, orderBy),
      roleRepository.count(whereClause)
    ]);

    return {
      roles,
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
 * Get role by ID
 *
 * @param {string} id - Role ID
 * @param {string} userId - User ID for audit
 * @param {string} ipAddress - User IP for audit
 * @returns {Promise<Object>} Role data
 */
const getRoleById = async (id, userId, ipAddress) => {
  try {
    const resolvedRoleId = await resolveRoleId(id);
    const role = await roleRepository.findById(resolvedRoleId);

    if (!role) {
      throw new HttpError('errors.role.not_found', 404);
    }

    return serializeAccessAdminRoleEntity(role);
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Create new role
 * Per prisma.mdc: Mutations must create audit logs
 *
 * @param {Object} data - Role data
 * @param {string} userId - User ID for audit
 * @param {string} ipAddress - User IP for audit
 * @returns {Promise<Object>} Created role
 */
const createRole = async (data, userId, ipAddress, actor = null) => {
  try {
    const confirmSimilar = data?.confirm_similar === true;
    const {
      permission_ids: permissionIdsInput,
      ...roleFieldsWithConfirm
    } = data || {};
    const roleFields = stripSimilarityPayloadFields(roleFieldsWithConfirm);
    const payload = await normalizeCreateRolePayload(roleFields);
    const scopedPayload = await assertRoleScopeAllowed(payload, actor || { id: userId });
    if (isCatalogProtectedRoleName(scopedPayload.name)) {
      // Default/system roles live once in the platform catalog — never duplicate.
      throw new HttpError('errors.role.catalog_duplicate', 409, [
        { field: 'name', reason: 'platform_catalog_exists' },
      ]);
    }
    await assertRoleUniqueness({
      data: scopedPayload,
      tenantId: scopedPayload.tenant_id,
      facilityId: scopedPayload.facility_id,
      confirmSimilar
    });
    const permissionIds = await assertPermissionIdsAssignable(
      permissionIdsInput,
      actor || { id: userId },
      { tenantId: scopedPayload.tenant_id || null }
    );
    const role = await roleRepository.create(scopedPayload, permissionIds);

    // Create audit log (non-blocking)
    createAuditLog({
      user_id: userId,
      action: 'CREATE',
      entity: 'role',
      entity_id: role.id,
      diff: { after: role, permission_ids: permissionIds },
      ip_address: ipAddress
    }).catch(() => {});

    await publishRoleRealtimeEvent(
      PLATFORM_ADMIN_EVENTS.ROLE_CREATED,
      role,
      userId
    );

    return serializeAccessAdminRoleEntity(role);
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Update role
 * Per prisma.mdc: Mutations must create audit logs
 *
 * @param {string} id - Role ID
 * @param {Object} data - Update data
 * @param {string} userId - User ID for audit
 * @param {string} ipAddress - User IP for audit
 * @returns {Promise<Object>} Updated role
 */
const updateRole = async (id, data, userId, ipAddress, actor = null) => {
  try {
    const resolvedRoleId = await resolveRoleId(id);
    // Get current state for audit
    const before = await roleRepository.findById(resolvedRoleId);

    if (!before) {
      throw new HttpError('errors.role.not_found', 404);
    }

    const actorUser = actor || { id: userId };
    assertActorCanManageRoleRecord(before, actorUser);
    assertRoleNotSystemProtected(before, 'update', actorUser);

    const confirmSimilar = data?.confirm_similar === true;
    const { permission_ids: permissionIdsInput, ...roleFieldsWithConfirm } =
      data || {};
    const roleFields = stripSimilarityPayloadFields(roleFieldsWithConfirm);
    const payload = { ...roleFields };

    const hasScopeHint =
      Object.prototype.hasOwnProperty.call(roleFields, 'scope') ||
      Object.prototype.hasOwnProperty.call(roleFields, 'facility_id') ||
      // tenant_id alone is often injected by tenant-scope middleware on
      // permission-only PUTs — require explicit `scope` to treat as ABAC change.
      (Object.prototype.hasOwnProperty.call(roleFields, 'tenant_id') &&
        Object.prototype.hasOwnProperty.call(roleFields, 'scope'));

    if (hasScopeHint) {
      const scoped = await normalizeCreateRolePayload({
        scope: roleFields.scope,
        tenant_id: Object.prototype.hasOwnProperty.call(roleFields, 'tenant_id')
          ? roleFields.tenant_id
          : before.tenant_id,
        facility_id: Object.prototype.hasOwnProperty.call(roleFields, 'facility_id')
          ? roleFields.facility_id
          : before.facility_id,
      });
      // Scope updates always set both keys so platform clears tenant/facility.
      payload.tenant_id = scoped.tenant_id;
      payload.facility_id = scoped.facility_id;
      delete payload.scope;

      await assertRoleScopeAllowed(
        {
          tenant_id: payload.tenant_id,
          facility_id: payload.facility_id,
        },
        actorUser
      );
    }

    const nextName = Object.prototype.hasOwnProperty.call(payload, 'name')
      ? payload.name
      : before.name;
    const nextDisplayName = Object.prototype.hasOwnProperty.call(
      payload,
      'display_name'
    )
      ? payload.display_name
      : before.display_name;
    const nextDescription = Object.prototype.hasOwnProperty.call(
      payload,
      'description'
    )
      ? payload.description
      : before.description;
    const nextTenantId = Object.prototype.hasOwnProperty.call(payload, 'tenant_id')
      ? payload.tenant_id
      : before.tenant_id;
    const nextFacilityId = Object.prototype.hasOwnProperty.call(
      payload,
      'facility_id'
    )
      ? payload.facility_id
      : before.facility_id;

    const identityChanged =
      String(nextName || '') !== String(before.name || '') ||
      String(nextDisplayName || '') !== String(before.display_name || '') ||
      String(nextDescription || '') !== String(before.description || '') ||
      String(nextTenantId || '') !== String(before.tenant_id || '') ||
      String(nextFacilityId || '') !== String(before.facility_id || '');

    if (identityChanged) {
      await assertRoleUniqueness({
        data: {
          name: nextName,
          display_name: nextDisplayName,
          description: nextDescription
        },
        tenantId: nextTenantId,
        facilityId: nextFacilityId,
        confirmSimilar,
        excludeRoleId: resolvedRoleId
      });
    }

    const shouldSyncPermissions = Object.prototype.hasOwnProperty.call(
      data || {},
      'permission_ids'
    );
    const permissionIds = shouldSyncPermissions
      ? await assertPermissionIdsAssignable(
          permissionIdsInput,
          actorUser,
          { tenantId: nextTenantId || null }
        )
      : null;

    const role =
      Object.keys(payload).length > 0
        ? await roleRepository.update(resolvedRoleId, payload)
        : before;

    if (shouldSyncPermissions) {
      await roleRepository.syncPermissions(resolvedRoleId, permissionIds);
    }

    // Create audit log (non-blocking)
    createAuditLog({
      user_id: userId,
      action: 'UPDATE',
      entity: 'role',
      entity_id: role.id,
      diff: {
        before,
        after: role,
        ...(shouldSyncPermissions ? { permission_ids: permissionIds } : {})},
      ip_address: ipAddress
    }).catch(() => {});

    await publishRoleRealtimeEvent(
      PLATFORM_ADMIN_EVENTS.ROLE_UPDATED,
      role,
      userId
    );

    return serializeAccessAdminRoleEntity(role);
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Delete role (soft delete)
 * Per prisma.mdc: Mutations must create audit logs
 *
 * @param {string} id - Role ID
 * @param {string} userId - User ID for audit
 * @param {string} ipAddress - User IP for audit
 * @returns {Promise<void>}
 */
const deleteRole = async (id, userId, ipAddress, actor = null) => {
  try {
    const resolvedRoleId = await resolveRoleId(id);
    // Get current state for audit
    const before = await roleRepository.findById(resolvedRoleId);

    if (!before) {
      throw new HttpError('errors.role.not_found', 404);
    }

    const actorUser = actor || { id: userId };
    assertActorCanManageRoleRecord(before, actorUser);
    assertRoleNotSystemProtected(before, 'delete', actorUser);

    const { role, detached_user_assignments: detachedUserAssignments } =
      await roleRepository.softDelete(resolvedRoleId);

    // Create audit log (non-blocking)
    createAuditLog({
      user_id: userId,
      action: 'DELETE',
      entity: 'role',
      entity_id: resolvedRoleId,
      diff: {
        before,
        after: role,
        detached_user_assignments: detachedUserAssignments},
      ip_address: ipAddress
    }).catch(() => {});

    await publishRoleRealtimeEvent(
      PLATFORM_ADMIN_EVENTS.ROLE_DELETED,
      before,
      userId
    );
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Restore soft-deleted role and matching permission / user-role links.
 */
const restoreRole = async (id, userId, ipAddress, actor = null) => {
  try {
    const resolvedRoleId = await resolveRoleId(id, { includeDeleted: true });
    if (!resolvedRoleId) {
      throw new HttpError('errors.role.not_found', 404);
    }
    const before = await roleRepository.findById(resolvedRoleId, {
      includeDeleted: true
    });

    if (!before || !before.deleted_at) {
      throw new HttpError('errors.role.not_found', 404);
    }

    const actorUser = actor || { id: userId };
    assertActorCanManageRoleRecord(before, actorUser);
    assertRoleNotSystemProtected(before, 'restore', actorUser);

    // Block restore when an active same-scope role already owns this identity.
    await assertRoleUniqueness({
      data: before,
      tenantId: before.tenant_id,
      facilityId: before.facility_id,
      confirmSimilar: true,
      excludeRoleId: before.id,
      includeDeletedPeers: false
    });

    const {
      role,
      restored_permissions: restoredPermissions,
      restored_user_assignments: restoredUserAssignments
    } = await roleRepository.restore(resolvedRoleId);

    createAuditLog({
      user_id: userId,
      action: 'ROLE_RESTORED',
      entity: 'role',
      entity_id: resolvedRoleId,
      diff: {
        before,
        after: role,
        restored_permissions: restoredPermissions,
        restored_user_assignments: restoredUserAssignments
      },
      ip_address: ipAddress
    }).catch(() => {});

    await publishRoleRealtimeEvent(
      PLATFORM_ADMIN_EVENTS.ROLE_RESTORED,
      role,
      userId
    );

    return serializeAccessAdminRoleEntity(role);
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Permanently delete a soft-deleted role after removing it from every attached user.
 */
const permanentDeleteRole = async (id, userId, ipAddress, actor = null) => {
  try {
    const resolvedRoleId = await resolveRoleId(id, { includeDeleted: true });
    if (!resolvedRoleId) {
      throw new HttpError('errors.role.not_found', 404);
    }
    const before = await roleRepository.findById(resolvedRoleId, {
      includeDeleted: true
    });

    // resolveEntityId may return an unresolved friendly id when lookup misses;
    // never treat that as a successful purge.
    if (!before) {
      throw new HttpError('errors.role.not_found', 404);
    }
    if (!before.deleted_at) {
      throw new HttpError('errors.role.permanent_delete_requires_soft_delete', 400);
    }

    const actorUser = actor || { id: userId };
    assertActorCanManageRoleRecord(before, actorUser);
    assertRoleNotSystemProtected(before, 'delete', actorUser);

    const {
      removed_user_ids: removedUserIds,
      removed_user_assignments: removedUserAssignments,
      removed_permissions: removedPermissions
    } = await roleRepository.permanentDelete(before.id);

    createAuditLog({
      user_id: userId,
      action: 'ROLE_PERMANENTLY_DELETED',
      entity: 'role',
      entity_id: before.id,
      diff: {
        before,
        irreversible: true,
        removed_user_ids: removedUserIds,
        removed_user_assignments: removedUserAssignments,
        removed_permissions: removedPermissions
      },
      ip_address: ipAddress
    }).catch(() => {});

    await publishRoleRealtimeEvent(
      PLATFORM_ADMIN_EVENTS.ROLE_PERMANENTLY_DELETED,
      before,
      userId
    );
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

module.exports = {
  listRoles,
  getRoleById,
  createRole,
  updateRole,
  deleteRole,
  restoreRole,
  permanentDeleteRole
};
