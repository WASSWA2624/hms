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
const multer = require('multer');
const router = express.Router();
const feedbackController = require('@controllers/feedback/feedback.controller');
const rateLimitConfig = require('@config/rateLimit');
const { HttpError } = require('@lib/errors');
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
  FEEDBACK_MAX_SCREENSHOTS,
  FEEDBACK_SCREENSHOT_FIELD,
  FEEDBACK_SCREENSHOT_MAX_BYTES
} = require('@lib/feedback/feedback-screenshots');
const {
  deleteFeedbackSchema,
  exportFeedbackBodySchema,
  exportFeedbackQuerySchema,
  feedbackFilterQuerySchema,
  feedbackRecordParamsSchema,
  feedbackScreenshotParamsSchema,
  listFeedbackQuerySchema,
  submitFeedbackSchema
} = require('@validations/feedback/feedback.schema');

// Live roles, not token claims: a revoked admin loses access immediately.
const requireFeedbackAdmin = () => [
  authenticate(),
  hydrateLiveAccess(),
  authorize(FEEDBACK_ADMIN_ROLES)
];

/** The multipart field carrying the JSON body beside the images. */
const FEEDBACK_PAYLOAD_FIELD = 'payload';

// Images are held in memory, never written to disk on the way through: they
// can show patient data, and the storage provider encrypts them on the way
// out. These caps are the API's; the service also refuses more shots than the
// submitter is allowed to send, and the whole request together.
//
// The JSON body limit does not apply here: `express.json` parses only JSON
// content types, so a multipart submission is bounded by these limits alone.
// The feedback rate limit (30 submissions an hour) stays as it is; what one
// client can send in an hour is bounded by it and by the caps below.
const feedbackScreenshotUpload = multer({
  storage: multer.memoryStorage(),
  limits: {
    files: FEEDBACK_MAX_SCREENSHOTS,
    fileSize: FEEDBACK_SCREENSHOT_MAX_BYTES
  }
});

/**
 * Feedback arrives as JSON, or — when it carries screenshots — as multipart
 * with that same JSON in a `payload` field beside the images. Both become
 * `req.body`, so one schema validates either shape and builds that know only
 * the JSON form keep working.
 */
const acceptFeedbackSubmission = (req, res, next) => {
  if (!req.is('multipart/form-data')) {
    return next();
  }

  return feedbackScreenshotUpload.array(
    FEEDBACK_SCREENSHOT_FIELD,
    FEEDBACK_MAX_SCREENSHOTS
  )(req, res, (error) => {
    if (error) {
      // Multer's own limits become localized 400s instead of generic 500s.
      return next(
        error instanceof multer.MulterError
          ? new HttpError('errors.validation.invalid', 400, [
              { field: FEEDBACK_SCREENSHOT_FIELD, code: error.code }
            ])
          : error
      );
    }

    try {
      const payload = req.body?.[FEEDBACK_PAYLOAD_FIELD];
      req.body = payload ? JSON.parse(payload) : {};
    } catch {
      return next(
        new HttpError('errors.validation.invalid', 400, [{ field: FEEDBACK_PAYLOAD_FIELD }])
      );
    }
    return next();
  });
};

/**
 * @description Submit application feedback from any screen
 * @method POST
 * @route /api/v1/feedback
 * @authentication Optional (anonymous when no valid bearer token)
 * @permissions Public
 * @urlParams None
 * @queryParams None
 * @bodyParams JSON: category, message, scope, scope_screens, screenshots, context.
 *   multipart/form-data: that same JSON in `payload`, plus up to 10 images
 *   (3 when anonymous) in `screenshots`
 * @returns {Object} Receipt with human_friendly_id, category, scope, submitter_type, submitted_at, screenshot_count
 * @throws 400 Validation error
 * @throws 429 Rate limit exceeded
 */
router.post(
  '/',
  rateLimit(rateLimitConfig.endpoints.feedback),
  authenticateOptional(),
  acceptFeedbackSubmission,
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
 * @queryParams page, limit, sort_by, order, search, category, submitter_type, device_type, platform, from, to, tenant_id, facility_id, role, plan_tier, subscription_status, route_name, applies_to, applies_to_route, app_environment, app_version, locale, breakpoint, theme, connectivity, orientation
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
 * @queryParams search, category, submitter_type, device_type, platform, from, to, tenant_id, facility_id, role, plan_tier, subscription_status, route_name, applies_to, applies_to_route, app_environment, app_version, locale, breakpoint, theme, connectivity, orientation
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
 * @queryParams search, category, submitter_type, device_type, platform, from, to, tenant_id, facility_id, role, plan_tier, subscription_status, route_name, applies_to, applies_to_route, app_environment, app_version, locale, breakpoint, theme, connectivity, orientation
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
 * @description Download stored feedback as HOSSPI-FEEDBACK-DDMMYYYY-HHmmss.zip
 *   (workbook, screenshots, prompts generator)
 * @method GET
 * @route /api/v1/feedback/export
 * @authentication Required
 * @permissions PLATFORM_OWNER, PLATFORM_ADMIN
 * @urlParams None
 * @queryParams search, category, submitter_type, device_type, platform, from, to, tenant_id, facility_id, role, plan_tier, subscription_status, route_name, applies_to, applies_to_route, app_environment, app_version, locale, breakpoint, theme, connectivity, orientation, utc_offset_minutes
 * @bodyParams None
 * @returns {Buffer} ZIP archive: workbook, screenshots, prompts generator
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
 * @description Download the picked feedback records as HOSSPI-FEEDBACK-DDMMYYYY-HHmmss.zip
 * @method POST
 * @route /api/v1/feedback/export
 * @authentication Required
 * @permissions PLATFORM_OWNER, PLATFORM_ADMIN
 * @urlParams None
 * @queryParams None
 * @bodyParams human_friendly_ids, search, category, submitter_type, device_type, platform, from, to, tenant_id, facility_id, role, plan_tier, subscription_status, route_name, applies_to, applies_to_route, app_environment, app_version, locale, breakpoint, theme, connectivity, orientation, utc_offset_minutes
 * @returns {Buffer} ZIP archive: workbook, screenshots, prompts generator
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
 * @description List the screenshots attached to one feedback record
 * @method GET
 * @route /api/v1/feedback/:human_friendly_id/screenshots
 * @authentication Required
 * @permissions PLATFORM_OWNER, PLATFORM_ADMIN
 * @urlParams human_friendly_id
 * @queryParams None
 * @bodyParams None
 * @returns {Object} human_friendly_id and items (id, sequence, screen, size, captured_at)
 * @throws 401 Unauthorized
 * @throws 403 Forbidden
 * @throws 404 Feedback not found
 */
router.get(
  '/:human_friendly_id/screenshots',
  ...requireFeedbackAdmin(),
  validateRequest({ params: feedbackRecordParamsSchema }),
  feedbackController.listFeedbackScreenshots
);

/**
 * @description Stream one feedback screenshot; never cached, never public
 * @method GET
 * @route /api/v1/feedback/:human_friendly_id/screenshots/:screenshot_id
 * @authentication Required
 * @permissions PLATFORM_OWNER, PLATFORM_ADMIN
 * @urlParams human_friendly_id, screenshot_id
 * @queryParams None
 * @bodyParams None
 * @returns {Buffer} Image bytes
 * @throws 401 Unauthorized
 * @throws 403 Forbidden
 * @throws 404 Screenshot not found
 */
router.get(
  '/:human_friendly_id/screenshots/:screenshot_id',
  ...requireFeedbackAdmin(),
  validateRequest({ params: feedbackScreenshotParamsSchema }),
  feedbackController.getFeedbackScreenshot
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
