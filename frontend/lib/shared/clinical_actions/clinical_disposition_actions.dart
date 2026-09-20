import 'package:hosspi_hms/l10n/app_localizations.dart';

String clinicalDispositionActionLabel(
  AppLocalizations l10n, {
  String? sourceQueue,
  String? status,
  String? stage,
  String? location,
  bool hasAdmission = false,
  bool isOpdContext = false,
}) {
  final String normalizedSource = _normalize(sourceQueue);
  final String normalizedStatus = _normalize(status);
  final String normalizedStage = _normalize(stage);
  final String normalizedLocation = _normalize(location);
  final bool hasInpatientLocation =
      normalizedLocation.contains('WARD') ||
      normalizedLocation.contains('BED') ||
      normalizedLocation.contains('IPD');

  if (isClinicalTriageDischargeContext(
    sourceQueue: normalizedSource,
    stage: normalizedStage,
  )) {
    return l10n.navigationDischargeLabel;
  }

  if (hasAdmission &&
      _matchesAny(<String>[
        normalizedStage,
        normalizedStatus,
      ], 'DISCHARGE_PLANNED')) {
    return l10n.ipdFinalizeDischargeAction;
  }

  if (hasAdmission &&
      (_isActiveAdmissionState(normalizedStage) ||
          _isActiveAdmissionState(normalizedStatus) ||
          normalizedSource == 'IPD' ||
          hasInpatientLocation)) {
    return l10n.navigationDischargeLabel;
  }

  if (isOpdContext || normalizedSource == 'OPD') {
    return l10n.opdDispositionAction;
  }

  return l10n.clinicalCompleteDispositionAction;
}

bool isClinicalTriageDischargeContext({String? sourceQueue, String? stage}) {
  final String normalizedSource = _normalize(sourceQueue);
  final String normalizedStage = _normalize(stage);
  return normalizedSource == 'TRIAGE' &&
      switch (normalizedStage) {
        'WAITING_CONSULTATION_PAYMENT' ||
        'WAITING_VITALS' ||
        'WAITING_DOCTOR_ASSIGNMENT' => true,
        '' => true,
        _ => false,
      };
}

/// Whether a clinician can close out the visit from here.
///
/// Every open OPD stage qualifies. A visit that ends before payment, before
/// vitals or before a doctor was assigned is a real outcome (patient left,
/// nurse-only visit, wrong queue) and the backend records that no review was
/// captured, so there is nothing to gain by hiding the action.
bool isClinicalDoctorDispositionContext({String? sourceQueue, String? stage}) {
  final String normalizedSource = _normalize(sourceQueue);
  final String normalizedStage = _normalize(stage);
  if (normalizedSource == 'TRIAGE') {
    return false;
  }
  return !isClinicalTerminalOpdStage(normalizedStage);
}

/// OPD stages that have already closed the encounter.
bool isClinicalTerminalOpdStage(String? stage) {
  return switch (_normalize(stage)) {
    'ADMITTED' || 'DISCHARGED' || 'CANCELLED' || 'CLOSED' || 'COMPLETED' =>
      true,
    _ => false,
  };
}

bool isClinicalDispositionActionAvailable({
  String? sourceQueue,
  String? status,
  String? stage,
  String? location,
  bool hasAdmission = false,
  bool hasOpdFlow = false,
}) {
  if (isClinicalAdmissionDischargeContext(
    sourceQueue: sourceQueue,
    status: status,
    stage: stage,
    location: location,
    hasAdmission: hasAdmission,
  )) {
    return true;
  }
  if (!hasOpdFlow) {
    return false;
  }
  return isClinicalTriageDischargeContext(
        sourceQueue: sourceQueue,
        stage: stage,
      ) ||
      isClinicalDoctorDispositionContext(
        sourceQueue: sourceQueue,
        stage: stage,
      );
}

bool isClinicalAdmissionDischargeContext({
  String? sourceQueue,
  String? status,
  String? stage,
  String? location,
  bool hasAdmission = false,
}) {
  if (!hasAdmission) {
    return false;
  }
  final String normalizedSource = _normalize(sourceQueue);
  final String normalizedStatus = _normalize(status);
  final String normalizedStage = _normalize(stage);
  final String normalizedLocation = _normalize(location);

  return _isActiveAdmissionState(normalizedStage) ||
      _isActiveAdmissionState(normalizedStatus) ||
      normalizedSource == 'IPD' ||
      normalizedLocation.contains('WARD') ||
      normalizedLocation.contains('BED') ||
      normalizedLocation.contains('IPD');
}

bool _isActiveAdmissionState(String value) {
  return switch (value) {
    'ACTIVE' ||
    'ADMITTED' ||
    'ADMITTED_PENDING_BED' ||
    'ADMITTED_IN_BED' ||
    'TRANSFER_REQUESTED' ||
    'TRANSFER_IN_PROGRESS' ||
    'DISCHARGE_PLANNED' => true,
    _ => false,
  };
}

bool _matchesAny(List<String> values, String target) {
  return values.any((String value) => value == target);
}

String _normalize(String? value) {
  return (value ?? '').trim().toUpperCase();
}
