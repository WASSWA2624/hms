/**
 * User controller
 *
 * @module modules/user/controllers
 * @description Request handlers for user endpoints.
 * Per module-creation.mdc: All methods wrapped with asyncHandler.
 * Per response-format.mdc: Use standardized response helpers.
 */

const userService = require('@services/user/user.service');
const { asyncHandler } = require('@lib/async');
const { sendSuccess, sendPaginated, sendNoContent } = require('@lib/response');
const { DEFAULT_PAGE, DEFAULT_PAGE_LIMIT } = require('@config/constants');

/**
 * List users with pagination
 * GET /api/v1/users
 *
 * @param {Object} req - Express request
 * @param {Object} res - Express response
 */
const listUsers = asyncHandler(async (req, res) => {
  const {
    tenant_id,
    facility_id,
    position_title,
    email,
    status,
    search,
    include_deleted,
    page = DEFAULT_PAGE,
    limit = DEFAULT_PAGE_LIMIT,
    sort_by,
    order = 'asc'
  } = req.query;

  const filters = {
    tenant_id,
    facility_id,
    position_title,
    email,
    status,
    search};
  if (include_deleted) filters.include_deleted = include_deleted;

  const userId = req.user?.id;
  const ipAddress = req.ip;

  const result = await userService.listUsers(
    filters,
    parseInt(page),
    parseInt(limit),
    sort_by,
    order,
    userId,
    ipAddress
  );

  sendPaginated(res, 'messages.user.list.success', result.users, result.pagination);
});

/**
 * Get user by ID
 * GET /api/v1/users/:id
 *
 * @param {Object} req - Express request
 * @param {Object} res - Express response
 */
const getUserById = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const userId = req.user?.id;
  const ipAddress = req.ip;

  const user = await userService.getUserById(id, userId, ipAddress);

  sendSuccess(res, 200, 'messages.user.get.success', user);
});

/**
 * Create new user
 * POST /api/v1/users
 *
 * @param {Object} req - Express request
 * @param {Object} res - Express response
 */
const createUser = asyncHandler(async (req, res) => {
  const userId = req.user?.id;
  const ipAddress = req.ip;

  const user = await userService.createUser(req.body, userId, ipAddress, req.user);

  sendSuccess(res, 201, 'messages.user.create.success', user);
});

/**
 * Update user
 * PUT /api/v1/users/:id
 *
 * @param {Object} req - Express request
 * @param {Object} res - Express response
 */
const updateUser = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const userId = req.user?.id;
  const ipAddress = req.ip;

  const user = await userService.updateUser(
    id,
    req.body,
    userId,
    ipAddress,
    req.user
  );

  sendSuccess(res, 200, 'messages.user.update.success', user);
});

/**
 * Delete user (soft delete)
 * DELETE /api/v1/users/:id
 *
 * @param {Object} req - Express request
 * @param {Object} res - Express response
 */
const deleteUser = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const userId = req.user?.id;
  const ipAddress = req.ip;

  await userService.deleteUser(id, userId, ipAddress, req.user);

  sendNoContent(res);
});

/**
 * Restore user
 * POST /api/v1/users/:id/restore
 */
const restoreUser = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const userId = req.user?.id;
  const ipAddress = req.ip;

  const user = await userService.restoreUser(id, userId, ipAddress, req.user);

  sendSuccess(res, 200, 'messages.user.restore.success', user);
});

/**
 * Permanently delete soft-deleted user
 * DELETE /api/v1/users/:id/permanent
 */
const permanentDeleteUser = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const userId = req.user?.id;
  const ipAddress = req.ip;

  await userService.permanentDeleteUser(id, userId, ipAddress, req.user);

  sendNoContent(res);
});

const readHeader = (req, name) =>
  typeof req.get === 'function' ? req.get(name) || null : null;

/**
 * Issue a single-use credential reset for a user
 * POST /api/v1/users/:id/reset-credentials
 *
 * @param {Object} req - Express request
 * @param {Object} res - Express response
 */
const resetUserCredentials = asyncHandler(async (req, res) => {
  const { id } = req.params;

  const result = await userService.resetUserCredentials(id, req.user, {
    ipAddress: req.ip,
    requestContext: {
      locale: req.locale || readHeader(req, 'x-locale') || readHeader(req, 'accept-language'),
      timezone: readHeader(req, 'x-timezone'),
      origin: readHeader(req, 'origin')}});

  sendSuccess(res, 200, 'messages.user.reset_credentials.success', result);
});

/**
 * Set a user's password directly, without emailing a reset link
 * PUT /api/v1/users/:id/password
 *
 * @param {Object} req - Express request
 * @param {Object} res - Express response
 */
const setUserPassword = asyncHandler(async (req, res) => {
  const { id } = req.params;

  const result = await userService.setUserPassword(id, req.body.password, req.user, {
    ipAddress: req.ip});

  sendSuccess(res, 200, 'messages.user.password_set.success', result);
});

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
