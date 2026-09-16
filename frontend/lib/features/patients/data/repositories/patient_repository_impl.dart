import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/network/api_client.dart';
import 'package:hosspi_hms/core/network/api_endpoints.dart';
import 'package:hosspi_hms/core/network/network_providers.dart';
import 'package:hosspi_hms/features/patients/data/dtos/patient_dtos.dart';
import 'package:hosspi_hms/features/patients/domain/entities/patient_entities.dart';
import 'package:hosspi_hms/features/patients/domain/repositories/patient_repository.dart';
import 'package:hosspi_hms/shared/data/data.dart';

final patientRepositoryProvider = Provider<PatientRepository>((ref) {
  return PatientRepositoryImpl(apiClient: ref.watch(apiClientProvider));
});

final class PatientRepositoryImpl implements PatientRepository {
  PatientRepositoryImpl({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  @override
  Future<Result<AppPage<Patient>>> listPatients(PatientListQuery query) {
    final AppPageRequest request = query.pageRequest;
    return _apiClient.get<AppPage<Patient>>(
      ApiEndpoints.collection(HmsApiResource.patients),
      queryParameters: _withoutEmpty(<String, Object?>{
        'page': request.pageIndex + 1,
        'limit': request.pageSize,
        'search': query.search,
        'patient_id': query.patientId,
        'contact': query.contact,
        'facility_id': query.facilityId,
        'gender': query.gender,
        'is_active': query.isActive,
        'consent_state': query.consentState,
        'appointment_status': query.appointmentStatus,
        'visit_date': _dateOnly(query.visitDate),
        'visit_from': _dateOnly(query.visitFrom),
        'visit_to': _dateOnly(query.visitTo),
        'created_from': _dateOnly(query.createdFrom),
        'created_to': _dateOnly(query.createdTo),
        'date_of_birth_from': _dateOnly(query.dateOfBirthFrom),
        'date_of_birth_to': _dateOnly(query.dateOfBirthTo),
        'has_active_admission': query.hasActiveAdmission,
        'has_outstanding_balance': query.hasOutstandingBalance,
        'record_state': query.recordState.queryValue,
        'include_deleted': query.effectiveIncludeDeleted ? true : null,
        'sort_by': 'updated_at',
        'order': 'desc',
      }),
      decoder: (Object? data) =>
          PatientPageDto.fromResponse(data, request).page,
    );
  }

  @override
  Future<Result<PatientRegistryOverview>> loadOverview() {
    return _apiClient.get<PatientRegistryOverview>(
      ApiEndpoints.apiV1(<String>[
        HmsApiResource.patients.path,
        'workspace',
        'overview',
      ]),
      decoder: (Object? data) =>
          PatientRegistryOverviewDto.fromResponse(data).toEntity(),
    );
  }

  @override
  Future<Result<PatientReferenceData>> loadReferenceData() {
    return _apiClient.get<PatientReferenceData>(
      ApiEndpoints.apiV1(<String>[
        HmsApiResource.patients.path,
        'workspace',
        'reference-data',
      ]),
      decoder: (Object? data) =>
          PatientReferenceDataDto.fromResponse(data).toEntity(),
    );
  }

  @override
  Future<Result<AppPage<PatientDuplicateCandidate>>> listDuplicateCandidates(
    PatientDuplicateQuery query,
  ) {
    final AppPageRequest request = query.pageRequest;
    return _apiClient.get<AppPage<PatientDuplicateCandidate>>(
      ApiEndpoints.apiV1(<String>[HmsApiResource.patients.path, 'duplicates']),
      queryParameters: _withoutEmpty(<String, Object?>{
        'page': request.pageIndex + 1,
        'limit': request.pageSize,
        'patient_id': query.patientId,
        'tenant_id': query.tenantId,
        'facility_id': query.facilityId,
        'first_name': query.firstName,
        'last_name': query.lastName,
        'date_of_birth': _dateOnly(query.dateOfBirth),
        'gender': query.gender,
        'phone': query.phone,
        'email': query.email,
        'identifier_type': query.identifierType,
        'identifier_value': query.identifierValue,
      }),
      decoder: (Object? data) =>
          PatientDuplicatePageDto.fromResponse(data, request).page,
    );
  }

  @override
  Future<Result<PatientDetail>> loadPatientDetail(String patientId) async {
    final Result<Patient> patientResult = await _apiClient.get<Patient>(
      ApiEndpoints.byId(HmsApiResource.patients, patientId),
      decoder: (Object? data) => PatientDto(decodeDataMap(data)).toEntity(),
    );
    final Patient? patient = _valueOrNull(patientResult);
    if (patient == null) {
      return Result<PatientDetail>.failure(_failureOf(patientResult)!);
    }

    // Fan out the per-patient workspace reads concurrently. Building the
    // futures before awaiting starts them in parallel, replacing the previous
    // sequential round-trips (workspace + timeline + seven related lists) with
    // a single concurrent batch. Any failure short-circuits to that failure.
    final Future<Result<PatientWorkspaceSnapshot>> workspaceFuture = _apiClient
        .get<PatientWorkspaceSnapshot>(
          ApiEndpoints.apiV1(<String>[
            HmsApiResource.patients.path,
            patient.id,
            'workspace',
          ]),
          decoder: (Object? data) =>
              PatientWorkspaceDto(decodeDataMap(data)).toSnapshot(),
        );
    final Future<Result<List<PatientTimelineItem>>> timelineFuture = _apiClient
        .get<List<PatientTimelineItem>>(
          ApiEndpoints.apiV1(<String>[
            HmsApiResource.patients.path,
            patient.id,
            'timeline',
          ]),
          queryParameters: const <String, Object?>{'page': 1, 'limit': 12},
          decoder: (Object? data) => decodeDataList(data)
              .map(PatientTimelineItemDto.new)
              .map((PatientTimelineItemDto dto) => dto.toEntity())
              .toList(growable: false),
        );
    final Future<Result<List<PatientIdentifier>>> identifiersFuture =
        _fetchRelatedList<PatientIdentifier>(
          HmsApiResource.patientIdentifiers,
          patient.id,
          decodeIdentifierList,
        );
    final Future<Result<List<PatientContact>>> contactsFuture =
        _fetchRelatedList<PatientContact>(
          HmsApiResource.patientContacts,
          patient.id,
          decodeContactList,
        );
    final Future<Result<List<PatientGuardian>>> guardiansFuture =
        _fetchRelatedList<PatientGuardian>(
          HmsApiResource.patientGuardians,
          patient.id,
          decodeGuardianList,
        );
    final Future<Result<List<PatientAllergy>>> allergiesFuture =
        _fetchRelatedList<PatientAllergy>(
          HmsApiResource.patientAllergies,
          patient.id,
          decodeAllergyList,
        );
    final Future<Result<List<PatientMedicalHistory>>> medicalHistoriesFuture =
        _fetchRelatedList<PatientMedicalHistory>(
          HmsApiResource.patientMedicalHistories,
          patient.id,
          decodeMedicalHistoryList,
        );
    final Future<Result<List<PatientConsent>>> consentsFuture =
        _fetchRelatedList<PatientConsent>(
          HmsApiResource.consents,
          patient.id,
          decodeConsentList,
        );

    final Result<PatientWorkspaceSnapshot> workspaceResult =
        await workspaceFuture;
    final Result<List<PatientTimelineItem>> timelineResult =
        await timelineFuture;
    final Result<List<PatientIdentifier>> identifiersResult =
        await identifiersFuture;
    final Result<List<PatientContact>> contactsResult = await contactsFuture;
    final Result<List<PatientGuardian>> guardiansResult = await guardiansFuture;
    final Result<List<PatientAllergy>> allergiesResult = await allergiesFuture;
    final Result<List<PatientMedicalHistory>> medicalHistoriesResult =
        await medicalHistoriesFuture;
    final Result<List<PatientConsent>> consentsResult = await consentsFuture;

    final AppFailure? failure = <AppFailure?>[
      _failureOf(workspaceResult),
      _failureOf(timelineResult),
      _failureOf(identifiersResult),
      _failureOf(contactsResult),
      _failureOf(guardiansResult),
      _failureOf(allergiesResult),
      _failureOf(medicalHistoriesResult),
      _failureOf(consentsResult),
    ].firstWhere((AppFailure? value) => value != null, orElse: () => null);
    if (failure != null) {
      return Result<PatientDetail>.failure(failure);
    }

    final List<PatientIdentifier> identifiers = _valueOrNull(
      identifiersResult,
    )!;
    final List<PatientContact> contacts = _valueOrNull(contactsResult)!;

    return Result<PatientDetail>.success(
      PatientDetail(
        patient: _hydratePatient(patient, identifiers, contacts),
        workspace: _valueOrNull(workspaceResult)!,
        identifiers: identifiers,
        contacts: contacts,
        guardians: _valueOrNull(guardiansResult)!,
        allergies: _valueOrNull(allergiesResult)!,
        medicalHistories: _valueOrNull(medicalHistoriesResult)!,
        consents: _valueOrNull(consentsResult)!,
        timeline: _valueOrNull(timelineResult)!,
      ),
    );
  }

  @override
  Future<Result<PatientMergePreview>> previewPatientMerge({
    required String primaryPatientId,
    required String secondaryPatientId,
  }) {
    return _apiClient.post<PatientMergePreview>(
      ApiEndpoints.apiV1(<String>[
        HmsApiResource.patients.path,
        'merge',
        'preview',
      ]),
      data: <String, Object?>{
        'primary_patient_id': primaryPatientId,
        'secondary_patient_id': secondaryPatientId,
      },
      decoder: (Object? data) =>
          PatientMergePreviewDto.fromResponse(data).toEntity(),
    );
  }

  @override
  Future<Result<PatientMutationResult>> mergePatients({
    required String primaryPatientId,
    required String secondaryPatientId,
    Map<String, Object?> summary = const <String, Object?>{},
  }) {
    return _apiClient.post<PatientMutationResult>(
      ApiEndpoints.apiV1(<String>[HmsApiResource.patients.path, 'merge']),
      data: _withoutEmpty(<String, Object?>{
        'primary_patient_id': primaryPatientId,
        'secondary_patient_id': secondaryPatientId,
        if (summary.isNotEmpty) 'summary': _withoutEmpty(summary),
      }),
      decoder: (_) => PatientMutationResult(patientId: primaryPatientId),
    );
  }

  @override
  Future<Result<PatientMutationResult>> dismissDuplicateCandidate({
    required String reviewId,
    required String primaryPatientId,
    required String secondaryPatientId,
    String? reason,
  }) {
    return _apiClient.post<PatientMutationResult>(
      ApiEndpoints.apiV1(<String>[
        HmsApiResource.patients.path,
        'duplicates',
        reviewId,
        'dismiss',
      ]),
      data: _withoutEmpty(<String, Object?>{
        'primary_patient_id': primaryPatientId,
        'secondary_patient_id': secondaryPatientId,
        'dismissed_reason': reason,
      }),
      decoder: (_) => PatientMutationResult(patientId: primaryPatientId),
    );
  }

  @override
  Future<Result<Patient>> createPatient(Map<String, Object?> payload) {
    return _apiClient.post<Patient>(
      ApiEndpoints.collection(HmsApiResource.patients),
      data: _withoutEmpty(payload),
      decoder: (Object? data) => PatientDto(decodeDataMap(data)).toEntity(),
    );
  }

  @override
  Future<Result<Patient>> updatePatient(
    String patientId,
    Map<String, Object?> payload,
  ) {
    return _apiClient.put<Patient>(
      ApiEndpoints.byId(HmsApiResource.patients, patientId),
      data: _withoutEmpty(payload),
      decoder: (Object? data) => PatientDto(decodeDataMap(data)).toEntity(),
    );
  }

  @override
  Future<Result<PatientMutationResult>> deletePatient(String patientId) {
    return _apiClient.delete<PatientMutationResult>(
      ApiEndpoints.byId(HmsApiResource.patients, patientId),
      decoder: (_) => PatientMutationResult(patientId: patientId),
    );
  }

  @override
  Future<Result<PatientDeletionImpact>> getDeletionImpact(String patientId) {
    return _apiClient.get<PatientDeletionImpact>(
      ApiEndpoints.nested(
        HmsApiResource.patients,
        patientId,
        const <String>['deletion-impact'],
      ),
      decoder: (Object? data) =>
          PatientDeletionImpactDto.fromResponse(data).toEntity(),
    );
  }

  @override
  Future<Result<Patient>> restorePatient(String patientId) {
    return _apiClient.post<Patient>(
      ApiEndpoints.nested(
        HmsApiResource.patients,
        patientId,
        const <String>['restore'],
      ),
      decoder: (Object? data) => PatientDto(decodeDataMap(data)).toEntity(),
    );
  }

  @override
  Future<Result<PatientMutationResult>> permanentDeletePatient(
    String patientId,
  ) {
    return _apiClient.delete<PatientMutationResult>(
      ApiEndpoints.nested(
        HmsApiResource.patients,
        patientId,
        const <String>['permanent'],
      ),
      data: const <String, Object?>{'confirm': true},
      decoder: (_) => PatientMutationResult(patientId: patientId),
    );
  }

  @override
  Future<Result<void>> createRelatedRecord(
    PatientRelatedResource resource,
    Map<String, Object?> payload,
  ) {
    return _apiClient.post<void>(
      ApiEndpoints.collection(_resourceEndpoint(resource)),
      data: _withoutEmpty(payload),
      decoder: (_) {},
    );
  }

  @override
  Future<Result<void>> updateRelatedRecord(
    PatientRelatedResource resource,
    String recordId,
    Map<String, Object?> payload,
  ) {
    return _apiClient.put<void>(
      ApiEndpoints.byId(_resourceEndpoint(resource), recordId),
      data: _withoutEmpty(payload),
      decoder: (_) {},
    );
  }

  @override
  Future<Result<void>> deleteRelatedRecord(
    PatientRelatedResource resource,
    String recordId,
  ) {
    return _apiClient.delete<void>(
      ApiEndpoints.byId(_resourceEndpoint(resource), recordId),
      decoder: (_) {},
    );
  }

  @override
  Future<Result<void>> recordPatientReportPrintEvent({
    required String patientId,
    required List<String> sections,
    String? encounterId,
    String reportType = 'patient_clinical',
    String action = 'print',
  }) {
    return _apiClient.post<void>(
      ApiEndpoints.apiV1(<String>[
        HmsApiResource.patientReports.path,
        'print-events',
      ]),
      data: <String, Object?>{
        'patient_id': patientId,
        if (encounterId != null && encounterId.isNotEmpty)
          'encounter_id': encounterId,
        'report_type': reportType,
        'action': action,
        'sections': sections,
      },
      decoder: (_) {},
    );
  }

  Future<Result<List<T>>> _fetchRelatedList<T>(
    HmsApiResource resource,
    String patientId,
    List<T> Function(Object? data) decoder,
  ) {
    return _apiClient.get<List<T>>(
      ApiEndpoints.collection(resource),
      queryParameters: <String, Object?>{
        'patient_id': patientId,
        'page': 1,
        'limit': 100,
        'sort_by': 'updated_at',
        'order': 'desc',
      },
      decoder: decoder,
    );
  }

  Patient _hydratePatient(
    Patient patient,
    List<PatientIdentifier> identifiers,
    List<PatientContact> contacts,
  ) {
    final PatientIdentifier? primaryIdentifier = identifiers
        .where((PatientIdentifier identifier) => identifier.isPrimary)
        .firstOrNull;
    final PatientIdentifier? fallbackIdentifier = identifiers.firstOrNull;
    final PatientContact? primaryPhone = contacts
        .where(
          (PatientContact contact) =>
              contact.type.toUpperCase() == 'PHONE' && contact.isPrimary,
        )
        .firstOrNull;
    final PatientContact? fallbackPhone = contacts
        .where(
          (PatientContact contact) => contact.type.toUpperCase() == 'PHONE',
        )
        .firstOrNull;
    final PatientContact? primaryEmail = contacts
        .where(
          (PatientContact contact) =>
              contact.type.toUpperCase() == 'EMAIL' && contact.isPrimary,
        )
        .firstOrNull;
    final PatientContact? fallbackEmail = contacts
        .where(
          (PatientContact contact) => contact.type.toUpperCase() == 'EMAIL',
        )
        .firstOrNull;

    return patient.copyWith(
      primaryPhone: primaryPhone?.value ?? fallbackPhone?.value,
      primaryEmail: primaryEmail?.value ?? fallbackEmail?.value,
      primaryIdentifierType:
          primaryIdentifier?.type ?? fallbackIdentifier?.type,
      primaryIdentifierValue:
          primaryIdentifier?.value ?? fallbackIdentifier?.value,
    );
  }

  HmsApiResource _resourceEndpoint(PatientRelatedResource resource) {
    return switch (resource) {
      PatientRelatedResource.identifier => HmsApiResource.patientIdentifiers,
      PatientRelatedResource.contact => HmsApiResource.patientContacts,
      PatientRelatedResource.guardian => HmsApiResource.patientGuardians,
      PatientRelatedResource.allergy => HmsApiResource.patientAllergies,
      PatientRelatedResource.medicalHistory =>
        HmsApiResource.patientMedicalHistories,
      PatientRelatedResource.consent => HmsApiResource.consents,
    };
  }

  T? _valueOrNull<T>(Result<T> result) {
    return result.when(success: (T value) => value, failure: (_) => null);
  }

  AppFailure? _failureOf<T>(Result<T> result) {
    return result.when(
      success: (_) => null,
      failure: (AppFailure failure) => failure,
    );
  }

  Map<String, Object?> _withoutEmpty(Map<String, Object?> payload) {
    return <String, Object?>{
      for (final MapEntry<String, Object?> entry in payload.entries)
        if (!_isEmpty(entry.value)) entry.key: entry.value,
    };
  }

  bool _isEmpty(Object? value) {
    if (value == null) {
      return true;
    }
    if (value is String) {
      return value.trim().isEmpty;
    }
    return false;
  }

  String? _dateOnly(DateTime? value) {
    if (value == null) {
      return null;
    }

    return value.toIso8601String().split('T').first;
  }
}
