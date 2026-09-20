const prisma = require('@prisma/client');
const { HttpError } = require('@lib/errors');

const withDbErrorHandling = async (operation) => {
  try {
    return await operation();
  } catch (error) {
    if (error instanceof HttpError) {
      throw error;
    }
    if (error?.code === 'P2025') {
      throw new HttpError('errors.resource.not_found', 404);
    }
    if (error?.code === 'P2002') {
      const target = error.meta?.target?.[0] || 'field';
      throw new HttpError('errors.database.unique_field', 409, [{ field: target }]);
    }
    if (error?.code === 'P2003') {
      const target = error.meta?.field_name || 'field';
      throw new HttpError('errors.database.foreign_key_field', 400, [{ field: target }]);
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

const findManyOrders = async (where, skip, take, orderBy, include) =>
  withDbErrorHandling(() =>
    prisma.pharmacy_order.findMany({
      where: { deleted_at: null, ...(where || {}) },
      skip,
      take,
      orderBy,
      include})
  );

const countOrders = async (where) =>
  withDbErrorHandling(() =>
    prisma.pharmacy_order.count({
      where: { deleted_at: null, ...(where || {}) }})
  );

const findOrderById = async (id, include) =>
  withDbErrorHandling(() =>
    prisma.pharmacy_order.findFirst({
      where: { id, deleted_at: null },
      include})
  );

const countDispenseAttestations = async (where) =>
  withDbErrorHandling(() =>
    prisma.pharmacy_dispense_attestation.count({
      where: { deleted_at: null, ...(where || {}) }})
  );

const findManyInventoryStocks = async (where, skip, take, orderBy, include) =>
  withDbErrorHandling(() =>
    prisma.inventory_stock.findMany({
      where: { deleted_at: null, ...(where || {}) },
      skip,
      take,
      orderBy,
      include})
  );

const countInventoryStocks = async (where) =>
  withDbErrorHandling(() =>
    prisma.inventory_stock.count({
      where: { deleted_at: null, ...(where || {}) }})
  );

const findInventoryStockMetrics = async (where) =>
  withDbErrorHandling(() =>
    prisma.inventory_stock.findMany({
      where: { deleted_at: null, ...(where || {}) },
      select: {
        quantity: true,
        reorder_level: true}})
  );

const findManyDrugs = async (where, skip, take, orderBy, include) =>
  withDbErrorHandling(() =>
    prisma.drug.findMany({
      where: { deleted_at: null, ...(where || {}) },
      skip,
      take,
      orderBy,
      include})
  );

const countDrugs = async (where) =>
  withDbErrorHandling(() =>
    prisma.drug.count({
      where: { deleted_at: null, ...(where || {}) }})
  );

const withTransaction = async (callback, options = undefined) =>
  withDbErrorHandling(() => prisma.$transaction((tx) => callback(tx), options));

/**
 * Tenant drugs with the inventory stock held at one facility, for import matching.
 */
const findDrugsForImport = async (tenantId, facilityId) =>
  withDbErrorHandling(() =>
    prisma.drug.findMany({
      where: { deleted_at: null, tenant_id: tenantId },
      orderBy: { updated_at: 'desc' },
      select: {
        id: true,
        human_friendly_id: true,
        name: true,
        generic_name: true,
        brand_name: true,
        code: true,
        form: true,
        strength: true,
        buy_unit_price: true,
        unit_price: true,
        currency: true,
        supplier_id: true,
        supplier: { select: { name: true } },
        inventory_maps: {
          where: { deleted_at: null },
          select: {
            inventory_item_id: true,
            inventory_item: {
              select: {
                stocks: {
                  where: { deleted_at: null, facility_id: facilityId },
                  select: { quantity: true }}}}}}}})
  );

const findSuppliersForImport = async (tenantId) =>
  withDbErrorHandling(() =>
    prisma.supplier.findMany({
      where: { deleted_at: null, tenant_id: tenantId },
      select: { id: true, name: true }})
  );

const findFacilityForImport = async (facilityId, tenantId) =>
  withDbErrorHandling(() =>
    prisma.facility.findFirst({
      where: { id: facilityId, tenant_id: tenantId, deleted_at: null },
      select: { id: true, human_friendly_id: true, name: true }})
  );

const txFindOrderById = async (tx, id, include) =>
  tx.pharmacy_order.findFirst({
    where: { id, deleted_at: null },
    include});

const txUpdateOrder = async (tx, id, data) =>
  tx.pharmacy_order.update({
    where: { id },
    data});

const txUpdateOrderItem = async (tx, id, data) =>
  tx.pharmacy_order_item.update({
    where: { id },
    data});

const txFindStockByInventoryItemAndFacility = async (tx, inventoryItemId, facilityId = null, include) =>
  tx.inventory_stock.findFirst({
    where: {
      deleted_at: null,
      inventory_item_id: inventoryItemId,
      facility_id: facilityId},
    include});

const txCreateInventoryStock = async (tx, data) =>
  tx.inventory_stock.create({
    data});

const txUpdateInventoryStock = async (tx, id, data) =>
  tx.inventory_stock.update({
    where: { id },
    data});

const txCreateStockMovement = async (tx, data) =>
  tx.stock_movement.create({
    data});

const txCreateDispenseLog = async (tx, data) =>
  tx.dispense_log.create({
    data});

const txUpdateDispenseLog = async (tx, id, data) =>
  tx.dispense_log.update({
    where: { id },
    data});

const txUpdateManyDispenseLogs = async (tx, where, data) =>
  tx.dispense_log.updateMany({
    where: { deleted_at: null, ...(where || {}) },
    data});

const txFindDispenseLogsByBatch = async (tx, pharmacyOrderId, batchRef, include = undefined) =>
  tx.dispense_log.findMany({
    where: {
      deleted_at: null,
      dispense_batch_ref: batchRef,
      pharmacy_order_item: {
        deleted_at: null,
        pharmacy_order_id: pharmacyOrderId}},
    orderBy: { created_at: 'asc' },
    include});

const txCreateDispenseAttestation = async (tx, data) =>
  tx.pharmacy_dispense_attestation.create({
    data});

const txSoftDeleteDispenseAttestation = async (tx, id, deletedAt = new Date()) =>
  tx.pharmacy_dispense_attestation.update({
    where: { id },
    data: { deleted_at: deletedAt }});

const txFindDispenseAttestation = async (tx, pharmacyOrderId, batchRef, phase) =>
  tx.pharmacy_dispense_attestation.findFirst({
    where: {
      deleted_at: null,
      pharmacy_order_id: pharmacyOrderId,
      dispense_batch_ref: batchRef,
      phase},
    orderBy: { created_at: 'desc' }});

const txFindManyDispenseAttestations = async (tx, where, orderBy = { created_at: 'desc' }) =>
  tx.pharmacy_dispense_attestation.findMany({
    where: { deleted_at: null, ...(where || {}) },
    orderBy});

const txFindInventoryMapByDrug = async (tx, drugId, tenantId = null) =>
  tx.drug_inventory_map.findFirst({
    where: {
      deleted_at: null,
      drug_id: drugId,
      ...(tenantId ? { tenant_id: tenantId } : {})},
    orderBy: [{ is_default: 'desc' }, { created_at: 'asc' }],
    include: {
      inventory_item: true}});

const txFindInventoryMapByDrugAndItem = async (tx, drugId, inventoryItemId, tenantId = null) =>
  tx.drug_inventory_map.findFirst({
    where: {
      deleted_at: null,
      drug_id: drugId,
      inventory_item_id: inventoryItemId,
      ...(tenantId ? { tenant_id: tenantId } : {})},
    include: {
      inventory_item: true}});

const findDrugInventoryMapsByInventoryItemIds = async (inventoryItemIds = []) =>
  withDbErrorHandling(() => {
    const normalized = Array.from(
      new Set((inventoryItemIds || []).filter((value) => Boolean(value)))
    );
    if (!normalized.length) return [];
    return prisma.drug_inventory_map.findMany({
      where: {
        deleted_at: null,
        inventory_item_id: { in: normalized }},
      select: {
        drug_id: true,
        inventory_item_id: true}});
  });

const findDrugBatchesByDrugIds = async (drugIds = []) =>
  withDbErrorHandling(() => {
    const normalized = Array.from(new Set((drugIds || []).filter((value) => Boolean(value))));
    if (!normalized.length) return [];
    return prisma.drug_batch.findMany({
      where: {
        deleted_at: null,
        drug_id: { in: normalized }},
      select: {
        id: true,
        drug_id: true,
        batch_number: true,
        expiry_date: true,
        quantity: true}});
  });

const findInventoryItemIdsByBatchFilters = async (tenantId, filters = {}) =>
  withDbErrorHandling(async () => {
    const now = new Date();
    const batchWhere = { deleted_at: null };

    if (filters.expired_only === true) {
      batchWhere.expiry_date = { lt: now };
    } else if (filters.expiring_within_days) {
      const horizon = new Date(now);
      horizon.setDate(horizon.getDate() + Number(filters.expiring_within_days));
      batchWhere.expiry_date = {
        gte: now,
        lte: horizon};
    } else {
      return null;
    }

    const batches = await prisma.drug_batch.findMany({
      where: batchWhere,
      select: { drug_id: true }});
    const drugIds = Array.from(new Set(batches.map((row) => row.drug_id).filter(Boolean)));
    if (!drugIds.length) return [];

    const maps = await prisma.drug_inventory_map.findMany({
      where: {
        deleted_at: null,
        tenant_id: tenantId,
        drug_id: { in: drugIds }},
      select: { inventory_item_id: true }});

    return Array.from(new Set(maps.map((row) => row.inventory_item_id).filter(Boolean)));
  });

const countInventoryRowsWithExpiringBatches = async (tenantId, facilityId, days = 30) =>
  withDbErrorHandling(async () => {
    const now = new Date();
    const horizon = new Date(now);
    horizon.setDate(horizon.getDate() + Number(days));

    const batches = await prisma.drug_batch.findMany({
      where: {
        deleted_at: null,
        quantity: { gt: 0 },
        expiry_date: {
          gte: now,
          lte: horizon}},
      select: { drug_id: true }});
    const drugIds = Array.from(new Set(batches.map((row) => row.drug_id).filter(Boolean)));
    if (!drugIds.length) return 0;

    const maps = await prisma.drug_inventory_map.findMany({
      where: {
        deleted_at: null,
        tenant_id: tenantId,
        drug_id: { in: drugIds }},
      select: { inventory_item_id: true }});
    const inventoryItemIds = Array.from(
      new Set(maps.map((row) => row.inventory_item_id).filter(Boolean))
    );
    if (!inventoryItemIds.length) return 0;

    return prisma.inventory_stock.count({
      where: {
        deleted_at: null,
        inventory_item_id: { in: inventoryItemIds },
        ...(facilityId ? { facility_id: facilityId } : {})}});
  });

const countInventoryRowsWithExpiredBatches = async (tenantId, facilityId) =>
  withDbErrorHandling(async () => {
    const now = new Date();

    const batches = await prisma.drug_batch.findMany({
      where: {
        deleted_at: null,
        quantity: { gt: 0 },
        expiry_date: { lt: now }},
      select: { drug_id: true }});
    const drugIds = Array.from(new Set(batches.map((row) => row.drug_id).filter(Boolean)));
    if (!drugIds.length) return 0;

    const maps = await prisma.drug_inventory_map.findMany({
      where: {
        deleted_at: null,
        tenant_id: tenantId,
        drug_id: { in: drugIds }},
      select: { inventory_item_id: true }});
    const inventoryItemIds = Array.from(
      new Set(maps.map((row) => row.inventory_item_id).filter(Boolean))
    );
    if (!inventoryItemIds.length) return 0;

    return prisma.inventory_stock.count({
      where: {
        deleted_at: null,
        inventory_item_id: { in: inventoryItemIds },
        ...(facilityId ? { facility_id: facilityId } : {})}});
  });

const txCreateDrug = async (tx, data) => tx.drug.create({ data });

const txCreateInventoryItem = async (tx, data) => tx.inventory_item.create({ data });

const txCreateDrugInventoryMap = async (tx, data) => tx.drug_inventory_map.create({ data });

/**
 * Find a batch of a drug, within one pharmacy when a location is given.
 *
 * Batch numbers repeat across pharmacies, so an unscoped lookup would let the
 * Hospital Pharmacy write into a Main Pharmacy batch row.
 *
 * @param {Object} tx - Prisma transaction
 * @param {string} drugId - Catalog drug
 * @param {string} batchNumber - Batch number
 * @param {string|null} [pharmacyLocationId] - Pharmacy holding the batch
 * @returns {Promise<Object|null>} Batch row or null
 */
const txFindDrugBatchByDrugAndNumber = async (
  tx,
  drugId,
  batchNumber,
  pharmacyLocationId = null
) =>
  tx.drug_batch.findFirst({
    where: {
      deleted_at: null,
      drug_id: drugId,
      batch_number: batchNumber,
      ...(pharmacyLocationId ? { pharmacy_location_id: pharmacyLocationId } : {})}});

const txCreateDrugBatch = async (tx, data) => tx.drug_batch.create({ data });

const txUpdateDrugBatch = async (tx, id, data) =>
  tx.drug_batch.update({
    where: { id },
    data});

const txUpdateDrug = async (tx, id, data) =>
  tx.drug.update({
    where: { id },
    data});

const txCreateSupplier = async (tx, data) => tx.supplier.create({ data });

const txFindDrugBatchesByDrug = async (tx, drugId) =>
  tx.drug_batch.findMany({
    where: { deleted_at: null, drug_id: drugId },
    select: {
      id: true,
      batch_number: true,
      quantity: true,
      storage_room: { select: { facility_id: true } }}});

const txFindInventoryMapByInventoryItem = async (tx, inventoryItemId, tenantId = null) =>
  tx.drug_inventory_map.findFirst({
    where: {
      deleted_at: null,
      inventory_item_id: inventoryItemId,
      ...(tenantId ? { tenant_id: tenantId } : {})},
    orderBy: [{ is_default: 'desc' }, { created_at: 'asc' }]});

module.exports = {
  findManyOrders,
  countOrders,
  findOrderById,
  countDispenseAttestations,
  findManyInventoryStocks,
  countInventoryStocks,
  findInventoryStockMetrics,
  findManyDrugs,
  countDrugs,
  withTransaction,
  findDrugsForImport,
  findSuppliersForImport,
  findFacilityForImport,
  txFindOrderById,
  txUpdateOrder,
  txUpdateOrderItem,
  txFindStockByInventoryItemAndFacility,
  txCreateInventoryStock,
  txUpdateInventoryStock,
  txCreateStockMovement,
  txCreateDispenseLog,
  txUpdateDispenseLog,
  txUpdateManyDispenseLogs,
  txFindDispenseLogsByBatch,
  txCreateDispenseAttestation,
  txSoftDeleteDispenseAttestation,
  txFindDispenseAttestation,
  txFindManyDispenseAttestations,
  txFindInventoryMapByDrug,
  txFindInventoryMapByDrugAndItem,
  findDrugInventoryMapsByInventoryItemIds,
  findDrugBatchesByDrugIds,
  findInventoryItemIdsByBatchFilters,
  countInventoryRowsWithExpiringBatches,
  countInventoryRowsWithExpiredBatches,
  txCreateDrug,
  txCreateInventoryItem,
  txCreateDrugInventoryMap,
  txFindDrugBatchByDrugAndNumber,
  txCreateDrugBatch,
  txUpdateDrugBatch,
  txUpdateDrug,
  txCreateSupplier,
  txFindDrugBatchesByDrug,
  txFindInventoryMapByInventoryItem};
