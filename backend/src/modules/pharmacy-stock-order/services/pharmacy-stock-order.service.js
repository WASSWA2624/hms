/**
 * Pharmacy stock order service
 *
 * @module modules/pharmacy-stock-order/services
 * @description The Hospital Pharmacy -> Main Pharmacy stock ordering workflow.
 *
 *   create -> submit -> review (approve / partially approve / reject)
 *          -> issue  -> receive
 *
 * The order is paperwork. Creating, submitting, approving and rejecting it
 * never touch a balance. Inventory changes exactly twice: `issueStockOrder`
 * takes the quantity out of the supplying pharmacy, and `receiveStockOrder`
 * brings it into the requesting pharmacy. Both legs share one
 * `transfer_group_id` so a shipment that was issued but not yet received stays
 * visible as in transit rather than vanishing from both balances.
 *
 * Sides are enforced separately: only the requesting pharmacy may create,
 * submit and receive; only the supplying pharmacy may review and issue. That is
 * what stops a Hospital Pharmacy user from reaching into Main Pharmacy stock.
 */

const prisma = require('@prisma/client');
const { randomUUID } = require('crypto');
const { createAuditLog } = require('@lib/audit');
const { HttpError } = require('@lib/errors');
const {
  ACCESS_LEVELS,
  requirePharmacyLocation,
  findPharmacyLocation,
  loadUserLocationGrants,
  assertLocationAccess,
  hasTenantWideAccess,
} = require('@lib/pharmacy/pharmacy-location-access');
const { requireSupplyPrice } = require('@lib/pharmacy/pharmacy-location-pricing');
const {
  issueStockToLocation,
  receiveStockAtLocation,
  findLocationStock,
  toPositiveInt,
} = require('@lib/pharmacy/pharmacy-location-stock');
const { resolveModelIdByIdentifier } = require('@lib/identifiers/resolve-entity-id');

const DEFAULT_PAGE_SIZE = 20;

const STATUS = Object.freeze({
  DRAFT: 'DRAFT',
  SUBMITTED: 'SUBMITTED',
  UNDER_REVIEW: 'UNDER_REVIEW',
  APPROVED: 'APPROVED',
  PARTIALLY_APPROVED: 'PARTIALLY_APPROVED',
  REJECTED: 'REJECTED',
  ISSUED: 'ISSUED',
  PARTIALLY_RECEIVED: 'PARTIALLY_RECEIVED',
  RECEIVED: 'RECEIVED',
  CANCELLED: 'CANCELLED',
});

const ITEM_STATUS = Object.freeze({
  REQUESTED: 'REQUESTED',
  APPROVED: 'APPROVED',
  PARTIALLY_APPROVED: 'PARTIALLY_APPROVED',
  REJECTED: 'REJECTED',
  ISSUED: 'ISSUED',
  RECEIVED: 'RECEIVED',
  CANCELLED: 'CANCELLED',
});

const EDITABLE_STATUSES = new Set([STATUS.DRAFT]);
const REVIEWABLE_STATUSES = new Set([STATUS.SUBMITTED, STATUS.UNDER_REVIEW]);
const ISSUABLE_STATUSES = new Set([STATUS.APPROVED, STATUS.PARTIALLY_APPROVED]);
const RECEIVABLE_STATUSES = new Set([STATUS.ISSUED, STATUS.PARTIALLY_RECEIVED]);
const CANCELLABLE_STATUSES = new Set([
  STATUS.DRAFT,
  STATUS.SUBMITTED,
  STATUS.UNDER_REVIEW,
  STATUS.APPROVED,
  STATUS.PARTIALLY_APPROVED,
]);

const ORDER_INCLUDE = Object.freeze({
  requesting_location: true,
  supplying_location: true,
  items: {
    where: { deleted_at: null },
    orderBy: { created_at: 'asc' },
    include: {
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
          currency: true,
          unit_price: true,
          transfer_unit_price: true,
        },
      },
      inventory_item: {
        select: { id: true, human_friendly_id: true, name: true, sku: true, unit: true },
      },
    },
  },
});

const normalizeIdentifier = (value) => (typeof value === 'string' ? value.trim() : '');
const normalizeUpper = (value) => normalizeIdentifier(value).toUpperCase();

const resolveScope = (user = {}) => {
  const roles = Array.isArray(user?.roles) ? user.roles : [];
  const tenantId = normalizeIdentifier(user?.tenant_id) || null;
  const canManageAllTenants = roles.includes('PLATFORM_ADMIN');
  if (!canManageAllTenants && !tenantId) {
    throw new HttpError('errors.auth.scope_mismatch', 403);
  }
  return { tenant_id: tenantId, can_manage_all_tenants: canManageAllTenants };
};

const assertTransition = (condition, details = {}) => {
  if (condition) return;
  throw new HttpError('errors.pharmacy_stock_order.invalid_transition', 400, [details]);
};

/**
 * Find a stock order by UUID or friendly id, within the caller's tenant.
 *
 * @param {Object} client - Prisma client or transaction
 * @param {string} identifier - Order identifier
 * @param {Object} scope - Resolved tenant scope
 * @returns {Promise<Object>} Order with items and both locations
 * @throws {HttpError} 404 when not found in scope
 */
const requireStockOrder = async (client, identifier, scope) => {
  const normalized = normalizeIdentifier(identifier);
  if (!normalized) {
    throw new HttpError('errors.pharmacy_stock_order.not_found', 404);
  }

  const where = {
    deleted_at: null,
    ...(scope.can_manage_all_tenants ? {} : { tenant_id: scope.tenant_id }),
    OR: [{ id: normalized }, { human_friendly_id: normalizeUpper(normalized) }],
  };

  const order = await client.pharmacy_stock_order.findFirst({ where, include: ORDER_INCLUDE });
  if (!order) {
    throw new HttpError('errors.pharmacy_stock_order.not_found', 404);
  }
  return order;
};

/**
 * Resolve which inventory item a drug moves against for a location.
 *
 * @param {Object} client - Prisma client or transaction
 * @param {Object} params
 * @param {string} params.drugId - Catalog drug
 * @param {string} params.tenantId - Tenant scope
 * @param {string} [params.explicitInventoryItemId] - Caller-supplied override
 * @returns {Promise<string|null>} Inventory item id, or null when unmapped
 */
const resolveInventoryItemIdForDrug = async (
  client,
  { drugId, tenantId, explicitInventoryItemId = null }
) => {
  if (explicitInventoryItemId) {
    const resolved = await resolveModelIdByIdentifier({
      model: 'inventory_item',
      identifier: explicitInventoryItemId,
    });
    if (resolved) return resolved;
  }

  const map = await client.drug_inventory_map.findFirst({
    where: {
      deleted_at: null,
      drug_id: drugId,
      ...(tenantId ? { tenant_id: tenantId } : {}),
    },
    orderBy: [{ is_default: 'desc' }, { created_at: 'asc' }],
  });

  return map?.inventory_item_id || null;
};

/**
 * Match a payload line to a persisted item, by item id or by drug.
 *
 * @param {Object[]} items - Persisted order items
 * @param {Object} entry - Payload line
 * @returns {Object|null} Matching item, or null
 */
const matchItem = (items, entry) => {
  const byId = normalizeIdentifier(entry?.id);
  if (byId) {
    const found = items.find(
      (item) =>
        String(item.id) === byId ||
        String(item.human_friendly_id || '').toUpperCase() === byId.toUpperCase()
    );
    if (found) return found;
  }

  const byDrug = normalizeIdentifier(entry?.drug_id);
  if (byDrug) {
    return (
      items.find(
        (item) =>
          String(item.drug_id) === byDrug ||
          String(item.drug?.human_friendly_id || '').toUpperCase() === byDrug.toUpperCase()
      ) || null
    );
  }

  return null;
};

/** Order status implied by its items after a review. */
const rollupReviewStatus = (items) => {
  const active = items.filter((item) => item.status !== ITEM_STATUS.CANCELLED);
  if (!active.length) return STATUS.REJECTED;

  const approvedTotal = active.reduce((sum, item) => sum + toPositiveInt(item.approved_quantity), 0);
  if (approvedTotal <= 0) return STATUS.REJECTED;

  const fullyApproved = active.every(
    (item) => toPositiveInt(item.approved_quantity) >= toPositiveInt(item.requested_quantity)
  );
  return fullyApproved ? STATUS.APPROVED : STATUS.PARTIALLY_APPROVED;
};

/** Order status implied by its items after a receipt. */
const rollupReceiveStatus = (items) => {
  const active = items.filter((item) => item.status !== ITEM_STATUS.CANCELLED);
  const issuedTotal = active.reduce((sum, item) => sum + toPositiveInt(item.issued_quantity), 0);
  const receivedTotal = active.reduce((sum, item) => sum + toPositiveInt(item.received_quantity), 0);

  if (receivedTotal <= 0) return STATUS.ISSUED;
  return receivedTotal >= issuedTotal ? STATUS.RECEIVED : STATUS.PARTIALLY_RECEIVED;
};

const audit = (order, user, action, diff, ipAddress) => {
  createAuditLog({
    tenant_id: order.tenant_id,
    user_id: user?.id,
    action,
    entity: 'pharmacy_stock_order',
    entity_id: order.id,
    diff,
    ip_address: ipAddress,
  }).catch(() => {});
};

/**
 * List stock orders, optionally split into a pharmacy's inbox and outbox.
 *
 * @param {Object} filters - Query filters
 * @param {Object} pagination - `{ page, limit }`
 * @param {Object} sort - `{ sort_by, order }`
 * @param {Object} user - Request user context
 * @returns {Promise<Object>} Paginated orders
 */
const listStockOrders = async (filters = {}, pagination = {}, sort = {}, user = {}) => {
  const scope = resolveScope(user);
  const page = Math.max(1, Number(pagination.page) || 1);
  const limit = Math.max(1, Number(pagination.limit) || DEFAULT_PAGE_SIZE);

  const where = {
    deleted_at: null,
    ...(scope.can_manage_all_tenants ? {} : { tenant_id: scope.tenant_id }),
  };

  if (filters.status) where.status = normalizeUpper(filters.status);

  const resolveLocationId = async (identifier) => {
    if (!identifier) return null;
    const location = await findPharmacyLocation(prisma, identifier, {
      tenantId: scope.can_manage_all_tenants ? null : scope.tenant_id,
    });
    return location?.id || null;
  };

  const requestingId = await resolveLocationId(filters.requesting_location_id);
  const supplyingId = await resolveLocationId(filters.supplying_location_id);
  if (requestingId) where.requesting_location_id = requestingId;
  if (supplyingId) where.supplying_location_id = supplyingId;

  const queue = normalizeUpper(filters.queue) || 'ALL';
  const locationId = await resolveLocationId(filters.location_id);
  if (locationId) {
    if (queue === 'INBOX') {
      where.supplying_location_id = locationId;
    } else if (queue === 'OUTBOX') {
      where.requesting_location_id = locationId;
    } else {
      where.OR = [
        { requesting_location_id: locationId },
        { supplying_location_id: locationId },
      ];
    }
  } else if (!hasTenantWideAccess(user)) {
    // Without an explicit location, a pharmacy user sees only the orders their
    // own pharmacies are a party to.
    const grants = await loadUserLocationGrants(prisma, {
      userId: user?.id,
      tenantId: scope.tenant_id,
    });
    const ids = Array.from(grants.keys());
    where.OR = [
      { requesting_location_id: { in: ids.length ? ids : ['__none__'] } },
      { supplying_location_id: { in: ids.length ? ids : ['__none__'] } },
    ];
  }

  const search = normalizeIdentifier(filters.search);
  if (search) {
    where.AND = [
      ...(where.AND || []),
      {
        OR: [
          { human_friendly_id: { contains: search.toUpperCase() } },
          { notes: { contains: search } },
          { items: { some: { deleted_at: null, drug: { is: { name: { contains: search } } } } } },
        ],
      },
    ];
  }

  const orderBy = sort.sort_by
    ? { [sort.sort_by]: sort.order === 'asc' ? 'asc' : 'desc' }
    : { created_at: 'desc' };

  const [rows, total] = await Promise.all([
    prisma.pharmacy_stock_order.findMany({
      where,
      skip: (page - 1) * limit,
      take: limit,
      orderBy,
      include: ORDER_INCLUDE,
    }),
    prisma.pharmacy_stock_order.count({ where }),
  ]);

  const totalPages = Math.ceil(total / limit) || 0;
  return {
    data: rows,
    page,
    limit,
    total,
    totalPages,
    hasNextPage: page < totalPages,
    hasPreviousPage: page > 1,
  };
};

/**
 * Get one stock order.
 *
 * @param {string} identifier - Order identifier
 * @param {Object} user - Request user context
 * @returns {Promise<Object>} Order with items
 */
const getStockOrder = async (identifier, user = {}) => {
  const scope = resolveScope(user);
  const order = await requireStockOrder(prisma, identifier, scope);

  // Either side of the order may read it.
  if (!hasTenantWideAccess(user)) {
    const grants = await loadUserLocationGrants(prisma, {
      userId: user?.id,
      tenantId: scope.tenant_id,
    });
    const isParty =
      grants.has(String(order.requesting_location_id)) ||
      grants.has(String(order.supplying_location_id));
    if (!isParty) {
      throw new HttpError('errors.pharmacy_location.access_denied', 403, [
        { pharmacy_stock_order_id: order.id },
      ]);
    }
  }

  return order;
};

/**
 * Create a stock order on behalf of the requesting pharmacy.
 *
 * Creating an order never changes stock; it records what the requesting
 * pharmacy wants.
 *
 * @param {Object} payload - Order and line fields
 * @param {Object} user - Request user context
 * @param {string} [ipAddress] - Caller IP for the audit log
 * @returns {Promise<Object>} Created order
 */
const createStockOrder = async (payload = {}, user = {}, ipAddress = null) => {
  const scope = resolveScope(user);

  const requesting = await requirePharmacyLocation(prisma, payload.requesting_location_id, {
    tenantId: scope.can_manage_all_tenants ? null : scope.tenant_id,
  });
  await assertLocationAccess(prisma, {
    location: requesting,
    user,
    level: ACCESS_LEVELS.DISPENSE,
  });

  const supplyingIdentifier = payload.supplying_location_id || requesting.supplied_by_location_id;
  if (!supplyingIdentifier) {
    throw new HttpError('errors.pharmacy_stock_order.supplier_not_configured', 400, [
      { field: 'supplying_location_id', pharmacy_location_id: requesting.id },
    ]);
  }

  const supplying = await requirePharmacyLocation(prisma, supplyingIdentifier, {
    tenantId: requesting.tenant_id,
  });

  if (String(supplying.id) === String(requesting.id)) {
    throw new HttpError('errors.pharmacy_location.self_supply', 400, [
      { field: 'supplying_location_id' },
    ]);
  }
  if (String(supplying.facility_id) !== String(requesting.facility_id)) {
    throw new HttpError('errors.pharmacy_location.supplier_facility_mismatch', 400, [
      { field: 'supplying_location_id' },
    ]);
  }

  const submitNow = payload.submit === true;
  const now = new Date();

  const created = await prisma.$transaction(async (tx) => {
    const order = await tx.pharmacy_stock_order.create({
      data: {
        tenant_id: requesting.tenant_id,
        requesting_location_id: requesting.id,
        supplying_location_id: supplying.id,
        status: submitNow ? STATUS.SUBMITTED : STATUS.DRAFT,
        requested_by_user_id: user?.id || null,
        notes: payload.notes || null,
        currency: requesting.currency || supplying.currency || null,
        submitted_at: submitNow ? now : null,
      },
    });

    for (const entry of payload.items || []) {
      const drugId = await resolveModelIdByIdentifier({
        model: 'drug',
        identifier: entry.drug_id,
      });
      if (!drugId) {
        throw new HttpError('errors.drug.not_found', 404, [{ field: 'items.drug_id' }]);
      }

      const inventoryItemId = await resolveInventoryItemIdForDrug(tx, {
        drugId,
        tenantId: requesting.tenant_id,
        explicitInventoryItemId: entry.inventory_item_id,
      });

      const row = {
        stock_order_id: order.id,
        drug_id: drugId,
        inventory_item_id: inventoryItemId,
        requested_quantity: toPositiveInt(entry.requested_quantity),
        status: ITEM_STATUS.REQUESTED,
        notes: entry.notes || null,
      };
      await prisma.assignFriendlyIdIfMissing('pharmacy_stock_order_item', row);
      await tx.pharmacy_stock_order_item.create({ data: row });
    }

    return tx.pharmacy_stock_order.findFirst({
      where: { id: order.id },
      include: ORDER_INCLUDE,
    });
  });

  audit(created, user, 'CREATE', { after: created }, ipAddress);
  return created;
};

/**
 * Edit a draft order, or submit it for review.
 *
 * @param {string} identifier - Order identifier
 * @param {Object} payload - Fields to change
 * @param {Object} user - Request user context
 * @param {string} [ipAddress] - Caller IP for the audit log
 * @returns {Promise<Object>} Updated order
 */
const updateStockOrder = async (identifier, payload = {}, user = {}, ipAddress = null) => {
  const scope = resolveScope(user);
  const existing = await requireStockOrder(prisma, identifier, scope);

  assertTransition(EDITABLE_STATUSES.has(existing.status), {
    from: existing.status,
    reason: 'only_draft_orders_are_editable',
  });

  await assertLocationAccess(prisma, {
    location: existing.requesting_location,
    user,
    level: ACCESS_LEVELS.DISPENSE,
  });

  const updated = await prisma.$transaction(async (tx) => {
    if (payload.notes !== undefined) {
      await tx.pharmacy_stock_order.update({
        where: { id: existing.id },
        data: { notes: payload.notes || null },
      });
    }

    if (Array.isArray(payload.items)) {
      await tx.pharmacy_stock_order_item.updateMany({
        where: { stock_order_id: existing.id, deleted_at: null },
        data: { deleted_at: new Date() },
      });

      for (const entry of payload.items) {
        const drugId = await resolveModelIdByIdentifier({
          model: 'drug',
          identifier: entry.drug_id,
        });
        if (!drugId) {
          throw new HttpError('errors.drug.not_found', 404, [{ field: 'items.drug_id' }]);
        }
        const inventoryItemId = await resolveInventoryItemIdForDrug(tx, {
          drugId,
          tenantId: existing.tenant_id,
          explicitInventoryItemId: entry.inventory_item_id,
        });
        const row = {
          stock_order_id: existing.id,
          drug_id: drugId,
          inventory_item_id: inventoryItemId,
          requested_quantity: toPositiveInt(entry.requested_quantity),
          status: ITEM_STATUS.REQUESTED,
          notes: entry.notes || null,
        };
        await prisma.assignFriendlyIdIfMissing('pharmacy_stock_order_item', row);
        await tx.pharmacy_stock_order_item.create({ data: row });
      }
    }

    return tx.pharmacy_stock_order.findFirst({
      where: { id: existing.id },
      include: ORDER_INCLUDE,
    });
  });

  audit(updated, user, 'UPDATE', { before: existing, after: updated }, ipAddress);
  return updated;
};

/**
 * Submit a draft order to the supplying pharmacy.
 *
 * @param {string} identifier - Order identifier
 * @param {Object} user - Request user context
 * @param {string} [ipAddress] - Caller IP for the audit log
 * @returns {Promise<Object>} Submitted order
 */
const submitStockOrder = async (identifier, user = {}, ipAddress = null) => {
  const scope = resolveScope(user);
  const existing = await requireStockOrder(prisma, identifier, scope);

  assertTransition(existing.status === STATUS.DRAFT, {
    from: existing.status,
    to: STATUS.SUBMITTED,
  });
  assertTransition((existing.items || []).length > 0, { reason: 'items_required' });

  await assertLocationAccess(prisma, {
    location: existing.requesting_location,
    user,
    level: ACCESS_LEVELS.DISPENSE,
  });

  await prisma.pharmacy_stock_order.update({
    where: { id: existing.id },
    data: { status: STATUS.SUBMITTED, submitted_at: new Date() },
  });

  const updated = await requireStockOrder(prisma, existing.id, scope);
  audit(updated, user, 'UPDATE', { before: existing, after: updated }, ipAddress);
  return updated;
};

/**
 * Review a submitted order: approve, partially approve or reject.
 *
 * Reviewing never moves stock. Approval only records how much the supplying
 * pharmacy is willing to issue.
 *
 * @param {string} identifier - Order identifier
 * @param {Object} payload - Decision and per-line approved quantities
 * @param {Object} user - Request user context
 * @param {string} [ipAddress] - Caller IP for the audit log
 * @returns {Promise<Object>} Reviewed order
 */
const reviewStockOrder = async (identifier, payload = {}, user = {}, ipAddress = null) => {
  const scope = resolveScope(user);
  const existing = await requireStockOrder(prisma, identifier, scope);

  assertTransition(REVIEWABLE_STATUSES.has(existing.status), {
    from: existing.status,
    reason: 'order_is_not_awaiting_review',
  });

  // Only the supplying pharmacy decides. A requesting-pharmacy user cannot
  // approve their own request against someone else's stock.
  await assertLocationAccess(prisma, {
    location: existing.supplying_location,
    user,
    level: ACCESS_LEVELS.MANAGE,
  });

  const reviewedAt = new Date();
  const rejectAll = normalizeUpper(payload.decision) === 'REJECT';

  const updated = await prisma.$transaction(async (tx) => {
    const items = existing.items || [];
    const nextItems = [];

    for (const item of items) {
      const entry = (payload.items || []).find((candidate) => matchItem([item], candidate));
      const requested = toPositiveInt(item.requested_quantity);
      const approved = rejectAll
        ? 0
        : entry && entry.approved_quantity !== undefined
          ? Math.min(toPositiveInt(entry.approved_quantity), requested)
          : requested;

      let status = ITEM_STATUS.APPROVED;
      if (approved <= 0) status = ITEM_STATUS.REJECTED;
      else if (approved < requested) status = ITEM_STATUS.PARTIALLY_APPROVED;

      await tx.pharmacy_stock_order_item.update({
        where: { id: item.id },
        data: {
          approved_quantity: approved,
          status,
          ...(entry?.notes !== undefined ? { notes: entry.notes || null } : {}),
        },
      });

      nextItems.push({ ...item, approved_quantity: approved, status });
    }

    const status = rejectAll ? STATUS.REJECTED : rollupReviewStatus(nextItems);

    await tx.pharmacy_stock_order.update({
      where: { id: existing.id },
      data: {
        status,
        reviewed_by_user_id: user?.id || null,
        reviewed_at: reviewedAt,
        review_notes: payload.review_notes || null,
      },
    });

    return tx.pharmacy_stock_order.findFirst({
      where: { id: existing.id },
      include: ORDER_INCLUDE,
    });
  });

  audit(updated, user, 'UPDATE', { before: existing, after: updated }, ipAddress);
  return updated;
};

/**
 * Issue approved stock out of the supplying pharmacy.
 *
 * This is the first balance change of the workflow. The supplying pharmacy's
 * quantity drops and a TRANSFER movement is written; the requesting pharmacy
 * does not gain the stock until it records receipt.
 *
 * Each line is priced at the supplying pharmacy's supply price, never its
 * walk-in price (requirement 9).
 *
 * @param {string} identifier - Order identifier
 * @param {Object} payload - Per-line issued quantities
 * @param {Object} user - Request user context
 * @param {string} [ipAddress] - Caller IP for the audit log
 * @returns {Promise<Object>} Issued order
 */
const issueStockOrder = async (identifier, payload = {}, user = {}, ipAddress = null) => {
  const scope = resolveScope(user);
  const existing = await requireStockOrder(prisma, identifier, scope);

  assertTransition(ISSUABLE_STATUSES.has(existing.status), {
    from: existing.status,
    reason: 'order_is_not_approved',
  });

  await assertLocationAccess(prisma, {
    location: existing.supplying_location,
    user,
    level: ACCESS_LEVELS.MANAGE,
  });

  const issuedAt = payload.issued_at ? new Date(payload.issued_at) : new Date();
  const transferGroupId = existing.transfer_group_id || randomUUID();

  const updated = await prisma.$transaction(async (tx) => {
    let supplyTotal = 0;
    let currency = existing.currency || null;
    let issuedAnything = false;

    for (const item of existing.items || []) {
      if (item.status === ITEM_STATUS.REJECTED || item.status === ITEM_STATUS.CANCELLED) {
        continue;
      }

      const entry = (payload.items || []).find((candidate) => matchItem([item], candidate));
      const approved = toPositiveInt(item.approved_quantity);
      const issueQuantity =
        entry && entry.issued_quantity !== undefined
          ? Math.min(toPositiveInt(entry.issued_quantity), approved)
          : approved;

      if (issueQuantity <= 0) continue;

      if (!item.inventory_item_id) {
        throw new HttpError('errors.pharmacy_workspace.inventory_map.required', 400, [
          { stock_order_item_id: item.id, drug_id: item.drug_id },
        ]);
      }

      await issueStockToLocation(tx, {
        fromLocation: existing.supplying_location,
        toLocation: existing.requesting_location,
        inventoryItemId: item.inventory_item_id,
        quantity: issueQuantity,
        transferGroupId,
        occurredAt: issuedAt,
      });

      const price = await requireSupplyPrice(tx, {
        supplyingLocation: existing.supplying_location,
        drug: item.drug,
      });
      currency = currency || price.currency;
      supplyTotal += Number(price.unit_price) * issueQuantity;

      await tx.pharmacy_stock_order_item.update({
        where: { id: item.id },
        data: {
          issued_quantity: issueQuantity,
          unit_supply_price: price.unit_price,
          currency: price.currency,
          status: ITEM_STATUS.ISSUED,
        },
      });

      issuedAnything = true;
    }

    assertTransition(issuedAnything, { reason: 'nothing_to_issue' });

    await tx.pharmacy_stock_order.update({
      where: { id: existing.id },
      data: {
        status: STATUS.ISSUED,
        issued_by_user_id: user?.id || null,
        issued_at: issuedAt,
        transfer_group_id: transferGroupId,
        supply_total: supplyTotal.toFixed(2),
        currency,
        ...(payload.notes ? { review_notes: payload.notes } : {}),
      },
    });

    return tx.pharmacy_stock_order.findFirst({
      where: { id: existing.id },
      include: ORDER_INCLUDE,
    });
  });

  audit(updated, user, 'UPDATE', { before: existing, after: updated }, ipAddress);
  return updated;
};

/**
 * Receive issued stock into the requesting pharmacy.
 *
 * Second balance change. Receiving less than was issued leaves the order
 * PARTIALLY_RECEIVED so the shortfall stays visible instead of disappearing.
 *
 * @param {string} identifier - Order identifier
 * @param {Object} payload - Per-line received quantities
 * @param {Object} user - Request user context
 * @param {string} [ipAddress] - Caller IP for the audit log
 * @returns {Promise<Object>} Received order
 */
const receiveStockOrder = async (identifier, payload = {}, user = {}, ipAddress = null) => {
  const scope = resolveScope(user);
  const existing = await requireStockOrder(prisma, identifier, scope);

  assertTransition(RECEIVABLE_STATUSES.has(existing.status), {
    from: existing.status,
    reason: 'order_has_not_been_issued',
  });

  // Only the requesting pharmacy books the delivery into its own balance.
  await assertLocationAccess(prisma, {
    location: existing.requesting_location,
    user,
    level: ACCESS_LEVELS.DISPENSE,
  });

  const receivedAt = payload.received_at ? new Date(payload.received_at) : new Date();

  const updated = await prisma.$transaction(async (tx) => {
    const nextItems = [];

    for (const item of existing.items || []) {
      const issued = toPositiveInt(item.issued_quantity);
      const alreadyReceived = toPositiveInt(item.received_quantity);
      const outstanding = Math.max(0, issued - alreadyReceived);

      if (outstanding <= 0) {
        nextItems.push(item);
        continue;
      }

      const entry = (payload.items || []).find((candidate) => matchItem([item], candidate));
      const receiveQuantity =
        entry && entry.received_quantity !== undefined
          ? Math.min(toPositiveInt(entry.received_quantity), outstanding)
          : outstanding;

      if (receiveQuantity <= 0) {
        nextItems.push(item);
        continue;
      }

      await receiveStockAtLocation(tx, {
        fromLocation: existing.supplying_location,
        toLocation: existing.requesting_location,
        inventoryItemId: item.inventory_item_id,
        quantity: receiveQuantity,
        transferGroupId: existing.transfer_group_id,
        occurredAt: receivedAt,
      });

      const totalReceived = alreadyReceived + receiveQuantity;

      // The supply price is what this pharmacy paid, so it becomes its
      // acquisition cost - not the supplier's walk-in price, and never its own
      // selling price.
      if (item.unit_supply_price !== null && item.unit_supply_price !== undefined) {
        const existingPrice = await tx.pharmacy_location_price.findFirst({
          where: {
            deleted_at: null,
            pharmacy_location_id: existing.requesting_location_id,
            drug_id: item.drug_id,
          },
        });

        if (existingPrice) {
          await tx.pharmacy_location_price.update({
            where: { id: existingPrice.id },
            data: { acquisition_cost: item.unit_supply_price },
          });
        } else {
          const row = {
            tenant_id: existing.tenant_id,
            pharmacy_location_id: existing.requesting_location_id,
            drug_id: item.drug_id,
            acquisition_cost: item.unit_supply_price,
            currency: item.currency || existing.currency || null,
          };
          await prisma.assignFriendlyIdIfMissing('pharmacy_location_price', row);
          await tx.pharmacy_location_price.create({ data: row });
        }
      }

      await tx.pharmacy_stock_order_item.update({
        where: { id: item.id },
        data: {
          received_quantity: totalReceived,
          status: totalReceived >= issued ? ITEM_STATUS.RECEIVED : ITEM_STATUS.ISSUED,
        },
      });

      nextItems.push({ ...item, received_quantity: totalReceived });
    }

    const status = rollupReceiveStatus(nextItems);

    await tx.pharmacy_stock_order.update({
      where: { id: existing.id },
      data: {
        status,
        received_by_user_id: user?.id || null,
        received_at: status === STATUS.RECEIVED ? receivedAt : existing.received_at,
      },
    });

    return tx.pharmacy_stock_order.findFirst({
      where: { id: existing.id },
      include: ORDER_INCLUDE,
    });
  });

  audit(updated, user, 'UPDATE', { before: existing, after: updated }, ipAddress);
  return updated;
};

/**
 * Cancel an order that has not yet moved stock.
 *
 * Once stock has been issued the transfer must be received (or reversed as its
 * own movement) rather than cancelled, so the two legs always balance.
 *
 * @param {string} identifier - Order identifier
 * @param {Object} payload - `{ reason }`
 * @param {Object} user - Request user context
 * @param {string} [ipAddress] - Caller IP for the audit log
 * @returns {Promise<Object>} Cancelled order
 */
const cancelStockOrder = async (identifier, payload = {}, user = {}, ipAddress = null) => {
  const scope = resolveScope(user);
  const existing = await requireStockOrder(prisma, identifier, scope);

  assertTransition(CANCELLABLE_STATUSES.has(existing.status), {
    from: existing.status,
    reason: 'issued_orders_must_be_received_not_cancelled',
  });

  // Either party may call it off before any stock has moved.
  const grants = await loadUserLocationGrants(prisma, {
    userId: user?.id,
    tenantId: scope.tenant_id,
  });
  if (!hasTenantWideAccess(user)) {
    const isParty =
      grants.has(String(existing.requesting_location_id)) ||
      grants.has(String(existing.supplying_location_id));
    if (!isParty) {
      throw new HttpError('errors.pharmacy_location.access_denied', 403, [
        { pharmacy_stock_order_id: existing.id },
      ]);
    }
  }

  const cancelledAt = new Date();
  const updated = await prisma.$transaction(async (tx) => {
    await tx.pharmacy_stock_order_item.updateMany({
      where: { stock_order_id: existing.id, deleted_at: null },
      data: { status: ITEM_STATUS.CANCELLED },
    });
    await tx.pharmacy_stock_order.update({
      where: { id: existing.id },
      data: {
        status: STATUS.CANCELLED,
        cancelled_at: cancelledAt,
        review_notes: payload.reason || existing.review_notes,
      },
    });
    return tx.pharmacy_stock_order.findFirst({
      where: { id: existing.id },
      include: ORDER_INCLUDE,
    });
  });

  audit(updated, user, 'UPDATE', { before: existing, after: updated }, ipAddress);
  return updated;
};

module.exports = {
  STATUS,
  ITEM_STATUS,
  listStockOrders,
  getStockOrder,
  createStockOrder,
  updateStockOrder,
  submitStockOrder,
  reviewStockOrder,
  issueStockOrder,
  receiveStockOrder,
  cancelStockOrder,
  rollupReviewStatus,
  rollupReceiveStatus,
  findLocationStock,
};
