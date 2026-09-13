import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/permissions/permission_providers.dart';
import 'package:hosspi_hms/core/realtime/realtime_event_groups.dart';
import 'package:hosspi_hms/core/realtime/realtime_message.dart';
import 'package:hosspi_hms/features/access_admin/data/repositories/access_admin_repository_impl.dart';
import 'package:hosspi_hms/features/access_admin/domain/entities/access_admin_entities.dart';
import 'package:hosspi_hms/features/access_admin/domain/repositories/access_admin_repository.dart';
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

/// Platform setup tab: pending self-registrations awaiting Pro trial activation.
class ManageSubscriptionApprovalsPanel extends ConsumerStatefulWidget {
  const ManageSubscriptionApprovalsPanel({
    super.key,
    this.onListTotalChanged,
  });

  final ValueChanged<int>? onListTotalChanged;

  @override
  ConsumerState<ManageSubscriptionApprovalsPanel> createState() =>
      _ManageSubscriptionApprovalsPanelState();
}

class _ManageSubscriptionApprovalsPanelState
    extends ConsumerState<ManageSubscriptionApprovalsPanel> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  PlatformManagementListSync? _realtimeSync;

  bool _loading = true;
  bool _loadingMore = false;
  bool _mutating = false;
  AppFailure? _failure;
  AppPageRequest _pageRequest = PlatformAdminListConfig.initialPageRequest;
  int _totalItemCount = 0;
  List<AccessAdminItem> _items = const <AccessAdminItem>[];

  AccessAdminRepository get _repository =>
      ref.read(accessAdminRepositoryProvider);

  AccessAdminWorkspaceQuery get _listQuery => AccessAdminWorkspaceQuery(
    panel: AccessAdminPanel.registrations,
    resource: AccessAdminResource.registrationFollowUps,
    search: _searchController.text.trim(),
    pageRequest: _pageRequest,
    allTenants: true,
    allFacilities: true,
  );

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    unawaited(_reload(resetPage: true));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _realtimeSync ??= PlatformManagementListSync(
      ref: ref,
      events: RealtimeEventGroups.platformAdmin,
      onMutated: () {},
      reload: ({bool silent = false, RealtimeMessage? message}) async {
        await _reload(resetPage: false, silent: silent);
      },
    )..attach();
  }

  @override
  void dispose() {
    _realtimeSync?.dispose();
    _searchDebounce?.cancel();
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      unawaited(_reload(resetPage: true, silent: _items.isNotEmpty));
    });
  }

  Future<void> _reload({
    required bool resetPage,
    bool silent = false,
  }) async {
    if (resetPage) {
      _pageRequest = _pageRequest.first();
    }
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _loadingMore = false;
        _failure = null;
      });
    }

    final Result<AccessAdminWorkspaceData> result = await _repository
        .getWorkspace(_listQuery);

    if (!mounted) {
      return;
    }
    result.when(
      success: (AccessAdminWorkspaceData data) {
        setState(() {
          _loading = false;
          _loadingMore = false;
          _failure = null;
          _items = data.page.items;
          _totalItemCount = data.page.totalItemCount ?? data.page.items.length;
        });
        widget.onListTotalChanged?.call(_totalItemCount);
      },
      failure: (AppFailure loadFailure) {
        setState(() {
          _loading = false;
          _loadingMore = false;
          _failure = loadFailure;
          if (!silent) {
            _items = const <AccessAdminItem>[];
          }
        });
      },
    );
  }

  Future<void> _onPageChanged(AppPageRequest request) async {
    final AppPageRequest previous = _pageRequest;
    _pageRequest = request;
    final bool silent = _items.isNotEmpty;
    if (silent && mounted) {
      setState(() {
        _loadingMore = true;
        _failure = null;
      });
    }
    await _reload(resetPage: false, silent: silent);
    if (!mounted) {
      return;
    }
    if (_failure != null && silent) {
      setState(() {
        _pageRequest = previous;
        _loadingMore = false;
      });
    }
  }

  Future<void> _approve(AccessAdminItem item) async {
    if (_mutating) {
      return;
    }
    final AppLocalizations l10n = context.l10n;
    final String subject = item.title.isEmpty
        ? (item.email ?? item.effectiveDisplayId)
        : item.title;
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (_) => AppConfirmActionDialog(
        title: l10n.tenantFacilitySubscriptionApprovalsApproveTitle,
        body: l10n.tenantFacilitySubscriptionApprovalsApproveBody(subject),
        submitLabel: l10n.accessAdminApproveRegistrationAction,
        submitLeadingIcon: Icons.check_circle_outline,
        onConfirm: () async => null,
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _mutating = true);
    final Result<void> result = await _repository.approveRegistration(
      item.mutationId,
    );
    if (!mounted) {
      return;
    }
    result.when(
      success: (_) {
        setState(() => _mutating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.tenantFacilitySubscriptionApprovalsApproveSuccess,
            ),
          ),
        );
        unawaited(_reload(resetPage: false, silent: true));
      },
      failure: (AppFailure failure) {
        setState(() {
          _mutating = false;
          _failure = failure;
        });
      },
    );
  }

  Future<void> _reject(AccessAdminItem item) async {
    if (_mutating) {
      return;
    }
    final AppLocalizations l10n = context.l10n;
    final String subject = item.title.isEmpty
        ? (item.email ?? item.effectiveDisplayId)
        : item.title;
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (_) => AppConfirmActionDialog(
        title: l10n.tenantFacilitySubscriptionApprovalsRejectTitle,
        body: l10n.tenantFacilitySubscriptionApprovalsRejectBody(subject),
        submitLabel: l10n.accessAdminRejectRegistrationAction,
        submitLeadingIcon: Icons.block_outlined,
        destructive: true,
        onConfirm: () async => null,
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _mutating = true);
    final Result<void> result = await _repository.rejectRegistration(
      item.mutationId,
    );
    if (!mounted) {
      return;
    }
    result.when(
      success: (_) {
        setState(() => _mutating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.tenantFacilitySubscriptionApprovalsRejectSuccess,
            ),
          ),
        );
        unawaited(_reload(resetPage: false, silent: true));
      },
      failure: (AppFailure failure) {
        setState(() {
          _mutating = false;
          _failure = failure;
        });
      },
    );
  }

  Future<void> _openDetail(AccessAdminItem item) async {
    final bool? activated = await showAppDialog<bool>(
      context: context,
      builder: (_) => _SubscriptionApprovalDetailDialog(
        item: item,
        onApprove: () => _approve(item),
        onReject: () => _reject(item),
        mutating: _mutating,
      ),
    );
    if (activated == true && mounted) {
      unawaited(_reload(resetPage: false, silent: true));
    }
  }

  AppPage<AccessAdminItem> get _currentPage => AppPage<AccessAdminItem>(
    items: _items,
    request: _pageRequest,
    totalItemCount: _totalItemCount,
  );

  List<AppListTableColumn<AccessAdminItem>> _columns(AppLocalizations l10n) {
    return <AppListTableColumn<AccessAdminItem>>[
      AppListTableColumn<AccessAdminItem>(
        id: 'admin',
        label: l10n.tenantFacilitySubscriptionApprovalsAdminColumn,
        sortComparator: (AccessAdminItem left, AccessAdminItem right) =>
            appListTableCompareText(left.title, right.title),
        exportValue: (AccessAdminItem item) =>
            item.title.isEmpty ? '—' : item.title,
        cellBuilder: (_, AccessAdminItem item) => tenantFacilitySetupAtomicCell(
          item.title.isEmpty ? '—' : item.title,
        ),
      ),
      AppListTableColumn<AccessAdminItem>(
        id: 'facility',
        label: l10n.tenantFacilitySubscriptionApprovalsFacilityColumn,
        sortComparator: (AccessAdminItem left, AccessAdminItem right) =>
            appListTableCompareText(
              left.facilityName ?? left.subtitle,
              right.facilityName ?? right.subtitle,
            ),
        exportValue: (AccessAdminItem item) =>
            item.facilityName ?? item.subtitle ?? item.tenantName ?? '—',
        cellBuilder: (_, AccessAdminItem item) => tenantFacilitySetupAtomicCell(
          item.facilityName ?? item.subtitle ?? item.tenantName ?? '—',
        ),
      ),
      AppListTableColumn<AccessAdminItem>(
        id: 'email',
        label: l10n.accessAdminEmailLabel,
        sortComparator: (AccessAdminItem left, AccessAdminItem right) =>
            appListTableCompareText(left.email, right.email),
        exportValue: (AccessAdminItem item) => item.email ?? '—',
        cellBuilder: (_, AccessAdminItem item) =>
            tenantFacilitySetupAtomicCell(item.email ?? '—'),
      ),
      AppListTableColumn<AccessAdminItem>(
        id: 'phone',
        label: l10n.accessAdminPhoneLabel,
        sortComparator: (AccessAdminItem left, AccessAdminItem right) =>
            appListTableCompareText(left.phone, right.phone),
        exportValue: (AccessAdminItem item) => item.phone ?? '—',
        cellBuilder: (_, AccessAdminItem item) =>
            tenantFacilitySetupAtomicCell(item.phone ?? '—'),
      ),
      AppListTableColumn<AccessAdminItem>(
        id: 'actions',
        label: l10n.tenantFacilitySubscriptionApprovalsActionsColumn,
        alwaysVisible: true,
        exportable: false,
        cellBuilder: (BuildContext context, AccessAdminItem item) {
          return AppButton.tertiary(
            label: l10n.accessAdminApproveRegistrationAction,
            leadingIcon: Icons.check_circle_outline,
            onPressed: _mutating ? null : () => unawaited(_approve(item)),
          );
        },
      ),
    ];
  }

  List<AppListTableColumn<AccessAdminItem>> _optionalColumns(
    AppLocalizations l10n,
  ) {
    return <AppListTableColumn<AccessAdminItem>>[
      AppListTableColumn<AccessAdminItem>(
        id: 'tenant',
        label: l10n.tenantFacilitySetupTabTenant,
        exportValue: (AccessAdminItem item) => item.tenantName ?? '—',
        cellBuilder: (_, AccessAdminItem item) =>
            tenantFacilitySetupAtomicCell(item.tenantName ?? '—'),
      ),
      AppListTableColumn<AccessAdminItem>(
        id: 'status',
        label: l10n.accessAdminColumnStatus,
        exportValue: (AccessAdminItem item) => item.status ?? '—',
        cellBuilder: (_, AccessAdminItem item) =>
            tenantFacilitySetupAtomicCell(item.status ?? '—'),
      ),
      AppListTableColumn<AccessAdminItem>(
        id: 'id',
        label: l10n.accessAdminColumnId,
        exportValue: (AccessAdminItem item) => item.effectiveDisplayId,
        cellBuilder: (_, AccessAdminItem item) =>
            tenantFacilitySetupAtomicCell(item.effectiveDisplayId),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.tenantFacilitySubscriptionApprovalsIntro,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: theme.spacing.md),
        if (_failure != null) ...<Widget>[
          AppFormInformationBanner.failure(
            context: context,
            failure: _failure!,
            onRetry: () => unawaited(_reload(resetPage: true)),
          ),
          SizedBox(height: theme.spacing.md),
        ],
        Expanded(
          child: AppListTable<AccessAdminItem>(
            page: _currentPage,
            isLoading: _loading || _loadingMore,
            onRowSelected: _mutating
                ? null
                : (AccessAdminItem item) => unawaited(_openDetail(item)),
            onPageChanged: _onPageChanged,
            previousPageLabel: l10n.hrPreviousPageLabel,
            nextPageLabel: l10n.hrNextPageLabel,
            pageLabelBuilder: (AppPage<AccessAdminItem> page) {
              if (_loading) {
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
            emptyBuilder: (_) => AppWorkspaceStatePanel.empty(
              title: l10n.tenantFacilitySubscriptionApprovalsEmptyTitle,
              body: l10n.tenantFacilitySubscriptionApprovalsEmpty,
            ),
            columns: _columns(l10n),
            columnChoices: _optionalColumns(l10n),
            columnVisibilityStorageKey:
                'setup_subscription_approvals_columns_v2',
            columnVisibilityLabel: l10n.commonTableSettingsActionLabel,
            columnVisibilityTitle: l10n.commonTableSettingsTitle,
            columnVisibilityApplyLabel: l10n.receptionApplyColumnsAction,
            columnVisibilityResetLabel: l10n.receptionResetColumnsAction,
            columnVisibilityCloseLabel: l10n.commonCloseActionLabel,
            canExport: canExportTenantFacilitySetup(
              ref.watch(appAccessPolicyProvider),
            ),
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
            canPrint: canPrintTenantFacilitySetup(
              ref.watch(appAccessPolicyProvider),
            ),
            printLabel: l10n.commonPrintActionLabel,
            onPrint: (List<AccessAdminItem> matching) =>
                printTenantFacilitySetupListTable<AccessAdminItem>(
              ref: ref,
              context: context,
              title: l10n.tenantFacilitySetupTabSubscriptionApprovals,
              columns: <AppListTableColumn<AccessAdminItem>>[
                ..._columns(l10n),
                ..._optionalColumns(l10n),
              ],
              items: matching,
              emptyText: l10n.tenantFacilitySubscriptionApprovalsEmpty,
            ),
            goToTopLabel: l10n.commonGoToTopActionLabel,
            loadingMoreLabel: l10n.commonLoadingMoreLabel,
            allRowsLoadedLabel: l10n.commonAllRowsLoadedLabel,
            exportConfig: AppListTableExportConfig<AccessAdminItem>(
              fileNameStem: 'setup_subscription_approvals',
              dateOf: (_) => null,
              sheetName: l10n.tenantFacilitySetupTabSubscriptionApprovals,
              enableDateFilter: false,
              dateFromLabel: l10n.commonTableExportDateFromLabel,
              dateToLabel: l10n.commonTableExportDateToLabel,
            ),
            search: AppListTableSearch<AccessAdminItem>(
              controller: _searchController,
              semanticLabel: l10n.tenantFacilitySubscriptionApprovalsSearchHint,
              hintText: l10n.tenantFacilitySubscriptionApprovalsSearchHint,
              matcher: (_, _) => true,
              onSubmitted: (_) => unawaited(_reload(resetPage: true)),
              onClear: () => unawaited(_reload(resetPage: true)),
              enableDateFilter: false,
            ),
            mobileItemBuilder: (BuildContext context, AccessAdminItem item) {
              return AppListTableMobileItem(
                title: item.title.isEmpty
                    ? (item.email ?? item.effectiveDisplayId)
                    : item.title,
                caption: item.facilityName ?? item.subtitle ?? '—',
                meta: <AppListTableMobileMeta>[
                  if ((item.email ?? '').isNotEmpty)
                    AppListTableMobileMeta(
                      label: item.email!,
                      icon: Icons.email_outlined,
                    ),
                  if ((item.phone ?? '').isNotEmpty)
                    AppListTableMobileMeta(
                      label: item.phone!,
                      icon: Icons.phone_outlined,
                    ),
                ],
                trailing: AppButton.tertiary(
                  label: l10n.accessAdminApproveRegistrationAction,
                  onPressed: _mutating
                      ? null
                      : () => unawaited(_approve(item)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SubscriptionApprovalDetailDialog extends StatelessWidget {
  static const String _emptyValue = '—';

  const _SubscriptionApprovalDetailDialog({
    required this.item,
    required this.onApprove,
    required this.onReject,
    required this.mutating,
  });

  final AccessAdminItem item;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;
  final bool mutating;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);

    final String headline = item.title.isEmpty
        ? (item.email ?? item.effectiveDisplayId)
        : item.title;
    final String? contextLabel =
        item.facilityName ?? item.subtitle ?? item.tenantName;

    return AppDialog(
      title: Text(l10n.tenantFacilitySubscriptionApprovalsDetailTitle),
      icon: const Icon(Icons.verified_user_outlined),
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: appCollapsibleSectionSpacing(context, <Widget>[
          AppCollapsibleSection(
            titleIcon: Icons.apartment_outlined,
            eyebrow: item.effectiveDisplayId,
            title: headline,
            subtitle: contextLabel,
            collapsible: false,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppStatusBadge(label: item.status ?? _emptyValue),
            ),
          ),
          AppCollapsibleSection(
            title: l10n.tenantFacilitySubscriptionApprovalsContactsSection,
            titleIcon: Icons.contact_mail_outlined,
            description:
                l10n.tenantFacilitySubscriptionApprovalsContactsDescription,
            child: AppInfoSheetGrid(
              emptyValue: _emptyValue,
              items: <AppInfoSheetItem>[
                AppInfoSheetItem(
                  label: l10n.authAdminNameLabel,
                  value: item.title,
                ),
                AppInfoSheetItem(
                  label: l10n.accessAdminEmailLabel,
                  value: item.email,
                ),
                AppInfoSheetItem(
                  label: l10n.accessAdminPhoneLabel,
                  value: item.phone,
                ),
              ],
            ),
          ),
          AppCollapsibleSection(
            title: l10n.tenantFacilitySubscriptionApprovalsFacilitySection,
            titleIcon: Icons.local_hospital_outlined,
            description:
                l10n.tenantFacilitySubscriptionApprovalsFacilityDescription,
            child: AppInfoSheetGrid(
              emptyValue: _emptyValue,
              items: <AppInfoSheetItem>[
                AppInfoSheetItem(
                  label:
                      l10n.tenantFacilitySubscriptionApprovalsFacilityColumn,
                  value: item.facilityName ?? item.subtitle,
                ),
                AppInfoSheetItem(
                  label: l10n.tenantFacilitySetupTabTenant,
                  value: item.tenantName,
                ),
                AppInfoSheetItem(
                  label: l10n.accessAdminColumnId,
                  value: item.effectiveDisplayId,
                  copyable: true,
                  copyTooltip: l10n.copyIdentifierAction,
                  copiedMessage: l10n.identifierCopiedMessage,
                  copyPlaceholderValues: const <String>{_emptyValue},
                ),
                AppInfoSheetItem(
                  label: l10n.accessAdminColumnStatus,
                  value: item.status,
                ),
              ],
            ),
          ),
          AppCollapsibleSection(
            title: l10n.tenantFacilitySubscriptionApprovalsPlanSection,
            titleIcon: Icons.workspace_premium_outlined,
            description: l10n.tenantFacilitySubscriptionApprovalsPlanDescription,
            collapsible: false,
            child: Text(
              l10n.tenantFacilitySubscriptionApprovalsPlanBody,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          AppCollapsibleSection(
            title: l10n.tenantFacilitySubscriptionApprovalsActionsSection,
            titleIcon: Icons.bolt_outlined,
            collapsible: false,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool wide = constraints.maxWidth >= 420;
                final List<Widget> buttons = <Widget>[
                  AppButton(
                    label: l10n.accessAdminApproveRegistrationAction,
                    leadingIcon: Icons.check_circle_outline,
                    onPressed: mutating
                        ? null
                        : () async {
                            await onApprove();
                            if (context.mounted) {
                              Navigator.of(context).pop(true);
                            }
                          },
                  ),
                  AppButton.secondary(
                    label: l10n.accessAdminRejectRegistrationAction,
                    leadingIcon: Icons.block_outlined,
                    onPressed: mutating
                        ? null
                        : () async {
                            await onReject();
                            if (context.mounted) {
                              Navigator.of(context).pop(true);
                            }
                          },
                  ),
                ];
                if (wide) {
                  return Row(
                    children: <Widget>[
                      Expanded(child: buttons[0]),
                      SizedBox(width: theme.spacing.sm),
                      Expanded(child: buttons[1]),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    buttons[0],
                    SizedBox(height: theme.spacing.sm),
                    buttons[1],
                  ],
                );
              },
            ),
          ),
        ]),
      ),
      actions: <Widget>[
        AppButton.tertiary(
          label: l10n.commonCloseActionLabel,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
