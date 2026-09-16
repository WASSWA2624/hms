/**
 * Application feedback routes
 *
 * Mounted ahead of the global authentication chain in `src/app/router.js`:
 * "Give us feedback" must work on sign-in screens and after a session lapses,
 * so every route here declares its own authentication. Listing, download, and
 * deletion stay with platform owners and platform admins, enforced here and in
 * the service.
 */

const express = require('express');
const router = express.Router();
const feedbackController = require('@controllers/feedback/feedback.controller');
const rateLimitConfig = require('@config/rateLimit');
const { rateLimit } = require('@middlewares/rateLimit.middleware');
const {
  authenticate,
  authenticateOptional,
  authorize
} = require('@middlewares/auth.middleware');
const { hydrateLiveAccess } = require('@middlewares/live-access.middleware');
const { validateRequest } = require('@middlewares/validate.middleware');
const { FEEDBACK_ADMIN_ROLES } = require('@lib/feedback/feedback-access');
const {
  deleteFeedbackSchema,
  exportFeedbackBodySchema,
  exportFeedbackQuerySchema,
  feedbackFilterQuerySchema,
  listFeedbackQuerySchema,
  submitFeedbackSchema
} = require('@validations/feedback/feedback.schema');

// Live roles, not token claims: a revoked admin loses access immediately.
const requireFeedbackAdmin = () => [
  authenticate(),
  hydrateLiveAccess(),
  authorize(FEEDBACK_ADMIN_ROLES)
];

/**
 * @description Submit application feedback from any screen
 * @method POST
 * @route /api/v1/feedback
 * @authentication Optional (anonymous when no valid bearer token)
 * @permissions Public
 * @urlParams None
 * @queryParams None
 * @bodyParams category, message, context
 * @returns {Object} Receipt with human_friendly_id, category, submitter_type, submitted_at
 * @throws 400 Validation error
 * @throws 429 Rate limit exceeded
 */
router.post(
  '/',
  rateLimit(rateLimitConfig.endpoints.feedback),
  authenticateOptional(),
  validateRequest({ body: submitFeedbackSchema }),
  feedbackController.submitFeedback
);

/**
 * @description List stored feedback for review and deletion, newest first
 * @method GET
 * @route /api/v1/feedback
 * @authentication Required
 * @permissions PLATFORM_OWNER, PLATFORM_ADMIN
 * @urlParams None
 * @queryParams page, limit, sort_by, order, search, category, submitter_type, device_type, platform, from, to, tenant_id, facility_id, role, plan_tier, subscription_status, route_name, app_environment, app_version, locale, breakpoint, theme, connectivity, orientation
 * @bodyParams None
 * @returns {Object[]} Paginated feedback rows
 * @throws 401 Unauthorized
 * @throws 403 Forbidden
 */
router.get(
  '/',
  ...requireFeedbackAdmin(),
  validateRequest({ query: listFeedbackQuerySchema }),
  feedbackController.listFeedback
);

/**
 * @description Count stored feedback
 * @method GET
 * @route /api/v1/feedback/summary
 * @authentication Required
 * @permissions PLATFORM_OWNER, PLATFORM_ADMIN
 * @urlParams None
 * @queryParams search, category, submitter_type, device_type, platform, from, to, tenant_id, facility_id, role, plan_tier, subscription_status, route_name, app_environment, app_version, locale, breakpoint, theme, connectivity, orientation
 * @bodyParams None
 * @returns {Object} total, authenticated, anonymous, latest_submitted_at
 * @throws 401 Unauthorized
 * @throws 403 Forbidden
 */
router.get(
  '/summary',
  ...requireFeedbackAdmin(),
  validateRequest({ query: feedbackFilterQuerySchema }),
  feedbackController.getFeedbackSummary
);

/**
 * @description Distinct values and record counts for every feedback filter
 * @method GET
 * @route /api/v1/feedback/facets
 * @authentication Required
 * @permissions PLATFORM_OWNER, PLATFORM_ADMIN
 * @urlParams None
 * @queryParams search, category, submitter_type, device_type, platform, from, to, tenant_id, facility_id, role, plan_tier, subscription_status, route_name, app_environment, app_version, locale, breakpoint, theme, connectivity, orientation
 * @bodyParams None
 * @returns {Object} total, facets (per filter: value, optional label, count)
 * @throws 400 Validation error
 * @throws 401 Unauthorized
 * @throws 403 Forbidden
 */
router.get(
  '/facets',
  ...requireFeedbackAdmin(),
  validateRequest({ query: feedbackFilterQuerySchema }),
  feedbackController.getFeedbackFacets
);

/**
 * @description Download stored feedback as HOSSPI-FEEDBACK-DDMMYYYY-HHmmss.xlsx
 * @method GET
 * @route /api/v1/feedback/export
 * @authentication Required
 * @permissions PLATFORM_OWNER, PLATFORM_ADMIN
 * @urlParams None
 * @queryParams search, category, submitter_type, device_type, platform, from, to, tenant_id, facility_id, role, plan_tier, subscription_status, route_name, app_environment, app_version, locale, breakpoint, theme, connectivity, orientation, utc_offset_minutes
 * @bodyParams None
 * @returns {Buffer} Excel workbook
 * @throws 401 Unauthorized
 * @throws 403 Forbidden
 */
router.get(
  '/export',
  ...requireFeedbackAdmin(),
  validateRequest({ query: exportFeedbackQuerySchema }),
  feedbackController.exportFeedback
);

/**
 * @description Download the picked feedback records as HOSSPI-FEEDBACK-DDMMYYYY-HHmmss.xlsx
 * @method POST
 * @route /api/v1/feedback/export
 * @authentication Required
 * @permissions PLATFORM_OWNER, PLATFORM_ADMIN
 * @urlParams None
 * @queryParams None
 * @bodyParams human_friendly_ids, search, category, submitter_type, device_type, platform, from, to, tenant_id, facility_id, role, plan_tier, subscription_status, route_name, app_environment, app_version, locale, breakpoint, theme, connectivity, orientation, utc_offset_minutes
 * @returns {Buffer} Excel workbook
 * @throws 400 Validation error
 * @throws 401 Unauthorized
 * @throws 403 Forbidden
 */
router.post(
  '/export',
  ...requireFeedbackAdmin(),
  validateRequest({ body: exportFeedbackBodySchema }),
  feedbackController.exportFeedback
);

/**
 * @description Permanently delete selected feedback, or every record matching filters
 * @method DELETE
 * @route /api/v1/feedback
 * @authentication Required
 * @permissions PLATFORM_OWNER, PLATFORM_ADMIN
 * @urlParams None
 * @queryParams None
 * @bodyParams confirm (true), human_friendly_ids | all_matching (true) + filters
 * @returns {Object} deleted_count, deleted_at
 * @throws 400 Validation error
 * @throws 401 Unauthorized
 * @throws 403 Forbidden
 */
router.delete(
  '/',
  ...requireFeedbackAdmin(),
  validateRequest({ body: deleteFeedbackSchema }),
  feedbackController.deleteFeedback
);

module.exports = router;
