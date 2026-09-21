import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/permissions/permission_providers.dart';
import 'package:hosspi_hms/core/responsive/app_breakpoints.dart';
import 'package:hosspi_hms/features/feedback/data/repositories/feedback_repository_impl.dart';
import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';
import 'package:hosspi_hms/features/feedback/presentation/controllers/feedback_capture_controller.dart';
import 'package:hosspi_hms/features/feedback/presentation/controllers/feedback_draft_controller.dart';
import 'package:hosspi_hms/features/feedback/presentation/feedback_capture_session.dart';
import 'package:hosspi_hms/features/feedback/presentation/feedback_labels.dart';
import 'package:hosspi_hms/features/feedback/presentation/feedback_screen_catalog.dart';
import 'package:hosspi_hms/features/feedback/presentation/widgets/feedback_screen_picker_dialog.dart';
import 'package:hosspi_hms/features/feedback/presentation/widgets/feedback_screenshot_strip.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/components/components.dart';
import 'package:hosspi_hms/shared/forms/forms.dart';
import 'package:hosspi_hms/shared/layout/app_workspace_feedback.dart';

/// How the "Give us feedback" form closed.
///
/// Sending it hands back the receipt. Walking the app for more screens is the
/// other way out: the form closes with the draft intact, and the floating
/// control takes over until the reporter comes back to it.
final class FeedbackSubmitOutcome {
  const FeedbackSubmitOutcome.submitted(FeedbackReceipt this.receipt)
    : capturesMoreScreens = false;

  const FeedbackSubmitOutcome.capturesMoreScreens()
    : receipt = null,
      capturesMoreScreens = true;

  final FeedbackReceipt? receipt;
  final bool capturesMoreScreens;
}

/// "Give us feedback" form. Pops a [FeedbackSubmitOutcome] once the feedback
/// is saved, or once the reporter leaves to capture more screens.
///
/// The caller captures the screen and device context; the form asks only for
/// what the system cannot know: the kind of feedback, what it applies to, the
/// details, and the screens worth a picture.
///
/// It opens at the size of that form rather than filling the window, and its
/// chrome is see-through, so the screen the feedback is about stays legible
/// behind it while the user writes. Only the details box is solid: that is
/// where the user is reading their own words back. Callers pair this with a
/// see-through barrier.
///
/// Everything typed, picked and captured lives in [feedbackDraftProvider], so
/// closing the form to walk the app costs the reporter nothing.
class FeedbackSubmitDialog extends ConsumerStatefulWidget {
  const FeedbackSubmitDialog({super.key});

  static const Key captureThisScreenKey = ValueKey<String>(
    'feedback-capture-this-screen',
  );
  static const Key captureAnotherScreenKey = ValueKey<String>(
    'feedback-capture-another-screen',
  );
  static const Key includeFormKey = ValueKey<String>(
    'feedback-capture-include-form',
  );
  static const Key chooseScreensKey = ValueKey<String>(
    'feedback-choose-screens',
  );

  @override
  ConsumerState<FeedbackSubmitDialog> createState() =>
      _FeedbackSubmitDialogState();
}

class _FeedbackSubmitDialogState extends ConsumerState<FeedbackSubmitDialog> {
  /// Enough of the screen behind shows through to place the feedback, while
  /// the form's own labels and buttons keep their contrast.
  static const double _surfaceOpacity = 0.86;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _messageController;
  int _categoryRevision = 0;
  bool _isSubmitting = false;
  bool _isCapturing = false;
  bool _showScreensError = false;
  AppFailure? _failure;

  FeedbackDraft get _draft => ref.read(feedbackDraftProvider)!;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController(
      text: ref.read(feedbackDraftProvider)?.message ?? '',
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final FeedbackDraft? draft = ref.watch(feedbackDraftProvider);
    // The form hides itself for a frame while a picture is taken of the
    // screen behind it; it stays mounted, so nothing typed is lost.
    final bool visible = ref.watch(feedbackFormVisibleProvider);
    if (draft == null) {
      return const SizedBox.shrink();
    }
    final bool busy = _isSubmitting || _isCapturing;

    return Opacity(
      opacity: visible ? 1 : 0,
      child: AppDialog(
        title: Text(l10n.feedbackDialogTitle),
        icon: const Icon(Icons.feedback_outlined),
        scrollable: true,
        initialMaximized: false,
        sizeToContent: true,
        surfaceOpacity: _surfaceOpacity,
        closeEnabled: !busy,
        content: AppFormShell(
          formKey: _formKey,
          enabled: !busy,
          formStatus: appFormFailureStatus(context, _failure),
          children: <Widget>[
            _FeedbackCategoryField(
              value: draft.category,
              revision: _categoryRevision,
              enabled: !busy,
              onChanged: (FeedbackCategory category) {
                setState(() => _categoryRevision += 1);
                _saveEntry(category: category);
              },
            ),
            _scopeField(l10n, draft, enabled: !busy),
            // The one solid control: the field's own fill hides the screen
            // behind it so what the user types stays easy to read.
            AppTextField(
              controller: _messageController,
              labelText: l10n.feedbackMessageLabel,
              hintText: l10n.feedbackMessageHint,
              isRequired: true,
              autofocus: true,
              minLines: 5,
              maxLines: 10,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (String value) => _saveEntry(message: value),
              validator: AppValidators.compose<String>(
                <FormFieldValidator<String>>[
                  AppValidators.requiredText(l10n.feedbackMessageRequired),
                  AppValidators.minLength(
                    feedbackMessageMinLength,
                    l10n.feedbackMessageTooShort(feedbackMessageMinLength),
                    trim: true,
                  ),
                  AppValidators.maxLength(
                    feedbackMessageMaxLength,
                    l10n.feedbackMessageTooLong(feedbackMessageMaxLength),
                    trim: true,
                  ),
                ],
              ),
            ),
            _screenshotsField(l10n, draft, enabled: !busy),
          ],
        ),
        actions: <Widget>[
          AppButton.close(
            label: l10n.commonCancelActionLabel,
            enabled: !busy,
            onPressed: busy ? null : () => Navigator.of(context).maybePop(),
          ),
          AppButton.primary(
            label: l10n.feedbackSubmitActionLabel,
            leadingIcon: Icons.send_outlined,
            isLoading: _isSubmitting,
            onPressed: busy ? null : _submit,
          ),
        ],
      ),
    );
  }

  /// What the feedback applies to, with the picked screens under it.
  Widget _scopeField(
    AppLocalizations l10n,
    FeedbackDraft draft, {
    required bool enabled,
  }) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppRadioGroup<FeedbackScope>(
          labelText: l10n.feedbackScopeLabel,
          value: draft.scope,
          enabled: enabled,
          layout: AppRadioGroupLayout.wrap,
          errorText: _showScreensError && draft.scope == FeedbackScope.screens
              ? l10n.feedbackScreensRequiredMessage
              : null,
          options: <AppRadioOption<FeedbackScope>>[
            AppRadioOption<FeedbackScope>(
              value: FeedbackScope.screen,
              label: l10n.feedbackScopeThisScreen,
              description: l10n.feedbackScopeThisScreenDescription,
            ),
            AppRadioOption<FeedbackScope>(
              value: FeedbackScope.app,
              label: l10n.feedbackScopeWholeApp,
              description: l10n.feedbackScopeWholeAppDescription,
            ),
            AppRadioOption<FeedbackScope>(
              value: FeedbackScope.screens,
              label: l10n.feedbackScopeSelectedScreens,
              description: l10n.feedbackScopeSelectedScreensDescription,
            ),
          ],
          onChanged: (FeedbackScope? scope) => _setScope(scope),
        ),
        if (draft.scope == FeedbackScope.screens) ...<Widget>[
          SizedBox(height: theme.spacing.sm),
          Wrap(
            spacing: theme.spacing.xs,
            runSpacing: theme.spacing.xs,
            children: <Widget>[
              for (final FeedbackScreenReference screen in draft.screens)
                InputChip(
                  label: Text(screen.label),
                  isEnabled: enabled,
                  onDeleted: enabled
                      ? () => ref
                            .read(feedbackDraftProvider.notifier)
                            .removeScreen(screen)
                      : null,
                  deleteButtonTooltipMessage: l10n.feedbackScreenRemoveLabel(
                    screen.label,
                  ),
                ),
              AppButton.secondary(
                key: FeedbackSubmitDialog.chooseScreensKey,
                label: l10n.feedbackChooseScreensAction,
                leadingIcon: Icons.checklist_outlined,
                onPressed: enabled ? _pickScreens : null,
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// The pictures attached so far, and the two ways to add another.
  Widget _screenshotsField(
    AppLocalizations l10n,
    FeedbackDraft draft, {
    required bool enabled,
  }) {
    final ThemeData theme = Theme.of(context);
    final int limit = feedbackScreenshotLimit(signedIn: draft.signedIn);
    final bool canCapture = enabled && draft.canCaptureMore;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child:
                  appFieldLabelWidget(
                    context,
                    l10n.feedbackScreenshotsLabel,
                    isRequired: false,
                  ) ??
                  Text(l10n.feedbackScreenshotsLabel),
            ),
            Text(
              l10n.feedbackScreenshotsCountLabel(draft.screenshots.length, limit),
              style: theme.textTheme.labelMedium,
            ),
          ],
        ),
        SizedBox(height: theme.spacing.xs),
        if (draft.screenshots.isNotEmpty) ...<Widget>[
          FeedbackScreenshotStrip(
            screenshots: draft.screenshots,
            enabled: enabled,
            onRemove: (int index) =>
                ref.read(feedbackDraftProvider.notifier).removeScreenshot(index),
            onCrop: _cropScreenshot,
            onCaptionChanged: (int index, String caption) => ref
                .read(feedbackDraftProvider.notifier)
                .replaceScreenshot(
                  index,
                  draft.screenshots[index].copyWith(caption: caption),
                ),
          ),
          SizedBox(height: theme.spacing.xs),
          Text(
            l10n.feedbackScreenshotsPatientDataNotice,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: theme.spacing.xs),
        ],
        AppCheckboxField(
          key: FeedbackSubmitDialog.includeFormKey,
          title: l10n.feedbackCaptureIncludeFormLabel,
          value: draft.includeDialogInShot,
          enabled: canCapture,
          onChanged: (bool include) => ref
              .read(feedbackDraftProvider.notifier)
              .setIncludeDialogInShot(include: include),
        ),
        SizedBox(height: theme.spacing.xs),
        Wrap(
          spacing: theme.spacing.sm,
          runSpacing: theme.spacing.xs,
          children: <Widget>[
            AppButton.secondary(
              key: FeedbackSubmitDialog.captureThisScreenKey,
              label: l10n.feedbackCaptureThisScreenAction,
              leadingIcon: Icons.photo_camera_outlined,
              isLoading: _isCapturing,
              onPressed: canCapture ? _captureThisScreen : null,
            ),
            AppButton.secondary(
              key: FeedbackSubmitDialog.captureAnotherScreenKey,
              label: l10n.feedbackCaptureAnotherScreenAction,
              leadingIcon: Icons.open_in_new,
              onPressed: canCapture ? _captureAnotherScreen : null,
            ),
          ],
        ),
      ],
    );
  }

  /// Keeps the form's own fields in the draft, so nothing typed is lost when
  /// the reporter leaves to capture a screen.
  void _saveEntry({FeedbackCategory? category, String? message}) {
    ref
        .read(feedbackDraftProvider.notifier)
        .saveEntry(
          category: category ?? _draft.category,
          message: message ?? _messageController.text,
        );
  }

  void _setScope(FeedbackScope? scope) {
    if (scope == null) {
      return;
    }
    _saveEntry();
    ref.read(feedbackDraftProvider.notifier).setScope(scope);
    if (scope == FeedbackScope.screens && _draft.screens.isEmpty) {
      unawaited(_pickScreens());
    }
  }

  Future<void> _pickScreens() async {
    final AppLocalizations l10n = context.l10n;
    final FeedbackDraft draft = _draft;
    final List<FeedbackScreenReference>? picked =
        await showFeedbackScreenPickerDialog(
          context: context,
          choices: reachableFeedbackScreens(
            l10n: l10n,
            policy: ref.read(appAccessPolicyProvider),
            signedIn: draft.signedIn,
          ),
          selected: draft.screens,
        );
    if (picked == null || !mounted) {
      return;
    }
    ref.read(feedbackDraftProvider.notifier).setScreens(picked);
    setState(() => _showScreensError = false);
  }

  Future<void> _captureThisScreen() async {
    final AppLocalizations l10n = context.l10n;
    _saveEntry();
    setState(() => _isCapturing = true);
    try {
      final FeedbackScreenshot? screenshot =
          await ref.read(feedbackScreenCapturerProvider)(
            ref: ref,
            router: GoRouter.of(context),
            l10n: l10n,
            hideForm: !_draft.includeDialogInShot,
          );
      if (!mounted) {
        return;
      }
      if (screenshot == null) {
        showAppNoticeSnackBar(context, l10n.feedbackCaptureFailedMessage);
        return;
      }
      final FeedbackDraftController draft = ref.read(
        feedbackDraftProvider.notifier,
      );
      final int limit = feedbackScreenshotLimit(signedIn: _draft.signedIn);
      if (!draft.addScreenshot(screenshot)) {
        showAppNoticeSnackBar(
          context,
          l10n.feedbackCaptureLimitReachedMessage(limit),
        );
        return;
      }
      showAppSuccessSnackBar(
        context,
        l10n.feedbackCaptureCapturedMessage(_draft.screenshots.length, limit),
      );
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  /// Puts the form aside: the host takes over so the reporter can navigate
  /// and keep capturing, then reopens this form with everything intact.
  void _captureAnotherScreen() {
    _saveEntry();
    ref.read(feedbackDraftProvider.notifier).beginCapturing();
    Navigator.of(context).pop(const FeedbackSubmitOutcome.capturesMoreScreens());
  }

  Future<void> _cropScreenshot(int index) async {
    final FeedbackScreenshot screenshot = _draft.screenshots[index];
    final Uint8List? cropped = await showAppImageCropDialog(
      context: context,
      imageBytes: screenshot.bytes,
    );
    if (cropped == null || !mounted) {
      return;
    }
    ref
        .read(feedbackDraftProvider.notifier)
        .replaceScreenshot(
          index,
          // The cropped image keeps the screen and time of the original; only
          // its pixels and size change.
          screenshot.copyWith(bytes: cropped),
        );
  }

  Future<void> _submit() async {
    if (_isSubmitting || !validateAndSaveAppForm(_formKey)) {
      return;
    }
    _saveEntry();
    final FeedbackDraft draft = _draft;
    if (draft.scope == FeedbackScope.screens && draft.screens.isEmpty) {
      setState(() => _showScreensError = true);
      return;
    }

    setState(() {
      _isSubmitting = true;
      _failure = null;
      _showScreensError = false;
    });

    final Result<FeedbackReceipt> result = await ref
        .read(feedbackRepositoryProvider)
        .submitFeedback(
          FeedbackSubmission(
            category: draft.category,
            message: draft.message.trim(),
            context: draft.context,
            submittedAt: DateTime.now(),
            scope: draft.scope,
            screens: draft.screens,
            screenshots: draft.screenshots,
          ),
          signedIn: draft.signedIn,
        );

    if (!mounted) {
      return;
    }

    switch (result) {
      case ResultSuccess<FeedbackReceipt>(value: final FeedbackReceipt receipt):
        ref.read(feedbackDraftProvider.notifier).reset();
        Navigator.of(context).pop(FeedbackSubmitOutcome.submitted(receipt));
      case ResultFailure<FeedbackReceipt>(failure: final AppFailure failure):
        // Keep the dialog open with the message intact so the user can retry.
        setState(() {
          _failure = failure;
          _isSubmitting = false;
        });
    }
  }
}

/// Every feedback type as a checkbox, all visible, exactly one checked.
class _FeedbackCategoryField extends StatelessWidget {
  const _FeedbackCategoryField({
    required this.value,
    required this.revision,
    required this.enabled,
    required this.onChanged,
  });

  final FeedbackCategory value;

  /// Changes on every tap. `AppCheckboxField` keeps its own checked state, so
  /// re-keying rebuilds each box from [value]; otherwise tapping the checked
  /// type would untick it and leave nothing selected.
  final int revision;
  final bool enabled;
  final ValueChanged<FeedbackCategory> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        appFieldLabelWidget(
              context,
              l10n.feedbackCategoryLabel,
              isRequired: true,
            ) ??
            Text(l10n.feedbackCategoryLabel),
        SizedBox(height: theme.spacing.xs),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            // One row of all types on large screens; wraps on smaller ones.
            final int columns = switch (AppBreakpoints.fromConstraints(
              constraints,
            )) {
              AppBreakpoint.xs => 1,
              AppBreakpoint.sm => 2,
              AppBreakpoint.md => 3,
              _ => FeedbackCategory.values.length,
            };
            final double gap = theme.spacing.md;
            final double itemWidth =
                (constraints.maxWidth - gap * (columns - 1)) / columns;

            return Wrap(
              spacing: gap,
              children: <Widget>[
                for (final FeedbackCategory category in FeedbackCategory.values)
                  SizedBox(
                    width: itemWidth,
                    child: AppCheckboxField(
                      key: ValueKey<String>(
                        'feedback-category-${category.name}-$revision',
                      ),
                      title: feedbackCategoryLabel(l10n, category),
                      value: category == value,
                      enabled: enabled,
                      onChanged: (_) => onChanged(category),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
