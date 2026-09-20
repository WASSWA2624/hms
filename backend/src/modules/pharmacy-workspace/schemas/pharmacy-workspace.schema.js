const { z } = require('zod');
const { listQuerySchema, uuidOrFriendlyIdentifierSchema } = require('@lib/validation/zod');
const { createPharmacyOrderSchema } = require('@validations/pharmacy-order/pharmacy-order.schema');
const { clinicalRequestBillingSchema } = require('@lib/billing/clinical-request-billing.schema');
const { DRUG_IMPORT_SOURCE_IDS } = require('@lib/pharmacy/drug-import/drug-import-sources');

const pharmacyOrderStatusSchema = z.enum([
  'ORDERED',
  'DISPENSED',
  'PARTIALLY_DISPENSED',
  'CANCELLED']);

const pharmacyOrderPrioritySchema = z.enum(['STAT', 'URGENT', 'ROUTINE', 'NORMAL']);

const stockReasonSchema = z.enum(['PURCHASE', 'DISPENSE', 'RETURN', 'DAMAGE', 'EXPIRY', 'OTHER']);

const stockStatusSchema = z.enum([
  'IN_STOCK',
  'ALMOST_OUT_OF_STOCK',
  'LOW_STOCK',
  'OUT_OF_STOCK']);

const panelSchema = z.enum(['orders', 'inventory']);

const orderWorkflowParamsSchema = z.object({
  id: uuidOrFriendlyIdentifierSchema});

const orderLocationSchema = z.enum(['OUTPATIENT', 'INPATIENT', 'DISCHARGE']);

const getPharmacyWorkbenchQuerySchema = listQuerySchema.extend({
  panel: panelSchema.optional(),
  status: pharmacyOrderStatusSchema.optional(),
  location: orderLocationSchema.optional(),
  pending_payment: z.coerce.boolean().optional(),
  payment_cleared: z.coerce.boolean().optional(),
  /** ORDERED + PARTIALLY_DISPENSED (any payment state). Used by Pending KPI. */
  open_orders: z.coerce.boolean().optional(),
  today_only: z.coerce.boolean().optional(),
  partial_stock: z.coerce.boolean().optional(),
  urgent: z.coerce.boolean().optional(),
  priority: pharmacyOrderPrioritySchema.optional(),
  from: z.string().datetime().optional(),
  to: z.string().datetime().optional(),
  patient_id: uuidOrFriendlyIdentifierSchema.optional(),
  encounter_id: uuidOrFriendlyIdentifierSchema.optional(),
  search: z.string().trim().optional()});

const searchDrugsQuerySchema = listQuerySchema.extend({
  search: z.string().trim().optional(),
  name: z.string().trim().optional(),
  code: z.string().trim().optional(),
  form: z.string().trim().optional(),
  strength: z.string().trim().optional(),
  stock_status: z
    .enum(['IN_STOCK', 'ALMOST_OUT_OF_STOCK', 'LOW_STOCK', 'OUT_OF_STOCK'])
    .optional(),
  facility_id: uuidOrFriendlyIdentifierSchema.optional(),
  storage_room_id: uuidOrFriendlyIdentifierSchema.optional(),
  storage_shelf_id: uuidOrFriendlyIdentifierSchema.optional()});

const prepareDispenseLineSchema = z.object({
  order_item_id: uuidOrFriendlyIdentifierSchema,
  quantity: z.coerce.number().int().positive(),
  inventory_item_id: uuidOrFriendlyIdentifierSchema.optional(),
  notes: z.string().trim().max(255).optional().nullable()});

const prepareDispenseSchema = z.object({
  dispense_batch_ref: z.string().trim().min(3).max(64).optional(),
  facility_id: uuidOrFriendlyIdentifierSchema.optional().nullable(),
  statement: z.string().trim().max(65535).optional().nullable(),
  reason: z.string().trim().max(255).optional().nullable(),
  // Dispense UI finalizes stock in the same request. Set false to prepare only
  // and require a separate attest step (dual control).
  finalize: z.coerce.boolean().optional().default(true),
  items: z.array(prepareDispenseLineSchema).min(1).optional()});

const attestDispenseSchema = z.object({
  // Pharmacy dispensing. Must match the pharmacy the prescription was routed to.
  pharmacy_location_id: uuidOrFriendlyIdentifierSchema.optional().nullable(),
  dispense_batch_ref: z.string().trim().min(3).max(64),
  facility_id: uuidOrFriendlyIdentifierSchema.optional().nullable(),
  statement: z.string().trim().max(65535).optional().nullable(),
  reason: z.string().trim().max(255).optional().nullable(),
  attested_at: z.string().datetime().optional()});

const cancelPharmacyOrderSchema = z.object({
  reason: z.string().trim().min(2).max(2000),
  notes: z.string().trim().max(65535).optional().nullable()});

const cancelPharmacyOrderItemParamsSchema = z.object({
  id: uuidOrFriendlyIdentifierSchema,
  itemId: uuidOrFriendlyIdentifierSchema});

const cancelPharmacyOrderItemSchema = z.object({
  reason: z.string().trim().min(2).max(2000),
  notes: z.string().trim().max(65535).optional().nullable()});

const returnDispenseLineSchema = z.object({
  order_item_id: uuidOrFriendlyIdentifierSchema,
  quantity: z.coerce.number().int().positive(),
  inventory_item_id: uuidOrFriendlyIdentifierSchema.optional()});

const returnPharmacyOrderSchema = z.object({
  facility_id: uuidOrFriendlyIdentifierSchema.optional().nullable(),
  reason: z.string().trim().min(2).max(255).optional().nullable(),
  notes: z.string().trim().max(65535).optional().nullable(),
  items: z.array(returnDispenseLineSchema).min(1)});

const getInventoryStockQuerySchema = listQuerySchema.extend({
  facility_id: uuidOrFriendlyIdentifierSchema.optional(),
  // Balances belong to one pharmacy. Left out, the caller's own pharmacy is
  // used; reading another pharmacy's stock goes through
  // GET /pharmacy-locations/:id/availability, which returns quantities only.
  pharmacy_location_id: uuidOrFriendlyIdentifierSchema.optional(),
  inventory_item_id: uuidOrFriendlyIdentifierSchema.optional(),
  low_stock_only: z.coerce.boolean().optional(),
  stock_status: stockStatusSchema.optional(),
  expiring_within_days: z.coerce.number().int().min(1).max(365).optional(),
  expired_only: z.coerce.boolean().optional(),
  storage_room_id: uuidOrFriendlyIdentifierSchema.optional(),
  storage_shelf_id: uuidOrFriendlyIdentifierSchema.optional(),
  search: z.string().trim().optional()});

const adjustInventorySchema = z
  .object({
    inventory_item_id: uuidOrFriendlyIdentifierSchema,
    facility_id: uuidOrFriendlyIdentifierSchema.optional().nullable(),
    // Pharmacy whose balance is adjusted. Batch/expiry metadata additionally
    // requires this to be the procurement pharmacy.
    pharmacy_location_id: uuidOrFriendlyIdentifierSchema.optional().nullable(),
    quantity_delta: z.coerce.number().int().optional().default(0),
    reorder_level: z.coerce.number().int().min(0).optional(),
    reason: stockReasonSchema.optional(),
    notes: z.string().trim().max(255).optional().nullable(),
    occurred_at: z.string().datetime().optional(),
    batch_number: z.string().trim().min(1).max(80).optional(),
    manufactured_at: z.string().datetime().optional().nullable(),
    expiry_date: z.string().datetime().optional().nullable(),
    expiry_alert_lead_days: z.coerce.number().int().min(1).max(730).optional().nullable(),
    storage_room_id: uuidOrFriendlyIdentifierSchema.optional().nullable(),
    storage_shelf_id: uuidOrFriendlyIdentifierSchema.optional().nullable(),
    drug_id: uuidOrFriendlyIdentifierSchema.optional()})
  .superRefine((data, ctx) => {
    const quantityDelta = Number(data.quantity_delta || 0);
    const hasQuantityChange = quantityDelta !== 0;
    const hasReorderChange = data.reorder_level !== undefined;
    const hasBatchMeta =
      Boolean(data.batch_number) ||
      data.manufactured_at != null ||
      data.expiry_date != null ||
      data.expiry_alert_lead_days != null;
    const hasStorageChange =
      data.storage_room_id != null || data.storage_shelf_id != null;

    if (
      !hasQuantityChange &&
      !hasReorderChange &&
      !hasBatchMeta &&
      !hasStorageChange
    ) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'errors.validation.required',
        path: ['quantity_delta']});
    }
  });

const setupPharmacyDrugSchema = z
  .object({
    tenant_id: uuidOrFriendlyIdentifierSchema,
    name: z.string().trim().min(1).max(255),
    brand_name: z.string().trim().max(255).optional().nullable(),
    generic_name: z.string().trim().max(255).optional().nullable(),
    code: z.string().trim().max(80).optional().nullable(),
    form: z.string().trim().max(80).optional().nullable(),
    strength: z.string().trim().max(80).optional().nullable(),
    buy_unit_price: z.coerce.number().min(0).optional().nullable(),
    unit_price: z.coerce.number().min(0).optional().nullable(),
    transfer_unit_price: z.coerce.number().min(0).optional().nullable(),
    currency: z.string().trim().max(10).optional().nullable(),
    inventory_unit: z.string().trim().max(80).optional().nullable(),
    initial_stock: z.coerce.number().int().min(0).optional(),
    reorder_level: z.coerce.number().int().min(0).optional(),
    batch_number: z.string().trim().min(1).max(80).optional(),
    manufactured_at: z.string().datetime().optional().nullable(),
    expiry_date: z.string().datetime().optional().nullable(),
    expiry_alert_lead_days: z.coerce.number().int().min(1).max(730).optional().nullable(),
    storage_room_id: uuidOrFriendlyIdentifierSchema.optional().nullable(),
    storage_shelf_id: uuidOrFriendlyIdentifierSchema.optional().nullable(),
    default_storage_shelf_id: uuidOrFriendlyIdentifierSchema.optional().nullable(),
    facility_id: uuidOrFriendlyIdentifierSchema.optional().nullable(),
    confirm_similar: z.coerce.boolean().optional()});

const recordOrderBillingSchema = z.object({
  billing: clinicalRequestBillingSchema});

const resolveLegacyRouteParamsSchema = z.object({
  resource: z.enum([
    'pharmacy-orders',
    'pharmacy-order-items',
    'dispense-logs',
    'inventory-items',
    'inventory-stocks',
    'stock-movements',
    'drugs']),
  id: uuidOrFriendlyIdentifierSchema});

const getPharmacyStorageLayoutQuerySchema = z.object({
  facility_id: uuidOrFriendlyIdentifierSchema.optional(),
  include_inactive: z.coerce.boolean().optional(),
  include_deleted: z.coerce.boolean().optional()});

const createPharmacyStorageRoomSchema = z.object({
  tenant_id: uuidOrFriendlyIdentifierSchema.optional(),
  facility_id: uuidOrFriendlyIdentifierSchema.optional(),
  name: z.string().trim().min(1).max(255),
  code: z.string().trim().max(80).optional().nullable(),
  is_active: z.coerce.boolean().optional(),
  confirm_similar: z.coerce.boolean().optional()});

const updatePharmacyStorageRoomSchema = z.object({
  name: z.string().trim().min(1).max(255).optional(),
  code: z.string().trim().max(80).optional().nullable(),
  is_active: z.coerce.boolean().optional(),
  confirm_similar: z.coerce.boolean().optional()});

const checkPharmacyStorageRoomSimilaritySchema = z.object({
  tenant_id: uuidOrFriendlyIdentifierSchema.optional(),
  facility_id: uuidOrFriendlyIdentifierSchema.optional(),
  name: z.string().trim().min(1).max(255),
  code: z.string().trim().max(80).optional().nullable(),
  exclude_room_id: uuidOrFriendlyIdentifierSchema.optional().nullable()});

const pharmacyStorageRoomParamsSchema = z.object({
  roomId: uuidOrFriendlyIdentifierSchema});

const createPharmacyStorageShelfSchema = z.object({
  shelf_code: z.string().trim().max(80).optional().nullable(),
  label: z.string().trim().min(1).max(120),
  is_active: z.coerce.boolean().optional(),
  confirm_similar: z.coerce.boolean().optional()});

const updatePharmacyStorageShelfSchema = z.object({
  shelf_code: z.string().trim().max(80).optional().nullable(),
  label: z.string().trim().min(1).max(120).optional(),
  is_active: z.coerce.boolean().optional(),
  confirm_similar: z.coerce.boolean().optional()});

const checkPharmacyStorageShelfSimilaritySchema = z.object({
  room_id: uuidOrFriendlyIdentifierSchema.optional(),
  shelf_code: z.string().trim().max(80).optional().nullable(),
  label: z.string().trim().min(1).max(120),
  exclude_shelf_id: uuidOrFriendlyIdentifierSchema.optional().nullable()});

const checkPharmacyDrugSimilaritySchema = z.object({
  tenant_id: uuidOrFriendlyIdentifierSchema.optional(),
  name: z.string().trim().max(255).optional().nullable(),
  generic_name: z.string().trim().min(1).max(255),
  brand_name: z.string().trim().max(255).optional().nullable(),
  code: z.string().trim().max(80).optional().nullable(),
  form: z.string().trim().max(80).optional().nullable(),
  strength: z.string().trim().max(80).optional().nullable(),
  // Accept UUID or public id; repository resolves either. Keep looser than
  // uuidOrFriendly so atypical public ids still exclude the edited drug.
  exclude_drug_id: z.string().trim().min(1).max(64).optional().nullable()});

const pharmacyStorageShelfParamsSchema = z.object({
  shelfId: uuidOrFriendlyIdentifierSchema});

const pharmacyDrugParamsSchema = z.object({
  drugId: uuidOrFriendlyIdentifierSchema});

const upsertPharmacyDrugFacilityOfferingSchema = z
  .object({
    facility_id: uuidOrFriendlyIdentifierSchema.optional().nullable(),
    is_active: z.boolean().optional(),
    sort_order: z.coerce.number().int().min(0).max(9999).optional(),
    unit_price: z.coerce.number().min(0).optional(),
    currency: z.string().trim().max(10).optional().nullable(),
    default_storage_shelf_id: uuidOrFriendlyIdentifierSchema.optional().nullable()})
  .superRefine((data, ctx) => {
    if (
      data.is_active === true &&
      (data.unit_price == null || data.unit_price < 0)
    ) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'unit_price is required when the offering is active',
        path: ['unit_price']});
    }
  });

// Drug import bodies arrive as multipart form fields, so every value is a string.
const multipartOptionalBooleanSchema = z.preprocess((value) => {
  if (typeof value !== 'string') return value;
  const normalized = value.trim().toLowerCase();
  if (['true', '1', 'yes', 'on'].includes(normalized)) return true;
  if (['false', '0', 'no', 'off'].includes(normalized)) return false;
  return normalized === '' ? undefined : value;
}, z.boolean().optional());

const drugImportSourceSchema = z.preprocess(
  (value) => (typeof value === 'string' ? value.trim().toUpperCase() : value),
  z.enum([...DRUG_IMPORT_SOURCE_IDS])
);

const drugImportNullableTextSchema = (max) => z.string().trim().max(max).nullable();

const drugImportMoneySchema = z.number().nonnegative().max(9999999999.99).nullable();

// Reviewer edits: a present key is the final catalog value for that field.
const drugImportDecisionValuesSchema = z
  .object({
    name: z.string().trim().min(1).max(255),
    brand_name: drugImportNullableTextSchema(255),
    form: drugImportNullableTextSchema(80),
    strength: drugImportNullableTextSchema(80),
    supplier_name: drugImportNullableTextSchema(255),
    unit_price: drugImportMoneySchema,
    buy_unit_price: drugImportMoneySchema})
  .partial()
  .strict();

// Edited batches carry their full final values, matched by the preview batch key.
const drugImportBatchEditSchema = z
  .object({
    key: z.string().trim().min(1).max(80),
    batch_number: drugImportNullableTextSchema(80),
    expiry_date: z.string().trim().regex(/^\d{4}-\d{2}-\d{2}$/).nullable(),
    quantity: z.number().int().nonnegative().max(2147483647)})
  .strict();

const drugImportDecisionSchema = z.object({
  key: z.string().min(1).max(600),
  action: z.enum(['CREATE', 'MERGE', 'UPDATE', 'SKIP']),
  target_drug_id: uuidOrFriendlyIdentifierSchema.optional().nullable(),
  values: drugImportDecisionValuesSchema.optional(),
  batches: z.array(drugImportBatchEditSchema).optional()});

const drugImportDecisionsSchema = z.preprocess((value) => {
  if (value == null || value === '') return [];
  if (typeof value !== 'string') return value;
  try {
    return JSON.parse(value);
  } catch (_error) {
    return value;
  }
}, z.array(drugImportDecisionSchema));

const previewDrugImportSchema = z.object({
  source: drugImportSourceSchema});

const commitDrugImportSchema = z.object({
  source: drugImportSourceSchema,
  plan_hash: z.string().trim().regex(/^[a-f0-9]{64}$/),
  decisions: drugImportDecisionsSchema,
  stock_mode: z.enum(['REPLACE', 'ADD']).optional(),
  clear_missing_stock: multipartOptionalBooleanSchema,
  confirm_review: multipartOptionalBooleanSchema,
  currency: z.string().trim().max(10).optional().nullable()});

module.exports = {
  pharmacyOrderStatusSchema,
  stockStatusSchema,
  orderLocationSchema,
  orderWorkflowParamsSchema,
  getPharmacyWorkbenchQuerySchema,
  searchDrugsQuerySchema,
  createPharmacyOrderSchema,
  prepareDispenseSchema,
  attestDispenseSchema,
  cancelPharmacyOrderSchema,
  cancelPharmacyOrderItemParamsSchema,
  cancelPharmacyOrderItemSchema,
  returnPharmacyOrderSchema,
  getInventoryStockQuerySchema,
  adjustInventorySchema,
  setupPharmacyDrugSchema,
  recordOrderBillingSchema,
  resolveLegacyRouteParamsSchema,
  getPharmacyStorageLayoutQuerySchema,
  createPharmacyStorageRoomSchema,
  updatePharmacyStorageRoomSchema,
  checkPharmacyStorageRoomSimilaritySchema,
  pharmacyStorageRoomParamsSchema,
  createPharmacyStorageShelfSchema,
  updatePharmacyStorageShelfSchema,
  checkPharmacyStorageShelfSimilaritySchema,
  checkPharmacyDrugSimilaritySchema,
  pharmacyStorageShelfParamsSchema,
  pharmacyDrugParamsSchema,
  upsertPharmacyDrugFacilityOfferingSchema,
  previewDrugImportSchema,
  commitDrugImportSchema};
