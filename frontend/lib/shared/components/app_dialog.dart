import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/core/responsive/app_breakpoints.dart';
import 'package:hosspi_hms/core/utils/app_dialog_title.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/components/app_action_label_scope.dart';
import 'package:hosspi_hms/shared/components/app_button.dart';
import 'package:hosspi_hms/shared/components/app_dialog_action.dart';
import 'package:hosspi_hms/shared/components/app_field_label.dart';
import 'package:hosspi_hms/shared/icons/app_action_icons.dart';
import 'package:hosspi_hms/shared/layout/app_dialog_insets.dart';
import 'package:hosspi_hms/shared/layout/app_overflow_menu_style.dart';

class AppDialog extends StatefulWidget {
  const AppDialog({
    this.title,
    this.content,
    this.actions = const <Widget>[],
    this.icon,
    this.semanticLabel,
    this.scrollable = false,
    this.pinActionsToBottom = false,
    this.stackActionsWhenCompact = false,
    this.denseActions = true,
    this.showCloseButton = true,
    this.showMaximizeButton = true,
    this.resizable = true,
    this.closeEnabled = true,
    this.initialMaximized = true,
    this.sizeToContent = false,
    this.surfaceOpacity = 1,
    this.maxWidth = _defaultMaxWidth,
    this.cornerRadius,
    this.contentPadding,
    super.key,
  });

  static const double _defaultMaxWidth = 600;

  /// Prefix for per-instance shell keys on the dialog [SizedBox].
  ///
  /// Keys must be unique across nested [AppDialog]s (Overlay siblings). A shared
  /// [ValueKey] causes element-tree assertions such as `_elements.contains`.
  @visibleForTesting
  static const String shellKeyPrefix = 'appDialogShell';

  /// Whether [key] identifies an [AppDialog] shell box (any nested instance).
  @visibleForTesting
  static bool isShellKey(Key? key) {
    return key is ValueKey<String> && key.value.startsWith(shellKeyPrefix);
  }

  final Widget? title;
  final Widget? content;
  final List<Widget> actions;
  final Widget? icon;
  final String? semanticLabel;
  final bool scrollable;
  final bool pinActionsToBottom;

  /// Overrides default body inset around [content].
  ///
  /// Use [EdgeInsets.zero] for dense full-bleed surfaces (e.g. print preview).
  final EdgeInsetsGeometry? contentPadding;

  /// When true, compact/mobile footers stack actions full-width.
  ///
  /// Default false: keep a right-aligned horizontal row of icon + label
  /// actions, moving the lowest-priority ones into a "More actions" menu when
  /// they do not fit (see [AppDialogActionPriority]). Opt into stacking only
  /// when a call site needs every action visible without a menu.
  final bool stackActionsWhenCompact;

  /// When true (default), footer uses compact chrome padding and dense action
  /// buttons. Prefer leaving this on for consistent dialog chrome.
  final bool denseActions;
  final bool showCloseButton;
  final bool showMaximizeButton;
  final bool resizable;
  final bool closeEnabled;
  final bool initialMaximized;

  /// When true, a restored (non-maximized) shell is only as tall as its
  /// content, up to the height the viewport allows. Use it with
  /// `initialMaximized: false` for short forms that should not open as a tall,
  /// mostly empty panel. Content past that height still scrolls.
  final bool sizeToContent;

  /// Opacity of the dialog's own surfaces — body, header, and footer — from 0
  /// to 1.
  ///
  /// Below 1 the screen behind shows through, so the user can see the part of
  /// the app they are writing about. Controls that carry their own opaque
  /// colour, such as text fields, stay readable on top of it. Pair it with a
  /// see-through barrier ([showAppDialog]'s `barrierColor`).
  final double surfaceOpacity;
  final double maxWidth;

  /// Overrides dialog shell corner radius. Use `0` for square forms.
  /// When null, maximized shells stay square and restored shells use theme lg.
  final double? cornerRadius;

  @override
  State<AppDialog> createState() => _AppDialogState();
}

class _AppDialogState extends State<AppDialog> {
  final GlobalKey _dialogShellKey = GlobalKey(debugLabel: 'appDialogShell');

  Offset _dragOffset = Offset.zero;
  Size? _desktopSize;
  Size? _preMaximizeSize;
  Offset? _preMaximizeDragOffset;
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialMaximized) {
      _isMaximized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final AppDesignTokens designTokens = theme.appTokens;
    final Size viewport = MediaQuery.sizeOf(context);
    final AppBreakpoint breakpoint = AppBreakpoints.of(context);
    final bool compact = breakpoint.index < AppBreakpoint.md.index;
    final bool desktopInteractive = breakpoint.index >= AppBreakpoint.md.index;
    final EdgeInsets insetPadding = AppDialogInsets.paddingFor(
      breakpoint,
      designTokens: designTokens,
      maximized: _isMaximized,
    );
    final double maxHeight = math.max(
      theme.spacing.none,
      viewport.height - insetPadding.vertical,
    );
    final double availableWidth = math.max(
      theme.spacing.none,
      viewport.width - insetPadding.horizontal,
    );
    final double defaultWidth = widget.maxWidth.isFinite
        ? math.min(widget.maxWidth, availableWidth)
        : availableWidth;
    final double defaultScrollableHeight = _defaultScrollableShellHeight(
      maxHeight,
      designTokens,
    );
    final Size? desktopSize = _desktopSize;
    final double shellWidth = _isMaximized
        ? availableWidth
        : (desktopSize?.width ?? defaultWidth);
    final double shellHeight = _isMaximized
        ? maxHeight
        : (desktopSize?.height ??
              (widget.scrollable &&
                      desktopInteractive &&
                      !widget.sizeToContent
                  ? defaultScrollableHeight
                  : maxHeight));
    final BoxConstraints dialogConstraints = BoxConstraints(
      maxWidth: _isMaximized || desktopInteractive ? shellWidth : defaultWidth,
      maxHeight: shellHeight,
    );
    final bool resizeEnabled =
        desktopInteractive && !_isMaximized && widget.resizable;
    final bool pinFooter =
        widget.pinActionsToBottom && widget.actions.isNotEmpty;
    // A content-sized shell never stretches to a fixed height; the footer sits
    // under the content instead of being pinned to the bottom of the viewport.
    final bool hugContent = widget.sizeToContent && !_isMaximized;
    final bool fillShellHeight =
        !hugContent &&
        (pinFooter ||
            _isMaximized ||
            (desktopInteractive && desktopSize != null) ||
            (desktopInteractive && widget.scrollable && !_isMaximized));

    final Widget dialogContent = DecoratedBox(
      decoration: BoxDecoration(
        border: theme.borders.all(),
      ),
      child: _DialogBody(
        title: widget.title,
        content: widget.content,
        actions: widget.actions,
        icon: widget.icon,
        scrollable: widget.scrollable,
        fillHeight: fillShellHeight,
        hugContent: hugContent,
        surfaceOpacity: widget.surfaceOpacity,
        compact: compact,
        stackActionsWhenCompact: widget.stackActionsWhenCompact,
        denseActions: widget.denseActions,
        showCloseButton: widget.showCloseButton,
        showMaximizeButton: widget.showMaximizeButton && desktopInteractive,
        isMaximized: _isMaximized,
        closeEnabled: widget.closeEnabled,
        contentPadding: widget.contentPadding,
        chromeBorderRadius: widget.cornerRadius,
        onMaximizeToggle: desktopInteractive ? _toggleMaximize : null,
        onHeaderDragUpdate: desktopInteractive && !_isMaximized
            ? (DragUpdateDetails details) {
                _handleDrag(details, viewport, insetPadding);
              }
            : null,
      ),
    );

    final bool enforceShellHeight = !hugContent && (pinFooter || fillShellHeight);
    Widget dialogBody = ConstrainedBox(
      constraints: desktopInteractive
          ? BoxConstraints(
              minHeight: enforceShellHeight ? dialogConstraints.maxHeight : 0,
              maxHeight: dialogConstraints.maxHeight,
            )
          : enforceShellHeight
          ? BoxConstraints(
              minHeight: dialogConstraints.maxHeight,
              maxHeight: dialogConstraints.maxHeight,
            )
          : dialogConstraints,
      child: DecoratedBox(
        decoration: const BoxDecoration(),
        child: dialogContent,
      ),
    );

    if (desktopInteractive || enforceShellHeight || _isMaximized) {
      dialogBody = SizedBox(
        // Unique per State so nested AppDialogs do not share an Overlay key.
        key: desktopInteractive || _isMaximized
            ? ValueKey<String>(
                '${AppDialog.shellKeyPrefix}-${identityHashCode(this)}',
              )
            : null,
        width: _isMaximized || desktopInteractive
            ? dialogConstraints.maxWidth
            : null,
        height: fillShellHeight ? dialogConstraints.maxHeight : null,
        child: KeyedSubtree(
          key: desktopInteractive || _isMaximized ? _dialogShellKey : null,
          child: dialogBody,
        ),
      );
    }

    if (resizeEnabled) {
      dialogBody = Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          dialogBody,
          PositionedDirectional(
            top: 0,
            end: 0,
            bottom: designTokens.dialogResizeHandleThickness,
            width: designTokens.dialogResizeHandleThickness,
            child: _DialogResizeHandle(
              axis: Axis.horizontal,
              tooltip: 'Resize width',
              onDragUpdate: (DragUpdateDetails details) {
                _handleResize(
                  details,
                  viewport,
                  insetPadding,
                  defaultWidth,
                  axis: Axis.horizontal,
                );
              },
            ),
          ),
          Positioned(
            left: 0,
            right: designTokens.dialogResizeHandleThickness,
            bottom: 0,
            height: designTokens.dialogResizeHandleThickness,
            child: _DialogResizeHandle(
              axis: Axis.vertical,
              tooltip: 'Resize height',
              onDragUpdate: (DragUpdateDetails details) {
                _handleResize(
                  details,
                  viewport,
                  insetPadding,
                  defaultWidth,
                  axis: Axis.vertical,
                );
              },
            ),
          ),
          PositionedDirectional(
            end: 0,
            bottom: 0,
            child: _DialogResizeHandle(
              onDragUpdate: (DragUpdateDetails details) {
                _handleResize(details, viewport, insetPadding, defaultWidth);
              },
            ),
          ),
        ],
      );
    }

    final double? overrideCornerRadius = widget.cornerRadius;
    final ShapeBorder dialogShape = overrideCornerRadius != null
        ? RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              context.responsiveRadius(overrideCornerRadius),
            ),
          )
        : (_isMaximized
              ? const RoundedRectangleBorder()
              : RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    context.responsiveRadius(theme.radius.lg),
                  ),
                ));

    Widget dialog = Dialog(
      insetPadding: insetPadding,
      alignment: _isMaximized && desktopInteractive
          ? Alignment.topCenter
          : Alignment.center,
      elevation: theme.dialogTheme.elevation ?? 24,
      shape: dialogShape,
      clipBehavior: Clip.antiAlias,
      backgroundColor: colorScheme.surface.withValues(
        alpha: widget.surfaceOpacity,
      ),
      shadowColor: colorScheme.shadow.withValues(alpha: 0.28),
      child: dialogBody,
    );

    if (desktopInteractive) {
      dialog = Transform.translate(offset: _dragOffset, child: dialog);
    }

    if (widget.semanticLabel != null) {
      dialog = Semantics(
        namesRoute: true,
        scopesRoute: true,
        explicitChildNodes: true,
        label: widget.semanticLabel,
        child: dialog,
      );
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (widget.closeEnabled) {
            Navigator.of(context).maybePop();
          }
        },
      },
      child: Focus(autofocus: true, child: FocusTraversalGroup(child: dialog)),
    );
  }

  void _handleDrag(
    DragUpdateDetails details,
    Size viewport,
    EdgeInsets insetPadding,
  ) {
    final double maxX = math.max(0, viewport.width / 2 - insetPadding.left);
    final double maxY = math.max(0, viewport.height / 2 - insetPadding.top);
    final Offset next = _dragOffset + details.delta;
    setState(() {
      _dragOffset = Offset(
        next.dx.clamp(-maxX, maxX).toDouble(),
        next.dy.clamp(-maxY, maxY).toDouble(),
      );
    });
  }

  void _toggleMaximize() {
    final Size viewport = MediaQuery.sizeOf(context);
    final ThemeData theme = Theme.of(context);
    final AppDesignTokens designTokens = theme.appTokens;
    final AppBreakpoint breakpoint = AppBreakpoints.of(context);
    final EdgeInsets normalInsetPadding = AppDialogInsets.paddingFor(
      breakpoint,
      designTokens: designTokens,
      maximized: false,
    );
    final double insetAvailableWidth = math.max(
      designTokens.dialogMinWidth,
      viewport.width - normalInsetPadding.horizontal,
    );
    final double insetAvailableHeight = math.max(
      designTokens.dialogMinHeight,
      viewport.height - normalInsetPadding.vertical,
    );
    final double defaultWidth = widget.maxWidth.isFinite
        ? math.min(widget.maxWidth, insetAvailableWidth)
        : insetAvailableWidth;

    if (_isMaximized) {
      final Size restoredSize =
          _preMaximizeSize ??
          Size(
            defaultWidth,
            math.min(insetAvailableHeight, insetAvailableHeight * 0.85),
          );
      setState(() {
        _isMaximized = false;
        _desktopSize = restoredSize;
        _dragOffset = _preMaximizeDragOffset ?? Offset.zero;
        _preMaximizeSize = null;
        _preMaximizeDragOffset = null;
      });
      return;
    }

    final Size currentSize =
        _desktopSize ??
        _measuredShellSize(
          designTokens,
          defaultWidth,
          insetAvailableWidth,
          insetAvailableHeight,
        );
    final Size maximizedSize = AppDialogInsets.availableSizeFor(
      viewport,
      breakpoint,
      designTokens: designTokens,
      maximized: true,
    );
    setState(() {
      _preMaximizeSize = currentSize;
      _preMaximizeDragOffset = _dragOffset;
      _isMaximized = true;
      _desktopSize = maximizedSize;
      _dragOffset = Offset.zero;
    });
  }

  void _handleResize(
    DragUpdateDetails details,
    Size viewport,
    EdgeInsets insetPadding,
    double defaultWidth, {
    Axis? axis,
  }) {
    final ThemeData theme = Theme.of(context);
    final AppDesignTokens designTokens = theme.appTokens;

    if (_isMaximized) {
      setState(() {
        _isMaximized = false;
        _preMaximizeSize = null;
        _preMaximizeDragOffset = null;
      });
    }

    final double availableWidth = math.max(
      designTokens.dialogMinWidth,
      viewport.width - insetPadding.horizontal,
    );
    final double availableHeight = math.max(
      designTokens.dialogMinHeight,
      viewport.height - insetPadding.vertical,
    );
    final Size current =
        _desktopSize ??
        _measuredShellSize(
          designTokens,
          defaultWidth,
          availableWidth,
          availableHeight,
        );
    setState(() {
      final double nextWidth = axis == Axis.vertical
          ? current.width
          : math.min(
              availableWidth,
              math.max(
                designTokens.dialogMinWidth,
                current.width + details.delta.dx,
              ),
            );
      final double nextHeight = axis == Axis.horizontal
          ? current.height
          : math.min(
              availableHeight,
              math.max(
                designTokens.dialogMinHeight,
                current.height + details.delta.dy,
              ),
            );
      _desktopSize = Size(nextWidth, nextHeight);
    });
  }

  static double _defaultScrollableShellHeight(
    double maxHeight,
    AppDesignTokens designTokens,
  ) {
    return math.max(
      designTokens.dialogMinHeight,
      math.min(maxHeight, maxHeight * 0.75),
    );
  }

  Size _measuredShellSize(
    AppDesignTokens designTokens,
    double defaultWidth,
    double availableWidth,
    double availableHeight,
  ) {
    final Size? measured = _dialogShellKey.currentContext?.size;
    if (measured != null) {
      return Size(
        math.max(designTokens.dialogMinWidth, measured.width),
        math.max(designTokens.dialogMinHeight, measured.height),
      );
    }
    return Size(defaultWidth, availableHeight);
  }
}

class _DialogBody extends StatelessWidget {
  const _DialogBody({
    required this.actions,
    required this.scrollable,
    required this.fillHeight,
    required this.hugContent,
    required this.surfaceOpacity,
    required this.compact,
    required this.stackActionsWhenCompact,
    required this.denseActions,
    required this.showCloseButton,
    required this.showMaximizeButton,
    required this.isMaximized,
    required this.closeEnabled,
    this.onMaximizeToggle,
    this.onHeaderDragUpdate,
    this.title,
    this.content,
    this.icon,
    this.chromeBorderRadius,
    this.contentPadding,
  });

  final Widget? title;
  final Widget? content;
  final List<Widget> actions;
  final Widget? icon;
  final bool scrollable;
  final bool fillHeight;

  /// Lets the body shrink to its content while still scrolling past the
  /// height the shell allows.
  final bool hugContent;
  final double surfaceOpacity;
  final bool compact;
  final bool stackActionsWhenCompact;
  final bool denseActions;
  final bool showCloseButton;
  final bool showMaximizeButton;
  final bool isMaximized;
  final bool closeEnabled;
  final VoidCallback? onMaximizeToggle;
  final ValueChanged<DragUpdateDetails>? onHeaderDragUpdate;
  final double? chromeBorderRadius;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final EdgeInsetsGeometry bodyPadding =
        contentPadding ??
        EdgeInsets.all(compact ? theme.spacing.md : theme.spacing.lg);
    final TextStyle titleStyle =
        ((compact ? theme.textTheme.titleMedium : theme.textTheme.titleLarge) ??
                theme.fonts.style(
                  color: colorScheme.onSurface,
                  fontSize: compact ? 18 : 22,
                  fontWeight: AppFontWeight.title,
                ))
            .copyWith(fontWeight: AppFontWeight.emphasis);
    final TextStyle contentStyle =
        theme.textTheme.bodyMedium ??
        theme.fonts.style(color: colorScheme.onSurface);
    final Widget? dialogContent = content == null
        ? null
        : AppFieldRequirementScope(
            showOptionalIndicators: true,
            child: DefaultTextStyle(style: contentStyle, child: content!),
          );

    final Widget? body = dialogContent == null
        ? null
        : _dialogBodyContent(
            scrollable: scrollable,
            bodyPadding: bodyPadding,
            child: dialogContent,
          );

    return Column(
      mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _DialogHeader(
          title: title,
          icon: icon,
          titleStyle: titleStyle,
          surfaceOpacity: surfaceOpacity,
          showCloseButton: showCloseButton,
          showMaximizeButton: showMaximizeButton,
          isMaximized: isMaximized,
          closeEnabled: closeEnabled,
          compact: compact,
          chromeBorderRadius: chromeBorderRadius,
          onMaximizeToggle: onMaximizeToggle,
          onDragUpdate: onHeaderDragUpdate,
        ),
        if (body != null)
          fillHeight
              ? Expanded(child: body)
              : hugContent
              ? Flexible(child: body)
              : body,
        if (actions.isNotEmpty)
          _DialogActions(
            actions: actions,
            compact: compact,
            stackWhenCompact: stackActionsWhenCompact,
            dense: denseActions,
            surfaceOpacity: surfaceOpacity,
          ),
      ],
    );
  }

  /// Keeps section content inset while the scrollbar/gutter stays on the outer
  /// edge of the dialog body (outside section chrome).
  static Widget _dialogBodyContent({
    required bool scrollable,
    required EdgeInsetsGeometry bodyPadding,
    required Widget child,
  }) {
    if (!scrollable) {
      return Padding(padding: bodyPadding, child: child);
    }

    return Scrollbar(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: bodyPadding,
        child: child,
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({
    required this.title,
    required this.icon,
    required this.titleStyle,
    required this.surfaceOpacity,
    required this.showCloseButton,
    required this.showMaximizeButton,
    required this.isMaximized,
    required this.closeEnabled,
    required this.compact,
    this.chromeBorderRadius,
    this.onMaximizeToggle,
    this.onDragUpdate,
  });

  final Widget? title;
  final Widget? icon;
  final TextStyle titleStyle;
  final double surfaceOpacity;
  final bool showCloseButton;
  final bool showMaximizeButton;
  final bool isMaximized;
  final bool closeEnabled;
  final bool compact;
  final double? chromeBorderRadius;
  final VoidCallback? onMaximizeToggle;
  final ValueChanged<DragUpdateDetails>? onDragUpdate;

  /// Back glyph matching the host platform's convention.
  ///
  /// Phones present dismissal as a back arrow rather than a corner ✕; Apple
  /// platforms use the chevron form.
  static IconData _backIconFor(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.iOS || TargetPlatform.macOS => Icons.arrow_back_ios_new,
      _ => Icons.arrow_back,
    };
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    // Compact dismissal moves to a leading back arrow (phone convention); the
    // trailing ✕ is desktop/tablet chrome only. Exactly one is ever rendered.
    final bool useLeadingBack = compact && showCloseButton;
    final bool useTrailingClose = !compact && showCloseButton;
    final String backLabel = context.l10n.commonBackActionLabel;
    final EdgeInsetsGeometry padding = EdgeInsetsDirectional.only(
      start: useLeadingBack
          ? theme.spacing.xs
          : compact
          ? theme.spacing.sm
          : theme.spacing.md,
      top: theme.spacing.xs,
      bottom: theme.spacing.xs,
      end: theme.spacing.xs,
    );

    final Widget header = DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow.withValues(alpha: surfaceOpacity),
        border: theme.borders.only(bottom: true),
      ),
      child: Padding(
        padding: padding,
        child: Row(
          children: <Widget>[
            if (useLeadingBack) ...<Widget>[
              _DialogChromeScope(
                child: AppButton.secondary(
                  iconOnly: true,
                  leadingIcon: _backIconFor(theme.platform),
                  label: backLabel,
                  semanticLabel: backLabel,
                  tooltip: backLabel,
                  enabled: closeEnabled,
                  borderRadius: chromeBorderRadius,
                  onPressed: closeEnabled
                      ? () {
                          Navigator.of(context).maybePop();
                        }
                      : null,
                ),
              ),
              SizedBox(width: theme.spacing.xs),
            ],
            if (icon != null) ...<Widget>[
              IconTheme.merge(
                data: IconThemeData(
                  color: colorScheme.primary,
                  size: theme.appTokens.listIconSize,
                ),
                child: icon!,
              ),
              SizedBox(width: theme.spacing.sm),
            ],
            Expanded(
              child: title == null
                  ? const SizedBox.shrink()
                  : DefaultTextStyle(
                      style: titleStyle.copyWith(color: colorScheme.onSurface),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      child: normalizeDialogTitleWidget(title!),
                    ),
            ),
            if (showMaximizeButton || useTrailingClose)
              _DialogChromeScope(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (showMaximizeButton)
                      AppButton(
                        iconOnly: true,
                        leadingIcon: isMaximized
                            ? Icons.fullscreen_exit
                            : Icons.fullscreen,
                        label: isMaximized
                            ? 'Restore dialog'
                            : 'Maximize dialog',
                        semanticLabel: isMaximized
                            ? 'Restore dialog'
                            : 'Maximize dialog',
                        tooltip: isMaximized
                            ? 'Restore dialog'
                            : 'Maximize dialog',
                        borderRadius: chromeBorderRadius,
                        onPressed: onMaximizeToggle,
                      ),
                    if (showMaximizeButton && useTrailingClose)
                      SizedBox(width: theme.spacing.xs),
                    if (useTrailingClose)
                      AppButton.close(
                        iconOnly: true,
                        label: MaterialLocalizations.of(
                          context,
                        ).closeButtonTooltip,
                        semanticLabel: MaterialLocalizations.of(
                          context,
                        ).closeButtonTooltip,
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).closeButtonTooltip,
                        enabled: closeEnabled,
                        borderRadius: chromeBorderRadius,
                        onPressed: closeEnabled
                            ? () {
                                Navigator.of(context).maybePop();
                              }
                            : null,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );

    final ValueChanged<DragUpdateDetails>? dragHandler = onDragUpdate;
    if (dragHandler == null) {
      return header;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanUpdate: dragHandler,
        child: header,
      ),
    );
  }
}

/// Header chrome stays icon-only on every breakpoint; tooltips and semantics
/// carry the accessible names.
class _DialogChromeScope extends StatelessWidget {
  const _DialogChromeScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppActionLabelScope(
      showLabels: false,
      forceIconOnly: true,
      dense: true,
      child: child,
    );
  }
}

class _DialogResizeHandle extends StatelessWidget {
  const _DialogResizeHandle({
    required this.onDragUpdate,
    this.axis,
    this.tooltip = 'Resize dialog',
  });

  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final Axis? axis;
  final String tooltip;

  SystemMouseCursor get _cursor {
    return switch (axis) {
      Axis.horizontal => SystemMouseCursors.resizeLeftRight,
      Axis.vertical => SystemMouseCursors.resizeUpDown,
      _ => SystemMouseCursors.resizeDownRight,
    };
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final bool showCornerIcon = axis == null;

    final Widget handle = showCornerIcon
        ? SizedBox.square(
            dimension: theme.appTokens.minInteractiveDimension,
            child: Align(
              alignment: Alignment.bottomRight,
              child: Icon(
                Icons.open_in_full,
                size: theme.appTokens.listIconSize - 2,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          )
        : const SizedBox.expand();

    return MouseRegion(
      cursor: _cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: onDragUpdate,
        child: Tooltip(message: tooltip, child: handle),
      ),
    );
  }
}

class _DialogActions extends StatelessWidget {
  const _DialogActions({
    required this.actions,
    required this.compact,
    required this.stackWhenCompact,
    this.dense = true,
    this.surfaceOpacity = 1,
  });

  final List<Widget> actions;
  final bool compact;
  final bool stackWhenCompact;
  final bool dense;
  final double surfaceOpacity;

  /// Slack so an estimate landing a hair under the true width still overflows
  /// an action instead of clipping the row.
  static const double _fitSafetyMargin = 4;

  /// Budget for a footer action that is not an [AppButton] and so cannot be
  /// measured from its own geometry (permission gates, custom controls).
  ///
  /// Sized as one ordinary labeled control. Such actions are laid out inside a
  /// [Flexible] so a wider-than-budgeted child shrinks instead of overflowing,
  /// which makes a modest estimate safer than a pessimistic one — the latter
  /// would strip labels off the whole row to make room that was never needed.
  static const double _unmeasurableActionWidth = 112;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    // Footer chrome: doubled vertical inset from the prior xs baseline; keep
    // horizontal inset and inter-button gaps tight around the actions.
    final EdgeInsets padding = EdgeInsets.symmetric(
      horizontal: theme.spacing.xs,
      vertical: theme.spacing.xs * 2,
    );

    // Two-action footers are authored [Close/dismiss, primary]. Reverse for
    // display so Close sits extreme-right (desktop) / last (stacked mobile).
    // Longer footers (wizards, etc.) already place Close last.
    final List<Widget> displayActions = actions.length == 2
        ? actions.reversed.toList(growable: false)
        : actions;

    final Widget actionRow = compact && stackWhenCompact
        ? _stackedActions(theme, displayActions)
        : _adaptiveActions(theme, displayActions);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow.withValues(alpha: surfaceOpacity),
        border: theme.borders.only(top: true),
      ),
      child: AppActionLabelScope(
        // Footer actions carry icon + label at every breakpoint. Crowding is
        // resolved by moving low-priority actions into the overflow menu —
        // never by dropping labels wholesale or scaling the row down.
        showLabels: true,
        forceIconOnly: false,
        dense: dense,
        child: Padding(padding: padding, child: actionRow),
      ),
    );
  }

  /// Opt-in only: stack full-width actions when a call site cannot fit a
  /// horizontal row. Bypasses overflow — every action stays visible.
  Widget _stackedActions(ThemeData theme, List<Widget> displayActions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < displayActions.length; i++) ...<Widget>[
          if (i > 0) SizedBox(height: theme.spacing.xs),
          SizedBox(width: double.infinity, child: displayActions[i]),
        ],
      ],
    );
  }

  /// Default: one right-aligned row. Actions that do not fit move into a
  /// trailing overflow menu, lowest priority first.
  Widget _adaptiveActions(ThemeData theme, List<Widget> displayActions) {
    final double gap = theme.spacing.xs;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final List<_FooterEntry> entries = <_FooterEntry>[
          for (final Widget action in displayActions)
            _FooterEntry(
              action: action,
              // Resolved from the action as authored: unwrapping first would
              // discard an AppDialogAction's explicit priority and fall back
              // to whatever the underlying button's variant implies.
              priority: resolveAppDialogActionPriority(action),
              overflowEligible: isAppDialogActionOverflowEligible(action),
            ),
        ];

        final _FooterLayout layout = constraints.hasBoundedWidth
            ? _resolveFooterLayout(
                context,
                entries,
                available: constraints.maxWidth,
                gap: gap,
              )
            : _FooterLayout(inline: entries, overflow: const <_FooterEntry>[]);

        final List<Widget> children = <Widget>[];
        for (int i = 0; i < layout.inline.length; i++) {
          if (i > 0) {
            children.add(SizedBox(width: gap));
          }
          final _FooterEntry entry = layout.inline[i];
          final Widget child = entry.iconOnly
              ? AppActionLabelScope(
                  showLabels: false,
                  forceIconOnly: true,
                  dense: dense,
                  child: entry.action,
                )
              : entry.action;
          // Actions whose width could only be estimated lay out flexibly, so a
          // wider-than-budgeted control shrinks (its label ellipsizes) instead
          // of overflowing the row. Measured buttons keep their intrinsic size
          // unless the row could not fit them, in which case they share the
          // width in proportion to how much each label wants.
          if (entry.measurable && !entry.flexible) {
            children.add(child);
          } else {
            children.add(
              Flexible(
                flex: entry.flexible
                    ? math.max(1, _estimatedWidth(context, entry).round())
                    : 1,
                child: child,
              ),
            );
          }
        }

        if (layout.overflow.isNotEmpty) {
          if (children.isNotEmpty) {
            children.add(SizedBox(width: gap));
          }
          children.add(
            _DialogOverflowMenu(
              actions: layout.overflow
                  .map((_FooterEntry entry) => entry.action)
                  .toList(growable: false),
              dense: dense,
            ),
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: children,
        );
      },
    );
  }

  /// Width [entry] wants at its current label setting.
  ///
  /// Actions that are not an [AppButton] cannot be measured from their own
  /// geometry, so they get a one-labeled-control budget.
  double _estimatedWidth(BuildContext context, _FooterEntry entry) {
    final Widget target = unwrapAppDialogAction(entry.action);
    if (target is! AppButton) {
      return _unmeasurableActionWidth;
    }
    return entry.iconOnly
        ? target.estimatedIconOnlyWidth(context, dense: dense)
        : target.estimatedLabeledWidth(context, dense: dense);
  }

  /// Greedy fit: evict overflow-eligible actions from the end until the row
  /// fits, then — only if the mandatory actions still do not fit — degrade the
  /// least important survivors to icon-only. Never scales.
  _FooterLayout _resolveFooterLayout(
    BuildContext context,
    List<_FooterEntry> entries, {
    required double available,
    required double gap,
  }) {
    final List<_FooterEntry> inline = List<_FooterEntry>.of(entries);
    final List<_FooterEntry> overflow = <_FooterEntry>[];

    double widthOf(_FooterEntry entry) => _estimatedWidth(context, entry);

    bool fits() {
      double total = 0;
      for (int i = 0; i < inline.length; i++) {
        if (i > 0) {
          total += gap;
        }
        total += widthOf(inline[i]);
      }
      if (overflow.isNotEmpty) {
        if (inline.isNotEmpty) {
          total += gap;
        }
        total += AppButton.iconOnlyWidth(context, dense: dense);
      }
      return total <= available - _fitSafetyMargin;
    }

    // Keep at least one action inline so the footer never collapses to a lone
    // overflow trigger.
    while (!fits() && inline.length > 1) {
      final int index = inline.lastIndexWhere(
        (_FooterEntry entry) => entry.overflowEligible,
      );
      if (index < 0) {
        break;
      }
      overflow.insert(0, inline.removeAt(index));
    }

    if (!fits()) {
      // Shed labels from supporting actions only. Confirm and dismiss keep
      // theirs at every size: a bare glyph gives no clue what committing does,
      // which is the whole point of a labeled footer.
      for (int i = inline.length - 1; i >= 0; i--) {
        if (inline[i].priority != AppDialogActionPriority.secondary ||
            inline[i].iconOnly) {
          continue;
        }
        inline[i].iconOnly = true;
        if (fits()) {
          break;
        }
      }
    }

    if (!fits()) {
      // Narrow viewport at a large text scale: the labeled mandatory actions
      // genuinely do not fit. Lay them out flexibly so each label ellipsizes
      // inside its button instead of overflowing the row.
      for (final _FooterEntry entry in inline) {
        entry.flexible = true;
      }
    }

    return _FooterLayout(inline: inline, overflow: overflow);
  }
}

/// One footer action plus the layout decisions taken for it.
final class _FooterEntry {
  _FooterEntry({
    required this.action,
    required this.priority,
    required this.overflowEligible,
  });

  final Widget action;

  /// Drives label-shedding order when even the inline-only row will not fit.
  final AppDialogActionPriority priority;

  /// Whether this action may move into the overflow menu at all.
  final bool overflowEligible;

  /// Whether the action's width comes from its own geometry rather than an
  /// estimate. Unmeasurable actions lay out flexibly as a safety net.
  bool get measurable => unwrapAppDialogAction(action) is AppButton;

  /// Set only as a last resort, when even the mandatory actions cannot fit.
  ///
  /// Never set for [AppDialogActionPriority.primary] or
  /// [AppDialogActionPriority.dismiss]: a footer that hides what committing
  /// does behind a bare glyph is worse than one whose label ellipsizes.
  bool iconOnly = false;

  /// Whether this action lays out flexibly so its label ellipsizes rather than
  /// overflowing the row. Set when the mandatory actions cannot fit even at
  /// full width — the narrow, high-text-scale case.
  bool flexible = false;
}

@immutable
final class _FooterLayout {
  const _FooterLayout({required this.inline, required this.overflow});

  final List<_FooterEntry> inline;
  final List<_FooterEntry> overflow;
}

/// Trailing "More actions" menu for footer actions that did not fit inline.
class _DialogOverflowMenu extends StatelessWidget {
  const _DialogOverflowMenu({required this.actions, required this.dense});

  final List<Widget> actions;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String label = context.l10n.workspaceToolbarOverflowLabel;

    return AppActionLabelScope(
      // The trigger itself stays icon-only inside the labeled footer scope.
      showLabels: false,
      forceIconOnly: true,
      dense: dense,
      child: MenuAnchor(
        style: appOverflowMenuStyle(theme),
        alignmentOffset: Offset(0, theme.spacing.xs),
        crossAxisUnconstrained: false,
        menuChildren: <Widget>[
          for (final Widget action in actions) _menuItem(context, theme, action),
        ],
        builder:
            (BuildContext context, MenuController controller, Widget? child) {
              return AppButton.popupMenuTrigger(
                context: context,
                icon: AppActionIcons.more,
                semanticLabel: label,
                onPressed: () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
              );
            },
      ),
    );
  }

  /// Disabled actions stay listed and disabled — never silently dropped.
  Widget _menuItem(BuildContext context, ThemeData theme, Widget action) {
    final Widget target = unwrapAppDialogAction(action);
    if (target is! AppButton) {
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: theme.spacing.sm,
          vertical: theme.spacing.xs,
        ),
        child: target,
      );
    }

    final bool canPress =
        target.enabled && !target.isLoading && target.onPressed != null;
    final VoidCallback? onPressed = target.onPressed;

    return MenuItemButton(
      style: appOverflowMenuItemStyle(theme),
      leadingIcon: Icon(
        target.overflowMenuIcon,
        size: theme.appTokens.listIconSize,
      ),
      onPressed: canPress
          ? () {
              onPressed?.call();
            }
          : null,
      child: Text(target.semanticLabel ?? target.label),
    );
  }
}

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  /// Outside taps never dismiss; only the dialog close control or Escape do.
  bool barrierDismissible = false,
  /// Overrides the scrim behind the dialog. Pass [Colors.transparent] when the
  /// screen underneath must stay visible, alongside [AppDialog.surfaceOpacity].
  Color? barrierColor,
  TraversalEdgeBehavior traversalEdgeBehavior =
      TraversalEdgeBehavior.closedLoop,
  bool requestFocus = true,
  RouteSettings? routeSettings,
}) async {
  final FocusNode? previousFocus = FocusManager.instance.primaryFocus;
  final T? result = await showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor ?? Colors.black54,
    traversalEdgeBehavior: traversalEdgeBehavior,
    requestFocus: requestFocus,
    routeSettings: routeSettings,
    builder: (BuildContext dialogContext) {
      return FocusTraversalGroup(child: builder(dialogContext));
    },
  );

  _restoreFocusAfterDialog(previousFocus);

  return result;
}

/// Restores focus without touching deactivated widget ancestors.
///
/// `BuildContext.mounted` stays true while an element is only deactivated, so
/// it is not a safe guard for ancestor lookups. Prefer focus-tree attachment
/// (`enclosingScope`) before calling [FocusNode.requestFocus].
void _restoreFocusAfterDialog(FocusNode? previousFocus) {
  if (previousFocus == null) {
    return;
  }
  final FocusNode node = previousFocus;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!node.canRequestFocus || node.enclosingScope == null) {
      return;
    }
    if (node.context == null) {
      return;
    }
    node.requestFocus();
  });
}
