/**
 * Pharmacy order module validation schemas
 *
 * @module modules/pharmacy-order/schemas
 * @description Zod validation schemas for pharmacy order endpoints.
 * Per validation.mdc: Use Zod exclusively for all validation
 * Per module-creation.mdc: Define schemas for body, params, and query
 */

const { z } = require('zod');
const {
  uuidOrFriendlyIdentifierSchema,
  listQuerySchema
} = require('@lib/validation/zod');
const { clinicalRequestBillingSchema } = require('@lib/billing/clinical-request-billing.schema');

// ==================== Body Schemas ====================

const PHARMACY_ORDER_STATUS_VALUES = [
  'ORDERED',
  'DISPENSED',
  'PARTIALLY_DISPENSED',
  'CANCELLED'];

const MEDICATION_ROUTE_VALUES = [
  'ORAL',
  'IV',
  'IM',
  'SC',
  'SUBLINGUAL',
  'RECTAL',
  'VAGINAL',
  'TOPICAL',
  'INHALATION',
  'OPHTHALMIC',
  'OTIC',
  'NASAL',
  'INTRADERMAL',
  'OTHER'];

const MEDICATION_FREQUENCY_VALUES = [
  'ONCE',
  'OD',
  'BID',
  'TID',
  'QID',
  'Q4H',
  'Q6H',
  'Q8H',
  'Q12H',
  'QHS',
  'WEEKLY',
  'PRN',
  'STAT',
  'CUSTOM'];

const quantityUnitSchema = z
  .string()
  .trim()
  .min(1)
  .max(40)
  .optional()
  .nullable();

const doseUnitSchema = z
  .string()
  .trim()
  .min(1)
  .max(40)
  .optional()
  .nullable();

const durationUnitSchema = z
  .string()
  .trim()
  .min(1)
  .max(40)
  .optional()
  .nullable();

const pharmacyOrderItemSchema = z
  .object({
    drug_id: uuidOrFriendlyIdentifierSchema,
    quantity: z.coerce.number().int().positive().optional().nullable(),
    quantity_unit: quantityUnitSchema,
    dosage: z.string().trim().max(80).optional().nullable(),
    dose_amount: z.coerce.number().positive().optional().nullable(),
    dose_unit: doseUnitSchema,
    duration_value: z.coerce.number().int().positive().optional().nullable(),
    duration_unit: durationUnitSchema,
    instructions: z.string().trim().max(5000).optional().nullable(),
    custom_prescription: z.string().trim().max(5000).optional().nullable(),
    frequency: z.enum(MEDICATION_FREQUENCY_VALUES).optional().nullable(),
    route: z.enum(MEDICATION_ROUTE_VALUES).optional().nullable()})
  .superRefine((value, ctx) => {
    const hasStructuredDose =
      value.dose_amount !== undefined && value.dose_amount !== null;
    const hasLegacyDose = Boolean(String(value.dosage || '').trim());
    const hasCustomPrescription = Boolean(
      String(value.custom_prescription || '').trim()
    );

    if (!hasStructuredDose && !hasLegacyDose && !hasCustomPrescription) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['dose_amount'],
        message: 'errors.validation.required'});
    }

    if (
      value.duration_value !== undefined &&
      value.duration_value !== null &&
      !String(value.duration_unit || '').trim()
    ) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['duration_unit'],
        message: 'errors.validation.required'});
    }

  });

/**
 * Create pharmacy order body validation
 * Used for POST /pharmacy-orders endpoint
 *
 * Clinician-created orders intentionally do not accept order/prescription
 * status. The service always creates the order as ORDERED and lines as ACTIVE.
 */
const createPharmacyOrderSchema = z.object({
  encounter_id: uuidOrFriendlyIdentifierSchema.optional().nullable(),
  patient_id: uuidOrFriendlyIdentifierSchema.optional().nullable(),
  ordered_at: z.string().datetime().optional(),
  // Routing. Left out, origin follows the encounter (hospital consultation ->
  // HOSPITAL, counter sale -> WALK_IN) and the pharmacy is the one configured
  // for that origin in the facility.
  origin: z.enum(['HOSPITAL', 'WALK_IN']).optional(),
  pharmacy_location_id: uuidOrFriendlyIdentifierSchema.optional().nullable(),
  items: z.array(pharmacyOrderItemSchema).min(1),
  billing: clinicalRequestBillingSchema.optional().nullable()});

/**
 * Update pharmacy order body validation
 * Used for PUT /pharmacy-orders/:id endpoint
 * All fields optional for partial updates.
 *
 * Status remains here for pharmacy-side workflows only; the clinical create
 * screen does not expose it.
 */
const updatePharmacyOrderSchema = z.object({
  encounter_id: uuidOrFriendlyIdentifierSchema.optional().nullable(),
  patient_id: uuidOrFriendlyIdentifierSchema.optional().nullable(),
  status: z.enum(PHARMACY_ORDER_STATUS_VALUES).optional(),
  ordered_at: z.string().datetime().optional(),
  billing: clinicalRequestBillingSchema.optional().nullable()});

/**
 * Dispense pharmacy order body validation
 * Used for POST /pharmacy-orders/:id/dispense endpoint
 */
const dispensePharmacyOrderSchema = z.object({
  status: z.enum(['DISPENSED', 'PARTIALLY_DISPENSED']).optional(),
  notes: z.string().trim().max(10000).optional().nullable()
});

// ==================== URL Params ====================

/**
 * Pharmacy order ID URL parameter validation
 * Used for GET /:id, PUT /:id, and DELETE /:id endpoints
 */
const pharmacyOrderIdParamsSchema = z.object({
  id: uuidOrFriendlyIdentifierSchema
});

// ==================== Query Params ====================

/**
 * List pharmacy orders query parameter validation
 * Used for GET / endpoint
 * Extends base listQuerySchema with pharmacy order-specific filters
 */
const listPharmacyOrdersQuerySchema = listQuerySchema.extend({
  encounter_id: uuidOrFriendlyIdentifierSchema.optional(),
  patient_id: uuidOrFriendlyIdentifierSchema.optional(),
  status: z.enum(PHARMACY_ORDER_STATUS_VALUES).optional(),
  ordered_at_from: z.string().datetime().optional(),
  ordered_at_to: z.string().datetime().optional()
});

module.exports = {
  createPharmacyOrderSchema,
  updatePharmacyOrderSchema,
  dispensePharmacyOrderSchema,
  pharmacyOrderIdParamsSchema,
  listPharmacyOrdersQuerySchema
};
