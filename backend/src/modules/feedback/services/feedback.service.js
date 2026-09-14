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
  FEEDBACK_EXPORT_MIME_TYPE,
  buildFeedbackExportFileName,
  renderFeedbackWorkbook,
  resolveExportClock
} = require('@lib/feedback/feedback-export');

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
  'facility_name'
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
 * Record feedback from any screen.
 *
 * Signed-in submitters get a live identity, tenant, facility, subscription, and
 * access snapshot; anyone else is recorded as anonymous with page and
 * technical context only.
 *
 * @param {Object} data - Validated body: category, message, context
 * @param {Object} context - Request context from the controller
 * @returns {Promise<Object>} Receipt
 */
const submitFeedback = async (data = {}, context = {}) => {
  const clientContext = data.context && typeof data.context === 'object' ? data.context : {};
  const submitter = await resolveSubmitterSnapshot(context.user);

  const record = await feedbackRepository.createFeedback({
    category: data.category || 'GENERAL',
    message: String(data.message || '').trim(),
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
    client_submitted_at: parseOptionalDate(clientContext.client_submitted_at)
  });

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
          submitter_type: record.submitter_type
        }
      },
      ip_address: context.ip_address
    }).catch(() => {});
  }

  return {
    human_friendly_id: record.human_friendly_id,
    category: record.category,
    submitter_type: record.submitter_type,
    submitted_at: record.submitted_at
  };
};

// Routes already require these roles; the service re-checks so no other caller
// can reach cross-tenant feedback.
const ensureFeedbackAdmin = (context = {}) => {
  if (!hasFeedbackAdminRole(context.user)) {
    throw new HttpError('errors.auth.insufficient_permissions', 403);
  }
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
 * Build the feedback workbook for download.
 *
 * @param {Object} query - Filters plus utc_offset_minutes
 * @param {Object} context - Request context (timezone header, user)
 * @returns {Promise<Object>} buffer, file_name, mime_type, record_count
 */
const exportFeedback = async (query = {}, context = {}) => {
  ensureFeedbackAdmin(context);

  const { utc_offset_minutes: utcOffsetMinutes, ...filters } = query;
  const rows = await feedbackRepository.listActiveFeedbackForExport(filters);
  const generatedAt = new Date();
  const clock = resolveExportClock({ timeZone: context.timezone, utcOffsetMinutes });
  const buffer = await renderFeedbackWorkbook({
    rows,
    clock,
    generatedAt,
    generatedBy: truncateFeedbackText(context.user?.email, 255),
    filters
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
        filters
      }
    },
    ip_address: context.ip_address
  }).catch(() => {});

  return {
    buffer,
    file_name: buildFeedbackExportFileName(generatedAt, clock),
    mime_type: FEEDBACK_EXPORT_MIME_TYPE,
    record_count: rows.length
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

  const humanFriendlyIds = Array.isArray(body.human_friendly_ids)
    ? Array.from(
        new Set(
          body.human_friendly_ids
            .map((id) => String(id || '').trim().toUpperCase())
            .filter(Boolean)
        )
      )
    : [];
  const deletesAllMatching = body.all_matching === true;
  if (humanFriendlyIds.length === 0 && !deletesAllMatching) {
    throw new HttpError('errors.validation.invalid', 400, [{ field: 'human_friendly_ids' }]);
  }

  const filters = deletesAllMatching ? body.filters || {} : null;
  const deletedAt = new Date();
  const deletedCount = await feedbackRepository.deleteFeedbackPermanently(
    deletesAllMatching ? { filters } : { humanFriendlyIds }
  );

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
        matched: deletedCount
      },
      after: {
        deleted_permanently: true,
        deleted_at: deletedAt.toISOString()
      }
    },
    ip_address: context.ip_address
  }).catch(() => {});

  return {
    deleted_count: deletedCount,
    deleted_at: deletedAt
  };
};

module.exports = {
  deleteFeedback,
  exportFeedback,
  getFeedbackSummary,
  listFeedback,
  submitCsatFeedback,
  submitFeedback,
  submitNpsFeedback
};
