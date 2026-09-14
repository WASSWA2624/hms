/**
 * Feedback administration access
 *
 * @module lib/feedback
 * @description Downloading and clearing feedback exposes submissions from every
 * tenant, anonymous ones included, so both stay with the platform's operators:
 * `PLATFORM_OWNER` (owner admin) and `PLATFORM_ADMIN` (platform admin). Every
 * other role, signed in or not, can submit feedback but cannot manage it.
 */

const { ROLES, normalizeRoleName } = require('@config/roles');

const FEEDBACK_ADMIN_ROLES = Object.freeze([ROLES.PLATFORM_OWNER, ROLES.PLATFORM_ADMIN]);

const collectRoleNames = (user = {}) => {
  const rawRoles = Array.isArray(user?.roles) ? user.roles : user?.role ? [user.role] : [];
  return rawRoles
    .map((role) => normalizeRoleName(role) || String(role || '').trim().toUpperCase())
    .filter(Boolean);
};

/**
 * @param {Object|null|undefined} user - Request user context
 * @returns {boolean} Whether the user may download or clear feedback
 */
const hasFeedbackAdminRole = (user) =>
  collectRoleNames(user || {}).some((role) => FEEDBACK_ADMIN_ROLES.includes(role));

module.exports = {
  FEEDBACK_ADMIN_ROLES,
  hasFeedbackAdminRole
};
