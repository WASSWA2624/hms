import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/features/feedback/data/repositories/feedback_repository_impl.dart';
import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/components/components.dart';
import 'package:hosspi_hms/shared/forms/forms.dart';

String feedbackCategoryLabel(AppLocalizations l10n, FeedbackCategory category) {
  return switch (category) {
    FeedbackCategory.general => l10n.feedbackCategoryGeneral,
    FeedbackCategory.problem => l10n.feedbackCategoryProblem,
    FeedbackCategory.complaint => l10n.feedbackCategoryComplaint,
    FeedbackCategory.suggestion => l10n.feedbackCategorySuggestion,
    FeedbackCategory.improvement => l10n.feedbackCategoryImprovement,
  };
}

String feedbackDeviceTypeLabel(
  AppLocalizations l10n,
  FeedbackDeviceType? deviceType,
) {
  return switch (deviceType) {
    FeedbackDeviceType.mobile => l10n.feedbackDeviceTypeMobile,
    FeedbackDeviceType.tablet => l10n.feedbackDeviceTypeTablet,
    FeedbackDeviceType.desktop => l10n.feedbackDeviceTypeDesktop,
    null => l10n.feedbackDeviceTypeUnknown,
  };
}

/// "Give us feedback" form. Pops a [FeedbackReceipt] once the feedback is saved.
///
/// The caller captures the screen and device context; the form asks only for
/// what the system cannot know: the kind of feedback and its details.
class FeedbackSubmitDialog extends ConsumerStatefulWidget {
  const FeedbackSubmitDialog({
    required this.feedbackContext,
    required this.signedIn,
    super.key,
  });

  final FeedbackContext feedbackContext;

  /// Whether a session exists, so the server can attach account context.
  final bool signedIn;

  @override
  ConsumerState<FeedbackSubmitDialog> createState() =>
      _FeedbackSubmitDialogState();
}

class _FeedbackSubmitDialogState extends ConsumerState<FeedbackSubmitDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _messageController = TextEditingController();
  FeedbackCategory _category = FeedbackCategory.general;
  bool _isSubmitting = false;
  AppFailure? _failure;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String screen = _screenLabel(widget.feedbackContext);
    final String device = feedbackDeviceTypeLabel(
      l10n,
      widget.feedbackContext.deviceType,
    );

    return AppDialog(
      title: Text(l10n.feedbackDialogTitle),
      icon: const Icon(Icons.feedback_outlined),
      scrollable: true,
      pinActionsToBottom: true,
      closeEnabled: !_isSubmitting,
      content: AppFormShell(
        formKey: _formKey,
        enabled: !_isSubmitting,
        formStatus: appFormFailureStatus(context, _failure),
        children: <Widget>[
          AppFormInformationBanner(
            title: l10n.feedbackContextTitle,
            message: widget.signedIn
                ? l10n.feedbackContextSignedInMessage(screen, device)
                : l10n.feedbackContextAnonymousMessage(screen, device),
          ),
          AppSelectField<FeedbackCategory>(
            value: _category,
            labelText: l10n.feedbackCategoryLabel,
            options: <AppSelectOption<FeedbackCategory>>[
              for (final FeedbackCategory category in FeedbackCategory.values)
                AppSelectOption<FeedbackCategory>(
                  value: category,
                  label: feedbackCategoryLabel(l10n, category),
                ),
            ],
            onChanged: (FeedbackCategory? value) {
              if (value != null) {
                setState(() => _category = value);
              }
            },
          ),
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
        ],
      ),
      actions: <Widget>[
        AppButton.close(
          label: l10n.commonCancelActionLabel,
          enabled: !_isSubmitting,
          onPressed: _isSubmitting
              ? null
              : () => Navigator.of(context).maybePop(),
        ),
        AppButton.primary(
          label: l10n.feedbackSubmitActionLabel,
          leadingIcon: Icons.send_outlined,
          isLoading: _isSubmitting,
          onPressed: _isSubmitting ? null : _submit,
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_isSubmitting || !validateAndSaveAppForm(_formKey)) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _failure = null;
    });

    final Result<FeedbackReceipt> result = await ref
        .read(feedbackRepositoryProvider)
        .submitFeedback(
          FeedbackSubmission(
            category: _category,
            message: _messageController.text.trim(),
            context: widget.feedbackContext,
            submittedAt: DateTime.now(),
          ),
          signedIn: widget.signedIn,
        );

    if (!mounted) {
      return;
    }

    switch (result) {
      case ResultSuccess<FeedbackReceipt>(value: final FeedbackReceipt receipt):
        Navigator.of(context).pop(receipt);
      case ResultFailure<FeedbackReceipt>(failure: final AppFailure failure):
        // Keep the dialog open with the message intact so the user can retry.
        setState(() {
          _failure = failure;
          _isSubmitting = false;
        });
    }
  }
}

String _screenLabel(FeedbackContext context) {
  final String? routePath = context.routePath;
  final String? path = routePath == null ? null : Uri.tryParse(routePath)?.path;
  if (path != null && path.isNotEmpty) {
    return path;
  }
  return context.routeName ?? '/';
}
