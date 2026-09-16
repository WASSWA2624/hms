/**
 * Facility repository
 *
 * @module modules/facility/repositories
 * @description Data access layer for facility operations.
 * Per module-creation.mdc: Only standard CRUD operations allowed in repositories.
 * Per prisma.mdc: All queries use soft delete filtering (deleted_at: null).
 */

const prisma = require('@prisma/client');
const { HttpError } = require('@lib/errors');
const {
  softDeleteFacilityCascade,
} = require('@lib/facility-structure/cascade-soft-delete');
const { PRIMARY_TENANT_ADMIN_INCLUDE } = require('@lib/tenant/resolve-tenant-contact');

const normalizeFacilityName = (value) =>
  String(value || '')
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9\s]/g, '')
    .replace(/\s+/g, ' ');

const buildWhereClause = (filters = {}, { includeDeleted = false } = {}) => {
  const where = { ...filters };
  if (!includeDeleted) {
    where.deleted_at = null;
  }
  return where;
};

const listSchemaTablesWithColumn = async (tx, columnName, { excludeTables = [] } = {}) => {
  const rows = await tx.$queryRaw`
    SELECT DISTINCT TABLE_NAME AS table_name
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND COLUMN_NAME = ${columnName}
  `;

  const excluded = new Set(
    excludeTables.map((name) => String(name || '').trim().toLowerCase()).filter(Boolean)
  );

  return rows
    .map((row) => String(row.table_name || row.TABLE_NAME || '').replace(/`/g, '').trim())
    .filter((tableName) => tableName && !excluded.has(tableName.toLowerCase()));
};

/**
 * Find facility by ID
 *
 * @param {string} id - Facility ID
 * @param {Object} [includeOrOptions] - Relations to include, or options bag
 * @param {Object} [maybeOptions] - Options when first arg is include
 * @returns {Promise<Object|null>} Facility object or null
 */
const findById = async (id, includeOrOptions = {}, maybeOptions = {}) => {
  const looksLikeOptions =
    includeOrOptions &&
    typeof includeOrOptions === 'object' &&
    Object.prototype.hasOwnProperty.call(includeOrOptions, 'includeDeleted');

  const include = looksLikeOptions ? {} : includeOrOptions;
  const options = looksLikeOptions ? includeOrOptions : maybeOptions;
  const includeDeleted = options.includeDeleted === true;

  try {
    return await prisma.facility.findFirst({
      where: {
        id,
        ...(includeDeleted ? {} : { deleted_at: null })
      },
      include
    });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Find many facilities with pagination
 *
 * @param {Object} filters - Filter criteria
 * @param {number} skip - Number of records to skip
 * @param {number} take - Number of records to take
 * @param {Object} orderBy - Sort order
 * @param {Object} include - Relations to include
 * @param {Object} [options]
 * @param {boolean} [options.includeDeleted]
 * @returns {Promise<Array>} Array of facilities
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
    const where = buildWhereClause(filters, { includeDeleted });

    return await prisma.facility.findMany({
      where,
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
 * Tenants loaded with what `resolveTenantContact` reads, so facility rows can
 * inherit the tenant contact in one query per page. Soft-deleted tenants are
 * included so deleted facilities still resolve.
 *
 * @param {Array<string>} tenantIds - Tenant IDs
 * @returns {Promise<Array>} Tenants with their primary tenant admin role
 */
const findTenantContactSources = async (tenantIds = []) => {
  const ids = [...new Set((tenantIds || []).filter(Boolean).map(String))];
  if (ids.length === 0) {
    return [];
  }

  try {
    return await prisma.tenant.findMany({
      where: { id: { in: ids } },
      include: PRIMARY_TENANT_ADMIN_INCLUDE
    });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Find an active facility in a tenant with the same normalized name.
 *
 * @param {string} tenantId - Tenant ID
 * @param {string} name - Facility name
 * @param {string} [excludeFacilityId] - Facility ID to exclude (updates)
 * @returns {Promise<Object|null>} Matching facility or null
 */
const findByTenantAndName = async (tenantId, name, excludeFacilityId = null) => {
  try {
    const normalizedName = normalizeFacilityName(name);
    if (!normalizedName) {
      return null;
    }

    const facilities = await prisma.facility.findMany({
      where: {
        tenant_id: tenantId,
        deleted_at: null,
        ...(excludeFacilityId ? { NOT: { id: excludeFacilityId } } : {})
      },
      take: 100
    });

    return (
      facilities.find(
        (facility) => normalizeFacilityName(facility.name) === normalizedName
      ) || null
    );
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Count facilities with filters
 *
 * @param {Object} filters - Filter criteria
 * @param {Object} [options]
 * @param {boolean} [options.includeDeleted]
 * @returns {Promise<number>} Count of facilities
 */
const count = async (filters = {}, { includeDeleted = false } = {}) => {
  try {
    const where = buildWhereClause(filters, { includeDeleted });

    return await prisma.facility.count({ where });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Create new facility
 *
 * @param {Object} data - Facility data
 * @returns {Promise<Object>} Created facility
 */
const create = async (data) => {
  try {
    return await prisma.facility.create({
      data
    });
  } catch (error) {
    if (error.code === 'P2002') {
      const target = error.meta?.target?.[0] || 'field';
      throw new HttpError('errors.database.unique_field', 409, [{ field: target }]);
    }
    if (error.code === 'P2003') {
      const field = error.meta?.field_name || 'reference';
      throw new HttpError('errors.database.foreign_key_field', 400, [{ field }]);
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Update facility
 *
 * @param {string} id - Facility ID
 * @param {Object} data - Update data
 * @returns {Promise<Object>} Updated facility
 */
const update = async (id, data) => {
  try {
    return await prisma.facility.update({
      where: { id },
      data
    });
  } catch (error) {
    if (error.code === 'P2025') {
      throw new HttpError('errors.facility.not_found', 404);
    }
    if (error.code === 'P2002') {
      const target = error.meta?.target?.[0] || 'field';
      throw new HttpError('errors.database.unique_field', 409, [{ field: target }]);
    }
    if (error.code === 'P2003') {
      const field = error.meta?.field_name || 'reference';
      throw new HttpError('errors.database.foreign_key_field', 400, [{ field }]);
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Soft delete facility and cascade to departments, units, wards, rooms, beds.
 *
 * @param {string} id - Facility ID
 * @returns {Promise<Object>} Deleted facility
 */
const softDelete = async (id) => {
  try {
    const result = await softDeleteFacilityCascade(id);
    return result.facility;
  } catch (error) {
    if (error instanceof HttpError) {
      throw error;
    }
    if (error.code === 'P2025') {
      throw new HttpError('errors.facility.not_found', 404);
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Restore a soft-deleted facility.
 *
 * @param {string} id - Facility ID
 * @returns {Promise<Object>} Restored facility
 */
const restore = async (id) => {
  try {
    const existing = await prisma.facility.findUnique({
      where: { id },
      select: {
        id: true,
        tenant_id: true,
        deleted_at: true
      }
    });

    if (!existing || !existing.deleted_at) {
      throw Object.assign(new Error('Record not found'), { code: 'P2025' });
    }

    const tenant = await prisma.tenant.findUnique({
      where: { id: existing.tenant_id },
      select: { id: true, deleted_at: true }
    });

    if (!tenant || tenant.deleted_at) {
      throw new HttpError('errors.facility.restore_requires_active_tenant', 409);
    }

    return await prisma.facility.update({
      where: { id },
      data: { deleted_at: null }
    });
  } catch (error) {
    if (error instanceof HttpError) {
      throw error;
    }
    if (error.code === 'P2025') {
      throw new HttpError('errors.facility.not_found', 404);
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Permanently delete a soft-deleted facility and all facility-scoped data.
 *
 * @param {string} id - Facility ID
 * @returns {Promise<void>}
 */
const permanentDelete = async (id) => {
  try {
    const existing = await prisma.facility.findUnique({
      where: { id },
      select: {
        id: true,
        deleted_at: true
      }
    });

    if (!existing) {
      return;
    }
    if (!existing.deleted_at) {
      throw new HttpError('errors.facility.permanent_delete_requires_soft_delete', 400);
    }

    await prisma.$transaction(async (tx) => {
      await tx.$executeRawUnsafe('SET FOREIGN_KEY_CHECKS = 0');
      try {
        const facilityTables = await listSchemaTablesWithColumn(tx, 'facility_id', {
          excludeTables: ['facility']
        });

        for (const tableName of facilityTables) {
          await tx.$executeRawUnsafe(
            `DELETE FROM \`${tableName}\` WHERE facility_id = ?`,
            id
          );
        }

        await tx.facility.delete({ where: { id } });
      } finally {
        await tx.$executeRawUnsafe('SET FOREIGN_KEY_CHECKS = 1');
      }
    }, { timeout: 120000 });
  } catch (error) {
    if (error instanceof HttpError) {
      throw error;
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

module.exports = {
  findById,
  findMany,
  findTenantContactSources,
  findByTenantAndName,
  count,
  create,
  update,
  softDelete,
  restore,
  permanentDelete,
  normalizeFacilityName
};
