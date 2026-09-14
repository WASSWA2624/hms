/**
 * User module validation schemas
 *
 * @module modules/user/schemas
 * @description Zod validation schemas for user endpoints.
 * Per validation.mdc: Use Zod exclusively for all validation
 * Per module-creation.mdc: Define schemas for body, params, and query
 */

const { z } = require('zod');
const {
  uuidOrFriendlyIdentifierSchema,
  listQuerySchema
} = require('@lib/validation/zod');
const { applyPasswordPolicy } = require('@lib/validation/password-policy');

const optionalBooleanSchema = z.preprocess((value) => {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    if (normalized === 'true') return true;
    if (normalized === 'false') return false;
  }
  return value;
}, z.boolean().optional());

const userStatusSchema = z.enum(['ACTIVE', 'INACTIVE', 'SUSPENDED', 'PENDING']);
const permissionIdsSchema = z
  .array(uuidOrFriendlyIdentifierSchema)
  .max(100)
  .optional();

/**
 * Field limits shared with the database columns and the Flutter access-admin
 * form (`frontend/lib/features/access_admin/domain/entities/user_account_rules.dart`).
 * Change all three together so the client never accepts what the API rejects.
 */
const USER_FIELD_LIMITS = Object.freeze({
  name: 120,
  positionTitle: 120,
  email: 255,
  phone: 40,
  phoneMinDigits: 7,
  phoneMaxDigits: 15,
  roleIds: 50,
});

/** Account email pattern, mirrored verbatim by the Flutter form. */
const USER_EMAIL_PATTERN =
  /^[A-Za-z0-9._%+'-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)*\.[A-Za-z]{2,}$/;

const USER_PHONE_CHARACTERS = /^\+?[\d\s\-().]+$/;

const isBlankOrValidPhone = (value) => {
  const trimmed = String(value ?? '').trim();
  if (!trimmed) {
    return true;
  }
  if (!USER_PHONE_CHARACTERS.test(trimmed)) {
    return false;
  }
  const digits = trimmed.replace(/\D/g, '');
  return (
    digits.length >= USER_FIELD_LIMITS.phoneMinDigits &&
    digits.length <= USER_FIELD_LIMITS.phoneMaxDigits
  );
};

const nameSchema = z
  .string()
  .trim()
  .min(1, 'errors.validation.required')
  .max(USER_FIELD_LIMITS.name, 'errors.validation.max_length');

const optionalNameSchema = z
  .string()
  .trim()
  .max(USER_FIELD_LIMITS.name, 'errors.validation.max_length')
  .optional()
  .nullable();

const positionTitleSchema = z
  .string()
  .trim()
  .min(1, 'errors.validation.required')
  .max(USER_FIELD_LIMITS.positionTitle, 'errors.validation.max_length');

const emailSchema = z
  .string()
  .trim()
  .min(1, 'errors.validation.email.required')
  .max(USER_FIELD_LIMITS.email, 'errors.validation.max_length')
  .regex(USER_EMAIL_PATTERN, 'errors.validation.email.format');

const phoneSchema = z
  .string()
  .trim()
  .max(USER_FIELD_LIMITS.phone, 'errors.validation.max_length')
  .refine(isBlankOrValidPhone, { message: 'errors.user.phone_invalid' })
  .optional()
  .nullable();

const roleIdsSchema = z
  .array(uuidOrFriendlyIdentifierSchema)
  .max(USER_FIELD_LIMITS.roleIds, 'errors.validation.max_items')
  .optional();

const staffProfileSchema = z
  .object({
    position: z
      .string()
      .trim()
      .max(USER_FIELD_LIMITS.positionTitle, 'errors.validation.max_length')
      .optional()
      .nullable()})
  .optional();

// Credentials never change through a profile edit. PUT /users/:id/password sets
// one directly and reset-credentials emails a link; both apply the password
// policy and end every session.
const credentialsFieldSchema = z
  .never({ message: 'errors.user.password_change_requires_reset' })
  .optional();

// ==================== Body Schemas ====================

/**
 * Create user body validation
 * Used for POST /users endpoint
 */
const createUserSchema = z.object({
  tenant_id: uuidOrFriendlyIdentifierSchema,
  facility_id: uuidOrFriendlyIdentifierSchema.optional().nullable(),
  first_name: nameSchema,
  last_name: optionalNameSchema,
  position_title: positionTitleSchema,
  email: emailSchema,
  phone: phoneSchema,
  password: applyPasswordPolicy(z.string().trim()),
  status: userStatusSchema,
  permission_ids: permissionIdsSchema,
  role_ids: roleIdsSchema,
  staff_profile: staffProfileSchema,
  confirm_similar: optionalBooleanSchema});

/**
 * Update user body validation
 * Used for PUT /users/:id endpoint
 * All fields optional for partial updates
 */
const updateUserSchema = z.object({
  facility_id: uuidOrFriendlyIdentifierSchema.optional().nullable(),
  first_name: nameSchema.optional(),
  last_name: optionalNameSchema,
  position_title: positionTitleSchema.optional(),
  email: emailSchema.optional(),
  phone: phoneSchema,
  status: userStatusSchema.optional(),
  permission_ids: permissionIdsSchema,
  password: credentialsFieldSchema,
  password_hash: credentialsFieldSchema,
  confirm_similar: optionalBooleanSchema});

/**
 * Set password body validation
 * Used for PUT /users/:id/password
 */
const setUserPasswordSchema = z.object({
  password: applyPasswordPolicy(z.string().trim())});

// ==================== URL Params ====================

/**
 * User ID URL parameter validation
 * Used for GET /:id, PUT /:id, and DELETE /:id endpoints
 */
const userIdParamsSchema = z.object({
  id: uuidOrFriendlyIdentifierSchema
});

// ==================== Query Params ====================

/**
 * List users query parameter validation
 * Used for GET / endpoint
 * Extends base listQuerySchema with user-specific filters
 */
const listUsersQuerySchema = listQuerySchema.extend({
  tenant_id: uuidOrFriendlyIdentifierSchema.optional(),
  facility_id: uuidOrFriendlyIdentifierSchema.optional(),
  position_title: z.string().trim().optional(),
  email: z.string().trim().optional(),
  status: userStatusSchema.optional(),
  search: z.string().trim().optional(),
  include_deleted: z.enum(['true', 'false']).optional()
});

module.exports = {
  USER_EMAIL_PATTERN,
  USER_FIELD_LIMITS,
  createUserSchema,
  updateUserSchema,
  setUserPasswordSchema,
  userIdParamsSchema,
  listUsersQuerySchema
};
