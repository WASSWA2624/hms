/**
 * Facility service
 *
 * @module modules/facility/services
 * @description Business logic for facility operations.
 * Per module-creation.mdc: Services contain business logic and call repositories.
 * Per module-creation.mdc: All mutations must call createAuditLog.
 */

const facilityRepository = require('@repositories/facility/facility.repository');
const { createAuditLog } = require('@lib/audit');
const { HttpError } = require('@lib/errors');
const { resolveEntityId, resolvePublicIdentifier } = require('@lib/billing/identifiers');
const {
  resolveModelIdByIdentifier,
  resolveModelRecordByIdentifier
} = require('@lib/identifiers/resolve-entity-id');
const { DEFAULT_PAGE, DEFAULT_PAGE_LIMIT, MAX_PAGE_LIMIT } = require('@config/constants');
const { publishCrudRealtimeEvent } = require('@lib/websocket/crud-realtime');
const { PLATFORM_ADMIN_EVENTS } = require('@lib/websocket/events');
const { ROLES } = require('@config/roles');
const {
  publishPlatformRealtimeEvent,
  buildFacilityDashboardDeltas
} = require('@lib/realtime/platform-realtime');
const { createStorageService } = require('@lib/storage');
const {
  deleteFacilityLogoFromStorage
} = require('@lib/storage/facility-logo-storage');
const {
  buildCandidateSnapshot,
  checkFacilityDuplicates
} = require('@lib/facility/facility-similarity');
const {
  pickFacilityOwnContact,
  resolveEffectiveFacilityContact
} = require('@lib/facility/effective-facility-contact');

const FACILITY_CONTACT_INCLUDE = Object.freeze({
  contacts: {
    where: { deleted_at: null }
  },
  addresses: {
    where: { deleted_at: null }
  }
});

const FACILITY_REALTIME_RECIPIENT_ROLES = Object.freeze([
  ROLES.FACILITY_ADMIN,
  ROLES.TENANT_ADMIN
]);

const FACILITY_SIMILARITY_LOOKUP_LIMIT = 100;

const SIMILARITY_CONTACT_KEYS = Object.freeze([
  'phone',
  'email',
  'address_line1',
  'city',
  'country',
  'confirm_similar'
]);

const extractFacilitySimilarityInput = (data = {}) => ({
  name: data.name,
  facilityType: data.facility_type,
  isActive: data.is_active,
  phone: data.phone,
  email: data.email,
  addressLine1: data.address_line1,
  city: data.city,
  country: data.country
});

const stripSimilarityPayloadFields = (data = {}) => {
  const payload = { ...data };
  for (const key of SIMILARITY_CONTACT_KEYS) {
    delete payload[key];
  }
  return payload;
};

const assertFacilityUniqueness = async ({
  data,
  tenantId,
  confirmSimilar = false,
  excludeFacilityId = null
}) => {
  const existing = await facilityRepository.findMany(
    { tenant_id: tenantId },
    0,
    FACILITY_SIMILARITY_LOOKUP_LIMIT,
    { name: 'asc' },
    {
      contacts: {
        where: { deleted_at: null }
      },
      addresses: {
        where: { deleted_at: null }
      }
    }
  );
  const input = extractFacilitySimilarityInput(data);
  const duplicateCheck = checkFacilityDuplicates({
    ...input,
    existing,
    excludeFacilityId
  });

  if (duplicateCheck.exactNameConflict) {
    throw new HttpError('errors.facility.duplicate_name', 409, [
      {
        field: 'name',
        matches: duplicateCheck.similarMatches
          .filter((match) => match.exactNameConflict)
          .slice(0, 5)
      }
    ]);
  }

  const reviewMatches = duplicateCheck.overridableMatches.slice(0, 5);
  if (reviewMatches.length > 0 && !confirmSimilar) {
    throw new HttpError('errors.facility.similar_exists', 409, [
      {
        field: 'name',
        matches: reviewMatches
      }
    ]);
  }

  return duplicateCheck;
};

const publishFacilityRealtimeEvent = async (
  event,
  facility,
  actorUserId,
  operation = 'create'
) => {
  await Promise.all([
    publishCrudRealtimeEvent({
      event,
      resource: facility,
      resource_type: 'facility',
      actor_user_id: actorUserId,
      recipient_roles: FACILITY_REALTIME_RECIPIENT_ROLES,
      payload: {
        is_active: facility?.is_active !== false,
        name: facility?.name || null
      }
    }),
    publishPlatformRealtimeEvent({
      event,
      resource_type: 'facility',
      resource_id: facility?.id || null,
      actor_user_id: actorUserId,
      tenant_id: facility?.tenant_id || null,
      facility_id: facility?.id || null,
      dashboard_deltas: buildFacilityDashboardDeltas(facility, operation),
      payload: {
        is_active: facility?.is_active !== false,
        name: facility?.name || null
      }
    })
  ]);
};

const resolveTenantId = async (identifier) =>
  resolveEntityId({ model: 'tenant', identifier });

const resolveFacilityId = async (identifier, { includeDeleted = false } = {}) => {
  const normalized = String(identifier ?? '').trim();
  if (!normalized) {
    return normalized;
  }

  if (includeDeleted) {
    const resolved = await resolveModelIdByIdentifier({
      model: 'facility',
      identifier: normalized,
      includeDeleted: true
    });
    return resolved || normalized;
  }

  return resolveEntityId({ model: 'facility', identifier: normalized });
};

/**
 * @param {Object} facility - Facility row
 * @param {Map<string, Object>|null} [tenantsById] - Tenants for contact
 *   inheritance; `effective_contact` is added only when the row's own contacts
 *   were loaded and this map is given
 * @returns {Object} Facility payload
 */
const normalizeFacilityRecord = (facility, tenantsById = null) => {
  if (!facility || typeof facility !== 'object') {
    return facility;
  }

  return {
    ...facility,
    resource_uuid: facility.id,
    display_id: resolvePublicIdentifier(facility.human_friendly_id) || null,
    ...(tenantsById && Array.isArray(facility.contacts)
      ? {
          effective_contact: resolveEffectiveFacilityContact(
            pickFacilityOwnContact(facility.contacts),
            tenantsById.get(facility.tenant_id) || null
          )
        }
      : {})
  };
};

/**
 * Tenants for the given facility rows, keyed by id, in a single query.
 *
 * @param {Array<Object>} facilities - Facility rows
 * @returns {Promise<Map<string, Object>>} Tenants by id
 */
const loadContactTenants = async (facilities = []) => {
  const tenants = await facilityRepository.findTenantContactSources(
    facilities.map((facility) => facility?.tenant_id)
  );
  return new Map((tenants || []).map((tenant) => [tenant.id, tenant]));
};

const toPositiveInt = (value, fallback, max = Number.POSITIVE_INFINITY) => {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  const normalized = Math.trunc(parsed);
  if (normalized <= 0) return fallback;
  return Math.min(normalized, max);
};

const normalizeSortOrder = (value) => {
  const normalized = String(value || 'desc').toLowerCase();
  return normalized === 'asc' ? 'asc' : 'desc';
};

/**
 * List facilities with pagination and filters
 *
 * @param {Object} filters - Filter criteria
 * @param {string} [filters.tenant_id] - Filter by tenant ID
 * @param {string} [filters.facility_type] - Filter by facility type
 * @param {boolean} [filters.is_active] - Filter by active status
 * @param {string} [filters.search] - Search by name, contact, or location
 * @param {string} [filters.phone] - Filter by contact phone
 * @param {string} [filters.email] - Filter by contact email
 * @param {string} [filters.city] - Filter by address city
 * @param {string} [filters.country] - Filter by address country
 * @param {number} page - Page number
 * @param {number} limit - Items per page
 * @param {string} [sort_by] - Field to sort by
 * @param {string} [order] - Sort order (asc/desc)
 * @returns {Promise<Object>} Paginated facilities
 */
const listFacilities = async (filters = {}, page = 1, limit = 20, sort_by = 'created_at', order = 'desc') => {
  const resolvedPage = toPositiveInt(page, DEFAULT_PAGE);
  const resolvedLimit = toPositiveInt(limit, DEFAULT_PAGE_LIMIT, MAX_PAGE_LIMIT);
  const resolvedSortBy = typeof sort_by === 'string' && sort_by.trim()
    ? sort_by.trim()
    : 'created_at';
  const resolvedOrder = normalizeSortOrder(order);
  const includeDeleted =
    filters.include_deleted === true || filters.include_deleted === 'true';

  // Build repository filters
  const repoFilters = {};
  const andConditions = [];

  if (filters.id) {
    repoFilters.id = filters.id;
  }

  if (filters.tenant_id) {
    repoFilters.tenant_id = await resolveTenantId(filters.tenant_id);
  }

  if (filters.facility_type) {
    repoFilters.facility_type = filters.facility_type;
  }

  if (filters.is_active !== undefined) {
    repoFilters.is_active = filters.is_active === true || filters.is_active === 'true';
  }

  const searchTerm =
    typeof filters.search === 'string' ? filters.search.trim() : '';
  if (searchTerm) {
    andConditions.push({
      OR: [
        { name: { contains: searchTerm } },
        {
          contacts: {
            some: {
              value: { contains: searchTerm },
              deleted_at: null
            }
          }
        },
        {
          addresses: {
            some: {
              deleted_at: null,
              OR: [
                { line1: { contains: searchTerm } },
                { city: { contains: searchTerm } },
                { country: { contains: searchTerm } }
              ]
            }
          }
        }
      ]
    });
  }

  const phoneTerm =
    typeof filters.phone === 'string' ? filters.phone.trim() : '';
  if (phoneTerm) {
    andConditions.push({
      contacts: {
        some: {
          contact_type: 'PHONE',
          value: { contains: phoneTerm },
          deleted_at: null
        }
      }
    });
  }

  const emailTerm =
    typeof filters.email === 'string' ? filters.email.trim() : '';
  if (emailTerm) {
    andConditions.push({
      contacts: {
        some: {
          contact_type: 'EMAIL',
          value: { contains: emailTerm },
          deleted_at: null
        }
      }
    });
  }

  const cityTerm = typeof filters.city === 'string' ? filters.city.trim() : '';
  if (cityTerm) {
    andConditions.push({
      addresses: {
        some: {
          city: { contains: cityTerm },
          deleted_at: null
        }
      }
    });
  }

  const countryTerm =
    typeof filters.country === 'string' ? filters.country.trim() : '';
  if (countryTerm) {
    andConditions.push({
      addresses: {
        some: {
          country: { contains: countryTerm },
          deleted_at: null
        }
      }
    });
  }

  if (andConditions.length === 1) {
    Object.assign(repoFilters, andConditions[0]);
  } else if (andConditions.length > 1) {
    repoFilters.AND = andConditions;
  }

  // Calculate pagination
  const skip = (resolvedPage - 1) * resolvedLimit;

  // Build sort order
  const orderBy = includeDeleted
    ? [
        { deleted_at: 'asc' },
        { [resolvedSortBy]: resolvedOrder },
      ]
    : { [resolvedSortBy]: resolvedOrder };

  const listOptions = { includeDeleted };

  // Fetch facilities and count (include contacts/addresses for list columns)
  const [facilities, total] = await Promise.all([
    facilityRepository.findMany(
      repoFilters,
      skip,
      resolvedLimit,
      orderBy,
      FACILITY_CONTACT_INCLUDE,
      listOptions
    ),
    facilityRepository.count(repoFilters, listOptions)
  ]);
  const tenantsById = await loadContactTenants(facilities);

  // Calculate pagination metadata
  const totalPages = Math.ceil(total / resolvedLimit);
  const hasNextPage = resolvedPage < totalPages;
  const hasPreviousPage = resolvedPage > 1;

  return {
    facilities: facilities.map((facility) =>
      normalizeFacilityRecord(facility, tenantsById)
    ),
    pagination: {
      page: resolvedPage,
      limit: resolvedLimit,
      total,
      totalPages,
      hasNextPage,
      hasPreviousPage
    }
  };
};

/**
 * Get facility by ID
 *
 * @param {string} id - Facility ID
 * @returns {Promise<Object>} Facility data
 */
const getFacilityById = async (id) => {
  const facilityId = await resolveFacilityId(id);
  const facility = await facilityRepository.findById(
    facilityId,
    FACILITY_CONTACT_INCLUDE
  );

  if (!facility) {
    throw new HttpError('errors.facility.not_found', 404);
  }

  return normalizeFacilityRecord(facility, await loadContactTenants([facility]));
};

/**
 * Create new facility
 *
 * @param {Object} data - Facility data
 * @param {string} data.tenant_id - Tenant ID
 * @param {string} data.name - Facility name
 * @param {string} data.facility_type - Facility type
 * @param {boolean} [data.is_active] - Active status
 * @param {Object} context - Request context for audit
 * @param {string} [context.user_id] - User ID performing the action
 * @param {string} [context.tenant_id] - Tenant ID
 * @param {string} [context.facility_id] - Facility ID
 * @param {string} [context.ip_address] - IP address
 * @param {string} [context.user_agent] - User agent
 * @returns {Promise<Object>} Created facility
 */
const createFacility = async (data, context = {}) => {
  const confirmSimilar = data?.confirm_similar === true;
  const similarityInput = extractFacilitySimilarityInput(data);
  const payload = {
    ...stripSimilarityPayloadFields(data),
    tenant_id: await resolveTenantId(data.tenant_id)
  };

  const duplicateCheck = await assertFacilityUniqueness({
    data: {
      ...similarityInput,
      name: payload.name,
      facility_type: payload.facility_type,
      is_active: payload.is_active
    },
    tenantId: payload.tenant_id,
    confirmSimilar
  });

  // Create facility
  const facility = await facilityRepository.create(payload);

  // Create audit log
  await createAuditLog({
    action: 'FACILITY_CREATED',
    entity: 'facility',
    entity_id: facility.id,
    user_id: context.user_id,
    tenant_id: context.tenant_id,
    facility_id: context.facility_id,
    ip_address: context.ip_address,
    user_agent: context.user_agent,
    details: {
      tenant_id: facility.tenant_id,
      name: facility.name,
      facility_type: facility.facility_type,
      is_active: facility.is_active,
      confirm_similar: confirmSimilar,
      similar_match_ids: confirmSimilar
        ? duplicateCheck.overridableMatches
            .slice(0, 5)
            .map((match) => match.id)
            .filter(Boolean)
        : []
    }
  });

  await publishFacilityRealtimeEvent(
    PLATFORM_ADMIN_EVENTS.FACILITY_CREATED,
    facility,
    context.user_id,
    'create'
  );

  return normalizeFacilityRecord(facility);
};

/**
 * Update facility
 *
 * @param {string} id - Facility ID
 * @param {Object} data - Update data
 * @param {string} [data.name] - Facility name
 * @param {string} [data.facility_type] - Facility type
 * @param {boolean} [data.is_active] - Active status
 * @param {Object} context - Request context for audit
 * @param {string} [context.user_id] - User ID performing the action
 * @param {string} [context.tenant_id] - Tenant ID
 * @param {string} [context.facility_id] - Facility ID
 * @param {string} [context.ip_address] - IP address
 * @param {string} [context.user_agent] - User agent
 * @returns {Promise<Object>} Updated facility
 */
const updateFacility = async (id, data, context = {}) => {
  const facilityId = await resolveFacilityId(id);
  // Check if facility exists and get before state
  const beforeFacility = await facilityRepository.findById(facilityId, {
    contacts: {
      where: { deleted_at: null }
    },
    addresses: {
      where: { deleted_at: null }
    }
  });

  if (!beforeFacility) {
    throw new HttpError('errors.facility.not_found', 404);
  }

  const confirmSimilar = data?.confirm_similar === true;
  const similarityInput = extractFacilitySimilarityInput(data);
  let payload = stripSimilarityPayloadFields(data);

  // Update facility
  if (payload.extension_json && typeof payload.extension_json === 'object') {
    const previousExtension =
      beforeFacility.extension_json && typeof beforeFacility.extension_json === 'object'
        ? beforeFacility.extension_json
        : {};
    const mergedExtension = {
      ...previousExtension,
      ...payload.extension_json
    };
    for (const [key, value] of Object.entries(mergedExtension)) {
      if (value === null || value === undefined) {
        delete mergedExtension[key];
      }
    }
    payload = {
      ...payload,
      extension_json: mergedExtension
    };
  }

  const beforeSnapshot = buildCandidateSnapshot(beforeFacility);
  const uniquenessData = {
    name: Object.prototype.hasOwnProperty.call(payload, 'name')
      ? payload.name
      : beforeFacility.name,
    facility_type: Object.prototype.hasOwnProperty.call(payload, 'facility_type')
      ? payload.facility_type
      : beforeFacility.facility_type,
    is_active: Object.prototype.hasOwnProperty.call(payload, 'is_active')
      ? payload.is_active
      : beforeFacility.is_active,
    phone:
      similarityInput.phone !== undefined
        ? similarityInput.phone
        : beforeSnapshot.phone,
    email:
      similarityInput.email !== undefined
        ? similarityInput.email
        : beforeSnapshot.email,
    address_line1:
      similarityInput.addressLine1 !== undefined
        ? similarityInput.addressLine1
        : beforeSnapshot.address_line1,
    city:
      similarityInput.city !== undefined
        ? similarityInput.city
        : beforeSnapshot.city,
    country:
      similarityInput.country !== undefined
        ? similarityInput.country
        : beforeSnapshot.country
  };

  const duplicateCheck = await assertFacilityUniqueness({
    data: uniquenessData,
    tenantId: beforeFacility.tenant_id,
    confirmSimilar,
    excludeFacilityId: facilityId
  });

  const facility = await facilityRepository.update(facilityId, payload);

  // Create audit log
  await createAuditLog({
    action: 'FACILITY_UPDATED',
    entity: 'facility',
    entity_id: facilityId,
    user_id: context.user_id,
    tenant_id: context.tenant_id,
    facility_id: context.facility_id,
    ip_address: context.ip_address,
    user_agent: context.user_agent,
    details: {
      before: {
        name: beforeFacility.name,
        facility_type: beforeFacility.facility_type,
        is_active: beforeFacility.is_active
      },
      after: {
        name: facility.name,
        facility_type: facility.facility_type,
        is_active: facility.is_active
      },
      confirm_similar: confirmSimilar,
      similar_match_ids: confirmSimilar
        ? duplicateCheck.overridableMatches
            .slice(0, 5)
            .map((match) => match.id)
            .filter(Boolean)
        : []
    }
  });

  await publishFacilityRealtimeEvent(
    PLATFORM_ADMIN_EVENTS.FACILITY_UPDATED,
    facility,
    context.user_id,
    'update'
  );

  return normalizeFacilityRecord(facility);
};

/**
 * Delete facility (soft delete)
 *
 * @param {string} id - Facility ID
 * @param {Object} context - Request context for audit
 * @param {string} [context.user_id] - User ID performing the action
 * @param {string} [context.tenant_id] - Tenant ID
 * @param {string} [context.facility_id] - Facility ID
 * @param {string} [context.ip_address] - IP address
 * @param {string} [context.user_agent] - User agent
 * @returns {Promise<void>}
 */
const deleteFacility = async (id, context = {}) => {
  const normalizedId = String(id ?? '').trim();
  const facilityId = await resolveFacilityId(normalizedId);
  const facility = await facilityRepository.findById(facilityId);

  if (!facility) {
    const lookupIds = [...new Set([facilityId, normalizedId].filter(Boolean))];
    for (const candidate of lookupIds) {
      const deletedFacility = await resolveModelRecordByIdentifier({
        model: 'facility',
        identifier: candidate,
        includeDeleted: true,
        select: { id: true, deleted_at: true }
      });
      if (deletedFacility?.deleted_at) {
        return;
      }
    }
    throw new HttpError('errors.facility.not_found', 404);
  }

  // Soft delete facility
  await facilityRepository.softDelete(facilityId);

  // Create audit log
  await createAuditLog({
    action: 'FACILITY_DELETED',
    entity: 'facility',
    entity_id: facilityId,
    user_id: context.user_id,
    tenant_id: context.tenant_id,
    facility_id: context.facility_id,
    ip_address: context.ip_address,
    user_agent: context.user_agent,
    details: {
      name: facility.name,
      facility_type: facility.facility_type
    }
  });

  await publishFacilityRealtimeEvent(
    PLATFORM_ADMIN_EVENTS.FACILITY_DELETED,
    facility,
    context.user_id,
    'delete'
  );
};

/**
 * Restore soft-deleted facility
 */
const restoreFacility = async (id, context = {}) => {
  const facilityId = await resolveFacilityId(id, { includeDeleted: true });
  const facility = await facilityRepository.restore(facilityId);

  await createAuditLog({
    action: 'FACILITY_RESTORED',
    entity: 'facility',
    entity_id: facilityId,
    user_id: context.user_id,
    tenant_id: context.tenant_id,
    facility_id: context.facility_id,
    ip_address: context.ip_address,
    user_agent: context.user_agent,
    details: {
      name: facility.name,
      facility_type: facility.facility_type,
      tenant_id: facility.tenant_id
    }
  });

  await publishFacilityRealtimeEvent(
    PLATFORM_ADMIN_EVENTS.FACILITY_RESTORED,
    facility,
    context.user_id,
    'create'
  );

  return normalizeFacilityRecord(facility);
};

/**
 * Permanently delete a soft-deleted facility and all related facility data.
 */
const permanentDeleteFacility = async (id, context = {}) => {
  const normalizedId = String(id ?? '').trim();
  const facilityId = await resolveFacilityId(normalizedId, { includeDeleted: true });
  const facility = await facilityRepository.findById(facilityId, { includeDeleted: true });

  if (!facility) {
    return;
  }
  if (!facility.deleted_at) {
    throw new HttpError('errors.facility.permanent_delete_requires_soft_delete', 400);
  }

  const extensionJson =
    facility.extension_json && typeof facility.extension_json === 'object'
      ? facility.extension_json
      : {};
  const logoUrl =
    typeof extensionJson.logo_url === 'string' ? extensionJson.logo_url : null;

  await createAuditLog({
    action: 'FACILITY_PERMANENTLY_DELETED',
    entity: 'facility',
    entity_id: facilityId,
    user_id: context.user_id,
    tenant_id: context.tenant_id,
    facility_id: context.facility_id,
    ip_address: context.ip_address,
    user_agent: context.user_agent,
    details: {
      name: facility.name,
      facility_type: facility.facility_type,
      tenant_id: facility.tenant_id,
      irreversible: true,
      logo_deleted: Boolean(logoUrl)
    }
  });

  // Remove logo file from storage before the DB row is purged.
  if (logoUrl) {
    const storage = createStorageService();
    await deleteFacilityLogoFromStorage(storage, logoUrl);
  }

  await facilityRepository.permanentDelete(facilityId);

  await publishPlatformRealtimeEvent({
    event: PLATFORM_ADMIN_EVENTS.FACILITY_PERMANENTLY_DELETED,
    resource_type: 'facility',
    resource_id: facilityId,
    actor_user_id: context.user_id || null,
    tenant_id: facility.tenant_id || null,
    facility_id: facilityId,
    payload: {
      name: facility.name,
      permanent: true
    }
  });
};

module.exports = {
  listFacilities,
  getFacilityById,
  createFacility,
  updateFacility,
  deleteFacility,
  restoreFacility,
  permanentDeleteFacility
};
