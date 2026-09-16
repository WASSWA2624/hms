import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hosspi_hms/app/printing/print_form_template_context.dart';
import 'package:hosspi_hms/app/router/app_routes.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/network/app_connectivity_status.dart';
import 'package:hosspi_hms/core/permissions/access_gate.dart';
import 'package:hosspi_hms/core/permissions/access_policy.dart';
import 'package:hosspi_hms/core/permissions/access_requirement.dart';
import 'package:hosspi_hms/core/permissions/permission_providers.dart';
import 'package:hosspi_hms/core/utils/app_display.dart';
import 'package:hosspi_hms/core/utils/app_formatters.dart';
import 'package:hosspi_hms/features/claims/data/repositories/claims_repository_impl.dart';
import 'package:hosspi_hms/features/claims/domain/entities/claims_entities.dart';
import 'package:hosspi_hms/features/claims/presentation/widgets/claims_insurance_config_dialogs.dart';
import 'package:hosspi_hms/features/opd/data/repositories/opd_repository_impl.dart';
import 'package:hosspi_hms/features/opd/domain/entities/opd_entities.dart';
import 'package:hosspi_hms/features/opd/presentation/controllers/opd_encounter_dialog_controller.dart';
import 'package:hosspi_hms/features/opd/presentation/controllers/opd_workspace_controller.dart';
import 'package:hosspi_hms/features/patients/data/repositories/patient_repository_impl.dart';
import 'package:hosspi_hms/features/patients/domain/entities/patient_entities.dart';
import 'package:hosspi_hms/features/patients/presentation/controllers/patient_registry_controller.dart';
import 'package:hosspi_hms/features/patients/presentation/patient_registry_access.dart';
import 'package:hosspi_hms/features/patients/presentation/widgets/patient_billing_context_panel.dart';
import 'package:hosspi_hms/features/patients/presentation/widgets/patient_pharmacy_context_panel.dart';
import 'package:hosspi_hms/features/patients/presentation/widgets/patient_registry_print_helpers.dart';
import 'package:hosspi_hms/features/patients/presentation/widgets/patient_widgets.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/actions/actions.dart';
import 'package:hosspi_hms/shared/clinical_actions/clinical_actions.dart';
import 'package:hosspi_hms/shared/components/components.dart';
import 'package:hosspi_hms/shared/data/data.dart';
import 'package:hosspi_hms/shared/forms/forms.dart';
import 'package:hosspi_hms/shared/layout/layout.dart';
import 'package:hosspi_hms/shared/opd_actions/opd_actions.dart';
import 'package:hosspi_hms/shared/opd_actions/opd_provider_options.dart';
import 'package:hosspi_hms/shared/printing/printing.dart';
import 'package:hosspi_hms/shared/routing/workspace_location_sync.dart';

part '../widgets/patient_detail_dialog_body.dart';

class PatientRegistryPage extends ConsumerWidget {
  const PatientRegistryPage({super.key, this.initialQuery});

  final PatientListQuery? initialQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final AsyncValue<Result<PatientRegistryState>> state = ref.watch(
      patientRegistryControllerProvider,
    );

    return AppAccessGate(
      requirement: patientRegistryReadRequirement,
      deniedBuilder: (_, _) => AppStateScaffold(
        variant: AppStateViewVariant.forbidden,
        title: l10n.routeForbiddenTitle,
        body: l10n.routeForbiddenBody,
      ),
      child: AsyncStateScaffold<PatientRegistryState>(
        value: state,
        loadingTitle: l10n.patientsLoadingTitle,
        loadingBody: l10n.patientsLoadingBody,
        maxWidth: PageMaxWidth.dataHeavy,
        centerVertically: false,
        onRetry: () {
          ref.read(patientRegistryControllerProvider.notifier).refresh();
        },
        dataBuilder: (BuildContext context, PatientRegistryState data) {
          return _PatientRegistryContent(
            state: data,
            initialQuery: initialQuery,
          );
        },
      ),
    );
  }
}

class _PatientRegistryContent extends ConsumerStatefulWidget {
  const _PatientRegistryContent({required this.state, this.initialQuery});

  final PatientRegistryState state;
  final PatientListQuery? initialQuery;

  @override
  ConsumerState<_PatientRegistryContent> createState() =>
      _PatientRegistryContentState();
}

class _PatientRegistryContentState
    extends ConsumerState<_PatientRegistryContent> {
  late final TextEditingController _tableSearchController;
  late final AppListTableColumnVisibilityController<Patient>
  _tableColumnController;
  Timer? _tableSearchDebounce;
  bool _handledRouteQuery = false;
  late PatientRegistrySection _section;

  @override
  void initState() {
    super.initState();
    _tableSearchController = TextEditingController(
      text: widget.state.query.search,
    );
    _tableColumnController = AppListTableColumnVisibilityController<Patient>();
    _section = widget.initialQuery?.section ?? PatientRegistrySection.all;
    _tableSearchController.addListener(_handleTableSearchChanged);
    _scheduleRouteQuery(widget.initialQuery);
  }

  void _scheduleRouteQuery(PatientListQuery? query) {
    if (query == null || !query.hasRouteTargeting) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _handledRouteQuery) {
        return;
      }
      _handledRouteQuery = true;
      unawaited(
        ref.read(patientRegistryControllerProvider.notifier).applyQuery(query),
      );
    });
  }

  @override
  void didUpdateWidget(covariant _PatientRegistryContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQuery?.signature != widget.initialQuery?.signature) {
      _handledRouteQuery = false;
      _scheduleRouteQuery(widget.initialQuery);
    }
    final String nextSearch = widget.state.query.search;
    if (oldWidget.state.query.search != nextSearch &&
        _tableSearchController.text != nextSearch) {
      _tableSearchController.text = nextSearch;
    }
  }

  @override
  void dispose() {
    _tableSearchDebounce?.cancel();
    _tableSearchController
      ..removeListener(_handleTableSearchChanged)
      ..dispose();
    _tableColumnController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final AppAccessPolicy accessPolicy = ref.watch(appAccessPolicyProvider);
    final List<PatientRegistrySection> allowedSections =
        patientRegistryAllowedSections(accessPolicy);
    if (allowedSections.isNotEmpty &&
        !allowedSections.contains(_section)) {
      final PatientRegistrySection fallback =
          patientRegistryFallbackSection(accessPolicy) ?? allowedSections.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _section == fallback) {
          return;
        }
        unawaited(_handleTabChanged(fallback));
      });
    }

    return ResponsivePage(
      padding: ResponsiveSpacing.workspacePagePaddingFor(
        spacing: Theme.of(context).spacing,
      ),
      maxWidth: PageMaxWidth.dataHeavy,
      scrollable: false,
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppTabStrip(
              tabs: <AppTabItem>[
                for (final PatientRegistrySection section in allowedSections)
                  AppTabItem(
                    id: section.name,
                    icon: _sectionIcon(section),
                    label: _sectionLabel(l10n, section),
                    count: _sectionCount(
                      widget.state,
                      section,
                      activeSection: _section,
                    ),
                    countTone: _sectionCountTone(section),
                  ),
              ],
              selectedId: _section.name,
              onTabTapped: (String tabId) {
                for (final PatientRegistrySection section in allowedSections) {
                  if (section.name == tabId) {
                    unawaited(_handleTabChanged(section));
                    break;
                  }
                }
              },
            ),
            SizedBox(height: theme.spacing.sm),
            Expanded(
              child: _PatientList(
                state: widget.state,
                section: _section,
                searchController: _tableSearchController,
                columnVisibilityController: _tableColumnController,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleTableSearchChanged() {
    final String query = _tableSearchController.text;
    _tableSearchDebounce?.cancel();
    _tableSearchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        unawaited(_applyTableSearch(query));
      }
    });
  }

  Future<void> _applyTableSearch(String query) async {
    final String search = query.trim();
    if (search == widget.state.query.search.trim()) {
      return;
    }

    final PatientListQuery baseQuery = widget.state.query.copyWith(
      search: search,
      section: _section,
      pageRequest: widget.state.query.pageRequest.first(),
    );
    final PatientListQuery filteredQuery = _section.applyToQuery(baseQuery);
    final AppFailure? failure = await ref
        .read(patientRegistryControllerProvider.notifier)
        .applyQuery(filteredQuery);
    if (mounted) {
      await _showFailureIfNeeded(context, failure);
    }
  }

  void _updateUrlForSection(PatientRegistrySection section) {
    if (!mounted) {
      return;
    }
    final String tab = section.queryValue;
    final String location = AppRoutes.patients.location(
      queryParameters: <String, String>{if (tab.isNotEmpty) 'section': tab},
    );
    syncWorkspaceLocation(context, location);
  }

  Future<void> _handleTabChanged(PatientRegistrySection section) async {
    if (section == _section) {
      return;
    }
    setState(() => _section = section);
    _updateUrlForSection(section);
    _tableSearchController.clear();
    final PatientListQuery baseQuery = const PatientListQuery().copyWith(
      section: section,
    );
    final PatientListQuery filteredQuery = section.applyToQuery(baseQuery);
    final AppFailure? failure = await ref
        .read(patientRegistryControllerProvider.notifier)
        .applyQuery(filteredQuery);
    if (mounted) {
      await _showFailureIfNeeded(context, failure);
    }
  }

  static IconData _sectionIcon(PatientRegistrySection section) {
    switch (section) {
      case PatientRegistrySection.all:
        return Icons.people_outlined;
      case PatientRegistrySection.active:
        return Icons.how_to_reg_outlined;
      case PatientRegistrySection.admitted:
        return Icons.local_hospital_outlined;
      case PatientRegistrySection.balanceDue:
        return Icons.payments_outlined;
    }
  }

  static String _sectionLabel(
    AppLocalizations l10n,
    PatientRegistrySection section,
  ) {
    switch (section) {
      case PatientRegistrySection.all:
        return l10n.patientsTabAll;
      case PatientRegistrySection.active:
        return l10n.patientsTabActive;
      case PatientRegistrySection.admitted:
        return l10n.patientsTabAdmitted;
      case PatientRegistrySection.balanceDue:
        return l10n.patientsTabBalanceDue;
    }
  }

  static int _sectionCount(
    PatientRegistryState state,
    PatientRegistrySection section, {
    required PatientRegistrySection activeSection,
  }) {
    final int scopeTotal = _sectionScopeTotal(state, section);
    if (section != activeSection) {
      return scopeTotal;
    }
    if (!_hasPatientListNarrowing(state.query, section)) {
      return scopeTotal;
    }
    // Active tab only — filtered membership from the current list query.
    // Prefer server totalItemCount; never fall back to painted page length.
    return state.page.totalItemCount ?? scopeTotal;
  }

  static int _sectionScopeTotal(
    PatientRegistryState state,
    PatientRegistrySection section,
  ) {
    switch (section) {
      case PatientRegistrySection.all:
        return state.overview.totalPatients;
      case PatientRegistrySection.active:
        return state.overview.activePatients;
      case PatientRegistrySection.admitted:
        return state.overview.activeAdmissions;
      case PatientRegistrySection.balanceDue:
        return state.overview.unpaidInvoices;
    }
  }

  static AppTabCountTone _sectionCountTone(PatientRegistrySection section) {
    return switch (section) {
      PatientRegistrySection.balanceDue => AppTabCountTone.warning,
      PatientRegistrySection.all ||
      PatientRegistrySection.active ||
      PatientRegistrySection.admitted => AppTabCountTone.info,
    };
  }

}

Future<void> _openDuplicateReviewDialog(
  BuildContext context,
  WidgetRef ref,
  List<PatientDuplicateCandidate> duplicates,
) async {
  final String? survivorPatientId = await showAppDialog<String>(
    context: context,
    builder: (_) => PatientDuplicateReviewDialog(duplicates: duplicates),
  );
  if (!context.mounted ||
      survivorPatientId == null ||
      survivorPatientId.trim().isEmpty) {
    return;
  }
  await showPatientDetailDialog(context, ref, survivorPatientId.trim());
}

Future<void> _openRegisterPatientDialog(
  BuildContext context,
  WidgetRef ref,
  PatientRegistryState state,
) async {
  final PatientRegistrationResult? registration =
      await showRegisterNewPatientDialog(
        context: context,
        referenceData: state.referenceData,
        registrationScope: PatientRegistrationScope.resolve(
          referenceData: state.referenceData,
          accessPolicy: ref.read(appAccessPolicyProvider),
        ),
        onLookupDuplicates: (PatientDuplicateQuery query) {
          return ref
              .read(patientRegistryControllerProvider.notifier)
              .loadDuplicateCandidates(query);
        },
        onSubmit: (Map<String, Object?> payload) {
          return ref
              .read(patientRegistryControllerProvider.notifier)
              .createPatient(payload);
        },
      );

  if (registration == null || !context.mounted) {
    return;
  }

  if (registration.wasCreated) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.patientsSavedMessage)),
    );
  }
  await showPatientDetailDialog(context, ref, registration.patient.id);
}

@immutable
final class _PatientFilterDraft {
  const _PatientFilterDraft({
    required this.patientId,
    required this.contact,
    required this.facilityId,
    required this.gender,
    required this.status,
    required this.consentState,
    required this.appointmentStatus,
    required this.visitDate,
    required this.visitFrom,
    required this.visitTo,
    required this.createdFrom,
    required this.createdTo,
    required this.dateOfBirthFrom,
    required this.dateOfBirthTo,
    required this.hasActiveAdmission,
    required this.hasOutstandingBalance,
  });

  final String patientId;
  final String contact;
  final String? facilityId;
  final String? gender;
  final String? status;
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
}

class _PatientAdvancedFiltersDialog extends StatefulWidget {
  const _PatientAdvancedFiltersDialog({
    required this.patientId,
    required this.contact,
    required this.facilityId,
    required this.gender,
    required this.status,
    required this.consentState,
    required this.appointmentStatus,
    required this.visitDate,
    required this.visitFrom,
    required this.visitTo,
    required this.createdFrom,
    required this.createdTo,
    required this.dateOfBirthFrom,
    required this.dateOfBirthTo,
    required this.hasActiveAdmission,
    required this.hasOutstandingBalance,
    required this.facilities,
    required this.appointmentStatuses,
    required this.consentStatuses,
    this.showActiveAdmissionFilter = true,
    this.showOutstandingBalanceFilter = true,
  });

  final String patientId;
  final String contact;
  final String? facilityId;
  final String? gender;
  final String? status;
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
  final List<PatientReferenceOption> facilities;
  final List<String> appointmentStatuses;
  final List<String> consentStatuses;
  final bool showActiveAdmissionFilter;
  final bool showOutstandingBalanceFilter;

  @override
  State<_PatientAdvancedFiltersDialog> createState() =>
      _PatientAdvancedFiltersDialogState();
}

class _PatientAdvancedFiltersDialogState
    extends State<_PatientAdvancedFiltersDialog> {
  late final TextEditingController _patientIdController;
  late final TextEditingController _contactController;
  String? _facilityId;
  String? _gender;
  String? _status;
  String? _consentState;
  String? _appointmentStatus;
  DateTime? _visitDate;
  DateTime? _visitFrom;
  DateTime? _visitTo;
  DateTime? _createdFrom;
  DateTime? _createdTo;
  DateTime? _dateOfBirthFrom;
  DateTime? _dateOfBirthTo;
  bool? _hasActiveAdmission;
  bool? _hasOutstandingBalance;

  @override
  void initState() {
    super.initState();
    _patientIdController = TextEditingController(text: widget.patientId);
    _contactController = TextEditingController(text: widget.contact);
    _facilityId = widget.facilityId;
    _gender = widget.gender;
    _status = widget.status;
    _consentState = widget.consentState;
    _appointmentStatus = widget.appointmentStatus;
    _visitDate = widget.visitDate;
    _visitFrom = widget.visitFrom;
    _visitTo = widget.visitTo;
    _createdFrom = widget.createdFrom;
    _createdTo = widget.createdTo;
    _dateOfBirthFrom = widget.dateOfBirthFrom;
    _dateOfBirthTo = widget.dateOfBirthTo;
    _hasActiveAdmission = widget.hasActiveAdmission;
    _hasOutstandingBalance = widget.hasOutstandingBalance;
  }

  @override
  void dispose() {
    _patientIdController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AppDialog(
      title: Text(l10n.commonAdvancedFiltersTitle),
      icon: const Icon(Icons.tune),
      scrollable: true,
      maxWidth: 760,
      content: AppFormSection(
        density: AppFormSectionDensity.compact,
        children: <Widget>[
          AppFormSection(
            title: l10n.patientsFilterIdentitySectionTitle,
            density: AppFormSectionDensity.compact,
            children: <Widget>[
              AppResponsiveFieldRow.two(
                left: AppTextField(
                  controller: _patientIdController,
                  labelText: l10n.patientsPatientIdFilterLabel,
                  textInputAction: TextInputAction.search,
                ),
                right: AppTextField(
                  controller: _contactController,
                  labelText: l10n.patientsContactFilterLabel,
                  textInputAction: TextInputAction.search,
                ),
              ),
              if (widget.facilities.length > 1)
                AppResponsiveFieldRow.two(
                  left: PatientFacilitySelectField(
                    facilities: widget.facilities,
                    value: _facilityId,
                    labelText: l10n.patientsFacilityLabel,
                    onChanged: (String? value) =>
                        setState(() => _facilityId = value),
                  ),
                  right: AppGenderField(
                    value: _gender,
                    labelText: l10n.patientsGenderFilterLabel,
                    maleLabel: l10n.patientsGenderMale,
                    femaleLabel: l10n.patientsGenderFemale,
                    otherLabel: l10n.patientsGenderOther,
                    unknownLabel: l10n.patientsGenderUnknown,
                    onChanged: (String? value) =>
                        setState(() => _gender = value),
                  ),
                )
              else
                AppGenderField(
                  value: _gender,
                  labelText: l10n.patientsGenderFilterLabel,
                  maleLabel: l10n.patientsGenderMale,
                  femaleLabel: l10n.patientsGenderFemale,
                  otherLabel: l10n.patientsGenderOther,
                  unknownLabel: l10n.patientsGenderUnknown,
                  onChanged: (String? value) => setState(() => _gender = value),
                ),
            ],
          ),
          AppFormSection(
            title: l10n.patientsFilterVisitSectionTitle,
            density: AppFormSectionDensity.compact,
            children: <Widget>[
              PatientDateField(
                value: _visitDate,
                firstDate: _patientFilterFirstDate,
                lastDate: _patientFilterLastDate,
                labelText: l10n.patientsVisitDateFilterLabel,
                onChanged: (DateTime? value) => _visitDate = value,
              ),
              AppResponsiveFieldRow.two(
                left: PatientDateField(
                  value: _visitFrom,
                  firstDate: _patientFilterFirstDate,
                  lastDate: _patientFilterLastDate,
                  labelText: l10n.patientsVisitFromFilterLabel,
                  onChanged: (DateTime? value) => _visitFrom = value,
                ),
                right: PatientDateField(
                  value: _visitTo,
                  firstDate: _patientFilterFirstDate,
                  lastDate: _patientFilterLastDate,
                  labelText: l10n.patientsVisitToFilterLabel,
                  onChanged: (DateTime? value) => _visitTo = value,
                ),
              ),
              AppSelectField<String>.searchable(
                value: _appointmentStatus,
                labelText: l10n.patientsAppointmentStatusLabel,
                onChanged: (String? value) =>
                    setState(() => _appointmentStatus = value),
                options: <AppSelectOption<String>>[
                  for (final String value in widget.appointmentStatuses)
                    AppSelectOption<String>(
                      value: value,
                      label: _apiLabel(value),
                      leadingIcon: Icon(_appointmentStatusIcon(value)),
                    ),
                ],
              ),
            ],
          ),
          AppFormSection(
            title: l10n.patientsFilterRecordSectionTitle,
            density: AppFormSectionDensity.compact,
            children: <Widget>[
              AppResponsiveFieldRow.two(
                left: AppSelectField<String>(
                  value: _status,
                  labelText: l10n.patientsStatusFilterLabel,
                  onChanged: (String? value) => setState(() => _status = value),
                  options: <AppSelectOption<String>>[
                    AppSelectOption<String>(
                      value: _statusActive,
                      label: l10n.patientsActiveFilter,
                    ),
                    AppSelectOption<String>(
                      value: _statusInactive,
                      label: l10n.patientsInactiveFilter,
                    ),
                  ],
                ),
                right: AppSelectField<String>(
                  value: _consentState,
                  labelText: l10n.patientsConsentFilterLabel,
                  onChanged: (String? value) =>
                      setState(() => _consentState = value),
                  options: <AppSelectOption<String>>[
                    for (final String value in widget.consentStatuses)
                      AppSelectOption<String>(
                        value: value,
                        label: _apiLabel(value),
                      ),
                  ],
                ),
              ),
              if (widget.showActiveAdmissionFilter ||
                  widget.showOutstandingBalanceFilter)
                AppResponsiveFieldRow.two(
                  left: widget.showActiveAdmissionFilter
                      ? AppSelectField<bool>(
                          value: _hasActiveAdmission,
                          labelText: l10n.patientsActiveAdmissionFilterLabel,
                          onChanged: (bool? value) =>
                              setState(() => _hasActiveAdmission = value),
                          options: _booleanFilterOptions(l10n),
                        )
                      : const SizedBox.shrink(),
                  right: widget.showOutstandingBalanceFilter
                      ? AppSelectField<bool>(
                          value: _hasOutstandingBalance,
                          labelText:
                              l10n.patientsOutstandingBalanceFilterLabel,
                          onChanged: (bool? value) =>
                              setState(() => _hasOutstandingBalance = value),
                          options: _booleanFilterOptions(l10n),
                        )
                      : const SizedBox.shrink(),
                ),
              AppResponsiveFieldRow.two(
                left: PatientDateField(
                  value: _dateOfBirthFrom,
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now(),
                  labelText: l10n.patientsDobFromFilterLabel,
                  onChanged: (DateTime? value) => _dateOfBirthFrom = value,
                ),
                right: PatientDateField(
                  value: _dateOfBirthTo,
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now(),
                  labelText: l10n.patientsDobToFilterLabel,
                  onChanged: (DateTime? value) => _dateOfBirthTo = value,
                ),
              ),
              AppResponsiveFieldRow.two(
                left: PatientDateField(
                  value: _createdFrom,
                  firstDate: _patientFilterFirstDate,
                  lastDate: _patientFilterLastDate,
                  labelText: l10n.patientsCreatedFromFilterLabel,
                  onChanged: (DateTime? value) => _createdFrom = value,
                ),
                right: PatientDateField(
                  value: _createdTo,
                  firstDate: _patientFilterFirstDate,
                  lastDate: _patientFilterLastDate,
                  labelText: l10n.patientsCreatedToFilterLabel,
                  onChanged: (DateTime? value) => _createdTo = value,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: <Widget>[
        AppButton.tertiary(
          label: l10n.opdClearFiltersAction,
          leadingIcon: Icons.filter_alt_off_outlined,
          onPressed: () {
            Navigator.of(context).pop(
              const _PatientFilterDraft(
                patientId: '',
                contact: '',
                facilityId: null,
                gender: null,
                status: null,
                consentState: null,
                appointmentStatus: null,
                visitDate: null,
                visitFrom: null,
                visitTo: null,
                createdFrom: null,
                createdTo: null,
                dateOfBirthFrom: null,
                dateOfBirthTo: null,
                hasActiveAdmission: null,
                hasOutstandingBalance: null,
              ),
            );
          },
        ),
        AppButton.primary(
          label: l10n.opdApplyFiltersAction,
          leadingIcon: Icons.filter_alt_outlined,
          onPressed: () {
            Navigator.of(context).pop(
              _PatientFilterDraft(
                patientId: _patientIdController.text.trim(),
                contact: _contactController.text.trim(),
                facilityId: _facilityId,
                gender: _gender,
                status: _status,
                consentState: _consentState,
                appointmentStatus: _appointmentStatus,
                visitDate: _visitDate,
                visitFrom: _visitFrom,
                visitTo: _visitTo,
                createdFrom: _createdFrom,
                createdTo: _createdTo,
                dateOfBirthFrom: _dateOfBirthFrom,
                dateOfBirthTo: _dateOfBirthTo,
                hasActiveAdmission: _hasActiveAdmission,
                hasOutstandingBalance: _hasOutstandingBalance,
              ),
            );
          },
        ),
        AppButton.close(
          label: l10n.commonCloseActionLabel,
          leadingIcon: Icons.close,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// User-chosen advanced filters, ignoring section-imposed scope flags.
bool _hasPatientUserAdvancedFilters(
  PatientListQuery query,
  PatientRegistrySection section,
) {
  final bool ignoresActiveScope =
      section == PatientRegistrySection.active && query.isActive == true;
  final bool ignoresAdmissionScope =
      section == PatientRegistrySection.admitted &&
      query.hasActiveAdmission == true;
  final bool ignoresBalanceScope =
      section == PatientRegistrySection.balanceDue &&
      query.hasOutstandingBalance == true;

  return query.patientId.trim().isNotEmpty ||
      query.contact.trim().isNotEmpty ||
      query.facilityId != null ||
      query.gender != null ||
      (query.isActive != null && !ignoresActiveScope) ||
      query.consentState != null ||
      query.appointmentStatus != null ||
      query.visitDate != null ||
      query.visitFrom != null ||
      query.visitTo != null ||
      query.createdFrom != null ||
      query.createdTo != null ||
      query.dateOfBirthFrom != null ||
      query.dateOfBirthTo != null ||
      (query.hasActiveAdmission != null && !ignoresAdmissionScope) ||
      (query.hasOutstandingBalance != null && !ignoresBalanceScope);
}

bool _hasPatientListNarrowing(
  PatientListQuery query,
  PatientRegistrySection section,
) {
  return query.search.trim().isNotEmpty ||
      _hasPatientUserAdvancedFilters(query, section);
}

_PatientFilterDraft _patientFilterDraftFromQuery(PatientListQuery query) {
  return _PatientFilterDraft(
    patientId: query.patientId,
    contact: query.contact,
    facilityId: query.facilityId,
    gender: query.gender,
    status: _statusValue(query.isActive),
    consentState: query.consentState,
    appointmentStatus: query.appointmentStatus,
    visitDate: query.visitDate,
    visitFrom: query.visitFrom,
    visitTo: query.visitTo,
    createdFrom: query.createdFrom,
    createdTo: query.createdTo,
    dateOfBirthFrom: query.dateOfBirthFrom,
    dateOfBirthTo: query.dateOfBirthTo,
    hasActiveAdmission: query.hasActiveAdmission,
    hasOutstandingBalance: query.hasOutstandingBalance,
  );
}

Future<void> _openPatientAdvancedFilters(
  BuildContext context,
  WidgetRef ref,
  PatientRegistryState state,
  TextEditingController searchController, {
  PatientRegistrySection section = PatientRegistrySection.all,
}) async {
  final PatientRegistryState currentState = _readCurrentState(ref) ?? state;
  final PatientListQuery query = currentState.query;
  final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
  final bool isAdmitted = section == PatientRegistrySection.admitted;
  final bool showActiveAdmissionFilter = !isAdmitted ||
      PatientAdmittedAtomPermissions.nestedRead.isAllowed(policy);
  final bool showOutstandingBalanceFilter = !isAdmitted ||
      PatientAdmittedAtomPermissions.financialStatus.isAllowed(policy);
  final _PatientFilterDraft? draft = await showAppDialog<_PatientFilterDraft>(
    context: context,
    builder: (_) => _PatientAdvancedFiltersDialog(
      patientId: query.patientId,
      contact: query.contact,
      facilityId: query.facilityId,
      gender: query.gender,
      status: _statusValue(query.isActive),
      consentState: query.consentState,
      appointmentStatus: query.appointmentStatus,
      visitDate: query.visitDate,
      visitFrom: query.visitFrom,
      visitTo: query.visitTo,
      createdFrom: query.createdFrom,
      createdTo: query.createdTo,
      dateOfBirthFrom: query.dateOfBirthFrom,
      dateOfBirthTo: query.dateOfBirthTo,
      hasActiveAdmission: showActiveAdmissionFilter
          ? query.hasActiveAdmission
          : null,
      hasOutstandingBalance: showOutstandingBalanceFilter
          ? query.hasOutstandingBalance
          : null,
      facilities: currentState.referenceData.facilities,
      appointmentStatuses: currentState.referenceData.appointmentStatuses,
      consentStatuses: _filterConsentStatuses(currentState),
      showActiveAdmissionFilter: showActiveAdmissionFilter,
      showOutstandingBalanceFilter: showOutstandingBalanceFilter,
    ),
  );
  if (draft == null || !context.mounted) {
    return;
  }

  await _applyPatientFilterDraft(
    context,
    ref,
    currentState,
    searchController,
    draft,
  );
}

Future<void> _applyPatientFilterDraft(
  BuildContext context,
  WidgetRef ref,
  PatientRegistryState state,
  TextEditingController searchController,
  _PatientFilterDraft draft,
) async {
  final PatientListQuery nextQuery = state.query.copyWith(
    search: searchController.text.trim(),
    patientId: draft.patientId.trim(),
    contact: draft.contact.trim(),
    facilityId: draft.facilityId,
    gender: draft.gender,
    isActive: _activeValue(draft.status),
    consentState: draft.consentState,
    appointmentStatus: draft.appointmentStatus,
    visitDate: draft.visitDate,
    visitFrom: draft.visitFrom,
    visitTo: draft.visitTo,
    createdFrom: draft.createdFrom,
    createdTo: draft.createdTo,
    dateOfBirthFrom: draft.dateOfBirthFrom,
    dateOfBirthTo: draft.dateOfBirthTo,
    hasActiveAdmission: draft.hasActiveAdmission,
    hasOutstandingBalance: draft.hasOutstandingBalance,
    pageRequest: state.query.pageRequest.first(),
    clearFacilityId: draft.facilityId == null,
    clearGender: draft.gender == null,
    clearIsActive: draft.status == null,
    clearConsentState: draft.consentState == null,
    clearAppointmentStatus: draft.appointmentStatus == null,
    clearVisitDate: draft.visitDate == null,
    clearVisitFrom: draft.visitFrom == null,
    clearVisitTo: draft.visitTo == null,
    clearCreatedFrom: draft.createdFrom == null,
    clearCreatedTo: draft.createdTo == null,
    clearDateOfBirthFrom: draft.dateOfBirthFrom == null,
    clearDateOfBirthTo: draft.dateOfBirthTo == null,
    clearHasActiveAdmission: draft.hasActiveAdmission == null,
    clearHasOutstandingBalance: draft.hasOutstandingBalance == null,
  );
  final AppFailure? failure = await ref
      .read(patientRegistryControllerProvider.notifier)
      .applyQuery(nextQuery);
  if (context.mounted) {
    await _showFailureIfNeeded(context, failure);
  }
}

class _PatientList extends ConsumerWidget {
  const _PatientList({
    required this.state,
    required this.section,
    required this.searchController,
    required this.columnVisibilityController,
  });

  final PatientRegistryState state;
  final PatientRegistrySection section;
  final TextEditingController searchController;
  final AppListTableColumnVisibilityController<Patient>
  columnVisibilityController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final AppAccessPolicy policy = ref.watch(appAccessPolicyProvider);
    return AppListTable<Patient>(
      page: state.page,
      columnVisibilityController: columnVisibilityController,
      columnVisibilityStorageKey: 'patients_${section.name}',
      columnWidthStorageKey: 'patients_cw_${section.name}',
      columnVisibilityLabel: l10n.commonTableSettingsActionLabel,
      columnVisibilityTitle: l10n.commonTableSettingsTitle,
      columnVisibilityApplyLabel: l10n.receptionApplyColumnsAction,
      columnVisibilityResetLabel: l10n.receptionResetColumnsAction,
      columnVisibilityCloseLabel: l10n.commonCloseActionLabel,
      exportLabel: l10n.commonTableExportActionLabel,
      exportDialogTitle: l10n.commonTableExportDialogTitle,
      exportCancelLabel: l10n.commonCancelActionLabel,
      exportColumnsSectionLabel: l10n.commonTableExportColumnsSectionLabel,
      exportFiltersSectionLabel: l10n.commonTableExportFiltersSectionLabel,
      exportEmptyColumnsMessage: l10n.commonTableExportEmptyColumnsMessage,
      exportEmptyRowsMessage: l10n.commonTableExportEmptyRowsMessage,
      exportSuccessMessage: l10n.commonTableExportSuccessMessage,
      exportFailureMessage: l10n.commonTableExportFailureMessage,
      enableExport: true,
      canExport: canExportPatientRegistry(policy),
      enablePrint: true,
      canPrint: canPrintPatientRegistry(policy),
      printLabel: l10n.commonPrintActionLabel,
      printFailureMessage: l10n.commonTablePrintFailureMessage,
      loadMatchingItems: () => matchingItemsOrThrow(
        ref.read(patientRegistryControllerProvider.notifier).loadMatchingPatients(),
      ),
      onPrint: (List<Patient> items) => _printPatientRegistryList(
        context,
        ref,
        items,
        section,
        l10n,
      ),
      goToTopLabel: l10n.commonGoToTopActionLabel,
      loadingMoreLabel: l10n.commonLoadingMoreLabel,
      allRowsLoadedLabel: l10n.commonAllRowsLoadedLabel,
      exportConfig: AppListTableExportConfig<Patient>(
        fileNameStem: 'patients_${section.name}',
        enableDateFilter: false,
        dateFromLabel: l10n.commonTableExportDateFromLabel,
        dateToLabel: l10n.commonTableExportDateToLabel,
      ),
      displayMode: AppListTableDisplayMode.adaptive,
      search: AppListTableSearch<Patient>(
        controller: searchController,
        semanticLabel: l10n.patientsSearchLabel,
        hintText: l10n.patientsSearchHint,
        clearLabel: l10n.opdClearFiltersAction,
        matcher: (Patient patient, String query) {
          return _matchesPatientTableSearch(
            context,
            patient,
            query,
            section: section,
          );
        },
        onClear: () {
          unawaited(
            _applyPatientFilterDraft(
              context,
              ref,
              state,
              searchController,
              _patientFilterDraftFromQuery(state.query),
            ),
          );
        },
        showAdvancedFilterButton: true,
        advancedFilterButtonLabel: l10n.commonFiltersActionLabel,
        advancedFilterTitle: l10n.commonAdvancedFiltersTitle,
        hasActiveFilters:
            _hasPatientUserAdvancedFilters(state.query, section) ||
            state.query.recordState != PatientRecordState.current,
        filterGroups: <AppSearchBarFilterGroup>[
          AppSearchBarFilterGroup(
            key: 'record_state',
            label: l10n.patientsRecordStateLabel,
            allLabel: l10n.patientsRecordStateAll,
            choices: <AppSearchBarFilterChoice>[
              AppSearchBarFilterChoice(
                value: PatientRecordState.current.queryValue,
                label: l10n.patientsRecordStateCurrent,
                icon: Icons.inventory_2_outlined,
              ),
              AppSearchBarFilterChoice(
                value: PatientRecordState.deleted.queryValue,
                label: l10n.patientsRecordStateDeleted,
                icon: Icons.delete_outline,
              ),
              AppSearchBarFilterChoice(
                value: PatientRecordState.all.queryValue,
                label: l10n.patientsRecordStateAll,
                icon: Icons.list_alt_outlined,
              ),
            ],
          ),
        ],
        filterValue: AppSearchBarFilterValue(
          options: <String, String>{
            'record_state': state.query.recordState.queryValue,
          },
        ),
        onFilterChanged: (AppSearchBarFilterValue value) {
          final String raw =
              value.option('record_state') ??
              PatientRecordState.current.queryValue;
          final PatientRecordState recordState = switch (raw) {
            'deleted' => PatientRecordState.deleted,
            'all' => PatientRecordState.all,
            _ => PatientRecordState.current,
          };
          unawaited(
            ref
                .read(patientRegistryControllerProvider.notifier)
                .applyQuery(
                  state.query.copyWith(
                    recordState: recordState,
                    clearIncludeDeleted: true,
                    pageRequest: state.query.pageRequest.copyWith(pageIndex: 0),
                  ),
                )
                .then((AppFailure? failure) async {
                  if (context.mounted) {
                    await _showFailureIfNeeded(context, failure);
                  }
                }),
          );
        },
        onAdvancedFilterPressed: () {
          unawaited(
            _openPatientAdvancedFilters(
              context,
              ref,
              state,
              searchController,
              section: section,
            ),
          );
        },
        // Filters → Settings → Export → Print → Duplicate review → Register.
        trailingActions: <AppSearchBarAction>[
          if (state.overview.duplicates.isNotEmpty &&
              patientRegistryDuplicateReviewAtom(section).isAllowed(policy))
            AppSearchBarAction(
              icon: Icons.content_copy_outlined,
              label: l10n.patientsDuplicateSummaryLabel,
              tooltip: l10n.patientsDuplicateSummaryBody,
              onPressed: () {
                unawaited(
                  _openDuplicateReviewDialog(
                    context,
                    ref,
                    state.overview.duplicates,
                  ),
                );
              },
            ),
          if (patientRegistryRegisterAtom(section).isAllowed(policy))
            AppSearchBarAction(
              icon: Icons.person_add_alt_1_outlined,
              label: l10n.patientsRegisterPatientAction,
              tooltip: l10n.patientsRegisterPatientAction,
              onPressed: () {
                unawaited(_openRegisterPatientDialog(context, ref, state));
              },
            ),
        ],
      ),
      isLoading: state.isRefreshingList || state.isSaving,
      columns: _defaultPatientColumns(context, ref, section, l10n),
      columnChoices: _optionalPatientColumns(context, ref, section, l10n),
      mobileItemBuilder: (BuildContext context, Patient patient) {
        return AppListTableMobileItem(
          title: patient.effectiveDisplayName,
          caption: patient.effectiveIdentifier,
          meta: <AppListTableMobileMeta>[
            AppListTableMobileMeta(
              label: _patientRegistryStatusLabel(
                context,
                patient,
                section,
                policy: policy,
              ),
            ),
          ],
        );
      },
      itemKeyBuilder: (Patient patient) => ValueKey<String>(patient.id),
      onRowSelected: (Patient patient) async {
        await showPatientDetailDialog(
          context,
          ref,
          patient.id,
          registrySection: section,
        );
      },
      emptyBuilder: (_) => AppWorkspaceStatePanel.empty(
        title: l10n.patientsEmptyTitle,
        body: l10n.patientsEmptyBody,
        icon: Icons.person_search_outlined,
        minHeight: 260,
      ),
      pageLabelBuilder: (AppPage<Patient> page) {
        return l10n.patientsPageLabel(
          page.firstItemNumber,
          page.lastItemNumber,
          page.totalItemCount ?? page.lastItemNumber,
        );
      },
      previousPageLabel: l10n.patientsPreviousPageLabel,
      nextPageLabel: l10n.patientsNextPageLabel,
      onPageChanged: (AppPageRequest request) async {
        final PatientListQuery baseQuery = state.query.copyWith(
          pageRequest: request,
          section: section,
        );
        final PatientListQuery filteredQuery = section.applyToQuery(baseQuery);
        final AppFailure? failure = await ref
            .read(patientRegistryControllerProvider.notifier)
            .applyQuery(filteredQuery);
        if (context.mounted) {
          await _showFailureIfNeeded(context, failure);
        }
      },
    );
  }
}

Future<void> _printPatientRegistryList(
  BuildContext context,
  WidgetRef ref,
  List<Patient> items,
  PatientRegistrySection section,
  AppLocalizations l10n,
) async {
  final List<PatientRegistryPrintColumn> printColumns =
      _patientRegistryPrintColumns(context, ref, section, l10n);
  final List<Map<String, String>> printRows = <Map<String, String>>[
    for (final Patient patient in items)
      <String, String>{
        for (final PatientRegistryPrintColumn column in printColumns)
          column.id: _patientRegistryPrintCellValue(
            context,
            ref,
            patient,
            column.id,
            section,
            l10n,
          ),
      },
  ];
  await printPatientRegistryList(
    ref: ref,
    context: context,
    title: _PatientRegistryContentState._sectionLabel(l10n, section),
    columns: printColumns,
    rows: printRows,
    emptyText: l10n.patientsEmptyTitle,
  );
}

List<PatientRegistryPrintColumn> _patientRegistryPrintColumns(
  BuildContext context,
  WidgetRef ref,
  PatientRegistrySection section,
  AppLocalizations l10n,
) {
  final List<AppListTableColumn<Patient>> available =
      <AppListTableColumn<Patient>>[
        ..._defaultPatientColumns(context, ref, section, l10n),
        ..._optionalPatientColumns(context, ref, section, l10n),
      ];
  final Set<String> seen = <String>{};
  final List<PatientRegistryPrintColumn> columns =
      <PatientRegistryPrintColumn>[];
  for (final AppListTableColumn<Patient> column in available) {
    if (!column.includesInExport) {
      continue;
    }
    final String id = column.key;
    if (!seen.add(id)) {
      continue;
    }
    columns.add(PatientRegistryPrintColumn(id: id, label: column.label));
  }
  return columns;
}

String _patientRegistryPrintCellValue(
  BuildContext context,
  WidgetRef ref,
  Patient patient,
  String columnId,
  PatientRegistrySection section,
  AppLocalizations l10n,
) {
  final Map<String, AppListTableColumn<Patient>> columns =
      _patientColumnDefinitions(context, ref, section, l10n);
  final AppListTableColumn<Patient>? column = columns[columnId];
  final AppListTableExportValue<Patient>? exportValue = column?.exportValue;
  if (exportValue != null) {
    return exportValue(patient).toString();
  }
  return '';
}

List<AppListTableColumn<Patient>> _defaultPatientColumns(
  BuildContext context,
  WidgetRef ref,
  PatientRegistrySection section,
  AppLocalizations l10n,
) {
  final AppAccessPolicy policy = ref.watch(appAccessPolicyProvider);
  final Map<String, AppListTableColumn<Patient>> columns =
      _patientColumnDefinitions(context, ref, section, l10n);
  final List<String> preferredIds = switch (section) {
    PatientRegistrySection.all => <String>[
      'patient',
      'contact',
      'alerts',
      'status',
      'next_action',
      'actions',
    ],
    PatientRegistrySection.active ||
    PatientRegistrySection.admitted ||
    PatientRegistrySection.balanceDue => <String>[
      'patient',
      'contact',
      'visit',
      'status',
      'next_action',
      'actions',
    ],
  };
  final List<String> promotionIds = switch (section) {
    PatientRegistrySection.all => <String>['visit', 'patient_number', 'age'],
    PatientRegistrySection.active ||
    PatientRegistrySection.admitted ||
    PatientRegistrySection.balanceDue => <String>[
      'alerts',
      'patient_number',
      'age',
    ],
  };

  bool isAllowed(String id) {
    if (id == 'visit' &&
        section == PatientRegistrySection.admitted &&
        !PatientAdmittedAtomPermissions.visitColumn.isAllowed(policy)) {
      return false;
    }
    return columns.containsKey(id);
  }

  final List<String> ids = preferredIds.where(isAllowed).toList(growable: true);
  // Prefer five defaults (tables.mdc); promote from choices when RBAC omits Visit.
  for (final String id in promotionIds) {
    if (ids.length >= 5) {
      break;
    }
    if (!ids.contains(id) && isAllowed(id)) {
      // Insert before always-visible trailing chrome when present.
      final int statusIndex = ids.indexOf('status');
      if (statusIndex >= 0) {
        ids.insert(statusIndex, id);
      } else {
        ids.add(id);
      }
    }
  }

  return ids.map((String id) => columns[id]!).toList(growable: false);
}

List<AppListTableColumn<Patient>> _optionalPatientColumns(
  BuildContext context,
  WidgetRef ref,
  PatientRegistrySection section,
  AppLocalizations l10n,
) {
  final AppAccessPolicy policy = ref.watch(appAccessPolicyProvider);
  final Map<String, AppListTableColumn<Patient>> columns =
      _patientColumnDefinitions(context, ref, section, l10n);
  final Set<String> defaultIds = _defaultPatientColumns(
    context,
    ref,
    section,
    l10n,
  ).map((AppListTableColumn<Patient> column) => column.key).toSet();
  final List<String> ids = switch (section) {
    PatientRegistrySection.all => <String>[
      'visit',
      'patient_number',
      'age',
      'gender',
    ],
    PatientRegistrySection.active ||
    PatientRegistrySection.admitted ||
    PatientRegistrySection.balanceDue => <String>[
      'alerts',
      'patient_number',
      'age',
      'gender',
    ],
  };
  return ids
      .where((String id) {
        if (defaultIds.contains(id)) {
          return false;
        }
        if (id == 'visit' &&
            section == PatientRegistrySection.admitted &&
            !PatientAdmittedAtomPermissions.visitColumn.isAllowed(policy)) {
          return false;
        }
        return true;
      })
      .map((String id) => columns[id]!)
      .toList(growable: false);
}

Map<String, AppListTableColumn<Patient>> _patientColumnDefinitions(
  BuildContext context,
  WidgetRef ref,
  PatientRegistrySection section,
  AppLocalizations l10n,
) {
  return <String, AppListTableColumn<Patient>>{
    'patient': AppListTableColumn<Patient>(
      id: 'patient',
      label: l10n.patientsPatientColumnLabel,
      alwaysVisible: true,
      sortComparator: (Patient left, Patient right) => appListTableCompareText(
        left.effectiveDisplayName,
        right.effectiveDisplayName,
      ),
      exportValue: (Patient patient) => patient.effectiveDisplayName,
      cellBuilder: (_, Patient patient) => Text(
        patient.effectiveDisplayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
    'contact': AppListTableColumn<Patient>(
      id: 'contact',
      label: l10n.patientsPhoneIdentifierColumnLabel,
      sortComparator: (Patient left, Patient right) => appListTableCompareText(
        left.primaryPhone ?? left.primaryEmail,
        right.primaryPhone ?? right.primaryEmail,
      ),
      exportValue: (Patient patient) =>
          patient.primaryPhone ?? patient.primaryEmail ?? '',
      cellBuilder: (_, Patient patient) =>
          _PatientContactIdentifierCell(patient: patient),
    ),
    'alerts': AppListTableColumn<Patient>(
      id: 'alerts',
      label: l10n.patientsAlertColumnLabel,
      sortComparator: (Patient left, Patient right) => appListTableCompareText(
        _patientAlertSortValue(context, left),
        _patientAlertSortValue(context, right),
      ),
      exportValue: (Patient patient) =>
          _patientAlertSortValue(context, patient),
      cellBuilder: (_, Patient patient) => _PatientAlertCell(patient: patient),
    ),
    'visit': AppListTableColumn<Patient>(
      id: 'visit',
      label: l10n.patientsVisitColumnLabel,
      sortComparator: (Patient left, Patient right) =>
          appListTableCompareDateTime(
            left.currentVisit?.occurredAt,
            right.currentVisit?.occurredAt,
          ),
      exportValue: (Patient patient) {
        final PatientVisitContext? visit = patient.currentVisit;
        if (visit == null) {
          return '';
        }
        return _visitTitleLine(visit) ??
            visit.occurredAt?.toIso8601String() ??
            '';
      },
      cellBuilder: (_, Patient patient) => _VisitContextCell(patient: patient),
    ),
    'status': AppListTableColumn<Patient>(
      id: 'status',
      label: l10n.patientsStatusColumnLabel,
      alwaysVisible: true,
      sortComparator: (Patient left, Patient right) => appListTableCompareText(
        _patientRegistryStatusLabel(context, left, section),
        _patientRegistryStatusLabel(context, right, section),
      ),
      exportValue: (Patient patient) =>
          _patientRegistryStatusLabel(context, patient, section),
      cellBuilder: (BuildContext context, Patient patient) {
        return _PatientRegistryStatusBadge(patient: patient, section: section);
      },
    ),
    'next_action': AppListTableColumn<Patient>(
      id: 'next_action',
      label: l10n.patientsNextActionColumnLabel,
      alwaysVisible: true,
      exportValue: (Patient patient) =>
          _patientNextActionLabel(l10n, patient),
      cellBuilder: (BuildContext context, Patient patient) => _NextActionCell(
        patient: patient,
        section: section,
        onCompleteRecord: () {
          unawaited(showPatientEditDialog(context, ref, patient));
        },
      ),
    ),
    'actions': AppListTableColumn<Patient>(
      id: 'actions',
      label: l10n.accessAdminColumnActions,
      alwaysVisible: true,
      exportable: false,
      cellBuilder: (BuildContext context, Patient patient) =>
          _PatientRegistryRowActions(
            patient: patient,
            section: section,
          ),
    ),
    'patient_number': AppListTableColumn<Patient>(
      id: 'patient_number',
      label: l10n.patientsPatientNumberColumnLabel,
      sortComparator: (Patient left, Patient right) => appListTableCompareText(
        left.effectiveIdentifier ?? left.publicId,
        right.effectiveIdentifier ?? right.publicId,
      ),
      exportValue: (Patient patient) =>
          patient.effectiveIdentifier ?? patient.publicId ?? '',
      cellBuilder: (_, Patient patient) => Text(
        patient.effectiveIdentifier ??
            patient.publicId ??
            l10n.profileUnknownValue,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
    'age': AppListTableColumn<Patient>(
      id: 'age',
      label: l10n.patientsAgeColumnLabel,
      sortComparator: (Patient left, Patient right) =>
          appListTableCompareDateTime(left.dateOfBirth, right.dateOfBirth),
      exportValue: (Patient patient) =>
          _patientAgeLabel(context, patient.dateOfBirth),
      cellBuilder: (BuildContext context, Patient patient) => Text(
        _patientAgeLabel(context, patient.dateOfBirth),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
    'gender': AppListTableColumn<Patient>(
      id: 'gender',
      label: l10n.patientsGenderColumnLabel,
      sortComparator: (Patient left, Patient right) =>
          appListTableCompareText(left.gender, right.gender),
      exportValue: (Patient patient) => patient.gender == null
          ? l10n.profileUnknownValue
          : _genderLabel(l10n, patient.gender!),
      cellBuilder: (BuildContext context, Patient patient) => Text(
        patient.gender == null
            ? l10n.profileUnknownValue
            : _genderLabel(l10n, patient.gender!),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  };
}

class _PatientRegistryStatusBadge extends ConsumerWidget {
  const _PatientRegistryStatusBadge({
    required this.patient,
    required this.section,
  });

  final Patient patient;
  final PatientRegistrySection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppAccessPolicy policy = ref.watch(appAccessPolicyProvider);
    return AppWorkspaceStatusBadge(
      status: _patientRegistryStatus(
        context,
        patient,
        section,
        policy: policy,
      ),
    );
  }
}

AppWorkspaceStatus _patientRegistryStatus(
  BuildContext context,
  Patient patient,
  PatientRegistrySection section, {
  AppAccessPolicy? policy,
}) {
  final AppLocalizations l10n = context.l10n;

  if (patient.isDeleted) {
    return AppWorkspaceStatus(
      label: l10n.patientsRecordStateDeleted,
      tone: AppWorkspaceStatusTone.error,
      icon: Icons.delete_outline,
    );
  }

  if (patient.requiresCompletion) {
    return AppWorkspaceStatus(
      label: l10n.patientsRegistrationIncompleteValue,
      tone: AppWorkspaceStatusTone.warning,
      icon: Icons.error_outline,
    );
  }

  final PatientVisitContext? visit = patient.currentVisit;
  final bool canShowAdmittedClinical =
      policy == null ||
      PatientAdmittedAtomPermissions.admissionStatus.isAllowed(policy);

  if (section == PatientRegistrySection.admitted &&
      canShowAdmittedClinical &&
      visit != null &&
      visit.kind == 'admission' &&
      visit.status != null) {
    return AppWorkspaceStatus(
      label: _apiLabel(visit.status!),
      tone: appTriageToneForValue(visit.status),
      icon: Icons.local_hospital_outlined,
    );
  }

  if (section == PatientRegistrySection.balanceDue && visit != null) {
    if (visit.status != null) {
      return AppWorkspaceStatus(
        label: _apiLabel(visit.status!),
        tone: AppWorkspaceStatusTone.warning,
        icon: Icons.account_balance_wallet_outlined,
      );
    }
  }

  if (!patient.isActive) {
    return AppWorkspaceStatus(
      label: l10n.patientsInactiveFilter,
      tone: AppWorkspaceStatusTone.neutral,
      icon: Icons.block_outlined,
    );
  }

  return AppWorkspaceStatus(
    label: l10n.patientsActiveFilter,
    tone: AppWorkspaceStatusTone.success,
    icon: Icons.check_circle_outline,
  );
}

String _patientRegistryStatusLabel(
  BuildContext context,
  Patient patient,
  PatientRegistrySection section, {
  AppAccessPolicy? policy,
}) {
  return _patientRegistryStatus(
    context,
    patient,
    section,
    policy: policy,
  ).label;
}

String _patientNextActionLabel(AppLocalizations l10n, Patient patient) {
  return patient.requiresCompletion
      ? l10n.patientsCompleteRecordAction
      : l10n.patientsOpenRecordAction;
}

String? _visitTitleLine(PatientVisitContext visit) {
  return visit.title?.trim().isNotEmpty == true ? visit.title!.trim() : null;
}

String _patientAlertSortValue(BuildContext context, Patient patient) {
  final AppLocalizations l10n = context.l10n;
  return _joinDisplay(<String?>[
    patient.hasAllergyAlert
        ? patient.allergyAlertLabel ?? l10n.patientsAllergyAlertLabel
        : null,
    patient.requiresCompletion
        ? l10n.patientsRegistrationIncompleteValue
        : null,
  ]);
}


Patient? _cachedPatientFromState(
  PatientRegistryState? state,
  String patientId,
) {
  if (state == null) {
    return null;
  }
  for (final Patient patient in state.page.items) {
    if (patient.id == patientId) {
      return patient;
    }
  }
  return null;
}

String _ageSexLabel(String age, String sex) => '$age / $sex';

class _PatientContactIdentifierCell extends StatelessWidget {
  const _PatientContactIdentifierCell({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String contact =
        patient.primaryPhone ??
        patient.primaryEmail ??
        l10n.profileUnknownValue;

    return Text(contact, maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}

class _PatientAlertCell extends StatelessWidget {
  const _PatientAlertCell({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final l10n = context.l10n;
    final List<Widget> alerts = <Widget>[
      if (patient.hasAllergyAlert)
        AppStatusText(
          icon: Icons.warning_amber_outlined,
          label: patient.allergyAlertLabel ?? l10n.patientsAllergyAlertLabel,
          tone: AppWorkspaceStatusTone.warning,
        ),
      if (patient.requiresCompletion)
        AppStatusText(
          icon: Icons.error_outline,
          label: l10n.patientsRegistrationIncompleteValue,
          tone: AppWorkspaceStatusTone.warning,
        ),
    ];

    if (alerts.isEmpty) {
      return Text(
        l10n.patientsNoAlertsLabel,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Wrap(
      spacing: theme.spacing.xs,
      runSpacing: theme.spacing.xs,
      children: alerts,
    );
  }
}

class _VisitContextCell extends StatelessWidget {
  const _VisitContextCell({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context) {
    final PatientVisitContext? visit = patient.currentVisit;
    final ThemeData theme = Theme.of(context);
    final l10n = context.l10n;
    if (visit == null) {
      return Text(
        l10n.patientsNoVisitLabel,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final String title = _visitTitleLine(visit) ?? '';
    if (title.isEmpty) {
      return Text(
        _formatOptionalDate(context, visit.occurredAt),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _NextActionCell extends StatelessWidget {
  const _NextActionCell({
    required this.patient,
    required this.onCompleteRecord,
    this.section = PatientRegistrySection.all,
  });

  final Patient patient;
  final VoidCallback onCompleteRecord;
  final PatientRegistrySection section;

  AccessRequirement get _completeRequirement {
    return patientRegistryNextActionCompleteAtom(section);
  }

  @override
  Widget build(BuildContext context) {
    if (patient.isDeleted) {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    // Complete records: label-only guidance — row select opens the detail.
    // Incomplete: sole next-action control opens the edit form directly.
    if (!patient.requiresCompletion) {
      return Text(
        l10n.patientsOpenRecordAction,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return AppAccessActionGate(
      requirement: _completeRequirement,
      builder: (_, bool isAllowed) {
        if (!isAllowed) {
          return Text(
            l10n.patientsCompleteRecordAction,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
        }
        // Opaque GestureDetector (same pattern as OpdBoardNextActionCell) so
        // DataRow onSelectChanged does not steal the tap.
        final Color primaryColor = theme.colorScheme.primary;
        return Semantics(
          button: true,
          enabled: true,
          label: l10n.patientsCompleteRecordAction,
          child: Tooltip(
            message: l10n.patientsCompleteRecordAction,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onCompleteRecord,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: theme.spacing.xs,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.edit_note_outlined,
                        size: 16,
                        color: primaryColor,
                      ),
                      SizedBox(width: theme.spacing.xs),
                      Flexible(
                        child: Text(
                          l10n.patientsCompleteRecordAction,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PatientRegistryRowActions extends ConsumerWidget {
  const _PatientRegistryRowActions({
    required this.patient,
    required this.section,
  });

  final Patient patient;
  final PatientRegistrySection section;

  AccessRequirement get _deleteRequirement {
    return switch (section) {
      PatientRegistrySection.all => PatientAllAtomPermissions.delete,
      PatientRegistrySection.active => PatientActiveAtomPermissions.delete,
      PatientRegistrySection.admitted => PatientAdmittedAtomPermissions.delete,
      PatientRegistrySection.balanceDue =>
        PatientBalanceDueAtomPermissions.delete,
    };
  }

  AccessRequirement get _restoreRequirement {
    return switch (section) {
      PatientRegistrySection.all => PatientAllAtomPermissions.restore,
      PatientRegistrySection.active => PatientActiveAtomPermissions.restore,
      PatientRegistrySection.admitted => PatientAdmittedAtomPermissions.restore,
      PatientRegistrySection.balanceDue =>
        PatientBalanceDueAtomPermissions.restore,
    };
  }

  AccessRequirement get _permanentDeleteRequirement {
    return switch (section) {
      PatientRegistrySection.all => PatientAllAtomPermissions.permanentDelete,
      PatientRegistrySection.active =>
        PatientActiveAtomPermissions.permanentDelete,
      PatientRegistrySection.admitted =>
        PatientAdmittedAtomPermissions.permanentDelete,
      PatientRegistrySection.balanceDue =>
        PatientBalanceDueAtomPermissions.permanentDelete,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final bool isSaving =
        (_readCurrentState(ref)?.isSaving ?? false);

    if (patient.isDeleted) {
      return Wrap(
        spacing: theme.spacing.sm,
        runSpacing: theme.spacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          AppAccessActionGate(
            requirement: _restoreRequirement,
            builder: (_, bool isAllowed) {
              if (!isAllowed) {
                return const SizedBox.shrink();
              }
              return AppButton.tertiary(
                label: l10n.patientsRestoreAction,
                leadingIcon: Icons.restore_outlined,
                semanticLabel: l10n.patientsRestoreAction,
                tooltip: l10n.patientsRestoreAction,
                isLoading: isSaving,
                onPressed: () => unawaited(
                  _confirmRestorePatient(
                    context,
                    ref,
                    patient,
                    popDetailOnSuccess: false,
                  ),
                ),
              );
            },
          ),
          AppAccessActionGate(
            requirement: _permanentDeleteRequirement,
            builder: (_, bool isAllowed) {
              if (!isAllowed) {
                return const SizedBox.shrink();
              }
              return AppButton.tertiary(
                label: l10n.patientsPermanentDeleteAction,
                leadingIcon: Icons.delete_forever_outlined,
                semanticLabel: l10n.patientsPermanentDeleteAction,
                tooltip: l10n.patientsPermanentDeleteAction,
                color: theme.colorScheme.error,
                isLoading: isSaving,
                onPressed: () => unawaited(
                  _confirmPermanentDeletePatient(
                    context,
                    ref,
                    patient,
                    popDetailOnSuccess: false,
                  ),
                ),
              );
            },
          ),
        ],
      );
    }

    return AppAccessActionGate(
      requirement: _deleteRequirement,
      builder: (_, bool isAllowed) {
        if (!isAllowed) {
          return const SizedBox.shrink();
        }
        return AppButton.tertiary(
          label: l10n.patientsDeleteAction,
          leadingIcon: Icons.delete_outline,
          color: theme.colorScheme.error,
          isLoading: isSaving,
          onPressed: () => unawaited(
            _confirmSoftDeletePatient(
              context,
              ref,
              patient,
              popDetailOnSuccess: false,
            ),
          ),
        );
      },
    );
  }
}

bool _matchesPatientTableSearch(
  BuildContext context,
  Patient patient,
  String query, {
  required PatientRegistrySection section,
}) {
  final List<String> tokens = _searchTokens(query);
  if (tokens.isEmpty) {
    return true;
  }

  final AppLocalizations l10n = context.l10n;
  final Locale locale = Localizations.localeOf(context);
  final DateTime? dateOfBirth = patient.dateOfBirth;
  final String age = _patientAgeLabel(context, dateOfBirth);
  final String gender = patient.gender == null
      ? l10n.profileUnknownValue
      : _genderLabel(l10n, patient.gender!);
  final PatientVisitContext? visit = patient.currentVisit;
  final String haystack = <String?>[
    patient.effectiveDisplayName,
    patient.displayName,
    patient.firstName,
    patient.lastName,
    patient.effectiveIdentifier,
    patient.id,
    patient.publicId,
    patient.primaryIdentifierType,
    patient.primaryIdentifierValue,
    patient.primaryPhone,
    patient.primaryEmail,
    dateOfBirth == null ? null : AppFormatters.mediumDate(dateOfBirth, locale),
    dateOfBirth?.toIso8601String(),
    age,
    gender,
    _ageSexLabel(age, gender),
    _patientRegistryStatusLabel(context, patient, section),
    _patientNextActionLabel(l10n, patient),
    patient.isActive ? l10n.patientsActiveFilter : l10n.patientsInactiveFilter,
    patient.isActive ? 'active' : 'inactive',
    patient.requiresCompletion
        ? l10n.patientsRegistrationIncompleteValue
        : null,
    patient.requiresCompletion ? 'incomplete registration emergency' : null,
    patient.registrationSource,
    patient.registrationStatus,
    patient.hasAllergyAlert ? l10n.patientsAllergyAlertLabel : null,
    patient.allergyAlertLabel,
    patient.hasAllergyAlert || patient.requiresCompletion
        ? null
        : l10n.patientsNoAlertsLabel,
    visit == null ? l10n.patientsNoVisitLabel : null,
    visit?.title,
    visit?.status,
    visit?.publicId,
    visit == null ? null : _visitTitleLine(visit),
    visit?.occurredAt == null
        ? null
        : AppFormatters.mediumDate(visit!.occurredAt!, locale),
    visit?.occurredAt?.toIso8601String(),
    patient.facilityLabel,
    patient.tenantLabel,
  ].whereType<String>().join(' ').toLowerCase();

  return tokens.every(haystack.contains);
}

List<String> _searchTokens(String query) {
  return query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((String token) => token.isNotEmpty)
      .toList(growable: false);
}

String _patientAgeLabel(BuildContext context, DateTime? dateOfBirth) {
  if (dateOfBirth == null) {
    return context.l10n.profileUnknownValue;
  }

  final DateTime today = DateTime.now();
  var years = today.year - dateOfBirth.year;
  if (today.month < dateOfBirth.month ||
      (today.month == dateOfBirth.month && today.day < dateOfBirth.day)) {
    years -= 1;
  }
  if (years > 0) {
    return years.toString();
  }

  var months = (today.year - dateOfBirth.year) * 12;
  months += today.month - dateOfBirth.month;
  if (today.day < dateOfBirth.day) {
    months -= 1;
  }
  if (months > 0) {
    return months.toString();
  }

  return today.difference(dateOfBirth).inDays.clamp(0, 30).toString();
}

Future<void> _openPatientQuickAction(
  BuildContext context,
  WidgetRef ref,
  Patient patient,
  PatientQuickAction action,
) async {
  final PatientRegistryState? state = _readCurrentState(ref);
  final PatientReferenceData referenceData =
      state?.referenceData ?? const PatientReferenceData();
  final PatientDetail? detail = state?.selectedDetail?.patient.id == patient.id
      ? state?.selectedDetail
      : null;

  Future<void> refreshIfChanged(bool? changed) async {
    if (changed == true && context.mounted) {
      await _refreshPatientAfterQuickAction(context, ref, patient.id);
    }
  }

  switch (action) {
    case PatientQuickAction.opdActions:
      // Queue-only work has no open visit yet; fall back to the start flow so
      // the Quick action still lands somewhere useful.
      if (isActiveOpdPatientVisit(patient.currentVisit)) {
        await _openActiveOpdActions(context, ref, patient);
      } else {
        await openPatientOpdEncounterFlow(
          context,
          ref,
          patient,
          onSaved: () =>
              _refreshPatientAfterQuickAction(context, ref, patient.id),
        );
      }
    case PatientQuickAction.labOrder:
      await refreshIfChanged(
        await openPatientLabOrderDialog(
          context,
          ref,
          patient,
          encounterId: patient.currentVisit?.publicId,
        ),
      );
    case PatientQuickAction.radiologyOrder:
      await refreshIfChanged(
        await openPatientRadiologyOrderDialog(
          context,
          ref,
          patient,
          encounterId: patient.currentVisit?.publicId,
        ),
      );
    case PatientQuickAction.theaterSchedule:
      await refreshIfChanged(
        await openPatientTheaterScheduleDialog(
          context,
          ref,
          patient,
          encounterId: patient.currentVisit?.publicId,
        ),
      );
    case PatientQuickAction.physiotherapy:
      if (detail == null) {
        return;
      }
      await refreshIfChanged(
        await openPatientPhysiotherapyRequestDialog(context, ref, detail),
      );
    case PatientQuickAction.enrollInsurance:
      final Result<ClaimsReferenceData> lookups = await ref
          .read(claimsRepositoryProvider)
          .loadReferenceData();
      if (!context.mounted) {
        return;
      }
      final ClaimsReferenceData? referenceData = lookups.when(
        success: (ClaimsReferenceData value) => value,
        failure: (_) => null,
      );
      if (referenceData == null) {
        return;
      }
      await openClaimsEnrollmentDialog(
        context: context,
        ref: ref,
        referenceData: referenceData,
        patientId: patient.publicId ?? patient.id,
      );
      if (context.mounted) {
        await _refreshPatientAfterQuickAction(context, ref, patient.id);
      }
    case PatientQuickAction.opdCheckIn:
      await openPatientOpdEncounterFlow(
        context,
        ref,
        patient,
        onSaved: () =>
            _refreshPatientAfterQuickAction(context, ref, patient.id),
      );
    case PatientQuickAction.discharge:
      if (detail == null) {
        return;
      }
      await refreshIfChanged(
        await openPatientDischargePlanningDialog(
          context: context,
          ref: ref,
          detail: detail,
          actionLabel: _patientDischargeActionLabel(context.l10n, detail),
          onFailure: (AppFailure failure) =>
              _showFailureIfNeeded(context, failure),
        ),
      );
    case PatientQuickAction.appointment:
      await refreshIfChanged(
        await showPatientAppointmentQuickDialog(
          context: context,
          patient: patient,
          referenceData: referenceData,
        ),
      );
    case PatientQuickAction.admission:
      await refreshIfChanged(
        await showPatientAdmissionQuickDialog(
          context,
          patient: patient,
          referenceData: referenceData,
        ),
      );
    case PatientQuickAction.report:
      await refreshIfChanged(
        await showAppDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _PatientReportPrintPreviewDialog(
            detail: detail,
            patient: patient,
          ),
        ),
      );
  }
}

Future<void> _refreshPatientAfterQuickAction(
  BuildContext context,
  WidgetRef ref,
  String patientId,
) async {
  await ref
      .read(patientRegistryControllerProvider.notifier)
      .selectPatient(patientId);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.patientsQuickActionSavedMessage)),
    );
  }
}

Future<void> _continuePatientActiveWork(
  BuildContext context,
  WidgetRef ref,
  PatientDetail detail,
  PatientActiveWorkItem item,
) async {
  final Patient patient = detail.patient;
  switch (item.kind) {
    case PatientActiveWorkKind.appointment:
      await _continuePatientAppointment(context, ref, detail, item);
    case PatientActiveWorkKind.encounter:
    case PatientActiveWorkKind.queue:
      if (isActiveOpdPatientVisit(patient.currentVisit)) {
        await _openActiveOpdActions(context, ref, patient);
      } else {
        await _openPatientQuickAction(
          context,
          ref,
          patient,
          PatientQuickAction.opdCheckIn,
        );
      }
    case PatientActiveWorkKind.admission:
      await _openPatientQuickAction(
        context,
        ref,
        patient,
        isPendingPatientAdmissionRequest(item.status)
            ? PatientQuickAction.admission
            : PatientQuickAction.discharge,
      );
    case PatientActiveWorkKind.labOrder:
    case PatientActiveWorkKind.radiologyOrder:
    case PatientActiveWorkKind.theater:
    case PatientActiveWorkKind.therapy:
      _navigateToPatientDepartmentWork(context, patient, item);
  }
}

Future<void> _continuePatientAppointment(
  BuildContext context,
  WidgetRef ref,
  PatientDetail detail,
  PatientActiveWorkItem item,
) async {
  final Patient patient = detail.patient;
  final OpdAppointment appointment = OpdAppointment(
    id: item.id,
    status: item.status,
    scheduledStart: item.occurredAt,
    reason: item.title,
    patientId: patient.publicId ?? patient.id,
    patientDisplayName: patient.effectiveDisplayName,
    patientIdentifier: patient.effectiveIdentifier,
    patientPhone: patient.primaryPhone,
    patientDateOfBirth: patient.dateOfBirth,
    patientGender: patient.gender,
    facilityId: patient.facilityId,
    tenantId: patient.tenantId,
  );
  final bool? changed = await showOpdAppointmentActionsDialog(
    context: context,
    appointment: appointment,
  );
  if (changed == true && context.mounted) {
    await _refreshPatientAfterQuickAction(context, ref, patient.id);
  }
}

void _navigateToPatientDepartmentWork(
  BuildContext context,
  Patient patient,
  PatientActiveWorkItem item,
) {
  final String encounterId = (patient.currentVisit?.publicId ?? '').trim();
  final String workId = item.id.trim();
  final Map<String, String> queryParameters = <String, String>{
    if (encounterId.isNotEmpty) 'encounterId': encounterId,
    if (workId.isNotEmpty) 'id': workId,
  };
  final String location = switch (item.kind) {
    PatientActiveWorkKind.radiologyOrder => AppRoutes.radiology.location(
      queryParameters: queryParameters,
    ),
    PatientActiveWorkKind.theater => AppRoutes.theater.location(
      queryParameters: queryParameters,
    ),
    PatientActiveWorkKind.therapy => AppRoutes.physiotherapy.location(
      queryParameters: queryParameters,
    ),
    _ => AppRoutes.lab.location(queryParameters: queryParameters),
  };
  context.go(location);
}

String _patientDischargeActionLabel(
  AppLocalizations l10n,
  PatientDetail detail,
) {
  final PatientSummaryRecord? activeAdmission = _activeAdmissionRecord(
    detail.workspace.admissions,
  );
  final PatientVisitContext? activeAdmissionVisit = _activeAdmissionVisit(
    detail.patient.currentVisit,
  );
  return clinicalDispositionActionLabel(
    l10n,
    sourceQueue: 'IPD',
    status: activeAdmission?.status ?? activeAdmissionVisit?.status,
    stage: activeAdmission?.status ?? activeAdmissionVisit?.status,
    location: activeAdmission?.subtitle ?? activeAdmissionVisit?.title,
    hasAdmission: activeAdmission != null || activeAdmissionVisit != null,
  );
}

PatientSummaryRecord? _activeAdmissionRecord(
  Iterable<PatientSummaryRecord> admissions,
) {
  for (final PatientSummaryRecord admission in admissions) {
    if (admission.id.trim().isNotEmpty &&
        _isActiveAdmissionStatus(admission.status)) {
      return admission;
    }
  }
  return null;
}

PatientVisitContext? _activeAdmissionVisit(PatientVisitContext? visit) {
  return _isActiveAdmissionVisit(visit) ? visit : null;
}

bool _isActiveAdmissionVisit(PatientVisitContext? visit) {
  return visit?.kind == 'admission' &&
      (visit?.publicId ?? '').trim().isNotEmpty &&
      _isActiveAdmissionStatus(visit?.status);
}

bool _isActiveAdmissionStatus(String? status) {
  return switch ((status ?? '').trim().toUpperCase()) {
    'REQUESTED' ||
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

Future<void> _openActiveOpdActions(
  BuildContext context,
  WidgetRef ref,
  Patient patient,
) async {
  final String? encounterId = patient.currentVisit?.publicId;
  if (encounterId == null || encounterId.trim().isEmpty) {
    return;
  }
  final Result<OpdFlowDetail> result = await ref
      .read(opdRepositoryProvider)
      .getOpdFlow(encounterId.trim());
  if (!context.mounted) {
    return;
  }
  final OpdFlowDetail? detail = result.when(
    success: (OpdFlowDetail value) => value,
    failure: (AppFailure failure) {
      _showFailureIfNeeded(context, failure);
      return null;
    },
  );
  if (detail == null || !context.mounted) {
    return;
  }

  // Skip the empty Flow Actions shell — run the stage mutation (or handoff)
  // directly, matching OPD / reception next-action.
  final OpdBoardNextActionKind kind = opdBoardNextActionKindForFlow(
    detail.summary,
    detail: detail,
  );
  bool? changed;
  if (kind != OpdBoardNextActionKind.none) {
    changed = await runOpdBoardNextAction(
      context: context,
      ref: ref,
      flow: detail.summary,
      kind: kind,
      detail: detail,
    );
  } else {
    changed = await showFlowActionsDialog(
      context: context,
      flow: detail.summary,
    );
  }
  if (changed == true && context.mounted) {
    await ref
        .read(patientRegistryControllerProvider.notifier)
        .selectPatient(patient.id);
  }
}

Future<bool?> showPatientTriageQuickDialog({
  required BuildContext context,
  required Patient patient,
  required PatientReferenceData referenceData,
}) {
  return showAppTriageActionDialog<bool>(
    context: context,
    builder: (_) => PatientTriageQuickDialog(
      patient: patient,
      referenceData: referenceData,
    ),
  );
}

class PatientTriageQuickDialog extends ConsumerStatefulWidget {
  const PatientTriageQuickDialog({
    required this.patient,
    required this.referenceData,
    super.key,
  });

  final Patient patient;
  final PatientReferenceData referenceData;

  @override
  ConsumerState<PatientTriageQuickDialog> createState() =>
      _PatientTriageQuickDialogState();
}

class _PatientTriageQuickDialogState
    extends ConsumerState<PatientTriageQuickDialog> {
  static const IconData _dialogIcon = Icons.monitor_heart_outlined;

  String? _facilityId;
  String? _providerId;
  List<OpdProviderOption> _providers = const <OpdProviderOption>[];
  bool _isLoadingProviders = false;
  AppFailure? _providerFailure;

  @override
  void initState() {
    super.initState();
    _facilityId = widget.patient.facilityId;
    unawaited(_loadProviders());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppTriageActionDialog(
      title: l10n.patientsTriageDialogTitle,
      icon: const Icon(_dialogIcon),
      submitLabel: l10n.patientsSaveTriageAction,
      requiredMessage: l10n.validationRequired,
      prioritySectionTitle: l10n.patientsTriagePrioritySectionTitle,
      severityLabel: l10n.patientsEmergencySeverityLabel,
      severityOptions: _statusTriageOptions(_emergencySeverityOptions),
      initialSeverity: 'HIGH',
      triageLevelLabel: l10n.patientsTriageLevelLabel,
      triageLevelRequired: false,
      triageLevelOptions: _statusTriageOptions(_triageLevelOptions),
      chiefComplaintLabel: l10n.patientsChiefComplaintLabel,
      chiefComplaintRequired: true,
      notesSectionTitle: l10n.patientsNotesSectionTitle,
      notesLabel: l10n.patientsNotesLabel,
      vitalsSectionTitle: l10n.patientsVitalsSectionTitle,
      vitalsReference: AppVitalsReference.fromPatientData(
        dateOfBirth: widget.patient.dateOfBirth,
        gender: widget.patient.gender,
      ),
      requireVitals: true,
      vitalsRequiredMessage: l10n.patientsVitalsRequiredMessage,
      bloodPressureLabel: l10n.patientsBloodPressureLabel,
      temperatureLabel: l10n.patientsTemperatureLabel,
      systolicLabel: l10n.patientsSystolicLabel,
      diastolicLabel: l10n.patientsDiastolicLabel,
      heartRateLabel: l10n.patientsHeartRateLabel,
      respiratoryRateLabel: l10n.patientsRespiratoryRateLabel,
      oxygenSaturationLabel: l10n.patientsOxygenSaturationLabel,
      weightLabel: l10n.patientsWeightLabel,
      heightLabel: l10n.patientsHeightLabel,
      unitLabel: l10n.patientsVitalUnitLabel,
      failureBodyBuilder: _workflowFailureMessage,
      formStatusSectionsBuilder: _workflowFailureSections,
      leadingSectionsBuilder: _workflowFields,
      isBusy: _isLoadingProviders,
      onSubmit: _submitTriage,
    );
  }

  List<Widget> _workflowFailureSections(BuildContext context) {
    if (_providerFailure == null) {
      return const <Widget>[];
    }

    return <Widget>[
      AppFormInformationBanner.failure(
        context: context,
        failure: _providerFailure!,
        message: _workflowFailureMessage(context, _providerFailure!),
      ),
    ];
  }

  List<Widget> _workflowFields(BuildContext context, bool enabled) {
    final l10n = context.l10n;
    return <Widget>[
      AppFormSection(
        title: l10n.patientsWorkflowSectionTitle,
        density: AppFormSectionDensity.compact,
        children: <Widget>[
          if (widget.referenceData.facilities.length > 1)
            _facilitySelect(context, enabled),
          _providerSelect(context, enabled),
        ],
      ),
    ];
  }

  Widget _facilitySelect(BuildContext context, bool enabled) {
    return PatientFacilitySelectField(
      facilities: widget.referenceData.facilities,
      value: _facilityId,
      labelText: context.l10n.patientsFacilityLabel,
      enabled: enabled,
      onChanged: (String? value) => setState(() => _facilityId = value),
    );
  }

  Widget _providerSelect(BuildContext context, bool enabled) {
    return AppSelectField<String>.searchable(
      value: _providerId,
      labelText: context.l10n.patientsProviderLabel,
      helperText: context.l10n.patientsProviderOptionalHelper,
      enabled: enabled,
      isLoading: _isLoadingProviders,
      onChanged: (String? value) => setState(() => _providerId = value),
      options: _providerSelectOptions(_providers),
    );
  }

  Future<void> _loadProviders() async {
    setState(() => _isLoadingProviders = true);
    final Result<List<OpdProviderOption>> result = await ref
        .read(opdEncounterDialogControllerProvider)
        .listProviders();
    if (!mounted) {
      return;
    }
    result.when(
      success: (List<OpdProviderOption> providers) {
        setState(() {
          _providers = dedupeOpdProviderOptions(providers);
          _providerFailure = null;
          _isLoadingProviders = false;
        });
      },
      failure: (AppFailure failure) {
        setState(() {
          _providerFailure = failure;
          _isLoadingProviders = false;
        });
      },
    );
  }

  Future<AppFailure?> _submitTriage(AppTriageActionInput input) async {
    final List<Map<String, Object?>> vitals = _vitalPayload(input.vitals);
    if (vitals.isEmpty) {
      return AppFailure.validation(validationFields: const <String>{'vitals'});
    }

    final OpdWorkspaceController opdController = ref.read(
      opdWorkspaceControllerProvider.notifier,
    );

    // Persist through the OPD controller so flows/triage queues patch on success.
    final Result<OpdFlowDetail> flowResult = await opdController
        .submitOpdEncounter(
          _baseFlowPayload(input, <String, Object?>{
            'arrival_mode': 'EMERGENCY',
            'emergency': _emergencyPayload(input),
            'initial_stage': 'WAITING_VITALS',
            'notes': input.chiefComplaint,
            'require_consultation_payment': false,
            'create_consultation_invoice': false,
          }),
        );
    final OpdFlowDetail? flow = _successOrNull(flowResult);
    if (flow == null) {
      return _failureOrNull(flowResult);
    }

    final AppFailure? vitalsFailure = await opdController.recordVitals(
      flow.summary,
      _withoutEmptyPayload(<String, Object?>{
        'vitals': vitals,
        'triage_level': input.triageLevel,
        'triage_priority': input.triageLevel,
        'chief_complaint': input.chiefComplaint,
        'emergency': true,
        'triage_notes': input.notes,
      }),
    );
    if (vitalsFailure != null) {
      return vitalsFailure;
    }

    if (_providerId == null) {
      return null;
    }

    return opdController.assignDoctor(flow.summary, _providerId!);
  }

  Map<String, Object?> _baseFlowPayload(
    AppTriageActionInput input,
    Map<String, Object?> extra,
  ) {
    return _withoutEmptyPayload(<String, Object?>{
      'tenant_id': widget.patient.tenantId,
      'facility_id': _facilityId,
      'patient_id': widget.patient.id,
      'provider_user_id': _providerId,
      'queued_at': DateTime.now().toUtc().toIso8601String(),
      'reuse_open_encounter': true,
      'notes': input.notes,
      ...extra,
    });
  }

  Map<String, Object?> _emergencyPayload(AppTriageActionInput input) {
    return _withoutEmptyPayload(<String, Object?>{
      'severity': input.severity,
      'triage_level': input.triageLevel,
      'notes': input.notes,
    });
  }

  List<Map<String, Object?>> _vitalPayload(AppTriageVitalsInput? input) {
    if (input == null) {
      return const <Map<String, Object?>>[];
    }
    final List<Map<String, Object?>> vitals = <Map<String, Object?>>[];
    final String now = DateTime.now().toUtc().toIso8601String();
    final String systolic = _bloodPressurePayloadValue(
      input.systolic,
      input.bloodPressureUnit,
    );
    final String diastolic = _bloodPressurePayloadValue(
      input.diastolic,
      input.bloodPressureUnit,
    );
    if (systolic.isNotEmpty && diastolic.isNotEmpty) {
      vitals.add(<String, Object?>{
        'vital_type': 'BLOOD_PRESSURE',
        'systolic_value': systolic,
        'diastolic_value': diastolic,
        'unit': AppVitalsUnits.bloodPressureMmHg,
        'recorded_at': now,
      });
    }
    if (input.temperature.trim().isNotEmpty) {
      vitals.add(<String, Object?>{
        'vital_type': 'TEMPERATURE',
        'value': normalizeCurrencyAmount(input.temperature),
        'unit': input.temperatureUnit,
        'recorded_at': now,
      });
    }
    if (input.heartRate.trim().isNotEmpty) {
      vitals.add(<String, Object?>{
        'vital_type': 'HEART_RATE',
        'value': input.heartRate.trim(),
        'unit': 'BPM',
        'recorded_at': now,
      });
    }
    if (input.respiratoryRate.trim().isNotEmpty) {
      vitals.add(<String, Object?>{
        'vital_type': 'RESPIRATORY_RATE',
        'value': input.respiratoryRate.trim(),
        'unit': 'BREATHS_PER_MIN',
        'recorded_at': now,
      });
    }
    if (input.oxygenSaturation.trim().isNotEmpty) {
      vitals.add(<String, Object?>{
        'vital_type': 'OXYGEN_SATURATION',
        'value': input.oxygenSaturation.trim(),
        'unit': 'PERCENT',
        'recorded_at': now,
      });
    }
    if (input.weight.trim().isNotEmpty) {
      vitals.add(<String, Object?>{
        'vital_type': 'WEIGHT',
        'value': normalizeCurrencyAmount(input.weight),
        'unit': input.weightUnit,
        'recorded_at': now,
      });
    }
    if (input.height.trim().isNotEmpty) {
      vitals.add(<String, Object?>{
        'vital_type': 'HEIGHT',
        'value': normalizeCurrencyAmount(input.height),
        'unit': input.heightUnit,
        'recorded_at': now,
      });
    }
    return vitals;
  }

  String _bloodPressurePayloadValue(String value, String unit) {
    final double? parsed = parseAppVitalInput(value);
    if (parsed == null) {
      return '';
    }

    final double mmHg = unit == AppVitalsUnits.bloodPressureKpa
        ? parsed / AppVitalsUnits.bloodPressureKpaFactor
        : parsed;
    return formatAppVitalNumber(mmHg, decimals: 2);
  }
}

class _PatientReportPrintPreviewDialog extends ConsumerStatefulWidget {
  const _PatientReportPrintPreviewDialog({required this.patient, this.detail});

  final Patient patient;
  final PatientDetail? detail;

  @override
  ConsumerState<_PatientReportPrintPreviewDialog> createState() =>
      _PatientReportPrintPreviewDialogState();
}

class _PatientReportPrintPreviewDialogState
    extends ConsumerState<_PatientReportPrintPreviewDialog> {
  late final DateTime _generatedAt;
  _PatientReportPeriodMode _periodMode = _PatientReportPeriodMode.allDates;
  DateTime? _singleDate;
  DateTime? _startDate;
  DateTime? _endDate;
  late Set<Object> _selectedSections;
  bool _facilityTouched = false;
  bool _isPrinting = false;
  AppPrintPreviewPaneMode _paneMode = AppPrintPreviewPaneMode.split;
  double _scale = 1;
  int _currentPage = 1;
  bool _didAutoFitPreview = false;

  /// Keeps every available facility-header field selected until the user edits
  /// the facility checkboxes, so facility details that load after the dialog
  /// opened are still included by default.
  Set<Object> _effectiveSelection(
    List<ReportSectionAvailability> availabilities,
  ) {
    if (_facilityTouched) {
      return sanitizeReportSectionSelection(
        selectedIds: _selectedSections,
        sections: availabilities,
      );
    }
    final Set<Object> facilityDefaults = <Object>{
      for (final ReportSectionAvailability section in availabilities)
        if (section.id is PrintFacilitySection && section.enabled) section.id,
    };
    return sanitizeReportSectionSelection(
      selectedIds: <Object>{..._selectedSections, ...facilityDefaults},
      sections: availabilities,
    );
  }

  @override
  void initState() {
    super.initState();
    _generatedAt = DateTime.now();
    final PatientDetail initialDetail = _effectivePatientDetail(
      widget.patient,
      widget.detail,
    );
    final _PatientReportSelection initialSelection = _PatientReportSelection(
      periodMode: _periodMode,
      singleDate: _singleDate,
      startDate: _startDate,
      endDate: _endDate,
      sections: const <_PatientReportSection>{},
    );
    final PrintFormTemplateContext branding = ref.read(
      printFormTemplateContextProvider,
    );
    _selectedSections = resolveDefaultReportSectionSelection(
      _patientReportAvailabilities(
        initialDetail,
        initialSelection,
        branding: branding,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final PatientDetail? liveDetail = _livePatientDetail(
      ref,
      widget.patient.id,
    );
    final PatientDetail effectiveDetail =
        liveDetail ?? _effectivePatientDetail(widget.patient, widget.detail);
    final PrintFormTemplateContext branding = ref.watch(
      printFormTemplateContextProvider,
    );
    final List<ReportSectionAvailability> availabilities =
        _patientReportAvailabilities(
          effectiveDetail,
          _PatientReportSelection(
            periodMode: _periodMode,
            singleDate: _singleDate,
            startDate: _startDate,
            endDate: _endDate,
            sections: const <_PatientReportSection>{},
          ),
          branding: branding,
        );
    final Set<Object> selected = _effectiveSelection(availabilities);
    final PrintFormBrandingOptions brandingOptions =
        brandingOptionsFromFacilitySections(selected);
    final _PatientReportSelection selection = _PatientReportSelection(
      periodMode: _periodMode,
      singleDate: _singleDate,
      startDate: _startDate,
      endDate: _endDate,
      sections: Set<_PatientReportSection>.unmodifiable(
        selected.whereType<_PatientReportSection>(),
      ),
    );
    final _PatientReportDocument document = _buildPatientReportDocument(
      context,
      detail: effectiveDetail,
      selection: selection,
      generatedAt: _generatedAt,
    );
    final bool periodIsValid = _periodRangeIsValid;
    final bool canPrint = periodIsValid && selection.sections.isNotEmpty;
    final String documentHtml = PrintDocumentTemplates.buildDocumentHtml(
      kind: PrintDocumentTemplateKind.patientChart,
      ref: ref,
      context: context,
      title: document.title,
      subtitle: document.periodLabel,
      brandingOptions: brandingOptions,
      patientContext: buildPrintFormPatientContext(
        l10n,
        patientName: document.patientName,
        patientId: document.patientIdentifier,
        patientNameLabel: l10n.labReportPatientLabel,
        patientIdLabel: l10n.patientsIdentifierLabel,
      ),
      pages: _patientReportPrintPages(document),
      includeSignatures: true,
    );

    return AppDialog(
      title: Text(l10n.patientsReportPreviewDialogTitle),
      icon: const Icon(Icons.preview_outlined),
      scrollable: false,
      pinActionsToBottom: true,
      stackActionsWhenCompact: false,
      contentPadding: EdgeInsets.zero,
      maxWidth: 1120,
      closeEnabled: !_isPrinting,
      content: AppPrintPreviewWorkspace(
        paneMode: _paneMode,
        paneModeEnabled: !_isPrinting,
        onPaneModeChanged: (AppPrintPreviewPaneMode next) {
          setState(() => _paneMode = next);
        },
        onPreviewPaneWidth: (double width) {
          if (_didAutoFitPreview || !width.isFinite || width <= 0) {
            return;
          }
          _didAutoFitPreview = true;
          final double next = AppPrintPreviewZoom.fitPage(width);
          if ((next - _scale).abs() < 0.01) {
            return;
          }
          setState(() => _scale = next);
        },
        toolbar: AppPrintPreviewToolbar(
          scale: _scale,
          enabled: !_isPrinting,
          currentPage: AppPrintPreviewPages.clampPage(
            _currentPage,
            AppPrintPreviewPages.countFromHtml(documentHtml),
          ),
          pageCount: AppPrintPreviewPages.countFromHtml(documentHtml),
          onZoomIn: () {
            setState(() => _scale = AppPrintPreviewZoom.zoomIn(_scale));
          },
          onZoomOut: () {
            setState(() => _scale = AppPrintPreviewZoom.zoomOut(_scale));
          },
          onZoomIncrease: () {
            setState(() => _scale = AppPrintPreviewZoom.increase(_scale));
          },
          onZoomDecrease: () {
            setState(() => _scale = AppPrintPreviewZoom.decrease(_scale));
          },
          onFitPage: () {
            setState(() {
              _scale = AppPrintPreviewZoom.fitPage(
                1120 * 0.55 - theme.spacing.lg * 2,
              );
            });
          },
          onPagePrevious: () {
            final int pageCount = AppPrintPreviewPages.countFromHtml(
              documentHtml,
            );
            setState(() {
              _currentPage = AppPrintPreviewPages.clampPage(
                _currentPage - 1,
                pageCount,
              );
            });
          },
          onPageNext: () {
            final int pageCount = AppPrintPreviewPages.countFromHtml(
              documentHtml,
            );
            setState(() {
              _currentPage = AppPrintPreviewPages.clampPage(
                _currentPage + 1,
                pageCount,
              );
            });
          },
        ),
        sectionPicker: _PatientReportPreviewControls(
          selection: selection,
          selectedIds: selected,
          availabilities: availabilities,
          periodIsValid: periodIsValid,
          onPeriodModeChanged: (_PatientReportPeriodMode? value) {
            setState(() {
              _periodMode = value ?? _PatientReportPeriodMode.allDates;
              _currentPage = 1;
              _resyncSelection(effectiveDetail);
            });
          },
          onSingleDateChanged: (DateTime? value) {
            setState(() {
              _singleDate = value;
              _currentPage = 1;
              _resyncSelection(effectiveDetail);
            });
          },
          onStartDateChanged: (DateTime? value) {
            setState(() {
              _startDate = value;
              _currentPage = 1;
              _resyncSelection(effectiveDetail);
            });
          },
          onEndDateChanged: (DateTime? value) {
            setState(() {
              _endDate = value;
              _currentPage = 1;
              _resyncSelection(effectiveDetail);
            });
          },
          onSelectionChanged: (Set<Object> next) {
            setState(() {
              _selectedSections = sanitizeReportSectionSelection(
                selectedIds: next,
                sections: availabilities,
              );
              _facilityTouched = true;
              _currentPage = 1;
            });
          },
        ),
        preview: AppPrintPreviewPanel(
          html: documentHtml,
          scale: _scale,
          toolbarEnabled: false,
          focusedPage: AppPrintPreviewPages.clampPage(
            _currentPage,
            AppPrintPreviewPages.countFromHtml(documentHtml),
          ),
          currentPage: AppPrintPreviewPages.clampPage(
            _currentPage,
            AppPrintPreviewPages.countFromHtml(documentHtml),
          ),
          pageCount: AppPrintPreviewPages.countFromHtml(documentHtml),
          fallbackChild: _PatientReportPreviewPages(document: document),
        ),
      ),
      actions: <Widget>[
        AppButton.tertiary(
          label: l10n.commonCloseActionLabel,
          enabled: !_isPrinting,
          onPressed: _isPrinting
              ? null
              : () => Navigator.of(context).maybePop(false),
        ),
        AppReportActionButton.print(
          label: l10n.commonPrintActionLabel,
          enabled: canPrint && !_isPrinting,
          isLoading: _isPrinting,
          onPressed: canPrint && !_isPrinting
              ? () =>
                    _printDocument(context, document, selection, brandingOptions)
              : null,
        ),
      ],
    );
  }

  Future<void> _printDocument(
    BuildContext context,
    _PatientReportDocument document,
    _PatientReportSelection selection,
    PrintFormBrandingOptions brandingOptions,
  ) async {
    final l10n = context.l10n;
    setState(() => _isPrinting = true);
    try {
      await ref
          .read(patientRepositoryProvider)
          .recordPatientReportPrintEvent(
            patientId: widget.patient.id,
            sections: selection.sections
                .map(_patientReportSectionApiId)
                .toList(growable: false),
          );
      if (!context.mounted) {
        return;
      }
      await PrintDocumentTemplates.patientChart(
        ref: ref,
        context: context,
        title: document.title,
        subtitle: document.periodLabel,
        brandingOptions: brandingOptions,
        patientContext: buildPrintFormPatientContext(
          l10n,
          patientName: document.patientName,
          patientId: document.patientIdentifier,
          patientNameLabel: l10n.labReportPatientLabel,
          patientIdLabel: l10n.patientsIdentifierLabel,
        ),
        pages: _patientReportPrintPages(document),
        includeSignatures: true,
        showPreview: false,
      );
    } finally {
      if (mounted) {
        setState(() => _isPrinting = false);
      }
    }
  }

  bool get _periodRangeIsValid {
    if (_periodMode != _PatientReportPeriodMode.dateRange ||
        _startDate == null ||
        _endDate == null) {
      return true;
    }
    return !_dateOnly(_startDate!).isAfter(_dateOnly(_endDate!));
  }

  void _resyncSelection(PatientDetail detail) {
    final PrintFormTemplateContext branding = ref.read(
      printFormTemplateContextProvider,
    );
    final _PatientReportSelection draft = _PatientReportSelection(
      periodMode: _periodMode,
      singleDate: _singleDate,
      startDate: _startDate,
      endDate: _endDate,
      sections: Set<_PatientReportSection>.unmodifiable(
        _selectedSections.whereType<_PatientReportSection>(),
      ),
    );
    _selectedSections = sanitizeReportSectionSelection(
      selectedIds: _selectedSections,
      sections: _patientReportAvailabilities(detail, draft, branding: branding),
    );
  }
}

class _PatientReportPreviewControls extends StatelessWidget {
  const _PatientReportPreviewControls({
    required this.selection,
    required this.selectedIds,
    required this.availabilities,
    required this.periodIsValid,
    required this.onPeriodModeChanged,
    required this.onSingleDateChanged,
    required this.onStartDateChanged,
    required this.onEndDateChanged,
    required this.onSelectionChanged,
  });

  final _PatientReportSelection selection;
  final Set<Object> selectedIds;
  final List<ReportSectionAvailability> availabilities;
  final bool periodIsValid;
  final ValueChanged<_PatientReportPeriodMode?> onPeriodModeChanged;
  final ValueChanged<DateTime?> onSingleDateChanged;
  final ValueChanged<DateTime?> onStartDateChanged;
  final ValueChanged<DateTime?> onEndDateChanged;
  final ValueChanged<Set<Object>> onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final l10n = context.l10n;
    final List<AppReportSectionData> tiles = buildReportSectionTiles(
      sections: availabilities,
      titleFor: (Object id) => _patientReportSectionLabel(l10n, id),
      iconFor: (Object id) => _patientReportSectionIcon(id),
      emptyDisabledReason: l10n.reportSectionEmptyDisabledReason,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppFormSection(
          title: l10n.patientsReportPeriodLabel,
          density: AppFormSectionDensity.compact,
          children: <Widget>[
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                if (constraints.maxWidth < 720) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _periodModeField(context),
                      if (_dateFieldForMode(context)
                          case final Widget field) ...<Widget>[
                        SizedBox(height: theme.spacing.sm),
                        field,
                      ],
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(width: 240, child: _periodModeField(context)),
                    SizedBox(width: theme.spacing.sm),
                    Expanded(
                      child:
                          _dateFieldForMode(context) ?? const SizedBox.shrink(),
                    ),
                  ],
                );
              },
            ),
            if (!periodIsValid)
              Text(
                l10n.patientsReportDateRangeInvalidMessage,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: AppFontWeight.emphasis,
                ),
              ),
          ],
        ),
        SizedBox(height: theme.spacing.lg),
        AppFormSection(
          title: l10n.patientsReportSectionsLabel,
          density: AppFormSectionDensity.compact,
          children: <Widget>[
            AppReportSectionPicker(
              sections: tiles,
              selectedIds: selectedIds,
              onSelectionChanged: onSelectionChanged,
            ),
          ],
        ),
      ],
    );
  }

  Widget _periodModeField(BuildContext context) {
    final l10n = context.l10n;
    return AppSelectField<_PatientReportPeriodMode>(
      value: selection.periodMode,
      labelText: l10n.patientsReportPeriodLabel,
      options: <AppSelectOption<_PatientReportPeriodMode>>[
        for (final _PatientReportPeriodMode value
            in _PatientReportPeriodMode.values)
          AppSelectOption<_PatientReportPeriodMode>(
            value: value,
            label: _patientReportPeriodModeLabel(l10n, value),
          ),
      ],
      onChanged: onPeriodModeChanged,
    );
  }

  Widget? _dateFieldForMode(BuildContext context) {
    final l10n = context.l10n;
    final DateTime now = DateTime.now();
    final DateTime firstDate = DateTime(1900);
    final DateTime lastDate = DateTime(now.year + 1, 12, 31);

    return switch (selection.periodMode) {
      _PatientReportPeriodMode.allDates => null,
      _PatientReportPeriodMode.singleDate => PatientDateField(
        value: selection.singleDate,
        firstDate: firstDate,
        lastDate: lastDate,
        currentDate: now,
        initialPickerDate: selection.singleDate ?? now,
        labelText: l10n.patientsReportDateLabel,
        onChanged: onSingleDateChanged,
      ),
      _PatientReportPeriodMode.dateRange => AppResponsiveFieldRow.two(
        left: PatientDateField(
          value: selection.startDate,
          firstDate: firstDate,
          lastDate: lastDate,
          currentDate: now,
          initialPickerDate: selection.startDate ?? now,
          labelText: l10n.patientsReportStartDateLabel,
          onChanged: onStartDateChanged,
        ),
        right: PatientDateField(
          value: selection.endDate,
          firstDate: firstDate,
          lastDate: lastDate,
          currentDate: now,
          initialPickerDate: selection.endDate ?? selection.startDate ?? now,
          labelText: l10n.patientsReportEndDateLabel,
          onChanged: onEndDateChanged,
        ),
      ),
    };
  }
}

class _PatientReportPreviewPages extends StatelessWidget {
  const _PatientReportPreviewPages({required this.document});

  final _PatientReportDocument document;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < document.pages.length; index++) ...<Widget>[
          _PatientReportPreviewPage(
            document: document,
            page: document.pages[index],
            pageNumber: index + 1,
            totalPages: document.pages.length,
          ),
          if (index < document.pages.length - 1)
            SizedBox(height: theme.spacing.md),
        ],
      ],
    );
  }
}

class _PatientReportPreviewPage extends StatelessWidget {
  const _PatientReportPreviewPage({
    required this.document,
    required this.page,
    required this.pageNumber,
    required this.totalPages,
  });

  final _PatientReportDocument document;
  final _PatientReportPage page;
  final int pageNumber;
  final int totalPages;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final l10n = context.l10n;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: theme.borders.all(),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 680),
        child: Padding(
          padding: EdgeInsets.all(theme.spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _PatientReportPageHeader(document: document),
              SizedBox(height: theme.spacing.md),
              for (
                var index = 0;
                index < page.blocks.length;
                index++
              ) ...<Widget>[
                _PatientReportBlockPreview(block: page.blocks[index]),
                if (index < page.blocks.length - 1)
                  SizedBox(height: theme.spacing.md),
              ],
              SizedBox(height: theme.spacing.md),
              Divider(color: theme.borders.faint),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  l10n.patientsReportPageNumberLabel(pageNumber, totalPages),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: AppFontWeight.emphasis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PatientReportPageHeader extends StatelessWidget {
  const _PatientReportPageHeader({required this.document});

  final _PatientReportDocument document;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final l10n = context.l10n;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: theme.borders.only(bottom: true, tone: AppBorderTone.strong),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: theme.spacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    document.hospitalName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: AppFontWeight.emphasis,
                    ),
                  ),
                  Text(
                    document.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: theme.spacing.md),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    document.patientName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: AppFontWeight.emphasis,
                    ),
                  ),
                  Text(
                    document.patientIdentifier,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '${l10n.patientsReportPeriodLabel}: ${document.periodLabel}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientReportBlockPreview extends StatelessWidget {
  const _PatientReportBlockPreview({required this.block});

  final _PatientReportBlock block;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          block.title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: AppFontWeight.emphasis,
          ),
        ),
        SizedBox(height: theme.spacing.xs),
        DecoratedBox(
          decoration: BoxDecoration(
            border: theme.borders.all(),
          ),
          child: block.rows.isEmpty
              ? Padding(
                  padding: EdgeInsets.all(theme.spacing.sm),
                  child: Text(
                    block.emptyText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : Column(
                  children: <Widget>[
                    for (var index = 0; index < block.rows.length; index++)
                      _PatientReportRowPreview(
                        row: block.rows[index],
                        showDivider: index < block.rows.length - 1,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _PatientReportRowPreview extends StatelessWidget {
  const _PatientReportRowPreview({
    required this.row,
    required this.showDivider,
  });

  final _PatientReportRow row;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: AppFontWeight.emphasis,
    );
    final TextStyle? valueStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface,
    );
    final TextStyle? detailStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: showDivider
            ? theme.borders.only(bottom: true)
            : null,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: theme.spacing.sm,
          vertical: theme.spacing.xs,
        ),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Widget value = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(row.value, style: valueStyle),
                if (row.detail != null) Text(row.detail!, style: detailStyle),
              ],
            );
            final Widget? meta = row.meta == null
                ? null
                : Text(row.meta!, textAlign: TextAlign.end, style: detailStyle);

            if (constraints.maxWidth < 520) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    row.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: labelStyle,
                  ),
                  SizedBox(height: theme.spacing.xs),
                  value,
                  if (meta != null) ...<Widget>[
                    SizedBox(height: theme.spacing.xs),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: meta,
                    ),
                  ],
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 160,
                  child: Text(
                    row.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: labelStyle,
                  ),
                ),
                SizedBox(width: theme.spacing.sm),
                Expanded(child: value),
                if (meta != null) ...<Widget>[
                  SizedBox(width: theme.spacing.sm),
                  SizedBox(width: 128, child: meta),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

PatientDetail? _livePatientDetail(WidgetRef ref, String patientId) {
  final AsyncValue<Result<PatientRegistryState>> state = ref.watch(
    patientRegistryControllerProvider,
  );
  return state.maybeWhen(
    data: (Result<PatientRegistryState> result) => result.when(
      success: (PatientRegistryState value) {
        final PatientDetail? selected = value.selectedDetail;
        return selected?.patient.id == patientId ? selected : null;
      },
      failure: (_) => null,
    ),
    orElse: () => null,
  );
}

PatientDetail _effectivePatientDetail(Patient patient, PatientDetail? detail) {
  return detail ??
      PatientDetail(
        patient: patient,
        workspace: const PatientWorkspaceSnapshot(),
      );
}

enum _PatientReportPeriodMode { allDates, singleDate, dateRange }

enum _PatientReportSection {
  summary,
  timeline,
  vitalSigns,
  appointments,
  encounters,
  admissions,
  invoices,
  payments,
  identifiers,
  contacts,
  guardians,
  allergies,
  medicalHistory,
  consents,
}

const List<_PatientReportSection> _patientReportSections =
    <_PatientReportSection>[
      _PatientReportSection.summary,
      _PatientReportSection.timeline,
      _PatientReportSection.vitalSigns,
      _PatientReportSection.appointments,
      _PatientReportSection.encounters,
      _PatientReportSection.admissions,
      _PatientReportSection.invoices,
      _PatientReportSection.payments,
      _PatientReportSection.identifiers,
      _PatientReportSection.contacts,
      _PatientReportSection.guardians,
      _PatientReportSection.allergies,
      _PatientReportSection.medicalHistory,
      _PatientReportSection.consents,
    ];

@immutable
final class _PatientReportSelection {
  const _PatientReportSelection({
    required this.periodMode,
    required this.sections,
    this.singleDate,
    this.startDate,
    this.endDate,
  });

  final _PatientReportPeriodMode periodMode;
  final DateTime? singleDate;
  final DateTime? startDate;
  final DateTime? endDate;
  final Set<_PatientReportSection> sections;
}

@immutable
final class _PatientReportRow {
  const _PatientReportRow({
    required this.label,
    required this.value,
    this.detail,
    this.meta,
  });

  final String label;
  final String value;
  final String? detail;
  final String? meta;
}

@immutable
final class _PatientReportBlock {
  const _PatientReportBlock({
    required this.title,
    required this.rows,
    required this.emptyText,
  });

  final String title;
  final List<_PatientReportRow> rows;
  final String emptyText;
}

@immutable
final class _PatientReportPage {
  const _PatientReportPage({required this.blocks});

  final List<_PatientReportBlock> blocks;
}

@immutable
final class _PatientReportDocument {
  const _PatientReportDocument({
    required this.title,
    required this.hospitalName,
    required this.patientName,
    required this.patientIdentifier,
    required this.periodLabel,
    required this.generatedAtLabel,
    required this.pages,
  });

  final String title;
  final String hospitalName;
  final String patientName;
  final String patientIdentifier;
  final String periodLabel;
  final String generatedAtLabel;
  final List<_PatientReportPage> pages;
}

_PatientReportDocument _buildPatientReportDocument(
  BuildContext context, {
  required PatientDetail detail,
  required _PatientReportSelection selection,
  required DateTime generatedAt,
}) {
  final l10n = context.l10n;
  final Locale locale = Localizations.localeOf(context);
  final Patient patient = detail.patient;
  final PatientWorkspaceSnapshot workspace = detail.workspace;
  final String hospitalName =
      patient.facilityLabel ?? patient.tenantLabel ?? l10n.appTitle;
  final String emptyText = l10n.patientsReportNoRecordsForSection;

  final List<_PatientReportBlock> leadingBlocks = <_PatientReportBlock>[
    _PatientReportBlock(
      title: l10n.patientsReportHospitalInfoSectionTitle,
      emptyText: emptyText,
      rows: <_PatientReportRow>[
        _PatientReportRow(
          label: l10n.patientsReportHospitalNameLabel,
          value: hospitalName,
        ),
        _PatientReportRow(
          label: l10n.patientsFacilityLabel,
          value: patient.facilityLabel ?? l10n.profileUnknownValue,
        ),
        _PatientReportRow(
          label: l10n.profileTenantLabel,
          value: patient.tenantLabel ?? l10n.profileUnknownValue,
        ),
        _PatientReportRow(
          label: l10n.patientsReportHospitalContactLabel,
          value: l10n.profileUnknownValue,
        ),
        _PatientReportRow(
          label: l10n.patientsReportHospitalLocationLabel,
          value: l10n.profileUnknownValue,
        ),
        _PatientReportRow(
          label: l10n.patientsReportHospitalAddressLabel,
          value: l10n.profileUnknownValue,
        ),
      ],
    ),
    _PatientReportBlock(
      title: l10n.patientsReportPatientInfoSectionTitle,
      emptyText: emptyText,
      rows: <_PatientReportRow>[
        _PatientReportRow(
          label: l10n.patientsIdentifierLabel,
          value: patient.effectiveIdentifier ?? l10n.profileUnknownValue,
        ),
        _PatientReportRow(
          label: l10n.patientsDobLabel,
          value: _formatOptionalDate(context, patient.dateOfBirth),
        ),
        _PatientReportRow(
          label: l10n.patientsGenderLabel,
          value: patient.gender == null
              ? l10n.profileUnknownValue
              : _genderLabel(l10n, patient.gender!),
        ),
        _PatientReportRow(
          label: l10n.patientsPhoneLabel,
          value: patient.primaryPhone ?? l10n.profileUnknownValue,
        ),
        _PatientReportRow(
          label: l10n.patientsEmailLabel,
          value: patient.primaryEmail ?? l10n.profileUnknownValue,
        ),
      ],
    ),
  ];

  final List<_PatientReportBlock> bodyBlocks = <_PatientReportBlock>[
    if (selection.sections.contains(_PatientReportSection.summary))
      _PatientReportBlock(
        title: l10n.patientsReportSummarySectionTitle,
        emptyText: emptyText,
        rows: <_PatientReportRow>[
          _PatientReportRow(
            label: l10n.patientsAppointmentsSectionTitle,
            value: _filteredSummaryRecords(
              workspace.appointments,
              selection,
            ).length.toString(),
          ),
          _PatientReportRow(
            label: l10n.patientsEncountersSectionTitle,
            value: _filteredSummaryRecords(
              workspace.encounters,
              selection,
            ).length.toString(),
          ),
          _PatientReportRow(
            label: l10n.patientsReportVitalsSectionTitle,
            value: _filteredTimelineItems(
              detail.timeline.where(_isVitalTimelineItem),
              selection,
            ).length.toString(),
          ),
          _PatientReportRow(
            label: l10n.patientsAdmissionsSectionTitle,
            value: _filteredSummaryRecords(
              workspace.admissions,
              selection,
            ).length.toString(),
          ),
          _PatientReportRow(
            label: l10n.patientsInvoicesSectionTitle,
            value: _filteredSummaryRecords(
              workspace.invoices,
              selection,
            ).length.toString(),
          ),
          _PatientReportRow(
            label: l10n.patientsReportPaymentsSectionTitle,
            value: _filteredSummaryRecords(
              workspace.payments,
              selection,
            ).length.toString(),
          ),
        ],
      ),
    if (selection.sections.contains(_PatientReportSection.timeline))
      _PatientReportBlock(
        title: l10n.patientsTimelineSectionTitle,
        rows: _timelineRows(context, detail.timeline, selection),
        emptyText: emptyText,
      ),
    if (selection.sections.contains(_PatientReportSection.vitalSigns))
      _PatientReportBlock(
        title: l10n.patientsReportVitalsSectionTitle,
        rows: _timelineRows(
          context,
          detail.timeline.where(_isVitalTimelineItem),
          selection,
        ),
        emptyText: emptyText,
      ),
    if (selection.sections.contains(_PatientReportSection.appointments))
      _PatientReportBlock(
        title: l10n.patientsAppointmentsSectionTitle,
        rows: _summaryRecordRows(context, workspace.appointments, selection),
        emptyText: emptyText,
      ),
    if (selection.sections.contains(_PatientReportSection.encounters))
      _PatientReportBlock(
        title: l10n.patientsEncountersSectionTitle,
        rows: _summaryRecordRows(context, workspace.encounters, selection),
        emptyText: emptyText,
      ),
    if (selection.sections.contains(_PatientReportSection.admissions))
      _PatientReportBlock(
        title: l10n.patientsAdmissionsSectionTitle,
        rows: _summaryRecordRows(context, workspace.admissions, selection),
        emptyText: emptyText,
      ),
    if (selection.sections.contains(_PatientReportSection.invoices))
      _PatientReportBlock(
        title: l10n.patientsInvoicesSectionTitle,
        rows: _summaryRecordRows(context, workspace.invoices, selection),
        emptyText: emptyText,
      ),
    if (selection.sections.contains(_PatientReportSection.payments))
      _PatientReportBlock(
        title: l10n.patientsReportPaymentsSectionTitle,
        rows: _summaryRecordRows(context, workspace.payments, selection),
        emptyText: emptyText,
      ),
    if (selection.sections.contains(_PatientReportSection.identifiers))
      _PatientReportBlock(
        title: l10n.patientsIdentifiersSectionTitle,
        rows: <_PatientReportRow>[
          for (final PatientIdentifier item in detail.identifiers)
            _PatientReportRow(
              label: _apiLabel(item.type),
              value: item.value,
              meta: item.isPrimary ? l10n.patientsPrimaryRecordLabel : null,
            ),
        ],
        emptyText: emptyText,
      ),
    if (selection.sections.contains(_PatientReportSection.contacts))
      _PatientReportBlock(
        title: l10n.patientsContactsSectionTitle,
        rows: <_PatientReportRow>[
          for (final PatientContact item in detail.contacts)
            _PatientReportRow(
              label: _apiLabel(item.type),
              value: item.value,
              meta: item.isPrimary ? l10n.patientsPrimaryRecordLabel : null,
            ),
        ],
        emptyText: emptyText,
      ),
    if (selection.sections.contains(_PatientReportSection.guardians))
      _PatientReportBlock(
        title: l10n.patientsGuardiansSectionTitle,
        rows: <_PatientReportRow>[
          for (final PatientGuardian item in detail.guardians)
            _PatientReportRow(
              label: item.name,
              value: item.relationship ?? l10n.profileUnknownValue,
              detail: _joinDisplay(<String?>[item.phone, item.email]),
            ),
        ],
        emptyText: emptyText,
      ),
    if (selection.sections.contains(_PatientReportSection.allergies))
      _PatientReportBlock(
        title: l10n.patientsAllergiesSectionTitle,
        rows: <_PatientReportRow>[
          for (final PatientAllergy item in detail.allergies)
            _PatientReportRow(
              label: item.allergen,
              value: _apiLabel(item.severity),
              detail: _joinDisplay(<String?>[item.reaction, item.notes]),
            ),
        ],
        emptyText: emptyText,
      ),
    if (selection.sections.contains(_PatientReportSection.medicalHistory))
      _PatientReportBlock(
        title: l10n.patientsMedicalHistorySectionTitle,
        rows: <_PatientReportRow>[
          for (final PatientMedicalHistory item in detail.medicalHistories)
            _PatientReportRow(
              label: item.condition,
              value: _formatOptionalDate(context, item.diagnosisDate),
              detail: item.notes,
            ),
        ],
        emptyText: emptyText,
      ),
    if (selection.sections.contains(_PatientReportSection.consents))
      _PatientReportBlock(
        title: l10n.patientsConsentsSectionTitle,
        rows: <_PatientReportRow>[
          for (final PatientConsent item in detail.consents)
            _PatientReportRow(
              label: _apiLabel(item.consentType),
              value: _apiLabel(item.status),
              meta: _formatOptionalDateTime(
                context,
                item.grantedAt ?? item.revokedAt ?? item.updatedAt,
              ),
            ),
        ],
        emptyText: emptyText,
      ),
    _PatientReportBlock(
      title: l10n.patientsReportGeneratedSectionTitle,
      emptyText: emptyText,
      rows: <_PatientReportRow>[
        _PatientReportRow(
          label: l10n.patientsReportPreparedOnLabel,
          value: AppFormatters.dateTime(generatedAt, locale),
        ),
      ],
    ),
  ];

  return _PatientReportDocument(
    title: l10n.patientsReportDialogTitle,
    hospitalName: hospitalName,
    patientName: patient.effectiveDisplayName,
    patientIdentifier: patient.effectiveIdentifier ?? l10n.profileUnknownValue,
    periodLabel: _patientReportPeriodLabel(context, selection),
    generatedAtLabel: AppFormatters.dateTime(generatedAt, locale),
    pages: _paginatePatientReportBlocks(leadingBlocks, bodyBlocks),
  );
}

List<_PatientReportPage> _paginatePatientReportBlocks(
  List<_PatientReportBlock> leadingBlocks,
  List<_PatientReportBlock> bodyBlocks,
) {
  const int firstPageCapacity = 22;
  const int regularPageCapacity = 26;
  const int maxBlockRows = 18;
  final List<_PatientReportPage> pages = <_PatientReportPage>[];
  final List<_PatientReportBlock> currentBlocks = <_PatientReportBlock>[];
  var capacity = firstPageCapacity;
  var used = 0;

  void pushPage() {
    if (currentBlocks.isEmpty) {
      return;
    }
    pages.add(
      _PatientReportPage(blocks: List<_PatientReportBlock>.of(currentBlocks)),
    );
    currentBlocks.clear();
    capacity = regularPageCapacity;
    used = 0;
  }

  void addBlock(_PatientReportBlock block) {
    for (final _PatientReportBlock chunk in _chunkPatientReportBlock(
      block,
      maxBlockRows,
    )) {
      final int weight = math.max(chunk.rows.length, 1) + 2;
      if (currentBlocks.isNotEmpty && used + weight > capacity) {
        pushPage();
      }
      currentBlocks.add(chunk);
      used += weight;
    }
  }

  for (final _PatientReportBlock block in leadingBlocks) {
    addBlock(block);
  }
  for (final _PatientReportBlock block in bodyBlocks) {
    addBlock(block);
  }
  pushPage();

  return pages.isEmpty
      ? <_PatientReportPage>[
          const _PatientReportPage(blocks: <_PatientReportBlock>[]),
        ]
      : pages;
}

List<_PatientReportBlock> _chunkPatientReportBlock(
  _PatientReportBlock block,
  int maxRows,
) {
  if (block.rows.length <= maxRows) {
    return <_PatientReportBlock>[block];
  }

  final List<_PatientReportBlock> chunks = <_PatientReportBlock>[];
  for (var index = 0; index < block.rows.length; index += maxRows) {
    chunks.add(
      _PatientReportBlock(
        title: block.title,
        rows: block.rows.skip(index).take(maxRows).toList(growable: false),
        emptyText: block.emptyText,
      ),
    );
  }
  return chunks;
}

List<_PatientReportRow> _summaryRecordRows(
  BuildContext context,
  Iterable<PatientSummaryRecord> records,
  _PatientReportSelection selection,
) {
  final List<PatientSummaryRecord> filtered = _filteredSummaryRecords(
    records,
    selection,
  );
  return <_PatientReportRow>[
    for (final PatientSummaryRecord record in filtered)
      _PatientReportRow(
        label: record.title ?? _apiLabel(record.kind),
        value: _joinDisplay(<String?>[
          record.status == null ? null : _apiLabel(record.status!),
          record.subtitle,
        ]),
        meta: _joinDisplay(<String?>[
          _formatOptionalDateTime(context, record.occurredAt),
          _formatSummaryRecordAmount(context, record),
        ]),
      ),
  ];
}

List<_PatientReportRow> _timelineRows(
  BuildContext context,
  Iterable<PatientTimelineItem> items,
  _PatientReportSelection selection,
) {
  return <_PatientReportRow>[
    for (final PatientTimelineItem item in _filteredTimelineItems(
      items,
      selection,
    ))
      _PatientReportRow(
        label: _apiLabel(item.resource),
        value: item.title ?? item.subtitle ?? context.l10n.profileUnknownValue,
        detail: item.title == null ? null : item.subtitle,
        meta: _formatOptionalDateTime(context, item.occurredAt),
      ),
  ];
}

List<PatientSummaryRecord> _filteredSummaryRecords(
  Iterable<PatientSummaryRecord> records,
  _PatientReportSelection selection,
) {
  return records
      .where(
        (PatientSummaryRecord record) =>
            _matchesPatientReportPeriod(record.occurredAt, selection),
      )
      .toList(growable: false);
}

List<PatientTimelineItem> _filteredTimelineItems(
  Iterable<PatientTimelineItem> items,
  _PatientReportSelection selection,
) {
  return items
      .where(
        (PatientTimelineItem item) =>
            _matchesPatientReportPeriod(item.occurredAt, selection),
      )
      .toList(growable: false);
}

bool _matchesPatientReportPeriod(
  DateTime? value,
  _PatientReportSelection selection,
) {
  if (selection.periodMode == _PatientReportPeriodMode.allDates) {
    return true;
  }
  if (value == null) {
    return false;
  }

  final DateTime date = _dateOnly(value);
  return switch (selection.periodMode) {
    _PatientReportPeriodMode.allDates => true,
    _PatientReportPeriodMode.singleDate =>
      selection.singleDate == null || date == _dateOnly(selection.singleDate!),
    _PatientReportPeriodMode.dateRange =>
      (selection.startDate == null ||
              !date.isBefore(_dateOnly(selection.startDate!))) &&
          (selection.endDate == null ||
              !date.isAfter(_dateOnly(selection.endDate!))),
  };
}

String? _formatSummaryRecordAmount(
  BuildContext context,
  PatientSummaryRecord record,
) {
  if (record.amount == null) {
    return null;
  }
  return AppFormatters.currency(
    record.amount!,
    Localizations.localeOf(context),
    currencyCode: record.currency,
  );
}

bool _isVitalTimelineItem(PatientTimelineItem item) {
  final String searchable = <String>[
    item.resource,
    item.title ?? '',
    item.subtitle ?? '',
  ].join(' ').toLowerCase();
  return searchable.contains('vital');
}

int _patientReportSectionCount(
  PatientDetail detail,
  _PatientReportSection section,
  _PatientReportSelection selection,
) {
  final PatientWorkspaceSnapshot workspace = detail.workspace;
  return switch (section) {
    _PatientReportSection.summary => 6,
    _PatientReportSection.timeline => _filteredTimelineItems(
      detail.timeline,
      selection,
    ).length,
    _PatientReportSection.vitalSigns => _filteredTimelineItems(
      detail.timeline.where(_isVitalTimelineItem),
      selection,
    ).length,
    _PatientReportSection.appointments => _filteredSummaryRecords(
      workspace.appointments,
      selection,
    ).length,
    _PatientReportSection.encounters => _filteredSummaryRecords(
      workspace.encounters,
      selection,
    ).length,
    _PatientReportSection.admissions => _filteredSummaryRecords(
      workspace.admissions,
      selection,
    ).length,
    _PatientReportSection.invoices => _filteredSummaryRecords(
      workspace.invoices,
      selection,
    ).length,
    _PatientReportSection.payments => _filteredSummaryRecords(
      workspace.payments,
      selection,
    ).length,
    _PatientReportSection.identifiers => detail.identifiers.length,
    _PatientReportSection.contacts => detail.contacts.length,
    _PatientReportSection.guardians => detail.guardians.length,
    _PatientReportSection.allergies => detail.allergies.length,
    _PatientReportSection.medicalHistory => detail.medicalHistories.length,
    _PatientReportSection.consents => detail.consents.length,
  };
}

List<ReportSectionAvailability> _patientReportAvailabilities(
  PatientDetail detail,
  _PatientReportSelection selection, {
  PrintFormTemplateContext? branding,
}) {
  final List<ReportSectionAvailability> facilitySections = branding == null
      ? const <ReportSectionAvailability>[]
      : buildFacilityPrintSectionAvailabilities(
          effectivePrintBranding(
            appBranding: branding.appBranding,
            facilityBranding: branding.facilityBranding,
          ),
        );
  return <ReportSectionAvailability>[
    ...facilitySections,
    for (final _PatientReportSection section in _patientReportSections)
      ReportSectionAvailability(
        id: section,
        count: _patientReportSectionCount(detail, section, selection),
        alwaysAvailable: section == _PatientReportSection.summary,
      ),
  ];
}

String _patientReportSectionApiId(_PatientReportSection section) {
  return switch (section) {
    _PatientReportSection.summary => 'patient_information',
    _PatientReportSection.timeline => 'patient_information',
    _PatientReportSection.vitalSigns => 'vitals',
    _PatientReportSection.appointments => 'appointments',
    _PatientReportSection.encounters => 'encounter_details',
    _PatientReportSection.admissions => 'admissions',
    _PatientReportSection.invoices => 'billing_information',
    _PatientReportSection.payments => 'billing_information',
    _PatientReportSection.identifiers => 'identifiers',
    _PatientReportSection.contacts => 'contacts',
    _PatientReportSection.guardians => 'guardians',
    _PatientReportSection.allergies => 'allergies',
    _PatientReportSection.medicalHistory => 'medical_history',
    _PatientReportSection.consents => 'consents',
  };
}

String _patientReportSectionLabel(
  AppLocalizations l10n,
  Object section,
) {
  if (section is PrintFacilitySection) {
    return printFacilitySectionLabel(l10n, section);
  }
  return switch (section as _PatientReportSection) {
    _PatientReportSection.summary => l10n.patientsReportSummarySectionTitle,
    _PatientReportSection.timeline => l10n.patientsTimelineSectionTitle,
    _PatientReportSection.vitalSigns => l10n.patientsReportVitalsSectionTitle,
    _PatientReportSection.appointments => l10n.patientsAppointmentsSectionTitle,
    _PatientReportSection.encounters => l10n.patientsEncountersSectionTitle,
    _PatientReportSection.admissions => l10n.patientsAdmissionsSectionTitle,
    _PatientReportSection.invoices => l10n.patientsInvoicesSectionTitle,
    _PatientReportSection.payments => l10n.patientsReportPaymentsSectionTitle,
    _PatientReportSection.identifiers => l10n.patientsIdentifiersSectionTitle,
    _PatientReportSection.contacts => l10n.patientsContactsSectionTitle,
    _PatientReportSection.guardians => l10n.patientsGuardiansSectionTitle,
    _PatientReportSection.allergies => l10n.patientsAllergiesSectionTitle,
    _PatientReportSection.medicalHistory =>
      l10n.patientsMedicalHistorySectionTitle,
    _PatientReportSection.consents => l10n.patientsConsentsSectionTitle,
  };
}

IconData _patientReportSectionIcon(Object section) {
  if (section is PrintFacilitySection) {
    return printFacilitySectionIcon(section);
  }
  return switch (section as _PatientReportSection) {
    _PatientReportSection.summary => Icons.summarize_outlined,
    _PatientReportSection.timeline => Icons.timeline_outlined,
    _PatientReportSection.vitalSigns => Icons.monitor_heart_outlined,
    _PatientReportSection.appointments => Icons.event_available_outlined,
    _PatientReportSection.encounters => Icons.medical_services_outlined,
    _PatientReportSection.admissions => Icons.local_hospital_outlined,
    _PatientReportSection.invoices => Icons.receipt_long_outlined,
    _PatientReportSection.payments => Icons.payments_outlined,
    _PatientReportSection.identifiers => Icons.badge_outlined,
    _PatientReportSection.contacts => Icons.contact_phone_outlined,
    _PatientReportSection.guardians => Icons.supervisor_account_outlined,
    _PatientReportSection.allergies => Icons.warning_amber_outlined,
    _PatientReportSection.medicalHistory => Icons.history_edu_outlined,
    _PatientReportSection.consents => Icons.fact_check_outlined,
  };
}

String _patientReportPeriodModeLabel(
  AppLocalizations l10n,
  _PatientReportPeriodMode value,
) {
  return switch (value) {
    _PatientReportPeriodMode.allDates => l10n.patientsReportAllDatesOption,
    _PatientReportPeriodMode.singleDate => l10n.patientsReportSingleDateOption,
    _PatientReportPeriodMode.dateRange => l10n.patientsReportDateRangeOption,
  };
}

String _patientReportPeriodLabel(
  BuildContext context,
  _PatientReportSelection selection,
) {
  final l10n = context.l10n;
  return switch (selection.periodMode) {
    _PatientReportPeriodMode.allDates => l10n.patientsReportAllDatesOption,
    _PatientReportPeriodMode.singleDate =>
      selection.singleDate == null
          ? l10n.patientsReportSingleDateOption
          : _formatOptionalDate(context, selection.singleDate),
    _PatientReportPeriodMode.dateRange =>
      _joinDisplay(<String?>[
            selection.startDate == null
                ? null
                : _formatOptionalDate(context, selection.startDate),
            selection.endDate == null
                ? null
                : _formatOptionalDate(context, selection.endDate),
          ]).isEmpty
          ? l10n.patientsReportDateRangeOption
          : _joinDisplay(<String?>[
              selection.startDate == null
                  ? null
                  : _formatOptionalDate(context, selection.startDate),
              selection.endDate == null
                  ? null
                  : _formatOptionalDate(context, selection.endDate),
            ]),
  };
}

DateTime _dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

List<PrintFormPage> _patientReportPrintPages(_PatientReportDocument report) {
  String row(_PatientReportRow value) {
    final String detail = value.detail == null
        ? ''
        : '<div class="detail">${printHtmlEscape(value.detail!)}</div>';
    final String meta = value.meta == null
        ? ''
        : '<div class="meta">${printHtmlEscape(value.meta!)}</div>';
    return '''
      <tr>
        <th>${printHtmlEscape(value.label)}</th>
        <td>${printHtmlEscape(value.value)}$detail</td>
        <td>$meta</td>
      </tr>
''';
  }

  String block(_PatientReportBlock value) {
    final String rows = value.rows.isEmpty
        ? '<tr><td colspan="3" class="empty">${printHtmlEscape(value.emptyText)}</td></tr>'
        : value.rows.map(row).join();
    return '''
      <section class="print-template-section print-template-section--avoid-break">
        <h2>${printHtmlEscape(value.title)}</h2>
        <table>$rows</table>
      </section>
''';
  }

  const String patientReportStyle = '''
<style>
  .print-template-section table { width: 100%; border-collapse: collapse; }
  .print-template-section th,
  .print-template-section td { border: 1px solid #d1d5db; padding: 6px 8px; text-align: left; vertical-align: top; font-size: 11px; }
  .print-template-section th { width: 28%; background: #f3f4f6; font-weight: 700; }
  .print-template-section td:last-child { width: 20%; text-align: right; color: #374151; }
  .detail { color: #374151; margin-top: 2px; }
  .meta { color: #374151; }
  .empty { color: #6b7280; text-align: left !important; }
</style>
''';

  return <PrintFormPage>[
    for (final _PatientReportPage page in report.pages)
      PrintFormPage(
        title: report.title,
        bodyHtml: '$patientReportStyle${page.blocks.map(block).join()}',
      ),
  ];
}

class PatientDuplicateReviewDialog extends ConsumerStatefulWidget {
  const PatientDuplicateReviewDialog({required this.duplicates, super.key});

  final List<PatientDuplicateCandidate> duplicates;

  @override
  ConsumerState<PatientDuplicateReviewDialog> createState() =>
      _PatientDuplicateReviewDialogState();
}

class _PatientDuplicateReviewDialogState
    extends ConsumerState<PatientDuplicateReviewDialog> {
  late List<PatientDuplicateCandidate> _duplicates;
  PatientDuplicateCandidate? _selectedDuplicate;
  PatientMergePreview? _preview;
  bool _isLoadingPreview = false;
  bool _isSaving = false;
  AppFailure? _failure;

  @override
  void initState() {
    super.initState();
    _duplicates = widget.duplicates.toList(growable: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ThemeData theme = Theme.of(context);

    return AppDialog(
      title: Text(l10n.patientsDuplicateReviewTitle),
      icon: const Icon(Icons.content_copy_outlined),
      maxWidth: 920,
      scrollable: true,
      closeEnabled: !_isSaving && !_isLoadingPreview,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_failure != null) ...<Widget>[
            AppFormInformationBanner.failure(
              context: context,
              failure: _failure!,
            ),
            SizedBox(height: theme.spacing.md),
          ],
          if (_duplicates.isEmpty)
            AppWorkspaceStatePanel.empty(
              title: l10n.patientsNoDuplicateReviewsTitle,
              body: l10n.patientsNoDuplicateReviewsBody,
              icon: Icons.verified_user_outlined,
              minHeight: 240,
            )
          else
            for (final PatientDuplicateCandidate duplicate in _duplicates)
              Padding(
                padding: EdgeInsets.only(bottom: theme.spacing.sm),
                child: _DuplicateReviewCard(
                  duplicate: duplicate,
                  isBusy: _isSaving || _isLoadingPreview,
                  onPreview: () => _previewMerge(duplicate),
                  onDismiss: () => _dismissDuplicate(duplicate),
                ),
              ),
          if (_isLoadingPreview)
            AppWorkspaceStatePanel.loading(
              title: l10n.patientsMergePreviewLoadingTitle,
              body: l10n.patientsMergePreviewLoadingBody,
              minHeight: 180,
            )
          else if (_preview != null && _selectedDuplicate != null)
            PatientDuplicateMergeWorkspace(
              preview: _preview!,
              comparisons: _selectedDuplicate!.fieldComparisons,
              facilities: _mergeFacilities(ref),
              isSaving: _isSaving,
              onConfirmMerge: (PatientMergeCommitPlan plan) {
                return _mergeDuplicate(_selectedDuplicate!, plan: plan);
              },
            ),
        ],
      ),
    );
  }

  List<PatientReferenceOption> _mergeFacilities(WidgetRef ref) {
    final Result<PatientRegistryState>? result = ref
        .watch(patientRegistryControllerProvider)
        .asData
        ?.value;
    if (result == null) {
      return const <PatientReferenceOption>[];
    }
    return result.when(
      success: (PatientRegistryState state) => state.referenceData.facilities,
      failure: (_) => const <PatientReferenceOption>[],
    );
  }

  Future<void> _previewMerge(PatientDuplicateCandidate duplicate) async {
    setState(() {
      _isLoadingPreview = true;
      _failure = null;
      _selectedDuplicate = duplicate;
      _preview = null;
    });
    final Result<PatientMergePreview> result = await ref
        .read(patientRegistryControllerProvider.notifier)
        .previewDuplicateMerge(duplicate);
    if (!mounted) {
      return;
    }
    result.when(
      success: (PatientMergePreview preview) {
        setState(() {
          _preview = preview;
          _isLoadingPreview = false;
        });
      },
      failure: (AppFailure failure) {
        setState(() {
          _failure = failure;
          _isLoadingPreview = false;
        });
      },
    );
  }

  Future<void> _dismissDuplicate(PatientDuplicateCandidate duplicate) async {
    setState(() {
      _isSaving = true;
      _failure = null;
    });
    final AppFailure? failure = await ref
        .read(patientRegistryControllerProvider.notifier)
        .dismissDuplicateCandidate(duplicate);
    if (!mounted) {
      return;
    }
    if (failure == null) {
      setState(() {
        _duplicates.removeWhere(
          (PatientDuplicateCandidate item) =>
              item.reviewId == duplicate.reviewId,
        );
        if (_selectedDuplicate?.reviewId == duplicate.reviewId) {
          _selectedDuplicate = null;
          _preview = null;
        }
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.patientsDuplicateDismissedMessage)),
      );
      return;
    }
    setState(() {
      _failure = failure;
      _isSaving = false;
    });
  }

  Future<void> _mergeDuplicate(
    PatientDuplicateCandidate duplicate, {
    required PatientMergeCommitPlan plan,
  }) async {
    setState(() {
      _isSaving = true;
      _failure = null;
    });
    final AppFailure? failure = await ref
        .read(patientRegistryControllerProvider.notifier)
        .mergeDuplicateCandidate(
          duplicate,
          primaryPatientId: plan.primaryPatientId,
          secondaryPatientId: plan.secondaryPatientId,
          summary: plan.summary,
        );
    if (!mounted) {
      return;
    }
    if (failure == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.patientsMergedMessage)),
      );
      await Navigator.of(context).maybePop(plan.primaryPatientId);
      return;
    }
    setState(() {
      _failure = failure;
      _isSaving = false;
    });
  }
}

class _DuplicateReviewCard extends StatelessWidget {
  const _DuplicateReviewCard({
    required this.duplicate,
    required this.isBusy,
    required this.onPreview,
    required this.onDismiss,
  });

  final PatientDuplicateCandidate duplicate;
  final bool isBusy;
  final VoidCallback onPreview;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final l10n = context.l10n;
    final Patient? primary = duplicate.primaryPatient;
    final Patient? secondary =
        duplicate.secondaryPatient ?? duplicate.candidatePatient;

    return AppContentPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AppWorkspaceStatusBadge(
                status: AppWorkspaceStatus(
                  label: l10n.patientsDuplicateScoreLabel(
                    duplicate.confidenceScore,
                  ),
                  tone: AppWorkspaceStatusTone.warning,
                ),
              ),
              SizedBox(width: theme.spacing.sm),
              Expanded(
                child: Text(
                  _apiLabel(duplicate.classification),
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          SizedBox(height: theme.spacing.sm),
          _DuplicatePatientPair(primary: primary, secondary: secondary),
          if (duplicate.matchReasons.isNotEmpty) ...<Widget>[
            SizedBox(height: theme.spacing.sm),
            Text(
              duplicate.matchReasons.map(_apiLabel).join(', '),
              style: theme.textTheme.bodySmall,
            ),
          ],
          SizedBox(height: theme.spacing.sm),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Wrap(
              spacing: theme.spacing.xs,
              runSpacing: theme.spacing.xs,
              alignment: WrapAlignment.end,
              children: <Widget>[
                AppAccessActionGate(
                  requirement: PatientAllAtomPermissions.duplicateReview,
                  builder: (_, bool isAllowed) {
                    if (!isAllowed) {
                      return const SizedBox.shrink();
                    }
                    return AppButton.secondary(
                      label: l10n.patientsReviewMergeAction,
                      leadingIcon: Icons.merge_type_outlined,
                      enabled: !isBusy && primary != null && secondary != null,
                      onPressed: onPreview,
                    );
                  },
                ),
                AppAccessActionGate(
                  requirement: PatientAllAtomPermissions.duplicateReview,
                  builder: (_, bool isAllowed) {
                    if (!isAllowed) {
                      return const SizedBox.shrink();
                    }
                    return AppButton.tertiary(
                      label: l10n.patientsDismissDuplicateAction,
                      leadingIcon: Icons.block_outlined,
                      enabled: !isBusy && primary != null && secondary != null,
                      onPressed: onDismiss,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DuplicatePatientPair extends StatelessWidget {
  const _DuplicatePatientPair({required this.primary, required this.secondary});

  final Patient? primary;
  final Patient? secondary;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool stacked = constraints.maxWidth < 560;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _DuplicatePatientSummary(patient: primary),
              SizedBox(height: theme.spacing.sm),
              _DuplicatePatientSummary(patient: secondary),
            ],
          );
        }

        return Row(
          children: <Widget>[
            Expanded(child: _DuplicatePatientSummary(patient: primary)),
            SizedBox(width: theme.spacing.sm),
            Expanded(child: _DuplicatePatientSummary(patient: secondary)),
          ],
        );
      },
    );
  }
}

class _DuplicatePatientSummary extends StatelessWidget {
  const _DuplicatePatientSummary({required this.patient});

  final Patient? patient;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Patient? value = patient;

    return AppContentPanel(
      density: AppContentPanelDensity.compact,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            value?.effectiveDisplayName ?? context.l10n.profileUnknownValue,
            style: theme.textTheme.titleSmall,
          ),
          Text(
            _joinDisplay(<String?>[
              value?.effectiveIdentifier,
              value?.primaryPhone,
              value?.primaryEmail,
            ]),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class PatientFormDialog extends StatefulWidget {
  const PatientFormDialog({
    required this.patient,
    required this.referenceData,
    required this.onSubmit,
    super.key,
  });

  final Patient patient;
  final PatientReferenceData referenceData;
  final Future<AppFailure?> Function(Map<String, Object?> payload) onSubmit;

  @override
  State<PatientFormDialog> createState() => _PatientFormDialogState();
}

class _PatientFormDialogState extends State<PatientFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _identifierTypeController;
  late final TextEditingController _identifierValueController;
  DateTime? _dateOfBirth;
  String? _gender;
  String? _facilityId;
  bool _isActive = true;
  bool _isSaving = false;
  AppFailure? _failure;

  @override
  void initState() {
    super.initState();
    final Patient patient = widget.patient;
    _firstNameController = TextEditingController(text: patient.firstName);
    _lastNameController = TextEditingController(text: patient.lastName);
    _phoneController = TextEditingController(text: patient.primaryPhone);
    _emailController = TextEditingController(text: patient.primaryEmail);
    _identifierTypeController = TextEditingController(
      text: patient.primaryIdentifierType,
    );
    _identifierValueController = TextEditingController(
      text: patient.primaryIdentifierValue,
    );
    _dateOfBirth = patient.dateOfBirth;
    _gender = patient.gender;
    _facilityId = patient.facilityId;
    _isActive = patient.isActive;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _identifierTypeController.dispose();
    _identifierValueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AppDialog(
      title: Text(l10n.patientsEditTitle),
      icon: const Icon(Icons.assignment_ind_outlined),
      closeEnabled: !_isSaving,
      maxWidth: 760,
      content: SizedBox(
        height: _formBodyHeight(context),
        child: AppFormShell(
          formKey: _formKey,
          enabled: !_isSaving,
          scrollable: true,
          density: AppFormSectionDensity.compact,
          formStatus: appFormFailureStatus(context, _failure),
          children: <Widget>[
            AppResponsiveFieldRow.two(
              left: AppTextField(
                controller: _firstNameController,
                labelText: l10n.patientsFirstNameLabel,
                isRequired: true,
                textCapitalization: TextCapitalization.words,
                enabled: !_isSaving,
                validator: AppValidators.requiredText(l10n.validationRequired),
              ),
              right: AppTextField(
                controller: _lastNameController,
                labelText: l10n.patientsLastNameLabel,
                textCapitalization: TextCapitalization.words,
                enabled: !_isSaving,
              ),
            ),
            AppResponsiveFieldRow.two(
              left: PatientDateField(
                value: _dateOfBirth,
                firstDate: DateTime(1900),
                lastDate: DateTime.now(),
                labelText: l10n.patientsDobLabel,
                enabled: !_isSaving,
                onChanged: (DateTime? value) {
                  setState(() {
                    _dateOfBirth = value;
                  });
                },
              ),
              right: AppGenderField(
                value: _gender,
                labelText: l10n.patientsGenderLabel,
                maleLabel: l10n.patientsGenderMale,
                femaleLabel: l10n.patientsGenderFemale,
                otherLabel: l10n.patientsGenderOther,
                unknownLabel: l10n.patientsGenderUnknown,
                enabled: !_isSaving,
                onChanged: (String? value) {
                  setState(() {
                    _gender = value;
                  });
                },
              ),
            ),
            if (widget.referenceData.facilities.length > 1)
              PatientFacilitySelectField(
                facilities: widget.referenceData.facilities,
                value: _facilityId,
                labelText: l10n.patientsFacilityLabel,
                enabled: !_isSaving,
                onChanged: (String? value) {
                  setState(() {
                    _facilityId = value;
                  });
                },
              ),
            PatientPhoneField(
              controller: _phoneController,
              labelText: l10n.patientsPhoneLabel,
              enabled: !_isSaving,
            ),
            PatientEmailField(
              controller: _emailController,
              labelText: l10n.patientsEmailLabel,
              enabled: !_isSaving,
            ),
            AppResponsiveFieldRow.two(
              left: AppSelectField<String>.searchable(
                value: _selectedIdentifierType(_identifierTypeController.text),
                labelText: l10n.patientsIdentifierTypeLabel,
                enabled: !_isSaving,
                menuHeight: 320,
                onChanged: (String? value) {
                  setState(() {
                    _identifierTypeController.text = value ?? '';
                  });
                },
                options: _identifierTypeSelectOptions(
                  _identifierTypeController.text,
                ),
              ),
              right: AppTextField(
                controller: _identifierValueController,
                labelText: l10n.patientsIdentifierValueLabel,
                enabled: !_isSaving,
              ),
            ),
            AppCheckboxField(
              title: l10n.patientsActiveCheckboxLabel,
              value: _isActive,
              enabled: !_isSaving,
              onChanged: (bool value) {
                setState(() {
                  _isActive = value;
                });
              },
            ),
          ],
        ),
      ),
      actions: <Widget>[
        AppButton.close(
          leadingIcon: AppActionIcons.cancel,
          label: l10n.commonCancelActionLabel,
          onPressed: _isSaving ? null : () => Navigator.of(context).maybePop(),
        ),
        AppButton.primary(
          label: l10n.patientsSaveAction,
          isLoading: _isSaving,
          onPressed: _submit,
        ),
      ],
    );
  }

  double _formBodyHeight(BuildContext context) {
    final double viewportHeight = MediaQuery.sizeOf(context).height;
    return math.min(640, viewportHeight * 0.72);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _isSaving = true;
      _failure = null;
    });

    final Map<String, Object?> payload = <String, Object?>{
      'first_name': _firstNameController.text.trim(),
      'last_name': _lastNameController.text.trim(),
      'date_of_birth': _dateOfBirth?.toIso8601String(),
      'gender': _gender,
      'facility_id': _facilityId,
      'primary_phone': _phoneController.text.trim(),
      'primary_email': _emailController.text.trim(),
      'primary_identifier_type': _identifierTypeController.text
          .trim()
          .toUpperCase(),
      'primary_identifier_value': _identifierValueController.text.trim(),
      'is_active': _isActive,
    };
    final AppFailure? failure = await widget.onSubmit(payload);
    if (!mounted) {
      return;
    }
    if (failure == null) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _isSaving = false;
      _failure = failure;
    });
  }
}

class PatientRelatedRecordDialog<T> extends StatefulWidget {
  const PatientRelatedRecordDialog({
    required this.detail,
    required this.resource,
    required this.referenceData,
    required this.onCreate,
    required this.onUpdate,
    this.item,
    super.key,
  });

  final PatientDetail detail;
  final PatientRelatedResource resource;
  final PatientReferenceData referenceData;
  final T? item;
  final Future<AppFailure?> Function(Map<String, Object?> payload) onCreate;
  final Future<AppFailure?> Function(
    String recordId,
    Map<String, Object?> payload,
  )
  onUpdate;

  @override
  State<PatientRelatedRecordDialog<T>> createState() =>
      _PatientRelatedRecordDialogState<T>();
}

class _PatientRelatedRecordDialogState<T>
    extends State<PatientRelatedRecordDialog<T>> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _first = TextEditingController();
  final TextEditingController _second = TextEditingController();
  final TextEditingController _third = TextEditingController();
  final TextEditingController _fourth = TextEditingController();
  String? _choice;
  bool _isPrimary = false;
  DateTime? _date;
  bool _isSaving = false;
  AppFailure? _failure;

  bool get _isEditing => widget.item != null;

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    _third.dispose();
    _fourth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AppDialog(
      title: Text(
        _isEditing
            ? l10n.patientsEditRelatedTitle
            : l10n.patientsAddRelatedTitle,
      ),
      icon: Icon(_resourceIcon(widget.resource)),
      scrollable: true,
      closeEnabled: !_isSaving,
      content: AppFormShell(
        formKey: _formKey,
        enabled: !_isSaving,
        density: AppFormSectionDensity.compact,
        formStatus: appFormFailureStatus(context, _failure),
        children: _fieldsForResource(context),
      ),
      actions: <Widget>[
        AppButton.close(
          leadingIcon: AppActionIcons.cancel,
          label: l10n.commonCancelActionLabel,
          onPressed: _isSaving ? null : () => Navigator.of(context).maybePop(),
        ),
        AppButton.primary(
          label: l10n.patientsSaveAction,
          isLoading: _isSaving,
          onPressed: _submit,
        ),
      ],
    );
  }

  List<Widget> _fieldsForResource(BuildContext context) {
    final l10n = context.l10n;
    return switch (widget.resource) {
      PatientRelatedResource.identifier => <Widget>[
        AppSelectField<String>.searchable(
          value: _selectedIdentifierType(_first.text),
          labelText: l10n.patientsIdentifierTypeLabel,
          enabled: !_isSaving,
          isRequired: true,
          menuHeight: 320,
          validator: AppValidators.requiredValue(l10n.validationRequired),
          onChanged: (String? value) =>
              setState(() => _first.text = value ?? ''),
          options: _identifierTypeSelectOptions(_first.text),
        ),
        AppTextField(
          controller: _second,
          labelText: l10n.patientsIdentifierValueLabel,
          enabled: !_isSaving,
          isRequired: true,
          validator: AppValidators.requiredText(l10n.validationRequired),
        ),
        AppCheckboxField(
          title: l10n.patientsPrimaryRecordLabel,
          value: _isPrimary,
          enabled: !_isSaving,
          onChanged: (bool value) => setState(() => _isPrimary = value),
        ),
      ],
      PatientRelatedResource.contact => <Widget>[
        AppSelectField<String>.searchable(
          value: _choice,
          labelText: l10n.patientsContactTypeLabel,
          isRequired: true,
          enabled: !_isSaving,
          menuHeight: 320,
          validator: AppValidators.requiredValue(l10n.validationRequired),
          onChanged: (String? value) => setState(() {
            _choice = value;
            _first.clear();
          }),
          options: _contactTypeSelectOptions(),
        ),
        _contactValueField(context),
        AppCheckboxField(
          title: l10n.patientsPrimaryRecordLabel,
          value: _isPrimary,
          enabled: !_isSaving,
          onChanged: (bool value) => setState(() => _isPrimary = value),
        ),
      ],
      PatientRelatedResource.guardian => <Widget>[
        AppTextField(
          controller: _first,
          labelText: l10n.patientsGuardianNameLabel,
          enabled: !_isSaving,
          isRequired: true,
          validator: AppValidators.requiredText(l10n.validationRequired),
        ),
        AppSelectField<String>.searchable(
          value: _second.text.trim().isEmpty
              ? null
              : _second.text.trim().toUpperCase(),
          labelText: l10n.patientsGuardianRelationshipLabel,
          enabled: !_isSaving,
          menuHeight: 360,
          onChanged: (String? value) =>
              setState(() => _second.text = value ?? ''),
          options: _relationshipSelectOptions(_second.text),
        ),
        PatientPhoneField(
          controller: _third,
          labelText: l10n.patientsPhoneLabel,
          enabled: !_isSaving,
        ),
        PatientEmailField(
          controller: _fourth,
          labelText: l10n.patientsEmailLabel,
          enabled: !_isSaving,
        ),
      ],
      PatientRelatedResource.allergy => <Widget>[
        AppTextField(
          controller: _first,
          labelText: l10n.patientsAllergenLabel,
          enabled: !_isSaving,
          isRequired: true,
          validator: AppValidators.requiredText(l10n.validationRequired),
        ),
        AppSelectField<String>(
          value: _choice,
          labelText: l10n.patientsSeverityLabel,
          enabled: !_isSaving,
          isRequired: true,
          validator: AppValidators.requiredValue(l10n.validationRequired),
          onChanged: (String? value) => setState(() => _choice = value),
          options: <AppSelectOption<String>>[
            for (final String value in _severityOptions)
              AppSelectOption<String>(value: value, label: _apiLabel(value)),
          ],
        ),
        AppTextField(
          controller: _second,
          labelText: l10n.patientsReactionLabel,
          enabled: !_isSaving,
        ),
        AppTextField(
          controller: _third,
          labelText: l10n.patientsNotesLabel,
          maxLines: 3,
          enabled: !_isSaving,
        ),
      ],
      PatientRelatedResource.medicalHistory => <Widget>[
        AppTextField(
          controller: _first,
          labelText: l10n.patientsConditionLabel,
          enabled: !_isSaving,
          isRequired: true,
          validator: AppValidators.requiredText(l10n.validationRequired),
        ),
        PatientDateField(
          value: _date,
          firstDate: DateTime(1900),
          lastDate: DateTime.now(),
          labelText: l10n.patientsDiagnosisDateLabel,
          enabled: !_isSaving,
          onChanged: (DateTime? value) => _date = value,
        ),
        AppTextField(
          controller: _second,
          labelText: l10n.patientsNotesLabel,
          maxLines: 3,
          enabled: !_isSaving,
        ),
      ],
      PatientRelatedResource.consent => <Widget>[
        AppSelectField<String>.searchable(
          value: _choice,
          labelText: l10n.patientsConsentTypeLabel,
          enabled: !_isSaving,
          isRequired: true,
          menuHeight: 320,
          validator: AppValidators.requiredValue(l10n.validationRequired),
          onChanged: (String? value) => setState(() => _choice = value),
          options: _consentTypeSelectOptions(
            widget.referenceData.consentTypes.isEmpty
                ? _consentTypes
                : widget.referenceData.consentTypes,
          ),
        ),
        AppSelectField<String>(
          value: _first.text.isEmpty ? null : _first.text,
          labelText: l10n.patientsConsentStatusLabel,
          enabled: !_isSaving,
          isRequired: true,
          validator: AppValidators.requiredValue(l10n.validationRequired),
          onChanged: (String? value) =>
              setState(() => _first.text = value ?? ''),
          options: <AppSelectOption<String>>[
            for (final String value
                in widget.referenceData.consentStatuses.isEmpty
                    ? _consentStates
                    : widget.referenceData.consentStatuses)
              AppSelectOption<String>(value: value, label: _apiLabel(value)),
          ],
        ),
        PatientDateField(
          value: _date,
          firstDate: DateTime(1900),
          lastDate: DateTime.now().add(const Duration(days: 3650)),
          labelText: l10n.patientsConsentDateLabel,
          enabled: !_isSaving,
          onChanged: (DateTime? value) => _date = value,
        ),
      ],
    };
  }

  Widget _contactValueField(BuildContext context) {
    final l10n = context.l10n;
    final String type = (_choice ?? '').toUpperCase();
    if (<String>{'PHONE', 'WHATSAPP', 'FAX'}.contains(type)) {
      return PatientPhoneField(
        controller: _first,
        labelText: l10n.patientsContactValueLabel,
        requiredMessage: l10n.validationRequired,
        enabled: !_isSaving,
        isRequired: true,
      );
    }

    if (type == 'EMAIL') {
      return PatientEmailField(
        controller: _first,
        labelText: l10n.patientsContactValueLabel,
        requiredMessage: l10n.validationRequired,
        enabled: !_isSaving,
        isRequired: true,
      );
    }

    return AppTextField(
      controller: _first,
      labelText: l10n.patientsContactValueLabel,
      enabled: !_isSaving,
      isRequired: true,
      validator: AppValidators.compose<String>(<FormFieldValidator<String>>[
        AppValidators.requiredText(l10n.validationRequired),
        AppValidators.maxLength(
          255,
          l10n.patientsContactInvalidMessage,
          allowEmpty: false,
          trim: true,
        ),
      ]),
    );
  }

  void _hydrate() {
    final Object? item = widget.item;
    switch (item) {
      case final PatientIdentifier value:
        _first.text = value.type;
        _second.text = value.value;
        _isPrimary = value.isPrimary;
      case final PatientContact value:
        _choice = value.type;
        _first.text = value.value;
        _isPrimary = value.isPrimary;
      case final PatientGuardian value:
        _first.text = value.name;
        _second.text = value.relationship ?? '';
        _third.text = value.phone ?? '';
        _fourth.text = value.email ?? '';
      case final PatientAllergy value:
        _first.text = value.allergen;
        _choice = value.severity;
        _second.text = value.reaction ?? '';
        _third.text = value.notes ?? '';
      case final PatientMedicalHistory value:
        _first.text = value.condition;
        _date = value.diagnosisDate;
        _second.text = value.notes ?? '';
      case final PatientConsent value:
        _choice = value.consentType;
        _first.text = value.status;
        _date = value.grantedAt ?? value.revokedAt;
      default:
        _choice = _defaultChoice(widget.resource, widget.referenceData);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _isSaving = true;
      _failure = null;
    });

    final String? recordId = _recordId(widget.item);
    final Map<String, Object?> payload = _payload();
    final AppFailure? failure = recordId == null
        ? await widget.onCreate(payload)
        : await widget.onUpdate(recordId, payload);
    if (!mounted) {
      return;
    }
    if (failure == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _isSaving = false;
      _failure = failure;
    });
  }

  Map<String, Object?> _payload() {
    final Patient patient = widget.detail.patient;
    final Map<String, Object?> createContext = <String, Object?>{
      'tenant_id': patient.tenantId,
      'patient_id': patient.id,
    };

    return switch (widget.resource) {
      PatientRelatedResource.identifier => <String, Object?>{
        ...createContext,
        'identifier_type': _first.text.trim().toUpperCase(),
        'identifier_value': _second.text.trim(),
        'is_primary': _isPrimary,
      },
      PatientRelatedResource.contact => <String, Object?>{
        ...createContext,
        'contact_type': _choice,
        'value': _first.text.trim(),
        'is_primary': _isPrimary,
      },
      PatientRelatedResource.guardian => <String, Object?>{
        ...createContext,
        'name': _first.text.trim(),
        'relationship': _second.text.trim().toUpperCase(),
        'phone': _third.text.trim(),
        'email': _fourth.text.trim(),
      },
      PatientRelatedResource.allergy => <String, Object?>{
        ...createContext,
        'allergen': _first.text.trim(),
        'severity': _choice,
        'reaction': _second.text.trim(),
        'notes': _third.text.trim(),
      },
      PatientRelatedResource.medicalHistory => <String, Object?>{
        ...createContext,
        'condition': _first.text.trim(),
        'diagnosis_date': _date?.toUtc().toIso8601String(),
        'notes': _second.text.trim(),
      },
      PatientRelatedResource.consent => <String, Object?>{
        'patient_id': patient.id,
        'consent_type': _choice,
        'status': _first.text.trim(),
        if (_first.text.trim() == 'GRANTED')
          'granted_at': _date?.toUtc().toIso8601String(),
        if (_first.text.trim() == 'REVOKED')
          'revoked_at': _date?.toUtc().toIso8601String(),
      },
    };
  }
}

Future<bool> _ensurePatientLifecycleOnline(
  BuildContext context,
  WidgetRef ref,
) async {
  final AppConnectivityStatus status =
      ref.read(appConnectivityStatusProvider).value ??
      AppConnectivityStatus.online;
  if (status.isOnline) {
    return true;
  }
  await _showFailureIfNeeded(context, const AppFailure.offline());
  return false;
}

String _patientDeletionCountsSummary(
  AppLocalizations l10n,
  Map<String, int> counts,
) {
  final List<MapEntry<String, int>> entries = counts.entries
      .where((MapEntry<String, int> e) => e.value > 0)
      .toList(growable: false)
    ..sort(
      (MapEntry<String, int> a, MapEntry<String, int> b) =>
          a.key.compareTo(b.key),
    );
  if (entries.isEmpty) {
    return '';
  }
  return entries
      .map(
        (MapEntry<String, int> entry) =>
            '${_patientDeletionCategoryLabel(l10n, entry.key)}: ${entry.value}',
      )
      .join('\n');
}

String _patientDeletionCategoryLabel(AppLocalizations l10n, String raw) {
  final String normalized = raw.trim().toLowerCase().replaceAll('_', ' ');
  if (normalized.isEmpty) {
    return raw;
  }
  return normalized
      .split(' ')
      .where((String part) => part.isNotEmpty)
      .map(
        (String part) =>
            '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}

String _patientDeletionBlockersSummary(
  List<PatientDeletionBlocker> blockers, {
  List<Map<String, Object?>> conflictEntries = const <Map<String, Object?>>[],
}) {
  final List<String> lines = <String>[];
  for (final PatientDeletionBlocker blocker in blockers) {
    final String label = blocker.code.replaceAll('_', ' ');
    lines.add(
      blocker.count > 0 ? '$label (${blocker.count})' : label,
    );
  }
  for (final Map<String, Object?> entry in conflictEntries) {
    final String code = (entry['code'] ?? entry['model'] ?? '').toString();
    if (code.trim().isEmpty) {
      continue;
    }
    final Object? count = entry['count'];
    lines.add(
      count == null
          ? code.replaceAll('_', ' ')
          : '${code.replaceAll('_', ' ')} ($count)',
    );
  }
  return lines.join('\n');
}

Future<void> _confirmSoftDeletePatient(
  BuildContext context,
  WidgetRef ref,
  Patient patient, {
  required bool popDetailOnSuccess,
}) async {
  if (!await _ensurePatientLifecycleOnline(context, ref) || !context.mounted) {
    return;
  }

  final Result<PatientDeletionImpact> impactResult = await ref
      .read(patientRegistryControllerProvider.notifier)
      .getDeletionImpact(patient.id);
  if (!context.mounted) {
    return;
  }

  final AppFailure? impactFailure = impactResult.when(
    success: (_) => null,
    failure: (AppFailure failure) => failure,
  );
  if (impactFailure != null) {
    if (impactFailure is ConflictFailure) {
      await _showPatientDeleteBlockedDialog(
        context,
        patient: patient,
        blockersSummary: _patientDeletionBlockersSummary(
          const <PatientDeletionBlocker>[],
          conflictEntries: impactFailure.conflictEntries,
        ),
      );
      return;
    }
    await _showFailureIfNeeded(context, impactFailure);
    return;
  }

  final PatientDeletionImpact impact =
      (impactResult as ResultSuccess<PatientDeletionImpact>).value;
  if (impact.hasBlockers) {
    await _showPatientDeleteBlockedDialog(
      context,
      patient: patient,
      blockersSummary: _patientDeletionBlockersSummary(impact.blockers),
    );
    return;
  }

  final AppLocalizations l10n = context.l10n;
  final String countsSummary = _patientDeletionCountsSummary(
    l10n,
    impact.counts,
  );
  final String body = countsSummary.isEmpty
      ? l10n.patientsSoftDeleteImpactEmptyBody(patient.effectiveDisplayName)
      : l10n.patientsSoftDeleteImpactBody(
          patient.effectiveDisplayName,
          countsSummary,
        );

  final bool? confirmed = await showAppDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AppConfirmActionDialog(
      title: l10n.patientsDeleteTitle,
      body: body,
      highlightedText: patient.effectiveDisplayName,
      submitLabel: l10n.patientsDeleteAction,
      destructive: true,
      icon: const Icon(Icons.delete_outline),
      onConfirm: () async {
        return ref
            .read(patientRegistryControllerProvider.notifier)
            .deletePatient(patient.id);
      },
      shouldPopOnFailure: (AppFailure failure) => failure is ConflictFailure,
      failurePopValue: false,
    ),
  );
  if (!context.mounted) {
    return;
  }

  final Object? lastFailure = _readCurrentState(ref)?.lastFailure;
  if (lastFailure is ConflictFailure) {
    await _showPatientDeleteBlockedDialog(
      context,
      patient: patient,
      blockersSummary: _patientDeletionBlockersSummary(
        const <PatientDeletionBlocker>[],
        conflictEntries: lastFailure.conflictEntries,
      ),
    );
    return;
  }

  if (confirmed == true) {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String message = l10n.patientsDeletedMessage;
    if (popDetailOnSuccess) {
      await Navigator.of(context).maybePop();
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

Future<void> _showPatientDeleteBlockedDialog(
  BuildContext context, {
  required Patient patient,
  required String blockersSummary,
}) {
  final AppLocalizations l10n = context.l10n;
  return showAppDialog<void>(
    context: context,
    builder: (_) => AppDialog(
      title: Text(l10n.patientsDeleteBlockedTitle),
      icon: const Icon(Icons.warning_amber_outlined),
      content: Text(
        l10n.patientsDeleteBlockedBody(
          patient.effectiveDisplayName,
          blockersSummary.isEmpty ? '—' : blockersSummary,
        ),
      ),
      actions: <Widget>[
        AppButton.close(
          label: l10n.commonCloseActionLabel,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}

Future<void> _confirmRestorePatient(
  BuildContext context,
  WidgetRef ref,
  Patient patient, {
  required bool popDetailOnSuccess,
}) async {
  if (!await _ensurePatientLifecycleOnline(context, ref) || !context.mounted) {
    return;
  }
  final AppLocalizations l10n = context.l10n;
  final bool? confirmed = await showAppDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AppConfirmActionDialog(
      title: l10n.patientsRestoreTitle,
      body: l10n.patientsRestoreBody(patient.effectiveDisplayName),
      highlightedText: patient.effectiveDisplayName,
      submitLabel: l10n.patientsRestoreAction,
      icon: const Icon(Icons.restore_outlined),
      onConfirm: () {
        return ref
            .read(patientRegistryControllerProvider.notifier)
            .restorePatient(patient.id);
      },
    ),
  );
  if (!context.mounted || confirmed != true) {
    return;
  }
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final String message = l10n.patientsRestoredMessage;
  if (popDetailOnSuccess) {
    await Navigator.of(context).maybePop();
  }
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

Future<void> _confirmPermanentDeletePatient(
  BuildContext context,
  WidgetRef ref,
  Patient patient, {
  required bool popDetailOnSuccess,
}) async {
  if (!await _ensurePatientLifecycleOnline(context, ref) || !context.mounted) {
    return;
  }
  final AppLocalizations l10n = context.l10n;
  final String confirmName = patient.effectiveDisplayName.trim().isEmpty
      ? (patient.publicId ?? patient.id)
      : patient.effectiveDisplayName.trim();

  final String? typed = await showAppDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AppTextInputActionDialog(
      title: l10n.tenantFacilityPermanentDeleteConfirmationTitle,
      description: l10n.patientsPermanentDeleteWarningBody(confirmName),
      fieldLabel: l10n.tenantFacilityPermanentDeleteConfirmFieldLabel(
        confirmName,
      ),
      submitLabel: l10n.tenantFacilityPermanentDeleteConfirmAction,
      cancelLabel: l10n.commonCancelActionLabel,
      requiredMessage: l10n.validationRequired,
      confirmExactValue: confirmName,
      confirmMismatchMessage: l10n
          .tenantFacilityPermanentDeleteConfirmFieldLabel(confirmName),
      destructive: true,
      minLines: 1,
      maxLines: 1,
      icon: const Icon(Icons.delete_forever_outlined),
    ),
  );
  if (!context.mounted || typed == null) {
    return;
  }
  if (typed.trim().toLowerCase() != confirmName.toLowerCase()) {
    return;
  }

  final bool? confirmed = await showAppDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AppConfirmActionDialog(
      title: l10n.tenantFacilityPermanentDeleteConfirmationTitle,
      body: l10n.patientsPermanentDeleteConfirmationBody(confirmName),
      highlightedText: confirmName,
      submitLabel: l10n.tenantFacilityPermanentDeleteConfirmAction,
      destructive: true,
      icon: const Icon(Icons.delete_forever_outlined),
      onConfirm: () {
        return ref
            .read(patientRegistryControllerProvider.notifier)
            .permanentDeletePatient(patient.id);
      },
    ),
  );
  if (!context.mounted || confirmed != true) {
    return;
  }
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final String message = l10n.patientsPermanentlyDeletedMessage;
  if (popDetailOnSuccess) {
    await Navigator.of(context).maybePop();
  }
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

Future<bool?> _showDeleteDialog(
  BuildContext context, {
  required String title,
  required String body,
}) {
  final l10n = context.l10n;

  return showAppDialog<bool>(
    context: context,
    builder: (_) => AppDialog(
      title: Text(title),
      icon: const Icon(Icons.warning_amber_outlined),
      content: Text(body),
      actions: <Widget>[
        AppButton.close(
          leadingIcon: AppActionIcons.cancel,
          label: l10n.commonCancelActionLabel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton.primary(
          label: l10n.patientsDeleteAction,
          leadingIcon: Icons.delete_outline,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
}

PatientRegistryState? _readCurrentState(WidgetRef ref) {
  final Result<PatientRegistryState>? result = ref
      .read(patientRegistryControllerProvider)
      .asData
      ?.value;
  return switch (result) {
    ResultSuccess<PatientRegistryState>(value: final value) => value,
    _ => null,
  };
}

Future<void> _showFailureIfNeeded(
  BuildContext context,
  AppFailure? failure,
) async {
  if (failure == null) {
    return;
  }
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(context.l10n.failureMessage(failure))));
}

PatientRelatedResource _resourceForItem<T>(T? item) {
  if (item is PatientIdentifier || T == PatientIdentifier) {
    return PatientRelatedResource.identifier;
  }
  if (item is PatientContact || T == PatientContact) {
    return PatientRelatedResource.contact;
  }
  if (item is PatientGuardian || T == PatientGuardian) {
    return PatientRelatedResource.guardian;
  }
  if (item is PatientAllergy || T == PatientAllergy) {
    return PatientRelatedResource.allergy;
  }
  if (item is PatientMedicalHistory || T == PatientMedicalHistory) {
    return PatientRelatedResource.medicalHistory;
  }
  return PatientRelatedResource.consent;
}

PatientRelatedResource _resourceForRecordId(
  PatientDetail detail,
  String recordId,
) {
  if (detail.identifiers.any((PatientIdentifier item) => item.id == recordId)) {
    return PatientRelatedResource.identifier;
  }
  if (detail.contacts.any((PatientContact item) => item.id == recordId)) {
    return PatientRelatedResource.contact;
  }
  if (detail.guardians.any((PatientGuardian item) => item.id == recordId)) {
    return PatientRelatedResource.guardian;
  }
  if (detail.allergies.any((PatientAllergy item) => item.id == recordId)) {
    return PatientRelatedResource.allergy;
  }
  if (detail.medicalHistories.any(
    (PatientMedicalHistory item) => item.id == recordId,
  )) {
    return PatientRelatedResource.medicalHistory;
  }
  return PatientRelatedResource.consent;
}

String? _recordId(Object? item) {
  return switch (item) {
    final PatientIdentifier value => value.id,
    final PatientContact value => value.id,
    final PatientGuardian value => value.id,
    final PatientAllergy value => value.id,
    final PatientMedicalHistory value => value.id,
    final PatientConsent value => value.id,
    _ => null,
  };
}

String? _defaultChoice(
  PatientRelatedResource resource,
  PatientReferenceData referenceData,
) {
  return switch (resource) {
    PatientRelatedResource.contact => 'PHONE',
    PatientRelatedResource.allergy => 'MILD',
    PatientRelatedResource.consent =>
      referenceData.consentTypes.firstOrNull ?? _consentTypes.first,
    _ => null,
  };
}

IconData _resourceIcon(PatientRelatedResource resource) {
  return switch (resource) {
    PatientRelatedResource.identifier => Icons.badge_outlined,
    PatientRelatedResource.contact => Icons.contact_phone_outlined,
    PatientRelatedResource.guardian => Icons.supervisor_account_outlined,
    PatientRelatedResource.allergy => Icons.warning_amber_outlined,
    PatientRelatedResource.medicalHistory => Icons.history_edu_outlined,
    PatientRelatedResource.consent => Icons.assignment_turned_in_outlined,
  };
}

String? _statusValue(bool? active) {
  return active == null
      ? null
      : active
      ? _statusActive
      : _statusInactive;
}

bool? _activeValue(String? status) {
  return switch (status) {
    _statusActive => true,
    _statusInactive => false,
    _ => null,
  };
}

List<String> _filterConsentStatuses(PatientRegistryState? state) {
  final List<String> values =
      state?.referenceData.consentStatuses ?? const <String>[];
  return values.isEmpty ? _consentStates : values;
}

String _genderLabel(AppLocalizations l10n, String value) {
  return switch (value.toUpperCase()) {
    'MALE' => l10n.patientsGenderMale,
    'FEMALE' => l10n.patientsGenderFemale,
    'OTHER' => l10n.patientsGenderOther,
    'UNKNOWN' => l10n.patientsGenderUnknown,
    _ => _apiLabel(value),
  };
}

String _formatOptionalDate(BuildContext context, DateTime? value) {
  return value == null
      ? context.l10n.profileUnknownValue
      : AppFormatters.mediumDate(value, Localizations.localeOf(context));
}

String _formatOptionalDateTime(BuildContext context, DateTime? value) {
  return value == null
      ? ''
      : AppFormatters.dateTime(value, Localizations.localeOf(context));
}

List<AppTriageOption> _statusTriageOptions(Iterable<String> values) {
  return <AppTriageOption>[
    for (final String value in values)
      AppTriageOption(
        value: value,
        label: _apiLabel(value),
        tone: appTriageToneForValue(value),
        icon: appTriageIconForValue(value),
      ),
  ];
}

List<AppSelectOption<String>> _providerSelectOptions(
  List<OpdProviderOption> providers, {
  List<OpdProviderSchedule> schedules = const <OpdProviderSchedule>[],
}) {
  return opdProviderSelectOptions(providers: providers, schedules: schedules);
}

Map<String, Object?> _withoutEmptyPayload(Map<String, Object?> payload) {
  return <String, Object?>{
    for (final MapEntry<String, Object?> entry in payload.entries)
      if (!_payloadValueIsEmpty(entry.value)) entry.key: entry.value,
  };
}

bool _payloadValueIsEmpty(Object? value) {
  if (value == null) {
    return true;
  }
  if (value is String) {
    return value.trim().isEmpty;
  }
  if (value is Iterable) {
    return value.isEmpty;
  }
  if (value is Map) {
    return value.isEmpty;
  }
  return false;
}

T? _successOrNull<T>(Result<T> result) {
  return result.when(success: (T value) => value, failure: (_) => null);
}

AppFailure? _failureOrNull<T>(Result<T> result) {
  return result.when(
    success: (_) => null,
    failure: (AppFailure value) => value,
  );
}

String _workflowFailureMessage(BuildContext context, AppFailure failure) {
  return failure.displayMessage(context.l10n);
}

String _apiLabel(String value) {
  return AppDisplay.apiLabel(value);
}

List<String> _identifierTypeOptions(String currentValue) {
  final String normalized = currentValue.trim().toUpperCase();
  if (normalized.isEmpty || _identifierTypes.contains(normalized)) {
    return _identifierTypes;
  }

  return <String>[normalized, ..._identifierTypes];
}

List<AppSelectOption<String>> _identifierTypeSelectOptions(
  String currentValue,
) {
  return <AppSelectOption<String>>[
    for (final String value in _identifierTypeOptions(currentValue))
      AppSelectOption<String>(
        value: value,
        label: _apiLabel(value),
        leadingIcon: Icon(_identifierTypeIcon(value)),
      ),
  ];
}

String? _selectedIdentifierType(String currentValue) {
  final String normalized = currentValue.trim().toUpperCase();
  return normalized.isEmpty ? null : normalized;
}

List<AppSelectOption<String>> _contactTypeSelectOptions() {
  return <AppSelectOption<String>>[
    for (final String value in _contactTypes)
      AppSelectOption<String>(
        value: value,
        label: _apiLabel(value),
        leadingIcon: Icon(_contactTypeIcon(value)),
      ),
  ];
}

List<AppSelectOption<String>> _relationshipSelectOptions(String currentValue) {
  final String normalized = currentValue.trim().toUpperCase();
  final List<String> values =
      normalized.isEmpty || _relationshipTypes.contains(normalized)
      ? _relationshipTypes
      : <String>[normalized, ..._relationshipTypes];
  return <AppSelectOption<String>>[
    for (final String value in values)
      AppSelectOption<String>(
        value: value,
        label: _apiLabel(value),
        leadingIcon: Icon(_relationshipIcon(value)),
      ),
  ];
}

List<AppSelectOption<String>> _consentTypeSelectOptions(
  Iterable<String> values,
) {
  return <AppSelectOption<String>>[
    for (final String value in values)
      AppSelectOption<String>(
        value: value,
        label: _apiLabel(value),
        leadingIcon: Icon(_consentTypeIcon(value)),
      ),
  ];
}

List<AppSelectOption<bool>> _booleanFilterOptions(AppLocalizations l10n) {
  return <AppSelectOption<bool>>[
    AppSelectOption<bool>(
      value: true,
      label: l10n.patientsYesFilterLabel,
      leadingIcon: const Icon(Icons.check_circle_outline),
    ),
    AppSelectOption<bool>(
      value: false,
      label: l10n.patientsNoFilterLabel,
      leadingIcon: const Icon(Icons.block_outlined),
    ),
  ];
}

IconData _identifierTypeIcon(String value) {
  return switch (value.toUpperCase()) {
    'MRN' => Icons.local_hospital_outlined,
    'NATIONAL_ID' => Icons.credit_card_outlined,
    'PASSPORT' => Icons.flight_takeoff_outlined,
    'INSURANCE' => Icons.health_and_safety_outlined,
    'DRIVER_LICENSE' => Icons.badge_outlined,
    'BIRTH_CERTIFICATE' => Icons.child_care_outlined,
    _ => Icons.perm_identity_outlined,
  };
}

IconData _appointmentStatusIcon(String value) {
  return switch (value.toUpperCase()) {
    'SCHEDULED' => Icons.event_available_outlined,
    'CONFIRMED' => Icons.verified_outlined,
    'IN_PROGRESS' => Icons.pending_actions_outlined,
    'COMPLETED' => Icons.check_circle_outline,
    'CANCELLED' => Icons.cancel_outlined,
    'NO_SHOW' => Icons.event_busy_outlined,
    _ => Icons.event_note_outlined,
  };
}

IconData _contactTypeIcon(String value) {
  return switch (value.toUpperCase()) {
    'PHONE' => Icons.phone_outlined,
    'EMAIL' => Icons.alternate_email_outlined,
    'WHATSAPP' => Icons.chat_outlined,
    'TELEGRAM' => Icons.send_outlined,
    'FAX' => Icons.print_outlined,
    'FACEBOOK' => Icons.groups_outlined,
    'LINKEDIN' => Icons.work_outline,
    'X' => Icons.public_outlined,
    'YOUTUBE' => Icons.play_circle_outline,
    'DISCORD' => Icons.forum_outlined,
    _ => Icons.contact_mail_outlined,
  };
}

IconData _relationshipIcon(String value) {
  return switch (value.toUpperCase()) {
    'SPOUSE' || 'PARTNER' => Icons.favorite_border,
    'PARENT' || 'MOTHER' || 'FATHER' => Icons.family_restroom_outlined,
    'CHILD' || 'SON' || 'DAUGHTER' => Icons.child_care_outlined,
    'SIBLING' || 'BROTHER' || 'SISTER' => Icons.people_alt_outlined,
    'GUARDIAN' || 'CAREGIVER' => Icons.supervisor_account_outlined,
    'NEXT_OF_KIN' => Icons.contact_emergency_outlined,
    _ => Icons.person_outline,
  };
}

IconData _consentTypeIcon(String value) {
  return switch (value.toUpperCase()) {
    'TREATMENT' => Icons.medical_services_outlined,
    'DATA_SHARING' => Icons.share_outlined,
    'RESEARCH' => Icons.science_outlined,
    'BILLING' => Icons.receipt_long_outlined,
    _ => Icons.verified_user_outlined,
  };
}

String _joinDisplay(Iterable<String?> values) {
  return AppDisplay.joinNonEmpty(values);
}

const List<String> _identifierTypes = <String>[
  'MRN',
  'NATIONAL_ID',
  'PASSPORT',
  'INSURANCE',
  'DRIVER_LICENSE',
  'BIRTH_CERTIFICATE',
  'OTHER',
];
const List<String> _contactTypes = <String>[
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
  'OTHER',
];
const List<String> _relationshipTypes = <String>[
  'SPOUSE',
  'PARTNER',
  'PARENT',
  'MOTHER',
  'FATHER',
  'CHILD',
  'SON',
  'DAUGHTER',
  'SIBLING',
  'BROTHER',
  'SISTER',
  'GRANDPARENT',
  'GRANDCHILD',
  'AUNT',
  'UNCLE',
  'COUSIN',
  'GUARDIAN',
  'CAREGIVER',
  'NEXT_OF_KIN',
  'FRIEND',
  'OTHER',
];
const List<String> _severityOptions = <String>['MILD', 'MODERATE', 'SEVERE'];
const List<String> _emergencySeverityOptions = <String>[
  'LOW',
  'MEDIUM',
  'HIGH',
  'CRITICAL',
];
const List<String> _triageLevelOptions = <String>[
  'LEVEL_1',
  'LEVEL_2',
  'LEVEL_3',
  'LEVEL_4',
  'LEVEL_5',
  'IMMEDIATE',
  'URGENT',
  'LESS_URGENT',
  'NON_URGENT',
];
const List<String> _consentStates = <String>['GRANTED', 'REVOKED', 'PENDING'];
const List<String> _consentTypes = <String>[
  'TREATMENT',
  'DATA_SHARING',
  'RESEARCH',
  'BILLING',
  'OTHER',
];
final DateTime _patientFilterFirstDate = DateTime(1900);
final DateTime _patientFilterLastDate = DateTime.now().add(
  const Duration(days: 730),
);
const String _statusActive = 'active';
const String _statusInactive = 'inactive';
