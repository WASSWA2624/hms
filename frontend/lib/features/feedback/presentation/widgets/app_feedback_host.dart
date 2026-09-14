import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hosspi_hms/app/router/app_popup_route_tracker.dart';
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

/// Floats the feedback control over every screen, sign-in screens included.
///
/// Mounted in `MaterialApp.router`'s builder, above the navigators, so any
/// screen added later gets it without wiring. Because it sits outside the
/// navigators, dialogs and menus open through the router's root navigator,
/// and the control steps aside while a popup route or the keyboard is showing
/// so it never covers their actions or the focused field.
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
  late final AppPopupRouteTracker _popupRouteTracker;
  bool _hasOpenPopup = false;
  bool _isBusy = false;

  BuildContext? get _navigatorContext =>
      widget.router.routerDelegate.navigatorKey.currentContext;

  @override
  void initState() {
    super.initState();
    _popupRouteTracker = ref.read(appPopupRouteTrackerProvider);
    _hasOpenPopup = _popupRouteTracker.hasOpenPopup.value;
    _popupRouteTracker.hasOpenPopup.addListener(_handlePopupChanged);
  }

  @override
  void dispose() {
    _popupRouteTracker.hasOpenPopup.removeListener(_handlePopupChanged);
    super.dispose();
  }

  void _handlePopupChanged() {
    if (!mounted) {
      return;
    }
    final bool hasOpenPopup = _popupRouteTracker.hasOpenPopup.value;
    if (hasOpenPopup == _hasOpenPopup) {
      return;
    }
    // Navigators can report route changes while they build; wait a frame.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback(
        (_) => _handlePopupChanged(),
      );
      return;
    }
    setState(() => _hasOpenPopup = hasOpenPopup);
  }

  @override
  Widget build(BuildContext context) {
    final bool canManage = canManageFeedback(
      ref.watch(appAccessPolicyProvider),
    );
    final ThemeData theme = Theme.of(context);
    final EdgeInsets safePadding = MediaQuery.paddingOf(context);
    final bool isKeyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final bool isVisible = !_hasOpenPopup && !isKeyboardOpen;
    final double endInset = Directionality.of(context) == TextDirection.rtl
        ? safePadding.left
        : safePadding.right;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        widget.child,
        PositionedDirectional(
          end: endInset + theme.spacing.lg,
          bottom: safePadding.bottom + theme.spacing.lg,
          child: IgnorePointer(
            ignoring: !isVisible,
            child: ExcludeSemantics(
              excluding: !isVisible,
              child: AnimatedOpacity(
                opacity: isVisible ? 1 : 0,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 150),
                child: KeyedSubtree(
                  key: _anchorKey,
                  child: _FeedbackLauncher(
                    compact: AppBreakpoints.of(context).isMobile,
                    isBusy: _isBusy,
                    canManage: canManage,
                    onPressed: canManage
                        ? _openAdminMenu
                        : _openFeedbackDialog,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
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
    final Offset anchorOrigin = overlay.globalToLocal(
      anchor.localToGlobal(Offset.zero),
    );
    final _FeedbackMenuAction? action = await showMenu<_FeedbackMenuAction>(
      context: navigatorContext,
      position: RelativeRect.fromRect(
        anchorOrigin & anchor.size,
        Offset.zero & overlay.size,
      ),
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

class _FeedbackLauncher extends StatelessWidget {
  const _FeedbackLauncher({
    required this.compact,
    required this.isBusy,
    required this.canManage,
    required this.onPressed,
  });

  /// Icon-only on phones, where screen space is tightest.
  final bool compact;
  final bool isBusy;
  final bool canManage;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String semanticLabel = canManage
        ? l10n.feedbackAdminMenuSemanticLabel
        : l10n.feedbackLauncherSemanticLabel;
    final VoidCallback? handler = isBusy ? null : onPressed;
    final Widget busyIndicator = SizedBox.square(
      dimension: 20,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        semanticsLabel: l10n.feedbackWorkingLabel,
      ),
    );

    if (compact) {
      return FloatingActionButton.small(
        key: AppFeedbackHost.launcherKey,
        heroTag: null,
        onPressed: handler,
        child: isBusy
            ? busyIndicator
            : Icon(Icons.feedback_outlined, semanticLabel: semanticLabel),
      );
    }

    return FloatingActionButton.extended(
      key: AppFeedbackHost.launcherKey,
      heroTag: null,
      onPressed: handler,
      icon: isBusy ? busyIndicator : const Icon(Icons.feedback_outlined),
      label: Text(l10n.feedbackLauncherLabel, semanticsLabel: semanticLabel),
    );
  }
}
