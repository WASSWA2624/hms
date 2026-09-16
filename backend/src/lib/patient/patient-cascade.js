/**
 * Declarative cascade map for patient soft-delete, restore, and permanent purge.
 *
 * Every Prisma model with `patient_id`, `participant_patient_id`, or
 * `sender_patient_id` must appear here (enforced by schema-driven tests), plus
 * clinical/financial children reached via encounter, admission, orders, etc.
 *
 * @module lib/patient/patient-cascade
 */

const entry = ({
  model,
  reach,
  softDelete = 'soft_delete',
  restore = softDelete === 'soft_delete' ? 'restore' : 'noop',
  purge = 'hard_delete',
  category,
  storageKeyField = null,
  anonymizeFields = null,
  collectOnlyActive = true,
}) => ({
  model,
  reach,
  softDelete,
  restore,
  purge,
  category,
  storageKeyField,
  anonymizeFields,
  collectOnlyActive,
});

const direct = (field = 'patient_id') => ({ type: 'direct', field });
const via = (parent, parentField) => ({ type: 'via', parent, parentField });

/**
 * Ordered so parents are collected before children (via reach resolves parent ids).
 * Hard-delete walks this list in reverse.
 */
const PATIENT_CASCADE_ENTRIES = Object.freeze([
  // --- Direct demographic / clinical / ops ---
  entry({
    model: 'address',
    reach: direct(),
    category: 'demographic',
    purge: 'hard_delete',
  }),
  entry({
    model: 'contact',
    reach: direct(),
    category: 'demographic',
    purge: 'hard_delete',
  }),
  entry({
    model: 'patient_identifier',
    reach: direct(),
    category: 'demographic',
    purge: 'hard_delete',
  }),
  entry({
    model: 'patient_contact',
    reach: direct(),
    category: 'demographic',
    purge: 'hard_delete',
  }),
  entry({
    model: 'patient_guardian',
    reach: direct(),
    category: 'demographic',
    purge: 'hard_delete',
  }),
  entry({
    model: 'patient_allergy',
    reach: direct(),
    category: 'clinical',
    purge: 'hard_delete',
  }),
  entry({
    model: 'patient_medical_history',
    reach: direct(),
    category: 'clinical',
    purge: 'hard_delete',
  }),
  entry({
    model: 'patient_document',
    reach: direct(),
    category: 'documents',
    purge: 'hard_delete',
    storageKeyField: 'storage_key',
  }),
  entry({
    model: 'consent',
    reach: direct(),
    category: 'demographic',
    purge: 'hard_delete',
  }),
  entry({
    model: 'appointment',
    reach: direct(),
    category: 'clinical',
    purge: 'hard_delete',
  }),
  entry({
    model: 'appointment_participant',
    reach: direct('participant_patient_id'),
    category: 'clinical',
    purge: 'hard_delete',
  }),
  entry({
    model: 'appointment_reminder',
    reach: via('appointment', 'appointment_id'),
    category: 'clinical',
    purge: 'hard_delete',
  }),
  entry({
    model: 'visit_queue',
    reach: direct(),
    category: 'clinical',
    purge: 'hard_delete',
  }),
  entry({
    model: 'encounter',
    reach: direct(),
    category: 'clinical',
    purge: 'hard_delete',
  }),
  entry({
    model: 'admission',
    reach: direct(),
    category: 'clinical',
    purge: 'hard_delete',
  }),
  entry({
    model: 'lab_order',
    reach: direct(),
    category: 'orders',
    purge: 'hard_delete',
  }),
  entry({
    model: 'radiology_order',
    reach: direct(),
    category: 'orders',
    purge: 'hard_delete',
  }),
  entry({
    model: 'pharmacy_order',
    reach: direct(),
    category: 'orders',
    purge: 'hard_delete',
  }),
  entry({
    model: 'adverse_event',
    reach: direct(),
    category: 'clinical',
    purge: 'hard_delete',
  }),
  entry({
    model: 'emergency_case',
    reach: direct(),
    category: 'clinical',
    purge: 'hard_delete',
  }),
  entry({
    model: 'invoice',
    reach: direct(),
    category: 'financial',
    purge: 'anonymize',
    anonymizeFields: { notes: null },
  }),
  entry({
    model: 'billable_charge_event',
    reach: direct(),
    category: 'financial',
    purge: 'anonymize',
    anonymizeFields: {},
  }),
  entry({
    model: 'payment',
    reach: direct(),
    category: 'financial',
    purge: 'anonymize',
    anonymizeFields: { transaction_ref: null, notes: null },
  }),
  entry({
    model: 'patient_insurance_enrollment',
    reach: direct(),
    category: 'insurance',
    purge: 'anonymize',
    anonymizeFields: {
      member_id: null,
      notes: null,
      extension_json: null,
    },
  }),
  entry({
    model: 'pre_authorization',
    reach: direct(),
    category: 'insurance',
    purge: 'anonymize',
    anonymizeFields: {
      reason: null,
      insurer_reference: null,
      notes: null,
    },
  }),
  entry({
    model: 'break_glass_access',
    reach: direct(),
    softDelete: 'retain',
    restore: 'noop',
    purge: 'retain',
    category: 'audit',
  }),
  entry({
    model: 'patient_report_job',
    reach: direct(),
    category: 'documents',
    purge: 'hard_delete',
    storageKeyField: 'output_storage_path',
  }),
  entry({
    model: 'phi_access_log',
    reach: direct(),
    softDelete: 'retain',
    restore: 'noop',
    purge: 'retain',
    category: 'audit',
  }),
  entry({
    model: 'mortuary_case',
    reach: direct(),
    category: 'mortuary',
    purge: 'anonymize',
    anonymizeFields: {
      next_of_kin_name: null,
      authorised_contact_name: null,
      authorised_contact_phone: null,
      notes: null,
      extension_json: null,
    },
  }),
  entry({
    model: 'message',
    reach: direct('sender_patient_id'),
    category: 'messaging',
    purge: 'hard_delete',
  }),
  // Manifest rows: not cascade soft-deleted (a new batch is written instead).
  // Hard-deleted only when the patient row itself can be removed.
  entry({
    model: 'patient_deletion_batch',
    reach: direct(),
    softDelete: 'retain',
    restore: 'noop',
    purge: 'retain',
    category: 'audit',
    collectOnlyActive: false,
  }),

  // --- Via encounter ---
  entry({
    model: 'clinical_note',
    reach: via('encounter', 'encounter_id'),
    category: 'clinical',
  }),
  entry({
    model: 'diagnosis',
    reach: via('encounter', 'encounter_id'),
    category: 'clinical',
  }),
  entry({
    model: 'procedure',
    reach: via('encounter', 'encounter_id'),
    category: 'clinical',
  }),
  entry({
    model: 'vital_sign',
    reach: via('encounter', 'encounter_id'),
    category: 'clinical',
  }),
  entry({
    model: 'care_plan',
    reach: via('encounter', 'encounter_id'),
    category: 'clinical',
  }),
  entry({
    model: 'clinical_alert',
    reach: via('encounter', 'encounter_id'),
    category: 'clinical',
  }),
  entry({
    model: 'referral',
    reach: via('encounter', 'encounter_id'),
    category: 'clinical',
  }),
  entry({
    model: 'follow_up',
    reach: via('encounter', 'encounter_id'),
    category: 'clinical',
  }),
  entry({
    model: 'theatre_case',
    reach: via('encounter', 'encounter_id'),
    category: 'clinical',
  }),
  entry({
    model: 'therapy_episode',
    reach: via('encounter', 'encounter_id'),
    category: 'clinical',
  }),

  // --- Via admission ---
  entry({
    model: 'bed_assignment',
    reach: via('admission', 'admission_id'),
    category: 'clinical',
  }),
  entry({
    model: 'ward_round',
    reach: via('admission', 'admission_id'),
    category: 'clinical',
  }),
  entry({
    model: 'nursing_note',
    reach: via('admission', 'admission_id'),
    category: 'clinical',
  }),
  entry({
    model: 'medication_administration',
    reach: via('admission', 'admission_id'),
    category: 'clinical',
  }),
  entry({
    model: 'discharge_summary',
    reach: via('admission', 'admission_id'),
    category: 'clinical',
  }),
  entry({
    model: 'transfer_request',
    reach: via('admission', 'admission_id'),
    category: 'clinical',
  }),
  entry({
    model: 'icu_stay',
    reach: via('admission', 'admission_id'),
    category: 'clinical',
  }),

  // --- Via ICU / theatre / therapy ---
  entry({
    model: 'icu_observation',
    reach: via('icu_stay', 'icu_stay_id'),
    category: 'clinical',
  }),
  entry({
    model: 'critical_alert',
    reach: via('icu_stay', 'icu_stay_id'),
    category: 'clinical',
  }),
  entry({
    model: 'anesthesia_record',
    reach: via('theatre_case', 'theatre_case_id'),
    category: 'clinical',
  }),
  entry({
    model: 'post_op_note',
    reach: via('theatre_case', 'theatre_case_id'),
    category: 'clinical',
  }),
  entry({
    model: 'theatre_case_resource_allocation',
    reach: via('theatre_case', 'theatre_case_id'),
    category: 'clinical',
  }),
  entry({
    model: 'theatre_case_checklist_item',
    reach: via('theatre_case', 'theatre_case_id'),
    category: 'clinical',
  }),
  entry({
    model: 'anesthesia_observation',
    reach: via('theatre_case', 'theatre_case_id'),
    category: 'clinical',
  }),
  entry({
    model: 'therapy_session',
    reach: via('therapy_episode', 'therapy_episode_id'),
    category: 'clinical',
  }),

  // --- Via orders ---
  entry({
    model: 'lab_order_item',
    reach: via('lab_order', 'lab_order_id'),
    category: 'orders',
  }),
  entry({
    model: 'lab_sample',
    reach: via('lab_order', 'lab_order_id'),
    category: 'orders',
  }),
  entry({
    model: 'lab_result',
    reach: via('lab_order_item', 'lab_order_item_id'),
    category: 'orders',
  }),
  entry({
    model: 'radiology_result',
    reach: via('radiology_order', 'radiology_order_id'),
    category: 'orders',
  }),
  entry({
    model: 'imaging_study',
    reach: via('radiology_order', 'radiology_order_id'),
    category: 'orders',
  }),
  entry({
    model: 'imaging_asset',
    reach: via('imaging_study', 'imaging_study_id'),
    category: 'orders',
    storageKeyField: 'storage_key',
  }),
  entry({
    model: 'pacs_link',
    reach: via('imaging_study', 'imaging_study_id'),
    category: 'orders',
  }),
  entry({
    model: 'radiology_result_attestation',
    reach: via('radiology_result', 'radiology_result_id'),
    category: 'orders',
  }),
  entry({
    model: 'pharmacy_order_item',
    reach: via('pharmacy_order', 'pharmacy_order_id'),
    category: 'orders',
  }),
  entry({
    model: 'pharmacy_dispense_attestation',
    reach: via('pharmacy_order', 'pharmacy_order_id'),
    category: 'orders',
  }),
  entry({
    model: 'dispense_log',
    reach: via('pharmacy_order_item', 'pharmacy_order_item_id'),
    category: 'orders',
  }),

  // --- Via invoice / payment ---
  entry({
    model: 'invoice_item',
    reach: via('invoice', 'invoice_id'),
    category: 'financial',
    purge: 'anonymize',
    anonymizeFields: { description: null },
  }),
  entry({
    model: 'insurance_claim',
    reach: via('invoice', 'invoice_id'),
    category: 'insurance',
    purge: 'anonymize',
    anonymizeFields: { payer_reference: null, notes: null },
  }),
  entry({
    model: 'billing_adjustment',
    reach: via('invoice', 'invoice_id'),
    category: 'financial',
    purge: 'anonymize',
    anonymizeFields: { reason: null },
  }),
  entry({
    model: 'subscription_invoice',
    reach: via('invoice', 'invoice_id'),
    category: 'financial',
    purge: 'anonymize',
    anonymizeFields: {},
  }),
  entry({
    model: 'refund',
    reach: via('payment', 'payment_id'),
    category: 'financial',
    purge: 'anonymize',
    anonymizeFields: { reason: null },
  }),

  // --- Via emergency ---
  entry({
    model: 'triage_assessment',
    reach: via('emergency_case', 'emergency_case_id'),
    category: 'clinical',
  }),
  entry({
    model: 'emergency_response',
    reach: via('emergency_case', 'emergency_case_id'),
    category: 'clinical',
  }),
  entry({
    model: 'ambulance_dispatch',
    reach: via('emergency_case', 'emergency_case_id'),
    category: 'clinical',
  }),
  entry({
    model: 'ambulance_trip',
    reach: via('emergency_case', 'emergency_case_id'),
    category: 'clinical',
  }),

  // --- Via mortuary (custody retained) ---
  entry({
    model: 'mortuary_storage_assignment',
    reach: via('mortuary_case', 'mortuary_case_id'),
    softDelete: 'soft_delete',
    purge: 'retain',
    category: 'mortuary',
  }),
  entry({
    model: 'mortuary_custody_event',
    reach: via('mortuary_case', 'mortuary_case_id'),
    softDelete: 'soft_delete',
    purge: 'retain',
    category: 'mortuary',
  }),
  entry({
    model: 'mortuary_viewing',
    reach: via('mortuary_case', 'mortuary_case_id'),
    softDelete: 'soft_delete',
    purge: 'retain',
    category: 'mortuary',
  }),
  entry({
    model: 'mortuary_post_mortem_request',
    reach: via('mortuary_case', 'mortuary_case_id'),
    softDelete: 'soft_delete',
    purge: 'retain',
    category: 'mortuary',
  }),
  entry({
    model: 'mortuary_release_authorisation',
    reach: via('mortuary_case', 'mortuary_case_id'),
    softDelete: 'soft_delete',
    purge: 'retain',
    category: 'mortuary',
  }),
  entry({
    model: 'mortuary_billable_event',
    reach: via('mortuary_case', 'mortuary_case_id'),
    category: 'mortuary',
    purge: 'anonymize',
    anonymizeFields: { description: null },
  }),

  // --- Via break-glass / messaging ---
  entry({
    model: 'break_glass_review',
    reach: via('break_glass_access', 'break_glass_access_id'),
    softDelete: 'retain',
    restore: 'noop',
    purge: 'retain',
    category: 'audit',
  }),
  entry({
    model: 'message_attachment',
    reach: via('message', 'message_id'),
    category: 'messaging',
    purge: 'hard_delete',
    storageKeyField: 'storage_key',
  }),
]);

const ACTIVE_ADMISSION_STATUS = 'ADMITTED';
const OPEN_ENCOUNTER_STATUS = 'OPEN';
const ACTIVE_THEATRE_STATUSES = Object.freeze(['SCHEDULED', 'IN_PROGRESS']);
const IN_PROGRESS_LAB_STATUSES = Object.freeze(['ORDERED', 'COLLECTED', 'IN_PROCESS']);
const IN_PROGRESS_RADIOLOGY_STATUSES = Object.freeze([
  'ORDERED',
  'IN_PROCESS',
  'AWAITING_REPORT',
]);
const IN_PROGRESS_PHARMACY_STATUSES = Object.freeze([
  'ORDERED',
  'PARTIALLY_DISPENSED',
]);

const listCascadeEntries = () => [...PATIENT_CASCADE_ENTRIES];

const listDirectPatientFkModels = () =>
  PATIENT_CASCADE_ENTRIES.filter((row) => row.reach?.type === 'direct').map(
    (row) => ({
      model: row.model,
      field: row.reach.field || 'patient_id',
    })
  );

const getSoftDeleteModels = () =>
  PATIENT_CASCADE_ENTRIES.filter((row) => row.softDelete === 'soft_delete').map(
    (row) => row.model
  );

const getRestoreModels = () =>
  PATIENT_CASCADE_ENTRIES.filter((row) => row.restore === 'restore').map(
    (row) => row.model
  );

const getHardDeleteModels = () =>
  PATIENT_CASCADE_ENTRIES.filter((row) => row.purge === 'hard_delete').map(
    (row) => row.model
  );

const getAnonymizeModels = () =>
  PATIENT_CASCADE_ENTRIES.filter((row) => row.purge === 'anonymize').map(
    (row) => row.model
  );

const getRetainPurgeModels = () =>
  PATIENT_CASCADE_ENTRIES.filter((row) => row.purge === 'retain').map(
    (row) => row.model
  );

const getStorageKeyEntries = () =>
  PATIENT_CASCADE_ENTRIES.filter((row) => row.storageKeyField);

const getEntriesByCategory = () => {
  const byCategory = {};
  for (const row of PATIENT_CASCADE_ENTRIES) {
    if (!byCategory[row.category]) byCategory[row.category] = [];
    byCategory[row.category].push(row.model);
  }
  return byCategory;
};

/**
 * Live operational state that must be cleared before soft delete.
 * @param {Object} client - Prisma client or transaction
 * @param {string} patientId
 * @returns {Promise<Array<{ code: string, model: string, count: number }>>}
 */
const findLiveStateBlockers = async (client, patientId) => {
  const blockers = [];

  const activeAdmissions = await client.admission.count({
    where: {
      patient_id: patientId,
      deleted_at: null,
      status: ACTIVE_ADMISSION_STATUS,
    },
  });
  if (activeAdmissions > 0) {
    blockers.push({
      code: 'active_admission',
      model: 'admission',
      count: activeAdmissions,
    });
  }

  const admissionIds = (
    await client.admission.findMany({
      where: { patient_id: patientId, deleted_at: null },
      select: { id: true },
    })
  ).map((row) => row.id);

  if (admissionIds.length > 0) {
    const occupiedBeds = await client.bed_assignment.count({
      where: {
        admission_id: { in: admissionIds },
        deleted_at: null,
        released_at: null,
      },
    });
    if (occupiedBeds > 0) {
      blockers.push({
        code: 'occupied_bed',
        model: 'bed_assignment',
        count: occupiedBeds,
      });
    }

    const activeIcu = await client.icu_stay.count({
      where: {
        admission_id: { in: admissionIds },
        deleted_at: null,
        ended_at: null,
      },
    });
    if (activeIcu > 0) {
      blockers.push({
        code: 'active_icu_stay',
        model: 'icu_stay',
        count: activeIcu,
      });
    }
  }

  const encounterIds = (
    await client.encounter.findMany({
      where: { patient_id: patientId, deleted_at: null },
      select: { id: true },
    })
  ).map((row) => row.id);

  const openEncounters = await client.encounter.count({
    where: {
      patient_id: patientId,
      deleted_at: null,
      status: OPEN_ENCOUNTER_STATUS,
    },
  });
  if (openEncounters > 0) {
    blockers.push({
      code: 'open_encounter',
      model: 'encounter',
      count: openEncounters,
    });
  }

  if (encounterIds.length > 0) {
    const activeTheatre = await client.theatre_case.count({
      where: {
        encounter_id: { in: encounterIds },
        deleted_at: null,
        status: { in: [...ACTIVE_THEATRE_STATUSES] },
      },
    });
    if (activeTheatre > 0) {
      blockers.push({
        code: 'active_theatre_case',
        model: 'theatre_case',
        count: activeTheatre,
      });
    }
  }

  const inProgressLab = await client.lab_order.count({
    where: {
      patient_id: patientId,
      deleted_at: null,
      status: { in: [...IN_PROGRESS_LAB_STATUSES] },
    },
  });
  if (inProgressLab > 0) {
    blockers.push({
      code: 'in_progress_lab_order',
      model: 'lab_order',
      count: inProgressLab,
    });
  }

  const inProgressRadiology = await client.radiology_order.count({
    where: {
      patient_id: patientId,
      deleted_at: null,
      status: { in: [...IN_PROGRESS_RADIOLOGY_STATUSES] },
    },
  });
  if (inProgressRadiology > 0) {
    blockers.push({
      code: 'in_progress_radiology_order',
      model: 'radiology_order',
      count: inProgressRadiology,
    });
  }

  const inProgressPharmacy = await client.pharmacy_order.count({
    where: {
      patient_id: patientId,
      deleted_at: null,
      status: { in: [...IN_PROGRESS_PHARMACY_STATUSES] },
    },
  });
  if (inProgressPharmacy > 0) {
    blockers.push({
      code: 'in_progress_pharmacy_order',
      model: 'pharmacy_order',
      count: inProgressPharmacy,
    });
  }

  return blockers;
};

module.exports = {
  PATIENT_CASCADE_ENTRIES,
  ACTIVE_ADMISSION_STATUS,
  OPEN_ENCOUNTER_STATUS,
  ACTIVE_THEATRE_STATUSES,
  IN_PROGRESS_LAB_STATUSES,
  IN_PROGRESS_RADIOLOGY_STATUSES,
  IN_PROGRESS_PHARMACY_STATUSES,
  listCascadeEntries,
  listDirectPatientFkModels,
  getSoftDeleteModels,
  getRestoreModels,
  getHardDeleteModels,
  getAnonymizeModels,
  getRetainPurgeModels,
  getStorageKeyEntries,
  getEntriesByCategory,
  findLiveStateBlockers,
};
