import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/features/feedback/presentation/controllers/feedback_draft_controller.dart';
import 'package:hosspi_hms/features/feedback/presentation/controllers/feedback_presentation_controller.dart';
import 'package:hosspi_hms/features/feedback/presentation/widgets/feedback_form_view.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/widgets/app_pointer_interceptor.dart';

/// "Give us feedback" beside the app rather than over it.
///
/// An opaque panel pinned to the trailing edge, full height. The app keeps
/// its own layout underneath — it is overlaid, never resized — so the screen
/// being reported on looks exactly as it did, and stays usable: the reporter
/// can scroll it, open a record, and capture what they find while writing.
class FeedbackDockPanel extends ConsumerStatefulWidget {
  const FeedbackDockPanel({
    required this.onFinished,
    required this.onClose,
    super.key,
  });

  static const Key panelKey = Key('app-feedback-dock-panel');
  static const Key undockKey = ValueKey<String>('feedback-dock-undock');
  static const Key closeKey = ValueKey<String>('feedback-dock-close');

  final ValueChanged<FeedbackSubmitOutcome> onFinished;
  final VoidCallback onClose;

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
    if (draft == null) {
      return const SizedBox.shrink();
    }
    final Radius radius = Radius.circular(theme.radius.md);

    return AppPointerInterceptor(
      child: Material(
        key: FeedbackDockPanel.panelKey,
        // Opaque: the screen behind is beside the panel, not through it.
        color: colors.surface,
        elevation: 8,
        shadowColor: colors.shadow,
        borderRadius: BorderRadiusDirectional.only(
          topStart: radius,
          bottomStart: radius,
        ).resolve(Directionality.of(context)),
        clipBehavior: Clip.antiAlias,
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
                    onFinished: widget.onFinished,
                  ),
                ),
              ),
              Divider(height: 1, color: colors.outlineVariant),
              Padding(
                padding: EdgeInsets.all(theme.spacing.md),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    for (final Widget action in buildFeedbackFormActions(
                      l10n: l10n,
                      status: status,
                      onCancel: widget.onClose,
                      onSubmit: () => _formKey.currentState?.submit(),
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
    );
  }

  Widget _header(
    ThemeData theme,
    AppLocalizations l10n,
    FeedbackDraft draft, {
    required bool busy,
  }) {
    final ColorScheme colors = theme.colorScheme;
    final String screen = (draft.context.routeName ?? draft.context.routePath ?? '')
        .trim();

    return Container(
      color: colors.surfaceContainerHigh,
      padding: EdgeInsetsDirectional.fromSTEB(
        theme.spacing.md,
        theme.spacing.sm,
        theme.spacing.xs,
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
                  style: theme.textTheme.titleMedium,
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
