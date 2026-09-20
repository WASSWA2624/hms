import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/core/permissions/access_policy.dart';
import 'package:hosspi_hms/core/permissions/permission_providers.dart';
import 'package:hosspi_hms/core/utils/app_formatters.dart';
import 'package:hosspi_hms/features/patients/domain/entities/patient_entities.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/components/components.dart';
import 'package:hosspi_hms/shared/layout/layout.dart';

export 'package:hosspi_hms/shared/patient_actions/patient_age_formatter.dart'
    show formatPatientAge, patientGenderIcon, patientGenderLabel;

String patientIdentifierTypeLabel(AppLocalizations l10n, Patient patient) {
  final String? type = patient.primaryIdentifierType?.trim();
  if (type == null || type.isEmpty) {
    return l10n.patientsIdentifierLabel;
  }
  return switch (type.toUpperCase()) {
    'MRN' => 'MRN',
    'NATIONAL_ID' => l10n.patientsIdentifierLabel,
    _ => type.replaceAll('_', ' '),
  };
}

/// Renders a stored calendar day (date of birth). Uses the non-shifting
/// formatter so the date never moves a day across a timezone boundary.
String formatPatientOptionalDate(BuildContext context, DateTime? value) {
  return value == null
      ? context.l10n.profileUnknownValue
      : AppFormatters.calendarDate(value, Localizations.localeOf(context));
}

/// Demographic / bio summary for the Patient Details section body.
///
/// Intentionally flat (no nested collapsible) so the dialog title stays
/// "Patient Details" and the patient name lives inside this card.
class PatientDetailHeader extends ConsumerWidget {
  const PatientDetailHeader({
    required this.detail,
    required this.referenceData,
    super.key,
  });

  final PatientDetail detail;
  final PatientReferenceData referenceData;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Patient patient = detail.patient;
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final AppAccessPolicy accessPolicy = ref.watch(appAccessPolicyProvider);
    final PatientRegistrationScope registrationScope =
        PatientRegistrationScope.resolve(
          referenceData: referenceData,
          accessPolicy: accessPolicy,
        );
    final String gender = patient.gender == null
        ? l10n.profileUnknownValue
        : patientGenderLabel(l10n, patient.gender!);
    final IconData? genderIcon = patientGenderIcon(patient.gender);
    final PatientVisitContext? visit = patient.currentVisit;
    final String publicId = (patient.publicId ?? '').trim();
    final String identifier = (patient.effectiveIdentifier ?? '').trim();
    final String unknown = l10n.profileUnknownValue;

    final List<AppWorkspacePatientContextField> fields =
        <AppWorkspacePatientContextField>[
          AppWorkspacePatientContextField(
            label: l10n.patientsNameLabel,
            value: patient.effectiveDisplayName,
            icon: Icons.person_outline,
          ),
          AppWorkspacePatientContextField(
            label: l10n.patientsGenderLabel,
            value: gender,
            icon: genderIcon ?? Icons.wc_outlined,
          ),
          AppWorkspacePatientContextField(
            label: l10n.patientsAgeColumnLabel,
            value: formatPatientAge(l10n, patient.dateOfBirth),
            icon: Icons.cake_outlined,
          ),
          AppWorkspacePatientContextField(
            label: l10n.patientsDobLabel,
            value: formatPatientOptionalDate(context, patient.dateOfBirth),
            icon: Icons.event_outlined,
          ),
          AppWorkspacePatientContextField(
            label: l10n.patientsPhoneLabel,
            value: (patient.primaryPhone ?? '').trim().isEmpty
                ? unknown
                : patient.primaryPhone!,
            icon: Icons.phone_outlined,
          ),
          AppWorkspacePatientContextField(
            label: l10n.patientsEmailLabel,
            value: (patient.primaryEmail ?? '').trim().isEmpty
                ? unknown
                : patient.primaryEmail!,
            icon: Icons.email_outlined,
          ),
          AppWorkspacePatientContextField(
            label: l10n.patientsStatusColumnLabel,
            value: patient.isActive
                ? l10n.patientsActiveFilter
                : l10n.patientsInactiveFilter,
            icon: patient.isActive
                ? Icons.check_circle_outline
                : Icons.block_outlined,
            tone: patient.isActive
                ? AppWorkspaceStatusTone.success
                : AppWorkspaceStatusTone.neutral,
          ),
          if (identifier.isNotEmpty)
            AppWorkspacePatientContextField(
              label: patientIdentifierTypeLabel(l10n, patient),
              value: identifier,
              icon: Icons.badge_outlined,
              copyable: true,
              copyTooltip: l10n.copyIdentifierAction,
              copiedMessage: l10n.identifierCopiedMessage,
            ),
          if (publicId.isNotEmpty && publicId != identifier)
            AppWorkspacePatientContextField(
              label: l10n.patientsPatientIdFilterLabel,
              value: publicId,
              icon: Icons.fingerprint_outlined,
              copyable: true,
              copyTooltip: l10n.copyIdentifierAction,
              copiedMessage: l10n.identifierCopiedMessage,
            ),
          AppWorkspacePatientContextField(
            label: l10n.patientsFacilityLabel,
            value: patient.facilityLabel ?? unknown,
            icon: Icons.business_outlined,
            authorized: registrationScope.showFacilityPicker,
          ),
          if ((patient.tenantLabel ?? '').trim().isNotEmpty &&
              registrationScope.showTenantPicker)
            AppWorkspacePatientContextField(
              label: l10n.tenantFacilitySetupTabTenant,
              value: patient.tenantLabel!,
              icon: Icons.apartment_outlined,
            ),
          if (visit != null && (visit.publicId ?? '').trim().isNotEmpty)
            AppWorkspacePatientContextField(
              label: l10n.patientsVisitIdLabel,
              value: visit.publicId!,
              icon: Icons.assignment_turned_in_outlined,
              tone: AppWorkspaceStatusTone.info,
              copyable: true,
              copyTooltip: l10n.copyIdentifierAction,
              copiedMessage: l10n.identifierCopiedMessage,
            ),
        ];

    return Semantics(
      container: true,
      label: l10n.patientsDetailTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (patient.hasAllergyAlert || patient.requiresCompletion) ...<
            Widget
          >[
            Wrap(
              spacing: theme.spacing.sm,
              runSpacing: theme.spacing.xs,
              children: <Widget>[
                if (patient.hasAllergyAlert)
                  AppWorkspaceStatusBadge(
                    status: AppWorkspaceStatus(
                      label:
                          patient.allergyAlertLabel ??
                          l10n.patientsAllergyAlertLabel,
                      tone: AppWorkspaceStatusTone.warning,
                      icon: Icons.warning_amber_outlined,
                    ),
                  ),
                if (patient.requiresCompletion)
                  AppWorkspaceStatusBadge(
                    status: AppWorkspaceStatus(
                      label: l10n.patientsRegistrationIncompleteValue,
                      tone: AppWorkspaceStatusTone.warning,
                      icon: Icons.error_outline,
                    ),
                  ),
              ],
            ),
            SizedBox(height: theme.spacing.sm),
          ],
          AppPatientContextFactsRow(fields: fields),
        ],
      ),
    );
  }
}
