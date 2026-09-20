/**
 * Pharmacy location access
 *
 * @module lib/pharmacy
 * @description Resolution and guards for pharmacy locations (Main Pharmacy,
 * Hospital Pharmacy, and any Branch/Theatre/Ward pharmacy added later).
 *
 * The isolation rules in one place:
 *
 * * Stock, batches, adjustments, prices and prescriptions are keyed on
 *   `pharmacy_location_id`, so two pharmacies in one facility never share a
 *   balance or a price.
 * * A user acts inside a location only through a `pharmacy_location_user`
 *   grant. MANAGE may change that location's inventory and prices; DISPENSE may
 *   dispense from it; VIEW may only read it.
 * * Procurement (suppliers, purchase orders, goods receipt, batches, costs,
 *   adjustments) additionally requires the location to be the procurement
 *   pharmacy, which keeps Hospital Pharmacy users out of Main Pharmacy records
 *   even if they somehow hold a grant on it.
 * * Reading the *supplying* pharmacy's availability is allowed without a grant
 *   when the requester's own location is supplied by it, but only the fields
 *   listed in `SUPPLIER_STOCK_PUBLIC_SELECT` - never supplier cost.
 */

const prisma = require('@prisma/client');
const { HttpError } = require('@lib/errors');
const { ROLES } = require('@config/roles');

const ACCESS_LEVELS = Object.freeze({
  VIEW: 'VIEW',
  DISPENSE: 'DISPENSE',
  MANAGE: 'MANAGE',
});

/** Higher number satisfies every lower requirement. */
const ACCESS_LEVEL_RANK = Object.freeze({
  [ACCESS_LEVELS.VIEW]: 1,
  [ACCESS_LEVELS.DISPENSE]: 2,
  [ACCESS_LEVELS.MANAGE]: 3,
});

const LOCATION_KINDS = Object.freeze({
  MAIN: 'MAIN',
  HOSPITAL: 'HOSPITAL',
  BRANCH: 'BRANCH',
  THEATRE: 'THEATRE',
  WARD: 'WARD',
  OTHER: 'OTHER',
});

const ORDER_ORIGINS = Object.freeze({
  HOSPITAL: 'HOSPITAL',
  WALK_IN: 'WALK_IN',
});

/**
 * What a Hospital Pharmacy user may see of the Main Pharmacy.
 *
 * Quantities and reorder levels only. Purchase cost, supplier and batch
 * economics are deliberately absent: requirement 7 says not to expose Main
 * Pharmacy information the Hospital Pharmacy does not need.
 */
const SUPPLIER_STOCK_PUBLIC_SELECT = Object.freeze({
  id: true,
  human_friendly_id: true,
  inventory_item_id: true,
  pharmacy_location_id: true,
  quantity: true,
  reorder_level: true,
  updated_at: true,
});

const PHARMACY_LOCATION_PUBLIC_SELECT = Object.freeze({
  id: true,
  human_friendly_id: true,
  tenant_id: true,
  facility_id: true,
  name: true,
  code: true,
  kind: true,
  is_active: true,
  is_default: true,
  handles_procurement: true,
  handles_walk_in: true,
  handles_prescriptions: true,
  supplied_by_location_id: true,
  currency: true,
  created_at: true,
  updated_at: true,
});

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const normalizeIdentifier = (value) => (typeof value === 'string' ? value.trim() : '');
const isUuid = (value) => UUID_REGEX.test(normalizeIdentifier(value));
const normalizeUpper = (value) => normalizeIdentifier(value).toUpperCase();

/** Tenant/platform admins act across every pharmacy without an explicit grant. */
const hasTenantWideAccess = (user = {}) => {
  const roles = Array.isArray(user?.roles) ? user.roles : [];
  return (
    roles.includes(ROLES.PLATFORM_ADMIN) ||
    roles.includes(ROLES.TENANT_ADMIN) ||
    roles.includes(ROLES.FACILITY_ADMIN)
  );
};

const delegateFor = (client, model) => {
  const delegate = client?.[model];
  if (!delegate || typeof delegate.findFirst !== 'function') {
    return null;
  }
  return delegate;
};

/**
 * Resolve a pharmacy location from a UUID, a human-friendly id (`PLO…`) or a
 * kind/code such as `MAIN` / `HOSPITAL`.
 *
 * @param {Object} client - Prisma client or an open transaction
 * @param {string} identifier - Location identifier
 * @param {Object} [options]
 * @param {string} [options.tenantId] - Restrict to this tenant
 * @param {string} [options.facilityId] - Restrict to this facility
 * @returns {Promise<Object|null>} Location row, or null when unresolvable
 */
const findPharmacyLocation = async (client, identifier, { tenantId = null, facilityId = null } = {}) => {
  const normalized = normalizeIdentifier(identifier);
  if (!normalized) return null;

  const delegate = delegateFor(client, 'pharmacy_location');
  if (!delegate) return null;

  const scope = {
    deleted_at: null,
    ...(tenantId ? { tenant_id: tenantId } : {}),
    ...(facilityId ? { facility_id: facilityId } : {}),
  };

  if (isUuid(normalized)) {
    const byId = await delegate.findFirst({ where: { ...scope, id: normalized } });
    if (byId) return byId;
  }

  const upper = normalizeUpper(normalized);
  const byFriendlyId = await delegate.findFirst({
    where: { ...scope, human_friendly_id: upper },
  });
  if (byFriendlyId) return byFriendlyId;

  const byCode = await delegate.findFirst({
    where: { ...scope, code: upper },
    orderBy: [{ is_default: 'desc' }, { created_at: 'asc' }],
  });
  if (byCode) return byCode;

  if (Object.prototype.hasOwnProperty.call(LOCATION_KINDS, upper)) {
    return delegate.findFirst({
      where: { ...scope, kind: upper, is_active: true },
      orderBy: [{ is_default: 'desc' }, { created_at: 'asc' }],
    });
  }

  return null;
};

/**
 * Resolve a location, or throw 404 when it does not exist in scope.
 *
 * @param {Object} client - Prisma client or transaction
 * @param {string} identifier - Location identifier
 * @param {Object} [options] - `tenantId` / `facilityId` scope
 * @returns {Promise<Object>} Location row
 * @throws {HttpError} 404 when unresolvable
 */
const requirePharmacyLocation = async (client, identifier, options = {}) => {
  const location = await findPharmacyLocation(client, identifier, options);
  if (!location) {
    throw new HttpError('errors.pharmacy_location.not_found', 404, [
      { field: 'pharmacy_location_id' },
    ]);
  }
  return location;
};

/**
 * The default location of a kind for a facility.
 *
 * @param {Object} client - Prisma client or transaction
 * @param {Object} params
 * @param {string} params.facilityId - Facility to look in
 * @param {string} params.kind - `PharmacyLocationKind` value
 * @param {string} [params.tenantId] - Tenant scope
 * @returns {Promise<Object|null>} Location row, or null when none exists
 */
const findDefaultLocationByKind = async (client, { facilityId, kind, tenantId = null }) => {
  const delegate = delegateFor(client, 'pharmacy_location');
  if (!delegate || !facilityId || !kind) return null;

  return delegate.findFirst({
    where: {
      deleted_at: null,
      is_active: true,
      facility_id: facilityId,
      kind,
      ...(tenantId ? { tenant_id: tenantId } : {}),
    },
    orderBy: [{ is_default: 'desc' }, { created_at: 'asc' }],
  });
};

/**
 * The pharmacy that should fill a prescription.
 *
 * Hospital prescriptions go to a pharmacy that handles prescriptions (the
 * Hospital Pharmacy); walk-in prescriptions go to one that handles walk-in
 * sales (the Main Pharmacy). This is what keeps a prescription from being
 * dispensed by the wrong pharmacy.
 *
 * @param {Object} client - Prisma client or transaction
 * @param {Object} params
 * @param {string} params.facilityId - Facility the order belongs to
 * @param {string} params.origin - `HOSPITAL` or `WALK_IN`
 * @param {string} [params.tenantId] - Tenant scope
 * @returns {Promise<Object|null>} Location row, or null when none is configured
 */
const resolveDispensingLocationForOrigin = async (
  client,
  { facilityId, origin, tenantId = null }
) => {
  const delegate = delegateFor(client, 'pharmacy_location');
  if (!delegate || !facilityId) return null;

  const normalizedOrigin = normalizeUpper(origin) || ORDER_ORIGINS.HOSPITAL;
  const capabilityField =
    normalizedOrigin === ORDER_ORIGINS.WALK_IN ? 'handles_walk_in' : 'handles_prescriptions';
  const preferredKind =
    normalizedOrigin === ORDER_ORIGINS.WALK_IN ? LOCATION_KINDS.MAIN : LOCATION_KINDS.HOSPITAL;

  const scope = {
    deleted_at: null,
    is_active: true,
    facility_id: facilityId,
    ...(tenantId ? { tenant_id: tenantId } : {}),
  };

  const byCapability = await delegate.findFirst({
    where: { ...scope, [capabilityField]: true },
    orderBy: [{ is_default: 'desc' }, { created_at: 'asc' }],
  });
  if (byCapability) return byCapability;

  // A facility that has not set the capability flags still routes by kind
  // rather than silently dispensing from whichever pharmacy is first.
  return delegate.findFirst({
    where: { ...scope, kind: preferredKind },
    orderBy: [{ is_default: 'desc' }, { created_at: 'asc' }],
  });
};

/**
 * Every active grant a user holds, keyed by location id.
 *
 * @param {Object} client - Prisma client or transaction
 * @param {Object} params
 * @param {string} params.userId - User to load grants for
 * @param {string} [params.tenantId] - Tenant scope
 * @returns {Promise<Map<string, Object>>} location id -> grant row
 */
const loadUserLocationGrants = async (client, { userId, tenantId = null }) => {
  const delegate = delegateFor(client, 'pharmacy_location_user');
  const normalizedUserId = normalizeIdentifier(userId);
  if (!delegate || !normalizedUserId || typeof delegate.findMany !== 'function') {
    return new Map();
  }

  const grants = await delegate.findMany({
    where: {
      deleted_at: null,
      is_active: true,
      user_id: normalizedUserId,
      ...(tenantId ? { tenant_id: tenantId } : {}),
    },
  });

  return new Map(
    (Array.isArray(grants) ? grants : []).map((grant) => [
      String(grant.pharmacy_location_id),
      grant,
    ])
  );
};

/**
 * Whether `grantLevel` satisfies `requiredLevel`.
 *
 * @param {string|null} grantLevel - Level the user holds
 * @param {string} requiredLevel - Level the action needs
 * @returns {boolean} True when the grant is sufficient
 */
const satisfiesAccessLevel = (grantLevel, requiredLevel) => {
  const held = ACCESS_LEVEL_RANK[normalizeUpper(grantLevel)] || 0;
  const needed = ACCESS_LEVEL_RANK[normalizeUpper(requiredLevel)] || 0;
  return held > 0 && held >= needed;
};

/**
 * Assert that a user may act in a pharmacy location at a given level.
 *
 * @param {Object} client - Prisma client or transaction
 * @param {Object} params
 * @param {Object} params.location - Location row being acted on
 * @param {Object} params.user - Request user context
 * @param {string} [params.level] - Required access level, default `DISPENSE`
 * @returns {Promise<Object|null>} The grant used, or null for tenant-wide roles
 * @throws {HttpError} 403 when the user has no sufficient grant
 */
const assertLocationAccess = async (client, { location, user = {}, level = ACCESS_LEVELS.DISPENSE }) => {
  if (!location) {
    throw new HttpError('errors.pharmacy_location.not_found', 404);
  }

  if (hasTenantWideAccess(user)) {
    return null;
  }

  const userId = normalizeIdentifier(user?.id || user?.user_id);
  if (!userId) {
    throw new HttpError('errors.pharmacy_location.access_denied', 403, [
      { pharmacy_location_id: location.id },
    ]);
  }

  const delegate = delegateFor(client, 'pharmacy_location_user');
  const grant = delegate
    ? await delegate.findFirst({
        where: {
          deleted_at: null,
          is_active: true,
          user_id: userId,
          pharmacy_location_id: location.id,
        },
      })
    : null;

  if (!grant || !satisfiesAccessLevel(grant.access_level, level)) {
    throw new HttpError('errors.pharmacy_location.access_denied', 403, [
      { pharmacy_location_id: location.id, required_access_level: level },
    ]);
  }

  return grant;
};

/**
 * Assert that a location may hold procurement records, and that the user may
 * manage them.
 *
 * Suppliers, purchase orders, goods receipt, batches, expiry, costs and stock
 * adjustments all run through here, which is what stops a Hospital Pharmacy
 * user from touching Main Pharmacy procurement.
 *
 * @param {Object} client - Prisma client or transaction
 * @param {Object} params
 * @param {Object} params.location - Location row being acted on
 * @param {Object} params.user - Request user context
 * @returns {Promise<Object|null>} The grant used, or null for tenant-wide roles
 * @throws {HttpError} 403 when the location does not procure, or access is denied
 */
const assertProcurementAccess = async (client, { location, user = {} }) => {
  if (!location) {
    throw new HttpError('errors.pharmacy_location.not_found', 404);
  }
  if (!location.handles_procurement) {
    throw new HttpError('errors.pharmacy_location.procurement_not_allowed', 403, [
      { pharmacy_location_id: location.id, kind: location.kind },
    ]);
  }
  return assertLocationAccess(client, { location, user, level: ACCESS_LEVELS.MANAGE });
};

/**
 * Whether `viewer` may read `target`'s availability without a grant on it.
 *
 * True when the viewer's pharmacy is supplied by the target pharmacy, which is
 * the read-only cross-pharmacy view in requirement 7.
 *
 * @param {Object} viewer - Location the user is acting from
 * @param {Object} target - Location being looked at
 * @returns {boolean} True when the read is allowed
 */
const canViewSupplierStock = (viewer, target) => {
  if (!viewer || !target) return false;
  if (String(viewer.id) === String(target.id)) return true;
  return String(viewer.supplied_by_location_id || '') === String(target.id);
};

/**
 * Assert a cross-pharmacy read is allowed, by grant or by supply relationship.
 *
 * @param {Object} client - Prisma client or transaction
 * @param {Object} params
 * @param {Object} params.target - Location being read
 * @param {Object} [params.viewer] - Location the user is acting from
 * @param {Object} params.user - Request user context
 * @returns {Promise<void>} Resolves when the read is allowed
 * @throws {HttpError} 403 when neither a grant nor a supply link exists
 */
const assertStockVisibility = async (client, { target, viewer = null, user = {} }) => {
  if (hasTenantWideAccess(user)) return;
  if (viewer && canViewSupplierStock(viewer, target)) return;

  await assertLocationAccess(client, { location: target, user, level: ACCESS_LEVELS.VIEW });
};

/**
 * Strip a supplying pharmacy's stock row down to what the requester may see.
 *
 * @param {Object} stockRecord - Raw `inventory_stock` row
 * @returns {Object|null} Quantity-only projection, or null for a falsy input
 */
const toSupplierStockProjection = (stockRecord) => {
  if (!stockRecord) return null;
  return Object.keys(SUPPLIER_STOCK_PUBLIC_SELECT).reduce((projection, field) => {
    projection[field] = stockRecord[field] ?? null;
    return projection;
  }, {});
};

module.exports = {
  ACCESS_LEVELS,
  ACCESS_LEVEL_RANK,
  LOCATION_KINDS,
  ORDER_ORIGINS,
  SUPPLIER_STOCK_PUBLIC_SELECT,
  PHARMACY_LOCATION_PUBLIC_SELECT,
  hasTenantWideAccess,
  findPharmacyLocation,
  requirePharmacyLocation,
  findDefaultLocationByKind,
  resolveDispensingLocationForOrigin,
  loadUserLocationGrants,
  satisfiesAccessLevel,
  assertLocationAccess,
  assertProcurementAccess,
  canViewSupplierStock,
  assertStockVisibility,
  toSupplierStockProjection,
};
