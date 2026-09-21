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
  scope: true,
  submitter_type: true,
  tenant_id: true,
  submitted_at: true
});

const FEEDBACK_SCOPE_SCREEN_SELECT = Object.freeze({
  sequence: true,
  route_name: true,
  route_path: true,
  screen_title: true
});

const FEEDBACK_SCREENSHOT_SELECT = Object.freeze({
  id: true,
  sequence: true,
  storage_key: true,
  content_type: true,
  byte_size: true,
  width: true,
  height: true,
  caption: true,
  route_path: true,
  route_name: true,
  screen_title: true,
  client_context_json: true,
  captured_at: true
});

const FEEDBACK_LIST_SELECT = Object.freeze({
  human_friendly_id: true,
  category: true,
  message: true,
  scope: true,
  submitter_type: true,
  user_email: true,
  user_name: true,
  tenant_name: true,
  facility_name: true,
  route_path: true,
  device_type: true,
  client_platform: true,
  submitted_at: true,
  scope_screens: {
    select: FEEDBACK_SCOPE_SCREEN_SELECT,
    orderBy: { sequence: 'asc' }
  },
  _count: { select: { screenshots: true } }
});

const FEEDBACK_EXPORT_SELECT = Object.freeze({
  id: true,
  human_friendly_id: true,
  category: true,
  message: true,
  scope: true,
  scope_screens: {
    select: FEEDBACK_SCOPE_SCREEN_SELECT,
    orderBy: { sequence: 'asc' }
  },
  screenshots: {
    select: FEEDBACK_SCREENSHOT_SELECT,
    orderBy: { sequence: 'asc' }
  },
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
 * Every filter dimension, keyed by its filter name, and where its values live.
 *
 * - `column`: an indexed feedback column; `labelColumn` names each value in
 *   facets (tenant and facility names beside their public ids).
 * - `rolesJson`: any role in the `user_roles_json` array.
 * - `contextKey`: a key of `client_context_json`.
 * - `scopeScreenColumn`: a column of the screens a report says it applies to.
 *
 * JSON filters go through Prisma's JSON filters, so values stay parameterized.
 */
const FEEDBACK_FILTER_DIMENSIONS = Object.freeze({
  category: { column: 'category' },
  submitter_type: { column: 'submitter_type' },
  device_type: { column: 'device_type' },
  platform: { column: 'client_platform' },
  tenant_id: { column: 'tenant_human_friendly_id', labelColumn: 'tenant_name' },
  facility_id: { column: 'facility_human_friendly_id', labelColumn: 'facility_name' },
  role: { rolesJson: true },
  plan_tier: { column: 'subscription_tier_code' },
  subscription_status: { column: 'subscription_status' },
  route_name: { column: 'route_name' },
  applies_to: { column: 'scope' },
  applies_to_route: { scopeScreenColumn: 'route_name' },
  app_environment: { column: 'app_environment' },
  app_version: { column: 'app_version' },
  locale: { column: 'locale' },
  breakpoint: { contextKey: 'breakpoint' },
  theme: { contextKey: 'theme_mode' },
  connectivity: { contextKey: 'connectivity' },
  orientation: { contextKey: 'orientation' }
});

const FEEDBACK_FILTER_KEYS = Object.freeze(Object.keys(FEEDBACK_FILTER_DIMENSIONS));

// Dimensions read from the screens a report applies to, counted on the child
// table rather than on `feedback`.
const FEEDBACK_SCOPE_SCREEN_FILTER_KEYS = Object.freeze(
  FEEDBACK_FILTER_KEYS.filter((key) => Boolean(FEEDBACK_FILTER_DIMENSIONS[key].scopeScreenColumn))
);

// Dimensions read from JSON, which Prisma cannot group by.
const FEEDBACK_JSON_FILTER_KEYS = Object.freeze(
  FEEDBACK_FILTER_KEYS.filter(
    (key) =>
      !FEEDBACK_FILTER_DIMENSIONS[key].column &&
      !FEEDBACK_FILTER_DIMENSIONS[key].scopeScreenColumn
  )
);

// Most distinct values a facet lists; the most frequent are kept.
const FEEDBACK_FACET_VALUE_LIMIT = 200;

const buildDimensionCondition = (key, values) => {
  const dimension = FEEDBACK_FILTER_DIMENSIONS[key];
  if (dimension.column) {
    return { [dimension.column]: { in: values } };
  }
  if (dimension.scopeScreenColumn) {
    // A report matches when any screen it applies to is one of these.
    return { scope_screens: { some: { [dimension.scopeScreenColumn]: { in: values } } } };
  }
  if (dimension.rolesJson) {
    return {
      OR: values.map((role) => ({ user_roles_json: { array_contains: [role] } }))
    };
  }
  return {
    OR: values.map((value) => ({
      client_context_json: { path: `$.${dimension.contextKey}`, equals: value }
    }))
  };
};

/**
 * Stored feedback matching optional filters. Rows soft-deleted by the first
 * release stay excluded.
 *
 * @param {Object} [filters] - search, from, to, and any key of
 *   FEEDBACK_FILTER_DIMENSIONS
 * @param {Object} [options]
 * @param {string[]} [options.omit] - Dimensions to leave out, so a facet can
 *   count values its own filter would hide
 * @returns {Object} Prisma where clause
 */
const buildActiveFeedbackWhere = (filters = {}, { omit = [] } = {}) => {
  const conditions = [{ deleted_at: null }];

  FEEDBACK_FILTER_KEYS.forEach((key) => {
    if (omit.includes(key)) {
      return;
    }
    const values = toFilterValues(filters[key]);
    if (values.length > 0) {
      conditions.push(buildDimensionCondition(key, values));
    }
  });
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
 * Append one feedback record, with the screens it says it applies to.
 *
 * `scope_screens` arrives as a plain list and is written with the row.
 * Screenshots are written afterwards by `createFeedbackScreenshots`: their
 * storage keys are built from the id this row gets.
 *
 * @param {Object} data - Feedback columns, plus an optional `scope_screens` list
 * @returns {Promise<Object>} Receipt fields
 */
const createFeedback = async (data) => {
  const { scope_screens: scopeScreens, ...columns } = data || {};
  const record = { ...columns };
  FEEDBACK_JSON_FIELDS.forEach((field) => {
    if (record[field] === null || record[field] === undefined) {
      delete record[field];
    }
  });
  if (Array.isArray(scopeScreens) && scopeScreens.length > 0) {
    record.scope_screens = {
      create: scopeScreens.map((screen, index) => ({
        sequence: index + 1,
        route_name: screen.route_name || null,
        route_path: screen.route_path || null,
        screen_title: screen.screen_title || null
      }))
    };
  }

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
 * Record the screenshots that reached storage, in capture order.
 *
 * @param {string} feedbackId
 * @param {Object[]} screenshots - Rows from `storeFeedbackScreenshots`
 * @returns {Promise<number>} Rows written
 */
const createFeedbackScreenshots = async (feedbackId, screenshots = []) => {
  if (!feedbackId || screenshots.length === 0) {
    return 0;
  }

  try {
    const result = await prisma.feedback_screenshot.createMany({
      data: screenshots.map((screenshot, index) => ({
        feedback_id: feedbackId,
        sequence: screenshot.sequence || index + 1,
        storage_key: screenshot.storage_key,
        content_type: screenshot.content_type,
        byte_size: screenshot.byte_size,
        width: screenshot.width ?? null,
        height: screenshot.height ?? null,
        caption: screenshot.caption ?? null,
        route_path: screenshot.route_path ?? null,
        route_name: screenshot.route_name ?? null,
        screen_title: screenshot.screen_title ?? null,
        // Prisma rejects a plain null for a Json column.
        ...(screenshot.client_context_json
          ? { client_context_json: screenshot.client_context_json }
          : {}),
        captured_at: screenshot.captured_at ?? null
      }))
    });
    return result?.count || 0;
  } catch (error) {
    throw toRepositoryError(error);
  }
};

/**
 * The screenshots of one record, oldest first, for review in the app.
 *
 * @param {string} humanFriendlyId - Public feedback id
 * @returns {Promise<Object|null>} The record with its screenshots, else null
 */
const findFeedbackWithScreenshots = async (humanFriendlyId) => {
  const reference = String(humanFriendlyId || '').trim();
  if (!reference) {
    return null;
  }

  try {
    return await prisma.feedback.findFirst({
      where: { AND: [buildActiveFeedbackWhere(), { human_friendly_id: reference }] },
      select: {
        id: true,
        human_friendly_id: true,
        submitted_at: true,
        screenshots: {
          select: FEEDBACK_SCREENSHOT_SELECT,
          orderBy: { sequence: 'asc' }
        }
      }
    });
  } catch (error) {
    throw toRepositoryError(error);
  }
};

/**
 * One screenshot, scoped to the record that owns it so an id from another
 * record cannot be read through it.
 *
 * @param {string} humanFriendlyId - Public feedback id
 * @param {string} screenshotId
 * @returns {Promise<Object|null>}
 */
const findFeedbackScreenshot = async (humanFriendlyId, screenshotId) => {
  const reference = String(humanFriendlyId || '').trim();
  const id = String(screenshotId || '').trim();
  if (!reference || !id) {
    return null;
  }

  try {
    return await prisma.feedback_screenshot.findFirst({
      where: {
        id,
        feedback: { AND: [buildActiveFeedbackWhere(), { human_friendly_id: reference }] }
      },
      select: FEEDBACK_SCREENSHOT_SELECT
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

const byCountThenValue = (left, right) =>
  right.count - left.count || String(left.value).localeCompare(String(right.value));

const toFacetValues = (counts, labels = new Map()) =>
  Array.from(counts.entries())
    .map(([value, count]) => ({
      value,
      ...(labels.has(value) ? { label: labels.get(value) } : {}),
      count
    }))
    .sort(byCountThenValue)
    .slice(0, FEEDBACK_FACET_VALUE_LIMIT);

/**
 * Distinct values of one column with how many records hold each. A value
 * stored under several labels (a renamed tenant) keeps its most common label.
 */
const countColumnFacet = async (key, filters) => {
  const { column, labelColumn } = FEEDBACK_FILTER_DIMENSIONS[key];
  // Records without a value (e.g. anonymous tenant) group under null, dropped below.
  const groups = await prisma.feedback.groupBy({
    by: labelColumn ? [column, labelColumn] : [column],
    where: buildActiveFeedbackWhere(filters, { omit: [key] }),
    _count: { _all: true }
  });

  const counts = new Map();
  const labels = new Map();
  const labelCounts = new Map();
  groups.forEach((group) => {
    const value = group[column];
    const count = group._count?._all || 0;
    if (value === null || value === undefined || value === '') {
      return;
    }
    counts.set(value, (counts.get(value) || 0) + count);
    const label = labelColumn ? group[labelColumn] : null;
    if (label && count > (labelCounts.get(value) || 0)) {
      labels.set(value, label);
      labelCounts.set(value, count);
    }
  });
  return toFacetValues(counts, labels);
};

/**
 * Distinct values of a screens-applied-to column, counted on the child table
 * under every other active filter. A report never lists the same screen
 * twice, so a screen's row count is its record count.
 */
const countScopeScreenFacet = async (key, filters) => {
  const { scopeScreenColumn } = FEEDBACK_FILTER_DIMENSIONS[key];
  const groups = await prisma.feedback_scope_screen.groupBy({
    by: [scopeScreenColumn],
    where: { feedback: buildActiveFeedbackWhere(filters, { omit: [key] }) },
    _count: { _all: true }
  });

  const counts = new Map();
  groups.forEach((group) => {
    const value = group[scopeScreenColumn];
    if (value === null || value === undefined || value === '') {
      return;
    }
    counts.set(value, (counts.get(value) || 0) + (group._count?._all || 0));
  });
  return toFacetValues(counts);
};

// A row's values for each JSON dimension, as filters compare them.
const readJsonDimensionValues = (row) => {
  const context =
    row.client_context_json && typeof row.client_context_json === 'object'
      ? row.client_context_json
      : {};
  const values = {};
  FEEDBACK_JSON_FILTER_KEYS.forEach((key) => {
    const dimension = FEEDBACK_FILTER_DIMENSIONS[key];
    const raw = dimension.rolesJson
      ? Array.isArray(row.user_roles_json)
        ? row.user_roles_json
        : []
      : [context[dimension.contextKey]];
    values[key] = Array.from(
      new Set(raw.filter((value) => typeof value === 'string' && value.trim() !== ''))
    );
  });
  return values;
};

/**
 * Counts for the JSON dimensions. Prisma cannot group by a JSON path, and raw
 * SQL would have to duplicate every filter this module builds, so the two JSON
 * columns of the matching rows are read in keyset pages and counted here.
 * Feedback is a low-volume table; each page stays bounded.
 */
const countJsonFacets = async (filters) => {
  const activeJsonFilters = FEEDBACK_JSON_FILTER_KEYS.map((key) => [
    key,
    toFilterValues(filters[key])
  ]).filter(([, values]) => values.length > 0);
  const where = buildActiveFeedbackWhere(filters, { omit: FEEDBACK_JSON_FILTER_KEYS });
  const counts = Object.fromEntries(FEEDBACK_JSON_FILTER_KEYS.map((key) => [key, new Map()]));
  let cursorId = null;
  let hasMore = true;

  while (hasMore) {
    const page = await prisma.feedback.findMany({
      where,
      orderBy: [{ id: 'asc' }],
      take: FEEDBACK_EXPORT_PAGE_SIZE,
      ...(cursorId ? { cursor: { id: cursorId }, skip: 1 } : {}),
      select: { id: true, user_roles_json: true, client_context_json: true }
    });
    page.forEach((row) => {
      const rowValues = readJsonDimensionValues(row);
      const failing = activeJsonFilters
        .filter(([key, wanted]) => !rowValues[key].some((value) => wanted.includes(value)))
        .map(([key]) => key);
      FEEDBACK_JSON_FILTER_KEYS.forEach((key) => {
        // Each facet ignores only its own filter.
        if (failing.some((failed) => failed !== key)) {
          return;
        }
        rowValues[key].forEach((value) => {
          counts[key].set(value, (counts[key].get(value) || 0) + 1);
        });
      });
    });
    hasMore = page.length === FEEDBACK_EXPORT_PAGE_SIZE;
    cursorId = page.length > 0 ? page[page.length - 1].id : null;
  }

  return Object.fromEntries(
    FEEDBACK_JSON_FILTER_KEYS.map((key) => [key, toFacetValues(counts[key])])
  );
};

/**
 * Distinct values, with record counts, for every filter dimension. Each
 * dimension's counts apply every other active filter but not its own, so the
 * values a user could add to a filter stay listed.
 *
 * @param {Object} [filters]
 * @returns {Promise<{ total: number, facets: Object<string, Object[]> }>}
 */
const summarizeFeedbackFacets = async (filters = {}) => {
  const columnKeys = FEEDBACK_FILTER_KEYS.filter(
    (key) => FEEDBACK_FILTER_DIMENSIONS[key].column
  );

  try {
    const [total, columnFacets, scopeScreenFacets, jsonFacets] = await Promise.all([
      prisma.feedback.count({ where: buildActiveFeedbackWhere(filters) }),
      Promise.all(columnKeys.map((key) => countColumnFacet(key, filters))),
      Promise.all(
        FEEDBACK_SCOPE_SCREEN_FILTER_KEYS.map((key) => countScopeScreenFacet(key, filters))
      ),
      countJsonFacets(filters)
    ]);
    const facets = {};
    FEEDBACK_FILTER_KEYS.forEach((key) => {
      const columnIndex = columnKeys.indexOf(key);
      const scopeScreenIndex = FEEDBACK_SCOPE_SCREEN_FILTER_KEYS.indexOf(key);
      if (columnIndex >= 0) {
        facets[key] = columnFacets[columnIndex];
      } else if (scopeScreenIndex >= 0) {
        facets[key] = scopeScreenFacets[scopeScreenIndex];
      } else {
        facets[key] = jsonFacets[key];
      }
    });
    return { total, facets };
  } catch (error) {
    throw toRepositoryError(error);
  }
};

/**
 * Permanently delete feedback: exactly the listed records, or every match for
 * the filters. Rows are removed, not soft-deleted, and their screenshots and
 * scope screens go with them through the cascade.
 *
 * The storage keys of those screenshots are read first and handed back: once
 * the rows are gone nothing points at the stored images any more, so the
 * caller deletes them from the provider in the same operation.
 *
 * @param {Object} options
 * @param {string[]} [options.humanFriendlyIds] - Delete exactly these records
 * @param {Object} [options.filters] - Otherwise delete every matching record
 * @returns {Promise<{ count: number, storage_keys: string[] }>}
 */
const deleteFeedbackPermanently = async ({ humanFriendlyIds, filters } = {}) => {
  const where = Array.isArray(humanFriendlyIds)
    ? { AND: [buildActiveFeedbackWhere(), { human_friendly_id: { in: humanFriendlyIds } }] }
    : buildActiveFeedbackWhere(filters);

  try {
    const images = await prisma.feedback_screenshot.findMany({
      where: { feedback: where },
      select: { storage_key: true }
    });
    const result = await prisma.feedback.deleteMany({ where });
    return {
      count: result?.count || 0,
      storage_keys: images
        .map((image) => image.storage_key)
        .filter((key) => typeof key === 'string' && key.trim() !== '')
    };
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
  FEEDBACK_FILTER_KEYS,
  buildActiveFeedbackWhere,
  createFeedback,
  createFeedbackEvent,
  createFeedbackScreenshots,
  deleteFeedbackPermanently,
  findCurrentSubscriptionSnapshot,
  findFacilitySnapshot,
  findFeedbackScreenshot,
  findFeedbackWithScreenshots,
  listActiveFeedbackForExport,
  listActiveFeedbackPage,
  summarizeActiveFeedback,
  summarizeFeedbackFacets
};
