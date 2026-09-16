/**
 * Feedback module validation schemas
 */

const { z } = require('zod');
const { paginationQuerySchema, searchQuerySchema } = require('@lib/validation/zod');

const FEEDBACK_CATEGORIES = Object.freeze([
  'GENERAL',
  'PROBLEM',
  'COMPLAINT',
  'SUGGESTION',
  'IMPROVEMENT'
]);
const FEEDBACK_SUBMITTER_TYPES = Object.freeze(['AUTHENTICATED', 'ANONYMOUS']);
const FEEDBACK_DEVICE_TYPES = Object.freeze(['MOBILE', 'TABLET', 'DESKTOP']);
const FEEDBACK_SORT_FIELDS = Object.freeze([
  'submitted_at',
  'human_friendly_id',
  'category',
  'submitter_type',
  'device_type',
  'client_platform',
  'user_email',
  'tenant_name',
  'facility_name',
  'route_path'
]);
const FEEDBACK_MESSAGE_MIN_LENGTH = 3;
const FEEDBACK_MESSAGE_MAX_LENGTH = 5000;
const FEEDBACK_DELETE_MAX_IDS = 1000;
const FEEDBACK_EXPORT_MAX_IDS = 1000;
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

// The whole display, which can be larger than the app window.
const feedbackScreenSizeSchema = z.object({
  width: z.number().nonnegative().max(100000),
  height: z.number().nonnegative().max(100000)
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
  device_type: z.enum(FEEDBACK_DEVICE_TYPES).optional().nullable(),
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
  orientation: optionalContextText(16),
  viewport: feedbackViewportSchema.optional().nullable(),
  screen: feedbackScreenSizeSchema.optional().nullable(),
  client_submitted_at: z.string().datetime({ offset: true }).optional().nullable()
});

const submitFeedbackSchema = z.object({
  category: z.enum(FEEDBACK_CATEGORIES).default('GENERAL'),
  message: z.string().trim().min(FEEDBACK_MESSAGE_MIN_LENGTH).max(FEEDBACK_MESSAGE_MAX_LENGTH),
  context: feedbackClientContextSchema.optional().nullable()
});

// Multi-value filters arrive as `A,B` in a query string or `['A', 'B']` in JSON.
const toFilterList = (value, normalize) => {
  if (value === undefined || value === null || value === '') {
    return undefined;
  }
  const list = (Array.isArray(value) ? value : String(value).split(','))
    .map((entry) => normalize(String(entry ?? '').trim()))
    .filter(Boolean);
  return list.length > 0 ? Array.from(new Set(list)) : undefined;
};

const enumFilterList = (values) =>
  z.preprocess(
    (value) => toFilterList(value, (entry) => entry.toUpperCase()),
    z.array(z.enum(values)).optional()
  );

const textFilterList = (maxLength) =>
  z.preprocess(
    (value) => toFilterList(value, (entry) => entry.toLowerCase()),
    z.array(z.string().max(maxLength)).max(20).optional()
  );

/**
 * Filters shared by listing, counting, exporting, and deleting feedback.
 * `from` and `to` bound `submitted_at` and are inclusive.
 */
const feedbackFiltersSchema = z.object({
  search: searchQuerySchema().optional(),
  category: enumFilterList(FEEDBACK_CATEGORIES),
  submitter_type: z.enum(FEEDBACK_SUBMITTER_TYPES).optional(),
  device_type: enumFilterList(FEEDBACK_DEVICE_TYPES),
  platform: textFilterList(40),
  from: z.string().datetime({ offset: true }).optional(),
  to: z.string().datetime({ offset: true }).optional()
});

const feedbackFilterQuerySchema = feedbackFiltersSchema;

const listFeedbackQuerySchema = feedbackFiltersSchema.extend({
  ...paginationQuerySchema.shape,
  sort_by: z.enum(FEEDBACK_SORT_FIELDS).optional(),
  order: z.enum(['asc', 'desc']).optional()
});

const exportFeedbackQuerySchema = feedbackFiltersSchema.extend({
  utc_offset_minutes: z.coerce
    .number()
    .int()
    .min(-MAX_UTC_OFFSET_MINUTES)
    .max(MAX_UTC_OFFSET_MINUTES)
    .optional()
});

/**
 * Body form of the export request, for "Download feedback" once records are
 * picked: too many ids to carry in a URL. Without `human_friendly_ids` it
 * exports every record matching the filters, exactly as the query form does.
 */
const exportFeedbackBodySchema = exportFeedbackQuerySchema.extend({
  human_friendly_ids: z
    .array(z.string().trim().min(1).max(32))
    .min(1)
    .max(FEEDBACK_EXPORT_MAX_IDS)
    .optional()
});

/**
 * Permanent deletion of either the listed feedback ids or, with `all_matching`,
 * every record matching `filters`. `confirm` must be true so a stray DELETE
 * cannot remove feedback.
 */
const deleteFeedbackSchema = z
  .object({
    confirm: z.literal(true),
    human_friendly_ids: z
      .array(z.string().trim().min(1).max(32))
      .min(1)
      .max(FEEDBACK_DELETE_MAX_IDS)
      .optional(),
    all_matching: z.literal(true).optional(),
    filters: feedbackFiltersSchema.optional()
  })
  .refine((body) => Boolean(body.human_friendly_ids) !== Boolean(body.all_matching), {
    message: 'Provide either human_friendly_ids or all_matching',
    path: ['human_friendly_ids']
  });

module.exports = {
  FEEDBACK_CATEGORIES,
  FEEDBACK_DELETE_MAX_IDS,
  FEEDBACK_DEVICE_TYPES,
  FEEDBACK_EXPORT_MAX_IDS,
  FEEDBACK_MESSAGE_MAX_LENGTH,
  FEEDBACK_MESSAGE_MIN_LENGTH,
  FEEDBACK_SORT_FIELDS,
  FEEDBACK_SUBMITTER_TYPES,
  deleteFeedbackSchema,
  exportFeedbackBodySchema,
  exportFeedbackQuerySchema,
  feedbackFilterQuerySchema,
  feedbackFiltersSchema,
  listFeedbackQuerySchema,
  submitCsatSchema,
  submitFeedbackSchema,
  submitNpsSchema
};
