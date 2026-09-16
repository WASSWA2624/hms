/**
 * Permanently deleted patients that retained records still point at.
 *
 * When financial, insurance, audit, or mortuary rows must keep a patient FK,
 * permanent delete keeps the patient row as a tombstone and erases identifying
 * fields. `first_name` is set to the reserved marker below so lists can exclude
 * purged rows the same way purged accounts use `@purged.invalid`.
 *
 * @module lib/patient/purged-patient
 */

/** Stands in for the erased first name on a profile that has to stay. */
const PURGED_PATIENT_NAME = 'Deleted patient';

const isPurgedPatient = (patient) =>
  String(patient?.first_name || '').trim() === PURGED_PATIENT_NAME;

/** Fields written onto a patient row that must remain as a tombstone. */
const purgedPatientFields = (patientId) => ({
  first_name: PURGED_PATIENT_NAME,
  last_name: null,
  date_of_birth: null,
  gender: null,
  is_active: false,
  extension_json: patientId
    ? { purged: true, purged_patient_id: patientId }
    : { purged: true },
});

/** Where clause matching patients that have not been purged. */
const notPurgedWhere = () => ({
  NOT: { first_name: PURGED_PATIENT_NAME },
});

module.exports = {
  PURGED_PATIENT_NAME,
  isPurgedPatient,
  purgedPatientFields,
  notPurgedWhere,
};
