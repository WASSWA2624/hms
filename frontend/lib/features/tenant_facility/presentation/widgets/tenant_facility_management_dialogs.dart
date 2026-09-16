import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/core/config/app_config_provider.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/permissions/permission_providers.dart';
import 'package:hosspi_hms/core/realtime/realtime_events.dart';
import 'package:hosspi_hms/core/realtime/realtime_message.dart';
import 'package:hosspi_hms/core/utils/app_formatters.dart';
import 'package:hosspi_hms/core/utils/app_media_url.dart';
import 'package:hosspi_hms/features/access_admin/data/repositories/access_admin_repository_impl.dart';
import 'package:hosspi_hms/features/access_admin/domain/entities/access_admin_entities.dart';
import 'package:hosspi_hms/features/access_admin/domain/repositories/access_admin_repository.dart';
import 'package:hosspi_hms/features/access_admin/presentation/widgets/access_admin_dialogs.dart';
import 'package:hosspi_hms/features/home/domain/entities/home_dashboard.dart';
import 'package:hosspi_hms/features/home/presentation/controllers/home_controller.dart';
import 'package:hosspi_hms/features/home/presentation/controllers/home_dashboard_optimistic_patch.dart';
import 'package:hosspi_hms/features/home/presentation/controllers/home_dashboard_sync.dart';
import 'package:hosspi_hms/features/tenant_facility/data/repositories/tenant_facility_repository_impl.dart';
import 'package:hosspi_hms/features/tenant_facility/domain/entities/tenant_facility_setup.dart';
import 'package:hosspi_hms/features/tenant_facility/domain/repositories/tenant_facility_repository.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/controllers/tenant_facility_setup_controller.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/pages/tenant_facility_setup_page.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/tenant_facility_setup_access.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/widgets/tenant_facility_setup_helpers.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/widgets/tenant_facility_setup_print_helpers.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/actions/app_action_dialogs.dart';
import 'package:hosspi_hms/shared/components/components.dart';
import 'package:hosspi_hms/shared/data/data.dart';
import 'package:hosspi_hms/shared/layout/layout.dart';
import 'package:hosspi_hms/shared/management/platform_admin_list_config.dart';
import 'package:hosspi_hms/shared/management/platform_management_list_sync.dart';

const Set<String> _tenantManagementRealtimeEvents = <String>{
  RealtimeEvents.tenantCreated,
  RealtimeEvents.tenantUpdated,
  RealtimeEvents.tenantDeleted,
  RealtimeEvents.tenantRestored,
  RealtimeEvents.tenantPermanentlyDeleted,
};

const Set<String> _facilityManagementRealtimeEvents = <String>{
  RealtimeEvents.tenantCreated,
  RealtimeEvents.tenantUpdated,
  RealtimeEvents.tenantDeleted,
  RealtimeEvents.facilityCreated,
  RealtimeEvents.facilityUpdated,
  RealtimeEvents.facilityDeleted,
  RealtimeEvents.facilityRestored,
  RealtimeEvents.facilityPermanentlyDeleted,
};

String? _managementNonEmptyString(Object? value) {
  if (value is! String) {
    return null;
  }
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _managementResourceIdFromMessage(
  RealtimeMessage message, {
  required Iterable<String> keys,
}) {
  final Map<String, Object?> payload = message.payload;
  final Object? nested = payload['payload'];
  final Map<String, Object?>? nestedMap = nested is Map<String, Object?>
      ? nested
      : nested is Map<Object?, Object?>
      ? Map<String, Object?>.fromEntries(
          nested.entries
              .where((MapEntry<Object?, Object?> entry) => entry.key != null)
              .map(
                (MapEntry<Object?, Object?> entry) => MapEntry<String, Object?>(
                  entry.key.toString(),
                  entry.value,
                ),
              ),
        )
      : null;

  for (final String key in keys) {
    final String? fromRoot = _managementNonEmptyString(payload[key]);
    if (fromRoot != null) {
      return fromRoot;
    }
    final String? fromNested = _managementNonEmptyString(nestedMap?[key]);
    if (fromNested != null) {
      return fromNested;
    }
  }
  return null;
}

void _syncPlatformDashboard(
  WidgetRef ref, {
  HomeDashboardOptimisticPatch? patch,
}) {
  const HomeDashboardRequest request = HomeDashboardRequest.empty;
  if (patch != null && !patch.isEmpty) {
    homeApplyDashboardOptimisticPatch(ref, request, patch);
  }
  ref.invalidate(homeControllerProvider(request));
}

Future<bool?> showManageTenantsDialog(BuildContext context, WidgetRef ref) {
  return showAppDialog<bool>(
    context: context,
    builder: (_) => const ManageTenantsPanel(dialogMode: true),
  );
}

Future<bool?> showManageFacilitiesDialog(BuildContext context, WidgetRef ref) {
  return showAppDialog<bool>(
    context: context,
    builder: (_) => const ManageFacilitiesPanel(dialogMode: true),
  );
}

Future<bool?> showTenantDetailsDialog(
  BuildContext context, {
  required TenantProfile tenant,
}) {
  return showAppDialog<bool>(
    context: context,
    builder: (_) => _TenantDetailsDialog(tenant: tenant),
  );
}

Future<bool?> showFacilityDetailsDialog(
  BuildContext context, {
  required FacilityProfile facility,
  String? tenantName,
}) {
  return showAppDialog<bool>(
    context: context,
    builder: (_) =>
        _FacilityDetailsDialog(facility: facility, tenantName: tenantName),
  );
}

/// Tenants table/CRUD shared by manage dialog and setup Tenants tab.
class ManageTenantsPanel extends ConsumerStatefulWidget {
  const ManageTenantsPanel({
    this.dialogMode = false,
    this.showCreateAction = true,
    this.sessionTenant,
    this.reloadListenable,
    this.onMutated,
    this.onListTotalChanged,
    this.initialSubscriptionFilter,
    super.key,
  });

  final bool dialogMode;
  final bool showCreateAction;
  final TenantProfile? sessionTenant;
  final Listenable? reloadListenable;
  final ValueChanged<bool>? onMutated;
  final ValueChanged<int>? onListTotalChanged;

  /// Preselected subscription filter from `?subscription=` deep links
  /// (platform dashboard "tenants without subscription" alert).
  final String? initialSubscriptionFilter;

  @override
  ConsumerState<ManageTenantsPanel> createState() => _ManageTenantsPanelState();
}

class _ManageTenantsPanelState extends ConsumerState<ManageTenantsPanel> {
  static const String _statusFilterKey = 'status';
  static const String _statusActive = 'active';
  static const String _statusDeleted = 'deleted';
  static const String _subscriptionFilterKey = 'subscription';
  static const String _subscriptionNone = 'none';
  static const String _subscriptionActive = 'active';

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  bool _loading = true;
  AppFailure? _failure;
  AppPageRequest _pageRequest = PlatformAdminListConfig.initialPageRequest;
  int _totalItemCount = 0;
  List<TenantProfile> _tenants = const <TenantProfile>[];
  TenantProfile? _scopedTenant;
  AppSearchBarFilterValue _filterValue = AppSearchBarFilterValue.empty;
  String? _subscriptionFilter;
  bool _mutated = false;
  int _reloadGeneration = 0;
  PlatformManagementListSync? _realtimeSync;

  bool get _canCreate => ref.read(appAccessPolicyProvider).canCreateTenant();

  bool get _canEdit => ref.read(appAccessPolicyProvider).canManageTenant();

  bool get _canDelete => _canCreate;

  bool get _isScopedTenantManager => tenantFacilityUsesScopedTenantPanel(
    canManageTenant: _canEdit,
    canCreateTenant: _canCreate,
  );

  @override
  void initState() {
    super.initState();
    _applySubscriptionDeepLink(widget.initialSubscriptionFilter);
    widget.reloadListenable?.addListener(_onReloadListenable);
    _searchController.addListener(_onSearchChanged);
    if (_isScopedTenantManager) {
      _scopedTenant = widget.sessionTenant;
      if (_scopedTenant != null) {
        _loading = false;
      } else {
        unawaited(_reloadScopedTenant());
      }
    } else {
      unawaited(_reload(resetPage: true));
    }
  }

  @override
  void didUpdateWidget(covariant ManageTenantsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSubscriptionFilter !=
            oldWidget.initialSubscriptionFilter &&
        _applySubscriptionDeepLink(widget.initialSubscriptionFilter) &&
        !_isScopedTenantManager) {
      unawaited(_reload(resetPage: true, silent: _tenants.isNotEmpty));
    }
    if (_isScopedTenantManager &&
        widget.sessionTenant != null &&
        widget.sessionTenant != oldWidget.sessionTenant) {
      _scopedTenant = _mergeScopedTenantProfile(
        previous: _scopedTenant,
        incoming: widget.sessionTenant!,
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isScopedTenantManager) {
      return;
    }
    _realtimeSync ??= PlatformManagementListSync(
      ref: ref,
      events: _tenantManagementRealtimeEvents,
      onMutated: _markMutated,
      reload: ({bool silent = false, RealtimeMessage? message}) async {
        _applyTenantRealtimeMessage(message);
        await _reload(resetPage: false, silent: silent);
      },
    )..attach();
  }

  @override
  void dispose() {
    widget.reloadListenable?.removeListener(_onReloadListenable);
    _realtimeSync?.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onReloadListenable() {
    if (_isScopedTenantManager) {
      unawaited(_reloadScopedTenant(silent: true));
      return;
    }
    unawaited(_reload(resetPage: false, silent: true));
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_reload(resetPage: true));
    });
  }

  /// Seeds the subscription filter from a deep link. Returns true when the
  /// applied value differs from the current one.
  bool _applySubscriptionDeepLink(String? value) {
    final String normalized = (value ?? '').trim().toLowerCase();
    final String? resolved =
        normalized == _subscriptionNone || normalized == _subscriptionActive
        ? normalized
        : null;
    if (resolved == _subscriptionFilter) {
      return false;
    }
    _subscriptionFilter = resolved;
    final Map<String, String> options = Map<String, String>.from(
      _filterValue.options,
    );
    if (resolved == null) {
      options.remove(_subscriptionFilterKey);
    } else {
      options[_subscriptionFilterKey] = resolved;
    }
    _filterValue = _filterValue.copyWith(options: options);
    return true;
  }

  Future<void> _applyTenantFilters(AppSearchBarFilterValue value) async {
    final String? nextSubscription = value.option(_subscriptionFilterKey);
    final bool reloadNeeded = nextSubscription != _subscriptionFilter;
    setState(() {
      _filterValue = value;
      _subscriptionFilter = nextSubscription;
    });
    if (reloadNeeded) {
      await _reload(resetPage: true, silent: _tenants.isNotEmpty);
    }
  }

  String _tenantPackageLabel(AppLocalizations l10n, TenantProfile tenant) {
    return tenant.subscription?.packageLabel ??
        l10n.tenantFacilityTenantSubscriptionNoneValue;
  }

  String _tenantSubscriptionStartLabel(
    AppLocalizations l10n,
    Locale locale,
    TenantProfile tenant,
  ) {
    final DateTime? start = tenant.subscription?.startDate;
    return start == null
        ? l10n.profileUnknownValue
        : AppFormatters.mediumDate(start.toLocal(), locale);
  }

  String _tenantSubscriptionEndLabel(
    AppLocalizations l10n,
    Locale locale,
    TenantProfile tenant,
  ) {
    final TenantSubscriptionProfile? subscription = tenant.subscription;
    if (subscription == null) {
      return l10n.profileUnknownValue;
    }
    final DateTime? end = subscription.endDate;
    return end == null
        ? l10n.tenantFacilityTenantSubscriptionOpenEndedValue
        : AppFormatters.mediumDate(end.toLocal(), locale);
  }

  List<TenantProfile> get _visibleTenants {
    final String? status = _filterValue.option(_statusFilterKey);
    if (status == _statusActive) {
      return _tenants
          .where((TenantProfile tenant) => !tenant.isDeleted)
          .toList(growable: false);
    }
    if (status == _statusDeleted) {
      return _tenants
          .where((TenantProfile tenant) => tenant.isDeleted)
          .toList(growable: false);
    }
    return _tenants;
  }

  Future<void> _reloadScopedTenant({bool silent = false}) async {
    final int generation = ++_reloadGeneration;
    if (!silent) {
      setState(() {
        _loading = true;
        _failure = null;
      });
    }

    final Result<FacilitySetupSnapshot> result = await ref
        .read(tenantFacilityRepositoryProvider)
        .loadSetup();

    if (!mounted || generation != _reloadGeneration) {
      return;
    }

    result.when(
      success: (FacilitySetupSnapshot snapshot) {
        setState(() {
          _loading = false;
          _failure = null;
          final TenantProfile? loaded = snapshot.tenant ?? widget.sessionTenant;
          _scopedTenant = loaded == null
              ? _scopedTenant
              : _mergeScopedTenantProfile(
                  previous: _scopedTenant,
                  incoming: loaded,
                );
        });
      },
      failure: (AppFailure failure) {
        setState(() {
          _loading = false;
          _failure = failure;
          if (!silent && _scopedTenant == null) {
            _scopedTenant = widget.sessionTenant;
          }
        });
      },
    );
  }

  TenantProfile _mergeScopedTenantProfile({
    required TenantProfile? previous,
    required TenantProfile incoming,
  }) {
    if (previous == null) {
      return incoming;
    }

    String? prefer(String? next, String? current) {
      final String? trimmedNext = next?.trim();
      if (trimmedNext != null && trimmedNext.isNotEmpty) {
        return trimmedNext;
      }
      final String? trimmedCurrent = current?.trim();
      if (trimmedCurrent != null && trimmedCurrent.isNotEmpty) {
        return trimmedCurrent;
      }
      return next ?? current;
    }

    return incoming.copyWith(
      resourceUuid: incoming.resourceUuid ?? previous.resourceUuid,
      displayId: incoming.displayId ?? previous.displayId,
      currency: prefer(incoming.currency, previous.currency),
      standardConsultationFee: prefer(
        incoming.standardConsultationFee,
        previous.standardConsultationFee,
      ),
      contactName: prefer(incoming.contactName, previous.contactName),
      contactEmail: prefer(incoming.contactEmail, previous.contactEmail),
      contactPhone: prefer(incoming.contactPhone, previous.contactPhone),
    );
  }

  Future<void> _reload({required bool resetPage, bool silent = false}) async {
    if (resetPage) {
      _pageRequest = _pageRequest.first();
    }
    final int generation = ++_reloadGeneration;
    if (!silent) {
      setState(() {
        _loading = true;
        _failure = null;
      });
    }

    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );
    final Result<AppPage<TenantProfile>> result = await repository.listTenants(
      request: _pageRequest,
      search: _searchController.text.trim(),
      subscription: _subscriptionFilter,
      // Subscription filtering mirrors the platform alert, which ignores
      // soft-deleted tenants - keep the two counts in step.
      includeDeleted: _subscriptionFilter == null,
    );

    if (!mounted || generation != _reloadGeneration) return;
    result.when(
      success: (AppPage<TenantProfile> page) {
        final List<TenantProfile> tenants = page.items;
        final int totalItemCount = page.totalItemCount ?? tenants.length;
        homeClearDashboardOptimisticPatch(ref, HomeDashboardRequest.empty);
        homeReconcileTenantsMetricFromList(
          ref,
          _countDashboardActiveTenants(tenants),
          totalCount: _countDashboardTotalTenants(tenants),
        );
        ref.invalidate(homeControllerProvider(HomeDashboardRequest.empty));
        setState(() {
          _loading = false;
          _tenants = tenants;
          _totalItemCount = totalItemCount;
        });
        widget.onListTotalChanged?.call(_totalItemCount);
      },
      failure: (AppFailure failure) {
        setState(() {
          _loading = false;
          _failure = failure;
          if (!silent) {
            _tenants = const <TenantProfile>[];
          }
        });
      },
    );
  }

  Future<void> _onPageChanged(AppPageRequest request) async {
    _pageRequest = request;
    await _reload(resetPage: false);
  }

  Future<void> _openTenantDetails(TenantProfile tenant) async {
    final bool? mutated = await showTenantDetailsDialog(
      context,
      tenant: tenant,
    );
    if (!mounted || mutated != true) {
      return;
    }

    _markMutated();
    await _reload(resetPage: false, silent: true);
  }

  Future<void> _openTenantForm({
    TenantProfile? tenant,
    bool forceCreate = false,
  }) async {
    final bool? wasActive = tenant?.isActive;
    final bool isCreate = forceCreate || tenant == null;
    final TenantProfile? savedTenant = await showTenantFacilityTenantFormDialog(
      context,
      tenant: tenant,
      forceCreate: forceCreate,
      managementMode: true,
    );
    if (!mounted || savedTenant == null) {
      return;
    }

    if (isCreate) {
      final bool alreadyListed = _tenants.any(
        (TenantProfile item) =>
            item.id == savedTenant.id ||
            item.mutationId == savedTenant.mutationId,
      );
      _searchDebounce?.cancel();
      if (_searchController.text.isNotEmpty) {
        _searchController.removeListener(_onSearchChanged);
        _searchController.clear();
        _searchController.addListener(_onSearchChanged);
      }
      _filterValue = AppSearchBarFilterValue.empty;
      _pageRequest = PlatformAdminListConfig.initialPageRequest;

      _upsertTenantLocally(savedTenant);
      _markMutated();
      if (!alreadyListed) {
        _syncPlatformDashboard(
          ref,
          patch: HomeDashboardOptimisticPatch.tenantCreated(),
        );
      }
      await _reload(resetPage: true, silent: true);
      if (!mounted) {
        return;
      }
      _upsertTenantLocally(savedTenant);
      if (alreadyListed) {
        await showTenantDetailsDialog(context, tenant: savedTenant);
      }
      return;
    }

    _upsertTenantLocally(savedTenant);
    _markMutated();

    if (wasActive != null && savedTenant.isActive != wasActive) {
      _syncPlatformDashboard(
        ref,
        patch: HomeDashboardOptimisticPatch.tenantActiveChanged(
          wasActive: wasActive,
          isActive: savedTenant.isActive,
        ),
      );
    }

    await _reload(resetPage: false, silent: true);
    if (!mounted) {
      return;
    }
    // Keep the saved row visible even if the list refresh is briefly stale.
    _upsertTenantLocally(savedTenant);
  }

  Future<void> _confirmDeleteTenant(TenantProfile tenant) async {
    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AppConfirmActionDialog(
        title: l10n.tenantFacilityDeleteConfirmationTitle,
        body: l10n.tenantFacilityDeleteTenantConfirmationBody(tenant.name),
        highlightedText: tenant.name,
        submitLabel: l10n.tenantFacilityDeleteConfirmAction,
        destructive: true,
        icon: const Icon(Icons.delete_outline),
        onConfirm: () async {
          final Result<void> result = await ref
              .read(tenantFacilityRepositoryProvider)
              .deleteTenant(tenant.mutationId);
          return result.when(
            success: (_) => null,
            failure: (AppFailure failure) {
              if (failure.category == AppFailureCategory.notFound) {
                return null;
              }
              return failure;
            },
          );
        },
      ),
    );

    if (!mounted) {
      return;
    }

    if (confirmed == true) {
      _markTenantSoftDeletedLocally(tenant);
      _markMutated();
      _syncPlatformDashboard(
        ref,
        patch: HomeDashboardOptimisticPatch.tenantDeleted(
          isActive: tenant.isActive && !tenant.isDeleted,
        ),
      );
      await _reload(resetPage: false, silent: true);
      if (mounted) {
        // Keep soft-delete visible locally if the refresh is briefly stale.
        _markTenantSoftDeletedLocally(tenant);
      }
    }
  }

  Future<void> _confirmRestoreTenant(TenantProfile tenant) async {
    final AppLocalizations l10n = context.l10n;
    TenantProfile? restoredTenant;
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AppConfirmActionDialog(
        title: l10n.tenantFacilityRestoreConfirmationTitle,
        body: l10n.tenantFacilityRestoreTenantConfirmationBody(tenant.name),
        highlightedText: tenant.name,
        submitLabel: l10n.tenantFacilityRestoreTenantAction,
        icon: const Icon(Icons.restore_outlined),
        onConfirm: () async {
          final Result<TenantProfile> result = await ref
              .read(tenantFacilityRepositoryProvider)
              .restoreTenant(tenant.mutationId);
          return result.when(
            success: (TenantProfile value) {
              restoredTenant = value;
              return null;
            },
            failure: (AppFailure failure) => failure,
          );
        },
      ),
    );

    if (!mounted || confirmed != true) {
      return;
    }

    final TenantProfile applied =
        restoredTenant ?? tenant.copyWith(clearDeletedAt: true);
    _upsertTenantLocally(applied);
    _markMutated();
    _syncPlatformDashboard(
      ref,
      patch: HomeDashboardOptimisticPatch.tenantRestored(
        isActive: applied.isActive,
      ),
    );
    await _reload(resetPage: false, silent: true);
    if (mounted) {
      // Keep the restored row active if the refresh is briefly stale.
      _upsertTenantLocally(applied);
    }
  }

  Future<void> _confirmPermanentDeleteTenant(TenantProfile tenant) async {
    final AppLocalizations l10n = context.l10n;
    final String? typed = await showAppDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AppTextInputActionDialog(
        title: l10n.tenantFacilityPermanentDeleteConfirmationTitle,
        description: l10n.tenantFacilityPermanentDeleteWarningBody(tenant.name),
        fieldLabel: l10n.tenantFacilityPermanentDeleteConfirmFieldLabel(
          tenant.name,
        ),
        submitLabel: l10n.tenantFacilityPermanentDeleteConfirmAction,
        cancelLabel: l10n.commonCancelActionLabel,
        requiredMessage: l10n.validationRequired,
        confirmExactValue: tenant.name,
        confirmMismatchMessage: l10n
            .tenantFacilityPermanentDeleteConfirmFieldLabel(tenant.name),
        destructive: true,
        minLines: 1,
        maxLines: 1,
        icon: const Icon(Icons.delete_forever_outlined),
      ),
    );

    if (!mounted || typed == null) {
      return;
    }
    if (typed.trim().toLowerCase() != tenant.name.trim().toLowerCase()) {
      return;
    }

    final Object? confirmed = await showAppDialog<Object?>(
      context: context,
      builder: (BuildContext dialogContext) => AppConfirmActionDialog(
        title: l10n.tenantFacilityPermanentDeleteConfirmationTitle,
        body: l10n.tenantFacilityPermanentDeleteConfirmationBody(tenant.name),
        highlightedText: tenant.name,
        submitLabel: l10n.tenantFacilityPermanentDeleteConfirmAction,
        destructive: true,
        icon: const Icon(Icons.delete_forever_outlined),
        shouldPopOnFailure: (AppFailure failure) =>
            failure.code == 'PERMANENT_DELETE_BLOCKED',
        failurePopValue: 'blocked',
        onConfirm: () async {
          final Result<void> result = await ref
              .read(tenantFacilityRepositoryProvider)
              .permanentDeleteTenant(tenant.mutationId);
          return result.when(
            success: (_) => null,
            failure: (AppFailure failure) {
              // Already purged — treat as success so the dialog closes and
              // the list can drop the stale row immediately.
              if (failure.category == AppFailureCategory.notFound) {
                return null;
              }
              return failure;
            },
          );
        },
      ),
    );

    if (!mounted) {
      return;
    }

    if (confirmed == true) {
      _markPermanentDeleteTenantSuccess(tenant);
      return;
    }

    if (confirmed != 'blocked') {
      return;
    }

    final bool? deleteAnyway = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AppConfirmActionDialog(
        title: l10n.tenantFacilityPermanentDeleteBlockedTitle,
        body:
            '${l10n.tenantFacilityPermanentDeleteBlockedActiveSubscriptionMessage}\n\n'
            '${l10n.tenantFacilityPermanentDeleteAnywayWarning}',
        submitLabel: l10n.tenantFacilityPermanentDeleteAnywayAction,
        cancelLabel: l10n.tenantFacilityPermanentDeleteBlockedCancelAction,
        destructive: true,
        icon: const Icon(Icons.delete_forever_outlined),
        onConfirm: () async {
          final Result<void> result = await ref
              .read(tenantFacilityRepositoryProvider)
              .permanentDeleteTenant(tenant.mutationId, force: true);
          return result.when(
            success: (_) => null,
            failure: (AppFailure failure) {
              if (failure.category == AppFailureCategory.notFound) {
                return null;
              }
              return failure;
            },
          );
        },
      ),
    );

    if (!mounted || deleteAnyway != true) {
      return;
    }

    _markPermanentDeleteTenantSuccess(tenant);
  }

  void _markPermanentDeleteTenantSuccess(TenantProfile tenant) {
    _markMutated();
    _removeTenantLocally(tenant);
    _syncPlatformDashboard(ref);
    unawaited(_reload(resetPage: false, silent: true));
  }

  bool _matchesTenant(TenantProfile entry, TenantProfile target) {
    if (entry.id == target.id || entry.mutationId == target.mutationId) {
      return true;
    }
    // Avoid matching a live slug against a soft-deleted mangled slug.
    final String? entrySlug = entry.slug?.trim();
    final String? targetSlug = target.slug?.trim();
    if (entrySlug == null ||
        entrySlug.isEmpty ||
        targetSlug == null ||
        targetSlug.isEmpty) {
      return false;
    }
    if (entrySlug.contains('__deleted__') ||
        targetSlug.contains('__deleted__')) {
      return false;
    }
    return entrySlug == targetSlug;
  }

  bool _matchesTenantId(TenantProfile entry, String tenantId) {
    return entry.id == tenantId ||
        entry.mutationId == tenantId ||
        entry.slug == tenantId;
  }

  void _upsertTenantLocally(TenantProfile tenant) {
    final int index = _tenants.indexWhere(
      (TenantProfile entry) => _matchesTenant(entry, tenant),
    );
    final List<TenantProfile> next = List<TenantProfile>.of(_tenants);
    if (index < 0) {
      next.insert(0, tenant);
      setState(() {
        _tenants = next;
        _totalItemCount += 1;
        _loading = false;
        _failure = null;
      });
      _reconcileDashboardFromLocalList();
      return;
    }

    final TenantProfile previous = next[index];
    next[index] = tenant.copyWith(
      id: tenant.id.isNotEmpty ? tenant.id : previous.id,
      resourceUuid: tenant.resourceUuid ?? previous.resourceUuid,
      displayId: tenant.displayId ?? previous.displayId,
      // Tenant edits never carry subscription relations - keep what we know.
      subscription: tenant.subscription ?? previous.subscription,
      deletedAt: tenant.deletedAt,
      clearDeletedAt: tenant.deletedAt == null && previous.deletedAt != null,
    );
    setState(() {
      _tenants = next;
      _loading = false;
      _failure = null;
    });
    _reconcileDashboardFromLocalList();
  }

  void _markTenantSoftDeletedLocally(TenantProfile tenant) {
    final int index = _tenants.indexWhere(
      (TenantProfile entry) => _matchesTenant(entry, tenant),
    );
    if (index < 0) {
      return;
    }
    final List<TenantProfile> next = List<TenantProfile>.of(_tenants);
    next[index] = tenant.copyWith(deletedAt: DateTime.now().toUtc());
    setState(() {
      _tenants = next;
    });
    _reconcileDashboardFromLocalList();
  }

  void _markTenantRestoredLocally(TenantProfile tenant) {
    final int index = _tenants.indexWhere(
      (TenantProfile entry) => _matchesTenant(entry, tenant),
    );
    if (index < 0) {
      return;
    }
    final List<TenantProfile> next = List<TenantProfile>.of(_tenants);
    next[index] = tenant.copyWith(clearDeletedAt: true);
    setState(() {
      _tenants = next;
    });
    _reconcileDashboardFromLocalList();
  }

  void _removeTenantLocally(TenantProfile tenant) {
    final List<TenantProfile> next = _tenants
        .where((TenantProfile entry) => !_matchesTenant(entry, tenant))
        .toList(growable: false);
    if (next.length == _tenants.length) {
      return;
    }
    setState(() {
      _tenants = next;
      _totalItemCount = math.max(0, _totalItemCount - 1);
    });
    _reconcileDashboardFromLocalList();
  }

  void _removeTenantByIdLocally(String tenantId) {
    final int before = _tenants.length;
    final List<TenantProfile> next = _tenants
        .where((TenantProfile entry) => !_matchesTenantId(entry, tenantId))
        .toList(growable: false);
    if (next.length == before) {
      return;
    }
    setState(() {
      _tenants = next;
      _totalItemCount = math.max(0, _totalItemCount - (before - next.length));
    });
    _reconcileDashboardFromLocalList();
  }

  void _reconcileDashboardFromLocalList() {
    homeClearDashboardOptimisticPatch(ref, HomeDashboardRequest.empty);
    homeReconcileTenantsMetricFromList(
      ref,
      _countDashboardActiveTenants(_tenants),
      totalCount: _countDashboardTotalTenants(_tenants),
    );
    ref.invalidate(homeControllerProvider(HomeDashboardRequest.empty));
  }

  void _applyTenantRealtimeMessage(RealtimeMessage? message) {
    if (message == null) {
      return;
    }

    final String? tenantId = _managementResourceIdFromMessage(
      message,
      keys: const <String>['resource_id', 'tenant_id', 'id'],
    );

    switch (message.event) {
      case RealtimeEvents.tenantDeleted:
        if (tenantId == null) {
          return;
        }
        final int index = _tenants.indexWhere(
          (TenantProfile entry) => _matchesTenantId(entry, tenantId),
        );
        if (index < 0) {
          return;
        }
        final List<TenantProfile> next = List<TenantProfile>.of(_tenants);
        next[index] = next[index].copyWith(deletedAt: DateTime.now().toUtc());
        setState(() {
          _tenants = next;
        });
        _reconcileDashboardFromLocalList();
        return;
      case RealtimeEvents.tenantPermanentlyDeleted:
        if (tenantId != null) {
          _removeTenantByIdLocally(tenantId);
        }
        return;
      case RealtimeEvents.tenantRestored:
      case RealtimeEvents.tenantCreated:
      case RealtimeEvents.tenantUpdated:
        return;
    }
  }

  int _countDashboardActiveTenants(List<TenantProfile> tenants) {
    return tenants
        .where((TenantProfile tenant) => !tenant.isDeleted && tenant.isActive)
        .length;
  }

  int _countDashboardTotalTenants(List<TenantProfile> tenants) {
    return tenants.where((TenantProfile tenant) => !tenant.isDeleted).length;
  }

  String _tenantStatusLabel(AppLocalizations l10n, TenantProfile tenant) {
    if (tenant.isDeleted) {
      return l10n.tenantFacilityTenantStatusDeleted;
    }
    return tenant.isActive
        ? l10n.tenantFacilityTenantStatusActive
        : l10n.commonNoLabel;
  }

  void _markMutated() {
    _mutated = true;
    widget.onMutated?.call(true);
  }

  Future<void> _editScopedTenant() async {
    final TenantProfile? tenant = _scopedTenant;
    if (tenant == null || !mounted) {
      return;
    }

    final BuildContext dialogContext = context;
    final TenantProfile? savedTenant = await showTenantFacilityTenantFormDialog(
      dialogContext,
      tenant: tenant,
      managementMode: true,
    );
    if (!mounted || savedTenant == null) {
      return;
    }

    setState(() {
      _scopedTenant = _mergeScopedTenantProfile(
        previous: tenant,
        incoming: savedTenant,
      );
      _failure = null;
    });

    _markMutated();
    unawaited(_reloadScopedTenant(silent: true));
  }

  Widget _buildScopedBody(AppLocalizations l10n) {
    if (_loading && _scopedTenant == null) {
      return AppWorkspaceStatePanel.loading(
        title: l10n.tenantFacilityTenantDetailsTitle,
        body: l10n.commonLoadingBody,
      );
    }

    if (_failure != null && _scopedTenant == null) {
      return AppFailureStateView(failure: _failure!);
    }

    final TenantProfile? tenant = _scopedTenant;
    if (tenant == null) {
      return AppWorkspaceStatePanel.empty(
        title: l10n.tenantFacilityTenantSectionTitle,
        body: l10n.tenantFacilityTenantSectionBody,
        icon: Icons.corporate_fare_outlined,
      );
    }

    final ThemeData theme = Theme.of(context);
    final String statusLabel = _tenantStatusLabel(l10n, tenant);
    final AppWorkspaceStatusTone statusTone = tenant.isDeleted
        ? AppWorkspaceStatusTone.error
        : (tenant.isActive
              ? AppWorkspaceStatusTone.success
              : AppWorkspaceStatusTone.neutral);
    final bool canEditTenant = _canEdit && !tenant.isDeleted;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        theme.spacing.md,
        theme.spacing.sm,
        theme.spacing.md,
        theme.spacing.md,
      ),
      child: _TenantDetailsSummary(
        tenant: tenant,
        statusLabel: statusLabel,
        statusTone: statusTone,
        onEdit: canEditTenant ? _editScopedTenant : null,
        editLabel: l10n.tenantFacilityEditTenantAction,
      ),
    );
  }

  Widget _buildTableBody(AppLocalizations l10n) {
    final Locale locale = Localizations.localeOf(context);
    final List<TenantProfile> visibleTenants = _visibleTenants;
    final bool statusFiltered = _filterValue.option(_statusFilterKey) != null;
    final bool hasActiveFilters = statusFiltered || _subscriptionFilter != null;

    if (_failure != null) {
      return AppFailureStateView(failure: _failure!);
    }

    return AppListTable<TenantProfile>(
      page: AppPage<TenantProfile>(
        items: visibleTenants,
        request: _pageRequest,
        totalItemCount: statusFiltered
            ? visibleTenants.length
            : _totalItemCount,
      ),
      isLoading: _loading,
      itemKeyBuilder: (TenantProfile item) => ValueKey<String>(item.id),
      onRowSelected: (TenantProfile tenant) {
        if (tenant.isDeleted) {
          return;
        }
        unawaited(_openTenantDetails(tenant));
      },
      previousPageLabel: l10n.hrPreviousPageLabel,
      nextPageLabel: l10n.hrNextPageLabel,
      pageLabelBuilder: (AppPage<TenantProfile> page) {
        if (_loading) {
          return '';
        }
        final int total = page.totalItemCount ?? page.items.length;
        if (total == 0) return l10n.commonTableEmptyLabel;
        final int start = page.pageIndex * page.pageSize + 1;
        final int end = start + page.items.length - 1;
        return '$start-$end / $total';
      },
      onPageChanged: _onPageChanged,
      columnVisibilityStorageKey: 'setup_manage_tenants_v3',
      columnVisibilityLabel: l10n.commonTableSettingsActionLabel,
      columnVisibilityTitle: l10n.commonTableSettingsTitle,
      columnVisibilityApplyLabel: l10n.receptionApplyColumnsAction,
      columnVisibilityResetLabel: l10n.receptionResetColumnsAction,
      columnVisibilityCloseLabel: l10n.commonCloseActionLabel,
      canExport: canExportTenantFacilitySetup(ref.watch(appAccessPolicyProvider)),
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
      canPrint: canPrintTenantFacilitySetup(ref.watch(appAccessPolicyProvider)),
      printLabel: l10n.commonPrintActionLabel,
      onPrint: (List<TenantProfile> matching) =>
          printTenantFacilitySetupListTable<TenantProfile>(
        ref: ref,
        context: context,
        title: l10n.tenantFacilityManageTenantsTitle,
        columns: <AppListTableColumn<TenantProfile>>[
          AppListTableColumn<TenantProfile>(
            id: 'name',
            label: l10n.tenantFacilityTenantNameLabel,
            exportValue: (TenantProfile tenant) => tenant.name,
            cellBuilder: (_, TenantProfile tenant) =>
                tenantFacilitySetupAtomicCell(
                  tenant.name,
                  muted: tenant.isDeleted,
                ),
          ),
          AppListTableColumn<TenantProfile>(
            id: 'status',
            label: l10n.tenantFacilityTenantStatusLabel,
            exportValue: (TenantProfile tenant) =>
                _tenantStatusLabel(l10n, tenant),
            cellBuilder: (_, TenantProfile tenant) =>
                tenantFacilitySetupAtomicCell(_tenantStatusLabel(l10n, tenant)),
          ),
          AppListTableColumn<TenantProfile>(
            id: 'subscription_plan',
            label: l10n.tenantFacilityTenantSubscriptionPlanLabel,
            exportValue: (TenantProfile tenant) =>
                _tenantPackageLabel(l10n, tenant),
            cellBuilder: (_, TenantProfile tenant) =>
                tenantFacilitySetupAtomicCell(_tenantPackageLabel(l10n, tenant)),
          ),
          AppListTableColumn<TenantProfile>(
            id: 'subscription_start',
            label: l10n.tenantFacilityTenantSubscriptionStartLabel,
            exportValue: (TenantProfile tenant) =>
                _tenantSubscriptionStartLabel(l10n, locale, tenant),
            cellBuilder: (_, TenantProfile tenant) =>
                tenantFacilitySetupAtomicCell(
                  _tenantSubscriptionStartLabel(l10n, locale, tenant),
                ),
          ),
          AppListTableColumn<TenantProfile>(
            id: 'subscription_end',
            label: l10n.tenantFacilityTenantSubscriptionEndLabel,
            exportValue: (TenantProfile tenant) =>
                _tenantSubscriptionEndLabel(l10n, locale, tenant),
            cellBuilder: (_, TenantProfile tenant) =>
                tenantFacilitySetupAtomicCell(
                  _tenantSubscriptionEndLabel(l10n, locale, tenant),
                ),
          ),
          AppListTableColumn<TenantProfile>(
            id: 'id',
            label: l10n.tenantFacilityTenantDetailsIdLabel,
            exportValue: (TenantProfile tenant) =>
                tenantFacilityHumanFriendlyDisplayId(
                  tenant.displayId,
                  opaqueId: tenant.resourceUuid ?? tenant.id,
                ) ??
                '',
            cellBuilder: (_, TenantProfile tenant) =>
                tenantFacilitySetupAtomicCell(
                  tenantFacilityHumanFriendlyDisplayId(
                        tenant.displayId,
                        opaqueId: tenant.resourceUuid ?? tenant.id,
                      ) ??
                      l10n.profileUnknownValue,
                ),
          ),
          AppListTableColumn<TenantProfile>(
            id: 'slug',
            label: l10n.tenantFacilityTenantSlugLabel,
            exportValue: (TenantProfile tenant) => tenant.slug ?? '',
            cellBuilder: (_, TenantProfile tenant) =>
                tenantFacilitySetupAtomicCell(
                  tenant.slug?.trim().isNotEmpty == true
                      ? tenant.slug!
                      : l10n.profileUnknownValue,
                ),
          ),
        ],
        items: matching,
        emptyText: l10n.tenantFacilityNoTenants,
      ),
      goToTopLabel: l10n.commonGoToTopActionLabel,
      loadingMoreLabel: l10n.commonLoadingMoreLabel,
      allRowsLoadedLabel: l10n.commonAllRowsLoadedLabel,
      exportConfig: AppListTableExportConfig<TenantProfile>(
        fileNameStem: 'setup_tenants',
        dateOf: (_) => null,
        sheetName: l10n.tenantFacilityManageTenantsTitle,
        enableDateFilter: false,
        dateFromLabel: l10n.commonTableExportDateFromLabel,
        dateToLabel: l10n.commonTableExportDateToLabel,
      ),
      search: AppListTableSearch<TenantProfile>(
        controller: _searchController,
        hintText: l10n.tenantFacilitySearchLabel,
        semanticLabel: l10n.tenantFacilitySearchLabel,
        matcher: (_, _) => true,
        onSubmitted: (_) => unawaited(_reload(resetPage: true)),
        onClear: () => unawaited(_reload(resetPage: true)),
        enableDateFilter: false,
        showAdvancedFilterButton: true,
        advancedFilterButtonLabel: l10n.commonFiltersActionLabel,
        advancedFilterTitle: l10n.commonAdvancedFiltersTitle,
        advancedFilterApplyLabel: l10n.opdApplyFiltersAction,
        advancedFilterResetLabel: l10n.opdClearFiltersAction,
        advancedFilterCloseLabel: l10n.commonCloseActionLabel,
        filterGroups: <AppSearchBarFilterGroup>[
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
          AppSearchBarFilterGroup(
            key: _subscriptionFilterKey,
            label: l10n.tenantFacilityTenantSubscriptionFilterLabel,
            allLabel: l10n.commonAllLabel,
            choices: <AppSearchBarFilterChoice>[
              AppSearchBarFilterChoice(
                value: _subscriptionNone,
                label: l10n.tenantFacilityTenantSubscriptionFilterNone,
                icon: Icons.money_off_outlined,
              ),
              AppSearchBarFilterChoice(
                value: _subscriptionActive,
                label: l10n.tenantFacilityTenantSubscriptionFilterActive,
                icon: Icons.workspace_premium_outlined,
              ),
            ],
          ),
        ],
        filterValue: _filterValue,
        hasActiveFilters: hasActiveFilters,
        onFilterChanged: (AppSearchBarFilterValue value) {
          unawaited(_applyTenantFilters(value));
        },
        trailingActions: widget.showCreateAction && _canCreate
            ? <AppSearchBarAction>[
                AppSearchBarAction(
                  icon: Icons.add_business_outlined,
                  label: l10n.tenantFacilityAddTenantAction,
                  tooltip: l10n.tenantFacilityAddTenantAction,
                  onPressed: _loading
                      ? null
                      : () => unawaited(_openTenantForm(forceCreate: true)),
                ),
              ]
            : const <AppSearchBarAction>[],
      ),
      columns: <AppListTableColumn<TenantProfile>>[
        AppListTableColumn<TenantProfile>(
          id: 'name',
          label: l10n.tenantFacilityTenantNameLabel,
          preferredWidth: 220,
          sortComparator: (TenantProfile left, TenantProfile right) =>
              appListTableCompareText(left.name, right.name),
          exportValue: (TenantProfile tenant) => tenant.name,
          cellBuilder: (_, TenantProfile tenant) {
            return tenantFacilitySetupAtomicCell(
              tenant.name,
              muted: tenant.isDeleted,
            );
          },
        ),
        AppListTableColumn<TenantProfile>(
          id: 'status',
          label: l10n.tenantFacilityTenantStatusLabel,
          sortComparator: (TenantProfile left, TenantProfile right) =>
              appListTableCompareText(
                _tenantStatusLabel(l10n, left),
                _tenantStatusLabel(l10n, right),
              ),
          exportValue: (TenantProfile tenant) =>
              _tenantStatusLabel(l10n, tenant),
          cellBuilder: (_, TenantProfile tenant) =>
              tenantFacilitySetupAtomicCell(_tenantStatusLabel(l10n, tenant)),
        ),
        AppListTableColumn<TenantProfile>(
          id: 'subscription_plan',
          label: l10n.tenantFacilityTenantSubscriptionPlanLabel,
          preferredWidth: 160,
          sortComparator: (TenantProfile left, TenantProfile right) =>
              appListTableCompareText(
                left.subscription?.packageLabel,
                right.subscription?.packageLabel,
              ),
          exportValue: (TenantProfile tenant) =>
              _tenantPackageLabel(l10n, tenant),
          cellBuilder: (_, TenantProfile tenant) =>
              tenantFacilitySetupAtomicCell(
                _tenantPackageLabel(l10n, tenant),
                muted: tenant.subscription == null,
              ),
        ),
        AppListTableColumn<TenantProfile>(
          id: 'subscription_start',
          label: l10n.tenantFacilityTenantSubscriptionStartLabel,
          preferredWidth: 150,
          sortComparator: (TenantProfile left, TenantProfile right) =>
              appListTableCompareDateTime(
                left.subscription?.startDate,
                right.subscription?.startDate,
              ),
          exportValue: (TenantProfile tenant) =>
              _tenantSubscriptionStartLabel(l10n, locale, tenant),
          cellBuilder: (_, TenantProfile tenant) =>
              tenantFacilitySetupAtomicCell(
                _tenantSubscriptionStartLabel(l10n, locale, tenant),
                muted: tenant.subscription?.startDate == null,
              ),
        ),
        AppListTableColumn<TenantProfile>(
          id: 'subscription_end',
          label: l10n.tenantFacilityTenantSubscriptionEndLabel,
          preferredWidth: 150,
          sortComparator: (TenantProfile left, TenantProfile right) =>
              appListTableCompareDateTime(
                left.subscription?.endDate,
                right.subscription?.endDate,
              ),
          exportValue: (TenantProfile tenant) =>
              _tenantSubscriptionEndLabel(l10n, locale, tenant),
          cellBuilder: (_, TenantProfile tenant) =>
              tenantFacilitySetupAtomicCell(
                _tenantSubscriptionEndLabel(l10n, locale, tenant),
                muted: tenant.subscription?.endDate == null,
              ),
        ),
        if (_canEdit)
          AppListTableColumn<TenantProfile>(
            id: 'actions',
            label: l10n.accessAdminColumnActions,
            alwaysVisible: true,
            exportable: false,
            cellBuilder: (BuildContext context, TenantProfile tenant) {
              return _TenantManagementRowActions(
                enabled: !_loading,
                tenant: tenant,
                canDelete: _canDelete,
                editLabel: l10n.tenantFacilityEditAction,
                deleteLabel: l10n.tenantFacilityDeleteAction,
                restoreLabel: l10n.tenantFacilityRestoreTenantAction,
                permanentDeleteLabel: l10n.tenantFacilityPermanentDeleteAction,
                onEdit: () => unawaited(_openTenantForm(tenant: tenant)),
                onDelete: () => unawaited(_confirmDeleteTenant(tenant)),
                onRestore: () => unawaited(_confirmRestoreTenant(tenant)),
                onPermanentDelete: () =>
                    unawaited(_confirmPermanentDeleteTenant(tenant)),
              );
            },
          ),
      ],
      columnChoices: <AppListTableColumn<TenantProfile>>[
        AppListTableColumn<TenantProfile>(
          id: 'id',
          label: l10n.tenantFacilityTenantDetailsIdLabel,
          exportValue: (TenantProfile tenant) =>
              tenantFacilityHumanFriendlyDisplayId(
                tenant.displayId,
                opaqueId: tenant.resourceUuid ?? tenant.id,
              ) ??
              '',
          cellBuilder: (_, TenantProfile tenant) =>
              tenantFacilitySetupAtomicCell(
                tenantFacilityHumanFriendlyDisplayId(
                      tenant.displayId,
                      opaqueId: tenant.resourceUuid ?? tenant.id,
                    ) ??
                    l10n.profileUnknownValue,
              ),
        ),
        AppListTableColumn<TenantProfile>(
          id: 'slug',
          label: l10n.tenantFacilityTenantSlugLabel,
          sortComparator: (TenantProfile left, TenantProfile right) =>
              appListTableCompareText(left.slug, right.slug),
          exportValue: (TenantProfile tenant) => tenant.slug ?? '',
          cellBuilder: (_, TenantProfile tenant) =>
              tenantFacilitySetupAtomicCell(
                tenant.slug?.trim().isNotEmpty == true
                    ? tenant.slug!
                    : l10n.profileUnknownValue,
              ),
        ),
      ],
      emptyBuilder: (_) => AppWorkspaceStatePanel.empty(
        title: l10n.tenantFacilityManageTenantsTitle,
        body: l10n.tenantFacilityNoTenants,
        action: widget.showCreateAction && _canCreate
            ? AppButton.primary(
                label: l10n.tenantFacilityAddTenantAction,
                leadingIcon: Icons.add_business_outlined,
                enabled: !_loading,
                onPressed: _loading
                    ? null
                    : () => unawaited(_openTenantForm(forceCreate: true)),
              )
            : null,
      ),
      mobileItemBuilder: (BuildContext context, TenantProfile tenant) {
        final String? slug = tenant.slug?.trim();
        final String? displayId = tenantFacilityHumanFriendlyDisplayId(
          tenant.displayId,
          opaqueId: tenant.resourceUuid ?? tenant.id,
        );
        return AppListTableMobileItem(
          title: tenant.name,
          caption: displayId ?? (slug != null && slug.isNotEmpty ? slug : null),
          meta: <AppListTableMobileMeta>[
            AppListTableMobileMeta(label: _tenantStatusLabel(l10n, tenant)),
            AppListTableMobileMeta(label: _tenantPackageLabel(l10n, tenant)),
            if (tenant.subscription != null)
              AppListTableMobileMeta(
                label:
                    '${_tenantSubscriptionStartLabel(l10n, locale, tenant)} – ${_tenantSubscriptionEndLabel(l10n, locale, tenant)}',
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final Widget body = _isScopedTenantManager
        ? _buildScopedBody(l10n)
        : _buildTableBody(l10n);

    if (!widget.dialogMode) {
      return body;
    }

    return AppDialog(
      title: Text(
        _isScopedTenantManager
            ? l10n.tenantFacilityTenantDetailsTitle
            : l10n.tenantFacilityManageTenantsTitle,
      ),
      icon: const Icon(Icons.corporate_fare_outlined),
      pinActionsToBottom: true,
      maxWidth: 960,
      content: SizedBox(height: 520, child: body),
      actions: <Widget>[
        if (!_isScopedTenantManager && widget.showCreateAction && _canCreate)
          AppButton.primary(
            label: l10n.tenantFacilityAddTenantAction,
            leadingIcon: Icons.add_business_outlined,
            onPressed: _loading
                ? null
                : () => unawaited(_openTenantForm(forceCreate: true)),
          ),
        AppButton.secondary(
          label: l10n.commonCloseActionLabel,
          leadingIcon: Icons.close,
          onPressed: () => Navigator.of(context).pop(_mutated ? true : null),
        ),
      ],
    );
  }
}

class _TenantDetailsDialog extends ConsumerStatefulWidget {
  const _TenantDetailsDialog({required this.tenant});

  final TenantProfile tenant;

  @override
  ConsumerState<_TenantDetailsDialog> createState() =>
      _TenantDetailsDialogState();
}

class _TenantDetailsDialogState extends ConsumerState<_TenantDetailsDialog> {
  static const String _statusFilterKey = 'status';
  static const String _statusActive = 'active';
  static const String _statusDeleted = 'deleted';

  late TenantProfile _tenant;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  bool _loadingFacilities = true;
  AppFailure? _facilitiesFailure;
  AppPageRequest _pageRequest = PlatformAdminListConfig.initialPageRequest;
  int _totalItemCount = 0;
  List<FacilityProfile> _facilities = const <FacilityProfile>[];
  AppSearchBarFilterValue _filterValue = AppSearchBarFilterValue.empty;
  bool _summaryVisible = true;
  bool _mutated = false;
  int _reloadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _tenant = widget.tenant;
    _searchController.addListener(_onSearchChanged);
    unawaited(_loadFacilities());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool get _canManageTenant =>
      ref.read(appAccessPolicyProvider).canManageTenant();

  bool get _canDeleteTenant =>
      ref.read(appAccessPolicyProvider).canCreateTenant();

  bool get _canManageFacility =>
      ref.read(appAccessPolicyProvider).canManageFacility();

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_loadFacilities(resetPage: true));
    });
  }

  List<FacilityProfile> get _visibleFacilities {
    final String? status = _filterValue.option(_statusFilterKey);
    if (status == _statusActive) {
      return _facilities
          .where((FacilityProfile facility) => !facility.isDeleted)
          .toList(growable: false);
    }
    if (status == _statusDeleted) {
      return _facilities
          .where((FacilityProfile facility) => facility.isDeleted)
          .toList(growable: false);
    }
    return _facilities;
  }

  Future<void> _loadFacilities({
    bool silent = false,
    bool resetPage = false,
  }) async {
    if (resetPage) {
      _pageRequest = _pageRequest.first();
    }
    final int generation = ++_reloadGeneration;
    if (!silent) {
      setState(() {
        _loadingFacilities = true;
        _facilitiesFailure = null;
      });
    }

    final Result<AppPage<FacilityProfile>> result = await ref
        .read(tenantFacilityRepositoryProvider)
        .listFacilities(
          request: _pageRequest,
          tenantId: _tenant.mutationId,
          search: _searchController.text.trim(),
          includeDeleted: true,
        );

    if (!mounted || generation != _reloadGeneration) {
      return;
    }

    result.when(
      success: (AppPage<FacilityProfile> page) {
        setState(() {
          _loadingFacilities = false;
          _facilities = page.items;
          _totalItemCount = page.totalItemCount ?? page.items.length;
        });
      },
      failure: (AppFailure failure) {
        setState(() {
          _loadingFacilities = false;
          _facilitiesFailure = failure;
          if (!silent) {
            _facilities = const <FacilityProfile>[];
          }
        });
      },
    );
  }

  Future<void> _onPageChanged(AppPageRequest request) async {
    _pageRequest = request;
    await _loadFacilities();
  }

  String _tenantStatusLabel(AppLocalizations l10n) {
    if (_tenant.isDeleted) {
      return l10n.tenantFacilityTenantStatusDeleted;
    }
    return _tenant.isActive
        ? l10n.tenantFacilityTenantStatusActive
        : l10n.tenantFacilityStatusInactive;
  }

  AppWorkspaceStatusTone _tenantStatusTone() {
    if (_tenant.isDeleted) {
      return AppWorkspaceStatusTone.error;
    }
    return _tenant.isActive
        ? AppWorkspaceStatusTone.success
        : AppWorkspaceStatusTone.neutral;
  }

  String _facilityStatusLabel(AppLocalizations l10n, FacilityProfile facility) {
    if (facility.isDeleted) {
      return l10n.tenantFacilityTenantStatusDeleted;
    }
    return facility.isActive
        ? l10n.tenantFacilityTenantStatusActive
        : l10n.tenantFacilityStatusInactive;
  }

  Future<void> _editTenant() async {
    final bool wasActive = _tenant.isActive;
    final TenantProfile? savedTenant = await showTenantFacilityTenantFormDialog(
      context,
      tenant: _tenant,
      managementMode: true,
    );
    if (!mounted || savedTenant == null) {
      return;
    }

    _mutated = true;
    setState(() {
      _tenant = savedTenant.copyWith(
        resourceUuid: savedTenant.resourceUuid ?? _tenant.resourceUuid,
        displayId: savedTenant.displayId ?? _tenant.displayId,
        contactName: savedTenant.contactName ?? _tenant.contactName,
        contactEmail: savedTenant.contactEmail ?? _tenant.contactEmail,
        contactPhone: savedTenant.contactPhone ?? _tenant.contactPhone,
      );
    });
    if (savedTenant.isActive != wasActive) {
      _syncPlatformDashboard(
        ref,
        patch: HomeDashboardOptimisticPatch.tenantActiveChanged(
          wasActive: wasActive,
          isActive: savedTenant.isActive,
        ),
      );
    }
  }

  Future<void> _deleteTenant() async {
    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AppConfirmActionDialog(
        title: l10n.tenantFacilityDeleteConfirmationTitle,
        body: l10n.tenantFacilityDeleteTenantConfirmationBody(_tenant.name),
        highlightedText: _tenant.name,
        submitLabel: l10n.tenantFacilityDeleteConfirmAction,
        destructive: true,
        icon: const Icon(Icons.delete_outline),
        onConfirm: () async {
          final Result<void> result = await ref
              .read(tenantFacilityRepositoryProvider)
              .deleteTenant(_tenant.mutationId);
          return result.when(
            success: (_) => null,
            failure: (AppFailure failure) {
              if (failure.category == AppFailureCategory.notFound) {
                return null;
              }
              return failure;
            },
          );
        },
      ),
    );

    if (!mounted || confirmed != true) {
      return;
    }

    _syncPlatformDashboard(
      ref,
      patch: HomeDashboardOptimisticPatch.tenantDeleted(
        isActive: _tenant.isActive && !_tenant.isDeleted,
      ),
    );
    Navigator.of(context).pop(true);
  }

  Future<void> _openFacilityDetails(FacilityProfile facility) async {
    final bool? mutated = await showFacilityDetailsDialog(
      context,
      facility: facility,
      tenantName: _tenant.name,
    );
    if (!mounted || mutated != true) {
      return;
    }

    _mutated = true;
    await _loadFacilities(silent: true);
  }

  Future<void> _editFacility(FacilityProfile facility) async {
    final FacilityProfile? saved = await showTenantFacilityFacilityFormDialog(
      context,
      tenantId: _tenant.mutationId,
      facility: facility,
      managementMode: true,
    );
    if (!mounted || saved == null) {
      return;
    }

    _mutated = true;
    await _loadFacilities(silent: true);
  }

  Future<void> _deleteFacility(FacilityProfile facility) async {
    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AppConfirmActionDialog(
        title: l10n.tenantFacilityDeleteConfirmationTitle,
        body: l10n.tenantFacilityDeleteFacilityConfirmationBody(facility.name),
        highlightedText: facility.name,
        submitLabel: l10n.tenantFacilityDeleteConfirmAction,
        destructive: true,
        icon: const Icon(Icons.delete_outline),
        onConfirm: () async {
          final Result<void> result = await ref
              .read(tenantFacilityRepositoryProvider)
              .deleteFacility(facility.mutationId);
          return result.when(
            success: (_) => null,
            failure: (AppFailure failure) {
              if (failure.category == AppFailureCategory.notFound) {
                return null;
              }
              return failure;
            },
          );
        },
      ),
    );

    if (!mounted || confirmed != true) {
      return;
    }

    _mutated = true;
    final int index = _facilities.indexWhere(
      (FacilityProfile entry) =>
          entry.id == facility.id || entry.mutationId == facility.mutationId,
    );
    if (index >= 0) {
      final List<FacilityProfile> next = List<FacilityProfile>.of(_facilities);
      next[index] = facility.copyWith(deletedAt: DateTime.now().toUtc());
      setState(() {
        _facilities = next;
      });
    }
    _syncPlatformDashboard(
      ref,
      patch: HomeDashboardOptimisticPatch.facilityDeleted(
        isActive: facility.isActive && !facility.isDeleted,
      ),
    );
    unawaited(_loadFacilities(silent: true));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final bool canMutateTenant = _canManageTenant && !_tenant.isDeleted;
    final bool canDeleteTenant = _canDeleteTenant && !_tenant.isDeleted;
    final bool canMutateFacility = _canManageFacility && !_tenant.isDeleted;
    final bool canDeleteFacility =
        ref.read(appAccessPolicyProvider).canDeleteFacility() &&
        !_tenant.isDeleted;
    final List<FacilityProfile> visibleFacilities = _visibleFacilities;
    final bool hasActiveFilters = _filterValue.option(_statusFilterKey) != null;

    return AppDialog(
      title: Text(l10n.tenantFacilityTenantDetailsTitle),
      icon: const Icon(Icons.apartment_outlined),
      pinActionsToBottom: true,
      maxWidth: 1040,
      content: SizedBox(
        height: 560,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool wide = constraints.maxWidth >= 720;
            final Widget facilitiesPanel = _TenantDetailsFacilitiesPanel(
              searchController: _searchController,
              loading: _loadingFacilities,
              failure: _facilitiesFailure,
              facilities: visibleFacilities,
              pageRequest: _pageRequest,
              totalItemCount: hasActiveFilters
                  ? visibleFacilities.length
                  : _totalItemCount,
              canManage: canMutateFacility,
              canDelete: canDeleteFacility,
              summaryVisible: _summaryVisible,
              filterValue: _filterValue,
              hasActiveFilters: hasActiveFilters,
              statusLabelBuilder: (FacilityProfile facility) =>
                  _facilityStatusLabel(l10n, facility),
              onRetry: () => unawaited(_loadFacilities()),
              onPageChanged: _onPageChanged,
              onFilterChanged: (AppSearchBarFilterValue value) {
                setState(() => _filterValue = value);
              },
              onShowSummary: () => setState(() => _summaryVisible = true),
              onRowSelected: (FacilityProfile facility) {
                if (facility.isDeleted) {
                  return;
                }
                unawaited(_openFacilityDetails(facility));
              },
              onEdit: (FacilityProfile facility) =>
                  unawaited(_editFacility(facility)),
              onDelete: (FacilityProfile facility) =>
                  unawaited(_deleteFacility(facility)),
            );

            if (!_summaryVisible) {
              return facilitiesPanel;
            }

            final Widget tenantSummary = _TenantDetailsSummary(
              tenant: _tenant,
              statusLabel: _tenantStatusLabel(l10n),
              statusTone: _tenantStatusTone(),
              onHide: () => setState(() => _summaryVisible = false),
            );

            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(width: 320, child: tenantSummary),
                  VerticalDivider(
                    width: theme.spacing.md,
                    thickness: 1,
                    color: theme.borders.faint,
                  ),
                  Expanded(child: facilitiesPanel),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: math.max(220, constraints.maxHeight * 0.42),
                  ),
                  child: tenantSummary,
                ),
                SizedBox(height: theme.spacing.md),
                Expanded(child: facilitiesPanel),
              ],
            );
          },
        ),
      ),
      actions: <Widget>[
        if (canMutateTenant)
          AppButton.secondary(
            label: l10n.tenantFacilityEditTenantAction,
            leadingIcon: Icons.edit_outlined,
            onPressed: () => unawaited(_editTenant()),
          ),
        if (canDeleteTenant)
          AppButton.primary(
            label: l10n.tenantFacilityDeleteTenantAction,
            leadingIcon: Icons.delete_outline,
            color: colorScheme.error,
            onPressed: () => unawaited(_deleteTenant()),
          ),
        AppButton.secondary(
          label: l10n.commonCloseActionLabel,
          leadingIcon: Icons.close,
          onPressed: () => Navigator.of(context).pop(_mutated ? true : null),
        ),
      ],
    );
  }
}

class _TenantDetailsSummary extends StatelessWidget {
  const _TenantDetailsSummary({
    required this.tenant,
    required this.statusLabel,
    required this.statusTone,
    this.onHide,
    this.onEdit,
    this.editLabel,
  });

  final TenantProfile tenant;
  final String statusLabel;
  final AppWorkspaceStatusTone statusTone;
  final VoidCallback? onHide;
  final Future<void> Function()? onEdit;
  final String? editLabel;

  String _initials(String name) {
    final List<String> parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final VoidCallback? hideAction = onHide;
    final Future<void> Function()? editAction = onEdit;
    final String? resolvedEditLabel = editLabel;
    final String emptyValue = l10n.profileUnknownValue;
    final Set<String> emptyPlaceholders = <String>{emptyValue, '—'};
    final String? slug = tenant.slug?.trim();
    final bool showSlug = slug != null && slug.isNotEmpty;

    final List<Widget> headerActions = <Widget>[
      if (editAction != null &&
          resolvedEditLabel != null &&
          resolvedEditLabel.isNotEmpty)
        AppButton.secondary(
          label: resolvedEditLabel,
          leadingIcon: Icons.edit_outlined,
          onPressed: () {
            unawaited(editAction());
          },
        ),
      if (hideAction != null)
        AppButton.tertiary(
          label: l10n.tenantFacilityTenantDetailsHideSummaryAction,
          leadingIcon: Icons.visibility_off_outlined,
          onPressed: hideAction,
        ),
    ];

    Widget section({
      required String title,
      required IconData icon,
      required List<AppInfoSheetItem> items,
      int maxColumns = 3,
    }) {
      return AppCollapsibleSection(
        title: title,
        titleIcon: icon,
        child: AppInfoSheetGrid(
          emptyValue: emptyValue,
          maxColumns: maxColumns,
          items: items,
        ),
      );
    }

    final Widget sections = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: appCollapsibleSectionSpacing(context, <Widget>[
        AppCollapsibleSection(
          collapsible: false,
          headerActions: headerActions,
          titleWidget: Row(
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: theme.borders.all(
                    color: colorScheme.primary.withValues(alpha: 0.22),
                  ),
                ),
                child: SizedBox.square(
                  dimension: 44,
                  child: Center(
                    child: Text(
                      _initials(tenant.name),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: AppFontWeight.emphasis,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: theme.spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      tenant.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: AppFontWeight.strong,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (showSlug) ...<Widget>[
                      SizedBox(height: theme.spacing.xs / 2),
                      Text(
                        slug,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: _TenantStatusBadge(label: statusLabel, tone: statusTone),
          ),
        ),
        section(
          title: l10n.hrStaffOverviewSectionTitle,
          icon: Icons.info_outline,
          items: <AppInfoSheetItem>[
            AppInfoSheetItem(
              label: l10n.tenantFacilityTenantSlugLabel,
              value: tenant.slug,
              copyable: true,
              copyTooltip: l10n.copyIdentifierAction,
              copiedMessage: l10n.identifierCopiedMessage,
              copyPlaceholderValues: emptyPlaceholders,
            ),
            AppInfoSheetItem(
              label: l10n.tenantFacilityTenantDetailsIdLabel,
              value: tenant.displayId,
              copyable: true,
              copyTooltip: l10n.copyIdentifierAction,
              copiedMessage: l10n.identifierCopiedMessage,
              copyPlaceholderValues: emptyPlaceholders,
            ),
            AppInfoSheetItem(
              label: l10n.tenantFacilityTenantStatusLabel,
              value: statusLabel,
            ),
          ],
        ),
        section(
          title: l10n.tenantFacilityFacilityDetailsContactHeading,
          icon: Icons.contact_mail_outlined,
          items: <AppInfoSheetItem>[
            AppInfoSheetItem(
              label: l10n.tenantFacilityTenantDetailsContactNameLabel,
              value: tenant.contactName,
            ),
            AppInfoSheetItem(
              label: l10n.profilePhoneLabel,
              value: tenant.contactPhone,
            ),
            AppInfoSheetItem(
              label: l10n.profileEmailLabel,
              value: tenant.contactEmail,
            ),
          ],
        ),
        section(
          title: l10n.settingsConfigurationTenantTitle,
          icon: Icons.tune_outlined,
          maxColumns: 2,
          items: <AppInfoSheetItem>[
            AppInfoSheetItem(
              label: l10n.tenantFacilityDefaultCurrencyLabel,
              value: resolveDefaultCurrency(tenantCurrency: tenant.currency),
            ),
            AppInfoSheetItem(
              label: l10n.settingsConfigurationConsultationFeeLabel,
              value: () {
                final String feeAmount = resolveDefaultConsultationFee(
                  fee: tenant.standardConsultationFee,
                );
                final num? parsed = num.tryParse(
                  normalizeCurrencyAmount(feeAmount),
                );
                final String formatted = parsed == null
                    ? feeAmount
                    : formatCurrencyAmountInput(parsed);
                return '${resolveDefaultCurrency(tenantCurrency: tenant.currency)} $formatted';
              }(),
            ),
          ],
        ),
      ]),
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (!constraints.hasBoundedHeight) {
          return sections;
        }
        return SingleChildScrollView(child: sections);
      },
    );
  }
}

class _TenantStatusBadge extends StatelessWidget {
  const _TenantStatusBadge({required this.label, required this.tone});

  final String label;
  final AppWorkspaceStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final Color foreground = switch (tone) {
      AppWorkspaceStatusTone.success => colorScheme.primary,
      AppWorkspaceStatusTone.error => colorScheme.error,
      AppWorkspaceStatusTone.warning => colorScheme.tertiary,
      AppWorkspaceStatusTone.info => colorScheme.secondary,
      AppWorkspaceStatusTone.neutral => colorScheme.onSurfaceVariant,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.12),
        borderRadius: BorderRadius.zero,
        border: theme.borders.all(color: foreground.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: foreground,
            fontWeight: AppFontWeight.emphasis,
          ),
        ),
      ),
    );
  }
}

class _TenantDetailsFacilitiesPanel extends StatelessWidget {
  const _TenantDetailsFacilitiesPanel({
    required this.searchController,
    required this.loading,
    required this.failure,
    required this.facilities,
    required this.pageRequest,
    required this.totalItemCount,
    required this.canManage,
    required this.canDelete,
    required this.summaryVisible,
    required this.filterValue,
    required this.hasActiveFilters,
    required this.statusLabelBuilder,
    required this.onRetry,
    required this.onPageChanged,
    required this.onFilterChanged,
    required this.onShowSummary,
    required this.onRowSelected,
    required this.onEdit,
    required this.onDelete,
  });

  final TextEditingController searchController;
  final bool loading;
  final AppFailure? failure;
  final List<FacilityProfile> facilities;
  final AppPageRequest pageRequest;
  final int totalItemCount;
  final bool canManage;
  final bool canDelete;
  final bool summaryVisible;
  final AppSearchBarFilterValue filterValue;
  final bool hasActiveFilters;
  final String Function(FacilityProfile facility) statusLabelBuilder;
  final VoidCallback onRetry;
  final Future<void> Function(AppPageRequest request) onPageChanged;
  final ValueChanged<AppSearchBarFilterValue> onFilterChanged;
  final VoidCallback onShowSummary;
  final ValueChanged<FacilityProfile> onRowSelected;
  final ValueChanged<FacilityProfile> onEdit;
  final ValueChanged<FacilityProfile> onDelete;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String showLabel = l10n.tenantFacilityTenantDetailsShowSummaryAction;

    return AppCollapsibleSection(
      title: l10n.tenantFacilityTenantDetailsFacilitiesHeading,
      actions: <Widget>[
        if (!summaryVisible)
          IconButton(
            tooltip: showLabel,
            visualDensity: VisualDensity.compact,
            onPressed: onShowSummary,
            icon: const Icon(Icons.visibility_outlined),
          ),
      ],
      child: SizedBox(
        height: math.max(320, MediaQuery.sizeOf(context).height * 0.45),
        child: failure != null
            ? AppFailureStateView(failure: failure!, onRetry: onRetry)
            : AppListTable<FacilityProfile>(
                page: AppPage<FacilityProfile>(
                  items: facilities,
                  request: pageRequest,
                  totalItemCount: totalItemCount,
                ),
                isLoading: loading,
                itemKeyBuilder: (FacilityProfile item) =>
                    ValueKey<String>(item.id),
                onRowSelected: onRowSelected,
                initialSortColumnKey: 'name',
                previousPageLabel: l10n.hrPreviousPageLabel,
                nextPageLabel: l10n.hrNextPageLabel,
                pageLabelBuilder: (AppPage<FacilityProfile> page) {
                  if (loading) {
                    return '';
                  }
                  final int total = page.totalItemCount ?? page.items.length;
                  if (total == 0) {
                    return l10n.commonTableEmptyLabel;
                  }
                  final int start = page.pageIndex * page.pageSize + 1;
                  final int end = start + page.items.length - 1;
                  return '$start-$end / $total';
                },
                onPageChanged: onPageChanged,
                columnVisibilityStorageKey:
                    'setup_tenant_details_facilities_v1',
                columnVisibilityLabel: l10n.commonTableSettingsActionLabel,
                columnVisibilityTitle: l10n.commonTableSettingsTitle,
                columnVisibilityApplyLabel: l10n.receptionApplyColumnsAction,
                columnVisibilityResetLabel: l10n.receptionResetColumnsAction,
                columnVisibilityCloseLabel: l10n.commonCloseActionLabel,
                search: AppListTableSearch<FacilityProfile>(
                  controller: searchController,
                  hintText: l10n.tenantFacilitySearchLabel,
                  semanticLabel: l10n.tenantFacilitySearchLabel,
                  matcher: (_, _) => true,
                  enableDateFilter: false,
                  showAdvancedFilterButton: true,
                  advancedFilterButtonLabel: l10n.commonFiltersActionLabel,
                  advancedFilterTitle: l10n.commonAdvancedFiltersTitle,
                  advancedFilterApplyLabel: l10n.opdApplyFiltersAction,
                  advancedFilterResetLabel: l10n.opdClearFiltersAction,
                  advancedFilterCloseLabel: l10n.commonCloseActionLabel,
                  filterGroups: <AppSearchBarFilterGroup>[
                    AppSearchBarFilterGroup(
                      key: _TenantDetailsDialogState._statusFilterKey,
                      label: l10n.tenantFacilityTenantStatusLabel,
                      allLabel: l10n.commonAllLabel,
                      choices: <AppSearchBarFilterChoice>[
                        AppSearchBarFilterChoice(
                          value: _TenantDetailsDialogState._statusActive,
                          label: l10n.tenantFacilityTenantStatusActive,
                          icon: Icons.check_circle_outline,
                        ),
                        AppSearchBarFilterChoice(
                          value: _TenantDetailsDialogState._statusDeleted,
                          label: l10n.tenantFacilityTenantStatusDeleted,
                          icon: Icons.delete_outline,
                        ),
                      ],
                    ),
                  ],
                  filterValue: filterValue,
                  hasActiveFilters: hasActiveFilters,
                  onFilterChanged: onFilterChanged,
                ),
                columns: <AppListTableColumn<FacilityProfile>>[
                  AppListTableColumn<FacilityProfile>(
                    id: 'name',
                    label: l10n.authFacilityNameLabel,
                    sortComparator:
                        (FacilityProfile left, FacilityProfile right) => left
                            .name
                            .toLowerCase()
                            .compareTo(right.name.toLowerCase()),
                    cellBuilder: (_, FacilityProfile facility) =>
                        tenantFacilitySetupAtomicCell(
                          facility.name,
                          muted: facility.isDeleted,
                        ),
                  ),
                  AppListTableColumn<FacilityProfile>(
                    id: 'type',
                    label: l10n.profileFacilityTypeLabel,
                    sortComparator:
                        (FacilityProfile left, FacilityProfile right) =>
                            left.type.name.compareTo(right.type.name),
                    cellBuilder: (_, FacilityProfile facility) =>
                        tenantFacilitySetupAtomicCell(
                          tenantFacilityFacilityTypeLabel(l10n, facility.type),
                        ),
                  ),
                  AppListTableColumn<FacilityProfile>(
                    id: 'status',
                    label: l10n.tenantFacilityTenantStatusLabel,
                    sortComparator:
                        (FacilityProfile left, FacilityProfile right) =>
                            statusLabelBuilder(
                              left,
                            ).compareTo(statusLabelBuilder(right)),
                    cellBuilder: (_, FacilityProfile facility) =>
                        tenantFacilitySetupAtomicCell(
                          statusLabelBuilder(facility),
                        ),
                  ),
                  if (canManage)
                    AppListTableColumn<FacilityProfile>(
                      id: 'actions',
                      label: l10n.accessAdminColumnActions,
                      alwaysVisible: true,
                      exportable: false,
                      cellBuilder:
                          (BuildContext context, FacilityProfile facility) {
                            if (facility.isDeleted) {
                              return const SizedBox.shrink();
                            }
                            return GestureDetector(
                              onTap: () {},
                              child: _ManagementRowActions(
                                enabled: !loading,
                                canDelete: canDelete,
                                editLabel: l10n.tenantFacilityEditAction,
                                deleteLabel: l10n.tenantFacilityDeleteAction,
                                onEdit: () => onEdit(facility),
                                onDelete: () => onDelete(facility),
                              ),
                            );
                          },
                    ),
                ],
                emptyBuilder: (_) => AppWorkspaceStatePanel.empty(
                  title: l10n.tenantFacilityTenantDetailsFacilitiesHeading,
                  body: l10n.tenantFacilityTenantDetailsNoFacilities,
                ),
                mobileItemBuilder:
                    (BuildContext context, FacilityProfile facility) {
                      return AppListTableMobileItem(
                        title: facility.name,
                        meta: <AppListTableMobileMeta>[
                          AppListTableMobileMeta(
                            label: statusLabelBuilder(facility),
                          ),
                          AppListTableMobileMeta(
                            label: facility.type.name,
                            icon: Icons.business_outlined,
                          ),
                        ],
                      );
                    },
              ),
      ),
    );
  }
}

class _ManagementRowActions extends StatelessWidget {
  const _ManagementRowActions({
    required this.enabled,
    required this.editLabel,
    required this.deleteLabel,
    required this.onEdit,
    required this.onDelete,
    this.canDelete = true,
  });

  final bool enabled;
  final bool canDelete;
  final String editLabel;
  final String deleteLabel;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Wrap(
      spacing: theme.spacing.md,
      runSpacing: theme.spacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        AppButton.tertiary(
          leadingIcon: Icons.edit_outlined,
          label: editLabel,
          semanticLabel: editLabel,
          tooltip: editLabel,
          enabled: enabled,
          onPressed: enabled ? onEdit : null,
        ),
        if (canDelete)
          AppButton.tertiary(
            leadingIcon: Icons.delete_outline,
            label: deleteLabel,
            semanticLabel: deleteLabel,
            tooltip: deleteLabel,
            color: colorScheme.error,
            enabled: enabled,
            onPressed: enabled ? onDelete : null,
          ),
      ],
    );
  }
}

enum _FacilityDetailsPanel { users, departments, units, wards, rooms, beds }

class _FacilityDetailsDialog extends ConsumerStatefulWidget {
  const _FacilityDetailsDialog({required this.facility, this.tenantName});

  final FacilityProfile facility;
  final String? tenantName;

  @override
  ConsumerState<_FacilityDetailsDialog> createState() =>
      _FacilityDetailsDialogState();
}

class _FacilityDetailsDialogState
    extends ConsumerState<_FacilityDetailsDialog> {
  late FacilityProfile _facility;
  FacilitySetupSnapshot? _snapshot;
  final TextEditingController _usersSearchController = TextEditingController();
  Timer? _usersSearchDebounce;
  _FacilityDetailsPanel _selectedPanel = _FacilityDetailsPanel.users;
  bool _loadingOverview = true;
  bool _loadingUsers = true;
  AppFailure? _overviewFailure;
  AppFailure? _usersFailure;
  AppPageRequest _pageRequest = PlatformAdminListConfig.initialPageRequest;
  int _totalUserCount = 0;
  List<AccessAdminItem> _users = const <AccessAdminItem>[];
  bool _mutated = false;
  int _usersReloadGeneration = 0;
  int _overviewReloadGeneration = 0;
  bool _logoBusy = false;
  PlatformManagementListSync? _structureRealtimeSync;

  @override
  void initState() {
    super.initState();
    _facility = widget.facility;
    _usersSearchController.addListener(_onUsersSearchChanged);
    unawaited(_loadOverview());
    unawaited(_loadUsers());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _structureRealtimeSync ??= PlatformManagementListSync(
      ref: ref,
      events: <String>{
        // Inherited phone/email follow tenant contact changes.
        RealtimeEvents.tenantUpdated,
        RealtimeEvents.facilityUpdated,
        RealtimeEvents.facilityLayoutUpdated,
        RealtimeEvents.userCreated,
        RealtimeEvents.userUpdated,
        RealtimeEvents.userDeleted,
        RealtimeEvents.userRestored,
        RealtimeEvents.userPermanentlyDeleted,
      },
      onMutated: () => _mutated = true,
      reload: ({bool silent = false, RealtimeMessage? message}) async {
        await _loadOverview(silent: true);
        if (_selectedPanel == _FacilityDetailsPanel.users) {
          await _loadUsers(silent: true);
        }
      },
    )..attach();
  }

  @override
  void dispose() {
    _structureRealtimeSync?.dispose();
    _usersSearchDebounce?.cancel();
    _usersSearchController.dispose();
    super.dispose();
  }

  bool get _canManageFacility =>
      ref.read(appAccessPolicyProvider).canManageFacility();

  bool get _canDeleteFacility =>
      ref.read(appAccessPolicyProvider).canDeleteFacility();

  bool get _canEditStructure =>
      ref.read(appAccessPolicyProvider).canEditFacilitySetupStructure();

  bool get _canRestoreFacility =>
      ref.read(appAccessPolicyProvider).canManageFacility() &&
      _facility.isDeleted;

  bool get _canPermanentDeleteFacility =>
      ref.read(appAccessPolicyProvider).canDeleteFacility() &&
      _facility.isDeleted;

  bool get _canMutate => _canManageFacility && !_facility.isDeleted;

  bool get _canDelete => _canDeleteFacility && !_facility.isDeleted;

  bool get _canMutateStructure => _canEditStructure && !_facility.isDeleted;

  String get _tenantLabel {
    final String? fromWidget = widget.tenantName?.trim();
    if (fromWidget != null && fromWidget.isNotEmpty) {
      return fromWidget;
    }
    final String? fromSnapshot = _snapshot?.tenant?.name.trim();
    if (fromSnapshot != null && fromSnapshot.isNotEmpty) {
      return fromSnapshot;
    }
    return '—';
  }

  FacilitySetupSnapshot get _effectiveSnapshot {
    final FacilitySetupSnapshot base =
        _snapshot ?? FacilitySetupSnapshot(facility: _facility);
    final FacilityProfile facility = base.facility ?? _facility;
    final TenantProfile tenant =
        base.tenant ?? TenantProfile(id: facility.tenantId, name: _tenantLabel);
    if (identical(base.facility, facility) && identical(base.tenant, tenant)) {
      return base;
    }
    return base.copyWith(tenant: tenant, facility: facility);
  }

  void _onUsersSearchChanged() {
    _usersSearchDebounce?.cancel();
    _usersSearchDebounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_loadUsers(resetPage: true));
    });
  }

  void _selectPanel(_FacilityDetailsPanel panel) {
    if (_selectedPanel == panel) {
      return;
    }
    setState(() {
      _selectedPanel = panel;
    });
    if (panel == _FacilityDetailsPanel.users) {
      unawaited(_loadUsers(resetPage: true));
    }
  }

  Future<void> _loadOverview({bool silent = false}) async {
    final int generation = ++_overviewReloadGeneration;
    if (!silent) {
      setState(() {
        _loadingOverview = true;
        _overviewFailure = null;
      });
    }

    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );

    final Result<FacilityProfile> facilityResult = await repository.getFacility(
      _facility.mutationId,
    );
    if (!mounted || generation != _overviewReloadGeneration) {
      return;
    }

    facilityResult.when(
      success: (FacilityProfile facility) {
        _facility = facility;
      },
      failure: (_) {},
    );

    final Result<FacilitySetupSnapshot> setupResult = await repository
        .loadSetup(
          facilityId: _facility.mutationId,
          tenantId: _facility.tenantId,
          includeDeleted: true,
        );
    if (!mounted || generation != _overviewReloadGeneration) {
      return;
    }

    setupResult.when(
      success: (FacilitySetupSnapshot snapshot) {
        setState(() {
          _loadingOverview = false;
          _snapshot = snapshot;
          if (snapshot.facility != null) {
            _facility = snapshot.facility!;
          }
        });
      },
      failure: (AppFailure failure) {
        setState(() {
          _loadingOverview = false;
          _overviewFailure = failure;
        });
      },
    );
  }

  Future<void> _loadUsers({bool silent = false, bool resetPage = false}) async {
    if (resetPage) {
      _pageRequest = _pageRequest.first();
    }
    final int generation = ++_usersReloadGeneration;
    if (!silent) {
      setState(() {
        _loadingUsers = true;
        _usersFailure = null;
      });
    }

    final AccessAdminRepository repository = ref.read(
      accessAdminRepositoryProvider,
    );
    final Result<AccessAdminWorkspaceData> result = await repository
        .getWorkspace(
          AccessAdminWorkspaceQuery(
            tenantId: _facility.tenantId,
            facilityId: _facility.mutationId,
            search: _usersSearchController.text.trim(),
            pageRequest: _pageRequest,
            includeDeleted: true,
          ),
        );

    if (!mounted || generation != _usersReloadGeneration) {
      return;
    }

    result.when(
      success: (AccessAdminWorkspaceData data) {
        setState(() {
          _loadingUsers = false;
          _users = data.page.items;
          _totalUserCount = data.page.totalItemCount ?? data.page.items.length;
        });
      },
      failure: (AppFailure failure) {
        setState(() {
          _loadingUsers = false;
          _usersFailure = failure;
          if (!silent) {
            _users = const <AccessAdminItem>[];
          }
        });
      },
    );
  }

  Future<void> _onUsersPageChanged(AppPageRequest request) async {
    _pageRequest = request;
    await _loadUsers();
  }

  AccessAdminWorkspaceState _usersWorkspaceState() {
    final AccessAdminWorkspaceQuery query = AccessAdminWorkspaceQuery(
      tenantId: _facility.tenantId,
      facilityId: _facility.mutationId,
      search: _usersSearchController.text.trim(),
      pageRequest: _pageRequest,
      includeDeleted: true,
    );
    return AccessAdminWorkspaceState(
      data: AccessAdminWorkspaceData(
        items: _users,
        page: AppPage<AccessAdminItem>(
          items: _users,
          request: _pageRequest,
          totalItemCount: _totalUserCount,
        ),
        query: query,
      ),
      query: query,
    );
  }

  Future<void> _afterStructureMutation() async {
    _mutated = true;
    await _loadOverview(silent: true);
    if (_selectedPanel == _FacilityDetailsPanel.users && mounted) {
      await _loadUsers(silent: true);
    }
  }

  Future<void> _createUser() async {
    final AccessAdminItem? created = await openAccessAdminCreateUserDialog(
      context,
      ref,
      _usersWorkspaceState(),
    );
    if (!mounted || created == null) {
      return;
    }
    _mutated = true;
    await _loadUsers(resetPage: true, silent: true);
  }

  Future<void> _editUser(AccessAdminItem user) async {
    if (user.isDeleted) {
      return;
    }
    final AccessAdminRepository repository = ref.read(
      accessAdminRepositoryProvider,
    );
    final Result<AccessAdminUserDetail> detailResult = await repository
        .getUserDetail(
          user.id,
          tenantId: _facility.tenantId,
          facilityId: _facility.mutationId,
        );
    if (!mounted) {
      return;
    }
    final AccessAdminUserDetail? detail = detailResult.when(
      success: (AccessAdminUserDetail value) => value,
      failure: (_) => null,
    );
    if (detail == null) {
      return;
    }
    final AccessAdminItem? updated = await openAccessAdminEditUserDialog(
      context,
      ref,
      _usersWorkspaceState(),
      user: detail.item,
      detail: detail,
    );
    if (!mounted || updated == null) {
      return;
    }
    _mutated = true;
    await _loadUsers(silent: true);
  }

  Future<void> _deleteUser(AccessAdminItem user) async {
    if (user.isDemo || user.isSystemCritical || user.isDeleted) {
      return;
    }
    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AppConfirmActionDialog(
        title: l10n.tenantFacilitySoftDeleteUserTitle,
        body: l10n.tenantFacilitySoftDeleteUserBody(user.title),
        highlightedText: user.title,
        submitLabel: l10n.tenantFacilityDeleteConfirmAction,
        destructive: true,
        icon: const Icon(Icons.delete_outline),
        onConfirm: () async {
          final Result<void> result = await ref
              .read(accessAdminRepositoryProvider)
              .deleteUser(user.mutationId);
          return result.when(
            success: (_) => null,
            failure: (AppFailure failure) => failure,
          );
        },
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }
    _mutated = true;
    await _loadUsers(resetPage: _users.length <= 1, silent: true);
  }

  Future<void> _restoreUser(AccessAdminItem user) async {
    if (!user.isDeleted) {
      return;
    }
    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AppConfirmActionDialog(
        title: l10n.tenantFacilityRestoreUserTitle,
        body: l10n.tenantFacilityRestoreUserBody(user.title),
        highlightedText: user.title,
        submitLabel: l10n.accessAdminRestoreUserAction,
        icon: const Icon(Icons.restore_outlined),
        onConfirm: () async {
          final Result<void> result = await ref
              .read(accessAdminRepositoryProvider)
              .restoreUser(user.mutationId);
          return result.when(
            success: (_) => null,
            failure: (AppFailure failure) => failure,
          );
        },
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }
    _mutated = true;
    await _loadUsers(silent: true);
  }

  Future<void> _openDepartmentForm({DepartmentProfile? department}) async {
    if (department != null && department.isDeleted) {
      return;
    }
    await showTenantFacilityDepartmentFormDialog(
      context,
      _effectiveSnapshot,
      department: department,
    );
    if (!mounted) {
      return;
    }
    await _afterStructureMutation();
  }

  Future<void> _openUnitForm({UnitProfile? unit}) async {
    if (unit != null && unit.isDeleted) {
      return;
    }
    await showTenantFacilityUnitFormDialog(
      context,
      _effectiveSnapshot,
      unit: unit,
    );
    if (!mounted) {
      return;
    }
    await _afterStructureMutation();
  }

  Future<void> _openWardForm({WardProfile? ward}) async {
    if (ward != null && ward.isDeleted) {
      return;
    }
    await showTenantFacilityWardFormDialog(
      context,
      _effectiveSnapshot,
      ward: ward,
    );
    if (!mounted) {
      return;
    }
    await _afterStructureMutation();
  }

  Future<void> _openRoomForm({RoomProfile? room}) async {
    if (room != null && room.isDeleted) {
      return;
    }
    await showTenantFacilityRoomFormDialog(
      context,
      _effectiveSnapshot,
      room: room,
    );
    if (!mounted) {
      return;
    }
    await _afterStructureMutation();
  }

  Future<void> _openBedForm({BedProfile? bed}) async {
    if (bed != null && bed.isDeleted) {
      return;
    }
    await showTenantFacilityBedFormDialog(
      context,
      _effectiveSnapshot,
      bed: bed,
    );
    if (!mounted) {
      return;
    }
    await _afterStructureMutation();
  }

  Future<void> _confirmDeleteStructure({
    required String name,
    required Future<bool> Function() deleteAction,
  }) async {
    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showAppDialog<bool>(
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
    if (!mounted || confirmed != true) {
      return;
    }
    await _afterStructureMutation();
  }

  Future<void> _confirmRestoreStructure({
    required String name,
    required Future<bool> Function() restoreAction,
  }) async {
    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showAppDialog<bool>(
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
    if (!mounted || confirmed != true) {
      return;
    }
    await _afterStructureMutation();
  }

  String _facilityStatusLabel(AppLocalizations l10n) {
    if (_facility.isDeleted) {
      return l10n.tenantFacilityTenantStatusDeleted;
    }
    return _facility.isActive
        ? l10n.tenantFacilityTenantStatusActive
        : l10n.commonNoLabel;
  }

  AppWorkspaceStatusTone _facilityStatusTone() {
    if (_facility.isDeleted) {
      return AppWorkspaceStatusTone.error;
    }
    return _facility.isActive
        ? AppWorkspaceStatusTone.success
        : AppWorkspaceStatusTone.neutral;
  }

  Future<void> _editFacility() async {
    final FacilityProfile? saved = await showTenantFacilityFacilityFormDialog(
      context,
      tenantId: _facility.tenantId,
      facility: _facility,
      managementMode: true,
    );
    if (!mounted || saved == null) {
      return;
    }

    _mutated = true;
    await _loadOverview(silent: true);
    await _loadUsers(silent: true);
  }

  Future<void> _addOrChangeLogo() async {
    if (!_canMutate || _logoBusy) {
      return;
    }
    final AppLocalizations l10n = context.l10n;
    final AppImageUploadPendingItem? picked = await pickAppImageFile(
      l10n,
      context: context,
      typeGroupLabel: 'facility-logo',
      showCropAspectPresets: true,
      preferredFileName: buildFacilityLogoFileName(_facility.name),
    );
    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _logoBusy = true;
    });
    final Result<String> result = await ref
        .read(tenantFacilityRepositoryProvider)
        .uploadFacilityLogo(
          facilityId: _facility.mutationId,
          bytes: picked.bytes,
          fileName: picked.fileName,
          mimeType: picked.mimeType,
        );
    if (!mounted) {
      return;
    }

    result.when(
      success: (String logoUrl) {
        setState(() {
          _logoBusy = false;
          _facility = _facility.copyWith(logoUrl: logoUrl);
          _mutated = true;
          if (_snapshot?.facility != null) {
            _snapshot = _snapshot!.copyWith(
              facility: _snapshot!.facility!.copyWith(logoUrl: logoUrl),
            );
          }
        });
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(l10n.tenantFacilityDetailsLogoUpdatedMessage),
            ),
          );
      },
      failure: (AppFailure failure) {
        setState(() {
          _logoBusy = false;
        });
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(l10n.failureMessage(failure))));
      },
    );
  }

  Future<void> _removeLogo() async {
    if (!_canMutate || _logoBusy) {
      return;
    }
    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AppConfirmActionDialog(
        title: l10n.tenantFacilityDetailsRemoveLogoTitle,
        body: l10n.tenantFacilityDetailsRemoveLogoBody(_facility.name),
        highlightedText: _facility.name,
        submitLabel: l10n.tenantFacilityDetailsRemoveLogoAction,
        destructive: true,
        icon: const Icon(Icons.hide_image_outlined),
        onConfirm: () async {
          final Result<void> result = await ref
              .read(tenantFacilityRepositoryProvider)
              .deleteFacilityLogo(_facility.mutationId);
          return result.when(
            success: (_) => null,
            failure: (AppFailure failure) => failure,
          );
        },
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }

    setState(() {
      _facility = _facility.copyWith(clearLogoUrl: true);
      _mutated = true;
      if (_snapshot?.facility != null) {
        _snapshot = _snapshot!.copyWith(
          facility: _snapshot!.facility!.copyWith(clearLogoUrl: true),
        );
      }
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(l10n.tenantFacilityDetailsLogoRemovedMessage)),
      );
  }

  Future<void> _deleteFacility() async {
    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AppConfirmActionDialog(
        title: l10n.tenantFacilityDeleteConfirmationTitle,
        body: l10n.tenantFacilityDeleteFacilityConfirmationBody(_facility.name),
        highlightedText: _facility.name,
        submitLabel: l10n.tenantFacilityDeleteConfirmAction,
        destructive: true,
        icon: const Icon(Icons.delete_outline),
        onConfirm: () async {
          final Result<void> result = await ref
              .read(tenantFacilityRepositoryProvider)
              .deleteFacility(_facility.mutationId);
          return result.when(
            success: (_) => null,
            failure: (AppFailure failure) {
              if (failure.category == AppFailureCategory.notFound) {
                return null;
              }
              return failure;
            },
          );
        },
      ),
    );

    if (!mounted || confirmed != true) {
      return;
    }

    _syncPlatformDashboard(
      ref,
      patch: HomeDashboardOptimisticPatch.facilityDeleted(
        isActive: _facility.isActive && !_facility.isDeleted,
      ),
    );
    Navigator.of(context).pop(true);
  }

  Future<void> _restoreFacility() async {
    if (!_canRestoreFacility) {
      return;
    }
    final AppLocalizations l10n = context.l10n;
    FacilityProfile? restoredFacility;
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AppConfirmActionDialog(
        title: l10n.tenantFacilityRestoreFacilityConfirmationTitle,
        body: l10n.tenantFacilityRestoreFacilityConfirmationBody(
          _facility.name,
        ),
        highlightedText: _facility.name,
        submitLabel: l10n.tenantFacilityRestoreTenantAction,
        icon: const Icon(Icons.restore_outlined),
        onConfirm: () async {
          final Result<FacilityProfile> result = await ref
              .read(tenantFacilityRepositoryProvider)
              .restoreFacility(_facility.mutationId);
          return result.when(
            success: (FacilityProfile value) {
              restoredFacility = value;
              return null;
            },
            failure: (AppFailure failure) => failure,
          );
        },
      ),
    );

    if (!mounted || confirmed != true) {
      return;
    }

    final FacilityProfile applied =
        restoredFacility ?? _facility.copyWith(clearDeletedAt: true);
    setState(() {
      _facility = applied;
      _mutated = true;
      if (_snapshot != null) {
        _snapshot = _snapshot!.copyWith(facility: applied);
      }
    });
    _syncPlatformDashboard(
      ref,
      patch: HomeDashboardOptimisticPatch.facilityCreated(
        isActive: applied.isActive,
      ),
    );
  }

  Future<void> _permanentDeleteFacility() async {
    if (!_canPermanentDeleteFacility) {
      return;
    }
    final AppLocalizations l10n = context.l10n;
    final String? typed = await showAppDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AppTextInputActionDialog(
        title: l10n.tenantFacilityPermanentDeleteFacilityConfirmationTitle,
        description: l10n.tenantFacilityPermanentDeleteFacilityWarningBody(
          _facility.name,
        ),
        fieldLabel: l10n.tenantFacilityPermanentDeleteConfirmFieldLabel(
          _facility.name,
        ),
        submitLabel: l10n.tenantFacilityPermanentDeleteConfirmAction,
        cancelLabel: l10n.commonCancelActionLabel,
        requiredMessage: l10n.validationRequired,
        confirmExactValue: _facility.name,
        confirmMismatchMessage: l10n
            .tenantFacilityPermanentDeleteConfirmFieldLabel(_facility.name),
        destructive: true,
        minLines: 1,
        maxLines: 1,
        icon: const Icon(Icons.delete_forever_outlined),
      ),
    );

    if (!mounted || typed == null) {
      return;
    }
    if (typed.trim().toLowerCase() != _facility.name.trim().toLowerCase()) {
      return;
    }

    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AppConfirmActionDialog(
        title: l10n.tenantFacilityPermanentDeleteFacilityConfirmationTitle,
        body: l10n.tenantFacilityPermanentDeleteFacilityConfirmationBody(
          _facility.name,
        ),
        highlightedText: _facility.name,
        submitLabel: l10n.tenantFacilityPermanentDeleteConfirmAction,
        destructive: true,
        icon: const Icon(Icons.delete_forever_outlined),
        onConfirm: () async {
          final Result<void> result = await ref
              .read(tenantFacilityRepositoryProvider)
              .permanentDeleteFacility(_facility.mutationId);
          return result.when(
            success: (_) => null,
            failure: (AppFailure failure) {
              if (failure.category == AppFailureCategory.notFound) {
                return null;
              }
              return failure;
            },
          );
        },
      ),
    );

    if (!mounted || confirmed != true) {
      return;
    }

    _syncPlatformDashboard(ref);
    Navigator.of(context).pop(true);
  }

  Widget _buildRightPanel(AppLocalizations l10n) {
    final FacilitySetupSnapshot snapshot = _effectiveSnapshot;
    final bool canMutateStructure = _canMutateStructure;

    switch (_selectedPanel) {
      case _FacilityDetailsPanel.users:
        return _FacilityDetailsUsersPanel(
          searchController: _usersSearchController,
          loading: _loadingUsers,
          failure: _usersFailure,
          users: _users,
          pageRequest: _pageRequest,
          totalItemCount: _totalUserCount,
          canManage: _canMutate,
          onPageChanged: _onUsersPageChanged,
          onAdd: () => unawaited(_createUser()),
          onEdit: (AccessAdminItem user) => unawaited(_editUser(user)),
          onDelete: (AccessAdminItem user) => unawaited(_deleteUser(user)),
          onRestore: (AccessAdminItem user) => unawaited(_restoreUser(user)),
        );
      case _FacilityDetailsPanel.departments:
        return _FacilityStructureCrudPanel<DepartmentProfile>(
          title: l10n.tenantFacilityDepartmentsListTitle,
          items: snapshot.departments,
          emptyLabel: l10n.tenantFacilityNoDepartments,
          addLabel: l10n.tenantFacilityAddDepartmentAction,
          canManage: canMutateStructure,
          titleBuilder: (DepartmentProfile item) => item.name,
          subtitleBuilder: (DepartmentProfile item) => item.type.name,
          isDeletedBuilder: (DepartmentProfile item) => item.isDeleted,
          statusBuilder: (DepartmentProfile item) => item.isDeleted
              ? l10n.tenantFacilityStructureDeletedStatus
              : l10n.tenantFacilityStructureActiveStatus,
          onAdd: () => unawaited(_openDepartmentForm()),
          onEdit: (DepartmentProfile item) =>
              unawaited(_openDepartmentForm(department: item)),
          onDelete: (DepartmentProfile item) => unawaited(
            _confirmDeleteStructure(
              name: item.name,
              deleteAction: () => ref
                  .read(tenantFacilitySetupSubmissionProvider.notifier)
                  .deleteDepartment(item.mutationId),
            ),
          ),
          onRestore: (DepartmentProfile item) => unawaited(
            _confirmRestoreStructure(
              name: item.name,
              restoreAction: () => ref
                  .read(tenantFacilitySetupSubmissionProvider.notifier)
                  .restoreDepartment(item.mutationId),
            ),
          ),
        );
      case _FacilityDetailsPanel.units:
        return _FacilityStructureCrudPanel<UnitProfile>(
          title: l10n.tenantFacilityUnitsListTitle,
          items: snapshot.units,
          emptyLabel: l10n.tenantFacilityNoUnits,
          addLabel: l10n.tenantFacilityAddUnitAction,
          canManage: canMutateStructure,
          canAdd: canMutateStructure && snapshot.departments.isNotEmpty,
          blockedMessage: canMutateStructure && snapshot.departments.isEmpty
              ? l10n.tenantFacilityGateNeedDepartmentForUnits
              : null,
          titleBuilder: (UnitProfile item) => item.name,
          subtitleBuilder: (UnitProfile item) => '',
          isDeletedBuilder: (UnitProfile item) => item.isDeleted,
          statusBuilder: (UnitProfile item) => item.isDeleted
              ? l10n.tenantFacilityStructureDeletedStatus
              : l10n.tenantFacilityStructureActiveStatus,
          onAdd: () => unawaited(_openUnitForm()),
          onEdit: (UnitProfile item) => unawaited(_openUnitForm(unit: item)),
          onDelete: (UnitProfile item) => unawaited(
            _confirmDeleteStructure(
              name: item.name,
              deleteAction: () => ref
                  .read(tenantFacilitySetupSubmissionProvider.notifier)
                  .deleteUnit(item.id),
            ),
          ),
          onRestore: (UnitProfile item) => unawaited(
            _confirmRestoreStructure(
              name: item.name,
              restoreAction: () => ref
                  .read(tenantFacilitySetupSubmissionProvider.notifier)
                  .restoreUnit(item.id),
            ),
          ),
        );
      case _FacilityDetailsPanel.wards:
        return _FacilityStructureCrudPanel<WardProfile>(
          title: l10n.tenantFacilityWardsLabel,
          items: snapshot.wards,
          emptyLabel: l10n.tenantFacilityNoWards,
          addLabel: l10n.tenantFacilityAddWardAction,
          canManage: canMutateStructure && _canManageFacility,
          titleBuilder: (WardProfile item) => item.name,
          subtitleBuilder: (WardProfile item) => item.type.name,
          isDeletedBuilder: (WardProfile item) => item.isDeleted,
          statusBuilder: (WardProfile item) => item.isDeleted
              ? l10n.tenantFacilityStructureDeletedStatus
              : l10n.tenantFacilityStructureActiveStatus,
          onAdd: () => unawaited(_openWardForm()),
          onEdit: (WardProfile item) => unawaited(_openWardForm(ward: item)),
          onDelete: (WardProfile item) => unawaited(
            _confirmDeleteStructure(
              name: item.name,
              deleteAction: () => ref
                  .read(tenantFacilitySetupSubmissionProvider.notifier)
                  .deleteWard(item.id),
            ),
          ),
          onRestore: (WardProfile item) => unawaited(
            _confirmRestoreStructure(
              name: item.name,
              restoreAction: () => ref
                  .read(tenantFacilitySetupSubmissionProvider.notifier)
                  .restoreWard(item.id),
            ),
          ),
        );
      case _FacilityDetailsPanel.rooms:
        return _FacilityStructureCrudPanel<RoomProfile>(
          title: l10n.tenantFacilityRoomsLabel,
          items: snapshot.rooms,
          emptyLabel: l10n.tenantFacilityNoRooms,
          addLabel: l10n.tenantFacilityAddRoomAction,
          canManage: canMutateStructure && _canManageFacility,
          titleBuilder: (RoomProfile item) => item.name,
          subtitleBuilder: (RoomProfile item) =>
              item.floor?.trim().isNotEmpty == true ? item.floor! : '—',
          isDeletedBuilder: (RoomProfile item) => item.isDeleted,
          statusBuilder: (RoomProfile item) => item.isDeleted
              ? l10n.tenantFacilityStructureDeletedStatus
              : l10n.tenantFacilityStructureActiveStatus,
          onAdd: () => unawaited(_openRoomForm()),
          onEdit: (RoomProfile item) => unawaited(_openRoomForm(room: item)),
          onDelete: (RoomProfile item) => unawaited(
            _confirmDeleteStructure(
              name: item.name,
              deleteAction: () => ref
                  .read(tenantFacilitySetupSubmissionProvider.notifier)
                  .deleteRoom(item.id),
            ),
          ),
          onRestore: (RoomProfile item) => unawaited(
            _confirmRestoreStructure(
              name: item.name,
              restoreAction: () => ref
                  .read(tenantFacilitySetupSubmissionProvider.notifier)
                  .restoreRoom(item.id),
            ),
          ),
        );
      case _FacilityDetailsPanel.beds:
        return _FacilityStructureCrudPanel<BedProfile>(
          title: l10n.tenantFacilityBedsLabel,
          items: snapshot.beds,
          emptyLabel: l10n.tenantFacilityNoBeds,
          addLabel: l10n.tenantFacilityAddBedAction,
          canManage: canMutateStructure && _canManageFacility,
          canAdd:
              (canMutateStructure && _canManageFacility) &&
              snapshot.wards.isNotEmpty,
          blockedMessage:
              (canMutateStructure && _canManageFacility) &&
                  snapshot.wards.isEmpty
              ? l10n.tenantFacilityGateNeedWardsForBeds
              : null,
          titleBuilder: (BedProfile item) => item.label,
          subtitleBuilder: (BedProfile item) => item.status.name,
          isDeletedBuilder: (BedProfile item) => item.isDeleted,
          statusBuilder: (BedProfile item) => item.isDeleted
              ? l10n.tenantFacilityStructureDeletedStatus
              : l10n.tenantFacilityStructureActiveStatus,
          onAdd: () => unawaited(_openBedForm()),
          onEdit: (BedProfile item) => unawaited(_openBedForm(bed: item)),
          onDelete: (BedProfile item) => unawaited(
            _confirmDeleteStructure(
              name: item.label,
              deleteAction: () => ref
                  .read(tenantFacilitySetupSubmissionProvider.notifier)
                  .deleteBed(item.id),
            ),
          ),
          onRestore: (BedProfile item) => unawaited(
            _confirmRestoreStructure(
              name: item.label,
              restoreAction: () => ref
                  .read(tenantFacilitySetupSubmissionProvider.notifier)
                  .restoreBed(item.id),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final bool canMutate = _canMutate;

    return AppDialog(
      title: Text(l10n.tenantFacilityFacilityDetailsTitle),
      icon: const Icon(Icons.domain_outlined),
      pinActionsToBottom: true,
      maxWidth: 1040,
      content: SizedBox(
        height: 560,
        child: _overviewFailure != null && _snapshot == null
            ? AppFailureStateView(failure: _overviewFailure!)
            : LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final bool wide = constraints.maxWidth >= 720;
                  final Widget summary = _FacilityDetailsSummary(
                    facility: _facility,
                    tenantLabel: _tenantLabel,
                    statusLabel: _facilityStatusLabel(l10n),
                    statusTone: _facilityStatusTone(),
                    snapshot: _snapshot,
                    userCount: _users
                        .where((AccessAdminItem user) => !user.isDeleted)
                        .length,
                    loading: _loadingOverview,
                    selectedPanel: _selectedPanel,
                    onPanelSelected: _selectPanel,
                    canManageLogo: canMutate,
                    logoBusy: _logoBusy,
                    onAddOrChangeLogo: () => unawaited(_addOrChangeLogo()),
                    onRemoveLogo: () => unawaited(_removeLogo()),
                  );
                  final Widget rightPanel = _buildRightPanel(l10n);

                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        SizedBox(
                          width: 320,
                          child: SingleChildScrollView(child: summary),
                        ),
                        SizedBox(width: theme.spacing.md),
                        Expanded(child: rightPanel),
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      summary,
                      SizedBox(height: theme.spacing.md),
                      Expanded(child: rightPanel),
                    ],
                  );
                },
              ),
      ),
      actions: <Widget>[
        if (canMutate)
          AppButton.secondary(
            label: l10n.tenantFacilityEditFacilityDetailsAction,
            leadingIcon: Icons.edit_outlined,
            onPressed: () => unawaited(_editFacility()),
          ),
        if (_canDelete)
          AppButton.primary(
            label: l10n.tenantFacilityDeleteFacilityDetailsAction,
            leadingIcon: Icons.delete_outline,
            color: colorScheme.error,
            onPressed: () => unawaited(_deleteFacility()),
          ),
        if (_canRestoreFacility)
          AppButton.secondary(
            label: l10n.tenantFacilityRestoreTenantAction,
            leadingIcon: Icons.restore_outlined,
            onPressed: () => unawaited(_restoreFacility()),
          ),
        if (_canPermanentDeleteFacility)
          AppButton.primary(
            label: l10n.tenantFacilityPermanentDeleteAction,
            leadingIcon: Icons.delete_forever_outlined,
            color: colorScheme.error,
            onPressed: () => unawaited(_permanentDeleteFacility()),
          ),
        AppButton.secondary(
          label: l10n.commonCloseActionLabel,
          leadingIcon: Icons.close,
          onPressed: () => Navigator.of(context).pop(_mutated ? true : null),
        ),
      ],
    );
  }
}

class _FacilityDetailsSummary extends StatelessWidget {
  const _FacilityDetailsSummary({
    required this.facility,
    required this.tenantLabel,
    required this.statusLabel,
    required this.statusTone,
    required this.snapshot,
    required this.userCount,
    required this.loading,
    required this.selectedPanel,
    required this.onPanelSelected,
    this.canManageLogo = false,
    this.logoBusy = false,
    this.onAddOrChangeLogo,
    this.onRemoveLogo,
  });

  final FacilityProfile facility;
  final String tenantLabel;
  final String statusLabel;
  final AppWorkspaceStatusTone statusTone;
  final FacilitySetupSnapshot? snapshot;
  final int userCount;
  final bool loading;
  final _FacilityDetailsPanel selectedPanel;
  final ValueChanged<_FacilityDetailsPanel> onPanelSelected;
  final bool canManageLogo;
  final bool logoBusy;
  final VoidCallback? onAddOrChangeLogo;
  final VoidCallback? onRemoveLogo;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final String? displayId = tenantFacilityHumanFriendlyDisplayId(
      facility.displayId,
      opaqueId: facility.resourceUuid ?? facility.id,
    );
    final bool hasLogo =
        facility.logoUrl != null && facility.logoUrl!.trim().isNotEmpty;
    final FacilityContactAddress contact =
        snapshot?.contactAddress ?? const FacilityContactAddress();
    // Phone/email fall back to the tenant contact when the facility has none.
    final FacilitySetupSnapshot? loadedSnapshot = snapshot;
    final FacilityEffectiveContact effectiveContact = loadedSnapshot == null
        ? facility.displayContact
        : loadedSnapshot.resolvedEffectiveContact;
    final String? phone = effectiveContact.phone?.trim();
    final String? email = effectiveContact.email?.trim();
    final bool hasInheritedContact =
        effectiveContact.isPhoneInherited || effectiveContact.isEmailInherited;
    final String address =
        <String?>[contact.addressLine1, contact.city, contact.country]
            .whereType<String>()
            .map((String value) => value.trim())
            .where((String value) => value.isNotEmpty)
            .join(', ');

    final String emptyValue = l10n.profileUnknownValue;

    final List<AppInfoSheetItem> overviewItems = <AppInfoSheetItem>[
      AppInfoSheetItem(label: l10n.profileTenantLabel, value: tenantLabel),
      AppInfoSheetItem(
        label: l10n.profileFacilityTypeLabel,
        value: facility.type.name,
      ),
      if (displayId != null)
        AppInfoSheetItem(
          label: l10n.tenantFacilityFacilityIdLabel,
          value: displayId,
          copyable: true,
          copyTooltip: l10n.copyIdentifierAction,
          copiedMessage: l10n.identifierCopiedMessage,
          copyPlaceholderValues: <String>{emptyValue, '—'},
        ),
      AppInfoSheetItem(
        label: l10n.tenantFacilityTenantStatusLabel,
        value: statusLabel,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: appCollapsibleSectionSpacing(context, <Widget>[
        AppCollapsibleSection(
          collapsible: false,
          titleWidget: Row(
            children: <Widget>[
              _FacilityLogoAvatar(logoUrl: facility.logoUrl),
              SizedBox(width: theme.spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      facility.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: AppFontWeight.strong,
                      ),
                    ),
                    SizedBox(height: theme.spacing.xs),
                    _TenantStatusBadge(label: statusLabel, tone: statusTone),
                  ],
                ),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (canManageLogo) ...<Widget>[
                if (logoBusy)
                  const LinearProgressIndicator(minHeight: 2)
                else
                  Wrap(
                    spacing: theme.spacing.sm,
                    runSpacing: theme.spacing.xs,
                    children: <Widget>[
                      AppButton.secondary(
                        label: hasLogo
                            ? l10n.tenantFacilityDetailsChangeLogoAction
                            : l10n.tenantFacilityDetailsAddLogoAction,
                        leadingIcon: hasLogo
                            ? Icons.sync_outlined
                            : Icons.add_photo_alternate_outlined,
                        onPressed: onAddOrChangeLogo,
                      ),
                      if (hasLogo)
                        AppButton.secondary(
                          label: l10n.tenantFacilityDetailsRemoveLogoAction,
                          leadingIcon: Icons.hide_image_outlined,
                          color: colorScheme.error,
                          onPressed: onRemoveLogo,
                        ),
                    ],
                  ),
                SizedBox(height: theme.spacing.md),
              ],
              AppInfoSheetGrid(
                emptyValue: emptyValue,
                maxColumns: 2,
                items: overviewItems,
              ),
            ],
          ),
        ),
        AppCollapsibleSection(
          title: l10n.tenantFacilityFacilityDetailsStructureHeading,
          titleIcon: Icons.account_tree_outlined,
          child: loading && snapshot == null
              ? const Center(child: CircularProgressIndicator())
              : Wrap(
                  spacing: theme.spacing.sm,
                  runSpacing: theme.spacing.sm,
                  children: <Widget>[
                    _FacilityMetricChip(
                      label: l10n.tenantFacilityFacilityDetailsUsersHeading,
                      value: userCount,
                      selected:
                          selectedPanel == _FacilityDetailsPanel.users,
                      onTap: () =>
                          onPanelSelected(_FacilityDetailsPanel.users),
                    ),
                    _FacilityMetricChip(
                      label: l10n.tenantFacilityDepartmentsListTitle,
                      value:
                          snapshot?.departments
                              .where(
                                (DepartmentProfile item) => !item.isDeleted,
                              )
                              .length ??
                          0,
                      selected:
                          selectedPanel ==
                          _FacilityDetailsPanel.departments,
                      onTap: () => onPanelSelected(
                        _FacilityDetailsPanel.departments,
                      ),
                    ),
                    _FacilityMetricChip(
                      label: l10n.tenantFacilityUnitsListTitle,
                      value:
                          snapshot?.units
                              .where((UnitProfile item) => !item.isDeleted)
                              .length ??
                          0,
                      selected:
                          selectedPanel == _FacilityDetailsPanel.units,
                      onTap: () =>
                          onPanelSelected(_FacilityDetailsPanel.units),
                    ),
                    _FacilityMetricChip(
                      label: l10n.tenantFacilityWardsLabel,
                      value:
                          snapshot?.wards
                              .where((WardProfile item) => !item.isDeleted)
                              .length ??
                          0,
                      selected:
                          selectedPanel == _FacilityDetailsPanel.wards,
                      onTap: () =>
                          onPanelSelected(_FacilityDetailsPanel.wards),
                    ),
                    _FacilityMetricChip(
                      label: l10n.tenantFacilityRoomsLabel,
                      value:
                          snapshot?.rooms
                              .where((RoomProfile item) => !item.isDeleted)
                              .length ??
                          0,
                      selected:
                          selectedPanel == _FacilityDetailsPanel.rooms,
                      onTap: () =>
                          onPanelSelected(_FacilityDetailsPanel.rooms),
                    ),
                    _FacilityMetricChip(
                      label: l10n.tenantFacilityBedsLabel,
                      value:
                          snapshot?.beds
                              .where((BedProfile item) => !item.isDeleted)
                              .length ??
                          0,
                      selected: selectedPanel == _FacilityDetailsPanel.beds,
                      onTap: () =>
                          onPanelSelected(_FacilityDetailsPanel.beds),
                    ),
                  ],
                ),
        ),        if (phone != null || email != null || address.isNotEmpty)
          AppCollapsibleSection(
            title: l10n.tenantFacilityFacilityDetailsContactHeading,
            titleIcon: Icons.contact_mail_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                AppInfoSheetGrid(
                  emptyValue: emptyValue,
                  maxColumns: 2,
                  items: <AppInfoSheetItem>[
                    if (phone != null && phone.isNotEmpty)
                      AppInfoSheetItem(
                        label: effectiveContact.isPhoneInherited
                            ? l10n.tenantFacilityInheritedContactLabel(
                                l10n.profilePhoneLabel,
                              )
                            : l10n.profilePhoneLabel,
                        value: phone,
                      ),
                    if (email != null && email.isNotEmpty)
                      AppInfoSheetItem(
                        label: effectiveContact.isEmailInherited
                            ? l10n.tenantFacilityInheritedContactLabel(
                                l10n.profileEmailLabel,
                              )
                            : l10n.profileEmailLabel,
                        value: email,
                      ),
                    if (address.isNotEmpty)
                      AppInfoSheetItem(
                        label: l10n.tenantFacilityAddressLineLabel,
                        value: address,
                      ),
                  ],
                ),
                if (hasInheritedContact) ...<Widget>[
                  SizedBox(height: theme.spacing.sm),
                  TenantFacilityInheritedContactNote(
                    message: l10n.tenantFacilityInheritedContactNote,
                  ),
                ],
              ],
            ),
          ),
      ]),
    );
  }
}

class _FacilityLogoAvatar extends ConsumerWidget {
  const _FacilityLogoAvatar({this.logoUrl});

  final String? logoUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final String? url = resolveAppMediaUrl(
      logoUrl,
      ref.watch(appConfigProvider).apiBaseUrl,
    );
    final bool hasLogo = url != null && url.isNotEmpty;

    // A logo that fails to load must not read as one that was never uploaded:
    // the two states are otherwise identical on screen, which hides real
    // delivery failures (a 404 on the media host, or a missing CORS header).
    Widget placeholder({required bool failed}) {
      final String label = failed
          ? l10n.tenantFacilityFacilityDetailsLogoLoadFailed
          : l10n.tenantFacilityFacilityDetailsNoLogo;
      return Tooltip(
        message: label,
        child: Icon(
          failed ? Icons.broken_image_outlined : Icons.domain_outlined,
          color: failed ? colorScheme.error : colorScheme.onSurfaceVariant,
          semanticLabel: label,
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: theme.borders.all(),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 88,
          height: 88,
          child: hasLogo
              ? Padding(
                  padding: const EdgeInsets.all(6),
                  child: Image.network(
                    url,
                    key: ValueKey<String>(url),
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    errorBuilder:
                        (
                          BuildContext context,
                          Object error,
                          StackTrace? stackTrace,
                        ) => placeholder(failed: true),
                  ),
                )
              : placeholder(failed: false),
        ),
      ),
    );
  }
}

class _FacilityMetricChip extends StatelessWidget {
  const _FacilityMetricChip({
    required this.label,
    required this.value,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final int value;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final Color borderColor = selected
        ? colorScheme.primary
        : theme.borders.faint;
    final Color background = selected
        ? colorScheme.primary.withValues(alpha: 0.10)
        : colorScheme.surface;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: theme.borders.all(
              color: borderColor,
              weight: selected ? AppBorderWeight.medium : AppBorderWeight.thin,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '$value',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: AppFontWeight.emphasis,
                    color: selected ? colorScheme.primary : null,
                  ),
                ),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: selected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                    fontWeight: selected ? AppFontWeight.emphasis : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FacilityStructureCrudPanel<T> extends StatefulWidget {
  const _FacilityStructureCrudPanel({
    required this.title,
    required this.items,
    required this.emptyLabel,
    required this.addLabel,
    required this.canManage,
    required this.titleBuilder,
    required this.subtitleBuilder,
    required this.isDeletedBuilder,
    required this.statusBuilder,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onRestore,
    this.canAdd,
    this.blockedMessage,
  });

  final String title;
  final List<T> items;
  final String emptyLabel;
  final String addLabel;
  final bool canManage;
  final bool? canAdd;
  final String? blockedMessage;
  final String Function(T item) titleBuilder;
  final String Function(T item) subtitleBuilder;
  final bool Function(T item) isDeletedBuilder;
  final String Function(T item) statusBuilder;
  final VoidCallback onAdd;
  final ValueChanged<T> onEdit;
  final ValueChanged<T> onDelete;
  final ValueChanged<T> onRestore;

  @override
  State<_FacilityStructureCrudPanel<T>> createState() =>
      _FacilityStructureCrudPanelState<T>();
}

class _FacilityStructureCrudPanelState<T>
    extends State<_FacilityStructureCrudPanel<T>> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final String query = _searchController.text.trim().toLowerCase();
    final List<T> filtered = query.isEmpty
        ? widget.items
        : widget.items
              .where((T item) {
                final String title = widget.titleBuilder(item).toLowerCase();
                final String subtitle = widget
                    .subtitleBuilder(item)
                    .toLowerCase();
                final String status = widget.statusBuilder(item).toLowerCase();
                return title.contains(query) ||
                    subtitle.contains(query) ||
                    status.contains(query);
              })
              .toList(growable: false);
    final bool canAdd = widget.canAdd ?? widget.canManage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                widget.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: AppFontWeight.strong,
                ),
              ),
            ),
            if (widget.canManage)
              AppButton.tertiary(
                leadingIcon: Icons.add,
                label: widget.addLabel,
                semanticLabel: widget.addLabel,
                tooltip: widget.blockedMessage ?? widget.addLabel,
                enabled: canAdd,
                onPressed: canAdd ? widget.onAdd : null,
              ),
          ],
        ),
        if (widget.blockedMessage case final String message) ...<Widget>[
          SizedBox(height: theme.spacing.xs),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        SizedBox(height: theme.spacing.sm),
        AppSearchBar(
          controller: _searchController,
          hintText: l10n.tenantFacilitySearchLabel,
          semanticLabel: l10n.tenantFacilitySearchLabel,
          onChanged: (_) => setState(() {}),
        ),
        SizedBox(height: theme.spacing.sm),
        Expanded(
          child: filtered.isEmpty
              ? AppWorkspaceStatePanel.empty(
                  title: widget.title,
                  body: widget.items.isEmpty
                      ? widget.emptyLabel
                      : l10n.tenantFacilitySearchNoResults,
                )
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final T item = filtered[index];
                    final bool deleted = widget.isDeletedBuilder(item);
                    final String subtitle = widget.subtitleBuilder(item);
                    final TextStyle? mutedStyle = deleted
                        ? theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          )
                        : null;
                    final AppWorkspaceStatusTone statusTone = deleted
                        ? AppWorkspaceStatusTone.error
                        : AppWorkspaceStatusTone.success;

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        widget.titleBuilder(item),
                        style: mutedStyle?.copyWith(
                          fontWeight: AppFontWeight.emphasis,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (subtitle.trim().isNotEmpty)
                            Text(subtitle, style: mutedStyle),
                          SizedBox(height: theme.spacing.xs),
                          _TenantStatusBadge(
                            label: widget.statusBuilder(item),
                            tone: statusTone,
                          ),
                        ],
                      ),
                      isThreeLine: true,
                      trailing: widget.canManage
                          ? (deleted
                                ? AppButton.tertiary(
                                    leadingIcon: Icons.restore_outlined,
                                    label: l10n
                                        .tenantFacilityRestoreStructureAction,
                                    semanticLabel: l10n
                                        .tenantFacilityRestoreStructureAction,
                                    tooltip: l10n
                                        .tenantFacilityRestoreStructureAction,
                                    onPressed: () => widget.onRestore(item),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      AppButton.tertiary(
                                        leadingIcon: Icons.edit_outlined,
                                        label: l10n.tenantFacilityEditAction,
                                        semanticLabel:
                                            l10n.tenantFacilityEditAction,
                                        tooltip: l10n.tenantFacilityEditAction,
                                        onPressed: () => widget.onEdit(item),
                                      ),
                                      AppButton.tertiary(
                                        leadingIcon: Icons.delete_outline,
                                        label: l10n.tenantFacilityDeleteAction,
                                        semanticLabel:
                                            l10n.tenantFacilityDeleteAction,
                                        tooltip:
                                            l10n.tenantFacilityDeleteAction,
                                        color: colorScheme.error,
                                        onPressed: () => widget.onDelete(item),
                                      ),
                                    ],
                                  ))
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FacilityDetailsUsersPanel extends StatelessWidget {
  const _FacilityDetailsUsersPanel({
    required this.searchController,
    required this.loading,
    required this.failure,
    required this.users,
    required this.pageRequest,
    required this.totalItemCount,
    required this.canManage,
    required this.onPageChanged,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onRestore,
  });

  final TextEditingController searchController;
  final bool loading;
  final AppFailure? failure;
  final List<AccessAdminItem> users;
  final AppPageRequest pageRequest;
  final int totalItemCount;
  final bool canManage;
  final Future<void> Function(AppPageRequest request) onPageChanged;
  final VoidCallback onAdd;
  final ValueChanged<AccessAdminItem> onEdit;
  final ValueChanged<AccessAdminItem> onDelete;
  final ValueChanged<AccessAdminItem> onRestore;

  String _userStatusLabel(AppLocalizations l10n, AccessAdminItem user) {
    if (user.isDeleted) {
      return l10n.tenantFacilityStructureDeletedStatus;
    }
    if (user.status?.trim().isNotEmpty == true) {
      return user.status!;
    }
    return user.isActive
        ? l10n.tenantFacilityTenantStatusActive
        : l10n.commonNoLabel;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                l10n.tenantFacilityFacilityDetailsUsersHeading,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: AppFontWeight.strong,
                ),
              ),
            ),
            if (canManage)
              AppButton.tertiary(
                leadingIcon: Icons.person_add_outlined,
                label: l10n.accessAdminCreateUserAction,
                semanticLabel: l10n.accessAdminCreateUserAction,
                tooltip: l10n.accessAdminCreateUserAction,
                onPressed: onAdd,
              ),
          ],
        ),
        SizedBox(height: theme.spacing.sm),
        AppSearchBar(
          controller: searchController,
          hintText: l10n.tenantFacilitySearchLabel,
          semanticLabel: l10n.tenantFacilitySearchLabel,
        ),
        SizedBox(height: theme.spacing.sm),
        Expanded(
          child: failure != null
              ? AppFailureStateView(failure: failure!)
              : AppListTable<AccessAdminItem>(
                  page: AppPage<AccessAdminItem>(
                    items: users,
                    request: pageRequest,
                    totalItemCount: totalItemCount,
                  ),
                  isLoading: loading,
                  itemKeyBuilder: (AccessAdminItem item) =>
                      ValueKey<String>(item.id),
                  previousPageLabel: l10n.hrPreviousPageLabel,
                  nextPageLabel: l10n.hrNextPageLabel,
                  pageLabelBuilder: (AppPage<AccessAdminItem> page) {
                    if (loading) {
                      return '';
                    }
                    final int total = page.totalItemCount ?? page.items.length;
                    if (total == 0) {
                      return l10n.commonTableEmptyLabel;
                    }
                    final int start = page.pageIndex * page.pageSize + 1;
                    final int end = start + page.items.length - 1;
                    return '$start-$end / $total';
                  },
                  onPageChanged: onPageChanged,
                  columns: <AppListTableColumn<AccessAdminItem>>[
                    AppListTableColumn<AccessAdminItem>(
                      label: l10n.accessAdminCreateUserDetailsSectionTitle,
                      cellBuilder: (_, AccessAdminItem user) => Text(
                        user.title,
                        style: user.isDeleted
                            ? theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              )
                            : null,
                      ),
                    ),
                    AppListTableColumn<AccessAdminItem>(
                      label: l10n.profileEmailLabel,
                      cellBuilder: (_, AccessAdminItem user) => Text(
                        user.email ?? user.subtitle ?? '—',
                        style: user.isDeleted
                            ? theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              )
                            : null,
                      ),
                    ),
                    AppListTableColumn<AccessAdminItem>(
                      label: l10n.tenantFacilityTenantStatusLabel,
                      cellBuilder: (_, AccessAdminItem user) => Text(
                        _userStatusLabel(l10n, user),
                        style: user.isDeleted
                            ? theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              )
                            : null,
                      ),
                    ),
                    if (canManage)
                      AppListTableColumn<AccessAdminItem>(
                        id: 'actions',
                        label: l10n.accessAdminColumnActions,
                        alwaysVisible: true,
                        cellBuilder:
                            (BuildContext context, AccessAdminItem user) {
                              if (user.isDeleted) {
                                return AppButton.tertiary(
                                  leadingIcon: Icons.restore_outlined,
                                  label: l10n.accessAdminRestoreUserAction,
                                  semanticLabel:
                                      l10n.accessAdminRestoreUserAction,
                                  tooltip: l10n.accessAdminRestoreUserAction,
                                  onPressed: () => onRestore(user),
                                );
                              }
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  AppButton.tertiary(
                                    leadingIcon: Icons.edit_outlined,
                                    label: l10n.tenantFacilityEditAction,
                                    semanticLabel:
                                        l10n.tenantFacilityEditAction,
                                    tooltip: l10n.tenantFacilityEditAction,
                                    onPressed: () => onEdit(user),
                                  ),
                                  AppButton.tertiary(
                                    leadingIcon: Icons.delete_outline,
                                    label: l10n.tenantFacilityDeleteAction,
                                    semanticLabel:
                                        l10n.tenantFacilityDeleteAction,
                                    tooltip: l10n.tenantFacilityDeleteAction,
                                    color: colorScheme.error,
                                    enabled:
                                        !user.isDemo && !user.isSystemCritical,
                                    onPressed:
                                        user.isDemo || user.isSystemCritical
                                        ? null
                                        : () => onDelete(user),
                                  ),
                                ],
                              );
                            },
                      ),
                  ],
                  emptyBuilder: (_) => AppWorkspaceStatePanel.empty(
                    title: l10n.tenantFacilityFacilityDetailsUsersHeading,
                    body: l10n.tenantFacilityFacilityDetailsNoUsers,
                  ),
                  mobileItemBuilder:
                      (BuildContext context, AccessAdminItem user) {
                        return AppListTableMobileItem(
                          title: user.title,
                          caption: user.email ?? user.subtitle,
                          meta: <AppListTableMobileMeta>[
                            AppListTableMobileMeta(
                              label: _userStatusLabel(l10n, user),
                            ),
                          ],
                        );
                      },
                ),
        ),
      ],
    );
  }
}

/// Facilities table/CRUD shared by manage dialog and setup Facility tab.
class ManageFacilitiesPanel extends ConsumerStatefulWidget {
  const ManageFacilitiesPanel({
    this.dialogMode = false,
    this.showCreateAction = true,
    this.sessionFacility,
    this.sessionTenantId,
    this.reloadListenable,
    this.onMutated,
    this.onListTotalChanged,
    super.key,
  });

  final bool dialogMode;
  final bool showCreateAction;
  final FacilityProfile? sessionFacility;
  final String? sessionTenantId;
  final Listenable? reloadListenable;
  final ValueChanged<bool>? onMutated;
  final ValueChanged<int>? onListTotalChanged;

  @override
  ConsumerState<ManageFacilitiesPanel> createState() =>
      _ManageFacilitiesPanelState();
}

class _ManageFacilitiesPanelState extends ConsumerState<ManageFacilitiesPanel> {
  static const String _tenantFilterKey = 'tenant';
  static const String _typeFilterKey = 'type';
  static const String _statusFilterKey = 'status';
  static const String _activeFilterKey = 'active';
  static const String _statusActive = 'active';
  static const String _statusDeleted = 'deleted';
  static const String _activeYes = 'yes';
  static const String _activeNo = 'no';

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  bool _loading = true;
  AppFailure? _failure;
  AppPageRequest _pageRequest = PlatformAdminListConfig.initialPageRequest;
  int _totalItemCount = 0;
  List<FacilityProfile> _facilities = const <FacilityProfile>[];
  List<TenantProfile> _tenantOptions = const <TenantProfile>[];
  FacilityProfile? _scopedFacility;
  FacilityContactAddress _scopedContact = const FacilityContactAddress();
  FacilityEffectiveContact? _scopedEffectiveContact;
  String? _tenantFilterId;
  FacilitySetupType? _typeFilter;
  bool? _isActiveFilter;
  AppSearchBarFilterValue _filterValue = AppSearchBarFilterValue.empty;
  bool _mutated = false;
  int _reloadGeneration = 0;
  PlatformManagementListSync? _realtimeSync;

  bool get _canManage => ref.read(appAccessPolicyProvider).canManageFacility();

  bool get _canCreate => ref.read(appAccessPolicyProvider).canCreateFacility();

  bool get _canDelete => ref.read(appAccessPolicyProvider).canDeleteFacility();

  TenantFacilityFacilitiesListScope get _listScope =>
      tenantFacilityFacilitiesListScope(ref.read(appAccessPolicyProvider));

  bool get _isScopedFacilityManager => tenantFacilityUsesScopedFacilityPanel(
    canManageFacility: _canManage,
    canCreateFacility: _canCreate,
  );

  String? get _sessionTenantId {
    final String? fromWidget = widget.sessionTenantId?.trim();
    if (fromWidget != null && fromWidget.isNotEmpty) {
      return fromWidget;
    }
    final String? fromFacility = widget.sessionFacility?.tenantId.trim();
    if (fromFacility != null && fromFacility.isNotEmpty) {
      return fromFacility;
    }
    return ref.read(appAccessPolicyProvider).tenantId?.trim();
  }

  @override
  void initState() {
    super.initState();
    widget.reloadListenable?.addListener(_onReloadListenable);
    _searchController.addListener(_onSearchChanged);
    if (_isScopedFacilityManager) {
      _scopedFacility = widget.sessionFacility;
      if (_scopedFacility != null) {
        _loading = false;
      } else {
        unawaited(_reloadScopedFacility());
      }
    } else {
      if (tenantFacilityFacilitiesShowsTenantFilter(_listScope)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_loadTenants());
        });
      }
      unawaited(_reload(resetPage: true));
    }
  }

  @override
  void didUpdateWidget(covariant ManageFacilitiesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isScopedFacilityManager &&
        widget.sessionFacility != null &&
        widget.sessionFacility != oldWidget.sessionFacility) {
      _scopedFacility = _mergeScopedFacilityProfile(
        previous: _scopedFacility,
        incoming: widget.sessionFacility!,
        contact: _scopedContact,
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isScopedFacilityManager) {
      // Inherited phone/email follow tenant contact changes.
      _realtimeSync ??= PlatformManagementListSync(
        ref: ref,
        events: const <String>{
          RealtimeEvents.tenantUpdated,
          RealtimeEvents.facilityUpdated,
        },
        onMutated: () {},
        reload: ({bool silent = false, RealtimeMessage? message}) =>
            _reloadScopedFacility(silent: true),
      )..attach();
      return;
    }
    _realtimeSync ??= PlatformManagementListSync(
      ref: ref,
      events: _facilityManagementRealtimeEvents,
      onMutated: _markMutated,
      reload: ({bool silent = false, RealtimeMessage? message}) async {
        _applyFacilityRealtimeMessage(message);
        if (tenantFacilityFacilitiesShowsTenantFilter(_listScope)) {
          await _loadTenants();
        }
        await _reload(resetPage: false, silent: silent);
      },
    )..attach();
  }

  @override
  void dispose() {
    widget.reloadListenable?.removeListener(_onReloadListenable);
    _realtimeSync?.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onReloadListenable() {
    if (_isScopedFacilityManager) {
      unawaited(_reloadScopedFacility(silent: true));
      return;
    }
    unawaited(_reload(resetPage: false, silent: true));
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_reload(resetPage: true));
    });
  }

  Future<void> _reloadScopedFacility({bool silent = false}) async {
    final int generation = ++_reloadGeneration;
    if (!silent) {
      setState(() {
        _loading = true;
        _failure = null;
      });
    }

    final Result<FacilitySetupSnapshot> result = await ref
        .read(tenantFacilityRepositoryProvider)
        .loadSetup();

    if (!mounted || generation != _reloadGeneration) {
      return;
    }

    result.when(
      success: (FacilitySetupSnapshot snapshot) {
        setState(() {
          _loading = false;
          _failure = null;
          _scopedContact = snapshot.contactAddress;
          _scopedEffectiveContact = snapshot.facility == null
              ? null
              : snapshot.resolvedEffectiveContact;
          final FacilityProfile? loaded =
              snapshot.facility ?? widget.sessionFacility;
          _scopedFacility = loaded == null
              ? _scopedFacility
              : _mergeScopedFacilityProfile(
                  previous: _scopedFacility,
                  incoming: loaded,
                  contact: snapshot.contactAddress,
                );
        });
      },
      failure: (AppFailure failure) {
        setState(() {
          _loading = false;
          _failure = failure;
          if (!silent && _scopedFacility == null) {
            _scopedFacility = widget.sessionFacility;
          }
        });
      },
    );
  }

  FacilityProfile _mergeScopedFacilityProfile({
    required FacilityProfile? previous,
    required FacilityProfile incoming,
    FacilityContactAddress contact = const FacilityContactAddress(),
  }) {
    String? prefer(String? next, String? current) {
      final String? trimmedNext = next?.trim();
      if (trimmedNext != null && trimmedNext.isNotEmpty) {
        return trimmedNext;
      }
      final String? trimmedCurrent = current?.trim();
      if (trimmedCurrent != null && trimmedCurrent.isNotEmpty) {
        return trimmedCurrent;
      }
      return next ?? current;
    }

    final FacilityProfile base = previous == null
        ? incoming
        : incoming.copyWith(
            resourceUuid: incoming.resourceUuid ?? previous.resourceUuid,
            displayId: incoming.displayId ?? previous.displayId,
            logoUrl: prefer(incoming.logoUrl, previous.logoUrl),
            currency: prefer(incoming.currency, previous.currency),
            standardConsultationFee: prefer(
              incoming.standardConsultationFee,
              previous.standardConsultationFee,
            ),
            phone: prefer(incoming.phone, previous.phone),
            email: prefer(incoming.email, previous.email),
            addressLine1: prefer(incoming.addressLine1, previous.addressLine1),
            city: prefer(incoming.city, previous.city),
            country: prefer(incoming.country, previous.country),
          );

    return base.copyWith(
      phone: prefer(contact.phone, base.phone),
      email: prefer(contact.email, base.email),
      addressLine1: prefer(contact.addressLine1, base.addressLine1),
      city: prefer(contact.city, base.city),
      country: prefer(contact.country, base.country),
    );
  }

  Future<void> _editScopedFacility() async {
    final FacilityProfile? facility = _scopedFacility;
    if (facility == null || !mounted) {
      return;
    }

    final FacilityProfile? saved = await showTenantFacilityFacilityFormDialog(
      context,
      tenantId: facility.tenantId,
      facility: facility,
      requireTenantPicker: false,
      managementMode: true,
    );
    if (!mounted || saved == null) {
      return;
    }

    setState(() {
      _scopedFacility = _mergeScopedFacilityProfile(
        previous: facility,
        incoming: saved,
        contact: _scopedContact,
      );
      _failure = null;
    });

    _markMutated();
    unawaited(_reloadScopedFacility(silent: true));
  }

  Future<void> _loadTenants() async {
    if (!tenantFacilityFacilitiesShowsTenantFilter(_listScope)) {
      return;
    }
    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );
    final Result<AppPage<TenantProfile>> result = await repository.listTenants(
      request: PlatformAdminListConfig.initialPageRequest,
    );
    if (!mounted) return;
    result.when(
      success: (AppPage<TenantProfile> page) {
        setState(() {
          _tenantOptions = page.items;
        });
      },
      failure: (_) {},
    );
  }

  List<FacilityProfile> get _visibleFacilities {
    final String? status = _filterValue.option(_statusFilterKey);
    if (status == _statusActive) {
      return _facilities
          .where((FacilityProfile facility) => !facility.isDeleted)
          .toList(growable: false);
    }
    if (status == _statusDeleted) {
      return _facilities
          .where((FacilityProfile facility) => facility.isDeleted)
          .toList(growable: false);
    }
    return _facilities;
  }

  Future<void> _applyFacilityFilters(AppSearchBarFilterValue value) async {
    final String? nextTenant = value.option(_tenantFilterKey);
    final String? nextType = value.option(_typeFilterKey);
    final String? nextActive = value.option(_activeFilterKey);
    FacilitySetupType? parsedType;
    if (nextType != null) {
      for (final FacilitySetupType type in FacilitySetupType.values) {
        if (type.apiValue == nextType) {
          parsedType = type;
          break;
        }
      }
    }
    final bool? parsedActive = nextActive == _activeYes
        ? true
        : nextActive == _activeNo
        ? false
        : null;
    final bool filtersChanged =
        nextTenant != _tenantFilterId ||
        parsedType != _typeFilter ||
        parsedActive != _isActiveFilter;
    setState(() {
      _filterValue = value;
      _tenantFilterId = nextTenant;
      _typeFilter = parsedType;
      _isActiveFilter = parsedActive;
    });
    if (filtersChanged) {
      await _reload(resetPage: true, silent: _facilities.isNotEmpty);
    }
  }

  Future<void> _reload({required bool resetPage, bool silent = false}) async {
    if (resetPage) {
      _pageRequest = _pageRequest.first();
    }
    final int generation = ++_reloadGeneration;
    if (!silent) {
      setState(() {
        _loading = true;
        _failure = null;
      });
    }

    final TenantFacilityRepository repository = ref.read(
      tenantFacilityRepositoryProvider,
    );
    final String? listTenantId =
        _listScope == TenantFacilityFacilitiesListScope.tenant
        ? _sessionTenantId
        : _tenantFilterId;
    final Result<AppPage<FacilityProfile>> result = await repository
        .listFacilities(
          request: _pageRequest,
          tenantId: listTenantId,
          search: _searchController.text.trim(),
          type: _typeFilter,
          isActive: _isActiveFilter,
          includeDeleted: true,
        );

    if (!mounted || generation != _reloadGeneration) return;
    result.when(
      success: (AppPage<FacilityProfile> page) {
        final int activeCount = page.items
            .where(
              (FacilityProfile facility) =>
                  !facility.isDeleted && facility.isActive,
            )
            .length;
        final int totalItemCount = page.totalItemCount ?? page.items.length;
        final int visibleTotalCount = page.items
            .where((FacilityProfile facility) => !facility.isDeleted)
            .length;
        homeReconcileFacilitiesMetricFromList(
          ref,
          activeCount,
          totalCount: page.items.length == totalItemCount
              ? visibleTotalCount
              : totalItemCount,
        );
        setState(() {
          _loading = false;
          _facilities = page.items;
          _totalItemCount = totalItemCount;
        });
        widget.onListTotalChanged?.call(_totalItemCount);
      },
      failure: (AppFailure failure) {
        setState(() {
          _loading = false;
          _failure = failure;
          if (!silent) {
            _facilities = const <FacilityProfile>[];
          }
        });
      },
    );
  }

  Future<void> _onPageChanged(AppPageRequest request) async {
    _pageRequest = request;
    await _reload(resetPage: false);
  }

  Future<void> _openFacilityDetails(FacilityProfile facility) async {
    final AppLocalizations l10n = context.l10n;
    final bool? mutated = await showFacilityDetailsDialog(
      context,
      facility: facility,
      tenantName: _tenantLabel(facility.tenantId, l10n),
    );
    if (!mounted || mutated != true) {
      return;
    }

    _markMutated();
    await _loadTenants();
    await _reload(resetPage: false, silent: true);
  }

  Future<void> _openFacilityForm({
    FacilityProfile? facility,
    bool forceCreate = false,
  }) async {
    final bool isCreate = forceCreate || facility == null;
    final String? defaultTenantId =
        _listScope == TenantFacilityFacilitiesListScope.tenant
        ? _sessionTenantId
        : _tenantFilterId;
    final FacilityProfile? savedFacility =
        await showTenantFacilityFacilityFormDialog(
          context,
          tenantId: facility?.tenantId ?? defaultTenantId,
          facility: facility,
          requireTenantPicker:
              isCreate &&
              _listScope == TenantFacilityFacilitiesListScope.platform,
          managementMode: true,
        );
    if (!mounted || savedFacility == null) {
      return;
    }

    _markMutated();
    await _loadTenants();
    await _reload(resetPage: isCreate, silent: true);
    if (!mounted) {
      return;
    }

    if (isCreate) {
      _syncPlatformDashboard(
        ref,
        patch: HomeDashboardOptimisticPatch.facilityCreated(),
      );
      await _openFacilityDetails(savedFacility);
    }
  }

  Future<void> _confirmDeleteFacility(FacilityProfile facility) async {
    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AppConfirmActionDialog(
        title: l10n.tenantFacilityDeleteConfirmationTitle,
        body: l10n.tenantFacilityDeleteFacilityConfirmationBody(facility.name),
        highlightedText: facility.name,
        submitLabel: l10n.tenantFacilityDeleteConfirmAction,
        destructive: true,
        icon: const Icon(Icons.delete_outline),
        onConfirm: () async {
          final Result<void> result = await ref
              .read(tenantFacilityRepositoryProvider)
              .deleteFacility(facility.mutationId);
          return result.when(
            success: (_) => null,
            failure: (AppFailure failure) {
              if (failure.category == AppFailureCategory.notFound) {
                return null;
              }
              return failure;
            },
          );
        },
      ),
    );

    if (!mounted) {
      return;
    }

    if (confirmed == true) {
      _markMutated();
      _markFacilitySoftDeletedLocally(facility);
      _syncPlatformDashboard(
        ref,
        patch: HomeDashboardOptimisticPatch.facilityDeleted(
          isActive: facility.isActive && !facility.isDeleted,
        ),
      );
      await _loadTenants();
      await _reload(resetPage: false, silent: true);
    }
  }

  Future<void> _confirmRestoreFacility(FacilityProfile facility) async {
    final AppLocalizations l10n = context.l10n;
    FacilityProfile? restoredFacility;
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AppConfirmActionDialog(
        title: l10n.tenantFacilityRestoreFacilityConfirmationTitle,
        body: l10n.tenantFacilityRestoreFacilityConfirmationBody(facility.name),
        highlightedText: facility.name,
        submitLabel: l10n.tenantFacilityRestoreTenantAction,
        icon: const Icon(Icons.restore_outlined),
        onConfirm: () async {
          final Result<FacilityProfile> result = await ref
              .read(tenantFacilityRepositoryProvider)
              .restoreFacility(facility.mutationId);
          return result.when(
            success: (FacilityProfile value) {
              restoredFacility = value;
              return null;
            },
            failure: (AppFailure failure) => failure,
          );
        },
      ),
    );

    if (!mounted || confirmed != true) {
      return;
    }

    final FacilityProfile applied =
        restoredFacility ?? facility.copyWith(clearDeletedAt: true);
    _markFacilityRestoredLocally(applied);
    _markMutated();
    _syncPlatformDashboard(
      ref,
      patch: HomeDashboardOptimisticPatch.facilityCreated(
        isActive: applied.isActive,
      ),
    );
    await _loadTenants();
    await _reload(resetPage: false, silent: true);
    if (mounted) {
      _markFacilityRestoredLocally(applied);
    }
  }

  Future<void> _confirmPermanentDeleteFacility(FacilityProfile facility) async {
    final AppLocalizations l10n = context.l10n;
    final String? typed = await showAppDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AppTextInputActionDialog(
        title: l10n.tenantFacilityPermanentDeleteFacilityConfirmationTitle,
        description: l10n.tenantFacilityPermanentDeleteFacilityWarningBody(
          facility.name,
        ),
        fieldLabel: l10n.tenantFacilityPermanentDeleteConfirmFieldLabel(
          facility.name,
        ),
        submitLabel: l10n.tenantFacilityPermanentDeleteConfirmAction,
        cancelLabel: l10n.commonCancelActionLabel,
        requiredMessage: l10n.validationRequired,
        confirmExactValue: facility.name,
        confirmMismatchMessage: l10n
            .tenantFacilityPermanentDeleteConfirmFieldLabel(facility.name),
        destructive: true,
        minLines: 1,
        maxLines: 1,
        icon: const Icon(Icons.delete_forever_outlined),
      ),
    );

    if (!mounted || typed == null) {
      return;
    }
    if (typed.trim().toLowerCase() != facility.name.trim().toLowerCase()) {
      return;
    }

    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AppConfirmActionDialog(
        title: l10n.tenantFacilityPermanentDeleteFacilityConfirmationTitle,
        body: l10n.tenantFacilityPermanentDeleteFacilityConfirmationBody(
          facility.name,
        ),
        highlightedText: facility.name,
        submitLabel: l10n.tenantFacilityPermanentDeleteConfirmAction,
        destructive: true,
        icon: const Icon(Icons.delete_forever_outlined),
        onConfirm: () async {
          final Result<void> result = await ref
              .read(tenantFacilityRepositoryProvider)
              .permanentDeleteFacility(facility.mutationId);
          return result.when(
            success: (_) => null,
            failure: (AppFailure failure) {
              if (failure.category == AppFailureCategory.notFound) {
                return null;
              }
              return failure;
            },
          );
        },
      ),
    );

    if (!mounted || confirmed != true) {
      return;
    }

    _markMutated();
    _removeFacilityLocally(facility.mutationId);
    _syncPlatformDashboard(ref);
    await _loadTenants();
    await _reload(resetPage: false, silent: true);
  }

  void _markFacilitySoftDeletedLocally(FacilityProfile facility) {
    final int index = _facilities.indexWhere(
      (FacilityProfile entry) =>
          entry.id == facility.id || entry.mutationId == facility.mutationId,
    );
    if (index < 0) {
      return;
    }
    final List<FacilityProfile> next = List<FacilityProfile>.of(_facilities);
    next[index] = facility.copyWith(deletedAt: DateTime.now().toUtc());
    setState(() {
      _facilities = next;
    });
  }

  void _markFacilityRestoredLocally(FacilityProfile facility) {
    final int index = _facilities.indexWhere(
      (FacilityProfile entry) =>
          entry.id == facility.id || entry.mutationId == facility.mutationId,
    );
    if (index < 0) {
      return;
    }
    final List<FacilityProfile> next = List<FacilityProfile>.of(_facilities);
    next[index] = facility.copyWith(clearDeletedAt: true);
    setState(() {
      _facilities = next;
    });
  }

  void _removeFacilityLocally(String facilityId) {
    final int before = _facilities.length;
    final List<FacilityProfile> next = _facilities
        .where(
          (FacilityProfile entry) =>
              entry.id != facilityId && entry.mutationId != facilityId,
        )
        .toList(growable: false);
    if (next.length == before) {
      return;
    }
    setState(() {
      _facilities = next;
      _totalItemCount = math.max(0, _totalItemCount - (before - next.length));
    });
  }

  void _applyFacilityRealtimeMessage(RealtimeMessage? message) {
    if (message == null) {
      return;
    }

    final String? facilityId = _managementResourceIdFromMessage(
      message,
      keys: const <String>['resource_id', 'facility_id', 'id'],
    );

    switch (message.event) {
      case RealtimeEvents.facilityDeleted:
        if (facilityId == null) {
          return;
        }
        final int index = _facilities.indexWhere(
          (FacilityProfile entry) =>
              entry.id == facilityId || entry.mutationId == facilityId,
        );
        if (index < 0) {
          return;
        }
        final List<FacilityProfile> next = List<FacilityProfile>.of(
          _facilities,
        );
        next[index] = next[index].copyWith(deletedAt: DateTime.now().toUtc());
        setState(() {
          _facilities = next;
        });
        return;
      case RealtimeEvents.facilityPermanentlyDeleted:
        if (facilityId != null) {
          _removeFacilityLocally(facilityId);
        }
        return;
      case RealtimeEvents.facilityRestored:
      case RealtimeEvents.facilityCreated:
      case RealtimeEvents.facilityUpdated:
        return;
    }
  }

  String _facilityStatusLabel(AppLocalizations l10n, FacilityProfile facility) {
    if (facility.isDeleted) {
      return l10n.tenantFacilityTenantStatusDeleted;
    }
    return facility.isActive
        ? l10n.tenantFacilityTenantStatusActive
        : l10n.commonNoLabel;
  }

  void _markMutated() {
    _mutated = true;
    widget.onMutated?.call(true);
  }

  String _tenantLabel(String tenantId, AppLocalizations l10n) {
    for (final TenantProfile tenant in _tenantOptions) {
      if (tenant.id == tenantId) {
        return tenant.name;
      }
    }
    return l10n.profileUnknownValue;
  }

  String _facilityCodeLabel(FacilityProfile facility) {
    return tenantFacilityHumanFriendlyDisplayId(
          facility.displayId,
          opaqueId: facility.resourceUuid ?? facility.id,
        ) ??
        '—';
  }

  String _optionalText(String? value) {
    final String? trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return '—';
    }
    return trimmed;
  }

  /// Effective phone for table cells, marked when inherited from the tenant.
  String _facilityPhoneLabel(AppLocalizations l10n, FacilityProfile facility) {
    final FacilityEffectiveContact contact = facility.displayContact;
    return tenantFacilityContactCellLabel(
      l10n,
      contact.phone,
      inherited: contact.isPhoneInherited,
    );
  }

  /// Effective email for table cells, marked when inherited from the tenant.
  String _facilityEmailLabel(AppLocalizations l10n, FacilityProfile facility) {
    final FacilityEffectiveContact contact = facility.displayContact;
    return tenantFacilityContactCellLabel(
      l10n,
      contact.email,
      inherited: contact.isEmailInherited,
    );
  }

  Widget _buildScopedBody(AppLocalizations l10n) {
    if (_loading && _scopedFacility == null) {
      return AppWorkspaceStatePanel.loading(
        title: l10n.tenantFacilityFacilityDetailsTitle,
        body: l10n.commonLoadingBody,
      );
    }

    if (_failure != null && _scopedFacility == null) {
      return AppFailureStateView(failure: _failure!);
    }

    final FacilityProfile? facility = _scopedFacility;
    if (facility == null) {
      return AppWorkspaceStatePanel.empty(
        title: l10n.tenantFacilityManageFacilitiesTitle,
        body: l10n.tenantFacilityNoFacilities,
        icon: Icons.domain_outlined,
      );
    }

    final ThemeData theme = Theme.of(context);
    final String statusLabel = _facilityStatusLabel(l10n, facility);
    final AppWorkspaceStatusTone statusTone = facility.isDeleted
        ? AppWorkspaceStatusTone.error
        : (facility.isActive
              ? AppWorkspaceStatusTone.success
              : AppWorkspaceStatusTone.neutral);
    final bool canEditFacility = _canManage && !facility.isDeleted;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        theme.spacing.md,
        theme.spacing.sm,
        theme.spacing.md,
        theme.spacing.md,
      ),
      child: _FacilityScopedDetailsSummary(
        facility: facility,
        effectiveContact: FacilityEffectiveContact.resolve(
          ownPhone: facility.phone,
          ownEmail: facility.email,
          inherited: _scopedEffectiveContact ?? facility.effectiveContact,
        ),
        statusLabel: statusLabel,
        statusTone: statusTone,
        onEdit: canEditFacility ? _editScopedFacility : null,
        editLabel: l10n.tenantFacilityEditFacilityAction,
      ),
    );
  }

  Widget _buildTableBody(AppLocalizations l10n) {
    final List<FacilityProfile> visibleFacilities = _visibleFacilities;
    final bool showTenantColumn = tenantFacilityFacilitiesShowsTenantColumn(
      _listScope,
    );
    final bool showTenantFilter = tenantFacilityFacilitiesShowsTenantFilter(
      _listScope,
    );
    final bool hasActiveFilters =
        (showTenantFilter && _filterValue.option(_tenantFilterKey) != null) ||
        _filterValue.option(_typeFilterKey) != null ||
        _filterValue.option(_statusFilterKey) != null ||
        _filterValue.option(_activeFilterKey) != null;
    final bool statusFiltered = _filterValue.option(_statusFilterKey) != null;

    if (_failure != null) {
      return AppFailureStateView(failure: _failure!);
    }

    return AppListTable<FacilityProfile>(
      page: AppPage<FacilityProfile>(
        items: visibleFacilities,
        request: _pageRequest,
        totalItemCount: statusFiltered
            ? visibleFacilities.length
            : _totalItemCount,
      ),
      isLoading: _loading,
      itemKeyBuilder: (FacilityProfile item) => ValueKey<String>(item.id),
      onRowSelected: (FacilityProfile facility) {
        unawaited(_openFacilityDetails(facility));
      },
      previousPageLabel: l10n.hrPreviousPageLabel,
      nextPageLabel: l10n.hrNextPageLabel,
      pageLabelBuilder: (AppPage<FacilityProfile> page) {
        if (_loading) {
          return '';
        }
        final int total = page.totalItemCount ?? page.items.length;
        if (total == 0) return l10n.commonTableEmptyLabel;
        final int start = page.pageIndex * page.pageSize + 1;
        final int end = start + page.items.length - 1;
        return '$start-$end / $total';
      },
      onPageChanged: _onPageChanged,
      columnVisibilityStorageKey: showTenantColumn
          ? 'setup_manage_facilities_v5'
          : 'setup_manage_facilities_tenant_v3',
      columnVisibilityLabel: l10n.commonTableSettingsActionLabel,
      columnVisibilityTitle: l10n.commonTableSettingsTitle,
      columnVisibilityApplyLabel: l10n.receptionApplyColumnsAction,
      columnVisibilityResetLabel: l10n.receptionResetColumnsAction,
      columnVisibilityCloseLabel: l10n.commonCloseActionLabel,
      canExport: canExportTenantFacilitySetup(ref.watch(appAccessPolicyProvider)),
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
      canPrint: canPrintTenantFacilitySetup(ref.watch(appAccessPolicyProvider)),
      printLabel: l10n.commonPrintActionLabel,
      onPrint: (List<FacilityProfile> matching) =>
          printTenantFacilitySetupListTable<FacilityProfile>(
        ref: ref,
        context: context,
        title: l10n.tenantFacilityManageFacilitiesTitle,
        columns: <AppListTableColumn<FacilityProfile>>[
          AppListTableColumn<FacilityProfile>(
            id: 'name',
            label: l10n.authFacilityNameLabel,
            exportValue: (FacilityProfile facility) => facility.name,
            cellBuilder: (_, FacilityProfile facility) =>
                tenantFacilitySetupAtomicCell(
                  facility.name,
                  muted: facility.isDeleted,
                ),
          ),
          AppListTableColumn<FacilityProfile>(
            id: 'type',
            label: l10n.profileFacilityTypeLabel,
            exportValue: (FacilityProfile facility) =>
                tenantFacilityFacilityTypeLabel(l10n, facility.type),
            cellBuilder: (_, FacilityProfile facility) =>
                tenantFacilitySetupAtomicCell(
                  tenantFacilityFacilityTypeLabel(l10n, facility.type),
                ),
          ),
          AppListTableColumn<FacilityProfile>(
            id: 'status',
            label: l10n.tenantFacilityTenantStatusLabel,
            exportValue: (FacilityProfile facility) =>
                _facilityStatusLabel(l10n, facility),
            cellBuilder: (_, FacilityProfile facility) =>
                tenantFacilitySetupAtomicCell(
                  _facilityStatusLabel(l10n, facility),
                ),
          ),
          AppListTableColumn<FacilityProfile>(
            id: 'tenant',
            label: l10n.profileTenantLabel,
            exportValue: (FacilityProfile facility) =>
                _tenantLabel(facility.tenantId, l10n),
            cellBuilder: (_, FacilityProfile facility) =>
                tenantFacilitySetupAtomicCell(
                  _tenantLabel(facility.tenantId, l10n),
                ),
          ),
          AppListTableColumn<FacilityProfile>(
            id: 'code',
            label: l10n.tenantFacilityFacilityIdLabel,
            exportValue: (FacilityProfile facility) =>
                _facilityCodeLabel(facility),
            cellBuilder: (_, FacilityProfile facility) =>
                tenantFacilitySetupAtomicCell(_facilityCodeLabel(facility)),
          ),
          AppListTableColumn<FacilityProfile>(
            id: 'phone',
            label: l10n.profilePhoneLabel,
            exportValue: (FacilityProfile facility) =>
                _facilityPhoneLabel(l10n, facility),
            cellBuilder: (_, FacilityProfile facility) =>
                tenantFacilitySetupAtomicCell(
                  _facilityPhoneLabel(l10n, facility),
                ),
          ),
          AppListTableColumn<FacilityProfile>(
            id: 'email',
            label: l10n.profileEmailLabel,
            exportValue: (FacilityProfile facility) =>
                _facilityEmailLabel(l10n, facility),
            cellBuilder: (_, FacilityProfile facility) =>
                tenantFacilitySetupAtomicCell(
                  _facilityEmailLabel(l10n, facility),
                ),
          ),
        ],
        items: matching,
        emptyText: l10n.tenantFacilityNoFacilities,
      ),
      goToTopLabel: l10n.commonGoToTopActionLabel,
      loadingMoreLabel: l10n.commonLoadingMoreLabel,
      allRowsLoadedLabel: l10n.commonAllRowsLoadedLabel,
      exportConfig: AppListTableExportConfig<FacilityProfile>(
        fileNameStem: 'setup_facilities',
        dateOf: (_) => null,
        sheetName: l10n.tenantFacilityManageFacilitiesTitle,
        enableDateFilter: false,
        dateFromLabel: l10n.commonTableExportDateFromLabel,
        dateToLabel: l10n.commonTableExportDateToLabel,
      ),
      search: AppListTableSearch<FacilityProfile>(
        controller: _searchController,
        hintText: l10n.tenantFacilitySearchLabel,
        semanticLabel: l10n.tenantFacilitySearchLabel,
        matcher: (_, _) => true,
        onSubmitted: (_) => unawaited(_reload(resetPage: true)),
        onClear: () => unawaited(_reload(resetPage: true)),
        enableDateFilter: false,
        showAdvancedFilterButton: true,
        advancedFilterButtonLabel: l10n.commonFiltersActionLabel,
        advancedFilterTitle: l10n.commonAdvancedFiltersTitle,
        advancedFilterApplyLabel: l10n.opdApplyFiltersAction,
        advancedFilterResetLabel: l10n.opdClearFiltersAction,
        advancedFilterCloseLabel: l10n.commonCloseActionLabel,
        filterGroups: <AppSearchBarFilterGroup>[
          if (showTenantFilter && _tenantOptions.isNotEmpty)
            AppSearchBarFilterGroup(
              key: _tenantFilterKey,
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
          AppSearchBarFilterGroup(
            key: _typeFilterKey,
            label: l10n.profileFacilityTypeLabel,
            allLabel: l10n.commonAllLabel,
            choices: FacilitySetupType.values
                .map(
                  (FacilitySetupType type) => AppSearchBarFilterChoice(
                    value: type.apiValue,
                    label: tenantFacilityFacilityTypeLabel(l10n, type),
                    icon: tenantFacilityFacilityTypeIcon(type),
                  ),
                )
                .toList(growable: false),
          ),
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
          AppSearchBarFilterGroup(
            key: _activeFilterKey,
            label: l10n.tenantFacilityActiveLabel,
            allLabel: l10n.commonAllLabel,
            choices: <AppSearchBarFilterChoice>[
              AppSearchBarFilterChoice(
                value: _activeYes,
                label: l10n.tenantFacilityTenantStatusActive,
                icon: Icons.toggle_on_outlined,
              ),
              AppSearchBarFilterChoice(
                value: _activeNo,
                label: l10n.tenantFacilityStatusInactive,
                icon: Icons.toggle_off_outlined,
              ),
            ],
          ),
        ],
        filterValue: _filterValue,
        hasActiveFilters: hasActiveFilters,
        onFilterChanged: (AppSearchBarFilterValue value) {
          unawaited(_applyFacilityFilters(value));
        },
        trailingActions: widget.showCreateAction && _canCreate
            ? <AppSearchBarAction>[
                AppSearchBarAction(
                  icon: Icons.add_business_outlined,
                  label: l10n.tenantFacilityAddFacilityAction,
                  tooltip: l10n.tenantFacilityAddFacilityAction,
                  onPressed: _loading
                      ? null
                      : () => unawaited(_openFacilityForm(forceCreate: true)),
                ),
              ]
            : const <AppSearchBarAction>[],
      ),
      columns: <AppListTableColumn<FacilityProfile>>[
        AppListTableColumn<FacilityProfile>(
          id: 'name',
          label: l10n.authFacilityNameLabel,
          preferredWidth: 220,
          sortComparator: (FacilityProfile left, FacilityProfile right) =>
              appListTableCompareText(left.name, right.name),
          exportValue: (FacilityProfile facility) => facility.name,
          cellBuilder: (_, FacilityProfile facility) {
            return tenantFacilitySetupAtomicCell(
              facility.name,
              muted: facility.isDeleted,
            );
          },
        ),
        if (showTenantColumn)
          AppListTableColumn<FacilityProfile>(
            id: 'tenant',
            label: l10n.profileTenantLabel,
            sortComparator: (FacilityProfile left, FacilityProfile right) =>
                appListTableCompareText(
                  _tenantLabel(left.tenantId, l10n),
                  _tenantLabel(right.tenantId, l10n),
                ),
            exportValue: (FacilityProfile facility) =>
                _tenantLabel(facility.tenantId, l10n),
            cellBuilder: (_, FacilityProfile facility) =>
                tenantFacilitySetupAtomicCell(
                  _tenantLabel(facility.tenantId, l10n),
                ),
          ),
        AppListTableColumn<FacilityProfile>(
          id: 'type',
          label: l10n.profileFacilityTypeLabel,
          sortComparator: (FacilityProfile left, FacilityProfile right) =>
              appListTableCompareText(
                tenantFacilityFacilityTypeLabel(l10n, left.type),
                tenantFacilityFacilityTypeLabel(l10n, right.type),
              ),
          exportValue: (FacilityProfile facility) =>
              tenantFacilityFacilityTypeLabel(l10n, facility.type),
          cellBuilder: (_, FacilityProfile facility) =>
              tenantFacilitySetupAtomicCell(
                tenantFacilityFacilityTypeLabel(l10n, facility.type),
              ),
        ),
        if (!showTenantColumn)
          AppListTableColumn<FacilityProfile>(
            id: 'code',
            label: l10n.tenantFacilityFacilityIdLabel,
            sortComparator: (FacilityProfile left, FacilityProfile right) =>
                appListTableCompareText(
                  _facilityCodeLabel(left),
                  _facilityCodeLabel(right),
                ),
            exportValue: (FacilityProfile facility) =>
                _facilityCodeLabel(facility),
            cellBuilder: (_, FacilityProfile facility) =>
                tenantFacilitySetupAtomicCell(_facilityCodeLabel(facility)),
          ),
        AppListTableColumn<FacilityProfile>(
          id: 'status',
          label: l10n.tenantFacilityTenantStatusLabel,
          sortComparator: (FacilityProfile left, FacilityProfile right) =>
              appListTableCompareText(
                _facilityStatusLabel(l10n, left),
                _facilityStatusLabel(l10n, right),
              ),
          exportValue: (FacilityProfile facility) =>
              _facilityStatusLabel(l10n, facility),
          cellBuilder: (_, FacilityProfile facility) =>
              tenantFacilitySetupAtomicCell(
                _facilityStatusLabel(l10n, facility),
                muted: facility.isDeleted,
              ),
        ),
        if (_canManage)
          AppListTableColumn<FacilityProfile>(
            id: 'actions',
            label: l10n.accessAdminColumnActions,
            alwaysVisible: true,
            exportable: false,
            cellBuilder: (BuildContext context, FacilityProfile facility) {
              return GestureDetector(
                onTap: () {},
                child: _FacilityManagementRowActions(
                  enabled: !_loading,
                  facility: facility,
                  canDelete: _canDelete,
                  editLabel: l10n.tenantFacilityEditAction,
                  deleteLabel: l10n.tenantFacilityDeleteAction,
                  restoreLabel: l10n.tenantFacilityRestoreTenantAction,
                  permanentDeleteLabel:
                      l10n.tenantFacilityPermanentDeleteAction,
                  onEdit: () =>
                      unawaited(_openFacilityForm(facility: facility)),
                  onDelete: () => unawaited(_confirmDeleteFacility(facility)),
                  onRestore: () => unawaited(_confirmRestoreFacility(facility)),
                  onPermanentDelete: () =>
                      unawaited(_confirmPermanentDeleteFacility(facility)),
                ),
              );
            },
          ),
      ],
      columnChoices: <AppListTableColumn<FacilityProfile>>[
        if (showTenantColumn)
          AppListTableColumn<FacilityProfile>(
            id: 'code',
            label: l10n.tenantFacilityFacilityIdLabel,
            sortComparator: (FacilityProfile left, FacilityProfile right) =>
                appListTableCompareText(
                  _facilityCodeLabel(left),
                  _facilityCodeLabel(right),
                ),
            exportValue: (FacilityProfile facility) =>
                _facilityCodeLabel(facility),
            cellBuilder: (_, FacilityProfile facility) =>
                tenantFacilitySetupAtomicCell(_facilityCodeLabel(facility)),
          ),
        AppListTableColumn<FacilityProfile>(
          id: 'phone',
          label: l10n.profilePhoneLabel,
          sortComparator: (FacilityProfile left, FacilityProfile right) =>
              appListTableCompareText(
                left.displayContact.phone,
                right.displayContact.phone,
              ),
          exportValue: (FacilityProfile facility) =>
              _facilityPhoneLabel(l10n, facility),
          cellBuilder: (_, FacilityProfile facility) =>
              tenantFacilitySetupAtomicCell(
                _facilityPhoneLabel(l10n, facility),
              ),
        ),
        AppListTableColumn<FacilityProfile>(
          id: 'email',
          label: l10n.profileEmailLabel,
          sortComparator: (FacilityProfile left, FacilityProfile right) =>
              appListTableCompareText(
                left.displayContact.email,
                right.displayContact.email,
              ),
          exportValue: (FacilityProfile facility) =>
              _facilityEmailLabel(l10n, facility),
          cellBuilder: (_, FacilityProfile facility) =>
              tenantFacilitySetupAtomicCell(
                _facilityEmailLabel(l10n, facility),
              ),
        ),
        AppListTableColumn<FacilityProfile>(
          id: 'address',
          label: l10n.tenantFacilityAddressLineLabel,
          sortComparator: (FacilityProfile left, FacilityProfile right) =>
              appListTableCompareText(left.addressLine1, right.addressLine1),
          exportValue: (FacilityProfile facility) =>
              _optionalText(facility.addressLine1),
          cellBuilder: (_, FacilityProfile facility) =>
              tenantFacilitySetupAtomicCell(
                _optionalText(facility.addressLine1),
              ),
        ),
        AppListTableColumn<FacilityProfile>(
          id: 'city',
          label: l10n.tenantFacilityCityLabel,
          sortComparator: (FacilityProfile left, FacilityProfile right) =>
              appListTableCompareText(left.city, right.city),
          exportValue: (FacilityProfile facility) =>
              _optionalText(facility.city),
          cellBuilder: (_, FacilityProfile facility) =>
              tenantFacilitySetupAtomicCell(_optionalText(facility.city)),
        ),
        AppListTableColumn<FacilityProfile>(
          id: 'country',
          label: l10n.tenantFacilityCountryLabel,
          sortComparator: (FacilityProfile left, FacilityProfile right) =>
              appListTableCompareText(left.country, right.country),
          exportValue: (FacilityProfile facility) =>
              _optionalText(facility.country),
          cellBuilder: (_, FacilityProfile facility) =>
              tenantFacilitySetupAtomicCell(_optionalText(facility.country)),
        ),
        AppListTableColumn<FacilityProfile>(
          id: 'currency',
          label: l10n.tenantFacilityDefaultCurrencyLabel,
          sortComparator: (FacilityProfile left, FacilityProfile right) =>
              appListTableCompareText(left.currency, right.currency),
          exportValue: (FacilityProfile facility) =>
              _optionalText(facility.currency),
          cellBuilder: (_, FacilityProfile facility) =>
              tenantFacilitySetupAtomicCell(_optionalText(facility.currency)),
        ),
        AppListTableColumn<FacilityProfile>(
          id: 'consultation_fee',
          label: l10n.settingsConfigurationConsultationFeeLabel,
          sortComparator: (FacilityProfile left, FacilityProfile right) =>
              appListTableCompareText(
                left.standardConsultationFee,
                right.standardConsultationFee,
              ),
          exportValue: (FacilityProfile facility) =>
              _optionalText(facility.standardConsultationFee),
          cellBuilder: (_, FacilityProfile facility) =>
              tenantFacilitySetupAtomicCell(
                _optionalText(facility.standardConsultationFee),
              ),
        ),
        AppListTableColumn<FacilityProfile>(
          id: 'logo',
          label: l10n.tenantFacilityLogoLabel,
          sortComparator: (FacilityProfile left, FacilityProfile right) {
            final bool leftHas = left.logoUrl?.trim().isNotEmpty == true;
            final bool rightHas = right.logoUrl?.trim().isNotEmpty == true;
            return (leftHas ? 1 : 0).compareTo(rightHas ? 1 : 0);
          },
          exportValue: (FacilityProfile facility) =>
              facility.logoUrl?.trim().isNotEmpty == true
              ? l10n.commonYesLabel
              : '—',
          cellBuilder: (_, FacilityProfile facility) =>
              tenantFacilitySetupAtomicCell(
                facility.logoUrl?.trim().isNotEmpty == true
                    ? l10n.commonYesLabel
                    : '—',
              ),
        ),
      ],
      emptyBuilder: (_) => AppWorkspaceStatePanel.empty(
        title: l10n.tenantFacilityManageFacilitiesTitle,
        body: l10n.tenantFacilityNoFacilities,
        action: widget.showCreateAction && _canCreate
            ? AppButton.primary(
                label: l10n.tenantFacilityAddFacilityAction,
                leadingIcon: Icons.add_business_outlined,
                enabled: !_loading,
                onPressed: _loading
                    ? null
                    : () => unawaited(_openFacilityForm(forceCreate: true)),
              )
            : null,
      ),
      mobileItemBuilder: (BuildContext context, FacilityProfile facility) {
        return AppListTableMobileItem(
          title: facility.name,
          caption: showTenantColumn
              ? _tenantLabel(facility.tenantId, l10n)
              : tenantFacilityFacilityTypeLabel(l10n, facility.type),
          meta: <AppListTableMobileMeta>[
            AppListTableMobileMeta(label: _facilityStatusLabel(l10n, facility)),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final Widget body = _isScopedFacilityManager
        ? _buildScopedBody(l10n)
        : _buildTableBody(l10n);

    if (!widget.dialogMode) {
      return body;
    }

    return AppDialog(
      title: Text(l10n.tenantFacilityManageFacilitiesTitle),
      icon: const Icon(Icons.domain_outlined),
      pinActionsToBottom: true,
      maxWidth: 1040,
      content: SizedBox(height: 560, child: body),
      actions: <Widget>[
        if (!_isScopedFacilityManager && widget.showCreateAction && _canCreate)
          AppButton.primary(
            label: l10n.tenantFacilityAddFacilityAction,
            leadingIcon: Icons.add_business_outlined,
            onPressed: _loading
                ? null
                : () => unawaited(_openFacilityForm(forceCreate: true)),
          ),
        AppButton.secondary(
          label: l10n.commonCloseActionLabel,
          leadingIcon: Icons.close,
          onPressed: () => Navigator.of(context).pop(_mutated ? true : null),
        ),
      ],
    );
  }
}

class _FacilityScopedDetailsSummary extends StatelessWidget {
  const _FacilityScopedDetailsSummary({
    required this.facility,
    required this.effectiveContact,
    required this.statusLabel,
    required this.statusTone,
    this.onEdit,
    this.editLabel,
  });

  final FacilityProfile facility;

  /// Phone/email with tenant fallback.
  final FacilityEffectiveContact effectiveContact;
  final String statusLabel;
  final AppWorkspaceStatusTone statusTone;
  final Future<void> Function()? onEdit;
  final String? editLabel;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final Future<void> Function()? editAction = onEdit;
    final String? resolvedEditLabel = editLabel;
    final String emptyValue = l10n.profileUnknownValue;
    final Set<String> emptyPlaceholders = <String>{emptyValue, '—'};
    final String? displayId = tenantFacilityHumanFriendlyDisplayId(
      facility.displayId,
      opaqueId: facility.resourceUuid ?? facility.id,
    );

    final List<Widget> headerActions = <Widget>[
      if (editAction != null &&
          resolvedEditLabel != null &&
          resolvedEditLabel.isNotEmpty)
        AppButton.secondary(
          label: resolvedEditLabel,
          leadingIcon: Icons.edit_outlined,
          onPressed: () {
            unawaited(editAction());
          },
        ),
    ];

    Widget section({
      required String title,
      required IconData icon,
      required List<AppInfoSheetItem> items,
      int maxColumns = 3,
      Widget? footer,
    }) {
      final Widget grid = AppInfoSheetGrid(
        emptyValue: emptyValue,
        maxColumns: maxColumns,
        items: items,
      );
      return AppCollapsibleSection(
        title: title,
        titleIcon: icon,
        child: footer == null
            ? grid
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  grid,
                  SizedBox(height: theme.spacing.sm),
                  footer,
                ],
              ),
      );
    }

    final Widget sections = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: appCollapsibleSectionSpacing(context, <Widget>[
        AppCollapsibleSection(
          collapsible: false,
          headerActions: headerActions,
          titleWidget: Row(
            children: <Widget>[
              _FacilityLogoAvatar(logoUrl: facility.logoUrl),
              SizedBox(width: theme.spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      facility.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: AppFontWeight.strong,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (displayId != null) ...<Widget>[
                      SizedBox(height: theme.spacing.xs / 2),
                      Text(
                        displayId,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: _TenantStatusBadge(label: statusLabel, tone: statusTone),
          ),
        ),
        section(
          title: l10n.hrStaffOverviewSectionTitle,
          icon: Icons.info_outline,
          items: <AppInfoSheetItem>[
            AppInfoSheetItem(
              label: l10n.profileFacilityTypeLabel,
              value: tenantFacilityFacilityTypeLabel(l10n, facility.type),
            ),
            AppInfoSheetItem(
              label: l10n.tenantFacilityFacilityIdLabel,
              value: displayId,
              copyable: displayId != null,
              copyTooltip: l10n.copyIdentifierAction,
              copiedMessage: l10n.identifierCopiedMessage,
              copyPlaceholderValues: emptyPlaceholders,
            ),
            AppInfoSheetItem(
              label: l10n.tenantFacilityTenantStatusLabel,
              value: statusLabel,
            ),
          ],
        ),
        section(
          title: l10n.tenantFacilityFacilityDetailsContactHeading,
          icon: Icons.contact_mail_outlined,
          footer:
              effectiveContact.isPhoneInherited ||
                  effectiveContact.isEmailInherited
              ? TenantFacilityInheritedContactNote(
                  message: l10n.tenantFacilityInheritedContactNote,
                )
              : null,
          items: <AppInfoSheetItem>[
            AppInfoSheetItem(
              label: effectiveContact.isPhoneInherited
                  ? l10n.tenantFacilityInheritedContactLabel(
                      l10n.profilePhoneLabel,
                    )
                  : l10n.profilePhoneLabel,
              value: effectiveContact.phone,
            ),
            AppInfoSheetItem(
              label: effectiveContact.isEmailInherited
                  ? l10n.tenantFacilityInheritedContactLabel(
                      l10n.profileEmailLabel,
                    )
                  : l10n.profileEmailLabel,
              value: effectiveContact.email,
            ),
            AppInfoSheetItem(
              label: l10n.tenantFacilityAddressLineLabel,
              value: facility.addressLine1,
            ),
            AppInfoSheetItem(
              label: l10n.tenantFacilityCityLabel,
              value: facility.city,
            ),
            AppInfoSheetItem(
              label: l10n.tenantFacilityCountryLabel,
              value: facility.country,
            ),
          ],
        ),
        section(
          title: l10n.settingsConfigurationTenantTitle,
          icon: Icons.tune_outlined,
          maxColumns: 2,
          items: <AppInfoSheetItem>[
            AppInfoSheetItem(
              label: l10n.tenantFacilityDefaultCurrencyLabel,
              value: facility.currency,
            ),
            AppInfoSheetItem(
              label: l10n.settingsConfigurationConsultationFeeLabel,
              value: facility.standardConsultationFee,
            ),
          ],
        ),
      ]),
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (!constraints.hasBoundedHeight) {
          return sections;
        }
        return SingleChildScrollView(child: sections);
      },
    );
  }
}

class _TenantManagementRowActions extends StatelessWidget {
  const _TenantManagementRowActions({
    required this.enabled,
    required this.tenant,
    required this.canDelete,
    required this.editLabel,
    required this.deleteLabel,
    required this.restoreLabel,
    required this.permanentDeleteLabel,
    required this.onEdit,
    required this.onDelete,
    required this.onRestore,
    required this.onPermanentDelete,
  });

  final bool enabled;
  final TenantProfile tenant;
  final bool canDelete;
  final String editLabel;
  final String deleteLabel;
  final String restoreLabel;
  final String permanentDeleteLabel;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRestore;
  final VoidCallback onPermanentDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final double actionGap = theme.spacing.md;

    if (tenant.isDeleted) {
      if (!canDelete) {
        return const SizedBox.shrink();
      }
      return Wrap(
        spacing: actionGap,
        runSpacing: theme.spacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          AppButton.tertiary(
            leadingIcon: Icons.restore_outlined,
            label: restoreLabel,
            semanticLabel: restoreLabel,
            tooltip: restoreLabel,
            enabled: enabled,
            onPressed: enabled ? onRestore : null,
          ),
          AppButton.tertiary(
            leadingIcon: Icons.delete_forever_outlined,
            label: permanentDeleteLabel,
            semanticLabel: permanentDeleteLabel,
            tooltip: permanentDeleteLabel,
            color: colorScheme.error,
            enabled: enabled,
            onPressed: enabled ? onPermanentDelete : null,
          ),
        ],
      );
    }

    return Wrap(
      spacing: actionGap,
      runSpacing: theme.spacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        AppButton.tertiary(
          leadingIcon: Icons.edit_outlined,
          label: editLabel,
          semanticLabel: editLabel,
          tooltip: editLabel,
          enabled: enabled,
          onPressed: enabled ? onEdit : null,
        ),
        if (canDelete)
          AppButton.tertiary(
            leadingIcon: Icons.delete_outline,
            label: deleteLabel,
            semanticLabel: deleteLabel,
            tooltip: deleteLabel,
            color: colorScheme.error,
            enabled: enabled,
            onPressed: enabled ? onDelete : null,
          ),
      ],
    );
  }
}

class _FacilityManagementRowActions extends StatelessWidget {
  const _FacilityManagementRowActions({
    required this.enabled,
    required this.facility,
    required this.canDelete,
    required this.editLabel,
    required this.deleteLabel,
    required this.restoreLabel,
    required this.permanentDeleteLabel,
    required this.onEdit,
    required this.onDelete,
    required this.onRestore,
    required this.onPermanentDelete,
  });

  final bool enabled;
  final FacilityProfile facility;
  final bool canDelete;
  final String editLabel;
  final String deleteLabel;
  final String restoreLabel;
  final String permanentDeleteLabel;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRestore;
  final VoidCallback onPermanentDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final double actionGap = theme.spacing.md;

    if (facility.isDeleted) {
      if (!canDelete) {
        return const SizedBox.shrink();
      }
      return Wrap(
        spacing: actionGap,
        runSpacing: theme.spacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          AppButton.tertiary(
            leadingIcon: Icons.restore_outlined,
            label: restoreLabel,
            semanticLabel: restoreLabel,
            tooltip: restoreLabel,
            enabled: enabled,
            onPressed: enabled ? onRestore : null,
          ),
          AppButton.tertiary(
            leadingIcon: Icons.delete_forever_outlined,
            label: permanentDeleteLabel,
            semanticLabel: permanentDeleteLabel,
            tooltip: permanentDeleteLabel,
            color: colorScheme.error,
            enabled: enabled,
            onPressed: enabled ? onPermanentDelete : null,
          ),
        ],
      );
    }

    return Wrap(
      spacing: actionGap,
      runSpacing: theme.spacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        AppButton.tertiary(
          leadingIcon: Icons.edit_outlined,
          label: editLabel,
          semanticLabel: editLabel,
          tooltip: editLabel,
          enabled: enabled,
          onPressed: enabled ? onEdit : null,
        ),
        if (canDelete)
          AppButton.tertiary(
            leadingIcon: Icons.delete_outline,
            label: deleteLabel,
            semanticLabel: deleteLabel,
            tooltip: deleteLabel,
            color: colorScheme.error,
            enabled: enabled,
            onPressed: enabled ? onDelete : null,
          ),
      ],
    );
  }
}
