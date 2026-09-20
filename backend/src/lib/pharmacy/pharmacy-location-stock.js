/**
 * Pharmacy location stock
 *
 * @module lib/pharmacy
 * @description Reading and moving a balance that belongs to one pharmacy.
 *
 * Every balance is a row keyed on `(inventory_item_id, pharmacy_location_id)`.
 * Main Pharmacy and Hospital Pharmacy therefore hold two rows for the same
 * catalog item and their quantities never pool, which is requirement 2.
 *
 * Stock moves only through `issueStockToLocation` and `receiveStockAtLocation`.
 * They are the two legs of one transfer, share a `transfer_group_id`, and are
 * the only writers of a cross-pharmacy quantity change: creating or approving a
 * stock order deliberately leaves inventory untouched (requirement 6).
 */

const { HttpError } = require('@lib/errors');

const delegateFor = (client, model) => {
  const delegate = client?.[model];
  return delegate && typeof delegate.findFirst === 'function' ? delegate : null;
};

const toPositiveInt = (value) => {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return 0;
  return Math.max(0, Math.trunc(numeric));
};

/**
 * Find the balance a pharmacy holds for an inventory item.
 *
 * @param {Object} client - Prisma client or transaction
 * @param {Object} params
 * @param {string} params.inventoryItemId - Inventory item
 * @param {string} params.pharmacyLocationId - Pharmacy holding the balance
 * @returns {Promise<Object|null>} Stock row, or null when the pharmacy has none
 */
const findLocationStock = async (client, { inventoryItemId, pharmacyLocationId }) => {
  const delegate = delegateFor(client, 'inventory_stock');
  if (!delegate || !inventoryItemId || !pharmacyLocationId) return null;

  return delegate.findFirst({
    where: {
      deleted_at: null,
      inventory_item_id: inventoryItemId,
      pharmacy_location_id: pharmacyLocationId,
    },
  });
};

/**
 * Find a pharmacy's balance, creating an empty one when it has never held the
 * item.
 *
 * A receiving pharmacy needs a row before its first delivery; creating it at
 * zero keeps the quantity change itself auditable as a movement.
 *
 * @param {Object} client - Prisma client or transaction
 * @param {Object} params
 * @param {string} params.inventoryItemId - Inventory item
 * @param {Object} params.location - Pharmacy location row
 * @returns {Promise<Object>} Existing or newly created stock row
 */
const ensureLocationStock = async (client, { inventoryItemId, location }) => {
  const existing = await findLocationStock(client, {
    inventoryItemId,
    pharmacyLocationId: location?.id,
  });
  if (existing) return existing;

  const delegate = client?.inventory_stock;
  if (!delegate || typeof delegate.create !== 'function') {
    throw new HttpError('errors.pharmacy_workspace.stock.not_found', 404, [
      { inventory_item_id: inventoryItemId },
    ]);
  }

  const row = {
    inventory_item_id: inventoryItemId,
    facility_id: location?.facility_id || null,
    pharmacy_location_id: location?.id || null,
    quantity: 0,
    reorder_level: 0,
  };

  // Nested/createMany paths do not always run HFID middleware - assign here.
  if (typeof client.assignFriendlyIdIfMissing === 'function') {
    await client.assignFriendlyIdIfMissing('inventory_stock', row);
  }

  return delegate.create({ data: row });
};

/**
 * Record one stock movement leg.
 *
 * @param {Object} client - Prisma client or transaction
 * @param {Object} params - Movement fields
 * @returns {Promise<Object>} Created movement row
 */
const recordMovement = async (client, params) => {
  const delegate = client?.stock_movement;
  if (!delegate || typeof delegate.create !== 'function') return null;

  const row = {
    inventory_item_id: params.inventoryItemId,
    facility_id: params.facilityId || null,
    from_facility_id: params.fromFacilityId || null,
    to_facility_id: params.toFacilityId || null,
    pharmacy_location_id: params.pharmacyLocationId || null,
    from_pharmacy_location_id: params.fromPharmacyLocationId || null,
    to_pharmacy_location_id: params.toPharmacyLocationId || null,
    transfer_group_id: params.transferGroupId || null,
    movement_type: params.movementType,
    reason: params.reason,
    quantity: toPositiveInt(params.quantity),
    occurred_at: params.occurredAt || new Date(),
  };

  if (typeof client.assignFriendlyIdIfMissing === 'function') {
    await client.assignFriendlyIdIfMissing('stock_movement', row);
  }

  return delegate.create({ data: row });
};

/**
 * Take stock out of the supplying pharmacy.
 *
 * This is the first leg of a transfer: the supplier's balance drops now, and
 * the requester's balance only rises when it records receipt. Between the two
 * legs the quantity is in transit and belongs to neither balance, which is why
 * `transfer_group_id` links them.
 *
 * @param {Object} client - Prisma transaction
 * @param {Object} params
 * @param {Object} params.fromLocation - Pharmacy issuing the stock
 * @param {Object} params.toLocation - Pharmacy the stock is destined for
 * @param {string} params.inventoryItemId - Inventory item
 * @param {number} params.quantity - Units to issue
 * @param {string} params.transferGroupId - Links this leg to the receipt
 * @param {Date} [params.occurredAt] - Movement timestamp
 * @returns {Promise<{stock: Object, movement: Object}>} Updated balance and leg
 * @throws {HttpError} 400 when the supplying pharmacy lacks the quantity
 */
const issueStockToLocation = async (
  client,
  { fromLocation, toLocation, inventoryItemId, quantity, transferGroupId, occurredAt = new Date() }
) => {
  const units = toPositiveInt(quantity);
  if (units <= 0) {
    throw new HttpError('errors.validation.invalid', 400, [{ field: 'quantity' }]);
  }

  const stock = await findLocationStock(client, {
    inventoryItemId,
    pharmacyLocationId: fromLocation?.id,
  });
  if (!stock) {
    throw new HttpError('errors.pharmacy_workspace.stock.not_found', 404, [
      { inventory_item_id: inventoryItemId, pharmacy_location_id: fromLocation?.id || null },
    ]);
  }

  const available = Number(stock.quantity || 0);
  if (available < units) {
    throw new HttpError('errors.pharmacy_location_stock.insufficient', 400, [
      {
        inventory_item_id: inventoryItemId,
        pharmacy_location_id: fromLocation?.id || null,
        available,
        required: units,
      },
    ]);
  }

  const updated = await client.inventory_stock.update({
    where: { id: stock.id },
    data: { quantity: available - units },
  });

  const movement = await recordMovement(client, {
    inventoryItemId,
    facilityId: fromLocation?.facility_id || null,
    fromFacilityId: fromLocation?.facility_id || null,
    toFacilityId: toLocation?.facility_id || null,
    pharmacyLocationId: fromLocation?.id || null,
    fromPharmacyLocationId: fromLocation?.id || null,
    toPharmacyLocationId: toLocation?.id || null,
    transferGroupId,
    movementType: 'TRANSFER',
    reason: 'OTHER',
    quantity: units,
    occurredAt,
  });

  return { stock: updated, movement };
};

/**
 * Bring stock into the receiving pharmacy.
 *
 * Second leg of the transfer. Receiving less than was issued is allowed - the
 * shortfall stays visible as the gap between the two legs of the group rather
 * than being silently written off.
 *
 * @param {Object} client - Prisma transaction
 * @param {Object} params
 * @param {Object} params.fromLocation - Pharmacy that issued the stock
 * @param {Object} params.toLocation - Pharmacy receiving it
 * @param {string} params.inventoryItemId - Inventory item
 * @param {number} params.quantity - Units received
 * @param {string} params.transferGroupId - Links this leg to the issue
 * @param {Date} [params.occurredAt] - Movement timestamp
 * @returns {Promise<{stock: Object, movement: Object}>} Updated balance and leg
 */
const receiveStockAtLocation = async (
  client,
  { fromLocation, toLocation, inventoryItemId, quantity, transferGroupId, occurredAt = new Date() }
) => {
  const units = toPositiveInt(quantity);
  if (units <= 0) {
    throw new HttpError('errors.validation.invalid', 400, [{ field: 'quantity' }]);
  }

  const stock = await ensureLocationStock(client, { inventoryItemId, location: toLocation });

  const updated = await client.inventory_stock.update({
    where: { id: stock.id },
    data: { quantity: Number(stock.quantity || 0) + units },
  });

  const movement = await recordMovement(client, {
    inventoryItemId,
    facilityId: toLocation?.facility_id || null,
    fromFacilityId: fromLocation?.facility_id || null,
    toFacilityId: toLocation?.facility_id || null,
    pharmacyLocationId: toLocation?.id || null,
    fromPharmacyLocationId: fromLocation?.id || null,
    toPharmacyLocationId: toLocation?.id || null,
    transferGroupId,
    movementType: 'TRANSFER',
    reason: 'OTHER',
    quantity: units,
    occurredAt,
  });

  return { stock: updated, movement };
};

/**
 * Availability of an inventory item across the pharmacies of a facility.
 *
 * Powers the Hospital Pharmacy's read-only "Main Pharmacy available" column.
 *
 * @param {Object} client - Prisma client or transaction
 * @param {Object} params
 * @param {string[]} params.inventoryItemIds - Items to report on
 * @param {string[]} params.pharmacyLocationIds - Pharmacies to report on
 * @returns {Promise<Map<string, Map<string, Object>>>} item id -> location id -> stock
 */
const loadStockMatrix = async (client, { inventoryItemIds = [], pharmacyLocationIds = [] }) => {
  const matrix = new Map();
  const delegate = client?.inventory_stock;
  if (!delegate || typeof delegate.findMany !== 'function') return matrix;
  if (!inventoryItemIds.length || !pharmacyLocationIds.length) return matrix;

  const rows = await delegate.findMany({
    where: {
      deleted_at: null,
      inventory_item_id: { in: inventoryItemIds },
      pharmacy_location_id: { in: pharmacyLocationIds },
    },
  });

  for (const row of Array.isArray(rows) ? rows : []) {
    const itemKey = String(row.inventory_item_id);
    if (!matrix.has(itemKey)) matrix.set(itemKey, new Map());
    matrix.get(itemKey).set(String(row.pharmacy_location_id), row);
  }

  return matrix;
};

module.exports = {
  findLocationStock,
  ensureLocationStock,
  issueStockToLocation,
  receiveStockAtLocation,
  loadStockMatrix,
  recordMovement,
  toPositiveInt,
};
