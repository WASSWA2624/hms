/**
 * OPD flow service
 *
 * @module modules/opd-flow/services
 * @description OPD patient flow orchestration rooted on encounter records.
 * Per module-creation.mdc: Services only import/use their own repository.
 * Per prisma.mdc: direct model operations in service are limited to prisma.$transaction orchestration.
 */

const opdFlowRepository = require('@repositories/opd-flow/opd-flow.repository');
const prisma = require('@prisma/client');
const { createAuditLog } = require('@lib/audit');
const { HttpError } = require('@lib/errors');
const { emitToUser, emitToUsers, OPD_EVENTS, NOTIFICATION_EVENTS } = require('@lib/websocket');
const { ROLES, normalizeRoleName } = require('@config/roles');
const clinicalAlertThresholdService = require('@services/clinical-alert-threshold/clinical-alert-threshold.service');
const { LAB_PANEL_WITH_RELATIONS_INCLUDE } = require('@services/lab-workspace/lab.shared');
const { STANDARD_LAB_PANELS, STANDARD_LAB_TESTS } = require('@services/lab-order/lab-order.service');
const {
  ACTIVE_OPD_ENCOUNTER_TYPES,
  activeOpdLockKeyForEncounter,
  buildActiveOpdLockKey,
  throwActiveOpdEncounterExists,
  throwIfActiveOpdLockError
} = require('@lib/opd-active-encounter');
const { CONSULTATION_FEE_PRACTITIONER_TYPES } = require('@lib/hr/reference-data');
const { recalculateInvoiceStateTx, computeInvoiceFinancials } = require('@lib/billing/financials');
const {
  buildConsultationBillingPayload,
  persistConsultationBilling,
  cancelInvoiceIfReversible} = require('@lib/billing/clinical-request-billing');
const {
  publishIssuedInvoiceBillingEvents,
  publishUpdatedInvoiceBillingEvents} = require('@lib/billing/realtime');

const STAGES = {
  WAITING_CONSULTATION_PAYMENT: 'WAITING_CONSULTATION_PAYMENT',
  WAITING_VITALS: 'WAITING_VITALS',
  WAITING_DOCTOR_ASSIGNMENT: 'WAITING_DOCTOR_ASSIGNMENT',
  WAITING_DOCTOR_REVIEW: 'WAITING_DOCTOR_REVIEW',
  LAB_REQUESTED: 'LAB_REQUESTED',
  RADIOLOGY_REQUESTED: 'RADIOLOGY_REQUESTED',
  LAB_AND_RADIOLOGY_REQUESTED: 'LAB_AND_RADIOLOGY_REQUESTED',
  PHARMACY_REQUESTED: 'PHARMACY_REQUESTED',
  WAITING_DISPOSITION: 'WAITING_DISPOSITION',
  ADMITTED: 'ADMITTED',
  DISCHARGED: 'DISCHARGED'
};

const TERMINAL_STAGES = new Set([STAGES.ADMITTED, STAGES.DISCHARGED]);
// Stages that sit before the consultation itself. Any of them may be skipped:
// billing, vitals and doctor assignment are independent of each other, so
// recording vitals or starting a review from any of them pulls the flow
// forward instead of rejecting the action.
const PRE_CONSULTATION_STAGES = new Set([
  STAGES.WAITING_CONSULTATION_PAYMENT,
  STAGES.WAITING_VITALS,
  STAGES.WAITING_DOCTOR_ASSIGNMENT
]);
const WORKFLOW_STAGE_SET = new Set(Object.values(STAGES));
const WORKFLOW_STAGE_ORDER = Object.values(STAGES);
const QUEUE_SCOPES = Object.freeze({
  ASSIGNED: 'ASSIGNED',
  WAITING: 'WAITING',
  ALL: 'ALL'
});
const WAITING_QUEUE_STAGES = [STAGES.WAITING_DOCTOR_ASSIGNMENT];
const PAID_PAYMENT_STATUSES = new Set(['COMPLETED', 'PAID', 'SUCCESS', 'SUCCESSFUL', 'APPROVED']);
const PAID_BILLING_STATUSES = new Set(['PAID', 'SETTLED', 'CLEARED']);
const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const BLOOD_PRESSURE_VALUE_REGEX = /^(\d{2,3}(?:\.\d{1,2})?)\s*\/\s*(\d{2,3}(?:\.\d{1,2})?)$/;
const MAX_OPD_SEARCH_TOKENS = 6;
const OPD_FLOW_STAGE_JSON_PATH = '$.opd_flow.stage';
const OPD_FLOW_APPOINTMENT_ID_JSON_PATH = '$.opd_flow.appointment_id';
const OPD_FLOW_VISIT_QUEUE_ID_JSON_PATH = '$.opd_flow.visit_queue_id';
const OPD_FLOW_EMERGENCY_CASE_ID_JSON_PATH = '$.opd_flow.emergency_case_id';
const LEGACY_ROUTE_CONFIG = Object.freeze({
  'emergency-cases': {
    model: 'emergency_case',
    panel: 'queue',
    action: 'open_case'
  },
  'triage-assessments': {
    model: 'triage_assessment',
    emergencyCaseField: 'emergency_case_id',
    panel: 'intake',
    action: 'update_triage'
  },
  'emergency-responses': {
    model: 'emergency_response',
    emergencyCaseField: 'emergency_case_id',
    panel: 'responses',
    action: 'add_response'
  },
  ambulances: {
    model: 'ambulance',
    ambulanceField: 'id',
    panel: 'ambulance',
    action: 'view_fleet'
  },
  'ambulance-dispatches': {
    model: 'ambulance_dispatch',
    emergencyCaseField: 'emergency_case_id',
    ambulanceField: 'ambulance_id',
    panel: 'dispatch',
    action: 'manage_dispatch'
  },
  'ambulance-trips': {
    model: 'ambulance_trip',
    emergencyCaseField: 'emergency_case_id',
    ambulanceField: 'ambulance_id',
    panel: 'trips',
    action: 'manage_trip'
  }
});

const PROVIDER_PROFILE_SELECT = {
  first_name: true,
  middle_name: true,
  last_name: true
};

const PROVIDER_STAFF_PROFILE_SELECT = {
  id: true,
  human_friendly_id: true,
  staff_number: true,
  position: true,
  practitioner_type: true,
  consultation_fee: true,
  consultation_currency: true,
  deleted_at: true
};

const PROVIDER_SELECT = {
  id: true,
  human_friendly_id: true,
  tenant_id: true,
  facility_id: true,
  email: true,
  phone: true,
  status: true,
  created_at: true,
  updated_at: true,
  deleted_at: true,
  version: true,
  profile: {
    select: PROVIDER_PROFILE_SELECT
  },
  staff_profile: {
    select: PROVIDER_STAFF_PROFILE_SELECT
  },
  roles: {
    where: { deleted_at: null },
    select: {
      role: {
        select: { name: true }
      }
    }
  }
};

const PROVIDER_INCLUDE = {
  select: PROVIDER_SELECT
};

const TRIAGE_ALIAS_MAP = {
  IMMEDIATE: 'LEVEL_1',
  URGENT: 'LEVEL_2',
  LESS_URGENT: 'LEVEL_3',
  NON_URGENT: 'LEVEL_4',
  LEVEL_1: 'LEVEL_1',
  LEVEL_2: 'LEVEL_2',
  LEVEL_3: 'LEVEL_3',
  LEVEL_4: 'LEVEL_4',
  LEVEL_5: 'LEVEL_5'
};

const normalizeIdentifier = (value) => (typeof value === 'string' ? value.trim() : '');
const normalizeNotes = (value) => {
  const normalized = typeof value === 'string' ? value.trim() : '';
  return normalized || null;
};
const buildOpdFlowJsonFilter = (jsonPath, equalsValue) => ({
  path: jsonPath,
  equals: equalsValue
});
const buildOpdFlowStagePresenceClause = () => ({
  OR: Object.values(STAGES).map((stage) => ({
    extension_json: buildOpdFlowJsonFilter(OPD_FLOW_STAGE_JSON_PATH, stage)
  }))
});

const stageCorrectionRequiresReason = (stageFrom, stageTo) => {
  if (TERMINAL_STAGES.has(stageTo)) return true;
  const fromIndex = WORKFLOW_STAGE_ORDER.indexOf(stageFrom);
  const toIndex = WORKFLOW_STAGE_ORDER.indexOf(stageTo);
  if (fromIndex < 0 || toIndex < 0) return true;
  return toIndex < fromIndex || Math.abs(toIndex - fromIndex) > 1;
};

const normalizeSearchTokens = (search) =>
  String(search || '')
    .trim()
    .split(/\s+/)
    .map((token) => token.trim())
    .filter(Boolean)
    .slice(0, MAX_OPD_SEARCH_TOKENS);

const isUuid = (value) => UUID_REGEX.test(normalizeIdentifier(value));
const toPublicIdentifier = (value) => {
  const normalized = normalizeIdentifier(value);
  if (!normalized || isUuid(normalized)) return null;
  return normalized;
};

const resolveTenantByIdentifier = async (tx, identifier) => {
  const normalized = normalizeIdentifier(identifier);
  if (!normalized) return null;
  if (!tx?.tenant?.findFirst) {
    return null;
  }

  return tx.tenant.findFirst({
    where: {
      deleted_at: null,
      OR: isUuid(normalized) ? [{ id: normalized }] : [{ human_friendly_id: normalized.toUpperCase() }]
    }
  });
};

const resolveFacilityByIdentifier = async (tx, identifier, tenantId = null) => {
  const normalized = normalizeIdentifier(identifier);
  if (!normalized) return null;
  if (!tx?.facility?.findFirst) {
    return null;
  }

  return tx.facility.findFirst({
    where: {
      deleted_at: null,
      ...(tenantId ? { tenant_id: tenantId } : {}),
      OR: isUuid(normalized) ? [{ id: normalized }] : [{ human_friendly_id: normalized.toUpperCase() }]
    }
  });
};

const resolveEntityByIdentifier = async (tx, modelName, identifier, where = {}) => {
  const normalized = normalizeIdentifier(identifier);
  if (!normalized) return null;
  const delegate = tx?.[modelName];
  if (!delegate?.findFirst) {
    return null;
  }

  return delegate.findFirst({
    where: {
      deleted_at: null,
      ...where,
      OR: isUuid(normalized) ? [{ id: normalized }] : [{ human_friendly_id: normalized.toUpperCase() }]
    }
  });
};

const resolvePatientLookupWhere = (identifier, tenantId = null) => {
  const normalized = normalizeIdentifier(identifier);
  if (!normalized) return null;

  const where = {
    deleted_at: null,
    ...(tenantId ? { tenant_id: tenantId } : {})
  };

  if (isUuid(normalized)) {
    return {
      ...where,
      id: normalized
    };
  }

  return {
    ...where,
    human_friendly_id: normalized.toUpperCase()
  };
};

const resolvePatientByIdentifier = async (tx, identifier, tenantId = null) => {
  const where = resolvePatientLookupWhere(identifier, tenantId);
  if (!where) return null;
  if (!tx?.patient?.findFirst) {
    return null;
  }

  return tx.patient.findFirst({ where });
};

const resolveUserLookupWhere = (identifier, tenantId = null, facilityId = null) => {
  const normalized = normalizeIdentifier(identifier);
  if (!normalized) return null;

  const where = {
    deleted_at: null,
    ...(tenantId ? { tenant_id: tenantId } : {})
  };

  if (facilityId) {
    where.OR = [{ facility_id: facilityId }, { facility_id: null }];
  }

  if (isUuid(normalized)) {
    return {
      ...where,
      id: normalized
    };
  }

  const upper = normalized.toUpperCase();
  return {
    ...where,
    AND: [
      ...(Array.isArray(where.OR) ? [{ OR: where.OR }] : []),
      {
        OR: [
          { human_friendly_id: upper },
          { email: normalized },
          { phone: normalized },
          { profile: { first_name: { contains: normalized } } },
          { profile: { middle_name: { contains: normalized } } },
          { profile: { last_name: { contains: normalized } } },
          { staff_profile: { human_friendly_id: { contains: upper } } },
          { staff_profile: { staff_number: { contains: normalized } } },
          { staff_profile: { position: { contains: normalized } } },
          { staff_profile: { practitioner_type: { contains: upper } } }
        ]
      }
    ]
  };
};

const resolveProviderByIdentifier = async (tx, identifier, tenantId = null, facilityId = null) => {
  const normalized = normalizeIdentifier(identifier);
  if (!normalized) return null;
  if (!tx?.user?.findFirst) {
    return null;
  }

  const facilityScopedWhere = resolveUserLookupWhere(identifier, tenantId, facilityId);
  if (!facilityScopedWhere) return null;

  const facilityScopedProvider = await tx.user.findFirst({
    where: facilityScopedWhere,
    select: PROVIDER_SELECT
  });
  if (facilityScopedProvider || !facilityId) {
    return facilityScopedProvider;
  }

  const tenantScopedWhere = resolveUserLookupWhere(identifier, tenantId, null);
  if (!tenantScopedWhere) return null;

  return tx.user.findFirst({
    where: tenantScopedWhere,
    select: PROVIDER_SELECT
  });
};

const resolveAppointmentByIdentifier = async (tx, identifier, tenantId = null, facilityId = null) => {
  const normalized = normalizeIdentifier(identifier);
  if (!normalized) return null;
  if (!tx?.appointment?.findFirst) return null;

  const where = {
    deleted_at: null,
    ...(tenantId ? { tenant_id: tenantId } : {}),
    ...(facilityId ? { facility_id: facilityId } : {})
  };

  if (isUuid(normalized)) {
    return tx.appointment.findFirst({
      where: {
        ...where,
        id: normalized
      }
    });
  }

  return tx.appointment.findFirst({
    where: {
      ...where,
      human_friendly_id: normalized.toUpperCase()
    }
  });
};

const resolveVisitQueueByIdentifier = async (tx, identifier, tenantId = null, facilityId = null) => {
  const normalized = normalizeIdentifier(identifier);
  if (!normalized) return null;
  if (!tx?.visit_queue?.findFirst) return null;

  const where = {
    deleted_at: null,
    ...(tenantId ? { tenant_id: tenantId } : {}),
    ...(facilityId ? { facility_id: facilityId } : {})
  };

  if (isUuid(normalized)) {
    return tx.visit_queue.findFirst({
      where: {
        ...where,
        id: normalized
      }
    });
  }

  return tx.visit_queue.findFirst({
    where: {
      ...where,
      human_friendly_id: normalized.toUpperCase()
    }
  });
};

const resolveEmergencyCaseByIdentifier = async (
  tx,
  identifier,
  tenantId = null,
  facilityId = null,
  patientId = null
) => {
  const normalized = normalizeIdentifier(identifier);
  if (!normalized) return null;
  if (!tx?.emergency_case?.findFirst) return null;

  const where = {
    deleted_at: null,
    ...(tenantId ? { tenant_id: tenantId } : {}),
    ...(facilityId ? { facility_id: facilityId } : {}),
    ...(patientId ? { patient_id: patientId } : {})
  };

  if (isUuid(normalized)) {
    return tx.emergency_case.findFirst({
      where: {
        ...where,
        id: normalized
      }
    });
  }

  return tx.emergency_case.findFirst({
    where: {
      ...where,
      human_friendly_id: normalized.toUpperCase()
    }
  });
};

const resolveEncounterByIdentifier = async (tx, identifier, options = {}) => {
  const normalized = normalizeIdentifier(identifier);
  if (!normalized) return null;
  if (!tx?.encounter?.findFirst) return null;
  const include = options?.include || undefined;
  return tx.encounter.findFirst({
    where: {
      OR: [{ id: normalized }, { human_friendly_id: normalized.toUpperCase() }],
      deleted_at: null,
      encounter_type: { in: ['OPD', 'EMERGENCY'] }
    },
    ...(include ? { include } : {})
  });
};

const resolveOpenEncounterForPatient = async (
  tx,
  { tenantId, facilityId, patientId, encounterTypes = ACTIVE_OPD_ENCOUNTER_TYPES }
) => {
  return opdFlowRepository.findOpenActiveEncounterForPatient(
    {
      tenantId,
      facilityId,
      patientId,
      encounterTypes
    },
    tx
  );
};

const standardCatalogCodeFromIdentifier = (identifier, prefix) => {
  const normalized = normalizeIdentifier(identifier).toUpperCase();
  if (!normalized.startsWith(`${prefix}:`)) {
    return null;
  }
  return normalized.slice(prefix.length + 1);
};

const resolveOrCreateStandardLabTest = async (tx, { identifier, tenantId, context = {} }) => {
  const catalogCode = standardCatalogCodeFromIdentifier(identifier, 'STD_LAB_TEST');
  if (!catalogCode) {
    return null;
  }

  const definition = STANDARD_LAB_TESTS[catalogCode];
  if (!definition) {
    return null;
  }

  const existing = await tx.lab_test.findFirst({
    where: {
      tenant_id: tenantId,
      deleted_at: null,
      code: definition.code
    },
    select: { id: true }
  });
  if (existing) {
    return existing;
  }

  const labTest = await tx.lab_test.create({
    data: {
      tenant_id: tenantId,
      name: definition.name,
      code: definition.code,
      category: definition.category,
      specimen_type: definition.specimen_type,
      result_kind: definition.result_kind,
      unit: definition.unit,
      description: definition.description,
      ...(definition.unit
        ? {
            unit_options: {
              create: [
                {
                  label: null,
                  unit: definition.unit,
                  ucum_code: null,
                  is_default: true,
                  sort_order: 0
                }
              ]
            }
          }
        : {})
    },
    select: { id: true }
  });

  createAuditLog({
    tenant_id: tenantId,
    user_id: context.user_id || null,
    action: 'CREATE',
    entity: 'lab_test',
    entity_id: labTest.id,
    diff: {
      after: { ...definition, id: labTest.id, source: 'STANDARD_LAB_CATALOG' }
    },
    ip_address: context.ip_address
  }).catch(() => {});

  return labTest;
};

const resolveLabTestRequest = async (tx, { identifier, tenantId, context = {} }) => {
  const standardLabTest = await resolveOrCreateStandardLabTest(tx, {
    identifier,
    tenantId,
    context
  });
  if (standardLabTest) {
    return standardLabTest;
  }

  return resolveEntityByIdentifier(tx, 'lab_test', identifier, {
    tenant_id: tenantId
  });
};

const throwIfPatientHasOpenEncounter = async (tx, { tenantId, facilityId, patientId }) => {
  const existing = await resolveOpenEncounterForPatient(tx, {
    tenantId,
    facilityId,
    patientId,
    encounterTypes: ACTIVE_OPD_ENCOUNTER_TYPES
  });

  if (!existing) {
    return;
  }

  throwActiveOpdEncounterExists({
    encounter_id: existing.human_friendly_id || existing.id,
    encounter_type: existing.encounter_type,
    stage: existing.extension_json?.opd_flow?.stage || null
  });
};

const NEXT_STEP_BY_STAGE = {
  [STAGES.WAITING_CONSULTATION_PAYMENT]: 'PAY_CONSULTATION',
  [STAGES.WAITING_VITALS]: 'RECORD_VITALS',
  [STAGES.WAITING_DOCTOR_ASSIGNMENT]: 'ASSIGN_DOCTOR',
  [STAGES.WAITING_DOCTOR_REVIEW]: 'DOCTOR_REVIEW',
  [STAGES.WAITING_DISPOSITION]: 'DISPOSITION',
  [STAGES.LAB_REQUESTED]: 'LAB_WORKSPACE',
  [STAGES.RADIOLOGY_REQUESTED]: 'RADIOLOGY_WORKSPACE',
  [STAGES.LAB_AND_RADIOLOGY_REQUESTED]: 'DIAGNOSTICS_PENDING',
  [STAGES.PHARMACY_REQUESTED]: 'PHARMACY_WORKSPACE',
  [STAGES.ADMITTED]: null,
  [STAGES.DISCHARGED]: null
};

const STAGE_ROLE_TEAM_MAP = {
  // Nurses are notified too: triage can start while the invoice is settled.
  [STAGES.WAITING_CONSULTATION_PAYMENT]: [ROLES.RECEPTIONIST, ROLES.BILLING, ROLES.NURSE],
  [STAGES.WAITING_VITALS]: [ROLES.NURSE],
  [STAGES.WAITING_DOCTOR_ASSIGNMENT]: [ROLES.RECEPTIONIST, ROLES.NURSE],
  [STAGES.WAITING_DOCTOR_REVIEW]: [ROLES.DOCTOR],
  [STAGES.LAB_REQUESTED]: [ROLES.LAB_TECH],
  [STAGES.RADIOLOGY_REQUESTED]: [ROLES.RADIOLOGY_TECH],
  [STAGES.LAB_AND_RADIOLOGY_REQUESTED]: [ROLES.LAB_TECH, ROLES.RADIOLOGY_TECH],
  [STAGES.PHARMACY_REQUESTED]: [ROLES.PHARMACIST],
  [STAGES.WAITING_DISPOSITION]: [ROLES.DOCTOR],
  [STAGES.ADMITTED]: [ROLES.RECEPTIONIST, ROLES.OPERATIONS],
  [STAGES.DISCHARGED]: [ROLES.RECEPTIONIST, ROLES.OPERATIONS]
};

// A new encounter is a revenue event: Billing and Accounting are notified on
// START_FLOW even when the opening stage does not route work to them.
const ENCOUNTER_CREATED_ROLE_TEAM = [ROLES.BILLING, ROLES.ACCOUNTANT];

const START_FLOW_ACTION = 'START_FLOW';

const formatStageLabel = (stage) =>
  String(stage || 'UPDATED')
    .trim()
    .replace(/_/g, ' ')
    .toLowerCase();

const buildOpdFlowListEntry = (snapshot) => {
  const encounter = snapshot?.encounter;
  if (!encounter) {
    return null;
  }
  const flow = snapshot?.flow || encounter?.extension_json?.opd_flow;
  if (!flow) {
    return null;
  }
  return {
    encounter,
    flow: attachResolvedDisplayToFlow(encounter, flow)
  };
};

const buildFlowSummary = (snapshot) => {
  const flow = snapshot?.flow || {};
  const timeline = Array.isArray(flow.timeline)
    ? flow.timeline
    : Array.isArray(snapshot?.timeline)
      ? snapshot.timeline
      : [];

  return {
    stage: flow.stage || null,
    next_step: flow.display_next_step || flow.next_step || null,
    display_code: flow.display_code || null,
    display_status: flow.display_status || null,
    assigned_staff_role: flow.assigned_staff_role || null,
    assigned_staff_type: flow.assigned_staff_type || null,
    assigned_staff_label: flow.assigned_staff_label || null,
    encounter_type: snapshot?.encounter?.encounter_type || null,
    timeline_count: timeline.length
  };
};

const buildConsultationSummary = (snapshot) => {
  const consultation =
    snapshot?.flow?.consultation || snapshot?.encounter?.extension_json?.opd_flow?.consultation || null;
  if (!consultation) {
    return null;
  }
  return {
    require_payment: consultation.require_payment === true,
    consultation_fee: consultation.consultation_fee ?? null,
    currency: consultation.currency || null,
    invoice_id: consultation.invoice_id || null,
    payment_status: consultation.payment_status || null,
    is_paid: consultation.is_paid === true
  };
};

const formatConsultationAmount = (consultation) => {
  const fee = consultation?.consultation_fee;
  if (fee === null || fee === undefined || fee === '') {
    return null;
  }
  const currency = String(consultation?.currency || '').trim();
  return currency ? `${fee} ${currency}` : String(fee);
};

const buildRealtimePayload = ({ snapshot, transition, context }) => {
  const encounterPublicId = snapshot?.encounter?.human_friendly_id || null;
  const providerPublicId = snapshot?.encounter?.provider?.human_friendly_id || null;
  const patientPublicId = snapshot?.encounter?.patient?.human_friendly_id || null;
  const tenantPublicId = snapshot?.encounter?.tenant?.human_friendly_id || null;
  const facilityPublicId = snapshot?.encounter?.facility?.human_friendly_id || null;
  const providerInternalId = snapshot?.encounter?.provider_user_id || transition?.provider_user_id || null;
  const actorInternalId = context?.user_id || null;
  const stageTo = transition?.stage_to || snapshot?.flow?.stage || null;
  const stageFrom = transition?.stage_from || null;
  const occurredAt =
    transition?.occurred_at || snapshot?.encounter?.updated_at?.toISOString?.() || new Date().toISOString();

  return {
    encounter_id: encounterPublicId || snapshot?.encounter?.id || null,
    encounter_public_id: encounterPublicId,
    tenant_id: tenantPublicId,
    facility_id: facilityPublicId,
    tenant_internal_id: snapshot?.encounter?.tenant_id || context?.tenant_id || null,
    facility_internal_id: snapshot?.encounter?.facility_id || context?.facility_id || null,
    patient_id: patientPublicId,
    provider_user_id: providerPublicId,
    stage_from: stageFrom,
    stage_to: stageTo,
    next_step: snapshot?.flow?.next_step || null,
    action: transition?.action || 'OPD_FLOW_UPDATED',
    actor_user_id: actorInternalId,
    provider_internal_user_id: providerInternalId,
    actor_internal_user_id: actorInternalId,
    occurred_at: occurredAt,
    operation: 'upsert',
    list_entry: buildOpdFlowListEntry(snapshot),
    flow_summary: buildFlowSummary(snapshot),
    consultation: buildConsultationSummary(snapshot),
    target_path: encounterPublicId ? `/scheduling/opd-flows/${encounterPublicId}` : '/scheduling/opd-flows'
  };
};

const buildOpdNotificationContent = (payload, { isAssignedProvider = false } = {}) => {
  const stageLabel = formatStageLabel(payload?.stage_to || payload?.flow_summary?.stage);
  const encounterLabel = payload.encounter_public_id || 'unknown';

  if (payload?.action === START_FLOW_ACTION) {
    const patientSuffix = payload.patient_id ? ` for patient ${payload.patient_id}` : '';

    if (isAssignedProvider) {
      return {
        title: 'New OPD patient assigned to you',
        message: `Encounter ${encounterLabel}${patientSuffix} is assigned to you and is now ${stageLabel}.`
      };
    }

    const amount = formatConsultationAmount(payload.consultation);
    const chargeSuffix = amount
      ? ` Consultation fee ${amount}${payload.consultation?.require_payment ? ' (payment required)' : ''}.`
      : '';
    return {
      title: 'OPD encounter started',
      message: `Encounter ${encounterLabel}${patientSuffix} was started and is now ${stageLabel}.${chargeSuffix}`
    };
  }

  return {
    title: `OPD flow update: ${stageLabel}`,
    message: `Encounter ${encounterLabel} is now ${stageLabel}.`
  };
};

const resolveRoleRecipients = async ({ tenantId, facilityId, roles = [] }) => {
  if (!tenantId || !Array.isArray(roles) || roles.length === 0) {
    return [];
  }

  if (!prisma?.user_role?.findMany) {
    return [];
  }

  const where = {
    tenant_id: tenantId,
    deleted_at: null,
    role: {
      deleted_at: null,
      name: { in: roles }
    }
  };

  if (facilityId) {
    where.OR = [{ facility_id: facilityId }, { facility_id: null }];
  }

  const rows = await prisma.user_role.findMany({
    where,
    select: { user_id: true }
  });

  return rows.map((row) => row.user_id).filter(Boolean);
};

const resolveOpdRecipientUserIds = async ({ payload }) => {
  const stageTeams = STAGE_ROLE_TEAM_MAP[payload.stage_to] || [];
  const roleTeams = Array.from(
    new Set(
      payload.action === START_FLOW_ACTION
        ? [...stageTeams, ...ENCOUNTER_CREATED_ROLE_TEAM]
        : stageTeams
    )
  );
  const roleRecipients = await resolveRoleRecipients({
    tenantId: payload.tenant_internal_id,
    facilityId: payload.facility_internal_id,
    roles: roleTeams
  });

  const recipientSet = new Set(roleRecipients);
  if (payload.provider_internal_user_id) {
    recipientSet.add(payload.provider_internal_user_id);
  }
  if (payload.actor_internal_user_id) {
    recipientSet.delete(payload.actor_internal_user_id);
  }

  return Array.from(recipientSet).filter(Boolean);
};

const toSafeNotificationPayload = (notification, targetPath) => ({
  id: notification.human_friendly_id || null,
  tenant_id: null,
  user_id: null,
  notification_type: notification.notification_type,
  priority: notification.priority,
  title: notification.title,
  message: notification.message,
  read_at: notification.read_at || null,
  created_at: notification.created_at,
  updated_at: notification.updated_at,
  target_path: targetPath
});

const createAndEmitOpdNotifications = async ({ payload, recipientUserIds }) => {
  if (!Array.isArray(recipientUserIds) || recipientUserIds.length === 0) {
    return [];
  }

  if (!prisma?.notification?.create) {
    return [];
  }

  const isEmergency = payload?.flow_summary?.encounter_type === 'EMERGENCY';
  const assignedProviderUserId = payload.provider_internal_user_id || null;

  const createdNotifications = [];

  for (const userId of recipientUserIds) {
    const isAssignedProvider = Boolean(assignedProviderUserId) && userId === assignedProviderUserId;
    // The assigned doctor's own hand-off is escalated so it surfaces at once.
    const priority =
      isEmergency || (isAssignedProvider && payload.action === START_FLOW_ACTION) ? 'HIGH' : 'MEDIUM';
    const { title, message } = buildOpdNotificationContent(payload, { isAssignedProvider });

    // Keep notification creation resilient and non-blocking per user.
    try {
      const notification = await prisma.notification.create({
        data: {
          tenant_id: payload.tenant_internal_id,
          user_id: userId,
          notification_type: 'SYSTEM',
          priority,
          title,
          message
        }
      });
      createdNotifications.push(notification);
    } catch (_err) {
      // Notification creation should not block OPD flow progression.
    }
  }

  if (createdNotifications.length > 0 && prisma?.notification_delivery?.createMany) {
    try {
      await prisma.notification_delivery.createMany({
        data: createdNotifications.map((notification) => ({
          notification_id: notification.id,
          channel: 'IN_APP',
          status: 'SENT',
          sent_at: new Date()
        }))
      });
    } catch (_err) {
      // Delivery metadata failure should not block clinical flow.
    }
  }

  createdNotifications.forEach((notification) => {
    emitToUser(notification.user_id, NOTIFICATION_EVENTS.NOTIFICATION_CREATED, {
      notification: toSafeNotificationPayload(notification, payload.target_path),
      target_path: payload.target_path
    });
  });

  return createdNotifications;
};

const publishOpdRealtimeUpdates = async ({ snapshot, transition, context }) => {
  try {
    const payload = buildRealtimePayload({
      snapshot,
      transition,
      context
    });
    const recipientUserIds = await resolveOpdRecipientUserIds({ payload });
    if (recipientUserIds.length > 0) {
      emitToUsers(recipientUserIds, OPD_EVENTS.OPD_FLOW_UPDATED, payload);
      await createAndEmitOpdNotifications({ payload, recipientUserIds });
    }
  } catch (_err) {
    // Realtime updates must never fail the OPD transaction response path.
  }
};

const CONSULTATION_INVOICE_REALTIME_INCLUDE = Object.freeze({
  patient: {
    select: {
      id: true,
      human_friendly_id: true,
      first_name: true,
      last_name: true}}});

const resolveConsultationInvoiceId = (snapshot, explicitInvoiceId = null) =>
  normalizeIdentifier(explicitInvoiceId) ||
  normalizeIdentifier(snapshot?.flow?.consultation?.invoice_id) ||
  normalizeIdentifier(
    snapshot?.encounter?.extension_json?.opd_flow?.consultation?.invoice_id
  ) ||
  null;

const loadConsultationInvoiceForRealtime = async (snapshot, explicitInvoiceId = null) => {
  const invoiceId = resolveConsultationInvoiceId(snapshot, explicitInvoiceId);
  if (!invoiceId) {
    return null;
  }
  const invoice = await prisma.invoice.findFirst({
    where: { id: invoiceId },
    include: CONSULTATION_INVOICE_REALTIME_INCLUDE});
  if (!invoice) {
    return null;
  }
  const encounterId =
    normalizeIdentifier(invoice.encounter_id) ||
    normalizeIdentifier(snapshot?.encounter?.id) ||
    null;
  if (encounterId && !invoice.encounter_id) {
    invoice.encounter_id = encounterId;
  }
  return invoice;
};

/**
 * Push consultation invoice create/update into Billing workspace queues.
 * Never throws — billing notify must not block OPD responses.
 */
const publishConsultationBillingRealtime = async ({
  snapshot,
  context = {},
  mode = 'issued',
  invoiceId = null} = {}) => {
  try {
    const invoice = await loadConsultationInvoiceForRealtime(snapshot, invoiceId);
    if (!invoice) {
      return;
    }
    const actorUserId = context.user_id || null;
    if (mode === 'cancelled' || mode === 'updated') {
      await publishUpdatedInvoiceBillingEvents({
        invoice,
        actorUserId,
        action: mode === 'cancelled' ? 'CANCELLED' : 'UPDATED'});
      return;
    }
    await publishIssuedInvoiceBillingEvents({
      invoice,
      actorUserId,
      action: 'ISSUED'});
  } catch (_err) {
    // Billing realtime must never fail the OPD transaction response path.
  }
};

const toDecimalNumber = (value) => {
  if (value === null || value === undefined) return 0;
  if (typeof value === 'number') return value;
  if (typeof value === 'string') return Number(value);
  if (typeof value.toNumber === 'function') return value.toNumber();
  if (typeof value.toString === 'function') return Number(value.toString());
  return Number(value);
};

const normalizeDecimalString = (value, fallback = '0.00') => {
  if (value === null || value === undefined || value === '') {
    return fallback;
  }
  if (typeof value === 'string') {
    return value;
  }
  if (typeof value.toString === 'function') {
    return value.toString();
  }
  return String(value);
};

const normalizeCurrencyCode = (value, fallback = null) => {
  const normalized = normalizeIdentifier(value).toUpperCase();
  return normalized || fallback;
};

const normalizeUpper = (value) => normalizeIdentifier(value).toUpperCase();

const uniqueNormalizedIdentifiers = (values = []) =>
  Array.from(new Set(values.map((value) => normalizeIdentifier(value)).filter(Boolean)));

const lookupIdentifierKeys = (value) => {
  const normalized = normalizeIdentifier(value);
  if (!normalized) return [];
  const upper = normalized.toUpperCase();
  return normalized === upper ? [normalized] : [normalized, upper];
};

const setLookupRecord = (target, identifier, record) => {
  for (const key of lookupIdentifierKeys(identifier)) {
    target.set(key, record);
  }
};

const getLookupRecord = (source, identifier) => {
  for (const key of lookupIdentifierKeys(identifier)) {
    if (source.has(key)) return source.get(key);
  }
  return null;
};

const positiveDecimalStringOrNull = (value) => {
  const amount = toDecimalNumber(value);
  if (!Number.isFinite(amount) || amount <= 0) return null;
  return normalizeDecimalString(value, amount.toFixed(2));
};

const sumPaidPayments = (payments = []) => {
  const total = (Array.isArray(payments) ? payments : []).reduce((sum, payment) => {
    if (!payment || payment.deleted_at) return sum;
    if (!PAID_PAYMENT_STATUSES.has(normalizeUpper(payment.status))) return sum;
    return sum + toDecimalNumber(payment.amount);
  }, 0);
  return total > 0 ? total.toFixed(2) : null;
};

const resolveConsultationPaymentAmount = ({ consultation = {}, invoice = null, payment = null } = {}) => {
  const directAmount = positiveDecimalStringOrNull(
    consultation.paid_amount || consultation.payment_amount || consultation.amount_paid
  );
  if (directAmount) return directAmount;

  if (payment && PAID_PAYMENT_STATUSES.has(normalizeUpper(payment.status))) {
    const paymentAmount = positiveDecimalStringOrNull(payment.amount);
    if (paymentAmount) return paymentAmount;
  }

  const invoicePaymentAmount = sumPaidPayments(invoice?.payments);
  if (invoicePaymentAmount) return invoicePaymentAmount;

  const consultationIsPaid =
    consultation.is_paid === true ||
    consultation.paid === true ||
    PAID_PAYMENT_STATUSES.has(normalizeUpper(consultation.payment_status));
  const invoiceIsPaid =
    PAID_BILLING_STATUSES.has(normalizeUpper(invoice?.billing_status)) ||
    PAID_BILLING_STATUSES.has(normalizeUpper(invoice?.status));

  if (consultationIsPaid || invoiceIsPaid) {
    return positiveDecimalStringOrNull(invoice?.total_amount);
  }

  return null;
};

const resolveConsultationFeeAmount = (consultation = {}, invoice = null) => {
  return (
    positiveDecimalStringOrNull(consultation.consultation_fee) ||
    positiveDecimalStringOrNull(consultation.fee) ||
    positiveDecimalStringOrNull(invoice?.total_amount) ||
    normalizeDecimalString(consultation.consultation_fee, null)
  );
};

/**
 * Prefer live invoice/payment state over a stale consultation snapshot so Desk
 * queue Payment-due does not outlive Billing PAID invoices.
 */
const resolveConsultationPaymentStatus = ({ consultation = {}, invoice = null, payment = null } = {}) => {
  if (payment && PAID_PAYMENT_STATUSES.has(normalizeUpper(payment.status))) {
    return 'PAID';
  }

  const invoiceBillingStatus = normalizeUpper(invoice?.billing_status);
  const invoiceStatus = normalizeUpper(invoice?.status);
  if (PAID_BILLING_STATUSES.has(invoiceBillingStatus) || PAID_BILLING_STATUSES.has(invoiceStatus)) {
    return 'PAID';
  }
  if (invoiceBillingStatus === 'PARTIAL') {
    return 'PARTIAL';
  }

  if (consultation.is_paid === true || consultation.paid === true) {
    return 'PAID';
  }
  if (PAID_PAYMENT_STATUSES.has(normalizeUpper(consultation.payment_status))) {
    return 'PAID';
  }
  if (
    consultation.require_payment === false ||
    normalizeUpper(consultation.payment_status) === 'NOT_REQUIRED'
  ) {
    return 'NOT_REQUIRED';
  }

  return (
    invoiceBillingStatus ||
    invoiceStatus ||
    consultation.payment_status ||
    (consultation.require_payment ? 'PENDING' : 'NOT_REQUIRED')
  );
};

const resolveConsultationIsPaid = ({ consultation = {}, invoice = null, payment = null } = {}) => {
  const paymentStatus = resolveConsultationPaymentStatus({ consultation, invoice, payment });
  return (
    consultation.is_paid === true ||
    consultation.paid === true ||
    PAID_PAYMENT_STATUSES.has(normalizeUpper(paymentStatus)) ||
    PAID_BILLING_STATUSES.has(normalizeUpper(invoice?.billing_status)) ||
    PAID_BILLING_STATUSES.has(normalizeUpper(invoice?.status))
  );
};

const buildResolvedConsultationBilling = ({ consultation = {}, invoice = null, payment = null } = {}) => {
  const paymentStatus = resolveConsultationPaymentStatus({ consultation, invoice, payment });
  const isPaid = resolveConsultationIsPaid({ consultation, invoice, payment });
  return {
    ...consultation,
    consultation_fee: resolveConsultationFeeAmount(consultation, invoice),
    paid_amount: resolveConsultationPaymentAmount({
      consultation,
      invoice,
      payment
    }),
    currency: consultation.currency || invoice?.currency || null,
    invoice_id: invoice?.human_friendly_id || consultation.invoice_id || null,
    payment_id: payment?.human_friendly_id || consultation.payment_id || null,
    payment_status: paymentStatus,
    is_paid: isPaid
  };
};

/**
 * Payment-due visits must always own an unpaid consultation invoice so Billing
 * Awaiting payment / All work items and Reception Payment gate stay aligned.
 * Creates or retains the invoice; throws when fee/billing cannot produce one.
 */
const ensureUnpaidConsultationInvoiceForPaymentDue = async (
  tx,
  {
    encounter,
    flow,
    catalogItemId = null,
    context = {},
    issuedAt = new Date(),
    paymentMode = null,
    coveragePlanId = null,
    insuranceCompanyId = null,
    payNow = null
  } = {}
) => {
  const consultation = { ...(flow.consultation || {}) };
  const isPaid =
    consultation.is_paid === true ||
    PAID_PAYMENT_STATUSES.has(normalizeUpper(consultation.payment_status));
  if (isPaid) {
    flow.consultation = consultation;
    return consultation;
  }
  if (consultation.invoice_id) {
    flow.consultation = consultation;
    return consultation;
  }

  const currency = normalizeCurrencyCode(consultation.currency, 'USD');
  const fee =
    resolveConsultationFeeAmount(consultation) ||
    normalizeDecimalString(consultation.consultation_fee, '0.00');
  const billingPayload = buildConsultationBillingPayload({
    consultationFee: fee,
    currency,
    paymentStatus: 'PENDING',
    catalogItemId,
    payNow,
    ...(paymentMode === 'INSURANCE' ? { paymentMode } : {})
  });
  if (!billingPayload) {
    throw new HttpError('errors.opd_flow.consultation_invoice_required', 400, [
      { field: 'consultation_fee' }
    ]);
  }

  const snapshot = await persistConsultationBilling(tx, {
    encounterId: encounter.id,
    billing: billingPayload,
    tenantId: encounter.tenant_id,
    facilityId: encounter.facility_id ?? null,
    patientId: encounter.patient_id,
    encounterDisplayId: encounter.human_friendly_id || null,
    catalogItemId,
    actorUserId: context.user_id || null,
    currency,
    issuedAt,
    description: 'Consultation fee',
    ...(paymentMode === 'INSURANCE'
      ? {
          paymentMode,
          coveragePlanId: coveragePlanId || null,
          insuranceCompanyId: insuranceCompanyId || null
        }
      : {})
  });
  if (!snapshot?.invoice_id) {
    throw new HttpError('errors.opd_flow.consultation_invoice_required', 500, [
      { field: 'invoice_id' }
    ]);
  }

  consultation.invoice_id = snapshot.invoice_id;
  consultation.billing = snapshot;
  consultation.payment_status = snapshot.payment_status || 'PENDING';
  consultation.require_payment = true;
  consultation.consultation_fee =
    consultation.consultation_fee || fee || snapshot.total_amount || null;
  consultation.currency = currency;
  flow.consultation = consultation;
  return consultation;
};

/**
 * Recompute an invoice's status/billing_status from ALL of its payments,
 * refunds, and adjustments (the same canonical billing math the billing
 * workspace uses), then mirror the result onto the consultation snapshot so the
 * OPD flow and the billing workspace stay synchronized. Handles partial
 * payments, multiple payments, refunds, and adjustments — not just the single
 * payment being recorded. Mutates `consultation` in place and returns the
 * refreshed invoice plus derived flags.
 */
const applyConsultationBillingSnapshot = async (
  tx,
  { invoiceId, payment = null, consultation, currency = null, paymentStatus = null } = {}
) => {
  const recalculated = await recalculateInvoiceStateTx(tx, invoiceId);
  const invoice =
    recalculated?.invoice || (await tx.invoice.findFirst({ where: { id: invoiceId, deleted_at: null } }));
  const financials = recalculated?.financials || computeInvoiceFinancials(invoice || {});
  const netPaidTotal = toDecimalNumber(financials.net_paid_total);
  const balanceDue = toDecimalNumber(financials.balance_due);
  const effectiveTotal = toDecimalNumber(financials.effective_total);
  const isPaid = balanceDue <= 0.009 && effectiveTotal > 0;
  const derivedStatus = isPaid
    ? 'PAID'
    : netPaidTotal > 0
      ? 'PARTIAL'
      : normalizeUpper(invoice?.billing_status) || normalizeUpper(paymentStatus) || 'ISSUED';

  consultation.invoice_id = invoice?.id || invoiceId || consultation.invoice_id || null;
  if (payment?.id) {
    consultation.payment_id = payment.id;
  }
  consultation.payment_status = derivedStatus;
  consultation.is_paid = isPaid;
  consultation.paid_amount = netPaidTotal > 0 ? netPaidTotal.toFixed(2) : null;
  consultation.balance_due = balanceDue > 0 ? balanceDue.toFixed(2) : '0.00';
  consultation.paid_at =
    isPaid && payment?.paid_at ? payment.paid_at.toISOString() : consultation.paid_at || null;
  if (currency) {
    consultation.currency = currency;
  }

  return { invoice, financials, isPaid, netPaidTotal, balanceDue };
};

const enrichConsultationBillingForListItems = async (items = []) => {
  const invoiceIdentifiers = uniqueNormalizedIdentifiers(items.map((item) => item?.flow?.consultation?.invoice_id));
  const paymentIdentifiers = uniqueNormalizedIdentifiers(items.map((item) => item?.flow?.consultation?.payment_id));

  if (invoiceIdentifiers.length === 0 && paymentIdentifiers.length === 0) {
    return items;
  }

  const [invoices, payments] = await Promise.all([
    invoiceIdentifiers.length > 0 && typeof prisma.invoice?.findMany === 'function'
      ? prisma.invoice.findMany({
          where: {
            deleted_at: null,
            OR: [
              { id: { in: invoiceIdentifiers } },
              {
                human_friendly_id: {
                  in: invoiceIdentifiers.flatMap(lookupIdentifierKeys)
                }
              }
            ]
          },
          include: {
            payments: {
              where: { deleted_at: null },
              orderBy: { created_at: 'desc' }
            }
          }
        })
      : [],
    paymentIdentifiers.length > 0 && typeof prisma.payment?.findMany === 'function'
      ? prisma.payment.findMany({
          where: {
            deleted_at: null,
            OR: [
              { id: { in: paymentIdentifiers } },
              {
                human_friendly_id: {
                  in: paymentIdentifiers.flatMap(lookupIdentifierKeys)
                }
              }
            ]
          },
          include: {
            invoice: {
              include: {
                payments: {
                  where: { deleted_at: null },
                  orderBy: { created_at: 'desc' }
                }
              }
            }
          }
        })
      : []
  ]);

  const invoiceByIdentifier = new Map();
  for (const invoice of invoices) {
    setLookupRecord(invoiceByIdentifier, invoice?.id, invoice);
    setLookupRecord(invoiceByIdentifier, invoice?.human_friendly_id, invoice);
  }

  const paymentByIdentifier = new Map();
  for (const payment of payments) {
    setLookupRecord(paymentByIdentifier, payment?.id, payment);
    setLookupRecord(paymentByIdentifier, payment?.human_friendly_id, payment);
  }

  return items.map((item) => {
    const flow = item?.flow || null;
    const consultation = flow?.consultation || {};
    const payment = getLookupRecord(paymentByIdentifier, consultation.payment_id);
    const invoice = getLookupRecord(invoiceByIdentifier, consultation.invoice_id) || payment?.invoice || null;
    if (
      !flow ||
      (!invoice && !payment && !consultation.paid_amount && !consultation.payment_amount && !consultation.amount_paid)
    ) {
      return item;
    }

    return {
      ...item,
      flow: {
        ...flow,
        consultation: buildResolvedConsultationBilling({
          consultation,
          invoice,
          payment
        })
      }
    };
  });
};

const resolveCurrencyFromExtension = (extensionJson) => {
  if (!extensionJson || typeof extensionJson !== 'object' || Array.isArray(extensionJson)) return null;

  const directCandidates = [extensionJson.currency, extensionJson.default_currency, extensionJson.defaultCurrency];
  const nestedCandidates = [
    extensionJson.settings?.currency,
    extensionJson.settings?.default_currency,
    extensionJson.settings?.defaultCurrency,
    extensionJson.billing?.currency,
    extensionJson.billing?.default_currency,
    extensionJson.billing?.defaultCurrency,
    extensionJson.preferences?.currency,
    extensionJson.preferences?.default_currency,
    extensionJson.preferences?.defaultCurrency
  ];

  const matched = [...directCandidates, ...nestedCandidates].find(
    (candidate) => typeof candidate === 'string' && candidate.trim()
  );

  return normalizeCurrencyCode(matched, null);
};

const resolveDefaultCurrency = async (tx, tenantId, facilityId = null) => {
  let facilityCurrency = null;
  if (facilityId && tx?.facility?.findFirst) {
    const facility = await tx.facility.findFirst({
      where: { id: facilityId, deleted_at: null },
      select: { extension_json: true }
    });
    facilityCurrency = resolveCurrencyFromExtension(facility?.extension_json);
  }

  if (facilityCurrency) return facilityCurrency;

  if (tenantId && tx?.tenant?.findFirst) {
    const tenant = await tx.tenant.findFirst({
      where: { id: tenantId, deleted_at: null },
      select: { extension_json: true }
    });
    const tenantCurrency = resolveCurrencyFromExtension(tenant?.extension_json);
    if (tenantCurrency) return tenantCurrency;
  }

  return 'UGX';
};

const resolveStandardConsultationFeeFromExtension = (extensionJson) => {
  if (!extensionJson || typeof extensionJson !== 'object' || Array.isArray(extensionJson)) {
    return {
      consultationFee: null,
      consultationCurrency: null
    };
  }

  const billing = extensionJson.billing || {};
  const feeCandidates = [
    billing.standard_consultation_fee,
    billing.standardConsultationFee,
    billing.default_consultation_fee,
    billing.defaultConsultationFee
  ];
  const currencyCandidates = [
    billing.standard_consultation_currency,
    billing.standardConsultationCurrency,
    billing.default_consultation_currency,
    billing.defaultConsultationCurrency
  ];
  const matchedFee = feeCandidates.find(
    (candidate) => candidate !== null && candidate !== undefined && String(candidate).trim()
  );
  const matchedCurrency = currencyCandidates.find(
    (candidate) => typeof candidate === 'string' && candidate.trim()
  );

  return {
    consultationFee: normalizeDecimalString(matchedFee, null),
    consultationCurrency: normalizeCurrencyCode(matchedCurrency, null)
  };
};

const resolveStandardConsultationFee = async (tx, tenantId, facilityId = null) => {
  if (facilityId && tx?.facility?.findFirst) {
    const facility = await tx.facility.findFirst({
      where: { id: facilityId, deleted_at: null },
      select: { extension_json: true }
    });
    const facilityDefaults = resolveStandardConsultationFeeFromExtension(facility?.extension_json);
    if (facilityDefaults.consultationFee) {
      return facilityDefaults;
    }
  }

  if (tenantId && tx?.tenant?.findFirst) {
    const tenant = await tx.tenant.findFirst({
      where: { id: tenantId, deleted_at: null },
      select: { extension_json: true }
    });
    return resolveStandardConsultationFeeFromExtension(tenant?.extension_json);
  }

  return {
    consultationFee: null,
    consultationCurrency: null
  };
};

const resolveConsultationFeeDefaults = async (
  tx,
  { provider = null, tenantId = null, facilityId = null } = {}
) => {
  const providerDefaults = resolveProviderConsultationDefaults(provider);
  const defaultCurrency = await resolveDefaultCurrency(tx, tenantId, facilityId);

  if (providerDefaults.consultationFee) {
    return {
      consultationFee: providerDefaults.consultationFee,
      consultationCurrency: providerDefaults.consultationCurrency || defaultCurrency
    };
  }

  const standardDefaults = await resolveStandardConsultationFee(tx, tenantId, facilityId);
  if (standardDefaults.consultationFee) {
    return {
      consultationFee: standardDefaults.consultationFee,
      consultationCurrency: standardDefaults.consultationCurrency || defaultCurrency
    };
  }

  return {
    consultationFee: null,
    consultationCurrency: defaultCurrency
  };
};

const resolveProviderConsultationDefaults = (provider) => {
  const profile = provider?.staff_profile || null;
  if (!profile || profile.deleted_at) {
    return {
      consultationFee: null,
      consultationCurrency: null
    };
  }

  const practitionerType = normalizeIdentifier(profile.practitioner_type).toUpperCase();
  if (!CONSULTATION_FEE_PRACTITIONER_TYPES.has(practitionerType)) {
    return {
      consultationFee: null,
      consultationCurrency: null
    };
  }

  return {
    consultationFee: normalizeDecimalString(profile.consultation_fee, null),
    consultationCurrency: normalizeCurrencyCode(profile.consultation_currency, null)
  };
};

const toFiniteNumber = (value) => {
  if (value === null || value === undefined) return null;
  if (typeof value === 'number') {
    return Number.isFinite(value) ? value : null;
  }
  if (typeof value === 'string') {
    const parsed = Number(value.trim());
    return Number.isFinite(parsed) ? parsed : null;
  }
  if (typeof value?.toNumber === 'function') {
    const parsed = value.toNumber();
    return Number.isFinite(parsed) ? parsed : null;
  }
  if (typeof value?.toString === 'function') {
    const parsed = Number(value.toString());
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
};

const roundToTwo = (value) => {
  if (!Number.isFinite(value)) return null;
  return Math.round(value * 100) / 100;
};

const formatBloodPressureValueComponent = (value) => {
  const rounded = roundToTwo(value);
  if (!Number.isFinite(rounded)) return '';
  return Number.isInteger(rounded) ? String(rounded) : String(rounded);
};

const parseLegacyBloodPressureValue = (value) => {
  const match = String(value || '')
    .trim()
    .match(BLOOD_PRESSURE_VALUE_REGEX);
  if (!match) return null;

  const systolic = roundToTwo(toFiniteNumber(match[1]));
  const diastolic = roundToTwo(toFiniteNumber(match[2]));

  if (!Number.isFinite(systolic) || !Number.isFinite(diastolic)) {
    return null;
  }

  return { systolic, diastolic };
};

const computeMeanArterialPressure = (systolic, diastolic) => {
  if (!Number.isFinite(systolic) || !Number.isFinite(diastolic)) return null;
  return roundToTwo((systolic + 2 * diastolic) / 3);
};

const normalizeBloodPressureVital = (vital) => {
  const parsedLegacy = parseLegacyBloodPressureValue(vital.value);
  const systolic = roundToTwo(toFiniteNumber(vital.systolic_value)) ?? parsedLegacy?.systolic ?? null;
  const diastolic = roundToTwo(toFiniteNumber(vital.diastolic_value)) ?? parsedLegacy?.diastolic ?? null;

  if (!Number.isFinite(systolic) || !Number.isFinite(diastolic)) {
    throw new HttpError('errors.validation.required', 400, [{ field: 'systolic_value' }, { field: 'diastolic_value' }]);
  }

  const mapValue = roundToTwo(toFiniteNumber(vital.map_value)) ?? computeMeanArterialPressure(systolic, diastolic);
  const canonicalValue = `${formatBloodPressureValueComponent(systolic)}/${formatBloodPressureValueComponent(diastolic)}`;

  return {
    value: canonicalValue,
    systolic_value: systolic,
    diastolic_value: diastolic,
    map_value: mapValue
  };
};

const normalizeVitalForPersistence = (vital) => {
  const vitalType = String(vital?.vital_type || '')
    .trim()
    .toUpperCase();
  if (vitalType === 'BLOOD_PRESSURE') {
    const normalizedBp = normalizeBloodPressureVital(vital);
    return {
      vital_type: vitalType,
      value: normalizedBp.value,
      systolic_value: normalizedBp.systolic_value,
      diastolic_value: normalizedBp.diastolic_value,
      map_value: normalizedBp.map_value
    };
  }

  return {
    vital_type: vitalType,
    value: String(vital?.value || '').trim(),
    systolic_value: null,
    diastolic_value: null,
    map_value: null
  };
};

const deriveArrivalMode = (data, appointment) => {
  if (data.arrival_mode) return data.arrival_mode;
  if (data.emergency) return 'EMERGENCY';
  if (appointment || data.appointment_id) return 'ONLINE_APPOINTMENT';
  return 'WALK_IN';
};

const mapTriageLevel = (triageLevel) => {
  if (!triageLevel) return null;
  return TRIAGE_ALIAS_MAP[triageLevel] || null;
};

const TRIAGE_PRIORITY_RANK = Object.freeze({
  LEVEL_1: 0,
  LEVEL_2: 1,
  LEVEL_3: 2,
  LEVEL_4: 3,
  LEVEL_5: 4
});

const resolveTriagePriorityRank = (triageLevel) => {
  const mapped = mapTriageLevel(triageLevel);
  if (!mapped) return 99;
  return Number.isInteger(TRIAGE_PRIORITY_RANK[mapped]) ? TRIAGE_PRIORITY_RANK[mapped] : 99;
};

const toTimestamp = (value) => {
  const parsed = new Date(value || '');
  if (Number.isNaN(parsed.getTime())) return Number.MAX_SAFE_INTEGER;
  return parsed.getTime();
};

const resolveEmergencyQueueTimestamp = (item) => {
  const flow = item?.flow || {};
  const encounter = item?.encounter || {};
  return toTimestamp(flow.queued_at || encounter.started_at || encounter.created_at);
};

const enrichEmergencyQueueUrgency = async (items = []) => {
  if (!Array.isArray(items) || items.length === 0) return items;
  if (!prisma?.triage_assessment?.findMany) return items;

  const emergencyCaseIds = Array.from(
    new Set(items.map((item) => normalizeIdentifier(item?.flow?.emergency_case_id)).filter(Boolean))
  );

  if (emergencyCaseIds.length === 0) {
    return items.map((item) => ({
      ...item,
      flow: {
        ...(item?.flow || {}),
        triage_level: null,
        triage_priority_rank: 99
      }
    }));
  }

  const triageRows = await prisma.triage_assessment.findMany({
    where: {
      deleted_at: null,
      emergency_case_id: { in: emergencyCaseIds }
    },
    select: {
      emergency_case_id: true,
      triage_level: true,
      created_at: true
    },
    orderBy: [{ created_at: 'desc' }]
  });

  const triageByEmergencyCaseId = new Map();
  for (const row of triageRows || []) {
    const emergencyCaseId = normalizeIdentifier(row?.emergency_case_id);
    if (!emergencyCaseId || triageByEmergencyCaseId.has(emergencyCaseId)) continue;
    triageByEmergencyCaseId.set(emergencyCaseId, mapTriageLevel(row?.triage_level));
  }

  return items.map((item) => {
    const flow = item?.flow || {};
    const emergencyCaseId = normalizeIdentifier(flow?.emergency_case_id);
    const triageLevel = triageByEmergencyCaseId.get(emergencyCaseId) || null;
    return {
      ...item,
      flow: {
        ...flow,
        triage_level: triageLevel,
        triage_priority_rank: resolveTriagePriorityRank(triageLevel)
      }
    };
  });
};

const sortEmergencyQueueItems = (items = []) =>
  [...items].sort((left, right) => {
    const leftRank = resolveTriagePriorityRank(left?.flow?.triage_level);
    const rightRank = resolveTriagePriorityRank(right?.flow?.triage_level);
    if (leftRank !== rightRank) return leftRank - rightRank;

    const leftQueuedAt = resolveEmergencyQueueTimestamp(left);
    const rightQueuedAt = resolveEmergencyQueueTimestamp(right);
    if (leftQueuedAt !== rightQueuedAt) return leftQueuedAt - rightQueuedAt;

    const leftStartedAt = toTimestamp(left?.encounter?.started_at);
    const rightStartedAt = toTimestamp(right?.encounter?.started_at);
    if (leftStartedAt !== rightStartedAt) return leftStartedAt - rightStartedAt;

    const leftId = normalizeIdentifier(left?.encounter?.id);
    const rightId = normalizeIdentifier(right?.encounter?.id);
    return leftId.localeCompare(rightId);
  });

const hasOpdFlowState = (encounter) => Boolean(encounter?.extension_json?.opd_flow);

const buildMinimalOpdFlowShell = ({
  arrivalMode = 'WALK_IN',
  stage = STAGES.WAITING_VITALS
} = {}) => ({
  version: 1,
  arrival_mode: arrivalMode,
  stage,
  next_step: getNextStep(stage),
  consultation: {
    require_payment: false,
    consultation_fee: null,
    currency: null,
    invoice_id: null,
    payment_id: null,
    payment_status: 'NOT_REQUIRED',
    is_paid: false,
    paid_amount: null,
    paid_at: null
  },
  appointment_id: null,
  visit_queue_id: null,
  emergency_case_id: null,
  triage_assessment_id: null,
  lab_order_ids: [],
  radiology_order_ids: [],
  pharmacy_order_id: null,
  admission_id: null,
  review_completed: false,
  timeline: []
});

const getOpdFlowState = (encounter) => {
  const opdFlow = encounter?.extension_json?.opd_flow;
  if (!opdFlow) {
    throw new HttpError('errors.opd_flow.not_found', 404);
  }
  return opdFlow;
};

const getOpdFlowStateOrShell = (encounter, shellOptions) => {
  if (hasOpdFlowState(encounter)) {
    return getOpdFlowState(encounter);
  }
  return buildMinimalOpdFlowShell(shellOptions);
};

const getNextStep = (stage) => NEXT_STEP_BY_STAGE[stage] || null;

const appendTimelineEvent = (flow, event, context = {}, details = {}, at = new Date()) => {
  if (!Array.isArray(flow.timeline)) {
    flow.timeline = [];
  }

  flow.timeline.push({
    event,
    at: at.toISOString(),
    by_user_id: context.user_id || null,
    details
  });
};

const setFlowStage = (flow, stage) => {
  flow.stage = stage;
  flow.next_step = getNextStep(stage);
};

const resolvePostVitalsStage = (encounter) =>
  normalizeIdentifier(encounter?.provider_user_id)
    ? STAGES.WAITING_DOCTOR_REVIEW
    : STAGES.WAITING_DOCTOR_ASSIGNMENT;

const normalizeStatus = (value) => normalizeIdentifier(value).toUpperCase();

const titleCaseWords = (value) =>
  String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[_-]+/g, ' ')
    .replace(/\b\w/g, (letter) => letter.toUpperCase());

const buildStaffDisplayName = (user) => {
  const profile = user?.profile || {};
  const names = [profile.first_name, profile.middle_name, profile.last_name]
    .map((part) => normalizeIdentifier(part))
    .filter(Boolean);
  return names.join(' ') || normalizeIdentifier(user?.email) || normalizeIdentifier(user?.phone) || null;
};

const staffRoleNames = (user) => {
  const roles = Array.isArray(user?.roles) ? user.roles : [];
  return roles
    .map((entry) => normalizeRoleName(entry?.role?.name || entry?.name || ''))
    .filter(Boolean);
};

const staffRoleText = (user) => {
  const normalizedRoles = new Set(staffRoleNames(user));
  const practitionerType = normalizeStatus(user?.staff_profile?.practitioner_type);
  const position = normalizeStatus(user?.staff_profile?.position);
  const combined = `${practitionerType} ${position}`;

  if (normalizedRoles.has(ROLES.DOCTOR) || /DOCTOR|PHYSICIAN|MEDICAL_OFFICER|CLINICAL_OFFICER|CLINICIAN|CONSULTANT/.test(combined)) {
    return 'Doctor';
  }
  if (normalizedRoles.has(ROLES.NURSE) || /NURSE|MIDWIFE/.test(combined)) return 'Nurse';
  if (normalizedRoles.has(ROLES.LAB_TECH) || /LAB|LABORATORY/.test(combined)) return 'Lab Technician';
  if (/RADIOLOGIST/.test(combined)) return 'Radiologist';
  if (normalizedRoles.has(ROLES.RADIOLOGY_TECH) || /RADIOLOGY|IMAGING|SONOGRAPHER|XRAY|X_RAY/.test(combined)) return 'Radiology Technician';
  if (normalizedRoles.has(ROLES.PHARMACIST) || /PHARMAC/.test(combined)) return 'Pharmacist';
  return titleCaseWords(user?.staff_profile?.position || user?.staff_profile?.practitioner_type) || 'Assigned staff';
};

const buildAssignedStaff = (user) => {
  const displayName = buildStaffDisplayName(user);
  const role = displayName ? staffRoleText(user) : null;
  return {
    id: user?.id || null,
    public_id: user?.human_friendly_id || user?.id || null,
    display_name: displayName,
    role,
    type: user?.staff_profile?.practitioner_type || null,
    position: user?.staff_profile?.position || null,
    label: displayName ? `${role || 'Assigned staff'}: ${displayName}` : null
  };
};

const isDoctorAssignable = (user) => {
  if (!user) return false;
  const normalizedRoles = new Set(staffRoleNames(user));
  if (normalizedRoles.has(ROLES.DOCTOR) || normalizedRoles.has('SPECIALIST')) return true;
  const practitionerType = normalizeStatus(user?.staff_profile?.practitioner_type);
  if (practitionerType && CONSULTATION_FEE_PRACTITIONER_TYPES.has(practitionerType)) return true;
  const position = normalizeStatus(user?.staff_profile?.position);
  return /DOCTOR|PHYSICIAN|MEDICAL_OFFICER|CLINICAL_OFFICER|CLINICIAN|CONSULTANT/.test(
    `${practitionerType} ${position}`
  );
};

const ensureDoctorAssignable = (provider) => {
  if (!isDoctorAssignable(provider)) {
    throw new HttpError('errors.opd_flow.provider_not_doctor', 400, [{ field: 'provider_user_id' }]);
  }
};

const hasCompletedConsultationPayment = (flow) => {
  const consultation = flow?.consultation || {};
  if (consultation.require_payment === false || normalizeStatus(consultation.payment_status) === 'NOT_REQUIRED') return true;
  if (consultation.is_paid === true) return true;
  return PAID_PAYMENT_STATUSES.has(normalizeStatus(consultation.payment_status));
};

const hasRecordedVitals = (encounter) =>
  Array.isArray(encounter?.vital_signs) && encounter.vital_signs.some((item) => !item.deleted_at);

const activeItems = (items) => (Array.isArray(items) ? items.filter((item) => !item?.deleted_at) : []);

const { resolveLabState } = require('@services/opd-flow/opd-diagnostics-state');
const resolveRadiologyState = (orders = []) => {
  const activeOrders = activeItems(orders).filter((order) => normalizeStatus(order.status) !== 'CANCELLED');
  if (!activeOrders.length) return { code: null, pending: false, ready: false };
  const hasFinalReport = activeOrders.some((order) =>
    activeItems(order.results).some((result) => ['FINAL', 'AMENDED'].includes(normalizeStatus(result.status)))
  );
  const hasPerformedStudy = activeOrders.some((order) => activeItems(order.imaging_studies).some((study) => Boolean(study.performed_at)));
  const hasIncomplete = activeOrders.some((order) => normalizeStatus(order.status) !== 'COMPLETED' || !activeItems(order.results).length);
  return {
    code: hasFinalReport ? 'REPORT_READY' : hasPerformedStudy ? 'REPORT_PENDING' : 'IMAGING_PENDING',
    pending: hasIncomplete && !hasFinalReport,
    ready: hasFinalReport || activeOrders.every((order) => normalizeStatus(order.status) === 'COMPLETED')
  };
};

const resolvePharmacyState = (orders = []) => {
  const activeOrders = activeItems(orders).filter((order) => normalizeStatus(order.status) !== 'CANCELLED');
  if (!activeOrders.length) return { code: null, pending: false, ready: false };
  const hasPending = activeOrders.some((order) =>
    ['ORDERED', 'PARTIALLY_DISPENSED'].includes(normalizeStatus(order.status)) ||
    activeItems(order.items).some((item) => normalizeStatus(item.status) !== 'COMPLETED') ||
    activeItems(order.items).some((item) => activeItems(item.dispense_logs).some((log) => normalizeStatus(log.status) === 'PENDING'))
  );
  return {
    code: hasPending ? 'PHARMACY_PENDING' : 'MEDICINES_DISPENSED',
    pending: hasPending,
    ready: !hasPending || activeOrders.some((order) => normalizeStatus(order.status) === 'DISPENSED')
  };
};

const hasConfirmedAdmission = (encounter, flow) => {
  const admissions = activeItems(encounter?.admissions);
  const admission = admissions.find((item) => item.id === flow?.admission_id) || admissions[0] || null;
  if (!admission || normalizeStatus(admission.status) !== 'ADMITTED') return false;
  return activeItems(admission.bed_assignments).some((assignment) => !assignment.released_at);
};

const workflowStageIndex = (stage) => WORKFLOW_STAGE_ORDER.indexOf(stage);

const hasDurableClinicalOrders = (encounter, flow) => {
  const labIds = Array.isArray(flow?.lab_order_ids)
    ? flow.lab_order_ids.map(normalizeIdentifier).filter(Boolean)
    : [];
  const radiologyIds = Array.isArray(flow?.radiology_order_ids)
    ? flow.radiology_order_ids.map(normalizeIdentifier).filter(Boolean)
    : [];
  if (labIds.length || radiologyIds.length || normalizeIdentifier(flow?.pharmacy_order_id)) {
    return true;
  }
  const isActiveOrder = (order) =>
    !order?.deleted_at && normalizeStatus(order?.status) !== 'CANCELLED';
  return (
    activeItems(encounter?.lab_orders).some(isActiveOrder) ||
    activeItems(encounter?.radiology_orders).some(isActiveOrder) ||
    activeItems(encounter?.pharmacy_orders).some(isActiveOrder)
  );
};

/**
 * Minimum workflow-stage index selectable for stage correction.
 * Recorded milestones raise the floor so staff cannot reverse past completed work.
 */
const resolveStageCorrectionMinIndex = (encounter, flow) => {
  let minIndex = 0;
  const bump = (stage) => {
    const index = workflowStageIndex(stage);
    if (index > minIndex) {
      minIndex = index;
    }
  };

  if (hasCompletedConsultationPayment(flow)) {
    bump(STAGES.WAITING_VITALS);
  }
  if (hasRecordedVitals(encounter)) {
    bump(STAGES.WAITING_DOCTOR_ASSIGNMENT);
  }
  if (normalizeIdentifier(encounter?.provider_user_id)) {
    bump(STAGES.WAITING_DOCTOR_REVIEW);
  }

  const hasOrders = hasDurableClinicalOrders(encounter, flow);
  if (flow?.review_completed || hasOrders) {
    bump(hasOrders ? STAGES.LAB_REQUESTED : STAGES.WAITING_DISPOSITION);
  }

  if (flow?.admission_id || flow?.admission_pending || flow?.disposition_decision) {
    bump(STAGES.WAITING_DISPOSITION);
  }
  if (hasConfirmedAdmission(encounter, flow) || flow?.stage === STAGES.ADMITTED) {
    bump(STAGES.ADMITTED);
  }

  return minIndex;
};

const isEligibleStageCorrectionTarget = (stageTo, encounter, flow) => {
  const toIndex = workflowStageIndex(stageTo);
  if (toIndex < 0) {
    return false;
  }
  return toIndex >= resolveStageCorrectionMinIndex(encounter, flow);
};

const STAGE_CORRECTION_ENCOUNTER_INCLUDE = {
  vital_signs: {
    where: { deleted_at: null },
    select: { id: true, deleted_at: true }
  },
  admissions: {
    where: { deleted_at: null },
    include: {
      bed_assignments: {
        where: { deleted_at: null },
        select: { id: true, released_at: true, deleted_at: true }
      }
    }
  },
  lab_orders: {
    where: { deleted_at: null },
    select: { id: true, status: true, deleted_at: true }
  },
  radiology_orders: {
    where: { deleted_at: null },
    select: { id: true, status: true, deleted_at: true }
  },
  pharmacy_orders: {
    where: { deleted_at: null },
    select: { id: true, status: true, deleted_at: true }
  }
};

const displayLabelByCode = (code, assignedStaff = null) => {
  if (code === 'WITH_DOCTOR' && assignedStaff?.display_name) return `${assignedStaff.role || 'Doctor'}: ${assignedStaff.display_name}`;
  return {
    PAYMENT_DUE: 'Payment due',
    VITALS_NEEDED: 'Vitals needed',
    DOCTOR_NEEDED: 'Doctor needed',
    WITH_DOCTOR: 'With doctor',
    LAB_PENDING: 'Lab pending',
    SAMPLE_PENDING: 'Sample pending',
    IN_LAB: 'In lab',
    RESULTS_READY: 'Results ready',
    IMAGING_PENDING: 'Imaging pending',
    REPORT_PENDING: 'Report pending',
    REPORT_READY: 'Report ready',
    PHARMACY_PENDING: 'Pharmacy pending',
    MEDICINES_DISPENSED: 'Medicines dispensed',
    DECISION_NEEDED: 'Decision needed',
    ADMISSION_PENDING: 'Admission pending',
    ADMITTED: 'Admitted',
    DISCHARGED: 'Discharged'
  }[code] || titleCaseWords(code || 'Updated');
};

const nextStepByDisplayCode = (code) => ({
  PAYMENT_DUE: 'PAY_CONSULTATION',
  VITALS_NEEDED: 'RECORD_VITALS',
  DOCTOR_NEEDED: 'ASSIGN_DOCTOR',
  WITH_DOCTOR: 'DOCTOR_REVIEW',
  LAB_PENDING: 'LAB_WORKSPACE',
  SAMPLE_PENDING: 'COLLECT_SAMPLE',
  IN_LAB: 'PROCESS_LAB',
  RESULTS_READY: 'REVIEW_RESULTS',
  IMAGING_PENDING: 'PERFORM_IMAGING',
  REPORT_PENDING: 'COMPLETE_IMAGING_REPORT',
  REPORT_READY: 'REVIEW_REPORT',
  PHARMACY_PENDING: 'DISPENSE_MEDICINE',
  MEDICINES_DISPENSED: 'DISPOSITION',
  DECISION_NEEDED: 'DISPOSITION',
  ADMISSION_PENDING: 'ADMISSION_HANDOFF',
  ADMITTED: null,
  DISCHARGED: null
}[code] ?? null);

const stageByDisplayCode = (code, currentStage = null) => ({
  PAYMENT_DUE: STAGES.WAITING_CONSULTATION_PAYMENT,
  VITALS_NEEDED: STAGES.WAITING_VITALS,
  DOCTOR_NEEDED: STAGES.WAITING_DOCTOR_ASSIGNMENT,
  WITH_DOCTOR: STAGES.WAITING_DOCTOR_REVIEW,
  LAB_PENDING: STAGES.LAB_REQUESTED,
  SAMPLE_PENDING: STAGES.LAB_REQUESTED,
  IN_LAB: STAGES.LAB_REQUESTED,
  RESULTS_READY: currentStage === STAGES.RADIOLOGY_REQUESTED || currentStage === STAGES.LAB_AND_RADIOLOGY_REQUESTED
    ? currentStage
    : STAGES.WAITING_DISPOSITION,
  IMAGING_PENDING: STAGES.RADIOLOGY_REQUESTED,
  REPORT_PENDING: STAGES.RADIOLOGY_REQUESTED,
  REPORT_READY: currentStage === STAGES.LAB_REQUESTED || currentStage === STAGES.LAB_AND_RADIOLOGY_REQUESTED
    ? currentStage
    : STAGES.WAITING_DISPOSITION,
  PHARMACY_PENDING: STAGES.PHARMACY_REQUESTED,
  MEDICINES_DISPENSED: STAGES.WAITING_DISPOSITION,
  DECISION_NEEDED: STAGES.WAITING_DISPOSITION,
  ADMISSION_PENDING: STAGES.WAITING_DISPOSITION,
  ADMITTED: STAGES.ADMITTED,
  DISCHARGED: STAGES.DISCHARGED
}[code] ?? currentStage ?? null);

const resolveOpdDisplayState = (encounter, flow = null) => {
  const currentFlow = flow || encounter?.extension_json?.opd_flow || {};
  const assignedStaff = buildAssignedStaff(encounter?.provider);
  const providerAssigned = Boolean(
    normalizeIdentifier(encounter?.provider_user_id) || assignedStaff.display_name
  );
  const labState = resolveLabState(encounter?.lab_orders);
  const radiologyState = resolveRadiologyState(encounter?.radiology_orders);
  const pharmacyState = resolvePharmacyState(encounter?.pharmacy_orders);
  const closedOrDischarged = normalizeStatus(encounter?.status) === 'CLOSED' || currentFlow.stage === STAGES.DISCHARGED;
  const admissionConfirmed = hasConfirmedAdmission(encounter, currentFlow);
  const admissionPending = Boolean(currentFlow.admission_pending || (currentFlow.admission_id && !admissionConfirmed));
  let code = null;

  if (closedOrDischarged) code = 'DISCHARGED';
  else if (admissionConfirmed || currentFlow.stage === STAGES.ADMITTED) code = 'ADMITTED';
  else if (admissionPending) code = 'ADMISSION_PENDING';
  else if (!hasCompletedConsultationPayment(currentFlow)) code = 'PAYMENT_DUE';
  else if (!hasRecordedVitals(encounter)) code = 'VITALS_NEEDED';
  else if (!providerAssigned) code = 'DOCTOR_NEEDED';
  else if (labState.pending) code = labState.code;
  else if (radiologyState.pending) code = radiologyState.code;
  else if (pharmacyState.pending) code = pharmacyState.code;
  else if (labState.ready && ['LAB_REQUESTED', 'LAB_AND_RADIOLOGY_REQUESTED'].includes(currentFlow.stage)) code = 'RESULTS_READY';
  else if (radiologyState.ready && ['RADIOLOGY_REQUESTED', 'LAB_AND_RADIOLOGY_REQUESTED'].includes(currentFlow.stage)) code = 'REPORT_READY';
  else if (pharmacyState.ready && currentFlow.stage === STAGES.PHARMACY_REQUESTED) code = 'MEDICINES_DISPENSED';
  else if (currentFlow.review_completed || currentFlow.stage === STAGES.WAITING_DISPOSITION) code = 'DECISION_NEEDED';
  else if (providerAssigned) code = 'WITH_DOCTOR';
  else code = 'DOCTOR_NEEDED';

  const resolvedStage = stageByDisplayCode(code, currentFlow.stage);
  const nextStep = nextStepByDisplayCode(code) || getNextStep(resolvedStage);
  return {
    stage: resolvedStage,
    next_step: nextStep,
    display_code: code,
    display_status: displayLabelByCode(code, assignedStaff),
    display_next_step: nextStep,
    assigned_staff: assignedStaff.display_name ? assignedStaff : null,
    assigned_staff_role: assignedStaff.role || null,
    assigned_staff_type: assignedStaff.type || null,
    // Prefer a real staff label. When a provider is assigned but the relation was
    // not loaded, avoid the misleading "Assigned staff unknown" placeholder used
    // by clients as a display value.
    assigned_staff_label:
      assignedStaff.label ||
      (providerAssigned
        ? code === 'WITH_DOCTOR'
          ? 'With doctor'
          : 'Doctor assigned'
        : code === 'DOCTOR_NEEDED'
          ? 'Doctor needed'
          : code === 'WITH_DOCTOR'
            ? 'With doctor'
            : null),
    lab_state: labState,
    radiology_state: radiologyState,
    pharmacy_state: pharmacyState,
    admission_state: admissionConfirmed ? 'ADMITTED' : admissionPending ? 'PENDING' : null
  };
};

const attachResolvedDisplayToFlow = (encounter, flow) => {
  const resolved = resolveOpdDisplayState(encounter, flow);
  return {
    ...flow,
    stage: resolved.stage || flow?.stage || null,
    next_step: resolved.next_step || flow?.next_step || null,
    display_code: resolved.display_code,
    display_status: resolved.display_status,
    display_next_step: resolved.display_next_step,
    assigned_staff: resolved.assigned_staff,
    assigned_staff_role: resolved.assigned_staff_role,
    assigned_staff_type: resolved.assigned_staff_type,
    assigned_staff_label: resolved.assigned_staff_label,
    lab_state: resolved.lab_state,
    radiology_state: resolved.radiology_state,
    pharmacy_state: resolved.pharmacy_state,
    admission_state: resolved.admission_state
  };
};

const applyResolvedStageToFlow = (encounter, flow) => {
  const resolved = resolveOpdDisplayState(encounter, flow);
  flow.stage = resolved.stage || flow.stage;
  flow.next_step = resolved.next_step || getNextStep(flow.stage);
  flow.display_code = resolved.display_code;
  flow.display_status = resolved.display_status;
  flow.display_next_step = resolved.display_next_step;
  flow.assigned_staff_role = resolved.assigned_staff_role;
  flow.assigned_staff_type = resolved.assigned_staff_type;
  flow.assigned_staff_label = resolved.assigned_staff_label;
  return resolved;
};

const ensureNonTerminalStage = (flow) => {
  if (TERMINAL_STAGES.has(flow.stage)) {
    throw new HttpError('errors.opd_flow.already_terminal', 400);
  }
};

const buildEncounterSearchTokenClause = (token) => {
  const term = String(token || '').trim();
  const upper = term.toUpperCase();

  return {
    OR: [
      { human_friendly_id: { contains: upper } },
      { patient: { first_name: { contains: term } } },
      { patient: { last_name: { contains: term } } },
      { patient: { human_friendly_id: { contains: upper } } },
      {
        patient: {
          identifiers: {
            some: {
              deleted_at: null,
              OR: [
                { human_friendly_id: { contains: upper } },
                { identifier_type: { contains: term } },
                { identifier_value: { contains: term } }
              ]
            }
          }
        }
      },
      {
        patient: {
          contacts: {
            some: {
              deleted_at: null,
              OR: [{ human_friendly_id: { contains: upper } }, { value: { contains: term } }]
            }
          }
        }
      },
      {
        patient: {
          guardians: {
            some: {
              deleted_at: null,
              OR: [
                { human_friendly_id: { contains: upper } },
                { name: { contains: term } },
                { relationship: { contains: term } },
                { phone: { contains: term } },
                { email: { contains: term } }
              ]
            }
          }
        }
      },
      { provider: { email: { contains: term } } },
      { provider: { phone: { contains: term } } },
      { provider: { human_friendly_id: { contains: upper } } },
      { provider: { profile: { first_name: { contains: term } } } },
      { provider: { profile: { last_name: { contains: term } } } },
      { provider: { profile: { middle_name: { contains: term } } } },
      { provider: { staff_profile: { staff_number: { contains: term } } } },
      {
        provider: { staff_profile: { practitioner_type: { contains: upper } } }
      },
      { provider: { staff_profile: { position: { contains: term } } } }
    ]
  };
};

const buildEncounterWhereClause = (filters = {}) => {
  const where = {
    encounter_type: 'OPD'
  };
  const andClauses = [];

  if (filters.tenant_id) where.tenant_id = filters.tenant_id;
  if (filters.facility_id) where.facility_id = filters.facility_id;
  if (filters.patient_id) where.patient_id = filters.patient_id;
  if (filters.provider_user_id) where.provider_user_id = filters.provider_user_id;
  if (filters.encounter_type) where.encounter_type = filters.encounter_type;
  if (filters.stage) {
    where.extension_json = buildOpdFlowJsonFilter(OPD_FLOW_STAGE_JSON_PATH, filters.stage);
  } else {
    andClauses.push(buildOpdFlowStagePresenceClause());
  }

  const requestedStage = normalizeIdentifier(filters.stage).toUpperCase();
  if (!TERMINAL_STAGES.has(requestedStage)) {
    andClauses.push({ status: 'OPEN' });
  }

  const queueScope = String(filters.queue_scope || QUEUE_SCOPES.ALL)
    .trim()
    .toUpperCase();
  if (queueScope === QUEUE_SCOPES.ASSIGNED) {
    andClauses.push({ status: 'OPEN' });
    if (!filters.provider_user_id) {
      andClauses.push({ provider_user_id: { not: null } });
    }
  } else if (queueScope === QUEUE_SCOPES.WAITING) {
    andClauses.push(
      { status: 'OPEN' },
      { provider_user_id: null },
      {
        OR: WAITING_QUEUE_STAGES.map((stage) => ({
          extension_json: buildOpdFlowJsonFilter(OPD_FLOW_STAGE_JSON_PATH, stage)
        }))
      }
    );
  }

  const searchTokens = normalizeSearchTokens(filters.search);
  if (searchTokens.length > 0) {
    andClauses.push(...searchTokens.map(buildEncounterSearchTokenClause));
  }

  if (andClauses.length > 0) {
    where.AND = andClauses;
  }

  return where;
};

const resolveLegacyRoute = async (resource, id) => {
  const normalizedResource = normalizeIdentifier(resource).toLowerCase();
  const config = LEGACY_ROUTE_CONFIG[normalizedResource];
  if (!config) {
    throw new HttpError('errors.opd_flow.not_found', 404);
  }

  const normalizedIdentifier = normalizeIdentifier(id);
  if (!normalizedIdentifier) {
    throw new HttpError('errors.opd_flow.not_found', 404);
  }

  const delegate = prisma?.[config.model];
  if (!delegate || typeof delegate.findFirst !== 'function') {
    throw new HttpError('errors.opd_flow.not_found', 404);
  }

  const resolvedResource = await delegate.findFirst({
    where: {
      deleted_at: null,
      OR: isUuid(normalizedIdentifier)
        ? [{ id: normalizedIdentifier }]
        : [{ human_friendly_id: normalizedIdentifier.toUpperCase() }]
    },
    select: {
      id: true,
      human_friendly_id: true,
      ...(config.emergencyCaseField && config.emergencyCaseField !== 'id' ? { [config.emergencyCaseField]: true } : {}),
      ...(config.ambulanceField && config.ambulanceField !== 'id' ? { [config.ambulanceField]: true } : {})
    }
  });

  if (!resolvedResource) {
    throw new HttpError('errors.opd_flow.not_found', 404);
  }

  const emergencyCaseInternalId = config.emergencyCaseField
    ? config.emergencyCaseField === 'id'
      ? resolvedResource.id
      : resolvedResource[config.emergencyCaseField] || null
    : null;
  const ambulanceInternalId = config.ambulanceField
    ? config.ambulanceField === 'id'
      ? resolvedResource.id
      : resolvedResource[config.ambulanceField] || null
    : null;

  const [emergencyCase, ambulance] = await Promise.all([
    emergencyCaseInternalId
      ? prisma.emergency_case.findFirst({
          where: {
            id: emergencyCaseInternalId,
            deleted_at: null
          },
          select: {
            id: true,
            human_friendly_id: true
          }
        })
      : null,
    ambulanceInternalId
      ? prisma.ambulance.findFirst({
          where: {
            id: ambulanceInternalId,
            deleted_at: null
          },
          select: {
            id: true,
            human_friendly_id: true
          }
        })
      : null
  ]);

  const encounter = emergencyCaseInternalId
    ? await prisma.encounter.findFirst({
        where: {
          deleted_at: null,
          encounter_type: 'EMERGENCY',
          extension_json: buildOpdFlowJsonFilter(OPD_FLOW_EMERGENCY_CASE_ID_JSON_PATH, emergencyCaseInternalId)
        },
        orderBy: {
          started_at: 'desc'
        },
        select: {
          id: true,
          human_friendly_id: true
        }
      })
    : null;

  return {
    encounter_id: toPublicIdentifier(encounter?.human_friendly_id || encounter?.id) || null,
    emergency_case_id:
      toPublicIdentifier(
        emergencyCase?.human_friendly_id ||
          (config.emergencyCaseField === 'id' ? resolvedResource.human_friendly_id : null)
      ) || null,
    ambulance_id:
      toPublicIdentifier(
        ambulance?.human_friendly_id || (config.ambulanceField === 'id' ? resolvedResource.human_friendly_id : null)
      ) || null,
    resource: normalizedResource,
    resource_id: toPublicIdentifier(resolvedResource.human_friendly_id || normalizedIdentifier) || null,
    panel: config.panel,
    action: config.action
  };
};

const getOpdFlowById = async (id) => {
  let result;
  try {
    result = await prisma.$transaction(async (tx) => {
      const encounter = await resolveEncounterByIdentifier(tx, id, {
        include: {
          tenant: true,
          facility: true,
          patient: true,
          provider: PROVIDER_INCLUDE,
          vital_signs: {
            where: { deleted_at: null },
            orderBy: { recorded_at: 'asc' }
          },
          clinical_notes: {
            where: { deleted_at: null },
            orderBy: { created_at: 'asc' }
          },
          diagnoses: {
            where: { deleted_at: null },
            orderBy: { created_at: 'asc' }
          },
          procedures: {
            where: { deleted_at: null },
            orderBy: { created_at: 'asc' }
          },
          care_plans: {
            where: { deleted_at: null },
            orderBy: { created_at: 'asc' }
          },
          alerts: {
            where: { deleted_at: null },
            orderBy: { created_at: 'desc' }
          },
          referrals: {
            where: { deleted_at: null },
            orderBy: { created_at: 'desc' }
          },
          follow_ups: {
            where: { deleted_at: null },
            orderBy: { scheduled_at: 'asc' }
          },
          admissions: {
            where: { deleted_at: null },
            orderBy: { created_at: 'desc' },
            include: {
              bed_assignments: {
                where: { deleted_at: null },
                orderBy: { assigned_at: 'desc' }
              }
            }
          },
          lab_orders: {
            where: { deleted_at: null },
            orderBy: { created_at: 'desc' },
            include: {
              items: {
                where: { deleted_at: null },
                include: {
                  results: { where: { deleted_at: null } }
                }
              },
              samples: { where: { deleted_at: null } }
            }
          },
          radiology_orders: {
            where: { deleted_at: null },
            orderBy: { created_at: 'desc' },
            include: {
              results: { where: { deleted_at: null } },
              imaging_studies: { where: { deleted_at: null } }
            }
          },
          pharmacy_orders: {
            where: { deleted_at: null },
            orderBy: { created_at: 'desc' },
            include: {
              items: {
                where: { deleted_at: null },
                include: { dispense_logs: { where: { deleted_at: null } } }
              }
            }
          }
        }
      });
      if (!encounter) {
        throw new HttpError('errors.opd_flow.not_found', 404);
      }

      const flow = getOpdFlowState(encounter);

      const [visitQueue, appointment, consultationInvoice, consultationPayment, emergencyCase, triageAssessment] =
        await Promise.all([
          flow.visit_queue_id
            ? tx.visit_queue.findFirst({
                where: { id: flow.visit_queue_id, deleted_at: null },
                include: {
                  provider: PROVIDER_INCLUDE,
                  facility: true,
                  appointment: true
                }
              })
            : null,
          flow.appointment_id
            ? tx.appointment.findFirst({
                where: { id: flow.appointment_id, deleted_at: null },
                include: { provider: PROVIDER_INCLUDE, facility: true }
              })
            : null,
          flow.consultation?.invoice_id
            ? tx.invoice.findFirst({
                where: { id: flow.consultation.invoice_id, deleted_at: null },
                include: {
                  payments: {
                    where: { deleted_at: null },
                    orderBy: { created_at: 'desc' }
                  }
                }
              })
            : null,
          flow.consultation?.payment_id
            ? tx.payment.findFirst({
                where: { id: flow.consultation.payment_id, deleted_at: null }
              })
            : null,
          flow.emergency_case_id
            ? tx.emergency_case.findFirst({
                where: { id: flow.emergency_case_id, deleted_at: null }
              })
            : null,
          flow.triage_assessment_id
            ? tx.triage_assessment.findFirst({
                where: { id: flow.triage_assessment_id, deleted_at: null }
              })
            : null
        ]);

      const resolvedAdmission =
        (Array.isArray(encounter.admissions)
          ? encounter.admissions.find((item) => item.id === flow.admission_id) || encounter.admissions[0]
          : null) || null;
      const resolvedPharmacyOrder =
        (Array.isArray(encounter.pharmacy_orders)
          ? encounter.pharmacy_orders.find((item) => item.id === flow.pharmacy_order_id) || encounter.pharmacy_orders[0]
          : null) || null;
      const consultation = flow.consultation || {};
      const resolvedConsultation = buildResolvedConsultationBilling({
        consultation,
        invoice: consultationInvoice,
        payment: consultationPayment
      });
      const resolvedDisplayFlow = attachResolvedDisplayToFlow(encounter, { ...flow, consultation: resolvedConsultation });
      const flowWithFriendlyIds = {
        ...resolvedDisplayFlow,
        consultation: resolvedConsultation,
        appointment_id: appointment?.human_friendly_id || flow.appointment_id || null,
        visit_queue_id: visitQueue?.human_friendly_id || flow.visit_queue_id || null,
        emergency_case_id: emergencyCase?.human_friendly_id || flow.emergency_case_id || null,
        triage_assessment_id: triageAssessment?.human_friendly_id || flow.triage_assessment_id || null,
        lab_order_ids: Array.isArray(encounter.lab_orders)
          ? encounter.lab_orders.map((entry) => entry.human_friendly_id).filter(Boolean)
          : [],
        radiology_order_ids: Array.isArray(encounter.radiology_orders)
          ? encounter.radiology_orders.map((entry) => entry.human_friendly_id).filter(Boolean)
          : [],
        pharmacy_order_id: resolvedPharmacyOrder?.human_friendly_id || null,
        admission_id: resolvedAdmission?.human_friendly_id || null
      };

      return {
        encounter,
        flow: flowWithFriendlyIds,
        visit_queue: visitQueue,
        appointment,
        consultation_invoice: consultationInvoice,
        consultation_payment: consultationPayment,
        emergency_case: emergencyCase,
        triage_assessment: triageAssessment,
        care_plans: encounter.care_plans || [],
        clinical_alerts: encounter.alerts || [],
        referrals: encounter.referrals || [],
        follow_ups: encounter.follow_ups || []
      };
    });
  } catch (error) {
    throwIfActiveOpdLockError(error);
    throw error;
  }

  return result;
};

const listOpdFlows = async (
  filters = {},
  page = 1,
  limit = 20,
  sortBy = 'started_at',
  order = 'desc',
  context = {}
) => {
  const skip = (page - 1) * limit;
  const resolvedFilters = { ...filters };
  resolvedFilters.queue_scope = String(filters.queue_scope || QUEUE_SCOPES.ALL)
    .trim()
    .toUpperCase();
  if (!Object.values(QUEUE_SCOPES).includes(resolvedFilters.queue_scope)) {
    resolvedFilters.queue_scope = QUEUE_SCOPES.ALL;
  }

  if (filters.tenant_id) {
    const tenant = await resolveTenantByIdentifier(prisma, filters.tenant_id);
    if (!tenant) {
      return {
        items: [],
        pagination: {
          page,
          limit,
          total: 0,
          totalPages: 0,
          hasNextPage: false,
          hasPreviousPage: page > 1
        }
      };
    }
    resolvedFilters.tenant_id = tenant.id;
  }

  if (filters.facility_id) {
    const facility = await resolveFacilityByIdentifier(prisma, filters.facility_id, resolvedFilters.tenant_id || null);
    if (!facility) {
      return {
        items: [],
        pagination: {
          page,
          limit,
          total: 0,
          totalPages: 0,
          hasNextPage: false,
          hasPreviousPage: page > 1
        }
      };
    }
    resolvedFilters.facility_id = facility.id;
  }

  if (filters.patient_id) {
    const patient = await resolvePatientByIdentifier(prisma, filters.patient_id, resolvedFilters.tenant_id || null);
    if (!patient) {
      return {
        items: [],
        pagination: {
          page,
          limit,
          total: 0,
          totalPages: 0,
          hasNextPage: false,
          hasPreviousPage: page > 1
        }
      };
    }
    resolvedFilters.patient_id = patient.id;
  }

  const requestedProviderIdentifier =
    filters.provider_user_id || (resolvedFilters.queue_scope === QUEUE_SCOPES.ASSIGNED ? context.user_id : null);

  if (requestedProviderIdentifier) {
    const provider = await resolveProviderByIdentifier(
      prisma,
      requestedProviderIdentifier,
      resolvedFilters.tenant_id || null,
      resolvedFilters.facility_id || null
    );
    if (!provider) {
      return {
        items: [],
        pagination: {
          page,
          limit,
          total: 0,
          totalPages: 0,
          hasNextPage: false,
          hasPreviousPage: page > 1
        }
      };
    }
    resolvedFilters.provider_user_id = provider.id;
  }

  const where = buildEncounterWhereClause(resolvedFilters);
  const orderBy = { [sortBy]: order };

  const flowDisplayInclude = {
    provider: PROVIDER_INCLUDE,
    vital_signs: { where: { deleted_at: null }, orderBy: { recorded_at: 'asc' } },
    admissions: {
      where: { deleted_at: null },
      orderBy: { created_at: 'desc' },
      include: { bed_assignments: { where: { deleted_at: null }, orderBy: { assigned_at: 'desc' } } }
    },
    lab_orders: {
      where: { deleted_at: null },
      orderBy: { created_at: 'desc' },
      include: {
        items: { where: { deleted_at: null }, include: { results: { where: { deleted_at: null } } } },
        samples: { where: { deleted_at: null } }
      }
    },
    radiology_orders: {
      where: { deleted_at: null },
      orderBy: { created_at: 'desc' },
      include: { results: { where: { deleted_at: null } }, imaging_studies: { where: { deleted_at: null } } }
    },
    pharmacy_orders: {
      where: { deleted_at: null },
      orderBy: { created_at: 'desc' },
      include: { items: { where: { deleted_at: null }, include: { dispense_logs: { where: { deleted_at: null } } } } }
    }
  };

  const [encounters, total] = await Promise.all([
    opdFlowRepository.findMany(where, skip, limit, orderBy, flowDisplayInclude),
    opdFlowRepository.count(where)
  ]);

  let items = encounters.map((encounter) => {
    const flow = encounter?.extension_json?.opd_flow || null;
    return {
      encounter,
      flow: flow ? attachResolvedDisplayToFlow(encounter, flow) : flow
    };
  });

  if (resolvedFilters.encounter_type === 'EMERGENCY') {
    items = sortEmergencyQueueItems(await enrichEmergencyQueueUrgency(items));
  }
  items = await enrichConsultationBillingForListItems(items);
  items = items.map((item) => ({
    ...item,
    flow: item.flow ? attachResolvedDisplayToFlow(item.encounter, item.flow) : item.flow
  }));

  return {
    items,
    pagination: {
      page,
      limit,
      total,
      totalPages: Math.ceil(total / limit),
      hasNextPage: page < Math.ceil(total / limit),
      hasPreviousPage: page > 1
    }
  };
};

const getOpdFlowSummaryCounts = async (filters = {}, context = {}) => {
  const tenantId = filters.tenant_id || context.tenant_id || null;
  const facilityId = filters.facility_id || context.facility_id || null;
  const scopeWhere = {
    deleted_at: null,
    ...(tenantId ? { tenant_id: tenantId } : {}),
    ...(facilityId ? { facility_id: facilityId } : {})
  };
  const encounterScopeWhere = {
    ...scopeWhere,
    encounter_type: 'OPD',
    AND: [buildOpdFlowStagePresenceClause()]
  };
  const activeEncounterWhere = {
    ...encounterScopeWhere,
    status: 'OPEN'
  };
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const tomorrow = new Date(today);
  tomorrow.setDate(tomorrow.getDate() + 1);

  const flowDisplayInclude = {
    provider: PROVIDER_INCLUDE,
    vital_signs: { where: { deleted_at: null }, orderBy: { recorded_at: 'asc' } },
    admissions: {
      where: { deleted_at: null },
      orderBy: { created_at: 'desc' },
      include: { bed_assignments: { where: { deleted_at: null }, orderBy: { assigned_at: 'desc' } } }
    },
    lab_orders: {
      where: { deleted_at: null },
      orderBy: { created_at: 'desc' },
      include: {
        items: { where: { deleted_at: null }, include: { results: { where: { deleted_at: null } } } },
        samples: { where: { deleted_at: null } }
      }
    },
    radiology_orders: {
      where: { deleted_at: null },
      orderBy: { created_at: 'desc' },
      include: { results: { where: { deleted_at: null } }, imaging_studies: { where: { deleted_at: null } } }
    },
    pharmacy_orders: {
      where: { deleted_at: null },
      orderBy: { created_at: 'desc' },
      include: { items: { where: { deleted_at: null }, include: { dispense_logs: { where: { deleted_at: null } } } } }
    }
  };

  const [allPatients, opdPatients, activeOpdPatients, openEncounters, dischargedTodayPatients] = await Promise.all([
    prisma.patient.count({ where: scopeWhere }),
    prisma.encounter.findMany({
      where: encounterScopeWhere,
      distinct: ['patient_id'],
      select: { patient_id: true }
    }),
    prisma.encounter.findMany({
      where: activeEncounterWhere,
      distinct: ['patient_id'],
      select: { patient_id: true }
    }),
    prisma.encounter.findMany({
      where: activeEncounterWhere,
      include: flowDisplayInclude
    }),
    prisma.encounter.findMany({
      where: {
        ...encounterScopeWhere,
        OR: [
          { status: 'CLOSED', ended_at: { gte: today, lt: tomorrow } },
          {
            extension_json: buildOpdFlowJsonFilter(OPD_FLOW_STAGE_JSON_PATH, STAGES.DISCHARGED),
            updated_at: { gte: today, lt: tomorrow }
          }
        ]
      },
      distinct: ['patient_id'],
      select: { patient_id: true }
    })
  ]);

  const counts = {
    all_patients: allPatients,
    all_opd_patients: opdPatients.length,
    active_opd: activeOpdPatients.length,
    vitals_needed: 0,
    doctor_needed: 0,
    with_doctor: 0,
    lab_pending: 0,
    imaging_pending: 0,
    pharmacy_pending: 0,
    decision_needed: 0,
    admission_pending: 0,
    discharged_today: dischargedTodayPatients.length
  };

  const openItems = await enrichConsultationBillingForListItems(
    openEncounters.map((encounter) => ({
      encounter,
      flow: encounter?.extension_json?.opd_flow || {}
    }))
  );

  const categoryPatientSets = {
    vitals_needed: new Set(),
    doctor_needed: new Set(),
    with_doctor: new Set(),
    lab_pending: new Set(),
    imaging_pending: new Set(),
    pharmacy_pending: new Set(),
    decision_needed: new Set(),
    admission_pending: new Set()};
  const addPatientToCategory = (key, encounter) => {
    const patientKey = normalizeIdentifier(encounter?.patient_id) || normalizeIdentifier(encounter?.id);
    if (patientKey && categoryPatientSets[key]) categoryPatientSets[key].add(patientKey);
  };

  openItems.forEach((item) => {
    const display = resolveOpdDisplayState(item.encounter, item.flow);
    switch (display.display_code) {
      case 'VITALS_NEEDED':
        addPatientToCategory('vitals_needed', item.encounter);
        break;
      case 'DOCTOR_NEEDED':
        addPatientToCategory('doctor_needed', item.encounter);
        break;
      case 'WITH_DOCTOR':
        addPatientToCategory('with_doctor', item.encounter);
        break;
      case 'LAB_PENDING':
      case 'SAMPLE_PENDING':
      case 'IN_LAB':
        addPatientToCategory('lab_pending', item.encounter);
        break;
      case 'IMAGING_PENDING':
      case 'REPORT_PENDING':
        addPatientToCategory('imaging_pending', item.encounter);
        break;
      case 'PHARMACY_PENDING':
        addPatientToCategory('pharmacy_pending', item.encounter);
        break;
      case 'DECISION_NEEDED':
      case 'RESULTS_READY':
      case 'REPORT_READY':
      case 'MEDICINES_DISPENSED':
        addPatientToCategory('decision_needed', item.encounter);
        break;
      case 'ADMISSION_PENDING':
        addPatientToCategory('admission_pending', item.encounter);
        break;
      default:
        break;
    }
  });

  Object.entries(categoryPatientSets).forEach(([key, values]) => {
    counts[key] = values.size;
  });

  return counts;
};

const bootstrapOpdFlow = async (data = {}, context = {}) => {
  const encounterType =
    String(data?.encounter_type || 'OPD')
      .trim()
      .toUpperCase() === 'EMERGENCY'
      ? 'EMERGENCY'
      : 'OPD';
  const reuseOpenEncounter = data?.reuse_open_encounter !== false;

  let result;
  try {
    result = await prisma.$transaction(async (tx) => {
      const resolvedTenantFromBody = data.tenant_id ? await resolveTenantByIdentifier(tx, data.tenant_id) : null;
      if (data.tenant_id && !resolvedTenantFromBody) {
        throw new HttpError('errors.tenant.not_found', 404, [{ field: 'tenant_id' }]);
      }

      const tenantId = resolvedTenantFromBody?.id || context.tenant_id || null;
      if (!tenantId) {
        throw new HttpError('errors.validation.required', 400, [{ field: 'tenant_id' }]);
      }

      const patient = await resolvePatientByIdentifier(tx, data.patient_id, tenantId);
      if (!patient) {
        throw new HttpError('errors.patient.not_found', 404, [{ field: 'patient_id' }]);
      }

      let facilityId = context.facility_id || null;
      if (data.facility_id !== undefined && data.facility_id !== null) {
        const facility = await resolveFacilityByIdentifier(tx, data.facility_id, tenantId);
        if (!facility) {
          throw new HttpError('errors.facility.not_found', 404, [{ field: 'facility_id' }]);
        }
        facilityId = facility.id;
      } else if (data.facility_id === null) {
        facilityId = null;
      }

      let providerUserId = null;
      if (data.provider_user_id) {
        const provider = await resolveProviderByIdentifier(tx, data.provider_user_id, tenantId, facilityId);
        if (!provider) {
          throw new HttpError('errors.user.not_found', 404, [{ field: 'provider_user_id' }]);
        }
        providerUserId = provider.id;
      }

      const existingOpenEncounter = await resolveOpenEncounterForPatient(tx, {
        tenantId,
        facilityId,
        patientId: patient.id,
        encounterTypes: ACTIVE_OPD_ENCOUNTER_TYPES
      });
      if (existingOpenEncounter) {
        if (reuseOpenEncounter && hasOpdFlowState(existingOpenEncounter)) {
          return { encounterId: existingOpenEncounter.id, reused: true };
        }

        if (!reuseOpenEncounter) {
          throwActiveOpdEncounterExists({
            encounter_id: existingOpenEncounter.human_friendly_id || existingOpenEncounter.id,
            encounter_type: existingOpenEncounter.encounter_type,
            stage: existingOpenEncounter.extension_json?.opd_flow?.stage || null
          });
        }
        // Incomplete OPEN encounter (e.g. seed row without opd_flow): let startOpdFlow
        // hydrate flow state onto the existing row instead of failing getOpdFlowById.
      }

      return {
        encounterId: null,
        reused: false,
        startPayload: {
          tenant_id: tenantId,
          facility_id: facilityId,
          patient_id: patient.id,
          provider_user_id: providerUserId || null,
          arrival_mode: encounterType === 'EMERGENCY' ? 'EMERGENCY' : 'WALK_IN',
          emergency: encounterType === 'EMERGENCY' ? { severity: 'HIGH' } : undefined,
          ...(reuseOpenEncounter && existingOpenEncounter
            ? { reuse_open_encounter: true }
            : {})
        }
      };
    });
  } catch (error) {
    throwIfActiveOpdLockError(error);
    throw error;
  }

  if (result?.reused && result?.encounterId) {
    return getOpdFlowById(result.encounterId);
  }

  return startOpdFlow(result.startPayload, context);
};

const startOpdFlow = async (data, context = {}) => {
  const startedAt = new Date();
  const reuseOpenEncounter = data?.reuse_open_encounter === true;
  const forceNewEncounter = data?.force_new_encounter === true;

  let startedResult;
  try {
    startedResult = await prisma.$transaction(async (tx) => {
      const resolvedTenantFromBody = data.tenant_id ? await resolveTenantByIdentifier(tx, data.tenant_id) : null;
      if (data.tenant_id && !resolvedTenantFromBody) {
        throw new HttpError('errors.tenant.not_found', 404, [{ field: 'tenant_id' }]);
      }

      const requestedTenantId = resolvedTenantFromBody?.id || context.tenant_id || null;
      let requestedFacilityId = context.facility_id !== undefined ? context.facility_id : null;
      if (data.facility_id !== undefined && data.facility_id !== null) {
        const resolvedFacility = await resolveFacilityByIdentifier(tx, data.facility_id, requestedTenantId || null);
        if (!resolvedFacility) {
          throw new HttpError('errors.facility.not_found', 404, [{ field: 'facility_id' }]);
        }
        requestedFacilityId = resolvedFacility.id;
      } else if (data.facility_id === null) {
        requestedFacilityId = null;
      }

      const appointmentIdentifier = normalizeIdentifier(data.appointment_id);
      let appointment = appointmentIdentifier
        ? await resolveAppointmentByIdentifier(tx, appointmentIdentifier, requestedTenantId, requestedFacilityId)
        : null;

      if (appointmentIdentifier && !appointment) {
        throw new HttpError('errors.appointment.not_found', 404);
      }

      const visitQueueIdentifier = normalizeIdentifier(data.visit_queue_id);
      const requestedVisitQueue = visitQueueIdentifier
        ? await resolveVisitQueueByIdentifier(tx, visitQueueIdentifier, requestedTenantId, requestedFacilityId)
        : null;

      if (visitQueueIdentifier && !requestedVisitQueue) {
        throw new HttpError('errors.visit_queue.not_found', 404, [{ field: 'visit_queue_id' }]);
      }

      if (!appointment && requestedVisitQueue?.appointment_id) {
        appointment = await resolveAppointmentByIdentifier(
          tx,
          requestedVisitQueue.appointment_id,
          requestedVisitQueue.tenant_id || requestedTenantId,
          requestedVisitQueue.facility_id || requestedFacilityId
        );
      }

      if (appointment && (appointment.status === 'CANCELLED' || appointment.status === 'NO_SHOW')) {
        throw new HttpError('errors.opd_flow.appointment_terminal_status', 400);
      }

      if (requestedVisitQueue) {
        const existingQueueFlow = await tx.encounter.findFirst({
          where: {
            deleted_at: null,
            status: 'OPEN',
            encounter_type: { in: ['OPD', 'EMERGENCY'] },
            extension_json: buildOpdFlowJsonFilter(OPD_FLOW_VISIT_QUEUE_ID_JSON_PATH, requestedVisitQueue.id)
          },
          select: { id: true }
        });

        if (existingQueueFlow && !forceNewEncounter) {
          const queueStatusChanged = requestedVisitQueue.status !== 'IN_PROGRESS';
          if (queueStatusChanged) {
            await tx.visit_queue.update({
              where: { id: requestedVisitQueue.id },
              data: { status: 'IN_PROGRESS' }
            });
          }
          return {
            existingEncounterId: existingQueueFlow.id,
            queueStatusChanged
          };
        }
      }

      if (appointment) {
        const existingFlow = await tx.encounter.findFirst({
          where: {
            deleted_at: null,
            status: 'OPEN',
            encounter_type: { in: ['OPD', 'EMERGENCY'] },
            extension_json: buildOpdFlowJsonFilter(OPD_FLOW_APPOINTMENT_ID_JSON_PATH, appointment.id)
          },
          select: { id: true }
        });

        if (existingFlow && !forceNewEncounter) {
          return { existingEncounterId: existingFlow.id };
        }
      }

      const arrivalMode = deriveArrivalMode(data, appointment);

      if (arrivalMode === 'ONLINE_APPOINTMENT' && !appointment) {
        throw new HttpError('errors.opd_flow.appointment_required_for_online_mode', 400);
      }

      const tenantId =
        resolvedTenantFromBody?.id ||
        context.tenant_id ||
        appointment?.tenant_id ||
        requestedVisitQueue?.tenant_id ||
        null;
      if (!tenantId) {
        throw new HttpError('errors.validation.required', 400, [{ field: 'tenant_id' }]);
      }

      let facilityId =
        data.facility_id !== undefined
          ? requestedFacilityId
          : requestedFacilityId || appointment?.facility_id || requestedVisitQueue?.facility_id || null;
      if (data.facility_id === null) {
        facilityId = null;
      }

      const requestedPatientIdentifier = normalizeIdentifier(data.patient_id);
      let patientId = appointment?.patient_id || requestedVisitQueue?.patient_id || null;

      if (requestedPatientIdentifier) {
        const existingPatient = await resolvePatientByIdentifier(tx, requestedPatientIdentifier, tenantId);
        if (!existingPatient) {
          throw new HttpError('errors.opd_flow.patient_not_found', 404);
        }

        if (appointment && appointment.patient_id !== existingPatient.id) {
          throw new HttpError('errors.opd_flow.appointment_patient_mismatch', 400);
        }

        patientId = existingPatient.id;
      } else if (patientId) {
        const existingPatient = await resolvePatientByIdentifier(tx, patientId, tenantId);
        if (!existingPatient) {
          throw new HttpError('errors.opd_flow.patient_not_found', 404);
        }

        patientId = existingPatient.id;
      } else if (data.patient_registration) {
        const createdPatient = await tx.patient.create({
          data: {
            tenant_id: tenantId,
            facility_id: facilityId,
            first_name: data.patient_registration.first_name,
            last_name: data.patient_registration.last_name,
            date_of_birth: data.patient_registration.date_of_birth
              ? new Date(data.patient_registration.date_of_birth)
              : null,
            gender: data.patient_registration.gender || null,
            is_active: true
          }
        });
        patientId = createdPatient.id;
      } else {
        throw new HttpError('errors.opd_flow.patient_or_appointment_required', 400);
      }

      if (requestedVisitQueue && requestedVisitQueue.patient_id !== patientId) {
        throw new HttpError('errors.opd_flow.patient_queue_mismatch', 400, [{ field: 'visit_queue_id' }]);
      }

      if (appointment && requestedVisitQueue?.appointment_id && requestedVisitQueue.appointment_id !== appointment.id) {
        throw new HttpError('errors.opd_flow.appointment_queue_mismatch', 400, [{ field: 'visit_queue_id' }]);
      }

      let incompleteOpenEncounterToHydrate = null;
      const existingOpenEncounter = await resolveOpenEncounterForPatient(tx, {
        tenantId,
        facilityId,
        patientId
      });
      if (existingOpenEncounter) {
        if (forceNewEncounter) {
          const requestedSupersededId = normalizeIdentifier(
            data.supersede_encounter_id
          );
          const existingIds = new Set(
            [
              existingOpenEncounter.id,
              existingOpenEncounter.human_friendly_id
            ]
              .map(normalizeIdentifier)
              .filter(Boolean)
          );
          if (!requestedSupersededId || !existingIds.has(requestedSupersededId)) {
            throw new HttpError(
              'errors.opd_flow.supersede_encounter_mismatch',
              409,
              [{ field: 'supersede_encounter_id' }]
            );
          }

          const supersededFlow = getOpdFlowStateOrShell(existingOpenEncounter, {
            arrivalMode:
              existingOpenEncounter.encounter_type === 'EMERGENCY'
                ? 'EMERGENCY'
                : 'WALK_IN'
          });
          supersededFlow.cancellation_reason_code = 'SUPERSEDED_BY_NEW_VISIT';
          supersededFlow.cancellation_reason_notes =
            normalizeNotes(data.supersede_reason_notes) || null;
          supersededFlow.cancelled_at = startedAt.toISOString();
          appendTimelineEvent(
            supersededFlow,
            'ENCOUNTER_SUPERSEDED',
            context,
            {
              reason_code: 'SUPERSEDED_BY_NEW_VISIT',
              reason_notes: supersededFlow.cancellation_reason_notes
            },
            startedAt
          );
          await finalizeEncounterClosure(
            tx,
            existingOpenEncounter,
            supersededFlow,
            startedAt,
            'CANCELLED'
          );
        } else if (reuseOpenEncounter) {
          if (hasOpdFlowState(existingOpenEncounter)) {
            return { existingEncounterId: existingOpenEncounter.id };
          }
          // Seeded/incomplete OPEN rows without opd_flow still hold the active
          // lock. Hydrate flow state onto that row instead of 404-ing.
          incompleteOpenEncounterToHydrate = existingOpenEncounter;
        } else {
          throwActiveOpdEncounterExists({
            encounter_id: existingOpenEncounter.human_friendly_id || existingOpenEncounter.id,
            encounter_type: existingOpenEncounter.encounter_type,
            stage: existingOpenEncounter.extension_json?.opd_flow?.stage || null
          });
        }
      }

      const openAdmission = await tx.admission.findFirst({
        where: {
          tenant_id: tenantId,
          patient_id: patientId,
          deleted_at: null,
          status: { in: ['ADMITTED', 'TRANSFERRED'] },
          ...(facilityId
            ? { OR: [{ facility_id: facilityId }, { facility_id: null }] }
            : {})
        },
        select: {
          id: true,
          human_friendly_id: true,
          status: true
        },
        orderBy: { created_at: 'desc' }
      });
      if (openAdmission) {
        throw new HttpError('errors.opd_flow.open_admission_exists', 409, [
          {
            field: 'patient_id',
            admission_id: openAdmission.human_friendly_id || openAdmission.id,
            admission_status: openAdmission.status
          }
        ]);
      }

      const providerIdentifier =
        normalizeIdentifier(data.provider_user_id) ||
        normalizeIdentifier(requestedVisitQueue?.provider_user_id) ||
        normalizeIdentifier(appointment?.provider_user_id);
      let resolvedProvider = null;
      if (providerIdentifier) {
        resolvedProvider = await resolveProviderByIdentifier(tx, providerIdentifier, tenantId, facilityId);
        if (!resolvedProvider && normalizeIdentifier(data.provider_user_id)) {
          throw new HttpError('errors.user.not_found', 404, [{ field: 'provider_user_id' }]);
        }
      }

      const providerUserId =
        resolvedProvider?.id ||
        (normalizeIdentifier(requestedVisitQueue?.provider_user_id) ? requestedVisitQueue.provider_user_id : null) ||
        (normalizeIdentifier(appointment?.provider_user_id) ? appointment.provider_user_id : null);
      const feeDefaults = await resolveConsultationFeeDefaults(tx, {
        provider: resolvedProvider,
        tenantId,
        facilityId
      });
      const consultationFee = normalizeDecimalString(
        data.consultation_fee,
        feeDefaults.consultationFee || '0.00'
      );
      const currency = normalizeCurrencyCode(data.currency, feeDefaults.consultationCurrency || 'USD');
      const hasPositiveFee = toDecimalNumber(consultationFee) > 0;
      const requireConsultationPayment =
        data.require_consultation_payment !== undefined
          ? data.require_consultation_payment && hasPositiveFee
          : arrivalMode !== 'EMERGENCY' && hasPositiveFee;
      const createConsultationInvoice =
        data.create_consultation_invoice !== undefined
          ? data.create_consultation_invoice
          : requireConsultationPayment || Boolean(data.pay_now);

      let consultationInvoice = null;
      let consultationPayment = null;
      let isConsultationPaid = false;
      let consultationPaidAt = null;
      let consultationPaymentStatus = requireConsultationPayment ? 'PENDING' : 'NOT_REQUIRED';
      let consultationBillingSnapshot = null;
      const consultationCatalogItemId =
        resolvedProvider?.staff_profile?.id || facilityId || null;

      // Billing is applied after the encounter is created so the charge is
      // traceable/idempotent against the encounter via the central engine.
      const shouldCreateConsultationInvoice =
        createConsultationInvoice || Boolean(data.pay_now);

      const expectConsultationPaid = Boolean(
        data.pay_now &&
          ['COMPLETED', 'PAID', 'SUCCESS', 'SUCCESSFUL', 'APPROVED'].includes(
            String(data.pay_now.status || 'COMPLETED')
              .trim()
              .toUpperCase()
          )
      );

      let emergencyCase = null;
      let triageAssessment = null;
      let linkedExistingEmergencyCase = false;

      if (arrivalMode === 'EMERGENCY') {
        const emergencyCaseIdentifier = normalizeIdentifier(data.emergency_case_id);
        emergencyCase = emergencyCaseIdentifier
          ? await resolveEmergencyCaseByIdentifier(tx, emergencyCaseIdentifier, tenantId, facilityId, patientId)
          : null;
        if (emergencyCaseIdentifier && !emergencyCase) {
          throw new HttpError('errors.emergency_case.not_found', 404, [
            { field: 'emergency_case_id' }
          ]);
        }

        if (!emergencyCase) {
          emergencyCase = await tx.emergency_case.create({
            data: {
              tenant_id: tenantId,
              facility_id: facilityId,
              patient_id: patientId,
              severity: data.emergency?.severity || 'HIGH',
              status: 'OPEN'
            }
          });
        } else {
          linkedExistingEmergencyCase = true;
        }

        const triageLevel = emergencyCaseIdentifier ? null : mapTriageLevel(data.emergency?.triage_level);
        if (!emergencyCaseIdentifier && triageLevel) {
          triageAssessment = await tx.triage_assessment.create({
            data: {
              emergency_case_id: emergencyCase.id,
              triage_level: triageLevel,
              notes: data.emergency?.notes || null
            }
          });
        }
      }

      const defaultInitialStage =
        arrivalMode !== 'EMERGENCY' && requireConsultationPayment && !expectConsultationPaid
          ? STAGES.WAITING_CONSULTATION_PAYMENT
          : STAGES.WAITING_VITALS;
      const requestedInitialStage = normalizeIdentifier(data.initial_stage).toUpperCase();
      const initialStage =
        requestedInitialStage &&
        WORKFLOW_STAGE_SET.has(requestedInitialStage) &&
        !TERMINAL_STAGES.has(requestedInitialStage)
          ? requestedInitialStage
          : defaultInitialStage;

      const flowState = {
        version: 1,
        arrival_mode: arrivalMode,
        stage: initialStage,
        next_step: getNextStep(initialStage),
        consultation: {
          require_payment: requireConsultationPayment,
          consultation_fee: consultationFee,
          currency,
          invoice_id: null,
          payment_id: null,
          payment_status: consultationPaymentStatus,
          is_paid: false,
          paid_amount: null,
          paid_at: null
        },
        appointment_id: appointment?.id || requestedVisitQueue?.appointment_id || null,
        visit_queue_id: requestedVisitQueue?.id || null,
        emergency_case_id: emergencyCase?.id || null,
        triage_assessment_id: triageAssessment?.id || null,
        lab_order_ids: [],
        radiology_order_ids: [],
        pharmacy_order_id: null,
        admission_id: null,
        review_completed: false,
        timeline: []
      };

      appendTimelineEvent(
        flowState,
        'FLOW_STARTED',
        context,
        {
          arrival_mode: arrivalMode,
          notes: data.notes || null
        },
        startedAt
      );

      if (emergencyCase) {
        appendTimelineEvent(
          flowState,
          linkedExistingEmergencyCase ? 'EMERGENCY_CASE_LINKED' : 'EMERGENCY_CASE_OPENED',
          context,
          {
            emergency_case_id: emergencyCase.id,
            severity: emergencyCase.severity,
            triage_assessment_id: triageAssessment?.id || null
          },
          startedAt
        );
      }

      const queuedAt = data.queued_at ? new Date(data.queued_at) : requestedVisitQueue?.queued_at || startedAt;
      let visitQueue = requestedVisitQueue || null;
      if (visitQueue) {
        visitQueue = await tx.visit_queue.update({
          where: { id: visitQueue.id },
          data: {
            provider_user_id: providerUserId || visitQueue.provider_user_id || null,
            status: 'IN_PROGRESS',
            queued_at: queuedAt
          }
        });
      } else {
        visitQueue = await tx.visit_queue.create({
          data: {
            tenant_id: tenantId,
            facility_id: facilityId,
            patient_id: patientId,
            appointment_id: appointment?.id || null,
            provider_user_id: providerUserId,
            status: 'IN_PROGRESS',
            queued_at: queuedAt
          }
        });
      }
      flowState.visit_queue_id = visitQueue.id;

      let encounter;
      if (incompleteOpenEncounterToHydrate) {
        encounter = await tx.encounter.update({
          where: { id: incompleteOpenEncounterToHydrate.id },
          data: {
            provider_user_id:
              providerUserId || incompleteOpenEncounterToHydrate.provider_user_id || null,
            encounter_type: arrivalMode === 'EMERGENCY' ? 'EMERGENCY' : 'OPD',
            active_opd_lock_key:
              incompleteOpenEncounterToHydrate.active_opd_lock_key ||
              buildActiveOpdLockKey({
                tenantId,
                facilityId,
                patientId
              }),
            extension_json: {
              ...(incompleteOpenEncounterToHydrate.extension_json || {}),
              opd_flow: flowState
            }
          },
          include: {
            tenant: true,
            facility: true,
            patient: true,
            provider: PROVIDER_INCLUDE
          }
        });
      } else {
        encounter = await tx.encounter.create({
          data: {
            tenant_id: tenantId,
            facility_id: facilityId,
            patient_id: patientId,
            provider_user_id: providerUserId,
            encounter_type: arrivalMode === 'EMERGENCY' ? 'EMERGENCY' : 'OPD',
            status: 'OPEN',
            active_opd_lock_key: buildActiveOpdLockKey({
              tenantId,
              facilityId,
              patientId
            }),
            started_at: startedAt,
            extension_json: {
              opd_flow: flowState
            }
          },
          include: {
            tenant: true,
            facility: true,
            patient: true,
            provider: PROVIDER_INCLUDE
          }
        });
      }

      const needsBillingForPaymentStage =
        shouldCreateConsultationInvoice ||
        flowState.stage === STAGES.WAITING_CONSULTATION_PAYMENT;

      if (needsBillingForPaymentStage) {
        const consultationPaymentMode =
          data.coverage_plan_id ||
          data.insurance_company_id ||
          normalizeUpper(data.pay_now?.method) === 'INSURANCE'
            ? 'INSURANCE'
            : 'SELF_PAY';
        const billingPayload = buildConsultationBillingPayload({
          consultationFee: consultationFee || '0.00',
          currency,
          paymentStatus: requireConsultationPayment ? 'PENDING' : 'PENDING',
          catalogItemId: consultationCatalogItemId,
          payNow: data.pay_now || null,
          ...(consultationPaymentMode === 'INSURANCE'
            ? { paymentMode: consultationPaymentMode }
            : {})
        });

        if (billingPayload) {
          consultationBillingSnapshot = await persistConsultationBilling(tx, {
            encounterId: encounter.id,
            billing: billingPayload,
            tenantId,
            facilityId,
            patientId,
            encounterDisplayId: encounter.human_friendly_id || null,
            catalogItemId: consultationCatalogItemId,
            actorUserId: context.user_id || null,
            currency,
            ...(consultationPaymentMode === 'INSURANCE'
              ? {
                  paymentMode: consultationPaymentMode,
                  coveragePlanId: data.coverage_plan_id || null,
                  insuranceCompanyId: data.insurance_company_id || null
                }
              : {}),
            issuedAt: startedAt,
            description: 'Consultation fee'
          });
        }

        if (consultationBillingSnapshot?.invoice_id) {
          consultationInvoice = await tx.invoice.findFirst({
            where: { id: consultationBillingSnapshot.invoice_id, deleted_at: null },
            include: { payments: { where: { deleted_at: null }, orderBy: { created_at: 'desc' } } }
          });
          consultationPayment =
            (consultationInvoice?.payments || []).find((entry) =>
              PAID_PAYMENT_STATUSES.has(normalizeUpper(entry.status))
            ) ||
            consultationInvoice?.payments?.[0] ||
            null;

          consultationPaymentStatus =
            consultationBillingSnapshot.payment_status || consultationPaymentStatus;
          isConsultationPaid =
            consultationPaymentStatus === 'PAID' ||
            PAID_PAYMENT_STATUSES.has(normalizeUpper(consultationPayment?.status));
          consultationPaidAt =
            isConsultationPaid && consultationPayment?.paid_at
              ? consultationPayment.paid_at
              : isConsultationPaid
                ? startedAt
                : null;

          flowState.consultation = {
            ...flowState.consultation,
            invoice_id: consultationBillingSnapshot.invoice_id,
            payment_id: consultationPayment?.id || null,
            payment_status: consultationPaymentStatus,
            is_paid: isConsultationPaid,
            paid_amount: isConsultationPaid
              ? consultationBillingSnapshot.paid_amount ||
                consultationPayment?.amount?.toString?.() ||
                null
              : null,
            paid_at: consultationPaidAt ? consultationPaidAt.toISOString() : null,
            billing: consultationBillingSnapshot
          };

          if (
            flowState.stage === STAGES.WAITING_CONSULTATION_PAYMENT &&
            isConsultationPaid
          ) {
            setFlowStage(flowState, STAGES.WAITING_VITALS);
          }

          appendTimelineEvent(
            flowState,
            'CONSULTATION_INVOICE_CREATED',
            context,
            {
              invoice_id: consultationBillingSnapshot.invoice_id,
              consultation_fee: consultationFee,
              currency
            },
            startedAt
          );

          if (consultationPayment) {
            appendTimelineEvent(
              flowState,
              'CONSULTATION_PAYMENT_RECORDED',
              context,
              {
                payment_id: consultationPayment.id,
                status: consultationPayment.status
              },
              startedAt
            );
          }

          // Prefer updateMany + findFirst over update(). The tenant-guard update
          // preflight reads via the base client and cannot see this encounter
          // until the surrounding interactive transaction commits.
          await tx.encounter.updateMany({
            where: { id: encounter.id },
            data: {
              extension_json: {
                ...(encounter.extension_json || {}),
                opd_flow: flowState
              }
            }
          });
          encounter = await tx.encounter.findFirst({
            where: { id: encounter.id },
            include: {
              tenant: true,
              facility: true,
              patient: true,
              provider: PROVIDER_INCLUDE
            }
          });
          if (!encounter) {
            throw new HttpError('errors.opd_flow.not_found', 404);
          }
        }
      }

      if (
        flowState.stage === STAGES.WAITING_CONSULTATION_PAYMENT &&
        !flowState.consultation?.is_paid
      ) {
        const consultationPaymentMode =
          data.coverage_plan_id ||
          data.insurance_company_id ||
          normalizeUpper(data.pay_now?.method) === 'INSURANCE'
            ? 'INSURANCE'
            : 'SELF_PAY';
        await ensureUnpaidConsultationInvoiceForPaymentDue(tx, {
          encounter,
          flow: flowState,
          catalogItemId: consultationCatalogItemId,
          context,
          issuedAt: startedAt,
          paymentMode: consultationPaymentMode,
          coveragePlanId: data.coverage_plan_id || null,
          insuranceCompanyId: data.insurance_company_id || null,
          payNow: data.pay_now || null
        });
        await tx.encounter.updateMany({
          where: { id: encounter.id },
          data: {
            extension_json: {
              ...(encounter.extension_json || {}),
              opd_flow: flowState
            }
          }
        });
        encounter = await tx.encounter.findFirst({
          where: { id: encounter.id },
          include: {
            tenant: true,
            facility: true,
            patient: true,
            provider: PROVIDER_INCLUDE
          }
        });
        if (!encounter) {
          throw new HttpError('errors.opd_flow.not_found', 404);
        }
      }

      if (appointment && appointment.status !== 'IN_PROGRESS') {
        await tx.appointment.update({
          where: { id: appointment.id },
          data: { status: 'IN_PROGRESS' }
        });
      }

      return {
        encounter,
        transition: {
          action: 'START_FLOW',
          stage_from: null,
          stage_to: initialStage,
          provider_user_id: providerUserId,
          occurred_at: startedAt.toISOString()
        }
      };
    });
  } catch (error) {
    throwIfActiveOpdLockError(error);
    throw error;
  }

  if (startedResult.existingEncounterId) {
    const snapshot = await getOpdFlowById(startedResult.existingEncounterId);
    if (startedResult.queueStatusChanged) {
      const stage = snapshot?.flow?.stage || null;
      await publishOpdRealtimeUpdates({
        snapshot,
        transition: {
          action: 'REUSE_QUEUE_FLOW',
          stage_from: stage,
          stage_to: stage,
          occurred_at: startedAt.toISOString()
        },
        context
      });
    }
    return snapshot;
  }

  createAuditLog({
    tenant_id: startedResult.encounter.tenant_id,
    user_id: context.user_id,
    action: 'CREATE',
    entity: 'opd_flow',
    entity_id: startedResult.encounter.id,
    diff: { after: startedResult.encounter },
    ip_address: context.ip_address
  }).catch(() => {});

  const snapshot = await getOpdFlowById(startedResult.encounter.id);
  await publishOpdRealtimeUpdates({
    snapshot,
    transition: startedResult.transition,
    context
  });
  if (snapshot?.flow?.consultation?.invoice_id) {
    await publishConsultationBillingRealtime({
      snapshot,
      context,
      mode: 'issued'
    });
  }
  return snapshot;
};

const updateActiveEncounterContext = async (id, data, context = {}) => {
  let updatedResult;
  try {
    updatedResult = await prisma.$transaction(async (tx) => {
      const encounter = await resolveEncounterByIdentifier(tx, id);
      if (!encounter) {
        throw new HttpError('errors.opd_flow.not_found', 404);
      }
      if (encounter.status !== 'OPEN') {
        throw new HttpError('errors.opd_flow.already_terminal', 400);
      }

      const flow = getOpdFlowState(encounter);
      ensureNonTerminalStage(flow);
      const stageBefore = flow.stage;
      const now = new Date();
      const encounterUpdate = {};

      let facilityId = encounter.facility_id || null;
      if (data.facility_id !== undefined) {
        const resolvedFacility = data.facility_id
          ? await resolveFacilityByIdentifier(tx, data.facility_id, encounter.tenant_id)
          : null;
        if (data.facility_id && !resolvedFacility) {
          throw new HttpError('errors.facility.not_found', 404, [{ field: 'facility_id' }]);
        }
        facilityId = resolvedFacility?.id || null;
        encounterUpdate.facility_id = facilityId;
      }

      if (data.patient_id) {
        const requestedPatient = await resolvePatientByIdentifier(tx, data.patient_id, encounter.tenant_id);
        if (!requestedPatient) {
          throw new HttpError('errors.opd_flow.patient_not_found', 404);
        }
        if (requestedPatient.id !== encounter.patient_id) {
          throw new HttpError('errors.opd_flow.active_encounter_patient_mismatch', 400, [{ field: 'patient_id' }]);
        }
      }

      let appointment = null;
      if (data.appointment_id !== undefined) {
        const appointmentIdentifier = normalizeIdentifier(data.appointment_id);
        appointment = appointmentIdentifier
          ? await resolveAppointmentByIdentifier(tx, appointmentIdentifier, encounter.tenant_id, facilityId)
          : null;
        if (appointmentIdentifier && !appointment) {
          throw new HttpError('errors.appointment.not_found', 404, [{ field: 'appointment_id' }]);
        }
        if (appointment && appointment.patient_id !== encounter.patient_id) {
          throw new HttpError('errors.opd_flow.appointment_patient_mismatch', 400);
        }
        flow.appointment_id = appointment?.id || null;
      } else if (flow.appointment_id) {
        appointment = await tx.appointment.findFirst({
          where: { id: flow.appointment_id, deleted_at: null }
        });
      }

      let visitQueue = null;
      if (data.visit_queue_id !== undefined) {
        const visitQueueIdentifier = normalizeIdentifier(data.visit_queue_id);
        visitQueue = visitQueueIdentifier
          ? await resolveVisitQueueByIdentifier(tx, visitQueueIdentifier, encounter.tenant_id, facilityId)
          : null;
        if (visitQueueIdentifier && !visitQueue) {
          throw new HttpError('errors.visit_queue.not_found', 404, [{ field: 'visit_queue_id' }]);
        }
        if (visitQueue && visitQueue.patient_id !== encounter.patient_id) {
          throw new HttpError('errors.opd_flow.patient_queue_mismatch', 400, [{ field: 'visit_queue_id' }]);
        }
        flow.visit_queue_id = visitQueue?.id || flow.visit_queue_id || null;
      } else if (flow.visit_queue_id) {
        visitQueue = await tx.visit_queue.findFirst({
          where: { id: flow.visit_queue_id, deleted_at: null }
        });
      }

      const arrivalMode = data.arrival_mode
        ? deriveArrivalMode(data, appointment)
        : flow.arrival_mode || encounter.encounter_type || 'WALK_IN';
      flow.arrival_mode = arrivalMode;
      if (data.arrival_mode) {
        encounterUpdate.encounter_type = arrivalMode === 'EMERGENCY' ? 'EMERGENCY' : 'OPD';
      }

      let provider = null;
      let providerUserId = encounter.provider_user_id || null;
      if (data.provider_user_id !== undefined) {
        const providerIdentifier = normalizeIdentifier(data.provider_user_id);
        if (providerIdentifier) {
          provider = await resolveProviderByIdentifier(tx, providerIdentifier, encounter.tenant_id, facilityId);
          if (!provider) {
            throw new HttpError('errors.user.not_found', 404, [{ field: 'provider_user_id' }]);
          }
          providerUserId = provider.id;
        } else {
          providerUserId = null;
        }
        encounterUpdate.provider_user_id = providerUserId;
      } else if (providerUserId) {
        provider = await resolveProviderByIdentifier(tx, providerUserId, encounter.tenant_id, facilityId);
      }

      const consultation = { ...(flow.consultation || {}) };
      const feeDefaults = await resolveConsultationFeeDefaults(tx, {
        provider,
        tenantId: encounter.tenant_id,
        facilityId
      });
      const currency = normalizeCurrencyCode(
        data.currency || consultation.currency,
        feeDefaults.consultationCurrency || 'USD'
      );
      if (data.consultation_fee !== undefined) {
        consultation.consultation_fee = normalizeDecimalString(
          data.consultation_fee,
          feeDefaults.consultationFee || consultation.consultation_fee || '0.00'
        );
      } else if (!consultation.consultation_fee && feeDefaults.consultationFee) {
        consultation.consultation_fee = feeDefaults.consultationFee;
      }
      consultation.currency = currency;
      const hasPositiveContextFee = toDecimalNumber(consultation.consultation_fee || '0') > 0;
      if (data.require_consultation_payment !== undefined) {
        consultation.require_payment = data.require_consultation_payment && hasPositiveContextFee;
      } else if (consultation.require_payment && !hasPositiveContextFee) {
        consultation.require_payment = false;
        if (!consultation.payment_status || consultation.payment_status === 'PENDING') {
          consultation.payment_status = 'NOT_REQUIRED';
        }
      }

      let cancelledConsultationInvoiceId = null;
      let consultationBillingMutated = false;
      if (
        consultation.require_payment === false &&
        consultation.invoice_id &&
        !consultation.is_paid &&
        !PAID_PAYMENT_STATUSES.has(normalizeUpper(consultation.payment_status))
      ) {
        const cancelled = await cancelInvoiceIfReversible(tx, consultation.invoice_id);
        if (cancelled) {
          cancelledConsultationInvoiceId = consultation.invoice_id;
          consultation.invoice_id = null;
          consultation.billing = null;
          consultation.payment_id = null;
          consultation.payment_status = 'NOT_REQUIRED';
          consultationBillingMutated = true;
        }
      }

      const requiresInvoice =
        hasPositiveContextFee && (
          data.create_consultation_invoice === true ||
          data.pay_now ||
          consultation.require_payment === true ||
          (consultation.require_payment !== false &&
            Boolean(consultation.consultation_fee))
        );
      let invoice = consultation.invoice_id
        ? await tx.invoice.findFirst({
            where: { id: consultation.invoice_id, deleted_at: null }
          })
        : null;
      const consultationCatalogItemId =
        provider?.staff_profile?.id || facilityId || encounter.facility_id || null;

      if (
        (!invoice && requiresInvoice) ||
        (invoice &&
          (data.consultation_fee !== undefined ||
            data.currency ||
            data.pay_now ||
            data.coverage_plan_id !== undefined ||
            data.insurance_company_id !== undefined))
      ) {
        const existingSnapshot =
          consultation.billing ||
          (consultation.invoice_id ? { invoice_id: consultation.invoice_id } : null);
        const consultationPaymentMode =
          data.coverage_plan_id ||
          data.insurance_company_id ||
          normalizeUpper(data.pay_now?.method) === 'INSURANCE'
            ? 'INSURANCE'
            : consultation.billing?.payment_mode || 'SELF_PAY';
        const billingPayload = buildConsultationBillingPayload({
          consultationFee: consultation.consultation_fee || '0.00',
          currency,
          paymentStatus: consultation.require_payment ? 'PENDING' : 'PENDING',
          catalogItemId: consultationCatalogItemId,
          payNow: data.pay_now || null,
          ...(consultationPaymentMode === 'INSURANCE'
            ? { paymentMode: consultationPaymentMode }
            : {})
        });

        if (billingPayload) {
          const snapshot = await persistConsultationBilling(tx, {
            encounterId: encounter.id,
            billing: billingPayload,
            existingSnapshot,
            tenantId: encounter.tenant_id,
            facilityId,
            patientId: encounter.patient_id,
            encounterDisplayId: encounter.human_friendly_id || null,
            catalogItemId: consultationCatalogItemId,
            actorUserId: context.user_id || null,
            currency,
            ...(consultationPaymentMode === 'INSURANCE'
              ? {
                  paymentMode: consultationPaymentMode,
                  coveragePlanId:
                    data.coverage_plan_id ||
                    consultation.billing?.coverage_plan_id ||
                    null,
                  insuranceCompanyId:
                    data.insurance_company_id ||
                    consultation.billing?.insurance_company_id ||
                    null
                }
              : {}),
            issuedAt: now,
            description: 'Consultation fee',
            mutableUpdate: Boolean(existingSnapshot)
          });

          if (snapshot?.invoice_id) {
            invoice = await tx.invoice.findFirst({
              where: { id: snapshot.invoice_id, deleted_at: null },
              include: {
                payments: { where: { deleted_at: null }, orderBy: { created_at: 'desc' } }
              }
            });
            consultation.invoice_id = snapshot.invoice_id;
            consultation.billing = snapshot;
            consultation.payment_status = snapshot.payment_status || consultation.payment_status;
            consultation.is_paid = snapshot.payment_status === 'PAID';
            consultation.paid_amount = snapshot.paid_amount || null;
            consultation.paid_at = consultation.is_paid ? now.toISOString() : consultation.paid_at || null;
            const payment =
              (invoice?.payments || []).find((entry) =>
                PAID_PAYMENT_STATUSES.has(normalizeUpper(entry.status))
              ) || null;
            consultation.payment_id = payment?.id || consultation.payment_id || null;
            consultationBillingMutated = true;
          }
        }
      } else if (!consultation.payment_status) {
        consultation.payment_status = consultation.require_payment ? 'PENDING' : 'NOT_REQUIRED';
      }
      flow.consultation = consultation;

      const requestedStage = normalizeIdentifier(data.initial_stage).toUpperCase();
      if (requestedStage && WORKFLOW_STAGE_SET.has(requestedStage) && !TERMINAL_STAGES.has(requestedStage)) {
        setFlowStage(flow, requestedStage);
      } else if (consultation.require_payment && !consultation.is_paid) {
        setFlowStage(flow, STAGES.WAITING_CONSULTATION_PAYMENT);
      } else if (flow.stage === STAGES.WAITING_CONSULTATION_PAYMENT) {
        setFlowStage(flow, STAGES.WAITING_VITALS);
      }
      if (providerUserId && flow.stage === STAGES.WAITING_DOCTOR_ASSIGNMENT) {
        setFlowStage(flow, STAGES.WAITING_DOCTOR_REVIEW);
      }

      if (
        flow.stage === STAGES.WAITING_CONSULTATION_PAYMENT &&
        !consultation.invoice_id &&
        !consultation.is_paid
      ) {
        await ensureUnpaidConsultationInvoiceForPaymentDue(tx, {
          encounter,
          flow,
          catalogItemId: consultationCatalogItemId,
          context,
          issuedAt: now
        });
        if (flow.consultation?.invoice_id) {
          consultationBillingMutated = true;
        }
      }

      if (flow.visit_queue_id) {
        await tx.visit_queue.update({
          where: { id: flow.visit_queue_id },
          data: {
            provider_user_id: providerUserId,
            status: 'IN_PROGRESS',
            queued_at: data.queued_at ? new Date(data.queued_at) : undefined
          }
        });
      }

      if (appointment && appointment.status !== 'IN_PROGRESS') {
        await tx.appointment.update({
          where: { id: appointment.id },
          data: { status: 'IN_PROGRESS', provider_user_id: providerUserId }
        });
      } else if (appointment && providerUserId) {
        await tx.appointment.update({
          where: { id: appointment.id },
          data: { provider_user_id: providerUserId }
        });
      }

      appendTimelineEvent(
        flow,
        'ACTIVE_ENCOUNTER_CONTEXT_UPDATED',
        context,
        {
          provider_user_id: providerUserId,
          appointment_id: flow.appointment_id || null,
          visit_queue_id: flow.visit_queue_id || null,
          arrival_mode: arrivalMode,
          consultation_fee: consultation.consultation_fee || null,
          require_consultation_payment: consultation.require_payment,
          payment_status: consultation.payment_status || null,
          notes: data.notes || null
        },
        now
      );

      const nextEncounterState = {
        ...encounter,
        ...encounterUpdate,
        tenant_id: encounter.tenant_id,
        patient_id: encounter.patient_id,
        status: encounter.status
      };
      const updatedEncounter = await tx.encounter.update({
        where: { id: encounter.id },
        data: {
          ...encounterUpdate,
          active_opd_lock_key: activeOpdLockKeyForEncounter(nextEncounterState),
          extension_json: {
            ...(encounter.extension_json || {}),
            opd_flow: flow
          }
        }
      });

      return {
        encounter: updatedEncounter,
        cancelledConsultationInvoiceId,
        consultationBillingMutated,
        consultationInvoiceId: flow.consultation?.invoice_id || null,
        transition: {
          action: 'UPDATE_ACTIVE_ENCOUNTER_CONTEXT',
          stage_from: stageBefore,
          stage_to: flow.stage,
          provider_user_id: providerUserId,
          occurred_at: now.toISOString()
        }
      };
    });
  } catch (error) {
    throwIfActiveOpdLockError(error);
    throw error;
  }

  createAuditLog({
    tenant_id: updatedResult.encounter.tenant_id,
    user_id: context.user_id,
    action: 'UPDATE',
    entity: 'opd_flow',
    entity_id: updatedResult.encounter.id,
    diff: { after: updatedResult.encounter },
    ip_address: context.ip_address
  }).catch(() => {});

  const snapshot = await getOpdFlowById(updatedResult.encounter.id);
  await publishOpdRealtimeUpdates({
    snapshot,
    transition: updatedResult.transition,
    context
  });
  if (updatedResult.cancelledConsultationInvoiceId) {
    await publishConsultationBillingRealtime({
      snapshot,
      context,
      mode: 'cancelled',
      invoiceId: updatedResult.cancelledConsultationInvoiceId
    });
  } else if (
    updatedResult.consultationBillingMutated &&
    updatedResult.consultationInvoiceId
  ) {
    await publishConsultationBillingRealtime({
      snapshot,
      context,
      mode: 'issued'
    });
  }
  return snapshot;
};

const payConsultation = async (id, data, context = {}) => {
  let updatedResult;
  try {
    updatedResult = await prisma.$transaction(async (tx) => {
      const encounter = await resolveEncounterByIdentifier(tx, id);
      if (!encounter) {
        throw new HttpError('errors.opd_flow.not_found', 404);
      }

      const flow = getOpdFlowState(encounter);
      ensureNonTerminalStage(flow);
      const stageBefore = flow.stage;

      const consultation = flow.consultation || {};
      const isCorrection =
        consultation.is_paid === true || PAID_PAYMENT_STATUSES.has(normalizeUpper(consultation.payment_status));

      let invoiceId = data.invoice_id || consultation.invoice_id || null;
      let invoice = null;

      const effectiveFee = toDecimalNumber(
        normalizeDecimalString(data.amount, consultation.consultation_fee || '0.00')
      );
      const isZeroFee = effectiveFee <= 0 && !invoiceId;

      if (isZeroFee) {
        consultation.is_paid = true;
        consultation.paid_amount = '0.00';
        consultation.paid_at = new Date().toISOString();
        consultation.payment_status = 'PAID';
        consultation.require_payment = false;
        flow.consultation = consultation;

        if (flow.stage === STAGES.WAITING_CONSULTATION_PAYMENT) {
          setFlowStage(flow, STAGES.WAITING_VITALS);
        }

        appendTimelineEvent(
          flow,
          'CONSULTATION_PAYMENT_RECORDED',
          context,
          {
            amount: '0.00',
            status: 'COMPLETED',
            zero_fee_auto_completed: true,
            notes: data.notes || null
          }
        );
      } else {
        if (invoiceId) {
          invoice = await resolveEntityByIdentifier(tx, 'invoice', invoiceId, {
            tenant_id: encounter.tenant_id
          });
          if (!invoice) {
            throw new HttpError('errors.invoice.not_found', 404);
          }
          invoiceId = invoice.id;
        } else {
          const consultationCatalogItemId =
            encounter.provider?.staff_profile?.id ||
            encounter.facility_id ||
            null;
          const currencyForCharge = normalizeCurrencyCode(
            data.currency || consultation.currency,
            await resolveDefaultCurrency(tx, encounter.tenant_id, encounter.facility_id)
          );
          const amountForCharge = normalizeDecimalString(
            data.amount,
            consultation.consultation_fee || '0.00'
          );
          const billingPayload = buildConsultationBillingPayload({
            consultationFee: amountForCharge,
            currency: currencyForCharge,
            paymentStatus: 'PENDING',
            catalogItemId: consultationCatalogItemId,
            payNow: null
          });
          const snapshot = await persistConsultationBilling(tx, {
            encounterId: encounter.id,
            billing: billingPayload,
            existingSnapshot: consultation.billing || null,
            tenantId: encounter.tenant_id,
            facilityId: encounter.facility_id,
            patientId: encounter.patient_id,
            encounterDisplayId: encounter.human_friendly_id || null,
            catalogItemId: consultationCatalogItemId,
            actorUserId: context.user_id || null,
            currency: currencyForCharge,
            description: 'Consultation fee'
          });
          if (!snapshot?.invoice_id) {
            throw new HttpError('errors.invoice.not_found', 404);
          }
          invoice = await tx.invoice.findFirst({
            where: { id: snapshot.invoice_id, deleted_at: null }
          });
          invoiceId = invoice.id;
          consultation.billing = snapshot;
        }

        const paymentStatus = data.status || 'COMPLETED';
        const currency = normalizeCurrencyCode(
          data.currency || consultation.currency || invoice.currency,
          await resolveDefaultCurrency(tx, encounter.tenant_id, encounter.facility_id)
        );
        const amount = normalizeDecimalString(
          data.amount,
          consultation.consultation_fee || normalizeDecimalString(invoice.total_amount, '0.00')
        );

        const payment = await tx.payment.create({
          data: {
            tenant_id: encounter.tenant_id,
            facility_id: encounter.facility_id,
            patient_id: encounter.patient_id,
            invoice_id: invoiceId,
            status: paymentStatus,
            method: data.method,
            amount,
            paid_at: paymentStatus === 'COMPLETED' ? (data.paid_at ? new Date(data.paid_at) : new Date()) : null,
            transaction_ref: data.transaction_ref || null
          }
        });

        const correctedInvoiceTotal =
          isCorrection && data.amount ? amount : normalizeDecimalString(invoice.total_amount, amount);
        const shouldUpdateTotal =
          isCorrection &&
          data.amount &&
          toDecimalNumber(correctedInvoiceTotal) !== toDecimalNumber(invoice.total_amount);

        invoice = await tx.invoice.update({
          where: { id: invoice.id },
          data: {
            currency,
            ...(shouldUpdateTotal ? { total_amount: correctedInvoiceTotal } : {})
          }
        });

        consultation.invoice_id = invoice.id;
        await applyConsultationBillingSnapshot(tx, {
          invoiceId: invoice.id,
          payment,
          consultation,
          currency,
          paymentStatus
        });
        flow.consultation = consultation;

        if (flow.stage === STAGES.WAITING_CONSULTATION_PAYMENT && consultation.is_paid) {
          setFlowStage(flow, STAGES.WAITING_VITALS);
        }

        appendTimelineEvent(
          flow,
          isCorrection ? 'CONSULTATION_PAYMENT_CORRECTED' : 'CONSULTATION_PAYMENT_RECORDED',
          context,
          {
            payment_id: payment.id,
            invoice_id: invoice.id,
            amount,
            status: paymentStatus,
            notes: data.notes || null
          }
        );
      }

      const updatedEncounter = await tx.encounter.update({
        where: { id: encounter.id },
        data: {
          extension_json: {
            ...(encounter.extension_json || {}),
            opd_flow: flow
          }
        }
      });

      return {
        encounter: updatedEncounter,
        transition: {
          action: 'PAY_CONSULTATION',
          stage_from: stageBefore,
          stage_to: flow.stage,
          provider_user_id: encounter.provider_user_id || null,
          occurred_at: new Date().toISOString()
        }
      };
    });
  } catch (error) {
    throwIfActiveOpdLockError(error);
    throw error;
  }

  createAuditLog({
    tenant_id: updatedResult.encounter.tenant_id,
    user_id: context.user_id,
    action: 'UPDATE',
    entity: 'opd_flow',
    entity_id: updatedResult.encounter.id,
    diff: { after: updatedResult.encounter },
    ip_address: context.ip_address
  }).catch(() => {});

  const snapshot = await getOpdFlowById(updatedResult.encounter.id);
  await publishOpdRealtimeUpdates({
    snapshot,
    transition: updatedResult.transition,
    context
  });
  return snapshot;
};

const recordVitals = async (id, data, context = {}) => {
  let updatedResult;
  try {
    updatedResult = await prisma.$transaction(async (tx) => {
      const encounter = await resolveEncounterByIdentifier(tx, id);
      if (!encounter) {
        throw new HttpError('errors.opd_flow.not_found', 404);
      }

      const flow = getOpdFlowState(encounter);
      ensureNonTerminalStage(flow);
      const stageBefore = flow.stage;

      // Triage is never gated on billing. Vitals may be recorded while the
      // consultation payment is pending, partial, unpaid or awaiting approval;
      // the outstanding balance stays on the flow for Reception/Billing to act
      // on. Vitals are likewise accepted at any open stage so a nurse can chart
      // before, during or after the consultation.
      const isVitalsUpdate = data.update_existing === true;

      const normalizedVitals = data.vitals.map((vital) => {
        const normalizedVital = normalizeVitalForPersistence(vital);
        return {
          encounter_id: encounter.id,
          vital_type: normalizedVital.vital_type,
          value: normalizedVital.value,
          systolic_value: normalizedVital.systolic_value,
          diastolic_value: normalizedVital.diastolic_value,
          map_value: normalizedVital.map_value,
          unit: vital.unit || null,
          recorded_at: vital.recorded_at ? new Date(vital.recorded_at) : new Date()
        };
      });

      const savedVitals = [];
      if (
        typeof tx?.vital_sign?.findFirst === 'function' &&
        typeof tx?.vital_sign?.update === 'function' &&
        typeof tx?.vital_sign?.create === 'function'
      ) {
        for (const vitalData of normalizedVitals) {
          const existingVital = await tx.vital_sign.findFirst({
            where: {
              encounter_id: encounter.id,
              vital_type: vitalData.vital_type,
              deleted_at: null
            },
            orderBy: { recorded_at: 'desc' }
          });
          const savedVital = existingVital
            ? await tx.vital_sign.update({
                where: { id: existingVital.id },
                data: vitalData
              })
            : await tx.vital_sign.create({ data: vitalData });
          savedVitals.push(savedVital);
        }
      } else if (typeof tx?.vital_sign?.create === 'function') {
        for (const vitalData of normalizedVitals) {
          const created = await tx.vital_sign.create({ data: vitalData });
          savedVitals.push(created);
        }
      } else {
        await tx.vital_sign.createMany({ data: normalizedVitals });
      }

      const requestedTriageValue = data.triage_priority || data.triage_level;
      const triageLevel = mapTriageLevel(requestedTriageValue);
      if (requestedTriageValue && !triageLevel) {
        throw new HttpError('errors.opd_flow.invalid_stage_transition', 400, [{ field: 'triage_level' }]);
      }

      if (triageLevel) {
        flow.triage_level = triageLevel;
        flow.triage_priority = triageLevel;
      }
      const chiefComplaint = normalizeNotes(data.chief_complaint);
      if (chiefComplaint) {
        flow.chief_complaint = chiefComplaint;
      }
      const triageNotes = normalizeNotes(data.triage_notes);
      if (triageNotes) {
        flow.triage_notes = triageNotes;
      }
      if (data.emergency === true) {
        flow.emergency_indicator = true;
      }

      if (flow.emergency_case_id && (triageLevel || triageNotes)) {
        if (flow.triage_assessment_id) {
          await tx.triage_assessment.update({
            where: { id: flow.triage_assessment_id },
            data: {
              triage_level: triageLevel || undefined,
              notes: triageNotes || undefined
            }
          });
        } else if (triageLevel) {
          const triageAssessment = await tx.triage_assessment.create({
            data: {
              emergency_case_id: flow.emergency_case_id,
              triage_level: triageLevel,
              notes: triageNotes
            }
          });
          flow.triage_assessment_id = triageAssessment.id;
        }
      }

      if (PRE_CONSULTATION_STAGES.has(flow.stage)) {
        setFlowStage(flow, resolvePostVitalsStage(encounter));
      }
      appendTimelineEvent(flow, isVitalsUpdate ? 'VITALS_UPDATED' : 'VITALS_RECORDED', context, {
        vitals_count: data.vitals.length,
        triage_level: data.triage_level || null
      });

      if (flow.visit_queue_id) {
        await tx.visit_queue.update({
          where: { id: flow.visit_queue_id },
          data: { status: 'IN_PROGRESS' }
        });
      }

      const updatedEncounter = await tx.encounter.update({
        where: { id: encounter.id },
        data: {
          extension_json: {
            ...(encounter.extension_json || {}),
            opd_flow: flow
          }
        }
      });

      return {
        encounter: updatedEncounter,
        saved_vitals: savedVitals,
        transition: {
          action: 'RECORD_VITALS',
          stage_from: stageBefore,
          stage_to: flow.stage,
          provider_user_id: encounter.provider_user_id || null,
          occurred_at: new Date().toISOString()
        }
      };
    });
  } catch (error) {
    throwIfActiveOpdLockError(error);
    throw error;
  }

  createAuditLog({
    tenant_id: updatedResult.encounter.tenant_id,
    user_id: context.user_id,
    action: 'UPDATE',
    entity: 'opd_flow',
    entity_id: updatedResult.encounter.id,
    diff: { after: updatedResult.encounter },
    ip_address: context.ip_address
  }).catch(() => {});

  let snapshot = await getOpdFlowById(updatedResult.encounter.id);
  const savedVitals = Array.isArray(updatedResult.saved_vitals) ? updatedResult.saved_vitals : [];
  if (savedVitals.length > 0) {
    await Promise.all(
      savedVitals.map((vital) =>
        clinicalAlertThresholdService
          .evaluateVitalAndCreateAlerts(
            {
              vitalSign: vital,
              encounter: snapshot?.encounter || updatedResult.encounter,
              patient: snapshot?.encounter?.patient || null
            },
            {
              user_id: context.user_id,
              ip_address: context.ip_address
            }
          )
          .catch(() => null)
      )
    );
    snapshot = await getOpdFlowById(updatedResult.encounter.id);
  }
  await publishOpdRealtimeUpdates({
    snapshot,
    transition: updatedResult.transition,
    context
  });
  return snapshot;
};

const assignDoctor = async (id, data, context = {}) => {
  const updatedResult = await prisma.$transaction(async (tx) => {
    const encounter = await resolveEncounterByIdentifier(tx, id);
    if (!encounter) {
      throw new HttpError('errors.opd_flow.not_found', 404);
    }

    const flow = getOpdFlowState(encounter);
    ensureNonTerminalStage(flow);
    const stageBefore = flow.stage;

    const provider = await resolveProviderByIdentifier(
      tx,
      data.provider_user_id,
      encounter.tenant_id,
      encounter.facility_id
    );
    if (!provider) {
      throw new HttpError('errors.user.not_found', 404, [{ field: 'provider_user_id' }]);
    }
    ensureDoctorAssignable(provider);

    const feeDefaults = await resolveConsultationFeeDefaults(tx, {
      provider,
      tenantId: encounter.tenant_id,
      facilityId: encounter.facility_id
    });
    const consultation = { ...(flow.consultation || {}) };
    const currency = normalizeCurrencyCode(
      feeDefaults.consultationCurrency || consultation.currency,
      'USD'
    );
    if (feeDefaults.consultationFee) {
      consultation.consultation_fee = feeDefaults.consultationFee;
    }
    consultation.currency = currency;

    const consultationCatalogItemId =
      provider?.staff_profile?.id || encounter.facility_id || null;
    const requiresInvoice =
      consultation.require_payment !== false &&
      Boolean(consultation.consultation_fee);

    let invoice = consultation.invoice_id
      ? await tx.invoice.findFirst({
          where: { id: consultation.invoice_id, deleted_at: null }
        })
      : null;

    if (requiresInvoice) {
      const existingSnapshot =
        consultation.billing ||
        (consultation.invoice_id ? { invoice_id: consultation.invoice_id } : null);
      const billingPayload = buildConsultationBillingPayload({
        consultationFee: consultation.consultation_fee || '0.00',
        currency,
        paymentStatus: consultation.require_payment !== false ? 'PENDING' : 'PENDING',
        catalogItemId: consultationCatalogItemId,
        payNow: null
      });

      if (billingPayload) {
        const snapshot = await persistConsultationBilling(tx, {
          encounterId: encounter.id,
          billing: billingPayload,
          existingSnapshot,
          tenantId: encounter.tenant_id,
          facilityId: encounter.facility_id,
          patientId: encounter.patient_id,
          encounterDisplayId: encounter.human_friendly_id || null,
          catalogItemId: consultationCatalogItemId,
          actorUserId: context.user_id || null,
          currency,
          description: 'Consultation fee',
          mutableUpdate: Boolean(existingSnapshot)
        });

        if (snapshot?.invoice_id) {
          invoice = await tx.invoice.findFirst({
            where: { id: snapshot.invoice_id, deleted_at: null },
            include: {
              payments: { where: { deleted_at: null }, orderBy: { created_at: 'desc' } }
            }
          });
          consultation.invoice_id = snapshot.invoice_id;
          consultation.billing = snapshot;
        }
      }
    }

    flow.consultation = consultation;

    const updated = await tx.encounter.update({
      where: { id: encounter.id },
      data: {
        provider_user_id: provider.id
      }
    });

    if (flow.visit_queue_id) {
      const visitQueue = await resolveVisitQueueByIdentifier(
        tx,
        flow.visit_queue_id,
        encounter.tenant_id,
        encounter.facility_id
      );
      if (visitQueue) {
        await tx.visit_queue.update({
          where: { id: visitQueue.id },
          data: {
            provider_user_id: provider.id,
            status: 'IN_PROGRESS'
          }
        });
      }
    }

    if (flow.stage === STAGES.WAITING_DOCTOR_ASSIGNMENT) {
      const invoiceCreated = Boolean(invoice && consultation.invoice_id);
      const paymentPending =
        invoiceCreated &&
        consultation.require_payment !== false &&
        !consultation.is_paid;
      setFlowStage(
        flow,
        paymentPending
          ? STAGES.WAITING_CONSULTATION_PAYMENT
          : STAGES.WAITING_DOCTOR_REVIEW
      );
      if (invoiceCreated) {
        appendTimelineEvent(flow, 'CONSULTATION_INVOICE_CREATED', context, {
          invoice_id: consultation.invoice_id
        });
      }
    }
    appendTimelineEvent(flow, 'DOCTOR_ASSIGNED', context, {
      provider_user_id: provider.id
    });

    const updatedEncounter = await tx.encounter.update({
      where: { id: updated.id },
      data: {
        extension_json: {
          ...(encounter.extension_json || {}),
          opd_flow: flow
        }
      }
    });

    return {
      encounter: updatedEncounter,
      consultationInvoiceId: flow.consultation?.invoice_id || null,
      consultationBillingMutated: Boolean(
        requiresInvoice && flow.consultation?.invoice_id
      ),
      transition: {
        action: 'ASSIGN_DOCTOR',
        stage_from: stageBefore,
        stage_to: flow.stage,
        provider_user_id: provider.id,
        occurred_at: new Date().toISOString()
      }
    };
  });

  createAuditLog({
    tenant_id: updatedResult.encounter.tenant_id,
    user_id: context.user_id,
    action: 'UPDATE',
    entity: 'opd_flow',
    entity_id: updatedResult.encounter.id,
    diff: { after: updatedResult.encounter },
    ip_address: context.ip_address
  }).catch(() => {});

  const snapshot = await getOpdFlowById(updatedResult.encounter.id);
  await publishOpdRealtimeUpdates({
    snapshot,
    transition: updatedResult.transition,
    context
  });
  if (
    updatedResult.consultationBillingMutated &&
    updatedResult.consultationInvoiceId
  ) {
    await publishConsultationBillingRealtime({
      snapshot,
      context,
      mode: 'issued'
    });
  }
  return snapshot;
};

const doctorReview = async (id, data, context = {}) => {
  const updatedResult = await prisma.$transaction(async (tx) => {
    const encounter = await resolveEncounterByIdentifier(tx, id);
    if (!encounter) {
      throw new HttpError('errors.opd_flow.not_found', 404);
    }

    const flow = getOpdFlowState(encounter);
    ensureNonTerminalStage(flow);
    const stageBefore = flow.stage;

    // A clinician may attend any open visit: before payment, before vitals and
    // before anybody has been formally assigned. Pre-consultation stages are
    // pulled forward to doctor review instead of being rejected, so no patient
    // is stranded waiting for an administrative step.
    if (PRE_CONSULTATION_STAGES.has(flow.stage)) {
      setFlowStage(flow, STAGES.WAITING_DOCTOR_REVIEW);
    }

    const authorUserId = context.user_id || encounter.provider_user_id;
    if (!authorUserId) {
      throw new HttpError('errors.opd_flow.invalid_stage_transition', 400, [{ field: 'author_user_id' }]);
    }

    // The attending clinician claims an unassigned encounter by attending it.
    // The route already restricts this action to doctors/admins.
    const claimsUnassignedEncounter =
      !normalizeIdentifier(encounter.provider_user_id) && Boolean(normalizeIdentifier(context.user_id));
    if (claimsUnassignedEncounter) {
      encounter.provider_user_id = context.user_id;
      flow.provider_user_id = context.user_id;
      flow.attending_claimed_at = new Date().toISOString();
      appendTimelineEvent(flow, 'DOCTOR_SELF_ASSIGNED', context, {
        provider_user_id: context.user_id
      });
    }

    const noteText = typeof data.note === 'string' ? data.note.trim() : '';
    const isPlaceholderActionNote = (value) => {
      const normalized = String(value || '').trim().toLowerCase();
      if (!normalized) return true;
      return [
        'prescribe',
        'request procedure',
        'request lab',
        'order lab',
        'request radiology',
        'order radiology',
        'add diagnosis',
        'record diagnosis',
      ].includes(normalized);
    };

    // Persist only real clinical prose. Action labels like "Prescribe" belong
    // with pharmacy/lab/radiology orders, not the clinical notes section.
    let note = null;
    if (noteText && !isPlaceholderActionNote(noteText)) {
      note = await tx.clinical_note.create({
        data: {
          encounter_id: encounter.id,
          author_user_id: authorUserId,
          note: noteText,
        },
      });
    }

    if (Array.isArray(data.diagnoses) && data.diagnoses.length) {
      await tx.diagnosis.createMany({
        data: data.diagnoses.map((diagnosis) => ({
          encounter_id: encounter.id,
          diagnosis_type: diagnosis.diagnosis_type,
          code: diagnosis.code || null,
          description: diagnosis.description
        }))
      });
    }

    if (Array.isArray(data.procedures) && data.procedures.length) {
      await tx.procedure.createMany({
        data: data.procedures.map((procedure) => ({
          encounter_id: encounter.id,
          code: procedure.code || null,
          description: procedure.description,
          performed_at: procedure.performed_at ? new Date(procedure.performed_at) : null
        }))
      });
    }

    let labOrder = null;
    const resolvedLabRequests = [];
    if (Array.isArray(data.lab_requests) && data.lab_requests.length) {
      const seenLabTestIds = new Set();
      for (const [index, item] of data.lab_requests.entries()) {
        if (item.lab_test_id) {
          const labTest = await resolveLabTestRequest(tx, {
            identifier: item.lab_test_id,
            tenantId: encounter.tenant_id,
            context
          });
          if (!labTest) {
            throw new HttpError('errors.lab_test.not_found', 404, [{ field: `lab_requests.${index}.lab_test_id` }]);
          }

          if (!seenLabTestIds.has(labTest.id)) {
            seenLabTestIds.add(labTest.id);
            resolvedLabRequests.push({
              lab_test_id: labTest.id,
              status: item.status || 'ORDERED'
            });
          }
        }

        if (item.lab_panel_id) {
          const normalizedPanelId = normalizeIdentifier(item.lab_panel_id);
          const standardPanelCode = standardCatalogCodeFromIdentifier(normalizedPanelId, 'STD_LAB_PANEL');
          if (standardPanelCode) {
            const standardCodes = STANDARD_LAB_PANELS[standardPanelCode] || [];
            for (const standardCode of standardCodes) {
              const labTest = await resolveOrCreateStandardLabTest(tx, {
                identifier: `STD_LAB_TEST:${standardCode}`,
                tenantId: encounter.tenant_id,
                context
              });
              if (!labTest?.id || seenLabTestIds.has(labTest.id)) continue;
              seenLabTestIds.add(labTest.id);
              resolvedLabRequests.push({
                lab_test_id: labTest.id,
                status: item.status || 'ORDERED'
              });
            }
            continue;
          }

          const labPanel = normalizedPanelId
            ? await tx.lab_panel.findFirst({
                where: {
                  deleted_at: null,
                  tenant_id: encounter.tenant_id,
                  OR: isUuid(normalizedPanelId)
                    ? [{ id: normalizedPanelId }]
                    : [{ human_friendly_id: normalizedPanelId.toUpperCase() }]
                },
                include: LAB_PANEL_WITH_RELATIONS_INCLUDE
              })
            : null;

          if (!labPanel) {
            throw new HttpError('errors.lab_panel.not_found', 404, [{ field: `lab_requests.${index}.lab_panel_id` }]);
          }

          const panelItems = Array.isArray(labPanel.panel_items) ? labPanel.panel_items : [];
          panelItems.forEach((panelItem) => {
            const labTestId = panelItem?.lab_test_id || panelItem?.lab_test?.id;
            if (!labTestId || seenLabTestIds.has(labTestId)) return;
            seenLabTestIds.add(labTestId);
            resolvedLabRequests.push({
              lab_test_id: labTestId,
              status: item.status || 'ORDERED'
            });
          });
        }
      }

      if (resolvedLabRequests.length) {
        labOrder = await tx.lab_order.create({
          data: {
            encounter_id: encounter.id,
            patient_id: encounter.patient_id,
            status: 'ORDERED',
            ordered_at: new Date()
          }
        });

        await tx.lab_order_item.createMany({
          data: resolvedLabRequests.map((item) => ({
            lab_order_id: labOrder.id,
            lab_test_id: item.lab_test_id,
            status: item.status || 'ORDERED'
          }))
        });
      }
    }

    const radiologyOrderIds = [];
    if (Array.isArray(data.radiology_requests) && data.radiology_requests.length) {
      const orderedAt = new Date();
      const seenRadiologyProcedureIds = new Set();

      for (const [index, request] of data.radiology_requests.entries()) {
        let radiologyTestId = null;
        const radRequestId = request.radiology_procedure_id ?? request.radiology_test_id;
        if (radRequestId) {
          const radiologyTest = await resolveEntityByIdentifier(tx, 'radiology_procedure', radRequestId, {
            tenant_id: encounter.tenant_id
          });
          if (!radiologyTest) {
            throw new HttpError('errors.radiology_test.not_found', 404, [
              { field: `radiology_requests.${index}.radiology_test_id` }
            ]);
          }
          radiologyTestId = radiologyTest.id;
        }

        if (radiologyTestId) {
          if (seenRadiologyProcedureIds.has(radiologyTestId)) {
            throw new HttpError('errors.radiology_order.duplicate_request', 400, [
              { field: `radiology_requests.${index}.radiology_test_id` }
            ]);
          }
          seenRadiologyProcedureIds.add(radiologyTestId);
        }

        const radiologyOrder = await tx.radiology_order.create({
          data: {
            encounter_id: encounter.id,
            patient_id: encounter.patient_id,
            radiology_procedure_id: radiologyTestId,
            status: request.status || 'ORDERED',
            ordered_at: orderedAt
          }
        });
        radiologyOrderIds.push(radiologyOrder.id);
      }
    }

    let pharmacyOrder = null;
    const resolvedMedications = [];
    if (Array.isArray(data.medications) && data.medications.length) {
      for (const [index, medication] of data.medications.entries()) {
        const drug = await resolveEntityByIdentifier(tx, 'drug', medication.drug_id, {
          tenant_id: encounter.tenant_id
        });
        if (!drug) {
          throw new HttpError('errors.drug.not_found', 404, [{ field: `medications.${index}.drug_id` }]);
        }
        resolvedMedications.push({
          ...medication,
          drug_id: drug.id
        });
      }

      pharmacyOrder = await tx.pharmacy_order.create({
        data: {
          encounter_id: encounter.id,
          patient_id: encounter.patient_id,
          status: 'ORDERED',
          ordered_at: new Date()
        }
      });

      await tx.pharmacy_order_item.createMany({
        data: await Promise.all(
          resolvedMedications.map(async (medication) => {
            const row = {
              pharmacy_order_id: pharmacyOrder.id,
              drug_id: medication.drug_id,
              quantity: medication.quantity,
              dosage: medication.dosage || null,
              frequency: medication.frequency || null,
              route: medication.route || null,
              status: medication.status || 'ACTIVE'};
            // Nested/createMany paths do not always run HFID middleware — assign explicitly.
            await prisma.assignFriendlyIdIfMissing('pharmacy_order_item', row);
            return row;
          })
        )});
    }

    const hasLab = Boolean(labOrder);
    const hasRadiology = radiologyOrderIds.length > 0;
    const hasMedication = Boolean(pharmacyOrder);

    if (hasLab && hasRadiology) {
      setFlowStage(flow, STAGES.LAB_AND_RADIOLOGY_REQUESTED);
    } else if (hasLab) {
      setFlowStage(flow, STAGES.LAB_REQUESTED);
    } else if (hasRadiology) {
      setFlowStage(flow, STAGES.RADIOLOGY_REQUESTED);
    } else if (hasMedication) {
      setFlowStage(flow, STAGES.PHARMACY_REQUESTED);
    } else if (flow.stage === STAGES.WAITING_DOCTOR_REVIEW) {
      setFlowStage(flow, STAGES.WAITING_DISPOSITION);
    }

    flow.review_completed = true;
    if (note?.id) {
      flow.clinical_note_id = note.id;
    }
    if (labOrder) {
      flow.lab_order_ids = [labOrder.id];
    }
    if (radiologyOrderIds.length) {
      flow.radiology_order_ids = radiologyOrderIds;
    }
    if (pharmacyOrder) {
      flow.pharmacy_order_id = pharmacyOrder.id;
    }

    appendTimelineEvent(flow, 'DOCTOR_REVIEW_COMPLETED', context, {
      note_id: note?.id || null,
      diagnosis_count: Array.isArray(data.diagnoses) ? data.diagnoses.length : 0,
      procedure_count: Array.isArray(data.procedures) ? data.procedures.length : 0,
      lab_order_count: hasLab ? 1 : 0,
      radiology_order_count: radiologyOrderIds.length,
      medication_count: Array.isArray(data.medications) ? data.medications.length : 0,
      notes: data.notes || null
    });

    const updatedEncounter = await tx.encounter.update({
      where: { id: encounter.id },
      data: {
        ...(claimsUnassignedEncounter ? { provider_user_id: context.user_id } : {}),
        extension_json: {
          ...(encounter.extension_json || {}),
          opd_flow: flow
        }
      }
    });

    return {
      encounter: updatedEncounter,
      transition: {
        action: 'DOCTOR_REVIEW',
        stage_from: stageBefore,
        stage_to: flow.stage,
        provider_user_id: encounter.provider_user_id || authorUserId || null,
        occurred_at: new Date().toISOString()
      }
    };
  });

  createAuditLog({
    tenant_id: updatedResult.encounter.tenant_id,
    user_id: context.user_id,
    action: 'UPDATE',
    entity: 'opd_flow',
    entity_id: updatedResult.encounter.id,
    diff: { after: updatedResult.encounter },
    ip_address: context.ip_address
  }).catch(() => {});

  const snapshot = await getOpdFlowById(updatedResult.encounter.id);
  await publishOpdRealtimeUpdates({
    snapshot,
    transition: updatedResult.transition,
    context
  });
  return snapshot;
};

const disposition = async (id, data, context = {}) => {
  const dispositionAt = new Date();

  const updatedResult = await prisma.$transaction(async (tx) => {
    const encounter = await resolveEncounterByIdentifier(tx, id);
    if (!encounter) {
      throw new HttpError('errors.opd_flow.not_found', 404);
    }

    const flow = getOpdFlowState(encounter);
    ensureNonTerminalStage(flow);
    const stageBefore = flow.stage;
    const dispositionReason = normalizeNotes(data.reason);
    const dispositionNotes = normalizeNotes(data.notes);

    // A visit can legitimately end without a recorded consultation (patient
    // left, nurse-only visit, wrong queue). Rather than blocking the close, the
    // flow records that no review was captured so the audit trail stays honest.
    if (!flow.review_completed) {
      flow.closed_without_review = true;
      appendTimelineEvent(flow, 'DISPOSITION_WITHOUT_REVIEW', context, {
        decision: data.decision || null,
        stage_from: stageBefore
      });
    }

    let admission = null;
    let closeEncounter = data.decision === 'DISCHARGE';
    if (data.decision === 'ADMIT') {
      let admissionFacilityId = encounter.facility_id || null;
      if (data.admission_facility_id !== undefined) {
        if (data.admission_facility_id === null) {
          admissionFacilityId = null;
        } else {
          const resolvedFacility = await resolveFacilityByIdentifier(
            tx,
            data.admission_facility_id,
            encounter.tenant_id
          );
          if (!resolvedFacility) {
            throw new HttpError('errors.facility.not_found', 404, [{ field: 'admission_facility_id' }]);
          }
          admissionFacilityId = resolvedFacility.id;
        }
      }

      admission = await tx.admission.create({
        data: {
          tenant_id: encounter.tenant_id,
          facility_id: admissionFacilityId,
          patient_id: encounter.patient_id,
          encounter_id: encounter.id,
          status: 'REQUESTED',
          admitted_at: dispositionAt
        }
      });
      flow.admission_id = admission.id;
      flow.admission_pending = true;
      flow.admission_requested_at = dispositionAt.toISOString();
      setFlowStage(flow, STAGES.WAITING_DISPOSITION);
      closeEncounter = false;
    } else if (data.decision === 'SEND_TO_PHARMACY') {
      if (!flow.pharmacy_order_id) {
        throw new HttpError('errors.opd_flow.pharmacy_order_required_for_disposition', 400);
      }
      flow.pharmacy_pending_after_disposition = true;
      setFlowStage(flow, STAGES.PHARMACY_REQUESTED);
      closeEncounter = false;
    } else if (data.decision === 'REFER_PHYSIOTHERAPY') {
      const therapyFlowService = require('@services/therapy-flow/therapy-flow.service');
      const therapyEpisode = await therapyFlowService.createTherapyReferralInternal(
        tx,
        {
          encounter_id: encounter.id,
          source_kind: 'OPD',
          source_id: encounter.id,
          source_title: 'OPD visit',
          referral_reason: dispositionReason,
          notes: dispositionNotes},
        context
      );
      flow.therapy_episode_id = therapyEpisode.id;
      flow.physiotherapy_referral_id = therapyEpisode.id;
      setFlowStage(flow, STAGES.WAITING_DISPOSITION);
      closeEncounter = false;
    } else {
      setFlowStage(flow, STAGES.DISCHARGED);
    }

    flow.disposition_decision = data.decision;
    flow.disposition_reason = dispositionReason;
    flow.disposition_notes = dispositionNotes;
    flow.disposition_at = dispositionAt.toISOString();

    appendTimelineEvent(flow, 'DISPOSITION_RECORDED', context, {
      decision: data.decision,
      admission_id: admission?.id || null,
      pharmacy_order_id: flow.pharmacy_order_id || null,
      reason: dispositionReason,
      notes: dispositionNotes
    });

    const finalizedEncounter = await tx.encounter.update({
      where: { id: encounter.id },
      data: {
        ...(closeEncounter
          ? {
              status: 'CLOSED',
              active_opd_lock_key: null,
              ended_at: dispositionAt
            }
          : {
              status: 'OPEN',
              ended_at: null
            }),
        extension_json: {
          ...(encounter.extension_json || {}),
          opd_flow: flow
        }
      }
    });

    if (closeEncounter && flow.visit_queue_id) {
      await tx.visit_queue.update({
        where: { id: flow.visit_queue_id },
        data: {
          status: 'COMPLETED'
        }
      });
    }

    if (closeEncounter && flow.appointment_id) {
      const appointment = await tx.appointment.findFirst({
        where: { id: flow.appointment_id, deleted_at: null }
      });
      if (appointment && appointment.status !== 'CANCELLED' && appointment.status !== 'NO_SHOW') {
        await tx.appointment.update({
          where: { id: appointment.id },
          data: { status: 'COMPLETED' }
        });
      }
    }

    if (closeEncounter && flow.emergency_case_id) {
      await tx.emergency_case.update({
        where: { id: flow.emergency_case_id },
        data: {
          status: 'CLOSED'
        }
      });
    }

    return {
      encounter: finalizedEncounter,
      admission_id: admission?.id || null,
      transition: {
        action: 'DISPOSITION',
        stage_from: stageBefore,
        stage_to: flow.stage,
        provider_user_id: encounter.provider_user_id || null,
        occurred_at: dispositionAt.toISOString()
      }
    };
  });

  createAuditLog({
    tenant_id: updatedResult.encounter.tenant_id,
    user_id: context.user_id,
    action: 'UPDATE',
    entity: 'opd_flow',
    entity_id: updatedResult.encounter.id,
    diff: { after: updatedResult.encounter },
    ip_address: context.ip_address
  }).catch(() => {});

  const snapshot = await getOpdFlowById(updatedResult.encounter.id);
  await publishOpdRealtimeUpdates({
    snapshot,
    transition: updatedResult.transition,
    context
  });

  if (updatedResult.admission_id) {
    try {
      const ipdFlowService = require('@services/ipd-flow/ipd-flow.service');
      await ipdFlowService.emitAdmissionRefreshEvent(updatedResult.admission_id, context);
    } catch (_error) {
      // OPD disposition should not fail when IPD realtime fan-out fails.
    }
  }

  return snapshot;
};

const finalizeEncounterClosure = async (tx, encounter, flow, closedAt, encounterStatus) => {
  if (flow.visit_queue_id) {
    await tx.visit_queue.update({
      where: { id: flow.visit_queue_id },
      data: {
        status: encounterStatus === 'CANCELLED' ? 'CANCELLED' : 'COMPLETED'
      }
    });
  }

  if (flow.appointment_id) {
    const appointment = await tx.appointment.findFirst({
      where: { id: flow.appointment_id, deleted_at: null }
    });
    if (appointment && appointment.status !== 'CANCELLED' && appointment.status !== 'NO_SHOW') {
      await tx.appointment.update({
        where: { id: appointment.id },
        data: {
          status: encounterStatus === 'CANCELLED' ? 'NO_SHOW' : 'COMPLETED'
        }
      });
    }
  }

  if (flow.emergency_case_id) {
    await tx.emergency_case.update({
      where: { id: flow.emergency_case_id },
      data: {
        status: encounterStatus === 'CANCELLED' ? 'CANCELLED' : 'CLOSED'
      }
    });
  }

  const consultationInvoiceId = flow.consultation?.invoice_id || null;
  if (consultationInvoiceId) {
    await cancelInvoiceIfReversible(tx, consultationInvoiceId);
  }

  return tx.encounter.update({
    where: { id: encounter.id },
    data: {
      status: encounterStatus,
      active_opd_lock_key: null,
      ended_at: closedAt,
      extension_json: {
        ...(encounter.extension_json || {}),
        opd_flow: flow
      }
    }
  });
};

const cancelEncounter = async (id, data, context = {}) => {
  const cancelledAt = new Date();
  const reasonCode = normalizeIdentifier(data.reason_code).toUpperCase();
  const reasonNotes = normalizeNotes(data.reason_notes);
  if (reasonCode === 'OTHER' && !reasonNotes) {
    throw new HttpError('errors.validation.required', 400, [{ field: 'reason_notes' }]);
  }

  const updatedResult = await prisma.$transaction(async (tx) => {
    const encounter = await resolveEncounterByIdentifier(tx, id);
    if (!encounter) {
      throw new HttpError('errors.opd_flow.not_found', 404);
    }

    const encounterStatus = normalizeStatus(encounter.status);
    if (encounterStatus === 'CANCELLED' || encounterStatus === 'CLOSED') {
      throw new HttpError('errors.opd_flow.already_terminal', 400);
    }

    const flow = getOpdFlowState(encounter);
    ensureNonTerminalStage(flow);
    const stageBefore = flow.stage;

    flow.cancellation_reason_code = reasonCode;
    flow.cancellation_reason_notes = reasonNotes;
    flow.cancelled_at = cancelledAt.toISOString();

    appendTimelineEvent(flow, 'ENCOUNTER_CANCELLED', context, {
      reason_code: reasonCode,
      reason_notes: reasonNotes
    });

    const finalizedEncounter = await finalizeEncounterClosure(
      tx,
      encounter,
      flow,
      cancelledAt,
      'CANCELLED'
    );

    return {
      encounter: finalizedEncounter,
      transition: {
        action: 'ENCOUNTER_CANCELLED',
        stage_from: stageBefore,
        stage_to: flow.stage,
        provider_user_id: encounter.provider_user_id || null,
        occurred_at: cancelledAt.toISOString()
      }
    };
  });

  createAuditLog({
    tenant_id: updatedResult.encounter.tenant_id,
    user_id: context.user_id,
    action: 'UPDATE',
    entity: 'opd_flow',
    entity_id: updatedResult.encounter.id,
    diff: { after: updatedResult.encounter },
    ip_address: context.ip_address
  }).catch(() => {});

  const consultationInvoiceId =
    updatedResult.encounter?.extension_json?.opd_flow?.consultation?.invoice_id ||
    null;

  const snapshot = await getOpdFlowById(updatedResult.encounter.id);
  await publishOpdRealtimeUpdates({
    snapshot,
    transition: updatedResult.transition,
    context
  });
  if (consultationInvoiceId) {
    await publishConsultationBillingRealtime({
      snapshot,
      context,
      mode: 'cancelled',
      invoiceId: consultationInvoiceId
    });
  }
  return snapshot;
};

const closeEncounter = async (id, data, context = {}) => {
  const closedAt = new Date();
  const reasonNotes = normalizeNotes(data.reason_notes);

  const updatedResult = await prisma.$transaction(async (tx) => {
    const encounter = await resolveEncounterByIdentifier(tx, id);
    if (!encounter) {
      throw new HttpError('errors.opd_flow.not_found', 404);
    }

    const encounterStatus = normalizeStatus(encounter.status);
    if (encounterStatus === 'CANCELLED' || encounterStatus === 'CLOSED') {
      throw new HttpError('errors.opd_flow.already_terminal', 400);
    }

    const flow = getOpdFlowState(encounter);
    ensureNonTerminalStage(flow);
    const stageBefore = flow.stage;

    setFlowStage(flow, STAGES.DISCHARGED);
    flow.closed_early = true;
    flow.close_reason_notes = reasonNotes;
    flow.closed_at = closedAt.toISOString();

    appendTimelineEvent(flow, 'ENCOUNTER_CLOSED', context, {
      reason_notes: reasonNotes
    });

    const finalizedEncounter = await finalizeEncounterClosure(
      tx,
      encounter,
      flow,
      closedAt,
      'CLOSED'
    );

    return {
      encounter: finalizedEncounter,
      transition: {
        action: 'ENCOUNTER_CLOSED',
        stage_from: stageBefore,
        stage_to: flow.stage,
        provider_user_id: encounter.provider_user_id || null,
        occurred_at: closedAt.toISOString()
      }
    };
  });

  createAuditLog({
    tenant_id: updatedResult.encounter.tenant_id,
    user_id: context.user_id,
    action: 'UPDATE',
    entity: 'opd_flow',
    entity_id: updatedResult.encounter.id,
    diff: { after: updatedResult.encounter },
    ip_address: context.ip_address
  }).catch(() => {});

  const consultationInvoiceId =
    updatedResult.encounter?.extension_json?.opd_flow?.consultation?.invoice_id ||
    null;

  const snapshot = await getOpdFlowById(updatedResult.encounter.id);
  await publishOpdRealtimeUpdates({
    snapshot,
    transition: updatedResult.transition,
    context
  });
  if (consultationInvoiceId) {
    await publishConsultationBillingRealtime({
      snapshot,
      context,
      mode: 'cancelled',
      invoiceId: consultationInvoiceId
    });
  }
  return snapshot;
};

const getBillingDefaults = async (filters = {}, context = {}) => {
  const tenantId = filters.tenant_id || context.tenant_id || null;
  const facilityId = filters.facility_id || context.facility_id || null;

  return prisma.$transaction(async (tx) => {
    const standardDefaults = await resolveStandardConsultationFee(tx, tenantId, facilityId);
    const defaultCurrency = await resolveDefaultCurrency(tx, tenantId, facilityId);
    return {
      standard_consultation_fee: standardDefaults.consultationFee,
      standard_consultation_currency:
        standardDefaults.consultationCurrency || defaultCurrency,
      default_currency: defaultCurrency
    };
  });
};

const correctStage = async (id, data, context = {}) => {
  const reason = String(data?.reason || '').trim();

  const stageTo = String(data?.stage_to || '').trim();
  if (!WORKFLOW_STAGE_SET.has(stageTo)) {
    throw new HttpError('errors.validation.invalid', 400, [{ field: 'stage_to' }]);
  }

  const correctedAt = new Date();

  let updatedResult;
  try {
    updatedResult = await prisma.$transaction(async (tx) => {
      const encounter = await resolveEncounterByIdentifier(tx, id, {
        include: STAGE_CORRECTION_ENCOUNTER_INCLUDE
      });
      if (!encounter) {
        throw new HttpError('errors.opd_flow.not_found', 404);
      }

      const flow = getOpdFlowState(encounter);
      const stageBefore = flow.stage || null;
      if (stageBefore === stageTo) {
        throw new HttpError('errors.opd_flow.invalid_stage_transition', 400, [{ field: 'stage_to' }]);
      }
      if (!isEligibleStageCorrectionTarget(stageTo, encounter, flow)) {
        throw new HttpError('errors.opd_flow.invalid_stage_transition', 400, [{ field: 'stage_to' }]);
      }
      if (stageCorrectionRequiresReason(stageBefore, stageTo) && !reason) {
        throw new HttpError('errors.validation.required', 400, [{ field: 'reason' }]);
      }

      setFlowStage(flow, stageTo);
      const isTerminalStage = TERMINAL_STAGES.has(stageTo);
      appendTimelineEvent(
        flow,
        'STAGE_CORRECTED',
        context,
        {
          stage_from: stageBefore,
          stage_to: stageTo,
          ...(reason ? { reason } : {})
        },
        correctedAt
      );

      if (stageTo === STAGES.WAITING_CONSULTATION_PAYMENT) {
        const consultation = flow.consultation || {};
        consultation.require_payment = true;
        flow.consultation = consultation;
        await ensureUnpaidConsultationInvoiceForPaymentDue(tx, {
          encounter,
          flow,
          catalogItemId: encounter.provider?.staff_profile?.id || encounter.facility_id || null,
          context,
          issuedAt: correctedAt
        });
      }

      const updatedEncounter = await tx.encounter.update({
        where: { id: encounter.id },
        data: {
          status: isTerminalStage ? 'CLOSED' : 'OPEN',
          active_opd_lock_key: isTerminalStage
            ? null
            : activeOpdLockKeyForEncounter({
                ...encounter,
                status: 'OPEN'
              }),
          ended_at: isTerminalStage ? encounter.ended_at || correctedAt : null,
          extension_json: {
            ...(encounter.extension_json || {}),
            opd_flow: flow
          }
        }
      });

      if (flow.visit_queue_id) {
        await tx.visit_queue.update({
          where: { id: flow.visit_queue_id },
          data: {
            status: isTerminalStage ? 'COMPLETED' : 'IN_PROGRESS'
          }
        });
      }

      if (flow.appointment_id) {
        const appointment = await tx.appointment.findFirst({
          where: { id: flow.appointment_id, deleted_at: null }
        });
        if (appointment && appointment.status !== 'CANCELLED' && appointment.status !== 'NO_SHOW') {
          await tx.appointment.update({
            where: { id: appointment.id },
            data: { status: isTerminalStage ? 'COMPLETED' : 'IN_PROGRESS' }
          });
        }
      }

      return {
        encounter: updatedEncounter,
        stageBefore,
        stageAfter: stageTo,
        consultationInvoiceId: flow.consultation?.invoice_id || null,
        consultationBillingMutated:
          stageTo === STAGES.WAITING_CONSULTATION_PAYMENT &&
          Boolean(flow.consultation?.invoice_id),
        transition: {
          action: 'STAGE_CORRECTED',
          stage_from: stageBefore,
          stage_to: stageTo,
          provider_user_id: encounter.provider_user_id || null,
          occurred_at: correctedAt.toISOString()
        }
      };
    });
  } catch (error) {
    throwIfActiveOpdLockError(error);
    throw error;
  }

  createAuditLog({
    tenant_id: updatedResult.encounter.tenant_id,
    user_id: context.user_id,
    action: 'UPDATE',
    entity: 'opd_flow',
    entity_id: updatedResult.encounter.id,
    diff: {
      before: {
        stage: updatedResult.stageBefore
      },
      after: {
        stage: updatedResult.stageAfter
      },
      reason,
      actor_user_id: context.user_id || null
    },
    ip_address: context.ip_address
  }).catch(() => {});

  const snapshot = await getOpdFlowById(updatedResult.encounter.id);
  await publishOpdRealtimeUpdates({
    snapshot,
    transition: updatedResult.transition,
    context
  });
  if (
    updatedResult.consultationBillingMutated &&
    updatedResult.consultationInvoiceId
  ) {
    await publishConsultationBillingRealtime({
      snapshot,
      context,
      mode: 'issued'
    });
  }
  return snapshot;
};

/**
 * Diagnostics stage orchestration
 *
 * Lab/Radiology workspaces execute and report on orders but must not mutate OPD
 * stages from their own UI/services. Instead, when diagnostic work completes they
 * call `syncDiagnosticsStage(encounterId)` so the OPD orchestrator can advance the
 * encounter out of the `LAB_REQUESTED` / `LAB_AND_RADIOLOGY_REQUESTED` /
 * `RADIOLOGY_REQUESTED` holding stages once the relevant diagnostics are done.
 *
 * The hook is intentionally forward-only and a no-op unless the encounter is an
 * OPD/EMERGENCY encounter currently parked in a diagnostics stage, so it is safe
 * to call after any lab/radiology mutation (including for IPD orders, which never
 * resolve to an OPD encounter here).
 */
const DIAGNOSTICS_SYNC_FLOW_STAGES = new Set([
  STAGES.LAB_REQUESTED,
  STAGES.LAB_AND_RADIOLOGY_REQUESTED,
  STAGES.RADIOLOGY_REQUESTED
]);

const DIAGNOSTICS_SYNC_ENCOUNTER_INCLUDE = {
  provider: PROVIDER_INCLUDE,
  vital_signs: { where: { deleted_at: null } },
  admissions: {
    where: { deleted_at: null },
    orderBy: { created_at: 'desc' },
    include: { bed_assignments: { where: { deleted_at: null } } }
  },
  lab_orders: {
    where: { deleted_at: null },
    include: {
      items: {
        where: { deleted_at: null },
        include: { results: { where: { deleted_at: null } } }
      },
      samples: { where: { deleted_at: null } }
    }
  },
  radiology_orders: {
    where: { deleted_at: null },
    include: {
      results: { where: { deleted_at: null } },
      imaging_studies: { where: { deleted_at: null } }
    }
  },
  pharmacy_orders: {
    where: { deleted_at: null },
    include: {
      items: {
        where: { deleted_at: null },
        include: { dispense_logs: { where: { deleted_at: null } } }
      }
    }
  }
};

const resolveDiagnosticsSyncStage = (encounter) => {
  const labState = resolveLabState(encounter?.lab_orders);
  const radiologyState = resolveRadiologyState(encounter?.radiology_orders);
  const pharmacyState = resolvePharmacyState(encounter?.pharmacy_orders);

  if (labState.pending && radiologyState.pending) return STAGES.LAB_AND_RADIOLOGY_REQUESTED;
  if (labState.pending) return STAGES.LAB_REQUESTED;
  if (radiologyState.pending) return STAGES.RADIOLOGY_REQUESTED;
  if (pharmacyState.pending) return STAGES.PHARMACY_REQUESTED;
  return STAGES.WAITING_DISPOSITION;
};

const syncDiagnosticsStage = async (encounterId, context = {}) => {
  try {
    const normalized = normalizeIdentifier(encounterId);
    if (!normalized || !prisma?.$transaction) return null;

    const transition = await prisma.$transaction(async (tx) => {
      const encounter = await resolveEncounterByIdentifier(tx, normalized, {
        include: DIAGNOSTICS_SYNC_ENCOUNTER_INCLUDE
      });
      if (!encounter) return null;

      const flow = encounter.extension_json?.opd_flow;
      if (!flow || typeof flow !== 'object') return null;

      const stageBefore = flow.stage || null;
      if (!DIAGNOSTICS_SYNC_FLOW_STAGES.has(stageBefore)) return null;
      if (TERMINAL_STAGES.has(stageBefore)) return null;

      const nextStage = resolveDiagnosticsSyncStage(encounter);
      if (!nextStage || nextStage === stageBefore) return null;

      setFlowStage(flow, nextStage);
      appendTimelineEvent(flow, 'DIAGNOSTICS_STAGE_SYNCED', context, {
        stage_from: stageBefore,
        stage_to: nextStage,
        trigger: context.trigger || 'DIAGNOSTICS_UPDATED'
      });

      const updatedEncounter = await tx.encounter.update({
        where: { id: encounter.id },
        data: {
          extension_json: {
            ...(encounter.extension_json || {}),
            opd_flow: flow
          }
        }
      });

      return {
        encounterId: updatedEncounter.id,
        stage_from: stageBefore,
        stage_to: nextStage
      };
    });

    if (!transition) return null;

    const snapshot = await getOpdFlowById(transition.encounterId);
    await publishOpdRealtimeUpdates({
      snapshot,
      transition: {
        action: 'DIAGNOSTICS_STAGE_SYNCED',
        stage_from: transition.stage_from,
        stage_to: transition.stage_to,
        occurred_at: new Date().toISOString()
      },
      context
    });
    return snapshot;
  } catch (_err) {
    // Diagnostics orchestration must never break lab/radiology workflow responses.
    return null;
  }
};

/**
 * Resolve the OPD encounter that owns a consultation invoice.
 * Prefer billable_charge_event (authoritative), then JSON invoice_id match,
 * then open-patient scan. Invoice rows do not store encounter_id.
 */
const resolveEncounterForConsultationInvoice = async (tx, invoice) => {
  if (!invoice?.id || !tx?.encounter?.findFirst) {
    return null;
  }

  if (tx.billable_charge_event?.findFirst) {
    const chargeEvent = await tx.billable_charge_event.findFirst({
      where: {
        invoice_id: invoice.id,
        deleted_at: null,
        encounter_id: { not: null }
      },
      orderBy: { created_at: 'desc' },
      select: { encounter_id: true }
    });
    if (chargeEvent?.encounter_id) {
      const fromCharge = await resolveEncounterByIdentifier(tx, chargeEvent.encounter_id);
      if (fromCharge?.extension_json?.opd_flow) {
        return fromCharge;
      }
    }
  }

  // Legacy/test payloads may still carry encounter_id on the invoice object.
  if (invoice.encounter_id) {
    const fromInvoice = await resolveEncounterByIdentifier(tx, invoice.encounter_id);
    if (fromInvoice?.extension_json?.opd_flow) {
      return fromInvoice;
    }
  }

  const invoiceKeys = uniqueNormalizedIdentifiers([invoice.id, invoice.human_friendly_id]);
  if (invoiceKeys.length && tx.encounter?.findMany) {
    for (const key of invoiceKeys) {
      const matches = await tx.encounter.findMany({
        where: {
          deleted_at: null,
          tenant_id: invoice.tenant_id,
          ...(invoice.facility_id ? { facility_id: invoice.facility_id } : {}),
          extension_json: {
            path: '$.opd_flow.consultation.invoice_id',
            equals: key
          }
        },
        take: 5
      });
      const matched = matches.find((candidate) => candidate?.extension_json?.opd_flow) || null;
      if (matched) {
        return matched;
      }
    }
  }

  if (invoice.patient_id && tx.encounter?.findMany) {
    const openEncounters = await tx.encounter.findMany({
      where: {
        deleted_at: null,
        tenant_id: invoice.tenant_id,
        patient_id: invoice.patient_id,
        status: 'OPEN',
        encounter_type: { in: ['OPD', 'EMERGENCY'] },
        ...(invoice.facility_id ? { facility_id: invoice.facility_id } : {})
      },
      take: 25,
      orderBy: { started_at: 'desc' }
    });
    const keySet = new Set(invoiceKeys.map((key) => String(key).toUpperCase()));
    return (
      openEncounters.find((candidate) => {
        const linked = normalizeIdentifier(
          candidate?.extension_json?.opd_flow?.consultation?.invoice_id
        );
        return linked && keySet.has(linked.toUpperCase());
      }) || null
    );
  }

  return null;
};

/**
 * When Billing reconciles a payment against a consultation invoice, keep the
 * linked OPD flow consultation snapshot and Payment-due stage in sync.
 * Never throws into the billing reconcile path.
 */
const syncConsultationBillingFromInvoicePayment = async ({
  invoiceId = null,
  payment = null,
  context = {}} = {}) => {
  try {
    const normalizedInvoiceId = normalizeIdentifier(invoiceId);
    if (!normalizedInvoiceId) {
      return null;
    }

    const transition = await prisma.$transaction(async (tx) => {
      const invoice = await tx.invoice.findFirst({
        where: { id: normalizedInvoiceId, deleted_at: null }});
      if (!invoice) {
        return null;
      }

      const encounter = await resolveEncounterForConsultationInvoice(tx, invoice);
      if (!encounter?.extension_json?.opd_flow) {
        return null;
      }

      const flow = getOpdFlowState(encounter);
      if (TERMINAL_STAGES.has(flow.stage)) {
        return null;
      }

      const consultation = { ...(flow.consultation || {}) };
      const linkedInvoiceId = normalizeIdentifier(consultation.invoice_id);
      const invoiceKeys = new Set(
        [invoice.id, invoice.human_friendly_id]
          .map((value) => normalizeIdentifier(value).toUpperCase())
          .filter(Boolean)
      );
      if (
        linkedInvoiceId &&
        !invoiceKeys.has(linkedInvoiceId.toUpperCase()) &&
        flow.stage !== STAGES.WAITING_CONSULTATION_PAYMENT
      ) {
        return null;
      }

      const stageBefore = flow.stage;
      await applyConsultationBillingSnapshot(tx, {
        invoiceId: invoice.id,
        payment,
        consultation,
        currency: consultation.currency || invoice.currency || null,
        paymentStatus: payment?.status || null});
      flow.consultation = consultation;

      if (flow.stage === STAGES.WAITING_CONSULTATION_PAYMENT && consultation.is_paid) {
        setFlowStage(flow, STAGES.WAITING_VITALS);
      }

      appendTimelineEvent(flow, 'CONSULTATION_PAYMENT_RECORDED', context, {
        payment_id: payment?.id || null,
        invoice_id: invoice.id,
        amount: payment?.amount || null,
        status: payment?.status || null,
        source: 'BILLING_RECONCILE'});

      const updatedEncounter = await tx.encounter.update({
        where: { id: encounter.id },
        data: {
          extension_json: {
            ...(encounter.extension_json || {}),
            opd_flow: flow}}});

      return {
        encounterId: updatedEncounter.id,
        stage_from: stageBefore,
        stage_to: flow.stage};
    });

    if (!transition) {
      return null;
    }

    const snapshot = await getOpdFlowById(transition.encounterId);
    await publishOpdRealtimeUpdates({
      snapshot,
      transition: {
        action: 'PAY_CONSULTATION',
        stage_from: transition.stage_from,
        stage_to: transition.stage_to,
        occurred_at: new Date().toISOString()},
      context});
    return snapshot;
  } catch (_err) {
    // Billing reconcile must succeed even when OPD sync cannot run.
    return null;
  }
};

module.exports = {
  listOpdFlows,
  getOpdFlowSummaryCounts,
  resolveLegacyRoute,
  getOpdFlowById,
  bootstrapOpdFlow,
  startOpdFlow,
  updateActiveEncounterContext,
  payConsultation,
  recordVitals,
  assignDoctor,
  doctorReview,
  disposition,
  cancelEncounter,
  closeEncounter,
  getBillingDefaults,
  correctStage,
  syncDiagnosticsStage,
  syncConsultationBillingFromInvoicePayment};
