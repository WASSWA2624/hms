/**
 * User repository
 *
 * @module modules/user/repositories
 * @description Data access layer for user operations.
 * Per module-creation.mdc: Only standard CRUD operations allowed in repositories.
 * Per prisma.mdc: All queries use soft delete filtering (deleted_at: null).
 */

const prisma = require('@prisma/client');
const { HttpError } = require('@lib/errors');
const {
  countReferencingRows,
  deleteReferencingRows,
  listForeignKeyReferences
} = require('@lib/database/foreign-key-references');
const {
  PURGED_ACCOUNT_NAME,
  isPurgedAccount,
  notPurgedWhere,
  purgedEmailFor
} = require('@lib/user/purged-account');
const { runWithoutTenantGuard } = require('../../../prisma/tenant-guard');

/**
 * Tenant-guard findFirst/findUnique inject `deleted_at: null` unless the caller
 * already mentions `deleted_at`. Soft-deleted lookups must either mention it or
 * bypass the guard — otherwise restore never sees the row.
 */
const userWhereById = (id, { includeDeleted = false } = {}) =>
  includeDeleted
    ? {
        id,
        OR: [{ deleted_at: null }, { deleted_at: { not: null } }],
      }
    : { id, deleted_at: null };

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
      id: true,
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

const resolveInclude = (include) => ({
  ...USER_DETAIL_INCLUDE,
  ...include});

// Create returns the assignments made in the same transaction so the caller can
// publish and audit the complete account without a second read.
const USER_CREATE_RESULT_INCLUDE = Object.freeze({
  roles: {
    where: { deleted_at: null },
    include: {
      role: {
        select: {
          id: true,
          human_friendly_id: true,
          name: true}}}},
  staff_profile: {
    select: {
      id: true,
      human_friendly_id: true,
      staff_number: true,
      position: true}}});

const normalizePermissionIds = (value) => (
  Array.isArray(value)
    ? [...new Set(value.map((entry) => String(entry ?? '').trim()).filter(Boolean))]
    : []
);

const mapUniqueConstraintField = (target) => {
  const fields = Array.isArray(target)
    ? target.map((entry) => String(entry))
    : [String(target || '')];
  if (fields.some((entry) => entry.includes('email'))) {
    return 'email';
  }
  if (fields.some((entry) => entry.includes('phone'))) {
    return 'phone';
  }
  if (fields.some((entry) => entry.includes('staff_number'))) {
    return 'staff_number';
  }
  return fields.find((entry) => entry && entry !== 'tenant_id') || 'field';
};

/**
 * Collect every place a unique-violation names its constraint.
 *
 * Prisma only fills `meta.target` for some drivers; with the MariaDB adapter the
 * constraint arrives under `meta.driverAdapterError.cause`. Reading both keeps a
 * duplicate email reported against the email field instead of as a generic
 * database error.
 */
const resolveUniqueConstraintTarget = (error) => {
  const meta = error?.meta || {};
  const cause = meta.driverAdapterError?.cause || {};
  const candidates = [
    meta.target,
    cause.constraint?.fields,
    cause.constraint?.index,
    cause.originalMessage,
    error?.message]
    .flat()
    .filter(Boolean)
    .map((entry) => String(entry));
  return candidates.length > 0 ? candidates : meta.target;
};

const UNIQUE_FIELD_MESSAGE_KEYS = Object.freeze({
  email: 'errors.user.email_exists_in_tenant',
  phone: 'errors.user.phone_exists_in_tenant',
  staff_number: 'errors.user.staff_number_conflict'});

const toUniqueConflictError = (error) => {
  const field = mapUniqueConstraintField(resolveUniqueConstraintTarget(error));
  const messageKey = UNIQUE_FIELD_MESSAGE_KEYS[field] || 'errors.database.unique_field';
  return new HttpError(messageKey, 409, [{ field, message: messageKey }]);
};

const findActiveByTenantEmail = async (tenantId, email, excludeUserId = null) => {
  if (!tenantId || !email) {
    return null;
  }

  return prisma.user.findFirst({
    where: {
      tenant_id: tenantId,
      deleted_at: null,
      email,
      ...(excludeUserId ? { NOT: { id: excludeUserId } } : {})},
    select: { id: true }});
};

const findActiveByTenantPhone = async (tenantId, phone, excludeUserId = null) => {
  if (!tenantId || !phone) {
    return null;
  }

  const normalizedDigits = String(phone).replace(/[^\d]/g, '');
  if (!normalizedDigits) {
    return null;
  }

  const baseWhere = {
    tenant_id: tenantId,
    deleted_at: null,
    ...(excludeUserId ? { NOT: { id: excludeUserId } } : {})};

  const exactMatch = await prisma.user.findFirst({
    where: {
      ...baseWhere,
      phone},
    select: { id: true }});
  if (exactMatch) {
    return exactMatch;
  }

  const candidates = await prisma.user.findMany({
    where: {
      ...baseWhere,
      phone: { not: null }},
    select: { id: true, phone: true }});

  return (
    candidates.find(
      (entry) =>
        entry.phone &&
        String(entry.phone).replace(/[^\d]/g, '') === normalizedDigits
    ) || null
  );
};

/**
 * Find a soft-deleted user that still holds an email within a tenant.
 *
 * The (tenant_id, email) unique index covers deleted rows too, so without this
 * check a create or email change fails at the database with nothing the form
 * can show against the email field.
 */
const findDeletedByTenantEmail = async (tenantId, email, excludeUserId = null) => {
  if (!tenantId || !email) {
    return null;
  }

  try {
    return await prisma.user.findFirst({
      where: {
        tenant_id: tenantId,
        email,
        deleted_at: { not: null },
        ...(excludeUserId ? { NOT: { id: excludeUserId } } : {})},
      select: { id: true, human_friendly_id: true }});
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Resolve the tenant that owns a facility.
 *
 * @param {string} facilityId - Facility ID
 * @returns {Promise<{id: string, tenant_id: string}|null>}
 */
const findFacilityScope = async (facilityId) => {
  if (!facilityId) {
    return null;
  }

  try {
    return await prisma.facility.findFirst({
      where: { id: facilityId, deleted_at: null },
      select: { id: true, tenant_id: true }});
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

const syncUserPermissions = async (tx, userId, permissionIds = []) => {
  const selectedPermissionIds = normalizePermissionIds(permissionIds);
  const existingRecords = await tx.user_permission.findMany({
    where: { user_id: userId }});
  const selectedSet = new Set(selectedPermissionIds);
  const existingByPermissionId = new Map(
    existingRecords.map((record) => [String(record.permission_id ?? '').trim(), record])
  );
  const deletedAt = new Date();

  const updates = [];

  existingRecords.forEach((record) => {
    const permissionId = String(record.permission_id ?? '').trim();
    const isSelected = selectedSet.has(permissionId);
    const isDeleted = Boolean(record.deleted_at);

    if (!isSelected && !isDeleted) {
      updates.push(
        tx.user_permission.update({
          where: { id: record.id },
          data: { deleted_at: deletedAt }})
      );
      return;
    }

    if (isSelected && isDeleted) {
      updates.push(
        tx.user_permission.update({
          where: { id: record.id },
          data: { deleted_at: null }})
      );
    }
  });

  selectedPermissionIds.forEach((permissionId) => {
    if (existingByPermissionId.has(permissionId)) return;
    updates.push(
      tx.user_permission.create({
        data: {
          user_id: userId,
          permission_id: permissionId}})
    );
  });

  if (updates.length > 0) {
    await Promise.all(updates);
  }
};

const buildWhereClause = (filters = {}, { includeDeleted = false } = {}) => {
  const where = { ...filters };
  if (!includeDeleted) {
    where.deleted_at = null;
  } else {
    // Purged accounts are deleted too, but gone for good: they never list.
    where.AND = [...[].concat(where.AND ?? []), notPurgedWhere()];
  }
  return where;
};

/**
 * Find user by ID
 *
 * @param {string} id - User ID
 * @param {Object} include - Relations to include
 * @param {Object} [options]
 * @param {boolean} [options.includeDeleted]
 * @returns {Promise<Object|null>} User object or null
 */
const findById = async (id, include, { includeDeleted = false } = {}) => {
  try {
    return await prisma.user.findFirst({
      where: userWhereById(id, { includeDeleted }),
      include
    });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Find many users with pagination
 *
 * @param {Object} filters - Filter criteria
 * @param {number} skip - Number of records to skip
 * @param {number} take - Number of records to take
 * @param {Object} orderBy - Sort order
 * @param {Object} include - Relations to include
 * @param {Object} [options]
 * @param {boolean} [options.includeDeleted]
 * @returns {Promise<Array>} Array of users
 */
const findMany = async (
  filters = {},
  skip = 0,
  take = 20,
  orderBy = { created_at: 'desc' },
  include,
  { includeDeleted = false } = {}
) => {
  try {
    return await prisma.user.findMany({
      where: buildWhereClause(filters, { includeDeleted }),
      skip,
      take,
      orderBy,
      include
    });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Count users with filters
 *
 * @param {Object} filters - Filter criteria
 * @param {Object} [options]
 * @param {boolean} [options.includeDeleted]
 * @returns {Promise<number>} Count of users
 */
const count = async (filters = {}, { includeDeleted = false } = {}) => {
  try {
    return await prisma.user.count({
      where: buildWhereClause(filters, { includeDeleted })});
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Create new user
 *
 * @param {Object} data - User data
 * @returns {Promise<Object>} Created user
 */
const create = async (data) => {
  try {
    const {
      permission_ids,
      profile,
      role_assignments,
      staff_profile,
      ...userData
    } = data || {};
    const permissionIds = normalizePermissionIds(permission_ids);
    const roleAssignments = Array.isArray(role_assignments) ? role_assignments : [];

    // The user, profile, staff profile, role assignments and direct permissions
    // commit together: any failure rolls every row back, so no partial account
    // is ever left behind.
    return await prisma.$transaction(async (tx) => {
      const createdUser = await tx.user.create({
        data: {
          ...userData,
          ...(profile
            ? {
                profile: {
                  create: {
                    first_name: profile.first_name,
                    last_name: profile.last_name ?? null,
                    facility_id: userData.facility_id ?? null
                  }
                }
              }
            : {})
        }
      });

      if (staff_profile) {
        await tx.staff_profile.create({
          data: {
            tenant_id: createdUser.tenant_id,
            user_id: createdUser.id,
            position: staff_profile.position ?? null,
            staff_number: staff_profile.staff_number ?? null}});
      }

      for (const assignment of roleAssignments) {
        await tx.user_role.create({
          data: {
            user_id: createdUser.id,
            role_id: assignment.role_id,
            tenant_id: createdUser.tenant_id,
            facility_id: assignment.facility_id ?? null}});
      }

      if (permissionIds.length > 0) {
        await syncUserPermissions(tx, createdUser.id, permissionIds);
      }

      return await tx.user.findFirst({
        where: {
          id: createdUser.id,
          deleted_at: null},
        include: resolveInclude(USER_CREATE_RESULT_INCLUDE)});
    });
  } catch (error) {
    if (error.code === 'P2002') {
      throw toUniqueConflictError(error);
    }
    if (error.code === 'P2003') {
      // Foreign key constraint violation
      const target = error.meta?.field_name || 'field';
      throw new HttpError('errors.database.foreign_key_field', 400, [{ field: target }]);
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Update user
 *
 * @param {string} id - User ID
 * @param {Object} data - Update data
 * @param {Object} [options]
 * @param {boolean} [options.revokeSessions] - End every active session in the
 *   same transaction (used when an account stops being ACTIVE)
 * @returns {Promise<Object>} Updated user
 */
const update = async (id, data, { revokeSessions = false } = {}) => {
  try {
    const { permission_ids, profile, ...userData } = data || {};
    const shouldSyncPermissions = permission_ids !== undefined;
    const shouldSyncProfile = profile !== undefined;

    return await prisma.$transaction(async (tx) => {
      if (Object.keys(userData).length > 0) {
        await tx.user.update({
          where: { id },
          data: userData
        });
      } else {
        const existingUser = await tx.user.findFirst({
          where: {
            id,
            deleted_at: null}});

        if (!existingUser) {
          const notFoundError = new Error('User not found');
          notFoundError.code = 'P2025';
          throw notFoundError;
        }
      }

      if (shouldSyncProfile) {
        const existingProfile = await tx.user_profile.findFirst({
          where: { user_id: id, deleted_at: null },
          select: { id: true }
        });
        if (existingProfile) {
          await tx.user_profile.update({
            where: { id: existingProfile.id },
            data: {
              ...(profile.first_name !== undefined
                ? { first_name: profile.first_name }
                : {}),
              ...(profile.last_name !== undefined
                ? { last_name: profile.last_name }
                : {}),
              ...(userData.facility_id !== undefined
                ? { facility_id: userData.facility_id }
                : {})
            }
          });
        } else if (profile.first_name) {
          await tx.user_profile.create({
            data: {
              user_id: id,
              first_name: profile.first_name,
              last_name: profile.last_name ?? null,
              facility_id: userData.facility_id ?? null
            }
          });
        }
      }

      if (shouldSyncPermissions) {
        await syncUserPermissions(tx, id, permission_ids);
      }

      if (revokeSessions) {
        await tx.user_session.updateMany({
          where: {
            user_id: id,
            revoked_at: null,
            deleted_at: null},
          data: { revoked_at: new Date() }});
      }

      return await tx.user.findFirst({
        where: {
          id,
          deleted_at: null},
        include: resolveInclude()});
    });
  } catch (error) {
    if (error.code === 'P2025') {
      throw new HttpError('errors.user.not_found', 404);
    }
    if (error.code === 'P2002') {
      throw toUniqueConflictError(error);
    }
    if (error.code === 'P2003') {
      // Foreign key constraint violation
      const target = error.meta?.field_name || 'field';
      throw new HttpError('errors.database.foreign_key_field', 400, [{ field: target }]);
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Soft delete user
 * Per prisma.mdc: Only soft deletes allowed
 *
 * @param {string} id - User ID
 * @returns {Promise<Object>} Deleted user
 */
const softDelete = async (id) => {
  try {
    const deletedAt = new Date();

    return await prisma.$transaction(async (tx) => {
      const deletedUser = await tx.user.update({
        where: { id },
        data: {
          deleted_at: deletedAt
        }
      });

      await tx.user_permission.updateMany({
        where: {
          user_id: id,
          deleted_at: null},
        data: {
          deleted_at: deletedAt}});

      // A deleted account must not keep working through sessions it already holds.
      await tx.user_session.updateMany({
        where: {
          user_id: id,
          revoked_at: null,
          deleted_at: null},
        data: { revoked_at: deletedAt }});

      return deletedUser;
    });
  } catch (error) {
    if (error.code === 'P2025') {
      throw new HttpError('errors.user.not_found', 404);
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Restore a soft-deleted user and user_permissions soft-deleted with the same timestamp.
 * Also clears soft-delete on linked staff_profile rows (HR offboarding).
 *
 * @param {string} id - User ID
 * @returns {Promise<Object>} Restored user
 */
const restore = async (id) => {
  try {
    // Soft-deleted rows are invisible to tenant-guard find/update unless we
    // bypass (guard forces deleted_at: null on those operations).
    return await runWithoutTenantGuard(async () => {
      const existing = await prisma.user.findFirst({
        where: userWhereById(id, { includeDeleted: true }),
        select: {
          id: true,
          email: true,
          tenant_id: true,
          facility_id: true,
          deleted_at: true,
        },
      });

      // A purged account is deleted for good; nothing is left to restore.
      if (!existing || !existing.deleted_at || isPurgedAccount(existing)) {
        throw Object.assign(new Error('Record not found'), { code: 'P2025' });
      }

      const tenant = await prisma.tenant.findFirst({
        where: { id: existing.tenant_id, deleted_at: null },
        select: { id: true },
      });
      if (!tenant) {
        throw new HttpError('errors.user.restore_requires_active_tenant', 409);
      }

      if (existing.facility_id) {
        const facility = await prisma.facility.findFirst({
          where: { id: existing.facility_id, deleted_at: null },
          select: { id: true },
        });
        if (!facility) {
          throw new HttpError('errors.user.restore_requires_active_facility', 409);
        }
      }

      return await prisma.$transaction(async (tx) => {
        await tx.user_permission.updateMany({
          where: {
            user_id: id,
            deleted_at: existing.deleted_at,
          },
          data: {
            deleted_at: null,
          },
        });

        await tx.staff_profile.updateMany({
          where: {
            user_id: id,
            deleted_at: { not: null },
          },
          data: { deleted_at: null },
        });

        return await tx.user.update({
          where: { id },
          data: { deleted_at: null },
          include: resolveInclude(),
        });
      });
    });
  } catch (error) {
    if (error instanceof HttpError) throw error;
    if (error.code === 'P2025') {
      throw new HttpError('errors.user.not_found', 404);
    }
    throw new HttpError('errors.database.unexpected', 500, [
      { originalError: error.message },
    ]);
  }
};

/**
 * Tables whose rows exist only to give an account access. They are removed with it.
 */
const USER_OWNED_TABLES = Object.freeze(new Set([
  'user_profile',
  'staff_profile',
  'user_session',
  'verification_token',
  'user_role',
  'user_permission',
  'user_module_assignment',
  'user_mfa',
  'oauth_account',
  'registration_follow_up',
  'clinical_term_favorite'
]));

/**
 * References the database detaches on delete that carry no history: inbox rows,
 * analytics events, and the self-registration idempotency record.
 */
const USER_DETACHABLE_TABLES = Object.freeze(new Set([
  'notification',
  'analytics_event',
  'registration_attempt'
]));

/** Personal details stored against a user or staff profile. */
const PROFILE_OWNED_TABLES = Object.freeze(new Set(['address', 'contact']));

/**
 * Tables outside `ignoredTables` with rows pointing at `ids`. Foreign keys come
 * from the live schema, so a newly added relation is checked automatically.
 */
const findHistoryReferences = async (tx, table, ids, ignoredTables) => {
  if (ids.length === 0) {
    return [];
  }
  const history = [];
  for (const reference of await listForeignKeyReferences(tx, table)) {
    if (ignoredTables.has(reference.table)) {
      continue;
    }
    if ((await countReferencingRows(tx, reference, ids)) > 0) {
      history.push(reference.table);
    }
  }
  return history;
};

const deleteOwnedReferences = async (tx, table, ids, ownedTables) => {
  if (ids.length === 0) {
    return 0;
  }
  let removed = 0;
  for (const reference of await listForeignKeyReferences(tx, table)) {
    if (ownedTables.has(reference.table)) {
      removed += await deleteReferencingRows(tx, reference, ids);
    }
  }
  return removed;
};

/**
 * Permanently delete a soft-deleted user.
 *
 * Rows that exist only to give the account access go with it. With nothing else
 * pointing at the account, its row is deleted too. When audit, clinical, or
 * operational records still reference it, deleting the row would strip those
 * records of their author (most of those foreign keys are ON DELETE SET NULL,
 * the rest RESTRICT), so the row stays as that author and nothing more: email,
 * phone, and name are erased, the password can never match, and the account
 * never lists or restores again.
 *
 * @param {string} id - User ID
 * @param {Object} options
 * @param {string} options.unusablePasswordHash - Stored on a row that has to stay
 * @returns {Promise<{ removed_access_rows: number, anonymized: boolean, history_tables: string[] }>}
 */
const permanentDelete = async (id, { unusablePasswordHash } = {}) => {
  try {
    // Hard-delete must see soft-deleted rows; tenant-guard would otherwise force
    // deleted_at: null and the purge would 404.
    return await runWithoutTenantGuard(async () => {
      const existing = await prisma.user.findFirst({
        where: userWhereById(id, { includeDeleted: true }),
        select: { id: true, email: true, deleted_at: true }
      });

      if (!existing || isPurgedAccount(existing)) {
        throw Object.assign(new Error('Record not found'), { code: 'P2025' });
      }
      if (!existing.deleted_at) {
        throw new HttpError('errors.user.permanent_delete_not_soft_deleted', 400);
      }

      return await prisma.$transaction(async (tx) => {
        const profileIds = (
          await tx.user_profile.findMany({ where: { user_id: id }, select: { id: true } })
        ).map((row) => row.id);
        const staffProfileIds = (
          await tx.staff_profile.findMany({ where: { user_id: id }, select: { id: true } })
        ).map((row) => row.id);

        const userHistory = await findHistoryReferences(
          tx,
          'user',
          [id],
          new Set([...USER_OWNED_TABLES, ...USER_DETACHABLE_TABLES])
        );
        const profileHistory =
          await findHistoryReferences(tx, 'user_profile', profileIds, PROFILE_OWNED_TABLES);
        const staffProfileHistory =
          await findHistoryReferences(tx, 'staff_profile', staffProfileIds, PROFILE_OWNED_TABLES);

        // A profile that records point at stays; its personal details go below.
        const ownedTables = new Set(USER_OWNED_TABLES);
        if (profileHistory.length > 0) ownedTables.delete('user_profile');
        if (staffProfileHistory.length > 0) ownedTables.delete('staff_profile');

        // Profile details first: they point at the profiles removed after them.
        const removedAccessRows =
          (await deleteOwnedReferences(tx, 'user_profile', profileIds, PROFILE_OWNED_TABLES)) +
          (await deleteOwnedReferences(tx, 'staff_profile', staffProfileIds, PROFILE_OWNED_TABLES)) +
          (await deleteOwnedReferences(tx, 'user', [id], ownedTables));

        const historyTables = [
          ...new Set([...userHistory, ...profileHistory, ...staffProfileHistory])
        ].sort();

        if (historyTables.length === 0) {
          await tx.user.delete({ where: { id } });
          return { removed_access_rows: removedAccessRows, anonymized: false, history_tables: [] };
        }

        if (!unusablePasswordHash) {
          throw new Error('permanentDelete needs unusablePasswordHash to keep the account row');
        }
        if (profileHistory.length > 0) {
          await tx.user_profile.updateMany({
            where: { user_id: id },
            data: {
              first_name: PURGED_ACCOUNT_NAME,
              middle_name: null,
              last_name: null,
              gender: null,
              date_of_birth: null
            }
          });
        }
        await tx.user.update({
          where: { id },
          data: {
            email: purgedEmailFor(id),
            phone: null,
            password_hash: unusablePasswordHash,
            status: 'INACTIVE'
          }
        });
        return {
          removed_access_rows: removedAccessRows,
          anonymized: true,
          history_tables: historyTables
        };
      }, { timeout: 30000 });
    });
  } catch (error) {
    if (error instanceof HttpError) throw error;
    if (error.code === 'P2025') {
      throw new HttpError('errors.user.not_found', 404);
    }
    if (error.code === 'P2003') {
      // A restricting reference the schema scan did not cover.
      throw new HttpError('errors.user.permanent_delete_has_history', 409, [
        { field: 'id', reason: 'has_history' }
      ]);
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Replace an account's password. Its sessions end and any reset link already
 * emailed stops working, in the same transaction.
 *
 * @param {string} id - User ID
 * @param {string} passwordHash - Hash of the new password
 * @returns {Promise<void>}
 */
const setPassword = async (id, passwordHash) => {
  try {
    await prisma.$transaction(async (tx) => {
      const changedAt = new Date();
      await tx.user.update({
        where: { id },
        data: { password_hash: passwordHash }
      });
      await tx.user_session.updateMany({
        where: { user_id: id, revoked_at: null, deleted_at: null },
        data: { revoked_at: changedAt }
      });
      await tx.verification_token.updateMany({
        where: { user_id: id, type: 'PASSWORD_RESET', deleted_at: null },
        data: { deleted_at: changedAt }
      });
    });
  } catch (error) {
    if (error.code === 'P2025') {
      throw new HttpError('errors.user.not_found', 404);
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

module.exports = {
  findById,
  findMany,
  count,
  create,
  update,
  softDelete,
  restore,
  permanentDelete,
  setPassword,
  findActiveByTenantEmail,
  findActiveByTenantPhone,
  findDeletedByTenantEmail,
  findFacilityScope};
