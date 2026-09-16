/**
 * Friendly-id sequence primitives
 *
 * @module lib/identifiers
 * @description Prefix derivation and counter scope keys for the
 * `human_id_counter` table. `src/prisma/client.js` uses these when it reserves
 * the next number; Accounts & Finance → Setup & Controls → Document Numbering
 * uses them to read the same counter back. Keeping both callers on one
 * implementation is what stops document numbering from acquiring a second
 * source of truth.
 */

const FRIENDLY_ID_PREFIX_LENGTH = 3;
const DEFAULT_FRIENDLY_ID_PADDING = 7;
const UNKNOWN_MODEL_PREFIX = 'XXX';

/**
 * Models whose derived three-letter prefix would be wrong or would collide
 * with another model's.
 */
const MODEL_PREFIX_OVERRIDES = Object.freeze({
  pharmacy_order: 'PHA',
  pharmacy_order_item: 'POI',
  tenant: 'TEN',
  facility: 'FAC',
  branch: 'BRA',
  department: 'DEP',
  unit: 'UNI',
  ward: 'WRD',
  room: 'ROM',
  bed: 'BED',
  user: 'USR',
  user_profile: 'UPR',
  user_role: 'URO',
  staff_position: 'SPO',
  patient: 'PAT',
  staff_profile: 'STF',
  appointment: 'APT',
  encounter: 'ENC',
  admission: 'ADM',
  clinical_term_catalog: 'CTC',
  invoice: 'INV',
  accounts_invoice: 'INV',
  payment: 'PAY',
  role: 'ROL',
  permission: 'PER',
  patient_identifier: 'PID',
  patient_contact: 'PCO',
  patient_guardian: 'PGU',
  patient_allergy: 'PAL',
  patient_document: 'PDO',
  patient_medical_history: 'PMH',
  // Would otherwise derive DOC and collide with `doctor`.
  document_number_sequence: 'DNS',
  feedback: 'FBK',
  // Would otherwise derive PAT and collide with `patient`.
  patient_deletion_batch: 'PDB',
  patient_deletion_batch_item: 'PDI',
});

/**
 * Models numbered on one platform-wide counter even when a row carries a
 * tenant or facility. Feedback is exported across every tenant, so its ids must
 * not repeat per tenant.
 */
const GLOBAL_COUNTER_MODELS = new Set(['feedback']);

/** Models that share a friendly-id counter with another model (same prefix). */
const FRIENDLY_ID_SEQUENCE_MODEL_ALIASES = Object.freeze({
  accounts_invoice: 'invoice',
});

const normalizePrefix = (value) =>
  String(value || '')
    .replace(/[^a-zA-Z0-9]/g, '')
    .toUpperCase()
    .slice(0, FRIENDLY_ID_PREFIX_LENGTH)
    .padEnd(FRIENDLY_ID_PREFIX_LENGTH, 'X');

const deriveModelPrefix = (model) => {
  if (!model) return UNKNOWN_MODEL_PREFIX;
  if (MODEL_PREFIX_OVERRIDES[model]) {
    return normalizePrefix(MODEL_PREFIX_OVERRIDES[model]);
  }

  const alphaNumericModelName = String(model).replace(/[^a-zA-Z0-9]/g, '');
  return normalizePrefix(alphaNumericModelName);
};

const formatFriendlyId = (prefix, sequence, padding = DEFAULT_FRIENDLY_ID_PADDING) =>
  `${normalizePrefix(prefix)}${String(sequence).padStart(padding, '0')}`;

/**
 * `human_id_counter.scope_key` for a plain model row.
 *
 * Narrowest scope wins: a facility-scoped record counts inside its facility, a
 * tenant-scoped one inside its tenant, and anything else globally.
 * `GLOBAL_COUNTER_MODELS` always count globally. `user_role` has an extra role
 * dimension and stays in `src/prisma/client.js`.
 */
const buildCounterScopeKey = (model, { tenantId, facilityId } = {}, prefix) => {
  if (GLOBAL_COUNTER_MODELS.has(model)) {
    return `global:model:${model}:prefix:${prefix}`;
  }
  if (typeof facilityId === 'string' && facilityId) {
    return `facility:${facilityId}:model:${model}:prefix:${prefix}`;
  }
  if (typeof tenantId === 'string' && tenantId) {
    return `tenant:${tenantId}:model:${model}:prefix:${prefix}`;
  }
  return `global:model:${model}:prefix:${prefix}`;
};

/** The model whose counter `model` actually draws from. */
const resolveCounterModel = (model) =>
  FRIENDLY_ID_SEQUENCE_MODEL_ALIASES[model] || model;

module.exports = {
  FRIENDLY_ID_PREFIX_LENGTH,
  DEFAULT_FRIENDLY_ID_PADDING,
  UNKNOWN_MODEL_PREFIX,
  MODEL_PREFIX_OVERRIDES,
  FRIENDLY_ID_SEQUENCE_MODEL_ALIASES,
  normalizePrefix,
  deriveModelPrefix,
  formatFriendlyId,
  buildCounterScopeKey,
  resolveCounterModel,
};
