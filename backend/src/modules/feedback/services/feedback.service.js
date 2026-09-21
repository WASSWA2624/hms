/**
 * Feedback service
 */

const { randomUUID } = require('crypto');
const feedbackRepository = require('@repositories/feedback/feedback.repository');
const authRepository = require('@repositories/auth/auth.repository');
const { createAuditLog } = require('@lib/audit');
const { HttpError } = require('@lib/errors');
const { logger } = require('@lib/logging');
const {
  getRoleNames,
  resolveEffectiveAccess
} = require('@lib/authorization/effective-access');
const { resolveTenantModuleEntitlements } = require('@lib/subscriptions/tenant-entitlements');
const { hasFeedbackAdminRole } = require('@lib/feedback/feedback-access');
const {
  buildFeedbackClientContextJson,
  resolveFeedbackDeviceType,
  sanitizeFeedbackLocation,
  toFeedbackPixelCount,
  truncateFeedbackText
} = require('@lib/feedback/feedback-context');
const {
  buildFeedbackExportFileName,
  listFeedbackExportScreenshots,
  renderFeedbackWorkbook,
  resolveExportClock
} = require('@lib/feedback/feedback-export');
const {
  FEEDBACK_ARCHIVE_MIME_TYPE,
  buildFeedbackArchiveFileName,
  streamFeedbackArchive
} = require('@lib/feedback/feedback-archive');
const {
  FEEDBACK_SCREENSHOTS_MAX_TOTAL_BYTES,
  buildFeedbackScreenshotFileName,
  maxFeedbackScreenshotsFor,
  prepareFeedbackScreenshots
} = require('@lib/feedback/feedback-screenshots');
const {
  deleteFeedbackScreenshotObjects,
  readFeedbackScreenshot,
  storeFeedbackScreenshots
} = require('@lib/storage/feedback-screenshot-storage');

const FEEDBACK_LIST_DEFAULT_LIMIT = 20;
const FEEDBACK_MESSAGE_PREVIEW_LENGTH = 280;
const FEEDBACK_AUDIT_ID_SAMPLE = 200;
const FEEDBACK_SORTABLE_FIELDS = new Set([
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

const ensureTenant = (context) => {
  if (!context.tenant_id) {
    throw new HttpError('errors.auth.forbidden', 403);
  }
};

const submitNpsFeedback = async (data, context = {}) => {
  ensureTenant(context);

  const event = await feedbackRepository.createFeedbackEvent(
    context.tenant_id,
    context.user_id,
    'feedback.nps',
    {
      score: data.score,
      comment: data.comment || null,
      campaign_id: data.campaign_id || null
    }
  );

  await createAuditLog({
    user_id: context.user_id,
    tenant_id: context.tenant_id,
    action: 'FEEDBACK_NPS',
    entity: 'feedback',
    entity_id: event.id,
    diff: {
      after: event
    },
    ip_address: context.ip_address
  }).catch(() => {});

  return {
    feedback_id: event.id,
    score: data.score,
    submitted_at: event.occurred_at
  };
};

const submitCsatFeedback = async (data, context = {}) => {
  ensureTenant(context);

  const event = await feedbackRepository.createFeedbackEvent(
    context.tenant_id,
    context.user_id,
    'feedback.csat',
    {
      rating: data.rating,
      comment: data.comment || null,
      campaign_id: data.campaign_id || null
    }
  );

  await createAuditLog({
    user_id: context.user_id,
    tenant_id: context.tenant_id,
    action: 'FEEDBACK_CSAT',
    entity: 'feedback',
    entity_id: event.id,
    diff: {
      after: event
    },
    ip_address: context.ip_address
  }).catch(() => {});

  return {
    feedback_id: event.id,
    rating: data.rating,
    submitted_at: event.occurred_at
  };
};

const ANONYMOUS_SUBMITTER = Object.freeze({
  submitter_type: 'ANONYMOUS',
  user_id: null,
  tenant_id: null,
  facility_id: null
});

const toIdentifier = (value) => {
  const text = String(value || '').trim();
  return text || null;
};

const toUniqueList = (values, { sort = false } = {}) => {
  const list = Array.from(
    new Set(
      (Array.isArray(values) ? values : [])
        .map((value) => String(value || '').trim())
        .filter(Boolean)
    )
  );
  return sort ? list.sort() : list;
};

const buildDisplayName = (profile) => {
  if (!profile) {
    return null;
  }
  const name = [profile.first_name, profile.middle_name, profile.last_name]
    .map((part) => String(part || '').trim())
    .filter(Boolean)
    .join(' ');
  return name || null;
};

const parseOptionalDate = (value) => {
  if (!value) {
    return null;
  }
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
};

// Context is best effort: a failed lookup must never cost the user their feedback.
const settleContextLookup = (lookup, promise) =>
  Promise.resolve(promise).catch((error) => {
    logger.warn('Feedback context lookup failed', { lookup, error: error?.message });
    return null;
  });

const findLiveSubmitter = async (userId) => {
  const user = await settleContextLookup('user', authRepository.findUserById(userId));
  return user && typeof user === 'object' && user.id ? user : null;
};

/**
 * Resolve the submitter's live roles and effective permissions.
 *
 * Mirrors `hydrateLiveAccess`, so the snapshot shows the rights the user
 * actually had, plan gates included. Falls back to the token claims.
 */
const resolveSubmitterAccess = async (liveUser, { tenantId, facilityId }, tokenUser = {}) => {
  try {
    const entitlements = tenantId ? await resolveTenantModuleEntitlements(tenantId) : [];
    const access = resolveEffectiveAccess(
      {
        ...liveUser,
        tenant_id: tenantId,
        facility_id: facilityId || liveUser.facility_id
      },
      {
        moduleEntitlements: entitlements,
        applyPlanGate: true,
        applyAssignedModuleGate: true
      }
    );
    return {
      roles: toUniqueList(getRoleNames(liveUser)),
      permissions: toUniqueList(access?.permissions, { sort: true })
    };
  } catch (error) {
    logger.warn('Feedback submitter access fell back to token claims', { error: error?.message });
    return {
      roles: toUniqueList(tokenUser.roles),
      permissions: toUniqueList(tokenUser.permissions, { sort: true })
    };
  }
};

/**
 * Snapshot who submitted feedback, or mark it anonymous.
 *
 * Identity comes from the database, never from client input: a token only
 * names the user. A token whose user cannot be found is treated as anonymous.
 *
 * @param {Object|null} tokenUser - `req.user` from optional authentication
 * @returns {Promise<Object>} Submitter columns
 */
const resolveSubmitterSnapshot = async (tokenUser) => {
  const userId = toIdentifier(tokenUser?.id || tokenUser?.user_id || tokenUser?.userId);
  if (!userId) {
    return { ...ANONYMOUS_SUBMITTER };
  }

  const liveUser = await findLiveSubmitter(userId);
  if (!liveUser) {
    return { ...ANONYMOUS_SUBMITTER };
  }

  const tenantId = toIdentifier(liveUser.tenant_id);
  // The token carries the facility the user is working in right now.
  const facilityId =
    toIdentifier(tokenUser.facility_id || tokenUser.facilityId) ||
    toIdentifier(liveUser.facility_id);

  const [facility, subscription, access] = await Promise.all([
    settleContextLookup('facility', feedbackRepository.findFacilitySnapshot(facilityId)),
    settleContextLookup('subscription', feedbackRepository.findCurrentSubscriptionSnapshot(tenantId)),
    resolveSubmitterAccess(liveUser, { tenantId, facilityId }, tokenUser)
  ]);

  // Never attribute another tenant's facility to this submitter.
  const scopedFacility =
    facility && (!tenantId || facility.tenant_id === tenantId) ? facility : null;

  return {
    submitter_type: 'AUTHENTICATED',
    user_id: liveUser.id,
    tenant_id: tenantId,
    facility_id: scopedFacility?.id || null,
    user_human_friendly_id: truncateFeedbackText(liveUser.human_friendly_id, 32),
    user_email: truncateFeedbackText(liveUser.email, 255),
    user_name: truncateFeedbackText(buildDisplayName(liveUser.profile), 255),
    user_position_title: truncateFeedbackText(liveUser.position_title, 120),
    user_roles_json: access.roles,
    user_permissions_json: access.permissions,
    tenant_human_friendly_id: truncateFeedbackText(liveUser.tenant?.human_friendly_id, 32),
    tenant_name: truncateFeedbackText(liveUser.tenant?.name, 255),
    facility_human_friendly_id: truncateFeedbackText(scopedFacility?.human_friendly_id, 32),
    facility_name: truncateFeedbackText(scopedFacility?.name, 255),
    subscription_plan_code: truncateFeedbackText(subscription?.plan?.code, 80),
    subscription_plan_name: truncateFeedbackText(subscription?.plan?.name, 255),
    subscription_tier_code: truncateFeedbackText(subscription?.plan?.tier_code, 40),
    subscription_status: truncateFeedbackText(subscription?.status, 40)
  };
};

/**
 * The screens a reporter picked, deduplicated and capped to what the schema
 * allows, and only for a report that says it applies to picked screens.
 */
const resolveScopeScreens = (data = {}) => {
  if (data.scope !== 'SCREENS') {
    return [];
  }
  const seen = new Set();
  return (Array.isArray(data.scope_screens) ? data.scope_screens : []).reduce(
    (screens, screen) => {
      const routeName = truncateFeedbackText(screen?.route_name, 120);
      const routePath = sanitizeFeedbackLocation(screen?.route_path, 512);
      const key = `${routeName || ''}|${routePath || ''}`;
      if (seen.has(key) || (!routeName && !routePath)) {
        return screens;
      }
      seen.add(key);
      screens.push({
        route_name: routeName,
        route_path: routePath,
        screen_title: truncateFeedbackText(screen?.screen_title, 255)
      });
      return screens;
    },
    []
  );
};

/**
 * Check the images of a submission before anything is stored.
 *
 * Too many, too large, or not an image at all is a bad request, not a silent
 * drop: the reporter can fix it while they still have the draft in front of
 * them.
 *
 * @param {Object[]} files - Multer memory-storage files
 * @param {Object[]} metadata - Per-shot metadata, in the order of the files
 * @param {boolean} authenticated - Whether a session identified the submitter
 * @returns {Object[]} Accepted screenshots, ready to store
 */
const validateSubmittedScreenshots = (files, metadata, authenticated) => {
  if (files.length === 0) {
    return [];
  }

  const limit = maxFeedbackScreenshotsFor({ authenticated });
  if (files.length > limit) {
    throw new HttpError('errors.validation.invalid', 400, [
      { field: 'screenshots', max: limit }
    ]);
  }

  const { accepted, rejected } = prepareFeedbackScreenshots({ files, metadata });
  if (rejected.length > 0) {
    throw new HttpError('errors.validation.invalid', 400, [
      { field: 'screenshots', rejected: rejected.map((entry) => entry.index) }
    ]);
  }

  const totalBytes = accepted.reduce((sum, screenshot) => sum + screenshot.byte_size, 0);
  if (totalBytes > FEEDBACK_SCREENSHOTS_MAX_TOTAL_BYTES) {
    throw new HttpError('errors.validation.invalid', 400, [
      { field: 'screenshots', max_total_bytes: FEEDBACK_SCREENSHOTS_MAX_TOTAL_BYTES }
    ]);
  }

  return accepted;
};

/**
 * Record feedback from any screen.
 *
 * Signed-in submitters get a live identity, tenant, facility, subscription, and
 * access snapshot; anyone else is recorded as anonymous with page and
 * technical context only.
 *
 * Screenshots ride along as multipart files. They are validated before the
 * feedback is written and stored after it, so an image that the provider
 * rejects costs the reporter that image and never their words.
 *
 * @param {Object} data - Validated body: category, message, scope, context
 * @param {Object} context - Request context from the controller, with `files`
 * @returns {Promise<Object>} Receipt
 */
const submitFeedback = async (data = {}, context = {}) => {
  const clientContext = data.context && typeof data.context === 'object' ? data.context : {};
  const submitter = await resolveSubmitterSnapshot(context.user);
  const screenshots = validateSubmittedScreenshots(
    Array.isArray(context.files) ? context.files : [],
    Array.isArray(data.screenshots) ? data.screenshots : [],
    submitter.submitter_type === 'AUTHENTICATED'
  );
  const scopeScreens = resolveScopeScreens(data);

  const record = await feedbackRepository.createFeedback({
    category: data.category || 'GENERAL',
    message: String(data.message || '').trim(),
    scope: data.scope || 'SCREEN',
    ...submitter,
    route_path: sanitizeFeedbackLocation(clientContext.route_path, 512),
    route_name: truncateFeedbackText(clientContext.route_name, 120),
    page_url: sanitizeFeedbackLocation(clientContext.page_url, 2048),
    screen_title: truncateFeedbackText(clientContext.screen_title, 255),
    client_platform: truncateFeedbackText(clientContext.platform || context.platform, 40),
    device_type: resolveFeedbackDeviceType(clientContext),
    viewport_width: toFeedbackPixelCount(clientContext.viewport?.width),
    viewport_height: toFeedbackPixelCount(clientContext.viewport?.height),
    screen_width: toFeedbackPixelCount(clientContext.screen?.width),
    screen_height: toFeedbackPixelCount(clientContext.screen?.height),
    app_version: truncateFeedbackText(clientContext.app_version, 64),
    app_environment: truncateFeedbackText(clientContext.app_environment, 40),
    locale: truncateFeedbackText(clientContext.locale || context.locale, 35),
    timezone: truncateFeedbackText(clientContext.timezone || context.timezone, 64),
    user_agent: truncateFeedbackText(context.user_agent, 512),
    ip_address: truncateFeedbackText(context.ip_address, 45),
    client_context_json: buildFeedbackClientContextJson(clientContext),
    client_submitted_at: parseOptionalDate(clientContext.client_submitted_at),
    scope_screens: scopeScreens
  });

  const { stored } = await storeFeedbackScreenshots({
    feedbackId: record.id,
    screenshots
  });
  let recordedScreenshots = 0;
  if (stored.length > 0) {
    try {
      recordedScreenshots = await feedbackRepository.createFeedbackScreenshots(record.id, stored);
    } catch (error) {
      // The images are stored but unrecorded; nothing can reach them, so take
      // them back out rather than leave objects no row points at.
      logger.error('Feedback screenshots could not be recorded', {
        feedback_id: record.id,
        error: error?.message
      });
      await deleteFeedbackScreenshotObjects(stored.map((image) => image.storage_key));
    }
  }

  // audit_log is tenant-scoped, so an anonymous row is its own evidence.
  if (record.tenant_id) {
    createAuditLog({
      user_id: submitter.user_id,
      tenant_id: record.tenant_id,
      action: 'CREATE',
      entity: 'feedback',
      entity_id: record.id,
      diff: {
        after: {
          human_friendly_id: record.human_friendly_id,
          category: record.category,
          submitter_type: record.submitter_type,
          scope: record.scope,
          screenshot_count: recordedScreenshots
        }
      },
      ip_address: context.ip_address
    }).catch(() => {});
  }

  return {
    human_friendly_id: record.human_friendly_id,
    category: record.category,
    scope: record.scope,
    submitter_type: record.submitter_type,
    submitted_at: record.submitted_at,
    screenshot_count: recordedScreenshots,
    // What the reporter sent that did not make it — a provider that refused
    // the image, or a row that could not be written — so the app can say so
    // instead of pretending every shot arrived.
    screenshots_dropped: Math.max(0, screenshots.length - recordedScreenshots)
  };
};

// Routes already require these roles; the service re-checks so no other caller
// can reach cross-tenant feedback.
const ensureFeedbackAdmin = (context = {}) => {
  if (!hasFeedbackAdminRole(context.user)) {
    throw new HttpError('errors.auth.insufficient_permissions', 403);
  }
};

// Upper-cased, de-duplicated feedback ids, or null when none were supplied.
const normalizeFeedbackIds = (values) => {
  if (!Array.isArray(values)) {
    return null;
  }
  const ids = Array.from(
    new Set(values.map((id) => String(id || '').trim().toUpperCase()).filter(Boolean))
  );
  return ids.length > 0 ? ids : null;
};

// Newest first by default; submission time and id break ties so paging is stable.
const buildFeedbackOrderBy = (sortBy, order) => {
  const direction = order === 'asc' ? 'asc' : 'desc';
  if (!FEEDBACK_SORTABLE_FIELDS.has(sortBy) || sortBy === 'submitted_at') {
    return [{ submitted_at: sortBy === 'submitted_at' ? direction : 'desc' }, { id: 'desc' }];
  }
  return [{ [sortBy]: direction }, { submitted_at: 'desc' }, { id: 'desc' }];
};

const toFeedbackListItem = (row) => ({
  human_friendly_id: row.human_friendly_id,
  submitted_at: row.submitted_at,
  category: row.category,
  scope: row.scope,
  // The screens a "selected screens" report named, so a reviewer sees what it
  // covers without opening the record.
  scope_screens: (row.scope_screens || []).map((screen) => ({
    route_name: screen.route_name,
    route_path: screen.route_path,
    screen_title: screen.screen_title
  })),
  screenshot_count: row._count?.screenshots || 0,
  submitter_type: row.submitter_type,
  message_preview: truncateFeedbackText(row.message, FEEDBACK_MESSAGE_PREVIEW_LENGTH),
  user_email: row.user_email || null,
  user_name: row.user_name || null,
  tenant_name: row.tenant_name || null,
  facility_name: row.facility_name || null,
  route_path: row.route_path || null,
  device_type: row.device_type || null,
  client_platform: row.client_platform || null
});

/**
 * One page of stored feedback for review and deletion.
 *
 * @param {Object} query - Validated page, limit, sort_by, order, and filters
 * @param {Object} context - Request context
 * @returns {Promise<{ items: Object[], pagination: Object }>}
 */
const listFeedback = async (query = {}, context = {}) => {
  ensureFeedbackAdmin(context);

  const { page: requestedPage, limit: requestedLimit, sort_by: sortBy, order, ...filters } = query;
  const page = Number.isInteger(requestedPage) && requestedPage > 0 ? requestedPage : 1;
  const limit =
    Number.isInteger(requestedLimit) && requestedLimit > 0
      ? requestedLimit
      : FEEDBACK_LIST_DEFAULT_LIMIT;

  const { rows, total } = await feedbackRepository.listActiveFeedbackPage({
    filters,
    skip: (page - 1) * limit,
    take: limit,
    orderBy: buildFeedbackOrderBy(sortBy, order)
  });

  return {
    items: rows.map(toFeedbackListItem),
    pagination: {
      page,
      limit,
      total,
      totalPages: Math.ceil(total / limit),
      hasNextPage: page * limit < total,
      hasPreviousPage: page > 1
    }
  };
};

/**
 * @param {Object} filters - Validated feedback filters
 * @param {Object} context - Request context
 * @returns {Promise<Object>} total, authenticated, anonymous, latest_submitted_at
 */
const getFeedbackSummary = async (filters = {}, context = {}) => {
  ensureFeedbackAdmin(context);

  const summary = await feedbackRepository.summarizeActiveFeedback(filters);
  return {
    total: summary.total,
    authenticated: Math.max(0, summary.total - summary.anonymous),
    anonymous: summary.anonymous,
    latest_submitted_at: summary.latest_submitted_at
  };
};

/**
 * Distinct values and record counts for every feedback filter, so "Download
 * feedback" and "Clear feedback" offer only values that exist. Each dimension
 * is counted under every other active filter but its own.
 *
 * @param {Object} filters - Validated feedback filters
 * @param {Object} context - Request context
 * @returns {Promise<{ total: number, facets: Object<string, Object[]> }>}
 */
const getFeedbackFacets = async (filters = {}, context = {}) => {
  ensureFeedbackAdmin(context);

  return feedbackRepository.summarizeFeedbackFacets(filters);
};

/**
 * Build the download archive: the workbook, the screenshots it describes, and
 * the prompts generator that turns the lot into implementation prompts.
 *
 * The archive is returned as a stream. Each image is read from storage only
 * as it is appended, so a download of every record never holds every image in
 * memory at once.
 *
 * @param {Object} query - Filters plus utc_offset_minutes and optional human_friendly_ids
 * @param {Object} context - Request context (timezone header, user)
 * @returns {Promise<Object>} stream, file_name, mime_type, record_count, image_count
 */
const exportFeedback = async (query = {}, context = {}) => {
  ensureFeedbackAdmin(context);

  const {
    utc_offset_minutes: utcOffsetMinutes,
    human_friendly_ids: requestedIds,
    ...filters
  } = query;
  // "Download feedback" picks records by id; without a pick the filters decide.
  const humanFriendlyIds = normalizeFeedbackIds(requestedIds);
  const rows = await feedbackRepository.listActiveFeedbackForExport(filters, {
    humanFriendlyIds
  });
  const generatedAt = new Date();
  const clock = resolveExportClock({ timeZone: context.timezone, utcOffsetMinutes });
  const workbookBuffer = await renderFeedbackWorkbook({
    rows,
    clock,
    generatedAt,
    generatedBy: truncateFeedbackText(context.user?.email, 255),
    filters
  });
  const screenshots = listFeedbackExportScreenshots(rows);
  const stream = streamFeedbackArchive({
    workbookFileName: buildFeedbackExportFileName(generatedAt, clock),
    workbookBuffer,
    screenshots,
    readScreenshot: (storageKey) => readFeedbackScreenshot(storageKey)
  });

  createAuditLog({
    user_id: context.user_id,
    tenant_id: context.tenant_id,
    action: 'EXPORT',
    entity: 'feedback',
    entity_id: randomUUID(),
    diff: {
      after: {
        record_count: rows.length,
        image_count: screenshots.length,
        human_friendly_ids: humanFriendlyIds
          ? humanFriendlyIds.slice(0, FEEDBACK_AUDIT_ID_SAMPLE)
          : null,
        filters
      }
    },
    ip_address: context.ip_address
  }).catch(() => {});

  return {
    stream,
    file_name: buildFeedbackArchiveFileName(generatedAt, clock),
    mime_type: FEEDBACK_ARCHIVE_MIME_TYPE,
    record_count: rows.length,
    image_count: screenshots.length
  };
};

/**
 * The screenshots of one record, for review in the app.
 *
 * Metadata only: the images themselves are fetched one at a time through
 * `getFeedbackScreenshotImage`, which is what keeps them off any public path.
 *
 * @param {string} humanFriendlyId - Public feedback id
 * @param {Object} context - Request context
 * @returns {Promise<{ human_friendly_id: string, items: Object[] }>}
 */
const listFeedbackScreenshots = async (humanFriendlyId, context = {}) => {
  ensureFeedbackAdmin(context);

  const record = await feedbackRepository.findFeedbackWithScreenshots(humanFriendlyId);
  if (!record) {
    throw new HttpError('errors.resource.not_found', 404);
  }

  return {
    human_friendly_id: record.human_friendly_id,
    items: record.screenshots.map((screenshot, index) => ({
      id: screenshot.id,
      sequence: screenshot.sequence || index + 1,
      content_type: screenshot.content_type,
      byte_size: screenshot.byte_size,
      width: screenshot.width,
      height: screenshot.height,
      caption: screenshot.caption,
      route_path: screenshot.route_path,
      route_name: screenshot.route_name,
      screen_title: screenshot.screen_title,
      // The window the shot was taken in: orientation, theme and size as
      // they were then, which the feedback's own context may not match.
      client_context: screenshot.client_context_json || null,
      captured_at: screenshot.captured_at,
      file_name: buildFeedbackScreenshotFileName({
        referenceId: record.human_friendly_id,
        position: index + 1,
        contentType: screenshot.content_type
      })
    }))
  };
};

/**
 * One screenshot's bytes, for a platform owner or admin to look at.
 *
 * Every read is audited: these images can show patient data.
 *
 * @param {string} humanFriendlyId - Public feedback id
 * @param {string} screenshotId
 * @param {Object} context - Request context
 * @returns {Promise<{ buffer: Buffer, mime_type: string, file_name: string }>}
 */
const getFeedbackScreenshotImage = async (humanFriendlyId, screenshotId, context = {}) => {
  ensureFeedbackAdmin(context);

  const screenshot = await feedbackRepository.findFeedbackScreenshot(
    humanFriendlyId,
    screenshotId
  );
  if (!screenshot) {
    throw new HttpError('errors.resource.not_found', 404);
  }

  const buffer = await readFeedbackScreenshot(screenshot.storage_key);
  if (!buffer) {
    throw new HttpError('errors.resource.not_found', 404);
  }

  createAuditLog({
    user_id: context.user_id,
    tenant_id: context.tenant_id,
    action: 'VIEW',
    entity: 'feedback_screenshot',
    entity_id: screenshot.id,
    diff: {
      after: {
        human_friendly_id: String(humanFriendlyId || '').trim().toUpperCase(),
        sequence: screenshot.sequence
      }
    },
    ip_address: context.ip_address
  }).catch(() => {});

  return {
    buffer,
    mime_type: screenshot.content_type,
    file_name: buildFeedbackScreenshotFileName({
      referenceId: String(humanFriendlyId || '').trim().toUpperCase(),
      position: screenshot.sequence || 1,
      contentType: screenshot.content_type
    })
  };
};

/**
 * Permanently delete feedback chosen in "Clear feedback": the listed ids, or
 * every record matching the filters when `all_matching` is set.
 *
 * @param {Object} body - Validated body: confirm, human_friendly_ids | all_matching + filters
 * @param {Object} context - Request context
 * @returns {Promise<Object>} deleted_count, deleted_at
 */
const deleteFeedback = async (body = {}, context = {}) => {
  ensureFeedbackAdmin(context);

  const humanFriendlyIds = normalizeFeedbackIds(body.human_friendly_ids) || [];
  const deletesAllMatching = body.all_matching === true;
  if (humanFriendlyIds.length === 0 && !deletesAllMatching) {
    throw new HttpError('errors.validation.invalid', 400, [{ field: 'human_friendly_ids' }]);
  }

  const filters = deletesAllMatching ? body.filters || {} : null;
  const deletedAt = new Date();
  const { count: deletedCount, storage_keys: storageKeys } =
    await feedbackRepository.deleteFeedbackPermanently(
      deletesAllMatching ? { filters } : { humanFriendlyIds }
    );
  // The rows are gone and nothing points at their images any more, so the
  // images go too. A key that is already absent counts as deleted, which
  // makes a repeat of this call safe.
  const { deleted: deletedImages, failed: failedImages } =
    await deleteFeedbackScreenshotObjects(storageKeys);
  if (failedImages.length > 0) {
    logger.error('Feedback images outlived their records', {
      count: failedImages.length,
      storage_keys: failedImages.slice(0, FEEDBACK_AUDIT_ID_SAMPLE)
    });
  }

  createAuditLog({
    user_id: context.user_id,
    tenant_id: context.tenant_id,
    action: 'DELETE',
    entity: 'feedback',
    entity_id: randomUUID(),
    diff: {
      before: {
        human_friendly_ids: deletesAllMatching
          ? null
          : humanFriendlyIds.slice(0, FEEDBACK_AUDIT_ID_SAMPLE),
        filters,
        matched: deletedCount,
        images: storageKeys.length
      },
      after: {
        deleted_permanently: true,
        deleted_at: deletedAt.toISOString(),
        deleted_images: deletedImages,
        orphaned_images: failedImages.length
      }
    },
    ip_address: context.ip_address
  }).catch(() => {});

  return {
    deleted_count: deletedCount,
    deleted_at: deletedAt,
    // Records, not files: the admin picked records, and that is what the app
    // reports back.
    deleted_screenshot_count: deletedImages
  };
};

module.exports = {
  deleteFeedback,
  exportFeedback,
  getFeedbackFacets,
  getFeedbackScreenshotImage,
  getFeedbackSummary,
  listFeedback,
  listFeedbackScreenshots,
  submitCsatFeedback,
  submitFeedback,
  submitNpsFeedback
};
