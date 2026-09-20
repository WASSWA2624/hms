/**
 * Triage service
 *
 * @module modules/triage/services
 * @description Triage queue orchestration for registered/scheduled patients.
 * Keeps database compatibility with the existing OPD encounter flow while
 * exposing Triage-facing workflow semantics.
 */

const prisma = require('@prisma/client');
const { createAuditLog } = require('@lib/audit');
const { HttpError } = require('@lib/errors');
const opdFlowService = require('@services/opd-flow/opd-flow.service');

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const OPD_FLOW_STAGE_JSON_PATH = '$.opd_flow.stage';
const MAX_SEARCH_TOKENS = 6;

const STAGES = Object.freeze({
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
});

// Triage does not wait for billing. Patients whose consultation payment is
// still outstanding stay visible in the triage queue so vitals can be taken
// while Reception/Billing settle the invoice in parallel.
const TRIAGE_QUEUE_STAGES = Object.freeze([
  STAGES.WAITING_CONSULTATION_PAYMENT,
  STAGES.WAITING_VITALS,
  STAGES.WAITING_DOCTOR_ASSIGNMENT
]);

const WORKFLOW_STAGE_SET = new Set(Object.values(STAGES));
const TERMINAL_STAGES = new Set([STAGES.ADMITTED, STAGES.DISCHARGED]);

const ROUTE_DESTINATIONS = Object.freeze({
  CONSULTATION: 'CONSULTATION',
  LAB: 'LAB',
  RADIOLOGY: 'RADIOLOGY',
  LAB_AND_RADIOLOGY: 'LAB_AND_RADIOLOGY',
  PHYSIOTHERAPY: 'PHYSIOTHERAPY',
  OTHER_SERVICE: 'OTHER_SERVICE',
  ADMIT: 'ADMIT',
  EMERGENCY: 'EMERGENCY',
  THEATRE: 'THEATRE',
  MINOR_PROCEDURE: 'MINOR_PROCEDURE',
  DISCHARGE: 'DISCHARGE'
});

const ROUTE_DESTINATION_SET = new Set(Object.values(ROUTE_DESTINATIONS));

const NEXT_STEP_BY_STAGE = Object.freeze({
  [STAGES.WAITING_CONSULTATION_PAYMENT]: 'Consultation payment is outstanding - triage can continue in parallel.',
  [STAGES.WAITING_VITALS]: 'Record vital signs and triage urgency.',
  [STAGES.WAITING_DOCTOR_ASSIGNMENT]: 'Assign patient to a provider or route to the right service.',
  [STAGES.WAITING_DOCTOR_REVIEW]: 'Provider consultation is ready to begin.',
  [STAGES.LAB_REQUESTED]: 'Lab request has been placed.',
  [STAGES.RADIOLOGY_REQUESTED]: 'Radiology request has been placed.',
  [STAGES.LAB_AND_RADIOLOGY_REQUESTED]: 'Lab and radiology requests have been placed.',
  [STAGES.PHARMACY_REQUESTED]: 'Pharmacy request has been placed.',
  [STAGES.WAITING_DISPOSITION]: 'Patient has been routed from triage.',
  [STAGES.ADMITTED]: 'Patient has been admitted.',
  [STAGES.DISCHARGED]: 'Patient has been discharged.'
});

const TRIAGE_ALIAS_MAP = Object.freeze({
  IMMEDIATE: 'LEVEL_1',
  URGENT: 'LEVEL_2',
  LESS_URGENT: 'LEVEL_3',
  NON_URGENT: 'LEVEL_4',
  LEVEL_1: 'LEVEL_1',
  LEVEL_2: 'LEVEL_2',
  LEVEL_3: 'LEVEL_3',
  LEVEL_4: 'LEVEL_4',
  LEVEL_5: 'LEVEL_5'
});

const TRIAGE_SEVERITY_MAP = Object.freeze({
  LEVEL_1: 'CRITICAL',
  LEVEL_2: 'HIGH',
  LEVEL_3: 'MEDIUM',
  LEVEL_4: 'LOW',
  LEVEL_5: 'LOW'
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
  }
};

const PROVIDER_INCLUDE = {
  select: PROVIDER_SELECT
};

const normalizeIdentifier = (value) => (typeof value === 'string' ? value.trim() : '');
const isUuid = (value) => UUID_REGEX.test(normalizeIdentifier(value));
const normalizeUpper = (value) => normalizeIdentifier(value).toUpperCase();
const normalizeRouteDestination = (value) => normalizeUpper(value);
const normalizeTriageLevel = (value) => TRIAGE_ALIAS_MAP[normalizeUpper(value)] || null;
const normalizeNotes = (value) => {
  const normalized = typeof value === 'string' ? value.trim() : '';
  return normalized || null;
};
const isElevatedContext = (context = {}) => Array.isArray(context.roles) && context.roles.includes('PLATFORM_ADMIN');

const assertEncounterScope = (encounter, context = {}) => {
  if (!encounter || isElevatedContext(context)) return;

  if (context.tenant_id && encounter.tenant_id !== context.tenant_id) {
    throw new HttpError('errors.auth.insufficient_permissions', 403);
  }

  if (context.facility_id && encounter.facility_id && encounter.facility_id !== context.facility_id) {
    throw new HttpError('errors.auth.insufficient_permissions', 403);
  }
};

const buildJsonStageFilter = (stage) => ({
  path: OPD_FLOW_STAGE_JSON_PATH,
  equals: stage
});

const buildStageOrFilter = (stages = TRIAGE_QUEUE_STAGES) => ({
  OR: stages.map((stage) => ({
    extension_json: buildJsonStageFilter(stage)
  }))
});

const normalizeSearchTokens = (search) =>
  String(search || '')
    .trim()
    .split(/\s+/)
    .map((token) => token.trim())
    .filter(Boolean)
    .slice(0, MAX_SEARCH_TOKENS);

const emptyPage = (page, limit) => ({
  items: [],
  pagination: {
    page,
    limit,
    total: 0,
    totalPages: 0,
    hasNextPage: false,
    hasPreviousPage: page > 1
  }
});

const getNextStep = (stage) => NEXT_STEP_BY_STAGE[stage] || null;

const setFlowStage = (flow, stage) => {
  flow.stage = stage;
  flow.next_step = getNextStep(stage);
};

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

const getOpdFlowState = (encounter) => {
  const flow = encounter?.extension_json?.opd_flow;
  if (!flow) {
    throw new HttpError('errors.opd_flow.not_found', 404);
  }
  return { ...flow };
};

const ensureNonTerminalStage = (flow) => {
  if (TERMINAL_STAGES.has(flow.stage)) {
    throw new HttpError('errors.opd_flow.already_terminal', 400);
  }
};

const resolveEntityByIdentifier = async (tx, modelName, identifier, where = {}, select = undefined) => {
  const normalized = normalizeIdentifier(identifier);
  if (!normalized) return null;
  const delegate = tx?.[modelName];
  if (!delegate?.findFirst) return null;

  return delegate.findFirst({
    where: {
      deleted_at: null,
      ...where,
      OR: isUuid(normalized) ? [{ id: normalized }] : [{ human_friendly_id: normalized.toUpperCase() }]
    },
    ...(select ? { select } : {})
  });
};

const resolveTenantByIdentifier = (tx, identifier) => resolveEntityByIdentifier(tx, 'tenant', identifier);

const resolveFacilityByIdentifier = (tx, identifier, tenantId = null) =>
  resolveEntityByIdentifier(tx, 'facility', identifier, {
    ...(tenantId ? { tenant_id: tenantId } : {})
  });

const resolvePatientByIdentifier = (tx, identifier, tenantId = null) =>
  resolveEntityByIdentifier(tx, 'patient', identifier, {
    ...(tenantId ? { tenant_id: tenantId } : {})
  });

const resolveDepartmentByIdentifier = (tx, identifier, tenantId = null, facilityId = null) =>
  resolveEntityByIdentifier(tx, 'department', identifier, {
    ...(tenantId ? { tenant_id: tenantId } : {}),
    ...(facilityId ? { facility_id: facilityId } : {})
  });

const resolveEncounterByIdentifier = async (tx, identifier, include = undefined) => {
  const normalized = normalizeIdentifier(identifier);
  if (!normalized) return null;

  return tx.encounter.findFirst({
    where: {
      deleted_at: null,
      encounter_type: { in: ['OPD', 'EMERGENCY'] },
      OR: isUuid(normalized)
        ? [{ id: normalized }]
        : [{ id: normalized }, { human_friendly_id: normalized.toUpperCase() }]
    },
    ...(include ? { include } : {})
  });
};

const resolveProviderLookupWhere = (identifier, tenantId = null, facilityId = null) => {
  const normalized = normalizeIdentifier(identifier);
  if (!normalized) return null;

  const where = {
    deleted_at: null,
    ...(tenantId ? { tenant_id: tenantId } : {}),
    ...(facilityId ? { facility_id: facilityId } : {})
  };

  if (isUuid(normalized)) {
    return {
      ...where,
      id: normalized
    };
  }

  const upper = normalized.toUpperCase();
  return {
    ...where,
    OR: [
      { human_friendly_id: upper },
      { email: normalized },
      { phone: normalized },
      { profile: { first_name: { contains: normalized } } },
      { profile: { middle_name: { contains: normalized } } },
      { profile: { last_name: { contains: normalized } } },
      { staff_profile: { human_friendly_id: { contains: upper } } },
      { staff_profile: { staff_number: { contains: normalized } } },
      { staff_profile: { practitioner_type: { contains: upper } } },
      { staff_profile: { position: { contains: normalized } } }
    ]
  };
};

const resolveProviderByIdentifier = async (tx, identifier, tenantId = null, facilityId = null) => {
  const normalized = normalizeIdentifier(identifier);
  if (!normalized) return null;

  const facilityScopedWhere = resolveProviderLookupWhere(identifier, tenantId, facilityId);
  const facilityProvider = facilityScopedWhere
    ? await tx.user.findFirst({
        where: facilityScopedWhere,
        select: PROVIDER_SELECT
      })
    : null;
  if (facilityProvider || !facilityId) return facilityProvider;

  const tenantScopedWhere = resolveProviderLookupWhere(identifier, tenantId, null);
  return tenantScopedWhere ? tx.user.findFirst({ where: tenantScopedWhere, select: PROVIDER_SELECT }) : null;
};

const buildSearchTokenClause = (token) => {
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
            some: { deleted_at: null, identifier_value: { contains: term } }
          }
        }
      },
      { provider: { email: { contains: term } } },
      { provider: { phone: { contains: term } } },
      { provider: { human_friendly_id: { contains: upper } } },
      { provider: { profile: { first_name: { contains: term } } } },
      { provider: { profile: { last_name: { contains: term } } } }
    ]
  };
};

const buildTriageQueueWhereClause = (filters = {}) => {
  const where = {
    deleted_at: null,
    status: 'OPEN',
    encounter_type: { in: ['OPD', 'EMERGENCY'] }
  };
  const andClauses = [{ patient: { deleted_at: null } }];

  if (filters.tenant_id) where.tenant_id = filters.tenant_id;
  if (filters.facility_id) where.facility_id = filters.facility_id;
  if (filters.patient_id) where.patient_id = filters.patient_id;
  if (filters.provider_user_id) where.provider_user_id = filters.provider_user_id;
  if (filters.encounter_type) where.encounter_type = filters.encounter_type;

  const requestedStage = normalizeUpper(filters.triage_status || filters.stage);
  if (requestedStage && WORKFLOW_STAGE_SET.has(requestedStage)) {
    andClauses.push({ extension_json: buildJsonStageFilter(requestedStage) });
  } else {
    andClauses.push(buildStageOrFilter(TRIAGE_QUEUE_STAGES));
  }

  const queueScope = normalizeUpper(filters.queue_scope || 'ALL');
  if (queueScope === 'ASSIGNED') {
    if (!filters.provider_user_id) {
      andClauses.push({ provider_user_id: { not: null } });
    }
  } else if (queueScope === 'WAITING') {
    andClauses.push({ provider_user_id: null });
  }

  const searchTokens = normalizeSearchTokens(filters.search);
  if (searchTokens.length > 0) {
    andClauses.push(...searchTokens.map(buildSearchTokenClause));
  }

  if (andClauses.length > 0) {
    where.AND = andClauses;
  }

  return where;
};

const resolveSortField = (sortBy) => {
  const normalized = normalizeIdentifier(sortBy);
  const allowed = new Set(['started_at', 'created_at', 'updated_at', 'human_friendly_id']);
  return allowed.has(normalized) ? normalized : 'started_at';
};

const toTimestamp = (value) => {
  if (!value) return Number.MAX_SAFE_INTEGER;
  const parsed = new Date(value).getTime();
  return Number.isFinite(parsed) ? parsed : Number.MAX_SAFE_INTEGER;
};

const resolveUrgencyRank = (level) => {
  const normalized = normalizeTriageLevel(level);
  if (normalized === 'LEVEL_1') return 1;
  if (normalized === 'LEVEL_2') return 2;
  if (normalized === 'LEVEL_3') return 3;
  if (normalized === 'LEVEL_4') return 4;
  if (normalized === 'LEVEL_5') return 5;
  return 9;
};

const sortTriageQueueItems = (items) =>
  items.sort((left, right) => {
    const leftFlow = left?.flow || {};
    const rightFlow = right?.flow || {};
    const levelDelta = resolveUrgencyRank(leftFlow.triage_level) - resolveUrgencyRank(rightFlow.triage_level);
    if (levelDelta !== 0) return levelDelta;

    const leftArrival = toTimestamp(leftFlow.queued_at || left?.visit_queue?.queued_at || left?.encounter?.started_at);
    const rightArrival = toTimestamp(
      rightFlow.queued_at || right?.visit_queue?.queued_at || right?.encounter?.started_at
    );
    if (leftArrival !== rightArrival) return leftArrival - rightArrival;

    return normalizeIdentifier(left?.encounter?.human_friendly_id || left?.encounter?.id).localeCompare(
      normalizeIdentifier(right?.encounter?.human_friendly_id || right?.encounter?.id)
    );
  });

const hydrateQueueSnapshots = async (tx, encounters = []) => {
  if (!Array.isArray(encounters) || encounters.length === 0) return [];

  const flows = encounters.map((encounter) => getOpdFlowState(encounter));
  const visitQueueIds = flows.map((flow) => flow.visit_queue_id).filter(Boolean);
  const appointmentIds = flows.map((flow) => flow.appointment_id).filter(Boolean);
  const emergencyCaseIds = flows.map((flow) => flow.emergency_case_id).filter(Boolean);
  const triageAssessmentIds = flows.map((flow) => flow.triage_assessment_id).filter(Boolean);

  const [visitQueues, appointments, emergencyCases, triageAssessments] = await Promise.all([
    visitQueueIds.length
      ? tx.visit_queue.findMany({
          where: { id: { in: visitQueueIds }, deleted_at: null },
          include: {
            provider: PROVIDER_INCLUDE,
            facility: true,
            appointment: true
          }
        })
      : [],
    appointmentIds.length
      ? tx.appointment.findMany({
          where: { id: { in: appointmentIds }, deleted_at: null },
          include: { provider: PROVIDER_INCLUDE, facility: true }
        })
      : [],
    emergencyCaseIds.length
      ? tx.emergency_case.findMany({
          where: { id: { in: emergencyCaseIds }, deleted_at: null }
        })
      : [],
    triageAssessmentIds.length
      ? tx.triage_assessment.findMany({
          where: { id: { in: triageAssessmentIds }, deleted_at: null }
        })
      : []
  ]);

  const visitQueueMap = new Map(visitQueues.map((entry) => [entry.id, entry]));
  const appointmentMap = new Map(appointments.map((entry) => [entry.id, entry]));
  const emergencyCaseMap = new Map(emergencyCases.map((entry) => [entry.id, entry]));
  const triageAssessmentMap = new Map(triageAssessments.map((entry) => [entry.id, entry]));

  return encounters.map((encounter) => {
    const flow = getOpdFlowState(encounter);
    const triageAssessment = flow.triage_assessment_id
      ? triageAssessmentMap.get(flow.triage_assessment_id) || null
      : null;

    return {
      encounter,
      flow: {
        ...flow,
        triage_level: flow.triage_level || triageAssessment?.triage_level || null
      },
      visit_queue: flow.visit_queue_id ? visitQueueMap.get(flow.visit_queue_id) || null : null,
      appointment: flow.appointment_id ? appointmentMap.get(flow.appointment_id) || null : null,
      emergency_case: flow.emergency_case_id ? emergencyCaseMap.get(flow.emergency_case_id) || null : null,
      triage_assessment: triageAssessment
    };
  });
};

const resolveScopedFilters = async (filters = {}) => {
  const resolved = { ...filters };

  if (filters.tenant_id) {
    const tenant = await resolveTenantByIdentifier(prisma, filters.tenant_id);
    if (!tenant) return null;
    resolved.tenant_id = tenant.id;
  }

  if (filters.facility_id) {
    const facility = await resolveFacilityByIdentifier(prisma, filters.facility_id, resolved.tenant_id || null);
    if (!facility) return null;
    resolved.facility_id = facility.id;
    if (!resolved.tenant_id) resolved.tenant_id = facility.tenant_id;
  }

  if (filters.patient_id) {
    const patient = await resolvePatientByIdentifier(prisma, filters.patient_id, resolved.tenant_id || null);
    if (!patient) return null;
    resolved.patient_id = patient.id;
    if (!resolved.tenant_id) resolved.tenant_id = patient.tenant_id;
  }

  if (filters.provider_user_id) {
    const provider = await resolveProviderByIdentifier(
      prisma,
      filters.provider_user_id,
      resolved.tenant_id || null,
      resolved.facility_id || null
    );
    if (!provider) return null;
    resolved.provider_user_id = provider.id;
    if (!resolved.tenant_id) resolved.tenant_id = provider.tenant_id;
    if (!resolved.facility_id && provider.facility_id) resolved.facility_id = provider.facility_id;
  }

  const urgencyLevel = normalizeTriageLevel(filters.urgency_level || filters.triage_level);
  if (urgencyLevel) resolved.urgency_level = urgencyLevel;

  return resolved;
};

const listTriageQueue = async (filters = {}, page = 1, limit = 20, sortBy = 'started_at', order = 'asc') => {
  const normalizedPage = Math.max(Number(page) || 1, 1);
  const normalizedLimit = Math.max(Number(limit) || 20, 1);
  const skip = (normalizedPage - 1) * normalizedLimit;
  const resolvedFilters = await resolveScopedFilters(filters);

  if (!resolvedFilters) return emptyPage(normalizedPage, normalizedLimit);

  const where = buildTriageQueueWhereClause(resolvedFilters);
  const sortField = resolveSortField(sortBy);
  const sortOrder = normalizeUpper(order) === 'DESC' ? 'desc' : 'asc';

  const [encounters, total] = await Promise.all([
    prisma.encounter.findMany({
      where,
      skip,
      take: normalizedLimit,
      orderBy: { [sortField]: sortOrder },
      include: {
        tenant: true,
        facility: true,
        patient: true,
        provider: PROVIDER_INCLUDE
      }
    }),
    prisma.encounter.count({ where })
  ]);

  const hydrated = await prisma.$transaction((tx) => hydrateQueueSnapshots(tx, encounters));
  const filtered = resolvedFilters.urgency_level
    ? hydrated.filter((item) => normalizeTriageLevel(item?.flow?.triage_level) === resolvedFilters.urgency_level)
    : hydrated;
  const items = sortTriageQueueItems(filtered);
  const totalPages = Math.ceil(total / normalizedLimit);

  return {
    items,
    pagination: {
      page: normalizedPage,
      limit: normalizedLimit,
      total,
      totalPages,
      hasNextPage: normalizedPage < totalPages,
      hasPreviousPage: normalizedPage > 1
    }
  };
};

const assertTriageCaseScope = async (id, context = {}) => {
  const encounter = await resolveEncounterByIdentifier(prisma, id);
  if (!encounter) {
    throw new HttpError('errors.opd_flow.not_found', 404);
  }
  assertEncounterScope(encounter, context);
  return encounter;
};

const getTriageCase = async (id, context = {}) => {
  const flow = await opdFlowService.getOpdFlowById(id);
  assertEncounterScope(flow?.encounter, context);
  return flow;
};
const recordVitals = async (id, data, context = {}) => {
  await assertTriageCaseScope(id, context);
  return opdFlowService.recordVitals(id, data, context);
};
const assignProvider = async (id, data, context = {}) => {
  await assertTriageCaseScope(id, context);
  return opdFlowService.assignDoctor(id, data, context);
};
const correctStage = async (id, data, context = {}) => {
  await assertTriageCaseScope(id, context);
  return opdFlowService.correctStage(id, data, context);
};

const resolveRoutingProvider = async (tx, providerId, encounter) => {
  const normalized = normalizeIdentifier(providerId);
  if (!normalized) return null;
  const provider = await resolveProviderByIdentifier(tx, normalized, encounter.tenant_id, encounter.facility_id);
  if (!provider) {
    throw new HttpError('errors.user.not_found', 404, [{ field: 'provider_user_id' }]);
  }
  return provider;
};

const resolveRoutingDepartment = async (tx, departmentId, encounter) => {
  const normalized = normalizeIdentifier(departmentId);
  if (!normalized) return null;
  const department = await resolveDepartmentByIdentifier(tx, normalized, encounter.tenant_id, encounter.facility_id);
  if (!department) {
    throw new HttpError('errors.department.not_found', 404, [{ field: 'department_id' }]);
  }
  return department;
};

const resolveAdmissionFacility = async (tx, facilityId, encounter) => {
  const normalized = normalizeIdentifier(facilityId);
  if (!normalized) return null;
  const facility = await resolveFacilityByIdentifier(tx, normalized, encounter.tenant_id);
  if (!facility) {
    throw new HttpError('errors.facility.not_found', 404, [{ field: 'admission_facility_id' }]);
  }
  return facility;
};

const updateVisitQueueForRoute = async (tx, flow, data = {}) => {
  if (!flow.visit_queue_id) return null;
  return tx.visit_queue.updateMany({
    where: { id: flow.visit_queue_id, deleted_at: null },
    data
  });
};

const completeAppointmentForRoute = async (tx, flow) => {
  if (!flow.appointment_id) return null;
  return tx.appointment.updateMany({
    where: { id: flow.appointment_id, deleted_at: null },
    data: { status: 'COMPLETED' }
  });
};

const resolveEmergencyRecords = async (tx, encounter, flow, data, context) => {
  const triageLevel = normalizeTriageLevel(data?.triage_level) || normalizeTriageLevel(flow.triage_level) || 'LEVEL_2';
  const severity = TRIAGE_SEVERITY_MAP[triageLevel] || 'HIGH';
  const notes = normalizeNotes(data?.notes) || normalizeNotes(data?.triage_notes);

  let emergencyCase = flow.emergency_case_id
    ? await tx.emergency_case.findFirst({
        where: { id: flow.emergency_case_id, deleted_at: null }
      })
    : null;

  if (!emergencyCase) {
    emergencyCase = await tx.emergency_case.create({
      data: {
        tenant_id: encounter.tenant_id,
        facility_id: encounter.facility_id,
        patient_id: encounter.patient_id,
        severity,
        status: 'OPEN'
      }
    });
  } else if (emergencyCase.severity !== severity || emergencyCase.status !== 'OPEN') {
    emergencyCase = await tx.emergency_case.update({
      where: { id: emergencyCase.id },
      data: { severity, status: 'OPEN' }
    });
  }

  let triageAssessment = flow.triage_assessment_id
    ? await tx.triage_assessment.findFirst({
        where: { id: flow.triage_assessment_id, deleted_at: null }
      })
    : null;

  if (!triageAssessment) {
    triageAssessment = await tx.triage_assessment.create({
      data: {
        emergency_case_id: emergencyCase.id,
        triage_level: triageLevel,
        notes
      }
    });
  } else {
    triageAssessment = await tx.triage_assessment.update({
      where: { id: triageAssessment.id },
      data: {
        triage_level: triageLevel,
        notes
      }
    });
  }

  appendTimelineEvent(flow, 'EMERGENCY_TRIAGE_UPDATED', context, {
    emergency_case_id: emergencyCase.id,
    triage_assessment_id: triageAssessment.id,
    triage_level: triageLevel,
    severity
  });

  flow.emergency_case_id = emergencyCase.id;
  flow.triage_assessment_id = triageAssessment.id;
  flow.triage_level = triageLevel;
  return { emergencyCase, triageAssessment };
};

const createLabOrder = async (tx, encounter) =>
  tx.lab_order.create({
    data: {
      encounter_id: encounter.id,
      patient_id: encounter.patient_id,
      status: 'ORDERED'
    }
  });

const createRadiologyOrder = async (tx, encounter, data) =>
  tx.radiology_order.create({
    data: {
      encounter_id: encounter.id,
      patient_id: encounter.patient_id,
      status: 'ORDERED',
      clinical_note: normalizeNotes(data?.notes),
      request_details: {
        source: 'TRIAGE',
        reason: normalizeNotes(data?.reason) || normalizeNotes(data?.notes)
      }
    }
  });

const createReferralForRoute = async (tx, encounter, routeTo, department, data) => {
  if (!department && routeTo !== ROUTE_DESTINATIONS.OTHER_SERVICE && routeTo !== ROUTE_DESTINATIONS.PHYSIOTHERAPY) {
    return null;
  }

  return tx.referral.create({
    data: {
      encounter_id: encounter.id,
      to_department_id: department?.id || null,
      reason: normalizeNotes(data?.reason) || routeTo.replace(/_/g, ' '),
      notes: normalizeNotes(data?.notes),
      status: 'REQUESTED'
    }
  });
};

const createAdmissionForRoute = async (tx, encounter, facility, data) =>
  tx.admission.create({
    data: {
      tenant_id: encounter.tenant_id,
      facility_id: facility?.id || encounter.facility_id || null,
      patient_id: encounter.patient_id,
      encounter_id: encounter.id,
      status: 'REQUESTED',
      admitted_at: data?.admitted_at ? new Date(data.admitted_at) : new Date()
    }
  });

const createTheatreCaseForRoute = async (tx, encounter, provider, data, routeTo) => {
  const scheduledAt = data?.scheduled_at ? new Date(data.scheduled_at) : new Date();
  return tx.theatre_case.create({
    data: {
      encounter_id: encounter.id,
      scheduled_at: scheduledAt,
      status: 'SCHEDULED',
      surgeon_user_id: provider?.id || encounter.provider_user_id || null,
      workflow_stage: routeTo === ROUTE_DESTINATIONS.MINOR_PROCEDURE ? 'MINOR_PROCEDURE_REQUESTED' : 'TRIAGE_REQUESTED',
      stage_notes: normalizeNotes(data?.notes) || normalizeNotes(data?.reason)
    }
  });
};

const appendRouteHistory = (flow, routeRecord) => {
  if (!Array.isArray(flow.route_history)) {
    flow.route_history = [];
  }
  flow.route_history.push(routeRecord);
  flow.last_triage_route = routeRecord;
};

const routeFromTriage = async (id, data = {}, context = {}) => {
  const routeTo = normalizeRouteDestination(data?.route_to);
  if (!ROUTE_DESTINATION_SET.has(routeTo)) {
    throw new HttpError('errors.validation.invalid', 400, [{ field: 'route_to' }]);
  }

  const routedAt = new Date();
  const updatedResult = await prisma.$transaction(async (tx) => {
    const encounter = await resolveEncounterByIdentifier(tx, id);
    if (!encounter) {
      throw new HttpError('errors.opd_flow.not_found', 404);
    }
    assertEncounterScope(encounter, context);

    const flow = getOpdFlowState(encounter);
    ensureNonTerminalStage(flow);
    const stageBefore = flow.stage || null;

    const provider = await resolveRoutingProvider(tx, data.provider_user_id, encounter);
    const department = await resolveRoutingDepartment(tx, data.department_id, encounter);
    const admissionFacility = await resolveAdmissionFacility(tx, data.admission_facility_id, encounter);
    const triageLevel = normalizeTriageLevel(data.triage_level) || normalizeTriageLevel(flow.triage_level);
    const notes = normalizeNotes(data.notes);
    const routeRecord = {
      route_to: routeTo,
      at: routedAt.toISOString(),
      by_user_id: context.user_id || null,
      provider_user_id: provider?.id || encounter.provider_user_id || null,
      department_id: department?.id || null,
      triage_level: triageLevel || null,
      notes
    };

    let encounterData = {};
    let queueData = { status: 'COMPLETED' };
    let createdLabOrder = null;
    let createdRadiologyOrder = null;
    let createdReferral = null;
    let createdAdmission = null;
    let createdTheatreCase = null;
    let emergencyRecords = null;

    if (triageLevel) {
      flow.triage_level = triageLevel;
    }

    switch (routeTo) {
      case ROUTE_DESTINATIONS.CONSULTATION: {
        const providerForConsultation = provider || (encounter.provider_user_id ? null : undefined);
        if (providerForConsultation === undefined) {
          throw new HttpError('errors.user.not_found', 404, [{ field: 'provider_user_id' }]);
        }
        setFlowStage(flow, STAGES.WAITING_DOCTOR_REVIEW);
        encounterData = provider ? { provider_user_id: provider.id } : {};
        queueData = {
          status: 'IN_PROGRESS',
          ...(provider ? { provider_user_id: provider.id } : {})
        };
        break;
      }
      case ROUTE_DESTINATIONS.LAB: {
        createdLabOrder = await createLabOrder(tx, encounter);
        flow.lab_order_ids = [...new Set([...(flow.lab_order_ids || []), createdLabOrder.id])];
        setFlowStage(flow, STAGES.LAB_REQUESTED);
        break;
      }
      case ROUTE_DESTINATIONS.RADIOLOGY: {
        createdRadiologyOrder = await createRadiologyOrder(tx, encounter, data);
        flow.radiology_order_ids = [...new Set([...(flow.radiology_order_ids || []), createdRadiologyOrder.id])];
        setFlowStage(flow, STAGES.RADIOLOGY_REQUESTED);
        break;
      }
      case ROUTE_DESTINATIONS.LAB_AND_RADIOLOGY: {
        createdLabOrder = await createLabOrder(tx, encounter);
        createdRadiologyOrder = await createRadiologyOrder(tx, encounter, data);
        flow.lab_order_ids = [...new Set([...(flow.lab_order_ids || []), createdLabOrder.id])];
        flow.radiology_order_ids = [...new Set([...(flow.radiology_order_ids || []), createdRadiologyOrder.id])];
        setFlowStage(flow, STAGES.LAB_AND_RADIOLOGY_REQUESTED);
        break;
      }
      case ROUTE_DESTINATIONS.PHYSIOTHERAPY:
      case ROUTE_DESTINATIONS.OTHER_SERVICE: {
        createdReferral = await createReferralForRoute(tx, encounter, routeTo, department, data);
        if (createdReferral) {
          flow.referral_ids = [...new Set([...(flow.referral_ids || []), createdReferral.id])];
        }
        if (routeTo === ROUTE_DESTINATIONS.PHYSIOTHERAPY) {
          const therapyFlowService = require('@services/therapy-flow/therapy-flow.service');
          const therapyEpisode = await therapyFlowService.createTherapyReferralInternal(
            tx,
            {
              encounter_id: encounter.id,
              referral_id: createdReferral?.id || null,
              source_kind: 'TRIAGE',
              source_id: encounter.id,
              source_title: 'Triage routing',
              referral_reason: normalizeNotes(data?.reason) || 'Physiotherapy referral',
              notes: normalizeNotes(data?.notes)},
            context
          );
          flow.therapy_episode_id = therapyEpisode.id;
        }
        setFlowStage(flow, STAGES.WAITING_DISPOSITION);
        break;
      }
      case ROUTE_DESTINATIONS.ADMIT: {
        createdAdmission = await createAdmissionForRoute(tx, encounter, admissionFacility, data);
        flow.admission_id = createdAdmission.id;
        setFlowStage(flow, STAGES.ADMITTED);
        encounterData = { status: 'CLOSED', ended_at: routedAt };
        break;
      }
      case ROUTE_DESTINATIONS.EMERGENCY: {
        emergencyRecords = await resolveEmergencyRecords(tx, encounter, flow, data, context);
        setFlowStage(flow, STAGES.WAITING_DOCTOR_ASSIGNMENT);
        encounterData = { encounter_type: 'EMERGENCY', status: 'OPEN' };
        queueData = { status: 'IN_PROGRESS' };
        break;
      }
      case ROUTE_DESTINATIONS.THEATRE:
      case ROUTE_DESTINATIONS.MINOR_PROCEDURE: {
        createdTheatreCase = await createTheatreCaseForRoute(tx, encounter, provider, data, routeTo);
        flow.theatre_case_id = createdTheatreCase.id;
        setFlowStage(flow, STAGES.WAITING_DISPOSITION);
        break;
      }
      case ROUTE_DESTINATIONS.DISCHARGE: {
        setFlowStage(flow, STAGES.DISCHARGED);
        encounterData = { status: 'CLOSED', ended_at: routedAt };
        break;
      }
      default:
        throw new HttpError('errors.validation.invalid', 400, [{ field: 'route_to' }]);
    }

    appendRouteHistory(flow, routeRecord);
    appendTimelineEvent(
      flow,
      'TRIAGE_ROUTED',
      context,
      {
        route_to: routeTo,
        provider_user_id: routeRecord.provider_user_id,
        department_id: routeRecord.department_id,
        triage_level: routeRecord.triage_level,
        lab_order_id: createdLabOrder?.id || null,
        radiology_order_id: createdRadiologyOrder?.id || null,
        referral_id: createdReferral?.id || null,
        admission_id: createdAdmission?.id || null,
        theatre_case_id: createdTheatreCase?.id || null,
        emergency_case_id: emergencyRecords?.emergencyCase?.id || null,
        notes
      },
      routedAt
    );

    await updateVisitQueueForRoute(tx, flow, queueData);
    if (routeTo !== ROUTE_DESTINATIONS.CONSULTATION && routeTo !== ROUTE_DESTINATIONS.EMERGENCY) {
      await completeAppointmentForRoute(tx, flow);
    }

    const updatedEncounter = await tx.encounter.update({
      where: { id: encounter.id },
      data: {
        ...encounterData,
        extension_json: {
          ...(encounter.extension_json || {}),
          opd_flow: flow
        }
      }
    });

    return {
      encounter: updatedEncounter,
      routeTo,
      stageBefore,
      stageAfter: flow.stage,
      transition: {
        action: 'TRIAGE_ROUTED',
        stage_from: stageBefore,
        stage_to: flow.stage,
        provider_user_id: routeRecord.provider_user_id,
        occurred_at: routedAt.toISOString()
      },
      diff: {
        before: { stage: stageBefore },
        after: {
          stage: flow.stage,
          route_to: routeTo,
          provider_user_id: routeRecord.provider_user_id,
          department_id: routeRecord.department_id,
          triage_level: routeRecord.triage_level
        }
      }
    };
  });

  createAuditLog({
    tenant_id: updatedResult.encounter.tenant_id,
    user_id: context.user_id,
    action: 'UPDATE',
    entity: 'triage_flow',
    entity_id: updatedResult.encounter.id,
    diff: updatedResult.diff,
    ip_address: context.ip_address
  }).catch(() => {});

  return getTriageCase(updatedResult.encounter.id);
};

module.exports = {
  listTriageQueue,
  getTriageCase,
  recordVitals,
  assignProvider,
  routeFromTriage,
  correctStage
};
