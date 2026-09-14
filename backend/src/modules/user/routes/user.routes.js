/**
 * User routes
 *
 * @module modules/user/routes
 * @description User endpoints mounted at /api/v1/users
 * Per module-creation.mdc: Apply all required middlewares
 * Per api.mdc: All endpoints must follow REST conventions
 */

const express = require('express');
const router = express.Router();
const userController = require('@controllers/user/user.controller');
const { validateRequest } = require('@middlewares/validate.middleware');
const { authenticate, authorize } = require('@middlewares/auth.middleware');
const { restoreRequestedScope } = require('@middlewares/tenant-scope.middleware');
const { PERMISSIONS } = require('@config/permissions');
const {
  createUserSchema,
  updateUserSchema,
  setUserPasswordSchema,
  userIdParamsSchema,
  listUsersQuerySchema
} = require('@validations/user/user.schema');

const USER_READ_SCOPES = [
  PERMISSIONS.HR_READ,
  PERMISSIONS.TENANT_ADMIN,
  PERMISSIONS.FACILITY_ADMIN,
  PERMISSIONS.PLATFORM_ADMIN,
  PERMISSIONS.PLATFORM_OWNER,
];
const USER_WRITE_SCOPES = [
  PERMISSIONS.HR_WRITE,
  PERMISSIONS.TENANT_ADMIN,
  PERMISSIONS.FACILITY_ADMIN,
  PERMISSIONS.PLATFORM_ADMIN,
  PERMISSIONS.PLATFORM_OWNER,
];

// The user service validates the requested facility against the actor's scope,
// so undo the global rewrite that would otherwise move the account into the
// actor's own facility.
const preserveRequestedFacility = restoreRequestedScope(['facility_id']);

/**
 * @description List users with pagination and filters
 * @method GET
 * @route /api/v1/users/
 * @authentication Required (JWT)
 * @permissions Authenticated users
 * @urlParams None
 * @queryParams {number} [page=1] - Page number
 * @queryParams {number} [limit=20] - Items per page
 * @queryParams {string} [sort_by=created_at] - Field to sort by
 * @queryParams {string} [order=desc] - Sort order (asc/desc)
 * @queryParams {string} [tenant_id] - Filter by tenant ID (UUID)
 * @queryParams {string} [facility_id] - Filter by facility ID (UUID)
 * @queryParams {string} [email] - Filter by email (partial match)
 * @queryParams {string} [status] - Filter by status (ACTIVE, INACTIVE, SUSPENDED, PENDING)
 * @queryParams {string} [search] - Search in email and phone fields
 * @bodyParams None
 * @returns {Object} Paginated list of users
 * @throws 401 Unauthorized
 */
router.get(
  '/',
  validateRequest({ query: listUsersQuerySchema }),
  authenticate(),
  authorize(USER_READ_SCOPES, 'permission'),
  userController.listUsers
);
router.post(
  '/:id/restore',
  validateRequest({ params: userIdParamsSchema }),
  authenticate(),
  authorize(USER_WRITE_SCOPES, 'permission'),
  userController.restoreUser
);

/**
 * @description Permanently delete a soft-deleted user
 * @method DELETE
 * @route /api/v1/users/:id/permanent
 * @authentication Required (JWT)
 * @permissions hr:write, tenant:admin, facility:admin, platform:admin, platform:owner
 * @urlParams {string} id - User ID (UUID or friendly ID)
 * @queryParams None
 * @bodyParams None
 * @returns {void} 204 No Content. A user that records still reference keeps an anonymized row as their author.
 * @throws 400 User is not soft-deleted
 * @throws 401 Unauthorized
 * @throws 403 Demo, out-of-scope, or protected platform account
 * @throws 404 User not found or already purged
 * @throws 409 A reference the schema scan could not detach
 */
router.delete(
  '/:id/permanent',
  validateRequest({ params: userIdParamsSchema }),
  authenticate(),
  authorize(USER_WRITE_SCOPES, 'permission'),
  userController.permanentDeleteUser
);

/**
 * @description Issue a single-use password reset link to a user
 * @method POST
 * @route /api/v1/users/:id/reset-credentials
 * @authentication Required (JWT)
 * @permissions hr:write, tenant:admin, facility:admin, platform:admin, platform:owner
 * @urlParams {string} id - User ID (UUID or friendly ID)
 * @queryParams None
 * @bodyParams None
 * @returns {Object} Masked email, delivery status (SENT, PENDING, FAILED) and link expiry; never a password, token, or code
 * @throws 400 User has no email address
 * @throws 401 Unauthorized
 * @throws 403 Demo, out-of-scope, or protected platform account
 * @throws 404 User not found
 */
router.post(
  '/:id/reset-credentials',
  validateRequest({ params: userIdParamsSchema }),
  authenticate(),
  authorize(USER_WRITE_SCOPES, 'permission'),
  userController.resetUserCredentials
);

/**
 * @description Set a user's password directly, without emailing a reset link
 * @method PUT
 * @route /api/v1/users/:id/password
 * @authentication Required (JWT)
 * @permissions hr:write, tenant:admin, facility:admin, platform:admin, platform:owner
 * @urlParams {string} id - User ID (UUID or friendly ID)
 * @queryParams None
 * @bodyParams {string} password - New password; must meet the password policy
 * @returns {Object} User identifier and sessions_revoked; never the password or its hash
 * @throws 400 Password fails the policy, or the target is the caller's own account
 * @throws 401 Unauthorized
 * @throws 403 Demo, out-of-scope, or protected platform account
 * @throws 404 User not found
 */
router.put(
  '/:id/password',
  validateRequest({ params: userIdParamsSchema, body: setUserPasswordSchema }),
  authenticate(),
  authorize(USER_WRITE_SCOPES, 'permission'),
  userController.setUserPassword
);


/**
 * @description Get user by ID
 * @method GET
 * @route /api/v1/users/:id
 * @authentication Required (JWT)
 * @permissions Authenticated users
 * @urlParams {string} id - User ID (UUID)
 * @queryParams None
 * @bodyParams None
 * @returns {Object} User data
 * @throws 401 Unauthorized
 * @throws 404 User not found
 */
router.get(
  '/:id',
  validateRequest({ params: userIdParamsSchema }),
  authenticate(),
  authorize(USER_READ_SCOPES, 'permission'),
  userController.getUserById
);

/**
 * @description Create new user
 * @method POST
 * @route /api/v1/users/
 * @authentication Required (JWT)
 * @permissions Authenticated users
 * @urlParams None
 * @queryParams None
 * @bodyParams {string} tenant_id - Tenant ID (required, UUID)
 * @bodyParams {string} [facility_id] - Facility ID (UUID)
 * @bodyParams {string} email - User email (required, valid email format, max 255 chars)
 * @bodyParams {string} [phone] - User phone (max 40 chars)
 * @bodyParams {string} password - Initial password (required; min 8 with upper, lower, number, symbol)
 * @bodyParams {string} status - User status (required, ACTIVE/INACTIVE/SUSPENDED/PENDING)
 * @bodyParams {string[]} [permission_ids] - Direct permission IDs to assign to the user
 * @bodyParams {string[]} [role_ids] - Roles assigned in the same transaction as the user
 * @bodyParams {Object} [staff_profile] - Create a linked staff profile in the same transaction
 * @returns {Object} Created user (never includes password_hash)
 * @throws 401 Unauthorized
 * @throws 400 Validation error (field-level)
 * @throws 403 Tenant or facility outside the actor's scope, or role above the actor's ceiling
 * @throws 409 Duplicate email/phone in tenant, email held by a deleted user, or similar user awaiting confirmation
 */
router.post(
  '/',
  preserveRequestedFacility,
  validateRequest({ body: createUserSchema }),
  authenticate(),
  authorize(USER_WRITE_SCOPES, 'permission'),
  userController.createUser
);

/**
 * @description Update user
 * @method PUT
 * @route /api/v1/users/:id
 * @authentication Required (JWT)
 * @permissions Authenticated users
 * @urlParams {string} id - User ID (UUID)
 * @queryParams None
 * @bodyParams {string} [facility_id] - Facility ID (UUID)
 * @bodyParams {string} [email] - User email (valid email format, max 255 chars)
 * @bodyParams {string} [phone] - User phone (max 40 chars)
 * @bodyParams {string} [status] - User status (ACTIVE/INACTIVE/SUSPENDED/PENDING); leaving ACTIVE revokes sessions
 * @bodyParams {string[]} [permission_ids] - Direct permission IDs to assign to the user
 * @returns {Object} Updated user (never includes password_hash)
 * @throws 401 Unauthorized
 * @throws 400 Validation error, password supplied (use reset-credentials), or self-deactivation
 * @throws 404 User not found
 * @throws 409 Unique constraint violation
 */
router.put(
  '/:id',
  preserveRequestedFacility,
  validateRequest({ params: userIdParamsSchema, body: updateUserSchema }),
  authenticate(),
  authorize(USER_WRITE_SCOPES, 'permission'),
  userController.updateUser
);

/**
 * @description Delete user (soft delete)
 * @method DELETE
 * @route /api/v1/users/:id
 * @authentication Required (JWT)
 * @permissions Authenticated users
 * @urlParams {string} id - User ID (UUID)
 * @queryParams None
 * @bodyParams None
 * @returns {void} 204 No Content
 * @throws 401 Unauthorized
 * @throws 404 User not found
 */
router.delete(
  '/:id',
  validateRequest({ params: userIdParamsSchema }),
  authenticate(),
  authorize(USER_WRITE_SCOPES, 'permission'),
  userController.deleteUser
);

module.exports = router;
