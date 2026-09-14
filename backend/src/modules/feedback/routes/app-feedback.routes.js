/**
 * Application feedback routes
 *
 * Mounted ahead of the global authentication chain in `src/app/router.js`:
 * "Give us feedback" must work on sign-in screens and after a session lapses,
 * so every route here declares its own authentication. Download and clear stay
 * with platform owners and platform admins, enforced here and in the service.
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
  clearFeedbackSchema,
  exportFeedbackQuerySchema,
  feedbackFilterQuerySchema,
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
 * @description Count stored feedback
 * @method GET
 * @route /api/v1/feedback/summary
 * @authentication Required
 * @permissions PLATFORM_OWNER, PLATFORM_ADMIN
 * @urlParams None
 * @queryParams category, submitter_type, from, to
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
 * @description Download stored feedback as HOSSPI-FEEDBACK-DDMMYYYY-HHmmss.xlsx
 * @method GET
 * @route /api/v1/feedback/export
 * @authentication Required
 * @permissions PLATFORM_OWNER, PLATFORM_ADMIN
 * @urlParams None
 * @queryParams category, submitter_type, from, to, utc_offset_minutes
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
 * @description Clear stored feedback (soft delete)
 * @method DELETE
 * @route /api/v1/feedback
 * @authentication Required
 * @permissions PLATFORM_OWNER, PLATFORM_ADMIN
 * @urlParams None
 * @queryParams None
 * @bodyParams confirm (must be true)
 * @returns {Object} cleared_count, cleared_at
 * @throws 400 Validation error
 * @throws 401 Unauthorized
 * @throws 403 Forbidden
 */
router.delete(
  '/',
  ...requireFeedbackAdmin(),
  validateRequest({ body: clearFeedbackSchema }),
  feedbackController.clearFeedback
);

module.exports = router;
