import 'package:flutter/material.dart';
import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';
import 'package:hosspi_hms/features/feedback/presentation/widgets/feedback_records_dialog.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/components/components.dart';

/// What "Download feedback" asked for: the picked records, or, when none were
/// picked, every record [filters] matches.
typedef FeedbackExportRequest = ({
  Set<String> referenceIds,
  FeedbackFilters filters,
});

/// Opens Download feedback. Resolves to what to export, or null when the
/// dialog closes without downloading.
Future<FeedbackExportRequest?> showFeedbackDownloadDialog({
  required BuildContext context,
}) {
  return showAppDialog<FeedbackExportRequest>(
    context: context,
    builder: (_) => const FeedbackDownloadDialog(),
  );
}

/// Download feedback: platform owners and platform admins pick stored feedback
/// and export it as a workbook. Picking nothing downloads every record the
/// search and filters match, which is the whole store by default.
///
/// The picking itself — paging, search, filters, sorting — is
/// [FeedbackRecordsDialog]; the caller does the export and the save, so the
/// same picker serves Clear feedback next door.
class FeedbackDownloadDialog extends StatelessWidget {
  const FeedbackDownloadDialog({super.key});

  /// The header checkbox that selects every record on the page.
  static const Key pageCheckboxKey = ValueKey<String>(
    'feedback-download-select-page',
  );

  static Key rowCheckboxKey(String referenceId) {
    return ValueKey<String>('feedback-download-select-$referenceId');
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return FeedbackRecordsDialog<FeedbackExportRequest>(
      title: l10n.feedbackDownloadActionLabel,
      icon: AppActionIcons.download,
      confirmLabel: l10n.feedbackDownloadSelectedAction,
      confirmIcon: AppActionIcons.download,
      requiresSelection: false,
      pageCheckboxKey: pageCheckboxKey,
      rowCheckboxKeyBuilder: rowCheckboxKey,
      onConfirm:
          (_, Set<String> referenceIds, FeedbackFilters filters) async =>
              (referenceIds: referenceIds, filters: filters),
    );
  }
}
