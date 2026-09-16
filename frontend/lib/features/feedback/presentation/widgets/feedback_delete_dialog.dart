import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/features/feedback/data/repositories/feedback_repository_impl.dart';
import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';
import 'package:hosspi_hms/features/feedback/domain/repositories/feedback_repository.dart';
import 'package:hosspi_hms/features/feedback/presentation/widgets/feedback_records_dialog.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/actions/app_action_dialogs.dart';
import 'package:hosspi_hms/shared/components/components.dart';

/// Opens Clear feedback. Resolves to how many records were deleted, or null
/// when the dialog closes without deleting.
Future<int?> showFeedbackDeleteDialog({required BuildContext context}) {
  return showAppDialog<int>(
    context: context,
    builder: (_) => const FeedbackDeleteDialog(),
  );
}

/// Clear feedback: platform owners and platform admins pick stored feedback
/// and delete it permanently.
///
/// The picking itself — paging, search, filters, sorting — is
/// [FeedbackRecordsDialog]; this adds the confirmation and the deletion.
class FeedbackDeleteDialog extends ConsumerWidget {
  const FeedbackDeleteDialog({super.key});

  /// The header checkbox that selects every record on the page.
  static const Key pageCheckboxKey = ValueKey<String>(
    'feedback-delete-select-page',
  );

  static Key rowCheckboxKey(String referenceId) {
    return ValueKey<String>('feedback-delete-select-$referenceId');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;

    return FeedbackRecordsDialog<int>(
      title: l10n.feedbackDeleteDialogTitle,
      icon: AppActionIcons.delete,
      confirmLabel: l10n.feedbackDeleteSelectedAction,
      confirmIcon: AppActionIcons.delete,
      destructive: true,
      pageCheckboxKey: pageCheckboxKey,
      rowCheckboxKeyBuilder: rowCheckboxKey,
      onConfirm:
          (BuildContext dialogContext, Set<String> referenceIds, _) =>
              _confirmDelete(dialogContext, ref, referenceIds),
    );
  }

  /// Asks once more, then deletes. Resolves to how many records went, or null
  /// when the user backs out or the deletion fails.
  Future<int?> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Set<String> referenceIds,
  ) async {
    final AppLocalizations l10n = context.l10n;
    final FeedbackRepository repository = ref.read(feedbackRepositoryProvider);
    int deletedCount = 0;

    final bool? deleted = await showAppDialog<bool>(
      context: context,
      builder: (_) => AppConfirmActionDialog(
        title: l10n.feedbackDeleteConfirmTitle,
        body: l10n.feedbackDeleteConfirmBody(referenceIds.length),
        submitLabel: l10n.feedbackDeleteSelectedAction,
        icon: const Icon(AppActionIcons.delete),
        submitLeadingIcon: AppActionIcons.delete,
        destructive: true,
        onConfirm: () async {
          final Result<FeedbackDeleteResult> result = await repository
              .deleteFeedback(referenceIds: referenceIds);
          switch (result) {
            case ResultSuccess<FeedbackDeleteResult>(
              value: final FeedbackDeleteResult value,
            ):
              deletedCount = value.deletedCount;
              return null;
            case ResultFailure<FeedbackDeleteResult>(
              failure: final AppFailure failure,
            ):
              return failure;
          }
        },
      ),
    );

    return deleted == true ? deletedCount : null;
  }
}
