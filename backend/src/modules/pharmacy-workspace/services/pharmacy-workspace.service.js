
const crypto = require('crypto');
const { createAuditLog } = require('@lib/audit');
const { HttpError } = require('@lib/errors');
const { normalizeIdentifier } = require('@lib/identifiers/resolve-entity-id');
const { isUuidLike } = require('@lib/identifiers/sanitize-friendly-ids');
const prisma = require('@prisma/client');
const pharmacyWorkspaceRepository = require('@repositories/pharmacy-workspace/pharmacy-workspace.repository');
const pharmacyStorageRepository = require('@repositories/pharmacy-workspace/pharmacy-storage.repository');
const facilityPharmacyCatalogRepository = require('@repositories/facility-pharmacy-catalog/facility-pharmacy-catalog.repository');
const facilityPharmacyCatalogService = require('@services/facility-pharmacy-catalog/facility-pharmacy-catalog.service');
const pharmacyOrderService = require('@services/pharmacy-order/pharmacy-order.service');
const { emitToUsers, PHARMACY_EVENTS, INVENTORY_EVENTS } = require('@lib/websocket');
const {
  reverseClinicalRequestBilling,
  extractStoredClinicalBilling,
  persistPharmacyOrderBilling} = require('@lib/billing/clinical-request-billing');
const {
  assertPharmacyRetailPriceMutationAllowed,
  assertFacilityTariffMutationAllowed,
} = require('@lib/billing/pricing-permissions');
const { ROLES } = require('@config/roles');
const {
  ACCESS_LEVELS,
  findPharmacyLocation,
  findDefaultLocationByKind,
  resolveDispensingLocationForOrigin,
  loadUserLocationGrants,
  assertLocationAccess,
  assertProcurementAccess,
  hasTenantWideAccess} = require('@lib/pharmacy/pharmacy-location-access');
const { assertOrderDispensableAt } = require('@lib/pharmacy/pharmacy-order-routing');
const {
  PHARMACY_ORDER_WITH_RELATIONS_INCLUDE,
  INVENTORY_STOCK_WITH_RELATIONS_INCLUDE,
  INVENTORY_ITEM_PUBLIC_SELECT,
  buildPagination,
  normalizeSearchTerm,
  resolveModelIdOrThrow,
  resolveModelRecordOrThrow,
  toDateOrNull,
  applyDateRangeFilter,
  resolveScopedUserContext,
  buildTenantScopeWhere,
  buildPatientScopeWhere,
  buildEncounterScopeWhere,
  buildDrugScopeWhere,
  buildInventoryItemScopeWhere,
  buildOrderScopeWhere,
  buildOrderItemScopeWhere,
  buildInventoryStockScopeWhere,
  matchesOrderScope,
  matchesInventoryStockScope,
  buildOrderLocationWhere,
  INPATIENT_ENCOUNTER_TYPES,
  PHARMACY_OPEN_ORDER_STATUSES} = require('@services/pharmacy-workspace/pharmacy.shared');
const {
  toPublicIdentifier,
  mapPharmacyOrderRecord,
  mapPharmacyOrderWorkflowRecord,
  mapInventoryStockRecord,
  mapDrugRecord,
  buildBatchMetaByInventoryItemId} = require('@services/pharmacy-workspace/pharmacy.serializer');
const { mapMergedDrugRecord } = require('@services/pharmacy-workspace/facility-pharmacy-catalog.merge');
const {
  resolveStorageAssignment,
  resolveDefaultStorageShelfId,
  attachDrugStorageSummaries,
  getPharmacyStorageLayout,
  checkPharmacyStorageRoomSimilarity,
  checkPharmacyStorageShelfSimilarity,
  createPharmacyStorageRoom,
  updatePharmacyStorageRoom,
  createPharmacyStorageShelf,
  updatePharmacyStorageShelf,
  deletePharmacyStorageRoom,
  restorePharmacyStorageRoom,
  permanentDeletePharmacyStorageRoom,
  deletePharmacyStorageShelf} = require('@services/pharmacy-workspace/pharmacy-storage.service');
const { resolveIdentifierForPayload } = require('@lib/identifiers/service-identifier-resolution');
const { resolveOperationalFacilityId } = require('@lib/facility-context');
const {
  checkPharmacyDrugDuplicates} = require('@lib/pharmacy/pharmacy-drug-similarity');
const drugRepository = require('@repositories/drug/drug.repository');

const DRUG_SIMILARITY_LOOKUP_LIMIT = 500;

const stripDrugSimilarityPayloadFields = (data = {}) => {
  const { confirm_similar: _confirmSimilar, ...payload } = data;
  return payload;
};

const assertPharmacyDrugUniqueness = async ({
  tenantId,
  name,
  genericName,
  brandName,
  code,
  form,
  strength,
  confirmSimilar = false,
  excludeDrugId = null}) => {
  if (!tenantId) {
    return null;
  }

  const existing = await pharmacyWorkspaceRepository.findManyDrugs(
    { tenant_id: tenantId },
    0,
    DRUG_SIMILARITY_LOOKUP_LIMIT,
    { updated_at: 'desc' }
  );

  const duplicateCheck = checkPharmacyDrugDuplicates({
    name,
    genericName,
    brandName,
    code,
    form,
    strength,
    existing,
    excludeDrugId});

  if (!confirmSimilar && duplicateCheck.exactIdentityConflict) {
    throw new HttpError('errors.pharmacy_drug.duplicate_identity', 409, [
      {
        field: 'generic_name',
        matches: duplicateCheck.similarMatches
          .filter((match) => match.exact_identity_conflict)
          .slice(0, 5)}]);
  }

  if (!confirmSimilar && duplicateCheck.exactCodeConflict) {
    throw new HttpError('errors.pharmacy_drug.duplicate_code', 409, [
      {
        field: 'code',
        matches: duplicateCheck.similarMatches
          .filter((match) => match.exact_code_conflict)
          .slice(0, 5)}]);
  }

  const reviewMatches = duplicateCheck.similarMatches
    .filter((match) => !match.is_exact)
    .slice(0, 8);

  if (!confirmSimilar && reviewMatches.length > 0) {
    throw new HttpError('errors.pharmacy_drug.similar_exists', 409, [
      {
        field: 'generic_name',
        matches: reviewMatches,
        closest_score: duplicateCheck.closestScore}]);
  }

  return duplicateCheck;
};

const checkPharmacyDrugSimilarity = async (payload = {}, user = {}) => {
  const scope = resolveScopedUserContext(user);
  let tenantId = scope.tenant_id;
  if (scope.can_manage_all_tenants && payload.tenant_id) {
    tenantId = await resolveIdentifierForPayload({
      value: payload.tenant_id,
      field: 'tenant_id',
      model: 'tenant',
      where: { deleted_at: null }});
  }
  if (!tenantId) {
    throw new HttpError('errors.validation.required', 400, [{ field: 'tenant_id' }]);
  }

  const name = String(payload.name || payload.generic_name || '').trim();
  const genericName = String(payload.generic_name || payload.name || '').trim() || null;
  const brandName = String(payload.brand_name || '').trim() || null;
  const code = String(payload.code || '').trim() || null;
  const form = String(payload.form || '').trim() || null;
  const strength = String(payload.strength || '').trim() || null;
  const excludeDrugId = String(payload.exclude_drug_id || '').trim() || null;

  if (!name && !genericName) {
    throw new HttpError('errors.validation.required', 400, [{ field: 'generic_name' }]);
  }

  const existing = await pharmacyWorkspaceRepository.findManyDrugs(
    { tenant_id: tenantId },
    0,
    DRUG_SIMILARITY_LOOKUP_LIMIT,
    { updated_at: 'desc' }
  );

  let excludeInternalId = null;
  let excludeFriendlyId = null;
  if (excludeDrugId) {
    const existingDrug = await drugRepository.findById(excludeDrugId);
    excludeInternalId = existingDrug?.id || excludeDrugId;
    excludeFriendlyId = existingDrug?.human_friendly_id || null;
  }

  const duplicateCheck = checkPharmacyDrugDuplicates({
    name: name || genericName,
    genericName,
    brandName,
    code,
    form,
    strength,
    existing,
    excludeDrugId: excludeInternalId});

  const excludeKeys = new Set(
    [excludeDrugId, excludeInternalId, excludeFriendlyId]
      .map((value) => String(value || '').trim().toUpperCase())
      .filter(Boolean)
  );

  const filteredMatches = duplicateCheck.similarMatches.filter((match) => {
    if (excludeKeys.size === 0) {
      return true;
    }
    const drug = match.drug || {};
    const drugKeys = [drug.id, drug.human_friendly_id, drug.display_id]
      .map((value) => String(value || '').trim().toUpperCase())
      .filter(Boolean);
    return !drugKeys.some((key) => excludeKeys.has(key));
  });

  const closestScore = filteredMatches.reduce(
    (max, match) => Math.max(max, Number(match.score) || 0),
    0
  );

  return {
    exact_identity_conflict: filteredMatches.some(
      (match) => match.exact_identity_conflict === true
    ),
    exact_code_conflict: filteredMatches.some(
      (match) => match.exact_code_conflict === true
    ),
    closest_score: closestScore,
    matches: filteredMatches.slice(0, 8).map((match) => ({
      ...match,
      drug: mapDrugRecord(match.drug) || match.drug}))};
};

const PHARMACY_RECIPIENT_ROLES = [
  ROLES.PLATFORM_ADMIN,
  ROLES.TENANT_ADMIN,
  ROLES.FACILITY_ADMIN,
  ROLES.PHARMACIST,
  ROLES.DOCTOR,
  ROLES.NURSE,
  ROLES.OPERATIONS];

const LEGACY_ROUTE_CONFIG = Object.freeze({
  'pharmacy-orders': {
    model: 'pharmacy_order',
    resource: 'orders',
    route: '/pharmacy/orders'},
  'pharmacy-order-items': {
    model: 'pharmacy_order_item',
    resource: 'order-items',
    route: '/pharmacy/order-items'},
  'dispense-logs': {
    model: 'dispense_log',
    resource: 'dispense-logs',
    route: '/pharmacy/dispense-logs'},
  'inventory-items': {
    model: 'inventory_item',
    resource: 'inventory-items',
    route: '/pharmacy?panel=inventory&item='},
  'inventory-stocks': {
    model: 'inventory_stock',
    resource: 'inventory-stock',
    route: '/pharmacy?panel=inventory&stock='},
  'stock-movements': {
    model: 'stock_movement',
    resource: 'stock-movements',
    route: '/pharmacy?panel=inventory&movement='},
  drugs: {
    model: 'drug',
    resource: 'drugs',
    route: '/pharmacy/drugs'}});

const resolveOfferingsByDrugIds = async (orderRecord, scope = {}) => {
  const facilityId = scope.facility_id;
  const items = Array.isArray(orderRecord?.items) ? orderRecord.items : [];
  if (!facilityId || !items.length) {
    return {};
  }

  const drugIds = [...new Set(items.map((item) => item.drug_id).filter(Boolean))];
  if (!drugIds.length) {
    return {};
  }

  const offerings = await facilityPharmacyCatalogRepository.findDrugOfferings(
    {
      tenant_id: scope.tenant_id,
      facility_id: facilityId,
      drug_id: { in: drugIds },
      is_active: true},
    0,
    drugIds.length
  );

  return offerings.reduce((acc, offering) => {
    if (offering?.drug_id) {
      acc[offering.drug_id] = offering;
    }
    return acc;
  }, {});
};

const mapScopedPharmacyOrderWorkflowRecord = async (orderRecord, scope = {}) => {
  const offeringsByDrugId = await resolveOfferingsByDrugIds(orderRecord, scope);
  return mapPharmacyOrderWorkflowRecord(orderRecord, { offeringsByDrugId });
};

const appendAnd = (where, clause) => {
  if (!clause || typeof clause !== 'object') return;
  if (!Array.isArray(where.AND)) where.AND = [];
  where.AND.push(clause);
};

const hasKeys = (value) => Boolean(value && typeof value === 'object' && Object.keys(value).length);

const STOCK_STATUS = Object.freeze({
  IN_STOCK: 'IN_STOCK',
  ALMOST_OUT_OF_STOCK: 'ALMOST_OUT_OF_STOCK',
  LOW_STOCK: 'LOW_STOCK',
  OUT_OF_STOCK: 'OUT_OF_STOCK'});

const EXPIRING_SOON_DAYS = 30;

const resolveStockStatus = (quantityValue, reorderValue) => {
  const quantity = Number(quantityValue || 0);
  const reorderLevel = Number(reorderValue || 0);

  if (quantity <= 0) return STOCK_STATUS.OUT_OF_STOCK;
  if (reorderLevel > 0 && quantity <= reorderLevel) return STOCK_STATUS.LOW_STOCK;
  if (reorderLevel > 0 && quantity <= reorderLevel * 2) {
    return STOCK_STATUS.ALMOST_OUT_OF_STOCK;
  }
  return STOCK_STATUS.IN_STOCK;
};

const summarizeStockMetrics = (records = [], extra = {}) =>
  records.reduce(
    (summary, record) => {
      const status = resolveStockStatus(record?.quantity, record?.reorder_level);
      summary.total_stock_rows += 1;
      if (status === STOCK_STATUS.OUT_OF_STOCK) summary.out_of_stock_rows += 1;
      if (status === STOCK_STATUS.LOW_STOCK) summary.low_stock_rows += 1;
      if (status === STOCK_STATUS.ALMOST_OUT_OF_STOCK) summary.almost_out_of_stock_rows += 1;
      return summary;
    },
    {
      total_stock_rows: 0,
      low_stock_rows: 0,
      almost_out_of_stock_rows: 0,
      pending_stock_rows: 0,
      out_of_stock_rows: 0,
      expiring_soon_rows: Number(extra.expiring_soon_rows || 0),
      expired_rows: Number(extra.expired_rows || 0)}
  );

const needsPostStockStatusFilter = (filters = {}) => {
  const status = String(filters.stock_status || '').trim().toUpperCase();
  return (
    status === STOCK_STATUS.IN_STOCK || status === STOCK_STATUS.ALMOST_OUT_OF_STOCK
  );
};

const enrichInventoryStockRecords = async (records = [], expiringWithinDays = EXPIRING_SOON_DAYS) => {
  const inventoryItemIds = records
    .map((record) => record?.inventory_item_id)
    .filter((value) => Boolean(value));
  const maps = await pharmacyWorkspaceRepository.findDrugInventoryMapsByInventoryItemIds(
    inventoryItemIds
  );
  const drugIds = Array.from(new Set(maps.map((row) => row.drug_id).filter(Boolean)));
  const batches = await pharmacyStorageRepository.findDrugBatchesWithStorageByDrugIds(drugIds);
  const batchMetaByItemId = buildBatchMetaByInventoryItemId(
    maps,
    batches,
    expiringWithinDays
  );

  return records
    .map((record) =>
      mapInventoryStockRecord(record, batchMetaByItemId.get(record.inventory_item_id) || null)
    )
    .filter(Boolean);
};

const upsertDrugBatchForReceipt = async (
  tx,
  {
    drugId,
    batchNumber,
    manufacturedAt = null,
    expiryDate = null,
    expiryAlertLeadDays = null,
    quantityDelta = 0,
    storageRoomId = null,
    storageShelfId = null,
    pharmacyLocationId = null}
) => {
  const resolvedBatchNumber = String(batchNumber || '').trim() || 'UNLABELED';
  if (!drugId) return null;
  const delta = Number(quantityDelta || 0);
  const hasDates = Boolean(manufacturedAt || expiryDate || expiryAlertLeadDays != null);
  const hasStorage = Boolean(storageRoomId || storageShelfId);
  // Allow metadata-only upserts (MFD/ED/location without quantity or pack batch).
  if (delta <= 0 && !hasDates && !hasStorage && resolvedBatchNumber === 'UNLABELED') {
    return null;
  }
  if (delta < 0) {
    return null;
  }

  let batch = await pharmacyWorkspaceRepository.txFindDrugBatchByDrugAndNumber(
    tx,
    drugId,
    resolvedBatchNumber,
    pharmacyLocationId
  );

  if (batch) {
    const stockUpdate = {
      ...(delta > 0 ? { quantity: Number(batch.quantity || 0) + delta } : {}),
      ...(manufacturedAt ? { manufactured_at: manufacturedAt } : {}),
      ...(expiryDate ? { expiry_date: expiryDate } : {}),
      ...(expiryAlertLeadDays != null
        ? { expiry_alert_lead_days: expiryAlertLeadDays }
        : {}),
      ...(storageRoomId ? { storage_room_id: storageRoomId } : {}),
      ...(storageShelfId ? { storage_shelf_id: storageShelfId } : {})};
    if (!Object.keys(stockUpdate).length) {
      return batch;
    }
    return pharmacyWorkspaceRepository.txUpdateDrugBatch(tx, batch.id, stockUpdate);
  }

  return pharmacyWorkspaceRepository.txCreateDrugBatch(tx, {
    drug_id: drugId,
    batch_number: resolvedBatchNumber,
    manufactured_at: manufacturedAt,
    expiry_date: expiryDate,
    expiry_alert_lead_days: expiryAlertLeadDays,
    quantity: Math.max(delta, 0),
    storage_room_id: storageRoomId,
    storage_shelf_id: storageShelfId,
    pharmacy_location_id: pharmacyLocationId});
};

const buildDrugStockInclude = (scope = {}) => ({
  inventory_maps: {
    where: { deleted_at: null },
    orderBy: [{ is_default: 'desc' }, { created_at: 'asc' }],
    include: {
      inventory_item: {
        select: {
          ...INVENTORY_ITEM_PUBLIC_SELECT,
          stocks: {
            where: {
              deleted_at: null,
              ...(scope.facility_id ? { facility_id: scope.facility_id } : {})},
            include: {
              facility: {
                select: {
                  id: true,
                  human_friendly_id: true,
                  name: true}}}}}}}}});

const resolveScopedOrderId = async (identifier, scope) =>
  resolveModelIdOrThrow({
    identifier,
    model: 'pharmacy_order',
    where: {
      deleted_at: null,
      ...buildOrderScopeWhere(scope)},
    errorKey: 'errors.pharmacy_order.not_found'});

const resolveScopedInventoryItemId = async (identifier, scope) =>
  resolveModelIdOrThrow({
    identifier,
    model: 'inventory_item',
    where: {
      deleted_at: null,
      ...buildInventoryItemScopeWhere(scope)},
    errorKey: 'errors.inventory_item.not_found'});

const resolveScopedFacilityId = async (identifier, scope, allowNull = false) =>
  resolveModelIdOrThrow({
    identifier: scope?.facility_id || identifier || null,
    model: 'facility',
    where: {
      deleted_at: null,
      ...buildTenantScopeWhere(scope)},
    errorKey: 'errors.facility.not_found',
    allowNull});

/**
 * The pharmacy the caller is acting in.
 *
 * Resolution order: an explicit id on the request, then the pharmacy the order
 * itself belongs to, then the single pharmacy the user holds a grant on. A
 * facility with no pharmacy locations configured resolves to null and keeps the
 * pre-location behaviour.
 *
 * @param {Object} client - Prisma client or transaction
 * @param {Object} params
 * @param {string} [params.explicitLocationId] - Location stated on the request
 * @param {Object} [params.order] - Order being acted on
 * @param {Object} params.scope - Resolved tenant/facility scope
 * @param {Object} params.user - Request user context
 * @returns {Promise<Object|null>} Pharmacy location row, or null when unset
 */
const resolveActingPharmacyLocation = async (
  client,
  { explicitLocationId = null, order = null, scope = {}, user = {} }
) => {
  const tenantId = scope?.can_manage_all_tenants ? null : scope?.tenant_id || null;

  if (explicitLocationId) {
    const explicit = await findPharmacyLocation(client, explicitLocationId, { tenantId });
    if (!explicit) {
      throw new HttpError('errors.pharmacy_location.not_found', 404, [
        { field: 'pharmacy_location_id' }]);
    }
    return explicit;
  }

  // The user's own pharmacy comes before the order's, so someone standing in
  // the wrong pharmacy gets "this prescription belongs elsewhere" rather than a
  // bare access-denied on a pharmacy they never asked for.
  if (!hasTenantWideAccess(user)) {
    const grants = await loadUserLocationGrants(client, { userId: user?.id, tenantId });
    if (grants.size === 1) {
      const [locationId] = Array.from(grants.keys());
      return findPharmacyLocation(client, locationId, { tenantId });
    }
  }

  if (order?.pharmacy_location_id) {
    return findPharmacyLocation(client, order.pharmacy_location_id, { tenantId });
  }

  // Several grants, or none: fall back to the facility's prescription pharmacy
  // so a tenant admin or a multi-pharmacy user still lands somewhere defined.
  if (scope?.facility_id) {
    return resolveDispensingLocationForOrigin(client, {
      facilityId: scope.facility_id,
      origin: order?.origin || 'HOSPITAL',
      tenantId});
  }

  return null;
};

const ensureScopedOrderRecord = (orderRecord, scope) => {
  if (!orderRecord || !matchesOrderScope(orderRecord, scope)) {
    throw new HttpError('errors.pharmacy_order.not_found', 404);
  }
  return orderRecord;
};

const ensureScopedInventoryStockRecord = (stockRecord, scope) => {
  if (!stockRecord || !matchesInventoryStockScope(stockRecord, scope)) {
    throw new HttpError('errors.inventory_stock.not_found', 404);
  }
  return stockRecord;
};

const buildLegacyScopeWhere = (model, scope) => {
  switch (model) {
    case 'pharmacy_order':
      return buildOrderScopeWhere(scope);
    case 'pharmacy_order_item':
      return buildOrderItemScopeWhere(scope);
    case 'dispense_log': {
      const orderItemScope = buildOrderItemScopeWhere(scope);
      return hasKeys(orderItemScope)
        ? {
            pharmacy_order_item: orderItemScope}
        : {};
    }
    case 'inventory_item':
      return buildInventoryItemScopeWhere(scope);
    case 'inventory_stock':
      return buildInventoryStockScopeWhere(scope);
    case 'stock_movement': {
      const where = {};
      const inventoryItemScope = buildInventoryItemScopeWhere(scope);
      if (hasKeys(inventoryItemScope)) {
        where.inventory_item = inventoryItemScope;
      }
      if (!scope?.can_manage_all_tenants && scope?.facility_id) {
        where.facility_id = scope.facility_id;
      }
      return where;
    }
    case 'drug':
      return buildDrugScopeWhere(scope);
    default:
      return {};
  }
};

const assertTransition = (condition, details = {}) => {
  if (condition) return;
  throw new HttpError('errors.pharmacy_workspace.invalid_transition', 400, [details]);
};

const buildDispenseBatchRef = () => {
  const stamp = new Date().toISOString().replace(/[-:TZ.]/g, '').slice(0, 14);
  const entropy = crypto.randomBytes(3).toString('hex').toUpperCase();
  return `DSP${stamp}${entropy}`;
};

const normalizeBatchRef = (value) => {
  const normalized = String(value || '').trim().toUpperCase();
  if (!normalized) return null;
  return normalized.slice(0, 64);
};

const resolveRoleRecipients = async ({ tenantId, facilityId = null }) => {
  if (!tenantId || !prisma?.user_role?.findMany) return [];

  const rows = await prisma.user_role.findMany({
    where: {
      deleted_at: null,
      tenant_id: tenantId,
      role: {
        name: { in: PHARMACY_RECIPIENT_ROLES },
        deleted_at: null},
      ...(facilityId ? { OR: [{ facility_id: null }, { facility_id: facilityId }] } : {})},
    select: {
      user_id: true}});

  return rows.map((item) => item.user_id).filter(Boolean);
};

const buildPharmacyRealtimePayload = ({
  workflow,
  action,
  resourceType = null,
  resourceId = null,
  batchRef = null}) => {
  const order = workflow?.order || null;
  const orderId = String(order?.id || '').trim() || null;
  const patientId = String(order?.patient_id || '').trim() || null;
  const nowIso = new Date().toISOString();

  return {
    order_id: orderId,
    order_public_id: orderId,
    patient_id: patientId,
    patient_public_id: patientId,
    patient_display_name: order?.patient_display_name || null,
    status: order?.status || null,
    action: String(action || 'UPDATED').trim().toUpperCase(),
    resource_type: resourceType,
    resource_id: resourceId,
    dispense_batch_ref: batchRef || null,
    occurred_at: nowIso,
    target_path: orderId ? `/pharmacy?id=${encodeURIComponent(orderId)}` : '/pharmacy',
    workflow};
};

const publishPharmacyRealtimeUpdates = async ({
  workflow,
  orderRecord,
  actorUserId = null,
  action,
  resourceType = null,
  resourceId = null,
  batchRef = null,
  stockRecords = []}) => {
  try {
    const tenantId = orderRecord?.patient?.tenant_id || null;
    if (!tenantId) return;

    const facilityId = orderRecord?.patient?.facility_id || null;
    const recipientUserIds = await resolveRoleRecipients({ tenantId, facilityId });
    // Include the actor so their home dashboard soft-refreshes KPIs/charts.
    // Pharmacy workbench already defers while saving, then coalesces the event.
    const recipients = [...new Set(recipientUserIds.filter(Boolean))];
    if (!recipients.length) return;

    const scopeFields = {
      tenant_id: tenantId,
      facility_id: facilityId,
      actor_user_id: actorUserId || null};

    const workflowPayload = {
      ...buildPharmacyRealtimePayload({
        workflow,
        action,
        resourceType,
        resourceId,
        batchRef}),
      ...scopeFields};

    emitToUsers(recipients, PHARMACY_EVENTS.PHARMACY_WORKSPACE_UPDATED, workflowPayload);

    emitToUsers(recipients, PHARMACY_EVENTS.PHARMACY_ORDER_UPDATED, {
      ...scopeFields,
      order_id: workflowPayload.order_id,
      order_public_id: workflowPayload.order_public_id,
      patient_id: workflowPayload.patient_id,
      patient_public_id: workflowPayload.patient_public_id,
      status: workflowPayload.status,
      action: workflowPayload.action,
      resource_type: workflowPayload.resource_type,
      resource_id: workflowPayload.resource_id,
      dispense_batch_ref: workflowPayload.dispense_batch_ref,
      occurred_at: workflowPayload.occurred_at,
      target_path: workflowPayload.target_path});

    if (!Array.isArray(stockRecords) || !stockRecords.length) return;

    const stockPayload = stockRecords.map((stock) => mapInventoryStockRecord(stock)).filter(Boolean);
    if (!stockPayload.length) return;

    emitToUsers(recipients, INVENTORY_EVENTS.INVENTORY_STOCK_UPDATED, {
      ...scopeFields,
      action: workflowPayload.action,
      order_id: workflowPayload.order_id,
      order_public_id: workflowPayload.order_public_id,
      dispense_batch_ref: workflowPayload.dispense_batch_ref,
      occurred_at: workflowPayload.occurred_at,
      stocks: stockPayload});
  } catch (_error) {
    // realtime delivery must not block business mutations
  }
};

const computeItemDispensedMetrics = (item) => {
  const logs = Array.isArray(item?.dispense_logs) ? item.dispense_logs : [];

  const dispensed = logs
    .filter((entry) => String(entry.status || '').toUpperCase() === 'DISPENSED')
    .reduce((sum, entry) => sum + Number(entry.quantity_dispensed || 0), 0);
  const returned = logs
    .filter((entry) => String(entry.status || '').toUpperCase() === 'RETURNED')
    .reduce((sum, entry) => sum + Number(entry.quantity_dispensed || 0), 0);
  const pending = logs
    .filter((entry) => String(entry.status || '').toUpperCase() === 'PENDING')
    .reduce((sum, entry) => sum + Number(entry.quantity_dispensed || 0), 0);

  const prescribed = Number(item?.quantity || 0);
  const netDispensed = Math.max(0, dispensed - returned);
  // Pending prepare batches are already reserved and cannot be prepared again.
  const remaining = Math.max(0, prescribed - netDispensed - pending);

  return {
    prescribed,
    dispensed,
    returned,
    pending,
    netDispensed,
    remaining};
};

const resolveOrderItemByIdentifier = (orderRecord, identifier) => {
  const normalized = normalizeIdentifier(identifier);
  if (!normalized) return null;

  const upper = normalized.toUpperCase();
  const items = Array.isArray(orderRecord?.items) ? orderRecord.items : [];

  return (
    items.find((item) => {
      if (!item) return false;
      if (isUuidLike(normalized)) {
        return String(item.id || '').toLowerCase() === normalized.toLowerCase();
      }

      const friendly = String(item.human_friendly_id || '').trim().toUpperCase();
      return friendly && friendly === upper;
    }) || null
  );
};

const resolveInventoryMapForItem = async ({
  tx,
  item,
  tenantId,
  inventoryItemIdentifier = null}) => {
  const mappings = Array.isArray(item?.drug?.inventory_maps) ? item.drug.inventory_maps : [];

  if (inventoryItemIdentifier) {
    const normalized = normalizeIdentifier(inventoryItemIdentifier);
    const resolved = mappings.find((entry) => {
      if (!entry) return false;
      if (isUuidLike(normalized)) {
        return String(entry.inventory_item_id || '').toLowerCase() === normalized.toLowerCase();
      }
      return (
        String(entry.inventory_item?.human_friendly_id || '').trim().toUpperCase() ===
        String(normalized || '').toUpperCase()
      );
    });

    if (resolved) return resolved;

    const inventoryItemId = await resolveModelIdOrThrow({
      identifier: inventoryItemIdentifier,
      model: 'inventory_item',
      where: {
        deleted_at: null,
        ...(tenantId ? { tenant_id: tenantId } : {})},
      errorKey: 'errors.inventory_item.not_found'});

    const explicitMap = await pharmacyWorkspaceRepository.txFindInventoryMapByDrugAndItem(
      tx,
      item.drug_id,
      inventoryItemId,
      tenantId
    );

    if (explicitMap) return explicitMap;
  }

  if (mappings.length) {
    return mappings.find((entry) => Boolean(entry.is_default)) || mappings[0];
  }

  return pharmacyWorkspaceRepository.txFindInventoryMapByDrug(tx, item.drug_id, tenantId);
};

const normalizeStockDeductionQuantity = (requestedQuantity, deductionFactor) => {
  const quantity = Number(requestedQuantity || 0);
  const factor = Number(deductionFactor || 1);
  const normalizedFactor = Number.isFinite(factor) && factor > 0 ? factor : 1;
  const raw = quantity * normalizedFactor;
  const rounded = Math.ceil(raw);
  return Number.isFinite(rounded) ? rounded : 0;
};

const rollupOrderStatus = (orderRecord) => {
  const items = Array.isArray(orderRecord?.items) ? orderRecord.items : [];
  const activeItems = items.filter(
    (item) => String(item?.status || '').toUpperCase() !== 'CANCELLED'
  );

  if (!activeItems.length) {
    return items.length ? 'CANCELLED' : 'ORDERED';
  }

  let allComplete = true;
  let anyDispensed = false;

  for (const item of activeItems) {
    const metrics = computeItemDispensedMetrics(item);
    if (metrics.netDispensed > 0) anyDispensed = true;
    if (metrics.netDispensed < metrics.prescribed) allComplete = false;
  }

  if (allComplete) return 'DISPENSED';
  if (anyDispensed) return 'PARTIALLY_DISPENSED';
  return 'ORDERED';
};

const listPendingAttestationBatchRefs = (orderRecord) => {
  const attestations = Array.isArray(orderRecord?.dispense_attestations)
    ? orderRecord.dispense_attestations
    : [];

  const phasesByBatch = new Map();
  attestations.forEach((entry) => {
    const batchRef = normalizeBatchRef(entry?.dispense_batch_ref);
    const phase = String(entry?.phase || '').trim().toUpperCase();
    if (!batchRef || !phase) return;

    const current = phasesByBatch.get(batchRef) || new Set();
    current.add(phase);
    phasesByBatch.set(batchRef, current);
  });

  return Array.from(phasesByBatch.entries())
    .filter(([, phases]) => phases.has('PREPARE') && !phases.has('ATTEST'))
    .map(([batchRef]) => batchRef);
};

const voidPendingPrepareBatches = async (tx, orderRecord) => {
  const pendingBatchRefs = listPendingAttestationBatchRefs(orderRecord);
  if (!pendingBatchRefs.length) {
    return [];
  }

  for (const batchRef of pendingBatchRefs) {
    await pharmacyWorkspaceRepository.txUpdateManyDispenseLogs(
      tx,
      {
        status: 'PENDING',
        dispense_batch_ref: batchRef,
        pharmacy_order_item: {
          pharmacy_order_id: orderRecord.id,
          deleted_at: null}},
      { status: 'CANCELLED' }
    );

    const prepareAttestation = await pharmacyWorkspaceRepository.txFindDispenseAttestation(
      tx,
      orderRecord.id,
      batchRef,
      'PREPARE'
    );
    if (prepareAttestation?.id) {
      await pharmacyWorkspaceRepository.txSoftDeleteDispenseAttestation(
        tx,
        prepareAttestation.id
      );
    }
  }

  return pendingBatchRefs;
};

const finalizePendingDispenseBatch = async ({
  tx,
  order,
  scope,
  batchRef,
  userId,
  userRole,
  ipAddress,
  payload = {},
  allowSameUser = false}) => {
  const prepareAttestation = await pharmacyWorkspaceRepository.txFindDispenseAttestation(
    tx,
    order.id,
    batchRef,
    'PREPARE'
  );
  assertTransition(Boolean(prepareAttestation), {
    reason: 'prepare_required',
    dispense_batch_ref: batchRef});

  const existingAttest = await pharmacyWorkspaceRepository.txFindDispenseAttestation(
    tx,
    order.id,
    batchRef,
    'ATTEST'
  );
  if (existingAttest) {
    const refreshedOrder = await pharmacyWorkspaceRepository.txFindOrderById(
      tx,
      order.id,
      PHARMACY_ORDER_WITH_RELATIONS_INCLUDE
    );
    return {
      order: refreshedOrder,
      batchRef,
      stockRecords: [],
      attestation: existingAttest};
  }

  if (
    !allowSameUser &&
    String(prepareAttestation.attested_by_user_id || '') === String(userId || '')
  ) {
    throw new HttpError('errors.pharmacy_workspace.attestation.same_user', 400);
  }

  const pendingLogs = await pharmacyWorkspaceRepository.txFindDispenseLogsByBatch(
    tx,
    order.id,
    batchRef,
    {
      pharmacy_order_item: {
        include: {
          drug: {
            include: {
              inventory_maps: {
                where: { deleted_at: null },
                orderBy: [{ is_default: 'desc' }, { created_at: 'asc' }],
                include: {
                  inventory_item: true}}}}}}}
  );

  const pendingOnly = pendingLogs.filter(
    (entry) => String(entry.status || '').toUpperCase() === 'PENDING'
  );
  assertTransition(pendingOnly.length > 0, {
    reason: 'pending_logs_required',
    dispense_batch_ref: batchRef});

  const resolvedFacilityId = await resolveScopedFacilityId(
    payload.facility_id || order.patient?.facility_id || null,
    scope,
    true
  );

  // Dispense out of the pharmacy that owns the prescription, and refuse the
  // attempt outright when the user is standing in a different one. Without
  // this, a hospital prescription could be filled from Main Pharmacy stock.
  const dispensingLocation = await resolveActingPharmacyLocation(tx, {
    explicitLocationId: payload.pharmacy_location_id,
    order,
    scope,
    user: scope?.user || {}});
  assertOrderDispensableAt({ order, dispensingLocation });
  if (dispensingLocation) {
    await assertLocationAccess(tx, {
      location: dispensingLocation,
      user: scope?.user || {},
      level: ACCESS_LEVELS.DISPENSE});
  }

  const attestedAt = toDateOrNull(payload.attested_at, new Date());
  const stockRecords = [];

  for (const log of pendingOnly) {
    const orderItem = log.pharmacy_order_item;
    if (!orderItem) {
      throw new HttpError('errors.pharmacy_order_item.not_found', 404);
    }

    const inventoryMap = await resolveInventoryMapForItem({
      tx,
      item: orderItem,
      tenantId: order.patient?.tenant_id || null,
      inventoryItemIdentifier: null});

    if (!inventoryMap) {
      throw new HttpError('errors.pharmacy_workspace.inventory_map.required', 400, [
        { order_item_id: orderItem.id }]);
    }

    const stockDelta = normalizeStockDeductionQuantity(
      log.quantity_dispensed,
      inventoryMap.deduction_factor
    );

    // Location-scoped balance first: Main and Hospital pharmacies hold separate
    // rows for the same item, so the facility-wide lookup would be ambiguous.
    const stockRecord = dispensingLocation
      ? await tx.inventory_stock.findFirst({
          where: {
            deleted_at: null,
            inventory_item_id: inventoryMap.inventory_item_id,
            pharmacy_location_id: dispensingLocation.id},
          include: INVENTORY_STOCK_WITH_RELATIONS_INCLUDE})
      : await pharmacyWorkspaceRepository.txFindStockByInventoryItemAndFacility(
          tx,
          inventoryMap.inventory_item_id,
          resolvedFacilityId,
          INVENTORY_STOCK_WITH_RELATIONS_INCLUDE
        );
    if (!stockRecord) {
      throw new HttpError('errors.pharmacy_workspace.stock.not_found', 404, [
        { inventory_item_id: inventoryMap.inventory_item_id,
          pharmacy_location_id: dispensingLocation?.id || null }]);
    }
    const stock = ensureScopedInventoryStockRecord(stockRecord, scope);

    assertTransition(Number(stock.quantity || 0) >= stockDelta, {
      reason: 'insufficient_stock',
      inventory_item_id: inventoryMap.inventory_item_id,
      available: Number(stock.quantity || 0),
      required: stockDelta});

    const updatedStock = await pharmacyWorkspaceRepository.txUpdateInventoryStock(tx, stock.id, {
      quantity: Number(stock.quantity || 0) - stockDelta});

    await pharmacyWorkspaceRepository.txCreateStockMovement(tx, {
      inventory_item_id: inventoryMap.inventory_item_id,
      facility_id: resolvedFacilityId,
      pharmacy_location_id: dispensingLocation?.id || null,
      movement_type: 'OUTBOUND',
      reason: 'DISPENSE',
      quantity: stockDelta,
      occurred_at: attestedAt});

    await pharmacyWorkspaceRepository.txUpdateDispenseLog(tx, log.id, {
      status: 'DISPENSED',
      dispensed_at: attestedAt});

    stockRecords.push({
      ...stock,
      ...updatedStock});
  }

  const attestRecord = await pharmacyWorkspaceRepository.txCreateDispenseAttestation(tx, {
    pharmacy_order_id: order.id,
    dispense_batch_ref: batchRef,
    phase: 'ATTEST',
    attested_by_user_id: userId,
    attested_role: userRole || null,
    statement: payload.statement || null,
    reason: payload.reason || (allowSameUser ? 'DISPENSE' : null),
    ip_address: ipAddress || null,
    attested_at: attestedAt});

  let refreshedOrder = await pharmacyWorkspaceRepository.txFindOrderById(
    tx,
    order.id,
    PHARMACY_ORDER_WITH_RELATIONS_INCLUDE
  );

  await syncOrderItemStatusesAfterDispense(tx, refreshedOrder);

  const rolledUpStatus = rollupOrderStatus(refreshedOrder);
  const billingReconciled = await reconcilePendingPharmacyBillingAfterDispense(
    tx,
    refreshedOrder
  );
  if (refreshedOrder.status !== rolledUpStatus) {
    await pharmacyWorkspaceRepository.txUpdateOrder(tx, order.id, {
      status: rolledUpStatus});
  }
  if (refreshedOrder.status !== rolledUpStatus || billingReconciled) {
    refreshedOrder = await pharmacyWorkspaceRepository.txFindOrderById(
      tx,
      order.id,
      PHARMACY_ORDER_WITH_RELATIONS_INCLUDE
    );
  }

  return {
    order: refreshedOrder,
    batchRef,
    stockRecords,
    attestation: attestRecord};
};

const syncOrderItemStatusesAfterDispense = async (tx, orderRecord) => {
  const items = Array.isArray(orderRecord?.items) ? orderRecord.items : [];
  for (const item of items) {
    const currentStatus = String(item?.status || '').toUpperCase();
    if (currentStatus === 'CANCELLED' || !item?.id) {
      continue;
    }

    const metrics = computeItemDispensedMetrics(item);
    const nextStatus =
      metrics.prescribed > 0 && metrics.netDispensed >= metrics.prescribed
        ? 'COMPLETED'
        : 'ACTIVE';

    if (currentStatus === nextStatus) {
      continue;
    }

    await pharmacyWorkspaceRepository.txUpdateOrderItem(tx, item.id, {
      status: nextStatus});
  }
};

// Billing writes `PENDING` for auto-built pharmacy billing, while older records
// may carry `UNPAID`; treat all unsettled states as pending payment so the tab,
// filter, and summary counter stay consistent.
const PHARMACY_PENDING_PAYMENT_STATUSES = Object.freeze([
  'PENDING',
  'PARTIAL',
  'UNPAID']);

const buildDispensedQuantityBillingPatch = (orderRecord) => {
  const snapshot = extractStoredClinicalBilling(orderRecord);
  if (!snapshot) {
    return null;
  }

  const paymentStatus = String(snapshot.payment_status || '').toUpperCase();
  if (!PHARMACY_PENDING_PAYMENT_STATUSES.includes(paymentStatus)) {
    return null;
  }

  const lineItems = Array.isArray(snapshot.line_items) ? snapshot.line_items : [];
  if (!lineItems.length) {
    return null;
  }

  const existingByKey = new Map();
  for (const line of lineItems) {
    const lineId = String(line?.id || '').trim();
    if (lineId) {
      existingByKey.set(lineId, line);
    }
  }

  // Bill only what has been net-dispensed so partial fills do not charge the
  // full prescribed course for undelivered medicines.
  const nextLines = [];
  let anyDispensed = false;
  for (const item of Array.isArray(orderRecord?.items) ? orderRecord.items : []) {
    if (String(item?.status || '').toUpperCase() === 'CANCELLED') {
      continue;
    }
    const metrics = computeItemDispensedMetrics(item);
    if (metrics.netDispensed <= 0) {
      continue;
    }
    anyDispensed = true;

    const keys = [
      item.drug?.human_friendly_id,
      item.drug_id,
      item.drug?.id]
      .map((value) => String(value || '').trim())
      .filter(Boolean);
    const existing =
      keys.map((key) => existingByKey.get(key)).find(Boolean) || null;
    const unitPrice = Number(existing?.unit_price ?? 0) || 0;
    const nextTotal = unitPrice * metrics.netDispensed;
    const lineId = String(existing?.id || keys[0] || item.id || '').trim();
    if (!lineId) {
      continue;
    }

    nextLines.push({
      ...(existing || {}),
      id: lineId,
      label:
        existing?.label ||
        item.drug?.name ||
        item.drug?.generic_name ||
        lineId,
      quantity: metrics.netDispensed,
      unit_price: existing?.unit_price ?? unitPrice,
      line_total: Number.isFinite(nextTotal) ? String(nextTotal) : existing?.line_total,
      ...(existing?.currency ? { currency: existing.currency } : {}),
      ...(existing?.price_source ? { price_source: existing.price_source } : {})});
  }

  if (!anyDispensed) {
    return null;
  }

  const subtotal = nextLines.reduce((sum, line) => {
    const lineTotal = Number(line?.line_total);
    if (Number.isFinite(lineTotal)) {
      return sum + lineTotal;
    }
    const unitPrice = Number(line?.unit_price) || 0;
    return sum + unitPrice * (Number(line?.quantity) || 0);
  }, 0);

  const priorSignature = JSON.stringify(
    lineItems.map((line) => [String(line?.id || ''), Number(line?.quantity) || 0])
  );
  const nextSignature = JSON.stringify(
    nextLines.map((line) => [String(line?.id || ''), Number(line?.quantity) || 0])
  );
  if (priorSignature === nextSignature) {
    return null;
  }

  return {
    ...snapshot,
    line_items: nextLines,
    total_amount: String(subtotal),
    ...(snapshot.subtotal !== undefined ? { subtotal: String(subtotal) } : {}),
    ...(snapshot.total !== undefined ? { total: String(subtotal) } : {})};
};

const reconcilePendingPharmacyBillingAfterDispense = async (tx, orderRecord) => {
  const patchedBilling = buildDispensedQuantityBillingPatch(orderRecord);
  if (!patchedBilling) {
    return false;
  }

  const patient = orderRecord?.patient || {};
  await persistPharmacyOrderBilling(tx, {
    orderId: orderRecord.id,
    billing: patchedBilling,
    existingSnapshot: extractStoredClinicalBilling(orderRecord),
    tenantId: patient.tenant_id || null,
    facilityId: patient.facility_id || null,
    patientId: orderRecord.patient_id || patient.id || null,
    encounterId: orderRecord.encounter_id || orderRecord.encounter?.id || null,
    description: 'Pharmacy dispense reconciliation'});

  return true;
};

const orderItemBillingKeys = (item) =>
  [item?.drug?.human_friendly_id, item?.drug_id, item?.drug?.id, item?.id]
    .map((value) => String(value || '').trim())
    .filter(Boolean);

/** Reverse reversible invoice (if any) and clear the pharmacy billing snapshot. */
const clearPharmacyOrderBilling = async (tx, orderRecord) => {
  const existingSnapshot = extractStoredClinicalBilling(orderRecord);
  if (!existingSnapshot) {
    return false;
  }

  if (existingSnapshot.invoice_id) {
    await reverseClinicalRequestBilling(tx, { existingSnapshot });
  }

  await tx.pharmacy_order.update({
    where: { id: orderRecord.id },
    data: { billing_snapshot: null }});

  return true;
};

/**
 * Rebuild unpaid pharmacy billing after a line cancel: drop cancelled drugs,
 * prefer net-dispensed quantities when present, otherwise keep remaining lines.
 * Clears billing when nothing billable remains.
 */
const reconcilePendingPharmacyBillingAfterItemCancel = async (tx, orderRecord) => {
  const snapshot = extractStoredClinicalBilling(orderRecord);
  if (!snapshot) {
    return false;
  }

  const paymentStatus = String(snapshot.payment_status || '').toUpperCase();
  if (!PHARMACY_PENDING_PAYMENT_STATUSES.includes(paymentStatus)) {
    return false;
  }

  const activeItems = (Array.isArray(orderRecord?.items) ? orderRecord.items : []).filter(
    (item) => String(item?.status || '').toUpperCase() !== 'CANCELLED'
  );
  if (!activeItems.length) {
    return clearPharmacyOrderBilling(tx, orderRecord);
  }

  const dispensedPatch = buildDispensedQuantityBillingPatch(orderRecord);
  if (dispensedPatch) {
    const patient = orderRecord?.patient || {};
    await persistPharmacyOrderBilling(tx, {
      orderId: orderRecord.id,
      billing: dispensedPatch,
      existingSnapshot: snapshot,
      tenantId: patient.tenant_id || null,
      facilityId: patient.facility_id || null,
      patientId: orderRecord.patient_id || patient.id || null,
      encounterId: orderRecord.encounter_id || orderRecord.encounter?.id || null,
      description: 'Pharmacy cancel item reconciliation'});
    return true;
  }

  const lineItems = Array.isArray(snapshot.line_items) ? snapshot.line_items : [];
  const activeKeys = new Set(activeItems.flatMap(orderItemBillingKeys));
  const nextLines = lineItems.filter((line) => {
    const lineId = String(line?.id || '').trim();
    return lineId && activeKeys.has(lineId);
  });

  if (!nextLines.length) {
    return clearPharmacyOrderBilling(tx, orderRecord);
  }

  const priorSignature = JSON.stringify(
    lineItems.map((line) => [String(line?.id || ''), Number(line?.quantity) || 0])
  );
  const nextSignature = JSON.stringify(
    nextLines.map((line) => [String(line?.id || ''), Number(line?.quantity) || 0])
  );
  if (priorSignature === nextSignature) {
    return false;
  }

  const subtotal = nextLines.reduce((sum, line) => {
    const lineTotal = Number(line?.line_total);
    if (Number.isFinite(lineTotal)) {
      return sum + lineTotal;
    }
    const unitPrice = Number(line?.unit_price) || 0;
    return sum + unitPrice * (Number(line?.quantity) || 0);
  }, 0);

  const patchedBilling = {
    ...snapshot,
    line_items: nextLines,
    total_amount: String(subtotal),
    ...(snapshot.subtotal !== undefined ? { subtotal: String(subtotal) } : {}),
    ...(snapshot.total !== undefined ? { total: String(subtotal) } : {})};

  const patient = orderRecord?.patient || {};
  await persistPharmacyOrderBilling(tx, {
    orderId: orderRecord.id,
    billing: patchedBilling,
    existingSnapshot: snapshot,
    tenantId: patient.tenant_id || null,
    facilityId: patient.facility_id || null,
    patientId: orderRecord.patient_id || patient.id || null,
    encounterId: orderRecord.encounter_id || orderRecord.encounter?.id || null,
    description: 'Pharmacy cancel item reconciliation'});

  return true;
};

const buildPendingPaymentStatusClause = () => ({
  OR: PHARMACY_PENDING_PAYMENT_STATUSES.map((paymentStatus) => ({
    billing_snapshot: { path: '$.payment_status', equals: paymentStatus }}))});

// Orders that are NOT awaiting payment (paid, no-charge, not required, or no
// billing snapshot). Used so New orders / Partial exclude payment-gated orders.
const buildNotPendingPaymentClause = () => ({
  NOT: buildPendingPaymentStatusClause()});

// Start of the current server/facility day, for day-scoped Completed / Cancelled.
const startOfServerDay = () => {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth(), now.getDate());
};

// Shallow-clones a where object, including its AND array, so appendAnd does not
// mutate a base shared across independent summary buckets.
const cloneOrderWhere = (base = {}) => ({
  ...base,
  ...(Array.isArray(base.AND) ? { AND: [...base.AND] } : {})});

// Builds an independent summary bucket: a fresh status plus an optional clause,
// keeping the tenant/facility/global scope from base without inheriting the
// active tab's status, payment, or day filters.
const buildSummaryBucketWhere = (base, status, clause) => {
  const where = cloneOrderWhere(base);
  where.status = status;
  if (clause) {
    appendAnd(where, clause);
  }
  return where;
};

const buildWorkbenchOrderWhere = async (filters = {}, scope, options = {}) => {
  const includeSearch = options.includeSearch !== false;
  const where = {
    ...buildOrderScopeWhere(scope)};

  if (filters.patient_id) {
    where.patient_id = await resolveModelIdOrThrow({
      identifier: filters.patient_id,
      model: 'patient',
      where: {
        deleted_at: null,
        ...buildPatientScopeWhere(scope)},
      errorKey: 'errors.patient.not_found'});
  }

  if (filters.encounter_id) {
    where.encounter_id = await resolveModelIdOrThrow({
      identifier: filters.encounter_id,
      model: 'encounter',
      where: {
        deleted_at: null,
        ...buildEncounterScopeWhere(scope)},
      errorKey: 'errors.encounter.not_found'});
  }

  if (filters.open_orders === true) {
    appendAnd(where, { status: { in: PHARMACY_OPEN_ORDER_STATUSES } });
  } else if (filters.status) {
    where.status = filters.status;
  }

  const locationWhere = buildOrderLocationWhere(filters.location);
  if (locationWhere) {
    appendAnd(where, locationWhere);
  }

  if (filters.pending_payment === true) {
    // Pending payment claims open orders awaiting payment; it takes precedence
    // over New orders / Partial, so scope to open statuses when none is set.
    appendAnd(where, buildPendingPaymentStatusClause());
    if (!filters.status) {
      appendAnd(where, { status: { in: PHARMACY_OPEN_ORDER_STATUSES } });
    }
  } else if (filters.payment_cleared === true) {
    appendAnd(where, buildNotPendingPaymentClause());
  }

  applyDateRangeFilter(where, 'ordered_at', filters.from, filters.to);

  if (filters.today_only === true) {
    appendAnd(where, { updated_at: { gte: startOfServerDay() } });
  }

  if (filters.partial_stock === true) {
    appendAnd(where, {
      OR: [
        { status: 'PARTIALLY_DISPENSED' },
        {
          status: { in: PHARMACY_OPEN_ORDER_STATUSES },
          items: {
            some: {
              deleted_at: null,
              status: 'ACTIVE',
              drug: {
                inventory_maps: {
                  some: {
                    deleted_at: null,
                    inventory_item: {
                      stocks: {
                        some: {
                          deleted_at: null,
                          quantity: { lte: 0 }}}}}}}}}}]});
  }

  if (filters.urgent === true) {
    appendAnd(where, {
      items: {
        some: {
          deleted_at: null,
          frequency: 'STAT'}}});
  }

  if (filters.priority) {
    const normalizedPriority = String(filters.priority).trim().toUpperCase();
    if (normalizedPriority === 'STAT' || normalizedPriority === 'URGENT') {
      appendAnd(where, {
        items: {
          some: {
            deleted_at: null,
            frequency: 'STAT'}}});
    } else if (normalizedPriority === 'ROUTINE' || normalizedPriority === 'NORMAL') {
      appendAnd(where, {
        NOT: {
          items: {
            some: {
              deleted_at: null,
              frequency: 'STAT'}}}});
    }
  }

  const searchTerm = normalizeSearchTerm(filters.search);
  if (includeSearch && searchTerm) {
    appendAnd(where, {
      OR: [
        { human_friendly_id: { contains: searchTerm.upper } },
        { patient: { human_friendly_id: { contains: searchTerm.upper } } },
        { patient: { first_name: { contains: searchTerm.raw } } },
        { patient: { last_name: { contains: searchTerm.raw } } },
        { encounter: { human_friendly_id: { contains: searchTerm.upper } } },
        { items: { some: { human_friendly_id: { contains: searchTerm.upper } } } },
        { items: { some: { drug: { human_friendly_id: { contains: searchTerm.upper } } } } },
        { items: { some: { drug: { name: { contains: searchTerm.raw } } } } },
        { items: { some: { drug: { code: { contains: searchTerm.raw } } } } },
        { items: { some: { dispense_logs: { some: { dispense_batch_ref: { contains: searchTerm.upper } } } } } }]});
  }

  return where;
};

const buildInventoryStockWhere = async (filters = {}, scope, options = {}) => {
  const includeSearch = options.includeSearch !== false;
  const where = {
    ...buildInventoryStockScopeWhere(scope)};

  if (filters.facility_id) {
    where.facility_id = await resolveScopedFacilityId(filters.facility_id, scope);
  } else if (scope?.facility_id && !scope?.can_manage_all_tenants) {
    where.facility_id = scope.facility_id;
  }

  // Balances belong to one pharmacy. Without a location filter a Main + Hospital
  // facility would list the same item twice and appear to hold both balances.
  if (options.pharmacyLocationId) {
    where.pharmacy_location_id = options.pharmacyLocationId;
  }

  if (filters.inventory_item_id) {
    where.inventory_item_id = await resolveScopedInventoryItemId(filters.inventory_item_id, scope);
  }

  if (filters.low_stock_only === true) {
    appendAnd(where, {
      OR: [
        { quantity: { lte: 0 } },
        {
          AND: [
            { reorder_level: { gt: 0 } },
            { quantity: { lte: prisma.inventory_stock.fields.reorder_level } }]}]});
  }

  const stockStatus = String(filters.stock_status || '').trim().toUpperCase();
  if (stockStatus === STOCK_STATUS.OUT_OF_STOCK) {
    appendAnd(where, { quantity: { lte: 0 } });
  } else if (stockStatus === STOCK_STATUS.LOW_STOCK) {
    appendAnd(where, {
      AND: [
        { quantity: { gt: 0 } },
        { reorder_level: { gt: 0 } },
        { quantity: { lte: prisma.inventory_stock.fields.reorder_level } }]});
  } else if (stockStatus === STOCK_STATUS.ALMOST_OUT_OF_STOCK) {
    appendAnd(where, {
      AND: [
        { quantity: { gt: 0 } },
        { reorder_level: { gt: 0 } },
        { quantity: { gt: prisma.inventory_stock.fields.reorder_level } }]});
  } else if (stockStatus === STOCK_STATUS.IN_STOCK) {
    appendAnd(where, {
      AND: [
        { quantity: { gt: 0 } },
        {
          OR: [
            { reorder_level: { lte: 0 } },
            { quantity: { gt: prisma.inventory_stock.fields.reorder_level } }]}]});
  }

  if (filters.expired_only === true || filters.expiring_within_days) {
    const inventoryItemIds = await pharmacyWorkspaceRepository.findInventoryItemIdsByBatchFilters(
      scope.tenant_id,
      filters
    );
    where.inventory_item_id = {
      in: inventoryItemIds?.length ? inventoryItemIds : ['__no_match__']};
  }

  if (filters.storage_room_id || filters.storage_shelf_id) {
    const facilityId = where.facility_id || scope.facility_id;
    const storageAssignment = await resolveStorageAssignment(
      {
        storage_room_id: filters.storage_room_id || null,
        storage_shelf_id: filters.storage_shelf_id || null},
      scope,
      facilityId
    );
    const inventoryItemIds = await pharmacyStorageRepository.findInventoryItemIdsByStorageFilters(
      scope.tenant_id,
      {
        storage_room_id: storageAssignment.storageRoomId,
        storage_shelf_id: storageAssignment.storageShelfId}
    );
    where.inventory_item_id = {
      in: inventoryItemIds?.length ? inventoryItemIds : ['__no_match__']};
  }

  const searchTerm = normalizeSearchTerm(filters.search);
  if (includeSearch && searchTerm) {
    appendAnd(where, {
      OR: [
        { human_friendly_id: { contains: searchTerm.upper } },
        { inventory_item: { human_friendly_id: { contains: searchTerm.upper } } },
        { inventory_item: { name: { contains: searchTerm.raw } } },
        { inventory_item: { sku: { contains: searchTerm.raw } } }]});
  }

  return where;
};

const buildDrugWhere = (filters = {}, scope, options = {}) => {
  const includeSearch = options.includeSearch !== false;
  const where = {
    ...buildDrugScopeWhere(scope)};

  if (filters.id) where.id = filters.id;
  if (filters.name) where.name = { contains: String(filters.name).trim() };
  if (filters.code) where.code = { contains: String(filters.code).trim() };
  if (filters.form) where.form = { contains: String(filters.form).trim() };
  if (filters.strength) where.strength = { contains: String(filters.strength).trim() };

  const searchTerm = normalizeSearchTerm(filters.search);
  if (includeSearch && searchTerm) {
    appendAnd(where, {
      OR: [
        { human_friendly_id: { contains: searchTerm.upper } },
        { name: { contains: searchTerm.raw } },
        { brand_name: { contains: searchTerm.raw } },
        { generic_name: { contains: searchTerm.raw } },
        { code: { contains: searchTerm.raw } },
        { form: { contains: searchTerm.raw } },
        { strength: { contains: searchTerm.raw } }]});
  }

  return where;
};

const buildDischargeSummaryWhere = (summaryWhere) => {
  const where = { ...summaryWhere };
  appendAnd(where, {
    status: { in: PHARMACY_OPEN_ORDER_STATUSES },
    encounter: { is: { encounter_type: { in: INPATIENT_ENCOUNTER_TYPES } } }});
  return where;
};

const buildPendingPaymentWhere = (baseWhere) => {
  const where = cloneOrderWhere(baseWhere);
  appendAnd(where, buildPendingPaymentStatusClause());
  appendAnd(where, { status: { in: PHARMACY_OPEN_ORDER_STATUSES } });
  return where;
};

const buildLocationScopedWhere = (baseWhere, location) => {
  const where = { ...baseWhere };
  const locationWhere = buildOrderLocationWhere(location);
  if (locationWhere) {
    appendAnd(where, locationWhere);
  }
  return where;
};

const buildWorkbenchSummary = async (summaryWhere, summaryBaseWhere = summaryWhere) => {
  const [
    totalOrders,
    orderedQueue,
    partiallyDispensedQueue,
    dispensedOrders,
    cancelledOrders,
    dischargePendingQueue,
    outpatientQueue,
    wardQueue,
    pendingPaymentQueue,
    preparedAttestations,
    completedAttestations] = await Promise.all([
    pharmacyWorkspaceRepository.countOrders(summaryBaseWhere),
    pharmacyWorkspaceRepository.countOrders(
      buildSummaryBucketWhere(
        summaryBaseWhere,
        'ORDERED',
        buildNotPendingPaymentClause()
      )
    ),
    pharmacyWorkspaceRepository.countOrders(
      buildSummaryBucketWhere(
        summaryBaseWhere,
        'PARTIALLY_DISPENSED',
        buildNotPendingPaymentClause()
      )
    ),
    pharmacyWorkspaceRepository.countOrders(
      buildSummaryBucketWhere(summaryBaseWhere, 'DISPENSED', {
        updated_at: { gte: startOfServerDay() }})
    ),
    pharmacyWorkspaceRepository.countOrders(
      buildSummaryBucketWhere(summaryBaseWhere, 'CANCELLED', {
        updated_at: { gte: startOfServerDay() }})
    ),
    pharmacyWorkspaceRepository.countOrders(buildDischargeSummaryWhere(summaryBaseWhere)),
    pharmacyWorkspaceRepository.countOrders(
      buildLocationScopedWhere(summaryBaseWhere, 'OUTPATIENT')
    ),
    pharmacyWorkspaceRepository.countOrders(
      buildLocationScopedWhere(summaryBaseWhere, 'INPATIENT')
    ),
    pharmacyWorkspaceRepository.countOrders(buildPendingPaymentWhere(summaryBaseWhere)),
    pharmacyWorkspaceRepository.countDispenseAttestations({
      phase: 'PREPARE',
      pharmacy_order: {
        deleted_at: null,
        ...summaryWhere}}),
    pharmacyWorkspaceRepository.countDispenseAttestations({
      phase: 'ATTEST',
      pharmacy_order: {
        deleted_at: null,
        ...summaryWhere}})]);

  return {
    total_orders: totalOrders,
    ordered_queue: orderedQueue,
    partially_dispensed_queue: partiallyDispensedQueue,
    dispensed_orders: dispensedOrders,
    cancelled_orders: cancelledOrders,
    discharge_pending_queue: dischargePendingQueue,
    outpatient_queue: outpatientQueue,
    ward_queue: wardQueue,
    pending_payment_queue: pendingPaymentQueue,
    pending_attestations: Math.max(0, preparedAttestations - completedAttestations)};
};

const getPharmacyWorkbench = async (filters, page, limit, sortBy, order, user = {}) => {
  try {
    const scope = resolveScopedUserContext(user);
    const skip = (page - 1) * limit;
    const orderBy = sortBy ? { [sortBy]: order } : { ordered_at: 'desc' };

    // Summary buckets strip only section-specific gates (status / payment /
    // today) so badges stay aligned with search + advanced filters applied to
    // the worklist. Location, date range, priority, and search remain.
    const [where, summaryWhere, summaryBaseWhere] = await Promise.all([
      buildWorkbenchOrderWhere(filters, scope, { includeSearch: true }),
      buildWorkbenchOrderWhere(filters, scope, { includeSearch: true }),
      buildWorkbenchOrderWhere(
        {
          ...filters,
          status: undefined,
          open_orders: undefined,
          pending_payment: undefined,
          payment_cleared: undefined,
          today_only: undefined},
        scope,
        { includeSearch: true }
      )]);

    const [worklistRecords, total, summary] = await Promise.all([
      pharmacyWorkspaceRepository.findManyOrders(
        where,
        skip,
        limit,
        orderBy,
        PHARMACY_ORDER_WITH_RELATIONS_INCLUDE
      ),
      pharmacyWorkspaceRepository.countOrders(where),
      buildWorkbenchSummary(summaryWhere, summaryBaseWhere)]);

    return {
      summary,
      worklist: worklistRecords.map((record) => mapPharmacyOrderRecord(record)).filter(Boolean),
      pagination: buildPagination(page, limit, total)};
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

const getPharmacyOrderWorkflow = async (identifier, user = {}) => {
  try {
    const scope = resolveScopedUserContext(user);
    const orderId = await resolveScopedOrderId(identifier, scope);

    const orderRecord = ensureScopedOrderRecord(
      await pharmacyWorkspaceRepository.findOrderById(
        orderId,
        PHARMACY_ORDER_WITH_RELATIONS_INCLUDE
      ),
      scope
    );

    return mapScopedPharmacyOrderWorkflowRecord(orderRecord, scope);
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

const searchDrugs = async (filters, page, limit, sortBy, order, user = {}) => {
  try {
    const scope = resolveScopedUserContext(user);
    const skip = (page - 1) * limit;
    const safeSortBy = ['name', 'code', 'form', 'strength', 'updated_at', 'created_at'].includes(sortBy)
      ? sortBy
      : 'name';
    const orderBy = { [safeSortBy]: order || 'asc' };
    const where = buildDrugWhere(filters, scope, { includeSearch: true });

    const facilityId =
      scope.facility_id ||
      (await resolveOperationalFacilityId({
        facilityId: filters?.facility_id || null,
        userId: scope.user_id || null,
        tenantId: scope.tenant_id || null}));

    if (filters.storage_room_id || filters.storage_shelf_id) {
      const storageAssignment = await resolveStorageAssignment(
        {
          storage_room_id: filters.storage_room_id || null,
          storage_shelf_id: filters.storage_shelf_id || null},
        scope,
        facilityId
      );
      const drugIds = await pharmacyStorageRepository.findDrugIdsByStorageFilters(
        scope.tenant_id,
        {
          storage_room_id: storageAssignment.storageRoomId,
          storage_shelf_id: storageAssignment.storageShelfId}
      );
      where.id = { in: drugIds?.length ? drugIds : ['__no_match__'] };
    }

    const [records, total] = await Promise.all([
      pharmacyWorkspaceRepository.findManyDrugs(
        where,
        skip,
        limit,
        orderBy,
        buildDrugStockInclude(scope)
      ),
      pharmacyWorkspaceRepository.countDrugs(where)]);

    let offeringByDrugId = new Map();
    const facilityIdForOfferings = facilityId;

    if (facilityIdForOfferings && records.length) {
      const offeringRows = await facilityPharmacyCatalogRepository.findDrugOfferings(
        {
          tenant_id: scope.tenant_id,
          facility_id: facilityId,
          drug_id: { in: records.map((row) => row.id) },
          is_active: true},
        0,
        records.length
      );
      offeringByDrugId = new Map(offeringRows.map((row) => [row.drug_id, row]));
    }

    const stockStatus = String(filters?.stock_status || '').trim().toUpperCase();
    const drugs = await attachDrugStorageSummaries(
      records
        .map((record) => mapMergedDrugRecord(record, offeringByDrugId.get(record.id) || null))
        .filter(Boolean)
        .filter((drug) => !stockStatus || drug.stock_status === stockStatus)
    );

    return {
      summary: {
        total_drugs: total,
        returned_drugs: drugs.length},
      drugs,
      pagination: buildPagination(page, limit, total)};
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

const createPharmacyOrder = async (payload = {}, userId, ipAddress, user = {}) => {
  try {
    const created = await pharmacyOrderService.createPharmacyOrder(
      payload,
      userId,
      ipAddress,
      user
    );
    const scope = resolveScopedUserContext(user);
    const orderId = await resolveScopedOrderId(created?.id || created?.display_id, scope);
    const orderRecord = ensureScopedOrderRecord(
      await pharmacyWorkspaceRepository.findOrderById(
        orderId,
        PHARMACY_ORDER_WITH_RELATIONS_INCLUDE
      ),
      scope
    );
    const workflow = await mapScopedPharmacyOrderWorkflowRecord(orderRecord, scope);

    publishPharmacyRealtimeUpdates({
      workflow,
      orderRecord,
      actorUserId: userId || null,
      action: 'CREATE_ORDER',
      resourceType: 'order',
      resourceId: workflow?.order?.id || null}).catch(() => {});

    const orderSummary = await buildWorkbenchSummary(
      await buildWorkbenchOrderWhere({}, scope, { includeSearch: false })
    );

    return {
      workflow,
      order_summary: orderSummary};
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

const prepareDispense = async (identifier, payload = {}, userId, userRole, ipAddress, user = {}) => {
  try {
    const scope = resolveScopedUserContext(user);
    const orderId = await resolveScopedOrderId(identifier, scope);

    const batchRef = normalizeBatchRef(payload.dispense_batch_ref) || buildDispenseBatchRef();

    const mutation = await pharmacyWorkspaceRepository.withTransaction(async (tx) => {
      const order = ensureScopedOrderRecord(
        await pharmacyWorkspaceRepository.txFindOrderById(
          tx,
          orderId,
          PHARMACY_ORDER_WITH_RELATIONS_INCLUDE
        ),
        scope
      );

      assertTransition(['ORDERED', 'PARTIALLY_DISPENSED'].includes(order.status), {
        from: order.status,
        to: 'PREPARE_DISPENSE'});

      const existingPrepare = await pharmacyWorkspaceRepository.txFindDispenseAttestation(
        tx,
        order.id,
        batchRef,
        'PREPARE'
      );
      const existingAttest = await pharmacyWorkspaceRepository.txFindDispenseAttestation(
        tx,
        order.id,
        batchRef,
        'ATTEST'
      );

      if (existingPrepare || existingAttest) {
        const refreshedOrder = await pharmacyWorkspaceRepository.txFindOrderById(
          tx,
          order.id,
          PHARMACY_ORDER_WITH_RELATIONS_INCLUDE
        );
        return {
          order: refreshedOrder,
          batchRef,
          prepareAttestation: existingPrepare,
          stockRecords: [],
          finalized: Boolean(existingAttest)};
      }

      // Dispense finalizes immediately by default. Replace any abandoned pending
      // prepare so pharmacists are not stuck after a prior incomplete attempt.
      const shouldFinalize = payload.finalize !== false;
      let workingOrder = order;
      if (shouldFinalize) {
        const voided = await voidPendingPrepareBatches(tx, workingOrder);
        if (voided.length) {
          workingOrder = ensureScopedOrderRecord(
            await pharmacyWorkspaceRepository.txFindOrderById(
              tx,
              order.id,
              PHARMACY_ORDER_WITH_RELATIONS_INCLUDE
            ),
            scope
          );
        }
      } else {
        const pendingBatchRefs = listPendingAttestationBatchRefs(workingOrder).filter(
          (entry) => entry !== batchRef
        );
        assertTransition(pendingBatchRefs.length === 0, {
          reason: 'pending_attestation_exists',
          requested_batch_ref: batchRef,
          pending_batch_refs: pendingBatchRefs});
      }

      const explicitLines = Array.isArray(payload.items) && payload.items.length ? payload.items : null;
      const sourceItems = explicitLines
        ? explicitLines
        : (workingOrder.items || []).map((item) => ({
            order_item_id: item.human_friendly_id || item.id,
            quantity: computeItemDispensedMetrics(item).remaining}));

      const targetLines = [];
      for (const line of sourceItems) {
        const orderItem = resolveOrderItemByIdentifier(workingOrder, line.order_item_id);
        if (!orderItem) {
          throw new HttpError('errors.pharmacy_order_item.not_found', 404);
        }

        const quantity = Number(line.quantity || 0);
        assertTransition(Number.isFinite(quantity) && quantity > 0, {
          reason: 'invalid_quantity',
          order_item_id: line.order_item_id});

        const metrics = computeItemDispensedMetrics(orderItem);
        if (quantity > metrics.remaining) {
          throw new HttpError('errors.pharmacy_workspace.quantity_exceeds_remaining', 400, [
            {
              field: 'quantity',
              order_item_id: line.order_item_id,
              remaining: metrics.remaining,
              requested: quantity}]);
        }

        const inventoryMap = await resolveInventoryMapForItem({
          tx,
          item: orderItem,
          tenantId: workingOrder.patient?.tenant_id || null,
          inventoryItemIdentifier: line.inventory_item_id || null});
        if (!inventoryMap) {
          throw new HttpError('errors.pharmacy_workspace.inventory_map.required', 400, [
            { order_item_id: orderItem.id }]);
        }

        targetLines.push({
          orderItem,
          quantity});
      }

      if (!targetLines.length) {
        throw new HttpError('errors.pharmacy_workspace.nothing_to_dispense', 400);
      }

      for (const line of targetLines) {
        await pharmacyWorkspaceRepository.txCreateDispenseLog(tx, {
          pharmacy_order_item_id: line.orderItem.id,
          dispense_batch_ref: batchRef,
          status: 'PENDING',
          quantity_dispensed: line.quantity});
      }

      const prepareAttestation = await pharmacyWorkspaceRepository.txCreateDispenseAttestation(tx, {
        pharmacy_order_id: workingOrder.id,
        dispense_batch_ref: batchRef,
        phase: 'PREPARE',
        attested_by_user_id: userId,
        attested_role: userRole || null,
        statement: payload.statement || null,
        reason: payload.reason || null,
        ip_address: ipAddress || null,
        attested_at: new Date()});

      if (!shouldFinalize) {
        const refreshedOrder = await pharmacyWorkspaceRepository.txFindOrderById(
          tx,
          workingOrder.id,
          PHARMACY_ORDER_WITH_RELATIONS_INCLUDE
        );
        return {
          order: refreshedOrder,
          batchRef,
          prepareAttestation,
          stockRecords: [],
          finalized: false};
      }

      const finalized = await finalizePendingDispenseBatch({
        tx,
        order: workingOrder,
        scope,
        batchRef,
        userId,
        userRole,
        ipAddress,
        payload,
        allowSameUser: true});

      return {
        ...finalized,
        prepareAttestation,
        finalized: true};
    });

    createAuditLog({
      user_id: userId,
      action: mutation.finalized ? 'DISPENSE' : 'PREPARE_DISPENSE',
      entity: 'pharmacy_order',
      entity_id: mutation.order?.id,
      diff: {
        metadata: {
          dispense_batch_ref: mutation.batchRef,
          finalized: Boolean(mutation.finalized),
          line_count: Array.isArray(payload.items) ? payload.items.length : null}},
      ip_address: ipAddress}).catch(() => {});

    const workflow = await mapScopedPharmacyOrderWorkflowRecord(mutation.order, scope);

    publishPharmacyRealtimeUpdates({
      workflow,
      orderRecord: mutation.order,
      actorUserId: userId || null,
      action: mutation.finalized ? 'DISPENSE' : 'PREPARE_DISPENSE',
      resourceType: 'dispense_batch',
      resourceId: mutation.batchRef,
      batchRef: mutation.batchRef,
      stockRecords: mutation.stockRecords || []}).catch(() => {});

    const orderSummary = await buildWorkbenchSummary(
      await buildWorkbenchOrderWhere({}, scope, { includeSearch: false })
    );

    const response = {
      workflow,
      dispense_batch_ref: mutation.batchRef,
      order_summary: orderSummary};

    if (mutation.finalized) {
      const stockSummaryWhere = await buildInventoryStockWhere({}, scope, { includeSearch: false });
      response.stocks = (mutation.stockRecords || [])
        .map((record) => mapInventoryStockRecord(record))
        .filter(Boolean);
      response.stock_summary = summarizeStockMetrics(
        await pharmacyWorkspaceRepository.findInventoryStockMetrics(stockSummaryWhere)
      );
    }

    return response;
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

const attestDispense = async (identifier, payload = {}, userId, userRole, ipAddress, user = {}) => {
  try {
    const scope = resolveScopedUserContext(user);
    const orderId = await resolveScopedOrderId(identifier, scope);

    const batchRef = normalizeBatchRef(payload.dispense_batch_ref);
    if (!batchRef) {
      throw new HttpError('errors.validation.failed', 400, [{ field: 'dispense_batch_ref' }]);
    }

    const mutation = await pharmacyWorkspaceRepository.withTransaction(async (tx) => {
      const order = ensureScopedOrderRecord(
        await pharmacyWorkspaceRepository.txFindOrderById(
          tx,
          orderId,
          PHARMACY_ORDER_WITH_RELATIONS_INCLUDE
        ),
        scope
      );

      assertTransition(['ORDERED', 'PARTIALLY_DISPENSED'].includes(order.status), {
        from: order.status,
        to: 'ATTEST_DISPENSE'});

      return finalizePendingDispenseBatch({
        tx,
        order,
        scope,
        batchRef,
        userId,
        userRole,
        ipAddress,
        payload,
        allowSameUser: false});
    });

    createAuditLog({
      user_id: userId,
      action: 'ATTEST_DISPENSE',
      entity: 'pharmacy_order',
      entity_id: mutation.order?.id,
      diff: {
        metadata: {
          dispense_batch_ref: mutation.batchRef,
          attestation_id: mutation.attestation?.id || null}},
      ip_address: ipAddress}).catch(() => {});

    const workflow = await mapScopedPharmacyOrderWorkflowRecord(mutation.order, scope);

    publishPharmacyRealtimeUpdates({
      workflow,
      orderRecord: mutation.order,
      actorUserId: userId || null,
      action: 'ATTEST_DISPENSE',
      resourceType: 'dispense_batch',
      resourceId: mutation.batchRef,
      batchRef: mutation.batchRef,
      stockRecords: mutation.stockRecords}).catch(() => {});

    const stockSummaryWhere = await buildInventoryStockWhere({}, scope, { includeSearch: false });
    const stockSummary = summarizeStockMetrics(
      await pharmacyWorkspaceRepository.findInventoryStockMetrics(stockSummaryWhere)
    );
    const orderSummary = await buildWorkbenchSummary(
      await buildWorkbenchOrderWhere({}, scope, { includeSearch: false })
    );

    return {
      workflow,
      dispense_batch_ref: mutation.batchRef,
      order_summary: orderSummary,
      stocks: mutation.stockRecords.map((record) => mapInventoryStockRecord(record)).filter(Boolean),
      stock_summary: stockSummary};
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

const cancelPharmacyOrder = async (identifier, payload = {}, userId, _userRole, ipAddress, user = {}) => {
  try {
    const scope = resolveScopedUserContext(user);
    const orderId = await resolveScopedOrderId(identifier, scope);

    const mutation = await pharmacyWorkspaceRepository.withTransaction(async (tx) => {
      const order = ensureScopedOrderRecord(
        await pharmacyWorkspaceRepository.txFindOrderById(
          tx,
          orderId,
          PHARMACY_ORDER_WITH_RELATIONS_INCLUDE
        ),
        scope
      );

      assertTransition(['ORDERED', 'PARTIALLY_DISPENSED'].includes(order.status), {
        from: order.status,
        to: 'CANCELLED'});

      await pharmacyWorkspaceRepository.txUpdateManyDispenseLogs(
        tx,
        {
          status: 'PENDING',
          pharmacy_order_item: {
            pharmacy_order_id: order.id}},
        {
          status: 'CANCELLED'}
      );

      await tx.pharmacy_order_item.updateMany({
        where: {
          pharmacy_order_id: order.id,
          NOT: { status: 'CANCELLED' }},
        data: { status: 'CANCELLED' }});

      await pharmacyWorkspaceRepository.txUpdateOrder(tx, order.id, {
        status: 'CANCELLED'});

      await clearPharmacyOrderBilling(tx, order);

      const refreshedOrder = await pharmacyWorkspaceRepository.txFindOrderById(
        tx,
        order.id,
        PHARMACY_ORDER_WITH_RELATIONS_INCLUDE
      );

      return { order: refreshedOrder };
    });

    createAuditLog({
      user_id: userId,
      action: 'CANCEL',
      entity: 'pharmacy_order',
      entity_id: mutation.order?.id,
      diff: {
        metadata: {
          reason: payload.reason || null,
          notes: payload.notes || null}},
      ip_address: ipAddress}).catch(() => {});

    const workflow = await mapScopedPharmacyOrderWorkflowRecord(mutation.order, scope);

    publishPharmacyRealtimeUpdates({
      workflow,
      orderRecord: mutation.order,
      actorUserId: userId || null,
      action: 'CANCEL_ORDER',
      resourceType: 'order',
      resourceId: workflow?.order?.id || null}).catch(() => {});

    const orderSummary = await buildWorkbenchSummary(
      await buildWorkbenchOrderWhere({}, scope, { includeSearch: false })
    );

    return {
      workflow,
      order_summary: orderSummary};
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

const cancelPharmacyOrderItem = async (
  orderIdentifier,
  itemIdentifier,
  payload = {},
  userId,
  _userRole,
  ipAddress,
  user = {}
) => {
  try {
    const scope = resolveScopedUserContext(user);
    const orderId = await resolveScopedOrderId(orderIdentifier, scope);

    const mutation = await pharmacyWorkspaceRepository.withTransaction(async (tx) => {
      const order = ensureScopedOrderRecord(
        await pharmacyWorkspaceRepository.txFindOrderById(
          tx,
          orderId,
          PHARMACY_ORDER_WITH_RELATIONS_INCLUDE
        ),
        scope
      );

      assertTransition(['ORDERED', 'PARTIALLY_DISPENSED'].includes(order.status), {
        from: order.status,
        to: 'CANCEL_ITEM'});

      const orderItem = resolveOrderItemByIdentifier(order, itemIdentifier);
      if (!orderItem) {
        throw new HttpError('errors.pharmacy_order_item.not_found', 404);
      }

      assertTransition(String(orderItem.status || '').toUpperCase() !== 'CANCELLED', {
        reason: 'item_already_cancelled',
        order_item_id: orderItem.id});

      await tx.pharmacy_order_item.update({
        where: { id: orderItem.id },
        data: { status: 'CANCELLED' }});

      await pharmacyWorkspaceRepository.txUpdateManyDispenseLogs(
        tx,
        {
          status: 'PENDING',
          pharmacy_order_item_id: orderItem.id},
        {
          status: 'CANCELLED'}
      );

      const remainingActive = (order.items || []).filter((item) => {
        if (!item || item.id === orderItem.id) return false;
        return String(item.status || '').toUpperCase() !== 'CANCELLED';
      });

      if (!remainingActive.length) {
        await pharmacyWorkspaceRepository.txUpdateOrder(tx, order.id, {
          status: 'CANCELLED'});
        await clearPharmacyOrderBilling(tx, order);
      } else {
        // Refresh after item cancel so billing rebuild sees CANCELLED status.
        const orderAfterItemCancel = await pharmacyWorkspaceRepository.txFindOrderById(
          tx,
          order.id,
          PHARMACY_ORDER_WITH_RELATIONS_INCLUDE
        );
        await reconcilePendingPharmacyBillingAfterItemCancel(tx, orderAfterItemCancel);
      }

      const refreshedOrder = await pharmacyWorkspaceRepository.txFindOrderById(
        tx,
        order.id,
        PHARMACY_ORDER_WITH_RELATIONS_INCLUDE
      );

      return { order: refreshedOrder, orderItemId: orderItem.id };
    });

    createAuditLog({
      user_id: userId,
      action: 'CANCEL',
      entity: 'pharmacy_order_item',
      entity_id: mutation.orderItemId,
      diff: {
        metadata: {
          reason: payload.reason || null,
          notes: payload.notes || null,
          pharmacy_order_id: mutation.order?.id || null}},
      ip_address: ipAddress}).catch(() => {});

    const workflow = await mapScopedPharmacyOrderWorkflowRecord(mutation.order, scope);

    publishPharmacyRealtimeUpdates({
      workflow,
      orderRecord: mutation.order,
      actorUserId: userId || null,
      action: 'CANCEL_ORDER_ITEM',
      resourceType: 'order_item',
      resourceId: mutation.orderItemId || null}).catch(() => {});

    const orderSummary = await buildWorkbenchSummary(
      await buildWorkbenchOrderWhere({}, scope, { includeSearch: false })
    );

    return {
      workflow,
      order_summary: orderSummary};
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

const returnDispense = async (identifier, payload = {}, userId, userRole, ipAddress, user = {}) => {
  try {
    const scope = resolveScopedUserContext(user);
    const orderId = await resolveScopedOrderId(identifier, scope);

    const mutation = await pharmacyWorkspaceRepository.withTransaction(async (tx) => {
      const order = ensureScopedOrderRecord(
        await pharmacyWorkspaceRepository.txFindOrderById(
          tx,
          orderId,
          PHARMACY_ORDER_WITH_RELATIONS_INCLUDE
        ),
        scope
      );

      assertTransition(['DISPENSED', 'PARTIALLY_DISPENSED'].includes(order.status), {
        from: order.status,
        to: 'RETURN'});

      const resolvedFacilityId = await resolveScopedFacilityId(
        payload.facility_id || order.patient?.facility_id || null,
        scope,
        true
      );

      const stockRecords = [];
      const returnedAt = new Date();

      for (const line of payload.items || []) {
        const orderItem = resolveOrderItemByIdentifier(order, line.order_item_id);
        if (!orderItem) {
          throw new HttpError('errors.pharmacy_order_item.not_found', 404);
        }

        const quantity = Number(line.quantity || 0);
        assertTransition(Number.isFinite(quantity) && quantity > 0, {
          reason: 'invalid_return_quantity',
          order_item_id: line.order_item_id});

        const metrics = computeItemDispensedMetrics(orderItem);
        assertTransition(quantity <= metrics.netDispensed, {
          reason: 'return_exceeds_dispensed',
          order_item_id: line.order_item_id,
          dispensed: metrics.netDispensed,
          requested: quantity});

        const inventoryMap = await resolveInventoryMapForItem({
          tx,
          item: orderItem,
          tenantId: order.patient?.tenant_id || null,
          inventoryItemIdentifier: line.inventory_item_id || null});
        if (!inventoryMap) {
          throw new HttpError('errors.pharmacy_workspace.inventory_map.required', 400, [
            { order_item_id: orderItem.id }]);
        }

        const stockDelta = normalizeStockDeductionQuantity(quantity, inventoryMap.deduction_factor);

        let stock = await pharmacyWorkspaceRepository.txFindStockByInventoryItemAndFacility(
          tx,
          inventoryMap.inventory_item_id,
          resolvedFacilityId,
          INVENTORY_STOCK_WITH_RELATIONS_INCLUDE
        );

        if (!stock) {
          stock = await pharmacyWorkspaceRepository.txCreateInventoryStock(tx, {
            inventory_item_id: inventoryMap.inventory_item_id,
            facility_id: resolvedFacilityId,
            quantity: 0,
            reorder_level: 0});
        } else {
          ensureScopedInventoryStockRecord(stock, scope);
        }

        const updatedStock = await pharmacyWorkspaceRepository.txUpdateInventoryStock(tx, stock.id, {
          quantity: Number(stock.quantity || 0) + stockDelta});

        await pharmacyWorkspaceRepository.txCreateStockMovement(tx, {
          inventory_item_id: inventoryMap.inventory_item_id,
          facility_id: resolvedFacilityId,
          movement_type: 'INBOUND',
          reason: 'RETURN',
          quantity: stockDelta,
          occurred_at: returnedAt});

        await pharmacyWorkspaceRepository.txCreateDispenseLog(tx, {
          pharmacy_order_item_id: orderItem.id,
          dispense_batch_ref: null,
          status: 'RETURNED',
          quantity_dispensed: quantity,
          dispensed_at: returnedAt});

        stockRecords.push({
          ...stock,
          ...updatedStock});
      }

      let refreshedOrder = await pharmacyWorkspaceRepository.txFindOrderById(
        tx,
        order.id,
        PHARMACY_ORDER_WITH_RELATIONS_INCLUDE
      );

      await syncOrderItemStatusesAfterDispense(tx, refreshedOrder);

      const rolledUpStatus = rollupOrderStatus(refreshedOrder);
      const billingReconciled = await reconcilePendingPharmacyBillingAfterDispense(
        tx,
        refreshedOrder
      );
      if (refreshedOrder.status !== rolledUpStatus) {
        await pharmacyWorkspaceRepository.txUpdateOrder(tx, order.id, {
          status: rolledUpStatus});
      }
      if (refreshedOrder.status !== rolledUpStatus || billingReconciled) {
        refreshedOrder = await pharmacyWorkspaceRepository.txFindOrderById(
          tx,
          order.id,
          PHARMACY_ORDER_WITH_RELATIONS_INCLUDE
        );
      }

      await pharmacyWorkspaceRepository.txCreateDispenseAttestation(tx, {
        pharmacy_order_id: order.id,
        dispense_batch_ref: `RETURN-${buildDispenseBatchRef()}`,
        phase: 'PREPARE',
        attested_by_user_id: userId,
        attested_role: userRole || null,
        statement: payload.notes || null,
        reason: payload.reason || 'RETURN',
        ip_address: ipAddress || null,
        attested_at: returnedAt});

      return {
        order: refreshedOrder,
        stockRecords};
    });

    createAuditLog({
      user_id: userId,
      action: 'RETURN_DISPENSE',
      entity: 'pharmacy_order',
      entity_id: mutation.order?.id,
      diff: {
        metadata: {
          item_count: Array.isArray(payload.items) ? payload.items.length : 0,
          reason: payload.reason || null}},
      ip_address: ipAddress}).catch(() => {});

    const workflow = await mapScopedPharmacyOrderWorkflowRecord(mutation.order, scope);

    publishPharmacyRealtimeUpdates({
      workflow,
      orderRecord: mutation.order,
      actorUserId: userId || null,
      action: 'RETURN_DISPENSE',
      resourceType: 'order',
      resourceId: workflow?.order?.id || null,
      stockRecords: mutation.stockRecords}).catch(() => {});

    const stockSummaryWhere = await buildInventoryStockWhere({}, scope, { includeSearch: false });
    const stockSummary = summarizeStockMetrics(
      await pharmacyWorkspaceRepository.findInventoryStockMetrics(stockSummaryWhere)
    );
    const orderSummary = await buildWorkbenchSummary(
      await buildWorkbenchOrderWhere({}, scope, { includeSearch: false })
    );

    return {
      workflow,
      order_summary: orderSummary,
      stocks: mutation.stockRecords.map((record) => mapInventoryStockRecord(record)).filter(Boolean),
      stock_summary: stockSummary};
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

const getInventoryStock = async (filters, page, limit, sortBy, order, user = {}) => {
  try {
    const scope = resolveScopedUserContext(user);
    const skip = (page - 1) * limit;
    const orderBy = sortBy ? { [sortBy]: order } : { updated_at: 'desc' };
    const expiringWithinDays = Number(filters.expiring_within_days || EXPIRING_SOON_DAYS);

    // A pharmacy user sees their own pharmacy's balances. Reading another
    // pharmacy's stock goes through the availability endpoint, which returns
    // quantities only.
    const actingLocation = await resolveActingPharmacyLocation(prisma, {
      explicitLocationId: filters.pharmacy_location_id,
      scope,
      user});
    if (actingLocation) {
      await assertLocationAccess(prisma, {
        location: actingLocation,
        user,
        level: ACCESS_LEVELS.VIEW});
    }
    const locationOptions = { pharmacyLocationId: actingLocation?.id || null };

    const [where, summaryWhere] = await Promise.all([
      buildInventoryStockWhere(filters, scope, { includeSearch: true, ...locationOptions }),
      buildInventoryStockWhere(filters, scope, { includeSearch: false, ...locationOptions })]);

    const facilityId =
      scope.facility_id ||
      (filters.facility_id
        ? await resolveScopedFacilityId(filters.facility_id, scope)
        : null);

    const [expiringSoonRows, expiredRows, stockMetrics] = await Promise.all([
      pharmacyWorkspaceRepository.countInventoryRowsWithExpiringBatches(
        scope.tenant_id,
        facilityId,
        EXPIRING_SOON_DAYS
      ),
      pharmacyWorkspaceRepository.countInventoryRowsWithExpiredBatches(
        scope.tenant_id,
        facilityId
      ),
      pharmacyWorkspaceRepository.findInventoryStockMetrics(summaryWhere)]);
    const stockSummary = summarizeStockMetrics(stockMetrics, {
      expiring_soon_rows: expiringSoonRows,
      expired_rows: expiredRows});

    if (needsPostStockStatusFilter(filters)) {
      const allRecords = await pharmacyWorkspaceRepository.findManyInventoryStocks(
        where,
        0,
        10000,
        orderBy,
        INVENTORY_STOCK_WITH_RELATIONS_INCLUDE
      );
      const stockStatus = String(filters.stock_status || '').trim().toUpperCase();
      const stocks = (await enrichInventoryStockRecords(allRecords, expiringWithinDays)).filter(
        (record) => record.stock_status === stockStatus
      );
      const total = stocks.length;
      const pagedStocks = stocks.slice(skip, skip + limit);

      return {
        summary: stockSummary,
        stocks: pagedStocks,
        pagination: buildPagination(page, limit, total)};
    }

    const [records, total] = await Promise.all([
      pharmacyWorkspaceRepository.findManyInventoryStocks(
        where,
        skip,
        limit,
        orderBy,
        INVENTORY_STOCK_WITH_RELATIONS_INCLUDE
      ),
      pharmacyWorkspaceRepository.countInventoryStocks(where)]);

    const stocks = await enrichInventoryStockRecords(records, expiringWithinDays);

    return {
      summary: stockSummary,
      stocks,
      pagination: buildPagination(page, limit, total)};
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

const adjustInventoryStock = async (payload = {}, userId, _userRole, ipAddress, user = {}) => {
  try {
    const scope = resolveScopedUserContext(user);
    const inventoryItemId = await resolveScopedInventoryItemId(payload.inventory_item_id, scope);
    const facilityId = await resolveScopedFacilityId(payload.facility_id || null, scope, true);
    const quantityDelta = Number(payload.quantity_delta || 0);
    const reorderLevel =
      payload.reorder_level !== undefined ? Number(payload.reorder_level) : undefined;
    const storageAssignment = await resolveStorageAssignment(payload, scope, facilityId);

    // Adjusting a balance means adjusting one pharmacy's balance, and needs a
    // MANAGE grant on it. Batch, expiry and cost metadata are procurement
    // records, so those additionally require the procurement pharmacy - which
    // is what keeps Hospital Pharmacy users out of Main Pharmacy batches.
    const actingLocation = await resolveActingPharmacyLocation(prisma, {
      explicitLocationId: payload.pharmacy_location_id,
      scope,
      user});
    const touchesProcurementRecords = Boolean(
      String(payload.batch_number || '').trim() ||
        payload.manufactured_at ||
        payload.expiry_date ||
        payload.expiry_alert_lead_days != null ||
        payload.unit_cost !== undefined
    );
    if (actingLocation) {
      if (touchesProcurementRecords) {
        await assertProcurementAccess(prisma, { location: actingLocation, user });
      } else {
        await assertLocationAccess(prisma, {
          location: actingLocation,
          user,
          level: ACCESS_LEVELS.MANAGE});
      }
    }

    const mutation = await pharmacyWorkspaceRepository.withTransaction(async (tx) => {
      let stock = actingLocation
        ? await tx.inventory_stock.findFirst({
            where: {
              deleted_at: null,
              inventory_item_id: inventoryItemId,
              pharmacy_location_id: actingLocation.id},
            include: INVENTORY_STOCK_WITH_RELATIONS_INCLUDE})
        : await pharmacyWorkspaceRepository.txFindStockByInventoryItemAndFacility(
            tx,
            inventoryItemId,
            facilityId,
            INVENTORY_STOCK_WITH_RELATIONS_INCLUDE
          );

      if (!stock) {
        stock = await pharmacyWorkspaceRepository.txCreateInventoryStock(tx, {
          inventory_item_id: inventoryItemId,
          facility_id: facilityId,
          pharmacy_location_id: actingLocation?.id || null,
          quantity: 0,
          reorder_level: reorderLevel !== undefined ? reorderLevel : 0});
      } else {
        ensureScopedInventoryStockRecord(stock, scope);
      }

      const nextQuantity = Number(stock.quantity || 0) + quantityDelta;

      assertTransition(nextQuantity >= 0, {
        reason: 'negative_stock_after_adjustment',
        current: Number(stock.quantity || 0),
        delta: quantityDelta});

      const stockUpdate = {};
      if (quantityDelta !== 0) {
        stockUpdate.quantity = nextQuantity;
      }
      if (reorderLevel !== undefined) {
        stockUpdate.reorder_level = reorderLevel;
      }

      if (Object.keys(stockUpdate).length > 0) {
        await pharmacyWorkspaceRepository.txUpdateInventoryStock(tx, stock.id, stockUpdate);
      }

      let movement = null;
      if (quantityDelta !== 0) {
        movement = await pharmacyWorkspaceRepository.txCreateStockMovement(tx, {
          inventory_item_id: inventoryItemId,
          facility_id: facilityId,
          pharmacy_location_id: actingLocation?.id || null,
          movement_type: 'ADJUSTMENT',
          reason: payload.reason || 'OTHER',
          quantity: Math.abs(quantityDelta),
          occurred_at: toDateOrNull(payload.occurred_at, new Date())});
      }

      const batchNumber = String(payload.batch_number || '').trim();
      const manufacturedAt = toDateOrNull(payload.manufactured_at, null);
      const expiryDate = toDateOrNull(payload.expiry_date, null);
      const expiryAlertLeadDays =
        payload.expiry_alert_lead_days == null
          ? null
          : Number(payload.expiry_alert_lead_days);
      const hasBatchMeta =
        Boolean(batchNumber) ||
        Boolean(manufacturedAt) ||
        Boolean(expiryDate) ||
        expiryAlertLeadDays != null;
      const hasStorageChange = Boolean(
        storageAssignment.storageRoomId || storageAssignment.storageShelfId
      );
      if (hasBatchMeta || hasStorageChange) {
        let drugId = null;
        if (payload.drug_id) {
          drugId = await resolveModelIdOrThrow({
            identifier: payload.drug_id,
            model: 'drug',
            where: { deleted_at: null, ...buildDrugScopeWhere(scope) },
            errorKey: 'errors.drug.not_found'});
        } else {
          const inventoryMap = await pharmacyWorkspaceRepository.txFindInventoryMapByInventoryItem(
            tx,
            inventoryItemId,
            scope.tenant_id
          );
          drugId = inventoryMap?.drug_id || null;
        }

        if (drugId) {
          await upsertDrugBatchForReceipt(tx, {
            drugId,
            batchNumber: batchNumber || 'UNLABELED',
            manufacturedAt,
            expiryDate,
            expiryAlertLeadDays,
            quantityDelta: quantityDelta > 0 ? quantityDelta : 0,
            storageRoomId: storageAssignment.storageRoomId,
            storageShelfId: storageAssignment.storageShelfId,
            pharmacyLocationId: actingLocation?.id || null});
        }
      }

      const refreshedStock = actingLocation
        ? await tx.inventory_stock.findFirst({
            where: {
              deleted_at: null,
              inventory_item_id: inventoryItemId,
              pharmacy_location_id: actingLocation.id},
            include: INVENTORY_STOCK_WITH_RELATIONS_INCLUDE})
        : await pharmacyWorkspaceRepository.txFindStockByInventoryItemAndFacility(
            tx,
            inventoryItemId,
            facilityId,
            INVENTORY_STOCK_WITH_RELATIONS_INCLUDE
          );

      return {
        stock: refreshedStock
          ? ensureScopedInventoryStockRecord(refreshedStock, scope)
          : { ...stock, ...stockUpdate },
        movement};
    });

    createAuditLog({
      user_id: userId,
      action: 'ADJUST_STOCK',
      entity: 'inventory_stock',
      entity_id: mutation.stock?.id || null,
      diff: {
        metadata: {
          inventory_item_id: inventoryItemId,
          quantity_delta: quantityDelta,
          reorder_level: reorderLevel,
          reason: payload.reason || null,
          notes: payload.notes || null,
          batch_number: payload.batch_number || null}},
      ip_address: ipAddress}).catch(() => {});

    const stockSummaryWhere = await buildInventoryStockWhere({}, scope, { includeSearch: false });
    const facilityIdForSummary =
      scope.facility_id ||
      (await resolveScopedFacilityId(payload.facility_id || null, scope, true));
    const [stockMetrics, expiringSoonRows] = await Promise.all([
      pharmacyWorkspaceRepository.findInventoryStockMetrics(stockSummaryWhere),
      pharmacyWorkspaceRepository.countInventoryRowsWithExpiringBatches(
        scope.tenant_id,
        facilityIdForSummary,
        EXPIRING_SOON_DAYS
      )]);
    const stockSummary = summarizeStockMetrics(stockMetrics, {
      expiring_soon_rows: expiringSoonRows});

    const [enrichedStock] = await enrichInventoryStockRecords(
      mutation.stock ? [mutation.stock] : [],
      EXPIRING_SOON_DAYS
    );

    try {
      const recipientUserIds = await resolveRoleRecipients({
        tenantId: scope.tenant_id,
        facilityId: facilityIdForSummary});
      const recipients = [...new Set(recipientUserIds.filter(Boolean))];
      if (recipients.length) {
        const stockPayload = enrichedStock
          ? [mapInventoryStockRecord(enrichedStock)].filter(Boolean)
          : [];
        emitToUsers(recipients, INVENTORY_EVENTS.INVENTORY_STOCK_UPDATED, {
          tenant_id: scope.tenant_id,
          facility_id: facilityIdForSummary,
          actor_user_id: userId || null,
          action: 'ADJUST_STOCK',
          occurred_at: new Date().toISOString(),
          stocks: stockPayload});
      }
    } catch (_error) {
      // realtime delivery must not block stock adjustments
    }

    return {
      stock: enrichedStock || null,
      stock_summary: stockSummary,
      movement: mutation.movement
        ? {
            id: toPublicIdentifier(mutation.movement?.human_friendly_id, mutation.movement?.id),
            movement_type: mutation.movement?.movement_type || null,
            reason: mutation.movement?.reason || null,
            quantity: Number(mutation.movement?.quantity || 0),
            occurred_at: mutation.movement?.occurred_at
              ? new Date(mutation.movement.occurred_at).toISOString()
              : null}
        : null};
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

const setupPharmacyDrug = async (payload = {}, userId, ipAddress, user = {}) => {
  try {
    const scope = resolveScopedUserContext(user);
    const confirmSimilar = payload?.confirm_similar === true;
    const data = stripDrugSimilarityPayloadFields(payload);
    assertPharmacyRetailPriceMutationAllowed(user, data);
    let tenantId = scope.tenant_id;
    if (scope.can_manage_all_tenants) {
      tenantId = await resolveIdentifierForPayload({
        value: data.tenant_id,
        field: 'tenant_id',
        model: 'tenant',
        where: { deleted_at: null }});
    }

    await assertPharmacyDrugUniqueness({
      tenantId,
      name: data.name,
      genericName: data.generic_name,
      brandName: data.brand_name,
      code: data.code,
      form: data.form,
      strength: data.strength,
      confirmSimilar});

    const facilityId = await resolveScopedFacilityId(data.facility_id || null, scope, true);
    const storageAssignment = await resolveStorageAssignment(data, scope, facilityId);
    const initialStock = Number(data.initial_stock || 0);
    const reorderLevel = Number(data.reorder_level || 0);
    const batchNumber = String(data.batch_number || '').trim();
    const manufacturedAt = toDateOrNull(data.manufactured_at, null);
    const expiryDate = toDateOrNull(data.expiry_date, null);
    const expiryAlertLeadDays =
      data.expiry_alert_lead_days == null
        ? null
        : Number(data.expiry_alert_lead_days);

    const mutation = await pharmacyWorkspaceRepository.withTransaction(async (tx) => {
      const drug = await pharmacyWorkspaceRepository.txCreateDrug(tx, {
        tenant_id: tenantId,
        name: data.name,
        brand_name: data.brand_name || null,
        generic_name: data.generic_name || null,
        code: data.code || null,
        form: data.form || null,
        strength: data.strength || null,
        buy_unit_price: data.buy_unit_price ?? null,
        unit_price: data.unit_price ?? null,
        transfer_unit_price: data.transfer_unit_price ?? null,
        currency: data.currency || null});

      const inventoryName = [data.name, data.strength, data.form]
        .map((value) => String(value || '').trim())
        .filter(Boolean)
        .join(' ');

      const inventoryItem = await pharmacyWorkspaceRepository.txCreateInventoryItem(tx, {
        tenant_id: tenantId,
        name: inventoryName || data.name,
        category: 'MEDICATION',
        sku: data.code || null,
        unit: data.inventory_unit || 'unit'});

      await pharmacyWorkspaceRepository.txCreateDrugInventoryMap(tx, {
        tenant_id: tenantId,
        drug_id: drug.id,
        inventory_item_id: inventoryItem.id,
        is_default: true,
        deduction_factor: 1});

      if (initialStock > 0 || reorderLevel > 0) {
        await pharmacyWorkspaceRepository.txCreateInventoryStock(tx, {
          inventory_item_id: inventoryItem.id,
          facility_id: facilityId,
          quantity: initialStock,
          reorder_level: reorderLevel});

        if (initialStock > 0) {
          await pharmacyWorkspaceRepository.txCreateStockMovement(tx, {
            inventory_item_id: inventoryItem.id,
            facility_id: facilityId,
            movement_type: 'INBOUND',
            reason: 'PURCHASE',
            quantity: initialStock,
            occurred_at: new Date()});
        }
      }

      if (batchNumber || manufacturedAt || expiryDate) {
        await pharmacyWorkspaceRepository.txCreateDrugBatch(tx, {
          drug_id: drug.id,
          batch_number: batchNumber || 'UNLABELED',
          manufactured_at: manufacturedAt,
          expiry_date: expiryDate,
          expiry_alert_lead_days: expiryAlertLeadDays,
          storage_room_id: storageAssignment.storageRoomId,
          storage_shelf_id: storageAssignment.storageShelfId,
          quantity: initialStock});
      }

      return drug;
    });

    const defaultShelfIdentifier =
      data.default_storage_shelf_id || data.storage_shelf_id || null;
    if (defaultShelfIdentifier && facilityId) {
      const defaultStorageShelfId = await resolveDefaultStorageShelfId(
        defaultShelfIdentifier,
        scope,
        facilityId
      );
      const existingOffering = await facilityPharmacyCatalogRepository.findDrugOffering({
        tenant_id: tenantId,
        facility_id: facilityId,
        drug_id: mutation.id});
      if (existingOffering) {
        await facilityPharmacyCatalogRepository.updateDrugOffering(existingOffering.id, {
          default_storage_shelf_id: defaultStorageShelfId});
      } else {
        // Shelf placeholder only — facility tariff is set via offering upsert.
        await facilityPharmacyCatalogRepository.createDrugOffering({
          tenant_id: tenantId,
          facility_id: facilityId,
          drug_id: mutation.id,
          is_active: false,
          sort_order: 0,
          unit_price: 0,
          currency: null,
          default_storage_shelf_id: defaultStorageShelfId});
      }
    }

    createAuditLog({
      tenant_id: tenantId,
      user_id: userId,
      action: 'CREATE',
      entity: 'drug',
      entity_id: mutation.id,
      diff: {
        metadata: {
          initial_stock: initialStock,
          reorder_level: reorderLevel,
          batch_number: batchNumber || null}},
      ip_address: ipAddress}).catch(() => {});

    const drugRecord = await pharmacyWorkspaceRepository.findManyDrugs(
      { id: mutation.id },
      0,
      1,
      { name: 'asc' },
      buildDrugStockInclude(scope)
    );

    let offeringByDrugId = new Map();
    if (facilityId && drugRecord.length) {
      const offeringRows = await facilityPharmacyCatalogRepository.findDrugOfferings(
        {
          tenant_id: tenantId,
          facility_id: facilityId,
          drug_id: mutation.id,
          is_active: true},
        0,
        1
      );
      offeringByDrugId = new Map(offeringRows.map((row) => [row.drug_id, row]));
    }

    return mapMergedDrugRecord(
      drugRecord[0] || mutation,
      offeringByDrugId.get(mutation.id) || null
    );
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

const recordOrderBilling = async (identifier, payload = {}, userId, _userRole, ipAddress, user = {}) => {
  try {
    const scope = resolveScopedUserContext(user);
    const orderId = await resolveScopedOrderId(identifier, scope);
    const billing = payload?.billing;
    if (!billing) {
      throw new HttpError('errors.validation.required', 400, [{ field: 'billing' }]);
    }

    const mutation = await pharmacyWorkspaceRepository.withTransaction(async (tx) => {
      const order = ensureScopedOrderRecord(
        await pharmacyWorkspaceRepository.txFindOrderById(
          tx,
          orderId,
          PHARMACY_ORDER_WITH_RELATIONS_INCLUDE
        ),
        scope
      );

      const patientId = order.patient_id;
      const patientRecord = await tx.patient.findFirst({
        where: { id: patientId, deleted_at: null },
        select: { id: true, tenant_id: true, facility_id: true }});
      if (!patientRecord) {
        throw new HttpError('errors.patient.not_found', 404);
      }

      const existingSnapshot = extractStoredClinicalBilling(order);
      await persistPharmacyOrderBilling(tx, {
        orderId: order.id,
        billing,
        existingSnapshot,
        tenantId: patientRecord.tenant_id,
        facilityId: patientRecord.facility_id || scope.facility_id || null,
        patientId: patientRecord.id,
        description: 'Pharmacy order'});

      const refreshedOrder = await pharmacyWorkspaceRepository.txFindOrderById(
        tx,
        order.id,
        PHARMACY_ORDER_WITH_RELATIONS_INCLUDE
      );

      return { order: refreshedOrder };
    });

    createAuditLog({
      tenant_id: mutation.order?.patient?.tenant_id || scope.tenant_id || null,
      user_id: userId,
      action: 'UPDATE',
      entity: 'pharmacy_order',
      entity_id: mutation.order?.id,
      diff: {
        metadata: {
          billing_recorded: true}},
      ip_address: ipAddress}).catch(() => {});

    const workflow = await mapScopedPharmacyOrderWorkflowRecord(mutation.order, scope);

    publishPharmacyRealtimeUpdates({
      workflow,
      orderRecord: mutation.order,
      actorUserId: userId || null,
      action: 'RECORD_BILLING',
      resourceType: 'order',
      resourceId: workflow?.order?.id || null}).catch(() => {});

    const summaryBaseWhere = await buildWorkbenchOrderWhere(
      { location: undefined, pending_payment: undefined },
      scope,
      { includeSearch: false }
    );
    const orderSummary = await buildWorkbenchSummary(summaryBaseWhere, summaryBaseWhere);

    return {
      workflow,
      order_summary: orderSummary};
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

const resolveLegacyRouteIdentifier = async (resource, identifier, user = {}) => {
  try {
    const scope = resolveScopedUserContext(user);
    const normalizedResource = String(resource || '').trim().toLowerCase();
    const normalizedIdentifier = normalizeIdentifier(identifier);
    if (!normalizedIdentifier) {
      throw new HttpError('errors.resource.not_found', 404);
    }

    const config = LEGACY_ROUTE_CONFIG[normalizedResource];
    if (!config) {
      throw new HttpError('errors.resource.not_found', 404);
    }

    const record = await resolveModelRecordOrThrow({
      identifier: normalizedIdentifier,
      model: config.model,
      where: {
        deleted_at: null,
        ...buildLegacyScopeWhere(config.model, scope)},
      select: {
        id: true,
        human_friendly_id: true},
      errorKey: 'errors.resource.not_found'});

    const publicIdentifier = toPublicIdentifier(record?.human_friendly_id, normalizedIdentifier);
    const safeIdentifier =
      publicIdentifier ||
      (isUuidLike(normalizedIdentifier) ? null : String(normalizedIdentifier).trim().toUpperCase());

    if (!safeIdentifier) {
      throw new HttpError('errors.resource.not_found', 404);
    }

    const routePrefix = config.route || '/pharmacy';
    const hasQuerySuffix = routePrefix.endsWith('=');
    const route = hasQuerySuffix
      ? `${routePrefix}${encodeURIComponent(safeIdentifier)}`
      : `${routePrefix}/${encodeURIComponent(safeIdentifier)}`;

    return {
      id: safeIdentifier,
      resource: config.resource,
      identifier: safeIdentifier,
      route,
      matched_by: isUuidLike(normalizedIdentifier) ? 'uuid' : 'human_friendly_id'};
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

const upsertPharmacyDrugFacilityOffering = async (
  drugIdentifier,
  payload = {},
  userId,
  ipAddress,
  user = {}
) => {
  try {
    const scope = resolveScopedUserContext(user);
    assertFacilityTariffMutationAllowed(user, payload);
    const item = await facilityPharmacyCatalogService.upsertFacilityPharmacyOffering(
      {
        ...payload,
        drug_id: drugIdentifier,
        facility_id: payload.facility_id || scope.facility_id || null,
        tenant_id: payload.tenant_id || scope.tenant_id || null},
      {
        tenant_id: scope.tenant_id,
        user_id: userId,
        facility_id: scope.facility_id || payload.facility_id || null,
        ip_address: ipAddress,
        user}
    );

    // Re-list through pharmacy search enrichment so storage labels match catalog.
    const drugId = await resolveModelIdOrThrow({
      identifier: drugIdentifier,
      model: 'drug',
      where: { deleted_at: null, ...buildDrugScopeWhere(scope) },
      errorKey: 'errors.drug.not_found'});
    const records = await pharmacyWorkspaceRepository.findManyDrugs(
      { id: drugId },
      0,
      1,
      { name: 'asc' },
      buildDrugStockInclude(scope)
    );
    if (!records.length) {
      return item;
    }
    const offeringRows = scope.facility_id
      ? await facilityPharmacyCatalogRepository.findDrugOfferings(
          {
            tenant_id: scope.tenant_id,
            facility_id: scope.facility_id,
            drug_id: drugId,
            is_active: true},
          0,
          1
        )
      : [];
    const enriched = await attachDrugStorageSummaries(
      [mapMergedDrugRecord(records[0], offeringRows[0] || null)].filter(Boolean)
    );
    return enriched[0] || item;
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

module.exports = {
  getPharmacyWorkbench,
  getPharmacyOrderWorkflow,
  searchDrugs,
  setupPharmacyDrug,
  upsertPharmacyDrugFacilityOffering,
  createPharmacyOrder,
  prepareDispense,
  attestDispense,
  cancelPharmacyOrder,
  cancelPharmacyOrderItem,
  returnDispense,
  getInventoryStock,
  adjustInventoryStock,
  recordOrderBilling,
  resolveLegacyRouteIdentifier,
  getPharmacyStorageLayout,
  checkPharmacyStorageRoomSimilarity,
  checkPharmacyStorageShelfSimilarity,
  checkPharmacyDrugSimilarity,
  createPharmacyStorageRoom,
  updatePharmacyStorageRoom,
  createPharmacyStorageShelf,
  updatePharmacyStorageShelf,
  deletePharmacyStorageRoom,
  restorePharmacyStorageRoom,
  permanentDeletePharmacyStorageRoom,
  deletePharmacyStorageShelf};
