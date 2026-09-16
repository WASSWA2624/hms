import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/features/patients/domain/entities/patient_entities.dart';
import 'package:hosspi_hms/shared/data/data.dart';

abstract interface class PatientRepository {
  Future<Result<AppPage<Patient>>> listPatients(PatientListQuery query);

  Future<Result<PatientRegistryOverview>> loadOverview();

  Future<Result<PatientReferenceData>> loadReferenceData();

  Future<Result<AppPage<PatientDuplicateCandidate>>> listDuplicateCandidates(
    PatientDuplicateQuery query,
  );

  Future<Result<PatientDetail>> loadPatientDetail(String patientId);

  Future<Result<PatientMergePreview>> previewPatientMerge({
    required String primaryPatientId,
    required String secondaryPatientId,
  });

  Future<Result<PatientMutationResult>> mergePatients({
    required String primaryPatientId,
    required String secondaryPatientId,
    Map<String, Object?> summary = const <String, Object?>{},
  });

  Future<Result<PatientMutationResult>> dismissDuplicateCandidate({
    required String reviewId,
    required String primaryPatientId,
    required String secondaryPatientId,
    String? reason,
  });

  Future<Result<Patient>> createPatient(Map<String, Object?> payload);

  Future<Result<Patient>> updatePatient(
    String patientId,
    Map<String, Object?> payload,
  );

  Future<Result<PatientMutationResult>> deletePatient(String patientId);

  Future<Result<PatientDeletionImpact>> getDeletionImpact(String patientId);

  Future<Result<Patient>> restorePatient(String patientId);

  Future<Result<PatientMutationResult>> permanentDeletePatient(String patientId);

  Future<Result<void>> createRelatedRecord(
    PatientRelatedResource resource,
    Map<String, Object?> payload,
  );

  Future<Result<void>> updateRelatedRecord(
    PatientRelatedResource resource,
    String recordId,
    Map<String, Object?> payload,
  );

  Future<Result<void>> deleteRelatedRecord(
    PatientRelatedResource resource,
    String recordId,
  );

  /// Records PHI audit for client-side print/export of authorized sections.
  Future<Result<void>> recordPatientReportPrintEvent({
    required String patientId,
    required List<String> sections,
    String? encounterId,
    String reportType = 'patient_clinical',
    String action = 'print',
  });
}
