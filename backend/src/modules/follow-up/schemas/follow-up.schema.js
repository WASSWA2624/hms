/**
 * Follow-up module validation schemas
 *
 * @module modules/follow-up/schemas
 * @description Zod validation schemas for follow-up endpoints.
 * Per validation.mdc: Use Zod exclusively for all validation
 * Per module-creation.mdc: Define schemas for body, params, and query
 */

const { z } = require('zod');
const { 
  uuidOrFriendlyIdentifierSchema,
  listQuerySchema,
  isoDateSchema
} = require('@lib/validation/zod');

const FOLLOW_UP_STATUS_VALUES = ['SCHEDULED', 'COMPLETED', 'CANCELLED'];

// ==================== Body Schemas ====================

/**
 * Create follow-up body validation
 * Used for POST /follow-ups endpoint
 */
const createFollowUpSchema = z.object({
  encounter_id: uuidOrFriendlyIdentifierSchema,
  scheduled_at: isoDateSchema,
  status: z.enum(FOLLOW_UP_STATUS_VALUES).optional().default('SCHEDULED'),
  notes: z.string().max(10000).optional().nullable()
});

/**
 * Update follow-up body validation
 * Used for PUT /follow-ups/:id endpoint
 * All fields optional for partial updates
 */
const updateFollowUpSchema = z.object({
  scheduled_at: isoDateSchema.optional(),
  status: z.enum(FOLLOW_UP_STATUS_VALUES).optional(),
  notes: z.string().max(10000).optional().nullable()
});

const transitionFollowUpSchema = z.object({
  notes: z.string().trim().max(10000).optional().nullable(),
});

// ==================== URL Params ====================

/**
 * Follow-up ID URL parameter validation
 * Used for GET /:id, PUT /:id, and DELETE /:id endpoints
 */
const followUpIdParamsSchema = z.object({
  id: uuidOrFriendlyIdentifierSchema
});

// ==================== Query Params ====================

/**
 * List follow-ups query parameter validation
 * Used for GET / endpoint
 * Extends base listQuerySchema with follow-up-specific filters
 */
const listFollowUpsQuerySchema = listQuerySchema.extend({
  encounter_id: uuidOrFriendlyIdentifierSchema.optional(),
  encounter_type: z
    .enum(['OPD', 'IPD', 'ICU', 'THEATRE', 'EMERGENCY', 'TELEMEDICINE', 'LAB'])
    .optional(),
  status: z.enum(FOLLOW_UP_STATUS_VALUES).optional(),
  scheduled_before: isoDateSchema.optional(),
  scheduled_after: isoDateSchema.optional(),
  tenant_id: uuidOrFriendlyIdentifierSchema.optional(),
  facility_id: uuidOrFriendlyIdentifierSchema.optional(),
});

module.exports = {
  createFollowUpSchema,
  updateFollowUpSchema,
  transitionFollowUpSchema,
  followUpIdParamsSchema,
  listFollowUpsQuerySchema,
  FOLLOW_UP_STATUS_VALUES
};
