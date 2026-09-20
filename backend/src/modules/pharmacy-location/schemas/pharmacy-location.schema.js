/**
 * Pharmacy location validation schemas
 *
 * @module modules/pharmacy-location/schemas
 * @description Zod schemas for pharmacy location, access grant and price
 * endpoints.
 * Per validation.mdc: Use Zod exclusively for all validation.
 */

const { z } = require('zod');
const {
  uuidOrFriendlyIdentifierSchema,
  listQuerySchema,
} = require('@lib/validation/zod');

const LOCATION_KINDS = ['MAIN', 'HOSPITAL', 'BRANCH', 'THEATRE', 'WARD', 'OTHER'];
const ACCESS_LEVELS = ['VIEW', 'DISPENSE', 'MANAGE'];

const optionalText = (max) => z.string().trim().max(max).optional().nullable();
const money = z
  .union([z.number(), z.string().trim().regex(/^\d+(\.\d{1,2})?$/)])
  .optional()
  .nullable();

const pharmacyLocationIdParamsSchema = z.object({
  id: uuidOrFriendlyIdentifierSchema,
});

const listPharmacyLocationsQuerySchema = listQuerySchema.extend({
  facility_id: uuidOrFriendlyIdentifierSchema.optional(),
  kind: z.enum(LOCATION_KINDS).optional(),
  is_active: z.coerce.boolean().optional(),
  handles_procurement: z.coerce.boolean().optional(),
  handles_walk_in: z.coerce.boolean().optional(),
  handles_prescriptions: z.coerce.boolean().optional(),
  /** Only the locations the calling user holds a grant on. */
  mine_only: z.coerce.boolean().optional(),
  search: z.string().trim().max(255).optional(),
});

const createPharmacyLocationSchema = z.object({
  facility_id: uuidOrFriendlyIdentifierSchema,
  name: z.string().trim().min(1).max(255),
  code: optionalText(80),
  kind: z.enum(LOCATION_KINDS).default('OTHER'),
  is_active: z.boolean().optional(),
  is_default: z.boolean().optional(),
  handles_procurement: z.boolean().optional(),
  handles_walk_in: z.boolean().optional(),
  handles_prescriptions: z.boolean().optional(),
  supplied_by_location_id: uuidOrFriendlyIdentifierSchema.optional().nullable(),
  currency: optionalText(10),
});

const updatePharmacyLocationSchema = createPharmacyLocationSchema
  .partial()
  .omit({ facility_id: true });

/** Grants a user access to one pharmacy location. */
const upsertPharmacyLocationAccessSchema = z.object({
  user_id: uuidOrFriendlyIdentifierSchema,
  access_level: z.enum(ACCESS_LEVELS).default('DISPENSE'),
  can_view_supplier_stock: z.boolean().optional(),
  is_active: z.boolean().optional(),
});

const revokePharmacyLocationAccessParamsSchema = z.object({
  id: uuidOrFriendlyIdentifierSchema,
  userId: uuidOrFriendlyIdentifierSchema,
});

/**
 * Sets this location's own prices.
 *
 * `sell_price` and `supply_price` are written independently: sending one never
 * changes the other, so a walk-in price edit cannot move a hospital supply
 * price (requirement 9).
 */
const upsertPharmacyLocationPriceSchema = z.object({
  drug_id: uuidOrFriendlyIdentifierSchema,
  sell_price: money,
  supply_price: money,
  acquisition_cost: money,
  currency: optionalText(10),
  is_active: z.boolean().optional(),
});

const listPharmacyLocationPricesQuerySchema = listQuerySchema.extend({
  drug_id: uuidOrFriendlyIdentifierSchema.optional(),
  search: z.string().trim().max(255).optional(),
  is_active: z.coerce.boolean().optional(),
});

/** Cross-pharmacy availability: this pharmacy next to the one that supplies it. */
const getPharmacyLocationAvailabilityQuerySchema = listQuerySchema.extend({
  /** Compare against this pharmacy instead of the configured supplier. */
  compare_location_id: uuidOrFriendlyIdentifierSchema.optional(),
  search: z.string().trim().max(255).optional(),
  /** Only rows at or below the requester's reorder level. */
  below_reorder_level: z.coerce.boolean().optional(),
});

module.exports = {
  LOCATION_KINDS,
  ACCESS_LEVELS,
  pharmacyLocationIdParamsSchema,
  listPharmacyLocationsQuerySchema,
  createPharmacyLocationSchema,
  updatePharmacyLocationSchema,
  upsertPharmacyLocationAccessSchema,
  revokePharmacyLocationAccessParamsSchema,
  upsertPharmacyLocationPriceSchema,
  listPharmacyLocationPricesQuerySchema,
  getPharmacyLocationAvailabilityQuerySchema,
};
