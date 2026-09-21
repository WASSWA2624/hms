import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/permissions/permission_providers.dart';
import 'package:hosspi_hms/features/feedback/data/repositories/feedback_repository_impl.dart';
import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';
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

/// How the feedback form ended.
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

/// Whether the form is busy, so the surface holding it can disable its
/// footer without owning the work.
final class FeedbackFormStatus {
  const FeedbackFormStatus({
    this.isSubmitting = false,
    this.isCapturing = false,
  });

  final bool isSubmitting;
  final bool isCapturing;

  bool get isBusy => isSubmitting || isCapturing;
}

final feedbackFormStatusProvider =
    NotifierProvider<FeedbackFormStatusController, FeedbackFormStatus>(
      FeedbackFormStatusController.new,
    );

final class FeedbackFormStatusController extends Notifier<FeedbackFormStatus> {
  @override
  FeedbackFormStatus build() => const FeedbackFormStatus();

  void set({bool? isSubmitting, bool? isCapturing}) {
    state = FeedbackFormStatus(
      isSubmitting: isSubmitting ?? state.isSubmitting,
      isCapturing: isCapturing ?? state.isCapturing,
    );
  }

  void reset() {
    state = const FeedbackFormStatus();
  }
}

/// Close and send, for whichever surface is holding the form.
List<Widget> buildFeedbackFormActions({
  required AppLocalizations l10n,
  required FeedbackFormStatus status,
  required VoidCallback? onCancel,
  required VoidCallback? onSubmit,
  bool compact = false,
}) {
  return <Widget>[
    AppButton.close(
      label: l10n.commonCancelActionLabel,
      enabled: !status.isBusy,
      onPressed: status.isBusy ? null : onCancel,
    ),
    AppButton.primary(
      label: l10n.feedbackSubmitActionLabel,
      leadingIcon: Icons.send_outlined,
      isLoading: status.isSubmitting,
      fullWidth: compact,
      onPressed: status.isBusy ? null : onSubmit,
    ),
  ];
}

/// The "Give us feedback" form itself, without any surface around it.
///
/// The same fields serve the panel docked beside the app and the dialog over
/// it, so switching between the two changes where the form sits and nothing
/// else. Everything typed, picked and captured lives in
/// [feedbackDraftProvider], so the form can close and come back untouched.
class FeedbackFormView extends ConsumerStatefulWidget {
  const FeedbackFormView({
    required this.onFinished,
    this.dialogContext,
    this.router,
    super.key,
  });

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
  static const Key categoryFieldKey = ValueKey<String>('feedback-category');
  static const Key scopeFieldKey = ValueKey<String>('feedback-scope');

  /// Called when the report is sent, or when the reporter leaves to capture
  /// more screens. The surface around the form decides what to do with it.
  final ValueChanged<FeedbackSubmitOutcome> onFinished;

  /// Context with the app's navigator for modal helpers opened from a dock
  /// that sits outside the router child.
  final BuildContext? dialogContext;

  /// Router used for capture metadata when the form itself is outside the
  /// router child.
  final GoRouter? router;

  @override
  ConsumerState<FeedbackFormView> createState() => FeedbackFormViewState();
}

class FeedbackFormViewState extends ConsumerState<FeedbackFormView> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _messageController;
  bool _isSubmitting = false;
  bool _isCapturing = false;
  bool _showScreensError = false;
  AppFailure? _failure;

  FeedbackDraft get _draft => ref.read(feedbackDraftProvider)!;

  bool get _busy => _isSubmitting || _isCapturing;

  BuildContext get _dialogContext {
    final BuildContext? dialogContext = widget.dialogContext;
    if (dialogContext != null && dialogContext.mounted) {
      return dialogContext;
    }
    return context;
  }

  GoRouter get _router => widget.router ?? GoRouter.of(context);

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

  void _setBusy({bool? isSubmitting, bool? isCapturing}) {
    if (isSubmitting != null) {
      _isSubmitting = isSubmitting;
    }
    if (isCapturing != null) {
      _isCapturing = isCapturing;
    }
    setState(() {});
    ref
        .read(feedbackFormStatusProvider.notifier)
        .set(isSubmitting: isSubmitting, isCapturing: isCapturing);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = context.l10n;
    final FeedbackDraft? draft = ref.watch(feedbackDraftProvider);
    if (draft == null) {
      return const SizedBox.shrink();
    }

    return AppFormShell(
      formKey: _formKey,
      enabled: !_busy,
      formStatus: appFormFailureStatus(context, _failure),
      children: <Widget>[
        // Two short answers the reporter can give at a glance, side by side
        // where there is room for them.
        AppResponsiveFieldRow.two(
          // Side by side on desktop and in the docked panel; compact phones
          // still stack them.
          breakpoint: 440,
          left: AppSelectField<FeedbackCategory>(
            key: FeedbackFormView.categoryFieldKey,
            labelText: l10n.feedbackCategoryLabel,
            value: draft.category,
            isRequired: true,
            allowClear: false,
            enabled: !_busy,
            options: <AppSelectOption<FeedbackCategory>>[
              for (final FeedbackCategory category in FeedbackCategory.values)
                AppSelectOption<FeedbackCategory>(
                  value: category,
                  label: feedbackCategoryLabel(l10n, category),
                ),
            ],
            onChanged: (FeedbackCategory? category) {
              if (category != null) {
                _saveEntry(category: category);
              }
            },
          ),
          right: AppSelectField<FeedbackScope>(
            key: FeedbackFormView.scopeFieldKey,
            labelText: l10n.feedbackScopeLabel,
            value: draft.scope,
            isRequired: true,
            allowClear: false,
            enabled: !_busy,
            // The chosen scope explains itself underneath, so the wording
            // that used to sit on the radio cards is not lost.
            helperText: _scopeDescription(l10n, draft.scope),
            errorText: _showScreensError && draft.scope == FeedbackScope.screens
                ? l10n.feedbackScreensRequiredMessage
                : null,
            options: <AppSelectOption<FeedbackScope>>[
              for (final FeedbackScope scope in FeedbackScope.values)
                AppSelectOption<FeedbackScope>(
                  value: scope,
                  label: feedbackScopeLabel(l10n, scope),
                ),
            ],
            onChanged: _setScope,
          ),
        ),
        if (draft.scope == FeedbackScope.screens)
          _screensField(l10n, draft, theme),
        AppTextField(
          controller: _messageController,
          labelText: l10n.feedbackMessageLabel,
          hintText: l10n.feedbackMessageHint,
          isRequired: true,
          autofocus: true,
          minLines: 4,
          maxLines: 8,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (String value) => _saveEntry(message: value),
          validator: AppValidators.compose<String>(<FormFieldValidator<String>>[
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
          ]),
        ),
        _screenshotsField(l10n, draft, theme),
      ],
    );
  }

  String _scopeDescription(AppLocalizations l10n, FeedbackScope scope) {
    return switch (scope) {
      FeedbackScope.screen => l10n.feedbackScopeThisScreenDescription,
      FeedbackScope.app => l10n.feedbackScopeWholeAppDescription,
      FeedbackScope.screens => l10n.feedbackScopeSelectedScreensDescription,
    };
  }

  /// The screens a "selected screens" report names, as removable chips.
  Widget _screensField(
    AppLocalizations l10n,
    FeedbackDraft draft,
    ThemeData theme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        appFieldLabelWidget(
              context,
              l10n.feedbackScreensLabel,
              isRequired: true,
            ) ??
            Text(l10n.feedbackScreensLabel),
        SizedBox(height: theme.spacing.xs),
        Wrap(
          spacing: theme.spacing.xs,
          runSpacing: theme.spacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            for (final FeedbackScreenReference screen in draft.screens)
              InputChip(
                label: Text(screen.label),
                isEnabled: !_busy,
                visualDensity: VisualDensity.compact,
                onDeleted: _busy
                    ? null
                    : () => ref
                          .read(feedbackDraftProvider.notifier)
                          .removeScreen(screen),
                deleteButtonTooltipMessage: l10n.feedbackScreenRemoveLabel(
                  screen.label,
                ),
              ),
            AppButton.tertiary(
              key: FeedbackFormView.chooseScreensKey,
              label: l10n.feedbackChooseScreensAction,
              leadingIcon: Icons.checklist_outlined,
              dense: true,
              onPressed: _busy ? null : _pickScreens,
            ),
          ],
        ),
      ],
    );
  }

  /// The pictures attached so far, and the two ways to add another.
  Widget _screenshotsField(
    AppLocalizations l10n,
    FeedbackDraft draft,
    ThemeData theme,
  ) {
    final int limit = feedbackScreenshotLimit(signedIn: draft.signedIn);
    final bool canCapture = !_busy && draft.canCaptureMore;
    final ColorScheme colors = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(theme.radius.sm),
        border: Border.all(color: colors.outlineVariant),
      ),
      padding: EdgeInsets.all(theme.spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.image_outlined,
                size: theme.appTokens.listIconSize,
                color: colors.onSurfaceVariant,
              ),
              SizedBox(width: theme.spacing.xs),
              Expanded(
                child: Text(
                  l10n.feedbackScreenshotsLabel,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text(
                l10n.feedbackScreenshotsCountLabel(
                  draft.screenshots.length,
                  limit,
                ),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          SizedBox(height: theme.spacing.sm),
          if (draft.screenshots.isEmpty)
            Text(
              l10n.feedbackScreenshotsEmptyHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            )
          else ...<Widget>[
            FeedbackScreenshotStrip(
              screenshots: draft.screenshots,
              enabled: !_busy,
              onRemove: (int index) => ref
                  .read(feedbackDraftProvider.notifier)
                  .removeScreenshot(index),
              onCrop: _cropScreenshot,
              onCaptionChanged: (int index, String caption) => ref
                  .read(feedbackDraftProvider.notifier)
                  .replaceScreenshot(
                    index,
                    draft.screenshots[index].copyWith(caption: caption),
                  ),
            ),
            SizedBox(height: theme.spacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.privacy_tip_outlined,
                  size: theme.appTokens.listIconSize,
                  color: colors.onSurfaceVariant,
                ),
                SizedBox(width: theme.spacing.xs),
                Expanded(
                  child: Text(
                    l10n.feedbackScreenshotsPatientDataNotice,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: theme.spacing.sm),
          AppCheckboxField(
            key: FeedbackFormView.includeFormKey,
            title: l10n.feedbackCaptureIncludeFormLabel,
            value: draft.includeDialogInShot,
            enabled: canCapture,
            contentPadding: EdgeInsets.zero,
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
                key: FeedbackFormView.captureThisScreenKey,
                label: l10n.feedbackCaptureThisScreenAction,
                leadingIcon: Icons.photo_camera_outlined,
                isLoading: _isCapturing,
                dense: true,
                onPressed: canCapture ? _captureThisScreen : null,
              ),
              AppButton.secondary(
                key: FeedbackFormView.captureAnotherScreenKey,
                label: l10n.feedbackCaptureAnotherScreenAction,
                leadingIcon: Icons.open_in_new,
                dense: true,
                onPressed: canCapture ? _captureAnotherScreen : null,
              ),
            ],
          ),
        ],
      ),
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
    final BuildContext dialogContext = _dialogContext;
    final AppLocalizations l10n = dialogContext.l10n;
    final FeedbackDraft draft = _draft;
    final List<FeedbackScreenReference>? picked =
        await showFeedbackScreenPickerDialog(
          context: dialogContext,
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
    final BuildContext dialogContext = _dialogContext;
    final AppLocalizations l10n = dialogContext.l10n;
    _saveEntry();
    _setBusy(isCapturing: true);
    try {
      final FeedbackScreenshot? screenshot =
          await ref.read(feedbackScreenCapturerProvider)(
            ref: ref,
            router: _router,
            l10n: l10n,
            hideForm: !_draft.includeDialogInShot,
          );
      if (!mounted) {
        return;
      }
      if (screenshot == null) {
        showAppNoticeSnackBar(dialogContext, l10n.feedbackCaptureFailedMessage);
        return;
      }
      final FeedbackDraftController draft = ref.read(
        feedbackDraftProvider.notifier,
      );
      final int limit = feedbackScreenshotLimit(signedIn: _draft.signedIn);
      if (!draft.addScreenshot(screenshot)) {
        showAppNoticeSnackBar(
          dialogContext,
          l10n.feedbackCaptureLimitReachedMessage(limit),
        );
        return;
      }
      showAppSuccessSnackBar(
        dialogContext,
        l10n.feedbackCaptureCapturedMessage(_draft.screenshots.length, limit),
      );
    } finally {
      if (mounted) {
        _setBusy(isCapturing: false);
      }
    }
  }

  /// Puts the form aside: the floating control takes over so the reporter can
  /// navigate and keep capturing, then brings the form back intact.
  void _captureAnotherScreen() {
    _saveEntry();
    ref.read(feedbackFormStatusProvider.notifier).reset();
    ref.read(feedbackDraftProvider.notifier).beginCapturing();
    widget.onFinished(const FeedbackSubmitOutcome.capturesMoreScreens());
  }

  Future<void> _cropScreenshot(int index) async {
    final FeedbackScreenshot screenshot = _draft.screenshots[index];
    final BuildContext dialogContext = _dialogContext;
    final Uint8List? cropped = await showAppImageCropDialog(
      context: dialogContext,
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
          // its pixels change.
          screenshot.copyWith(bytes: cropped),
        );
  }

  /// Sends the report. The surface's footer calls this through the form's
  /// key, so the footer never has to own any of the work.
  Future<void> submit() async {
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
      _failure = null;
      _showScreensError = false;
    });
    _setBusy(isSubmitting: true);

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
        ref.read(feedbackFormStatusProvider.notifier).reset();
        widget.onFinished(FeedbackSubmitOutcome.submitted(receipt));
      case ResultFailure<FeedbackReceipt>(failure: final AppFailure failure):
        // Keep the form open with the message intact so the user can retry.
        setState(() => _failure = failure);
        _setBusy(isSubmitting: false);
    }
  }
}
