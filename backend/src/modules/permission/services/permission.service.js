/**
 * Permission service
 *
 * @module modules/permission/services
 * @description Business logic layer for permission operations.
 * Per module-creation.mdc: Services only import/use their own repository.
 * Per prisma.mdc: All mutations call createAuditLog.
 */

const permissionRepository = require('@repositories/permission/permission.repository');
const { createAuditLog } = require('@lib/audit');
const { HttpError } = require('@lib/errors');
const {
  assertPermissionNotSystemProtected,
  isCatalogProtectedPermissionName,
  canActorCreatePlatformRole,
} = require('@lib/authorization/assignable-access');
const {
  findActivePlatformPermissionByName,
} = require('@lib/authorization/platform-access-catalog');

/**
 * List permissions with pagination and filtering
 *
 * @param {Object} filters - Query filters
 * @param {number} page - Page number
 * @param {number} limit - Items per page
 * @param {string} sortBy - Sort field
 * @param {string} order - Sort order
 * @param {string} userId - User ID for audit
 * @param {string} ipAddress - User IP for audit
 * @returns {Promise<Object>} Permissions and pagination data
 */
const listPermissions = async (filters, page, limit, sortBy, order, userId, ipAddress) => {
  try {
    const skip = (page - 1) * limit;
    const orderBy = sortBy ? { [sortBy]: order } : { created_at: 'desc' };

    // Build filter object
    const whereClause = {};
    
    if (filters.tenant_id) whereClause.tenant_id = filters.tenant_id;
    if (filters.name) whereClause.name = { contains: filters.name };
    
    // Search filter (searches in name and description)
    if (filters.search) {
      whereClause.OR = [
        { name: { contains: filters.search } },
        { description: { contains: filters.search } }
      ];
    }

    const [permissions, total] = await Promise.all([
      permissionRepository.findMany(whereClause, skip, limit, orderBy),
      permissionRepository.count(whereClause)
    ]);

    return {
      permissions,
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
 * Get permission by ID
 *
 * @param {string} id - Permission ID
 * @param {string} userId - User ID for audit
 * @param {string} ipAddress - User IP for audit
 * @returns {Promise<Object>} Permission data
 */
const getPermissionById = async (id, userId, ipAddress) => {
  try {
    const permission = await permissionRepository.findById(id);

    if (!permission) {
      throw new HttpError('errors.permission.not_found', 404);
    }

    return permission;
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Create new permission
 * Per prisma.mdc: Mutations must create audit logs
 *
 * @param {Object} data - Permission data
 * @param {string} userId - User ID for audit
 * @param {string} ipAddress - User IP for audit
 * @returns {Promise<Object>} Created permission
 */
const createPermission = async (data, userId, ipAddress, actor = null) => {
  try {
    const actorUser = actor || { id: userId };
    const permissionName = String(data?.name || '').trim();
    if (isCatalogProtectedPermissionName(permissionName)) {
      if (!canActorCreatePlatformRole(actorUser)) {
        throw new HttpError('errors.auth.insufficient_permissions', 403, [
          { field: 'name', reason: 'system_permission_protected' },
        ]);
      }
      // Platform catalog permissions are seeded once — never create duplicates.
      throw new HttpError('errors.permission.duplicate', 409, [
        { field: 'name', reason: 'platform_catalog_exists' },
      ]);
    }

    // Organizations use platform permissions; a same-name copy is a duplicate.
    if (await findActivePlatformPermissionByName(permissionName)) {
      throw new HttpError('errors.permission.duplicate', 409, [
        { field: 'name', reason: 'platform_catalog_exists' },
      ]);
    }

    const permission = await permissionRepository.create(data);

    // Create audit log (non-blocking)
    createAuditLog({
      user_id: userId,
      action: 'CREATE',
      entity: 'permission',
      entity_id: permission.id,
      diff: { after: permission },
      ip_address: ipAddress
    }).catch(() => {});

    return permission;
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Update permission
 * Per prisma.mdc: Mutations must create audit logs
 *
 * @param {string} id - Permission ID
 * @param {Object} data - Update data
 * @param {string} userId - User ID for audit
 * @param {string} ipAddress - User IP for audit
 * @returns {Promise<Object>} Updated permission
 */
const updatePermission = async (id, data, userId, ipAddress, actor = null) => {
  try {
    // Get current state for audit
    const before = await permissionRepository.findById(id);

    if (!before) {
      throw new HttpError('errors.permission.not_found', 404);
    }

    assertPermissionNotSystemProtected(
      before,
      'update',
      actor || { id: userId }
    );

    const nextName = String(data?.name || '').trim();
    if (nextName && nextName !== before.name) {
      const platformPermission = await findActivePlatformPermissionByName(nextName);
      if (platformPermission && platformPermission.id !== before.id) {
        throw new HttpError('errors.permission.duplicate', 409, [
          { field: 'name', reason: 'platform_catalog_exists' },
        ]);
      }
    }

    const permission = await permissionRepository.update(id, data);

    // Create audit log (non-blocking)
    createAuditLog({
      user_id: userId,
      action: 'UPDATE',
      entity: 'permission',
      entity_id: permission.id,
      diff: { before, after: permission },
      ip_address: ipAddress
    }).catch(() => {});

    return permission;
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Delete permission (soft delete)
 * Per prisma.mdc: Mutations must create audit logs
 *
 * @param {string} id - Permission ID
 * @param {string} userId - User ID for audit
 * @param {string} ipAddress - User IP for audit
 * @returns {Promise<void>}
 */
const deletePermission = async (id, userId, ipAddress, actor = null) => {
  try {
    // Get current state for audit
    const before = await permissionRepository.findById(id);

    if (!before) {
      throw new HttpError('errors.permission.not_found', 404);
    }

    assertPermissionNotSystemProtected(before, 'delete', actor || { id: userId });

    await permissionRepository.softDelete(id);

    // Create audit log (non-blocking)
    createAuditLog({
      user_id: userId,
      action: 'DELETE',
      entity: 'permission',
      entity_id: id,
      diff: { before },
      ip_address: ipAddress
    }).catch(() => {});
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

module.exports = {
  listPermissions,
  getPermissionById,
  createPermission,
  updatePermission,
  deletePermission
};
