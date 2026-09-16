import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/core/config/app_config_provider.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/network/app_connectivity_status.dart';
import 'package:hosspi_hms/core/permissions/permission_providers.dart';
import 'package:hosspi_hms/core/security/session_controller.dart';
import 'package:hosspi_hms/core/security/session_state.dart';
import 'package:hosspi_hms/features/feedback/data/repositories/feedback_repository_impl.dart';
import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';
import 'package:hosspi_hms/features/feedback/domain/repositories/feedback_repository.dart';
import 'package:hosspi_hms/features/feedback/presentation/controllers/feedback_launcher_position_controller.dart';
import 'package:hosspi_hms/features/feedback/presentation/feedback_access.dart';
import 'package:hosspi_hms/features/feedback/presentation/feedback_context_capture.dart';
import 'package:hosspi_hms/features/feedback/presentation/widgets/feedback_delete_dialog.dart';
import 'package:hosspi_hms/features/feedback/presentation/widgets/feedback_download_dialog.dart';
import 'package:hosspi_hms/features/feedback/presentation/widgets/feedback_submit_dialog.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/components/app_list_table_export_save.dart';
import 'package:hosspi_hms/shared/components/components.dart';
import 'package:hosspi_hms/shared/layout/app_workspace_feedback.dart';
import 'package:hosspi_hms/shared/widgets/app_pointer_interceptor.dart';

/// Saves exported feedback bytes; returns false when the user cancels.
typedef FeedbackExportSaver =
    Future<bool> Function({required Uint8List bytes, required String fileName});

enum _FeedbackMenuAction { give, download, clear }

typedef _FeedbackMenuPlacement = ({
  RelativeRect position,
  BoxConstraints constraints,
});

/// Material's popup menu keeps this far inside the screen's safe area.
const double _menuScreenMargin = 8;

/// Material's popup menu width limits.
const double _menuMinWidth = 112;
const double _menuMaxWidth = 280;

/// Places the feedback menu beside [icon], on the side with more room, so the
/// control, which paints above the menu, never covers it.
///
/// Material grows a menu away from whichever screen edge its position is
/// closer to, then nudges it back on screen if it spills over. Pushing the
/// unused edge of the position to the far side fixes the direction, and
/// capping the width at the room on that side leaves nothing to nudge.
_FeedbackMenuPlacement _placeMenuBeside(
  Rect icon, {
  required Size overlaySize,
  required EdgeInsets safePadding,
  required double gap,
}) {
  final double roomLeft =
      icon.left - gap - safePadding.left - _menuScreenMargin;
  final double roomRight =
      overlaySize.width -
      safePadding.right -
      _menuScreenMargin -
      icon.right -
      gap;
  final bool opensLeftward = roomLeft > roomRight;
  final double maxWidth = math.max(
    0,
    math.min(_menuMaxWidth, opensLeftward ? roomLeft : roomRight),
  );
  final double bottom = overlaySize.height - icon.top;

  return (
    position: opensLeftward
        ? RelativeRect.fromLTRB(
            overlaySize.width,
            icon.top,
            overlaySize.width - icon.left + gap,
            bottom,
          )
        : RelativeRect.fromLTRB(
            icon.right + gap,
            icon.top,
            overlaySize.width,
            bottom,
          ),
    constraints: BoxConstraints(
      minWidth: math.min(_menuMinWidth, maxWidth),
      maxWidth: maxWidth,
    ),
  );
}

/// Floats the feedback control above everything in the app, sign-in screens,
/// modal dialogs, and print previews included.
///
/// Mounted in `MaterialApp.router`'s builder, above the navigators, so it paints
/// over every route, dialog, sheet, and menu, and any screen added later gets
/// it without wiring. The dialogs and menus it opens go through the router's
/// root navigator. Users can drag the control anywhere on screen; the position
/// is kept in memory for the session ([feedbackLauncherPositionProvider]).
///
/// Everyone can give feedback. Platform owners and platform admins get a menu
/// that also offers Download feedback and Clear feedback; tapping the control
/// shows or hides it. The API enforces the same roles.
///
/// The control is on screen at all times bar one: while one of its own dialogs
/// is open it steps aside, so it cannot sit over the form it just opened.
class AppFeedbackHost extends ConsumerStatefulWidget {
  const AppFeedbackHost({
    required this.router,
    required this.child,
    this.saveExportFile = appListTableSaveExportFile,
    super.key,
  });

  /// The floating control.
  static const Key launcherKey = Key('app-feedback-launcher');

  final GoRouter router;
  final Widget child;
  final FeedbackExportSaver saveExportFile;

  @override
  ConsumerState<AppFeedbackHost> createState() => _AppFeedbackHostState();
}

class _AppFeedbackHostState extends ConsumerState<AppFeedbackHost> {
  static const Key _launcherSlotKey = ValueKey<String>(
    'app-feedback-launcher-slot',
  );
  static const Key _interceptorLayerKey = ValueKey<String>(
    'app-feedback-interceptor-layer',
  );

  final GlobalKey _anchorKey = GlobalKey(debugLabel: 'feedback-launcher');

  // The control stays tappable above its own menu. A tap closes an open menu;
  // while a dialog or download is under way, taps are ignored instead of
  // stacking a second.
  bool _isFlowActive = false;

  // One of this control's own dialogs is showing, so the control hides until
  // the dialog closes rather than floating over it.
  bool _isDialogOpen = false;
  bool _isBusy = false;
  bool _isDragging = false;

  // The open menu, so tapping the control again can close it. Each menu gets
  // a fresh key because a closing menu can still be animating out when the
  // next one opens.
  GlobalKey? _openMenuKey;

  // Layout facts from the last build, used to keep a dragged control on screen.
  Size _viewSize = Size.zero;
  EdgeInsets _safePadding = EdgeInsets.zero;
  double _edgeInset = 0;
  Size _iconOnlySize = Size.zero;
  bool _labelOpensLeftward = true;

  BuildContext? get _navigatorContext =>
      widget.router.routerDelegate.navigatorKey.currentContext;

  @override
  Widget build(BuildContext context) {
    final bool canManage = canManageFeedback(
      ref.watch(appAccessPolicyProvider),
    );
    final Offset? savedPosition = ref.watch(feedbackLauncherPositionProvider);
    final ThemeData theme = Theme.of(context);
    final TextDirection textDirection = Directionality.of(context);
    final Size viewSize = MediaQuery.sizeOf(context);
    final EdgeInsets safePadding = MediaQuery.paddingOf(context);
    if (_openMenuKey != null &&
        (viewSize != _viewSize || safePadding != _safePadding)) {
      // The menu was placed for the old layout, and the control may move onto
      // it. Close it at once rather than let the control cover it.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _closeMenu(animate: false),
      );
    }
    _viewSize = viewSize;
    _safePadding = safePadding;
    _edgeInset = theme.spacing.sm;
    // The control is an icon until hovered, and its label opens toward the
    // middle of the screen, so the icon alone decides what stays on screen.
    _iconOnlySize = Size.square(
      theme.appTokens.listIconSize + theme.spacing.xs * 2,
    );

    final Offset? position = savedPosition == null
        ? null
        : _clampPosition(savedPosition);
    _labelOpensLeftward = position == null
        ? textDirection == TextDirection.ltr
        : position.dx + _iconOnlySize.width / 2 > _viewSize.width / 2;

    final Widget launcher = GestureDetector(
      // Report movement from the touch-down point so the control tracks the
      // pointer exactly instead of lagging by the drag slop.
      dragStartBehavior: DragStartBehavior.down,
      onPanStart: _handleDragStart,
      onPanUpdate: _handleDragUpdate,
      onPanEnd: (_) => _endDrag(),
      onPanCancel: _endDrag,
      child: KeyedSubtree(
        key: _anchorKey,
        child: _FeedbackLauncher(
          isBusy: _isBusy,
          isDragging: _isDragging,
          canManage: canManage,
          labelOpensLeftward: _labelOpensLeftward,
          isMenuOpen: _openMenuKey != null,
          onPressed: _openMenuKey != null
              ? _closeMenu
              : _isFlowActive
              ? null
              : () => unawaited(
                  _runExclusive(
                    canManage ? _openAdminMenu : _openFeedbackDialog,
                  ),
                ),
        ),
      ),
    );

    final double endInset = textDirection == TextDirection.rtl
        ? _safePadding.left
        : _safePadding.right;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        widget.child,
        // Over an HTML platform view, such as the print preview iframe, the
        // browser hands pointer input to the view and Flutter never sees it.
        // While a feedback menu or dialog is open, or the control is being
        // dragged, a transparent interceptor covers the screen so input reaches
        // Flutter everywhere. Flutter's own hit testing skips it, so the menus
        // and dialogs beneath still get their taps.
        if (_isFlowActive || _isDragging)
          const Positioned.fill(
            key: _interceptorLayerKey,
            child: IgnorePointer(
              child: AppPointerInterceptor(child: SizedBox.expand()),
            ),
          ),
        // Last child, so it paints above the navigators and everything they
        // show. Every branch builds the same keyed `Positioned`, so dragging
        // moves the control without remounting it and cancelling the gesture.
        // While one of its own dialogs is open it leaves the screen entirely.
        if (_isDialogOpen)
          ...const <Widget>[]
        else if (position == null)
          Positioned.directional(
            key: _launcherSlotKey,
            textDirection: textDirection,
            end: endInset + theme.spacing.lg,
            bottom: _safePadding.bottom + theme.spacing.lg,
            child: launcher,
          )
        else if (_labelOpensLeftward)
          // Pin the right edge so the label grows leftward, into the screen.
          Positioned(
            key: _launcherSlotKey,
            right: _viewSize.width - position.dx - _iconOnlySize.width,
            top: position.dy,
            child: launcher,
          )
        else
          Positioned(
            key: _launcherSlotKey,
            left: position.dx,
            top: position.dy,
            child: launcher,
          ),
      ],
    );
  }

  /// Hides the control while one of its own dialogs is on screen.
  Future<T?> _withDialogHidden<T>(Future<T?> Function() open) async {
    setState(() => _isDialogOpen = true);
    try {
      return await open();
    } finally {
      if (mounted) {
        setState(() => _isDialogOpen = false);
      }
    }
  }

  Future<void> _runExclusive(Future<void> Function() flow) async {
    if (_isFlowActive) {
      return;
    }
    setState(() => _isFlowActive = true);
    try {
      await flow();
    } finally {
      if (mounted) {
        setState(() => _isFlowActive = false);
      }
    }
  }

  void _handleDragStart(DragStartDetails details) {
    // Moving the control would carry it over its open menu.
    _closeMenu(animate: false);

    final RenderObject? launcher = _anchorKey.currentContext
        ?.findRenderObject();
    final RenderObject? host = context.findRenderObject();
    if (launcher is! RenderBox || host is! RenderBox || !launcher.hasSize) {
      return;
    }

    final Rect bounds =
        host.globalToLocal(launcher.localToGlobal(Offset.zero)) &
        launcher.size;
    // Track the icon, not a label that hides while dragging.
    final Offset origin = Offset(
      _labelOpensLeftward ? bounds.right - _iconOnlySize.width : bounds.left,
      bounds.top,
    );
    ref
        .read(feedbackLauncherPositionProvider.notifier)
        .moveTo(_clampPosition(origin));
    setState(() => _isDragging = true);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final Offset? position = ref.read(feedbackLauncherPositionProvider);
    if (position == null) {
      return;
    }
    ref
        .read(feedbackLauncherPositionProvider.notifier)
        .moveTo(_clampPosition(position + details.delta));
  }

  void _endDrag() {
    if (mounted && _isDragging) {
      setState(() => _isDragging = false);
    }
  }

  /// Keeps the control fully on screen, clear of system insets.
  Offset _clampPosition(Offset position) {
    final double minLeft = _safePadding.left + _edgeInset;
    final double minTop = _safePadding.top + _edgeInset;
    final double maxLeft = math.max(
      minLeft,
      _viewSize.width - _safePadding.right - _edgeInset - _iconOnlySize.width,
    );
    final double maxTop = math.max(
      minTop,
      _viewSize.height -
          _safePadding.bottom -
          _edgeInset -
          _iconOnlySize.height,
    );

    return Offset(
      math.min(math.max(position.dx, minLeft), maxLeft),
      math.min(math.max(position.dy, minTop), maxTop),
    );
  }

  Future<void> _openAdminMenu() async {
    final BuildContext? navigatorContext = _navigatorContext;
    final RenderBox? anchor =
        _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? overlay =
        widget.router.routerDelegate.navigatorKey.currentState?.overlay?.context
                .findRenderObject()
            as RenderBox?;
    if (navigatorContext == null || anchor == null || overlay == null) {
      return;
    }

    final AppLocalizations l10n = navigatorContext.l10n;
    final Rect launcherRect =
        overlay.globalToLocal(anchor.localToGlobal(Offset.zero)) & anchor.size;
    // The control paints above everything, so its menu goes beside it, never
    // under it. The label hides while the menu is open, so place the menu
    // against the icon alone.
    final _FeedbackMenuPlacement placement = _placeMenuBeside(
      Rect.fromLTWH(
        _labelOpensLeftward
            ? launcherRect.right - _iconOnlySize.width
            : launcherRect.left,
        launcherRect.top,
        _iconOnlySize.width,
        _iconOnlySize.height,
      ),
      overlaySize: overlay.size,
      safePadding: MediaQuery.paddingOf(navigatorContext),
      gap: Theme.of(context).spacing.xs,
    );

    final GlobalKey menuKey = GlobalKey(debugLabel: 'feedback-menu');
    setState(() => _openMenuKey = menuKey);
    final _FeedbackMenuAction? action;
    try {
      action = await showMenu<_FeedbackMenuAction>(
        context: navigatorContext,
        position: placement.position,
        constraints: placement.constraints,
        items: <PopupMenuEntry<_FeedbackMenuAction>>[
          PopupMenuItem<_FeedbackMenuAction>(
            key: menuKey,
            value: _FeedbackMenuAction.give,
            child: AppMenuItemLabel(
              icon: Icons.feedback_outlined,
              label: l10n.feedbackGiveActionLabel,
            ),
          ),
          PopupMenuItem<_FeedbackMenuAction>(
            value: _FeedbackMenuAction.download,
            child: AppMenuItemLabel(
              icon: AppActionIcons.download,
              label: l10n.feedbackDownloadActionLabel,
            ),
          ),
          PopupMenuItem<_FeedbackMenuAction>(
            value: _FeedbackMenuAction.clear,
            child: AppMenuItemLabel(
              icon: AppActionIcons.delete,
              label: l10n.feedbackClearActionLabel,
            ),
          ),
        ],
      );
    } finally {
      if (mounted) {
        setState(() => _openMenuKey = null);
      }
    }
    if (!mounted) {
      return;
    }

    switch (action) {
      case _FeedbackMenuAction.give:
        await _openFeedbackDialog();
      case _FeedbackMenuAction.download:
        await _downloadFeedback();
      case _FeedbackMenuAction.clear:
        await _clearFeedback();
      case null:
        return;
    }
  }

  /// Closes the menu this control opened. [animate] plays the usual exit
  /// animation; without it the menu goes at once, for when the control is
  /// about to move and would otherwise pass over the fading menu.
  void _closeMenu({bool animate = true}) {
    final BuildContext? menuContext = _openMenuKey?.currentContext;
    if (menuContext == null) {
      return;
    }
    final ModalRoute<Object?>? route = ModalRoute.of(menuContext);
    final NavigatorState? navigator = route?.navigator;
    if (route == null || navigator == null || !route.isActive) {
      return;
    }
    if (animate && route.isCurrent) {
      navigator.pop();
    } else {
      // Removes it without animation, even from under a route opened above.
      navigator.removeRoute(route);
    }
  }

  Future<void> _openFeedbackDialog() async {
    final BuildContext? navigatorContext = _navigatorContext;
    if (navigatorContext == null) {
      return;
    }

    final SessionState session = ref.read(sessionStateProvider);
    final FeedbackContext feedbackContext = captureFeedbackContext(
      context: context,
      router: widget.router,
      session: session,
      config: ref.read(appConfigProvider),
      connectivity: ref.read(appConnectivityStatusProvider).value,
    );

    final FeedbackReceipt? receipt = await _withDialogHidden<FeedbackReceipt>(
      () => showAppDialog<FeedbackReceipt>(
        context: navigatorContext,
        // See-through, so the screen the feedback is about stays in view.
        barrierColor: Colors.transparent,
        builder: (_) => FeedbackSubmitDialog(
          feedbackContext: feedbackContext,
          signedIn: session.session != null,
        ),
      ),
    );
    if (receipt == null || !navigatorContext.mounted) {
      return;
    }

    final AppLocalizations l10n = navigatorContext.l10n;
    final String? reference = receipt.referenceId;
    showAppSuccessSnackBar(
      navigatorContext,
      reference == null
          ? l10n.feedbackSubmittedPlainMessage
          : l10n.feedbackSubmittedMessage(reference),
    );
  }

  /// Lets the user pick stored feedback and save it as a workbook.
  Future<void> _downloadFeedback() async {
    final BuildContext? navigatorContext = _navigatorContext;
    if (navigatorContext == null) {
      return;
    }

    final FeedbackExportRequest? request =
        await _withDialogHidden<FeedbackExportRequest>(
          () => showFeedbackDownloadDialog(context: navigatorContext),
        );
    if (request == null || !navigatorContext.mounted) {
      return;
    }

    final FeedbackRepository repository = ref.read(feedbackRepositoryProvider);
    final DateTime requestedAt = DateTime.now();

    setState(() => _isBusy = true);
    try {
      final Result<Uint8List> result = await repository.downloadFeedbackExport(
        utcOffsetMinutes: requestedAt.timeZoneOffset.inMinutes,
        referenceIds: request.referenceIds,
        filters: request.filters,
      );
      if (!navigatorContext.mounted) {
        return;
      }

      switch (result) {
        case ResultFailure<Uint8List>(failure: final AppFailure failure):
          showAppFailureSnackBar(navigatorContext, failure);
        case ResultSuccess<Uint8List>(value: final Uint8List bytes):
          final bool saved = await _saveExport(
            navigatorContext,
            bytes: bytes,
            fileName: buildFeedbackExportFileName(requestedAt),
          );
          if (saved && navigatorContext.mounted) {
            showAppSuccessSnackBar(
              navigatorContext,
              navigatorContext.l10n.feedbackDownloadedMessage,
            );
          }
      }
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<bool> _saveExport(
    BuildContext navigatorContext, {
    required Uint8List bytes,
    required String fileName,
  }) async {
    try {
      return await widget.saveExportFile(bytes: bytes, fileName: fileName);
    } on Exception {
      if (navigatorContext.mounted) {
        showAppFailureSnackBar(navigatorContext, const AppFailure.unexpected());
      }
      return false;
    }
  }

  /// Lets the user pick stored feedback and delete it permanently.
  Future<void> _clearFeedback() async {
    final BuildContext? navigatorContext = _navigatorContext;
    if (navigatorContext == null) {
      return;
    }

    final int? deletedCount = await _withDialogHidden<int>(
      () => showFeedbackDeleteDialog(context: navigatorContext),
    );
    if (deletedCount == null || !navigatorContext.mounted) {
      return;
    }
    showAppSuccessSnackBar(
      navigatorContext,
      navigatorContext.l10n.feedbackDeletedMessage(deletedCount),
    );
  }
}

/// Small square icon button whose label shows while it is hovered or focused.
class _FeedbackLauncher extends StatefulWidget {
  const _FeedbackLauncher({
    required this.isBusy,
    required this.isDragging,
    required this.canManage,
    required this.labelOpensLeftward,
    required this.isMenuOpen,
    required this.onPressed,
  });

  final bool isBusy;
  final bool isDragging;
  final bool canManage;

  /// Whether the menu this control toggles is showing.
  final bool isMenuOpen;

  /// Whether the label opens to the left of the icon, into the screen.
  final bool labelOpensLeftward;
  final VoidCallback? onPressed;

  @override
  State<_FeedbackLauncher> createState() => _FeedbackLauncherState();
}

class _FeedbackLauncherState extends State<_FeedbackLauncher> {
  bool _isHovered = false;
  bool _isFocused = false;

  void _setHovered(bool hovered) {
    if (mounted && hovered != _isHovered) {
      setState(() => _isHovered = hovered);
    }
  }

  void _setFocused(bool focused) {
    if (mounted && focused != _isFocused) {
      setState(() => _isFocused = focused);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final AppLocalizations l10n = context.l10n;
    final Color foreground = colorScheme.onPrimaryContainer;
    final double iconSize = theme.appTokens.listIconSize;
    final String semanticLabel = widget.canManage
        ? l10n.feedbackAdminMenuSemanticLabel
        : l10n.feedbackLauncherSemanticLabel;
    // No label while the menu is open: it would grow over the menu.
    final bool showLabel =
        (_isHovered || _isFocused) && !widget.isDragging && !widget.isMenuOpen;

    final Widget icon = widget.isBusy
        ? SizedBox.square(
            dimension: iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: foreground,
              semanticsLabel: l10n.feedbackWorkingLabel,
            ),
          )
        : Icon(
            Icons.feedback_outlined,
            size: iconSize,
            color: foreground,
            semanticLabel: semanticLabel,
          );

    final Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      // Visual order only: the label sits on the side it opens to.
      textDirection: widget.labelOpensLeftward
          ? TextDirection.rtl
          : TextDirection.ltr,
      children: <Widget>[
        icon,
        if (showLabel) ...<Widget>[
          SizedBox(width: theme.spacing.xs),
          // The icon already carries the accessible label.
          ExcludeSemantics(
            child: Text(
              l10n.feedbackLauncherLabel,
              style: theme.textTheme.labelLarge?.copyWith(color: foreground),
            ),
          ),
        ],
      ],
    );

    return AppPointerInterceptor(
      onPointerLeave: () => _setHovered(false),
      child: Semantics(
        hint: l10n.feedbackLauncherMoveHint,
        // Only owners and admins have a menu to expand.
        expanded: widget.canManage ? widget.isMenuOpen : null,
        child: Material(
          key: AppFeedbackHost.launcherKey,
          color: colorScheme.primaryContainer,
          elevation: widget.isDragging ? 6 : 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(theme.radius.xs),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.isBusy ? null : widget.onPressed,
            onHover: _setHovered,
            onFocusChange: _setFocused,
            mouseCursor: widget.isDragging
                ? SystemMouseCursors.grabbing
                : SystemMouseCursors.click,
            child: Padding(
              padding: EdgeInsets.all(theme.spacing.xs),
              // Snap shut as the menu opens instead of shrinking over it.
              child: widget.isMenuOpen
                  ? content
                  : AnimatedSize(
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeOut,
                      alignment: widget.labelOpensLeftward
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: content,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
