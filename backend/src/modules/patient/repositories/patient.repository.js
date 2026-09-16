/**
 * Patient repository
 *
 * @module modules/patient/repositories
 * @description Data access layer for patient operations.
 * Per module-creation.mdc: Only standard CRUD operations allowed in repositories.
 * Per prisma.mdc: All queries use soft delete filtering (deleted_at: null).
 */

const prisma = require('@prisma/client');
const { HttpError } = require('@lib/errors');
const { notPurgedWhere, isPurgedPatient } = require('@lib/patient/purged-patient');

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const normalizeIdentifier = (value) =>
  typeof value === 'string' ? value.trim() : '';

const isUuid = (value) => UUID_REGEX.test(value);

const normalizeScopeValue = (value) =>
  typeof value === 'string' ? value.trim() : '';

const resolveScopeFilter = (value, relationName, foreignKeyName) => {
  const normalized = normalizeScopeValue(value);
  if (!normalized) return null;

  if (isUuid(normalized)) {
    return {
      type: 'uuid',
      value: normalized,
      where: { [foreignKeyName]: normalized }
    };
  }

  return {
    type: 'friendly_id',
    value: normalized.toUpperCase(),
    where: {
      [relationName]: {
        human_friendly_id: normalized.toUpperCase()
      }
    }
  };
};

const buildScopeState = (scope = {}) => {
  const tenantScope = resolveScopeFilter(scope.tenant_id, 'tenant', 'tenant_id');
  const facilityScope = resolveScopeFilter(scope.facility_id, 'facility', 'facility_id');

  return {
    tenantScope,
    facilityScope,
    primaryWhere: {
      ...(tenantScope?.where || {}),
      ...(facilityScope?.where || {})
    }
  };
};

const buildIdentifierFilter = (identifier) =>
  isUuid(identifier)
    ? { id: identifier }
    : { human_friendly_id: identifier.toUpperCase() };

// An empty include is sent as undefined, never as {}: Prisma treats the two
// differently, and internal callers here pass {} to mean "no relations".
const omitEmptyInclude = (include) =>
  include && Object.keys(include).length > 0 ? include : undefined;

/**
 * @param {'current'|'deleted'|'all'} recordState
 * @param {boolean} includeDeleted
 */
const resolveRecordState = ({ recordState, includeDeleted } = {}) => {
  if (recordState === 'current' || recordState === 'deleted' || recordState === 'all') {
    return recordState;
  }
  if (includeDeleted === true) return 'all';
  return 'current';
};

const applyRecordStateWhere = (where, recordState) => {
  const next = { ...where };
  const and = [];
  if (Array.isArray(next.AND)) {
    and.push(...next.AND);
  } else if (next.AND) {
    and.push(next.AND);
  }
  and.push(notPurgedWhere());

  if (recordState === 'current') {
    next.deleted_at = null;
  } else if (recordState === 'deleted') {
    next.deleted_at = { not: null };
  } else {
    // all: include soft-deleted, still exclude purged tombstones
    delete next.deleted_at;
  }

  next.AND = and;
  return next;
};

const findFirstByIdentifier = async (
  identifier,
  include,
  scopeFilters = {},
  dbClient = prisma,
  { includeDeleted = false, recordState } = {}
) => {
  const state = resolveRecordState({ includeDeleted, recordState });
  const where = applyRecordStateWhere(
    {
      ...scopeFilters,
      ...buildIdentifierFilter(identifier)
    },
    state
  );

  return dbClient.patient.findFirst({
    where,
    include: omitEmptyInclude(include)
  });
};

const resolveCanonicalPatientId = async (id, scope = {}, dbClient = prisma, options = {}) => {
  const existing = await findById(id, {}, scope, dbClient, options);
  return existing?.id || null;
};

/**
 * Find patient by ID
 *
 * @param {string} id - Patient ID
 * @param {Object} include - Relations to include
 * @param {Object} scope - Optional scope filters (tenant_id, facility_id)
 * @param {Object} [dbClient]
 * @param {Object} [options]
 * @param {boolean} [options.includeDeleted]
 * @param {'current'|'deleted'|'all'} [options.recordState]
 * @returns {Promise<Object|null>} Patient object or null
 */
const findById = async (
  id,
  include,
  scope = {},
  dbClient = prisma,
  options = {}
) => {
  try {
    const identifier = normalizeIdentifier(id);
    if (!identifier) return null;

    const scopeState = buildScopeState(scope);
    return await findFirstByIdentifier(
      identifier,
      include,
      scopeState.primaryWhere,
      dbClient,
      options
    );
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

const findByIdIncludingDeleted = async (id, include, scope = {}, dbClient = prisma) =>
  findById(id, include, scope, dbClient, { includeDeleted: true, recordState: 'all' });

/**
 * Find many patients with pagination
 *
 * @param {Object} filters - Filter criteria
 * @param {number} skip - Number of records to skip
 * @param {number} take - Number of records to take
 * @param {Object} orderBy - Sort order
 * @param {Object} include - Relations to include
 * @param {Object} [dbClient]
 * @param {Object} [options]
 * @returns {Promise<Array>} Array of patients
 */
const findMany = async (
  filters = {},
  skip = 0,
  take = 20,
  orderBy = { created_at: 'desc' },
  include,
  dbClient = prisma,
  options = {}
) => {
  try {
    const state = resolveRecordState(options);
    const where = applyRecordStateWhere({ ...filters }, state);

    return await dbClient.patient.findMany({
      where,
      skip,
      take,
      orderBy,
      include
    });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Count patients with filters
 *
 * @param {Object} filters - Filter criteria
 * @param {Object} [dbClient]
 * @param {Object} [options]
 * @returns {Promise<number>} Count of patients
 */
const count = async (filters = {}, dbClient = prisma, options = {}) => {
  try {
    const state = resolveRecordState(options);
    const where = applyRecordStateWhere({ ...filters }, state);

    return await dbClient.patient.count({ where });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Create new patient
 *
 * @param {Object} data - Patient data
 * @returns {Promise<Object>} Created patient
 */
const create = async (data, dbClient = prisma) => {
  try {
    return await dbClient.patient.create({
      data
    });
  } catch (error) {
    if (error.code === 'P2002') {
      // Unique constraint violation
      const target = error.meta?.target?.[0] || 'field';
      throw new HttpError('errors.database.unique_field', 409, [{ field: target }]);
    }
    if (error.code === 'P2003') {
      // Foreign key constraint violation
      const target = error.meta?.field_name || 'field';
      throw new HttpError('errors.database.foreign_key_field', 400, [{ field: target }]);
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Update patient
 *
 * @param {string} id - Patient ID
 * @param {Object} data - Update data
 * @param {Object} scope - Optional scope filters (tenant_id, facility_id)
 * @returns {Promise<Object>} Updated patient
 */
const update = async (id, data, scope = {}, dbClient = prisma) => {
  try {
    const canonicalId = await resolveCanonicalPatientId(id, scope, dbClient);
    if (!canonicalId) {
      throw new HttpError('errors.patient.not_found', 404);
    }

    return await dbClient.patient.update({
      where: { id: canonicalId },
      data
    });
  } catch (error) {
    if (error instanceof HttpError) {
      throw error;
    }
    if (error.code === 'P2025') {
      throw new HttpError('errors.patient.not_found', 404);
    }
    if (error.code === 'P2002') {
      // Unique constraint violation
      const target = error.meta?.target?.[0] || 'field';
      throw new HttpError('errors.database.unique_field', 409, [{ field: target }]);
    }
    if (error.code === 'P2003') {
      // Foreign key constraint violation
      const target = error.meta?.field_name || 'field';
      throw new HttpError('errors.database.foreign_key_field', 400, [{ field: target }]);
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Soft delete patient
 * Per prisma.mdc: Only soft deletes allowed
 *
 * @param {string} id - Patient ID
 * @param {Object} scope - Optional scope filters (tenant_id, facility_id)
 * @returns {Promise<Object>} Deleted patient
 */
const softDelete = async (id, scope = {}, dbClient = prisma) => {
  try {
    const canonicalId = await resolveCanonicalPatientId(id, scope, dbClient);
    if (!canonicalId) {
      throw new HttpError('errors.patient.not_found', 404);
    }

    return await dbClient.patient.update({
      where: { id: canonicalId },
      data: {
        deleted_at: new Date()
      }
    });
  } catch (error) {
    if (error instanceof HttpError) {
      throw error;
    }
    if (error.code === 'P2025') {
      throw new HttpError('errors.patient.not_found', 404);
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Clear soft-delete on a patient row (manifest-driven restore uses the deletion repo).
 */
const restore = async (id, scope = {}, dbClient = prisma) => {
  try {
    const existing = await findByIdIncludingDeleted(id, {}, scope, dbClient);
    if (!existing || !existing.deleted_at || isPurgedPatient(existing)) {
      throw new HttpError('errors.patient.not_found', 404);
    }

    return await dbClient.patient.update({
      where: { id: existing.id },
      data: { deleted_at: null }
    });
  } catch (error) {
    if (error instanceof HttpError) throw error;
    if (error.code === 'P2025') {
      throw new HttpError('errors.patient.not_found', 404);
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

const findRealtimeRecipientUserIds = async ({ tenantId, facilityId = null, roles = [], extraUserIds = [] }) => {
  try {
    const recipients = new Set(
      (Array.isArray(extraUserIds) ? extraUserIds : [])
        .map((value) => String(value || '').trim())
        .filter(Boolean)
    );

    if (!tenantId || !Array.isArray(roles) || roles.length === 0) {
      return Array.from(recipients);
    }

    const rows = await prisma.user_role.findMany({
      where: {
        deleted_at: null,
        tenant_id: tenantId,
        role: {
          name: { in: roles },
          deleted_at: null
        },
        ...(facilityId ? { OR: [{ facility_id: null }, { facility_id: facilityId }] } : {})
      },
      select: { user_id: true }
    });

    rows.forEach((item) => {
      if (item?.user_id) recipients.add(item.user_id);
    });

    return Array.from(recipients);
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

module.exports = {
  findById,
  findByIdIncludingDeleted,
  findMany,
  count,
  create,
  update,
  softDelete,
  restore,
  findRealtimeRecipientUserIds
};
