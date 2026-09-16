/**
 * Patient module validation schemas
 *
 * @module modules/patient/schemas
 * @description Zod validation schemas for patient endpoints.
 * Per validation.mdc: Use Zod exclusively for all validation
 * Per module-creation.mdc: Define schemas for body, params, and query
 */

const { z } = require('zod');
const {
  uuidSchema,
  uuidOrFriendlyIdentifierSchema,
  friendlyIdentifierSchema,
  listQuerySchema} = require('@lib/validation/zod');

const DATE_ONLY_REGEX = /^\d{4}-\d{2}-\d{2}$/;
const GENDER_VALUES = ['MALE', 'FEMALE', 'OTHER', 'UNKNOWN'];
const CONSENT_STATUS_VALUES = ['GRANTED', 'REVOKED', 'PENDING'];
const APPOINTMENT_STATUS_VALUES = [
  'SCHEDULED',
  'CONFIRMED',
  'IN_PROGRESS',
  'COMPLETED',
  'CANCELLED',
  'NO_SHOW'
];

const normalizeOptionalTextQuery = (maxLength = 120) =>
  z
    .string()
    .trim()
    .max(maxLength)
    .optional()
    .transform((value) => (value ? value : undefined));

const isValidDateQueryInput = (value) => {
  const normalized = String(value || '').trim();
  if (!normalized) return false;
  if (DATE_ONLY_REGEX.test(normalized)) return true;
  return !Number.isNaN(Date.parse(normalized));
};

const dateQuerySchema = z
  .string()
  .trim()
  .max(40)
  .refine(isValidDateQueryInput, 'Invalid date filter value')
  .optional()
  .transform((value) => (value ? value : undefined));

const searchQuerySchema = z
  .string()
  .trim()
  .max(120)
  .transform((value) => value.replace(/\s+/g, ' ').trim())
  .optional()
  .transform((value) => (value ? value : undefined));

const patientFriendlyIdSchema = friendlyIdentifierSchema;
const patientRouteIdSchema = uuidOrFriendlyIdentifierSchema;
const optionalFriendlyOrUuidSchema = uuidOrFriendlyIdentifierSchema.optional().nullable();
const optionalBooleanQuerySchema = z
  .union([z.boolean(), z.string().trim().toLowerCase()])
  .optional()
  .transform((value) => {
    if (value === undefined) return undefined;
    if (typeof value === 'boolean') return value;
    if (value === 'true') return true;
    if (value === 'false') return false;
    return undefined;
  });
const dateLikeBodySchema = z
  .string()
  .trim()
  .max(40)
  .refine(isValidDateQueryInput, 'Invalid date value')
  .optional()
  .nullable()
  .transform((value) => (value ? value : null));
const requiredNameBodySchema = z.string().trim().min(1).max(120);
const optionalNameBodySchema = z
  .string()
  .trim()
  .max(120)
  .optional()
  .nullable()
  .transform((value) => {
    if (value === undefined) return undefined;
    return value ? value : null;
  });

const jsonValueSchema = z.lazy(() =>
  z.union([
    z.string(),
    z.number(),
    z.boolean(),
    z.null(),
    z.array(jsonValueSchema),
    z.record(z.string(), jsonValueSchema)])
);
const optionalJsonObjectSchema = z
  .record(z.string(), jsonValueSchema)
  .optional()
  .nullable();

// ==================== Body Schemas ====================

/**
 * Create patient body validation
 * Used for POST /patients endpoint
 */
const createPatientSchema = z.object({
  tenant_id: optionalFriendlyOrUuidSchema,
  facility_id: optionalFriendlyOrUuidSchema,
  first_name: requiredNameBodySchema,
  last_name: optionalNameBodySchema,
  date_of_birth: dateLikeBodySchema,
  gender: z.enum(GENDER_VALUES).optional().nullable(),
  is_active: z.boolean().optional(),
  extension_json: optionalJsonObjectSchema,
  primary_phone: z.string().trim().min(1).max(40).optional().nullable(),
  primary_email: z.string().trim().email().max(255).optional().nullable(),
  primary_identifier_type: z.string().trim().max(80).optional().nullable(),
  primary_identifier_value: z.string().trim().max(120).optional().nullable()});

/**
 * Update patient body validation
 * Used for PUT /patients/:id endpoint
 * All fields optional for partial updates
 */
const updatePatientSchema = z.object({
  facility_id: optionalFriendlyOrUuidSchema,
  first_name: requiredNameBodySchema.optional(),
  last_name: optionalNameBodySchema,
  date_of_birth: dateLikeBodySchema,
  gender: z.enum(GENDER_VALUES).optional().nullable(),
  is_active: z.boolean().optional(),
  extension_json: optionalJsonObjectSchema,
  primary_phone: z.string().trim().min(1).max(40).optional().nullable(),
  primary_email: z.string().trim().email().max(255).optional().nullable(),
  primary_identifier_type: z.string().trim().max(80).optional().nullable(),
  primary_identifier_value: z.string().trim().max(120).optional().nullable()});

// ==================== URL Params ====================

/**
 * Patient ID URL parameter validation
 * Used for GET /:id, PUT /:id, and DELETE /:id endpoints
 */
const patientIdParamsSchema = z.object({
  id: patientRouteIdSchema
});

const patientWorkspaceParamsSchema = z.object({
  patientId: patientRouteIdSchema});

const patientDuplicateDismissParamsSchema = z.object({
  reviewId: z.string().trim().min(1).max(255)});

// ==================== Query Params ====================

/**
 * List patients query parameter validation
 * Used for GET / endpoint
 * Extends base listQuerySchema with patient-specific filters
 */
const listPatientsQuerySchema = listQuerySchema.extend({
  tenant_id: uuidOrFriendlyIdentifierSchema.optional(),
  facility_id: uuidOrFriendlyIdentifierSchema.optional(),
  patient_id: normalizeOptionalTextQuery(64),
  first_name: normalizeOptionalTextQuery(120),
  last_name: normalizeOptionalTextQuery(120),
  date_of_birth: dateQuerySchema,
  date_of_birth_from: dateQuerySchema,
  date_of_birth_to: dateQuerySchema,
  gender: z.enum(['MALE', 'FEMALE', 'OTHER', 'UNKNOWN']).optional(),
  contact: normalizeOptionalTextQuery(255),
  appointment_status: z.enum(APPOINTMENT_STATUS_VALUES).optional(),
  visit_date: dateQuerySchema,
  visit_from: dateQuerySchema,
  visit_to: dateQuerySchema,
  created_at: dateQuerySchema,
  created_from: dateQuerySchema,
  created_to: dateQuerySchema,
  appointment_from: dateQuerySchema,
  appointment_to: dateQuerySchema,
  is_active: optionalBooleanQuerySchema,
  search: searchQuerySchema,
  has_active_admission: optionalBooleanQuerySchema,
  has_outstanding_balance: optionalBooleanQuerySchema,
  consent_state: z.enum(CONSENT_STATUS_VALUES).optional(),
  include_deleted: z.enum(['true', 'false']).optional(),
  record_state: z.enum(['current', 'deleted', 'all']).optional()});

const permanentDeletePatientSchema = z.object({
  confirm: z.literal(true)
});

const patientWorkspaceOverviewQuerySchema = listQuerySchema.extend({
  tenant_id: uuidOrFriendlyIdentifierSchema.optional(),
  facility_id: uuidOrFriendlyIdentifierSchema.optional()});

const patientWorkspaceReferenceDataQuerySchema = z.object({
  tenant_id: uuidOrFriendlyIdentifierSchema.optional(),
  facility_id: uuidOrFriendlyIdentifierSchema.optional()});

const patientWorkspaceListQuerySchema = listQuerySchema.extend({
  tenant_id: uuidOrFriendlyIdentifierSchema.optional(),
  facility_id: uuidOrFriendlyIdentifierSchema.optional()});

const patientDuplicateListQuerySchema = listQuerySchema.extend({
  tenant_id: uuidOrFriendlyIdentifierSchema.optional(),
  facility_id: uuidOrFriendlyIdentifierSchema.optional(),
  patient_id: uuidOrFriendlyIdentifierSchema.optional(),
  first_name: normalizeOptionalTextQuery(120),
  last_name: normalizeOptionalTextQuery(120),
  date_of_birth: dateQuerySchema,
  gender: z.enum(GENDER_VALUES).optional(),
  phone: normalizeOptionalTextQuery(40),
  email: normalizeOptionalTextQuery(255),
  contact: normalizeOptionalTextQuery(255),
  identifier_type: normalizeOptionalTextQuery(60),
  identifier_value: normalizeOptionalTextQuery(120)});

const patientMergePreviewSchema = z.object({
  primary_patient_id: uuidOrFriendlyIdentifierSchema,
  secondary_patient_id: uuidOrFriendlyIdentifierSchema});

const patientMergeSchema = patientMergePreviewSchema.extend({
  summary: z.object({
    first_name: z.string().trim().min(1).max(120).optional(),
    last_name: z.string().trim().min(1).max(120).optional(),
    date_of_birth: dateLikeBodySchema.optional(),
    gender: z.enum(GENDER_VALUES).optional().nullable(),
    facility_id: optionalFriendlyOrUuidSchema}).optional()});

const patientDuplicateDismissSchema = z.object({
  primary_patient_id: uuidOrFriendlyIdentifierSchema,
  secondary_patient_id: uuidOrFriendlyIdentifierSchema,
  dismissed_reason: z.string().trim().max(255).optional().nullable()});

module.exports = {
  createPatientSchema,
  updatePatientSchema,
  patientIdParamsSchema,
  listPatientsQuerySchema,
  patientFriendlyIdSchema,
  patientWorkspaceParamsSchema,
  patientDuplicateDismissParamsSchema,
  patientWorkspaceOverviewQuerySchema,
  patientWorkspaceReferenceDataQuerySchema,
  patientWorkspaceListQuerySchema,
  patientDuplicateListQuerySchema,
  patientMergePreviewSchema,
  patientMergeSchema,
  patientDuplicateDismissSchema,
  permanentDeletePatientSchema};

