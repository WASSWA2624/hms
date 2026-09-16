import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/utils/app_formatters.dart';
import 'package:hosspi_hms/features/feedback/data/repositories/feedback_repository_impl.dart';
import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';
import 'package:hosspi_hms/features/feedback/presentation/feedback_labels.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/components/components.dart';
import 'package:hosspi_hms/shared/data/app_pagination.dart';
import 'package:hosspi_hms/shared/layout/app_workspace.dart';

/// [AppSearchBarFilterValue] keys for the feedback filters.
abstract final class FeedbackFilterKeys {
  static const String category = 'category';
  static const String submitterType = 'submitter_type';
  static const String deviceType = 'device_type';
  static const String platform = 'platform';
}

/// Picks stored feedback from a paged table, then hands the picked records to
/// [onConfirm].
///
/// The ticked boxes are the only record of what is picked: no running count,
/// no clear-selection action, so the toolbar stays search and filters alone.
///
/// Clear feedback and Download feedback differ only in what happens to the
/// records at the end, so both drive this one dialog. Feedback loads a page at
/// a time from the server and narrows by search, a submission date range,
/// feedback type, submitter, device type, and platform. Sorting is the
/// server's too: ordering only the page in front of the user would misreport
/// the list as a whole.
class FeedbackRecordsDialog<T> extends ConsumerStatefulWidget {
  const FeedbackRecordsDialog({
    required this.title,
    required this.icon,
    required this.confirmLabel,
    required this.confirmIcon,
    required this.onConfirm,
    required this.pageCheckboxKey,
    required this.rowCheckboxKeyBuilder,
    this.requiresSelection = true,
    this.destructive = false,
    super.key,
  });

  final String title;
  final IconData icon;
  final String confirmLabel;
  final IconData confirmIcon;

  /// Acts on the picked records, with the search and filters they were picked
  /// under. Returning a value closes the dialog with it; returning null leaves
  /// the dialog open with the selection intact.
  ///
  /// The set is empty only when [requiresSelection] is false, and then means
  /// every record matching those filters.
  final Future<T?> Function(
    BuildContext context,
    Set<String> referenceIds,
    FeedbackFilters filters,
  )
  onConfirm;

  /// When true (default), the confirm action waits until records are picked.
  /// Set false where acting on the whole matching list is meaningful, as
  /// downloading it is.
  final bool requiresSelection;

  /// Paints the confirm action in the error colour.
  final bool destructive;

  final Key pageCheckboxKey;
  final Key Function(String referenceId) rowCheckboxKeyBuilder;

  @override
  ConsumerState<FeedbackRecordsDialog<T>> createState() =>
      _FeedbackRecordsDialogState<T>();
}

class _FeedbackRecordsDialogState<T>
    extends ConsumerState<FeedbackRecordsDialog<T>> {
  static const Duration _searchDebounce = Duration(milliseconds: 350);
  static const String _emptyCell = '—';

  /// Column ids the table sorts by, mapped to what the API orders on. Columns
  /// missing here cannot be ordered server-side and do not offer sort.
  static const Map<String, FeedbackSortField> _sortFields =
      <String, FeedbackSortField>{
        'submitted_at': FeedbackSortField.submittedAt,
        'category': FeedbackSortField.category,
        'submitted_by': FeedbackSortField.submitter,
        'reference': FeedbackSortField.reference,
        'tenant': FeedbackSortField.tenant,
        'facility': FeedbackSortField.facility,
        'device_type': FeedbackSortField.deviceType,
        'platform': FeedbackSortField.platform,
        'screen': FeedbackSortField.routePath,
      };

  final TextEditingController _searchController = TextEditingController();

  // Checkboxes listen to this, so they repaint on every selection change even
  // when the table keeps its rows and header mounted.
  final ValueNotifier<int> _selectionRevision = ValueNotifier<int>(0);
  final Set<String> _selectedIds = <String>{};
  Timer? _searchTimer;
  String _appliedSearch = '';
  AppSearchBarFilterValue _filterValue = AppSearchBarFilterValue.empty;
  AppPageRequest _request = const AppPageRequest();
  FeedbackSort _sort = FeedbackSort.newestFirst;
  AppPage<FeedbackRecord>? _page;
  AppFailure? _loadFailure;
  bool _isLoading = true;
  bool _isConfirming = false;
  int _loadGeneration = 0;

  List<FeedbackRecord> get _pageItems =>
      _page?.items ?? const <FeedbackRecord>[];

  int get _selectedCount => _selectedIds.length;

  bool get _canConfirm {
    if (_isLoading || _isConfirming) {
      return false;
    }
    return _selectedCount > 0 || !widget.requiresSelection;
  }

  FeedbackFilters get _filters {
    final AppSearchBarFilterValue value = _filterValue;
    final String? submitterType = value.option(FeedbackFilterKeys.submitterType);

    return FeedbackFilters(
      search: _appliedSearch,
      categories: value
          .optionsFor(FeedbackFilterKeys.category)
          .map(FeedbackCategory.fromApiValue)
          .toSet(),
      submitterType: submitterType == null
          ? null
          : FeedbackSubmitterType.fromApiValue(submitterType),
      deviceTypes: value
          .optionsFor(FeedbackFilterKeys.deviceType)
          .map(FeedbackDeviceType.fromApiValue)
          .whereType<FeedbackDeviceType>()
          .toSet(),
      platforms: value.optionsFor(FeedbackFilterKeys.platform),
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
      title: Text(widget.title),
      icon: Icon(widget.icon),
      maxWidth: 1200,
      pinActionsToBottom: true,
      closeEnabled: !_isConfirming,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (loadFailure != null) ...<Widget>[
            AppFormInformationBanner.failure(
              context: context,
              failure: loadFailure,
            ),
            SizedBox(height: theme.spacing.sm),
          ],
          Expanded(child: _buildTable(context, l10n)),
        ],
      ),
      actions: <Widget>[
        AppButton.close(
          label: l10n.commonCloseActionLabel,
          enabled: !_isConfirming,
          onPressed: _isConfirming
              ? null
              : () => Navigator.of(context).maybePop(),
        ),
        AppButton.primary(
          label: widget.confirmLabel,
          leadingIcon: widget.confirmIcon,
          // No spinner: the action either opens its own dialog or resolves at
          // once, so a busy indicator would only flash or hang.
          enabled: _canConfirm,
          color: widget.destructive ? theme.colorScheme.error : null,
          onPressed: _canConfirm ? () => unawaited(_confirm()) : null,
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
      initialSortColumnKey: 'submitted_at',
      initialSortAscending: false,
      onSortChanged: _applySort,
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
              key: widget.pageCheckboxKey,
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
      // The API orders the whole list; a column it cannot order stays fixed
      // rather than sorting only the rows on this page.
      sortable: _sortFields.containsKey(id),
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
        key: widget.rowCheckboxKeyBuilder(record.referenceId),
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
        key: FeedbackFilterKeys.category,
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
        key: FeedbackFilterKeys.submitterType,
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
        key: FeedbackFilterKeys.deviceType,
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
        key: FeedbackFilterKeys.platform,
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
    return _selectedIds.contains(record.referenceId);
  }

  void _updateSelection(VoidCallback change) {
    setState(change);
    _selectionRevision.value += 1;
  }

  void _setSelected(FeedbackRecord record, bool selected) {
    _updateSelection(() {
      if (selected) {
        _selectedIds.add(record.referenceId);
      } else {
        _selectedIds.remove(record.referenceId);
      }
    });
  }

  void _setPageSelected(bool selected) {
    _updateSelection(() {
      final Iterable<String> ids = _pageItems.map(_referenceIdOf);
      if (selected) {
        _selectedIds.addAll(ids);
      } else {
        _selectedIds.removeAll(ids);
      }
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

  /// Reorders the whole list, not just this page. The same records still
  /// match, so the selection survives.
  void _applySort(String columnKey, bool ascending) {
    final FeedbackSortField? field = _sortFields[columnKey];
    if (field == null) {
      return;
    }
    final FeedbackSort sort = FeedbackSort(
      field: field,
      ascending: ascending,
    );
    if (sort == _sort) {
      return;
    }
    _sort = sort;
    unawaited(_load(_request.first()));
  }

  /// New search or filter criteria change which records match, so selections
  /// made under the old criteria are dropped.
  void _reloadFromFirstPage() {
    _selectedIds.clear();
    unawaited(_load(_request.first()));
  }

  Future<void> _load(AppPageRequest request) async {
    final int generation = ++_loadGeneration;
    final FeedbackFilters filters = _filters;
    final FeedbackSort sort = _sort;
    _updateSelection(() {
      _request = request;
      _isLoading = true;
      _loadFailure = null;
    });

    final Result<AppPage<FeedbackRecord>> result = await ref
        .read(feedbackRepositoryProvider)
        .fetchFeedbackPage(filters: filters, request: request, sort: sort);
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

  Future<void> _confirm() async {
    // Snapshot both: the action covers exactly what was picked, under exactly
    // the filters it was picked under.
    final Set<String> referenceIds = Set<String>.of(_selectedIds);
    final FeedbackFilters filters = _filters;
    setState(() => _isConfirming = true);
    final T? result;
    try {
      result = await widget.onConfirm(context, referenceIds, filters);
    } finally {
      if (mounted) {
        setState(() => _isConfirming = false);
      }
    }
    if (result != null && mounted) {
      Navigator.of(context).pop(result);
    }
  }
}
