import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/features/feedback/presentation/controllers/feedback_capture_controller.dart';
import 'package:hosspi_hms/features/feedback/presentation/controllers/feedback_draft_controller.dart';
import 'package:hosspi_hms/features/feedback/presentation/controllers/feedback_presentation_controller.dart';
import 'package:hosspi_hms/features/feedback/presentation/widgets/feedback_form_view.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/widgets/app_pointer_interceptor.dart';

/// "Give us feedback" beside the app rather than over it.
///
/// An opaque panel pinned to the trailing edge, full height. The app receives
/// the space beside it, so the panel never covers the screen being reported.
class FeedbackDockPanel extends ConsumerStatefulWidget {
  const FeedbackDockPanel({
    required this.onFinished,
    required this.onClose,
    this.dialogContext,
    this.router,
    super.key,
  });

  static const Key panelKey = Key('app-feedback-dock-panel');
  static const Key undockKey = ValueKey<String>('feedback-dock-undock');
  static const Key closeKey = ValueKey<String>('feedback-dock-close');

  final ValueChanged<FeedbackSubmitOutcome> onFinished;
  final VoidCallback onClose;
  final BuildContext? dialogContext;
  final GoRouter? router;

  @override
  ConsumerState<FeedbackDockPanel> createState() => _FeedbackDockPanelState();
}

class _FeedbackDockPanelState extends ConsumerState<FeedbackDockPanel> {
  final GlobalKey<FeedbackFormViewState> _formKey =
      GlobalKey<FeedbackFormViewState>();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final AppLocalizations l10n = context.l10n;
    final FeedbackDraft? draft = ref.watch(feedbackDraftProvider);
    final FeedbackFormStatus status = ref.watch(feedbackFormStatusProvider);
    final bool visible = ref.watch(feedbackFormVisibleProvider);
    if (draft == null) {
      return const SizedBox.shrink();
    }

    return AppPointerInterceptor(
      child: ColoredBox(
        color: colors.surface,
        child: Opacity(
          opacity: visible ? 1 : 0,
          child: IgnorePointer(
            ignoring: !visible,
            child: Material(
              key: FeedbackDockPanel.panelKey,
              // Opaque: the screen is beside the panel, never seen through it.
              color: colors.surface,
              elevation: 2,
              shadowColor: colors.shadow.withValues(alpha: 0.16),
              clipBehavior: Clip.antiAlias,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: BorderDirectional(
                    start: BorderSide(color: colors.outlineVariant),
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _header(theme, l10n, draft, busy: status.isBusy),
                      Divider(height: 1, color: colors.outlineVariant),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.all(theme.spacing.md),
                          child: FeedbackFormView(
                            key: _formKey,
                            dialogContext: widget.dialogContext,
                            router: widget.router,
                            onFinished: widget.onFinished,
                          ),
                        ),
                      ),
                      Divider(height: 1, color: colors.outlineVariant),
                      Container(
                        color: colors.surfaceContainerLowest,
                        padding: EdgeInsets.all(theme.spacing.md),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: <Widget>[
                            for (final Widget action
                                in buildFeedbackFormActions(
                                  l10n: l10n,
                                  status: status,
                                  onCancel: widget.onClose,
                                  onSubmit: () =>
                                      _formKey.currentState?.submit(),
                                ))
                              Padding(
                                padding: EdgeInsetsDirectional.only(
                                  start: theme.spacing.sm,
                                ),
                                child: action,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(
    ThemeData theme,
    AppLocalizations l10n,
    FeedbackDraft draft, {
    required bool busy,
  }) {
    final ColorScheme colors = theme.colorScheme;
    final String screen =
        (draft.context.routeName ?? draft.context.routePath ?? '').trim();

    return Container(
      color: colors.surfaceContainerHighest,
      padding: EdgeInsetsDirectional.fromSTEB(
        theme.spacing.lg,
        theme.spacing.sm,
        theme.spacing.sm,
        theme.spacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.feedback_outlined, color: colors.primary),
          SizedBox(width: theme.spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  l10n.feedbackDialogTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.onSurface,
                    fontWeight: AppFontWeight.title,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (screen.isNotEmpty)
                  Text(
                    l10n.feedbackRaisedFromLabel(screen),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          IconButton(
            key: FeedbackDockPanel.undockKey,
            icon: const Icon(Icons.open_in_full),
            tooltip: l10n.feedbackOpenAsWindowAction,
            onPressed: busy
                ? null
                : () => ref
                      .read(feedbackPresentationProvider.notifier)
                      .set(FeedbackPresentation.dialog),
          ),
          IconButton(
            key: FeedbackDockPanel.closeKey,
            icon: const Icon(Icons.close),
            tooltip: l10n.commonCloseActionLabel,
            onPressed: busy ? null : widget.onClose,
          ),
        ],
      ),
    );
  }
}
