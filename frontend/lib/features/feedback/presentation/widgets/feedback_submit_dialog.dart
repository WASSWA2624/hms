import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/responsive/app_breakpoints.dart';
import 'package:hosspi_hms/features/feedback/data/repositories/feedback_repository_impl.dart';
import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';
import 'package:hosspi_hms/features/feedback/presentation/feedback_labels.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/components/components.dart';
import 'package:hosspi_hms/shared/forms/forms.dart';

/// "Give us feedback" form. Pops a [FeedbackReceipt] once the feedback is saved.
///
/// The caller captures the screen and device context; the form asks only for
/// what the system cannot know: the kind of feedback and its details.
///
/// It opens at the size of that form rather than filling the window, and its
/// chrome is see-through, so the screen the feedback is about stays legible
/// behind it while the user writes. Only the details box is solid: that is
/// where the user is reading their own words back. Callers pair this with a
/// see-through barrier.
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
  /// Enough of the screen behind shows through to place the feedback, while
  /// the form's own labels and buttons keep their contrast.
  static const double _surfaceOpacity = 0.86;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _messageController = TextEditingController();
  FeedbackCategory _category = FeedbackCategory.general;
  int _categoryRevision = 0;
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

    return AppDialog(
      title: Text(l10n.feedbackDialogTitle),
      icon: const Icon(Icons.feedback_outlined),
      scrollable: true,
      initialMaximized: false,
      sizeToContent: true,
      surfaceOpacity: _surfaceOpacity,
      closeEnabled: !_isSubmitting,
      content: AppFormShell(
        formKey: _formKey,
        enabled: !_isSubmitting,
        formStatus: appFormFailureStatus(context, _failure),
        children: <Widget>[
          _FeedbackCategoryField(
            value: _category,
            revision: _categoryRevision,
            enabled: !_isSubmitting,
            onChanged: (FeedbackCategory category) {
              setState(() {
                _category = category;
                _categoryRevision += 1;
              });
            },
          ),
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
