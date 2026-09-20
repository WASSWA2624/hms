/**
 * Pharmacy stock order validation schemas
 *
 * @module modules/pharmacy-stock-order/schemas
 * @description Zod schemas for the Hospital Pharmacy -> Main Pharmacy stock
 * ordering workflow.
 * Per validation.mdc: Use Zod exclusively for all validation.
 */

const { z } = require('zod');
const { uuidOrFriendlyIdentifierSchema, listQuerySchema } = require('@lib/validation/zod');

const STOCK_ORDER_STATUSES = [
  'DRAFT',
  'SUBMITTED',
  'UNDER_REVIEW',
  'APPROVED',
  'PARTIALLY_APPROVED',
  'REJECTED',
  'ISSUED',
  'PARTIALLY_RECEIVED',
  'RECEIVED',
  'CANCELLED',
];

const quantity = z.coerce.number().int().min(0).max(1_000_000);
const notes = z.string().trim().max(2000).optional().nullable();

const stockOrderIdParamsSchema = z.object({
  id: uuidOrFriendlyIdentifierSchema,
});

const listStockOrdersQuerySchema = listQuerySchema.extend({
  status: z.enum(STOCK_ORDER_STATUSES).optional(),
  requesting_location_id: uuidOrFriendlyIdentifierSchema.optional(),
  supplying_location_id: uuidOrFriendlyIdentifierSchema.optional(),
  /** Orders this pharmacy must act on: incoming requests plus its own. */
  location_id: uuidOrFriendlyIdentifierSchema.optional(),
  /** INBOX = requests to supply, OUTBOX = requests raised. */
  queue: z.enum(['INBOX', 'OUTBOX', 'ALL']).optional(),
  search: z.string().trim().max(255).optional(),
});

const createStockOrderSchema = z.object({
  requesting_location_id: uuidOrFriendlyIdentifierSchema,
  /** Defaults to the requesting pharmacy's configured supplier. */
  supplying_location_id: uuidOrFriendlyIdentifierSchema.optional().nullable(),
  notes,
  /** Submit straight away instead of leaving the order in DRAFT. */
  submit: z.boolean().optional(),
  items: z
    .array(
      z.object({
        drug_id: uuidOrFriendlyIdentifierSchema,
        inventory_item_id: uuidOrFriendlyIdentifierSchema.optional().nullable(),
        requested_quantity: quantity,
        notes,
      })
    )
    .min(1),
});

const updateStockOrderSchema = z.object({
  notes,
  items: z
    .array(
      z.object({
        drug_id: uuidOrFriendlyIdentifierSchema,
        inventory_item_id: uuidOrFriendlyIdentifierSchema.optional().nullable(),
        requested_quantity: quantity,
        notes,
      })
    )
    .min(1)
    .optional(),
});

/**
 * Review decision by the supplying pharmacy.
 *
 * Per-item `approved_quantity` drives partial approval: omit an item to approve
 * it in full, set it to 0 to reject that line.
 */
const reviewStockOrderSchema = z.object({
  decision: z.enum(['APPROVE', 'REJECT']),
  review_notes: notes,
  items: z
    .array(
      z.object({
        id: uuidOrFriendlyIdentifierSchema.optional(),
        drug_id: uuidOrFriendlyIdentifierSchema.optional(),
        approved_quantity: quantity,
        notes,
      })
    )
    .optional(),
});

/** Issue moves stock out of the supplying pharmacy. */
const issueStockOrderSchema = z.object({
  issued_at: z.coerce.date().optional(),
  notes,
  items: z
    .array(
      z.object({
        id: uuidOrFriendlyIdentifierSchema.optional(),
        drug_id: uuidOrFriendlyIdentifierSchema.optional(),
        issued_quantity: quantity,
      })
    )
    .optional(),
});

/** Receipt moves stock into the requesting pharmacy. */
const receiveStockOrderSchema = z.object({
  received_at: z.coerce.date().optional(),
  notes,
  items: z
    .array(
      z.object({
        id: uuidOrFriendlyIdentifierSchema.optional(),
        drug_id: uuidOrFriendlyIdentifierSchema.optional(),
        received_quantity: quantity,
      })
    )
    .optional(),
});

const cancelStockOrderSchema = z.object({
  reason: notes,
});

module.exports = {
  STOCK_ORDER_STATUSES,
  stockOrderIdParamsSchema,
  listStockOrdersQuerySchema,
  createStockOrderSchema,
  updateStockOrderSchema,
  reviewStockOrderSchema,
  issueStockOrderSchema,
  receiveStockOrderSchema,
  cancelStockOrderSchema,
};
