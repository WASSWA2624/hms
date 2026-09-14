import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/core/config/app_config_provider.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/network/app_connectivity_status.dart';
import 'package:hosspi_hms/core/permissions/permission_providers.dart';
import 'package:hosspi_hms/core/responsive/app_breakpoints.dart';
import 'package:hosspi_hms/core/security/session_controller.dart';
import 'package:hosspi_hms/core/security/session_state.dart';
import 'package:hosspi_hms/features/feedback/data/repositories/feedback_repository_impl.dart';
import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';
import 'package:hosspi_hms/features/feedback/domain/repositories/feedback_repository.dart';
import 'package:hosspi_hms/features/feedback/presentation/controllers/feedback_launcher_position_controller.dart';
import 'package:hosspi_hms/features/feedback/presentation/feedback_access.dart';
import 'package:hosspi_hms/features/feedback/presentation/feedback_context_capture.dart';
import 'package:hosspi_hms/features/feedback/presentation/widgets/feedback_submit_dialog.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/actions/app_action_dialogs.dart';
import 'package:hosspi_hms/shared/components/app_list_table_export_save.dart';
import 'package:hosspi_hms/shared/components/components.dart';
import 'package:hosspi_hms/shared/layout/app_workspace_feedback.dart';

/// Saves exported feedback bytes; returns false when the user cancels.
typedef FeedbackExportSaver =
    Future<bool> Function({required Uint8List bytes, required String fileName});

enum _FeedbackMenuAction { give, download, clear }

/// Floats the feedback control above everything in the app, sign-in screens
/// and modal dialogs included.
///
/// Mounted in `MaterialApp.router`'s builder, above the navigators, so it paints
/// over every route, dialog, sheet, and menu, and any screen added later gets
/// it without wiring. The dialogs and menus it opens go through the router's
/// root navigator. Users can drag the control anywhere on screen; the position
/// is kept in memory for the session ([feedbackLauncherPositionProvider]).
///
/// Everyone can give feedback. Platform owners and platform admins also get
/// Download feedback and Clear feedback; the API enforces the same roles.
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
  final GlobalKey _anchorKey = GlobalKey(debugLabel: 'feedback-launcher');

  // The control stays tappable above its own menu and form, so ignore taps
  // while one is open instead of stacking a second.
  bool _isFlowActive = false;
  bool _isBusy = false;
  bool _isDragging = false;

  // Layout facts from the last build, used to keep a dragged control on screen.
  Size _viewSize = Size.zero;
  EdgeInsets _safePadding = EdgeInsets.zero;
  double _edgeInset = 0;
  Size _launcherSize = Size.zero;

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
    _viewSize = MediaQuery.sizeOf(context);
    _safePadding = MediaQuery.paddingOf(context);
    _edgeInset = theme.spacing.sm;

    // The control's width changes with the breakpoint and busy state; track
    // it so a dragged position is clamped against its real size.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncLauncherSize());

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
          compact: AppBreakpoints.of(context).isMobile,
          isBusy: _isBusy,
          isDragging: _isDragging,
          canManage: canManage,
          onPressed: _isFlowActive
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
    final Offset? position = savedPosition == null
        ? null
        : _clampPosition(savedPosition);

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        widget.child,
        // Last child, so it paints above the navigators and everything they
        // show. Both branches build a `Positioned`, so the first drag moves the
        // control without remounting it and cancelling the gesture.
        if (position == null)
          Positioned.directional(
            textDirection: textDirection,
            end: endInset + theme.spacing.lg,
            bottom: _safePadding.bottom + theme.spacing.lg,
            child: launcher,
          )
        else
          Positioned(left: position.dx, top: position.dy, child: launcher),
      ],
    );
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

  void _syncLauncherSize() {
    if (!mounted) {
      return;
    }
    final RenderObject? renderObject = _anchorKey.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return;
    }
    if (renderObject.size != _launcherSize) {
      setState(() => _launcherSize = renderObject.size);
    }
  }

  void _handleDragStart(DragStartDetails details) {
    final RenderObject? launcher = _anchorKey.currentContext
        ?.findRenderObject();
    final RenderObject? host = context.findRenderObject();
    if (launcher is! RenderBox || host is! RenderBox || !launcher.hasSize) {
      return;
    }

    _launcherSize = launcher.size;
    final Offset origin = host.globalToLocal(
      launcher.localToGlobal(Offset.zero),
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
      _viewSize.width - _safePadding.right - _edgeInset - _launcherSize.width,
    );
    final double maxTop = math.max(
      minTop,
      _viewSize.height -
          _safePadding.bottom -
          _edgeInset -
          _launcherSize.height,
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
    final Rect anchorRect =
        overlay.globalToLocal(anchor.localToGlobal(Offset.zero)) & anchor.size;
    // The control paints above the menu, so open the menu beside it, toward
    // the wider side of the screen, rather than over it.
    final double gap = Theme.of(context).spacing.xs;
    final bool opensLeftward = anchorRect.center.dx > overlay.size.width / 2;
    final Rect menuAnchor = Rect.fromLTWH(
      opensLeftward ? anchorRect.left - gap : anchorRect.right + gap,
      anchorRect.top,
      0,
      anchorRect.height,
    );

    final _FeedbackMenuAction? action = await showMenu<_FeedbackMenuAction>(
      context: navigatorContext,
      position: RelativeRect.fromRect(menuAnchor, Offset.zero & overlay.size),
      items: <PopupMenuEntry<_FeedbackMenuAction>>[
        PopupMenuItem<_FeedbackMenuAction>(
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

    final FeedbackReceipt? receipt = await showAppDialog<FeedbackReceipt>(
      context: navigatorContext,
      builder: (_) => FeedbackSubmitDialog(
        feedbackContext: feedbackContext,
        signedIn: session.session != null,
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

  Future<void> _downloadFeedback() async {
    final BuildContext? navigatorContext = _navigatorContext;
    if (navigatorContext == null) {
      return;
    }

    final FeedbackRepository repository = ref.read(feedbackRepositoryProvider);
    final DateTime requestedAt = DateTime.now();

    setState(() => _isBusy = true);
    try {
      final Result<Uint8List> result = await repository.downloadFeedbackExport(
        utcOffsetMinutes: requestedAt.timeZoneOffset.inMinutes,
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

  Future<void> _clearFeedback() async {
    final BuildContext? navigatorContext = _navigatorContext;
    if (navigatorContext == null) {
      return;
    }

    final FeedbackRepository repository = ref.read(feedbackRepositoryProvider);

    setState(() => _isBusy = true);
    final Result<FeedbackSummary> summaryResult;
    try {
      summaryResult = await repository.fetchFeedbackSummary();
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
    if (!navigatorContext.mounted) {
      return;
    }

    final FeedbackSummary summary;
    switch (summaryResult) {
      case ResultFailure<FeedbackSummary>(failure: final AppFailure failure):
        showAppFailureSnackBar(navigatorContext, failure);
        return;
      case ResultSuccess<FeedbackSummary>(value: final FeedbackSummary value):
        summary = value;
    }

    final AppLocalizations l10n = navigatorContext.l10n;
    if (summary.total == 0) {
      showAppSuccessSnackBar(
        navigatorContext,
        l10n.feedbackNothingToClearMessage,
      );
      return;
    }

    int clearedCount = 0;
    final bool? cleared = await showAppDialog<bool>(
      context: navigatorContext,
      builder: (_) => AppConfirmActionDialog(
        title: l10n.feedbackClearConfirmTitle,
        body: l10n.feedbackClearConfirmBody(summary.total),
        submitLabel: l10n.feedbackClearActionLabel,
        icon: const Icon(AppActionIcons.delete),
        submitLeadingIcon: AppActionIcons.delete,
        destructive: true,
        onConfirm: () async {
          final Result<FeedbackClearResult> result = await repository
              .clearFeedback();
          switch (result) {
            case ResultSuccess<FeedbackClearResult>(
              value: final FeedbackClearResult value,
            ):
              clearedCount = value.clearedCount;
              return null;
            case ResultFailure<FeedbackClearResult>(
              failure: final AppFailure failure,
            ):
              return failure;
          }
        },
      ),
    );

    if (cleared == true && navigatorContext.mounted) {
      showAppSuccessSnackBar(
        navigatorContext,
        l10n.feedbackClearedMessage(clearedCount),
      );
    }
  }
}

/// Compact pill with icon and label; icon-only on phones.
class _FeedbackLauncher extends StatelessWidget {
  const _FeedbackLauncher({
    required this.compact,
    required this.isBusy,
    required this.isDragging,
    required this.canManage,
    required this.onPressed,
  });

  final bool compact;
  final bool isBusy;
  final bool isDragging;
  final bool canManage;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final AppLocalizations l10n = context.l10n;
    final Color foreground = colorScheme.onPrimaryContainer;
    final double iconSize = theme.appTokens.listIconSize;
    final String semanticLabel = canManage
        ? l10n.feedbackAdminMenuSemanticLabel
        : l10n.feedbackLauncherSemanticLabel;

    final Widget icon = isBusy
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
            semanticLabel: compact ? semanticLabel : null,
          );

    return Semantics(
      hint: l10n.feedbackLauncherMoveHint,
      child: Material(
        key: AppFeedbackHost.launcherKey,
        color: colorScheme.primaryContainer,
        elevation: isDragging ? 6 : 2,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isBusy ? null : onPressed,
          mouseCursor: isDragging
              ? SystemMouseCursors.grabbing
              : SystemMouseCursors.click,
          child: Padding(
            padding: compact
                ? EdgeInsets.all(theme.spacing.sm)
                : EdgeInsets.symmetric(
                    horizontal: theme.spacing.md,
                    vertical: theme.spacing.sm,
                  ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                icon,
                if (!compact) ...<Widget>[
                  SizedBox(width: theme.spacing.xs),
                  Text(
                    l10n.feedbackLauncherLabel,
                    semanticsLabel: semanticLabel,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: foreground,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
