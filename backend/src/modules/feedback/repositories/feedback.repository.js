/**
 * Feedback repository
 */

const prisma = require('@prisma/client');
const { HttpError } = require('@lib/errors');

const FEEDBACK_EXPORT_PAGE_SIZE = 1000;
const CURRENT_SUBSCRIPTION_STATUSES = Object.freeze(['ACTIVE', 'TRIAL', 'PAST_DUE']);
// Prisma rejects a plain `null` for Json columns; omit them instead.
const FEEDBACK_JSON_FIELDS = Object.freeze([
  'user_roles_json',
  'user_permissions_json',
  'client_context_json'
]);
// Columns a free-text search looks in.
const FEEDBACK_SEARCH_FIELDS = Object.freeze([
  'human_friendly_id',
  'message',
  'user_email',
  'user_name',
  'tenant_name',
  'facility_name',
  'route_path',
  'screen_title'
]);

const FEEDBACK_RECEIPT_SELECT = Object.freeze({
  id: true,
  human_friendly_id: true,
  category: true,
  submitter_type: true,
  tenant_id: true,
  submitted_at: true
});

const FEEDBACK_LIST_SELECT = Object.freeze({
  human_friendly_id: true,
  category: true,
  message: true,
  submitter_type: true,
  user_email: true,
  user_name: true,
  tenant_name: true,
  facility_name: true,
  route_path: true,
  device_type: true,
  client_platform: true,
  submitted_at: true
});

const FEEDBACK_EXPORT_SELECT = Object.freeze({
  id: true,
  human_friendly_id: true,
  category: true,
  message: true,
  submitter_type: true,
  user_human_friendly_id: true,
  user_email: true,
  user_name: true,
  user_position_title: true,
  user_roles_json: true,
  user_permissions_json: true,
  tenant_human_friendly_id: true,
  tenant_name: true,
  facility_human_friendly_id: true,
  facility_name: true,
  subscription_plan_code: true,
  subscription_plan_name: true,
  subscription_tier_code: true,
  subscription_status: true,
  route_path: true,
  route_name: true,
  page_url: true,
  screen_title: true,
  client_platform: true,
  device_type: true,
  viewport_width: true,
  viewport_height: true,
  screen_width: true,
  screen_height: true,
  app_version: true,
  app_environment: true,
  locale: true,
  timezone: true,
  user_agent: true,
  ip_address: true,
  client_context_json: true,
  client_submitted_at: true,
  submitted_at: true
});

const toRepositoryError = (error) => {
  if (error instanceof HttpError) {
    return error;
  }
  if (error?.code === 'P2003') {
    const target = error.meta?.field_name || 'field';
    return new HttpError('errors.database.foreign_key_field', 400, [{ field: target }]);
  }
  return new HttpError('errors.database.unexpected', 500, [{ originalError: error?.message }]);
};

const createFeedbackEvent = async (tenantId, userId, eventName, payloadJson) => {
  try {
    return await prisma.analytics_event.create({
      data: {
        tenant_id: tenantId,
        user_id: userId || null,
        event_name: eventName,
        payload_json: payloadJson
      }
    });
  } catch (error) {
    throw toRepositoryError(error);
  }
};

const toFilterValues = (value) =>
  (Array.isArray(value) ? value : value ? [value] : []).filter(Boolean);

/**
 * Stored feedback matching optional filters. Rows soft-deleted by the first
 * release stay excluded.
 *
 * @param {Object} [filters] - search, category, submitter_type, device_type, platform, from, to
 * @returns {Object} Prisma where clause
 */
const buildActiveFeedbackWhere = (filters = {}) => {
  const conditions = [{ deleted_at: null }];

  const categories = toFilterValues(filters.category);
  if (categories.length > 0) {
    conditions.push({ category: { in: categories } });
  }
  if (filters.submitter_type) {
    conditions.push({ submitter_type: filters.submitter_type });
  }
  const deviceTypes = toFilterValues(filters.device_type);
  if (deviceTypes.length > 0) {
    conditions.push({ device_type: { in: deviceTypes } });
  }
  const platforms = toFilterValues(filters.platform);
  if (platforms.length > 0) {
    conditions.push({ client_platform: { in: platforms } });
  }
  if (filters.from || filters.to) {
    conditions.push({
      submitted_at: {
        ...(filters.from ? { gte: new Date(filters.from) } : {}),
        ...(filters.to ? { lte: new Date(filters.to) } : {})
      }
    });
  }
  const search = String(filters.search || '').trim();
  if (search) {
    conditions.push({
      OR: FEEDBACK_SEARCH_FIELDS.map((field) => ({ [field]: { contains: search } }))
    });
  }

  return conditions.length === 1 ? conditions[0] : { AND: conditions };
};

/**
 * Append one feedback record.
 *
 * @param {Object} data - Feedback columns
 * @returns {Promise<Object>} Receipt fields
 */
const createFeedback = async (data) => {
  const record = { ...data };
  FEEDBACK_JSON_FIELDS.forEach((field) => {
    if (record[field] === null || record[field] === undefined) {
      delete record[field];
    }
  });

  try {
    return await prisma.feedback.create({
      data: record,
      select: FEEDBACK_RECEIPT_SELECT
    });
  } catch (error) {
    throw toRepositoryError(error);
  }
};

/**
 * One page of feedback for review, with the total matching count.
 *
 * @param {Object} options
 * @param {Object} [options.filters]
 * @param {number} options.skip
 * @param {number} options.take
 * @param {Object[]} options.orderBy
 * @returns {Promise<{ rows: Object[], total: number }>}
 */
const listActiveFeedbackPage = async ({ filters = {}, skip = 0, take = 20, orderBy } = {}) => {
  const where = buildActiveFeedbackWhere(filters);

  try {
    const [rows, total] = await Promise.all([
      prisma.feedback.findMany({
        where,
        orderBy,
        skip,
        take,
        select: FEEDBACK_LIST_SELECT
      }),
      prisma.feedback.count({ where })
    ]);
    return { rows, total };
  } catch (error) {
    throw toRepositoryError(error);
  }
};

/**
 * Every active feedback row for export, newest first.
 *
 * @param {Object} [filters]
 * @param {Object} [options]
 * @param {string[]|null} [options.humanFriendlyIds] - Export exactly these records
 * @returns {Promise<Object[]>}
 */
const listActiveFeedbackForExport = async (filters = {}, { humanFriendlyIds } = {}) => {
  const matching = buildActiveFeedbackWhere(filters);
  const where =
    Array.isArray(humanFriendlyIds) && humanFriendlyIds.length > 0
      ? { AND: [matching, { human_friendly_id: { in: humanFriendlyIds } }] }
      : matching;
  const rows = [];
  let cursorId = null;
  let hasMore = true;

  try {
    // Keyset pages keep each query bounded however much feedback accumulates.
    while (hasMore) {
      const page = await prisma.feedback.findMany({
        where,
        orderBy: [{ submitted_at: 'desc' }, { id: 'desc' }],
        take: FEEDBACK_EXPORT_PAGE_SIZE,
        ...(cursorId ? { cursor: { id: cursorId }, skip: 1 } : {}),
        select: FEEDBACK_EXPORT_SELECT
      });
      rows.push(...page);
      hasMore = page.length === FEEDBACK_EXPORT_PAGE_SIZE;
      cursorId = page.length > 0 ? page[page.length - 1].id : null;
    }
    return rows;
  } catch (error) {
    throw toRepositoryError(error);
  }
};

/**
 * @param {Object} [filters]
 * @returns {Promise<{ total: number, anonymous: number, latest_submitted_at: Date|null }>}
 */
const summarizeActiveFeedback = async (filters = {}) => {
  const where = buildActiveFeedbackWhere(filters);

  try {
    const [total, anonymous, latest] = await Promise.all([
      prisma.feedback.count({ where }),
      prisma.feedback.count({ where: { AND: [where, { submitter_type: 'ANONYMOUS' }] } }),
      prisma.feedback.findFirst({
        where,
        orderBy: [{ submitted_at: 'desc' }],
        select: { submitted_at: true }
      })
    ]);
    return {
      total,
      anonymous,
      latest_submitted_at: latest?.submitted_at || null
    };
  } catch (error) {
    throw toRepositoryError(error);
  }
};

/**
 * Permanently delete feedback: exactly the listed records, or every match for
 * the filters. Rows are removed, not soft-deleted.
 *
 * @param {Object} options
 * @param {string[]} [options.humanFriendlyIds] - Delete exactly these records
 * @param {Object} [options.filters] - Otherwise delete every matching record
 * @returns {Promise<number>} Rows deleted
 */
const deleteFeedbackPermanently = async ({ humanFriendlyIds, filters } = {}) => {
  const where = Array.isArray(humanFriendlyIds)
    ? { AND: [buildActiveFeedbackWhere(), { human_friendly_id: { in: humanFriendlyIds } }] }
    : buildActiveFeedbackWhere(filters);

  try {
    const result = await prisma.feedback.deleteMany({ where });
    return result?.count || 0;
  } catch (error) {
    throw toRepositoryError(error);
  }
};

/**
 * @param {string|null} facilityId
 * @returns {Promise<Object|null>} Facility snapshot fields
 */
const findFacilitySnapshot = async (facilityId) => {
  if (!facilityId) {
    return null;
  }
  try {
    return await prisma.facility.findFirst({
      where: { id: facilityId },
      select: { id: true, human_friendly_id: true, name: true, tenant_id: true }
    });
  } catch (error) {
    throw toRepositoryError(error);
  }
};

/**
 * The tenant's current subscription, else its most recent one.
 *
 * @param {string|null} tenantId
 * @returns {Promise<Object|null>} Status and plan snapshot fields
 */
const findCurrentSubscriptionSnapshot = async (tenantId) => {
  if (!tenantId) {
    return null;
  }

  const select = {
    status: true,
    plan: { select: { code: true, name: true, tier_code: true } }
  };
  const orderBy = [{ start_date: 'desc' }, { created_at: 'desc' }];

  try {
    const current = await prisma.subscription.findFirst({
      where: {
        tenant_id: tenantId,
        deleted_at: null,
        status: { in: CURRENT_SUBSCRIPTION_STATUSES }
      },
      orderBy,
      select
    });
    if (current) {
      return current;
    }
    return await prisma.subscription.findFirst({
      where: { tenant_id: tenantId, deleted_at: null },
      orderBy,
      select
    });
  } catch (error) {
    throw toRepositoryError(error);
  }
};

module.exports = {
  buildActiveFeedbackWhere,
  createFeedback,
  createFeedbackEvent,
  deleteFeedbackPermanently,
  findCurrentSubscriptionSnapshot,
  findFacilitySnapshot,
  listActiveFeedbackForExport,
  listActiveFeedbackPage,
  summarizeActiveFeedback
};
