/**
 * User-Role repository
 *
 * @module modules/user-role/repositories
 * @description Data access layer for user-role operations.
 * Per module-creation.mdc: Only standard CRUD operations allowed in repositories.
 * Per prisma.mdc: All queries use soft delete filtering (deleted_at: null).
 */

const prisma = require('@prisma/client');
const { HttpError } = require('@lib/errors');

const userRoleRelations = {
  user: {
    select: {
      id: true,
      human_friendly_id: true,
      email: true}},
  role: {
    select: {
      id: true,
      human_friendly_id: true,
      name: true}},
  tenant: {
    select: {
      id: true,
      human_friendly_id: true,
      name: true,
      slug: true}}};

const facilitySelect = {
  id: true,
  human_friendly_id: true,
  name: true};

const attachFacility = async (userRole) => {
  if (!userRole) return null;
  if (!userRole.facility_id) {
    return {
      ...userRole,
      facility: null};
  }

  const facility = await prisma.facility.findFirst({
    where: {
      id: userRole.facility_id,
      deleted_at: null},
    select: facilitySelect});

  return {
    ...userRole,
    facility};
};

const attachFacilities = async (userRoles) => {
  if (!Array.isArray(userRoles) || userRoles.length === 0) return [];

  const facilityIds = Array.from(
    new Set(
      userRoles
        .map((userRole) => userRole?.facility_id)
        .filter(Boolean)
    )
  );

  if (facilityIds.length === 0) {
    return userRoles.map((userRole) => ({
      ...userRole,
      facility: null}));
  }

  const facilities = await prisma.facility.findMany({
    where: {
      id: { in: facilityIds },
      deleted_at: null},
    select: facilitySelect});

  const facilitiesById = new Map(facilities.map((facility) => [facility.id, facility]));

  return userRoles.map((userRole) => ({
    ...userRole,
    facility: userRole.facility_id ? facilitiesById.get(userRole.facility_id) || null : null}));
};

/**
 * Find user-role by ID
 *
 * @param {string} id - User-Role ID
 * @returns {Promise<Object|null>} User-Role object or null
 */
const findById = async (id) => {
  try {
    const userRole = await prisma.user_role.findFirst({
      where: {
        id,
        deleted_at: null
      },
      include: userRoleRelations});

    return attachFacility(userRole);
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Find many user-roles with pagination
 *
 * @param {Object} filters - Filter criteria
 * @param {number} skip - Number of records to skip
 * @param {number} take - Number of records to take
 * @param {Object} orderBy - Sort order
 * @returns {Promise<Array>} Array of user-roles
 */
const findMany = async (filters = {}, skip = 0, take = 20, orderBy = { created_at: 'desc' }) => {
  try {
    // Build where clause
    const where = {
      deleted_at: null,
      ...filters
    };

    const userRoles = await prisma.user_role.findMany({
      where,
      skip,
      take,
      orderBy,
      include: userRoleRelations});

    return attachFacilities(userRoles);
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Count user-roles with filters
 *
 * @param {Object} filters - Filter criteria
 * @returns {Promise<number>} Count of user-roles
 */
const count = async (filters = {}) => {
  try {
    const where = {
      deleted_at: null,
      ...filters
    };

    return await prisma.user_role.count({ where });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Create new user-role.
 * Soft-deleted rows still occupy the unique key, so re-assign restores them.
 * Active duplicates are returned as-is (idempotent assign).
 *
 * @param {Object} data - User-Role data
 * @returns {Promise<Object>} Created user-role
 */
const create = async (data) => {
  // The tenant guard adds `deleted_at: null` to any lookup that doesn't name
  // deleted_at, which hides the soft-deleted row this has to restore.
  const matchWhere = {
    user_id: data.user_id,
    role_id: data.role_id,
    tenant_id: data.tenant_id,
    facility_id: data.facility_id ?? null,
    OR: [{ deleted_at: null }, { deleted_at: { not: null } }]};

  const restoreOrReturnExisting = async () => {
    const existing = await prisma.user_role.findFirst({
      where: matchWhere,
      orderBy: [{ deleted_at: 'asc' }, { updated_at: 'desc' }]});
    if (!existing) {
      return null;
    }
    if (existing.deleted_at == null) {
      return findById(existing.id);
    }
    await prisma.user_role.update({
      where: { id: existing.id, deleted_at: { not: null } },
      data: {
        deleted_at: null,
        version: { increment: 1 }}});
    return findById(existing.id);
  };

  try {
    const existing = await restoreOrReturnExisting();
    if (existing) {
      return existing;
    }

    const userRole = await prisma.user_role.create({
      data});

    return findById(userRole.id);
  } catch (error) {
    if (error.code === 'P2002') {
      // Concurrent create/restore race — resolve to the surviving row.
      const recovered = await restoreOrReturnExisting();
      if (recovered) {
        return recovered;
      }
      const target = error.meta?.target?.[0] || 'field';
      throw new HttpError('errors.database.unique_field', 409, [{ field: target }]);
    }
    if (error instanceof HttpError) throw error;
    if (error.code === 'P2003') {
      // Foreign key constraint violation
      const target = error.meta?.field_name || 'field';
      throw new HttpError('errors.database.foreign_key_field', 400, [{ field: target }]);
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Update user-role
 *
 * @param {string} id - User-Role ID
 * @param {Object} data - Update data
 * @returns {Promise<Object>} Updated user-role
 */
const update = async (id, data) => {
  try {
    const userRole = await prisma.user_role.update({
      where: { id },
      data
    });

    return findById(userRole.id);
  } catch (error) {
    if (error.code === 'P2025') {
      throw new HttpError('errors.user_role.not_found', 404);
    }
    if (error.code === 'P2002') {
      // Unique constraint violation
      const target = error.meta?.target?.[0] || 'field';
      throw new HttpError('errors.database.unique_field', 409, [{ field: target }]);
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
 * Soft delete user-role
 * Per prisma.mdc: Only soft deletes allowed
 *
 * @param {string} id - User-Role ID
 * @returns {Promise<Object>} Deleted user-role
 */
const softDelete = async (id) => {
  try {
    return await prisma.user_role.update({
      where: { id },
      data: {
        deleted_at: new Date()
      }
    });
  } catch (error) {
    if (error.code === 'P2025') {
      throw new HttpError('errors.user_role.not_found', 404);
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Resolve the tenant and facility an account belongs to.
 *
 * @param {string} userId - User ID
 * @returns {Promise<{id: string, tenant_id: string, facility_id: (string|null)}|null>}
 */
const findUserScope = async (userId) => {
  try {
    return await prisma.user.findFirst({
      where: { id: userId, deleted_at: null },
      select: { id: true, tenant_id: true, facility_id: true }});
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Resolve the tenant and facility a role is limited to.
 *
 * @param {string} roleId - Role ID
 * @returns {Promise<{id: string, tenant_id: (string|null), facility_id: (string|null)}|null>}
 */
const findRoleScope = async (roleId) => {
  try {
    return await prisma.role.findFirst({
      where: { id: roleId, deleted_at: null },
      select: { id: true, tenant_id: true, facility_id: true }});
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
  try {
    return await prisma.facility.findFirst({
      where: { id: facilityId, deleted_at: null },
      select: { id: true, tenant_id: true }});
  } catch (error) {
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
  findUserScope,
  findRoleScope,
  findFacilityScope
};
