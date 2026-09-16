import 'package:hosspi_hms/features/patients/domain/entities/patient_entities.dart';
import 'package:hosspi_hms/shared/data/data.dart';

typedef PatientJsonMap = Map<String, Object?>;

final class PatientPageDto {
  const PatientPageDto({required this.page});

  final AppPage<Patient> page;

  factory PatientPageDto.fromResponse(
    Object? responseData,
    AppPageRequest request,
  ) {
    final PatientJsonMap response = _expectMap(responseData);
    final List<Patient> items = _list(response['data'])
        .map(PatientDto.fromJson)
        .map((PatientDto dto) => dto.toEntity())
        .toList(growable: false);
    final PatientJsonMap pagination = _map(response['pagination']);
    final int total = _int(pagination['total']);

    return PatientPageDto(
      page: AppPage<Patient>(
        items: items,
        request: request,
        totalItemCount: total,
      ),
    );
  }
}

final class PatientDuplicatePageDto {
  const PatientDuplicatePageDto({required this.page});

  final AppPage<PatientDuplicateCandidate> page;

  factory PatientDuplicatePageDto.fromResponse(
    Object? responseData,
    AppPageRequest request,
  ) {
    final PatientJsonMap response = _expectMap(responseData);
    final List<PatientDuplicateCandidate> items = _list(response['data'])
        .map(PatientDuplicateCandidateDto.new)
        .map((PatientDuplicateCandidateDto dto) => dto.toEntity())
        .toList(growable: false);
    final PatientJsonMap pagination = _map(response['pagination']);

    return PatientDuplicatePageDto(
      page: AppPage<PatientDuplicateCandidate>(
        items: items,
        request: request,
        totalItemCount: _int(pagination['total']),
      ),
    );
  }
}

final class PatientDto {
  const PatientDto(this.json);

  final PatientJsonMap json;

  factory PatientDto.fromJson(PatientJsonMap json) {
    return PatientDto(json);
  }

  Patient toEntity() {
    final PatientJsonMap? tenantContext = _nullableMap(json['tenant_context']);
    final PatientJsonMap? facilityContext = _nullableMap(
      json['facility_context'],
    );
    final PatientJsonMap? facility = _nullableMap(json['facility']);
    final PatientJsonMap? primaryContact = _nullableMap(
      json['primary_contact_details'],
    );
    final PatientJsonMap? workspacePrimaryContact = _nullableMap(
      json['primary_contact'],
    );
    final String? primaryContactType =
        _string(primaryContact?['contact_type']) ??
        _string(workspacePrimaryContact?['contact_type']);
    final String? primaryContactValue =
        _string(primaryContact?['value']) ??
        _string(workspacePrimaryContact?['value']) ??
        _string(json['contact_value']);
    final bool primaryContactIsPhone =
        primaryContactType?.toUpperCase() == 'PHONE';
    final PatientJsonMap extension = _map(json['extension_json']);
    final PatientJsonMap registration = _map(extension['registration']);
    final PatientJsonMap alerts = _map(json['alerts']);
    final PatientJsonMap? currentVisit = _nullableMap(json['current_visit']);

    return Patient(
      id: _string(json['id']) ?? _string(json['human_friendly_id']) ?? '',
      publicId: _string(json['human_friendly_id']),
      displayName: _string(json['display_name']),
      tenantId: _string(json['tenant_id']),
      facilityId:
          _string(json['facility_id']) ??
          _string(facility?['human_friendly_id']) ??
          _string(facility?['id']) ??
          _string(facilityContext?['human_friendly_id']) ??
          _string(facilityContext?['id']),
      firstName: _string(json['first_name']),
      lastName: _string(json['last_name']),
      dateOfBirth: _date(json['date_of_birth']),
      gender: _string(json['gender']),
      isActive: _bool(json['is_active'], fallback: true),
      primaryPhone: _string(json['primary_phone']),
      primaryEmail: _string(json['primary_email']),
      primaryIdentifierType: _string(json['primary_identifier_type']),
      primaryIdentifierValue: _string(json['primary_identifier_value']),
      tenantLabel:
          _string(json['tenant_label']) ??
          _string(tenantContext?['label']) ??
          _string(_nullableMap(json['tenant'])?['label']),
      facilityLabel:
          _string(json['facility_label']) ??
          _string(facilityContext?['label']) ??
          _string(facility?['label']),
      requiresCompletion: _bool(registration['requires_completion']),
      registrationSource: _string(registration['source']),
      registrationStatus: _string(registration['status']),
      hasAllergyAlert: _bool(alerts['has_allergy']),
      allergyAlertLabel: _string(alerts['allergy_label']),
      currentVisit: currentVisit == null
          ? null
          : PatientVisitContextDto(currentVisit).toEntity(),
      createdAt: _date(json['created_at']),
      updatedAt: _date(json['updated_at']),
      deletedAt: _date(json['deleted_at']),
    ).copyWith(
      primaryPhone: primaryContactIsPhone ? primaryContactValue : null,
    );
  }
}

final class PatientVisitContextDto {
  const PatientVisitContextDto(this.json);

  final PatientJsonMap json;

  PatientVisitContext toEntity() {
    return PatientVisitContext(
      kind: _string(json['kind']) ?? '',
      publicId: _string(json['human_friendly_id']),
      status: _string(json['status']),
      title: _string(json['title']),
      occurredAt: _date(json['occurred_at']),
    );
  }
}

final class PatientIdentifierDto {
  const PatientIdentifierDto(this.json);

  final PatientJsonMap json;

  PatientIdentifier toEntity() {
    return PatientIdentifier(
      id: _string(json['id']) ?? '',
      publicId: _string(json['human_friendly_id']),
      tenantId: _string(json['tenant_id']) ?? '',
      patientId: _string(json['patient_id']) ?? '',
      type: _string(json['identifier_type']) ?? '',
      value: _string(json['identifier_value']) ?? '',
      isPrimary: _bool(json['is_primary']),
      updatedAt: _date(json['updated_at']),
    );
  }
}

final class PatientContactDto {
  const PatientContactDto(this.json);

  final PatientJsonMap json;

  PatientContact toEntity() {
    return PatientContact(
      id: _string(json['id']) ?? '',
      publicId: _string(json['human_friendly_id']),
      tenantId: _string(json['tenant_id']) ?? '',
      patientId: _string(json['patient_id']) ?? '',
      type: _string(json['contact_type']) ?? '',
      value: _string(json['value']) ?? '',
      isPrimary: _bool(json['is_primary']),
      updatedAt: _date(json['updated_at']),
    );
  }
}

final class PatientGuardianDto {
  const PatientGuardianDto(this.json);

  final PatientJsonMap json;

  PatientGuardian toEntity() {
    return PatientGuardian(
      id: _string(json['id']) ?? '',
      publicId: _string(json['human_friendly_id']),
      tenantId: _string(json['tenant_id']) ?? '',
      patientId: _string(json['patient_id']) ?? '',
      name: _string(json['name']) ?? '',
      relationship: _string(json['relationship']),
      phone: _string(json['phone']),
      email: _string(json['email']),
      updatedAt: _date(json['updated_at']),
    );
  }
}

final class PatientAllergyDto {
  const PatientAllergyDto(this.json);

  final PatientJsonMap json;

  PatientAllergy toEntity() {
    return PatientAllergy(
      id: _string(json['id']) ?? '',
      publicId: _string(json['human_friendly_id']),
      tenantId: _string(json['tenant_id']) ?? '',
      patientId: _string(json['patient_id']) ?? '',
      allergen: _string(json['allergen']) ?? '',
      severity: _string(json['severity']) ?? '',
      reaction: _string(json['reaction']),
      notes: _string(json['notes']),
      updatedAt: _date(json['updated_at']),
    );
  }
}

final class PatientMedicalHistoryDto {
  const PatientMedicalHistoryDto(this.json);

  final PatientJsonMap json;

  PatientMedicalHistory toEntity() {
    return PatientMedicalHistory(
      id: _string(json['id']) ?? '',
      publicId: _string(json['human_friendly_id']),
      tenantId: _string(json['tenant_id']) ?? '',
      patientId: _string(json['patient_id']) ?? '',
      condition: _string(json['condition']) ?? '',
      diagnosisDate: _date(json['diagnosis_date']),
      notes: _string(json['notes']),
      updatedAt: _date(json['updated_at']),
    );
  }
}

final class PatientDocumentDto {
  const PatientDocumentDto(this.json);

  final PatientJsonMap json;

  PatientDocument toEntity() {
    return PatientDocument(
      id: _string(json['id']) ?? '',
      publicId: _string(json['human_friendly_id']),
      tenantId: _string(json['tenant_id']) ?? '',
      patientId: _string(json['patient_id']) ?? '',
      documentType: _string(json['document_type']) ?? '',
      storageKey: _string(json['storage_key']) ?? '',
      fileName: _string(json['file_name']),
      contentType: _string(json['content_type']),
      updatedAt: _date(json['updated_at']),
    );
  }
}

final class PatientConsentDto {
  const PatientConsentDto(this.json);

  final PatientJsonMap json;

  PatientConsent toEntity() {
    return PatientConsent(
      id: _string(json['id']) ?? '',
      publicId: _string(json['human_friendly_id']),
      tenantId: _string(json['tenant_id']) ?? '',
      patientId: _string(json['patient_id']) ?? '',
      consentType: _string(json['consent_type']) ?? '',
      status: _string(json['status']) ?? '',
      grantedAt: _date(json['granted_at']),
      revokedAt: _date(json['revoked_at']),
      updatedAt: _date(json['updated_at']),
    );
  }
}

final class PatientWorkspaceDto {
  const PatientWorkspaceDto(this.json);

  final PatientJsonMap json;

  PatientWorkspaceSnapshot toSnapshot() {
    final PatientJsonMap snapshot = _map(json['snapshot']);

    return PatientWorkspaceSnapshot(
      appointments: _summaryRecords(snapshot['appointments'], 'appointment'),
      queueEntries: _summaryRecords(snapshot['queue_entries'], 'queue'),
      encounters: _summaryRecords(snapshot['encounters'], 'encounter'),
      admissions: _summaryRecords(snapshot['admissions'], 'admission'),
      invoices: _summaryRecords(snapshot['invoices'], 'invoice'),
      payments: _summaryRecords(snapshot['payments'], 'payment'),
      pharmacyOrders: _summaryRecords(
        snapshot['pharmacy_orders'],
        'pharmacy_order',
      ),
      duplicateCandidates: _list(snapshot['duplicate_candidates'])
          .map(PatientDuplicateCandidateDto.new)
          .map((PatientDuplicateCandidateDto dto) => dto.toEntity())
          .toList(growable: false),
      summaryCounts: _intMap(snapshot['summary_counts']),
    );
  }

  List<PatientTimelineItem> toTimeline() {
    return _list(json['timeline'])
        .map(PatientTimelineItemDto.new)
        .map((PatientTimelineItemDto dto) => dto.toEntity())
        .toList(growable: false);
  }
}

final class PatientTimelineItemDto {
  const PatientTimelineItemDto(this.json);

  final PatientJsonMap json;

  PatientTimelineItem toEntity() {
    final PatientJsonMap? summary = _nullableMap(json['summary']);
    final String? status =
        _string(summary?['status']) ??
        _string(summary?['billing_status']) ??
        _string(summary?['encounter_type']);
    final String? title =
        _string(summary?['display_name']) ??
        _string(summary?['document_type']) ??
        _string(summary?['consent_type']) ??
        _string(summary?['reason']) ??
        status;

    return PatientTimelineItem(
      id: _string(json['id']) ?? '',
      resource: _string(json['resource']) ?? '',
      occurredAt: _date(json['occurred_at']),
      title: title,
      subtitle: status,
    );
  }
}

final class PatientDuplicateCandidateDto {
  const PatientDuplicateCandidateDto(this.json);

  final PatientJsonMap json;

  PatientDuplicateCandidate toEntity() {
    return PatientDuplicateCandidate(
      reviewId: _string(json['review_id']) ?? '',
      confidenceScore: _int(json['confidence_score']),
      classification: _string(json['classification']) ?? '',
      matchReasons: _duplicateReasonList(json['match_reasons']),
      fieldComparisons: _list(json['field_comparisons'])
          .map(
            (PatientJsonMap value) => PatientDuplicateFieldComparison(
              field: _string(value['field']) ?? '',
              inputValue: _string(value['input_value']) ?? '',
              candidateValue: _string(value['candidate_value']) ?? '',
              status: _string(value['status']) ?? '',
              contribution: _int(value['contribution']),
              similarityPercent: value['similarity_percent'] == null
                  ? null
                  : _int(value['similarity_percent']),
            ),
          )
          .toList(growable: false),
      scoreVersion: _string(json['score_version']),
      primaryPatient: _patientOrNull(json['primary_patient']),
      secondaryPatient: _patientOrNull(json['secondary_patient']),
      candidatePatient: _patientOrNull(json['candidate_patient']),
    );
  }
}

final class PatientMergePreviewDto {
  const PatientMergePreviewDto(this.json);

  final PatientJsonMap json;

  factory PatientMergePreviewDto.fromResponse(Object? responseData) {
    return PatientMergePreviewDto(decodeDataMap(responseData));
  }

  PatientMergePreview toEntity() {
    return PatientMergePreview(
      primaryPatient:
          _patientOrNull(json['primary_patient']) ?? const Patient(id: ''),
      secondaryPatient:
          _patientOrNull(json['secondary_patient']) ?? const Patient(id: ''),
      confidenceScore: _int(json['confidence_score']),
      classification: _string(json['classification']) ?? '',
      matchReasons: _stringList(json['match_reasons']),
      transferCounts: _intMap(json['transfer_counts']),
    );
  }
}

final class PatientDeletionImpactDto {
  const PatientDeletionImpactDto(this.json);

  final PatientJsonMap json;

  factory PatientDeletionImpactDto.fromResponse(Object? responseData) {
    return PatientDeletionImpactDto(decodeDataMap(responseData));
  }

  PatientDeletionImpact toEntity() {
    final PatientJsonMap counts = _map(json['counts']);
    return PatientDeletionImpact(
      patientId:
          _string(json['patient_id']) ??
          _string(json['human_friendly_id']) ??
          '',
      humanFriendlyId: _string(json['human_friendly_id']),
      blockers: _list(json['blockers'])
          .map(
            (PatientJsonMap entry) => PatientDeletionBlocker(
              code: _string(entry['code']) ?? '',
              model: _string(entry['model']),
              count: _int(entry['count']),
            ),
          )
          .where((PatientDeletionBlocker blocker) => blocker.code.isNotEmpty)
          .toList(growable: false),
      countsByCategory: _intMap(counts['by_category']),
      countsByModel: _intMap(counts['by_model']),
    );
  }
}

final class PatientRegistryOverviewDto {
  const PatientRegistryOverviewDto(this.json);

  final PatientJsonMap json;

  factory PatientRegistryOverviewDto.fromResponse(Object? responseData) {
    final PatientJsonMap response = _expectMap(responseData);
    return PatientRegistryOverviewDto(_map(response['data']));
  }

  PatientRegistryOverview toEntity() {
    final PatientJsonMap metrics = _map(json['metrics']);

    return PatientRegistryOverview(
      totalPatients: _int(metrics['total_patients']),
      activePatients: _int(metrics['active_patients']),
      waitingQueue: _int(metrics['waiting_queue']),
      activeAdmissions: _int(metrics['active_admissions']),
      unpaidInvoices: _int(metrics['unpaid_invoices']),
      dueFollowUps: _int(metrics['due_follow_ups']),
      duplicates: _list(json['duplicate_queue'])
          .map(PatientDuplicateCandidateDto.new)
          .map((PatientDuplicateCandidateDto dto) => dto.toEntity())
          .toList(growable: false),
      recentPatients: _list(json['recent_patients'])
          .map(PatientDto.new)
          .map((PatientDto dto) => dto.toEntity())
          .toList(growable: false),
      waitingQueuePatients: _list(json['waiting_queue'])
          .map((PatientJsonMap entry) => _map(entry['patient']))
          .map(PatientDto.new)
          .map((PatientDto dto) => dto.toEntity())
          .where((Patient patient) => patient.id.isNotEmpty)
          .toList(growable: false),
      consentExceptions: _list(json['consent_exceptions']).length,
      missingDocuments: _list(json['missing_documents']).length,
    );
  }
}

final class PatientReferenceDataDto {
  const PatientReferenceDataDto(this.json);

  final PatientJsonMap json;

  factory PatientReferenceDataDto.fromResponse(Object? responseData) {
    final PatientJsonMap response = _expectMap(responseData);
    return PatientReferenceDataDto(_map(response['data']));
  }

  PatientReferenceData toEntity() {
    return PatientReferenceData(
      tenants: _list(json['tenants'])
          .map(_referenceOption)
          .where((PatientReferenceOption option) => option.id.isNotEmpty)
          .toList(growable: false),
      facilities: _list(json['facilities'])
          .map(_referenceOption)
          .where((PatientReferenceOption option) => option.id.isNotEmpty)
          .toList(growable: false),
      wards: _list(json['wards'])
          .map(_referenceOption)
          .where((PatientReferenceOption option) => option.id.isNotEmpty)
          .toList(growable: false),
      rooms: _list(json['rooms'])
          .map(_referenceOption)
          .where((PatientReferenceOption option) => option.id.isNotEmpty)
          .toList(growable: false),
      beds: _list(json['beds'])
          .map(_referenceOption)
          .where((PatientReferenceOption option) => option.id.isNotEmpty)
          .toList(growable: false),
      documentTypes: _optionValues(json['document_types']),
      consentTypes: _optionValues(json['consent_types']),
      consentStatuses: _optionValues(json['consent_statuses']),
      appointmentStatuses: _optionValues(json['appointment_statuses']),
    );
  }
}

PatientReferenceOption _referenceOption(PatientJsonMap entry) {
  return PatientReferenceOption(
    id: _string(entry['human_friendly_id']) ?? _string(entry['id']) ?? '',
    label: _string(entry['label']) ?? '',
    tenantId: _string(entry['tenant_id']),
    facilityId: _string(entry['facility_id']),
    wardId: _string(entry['ward_id']),
    roomId: _string(entry['room_id']),
    status: _string(entry['status']),
    type: _string(entry['type']) ?? _string(entry['ward_type']),
  );
}

PatientJsonMap decodeDataMap(Object? responseData) {
  final PatientJsonMap response = _expectMap(responseData);
  return _map(response['data']);
}

List<PatientJsonMap> decodeDataList(Object? responseData) {
  final PatientJsonMap response = _expectMap(responseData);
  return _list(response['data']);
}

List<PatientIdentifier> decodeIdentifierList(Object? responseData) {
  return decodeDataList(responseData)
      .map(PatientIdentifierDto.new)
      .map((PatientIdentifierDto dto) => dto.toEntity())
      .where((PatientIdentifier value) => value.id.isNotEmpty)
      .toList(growable: false);
}

List<PatientContact> decodeContactList(Object? responseData) {
  return decodeDataList(responseData)
      .map(PatientContactDto.new)
      .map((PatientContactDto dto) => dto.toEntity())
      .where((PatientContact value) => value.id.isNotEmpty)
      .toList(growable: false);
}

List<PatientGuardian> decodeGuardianList(Object? responseData) {
  return decodeDataList(responseData)
      .map(PatientGuardianDto.new)
      .map((PatientGuardianDto dto) => dto.toEntity())
      .where((PatientGuardian value) => value.id.isNotEmpty)
      .toList(growable: false);
}

List<PatientAllergy> decodeAllergyList(Object? responseData) {
  return decodeDataList(responseData)
      .map(PatientAllergyDto.new)
      .map((PatientAllergyDto dto) => dto.toEntity())
      .where((PatientAllergy value) => value.id.isNotEmpty)
      .toList(growable: false);
}

List<PatientMedicalHistory> decodeMedicalHistoryList(Object? responseData) {
  return decodeDataList(responseData)
      .map(PatientMedicalHistoryDto.new)
      .map((PatientMedicalHistoryDto dto) => dto.toEntity())
      .where((PatientMedicalHistory value) => value.id.isNotEmpty)
      .toList(growable: false);
}

List<PatientDocument> decodeDocumentList(Object? responseData) {
  return decodeDataList(responseData)
      .map(PatientDocumentDto.new)
      .map((PatientDocumentDto dto) => dto.toEntity())
      .where((PatientDocument value) => value.id.isNotEmpty)
      .toList(growable: false);
}

List<PatientDocument> decodeDocumentUploadList(Object? responseData) {
  final PatientJsonMap data = decodeDataMap(responseData);
  return _list(data['items'])
      .map(PatientDocumentDto.new)
      .map((PatientDocumentDto dto) => dto.toEntity())
      .where((PatientDocument value) => value.id.isNotEmpty)
      .toList(growable: false);
}

List<PatientConsent> decodeConsentList(Object? responseData) {
  return decodeDataList(responseData)
      .map(PatientConsentDto.new)
      .map((PatientConsentDto dto) => dto.toEntity())
      .where((PatientConsent value) => value.id.isNotEmpty)
      .toList(growable: false);
}

List<PatientSummaryRecord> _summaryRecords(Object? value, String kind) {
  return _list(value)
      .map((PatientJsonMap entry) => _summaryRecord(entry, kind))
      .toList(growable: false);
}

PatientSummaryRecord _summaryRecord(PatientJsonMap json, String kind) {
  final String id =
      _string(json['human_friendly_id']) ?? _string(json['id']) ?? '';
  final String? status =
      _string(json['status']) ??
      _string(json['billing_status']) ??
      _string(json['encounter_type']);
  final String? title =
      _string(json['reason']) ??
      _string(json['provider_name']) ??
      _string(json['transaction_ref']) ??
      _string(json['document_type']) ??
      _string(json['human_friendly_id']) ??
      _string(json['priority']) ??
      status;
  final DateTime? occurredAt =
      _date(json['scheduled_start']) ??
      _date(json['queued_at']) ??
      _date(json['admitted_at']) ??
      _date(json['issued_at']) ??
      _date(json['paid_at']) ??
      _date(json['ordered_at']) ??
      _date(json['dispensed_at']) ??
      _date(json['created_at']) ??
      _date(json['updated_at']);

  return PatientSummaryRecord(
    id: id,
    kind: kind,
    status: status,
    title: title,
    subtitle: _string(json['provider_name']) ?? _string(json['invoice_id']),
    amount: _number(json['total_amount']) ?? _number(json['amount']),
    currency: _string(json['currency']),
    occurredAt: occurredAt,
  );
}

Patient? _patientOrNull(Object? value) {
  final PatientJsonMap? json = _nullableMap(value);
  if (json == null) {
    return null;
  }

  final Patient patient = PatientDto(json).toEntity();
  return patient.id.isEmpty ? null : patient;
}

List<String> _optionValues(Object? value) {
  return _list(value)
      .map(
        (PatientJsonMap json) => _string(json['value']) ?? _string(json['id']),
      )
      .whereType<String>()
      .where((String value) => value.isNotEmpty)
      .toList(growable: false);
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }

  return value
      .map(_string)
      .whereType<String>()
      .where((String entry) => entry.isNotEmpty)
      .toList(growable: false);
}

List<String> _duplicateReasonList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .map((Object? entry) {
        if (entry is PatientJsonMap) {
          return _string(entry['code']);
        }
        return _string(entry);
      })
      .whereType<String>()
      .where((String entry) => entry.isNotEmpty)
      .toList(growable: false);
}

PatientJsonMap _expectMap(Object? value) {
  if (value is PatientJsonMap) {
    return value;
  }

  throw const FormatException('Expected response object.');
}

PatientJsonMap _map(Object? value) {
  return value is PatientJsonMap ? value : <String, Object?>{};
}

PatientJsonMap? _nullableMap(Object? value) {
  return value is PatientJsonMap ? value : null;
}

List<PatientJsonMap> _list(Object? value) {
  if (value is! List) {
    return const <PatientJsonMap>[];
  }

  return value.whereType<PatientJsonMap>().toList(growable: false);
}

Map<String, int> _intMap(Object? value) {
  final PatientJsonMap map = _map(value);
  return <String, int>{
    for (final MapEntry<String, Object?> entry in map.entries)
      entry.key: _int(entry.value),
  };
}

String? _string(Object? value) {
  if (value == null) {
    return null;
  }

  final String normalized = value.toString().trim();
  return normalized.isEmpty ? null : normalized;
}

DateTime? _date(Object? value) {
  final String? normalized = _string(value);
  if (normalized == null) {
    return null;
  }

  return DateTime.tryParse(normalized);
}

bool _bool(Object? value, {bool fallback = false}) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    return value.toLowerCase() == 'true';
  }
  return fallback;
}

int _int(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

num? _number(Object? value) {
  if (value is num) {
    return value;
  }
  if (value is String) {
    return num.tryParse(value);
  }
  return null;
}
