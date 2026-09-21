/**
 * Feedback module validation schemas
 */

const { z } = require('zod');
const { paginationQuerySchema, searchQuerySchema, uuidSchema } = require('@lib/validation/zod');
const { FEEDBACK_MAX_SCREENSHOTS } = require('@lib/feedback/feedback-screenshots');

const FEEDBACK_CATEGORIES = Object.freeze([
  'GENERAL',
  'PROBLEM',
  'COMPLAINT',
  'SUGGESTION',
  'IMPROVEMENT'
]);
const FEEDBACK_SUBMITTER_TYPES = Object.freeze(['AUTHENTICATED', 'ANONYMOUS']);
// What a report applies to: the screen it was raised from, the whole app, or
// the screens the reporter picked.
const FEEDBACK_SCOPES = Object.freeze(['SCREEN', 'APP', 'SCREENS']);
const FEEDBACK_MAX_SCOPE_SCREENS = 40;
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

/**
 * A screen the reporter said their feedback applies to. Named as the app
 * knows it; a screen with neither a route name nor a path says nothing and is
 * rejected.
 */
const feedbackScopeScreenSchema = z
  .object({
    route_name: optionalContextText(120),
    route_path: optionalContextText(512),
    screen_title: optionalContextText(255)
  })
  .refine((screen) => Boolean(screen.route_name || screen.route_path), {
    message: 'A screen needs a route name or a route path',
    path: ['route_name']
  });

/**
 * What the app knows about one attached screenshot. The image itself travels
 * as a multipart file; these entries are matched to the files by position, so
 * the order must be the order the files are sent in.
 */
const feedbackScreenshotMetaSchema = z.object({
  width: z.number().int().positive().max(100000).optional().nullable(),
  height: z.number().int().positive().max(100000).optional().nullable(),
  caption: z.string().trim().max(255).optional().nullable(),
  route_path: optionalContextText(512),
  route_name: optionalContextText(120),
  screen_title: optionalContextText(255),
  // The window this shot was taken in, which can differ from the feedback's
  // own: a reporter rotates, resizes or switches theme between pictures.
  client_context: z
    .object({
      viewport_width: z.number().nonnegative().max(100000).optional().nullable(),
      viewport_height: z.number().nonnegative().max(100000).optional().nullable(),
      device_pixel_ratio: z.number().positive().max(16).optional().nullable(),
      orientation: optionalContextText(16),
      theme_mode: optionalContextText(16),
      breakpoint: optionalContextText(16)
    })
    .strict()
    .optional()
    .nullable(),
  captured_at: z.string().datetime({ offset: true }).optional().nullable()
});

/**
 * Feedback as submitted, whether the body is JSON or the `payload` field of a
 * multipart request carrying screenshots.
 */
const submitFeedbackSchema = z
  .object({
    category: z.enum(FEEDBACK_CATEGORIES).default('GENERAL'),
    message: z.string().trim().min(FEEDBACK_MESSAGE_MIN_LENGTH).max(FEEDBACK_MESSAGE_MAX_LENGTH),
    scope: z.enum(FEEDBACK_SCOPES).default('SCREEN'),
    scope_screens: z.array(feedbackScopeScreenSchema).max(FEEDBACK_MAX_SCOPE_SCREENS).optional(),
    screenshots: z.array(feedbackScreenshotMetaSchema).max(FEEDBACK_MAX_SCREENSHOTS).optional(),
    context: feedbackClientContextSchema.optional().nullable()
  })
  .superRefine((body, ctx) => {
    // "Selected screens" without screens would be indistinguishable from
    // "this screen" once stored.
    if (body.scope === 'SCREENS' && (body.scope_screens || []).length === 0) {
      ctx.addIssue({
        code: 'custom',
        message: 'Pick at least one screen',
        path: ['scope_screens']
      });
    }
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

const FEEDBACK_FILTER_MAX_VALUES = 50;

const filterList = (maxLength, normalize) =>
  z.preprocess(
    (value) => toFilterList(value, normalize),
    z.array(z.string().max(maxLength)).max(FEEDBACK_FILTER_MAX_VALUES).optional()
  );

// Lower-case values: platforms, environments, breakpoints, themes.
const textFilterList = (maxLength) => filterList(maxLength, (entry) => entry.toLowerCase());

// Upper-case codes: public ids, role names, plan tiers, statuses.
const codeFilterList = (maxLength) => filterList(maxLength, (entry) => entry.toUpperCase());

// Values matched as stored: route names, app versions, locales.
const exactFilterList = (maxLength) => filterList(maxLength, (entry) => entry);

/**
 * Filters shared by listing, counting, faceting, exporting, and deleting
 * feedback, so each narrows to exactly the same records. `from` and `to` bound
 * `submitted_at` and are inclusive. Tenants and facilities are named by their
 * public `human_friendly_id`. Unknown keys are rejected.
 */
const feedbackFiltersSchema = z
  .object({
    search: searchQuerySchema().optional(),
    category: enumFilterList(FEEDBACK_CATEGORIES),
    submitter_type: z.enum(FEEDBACK_SUBMITTER_TYPES).optional(),
    device_type: enumFilterList(FEEDBACK_DEVICE_TYPES),
    platform: textFilterList(40),
    from: z.string().datetime({ offset: true }).optional(),
    to: z.string().datetime({ offset: true }).optional(),
    // Who
    tenant_id: codeFilterList(32),
    facility_id: codeFilterList(32),
    role: codeFilterList(80),
    plan_tier: codeFilterList(40),
    subscription_status: codeFilterList(40),
    // Where
    route_name: exactFilterList(120),
    // What the report says it applies to, and the screens a `SCREENS` report
    // picked. `route_name` keeps its meaning: the screen it was raised from.
    applies_to: enumFilterList(FEEDBACK_SCOPES),
    applies_to_route: exactFilterList(120),
    app_environment: textFilterList(40),
    app_version: exactFilterList(64),
    // Device, from the client context
    locale: exactFilterList(35),
    breakpoint: textFilterList(16),
    theme: textFilterList(16),
    connectivity: textFilterList(16),
    orientation: textFilterList(16)
  })
  .strict();

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

/**
 * Path parameters of the screenshot routes. Feedback is addressed by its
 * public `FBK…` id, screenshots by their uuid.
 */
const feedbackScreenshotParamsSchema = z
  .object({
    human_friendly_id: z.string().trim().min(1).max(32),
    screenshot_id: uuidSchema
  })
  .strict();

const feedbackRecordParamsSchema = z
  .object({
    human_friendly_id: z.string().trim().min(1).max(32)
  })
  .strict();

module.exports = {
  FEEDBACK_CATEGORIES,
  FEEDBACK_DELETE_MAX_IDS,
  FEEDBACK_DEVICE_TYPES,
  FEEDBACK_EXPORT_MAX_IDS,
  FEEDBACK_FILTER_MAX_VALUES,
  FEEDBACK_MAX_SCOPE_SCREENS,
  FEEDBACK_MESSAGE_MAX_LENGTH,
  FEEDBACK_MESSAGE_MIN_LENGTH,
  FEEDBACK_SCOPES,
  FEEDBACK_SORT_FIELDS,
  FEEDBACK_SUBMITTER_TYPES,
  deleteFeedbackSchema,
  exportFeedbackBodySchema,
  exportFeedbackQuerySchema,
  feedbackFilterQuerySchema,
  feedbackFiltersSchema,
  feedbackRecordParamsSchema,
  feedbackScreenshotParamsSchema,
  listFeedbackQuerySchema,
  submitCsatSchema,
  submitFeedbackSchema,
  submitNpsSchema
};
