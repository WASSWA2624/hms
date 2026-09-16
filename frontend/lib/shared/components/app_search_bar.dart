import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/core/responsive/app_breakpoints.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/components/app_action_label_scope.dart';
import 'package:hosspi_hms/shared/components/app_button.dart';
import 'package:hosspi_hms/shared/components/app_checkbox_field.dart';
import 'package:hosspi_hms/shared/components/app_date_field.dart';
import 'package:hosspi_hms/shared/components/app_dialog.dart';
import 'package:hosspi_hms/shared/components/app_field_label.dart';
import 'package:hosspi_hms/shared/components/app_loading_indicator.dart';
import 'package:hosspi_hms/shared/components/app_select_field.dart';
import 'package:hosspi_hms/shared/components/app_speech_to_text.dart';
import 'package:hosspi_hms/shared/components/app_text_field.dart';

/// Default maximum characters accepted by [AppSearchBar] / list search APIs.
const int appSearchQueryMaxLength = 255;

/// Normalizes and clamps a search query for list APIs.
///
/// Collapses whitespace (including newlines from pasted paragraphs) and caps
/// length so overlong paste never trips backend `search` validation.
String clampAppSearchQuery(
  String value, {
  int maxLength = appSearchQueryMaxLength,
}) {
  final String collapsed = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.length <= maxLength) {
    return collapsed;
  }
  return collapsed.substring(0, maxLength);
}

@immutable
final class AppSearchBarFieldChoice {
  const AppSearchBarFieldChoice({
    required this.field,
    required this.label,
    this.icon,
  });

  final String field;
  final String label;
  final IconData? icon;
}

@immutable
final class AppSearchBarTextFilter {
  const AppSearchBarTextFilter({
    required this.key,
    required this.label,
    this.hintText,
    this.icon,
    this.keyboardType,
    this.textInputAction,
  });

  final String key;
  final String label;
  final String? hintText;
  final IconData? icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
}

@immutable
final class AppSearchBarFilterChoice {
  const AppSearchBarFilterChoice({
    required this.value,
    required this.label,
    this.icon,
  });

  final String value;
  final String label;
  final IconData? icon;
}

@immutable
final class AppSearchBarFilterGroup {
  const AppSearchBarFilterGroup({
    required this.key,
    required this.label,
    required this.choices,
    this.allLabel,
    this.allowMultiple = false,
  });

  final String key;
  final String label;
  final List<AppSearchBarFilterChoice> choices;
  final String? allLabel;
  final bool allowMultiple;
}

@immutable
final class AppSearchBarFilterValue {
  const AppSearchBarFilterValue({
    this.field,
    this.dateFrom,
    this.dateTo,
    this.texts = const <String, String>{},
    this.options = const <String, String>{},
    this.selections = const <String, Set<String>>{},
  });

  static const AppSearchBarFilterValue empty = AppSearchBarFilterValue();

  final String? field;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final Map<String, String> texts;
  final Map<String, String> options;
  final Map<String, Set<String>> selections;

  bool get isActive {
    return _hasText(field) ||
        dateFrom != null ||
        dateTo != null ||
        texts.values.any(_hasText) ||
        options.values.any(_hasText) ||
        selections.values.any((Set<String> values) => values.isNotEmpty);
  }

  int get activeCount {
    return (_hasText(field) ? 1 : 0) +
        (dateFrom != null || dateTo != null ? 1 : 0) +
        texts.values.where(_hasText).length +
        options.values.where(_hasText).length +
        selections.values.fold<int>(
          0,
          (int count, Set<String> values) => count + values.length,
        );
  }

  String? text(String key) {
    final String? value = texts[key];
    return _hasText(value) ? value : null;
  }

  String? option(String key) {
    final String? value = options[key];
    return _hasText(value) ? value : null;
  }

  Set<String> optionsFor(String key) {
    final Set<String>? values = selections[key];
    if (values != null && values.isNotEmpty) {
      return Set<String>.unmodifiable(values);
    }
    final String? scalar = option(key);
    return scalar == null ? const <String>{} : <String>{scalar};
  }

  AppSearchBarFilterValue copyWith({
    String? field,
    DateTime? dateFrom,
    DateTime? dateTo,
    Map<String, String>? texts,
    Map<String, String>? options,
    Map<String, Set<String>>? selections,
    bool clearField = false,
    bool clearDateFrom = false,
    bool clearDateTo = false,
    bool clearTexts = false,
    bool clearOptions = false,
    bool clearSelections = false,
  }) {
    return AppSearchBarFilterValue(
      field: clearField ? null : field ?? this.field,
      dateFrom: clearDateFrom ? null : dateFrom ?? this.dateFrom,
      dateTo: clearDateTo ? null : dateTo ?? this.dateTo,
      texts: clearTexts ? const <String, String>{} : texts ?? this.texts,
      options: clearOptions
          ? const <String, String>{}
          : options ?? this.options,
      selections: clearSelections
          ? const <String, Set<String>>{}
          : selections ?? this.selections,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AppSearchBarFilterValue &&
        other.field == field &&
        other.dateFrom == dateFrom &&
        other.dateTo == dateTo &&
        mapEquals(other.texts, texts) &&
        mapEquals(other.options, options) &&
        _setMapEquals(other.selections, selections);
  }

  @override
  int get hashCode {
    final List<String> textKeys = texts.keys.toList(growable: false)..sort();
    final List<String> optionKeys = options.keys.toList(growable: false)
      ..sort();
    final List<String> selectionKeys = selections.keys.toList(growable: false)
      ..sort();
    return Object.hash(
      field,
      dateFrom,
      dateTo,
      Object.hashAll(
        textKeys.map((String key) => Object.hash(key, texts[key])),
      ),
      Object.hashAll(
        optionKeys.map((String key) => Object.hash(key, options[key])),
      ),
      Object.hashAll(
        selectionKeys.map((String key) {
          final List<String> values = selections[key]!.toList()..sort();
          return Object.hash(key, Object.hashAll(values));
        }),
      ),
    );
  }
}

bool _setMapEquals(
  Map<String, Set<String>> left,
  Map<String, Set<String>> right,
) {
  if (left.length != right.length || !left.keys.every(right.containsKey)) {
    return false;
  }
  return left.keys.every((String key) => setEquals(left[key], right[key]));
}

bool appSearchBarDateRangeIsValid(DateTime? from, DateTime? to) {
  return from == null ||
      to == null ||
      !DateUtils.dateOnly(from).isAfter(DateUtils.dateOnly(to));
}

@immutable
final class AppSearchBarAction {
  const AppSearchBarAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
    this.enabled = true,
    this.active = false,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool enabled;
  final bool active;
  final bool destructive;
}

class AppSearchBar extends StatefulWidget {
  const AppSearchBar({
    required this.controller,
    required this.semanticLabel,
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
    this.maxTrailingActions,
    this.trailingActionsOverflowLabel = 'More actions',
    this.enableSpeechToText = true,
    this.maxLength = appSearchQueryMaxLength,
    super.key,
  });

  final TextEditingController controller;
  final String semanticLabel;
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
  final List<AppSearchBarAction> trailingActions;
  final int? maxTrailingActions;
  final String trailingActionsOverflowLabel;
  final bool enableSpeechToText;

  /// Maximum characters kept in the search field (null disables the cap).
  final int? maxLength;

  @override
  State<AppSearchBar> createState() => _AppSearchBarState();
}

class _AppSearchBarState extends State<AppSearchBar> {
  late FocusNode _focusNode;
  late bool _ownsFocusNode;

  @override
  void initState() {
    super.initState();
    _attachFocusNode();
  }

  @override
  void didUpdateWidget(covariant AppSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _detachFocusNode();
      _attachFocusNode();
    }
  }

  @override
  void dispose() {
    _detachFocusNode();
    super.dispose();
  }

  void _attachFocusNode() {
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChanged);
  }

  void _detachFocusNode() {
    _focusNode.removeListener(_handleFocusChanged);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
  }

  void _handleFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controller,
      builder: (BuildContext context, TextEditingValue value, _) {
        final ThemeData theme = Theme.of(context);
        final bool canEdit = widget.enabled;
        final String clearLabel =
            widget.clearLabel ??
            MaterialLocalizations.of(context).clearButtonTooltip;
        final bool canClear =
            widget.showClearButton && value.text.isNotEmpty && widget.enabled;
        final bool showFilters = _shouldShowFilterButton;
        final BorderSide borderSide = _borderSide(theme);
        final double minHeight =
            theme.inputDecorationTheme.constraints?.minHeight ?? 48;

        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints _) {
            final bool showActionLabels =
                AppBreakpoints.of(context).showsToolbarActionLabels;
            final List<AppSearchBarAction> inlineTrailingActions;
            final List<AppSearchBarAction> overflowTrailingActions;
            final int? maxTrailingActions = widget.maxTrailingActions;
            if (maxTrailingActions != null &&
                widget.trailingActions.length > maxTrailingActions) {
              inlineTrailingActions = widget.trailingActions
                  .take(maxTrailingActions)
                  .toList(growable: false);
              overflowTrailingActions = widget.trailingActions
                  .skip(maxTrailingActions)
                  .toList(growable: false);
            } else {
              inlineTrailingActions = widget.trailingActions;
              overflowTrailingActions = const <AppSearchBarAction>[];
            }

            return AppActionLabelScope(
              showLabels: showActionLabels,
              forceIconOnly: !showActionLabels,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _fillColor(theme, canEdit),
                  border: theme.borders.all(color: borderSide.color,
                    width: borderSide.width),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minHeight),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Semantics(
                          textField: true,
                          enabled: canEdit,
                          label: widget.semanticLabel,
                          child: TextFormField(
                            controller: widget.controller,
                            enabled: canEdit,
                            focusNode: _focusNode,
                            autofocus: widget.autofocus,
                            textInputAction: TextInputAction.search,
                            maxLines: 1,
                            maxLength: widget.maxLength,
                            maxLengthEnforcement: widget.maxLength == null
                                ? MaxLengthEnforcement.none
                                : MaxLengthEnforcement.enforced,
                            inputFormatters: <TextInputFormatter>[
                              // Keep search single-line when pasting paragraphs.
                              FilteringTextInputFormatter.deny(
                                RegExp(r'[\r\n]+'),
                                replacementString: ' ',
                              ),
                            ],
                            onChanged: widget.onChanged,
                            onFieldSubmitted: widget.onSubmitted,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: canEdit
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurface.withValues(
                                      alpha: 0.62,
                                    ),
                              fontWeight: AppFontWeight.regular,
                            ),
                            decoration: InputDecoration(
                              hintText: widget.hintText,
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _suffixIcon(clearLabel, canClear),
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              focusedErrorBorder: InputBorder.none,
                              // Hide the default "0/255" counter under the field.
                              counterText: '',
                            ),
                          ),
                        ),
                      ),
                      if (showFilters ||
                          inlineTrailingActions.isNotEmpty ||
                          overflowTrailingActions.isNotEmpty) ...<Widget>[
                        ..._searchBarActionChrome(
                          theme: theme,
                          showFilters: showFilters,
                          showActionLabels: showActionLabels,
                          inlineTrailingActions: inlineTrailingActions,
                          overflowTrailingActions: overflowTrailingActions,
                        ),
                        // End inset so the last chrome action is not flush against
                        // the search bar border on any breakpoint.
                        SizedBox(width: theme.spacing.sm),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<Widget> _searchBarActionChrome({
    required ThemeData theme,
    required bool showFilters,
    required bool showActionLabels,
    required List<AppSearchBarAction> inlineTrailingActions,
    required List<AppSearchBarAction> overflowTrailingActions,
  }) {
    final List<Widget> actions = <Widget>[
      if (showFilters)
        _AttachedFilterButton(
          enabled: widget.enabled && !widget.isLoading,
          active:
              widget.hasActiveFilters || widget.filterValue.isActive,
          activeCount: widget.filterValue.activeCount,
          label: widget.advancedFilterButtonLabel ?? 'Filter',
          showLabel: showActionLabels,
          onPressed: _openAdvancedFilters,
        ),
      for (final AppSearchBarAction action in inlineTrailingActions)
        _AttachedSearchBarActionButton(
          action: action,
          showLabel: showActionLabels,
          enabled:
              widget.enabled &&
              !widget.isLoading &&
              action.enabled &&
              action.onPressed != null,
        ),
      if (overflowTrailingActions.isNotEmpty)
        _AttachedSearchBarOverflowMenu(
          actions: overflowTrailingActions,
          label: widget.trailingActionsOverflowLabel,
          showLabel: showActionLabels,
          enabled: widget.enabled && !widget.isLoading,
        ),
    ];

    final List<Widget> chrome = <Widget>[];
    for (int index = 0; index < actions.length; index += 1) {
      if (index > 0) {
        chrome.add(
          SizedBox(
            height: 20,
            child: VerticalDivider(
              width: theme.spacing.sm,
              thickness: theme.appTokens.dividerThickness,
              color: theme.borders.faint,
            ),
          ),
        );
      }
      chrome.add(actions[index]);
    }
    return chrome;
  }

  Widget? _suffixIcon(String clearLabel, bool canClear) {
    final bool showSpeech = widget.enableSpeechToText;
    if (!widget.isLoading && !canClear && !showSpeech) {
      return null;
    }

    final ThemeData theme = Theme.of(context);
    final double width =
        48.0 +
        (canClear ? 28.0 : 0.0) +
        (showSpeech ? 28.0 : 0.0) +
        (widget.isLoading ? 28.0 : 0.0);
    return SizedBox(
      width: width,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (canClear)
            AppActionLabelScope(
              key: const ValueKey<String>('app-search-bar-clear'),
              showLabels: false,
              forceIconOnly: true,
              child: AppButton(
                iconOnly: true,
                leadingIcon: Icons.close,
                label: clearLabel,
                semanticLabel: clearLabel,
                tooltip: clearLabel,
                onPressed: _clear,
              ),
            ),
          if (showSpeech)
            // Keyed so the clear action appearing mid-dictation does not
            // rebuild this element at a new index and cancel the session.
            AppSpeechToTextButton(
              key: const ValueKey<String>('app-search-bar-speech'),
              controller: widget.controller,
              enabled: widget.enabled && !widget.isLoading,
              dense: true,
              transcriptTransform: appSpeechTextTranscript,
              aiFormatMode: 'text',
              onChanged: widget.onChanged,
            ),
          if (widget.isLoading)
            Padding(
              padding: EdgeInsetsDirectional.only(end: theme.spacing.sm),
              child: SizedBox.square(
                dimension: theme.appTokens.listIconSize * 0.82,
                child: const CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }

  BorderSide _borderSide(ThemeData theme) {
    if (!widget.enabled) {
      return _sideFromBorder(theme.inputDecorationTheme.disabledBorder) ??
          theme.borders.side();
    }

    if (_focusNode.hasFocus) {
      return _sideFromBorder(theme.inputDecorationTheme.focusedBorder) ??
          theme.borders.side(
            tone: AppBorderTone.focused,
            weight: AppBorderWeight.medium,
          );
    }

    return _sideFromBorder(theme.inputDecorationTheme.enabledBorder) ??
        theme.borders.side(color: theme.borders.inputIdle);
  }

  BorderSide? _sideFromBorder(InputBorder? border) {
    if (border is OutlineInputBorder) {
      return border.borderSide;
    }
    if (border is UnderlineInputBorder) {
      return border.borderSide;
    }
    return null;
  }

  Color _fillColor(ThemeData theme, bool canEdit) {
    final Color fallback = canEdit
        ? theme.colorScheme.surface
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.38);
    return theme.inputDecorationTheme.fillColor ?? fallback;
  }

  bool get _shouldShowFilterButton {
    return widget.showAdvancedFilterButton ||
        widget.onAdvancedFilterPressed != null ||
        widget.onFilterChanged != null ||
        widget.searchFields.isNotEmpty ||
        widget.textFilters.isNotEmpty ||
        widget.filterGroups.isNotEmpty;
  }

  void _clear() {
    widget.controller.clear();
    widget.onChanged?.call('');
    widget.onClear?.call();
  }

  Future<void> _openAdvancedFilters() async {
    if (!widget.enabled || widget.isLoading) {
      return;
    }

    final VoidCallback? customHandler = widget.onAdvancedFilterPressed;
    if (customHandler != null) {
      customHandler();
      return;
    }

    await showAppDialog<AppSearchBarFilterValue>(
      context: context,
      builder: (_) => _AppSearchBarFiltersDialog(
        title: widget.advancedFilterTitle ?? 'Advanced filters',
        applyLabel: widget.advancedFilterApplyLabel ?? 'Apply filters',
        resetLabel: widget.advancedFilterResetLabel ?? 'Reset filters',
        closeLabel: widget.advancedFilterCloseLabel ?? 'Close',
        resetAppliesImmediately: widget.advancedFilterResetAppliesImmediately,
        searchFields: widget.searchFields,
        textFilters: widget.textFilters,
        searchFieldLabel: widget.searchFieldLabel ?? 'Search in',
        allFieldsLabel: widget.allFieldsLabel ?? 'All fields',
        enableDateFilter: widget.enableDateFilter,
        dateFilterLabel: widget.dateFilterLabel ?? 'Date',
        dateFromLabel: widget.dateFromLabel ?? 'From',
        dateToLabel: widget.dateToLabel ?? 'To',
        datePickerButtonLabel: widget.datePickerButtonLabel ?? 'Choose date',
        invalidDateMessage: widget.invalidDateMessage ?? 'Enter a valid date.',
        firstDate: widget.firstDate ?? DateTime(1900),
        lastDate: widget.lastDate ?? _defaultLastDate(),
        currentDate: widget.currentDate,
        filterGroups: widget.filterGroups,
        initialValue: widget.filterValue,
        onApplying: widget.onFilterChanged == null
            ? null
            : (AppSearchBarFilterValue next) async {
                widget.onFilterChanged!(next);
                // Let the parent rebuild filtered rows while the dialog stays busy.
                await Future<void>.delayed(Duration.zero);
              },
      ),
    );
  }

  DateTime _defaultLastDate() {
    final DateTime now = DateTime.now();
    return DateTime(now.year + 20, 12, 31);
  }
}

class _AttachedSearchBarActionButton extends StatelessWidget {
  const _AttachedSearchBarActionButton({
    required this.action,
    required this.enabled,
    required this.showLabel,
  });

  final AppSearchBarAction action;
  final bool enabled;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return _AttachedSearchBarButton(
      enabled: enabled,
      active: action.active,
      showLabel: showLabel,
      icon: action.icon,
      label: action.label,
      tooltip: action.tooltip,
      onPressed: action.onPressed,
      foregroundColor: action.destructive ? colorScheme.error : null,
    );
  }
}

class _AttachedSearchBarOverflowMenu extends StatelessWidget {
  const _AttachedSearchBarOverflowMenu({
    required this.actions,
    required this.label,
    required this.showLabel,
    required this.enabled,
  });

  final List<AppSearchBarAction> actions;
  final String label;
  final bool showLabel;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return MenuAnchor(
      style: MenuStyle(
        visualDensity: VisualDensity.compact,
        alignment: AlignmentDirectional.bottomEnd,
        padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.all(theme.spacing.xs),
        ),
      ),
      builder:
          (BuildContext context, MenuController controller, Widget? child) {
            return _AttachedSearchBarButton(
              enabled: enabled,
              active: controller.isOpen,
              showLabel: showLabel,
              icon: Icons.more_vert,
              label: label,
              tooltip: label,
              onPressed: enabled
                  ? () {
                      if (controller.isOpen) {
                        controller.close();
                      } else {
                        controller.open();
                      }
                    }
                  : null,
            );
          },
      menuChildren: <Widget>[
        for (final AppSearchBarAction action in actions)
          MenuItemButton(
            onPressed: enabled && action.enabled && action.onPressed != null
                ? action.onPressed
                : null,
            leadingIcon: Icon(
              action.icon,
              color: action.destructive ? colorScheme.error : null,
            ),
            child: Text(action.label),
          ),
      ],
    );
  }
}

class _AttachedFilterButton extends StatelessWidget {
  const _AttachedFilterButton({
    required this.enabled,
    required this.active,
    required this.activeCount,
    required this.label,
    required this.showLabel,
    required this.onPressed,
  });

  final bool enabled;
  final bool active;
  final int activeCount;
  final String label;
  final bool showLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final String effectiveLabel = activeCount > 0
        ? '$label ($activeCount)'
        : label;
    return Badge(
      isLabelVisible: activeCount > 0,
      label: Text('$activeCount'),
      child: _AttachedSearchBarButton(
        enabled: enabled,
        active: active,
        showLabel: showLabel,
        icon: active ? Icons.filter_alt : Icons.filter_alt_outlined,
        label: effectiveLabel,
        onPressed: onPressed,
      ),
    );
  }
}

/// Flat search-bar chrome action: icon (+ optional label), no fill.
/// Adjacent actions are separated by a thin vertical rule in [AppSearchBar].
class _AttachedSearchBarButton extends StatelessWidget {
  const _AttachedSearchBarButton({
    required this.enabled,
    required this.active,
    required this.showLabel,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
    this.foregroundColor,
  });

  final bool enabled;
  final bool active;
  final bool showLabel;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final Color foreground =
        foregroundColor ??
        (active ? colorScheme.primary : colorScheme.onSurfaceVariant);
    final bool canPress = enabled && onPressed != null;
    final String resolvedTooltip = tooltip ?? label;

    final Widget button = TextButton(
      onPressed: canPress ? onPressed : null,
      style: TextButton.styleFrom(
        foregroundColor: foreground,
        disabledForegroundColor: colorScheme.onSurface.withValues(alpha: 0.38),
        padding: EdgeInsets.symmetric(horizontal: theme.spacing.xs),
        minimumSize: Size(theme.spacing.none, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        backgroundColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18),
          if (showLabel) ...<Widget>[
            SizedBox(width: theme.spacing.xs),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: foreground,
                fontWeight: AppFontWeight.emphasis,
              ),
            ),
          ],
        ],
      ),
    );

    return Tooltip(
      message: resolvedTooltip,
      child: Semantics(
        button: true,
        enabled: canPress,
        label: label,
        child: button,
      ),
    );
  }
}

class _AppSearchBarFiltersDialog extends StatefulWidget {
  const _AppSearchBarFiltersDialog({
    required this.title,
    required this.applyLabel,
    required this.resetLabel,
    required this.closeLabel,
    required this.resetAppliesImmediately,
    required this.searchFields,
    required this.textFilters,
    required this.searchFieldLabel,
    required this.allFieldsLabel,
    required this.enableDateFilter,
    required this.dateFilterLabel,
    required this.dateFromLabel,
    required this.dateToLabel,
    required this.datePickerButtonLabel,
    required this.invalidDateMessage,
    required this.firstDate,
    required this.lastDate,
    required this.currentDate,
    required this.filterGroups,
    required this.initialValue,
    this.onApplying,
  });

  final String title;
  final String applyLabel;
  final String resetLabel;
  final String closeLabel;
  final bool resetAppliesImmediately;
  final List<AppSearchBarFieldChoice> searchFields;
  final List<AppSearchBarTextFilter> textFilters;
  final String searchFieldLabel;
  final String allFieldsLabel;
  final bool enableDateFilter;
  final String dateFilterLabel;
  final String dateFromLabel;
  final String dateToLabel;
  final String datePickerButtonLabel;
  final String invalidDateMessage;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime? currentDate;
  final List<AppSearchBarFilterGroup> filterGroups;
  final AppSearchBarFilterValue initialValue;
  final Future<void> Function(AppSearchBarFilterValue value)? onApplying;

  @override
  State<_AppSearchBarFiltersDialog> createState() =>
      _AppSearchBarFiltersDialogState();
}

class _AppSearchBarFiltersDialogState
    extends State<_AppSearchBarFiltersDialog> {
  static const String _allValue = '__all__';
  static const Duration _applyBusyHold = Duration(milliseconds: 220);

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late String? _field;
  late DateTime? _dateFrom;
  late DateTime? _dateTo;
  late Map<String, TextEditingController> _textControllers;
  late Map<String, String> _options;
  late Map<String, Set<String>> _selections;
  String? _dateRangeError;
  bool _isApplying = false;
  OverlayEntry? _applyOverlay;

  @override
  void initState() {
    super.initState();
    _textControllers = <String, TextEditingController>{
      for (final AppSearchBarTextFilter filter in widget.textFilters)
        filter.key: TextEditingController(),
    };
    _hydrate(widget.initialValue);
  }

  @override
  void dispose() {
    _removeApplyOverlay();
    for (final TextEditingController controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool canInteract = !_isApplying;

    return AppDialog(
      title: Text(widget.title),
      icon: const Icon(Icons.filter_alt_outlined),
      scrollable: true,
      // A filter form is as tall as its filters; a maximized shell would only
      // add empty space under them.
      initialMaximized: false,
      sizeToContent: true,
      closeEnabled: canInteract,
      maxWidth: 760,
      content: AppFieldRequirementScope(
        showOptionalIndicators: false,
        child: Form(
          key: _formKey,
          child: AbsorbPointer(
            absorbing: !canInteract,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _spacedPanels(theme, _panels(theme)),
            ),
          ),
        ),
      ),
      actions: <Widget>[
        AppButton.tertiary(
          label: widget.resetLabel,
          leadingIcon: Icons.filter_alt_off_outlined,
          enabled: canInteract,
          onPressed: canInteract ? _reset : null,
        ),
        AppButton.primary(
          label: widget.applyLabel,
          leadingIcon: Icons.check,
          enabled: canInteract,
          onPressed: canInteract ? _apply : null,
        ),
        AppButton.close(
          label: widget.closeLabel,
          leadingIcon: Icons.close,
          enabled: canInteract,
          onPressed: canInteract ? () => Navigator.of(context).pop() : null,
        ),
      ],
    );
  }

  /// Spaces the panels evenly down the dialog.
  List<Widget> _spacedPanels(ThemeData theme, List<Widget> panels) {
    return <Widget>[
      for (int index = 0; index < panels.length; index++) ...<Widget>[
        if (index > 0) SizedBox(height: theme.spacing.md),
        panels[index],
      ],
    ];
  }

  /// Every filter the caller offers, grouped into titled panels: what to search
  /// in, when it happened, then one panel per set of choices.
  List<Widget> _panels(ThemeData theme) {
    final bool hasSearchPanel =
        widget.searchFields.isNotEmpty || widget.textFilters.isNotEmpty;
    final List<AppSearchBarFilterGroup> groups = widget.filterGroups
        .where(_hasFilterChoices)
        .toList(growable: false);

    return <Widget>[
      if (hasSearchPanel)
        _FilterPanel(
          icon: Icons.manage_search_outlined,
          title: widget.searchFieldLabel,
          isActive: _field != null || _textControllers.values.any(_hasEntry),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (widget.searchFields.isNotEmpty)
                AppSelectField<String>.searchable(
                  value: _field,
                  hintText: widget.allFieldsLabel,
                  options: <AppSelectOption<String>>[
                    AppSelectOption<String>(
                      value: _allValue,
                      label: widget.allFieldsLabel,
                      leadingIcon: const Icon(Icons.manage_search_outlined),
                    ),
                    for (final AppSearchBarFieldChoice field
                        in widget.searchFields)
                      AppSelectOption<String>(
                        value: field.field,
                        label: field.label,
                        leadingIcon: field.icon == null
                            ? null
                            : Icon(field.icon),
                      ),
                  ],
                  onChanged: (String? value) {
                    setState(() {
                      _field = value == null || value == _allValue
                          ? null
                          : value;
                    });
                  },
                ),
              if (widget.searchFields.isNotEmpty &&
                  widget.textFilters.isNotEmpty)
                SizedBox(height: theme.spacing.md),
              if (widget.textFilters.isNotEmpty)
                _ResponsiveFilterGrid(
                  children: <Widget>[
                    for (final AppSearchBarTextFilter filter
                        in widget.textFilters)
                      AppTextField(
                        controller: _textControllers[filter.key],
                        labelText: filter.label,
                        hintText: filter.hintText,
                        prefixIcon: filter.icon == null
                            ? null
                            : Icon(filter.icon),
                        keyboardType: filter.keyboardType,
                        textInputAction:
                            filter.textInputAction ?? TextInputAction.next,
                      ),
                  ],
                ),
            ],
          ),
        ),
      if (widget.enableDateFilter)
        _FilterPanel(
          icon: Icons.event_outlined,
          title: widget.dateFilterLabel,
          isActive: _dateFrom != null || _dateTo != null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _ResponsiveFilterRow(
                left: AppDateField(
                  value: _dateFrom,
                  firstDate: widget.firstDate,
                  lastDate: widget.lastDate,
                  currentDate: widget.currentDate,
                  pickerButtonLabel: widget.datePickerButtonLabel,
                  invalidDateMessage: widget.invalidDateMessage,
                  labelText: widget.dateFromLabel,
                  onChanged: (DateTime? value) {
                    setState(() {
                      _dateFrom = value;
                      _dateRangeError = null;
                    });
                  },
                ),
                right: AppDateField(
                  value: _dateTo,
                  firstDate: widget.firstDate,
                  lastDate: widget.lastDate,
                  currentDate: widget.currentDate,
                  pickerButtonLabel: widget.datePickerButtonLabel,
                  invalidDateMessage: widget.invalidDateMessage,
                  labelText: widget.dateToLabel,
                  onChanged: (DateTime? value) {
                    setState(() {
                      _dateTo = value;
                      _dateRangeError = null;
                    });
                  },
                ),
              ),
              if (_dateRangeError != null) ...<Widget>[
                SizedBox(height: theme.spacing.xs),
                Text(
                  _dateRangeError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      if (groups.isNotEmpty)
        _FilterPanelGrid(
          children: <Widget>[
            for (final AppSearchBarFilterGroup group in groups)
              _groupPanel(group),
          ],
        ),
    ];
  }

  /// One panel per filter group: the group's name is the panel heading, so the
  /// control inside carries only its values.
  Widget _groupPanel(AppSearchBarFilterGroup group) {
    if (!group.allowMultiple) {
      final String? selected = _options[group.key];
      return _FilterPanel(
        icon: Icons.tune_outlined,
        title: group.label,
        isActive: selected != null,
        child: AppSelectField<String>.searchable(
          value: selected,
          hintText: group.allLabel ?? widget.allFieldsLabel,
          options: <AppSelectOption<String>>[
            AppSelectOption<String>(
              value: _allValue,
              label: group.allLabel ?? widget.allFieldsLabel,
              leadingIcon: const Icon(Icons.filter_list_off),
            ),
            for (final AppSearchBarFilterChoice choice in group.choices)
              AppSelectOption<String>(
                value: choice.value,
                label: choice.label,
                leadingIcon: choice.icon == null ? null : Icon(choice.icon),
              ),
          ],
          onChanged: (String? value) {
            setState(() {
              final Map<String, String> next = Map<String, String>.of(_options);
              if (value == null || value == _allValue) {
                next.remove(group.key);
              } else {
                next[group.key] = value;
              }
              _options = next;
            });
          },
        ),
      );
    }

    final Set<String> selected = _selections[group.key] ?? const <String>{};
    return _FilterPanel(
      icon: Icons.checklist_outlined,
      title: group.label,
      isActive: selected.isNotEmpty,
      child: _MultiSelectFilterGroup(
        group: group,
        selected: selected,
        onChanged: (Set<String> values) {
          setState(() {
            final Map<String, Set<String>> next = _copySelections(_selections);
            if (values.isEmpty) {
              next.remove(group.key);
            } else {
              next[group.key] = values;
            }
            _selections = next;
          });
        },
      ),
    );
  }

  static bool _hasEntry(TextEditingController controller) {
    return controller.text.trim().isNotEmpty;
  }

  void _hydrate(AppSearchBarFilterValue value) {
    _field = _knownField(value.field);
    _dateFrom = value.dateFrom;
    _dateTo = value.dateTo;
    final Map<String, String> texts = _knownTexts(value.texts);
    for (final AppSearchBarTextFilter filter in widget.textFilters) {
      _textControllers[filter.key]?.text = texts[filter.key] ?? '';
    }
    _options = _knownOptions(value.options);
    _selections = _knownSelections(value.selections);
    _dateRangeError = null;
  }

  void _reset() {
    if (_isApplying) {
      return;
    }
    if (widget.resetAppliesImmediately) {
      unawaited(_commitAndClose(AppSearchBarFilterValue.empty));
      return;
    }
    setState(() {
      _hydrate(AppSearchBarFilterValue.empty);
    });
  }

  Future<void> _apply() async {
    if (_isApplying) {
      return;
    }
    final bool isValid = _formKey.currentState?.validate() ?? true;
    if (!isValid) {
      return;
    }
    if (!appSearchBarDateRangeIsValid(_dateFrom, _dateTo)) {
      setState(() => _dateRangeError = widget.invalidDateMessage);
      return;
    }
    await _commitAndClose(_value);
  }

  Future<void> _commitAndClose(AppSearchBarFilterValue value) async {
    setState(() => _isApplying = true);
    _showApplyOverlay();
    // Paint the busy/disabled state before applying filters.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      _removeApplyOverlay();
      return;
    }

    final Future<void> Function(AppSearchBarFilterValue value)? onApplying =
        widget.onApplying;
    try {
      if (onApplying != null) {
        await onApplying(value);
        if (!mounted) {
          return;
        }
      }

      await Future<void>.delayed(_applyBusyHold);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(value);
    } finally {
      _removeApplyOverlay();
    }
  }

  void _showApplyOverlay() {
    _removeApplyOverlay();
    final OverlayState? overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      return;
    }

    final String title = context.l10n.commonLoadingTitle;
    final String body = context.l10n.commonLoadingBody;

    _applyOverlay = OverlayEntry(
      builder: (BuildContext overlayContext) {
        return IgnorePointer(
          child: Center(
            child: AppLoadingIndicator(
              size: AppLoadingIndicatorSize.large,
              title: title,
              body: body,
              expand: false,
              semanticLabel: title,
            ),
          ),
        );
      },
    );
    overlay.insert(_applyOverlay!);
  }

  void _removeApplyOverlay() {
    _applyOverlay?.remove();
    _applyOverlay = null;
  }

  AppSearchBarFilterValue get _value {
    return AppSearchBarFilterValue(
      field: _field,
      dateFrom: _dateFrom,
      dateTo: _dateTo,
      texts: Map<String, String>.unmodifiable(<String, String>{
        for (final MapEntry<String, TextEditingController> entry
            in _textControllers.entries)
          if (_hasText(entry.value.text)) entry.key: entry.value.text.trim(),
      }),
      options: Map<String, String>.unmodifiable(_options),
      selections: Map<String, Set<String>>.unmodifiable(
        _copySelections(_selections),
      ),
    );
  }

  String? _knownField(String? field) {
    if (!_hasText(field)) {
      return null;
    }
    final bool exists = widget.searchFields.any(
      (AppSearchBarFieldChoice choice) => choice.field == field,
    );
    return exists ? field : null;
  }

  Map<String, String> _knownTexts(Map<String, String> texts) {
    final Set<String> knownKeys = widget.textFilters
        .map((AppSearchBarTextFilter filter) => filter.key)
        .toSet();
    return <String, String>{
      for (final MapEntry<String, String> entry in texts.entries)
        if (knownKeys.contains(entry.key) && _hasText(entry.value))
          entry.key: entry.value.trim(),
    };
  }

  Map<String, String> _knownOptions(Map<String, String> options) {
    final Map<String, String> known = <String, String>{};
    for (final AppSearchBarFilterGroup group in widget.filterGroups) {
      final String? value = options[group.key];
      if (!_hasText(value)) {
        continue;
      }
      final bool exists = group.choices.any(
        (AppSearchBarFilterChoice choice) => choice.value == value,
      );
      if (exists) {
        known[group.key] = value!;
      }
    }
    return known;
  }

  Map<String, Set<String>> _knownSelections(
    Map<String, Set<String>> selections,
  ) {
    final Map<String, Set<String>> known = <String, Set<String>>{};
    for (final AppSearchBarFilterGroup group in widget.filterGroups) {
      if (!group.allowMultiple) {
        continue;
      }
      final Set<String> available = group.choices
          .map((AppSearchBarFilterChoice choice) => choice.value)
          .toSet();
      final Set<String> values = (selections[group.key] ?? const <String>{})
          .where(available.contains)
          .toSet();
      if (values.isNotEmpty) {
        known[group.key] = values;
      }
    }
    return known;
  }
}

Map<String, Set<String>> _copySelections(Map<String, Set<String>> source) {
  return <String, Set<String>>{
    for (final MapEntry<String, Set<String>> entry in source.entries)
      entry.key: Set<String>.of(entry.value),
  };
}

/// Every choice in a multi-select group, laid out as a checklist.
class _MultiSelectFilterGroup extends StatelessWidget {
  const _MultiSelectFilterGroup({
    required this.group,
    required this.selected,
    required this.onChanged,
  });

  final AppSearchBarFilterGroup group;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Semantics(
      container: true,
      label: group.label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int index = 0; index < group.choices.length; index++) ...<Widget>[
            if (index > 0) SizedBox(height: theme.spacing.xs),
            Builder(
              builder: (BuildContext context) {
                final AppSearchBarFilterChoice choice = group.choices[index];
                final bool isSelected = selected.contains(choice.value);
                return AppCheckboxField(
                  title: choice.label,
                  value: isSelected,
                  semanticLabel: choice.label,
                  secondary: choice.icon == null ? null : Icon(choice.icon),
                  onChanged: (bool checked) {
                    final Set<String> next = Set<String>.of(selected);
                    if (checked) {
                      next.add(choice.value);
                    } else {
                      next.remove(choice.value);
                    }
                    onChanged(next);
                  },
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

bool _hasFilterChoices(AppSearchBarFilterGroup group) {
  return group.choices.isNotEmpty;
}

/// One titled block of related filter controls.
///
/// The heading names the block, so the controls inside need no label of their
/// own, and a block that currently narrows the list is outlined as selected —
/// an open dialog then shows at a glance which filters are doing work.
class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.icon,
    required this.title,
    required this.child,
    this.isActive = false,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final Color accent = isActive
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(theme.radius.md),
        border: isActive
            ? theme.borders.all(tone: AppBorderTone.selected)
            : theme.borders.all(),
      ),
      child: Padding(
        padding: EdgeInsets.all(theme.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(theme.radius.xs),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(theme.spacing.xs),
                    child: Icon(
                      icon,
                      size: theme.appTokens.listIconSize,
                      color: accent,
                    ),
                  ),
                ),
                SizedBox(width: theme.spacing.sm),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: AppFontWeight.emphasis,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: theme.spacing.sm),
            child,
          ],
        ),
      ),
    );
  }
}

/// Lays filter-group panels out two to a row once there is room.
class _FilterPanelGrid extends StatelessWidget {
  const _FilterPanelGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double spacing = theme.spacing.md;
        final bool twoColumns = constraints.maxWidth >= 620;
        final double itemWidth = twoColumns
            ? (constraints.maxWidth - spacing) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: <Widget>[
            for (final Widget child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

class _FilterControlShell extends StatelessWidget {
  const _FilterControlShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: Theme.of(context).spacing.xs),
      child: child,
    );
  }
}

class _ResponsiveFilterGrid extends StatelessWidget {
  const _ResponsiveFilterGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double spacing = theme.spacing.md;
        final bool twoColumns = constraints.maxWidth >= 620;
        final double itemWidth = twoColumns
            ? (constraints.maxWidth - spacing) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: spacing,
          runSpacing: theme.spacing.md,
          children: <Widget>[
            for (final Widget child in children)
              SizedBox(
                width: itemWidth,
                child: _FilterControlShell(child: child),
              ),
          ],
        );
      },
    );
  }
}

class _ResponsiveFilterRow extends StatelessWidget {
  const _ResponsiveFilterRow({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              left,
              SizedBox(height: theme.spacing.sm),
              right,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: left),
            SizedBox(width: theme.spacing.sm),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

bool _hasText(String? value) {
  return value != null && value.trim().isNotEmpty;
}
