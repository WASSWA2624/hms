import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/features/feedback/presentation/controllers/feedback_capture_controller.dart';
import 'package:hosspi_hms/features/feedback/presentation/controllers/feedback_presentation_controller.dart';
import 'package:hosspi_hms/features/feedback/presentation/widgets/feedback_form_view.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/components/components.dart';

export 'package:hosspi_hms/features/feedback/presentation/widgets/feedback_form_view.dart'
    show FeedbackSubmitOutcome;

/// "Give us feedback" as a window over the app.
///
/// The same form the docked panel shows, for narrow screens and for reporters
/// who would rather have it in front of them. It is opaque: the screen behind
/// stays legible by being beside the form or behind a solid surface, never
/// through it.
///
/// Pops a [FeedbackSubmitOutcome] once the feedback is sent, or once the
/// reporter leaves to capture more screens; closing it keeps the draft.
class FeedbackSubmitDialog extends ConsumerStatefulWidget {
  const FeedbackSubmitDialog({super.key});

  static const Key dockKey = ValueKey<String>('feedback-dialog-dock');

  /// Kept beside the form's own keys so callers and tests have one name for
  /// each control wherever the form is shown.
  static const Key captureThisScreenKey = FeedbackFormView.captureThisScreenKey;
  static const Key captureAnotherScreenKey =
      FeedbackFormView.captureAnotherScreenKey;
  static const Key includeFormKey = FeedbackFormView.includeFormKey;
  static const Key chooseScreensKey = FeedbackFormView.chooseScreensKey;
  static const Key categoryFieldKey = FeedbackFormView.categoryFieldKey;
  static const Key scopeFieldKey = FeedbackFormView.scopeFieldKey;

  @override
  ConsumerState<FeedbackSubmitDialog> createState() =>
      _FeedbackSubmitDialogState();
}

class _FeedbackSubmitDialogState extends ConsumerState<FeedbackSubmitDialog> {
  final GlobalKey<FeedbackFormViewState> _formKey =
      GlobalKey<FeedbackFormViewState>();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final FeedbackFormStatus status = ref.watch(feedbackFormStatusProvider);
    // The form steps out of the picture for a frame when a shot is taken of
    // the screen behind it; it stays mounted, so nothing typed is lost.
    final bool visible = ref.watch(feedbackFormVisibleProvider);
    final bool canDock = feedbackCanDock(MediaQuery.sizeOf(context).width);

    return Opacity(
      opacity: visible ? 1 : 0,
      child: AppDialog(
        title: Text(l10n.feedbackDialogTitle),
        icon: const Icon(Icons.feedback_outlined),
        scrollable: true,
        initialMaximized: false,
        sizeToContent: true,
        // Room for the two choices to sit on one row, and for a screenshot
        // strip under them.
        maxWidth: 720,
        closeEnabled: !status.isBusy,
        content: FeedbackFormView(
          key: _formKey,
          onFinished: (FeedbackSubmitOutcome outcome) =>
              Navigator.of(context).pop(outcome),
        ),
        actions: <Widget>[
          if (canDock)
            // Stays on the footer row rather than folding into the overflow
            // menu: it is what makes the side-by-side layout discoverable.
            AppDialogAction(
              priority: AppDialogActionPriority.primary,
              child: AppButton.tertiary(
                key: FeedbackSubmitDialog.dockKey,
                label: l10n.feedbackDockBesideAppAction,
                leadingIcon: Icons.vertical_split_outlined,
                onPressed: status.isBusy
                    ? null
                    : () {
                        ref
                            .read(feedbackPresentationProvider.notifier)
                            .set(FeedbackPresentation.docked);
                        Navigator.of(context).pop();
                      },
              ),
            ),
          ...buildFeedbackFormActions(
            l10n: l10n,
            status: status,
            onCancel: () => Navigator.of(context).maybePop(),
            onSubmit: () => _formKey.currentState?.submit(),
          ),
        ],
      ),
    );
  }
}
