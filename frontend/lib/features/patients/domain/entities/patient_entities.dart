import 'package:flutter/foundation.dart';
import 'package:hosspi_hms/shared/data/data.dart';

enum PatientRegistrySection { all, active, admitted, balanceDue }

/// Record-state filter for patient list (`record_state` query param).
enum PatientRecordState { current, deleted, all }

extension PatientRecordStateQuery on PatientRecordState {
  String get queryValue => name;

  bool get includeDeleted =>
      this == PatientRecordState.deleted || this == PatientRecordState.all;
}

extension PatientRegistrySectionFilter on PatientRegistrySection {
  PatientListQuery applyToQuery(PatientListQuery query) {
    switch (this) {
      case PatientRegistrySection.all:
        return query.copyWith(
          clearIsActive: true,
          clearHasActiveAdmission: true,
          clearHasOutstandingBalance: true,
        );
      case PatientRegistrySection.active:
        return query.copyWith(
          isActive: true,
          clearHasActiveAdmission: true,
          clearHasOutstandingBalance: true,
        );
      case PatientRegistrySection.admitted:
        return query.copyWith(
          hasActiveAdmission: true,
          clearIsActive: true,
          clearHasOutstandingBalance: true,
        );
      case PatientRegistrySection.balanceDue:
        return query.copyWith(
          hasOutstandingBalance: true,
          clearIsActive: true,
          clearHasActiveAdmission: true,
        );
    }
  }

  String get queryValue {
    switch (this) {
      case PatientRegistrySection.all:
        return '';
      case PatientRegistrySection.active:
        return 'active';
      case PatientRegistrySection.admitted:
        return 'admitted';
      case PatientRegistrySection.balanceDue:
        return 'balance-due';
    }
  }
}

@immutable
final class PatientListQuery {
  const PatientListQuery({
    this.section = PatientRegistrySection.all,
    this.search = '',
    this.patientId = '',
    this.contact = '',
    this.facilityId,
    this.gender,
    this.isActive,
    this.consentState,
    this.appointmentStatus,
    this.visitDate,
    this.visitFrom,
    this.visitTo,
    this.createdFrom,
    this.createdTo,
    this.dateOfBirthFrom,
    this.dateOfBirthTo,
    this.hasActiveAdmission,
    this.hasOutstandingBalance,
    this.recordState = PatientRecordState.current,
    this.includeDeleted,
    this.pageRequest = const AppPageRequest(),
  });

  factory PatientListQuery.fromUri(Uri uri) {
    final Map<String, String> params = uri.queryParameters;
    String pick(List<String> keys) {
      for (final String key in keys) {
        final String value = (params[key] ?? '').trim();
        if (value.isNotEmpty) {
          return value;
        }
      }
      return '';
    }

    bool? parseBool(String raw) {
      final String normalized = raw.trim().toLowerCase();
      if (normalized.isEmpty) {
        return null;
      }
      if (<String>{'1', 'true', 'yes', 'y'}.contains(normalized)) {
        return true;
      }
      if (<String>{'0', 'false', 'no', 'n'}.contains(normalized)) {
        return false;
      }
      return null;
    }

    PatientRegistrySection parseSection(String raw) {
      switch (raw.trim().toLowerCase()) {
        case 'active':
          return PatientRegistrySection.active;
        case 'admitted':
          return PatientRegistrySection.admitted;
        case 'balance-due':
        case 'balance_due':
        case 'balancedue':
          return PatientRegistrySection.balanceDue;
        default:
          return PatientRegistrySection.all;
      }
    }

    PatientRecordState parseRecordState(String raw) {
      switch (raw.trim().toLowerCase()) {
        case 'deleted':
          return PatientRecordState.deleted;
        case 'all':
          return PatientRecordState.all;
        default:
          return PatientRecordState.current;
      }
    }

    final bool? includeDeleted = parseBool(
      pick(<String>['include_deleted', 'includeDeleted']),
    );
    final String recordStateRaw = pick(<String>['record_state', 'recordState']);
    final PatientRecordState recordState = recordStateRaw.isNotEmpty
        ? parseRecordState(recordStateRaw)
        : (includeDeleted == true
              ? PatientRecordState.all
              : PatientRecordState.current);

    return PatientListQuery(
      section: parseSection(pick(<String>['section', 'tab'])),
      search: pick(<String>['search', 'q']),
      patientId: pick(<String>['patientId', 'patient_id', 'patient']),
      contact: pick(<String>['contact', 'phone']),
      hasOutstandingBalance: parseBool(
        pick(<String>[
          'has_outstanding_balance',
          'hasOutstandingBalance',
          'outstanding',
        ]),
      ),
      hasActiveAdmission: parseBool(
        pick(<String>['has_active_admission', 'hasActiveAdmission']),
      ),
      recordState: recordState,
      includeDeleted: includeDeleted,
    );
  }

  final PatientRegistrySection section;
  final String search;
  final String patientId;
  final String contact;
  final String? facilityId;
  final String? gender;
  final bool? isActive;
  final String? consentState;
  final String? appointmentStatus;
  final DateTime? visitDate;
  final DateTime? visitFrom;
  final DateTime? visitTo;
  final DateTime? createdFrom;
  final DateTime? createdTo;
  final DateTime? dateOfBirthFrom;
  final DateTime? dateOfBirthTo;
  final bool? hasActiveAdmission;
  final bool? hasOutstandingBalance;
  final PatientRecordState recordState;
  /// When set, overrides [recordState.includeDeleted] for the list request.
  final bool? includeDeleted;
  final AppPageRequest pageRequest;

  bool get effectiveIncludeDeleted =>
      includeDeleted ?? recordState.includeDeleted;

  bool get hasRouteTargeting {
    return section != PatientRegistrySection.all ||
        search.trim().isNotEmpty ||
        patientId.trim().isNotEmpty ||
        contact.trim().isNotEmpty ||
        hasOutstandingBalance != null ||
        hasActiveAdmission != null ||
        recordState != PatientRecordState.current;
  }

  String get signature =>
      '${section.name}|$search|$patientId|$contact|$hasOutstandingBalance|$hasActiveAdmission|${recordState.name}|$includeDeleted';

  PatientListQuery copyWith({
    PatientRegistrySection? section,
    String? search,
    String? patientId,
    String? contact,
    String? facilityId,
    String? gender,
    bool? isActive,
    String? consentState,
    String? appointmentStatus,
    DateTime? visitDate,
    DateTime? visitFrom,
    DateTime? visitTo,
    DateTime? createdFrom,
    DateTime? createdTo,
    DateTime? dateOfBirthFrom,
    DateTime? dateOfBirthTo,
    bool? hasActiveAdmission,
    bool? hasOutstandingBalance,
    PatientRecordState? recordState,
    bool? includeDeleted,
    AppPageRequest? pageRequest,
    bool clearFacilityId = false,
    bool clearGender = false,
    bool clearIsActive = false,
    bool clearConsentState = false,
    bool clearAppointmentStatus = false,
    bool clearVisitDate = false,
    bool clearVisitFrom = false,
    bool clearVisitTo = false,
    bool clearCreatedFrom = false,
    bool clearCreatedTo = false,
    bool clearDateOfBirthFrom = false,
    bool clearDateOfBirthTo = false,
    bool clearHasActiveAdmission = false,
    bool clearHasOutstandingBalance = false,
    bool clearIncludeDeleted = false,
  }) {
    return PatientListQuery(
      section: section ?? this.section,
      search: search ?? this.search,
      patientId: patientId ?? this.patientId,
      contact: contact ?? this.contact,
      facilityId: clearFacilityId ? null : facilityId ?? this.facilityId,
      gender: clearGender ? null : gender ?? this.gender,
      isActive: clearIsActive ? null : isActive ?? this.isActive,
      consentState: clearConsentState
          ? null
          : consentState ?? this.consentState,
      appointmentStatus: clearAppointmentStatus
          ? null
          : appointmentStatus ?? this.appointmentStatus,
      visitDate: clearVisitDate ? null : visitDate ?? this.visitDate,
      visitFrom: clearVisitFrom ? null : visitFrom ?? this.visitFrom,
      visitTo: clearVisitTo ? null : visitTo ?? this.visitTo,
      createdFrom: clearCreatedFrom ? null : createdFrom ?? this.createdFrom,
      createdTo: clearCreatedTo ? null : createdTo ?? this.createdTo,
      dateOfBirthFrom: clearDateOfBirthFrom
          ? null
          : dateOfBirthFrom ?? this.dateOfBirthFrom,
      dateOfBirthTo: clearDateOfBirthTo
          ? null
          : dateOfBirthTo ?? this.dateOfBirthTo,
      hasActiveAdmission: clearHasActiveAdmission
          ? null
          : hasActiveAdmission ?? this.hasActiveAdmission,
      hasOutstandingBalance: clearHasOutstandingBalance
          ? null
          : hasOutstandingBalance ?? this.hasOutstandingBalance,
      recordState: recordState ?? this.recordState,
      includeDeleted: clearIncludeDeleted
          ? null
          : includeDeleted ?? this.includeDeleted,
      pageRequest: pageRequest ?? this.pageRequest,
    );
  }
}

@immutable
final class PatientDuplicateQuery {
  const PatientDuplicateQuery({
    this.patientId = '',
    this.tenantId = '',
    this.facilityId = '',
    this.firstName = '',
    this.lastName = '',
    this.dateOfBirth,
    this.gender = '',
    this.phone = '',
    this.email = '',
    this.identifierType = '',
    this.identifierValue = '',
    this.pageRequest = const AppPageRequest(pageSize: 8),
  });

  final String patientId;
  final String tenantId;
  final String facilityId;
  final String firstName;
  final String lastName;
  final DateTime? dateOfBirth;
  final String gender;
  final String phone;
  final String email;
  final String identifierType;
  final String identifierValue;
  final AppPageRequest pageRequest;

  PatientDuplicateQuery copyWith({
    String? patientId,
    String? tenantId,
    String? facilityId,
    String? firstName,
    String? lastName,
    DateTime? dateOfBirth,
    String? gender,
    String? phone,
    String? email,
    String? identifierType,
    String? identifierValue,
    AppPageRequest? pageRequest,
    bool clearDateOfBirth = false,
  }) {
    return PatientDuplicateQuery(
      patientId: patientId ?? this.patientId,
      tenantId: tenantId ?? this.tenantId,
      facilityId: facilityId ?? this.facilityId,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      dateOfBirth: clearDateOfBirth ? null : dateOfBirth ?? this.dateOfBirth,
      gender: gender ?? this.gender,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      identifierType: identifierType ?? this.identifierType,
      identifierValue: identifierValue ?? this.identifierValue,
      pageRequest: pageRequest ?? this.pageRequest,
    );
  }
}

@immutable
final class Patient {
  const Patient({
    required this.id,
    this.publicId,
    this.displayName,
    this.tenantId,
    this.facilityId,
    this.firstName,
    this.lastName,
    this.dateOfBirth,
    this.gender,
    this.isActive = true,
    this.primaryPhone,
    this.primaryEmail,
    this.primaryIdentifierType,
    this.primaryIdentifierValue,
    this.tenantLabel,
    this.facilityLabel,
    this.requiresCompletion = false,
    this.registrationSource,
    this.registrationStatus,
    this.hasAllergyAlert = false,
    this.allergyAlertLabel,
    this.currentVisit,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String? publicId;
  final String? displayName;
  final String? tenantId;
  final String? facilityId;
  final String? firstName;
  final String? lastName;
  final DateTime? dateOfBirth;
  final String? gender;
  final bool isActive;
  final String? primaryPhone;
  final String? primaryEmail;
  final String? primaryIdentifierType;
  final String? primaryIdentifierValue;
  final String? tenantLabel;
  final String? facilityLabel;
  final bool requiresCompletion;
  final String? registrationSource;
  final String? registrationStatus;
  final bool hasAllergyAlert;
  final String? allergyAlertLabel;
  final PatientVisitContext? currentVisit;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  String get effectiveDisplayName {
    final String first = firstName?.trim() ?? '';
    final String last = lastName?.trim() ?? '';
    final String joined = <String>[
      first,
      last,
    ].where((String value) => value.isNotEmpty).join(' ');
    return _firstNonEmpty(<String?>[displayName, joined, publicId]) ?? '';
  }

  String? get effectiveIdentifier {
    final String? value = primaryIdentifierValue?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
    return _firstNonEmpty(<String?>[publicId]);
  }

  Patient copyWith({
    String? id,
    String? publicId,
    String? displayName,
    String? tenantId,
    String? facilityId,
    String? firstName,
    String? lastName,
    DateTime? dateOfBirth,
    String? gender,
    bool? isActive,
    String? primaryPhone,
    String? primaryEmail,
    String? primaryIdentifierType,
    String? primaryIdentifierValue,
    String? tenantLabel,
    String? facilityLabel,
    bool? requiresCompletion,
    String? registrationSource,
    String? registrationStatus,
    bool? hasAllergyAlert,
    String? allergyAlertLabel,
    PatientVisitContext? currentVisit,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDateOfBirth = false,
    bool clearGender = false,
    bool clearFacilityId = false,
    bool clearPrimaryPhone = false,
    bool clearPrimaryEmail = false,
    bool clearPrimaryIdentifierType = false,
    bool clearPrimaryIdentifierValue = false,
    bool clearAllergyAlertLabel = false,
    bool clearCurrentVisit = false,
    bool clearDeletedAt = false,
  }) {
    return Patient(
      id: id ?? this.id,
      publicId: publicId ?? this.publicId,
      displayName: displayName ?? this.displayName,
      tenantId: tenantId ?? this.tenantId,
      facilityId: clearFacilityId ? null : facilityId ?? this.facilityId,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      dateOfBirth: clearDateOfBirth ? null : dateOfBirth ?? this.dateOfBirth,
      gender: clearGender ? null : gender ?? this.gender,
      isActive: isActive ?? this.isActive,
      primaryPhone: clearPrimaryPhone
          ? null
          : primaryPhone ?? this.primaryPhone,
      primaryEmail: clearPrimaryEmail
          ? null
          : primaryEmail ?? this.primaryEmail,
      primaryIdentifierType: clearPrimaryIdentifierType
          ? null
          : primaryIdentifierType ?? this.primaryIdentifierType,
      primaryIdentifierValue: clearPrimaryIdentifierValue
          ? null
          : primaryIdentifierValue ?? this.primaryIdentifierValue,
      tenantLabel: tenantLabel ?? this.tenantLabel,
      facilityLabel: facilityLabel ?? this.facilityLabel,
      requiresCompletion: requiresCompletion ?? this.requiresCompletion,
      registrationSource: registrationSource ?? this.registrationSource,
      registrationStatus: registrationStatus ?? this.registrationStatus,
      hasAllergyAlert: hasAllergyAlert ?? this.hasAllergyAlert,
      allergyAlertLabel: clearAllergyAlertLabel
          ? null
          : allergyAlertLabel ?? this.allergyAlertLabel,
      currentVisit: clearCurrentVisit
          ? null
          : currentVisit ?? this.currentVisit,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    );
  }
}

@immutable
final class PatientVisitContext {
  const PatientVisitContext({
    required this.kind,
    this.publicId,
    this.status,
    this.title,
    this.occurredAt,
  });

  final String kind;
  final String? publicId;
  final String? status;
  final String? title;
  final DateTime? occurredAt;
}

@immutable
final class PatientIdentifier {
  const PatientIdentifier({
    required this.id,
    required this.tenantId,
    required this.patientId,
    required this.type,
    required this.value,
    this.publicId,
    this.isPrimary = false,
    this.updatedAt,
  });

  final String id;
  final String? publicId;
  final String tenantId;
  final String patientId;
  final String type;
  final String value;
  final bool isPrimary;
  final DateTime? updatedAt;
}

@immutable
final class PatientContact {
  const PatientContact({
    required this.id,
    required this.tenantId,
    required this.patientId,
    required this.type,
    required this.value,
    this.publicId,
    this.isPrimary = false,
    this.updatedAt,
  });

  final String id;
  final String? publicId;
  final String tenantId;
  final String patientId;
  final String type;
  final String value;
  final bool isPrimary;
  final DateTime? updatedAt;
}

@immutable
final class PatientGuardian {
  const PatientGuardian({
    required this.id,
    required this.tenantId,
    required this.patientId,
    required this.name,
    this.publicId,
    this.relationship,
    this.phone,
    this.email,
    this.updatedAt,
  });

  final String id;
  final String? publicId;
  final String tenantId;
  final String patientId;
  final String name;
  final String? relationship;
  final String? phone;
  final String? email;
  final DateTime? updatedAt;
}

@immutable
final class PatientAllergy {
  const PatientAllergy({
    required this.id,
    required this.tenantId,
    required this.patientId,
    required this.allergen,
    required this.severity,
    this.publicId,
    this.reaction,
    this.notes,
    this.updatedAt,
  });

  final String id;
  final String? publicId;
  final String tenantId;
  final String patientId;
  final String allergen;
  final String severity;
  final String? reaction;
  final String? notes;
  final DateTime? updatedAt;
}

@immutable
final class PatientMedicalHistory {
  const PatientMedicalHistory({
    required this.id,
    required this.tenantId,
    required this.patientId,
    required this.condition,
    this.publicId,
    this.diagnosisDate,
    this.notes,
    this.updatedAt,
  });

  final String id;
  final String? publicId;
  final String tenantId;
  final String patientId;
  final String condition;
  final DateTime? diagnosisDate;
  final String? notes;
  final DateTime? updatedAt;
}

@immutable
final class PatientDocument {
  const PatientDocument({
    required this.id,
    required this.tenantId,
    required this.patientId,
    required this.documentType,
    required this.storageKey,
    this.publicId,
    this.fileName,
    this.contentType,
    this.updatedAt,
  });

  final String id;
  final String? publicId;
  final String tenantId;
  final String patientId;
  final String documentType;
  final String storageKey;
  final String? fileName;
  final String? contentType;
  final DateTime? updatedAt;
}

@immutable
final class PatientDocumentUploadFile {
  const PatientDocumentUploadFile({
    required this.name,
    required this.bytes,
    this.contentType,
  });

  final String name;
  final Uint8List bytes;
  final String? contentType;
}

@immutable
final class PatientConsent {
  const PatientConsent({
    required this.id,
    required this.tenantId,
    required this.patientId,
    required this.consentType,
    required this.status,
    this.publicId,
    this.grantedAt,
    this.revokedAt,
    this.updatedAt,
  });

  final String id;
  final String? publicId;
  final String tenantId;
  final String patientId;
  final String consentType;
  final String status;
  final DateTime? grantedAt;
  final DateTime? revokedAt;
  final DateTime? updatedAt;
}

@immutable
final class PatientTimelineItem {
  const PatientTimelineItem({
    required this.id,
    required this.resource,
    this.occurredAt,
    this.title,
    this.subtitle,
  });

  final String id;
  final String resource;
  final DateTime? occurredAt;
  final String? title;
  final String? subtitle;
}

@immutable
final class PatientWorkspaceSnapshot {
  const PatientWorkspaceSnapshot({
    this.appointments = const <PatientSummaryRecord>[],
    this.queueEntries = const <PatientSummaryRecord>[],
    this.encounters = const <PatientSummaryRecord>[],
    this.admissions = const <PatientSummaryRecord>[],
    this.invoices = const <PatientSummaryRecord>[],
    this.payments = const <PatientSummaryRecord>[],
    this.pharmacyOrders = const <PatientSummaryRecord>[],
    this.duplicateCandidates = const <PatientDuplicateCandidate>[],
    this.summaryCounts = const <String, int>{},
  });

  final List<PatientSummaryRecord> appointments;
  final List<PatientSummaryRecord> queueEntries;
  final List<PatientSummaryRecord> encounters;
  final List<PatientSummaryRecord> admissions;
  final List<PatientSummaryRecord> invoices;
  final List<PatientSummaryRecord> payments;
  final List<PatientSummaryRecord> pharmacyOrders;
  final List<PatientDuplicateCandidate> duplicateCandidates;
  final Map<String, int> summaryCounts;

  PatientWorkspaceSnapshot copyWith({
    List<PatientSummaryRecord>? appointments,
    List<PatientSummaryRecord>? queueEntries,
    List<PatientSummaryRecord>? encounters,
    List<PatientSummaryRecord>? admissions,
    List<PatientSummaryRecord>? invoices,
    List<PatientSummaryRecord>? payments,
    List<PatientSummaryRecord>? pharmacyOrders,
    List<PatientDuplicateCandidate>? duplicateCandidates,
    Map<String, int>? summaryCounts,
  }) {
    return PatientWorkspaceSnapshot(
      appointments: appointments ?? this.appointments,
      queueEntries: queueEntries ?? this.queueEntries,
      encounters: encounters ?? this.encounters,
      admissions: admissions ?? this.admissions,
      invoices: invoices ?? this.invoices,
      payments: payments ?? this.payments,
      pharmacyOrders: pharmacyOrders ?? this.pharmacyOrders,
      duplicateCandidates: duplicateCandidates ?? this.duplicateCandidates,
      summaryCounts: summaryCounts ?? this.summaryCounts,
    );
  }
}

@immutable
final class PatientSummaryRecord {
  const PatientSummaryRecord({
    required this.id,
    required this.kind,
    this.status,
    this.title,
    this.subtitle,
    this.amount,
    this.currency,
    this.occurredAt,
  });

  final String id;
  final String kind;
  final String? status;
  final String? title;
  final String? subtitle;
  final num? amount;
  final String? currency;
  final DateTime? occurredAt;
}

@immutable
final class PatientDuplicateFieldComparison {
  const PatientDuplicateFieldComparison({
    required this.field,
    required this.inputValue,
    required this.candidateValue,
    required this.status,
    this.contribution = 0,
    this.similarityPercent,
  });

  final String field;
  final String inputValue;
  final String candidateValue;
  final String status;
  final int contribution;
  final int? similarityPercent;

  bool get isConflict => status.toUpperCase() == 'CONFLICT';
}

@immutable
final class PatientDuplicateCandidate {
  const PatientDuplicateCandidate({
    required this.reviewId,
    required this.confidenceScore,
    required this.classification,
    this.matchReasons = const <String>[],
    this.fieldComparisons = const <PatientDuplicateFieldComparison>[],
    this.scoreVersion,
    this.primaryPatient,
    this.secondaryPatient,
    this.candidatePatient,
  });

  final String reviewId;
  final int confidenceScore;
  final String classification;
  final List<String> matchReasons;
  final List<PatientDuplicateFieldComparison> fieldComparisons;
  final String? scoreVersion;
  final Patient? primaryPatient;
  final Patient? secondaryPatient;
  final Patient? candidatePatient;

  List<Patient> get patients {
    final Map<String, Patient> values = <String, Patient>{};
    for (final Patient? patient in <Patient?>[
      primaryPatient,
      secondaryPatient,
      candidatePatient,
    ]) {
      if (patient != null && patient.id.isNotEmpty) {
        values[patient.id] = patient;
      }
    }

    return values.values.toList(growable: false);
  }
}

@immutable
final class PatientMergePreview {
  const PatientMergePreview({
    required this.primaryPatient,
    required this.secondaryPatient,
    required this.confidenceScore,
    required this.classification,
    this.matchReasons = const <String>[],
    this.transferCounts = const <String, int>{},
  });

  final Patient primaryPatient;
  final Patient secondaryPatient;
  final int confidenceScore;
  final String classification;
  final List<String> matchReasons;
  final Map<String, int> transferCounts;
}

@immutable
final class PatientDeletionBlocker {
  const PatientDeletionBlocker({
    required this.code,
    this.model,
    this.count = 0,
  });

  final String code;
  final String? model;
  final int count;
}

@immutable
final class PatientDeletionImpact {
  const PatientDeletionImpact({
    required this.patientId,
    this.humanFriendlyId,
    this.blockers = const <PatientDeletionBlocker>[],
    this.countsByCategory = const <String, int>{},
    this.countsByModel = const <String, int>{},
  });

  final String patientId;
  final String? humanFriendlyId;
  final List<PatientDeletionBlocker> blockers;
  final Map<String, int> countsByCategory;
  final Map<String, int> countsByModel;

  bool get hasBlockers => blockers.isNotEmpty;

  /// Prefer category totals for soft-delete confirm UI.
  Map<String, int> get counts =>
      countsByCategory.isNotEmpty ? countsByCategory : countsByModel;
}

@immutable
final class PatientDetail {
  const PatientDetail({
    required this.patient,
    required this.workspace,
    this.identifiers = const <PatientIdentifier>[],
    this.contacts = const <PatientContact>[],
    this.guardians = const <PatientGuardian>[],
    this.allergies = const <PatientAllergy>[],
    this.medicalHistories = const <PatientMedicalHistory>[],
    this.documents = const <PatientDocument>[],
    this.consents = const <PatientConsent>[],
    this.timeline = const <PatientTimelineItem>[],
  });

  final Patient patient;
  final PatientWorkspaceSnapshot workspace;
  final List<PatientIdentifier> identifiers;
  final List<PatientContact> contacts;
  final List<PatientGuardian> guardians;
  final List<PatientAllergy> allergies;
  final List<PatientMedicalHistory> medicalHistories;
  final List<PatientDocument> documents;
  final List<PatientConsent> consents;
  final List<PatientTimelineItem> timeline;

  PatientDetail copyWith({
    Patient? patient,
    PatientWorkspaceSnapshot? workspace,
    List<PatientIdentifier>? identifiers,
    List<PatientContact>? contacts,
    List<PatientGuardian>? guardians,
    List<PatientAllergy>? allergies,
    List<PatientMedicalHistory>? medicalHistories,
    List<PatientDocument>? documents,
    List<PatientConsent>? consents,
    List<PatientTimelineItem>? timeline,
  }) {
    return PatientDetail(
      patient: patient ?? this.patient,
      workspace: workspace ?? this.workspace,
      identifiers: identifiers ?? this.identifiers,
      contacts: contacts ?? this.contacts,
      guardians: guardians ?? this.guardians,
      allergies: allergies ?? this.allergies,
      medicalHistories: medicalHistories ?? this.medicalHistories,
      documents: documents ?? this.documents,
      consents: consents ?? this.consents,
      timeline: timeline ?? this.timeline,
    );
  }
}

@immutable
final class PatientRegistryOverview {
  const PatientRegistryOverview({
    this.totalPatients = 0,
    this.activePatients = 0,
    this.waitingQueue = 0,
    this.activeAdmissions = 0,
    this.unpaidInvoices = 0,
    this.dueFollowUps = 0,
    this.duplicates = const <PatientDuplicateCandidate>[],
    this.recentPatients = const <Patient>[],
    this.waitingQueuePatients = const <Patient>[],
    this.consentExceptions = 0,
    this.missingDocuments = 0,
  });

  final int totalPatients;
  final int activePatients;
  final int waitingQueue;
  final int activeAdmissions;
  final int unpaidInvoices;
  final int dueFollowUps;
  final List<PatientDuplicateCandidate> duplicates;
  final List<Patient> recentPatients;
  final List<Patient> waitingQueuePatients;
  final int consentExceptions;
  final int missingDocuments;

  PatientRegistryOverview copyWith({
    int? totalPatients,
    int? activePatients,
    int? waitingQueue,
    int? activeAdmissions,
    int? unpaidInvoices,
    int? dueFollowUps,
    List<PatientDuplicateCandidate>? duplicates,
    List<Patient>? recentPatients,
    List<Patient>? waitingQueuePatients,
    int? consentExceptions,
    int? missingDocuments,
  }) {
    return PatientRegistryOverview(
      totalPatients: totalPatients ?? this.totalPatients,
      activePatients: activePatients ?? this.activePatients,
      waitingQueue: waitingQueue ?? this.waitingQueue,
      activeAdmissions: activeAdmissions ?? this.activeAdmissions,
      unpaidInvoices: unpaidInvoices ?? this.unpaidInvoices,
      dueFollowUps: dueFollowUps ?? this.dueFollowUps,
      duplicates: duplicates ?? this.duplicates,
      recentPatients: recentPatients ?? this.recentPatients,
      waitingQueuePatients: waitingQueuePatients ?? this.waitingQueuePatients,
      consentExceptions: consentExceptions ?? this.consentExceptions,
      missingDocuments: missingDocuments ?? this.missingDocuments,
    );
  }
}

@immutable
final class PatientReferenceData {
  const PatientReferenceData({
    this.tenants = const <PatientReferenceOption>[],
    this.facilities = const <PatientReferenceOption>[],
    this.wards = const <PatientReferenceOption>[],
    this.rooms = const <PatientReferenceOption>[],
    this.beds = const <PatientReferenceOption>[],
    this.documentTypes = const <String>[],
    this.consentTypes = const <String>[],
    this.consentStatuses = const <String>[],
    this.appointmentStatuses = const <String>[],
  });

  final List<PatientReferenceOption> tenants;
  final List<PatientReferenceOption> facilities;
  final List<PatientReferenceOption> wards;
  final List<PatientReferenceOption> rooms;
  final List<PatientReferenceOption> beds;
  final List<String> documentTypes;
  final List<String> consentTypes;
  final List<String> consentStatuses;
  final List<String> appointmentStatuses;
}

@immutable
final class PatientReferenceOption {
  const PatientReferenceOption({
    required this.id,
    required this.label,
    this.tenantId,
    this.facilityId,
    this.wardId,
    this.roomId,
    this.status,
    this.type,
  });

  final String id;
  final String label;
  final String? tenantId;
  final String? facilityId;
  final String? wardId;
  final String? roomId;
  final String? status;
  final String? type;
}

@immutable
final class PatientRegistryState {
  const PatientRegistryState({
    required this.query,
    required this.page,
    required this.overview,
    required this.referenceData,
    this.selectedDetail,
    this.lastFailure,
    this.isRefreshingList = false,
    this.isRefreshingDetail = false,
    this.isSaving = false,
  });

  factory PatientRegistryState.empty() {
    return const PatientRegistryState(
      query: PatientListQuery(),
      page: AppPage<Patient>(items: <Patient>[], request: AppPageRequest()),
      overview: PatientRegistryOverview(),
      referenceData: PatientReferenceData(),
    );
  }

  final PatientListQuery query;
  final AppPage<Patient> page;
  final PatientRegistryOverview overview;
  final PatientReferenceData referenceData;
  final PatientDetail? selectedDetail;
  final Object? lastFailure;
  final bool isRefreshingList;
  final bool isRefreshingDetail;
  final bool isSaving;

  PatientRegistryState copyWith({
    PatientListQuery? query,
    AppPage<Patient>? page,
    PatientRegistryOverview? overview,
    PatientReferenceData? referenceData,
    PatientDetail? selectedDetail,
    Object? lastFailure,
    bool? isRefreshingList,
    bool? isRefreshingDetail,
    bool? isSaving,
    bool clearSelectedDetail = false,
    bool clearLastFailure = false,
  }) {
    return PatientRegistryState(
      query: query ?? this.query,
      page: page ?? this.page,
      overview: overview ?? this.overview,
      referenceData: referenceData ?? this.referenceData,
      selectedDetail: clearSelectedDetail
          ? null
          : selectedDetail ?? this.selectedDetail,
      lastFailure: clearLastFailure ? null : lastFailure ?? this.lastFailure,
      isRefreshingList: isRefreshingList ?? this.isRefreshingList,
      isRefreshingDetail: isRefreshingDetail ?? this.isRefreshingDetail,
      isSaving: isSaving ?? this.isSaving,
    );
  }
}

enum PatientRelatedResource {
  identifier,
  contact,
  guardian,
  allergy,
  medicalHistory,
  consent,
}

@immutable
final class PatientMutationResult {
  const PatientMutationResult({required this.patientId});

  final String patientId;
}

String? _firstNonEmpty(Iterable<String?> values) {
  for (final String? value in values) {
    final String normalized = value?.trim() ?? '';
    if (normalized.isNotEmpty) {
      return normalized;
    }
  }

  return null;
}
