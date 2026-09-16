import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/app/router/app_route_icons.dart';
import 'package:hosspi_hms/app/router/app_routes.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/core/config/app_config_provider.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/permissions/access_policy.dart';
import 'package:hosspi_hms/core/permissions/app_permission.dart';
import 'package:hosspi_hms/core/permissions/permission_providers.dart';
import 'package:hosspi_hms/core/responsive/app_breakpoints.dart';
import 'package:hosspi_hms/core/utils/app_media_url.dart';
import 'package:hosspi_hms/core/utils/app_slug.dart';
import 'package:hosspi_hms/features/access_admin/domain/entities/access_admin_entities.dart';
import 'package:hosspi_hms/features/access_admin/presentation/widgets/access_admin_management_dialogs.dart';
import 'package:hosspi_hms/features/tenant_facility/data/repositories/tenant_facility_repository_impl.dart';
import 'package:hosspi_hms/features/tenant_facility/domain/entities/bed_similarity.dart';
import 'package:hosspi_hms/features/tenant_facility/domain/entities/department_similarity.dart';
import 'package:hosspi_hms/features/tenant_facility/domain/entities/facility_similarity.dart';
import 'package:hosspi_hms/features/tenant_facility/domain/entities/room_similarity.dart';
import 'package:hosspi_hms/features/tenant_facility/domain/entities/tenant_facility_setup.dart';
import 'package:hosspi_hms/features/tenant_facility/domain/entities/tenant_similarity.dart';
import 'package:hosspi_hms/features/tenant_facility/domain/entities/unit_similarity.dart';
import 'package:hosspi_hms/features/tenant_facility/domain/entities/ward_similarity.dart';
import 'package:hosspi_hms/features/tenant_facility/domain/repositories/tenant_facility_repository.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/controllers/tenant_facility_setup_controller.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/tenant_facility_setup_access.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/widgets/bed_details_dialog.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/widgets/bed_similarity_dialog.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/widgets/department_details_dialog.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/widgets/department_similarity_dialog.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/widgets/facility_catalog_config_panel.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/widgets/facility_similarity_dialog.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/widgets/manage_subscription_activations_panel.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/widgets/manage_subscription_approvals_panel.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/widgets/room_details_dialog.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/widgets/room_similarity_dialog.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/widgets/tenant_facility_management_dialogs.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/widgets/tenant_facility_setup_helpers.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/widgets/tenant_facility_setup_print_helpers.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/widgets/tenant_similarity_dialog.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/widgets/unit_details_dialog.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/widgets/unit_similarity_dialog.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/widgets/ward_details_dialog.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/widgets/ward_similarity_dialog.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/actions/app_action_dialogs.dart';
import 'package:hosspi_hms/shared/components/components.dart';
import 'package:hosspi_hms/shared/data/data.dart';
import 'package:hosspi_hms/shared/forms/forms.dart';
import 'package:hosspi_hms/shared/layout/layout.dart';
import 'package:hosspi_hms/shared/management/platform_admin_list_config.dart';
import 'package:hosspi_hms/shared/routing/workspace_location_sync.dart';

class TenantFacilitySetupPage extends ConsumerWidget {
  const TenantFacilitySetupPage({super.key, this.initialQuery});

  /// Deep-link targeting parsed from the `/admin/setup` route query string.
  final TenantFacilitySetupPageQuery? initialQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<Result<FacilitySetupSnapshot>> setup = ref.watch(
      tenantFacilitySetupControllerProvider,
    );

    ref.listen<int>(
      tenantFacilitySetupSubmissionProvider.select(
        (TenantFacilitySetupSubmissionState state) => state.successVersion,
      ),
      (int? previous, int next) {
        if (previous == null || next <= previous || !context.mounted) {
          return;
        }

        _showSaved(context);
      },
    );

    return AsyncStateScaffold<FacilitySetupSnapshot>(
      value: setup,
      loadingTitle: l10n.tenantFacilitySetupLoadingTitle,
      loadingBody: l10n.tenantFacilitySetupLoadingBody,
      maxWidth: PageMaxWidth.dashboard,
      centerVertically: false,
      scrollable: false,
      onRetry: () {
        ref.read(tenantFacilitySetupControllerProvider.notifier).refresh();
      },
      dataBuilder: (BuildContext context, FacilitySetupSnapshot snapshot) {
        return _TenantFacilitySetupContent(
          snapshot: snapshot,
          initialQuery: initialQuery,
        );
      },
    );
  }
}

class _TenantFacilitySetupContent extends ConsumerWidget {
  const _TenantFacilitySetupContent({
    required this.snapshot,
    this.initialQuery,
  });

  final FacilitySetupSnapshot snapshot;
  final TenantFacilitySetupPageQuery? initialQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final accessPolicy = ref.watch(appAccessPolicyProvider);
    final bool canManageTenant = accessPolicy.canManageTenant();
    final bool canManageFacility = accessPolicy.canManageFacility();
    final bool canEditStructure = accessPolicy.canEditFacilitySetupStructure();
    final bool canManageAccess = accessPolicy.grantsAny(const <AppPermission>[
      AppPermissions.platformAdmin,
      AppPermissions.tenantAdmin,
      AppPermissions.facilityAdmin,
      AppPermissions.hrWrite,
    ]);
    final bool isElevated = accessPolicy.isElevated;

    return AppWorkspace(
      title: tenantFacilitySetupWorkspaceTitle(accessPolicy, l10n),
      leadingIcon: AppRouteIcons.setup,
      maxWidth: PageMaxWidth.dataHeavy,
      scrollable: false,
      toolbar: appWorkspaceToolbarWithLabels(
        l10n,
        showGlobalActions: false,
        showFaultReport: false,
        showHousekeepingRequest: false,
      ),
      body: _SetupBody(
        snapshot: snapshot,
        initialQuery: initialQuery,
        canManageTenant: canManageTenant,
        canManageFacility: canManageFacility,
        canEditStructure: canEditStructure,
        canManageAccess: canManageAccess,
        isElevated: isElevated,
      ),
    );
  }
}

typedef _ProfileFormSubmitRegistrar =
    void Function(
      Future<bool> Function() submit, {
      bool Function()? canSave,
      VoidCallback? onFormStateChanged,
    });

typedef _SetupProfileFormBuilder =
    Widget Function(
      BuildContext context,
      FacilitySetupSnapshot snapshot,
      bool canManageTenant,
      bool canManageFacility,
      bool canEditHrStructure,
      _ProfileFormSubmitRegistrar registerSubmitHandler,
      VoidCallback onDialogStateChanged,
    );

class _SetupProfileDialog extends ConsumerStatefulWidget {
  const _SetupProfileDialog({
    required this.title,
    required this.icon,
    required this.saveLabel,
    required this.formBuilder,
    this.managementSnapshot,
  });

  final String title;
  final IconData icon;
  final String saveLabel;
  final _SetupProfileFormBuilder formBuilder;
  final FacilitySetupSnapshot? managementSnapshot;

  @override
  ConsumerState<_SetupProfileDialog> createState() =>
      _SetupProfileDialogState();
}

class _SetupProfileDialogState extends ConsumerState<_SetupProfileDialog> {
  Future<bool> Function()? _submitHandler;
  bool Function()? _canSaveChecker;

  void _registerSubmitHandler(
    Future<bool> Function() submit, {
    bool Function()? canSave,
    VoidCallback? onFormStateChanged,
  }) {
    _submitHandler = submit;
    _canSaveChecker = canSave;
    if (mounted) {
      setState(() {});
    }
  }

  void _handleFormStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _handleSave() async {
    final Future<bool> Function()? submit = _submitHandler;
    if (submit == null) {
      return;
    }
    final bool saved = await submit();
    if (!mounted || !saved) {
      return;
    }

    final Object? savedEntity = ref
        .read(tenantFacilitySetupSubmissionProvider)
        .lastSavedEntity;
    if (widget.managementSnapshot == null) {
      _showSaved(context);
    }
    if (savedEntity is TenantProfile) {
      Navigator.of(context).pop<TenantProfile>(savedEntity);
      return;
    }
    if (savedEntity is FacilityProfile) {
      Navigator.of(context).pop<FacilityProfile>(savedEntity);
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final accessPolicy = ref.watch(appAccessPolicyProvider);
    final TenantFacilitySetupSubmissionState submission = ref.watch(
      tenantFacilitySetupSubmissionProvider,
    );
    final setup = ref.watch(tenantFacilitySetupControllerProvider);
    final FacilitySetupSnapshot? managementSnapshot = widget.managementSnapshot;
    final Widget content = managementSnapshot != null
        ? widget.formBuilder(
            context,
            managementSnapshot,
            accessPolicy.canManageTenant(),
            accessPolicy.canManageFacility(),
            accessPolicy.canEditFacilitySetupStructure(),
            _registerSubmitHandler,
            _handleFormStateChanged,
          )
        : setup.when(
            data: (result) => result.when(
              success: (FacilitySetupSnapshot snapshot) => widget.formBuilder(
                context,
                snapshot,
                accessPolicy.canManageTenant(),
                accessPolicy.canManageFacility(),
                accessPolicy.canEditFacilitySetupStructure(),
                _registerSubmitHandler,
                _handleFormStateChanged,
              ),
              failure: (AppFailure failure) => AppFailureStateView(
                failure: failure,
                onRetry: () {
                  ref
                      .read(tenantFacilitySetupControllerProvider.notifier)
                      .refresh();
                },
              ),
            ),
            error: (Object error, StackTrace stackTrace) => AppFailureStateView(
              failure: _setupFailure(error),
              onRetry: () {
                ref
                    .read(tenantFacilitySetupControllerProvider.notifier)
                    .refresh();
              },
            ),
            loading: () => AppStateView(
              variant: AppStateViewVariant.loading,
              title: l10n.tenantFacilitySetupLoadingTitle,
              body: l10n.tenantFacilitySetupLoadingBody,
            ),
          );

    return AppDialog(
      title: Text(widget.title),
      icon: Icon(widget.icon),
      scrollable: true,
      pinActionsToBottom: true,
      maxWidth: 880,
      closeEnabled: !submission.isSubmitting,
      content: content,
      actions: <Widget>[
        AppButton.close(
          label: l10n.commonCancelActionLabel,
          leadingIcon: Icons.close,
          enabled: !submission.isSubmitting,
          onPressed: submission.isSubmitting
              ? null
              : () => Navigator.of(context).pop(),
        ),
        AppButton.primary(
          label: widget.saveLabel,
          leadingIcon: Icons.save_outlined,
          isLoading: submission.isSubmitting,
          onPressed:
              submission.isSubmitting || !(_canSaveChecker?.call() ?? true)
              ? null
              : _handleSave,
        ),
      ],
    );
  }
}

Future<TenantProfile?> _openTenantProfileModal(
  BuildContext context, {
  TenantProfile? tenant,
  bool forceCreate = false,
  bool managementMode = false,
}) {
  final AppLocalizations l10n = context.l10n;
  const FacilitySetupSnapshot managementSnapshot = FacilitySetupSnapshot();
  ProviderScope.containerOf(
    context,
  ).read(tenantFacilitySetupSubmissionProvider.notifier).clearFailure();

  return showAppDialog<TenantProfile>(
    context: context,
    builder: (BuildContext dialogContext) => Consumer(
      builder: (BuildContext context, WidgetRef ref, _) {
        final AppAccessPolicy accessPolicy = ref.watch(appAccessPolicyProvider);
        final String dialogTitle = forceCreate
            ? l10n.tenantFacilityCreateTenantTitle
            : tenant != null
            ? l10n.tenantFacilityEditTenantTitle
            : l10n.tenantFacilityTenantSectionTitle;
        final String saveLabel = forceCreate
            ? l10n.tenantFacilityCreateTenantAction
            : l10n.tenantFacilitySaveTenantAction;

        return _SetupProfileDialog(
          title: dialogTitle,
          icon: Icons.apartment_outlined,
          saveLabel: saveLabel,
          managementSnapshot: managementMode ? managementSnapshot : null,
          formBuilder:
              (
                BuildContext context,
                FacilitySetupSnapshot snapshot,
                bool canManageTenant,
                bool canManageFacility,
                bool canEditHrStructure,
                _ProfileFormSubmitRegistrar registerSubmitHandler,
                VoidCallback onDialogStateChanged,
              ) {
                final TenantProfile? formTenant = forceCreate
                    ? null
                    : (tenant ?? snapshot.tenant);
                final bool isCreate = forceCreate || formTenant == null;

                return _TenantProfileForm(
                  tenant: formTenant,
                  canSubmit: isCreate
                      ? accessPolicy.canCreateTenant()
                      : canManageTenant,
                  framed: false,
                  isCreate: isCreate,
                  sectionBody: isCreate
                      ? l10n.tenantFacilityCreateTenantBody
                      : l10n.tenantFacilityTenantSectionBody,
                  permissionDeniedMessage: isCreate
                      ? l10n.tenantFacilityCreateTenantPermissionRequired
                      : l10n.tenantFacilityPermissionRequired,
                  hideSubmitButton: true,
                  refreshSetupAfterSave: !managementMode,
                  updateSetupSnapshot: !managementMode,
                  registerSubmitHandler: registerSubmitHandler,
                  onDialogStateChanged: onDialogStateChanged,
                );
              },
        );
      },
    ),
  );
}

Future<FacilityProfile?> _openFacilityProfileModal(
  BuildContext context, {
  String? tenantId,
  FacilityProfile? facility,
  bool requireTenantPicker = false,
  bool managementMode = false,
}) {
  final AppLocalizations l10n = context.l10n;
  final bool isCreate = facility == null;
  const FacilitySetupSnapshot managementSnapshot = FacilitySetupSnapshot();
  ProviderScope.containerOf(
    context,
  ).read(tenantFacilitySetupSubmissionProvider.notifier).clearFailure();

  return showAppDialog<FacilityProfile>(
    context: context,
    builder: (BuildContext dialogContext) => Consumer(
      builder: (BuildContext context, WidgetRef ref, _) {
        return _SetupProfileDialog(
          title: isCreate
              ? l10n.tenantFacilityCreateFacilityTitle
              : l10n.tenantFacilityEditFacilityTitle,
          icon: isCreate ? Icons.add_business_outlined : Icons.edit_outlined,
          saveLabel: isCreate
              ? l10n.tenantFacilitySaveFacilityAction
              : l10n.tenantFacilityEditFacilityAction,
          managementSnapshot: managementMode ? managementSnapshot : null,
          formBuilder:
              (
                BuildContext context,
                FacilitySetupSnapshot snapshot,
                bool canManageTenant,
                bool canManageFacility,
                bool canEditHrStructure,
                _ProfileFormSubmitRegistrar registerSubmitHandler,
                VoidCallback onDialogStateChanged,
              ) => _FacilityProfileForm(
                snapshot: snapshot,
                canSubmit: canManageFacility,
                framed: false,
                tenantId: tenantId,
                facility: facility,
                requireTenantPicker: requireTenantPicker,
                hideSubmitButton: true,
                refreshSetupAfterSave: !managementMode,
                registerSubmitHandler: registerSubmitHandler,
                onDialogStateChanged: onDialogStateChanged,
              ),
        );
      },
    ),
  );
}

AppFailure _setupFailure(Object error) {
  if (error is AppFailure) {
    return error;
  }

  return const AppFailure.unexpected();
}

class _SetupBody extends ConsumerStatefulWidget {
  const _SetupBody({
    required this.snapshot,
    required this.canManageTenant,
    required this.canManageFacility,
    required this.canEditStructure,
    required this.canManageAccess,
    required this.isElevated,
    this.initialQuery,
  });

  final FacilitySetupSnapshot snapshot;
  final TenantFacilitySetupPageQuery? initialQuery;
  final bool canManageTenant;
  final bool canManageFacility;
  final bool canEditStructure;
  final bool canManageAccess;
  final bool isElevated;

  @override
  ConsumerState<_SetupBody> createState() => _SetupBodyState();
}

class _SetupBodyState extends ConsumerState<_SetupBody> {
  TenantFacilitySetupDeskSection? _section;
  final Set<TenantFacilitySetupDeskSection> _mountedSections =
      <TenantFacilitySetupDeskSection>{};
  final Map<TenantFacilitySetupDeskSection, int> _liveSectionCounts =
      <TenantFacilitySetupDeskSection, int>{};

  void _setLiveSectionCount(TenantFacilitySetupDeskSection section, int count) {
    if (_liveSectionCounts[section] == count) {
      return;
    }
    setState(() {
      _liveSectionCounts[section] = count;
    });
  }

  List<TenantFacilitySetupDeskSection> get _visibleSections {
    return tenantFacilityVisibleSetupDeskSections(
      canManageTenant: widget.canManageTenant,
      canManageFacility: widget.canManageFacility,
      canManageAccess: widget.canManageAccess,
      isElevated: widget.isElevated,
    );
  }

  TenantFacilitySetupDeskSection get _currentSection {
    final List<TenantFacilitySetupDeskSection> sections = _visibleSections;
    if (sections.isEmpty) {
      return TenantFacilitySetupDeskSection.facility;
    }
    final TenantFacilitySetupDeskSection? selected = _section;
    if (selected != null && sections.contains(selected)) {
      return selected;
    }
    return sections.first;
  }

  @override
  void initState() {
    super.initState();
    _section = TenantFacilitySetupDeskSection.fromQuery(
      widget.initialQuery?.section ?? '',
    );
    _mountedSections.add(_currentSection);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _syncUrlToCurrentSection();
    });
  }

  @override
  void didUpdateWidget(covariant _SetupBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String previous =
        oldWidget.initialQuery?.signature ?? '';
    final String next = widget.initialQuery?.signature ?? '';
    if (previous == next) {
      return;
    }
    final TenantFacilitySetupDeskSection? fromRoute =
        TenantFacilitySetupDeskSection.fromQuery(
          widget.initialQuery?.section ?? '',
        );
    if (fromRoute != null && fromRoute != _section) {
      setState(() {
        _section = fromRoute;
        _mountedSections.add(fromRoute);
      });
    }
  }

  void _refreshSetup() {
    unawaited(
      ref.read(tenantFacilitySetupControllerProvider.notifier).refresh(),
    );
  }

  void _updateUrlForSection(TenantFacilitySetupDeskSection section) {
    if (!mounted) {
      return;
    }
    final String tab = section.routeQueryValue;
    final String location = AppRoutes.tenantFacilitySetup.location(
      queryParameters: <String, String>{if (tab.isNotEmpty) 'section': tab},
    );
    syncWorkspaceLocation(context, location);
  }

  void _syncUrlToCurrentSection() {
    final TenantFacilitySetupDeskSection current = _currentSection;
    final TenantFacilitySetupDeskSection? fromRoute =
        TenantFacilitySetupDeskSection.fromQuery(
          widget.initialQuery?.section ?? '',
        );
    if (fromRoute == current) {
      return;
    }
    _updateUrlForSection(current);
  }

  void _handleTabChanged(TenantFacilitySetupDeskSection section) {
    if (section == _currentSection) {
      return;
    }
    setState(() {
      _section = section;
      _mountedSections.add(section);
    });
    _updateUrlForSection(section);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final List<TenantFacilitySetupDeskSection> sections = _visibleSections;
    final TenantFacilitySetupDeskSection current = _currentSection;
    final AppAccessPolicy accessPolicy = ref.watch(appAccessPolicyProvider);

    if (sections.isEmpty) {
      return AppWorkspaceStatePanel.empty(
        title: l10n.tenantFacilitySetupTitle,
        body: l10n.tenantFacilitySetupBody,
      );
    }

    final int currentIndex = sections.indexOf(current);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppTabStrip(
          tabs: <AppTabItem>[
            for (final TenantFacilitySetupDeskSection section in sections)
              AppTabItem(
                id: section.name,
                icon: tenantFacilitySetupDeskSectionIcon(section),
                label: tenantFacilitySetupDeskSectionLabel(
                  l10n,
                  section,
                  policy: accessPolicy,
                ),
                count: tenantFacilitySetupDeskSectionCount(
                  section: section,
                  snapshot: widget.snapshot,
                  liveCount: _liveSectionCounts[section],
                ),
                countTone: section ==
                            TenantFacilitySetupDeskSection
                                .subscriptionApprovals ||
                        section ==
                            TenantFacilitySetupDeskSection
                                .subscriptionActivations
                    ? AppTabCountTone.warning
                    : AppTabCountTone.info,
              ),
          ],
          selectedId: current.name,
          onTabTapped: (String tabId) {
            for (final TenantFacilitySetupDeskSection section in sections) {
              if (section.name == tabId) {
                _handleTabChanged(section);
                break;
              }
            }
          },
        ),
        SizedBox(height: theme.spacing.sm),
        Expanded(
          child: IndexedStack(
            index: currentIndex < 0 ? 0 : currentIndex,
            sizing: StackFit.expand,
            children: <Widget>[
              for (final TenantFacilitySetupDeskSection section in sections)
                _mountedSections.contains(section)
                    ? _SetupTabKeepAlive(
                        key: ValueKey<String>('setup-tab-${section.name}'),
                        child: _buildTabBody(section),
                      )
                    : const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabBody(TenantFacilitySetupDeskSection section) {
    final FacilitySetupSnapshot snapshot = widget.snapshot;
    // Permission only — each section gates Add on its own prerequisites
    // (e.g. departments require a facility) so the Add control stays visible.
    final bool canSubmitStructure = widget.canEditStructure;

    return switch (section) {
      TenantFacilitySetupDeskSection.tenants => ManageTenantsPanel(
        sessionTenant: snapshot.tenant,
        initialSubscriptionFilter: widget.initialQuery?.subscription,
        onMutated: (_) => _refreshSetup(),
        onListTotalChanged: (int count) =>
            _setLiveSectionCount(TenantFacilitySetupDeskSection.tenants, count),
      ),
      TenantFacilitySetupDeskSection.facility => ManageFacilitiesPanel(
        sessionFacility: snapshot.facility,
        sessionTenantId: snapshot.tenant?.id ?? snapshot.facility?.tenantId,
        onMutated: (_) => _refreshSetup(),
        onListTotalChanged: (int count) =>
            _setLiveSectionCount(TenantFacilitySetupDeskSection.facility, count),
      ),
      TenantFacilitySetupDeskSection.departments => _DepartmentSetupSection(
        snapshot: snapshot,
        canSubmit: canSubmitStructure,
        onListTotalChanged: (int count) => _setLiveSectionCount(
          TenantFacilitySetupDeskSection.departments,
          count,
        ),
      ),
      TenantFacilitySetupDeskSection.units => _UnitSetupSection(
        snapshot: snapshot,
        canSubmit: canSubmitStructure,
        onListTotalChanged: (int count) =>
            _setLiveSectionCount(TenantFacilitySetupDeskSection.units, count),
      ),
      TenantFacilitySetupDeskSection.wards => _WardSetupSection(
        snapshot: snapshot,
        canSubmit: canSubmitStructure,
        onListTotalChanged: (int count) =>
            _setLiveSectionCount(TenantFacilitySetupDeskSection.wards, count),
      ),
      TenantFacilitySetupDeskSection.rooms => _RoomSetupSection(
        snapshot: snapshot,
        canSubmit: canSubmitStructure,
        onListTotalChanged: (int count) =>
            _setLiveSectionCount(TenantFacilitySetupDeskSection.rooms, count),
      ),
      TenantFacilitySetupDeskSection.beds => _BedSetupSection(
        snapshot: snapshot,
        canSubmit: canSubmitStructure,
        onListTotalChanged: (int count) =>
            _setLiveSectionCount(TenantFacilitySetupDeskSection.beds, count),
      ),
      TenantFacilitySetupDeskSection.clinicalCatalog =>
          _buildClinicalCatalogBody(snapshot),
      TenantFacilitySetupDeskSection.roles => ManageRolesPermissionsPanel(
        onListTotalChanged: (int count) =>
            _setLiveSectionCount(TenantFacilitySetupDeskSection.roles, count),
      ),
      TenantFacilitySetupDeskSection.permissions => ManageRolesPermissionsPanel(
        panel: AccessAdminPanel.permissions,
        onListTotalChanged: (int count) => _setLiveSectionCount(
          TenantFacilitySetupDeskSection.permissions,
          count,
        ),
      ),
      TenantFacilitySetupDeskSection.users => ManageUsersPanel(
        onListTotalChanged: (int count) =>
            _setLiveSectionCount(TenantFacilitySetupDeskSection.users, count),
      ),
      TenantFacilitySetupDeskSection.subscriptionApprovals =>
        ManageSubscriptionApprovalsPanel(
          onListTotalChanged: (int count) => _setLiveSectionCount(
            TenantFacilitySetupDeskSection.subscriptionApprovals,
            count,
          ),
        ),
      TenantFacilitySetupDeskSection.subscriptionActivations =>
        ManageSubscriptionActivationsPanel(
          onListTotalChanged: (int count) => _setLiveSectionCount(
            TenantFacilitySetupDeskSection.subscriptionActivations,
            count,
          ),
        ),
    };
  }

  Widget _buildClinicalCatalogBody(FacilitySetupSnapshot snapshot) {
    final String? facilityId = snapshot.facility?.id.trim();
    final String? tenantId =
        (snapshot.facility?.tenantId ?? snapshot.tenant?.id)?.trim();

    return FacilityCatalogConfigPanel(
      facilityId: facilityId?.isEmpty == true ? null : facilityId,
      tenantId: tenantId?.isEmpty == true ? null : tenantId,
      defaultCurrency: resolveDefaultCurrency(
        facilityCurrency: snapshot.facility?.currency,
        tenantCurrency: snapshot.tenant?.currency,
      ),
      enabled: widget.canManageFacility || widget.canManageTenant,
      onListTotalChanged: (int count) => _setLiveSectionCount(
        TenantFacilitySetupDeskSection.clinicalCatalog,
        count,
      ),
    );
  }
}

class _SetupTabKeepAlive extends StatefulWidget {
  const _SetupTabKeepAlive({required this.child, super.key});

  final Widget child;

  @override
  State<_SetupTabKeepAlive> createState() => _SetupTabKeepAliveState();
}

class _SetupTabKeepAliveState extends State<_SetupTabKeepAlive>
    with AutomaticKeepAliveClientMixin<_SetupTabKeepAlive> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _TenantProfileForm extends ConsumerStatefulWidget {
  const _TenantProfileForm({
    required this.tenant,
    required this.canSubmit,
    this.framed = true,
    this.isCreate = false,
    this.sectionBody,
    this.permissionDeniedMessage,
    this.hideSubmitButton = false,
    this.refreshSetupAfterSave = true,
    this.updateSetupSnapshot = true,
    this.registerSubmitHandler,
    this.onDialogStateChanged,
  });

  final TenantProfile? tenant;
  final bool canSubmit;
  final bool framed;
  final bool isCreate;
  final String? sectionBody;
  final String? permissionDeniedMessage;
  final bool hideSubmitButton;
  final bool refreshSetupAfterSave;
  final bool updateSetupSnapshot;
  final _ProfileFormSubmitRegistrar? registerSubmitHandler;
  final VoidCallback? onDialogStateChanged;

  @override
  ConsumerState<_TenantProfileForm> createState() => _TenantProfileFormState();
}

class _TenantProfileFormState extends ConsumerState<_TenantProfileForm> {
  static const AppPageRequest _duplicateLookupRequest = AppPageRequest(
    pageSize: 100,
  );

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _slugController;
  late final TextEditingController _contactNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _feeController;
  late bool _isActive;
  late String _currency;
  bool _slugManuallyEdited = false;
  String? _nameErrorText;
  String? _slugErrorText;
  List<TenantSimilarityMatch> _similarMatches = const <TenantSimilarityMatch>[];
  bool _similarityAccepted = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.tenant?.name);
    _slugController = TextEditingController(text: widget.tenant?.slug);
    _contactNameController = TextEditingController(
      text: widget.tenant?.contactName,
    );
    _phoneController = TextEditingController(text: widget.tenant?.contactPhone);
    _emailController = TextEditingController(text: widget.tenant?.contactEmail);
    _feeController = TextEditingController(
      text: resolveDefaultConsultationFee(
        fee: widget.tenant?.standardConsultationFee,
      ),
    );
    _isActive = widget.tenant?.isActive ?? true;
    _currency = resolveDefaultCurrency(tenantCurrency: widget.tenant?.currency);
    _slugManuallyEdited =
        widget.tenant?.slug != null && widget.tenant!.slug!.trim().isNotEmpty;
    _nameController.addListener(_handleNameChanged);
    _slugController.addListener(_handleSlugChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.registerSubmitHandler?.call(_submit);
    });
  }

  @override
  void didUpdateWidget(_TenantProfileForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.registerSubmitHandler != widget.registerSubmitHandler ||
        oldWidget.tenant?.id != widget.tenant?.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        widget.registerSubmitHandler?.call(_submit);
      });
    }
    if (oldWidget.tenant?.id != widget.tenant?.id) {
      _nameController.text = widget.tenant?.name ?? '';
      _slugController.text = widget.tenant?.slug ?? '';
      _contactNameController.text = widget.tenant?.contactName ?? '';
      _phoneController.text = widget.tenant?.contactPhone ?? '';
      _emailController.text = widget.tenant?.contactEmail ?? '';
      _feeController.text = resolveDefaultConsultationFee(
        fee: widget.tenant?.standardConsultationFee,
      );
      _isActive = widget.tenant?.isActive ?? true;
      _currency = resolveDefaultCurrency(
        tenantCurrency: widget.tenant?.currency,
      );
      _slugManuallyEdited =
          widget.tenant?.slug != null && widget.tenant!.slug!.trim().isNotEmpty;
      _clearDuplicateState();
    }
  }

  @override
  void dispose() {
    _nameController
      ..removeListener(_handleNameChanged)
      ..dispose();
    _slugController
      ..removeListener(_handleSlugChanged)
      ..dispose();
    _contactNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _feeController.dispose();
    super.dispose();
  }

  void _handleNameChanged() {
    _clearDuplicateState();
    if (!widget.isCreate || _slugManuallyEdited) {
      return;
    }

    final String slug = slugify(_nameController.text);
    if (_slugController.text != slug) {
      _slugController.text = slug;
    }
  }

  void _handleSlugChanged() {
    _clearDuplicateState();
    if (!widget.isCreate) {
      return;
    }

    final String autoSlug = slugify(_nameController.text);
    final String currentSlug = _slugController.text.trim();
    _slugManuallyEdited = currentSlug.isNotEmpty && currentSlug != autoSlug;
  }

  void _clearDuplicateState() {
    if (_nameErrorText == null &&
        _slugErrorText == null &&
        _similarMatches.isEmpty &&
        !_similarityAccepted) {
      return;
    }

    setState(() {
      _nameErrorText = null;
      _slugErrorText = null;
      _similarMatches = const <TenantSimilarityMatch>[];
      _similarityAccepted = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final submission = ref.watch(tenantFacilitySetupSubmissionProvider);
    final String sectionBody =
        widget.sectionBody ?? l10n.tenantFacilityTenantSectionBody;
    final bool fieldsEnabled = widget.canSubmit && !submission.isSubmitting;
    final String? displayId = widget.tenant?.displayId?.trim();
    final String resolvedCurrency = resolveDefaultCurrency(
      tenantCurrency: _currency,
    );

    final Widget form = Form(
      key: _formKey,
      child: AppFormSection(
        children: <Widget>[
          AppResponsiveFieldRow.two(
            gap: AppResponsiveFieldRowGap.form,
            left: AppTextField(
              controller: _nameController,
              enabled: fieldsEnabled,
              labelText: l10n.tenantFacilityTenantNameLabel,
              isRequired: true,
              textCapitalization: TextCapitalization.words,
              errorText: _nameErrorText,
              validator: AppValidators.requiredText(l10n.validationRequired),
            ),
            right: AppTextField(
              controller: _slugController,
              enabled: fieldsEnabled,
              labelText: l10n.tenantFacilityTenantSlugLabel,
              errorText: _slugErrorText,
            ),
          ),
          if (!widget.isCreate &&
              displayId != null &&
              displayId.isNotEmpty)
            AppTextField(
              initialValue: displayId,
              enabled: false,
              readOnly: true,
              labelText: l10n.tenantFacilityTenantDetailsIdLabel,
            ),
          AppSwitchField(
            title: l10n.tenantFacilityActiveLabel,
            subtitle: _isActive
                ? l10n.tenantFacilityActiveSubtitleActive
                : l10n.tenantFacilityActiveSubtitleInactive,
            semanticLabel: l10n.tenantFacilityActiveLabel,
            value: _isActive,
            enabled: fieldsEnabled,
            onChanged: (bool value) {
              setState(() {
                _isActive = value;
              });
              _clearDuplicateState();
            },
          ),
          AppResponsiveFieldRow.two(
            gap: AppResponsiveFieldRowGap.form,
            left: AppTextField(
              controller: _contactNameController,
              enabled: fieldsEnabled,
              labelText: l10n.tenantFacilityTenantDetailsContactNameLabel,
              isRequired: widget.isCreate,
              textCapitalization: TextCapitalization.words,
              validator: widget.isCreate
                  ? AppValidators.requiredText(l10n.validationRequired)
                  : null,
              onChanged: (_) => _clearDuplicateState(),
            ),
            right: AppPhoneField(
              controller: _phoneController,
              enabled: fieldsEnabled,
              labelText: l10n.profilePhoneLabel,
              countryLabelText: l10n.appPhoneCountryLabel,
              countrySearchLabelText: l10n.appPhoneCountrySearchLabel,
              countryNoResultsText: l10n.appPhoneCountryNoResults,
              numberLabelText: l10n.appPhoneNumberLabel,
              numberHintText: l10n.appPhoneNumberHint,
              invalidPhoneMessage: l10n.appPhoneInvalidMessage,
              requiredMessage: l10n.validationRequired,
              isRequired: widget.isCreate,
              onChanged: (_) => _clearDuplicateState(),
            ),
          ),
          AppResponsiveFieldRow.two(
            gap: AppResponsiveFieldRowGap.form,
            left: AppEmailField(
              controller: _emailController,
              enabled: fieldsEnabled,
              labelText: l10n.profileEmailLabel,
              requiredMessage: l10n.validationRequired,
              invalidEmailMessage: l10n.authEmailInvalidMessage,
              isRequired: widget.isCreate,
              onChanged: (_) => _clearDuplicateState(),
            ),
            right: AppCurrencySelectField(
              value: _currency,
              enabled: fieldsEnabled,
              labelText: l10n.tenantFacilityDefaultCurrencyLabel,
              helperText: l10n.tenantFacilityTenantDefaultCurrencyHelper,
              onChanged: (String? value) {
                if (value == null || value.trim().isEmpty) {
                  return;
                }
                setState(() {
                  _currency = value.trim().toUpperCase();
                });
                _clearDuplicateState();
              },
            ),
          ),
          AppCurrencyAmountField(
            amountController: _feeController,
            currency: resolvedCurrency,
            onCurrencyChanged: (String? value) {
              if (value == null || value.trim().isEmpty) {
                return;
              }
              setState(() {
                _currency = value.trim().toUpperCase();
              });
              _clearDuplicateState();
            },
            amountLabelText: l10n.settingsConfigurationConsultationFeeLabel,
            currencyLabelText: l10n.tenantFacilityDefaultCurrencyLabel,
            helperText: l10n.settingsConfigurationConsultationFeeHelper,
            enabled: fieldsEnabled,
            onAmountChanged: (_) => _clearDuplicateState(),
          ),
          if (!widget.hideSubmitButton)
            _SubmitButton(
              enabled: widget.canSubmit,
              isLoading: submission.isSubmitting,
              label: widget.isCreate
                  ? l10n.tenantFacilityCreateTenantAction
                  : l10n.tenantFacilitySaveTenantAction,
              onPressed: _submit,
              permissionDeniedMessage: widget.permissionDeniedMessage,
            )
          else
            _SubmissionFeedback(
              enabled: widget.canSubmit,
              failure: _inlineSubmissionFailure(submission.failure),
              permissionDeniedMessage: widget.permissionDeniedMessage,
            ),
        ],
      ),
    );

    if (widget.framed) {
      return AppCollapsibleSection(
        title: widget.isCreate
            ? l10n.tenantFacilityCreateTenantTitle
            : l10n.tenantFacilityTenantSectionTitle,
        description: sectionBody,
        child: form,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          sectionBody,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: theme.spacing.lg),
        form,
      ],
    );
  }

  Future<bool> _submit() async {
    if (_formKey.currentState?.validate() != true) {
      return false;
    }

    final bool canProceed = await _guardAgainstDuplicates();
    if (!canProceed) {
      return false;
    }

    final String fee = _feeController.text.trim();
    final bool saved = await ref
        .read(tenantFacilitySetupSubmissionProvider.notifier)
        .saveTenant(
          id: widget.isCreate ? null : widget.tenant?.mutationId,
          name: _nameController.text,
          slug: _slugController.text,
          isActive: _isActive,
          currency: resolveDefaultCurrency(tenantCurrency: _currency),
          standardConsultationFee: fee.isEmpty ? null : fee,
          clearStandardConsultationFee: fee.isEmpty,
          contactName: _contactNameController.text,
          contactEmail: _emailController.text,
          contactPhone: _phoneController.text,
          confirmSimilar: _similarityAccepted,
          refreshSetup: widget.refreshSetupAfterSave,
          updateSetupSnapshot: widget.updateSetupSnapshot,
        );
    if (!mounted) {
      return false;
    }
    if (saved) {
      return true;
    }

    final AppFailure? failure = ref
        .read(tenantFacilitySetupSubmissionProvider)
        .failure;
    if (!_isTenantSimilarityConflict(failure)) {
      return false;
    }

    // Backend similarity is authoritative. Clear the inline conflict message and
    // reopen the dedicated results dialog so the user can review and confirm.
    ref.read(tenantFacilitySetupSubmissionProvider.notifier).clearFailure();
    setState(() {
      _similarityAccepted = false;
    });
    final bool confirmed = await _guardAgainstDuplicates(
      forceReviewMatches: true,
    );
    if (!confirmed || !mounted) {
      return false;
    }
    return ref
        .read(tenantFacilitySetupSubmissionProvider.notifier)
        .saveTenant(
          id: widget.isCreate ? null : widget.tenant?.mutationId,
          name: _nameController.text,
          slug: _slugController.text,
          isActive: _isActive,
          currency: resolveDefaultCurrency(tenantCurrency: _currency),
          standardConsultationFee: fee.isEmpty ? null : fee,
          clearStandardConsultationFee: fee.isEmpty,
          contactName: _contactNameController.text,
          contactEmail: _emailController.text,
          contactPhone: _phoneController.text,
          confirmSimilar: true,
          refreshSetup: widget.refreshSetupAfterSave,
          updateSetupSnapshot: widget.updateSetupSnapshot,
        );
  }

  AppFailure? _inlineSubmissionFailure(AppFailure? failure) {
    if (_isTenantSimilarityConflict(failure)) {
      return null;
    }
    return failure;
  }

  bool _isTenantSimilarityConflict(AppFailure? failure) {
    if (failure == null || failure.category != AppFailureCategory.conflict) {
      return false;
    }
    final String detail = (failure.detailMessage ?? '').toLowerCase();
    return detail.contains('similar tenant') ||
        detail.contains('confirm to create anyway') ||
        detail.contains('duplicate_slug') ||
        failure.validationFields.contains('slug') ||
        failure.validationFields.contains('name');
  }

  TenantSimilarityProposedValues _proposedValues() {
    return TenantSimilarityProposedValues(
      name: _nameController.text.trim(),
      slug: _slugController.text.trim().isEmpty
          ? null
          : _slugController.text.trim(),
      contactName: _contactNameController.text.trim().isEmpty
          ? null
          : _contactNameController.text.trim(),
      contactPhone: _phoneController.text.trim().isEmpty
          ? null
          : _phoneController.text.trim(),
      contactEmail: _emailController.text.trim().isEmpty
          ? null
          : _emailController.text.trim(),
      currency: resolveDefaultCurrency(tenantCurrency: _currency),
      standardConsultationFee: _feeController.text.trim().isEmpty
          ? null
          : _feeController.text.trim(),
    );
  }

  Future<bool> _guardAgainstDuplicates({
    bool forceReviewMatches = false,
  }) async {
    final List<TenantProfile> existing = await _loadExistingTenants();
    final TenantDuplicateCheckResult result = checkTenantDuplicates(
      name: _nameController.text,
      slug: _slugController.text,
      existing: existing,
      excludeTenantId: widget.tenant?.mutationId ?? widget.tenant?.id,
      contactName: _contactNameController.text,
      contactEmail: _emailController.text,
      contactPhone: _phoneController.text,
      currency: resolveDefaultCurrency(tenantCurrency: _currency),
      standardConsultationFee: _feeController.text,
    );

    final bool exactSlugConflict = result.exactSlugConflict;
    final List<TenantSimilarityMatch> reviewMatches = exactSlugConflict
        ? result.similarMatches
              .where((TenantSimilarityMatch match) => match.exactSlugConflict)
              .toList(growable: false)
        : result.overridableMatches;

    if (!mounted) {
      return false;
    }

    // Edit saves with no conflicting peers should not open the empty review
    // dialog; create still shows the no-similar confirmation path.
    if (!widget.isCreate &&
        !forceReviewMatches &&
        !exactSlugConflict &&
        reviewMatches.isEmpty) {
      setState(() {
        _nameErrorText = null;
        _slugErrorText = null;
        _similarMatches = const <TenantSimilarityMatch>[];
        _similarityAccepted = false;
      });
      return true;
    }

    setState(() {
      _nameErrorText = null;
      _slugErrorText = exactSlugConflict
          ? context.l10n.tenantFacilityTenantSlugAlreadyInUse
          : null;
      _similarMatches = const <TenantSimilarityMatch>[];
      if (exactSlugConflict) {
        _similarityAccepted = false;
      }
    });

    final TenantSimilarityDialogResult decision =
        await showTenantSimilarityDialog(
          context,
          proposed: _proposedValues(),
          matches: reviewMatches,
          allowProceed: !exactSlugConflict,
        );
    if (!mounted) {
      return false;
    }

    switch (decision.action) {
      case TenantSimilarityAction.cancel:
        setState(() {
          _similarityAccepted = false;
        });
        return false;
      case TenantSimilarityAction.useExisting:
        final TenantProfile? existingTenant = decision.selectedTenant;
        if (existingTenant != null) {
          Navigator.of(context).pop<TenantProfile>(existingTenant);
        }
        return false;
      case TenantSimilarityAction.proceed:
        setState(() {
          _similarityAccepted = reviewMatches.isNotEmpty || forceReviewMatches;
          _nameErrorText = null;
          _slugErrorText = null;
        });
        return true;
    }
  }

  Future<List<TenantProfile>> _loadExistingTenants() async {
    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );
    final String name = _nameController.text.trim();
    final String slug = _slugController.text.trim();
    final Set<String> seenIds = <String>{};
    final List<TenantProfile> tenants = <TenantProfile>[];

    Future<void> appendMatches(String? search) async {
      final Result<AppPage<TenantProfile>> result = await repository
          .listTenants(request: _duplicateLookupRequest, search: search);
      result.when(
        success: (AppPage<TenantProfile> page) {
          for (final TenantProfile tenant in page.items) {
            if (seenIds.add(tenant.id)) {
              tenants.add(tenant);
            }
          }
        },
        failure: (_) {},
      );
    }

    // Always include an unfiltered page so sparse name/slug searches do not
    // miss candidates the backend similarity check would still catch.
    await appendMatches(null);
    if (name.isNotEmpty) {
      await appendMatches(name);
    }
    if (slug.isNotEmpty && slug != name) {
      await appendMatches(slug);
    }

    return tenants;
  }
}

class _FacilityProfileForm extends ConsumerStatefulWidget {
  const _FacilityProfileForm({
    required this.snapshot,
    required this.canSubmit,
    this.framed = true,
    this.tenantId,
    this.facility,
    this.requireTenantPicker = false,
    this.hideSubmitButton = false,
    this.refreshSetupAfterSave = true,
    this.registerSubmitHandler,
    this.onDialogStateChanged,
  });

  final FacilitySetupSnapshot snapshot;
  final bool canSubmit;
  final bool framed;
  final String? tenantId;
  final FacilityProfile? facility;
  final bool requireTenantPicker;
  final bool hideSubmitButton;
  final bool refreshSetupAfterSave;
  final _ProfileFormSubmitRegistrar? registerSubmitHandler;
  final VoidCallback? onDialogStateChanged;

  @override
  ConsumerState<_FacilityProfileForm> createState() =>
      _FacilityProfileFormState();
}

class _FacilityProfileFormState extends ConsumerState<_FacilityProfileForm> {
  static const AppPageRequest _duplicateLookupRequest = AppPageRequest(
    pageSize: 100,
  );

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressLineController;
  late final TextEditingController _cityController;
  late final TextEditingController _feeController;
  late FacilitySetupType _type;
  late bool _isActive;
  late String _currency;
  String? _existingLogoUrl;
  String? _logoFileName;
  List<int>? _logoBytes;
  String? _logoMimeType;
  bool _logoCleared = false;
  AppImageUploadPendingItem? _pendingLogoItem;
  String? _selectedTenantId;
  String? _selectedCountry;
  List<TenantProfile> _tenantOptions = const <TenantProfile>[];
  bool _loadingTenants = false;
  bool _loadingContact = false;
  FacilityEffectiveContact? _hydratedInheritedContact;
  AppFailure? _tenantLoadFailure;
  String? _nameErrorText;
  List<FacilitySimilarityMatch> _similarMatches =
      const <FacilitySimilarityMatch>[];
  bool _similarityAccepted = false;

  String _baselineName = '';
  FacilitySetupType _baselineType = FacilitySetupType.hospital;
  bool _baselineIsActive = true;
  String _baselineCurrency = appDefaultCurrencyCode;
  String? _baselineFee;
  String? _baselinePhone;
  String? _baselineEmail;
  String? _baselineAddressLine1;
  String? _baselineCity;
  String? _baselineCountry;
  String? _baselineLogoUrl;

  FacilityProfile? get _activeFacility => widget.facility;

  bool get _isCreate => widget.facility == null;

  String? get _resolvedTenantId {
    if (widget.requireTenantPicker) {
      return _selectedTenantId ?? widget.tenantId;
    }

    return _selectedTenantId ??
        widget.tenantId ??
        widget.snapshot.tenant?.mutationId ??
        widget.snapshot.tenant?.id ??
        _activeFacility?.tenantId;
  }

  /// Prefer a UUID mutation id when the selected tenant is known by public id.
  String _resolveMutationTenantId(String tenantId) {
    final String normalized = tenantId.trim();
    if (normalized.isEmpty) {
      return normalized;
    }

    final TenantProfile? fromOptions = _tenantOptions
        .where(
          (TenantProfile tenant) =>
              tenant.id == normalized ||
              tenant.mutationId == normalized ||
              tenant.displayId == normalized ||
              tenant.slug == normalized,
        )
        .firstOrNull;
    if (fromOptions != null) {
      return fromOptions.mutationId;
    }

    final TenantProfile? fromSnapshot = widget.snapshot.tenant;
    if (fromSnapshot != null &&
        (fromSnapshot.id == normalized ||
            fromSnapshot.mutationId == normalized ||
            fromSnapshot.displayId == normalized ||
            fromSnapshot.slug == normalized)) {
      return fromSnapshot.mutationId;
    }

    return normalized;
  }

  bool get _hasSelectedTenant => (_resolvedTenantId ?? '').trim().isNotEmpty;

  bool _canSave() => widget.canSubmit && _hasSelectedTenant;

  @override
  void initState() {
    super.initState();
    final FacilityProfile? facility = _activeFacility;
    // Create must start blank — never inherit contact/logo from setup snapshot.
    final FacilityContactAddress contact = _isCreate
        ? const FacilityContactAddress()
        : widget.snapshot.contactAddress;
    _selectedTenantId =
        widget.tenantId ??
        (_isCreate ? null : widget.snapshot.tenant?.id) ??
        facility?.tenantId;
    _nameController = TextEditingController(text: facility?.name ?? '');
    _existingLogoUrl = facility?.logoUrl;
    _phoneController = TextEditingController(text: contact.phone ?? '');
    _emailController = TextEditingController(text: contact.email ?? '');
    _addressLineController = TextEditingController(
      text: contact.addressLine1 ?? '',
    );
    _cityController = TextEditingController(text: contact.city ?? '');
    _feeController = TextEditingController(
      text: facility?.standardConsultationFee ?? '',
    );
    _selectedCountry = contact.country;
    _type = facility?.type ?? FacilitySetupType.hospital;
    _isActive = facility?.isActive ?? true;
    _currency = resolveDefaultCurrency(
      facilityCurrency: facility?.currency,
      tenantCurrency: widget.snapshot.tenant?.currency,
    );
    _captureBaseline();
    _nameController.addListener(_handleNameChanged);
    if (widget.requireTenantPicker) {
      unawaited(_loadTenantOptions());
    }
    if (!_isCreate) {
      unawaited(_hydrateEditContact());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerWithDialog();
    });
  }

  void _captureBaseline() {
    _baselineName = _nameController.text.trim();
    _baselineType = _type;
    _baselineIsActive = _isActive;
    _baselineCurrency = _currency.trim().toUpperCase();
    _baselineFee = _normalizedOptional(
      normalizeCurrencyAmount(_feeController.text),
    );
    _baselinePhone = _normalizedOptional(_phoneController.text);
    _baselineEmail = _normalizedOptional(_emailController.text);
    _baselineAddressLine1 = _normalizedOptional(_addressLineController.text);
    _baselineCity = _normalizedOptional(_cityController.text);
    _baselineCountry = _normalizedOptional(_selectedCountry);
    _baselineLogoUrl = _logoCleared
        ? null
        : _normalizedOptional(_existingLogoUrl);
  }

  static String? _normalizedOptional(String? value) {
    final String? normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static bool _isSameFacility(FacilityProfile? left, FacilityProfile right) {
    return left != null &&
        (left.id == right.id || left.mutationId == right.mutationId);
  }

  /// Tenant phone/email the facility falls back to for fields it leaves empty.
  static FacilityEffectiveContact _inheritedContactFor(
    FacilitySetupSnapshot snapshot,
  ) {
    return FacilityEffectiveContact.resolve(
      inherited: snapshot.effectiveContact ?? snapshot.facility?.effectiveContact,
      tenantPhone: snapshot.tenant?.contactPhone,
      tenantEmail: snapshot.tenant?.contactEmail,
    );
  }

  /// Inherited contact for the edited facility. Only ever shown as a hint, so
  /// saving never writes a tenant value as the facility's own.
  FacilityEffectiveContact get _inheritedContact {
    final FacilityProfile? facility = _activeFacility;
    if (facility == null) {
      return const FacilityEffectiveContact();
    }
    if (_isSameFacility(widget.snapshot.facility, facility)) {
      return _inheritedContactFor(widget.snapshot);
    }
    return _hydratedInheritedContact ??
        FacilityEffectiveContact.resolve(inherited: facility.effectiveContact);
  }

  /// Hint for an empty own field that inherits the tenant value. Hidden once
  /// the facility has its own value, since edits keep a saved value.
  String? _inheritedHint({
    required String current,
    required String? baseline,
    required String? inherited,
    required String Function(String value) hint,
  }) {
    final String? inheritedValue = _normalizedOptional(inherited);
    if (_isCreate ||
        inheritedValue == null ||
        baseline != null ||
        _normalizedOptional(current) != null) {
      return null;
    }
    return hint(inheritedValue);
  }

  String _coalescePreserved(String current, String? baseline) {
    final String? normalized = _normalizedOptional(current);
    if (normalized != null) {
      return normalized;
    }
    return baseline ?? '';
  }

  String? _coalesceOptionalPreserved(String? current, String? baseline) {
    final String? normalized = _normalizedOptional(current);
    return normalized ?? baseline;
  }

  Future<void> _hydrateEditContact() async {
    final FacilityProfile? facility = _activeFacility;
    if (facility == null) {
      return;
    }
    final FacilityProfile editingFacility = facility;

    final FacilityContactAddress existing = widget.snapshot.contactAddress;
    final bool contactMissing =
        _normalizedOptional(existing.phone) == null &&
        _normalizedOptional(existing.email) == null &&
        _normalizedOptional(existing.addressLine1) == null &&
        _normalizedOptional(existing.city) == null &&
        _normalizedOptional(existing.country) == null;
    final bool logoMissing = _normalizedOptional(_existingLogoUrl) == null;

    if (!contactMissing && !logoMissing) {
      _captureBaseline();
      return;
    }

    setState(() {
      _loadingContact = true;
    });

    final Result<FacilitySetupSnapshot> result = await ref
        .read(tenantFacilityRepositoryProvider)
        .loadSetup(
          facilityId: editingFacility.mutationId,
          tenantId: editingFacility.tenantId,
        );

    if (!mounted) {
      return;
    }

    result.when(
      success: (FacilitySetupSnapshot snapshot) {
        final FacilityContactAddress contact = snapshot.contactAddress;
        final FacilityProfile loadedFacility =
            snapshot.facility ?? editingFacility;
        setState(() {
          _loadingContact = false;
          if (_isSameFacility(snapshot.facility, editingFacility)) {
            _hydratedInheritedContact = _inheritedContactFor(snapshot);
          }
          if (_normalizedOptional(_nameController.text) == null &&
              loadedFacility.name.trim().isNotEmpty) {
            _nameController.text = loadedFacility.name;
          }
          _type = loadedFacility.type;
          _isActive = loadedFacility.isActive;
          _currency = resolveDefaultCurrency(
            facilityCurrency: loadedFacility.currency,
            tenantCurrency:
                snapshot.tenant?.currency ?? widget.snapshot.tenant?.currency,
          );
          if (_normalizedOptional(_feeController.text) == null &&
              _normalizedOptional(loadedFacility.standardConsultationFee) !=
                  null) {
            _feeController.text = loadedFacility.standardConsultationFee ?? '';
          }
          if (logoMissing) {
            _existingLogoUrl = loadedFacility.logoUrl;
          }
          if (contactMissing) {
            _phoneController.text = contact.phone ?? '';
            _emailController.text = contact.email ?? '';
            _addressLineController.text = contact.addressLine1 ?? '';
            _cityController.text = contact.city ?? '';
            _selectedCountry = contact.country;
          }
          _captureBaseline();
        });
        _notifyDialogState();
      },
      failure: (_) {
        setState(() {
          _loadingContact = false;
        });
        _captureBaseline();
      },
    );
  }

  void _registerWithDialog() {
    widget.registerSubmitHandler?.call(
      _submit,
      canSave: _canSave,
      onFormStateChanged: widget.onDialogStateChanged,
    );
  }

  void _handleNameChanged() {
    if (_nameErrorText != null ||
        _similarMatches.isNotEmpty ||
        _similarityAccepted) {
      setState(() {
        _nameErrorText = null;
        _similarMatches = const <FacilitySimilarityMatch>[];
        _similarityAccepted = false;
      });
      widget.onDialogStateChanged?.call();
    }
  }

  void _notifyDialogState() {
    if (!mounted) {
      return;
    }
    _registerWithDialog();
    widget.onDialogStateChanged?.call();
  }

  Future<void> _loadTenantOptions() async {
    setState(() {
      _loadingTenants = true;
      _tenantLoadFailure = null;
    });
    final result = await ref
        .read(tenantFacilityRepositoryProvider)
        .listTenants(request: const AppPageRequest(pageSize: 100));
    if (!mounted) return;
    result.when(
      success: (AppPage<TenantProfile> page) {
        setState(() {
          _loadingTenants = false;
          _tenantOptions = page.items;
          if (widget.tenantId != null && widget.tenantId!.trim().isNotEmpty) {
            _selectedTenantId = widget.tenantId;
          }
        });
        _notifyDialogState();
      },
      failure: (AppFailure failure) {
        setState(() {
          _loadingTenants = false;
          _tenantLoadFailure = failure;
        });
        _notifyDialogState();
      },
    );
  }

  @override
  void didUpdateWidget(_FacilityProfileForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hideSubmitButton) {
      return;
    }
    if (oldWidget.snapshot.facility?.id != widget.snapshot.facility?.id) {
      _nameController.text = widget.snapshot.facility?.name ?? '';
      _existingLogoUrl = widget.snapshot.facility?.logoUrl;
      _logoFileName = null;
      _logoBytes = null;
      _logoMimeType = null;
      _logoCleared = false;
      _pendingLogoItem = null;
      _phoneController.text = widget.snapshot.contactAddress.phone ?? '';
      _emailController.text = widget.snapshot.contactAddress.email ?? '';
      _addressLineController.text =
          widget.snapshot.contactAddress.addressLine1 ?? '';
      _cityController.text = widget.snapshot.contactAddress.city ?? '';
      _selectedCountry = widget.snapshot.contactAddress.country;
      _type = widget.snapshot.facility?.type ?? FacilitySetupType.hospital;
      _isActive = widget.snapshot.facility?.isActive ?? true;
      _currency = resolveDefaultCurrency(
        facilityCurrency: widget.snapshot.facility?.currency,
        tenantCurrency: widget.snapshot.tenant?.currency,
      );
      _feeController.text =
          widget.snapshot.facility?.standardConsultationFee ?? '';
      _captureBaseline();
      _notifyDialogState();
    }
  }

  @override
  void dispose() {
    _nameController
      ..removeListener(_handleNameChanged)
      ..dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressLineController.dispose();
    _cityController.dispose();
    _feeController.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    if (!_hasSelectedTenant) {
      return;
    }
    final String facilityName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : (_activeFacility?.name ?? 'facility');
    final AppImageUploadPendingItem? picked = await pickAppImageFile(
      context.l10n,
      context: context,
      typeGroupLabel: 'facility-logo',
      showCropAspectPresets: true,
      preferredFileName: buildFacilityLogoFileName(facilityName),
    );
    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _pendingLogoItem = picked;
      _logoFileName = picked.fileName;
      _logoBytes = picked.bytes;
      _logoMimeType = picked.mimeType;
      _logoCleared = false;
    });
  }

  void _clearLogo() {
    setState(() {
      _pendingLogoItem = null;
      _logoFileName = null;
      _logoBytes = null;
      _logoMimeType = null;
      _existingLogoUrl = null;
      _logoCleared = true;
    });
  }

  List<AppImageUploadPendingItem> get _pendingLogoItems {
    if (_pendingLogoItem == null) {
      return const <AppImageUploadPendingItem>[];
    }
    return <AppImageUploadPendingItem>[_pendingLogoItem!];
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final submission = ref.watch(tenantFacilitySetupSubmissionProvider);
    final bool canEditBase = widget.canSubmit && !submission.isSubmitting;
    final bool fieldsEnabled =
        canEditBase && _hasSelectedTenant && !_loadingContact;
    final bool requireFields = _isCreate;
    final FacilityEffectiveContact inheritedContact = _inheritedContact;
    final String resolvedCurrency = resolveDefaultCurrency(
      facilityCurrency: _currency,
      tenantCurrency: widget.snapshot.tenant?.currency,
    );

    final Widget form = Form(
      key: _formKey,
      child: AppFormSection(
        children: <Widget>[
          if (_loadingContact)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(),
            ),
          if (widget.requireTenantPicker) ...<Widget>[
            if (_loadingTenants)
              const Center(child: CircularProgressIndicator())
            else if (_tenantLoadFailure != null)
              AppFailureStateView(
                failure: _tenantLoadFailure!,
                onRetry: () => unawaited(_loadTenantOptions()),
              )
            else
              AppSelectField<String>.searchable(
                value: _selectedTenantId,
                enabled: canEditBase,
                labelText: l10n.tenantFacilitySelectTenantLabel,
                isRequired: true,
                menuHeight: 320,
                options: _tenantOptions
                    .map(
                      (TenantProfile tenant) => AppSelectOption<String>(
                        value: tenant.id,
                        label: tenant.name,
                      ),
                    )
                    .toList(growable: false),
                onChanged: (String? value) {
                  setState(() {
                    _selectedTenantId = value;
                  });
                  _notifyDialogState();
                },
                validator: (String? value) => (value ?? '').trim().isEmpty
                    ? l10n.validationRequired
                    : null,
              ),
            if (_tenantOptions.isEmpty &&
                !_loadingTenants &&
                _tenantLoadFailure == null) ...<Widget>[
              SizedBox(height: theme.spacing.sm),
              Text(
                l10n.tenantFacilitySelectTenantLoadError,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            SizedBox(height: theme.spacing.md),
          ],
          if (widget.snapshot.facilities.length > 1 && widget.facility == null)
            AppSelectField<String>.searchable(
              value: widget.snapshot.facility?.id,
              enabled: !submission.isSubmitting,
              labelText: l10n.tenantFacilityFacilitySelectLabel,
              menuHeight: 320,
              options: <AppSelectOption<String>>[
                for (final FacilityProfile facility
                    in widget.snapshot.facilities)
                  AppSelectOption<String>(
                    value: facility.id,
                    label: facility.name,
                  ),
              ],
              onChanged: (String? value) {
                if (value == null || value == widget.snapshot.facility?.id) {
                  return;
                }
                ref
                    .read(tenantFacilitySetupControllerProvider.notifier)
                    .selectFacility(value);
              },
            ),
          if (_similarMatches.isNotEmpty)
            AppFormInformationBanner(
              title: context.l10n.tenantFacilitySimilarFacilityWarningTitle,
              message: context.l10n.tenantFacilitySimilarFacilityWarningBody,
              variant: AppFormInformationVariant.warning,
              icon: Icons.content_copy_outlined,
              children: <Widget>[
                for (final FacilitySimilarityMatch match
                    in _similarMatches.take(3))
                  Padding(
                    padding: EdgeInsets.only(
                      top: Theme.of(context).spacing.xs,
                    ),
                    child: Text(
                      context.l10n.tenantFacilitySimilarFacilityScoreLabel(
                        match.score,
                      ),
                    ),
                  ),
              ],
            ),
          AppTextField(
            controller: _nameController,
            enabled: fieldsEnabled,
            labelText: l10n.authFacilityNameLabel,
            isRequired: requireFields,
            textCapitalization: TextCapitalization.words,
            errorText: _nameErrorText,
            validator: requireFields
                ? AppValidators.requiredText(l10n.validationRequired)
                : null,
          ),
          AppSelectField<FacilitySetupType>(
            value: _type,
            enabled: fieldsEnabled,
            labelText: l10n.authFacilityTypeLabel,
            isRequired: requireFields,
            options: <AppSelectOption<FacilitySetupType>>[
              for (final type in FacilitySetupType.values)
                AppSelectOption<FacilitySetupType>(
                  value: type,
                  label: tenantFacilityFacilityTypeLabel(l10n, type),
                  leadingIcon: Icon(tenantFacilityFacilityTypeIcon(type)),
                ),
            ],
            onChanged: (FacilitySetupType? value) {
              if (value != null) {
                setState(() {
                  _type = value;
                });
              }
            },
          ),
          AppCurrencySelectField(
            value: _currency,
            enabled: fieldsEnabled,
            labelText: l10n.tenantFacilityDefaultCurrencyLabel,
            helperText: l10n.tenantFacilityDefaultCurrencyHelper,
            onChanged: (String? value) {
              if (value == null || value.trim().isEmpty) {
                return;
              }
              setState(() {
                _currency = value.trim().toUpperCase();
              });
            },
          ),
          AppCurrencyAmountField(
            amountController: _feeController,
            currency: resolvedCurrency,
            onCurrencyChanged: (String? value) {
              if (value == null || value.trim().isEmpty) {
                return;
              }
              setState(() {
                _currency = value.trim().toUpperCase();
              });
            },
            amountLabelText: l10n.settingsConfigurationConsultationFeeLabel,
            currencyLabelText: l10n.tenantFacilityDefaultCurrencyLabel,
            helperText: l10n.settingsConfigurationConsultationFeeHelper,
            enabled: fieldsEnabled,
          ),
          AppImageUploadField(
            label: l10n.tenantFacilityLogoLabel,
            helperText: l10n.tenantFacilityLogoHelper,
            chooseLabel: l10n.tenantFacilityChooseLogoAction,
            removeLabel: l10n.tenantFacilityRemoveLogoAction,
            enabled: fieldsEnabled,
            existingImageUrl: _logoCleared ? null : _existingLogoUrl,
            pendingItems: _pendingLogoItems,
            previewSize: 104,
            onChoose: _pickLogo,
            onClear: fieldsEnabled ? _clearLogo : null,
          ),
          ListenableBuilder(
            listenable: _phoneController,
            builder: (BuildContext context, _) => AppPhoneField(
              controller: _phoneController,
              enabled: fieldsEnabled,
              labelText: l10n.profilePhoneLabel,
              helperText: _inheritedHint(
                current: _phoneController.text,
                baseline: _baselinePhone,
                inherited: inheritedContact.phone,
                hint: l10n.tenantFacilityInheritedPhoneHint,
              ),
              countryLabelText: l10n.appPhoneCountryLabel,
              countrySearchLabelText: l10n.appPhoneCountrySearchLabel,
              countryNoResultsText: l10n.appPhoneCountryNoResults,
              numberLabelText: l10n.appPhoneNumberLabel,
              numberHintText: l10n.appPhoneNumberHint,
              invalidPhoneMessage: l10n.appPhoneInvalidMessage,
              requiredMessage: l10n.validationRequired,
              isRequired: requireFields,
            ),
          ),
          ListenableBuilder(
            listenable: _emailController,
            builder: (BuildContext context, _) => AppEmailField(
              controller: _emailController,
              enabled: fieldsEnabled,
              labelText: l10n.profileEmailLabel,
              helperText: _inheritedHint(
                current: _emailController.text,
                baseline: _baselineEmail,
                inherited: inheritedContact.email,
                hint: l10n.tenantFacilityInheritedEmailHint,
              ),
              isRequired: requireFields,
              requiredMessage: l10n.validationRequired,
              invalidEmailMessage: l10n.authEmailInvalidMessage,
            ),
          ),
          AppTextField(
            controller: _addressLineController,
            enabled: fieldsEnabled,
            labelText: l10n.tenantFacilityAddressLineLabel,
            textCapitalization: TextCapitalization.words,
          ),
          _TwoColumnFields(
            left: AppTextField(
              controller: _cityController,
              enabled: fieldsEnabled,
              labelText: l10n.tenantFacilityCityLabel,
              textCapitalization: TextCapitalization.words,
            ),
            right: AppCountryField(
              value: _selectedCountry,
              enabled: fieldsEnabled,
              labelText: l10n.tenantFacilityCountryLabel,
              onChanged: (String? value) {
                setState(() {
                  _selectedCountry = value;
                });
              },
            ),
          ),
          AppSwitchField(
            title: l10n.tenantFacilityActiveLabel,
            value: _isActive,
            enabled: fieldsEnabled,
            onChanged: (bool value) {
              setState(() {
                _isActive = value;
              });
            },
          ),
          if (!widget.hideSubmitButton)
            _SubmitButton(
              enabled: widget.canSubmit && _hasSelectedTenant,
              isLoading: submission.isSubmitting,
              label: _isCreate
                  ? l10n.tenantFacilitySaveFacilityAction
                  : l10n.tenantFacilityEditFacilityAction,
              onPressed: _submit,
            )
          else
            _SubmissionFeedback(
              enabled: widget.canSubmit && _hasSelectedTenant,
              failure: submission.failure,
            ),
        ],
      ),
    );

    if (widget.framed) {
      return AppCollapsibleSection(
        title: _isCreate
            ? l10n.tenantFacilityCreateFacilityTitle
            : l10n.tenantFacilityEditFacilityTitle,
        description: l10n.tenantFacilityFacilitySectionBody,
        child: form,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l10n.tenantFacilityFacilitySectionBody,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: theme.spacing.lg),
        form,
      ],
    );
  }

  Future<bool> _submit() async {
    if (_formKey.currentState?.validate() != true) {
      return false;
    }

    final String? tenantId = _resolvedTenantId;
    if (tenantId == null) {
      return false;
    }

    final String resolvedName = _isCreate
        ? _nameController.text.trim()
        : _coalescePreserved(_nameController.text, _baselineName);
    if (resolvedName.isEmpty) {
      setState(() {
        _nameErrorText = context.l10n.validationRequired;
      });
      return false;
    }

    final String? resolvedPhone = _isCreate
        ? _normalizedOptional(_phoneController.text)
        : _coalesceOptionalPreserved(_phoneController.text, _baselinePhone);
    final String? resolvedEmail = _isCreate
        ? _normalizedOptional(_emailController.text)
        : _coalesceOptionalPreserved(_emailController.text, _baselineEmail);
    final String? resolvedAddress = _isCreate
        ? _normalizedOptional(_addressLineController.text)
        : _coalesceOptionalPreserved(
            _addressLineController.text,
            _baselineAddressLine1,
          );
    final String? resolvedCity = _isCreate
        ? _normalizedOptional(_cityController.text)
        : _coalesceOptionalPreserved(_cityController.text, _baselineCity);
    final String? resolvedCountry = _isCreate
        ? _normalizedOptional(_selectedCountry)
        : _coalesceOptionalPreserved(_selectedCountry, _baselineCountry);
    final String? resolvedLogoUrl = _logoCleared
        ? null
        : (_normalizedOptional(_existingLogoUrl) ?? _baselineLogoUrl);
    final String resolvedFee = normalizeCurrencyAmount(_feeController.text);

    if (!_isCreate) {
      final List<_FacilityFieldChange> changes = _buildFacilityChanges(
        name: resolvedName,
        type: _type,
        isActive: _isActive,
        currency: _currency.trim().toUpperCase(),
        standardConsultationFee: resolvedFee.isEmpty ? null : resolvedFee,
        phone: resolvedPhone,
        email: resolvedEmail,
        addressLine1: resolvedAddress,
        city: resolvedCity,
        country: resolvedCountry,
        logoChanged: _logoCleared || _logoBytes != null,
        logoCleared: _logoCleared,
        logoReplaced: _logoBytes != null,
      );
      if (changes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  context.l10n.tenantFacilityNoFacilityChangesMessage,
                ),
              ),
            );
        }
        return false;
      }

      final bool confirmed = await _confirmFacilityChanges(changes);
      if (!confirmed) {
        return false;
      }
    }

    final bool canProceed = await _guardAgainstDuplicates(
      tenantId,
      name: resolvedName,
      phone: resolvedPhone,
      email: resolvedEmail,
      addressLine1: resolvedAddress,
      city: resolvedCity,
      country: resolvedCountry,
    );
    if (!canProceed) {
      return false;
    }

    final FacilityProfile? editingFacility = widget.facility ?? _activeFacility;
    final String resolvedTenantId = _resolveMutationTenantId(tenantId);
    final bool saved = await ref
        .read(tenantFacilitySetupSubmissionProvider.notifier)
        .saveFacility(
          id: editingFacility?.mutationId ?? editingFacility?.id,
          tenantId: resolvedTenantId,
          name: resolvedName,
          type: _type,
          isActive: _isActive,
          logoUrl: resolvedLogoUrl,
          removeLogo: _logoCleared,
          currency: _currency.trim().toUpperCase(),
          standardConsultationFee: resolvedFee.isEmpty ? null : resolvedFee,
          clearStandardConsultationFee: resolvedFee.isEmpty,
          logoBytes: _logoBytes,
          logoFileName: _logoFileName,
          logoMimeType: _logoMimeType,
          phone: resolvedPhone,
          email: resolvedEmail,
          addressLine1: resolvedAddress,
          city: resolvedCity,
          country: resolvedCountry,
          confirmSimilar: _similarityAccepted,
          refreshSetup: widget.refreshSetupAfterSave,
        );

    if (saved) {
      return true;
    }

    if (!mounted) {
      return false;
    }

    final AppFailure? failure = ref
        .read(tenantFacilitySetupSubmissionProvider)
        .failure;
    if (failure?.messageKey == 'errors.facility.duplicate_name') {
      setState(() {
        _nameErrorText = context.l10n.tenantFacilityFacilityNameAlreadyInUse;
      });
      return false;
    }
    if (!_isFacilitySimilarityConflict(failure)) {
      return false;
    }

    ref.read(tenantFacilitySetupSubmissionProvider.notifier).clearFailure();
    setState(() {
      _similarityAccepted = false;
    });
    final bool confirmed = await _guardAgainstDuplicates(
      tenantId,
      name: resolvedName,
      phone: resolvedPhone,
      email: resolvedEmail,
      addressLine1: resolvedAddress,
      city: resolvedCity,
      country: resolvedCountry,
      forceReviewMatches: true,
    );
    if (!confirmed || !mounted) {
      return false;
    }
    return ref
        .read(tenantFacilitySetupSubmissionProvider.notifier)
        .saveFacility(
          id: editingFacility?.mutationId ?? editingFacility?.id,
          tenantId: resolvedTenantId,
          name: resolvedName,
          type: _type,
          isActive: _isActive,
          logoUrl: resolvedLogoUrl,
          removeLogo: _logoCleared,
          currency: _currency.trim().toUpperCase(),
          standardConsultationFee: resolvedFee.isEmpty ? null : resolvedFee,
          clearStandardConsultationFee: resolvedFee.isEmpty,
          logoBytes: _logoBytes,
          logoFileName: _logoFileName,
          logoMimeType: _logoMimeType,
          phone: resolvedPhone,
          email: resolvedEmail,
          addressLine1: resolvedAddress,
          city: resolvedCity,
          country: resolvedCountry,
          confirmSimilar: true,
          refreshSetup: widget.refreshSetupAfterSave,
        );
  }

  bool _isFacilitySimilarityConflict(AppFailure? failure) {
    if (failure == null || failure.category != AppFailureCategory.conflict) {
      return false;
    }
    if (failure.messageKey == 'errors.facility.similar_exists') {
      return true;
    }
    final String detail = (failure.detailMessage ?? '').toLowerCase();
    return detail.contains('similar facility') ||
        detail.contains('confirm to create anyway');
  }

  List<_FacilityFieldChange> _buildFacilityChanges({
    required String name,
    required FacilitySetupType type,
    required bool isActive,
    required String currency,
    required String? standardConsultationFee,
    required String? phone,
    required String? email,
    required String? addressLine1,
    required String? city,
    required String? country,
    required bool logoChanged,
    required bool logoCleared,
    required bool logoReplaced,
  }) {
    final AppLocalizations l10n = context.l10n;
    final List<_FacilityFieldChange> changes = <_FacilityFieldChange>[];

    void addChange(String label, String? previous, String? next) {
      final String previousValue = (previous ?? '').trim();
      final String nextValue = (next ?? '').trim();
      if (previousValue == nextValue) {
        return;
      }
      changes.add(
        _FacilityFieldChange(
          label: label,
          previousValue: previousValue.isEmpty ? '—' : previousValue,
          nextValue: nextValue.isEmpty ? '—' : nextValue,
        ),
      );
    }

    addChange(l10n.authFacilityNameLabel, _baselineName, name);
    addChange(
      l10n.authFacilityTypeLabel,
      tenantFacilityFacilityTypeLabel(l10n, _baselineType),
      tenantFacilityFacilityTypeLabel(l10n, type),
    );
    addChange(
      l10n.tenantFacilityActiveLabel,
      _baselineIsActive
          ? l10n.tenantFacilityStatusActive
          : l10n.tenantFacilityStatusInactive,
      isActive
          ? l10n.tenantFacilityStatusActive
          : l10n.tenantFacilityStatusInactive,
    );
    addChange(
      l10n.tenantFacilityDefaultCurrencyLabel,
      _baselineCurrency,
      currency,
    );
    addChange(
      l10n.settingsConfigurationConsultationFeeLabel,
      _baselineFee,
      standardConsultationFee,
    );
    addChange(l10n.profilePhoneLabel, _baselinePhone, phone);
    addChange(l10n.profileEmailLabel, _baselineEmail, email);
    addChange(
      l10n.tenantFacilityAddressLineLabel,
      _baselineAddressLine1,
      addressLine1,
    );
    addChange(l10n.tenantFacilityCityLabel, _baselineCity, city);
    addChange(l10n.tenantFacilityCountryLabel, _baselineCountry, country);
    if (logoChanged) {
      final String? previousUrl = _normalizedOptional(_baselineLogoUrl);
      final List<int>? nextBytes = logoReplaced ? _logoBytes : null;
      changes.add(
        _FacilityFieldChange(
          label: l10n.tenantFacilityLogoLabel,
          previousValue: previousUrl == null
              ? l10n.tenantFacilityFacilityDetailsNoLogo
              : l10n.tenantFacilityLogoLabel,
          nextValue: logoCleared
              ? l10n.tenantFacilityLogoRemovedLabel
              : l10n.tenantFacilityLogoAddedLabel,
          isLogo: true,
          previousLogoUrl: previousUrl,
          nextLogoBytes: nextBytes,
          logoCleared: logoCleared,
        ),
      );
    }

    return changes;
  }

  Future<bool> _confirmFacilityChanges(
    List<_FacilityFieldChange> changes,
  ) async {
    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        final ThemeData theme = Theme.of(dialogContext);
        final ColorScheme colorScheme = theme.colorScheme;
        return AppDialog(
          title: Text(l10n.tenantFacilityConfirmFacilityUpdateTitle),
          icon: const Icon(Icons.compare_arrows_outlined),
          scrollable: true,
          maxWidth: 720,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: theme.borders.all(color: colorScheme.primary.withValues(alpha: 0.18)),
                ),
                child: Padding(
                  padding: EdgeInsets.all(theme.spacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.info_outline,
                        color: colorScheme.primary,
                        size: 22,
                      ),
                      SizedBox(width: theme.spacing.sm),
                      Expanded(
                        child: Text(
                          l10n.tenantFacilityConfirmFacilityUpdateBody,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: theme.spacing.md),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      l10n.tenantFacilityFieldPreviousLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: AppFontWeight.emphasis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 40),
                  Expanded(
                    child: Text(
                      l10n.tenantFacilityFieldNewLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: AppFontWeight.emphasis,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: theme.spacing.sm),
              for (final _FacilityFieldChange change in changes) ...<Widget>[
                _FacilityChangeDiffCard(change: change),
                SizedBox(height: theme.spacing.sm),
              ],
            ],
          ),
          actions: <Widget>[
            AppButton.close(
              label: l10n.commonCancelActionLabel,
              leadingIcon: Icons.close,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            AppButton.primary(
              label: l10n.tenantFacilityConfirmFacilityUpdateAction,
              leadingIcon: Icons.check,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  Future<bool> _guardAgainstDuplicates(
    String tenantId, {
    required String name,
    String? phone,
    String? email,
    String? addressLine1,
    String? city,
    String? country,
    bool forceReviewMatches = false,
  }) async {
    final FacilityProfile? editingFacility = widget.facility ?? _activeFacility;

    // Edit saves with an unchanged identity should skip empty review.
    if (!_isCreate &&
        !forceReviewMatches &&
        editingFacility != null &&
        normalizeFacilityName(name) == normalizeFacilityName(_baselineName) &&
        _type == _baselineType &&
        _isActive == _baselineIsActive &&
        normalizeFacilityPhone(phone) == normalizeFacilityPhone(_baselinePhone) &&
        normalizeFacilityEmail(email) ==
            normalizeFacilityEmail(_baselineEmail) &&
        normalizeFacilityAddress(addressLine1) ==
            normalizeFacilityAddress(_baselineAddressLine1) &&
        normalizeFacilityAddress(city) ==
            normalizeFacilityAddress(_baselineCity) &&
        normalizeFacilityAddress(country) ==
            normalizeFacilityAddress(_baselineCountry)) {
      setState(() {
        _nameErrorText = null;
        _similarMatches = const <FacilitySimilarityMatch>[];
        _similarityAccepted = false;
      });
      return true;
    }

    final List<FacilityProfile> existing = await _loadExistingFacilities(
      tenantId,
    );
    final FacilityDuplicateCheckResult result = checkFacilityDuplicates(
      name: name,
      type: _type,
      isActive: _isActive,
      existing: existing,
      excludeFacility: editingFacility,
      excludeFacilityId: editingFacility?.mutationId ?? editingFacility?.id,
      phone: phone,
      email: email,
      addressLine1: addressLine1,
      city: city,
      country: country,
    );

    final bool exactNameConflict = result.exactNameConflict;
    final List<FacilitySimilarityMatch> reviewMatches = exactNameConflict
        ? result.similarMatches
              .where((FacilitySimilarityMatch match) => match.exactNameConflict)
              .toList(growable: false)
        : result.overridableMatches;

    if (!mounted) {
      return false;
    }

    if (!_isCreate &&
        !forceReviewMatches &&
        !exactNameConflict &&
        reviewMatches.isEmpty) {
      setState(() {
        _nameErrorText = null;
        _similarMatches = const <FacilitySimilarityMatch>[];
        _similarityAccepted = false;
      });
      return true;
    }

    // Create always opens review (including zero matches). Edit only when
    // forced by backend conflict or local matches exist.
    if (!_isCreate && !forceReviewMatches && reviewMatches.isEmpty) {
      return true;
    }

    setState(() {
      _nameErrorText = exactNameConflict
          ? context.l10n.tenantFacilityFacilityNameAlreadyInUse
          : null;
      _similarMatches = const <FacilitySimilarityMatch>[];
      if (exactNameConflict) {
        _similarityAccepted = false;
      }
    });

    final FacilitySimilarityDialogResult decision =
        await showFacilitySimilarityDialog(
          context,
          proposed: FacilitySimilarityProposedValues(
            name: name,
            type: _type,
            isActive: _isActive,
            phone: phone,
            email: email,
            addressLine1: addressLine1,
            city: city,
            country: country,
          ),
          matches: reviewMatches,
          allowProceed: !exactNameConflict,
        );
    if (!mounted) {
      return false;
    }

    switch (decision.action) {
      case FacilitySimilarityAction.cancel:
        setState(() {
          _similarityAccepted = false;
          if (reviewMatches.isNotEmpty) {
            _similarMatches = reviewMatches;
          }
        });
        widget.onDialogStateChanged?.call();
        return false;
      case FacilitySimilarityAction.useExisting:
        final FacilityProfile? existingFacility = decision.selectedFacility;
        if (existingFacility != null) {
          Navigator.of(context).pop<FacilityProfile>(existingFacility);
        }
        return false;
      case FacilitySimilarityAction.proceed:
        setState(() {
          _similarityAccepted = reviewMatches.isNotEmpty || forceReviewMatches;
          _nameErrorText = null;
        });
        return true;
    }
  }

  Future<List<FacilityProfile>> _loadExistingFacilities(String tenantId) async {
    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );
    final String name = _nameController.text.trim();
    final Set<String> seenIds = <String>{};
    final List<FacilityProfile> facilities = <FacilityProfile>[];

    Future<void> appendMatches(String? search) async {
      final Result<AppPage<FacilityProfile>> result = await repository
          .listFacilities(
            request: _duplicateLookupRequest,
            tenantId: tenantId,
            search: search,
          );
      result.when(
        success: (AppPage<FacilityProfile> page) {
          for (final FacilityProfile facility in page.items) {
            if (seenIds.add(facility.id)) {
              facilities.add(facility);
            }
          }
        },
        failure: (_) {},
      );
    }

    await appendMatches(name.isEmpty ? null : name);
    if (facilities.isEmpty) {
      await appendMatches(null);
    }

    return facilities;
  }
}

const String _noneSelection = tenantFacilityNoneSelection;

class _DepartmentSetupSection extends ConsumerStatefulWidget {
  const _DepartmentSetupSection({
    required this.snapshot,
    required this.canSubmit,
    this.framed = true,
    this.onListTotalChanged,
  });

  final FacilitySetupSnapshot snapshot;
  final bool canSubmit;
  final bool framed;
  final ValueChanged<int>? onListTotalChanged;

  @override
  ConsumerState<_DepartmentSetupSection> createState() =>
      _DepartmentSetupSectionState();
}

class _DepartmentSetupSectionState
    extends ConsumerState<_DepartmentSetupSection> {
  static const AppPageRequest _lookupOptionsRequest = AppPageRequest(
    pageSize: PlatformAdminListConfig.pageSize,
  );

  AppPageRequest _pageRequest = PlatformAdminListConfig.initialPageRequest;
  int _totalItemCount = 0;
  String _searchQuery = '';
  String? _listStatusFilter = 'active';
  Timer? _searchDebounce;

  bool _loading = true;
  AppFailure? _failure;
  List<DepartmentProfile> _departments = const <DepartmentProfile>[];
  List<TenantProfile> _tenantOptions = const <TenantProfile>[];
  List<FacilityProfile> _facilityOptions = const <FacilityProfile>[];
  Map<String, String> _tenantNamesById = const <String, String>{};
  Map<String, String> _facilityNamesById = const <String, String>{};
  String? _tenantFilterId;
  String? _facilityFilterId;
  DepartmentSetupType? _typeFilter;
  bool? _isActiveFilter;
  String? _busyDepartmentId;
  int _reloadGeneration = 0;

  FacilitySetupSnapshot get snapshot => widget.snapshot;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(covariant _DepartmentSetupSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String? oldFacilityId = oldWidget.snapshot.facility?.id;
    final String? nextFacilityId = widget.snapshot.facility?.id;
    final String? oldTenantId = oldWidget.snapshot.tenant?.id;
    final String? nextTenantId = widget.snapshot.tenant?.id;
    if (oldFacilityId != nextFacilityId || oldTenantId != nextTenantId) {
      unawaited(_reload());
    }
  }

  List<FacilityProfile> get _facilitiesForFilter {
    final String? tenantFilterId = _tenantFilterId?.trim();
    if (tenantFilterId == null || tenantFilterId.isEmpty) {
      return _facilityOptions
          .where((FacilityProfile facility) => !facility.isDeleted)
          .toList(growable: false);
    }
    return _facilityOptions
        .where(
          (FacilityProfile facility) =>
              !facility.isDeleted && facility.tenantId == tenantFilterId,
        )
        .toList(growable: false);
  }

  void _applyServerFilters(AppSearchBarFilterValue value) {
    final String? nextTenant = value.option(
      TenantFacilityDepartmentsFilterKeys.tenant,
    );
    final String? nextFacility = value.option(
      TenantFacilityDepartmentsFilterKeys.facility,
    );
    final String? nextType = value.option(
      TenantFacilityDepartmentsFilterKeys.type,
    );
    final String? nextActive = value.option(
      TenantFacilityDepartmentsFilterKeys.active,
    );

    DepartmentSetupType? parsedType;
    if (nextType != null) {
      for (final DepartmentSetupType type in DepartmentSetupType.values) {
        if (type.apiValue == nextType) {
          parsedType = type;
          break;
        }
      }
    }

    final bool? parsedActive =
        nextActive == TenantFacilityDepartmentsFilterKeys.activeYes
        ? true
        : nextActive == TenantFacilityDepartmentsFilterKeys.activeNo
        ? false
        : null;

    _tenantFilterId = nextTenant;
    _facilityFilterId = nextFacility;
    _typeFilter = parsedType;
    _isActiveFilter = parsedActive;
    _syncFacilityFilterToOptions();
  }

  void _syncFacilityFilterToOptions() {
    final String? facilityId = _facilityFilterId;
    if (facilityId == null) {
      return;
    }
    final String? tenantFilterId = _tenantFilterId?.trim();
    final bool facilityAllowed = _facilityOptions.any((FacilityProfile facility) {
      if (facility.id != facilityId || facility.isDeleted) {
        return false;
      }
      if (tenantFilterId == null || tenantFilterId.isEmpty) {
        return true;
      }
      return facility.tenantId == tenantFilterId;
    });
    if (!facilityAllowed) {
      _facilityFilterId = null;
    }
  }

  Future<void> _onFiltersChanged(AppSearchBarFilterValue value) async {
    final String? previousTenant = _tenantFilterId;
    _applyServerFilters(value);
    _listStatusFilter = value.option('status');
    _pageRequest = _pageRequest.first();
    final bool tenantChanged = previousTenant != _tenantFilterId;
    if (tenantChanged) {
      await _reloadFacilityOptions();
      _syncFacilityFilterToOptions();
    }
    await _reload(silent: true);
  }

  void _onSearchChanged(String raw) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      final String next = raw.trim();
      if (next == _searchQuery) {
        return;
      }
      _searchQuery = next;
      _pageRequest = _pageRequest.first();
      unawaited(_reload(silent: true));
    });
  }

  Future<void> _onPageChanged(AppPageRequest request) async {
    _pageRequest = request;
    await _reload(silent: true);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _reloadFacilityOptions() async {
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final TenantFacilityDepartmentsListScope scope =
        tenantFacilityDepartmentsListScope(policy);
    if (!tenantFacilityDepartmentsShowsFacilityFilter(scope)) {
      return;
    }

    final String? tenantId = switch (scope) {
      TenantFacilityDepartmentsListScope.platform => _tenantFilterId,
      TenantFacilityDepartmentsListScope.tenant ||
      TenantFacilityDepartmentsListScope.facility =>
        policy.tenantId ?? snapshot.tenant?.id,
    };

    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );
    final Result<AppPage<FacilityProfile>> result = await repository
        .listFacilities(request: _lookupOptionsRequest, tenantId: tenantId);
    if (!mounted) {
      return;
    }
    result.when(
      success: (AppPage<FacilityProfile> page) {
        setState(() {
          _facilityOptions = page.items;
          _facilityNamesById = <String, String>{
            for (final FacilityProfile facility in page.items)
              facility.id: facility.name,
          };
          if (_facilityFilterId != null &&
              !_facilitiesForFilter.any(
                (FacilityProfile facility) => facility.id == _facilityFilterId,
              )) {
            _facilityFilterId = null;
          }
        });
      },
      failure: (_) {},
    );
  }

  Future<void> _reload({bool silent = false}) async {
    final int generation = ++_reloadGeneration;
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final TenantFacilityDepartmentsListScope scope =
        tenantFacilityDepartmentsListScope(policy);
    final String? scopedTenantId = switch (scope) {
      TenantFacilityDepartmentsListScope.platform => _tenantFilterId,
      TenantFacilityDepartmentsListScope.tenant ||
      TenantFacilityDepartmentsListScope.facility =>
        policy.tenantId ?? snapshot.tenant?.id,
    };
    final String? scopedFacilityId =
        scope == TenantFacilityDepartmentsListScope.facility
        ? (policy.facilityId ?? snapshot.facility?.id)
        : _facilityFilterId;

    if (!silent) {
      setState(() {
        // Keep populated rows visible; only empty lists show the full loader.
        _loading = _departments.isEmpty;
        _failure = null;
      });
    }

    if (scope == TenantFacilityDepartmentsListScope.facility &&
        (scopedFacilityId == null || scopedFacilityId.trim().isEmpty)) {
      if (!mounted || generation != _reloadGeneration) {
        return;
      }
      setState(() {
        _loading = false;
        _departments = const <DepartmentProfile>[];
        _facilityOptions = const <FacilityProfile>[];
        _tenantOptions = const <TenantProfile>[];
        _tenantNamesById = const <String, String>{};
        _facilityNamesById = const <String, String>{};
      });
      return;
    }

    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );

    final Future<Result<AppPage<TenantProfile>>>? tenantsFuture =
        tenantFacilityDepartmentsShowsTenantFilter(scope)
        ? repository.listTenants(
            request: _lookupOptionsRequest,
          )
        : null;
    final Future<Result<AppPage<FacilityProfile>>>? facilitiesFuture =
        tenantFacilityDepartmentsShowsFacilityFilter(scope)
        ? repository.listFacilities(
            request: _lookupOptionsRequest,
            tenantId: scope == TenantFacilityDepartmentsListScope.platform
                ? _tenantFilterId
                : scopedTenantId,
          )
        : null;
    final bool includeDeleted = _listStatusFilter != 'active';
    final Future<Result<AppPage<DepartmentProfile>>> departmentsFuture =
        repository.listDepartments(
          request: _pageRequest,
          tenantId: scopedTenantId,
          facilityId: scopedFacilityId,
          search: _searchQuery.isEmpty ? null : _searchQuery,
          type: _typeFilter,
          isActive: _isActiveFilter,
          includeDeleted: includeDeleted,
        );

    final Result<AppPage<TenantProfile>>? tenantsResult = tenantsFuture == null
        ? null
        : await tenantsFuture;
    final Result<AppPage<FacilityProfile>>? facilitiesResult =
        facilitiesFuture == null ? null : await facilitiesFuture;
    final Result<AppPage<DepartmentProfile>> departmentsResult =
        await departmentsFuture;

    if (!mounted || generation != _reloadGeneration) {
      return;
    }

    departmentsResult.when(
      success: (AppPage<DepartmentProfile> page) {
        final Map<String, String> tenantNames = <String, String>{
          if (snapshot.tenant case final TenantProfile tenant)
            tenant.id: tenant.name,
        };
        List<TenantProfile> tenants = const <TenantProfile>[];
        tenantsResult?.when(
          success: (AppPage<TenantProfile> tenantsPage) {
            tenants = tenantsPage.items;
            for (final TenantProfile tenant in tenantsPage.items) {
              tenantNames[tenant.id] = tenant.name;
            }
          },
          failure: (_) {},
        );

        List<FacilityProfile> facilities = <FacilityProfile>[
          ...snapshot.facilities,
          if (snapshot.facility != null) snapshot.facility!,
        ];
        facilitiesResult?.when(
          success: (AppPage<FacilityProfile> facilitiesPage) {
            facilities = facilitiesPage.items;
          },
          failure: (_) {},
        );
        final Map<String, String> facilityNames = <String, String>{
          for (final FacilityProfile facility in facilities)
            facility.id: facility.name,
        };

        List<DepartmentProfile> departments = page.items;
        if (_listStatusFilter == 'deleted') {
          departments = departments
              .where((DepartmentProfile item) => item.isDeleted)
              .toList(growable: false);
        }
        setState(() {
          _loading = false;
          _failure = null;
          _departments = departments;
          _totalItemCount = _listStatusFilter == 'deleted'
              ? departments.length
              : (page.totalItemCount ?? departments.length);
          _tenantOptions = tenants;
          _facilityOptions = facilities;
          _tenantNamesById = tenantNames;
          _facilityNamesById = facilityNames;
        });
        widget.onListTotalChanged?.call(_totalItemCount);
      },
      failure: (AppFailure failure) {
        setState(() {
          _loading = false;
          _failure = failure;
          if (!silent) {
            _departments = const <DepartmentProfile>[];
          }
        });
      },
    );
  }

  String _facilityLabel(DepartmentProfile department) {
    final String? facilityId = department.facilityId?.trim();
    if (facilityId == null || facilityId.isEmpty) {
      return '—';
    }
    final bool isDeleted = _facilityOptions.any(
      (FacilityProfile facility) =>
          facility.id == facilityId && facility.isDeleted,
    );
    return tenantFacilityRelatedNameLabel(
      _facilityNamesById[facilityId],
      isDeleted: isDeleted,
      deletedLabel: context.l10n.tenantFacilityStructureDeletedStatus,
    );
  }

  String _tenantLabel(DepartmentProfile department) {
    final String tenantId = department.tenantId.trim();
    if (tenantId.isEmpty) {
      return '—';
    }
    final bool isDeleted = _tenantOptions.any(
      (TenantProfile tenant) => tenant.id == tenantId && tenant.isDeleted,
    );
    return tenantFacilityRelatedNameLabel(
      _tenantNamesById[tenantId],
      isDeleted: isDeleted,
      deletedLabel: context.l10n.tenantFacilityStructureDeletedStatus,
    );
  }

  Future<void> _afterMutation(Future<void> Function() action) async {
    await action();
    if (!mounted) {
      return;
    }
    await _reload(silent: true);
  }

  Future<bool> _runBusyDepartmentAction(
    DepartmentProfile department,
    Future<bool> Function() action,
  ) async {
    if (mounted) {
      setState(() => _busyDepartmentId = department.mutationId);
    }
    final bool succeeded = await action();
    if (!succeeded && mounted && _busyDepartmentId == department.mutationId) {
      setState(() => _busyDepartmentId = null);
    }
    return succeeded;
  }

  List<AppSearchBarFilterGroup> _buildFilterGroups(AppLocalizations l10n) {
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final TenantFacilityDepartmentsListScope scope =
        tenantFacilityDepartmentsListScope(policy);
    final List<FacilityProfile> facilities = _facilitiesForFilter;

    return <AppSearchBarFilterGroup>[
      if (tenantFacilityDepartmentsShowsTenantFilter(scope) &&
          _tenantOptions.isNotEmpty)
        AppSearchBarFilterGroup(
          key: TenantFacilityDepartmentsFilterKeys.tenant,
          label: l10n.profileTenantLabel,
          allLabel: l10n.commonAllLabel,
          choices: _tenantOptions
              .map(
                (TenantProfile tenant) => AppSearchBarFilterChoice(
                  value: tenant.id,
                  label: tenant.name,
                  icon: Icons.apartment_outlined,
                ),
              )
              .toList(growable: false),
        ),
      if (tenantFacilityDepartmentsShowsFacilityFilter(scope) &&
          facilities.isNotEmpty)
        AppSearchBarFilterGroup(
          key: TenantFacilityDepartmentsFilterKeys.facility,
          label: l10n.profileFacilityLabel,
          allLabel: l10n.commonAllLabel,
          choices: facilities
              .map(
                (FacilityProfile facility) => AppSearchBarFilterChoice(
                  value: facility.id,
                  label: facility.name,
                  icon: Icons.local_hospital_outlined,
                ),
              )
              .toList(growable: false),
        ),
      AppSearchBarFilterGroup(
        key: TenantFacilityDepartmentsFilterKeys.type,
        label: l10n.tenantFacilityDepartmentTypeLabel,
        allLabel: l10n.commonAllLabel,
        choices: DepartmentSetupType.values
            .map(
              (DepartmentSetupType type) => AppSearchBarFilterChoice(
                value: type.apiValue,
                label: _departmentTypeLabel(l10n, type),
                icon: Icons.category_outlined,
              ),
            )
            .toList(growable: false),
      ),
      AppSearchBarFilterGroup(
        key: TenantFacilityDepartmentsFilterKeys.active,
        label: l10n.tenantFacilityActiveLabel,
        allLabel: l10n.commonAllLabel,
        choices: <AppSearchBarFilterChoice>[
          AppSearchBarFilterChoice(
            value: TenantFacilityDepartmentsFilterKeys.activeYes,
            label: l10n.tenantFacilityTenantStatusActive,
            icon: Icons.toggle_on_outlined,
          ),
          AppSearchBarFilterChoice(
            value: TenantFacilityDepartmentsFilterKeys.activeNo,
            label: l10n.tenantFacilityStatusInactive,
            icon: Icons.toggle_off_outlined,
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppAccessPolicy policy = ref.watch(appAccessPolicyProvider);
    final TenantFacilityDepartmentsListScope scope =
        tenantFacilityDepartmentsListScope(policy);
    final bool isSubmitting = ref.watch(
      tenantFacilitySetupSubmissionProvider.select(
        (TenantFacilitySetupSubmissionState state) => state.isSubmitting,
      ),
    );
    final bool canManageRecords = widget.canSubmit;
    final TenantFacilityDepartmentsListScope createScope = scope;
    final bool prerequisitesMet =
        createScope == TenantFacilityDepartmentsListScope.facility
        ? (policy.facilityId ?? snapshot.facility?.id) != null
        : true;
    final bool canAdd =
        canManageRecords && prerequisitesMet && !isSubmitting && _busyDepartmentId == null;
    final String? blockedMessage = canManageRecords && !prerequisitesMet
        ? l10n.tenantFacilityGateNeedFacility
        : null;
    final bool showTenantColumn = tenantFacilityDepartmentsShowsTenantColumn(
      scope,
    );
    final bool showFacilityColumn =
        tenantFacilityDepartmentsShowsFacilityColumn(scope);
    final bool showDetailColumns = tenantFacilityDepartmentsShowsDetailColumns(
      scope,
    );

    final List<AppListTableColumn<DepartmentProfile>> extraColumns =
        <AppListTableColumn<DepartmentProfile>>[
          if (showFacilityColumn)
            AppListTableColumn<DepartmentProfile>(
              id: 'facility',
              label: l10n.profileFacilityLabel,
              preferredWidth: 160,
              sortComparator:
                  (DepartmentProfile left, DepartmentProfile right) =>
                      appListTableCompareText(
                        _facilityLabel(left),
                        _facilityLabel(right),
                      ),
              cellBuilder: (_, DepartmentProfile department) =>
                  tenantFacilitySetupAtomicCell(_facilityLabel(department)),
              exportValue: (DepartmentProfile department) =>
                  _facilityLabel(department),
            ),
          if (showTenantColumn)
            AppListTableColumn<DepartmentProfile>(
              id: 'tenant',
              label: l10n.profileTenantLabel,
              preferredWidth: 160,
              sortComparator:
                  (DepartmentProfile left, DepartmentProfile right) =>
                      appListTableCompareText(
                        _tenantLabel(left),
                        _tenantLabel(right),
                      ),
              cellBuilder: (_, DepartmentProfile department) =>
                  tenantFacilitySetupAtomicCell(_tenantLabel(department)),
              exportValue: (DepartmentProfile department) =>
                  _tenantLabel(department),
            ),
          if (showDetailColumns)
            AppListTableColumn<DepartmentProfile>(
              id: 'type',
              label: l10n.tenantFacilityDepartmentTypeLabel,
              preferredWidth: 140,
              sortComparator:
                  (DepartmentProfile left, DepartmentProfile right) =>
                      appListTableCompareText(
                        _departmentTypeLabel(l10n, left.type),
                        _departmentTypeLabel(l10n, right.type),
                      ),
              cellBuilder: (_, DepartmentProfile department) =>
                  tenantFacilitySetupAtomicCell(
                    _departmentTypeLabel(l10n, department.type),
                  ),
              exportValue: (DepartmentProfile department) =>
                  _departmentTypeLabel(l10n, department.type),
            ),
        ];

    final Widget content = _loading && _departments.isEmpty
        ? const AppLoadingIndicator.compact()
        : _failure != null && _departments.isEmpty
        ? Center(
            child: Text(
              l10n.failureMessage(_failure!),
              textAlign: TextAlign.center,
            ),
          )
        : _SearchableEntityGroup<DepartmentProfile>(
            title: l10n.tenantFacilityDepartmentsListTitle,
            nameColumnLabel: l10n.tenantFacilityDepartmentNameLabel,
            nameDetailBuilder: (DepartmentProfile department) {
              final List<String> details = <String>[];
              final String? departmentId = tenantFacilityHumanFriendlyDisplayId(
                department.displayId,
                opaqueId: department.resourceUuid ?? department.id,
              );
              if (departmentId != null) {
                details.add(departmentId);
              }
              final String? shortName = department.shortName?.trim();
              if (shortName != null && shortName.isNotEmpty) {
                details.add(shortName);
              }
              if (!showDetailColumns) {
                details.add(_departmentTypeLabel(l10n, department.type));
              }
              return details;
            },
            items: _departments,
            serverDrivenList: true,
            onSearchChanged: _onSearchChanged,
            pageRequest: _pageRequest,
            totalItemCount: _totalItemCount,
            onPageChanged: _onPageChanged,
            emptyLabel: l10n.tenantFacilityNoDepartments,
            noResultsLabel: l10n.tenantFacilitySearchNoResults,
            searchLabel: l10n.tenantFacilitySearchLabel,
            searchHint: l10n.tenantFacilityDepartmentSearchHint,
            addLabel: l10n.tenantFacilityAddDepartmentAction,
            canManageRecords: canManageRecords,
            canAdd: canAdd,
            isSubmitting: isSubmitting,
            busyItemId: _busyDepartmentId,
            itemIdBuilder: (DepartmentProfile department) =>
                department.mutationId,
            blockedMessage: blockedMessage,
            onAdd: () => unawaited(
              _afterMutation(
                () => _openDepartmentDialog(
                  context,
                  snapshot,
                  tenantOptions: _tenantOptions,
                  facilityOptions: _facilityOptions,
                ),
              ),
            ),
            onRowSelected: (DepartmentProfile department) {
              unawaited(
                _afterMutation(
                  () => _openDepartmentDetails(
                    context,
                    department: department,
                    snapshot: snapshot,
                    tenantName: _tenantLabel(department),
                    facilityName: _facilityLabel(department),
                  ),
                ),
              );
            },
            columnVisibilityStorageKey:
                'setup_structure_departments_${scope.name}_v4',
            extraFilterGroups: _buildFilterGroups(l10n),
            onFiltersChanged: (AppSearchBarFilterValue value) {
              unawaited(_onFiltersChanged(value));
            },
            titleBuilder: (DepartmentProfile department) => department.name,
            subtitleBuilder: (DepartmentProfile department) =>
                _departmentSubtitle(l10n, snapshot, department),
            statusLabelBuilder: (DepartmentProfile department) {
              if (department.isDeleted) {
                return l10n.tenantFacilityStructureDeletedStatus;
              }
              return _activeStatusLabel(l10n, department.isActive);
            },
            extraColumns: extraColumns,
            isDeletedBuilder: (DepartmentProfile department) =>
                department.isDeleted,
            onEdit: (DepartmentProfile department) {
              if (department.isDeleted ||
                  isSubmitting ||
                  _busyDepartmentId != null) {
                return;
              }
              unawaited(() async {
                await _openDepartmentDialog(
                  context,
                  snapshot,
                  department: department,
                  tenantOptions: _tenantOptions,
                  facilityOptions: _facilityOptions,
                );
                if (!mounted) {
                  return;
                }
                setState(() => _busyDepartmentId = department.mutationId);
                try {
                  await _reload(silent: true);
                } finally {
                  if (mounted &&
                      _busyDepartmentId == department.mutationId) {
                    setState(() => _busyDepartmentId = null);
                  }
                }
              }());
            },
            onDelete: (DepartmentProfile department) {
              if (_busyDepartmentId != null) {
                return;
              }
              unawaited(() async {
                await _deleteEntity(
                  context: context,
                  ref: ref,
                  name: department.name,
                  deleteAction: () => _runBusyDepartmentAction(
                    department,
                    () => ref
                        .read(tenantFacilitySetupSubmissionProvider.notifier)
                        .deleteDepartment(department.mutationId),
                  ),
                );
                if (!mounted) {
                  return;
                }
                try {
                  await _reload(silent: true);
                } finally {
                  if (mounted &&
                      _busyDepartmentId == department.mutationId) {
                    setState(() => _busyDepartmentId = null);
                  }
                }
              }());
            },
            onRestore: (DepartmentProfile department) {
              if (_busyDepartmentId != null) {
                return;
              }
              unawaited(() async {
                await _restoreEntity(
                  context: context,
                  ref: ref,
                  name: department.name,
                  restoreAction: () => _runBusyDepartmentAction(
                    department,
                    () => ref
                        .read(tenantFacilitySetupSubmissionProvider.notifier)
                        .restoreDepartment(department.mutationId),
                  ),
                );
                if (!mounted) {
                  return;
                }
                try {
                  await _reload(silent: true);
                } finally {
                  if (mounted &&
                      _busyDepartmentId == department.mutationId) {
                    setState(() => _busyDepartmentId = null);
                  }
                }
              }());
            },
            onPermanentDelete: (DepartmentProfile department) {
              if (_busyDepartmentId != null) {
                return;
              }
              unawaited(() async {
                await _permanentDeleteEntity(
                  context: context,
                  ref: ref,
                  name: department.name,
                  permanentDeleteAction: () => _runBusyDepartmentAction(
                    department,
                    () => ref
                        .read(tenantFacilitySetupSubmissionProvider.notifier)
                        .permanentDeleteDepartment(department.mutationId),
                  ),
                );
                if (!mounted) {
                  return;
                }
                try {
                  await _reload(silent: true);
                } finally {
                  if (mounted &&
                      _busyDepartmentId == department.mutationId) {
                    setState(() => _busyDepartmentId = null);
                  }
                }
              }());
            },
          );

    if (widget.framed) {
      return content;
    }

    return _ModalSectionBody(
      body: l10n.tenantFacilityDepartmentsModalBody,
      blockedMessage: blockedMessage,
      child: content,
    );
  }
}

class _UnitSetupSection extends ConsumerStatefulWidget {
  const _UnitSetupSection({
    required this.snapshot,
    required this.canSubmit,
    this.framed = true,
    this.onListTotalChanged,
  });

  final FacilitySetupSnapshot snapshot;
  final bool canSubmit;
  final bool framed;
  final ValueChanged<int>? onListTotalChanged;

  @override
  ConsumerState<_UnitSetupSection> createState() => _UnitSetupSectionState();
}

class _UnitSetupSectionState extends ConsumerState<_UnitSetupSection> {
  static const AppPageRequest _lookupOptionsRequest = AppPageRequest(
    pageSize: PlatformAdminListConfig.pageSize,
  );

  AppPageRequest _pageRequest = PlatformAdminListConfig.initialPageRequest;
  int _totalItemCount = 0;
  String _searchQuery = '';
  String? _listStatusFilter = 'active';
  Timer? _searchDebounce;

  bool _loading = true;
  AppFailure? _failure;
  bool _departmentsReady = false;
  List<UnitProfile> _units = const <UnitProfile>[];
  List<DepartmentProfile> _departments = const <DepartmentProfile>[];
  List<TenantProfile> _tenantOptions = const <TenantProfile>[];
  List<FacilityProfile> _facilityOptions = const <FacilityProfile>[];
  Map<String, String> _tenantNamesById = const <String, String>{};
  Map<String, String> _facilityNamesById = const <String, String>{};
  Map<String, String> _departmentNamesById = const <String, String>{};
  String? _tenantFilterId;
  String? _facilityFilterId;
  String? _departmentFilterId;
  bool? _isActiveFilter;
  String? _busyUnitId;
  int _reloadGeneration = 0;

  FacilitySetupSnapshot get snapshot => widget.snapshot;

  /// Non-deleted departments visible under the current filters. Drives the
  /// prerequisites gate and the Create form department picker.
  List<DepartmentProfile> get _accessibleDepartments => _departments
      .where((DepartmentProfile department) => !department.isDeleted)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(covariant _UnitSetupSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String? oldFacilityId = oldWidget.snapshot.facility?.id;
    final String? nextFacilityId = widget.snapshot.facility?.id;
    final String? oldTenantId = oldWidget.snapshot.tenant?.id;
    final String? nextTenantId = widget.snapshot.tenant?.id;
    if (oldFacilityId != nextFacilityId || oldTenantId != nextTenantId) {
      unawaited(_reload());
    }
  }

  List<FacilityProfile> get _facilitiesForFilter {
    final String? tenantFilterId = _tenantFilterId?.trim();
    if (tenantFilterId == null || tenantFilterId.isEmpty) {
      return _facilityOptions
          .where((FacilityProfile facility) => !facility.isDeleted)
          .toList(growable: false);
    }
    return _facilityOptions
        .where(
          (FacilityProfile facility) =>
              !facility.isDeleted && facility.tenantId == tenantFilterId,
        )
        .toList(growable: false);
  }

  List<DepartmentProfile> get _departmentsForFilter {
    final String? tenantFilterId = _tenantFilterId?.trim();
    final String? facilityFilterId = _facilityFilterId?.trim();
    return _accessibleDepartments
        .where((DepartmentProfile department) {
          if (tenantFilterId != null &&
              tenantFilterId.isNotEmpty &&
              department.tenantId != tenantFilterId) {
            return false;
          }
          if (facilityFilterId != null &&
              facilityFilterId.isNotEmpty &&
              department.facilityId != facilityFilterId) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  void _applyServerFilters(AppSearchBarFilterValue value) {
    final String? nextTenant = value.option(
      TenantFacilityUnitsFilterKeys.tenant,
    );
    final String? nextFacility = value.option(
      TenantFacilityUnitsFilterKeys.facility,
    );
    final String? nextDepartment = value.option(
      TenantFacilityUnitsFilterKeys.department,
    );
    final String? nextActive = value.option(
      TenantFacilityUnitsFilterKeys.active,
    );

    final bool? parsedActive =
        nextActive == TenantFacilityUnitsFilterKeys.activeYes
        ? true
        : nextActive == TenantFacilityUnitsFilterKeys.activeNo
        ? false
        : null;

    _tenantFilterId = nextTenant;
    _facilityFilterId = nextFacility;
    _departmentFilterId = nextDepartment;
    _isActiveFilter = parsedActive;
    _syncFacilityFilterToOptions();
    _syncDepartmentFilterToOptions();
  }

  void _syncFacilityFilterToOptions() {
    final String? facilityId = _facilityFilterId;
    if (facilityId == null) {
      return;
    }
    final String? tenantFilterId = _tenantFilterId?.trim();
    final bool facilityAllowed = _facilityOptions.any((FacilityProfile facility) {
      if (facility.id != facilityId || facility.isDeleted) {
        return false;
      }
      if (tenantFilterId == null || tenantFilterId.isEmpty) {
        return true;
      }
      return facility.tenantId == tenantFilterId;
    });
    if (!facilityAllowed) {
      _facilityFilterId = null;
    }
  }

  void _syncDepartmentFilterToOptions() {
    final String? departmentId = _departmentFilterId;
    if (departmentId == null) {
      return;
    }
    final bool departmentAllowed = _departmentsForFilter.any(
      (DepartmentProfile department) => department.id == departmentId,
    );
    if (!departmentAllowed) {
      _departmentFilterId = null;
    }
  }

  Future<void> _onFiltersChanged(AppSearchBarFilterValue value) async {
    final String? previousTenant = _tenantFilterId;
    final String? previousFacility = _facilityFilterId;
    _applyServerFilters(value);
    _listStatusFilter = value.option('status');
    _pageRequest = _pageRequest.first();
    final bool tenantChanged = previousTenant != _tenantFilterId;
    final bool facilityChanged = previousFacility != _facilityFilterId;
    if (tenantChanged) {
      await _reloadFacilityOptions();
      _syncFacilityFilterToOptions();
    }
    if (tenantChanged || facilityChanged) {
      _syncDepartmentFilterToOptions();
    }
    await _reload(silent: true);
  }


  void _onSearchChanged(String raw) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      final String next = raw.trim();
      if (next == _searchQuery) {
        return;
      }
      _searchQuery = next;
      _pageRequest = _pageRequest.first();
      unawaited(_reload(silent: true));
    });
  }

  Future<void> _onPageChanged(AppPageRequest request) async {
    _pageRequest = request;
    await _reload(silent: true);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _reloadFacilityOptions() async {
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final TenantFacilityUnitsListScope scope = tenantFacilityUnitsListScope(
      policy,
    );
    if (!tenantFacilityUnitsShowsFacilityFilter(scope)) {
      return;
    }

    final String? tenantId = switch (scope) {
      TenantFacilityUnitsListScope.platform => _tenantFilterId,
      TenantFacilityUnitsListScope.tenant ||
      TenantFacilityUnitsListScope.facility =>
        policy.tenantId ?? snapshot.tenant?.id,
    };

    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );
    final Result<AppPage<FacilityProfile>> result = await repository
        .listFacilities(request: _lookupOptionsRequest, tenantId: tenantId);
    if (!mounted) {
      return;
    }
    result.when(
      success: (AppPage<FacilityProfile> page) {
        setState(() {
          _facilityOptions = page.items;
          _facilityNamesById = <String, String>{
            for (final FacilityProfile facility in page.items)
              facility.id: facility.name,
          };
          if (_facilityFilterId != null &&
              !_facilitiesForFilter.any(
                (FacilityProfile facility) => facility.id == _facilityFilterId,
              )) {
            _facilityFilterId = null;
          }
        });
      },
      failure: (_) {},
    );
  }

  Future<void> _reload({bool silent = false}) async {
    final int generation = ++_reloadGeneration;
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final TenantFacilityUnitsListScope scope = tenantFacilityUnitsListScope(
      policy,
    );
    final String? scopedTenantId = switch (scope) {
      TenantFacilityUnitsListScope.platform => _tenantFilterId,
      TenantFacilityUnitsListScope.tenant ||
      TenantFacilityUnitsListScope.facility =>
        policy.tenantId ?? snapshot.tenant?.id,
    };
    final String? scopedFacilityId =
        scope == TenantFacilityUnitsListScope.facility
        ? (policy.facilityId ?? snapshot.facility?.id)
        : _facilityFilterId;
    final String? scopedDepartmentId = _departmentFilterId;

    if (!silent) {
      setState(() {
        _loading = _units.isEmpty;
        _failure = null;
      });
    }

    if (scope == TenantFacilityUnitsListScope.facility &&
        (scopedFacilityId == null || scopedFacilityId.trim().isEmpty)) {
      if (!mounted || generation != _reloadGeneration) {
        return;
      }
      setState(() {
        _loading = false;
        _departmentsReady = false;
        _units = const <UnitProfile>[];
        _departments = const <DepartmentProfile>[];
        _facilityOptions = const <FacilityProfile>[];
        _tenantOptions = const <TenantProfile>[];
        _tenantNamesById = const <String, String>{};
        _facilityNamesById = const <String, String>{};
        _departmentNamesById = const <String, String>{};
      });
      return;
    }

    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );

    final Future<Result<AppPage<TenantProfile>>>? tenantsFuture =
        tenantFacilityUnitsShowsTenantFilter(scope)
        ? repository.listTenants(
            request: _lookupOptionsRequest,
          )
        : null;
    final Future<Result<AppPage<FacilityProfile>>>? facilitiesFuture =
        tenantFacilityUnitsShowsFacilityFilter(scope)
        ? repository.listFacilities(
            request: _lookupOptionsRequest,
            tenantId: scope == TenantFacilityUnitsListScope.platform
                ? _tenantFilterId
                : scopedTenantId,
          )
        : null;
    final Future<Result<AppPage<DepartmentProfile>>> departmentsFuture =
        repository.listDepartments(
          request: _lookupOptionsRequest,
          tenantId: scopedTenantId,
          facilityId: scopedFacilityId,
          includeDeleted: true,
        );
    final bool includeDeleted = _listStatusFilter != 'active';
    final Future<Result<AppPage<UnitProfile>>> unitsFuture = repository
        .listUnits(
          request: _pageRequest,
          tenantId: scopedTenantId,
          facilityId: scopedFacilityId,
          departmentId: scopedDepartmentId,
          search: _searchQuery.isEmpty ? null : _searchQuery,
          isActive: _isActiveFilter,
          includeDeleted: includeDeleted,
        );

    final Result<AppPage<TenantProfile>>? tenantsResult = tenantsFuture == null
        ? null
        : await tenantsFuture;
    final Result<AppPage<FacilityProfile>>? facilitiesResult =
        facilitiesFuture == null ? null : await facilitiesFuture;
    final Result<AppPage<DepartmentProfile>> departmentsResult =
        await departmentsFuture;
    final Result<AppPage<UnitProfile>> unitsResult = await unitsFuture;

    if (!mounted || generation != _reloadGeneration) {
      return;
    }

    unitsResult.when(
      success: (AppPage<UnitProfile> page) {
        final Map<String, String> tenantNames = <String, String>{
          if (snapshot.tenant case final TenantProfile tenant)
            tenant.id: tenant.name,
        };
        List<TenantProfile> tenants = const <TenantProfile>[];
        tenantsResult?.when(
          success: (AppPage<TenantProfile> tenantsPage) {
            tenants = tenantsPage.items;
            for (final TenantProfile tenant in tenantsPage.items) {
              tenantNames[tenant.id] = tenant.name;
            }
          },
          failure: (_) {},
        );

        List<FacilityProfile> facilities = <FacilityProfile>[
          ...snapshot.facilities,
          if (snapshot.facility != null) snapshot.facility!,
        ];
        facilitiesResult?.when(
          success: (AppPage<FacilityProfile> facilitiesPage) {
            facilities = facilitiesPage.items;
          },
          failure: (_) {},
        );
        final Map<String, String> facilityNames = <String, String>{
          for (final FacilityProfile facility in facilities)
            facility.id: facility.name,
        };

        List<DepartmentProfile> departments = const <DepartmentProfile>[];
        bool departmentsReady = false;
        departmentsResult.when(
          success: (AppPage<DepartmentProfile> departmentsPage) {
            departments = departmentsPage.items;
            departmentsReady = true;
          },
          failure: (_) {},
        );
        final Map<String, String> departmentNames = <String, String>{
          for (final DepartmentProfile department in departments)
            department.id: department.name,
        };

        List<UnitProfile> units = page.items;
        if (_listStatusFilter == 'deleted') {
          units = units
              .where((UnitProfile item) => item.isDeleted)
              .toList(growable: false);
        }
        setState(() {
          _loading = false;
          _failure = null;
          _departmentsReady = departmentsReady;
          _units = units;
          _totalItemCount = _listStatusFilter == 'deleted'
              ? units.length
              : (page.totalItemCount ?? units.length);
          _departments = departments;
          _tenantOptions = tenants;
          _facilityOptions = facilities;
          _tenantNamesById = tenantNames;
          _facilityNamesById = facilityNames;
          _departmentNamesById = departmentNames;
          _syncDepartmentFilterToOptions();
        });
        widget.onListTotalChanged?.call(_totalItemCount);
      },
      failure: (AppFailure failure) {
        setState(() {
          _loading = false;
          _failure = failure;
          if (!silent) {
            _units = const <UnitProfile>[];
            _departmentsReady = false;
          }
        });
      },
    );
  }

  String _facilityLabel(UnitProfile unit) {
    final String? facilityId = unit.facilityId?.trim();
    if (facilityId == null || facilityId.isEmpty) {
      return '—';
    }
    final bool isDeleted = _facilityOptions.any(
      (FacilityProfile facility) =>
          facility.id == facilityId && facility.isDeleted,
    );
    return tenantFacilityRelatedNameLabel(
      _facilityNamesById[facilityId],
      isDeleted: isDeleted,
      deletedLabel: context.l10n.tenantFacilityStructureDeletedStatus,
    );
  }

  String _tenantLabel(UnitProfile unit) {
    final String tenantId = unit.tenantId.trim();
    if (tenantId.isEmpty) {
      return '—';
    }
    final bool isDeleted = _tenantOptions.any(
      (TenantProfile tenant) => tenant.id == tenantId && tenant.isDeleted,
    );
    return tenantFacilityRelatedNameLabel(
      _tenantNamesById[tenantId],
      isDeleted: isDeleted,
      deletedLabel: context.l10n.tenantFacilityStructureDeletedStatus,
    );
  }

  String _departmentLabel(UnitProfile unit) {
    final String? departmentId = unit.departmentId?.trim();
    if (departmentId == null || departmentId.isEmpty) {
      return '—';
    }
    final bool isDeleted = _departments.any(
      (DepartmentProfile department) =>
          department.id == departmentId && department.isDeleted,
    );
    return tenantFacilityRelatedNameLabel(
      _departmentNamesById[departmentId] ??
          _departmentName(snapshot, departmentId),
      isDeleted: isDeleted,
      deletedLabel: context.l10n.tenantFacilityStructureDeletedStatus,
    );
  }

  Future<void> _afterMutation(Future<void> Function() action) async {
    await action();
    if (!mounted) {
      return;
    }
    await _reload(silent: true);
  }

  Future<bool> _runBusyUnitAction(
    UnitProfile unit,
    Future<bool> Function() action,
  ) async {
    if (mounted) {
      setState(() => _busyUnitId = unit.mutationId);
    }
    final bool succeeded = await action();
    if (!succeeded && mounted && _busyUnitId == unit.mutationId) {
      setState(() => _busyUnitId = null);
    }
    return succeeded;
  }

  List<AppSearchBarFilterGroup> _buildFilterGroups(AppLocalizations l10n) {
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final TenantFacilityUnitsListScope scope = tenantFacilityUnitsListScope(
      policy,
    );
    final List<FacilityProfile> facilities = _facilitiesForFilter;
    final List<DepartmentProfile> departments = _departmentsForFilter;

    return <AppSearchBarFilterGroup>[
      if (tenantFacilityUnitsShowsTenantFilter(scope) &&
          _tenantOptions.isNotEmpty)
        AppSearchBarFilterGroup(
          key: TenantFacilityUnitsFilterKeys.tenant,
          label: l10n.profileTenantLabel,
          allLabel: l10n.commonAllLabel,
          choices: _tenantOptions
              .map(
                (TenantProfile tenant) => AppSearchBarFilterChoice(
                  value: tenant.id,
                  label: tenant.name,
                  icon: Icons.apartment_outlined,
                ),
              )
              .toList(growable: false),
        ),
      if (tenantFacilityUnitsShowsFacilityFilter(scope) &&
          facilities.isNotEmpty)
        AppSearchBarFilterGroup(
          key: TenantFacilityUnitsFilterKeys.facility,
          label: l10n.profileFacilityLabel,
          allLabel: l10n.commonAllLabel,
          choices: facilities
              .map(
                (FacilityProfile facility) => AppSearchBarFilterChoice(
                  value: facility.id,
                  label: facility.name,
                  icon: Icons.local_hospital_outlined,
                ),
              )
              .toList(growable: false),
        ),
      if (departments.isNotEmpty)
        AppSearchBarFilterGroup(
          key: TenantFacilityUnitsFilterKeys.department,
          label: l10n.tenantFacilityUnitDepartmentLabel,
          allLabel: l10n.commonAllLabel,
          choices: departments
              .map(
                (DepartmentProfile department) => AppSearchBarFilterChoice(
                  value: department.id,
                  label: department.name,
                  icon: Icons.domain_outlined,
                ),
              )
              .toList(growable: false),
        ),
      AppSearchBarFilterGroup(
        key: TenantFacilityUnitsFilterKeys.active,
        label: l10n.tenantFacilityActiveLabel,
        allLabel: l10n.commonAllLabel,
        choices: <AppSearchBarFilterChoice>[
          AppSearchBarFilterChoice(
            value: TenantFacilityUnitsFilterKeys.activeYes,
            label: l10n.tenantFacilityTenantStatusActive,
            icon: Icons.toggle_on_outlined,
          ),
          AppSearchBarFilterChoice(
            value: TenantFacilityUnitsFilterKeys.activeNo,
            label: l10n.tenantFacilityStatusInactive,
            icon: Icons.toggle_off_outlined,
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppAccessPolicy policy = ref.watch(appAccessPolicyProvider);
    final TenantFacilityUnitsListScope scope = tenantFacilityUnitsListScope(
      policy,
    );
    final bool isSubmitting = ref.watch(
      tenantFacilitySetupSubmissionProvider.select(
        (TenantFacilitySetupSubmissionState state) => state.isSubmitting,
      ),
    );
    final bool canManageRecords = widget.canSubmit;
    final bool hasAccessibleDepartments = _accessibleDepartments.isNotEmpty;
    // Avoid a false gate when departments failed to load independently of units.
    final bool prerequisitesMet =
        !_departmentsReady || hasAccessibleDepartments;
    final bool canAdd =
        canManageRecords &&
        prerequisitesMet &&
        !isSubmitting &&
        _busyUnitId == null;
    final String? blockedMessage =
        canManageRecords && _departmentsReady && !hasAccessibleDepartments
        ? l10n.tenantFacilityGateNeedDepartmentForUnits
        : null;
    final bool showTenantColumn = tenantFacilityUnitsShowsTenantColumn(scope);
    final bool showFacilityColumn = tenantFacilityUnitsShowsFacilityColumn(
      scope,
    );

    final List<AppListTableColumn<UnitProfile>> extraColumns =
        <AppListTableColumn<UnitProfile>>[
          AppListTableColumn<UnitProfile>(
            id: 'department',
            label: l10n.tenantFacilityUnitDepartmentLabel,
            preferredWidth: 160,
            sortComparator: (UnitProfile left, UnitProfile right) =>
                appListTableCompareText(
                  _departmentLabel(left),
                  _departmentLabel(right),
                ),
            exportValue: (UnitProfile unit) => _departmentLabel(unit),
            cellBuilder: (_, UnitProfile unit) =>
                tenantFacilitySetupAtomicCell(_departmentLabel(unit)),
          ),
        ];
    final List<AppListTableColumn<UnitProfile>> optionalColumns =
        <AppListTableColumn<UnitProfile>>[
          if (showFacilityColumn)
            AppListTableColumn<UnitProfile>(
              id: 'facility',
              label: l10n.profileFacilityLabel,
              preferredWidth: 160,
              sortComparator: (UnitProfile left, UnitProfile right) =>
                  appListTableCompareText(
                    _facilityLabel(left),
                    _facilityLabel(right),
                  ),
              exportValue: (UnitProfile unit) => _facilityLabel(unit),
              cellBuilder: (_, UnitProfile unit) =>
                  tenantFacilitySetupAtomicCell(_facilityLabel(unit)),
            ),
          if (showTenantColumn)
            AppListTableColumn<UnitProfile>(
              id: 'tenant',
              label: l10n.profileTenantLabel,
              preferredWidth: 160,
              sortComparator: (UnitProfile left, UnitProfile right) =>
                  appListTableCompareText(
                    _tenantLabel(left),
                    _tenantLabel(right),
                  ),
              exportValue: (UnitProfile unit) => _tenantLabel(unit),
              cellBuilder: (_, UnitProfile unit) =>
                  tenantFacilitySetupAtomicCell(_tenantLabel(unit)),
            ),
        ];

    final Widget content = _loading && _units.isEmpty
        ? AppLoadingIndicator.compact(
            title: l10n.tenantFacilityUnitsLoadingTitle,
            body: l10n.tenantFacilityUnitsLoadingBody,
          )
        : _failure != null && _units.isEmpty
        ? AppWorkspaceStatePanel.error(
            title: l10n.tenantFacilityUnitsListTitle,
            body: l10n.failureMessage(_failure!),
            action: AppButton.secondary(
              label: l10n.commonRetryActionLabel,
              leadingIcon: Icons.refresh,
              onPressed: () => unawaited(_reload()),
            ),
          )
        : _SearchableEntityGroup<UnitProfile>(
            title: l10n.tenantFacilityUnitsListTitle,
            nameColumnLabel: l10n.tenantFacilityUnitNameLabel,
            nameDetailBuilder: (UnitProfile unit) {
              final List<String> details = <String>[];
              final String? unitId = tenantFacilityHumanFriendlyDisplayId(
                unit.displayId,
                opaqueId: unit.resourceUuid ?? unit.id,
              );
              if (unitId != null) {
                details.add(unitId);
              }
              if (showFacilityColumn) {
                final String facility = _facilityLabel(unit);
                if (facility != '—') {
                  details.add(facility);
                }
              }
              if (showTenantColumn) {
                final String tenant = _tenantLabel(unit);
                if (tenant != '—') {
                  details.add(tenant);
                }
              }
              return details;
            },
            items: _units,
            serverDrivenList: true,
            onSearchChanged: _onSearchChanged,
            pageRequest: _pageRequest,
            totalItemCount: _totalItemCount,
            onPageChanged: _onPageChanged,
            emptyLabel: l10n.tenantFacilityNoUnits,
            noResultsLabel: l10n.tenantFacilitySearchNoResults,
            searchLabel: l10n.tenantFacilitySearchLabel,
            searchHint: l10n.tenantFacilityUnitSearchHint,
            addLabel: l10n.tenantFacilityAddUnitAction,
            canManageRecords: canManageRecords,
            canAdd: canAdd,
            isSubmitting: isSubmitting,
            busyItemId: _busyUnitId,
            itemIdBuilder: (UnitProfile unit) => unit.mutationId,
            blockedMessage: blockedMessage,
            onAdd: () => unawaited(
              _afterMutation(
                () => _openUnitDialog(
                  context,
                  snapshot,
                  tenantOptions: _tenantOptions,
                  facilityOptions: _facilityOptions,
                  departmentOptions: _accessibleDepartments,
                ),
              ),
            ),
            onRowSelected: (UnitProfile unit) {
              unawaited(
                _afterMutation(
                  () => _openUnitDetails(
                    context,
                    unit: unit,
                    snapshot: snapshot,
                    tenantName: _tenantLabel(unit),
                    facilityName: _facilityLabel(unit),
                    departmentName: _departmentLabel(unit),
                  ),
                ),
              );
            },
            columnVisibilityStorageKey:
                'setup_structure_units_${scope.name}_v2',
            extraFilterGroups: _buildFilterGroups(l10n),
            onFiltersChanged: (AppSearchBarFilterValue value) {
              unawaited(_onFiltersChanged(value));
            },
            titleBuilder: (UnitProfile unit) => unit.name,
            subtitleBuilder: (UnitProfile unit) {
              final String department = _departmentLabel(unit);
              final String status = unit.isDeleted
                  ? l10n.tenantFacilityStructureDeletedStatus
                  : _activeStatusLabel(l10n, unit.isActive);
              return <String>[
                if (department != '—') department,
                status,
                if (showFacilityColumn) _facilityLabel(unit),
                if (showTenantColumn) _tenantLabel(unit),
              ].where((String part) => part.trim().isNotEmpty).join(', ');
            },
            statusLabelBuilder: (UnitProfile unit) {
              if (unit.isDeleted) {
                return l10n.tenantFacilityStructureDeletedStatus;
              }
              return _activeStatusLabel(l10n, unit.isActive);
            },
            extraColumns: extraColumns,
            optionalColumns: optionalColumns,
            isDeletedBuilder: (UnitProfile unit) => unit.isDeleted,
            onEdit: (UnitProfile unit) {
              if (unit.isDeleted ||
                  isSubmitting ||
                  _busyUnitId != null) {
                return;
              }
              unawaited(() async {
                await _openUnitDialog(
                  context,
                  snapshot,
                  unit: unit,
                  tenantOptions: _tenantOptions,
                  facilityOptions: _facilityOptions,
                  departmentOptions: _accessibleDepartments,
                );
                if (!mounted) {
                  return;
                }
                setState(() => _busyUnitId = unit.mutationId);
                try {
                  await _reload(silent: true);
                } finally {
                  if (mounted && _busyUnitId == unit.mutationId) {
                    setState(() => _busyUnitId = null);
                  }
                }
              }());
            },
            onDelete: (UnitProfile unit) {
              if (_busyUnitId != null) {
                return;
              }
              unawaited(() async {
                await _deleteEntity(
                  context: context,
                  ref: ref,
                  name: unit.name,
                  deleteAction: () => _runBusyUnitAction(
                    unit,
                    () => ref
                        .read(tenantFacilitySetupSubmissionProvider.notifier)
                        .deleteUnit(unit.mutationId),
                  ),
                );
                if (!mounted) {
                  return;
                }
                try {
                  await _reload(silent: true);
                } finally {
                  if (mounted && _busyUnitId == unit.mutationId) {
                    setState(() => _busyUnitId = null);
                  }
                }
              }());
            },
            onRestore: (UnitProfile unit) {
              if (_busyUnitId != null) {
                return;
              }
              unawaited(() async {
                await _restoreEntity(
                  context: context,
                  ref: ref,
                  name: unit.name,
                  restoreAction: () => _runBusyUnitAction(
                    unit,
                    () => ref
                        .read(tenantFacilitySetupSubmissionProvider.notifier)
                        .restoreUnit(unit.mutationId),
                  ),
                );
                if (!mounted) {
                  return;
                }
                try {
                  await _reload(silent: true);
                } finally {
                  if (mounted && _busyUnitId == unit.mutationId) {
                    setState(() => _busyUnitId = null);
                  }
                }
              }());
            },
          );

    if (widget.framed) {
      return content;
    }

    return _ModalSectionBody(
      body: l10n.tenantFacilityUnitsModalBody,
      blockedMessage: blockedMessage,
      child: content,
    );
  }
}

class _WardSetupSection extends ConsumerStatefulWidget {
  const _WardSetupSection({
    required this.snapshot,
    required this.canSubmit,
    this.framed = true,
    this.onListTotalChanged,
  });

  final FacilitySetupSnapshot snapshot;
  final bool canSubmit;
  final bool framed;
  final ValueChanged<int>? onListTotalChanged;

  @override
  ConsumerState<_WardSetupSection> createState() => _WardSetupSectionState();
}

class _WardSetupSectionState extends ConsumerState<_WardSetupSection> {
  static const AppPageRequest _lookupOptionsRequest = AppPageRequest(
    pageSize: PlatformAdminListConfig.pageSize,
  );

  AppPageRequest _pageRequest = PlatformAdminListConfig.initialPageRequest;
  int _totalItemCount = 0;
  String _searchQuery = '';
  String? _listStatusFilter = 'active';
  Timer? _searchDebounce;

  bool _loading = true;
  AppFailure? _failure;
  bool _departmentsReady = false;
  List<WardProfile> _wards = const <WardProfile>[];
  List<DepartmentProfile> _departments = const <DepartmentProfile>[];
  List<TenantProfile> _tenantOptions = const <TenantProfile>[];
  List<FacilityProfile> _facilityOptions = const <FacilityProfile>[];
  Map<String, String> _tenantNamesById = const <String, String>{};
  Map<String, String> _facilityNamesById = const <String, String>{};
  Map<String, String> _departmentNamesById = const <String, String>{};
  String? _tenantFilterId;
  String? _facilityFilterId;
  String? _departmentFilterId;
  WardSetupType? _typeFilter;
  bool? _isActiveFilter;
  String? _busyWardId;
  int _reloadGeneration = 0;

  FacilitySetupSnapshot get snapshot => widget.snapshot;

  /// Non-deleted departments visible under the current filters. Drives the
  /// prerequisites gate and the Create form department picker.
  List<DepartmentProfile> get _accessibleDepartments => _departments
      .where((DepartmentProfile department) => !department.isDeleted)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(covariant _WardSetupSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String? oldFacilityId = oldWidget.snapshot.facility?.id;
    final String? nextFacilityId = widget.snapshot.facility?.id;
    final String? oldTenantId = oldWidget.snapshot.tenant?.id;
    final String? nextTenantId = widget.snapshot.tenant?.id;
    if (oldFacilityId != nextFacilityId || oldTenantId != nextTenantId) {
      unawaited(_reload());
    }
  }

  List<FacilityProfile> get _facilitiesForFilter {
    final String? tenantFilterId = _tenantFilterId?.trim();
    if (tenantFilterId == null || tenantFilterId.isEmpty) {
      return _facilityOptions
          .where((FacilityProfile facility) => !facility.isDeleted)
          .toList(growable: false);
    }
    return _facilityOptions
        .where(
          (FacilityProfile facility) =>
              !facility.isDeleted && facility.tenantId == tenantFilterId,
        )
        .toList(growable: false);
  }

  List<DepartmentProfile> get _departmentsForFilter {
    final String? tenantFilterId = _tenantFilterId?.trim();
    final String? facilityFilterId = _facilityFilterId?.trim();
    return _accessibleDepartments
        .where((DepartmentProfile department) {
          if (tenantFilterId != null &&
              tenantFilterId.isNotEmpty &&
              department.tenantId != tenantFilterId) {
            return false;
          }
          if (facilityFilterId != null &&
              facilityFilterId.isNotEmpty &&
              department.facilityId != facilityFilterId) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  void _applyServerFilters(AppSearchBarFilterValue value) {
    final String? nextTenant = value.option(
      TenantFacilityWardsFilterKeys.tenant,
    );
    final String? nextFacility = value.option(
      TenantFacilityWardsFilterKeys.facility,
    );
    final String? nextDepartment = value.option(
      TenantFacilityWardsFilterKeys.department,
    );
    final String? nextType = value.option(TenantFacilityWardsFilterKeys.type);
    final String? nextActive = value.option(
      TenantFacilityWardsFilterKeys.active,
    );

    WardSetupType? parsedType;
    if (nextType != null) {
      for (final WardSetupType type in WardSetupType.values) {
        if (type.apiValue == nextType) {
          parsedType = type;
          break;
        }
      }
    }

    final bool? parsedActive =
        nextActive == TenantFacilityWardsFilterKeys.activeYes
        ? true
        : nextActive == TenantFacilityWardsFilterKeys.activeNo
        ? false
        : null;

    _tenantFilterId = nextTenant;
    _facilityFilterId = nextFacility;
    _departmentFilterId = nextDepartment;
    _typeFilter = parsedType;
    _isActiveFilter = parsedActive;
    _syncFacilityFilterToOptions();
    _syncDepartmentFilterToOptions();
  }

  void _syncFacilityFilterToOptions() {
    final String? facilityId = _facilityFilterId;
    if (facilityId == null) {
      return;
    }
    final String? tenantFilterId = _tenantFilterId?.trim();
    final bool facilityAllowed = _facilityOptions.any((FacilityProfile facility) {
      if (facility.id != facilityId || facility.isDeleted) {
        return false;
      }
      if (tenantFilterId == null || tenantFilterId.isEmpty) {
        return true;
      }
      return facility.tenantId == tenantFilterId;
    });
    if (!facilityAllowed) {
      _facilityFilterId = null;
    }
  }

  void _syncDepartmentFilterToOptions() {
    final String? departmentId = _departmentFilterId;
    if (departmentId == null) {
      return;
    }
    final bool departmentAllowed = _departmentsForFilter.any(
      (DepartmentProfile department) => department.id == departmentId,
    );
    if (!departmentAllowed) {
      _departmentFilterId = null;
    }
  }

  Future<void> _onFiltersChanged(AppSearchBarFilterValue value) async {
    final String? previousTenant = _tenantFilterId;
    final String? previousFacility = _facilityFilterId;
    _applyServerFilters(value);
    _listStatusFilter = value.option('status');
    _pageRequest = _pageRequest.first();
    final bool tenantChanged = previousTenant != _tenantFilterId;
    final bool facilityChanged = previousFacility != _facilityFilterId;
    if (tenantChanged) {
      await _reloadFacilityOptions();
      _syncFacilityFilterToOptions();
    }
    if (tenantChanged || facilityChanged) {
      _syncDepartmentFilterToOptions();
    }
    await _reload(silent: true);
  }


  void _onSearchChanged(String raw) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      final String next = raw.trim();
      if (next == _searchQuery) {
        return;
      }
      _searchQuery = next;
      _pageRequest = _pageRequest.first();
      unawaited(_reload(silent: true));
    });
  }

  Future<void> _onPageChanged(AppPageRequest request) async {
    _pageRequest = request;
    await _reload(silent: true);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _reloadFacilityOptions() async {
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final TenantFacilityWardsListScope scope = tenantFacilityWardsListScope(
      policy,
    );
    if (!tenantFacilityWardsShowsFacilityFilter(scope)) {
      return;
    }

    final String? tenantId = switch (scope) {
      TenantFacilityWardsListScope.platform => _tenantFilterId,
      TenantFacilityWardsListScope.tenant ||
      TenantFacilityWardsListScope.facility =>
        policy.tenantId ?? snapshot.tenant?.id,
    };

    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );
    final Result<AppPage<FacilityProfile>> result = await repository
        .listFacilities(request: _lookupOptionsRequest, tenantId: tenantId);
    if (!mounted) {
      return;
    }
    result.when(
      success: (AppPage<FacilityProfile> page) {
        setState(() {
          _facilityOptions = page.items;
          _facilityNamesById = <String, String>{
            for (final FacilityProfile facility in page.items)
              facility.id: facility.name,
          };
          if (_facilityFilterId != null &&
              !_facilitiesForFilter.any(
                (FacilityProfile facility) => facility.id == _facilityFilterId,
              )) {
            _facilityFilterId = null;
          }
        });
      },
      failure: (_) {},
    );
  }

  Future<void> _reload({bool silent = false}) async {
    final int generation = ++_reloadGeneration;
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final TenantFacilityWardsListScope scope = tenantFacilityWardsListScope(
      policy,
    );
    final String? scopedTenantId = switch (scope) {
      TenantFacilityWardsListScope.platform => _tenantFilterId,
      TenantFacilityWardsListScope.tenant ||
      TenantFacilityWardsListScope.facility =>
        policy.tenantId ?? snapshot.tenant?.id,
    };
    final String? scopedFacilityId =
        scope == TenantFacilityWardsListScope.facility
        ? (policy.facilityId ?? snapshot.facility?.id)
        : _facilityFilterId;
    final String? scopedDepartmentId = _departmentFilterId;

    if (!silent) {
      setState(() {
        _loading = _wards.isEmpty;
        _failure = null;
      });
    }

    if (scope == TenantFacilityWardsListScope.facility &&
        (scopedFacilityId == null || scopedFacilityId.trim().isEmpty)) {
      if (!mounted || generation != _reloadGeneration) {
        return;
      }
      setState(() {
        _loading = false;
        _departmentsReady = false;
        _wards = const <WardProfile>[];
        _departments = const <DepartmentProfile>[];
        _facilityOptions = const <FacilityProfile>[];
        _tenantOptions = const <TenantProfile>[];
        _tenantNamesById = const <String, String>{};
        _facilityNamesById = const <String, String>{};
        _departmentNamesById = const <String, String>{};
      });
      return;
    }

    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );

    final Future<Result<AppPage<TenantProfile>>>? tenantsFuture =
        tenantFacilityWardsShowsTenantFilter(scope)
        ? repository.listTenants(
            request: _lookupOptionsRequest,
          )
        : null;
    final Future<Result<AppPage<FacilityProfile>>>? facilitiesFuture =
        tenantFacilityWardsShowsFacilityFilter(scope)
        ? repository.listFacilities(
            request: _lookupOptionsRequest,
            tenantId: scope == TenantFacilityWardsListScope.platform
                ? _tenantFilterId
                : scopedTenantId,
          )
        : null;
    final Future<Result<AppPage<DepartmentProfile>>> departmentsFuture =
        repository.listDepartments(
          request: _lookupOptionsRequest,
          tenantId: scopedTenantId,
          facilityId: scopedFacilityId,
          includeDeleted: true,
        );
    final bool includeDeleted = _listStatusFilter != 'active';
    final Future<Result<AppPage<WardProfile>>> wardsFuture = repository
        .listWards(
          request: _pageRequest,
          tenantId: scopedTenantId,
          facilityId: scopedFacilityId,
          departmentId: scopedDepartmentId,
          search: _searchQuery.isEmpty ? null : _searchQuery,
          type: _typeFilter,
          isActive: _isActiveFilter,
          includeDeleted: includeDeleted,
        );

    final Result<AppPage<TenantProfile>>? tenantsResult = tenantsFuture == null
        ? null
        : await tenantsFuture;
    final Result<AppPage<FacilityProfile>>? facilitiesResult =
        facilitiesFuture == null ? null : await facilitiesFuture;
    final Result<AppPage<DepartmentProfile>> departmentsResult =
        await departmentsFuture;
    final Result<AppPage<WardProfile>> wardsResult = await wardsFuture;

    if (!mounted || generation != _reloadGeneration) {
      return;
    }

    wardsResult.when(
      success: (AppPage<WardProfile> page) {
        final Map<String, String> tenantNames = <String, String>{
          if (snapshot.tenant case final TenantProfile tenant)
            tenant.id: tenant.name,
        };
        List<TenantProfile> tenants = const <TenantProfile>[];
        tenantsResult?.when(
          success: (AppPage<TenantProfile> tenantsPage) {
            tenants = tenantsPage.items;
            for (final TenantProfile tenant in tenantsPage.items) {
              tenantNames[tenant.id] = tenant.name;
            }
          },
          failure: (_) {},
        );

        List<FacilityProfile> facilities = <FacilityProfile>[
          ...snapshot.facilities,
          if (snapshot.facility != null) snapshot.facility!,
        ];
        facilitiesResult?.when(
          success: (AppPage<FacilityProfile> facilitiesPage) {
            facilities = facilitiesPage.items;
          },
          failure: (_) {},
        );
        final Map<String, String> facilityNames = <String, String>{
          for (final FacilityProfile facility in facilities)
            facility.id: facility.name,
        };

        List<DepartmentProfile> departments = const <DepartmentProfile>[];
        bool departmentsReady = false;
        departmentsResult.when(
          success: (AppPage<DepartmentProfile> departmentsPage) {
            departments = departmentsPage.items;
            departmentsReady = true;
          },
          failure: (_) {},
        );
        final Map<String, String> departmentNames = <String, String>{
          for (final DepartmentProfile department in departments)
            department.id: department.name,
        };

        List<WardProfile> wards = page.items;
        if (_listStatusFilter == 'deleted') {
          wards = wards
              .where((WardProfile item) => item.isDeleted)
              .toList(growable: false);
        }
        setState(() {
          _loading = false;
          _failure = null;
          _departmentsReady = departmentsReady;
          _wards = wards;
          _totalItemCount = _listStatusFilter == 'deleted'
              ? wards.length
              : (page.totalItemCount ?? wards.length);
          _departments = departments;
          _tenantOptions = tenants;
          _facilityOptions = facilities;
          _tenantNamesById = tenantNames;
          _facilityNamesById = facilityNames;
          _departmentNamesById = departmentNames;
          _syncDepartmentFilterToOptions();
        });
        widget.onListTotalChanged?.call(_totalItemCount);
      },
      failure: (AppFailure failure) {
        setState(() {
          _loading = false;
          _failure = failure;
          if (!silent) {
            _wards = const <WardProfile>[];
            _departmentsReady = false;
          }
        });
      },
    );
  }

  String _facilityLabel(WardProfile ward) {
    final String facilityId = ward.facilityId.trim();
    if (facilityId.isEmpty) {
      return '—';
    }
    final bool isDeleted = _facilityOptions.any(
      (FacilityProfile facility) =>
          facility.id == facilityId && facility.isDeleted,
    );
    return tenantFacilityRelatedNameLabel(
      _facilityNamesById[facilityId],
      isDeleted: isDeleted,
      deletedLabel: context.l10n.tenantFacilityStructureDeletedStatus,
    );
  }

  String _tenantLabel(WardProfile ward) {
    final String tenantId = ward.tenantId.trim();
    if (tenantId.isEmpty) {
      return '—';
    }
    final bool isDeleted = _tenantOptions.any(
      (TenantProfile tenant) => tenant.id == tenantId && tenant.isDeleted,
    );
    return tenantFacilityRelatedNameLabel(
      _tenantNamesById[tenantId],
      isDeleted: isDeleted,
      deletedLabel: context.l10n.tenantFacilityStructureDeletedStatus,
    );
  }

  String _departmentLabel(WardProfile ward) {
    final String? departmentId = ward.departmentId?.trim();
    if (departmentId == null || departmentId.isEmpty) {
      return '—';
    }
    final bool isDeleted = _departments.any(
      (DepartmentProfile department) =>
          department.id == departmentId && department.isDeleted,
    );
    return tenantFacilityRelatedNameLabel(
      _departmentNamesById[departmentId] ??
          _departmentName(snapshot, departmentId),
      isDeleted: isDeleted,
      deletedLabel: context.l10n.tenantFacilityStructureDeletedStatus,
    );
  }

  Future<void> _afterMutation(Future<void> Function() action) async {
    await action();
    if (!mounted) {
      return;
    }
    await _reload(silent: true);
  }

  Future<bool> _runBusyWardAction(
    WardProfile ward,
    Future<bool> Function() action,
  ) async {
    if (mounted) {
      setState(() => _busyWardId = ward.id);
    }
    final bool succeeded = await action();
    if (!succeeded && mounted && _busyWardId == ward.id) {
      setState(() => _busyWardId = null);
    }
    return succeeded;
  }

  List<AppSearchBarFilterGroup> _buildFilterGroups(AppLocalizations l10n) {
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final TenantFacilityWardsListScope scope = tenantFacilityWardsListScope(
      policy,
    );
    final List<FacilityProfile> facilities = _facilitiesForFilter;
    final List<DepartmentProfile> departments = _departmentsForFilter;

    return <AppSearchBarFilterGroup>[
      if (tenantFacilityWardsShowsTenantFilter(scope) &&
          _tenantOptions.isNotEmpty)
        AppSearchBarFilterGroup(
          key: TenantFacilityWardsFilterKeys.tenant,
          label: l10n.profileTenantLabel,
          allLabel: l10n.commonAllLabel,
          choices: _tenantOptions
              .map(
                (TenantProfile tenant) => AppSearchBarFilterChoice(
                  value: tenant.id,
                  label: tenant.name,
                  icon: Icons.apartment_outlined,
                ),
              )
              .toList(growable: false),
        ),
      if (tenantFacilityWardsShowsFacilityFilter(scope) &&
          facilities.isNotEmpty)
        AppSearchBarFilterGroup(
          key: TenantFacilityWardsFilterKeys.facility,
          label: l10n.profileFacilityLabel,
          allLabel: l10n.commonAllLabel,
          choices: facilities
              .map(
                (FacilityProfile facility) => AppSearchBarFilterChoice(
                  value: facility.id,
                  label: facility.name,
                  icon: Icons.local_hospital_outlined,
                ),
              )
              .toList(growable: false),
        ),
      if (departments.isNotEmpty)
        AppSearchBarFilterGroup(
          key: TenantFacilityWardsFilterKeys.department,
          label: l10n.tenantFacilityWardDepartmentLabel,
          allLabel: l10n.commonAllLabel,
          choices: departments
              .map(
                (DepartmentProfile department) => AppSearchBarFilterChoice(
                  value: department.id,
                  label: department.name,
                  icon: Icons.domain_outlined,
                ),
              )
              .toList(growable: false),
        ),
      AppSearchBarFilterGroup(
        key: TenantFacilityWardsFilterKeys.type,
        label: l10n.tenantFacilityWardTypeLabel,
        allLabel: l10n.commonAllLabel,
        choices: WardSetupType.values
            .map(
              (WardSetupType type) => AppSearchBarFilterChoice(
                value: type.apiValue,
                label: _wardTypeLabel(l10n, type),
                icon: Icons.category_outlined,
              ),
            )
            .toList(growable: false),
      ),
      AppSearchBarFilterGroup(
        key: TenantFacilityWardsFilterKeys.active,
        label: l10n.tenantFacilityActiveLabel,
        allLabel: l10n.commonAllLabel,
        choices: <AppSearchBarFilterChoice>[
          AppSearchBarFilterChoice(
            value: TenantFacilityWardsFilterKeys.activeYes,
            label: l10n.tenantFacilityTenantStatusActive,
            icon: Icons.toggle_on_outlined,
          ),
          AppSearchBarFilterChoice(
            value: TenantFacilityWardsFilterKeys.activeNo,
            label: l10n.tenantFacilityStatusInactive,
            icon: Icons.toggle_off_outlined,
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppAccessPolicy policy = ref.watch(appAccessPolicyProvider);
    final TenantFacilityWardsListScope scope = tenantFacilityWardsListScope(
      policy,
    );
    final bool isSubmitting = ref.watch(
      tenantFacilitySetupSubmissionProvider.select(
        (TenantFacilitySetupSubmissionState state) => state.isSubmitting,
      ),
    );
    final bool canManageRecords = widget.canSubmit;
    final bool hasAccessibleDepartments = _accessibleDepartments.isNotEmpty;
    // Avoid a false gate when departments failed to load independently of wards.
    final bool prerequisitesMet =
        !_departmentsReady || hasAccessibleDepartments;
    final bool canAdd =
        canManageRecords &&
        prerequisitesMet &&
        !isSubmitting &&
        _busyWardId == null;
    final String? blockedMessage =
        canManageRecords && _departmentsReady && !hasAccessibleDepartments
        ? l10n.tenantFacilityGateNeedDepartmentForWards
        : null;
    final bool showTenantColumn = tenantFacilityWardsShowsTenantColumn(scope);
    final bool showFacilityColumn = tenantFacilityWardsShowsFacilityColumn(
      scope,
    );

    // Default-visible extras stay at type only so the table defaults to
    // # / name / type / status / actions. Nest department, facility, and
    // tenant under the name cell (and keep them searchable via subtitle).
    final List<AppListTableColumn<WardProfile>> extraColumns =
        <AppListTableColumn<WardProfile>>[
          AppListTableColumn<WardProfile>(
            id: 'type',
            label: l10n.tenantFacilityWardTypeLabel,
            preferredWidth: 120,
            sortComparator: (WardProfile left, WardProfile right) =>
                appListTableCompareText(
                  _wardTypeLabel(l10n, left.type),
                  _wardTypeLabel(l10n, right.type),
                ),
            exportValue: (WardProfile ward) =>
                _wardTypeLabel(l10n, ward.type),
            cellBuilder: (_, WardProfile ward) => tenantFacilitySetupAtomicCell(
              _wardTypeLabel(l10n, ward.type),
            ),
          ),
        ];
    final List<AppListTableColumn<WardProfile>> optionalColumns =
        <AppListTableColumn<WardProfile>>[
          AppListTableColumn<WardProfile>(
            id: 'department',
            label: l10n.tenantFacilityUnitDepartmentLabel,
            preferredWidth: 160,
            sortComparator: (WardProfile left, WardProfile right) =>
                appListTableCompareText(
                  _departmentLabel(left),
                  _departmentLabel(right),
                ),
            exportValue: (WardProfile ward) => _departmentLabel(ward),
            cellBuilder: (_, WardProfile ward) =>
                tenantFacilitySetupAtomicCell(_departmentLabel(ward)),
          ),
          if (showFacilityColumn)
            AppListTableColumn<WardProfile>(
              id: 'facility',
              label: l10n.profileFacilityLabel,
              preferredWidth: 160,
              sortComparator: (WardProfile left, WardProfile right) =>
                  appListTableCompareText(
                    _facilityLabel(left),
                    _facilityLabel(right),
                  ),
              exportValue: (WardProfile ward) => _facilityLabel(ward),
              cellBuilder: (_, WardProfile ward) =>
                  tenantFacilitySetupAtomicCell(_facilityLabel(ward)),
            ),
          if (showTenantColumn)
            AppListTableColumn<WardProfile>(
              id: 'tenant',
              label: l10n.profileTenantLabel,
              preferredWidth: 160,
              sortComparator: (WardProfile left, WardProfile right) =>
                  appListTableCompareText(
                    _tenantLabel(left),
                    _tenantLabel(right),
                  ),
              exportValue: (WardProfile ward) => _tenantLabel(ward),
              cellBuilder: (_, WardProfile ward) =>
                  tenantFacilitySetupAtomicCell(_tenantLabel(ward)),
            ),
        ];

    final Widget content = _loading && _wards.isEmpty
        ? AppLoadingIndicator.compact(
            title: l10n.commonLoadingTitle,
            body: l10n.commonLoadingBody,
          )
        : _failure != null && _wards.isEmpty
        ? AppWorkspaceStatePanel.error(
            title: l10n.tenantFacilityWardsLabel,
            body: l10n.failureMessage(_failure!),
            action: AppButton.secondary(
              label: l10n.commonRetryActionLabel,
              leadingIcon: Icons.refresh,
              onPressed: () => unawaited(_reload()),
            ),
          )
        : _SearchableEntityGroup<WardProfile>(
            title: l10n.tenantFacilityWardsLabel,
            nameColumnLabel: l10n.tenantFacilityWardNameLabel,
            nameDetailBuilder: (WardProfile ward) {
              final List<String> details = <String>[];
              final String? wardId = tenantFacilityHumanFriendlyDisplayId(
                ward.displayId,
                opaqueId: ward.resourceUuid ?? ward.id,
              );
              if (wardId != null) {
                details.add(wardId);
              }
              final String department = _departmentLabel(ward);
              if (department != '—') {
                details.add(department);
              }
              if (showFacilityColumn) {
                final String facility = _facilityLabel(ward);
                if (facility != '—') {
                  details.add(facility);
                }
              }
              if (showTenantColumn) {
                final String tenant = _tenantLabel(ward);
                if (tenant != '—') {
                  details.add(tenant);
                }
              }
              return details;
            },
            items: _wards,
            serverDrivenList: true,
            onSearchChanged: _onSearchChanged,
            pageRequest: _pageRequest,
            totalItemCount: _totalItemCount,
            onPageChanged: _onPageChanged,
            emptyLabel: l10n.tenantFacilityNoWards,
            noResultsLabel: l10n.tenantFacilitySearchNoResults,
            searchLabel: l10n.tenantFacilitySearchLabel,
            searchHint: l10n.tenantFacilityWardSearchHint,
            addLabel: l10n.tenantFacilityAddWardAction,
            canManageRecords: canManageRecords,
            canAdd: canAdd,
            isSubmitting: isSubmitting,
            busyItemId: _busyWardId,
            itemIdBuilder: (WardProfile ward) => ward.id,
            blockedMessage: blockedMessage,
            onAdd: () => unawaited(
              _afterMutation(
                () => _openWardDialog(
                  context,
                  snapshot,
                  tenantOptions: _tenantOptions,
                  facilityOptions: _facilityOptions,
                  departmentOptions: _accessibleDepartments,
                ),
              ),
            ),
            onRowSelected: (WardProfile ward) {
              unawaited(
                _afterMutation(
                  () => _openWardDetails(
                    context,
                    ward: ward,
                    snapshot: snapshot,
                    tenantName: _tenantLabel(ward),
                    facilityName: _facilityLabel(ward),
                    departmentName: _departmentLabel(ward),
                  ),
                ),
              );
            },
            columnVisibilityStorageKey:
                'setup_structure_wards_${scope.name}_v2',
            extraFilterGroups: _buildFilterGroups(l10n),
            onFiltersChanged: (AppSearchBarFilterValue value) {
              unawaited(_onFiltersChanged(value));
            },
            titleBuilder: (WardProfile ward) => ward.name,
            subtitleBuilder: (WardProfile ward) {
              final String department = _departmentLabel(ward);
              final String status = ward.isDeleted
                  ? l10n.tenantFacilityStructureDeletedStatus
                  : _activeStatusLabel(l10n, ward.isActive);
              return <String>[
                _wardTypeLabel(l10n, ward.type),
                if (department != '—') department,
                status,
                if (showFacilityColumn) _facilityLabel(ward),
                if (showTenantColumn) _tenantLabel(ward),
              ].where((String part) => part.trim().isNotEmpty && part != '—')
                  .join(', ');
            },
            statusLabelBuilder: (WardProfile ward) {
              if (ward.isDeleted) {
                return l10n.tenantFacilityStructureDeletedStatus;
              }
              return _activeStatusLabel(l10n, ward.isActive);
            },
            extraColumns: extraColumns,
            optionalColumns: optionalColumns,
            isDeletedBuilder: (WardProfile ward) => ward.isDeleted,
            onEdit: (WardProfile ward) {
              if (ward.isDeleted ||
                  isSubmitting ||
                  _busyWardId != null) {
                return;
              }
              unawaited(() async {
                await _openWardDialog(
                  context,
                  snapshot,
                  ward: ward,
                  tenantOptions: _tenantOptions,
                  facilityOptions: _facilityOptions,
                  departmentOptions: _accessibleDepartments,
                );
                if (!mounted) {
                  return;
                }
                setState(() => _busyWardId = ward.id);
                try {
                  await _reload(silent: true);
                } finally {
                  if (mounted && _busyWardId == ward.id) {
                    setState(() => _busyWardId = null);
                  }
                }
              }());
            },
            onDelete: (WardProfile ward) {
              if (_busyWardId != null) {
                return;
              }
              unawaited(() async {
                await _deleteEntity(
                  context: context,
                  ref: ref,
                  name: ward.name,
                  deleteAction: () => _runBusyWardAction(
                    ward,
                    () => ref
                        .read(tenantFacilitySetupSubmissionProvider.notifier)
                        .deleteWard(ward.id),
                  ),
                );
                if (!mounted) {
                  return;
                }
                try {
                  await _reload(silent: true);
                } finally {
                  if (mounted && _busyWardId == ward.id) {
                    setState(() => _busyWardId = null);
                  }
                }
              }());
            },
            onRestore: (WardProfile ward) {
              if (_busyWardId != null) {
                return;
              }
              unawaited(() async {
                await _restoreEntity(
                  context: context,
                  ref: ref,
                  name: ward.name,
                  restoreAction: () => _runBusyWardAction(
                    ward,
                    () => ref
                        .read(tenantFacilitySetupSubmissionProvider.notifier)
                        .restoreWard(ward.id),
                  ),
                );
                if (!mounted) {
                  return;
                }
                try {
                  await _reload(silent: true);
                } finally {
                  if (mounted && _busyWardId == ward.id) {
                    setState(() => _busyWardId = null);
                  }
                }
              }());
            },
          );

    if (widget.framed) {
      return content;
    }

    return _ModalSectionBody(
      body: l10n.tenantFacilityWardsModalBody,
      blockedMessage: blockedMessage,
      child: content,
    );
  }
}

class _RoomSetupSection extends ConsumerStatefulWidget {
  const _RoomSetupSection({
    required this.snapshot,
    required this.canSubmit,
    this.framed = true,
    this.onListTotalChanged,
  });

  final FacilitySetupSnapshot snapshot;
  final bool canSubmit;
  final bool framed;
  final ValueChanged<int>? onListTotalChanged;

  @override
  ConsumerState<_RoomSetupSection> createState() => _RoomSetupSectionState();
}

class _RoomSetupSectionState extends ConsumerState<_RoomSetupSection> {
  static const AppPageRequest _lookupOptionsRequest = AppPageRequest(
    pageSize: PlatformAdminListConfig.pageSize,
  );

  AppPageRequest _pageRequest = PlatformAdminListConfig.initialPageRequest;
  int _totalItemCount = 0;
  String _searchQuery = '';
  String? _listStatusFilter = 'active';
  Timer? _searchDebounce;

  bool _loading = true;
  AppFailure? _failure;
  bool _facilitiesReady = false;
  List<RoomProfile> _rooms = const <RoomProfile>[];
  List<WardProfile> _wards = const <WardProfile>[];
  List<TenantProfile> _tenantOptions = const <TenantProfile>[];
  List<FacilityProfile> _facilityOptions = const <FacilityProfile>[];
  Map<String, String> _tenantNamesById = const <String, String>{};
  Map<String, String> _facilityNamesById = const <String, String>{};
  Map<String, String> _wardNamesById = const <String, String>{};
  String? _tenantFilterId;
  String? _facilityFilterId;
  String? _wardFilterId;
  String? _busyRoomId;
  int _reloadGeneration = 0;

  FacilitySetupSnapshot get snapshot => widget.snapshot;

  /// Non-deleted facilities visible under the current scope. Drives the
  /// prerequisites gate and Create enablement.
  List<FacilityProfile> get _accessibleFacilities {
    final List<FacilityProfile> fromOptions = _facilityOptions
        .where((FacilityProfile facility) => !facility.isDeleted)
        .toList(growable: false);
    if (fromOptions.isNotEmpty) {
      return fromOptions;
    }
    final FacilityProfile? snapshotFacility = snapshot.facility;
    if (snapshotFacility != null && !snapshotFacility.isDeleted) {
      return <FacilityProfile>[snapshotFacility];
    }
    return snapshot.facilities
        .where((FacilityProfile facility) => !facility.isDeleted)
        .toList(growable: false);
  }

  List<WardProfile> get _accessibleWards => _wards
      .where((WardProfile ward) => !ward.isDeleted)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(covariant _RoomSetupSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String? oldFacilityId = oldWidget.snapshot.facility?.id;
    final String? nextFacilityId = widget.snapshot.facility?.id;
    final String? oldTenantId = oldWidget.snapshot.tenant?.id;
    final String? nextTenantId = widget.snapshot.tenant?.id;
    if (oldFacilityId != nextFacilityId || oldTenantId != nextTenantId) {
      unawaited(_reload());
    }
  }

  List<FacilityProfile> get _facilitiesForFilter {
    final String? tenantFilterId = _tenantFilterId?.trim();
    if (tenantFilterId == null || tenantFilterId.isEmpty) {
      return _facilityOptions
          .where((FacilityProfile facility) => !facility.isDeleted)
          .toList(growable: false);
    }
    return _facilityOptions
        .where(
          (FacilityProfile facility) =>
              !facility.isDeleted && facility.tenantId == tenantFilterId,
        )
        .toList(growable: false);
  }

  List<WardProfile> get _wardsForFilter {
    final String? tenantFilterId = _tenantFilterId?.trim();
    final String? facilityFilterId = _facilityFilterId?.trim();
    return _accessibleWards
        .where((WardProfile ward) {
          if (tenantFilterId != null &&
              tenantFilterId.isNotEmpty &&
              ward.tenantId != tenantFilterId) {
            return false;
          }
          if (facilityFilterId != null &&
              facilityFilterId.isNotEmpty &&
              ward.facilityId != facilityFilterId) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  void _applyServerFilters(AppSearchBarFilterValue value) {
    final String? nextTenant = value.option(
      TenantFacilityRoomsFilterKeys.tenant,
    );
    final String? nextFacility = value.option(
      TenantFacilityRoomsFilterKeys.facility,
    );
    final String? nextWard = value.option(TenantFacilityRoomsFilterKeys.ward);

    _tenantFilterId = nextTenant;
    _facilityFilterId = nextFacility;
    _wardFilterId = nextWard;
    _syncFacilityFilterToOptions();
    _syncWardFilterToOptions();
  }

  void _syncFacilityFilterToOptions() {
    final String? facilityId = _facilityFilterId;
    if (facilityId == null) {
      return;
    }
    final String? tenantFilterId = _tenantFilterId?.trim();
    final bool facilityAllowed = _facilityOptions.any((FacilityProfile facility) {
      if (facility.id != facilityId || facility.isDeleted) {
        return false;
      }
      if (tenantFilterId == null || tenantFilterId.isEmpty) {
        return true;
      }
      return facility.tenantId == tenantFilterId;
    });
    if (!facilityAllowed) {
      _facilityFilterId = null;
    }
  }

  void _syncWardFilterToOptions() {
    final String? wardId = _wardFilterId;
    if (wardId == null) {
      return;
    }
    final bool wardAllowed = _wardsForFilter.any(
      (WardProfile ward) => ward.id == wardId,
    );
    if (!wardAllowed) {
      _wardFilterId = null;
    }
  }

  Future<void> _onFiltersChanged(AppSearchBarFilterValue value) async {
    final String? previousTenant = _tenantFilterId;
    final String? previousFacility = _facilityFilterId;
    _applyServerFilters(value);
    _listStatusFilter = value.option(TenantFacilityRoomsFilterKeys.status);
    _pageRequest = _pageRequest.first();
    final bool tenantChanged = previousTenant != _tenantFilterId;
    final bool facilityChanged = previousFacility != _facilityFilterId;
    if (tenantChanged) {
      await _reloadFacilityOptions();
      _syncFacilityFilterToOptions();
    }
    if (tenantChanged || facilityChanged) {
      _syncWardFilterToOptions();
    }
    await _reload(silent: true);
  }

  void _onSearchChanged(String raw) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      final String next = raw.trim();
      if (next == _searchQuery) {
        return;
      }
      _searchQuery = next;
      _pageRequest = _pageRequest.first();
      unawaited(_reload(silent: true));
    });
  }

  Future<void> _onPageChanged(AppPageRequest request) async {
    _pageRequest = request;
    await _reload(silent: true);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _reloadFacilityOptions() async {
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final TenantFacilityRoomsListScope scope = tenantFacilityRoomsListScope(
      policy,
    );
    if (!tenantFacilityRoomsShowsFacilityFilter(scope)) {
      return;
    }

    final String? tenantId = switch (scope) {
      TenantFacilityRoomsListScope.platform => _tenantFilterId,
      TenantFacilityRoomsListScope.tenant ||
      TenantFacilityRoomsListScope.facility =>
        policy.tenantId ?? snapshot.tenant?.id,
    };

    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );
    final Result<AppPage<FacilityProfile>> result = await repository
        .listFacilities(request: _lookupOptionsRequest, tenantId: tenantId);
    if (!mounted) {
      return;
    }
    result.when(
      success: (AppPage<FacilityProfile> page) {
        setState(() {
          _facilityOptions = page.items;
          _facilityNamesById = <String, String>{
            for (final FacilityProfile facility in page.items)
              facility.id: facility.name,
          };
          if (_facilityFilterId != null &&
              !_facilitiesForFilter.any(
                (FacilityProfile facility) => facility.id == _facilityFilterId,
              )) {
            _facilityFilterId = null;
          }
        });
      },
      failure: (_) {},
    );
  }

  Future<void> _reload({bool silent = false}) async {
    final int generation = ++_reloadGeneration;
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final TenantFacilityRoomsListScope scope = tenantFacilityRoomsListScope(
      policy,
    );
    final String? scopedTenantId = switch (scope) {
      TenantFacilityRoomsListScope.platform => _tenantFilterId,
      TenantFacilityRoomsListScope.tenant ||
      TenantFacilityRoomsListScope.facility =>
        policy.tenantId ?? snapshot.tenant?.id,
    };
    final String? scopedFacilityId =
        scope == TenantFacilityRoomsListScope.facility
        ? (policy.facilityId ?? snapshot.facility?.id)
        : _facilityFilterId;
    final String? scopedWardId = _wardFilterId;

    if (!silent) {
      setState(() {
        _loading = _rooms.isEmpty;
        _failure = null;
      });
    }

    if (scope == TenantFacilityRoomsListScope.facility &&
        (scopedFacilityId == null || scopedFacilityId.trim().isEmpty)) {
      if (!mounted || generation != _reloadGeneration) {
        return;
      }
      setState(() {
        _loading = false;
        _facilitiesReady = false;
        _rooms = const <RoomProfile>[];
        _wards = const <WardProfile>[];
        _facilityOptions = const <FacilityProfile>[];
        _tenantOptions = const <TenantProfile>[];
        _tenantNamesById = const <String, String>{};
        _facilityNamesById = const <String, String>{};
        _wardNamesById = const <String, String>{};
      });
      return;
    }

    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );

    final Future<Result<AppPage<TenantProfile>>>? tenantsFuture =
        tenantFacilityRoomsShowsTenantFilter(scope)
        ? repository.listTenants(
            request: _lookupOptionsRequest,
          )
        : null;
    final bool loadFacilities =
        tenantFacilityRoomsShowsFacilityFilter(scope) ||
        scope == TenantFacilityRoomsListScope.platform ||
        scope == TenantFacilityRoomsListScope.tenant;
    final Future<Result<AppPage<FacilityProfile>>>? facilitiesFuture =
        loadFacilities
        ? repository.listFacilities(
            request: _lookupOptionsRequest,
            tenantId: scope == TenantFacilityRoomsListScope.platform
                ? _tenantFilterId
                : scopedTenantId,
            includeDeleted: true,
          )
        : null;
    final Future<Result<AppPage<WardProfile>>> wardsFuture = repository
        .listWards(
          request: _lookupOptionsRequest,
          tenantId: scopedTenantId,
          facilityId: scopedFacilityId,
          includeDeleted: true,
        );
    final bool includeDeleted = _listStatusFilter != 'active';
    final Future<Result<AppPage<RoomProfile>>> roomsFuture = repository
        .listRooms(
          request: _pageRequest,
          tenantId: scopedTenantId,
          facilityId: scopedFacilityId,
          wardId: scopedWardId,
          search: _searchQuery.isEmpty ? null : _searchQuery,
          includeDeleted: includeDeleted,
        );

    final Result<AppPage<TenantProfile>>? tenantsResult = tenantsFuture == null
        ? null
        : await tenantsFuture;
    final Result<AppPage<FacilityProfile>>? facilitiesResult =
        facilitiesFuture == null ? null : await facilitiesFuture;
    final Result<AppPage<WardProfile>> wardsResult = await wardsFuture;
    final Result<AppPage<RoomProfile>> roomsResult = await roomsFuture;

    if (!mounted || generation != _reloadGeneration) {
      return;
    }

    roomsResult.when(
      success: (AppPage<RoomProfile> page) {
        final Map<String, String> tenantNames = <String, String>{
          if (snapshot.tenant case final TenantProfile tenant)
            tenant.id: tenant.name,
        };
        List<TenantProfile> tenants = const <TenantProfile>[];
        tenantsResult?.when(
          success: (AppPage<TenantProfile> tenantsPage) {
            tenants = tenantsPage.items;
            for (final TenantProfile tenant in tenantsPage.items) {
              tenantNames[tenant.id] = tenant.name;
            }
          },
          failure: (_) {},
        );

        List<FacilityProfile> facilities = <FacilityProfile>[
          ...snapshot.facilities,
          if (snapshot.facility != null) snapshot.facility!,
        ];
        bool facilitiesReady = !loadFacilities;
        facilitiesResult?.when(
          success: (AppPage<FacilityProfile> facilitiesPage) {
            facilities = facilitiesPage.items;
            facilitiesReady = true;
          },
          failure: (_) {},
        );
        if (scope == TenantFacilityRoomsListScope.facility) {
          final String? facilityId =
              (policy.facilityId ?? snapshot.facility?.id)?.trim();
          facilitiesReady =
              facilityId != null &&
              facilityId.isNotEmpty &&
              !(snapshot.facility?.isDeleted ?? false);
        }
        final Map<String, String> facilityNames = <String, String>{
          for (final FacilityProfile facility in facilities)
            facility.id: facility.name,
        };

        List<WardProfile> wards = const <WardProfile>[];
        wardsResult.when(
          success: (AppPage<WardProfile> wardsPage) {
            wards = wardsPage.items;
          },
          failure: (_) {},
        );
        final Map<String, String> wardNames = <String, String>{
          for (final WardProfile ward in wards) ward.id: ward.name,
        };

        List<RoomProfile> rooms = page.items;
        if (_listStatusFilter == 'deleted') {
          rooms = rooms
              .where((RoomProfile item) => item.isDeleted)
              .toList(growable: false);
        }
        setState(() {
          _loading = false;
          _failure = null;
          _facilitiesReady = facilitiesReady;
          _rooms = rooms;
          _totalItemCount = _listStatusFilter == 'deleted'
              ? rooms.length
              : (page.totalItemCount ?? rooms.length);
          _wards = wards;
          _tenantOptions = tenants;
          _facilityOptions = facilities;
          _tenantNamesById = tenantNames;
          _facilityNamesById = facilityNames;
          _wardNamesById = wardNames;
          _syncWardFilterToOptions();
        });
        widget.onListTotalChanged?.call(_totalItemCount);
      },
      failure: (AppFailure failure) {
        setState(() {
          _loading = false;
          _failure = failure;
          if (!silent) {
            _rooms = const <RoomProfile>[];
            _facilitiesReady = false;
          }
        });
      },
    );
  }

  String _facilityLabel(RoomProfile room) {
    final String facilityId = room.facilityId.trim();
    if (facilityId.isEmpty) {
      return '—';
    }
    final bool isDeleted = _facilityOptions.any(
      (FacilityProfile facility) =>
          facility.id == facilityId && facility.isDeleted,
    );
    return tenantFacilityRelatedNameLabel(
      _facilityNamesById[facilityId],
      isDeleted: isDeleted,
      deletedLabel: context.l10n.tenantFacilityStructureDeletedStatus,
    );
  }

  String _tenantLabel(RoomProfile room) {
    final String tenantId = room.tenantId.trim();
    if (tenantId.isEmpty) {
      return '—';
    }
    final bool isDeleted = _tenantOptions.any(
      (TenantProfile tenant) => tenant.id == tenantId && tenant.isDeleted,
    );
    return tenantFacilityRelatedNameLabel(
      _tenantNamesById[tenantId],
      isDeleted: isDeleted,
      deletedLabel: context.l10n.tenantFacilityStructureDeletedStatus,
    );
  }

  String _wardLabel(RoomProfile room) {
    final String? wardId = room.wardId?.trim();
    if (wardId == null || wardId.isEmpty) {
      return '—';
    }
    final bool isDeleted = _wards.any(
      (WardProfile ward) => ward.id == wardId && ward.isDeleted,
    );
    return tenantFacilityRelatedNameLabel(
      _wardNamesById[wardId] ?? _wardName(snapshot, wardId),
      isDeleted: isDeleted,
      deletedLabel: context.l10n.tenantFacilityStructureDeletedStatus,
    );
  }

  Future<void> _afterMutation(Future<void> Function() action) async {
    await action();
    if (!mounted) {
      return;
    }
    await _reload(silent: true);
  }

  Future<bool> _runBusyRoomAction(
    RoomProfile room,
    Future<bool> Function() action,
  ) async {
    if (mounted) {
      setState(() => _busyRoomId = room.mutationId);
    }
    final bool succeeded = await action();
    if (!succeeded && mounted && _busyRoomId == room.mutationId) {
      setState(() => _busyRoomId = null);
    }
    return succeeded;
  }

  List<AppSearchBarFilterGroup> _buildFilterGroups(AppLocalizations l10n) {
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final TenantFacilityRoomsListScope scope = tenantFacilityRoomsListScope(
      policy,
    );
    final List<FacilityProfile> facilities = _facilitiesForFilter;
    final List<WardProfile> wards = _wardsForFilter;

    return <AppSearchBarFilterGroup>[
      if (tenantFacilityRoomsShowsTenantFilter(scope) &&
          _tenantOptions.isNotEmpty)
        AppSearchBarFilterGroup(
          key: TenantFacilityRoomsFilterKeys.tenant,
          label: l10n.profileTenantLabel,
          allLabel: l10n.commonAllLabel,
          choices: _tenantOptions
              .map(
                (TenantProfile tenant) => AppSearchBarFilterChoice(
                  value: tenant.id,
                  label: tenant.name,
                  icon: Icons.apartment_outlined,
                ),
              )
              .toList(growable: false),
        ),
      if (tenantFacilityRoomsShowsFacilityFilter(scope) &&
          facilities.isNotEmpty)
        AppSearchBarFilterGroup(
          key: TenantFacilityRoomsFilterKeys.facility,
          label: l10n.profileFacilityLabel,
          allLabel: l10n.commonAllLabel,
          choices: facilities
              .map(
                (FacilityProfile facility) => AppSearchBarFilterChoice(
                  value: facility.id,
                  label: facility.name,
                  icon: Icons.local_hospital_outlined,
                ),
              )
              .toList(growable: false),
        ),
      if (wards.isNotEmpty)
        AppSearchBarFilterGroup(
          key: TenantFacilityRoomsFilterKeys.ward,
          label: l10n.tenantFacilityRoomWardLabel,
          allLabel: l10n.commonAllLabel,
          choices: wards
              .map(
                (WardProfile ward) => AppSearchBarFilterChoice(
                  value: ward.id,
                  label: ward.name,
                  icon: Icons.local_hotel_outlined,
                ),
              )
              .toList(growable: false),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppAccessPolicy policy = ref.watch(appAccessPolicyProvider);
    final TenantFacilityRoomsListScope scope = tenantFacilityRoomsListScope(
      policy,
    );
    final bool isSubmitting = ref.watch(
      tenantFacilitySetupSubmissionProvider.select(
        (TenantFacilitySetupSubmissionState state) => state.isSubmitting,
      ),
    );
    final bool canManageRecords = widget.canSubmit;
    final bool hasAccessibleFacilities = switch (scope) {
      TenantFacilityRoomsListScope.facility =>
        (policy.facilityId ?? snapshot.facility?.id)?.trim().isNotEmpty ==
                true &&
            !(snapshot.facility?.isDeleted ?? false),
      TenantFacilityRoomsListScope.tenant ||
      TenantFacilityRoomsListScope.platform =>
        _accessibleFacilities.isNotEmpty,
    };
    // Avoid a false gate when facilities failed to load independently of rooms.
    final bool prerequisitesMet =
        !_facilitiesReady || hasAccessibleFacilities;
    final bool canAdd =
        canManageRecords &&
        prerequisitesMet &&
        !isSubmitting &&
        _busyRoomId == null;
    final String? blockedMessage =
        canManageRecords && _facilitiesReady && !hasAccessibleFacilities
        ? l10n.tenantFacilityGateNeedFacilityForRooms
        : null;
    final bool showTenantColumn = tenantFacilityRoomsShowsTenantColumn(scope);
    final bool showFacilityColumn = tenantFacilityRoomsShowsFacilityColumn(
      scope,
    );

    final List<AppListTableColumn<RoomProfile>> extraColumns =
        <AppListTableColumn<RoomProfile>>[
          AppListTableColumn<RoomProfile>(
            id: 'ward',
            label: l10n.tenantFacilityRoomWardLabel,
            preferredWidth: 160,
            sortComparator: (RoomProfile left, RoomProfile right) =>
                appListTableCompareText(_wardLabel(left), _wardLabel(right)),
            exportValue: (RoomProfile room) => _wardLabel(room),
            cellBuilder: (_, RoomProfile room) =>
                tenantFacilitySetupAtomicCell(_wardLabel(room)),
          ),
        ];
    final List<AppListTableColumn<RoomProfile>> optionalColumns =
        <AppListTableColumn<RoomProfile>>[
          AppListTableColumn<RoomProfile>(
            id: 'floor',
            label: l10n.tenantFacilityRoomFloorLabel,
            preferredWidth: 100,
            sortComparator: (RoomProfile left, RoomProfile right) =>
                appListTableCompareText(left.floor, right.floor),
            exportValue: (RoomProfile room) {
              final String? floor = room.floor?.trim();
              return floor == null || floor.isEmpty ? '—' : floor;
            },
            cellBuilder: (_, RoomProfile room) {
              final String? floor = room.floor?.trim();
              return tenantFacilitySetupAtomicCell(
                floor == null || floor.isEmpty ? '—' : floor,
              );
            },
          ),
          if (showFacilityColumn)
            AppListTableColumn<RoomProfile>(
              id: 'facility',
              label: l10n.profileFacilityLabel,
              preferredWidth: 160,
              sortComparator: (RoomProfile left, RoomProfile right) =>
                  appListTableCompareText(
                    _facilityLabel(left),
                    _facilityLabel(right),
                  ),
              exportValue: (RoomProfile room) => _facilityLabel(room),
              cellBuilder: (_, RoomProfile room) =>
                  tenantFacilitySetupAtomicCell(_facilityLabel(room)),
            ),
          if (showTenantColumn)
            AppListTableColumn<RoomProfile>(
              id: 'tenant',
              label: l10n.profileTenantLabel,
              preferredWidth: 160,
              sortComparator: (RoomProfile left, RoomProfile right) =>
                  appListTableCompareText(
                    _tenantLabel(left),
                    _tenantLabel(right),
                  ),
              exportValue: (RoomProfile room) => _tenantLabel(room),
              cellBuilder: (_, RoomProfile room) =>
                  tenantFacilitySetupAtomicCell(_tenantLabel(room)),
            ),
        ];

    final Widget content = _loading && _rooms.isEmpty
        ? AppLoadingIndicator.compact(
            title: l10n.tenantFacilityRoomsLoadingTitle,
            body: l10n.tenantFacilityRoomsLoadingBody,
          )
        : _failure != null && _rooms.isEmpty
        ? AppWorkspaceStatePanel.error(
            title: l10n.tenantFacilityRoomsLabel,
            body: l10n.failureMessage(_failure!),
            action: AppButton.secondary(
              label: l10n.commonRetryActionLabel,
              leadingIcon: Icons.refresh,
              onPressed: () => unawaited(_reload()),
            ),
          )
        : _SearchableEntityGroup<RoomProfile>(
            title: l10n.tenantFacilityRoomsLabel,
            nameColumnLabel: l10n.tenantFacilityRoomNameLabel,
            nameDetailBuilder: (RoomProfile room) {
              final List<String> details = <String>[];
              final String? roomId = tenantFacilityHumanFriendlyDisplayId(
                room.displayId,
                opaqueId: room.resourceUuid ?? room.id,
              );
              if (roomId != null) {
                details.add(roomId);
              }
              final String? floor = room.floor?.trim();
              if (floor != null && floor.isNotEmpty) {
                details.add(floor);
              }
              if (showFacilityColumn) {
                final String facility = _facilityLabel(room);
                if (facility != '—') {
                  details.add(facility);
                }
              }
              if (showTenantColumn) {
                final String tenant = _tenantLabel(room);
                if (tenant != '—') {
                  details.add(tenant);
                }
              }
              return details;
            },
            items: _rooms,
            serverDrivenList: true,
            onSearchChanged: _onSearchChanged,
            pageRequest: _pageRequest,
            totalItemCount: _totalItemCount,
            onPageChanged: _onPageChanged,
            emptyLabel: l10n.tenantFacilityNoRooms,
            noResultsLabel: l10n.tenantFacilitySearchNoResults,
            searchLabel: l10n.tenantFacilitySearchLabel,
            searchHint: l10n.tenantFacilityRoomSearchHint,
            addLabel: l10n.tenantFacilityAddRoomAction,
            canManageRecords: canManageRecords,
            canAdd: canAdd,
            isSubmitting: isSubmitting,
            busyItemId: _busyRoomId,
            itemIdBuilder: (RoomProfile room) => room.mutationId,
            blockedMessage: blockedMessage,
            onAdd: () => unawaited(
              _afterMutation(
                () => _openRoomDialog(
                  context,
                  snapshot,
                  tenantOptions: _tenantOptions,
                  facilityOptions: _accessibleFacilities,
                  wardOptions: _accessibleWards,
                  tenantNameFor: _tenantLabel,
                  facilityNameFor: _facilityLabel,
                  wardNameFor: _wardLabel,
                ),
              ),
            ),
            onRowSelected: (RoomProfile room) {
              unawaited(
                _afterMutation(
                  () => _openRoomDetails(
                    context,
                    room: room,
                    snapshot: snapshot,
                    tenantName: _tenantLabel(room),
                    facilityName: _facilityLabel(room),
                    wardName: _wardLabel(room),
                  ),
                ),
              );
            },
            columnVisibilityStorageKey:
                'setup_structure_rooms_${scope.name}_v2',
            extraFilterGroups: _buildFilterGroups(l10n),
            onFiltersChanged: (AppSearchBarFilterValue value) {
              unawaited(_onFiltersChanged(value));
            },
            titleBuilder: (RoomProfile room) => room.name,
            subtitleBuilder: (RoomProfile room) {
              final String ward = _wardLabel(room);
              final String? floor = room.floor?.trim();
              final String status = room.isDeleted
                  ? l10n.tenantFacilityStructureDeletedStatus
                  : l10n.tenantFacilityTenantStatusActive;
              return <String>[
                if (ward != '—') ward,
                if (floor != null && floor.isNotEmpty) floor,
                status,
                if (showFacilityColumn) _facilityLabel(room),
                if (showTenantColumn) _tenantLabel(room),
              ].where((String part) => part.trim().isNotEmpty).join(', ');
            },
            statusLabelBuilder: (RoomProfile room) {
              if (room.isDeleted) {
                return l10n.tenantFacilityStructureDeletedStatus;
              }
              return l10n.tenantFacilityTenantStatusActive;
            },
            extraColumns: extraColumns,
            optionalColumns: optionalColumns,
            isDeletedBuilder: (RoomProfile room) => room.isDeleted,
            onEdit: (RoomProfile room) {
              if (room.isDeleted ||
                  isSubmitting ||
                  _busyRoomId != null) {
                return;
              }
              unawaited(() async {
                await _openRoomDialog(
                  context,
                  snapshot,
                  room: room,
                  tenantOptions: _tenantOptions,
                  facilityOptions: _accessibleFacilities,
                  wardOptions: _accessibleWards,
                  tenantNameFor: _tenantLabel,
                  facilityNameFor: _facilityLabel,
                  wardNameFor: _wardLabel,
                );
                if (!mounted) {
                  return;
                }
                setState(() => _busyRoomId = room.mutationId);
                try {
                  await _reload(silent: true);
                } finally {
                  if (mounted && _busyRoomId == room.mutationId) {
                    setState(() => _busyRoomId = null);
                  }
                }
              }());
            },
            onDelete: (RoomProfile room) {
              if (_busyRoomId != null) {
                return;
              }
              unawaited(() async {
                await _deleteEntity(
                  context: context,
                  ref: ref,
                  name: room.name,
                  deleteAction: () => _runBusyRoomAction(
                    room,
                    () => ref
                        .read(tenantFacilitySetupSubmissionProvider.notifier)
                        .deleteRoom(room.mutationId),
                  ),
                );
                if (!mounted) {
                  return;
                }
                try {
                  await _reload(silent: true);
                } finally {
                  if (mounted && _busyRoomId == room.mutationId) {
                    setState(() => _busyRoomId = null);
                  }
                }
              }());
            },
            onRestore: (RoomProfile room) {
              if (_busyRoomId != null) {
                return;
              }
              unawaited(() async {
                await _restoreEntity(
                  context: context,
                  ref: ref,
                  name: room.name,
                  restoreAction: () => _runBusyRoomAction(
                    room,
                    () => ref
                        .read(tenantFacilitySetupSubmissionProvider.notifier)
                        .restoreRoom(room.mutationId),
                  ),
                );
                if (!mounted) {
                  return;
                }
                try {
                  await _reload(silent: true);
                } finally {
                  if (mounted && _busyRoomId == room.mutationId) {
                    setState(() => _busyRoomId = null);
                  }
                }
              }());
            },
          );

    if (widget.framed) {
      return content;
    }

    return _ModalSectionBody(
      body: l10n.tenantFacilityRoomsModalBody,
      blockedMessage: blockedMessage,
      child: content,
    );
  }
}

class _BedSetupSection extends ConsumerStatefulWidget {
  const _BedSetupSection({
    required this.snapshot,
    required this.canSubmit,
    this.framed = true,
    this.onListTotalChanged,
  });

  final FacilitySetupSnapshot snapshot;
  final bool canSubmit;
  final bool framed;
  final ValueChanged<int>? onListTotalChanged;

  @override
  ConsumerState<_BedSetupSection> createState() => _BedSetupSectionState();
}

class _BedSetupSectionState extends ConsumerState<_BedSetupSection> {
  static const AppPageRequest _lookupOptionsRequest = AppPageRequest(
    pageSize: PlatformAdminListConfig.pageSize,
  );

  AppPageRequest _pageRequest = PlatformAdminListConfig.initialPageRequest;
  int _totalItemCount = 0;
  String _searchQuery = '';
  String? _listStatusFilter = 'active';
  Timer? _searchDebounce;

  bool _loading = true;
  AppFailure? _failure;
  List<BedProfile> _beds = const <BedProfile>[];
  List<WardProfile> _wards = const <WardProfile>[];
  List<RoomProfile> _rooms = const <RoomProfile>[];
  List<TenantProfile> _tenantOptions = const <TenantProfile>[];
  List<FacilityProfile> _facilityOptions = const <FacilityProfile>[];
  Map<String, String> _tenantNamesById = const <String, String>{};
  Map<String, String> _facilityNamesById = const <String, String>{};
  Map<String, String> _wardNamesById = const <String, String>{};
  Map<String, String> _roomNamesById = const <String, String>{};
  String? _tenantFilterId;
  String? _facilityFilterId;
  String? _wardFilterId;
  String? _roomFilterId;
  BedSetupStatus? _statusFilter;
  String? _busyBedId;
  int _reloadGeneration = 0;

  FacilitySetupSnapshot get snapshot => widget.snapshot;

  List<WardProfile> get _accessibleWards => _wards
      .where((WardProfile ward) => !ward.isDeleted)
      .toList(growable: false);

  List<RoomProfile> get _accessibleRooms => _rooms
      .where((RoomProfile room) => !room.isDeleted)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(covariant _BedSetupSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String? oldFacilityId = oldWidget.snapshot.facility?.id;
    final String? nextFacilityId = widget.snapshot.facility?.id;
    final String? oldTenantId = oldWidget.snapshot.tenant?.id;
    final String? nextTenantId = widget.snapshot.tenant?.id;
    if (oldFacilityId != nextFacilityId || oldTenantId != nextTenantId) {
      unawaited(_reload());
    }
  }

  List<FacilityProfile> get _facilitiesForFilter {
    final String? tenantFilterId = _tenantFilterId?.trim();
    if (tenantFilterId == null || tenantFilterId.isEmpty) {
      return _facilityOptions
          .where((FacilityProfile facility) => !facility.isDeleted)
          .toList(growable: false);
    }
    return _facilityOptions
        .where(
          (FacilityProfile facility) =>
              !facility.isDeleted && facility.tenantId == tenantFilterId,
        )
        .toList(growable: false);
  }

  List<WardProfile> get _wardsForFilter {
    final String? tenantFilterId = _tenantFilterId?.trim();
    final String? facilityFilterId = _facilityFilterId?.trim();
    return _accessibleWards
        .where((WardProfile ward) {
          if (tenantFilterId != null &&
              tenantFilterId.isNotEmpty &&
              ward.tenantId != tenantFilterId) {
            return false;
          }
          if (facilityFilterId != null &&
              facilityFilterId.isNotEmpty &&
              ward.facilityId != facilityFilterId) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  List<RoomProfile> get _roomsForFilter {
    final String? tenantFilterId = _tenantFilterId?.trim();
    final String? facilityFilterId = _facilityFilterId?.trim();
    final String? wardFilterId = _wardFilterId?.trim();
    return _accessibleRooms
        .where((RoomProfile room) {
          if (tenantFilterId != null &&
              tenantFilterId.isNotEmpty &&
              room.tenantId != tenantFilterId) {
            return false;
          }
          if (facilityFilterId != null &&
              facilityFilterId.isNotEmpty &&
              room.facilityId != facilityFilterId) {
            return false;
          }
          if (wardFilterId != null &&
              wardFilterId.isNotEmpty &&
              (room.wardId?.trim() ?? '') != wardFilterId) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  void _applyServerFilters(AppSearchBarFilterValue value) {
    final String? nextTenant = value.option(
      TenantFacilityBedsFilterKeys.tenant,
    );
    final String? nextFacility = value.option(
      TenantFacilityBedsFilterKeys.facility,
    );
    final String? nextWard = value.option(TenantFacilityBedsFilterKeys.ward);
    final String? nextRoom = value.option(TenantFacilityBedsFilterKeys.room);
    final String? nextStatus = value.option(
      TenantFacilityBedsFilterKeys.status,
    );

    BedSetupStatus? parsedStatus;
    if (nextStatus != null) {
      parsedStatus = BedSetupStatusX.fromApiValue(nextStatus);
    }

    _tenantFilterId = nextTenant;
    _facilityFilterId = nextFacility;
    _wardFilterId = nextWard;
    _roomFilterId = nextRoom;
    _statusFilter = parsedStatus;
    _syncFacilityFilterToOptions();
    _syncWardFilterToOptions();
    _syncRoomFilterToOptions();
  }

  void _syncFacilityFilterToOptions() {
    final String? facilityId = _facilityFilterId;
    if (facilityId == null) {
      return;
    }
    final String? tenantFilterId = _tenantFilterId?.trim();
    final bool facilityAllowed = _facilityOptions.any((FacilityProfile facility) {
      if (facility.id != facilityId || facility.isDeleted) {
        return false;
      }
      if (tenantFilterId == null || tenantFilterId.isEmpty) {
        return true;
      }
      return facility.tenantId == tenantFilterId;
    });
    if (!facilityAllowed) {
      _facilityFilterId = null;
    }
  }

  void _syncWardFilterToOptions() {
    final String? wardId = _wardFilterId;
    if (wardId == null) {
      return;
    }
    final bool wardAllowed = _wardsForFilter.any(
      (WardProfile ward) => ward.id == wardId,
    );
    if (!wardAllowed) {
      _wardFilterId = null;
    }
  }

  void _syncRoomFilterToOptions() {
    final String? roomId = _roomFilterId;
    if (roomId == null) {
      return;
    }
    final bool roomAllowed = _roomsForFilter.any(
      (RoomProfile room) => room.id == roomId,
    );
    if (!roomAllowed) {
      _roomFilterId = null;
    }
  }

  Future<void> _onFiltersChanged(AppSearchBarFilterValue value) async {
    final String? previousTenant = _tenantFilterId;
    final String? previousFacility = _facilityFilterId;
    final String? previousWard = _wardFilterId;
    _applyServerFilters(value);
    _listStatusFilter = value.option('status');
    _pageRequest = _pageRequest.first();
    final bool tenantChanged = previousTenant != _tenantFilterId;
    final bool facilityChanged = previousFacility != _facilityFilterId;
    final bool wardChanged = previousWard != _wardFilterId;
    if (tenantChanged) {
      await _reloadFacilityOptions();
      _syncFacilityFilterToOptions();
    }
    if (tenantChanged || facilityChanged) {
      _syncWardFilterToOptions();
    }
    if (tenantChanged || facilityChanged || wardChanged) {
      _syncRoomFilterToOptions();
    }
    await _reload(silent: true);
  }


  void _onSearchChanged(String raw) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      final String next = raw.trim();
      if (next == _searchQuery) {
        return;
      }
      _searchQuery = next;
      _pageRequest = _pageRequest.first();
      unawaited(_reload(silent: true));
    });
  }

  Future<void> _onPageChanged(AppPageRequest request) async {
    _pageRequest = request;
    await _reload(silent: true);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _reloadFacilityOptions() async {
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final TenantFacilityBedsListScope scope = tenantFacilityBedsListScope(
      policy,
    );
    if (!tenantFacilityBedsShowsFacilityFilter(scope)) {
      return;
    }

    final String? tenantId = switch (scope) {
      TenantFacilityBedsListScope.platform => _tenantFilterId,
      TenantFacilityBedsListScope.tenant ||
      TenantFacilityBedsListScope.facility =>
        policy.tenantId ?? snapshot.tenant?.id,
    };

    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );
    final Result<AppPage<FacilityProfile>> result = await repository
        .listFacilities(request: _lookupOptionsRequest, tenantId: tenantId);
    if (!mounted) {
      return;
    }
    result.when(
      success: (AppPage<FacilityProfile> page) {
        setState(() {
          _facilityOptions = page.items;
          _facilityNamesById = <String, String>{
            for (final FacilityProfile facility in page.items)
              facility.id: facility.name,
          };
          if (_facilityFilterId != null &&
              !_facilitiesForFilter.any(
                (FacilityProfile facility) => facility.id == _facilityFilterId,
              )) {
            _facilityFilterId = null;
          }
        });
      },
      failure: (_) {},
    );
  }

  Future<void> _reload({bool silent = false}) async {
    final int generation = ++_reloadGeneration;
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final TenantFacilityBedsListScope scope = tenantFacilityBedsListScope(
      policy,
    );
    final String? scopedTenantId = switch (scope) {
      TenantFacilityBedsListScope.platform => _tenantFilterId,
      TenantFacilityBedsListScope.tenant ||
      TenantFacilityBedsListScope.facility =>
        policy.tenantId ?? snapshot.tenant?.id,
    };
    final String? scopedFacilityId =
        scope == TenantFacilityBedsListScope.facility
        ? (policy.facilityId ?? snapshot.facility?.id)
        : _facilityFilterId;

    if (!silent) {
      setState(() {
        _loading = _beds.isEmpty;
        _failure = null;
      });
    }

    if (scope == TenantFacilityBedsListScope.facility &&
        (scopedFacilityId == null || scopedFacilityId.trim().isEmpty)) {
      if (!mounted || generation != _reloadGeneration) {
        return;
      }
      setState(() {
        _loading = false;
        _beds = const <BedProfile>[];
        _wards = const <WardProfile>[];
        _rooms = const <RoomProfile>[];
        _facilityOptions = const <FacilityProfile>[];
        _tenantOptions = const <TenantProfile>[];
        _tenantNamesById = const <String, String>{};
        _facilityNamesById = const <String, String>{};
        _wardNamesById = const <String, String>{};
        _roomNamesById = const <String, String>{};
      });
      return;
    }

    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );

    final Future<Result<AppPage<TenantProfile>>>? tenantsFuture =
        tenantFacilityBedsShowsTenantFilter(scope)
        ? repository.listTenants(
            request: _lookupOptionsRequest,
          )
        : null;
    final Future<Result<AppPage<FacilityProfile>>>? facilitiesFuture =
        tenantFacilityBedsShowsFacilityFilter(scope)
        ? repository.listFacilities(
            request: _lookupOptionsRequest,
            tenantId: scope == TenantFacilityBedsListScope.platform
                ? _tenantFilterId
                : scopedTenantId,
            includeDeleted: true,
          )
        : null;
    final Future<Result<AppPage<WardProfile>>> wardsFuture = repository
        .listWards(
          request: _lookupOptionsRequest,
          tenantId: scopedTenantId,
          facilityId: scopedFacilityId,
          includeDeleted: true,
        );
    final Future<Result<AppPage<RoomProfile>>> roomsFuture = repository
        .listRooms(
          request: _lookupOptionsRequest,
          tenantId: scopedTenantId,
          facilityId: scopedFacilityId,
          includeDeleted: true,
        );
    final bool includeDeleted = _listStatusFilter != 'active';
    final Future<Result<AppPage<BedProfile>>> bedsFuture = repository.listBeds(
      request: _pageRequest,
      tenantId: scopedTenantId,
      facilityId: scopedFacilityId,
      wardId: _wardFilterId,
      roomId: _roomFilterId,
      search: _searchQuery.isEmpty ? null : _searchQuery,
      status: _statusFilter,
      includeDeleted: includeDeleted,
    );

    final Result<AppPage<TenantProfile>>? tenantsResult = tenantsFuture == null
        ? null
        : await tenantsFuture;
    final Result<AppPage<FacilityProfile>>? facilitiesResult =
        facilitiesFuture == null ? null : await facilitiesFuture;
    final Result<AppPage<WardProfile>> wardsResult = await wardsFuture;
    final Result<AppPage<RoomProfile>> roomsResult = await roomsFuture;
    final Result<AppPage<BedProfile>> bedsResult = await bedsFuture;

    if (!mounted || generation != _reloadGeneration) {
      return;
    }

    bedsResult.when(
      success: (AppPage<BedProfile> page) {
        final Map<String, String> tenantNames = <String, String>{
          if (snapshot.tenant case final TenantProfile tenant)
            tenant.id: tenant.name,
        };
        List<TenantProfile> tenants = const <TenantProfile>[];
        tenantsResult?.when(
          success: (AppPage<TenantProfile> tenantsPage) {
            tenants = tenantsPage.items;
            for (final TenantProfile tenant in tenantsPage.items) {
              tenantNames[tenant.id] = tenant.name;
            }
          },
          failure: (_) {},
        );

        List<FacilityProfile> facilities = <FacilityProfile>[
          ...snapshot.facilities,
          if (snapshot.facility != null) snapshot.facility!,
        ];
        facilitiesResult?.when(
          success: (AppPage<FacilityProfile> facilitiesPage) {
            facilities = facilitiesPage.items;
          },
          failure: (_) {},
        );
        final Map<String, String> facilityNames = <String, String>{
          for (final FacilityProfile facility in facilities)
            facility.id: facility.name,
        };

        List<WardProfile> wards = const <WardProfile>[];
        wardsResult.when(
          success: (AppPage<WardProfile> wardsPage) {
            wards = wardsPage.items;
          },
          failure: (_) {},
        );
        final Map<String, String> wardNames = <String, String>{
          for (final WardProfile ward in wards) ward.id: ward.name,
        };

        List<RoomProfile> rooms = const <RoomProfile>[];
        roomsResult.when(
          success: (AppPage<RoomProfile> roomsPage) {
            rooms = roomsPage.items;
          },
          failure: (_) {},
        );
        final Map<String, String> roomNames = <String, String>{
          for (final RoomProfile room in rooms) room.id: room.name,
        };

        List<BedProfile> beds = page.items;
        if (_listStatusFilter == 'deleted') {
          beds = beds
              .where((BedProfile item) => item.isDeleted)
              .toList(growable: false);
        }
        setState(() {
          _loading = false;
          _failure = null;
          _beds = beds;
          _totalItemCount = _listStatusFilter == 'deleted'
              ? beds.length
              : (page.totalItemCount ?? beds.length);
          _wards = wards;
          _rooms = rooms;
          _tenantOptions = tenants;
          _facilityOptions = facilities;
          _tenantNamesById = tenantNames;
          _facilityNamesById = facilityNames;
          _wardNamesById = wardNames;
          _roomNamesById = roomNames;
          _syncWardFilterToOptions();
          _syncRoomFilterToOptions();
        });
        widget.onListTotalChanged?.call(_totalItemCount);
      },
      failure: (AppFailure failure) {
        setState(() {
          _loading = false;
          _failure = failure;
          if (!silent) {
            _beds = const <BedProfile>[];
          }
        });
      },
    );
  }

  String _facilityLabel(BedProfile bed) {
    final String facilityId = bed.facilityId.trim();
    if (facilityId.isEmpty) {
      return '—';
    }
    final bool isDeleted = _facilityOptions.any(
      (FacilityProfile facility) =>
          facility.id == facilityId && facility.isDeleted,
    );
    return tenantFacilityRelatedNameLabel(
      _facilityNamesById[facilityId],
      isDeleted: isDeleted,
      deletedLabel: context.l10n.tenantFacilityStructureDeletedStatus,
    );
  }

  String _tenantLabel(BedProfile bed) {
    final String tenantId = bed.tenantId.trim();
    if (tenantId.isEmpty) {
      return '—';
    }
    final bool isDeleted = _tenantOptions.any(
      (TenantProfile tenant) => tenant.id == tenantId && tenant.isDeleted,
    );
    return tenantFacilityRelatedNameLabel(
      _tenantNamesById[tenantId],
      isDeleted: isDeleted,
      deletedLabel: context.l10n.tenantFacilityStructureDeletedStatus,
    );
  }

  String _wardLabel(BedProfile bed) {
    final String wardId = bed.wardId.trim();
    if (wardId.isEmpty) {
      return '—';
    }
    final bool isDeleted = _wards.any(
      (WardProfile ward) => ward.id == wardId && ward.isDeleted,
    );
    return tenantFacilityRelatedNameLabel(
      _wardNamesById[wardId] ?? _wardName(snapshot, wardId),
      isDeleted: isDeleted,
      deletedLabel: context.l10n.tenantFacilityStructureDeletedStatus,
    );
  }

  String _roomLabel(BedProfile bed) {
    final String? roomId = bed.roomId?.trim();
    if (roomId == null || roomId.isEmpty) {
      return '—';
    }
    final bool isDeleted = _rooms.any(
      (RoomProfile room) => room.id == roomId && room.isDeleted,
    );
    return tenantFacilityRelatedNameLabel(
      _roomNamesById[roomId] ?? _roomName(snapshot, roomId),
      isDeleted: isDeleted,
      deletedLabel: context.l10n.tenantFacilityStructureDeletedStatus,
    );
  }

  Future<void> _afterMutation(Future<void> Function() action) async {
    await action();
    if (!mounted) {
      return;
    }
    await _reload(silent: true);
  }

  Future<bool> _runBusyBedAction(
    BedProfile bed,
    Future<bool> Function() action,
  ) async {
    if (mounted) {
      setState(() => _busyBedId = bed.id);
    }
    final bool succeeded = await action();
    if (!succeeded && mounted && _busyBedId == bed.id) {
      setState(() => _busyBedId = null);
    }
    return succeeded;
  }

  List<AppSearchBarFilterGroup> _buildFilterGroups(AppLocalizations l10n) {
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final TenantFacilityBedsListScope scope = tenantFacilityBedsListScope(
      policy,
    );
    final List<FacilityProfile> facilities = _facilitiesForFilter;
    final List<WardProfile> wards = _wardsForFilter;
    final List<RoomProfile> rooms = _roomsForFilter;

    return <AppSearchBarFilterGroup>[
      if (tenantFacilityBedsShowsTenantFilter(scope) &&
          _tenantOptions.isNotEmpty)
        AppSearchBarFilterGroup(
          key: TenantFacilityBedsFilterKeys.tenant,
          label: l10n.profileTenantLabel,
          allLabel: l10n.commonAllLabel,
          choices: _tenantOptions
              .map(
                (TenantProfile tenant) => AppSearchBarFilterChoice(
                  value: tenant.id,
                  label: tenant.name,
                  icon: Icons.apartment_outlined,
                ),
              )
              .toList(growable: false),
        ),
      if (tenantFacilityBedsShowsFacilityFilter(scope) &&
          facilities.isNotEmpty)
        AppSearchBarFilterGroup(
          key: TenantFacilityBedsFilterKeys.facility,
          label: l10n.profileFacilityLabel,
          allLabel: l10n.commonAllLabel,
          choices: facilities
              .map(
                (FacilityProfile facility) => AppSearchBarFilterChoice(
                  value: facility.id,
                  label: facility.name,
                  icon: Icons.local_hospital_outlined,
                ),
              )
              .toList(growable: false),
        ),
      if (wards.isNotEmpty)
        AppSearchBarFilterGroup(
          key: TenantFacilityBedsFilterKeys.ward,
          label: l10n.tenantFacilityBedWardLabel,
          allLabel: l10n.commonAllLabel,
          choices: wards
              .map(
                (WardProfile ward) => AppSearchBarFilterChoice(
                  value: ward.id,
                  label: ward.name,
                  icon: Icons.local_hospital_outlined,
                ),
              )
              .toList(growable: false),
        ),
      if (rooms.isNotEmpty)
        AppSearchBarFilterGroup(
          key: TenantFacilityBedsFilterKeys.room,
          label: l10n.tenantFacilityBedRoomLabel,
          allLabel: l10n.commonAllLabel,
          choices: rooms
              .map(
                (RoomProfile room) => AppSearchBarFilterChoice(
                  value: room.id,
                  label: room.name,
                  icon: Icons.meeting_room_outlined,
                ),
              )
              .toList(growable: false),
        ),
      AppSearchBarFilterGroup(
        key: TenantFacilityBedsFilterKeys.status,
        label: l10n.tenantFacilityBedStatusLabel,
        allLabel: l10n.commonAllLabel,
        choices: BedSetupStatus.values
            .map(
              (BedSetupStatus status) => AppSearchBarFilterChoice(
                value: status.apiValue,
                label: tenantFacilityBedStatusLabel(l10n, status),
                icon: Icons.bed_outlined,
              ),
            )
            .toList(growable: false),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppAccessPolicy policy = ref.watch(appAccessPolicyProvider);
    final TenantFacilityBedsListScope scope = tenantFacilityBedsListScope(
      policy,
    );
    final bool isSubmitting = ref.watch(
      tenantFacilitySetupSubmissionProvider.select(
        (TenantFacilitySetupSubmissionState state) => state.isSubmitting,
      ),
    );
    final bool canManageRecords = widget.canSubmit;
    final bool prerequisitesMet = _accessibleWards.isNotEmpty;
    final bool canAdd =
        canManageRecords &&
        prerequisitesMet &&
        !isSubmitting &&
        _busyBedId == null;
    final String? blockedMessage = canManageRecords && !prerequisitesMet
        ? l10n.tenantFacilityGateNeedWardsForBeds
        : null;
    final bool showTenantColumn = tenantFacilityBedsShowsTenantColumn(scope);
    final bool showFacilityColumn = tenantFacilityBedsShowsFacilityColumn(
      scope,
    );

    final List<AppListTableColumn<BedProfile>> extraColumns =
        <AppListTableColumn<BedProfile>>[
          AppListTableColumn<BedProfile>(
            id: 'ward',
            label: l10n.tenantFacilityBedWardLabel,
            preferredWidth: 160,
            sortComparator: (BedProfile left, BedProfile right) =>
                appListTableCompareText(_wardLabel(left), _wardLabel(right)),
            exportValue: (BedProfile bed) => _wardLabel(bed),
            cellBuilder: (_, BedProfile bed) =>
                tenantFacilitySetupAtomicCell(_wardLabel(bed)),
          ),
        ];
    final List<AppListTableColumn<BedProfile>> optionalColumns =
        <AppListTableColumn<BedProfile>>[
          AppListTableColumn<BedProfile>(
            id: 'room',
            label: l10n.tenantFacilityRoomNameLabel,
            preferredWidth: 160,
            sortComparator: (BedProfile left, BedProfile right) =>
                appListTableCompareText(_roomLabel(left), _roomLabel(right)),
            exportValue: (BedProfile bed) => _roomLabel(bed),
            cellBuilder: (_, BedProfile bed) =>
                tenantFacilitySetupAtomicCell(_roomLabel(bed)),
          ),
          if (showFacilityColumn)
            AppListTableColumn<BedProfile>(
              id: 'facility',
              label: l10n.profileFacilityLabel,
              preferredWidth: 160,
              sortComparator: (BedProfile left, BedProfile right) =>
                  appListTableCompareText(
                    _facilityLabel(left),
                    _facilityLabel(right),
                  ),
              exportValue: (BedProfile bed) => _facilityLabel(bed),
              cellBuilder: (_, BedProfile bed) =>
                  tenantFacilitySetupAtomicCell(_facilityLabel(bed)),
            ),
          if (showTenantColumn)
            AppListTableColumn<BedProfile>(
              id: 'tenant',
              label: l10n.profileTenantLabel,
              preferredWidth: 160,
              sortComparator: (BedProfile left, BedProfile right) =>
                  appListTableCompareText(
                    _tenantLabel(left),
                    _tenantLabel(right),
                  ),
              exportValue: (BedProfile bed) => _tenantLabel(bed),
              cellBuilder: (_, BedProfile bed) =>
                  tenantFacilitySetupAtomicCell(_tenantLabel(bed)),
            ),
        ];

    final Widget content = _loading && _beds.isEmpty
        ? AppLoadingIndicator.compact(
            title: l10n.tenantFacilityBedsLoadingTitle,
            body: l10n.tenantFacilityBedsLoadingBody,
          )
        : _failure != null && _beds.isEmpty
        ? Center(
            child: Text(
              l10n.failureMessage(_failure!),
              textAlign: TextAlign.center,
            ),
          )
        : _SearchableEntityGroup<BedProfile>(
            title: l10n.tenantFacilityBedsLabel,
            nameColumnLabel: l10n.tenantFacilityBedLabelLabel,
            nameDetailBuilder: (BedProfile bed) {
              final List<String> details = <String>[];
              final String? bedId = tenantFacilityHumanFriendlyDisplayId(
                bed.displayId,
                opaqueId: bed.id,
              );
              if (bedId != null) {
                details.add(bedId);
              }
              final String room = _roomLabel(bed);
              if (room != '—') {
                details.add(room);
              }
              if (showFacilityColumn) {
                final String facility = _facilityLabel(bed);
                if (facility != '—') {
                  details.add(facility);
                }
              }
              if (showTenantColumn) {
                final String tenant = _tenantLabel(bed);
                if (tenant != '—') {
                  details.add(tenant);
                }
              }
              return details;
            },
            items: _beds,
            serverDrivenList: true,
            onSearchChanged: _onSearchChanged,
            pageRequest: _pageRequest,
            totalItemCount: _totalItemCount,
            onPageChanged: _onPageChanged,
            emptyLabel: l10n.tenantFacilityNoBeds,
            noResultsLabel: l10n.tenantFacilitySearchNoResults,
            searchLabel: l10n.tenantFacilitySearchLabel,
            searchHint: l10n.tenantFacilityBedSearchHint,
            addLabel: l10n.tenantFacilityAddBedAction,
            canManageRecords: canManageRecords,
            canAdd: canAdd,
            isSubmitting: isSubmitting,
            busyItemId: _busyBedId,
            itemIdBuilder: (BedProfile bed) => bed.id,
            blockedMessage: blockedMessage,
            onAdd: () => unawaited(
              _afterMutation(
                () => _openBedDialog(
                  context,
                  snapshot,
                  tenantOptions: _tenantOptions,
                  facilityOptions: _facilityOptions
                      .where((FacilityProfile facility) => !facility.isDeleted)
                      .toList(growable: false),
                  wardOptions: _accessibleWards,
                  roomOptions: _accessibleRooms,
                  tenantNameFor: _tenantLabel,
                  facilityNameFor: _facilityLabel,
                  wardNameFor: _wardLabel,
                  roomNameFor: _roomLabel,
                ),
              ),
            ),
            onRowSelected: (BedProfile bed) {
              unawaited(
                _afterMutation(
                  () => _openBedDetails(
                    context,
                    bed: bed,
                    snapshot: snapshot,
                    tenantName: _tenantLabel(bed),
                    facilityName: _facilityLabel(bed),
                    wardName: _wardLabel(bed),
                    roomName: _roomLabel(bed),
                  ),
                ),
              );
            },
            columnVisibilityStorageKey: 'setup_structure_beds_${scope.name}_v2',
            extraFilterGroups: _buildFilterGroups(l10n),
            onFiltersChanged: (AppSearchBarFilterValue value) {
              unawaited(_onFiltersChanged(value));
            },
            titleBuilder: (BedProfile bed) => bed.label,
            subtitleBuilder: (BedProfile bed) {
              if (bed.isDeleted) {
                return l10n.tenantFacilityStructureDeletedStatus;
              }
              return <String>[
                _wardLabel(bed),
                if (_roomLabel(bed) != '—') _roomLabel(bed),
                tenantFacilityBedStatusLabel(l10n, bed.status),
                if (showFacilityColumn) _facilityLabel(bed),
                if (showTenantColumn) _tenantLabel(bed),
              ].where((String part) => part.trim().isNotEmpty).join(', ');
            },
            statusLabelBuilder: (BedProfile bed) {
              if (bed.isDeleted) {
                return l10n.tenantFacilityStructureDeletedStatus;
              }
              return tenantFacilityBedStatusLabel(l10n, bed.status);
            },
            extraColumns: extraColumns,
            optionalColumns: optionalColumns,
            isDeletedBuilder: (BedProfile bed) => bed.isDeleted,
            onEdit: (BedProfile bed) {
              if (bed.isDeleted || isSubmitting || _busyBedId != null) {
                return;
              }
              unawaited(() async {
                await _openBedDialog(
                  context,
                  snapshot,
                  bed: bed,
                  tenantOptions: _tenantOptions,
                  facilityOptions: _facilityOptions
                      .where((FacilityProfile facility) => !facility.isDeleted)
                      .toList(growable: false),
                  wardOptions: _accessibleWards,
                  roomOptions: _accessibleRooms,
                  tenantNameFor: _tenantLabel,
                  facilityNameFor: _facilityLabel,
                  wardNameFor: _wardLabel,
                  roomNameFor: _roomLabel,
                );
                if (!mounted) {
                  return;
                }
                setState(() => _busyBedId = bed.id);
                try {
                  await _reload(silent: true);
                } finally {
                  if (mounted && _busyBedId == bed.id) {
                    setState(() => _busyBedId = null);
                  }
                }
              }());
            },
            onDelete: (BedProfile bed) {
              if (_busyBedId != null) {
                return;
              }
              unawaited(() async {
                await _deleteEntity(
                  context: context,
                  ref: ref,
                  name: bed.label,
                  deleteAction: () => _runBusyBedAction(
                    bed,
                    () => ref
                        .read(tenantFacilitySetupSubmissionProvider.notifier)
                        .deleteBed(bed.id),
                  ),
                );
                if (!mounted) {
                  return;
                }
                try {
                  await _reload(silent: true);
                } finally {
                  if (mounted && _busyBedId == bed.id) {
                    setState(() => _busyBedId = null);
                  }
                }
              }());
            },
            onRestore: (BedProfile bed) {
              if (_busyBedId != null) {
                return;
              }
              unawaited(() async {
                await _restoreEntity(
                  context: context,
                  ref: ref,
                  name: bed.label,
                  restoreAction: () => _runBusyBedAction(
                    bed,
                    () => ref
                        .read(tenantFacilitySetupSubmissionProvider.notifier)
                        .restoreBed(bed.id),
                  ),
                );
                if (!mounted) {
                  return;
                }
                try {
                  await _reload(silent: true);
                } finally {
                  if (mounted && _busyBedId == bed.id) {
                    setState(() => _busyBedId = null);
                  }
                }
              }());
            },
          );

    if (widget.framed) {
      return content;
    }

    return _ModalSectionBody(
      body: l10n.tenantFacilityBedsModalBody,
      blockedMessage: blockedMessage,
      child: content,
    );
  }
}

class _ModalSectionBody extends StatelessWidget {
  const _ModalSectionBody({
    required this.body,
    required this.child,
    this.blockedMessage,
  });

  final String body;
  final Widget child;
  final String? blockedMessage;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          body,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (blockedMessage != null) ...<Widget>[
          SizedBox(height: theme.spacing.sm),
          Text(
            blockedMessage!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        SizedBox(height: theme.spacing.lg),
        child,
      ],
    );
  }
}

class _SearchableEntityGroupScopeOption {
  const _SearchableEntityGroupScopeOption({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}

class _SearchableEntityGroup<T> extends ConsumerStatefulWidget {
  const _SearchableEntityGroup({
    required this.title,
    required this.items,
    required this.emptyLabel,
    required this.noResultsLabel,
    required this.searchLabel,
    required this.searchHint,
    required this.addLabel,
    required this.canManageRecords,
    required this.canAdd,
    required this.onAdd,
    required this.titleBuilder,
    required this.subtitleBuilder,
    required this.isDeletedBuilder,
    required this.onEdit,
    required this.onDelete,
    required this.onRestore,
    this.onPermanentDelete,
    this.onRowSelected,
    this.isSubmitting = false,
    this.busyItemId,
    this.itemIdBuilder,
    this.scopeLabel,
    this.scopeOptions = const <_SearchableEntityGroupScopeOption>[],
    this.itemScopeId,
    this.addIcon = Icons.add_circle_outline,
    this.blockedMessage,
    this.leadingColumns,
    this.extraColumns,
    this.optionalColumns,
    this.extraFilterGroups = const <AppSearchBarFilterGroup>[],
    this.onFiltersChanged,
    this.columnVisibilityStorageKey,
    this.statusLabelBuilder,
    this.nameColumnLabel,
    this.nameDetailBuilder,
    this.serverDrivenList = false,
    this.onSearchChanged,
    this.pageRequest,
    this.totalItemCount,
    this.onPageChanged,
  });

  final String title;
  final List<T> items;
  final String emptyLabel;
  final String noResultsLabel;
  final String searchLabel;
  final String searchHint;
  final String addLabel;
  final IconData addIcon;
  final bool canManageRecords;
  final bool canAdd;
  final bool isSubmitting;
  final String? busyItemId;
  final String Function(T item)? itemIdBuilder;
  final VoidCallback onAdd;
  final String Function(T item) titleBuilder;
  final String Function(T item) subtitleBuilder;
  final bool Function(T item) isDeletedBuilder;
  final ValueChanged<T> onEdit;
  final ValueChanged<T> onDelete;
  final ValueChanged<T> onRestore;
  final ValueChanged<T>? onPermanentDelete;
  final ValueChanged<T>? onRowSelected;
  final String? scopeLabel;
  final List<_SearchableEntityGroupScopeOption> scopeOptions;
  final String? Function(T item)? itemScopeId;
  final String? blockedMessage;
  final List<AppListTableColumn<T>>? leadingColumns;
  final List<AppListTableColumn<T>>? extraColumns;
  /// Available via column visibility but hidden by default.
  final List<AppListTableColumn<T>>? optionalColumns;
  final List<AppSearchBarFilterGroup> extraFilterGroups;
  final ValueChanged<AppSearchBarFilterValue>? onFiltersChanged;
  final String? columnVisibilityStorageKey;
  final String Function(T item)? statusLabelBuilder;
  final String? nameColumnLabel;
  final List<String> Function(T item)? nameDetailBuilder;
  final bool serverDrivenList;
  final ValueChanged<String>? onSearchChanged;
  final AppPageRequest? pageRequest;
  final int? totalItemCount;
  final Future<void> Function(AppPageRequest request)? onPageChanged;

  @override
  ConsumerState<_SearchableEntityGroup<T>> createState() =>
      _SearchableEntityGroupState<T>();
}

class _SearchableEntityGroupState<T>
    extends ConsumerState<_SearchableEntityGroup<T>> {
  static const String _statusFilterKey = 'status';
  static const String _scopeFilterKey = 'scope';
  static const String _statusActive = 'active';
  static const String _statusDeleted = 'deleted';
  static const String _allScopes = '__all_scopes__';

  final TextEditingController _searchController = TextEditingController();
  late AppSearchBarFilterValue _filterValue;
  String _scopeId = _allScopes;

  bool get _hasScopeSelector =>
      widget.scopeLabel != null &&
      widget.scopeOptions.isNotEmpty &&
      widget.itemScopeId != null;

  @override
  void initState() {
    super.initState();
    _filterValue = widget.serverDrivenList
        ? const AppSearchBarFilterValue(
            options: <String, String>{_statusFilterKey: _statusActive},
          )
        : AppSearchBarFilterValue.empty;
    if (widget.serverDrivenList && widget.onSearchChanged != null) {
      _searchController.addListener(_handleSearchTextChanged);
    }
  }

  void _handleSearchTextChanged() {
    widget.onSearchChanged?.call(_searchController.text);
  }

  @override
  void dispose() {
    if (widget.serverDrivenList && widget.onSearchChanged != null) {
      _searchController.removeListener(_handleSearchTextChanged);
    }
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SearchableEntityGroup<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_scopeId == _allScopes) {
      return;
    }
    final bool scopeStillValid = widget.scopeOptions.any(
      (_SearchableEntityGroupScopeOption option) => option.id == _scopeId,
    );
    if (!scopeStillValid) {
      setState(() => _scopeId = _allScopes);
    }
  }

  List<T> get _visibleItems {
    final String? status = _filterValue.options[_statusFilterKey];
    Iterable<T> items = widget.items;
    if (!widget.serverDrivenList) {
      if (status == _statusActive) {
        items = items.where((T item) => !widget.isDeletedBuilder(item));
      } else if (status == _statusDeleted) {
        items = items.where(widget.isDeletedBuilder);
      }
    }
    final String? Function(T item)? itemScopeId = widget.itemScopeId;
    if (_hasScopeSelector && _scopeId != _allScopes && itemScopeId != null) {
      items = items.where((T item) => itemScopeId(item) == _scopeId);
    }
    return items.toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = context.l10n;
    final List<T> items = _visibleItems;
    final bool hasNonDefaultStatus =
        _filterValue.options[_statusFilterKey] != null &&
        !(widget.serverDrivenList &&
            _filterValue.options[_statusFilterKey] == _statusActive);
    final bool hasActiveFilters =
        hasNonDefaultStatus ||
        _filterValue.options.keys.any(
          (String key) => key != _statusFilterKey,
        ) ||
        (_hasScopeSelector && _scopeId != _allScopes);

    final double actionGap = theme.spacing.xs;
    final AppListTableColumn<T> nameColumn = AppListTableColumn<T>(
      id: 'name',
      label: widget.nameColumnLabel ?? widget.title,
      preferredWidth: 220,
      sortComparator: (T left, T right) => appListTableCompareText(
        widget.titleBuilder(left),
        widget.titleBuilder(right),
      ),
      exportValue: (T item) => widget.titleBuilder(item),
      cellBuilder: (BuildContext context, T item) {
        return tenantFacilitySetupAtomicCell(
          widget.titleBuilder(item),
          muted: widget.isDeletedBuilder(item),
        );
      },
    );
    final String Function(T item) statusLabel =
        widget.statusLabelBuilder ?? widget.subtitleBuilder;
    final AppListTableColumn<T> statusColumn = AppListTableColumn<T>(
      id: 'status',
      label: l10n.tenantFacilityTenantStatusLabel,
      preferredWidth: 120,
      sortComparator: (T left, T right) =>
          appListTableCompareText(statusLabel(left), statusLabel(right)),
      exportValue: (T item) => statusLabel(item),
      cellBuilder: (_, T item) => tenantFacilitySetupAtomicCell(statusLabel(item)),
    );
    final List<AppListTableColumn<T>> leadingColumns =
        widget.leadingColumns ?? <AppListTableColumn<T>>[];
    final List<AppListTableColumn<T>> extraColumns =
        widget.extraColumns ?? <AppListTableColumn<T>>[];
    final bool rowScopedBusy = widget.itemIdBuilder != null;
    final bool searchLoading = !rowScopedBusy && widget.isSubmitting;
    final AppListTableColumn<T>? actionsColumn = widget.canManageRecords
        ? AppListTableColumn<T>(
            id: 'actions',
            label: l10n.accessAdminColumnActions,
            alwaysVisible: true,
            exportable: false,
            preferredWidth: widget.onPermanentDelete != null ? 280 : 168,
            cellBuilder: (BuildContext context, T item) {
              final bool deleted = widget.isDeletedBuilder(item);
              final String? itemId = widget.itemIdBuilder?.call(item);
              final bool itemBusy =
                  rowScopedBusy &&
                  widget.busyItemId != null &&
                  itemId == widget.busyItemId;
              final bool actionsEnabled = rowScopedBusy
                  ? widget.busyItemId == null
                  : !widget.isSubmitting;
              if (itemBusy) {
                return const Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AppLoadingIndicator.compact(expand: false),
                );
              }
              return Wrap(
                spacing: actionGap,
                runSpacing: theme.spacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  if (deleted) ...<Widget>[
                    AppButton.tertiary(
                      leadingIcon: Icons.restore_outlined,
                      label: l10n.tenantFacilityRestoreStructureAction,
                      semanticLabel: l10n.tenantFacilityRestoreStructureAction,
                      tooltip: l10n.tenantFacilityRestoreStructureAction,
                      enabled: actionsEnabled,
                      onPressed: actionsEnabled
                          ? () => widget.onRestore(item)
                          : null,
                    ),
                    if (widget.onPermanentDelete != null)
                      AppButton.tertiary(
                        leadingIcon: Icons.delete_forever_outlined,
                        label: l10n.tenantFacilityPermanentDeleteAction,
                        semanticLabel: l10n.tenantFacilityPermanentDeleteAction,
                        tooltip: l10n.tenantFacilityPermanentDeleteAction,
                        color: theme.statusColors.error,
                        enabled: actionsEnabled,
                        onPressed: actionsEnabled
                            ? () => widget.onPermanentDelete!(item)
                            : null,
                      ),
                  ] else ...<Widget>[
                    AppButton.tertiary(
                      leadingIcon: Icons.edit_outlined,
                      label: l10n.tenantFacilityEditAction,
                      semanticLabel: l10n.tenantFacilityEditAction,
                      tooltip: l10n.tenantFacilityEditAction,
                      enabled: actionsEnabled,
                      onPressed: actionsEnabled
                          ? () => widget.onEdit(item)
                          : null,
                    ),
                    AppButton.tertiary(
                      leadingIcon: Icons.delete_outline,
                      label: l10n.tenantFacilityDeleteAction,
                      semanticLabel: l10n.tenantFacilityDeleteAction,
                      tooltip: l10n.tenantFacilityDeleteAction,
                      color: theme.statusColors.error,
                      enabled: actionsEnabled,
                      onPressed: actionsEnabled
                          ? () => widget.onDelete(item)
                          : null,
                    ),
                  ],
                ],
              );
            },
          )
        : null;

    final bool canExport = canExportTenantFacilitySetup(
      ref.watch(appAccessPolicyProvider),
    );
    final bool canPrint = canPrintTenantFacilitySetup(
      ref.watch(appAccessPolicyProvider),
    );
    final List<AppListTableColumn<T>> allExportColumns =
        <AppListTableColumn<T>>[
          ...leadingColumns,
          nameColumn,
          ...extraColumns,
          statusColumn,
          ...?widget.optionalColumns,
          if (widget.nameDetailBuilder != null)
            AppListTableColumn<T>(
              id: 'record_id',
              label: l10n.reportsReferenceLabel,
              exportValue: (T item) {
                final List<String> details = widget.nameDetailBuilder!(item);
                return details.isEmpty ? '' : details.first;
              },
              cellBuilder: (_, T item) {
                final List<String> details = widget.nameDetailBuilder!(item);
                return tenantFacilitySetupAtomicCell(
                  details.isEmpty ? l10n.profileUnknownValue : details.first,
                );
              },
            ),
          AppListTableColumn<T>(
            id: 'details',
            label: l10n.accessAdminColumnDetails,
            sortComparator: (T left, T right) => appListTableCompareText(
              widget.subtitleBuilder(left),
              widget.subtitleBuilder(right),
            ),
            exportValue: (T item) => widget.subtitleBuilder(item),
            cellBuilder: (_, T item) =>
                tenantFacilitySetupAtomicCell(widget.subtitleBuilder(item)),
          ),
        ];
    final String exportStem = widget.columnVisibilityStorageKey ??
        'setup_structure_${widget.title}';

    final Widget table = AppListTable<T>(
      items: widget.serverDrivenList ? null : items,
      page: widget.serverDrivenList
          ? AppPage<T>(
              items: items,
              request: widget.pageRequest ?? PlatformAdminListConfig.initialPageRequest,
              totalItemCount: widget.totalItemCount ?? items.length,
            )
          : null,
      isLoading: searchLoading,
      paginationMode: widget.serverDrivenList
          ? AppListTablePaginationMode.buttons
          : AppListTablePaginationMode.infinite,
      onPageChanged: widget.serverDrivenList ? (AppPageRequest request) {
        unawaited(widget.onPageChanged?.call(request) ?? Future<void>.value());
      } : null,
      previousPageLabel: widget.serverDrivenList ? l10n.hrPreviousPageLabel : null,
      nextPageLabel: widget.serverDrivenList ? l10n.hrNextPageLabel : null,
      pageLabelBuilder: widget.serverDrivenList
          ? (AppPage<T> page) {
              if (searchLoading) {
                return '';
              }
              final int total = page.totalItemCount ?? page.items.length;
              if (total == 0) {
                return l10n.commonTableEmptyLabel;
              }
              final int start = page.pageIndex * page.pageSize + 1;
              final int end = start + page.items.length - 1;
              return '$start-$end / $total';
            }
          : null,
      columnVisibilityStorageKey:
          widget.columnVisibilityStorageKey ??
          'setup_structure_${widget.title}',
      columnVisibilityLabel: l10n.commonTableSettingsActionLabel,
      columnVisibilityTitle: l10n.commonTableSettingsTitle,
      columnVisibilityApplyLabel: l10n.receptionApplyColumnsAction,
      columnVisibilityResetLabel: l10n.receptionResetColumnsAction,
      columnVisibilityCloseLabel: l10n.commonCloseActionLabel,
      canExport: canExport,
      exportLabel: l10n.commonTableExportActionLabel,
      exportDialogTitle: l10n.commonTableExportDialogTitle,
      exportCancelLabel: l10n.commonCancelActionLabel,
      exportColumnsSectionLabel: l10n.commonTableExportColumnsSectionLabel,
      exportFiltersSectionLabel: l10n.commonTableExportFiltersSectionLabel,
      exportEmptyColumnsMessage: l10n.commonTableExportEmptyColumnsMessage,
      exportEmptyRowsMessage: l10n.commonTableExportEmptyRowsMessage,
      exportSuccessMessage: l10n.commonTableExportSuccessMessage,
      exportFailureMessage: l10n.commonTableExportFailureMessage,
      exportInvalidDateMessage: l10n.opdInvalidDateMessage,
      enablePrint: true,
      canPrint: canPrint,
      printLabel: l10n.commonPrintActionLabel,
      onPrint: (List<T> matching) => printTenantFacilitySetupListTable<T>(
        ref: ref,
        context: context,
        title: widget.title,
        columns: allExportColumns,
        items: matching,
        emptyText: widget.emptyLabel,
      ),
      goToTopLabel: l10n.commonGoToTopActionLabel,
      loadingMoreLabel: l10n.commonLoadingMoreLabel,
      allRowsLoadedLabel: l10n.commonAllRowsLoadedLabel,
      exportConfig: AppListTableExportConfig<T>(
        fileNameStem: exportStem.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_'),
        dateOf: (_) => null,
        sheetName: widget.title,
        enableDateFilter: false,
        dateFromLabel: l10n.commonTableExportDateFromLabel,
        dateToLabel: l10n.commonTableExportDateToLabel,
      ),
      onRowSelected: widget.onRowSelected,
      columns: <AppListTableColumn<T>>[
        ...leadingColumns,
        nameColumn,
        ...extraColumns,
        statusColumn,
        if (actionsColumn != null) actionsColumn,
      ],
      columnChoices: <AppListTableColumn<T>>[
        ...?widget.optionalColumns,
        if (widget.nameDetailBuilder != null)
          AppListTableColumn<T>(
            id: 'record_id',
            label: l10n.reportsReferenceLabel,
            exportValue: (T item) {
              final List<String> details = widget.nameDetailBuilder!(item);
              return details.isEmpty ? '' : details.first;
            },
            cellBuilder: (_, T item) {
              final List<String> details = widget.nameDetailBuilder!(item);
              return tenantFacilitySetupAtomicCell(
                details.isEmpty ? l10n.profileUnknownValue : details.first,
              );
            },
          ),
        AppListTableColumn<T>(
          id: 'details',
          label: l10n.accessAdminColumnDetails,
          sortComparator: (T left, T right) => appListTableCompareText(
            widget.subtitleBuilder(left),
            widget.subtitleBuilder(right),
          ),
          exportValue: (T item) => widget.subtitleBuilder(item),
          cellBuilder: (_, T item) =>
              tenantFacilitySetupAtomicCell(widget.subtitleBuilder(item)),
        ),
      ],
      search: AppListTableSearch<T>(
        controller: _searchController,
        semanticLabel: widget.searchLabel,
        hintText: widget.searchHint,
        matcher: widget.serverDrivenList
            ? (_, _) => true
            : (T item, String query) => _entitySearchText(
                widget.titleBuilder(item),
                widget.subtitleBuilder(item),
              ).contains(_normalizeSearch(query)),
        showAdvancedFilterButton: true,
        advancedFilterTitle: l10n.commonAdvancedFiltersTitle,
        advancedFilterButtonLabel: l10n.commonFiltersActionLabel,
        advancedFilterApplyLabel: l10n.opdApplyFiltersAction,
        advancedFilterResetLabel: l10n.opdClearFiltersAction,
        advancedFilterCloseLabel: l10n.commonCloseActionLabel,
        filterGroups: <AppSearchBarFilterGroup>[
          if (_hasScopeSelector)
            AppSearchBarFilterGroup(
              key: _scopeFilterKey,
              label: widget.scopeLabel!,
              allLabel: l10n.commonAllLabel,
              choices: <AppSearchBarFilterChoice>[
                for (final _SearchableEntityGroupScopeOption option
                    in widget.scopeOptions)
                  AppSearchBarFilterChoice(
                    value: option.id,
                    label: option.label,
                    icon: Icons.filter_alt_outlined,
                  ),
              ],
            ),
          ...widget.extraFilterGroups,
          AppSearchBarFilterGroup(
            key: _statusFilterKey,
            label: l10n.tenantFacilityTenantStatusLabel,
            allLabel: l10n.commonAllLabel,
            choices: <AppSearchBarFilterChoice>[
              AppSearchBarFilterChoice(
                value: _statusActive,
                label: l10n.tenantFacilityTenantStatusActive,
                icon: Icons.check_circle_outline,
              ),
              AppSearchBarFilterChoice(
                value: _statusDeleted,
                label: l10n.tenantFacilityTenantStatusDeleted,
                icon: Icons.delete_outline,
              ),
            ],
          ),
        ],
        filterValue: AppSearchBarFilterValue(
          options: <String, String>{
            ..._filterValue.options,
            if (_hasScopeSelector && _scopeId != _allScopes)
              _scopeFilterKey: _scopeId,
          },
        ),
        hasActiveFilters: hasActiveFilters,
        onFilterChanged: (AppSearchBarFilterValue value) {
          setState(() {
            _filterValue = value;
            final String? nextScope = value.options[_scopeFilterKey];
            if (_hasScopeSelector) {
              _scopeId = (nextScope == null || nextScope.isEmpty)
                  ? _allScopes
                  : nextScope;
            }
          });
          widget.onFiltersChanged?.call(value);
        },
        isLoading: searchLoading,
        trailingActions: widget.canManageRecords
            ? <AppSearchBarAction>[
                AppSearchBarAction(
                  icon: widget.addIcon,
                  label: widget.addLabel,
                  tooltip: widget.canAdd
                      ? widget.addLabel
                      : (widget.blockedMessage ?? widget.addLabel),
                  enabled: widget.canAdd,
                  onPressed: widget.canAdd ? widget.onAdd : null,
                ),
              ]
            : const <AppSearchBarAction>[],
      ),
      emptyBuilder: (_) {
        final bool searching =
            _searchController.text.trim().isNotEmpty || hasActiveFilters;
        return AppWorkspaceStatePanel.empty(
          title: widget.title,
          body: searching ? widget.noResultsLabel : widget.emptyLabel,
          detail: !searching && !widget.canAdd ? widget.blockedMessage : null,
          action: widget.canManageRecords && !searching
              ? AppButton.primary(
                  label: widget.addLabel,
                  leadingIcon: widget.addIcon,
                  enabled: widget.canAdd,
                  isLoading: searchLoading,
                  tooltip: widget.canAdd
                      ? widget.addLabel
                      : (widget.blockedMessage ?? widget.addLabel),
                  onPressed: widget.canAdd ? widget.onAdd : null,
                )
              : null,
        );
      },
      mobileItemBuilder: (BuildContext context, T item) {
        return AppListTableMobileItem(
          title: widget.titleBuilder(item),
          caption: widget.subtitleBuilder(item),
        );
      },
    );

    return table;
  }
}

String _entitySearchText(String title, String subtitle) {
  return _normalizeSearch('$title $subtitle');
}

String _normalizeSearch(String value) {
  return value.trim().toLowerCase();
}

final class _FacilityFieldChange {
  const _FacilityFieldChange({
    required this.label,
    required this.previousValue,
    required this.nextValue,
    this.isLogo = false,
    this.previousLogoUrl,
    this.nextLogoBytes,
    this.logoCleared = false,
  });

  final String label;
  final String previousValue;
  final String nextValue;
  final bool isLogo;
  final String? previousLogoUrl;
  final List<int>? nextLogoBytes;
  final bool logoCleared;
}

class _FacilityChangeDiffCard extends StatelessWidget {
  const _FacilityChangeDiffCard({required this.change});

  final _FacilityFieldChange change;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return AppCollapsibleSection(
      title: change.label,
      collapsible: false,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool stacked = constraints.maxWidth < 420;
          final Widget previousPane = _FacilityChangeValuePane(
            tone: _FacilityChangePaneTone.previous,
            caption: l10n.tenantFacilityFieldPreviousLabel,
            textValue: change.previousValue,
            isLogo: change.isLogo,
            logoUrl: change.previousLogoUrl,
            emptyLogoLabel: l10n.tenantFacilityFacilityDetailsNoLogo,
          );
          final Widget nextPane = _FacilityChangeValuePane(
            tone: _FacilityChangePaneTone.next,
            caption: l10n.tenantFacilityFieldNewLabel,
            textValue: change.nextValue,
            isLogo: change.isLogo,
            logoBytes: change.nextLogoBytes,
            logoCleared: change.logoCleared,
            emptyLogoLabel: change.logoCleared
                ? l10n.tenantFacilityLogoRemovedLabel
                : l10n.tenantFacilityFacilityDetailsNoLogo,
          );
          final Widget arrow = Padding(
            padding: EdgeInsets.symmetric(
              horizontal: stacked ? 0 : theme.spacing.sm,
              vertical: stacked ? theme.spacing.sm : 0,
            ),
            child: Icon(
              stacked
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_forward_rounded,
              color: colorScheme.primary,
              size: 22,
            ),
          );

          if (stacked) {
            return Column(
              children: <Widget>[previousPane, arrow, nextPane],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: previousPane),
              arrow,
              Expanded(child: nextPane),
            ],
          );
        },
      ),
    );
  }
}

enum _FacilityChangePaneTone { previous, next }

class _FacilityChangeValuePane extends StatelessWidget {
  const _FacilityChangeValuePane({
    required this.tone,
    required this.caption,
    required this.textValue,
    required this.isLogo,
    required this.emptyLogoLabel,
    this.logoUrl,
    this.logoBytes,
    this.logoCleared = false,
  });

  final _FacilityChangePaneTone tone;
  final String caption;
  final String textValue;
  final bool isLogo;
  final String emptyLogoLabel;
  final String? logoUrl;
  final List<int>? logoBytes;
  final bool logoCleared;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final bool isPrevious = tone == _FacilityChangePaneTone.previous;
    final Color background = isPrevious
        ? colorScheme.errorContainer.withValues(alpha: 0.28)
        : colorScheme.primaryContainer.withValues(alpha: 0.45);
    final Color border = isPrevious
        ? colorScheme.error.withValues(alpha: 0.22)
        : colorScheme.primary.withValues(alpha: 0.28);
    final Color captionColor = isPrevious
        ? colorScheme.onErrorContainer
        : colorScheme.primary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: theme.borders.all(color: border),
      ),
      child: Padding(
        padding: EdgeInsets.all(theme.spacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (isLogo)
              _FacilityConfirmLogoPreview(
                url: logoUrl,
                bytes: logoBytes,
                cleared: logoCleared,
                emptyLabel: emptyLogoLabel,
                emphasizeRemoval: isPrevious || logoCleared,
              )
            else ...<Widget>[
              Text(
                caption,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: captionColor,
                  fontWeight: AppFontWeight.emphasis,
                ),
              ),
              SizedBox(height: theme.spacing.sm),
              Text(
                textValue,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: AppFontWeight.emphasis,
                  decoration: isPrevious ? TextDecoration.lineThrough : null,
                  color: isPrevious
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.onSurface,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FacilityConfirmLogoPreview extends StatelessWidget {
  const _FacilityConfirmLogoPreview({
    required this.emptyLabel,
    required this.emphasizeRemoval,
    this.url,
    this.bytes,
    this.cleared = false,
  });

  final String? url;
  final List<int>? bytes;
  final bool cleared;
  final String emptyLabel;
  final bool emphasizeRemoval;

  static const double _previewHeight = 128;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final bool hasBytes = bytes != null && bytes!.isNotEmpty;
    final bool hasUrl = (url ?? '').trim().isNotEmpty;
    final Widget image;

    if (hasBytes) {
      image = Image.memory(
        Uint8List.fromList(bytes!),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder:
            (BuildContext context, Object error, StackTrace? stackTrace) =>
                Icon(Icons.broken_image_outlined, color: colorScheme.error),
      );
    } else if (hasUrl && !cleared) {
      final String? resolvedUrl = resolveAppMediaUrl(
        url,
        ProviderScope.containerOf(
          context,
          listen: false,
        ).read(appConfigProvider).apiBaseUrl,
      );
      image = Image.network(
        resolvedUrl ?? url!.trim(),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder:
            (BuildContext context, Object error, StackTrace? stackTrace) =>
                Icon(Icons.broken_image_outlined, color: colorScheme.error),
      );
    } else {
      image = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            cleared
                ? Icons.hide_image_outlined
                : Icons.image_not_supported_outlined,
            color: colorScheme.onSurfaceVariant,
            size: 28,
          ),
          SizedBox(height: theme.spacing.xs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              emptyLabel,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: theme.borders.all(),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: double.infinity,
          height: _previewHeight,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Padding(padding: EdgeInsets.all(theme.spacing.sm), child: image),
              if (emphasizeRemoval && (hasUrl || cleared) && !hasBytes)
                ColoredBox(
                  color: colorScheme.error.withValues(alpha: 0.12),
                  child: const SizedBox.expand(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}


class _DepartmentFormDialog extends ConsumerStatefulWidget {
  const _DepartmentFormDialog({
    required this.snapshot,
    this.department,
    this.tenantOptions = const <TenantProfile>[],
    this.facilityOptions = const <FacilityProfile>[],
  });

  final FacilitySetupSnapshot snapshot;
  final DepartmentProfile? department;
  final List<TenantProfile> tenantOptions;
  final List<FacilityProfile> facilityOptions;

  @override
  ConsumerState<_DepartmentFormDialog> createState() =>
      _DepartmentFormDialogState();
}

class _DepartmentFormDialogState extends ConsumerState<_DepartmentFormDialog> {
  static const AppPageRequest _lookupRequest = AppPageRequest(
    pageSize: PlatformAdminListConfig.pageSize,
  );

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _shortNameController;
  late DepartmentSetupType _type;
  late bool _isActive;
  String? _selectedTenantId;
  String? _selectedFacilityId;
  List<TenantProfile> _tenantOptions = const <TenantProfile>[];
  List<FacilityProfile> _facilityOptions = const <FacilityProfile>[];
  bool _loadingOptions = false;
  bool _similarityAccepted = false;
  bool _checkingSimilarity = false;
  String? _nameErrorText;

  bool get _isCreate => widget.department == null;

  @override
  void initState() {
    super.initState();
    final DepartmentProfile? department = widget.department;
    _nameController = TextEditingController(text: department?.name);
    _shortNameController = TextEditingController(text: department?.shortName);
    _type = department?.type ?? DepartmentSetupType.clinical;
    _isActive = department?.isActive ?? true;
    _tenantOptions = widget.tenantOptions;
    _facilityOptions = widget.facilityOptions;
    _selectedTenantId =
        department?.tenantId.trim().isNotEmpty == true
        ? department!.tenantId.trim()
        : widget.snapshot.tenant?.id.trim();
    _selectedFacilityId =
        department?.facilityId?.trim().isNotEmpty == true
        ? department!.facilityId!.trim()
        : widget.snapshot.facility?.id.trim();
    unawaited(_ensureScopeOptions());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _shortNameController.dispose();
    super.dispose();
  }

  Future<void> _ensureScopeOptions() async {
    if (!_isCreate) {
      return;
    }
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final TenantFacilityDepartmentsListScope scope =
        tenantFacilityDepartmentsListScope(policy);
    if (scope == TenantFacilityDepartmentsListScope.facility) {
      return;
    }

    setState(() {
      _loadingOptions = true;
    });

    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );

    if (scope == TenantFacilityDepartmentsListScope.platform &&
        _tenantOptions.isEmpty) {
      final Result<AppPage<TenantProfile>> tenantsResult = await repository
          .listTenants(request: _lookupRequest);
      if (!mounted) {
        return;
      }
      tenantsResult.when(
        success: (AppPage<TenantProfile> page) {
          _tenantOptions = page.items
              .where((TenantProfile tenant) => !tenant.isDeleted)
              .toList(growable: false);
        },
        failure: (_) {},
      );
    }

    final String? tenantIdForFacilities = switch (scope) {
      TenantFacilityDepartmentsListScope.platform => _selectedTenantId,
      TenantFacilityDepartmentsListScope.tenant =>
        policy.tenantId ?? widget.snapshot.tenant?.id,
      TenantFacilityDepartmentsListScope.facility => null,
    };

    if (tenantFacilityDepartmentsShowsFacilityFilter(scope) &&
        (scope != TenantFacilityDepartmentsListScope.platform ||
            (tenantIdForFacilities != null &&
                tenantIdForFacilities.isNotEmpty))) {
      final Result<AppPage<FacilityProfile>> facilitiesResult = await repository
          .listFacilities(
            request: _lookupRequest,
            tenantId: tenantIdForFacilities,
          );
      if (!mounted) {
        return;
      }
      facilitiesResult.when(
        success: (AppPage<FacilityProfile> page) {
          _facilityOptions = page.items
              .where((FacilityProfile facility) => !facility.isDeleted)
              .toList(growable: false);
        },
        failure: (_) {},
      );
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _loadingOptions = false;
      _syncFacilitySelection();
    });
  }

  void _syncFacilitySelection() {
    final String? facilityId = _selectedFacilityId;
    if (facilityId == null) {
      return;
    }
    final bool allowed = _facilityOptions.any(
      (FacilityProfile facility) =>
          facility.id == facilityId && !facility.isDeleted,
    );
    if (!allowed) {
      _selectedFacilityId = null;
    }
  }

  Future<void> _onTenantChanged(String? tenantId) async {
    setState(() {
      _selectedTenantId = tenantId;
      _selectedFacilityId = null;
      _facilityOptions = const <FacilityProfile>[];
      _loadingOptions = tenantId != null && tenantId.isNotEmpty;
    });
    if (tenantId == null || tenantId.isEmpty) {
      return;
    }
    final Result<AppPage<FacilityProfile>> result = await ref
        .read(tenantFacilityRepositoryProvider)
        .listFacilities(request: _lookupRequest, tenantId: tenantId);
    if (!mounted) {
      return;
    }
    result.when(
      success: (AppPage<FacilityProfile> page) {
        setState(() {
          _facilityOptions = page.items
              .where((FacilityProfile facility) => !facility.isDeleted)
              .toList(growable: false);
          _loadingOptions = false;
        });
      },
      failure: (_) {
        setState(() {
          _loadingOptions = false;
        });
      },
    );
  }

  IconData _departmentTypeIcon(DepartmentSetupType type) {
    return switch (type) {
      DepartmentSetupType.clinical => Icons.medical_services_outlined,
      DepartmentSetupType.administrative => Icons.apartment_outlined,
      DepartmentSetupType.support => Icons.support_agent_outlined,
      DepartmentSetupType.diagnostics => Icons.biotech_outlined,
      DepartmentSetupType.other => Icons.category_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppAccessPolicy policy = ref.watch(appAccessPolicyProvider);
    final TenantFacilityDepartmentsListScope scope =
        tenantFacilityDepartmentsListScope(policy);
    final submission = ref.watch(tenantFacilitySetupSubmissionProvider);
    final bool isEditing = !_isCreate;
    final bool canEdit = !submission.isSubmitting && !_checkingSimilarity;
    final bool showTenantPicker =
        _isCreate && tenantFacilityDepartmentsShowsTenantFilter(scope);
    final bool showFacilityPicker =
        _isCreate && tenantFacilityDepartmentsShowsFacilityFilter(scope);
    final ThemeData theme = Theme.of(context);

    final Widget? tenantField = showTenantPicker
        ? AppSelectField<String>.searchable(
            value: _selectedTenantId ?? _noneSelection,
            enabled: canEdit && !_loadingOptions,
            labelText: l10n.profileTenantLabel,
            isRequired: true,
            options: <AppSelectOption<String>>[
              AppSelectOption<String>(
                value: _noneSelection,
                label: l10n.tenantFacilityNoSelectionLabel,
              ),
              for (final TenantProfile tenant in _tenantOptions)
                AppSelectOption<String>(
                  value: tenant.id,
                  label: tenant.name,
                  leadingIcon: const Icon(Icons.apartment_outlined),
                ),
            ],
            validator: (String? value) {
              if (value == null ||
                  value.isEmpty ||
                  value == _noneSelection) {
                return l10n.validationRequired;
              }
              return null;
            },
            onChanged: (String? value) {
              final String? next =
                  value == null || value == _noneSelection ? null : value;
              unawaited(_onTenantChanged(next));
            },
          )
        : null;
    final Widget? facilityField = showFacilityPicker
        ? AppSelectField<String>.searchable(
            value: _selectedFacilityId ?? _noneSelection,
            enabled:
                canEdit &&
                !_loadingOptions &&
                (!showTenantPicker ||
                    (_selectedTenantId != null &&
                        _selectedTenantId!.isNotEmpty)),
            labelText: l10n.profileFacilityLabel,
            isRequired: true,
            options: <AppSelectOption<String>>[
              AppSelectOption<String>(
                value: _noneSelection,
                label: l10n.tenantFacilityNoSelectionLabel,
              ),
              for (final FacilityProfile facility in _facilityOptions)
                AppSelectOption<String>(
                  value: facility.id,
                  label: facility.name,
                  leadingIcon: const Icon(Icons.local_hospital_outlined),
                ),
            ],
            validator: (String? value) {
              if (value == null ||
                  value.isEmpty ||
                  value == _noneSelection) {
                return l10n.validationRequired;
              }
              return null;
            },
            onChanged: (String? value) {
              setState(() {
                _selectedFacilityId =
                    value == null || value == _noneSelection ? null : value;
              });
            },
          )
        : null;

    return AppDialog(
      title: Text(
        isEditing
            ? l10n.tenantFacilityEditDepartmentTitle
            : l10n.tenantFacilityAddDepartmentTitle,
      ),
      scrollable: true,
      closeEnabled: canEdit,
      content: Form(
        key: _formKey,
        child: AppFormSection(
          density: AppFormSectionDensity.compact,
          children: <Widget>[
            if (_checkingSimilarity || _loadingOptions)
              Padding(
                padding: EdgeInsets.only(bottom: theme.spacing.sm),
                child: Row(
                  children: <Widget>[
                    const AppLoadingIndicator.compact(expand: false),
                    SizedBox(width: theme.spacing.sm),
                    Expanded(
                      child: Text(
                        _checkingSimilarity
                            ? l10n
                                  .tenantFacilityDepartmentSimilarityCheckingMessage
                            : l10n.commonLoadingCompactTitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: AppFontWeight.emphasis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (tenantField != null && facilityField != null)
              AppResponsiveFieldRow.two(
                gap: AppResponsiveFieldRowGap.form,
                left: tenantField,
                right: facilityField,
              )
            else if (tenantField != null)
              tenantField
            else if (facilityField != null)
              facilityField,
            AppResponsiveFieldRow.two(
              gap: AppResponsiveFieldRowGap.form,
              left: AppTextField(
                controller: _nameController,
                enabled: canEdit,
                labelText: l10n.tenantFacilityDepartmentNameLabel,
                isRequired: true,
                textCapitalization: TextCapitalization.words,
                errorText: _nameErrorText,
                validator: AppValidators.requiredText(l10n.validationRequired),
                onChanged: (_) {
                  if (_nameErrorText != null) {
                    setState(() {
                      _nameErrorText = null;
                    });
                  }
                },
              ),
              right: AppTextField(
                controller: _shortNameController,
                enabled: canEdit,
                labelText: l10n.tenantFacilityDepartmentShortNameLabel,
              ),
            ),
            AppResponsiveFieldRow.two(
              gap: AppResponsiveFieldRowGap.form,
              left: AppSelectField<DepartmentSetupType>(
                value: _type,
                enabled: canEdit,
                labelText: l10n.tenantFacilityDepartmentTypeLabel,
                isRequired: true,
                options: <AppSelectOption<DepartmentSetupType>>[
                  for (final type in DepartmentSetupType.values)
                    AppSelectOption<DepartmentSetupType>(
                      value: type,
                      label: _departmentTypeLabel(l10n, type),
                      leadingIcon: Icon(_departmentTypeIcon(type)),
                    ),
                ],
                onChanged: (DepartmentSetupType? value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _type = value;
                  });
                },
              ),
              right: AppSwitchField(
                title: l10n.tenantFacilityActiveLabel,
                value: _isActive,
                enabled: canEdit,
                onChanged: (bool value) {
                  setState(() {
                    _isActive = value;
                  });
                },
              ),
            ),
            _SubmissionFailureBanner(),
          ],
        ),
      ),
      actions: <Widget>[
        AppButton.close(
          leadingIcon: AppActionIcons.cancel,
          label: l10n.commonCancelActionLabel,
          enabled: canEdit,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton.primary(
          label: isEditing
              ? l10n.tenantFacilitySaveAction
              : l10n.tenantFacilityCreateAction,
          leadingIcon: Icons.save_outlined,
          isLoading: submission.isSubmitting || _checkingSimilarity,
          onPressed: _submit,
        ),
      ],
    );
  }

  (String?, String?) _resolveScopeIds() {
    final DepartmentProfile? editing = widget.department;
    if (editing != null) {
      final String? tenantId = editing.tenantId.trim().isNotEmpty
          ? editing.tenantId.trim()
          : widget.snapshot.tenant?.mutationId.trim();
      final String? facilityId = editing.facilityId?.trim().isNotEmpty == true
          ? editing.facilityId!.trim()
          : widget.snapshot.facility?.mutationId.trim();
      return (tenantId, facilityId);
    }

    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final TenantFacilityDepartmentsListScope scope =
        tenantFacilityDepartmentsListScope(policy);
    final String? tenantId = switch (scope) {
      TenantFacilityDepartmentsListScope.platform => _selectedTenantId?.trim(),
      TenantFacilityDepartmentsListScope.tenant ||
      TenantFacilityDepartmentsListScope.facility =>
        policy.tenantId ?? widget.snapshot.tenant?.mutationId.trim(),
    };
    final String? facilityId = switch (scope) {
      TenantFacilityDepartmentsListScope.platform ||
      TenantFacilityDepartmentsListScope.tenant =>
        _selectedFacilityId?.trim(),
      TenantFacilityDepartmentsListScope.facility =>
        policy.facilityId ?? widget.snapshot.facility?.mutationId.trim(),
    };
    return (tenantId, facilityId);
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true || _checkingSimilarity) {
      return;
    }

    final (String? tenantId, String? facilityId) = _resolveScopeIds();
    if (tenantId == null ||
        tenantId.isEmpty ||
        facilityId == null ||
        facilityId.isEmpty) {
      return;
    }

    final String name = _nameController.text.trim();
    final String shortName = resolveDepartmentShortName(
      name,
      _shortNameController.text,
    );

    setState(() {
      _checkingSimilarity = true;
    });
    final bool canProceed;
    try {
      canProceed = await _guardAgainstDuplicates(
        facilityId: facilityId,
        name: name,
        shortName: shortName,
      );
    } finally {
      if (mounted) {
        setState(() {
          _checkingSimilarity = false;
        });
      }
    }
    if (!canProceed || !mounted) {
      return;
    }

    final DepartmentProfile? editing = widget.department;
    final bool saved = await ref
        .read(tenantFacilitySetupSubmissionProvider.notifier)
        .saveDepartment(
          id: editing?.mutationId,
          tenantId: tenantId,
          facilityId: facilityId,
          name: name,
          shortName: shortName,
          type: _type,
          isActive: _isActive,
          confirmSimilar: _similarityAccepted,
        );

    if (saved && mounted) {
      final DepartmentProfile? created = _isCreate
          ? ref.read(tenantFacilitySetupSubmissionProvider).lastSavedDepartment
          : null;
      Navigator.of(context).pop<Object?>(created ?? true);
      return;
    }

    if (!mounted) {
      return;
    }

    final AppFailure? failure = ref
        .read(tenantFacilitySetupSubmissionProvider)
        .failure;
    if (failure?.messageKey == 'errors.department.duplicate_name') {
      setState(() {
        _nameErrorText = context.l10n.tenantFacilityDepartmentNameAlreadyInUse;
      });
      return;
    }
    if (!_isDepartmentSimilarityConflict(failure)) {
      return;
    }

    ref.read(tenantFacilitySetupSubmissionProvider.notifier).clearFailure();
    setState(() {
      _similarityAccepted = false;
      _checkingSimilarity = true;
    });
    final bool confirmed;
    try {
      confirmed = await _guardAgainstDuplicates(
        facilityId: facilityId,
        name: name,
        shortName: shortName,
        forceReviewMatches: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _checkingSimilarity = false;
        });
      }
    }
    if (!confirmed || !mounted) {
      return;
    }

    final bool retried = await ref
        .read(tenantFacilitySetupSubmissionProvider.notifier)
        .saveDepartment(
          id: editing?.mutationId,
          tenantId: tenantId,
          facilityId: facilityId,
          name: name,
          shortName: shortName,
          type: _type,
          isActive: _isActive,
          confirmSimilar: true,
        );
    if (retried && mounted) {
      final DepartmentProfile? created = _isCreate
          ? ref.read(tenantFacilitySetupSubmissionProvider).lastSavedDepartment
          : null;
      Navigator.of(context).pop<Object?>(created ?? true);
    }
  }

  bool _isDepartmentSimilarityConflict(AppFailure? failure) {
    if (failure == null || failure.category != AppFailureCategory.conflict) {
      return false;
    }
    if (failure.messageKey == 'errors.department.similar_exists') {
      return true;
    }
    final String detail = (failure.detailMessage ?? '').toLowerCase();
    return detail.contains('similar department') ||
        detail.contains('confirm to create anyway');
  }

  Future<bool> _guardAgainstDuplicates({
    required String facilityId,
    required String name,
    required String shortName,
    bool forceReviewMatches = false,
  }) async {
    final DepartmentProfile? editing = widget.department;

    if (!_isCreate &&
        !forceReviewMatches &&
        editing != null &&
        normalizeDepartmentName(name) ==
            normalizeDepartmentName(editing.name) &&
        normalizeDepartmentName(shortName) ==
            normalizeDepartmentName(
              resolveDepartmentShortName(editing.name, editing.shortName),
            ) &&
        _type == editing.type &&
        _isActive == editing.isActive) {
      setState(() {
        _nameErrorText = null;
        _similarityAccepted = false;
      });
      return true;
    }

    final List<DepartmentProfile> existing = await _loadExistingDepartments(
      facilityId,
      name,
    );
    final DepartmentDuplicateCheckResult result = checkDepartmentDuplicates(
      name: name,
      shortName: shortName,
      type: _type,
      isActive: _isActive,
      existing: existing,
      excludeDepartment: editing,
      excludeDepartmentId: editing?.mutationId ?? editing?.id,
    );

    final bool exactNameConflict = result.exactNameConflict;
    final List<DepartmentSimilarityMatch> reviewMatches = exactNameConflict
        ? result.similarMatches
              .where(
                (DepartmentSimilarityMatch match) => match.exactNameConflict,
              )
              .toList(growable: false)
        : result.overridableMatches;

    if (!mounted) {
      return false;
    }

    if (!_isCreate &&
        !forceReviewMatches &&
        !exactNameConflict &&
        reviewMatches.isEmpty) {
      setState(() {
        _nameErrorText = null;
        _similarityAccepted = false;
      });
      return true;
    }

    setState(() {
      _nameErrorText = exactNameConflict
          ? context.l10n.tenantFacilityDepartmentNameAlreadyInUse
          : null;
      if (exactNameConflict) {
        _similarityAccepted = false;
      }
    });

    final DepartmentSimilarityDialogResult decision =
        await showDepartmentSimilarityDialog(
          context,
          proposed: DepartmentSimilarityProposedValues(
            name: name,
            shortName: shortName,
            type: _type,
            isActive: _isActive,
          ),
          matches: reviewMatches,
          allowProceed: !exactNameConflict,
        );
    if (!mounted) {
      return false;
    }

    switch (decision.action) {
      case DepartmentSimilarityAction.cancel:
        setState(() {
          _similarityAccepted = false;
        });
        return false;
      case DepartmentSimilarityAction.useExisting:
        final DepartmentProfile? existingDepartment =
            decision.selectedDepartment;
        if (existingDepartment != null) {
          Navigator.of(context).pop<Object?>(existingDepartment);
        }
        return false;
      case DepartmentSimilarityAction.proceed:
        setState(() {
          _similarityAccepted = reviewMatches.isNotEmpty || forceReviewMatches;
          _nameErrorText = null;
        });
        return true;
    }
  }

  Future<List<DepartmentProfile>> _loadExistingDepartments(
    String facilityId,
    String name,
  ) async {
    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );
    final Set<String> seenIds = <String>{};
    final List<DepartmentProfile> departments = <DepartmentProfile>[];

    Future<void> appendMatches(String? search) async {
      final Result<AppPage<DepartmentProfile>> result = await repository
          .listDepartments(
            request: _lookupRequest,
            facilityId: facilityId,
            search: search,
          );
      result.when(
        success: (AppPage<DepartmentProfile> page) {
          for (final DepartmentProfile department in page.items) {
            final String key = department.mutationId.isNotEmpty
                ? department.mutationId
                : department.id;
            if (seenIds.add(key)) {
              departments.add(department);
            }
          }
        },
        failure: (_) {},
      );
    }

    // Bounded peer set only — backend confirm_similar remains authoritative.
    await appendMatches(null);

    return departments;
  }
}

class _UnitFormDialog extends ConsumerStatefulWidget {
  const _UnitFormDialog({
    required this.snapshot,
    this.unit,
    this.tenantOptions = const <TenantProfile>[],
    this.facilityOptions = const <FacilityProfile>[],
    this.departmentOptions = const <DepartmentProfile>[],
  });

  final FacilitySetupSnapshot snapshot;
  final UnitProfile? unit;
  final List<TenantProfile> tenantOptions;
  final List<FacilityProfile> facilityOptions;
  final List<DepartmentProfile> departmentOptions;

  @override
  ConsumerState<_UnitFormDialog> createState() => _UnitFormDialogState();
}

class _UnitFormDialogState extends ConsumerState<_UnitFormDialog> {
  static const AppPageRequest _lookupRequest = AppPageRequest(
    pageSize: PlatformAdminListConfig.pageSize,
  );

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late bool _isActive;
  String? _selectedTenantId;
  String? _selectedFacilityId;
  String? _selectedDepartmentId;
  List<TenantProfile> _tenantOptions = const <TenantProfile>[];
  List<FacilityProfile> _facilityOptions = const <FacilityProfile>[];
  List<DepartmentProfile> _departmentOptions = const <DepartmentProfile>[];
  bool _loadingOptions = false;
  bool _checkingSimilarity = false;
  String? _nameErrorText;

  bool get _isCreate => widget.unit == null;

  @override
  void initState() {
    super.initState();
    final UnitProfile? unit = widget.unit;
    _nameController = TextEditingController(text: unit?.name);
    _isActive = unit?.isActive ?? true;
    _tenantOptions = widget.tenantOptions;
    _facilityOptions = widget.facilityOptions;
    _departmentOptions = widget.departmentOptions;
    _selectedTenantId = unit?.tenantId.trim().isNotEmpty == true
        ? unit!.tenantId.trim()
        : widget.snapshot.tenant?.id.trim();
    _selectedFacilityId = unit?.facilityId?.trim().isNotEmpty == true
        ? unit!.facilityId!.trim()
        : widget.snapshot.facility?.id.trim();
    _selectedDepartmentId = unit?.departmentId?.trim().isNotEmpty == true
        ? unit!.departmentId!.trim()
        : (_departmentOptions.length == 1
              ? _departmentOptions.first.id
              : (widget.snapshot.departments
                        .where(
                          (DepartmentProfile department) =>
                              !department.isDeleted,
                        )
                        .length ==
                    1
                    ? widget.snapshot.departments
                          .firstWhere(
                            (DepartmentProfile department) =>
                                !department.isDeleted,
                          )
                          .id
                    : null));
    unawaited(_ensureScopeOptions());
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _ensureScopeOptions() async {
    if (!_isCreate) {
      return;
    }
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final TenantFacilityUnitsListScope scope = tenantFacilityUnitsListScope(
      policy,
    );

    setState(() {
      _loadingOptions = true;
    });

    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );

    if (scope == TenantFacilityUnitsListScope.platform &&
        _tenantOptions.isEmpty) {
      final Result<AppPage<TenantProfile>> tenantsResult = await repository
          .listTenants(request: _lookupRequest);
      if (!mounted) {
        return;
      }
      tenantsResult.when(
        success: (AppPage<TenantProfile> page) {
          _tenantOptions = page.items
              .where((TenantProfile tenant) => !tenant.isDeleted)
              .toList(growable: false);
        },
        failure: (_) {},
      );
    }

    final String? tenantIdForFacilities = switch (scope) {
      TenantFacilityUnitsListScope.platform => _selectedTenantId,
      TenantFacilityUnitsListScope.tenant =>
        policy.tenantId ?? widget.snapshot.tenant?.id,
      TenantFacilityUnitsListScope.facility => null,
    };

    if (tenantFacilityUnitsShowsFacilityFilter(scope) &&
        (scope != TenantFacilityUnitsListScope.platform ||
            (tenantIdForFacilities != null &&
                tenantIdForFacilities.isNotEmpty))) {
      final Result<AppPage<FacilityProfile>> facilitiesResult = await repository
          .listFacilities(
            request: _lookupRequest,
            tenantId: tenantIdForFacilities,
          );
      if (!mounted) {
        return;
      }
      facilitiesResult.when(
        success: (AppPage<FacilityProfile> page) {
          _facilityOptions = page.items
              .where((FacilityProfile facility) => !facility.isDeleted)
              .toList(growable: false);
        },
        failure: (_) {},
      );
    }

    await _loadDepartmentOptions(
      tenantId: switch (scope) {
        TenantFacilityUnitsListScope.platform => _selectedTenantId,
        TenantFacilityUnitsListScope.tenant ||
        TenantFacilityUnitsListScope.facility =>
          policy.tenantId ?? widget.snapshot.tenant?.id,
      },
      facilityId: switch (scope) {
        TenantFacilityUnitsListScope.platform ||
        TenantFacilityUnitsListScope.tenant =>
          _selectedFacilityId,
        TenantFacilityUnitsListScope.facility =>
          policy.facilityId ?? widget.snapshot.facility?.id,
      },
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _loadingOptions = false;
      _syncFacilitySelection();
      _syncDepartmentSelection();
    });
  }

  Future<void> _loadDepartmentOptions({
    String? tenantId,
    String? facilityId,
  }) async {
    final bool tenantScoped = tenantId != null && tenantId.isNotEmpty;
    final bool facilityScoped = facilityId != null && facilityId.isNotEmpty;
    if (!tenantScoped && !facilityScoped) {
      _departmentOptions = const <DepartmentProfile>[];
      return;
    }
    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );
    final Result<AppPage<DepartmentProfile>> result = await repository
        .listDepartments(
          request: _lookupRequest,
          tenantId: tenantScoped ? tenantId : null,
          facilityId: facilityScoped ? facilityId : null,
        );
    if (!mounted) {
      return;
    }
    result.when(
      success: (AppPage<DepartmentProfile> page) {
        _departmentOptions = page.items
            .where((DepartmentProfile department) => !department.isDeleted)
            .toList(growable: false);
      },
      failure: (_) {},
    );
  }

  void _syncFacilitySelection() {
    final String? facilityId = _selectedFacilityId;
    if (facilityId == null) {
      return;
    }
    final bool allowed = _facilityOptions.any(
      (FacilityProfile facility) =>
          facility.id == facilityId && !facility.isDeleted,
    );
    if (!allowed) {
      _selectedFacilityId = null;
    }
  }

  void _syncDepartmentSelection() {
    final String? departmentId = _selectedDepartmentId;
    if (departmentId == null) {
      return;
    }
    final bool allowed = _departmentOptions.any(
      (DepartmentProfile department) =>
          department.id == departmentId && !department.isDeleted,
    );
    if (!allowed) {
      _selectedDepartmentId = null;
    }
  }

  Future<void> _onTenantChanged(String? tenantId) async {
    setState(() {
      _selectedTenantId = tenantId;
      _selectedFacilityId = null;
      _selectedDepartmentId = null;
      _facilityOptions = const <FacilityProfile>[];
      _departmentOptions = const <DepartmentProfile>[];
      _loadingOptions = tenantId != null && tenantId.isNotEmpty;
    });
    if (tenantId == null || tenantId.isEmpty) {
      return;
    }
    final Result<AppPage<FacilityProfile>> result = await ref
        .read(tenantFacilityRepositoryProvider)
        .listFacilities(request: _lookupRequest, tenantId: tenantId);
    if (!mounted) {
      return;
    }
    result.when(
      success: (AppPage<FacilityProfile> page) {
        setState(() {
          _facilityOptions = page.items
              .where((FacilityProfile facility) => !facility.isDeleted)
              .toList(growable: false);
          _loadingOptions = false;
        });
      },
      failure: (_) {
        setState(() {
          _loadingOptions = false;
        });
      },
    );
  }

  Future<void> _onFacilityChanged(String? facilityId) async {
    setState(() {
      _selectedFacilityId = facilityId;
      _selectedDepartmentId = null;
      _departmentOptions = const <DepartmentProfile>[];
      _loadingOptions = facilityId != null && facilityId.isNotEmpty;
    });
    if (facilityId == null || facilityId.isEmpty) {
      setState(() {
        _loadingOptions = false;
      });
      return;
    }
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final String? tenantId = switch (tenantFacilityUnitsListScope(policy)) {
      TenantFacilityUnitsListScope.platform => _selectedTenantId,
      TenantFacilityUnitsListScope.tenant ||
      TenantFacilityUnitsListScope.facility =>
        policy.tenantId ?? widget.snapshot.tenant?.id,
    };
    await _loadDepartmentOptions(tenantId: tenantId, facilityId: facilityId);
    if (!mounted) {
      return;
    }
    setState(() {
      _loadingOptions = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppAccessPolicy policy = ref.watch(appAccessPolicyProvider);
    final TenantFacilityUnitsListScope scope = tenantFacilityUnitsListScope(
      policy,
    );
    final submission = ref.watch(tenantFacilitySetupSubmissionProvider);
    final bool isEditing = !_isCreate;
    final bool showDialogLoadingOverlay =
        _loadingOptions || _checkingSimilarity || submission.isSubmitting;
    final bool canEdit = !showDialogLoadingOverlay;
    final bool showTenantPicker =
        _isCreate && tenantFacilityUnitsShowsTenantFilter(scope);
    final bool showFacilityPicker =
        _isCreate && tenantFacilityUnitsShowsFacilityFilter(scope);
    final ThemeData theme = Theme.of(context);
    final String overlayTitle;
    final String overlayBody;
    if (_checkingSimilarity) {
      overlayTitle = l10n.tenantFacilityUnitSimilarityCheckingMessage;
      overlayBody = l10n.commonLoadingBody;
    } else if (submission.isSubmitting) {
      overlayTitle = l10n.tenantFacilityUnitSavingTitle;
      overlayBody = l10n.tenantFacilityUnitSavingBody;
    } else {
      overlayTitle = l10n.tenantFacilityUnitOptionsLoadingTitle;
      overlayBody = l10n.tenantFacilityUnitOptionsLoadingBody;
    }

    final Widget? tenantField = showTenantPicker
        ? AppSelectField<String>.searchable(
            value: _selectedTenantId ?? _noneSelection,
            enabled: canEdit,
            labelText: l10n.profileTenantLabel,
            isRequired: true,
            options: <AppSelectOption<String>>[
              AppSelectOption<String>(
                value: _noneSelection,
                label: l10n.tenantFacilityNoSelectionLabel,
              ),
              for (final TenantProfile tenant in _tenantOptions)
                AppSelectOption<String>(
                  value: tenant.id,
                  label: tenant.name,
                  leadingIcon: const Icon(Icons.apartment_outlined),
                ),
            ],
            validator: (String? value) {
              if (value == null ||
                  value.isEmpty ||
                  value == _noneSelection) {
                return l10n.validationRequired;
              }
              return null;
            },
            onChanged: (String? value) {
              final String? next =
                  value == null || value == _noneSelection ? null : value;
              unawaited(_onTenantChanged(next));
            },
          )
        : null;
    final Widget? facilityField = showFacilityPicker
        ? AppSelectField<String>.searchable(
            value: _selectedFacilityId ?? _noneSelection,
            enabled:
                canEdit &&
                (!showTenantPicker ||
                    (_selectedTenantId != null &&
                        _selectedTenantId!.isNotEmpty)),
            labelText: l10n.profileFacilityLabel,
            isRequired: true,
            options: <AppSelectOption<String>>[
              AppSelectOption<String>(
                value: _noneSelection,
                label: l10n.tenantFacilityNoSelectionLabel,
              ),
              for (final FacilityProfile facility in _facilityOptions)
                AppSelectOption<String>(
                  value: facility.id,
                  label: facility.name,
                  leadingIcon: const Icon(Icons.local_hospital_outlined),
                ),
            ],
            validator: (String? value) {
              if (value == null ||
                  value.isEmpty ||
                  value == _noneSelection) {
                return l10n.validationRequired;
              }
              return null;
            },
            onChanged: (String? value) {
              final String? next =
                  value == null || value == _noneSelection ? null : value;
              unawaited(_onFacilityChanged(next));
            },
          )
        : null;

    final Widget departmentField = AppSelectField<String>.searchable(
      value: _selectedDepartmentId ?? _noneSelection,
      enabled:
          canEdit &&
          _isCreate &&
          _departmentOptions.isNotEmpty,
      labelText: l10n.tenantFacilityUnitDepartmentLabel,
      isRequired: true,
      options: <AppSelectOption<String>>[
        AppSelectOption<String>(
          value: _noneSelection,
          label: l10n.tenantFacilityNoSelectionLabel,
        ),
        for (final DepartmentProfile department in _departmentOptions)
          AppSelectOption<String>(
            value: department.id,
            label: department.name,
            leadingIcon: const Icon(Icons.domain_outlined),
          ),
      ],
      validator: (String? value) {
        if (value == null || value.isEmpty || value == _noneSelection) {
          return l10n.validationRequired;
        }
        return null;
      },
      onChanged: (String? value) {
        setState(() {
          _selectedDepartmentId =
              value == null || value == _noneSelection ? null : value;
        });
      },
    );

    final Widget formBody = Form(
      key: _formKey,
      child: AppFormSection(
        density: AppFormSectionDensity.compact,
        children: <Widget>[
          if (tenantField != null && facilityField != null)
            AppResponsiveFieldRow.two(
              gap: AppResponsiveFieldRowGap.form,
              left: tenantField,
              right: facilityField,
            )
          else if (tenantField != null)
            tenantField
          else if (facilityField != null)
            facilityField,
          AppResponsiveFieldRow.two(
            gap: AppResponsiveFieldRowGap.form,
            left: AppTextField(
              controller: _nameController,
              enabled: canEdit,
              labelText: l10n.tenantFacilityUnitNameLabel,
              isRequired: true,
              textCapitalization: TextCapitalization.words,
              errorText: _nameErrorText,
              validator: AppValidators.requiredText(l10n.validationRequired),
              onChanged: (_) {
                if (_nameErrorText != null) {
                  setState(() {
                    _nameErrorText = null;
                  });
                }
              },
            ),
            right: departmentField,
          ),
          AppSwitchField(
            title: l10n.tenantFacilityActiveLabel,
            value: _isActive,
            enabled: canEdit,
            onChanged: (bool value) {
              setState(() {
                _isActive = value;
              });
            },
          ),
          _SubmissionFailureBanner(),
        ],
      ),
    );

    return AppDialog(
      title: Text(
        isEditing
            ? l10n.tenantFacilityEditUnitTitle
            : l10n.tenantFacilityAddUnitTitle,
      ),
      scrollable: false,
      closeEnabled: canEdit,
      content: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ExcludeSemantics(
            excluding: showDialogLoadingOverlay,
            child: AbsorbPointer(
              absorbing: showDialogLoadingOverlay,
              child: SingleChildScrollView(
                child: formBody,
              ),
            ),
          ),
          if (showDialogLoadingOverlay)
            Positioned.fill(
              child: ColoredBox(
                color: theme.colorScheme.surface.withValues(alpha: 0.94),
                child: AppLoadingIndicator(
                  title: overlayTitle,
                  body: overlayBody,
                  expand: true,
                  semanticLabel: overlayTitle,
                ),
              ),
            ),
        ],
      ),
      actions: <Widget>[
        AppButton.close(
          leadingIcon: AppActionIcons.cancel,
          label: l10n.commonCancelActionLabel,
          enabled: canEdit,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton.primary(
          label: isEditing
              ? l10n.tenantFacilitySaveAction
              : l10n.tenantFacilityCreateAction,
          leadingIcon: Icons.save_outlined,
          isLoading: submission.isSubmitting || _checkingSimilarity,
          onPressed: _submit,
        ),
      ],
    );
  }

  (String?, String?) _resolveScopeIds() {
    final UnitProfile? editing = widget.unit;
    if (editing != null) {
      final String? tenantId = editing.tenantId.trim().isNotEmpty
          ? editing.tenantId.trim()
          : widget.snapshot.tenant?.id.trim();
      final String? facilityId = editing.facilityId?.trim().isNotEmpty == true
          ? editing.facilityId!.trim()
          : widget.snapshot.facility?.id.trim();
      return (tenantId, facilityId);
    }

    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final TenantFacilityUnitsListScope scope = tenantFacilityUnitsListScope(
      policy,
    );
    final String? tenantId = switch (scope) {
      TenantFacilityUnitsListScope.platform => _selectedTenantId?.trim(),
      TenantFacilityUnitsListScope.tenant ||
      TenantFacilityUnitsListScope.facility =>
        policy.tenantId ?? widget.snapshot.tenant?.id.trim(),
    };
    final String? facilityId = switch (scope) {
      TenantFacilityUnitsListScope.platform ||
      TenantFacilityUnitsListScope.tenant =>
        _selectedFacilityId?.trim(),
      TenantFacilityUnitsListScope.facility =>
        policy.facilityId ?? widget.snapshot.facility?.id.trim(),
    };
    return (tenantId, facilityId);
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true || _checkingSimilarity) {
      return;
    }

    final (String? tenantId, String? facilityId) = _resolveScopeIds();
    if (tenantId == null ||
        tenantId.isEmpty ||
        facilityId == null ||
        facilityId.isEmpty) {
      return;
    }

    final String? departmentId = _isCreate
        ? _selectedDepartmentId?.trim()
        : widget.unit?.departmentId?.trim();
    if (departmentId == null || departmentId.isEmpty) {
      return;
    }

    final String name = _nameController.text.trim();

    setState(() {
      _checkingSimilarity = true;
    });
    final bool canProceed;
    try {
      canProceed = await _guardAgainstDuplicates(
        tenantId: tenantId,
        facilityId: facilityId,
        departmentId: departmentId,
        name: name,
      );
    } finally {
      if (mounted) {
        setState(() {
          _checkingSimilarity = false;
        });
      }
    }
    if (!canProceed || !mounted) {
      return;
    }

    final UnitProfile? editing = widget.unit;
    final bool saved = await ref
        .read(tenantFacilitySetupSubmissionProvider.notifier)
        .saveUnit(
          id: editing?.mutationId,
          tenantId: tenantId,
          facilityId: facilityId,
          name: name,
          departmentId: departmentId,
          isActive: _isActive,
        );

    if (saved && mounted) {
      final UnitProfile? savedUnit =
          ref.read(tenantFacilitySetupSubmissionProvider).lastSavedUnit;
      Navigator.of(context).pop<Object?>(savedUnit ?? true);
      return;
    }
  }

  Future<bool> _guardAgainstDuplicates({
    required String tenantId,
    required String facilityId,
    required String departmentId,
    required String name,
  }) async {
    final UnitProfile? editing = widget.unit;

    final List<UnitProfile> existing = await _loadExistingUnits(
      tenantId: tenantId,
      facilityId: facilityId,
      departmentId: departmentId,
      name: name,
    );

    final Map<String, String> departmentNamesById = <String, String>{
      for (final DepartmentProfile department in _departmentOptions)
        department.id: department.name,
      for (final DepartmentProfile department in widget.snapshot.departments)
        department.id: department.name,
    };
    final String? departmentName = departmentNamesById[departmentId];

    final UnitDuplicateCheckResult result = checkUnitDuplicates(
      name: name,
      isActive: _isActive,
      existing: existing,
      departmentId: departmentId,
      departmentName: departmentName,
      departmentNamesById: departmentNamesById,
      excludeUnit: editing,
      excludeUnitId: editing?.id,
    );

    final bool exactNameConflict = result.exactNameConflict;
    final List<UnitSimilarityMatch> reviewMatches = result.similarMatches;

    if (!mounted) {
      return false;
    }

    setState(() {
      _nameErrorText = exactNameConflict
          ? context.l10n.tenantFacilityUnitNameAlreadyInUse
          : null;
    });

    final UnitSimilarityDialogResult decision = await showUnitSimilarityDialog(
      context,
      proposed: UnitSimilarityProposedValues(
        name: name,
        isActive: _isActive,
        departmentName: departmentName,
      ),
      matches: reviewMatches,
      allowProceed: !exactNameConflict,
    );
    if (!mounted) {
      return false;
    }

    switch (decision.action) {
      case UnitSimilarityAction.cancel:
        return false;
      case UnitSimilarityAction.useExisting:
        final UnitProfile? existingUnit = decision.selectedUnit;
        if (existingUnit != null) {
          Navigator.of(context).pop<Object?>(existingUnit);
        }
        return false;
      case UnitSimilarityAction.proceed:
        setState(() {
          _nameErrorText = null;
        });
        return true;
    }
  }

  Future<List<UnitProfile>> _loadExistingUnits({
    required String tenantId,
    required String facilityId,
    required String departmentId,
    required String name,
  }) async {
    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );
    final Set<String> seenIds = <String>{};
    final List<UnitProfile> units = <UnitProfile>[];

    Future<void> appendMatches({
      String? search,
      String? scopedDepartmentId,
    }) async {
      final Result<AppPage<UnitProfile>> result = await repository.listUnits(
        request: _lookupRequest,
        tenantId: tenantId,
        facilityId: facilityId,
        departmentId: scopedDepartmentId,
        search: search,
      );
      result.when(
        success: (AppPage<UnitProfile> page) {
          for (final UnitProfile unit in page.items) {
            if (seenIds.add(unit.id)) {
              units.add(unit);
            }
          }
        },
        failure: (_) {},
      );
    }

    // Bounded peer set only - backend confirm_similar remains authoritative.
    await appendMatches();

    return units;
  }
}

class _WardFormDialog extends ConsumerStatefulWidget {
  const _WardFormDialog({
    required this.snapshot,
    this.ward,
    this.tenantOptions = const <TenantProfile>[],
    this.facilityOptions = const <FacilityProfile>[],
    this.departmentOptions = const <DepartmentProfile>[],
  });

  final FacilitySetupSnapshot snapshot;
  final WardProfile? ward;
  final List<TenantProfile> tenantOptions;
  final List<FacilityProfile> facilityOptions;
  final List<DepartmentProfile> departmentOptions;

  @override
  ConsumerState<_WardFormDialog> createState() => _WardFormDialogState();
}

class _WardFormDialogState extends ConsumerState<_WardFormDialog> {
  static const AppPageRequest _lookupRequest = AppPageRequest(
    pageSize: PlatformAdminListConfig.pageSize,
  );

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late WardSetupType _type;
  late bool _isActive;
  String? _selectedTenantId;
  String? _selectedFacilityId;
  String? _selectedDepartmentId;
  List<TenantProfile> _tenantOptions = const <TenantProfile>[];
  List<FacilityProfile> _facilityOptions = const <FacilityProfile>[];
  List<DepartmentProfile> _departmentOptions = const <DepartmentProfile>[];
  bool _loadingOptions = false;
  bool _checkingSimilarity = false;
  String? _nameErrorText;

  bool get _isCreate => widget.ward == null;

  @override
  void initState() {
    super.initState();
    final WardProfile? ward = widget.ward;
    _nameController = TextEditingController(text: ward?.name);
    _type = ward?.type ?? WardSetupType.general;
    _isActive = ward?.isActive ?? true;
    _tenantOptions = widget.tenantOptions;
    _facilityOptions = widget.facilityOptions;
    _departmentOptions = widget.departmentOptions;
    _selectedTenantId = ward?.tenantId.trim().isNotEmpty == true
        ? ward!.tenantId.trim()
        : widget.snapshot.tenant?.id.trim();
    _selectedFacilityId = ward?.facilityId.trim().isNotEmpty == true
        ? ward!.facilityId.trim()
        : widget.snapshot.facility?.id.trim();
    _selectedDepartmentId = ward?.departmentId?.trim().isNotEmpty == true
        ? ward!.departmentId!.trim()
        : (_departmentOptions.length == 1
              ? _departmentOptions.first.id
              : null);
    unawaited(_ensureScopeOptions());
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _ensureScopeOptions() async {
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final TenantFacilityWardsListScope scope = tenantFacilityWardsListScope(
      policy,
    );

    setState(() {
      _loadingOptions = true;
    });

    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );

    if (_isCreate &&
        scope == TenantFacilityWardsListScope.platform &&
        _tenantOptions.isEmpty) {
      final Result<AppPage<TenantProfile>> tenantsResult = await repository
          .listTenants(request: _lookupRequest);
      if (!mounted) {
        return;
      }
      tenantsResult.when(
        success: (AppPage<TenantProfile> page) {
          _tenantOptions = page.items
              .where((TenantProfile tenant) => !tenant.isDeleted)
              .toList(growable: false);
        },
        failure: (_) {},
      );
    }

    final String? tenantIdForFacilities = switch (scope) {
      TenantFacilityWardsListScope.platform => _selectedTenantId,
      TenantFacilityWardsListScope.tenant =>
        policy.tenantId ?? widget.snapshot.tenant?.id,
      TenantFacilityWardsListScope.facility => null,
    };

    if (_isCreate &&
        tenantFacilityWardsShowsFacilityFilter(scope) &&
        (scope != TenantFacilityWardsListScope.platform ||
            (tenantIdForFacilities != null &&
                tenantIdForFacilities.isNotEmpty))) {
      final Result<AppPage<FacilityProfile>> facilitiesResult = await repository
          .listFacilities(
            request: _lookupRequest,
            tenantId: tenantIdForFacilities,
          );
      if (!mounted) {
        return;
      }
      facilitiesResult.when(
        success: (AppPage<FacilityProfile> page) {
          _facilityOptions = page.items
              .where((FacilityProfile facility) => !facility.isDeleted)
              .toList(growable: false);
        },
        failure: (_) {},
      );
    }

    await _loadDepartmentOptions(
      tenantId: switch (scope) {
        TenantFacilityWardsListScope.platform => _selectedTenantId,
        TenantFacilityWardsListScope.tenant ||
        TenantFacilityWardsListScope.facility =>
          policy.tenantId ?? widget.snapshot.tenant?.id,
      },
      facilityId: switch (scope) {
        TenantFacilityWardsListScope.platform ||
        TenantFacilityWardsListScope.tenant =>
          _selectedFacilityId,
        TenantFacilityWardsListScope.facility =>
          policy.facilityId ?? widget.snapshot.facility?.id,
      },
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _loadingOptions = false;
      _syncFacilitySelection();
      _syncDepartmentSelection();
    });
  }

  Future<void> _loadDepartmentOptions({
    String? tenantId,
    String? facilityId,
  }) async {
    final bool tenantScoped = tenantId != null && tenantId.isNotEmpty;
    final bool facilityScoped = facilityId != null && facilityId.isNotEmpty;
    if (!tenantScoped && !facilityScoped) {
      _departmentOptions = const <DepartmentProfile>[];
      return;
    }
    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );
    final Result<AppPage<DepartmentProfile>> result = await repository
        .listDepartments(
          request: _lookupRequest,
          tenantId: tenantScoped ? tenantId : null,
          facilityId: facilityScoped ? facilityId : null,
        );
    if (!mounted) {
      return;
    }
    result.when(
      success: (AppPage<DepartmentProfile> page) {
        _departmentOptions = page.items
            .where((DepartmentProfile department) => !department.isDeleted)
            .toList(growable: false);
      },
      failure: (_) {},
    );
  }

  void _syncFacilitySelection() {
    final String? facilityId = _selectedFacilityId;
    if (facilityId == null) {
      return;
    }
    final bool allowed = _facilityOptions.any(
      (FacilityProfile facility) =>
          facility.id == facilityId && !facility.isDeleted,
    );
    if (!allowed && _isCreate) {
      _selectedFacilityId = null;
    }
  }

  void _syncDepartmentSelection() {
    final String? departmentId = _selectedDepartmentId;
    if (departmentId == null) {
      return;
    }
    final bool allowed = _departmentOptions.any(
      (DepartmentProfile department) =>
          department.id == departmentId && !department.isDeleted,
    );
    if (!allowed) {
      _selectedDepartmentId = null;
    }
  }

  Future<void> _onTenantChanged(String? tenantId) async {
    setState(() {
      _selectedTenantId = tenantId;
      _selectedFacilityId = null;
      _selectedDepartmentId = null;
      _facilityOptions = const <FacilityProfile>[];
      _departmentOptions = const <DepartmentProfile>[];
      _loadingOptions = tenantId != null && tenantId.isNotEmpty;
    });
    if (tenantId == null || tenantId.isEmpty) {
      return;
    }
    final Result<AppPage<FacilityProfile>> result = await ref
        .read(tenantFacilityRepositoryProvider)
        .listFacilities(request: _lookupRequest, tenantId: tenantId);
    if (!mounted) {
      return;
    }
    result.when(
      success: (AppPage<FacilityProfile> page) {
        setState(() {
          _facilityOptions = page.items
              .where((FacilityProfile facility) => !facility.isDeleted)
              .toList(growable: false);
          _loadingOptions = false;
        });
      },
      failure: (_) {
        setState(() {
          _loadingOptions = false;
        });
      },
    );
  }

  Future<void> _onFacilityChanged(String? facilityId) async {
    setState(() {
      _selectedFacilityId = facilityId;
      _selectedDepartmentId = null;
      _departmentOptions = const <DepartmentProfile>[];
      _loadingOptions = facilityId != null && facilityId.isNotEmpty;
    });
    if (facilityId == null || facilityId.isEmpty) {
      setState(() {
        _loadingOptions = false;
      });
      return;
    }
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final String? tenantId = switch (tenantFacilityWardsListScope(policy)) {
      TenantFacilityWardsListScope.platform => _selectedTenantId,
      TenantFacilityWardsListScope.tenant ||
      TenantFacilityWardsListScope.facility =>
        policy.tenantId ?? widget.snapshot.tenant?.id,
    };
    await _loadDepartmentOptions(tenantId: tenantId, facilityId: facilityId);
    if (!mounted) {
      return;
    }
    setState(() {
      _loadingOptions = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppAccessPolicy policy = ref.watch(appAccessPolicyProvider);
    final TenantFacilityWardsListScope scope = tenantFacilityWardsListScope(
      policy,
    );
    final submission = ref.watch(tenantFacilitySetupSubmissionProvider);
    final bool isEditing = !_isCreate;
    final bool showLoadingOverlay =
        _loadingOptions || _checkingSimilarity || submission.isSubmitting;
    final bool canEdit = !showLoadingOverlay;
    final bool showTenantPicker =
        _isCreate && tenantFacilityWardsShowsTenantFilter(scope);
    final bool showFacilityPicker =
        _isCreate && tenantFacilityWardsShowsFacilityFilter(scope);
    final ThemeData theme = Theme.of(context);
    final String overlayTitle = _checkingSimilarity
        ? l10n.tenantFacilityWardSimilarityCheckingMessage
        : submission.isSubmitting
        ? l10n.commonLoadingTitle
        : l10n.commonLoadingCompactTitle;
    final String overlayBody = l10n.commonLoadingBody;

    final Widget? tenantField = showTenantPicker
        ? AppSelectField<String>.searchable(
            value: _selectedTenantId ?? _noneSelection,
            enabled: canEdit,
            labelText: l10n.profileTenantLabel,
            isRequired: true,
            options: <AppSelectOption<String>>[
              AppSelectOption<String>(
                value: _noneSelection,
                label: l10n.tenantFacilityNoSelectionLabel,
              ),
              for (final TenantProfile tenant in _tenantOptions)
                AppSelectOption<String>(
                  value: tenant.id,
                  label: tenant.name,
                  leadingIcon: const Icon(Icons.apartment_outlined),
                ),
            ],
            validator: (String? value) {
              if (value == null ||
                  value.isEmpty ||
                  value == _noneSelection) {
                return l10n.validationRequired;
              }
              return null;
            },
            onChanged: (String? value) {
              final String? next =
                  value == null || value == _noneSelection ? null : value;
              unawaited(_onTenantChanged(next));
            },
          )
        : null;
    final Widget? facilityField = showFacilityPicker
        ? AppSelectField<String>.searchable(
            value: _selectedFacilityId ?? _noneSelection,
            enabled:
                canEdit &&
                (!showTenantPicker ||
                    (_selectedTenantId != null &&
                        _selectedTenantId!.isNotEmpty)),
            labelText: l10n.profileFacilityLabel,
            isRequired: true,
            options: <AppSelectOption<String>>[
              AppSelectOption<String>(
                value: _noneSelection,
                label: l10n.tenantFacilityNoSelectionLabel,
              ),
              for (final FacilityProfile facility in _facilityOptions)
                AppSelectOption<String>(
                  value: facility.id,
                  label: facility.name,
                  leadingIcon: const Icon(Icons.local_hospital_outlined),
                ),
            ],
            validator: (String? value) {
              if (value == null ||
                  value.isEmpty ||
                  value == _noneSelection) {
                return l10n.validationRequired;
              }
              return null;
            },
            onChanged: (String? value) {
              final String? next =
                  value == null || value == _noneSelection ? null : value;
              unawaited(_onFacilityChanged(next));
            },
          )
        : null;

    final Widget departmentField = AppSelectField<String>.searchable(
      value: _selectedDepartmentId ?? _noneSelection,
      enabled: canEdit,
      labelText: l10n.tenantFacilityWardDepartmentLabel,
      options: <AppSelectOption<String>>[
        AppSelectOption<String>(
          value: _noneSelection,
          label: l10n.tenantFacilityNoSelectionLabel,
        ),
        for (final DepartmentProfile department in _departmentOptions)
          AppSelectOption<String>(
            value: department.id,
            label: department.name,
            leadingIcon: const Icon(Icons.domain_outlined),
          ),
      ],
      validator: tenantFacilityValidReferenceSelection(
        validIds: _departmentOptions
            .map((DepartmentProfile department) => department.id)
            .toList(growable: false),
        invalidMessage: l10n.tenantFacilityInvalidDepartmentSelection,
      ),
      onChanged: (String? value) {
        setState(() {
          _selectedDepartmentId =
              value == null || value == _noneSelection ? null : value;
        });
      },
    );

    final Widget formBody = Form(
      key: _formKey,
      child: AppFormSection(
        density: AppFormSectionDensity.compact,
        children: <Widget>[
          if (tenantField != null && facilityField != null)
            AppResponsiveFieldRow.two(
              gap: AppResponsiveFieldRowGap.form,
              left: tenantField,
              right: facilityField,
            )
          else if (tenantField != null)
            tenantField
          else if (facilityField != null)
            facilityField,
          AppResponsiveFieldRow.two(
            gap: AppResponsiveFieldRowGap.form,
            left: AppTextField(
              controller: _nameController,
              enabled: canEdit,
              labelText: l10n.tenantFacilityWardNameLabel,
              isRequired: true,
              textCapitalization: TextCapitalization.words,
              errorText: _nameErrorText,
              validator: AppValidators.requiredText(l10n.validationRequired),
              onChanged: (_) {
                if (_nameErrorText != null) {
                  setState(() {
                    _nameErrorText = null;
                  });
                }
              },
            ),
            right: AppSelectField<WardSetupType>(
              value: _type,
              enabled: canEdit,
              labelText: l10n.tenantFacilityWardTypeLabel,
              isRequired: true,
              options: <AppSelectOption<WardSetupType>>[
                for (final WardSetupType type in WardSetupType.values)
                  AppSelectOption<WardSetupType>(
                    value: type,
                    label: _wardTypeLabel(l10n, type),
                  ),
              ],
              onChanged: (WardSetupType? value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _type = value;
                });
              },
            ),
          ),
          departmentField,
          AppSwitchField(
            title: l10n.tenantFacilityActiveLabel,
            value: _isActive,
            enabled: canEdit,
            onChanged: (bool value) {
              setState(() {
                _isActive = value;
              });
            },
          ),
          _SubmissionFailureBanner(),
        ],
      ),
    );

    return AppDialog(
      title: Text(
        isEditing
            ? l10n.tenantFacilityEditWardTitle
            : l10n.tenantFacilityAddWardTitle,
      ),
      scrollable: false,
      closeEnabled: canEdit,
      content: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ExcludeSemantics(
            excluding: showLoadingOverlay,
            child: AbsorbPointer(
              absorbing: showLoadingOverlay,
              child: SingleChildScrollView(child: formBody),
            ),
          ),
          if (showLoadingOverlay)
            Positioned.fill(
              child: ColoredBox(
                color: theme.colorScheme.surface.withValues(alpha: 0.94),
                child: AppLoadingIndicator(
                  title: overlayTitle,
                  body: overlayBody,
                  expand: true,
                  semanticLabel: overlayTitle,
                ),
              ),
            ),
        ],
      ),
      actions: <Widget>[
        AppButton.close(
          leadingIcon: AppActionIcons.cancel,
          label: l10n.commonCancelActionLabel,
          enabled: canEdit,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton.primary(
          label: isEditing
              ? l10n.tenantFacilitySaveAction
              : l10n.tenantFacilityCreateAction,
          leadingIcon: Icons.save_outlined,
          isLoading: submission.isSubmitting || _checkingSimilarity,
          onPressed: _submit,
        ),
      ],
    );
  }

  (String?, String?) _resolveScopeIds() {
    final WardProfile? editing = widget.ward;
    if (editing != null) {
      final String? tenantId = editing.tenantId.trim().isNotEmpty
          ? editing.tenantId.trim()
          : widget.snapshot.tenant?.id.trim();
      final String? facilityId = editing.facilityId.trim().isNotEmpty
          ? editing.facilityId.trim()
          : widget.snapshot.facility?.id.trim();
      return (tenantId, facilityId);
    }

    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final TenantFacilityWardsListScope scope = tenantFacilityWardsListScope(
      policy,
    );
    final String? tenantId = switch (scope) {
      TenantFacilityWardsListScope.platform => _selectedTenantId?.trim(),
      TenantFacilityWardsListScope.tenant ||
      TenantFacilityWardsListScope.facility =>
        policy.tenantId ?? widget.snapshot.tenant?.id.trim(),
    };
    final String? facilityId = switch (scope) {
      TenantFacilityWardsListScope.platform ||
      TenantFacilityWardsListScope.tenant =>
        _selectedFacilityId?.trim(),
      TenantFacilityWardsListScope.facility =>
        policy.facilityId ?? widget.snapshot.facility?.id.trim(),
    };
    return (tenantId, facilityId);
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true || _checkingSimilarity) {
      return;
    }

    final (String? tenantId, String? facilityId) = _resolveScopeIds();
    if (tenantId == null ||
        tenantId.isEmpty ||
        facilityId == null ||
        facilityId.isEmpty) {
      return;
    }

    final String? departmentId = _selectedDepartmentId?.trim();
    final String name = _nameController.text.trim();

    setState(() {
      _checkingSimilarity = true;
    });
    final bool canProceed;
    try {
      canProceed = await _guardAgainstDuplicates(
        tenantId: tenantId,
        facilityId: facilityId,
        departmentId: departmentId,
        name: name,
      );
    } finally {
      if (mounted) {
        setState(() {
          _checkingSimilarity = false;
        });
      }
    }
    if (!canProceed || !mounted) {
      return;
    }

    final WardProfile? editing = widget.ward;
    final bool saved = await ref
        .read(tenantFacilitySetupSubmissionProvider.notifier)
        .saveWard(
          id: editing?.id,
          tenantId: tenantId,
          facilityId: facilityId,
          name: name,
          type: _type,
          departmentId: departmentId,
          isActive: _isActive,
        );

    if (saved && mounted) {
      final WardProfile? savedWard =
          ref.read(tenantFacilitySetupSubmissionProvider).lastSavedWard ??
          editing;
      Navigator.of(context).pop<Object?>(savedWard);
      return;
    }
  }

  Future<bool> _guardAgainstDuplicates({
    required String tenantId,
    required String facilityId,
    String? departmentId,
    required String name,
  }) async {
    final WardProfile? editing = widget.ward;

    final List<WardProfile> existing = await _loadExistingWards(
      tenantId: tenantId,
      facilityId: facilityId,
      departmentId: departmentId,
      name: name,
    );

    final Map<String, String> departmentNamesById = <String, String>{
      for (final DepartmentProfile department in _departmentOptions)
        department.id: department.name,
      for (final DepartmentProfile department in widget.snapshot.departments)
        department.id: department.name,
    };
    final String? departmentName =
        departmentId == null || departmentId.isEmpty
        ? null
        : departmentNamesById[departmentId];

    final WardDuplicateCheckResult result = checkWardDuplicates(
      name: name,
      type: _type,
      isActive: _isActive,
      existing: existing,
      departmentId: departmentId,
      departmentName: departmentName,
      departmentNamesById: departmentNamesById,
      excludeWard: editing,
      excludeWardId: editing?.id,
    );

    final bool exactNameConflict = result.exactNameConflict;
    final List<WardSimilarityMatch> reviewMatches = result.similarMatches;

    if (!mounted) {
      return false;
    }

    setState(() {
      _nameErrorText = exactNameConflict
          ? context.l10n.tenantFacilityWardNameAlreadyInUse
          : null;
    });

    final WardSimilarityDialogResult decision = await showWardSimilarityDialog(
      context,
      proposed: WardSimilarityProposedValues(
        name: name,
        type: _type,
        isActive: _isActive,
        departmentName: departmentName,
      ),
      matches: reviewMatches,
      allowProceed: !exactNameConflict,
    );
    if (!mounted) {
      return false;
    }

    switch (decision.action) {
      case WardSimilarityAction.cancel:
        return false;
      case WardSimilarityAction.useExisting:
        final WardProfile? existingWard = decision.selectedWard;
        if (existingWard != null) {
          Navigator.of(context).pop<Object?>(existingWard);
        }
        return false;
      case WardSimilarityAction.proceed:
        setState(() {
          _nameErrorText = null;
        });
        return true;
    }
  }

  Future<List<WardProfile>> _loadExistingWards({
    required String tenantId,
    required String facilityId,
    String? departmentId,
    required String name,
  }) async {
    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );
    final Set<String> seenIds = <String>{};
    final List<WardProfile> wards = <WardProfile>[];

    Future<void> appendMatches({
      String? search,
      String? scopedDepartmentId,
    }) async {
      final Result<AppPage<WardProfile>> result = await repository.listWards(
        request: _lookupRequest,
        tenantId: tenantId,
        facilityId: facilityId,
        departmentId: scopedDepartmentId,
        search: search,
      );
      result.when(
        success: (AppPage<WardProfile> page) {
          for (final WardProfile ward in page.items) {
            if (seenIds.add(ward.id)) {
              wards.add(ward);
            }
          }
        },
        failure: (_) {},
      );
    }

    // Bounded peer set only - backend confirm_similar remains authoritative.
    await appendMatches();

    return wards;
  }
}

class _RoomFormDialog extends ConsumerStatefulWidget {
  const _RoomFormDialog({
    required this.snapshot,
    this.room,
    this.tenantOptions = const <TenantProfile>[],
    this.facilityOptions = const <FacilityProfile>[],
    this.wardOptions = const <WardProfile>[],
  });

  final FacilitySetupSnapshot snapshot;
  final RoomProfile? room;
  final List<TenantProfile> tenantOptions;
  final List<FacilityProfile> facilityOptions;
  final List<WardProfile> wardOptions;

  @override
  ConsumerState<_RoomFormDialog> createState() => _RoomFormDialogState();
}

class _RoomFormDialogState extends ConsumerState<_RoomFormDialog> {
  static const AppPageRequest _lookupRequest = AppPageRequest(
    pageSize: PlatformAdminListConfig.pageSize,
  );

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _floorController;
  late String _wardId;
  String? _selectedTenantId;
  String? _selectedFacilityId;
  List<TenantProfile> _tenantOptions = const <TenantProfile>[];
  List<FacilityProfile> _facilityOptions = const <FacilityProfile>[];
  List<WardProfile> _wardOptions = const <WardProfile>[];
  bool _loadingOptions = false;
  bool _checkingSimilarity = false;
  String? _nameErrorText;

  bool get _isCreate => widget.room == null;

  @override
  void initState() {
    super.initState();
    final RoomProfile? room = widget.room;
    _nameController = TextEditingController(text: room?.name);
    _floorController = TextEditingController(text: room?.floor);
    _tenantOptions = widget.tenantOptions;
    _facilityOptions = widget.facilityOptions;
    _wardOptions = widget.wardOptions;
    _selectedTenantId = room?.tenantId.trim().isNotEmpty == true
        ? room!.tenantId.trim()
        : widget.snapshot.tenant?.id.trim();
    _selectedFacilityId = room?.facilityId.trim().isNotEmpty == true
        ? room!.facilityId.trim()
        : widget.snapshot.facility?.id.trim();
    _wardId = room?.wardId ??
        (_wardOptions.length == 1 ? _wardOptions.first.id : _noneSelection);
    unawaited(_ensureScopeOptions());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _floorController.dispose();
    super.dispose();
  }

  Future<void> _ensureScopeOptions() async {
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final TenantFacilityRoomsListScope scope = tenantFacilityRoomsListScope(
      policy,
    );

    setState(() {
      _loadingOptions = true;
    });

    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );

    if (_isCreate &&
        scope == TenantFacilityRoomsListScope.platform &&
        _tenantOptions.isEmpty) {
      final Result<AppPage<TenantProfile>> tenantsResult = await repository
          .listTenants(request: _lookupRequest);
      if (!mounted) {
        return;
      }
      tenantsResult.when(
        success: (AppPage<TenantProfile> page) {
          _tenantOptions = page.items
              .where((TenantProfile tenant) => !tenant.isDeleted)
              .toList(growable: false);
        },
        failure: (_) {},
      );
    }

    final String? tenantIdForFacilities = switch (scope) {
      TenantFacilityRoomsListScope.platform => _selectedTenantId,
      TenantFacilityRoomsListScope.tenant =>
        policy.tenantId ?? widget.snapshot.tenant?.id,
      TenantFacilityRoomsListScope.facility => null,
    };

    if (_isCreate &&
        tenantFacilityRoomsShowsFacilityFilter(scope) &&
        (scope != TenantFacilityRoomsListScope.platform ||
            (tenantIdForFacilities != null &&
                tenantIdForFacilities.isNotEmpty))) {
      final Result<AppPage<FacilityProfile>> facilitiesResult = await repository
          .listFacilities(
            request: _lookupRequest,
            tenantId: tenantIdForFacilities,
          );
      if (!mounted) {
        return;
      }
      facilitiesResult.when(
        success: (AppPage<FacilityProfile> page) {
          _facilityOptions = page.items
              .where((FacilityProfile facility) => !facility.isDeleted)
              .toList(growable: false);
        },
        failure: (_) {},
      );
    }

    await _loadWardOptions(
      tenantId: switch (scope) {
        TenantFacilityRoomsListScope.platform => _selectedTenantId,
        TenantFacilityRoomsListScope.tenant ||
        TenantFacilityRoomsListScope.facility =>
          policy.tenantId ?? widget.snapshot.tenant?.id,
      },
      facilityId: switch (scope) {
        TenantFacilityRoomsListScope.platform ||
        TenantFacilityRoomsListScope.tenant =>
          _selectedFacilityId,
        TenantFacilityRoomsListScope.facility =>
          policy.facilityId ?? widget.snapshot.facility?.id,
      },
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _loadingOptions = false;
      _syncFacilitySelection();
      _syncWardSelection();
    });
  }

  Future<void> _loadWardOptions({
    String? tenantId,
    String? facilityId,
  }) async {
    final bool tenantScoped = tenantId != null && tenantId.isNotEmpty;
    final bool facilityScoped = facilityId != null && facilityId.isNotEmpty;
    if (!tenantScoped && !facilityScoped) {
      _wardOptions = const <WardProfile>[];
      return;
    }
    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );
    final Result<AppPage<WardProfile>> result = await repository.listWards(
      request: _lookupRequest,
      tenantId: tenantScoped ? tenantId : null,
      facilityId: facilityScoped ? facilityId : null,
    );
    if (!mounted) {
      return;
    }
    result.when(
      success: (AppPage<WardProfile> page) {
        _wardOptions = page.items
            .where((WardProfile ward) => !ward.isDeleted)
            .toList(growable: false);
      },
      failure: (_) {},
    );
  }

  void _syncFacilitySelection() {
    final String? facilityId = _selectedFacilityId;
    if (facilityId == null) {
      return;
    }
    final bool allowed = _facilityOptions.any(
      (FacilityProfile facility) =>
          facility.id == facilityId && !facility.isDeleted,
    );
    if (!allowed && _isCreate) {
      _selectedFacilityId = null;
    }
  }

  void _syncWardSelection() {
    final String? wardId = _optionalSelection(_wardId);
    if (wardId == null) {
      return;
    }
    final bool allowed = _wardOptions.any(
      (WardProfile ward) => ward.id == wardId && !ward.isDeleted,
    );
    if (!allowed) {
      _wardId = _noneSelection;
    }
  }

  Future<void> _onTenantChanged(String? tenantId) async {
    setState(() {
      _selectedTenantId = tenantId;
      _selectedFacilityId = null;
      _wardId = _noneSelection;
      _facilityOptions = const <FacilityProfile>[];
      _wardOptions = const <WardProfile>[];
      _loadingOptions = tenantId != null && tenantId.isNotEmpty;
    });
    if (tenantId == null || tenantId.isEmpty) {
      return;
    }
    final Result<AppPage<FacilityProfile>> result = await ref
        .read(tenantFacilityRepositoryProvider)
        .listFacilities(request: _lookupRequest, tenantId: tenantId);
    if (!mounted) {
      return;
    }
    result.when(
      success: (AppPage<FacilityProfile> page) {
        setState(() {
          _facilityOptions = page.items
              .where((FacilityProfile facility) => !facility.isDeleted)
              .toList(growable: false);
          _loadingOptions = false;
        });
      },
      failure: (_) {
        setState(() {
          _loadingOptions = false;
        });
      },
    );
  }

  Future<void> _onFacilityChanged(String? facilityId) async {
    setState(() {
      _selectedFacilityId = facilityId;
      _wardId = _noneSelection;
      _wardOptions = const <WardProfile>[];
      _loadingOptions = facilityId != null && facilityId.isNotEmpty;
    });
    if (facilityId == null || facilityId.isEmpty) {
      setState(() {
        _loadingOptions = false;
      });
      return;
    }
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final String? tenantId = switch (tenantFacilityRoomsListScope(policy)) {
      TenantFacilityRoomsListScope.platform => _selectedTenantId,
      TenantFacilityRoomsListScope.tenant ||
      TenantFacilityRoomsListScope.facility =>
        policy.tenantId ?? widget.snapshot.tenant?.id,
    };
    await _loadWardOptions(tenantId: tenantId, facilityId: facilityId);
    if (!mounted) {
      return;
    }
    setState(() {
      _loadingOptions = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppAccessPolicy policy = ref.watch(appAccessPolicyProvider);
    final TenantFacilityRoomsListScope scope = tenantFacilityRoomsListScope(
      policy,
    );
    final submission = ref.watch(tenantFacilitySetupSubmissionProvider);
    final bool isEditing = !_isCreate;
    final bool showDialogLoadingOverlay =
        _loadingOptions || _checkingSimilarity || submission.isSubmitting;
    final bool canEdit = !showDialogLoadingOverlay;
    final bool showTenantPicker =
        _isCreate && tenantFacilityRoomsShowsTenantFilter(scope);
    final bool showFacilityPicker =
        _isCreate && tenantFacilityRoomsShowsFacilityFilter(scope);
    final ThemeData theme = Theme.of(context);
    final String overlayTitle;
    final String overlayBody;
    if (_checkingSimilarity) {
      overlayTitle = l10n.tenantFacilityRoomSimilarityCheckingMessage;
      overlayBody = l10n.tenantFacilityRoomSimilarityCheckingBody;
    } else if (submission.isSubmitting) {
      overlayTitle = l10n.tenantFacilityRoomSavingTitle;
      overlayBody = l10n.tenantFacilityRoomSavingBody;
    } else {
      overlayTitle = l10n.tenantFacilityRoomFormLoadingTitle;
      overlayBody = l10n.tenantFacilityRoomFormLoadingBody;
    }

    final Widget? tenantField = showTenantPicker
        ? AppSelectField<String>.searchable(
            value: _selectedTenantId ?? _noneSelection,
            enabled: canEdit,
            labelText: l10n.profileTenantLabel,
            isRequired: true,
            options: <AppSelectOption<String>>[
              AppSelectOption<String>(
                value: _noneSelection,
                label: l10n.tenantFacilityNoSelectionLabel,
              ),
              for (final TenantProfile tenant in _tenantOptions)
                AppSelectOption<String>(
                  value: tenant.id,
                  label: tenant.name,
                  leadingIcon: const Icon(Icons.apartment_outlined),
                ),
            ],
            validator: (String? value) {
              if (value == null ||
                  value.isEmpty ||
                  value == _noneSelection) {
                return l10n.validationRequired;
              }
              return null;
            },
            onChanged: (String? value) {
              final String? next =
                  value == null || value == _noneSelection ? null : value;
              unawaited(_onTenantChanged(next));
            },
          )
        : null;
    final Widget? facilityField = showFacilityPicker
        ? AppSelectField<String>.searchable(
            value: _selectedFacilityId ?? _noneSelection,
            enabled:
                canEdit &&
                (!showTenantPicker ||
                    (_selectedTenantId != null &&
                        _selectedTenantId!.isNotEmpty)),
            labelText: l10n.profileFacilityLabel,
            isRequired: true,
            options: <AppSelectOption<String>>[
              AppSelectOption<String>(
                value: _noneSelection,
                label: l10n.tenantFacilityNoSelectionLabel,
              ),
              for (final FacilityProfile facility in _facilityOptions)
                AppSelectOption<String>(
                  value: facility.id,
                  label: facility.name,
                  leadingIcon: const Icon(Icons.local_hospital_outlined),
                ),
            ],
            validator: (String? value) {
              if (value == null ||
                  value.isEmpty ||
                  value == _noneSelection) {
                return l10n.validationRequired;
              }
              return null;
            },
            onChanged: (String? value) {
              final String? next =
                  value == null || value == _noneSelection ? null : value;
              unawaited(_onFacilityChanged(next));
            },
          )
        : null;

    final Widget formBody = Form(
      key: _formKey,
      child: AppFormSection(
        density: AppFormSectionDensity.compact,
        children: <Widget>[
          if (tenantField != null && facilityField != null)
            AppResponsiveFieldRow.two(
              gap: AppResponsiveFieldRowGap.form,
              left: tenantField,
              right: facilityField,
            )
          else if (tenantField != null)
            tenantField
          else if (facilityField != null)
            facilityField,
          AppTextField(
            controller: _nameController,
            enabled: canEdit,
            labelText: l10n.tenantFacilityRoomNameLabel,
            isRequired: true,
            textCapitalization: TextCapitalization.words,
            errorText: _nameErrorText,
            validator: AppValidators.requiredText(l10n.validationRequired),
            onChanged: (_) {
              if (_nameErrorText != null) {
                setState(() {
                  _nameErrorText = null;
                });
              }
            },
          ),
          AppSelectField<String>.searchable(
            value: _wardId,
            enabled: canEdit,
            labelText: l10n.tenantFacilityRoomWardLabel,
            helperText: l10n.tenantFacilityRoomWardOptionalHint,
            options: <AppSelectOption<String>>[
              AppSelectOption<String>(
                value: _noneSelection,
                label: l10n.tenantFacilityRoomOutpatientLabel,
              ),
              for (final WardProfile ward in _wardOptions)
                AppSelectOption<String>(
                  value: ward.id,
                  label: ward.name,
                  leadingIcon: const Icon(Icons.local_hotel_outlined),
                ),
            ],
            validator: tenantFacilityValidReferenceSelection(
              validIds: _wardOptions
                  .map((WardProfile ward) => ward.id)
                  .toList(growable: false),
              invalidMessage: l10n.tenantFacilityInvalidWardSelection,
            ),
            onChanged: (String? value) {
              setState(() {
                _wardId = value ?? _noneSelection;
              });
            },
          ),
          AppTextField(
            controller: _floorController,
            enabled: canEdit,
            labelText: l10n.tenantFacilityRoomFloorLabel,
          ),
          _SubmissionFailureBanner(),
        ],
      ),
    );

    return AppDialog(
      title: Text(
        isEditing
            ? l10n.tenantFacilityEditRoomTitle
            : l10n.tenantFacilityAddRoomTitle,
      ),
      scrollable: false,
      closeEnabled: canEdit,
      content: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ExcludeSemantics(
            excluding: showDialogLoadingOverlay,
            child: AbsorbPointer(
              absorbing: showDialogLoadingOverlay,
              child: SingleChildScrollView(child: formBody),
            ),
          ),
          if (showDialogLoadingOverlay)
            Positioned.fill(
              child: ColoredBox(
                color: theme.colorScheme.surface.withValues(alpha: 0.94),
                child: AppLoadingIndicator(
                  title: overlayTitle,
                  body: overlayBody,
                  expand: true,
                  semanticLabel: overlayTitle,
                ),
              ),
            ),
        ],
      ),
      actions: <Widget>[
        AppButton.close(
          leadingIcon: AppActionIcons.cancel,
          label: l10n.commonCancelActionLabel,
          enabled: canEdit,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton.primary(
          label: isEditing
              ? l10n.tenantFacilitySaveAction
              : l10n.tenantFacilityCreateAction,
          leadingIcon: Icons.save_outlined,
          isLoading: submission.isSubmitting || _checkingSimilarity,
          onPressed: showDialogLoadingOverlay ? null : _submit,
        ),
      ],
    );
  }

  (String?, String?) _resolveScopeIds() {
    final RoomProfile? editing = widget.room;
    if (editing != null) {
      final String? tenantId = editing.tenantId.trim().isNotEmpty
          ? editing.tenantId.trim()
          : widget.snapshot.tenant?.id.trim();
      final String? facilityId = editing.facilityId.trim().isNotEmpty
          ? editing.facilityId.trim()
          : widget.snapshot.facility?.id.trim();
      return (tenantId, facilityId);
    }

    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final TenantFacilityRoomsListScope scope = tenantFacilityRoomsListScope(
      policy,
    );
    final String? tenantId = switch (scope) {
      TenantFacilityRoomsListScope.platform => _selectedTenantId?.trim(),
      TenantFacilityRoomsListScope.tenant ||
      TenantFacilityRoomsListScope.facility =>
        policy.tenantId ?? widget.snapshot.tenant?.id.trim(),
    };
    final String? facilityId = switch (scope) {
      TenantFacilityRoomsListScope.platform ||
      TenantFacilityRoomsListScope.tenant =>
        _selectedFacilityId?.trim(),
      TenantFacilityRoomsListScope.facility =>
        policy.facilityId ?? widget.snapshot.facility?.id.trim(),
    };
    return (tenantId, facilityId);
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true ||
        _checkingSimilarity ||
        _loadingOptions) {
      return;
    }

    final (String? tenantId, String? facilityId) = _resolveScopeIds();
    if (tenantId == null ||
        tenantId.isEmpty ||
        facilityId == null ||
        facilityId.isEmpty) {
      return;
    }

    final String? wardId = _optionalSelection(_wardId);
    final String name = _nameController.text.trim();
    final String floor = _floorController.text.trim();

    setState(() {
      _checkingSimilarity = true;
    });
    final bool canProceed;
    try {
      canProceed = await _guardAgainstDuplicates(
        tenantId: tenantId,
        facilityId: facilityId,
        wardId: wardId,
        name: name,
        floor: floor,
      );
    } finally {
      if (mounted) {
        setState(() {
          _checkingSimilarity = false;
        });
      }
    }
    if (!canProceed || !mounted) {
      return;
    }

    final RoomProfile? editing = widget.room;
    final bool saved = await ref
        .read(tenantFacilitySetupSubmissionProvider.notifier)
        .saveRoom(
          id: editing?.id,
          tenantId: tenantId,
          facilityId: facilityId,
          name: name,
          wardId: wardId,
          floor: floor,
        );

    if (saved && mounted) {
      final RoomProfile? savedRoom =
          ref.read(tenantFacilitySetupSubmissionProvider).lastSavedRoom;
      Navigator.of(context).pop<Object?>(savedRoom ?? true);
    }
  }

  Future<bool> _guardAgainstDuplicates({
    required String tenantId,
    required String facilityId,
    String? wardId,
    required String name,
    required String floor,
  }) async {
    final RoomProfile? editing = widget.room;

    final List<RoomProfile> existing = await _loadExistingRooms(
      tenantId: tenantId,
      facilityId: facilityId,
      wardId: wardId,
      name: name,
    );

    final Map<String, String> wardNamesById = <String, String>{
      for (final WardProfile ward in _wardOptions) ward.id: ward.name,
      for (final WardProfile ward in widget.snapshot.wards)
        ward.id: ward.name,
    };
    final String? wardName =
        wardId == null || wardId.isEmpty ? null : wardNamesById[wardId];

    final RoomDuplicateCheckResult result = checkRoomDuplicates(
      name: name,
      existing: existing,
      wardId: wardId,
      wardName: wardName,
      floor: floor,
      wardNamesById: wardNamesById,
      excludeRoom: editing,
      excludeRoomId: editing?.id,
    );

    final bool exactNameConflict = result.exactNameConflict;
    final List<RoomSimilarityMatch> reviewMatches = result.similarMatches;

    if (!mounted) {
      return false;
    }

    setState(() {
      _nameErrorText = exactNameConflict
          ? context.l10n.tenantFacilityRoomNameAlreadyInUse
          : null;
    });

    final RoomSimilarityDialogResult decision = await showRoomSimilarityDialog(
      context,
      proposed: RoomSimilarityProposedValues(
        name: name,
        wardName: wardName,
        floor: floor.isEmpty ? null : floor,
      ),
      matches: reviewMatches,
      allowProceed: !exactNameConflict,
    );
    if (!mounted) {
      return false;
    }

    switch (decision.action) {
      case RoomSimilarityAction.cancel:
        return false;
      case RoomSimilarityAction.useExisting:
        final RoomProfile? existingRoom = decision.selectedRoom;
        if (existingRoom != null) {
          Navigator.of(context).pop<Object?>(existingRoom);
        }
        return false;
      case RoomSimilarityAction.proceed:
        setState(() {
          _nameErrorText = null;
        });
        return true;
    }
  }

  Future<List<RoomProfile>> _loadExistingRooms({
    required String tenantId,
    required String facilityId,
    String? wardId,
    required String name,
  }) async {
    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );
    final Set<String> seenIds = <String>{};
    final List<RoomProfile> rooms = <RoomProfile>[];

    Future<void> appendMatches({
      String? search,
      String? scopedWardId,
    }) async {
      final Result<AppPage<RoomProfile>> result = await repository.listRooms(
        request: _lookupRequest,
        tenantId: tenantId,
        facilityId: facilityId,
        wardId: scopedWardId,
        search: search,
      );
      result.when(
        success: (AppPage<RoomProfile> page) {
          for (final RoomProfile room in page.items) {
            if (seenIds.add(room.id)) {
              rooms.add(room);
            }
          }
        },
        failure: (_) {},
      );
    }

    // Bounded peer set only - backend confirm_similar remains authoritative.
    await appendMatches();

    return rooms;
  }
}

class _BedFormDialog extends ConsumerStatefulWidget {
  const _BedFormDialog({
    required this.snapshot,
    this.bed,
    this.tenantOptions = const <TenantProfile>[],
    this.facilityOptions = const <FacilityProfile>[],
    this.wardOptions = const <WardProfile>[],
    this.roomOptions = const <RoomProfile>[],
  });

  final FacilitySetupSnapshot snapshot;
  final BedProfile? bed;
  final List<TenantProfile> tenantOptions;
  final List<FacilityProfile> facilityOptions;
  final List<WardProfile> wardOptions;
  final List<RoomProfile> roomOptions;

  @override
  ConsumerState<_BedFormDialog> createState() => _BedFormDialogState();
}

class _BedFormDialogState extends ConsumerState<_BedFormDialog> {
  static const AppPageRequest _lookupRequest = AppPageRequest(
    pageSize: PlatformAdminListConfig.pageSize,
  );

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelController;
  late String _wardId;
  late String _roomId;
  late BedSetupStatus _status;
  String? _selectedTenantId;
  String? _selectedFacilityId;
  List<TenantProfile> _tenantOptions = const <TenantProfile>[];
  List<FacilityProfile> _facilityOptions = const <FacilityProfile>[];
  List<WardProfile> _wardOptions = const <WardProfile>[];
  List<RoomProfile> _roomOptions = const <RoomProfile>[];
  bool _loadingOptions = false;
  bool _checkingSimilarity = false;
  String? _labelErrorText;

  bool get _isCreate => widget.bed == null;

  @override
  void initState() {
    super.initState();
    final BedProfile? bed = widget.bed;
    _labelController = TextEditingController(text: bed?.label);
    _wardId = bed?.wardId ?? _noneSelection;
    _roomId = bed?.roomId ?? _noneSelection;
    _status = bed?.status ?? BedSetupStatus.available;
    _tenantOptions = widget.tenantOptions;
    _facilityOptions = widget.facilityOptions;
    _wardOptions = widget.wardOptions;
    _roomOptions = widget.roomOptions;
    _selectedTenantId = bed?.tenantId.trim().isNotEmpty == true
        ? bed!.tenantId.trim()
        : widget.snapshot.tenant?.id.trim();
    _selectedFacilityId = bed?.facilityId.trim().isNotEmpty == true
        ? bed!.facilityId.trim()
        : widget.snapshot.facility?.id.trim();
    unawaited(_ensureScopeOptions());
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  List<RoomProfile> get _roomsForSelectedWard {
    final String? wardId = _optionalSelection(_wardId);
    if (wardId == null) {
      return const <RoomProfile>[];
    }
    return _roomOptions
        .where(
          (RoomProfile room) =>
              !room.isDeleted && (room.wardId?.trim() ?? '') == wardId,
        )
        .toList(growable: false);
  }

  Future<void> _ensureScopeOptions() async {
    setState(() {
      _loadingOptions = true;
    });

    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final TenantFacilityBedsListScope scope = tenantFacilityBedsListScope(
      policy,
    );
    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );

    if (_isCreate &&
        scope == TenantFacilityBedsListScope.platform &&
        _tenantOptions.isEmpty) {
      final Result<AppPage<TenantProfile>> tenantsResult = await repository
          .listTenants(request: _lookupRequest);
      if (!mounted) {
        return;
      }
      tenantsResult.when(
        success: (AppPage<TenantProfile> page) {
          _tenantOptions = page.items
              .where((TenantProfile tenant) => !tenant.isDeleted)
              .toList(growable: false);
        },
        failure: (_) {},
      );
    }

    final String? tenantIdForFacilities = switch (scope) {
      TenantFacilityBedsListScope.platform => _selectedTenantId,
      TenantFacilityBedsListScope.tenant =>
        policy.tenantId ?? widget.snapshot.tenant?.id,
      TenantFacilityBedsListScope.facility => null,
    };

    if (_isCreate &&
        tenantFacilityBedsShowsFacilityFilter(scope) &&
        (scope != TenantFacilityBedsListScope.platform ||
            (tenantIdForFacilities != null &&
                tenantIdForFacilities.isNotEmpty))) {
      final Result<AppPage<FacilityProfile>> facilitiesResult = await repository
          .listFacilities(
            request: _lookupRequest,
            tenantId: tenantIdForFacilities,
          );
      if (!mounted) {
        return;
      }
      facilitiesResult.when(
        success: (AppPage<FacilityProfile> page) {
          _facilityOptions = page.items
              .where((FacilityProfile facility) => !facility.isDeleted)
              .toList(growable: false);
        },
        failure: (_) {},
      );
    }

    await _loadWardOptions(
      tenantId: switch (scope) {
        TenantFacilityBedsListScope.platform => _selectedTenantId,
        TenantFacilityBedsListScope.tenant ||
        TenantFacilityBedsListScope.facility =>
          policy.tenantId ?? widget.snapshot.tenant?.id,
      },
      facilityId: switch (scope) {
        TenantFacilityBedsListScope.platform ||
        TenantFacilityBedsListScope.tenant =>
          _selectedFacilityId,
        TenantFacilityBedsListScope.facility =>
          policy.facilityId ?? widget.snapshot.facility?.id,
      },
    );

    await _loadRoomOptions(
      tenantId: switch (scope) {
        TenantFacilityBedsListScope.platform => _selectedTenantId,
        TenantFacilityBedsListScope.tenant ||
        TenantFacilityBedsListScope.facility =>
          policy.tenantId ?? widget.snapshot.tenant?.id,
      },
      facilityId: switch (scope) {
        TenantFacilityBedsListScope.platform ||
        TenantFacilityBedsListScope.tenant =>
          _selectedFacilityId,
        TenantFacilityBedsListScope.facility =>
          policy.facilityId ?? widget.snapshot.facility?.id,
      },
      wardId: _optionalSelection(_wardId),
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _loadingOptions = false;
      _syncFacilitySelection();
      _syncWardSelection();
      _syncRoomSelection();
    });
  }

  Future<void> _loadWardOptions({
    String? tenantId,
    String? facilityId,
  }) async {
    final bool tenantScoped = tenantId != null && tenantId.isNotEmpty;
    final bool facilityScoped = facilityId != null && facilityId.isNotEmpty;
    if (!tenantScoped && !facilityScoped) {
      _wardOptions = const <WardProfile>[];
      return;
    }
    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );
    final Result<AppPage<WardProfile>> result = await repository.listWards(
      request: _lookupRequest,
      tenantId: tenantScoped ? tenantId : null,
      facilityId: facilityScoped ? facilityId : null,
    );
    if (!mounted) {
      return;
    }
    result.when(
      success: (AppPage<WardProfile> page) {
        _wardOptions = page.items
            .where((WardProfile ward) => !ward.isDeleted)
            .toList(growable: false);
      },
      failure: (_) {},
    );
  }

  Future<void> _loadRoomOptions({
    String? tenantId,
    String? facilityId,
    String? wardId,
  }) async {
    final bool tenantScoped = tenantId != null && tenantId.isNotEmpty;
    final bool facilityScoped = facilityId != null && facilityId.isNotEmpty;
    if (!tenantScoped && !facilityScoped) {
      _roomOptions = const <RoomProfile>[];
      return;
    }
    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );
    final Result<AppPage<RoomProfile>> result = await repository.listRooms(
      request: _lookupRequest,
      tenantId: tenantScoped ? tenantId : null,
      facilityId: facilityScoped ? facilityId : null,
      wardId: wardId?.trim().isNotEmpty == true ? wardId : null,
    );
    if (!mounted) {
      return;
    }
    result.when(
      success: (AppPage<RoomProfile> page) {
        _roomOptions = page.items
            .where((RoomProfile room) => !room.isDeleted)
            .toList(growable: false);
      },
      failure: (_) {},
    );
  }

  void _syncFacilitySelection() {
    final String? facilityId = _selectedFacilityId;
    if (facilityId == null) {
      return;
    }
    final bool allowed = _facilityOptions.any(
      (FacilityProfile facility) =>
          facility.id == facilityId && !facility.isDeleted,
    );
    if (!allowed) {
      _selectedFacilityId = null;
    }
  }

  void _syncWardSelection() {
    final String? wardId = _optionalSelection(_wardId);
    if (wardId == null) {
      return;
    }
    final bool allowed = _wardOptions.any(
      (WardProfile ward) => ward.id == wardId && !ward.isDeleted,
    );
    if (!allowed) {
      _wardId = _noneSelection;
    }
  }

  void _syncRoomSelection() {
    final String? roomId = _optionalSelection(_roomId);
    if (roomId == null) {
      return;
    }
    final bool allowed = _roomsForSelectedWard.any(
      (RoomProfile room) => room.id == roomId,
    );
    if (!allowed) {
      _roomId = _noneSelection;
    }
  }

  Future<void> _onTenantChanged(String? tenantId) async {
    setState(() {
      _selectedTenantId = tenantId;
      _selectedFacilityId = null;
      _wardId = _noneSelection;
      _roomId = _noneSelection;
      _facilityOptions = const <FacilityProfile>[];
      _wardOptions = const <WardProfile>[];
      _roomOptions = const <RoomProfile>[];
      _loadingOptions = tenantId != null && tenantId.isNotEmpty;
    });
    if (tenantId == null || tenantId.isEmpty) {
      return;
    }
    final Result<AppPage<FacilityProfile>> result = await ref
        .read(tenantFacilityRepositoryProvider)
        .listFacilities(request: _lookupRequest, tenantId: tenantId);
    if (!mounted) {
      return;
    }
    result.when(
      success: (AppPage<FacilityProfile> page) {
        setState(() {
          _facilityOptions = page.items
              .where((FacilityProfile facility) => !facility.isDeleted)
              .toList(growable: false);
          _loadingOptions = false;
        });
      },
      failure: (_) {
        setState(() {
          _loadingOptions = false;
        });
      },
    );
  }

  Future<void> _onFacilityChanged(String? facilityId) async {
    setState(() {
      _selectedFacilityId = facilityId;
      _wardId = _noneSelection;
      _roomId = _noneSelection;
      _wardOptions = const <WardProfile>[];
      _roomOptions = const <RoomProfile>[];
      _loadingOptions = facilityId != null && facilityId.isNotEmpty;
    });
    if (facilityId == null || facilityId.isEmpty) {
      setState(() {
        _loadingOptions = false;
      });
      return;
    }
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final String? tenantId = switch (tenantFacilityBedsListScope(policy)) {
      TenantFacilityBedsListScope.platform => _selectedTenantId,
      TenantFacilityBedsListScope.tenant ||
      TenantFacilityBedsListScope.facility =>
        policy.tenantId ?? widget.snapshot.tenant?.id,
    };
    await _loadWardOptions(tenantId: tenantId, facilityId: facilityId);
    if (!mounted) {
      return;
    }
    setState(() {
      _loadingOptions = false;
    });
  }

  Future<void> _onWardChanged(String? wardId) async {
    setState(() {
      _wardId = wardId ?? _noneSelection;
      _roomId = _noneSelection;
      _loadingOptions = wardId != null && wardId.isNotEmpty;
    });
    if (wardId == null || wardId.isEmpty) {
      setState(() {
        _roomOptions = const <RoomProfile>[];
        _loadingOptions = false;
      });
      return;
    }
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final TenantFacilityBedsListScope scope = tenantFacilityBedsListScope(
      policy,
    );
    await _loadRoomOptions(
      tenantId: switch (scope) {
        TenantFacilityBedsListScope.platform => _selectedTenantId,
        TenantFacilityBedsListScope.tenant ||
        TenantFacilityBedsListScope.facility =>
          policy.tenantId ?? widget.snapshot.tenant?.id,
      },
      facilityId: switch (scope) {
        TenantFacilityBedsListScope.platform ||
        TenantFacilityBedsListScope.tenant =>
          _selectedFacilityId,
        TenantFacilityBedsListScope.facility =>
          policy.facilityId ?? widget.snapshot.facility?.id,
      },
      wardId: wardId,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _loadingOptions = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppAccessPolicy policy = ref.watch(appAccessPolicyProvider);
    final TenantFacilityBedsListScope scope = tenantFacilityBedsListScope(
      policy,
    );
    final submission = ref.watch(tenantFacilitySetupSubmissionProvider);
    final bool isEditing = !_isCreate;
    final bool showTenantPicker =
        _isCreate && tenantFacilityBedsShowsTenantFilter(scope);
    final bool showFacilityPicker =
        _isCreate && tenantFacilityBedsShowsFacilityFilter(scope);
    final ThemeData theme = Theme.of(context);
    final List<RoomProfile> rooms = _roomsForSelectedWard;
    final bool showLoadingOverlay =
        _loadingOptions || _checkingSimilarity || submission.isSubmitting;
    final bool canEdit = !showLoadingOverlay;
    final String overlayTitle = _checkingSimilarity
        ? l10n.tenantFacilityBedSimilarityCheckingMessage
        : submission.isSubmitting
        ? l10n.commonLoadingTitle
        : l10n.tenantFacilityBedFormLoadingTitle;
    final String overlayBody = _checkingSimilarity
        ? l10n.tenantFacilityBedSimilarityCheckingBody
        : submission.isSubmitting
        ? l10n.commonLoadingBody
        : l10n.tenantFacilityBedFormLoadingBody;

    final Widget? tenantField = showTenantPicker
        ? AppSelectField<String>.searchable(
            value: _selectedTenantId ?? _noneSelection,
            enabled: canEdit,
            labelText: l10n.profileTenantLabel,
            isRequired: true,
            options: <AppSelectOption<String>>[
              AppSelectOption<String>(
                value: _noneSelection,
                label: l10n.tenantFacilityNoSelectionLabel,
              ),
              for (final TenantProfile tenant in _tenantOptions)
                AppSelectOption<String>(
                  value: tenant.id,
                  label: tenant.name,
                  leadingIcon: const Icon(Icons.apartment_outlined),
                ),
            ],
            validator: (String? value) {
              if (value == null ||
                  value.isEmpty ||
                  value == _noneSelection) {
                return l10n.validationRequired;
              }
              return null;
            },
            onChanged: (String? value) {
              final String? next =
                  value == null || value == _noneSelection ? null : value;
              unawaited(_onTenantChanged(next));
            },
          )
        : null;
    final Widget? facilityField = showFacilityPicker
        ? AppSelectField<String>.searchable(
            value: _selectedFacilityId ?? _noneSelection,
            enabled:
                canEdit &&
                (!showTenantPicker ||
                    (_selectedTenantId != null &&
                        _selectedTenantId!.isNotEmpty)),
            labelText: l10n.profileFacilityLabel,
            isRequired: true,
            options: <AppSelectOption<String>>[
              AppSelectOption<String>(
                value: _noneSelection,
                label: l10n.tenantFacilityNoSelectionLabel,
              ),
              for (final FacilityProfile facility in _facilityOptions)
                AppSelectOption<String>(
                  value: facility.id,
                  label: facility.name,
                  leadingIcon: const Icon(Icons.local_hospital_outlined),
                ),
            ],
            validator: (String? value) {
              if (value == null ||
                  value.isEmpty ||
                  value == _noneSelection) {
                return l10n.validationRequired;
              }
              return null;
            },
            onChanged: (String? value) {
              final String? next =
                  value == null || value == _noneSelection ? null : value;
              unawaited(_onFacilityChanged(next));
            },
          )
        : null;

    final Widget wardField = AppSelectField<String>.searchable(
      value: _wardId,
      enabled: canEdit && (_isCreate ? _wardOptions.isNotEmpty : true),
      labelText: l10n.tenantFacilityBedWardLabel,
      isRequired: true,
      options: <AppSelectOption<String>>[
        AppSelectOption<String>(
          value: _noneSelection,
          label: l10n.tenantFacilityNoSelectionLabel,
        ),
        for (final WardProfile ward in _wardOptions)
          AppSelectOption<String>(
            value: ward.id,
            label: ward.name,
            leadingIcon: const Icon(Icons.local_hospital_outlined),
          ),
      ],
      validator: (String? value) {
        final String? requiredError = tenantFacilityRequiredSelection(l10n)(
          value,
        );
        if (requiredError != null) {
          return requiredError;
        }
        return tenantFacilityValidReferenceSelection(
          validIds: _wardOptions
              .map((WardProfile ward) => ward.id)
              .toList(growable: false),
          invalidMessage: l10n.tenantFacilityInvalidWardSelection,
        )(value);
      },
      onChanged: (String? value) {
        final String? next =
            value == null || value == _noneSelection ? null : value;
        unawaited(_onWardChanged(next));
      },
    );

    final Widget roomField = AppSelectField<String>.searchable(
      value: _roomId,
      enabled: canEdit && _optionalSelection(_wardId) != null,
      labelText: l10n.tenantFacilityBedRoomLabel,
      options: <AppSelectOption<String>>[
        AppSelectOption<String>(
          value: _noneSelection,
          label: l10n.tenantFacilityNoSelectionLabel,
        ),
        for (final RoomProfile room in rooms)
          AppSelectOption<String>(
            value: room.id,
            label: room.name,
            leadingIcon: const Icon(Icons.meeting_room_outlined),
          ),
      ],
      validator: tenantFacilityValidReferenceSelection(
        validIds: rooms.map((RoomProfile room) => room.id).toList(growable: false),
        invalidMessage: l10n.tenantFacilityInvalidRoomSelection,
      ),
      onChanged: (String? value) {
        setState(() {
          _roomId = value ?? _noneSelection;
        });
      },
    );

    final Widget form = Form(
      key: _formKey,
      child: AppFormSection(
        density: AppFormSectionDensity.compact,
        children: <Widget>[
          if (tenantField != null && facilityField != null)
            AppResponsiveFieldRow.two(
              gap: AppResponsiveFieldRowGap.form,
              left: tenantField,
              right: facilityField,
            )
          else if (tenantField != null)
            tenantField
          else if (facilityField != null)
            facilityField,
          AppTextField(
            controller: _labelController,
            enabled: canEdit,
            labelText: l10n.tenantFacilityBedLabelLabel,
            isRequired: true,
            textCapitalization: TextCapitalization.characters,
            errorText: _labelErrorText,
            validator: AppValidators.requiredText(l10n.validationRequired),
            onChanged: (_) {
              if (_labelErrorText != null) {
                setState(() {
                  _labelErrorText = null;
                });
              }
            },
          ),
          AppResponsiveFieldRow.two(
            gap: AppResponsiveFieldRowGap.form,
            left: wardField,
            right: roomField,
          ),
          AppSelectField<BedSetupStatus>(
            value: _status,
            enabled: canEdit,
            labelText: l10n.tenantFacilityBedStatusLabel,
            isRequired: true,
            options: <AppSelectOption<BedSetupStatus>>[
              for (final BedSetupStatus status in BedSetupStatus.values)
                AppSelectOption<BedSetupStatus>(
                  value: status,
                  label: _bedStatusLabel(l10n, status),
                ),
            ],
            onChanged: (BedSetupStatus? value) {
              if (value == null) {
                return;
              }
              setState(() {
                _status = value;
              });
            },
          ),
          _SubmissionFailureBanner(),
        ],
      ),
    );

    return AppDialog(
      title: Text(
        isEditing
            ? l10n.tenantFacilityEditBedTitle
            : l10n.tenantFacilityAddBedTitle,
      ),
      scrollable: true,
      closeEnabled: canEdit,
      content: Stack(
        children: <Widget>[
          ExcludeSemantics(
            excluding: showLoadingOverlay,
            child: AbsorbPointer(absorbing: showLoadingOverlay, child: form),
          ),
          if (showLoadingOverlay)
            Positioned.fill(
              child: ColoredBox(
                color: theme.colorScheme.surface.withValues(alpha: 0.94),
                child: AppLoadingIndicator(
                  title: overlayTitle,
                  body: overlayBody,
                  expand: true,
                  semanticLabel: overlayTitle,
                ),
              ),
            ),
        ],
      ),
      actions: <Widget>[
        AppButton.close(
          leadingIcon: AppActionIcons.cancel,
          label: l10n.commonCancelActionLabel,
          enabled: canEdit,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton.primary(
          label: isEditing
              ? l10n.tenantFacilitySaveAction
              : l10n.tenantFacilityCreateAction,
          leadingIcon: Icons.save_outlined,
          isLoading: submission.isSubmitting || _checkingSimilarity,
          onPressed: _submit,
        ),
      ],
    );
  }

  (String?, String?) _resolveScopeIds() {
    final BedProfile? editing = widget.bed;
    if (editing != null) {
      final String? tenantId = editing.tenantId.trim().isNotEmpty
          ? editing.tenantId.trim()
          : widget.snapshot.tenant?.id.trim();
      final String? facilityId = editing.facilityId.trim().isNotEmpty
          ? editing.facilityId.trim()
          : widget.snapshot.facility?.id.trim();
      return (tenantId, facilityId);
    }

    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    final TenantFacilityBedsListScope scope = tenantFacilityBedsListScope(
      policy,
    );
    final String? tenantId = switch (scope) {
      TenantFacilityBedsListScope.platform => _selectedTenantId?.trim(),
      TenantFacilityBedsListScope.tenant ||
      TenantFacilityBedsListScope.facility =>
        policy.tenantId ?? widget.snapshot.tenant?.id.trim(),
    };
    final String? facilityId = switch (scope) {
      TenantFacilityBedsListScope.platform ||
      TenantFacilityBedsListScope.tenant =>
        _selectedFacilityId?.trim(),
      TenantFacilityBedsListScope.facility =>
        policy.facilityId ?? widget.snapshot.facility?.id.trim(),
    };
    return (tenantId, facilityId);
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true || _checkingSimilarity) {
      return;
    }

    final (String? tenantId, String? facilityId) = _resolveScopeIds();
    if (tenantId == null ||
        tenantId.isEmpty ||
        facilityId == null ||
        facilityId.isEmpty) {
      return;
    }

    final String? wardId = _optionalSelection(_wardId);
    if (wardId == null || wardId.isEmpty) {
      return;
    }

    final String label = _labelController.text.trim();
    final String? roomId = _optionalSelection(_roomId);

    setState(() {
      _checkingSimilarity = true;
    });
    final bool canProceed;
    try {
      canProceed = await _guardAgainstDuplicates(
        tenantId: tenantId,
        facilityId: facilityId,
        wardId: wardId,
        roomId: roomId,
        label: label,
      );
    } finally {
      if (mounted) {
        setState(() {
          _checkingSimilarity = false;
        });
      }
    }
    if (!canProceed || !mounted) {
      return;
    }

    final BedProfile? editing = widget.bed;
    final bool saved = await ref
        .read(tenantFacilitySetupSubmissionProvider.notifier)
        .saveBed(
          id: editing?.id,
          tenantId: tenantId,
          facilityId: facilityId,
          wardId: wardId,
          label: label,
          status: _status,
          roomId: roomId,
        );

    if (saved && mounted) {
      final BedProfile? savedBed =
          ref.read(tenantFacilitySetupSubmissionProvider).lastSavedBed;
      Navigator.of(context).pop<Object?>(savedBed);
    }
  }

  Future<bool> _guardAgainstDuplicates({
    required String tenantId,
    required String facilityId,
    required String wardId,
    required String? roomId,
    required String label,
  }) async {
    final BedProfile? editing = widget.bed;
    final String normalizedRoomId = roomId?.trim() ?? '';
    final String editingRoomId = editing?.roomId?.trim() ?? '';

    if (!_isCreate &&
        editing != null &&
        normalizeBedLabel(label) == normalizeBedLabel(editing.label) &&
        wardId == editing.wardId &&
        normalizedRoomId == editingRoomId &&
        _status == editing.status) {
      setState(() {
        _labelErrorText = null;
      });
      return true;
    }

    final List<BedProfile> existing = await _loadExistingBeds(
      tenantId: tenantId,
      facilityId: facilityId,
      wardId: wardId,
      label: label,
    );

    final Map<String, String> wardNamesById = <String, String>{
      for (final WardProfile ward in _wardOptions) ward.id: ward.name,
      for (final WardProfile ward in widget.wardOptions) ward.id: ward.name,
      for (final WardProfile ward in widget.snapshot.wards)
        ward.id: ward.name,
    };
    final Map<String, String> roomNamesById = <String, String>{
      for (final RoomProfile room in _roomOptions) room.id: room.name,
      for (final RoomProfile room in widget.roomOptions) room.id: room.name,
      for (final RoomProfile room in widget.snapshot.rooms) room.id: room.name,
    };
    final String? wardName = wardNamesById[wardId];
    final String? roomName = normalizedRoomId.isEmpty
        ? null
        : roomNamesById[normalizedRoomId];

    final BedDuplicateCheckResult result = checkBedDuplicates(
      label: label,
      status: _status,
      existing: existing,
      wardId: wardId,
      roomId: normalizedRoomId.isEmpty ? null : normalizedRoomId,
      wardName: wardName,
      roomName: roomName,
      wardNamesById: wardNamesById,
      roomNamesById: roomNamesById,
      excludeBed: editing,
      excludeBedId: editing?.id,
    );

    if (!mounted) {
      return false;
    }

    setState(() {
      _labelErrorText = result.exactLabelConflict
          ? context.l10n.tenantFacilityBedLabelAlreadyInUse
          : null;
    });

    final BedSimilarityDialogResult decision = await showBedSimilarityDialog(
      context,
      proposed: BedSimilarityProposedValues(
        label: label,
        statusLabel: tenantFacilityBedStatusLabel(context.l10n, _status),
        wardName: wardName,
        roomName: roomName,
      ),
      matches: result.similarMatches,
      allowProceed: !result.exactLabelConflict,
    );
    if (!mounted) {
      return false;
    }

    switch (decision.action) {
      case BedSimilarityAction.cancel:
        return false;
      case BedSimilarityAction.useExisting:
        final BedProfile? existingBed = decision.selectedBed;
        if (existingBed != null) {
          Navigator.of(context).pop<Object?>(existingBed);
        }
        return false;
      case BedSimilarityAction.proceed:
        setState(() {
          _labelErrorText = null;
        });
        return true;
    }
  }

  Future<List<BedProfile>> _loadExistingBeds({
    required String tenantId,
    required String facilityId,
    required String wardId,
    required String label,
  }) async {
    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );
    final Set<String> seenIds = <String>{};
    final List<BedProfile> beds = <BedProfile>[];

    Future<void> appendMatches({
      String? search,
      String? scopedWardId,
    }) async {
      final Result<AppPage<BedProfile>> result = await repository.listBeds(
        request: _lookupRequest,
        tenantId: tenantId,
        facilityId: facilityId,
        wardId: scopedWardId,
        search: search,
      );
      result.when(
        success: (AppPage<BedProfile> page) {
          for (final BedProfile bed in page.items) {
            if (seenIds.add(bed.id)) {
              beds.add(bed);
            }
          }
        },
        failure: (_) {},
      );
    }

    // Bounded peer set only - backend confirm_similar remains authoritative.
    await appendMatches();

    return beds;
  }
}

class _SubmissionFailureBanner extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppFailure? failure = ref.watch(
      tenantFacilitySetupSubmissionProvider.select((state) => state.failure),
    );
    if (failure == null) {
      return const SizedBox.shrink();
    }

    return AppFormInformationBanner.failure(context: context, failure: failure);
  }
}

Future<void> _openDepartmentDialog(
  BuildContext context,
  FacilitySetupSnapshot snapshot, {
  DepartmentProfile? department,
  List<TenantProfile> tenantOptions = const <TenantProfile>[],
  List<FacilityProfile> facilityOptions = const <FacilityProfile>[],
}) async {
  final Object? result = await showAppDialog<Object?>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DepartmentFormDialog(
      snapshot: snapshot,
      department: department,
      tenantOptions: tenantOptions,
      facilityOptions: facilityOptions,
    ),
  );
  if (!context.mounted || result is! DepartmentProfile) {
    return;
  }
  await _openDepartmentDetails(
    context,
    department: result,
    snapshot: snapshot,
    tenantName: snapshot.tenant?.name,
    facilityName: snapshot.facility?.name,
  );
}

Future<void> _openDepartmentDetails(
  BuildContext context, {
  required DepartmentProfile department,
  FacilitySetupSnapshot? snapshot,
  String? tenantName,
  String? facilityName,
}) async {
  await showDepartmentDetailsDialog(
    context,
    department: department,
    snapshot: snapshot,
    tenantName: tenantName,
    facilityName: facilityName == '—' ? null : facilityName,
  );
}

Future<void> _openUnitDialog(
  BuildContext context,
  FacilitySetupSnapshot snapshot, {
  UnitProfile? unit,
  List<TenantProfile> tenantOptions = const <TenantProfile>[],
  List<FacilityProfile> facilityOptions = const <FacilityProfile>[],
  List<DepartmentProfile> departmentOptions = const <DepartmentProfile>[],
  bool openDetailsOnSave = true,
}) async {
  final Object? result = await showAppDialog<Object?>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UnitFormDialog(
      snapshot: snapshot,
      unit: unit,
      tenantOptions: tenantOptions,
      facilityOptions: facilityOptions,
      departmentOptions: departmentOptions,
    ),
  );
  if (!openDetailsOnSave || !context.mounted || result is! UnitProfile) {
    return;
  }
  await _openUnitDetails(
    context,
    unit: result,
    snapshot: snapshot,
    tenantName: snapshot.tenant?.name,
    facilityName: snapshot.facility?.name,
    departmentName: _departmentName(snapshot, result.departmentId),
  );
}

Future<void> _openUnitDetails(
  BuildContext context, {
  required UnitProfile unit,
  FacilitySetupSnapshot? snapshot,
  String? tenantName,
  String? facilityName,
  String? departmentName,
}) async {
  await showUnitDetailsDialog(
    context,
    unit: unit,
    snapshot: snapshot,
    tenantName: tenantName,
    facilityName: facilityName == '—' ? null : facilityName,
    departmentName: departmentName == '—' ? null : departmentName,
  );
}

Future<void> _openWardDialog(
  BuildContext context,
  FacilitySetupSnapshot snapshot, {
  WardProfile? ward,
  List<TenantProfile> tenantOptions = const <TenantProfile>[],
  List<FacilityProfile> facilityOptions = const <FacilityProfile>[],
  List<DepartmentProfile> departmentOptions = const <DepartmentProfile>[],
  bool openDetailsOnSave = true,
}) async {
  final Object? result = await showAppDialog<Object?>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _WardFormDialog(
      snapshot: snapshot,
      ward: ward,
      tenantOptions: tenantOptions,
      facilityOptions: facilityOptions,
      departmentOptions: departmentOptions,
    ),
  );
  if (!openDetailsOnSave || !context.mounted || result is! WardProfile) {
    return;
  }
  String? tenantName = snapshot.tenant?.name;
  for (final TenantProfile tenant in tenantOptions) {
    if (tenant.id == result.tenantId) {
      tenantName = tenant.name;
      break;
    }
  }
  String? facilityName = snapshot.facility?.name;
  for (final FacilityProfile facility in facilityOptions) {
    if (facility.id == result.facilityId) {
      facilityName = facility.name;
      break;
    }
  }
  String? departmentName;
  final String? departmentId = result.departmentId?.trim();
  if (departmentId != null && departmentId.isNotEmpty) {
    for (final DepartmentProfile department in departmentOptions) {
      if (department.id == departmentId) {
        departmentName = department.name;
        break;
      }
    }
    departmentName ??= _departmentName(snapshot, departmentId);
  }
  await _openWardDetails(
    context,
    ward: result,
    snapshot: snapshot,
    tenantName: tenantName,
    facilityName: facilityName,
    departmentName: departmentName,
  );
}

Future<void> _openWardDetails(
  BuildContext context, {
  required WardProfile ward,
  FacilitySetupSnapshot? snapshot,
  String? tenantName,
  String? facilityName,
  String? departmentName,
}) async {
  await showWardDetailsDialog(
    context,
    ward: ward,
    snapshot: snapshot,
    tenantName: tenantName,
    facilityName: facilityName == '—' ? null : facilityName,
    departmentName: departmentName == '—' ? null : departmentName,
  );
}

Future<void> _openRoomDialog(
  BuildContext context,
  FacilitySetupSnapshot snapshot, {
  RoomProfile? room,
  List<TenantProfile> tenantOptions = const <TenantProfile>[],
  List<FacilityProfile> facilityOptions = const <FacilityProfile>[],
  List<WardProfile> wardOptions = const <WardProfile>[],
  String Function(RoomProfile room)? tenantNameFor,
  String Function(RoomProfile room)? facilityNameFor,
  String Function(RoomProfile room)? wardNameFor,
  bool openDetailsOnSave = true,
}) async {
  final Object? result = await showAppDialog<Object?>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RoomFormDialog(
      snapshot: snapshot,
      room: room,
      tenantOptions: tenantOptions,
      facilityOptions: facilityOptions,
      wardOptions: wardOptions,
    ),
  );
  if (!openDetailsOnSave || !context.mounted || result is! RoomProfile) {
    return;
  }

  String? tenantName = tenantNameFor?.call(result) ?? snapshot.tenant?.name;
  if (tenantName == null || tenantName == '—') {
    for (final TenantProfile tenant in tenantOptions) {
      if (tenant.id == result.tenantId) {
        tenantName = tenant.name;
        break;
      }
    }
  }

  String? facilityName =
      facilityNameFor?.call(result) ?? snapshot.facility?.name;
  if (facilityName == null || facilityName == '—') {
    for (final FacilityProfile facility in facilityOptions) {
      if (facility.id == result.facilityId) {
        facilityName = facility.name;
        break;
      }
    }
  }

  String? wardName = wardNameFor?.call(result);
  if (wardName == null || wardName == '—') {
    wardName = _wardName(snapshot, result.wardId);
    if (wardName == null) {
      final String? wardId = result.wardId?.trim();
      if (wardId != null && wardId.isNotEmpty) {
        for (final WardProfile ward in wardOptions) {
          if (ward.id == wardId) {
            wardName = ward.name;
            break;
          }
        }
      }
    }
  }

  await _openRoomDetails(
    context,
    room: result,
    snapshot: snapshot,
    tenantName: tenantName,
    facilityName: facilityName,
    wardName: wardName,
  );
}

Future<void> _openRoomDetails(
  BuildContext context, {
  required RoomProfile room,
  FacilitySetupSnapshot? snapshot,
  String? tenantName,
  String? facilityName,
  String? wardName,
}) async {
  await showRoomDetailsDialog(
    context,
    room: room,
    snapshot: snapshot,
    tenantName: tenantName,
    facilityName: facilityName == '—' ? null : facilityName,
    wardName: wardName == '—' ? null : wardName,
  );
}

Future<void> _openBedDialog(
  BuildContext context,
  FacilitySetupSnapshot snapshot, {
  BedProfile? bed,
  List<TenantProfile> tenantOptions = const <TenantProfile>[],
  List<FacilityProfile> facilityOptions = const <FacilityProfile>[],
  List<WardProfile> wardOptions = const <WardProfile>[],
  List<RoomProfile> roomOptions = const <RoomProfile>[],
  String Function(BedProfile bed)? tenantNameFor,
  String Function(BedProfile bed)? facilityNameFor,
  String Function(BedProfile bed)? wardNameFor,
  String Function(BedProfile bed)? roomNameFor,
  bool openDetailsOnSave = true,
}) async {
  final Object? result = await showAppDialog<Object?>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _BedFormDialog(
      snapshot: snapshot,
      bed: bed,
      tenantOptions: tenantOptions,
      facilityOptions: facilityOptions,
      wardOptions: wardOptions,
      roomOptions: roomOptions,
    ),
  );
  if (!openDetailsOnSave || !context.mounted || result is! BedProfile) {
    return;
  }
  await _openBedDetails(
    context,
    bed: result,
    snapshot: snapshot,
    tenantName: tenantNameFor?.call(result) ?? snapshot.tenant?.name,
    facilityName: facilityNameFor?.call(result) ?? snapshot.facility?.name,
    wardName: wardNameFor?.call(result) ?? _wardName(snapshot, result.wardId),
    roomName: roomNameFor?.call(result) ?? _roomName(snapshot, result.roomId),
  );
}

Future<void> _openBedDetails(
  BuildContext context, {
  required BedProfile bed,
  FacilitySetupSnapshot? snapshot,
  String? tenantName,
  String? facilityName,
  String? wardName,
  String? roomName,
}) async {
  await showBedDetailsDialog(
    context,
    bed: bed,
    snapshot: snapshot,
    tenantName: tenantName,
    facilityName: facilityName == '—' ? null : facilityName,
    wardName: wardName == '—' ? null : wardName,
    roomName: roomName == '—' ? null : roomName,
  );
}

Future<void> _deleteEntity({
  required BuildContext context,
  required WidgetRef ref,
  required String name,
  required Future<bool> Function() deleteAction,
}) async {
  final AppLocalizations l10n = context.l10n;
  await showAppDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AppConfirmActionDialog(
      title: l10n.tenantFacilitySoftDeleteStructureTitle,
      body: l10n.tenantFacilitySoftDeleteStructureBody(name),
      highlightedText: name,
      submitLabel: l10n.tenantFacilityDeleteConfirmAction,
      destructive: true,
      icon: const Icon(Icons.delete_outline),
      onConfirm: () async {
        final bool deleted = await deleteAction();
        if (deleted) {
          return null;
        }
        return ref.read(tenantFacilitySetupSubmissionProvider).failure ??
            const AppFailure.unexpected();
      },
    ),
  );
}

Future<void> _restoreEntity({
  required BuildContext context,
  required WidgetRef ref,
  required String name,
  required Future<bool> Function() restoreAction,
}) async {
  final AppLocalizations l10n = context.l10n;
  await showAppDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AppConfirmActionDialog(
      title: l10n.tenantFacilityRestoreStructureTitle,
      body: l10n.tenantFacilityRestoreStructureBody(name),
      highlightedText: name,
      submitLabel: l10n.tenantFacilityRestoreStructureAction,
      icon: const Icon(Icons.restore_outlined),
      onConfirm: () async {
        final bool restored = await restoreAction();
        if (restored) {
          return null;
        }
        return ref.read(tenantFacilitySetupSubmissionProvider).failure ??
            const AppFailure.unexpected();
      },
    ),
  );
}

Future<void> _permanentDeleteEntity({
  required BuildContext context,
  required WidgetRef ref,
  required String name,
  required Future<bool> Function() permanentDeleteAction,
}) async {
  final AppLocalizations l10n = context.l10n;
  final String? typed = await showAppDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) => AppTextInputActionDialog(
      title: l10n.tenantFacilityPermanentDeleteDepartmentConfirmationTitle,
      description: l10n.tenantFacilityPermanentDeleteDepartmentWarningBody(name),
      fieldLabel: l10n.tenantFacilityPermanentDeleteConfirmFieldLabel(name),
      submitLabel: l10n.tenantFacilityPermanentDeleteConfirmAction,
      cancelLabel: l10n.commonCancelActionLabel,
      requiredMessage: l10n.validationRequired,
      confirmExactValue: name,
      confirmMismatchMessage:
          l10n.tenantFacilityPermanentDeleteConfirmFieldLabel(name),
      destructive: true,
      minLines: 1,
      maxLines: 1,
      icon: const Icon(Icons.delete_forever_outlined),
    ),
  );

  if (!context.mounted || typed == null) {
    return;
  }
  if (typed.trim().toLowerCase() != name.trim().toLowerCase()) {
    return;
  }

  await showAppDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AppConfirmActionDialog(
      title: l10n.tenantFacilityPermanentDeleteDepartmentConfirmationTitle,
      body: l10n.tenantFacilityPermanentDeleteDepartmentConfirmationBody(name),
      highlightedText: name,
      submitLabel: l10n.tenantFacilityPermanentDeleteConfirmAction,
      destructive: true,
      icon: const Icon(Icons.delete_forever_outlined),
      onConfirm: () async {
        final bool deleted = await permanentDeleteAction();
        if (deleted) {
          return null;
        }
        final AppFailure? failure =
            ref.read(tenantFacilitySetupSubmissionProvider).failure;
        if (failure?.category == AppFailureCategory.notFound) {
          return null;
        }
        return failure ?? const AppFailure.unexpected();
      },
    ),
  );
}

String? _optionalSelection(String? value) {
  if (value == null || value == _noneSelection) {
    return null;
  }

  return value;
}

String _activeStatusLabel(AppLocalizations l10n, bool isActive) {
  return isActive
      ? l10n.tenantFacilityStatusActive
      : l10n.tenantFacilityStatusInactive;
}

String _departmentSubtitle(
  AppLocalizations l10n,
  FacilitySetupSnapshot snapshot,
  DepartmentProfile department,
) {
  // Used for search matching; table shows type/short name/status as columns.
  return _joinParts(<String?>[
    _departmentTypeLabel(l10n, department.type),
    if (department.shortName != null) department.shortName!,
    department.isDeleted
        ? l10n.tenantFacilityStructureDeletedStatus
        : _activeStatusLabel(l10n, department.isActive),
  ]);
}

String _roomSubtitle(
  AppLocalizations l10n,
  FacilitySetupSnapshot snapshot,
  RoomProfile room,
) {
  return _joinParts(<String?>[
    room.wardId != null
        ? _wardName(snapshot, room.wardId)
        : l10n.tenantFacilityRoomOutpatientLabel,
    if (room.floor != null) room.floor!,
  ]);
}

String _bedSubtitle(
  AppLocalizations l10n,
  FacilitySetupSnapshot snapshot,
  BedProfile bed,
) {
  return _joinParts(<String?>[
    _wardName(snapshot, bed.wardId),
    _roomName(snapshot, bed.roomId),
    _bedStatusLabel(l10n, bed.status),
  ]);
}

String _joinParts(List<String?> parts) {
  return parts
      .whereType<String>()
      .map((String part) => part.trim())
      .where((String part) => part.isNotEmpty)
      .join(', ');
}

String? _departmentName(FacilitySetupSnapshot snapshot, String? departmentId) {
  return snapshot.departments
      .where((DepartmentProfile department) => department.id == departmentId)
      .firstOrNull
      ?.name;
}

String? _wardName(FacilitySetupSnapshot snapshot, String? wardId) {
  return snapshot.wards
      .where((WardProfile ward) => ward.id == wardId)
      .firstOrNull
      ?.name;
}

String? _roomName(FacilitySetupSnapshot snapshot, String? roomId) {
  return snapshot.rooms
      .where((RoomProfile room) => room.id == roomId)
      .firstOrNull
      ?.name;
}

class _TwoColumnFields extends StatelessWidget {
  const _TwoColumnFields({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 640) {
          return Column(
            children: <Widget>[
              left,
              SizedBox(height: theme.spacing.md),
              right,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: left),
            SizedBox(width: theme.spacing.md),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

class _SubmissionFeedback extends StatelessWidget {
  const _SubmissionFeedback({
    required this.enabled,
    this.failure,
    this.permissionDeniedMessage,
  });

  final bool enabled;
  final AppFailure? failure;
  final String? permissionDeniedMessage;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final String deniedMessage =
        permissionDeniedMessage ?? l10n.tenantFacilityPermissionRequired;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (!enabled) ...<Widget>[
          Text(
            deniedMessage,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (failure != null) ...<Widget>[
          SizedBox(height: theme.spacing.xs),
          Text(
            l10n.failureMessage(failure!),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.statusColors.error,
            ),
          ),
        ],
      ],
    );
  }
}

class _SubmitButton extends ConsumerWidget {
  const _SubmitButton({
    required this.enabled,
    required this.isLoading,
    required this.label,
    required this.onPressed,
    this.permissionDeniedMessage,
  });

  final bool enabled;
  final bool isLoading;
  final String label;
  final VoidCallback onPressed;
  final String? permissionDeniedMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AppBreakpoint breakpoint = AppBreakpoints.of(context);
    final bool fullWidth = breakpoint.isMobile;
    final failure = ref.watch(
      tenantFacilitySetupSubmissionProvider.select((state) => state.failure),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AppButton.primary(
          label: label,
          leadingIcon: Icons.save_outlined,
          isLoading: isLoading,
          enabled: enabled,
          fullWidth: fullWidth,
          onPressed: onPressed,
        ),
        if (!enabled) ...<Widget>[
          SizedBox(height: Theme.of(context).spacing.xs),
          Text(
            permissionDeniedMessage ?? l10n.tenantFacilityPermissionRequired,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (failure != null) ...<Widget>[
          SizedBox(height: Theme.of(context).spacing.xs),
          Text(
            l10n.failureMessage(failure),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).statusColors.error,
            ),
          ),
        ],
      ],
    );
  }
}

String _departmentTypeLabel(AppLocalizations l10n, DepartmentSetupType type) {
  return switch (type) {
    DepartmentSetupType.clinical => l10n.tenantFacilityDepartmentTypeClinical,
    DepartmentSetupType.administrative =>
      l10n.tenantFacilityDepartmentTypeAdministrative,
    DepartmentSetupType.support => l10n.tenantFacilityDepartmentTypeSupport,
    DepartmentSetupType.diagnostics =>
      l10n.tenantFacilityDepartmentTypeDiagnostics,
    DepartmentSetupType.other => l10n.tenantFacilityDepartmentTypeOther,
  };
}

String _wardTypeLabel(AppLocalizations l10n, WardSetupType type) {
  return switch (type) {
    WardSetupType.general => l10n.tenantFacilityWardTypeGeneral,
    WardSetupType.icu => l10n.tenantFacilityWardTypeIcu,
    WardSetupType.maternity => l10n.tenantFacilityWardTypeMaternity,
    WardSetupType.pediatric => l10n.tenantFacilityWardTypePediatric,
    WardSetupType.surgical => l10n.tenantFacilityWardTypeSurgical,
    WardSetupType.other => l10n.tenantFacilityWardTypeOther,
  };
}

String _bedStatusLabel(AppLocalizations l10n, BedSetupStatus status) {
  return switch (status) {
    BedSetupStatus.available => l10n.tenantFacilityBedStatusAvailable,
    BedSetupStatus.occupied => l10n.tenantFacilityBedStatusOccupied,
    BedSetupStatus.reserved => l10n.tenantFacilityBedStatusReserved,
    BedSetupStatus.cleaning => l10n.tenantFacilityBedStatusCleaning,
    BedSetupStatus.maintenance => l10n.tenantFacilityBedStatusMaintenance,
    BedSetupStatus.blocked => l10n.tenantFacilityBedStatusBlocked,
    BedSetupStatus.outOfService => l10n.tenantFacilityBedStatusOutOfService,
  };
}

void _showSaved(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(context.l10n.tenantFacilitySavedMessage)),
    );
}

/// Opens the tenant profile create/edit dialog from the home dashboard.
Future<TenantProfile?> showTenantFacilityTenantFormDialog(
  BuildContext context, {
  TenantProfile? tenant,
  bool forceCreate = false,
  bool managementMode = false,
}) {
  return _openTenantProfileModal(
    context,
    tenant: tenant,
    forceCreate: forceCreate,
    managementMode: managementMode,
  );
}

/// Opens the facility profile create/edit dialog from the home dashboard.
Future<FacilityProfile?> showTenantFacilityFacilityFormDialog(
  BuildContext context, {
  String? tenantId,
  FacilityProfile? facility,
  bool requireTenantPicker = false,
  bool managementMode = false,
}) {
  return _openFacilityProfileModal(
    context,
    tenantId: tenantId,
    facility: facility,
    requireTenantPicker: requireTenantPicker,
    managementMode: managementMode,
  );
}

/// Shared department create/edit dialog for facility setup.
Future<void> showTenantFacilityDepartmentFormDialog(
  BuildContext context,
  FacilitySetupSnapshot snapshot, {
  DepartmentProfile? department,
}) {
  return _openDepartmentDialog(context, snapshot, department: department);
}

/// Shared unit create/edit dialog for facility setup.
Future<void> showTenantFacilityUnitFormDialog(
  BuildContext context,
  FacilitySetupSnapshot snapshot, {
  UnitProfile? unit,
  bool openDetailsOnSave = true,
}) {
  return _openUnitDialog(
    context,
    snapshot,
    unit: unit,
    openDetailsOnSave: openDetailsOnSave,
  );
}

/// Shared ward create/edit dialog for facility setup and management.
Future<void> showTenantFacilityWardFormDialog(
  BuildContext context,
  FacilitySetupSnapshot snapshot, {
  WardProfile? ward,
  bool openDetailsOnSave = true,
}) {
  return _openWardDialog(
    context,
    snapshot,
    ward: ward,
    openDetailsOnSave: openDetailsOnSave,
  );
}

/// Shared room create/edit dialog for facility setup and rooms & beds workspace.
Future<void> showTenantFacilityRoomFormDialog(
  BuildContext context,
  FacilitySetupSnapshot snapshot, {
  RoomProfile? room,
  bool openDetailsOnSave = true,
}) {
  return _openRoomDialog(
    context,
    snapshot,
    room: room,
    openDetailsOnSave: openDetailsOnSave,
  );
}

/// Shared bed create/edit dialog for facility setup and rooms & beds workspace.
Future<void> showTenantFacilityBedFormDialog(
  BuildContext context,
  FacilitySetupSnapshot snapshot, {
  BedProfile? bed,
}) {
  return _openBedDialog(
    context,
    snapshot,
    bed: bed,
    openDetailsOnSave: false,
  );
}
