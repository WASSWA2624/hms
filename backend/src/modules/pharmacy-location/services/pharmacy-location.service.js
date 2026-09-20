/**
 * Pharmacy location service
 *
 * @module modules/pharmacy-location/services
 * @description Pharmacy locations, who may act in them, what they charge, and
 * what one pharmacy may see of another's availability.
 *
 * The structural rules this service enforces:
 *
 * * Only one pharmacy per facility may hold procurement, and it is the one
 *   other pharmacies order from.
 * * A pharmacy cannot be supplied by itself, nor by a pharmacy in another
 *   facility or tenant.
 * * `sell_price` and `supply_price` are written independently, so a walk-in
 *   price edit can never move a hospital supply price.
 * * Cross-pharmacy availability returns quantities only. Purchase cost and
 *   supplier terms stay with the pharmacy that owns them.
 */

const prisma = require('@prisma/client');
const { createAuditLog } = require('@lib/audit');
const { HttpError } = require('@lib/errors');
const pharmacyLocationRepository = require('@repositories/pharmacy-location/pharmacy-location.repository');
const {
  ACCESS_LEVELS,
  LOCATION_KINDS,
  PHARMACY_LOCATION_PUBLIC_SELECT,
  hasTenantWideAccess,
  findPharmacyLocation,
  requirePharmacyLocation,
  loadUserLocationGrants,
  assertLocationAccess,
  assertStockVisibility,
  toSupplierStockProjection,
} = require('@lib/pharmacy/pharmacy-location-access');
const {
  findLocationPrice,
  buildLocationPriceSnapshot,
  toDecimalString,
} = require('@lib/pharmacy/pharmacy-location-pricing');
const { loadStockMatrix } = require('@lib/pharmacy/pharmacy-location-stock');
const { resolveModelIdByIdentifier } = require('@lib/identifiers/resolve-entity-id');

const DEFAULT_PAGE_SIZE = 20;

const normalizeIdentifier = (value) => (typeof value === 'string' ? value.trim() : '');
const normalizeUpper = (value) => normalizeIdentifier(value).toUpperCase();

const resolveScope = (user = {}) => {
  const roles = Array.isArray(user?.roles) ? user.roles : [];
  const tenantId = normalizeIdentifier(user?.tenant_id) || null;
  const facilityId = normalizeIdentifier(user?.facility_id) || null;
  const canManageAllTenants = roles.includes('PLATFORM_ADMIN');

  if (!canManageAllTenants && !tenantId) {
    throw new HttpError('errors.auth.scope_mismatch', 403);
  }

  return { user, tenant_id: tenantId, facility_id: facilityId, can_manage_all_tenants: canManageAllTenants };
};

const buildScopeWhere = (scope) => ({
  ...(scope.can_manage_all_tenants ? {} : { tenant_id: scope.tenant_id }),
});

const toPublic = (location, { includeSupplier = true } = {}) => {
  if (!location) return null;
  const projection = Object.keys(PHARMACY_LOCATION_PUBLIC_SELECT).reduce((acc, field) => {
    acc[field] = location[field] ?? null;
    return acc;
  }, {});
  if (!includeSupplier) delete projection.supplied_by_location_id;
  return projection;
};

const paginate = (page, limit, total) => {
  const totalPages = Math.ceil(total / limit) || 0;
  return {
    page,
    limit,
    total,
    totalPages,
    hasNextPage: page < totalPages,
    hasPreviousPage: page > 1,
  };
};

/**
 * List pharmacy locations the caller may see.
 *
 * @param {Object} filters - Query filters
 * @param {Object} pagination - `{ page, limit }`
 * @param {Object} sort - `{ sort_by, order }`
 * @param {Object} user - Request user context
 * @returns {Promise<Object>} Paginated locations, annotated with the caller's grant
 */
const listPharmacyLocations = async (filters = {}, pagination = {}, sort = {}, user = {}) => {
  const scope = resolveScope(user);
  const page = Math.max(1, Number(pagination.page) || 1);
  const limit = Math.max(1, Number(pagination.limit) || DEFAULT_PAGE_SIZE);

  const where = buildScopeWhere(scope);

  if (filters.facility_id) {
    const facilityId = await resolveModelIdByIdentifier({
      model: 'facility',
      identifier: filters.facility_id,
    });
    where.facility_id = facilityId || filters.facility_id;
  } else if (!scope.can_manage_all_tenants && scope.facility_id) {
    where.facility_id = scope.facility_id;
  }

  if (filters.kind) where.kind = normalizeUpper(filters.kind);
  if (filters.is_active !== undefined) where.is_active = Boolean(filters.is_active);
  if (filters.handles_procurement !== undefined) {
    where.handles_procurement = Boolean(filters.handles_procurement);
  }
  if (filters.handles_walk_in !== undefined) where.handles_walk_in = Boolean(filters.handles_walk_in);
  if (filters.handles_prescriptions !== undefined) {
    where.handles_prescriptions = Boolean(filters.handles_prescriptions);
  }

  const search = normalizeIdentifier(filters.search);
  if (search) {
    where.OR = [
      { name: { contains: search } },
      { code: { contains: search.toUpperCase() } },
      { human_friendly_id: { contains: search.toUpperCase() } },
    ];
  }

  const grants = await loadUserLocationGrants(prisma, {
    userId: user?.id,
    tenantId: scope.tenant_id,
  });

  if (filters.mine_only && !hasTenantWideAccess(user)) {
    const ids = Array.from(grants.keys());
    where.id = { in: ids.length ? ids : ['__none__'] };
  }

  const orderBy = sort.sort_by
    ? { [sort.sort_by]: sort.order === 'asc' ? 'asc' : 'desc' }
    : [{ kind: 'asc' }, { is_default: 'desc' }, { name: 'asc' }];

  const [rows, total] = await Promise.all([
    pharmacyLocationRepository.findMany(where, (page - 1) * limit, limit, orderBy),
    pharmacyLocationRepository.count(where),
  ]);

  const data = rows.map((location) => {
    const grant = grants.get(String(location.id)) || null;
    return {
      ...toPublic(location),
      access_level: hasTenantWideAccess(user)
        ? ACCESS_LEVELS.MANAGE
        : grant?.access_level || null,
      can_view_supplier_stock: hasTenantWideAccess(user)
        ? true
        : Boolean(grant?.can_view_supplier_stock),
    };
  });

  return { data, ...paginate(page, limit, total) };
};

/**
 * Get one pharmacy location.
 *
 * @param {string} identifier - Location id, friendly id, code or kind
 * @param {Object} user - Request user context
 * @returns {Promise<Object>} Location with the caller's access level
 */
const getPharmacyLocation = async (identifier, user = {}) => {
  const scope = resolveScope(user);
  const location = await requirePharmacyLocation(prisma, identifier, {
    tenantId: scope.can_manage_all_tenants ? null : scope.tenant_id,
  });

  await assertLocationAccess(prisma, { location, user, level: ACCESS_LEVELS.VIEW }).catch(
    async (error) => {
      // A pharmacy may always read the one that supplies it, so a denied grant
      // is not final until the supply link has been checked too.
      const grants = await loadUserLocationGrants(prisma, {
        userId: user?.id,
        tenantId: scope.tenant_id,
      });
      const suppliesAGrantedLocation = await prisma.pharmacy_location.findFirst({
        where: {
          deleted_at: null,
          supplied_by_location_id: location.id,
          id: { in: Array.from(grants.keys()).length ? Array.from(grants.keys()) : ['__none__'] },
        },
      });
      if (!suppliesAGrantedLocation) throw error;
    }
  );

  const grant = await pharmacyLocationRepository.findAccessGrant(location.id, user?.id);
  return {
    ...toPublic(location),
    access_level: hasTenantWideAccess(user) ? ACCESS_LEVELS.MANAGE : grant?.access_level || null,
    can_view_supplier_stock: hasTenantWideAccess(user)
      ? true
      : Boolean(grant?.can_view_supplier_stock),
  };
};

/**
 * Validate the supply link between two pharmacies.
 *
 * @param {Object} params
 * @param {Object} params.location - Pharmacy being configured
 * @param {Object|null} params.supplier - Pharmacy it would be supplied by
 * @throws {HttpError} 400 when the link is self-referential or crosses facilities
 */
const assertSupplyLinkValid = ({ location, supplier }) => {
  if (!supplier) return;
  if (String(supplier.id) === String(location.id)) {
    throw new HttpError('errors.pharmacy_location.self_supply', 400, [
      { field: 'supplied_by_location_id' },
    ]);
  }
  if (String(supplier.facility_id) !== String(location.facility_id)) {
    throw new HttpError('errors.pharmacy_location.supplier_facility_mismatch', 400, [
      { field: 'supplied_by_location_id' },
    ]);
  }
  if (!supplier.is_active) {
    throw new HttpError('errors.pharmacy_location.supplier_inactive', 400, [
      { field: 'supplied_by_location_id' },
    ]);
  }
};

/**
 * Create a pharmacy location.
 *
 * @param {Object} payload - Location fields
 * @param {Object} user - Request user context
 * @param {string} [ipAddress] - Caller IP for the audit log
 * @returns {Promise<Object>} Created location
 */
const createPharmacyLocation = async (payload = {}, user = {}, ipAddress = null) => {
  const scope = resolveScope(user);

  const facilityId = await resolveModelIdByIdentifier({
    model: 'facility',
    identifier: payload.facility_id,
  });
  if (!facilityId) {
    throw new HttpError('errors.facility.not_found', 404, [{ field: 'facility_id' }]);
  }

  const facility = await prisma.facility.findFirst({
    where: { id: facilityId, deleted_at: null },
    select: { id: true, tenant_id: true },
  });
  if (!facility) {
    throw new HttpError('errors.facility.not_found', 404, [{ field: 'facility_id' }]);
  }
  if (!scope.can_manage_all_tenants && String(facility.tenant_id) !== String(scope.tenant_id)) {
    throw new HttpError('errors.auth.scope_mismatch', 403);
  }

  const kind = normalizeUpper(payload.kind) || LOCATION_KINDS.OTHER;
  const handlesProcurement = payload.handles_procurement ?? kind === LOCATION_KINDS.MAIN;

  // One procurement pharmacy per facility keeps purchasing, supplier terms and
  // landed cost in a single place.
  if (handlesProcurement) {
    const existing = await pharmacyLocationRepository.findMany(
      { facility_id: facilityId, handles_procurement: true },
      0,
      1
    );
    if (existing.length) {
      throw new HttpError('errors.pharmacy_location.procurement_already_assigned', 409, [
        { field: 'handles_procurement', pharmacy_location_id: existing[0].id },
      ]);
    }
  }

  let supplier = null;
  if (payload.supplied_by_location_id) {
    supplier = await requirePharmacyLocation(prisma, payload.supplied_by_location_id, {
      tenantId: facility.tenant_id,
    });
    assertSupplyLinkValid({ location: { id: null, facility_id: facilityId }, supplier });
  }

  const data = {
    tenant_id: facility.tenant_id,
    facility_id: facilityId,
    name: normalizeIdentifier(payload.name),
    code: payload.code ? normalizeUpper(payload.code) : null,
    kind,
    is_active: payload.is_active ?? true,
    is_default: payload.is_default ?? false,
    handles_procurement: handlesProcurement,
    handles_walk_in: payload.handles_walk_in ?? kind === LOCATION_KINDS.MAIN,
    handles_prescriptions: payload.handles_prescriptions ?? kind === LOCATION_KINDS.HOSPITAL,
    supplied_by_location_id: supplier?.id || null,
    currency: payload.currency ? normalizeUpper(payload.currency) : null,
  };

  const created = await pharmacyLocationRepository.create(data);

  if (created.is_default) {
    await pharmacyLocationRepository.clearDefaultForKind(facilityId, kind, created.id);
  }

  createAuditLog({
    tenant_id: created.tenant_id,
    user_id: user?.id,
    action: 'CREATE',
    entity: 'pharmacy_location',
    entity_id: created.id,
    diff: { after: created },
    ip_address: ipAddress,
  }).catch(() => {});

  return toPublic(created);
};

/**
 * Update a pharmacy location.
 *
 * @param {string} identifier - Location identifier
 * @param {Object} payload - Fields to change
 * @param {Object} user - Request user context
 * @param {string} [ipAddress] - Caller IP for the audit log
 * @returns {Promise<Object>} Updated location
 */
const updatePharmacyLocation = async (identifier, payload = {}, user = {}, ipAddress = null) => {
  const scope = resolveScope(user);
  const location = await requirePharmacyLocation(prisma, identifier, {
    tenantId: scope.can_manage_all_tenants ? null : scope.tenant_id,
  });
  await assertLocationAccess(prisma, { location, user, level: ACCESS_LEVELS.MANAGE });

  const data = {};
  if (payload.name !== undefined) data.name = normalizeIdentifier(payload.name);
  if (payload.code !== undefined) data.code = payload.code ? normalizeUpper(payload.code) : null;
  if (payload.kind !== undefined) data.kind = normalizeUpper(payload.kind);
  if (payload.is_active !== undefined) data.is_active = Boolean(payload.is_active);
  if (payload.is_default !== undefined) data.is_default = Boolean(payload.is_default);
  if (payload.handles_walk_in !== undefined) data.handles_walk_in = Boolean(payload.handles_walk_in);
  if (payload.handles_prescriptions !== undefined) {
    data.handles_prescriptions = Boolean(payload.handles_prescriptions);
  }
  if (payload.currency !== undefined) {
    data.currency = payload.currency ? normalizeUpper(payload.currency) : null;
  }

  if (payload.handles_procurement !== undefined) {
    const next = Boolean(payload.handles_procurement);
    if (next && !location.handles_procurement) {
      const existing = await pharmacyLocationRepository.findMany(
        { facility_id: location.facility_id, handles_procurement: true, id: { not: location.id } },
        0,
        1
      );
      if (existing.length) {
        throw new HttpError('errors.pharmacy_location.procurement_already_assigned', 409, [
          { field: 'handles_procurement', pharmacy_location_id: existing[0].id },
        ]);
      }
    }
    data.handles_procurement = next;
  }

  if (payload.supplied_by_location_id !== undefined) {
    if (!payload.supplied_by_location_id) {
      data.supplied_by_location_id = null;
    } else {
      const supplier = await requirePharmacyLocation(prisma, payload.supplied_by_location_id, {
        tenantId: location.tenant_id,
      });
      assertSupplyLinkValid({ location, supplier });
      data.supplied_by_location_id = supplier.id;
    }
  }

  const updated = await pharmacyLocationRepository.update(location.id, data);

  if (data.is_default) {
    await pharmacyLocationRepository.clearDefaultForKind(
      updated.facility_id,
      updated.kind,
      updated.id
    );
  }

  createAuditLog({
    tenant_id: updated.tenant_id,
    user_id: user?.id,
    action: 'UPDATE',
    entity: 'pharmacy_location',
    entity_id: updated.id,
    diff: { before: location, after: updated },
    ip_address: ipAddress,
  }).catch(() => {});

  return toPublic(updated);
};

/**
 * Soft-delete a pharmacy location.
 *
 * Refused while the location still holds stock, so a balance can never be
 * orphaned by removing the pharmacy that owns it.
 *
 * @param {string} identifier - Location identifier
 * @param {Object} user - Request user context
 * @param {string} [ipAddress] - Caller IP for the audit log
 * @returns {Promise<void>} Resolves when removed
 */
const deletePharmacyLocation = async (identifier, user = {}, ipAddress = null) => {
  const scope = resolveScope(user);
  const location = await requirePharmacyLocation(prisma, identifier, {
    tenantId: scope.can_manage_all_tenants ? null : scope.tenant_id,
  });
  await assertLocationAccess(prisma, { location, user, level: ACCESS_LEVELS.MANAGE });

  const heldStock = await prisma.inventory_stock.findFirst({
    where: { deleted_at: null, pharmacy_location_id: location.id, quantity: { gt: 0 } },
  });
  if (heldStock) {
    throw new HttpError('errors.pharmacy_location.has_stock', 409, [
      { pharmacy_location_id: location.id },
    ]);
  }

  const dependents = await prisma.pharmacy_location.findFirst({
    where: { deleted_at: null, supplied_by_location_id: location.id },
  });
  if (dependents) {
    throw new HttpError('errors.pharmacy_location.supplies_other_locations', 409, [
      { pharmacy_location_id: location.id, dependent_location_id: dependents.id },
    ]);
  }

  await pharmacyLocationRepository.softDelete(location.id);

  createAuditLog({
    tenant_id: location.tenant_id,
    user_id: user?.id,
    action: 'DELETE',
    entity: 'pharmacy_location',
    entity_id: location.id,
    diff: { before: location },
    ip_address: ipAddress,
  }).catch(() => {});
};

// ------------------------------------------------------------ access grants

/**
 * List who may act in a pharmacy location.
 *
 * @param {string} identifier - Location identifier
 * @param {Object} user - Request user context
 * @returns {Promise<Object[]>} Access grants with basic user details
 */
const listPharmacyLocationAccess = async (identifier, user = {}) => {
  const scope = resolveScope(user);
  const location = await requirePharmacyLocation(prisma, identifier, {
    tenantId: scope.can_manage_all_tenants ? null : scope.tenant_id,
  });
  await assertLocationAccess(prisma, { location, user, level: ACCESS_LEVELS.MANAGE });

  const grants = await pharmacyLocationRepository.findAccessGrants(
    { pharmacy_location_id: location.id },
    {
      user: {
        select: {
          id: true,
          human_friendly_id: true,
          email: true,
          profile: { select: { first_name: true, last_name: true } },
        },
      },
    }
  );

  return grants.map((grant) => ({
    id: grant.id,
    human_friendly_id: grant.human_friendly_id,
    pharmacy_location_id: grant.pharmacy_location_id,
    user_id: grant.user_id,
    user_display_id: grant.user?.human_friendly_id || null,
    user_email: grant.user?.email || null,
    user_display_name: [grant.user?.profile?.first_name, grant.user?.profile?.last_name]
      .filter(Boolean)
      .join(' ')
      .trim() || null,
    access_level: grant.access_level,
    can_view_supplier_stock: grant.can_view_supplier_stock,
    is_active: grant.is_active,
  }));
};

/**
 * Grant or change a user's access to a pharmacy location.
 *
 * @param {string} identifier - Location identifier
 * @param {Object} payload - `{ user_id, access_level, ... }`
 * @param {Object} user - Request user context
 * @param {string} [ipAddress] - Caller IP for the audit log
 * @returns {Promise<Object>} The grant
 */
const upsertPharmacyLocationAccess = async (
  identifier,
  payload = {},
  user = {},
  ipAddress = null
) => {
  const scope = resolveScope(user);
  const location = await requirePharmacyLocation(prisma, identifier, {
    tenantId: scope.can_manage_all_tenants ? null : scope.tenant_id,
  });
  await assertLocationAccess(prisma, { location, user, level: ACCESS_LEVELS.MANAGE });

  const targetUserId = await resolveModelIdByIdentifier({
    model: 'user',
    identifier: payload.user_id,
  });
  if (!targetUserId) {
    throw new HttpError('errors.user.not_found', 404, [{ field: 'user_id' }]);
  }

  const targetUser = await prisma.user.findFirst({
    where: { id: targetUserId, deleted_at: null },
    select: { id: true, tenant_id: true },
  });
  if (!targetUser) {
    throw new HttpError('errors.user.not_found', 404, [{ field: 'user_id' }]);
  }
  if (String(targetUser.tenant_id) !== String(location.tenant_id)) {
    throw new HttpError('errors.auth.scope_mismatch', 403, [{ field: 'user_id' }]);
  }

  const existing = await pharmacyLocationRepository.findAccessGrant(location.id, targetUserId);
  const data = {
    access_level: normalizeUpper(payload.access_level) || ACCESS_LEVELS.DISPENSE,
    can_view_supplier_stock: payload.can_view_supplier_stock ?? true,
    is_active: payload.is_active ?? true,
  };

  const grant = existing
    ? await pharmacyLocationRepository.updateAccessGrant(existing.id, {
        ...data,
        deleted_at: null,
      })
    : await pharmacyLocationRepository.createAccessGrant({
        tenant_id: location.tenant_id,
        pharmacy_location_id: location.id,
        user_id: targetUserId,
        ...data,
      });

  createAuditLog({
    tenant_id: location.tenant_id,
    user_id: user?.id,
    action: existing ? 'UPDATE' : 'CREATE',
    entity: 'pharmacy_location_user',
    entity_id: grant.id,
    diff: { before: existing || null, after: grant },
    ip_address: ipAddress,
  }).catch(() => {});

  return grant;
};

/**
 * Revoke a user's access to a pharmacy location.
 *
 * @param {string} identifier - Location identifier
 * @param {string} userIdentifier - User whose access is revoked
 * @param {Object} user - Request user context
 * @param {string} [ipAddress] - Caller IP for the audit log
 * @returns {Promise<void>} Resolves when revoked
 */
const revokePharmacyLocationAccess = async (
  identifier,
  userIdentifier,
  user = {},
  ipAddress = null
) => {
  const scope = resolveScope(user);
  const location = await requirePharmacyLocation(prisma, identifier, {
    tenantId: scope.can_manage_all_tenants ? null : scope.tenant_id,
  });
  await assertLocationAccess(prisma, { location, user, level: ACCESS_LEVELS.MANAGE });

  const targetUserId = await resolveModelIdByIdentifier({
    model: 'user',
    identifier: userIdentifier,
  });
  const existing = targetUserId
    ? await pharmacyLocationRepository.findAccessGrant(location.id, targetUserId)
    : null;
  if (!existing) {
    throw new HttpError('errors.pharmacy_location_user.not_found', 404);
  }

  await pharmacyLocationRepository.softDeleteAccessGrant(existing.id);

  createAuditLog({
    tenant_id: location.tenant_id,
    user_id: user?.id,
    action: 'DELETE',
    entity: 'pharmacy_location_user',
    entity_id: existing.id,
    diff: { before: existing },
    ip_address: ipAddress,
  }).catch(() => {});
};

// ------------------------------------------------------------------ pricing

/**
 * List a pharmacy's own prices.
 *
 * Supply price and acquisition cost are included only for a caller who manages
 * the pharmacy; a Hospital Pharmacy user reading Main Pharmacy prices sees
 * neither.
 *
 * @param {string} identifier - Location identifier
 * @param {Object} filters - Query filters
 * @param {Object} pagination - `{ page, limit }`
 * @param {Object} user - Request user context
 * @returns {Promise<Object>} Paginated price snapshots
 */
const listPharmacyLocationPrices = async (identifier, filters = {}, pagination = {}, user = {}) => {
  const scope = resolveScope(user);
  const location = await requirePharmacyLocation(prisma, identifier, {
    tenantId: scope.can_manage_all_tenants ? null : scope.tenant_id,
  });

  const grant = await pharmacyLocationRepository.findAccessGrant(location.id, user?.id);
  const manages =
    hasTenantWideAccess(user) || normalizeUpper(grant?.access_level) === ACCESS_LEVELS.MANAGE;

  await assertStockVisibility(prisma, { target: location, user });

  const page = Math.max(1, Number(pagination.page) || 1);
  const limit = Math.max(1, Number(pagination.limit) || DEFAULT_PAGE_SIZE);

  const where = { pharmacy_location_id: location.id };
  if (filters.is_active !== undefined) where.is_active = Boolean(filters.is_active);
  if (filters.drug_id) {
    const drugId = await resolveModelIdByIdentifier({ model: 'drug', identifier: filters.drug_id });
    where.drug_id = drugId || filters.drug_id;
  }
  const search = normalizeIdentifier(filters.search);
  if (search) {
    where.drug = {
      is: {
        OR: [
          { name: { contains: search } },
          { generic_name: { contains: search } },
          { brand_name: { contains: search } },
          { code: { contains: search } },
        ],
      },
    };
  }

  const include = {
    drug: {
      select: {
        id: true,
        human_friendly_id: true,
        name: true,
        generic_name: true,
        brand_name: true,
        code: true,
        form: true,
        strength: true,
        unit_price: true,
        transfer_unit_price: true,
        buy_unit_price: true,
        currency: true,
      },
    },
  };

  const [rows, total] = await Promise.all([
    pharmacyLocationRepository.findPrices(
      where,
      (page - 1) * limit,
      limit,
      { created_at: 'desc' },
      include
    ),
    pharmacyLocationRepository.countPrices(where),
  ]);

  const data = rows.map((row) => ({
    id: row.id,
    human_friendly_id: row.human_friendly_id,
    drug: row.drug,
    is_active: row.is_active,
    ...buildLocationPriceSnapshot({
      priceRow: row,
      location,
      drug: row.drug,
      includeSupplyPrice: manages,
      includeCost: manages,
    }),
  }));

  return { data, ...paginate(page, limit, total) };
};

/**
 * Set a pharmacy's own price for a drug.
 *
 * Only the fields present in the payload are written. `sell_price` and
 * `supply_price` are independent, so setting a Main Pharmacy walk-in price
 * leaves its hospital supply price exactly as it was.
 *
 * @param {string} identifier - Location identifier
 * @param {Object} payload - Price fields
 * @param {Object} user - Request user context
 * @param {string} [ipAddress] - Caller IP for the audit log
 * @returns {Promise<Object>} Stored price row
 */
const upsertPharmacyLocationPrice = async (
  identifier,
  payload = {},
  user = {},
  ipAddress = null
) => {
  const scope = resolveScope(user);
  const location = await requirePharmacyLocation(prisma, identifier, {
    tenantId: scope.can_manage_all_tenants ? null : scope.tenant_id,
  });
  await assertLocationAccess(prisma, { location, user, level: ACCESS_LEVELS.MANAGE });

  const drugId = await resolveModelIdByIdentifier({ model: 'drug', identifier: payload.drug_id });
  if (!drugId) {
    throw new HttpError('errors.drug.not_found', 404, [{ field: 'drug_id' }]);
  }

  const existing = await pharmacyLocationRepository.findPrice(location.id, drugId);

  const data = {};
  if (payload.sell_price !== undefined) data.sell_price = toDecimalString(payload.sell_price);
  if (payload.supply_price !== undefined) data.supply_price = toDecimalString(payload.supply_price);
  if (payload.acquisition_cost !== undefined) {
    data.acquisition_cost = toDecimalString(payload.acquisition_cost);
  }
  if (payload.currency !== undefined) {
    data.currency = payload.currency ? normalizeUpper(payload.currency) : null;
  }
  if (payload.is_active !== undefined) data.is_active = Boolean(payload.is_active);

  const saved = existing
    ? await pharmacyLocationRepository.updatePrice(existing.id, { ...data, deleted_at: null })
    : await pharmacyLocationRepository.createPrice({
        tenant_id: location.tenant_id,
        pharmacy_location_id: location.id,
        drug_id: drugId,
        ...data,
      });

  createAuditLog({
    tenant_id: location.tenant_id,
    user_id: user?.id,
    action: existing ? 'UPDATE' : 'CREATE',
    entity: 'pharmacy_location_price',
    entity_id: saved.id,
    diff: { before: existing || null, after: saved },
    ip_address: ipAddress,
  }).catch(() => {});

  return saved;
};

// -------------------------------------------------- cross-pharmacy visibility

/**
 * This pharmacy's stock next to the availability of the pharmacy that supplies
 * it.
 *
 * Returns one row per item: the caller's own quantity and reorder level in
 * full, and the supplier's quantity as a bare number. Supplier purchase cost,
 * batches and supplier identity are never included.
 *
 * @param {string} identifier - Requesting pharmacy identifier
 * @param {Object} filters - Query filters
 * @param {Object} pagination - `{ page, limit }`
 * @param {Object} user - Request user context
 * @returns {Promise<Object>} Paginated availability rows
 */
const getPharmacyLocationAvailability = async (
  identifier,
  filters = {},
  pagination = {},
  user = {}
) => {
  const scope = resolveScope(user);
  const location = await requirePharmacyLocation(prisma, identifier, {
    tenantId: scope.can_manage_all_tenants ? null : scope.tenant_id,
  });
  await assertLocationAccess(prisma, { location, user, level: ACCESS_LEVELS.VIEW });

  let comparison = null;
  if (filters.compare_location_id) {
    comparison = await requirePharmacyLocation(prisma, filters.compare_location_id, {
      tenantId: scope.can_manage_all_tenants ? null : scope.tenant_id,
    });
  } else if (location.supplied_by_location_id) {
    comparison = await findPharmacyLocation(prisma, location.supplied_by_location_id, {
      tenantId: scope.can_manage_all_tenants ? null : scope.tenant_id,
    });
  }

  if (comparison) {
    await assertStockVisibility(prisma, { target: comparison, viewer: location, user });
  }

  const page = Math.max(1, Number(pagination.page) || 1);
  const limit = Math.max(1, Number(pagination.limit) || DEFAULT_PAGE_SIZE);

  const where = { deleted_at: null, pharmacy_location_id: location.id };
  const search = normalizeIdentifier(filters.search);
  if (search) {
    where.inventory_item = {
      is: {
        OR: [{ name: { contains: search } }, { sku: { contains: search } }],
      },
    };
  }

  const [rows, total] = await Promise.all([
    prisma.inventory_stock.findMany({
      where,
      skip: (page - 1) * limit,
      take: limit,
      orderBy: { updated_at: 'desc' },
      include: {
        inventory_item: {
          select: {
            id: true,
            human_friendly_id: true,
            name: true,
            sku: true,
            unit: true,
            category: true,
            drug_maps: {
              where: { deleted_at: null },
              orderBy: [{ is_default: 'desc' }, { created_at: 'asc' }],
              take: 1,
              select: { drug_id: true },
            },
          },
        },
      },
    }),
    prisma.inventory_stock.count({ where }),
  ]);

  const filtered = filters.below_reorder_level
    ? rows.filter((row) => Number(row.quantity || 0) <= Number(row.reorder_level || 0))
    : rows;

  const supplierMatrix = comparison
    ? await loadStockMatrix(prisma, {
        inventoryItemIds: filtered.map((row) => row.inventory_item_id),
        pharmacyLocationIds: [comparison.id],
      })
    : new Map();

  const data = filtered.map((row) => {
    const supplierStock = comparison
      ? supplierMatrix.get(String(row.inventory_item_id))?.get(String(comparison.id)) || null
      : null;
    const quantity = Number(row.quantity || 0);
    const reorderLevel = Number(row.reorder_level || 0);

    return {
      inventory_item_id: row.inventory_item_id,
      inventory_item: row.inventory_item
        ? {
            id: row.inventory_item.id,
            human_friendly_id: row.inventory_item.human_friendly_id,
            name: row.inventory_item.name,
            sku: row.inventory_item.sku,
            unit: row.inventory_item.unit,
            category: row.inventory_item.category,
          }
        : null,
      drug_id: row.inventory_item?.drug_maps?.[0]?.drug_id || null,
      pharmacy_location_id: location.id,
      quantity,
      reorder_level: reorderLevel,
      below_reorder_level: quantity <= reorderLevel,
      supplier_location: comparison
        ? {
            id: comparison.id,
            name: comparison.name,
            kind: comparison.kind,
            // Quantity only. Cost and supplier terms stay with the pharmacy
            // that owns them (requirement 7).
            available: Number(toSupplierStockProjection(supplierStock)?.quantity || 0),
          }
        : null,
      can_order: Boolean(comparison),
    };
  });

  return {
    data,
    location: toPublic(location),
    comparison_location: comparison ? toPublic(comparison, { includeSupplier: false }) : null,
    ...paginate(page, limit, total),
  };
};

module.exports = {
  listPharmacyLocations,
  getPharmacyLocation,
  createPharmacyLocation,
  updatePharmacyLocation,
  deletePharmacyLocation,
  listPharmacyLocationAccess,
  upsertPharmacyLocationAccess,
  revokePharmacyLocationAccess,
  listPharmacyLocationPrices,
  upsertPharmacyLocationPrice,
  getPharmacyLocationAvailability,
  findLocationPrice,
};
