/**
 * Patient service
 *
 * @module modules/patient/services
 * @description Business logic layer for patient operations.
 * Per module-creation.mdc: Services only import/use their own repository.
 * Per prisma.mdc: All mutations call createAuditLog.
 */

const patientRepository = require('@repositories/patient/patient.repository');
const patientDeletionRepository = require('@repositories/patient/patient-deletion.repository');
const patientContactRepository = require('@repositories/patient-contact/patient-contact.repository');
const patientIdentifierRepository = require('@repositories/patient-identifier/patient-identifier.repository');
const prisma = require('@prisma/client');
const { createAuditLog } = require('@lib/audit');
const { HttpError } = require('@lib/errors');
const { logger } = require('@lib/logging');
const { publishDomainEvent, PATIENT_EVENTS } = require('@lib/websocket');
const { ROLES } = require('@config/roles');
const { PERMISSIONS } = require('@config/permissions');
const { createStorageService } = require('@lib/storage');
const { findLiveStateBlockers } = require('@lib/patient/patient-cascade');
const {
  isPurgedPatient,
} = require('@lib/patient/purged-patient');
const {
  sanitizeIdentifier,
  resolvePublicIdentifier,
  resolveIdentifierForFilter,
  resolveIdentifierForPayload} = require('@lib/billing/identifiers');

const PATIENT_PURGE_ADMIN_PERMISSIONS = Object.freeze([
  PERMISSIONS.FACILITY_ADMIN,
  PERMISSIONS.TENANT_ADMIN,
  PERMISSIONS.PLATFORM_ADMIN,
  PERMISSIONS.PLATFORM_OWNER,
]);

const LIFECYCLE_REALTIME_EVENTS = new Set([
  PATIENT_EVENTS.PATIENT_DELETED,
  PATIENT_EVENTS.PATIENT_RESTORED,
  PATIENT_EVENTS.PATIENT_PERMANENTLY_DELETED,
]);

const MAX_SEARCH_TOKENS = 5;
const CONTACT_TYPE_VALUES = new Set([
  'PHONE',
  'EMAIL',
  'WHATSAPP',
  'TELEGRAM',
  'TIKTOK',
  'INSTAGRAM',
  'FACEBOOK',
  'LINKEDIN',
  'X',
  'YOUTUBE',
  'PINTEREST',
  'REDDIT',
  'DISCORD',
  'FAX',
  'OTHER'
]);
const CONSENT_TYPE_VALUES = new Set([
  'TREATMENT',
  'DATA_SHARING',
  'RESEARCH',
  'BILLING',
  'OTHER'
]);
const CONSENT_STATUS_VALUES = new Set([
  'GRANTED',
  'REVOKED',
  'PENDING'
]);
const APPOINTMENT_STATUS_VALUES = new Set([
  'SCHEDULED',
  'CONFIRMED',
  'IN_PROGRESS',
  'COMPLETED',
  'CANCELLED',
  'NO_SHOW'
]);
const ACTIVE_ADMISSION_STATUS = 'ADMITTED';
const OUTSTANDING_INVOICE_STATUSES = ['SENT', 'OVERDUE'];
const OUTSTANDING_BILLING_STATUSES = ['ISSUED', 'PARTIAL'];
const DATE_ONLY_REGEX = /^\d{4}-\d{2}-\d{2}$/;


const PATIENT_REALTIME_RECIPIENT_ROLES = Object.freeze([
  ROLES.RECEPTIONIST,
  ROLES.DOCTOR,
  ROLES.NURSE,
  ROLES.FACILITY_ADMIN,
  ROLES.TENANT_ADMIN
]);

const compactId = (value) => String(value || '').trim() || null;

const actorPermissionSet = (actor = {}) => {
  const values = [
    ...(Array.isArray(actor.permissions) ? actor.permissions : []),
    ...(Array.isArray(actor.permissionNames) ? actor.permissionNames : []),
  ]
    .map((value) => String(value || '').trim())
    .filter(Boolean);
  return new Set(values);
};

const assertActorCanPermanentlyDeletePatient = (actor = {}) => {
  const permissions = actorPermissionSet(actor);
  const allowed = PATIENT_PURGE_ADMIN_PERMISSIONS.some((permission) =>
    permissions.has(permission)
  );
  if (!allowed) {
    throw new HttpError('errors.patient.purge_forbidden', 403);
  }
};

const resolveListRecordState = (filters = {}) => {
  const recordState = String(filters.record_state || '').trim().toLowerCase();
  if (recordState === 'current' || recordState === 'deleted' || recordState === 'all') {
    return recordState;
  }
  if (filters.include_deleted === true || filters.include_deleted === 'true') {
    return 'all';
  }
  return 'current';
};

const publishPatientRealtimeEvent = async (event, patient = {}, actorUserId = null) => {
  try {
    const tenantId = compactId(patient?.tenant_id);
    if (!tenantId) return;

    const facilityId = compactId(patient?.facility_id);
    const patientId = compactId(patient?.id);
    const occurredAt = new Date().toISOString();
    const patientPublicId = resolvePublicIdentifier(
      patient?.patient_public_id,
      patient?.display_id,
      patient?.human_friendly_id,
      // Lifecycle events must not leak internal UUIDs in the payload.
      LIFECYCLE_REALTIME_EVENTS.has(event) ? null : patientId
    );
    const recipientUserIds = await patientRepository.findRealtimeRecipientUserIds({
      tenantId,
      facilityId,
      roles: PATIENT_REALTIME_RECIPIENT_ROLES,
      extraUserIds: [actorUserId]
    });

    const lifecycleOnly = LIFECYCLE_REALTIME_EVENTS.has(event);
    const publicHumanId =
      compactId(patient?.human_friendly_id) ||
      compactId(patient?.patient_public_id) ||
      compactId(patient?.display_id) ||
      null;

    publishDomainEvent({
      event,
      tenant_id: tenantId,
      facility_id: facilityId,
      actor_user_id: actorUserId,
      resource_type: 'patient',
      resource_id: lifecycleOnly ? publicHumanId : patientId,
      affected: lifecycleOnly
        ? { human_friendly_id: publicHumanId }
        : { patient_id: patientId },
      recipient_user_ids: recipientUserIds,
      payload: lifecycleOnly
        ? {
            human_friendly_id: publicHumanId,
            tenant_id: tenantId,
            facility_id: facilityId,
            actor_user_id: actorUserId || null,
            target_path: publicHumanId
              ? `/patients?id=${encodeURIComponent(publicHumanId)}`
              : '/patients',
            occurred_at: occurredAt
          }
        : {
            patient_id: patientId,
            patient_public_id: patientPublicId,
            tenant_id: tenantId,
            facility_id: facilityId,
            status: patient?.status || null,
            is_active: patient?.is_active !== undefined ? patient.is_active : patient?.isActive,
            actor_user_id: actorUserId || null,
            target_path: patientPublicId ? `/patients?id=${encodeURIComponent(patientPublicId)}` : '/patients',
            occurred_at: occurredAt
          }
    });
  } catch (error) {
    logger.error('Failed to publish patient realtime event', {
      event,
      patientId: patient?.id,
      error: error.message
    });
  }
};


const PATIENT_RELATION_CONTEXT_INCLUDE = {
  tenant: {
    select: {
      human_friendly_id: true,
      name: true
    }
  },
  facility: {
    select: {
      human_friendly_id: true,
      name: true
    }
  },
  contacts: {
    where: {
      deleted_at: null
    },
    orderBy: [
      { is_primary: 'desc' },
      { updated_at: 'desc' }
    ],
    take: 3,
    select: {
      human_friendly_id: true,
      contact_type: true,
      value: true,
      is_primary: true,
      updated_at: true
    }
  },
  identifiers: {
    where: {
      deleted_at: null
    },
    orderBy: [
      { is_primary: 'desc' },
      { updated_at: 'desc' }
    ],
    take: 3,
    select: {
      human_friendly_id: true,
      identifier_type: true,
      identifier_value: true,
      is_primary: true,
      updated_at: true
    }
  },
  guardians: {
    where: {
      deleted_at: null
    },
    orderBy: [
      { updated_at: 'desc' }
    ],
    take: 3,
    select: {
      human_friendly_id: true,
      name: true,
      relationship: true,
      phone: true,
      email: true,
      updated_at: true
    }
  },
  allergies: {
    where: {
      deleted_at: null
    },
    orderBy: [
      { updated_at: 'desc' }
    ],
    take: 1,
    select: {
      human_friendly_id: true,
      allergen: true,
      severity: true,
      updated_at: true
    }
  },
  appointments: {
    where: {
      deleted_at: null
    },
    orderBy: [
      { scheduled_start: 'desc' }
    ],
    take: 1,
    select: {
      human_friendly_id: true,
      status: true,
      scheduled_start: true,
      updated_at: true
    }
  },
  visit_queue_entries: {
    where: {
      deleted_at: null
    },
    orderBy: [
      { queued_at: 'desc' }
    ],
    take: 1,
    select: {
      human_friendly_id: true,
      status: true,
      queued_at: true,
      updated_at: true
    }
  },
  encounters: {
    where: {
      deleted_at: null
    },
    orderBy: [
      { started_at: 'desc' }
    ],
    take: 1,
    select: {
      human_friendly_id: true,
      encounter_type: true,
      status: true,
      started_at: true,
      updated_at: true
    }
  },
  admissions: {
    where: {
      deleted_at: null
    },
    orderBy: [
      { admitted_at: 'desc' }
    ],
    take: 1,
    select: {
      human_friendly_id: true,
      status: true,
      admitted_at: true,
      updated_at: true
    }
  }
};

const buildEmptyListResult = (page, limit) => ({
  patients: [],
  pagination: {
    page,
    limit,
    total: 0,
    totalPages: 0,
    hasNextPage: false,
    hasPreviousPage: page > 1
  }
});

const normalizeText = (value) => String(value || '').trim();

const normalizeSearchTokens = (search) =>
  String(search || '')
    .trim()
    .split(/\s+/)
    .map((token) => token.trim())
    .filter(Boolean)
    .slice(0, MAX_SEARCH_TOKENS);

const normalizeBooleanFilter = (value) => {
  if (value === true || value === false) return value;
  const normalized = normalizeText(value).toLowerCase();
  if (normalized === 'true') return true;
  if (normalized === 'false') return false;
  return undefined;
};

const parseDateValue = (value) => {
  if (value === undefined) return undefined;
  if (value === null || value === '') return null;
  const parsed = parseDateFilter(value, false);
  return parsed || null;
};

const hasOwn = (value, property) =>
  Boolean(value) && Object.prototype.hasOwnProperty.call(value, property);

const pickScopedIdentifier = (data, scope, field) => {
  if (hasOwn(data, field)) {
    const explicit = data[field];
    if (explicit !== undefined && explicit !== null && String(explicit).trim() !== '') {
      return explicit;
    }
  }
  return scope[field];
};

const findPrimaryContactRecord = async (patientId, tenantId, contactType, dbClient = prisma) => {
  const records = await patientContactRepository.findMany(
    {
      tenant_id: tenantId,
      patient_id: patientId,
      contact_type: contactType,
      deleted_at: null
    },
    0,
    1,
    [{ is_primary: 'desc' }, { updated_at: 'desc' }],
    {},
    dbClient
  );

  return records[0] || null;
};

const findPrimaryIdentifierRecord = async (patientId, tenantId, dbClient = prisma) => {
  const records = await patientIdentifierRepository.findMany(
    {
      tenant_id: tenantId,
      patient_id: patientId,
      deleted_at: null,
      is_primary: true
    },
    0,
    1,
    [{ updated_at: 'desc' }],
    {},
    dbClient
  );

  return records[0] || null;
};

const resolvePrimaryContactByType = (contacts = [], contactType) => {
  const normalizedType = normalizeText(contactType).toUpperCase();
  if (!normalizedType) return null;

  const matchingContacts = Array.isArray(contacts)
    ? contacts.filter(
        (entry) => normalizeText(entry?.contact_type).toUpperCase() === normalizedType
      )
    : [];

  return matchingContacts.find((entry) => entry?.is_primary) || matchingContacts[0] || null;
};

const resolvePrimaryIdentifierRecord = (identifiers = []) => {
  if (!Array.isArray(identifiers)) return null;
  return identifiers.find((entry) => entry?.is_primary) || identifiers[0] || null;
};

const synchronizePrimaryPatientContacts = async (patientId, tenantId, dbClient = prisma) => {
  const [phoneRecords, emailRecords] = await Promise.all([
    patientContactRepository.findMany(
      {
        tenant_id: tenantId,
        patient_id: patientId,
        contact_type: 'PHONE',
        deleted_at: null
      },
      0,
      50,
      [{ is_primary: 'desc' }, { updated_at: 'desc' }],
      {},
      dbClient
    ),
    patientContactRepository.findMany(
      {
        tenant_id: tenantId,
        patient_id: patientId,
        contact_type: 'EMAIL',
        deleted_at: null
      },
      0,
      50,
      [{ is_primary: 'desc' }, { updated_at: 'desc' }],
      {},
      dbClient
    )
  ]);

  const preferredPrimaryId = phoneRecords[0]?.id || emailRecords[0]?.id || null;
  const trackedRecords = [...phoneRecords, ...emailRecords];

  await Promise.all(
    trackedRecords
      .map((record) => {
        const shouldBePrimary = Boolean(preferredPrimaryId) && record.id === preferredPrimaryId;
        if (Boolean(record?.is_primary) === shouldBePrimary) {
          return null;
        }

        return patientContactRepository.update(
          record.id,
          { is_primary: shouldBePrimary },
          dbClient
        );
      })
      .filter(Boolean)
  );
};

const resolveEnumSearchClauses = (token, allowedValues, fieldName) => {
  const enumToken = String(token || '').toUpperCase();
  if (!allowedValues.has(enumToken)) {
    return [];
  }
  return [{ [fieldName]: enumToken }];
};

const parseDateFilter = (value, endOfDay = false) => {
  const normalized = String(value || '').trim();
  if (!normalized) return null;

  if (DATE_ONLY_REGEX.test(normalized)) {
    const date = new Date(
      `${normalized}${endOfDay ? 'T23:59:59.999Z' : 'T00:00:00.000Z'}`
    );
    return Number.isNaN(date.getTime()) ? null : date;
  }

  const date = new Date(normalized);
  return Number.isNaN(date.getTime()) ? null : date;
};

const buildTemporalFilter = ({ exactValue, fromValue, toValue }) => {
  if (exactValue) {
    const exactStart = parseDateFilter(exactValue, false);
    if (!exactStart) return null;
    if (DATE_ONLY_REGEX.test(String(exactValue).trim())) {
      const exactEnd = parseDateFilter(exactValue, true);
      if (!exactEnd) return null;
      return { gte: exactStart, lte: exactEnd };
    }
    return { equals: exactStart };
  }

  const fromDate = parseDateFilter(fromValue, false);
  const toDate = parseDateFilter(toValue, true);
  const rangeFilter = {};
  if (fromDate) rangeFilter.gte = fromDate;
  if (toDate) rangeFilter.lte = toDate;

  return Object.keys(rangeFilter).length > 0 ? rangeFilter : null;
};

const buildSearchTokenClause = (token) => {
  const contactTypeClauses = resolveEnumSearchClauses(token, CONTACT_TYPE_VALUES, 'contact_type');
  const consentTypeClauses = resolveEnumSearchClauses(token, CONSENT_TYPE_VALUES, 'consent_type');
  const consentStatusClauses = resolveEnumSearchClauses(token, CONSENT_STATUS_VALUES, 'status');
  const appointmentStatusClauses = resolveEnumSearchClauses(
    token,
    APPOINTMENT_STATUS_VALUES,
    'status'
  );

  return {
    OR: [
      { human_friendly_id: { contains: token } },
      { first_name: { contains: token } },
      { last_name: { contains: token } },
      {
        identifiers: {
          some: {
            deleted_at: null,
            OR: [
              { human_friendly_id: { contains: token } },
              { identifier_type: { contains: token } },
              { identifier_value: { contains: token } }
            ]
          }
        }
      },
      {
        contacts: {
          some: {
            deleted_at: null,
            OR: [
              { human_friendly_id: { contains: token } },
              { value: { contains: token } },
              ...contactTypeClauses
            ]
          }
        }
      },
      {
        guardians: {
          some: {
            deleted_at: null,
            OR: [
              { human_friendly_id: { contains: token } },
              { name: { contains: token } },
              { relationship: { contains: token } },
              { phone: { contains: token } },
              { email: { contains: token } }
            ]
          }
        }
      },
      {
        allergies: {
          some: {
            deleted_at: null,
            OR: [
              { human_friendly_id: { contains: token } },
              { allergen: { contains: token } },
              { reaction: { contains: token } },
              { notes: { contains: token } }
            ]
          }
        }
      },
      {
        medical_history: {
          some: {
            deleted_at: null,
            OR: [
              { human_friendly_id: { contains: token } },
              { condition: { contains: token } },
              { notes: { contains: token } }
            ]
          }
        }
      },
      {
        documents: {
          some: {
            deleted_at: null,
            OR: [
              { human_friendly_id: { contains: token } },
              { document_type: { contains: token } },
              { file_name: { contains: token } },
              { storage_key: { contains: token } },
              { content_type: { contains: token } }
            ]
          }
        }
      },
      {
        consents: {
          some: {
            deleted_at: null,
            OR: [
              { human_friendly_id: { contains: token } },
              ...consentTypeClauses,
              ...consentStatusClauses
            ]
          }
        }
      },
      {
        appointments: {
          some: {
            deleted_at: null,
            OR: [
              { human_friendly_id: { contains: token } },
              { reason: { contains: token } },
              ...appointmentStatusClauses
            ]
          }
        }
      }
    ]
  };
};

const buildAppointmentFilter = (filters = {}) => {
  const filter = {
    deleted_at: null
  };
  let hasAppliedFilter = false;

  if (filters.appointment_status) {
    filter.status = filters.appointment_status;
    hasAppliedFilter = true;
  }

  const scheduledStartFilter = buildTemporalFilter({
    fromValue: filters.appointment_from,
    toValue: filters.appointment_to
  });
  if (scheduledStartFilter) {
    filter.scheduled_start = scheduledStartFilter;
    hasAppliedFilter = true;
  }

  return hasAppliedFilter ? filter : null;
};

const buildVisitDateFilter = (filters = {}) =>
  buildTemporalFilter({
    exactValue: filters.visit_date,
    fromValue: filters.visit_from,
    toValue: filters.visit_to
  });

const buildPatientWhereClause = (filters = {}) => {
  const whereClause = {};
  const searchTokens = normalizeSearchTokens(filters.search);

  if (filters.tenant_id) whereClause.tenant_id = filters.tenant_id;
  if (filters.facility_id) whereClause.facility_id = filters.facility_id;
  if (filters.patient_id) whereClause.human_friendly_id = { contains: filters.patient_id };
  if (filters.gender) whereClause.gender = filters.gender;
  const activeFilter = normalizeBooleanFilter(filters.is_active);
  if (activeFilter === true) {
    whereClause.encounters = {
      some: {
        deleted_at: null,
        status: 'OPEN'
      }
    };
  }
  if (activeFilter === false) {
    whereClause.encounters = {
      none: {
        deleted_at: null,
        status: 'OPEN'
      }
    };
  }
  if (filters.first_name) whereClause.first_name = { contains: filters.first_name };
  if (filters.last_name) whereClause.last_name = { contains: filters.last_name };
  if (filters.consent_state) {
    whereClause.consents = {
      some: {
        deleted_at: null,
        status: filters.consent_state
      }
    };
  }

  const hasActiveAdmissionFilter = normalizeBooleanFilter(filters.has_active_admission);
  if (hasActiveAdmissionFilter === true) {
    whereClause.admissions = {
      some: {
        deleted_at: null,
        status: ACTIVE_ADMISSION_STATUS
      }
    };
  }
  if (hasActiveAdmissionFilter === false) {
    whereClause.admissions = {
      none: {
        deleted_at: null,
        status: ACTIVE_ADMISSION_STATUS
      }
    };
  }

  const outstandingFilter = {
    deleted_at: null,
    OR: [
      { status: { in: OUTSTANDING_INVOICE_STATUSES } },
      { billing_status: { in: OUTSTANDING_BILLING_STATUSES } }
    ]
  };
  const hasOutstandingBalanceFilter = normalizeBooleanFilter(filters.has_outstanding_balance);
  if (hasOutstandingBalanceFilter === true) {
    whereClause.invoices = {
      some: outstandingFilter
    };
  }
  if (hasOutstandingBalanceFilter === false) {
    whereClause.invoices = {
      none: outstandingFilter
    };
  }

  const dateOfBirthFilter = buildTemporalFilter({
    exactValue: filters.date_of_birth,
    fromValue: filters.date_of_birth_from,
    toValue: filters.date_of_birth_to
  });
  if (dateOfBirthFilter) whereClause.date_of_birth = dateOfBirthFilter;

  const createdAtFilter = buildTemporalFilter({
    exactValue: filters.created_at,
    fromValue: filters.created_from,
    toValue: filters.created_to
  });
  if (createdAtFilter) whereClause.created_at = createdAtFilter;

  if (filters.contact) {
    whereClause.contacts = {
      some: {
        deleted_at: null,
        OR: [
          { human_friendly_id: { contains: filters.contact } },
          { value: { contains: filters.contact } }
        ]
      }
    };
  }

  const appointmentFilter = buildAppointmentFilter(filters);
  if (appointmentFilter) {
    whereClause.appointments = { some: appointmentFilter };
  }

  const visitDateFilter = buildVisitDateFilter(filters);
  if (visitDateFilter) {
    whereClause.OR = [
      ...(whereClause.OR || []),
      {
        encounters: {
          some: {
            deleted_at: null,
            started_at: visitDateFilter
          }
        }
      },
      {
        visit_queue_entries: {
          some: {
            deleted_at: null,
            queued_at: visitDateFilter
          }
        }
      },
      {
        appointments: {
          some: {
            deleted_at: null,
            scheduled_start: visitDateFilter
          }
        }
      }
    ];
  }

  if (searchTokens.length > 0) {
    whereClause.AND = searchTokens.map(buildSearchTokenClause);
  }

  return whereClause;
};

const decoratePatientContext = (patient) => {
  if (!patient || typeof patient !== 'object') return patient;

  const tenantContext = patient.tenant || null;
  const facilityContext = patient.facility || null;
  const contacts = Array.isArray(patient.contacts)
    ? patient.contacts.map((entry) => ({
        human_friendly_id: resolvePublicIdentifier(entry?.human_friendly_id),
        contact_type: entry?.contact_type || null,
        value: normalizeText(entry?.value) || null,
        is_primary: Boolean(entry?.is_primary),
        updated_at: entry?.updated_at || null
      }))
    : [];
  const identifiers = Array.isArray(patient.identifiers)
    ? patient.identifiers.map((entry) => ({
        human_friendly_id: resolvePublicIdentifier(entry?.human_friendly_id),
        identifier_type: normalizeText(entry?.identifier_type) || null,
        identifier_value: normalizeText(entry?.identifier_value) || null,
        is_primary: Boolean(entry?.is_primary),
        updated_at: entry?.updated_at || null
      }))
    : [];
  const guardians = Array.isArray(patient.guardians)
    ? patient.guardians.map((entry) => ({
        human_friendly_id: resolvePublicIdentifier(entry?.human_friendly_id),
        name: normalizeText(entry?.name) || null,
        relationship: normalizeText(entry?.relationship) || null,
        phone: normalizeText(entry?.phone) || null,
        email: normalizeText(entry?.email) || null,
        updated_at: entry?.updated_at || null
      }))
    : [];
  const primaryContact = contacts.find((entry) => entry?.is_primary) || contacts[0] || null;
  const primaryPhoneContact = resolvePrimaryContactByType(contacts, 'PHONE');
  const primaryEmailContact = resolvePrimaryContactByType(contacts, 'EMAIL');
  const primaryIdentifier = resolvePrimaryIdentifierRecord(identifiers);
  const allergy = Array.isArray(patient.allergies) ? patient.allergies[0] : null;
  const visitCandidates = [
    firstVisitContext(patient.visit_queue_entries, 'visit_queue', 'queued_at'),
    firstVisitContext(patient.encounters, 'encounter', 'started_at'),
    firstVisitContext(patient.admissions, 'admission', 'admitted_at'),
    firstVisitContext(patient.appointments, 'appointment', 'scheduled_start')
  ].filter(Boolean);
  const activeVisit = visitCandidates.find((entry) =>
    ['ADMITTED', 'ARRIVED', 'CHECKED_IN', 'IN_PROGRESS', 'SCHEDULED', 'OPEN'].includes(
      normalizeText(entry.status).toUpperCase()
    )
  );
  const latestVisit = visitCandidates.sort(
    (left, right) => new Date(right.occurred_at || 0) - new Date(left.occurred_at || 0)
  )[0] || null;

  return {
    id: patient?.id || null,
    human_friendly_id: resolvePublicIdentifier(patient?.human_friendly_id),
    display_name: `${normalizeText(patient?.first_name)} ${normalizeText(patient?.last_name)}`.trim() || null,
    tenant_id: patient?.tenant_id || null,
    facility_id: patient?.facility_id || null,
    first_name: normalizeText(patient?.first_name) || null,
    last_name: normalizeText(patient?.last_name) || null,
    date_of_birth: patient?.date_of_birth || null,
    gender: patient?.gender || null,
    is_active: patient?.is_active !== false,
    extension_json: patient?.extension_json || null,
    contact: primaryContact?.value || null,
    contact_value: primaryContact?.value || null,
    contact_label: primaryContact?.value || null,
    primary_contact: primaryContact?.value || null,
    primary_contact_details: primaryContact || null,
    primary_phone: primaryPhoneContact?.value || null,
    primary_email: primaryEmailContact?.value || null,
    primary_identifier_type: primaryIdentifier?.identifier_type || null,
    primary_identifier_value: primaryIdentifier?.identifier_value || null,
    contacts,
    identifiers,
    guardians,
    alerts: {
      has_allergy: Boolean(allergy),
      allergy_label: allergy
        ? [normalizeText(allergy.allergen), normalizeText(allergy.severity)]
            .filter(Boolean)
            .join(' - ')
        : null
    },
    current_visit: activeVisit || latestVisit,
    tenant_context: tenantContext
      ? {
          id: resolvePublicIdentifier(tenantContext.human_friendly_id),
          label: tenantContext.name || null
        }
      : null,
    facility_context: facilityContext
      ? {
          id: resolvePublicIdentifier(facilityContext.human_friendly_id),
          label: facilityContext.name || null
        }
      : null,
    tenant_human_friendly_id: resolvePublicIdentifier(tenantContext?.human_friendly_id),
    tenant_label: tenantContext?.name || null,
    facility_human_friendly_id: resolvePublicIdentifier(facilityContext?.human_friendly_id),
    facility_label: facilityContext?.name || null,
    created_at: patient?.created_at || null,
    updated_at: patient?.updated_at || null
  };
};

const firstVisitContext = (records, kind, dateField) => {
  const record = Array.isArray(records) ? records[0] : null;
  if (!record) return null;

  return {
    kind,
    human_friendly_id: resolvePublicIdentifier(record.human_friendly_id),
    status: record.status || null,
    title: visitContextTitle(kind, record),
    occurred_at: record[dateField] || record.updated_at || null
  };
};

const visitContextTitle = (kind, record) => {
  if (kind === 'encounter') {
    return normalizeText(record.encounter_type) || 'Encounter';
  }
  if (kind === 'visit_queue') {
    return 'Visit queue';
  }
  if (kind === 'admission') {
    return 'Admission';
  }
  return 'Appointment';
};

const normalizeScopeValue = (value) =>
  typeof value === 'string' && value.trim() ? value.trim() : null;

const buildPatientScope = (scope = {}) => {
  const tenantId = normalizeScopeValue(scope.tenant_id);
  const facilityId = normalizeScopeValue(scope.facility_id);

  return {
    ...(tenantId ? { tenant_id: tenantId } : {}),
    ...(facilityId ? { facility_id: facilityId } : {})
  };
};

const resolvePatientScope = async (scope = {}) => {
  const scopedValues = buildPatientScope(scope);
  const resolved = {};

  if (scopedValues.tenant_id !== undefined) {
    const tenantId = await resolveIdentifierForFilter({
      value: scopedValues.tenant_id,
      model: 'tenant'
    });
    if (tenantId === null) return { __empty__: true };
    if (tenantId !== undefined) resolved.tenant_id = tenantId;
  }

  if (scopedValues.facility_id !== undefined) {
    const facilityId = await resolveIdentifierForFilter({
      value: scopedValues.facility_id,
      model: 'facility',
      where: resolved.tenant_id ? { tenant_id: resolved.tenant_id } : {}
    });
    if (facilityId === null) return { __empty__: true };
    if (facilityId !== undefined) resolved.facility_id = facilityId;
  }

  return resolved;
};

const mapPrismaError = (error) => {
  if (error?.code === 'P2002') {
    const target = error.meta?.target?.[0] || 'field';
    return new HttpError('errors.database.unique_field', 409, [{ field: target }]);
  }
  if (error?.code === 'P2003') {
    const target = error.meta?.field_name || 'field';
    return new HttpError('errors.database.foreign_key_field', 400, [{ field: target }]);
  }
  return null;
};

const ensurePatientExists = async (id, scope = {}) => {
  const resolvedScope = await resolvePatientScope(scope);
  if (resolvedScope.__empty__) {
    throw new HttpError('errors.patient.not_found', 404);
  }
  const patient = await patientRepository.findById(id, {}, resolvedScope);
  if (!patient) {
    throw new HttpError('errors.patient.not_found', 404);
  }
  return patient;
};

/**
 * List patients with pagination and filtering
 *
 * @param {Object} filters - Query filters
 * @param {number} page - Page number
 * @param {number} limit - Items per page
 * @param {string} sortBy - Sort field
 * @param {string} order - Sort order
 * @param {string} userId - User ID for audit
 * @param {string} ipAddress - User IP for audit
 * @returns {Promise<Object>} Patients and pagination data
 */
const listPatients = async (filters, page, limit, sortBy, order, userId, ipAddress) => {
  try {
    const skip = (page - 1) * limit;
    const orderBy = sortBy ? { [sortBy]: order } : { created_at: 'desc' };
    const scopedFilters = { ...filters };
    if (scopedFilters.tenant_id !== undefined) {
      const tenantId = await resolveIdentifierForFilter({
        value: scopedFilters.tenant_id,
        model: 'tenant'
      });
      if (tenantId === null) {
        return buildEmptyListResult(page, limit);
      }
      if (tenantId !== undefined) scopedFilters.tenant_id = tenantId;
      else delete scopedFilters.tenant_id;
    }
    if (scopedFilters.facility_id !== undefined) {
      const facilityId = await resolveIdentifierForFilter({
        value: scopedFilters.facility_id,
        model: 'facility',
        where: scopedFilters.tenant_id ? { tenant_id: scopedFilters.tenant_id } : {}
      });
      if (facilityId === null) {
        return buildEmptyListResult(page, limit);
      }
      if (facilityId !== undefined) scopedFilters.facility_id = facilityId;
      else delete scopedFilters.facility_id;
    }
    const whereClause = buildPatientWhereClause(scopedFilters);
    const recordState = resolveListRecordState(scopedFilters);
    const listOptions = { recordState, includeDeleted: recordState !== 'current' };

    const [patients, total] = await Promise.all([
      patientRepository.findMany(
        whereClause,
        skip,
        limit,
        orderBy,
        PATIENT_RELATION_CONTEXT_INCLUDE,
        prisma,
        listOptions
      ),
      patientRepository.count(whereClause, prisma, listOptions)
    ]);
    const normalizedPatients = patients.map(decoratePatientContext);

    return {
      patients: normalizedPatients,
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
        hasNextPage: page < Math.ceil(total / limit),
        hasPreviousPage: page > 1
      }
    };
  } catch (error) {
    if (error instanceof HttpError) throw error;
    const mapped = mapPrismaError(error);
    if (mapped) throw mapped;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Get patient by ID
 *
 * @param {string} id - Patient ID
 * @param {string} userId - User ID for audit
 * @param {string} ipAddress - User IP for audit
 * @returns {Promise<Object>} Patient data
 */
const getPatientById = async (id, userId, ipAddress, scope = {}) => {
  try {
    const patientScope = await resolvePatientScope(scope);
    if (patientScope.__empty__) {
      throw new HttpError('errors.patient.not_found', 404);
    }
    const patient = await patientRepository.findById(
      id,
      PATIENT_RELATION_CONTEXT_INCLUDE,
      patientScope
    );

    if (!patient) {
      throw new HttpError('errors.patient.not_found', 404);
    }

    return decoratePatientContext(patient);
  } catch (error) {
    if (error instanceof HttpError) throw error;
    const mapped = mapPrismaError(error);
    if (mapped) throw mapped;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Create new patient
 * Per prisma.mdc: Mutations must create audit logs
 *
 * @param {Object} data - Patient data
 * @param {string} userId - User ID for audit
 * @param {string} ipAddress - User IP for audit
 * @returns {Promise<Object>} Created patient
 */
const createPatient = async (data, userId, ipAddress, scope = {}) => {
  try {
    const resolvedScope = await resolvePatientScope(scope);
    const tenantInput = pickScopedIdentifier(data, resolvedScope, 'tenant_id');
    const tenantId = await resolveIdentifierForPayload({
      value: tenantInput === undefined ? null : tenantInput,
      field: 'tenant_id',
      model: 'tenant'
    });
    const facilityInput = pickScopedIdentifier(data, resolvedScope, 'facility_id');
    const facilityId = await resolveIdentifierForPayload({
      value: facilityInput,
      field: 'facility_id',
      model: 'facility',
      where: tenantId ? { tenant_id: tenantId } : {},
      nullable: true
    });

    const payload = { ...data };
    const primaryPhone = sanitizeIdentifier(payload.primary_phone);
    const primaryEmail = sanitizeIdentifier(payload.primary_email);
    const primaryIdentifierType = sanitizeIdentifier(payload.primary_identifier_type).toUpperCase();
    const primaryIdentifierValue = sanitizeIdentifier(payload.primary_identifier_value);
    delete payload.primary_phone;
    delete payload.primary_email;
    delete payload.primary_identifier_type;
    delete payload.primary_identifier_value;
    // Never persist national/MRN identifiers as patient PK or public id.
    delete payload.id;
    delete payload.human_friendly_id;

    payload.tenant_id = tenantId;
    payload.facility_id = facilityId;
    if (hasOwn(payload, 'date_of_birth')) {
      payload.date_of_birth = parseDateValue(payload.date_of_birth);
    }

    const shouldCreateRelatedRecords = Boolean(
      primaryPhone || primaryEmail || (primaryIdentifierType && primaryIdentifierValue)
    );

    const patient = shouldCreateRelatedRecords
      ? await prisma.$transaction(async (tx) => {
          const created = await patientRepository.create(payload, tx);

          if (primaryPhone) {
            await patientContactRepository.create(
              {
                tenant_id: tenantId,
                patient_id: created.id,
                contact_type: 'PHONE',
                value: primaryPhone,
                is_primary: true
              },
              tx
            );
          }

          if (primaryEmail) {
            await patientContactRepository.create(
              {
                tenant_id: tenantId,
                patient_id: created.id,
                contact_type: 'EMAIL',
                value: primaryEmail,
                is_primary: !primaryPhone
              },
              tx
            );
          }

          if (primaryIdentifierType && primaryIdentifierValue) {
            await patientIdentifierRepository.create(
              {
                tenant_id: tenantId,
                patient_id: created.id,
                identifier_type: primaryIdentifierType,
                identifier_value: primaryIdentifierValue,
                is_primary: true
              },
              tx
            );
          }

          return created;
        })
      : await patientRepository.create(payload);

    const decorated = await getPatientById(patient.id, userId, ipAddress, { tenant_id: tenantId });

    // Create audit log (non-blocking)
    createAuditLog({
      tenant_id: tenantId,
      user_id: userId,
      action: 'CREATE',
      entity: 'patient',
      entity_id: patient.id,
      diff: { after: patient },
      ip_address: ipAddress
    }).catch(() => {});

    await publishPatientRealtimeEvent(PATIENT_EVENTS.PATIENT_CREATED, decorated, userId);

    return decorated;
  } catch (error) {
    if (error instanceof HttpError) throw error;
    const mapped = mapPrismaError(error);
    if (mapped) throw mapped;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Update patient
 * Per prisma.mdc: Mutations must create audit logs
 *
 * @param {string} id - Patient ID
 * @param {Object} data - Update data
 * @param {string} userId - User ID for audit
 * @param {string} ipAddress - User IP for audit
 * @returns {Promise<Object>} Updated patient
 */
const updatePatient = async (id, data, userId, ipAddress, scope = {}) => {
  try {
    const patientScope = await resolvePatientScope(scope);
    if (patientScope.__empty__) {
      throw new HttpError('errors.patient.not_found', 404);
    }

    // Get current state for audit
    const before = await patientRepository.findById(id, PATIENT_RELATION_CONTEXT_INCLUDE, patientScope);

    if (!before) {
      throw new HttpError('errors.patient.not_found', 404);
    }

    const payload = { ...data };
    const hasPrimaryPhone = Object.prototype.hasOwnProperty.call(payload, 'primary_phone');
    const hasPrimaryEmail = Object.prototype.hasOwnProperty.call(payload, 'primary_email');
    const hasPrimaryIdentifierType = Object.prototype.hasOwnProperty.call(payload, 'primary_identifier_type');
    const hasPrimaryIdentifierValue = Object.prototype.hasOwnProperty.call(payload, 'primary_identifier_value');

    const primaryPhone = sanitizeIdentifier(payload.primary_phone);
    const primaryEmail = sanitizeIdentifier(payload.primary_email);
    const primaryIdentifierType = sanitizeIdentifier(payload.primary_identifier_type).toUpperCase();
    const primaryIdentifierValue = sanitizeIdentifier(payload.primary_identifier_value);
    delete payload.primary_phone;
    delete payload.primary_email;
    delete payload.primary_identifier_type;
    delete payload.primary_identifier_value;
    // Patient UUID / PAT id are immutable system fields.
    delete payload.id;
    delete payload.human_friendly_id;
    delete payload.tenant_id;

    if (hasOwn(payload, 'facility_id')) {
      payload.facility_id = await resolveIdentifierForPayload({
        value: payload.facility_id,
        field: 'facility_id',
        model: 'facility',
        where: before.tenant_id ? { tenant_id: before.tenant_id } : {},
        nullable: true
      });
    }

    if (hasOwn(payload, 'date_of_birth')) {
      payload.date_of_birth = parseDateValue(payload.date_of_birth);
    }

    const shouldUpdateRelatedRecords =
      hasPrimaryPhone || hasPrimaryEmail || hasPrimaryIdentifierType || hasPrimaryIdentifierValue;
    const shouldSynchronizePrimaryContacts = hasPrimaryPhone || hasPrimaryEmail;

    const patient = shouldUpdateRelatedRecords
      ? await prisma.$transaction(async (tx) => {
          const updated = await patientRepository.update(before.id, payload, {}, tx);
          const existingPhone = shouldSynchronizePrimaryContacts
            ? await findPrimaryContactRecord(before.id, before.tenant_id, 'PHONE', tx)
            : null;
          const existingEmail = shouldSynchronizePrimaryContacts
            ? await findPrimaryContactRecord(before.id, before.tenant_id, 'EMAIL', tx)
            : null;
          const effectivePrimaryPhoneExists = hasPrimaryPhone
            ? Boolean(primaryPhone)
            : Boolean(existingPhone?.id);

          if (hasPrimaryPhone) {
            if (primaryPhone) {
              if (existingPhone?.id) {
                await patientContactRepository.update(
                  existingPhone.id,
                  { value: primaryPhone, is_primary: true },
                  tx
                );
              } else {
                await patientContactRepository.create(
                  {
                    tenant_id: before.tenant_id,
                    patient_id: before.id,
                    contact_type: 'PHONE',
                    value: primaryPhone,
                    is_primary: true
                  },
                  tx
                );
              }
            } else if (existingPhone?.id) {
              await patientContactRepository.update(
                existingPhone.id,
                { deleted_at: new Date(), is_primary: false },
                tx
              );
            }
          }

          if (hasPrimaryEmail) {
            const shouldEmailBePrimary = !effectivePrimaryPhoneExists;
            if (primaryEmail) {
              if (existingEmail?.id) {
                await patientContactRepository.update(
                  existingEmail.id,
                  { value: primaryEmail, is_primary: shouldEmailBePrimary },
                  tx
                );
              } else {
                await patientContactRepository.create(
                  {
                    tenant_id: before.tenant_id,
                    patient_id: before.id,
                    contact_type: 'EMAIL',
                    value: primaryEmail,
                    is_primary: shouldEmailBePrimary
                  },
                  tx
                );
              }
            } else if (existingEmail?.id) {
              await patientContactRepository.update(
                existingEmail.id,
                { deleted_at: new Date(), is_primary: false },
                tx
              );
            }
          }

          if (hasPrimaryIdentifierType || hasPrimaryIdentifierValue) {
            const existingIdentifier = await findPrimaryIdentifierRecord(
              before.id,
              before.tenant_id,
              tx
            );

            const fallbackIdentifier = Array.isArray(before.identifiers)
              ? before.identifiers.find((entry) => entry?.is_primary) || before.identifiers[0]
              : null;

            const nextType = hasPrimaryIdentifierType
              ? primaryIdentifierType
              : normalizeText(fallbackIdentifier?.identifier_type).toUpperCase();
            const nextValue = hasPrimaryIdentifierValue
              ? primaryIdentifierValue
              : sanitizeIdentifier(fallbackIdentifier?.identifier_value);

            if (nextType && nextValue) {
              if (existingIdentifier?.id) {
                await patientIdentifierRepository.update(
                  existingIdentifier.id,
                  {
                    identifier_type: nextType,
                    identifier_value: nextValue,
                    is_primary: true
                  },
                  tx
                );
              } else {
                await patientIdentifierRepository.create(
                  {
                    tenant_id: before.tenant_id,
                    patient_id: before.id,
                    identifier_type: nextType,
                    identifier_value: nextValue,
                    is_primary: true
                  },
                  tx
                );
              }
            } else if (existingIdentifier?.id) {
              await patientIdentifierRepository.update(
                existingIdentifier.id,
                { deleted_at: new Date(), is_primary: false },
                tx
              );
            }
          }

          if (shouldSynchronizePrimaryContacts) {
            await synchronizePrimaryPatientContacts(before.id, before.tenant_id, tx);
          }

          return updated;
        })
      : await patientRepository.update(before.id, payload, {});
    const after = await getPatientById(patient.id, userId, ipAddress, { tenant_id: before.tenant_id });

    // Create audit log (non-blocking)
    createAuditLog({
      tenant_id: before.tenant_id,
      user_id: userId,
      action: 'UPDATE',
      entity: 'patient',
      entity_id: patient.id,
      diff: { before, after: patient },
      ip_address: ipAddress
    }).catch(() => {});

    await publishPatientRealtimeEvent(PATIENT_EVENTS.PATIENT_UPDATED, after, userId);

    return after;
  } catch (error) {
    if (error instanceof HttpError) throw error;
    const mapped = mapPrismaError(error);
    if (mapped) throw mapped;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Soft-delete patient with cascade + deletion manifest.
 * Refuses with 409 when live operational state blocks deletion.
 *
 * @param {string} id - Patient ID
 * @param {string} userId - User ID for audit
 * @param {string} ipAddress - User IP for audit
 * @param {Object} [scope]
 * @returns {Promise<void>}
 */
const deletePatient = async (id, userId, ipAddress, scope = {}) => {
  try {
    const patientScope = await resolvePatientScope(scope);
    if (patientScope.__empty__) {
      throw new HttpError('errors.patient.not_found', 404);
    }

    const before = await patientRepository.findById(id, {}, patientScope);

    if (!before || isPurgedPatient(before)) {
      throw new HttpError('errors.patient.not_found', 404);
    }

    const blockers = await findLiveStateBlockers(prisma, before.id);
    if (blockers.length > 0) {
      throw new HttpError('errors.patient.live_state_blocked', 409, blockers);
    }

    const deletedAt = new Date();
    const { batch, counts } = await prisma.$transaction(
      async (tx) =>
        patientDeletionRepository.softDeleteCascadeInTx(tx, {
          patient: before,
          deletedByUserId: userId || null,
          deletedAt,
        }),
      { timeout: 60000 }
    );

    createAuditLog({
      tenant_id: before.tenant_id,
      facility_id: before.facility_id || null,
      user_id: userId,
      action: 'PATIENT_SOFT_DELETED',
      entity: 'patient',
      entity_id: before.id,
      diff: {
        human_friendly_id: before.human_friendly_id || null,
        batch_id: batch.id,
        batch_human_friendly_id: batch.human_friendly_id || null,
        counts,
      },
      ip_address: ipAddress
    }).catch(() => {});

    await publishPatientRealtimeEvent(PATIENT_EVENTS.PATIENT_DELETED, before, userId);
  } catch (error) {
    if (error instanceof HttpError) throw error;
    const mapped = mapPrismaError(error);
    if (mapped) throw mapped;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Preview cascade impact counts for soft-delete confirm UI.
 */
const getPatientDeletionImpact = async (id, userId, ipAddress, scope = {}) => {
  try {
    const patientScope = await resolvePatientScope(scope);
    if (patientScope.__empty__) {
      throw new HttpError('errors.patient.not_found', 404);
    }

    const patient = await patientRepository.findById(id, {}, patientScope);
    if (!patient || isPurgedPatient(patient)) {
      throw new HttpError('errors.patient.not_found', 404);
    }

    const blockers = await findLiveStateBlockers(prisma, patient.id);
    const impact = await patientDeletionRepository.countDeletionImpact(patient.id);

    return {
      patient_id: resolvePublicIdentifier(patient.human_friendly_id, patient.id),
      human_friendly_id: patient.human_friendly_id || null,
      blockers,
      counts: impact,
    };
  } catch (error) {
    if (error instanceof HttpError) throw error;
    const mapped = mapPrismaError(error);
    if (mapped) throw mapped;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Restore a soft-deleted patient using the latest unrestored deletion manifest.
 */
const restorePatient = async (id, userId, ipAddress, scope = {}) => {
  try {
    const patientScope = await resolvePatientScope(scope);
    if (patientScope.__empty__) {
      throw new HttpError('errors.patient.not_found', 404);
    }

    const before = await patientRepository.findByIdIncludingDeleted(
      id,
      {},
      patientScope
    );
    if (!before || isPurgedPatient(before)) {
      throw new HttpError('errors.patient.not_found', 404);
    }
    if (!before.deleted_at) {
      throw new HttpError('errors.patient.not_soft_deleted', 400);
    }

    const batch = await patientDeletionRepository.findLatestUnrestoredBatch(before.id);
    if (!batch) {
      throw new HttpError('errors.patient.not_soft_deleted', 400);
    }

    const restored = await prisma.$transaction(
      async (tx) => {
        const conflicts = await patientDeletionRepository.findRestoreConflicts(tx, before);
        if (conflicts.length > 0) {
          throw new HttpError('errors.patient.restore_conflict', 409, conflicts);
        }
        return patientDeletionRepository.restoreCascadeInTx(tx, {
          patientId: before.id,
          batch,
        });
      },
      { timeout: 60000 }
    );

    createAuditLog({
      tenant_id: before.tenant_id,
      facility_id: before.facility_id || null,
      user_id: userId,
      action: 'PATIENT_RESTORED',
      entity: 'patient',
      entity_id: before.id,
      diff: {
        human_friendly_id: before.human_friendly_id || null,
        batch_id: batch.id,
        batch_human_friendly_id: batch.human_friendly_id || null,
        counts: batch.counts_json || null,
      },
      ip_address: ipAddress
    }).catch(() => {});

    await publishPatientRealtimeEvent(
      PATIENT_EVENTS.PATIENT_RESTORED,
      restored || before,
      userId
    );

    return decoratePatientContext(restored || before);
  } catch (error) {
    if (error instanceof HttpError) throw error;
    const mapped = mapPrismaError(error);
    if (mapped) throw mapped;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Permanently delete an already soft-deleted patient (admin grant required).
 *
 * @param {string} id
 * @param {string} userId
 * @param {string} ipAddress
 * @param {Object} [scope]
 * @param {Object} [options]
 * @param {boolean} [options.confirm]
 * @param {Object} [options.actor]
 */
const permanentDeletePatient = async (
  id,
  userId,
  ipAddress,
  scope = {},
  { confirm = false, actor = {} } = {}
) => {
  try {
    if (confirm !== true) {
      throw new HttpError('errors.patient.permanent_confirm_required', 400);
    }

    assertActorCanPermanentlyDeletePatient(actor);

    const patientScope = await resolvePatientScope(scope);
    if (patientScope.__empty__) {
      throw new HttpError('errors.patient.not_found', 404);
    }

    const before = await patientRepository.findByIdIncludingDeleted(
      id,
      {},
      patientScope
    );
    if (!before || isPurgedPatient(before)) {
      throw new HttpError('errors.patient.already_purged', 404);
    }
    if (!before.deleted_at) {
      throw new HttpError('errors.patient.not_soft_deleted', 400);
    }

    const batch =
      (await patientDeletionRepository.findLatestUnrestoredBatch(before.id)) ||
      (await patientDeletionRepository.findLatestBatchIncludingRestored(before.id));

    const storage = createStorageService();
    const result = await prisma.$transaction(
      async (tx) =>
        patientDeletionRepository.permanentPurgeInTx(tx, {
          patient: before,
          batch,
        }),
      { timeout: 120000 }
    );

    // Blob cleanup after DB commit so a failed storage delete does not roll back
    // the purge; keys are already detached from rows that were hard-deleted.
    for (const key of result.storageKeys || []) {
      try {
        await storage.delete(key);
      } catch (error) {
        logger.error('Failed to delete patient storage object during purge', {
          patientId: before.id,
          storageKey: key,
          error: error.message,
        });
      }
    }

    createAuditLog({
      tenant_id: before.tenant_id,
      facility_id: before.facility_id || null,
      user_id: userId,
      action: 'PATIENT_PERMANENTLY_DELETED',
      entity: 'patient',
      entity_id: before.id,
      diff: {
        human_friendly_id: before.human_friendly_id || null,
        batch_id: batch?.id || null,
        batch_human_friendly_id: batch?.human_friendly_id || null,
        irreversible: true,
        anonymized: result.anonymized,
        retained_references: result.retained_references,
        counts: result.counts,
        storage_keys_removed: (result.storageKeys || []).length,
      },
      ip_address: ipAddress
    }).catch(() => {});

    await publishPatientRealtimeEvent(
      PATIENT_EVENTS.PATIENT_PERMANENTLY_DELETED,
      before,
      userId
    );
  } catch (error) {
    if (error instanceof HttpError) throw error;
    const mapped = mapPrismaError(error);
    if (mapped) throw mapped;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Get patient identifiers (nested resource)
 *
 * @param {string} patientId - Patient ID
 * @param {number} page - Page number
 * @param {number} limit - Items per page
 * @param {string} sortBy - Sort field
 * @param {string} order - Sort order
 * @param {string} userId - User ID for audit
 * @param {string} ipAddress - User IP for audit
 * @returns {Promise<Object>} Patient identifiers with pagination
 */
const getPatientIdentifiers = async (
  patientId,
  page = 1,
  limit = 20,
  sortBy = 'created_at',
  order = 'desc',
  userId,
  ipAddress,
  scope = {}
) => {
  try {
    const patient = await ensurePatientExists(patientId, scope);
    const patientIdentifierService = require('@services/patient-identifier/patient-identifier.service');
    const result = await patientIdentifierService.listPatientIdentifiers(
      { patient_id: patient.id },
      page,
      limit,
      sortBy,
      order,
      userId,
      ipAddress
    );

    return {
      patientIdentifiers: result.patientIdentifiers || [],
      pagination: result.pagination
    };
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Get patient contacts (nested resource)
 */
const getPatientContacts = async (
  patientId,
  page = 1,
  limit = 20,
  sortBy = 'created_at',
  order = 'desc',
  userId,
  ipAddress,
  scope = {}
) => {
  try {
    const patient = await ensurePatientExists(patientId, scope);
    const patientContactService = require('@services/patient-contact/patient-contact.service');
    const result = await patientContactService.listPatientContacts(
      { patient_id: patient.id },
      page,
      limit,
      sortBy,
      order,
      userId,
      ipAddress
    );

    return {
      patientContacts: result.patientContacts || [],
      pagination: result.pagination
    };
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Get patient guardians (nested resource)
 */
const getPatientGuardians = async (
  patientId,
  page = 1,
  limit = 20,
  sortBy = 'created_at',
  order = 'desc',
  userId,
  ipAddress,
  scope = {}
) => {
  try {
    const patient = await ensurePatientExists(patientId, scope);
    const patientGuardianService = require('@services/patient-guardian/patient-guardian.service');
    const result = await patientGuardianService.listPatientGuardians(
      { patient_id: patient.id },
      page,
      limit,
      sortBy,
      order,
      userId,
      ipAddress
    );

    return {
      patientGuardians: result.patientGuardians || [],
      pagination: result.pagination
    };
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Get patient allergies (nested resource)
 */
const getPatientAllergies = async (
  patientId,
  page = 1,
  limit = 20,
  sortBy = 'created_at',
  order = 'desc',
  scope = {}
) => {
  try {
    const patient = await ensurePatientExists(patientId, scope);
    const patientAllergyService = require('@services/patient-allergy/patient-allergy.service');
    const result = await patientAllergyService.listPatientAllergies(
      { patient_id: patient.id },
      page,
      limit,
      sortBy,
      order
    );

    return {
      patientAllergies: result.items || [],
      pagination: result.pagination
    };
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Get patient medical histories (nested resource)
 */
const getPatientMedicalHistories = async (
  patientId,
  page = 1,
  limit = 20,
  sortBy = 'created_at',
  order = 'desc',
  scope = {}
) => {
  try {
    const patient = await ensurePatientExists(patientId, scope);
    const patientMedicalHistoryService = require('@services/patient-medical-history/patient-medical-history.service');
    const result = await patientMedicalHistoryService.listPatientMedicalHistories(
      { patient_id: patient.id },
      page,
      limit,
      sortBy,
      order
    );

    return {
      patientMedicalHistories: result.items || [],
      pagination: result.pagination
    };
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

module.exports = {
  listPatients,
  getPatientById,
  createPatient,
  updatePatient,
  deletePatient,
  restorePatient,
  permanentDeletePatient,
  getPatientDeletionImpact,
  getPatientIdentifiers,
  getPatientContacts,
  getPatientGuardians,
  getPatientAllergies,
  getPatientMedicalHistories
};
