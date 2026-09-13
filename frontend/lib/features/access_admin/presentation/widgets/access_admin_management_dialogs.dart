import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/permissions/access_policy.dart';
import 'package:hosspi_hms/core/permissions/app_permission_catalog_localizations.dart';
import 'package:hosspi_hms/core/permissions/permission_providers.dart';
import 'package:hosspi_hms/core/realtime/realtime_event_groups.dart';
import 'package:hosspi_hms/core/realtime/realtime_message.dart';
import 'package:hosspi_hms/core/security/session_controller.dart';
import 'package:hosspi_hms/features/access_admin/data/repositories/access_admin_repository_impl.dart';
import 'package:hosspi_hms/features/access_admin/domain/entities/access_admin_entities.dart';
import 'package:hosspi_hms/features/access_admin/domain/repositories/access_admin_repository.dart';
import 'package:hosspi_hms/features/access_admin/presentation/access_admin_access.dart';
import 'package:hosspi_hms/features/access_admin/presentation/widgets/access_admin_credential_reset.dart';
import 'package:hosspi_hms/features/access_admin/presentation/widgets/access_admin_dialogs.dart';
import 'package:hosspi_hms/features/access_admin/presentation/widgets/access_admin_workspace_print_helpers.dart';
import 'package:hosspi_hms/features/access_admin/presentation/widgets/access_admin_workspace_table.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/actions/app_action_dialogs.dart';
import 'package:hosspi_hms/shared/components/components.dart';
import 'package:hosspi_hms/shared/data/data.dart';
import 'package:hosspi_hms/shared/layout/layout.dart';
import 'package:hosspi_hms/shared/management/platform_admin_list_config.dart';
import 'package:hosspi_hms/shared/management/platform_management_list_sync.dart';

Future<bool?> showManageUsersDialog(BuildContext context, WidgetRef ref) {
  return showAppDialog<bool>(
    context: context,
    builder: (_) => const ManageUsersPanel(dialogMode: true),
  );
}

/// Whether [user] may be soft-deleted under Access Admin / HR Users CRUD rules.
bool canSoftDeleteAccessAdminUser(
  AccessAdminItem user, {
  required AppAccessPolicy policy,
}) {
  if (user.isDeleted || !canMutateAccessAdminDemoAccount(user)) {
    return false;
  }
  if (!canWriteAccessAdmin(policy)) {
    return false;
  }
  if (policy.canManagePlatformAdmins()) {
    return true;
  }
  return !user.isSystemCritical;
}

/// Confirms and soft-deletes an Access Admin user. Returns `true` when deleted.
Future<bool> confirmSoftDeleteAccessAdminUser(
  BuildContext context, {
  required AccessAdminRepository repository,
  required AccessAdminItem user,
}) async {
  if (!context.mounted) {
    return false;
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
        final Result<void> result = await repository.deleteUser(
          user.mutationId,
        );
        return result.when(
          success: (_) => null,
          failure: (AppFailure failure) => failure,
        );
      },
    ),
  );
  return confirmed == true;
}

Future<bool?> showManageRolesPermissionsDialog(
  BuildContext context,
  WidgetRef ref, {
  AccessAdminPanel panel = AccessAdminPanel.roles,
}) {
  return showAppDialog<bool>(
    context: context,
    builder: (_) => ManageRolesPermissionsPanel(
      dialogMode: true,
      panel: panel,
    ),
  );
}

Future<void> showAccessAdminPermissionDetailDialog(
  BuildContext context, {
  required AccessAdminItem permission,
}) {
  return showAppDialog<void>(
    context: context,
    builder: (_) => _AccessAdminPermissionDetailDialog(permission: permission),
  );
}

abstract class _ScopedAccessAdminListDialogState<
  T extends ConsumerStatefulWidget
>
    extends ConsumerState<T> {
  final TextEditingController searchController = TextEditingController();
  Timer? searchDebounce;
  bool loading = true;
  bool loadingMore = false;
  bool mutating = false;
  bool mutated = false;
  AppFailure? failure;
  AppPageRequest pageRequest = PlatformAdminListConfig.initialPageRequest;
  int totalItemCount = 0;
  List<AccessAdminItem> items = const <AccessAdminItem>[];
  AccessAdminWorkspaceData? workspaceData;
  PlatformManagementListSync? _realtimeSync;

  AccessAdminRepository get repository =>
      ref.read(accessAdminRepositoryProvider);

  AccessAdminWorkspaceQuery get listQuery;

  ValueChanged<int>? get onListTotalChangedCallback => null;

  @override
  void initState() {
    super.initState();
    searchController.addListener(_onSearchChanged);
    unawaited(reload(resetPage: true));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _realtimeSync ??= PlatformManagementListSync(
      ref: ref,
      events: RealtimeEventGroups.platformAdmin,
      onMutated: () => mutated = true,
      reload: ({bool silent = false, RealtimeMessage? message}) async {
        await reload(resetPage: false, silent: silent);
      },
    )..attach();
  }

  @override
  void dispose() {
    _realtimeSync?.dispose();
    searchDebounce?.cancel();
    searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    searchDebounce?.cancel();
    searchDebounce = Timer(const Duration(milliseconds: 450), () {
      // Keep existing rows visible while search refreshes.
      unawaited(reload(resetPage: true, silent: items.isNotEmpty));
    });
  }

  Future<void> reload({
    required bool resetPage,
    bool silent = false,
    bool refreshLookups = false,
  }) async {
    if (resetPage) {
      pageRequest = pageRequest.first();
    }
    if (!silent) {
      setState(() {
        loading = true;
        loadingMore = false;
        failure = null;
      });
    }

    final bool canSkipLookups =
        !refreshLookups &&
        workspaceData != null &&
        (workspaceData!.lookups.tenants.isNotEmpty ||
            workspaceData!.lookups.facilities.isNotEmpty ||
            workspaceData!.lookups.roles.isNotEmpty ||
            workspaceData!.lookups.userStatuses.isNotEmpty);

    final Result<AccessAdminWorkspaceData> result = await repository
        .getWorkspace(
          listQuery.copyWith(
            search: clampAppSearchQuery(searchController.text),
            pageRequest: pageRequest,
            skipLookups: canSkipLookups,
          ),
        );

    if (!mounted) return;
    result.when(
      success: (AccessAdminWorkspaceData data) {
        final AccessAdminLookups preservedLookups =
            canSkipLookups &&
                data.lookups.tenants.isEmpty &&
                data.lookups.facilities.isEmpty &&
                data.lookups.roles.isEmpty
            ? workspaceData!.lookups
            : data.lookups;
        setState(() {
          loading = false;
          loadingMore = false;
          failure = null;
          workspaceData = data.copyWith(lookups: preservedLookups);
          items = data.page.items;
          totalItemCount = data.page.totalItemCount ?? data.page.items.length;
        });
        onListTotalChangedCallback?.call(totalItemCount);
      },
      failure: (AppFailure loadFailure) {
        setState(() {
          loading = false;
          loadingMore = false;
          failure = loadFailure;
          if (!silent) {
            items = const <AccessAdminItem>[];
          }
        });
      },
    );
  }

  Future<void> onPageChanged(AppPageRequest request) async {
    final AppPageRequest previousRequest = pageRequest;
    pageRequest = request;
    final bool silent = items.isNotEmpty;
    if (silent && mounted) {
      setState(() {
        loadingMore = true;
        failure = null;
      });
    }
    await reload(resetPage: false, silent: silent);
    if (!mounted) {
      return;
    }
    if (failure != null && silent) {
      setState(() {
        pageRequest = previousRequest;
        loadingMore = false;
      });
    }
  }

  AccessAdminWorkspaceState? buildWorkspaceState() {
    final AccessAdminWorkspaceData? data = workspaceData;
    if (data == null) {
      return null;
    }
    return AccessAdminWorkspaceState(data: data, query: data.query);
  }

  AppPage<AccessAdminItem> get currentPage => AppPage<AccessAdminItem>(
    items: items,
    request: pageRequest,
    totalItemCount: totalItemCount,
  );

  bool get canWrite => workspaceData?.permissions.canWrite ?? false;

  Widget buildTable({
    required AppLocalizations l10n,
    required ValueChanged<AccessAdminItem>? onRowSelected,
    required List<AppListTableColumn<AccessAdminItem>> columns,
    AppListTableSearch<AccessAdminItem>? search,
    String? columnVisibilityStorageKey,
    List<AppListTableColumn<AccessAdminItem>>? columnChoices,
    Widget? emptyAction,
  }) {
    if (failure != null) {
      return AppFailureStateView(
        failure: failure!,
        onRetry: () => unawaited(reload(resetPage: true)),
      );
    }

    return AppListTable<AccessAdminItem>(
      page: currentPage,
      isLoading: loading || loadingMore,
      onRowSelected: onRowSelected,
      onPageChanged: onPageChanged,
      previousPageLabel: l10n.hrPreviousPageLabel,
      nextPageLabel: l10n.hrNextPageLabel,
      pageLabelBuilder: (AppPage<AccessAdminItem> page) {
        if (loading) {
          return '';
        }
        final int total = page.totalItemCount ?? page.items.length;
        if (total == 0) return l10n.commonTableEmptyLabel;
        final int start = page.pageIndex * page.pageSize + 1;
        final int end = start + page.items.length - 1;
        return '$start-$end / $total';
      },
      columns: columns,
      columnChoices: columnChoices,
      search: search,
      columnVisibilityLabel: l10n.commonTableSettingsActionLabel,
      columnVisibilityTitle: l10n.commonTableSettingsTitle,
      columnVisibilityApplyLabel: l10n.receptionApplyColumnsAction,
      columnVisibilityResetLabel: l10n.receptionResetColumnsAction,
      columnVisibilityCloseLabel: l10n.commonCloseActionLabel,
      columnVisibilityStorageKey: columnVisibilityStorageKey,
      canExport: canExportAccessAdminWorkspace(ref.watch(appAccessPolicyProvider)),
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
      canPrint: canPrintAccessAdminWorkspace(ref.watch(appAccessPolicyProvider)),
      printLabel: l10n.commonPrintActionLabel,
      onPrint: (List<AccessAdminItem> matchingItems) =>
          printAccessAdminListTable<AccessAdminItem>(
        ref: ref,
        context: context,
        title: l10n.accessAdminTitle,
        columns: <AppListTableColumn<AccessAdminItem>>[
          ...columns,
          ...?columnChoices,
        ],
        items: matchingItems,
        emptyText: l10n.accessAdminEmptyTitle,
      ),
      goToTopLabel: l10n.commonGoToTopActionLabel,
      loadingMoreLabel: l10n.commonLoadingMoreLabel,
      allRowsLoadedLabel: l10n.commonAllRowsLoadedLabel,
      exportConfig: AppListTableExportConfig<AccessAdminItem>(
        fileNameStem: 'access_admin_users',
        dateOf: (_) => null,
        sheetName: l10n.accessAdminTitle,
        enableDateFilter: false,
        dateFromLabel: l10n.commonTableExportDateFromLabel,
        dateToLabel: l10n.commonTableExportDateToLabel,
      ),
      emptyBuilder: (_) => AppWorkspaceStatePanel.empty(
        title: l10n.accessAdminEmptyTitle,
        body: l10n.accessAdminEmptyBody,
        action: emptyAction,
      ),
      mobileItemBuilder: (BuildContext context, AccessAdminItem item) {
        final bool isRole = item.resource == AccessAdminResource.roles;
        return AppListTableMobileItem(
          title: item.title,
          caption: item.subtitle ?? item.effectiveDisplayId,
          meta: <AppListTableMobileMeta>[
            if (isRole)
              AppListTableMobileMeta(
                label: item.isFacilityScopedRole
                    ? (item.facilityName?.trim().isNotEmpty == true
                          ? '${context.l10n.accessAdminRoleScopeFacilityBadge} · ${item.facilityName}'
                          : context.l10n.accessAdminRoleScopeFacilityBadge)
                    : item.isPlatformScopedRole
                    ? context.l10n.accessAdminRoleScopePlatformLabel
                    : context.l10n.accessAdminRoleScopeTenantBadge,
                icon: item.isFacilityScopedRole
                    ? Icons.local_hospital_outlined
                    : item.isPlatformScopedRole
                    ? Icons.public_outlined
                    : Icons.domain_outlined,
              )
            else if ((item.status ?? '').isNotEmpty)
              AppListTableMobileMeta(label: item.status!),
          ],
        );
      },
    );
  }

  AppListTableSearch<AccessAdminItem> buildTableSearch({
    required AppLocalizations l10n,
    List<AppSearchBarFilterGroup> filterGroups =
        const <AppSearchBarFilterGroup>[],
    AppSearchBarFilterValue filterValue = AppSearchBarFilterValue.empty,
    ValueChanged<AppSearchBarFilterValue>? onFilterChanged,
    bool hasActiveFilters = false,
    bool showAdvancedFilterButton = false,
    String? advancedFilterTitle,
    List<AppSearchBarAction> trailingActions = const <AppSearchBarAction>[],
  }) {
    return AppListTableSearch<AccessAdminItem>(
      controller: searchController,
      semanticLabel: l10n.accessAdminSearchLabel,
      hintText: l10n.accessAdminSearchHint,
      matcher: (_, _) => true,
      onSubmitted: (_) => unawaited(reload(resetPage: true)),
      onClear: () => unawaited(reload(resetPage: true)),
      enableDateFilter: false,
      showAdvancedFilterButton: showAdvancedFilterButton,
      advancedFilterButtonLabel: l10n.commonFiltersActionLabel,
      advancedFilterTitle: advancedFilterTitle ?? l10n.commonAdvancedFiltersTitle,
      advancedFilterApplyLabel: l10n.opdApplyFiltersAction,
      advancedFilterResetLabel: l10n.opdClearFiltersAction,
      advancedFilterCloseLabel: l10n.commonCloseActionLabel,
      filterGroups: filterGroups,
      filterValue: filterValue,
      hasActiveFilters: hasActiveFilters,
      onFilterChanged: onFilterChanged,
      trailingActions: trailingActions,
    );
  }
}

/// Users table/CRUD shared by manage dialog and setup Users tab.
class ManageUsersPanel extends ConsumerStatefulWidget {
  const ManageUsersPanel({
    this.dialogMode = false,
    this.showCreateAction = true,
    this.reloadListenable,
    this.onMutated,
    this.onOpenDetail,
    this.onListTotalChanged,
    super.key,
  });

  final bool dialogMode;
  final bool showCreateAction;
  final Listenable? reloadListenable;
  final ValueChanged<bool>? onMutated;

  /// When set and returns `true`, skips the Access Admin user-details dialog.
  final Future<bool> Function(AccessAdminItem item)? onOpenDetail;
  final ValueChanged<int>? onListTotalChanged;

  @override
  ConsumerState<ManageUsersPanel> createState() => _ManageUsersPanelState();
}

class _ManageUsersPanelState
    extends _ScopedAccessAdminListDialogState<ManageUsersPanel> {
  @override
  ValueChanged<int>? get onListTotalChangedCallback =>
      widget.onListTotalChanged;

  String? tenantFilter;
  String? facilityFilter;
  String? roleFilter;
  String? statusFilter;

  /// Defaults to the widest list the actor is allowed to see.
  /// Platform admin: all tenants + facilities. Tenant admin: all facilities.
  /// Facility-scoped actors keep their facility from session scope.
  bool allTenants = true;
  bool allFacilities = true;

  static const String _tenantFilterKey = 'tenant';
  static const String _facilityFilterKey = 'facility';
  static const String _roleFilterKey = 'role';
  static const String _statusFilterKey = 'status';

  bool get _canManageProtectedUsers =>
      ref.read(appAccessPolicyProvider).canManagePlatformAdmins();

  bool _canMutateUser(AccessAdminItem user) {
    if (user.isDeleted) {
      return false;
    }
    return canMutateAccessAdminDemoAccount(user);
  }

  bool _canDeleteUser(AccessAdminItem user) {
    return canSoftDeleteAccessAdminUser(
      user,
      policy: ref.read(appAccessPolicyProvider),
    );
  }

  @override
  void initState() {
    super.initState();
    widget.reloadListenable?.addListener(_onExternalReload);
  }

  @override
  void dispose() {
    widget.reloadListenable?.removeListener(_onExternalReload);
    super.dispose();
  }

  void _onExternalReload() {
    unawaited(reload(resetPage: false, silent: true));
  }

  bool get _canPickTenant {
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    return policy.canCreateTenant();
  }

  bool get _canFilterAcrossFacilities {
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    return policy.canCreateTenant() || policy.canCreateTenantWideRole();
  }

  @override
  AccessAdminWorkspaceQuery get listQuery {
    final bool crossTenant =
        _canPickTenant && allTenants && tenantFilter == null;
    final bool tenantWide =
        _canFilterAcrossFacilities && allFacilities && facilityFilter == null;
    return AccessAdminWorkspaceQuery(
      includeDeleted: true,
      lean: true,
      tenantId: crossTenant ? null : tenantFilter,
      facilityId: tenantWide ? null : facilityFilter,
      allTenants: crossTenant,
      allFacilities: tenantWide || crossTenant,
      roleId: roleFilter,
      status: statusFilter,
    );
  }

  Future<void> _applyUserFilters(AppSearchBarFilterValue value) async {
    final String? nextTenant = value.option(_tenantFilterKey);
    final String? nextFacilityRaw = value.option(_facilityFilterKey);
    final String? nextRole = value.option(_roleFilterKey);
    final String? nextStatus = value.option(_statusFilterKey);

    final bool nextAllTenants = _canPickTenant && nextTenant == null;
    final bool nextAllFacilities = nextAllTenants
        ? true
        : (_canFilterAcrossFacilities && nextFacilityRaw == null);
    final String? nextFacility = nextAllFacilities || nextAllTenants
        ? null
        : nextFacilityRaw;

    if (tenantFilter == nextTenant &&
        facilityFilter == nextFacility &&
        allTenants == nextAllTenants &&
        allFacilities == nextAllFacilities &&
        roleFilter == nextRole &&
        statusFilter == nextStatus) {
      return;
    }

    final bool tenantScopeChanged =
        tenantFilter != nextTenant || allTenants != nextAllTenants;

    setState(() {
      tenantFilter = nextTenant;
      facilityFilter = nextFacility;
      allTenants = nextAllTenants;
      allFacilities = nextAllFacilities;
      roleFilter = nextRole;
      statusFilter = nextStatus;
    });
    await reload(
      resetPage: true,
      silent: items.isNotEmpty,
      refreshLookups: tenantScopeChanged,
    );
  }

  Future<void> _openCreateUserDialog() async {
    final AccessAdminWorkspaceState? state = buildWorkspaceState();
    if (state == null || !mounted) {
      return;
    }
    final AccessAdminItem? createdOrExisting =
        await openAccessAdminCreateUserDialog(
      context,
      ref,
      state,
    );
    if (createdOrExisting != null && mounted) {
      mutated = true;
      // Restore widest allowed defaults so the new user is not hidden.
      setState(() {
        if (_canPickTenant) {
          allTenants = true;
          tenantFilter = null;
        }
        if (_canFilterAcrossFacilities) {
          allFacilities = true;
          facilityFilter = null;
        }
        roleFilter = null;
        statusFilter = null;
      });
      // Open details immediately so the users list never flashes between create
      // and detail. List reload runs silently in the background.
      unawaited(reload(resetPage: true, silent: true));
      await _openUserDetail(createdOrExisting, coverListImmediately: true);
      // createUserReviewed already schedules a deferred session rehydrate.
    }
  }

  Future<void> _openEditUserDialog(
    AccessAdminItem item, {
    AccessAdminUserDetail? detail,
  }) async {
    if (!_canMutateUser(item)) {
      return;
    }
    final AccessAdminWorkspaceState? state = buildWorkspaceState();
    if (state == null || !mounted) {
      return;
    }

    AccessAdminUserDetail? resolvedDetail = detail;
    if (resolvedDetail == null) {
      final Result<AccessAdminUserDetail> detailResult = await repository
          .getUserDetail(
            item.mutationId,
            tenantId: item.tenantId ?? workspaceData?.query.tenantId,
          );
      if (!mounted) return;
      resolvedDetail = detailResult.when(
        success: (AccessAdminUserDetail value) => value,
        failure: (_) => null,
      );
      if (resolvedDetail == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              detailResult.when(
                success: (_) => context.l10n.accessAdminEmptyTitle,
                failure: (AppFailure loadFailure) =>
                    context.l10n.failureMessage(loadFailure),
              ),
            ),
          ),
        );
        return;
      }
    }

    if (!mounted) return;
    final AccessAdminItem? updatedOrExisting =
        await openAccessAdminEditUserDialog(
      context,
      ref,
      state,
      user: resolvedDetail.item,
      detail: resolvedDetail,
    );
    if (updatedOrExisting != null && mounted) {
      mutated = true;
      // Mirror create: open details immediately; refresh list in the background.
      unawaited(reload(resetPage: true, silent: true));
      await _openUserDetail(updatedOrExisting, coverListImmediately: true);
      // updateUserReviewed already schedules a deferred session rehydrate.
    }
  }

  Future<void> _confirmDeleteUser(AccessAdminItem user) async {
    if (!_canDeleteUser(user)) {
      return;
    }
    final bool deleted = await confirmSoftDeleteAccessAdminUser(
      context,
      repository: repository,
      user: user,
    );
    if (deleted && mounted) {
      mutated = true;
      setState(() {
        items = <AccessAdminItem>[
          for (final AccessAdminItem entry in items)
            entry.id == user.id || entry.mutationId == user.mutationId
                ? entry.copyWith(deletedAt: DateTime.now().toUtc())
                : entry,
        ];
      });
      unawaited(reload(resetPage: false, silent: true));
    }
  }

  Future<void> _confirmRestoreUser(AccessAdminItem user) async {
    if (!user.isDeleted || !canMutateAccessAdminDemoAccount(user)) {
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
          final Result<void> result = await repository.restoreUser(
            user.mutationId,
          );
          return result.when(
            success: (_) => null,
            failure: (AppFailure failure) => failure,
          );
        },
      ),
    );
    if (confirmed == true && mounted) {
      mutated = true;
      setState(() {
        items = <AccessAdminItem>[
          for (final AccessAdminItem entry in items)
            entry.id == user.id || entry.mutationId == user.mutationId
                ? entry.copyWith(clearDeletedAt: true)
                : entry,
        ];
      });
      unawaited(reload(resetPage: false, silent: true));
    }
  }

  bool _canPermanentlyDeleteUser(AccessAdminItem user) {
    return canWrite &&
        user.isDeleted &&
        canMutateAccessAdminDemoAccount(user) &&
        (_canManageProtectedUsers || !user.isSystemCritical);
  }

  Future<void> _confirmPermanentDeleteUser(AccessAdminItem user) async {
    if (!_canPermanentlyDeleteUser(user)) {
      return;
    }
    final AppLocalizations l10n = context.l10n;
    final String confirmName = user.title.trim();
    final String? typed = await showAppDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AppTextInputActionDialog(
        title: l10n.tenantFacilityPermanentDeleteConfirmationTitle,
        description: l10n.accessAdminPermanentDeleteUserWarningBody(
          confirmName,
        ),
        fieldLabel: l10n.tenantFacilityPermanentDeleteConfirmFieldLabel(
          confirmName,
        ),
        submitLabel: l10n.tenantFacilityPermanentDeleteConfirmAction,
        cancelLabel: l10n.commonCancelActionLabel,
        requiredMessage: l10n.validationRequired,
        confirmExactValue: confirmName,
        confirmMismatchMessage:
            l10n.tenantFacilityPermanentDeleteConfirmFieldLabel(confirmName),
        destructive: true,
        minLines: 1,
        maxLines: 1,
        icon: const Icon(Icons.delete_forever_outlined),
      ),
    );
    if (!mounted || typed == null) {
      return;
    }
    // Dialog already validates the typed name; keep a hard guard.
    if (typed.trim().toLowerCase() != confirmName.toLowerCase()) {
      return;
    }

    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AppConfirmActionDialog(
        title: l10n.tenantFacilityPermanentDeleteConfirmationTitle,
        body: l10n.accessAdminPermanentDeleteUserConfirmationBody(confirmName),
        highlightedText: confirmName,
        submitLabel: l10n.tenantFacilityPermanentDeleteConfirmAction,
        destructive: true,
        icon: const Icon(Icons.delete_forever_outlined),
        onConfirm: () async {
          final Result<void> result = await repository.permanentDeleteUser(
            user.mutationId,
          );
          return result.when(
            success: (_) => null,
            // Already purged elsewhere: treat as done so the stale row drops.
            failure: (AppFailure failure) =>
                failure.category == AppFailureCategory.notFound
                ? null
                : failure,
          );
        },
      ),
    );
    if (confirmed == true && mounted) {
      mutated = true;
      setState(() {
        items = <AccessAdminItem>[
          for (final AccessAdminItem entry in items)
            if (entry.id != user.id && entry.mutationId != user.mutationId)
              entry,
        ];
      });
      unawaited(reload(resetPage: false, silent: true));
    }
  }

  Future<void> _openUserDetail(
    AccessAdminItem item, {
    bool coverListImmediately = false,
  }) async {
    if (!mounted) {
      return;
    }

    final Future<bool> Function(AccessAdminItem item)? customOpen =
        widget.onOpenDetail;
    if (customOpen != null) {
      final bool handled = await customOpen(item);
      if (handled) {
        if (mounted) {
          // Keep the directory list fresh after Staff Details mutations
          // (for example soft-delete from the detail footer).
          unawaited(reload(resetPage: false, silent: true));
        }
        return;
      }
      if (!mounted) {
        return;
      }
    }

    var coverOpen = false;
    if (coverListImmediately) {
      final Completer<void> coverReady = Completer<void>();
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          useRootNavigator: true,
          builder: (BuildContext dialogContext) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!coverReady.isCompleted) {
                coverReady.complete();
              }
            });
            final ThemeData theme = Theme.of(dialogContext);
            return PopScope(
              canPop: false,
              child: Center(
                child: Material(
                  color: theme.colorScheme.surface,
                  elevation: 2,
                  borderRadius: BorderRadius.circular(theme.radius.md),
                  child: Padding(
                    padding: EdgeInsets.all(theme.spacing.lg),
                    child: const AppLoadingIndicator.compact(expand: false),
                  ),
                ),
              ),
            );
          },
        ),
      );
      await coverReady.future;
      coverOpen = true;
    }

    // Do not flip the table into a global busy state — keep rows interactive.
    final Result<AccessAdminUserDetail> detailResult = await repository
        .getUserDetail(
          item.mutationId,
          tenantId: item.tenantId ?? workspaceData?.query.tenantId,
        );

    if (coverOpen && mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      coverOpen = false;
    }
    if (!mounted) return;

    final AccessAdminUserDetail? detail = detailResult.when(
      success: (AccessAdminUserDetail value) => value,
      failure: (_) => null,
    );
    if (detail == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            detailResult.when(
              success: (_) => context.l10n.accessAdminEmptyTitle,
              failure: (AppFailure loadFailure) =>
                  context.l10n.failureMessage(loadFailure),
            ),
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    var detailDidMutate = false;
    await showAppDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => _AccessAdminUserDetailDialog(
        item: detail.item,
        detail: detail,
        canWrite: canWrite,
        canDeleteProtected: _canManageProtectedUsers,
        repository: repository,
        lookups: workspaceData?.lookups ?? const AccessAdminLookups(),
        tenantId: detail.item.tenantId ?? item.tenantId,
        facilityId: detail.item.facilityId ?? item.facilityId,
        onStatusChanged: (String status) async {
          final Result<void> result = await repository.setUserStatus(
            item.mutationId,
            status,
          );
          return result.when(
            success: (_) => null,
            failure: (AppFailure failure) => failure,
          );
        },
        onEdit: () {
          Navigator.of(dialogContext).pop();
          unawaited(_openEditUserDialog(detail.item, detail: detail));
        },
        onDelete: () {
          Navigator.of(dialogContext).pop();
          unawaited(_confirmDeleteUser(detail.item));
        },
        onMutated: () {
          mutated = true;
          detailDidMutate = true;
        },
      ),
    );
    if (mounted && detailDidMutate) {
      await reload(resetPage: false, silent: true);
      // Role/permission mutations on the detail dialog already schedule rehydrate.
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final AccessAdminLookups lookups =
        workspaceData?.lookups ?? const AccessAdminLookups();
    final bool canPickTenant = ref
        .watch(appAccessPolicyProvider)
        .canCreateTenant();
    final bool canFilterFacilities = _canFilterAcrossFacilities;
    final bool showFacilityFilter =
        canFilterFacilities && (!canPickTenant || tenantFilter != null);
    final List<String> statusOptions = lookups.userStatuses.isNotEmpty
        ? lookups.userStatuses
        : const <String>['ACTIVE', 'INACTIVE', 'SUSPENDED', 'PENDING'];

    final List<AppSearchBarFilterGroup> filterGroups =
        <AppSearchBarFilterGroup>[
          if (canPickTenant)
            AppSearchBarFilterGroup(
              key: _tenantFilterKey,
              label: l10n.settingsWorkspaceTenantLabel,
              allLabel: l10n.accessAdminAllTenantsFilterLabel,
              choices: lookups.tenants
                  .map(
                    (AccessAdminLookupOption tenant) =>
                        AppSearchBarFilterChoice(
                          value: tenant.id,
                          label: tenant.label,
                          icon: Icons.apartment_outlined,
                        ),
                  )
                  .toList(growable: false),
            ),
          if (showFacilityFilter)
            AppSearchBarFilterGroup(
              key: _facilityFilterKey,
              label: l10n.settingsWorkspaceFacilityLabel,
              allLabel: l10n.accessAdminAllFacilitiesFilterLabel,
              choices: lookups.facilities
                  .map(
                    (AccessAdminLookupOption facility) =>
                        AppSearchBarFilterChoice(
                          value: facility.id,
                          label: facility.label,
                          icon: Icons.local_hospital_outlined,
                        ),
                  )
                  .toList(growable: false),
            ),
          AppSearchBarFilterGroup(
            key: _roleFilterKey,
            label: l10n.accessAdminFilterRoleLabel,
            allLabel: l10n.accessAdminAllRolesFilterLabel,
            choices: lookups.roles
                .map(
                  (AccessAdminLookupOption role) => AppSearchBarFilterChoice(
                    value: role.id,
                    label: role.label,
                    icon: Icons.badge_outlined,
                  ),
                )
                .toList(growable: false),
          ),
          AppSearchBarFilterGroup(
            key: _statusFilterKey,
            label: l10n.accessAdminStatusLabel,
            allLabel: l10n.accessAdminAllStatusesLabel,
            choices: statusOptions
                .map(
                  (String status) => AppSearchBarFilterChoice(
                    value: status,
                    label: status,
                    icon: Icons.flag_outlined,
                  ),
                )
                .toList(growable: false),
          ),
        ];

    final Map<String, String> filterOptions = <String, String>{
      if (tenantFilter != null) _tenantFilterKey: tenantFilter!,
      if (showFacilityFilter && !allFacilities && facilityFilter != null)
        _facilityFilterKey: facilityFilter!,
      if (roleFilter != null) _roleFilterKey: roleFilter!,
      if (statusFilter != null) _statusFilterKey: statusFilter!,
    };

    final bool hasActiveFilters =
        tenantFilter != null ||
        (showFacilityFilter && !allFacilities && facilityFilter != null) ||
        roleFilter != null ||
        statusFilter != null;

    final Widget table = SizedBox.expand(
      child: buildTable(
          l10n: l10n,
          columnVisibilityStorageKey: 'access_admin_manage_users_v4',
          onRowSelected: (AccessAdminItem item) =>
              unawaited(_openUserDetail(item)),
          emptyAction: widget.showCreateAction && canWrite
              ? AppButton.primary(
                  label: l10n.accessAdminCreateUserAction,
                  leadingIcon: Icons.person_add_alt_1_outlined,
                  enabled: !loading && !mutating,
                  onPressed: loading || mutating
                      ? null
                      : () => unawaited(_openCreateUserDialog()),
                )
              : null,
          search: buildTableSearch(
            l10n: l10n,
            showAdvancedFilterButton: true,
            advancedFilterTitle: l10n.commonAdvancedFiltersTitle,
            filterGroups: filterGroups,
            filterValue: filterOptions.isEmpty
                ? AppSearchBarFilterValue.empty
                : AppSearchBarFilterValue(options: filterOptions),
            hasActiveFilters: hasActiveFilters,
            onFilterChanged: (AppSearchBarFilterValue value) {
              unawaited(_applyUserFilters(value));
            },
            trailingActions: widget.showCreateAction && canWrite
                ? <AppSearchBarAction>[
                    AppSearchBarAction(
                      icon: Icons.person_add_alt_1_outlined,
                      label: l10n.accessAdminCreateUserAction,
                      tooltip: l10n.accessAdminCreateUserAction,
                      onPressed: loading || mutating
                          ? null
                          : () => unawaited(_openCreateUserDialog()),
                    ),
                  ]
                : const <AppSearchBarAction>[],
          ),
          columns: <AppListTableColumn<AccessAdminItem>>[
            AppListTableColumn<AccessAdminItem>(
              id: 'name',
              label: l10n.accessAdminColumnName,
              sortComparator: (AccessAdminItem left, AccessAdminItem right) =>
                  appListTableCompareText(left.title, right.title),
              exportValue: (AccessAdminItem item) => item.title,
              cellBuilder: (_, AccessAdminItem item) => Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            AppListTableColumn<AccessAdminItem>(
              id: 'roles',
              label: l10n.accessAdminColumnRoles,
              sortComparator: (AccessAdminItem left, AccessAdminItem right) =>
                  appListTableCompareText(
                    left.roles
                        .map((AccessAdminRoleRef role) => role.name)
                        .join(', '),
                    right.roles
                        .map((AccessAdminRoleRef role) => role.name)
                        .join(', '),
                  ),
              exportValue: (AccessAdminItem item) => item.roles
                  .map((AccessAdminRoleRef role) => role.name)
                  .join(', '),
              cellBuilder: (_, AccessAdminItem item) {
                if (item.roles.isEmpty) {
                  return const Text('—');
                }
                return Text(
                  item.roles
                      .map((AccessAdminRoleRef role) => role.name)
                      .join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                );
              },
            ),
            AppListTableColumn<AccessAdminItem>(
              id: 'status',
              label: l10n.accessAdminColumnStatus,
              sortComparator: (AccessAdminItem left, AccessAdminItem right) {
                final String leftStatus = left.isDeleted
                    ? l10n.tenantFacilityStructureDeletedStatus
                    : (left.status ?? '—');
                final String rightStatus = right.isDeleted
                    ? l10n.tenantFacilityStructureDeletedStatus
                    : (right.status ?? '—');
                return appListTableCompareText(leftStatus, rightStatus);
              },
              exportValue: (AccessAdminItem item) => item.isDeleted
                  ? l10n.tenantFacilityStructureDeletedStatus
                  : (item.status ?? '—'),
              cellBuilder: (_, AccessAdminItem item) => Text(
                item.isDeleted
                    ? l10n.tenantFacilityStructureDeletedStatus
                    : (item.status ?? '—'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (canWrite)
              AppListTableColumn<AccessAdminItem>(
                id: 'actions',
                label: l10n.accessAdminColumnActions,
                alwaysVisible: true,
                exportable: false,
                cellBuilder: (BuildContext context, AccessAdminItem user) {
                  final ThemeData theme = Theme.of(context);
                  final double actionGap = theme.spacing.md;
                  final bool actionsEnabled = !loading && !mutating;
                  if (user.isDeleted) {
                    if (!canMutateAccessAdminDemoAccount(user)) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: EdgeInsetsDirectional.only(
                        end: theme.spacing.sm,
                      ),
                      child: Wrap(
                        spacing: actionGap,
                        runSpacing: theme.spacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          AppButton.tertiary(
                            leadingIcon: Icons.restore_outlined,
                            label: l10n.accessAdminRestoreUserAction,
                            semanticLabel: l10n.accessAdminRestoreUserAction,
                            tooltip: l10n.accessAdminRestoreUserAction,
                            enabled: actionsEnabled,
                            onPressed: actionsEnabled
                                ? () => unawaited(_confirmRestoreUser(user))
                                : null,
                          ),
                          if (_canPermanentlyDeleteUser(user))
                            AppButton.tertiary(
                              leadingIcon: Icons.delete_forever_outlined,
                              label: l10n.tenantFacilityPermanentDeleteAction,
                              semanticLabel:
                                  l10n.tenantFacilityPermanentDeleteAction,
                              tooltip: l10n.tenantFacilityPermanentDeleteAction,
                              color: colorScheme.error,
                              enabled: actionsEnabled,
                              onPressed: actionsEnabled
                                  ? () => unawaited(
                                        _confirmPermanentDeleteUser(user),
                                      )
                                  : null,
                            ),
                        ],
                      ),
                    );
                  }
                  return Padding(
                    padding: EdgeInsetsDirectional.only(end: theme.spacing.sm),
                    child: Wrap(
                      spacing: actionGap,
                      runSpacing: theme.spacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        if (_canMutateUser(user))
                          AppButton.tertiary(
                            leadingIcon: Icons.edit_outlined,
                            label: l10n.tenantFacilityEditAction,
                            semanticLabel: l10n.tenantFacilityEditAction,
                            tooltip: l10n.tenantFacilityEditAction,
                            enabled: actionsEnabled,
                            onPressed: actionsEnabled
                                ? () => unawaited(_openEditUserDialog(user))
                                : null,
                          ),
                        if (_canDeleteUser(user))
                          AppButton.tertiary(
                            leadingIcon: Icons.delete_outline,
                            label: l10n.tenantFacilityDeleteAction,
                            semanticLabel: l10n.tenantFacilityDeleteAction,
                            tooltip: l10n.tenantFacilityDeleteAction,
                            color: colorScheme.error,
                            enabled: actionsEnabled,
                            onPressed: actionsEnabled
                                ? () => unawaited(_confirmDeleteUser(user))
                                : null,
                          ),
                      ],
                    ),
                  );
                },
              ),
          ],
          columnChoices: <AppListTableColumn<AccessAdminItem>>[
            AppListTableColumn<AccessAdminItem>(
              id: 'id',
              label: l10n.accessAdminColumnId,
              sortComparator: (AccessAdminItem left, AccessAdminItem right) =>
                  appListTableCompareText(
                    left.effectiveDisplayId,
                    right.effectiveDisplayId,
                  ),
              exportValue: (AccessAdminItem item) => item.effectiveDisplayId,
              cellBuilder: (_, AccessAdminItem item) => Text(
                item.effectiveDisplayId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            AppListTableColumn<AccessAdminItem>(
              id: 'facility',
              label: l10n.accessAdminColumnFacility,
              sortComparator: (AccessAdminItem left, AccessAdminItem right) =>
                  appListTableCompareText(
                    left.facilityName?.trim().isNotEmpty == true
                        ? left.facilityName!
                        : (left.facilityId ?? '—'),
                    right.facilityName?.trim().isNotEmpty == true
                        ? right.facilityName!
                        : (right.facilityId ?? '—'),
                  ),
              exportValue: (AccessAdminItem item) =>
                  item.facilityName?.trim().isNotEmpty == true
                  ? item.facilityName!
                  : (item.facilityId ?? '—'),
              cellBuilder: (_, AccessAdminItem item) => Text(
                item.facilityName?.trim().isNotEmpty == true
                    ? item.facilityName!
                    : (item.facilityId ?? '—'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            AppListTableColumn<AccessAdminItem>(
              id: 'details',
              label: l10n.accessAdminColumnDetails,
              sortComparator: (AccessAdminItem left, AccessAdminItem right) =>
                  appListTableCompareText(
                    left.subtitle ?? left.email ?? '—',
                    right.subtitle ?? right.email ?? '—',
                  ),
              exportValue: (AccessAdminItem item) =>
                  item.subtitle ?? item.email ?? '—',
              cellBuilder: (_, AccessAdminItem item) => Text(
                item.subtitle ?? item.email ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
    );

    final Widget createAction = AppButton.primary(
      label: l10n.accessAdminCreateUserAction,
      leadingIcon: Icons.person_add_alt_1_outlined,
      onPressed: loading || mutating
          ? null
          : () => unawaited(_openCreateUserDialog()),
    );

    if (!widget.dialogMode) {
      return table;
    }

    return AppDialog(
      title: Text(l10n.homeManageUsersTitle),
      icon: const Icon(Icons.people_outline),
      pinActionsToBottom: true,
      maxWidth: 1200,
      content: table,
      actions: <Widget>[
        if (widget.showCreateAction && canWrite) createAction,
        AppButton.secondary(
          label: l10n.commonCloseActionLabel,
          leadingIcon: Icons.close,
          onPressed: () => Navigator.of(context).pop(mutated ? true : null),
        ),
      ],
    );
  }
}

bool _isSameAccessAdminRole(AccessAdminItem left, AccessAdminItem right) {
  final Set<String> leftKeys = _roleLifecycleKeys(left);
  final Set<String> rightKeys = _roleLifecycleKeys(right);
  if (leftKeys.isNotEmpty && rightKeys.isNotEmpty) {
    return leftKeys.any(rightKeys.contains);
  }
  // Fall back only when UUIDs are unavailable — never match on display id alone
  // (duplicate human_friendly_id across scopes is possible).
  return left.id == right.id &&
      left.roleScope == right.roleScope &&
      left.facilityId == right.facilityId &&
      left.tenantId == right.tenantId;
}

/// All known identifiers for a role so purge/soft-delete pending state survives
/// friendly-id vs resource_uuid mismatches across reloads.
Set<String> _roleLifecycleKeys(AccessAdminItem role) {
  return <String?>{
    role.resourceUuid,
    role.mutationId,
    role.id,
    role.displayId,
    role.effectiveDisplayId,
  }
      .whereType<String>()
      .map((String value) => value.trim())
      .where((String value) => value.isNotEmpty)
      .toSet();
}

String _roleLifecycleKey(AccessAdminItem role) {
  final Set<String> keys = _roleLifecycleKeys(role);
  if (keys.isEmpty) {
    return <String>[
      role.id,
      role.roleScope ?? '',
      role.facilityId ?? '',
      role.tenantId ?? '',
    ].join('|');
  }
  // Prefer raw UUID when present so purge keys align with mutation APIs.
  for (final String key in keys) {
    if (RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(key)) {
      return key;
    }
  }
  return keys.first;
}

/// Keep soft-delete / purge visible when a silent refresh is briefly stale or
/// omits soft-deleted rows (include_deleted races).
List<AccessAdminItem> _mergeRoleLifecycleItems({
  required List<AccessAdminItem> serverItems,
  required Map<String, AccessAdminItem> pendingSoftDeleted,
  required Set<String> pendingPurgedKeys,
}) {
  final Map<String, AccessAdminItem> merged = <String, AccessAdminItem>{};
  for (final AccessAdminItem item in serverItems) {
    final Set<String> itemKeys = _roleLifecycleKeys(item);
    if (itemKeys.any(pendingPurgedKeys.contains)) {
      continue;
    }
    final String key = _roleLifecycleKey(item);
    AccessAdminItem? pending;
    for (final String itemKey in itemKeys) {
      pending = pendingSoftDeleted[itemKey];
      if (pending != null) {
        break;
      }
    }
    if (pending != null) {
      if (item.isDeleted) {
        for (final String itemKey in itemKeys) {
          pendingSoftDeleted.remove(itemKey);
        }
        merged[key] = item;
      } else {
        merged[key] = item.copyWith(deletedAt: pending.deletedAt);
      }
      continue;
    }
    merged[key] = item;
  }

  for (final MapEntry<String, AccessAdminItem> entry
      in pendingSoftDeleted.entries) {
    if (pendingPurgedKeys.contains(entry.key) ||
        _roleLifecycleKeys(entry.value).any(pendingPurgedKeys.contains)) {
      continue;
    }
    merged.putIfAbsent(_roleLifecycleKey(entry.value), () => entry.value);
  }

  for (final String key in pendingPurgedKeys.toList(growable: false)) {
    final bool stillOnServer = serverItems.any(
      (AccessAdminItem item) => _roleLifecycleKeys(item).contains(key),
    );
    if (!stillOnServer) {
      pendingPurgedKeys.remove(key);
    }
  }

  return merged.values.toList(growable: false);
}

bool _rolePermanentDeleteNameMatches(
  AccessAdminItem role,
  String typed, {
  required AppLocalizations l10n,
}) {
  final String needle = _normalizeRoleConfirmName(typed);
  if (needle.isEmpty) {
    return false;
  }
  final String title = role.title.trim();
  final String displayName = (role.displayName ?? '').trim();
  final String name = (role.name ?? '').trim();
  final String deletedStatus = l10n.tenantFacilityStructureDeletedStatus;
  final List<String> accepted = <String>[
    title,
    displayName,
    name,
    '$title · $deletedStatus',
    '$title - $deletedStatus',
    if (displayName.isNotEmpty) ...<String>[
      '$displayName · $deletedStatus',
      '$displayName - $deletedStatus',
    ],
  ];
  return accepted.any(
    (String value) => _normalizeRoleConfirmName(value) == needle,
  );
}

String _normalizeRoleConfirmName(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\u00b7\u2022\u2219]'), '-')
      .replaceAll(RegExp(r'\s+'), ' ');
}

/// Roles/permissions table/CRUD shared by manage dialog and setup tabs.
class ManageRolesPermissionsPanel extends ConsumerStatefulWidget {
  const ManageRolesPermissionsPanel({
    this.dialogMode = false,
    this.showCreateAction = true,
    this.reloadListenable,
    this.panel = AccessAdminPanel.roles,
    this.onMutated,
    this.onListTotalChanged,
    super.key,
  });

  final bool dialogMode;
  final bool showCreateAction;
  final Listenable? reloadListenable;
  final AccessAdminPanel panel;
  final ValueChanged<bool>? onMutated;
  final ValueChanged<int>? onListTotalChanged;

  @override
  ConsumerState<ManageRolesPermissionsPanel> createState() =>
      _ManageRolesPermissionsPanelState();
}

class _ManageRolesPermissionsPanelState
    extends _ScopedAccessAdminListDialogState<ManageRolesPermissionsPanel> {
  @override
  ValueChanged<int>? get onListTotalChangedCallback =>
      widget.onListTotalChanged;

  String? roleScopeFilter;
  String? tenantFilter;
  String? facilityFilter;

  /// Mutation id / resource uuid of the role currently being soft-deleted,
  /// restored, or permanently deleted.
  String? _roleActionBusyKey;

  /// Local soft-delete snapshots retained across silent reloads.
  final Map<String, AccessAdminItem> _pendingSoftDeletedRoles =
      <String, AccessAdminItem>{};

  /// Permanently deleted keys suppressed until the server omits them.
  final Set<String> _pendingPurgedRoleKeys = <String>{};

  /// Match Manage Users: widest list the actor is allowed to see.
  bool allTenants = true;
  bool allFacilities = true;

  static const String _tenantFilterKey = 'tenant';
  static const String _facilityFilterKey = 'facility';

  bool _isRoleActionBusy(AccessAdminItem role) {
    final String? busyKey = _roleActionBusyKey;
    if (busyKey == null || busyKey.isEmpty) {
      return false;
    }
    return role.mutationId == busyKey ||
        (role.resourceUuid != null && role.resourceUuid == busyKey);
  }

  void _setRoleActionBusy(AccessAdminItem role, {required bool busy}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _roleActionBusyKey = busy ? role.mutationId : null;
      mutating = busy;
    });
  }

  void _markRoleSoftDeletedLocally(AccessAdminItem role) {
    final AccessAdminItem softDeleted = role.isDeleted
        ? role
        : role.copyWith(deletedAt: DateTime.now().toUtc());
    final Set<String> keys = _roleLifecycleKeys(softDeleted);
    for (final String key in keys) {
      _pendingSoftDeletedRoles[key] = softDeleted;
      _pendingPurgedRoleKeys.remove(key);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      final bool existed = items.any(
        (AccessAdminItem entry) => _isSameAccessAdminRole(entry, softDeleted),
      );
      items = <AccessAdminItem>[
        for (final AccessAdminItem entry in items)
          _isSameAccessAdminRole(entry, softDeleted)
              ? entry.copyWith(deletedAt: softDeleted.deletedAt)
              : entry,
        if (!existed) softDeleted,
      ];
      _roleActionBusyKey = null;
      mutating = false;
    });
  }

  void _markRoleRestoredLocally(AccessAdminItem role) {
    for (final String key in _roleLifecycleKeys(role)) {
      _pendingSoftDeletedRoles.remove(key);
      _pendingPurgedRoleKeys.remove(key);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      items = <AccessAdminItem>[
        for (final AccessAdminItem entry in items)
          _isSameAccessAdminRole(entry, role)
              ? entry.copyWith(clearDeletedAt: true)
              : entry,
      ];
      _roleActionBusyKey = null;
      mutating = false;
    });
  }

  void _markRolePurgedLocally(AccessAdminItem role) {
    for (final String key in _roleLifecycleKeys(role)) {
      _pendingSoftDeletedRoles.remove(key);
      _pendingPurgedRoleKeys.add(key);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      final int before = items.length;
      items = items
          .where(
            (AccessAdminItem entry) => !_isSameAccessAdminRole(entry, role),
          )
          .toList(growable: false);
      if (items.length < before) {
        totalItemCount = math.max(0, totalItemCount - (before - items.length));
      }
      _roleActionBusyKey = null;
      mutating = false;
    });
  }

  void _applyPendingRoleLifecycleToItems() {
    if (!mounted) {
      return;
    }
    final List<AccessAdminItem> merged = _mergeRoleLifecycleItems(
      serverItems: items,
      pendingSoftDeleted: _pendingSoftDeletedRoles,
      pendingPurgedKeys: _pendingPurgedRoleKeys,
    );
    setState(() {
      totalItemCount = math.max(totalItemCount, merged.length);
      items = merged;
    });
  }

  @override
  Future<void> reload({
    required bool resetPage,
    bool silent = false,
    bool refreshLookups = false,
  }) async {
    await super.reload(
      resetPage: resetPage,
      silent: silent,
      refreshLookups: refreshLookups,
    );
    if (!mounted) {
      return;
    }
    // Keep soft-delete / purge visible locally if the refresh is briefly stale.
    _applyPendingRoleLifecycleToItems();
  }

  Future<void> _syncRoleListAfterLifecycle({bool resetPage = false}) async {
    await reload(resetPage: resetPage, silent: true);
    widget.onMutated?.call(true);
  }

  Future<AppFailure?> _runRoleLifecycleMutation(
    AccessAdminItem role,
    Future<Result<void>> Function() mutate,
  ) async {
    _setRoleActionBusy(role, busy: true);
    final Result<void> result = await mutate();
    return result.when(
      success: (_) => null,
      failure: (AppFailure failure) {
        _setRoleActionBusy(role, busy: false);
        return failure;
      },
    );
  }

  @override
  void initState() {
    // Platform admins otherwise default to every tenant's catalog copy of the
    // same system roles (shared ROL####### sequences look like duplicates).
    if (_canPickTenant) {
      final String? sessionTenantId = ref
          .read(sessionStateProvider)
          .session
          ?.user
          ?.tenantId
          ?.trim();
      if (sessionTenantId != null && sessionTenantId.isNotEmpty) {
        tenantFilter = sessionTenantId;
        allTenants = false;
      }
    }
    super.initState();
    widget.reloadListenable?.addListener(_onExternalReload);
  }

  @override
  void dispose() {
    widget.reloadListenable?.removeListener(_onExternalReload);
    super.dispose();
  }

  void _onExternalReload() {
    unawaited(reload(resetPage: false, silent: true));
  }

  bool get _canPickTenant {
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    return policy.canCreateTenant();
  }

  bool get _canFilterAcrossFacilities {
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    return policy.canCreateTenant() || policy.canCreateTenantWideRole();
  }

  @override
  AccessAdminWorkspaceQuery get listQuery {
    final bool crossTenant =
        _canPickTenant && allTenants && tenantFilter == null;
    final bool tenantWide =
        _canFilterAcrossFacilities && allFacilities && facilityFilter == null;
    final AccessAdminPanel panel = widget.panel;
    final AccessAdminResource resource = panel == AccessAdminPanel.permissions
        ? AccessAdminResource.permissions
        : AccessAdminResource.roles;
    return AccessAdminWorkspaceQuery(
      panel: panel,
      resource: resource,
      roleScope: roleScopeFilter,
      lean: true,
      includeDeleted: panel != AccessAdminPanel.permissions,
      tenantId: crossTenant ? null : tenantFilter,
      facilityId: tenantWide ? null : facilityFilter,
      allTenants: crossTenant,
      allFacilities: tenantWide || crossTenant,
    );
  }

  Future<void> _applyRoleListFilters(AppSearchBarFilterValue value) async {
    final String? nextTenant = value.option(_tenantFilterKey);
    final String? nextFacilityRaw = value.option(_facilityFilterKey);
    final String? nextRoleScope = value.option(_roleScopeFilterKey);

    final bool nextAllTenants = _canPickTenant && nextTenant == null;
    final bool nextAllFacilities = nextAllTenants
        ? true
        : (_canFilterAcrossFacilities && nextFacilityRaw == null);
    final String? nextFacility = nextAllFacilities || nextAllTenants
        ? null
        : nextFacilityRaw;

    if (tenantFilter == nextTenant &&
        facilityFilter == nextFacility &&
        allTenants == nextAllTenants &&
        allFacilities == nextAllFacilities &&
        roleScopeFilter == nextRoleScope) {
      return;
    }

    final bool tenantScopeChanged =
        tenantFilter != nextTenant || allTenants != nextAllTenants;

    setState(() {
      tenantFilter = nextTenant;
      facilityFilter = nextFacility;
      allTenants = nextAllTenants;
      allFacilities = nextAllFacilities;
      roleScopeFilter = nextRoleScope;
    });
    await reload(
      resetPage: true,
      silent: items.isNotEmpty,
      refreshLookups: tenantScopeChanged,
    );
  }

  Future<void> _openCreateRoleDialog() async {
    final AccessAdminWorkspaceState? state = buildWorkspaceState();
    if (state == null || !mounted) {
      return;
    }
    final AccessAdminItem? createdOrExisting =
        await openAccessAdminCreateRoleDialog(
      context,
      ref,
      state,
    );
    if (createdOrExisting != null && mounted) {
      mutated = true;
      // Open details immediately so the roles list never flashes between create
      // and detail. List reload runs silently in the background.
      unawaited(reload(resetPage: true, silent: true));
      await _openRoleDetail(createdOrExisting, coverListImmediately: true);
    }
  }

  Future<void> _openRoleDetail(
    AccessAdminItem role, {
    bool coverListImmediately = false,
  }) async {
    if (!mounted) {
      return;
    }

    var coverOpen = false;
    if (coverListImmediately) {
      final Completer<void> coverReady = Completer<void>();
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          useRootNavigator: true,
          builder: (BuildContext dialogContext) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!coverReady.isCompleted) {
                coverReady.complete();
              }
            });
            final ThemeData theme = Theme.of(dialogContext);
            return PopScope(
              canPop: false,
              child: Center(
                child: Material(
                  color: theme.colorScheme.surface,
                  elevation: 2,
                  borderRadius: BorderRadius.circular(theme.radius.md),
                  child: Padding(
                    padding: EdgeInsets.all(theme.spacing.lg),
                    // Compact mark is ~72px; do not clamp to 36×36 (overflows).
                    child: const AppLoadingIndicator.compact(expand: false),
                  ),
                ),
              ),
            );
          },
        ),
      );
      await coverReady.future;
      coverOpen = true;
    }

    final Result<List<AccessAdminRolePermissionAssignment>> permissionsResult =
        await repository.listRolePermissions(role.mutationId);

    if (coverOpen && mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      coverOpen = false;
    }
    if (!mounted) {
      return;
    }

    final List<AccessAdminRolePermissionAssignment>? permissions =
        permissionsResult.when(
          success: (List<AccessAdminRolePermissionAssignment> value) => value,
          failure: (AppFailure failure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.failureMessage(failure))),
            );
            return null;
          },
        );
    if (permissions == null || !mounted) {
      return;
    }

    await showAppDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => _AccessAdminRoleDetailDialog(
        role: role,
        permissions: permissions,
        canWrite: canWrite,
        canMutateSystemCatalog: canMutateAccessAdminSystemCatalog(
          ref.read(appAccessPolicyProvider),
          isSystemCritical: role.isSystemCritical,
        ),
        repository: repository,
        catalogTenantId:
            role.tenantId ??
            tenantFilter ??
            ref.read(sessionStateProvider).session?.user?.tenantId,
        onEdit: () {
          Navigator.of(dialogContext).pop();
          unawaited(_openEditRoleDialog(role));
        },
        onDelete: () {
          Navigator.of(dialogContext).pop();
          unawaited(_confirmDeleteRole(role));
        },
        onPermissionsChanged: () {
          mutated = true;
        },
      ),
    );
  }

  Future<void> _openPermissionDetail(AccessAdminItem permission) async {
    if (!mounted) {
      return;
    }
    await showAccessAdminPermissionDetailDialog(
      context,
      permission: permission,
    );
  }

  Future<void> _openEditRoleDialog(AccessAdminItem role) async {
    if (role.isDeleted) {
      return;
    }
    final AccessAdminWorkspaceState? state = buildWorkspaceState();
    if (state == null || !mounted) {
      return;
    }
    final AccessAdminItem? updated = await openAccessAdminEditRoleDialog(
      context,
      ref,
      state,
      role,
    );
    if (updated != null && mounted) {
      mutated = true;
      // Mirror create: open details immediately; refresh list in the background.
      unawaited(reload(resetPage: true, silent: true));
      await _openRoleDetail(updated, coverListImmediately: true);
    }
  }

  Future<void> _confirmDeleteRole(AccessAdminItem role) async {
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    if (!canMutateAccessAdminSystemCatalog(
          policy,
          isSystemCritical: role.isSystemCritical,
        ) ||
        role.isDeleted ||
        _isRoleActionBusy(role)) {
      return;
    }
    final AppLocalizations l10n = context.l10n;
    final String body = role.userCount > 0
        ? l10n.accessAdminSoftDeleteRoleAssignedBody(role.title, role.userCount)
        : l10n.accessAdminSoftDeleteRoleBody(role.title);
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AppConfirmActionDialog(
        title: l10n.accessAdminDeleteRoleAction,
        body: body,
        highlightedText: role.title,
        submitLabel: l10n.tenantFacilityDeleteConfirmAction,
        destructive: true,
        icon: const Icon(Icons.delete_outline),
        onConfirm: () => _runRoleLifecycleMutation(
          role,
          () => repository.deleteRole(role.mutationId),
        ),
      ),
    );
    if (!mounted || confirmed != true) {
      if (mounted && confirmed != true) {
        _setRoleActionBusy(role, busy: false);
      }
      return;
    }
    mutated = true;
    _markRoleSoftDeletedLocally(role);
    await _syncRoleListAfterLifecycle();
    if (mounted) {
      // Keep soft-delete visible locally if the refresh is briefly stale.
      _markRoleSoftDeletedLocally(role);
    }
  }

  Future<void> _confirmRestoreRole(AccessAdminItem role) async {
    if (!role.isDeleted || _isRoleActionBusy(role)) {
      return;
    }
    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AppConfirmActionDialog(
        title: l10n.tenantFacilityRestoreStructureTitle,
        body: l10n.tenantFacilityRestoreStructureBody(role.title),
        highlightedText: role.title,
        submitLabel: l10n.tenantFacilityRestoreStructureAction,
        icon: const Icon(Icons.restore_outlined),
        onConfirm: () => _runRoleLifecycleMutation(
          role,
          () => repository.restoreRole(role.mutationId),
        ),
      ),
    );
    if (!mounted || confirmed != true) {
      if (mounted && confirmed != true) {
        _setRoleActionBusy(role, busy: false);
      }
      return;
    }
    mutated = true;
    _markRoleRestoredLocally(role);
    await _syncRoleListAfterLifecycle();
    if (mounted) {
      // Keep the restored row active if the refresh is briefly stale.
      _markRoleRestoredLocally(role);
    }
  }

  Future<void> _confirmPermanentDeleteRole(AccessAdminItem role) async {
    final AppAccessPolicy policy = ref.read(appAccessPolicyProvider);
    if (!role.isDeleted ||
        !canMutateAccessAdminSystemCatalog(
          policy,
          isSystemCritical: role.isSystemCritical,
        ) ||
        _isRoleActionBusy(role)) {
      return;
    }
    final AppLocalizations l10n = context.l10n;
    final String confirmName = (role.displayName ?? role.title).trim();
    final String? typed = await showAppDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AppTextInputActionDialog(
        title: l10n.tenantFacilityPermanentDeleteConfirmationTitle,
        description: l10n.accessAdminPermanentDeleteRoleWarningBody(confirmName),
        fieldLabel: l10n.tenantFacilityPermanentDeleteConfirmFieldLabel(
          confirmName,
        ),
        submitLabel: l10n.tenantFacilityPermanentDeleteConfirmAction,
        cancelLabel: l10n.commonCancelActionLabel,
        requiredMessage: l10n.validationRequired,
        confirmMismatchMessage:
            l10n.tenantFacilityPermanentDeleteConfirmFieldLabel(confirmName),
        confirmMatches: (String value) =>
            _rolePermanentDeleteNameMatches(role, value, l10n: l10n),
        destructive: true,
        minLines: 1,
        maxLines: 1,
        icon: const Icon(Icons.delete_forever_outlined),
      ),
    );

    if (!mounted || typed == null) {
      return;
    }
    // Dialog already validates the typed name; keep a hard guard.
    if (!_rolePermanentDeleteNameMatches(role, typed, l10n: l10n)) {
      return;
    }

    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AppConfirmActionDialog(
        title: l10n.tenantFacilityPermanentDeleteConfirmationTitle,
        body: l10n.accessAdminPermanentDeleteRoleConfirmationBody(confirmName),
        highlightedText: confirmName,
        submitLabel: l10n.tenantFacilityPermanentDeleteConfirmAction,
        destructive: true,
        icon: const Icon(Icons.delete_forever_outlined),
        onConfirm: () => _runRoleLifecycleMutation(
          role,
          () async {
            final String roleId =
                (role.resourceUuid ?? role.mutationId).trim().isNotEmpty
                ? (role.resourceUuid ?? role.mutationId).trim()
                : role.id;
            final Result<void> result = await repository.permanentDeleteRole(
              roleId,
            );
            return result.when(
              success: (_) => const Result<void>.success(null),
              failure: (AppFailure failure) => Result<void>.failure(failure),
            );
          },
        ),
      ),
    );

    if (!mounted || confirmed != true) {
      if (mounted && confirmed != true) {
        _setRoleActionBusy(role, busy: false);
      }
      return;
    }
    mutated = true;
    _markRolePurgedLocally(role);
    await _syncRoleListAfterLifecycle(resetPage: items.isEmpty);
    if (!mounted) {
      return;
    }
    // If the row is still present after reload, the purge did not stick.
    final bool stillPresent = items.any(
      (AccessAdminItem entry) => _isSameAccessAdminRole(entry, role),
    );
    if (stillPresent) {
      _setRoleActionBusy(role, busy: false);
      for (final String key in _roleLifecycleKeys(role)) {
        _pendingPurgedRoleKeys.remove(key);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.failureMessage(AppFailure.unexpected())),
          ),
        );
      }
      return;
    }
    _markRolePurgedLocally(role);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final AppAccessPolicy accessPolicy = ref.watch(appAccessPolicyProvider);
    final bool canViewTenantRoles = accessPolicy.canCreateTenantWideRole();
    final bool canPickTenant = accessPolicy.canCreateTenant();
    final bool canFilterFacilities = accessPolicy.canCreateTenantWideRole();
    final bool showFacilityFilter =
        canFilterFacilities && (!canPickTenant || tenantFilter != null);

    final List<AppSearchBarFilterGroup> filterGroups =
        <AppSearchBarFilterGroup>[
          if (canPickTenant)
            AppSearchBarFilterGroup(
              key: _tenantFilterKey,
              label: l10n.settingsWorkspaceTenantLabel,
              allLabel: l10n.accessAdminAllTenantsFilterLabel,
              choices:
                  (workspaceData?.lookups.tenants ??
                          const <AccessAdminLookupOption>[])
                      .map(
                        (AccessAdminLookupOption tenant) =>
                            AppSearchBarFilterChoice(
                              value: tenant.id,
                              label: tenant.label,
                              icon: Icons.apartment_outlined,
                            ),
                      )
                      .toList(growable: false),
            ),
          if (showFacilityFilter)
            AppSearchBarFilterGroup(
              key: _facilityFilterKey,
              label: l10n.settingsWorkspaceFacilityLabel,
              allLabel: l10n.accessAdminAllFacilitiesFilterLabel,
              choices:
                  (workspaceData?.lookups.facilities ??
                          const <AccessAdminLookupOption>[])
                      .map(
                        (AccessAdminLookupOption facility) =>
                            AppSearchBarFilterChoice(
                              value: facility.id,
                              label: facility.label,
                              icon: Icons.local_hospital_outlined,
                            ),
                      )
                      .toList(growable: false),
            ),
          if (canViewTenantRoles)
            AppSearchBarFilterGroup(
              key: _roleScopeFilterKey,
              label: l10n.accessAdminColumnScope,
              allLabel: l10n.accessAdminRoleScopeFilterAll,
              choices: <AppSearchBarFilterChoice>[
                AppSearchBarFilterChoice(
                  value: 'platform',
                  label: l10n.accessAdminRoleScopeFilterPlatform,
                  icon: Icons.public_outlined,
                ),
                AppSearchBarFilterChoice(
                  value: 'tenant',
                  label: l10n.accessAdminRoleScopeFilterTenant,
                  icon: Icons.domain_outlined,
                ),
                AppSearchBarFilterChoice(
                  value: 'facility',
                  label: l10n.accessAdminRoleScopeFilterFacility,
                  icon: Icons.local_hospital_outlined,
                ),
              ],
            ),
        ];

    final Map<String, String> activeOptions = <String, String>{
      if (tenantFilter != null) _tenantFilterKey: tenantFilter!,
      if (showFacilityFilter && !allFacilities && facilityFilter != null)
        _facilityFilterKey: facilityFilter!,
      if (roleScopeFilter != null) _roleScopeFilterKey: roleScopeFilter!,
    };

    final String title = widget.panel == AccessAdminPanel.permissions
        ? l10n.tenantFacilitySetupTabPermissions
        : l10n.homeManageRolesPermissionsTitle;
    final IconData icon = widget.panel == AccessAdminPanel.permissions
        ? Icons.key_outlined
        : Icons.admin_panel_settings_outlined;
    final bool isPermissions = widget.panel == AccessAdminPanel.permissions;
    final bool showTenantColumn = canPickTenant && allTenants;
    final List<AppListTableColumn<AccessAdminItem>> permissionColumns =
        accessAdminPermissionColumns(context);
    final List<AppListTableColumn<AccessAdminItem>> permissionDefaults =
        permissionColumns
            .where(
              (AppListTableColumn<AccessAdminItem> column) =>
                  column.id == 'perm_id' ||
                  column.id == 'perm_name' ||
                  (showTenantColumn && column.id == 'perm_tenant') ||
                  column.id == 'perm_description',
            )
            .toList(growable: false);
    final List<AppListTableColumn<AccessAdminItem>> permissionChoices =
        permissionColumns
            .where(
              (AppListTableColumn<AccessAdminItem> column) =>
                  column.id == 'perm_code' ||
                  (!showTenantColumn && column.id == 'perm_tenant'),
            )
            .toList(growable: false);
    final bool roleActionsBusy = _roleActionBusyKey != null;
    final Widget table = SizedBox.expand(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: 2,
            child: roleActionsBusy || mutating
                ? const LinearProgressIndicator(minHeight: 2)
                : const SizedBox.expand(),
          ),
          Expanded(
            child: buildTable(
          l10n: l10n,
          columnVisibilityStorageKey: isPermissions
              ? 'access_admin_manage_permissions_v4'
              : 'access_admin_manage_roles_v3',
          onRowSelected: isPermissions
              ? (AccessAdminItem permission) =>
                    unawaited(_openPermissionDetail(permission))
              : roleActionsBusy
              ? null
              : (AccessAdminItem role) => unawaited(_openRoleDetail(role)),
          emptyAction: !isPermissions && canWrite && widget.showCreateAction
              ? AppButton.primary(
                  label: l10n.accessAdminCreateRoleAction,
                  leadingIcon: Icons.badge_outlined,
                  enabled: !loading && !mutating,
                  onPressed: loading || mutating
                      ? null
                      : () => unawaited(_openCreateRoleDialog()),
                )
              : null,
          search: buildTableSearch(
            l10n: l10n,
            showAdvancedFilterButton: filterGroups.isNotEmpty,
            advancedFilterTitle: l10n.commonAdvancedFiltersTitle,
            filterGroups: filterGroups,
            filterValue: activeOptions.isEmpty
                ? AppSearchBarFilterValue.empty
                : AppSearchBarFilterValue(options: activeOptions),
            hasActiveFilters: activeOptions.isNotEmpty,
            onFilterChanged: filterGroups.isEmpty
                ? null
                : (AppSearchBarFilterValue value) {
                    unawaited(_applyRoleListFilters(value));
                  },
            trailingActions: !isPermissions &&
                    canWrite &&
                    widget.showCreateAction
                ? <AppSearchBarAction>[
                    AppSearchBarAction(
                      icon: Icons.badge_outlined,
                      label: l10n.accessAdminCreateRoleAction,
                      tooltip: l10n.accessAdminCreateRoleAction,
                      onPressed: loading || mutating
                          ? null
                          : () => unawaited(_openCreateRoleDialog()),
                    ),
                  ]
                : const <AppSearchBarAction>[],
          ),
          columns: isPermissions
              ? permissionDefaults
              : <AppListTableColumn<AccessAdminItem>>[
                  AppListTableColumn<AccessAdminItem>(
                    id: 'id',
                    label: l10n.accessAdminColumnId,
                    sortComparator:
                        (AccessAdminItem left, AccessAdminItem right) =>
                            appListTableCompareText(
                              left.effectiveDisplayId,
                              right.effectiveDisplayId,
                            ),
                    exportValue: (AccessAdminItem item) =>
                        item.effectiveDisplayId,
                    cellBuilder: (_, AccessAdminItem item) => Text(
                      item.effectiveDisplayId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  AppListTableColumn<AccessAdminItem>(
                    id: 'name',
                    label: l10n.accessAdminColumnName,
                    sortComparator:
                        (AccessAdminItem left, AccessAdminItem right) =>
                            appListTableCompareText(left.title, right.title),
                    exportValue: (AccessAdminItem item) => item.title,
                    cellBuilder: (BuildContext context, AccessAdminItem item) {
                      final ThemeData theme = Theme.of(context);
                      return Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: item.isDeleted
                            ? theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              )
                            : theme.textTheme.bodyMedium,
                      );
                    },
                  ),
                  if (showTenantColumn)
                    AppListTableColumn<AccessAdminItem>(
                      id: 'tenant',
                      label: l10n.settingsWorkspaceTenantLabel,
                      sortComparator:
                          (AccessAdminItem left, AccessAdminItem right) =>
                              appListTableCompareText(
                                left.tenantName,
                                right.tenantName,
                              ),
                      exportValue: (AccessAdminItem item) =>
                          (item.tenantName ?? '').trim().isNotEmpty
                          ? item.tenantName!.trim()
                          : '—',
                      cellBuilder: (_, AccessAdminItem item) => Text(
                        (item.tenantName ?? '').trim().isNotEmpty
                            ? item.tenantName!.trim()
                            : '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  AppListTableColumn<AccessAdminItem>(
                    id: 'scope',
                    label: l10n.accessAdminColumnScope,
                    sortComparator:
                        (AccessAdminItem left, AccessAdminItem right) =>
                            appListTableCompareText(
                              accessAdminRoleScopeLabel(context, left),
                              accessAdminRoleScopeLabel(context, right),
                            ),
                    exportValue: (AccessAdminItem item) {
                      if (item.isFacilityScopedRole) {
                        final String? facility = item.facilityName?.trim();
                        return facility != null && facility.isNotEmpty
                            ? '${l10n.accessAdminRoleScopeFacilityBadge} · $facility'
                            : l10n.accessAdminRoleScopeFacilityBadge;
                      }
                      if (item.isPlatformScopedRole) {
                        return l10n.accessAdminRoleScopePlatformLabel;
                      }
                      return l10n.accessAdminRoleScopeTenantBadge;
                    },
                    cellBuilder:
                        (BuildContext context, AccessAdminItem item) =>
                            _RoleScopeBadge(item: item),
                  ),
                  if (canWrite)
                    AppListTableColumn<AccessAdminItem>(
                      id: 'actions',
                      label: l10n.accessAdminColumnActions,
                      alwaysVisible: true,
                      exportable: false,
                      cellBuilder: (BuildContext context, AccessAdminItem role) {
                        final ThemeData theme = Theme.of(context);
                        final double actionGap = theme.spacing.md;
                        final bool rowBusy = _isRoleActionBusy(role);
                        final bool actionsEnabled =
                            !loading && !mutating && !rowBusy;
                        if (role.isDeleted) {
                          return Padding(
                            padding: EdgeInsetsDirectional.only(
                              end: theme.spacing.sm,
                            ),
                            child: Wrap(
                              spacing: actionGap,
                              runSpacing: theme.spacing.xs,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: <Widget>[
                                AppButton.tertiary(
                                  leadingIcon: Icons.restore_outlined,
                                  label:
                                      l10n.tenantFacilityRestoreStructureAction,
                                  semanticLabel:
                                      l10n.tenantFacilityRestoreStructureAction,
                                  tooltip:
                                      l10n.tenantFacilityRestoreStructureAction,
                                  enabled: actionsEnabled,
                                  isLoading: rowBusy,
                                  onPressed: actionsEnabled
                                      ? () => unawaited(
                                            _confirmRestoreRole(role),
                                          )
                                      : null,
                                ),
                                if (canMutateAccessAdminSystemCatalog(
                                  accessPolicy,
                                  isSystemCritical: role.isSystemCritical,
                                ))
                                  AppButton.tertiary(
                                    leadingIcon: Icons.delete_forever_outlined,
                                    label:
                                        l10n.tenantFacilityPermanentDeleteAction,
                                    semanticLabel:
                                        l10n.tenantFacilityPermanentDeleteAction,
                                    tooltip:
                                        l10n.tenantFacilityPermanentDeleteAction,
                                    color: colorScheme.error,
                                    enabled: actionsEnabled,
                                    isLoading: rowBusy,
                                    onPressed: actionsEnabled
                                        ? () => unawaited(
                                              _confirmPermanentDeleteRole(role),
                                            )
                                        : null,
                                  ),
                              ],
                            ),
                          );
                        }
                        return Padding(
                          padding: EdgeInsetsDirectional.only(
                            end: theme.spacing.sm,
                          ),
                          child: Wrap(
                            spacing: actionGap,
                            runSpacing: theme.spacing.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: <Widget>[
                              if (canMutateAccessAdminSystemCatalog(
                                accessPolicy,
                                isSystemCritical: role.isSystemCritical,
                              ))
                                AppButton.tertiary(
                                  leadingIcon: Icons.edit_outlined,
                                  label: l10n.tenantFacilityEditAction,
                                  semanticLabel: l10n.tenantFacilityEditAction,
                                  tooltip: l10n.tenantFacilityEditAction,
                                  enabled: actionsEnabled,
                                  onPressed: actionsEnabled
                                      ? () =>
                                            unawaited(_openEditRoleDialog(role))
                                      : null,
                                ),
                              if (canMutateAccessAdminSystemCatalog(
                                accessPolicy,
                                isSystemCritical: role.isSystemCritical,
                              ))
                                AppButton.tertiary(
                                  leadingIcon: Icons.delete_outline,
                                  label: l10n.tenantFacilityDeleteAction,
                                  semanticLabel:
                                      l10n.tenantFacilityDeleteAction,
                                  tooltip: l10n.tenantFacilityDeleteAction,
                                  color: colorScheme.error,
                                  enabled: actionsEnabled,
                                  isLoading: rowBusy,
                                  onPressed: actionsEnabled
                                      ? () =>
                                            unawaited(_confirmDeleteRole(role))
                                      : null,
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
          columnChoices: isPermissions
              ? permissionChoices
              : <AppListTableColumn<AccessAdminItem>>[
                  if (!showTenantColumn)
                    AppListTableColumn<AccessAdminItem>(
                      id: 'tenant',
                      label: l10n.settingsWorkspaceTenantLabel,
                      sortComparator:
                          (AccessAdminItem left, AccessAdminItem right) =>
                              appListTableCompareText(
                                left.tenantName,
                                right.tenantName,
                              ),
                      exportValue: (AccessAdminItem item) =>
                          (item.tenantName ?? '').trim().isNotEmpty
                          ? item.tenantName!.trim()
                          : '—',
                      cellBuilder: (_, AccessAdminItem item) => Text(
                        (item.tenantName ?? '').trim().isNotEmpty
                            ? item.tenantName!.trim()
                            : '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  AppListTableColumn<AccessAdminItem>(
                    id: 'status',
                    label: l10n.accessAdminColumnStatus,
                    sortComparator:
                        (AccessAdminItem left, AccessAdminItem right) =>
                            appListTableCompareText(
                              left.isDeleted
                                  ? l10n.tenantFacilityStructureDeletedStatus
                                  : (left.status ?? '—'),
                              right.isDeleted
                                  ? l10n.tenantFacilityStructureDeletedStatus
                                  : (right.status ?? '—'),
                            ),
                    exportValue: (AccessAdminItem item) => item.isDeleted
                        ? l10n.tenantFacilityStructureDeletedStatus
                        : (item.status ?? '—'),
                    cellBuilder: (_, AccessAdminItem item) => Text(
                      item.isDeleted
                          ? l10n.tenantFacilityStructureDeletedStatus
                          : (item.status ?? '—'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  AppListTableColumn<AccessAdminItem>(
                    id: 'details',
                    label: l10n.accessAdminColumnDetails,
                    sortComparator:
                        (AccessAdminItem left, AccessAdminItem right) =>
                            appListTableCompareText(
                              left.subtitle,
                              right.subtitle,
                            ),
                    exportValue: (AccessAdminItem item) => item.subtitle ?? '—',
                    cellBuilder: (_, AccessAdminItem item) => Text(
                      item.subtitle ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
            ),
          ),
        ],
      ),
    );

    final Widget? createAction =
        (!isPermissions && canWrite && widget.showCreateAction)
        ? AppButton.primary(
            label: l10n.accessAdminCreateRoleAction,
            leadingIcon: Icons.badge_outlined,
            onPressed: loading || mutating
                ? null
                : () => unawaited(_openCreateRoleDialog()),
          )
        : null;

    if (!widget.dialogMode) {
      return table;
    }

    return AppDialog(
      title: Text(title),
      icon: Icon(icon),
      pinActionsToBottom: true,
      maxWidth: 1200,
      content: table,
      actions: <Widget>[
        if (createAction != null) createAction,
        AppButton.secondary(
          label: l10n.commonCloseActionLabel,
          leadingIcon: Icons.close,
          onPressed: () => Navigator.of(context).pop(mutated ? true : null),
        ),
      ],
    );
  }
}

const String _roleScopeFilterKey = 'role_scope';

class _AccessAdminPermissionDetailDialog extends StatelessWidget {
  const _AccessAdminPermissionDetailDialog({required this.permission});

  final AccessAdminItem permission;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final String? code = accessAdminPermissionMachineCode(permission);
    final String description = accessAdminPermissionDescription(
      l10n,
      permission,
    );

    return AppDialog(
      title: Text(l10n.accessAdminPermissionDetailsTitle),
      icon: const Icon(Icons.key_outlined),
      scrollable: true,
      pinActionsToBottom: true,
      maxWidth: 720,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _PermissionDetailSummaryCard(
            permission: permission,
            code: code,
          ),
          if (description != '—') ...<Widget>[
            SizedBox(height: theme.spacing.md),
            AppCollapsibleSection(
              title: l10n.accessAdminPermissionDescriptionColumnLabel,
              titleIcon: Icons.notes_outlined,
              child: Text(
                description,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
              ),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        AppButton.secondary(
          label: l10n.commonCloseActionLabel,
          leadingIcon: Icons.close,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _PermissionDetailSummaryCard extends StatelessWidget {
  const _PermissionDetailSummaryCard({
    required this.permission,
    required this.code,
  });

  final AccessAdminItem permission;
  final String? code;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(theme.radius.md),
        border: theme.borders.all(),
      ),
      child: Padding(
        padding: EdgeInsets.all(theme.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(theme.radius.sm),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.key_outlined,
                    color: colors.onPrimaryContainer,
                  ),
                ),
                SizedBox(width: theme.spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        permission.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: AppFontWeight.emphasis,
                        ),
                      ),
                      if (code != null) ...<Widget>[
                        SizedBox(height: theme.spacing.xs),
                        SelectableText(
                          code!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontFamily: AppFontFamily.monospace,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Chip(
                  avatar: Icon(
                    Icons.lock_outline,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                  label: Text(
                    l10n.accessAdminPermissionReadOnlyBadge,
                    style: theme.textTheme.labelSmall,
                  ),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: colors.surface,
                  side: theme.borders.side(),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
            SizedBox(height: theme.spacing.md),
            AppInfoSheetGrid(
              items: <AppInfoSheetItem>[
                AppInfoSheetItem(
                  label: l10n.accessAdminPermissionIdColumnLabel,
                  value: permission.effectiveDisplayId,
                  copyable: true,
                  copyTooltip: l10n.copyIdentifierAction,
                  copiedMessage: l10n.identifierCopiedMessage,
                ),
                if (code != null)
                  AppInfoSheetItem(
                    label: l10n.accessAdminPermissionCodeColumnLabel,
                    value: code,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessAdminRoleDetailDialog extends StatefulWidget {
  const _AccessAdminRoleDetailDialog({
    required this.role,
    required this.permissions,
    required this.canWrite,
    required this.canMutateSystemCatalog,
    required this.repository,
    required this.onEdit,
    required this.onDelete,
    this.catalogTenantId,
    this.onPermissionsChanged,
  });

  final AccessAdminItem role;
  final List<AccessAdminRolePermissionAssignment> permissions;
  final bool canWrite;
  final bool canMutateSystemCatalog;
  final AccessAdminRepository repository;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  /// Tenant used to load the assignable permission catalog when the role is
  /// platform-scoped (`tenant_id` null) or the create payload lacked tenant.
  final String? catalogTenantId;
  final VoidCallback? onPermissionsChanged;

  @override
  State<_AccessAdminRoleDetailDialog> createState() =>
      _AccessAdminRoleDetailDialogState();
}

class _AccessAdminRoleDetailDialogState
    extends State<_AccessAdminRoleDetailDialog> {
  late List<AccessAdminRolePermissionAssignment> _permissions;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _permissions = List<AccessAdminRolePermissionAssignment>.from(
      widget.permissions,
    );
  }

  List<AppPermissionAssignmentOption> _permissionOptions(
    AppLocalizations l10n,
  ) {
    final Set<String> seenKeys = <String>{};
    final List<AppPermissionAssignmentOption> options =
        <AppPermissionAssignmentOption>[];
    for (final AccessAdminRolePermissionAssignment assignment in _permissions) {
      final String code =
          (assignment.permissionName ?? assignment.permissionId ?? '').trim();
      if (code.isEmpty) {
        continue;
      }
      final String codeKey = 'code:${code.toLowerCase()}';
      final String permissionId = (assignment.permissionId ?? '').trim();
      if (permissionId.isNotEmpty &&
          !seenKeys.add('id:${permissionId.toLowerCase()}')) {
        continue;
      }
      if (!seenKeys.add(codeKey)) {
        continue;
      }
      options.add(
        AppPermissionAssignmentOption(
          id: permissionId.isNotEmpty ? permissionId : assignment.id,
          code: code,
          label: l10n.permissionAssignmentLabelForCode(code),
          description: l10n.permissionCatalogDescriptionForCode(code),
        ),
      );
    }
    return options;
  }

  Future<void> _addPermissions() async {
    final AppLocalizations l10n = context.l10n;
    final String? tenantId =
        (widget.role.tenantId ?? widget.catalogTenantId)?.trim();
    if (tenantId == null || tenantId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.accessAdminTenantContextRequiredBody)),
      );
      return;
    }

    setState(() => _saving = true);
    // Prefer cached catalog; force-refresh made Add permissions feel hung on
    // every open while ensureTenantPermissionCatalog ran.
    final Result<AccessAdminLookups> lookupResult = await widget.repository
        .getReferenceData(
          tenantId: tenantId,
          facilityId: widget.role.facilityId,
          include: const <String>['permissions'],
          forceRefresh: true,
        );
    if (!mounted) {
      return;
    }
    final AccessAdminLookups? resolved = lookupResult.when(
      success: (AccessAdminLookups value) => value,
      failure: (_) => null,
    );
    setState(() => _saving = false);
    if (resolved == null || resolved.permissions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            lookupResult.when(
              success: (_) =>
                  l10n.accessAdminPermissionCatalogUnavailableMessage,
              failure: (AppFailure failure) =>
                  context.l10n.failureMessage(failure),
            ),
          ),
        ),
      );
      return;
    }

    final Set<String> catalogIds = <String>{
      for (final AccessAdminLookupOption permission in resolved.permissions)
        permission.id,
    };
    final Map<String, String> idByCode = <String, String>{
      for (final AccessAdminLookupOption permission in resolved.permissions)
        permission.label: permission.id,
    };
    final Set<String> selectedIds = <String>{};
    for (final AccessAdminRolePermissionAssignment assignment in _permissions) {
      final String permissionId = (assignment.permissionId ?? '').trim();
      final String code = (assignment.permissionName ?? '').trim();
      if (permissionId.isNotEmpty && catalogIds.contains(permissionId)) {
        selectedIds.add(permissionId);
        continue;
      }
      if (code.isNotEmpty && idByCode.containsKey(code)) {
        selectedIds.add(idByCode[code]!);
      }
    }
    final List<AppPermissionAssignmentOption> options = resolved.permissions
        .map(
          (AccessAdminLookupOption permission) => AppPermissionAssignmentOption(
            id: permission.id,
            code: permission.label,
            label: l10n.permissionAssignmentLabelForCode(
              permission.label,
              displayName: permission.displayName,
            ),
            description:
                (permission.meta ?? '').trim().isNotEmpty
                    ? permission.meta
                    : l10n.permissionCatalogDescriptionForCode(permission.label),
          ),
        )
        .toList(growable: false);

    final String syncRoleId = widget.role.mutationId.trim().isNotEmpty
        ? widget.role.mutationId
        : widget.role.id;

    final bool? saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (BuildContext dialogContext) {
        return _RolePermissionsEditorDialog(
          title: _permissions.isEmpty
              ? l10n.accessAdminAddRolePermissionsDialogTitle
              : l10n.accessAdminEditRolePermissionsDialogTitle,
          description: l10n.accessAdminAddRolePermissionsDialogDescription,
          options: options,
          initialSelectedIds: selectedIds,
          onSave: (Set<String> nextIds) async {
            final Result<void> syncResult = await widget.repository
                .syncRolePermissions(
                  roleId: syncRoleId,
                  permissionIds: nextIds.toList(growable: false),
                );
            return syncResult.when(
              success: (_) => null,
              failure: (AppFailure failure) => failure,
            );
          },
        );
      },
    );
    if (saved != true || !mounted) {
      return;
    }

    setState(() => _saving = true);
    final Result<List<AccessAdminRolePermissionAssignment>> reloadResult =
        await widget.repository.listRolePermissions(syncRoleId);
    if (!mounted) {
      return;
    }
    reloadResult.when(
      success: (List<AccessAdminRolePermissionAssignment> value) {
        setState(() {
          _permissions = value;
          _saving = false;
        });
        widget.onPermissionsChanged?.call();
      },
      failure: (AppFailure failure) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.failureMessage(failure))),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final List<AppPermissionAssignmentOption> permissionOptions =
        _permissionOptions(l10n);
    final bool canManagePermissions =
        widget.canWrite &&
        widget.canMutateSystemCatalog &&
        !widget.role.isDeleted;
    final bool hasPermissions = permissionOptions.isNotEmpty;

    return AppDialog(
      title: Text(l10n.accessAdminCreateRoleDetailsSectionTitle),
      icon: const Icon(Icons.badge_outlined),
      scrollable: true,
      pinActionsToBottom: true,
      maxWidth: 920,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_saving)
            const LinearProgressIndicator(minHeight: 2)
          else
            const SizedBox(height: 2),
          _RoleDetailSummaryCard(
            role: widget.role,
            permissionCount: permissionOptions.length,
          ),
          SizedBox(height: theme.spacing.md),
          AppCollapsibleSection(
            title: l10n.accessAdminRolePermissionsLabel,
            description: l10n.accessAdminRoleDetailPermissionsDescription,
            titleIcon: Icons.lock_outline,
            headerActions: hasPermissions && canManagePermissions
                ? <Widget>[
                    AppButton.secondary(
                      dense: true,
                      label: l10n.accessAdminEditRolePermissionsAction,
                      leadingIcon: Icons.tune_outlined,
                      enabled: !_saving,
                      onPressed: _saving
                          ? null
                          : () => unawaited(_addPermissions()),
                    ),
                  ]
                : const <Widget>[],
            child: hasPermissions
                ? AppPermissionGroupedView(
                    permissions: permissionOptions,
                    initiallyExpandAll: permissionOptions.length <= 24,
                    emptyMessage:
                        l10n.accessAdminRoleDetailNoPermissionsMessage,
                  )
                : _RolePermissionsEmptyState(
                    message: l10n.accessAdminRoleDetailNoPermissionsMessage,
                    actionLabel: l10n.accessAdminAddRolePermissionsAction,
                    showAction: canManagePermissions,
                    actionEnabled: !_saving,
                    onAdd: () => unawaited(_addPermissions()),
                  ),
          ),
        ],
      ),
      actions: <Widget>[
        if (widget.canWrite && !widget.role.isDeleted) ...<Widget>[
          if (widget.canMutateSystemCatalog)
            AppButton.secondary(
              label: l10n.accessAdminEditRoleAction,
              leadingIcon: Icons.edit_outlined,
              enabled: !_saving,
              onPressed: widget.onEdit,
            ),
          if (widget.canMutateSystemCatalog)
            AppButton.secondary(
              label: l10n.accessAdminDeleteRoleAction,
              leadingIcon: Icons.delete_outline,
              color: colors.error,
              enabled: !_saving,
              onPressed: widget.onDelete,
            ),
        ],
        AppButton.secondary(
          label: l10n.commonCloseActionLabel,
          leadingIcon: Icons.close,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _RoleDetailSummaryCard extends StatelessWidget {
  const _RoleDetailSummaryCard({
    required this.role,
    required this.permissionCount,
  });

  final AccessAdminItem role;
  final int permissionCount;

  static bool _isDistinctLabel(String? value, List<String> existing) {
    final String needle = (value ?? '').trim();
    if (needle.isEmpty) {
      return false;
    }
    final String normalized = needle.toLowerCase();
    return existing.every(
      (String other) => other.trim().toLowerCase() != normalized,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final String title = role.title.trim();
    final String? technicalName = _isDistinctLabel(role.name, <String>[title])
        ? role.name!.trim()
        : null;
    final String description = (role.subtitle ?? '').trim();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(theme.radius.md),
        border: theme.borders.all(),
      ),
      child: Padding(
        padding: EdgeInsets.all(theme.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(theme.radius.sm),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.badge_outlined,
                    color: colors.onPrimaryContainer,
                  ),
                ),
                SizedBox(width: theme.spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title.isEmpty ? '—' : title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: AppFontWeight.emphasis,
                        ),
                      ),
                      if (technicalName != null) ...<Widget>[
                        SizedBox(height: theme.spacing.xs),
                        SelectableText(
                          technicalName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontFamily: AppFontFamily.monospace,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: theme.spacing.sm),
                _RoleScopeBadge(item: role),
              ],
            ),
            SizedBox(height: theme.spacing.md),
            Text(
              l10n.accessAdminRoleDescriptionLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: AppFontWeight.emphasis,
              ),
            ),
            SizedBox(height: theme.spacing.xs),
            Text(
              description.isEmpty ? '—' : description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: description.isEmpty
                    ? colors.onSurfaceVariant
                    : colors.onSurface,
                height: 1.4,
              ),
            ),
            SizedBox(height: theme.spacing.md),
            AppInfoSheetGrid(
              items: <AppInfoSheetItem>[
                AppInfoSheetItem(
                  label: l10n.accessAdminColumnId,
                  value: role.effectiveDisplayId,
                  copyable: true,
                  copyTooltip: l10n.copyIdentifierAction,
                  copiedMessage: l10n.identifierCopiedMessage,
                ),
                AppInfoSheetItem(
                  label: l10n.accessAdminRolePermissionsLabel,
                  value: l10n.hrAccessPermissionCountLabel(permissionCount),
                ),
                AppInfoSheetItem(
                  label: l10n.accessAdminRoleDetailUsersLabel,
                  value: '${role.userCount}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RolePermissionsEmptyState extends StatelessWidget {
  const _RolePermissionsEmptyState({
    required this.message,
    required this.actionLabel,
    required this.showAction,
    required this.actionEnabled,
    required this.onAdd,
  });

  final String message;
  final String actionLabel;
  final bool showAction;
  final bool actionEnabled;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: theme.spacing.lg,
          horizontal: theme.spacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.key_off_outlined,
                color: colors.onPrimaryContainer,
                size: 28,
              ),
            ),
            SizedBox(height: theme.spacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            if (showAction) ...<Widget>[
              SizedBox(height: theme.spacing.md),
              AppButton.primary(
                label: actionLabel,
                leadingIcon: Icons.key_outlined,
                enabled: actionEnabled,
                onPressed: actionEnabled ? onAdd : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RolePermissionsEditorDialog extends StatefulWidget {
  const _RolePermissionsEditorDialog({
    required this.title,
    required this.description,
    required this.options,
    required this.initialSelectedIds,
    required this.onSave,
  });

  final String title;
  final String description;
  final List<AppPermissionAssignmentOption> options;
  final Set<String> initialSelectedIds;
  final Future<AppFailure?> Function(Set<String> selectedIds) onSave;

  @override
  State<_RolePermissionsEditorDialog> createState() =>
      _RolePermissionsEditorDialogState();
}

class _RolePermissionsEditorDialogState
    extends State<_RolePermissionsEditorDialog> {
  late Set<String> _selectedIds;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedIds = Set<String>.from(widget.initialSelectedIds);
  }

  Future<void> _submit() async {
    if (_saving) {
      return;
    }
    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    final AppFailure? failure = await widget.onSave(
      Set<String>.from(_selectedIds),
    );
    if (!mounted) {
      return;
    }
    if (failure != null) {
      setState(() {
        _saving = false;
        _errorMessage = context.l10n.failureMessage(failure);
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return AppDialog(
      title: Text(widget.title),
      icon: const Icon(Icons.key_outlined),
      maxWidth: 720,
      scrollable: true,
      pinActionsToBottom: true,
      initialMaximized: true,
      closeEnabled: !_saving,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(widget.description, style: theme.textTheme.bodyMedium),
          SizedBox(height: theme.spacing.md),
          if (_errorMessage != null) ...<Widget>[
            Text(
              _errorMessage!,
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.error),
            ),
            SizedBox(height: theme.spacing.sm),
          ],
          AppPermissionAssignmentPicker(
            permissions: widget.options,
            selectedPermissionIds: _selectedIds,
            enabled: !_saving,
            onSelectionChanged: (Set<String> next) {
              setState(() {
                // Replace the set so dependents see a new identity (avoid
                // in-place mutation that can skip didUpdateWidget).
                _selectedIds = Set<String>.from(next);
              });
            },
          ),
        ],
      ),
      actions: <Widget>[
        AppButton.close(
          label: l10n.commonCancelActionLabel,
          leadingIcon: Icons.close,
          enabled: !_saving,
          onPressed: _saving
              ? null
              : () => Navigator.of(context).pop(false),
        ),
        AppButton.primary(
          label: l10n.commonSaveActionLabel,
          leadingIcon: Icons.save_outlined,
          enabled: !_saving,
          isLoading: _saving,
          onPressed: _saving ? null : () => unawaited(_submit()),
        ),
      ],
    );
  }
}

class _RoleScopeBadge extends StatelessWidget {
  const _RoleScopeBadge({required this.item});

  final AccessAdminItem item;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isFacility = item.isFacilityScopedRole;
    final bool isPlatform = item.isPlatformScopedRole;
    final String label = isFacility
        ? (item.facilityName?.trim().isNotEmpty == true
              ? '${l10n.accessAdminRoleScopeFacilityBadge} · ${item.facilityName}'
              : l10n.accessAdminRoleScopeFacilityBadge)
        : isPlatform
        ? l10n.accessAdminRoleScopePlatformLabel
        : l10n.accessAdminRoleScopeTenantBadge;

    return Chip(
      avatar: Icon(
        isFacility
            ? Icons.local_hospital_outlined
            : isPlatform
            ? Icons.public_outlined
            : Icons.domain_outlined,
        size: 16,
        color: isFacility
            ? colors.tertiary
            : isPlatform
            ? colors.secondary
            : colors.primary,
      ),
      label: Text(label, style: theme.textTheme.labelSmall),
      visualDensity: VisualDensity.compact,
      backgroundColor: isFacility
          ? colors.tertiaryContainer
          : isPlatform
          ? colors.secondaryContainer
          : colors.primaryContainer,
      side: theme.borders.side(
        color: (isFacility
                ? colors.tertiary
                : isPlatform
                ? colors.secondary
                : colors.primary)
            .withValues(alpha: 0.28),
      ),
      padding: EdgeInsets.symmetric(horizontal: theme.spacing.xs),
    );
  }
}

class _AccessAdminUserDetailDialog extends StatefulWidget {
  const _AccessAdminUserDetailDialog({
    required this.item,
    required this.detail,
    required this.canWrite,
    required this.canDeleteProtected,
    required this.repository,
    required this.lookups,
    required this.onStatusChanged,
    required this.onEdit,
    required this.onDelete,
    this.tenantId,
    this.facilityId,
    this.onMutated,
  });

  final AccessAdminItem item;
  final AccessAdminUserDetail detail;
  final bool canWrite;
  final bool canDeleteProtected;
  final AccessAdminRepository repository;
  final AccessAdminLookups lookups;
  final String? tenantId;
  final String? facilityId;
  final Future<AppFailure?> Function(String status) onStatusChanged;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onMutated;

  @override
  State<_AccessAdminUserDetailDialog> createState() =>
      _AccessAdminUserDetailDialogState();
}

class _AccessAdminUserDetailDialogState
    extends State<_AccessAdminUserDetailDialog> {
  late AccessAdminItem _item;
  late AccessAdminUserDetail _detail;
  bool _saving = false;

  // Mutation feedback renders inside the dialog: a SnackBar sits behind the
  // modal barrier, where a rejected change reads as nothing happening.
  AppFailure? _actionFailure;
  String? _actionNotice;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _detail = widget.detail;
  }

  void _showActionFailure(AppFailure failure) {
    setState(() {
      _saving = false;
      _actionFailure = failure;
      _actionNotice = null;
    });
  }

  void _showActionNotice(String message) {
    setState(() {
      _saving = false;
      _actionFailure = null;
      _actionNotice = message;
    });
  }

  void _clearActionFeedback() {
    if (_actionFailure == null && _actionNotice == null) {
      return;
    }
    setState(() {
      _actionFailure = null;
      _actionNotice = null;
    });
  }

  Future<void> _toggleStatus() async {
    final String nextStatus = _item.status == 'ACTIVE' ? 'INACTIVE' : 'ACTIVE';
    _clearActionFeedback();
    setState(() => _saving = true);
    final AppFailure? failure = await widget.onStatusChanged(nextStatus);
    if (!mounted) return;
    if (failure == null) {
      // Tell the directory to reload so the list shows the new status.
      widget.onMutated?.call();
      Navigator.of(context).pop();
      return;
    }
    _showActionFailure(failure);
  }

  Future<void> _resetCredentials() async {
    final bool issued = await confirmAccessAdminCredentialReset(
      context,
      user: _item,
      issue: () => widget.repository.resetUserCredentials(_item.mutationId),
    );
    if (issued && mounted) {
      widget.onMutated?.call();
    }
  }

  Future<void> _reloadDetail() async {
    final Result<AccessAdminUserDetail> result = await widget.repository
        .getUserDetail(
          _item.mutationId,
          tenantId: _item.tenantId ?? widget.tenantId,
        );
    if (!mounted) return;
    result.when(
      success: (AccessAdminUserDetail detail) {
        setState(() {
          _detail = detail;
          _item = detail.item;
          _saving = false;
        });
        widget.onMutated?.call();
      },
      failure: _showActionFailure,
    );
  }

  List<AppUserAccessRoleGroup> get _roleGroups {
    return _detail.resolvedRoleGroups
        .map(
          (AccessAdminRolePermissionGroup group) => AppUserAccessRoleGroup(
            roleId: group.roleId,
            roleName: group.roleName,
            userRoleId: group.userRoleId,
            permissions: group.permissions
                .map((AccessAdminRolePermissionPreview preview) => preview.name)
                .toList(growable: false),
          ),
        )
        .toList(growable: false);
  }

  List<AppUserAccessDirectPermission> get _directPermissions {
    return _detail.directPermissions
        .map(
          (AccessAdminPermissionRef permission) =>
              AppUserAccessDirectPermission(
                id: permission.mutationId,
                name: permission.name,
              ),
        )
        .toList(growable: false);
  }

  Future<void> _addRole() async {
    final AppLocalizations l10n = context.l10n;
    final String? tenantId = (widget.tenantId ?? _item.tenantId)?.trim();
    if (tenantId == null || tenantId.isEmpty) {
      _showActionNotice(l10n.accessAdminTenantContextRequiredBody);
      return;
    }

    // Always load roles for this user's tenant/facility. Workspace list lookups
    // may be empty (lean/skipLookups) or scoped to a different tenant.
    _clearActionFeedback();
    setState(() => _saving = true);
    final Result<AccessAdminLookups> lookupResult = await widget.repository
        .getReferenceData(
          tenantId: tenantId,
          facilityId: widget.facilityId ?? _item.facilityId,
          include: const <String>['roles'],
          forceRefresh: true,
        );
    if (!mounted) return;
    final AccessAdminLookups? resolved = lookupResult.when(
      success: (AccessAdminLookups value) => value,
      failure: (_) => null,
    );
    setState(() => _saving = false);
    if (resolved == null) {
      lookupResult.when(
        success: (_) => _showActionNotice(
          l10n.accessAdminUserAccessNoAssignableRolesMessage,
        ),
        failure: _showActionFailure,
      );
      return;
    }

    final Set<String> assignedRoleIds = <String>{
      for (final AccessAdminRolePermissionGroup group
          in _detail.resolvedRoleGroups) ...<String>[
        group.roleId,
        if ((group.resourceUuid ?? '').trim().isNotEmpty) group.resourceUuid!,
      ],
    };
    final List<AccessAdminLookupOption> availableRoles = resolved.roles
        .where(
          (AccessAdminLookupOption role) =>
              role.id.trim().isNotEmpty && !assignedRoleIds.contains(role.id),
        )
        .toList(growable: false);

    if (availableRoles.isEmpty) {
      _showActionNotice(l10n.accessAdminUserAccessNoAssignableRolesMessage);
      return;
    }

    final List<AppRoleAssignmentOption> roleOptions = availableRoles
        .map(
          (AccessAdminLookupOption role) => AppRoleAssignmentOption(
            id: role.id,
            label: role.displayName?.trim().isNotEmpty == true
                ? role.displayName!.trim()
                : role.label,
            description: role.meta,
            permissionCount: role.permissionCount,
          ),
        )
        .toList(growable: false);

    final Set<String>? confirmed = await showAppRoleSelectionTableDialog(
      context: context,
      roles: roleOptions,
      title: l10n.accessAdminUserAccessAddRoleDialogTitle,
      description: l10n.accessAdminUserAccessAddRoleDialogDescription,
      searchHint: l10n.hrStaffRolesSearchHint,
      confirmLabel: l10n.accessAdminUserAccessAddRoleAction,
      emptyTitle: l10n.hrNoRolesLabel,
      emptyBody: l10n.accessAdminUserAccessNoAssignableRolesMessage,
      storageKey: 'access_admin.user_access.add_roles.table',
    );

    if (confirmed == null || confirmed.isEmpty || !mounted) {
      return;
    }
    final Set<String> rolesToAssign = confirmed;

    setState(() => _saving = true);
    AppFailure? lastFailure;
    final List<Result<void>> results = await Future.wait(
      rolesToAssign.map(
        (String roleId) => widget.repository.assignUserRole(
          AccessAdminUserRoleDraft(
            userId: _item.mutationId,
            roleId: roleId,
            tenantId: tenantId,
            facilityId: widget.facilityId ?? _item.facilityId,
          ),
        ),
      ),
    );
    for (final Result<void> result in results) {
      if (result case ResultFailure<void>(:final failure)) {
        lastFailure ??= failure;
      }
    }
    if (!mounted) return;
    // Reload even after a partial failure so roles that did save show up.
    await _reloadDetail();
    if (mounted && lastFailure != null) {
      _showActionFailure(lastFailure);
    }
  }

  Future<void> _removeRole(AppUserAccessRoleGroup group) async {
    final String? userRoleId = group.userRoleId?.trim();
    if (userRoleId == null || userRoleId.isEmpty) {
      return;
    }

    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AppConfirmActionDialog(
        title: l10n.accessAdminUserAccessRemoveRoleConfirmTitle,
        body: l10n.accessAdminUserAccessRemoveRoleConfirmMessage(
          group.roleName,
        ),
        highlightedText: group.roleName,
        submitLabel: l10n.accessAdminUserAccessRemoveRoleAction,
        destructive: true,
        icon: const Icon(Icons.remove_circle_outline),
        onConfirm: () async {
          final Result<void> result = await widget.repository.revokeUserRole(
            userRoleId,
          );
          return result.when(
            success: (_) => null,
            failure: (AppFailure failure) => failure,
          );
        },
      ),
    );
    if (confirmed == true && mounted) {
      setState(() => _saving = true);
      await _reloadDetail();
    }
  }

  Future<void> _removeAllRoles() async {
    final List<AppUserAccessRoleGroup> removable = _roleGroups
        .where((AppUserAccessRoleGroup group) => group.canRemove)
        .toList(growable: false);
    if (removable.isEmpty) {
      return;
    }

    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AppConfirmActionDialog(
        title: l10n.accessAdminUserAccessRemoveAllRolesConfirmTitle,
        body: l10n.accessAdminUserAccessRemoveAllRolesConfirmMessage(
          removable.length,
        ),
        submitLabel: l10n.accessAdminUserAccessRemoveAllRolesAction,
        destructive: true,
        icon: const Icon(Icons.delete_sweep_outlined),
        onConfirm: () async {
          AppFailure? lastFailure;
          final List<Result<void>> results = await Future.wait(
            removable.map((AppUserAccessRoleGroup group) {
              return widget.repository.revokeUserRole(group.userRoleId!.trim());
            }),
          );
          for (final Result<void> result in results) {
            if (result case ResultFailure<void>(:final failure)) {
              lastFailure ??= failure;
            }
          }
          return lastFailure;
        },
      ),
    );
    if (confirmed == true && mounted) {
      setState(() => _saving = true);
      await _reloadDetail();
    }
  }

  Future<void> _addDirectPermission() async {
    final AppLocalizations l10n = context.l10n;
    final String? tenantId = (widget.tenantId ?? _item.tenantId)?.trim();
    if (tenantId == null || tenantId.isEmpty) {
      _showActionNotice(l10n.accessAdminTenantContextRequiredBody);
      return;
    }

    _clearActionFeedback();
    setState(() => _saving = true);
    final Result<AccessAdminLookups> lookupResult = await widget.repository
        .getReferenceData(
          tenantId: tenantId,
          facilityId: widget.facilityId ?? _item.facilityId,
          include: const <String>['permissions'],
          forceRefresh: true,
        );
    if (!mounted) return;
    final AccessAdminLookups? resolved = lookupResult.when(
      success: (AccessAdminLookups value) => value,
      failure: (_) => null,
    );
    setState(() => _saving = false);
    if (resolved == null || resolved.permissions.isEmpty) {
      lookupResult.when(
        success: (_) => _showActionNotice(
          l10n.accessAdminPermissionCatalogUnavailableMessage,
        ),
        failure: _showActionFailure,
      );
      return;
    }

    final Set<String> selectedIds = _resolveDirectPermissionOptionIds(
      directs: _detail.directPermissions,
      permissionLookups: resolved.permissions,
    );
    final List<AppPermissionAssignmentOption> options = resolved.permissions
        .map(
          (AccessAdminLookupOption permission) => AppPermissionAssignmentOption(
            id: permission.id,
            code: permission.label,
            label: l10n.permissionAssignmentLabelForCode(
              permission.label,
              displayName: permission.displayName,
            ),
            description:
                (permission.meta ?? '').trim().isNotEmpty
                    ? permission.meta
                    : l10n.permissionCatalogDescriptionForCode(permission.label),
          ),
        )
        .toList(growable: false);

    // The editor keeps save errors (missing read rights, assignment ceiling)
    // inline, so the selection survives a rejected save.
    final bool? saved = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => _RolePermissionsEditorDialog(
        title: l10n.accessAdminUserAccessAddDirectPermissionDialogTitle,
        description:
            l10n.accessAdminUserAccessAddDirectPermissionDialogDescription,
        options: options,
        initialSelectedIds: selectedIds,
        onSave: (Set<String> permissionIds) async {
          final Result<void> result = await widget.repository
              .syncUserDirectPermissions(
                userId: _item.mutationId,
                permissionIds: permissionIds.toList(growable: false),
              );
          return result.when(
            success: (_) => null,
            failure: (AppFailure failure) => failure,
          );
        },
      ),
    );

    if (saved != true || !mounted) {
      return;
    }

    setState(() => _saving = true);
    await _reloadDetail();
  }

  Future<void> _removeDirectPermission(
    AppUserAccessDirectPermission permission,
  ) async {
    final List<String> nextIds = _detail.directPermissions
        .where(
          (AccessAdminPermissionRef entry) =>
              entry.mutationId != permission.id && entry.id != permission.id,
        )
        .map((AccessAdminPermissionRef entry) => entry.mutationId)
        .toList(growable: false);

    setState(() => _saving = true);
    final Result<void> result = await widget.repository
        .syncUserDirectPermissions(
          userId: _item.mutationId,
          permissionIds: nextIds,
        );
    if (!mounted) return;
    final AppFailure? failure = result.when(
      success: (_) => null,
      failure: (AppFailure value) => value,
    );
    if (failure != null) {
      _showActionFailure(failure);
      return;
    }
    await _reloadDetail();
  }

  Future<void> _removeAllDirectPermissions() async {
    final int count = _detail.directPermissions.length;
    if (count == 0) {
      return;
    }

    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AppConfirmActionDialog(
        title: l10n.accessAdminUserAccessRemoveAllDirectPermissionsConfirmTitle,
        body: l10n.accessAdminUserAccessRemoveAllDirectPermissionsConfirmMessage(
          count,
        ),
        submitLabel: l10n.accessAdminUserAccessRemoveAllDirectPermissionsAction,
        destructive: true,
        icon: const Icon(Icons.delete_sweep_outlined),
        onConfirm: () async {
          final Result<void> result = await widget.repository
              .syncUserDirectPermissions(
                userId: _item.mutationId,
                permissionIds: const <String>[],
              );
          return result.when(
            success: (_) => null,
            failure: (AppFailure failure) => failure,
          );
        },
      ),
    );
    if (confirmed == true && mounted) {
      setState(() => _saving = true);
      await _reloadDetail();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final AccessAdminItem item = _item;
    final bool canMutate =
        widget.canWrite &&
        !item.isDeleted &&
        canMutateAccessAdminDemoAccount(item);
    final bool canResetCredentials =
        canMutate &&
        (widget.canDeleteProtected || !item.isSystemCritical) &&
        (item.email ?? '').trim().isNotEmpty;

    return AppDialog(
      title: Text(l10n.accessAdminCreateUserDetailsSectionTitle),
      icon: const Icon(Icons.person_outline),
      scrollable: true,
      pinActionsToBottom: true,
      maxWidth: 920,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppCollapsibleSection(
            title: l10n.accessAdminUserDetailProfileSectionTitle,
            titleIcon: Icons.badge_outlined,
            child: _UserDetailAccountFields(item: item),
          ),
          SizedBox(height: theme.spacing.md),
          // Right above the role / permission actions that produce it.
          if (_actionFailure != null) ...<Widget>[
            AppFormInformationBanner.failure(
              context: context,
              failure: _actionFailure!,
            ),
            SizedBox(height: theme.spacing.md),
          ] else if (_actionNotice != null) ...<Widget>[
            AppFormInformationBanner.message(
              message: _actionNotice!,
              variant: AppFormInformationVariant.warning,
            ),
            SizedBox(height: theme.spacing.md),
          ],
          AppUserAccessPanel(
            roleGroups: _roleGroups,
            directPermissions: _directPermissions,
            effectivePermissions: _detail.effectivePermissions,
            canWrite: canMutate,
            isBusy: _saving,
            permissionsInitiallyExpanded: false,
            effectiveInitiallyExpanded: false,
            onAddRole: canMutate ? _addRole : null,
            onRemoveRole: canMutate ? _removeRole : null,
            onRemoveAllRoles: canMutate ? _removeAllRoles : null,
            onAddDirectPermission: canMutate ? _addDirectPermission : null,
            onRemoveDirectPermission: canMutate
                ? _removeDirectPermission
                : null,
            onRemoveAllDirectPermissions: canMutate
                ? _removeAllDirectPermissions
                : null,
          ),
          if (item.isDemo || item.isSystemCritical) ...<Widget>[
            SizedBox(height: theme.spacing.md),
            AppFormInformationBanner(
              title: item.isDemo
                  ? l10n.accessAdminUserDetailDemoAccountTitle
                  : l10n.accessAdminUserDetailSystemAccountTitle,
              message: item.isDemo
                  ? l10n.accessAdminUserDetailDemoAccountMessage
                  : l10n.accessAdminUserDetailSystemAccountMessage,
              variant: AppFormInformationVariant.warning,
              icon: item.isDemo
                  ? Icons.science_outlined
                  : Icons.admin_panel_settings_outlined,
            ),
          ],
        ],
      ),
      actions: <Widget>[
        if (canMutate) ...<Widget>[
          AppButton.primary(
            leadingIcon: Icons.edit_outlined,
            label: l10n.accessAdminEditUserAction,
            onPressed: _saving ? null : widget.onEdit,
          ),
          AppButton.secondary(
            leadingIcon: item.status == 'ACTIVE'
                ? Icons.person_off_outlined
                : Icons.person_outline,
            label: item.status == 'ACTIVE'
                ? l10n.accessAdminDeactivateAction
                : l10n.accessAdminActivateAction,
            isLoading: _saving,
            onPressed: _saving ? null : _toggleStatus,
          ),
          if (canResetCredentials)
            AppButton.secondary(
              leadingIcon: Icons.lock_reset_outlined,
              label: l10n.accessAdminResetCredentialsAction,
              onPressed: _saving ? null : _resetCredentials,
            ),
          if (widget.canDeleteProtected || !item.isSystemCritical)
            AppButton.secondary(
              leadingIcon: Icons.delete_outline,
              label: l10n.accessAdminDeleteUserAction,
              color: colorScheme.error,
              onPressed: _saving ? null : widget.onDelete,
            ),
        ],
        AppButton.secondary(
          label: l10n.commonCloseActionLabel,
          leadingIcon: Icons.close,
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// Maps existing direct permissions onto catalog lookup option ids for the picker.
Set<String> _resolveDirectPermissionOptionIds({
  required List<AccessAdminPermissionRef> directs,
  required List<AccessAdminLookupOption> permissionLookups,
}) {
  final Map<String, String> idByLookupId = <String, String>{
    for (final AccessAdminLookupOption option in permissionLookups)
      option.id: option.id,
  };
  final Map<String, String> idByName = <String, String>{
    for (final AccessAdminLookupOption option in permissionLookups)
      option.label: option.id,
  };
  final Set<String> resolved = <String>{};

  for (final AccessAdminPermissionRef permission in directs) {
    final List<String> candidates = <String>[
      permission.mutationId,
      permission.id,
      permission.name,
      if (permission.resourceUuid != null) permission.resourceUuid!,
    ];
    String? matched;
    for (final String candidate in candidates) {
      final String trimmed = candidate.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      matched = idByLookupId[trimmed] ?? idByName[trimmed];
      if (matched != null) {
        break;
      }
    }
    if (matched != null) {
      resolved.add(matched);
    } else if (permission.mutationId.trim().isNotEmpty) {
      resolved.add(permission.mutationId.trim());
    }
  }

  return resolved;
}

String? _userDetailDisplayName(AccessAdminItem item) {
  for (final String? candidate in <String?>[
    item.displayName,
    item.profileName,
    item.name,
    item.title,
  ]) {
    final String value = (candidate ?? '').trim();
    if (value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

class _UserDetailAccountFields extends StatelessWidget {
  const _UserDetailAccountFields({required this.item});

  final AccessAdminItem item;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    final String? displayName = _userDetailDisplayName(item);
    final String? email = item.email?.trim();
    final String? phone = item.phone?.trim();
    final String? position = item.positionTitle?.trim();
    final String? status = item.status?.trim();
    final String displayId = item.effectiveDisplayId.trim();
    final String? tenant = item.tenantId == null
        ? null
        : (item.tenantName?.trim().isNotEmpty == true
              ? item.tenantName!.trim()
              : item.tenantId!.trim());
    final String? facility = item.facilityId == null
        ? null
        : (item.facilityName?.trim().isNotEmpty == true
              ? item.facilityName!.trim()
              : item.facilityId!.trim());

    return AppInfoSheetGrid(
      emptyValue: l10n.profileUnknownValue,
      items: <AppInfoSheetItem>[
        if (displayName != null)
          AppInfoSheetItem(
            label: l10n.accessAdminColumnName,
            value: displayName,
          ),
        if (displayId.isNotEmpty)
          AppInfoSheetItem(
            label: l10n.accessAdminColumnId,
            value: displayId,
            copyable: true,
            copyTooltip: l10n.copyIdentifierAction,
            copiedMessage: l10n.identifierCopiedMessage,
          ),
        if (email != null && email.isNotEmpty)
          AppInfoSheetItem(
            label: l10n.accessAdminEmailLabel,
            value: email,
          ),
        if (phone != null && phone.isNotEmpty)
          AppInfoSheetItem(
            label: l10n.accessAdminPhoneLabel,
            value: phone,
          ),
        if (status != null && status.isNotEmpty)
          AppInfoSheetItem(
            label: l10n.accessAdminStatusLabel,
            value: status,
          ),
        if (position != null && position.isNotEmpty)
          AppInfoSheetItem(
            label: l10n.accessAdminPositionLabel,
            value: position,
          ),
        if (tenant != null && tenant.isNotEmpty)
          AppInfoSheetItem(
            label: l10n.settingsWorkspaceTenantLabel,
            value: tenant,
          ),
        if (facility != null && facility.isNotEmpty)
          AppInfoSheetItem(
            label: l10n.settingsWorkspaceFacilityLabel,
            value: facility,
          ),
      ],
    );
  }
}
