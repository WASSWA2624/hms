import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/core/responsive/app_breakpoints.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/components/app_button.dart';
import 'package:hosspi_hms/shared/components/app_dialog.dart';
import 'package:hosspi_hms/shared/components/app_list_table_column_layout_memory.dart';
import 'package:hosspi_hms/shared/components/app_list_table_column_visibility_memory.dart';
import 'package:hosspi_hms/shared/components/app_list_table_export.dart';
import 'package:hosspi_hms/shared/components/app_list_table_text_policy.dart';
import 'package:hosspi_hms/shared/components/app_loading_indicator.dart';
import 'package:hosspi_hms/shared/components/app_search_bar.dart';
import 'package:hosspi_hms/shared/data/data.dart';
import 'package:hosspi_hms/shared/icons/app_action_icons.dart';

typedef AppListTableCellBuilder<T> =
    Widget Function(BuildContext context, T item);
typedef AppListTableHeaderBuilder<T> = Widget Function(BuildContext context);
typedef AppListTableMobileItemBuilder<T> =
    Widget Function(BuildContext context, T item);
typedef AppListTableItemKeyBuilder<T> = LocalKey Function(T item);
typedef AppListTablePageLabelBuilder<T> = String Function(AppPage<T> page);
typedef AppListTableRowColorBuilder<T> =
    Color? Function(BuildContext context, T item);
typedef AppListTableSearchMatcher<T> = bool Function(T item, String query);
typedef AppListTableSortComparator<T> = int Function(T left, T right);

/// Reports the column the user sorted by and its direction.
typedef AppListTableSortChanged =
    void Function(String columnKey, bool ascending);

enum AppListTableDisplayMode { adaptive, table, list }

/// How [AppListTable] requests additional [AppPage] data.
///
/// [infinite] loads the next page when the user scrolls near the bottom and
/// appends rows (preferred). [buttons] keeps classic previous/next controls.
enum AppListTablePaginationMode { infinite, buttons }

const int _maxVisibleTableColumns = 5;
const int _minTableRowCount = 50;
const double _rowNumberColumnWidth = 48;
const double _mobileRowNumberColumnWidth = 26;

/// Height of the surface gutter between tinted mobile rows.
///
/// Only tinted rows (see [AppListTable.rowColorBuilder]) get a gutter; plain
/// rows are separated by an inset hairline so the list stays compact.
const double _mobileRowGutterHeight = 6;
const double _minResizableColumnWidth = 96;
const String _defaultGoToTopLabel = 'Go to top';
const String _defaultLoadingMoreLabel = 'Loading more...';
const String _defaultAllRowsLoadedLabel = 'All rows loaded';
const Duration _goToTopAnimationDuration = Duration(milliseconds: 280);

/// Bridges scroll-to-top enablement from the table body to the pinned footer.
final class _AppListTableGoToTopController {
  final ValueNotifier<bool> canGoToTop = ValueNotifier<bool>(false);
  Future<void> Function()? _scrollToTop;

  void attach(Future<void> Function() scrollToTop) {
    _scrollToTop = scrollToTop;
  }

  void detach() {
    _scrollToTop = null;
    if (canGoToTop.value) {
      canGoToTop.value = false;
    }
  }

  /// Clears the scroll callback without notifying listeners.
  ///
  /// Use from widget `dispose` so a locked element tree is not rebuilt while
  /// unmounting a [ValueListenableBuilder] that listens to [canGoToTop].
  void detachSilently() {
    _scrollToTop = null;
  }

  void setCanGoToTop(bool value) {
    if (canGoToTop.value == value) {
      return;
    }
    canGoToTop.value = value;
  }

  Future<void> goToTop() async {
    final Future<void> Function()? action = _scrollToTop;
    if (action == null) {
      return;
    }
    await action();
  }

  void dispose() {
    canGoToTop.dispose();
    _scrollToTop = null;
  }
}
const double _defaultColumnWidth = 168;
const double _defaultCompactColumnWidth = 144;
const double _columnResizeHandleWidth = 8;
const double _infiniteScrollLoadExtent = 240;

/// Thumb thickness for the pinned horizontal table scrollbar.
///
/// Slightly taller than the Material desktop default so the gutter is easy to
/// grab, while staying compact enough not to steal much vertical space.
const double _horizontalScrollbarThickness = 12;

/// Layout space reserved under table rows for the horizontal scrollbar so the
/// last row is never painted underneath the thumb/track.
const double _horizontalScrollbarGutter = 16;

/// Preferred first-page size for paged [AppListTable] callers (backend max).
const int appListTablePreferredPageSize = AppPageRequest.maxPageSize;

/// Extra rows beyond the visible viewport kept mounted for smooth scrolling.
const int _progressiveRenderBufferRows = 4;

/// Used before the first layout pass measures the table body height.
const int _fallbackProgressiveBatch = 16;

LocalKey appListTableUniqueRowKey<T>({
  required int index,
  required AppListTableItemKeyBuilder<T>? itemKeyBuilder,
  required T item,
  Object? rowsVersion,
}) {
  final LocalKey? baseKey = itemKeyBuilder?.call(item);
  if (baseKey is ValueKey<Object?>) {
    return ValueKey<Object>(Object.hash(index, baseKey.value, rowsVersion));
  }
  if (baseKey != null) {
    return ValueKey<Object>(Object.hash(index, baseKey, rowsVersion));
  }
  return ValueKey<Object>(Object.hash(index, rowsVersion));
}

List<AppListTableColumn<T>> _availableColumnsFor<T>(
  List<AppListTableColumn<T>> columns,
  List<AppListTableColumn<T>>? columnChoices,
) {
  final List<AppListTableColumn<T>> availableColumns =
      <AppListTableColumn<T>>[];
  final Set<String> keys = <String>{};

  void addColumns(Iterable<AppListTableColumn<T>> source) {
    for (final AppListTableColumn<T> column in source) {
      if (keys.add(column.key)) {
        availableColumns.add(column);
      }
    }
  }

  addColumns(columns);
  addColumns(columnChoices ?? <AppListTableColumn<T>>[]);
  return availableColumns;
}

List<AppListTableColumn<T>> appListTableDefaultVisibleColumns<T>(
  List<AppListTableColumn<T>> availableColumns, {
  List<AppListTableColumn<T>>? defaultColumns,
}) {
  if (availableColumns.isEmpty) {
    return <AppListTableColumn<T>>[];
  }

  final List<AppListTableColumn<T>>? configuredDefault = defaultColumns;
  final List<AppListTableColumn<T>> defaultSource =
      configuredDefault == null || configuredDefault.isEmpty
      ? availableColumns
      : configuredDefault;
  final List<AppListTableColumn<T>> visible = defaultSource
      .take(math.min(defaultSource.length, _maxVisibleTableColumns))
      .toList(growable: true);
  final Set<String> visibleKeys = visible
      .map((AppListTableColumn<T> column) => column.key)
      .toSet();
  for (final AppListTableColumn<T> column in availableColumns) {
    if (column.alwaysVisible && visibleKeys.add(column.key)) {
      visible.add(column);
    }
  }
  return visible;
}

int appListTableCompareText(String? left, String? right) {
  return (left ?? '').trim().toLowerCase().compareTo(
    (right ?? '').trim().toLowerCase(),
  );
}

int appListTableCompareDateTime(DateTime? left, DateTime? right) {
  if (left == null && right == null) {
    return 0;
  }
  if (left == null) {
    return 1;
  }
  if (right == null) {
    return -1;
  }
  return left.compareTo(right);
}

int appListTableCompareNumber(num? left, num? right) {
  if (left == null && right == null) {
    return 0;
  }
  if (left == null) {
    return 1;
  }
  if (right == null) {
    return -1;
  }
  return left.compareTo(right);
}

/// Compares heterogeneous sort keys (`num`, `DateTime`, `bool`, or text).
int appListTableCompareSortValues(Object? left, Object? right) {
  if (left == null && right == null) {
    return 0;
  }
  if (left == null) {
    return 1;
  }
  if (right == null) {
    return -1;
  }
  if (left is num && right is num) {
    return left.compareTo(right);
  }
  if (left is DateTime && right is DateTime) {
    return left.compareTo(right);
  }
  if (left is bool && right is bool) {
    return left == right ? 0 : (left ? 1 : -1);
  }
  return appListTableCompareText('$left', '$right');
}

bool appListTableColumnIsActionChrome(String columnKey) {
  final String normalized = columnKey.trim().toLowerCase();
  return normalized == 'actions' ||
      normalized == 'action' ||
      normalized == 'next' ||
      normalized == 'next_action';
}

/// Resolves the value used when a column has no explicit [sortComparator].
///
/// Prefers [AppListTableColumn.exportValue]; otherwise extracts plain text from
/// [AppListTableColumn.cellBuilder] when [context] is available.
Object? appListTableResolveSortKey<T>({
  required AppListTableColumn<T> column,
  required T item,
  BuildContext? context,
}) {
  final AppListTableExportValue<T>? exportValue = column.exportValue;
  if (exportValue != null) {
    return exportValue(item);
  }
  if (context == null) {
    return null;
  }
  try {
    return appListTablePlainTextFromWidget(column.cellBuilder(context, item));
  } catch (_) {
    return null;
  }
}

String appListTableColumnVisibilityStorageKey<T>(
  List<AppListTableColumn<T>> columns,
  List<AppListTableColumn<T>>? columnChoices,
) {
  final Set<String> schemaKeys = <String>{};
  for (final AppListTableColumn<T> column in columns) {
    schemaKeys.add(column.key);
  }
  for (final AppListTableColumn<T> column
      in columnChoices ?? <AppListTableColumn<T>>[]) {
    schemaKeys.add(column.key);
  }

  final List<String> sortedKeys = schemaKeys.toList(growable: false)..sort();
  return sortedKeys.join('\u0001');
}

/// Whether [AppListTable.isLoading] should replace the table body with a skeleton.
///
/// Keeps already-fetched rows visible during background refresh; only the initial
/// empty load shows the full-table loading state.
bool appListTableShowsInitialLoading({
  required bool isLoading,
  required List<dynamic> visibleItems,
}) {
  return isLoading && visibleItems.isEmpty;
}

/// Rows to mount for the first paint / each progressive reveal batch.
///
/// When [maxVisibleItems] is set it is the batch size override. Otherwise the
/// batch is viewport rows (from [availableHeight]) plus a small buffer, falling
/// back to [_fallbackProgressiveBatch] when height is unknown.
int appListTableProgressiveBatchSize({
  int? maxVisibleItems,
  double? availableHeight,
  double headingHeight = 48,
  double rowMinHeight = 52,
  int bufferRows = _progressiveRenderBufferRows,
  int fallbackBatch = _fallbackProgressiveBatch,
}) {
  if (maxVisibleItems != null && maxVisibleItems > 0) {
    return maxVisibleItems;
  }
  if (availableHeight == null ||
      !availableHeight.isFinite ||
      availableHeight <= 0 ||
      rowMinHeight <= 0) {
    return fallbackBatch;
  }
  final double bodyHeight = math.max(0.0, availableHeight - headingHeight);
  final int viewportRows = math.max(1, (bodyHeight / rowMinHeight).ceil());
  return math.max(fallbackBatch, viewportRows + bufferRows);
}

/// How the action row under the search bar presents caller actions.
enum AppListTableActionBarLayout {
  /// Icon + label, all actions on one row.
  labeledRow,

  /// Icon only, all actions on one row.
  iconRow,

  /// Icon only, wrapped onto as many rows as needed.
  iconWrap,
}

/// Picks the presentation for the action row below the search bar.
///
/// One row is always preferred, on every breakpoint: labels are kept when the
/// labelled buttons fit ([AppListTableActionBarLayout.labeledRow]), dropped so
/// the icons still fit ([AppListTableActionBarLayout.iconRow]), and only when
/// even the icons overflow does the row wrap
/// ([AppListTableActionBarLayout.iconWrap]).
///
/// [labeledWidths] and [iconWidths] are per-action widths in the same order,
/// [spacing] the gap between adjacent buttons.
AppListTableActionBarLayout appListTableResolveActionBarLayout({
  required List<double> labeledWidths,
  required List<double> iconWidths,
  required double spacing,
  required double maxWidth,
}) {
  if (labeledWidths.isEmpty || !maxWidth.isFinite || maxWidth <= 0) {
    return AppListTableActionBarLayout.labeledRow;
  }

  double rowWidth(List<double> widths) {
    return widths.fold<double>(0, (double sum, double width) => sum + width) +
        spacing * (widths.length - 1);
  }

  if (rowWidth(labeledWidths) <= maxWidth) {
    return AppListTableActionBarLayout.labeledRow;
  }
  if (rowWidth(iconWidths) <= maxWidth) {
    return AppListTableActionBarLayout.iconRow;
  }
  return AppListTableActionBarLayout.iconWrap;
}

class AppListTableColumnVisibilityController<T> extends ChangeNotifier {
  AppListTableColumnVisibilityController({this.storageKey});

  final String? storageKey;

  List<AppListTableColumn<T>> _availableColumns = <AppListTableColumn<T>>[];
  Set<String> _visibleColumnKeys = <String>{};
  String? _syncedStorageKey;
  Set<String> _syncedDefaultColumnKeys = <String>{};

  void syncColumns({
    required List<AppListTableColumn<T>> columns,
    List<AppListTableColumn<T>>? columnChoices,
    String? storageKey,
  }) {
    final List<AppListTableColumn<T>> nextColumns = _availableColumnsFor(
      columns,
      columnChoices,
    );
    final List<String> currentKeys = _availableColumns
        .map((AppListTableColumn<T> column) => column.key)
        .toList(growable: false);
    final List<String> nextKeys = nextColumns
        .map((AppListTableColumn<T> column) => column.key)
        .toList(growable: false);
    final Set<String> nextDefaultKeys = appListTableDefaultVisibleColumns(
      nextColumns,
      defaultColumns: columns,
    ).map((AppListTableColumn<T> column) => column.key).toSet();
    final String? resolvedStorageKey = _resolvedStorageKey(storageKey);

    final bool availableUnchanged = listEquals(currentKeys, nextKeys);
    final bool defaultsUnchanged = setEquals(
      _syncedDefaultColumnKeys,
      nextDefaultKeys,
    );
    final bool storageUnchanged = _syncedStorageKey == resolvedStorageKey;
    if (availableUnchanged && defaultsUnchanged && storageUnchanged) {
      // Keys/defaults are unchanged, but callers rebuild column objects with
      // fresh builders (e.g. selection checkboxes). Keep references current.
      _availableColumns = nextColumns;
      return;
    }

    _availableColumns = nextColumns;
    _syncedDefaultColumnKeys = nextDefaultKeys;
    _syncedStorageKey = resolvedStorageKey;
    _visibleColumnKeys = _resolveVisibleColumnKeys(
      columns: columns,
      availableColumns: nextColumns,
      storageKey: storageKey,
    );
    notifyListeners();
  }

  /// Updates column object references (builders) without changing visibility.
  ///
  /// Safe to call during [State.build]; does not [notifyListeners].
  void refreshColumnBuilders({
    required List<AppListTableColumn<T>> columns,
    List<AppListTableColumn<T>>? columnChoices,
  }) {
    _availableColumns = _availableColumnsFor(columns, columnChoices);
  }

  List<AppListTableColumn<T>> get visibleColumns {
    final List<AppListTableColumn<T>> columns = _availableColumns
        .where(
          (AppListTableColumn<T> column) =>
              column.alwaysVisible || _visibleColumnKeys.contains(column.key),
        )
        .toList(growable: false);
    if (columns.isNotEmpty || _availableColumns.isEmpty) {
      return columns;
    }
    return appListTableDefaultVisibleColumns(_availableColumns);
  }

  Set<String> get visibleColumnKeys => Set<String>.of(_visibleColumnKeys);

  Set<String> get defaultColumnKeys => Set<String>.of(
    _syncedDefaultColumnKeys.isEmpty
        ? _defaultColumnKeys
        : _syncedDefaultColumnKeys,
  );

  void applyVisibleColumnKeys(Set<String> keys, {String? storageKey}) {
    _visibleColumnKeys = _withAlwaysVisibleColumnKeys(keys);
    _persistVisibleColumnKeys(storageKey ?? _syncedStorageKey);
    notifyListeners();
  }

  bool get canConfigure => _availableColumns.length > 1;

  bool get hasCustomColumnVisibility {
    final Set<String> defaults = _syncedDefaultColumnKeys.isEmpty
        ? _defaultColumnKeys
        : _syncedDefaultColumnKeys;
    return !setEquals(_visibleColumnKeys, defaults);
  }

  bool isColumnVisible(String key) {
    final AppListTableColumn<T>? column = _columnByKey(key);
    if (column?.alwaysVisible ?? false) {
      return true;
    }
    return _visibleColumnKeys.contains(key);
  }

  AppSearchBarAction settingsAction(
    BuildContext context, {
    String? label,
    String? title,
    String? applyLabel,
    String? resetLabel,
    String? closeLabel,
  }) {
    final String resolvedLabel = label ?? 'Settings';
    return AppSearchBarAction(
      icon: Icons.settings_outlined,
      label: resolvedLabel,
      tooltip: resolvedLabel,
      active: hasCustomColumnVisibility,
      onPressed: () {
        openColumnVisibilityDialog(
          context,
          title: title,
          applyLabel: applyLabel,
          resetLabel: resetLabel,
          closeLabel: closeLabel,
        );
      },
    );
  }

  Future<void> openColumnVisibilityDialog(
    BuildContext context, {
    String? title,
    String? applyLabel,
    String? resetLabel,
    String? closeLabel,
    String? storageKey,
  }) async {
    if (!canConfigure) {
      return;
    }

    final Set<String>? value = await showAppDialog<Set<String>>(
      context: context,
      builder: (_) => _ColumnVisibilityDialog<T>(
        columns: _availableColumns,
        visibleColumnKeys: _visibleColumnKeys,
        defaultColumnKeys: _syncedDefaultColumnKeys.isEmpty
            ? _defaultColumnKeys
            : _syncedDefaultColumnKeys,
        title: title ?? 'Table columns',
        applyLabel: applyLabel ?? 'Apply columns',
        resetLabel: resetLabel ?? 'Reset columns',
        closeLabel: closeLabel ?? 'Close',
      ),
    );
    if (value == null) {
      return;
    }

    _visibleColumnKeys = _withAlwaysVisibleColumnKeys(value);
    _persistVisibleColumnKeys(storageKey);
    notifyListeners();
  }

  Set<String> get _defaultColumnKeys {
    return appListTableDefaultVisibleColumns(
      _availableColumns,
    ).map((AppListTableColumn<T> column) => column.key).toSet();
  }

  AppListTableColumn<T>? _columnByKey(String key) {
    for (final AppListTableColumn<T> column in _availableColumns) {
      if (column.key == key) {
        return column;
      }
    }
    return null;
  }

  Set<String> _withAlwaysVisibleColumnKeys(Set<String> keys) {
    return <String>{
      ...keys,
      for (final AppListTableColumn<T> column in _availableColumns)
        if (column.alwaysVisible) column.key,
    };
  }

  Set<String> _resolveVisibleColumnKeys({
    required List<AppListTableColumn<T>> columns,
    required List<AppListTableColumn<T>> availableColumns,
    String? storageKey,
  }) {
    final Set<String> availableKeys = availableColumns
        .map((AppListTableColumn<T> column) => column.key)
        .toSet();
    final String? resolvedStorageKey = _resolvedStorageKey(storageKey);
    final Set<String>? savedKeys = resolvedStorageKey == null
        ? null
        : AppListTableColumnVisibilityMemory.instance.read(resolvedStorageKey);
    if (savedKeys != null) {
      final Set<String> restoredKeys = savedKeys
          .where(availableKeys.contains)
          .toSet();
      if (restoredKeys.isNotEmpty) {
        return _withAlwaysVisibleColumnKeys(restoredKeys);
      }
    }

    return appListTableDefaultVisibleColumns(
      availableColumns,
      defaultColumns: columns,
    ).map((AppListTableColumn<T> column) => column.key).toSet();
  }

  String? _resolvedStorageKey(String? override) {
    return override ?? storageKey;
  }

  void _persistVisibleColumnKeys(String? storageKey) {
    final String? resolvedStorageKey = _resolvedStorageKey(storageKey);
    if (resolvedStorageKey == null) {
      return;
    }
    AppListTableColumnVisibilityMemory.instance.write(
      resolvedStorageKey,
      _visibleColumnKeys,
    );
  }
}

@immutable
final class AppListTableSearch<T> {
  const AppListTableSearch({
    required this.controller,
    required this.semanticLabel,
    required this.matcher,
    this.hintText,
    this.clearLabel,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.enabled = true,
    this.isLoading = false,
    this.autofocus = false,
    this.showClearButton = true,
    this.focusNode,
    this.showAdvancedFilterButton = false,
    this.onAdvancedFilterPressed,
    this.advancedFilterButtonLabel,
    this.advancedFilterTitle,
    this.advancedFilterApplyLabel,
    this.advancedFilterResetLabel,
    this.advancedFilterCloseLabel,
    this.advancedFilterResetAppliesImmediately = false,
    this.searchFields = const <AppSearchBarFieldChoice>[],
    this.textFilters = const <AppSearchBarTextFilter>[],
    this.searchFieldLabel,
    this.allFieldsLabel,
    this.enableDateFilter = true,
    this.dateFilterLabel,
    this.dateFromLabel,
    this.dateToLabel,
    this.datePickerButtonLabel,
    this.invalidDateMessage,
    this.firstDate,
    this.lastDate,
    this.currentDate,
    this.filterGroups = const <AppSearchBarFilterGroup>[],
    this.filterValue = AppSearchBarFilterValue.empty,
    this.onFilterChanged,
    this.hasActiveFilters = false,
    this.trailingActions = const <AppSearchBarAction>[],
    this.enableSpeechToText = true,
  });

  final TextEditingController controller;
  final String semanticLabel;
  final AppListTableSearchMatcher<T> matcher;
  final String? hintText;
  final String? clearLabel;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final bool enabled;
  final bool isLoading;
  final bool autofocus;
  final bool showClearButton;
  final FocusNode? focusNode;
  final bool showAdvancedFilterButton;
  final VoidCallback? onAdvancedFilterPressed;
  final String? advancedFilterButtonLabel;
  final String? advancedFilterTitle;
  final String? advancedFilterApplyLabel;
  final String? advancedFilterResetLabel;
  final String? advancedFilterCloseLabel;
  final bool advancedFilterResetAppliesImmediately;
  final List<AppSearchBarFieldChoice> searchFields;
  final List<AppSearchBarTextFilter> textFilters;
  final String? searchFieldLabel;
  final String? allFieldsLabel;
  final bool enableDateFilter;
  final String? dateFilterLabel;
  final String? dateFromLabel;
  final String? dateToLabel;
  final String? datePickerButtonLabel;
  final String? invalidDateMessage;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final DateTime? currentDate;
  final List<AppSearchBarFilterGroup> filterGroups;
  final AppSearchBarFilterValue filterValue;
  final ValueChanged<AppSearchBarFilterValue>? onFilterChanged;
  final bool hasActiveFilters;

  /// Caller actions (e.g. Create / Refresh).
  ///
  /// These never enter the search bar: [AppListTable] renders them in a
  /// wrapping action row directly below it. See [AppListTable] docs.
  final List<AppSearchBarAction> trailingActions;
  final bool enableSpeechToText;

  /// Builds the search bar with the reserved table chrome only.
  ///
  /// The bar keeps speech-to-text, Filters, and the [tableActions] chrome
  /// (Settings / Export / Print); [trailingActions] are laid out below it by
  /// [AppListTable].
  Widget buildSearchBar(
    BuildContext context, {
    List<AppSearchBarAction> tableActions = const <AppSearchBarAction>[],
  }) {
    return AppSearchBar(
      controller: controller,
      semanticLabel: semanticLabel,
      hintText: hintText,
      clearLabel: clearLabel,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onClear: onClear,
      enabled: enabled,
      isLoading: isLoading,
      autofocus: autofocus,
      showClearButton: showClearButton,
      focusNode: focusNode,
      showAdvancedFilterButton: showAdvancedFilterButton,
      onAdvancedFilterPressed: onAdvancedFilterPressed,
      advancedFilterButtonLabel: advancedFilterButtonLabel,
      advancedFilterTitle: advancedFilterTitle,
      advancedFilterApplyLabel: advancedFilterApplyLabel,
      advancedFilterResetLabel: advancedFilterResetLabel,
      advancedFilterCloseLabel: advancedFilterCloseLabel,
      advancedFilterResetAppliesImmediately:
          advancedFilterResetAppliesImmediately,
      searchFields: searchFields,
      textFilters: textFilters,
      searchFieldLabel: searchFieldLabel,
      allFieldsLabel: allFieldsLabel,
      enableDateFilter: enableDateFilter,
      dateFilterLabel: dateFilterLabel,
      dateFromLabel: dateFromLabel,
      dateToLabel: dateToLabel,
      datePickerButtonLabel: datePickerButtonLabel,
      invalidDateMessage: invalidDateMessage,
      firstDate: firstDate,
      lastDate: lastDate,
      currentDate: currentDate,
      filterGroups: filterGroups,
      filterValue: filterValue,
      onFilterChanged: onFilterChanged,
      hasActiveFilters: hasActiveFilters,
      // Search bar chrome only: Filters (in AppSearchBar) → Settings → Export
      // → Print. Caller actions live in the action row below the search bar.
      trailingActions: tableActions,
      enableSpeechToText: enableSpeechToText,
    );
  }
}

/// Extra slack per button so rounding / borders cannot make a measured row
/// overflow the real layout by a hairline.
const double _actionBarFitSlack = 2;

/// Height of the compact action buttons under the search bar. Matches the
/// search-bar chrome buttons so the row costs as little vertical space as
/// possible.
const double _actionBarButtonHeight = 32;

/// Icon size inside those buttons (search-bar chrome parity).
const double _actionBarIconSize = 18;

/// Caller actions ([AppListTableSearch.trailingActions]) laid out under the
/// search bar.
///
/// Buttons are end-aligned (right in LTR) on every breakpoint and prefer a
/// single row: labels are dropped before the row is allowed to wrap. See
/// [appListTableResolveActionBarLayout].
class _AppListTableActionBar extends StatelessWidget {
  const _AppListTableActionBar({required this.actions, required this.enabled});

  final List<AppSearchBarAction> actions;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }

    final ThemeData theme = Theme.of(context);
    final AppSpacingTokens spacing = theme.spacing;
    final double gap = spacing.xs;
    final TextStyle labelStyle = _labelStyle(theme);
    final TextScaler textScaler = MediaQuery.textScalerOf(context);
    final TextDirection textDirection = Directionality.of(context);

    // Mirrors [_AppListTableActionButton] metrics so the fit test matches what
    // is painted: icon-only is a square tap target, labelled is padding + icon
    // + gap + text.
    final double iconOnlyWidth = math.max(
      _actionBarButtonHeight,
      _actionBarIconSize + spacing.xs * 2,
    );
    final List<double> iconWidths = List<double>.filled(
      actions.length,
      iconOnlyWidth,
    );
    final List<double> labeledWidths = <double>[
      for (final AppSearchBarAction action in actions)
        spacing.sm * 2 +
            _actionBarIconSize +
            spacing.xs +
            _labelWidth(action.label, labelStyle, textScaler, textDirection) +
            _actionBarFitSlack,
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final AppListTableActionBarLayout layout =
            appListTableResolveActionBarLayout(
              labeledWidths: labeledWidths,
              iconWidths: iconWidths,
              spacing: gap,
              maxWidth: constraints.maxWidth,
            );
        final bool showLabels =
            layout == AppListTableActionBarLayout.labeledRow;

        return Wrap(
          // End-aligned on every breakpoint (and on every run once the row is
          // allowed to wrap), so the actions sit under the search bar's own
          // trailing chrome instead of drifting away from it.
          alignment: WrapAlignment.end,
          runAlignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final AppSearchBarAction action in actions)
              _AppListTableActionButton(
                action: action,
                showLabel: showLabels,
                enabled: enabled && action.enabled,
              ),
          ],
        );
      },
    );
  }

  static TextStyle _labelStyle(ThemeData theme) {
    return (theme.textTheme.labelMedium ?? const TextStyle()).copyWith(
      fontWeight: AppFontWeight.emphasis,
    );
  }

  static double _labelWidth(
    String label,
    TextStyle style,
    TextScaler textScaler,
    TextDirection textDirection,
  ) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    final double width = painter.width;
    painter.dispose();
    return width;
  }
}

/// Compact action chrome for [_AppListTableActionBar].
///
/// Deliberately smaller than [AppButton]: the row sits between the search bar
/// and the table, so it is kept to [_actionBarButtonHeight] with no vertical
/// padding of its own.
class _AppListTableActionButton extends StatelessWidget {
  const _AppListTableActionButton({
    required this.action,
    required this.showLabel,
    required this.enabled,
  });

  final AppSearchBarAction action;
  final bool showLabel;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final AppSpacingTokens spacing = theme.spacing;
    final bool canPress = enabled && action.onPressed != null;
    final Color foreground = action.destructive
        ? colorScheme.error
        : action.active
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    final String tooltip = action.tooltip ?? action.label;

    final Widget button = TextButton(
      onPressed: canPress ? action.onPressed : null,
      // Flat chrome, like the search-bar actions: no fill, no border.
      style: TextButton.styleFrom(
        foregroundColor: foreground,
        disabledForegroundColor: colorScheme.onSurface.withValues(alpha: 0.38),
        backgroundColor: Colors.transparent,
        padding: EdgeInsets.symmetric(
          horizontal: showLabel ? spacing.sm : spacing.xs,
        ),
        minimumSize: Size(
          showLabel ? spacing.none : _actionBarButtonHeight,
          _actionBarButtonHeight,
        ),
        maximumSize: const Size(double.infinity, _actionBarButtonHeight),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        // Standard density keeps the painted height equal to the measured
        // [_actionBarButtonHeight]; a denser theme would shrink it further and
        // desync the one-row fit test.
        visualDensity: VisualDensity.standard,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            context.responsiveRadius(theme.radius.xs),
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(action.icon, size: _actionBarIconSize),
          if (showLabel) ...<Widget>[
            SizedBox(width: spacing.xs),
            Text(
              action.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: _AppListTableActionBar._labelStyle(
                theme,
              ).copyWith(color: canPress ? foreground : null),
            ),
          ],
        ],
      ),
    );

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: canPress,
        label: action.label,
        child: button,
      ),
    );
  }
}

class AppListTableColumn<T> {
  const AppListTableColumn({
    required this.label,
    required this.cellBuilder,
    this.id,
    this.numeric = false,
    this.alwaysVisible = false,
    this.tooltip,
    this.sortable,
    this.sortComparator,
    this.headerBuilder,
    this.preferredWidth,
    this.fixedWidth,
    this.exportValue,
    this.exportable,
  });

  final String? id;
  final String label;
  final AppListTableCellBuilder<T> cellBuilder;
  final bool numeric;
  final bool alwaysVisible;
  final String? tooltip;

  /// Whether the column header offers sort.
  ///
  /// When null, defaults to true except action chrome columns (`actions`,
  /// `action`, `next`, `next_action`). Set false to opt out, or true to force
  /// sort even on action keys when a [sortComparator] / export value exists.
  final bool? sortable;

  final AppListTableSortComparator<T>? sortComparator;
  final AppListTableHeaderBuilder<T>? headerBuilder;

  /// Optional default width before user resize; clamped like saved widths.
  final double? preferredWidth;

  /// Exact non-resizable width; bypasses the resize minimum clamp.
  final double? fixedWidth;

  /// Plain cell value used by Excel export (not the widget [cellBuilder]).
  ///
  /// When null, export falls back to plain text extracted from [cellBuilder].
  /// Also used as the default sort key when [sortComparator] is null.
  final AppListTableExportValue<T>? exportValue;

  /// Whether this column appears in Excel export.
  ///
  /// When null, action chrome columns (`actions` / `next_action`) are omitted
  /// unless [exportValue] is provided; all other columns are included.
  final bool? exportable;

  String get key => id ?? label;

  bool get isSortable {
    if (sortable != null) {
      return sortable!;
    }
    return !appListTableColumnIsActionChrome(key);
  }

  bool get includesInExport {
    if (exportable != null) {
      return exportable!;
    }
    if (exportValue != null) {
      return true;
    }
    final String normalized = key.trim().toLowerCase();
    return normalized != 'actions' && normalized != 'next_action';
  }
}

/// One meta fragment on the secondary line of [AppListTableMobileItem].
final class AppListTableMobileMeta {
  const AppListTableMobileMeta({required this.label, this.icon});

  final String label;
  final IconData? icon;
}

/// Two-line mobile row for [AppListTable] list layout.
///
/// Line 1: [title] (up to two lines).
/// Line 2: optional [caption] plus middot-joined [meta] entries (optional
/// icons); the whole meta line truncates from the end.
/// Optional [trailing] hosts a labeled next-action (or similar) without nesting
/// a second list chrome. A chevron is still added by the table when the row is
/// selectable.
class AppListTableMobileItem extends StatelessWidget {
  const AppListTableMobileItem({
    required this.title,
    this.caption,
    this.meta = const <AppListTableMobileMeta>[],
    this.leading,
    this.trailing,
    this.showAvatar = true,
    this.avatarLabel,
    this.padding,
    super.key,
  });

  final String title;
  final String? caption;
  final List<AppListTableMobileMeta> meta;
  final Widget? leading;
  final Widget? trailing;
  final bool showAvatar;
  final String? avatarLabel;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppListTokens listTokens = theme.listTokens;
    final String resolvedTitle = title.trim();
    final String? resolvedCaption = caption?.trim();
    final List<AppListTableMobileMeta> resolvedMeta = <AppListTableMobileMeta>[
      if (resolvedCaption != null && resolvedCaption.isNotEmpty)
        AppListTableMobileMeta(label: resolvedCaption),
      ...meta.where(
        (AppListTableMobileMeta item) => item.label.trim().isNotEmpty,
      ),
    ];
    final Widget? leadingWidget =
        leading ??
        (showAvatar
            ? _AppListTableMobileAvatar(
                label: avatarLabel?.trim().isNotEmpty == true
                    ? avatarLabel!.trim()
                    : resolvedTitle,
              )
            : null);

    return Padding(
      // Compact by default: the leading avatar already sets the row's minimum
      // height, so the vertical inset only needs to keep two-line content off
      // the divider.
      padding:
          padding ??
          EdgeInsets.symmetric(
            horizontal: theme.spacing.sm,
            vertical: theme.spacing.sm,
          ),
      child: Row(
        children: <Widget>[
          if (leadingWidget != null) ...<Widget>[
            leadingWidget,
            SizedBox(width: theme.spacing.sm + 2),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  resolvedTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: listTokens.mobileTitle,
                ),
                if (resolvedMeta.isNotEmpty) ...<Widget>[
                  SizedBox(height: listTokens.mobileMetaLineGap),
                  _AppListTableMobileMetaRow(items: resolvedMeta),
                ],
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            SizedBox(width: theme.spacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _AppListTableMobileAvatar extends StatelessWidget {
  const _AppListTableMobileAvatar({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppListTokens listTokens = theme.listTokens;
    final ColorScheme colors = theme.colorScheme;
    final String? initials = _initialsFor(label);
    final _AvatarTone tone = _avatarTone(colors, label);
    final double size = listTokens.mobileAvatarSize;

    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tone.background,
          shape: BoxShape.circle,
          border: theme.borders.all(color: tone.foreground.withValues(alpha: 0.12)),
        ),
        child: initials == null
            ? Icon(
                Icons.article_outlined,
                size: size * 0.42,
                color: tone.foreground.withValues(alpha: 0.85),
              )
            : Text(
                initials,
                style: listTokens.mobileAvatarInitials.copyWith(
                  color: tone.foreground,
                ),
              ),
      ),
    );
  }

  /// Prefer alphabetic word initials so catalog titles like
  /// `1,3 beta glucan [...]` become `BG` instead of `1,` / `1[`.
  static String? _initialsFor(String value) {
    final List<String> words = value
        .trim()
        .split(RegExp(r'[\s|/,_.:;\-]+'))
        .map((String part) => part.replaceAll(RegExp(r'[^A-Za-z]'), ''))
        .where((String part) => part.isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) {
      return null;
    }
    if (words.length == 1) {
      final String token = words.first.toUpperCase();
      return token.length >= 2 ? token.substring(0, 2) : token;
    }
    return '${words[0][0]}${words[1][0]}'.toUpperCase();
  }

  static _AvatarTone _avatarTone(ColorScheme colors, String seed) {
    final List<_AvatarTone> tones = <_AvatarTone>[
      _AvatarTone(
        background: colors.primary.withValues(alpha: 0.10),
        foreground: colors.primary,
      ),
      _AvatarTone(
        background: colors.tertiary.withValues(alpha: 0.12),
        foreground: colors.tertiary,
      ),
      _AvatarTone(
        background: colors.secondary.withValues(alpha: 0.12),
        foreground: colors.secondary,
      ),
      _AvatarTone(
        background: colors.onSurface.withValues(alpha: 0.06),
        foreground: colors.onSurfaceVariant,
      ),
    ];
    return tones[seed.hashCode.abs() % tones.length];
  }
}

final class _AvatarTone {
  const _AvatarTone({required this.background, required this.foreground});

  final Color background;
  final Color foreground;
}

class _AppListTableMobileMetaRow extends StatelessWidget {
  const _AppListTableMobileMetaRow({required this.items});

  final List<AppListTableMobileMeta> items;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppListTokens listTokens = theme.listTokens;
    final TextStyle style = listTokens.mobileMeta;
    final Color muted =
        style.color ?? theme.colorScheme.onSurfaceVariant;
    final double iconSize = listTokens.mobileMetaIconSize;

    return Text.rich(
      TextSpan(
        style: style,
        children: <InlineSpan>[
          for (int index = 0; index < items.length; index++) ...<InlineSpan>[
            if (index > 0)
              TextSpan(
                // Tight middot: on a phone the meta line is the first thing to
                // truncate, so padding around the separator is width wasted.
                text: ' · ',
                style: style.copyWith(
                  color: muted.withValues(alpha: 0.55),
                ),
              ),
            if (items[index].icon != null)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    end: theme.spacing.xs / 2,
                  ),
                  child: Icon(
                    items[index].icon,
                    size: iconSize,
                    color: muted.withValues(alpha: 0.9),
                  ),
                ),
              ),
            TextSpan(text: items[index].label.trim()),
          ],
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Shared worklist table with viewport-virtualized rows.
///
/// In bounded-height layouts (the common workspace case) table rows live in a
/// lazily built scroll view: only rows near the viewport are built, laid out,
/// and painted, so the full loaded list is scrollable in one smooth gesture
/// and appended pages extend the scroll extent in place. Shrink-wrapped
/// tables inside an ancestor scroll view cannot be virtualized; those mount
/// roughly a viewport of rows first and progressively reveal more as the user
/// scrolls. For paged backends, prefer
/// `AppPageRequest(pageSize: appListTablePreferredPageSize)` (100 / max page
/// size); smaller explicit [AppPageRequest.pageSize] values are left alone.
///
/// Toolbar chrome is fixed: the search bar holds only speech-to-text, Filters,
/// Settings, Export and Print. Caller actions
/// ([AppListTableSearch.trailingActions]) are laid out in a compact,
/// end-aligned wrapping row directly below the search bar — see
/// [appListTableResolveActionBarLayout] for how that row picks icon-only vs
/// icon+label.
///
/// Search bar, action row, and rows scroll together as one body; only the
/// footer (status / pagination + go-to-top) stays pinned. Tables with a
/// toolbar therefore mount rows progressively instead of virtualizing them.
class AppListTable<T> extends StatefulWidget {
  const AppListTable({
    required this.columns,
    required this.mobileItemBuilder,
    this.items,
    this.page,
    this.columnChoices,
    this.itemKeyBuilder,
    this.rowsVersion,
    this.onRowSelected,
    this.onPageChanged,
    this.pageLabelBuilder,
    this.previousPageLabel,
    this.nextPageLabel,
    this.paginationMode = AppListTablePaginationMode.infinite,
    this.emptyBuilder,
    this.loadingBuilder,
    this.errorBuilder,
    this.footer,
    this.rowColorBuilder,
    this.initialSortColumnKey,
    this.initialSortAscending = true,
    this.onSortChanged,
    this.maxVisibleItems,
    this.isLoading = false,
    this.error,
    this.shrinkWrap = false,
    this.physics,
    this.displayMode = AppListTableDisplayMode.adaptive,
    this.search,
    this.searchListenable,
    this.searchMatcher,
    @Deprecated(
      'Section titles belong on AppWorkspace or AppCollapsibleSection only.',
    )
    this.title,
    @Deprecated(
      'Section descriptions belong on AppWorkspace or AppCollapsibleSection only.',
    )
    this.description,
    this.columnVisibilityLabel,
    this.columnVisibilityTitle,
    this.columnVisibilityApplyLabel,
    this.columnVisibilityResetLabel,
    this.columnVisibilityCloseLabel,
    this.columnVisibilityController,
    this.columnVisibilityStorageKey,
    this.columnWidthStorageKey,
    this.onSettingsPressed,
    this.enableExport = true,
    this.canExport = true,
    this.exportConfig,
    this.loadMatchingItems,
    this.exportLabel,
    this.exportDialogTitle,
    this.exportCancelLabel,
    this.exportColumnsSectionLabel,
    this.exportFiltersSectionLabel,
    this.exportEmptyColumnsMessage,
    this.exportEmptyRowsMessage,
    this.exportSuccessMessage,
    this.exportFailureMessage,
    this.exportInvalidDateMessage,
    this.enablePrint = false,
    this.canPrint = true,
    this.onPrint,
    this.printLabel,
    this.printFailureMessage,
    this.enableColumnResize = true,
    this.tableHorizontalMargin,
    this.toolbarContentGap,
    this.showRowNumbers = true,
    this.padEmptyRows,
    this.surfaceHeader,
    this.forceCompact = false,
    this.goToTopLabel = _defaultGoToTopLabel,
    this.loadingMoreLabel = _defaultLoadingMoreLabel,
    this.allRowsLoadedLabel = _defaultAllRowsLoadedLabel,
    super.key,
  }) : assert(
         items != null || page != null,
         'Provide either items or page to AppListTable.',
       ),
       assert(
         searchListenable == null || searchMatcher != null,
         'Provide searchMatcher when searchListenable is used.',
       );

  final List<T>? items;
  final AppPage<T>? page;
  final List<AppListTableColumn<T>> columns;
  final List<AppListTableColumn<T>>? columnChoices;
  final AppListTableMobileItemBuilder<T> mobileItemBuilder;
  final AppListTableItemKeyBuilder<T>? itemKeyBuilder;

  /// When this value changes, desktop/mobile row elements remount so stateful
  /// cell chrome (e.g. selection checkboxes) cannot stay visually stale.
  final Object? rowsVersion;
  final ValueChanged<T>? onRowSelected;
  final ValueChanged<AppPageRequest>? onPageChanged;
  final AppListTablePageLabelBuilder<T>? pageLabelBuilder;
  final String? previousPageLabel;
  final String? nextPageLabel;
  final AppListTablePaginationMode paginationMode;
  final WidgetBuilder? emptyBuilder;
  final WidgetBuilder? loadingBuilder;
  final Widget Function(BuildContext context, Object error)? errorBuilder;
  final Widget? footer;
  final AppListTableRowColorBuilder<T>? rowColorBuilder;
  final String? initialSortColumnKey;
  final bool initialSortAscending;

  /// Called when the user picks a sort column or flips its direction.
  ///
  /// Set it when the rows are ordered elsewhere — a paged backend, say. The
  /// header keeps showing the sort indicator, but the table leaves the loaded
  /// rows in the order they arrived instead of re-sorting the page on its own,
  /// which would only order the rows in front of the user.
  final AppListTableSortChanged? onSortChanged;

  /// Progressive reveal batch size override.
  ///
  /// When null (default), bounded-height tables virtualize row building via
  /// the scroll viewport, and shrink-wrapped tables mount roughly a viewport
  /// of rows plus a small buffer, revealing more as the user scrolls. When
  /// set, rows are always mounted in progressive batches with this value as
  /// the initial and per-scroll batch size. Prefer
  /// [appListTablePreferredPageSize] (`AppPageRequest.maxPageSize`) for paged
  /// data requests; this field only controls client-side mounting.
  final int? maxVisibleItems;
  final bool isLoading;
  final Object? error;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final AppListTableDisplayMode displayMode;
  final AppListTableSearch<T>? search;
  final ValueListenable<String>? searchListenable;
  final AppListTableSearchMatcher<T>? searchMatcher;
  final String? title;
  final String? description;
  final String? columnVisibilityLabel;
  final String? columnVisibilityTitle;
  final String? columnVisibilityApplyLabel;
  final String? columnVisibilityResetLabel;
  final String? columnVisibilityCloseLabel;
  final AppListTableColumnVisibilityController<T>? columnVisibilityController;
  final String? columnVisibilityStorageKey;
  final String? columnWidthStorageKey;
  /// When set, Settings opens this callback instead of the column-visibility dialog.
  final Future<void> Function()? onSettingsPressed;

  /// When true (default), shows an Export action in the search-bar trailing cluster.
  /// Set false to opt out for tables that must not export.
  final bool enableExport;

  /// When false, hides Export even if [enableExport] is true (permission gate).
  /// Defaults to true; callers should pass false when the user lacks export access.
  final bool canExport;
  final AppListTableExportConfig<T>? exportConfig;

  /// Resolves the matching dataset for Export and Print. Prefer this over
  /// passing only the currently loaded [page] slice.
  final AppListTableMatchingItemsLoader<T>? loadMatchingItems;
  final String? exportLabel;
  final String? exportDialogTitle;
  final String? exportCancelLabel;
  final String? exportColumnsSectionLabel;
  final String? exportFiltersSectionLabel;
  final String? exportEmptyColumnsMessage;
  final String? exportEmptyRowsMessage;
  final String? exportSuccessMessage;
  final String? exportFailureMessage;
  final String? exportInvalidDateMessage;

  /// When true, shows a Print action immediately after Export in the toolbar.
  /// Callers must supply [onPrint] (preview-first path). Default false.
  final bool enablePrint;

  /// When false, hides Print even if [enablePrint] is true (permission gate).
  final bool canPrint;

  /// Opens the feature print-preview path with the matching dataset.
  /// Required when [enablePrint] is true.
  final Future<void> Function(List<T> matchingItems)? onPrint;

  /// Defaults to `Print` when null.
  final String? printLabel;

  /// Shown when resolving the matching dataset for Print fails.
  final String? printFailureMessage;
  final bool enableColumnResize;
  final double? tableHorizontalMargin;

  /// Vertical space between the search/toolbar and the table surface.
  ///
  /// Defaults to `theme.spacing.xs`. Pass `0` when the table should sit flush
  /// under the search bar (e.g. inside an [AppCollapsibleSection] with zero
  /// content padding).
  final double? toolbarContentGap;

  /// When false, hides the leading `#` index column (desktop and mobile).
  final bool showRowNumbers;

  /// When set, overrides empty spacer-row padding. Defaults to padding when the
  /// table has a bounded height and is not shrink-wrapped, filling the
  /// remaining viewport with blank rows.
  final bool? padEmptyRows;

  /// Optional chrome rendered inside the table surface above the rows; scrolls
  /// with table content when the table scrolls vertically.
  final Widget? surfaceHeader;

  /// When true, uses compact row/header metrics regardless of breakpoint.
  final bool forceCompact;
  final String goToTopLabel;
  final String loadingMoreLabel;
  final String allRowsLoadedLabel;

  @override
  State<AppListTable<T>> createState() => _AppListTableState<T>();
}

class _AppListTableState<T> extends State<AppListTable<T>> {
  Set<String> _visibleColumnKeys = <String>{};
  Map<String, double> _columnWidths = <String, double>{};
  String? _sortColumnKey;
  bool _sortAscending = true;
  int? _renderLimit;
  int? _viewportBatchSize;
  bool _viewportSyncScheduled = false;
  bool _revealScheduled = false;
  bool _viewportDrivesRowMounting = false;
  bool _lastLayoutHadBoundedHeight = false;
  bool _rowMountingSyncScheduled = false;
  String _trackedQuery = '';
  int _trackedSortedItemCount = 0;
  List<T> _accumulatedItems = <T>[];
  int _accumulatedPageIndex = -1;
  bool _pendingLoadMore = false;
  bool _skipAutoLoadMore = false;
  ScrollMetrics? _lastVerticalScrollMetrics;
  ScrollPosition? _ancestorScrollPosition;
  List<T>? _cachedSortSource;
  String? _cachedSortColumnKey;
  bool? _cachedSortAscending;
  List<T>? _cachedSortedItems;
  int _lastSeenItemsLength = -1;
  final _AppListTableGoToTopController _goToTopController =
      _AppListTableGoToTopController();

  /// Drives the single scroll view that carries toolbar + rows together.
  final ScrollController _toolbarScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.columnVisibilityController?.addListener(
      _handleColumnVisibilityChanged,
    );
    _syncVisibleColumns();
    _syncColumnWidths();
    _syncAccumulatedPage(widget.page);
    _ensureDefaultSortColumn();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _continueInfiniteScrollIfNeeded();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reattachAncestorScrollListener();
  }

  @override
  void didUpdateWidget(covariant AppListTable<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.columnVisibilityController !=
        widget.columnVisibilityController) {
      oldWidget.columnVisibilityController?.removeListener(
        _handleColumnVisibilityChanged,
      );
      widget.columnVisibilityController?.addListener(
        _handleColumnVisibilityChanged,
      );
    }
    final bool columnsChanged = !_sameColumnIdentity(
      oldWidget.columns,
      widget.columns,
    );
    final List<AppListTableColumn<T>> previousChoices =
        oldWidget.columnChoices ?? <AppListTableColumn<T>>[];
    final List<AppListTableColumn<T>> nextChoices =
        widget.columnChoices ?? <AppListTableColumn<T>>[];
    final bool columnChoicesChanged = !_sameColumnIdentity(
      previousChoices,
      nextChoices,
    );
    if (columnsChanged ||
        columnChoicesChanged ||
        oldWidget.columnVisibilityController !=
            widget.columnVisibilityController ||
        oldWidget.columnVisibilityStorageKey !=
            widget.columnVisibilityStorageKey ||
        oldWidget.initialSortColumnKey != widget.initialSortColumnKey ||
        oldWidget.initialSortAscending != widget.initialSortAscending) {
      if (oldWidget.initialSortColumnKey != widget.initialSortColumnKey ||
          oldWidget.initialSortAscending != widget.initialSortAscending) {
        _sortColumnKey = null;
        _invalidateSortCache();
      }
      _syncVisibleColumns();
      _ensureDefaultSortColumn();
    }
    if (oldWidget.columnWidthStorageKey != widget.columnWidthStorageKey ||
        columnsChanged ||
        columnChoicesChanged) {
      _syncColumnWidths();
    }
    if (oldWidget.page != widget.page ||
        oldWidget.paginationMode != widget.paginationMode ||
        !identical(oldWidget.items, widget.items)) {
      if (oldWidget.page != widget.page) {
        _skipAutoLoadMore = false;
      }
      _syncAccumulatedPage(widget.page);
      if (!identical(oldWidget.items, widget.items)) {
        _invalidateSortCache();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _continueInfiniteScrollIfNeeded();
        }
      });
    }
    if (oldWidget.isLoading && !widget.isLoading) {
      _pendingLoadMore = false;
      if (oldWidget.page == widget.page) {
        _skipAutoLoadMore = true;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _reattachAncestorScrollListener();
      }
    });
  }

  @override
  void dispose() {
    _detachAncestorScrollListener();
    widget.columnVisibilityController?.removeListener(
      _handleColumnVisibilityChanged,
    );
    _goToTopController.dispose();
    _toolbarScrollController.dispose();
    super.dispose();
  }

  void _handleColumnVisibilityChanged() {
    final String? sortColumnKey = _sortColumnKey;
    if (sortColumnKey != null &&
        widget.columnVisibilityController?.isColumnVisible(sortColumnKey) ==
            false) {
      _sortColumnKey = null;
      _sortAscending = true;
      _ensureDefaultSortColumn();
    }
    if (mounted) {
      setState(() {});
    }
  }

  bool get _usesInfinitePagination {
    return widget.paginationMode == AppListTablePaginationMode.infinite &&
        widget.page != null &&
        widget.onPageChanged != null;
  }

  void _syncAccumulatedPage(AppPage<T>? page) {
    _invalidateSortCache();
    if (!_usesInfinitePagination || page == null) {
      _accumulatedItems = page?.items ?? widget.items ?? <T>[];
      _accumulatedPageIndex = page?.pageIndex ?? -1;
      _pendingLoadMore = false;
      return;
    }

    if (page.pageIndex == 0) {
      _accumulatedItems = List<T>.of(page.items);
      _accumulatedPageIndex = 0;
      _pendingLoadMore = false;
      return;
    }

    if (page.pageIndex == _accumulatedPageIndex + 1) {
      _accumulatedItems = <T>[..._accumulatedItems, ...page.items];
      _accumulatedPageIndex = page.pageIndex;
      _pendingLoadMore = false;
      return;
    }

    if (page.pageIndex == _accumulatedPageIndex) {
      // Same page re-emitted (refresh); keep accumulated prefix and replace
      // the current page slice when possible.
      final int offset = page.request.offset;
      if (offset <= _accumulatedItems.length) {
        _accumulatedItems = <T>[
          ..._accumulatedItems.take(offset),
          ...page.items,
        ];
      } else {
        _accumulatedItems = List<T>.of(page.items);
        _accumulatedPageIndex = page.pageIndex;
      }
      _pendingLoadMore = false;
      return;
    }

    _accumulatedItems = List<T>.of(page.items);
    _accumulatedPageIndex = page.pageIndex;
    _pendingLoadMore = false;
  }

  void _syncColumnWidths() {
    final String? storageKey = _resolvedColumnWidthStorageKey();
    final Map<String, double> next = <String, double>{};
    if (storageKey != null) {
      final Map<String, double>? saved = AppListTableColumnLayoutMemory.instance
          .read(storageKey);
      if (saved != null) {
        next.addAll(saved);
      }
    }
    _columnWidths = next;
  }

  String? _resolvedColumnWidthStorageKey() {
    return widget.columnWidthStorageKey ??
        widget.columnVisibilityStorageKey ??
        appListTableColumnVisibilityStorageKey(
          widget.columns,
          widget.columnChoices,
        );
  }

  double _columnWidthFor(
    AppListTableColumn<T> column, {
    required bool compact,
  }) {
    final double? fixed = column.fixedWidth;
    if (fixed != null) {
      return fixed;
    }
    final double? saved = _columnWidths[column.key];
    if (saved != null) {
      return saved.clamp(_minResizableColumnWidth, 640);
    }
    final double? preferred = column.preferredWidth;
    if (preferred != null) {
      return preferred.clamp(_minResizableColumnWidth, 640);
    }
    if (_isActionsColumn(column)) {
      return compact ? 176.0 : 208.0;
    }
    return compact ? _defaultCompactColumnWidth : _defaultColumnWidth;
  }

  bool _isActionsColumn(AppListTableColumn<T> column) {
    final String key = column.key.trim().toLowerCase();
    final String label = column.label.trim().toLowerCase();
    return column.id == 'actions' || key == 'actions' || label == 'actions';
  }

  void _updateColumnWidth(String columnKey, double width) {
    final double nextWidth = width.clamp(_minResizableColumnWidth, 640);
    if (_columnWidths[columnKey] == nextWidth) {
      return;
    }
    setState(() {
      _columnWidths = <String, double>{..._columnWidths, columnKey: nextWidth};
    });
    final String? storageKey = _resolvedColumnWidthStorageKey();
    if (storageKey != null) {
      AppListTableColumnLayoutMemory.instance.writeWidth(
        storageKey,
        columnKey,
        nextWidth,
      );
    }
  }

  void _reattachAncestorScrollListener() {
    // Progressive reveal and infinite pagination both need ancestor scroll.
    final ScrollableState? scrollable = Scrollable.maybeOf(context);
    final ScrollPosition? position = scrollable?.position;
    if (identical(position, _ancestorScrollPosition)) {
      return;
    }
    _detachAncestorScrollListener();
    _ancestorScrollPosition = position;
    _ancestorScrollPosition?.addListener(_handleAncestorScroll);
  }

  void _detachAncestorScrollListener() {
    _ancestorScrollPosition?.removeListener(_handleAncestorScroll);
    _ancestorScrollPosition = null;
  }

  void _handleAncestorScroll() {
    final ScrollPosition? position = _ancestorScrollPosition;
    if (position == null || !position.hasContentDimensions) {
      return;
    }
    _handleScrollMetrics(position);
  }

  void _handleScrollMetrics(ScrollMetrics metrics) {
    _lastVerticalScrollMetrics = metrics;
    if (metrics.maxScrollExtent <= 0) {
      if (!_skipAutoLoadMore) {
        _maybeRequestNextPage();
      }
      return;
    }
    _skipAutoLoadMore = false;
    // Prefetch roughly a viewport ahead so batch reveals and next-page
    // requests start before the user actually hits the bottom.
    final double loadExtent = math.max(
      _infiniteScrollLoadExtent,
      metrics.viewportDimension,
    );
    if (metrics.pixels < metrics.maxScrollExtent - loadExtent) {
      return;
    }
    _onNearScrollEnd();
  }

  void _continueInfiniteScrollIfNeeded() {
    if (!_usesInfinitePagination || _skipAutoLoadMore) {
      return;
    }
    final ScrollMetrics? metrics = _lastVerticalScrollMetrics;
    if (metrics == null) {
      // First layout may not have dispatched inner-table metrics yet
      // (ancestor lookup cannot see the table's own CustomScrollView).
      // Request the next page when more matching rows exist so empty-row
      // padding cannot stall infinite scroll.
      _maybeRequestNextPage();
      return;
    }
    _handleScrollMetrics(metrics);
  }

  void _scheduleRevealIfNeeded({bool allowPageRequest = true}) {
    if (_revealScheduled) {
      return;
    }
    _revealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealScheduled = false;
      if (!mounted) {
        return;
      }
      _onNearScrollEnd(allowPageRequest: allowPageRequest);
    });
  }

  void _onNearScrollEnd({bool allowPageRequest = true}) {
    // Reuses the row count tracked during the last build; re-filtering and
    // re-sorting the source list on every scroll notification caused visible
    // jank near the end of large tables.
    final int totalSortedCount = _trackedSortedItemCount;
    if (_canRevealMoreItems(totalSortedCount)) {
      _revealMoreItems(totalSortedCount);
      // Keep revealing across frames while the user remains near the end so a
      // single scroll gesture does not stall after one batch.
      if (allowPageRequest) {
        _scheduleRevealIfNeeded();
      }
      return;
    }
    if (allowPageRequest) {
      _maybeRequestNextPage();
    }
  }

  String _currentQuery() {
    final AppListTableSearch<T>? search = widget.search;
    if (search != null) {
      return search.controller.text;
    }
    return widget.searchListenable?.value ?? '';
  }

  void _maybeRequestNextPage() {
    if (!_usesInfinitePagination) {
      return;
    }
    final AppPage<T>? page = widget.page;
    if (page == null) {
      return;
    }
    if (_pendingLoadMore || widget.isLoading) {
      return;
    }
    if (!page.hasNextPage) {
      return;
    }
    _pendingLoadMore = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
    widget.onPageChanged!(page.request.next());
  }

  @override
  Widget build(BuildContext context) {
    // Column keys are often unchanged across selection rebuilds, so
    // didUpdateWidget skips sync. Refresh builders here without notifying.
    widget.columnVisibilityController?.refreshColumnBuilders(
      columns: widget.columns,
      columnChoices: widget.columnChoices,
    );
    final AppListTableSearch<T>? resolvedSearch = widget.search;
    if (resolvedSearch == null) {
      final ValueListenable<String>? searchListenable = widget.searchListenable;
      if (searchListenable == null) {
        return _buildForQuery(context, query: '', searchBar: null);
      }

      return ValueListenableBuilder<String>(
        valueListenable: searchListenable,
        builder: (BuildContext context, String query, _) {
          return _buildForQuery(
            context,
            query: query,
            searchBar: null,
            usesExternalSearchListenable: true,
          );
        },
      );
    }

    final Widget searchBar = resolvedSearch.buildSearchBar(
      context,
      tableActions: _searchActions(context),
    );
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: resolvedSearch.controller,
      builder: (BuildContext context, TextEditingValue value, _) {
        return _buildForQuery(context, query: value.text, searchBar: searchBar);
      },
    );
  }

  Widget _buildForQuery(
    BuildContext context, {
    required String query,
    required Widget? searchBar,
    bool usesExternalSearchListenable = false,
  }) {
    final ({
      bool disablePagination,
      List<T> items,
      int totalSortedCount,
      AppPage<T>? page,
      int rowNumberOffset,
    })
    data = _visibleData(
      query,
      usesExternalSearchListenable: usesExternalSearchListenable,
    );
    final Widget content = _buildForItems(
      context,
      data.items,
      rowNumberOffset: data.rowNumberOffset,
    );
    final ThemeData theme = Theme.of(context);
    final bool loadingMore = _isLoadingMore(data.items.length);
    final Widget footer = _buildTableFooter(
      context,
      data.page,
      disablePagination: data.disablePagination,
      visibleItemCount: data.items.length,
      loadingMore: loadingMore,
    );
    final Widget? toolbar = _buildToolbar(context, searchBar);

    assert(() {
      if ((widget.title?.trim().isNotEmpty ?? false) ||
          (widget.description?.trim().isNotEmpty ?? false)) {
        debugPrint(
          'AppListTable title/description are deprecated. '
          'Move section copy to AppWorkspace or AppCollapsibleSection.',
        );
      }
      return true;
    }());

    // The Column/LayoutBuilder shell is kept even when the toolbar is currently
    // absent so swapping chrome at that slot does not remount the table body.
    // The footer is always mounted (status / pagination + go-to-top).
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool canExpand =
            !widget.shrinkWrap && constraints.hasBoundedHeight;

        final double toolbarGap =
            widget.toolbarContentGap ?? theme.spacing.xs;
        // Search bar and the action row below it are part of the scrolling
        // body, never pinned above it: the whole table scrolls as one. Only
        // the footer (status / pagination + go-to-top) stays put.
        final Widget scrollChild = toolbar == null
            ? content
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  toolbar,
                  if (toolbarGap > 0) SizedBox(height: toolbarGap),
                  content,
                ],
              );
        // With a toolbar the rows cannot own the vertical scroll (they would
        // scroll under a stationary search bar), so one scroll view wraps the
        // whole stack. Without one, the table body keeps its virtualized
        // scroller.
        final Widget body = _wrapIncrementalScroll(
          context,
          totalSortedCount: data.totalSortedCount,
          child: canExpand && toolbar != null
              ? Scrollbar(
                  controller: _toolbarScrollController,
                  child: SingleChildScrollView(
                    controller: _toolbarScrollController,
                    primary: false,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: scrollChild,
                  ),
                )
              : scrollChild,
        );
        return Column(
          mainAxisSize: canExpand ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (canExpand) Expanded(child: body) else body,
            footer,
          ],
        );
      },
    );
  }

  bool _isLoadingMore(int visibleItemCount) {
    return (widget.isLoading || _pendingLoadMore) &&
        visibleItemCount > 0 &&
        _usesInfinitePagination;
  }

  ({
    bool disablePagination,
    List<T> items,
    int totalSortedCount,
    AppPage<T>? page,
    int rowNumberOffset,
  })
  _visibleData(String query, {required bool usesExternalSearchListenable}) {
    final AppPage<T>? sourcePage = widget.page;
    final List<T> sourceItems = _usesInfinitePagination
        ? _accumulatedItems
        : sourcePage?.items ?? widget.items ?? <T>[];
    // In-place list mutations keep the same [List] identity, so also invalidate
    // when the item count changes (empty → selected rows is the common case).
    if (sourceItems.length != _lastSeenItemsLength) {
      _lastSeenItemsLength = sourceItems.length;
      _invalidateSortCache();
    }
    final String normalizedQuery = query.trim();
    List<T> visibleItems = sourceItems;

    if (normalizedQuery.isNotEmpty) {
      final AppListTableSearchMatcher<T>? matcher = usesExternalSearchListenable
          ? widget.searchMatcher
          : widget.search?.matcher ?? widget.searchMatcher;
      if (matcher != null) {
        visibleItems = _filteredItems(sourceItems, normalizedQuery, matcher);
      }
    }

    final List<T> sortedItems = _sortedItems(visibleItems);
    _syncRenderLimit(query, sortedItems.length);
    final List<T> renderedItems = _limitedVisibleItems(sortedItems);
    if (usesExternalSearchListenable &&
        normalizedQuery.isNotEmpty &&
        sourcePage != null) {
      return (
        disablePagination: true,
        items: renderedItems,
        totalSortedCount: sortedItems.length,
        rowNumberOffset: 0,
        page: AppPage<T>(
          items: renderedItems,
          request: sourcePage.request.first(),
          totalItemCount: sortedItems.length,
        ),
      );
    }

    final AppPage<T>? visiblePage =
        _usesInfinitePagination && sourcePage != null
        ? AppPage<T>(
            items: renderedItems,
            request: AppPageRequest(
              pageSize: math.max(renderedItems.length, 1),
            ),
            totalItemCount: sourcePage.totalItemCount,
          )
        : sourcePage;

    final int rowNumberOffset = _usesInfinitePagination
        ? 0
        : sourcePage?.request.offset ?? 0;

    return (
      disablePagination: false,
      items: renderedItems,
      totalSortedCount: sortedItems.length,
      page: visiblePage,
      rowNumberOffset: rowNumberOffset,
    );
  }

  void _syncRenderLimit(String query, int sortedItemCount) {
    final int batch = _effectiveRevealBatch;
    final int floor = math.min(batch, sortedItemCount);
    if (query != _trackedQuery) {
      // New search: restart from one batch.
      _trackedQuery = query;
      _trackedSortedItemCount = sortedItemCount;
      _renderLimit = floor;
      return;
    }
    if (sortedItemCount != _trackedSortedItemCount) {
      // Item count changed (page append / refresh): keep already revealed
      // rows mounted. Collapsing back to one batch reset the scroll extent
      // and forced a batch-by-batch re-reveal after every page load.
      _trackedSortedItemCount = sortedItemCount;
      final int current = _renderLimit ?? floor;
      _renderLimit = math.max(floor, math.min(current, sortedItemCount));
      return;
    }
    _renderLimit ??= floor;
  }

  /// Progressive mount/reveal batch: [maxVisibleItems] override or viewport estimate.
  int get _effectiveRevealBatch {
    final int? override = widget.maxVisibleItems;
    if (override != null && override > 0) {
      return override;
    }
    return _viewportBatchSize ?? _fallbackProgressiveBatch;
  }

  /// Whether rows are mounted in progressive batches.
  ///
  /// Bounded-height layouts virtualize row building through the scroll
  /// viewport instead, which keeps the full scroll extent available and lets
  /// a single fling reach any loaded row without waiting for batch reveals.
  /// Progressive mounting remains for shrink-wrapped/unbounded layouts (all
  /// children of an ancestor scroll view are always built) and for callers
  /// that force a cap through [AppListTable.maxVisibleItems].
  bool get _usesProgressiveRowMounting {
    return widget.maxVisibleItems != null || !_viewportDrivesRowMounting;
  }

  void _syncRowMountingStrategy({required bool boundedHeight}) {
    _lastLayoutHadBoundedHeight = boundedHeight;
    if (_viewportDrivesRowMounting == boundedHeight ||
        _rowMountingSyncScheduled) {
      return;
    }
    _rowMountingSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rowMountingSyncScheduled = false;
      if (!mounted ||
          _viewportDrivesRowMounting == _lastLayoutHadBoundedHeight) {
        return;
      }
      setState(() {
        _viewportDrivesRowMounting = _lastLayoutHadBoundedHeight;
        if (_viewportDrivesRowMounting && widget.maxVisibleItems == null) {
          _renderLimit = null;
        }
      });
    });
  }

  List<T> _limitedVisibleItems(List<T> items) {
    if (items.isEmpty) {
      return items;
    }
    if (!_usesProgressiveRowMounting) {
      // Virtualized layouts render the full list; the viewport only builds
      // the rows it needs.
      return items;
    }
    final int batch = _effectiveRevealBatch;
    final int renderCount = math.min(_renderLimit ?? batch, items.length);
    if (renderCount >= items.length) {
      return items;
    }
    return items.take(renderCount).toList(growable: false);
  }

  bool _canRevealMoreItems(int totalSortedCount) {
    if (totalSortedCount <= 0) {
      return false;
    }
    if (!_usesProgressiveRowMounting) {
      return false;
    }
    final int batch = _effectiveRevealBatch;
    return (_renderLimit ?? batch) < totalSortedCount;
  }

  void _revealMoreItems(int totalSortedCount) {
    final int batch = _effectiveRevealBatch;
    final int current = _renderLimit ?? batch;
    if (current >= totalSortedCount) {
      return;
    }
    setState(() {
      _renderLimit = math.min(current + batch, totalSortedCount);
    });
  }

  void _syncViewportBatchFromConstraints({
    required BoxConstraints constraints,
    required bool compact,
    required bool dense,
  }) {
    if (!_usesProgressiveRowMounting) {
      return;
    }
    if (!constraints.hasBoundedHeight) {
      return;
    }
    final double headingHeight = dense
        ? 32
        : compact
        ? 44
        : 48;
    final double rowMinHeight = dense
        ? 44
        : compact
        ? 48
        : 52;
    final int nextBatch = appListTableProgressiveBatchSize(
      maxVisibleItems: widget.maxVisibleItems,
      availableHeight: constraints.maxHeight,
      headingHeight: headingHeight,
      rowMinHeight: rowMinHeight,
    );
    if (_viewportBatchSize == nextBatch || _viewportSyncScheduled) {
      return;
    }
    _viewportSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportSyncScheduled = false;
      if (!mounted || _viewportBatchSize == nextBatch) {
        return;
      }
      setState(() {
        _viewportBatchSize = nextBatch;
        final int current = _renderLimit ?? _fallbackProgressiveBatch;
        if (current < nextBatch) {
          final int cap = _trackedSortedItemCount > 0
              ? _trackedSortedItemCount
              : nextBatch;
          _renderLimit = math.min(math.max(current, nextBatch), cap);
        }
      });
    });
  }

  Widget _wrapIncrementalScroll(
    BuildContext context, {
    required int totalSortedCount,
    required Widget child,
  }) {
    // Always mounted, even when there is currently nothing to reveal or load:
    // removing the listener when capabilities change would swap the widget
    // type at this slot and remount the whole table subtree, resetting the
    // scroll position (for example right after the last page loads).
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (ScrollMetricsNotification notification) {
        if (notification.metrics.axis != Axis.vertical) {
          return false;
        }
        _handleScrollMetrics(notification.metrics);
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification notification) {
          if (notification.metrics.axis != Axis.vertical) {
            return false;
          }
          if (notification is! ScrollUpdateNotification &&
              notification is! OverscrollNotification &&
              notification is! ScrollEndNotification) {
            return false;
          }
          _handleScrollMetrics(notification.metrics);
          return false;
        },
        child: child,
      ),
    );
  }

  Widget _buildForItems(
    BuildContext context,
    List<T> visibleItems, {
    required int rowNumberOffset,
  }) {
    final Object? resolvedError = widget.error;
    if (resolvedError != null && widget.errorBuilder != null) {
      return widget.errorBuilder!(context, resolvedError);
    }

    if (appListTableShowsInitialLoading(
      isLoading: widget.isLoading,
      visibleItems: visibleItems,
    )) {
      final Widget loading =
          widget.loadingBuilder?.call(context) ??
          const _DefaultListTableLoading();
      final Widget? surfaceHeader = widget.surfaceHeader;
      if (surfaceHeader == null) {
        return loading;
      }
      return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final ThemeData theme = Theme.of(context);
          final ColorScheme colorScheme = theme.colorScheme;
          final bool canExpand =
              !widget.shrinkWrap && constraints.hasBoundedHeight;
          return Material(
            color: colorScheme.surface,
            shape: RoundedRectangleBorder(
              side: theme.borders.side(),
            ),
            child: Column(
              mainAxisSize: canExpand ? MainAxisSize.max : MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                surfaceHeader,
                if (canExpand) Expanded(child: loading) else loading,
              ],
            ),
          );
        },
      );
    }

    if (visibleItems.isEmpty && widget.emptyBuilder != null) {
      final Widget empty = widget.emptyBuilder!(context);
      final Widget? surfaceHeader = widget.surfaceHeader;
      if (surfaceHeader == null) {
        return empty;
      }
      return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final ThemeData theme = Theme.of(context);
          final ColorScheme colorScheme = theme.colorScheme;
          final bool canExpand =
              !widget.shrinkWrap && constraints.hasBoundedHeight;
          return Material(
            color: colorScheme.surface,
            shape: RoundedRectangleBorder(
              side: theme.borders.side(),
            ),
            child: Column(
              mainAxisSize: canExpand ? MainAxisSize.max : MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                surfaceHeader,
                if (canExpand) Expanded(child: empty) else empty,
              ],
            ),
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool hasBoundedHeight = constraints.hasBoundedHeight;
        final bool effectiveShrinkWrap = widget.shrinkWrap || !hasBoundedHeight;
        final ScrollPhysics? effectivePhysics = hasBoundedHeight
            ? widget.physics
            : widget.physics ?? const NeverScrollableScrollPhysics();
        final List<AppListTableColumn<T>> visibleColumns = _visibleColumns;
        final bool compact =
            widget.forceCompact || _usesCompactTableLayout(constraints);
        _syncRowMountingStrategy(boundedHeight: !effectiveShrinkWrap);
        _syncViewportBatchFromConstraints(
          constraints: constraints,
          compact: compact,
          dense: widget.forceCompact,
        );
        final Map<String, double> resolvedWidths = _resolvedColumnWidths(
          constraints: constraints,
          visibleColumns: visibleColumns,
          compact: compact,
        );

        if (_usesListLayout(constraints)) {
          return _MobileListTable<T>(
            items: visibleItems,
            itemBuilder: widget.mobileItemBuilder,
            itemKeyBuilder: widget.itemKeyBuilder,
            rowsVersion: widget.rowsVersion,
            onRowSelected: widget.onRowSelected,
            shrinkWrap: effectiveShrinkWrap,
            physics: effectivePhysics,
            rowColorBuilder: widget.rowColorBuilder,
            rowNumberOffset: rowNumberOffset,
            showRowNumbers: widget.showRowNumbers,
            surfaceHeader: widget.surfaceHeader,
            goToTopController: _goToTopController,
          );
        }

        final bool padEmptyRows =
            widget.padEmptyRows ?? (hasBoundedHeight && !effectiveShrinkWrap);

        return _DesktopListTable<T>(
          items: visibleItems,
          columns: visibleColumns,
          itemKeyBuilder: widget.itemKeyBuilder,
          rowsVersion: widget.rowsVersion,
          onRowSelected: widget.onRowSelected,
          minWidth: constraints.hasBoundedWidth
              ? math.max(
                  constraints.maxWidth,
                  _columnsWidthTotal(resolvedWidths),
                )
              : _columnsWidthTotal(resolvedWidths),
          rowColorBuilder: widget.rowColorBuilder,
          compact: compact,
          dense: widget.forceCompact,
          horizontalMargin: widget.tableHorizontalMargin,
          sortColumnKey: _sortColumnKey,
          sortAscending: _sortAscending,
          onSort: _sortByColumn,
          rowNumberOffset: rowNumberOffset,
          showRowNumbers: widget.showRowNumbers,
          enableColumnResize: widget.enableColumnResize,
          scrollVertically: hasBoundedHeight,
          padEmptyRows: padEmptyRows,
          surfaceHeader: widget.surfaceHeader,
          goToTopController: _goToTopController,
          columnWidthFor: (AppListTableColumn<T> column) {
            return resolvedWidths[column.key] ??
                _columnWidthFor(column, compact: compact);
          },
          onColumnWidthChanged: widget.enableColumnResize
              ? _updateColumnWidth
              : null,
          onVerticalScrollMetrics: _handleScrollMetrics,
        );
      },
    );
  }

  Widget _buildTableFooter(
    BuildContext context,
    AppPage<T>? visiblePage, {
    required bool disablePagination,
    required int visibleItemCount,
    required bool loadingMore,
  }) {
    return _AppListTableFooterBar(
      goToTopLabel: widget.goToTopLabel,
      canGoToTopListenable: _goToTopController.canGoToTop,
      onGoToTop: _goToTopController.goToTop,
      loadingMore: loadingMore,
      loadingMoreLabel: widget.loadingMoreLabel,
      leading: _footerLeading(
        context,
        visiblePage,
        disablePagination: disablePagination,
        visibleItemCount: visibleItemCount,
      ),
    );
  }

  Widget? _footerLeading(
    BuildContext context,
    AppPage<T>? visiblePage, {
    required bool disablePagination,
    required int visibleItemCount,
  }) {
    final Widget? resolvedFooter = widget.footer;
    if (resolvedFooter != null) {
      return resolvedFooter;
    }

    if (visiblePage == null) {
      return null;
    }

    final bool showButtons =
        widget.paginationMode == AppListTablePaginationMode.buttons &&
        !disablePagination;
    final AppListTablePageLabelBuilder<T>? pageLabelBuilder =
        widget.pageLabelBuilder;
    final String? previousPageLabel = widget.previousPageLabel;
    final String? nextPageLabel = widget.nextPageLabel;

    if (showButtons) {
      if (pageLabelBuilder == null ||
          previousPageLabel == null ||
          nextPageLabel == null) {
        return null;
      }
      return _AppPaginationControls(
        pageRequest: widget.page!.request,
        hasPreviousPage: widget.page!.hasPreviousPage,
        hasNextPage: widget.page!.hasNextPage,
        pageLabel: pageLabelBuilder(widget.page!),
        previousPageLabel: previousPageLabel,
        nextPageLabel: nextPageLabel,
        onPageChanged: widget.onPageChanged,
      );
    }

    final bool showInfiniteChrome =
        _usesInfinitePagination ||
        (pageLabelBuilder != null && visibleItemCount > 0);
    if (!showInfiniteChrome) {
      return null;
    }

    final bool hasMore = widget.page?.hasNextPage ?? false;
    final String? statusLabel = pageLabelBuilder == null
        ? null
        : pageLabelBuilder(visiblePage);
    final bool reachedEnd =
        _usesInfinitePagination && !hasMore && visibleItemCount > 0;

    // Load-more chrome is overlaid on the table body; footer status only shows
    // range / end-of-list copy so it does not look like an extra row.
    if (statusLabel == null && !reachedEnd) {
      return null;
    }

    return _AppInfiniteScrollFooter(
      statusLabel: statusLabel,
      reachedEnd: reachedEnd,
      allRowsLoadedLabel: widget.allRowsLoadedLabel,
    );
  }

  bool _usesListLayout(BoxConstraints constraints) {
    return switch (widget.displayMode) {
      AppListTableDisplayMode.list => true,
      AppListTableDisplayMode.table => false,
      AppListTableDisplayMode.adaptive =>
        switch (AppBreakpoints.fromConstraints(constraints)) {
          AppBreakpoint.xs || AppBreakpoint.sm => true,
          _ => false,
        },
    };
  }

  bool _usesCompactTableLayout(BoxConstraints constraints) {
    return AppBreakpoints.fromConstraints(constraints) == AppBreakpoint.md;
  }

  double _columnsWidthTotal(Map<String, double> widths) {
    double total = widget.showRowNumbers ? _rowNumberColumnWidth : 0;
    for (final double width in widths.values) {
      total += width;
    }
    return total;
  }

  Map<String, double> _resolvedColumnWidths({
    required BoxConstraints constraints,
    required List<AppListTableColumn<T>> visibleColumns,
    required bool compact,
  }) {
    final Map<String, double> widths = <String, double>{
      for (final AppListTableColumn<T> column in visibleColumns)
        column.key: _columnWidthFor(column, compact: compact),
    };
    if (!constraints.hasBoundedWidth || visibleColumns.isEmpty) {
      return widths;
    }

    final ThemeData theme = Theme.of(context);
    final double horizontalMargin =
        widget.tableHorizontalMargin ??
        (widget.forceCompact
            ? theme.spacing.xs
            : compact
            ? theme.spacing.sm
            : theme.spacing.md);
    final double columnSpacing = widget.forceCompact
        ? theme.spacing.xs
        : compact
        ? theme.spacing.sm
        : theme.spacing.lg;
    final int columnCount =
        visibleColumns.length + (widget.showRowNumbers ? 1 : 0);
    final double chrome =
        (horizontalMargin * 2) +
        (columnCount > 1 ? columnSpacing * (columnCount - 1) : 0);
    final double baseTotal = _columnsWidthTotal(widths);
    final double extra = constraints.maxWidth - chrome - baseTotal;
    if (extra <= 0) {
      return widths;
    }

    AppListTableColumn<T>? expandable;
    for (final AppListTableColumn<T> column in visibleColumns.reversed) {
      if (column.fixedWidth == null) {
        expandable = column;
        break;
      }
    }
    if (expandable == null) {
      return widths;
    }
    widths[expandable.key] = widths[expandable.key]! + extra;
    return widths;
  }

  List<T> _filteredItems(
    List<T> sourceItems,
    String query,
    AppListTableSearchMatcher<T> matcher,
  ) {
    final String normalizedQuery = _normalizeTableSearchQuery(query);
    if (normalizedQuery.isEmpty) {
      return sourceItems;
    }
    final List<String> tokens = _tableSearchTokens(normalizedQuery);

    return sourceItems
        .where(
          (T item) =>
              matcher(item, normalizedQuery) ||
              (tokens.length > 1 &&
                  tokens.every((String token) => matcher(item, token))),
        )
        .toList(growable: false);
  }

  List<T> _sortedItems(List<T> sourceItems) {
    final String? sortColumnKey = _sortColumnKey;
    // The source is already ordered by whoever answers [onSortChanged].
    if (sortColumnKey == null || widget.onSortChanged != null) {
      return sourceItems;
    }

    final AppListTableColumn<T>? column = _columnByKey(
      _availableColumns,
      sortColumnKey,
    );
    if (column == null || !column.isSortable) {
      return sourceItems;
    }

    // Length must be part of the cache key: callers often mutate the same
    // List instance in place (clear/addAll), which keeps [identical] true.
    if (identical(sourceItems, _cachedSortSource) &&
        _cachedSortedItems != null &&
        _cachedSortedItems!.length == sourceItems.length &&
        _cachedSortColumnKey == sortColumnKey &&
        _cachedSortAscending == _sortAscending) {
      return _cachedSortedItems!;
    }

    final List<T> sortedItems = List<T>.of(sourceItems);
    final AppListTableSortComparator<T>? comparator = column.sortComparator;
    if (comparator != null) {
      sortedItems.sort((T left, T right) {
        final int result = comparator(left, right);
        return _sortAscending ? result : -result;
      });
    } else {
      final List<Object?> sortKeys = <Object?>[
        for (final T item in sortedItems)
          appListTableResolveSortKey<T>(
            column: column,
            item: item,
            context: context,
          ),
      ];
      final List<int> indices = List<int>.generate(
        sortedItems.length,
        (int index) => index,
      );
      indices.sort((int leftIndex, int rightIndex) {
        final int result = appListTableCompareSortValues(
          sortKeys[leftIndex],
          sortKeys[rightIndex],
        );
        return _sortAscending ? result : -result;
      });
      for (int index = 0; index < indices.length; index += 1) {
        sortedItems[index] = sourceItems[indices[index]];
      }
    }

    _cachedSortSource = sourceItems;
    _cachedSortColumnKey = sortColumnKey;
    _cachedSortAscending = _sortAscending;
    _cachedSortedItems = sortedItems;
    return sortedItems;
  }

  void _invalidateSortCache() {
    _cachedSortSource = null;
    _cachedSortColumnKey = null;
    _cachedSortAscending = null;
    _cachedSortedItems = null;
  }

  bool _sameColumnIdentity(
    List<AppListTableColumn<T>> left,
    List<AppListTableColumn<T>> right,
  ) {
    if (identical(left, right)) {
      return true;
    }
    if (left.length != right.length) {
      return false;
    }
    for (int index = 0; index < left.length; index += 1) {
      final AppListTableColumn<T> a = left[index];
      final AppListTableColumn<T> b = right[index];
      if (a.key != b.key ||
          a.label != b.label ||
          a.isSortable != b.isSortable ||
          a.alwaysVisible != b.alwaysVisible ||
          a.numeric != b.numeric) {
        return false;
      }
    }
    return true;
  }

  /// Search bar plus, when the caller supplies extra actions, the wrapping
  /// action row rendered directly beneath it.
  Widget? _buildToolbar(BuildContext context, Widget? searchBar) {
    final AppListTableSearch<T>? search = widget.search;
    final List<AppSearchBarAction> extraActions =
        search?.trailingActions ?? const <AppSearchBarAction>[];
    if (extraActions.isEmpty) {
      return searchBar;
    }

    final Widget actionBar = _AppListTableActionBar(
      actions: extraActions,
      enabled: (search?.enabled ?? true) && !(search?.isLoading ?? false),
    );
    if (searchBar == null) {
      return actionBar;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        searchBar,
        SizedBox(height: Theme.of(context).spacing.xs),
        actionBar,
      ],
    );
  }

  List<AppSearchBarAction> _searchActions(BuildContext context) {
    // Search bar chrome only: Filters (in AppSearchBar) → Settings → Export →
    // Print. Settings / Print are desktop-only (lg+); mobile and tablet keep
    // Filters / Export so the compact search chrome stays usable.
    final bool showDesktopChrome =
        AppBreakpoints.of(context).index >= AppBreakpoint.lg.index;
    final List<AppSearchBarAction> actions = <AppSearchBarAction>[];
    if (showDesktopChrome && _availableColumns.length > 1) {
      actions.add(
        AppSearchBarAction(
          icon: Icons.settings_outlined,
          label: _columnVisibilityLabel,
          tooltip: _columnVisibilityLabel,
          active: _hasCustomColumnVisibility,
          onPressed: _openColumnVisibilityDialog,
        ),
      );
    }
    if (widget.enableExport && widget.canExport) {
      actions.add(
        AppSearchBarAction(
          icon: AppActionIcons.export,
          label: _exportLabel,
          tooltip: _exportLabel,
          onPressed: _openExportDialog,
        ),
      );
    }
    if (showDesktopChrome &&
        widget.enablePrint &&
        widget.canPrint &&
        widget.onPrint != null) {
      actions.add(
        AppSearchBarAction(
          icon: AppActionIcons.print,
          label: _printLabel,
          tooltip: _printLabel,
          onPressed: () {
            unawaited(_handlePrint());
          },
        ),
      );
    }
    return actions;
  }

  Future<void> _handlePrint() async {
    if (!widget.enablePrint || !widget.canPrint || widget.onPrint == null) {
      return;
    }
    final AppListTableMatchingItemsLoader<T>? loader = _matchingItemsLoader;
    final bool showLoading = loader != null;
    if (showLoading && mounted) {
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) {
            return PopScope(
              canPop: false,
              child: Center(
                child: AppLoadingIndicator(
                  size: AppLoadingIndicatorSize.compact,
                  expand: false,
                  title: dialogContext.l10n.commonLoadingTitle,
                ),
              ),
            );
          },
        ),
      );
    }
    try {
      final List<T> items = await _resolveMatchingItems();
      if (showLoading && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (!mounted) {
        return;
      }
      await widget.onPrint!(items);
    } catch (_) {
      if (showLoading && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (!mounted) {
        return;
      }
      final String message =
          widget.printFailureMessage ??
          context.l10n.commonTablePrintFailureMessage;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  AppListTableMatchingItemsLoader<T>? get _matchingItemsLoader {
    return widget.loadMatchingItems ?? widget.exportConfig?.loadMatchingItems;
  }

  Future<List<T>> _resolveMatchingItems() async {
    final AppListTableMatchingItemsLoader<T>? loader = _matchingItemsLoader;
    if (loader != null) {
      return loader();
    }
    final List<T>? overrideItems = widget.exportConfig?.items;
    if (overrideItems != null) {
      return overrideItems;
    }
    return _exportRows();
  }

  Future<void> _openExportDialog() async {
    if (!widget.enableExport || !widget.canExport) {
      return;
    }

    final List<T> rows = _exportRows();
    await showAppListTableExportDialog<T>(
      context: context,
      columns: _availableColumns,
      visibleColumnKeys: _visibleColumns
          .map((AppListTableColumn<T> column) => column.key)
          .toSet(),
      rows: rows,
      config: _resolvedExportConfig(),
      title: widget.exportDialogTitle,
      exportLabel: widget.exportLabel,
      cancelLabel: widget.exportCancelLabel,
      columnsSectionLabel: widget.exportColumnsSectionLabel,
      filtersSectionLabel: widget.exportFiltersSectionLabel,
      emptyColumnsMessage: widget.exportEmptyColumnsMessage,
      emptyRowsMessage: widget.exportEmptyRowsMessage,
      successMessage: widget.exportSuccessMessage,
      failureMessage: widget.exportFailureMessage,
      invalidDateMessage: widget.exportInvalidDateMessage,
    );
  }

  List<T> _exportRows() {
    final AppListTableExportConfig<T>? config = widget.exportConfig;
    final List<T>? overrideItems = config?.items;
    if (overrideItems != null) {
      return overrideItems;
    }

    final String query = _currentQuery();
    final AppPage<T>? sourcePage = widget.page;
    final List<T> sourceItems = _usesInfinitePagination
        ? _accumulatedItems
        : sourcePage?.items ?? widget.items ?? <T>[];
    List<T> visibleItems = sourceItems;
    final String normalizedQuery = query.trim();
    if (normalizedQuery.isNotEmpty) {
      final AppListTableSearchMatcher<T>? matcher =
          widget.search?.matcher ?? widget.searchMatcher;
      if (matcher != null) {
        visibleItems = _filteredItems(sourceItems, normalizedQuery, matcher);
      }
    }
    return _sortedItems(visibleItems);
  }

  AppListTableExportConfig<T> _resolvedExportConfig() {
    final AppListTableExportConfig<T> config =
        widget.exportConfig ?? AppListTableExportConfig<T>();
    final AppListTableSearch<T>? search = widget.search;
    final AppListTableMatchingItemsLoader<T>? loader =
        widget.loadMatchingItems ?? config.loadMatchingItems;
    if (search == null) {
      if (identical(loader, config.loadMatchingItems)) {
        return config;
      }
      return AppListTableExportConfig<T>(
        fileNameStem: config.fileNameStem,
        sheetName: config.sheetName,
        enableDateFilter: config.enableDateFilter,
        filterGroups: config.filterGroups,
        textFilters: config.textFilters,
        initialFilterValue: config.initialFilterValue,
        rowFilter: config.rowFilter,
        dateOf: config.dateOf,
        items: config.items,
        loadMatchingItems: loader,
        saver: config.saver,
        firstDate: config.firstDate,
        lastDate: config.lastDate,
        currentDate: config.currentDate,
        dateFilterLabel: config.dateFilterLabel,
        dateFromLabel: config.dateFromLabel,
        dateToLabel: config.dateToLabel,
        datePickerButtonLabel: config.datePickerButtonLabel,
        invalidDateMessage: config.invalidDateMessage,
        allFieldsLabel: config.allFieldsLabel,
      );
    }
    return AppListTableExportConfig<T>(
      fileNameStem: config.fileNameStem,
      sheetName: config.sheetName,
      enableDateFilter: config.enableDateFilter && search.enableDateFilter,
      filterGroups: config.filterGroups.isNotEmpty
          ? config.filterGroups
          : search.filterGroups,
      textFilters: config.textFilters.isNotEmpty
          ? config.textFilters
          : search.textFilters,
      initialFilterValue: config.initialFilterValue.isActive
          ? config.initialFilterValue
          : search.filterValue,
      rowFilter: config.rowFilter,
      dateOf: config.dateOf,
      items: config.items,
      loadMatchingItems: widget.loadMatchingItems ?? config.loadMatchingItems,
      saver: config.saver,
      firstDate: config.firstDate ?? search.firstDate,
      lastDate: config.lastDate ?? search.lastDate,
      currentDate: config.currentDate ?? search.currentDate,
      dateFilterLabel: config.dateFilterLabel ?? search.dateFilterLabel,
      dateFromLabel: config.dateFromLabel ?? search.dateFromLabel,
      dateToLabel: config.dateToLabel ?? search.dateToLabel,
      datePickerButtonLabel:
          config.datePickerButtonLabel ?? search.datePickerButtonLabel,
      invalidDateMessage:
          config.invalidDateMessage ?? search.invalidDateMessage,
      allFieldsLabel: config.allFieldsLabel ?? search.allFieldsLabel,
    );
  }

  String get _exportLabel => widget.exportLabel ?? 'Export';

  String get _printLabel => widget.printLabel ?? 'Print';

  List<AppListTableColumn<T>> get _availableColumns {
    return _availableColumnsFor(widget.columns, widget.columnChoices);
  }

  List<AppListTableColumn<T>> get _visibleColumns {
    final AppListTableColumnVisibilityController<T>? controller =
        widget.columnVisibilityController;
    if (controller != null) {
      return controller.visibleColumns;
    }

    final List<AppListTableColumn<T>> availableColumns = _availableColumns;
    final List<AppListTableColumn<T>> visibleColumns = availableColumns
        .where(
          (AppListTableColumn<T> column) =>
              column.alwaysVisible || _visibleColumnKeys.contains(column.key),
        )
        .toList(growable: false);
    if (visibleColumns.isNotEmpty || availableColumns.isEmpty) {
      return visibleColumns;
    }
    return _defaultVisibleColumns(availableColumns);
  }

  bool get _hasCustomColumnVisibility {
    final AppListTableColumnVisibilityController<T>? controller =
        widget.columnVisibilityController;
    if (controller != null) {
      return controller.hasCustomColumnVisibility;
    }
    return !setEquals(_visibleColumnKeys, _defaultColumnKeys);
  }

  Set<String> get _defaultColumnKeys {
    return _defaultVisibleColumns(
      _availableColumns,
    ).map((AppListTableColumn<T> column) => column.key).toSet();
  }

  List<AppListTableColumn<T>> _defaultVisibleColumns(
    List<AppListTableColumn<T>> availableColumns,
  ) {
    return appListTableDefaultVisibleColumns(
      availableColumns,
      defaultColumns: widget.columns,
    );
  }

  void _syncVisibleColumns() {
    final AppListTableColumnVisibilityController<T>? controller =
        widget.columnVisibilityController;
    final String? storageKey = _resolvedColumnVisibilityStorageKey();
    if (controller != null) {
      controller.syncColumns(
        columns: widget.columns,
        columnChoices: widget.columnChoices,
        storageKey: storageKey,
      );
      return;
    }

    final List<AppListTableColumn<T>> availableColumns = _availableColumns;
    final Set<String> availableKeys = availableColumns
        .map((AppListTableColumn<T> column) => column.key)
        .toSet();
    final Set<String> next = _visibleColumnKeys
        .where(availableKeys.contains)
        .toSet();

    if (next.isEmpty) {
      final Set<String>? savedKeys = storageKey == null
          ? null
          : AppListTableColumnVisibilityMemory.instance.read(storageKey);
      if (savedKeys != null) {
        final Set<String> restoredKeys = savedKeys
            .where(availableKeys.contains)
            .toSet();
        if (restoredKeys.isNotEmpty) {
          next.addAll(_withAlwaysVisibleColumnKeys(restoredKeys));
        } else {
          next.addAll(_defaultColumnKeys);
        }
      } else {
        next.addAll(_defaultColumnKeys);
      }
    }

    _visibleColumnKeys = next;
    final String? sortColumnKey = _sortColumnKey;
    if (sortColumnKey != null && !_visibleColumnKeys.contains(sortColumnKey)) {
      _sortColumnKey = null;
      _sortAscending = true;
      _ensureDefaultSortColumn();
    }
  }

  void _ensureDefaultSortColumn() {
    if (_sortColumnKey != null) {
      return;
    }

    final String? preferredKey = widget.initialSortColumnKey;
    if (preferredKey != null) {
      final AppListTableColumn<T>? preferred = _columnByKey(
        _visibleColumns,
        preferredKey,
      );
      if (preferred != null && preferred.isSortable) {
        _sortColumnKey = preferred.key;
        _sortAscending = widget.initialSortAscending;
        return;
      }
    }

    // Keep source order until the user sorts, unless a column opts into an
    // explicit comparator (legacy auto-sort) or [initialSortColumnKey] is set.
    for (final AppListTableColumn<T> column in _visibleColumns) {
      if (column.isSortable && column.sortComparator != null) {
        _sortColumnKey = column.key;
        _sortAscending = widget.initialSortAscending;
        return;
      }
    }
  }

  AppListTableColumn<T>? _columnByKey(
    List<AppListTableColumn<T>> columns,
    String key,
  ) {
    for (final AppListTableColumn<T> column in columns) {
      if (column.key == key) {
        return column;
      }
    }
    return null;
  }

  void _sortByColumn(AppListTableColumn<T> column) {
    if (!column.isSortable) {
      return;
    }

    setState(() {
      if (_sortColumnKey == column.key) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumnKey = column.key;
        _sortAscending = true;
      }
      // Keep prior cache until the next _sortedItems call rebuilds it for the
      // new direction/column; clear so we never show a stale order.
      _invalidateSortCache();
    });
    widget.onSortChanged?.call(column.key, _sortAscending);
  }

  Future<void> _openColumnVisibilityDialog() async {
    final Future<void> Function()? customSettings = widget.onSettingsPressed;
    if (customSettings != null) {
      await customSettings();
      return;
    }

    final AppListTableColumnVisibilityController<T>? controller =
        widget.columnVisibilityController;
    final String? storageKey = _resolvedColumnVisibilityStorageKey();
    if (controller != null) {
      await controller.openColumnVisibilityDialog(
        context,
        title: widget.columnVisibilityTitle,
        applyLabel: widget.columnVisibilityApplyLabel,
        resetLabel: widget.columnVisibilityResetLabel,
        closeLabel: widget.columnVisibilityCloseLabel,
        storageKey: storageKey,
      );
      return;
    }

    final Set<String>? value = await showAppDialog<Set<String>>(
      context: context,
      builder: (_) => _ColumnVisibilityDialog<T>(
        columns: _availableColumns,
        visibleColumnKeys: _visibleColumnKeys,
        defaultColumnKeys: _defaultColumnKeys,
        title: widget.columnVisibilityTitle ?? 'Table columns',
        applyLabel: widget.columnVisibilityApplyLabel ?? 'Apply columns',
        resetLabel: widget.columnVisibilityResetLabel ?? 'Reset columns',
        closeLabel: widget.columnVisibilityCloseLabel ?? 'Close',
      ),
    );
    if (!mounted || value == null) {
      return;
    }

    setState(() {
      _visibleColumnKeys = _withAlwaysVisibleColumnKeys(value);
      final String? sortColumnKey = _sortColumnKey;
      if (sortColumnKey != null &&
          !_visibleColumnKeys.contains(sortColumnKey)) {
        _sortColumnKey = null;
        _sortAscending = true;
      }
    });
    _persistVisibleColumnKeys(storageKey);
  }

  String? _resolvedColumnVisibilityStorageKey() {
    final String? explicitKey = widget.columnVisibilityStorageKey;
    if (explicitKey != null) {
      return explicitKey;
    }
    if (widget.columnVisibilityController?.storageKey != null) {
      return widget.columnVisibilityController!.storageKey;
    }
    return appListTableColumnVisibilityStorageKey(
      widget.columns,
      widget.columnChoices,
    );
  }

  void _persistVisibleColumnKeys(String? storageKey) {
    if (storageKey == null) {
      return;
    }
    AppListTableColumnVisibilityMemory.instance.write(
      storageKey,
      _visibleColumnKeys,
    );
  }

  String get _columnVisibilityLabel {
    return widget.columnVisibilityLabel ?? 'Settings';
  }

  Set<String> _withAlwaysVisibleColumnKeys(Set<String> keys) {
    return <String>{
      ...keys,
      for (final AppListTableColumn<T> column in _availableColumns)
        if (column.alwaysVisible) column.key,
    };
  }
}

final RegExp _whitespaceRun = RegExp(r'\s+');

String _normalizeTableSearchQuery(String query) {
  return query.trim().replaceAll(_whitespaceRun, ' ');
}

List<String> _tableSearchTokens(String query) {
  final String normalized = _normalizeTableSearchQuery(query);
  if (normalized.isEmpty) {
    return const <String>[];
  }
  return normalized
      .split(' ')
      .where((String token) => token.isNotEmpty)
      .toList(growable: false);
}

class _ColumnVisibilityDialog<T> extends StatefulWidget {
  const _ColumnVisibilityDialog({
    required this.columns,
    required this.visibleColumnKeys,
    required this.defaultColumnKeys,
    required this.title,
    required this.applyLabel,
    required this.resetLabel,
    required this.closeLabel,
  });

  final List<AppListTableColumn<T>> columns;
  final Set<String> visibleColumnKeys;
  final Set<String> defaultColumnKeys;
  final String title;
  final String applyLabel;
  final String resetLabel;
  final String closeLabel;

  @override
  State<_ColumnVisibilityDialog<T>> createState() =>
      _ColumnVisibilityDialogState<T>();
}

class _ColumnVisibilityDialogState<T>
    extends State<_ColumnVisibilityDialog<T>> {
  late Set<String> _visibleColumnKeys;

  @override
  void initState() {
    super.initState();
    _visibleColumnKeys = Set<String>.of(widget.visibleColumnKeys);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return AppDialog(
      title: Text(widget.title),
      icon: const Icon(Icons.settings_outlined),
      maxWidth: 480,
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var index = 0; index < widget.columns.length; index++) ...<
            Widget
          >[
            if (index > 0) SizedBox(height: theme.spacing.xs),
            Builder(
              builder: (BuildContext context) {
                final AppListTableColumn<T> column = widget.columns[index];
                final bool isChecked =
                    column.alwaysVisible ||
                    _visibleColumnKeys.contains(column.key);
                final bool canChange =
                    !column.alwaysVisible &&
                    (!isChecked || _visibleColumnKeys.length > 1);

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: canChange
                        ? () {
                            setState(() {
                              final Set<String> next = Set<String>.of(
                                _visibleColumnKeys,
                              );
                              if (isChecked) {
                                next.remove(column.key);
                              } else {
                                next.add(column.key);
                              }
                              _visibleColumnKeys = next;
                            });
                          }
                        : null,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: isChecked
                            ? colorScheme.primaryContainer.withValues(
                                alpha: 0.28,
                              )
                            : colorScheme.surface,
                        border: isChecked
                            ? theme.borders.all(tone: AppBorderTone.selected)
                            : theme.borders.all(),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: theme.spacing.xs,
                          vertical: theme.spacing.xs,
                        ),
                        child: Row(
                          children: <Widget>[
                            Checkbox(
                              value: isChecked,
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              onChanged: canChange
                                  ? (bool? value) {
                                      setState(() {
                                        final Set<String> next = Set<String>.of(
                                          _visibleColumnKeys,
                                        );
                                        if (value ?? false) {
                                          next.add(column.key);
                                        } else {
                                          next.remove(column.key);
                                        }
                                        _visibleColumnKeys = next;
                                      });
                                    }
                                  : null,
                            ),
                            Icon(
                              Icons.view_column_outlined,
                              size: theme.appTokens.listIconSize * 0.9,
                              color: isChecked
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                            SizedBox(width: theme.spacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    column.label,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: AppFontWeight.emphasis,
                                    ),
                                  ),
                                  if (column.tooltip != null)
                                    Text(
                                      column.tooltip!,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color:
                                                colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
      actions: <Widget>[
        AppButton.tertiary(
          label: widget.resetLabel,
          leadingIcon: Icons.restart_alt,
          onPressed: () {
            setState(() {
              _visibleColumnKeys = Set<String>.of(widget.defaultColumnKeys);
            });
          },
        ),
        AppButton.primary(
          label: widget.applyLabel,
          leadingIcon: Icons.check,
          onPressed: () {
            Navigator.of(context).pop(_visibleColumnKeys);
          },
        ),
        AppButton.close(
          label: widget.closeLabel,
          leadingIcon: Icons.close,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _AppPaginationControls extends StatelessWidget {
  const _AppPaginationControls({
    required this.pageRequest,
    required this.hasPreviousPage,
    required this.hasNextPage,
    required this.pageLabel,
    required this.previousPageLabel,
    required this.nextPageLabel,
    required this.onPageChanged,
  });

  final AppPageRequest pageRequest;
  final bool hasPreviousPage;
  final bool hasNextPage;
  final String pageLabel;
  final String previousPageLabel;
  final String nextPageLabel;
  final ValueChanged<AppPageRequest>? onPageChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      children: <Widget>[
        Flexible(
          child: Text(
            pageLabel,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ),
          SizedBox(width: theme.spacing.sm),
          AppButton(
            iconOnly: true,
            leadingIcon: Icons.chevron_left,
            label: previousPageLabel,
            semanticLabel: previousPageLabel,
            tooltip: previousPageLabel,
            onPressed: hasPreviousPage && onPageChanged != null
                ? () {
                    onPageChanged!(pageRequest.previous());
                  }
                : null,
          ),
          AppButton(
            iconOnly: true,
            leadingIcon: Icons.chevron_right,
            label: nextPageLabel,
            semanticLabel: nextPageLabel,
            tooltip: nextPageLabel,
            onPressed: hasNextPage && onPageChanged != null
                ? () {
                    onPageChanged!(pageRequest.next());
                  }
                : null,
          ),
      ],
    );
  }
}

class _AppInfiniteScrollFooter extends StatelessWidget {
  const _AppInfiniteScrollFooter({
    required this.statusLabel,
    required this.reachedEnd,
    required this.allRowsLoadedLabel,
  });

  final String? statusLabel;
  final bool reachedEnd;
  final String allRowsLoadedLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Row(
      children: <Widget>[
        if (statusLabel != null)
          Expanded(
            child: Text(
              statusLabel!,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: AppFontWeight.regular,
              ),
            ),
          )
        else
          const Spacer(),
        if (reachedEnd)
          Text(
            allRowsLoadedLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
      ],
    );
  }
}

class _AppListTableFooterBar extends StatelessWidget {
  const _AppListTableFooterBar({
    required this.goToTopLabel,
    required this.canGoToTopListenable,
    required this.onGoToTop,
    required this.loadingMore,
    required this.loadingMoreLabel,
    this.leading,
  });

  final String goToTopLabel;
  final ValueListenable<bool> canGoToTopListenable;
  final Future<void> Function() onGoToTop;
  final bool loadingMore;
  final String loadingMoreLabel;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // The bar is exactly as tall as the controls in it. The table body above
    // already ends in the horizontal scrollbar gutter, so padding here would
    // only push the pagination away from the rows it belongs to.
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: leading ?? const SizedBox.shrink()),
            SizedBox(width: theme.spacing.sm),
            ValueListenableBuilder<bool>(
              valueListenable: canGoToTopListenable,
              builder: (BuildContext context, bool canGoToTop, _) {
                return AppButton(
                  iconOnly: true,
                  dense: true,
                  leadingIcon: Icons.vertical_align_top,
                  label: goToTopLabel,
                  semanticLabel: goToTopLabel,
                  tooltip: goToTopLabel,
                  onPressed: canGoToTop
                      ? () {
                          unawaited(onGoToTop());
                        }
                      : null,
                );
              },
            ),
          ],
        ),
        if (loadingMore)
          IgnorePointer(
            child: _AppListTableLoadingDots(
              semanticLabel: loadingMoreLabel,
            ),
          ),
      ],
    );
  }
}

/// Compact three-dot pulse used only for infinite-scroll "load more" in the
/// table footer. Initial / empty-body loads keep [AppLoadingIndicator].
class _AppListTableLoadingDots extends StatefulWidget {
  const _AppListTableLoadingDots({required this.semanticLabel});

  final String semanticLabel;

  @override
  State<_AppListTableLoadingDots> createState() =>
      _AppListTableLoadingDotsState();
}

class _AppListTableLoadingDotsState extends State<_AppListTableLoadingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final Color base = colorScheme.primary;

    return Semantics(
      label: widget.semanticLabel,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(theme.radius.full),
          border: theme.borders.all(),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: theme.spacing.md,
            vertical: theme.spacing.sm,
          ),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (BuildContext context, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (int index = 0; index < 3; index += 1) ...<Widget>[
                    if (index > 0) SizedBox(width: theme.spacing.sm),
                    _AppListTableLoadingDot(
                      progress: _controller.value,
                      phase: index / 3,
                      color: base,
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AppListTableLoadingDot extends StatelessWidget {
  const _AppListTableLoadingDot({
    required this.progress,
    required this.phase,
    required this.color,
  });

  final double progress;
  final double phase;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final double wave = (progress + phase) % 1.0;
    final double t = wave < 0.5 ? wave * 2 : (1 - wave) * 2;
    final double eased = Curves.easeInOut.transform(t);
    final double opacity = 0.45 + (0.55 * eased);
    final double scale = 0.75 + (0.55 * eased);

    return Transform.scale(
      scale: scale,
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: color.withValues(alpha: opacity),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _MobileListTable<T> extends StatelessWidget {
  const _MobileListTable({
    required this.items,
    required this.itemBuilder,
    required this.itemKeyBuilder,
    this.rowsVersion,
    required this.onRowSelected,
    required this.shrinkWrap,
    required this.physics,
    required this.rowColorBuilder,
    this.rowNumberOffset = 0,
    this.showRowNumbers = true,
    this.surfaceHeader,
    required this.goToTopController,
  });

  final List<T> items;
  final AppListTableMobileItemBuilder<T> itemBuilder;
  final AppListTableItemKeyBuilder<T>? itemKeyBuilder;
  final Object? rowsVersion;
  final ValueChanged<T>? onRowSelected;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final AppListTableRowColorBuilder<T>? rowColorBuilder;
  final int rowNumberOffset;
  final bool showRowNumbers;
  final Widget? surfaceHeader;
  final _AppListTableGoToTopController goToTopController;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    // Tinted rows need a surface gutter so adjacent pastel bands stay legible
    // as separate rows; plain lists get a single inset hairline instead, which
    // is both tidier and shorter.
    final bool usesTintedRows = rowColorBuilder != null;
    // Aligns the hairline with the row content: past the row-number lane, or a
    // small text inset when numbers are hidden.
    final double separatorIndent = showRowNumbers
        ? _mobileRowNumberColumnWidth
        : theme.spacing.md;

    // Same bordered surface the desktop table (and the mobile empty/loading
    // states) use, so the list reads as one contained card on phones.
    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        side: theme.borders.side(),
      ),
      child: _GoToTopHost(
        controller: goToTopController,
        headerExtent: 56,
        builder: (BuildContext context, Key headerKey) {
          return ListView.separated(
            itemCount: items.length + (surfaceHeader == null ? 0 : 1),
            shrinkWrap: shrinkWrap,
            physics: physics,
            padding: EdgeInsets.zero,
            itemBuilder: (BuildContext context, int index) {
              if (surfaceHeader != null && index == 0) {
                return KeyedSubtree(key: headerKey, child: surfaceHeader!);
              }
              final int itemIndex = surfaceHeader == null ? index : index - 1;
              final T item = items[itemIndex];
              Widget row = KeyedSubtree(
                key: appListTableUniqueRowKey<T>(
                  index: itemIndex,
                  itemKeyBuilder: itemKeyBuilder,
                  item: item,
                  rowsVersion: rowsVersion,
                ),
                child: showRowNumbers
                    ? _NumberedMobileListItem(
                        number: rowNumberOffset + itemIndex + 1,
                        child: itemBuilder(context, item),
                      )
                    : itemBuilder(context, item),
              );

              if (onRowSelected != null) {
                row = _SelectableMobileDataRow<T>(
                  item: item,
                  onSelected: onRowSelected!,
                  child: row,
                );
              }

              final Color? rowColor = rowColorBuilder?.call(context, item);
              // Each row owns its Material so tap ink paints above the status
              // tint instead of being hidden underneath it.
              row = rowColor == null
                  ? Material(type: MaterialType.transparency, child: row)
                  : DecoratedBox(
                      // Foreground so the rail is not overpainted by the row's
                      // own opaque Material fill.
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(
                        border: Border(
                          // Soft left rail keeps status tint readable as a
                          // distinct row even when adjacent pastels are similar.
                          left: theme.borders.side(
                            color: Color.alphaBlend(
                              colorScheme.onSurface.withValues(alpha: 0.14),
                              rowColor,
                            ),
                            width: 3,
                          ),
                        ),
                      ),
                      child: Material(color: rowColor, child: row),
                    );

              if (surfaceHeader == null && itemIndex == 0) {
                row = KeyedSubtree(key: headerKey, child: row);
              }
              return row;
            },
            separatorBuilder: (BuildContext context, int index) {
              if (!usesTintedRows) {
                return Divider(
                  height: theme.borders.thin,
                  thickness: theme.borders.thin,
                  indent: separatorIndent,
                  color: theme.borders.faint,
                );
              }
              return ColoredBox(
                color: colorScheme.surface,
                child: SizedBox(
                  height: _mobileRowGutterHeight,
                  child: Center(
                    child: Container(
                      height: theme.borders.thin,
                      margin: EdgeInsetsDirectional.only(
                        start: separatorIndent,
                        end: theme.spacing.sm,
                      ),
                      color: theme.borders.faint,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _NumberedMobileListItem extends StatelessWidget {
  const _NumberedMobileListItem({required this.number, required this.child});

  final int number;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      children: <Widget>[
        SizedBox(
          width: _mobileRowNumberColumnWidth,
          // End-aligned tabular figures line up as a tidy column and leave the
          // gap next to the row content, not next to the card edge.
          child: Padding(
            padding: EdgeInsetsDirectional.only(end: theme.spacing.xs),
            child: Text(
              number.toString(),
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: theme.listTokens.mobileRowNumber,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _SelectableMobileDataRow<T> extends StatelessWidget {
  const _SelectableMobileDataRow({
    required this.item,
    required this.onSelected,
    required this.child,
  });

  static const Map<ShortcutActivator, Intent> _shortcuts =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      };

  final T item;
  final ValueChanged<T> onSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: _shortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onSelected(item);
              return null;
            },
          ),
        },
        child: Semantics(
          button: true,
          enabled: true,
          onTap: () {
            onSelected(item);
          },
          child: InkWell(
            mouseCursor: SystemMouseCursors.click,
            onTap: () {
              onSelected(item);
            },
            child: Builder(
              builder: (BuildContext context) {
                final ThemeData theme = Theme.of(context);
                return Row(
                  children: <Widget>[
                    Expanded(child: child),
                    Padding(
                      // Tucked close to the edge: the affordance only needs to
                      // be legible, and the row content is what needs width.
                      padding: EdgeInsetsDirectional.only(
                        end: theme.spacing.xs,
                      ),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.38,
                        ),
                        size: theme.listTokens.mobileChevronSize,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Tap target wrapping each selectable data row of [AppListTableGrid].
///
/// Public marker so tests can find and tap table rows, replacing the
/// DataTable-era `TableRowInkWell` target.
class AppListTableRowInkWell extends InkWell {
  const AppListTableRowInkWell({
    super.key,
    super.onTap,
    super.hoverColor,
    super.child,
  });
}

/// Rendered table (grid) presentation of [AppListTable].
///
/// Non-generic marker widget wrapping the header and rows of the table
/// layout. Tests and tooling can locate the rendered table with
/// `find.byType(AppListTableGrid)` and read the resolved [horizontalMargin]
/// and [columnSpacing] metrics.
class AppListTableGrid extends StatelessWidget {
  const AppListTableGrid({
    required this.horizontalMargin,
    required this.columnSpacing,
    required this.child,
    super.key,
  });

  /// Resolved margin before the first and after the last column.
  final double horizontalMargin;

  /// Resolved gap between adjacent columns.
  final double columnSpacing;

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Paints the vertical inside column dividers (and optionally the bottom row
/// divider) across a header/data/spacer row in one cheap pass, so rows never
/// need intrinsic-height measurement to stretch bordered cells.
class _TableGridLinePainter extends CustomPainter {
  const _TableGridLinePainter({
    required this.verticalOffsets,
    required this.verticalSide,
    this.bottomSide,
  });

  final List<double> verticalOffsets;
  final BorderSide verticalSide;
  final BorderSide? bottomSide;

  @override
  void paint(Canvas canvas, Size size) {
    if (verticalSide.width > 0 && verticalOffsets.isNotEmpty) {
      final Paint paint = Paint()
        ..color = verticalSide.color
        ..strokeWidth = verticalSide.width;
      for (final double x in verticalOffsets) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
    }
    final BorderSide? bottom = bottomSide;
    if (bottom != null) {
      final Paint paint = Paint()
        ..color = bottom.color
        ..strokeWidth = bottom.width;
      final double y = size.height - bottom.width / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_TableGridLinePainter oldDelegate) {
    return oldDelegate.verticalSide != verticalSide ||
        oldDelegate.bottomSide != bottomSide ||
        !listEquals(oldDelegate.verticalOffsets, verticalOffsets);
  }
}

class _DesktopListTable<T> extends StatefulWidget {
  const _DesktopListTable({
    required this.items,
    required this.columns,
    required this.itemKeyBuilder,
    this.rowsVersion,
    required this.onRowSelected,
    required this.minWidth,
    required this.rowColorBuilder,
    required this.compact,
    this.dense = false,
    this.horizontalMargin,
    required this.sortColumnKey,
    required this.sortAscending,
    required this.onSort,
    this.rowNumberOffset = 0,
    this.showRowNumbers = true,
    this.enableColumnResize = true,
    this.scrollVertically = false,
    this.padEmptyRows = true,
    this.surfaceHeader,
    required this.goToTopController,
    required this.columnWidthFor,
    this.onColumnWidthChanged,
    this.onVerticalScrollMetrics,
  });

  final List<T> items;
  final List<AppListTableColumn<T>> columns;
  final AppListTableItemKeyBuilder<T>? itemKeyBuilder;
  final Object? rowsVersion;
  final ValueChanged<T>? onRowSelected;
  final double minWidth;
  final AppListTableRowColorBuilder<T>? rowColorBuilder;
  final bool compact;
  final bool dense;
  final double? horizontalMargin;
  final String? sortColumnKey;
  final bool sortAscending;
  final ValueChanged<AppListTableColumn<T>> onSort;
  final int rowNumberOffset;
  final bool showRowNumbers;
  final bool enableColumnResize;
  /// When true, vertical scroll is nested inside horizontal scroll so the
  /// bottom horizontal scrollbar stays fixed above the table footer.
  final bool scrollVertically;
  /// When false, do not pad the table with blank numbered spacer rows.
  final bool padEmptyRows;
  final Widget? surfaceHeader;
  final _AppListTableGoToTopController goToTopController;
  final double Function(AppListTableColumn<T> column) columnWidthFor;
  final void Function(String columnKey, double width)? onColumnWidthChanged;
  final ValueChanged<ScrollMetrics>? onVerticalScrollMetrics;

  @override
  State<_DesktopListTable<T>> createState() => _DesktopListTableState<T>();
}

class _DesktopListTableState<T> extends State<_DesktopListTable<T>> {
  late final ScrollController _horizontalController;
  late final ScrollController _verticalController;
  final GlobalKey _horizontalScrollShellKey = GlobalKey();

  double get _headingRowHeight {
    if (widget.dense) {
      return 32;
    }
    return widget.compact ? 44 : 48;
  }

  // Rows grow with wrapped cell content; min height keeps comfortable padding.
  double get _rowMinHeight {
    if (widget.dense) {
      return 44;
    }
    return widget.compact ? 48 : 52;
  }

  @override
  void initState() {
    super.initState();
    _horizontalController = ScrollController();
    _verticalController = ScrollController();
    _verticalController.addListener(_reportVerticalScrollMetrics);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportVerticalScrollMetrics();
    });
  }

  @override
  void didUpdateWidget(covariant _DesktopListTable<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportVerticalScrollMetrics();
    });
  }

  void _reportVerticalScrollMetrics() {
    if (!mounted || !_verticalController.hasClients) {
      return;
    }
    widget.onVerticalScrollMetrics?.call(_verticalController.position);
  }

  @override
  void dispose() {
    _verticalController.removeListener(_reportVerticalScrollMetrics);
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  // Layout metrics resolved once per build and shared by the header, data,
  // and spacer row builders (including rows built lazily by slivers).
  double _horizontalMargin = 0;
  double _columnSpacing = 0;
  List<double> _columnWidths = const <double>[];
  List<double> _gridLineOffsets = const <double>[];
  double _rowContentWidth = 0;
  BorderSide _verticalInsideSide = BorderSide.none;
  BorderSide _rowDividerSide = BorderSide.none;

  void _resolveLayoutMetrics(ThemeData theme) {
    _horizontalMargin =
        widget.horizontalMargin ??
        (widget.dense
            ? theme.spacing.xs
            : widget.compact
            ? theme.spacing.sm
            : theme.spacing.md);
    _columnSpacing = widget.dense
        ? theme.spacing.xs
        : widget.compact
        ? theme.spacing.sm
        : theme.spacing.lg;
    _columnWidths = <double>[
      for (final AppListTableColumn<T> column in widget.columns)
        widget.columnWidthFor(column),
    ];

    final List<double> slotWidths = <double>[
      if (widget.showRowNumbers) _rowNumberColumnWidth,
      ..._columnWidths,
    ];
    final List<double> gridLineOffsets = <double>[];
    double cursor = _horizontalMargin;
    for (int index = 0; index < slotWidths.length; index += 1) {
      cursor += slotWidths[index];
      if (index < slotWidths.length - 1) {
        gridLineOffsets.add(cursor + _columnSpacing / 2);
        cursor += _columnSpacing;
      }
    }
    _gridLineOffsets = gridLineOffsets;
    _rowContentWidth = cursor + _horizontalMargin;

    _verticalInsideSide = theme.borders.side();
    _rowDividerSide = Divider.createBorderSide(
      context,
      width: theme.appTokens.dividerThickness,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    _resolveTableStyles(theme);
    _resolveLayoutMetrics(theme);

    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        side: theme.borders.side(),
      ),
      child: _GoToTopHost(
        controller: widget.goToTopController,
        headerExtent: _headingRowHeight,
        builder: (BuildContext context, Key headerKey) {
          final Widget? surfaceHeader = widget.surfaceHeader;

          if (widget.scrollVertically) {
            return LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double viewportWidth = constraints.hasBoundedWidth
                    ? constraints.maxWidth
                    : 0;
                final double tableWidth = math.max(
                  _rowContentWidth,
                  math.max(widget.minWidth, viewportWidth),
                );

                if (surfaceHeader == null) {
                  return _buildVirtualizedBody(
                    context,
                    headerKey: headerKey,
                    tableWidth: tableWidth,
                    bodyHeight: constraints.maxHeight,
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    surfaceHeader,
                    Expanded(
                      child: LayoutBuilder(
                        builder:
                            (
                              BuildContext context,
                              BoxConstraints bodyConstraints,
                            ) {
                              return _buildVirtualizedBody(
                                context,
                                headerKey: headerKey,
                                tableWidth: tableWidth,
                                bodyHeight: bodyConstraints.maxHeight,
                              );
                            },
                      ),
                    ),
                  ],
                );
              },
            );
          }

          // Unbounded height: the table participates in an ancestor scroll
          // view, so rows are mounted directly (the parent state throttles
          // how many through progressive reveal).
          final int itemCount = widget.items.length;
          final int minRowCount = widget.padEmptyRows
              ? math.max(_minTableRowCount, itemCount)
              : itemCount;
          final int lastRowIndex = minRowCount - 1;

          final Widget table = AppListTableGrid(
            horizontalMargin: _horizontalMargin,
            columnSpacing: _columnSpacing,
            child: DefaultTextStyle(
              style: _dataTextStyle(theme),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _buildHeaderRow(context),
                  for (int index = 0; index < itemCount; index += 1)
                    _buildDataRow(
                      context,
                      index,
                      drawBottomDivider: index != lastRowIndex,
                    ),
                  for (int index = itemCount; index < minRowCount; index += 1)
                    _buildSpacerRow(
                      context,
                      index,
                      drawBottomDivider: index != lastRowIndex,
                    ),
                ],
              ),
            ),
          );

          final Widget horizontalTable = _wrapHorizontalScroll(
            context: context,
            expandVertically: false,
            child: SizedBox(
              // Explicit width: the horizontal scroll view provides unbounded
              // width, under which the stretched row Column cannot size itself.
              width: math.max(widget.minWidth, _rowContentWidth),
              child: table,
            ),
          );

          if (surfaceHeader != null) {
            return KeyedSubtree(
              key: headerKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[surfaceHeader, horizontalTable],
              ),
            );
          }

          return KeyedSubtree(key: headerKey, child: horizontalTable);
        },
      ),
    );
  }

  /// Bounded-height table body: rows live in a [CustomScrollView] so only the
  /// rows near the viewport are built, laid out, and painted. Scrolling stays
  /// smooth regardless of how many rows are loaded, and the full scroll
  /// extent is available immediately.
  Widget _buildVirtualizedBody(
    BuildContext context, {
    required Key headerKey,
    required double tableWidth,
    required double bodyHeight,
  }) {
    final ThemeData theme = Theme.of(context);
    // Rows fill the viewport above the reserved horizontal scrollbar gutter.
    final double scrollViewportHeight = math.max(
      0.0,
      bodyHeight - _horizontalScrollbarGutter,
    );
    final int itemCount = widget.items.length;
    final int minRowCount = widget.padEmptyRows
        ? _rowCountToFillHeight(
            availableHeight: scrollViewportHeight,
            headingHeight: _headingRowHeight,
            rowMinHeight: _rowMinHeight,
            itemCount: itemCount,
          )
        : itemCount;
    final int spacerCount = math.max(0, minRowCount - itemCount);
    final int lastRowIndex = itemCount + spacerCount - 1;

    // Horizontal scroll is the outer axis so its scrollbar stays pinned to
    // the bottom of the visible table viewport, in a dedicated gutter below
    // the rows.
    return SizedBox(
      height: bodyHeight,
      child: _wrapHorizontalScroll(
        context: context,
        expandVertically: true,
        child: SizedBox(
          width: tableWidth,
          child: AppListTableGrid(
            horizontalMargin: _horizontalMargin,
            columnSpacing: _columnSpacing,
            child: Scrollbar(
              controller: _verticalController,
              thumbVisibility: true,
              child: DefaultTextStyle(
                style: _dataTextStyle(theme),
                child: CustomScrollView(
                  controller: _verticalController,
                  slivers: <Widget>[
                    SliverToBoxAdapter(
                      child: KeyedSubtree(
                        key: headerKey,
                        child: _buildHeaderRow(context),
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (BuildContext context, int index) {
                          return _buildDataRow(
                            context,
                            index,
                            drawBottomDivider: index != lastRowIndex,
                          );
                        },
                        childCount: itemCount,
                        addAutomaticKeepAlives: false,
                      ),
                    ),
                    if (spacerCount > 0)
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (BuildContext context, int index) {
                            final int rowIndex = itemCount + index;
                            return _buildSpacerRow(
                              context,
                              rowIndex,
                              drawBottomDivider: rowIndex != lastRowIndex,
                            );
                          },
                          childCount: spacerCount,
                          addAutomaticKeepAlives: false,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Horizontal scroller with a pinned, clearly visible scrollbar gutter and
  /// mouse-wheel / trackpad support for left/right panning.
  Widget _wrapHorizontalScroll({
    required BuildContext context,
    required Widget child,
    required bool expandVertically,
  }) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Widget scrollView = ScrollConfiguration(
      // Keep click-and-drag panning available with a mouse in addition to
      // the scrollbar thumb and wheel / trackpad gestures.
      behavior: const _TableDragScrollBehavior(),
      child: SingleChildScrollView(
        controller: _horizontalController,
        scrollDirection: Axis.horizontal,
        child: child,
      ),
    );

    final Widget gutter = Listener(
      // Opaque so wheel events over the empty gutter / track still hit here
      // instead of falling through to an ancestor vertical scroll view.
      behavior: HitTestBehavior.opaque,
      onPointerSignal: (PointerSignalEvent event) {
        _handleHorizontalPointerSignal(event, forceHorizontal: true);
      },
      child: const SizedBox(height: _horizontalScrollbarGutter),
    );

    final Widget body = expandVertically
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: scrollView),
              gutter,
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              scrollView,
              gutter,
            ],
          );

    // Outer listener covers the painted scrollbar thumb/track (which sits in
    // the gutter) as well as the table body for Shift+wheel / trackpad dx.
    return Listener(
      key: _horizontalScrollShellKey,
      behavior: HitTestBehavior.translucent,
      onPointerSignal: (PointerSignalEvent event) {
        _handleHorizontalPointerSignal(
          event,
          forceHorizontal: _isPointerOverHorizontalScrollbar(event),
        );
      },
      child: RawScrollbar(
        controller: _horizontalController,
        thumbVisibility: true,
        trackVisibility: true,
        interactive: true,
        thickness: _horizontalScrollbarThickness,
        radius: const Radius.circular(6),
        scrollbarOrientation: ScrollbarOrientation.bottom,
        thumbColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
        trackColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.92),
        trackBorderColor: colorScheme.outlineVariant.withValues(alpha: 0.85),
        padding: EdgeInsets.zero,
        notificationPredicate: (ScrollNotification notification) {
          return notification.metrics.axis == Axis.horizontal;
        },
        child: body,
      ),
    );
  }

  /// Whether [event] landed in the reserved bottom horizontal scrollbar gutter.
  bool _isPointerOverHorizontalScrollbar(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return false;
    }
    final BuildContext? shellContext = _horizontalScrollShellKey.currentContext;
    final RenderObject? renderObject = shellContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return false;
    }
    final Offset local = renderObject.globalToLocal(event.position);
    if (!renderObject.size.contains(local)) {
      return false;
    }
    return local.dy >= renderObject.size.height - _horizontalScrollbarGutter;
  }

  /// Translates pointer scroll into horizontal panning while preserving plain
  /// vertical wheel scrolling for the nested body.
  ///
  /// - Trackpad / mouse horizontal deltas pan left/right.
  /// - Shift + vertical wheel also pans left/right.
  /// - Vertical wheel over the horizontal scrollbar gutter always pans
  ///   left/right (no Shift required).
  /// - Unmodified vertical wheel over the table body is left for the nested
  ///   vertical scroll view.
  void _handleHorizontalPointerSignal(
    PointerSignalEvent event, {
    bool forceHorizontal = false,
  }) {
    if (event is! PointerScrollEvent) {
      return;
    }
    if (!_horizontalController.hasClients) {
      return;
    }

    final ScrollPosition horizontal = _horizontalController.position;
    if (horizontal.maxScrollExtent <= horizontal.minScrollExtent) {
      return;
    }

    final bool shiftPressed = HardwareKeyboard.instance.isShiftPressed;
    final bool mapVerticalToHorizontal = forceHorizontal || shiftPressed;
    final double horizontalDelta =
        event.scrollDelta.dx +
        (mapVerticalToHorizontal ? event.scrollDelta.dy : 0.0);
    if (horizontalDelta == 0) {
      return;
    }

    // Claim the signal when we intentionally pan horizontally so nested
    // vertical scrollables do not also move (especially for Shift+wheel or
    // wheel-over-scrollbar).
    GestureBinding.instance.pointerSignalResolver.register(event, (
      PointerSignalEvent resolvedEvent,
    ) {
      if (resolvedEvent is! PointerScrollEvent) {
        return;
      }
      if (!_horizontalController.hasClients) {
        return;
      }

      final ScrollPosition position = _horizontalController.position;
      final bool shift = HardwareKeyboard.instance.isShiftPressed;
      final bool mapVertical =
          forceHorizontal ||
          shift ||
          _isPointerOverHorizontalScrollbar(resolvedEvent);
      final double delta =
          resolvedEvent.scrollDelta.dx +
          (mapVertical ? resolvedEvent.scrollDelta.dy : 0.0);
      if (delta == 0) {
        return;
      }

      final double next = (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (next != position.pixels) {
        position.jumpTo(next);
      }

      // Diagonal trackpad gestures: keep vertical motion on the body when we
      // claimed the event only because of a non-zero horizontal delta.
      if (!mapVertical &&
          resolvedEvent.scrollDelta.dy != 0 &&
          _verticalController.hasClients) {
        final ScrollPosition vertical = _verticalController.position;
        final double verticalNext =
            (vertical.pixels + resolvedEvent.scrollDelta.dy).clamp(
              vertical.minScrollExtent,
              vertical.maxScrollExtent,
            );
        if (verticalNext != vertical.pixels) {
          vertical.jumpTo(verticalNext);
        }
      }
    });
  }

  Widget _buildHeaderRow(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle headingStyle =
        _cachedHeadingTextStyle ??
        theme.textTheme.labelLarge ??
        AppFontFamily.style();

    return SizedBox(
      height: _headingRowHeight,
      child: CustomPaint(
        foregroundPainter: _TableGridLinePainter(
          verticalOffsets: _gridLineOffsets,
          verticalSide: _verticalInsideSide,
          bottomSide: _rowDividerSide,
        ),
        child: ColoredBox(
          color: _headingBackgroundColor(theme),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: _horizontalMargin),
            child: DefaultTextStyle(
              style: headingStyle,
              child: Row(
                children: <Widget>[
                  if (widget.showRowNumbers) ...<Widget>[
                    SizedBox(
                      width: _rowNumberColumnWidth,
                      child: Text(
                        '#',
                        textAlign: TextAlign.start,
                        style: _cachedNumberColumnStyle,
                      ),
                    ),
                    SizedBox(width: _columnSpacing),
                  ],
                  for (
                    int index = 0;
                    index < widget.columns.length;
                    index += 1
                  ) ...<Widget>[
                    if (index > 0) SizedBox(width: _columnSpacing),
                    _buildHeaderCell(context, index),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCell(BuildContext context, int index) {
    final AppListTableColumn<T> column = widget.columns[index];
    final Widget header = _DataColumnHeader<T>(
      column: column,
      isSorted: widget.sortColumnKey == column.key,
      sortAscending: widget.sortAscending,
      onSort: widget.onSort,
      width: _columnWidths[index],
      enableResize: widget.enableColumnResize && column.fixedWidth == null,
      onWidthChanged:
          widget.onColumnWidthChanged == null || column.fixedWidth != null
          ? null
          : (double width) {
              widget.onColumnWidthChanged!(column.key, width);
            },
    );
    final String? tooltip = column.tooltip;
    // Sortable headers already describe themselves through the sort tooltip.
    if (tooltip == null || column.isSortable) {
      return header;
    }
    return Tooltip(message: tooltip, child: header);
  }

  Widget _buildDataRow(
    BuildContext context,
    int index, {
    required bool drawBottomDivider,
  }) {
    final T item = widget.items[index];
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final Color? custom = widget.rowColorBuilder?.call(context, item);
    final Color? stripe = index.isOdd
        ? colorScheme.surfaceContainerLowest.withValues(alpha: 0.65)
        : null;
    final Color? baseColor = custom ?? stripe;
    final ValueChanged<T>? onRowSelected = widget.onRowSelected;

    Widget row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: _rowMinHeight),
      child: CustomPaint(
        foregroundPainter: _TableGridLinePainter(
          verticalOffsets: _gridLineOffsets,
          verticalSide: _verticalInsideSide,
          bottomSide: drawBottomDivider ? _rowDividerSide : null,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: _horizontalMargin),
          child: Row(
            children: <Widget>[
              if (widget.showRowNumbers) ...<Widget>[
                SizedBox(
                  width: _rowNumberColumnWidth,
                  child: Text(
                    (widget.rowNumberOffset + index + 1).toString(),
                    textAlign: TextAlign.center,
                    style: _resolveRowNumberStyle(theme),
                  ),
                ),
                SizedBox(width: _columnSpacing),
              ],
              for (
                int columnIndex = 0;
                columnIndex < widget.columns.length;
                columnIndex += 1
              ) ...<Widget>[
                if (columnIndex > 0) SizedBox(width: _columnSpacing),
                _AppListTableCell(
                  width: _columnWidths[columnIndex],
                  numeric: widget.columns[columnIndex].numeric,
                  child: widget.columns[columnIndex].cellBuilder(
                    context,
                    item,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (onRowSelected != null) {
      row = AppListTableRowInkWell(
        onTap: () {
          onRowSelected(item);
        },
        hoverColor: colorScheme.primary.withValues(
          alpha: baseColor == null ? 0.05 : 0.06,
        ),
        child: row,
      );
    }
    // Each row hosts its own Material so hover/splash ink paints above the
    // stripe/status base color instead of being hidden underneath it.
    row = baseColor == null
        ? Material(type: MaterialType.transparency, child: row)
        : Material(color: baseColor, child: row);

    return KeyedSubtree(
      key: appListTableUniqueRowKey<T>(
        index: index,
        itemKeyBuilder: widget.itemKeyBuilder,
        item: item,
        rowsVersion: widget.rowsVersion,
      ),
      child: row,
    );
  }

  Widget _buildSpacerRow(
    BuildContext context,
    int index, {
    required bool drawBottomDivider,
  }) {
    final ThemeData theme = Theme.of(context);
    final Color? stripe = index.isOdd
        ? theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.65)
        : null;

    Widget content = Padding(
      padding: EdgeInsets.symmetric(horizontal: _horizontalMargin),
      child: widget.showRowNumbers
          ? Row(
              children: <Widget>[
                SizedBox(
                  width: _rowNumberColumnWidth,
                  child: Text(
                    (widget.rowNumberOffset + index + 1).toString(),
                    textAlign: TextAlign.center,
                    style: _resolveRowNumberStyle(theme),
                  ),
                ),
              ],
            )
          : const SizedBox.shrink(),
    );
    if (stripe != null) {
      content = ColoredBox(color: stripe, child: content);
    }

    return SizedBox(
      height: _rowMinHeight,
      child: CustomPaint(
        foregroundPainter: _TableGridLinePainter(
          verticalOffsets: _gridLineOffsets,
          verticalSide: _verticalInsideSide,
          bottomSide: drawBottomDivider ? _rowDividerSide : null,
        ),
        child: content,
      ),
    );
  }

  TextStyle _dataTextStyle(ThemeData theme) {
    return _cachedDataTextStyle ??
        theme.textTheme.bodyMedium ??
        AppFontFamily.style();
  }

  /// Computes how many rows (data + blank spacers) are needed so the table body
  /// fills [availableHeight] under the heading at [rowMinHeight], without a
  /// fixed oversized pad beyond the viewport.
  static int _rowCountToFillHeight({
    required double availableHeight,
    required double headingHeight,
    required double rowMinHeight,
    required int itemCount,
  }) {
    if (!availableHeight.isFinite ||
        availableHeight <= 0 ||
        rowMinHeight <= 0) {
      return math.max(itemCount, _minTableRowCount);
    }
    final double bodyHeight = math.max(0.0, availableHeight - headingHeight);
    final int viewportRows = math.max(1, (bodyHeight / rowMinHeight).ceil());
    return math.max(itemCount, viewportRows);
  }

  ColorScheme? _cachedTableStyleScheme;
  Color? _cachedHeadingRowColor;
  TextStyle? _cachedHeadingTextStyle;
  TextStyle? _cachedDataTextStyle;
  TextStyle? _cachedNumberColumnStyle;

  Color _headingBackgroundColor(ThemeData theme) {
    return _cachedHeadingRowColor ?? theme.colorScheme.surface;
  }

  void _resolveTableStyles(ThemeData theme) {
    final ColorScheme cs = theme.colorScheme;
    if (identical(_cachedTableStyleScheme, cs)) {
      return;
    }
    _cachedTableStyleScheme = cs;
    _cachedHeadingRowColor = Color.alphaBlend(
      cs.surfaceContainerHigh.withValues(alpha: 0.72),
      cs.surface,
    );
    _cachedHeadingTextStyle = theme.textTheme.labelLarge?.copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: AppFontWeight.emphasis,
      letterSpacing: 0.1,
    );
    _cachedDataTextStyle = theme.textTheme.bodyMedium?.copyWith(
      color: cs.onSurface,
      fontWeight: AppFontWeight.regular,
    );
    _cachedNumberColumnStyle = theme.textTheme.labelMedium?.copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: AppFontWeight.emphasis,
    );
    _rowNumberStyle = null;
  }

  TextStyle? _rowNumberStyle;

  TextStyle? _resolveRowNumberStyle(ThemeData theme) {
    if (_rowNumberStyle != null &&
        identical(_cachedTableStyleScheme, theme.colorScheme)) {
      return _rowNumberStyle;
    }
    _rowNumberStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: AppFontWeight.emphasis,
    );
    return _rowNumberStyle;
  }

}

/// Enables mouse click-and-drag panning on table scroll views (in addition to
/// touch / trackpad), matching desktop spreadsheet-style interaction.
class _TableDragScrollBehavior extends MaterialScrollBehavior {
  const _TableDragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.unknown,
  };
}

/// Constrains cell content to the column width so text wraps and the row can
/// grow with the tallest cell.
///
/// Long labels keep their natural font size and wrap inside the column instead
/// of being shrunk by [FittedBox] or clipped to a fixed line count.
class _AppListTableCell extends StatelessWidget {
  const _AppListTableCell({
    required this.width,
    required this.numeric,
    required this.child,
  });

  final double width;
  final bool numeric;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle style = DefaultTextStyle.of(context).style;
    // Tight width so text wraps at the column edge; the row then grows with
    // its tallest cell (rows only enforce a minimum height).
    return SizedBox(
      width: width,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: theme.spacing.sm),
        child: AppListTableTextPolicy(
          child: DefaultTextStyle(
            style: style,
            overflow: TextOverflow.visible,
            textAlign: numeric ? TextAlign.right : TextAlign.start,
            child: _AppListTableWrappingScope(child: child),
          ),
        ),
      ),
    );
  }
}

/// Rewrites nested [Text]/[RichText] so explicit maxLines/ellipsis in cell
/// builders cannot prevent wrapping inside the table.
class _AppListTableWrappingScope extends StatelessWidget {
  const _AppListTableWrappingScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => _enableCellTextWrapping(child);
}

Widget _enableCellTextWrapping(Widget widget) {
  if (widget is Text) {
    return Text.rich(
      widget.textSpan ?? TextSpan(text: widget.data, style: widget.style),
      key: widget.key,
      style: widget.style,
      strutStyle: widget.strutStyle,
      textAlign: widget.textAlign,
      textDirection: widget.textDirection,
      locale: widget.locale,
      overflow: TextOverflow.visible,
      textScaler: widget.textScaler,
      semanticsLabel: widget.semanticsLabel,
      textWidthBasis: widget.textWidthBasis,
      textHeightBehavior: widget.textHeightBehavior,
      selectionColor: widget.selectionColor,
    );
  }

  if (widget is RichText) {
    return RichText(
      key: widget.key,
      text: widget.text,
      textAlign: widget.textAlign,
      textDirection: widget.textDirection,
      overflow: TextOverflow.visible,
      textScaler: widget.textScaler,
      locale: widget.locale,
      strutStyle: widget.strutStyle,
      textWidthBasis: widget.textWidthBasis,
      textHeightBehavior: widget.textHeightBehavior,
      selectionColor: widget.selectionColor,
    );
  }

  if (widget is Padding) {
    final Widget? child = widget.child;
    if (child == null) {
      return widget;
    }
    return Padding(
      key: widget.key,
      padding: widget.padding,
      child: _enableCellTextWrapping(child),
    );
  }

  if (widget is Align) {
    final Widget? child = widget.child;
    if (child == null) {
      return widget;
    }
    return Align(
      key: widget.key,
      alignment: widget.alignment,
      widthFactor: widget.widthFactor,
      heightFactor: widget.heightFactor,
      child: _enableCellTextWrapping(child),
    );
  }

  if (widget is SizedBox) {
    final Widget? child = widget.child;
    if (child == null) {
      return widget;
    }
    return SizedBox(
      key: widget.key,
      width: widget.width,
      height: widget.height,
      child: _enableCellTextWrapping(child),
    );
  }

  if (widget is ConstrainedBox) {
    final Widget? child = widget.child;
    if (child == null) {
      return widget;
    }
    return ConstrainedBox(
      key: widget.key,
      constraints: widget.constraints,
      child: _enableCellTextWrapping(child),
    );
  }

  if (widget is ColoredBox) {
    final Widget? child = widget.child;
    if (child == null) {
      return widget;
    }
    return ColoredBox(
      key: widget.key,
      color: widget.color,
      child: _enableCellTextWrapping(child),
    );
  }

  if (widget is DecoratedBox) {
    final Widget? child = widget.child;
    if (child == null) {
      return widget;
    }
    return DecoratedBox(
      key: widget.key,
      decoration: widget.decoration,
      position: widget.position,
      child: _enableCellTextWrapping(child),
    );
  }

  if (widget is Flexible) {
    return Flexible(
      key: widget.key,
      flex: widget.flex,
      fit: widget.fit,
      child: _enableCellTextWrapping(widget.child),
    );
  }

  if (widget is Expanded) {
    return Expanded(
      key: widget.key,
      flex: widget.flex,
      child: _enableCellTextWrapping(widget.child),
    );
  }

  if (widget is Column) {
    return Column(
      key: widget.key,
      mainAxisAlignment: widget.mainAxisAlignment,
      mainAxisSize: widget.mainAxisSize,
      crossAxisAlignment: widget.crossAxisAlignment,
      textDirection: widget.textDirection,
      verticalDirection: widget.verticalDirection,
      textBaseline: widget.textBaseline,
      children: widget.children.map(_enableCellTextWrapping).toList(),
    );
  }

  if (widget is Row) {
    return Row(
      key: widget.key,
      mainAxisAlignment: widget.mainAxisAlignment,
      mainAxisSize: widget.mainAxisSize,
      crossAxisAlignment: widget.crossAxisAlignment == CrossAxisAlignment.center
          ? CrossAxisAlignment.start
          : widget.crossAxisAlignment,
      textDirection: widget.textDirection,
      verticalDirection: widget.verticalDirection,
      textBaseline: widget.textBaseline,
      children: widget.children.map(_enableCellTextWrapping).toList(),
    );
  }

  if (widget is Wrap) {
    return Wrap(
      key: widget.key,
      direction: widget.direction,
      alignment: widget.alignment,
      spacing: widget.spacing,
      runAlignment: widget.runAlignment,
      runSpacing: widget.runSpacing,
      crossAxisAlignment: widget.crossAxisAlignment,
      textDirection: widget.textDirection,
      verticalDirection: widget.verticalDirection,
      clipBehavior: widget.clipBehavior,
      children: widget.children.map(_enableCellTextWrapping).toList(),
    );
  }

  if (widget is GestureDetector) {
    final Widget? child = widget.child;
    if (child == null) {
      return widget;
    }
    return GestureDetector(
      key: widget.key,
      onTap: widget.onTap,
      onTapDown: widget.onTapDown,
      onTapUp: widget.onTapUp,
      onTapCancel: widget.onTapCancel,
      onSecondaryTap: widget.onSecondaryTap,
      onSecondaryTapDown: widget.onSecondaryTapDown,
      onSecondaryTapUp: widget.onSecondaryTapUp,
      onSecondaryTapCancel: widget.onSecondaryTapCancel,
      onDoubleTap: widget.onDoubleTap,
      onLongPress: widget.onLongPress,
      onLongPressStart: widget.onLongPressStart,
      onLongPressMoveUpdate: widget.onLongPressMoveUpdate,
      onLongPressUp: widget.onLongPressUp,
      onLongPressEnd: widget.onLongPressEnd,
      behavior: widget.behavior,
      excludeFromSemantics: widget.excludeFromSemantics,
      child: _enableCellTextWrapping(child),
    );
  }

  return widget;
}

class _DataColumnHeader<T> extends StatelessWidget {
  const _DataColumnHeader({
    required this.column,
    required this.isSorted,
    required this.sortAscending,
    required this.onSort,
    required this.width,
    required this.enableResize,
    this.onWidthChanged,
  });

  final AppListTableColumn<T> column;
  final bool isSorted;
  final bool sortAscending;
  final ValueChanged<AppListTableColumn<T>> onSort;
  final double width;
  final bool enableResize;
  final ValueChanged<double>? onWidthChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final TextStyle? headerStyle = theme.textTheme.labelLarge?.copyWith(
      color: isSorted ? colorScheme.primary : colorScheme.onSurfaceVariant,
      fontWeight: isSorted ? AppFontWeight.emphasis : AppFontWeight.regular,
    );

    Widget label;
    if (!column.isSortable) {
      final AppListTableHeaderBuilder<T>? headerBuilder = column.headerBuilder;
      if (headerBuilder != null) {
        label = headerBuilder(context);
      } else {
        label = Text(
          column.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: headerStyle,
        );
      }
    } else {
      final IconData sortIcon = isSorted
          ? sortAscending
                ? Icons.arrow_upward
                : Icons.arrow_downward
          : Icons.swap_vert;
      final Color foreground = isSorted
          ? colorScheme.primary
          : colorScheme.onSurfaceVariant;
      final String direction = sortAscending ? 'ascending' : 'descending';
      final String tooltip = isSorted
          ? 'Sorted by ${column.label}, $direction'
          : 'Sort by ${column.label}';

      label = Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          selected: isSorted,
          label: tooltip,
          child: InkWell(
            onTap: () {
              onSort(column);
            },
            borderRadius: BorderRadius.circular(theme.radius.sm),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: theme.spacing.xs),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: theme.borders.only(
                    bottom: true,
                    color: isSorted ? colorScheme.primary : Colors.transparent,
                    weight: AppBorderWeight.medium,
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        column.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: headerStyle?.copyWith(color: foreground),
                      ),
                    ),
                    SizedBox(width: theme.spacing.xs),
                    Icon(
                      sortIcon,
                      color: foreground.withValues(alpha: isSorted ? 1 : 0.74),
                      size: theme.appTokens.listIconSize * 0.82,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: width,
      child: Row(
        children: <Widget>[
          Expanded(child: label),
          if (enableResize && onWidthChanged != null)
            _ColumnResizeHandle(width: width, onWidthChanged: onWidthChanged!),
        ],
      ),
    );
  }
}

class _ColumnResizeHandle extends StatefulWidget {
  const _ColumnResizeHandle({
    required this.width,
    required this.onWidthChanged,
  });

  final double width;
  final ValueChanged<double> onWidthChanged;

  @override
  State<_ColumnResizeHandle> createState() => _ColumnResizeHandleState();
}

class _ColumnResizeHandleState extends State<_ColumnResizeHandle> {
  double? _dragWidth;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) {
          _dragWidth = widget.width;
        },
        onHorizontalDragUpdate: (DragUpdateDetails details) {
          final double next = (_dragWidth ?? widget.width) + details.delta.dx;
          _dragWidth = next;
          widget.onWidthChanged(next);
        },
        onHorizontalDragEnd: (_) {
          _dragWidth = null;
        },
        onHorizontalDragCancel: () {
          _dragWidth = null;
        },
        child: Semantics(
          label: 'Resize column',
          slider: true,
          child: SizedBox(
            width: _columnResizeHandleWidth,
            child: Center(
              child: Container(
                width: 2,
                height: 18,
                decoration: BoxDecoration(
                  color: theme.borders.faint,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoToTopHost extends StatefulWidget {
  const _GoToTopHost({
    required this.controller,
    required this.headerExtent,
    required this.builder,
  });

  final _AppListTableGoToTopController controller;
  final double headerExtent;
  final Widget Function(BuildContext context, Key headerKey) builder;

  @override
  State<_GoToTopHost> createState() => _GoToTopHostState();
}

class _GoToTopHostState extends State<_GoToTopHost> {
  final GlobalKey _headerKey = GlobalKey(debugLabel: 'appListTableHeader');
  ScrollPosition? _trackedPosition;
  bool _visibilityCheckScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.attach(_goToTop);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _reattachScrollPosition();
        _scheduleVisibilityCheck();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _GoToTopHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.detach();
      widget.controller.attach(_goToTop);
      _scheduleVisibilityCheck();
    }
  }

  @override
  void dispose() {
    widget.controller.detachSilently();
    _detachScrollPosition();
    super.dispose();
  }

  void _scheduleVisibilityCheck() {
    if (_visibilityCheckScheduled) {
      return;
    }
    _visibilityCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityCheckScheduled = false;
      if (!mounted) {
        return;
      }
      _reattachScrollPosition();
      _syncVisibility();
    });
  }

  void _reattachScrollPosition() {
    final BuildContext? headerContext = _headerKey.currentContext;
    if (headerContext == null) {
      // The header row can be virtualized out while scrolled far down; keep
      // the tracked position so visibility updates keep flowing until the
      // header mounts again.
      return;
    }
    final ScrollPosition? position = Scrollable.maybeOf(
      headerContext,
    )?.position;
    if (identical(position, _trackedPosition)) {
      return;
    }
    _detachScrollPosition();
    _trackedPosition = position;
    _trackedPosition?.addListener(_scheduleVisibilityCheck);
  }

  void _detachScrollPosition() {
    _trackedPosition?.removeListener(_scheduleVisibilityCheck);
    _trackedPosition = null;
  }

  bool _isHeaderHidden() {
    final BuildContext? headerContext = _headerKey.currentContext;
    if (headerContext == null) {
      // A virtualized scroll view culls the header sliver once it is far off
      // screen, so a missing context while scrolled past the header height
      // means it is hidden.
      final ScrollPosition? position = _trackedPosition;
      return position != null &&
          position.hasPixels &&
          position.pixels > widget.headerExtent;
    }
    final RenderObject? headerRender = headerContext.findRenderObject();
    if (headerRender == null || !headerRender.attached) {
      return false;
    }

    final ScrollableState? scrollable = Scrollable.maybeOf(headerContext);
    final ScrollPosition? position = scrollable?.position;
    if (position == null || !position.hasPixels) {
      return false;
    }

    final RenderAbstractViewport? viewport = RenderAbstractViewport.maybeOf(
      headerRender,
    );
    if (viewport != null) {
      final RevealedOffset revealed = viewport.getOffsetToReveal(
        headerRender,
        0,
      );
      // Headers are hidden as soon as their top edge leaves the viewport top.
      return position.pixels > revealed.offset + 0.5;
    }

    return position.pixels > widget.headerExtent;
  }

  void _syncVisibility() {
    widget.controller.setCanGoToTop(_isHeaderHidden());
  }

  Future<void> _goToTop() async {
    final BuildContext? headerContext = _headerKey.currentContext;
    final ScrollPosition? position = headerContext != null
        ? Scrollable.maybeOf(headerContext)?.position
        : _trackedPosition;
    if (position != null && position.hasPixels) {
      await position.animateTo(
        0,
        duration: _goToTopAnimationDuration,
        curve: Curves.easeOutCubic,
      );
    } else if (headerContext != null) {
      await Scrollable.ensureVisible(
        headerContext,
        duration: _goToTopAnimationDuration,
        curve: Curves.easeOutCubic,
      );
    }
    _scheduleVisibilityCheck();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        if (notification.metrics.axis != Axis.vertical) {
          return false;
        }
        if (notification is ScrollUpdateNotification ||
            notification is ScrollEndNotification ||
            notification is OverscrollNotification) {
          _scheduleVisibilityCheck();
        }
        return false;
      },
      child: widget.builder(context, _headerKey),
    );
  }
}

class _DefaultListTableLoading extends StatelessWidget {
  const _DefaultListTableLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: AppLoadingIndicator.compact(),
    );
  }
}
