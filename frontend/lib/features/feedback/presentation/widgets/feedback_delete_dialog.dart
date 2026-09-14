import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/utils/app_formatters.dart';
import 'package:hosspi_hms/features/feedback/data/repositories/feedback_repository_impl.dart';
import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';
import 'package:hosspi_hms/features/feedback/domain/repositories/feedback_repository.dart';
import 'package:hosspi_hms/features/feedback/presentation/feedback_labels.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/actions/app_action_dialogs.dart';
import 'package:hosspi_hms/shared/components/components.dart';
import 'package:hosspi_hms/shared/data/app_pagination.dart';
import 'package:hosspi_hms/shared/layout/app_workspace.dart';

/// Opens Clear feedback. Resolves to how many records were deleted, or null
/// when the dialog closes without deleting.
Future<int?> showFeedbackDeleteDialog({required BuildContext context}) {
  return showAppDialog<int>(
    context: context,
    builder: (_) => const FeedbackDeleteDialog(),
  );
}

/// [AppSearchBarFilterValue] keys for the feedback filters.
abstract final class FeedbackDeleteFilterKeys {
  static const String category = 'category';
  static const String submitterType = 'submitter_type';
  static const String deviceType = 'device_type';
  static const String platform = 'platform';
}

/// Clear feedback: platform owners and platform admins pick stored feedback
/// and delete it permanently.
///
/// Feedback loads a page at a time from the server and narrows by search, a
/// submission date range, feedback type, submitter, device type, and platform.
/// Records can be picked one at a time, a page at a time, or every record
/// matching the current search and filters at once, across pages.
class FeedbackDeleteDialog extends ConsumerStatefulWidget {
  const FeedbackDeleteDialog({super.key});

  /// The header checkbox that selects every record on the page.
  static const Key pageCheckboxKey = ValueKey<String>(
    'feedback-delete-select-page',
  );

  static Key rowCheckboxKey(String referenceId) {
    return ValueKey<String>('feedback-delete-select-$referenceId');
  }

  @override
  ConsumerState<FeedbackDeleteDialog> createState() =>
      _FeedbackDeleteDialogState();
}

class _FeedbackDeleteDialogState extends ConsumerState<FeedbackDeleteDialog> {
  static const Duration _searchDebounce = Duration(milliseconds: 350);
  static const String _emptyCell = '—';

  final TextEditingController _searchController = TextEditingController();

  // Checkboxes listen to this, so they repaint on every selection change even
  // when the table keeps its rows and header mounted.
  final ValueNotifier<int> _selectionRevision = ValueNotifier<int>(0);
  final Set<String> _selectedIds = <String>{};
  Timer? _searchTimer;
  String _appliedSearch = '';
  AppSearchBarFilterValue _filterValue = AppSearchBarFilterValue.empty;
  AppPageRequest _request = const AppPageRequest();
  AppPage<FeedbackRecord>? _page;
  AppFailure? _loadFailure;
  bool _isLoading = true;
  bool _allMatchingSelected = false;
  int _loadGeneration = 0;

  List<FeedbackRecord> get _pageItems =>
      _page?.items ?? const <FeedbackRecord>[];

  int get _matchingCount => _page?.totalItemCount ?? _pageItems.length;

  int get _selectedCount =>
      _allMatchingSelected ? _matchingCount : _selectedIds.length;

  FeedbackFilters get _filters {
    final AppSearchBarFilterValue value = _filterValue;
    final String? submitterType = value.option(
      FeedbackDeleteFilterKeys.submitterType,
    );

    return FeedbackFilters(
      search: _appliedSearch,
      categories: value
          .optionsFor(FeedbackDeleteFilterKeys.category)
          .map(FeedbackCategory.fromApiValue)
          .toSet(),
      submitterType: submitterType == null
          ? null
          : FeedbackSubmitterType.fromApiValue(submitterType),
      deviceTypes: value
          .optionsFor(FeedbackDeleteFilterKeys.deviceType)
          .map(FeedbackDeviceType.fromApiValue)
          .whereType<FeedbackDeviceType>()
          .toSet(),
      platforms: value.optionsFor(FeedbackDeleteFilterKeys.platform),
      submittedFrom: value.dateFrom,
      submittedTo: value.dateTo,
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load(_request));
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    _selectionRevision.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = context.l10n;
    final AppFailure? loadFailure = _loadFailure;

    return AppDialog(
      title: Text(l10n.feedbackDeleteDialogTitle),
      icon: const Icon(AppActionIcons.delete),
      maxWidth: 1200,
      pinActionsToBottom: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            l10n.feedbackDeleteDialogBody,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: theme.spacing.sm),
          if (loadFailure != null) ...<Widget>[
            AppFormInformationBanner.failure(
              context: context,
              failure: loadFailure,
            ),
            SizedBox(height: theme.spacing.sm),
          ],
          Semantics(
            liveRegion: true,
            child: Text(
              _allMatchingSelected
                  ? l10n.feedbackAllMatchingSelected(_matchingCount)
                  : l10n.feedbackSelectedCount(_selectedIds.length),
              style: theme.textTheme.titleSmall,
            ),
          ),
          SizedBox(height: theme.spacing.xs),
          Expanded(child: _buildTable(context, l10n)),
        ],
      ),
      actions: <Widget>[
        AppButton.close(
          label: l10n.commonCloseActionLabel,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        AppButton.primary(
          label: l10n.feedbackDeleteSelectedAction,
          leadingIcon: AppActionIcons.delete,
          color: theme.colorScheme.error,
          onPressed: !_isLoading && _selectedCount > 0
              ? () => unawaited(_confirmDelete())
              : null,
        ),
      ],
    );
  }

  Widget _buildTable(BuildContext context, AppLocalizations l10n) {
    final Locale locale = Localizations.localeOf(context);
    final AppPage<FeedbackRecord> page =
        _page ??
        AppPage<FeedbackRecord>(
          items: const <FeedbackRecord>[],
          request: _request,
          totalItemCount: 0,
        );

    return AppListTable<FeedbackRecord>(
      page: page,
      paginationMode: AppListTablePaginationMode.buttons,
      onPageChanged: (AppPageRequest request) => unawaited(_load(request)),
      pageLabelBuilder: (AppPage<FeedbackRecord> value) {
        final int total = value.totalItemCount ?? value.items.length;
        if (value.items.isEmpty || total == 0) {
          return '';
        }
        return l10n.feedbackPageRangeLabel(
          value.firstItemNumber,
          value.lastItemNumber,
          total,
        );
      },
      previousPageLabel: l10n.feedbackPreviousPageLabel,
      nextPageLabel: l10n.feedbackNextPageLabel,
      isLoading: _isLoading,
      itemKeyBuilder: (FeedbackRecord record) =>
          ValueKey<String>(record.referenceId),
      onRowSelected: (FeedbackRecord record) =>
          _setSelected(record, !_isSelected(record)),
      showRowNumbers: false,
      enableExport: false,
      tableHorizontalMargin: 0,
      columnVisibilityLabel: l10n.commonTableSettingsActionLabel,
      columnVisibilityTitle: l10n.commonTableSettingsTitle,
      columnVisibilityApplyLabel: l10n.receptionApplyColumnsAction,
      columnVisibilityResetLabel: l10n.receptionResetColumnsAction,
      columnVisibilityCloseLabel: l10n.commonCloseActionLabel,
      search: AppListTableSearch<FeedbackRecord>(
        controller: _searchController,
        semanticLabel: l10n.feedbackSearchLabel,
        hintText: l10n.feedbackSearchHint,
        // The server has already searched; show every row it returns.
        matcher: (_, _) => true,
        onChanged: _handleSearchChanged,
        onSubmitted: _applySearch,
        onClear: () => _applySearch(''),
        showAdvancedFilterButton: true,
        advancedFilterButtonLabel: l10n.commonFilterActionLabel,
        advancedFilterTitle: l10n.feedbackFiltersTitle,
        advancedFilterApplyLabel: l10n.feedbackApplyFiltersAction,
        advancedFilterResetLabel: l10n.feedbackClearFiltersAction,
        advancedFilterCloseLabel: l10n.commonCloseActionLabel,
        dateFilterLabel: l10n.feedbackSubmittedDateLabel,
        dateFromLabel: l10n.feedbackSubmittedFromLabel,
        dateToLabel: l10n.feedbackSubmittedToLabel,
        invalidDateMessage: l10n.feedbackInvalidDateMessage,
        lastDate: DateTime.now(),
        filterGroups: _filterGroups(l10n),
        filterValue: _filterValue,
        hasActiveFilters: _filterValue.isActive,
        onFilterChanged: _applyFilters,
        trailingActions: _selectionActions(l10n),
      ),
      loadingBuilder: (_) => AppWorkspaceStatePanel.loading(
        title: l10n.feedbackLoadingTitle,
        body: l10n.feedbackLoadingBody,
      ),
      emptyBuilder: (_) => _loadFailure == null
          ? AppWorkspaceStatePanel.empty(
              icon: Icons.feedback_outlined,
              title: l10n.feedbackEmptyTitle,
              body: l10n.feedbackEmptyBody,
            )
          : AppWorkspaceStatePanel.error(
              title: l10n.feedbackLoadErrorTitle,
              body: l10n.feedbackLoadErrorBody,
              action: AppButton.secondary(
                label: l10n.feedbackRetryAction,
                leadingIcon: Icons.refresh,
                onPressed: () => unawaited(_load(_request)),
              ),
            ),
      columns: _columns(l10n, locale),
      mobileItemBuilder: (BuildContext context, FeedbackRecord record) =>
          _mobileItem(l10n, locale, record),
    );
  }

  List<AppListTableColumn<FeedbackRecord>> _columns(
    AppLocalizations l10n,
    Locale locale,
  ) {
    return <AppListTableColumn<FeedbackRecord>>[
      AppListTableColumn<FeedbackRecord>(
        id: 'select',
        label: '',
        alwaysVisible: true,
        sortable: false,
        exportable: false,
        fixedWidth: 48,
        headerBuilder: (_) => _selectionListener(() {
          final List<FeedbackRecord> items = _pageItems;
          final bool allOnPage = items.isNotEmpty && items.every(_isSelected);
          return Center(
            child: Checkbox(
              key: FeedbackDeleteDialog.pageCheckboxKey,
              tristate: true,
              value: allOnPage ? true : (items.any(_isSelected) ? null : false),
              semanticLabel: l10n.feedbackSelectPageLabel,
              onChanged: items.isEmpty || _isLoading
                  ? null
                  : (_) => _setPageSelected(!allOnPage),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          );
        }),
        cellBuilder: (_, FeedbackRecord record) =>
            Center(child: _recordCheckbox(l10n, record)),
      ),
      // The table shows the first few columns by default; the rest are one
      // tap away in Settings.
      _textColumn(
        id: 'submitted_at',
        label: l10n.feedbackSubmittedAtColumnLabel,
        preferredWidth: 180,
        value: (FeedbackRecord record) => _submittedAtText(record, locale),
      ),
      _textColumn(
        id: 'category',
        label: l10n.feedbackCategoryLabel,
        preferredWidth: 150,
        value: (FeedbackRecord record) =>
            feedbackCategoryLabel(l10n, record.category),
      ),
      _textColumn(
        id: 'details',
        label: l10n.feedbackMessageLabel,
        preferredWidth: 320,
        maxLines: 2,
        value: (FeedbackRecord record) => _orEmpty(record.messagePreview),
      ),
      _textColumn(
        id: 'submitted_by',
        label: l10n.feedbackSubmittedByLabel,
        preferredWidth: 220,
        value: (FeedbackRecord record) => _submitterText(l10n, record),
      ),
      _textColumn(
        id: 'reference',
        label: l10n.feedbackIdColumnLabel,
        preferredWidth: 130,
        value: (FeedbackRecord record) => record.referenceId,
      ),
      _textColumn(
        id: 'tenant',
        label: l10n.feedbackTenantColumnLabel,
        preferredWidth: 180,
        value: (FeedbackRecord record) => _orEmpty(record.tenantName),
      ),
      _textColumn(
        id: 'facility',
        label: l10n.feedbackFacilityColumnLabel,
        preferredWidth: 180,
        value: (FeedbackRecord record) => _orEmpty(record.facilityName),
      ),
      _textColumn(
        id: 'device_type',
        label: l10n.feedbackDeviceTypeLabel,
        preferredWidth: 120,
        value: (FeedbackRecord record) {
          final FeedbackDeviceType? deviceType = record.deviceType;
          return deviceType == null
              ? _emptyCell
              : feedbackDeviceTypeLabel(l10n, deviceType);
        },
      ),
      _textColumn(
        id: 'platform',
        label: l10n.feedbackPlatformLabel,
        preferredWidth: 110,
        value: (FeedbackRecord record) {
          final String? platform = record.platform;
          return platform == null
              ? _emptyCell
              : feedbackPlatformName(l10n, platform);
        },
      ),
      _textColumn(
        id: 'screen',
        label: l10n.feedbackRouteColumnLabel,
        preferredWidth: 220,
        value: (FeedbackRecord record) => _orEmpty(record.routePath),
      ),
    ];
  }

  AppListTableColumn<FeedbackRecord> _textColumn({
    required String id,
    required String label,
    required String Function(FeedbackRecord record) value,
    double? preferredWidth,
    int maxLines = 1,
  }) {
    return AppListTableColumn<FeedbackRecord>(
      id: id,
      label: label,
      // Sorting one page locally would misrepresent the whole list.
      sortable: false,
      preferredWidth: preferredWidth,
      cellBuilder: (_, FeedbackRecord record) => Text(
        value(record),
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _mobileItem(
    AppLocalizations l10n,
    Locale locale,
    FeedbackRecord record,
  ) {
    final DateTime? submittedAt = record.submittedAt;
    final FeedbackDeviceType? deviceType = record.deviceType;

    return AppListTableMobileItem(
      title: record.messagePreview.trim().isEmpty
          ? record.referenceId
          : record.messagePreview,
      caption:
          '${record.referenceId} · ${feedbackCategoryLabel(l10n, record.category)}',
      showAvatar: false,
      leading: _recordCheckbox(l10n, record),
      meta: <AppListTableMobileMeta>[
        if (submittedAt != null)
          AppListTableMobileMeta(
            label: AppFormatters.dateTime(submittedAt, locale),
            icon: Icons.schedule_outlined,
          ),
        AppListTableMobileMeta(
          label: _submitterText(l10n, record),
          icon: Icons.person_outline,
        ),
        if (deviceType != null)
          AppListTableMobileMeta(
            label: feedbackDeviceTypeLabel(l10n, deviceType),
            icon: Icons.devices_outlined,
          ),
      ],
    );
  }

  Widget _recordCheckbox(AppLocalizations l10n, FeedbackRecord record) {
    return _selectionListener(
      () => Checkbox(
        key: FeedbackDeleteDialog.rowCheckboxKey(record.referenceId),
        value: _isSelected(record),
        semanticLabel: l10n.feedbackSelectRowLabel(record.referenceId),
        onChanged: (bool? checked) => _setSelected(record, checked ?? false),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _selectionListener(Widget Function() builder) {
    return ValueListenableBuilder<int>(
      valueListenable: _selectionRevision,
      builder: (_, _, _) => builder(),
    );
  }

  List<AppSearchBarFilterGroup> _filterGroups(AppLocalizations l10n) {
    return <AppSearchBarFilterGroup>[
      AppSearchBarFilterGroup(
        key: FeedbackDeleteFilterKeys.category,
        label: l10n.feedbackCategoryLabel,
        allLabel: l10n.commonAllLabel,
        allowMultiple: true,
        choices: <AppSearchBarFilterChoice>[
          for (final FeedbackCategory category in FeedbackCategory.values)
            AppSearchBarFilterChoice(
              value: category.apiValue,
              label: feedbackCategoryLabel(l10n, category),
            ),
        ],
      ),
      AppSearchBarFilterGroup(
        key: FeedbackDeleteFilterKeys.submitterType,
        label: l10n.feedbackSubmittedByLabel,
        allLabel: l10n.feedbackFilterAnyLabel,
        choices: <AppSearchBarFilterChoice>[
          for (final FeedbackSubmitterType type in FeedbackSubmitterType.values)
            AppSearchBarFilterChoice(
              value: type.apiValue,
              label: feedbackSubmitterTypeLabel(l10n, type),
            ),
        ],
      ),
      AppSearchBarFilterGroup(
        key: FeedbackDeleteFilterKeys.deviceType,
        label: l10n.feedbackDeviceTypeLabel,
        allLabel: l10n.commonAllLabel,
        allowMultiple: true,
        choices: <AppSearchBarFilterChoice>[
          for (final FeedbackDeviceType type in FeedbackDeviceType.values)
            AppSearchBarFilterChoice(
              value: type.apiValue,
              label: feedbackDeviceTypeLabel(l10n, type),
            ),
        ],
      ),
      AppSearchBarFilterGroup(
        key: FeedbackDeleteFilterKeys.platform,
        label: l10n.feedbackPlatformLabel,
        allLabel: l10n.commonAllLabel,
        allowMultiple: true,
        choices: <AppSearchBarFilterChoice>[
          for (final String platform in feedbackPlatforms)
            AppSearchBarFilterChoice(
              value: platform,
              label: feedbackPlatformName(l10n, platform),
            ),
        ],
      ),
    ];
  }

  List<AppSearchBarAction> _selectionActions(AppLocalizations l10n) {
    final int matchingCount = _matchingCount;
    return <AppSearchBarAction>[
      if (matchingCount > 0 && !_allMatchingSelected)
        AppSearchBarAction(
          icon: Icons.select_all,
          label: l10n.feedbackSelectAllMatchingAction(matchingCount),
          onPressed: _isLoading ? null : _selectAllMatching,
        ),
      if (_selectedCount > 0)
        AppSearchBarAction(
          icon: Icons.deselect,
          label: l10n.commonClearSelectionActionLabel,
          onPressed: _clearSelection,
        ),
    ];
  }

  String _submittedAtText(FeedbackRecord record, Locale locale) {
    final DateTime? submittedAt = record.submittedAt;
    return submittedAt == null
        ? _emptyCell
        : AppFormatters.dateTime(submittedAt, locale);
  }

  String _submitterText(AppLocalizations l10n, FeedbackRecord record) {
    final String? identity = record.userEmail ?? record.userName;
    if (identity != null) {
      return identity;
    }
    return record.submitterType == FeedbackSubmitterType.anonymous
        ? l10n.feedbackSubmitterAnonymous
        : _emptyCell;
  }

  String _orEmpty(String? value) {
    final String text = value?.trim() ?? '';
    return text.isEmpty ? _emptyCell : text;
  }

  bool _isSelected(FeedbackRecord record) {
    return _allMatchingSelected || _selectedIds.contains(record.referenceId);
  }

  void _updateSelection(VoidCallback change) {
    setState(change);
    _selectionRevision.value += 1;
  }

  void _setSelected(FeedbackRecord record, bool selected) {
    _updateSelection(() {
      if (_allMatchingSelected) {
        // Deleting every match cannot skip records, so unticking one switches
        // to picking the rest of this page individually.
        _allMatchingSelected = false;
        _selectedIds.addAll(_pageItems.map(_referenceIdOf));
      }
      if (selected) {
        _selectedIds.add(record.referenceId);
      } else {
        _selectedIds.remove(record.referenceId);
      }
    });
  }

  void _setPageSelected(bool selected) {
    _updateSelection(() {
      _allMatchingSelected = false;
      final Iterable<String> ids = _pageItems.map(_referenceIdOf);
      if (selected) {
        _selectedIds.addAll(ids);
      } else {
        _selectedIds.removeAll(ids);
      }
    });
  }

  void _selectAllMatching() {
    _updateSelection(() {
      _allMatchingSelected = true;
      _selectedIds.clear();
    });
  }

  void _clearSelection() {
    _updateSelection(() {
      _allMatchingSelected = false;
      _selectedIds.clear();
    });
  }

  static String _referenceIdOf(FeedbackRecord record) => record.referenceId;

  void _handleSearchChanged(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(_searchDebounce, () => _applySearch(value));
  }

  void _applySearch(String value) {
    _searchTimer?.cancel();
    final String search = value.trim();
    if (!mounted || search == _appliedSearch) {
      return;
    }
    _appliedSearch = search;
    _reloadFromFirstPage();
  }

  void _applyFilters(AppSearchBarFilterValue value) {
    _filterValue = value;
    _reloadFromFirstPage();
  }

  /// New search or filter criteria change which records match, so selections
  /// made under the old criteria are dropped.
  void _reloadFromFirstPage() {
    _selectedIds.clear();
    _allMatchingSelected = false;
    unawaited(_load(_request.first()));
  }

  Future<void> _load(AppPageRequest request) async {
    final int generation = ++_loadGeneration;
    final FeedbackFilters filters = _filters;
    _updateSelection(() {
      _request = request;
      _isLoading = true;
      _loadFailure = null;
    });

    final Result<AppPage<FeedbackRecord>> result = await ref
        .read(feedbackRepositoryProvider)
        .fetchFeedbackPage(filters: filters, request: request);
    if (!mounted || generation != _loadGeneration) {
      return;
    }

    switch (result) {
      case ResultSuccess<AppPage<FeedbackRecord>>(
        value: final AppPage<FeedbackRecord> page,
      ):
        _updateSelection(() {
          _page = page;
          _isLoading = false;
        });
      case ResultFailure<AppPage<FeedbackRecord>>(
        failure: final AppFailure failure,
      ):
        _updateSelection(() {
          _page = null;
          _loadFailure = failure;
          _isLoading = false;
        });
    }
  }

  Future<void> _confirmDelete() async {
    final AppLocalizations l10n = context.l10n;
    final FeedbackRepository repository = ref.read(feedbackRepositoryProvider);
    // Snapshot the selection: the confirmation deletes exactly what it names.
    final bool deletesAllMatching = _allMatchingSelected;
    final FeedbackFilters filters = _filters;
    final Set<String> referenceIds = Set<String>.of(_selectedIds);
    final int count = _selectedCount;
    int deletedCount = 0;

    final bool? deleted = await showAppDialog<bool>(
      context: context,
      builder: (_) => AppConfirmActionDialog(
        title: l10n.feedbackDeleteConfirmTitle,
        body: l10n.feedbackDeleteConfirmBody(count),
        submitLabel: l10n.feedbackDeleteSelectedAction,
        icon: const Icon(AppActionIcons.delete),
        submitLeadingIcon: AppActionIcons.delete,
        destructive: true,
        onConfirm: () async {
          final Result<FeedbackDeleteResult> result = deletesAllMatching
              ? await repository.deleteMatchingFeedback(filters: filters)
              : await repository.deleteFeedback(referenceIds: referenceIds);
          switch (result) {
            case ResultSuccess<FeedbackDeleteResult>(
              value: final FeedbackDeleteResult value,
            ):
              deletedCount = value.deletedCount;
              return null;
            case ResultFailure<FeedbackDeleteResult>(
              failure: final AppFailure failure,
            ):
              return failure;
          }
        },
      ),
    );

    if (deleted == true && mounted) {
      Navigator.of(context).pop(deletedCount);
    }
  }
}
