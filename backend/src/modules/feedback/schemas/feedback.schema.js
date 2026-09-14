/**
 * Feedback module validation schemas
 */

const { z } = require('zod');

const FEEDBACK_CATEGORIES = Object.freeze([
  'GENERAL',
  'PROBLEM',
  'COMPLAINT',
  'SUGGESTION',
  'IMPROVEMENT'
]);
const FEEDBACK_SUBMITTER_TYPES = Object.freeze(['AUTHENTICATED', 'ANONYMOUS']);
const FEEDBACK_MESSAGE_MIN_LENGTH = 3;
const FEEDBACK_MESSAGE_MAX_LENGTH = 5000;
const MAX_UTC_OFFSET_MINUTES = 14 * 60;

const submitNpsSchema = z.object({
  score: z.number().int().min(0).max(10),
  comment: z.string().trim().max(2000).optional().nullable(),
  campaign_id: z.string().trim().max(120).optional().nullable()
});

const submitCsatSchema = z.object({
  rating: z.number().int().min(1).max(5),
  comment: z.string().trim().max(2000).optional().nullable(),
  campaign_id: z.string().trim().max(120).optional().nullable()
});

const optionalContextText = (maxLength) => z.string().trim().max(maxLength).optional().nullable();

const feedbackViewportSchema = z.object({
  width: z.number().nonnegative().max(100000),
  height: z.number().nonnegative().max(100000),
  device_pixel_ratio: z.number().positive().max(16).optional().nullable()
});

/**
 * Screen and device context the client attaches to a submission. All optional:
 * the server resolves identity, tenant, facility, and subscription itself.
 */
const feedbackClientContextSchema = z.object({
  route_path: optionalContextText(512),
  route_name: optionalContextText(120),
  page_url: optionalContextText(2048),
  screen_title: optionalContextText(255),
  platform: optionalContextText(40),
  app_version: optionalContextText(64),
  app_environment: optionalContextText(40),
  locale: optionalContextText(35),
  timezone: optionalContextText(64),
  utc_offset_minutes: z
    .number()
    .int()
    .min(-MAX_UTC_OFFSET_MINUTES)
    .max(MAX_UTC_OFFSET_MINUTES)
    .optional()
    .nullable(),
  breakpoint: optionalContextText(16),
  theme_mode: optionalContextText(16),
  text_scale: z.number().positive().max(10).optional().nullable(),
  connectivity: optionalContextText(16),
  session_status: optionalContextText(24),
  viewport: feedbackViewportSchema.optional().nullable(),
  client_submitted_at: z.string().datetime({ offset: true }).optional().nullable()
});

const submitFeedbackSchema = z.object({
  category: z.enum(FEEDBACK_CATEGORIES).default('GENERAL'),
  message: z.string().trim().min(FEEDBACK_MESSAGE_MIN_LENGTH).max(FEEDBACK_MESSAGE_MAX_LENGTH),
  context: feedbackClientContextSchema.optional().nullable()
});

const feedbackFilterQuerySchema = z.object({
  category: z.enum(FEEDBACK_CATEGORIES).optional(),
  submitter_type: z.enum(FEEDBACK_SUBMITTER_TYPES).optional(),
  from: z.string().datetime({ offset: true }).optional(),
  to: z.string().datetime({ offset: true }).optional()
});

const exportFeedbackQuerySchema = feedbackFilterQuerySchema.extend({
  utc_offset_minutes: z.coerce
    .number()
    .int()
    .min(-MAX_UTC_OFFSET_MINUTES)
    .max(MAX_UTC_OFFSET_MINUTES)
    .optional()
});

// An explicit flag, so a stray DELETE cannot wipe feedback.
const clearFeedbackSchema = z.object({
  confirm: z.literal(true)
});

module.exports = {
  FEEDBACK_CATEGORIES,
  FEEDBACK_MESSAGE_MAX_LENGTH,
  FEEDBACK_MESSAGE_MIN_LENGTH,
  FEEDBACK_SUBMITTER_TYPES,
  clearFeedbackSchema,
  exportFeedbackQuerySchema,
  feedbackFilterQuerySchema,
  submitCsatSchema,
  submitFeedbackSchema,
  submitNpsSchema
};
