/**
 * Procedure module validation schemas
 *
 * @module modules/procedure/schemas
 * @description Zod validation schemas for procedure endpoints.
 * Per validation.mdc: Use Zod exclusively for all validation
 * Per module-creation.mdc: Define schemas for body, params, and query
 */

const { z } = require('zod');
const { 
  uuidSchema, 
  uuidOrFriendlyIdentifierSchema,
  listQuerySchema,
  isoDateSchema
} = require('@lib/validation/zod');
const {
  clinicalRequestBillingSchema} = require('@lib/billing/clinical-request-billing.schema');

// ==================== Body Schemas ====================

/**
 * Create procedure body validation
 * Used for POST /procedures endpoint
 */
const createProcedureSchema = z.object({
  // Accepts a UUID or a human-friendly encounter id (ENC…), matching the lab
  // and radiology request endpoints, so a procedure can be requested from any
  // surface that holds either identifier.
  encounter_id: uuidOrFriendlyIdentifierSchema,
  code: z.string().trim().max(80).optional().nullable(),
  description: z.string().trim().min(1).max(65535),
  performed_at: isoDateSchema.optional().nullable(),
  billing: clinicalRequestBillingSchema.optional().nullable()
});

/**
 * Update procedure body validation
 * Used for PUT /procedures/:id endpoint
 * All fields optional for partial updates
 */
const updateProcedureSchema = z.object({
  code: z.string().trim().max(80).optional().nullable(),
  description: z.string().trim().min(1).max(65535).optional(),
  performed_at: isoDateSchema.optional().nullable()
});

// ==================== URL Params ====================

/**
 * Procedure ID URL parameter validation
 * Used for GET /:id, PUT /:id, and DELETE /:id endpoints
 */
const procedureIdParamsSchema = z.object({
  id: uuidSchema
});

// ==================== Query Params ====================

/**
 * List procedures query parameter validation
 * Used for GET / endpoint
 * Extends base listQuerySchema with procedure-specific filters
 */
const listProceduresQuerySchema = listQuerySchema.extend({
  encounter_id: uuidOrFriendlyIdentifierSchema.optional(),
  code: z.string().trim().optional()
});

module.exports = {
  createProcedureSchema,
  updateProcedureSchema,
  procedureIdParamsSchema,
  listProceduresQuerySchema
};
