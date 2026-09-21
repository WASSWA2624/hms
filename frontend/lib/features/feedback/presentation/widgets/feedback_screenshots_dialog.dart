import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/utils/app_formatters.dart';
import 'package:hosspi_hms/features/feedback/data/repositories/feedback_repository_impl.dart';
import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/components/components.dart';
import 'package:hosspi_hms/shared/layout/app_workspace.dart';

/// Opens the screenshots attached to one stored feedback record.
Future<void> showFeedbackScreenshotsDialog({
  required BuildContext context,
  required String referenceId,
}) {
  return showAppDialog<void>(
    context: context,
    builder: (_) => FeedbackScreenshotsDialog(referenceId: referenceId),
  );
}

/// The pictures a reporter attached, for the platform owners and admins who
/// triage their feedback.
///
/// Images are fetched one at a time through the authenticated route: they can
/// show patient data, so they are never on a public path and never cached.
class FeedbackScreenshotsDialog extends ConsumerStatefulWidget {
  const FeedbackScreenshotsDialog({required this.referenceId, super.key});

  static Key imageKey(String screenshotId) =>
      ValueKey<String>('feedback-stored-screenshot-$screenshotId');

  final String referenceId;

  @override
  ConsumerState<FeedbackScreenshotsDialog> createState() =>
      _FeedbackScreenshotsDialogState();
}

class _FeedbackScreenshotsDialogState
    extends ConsumerState<FeedbackScreenshotsDialog> {
  List<FeedbackStoredScreenshot> _screenshots =
      const <FeedbackStoredScreenshot>[];
  AppFailure? _failure;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final Result<List<FeedbackStoredScreenshot>> result = await ref
        .read(feedbackRepositoryProvider)
        .fetchFeedbackScreenshots(referenceId: widget.referenceId);
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = false;
      switch (result) {
        case ResultSuccess<List<FeedbackStoredScreenshot>>(
          value: final List<FeedbackStoredScreenshot> items,
        ):
          _screenshots = items;
          _failure = null;
        case ResultFailure<List<FeedbackStoredScreenshot>>(
          failure: final AppFailure failure,
        ):
          _failure = failure;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = context.l10n;

    return AppDialog(
      title: Text(l10n.feedbackScreenshotsDialogTitle(widget.referenceId)),
      icon: const Icon(Icons.image_outlined),
      scrollable: true,
      content: switch ((_isLoading, _failure, _screenshots.isEmpty)) {
        (true, _, _) => AppLoadingIndicator(title: l10n.feedbackLoadingTitle),
        (_, final AppFailure failure?, _) => AppWorkspaceStatePanel.error(
          title: l10n.feedbackLoadErrorTitle,
          body: context.l10n.failureMessage(failure),
          action: AppButton.secondary(
            label: l10n.feedbackRetryAction,
            leadingIcon: Icons.refresh,
            onPressed: () {
              setState(() => _isLoading = true);
              unawaited(_load());
            },
          ),
        ),
        (_, _, true) => AppWorkspaceStatePanel.empty(
          icon: Icons.image_not_supported_outlined,
          title: l10n.feedbackScreenshotsEmptyMessage,
          body: l10n.feedbackEmptyBody,
        ),
        _ => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final FeedbackStoredScreenshot screenshot in _screenshots)
              Padding(
                padding: EdgeInsets.only(bottom: theme.spacing.md),
                child: _StoredScreenshot(
                  referenceId: widget.referenceId,
                  screenshot: screenshot,
                ),
              ),
          ],
        ),
      },
      actions: <Widget>[
        AppButton.close(
          label: l10n.commonCloseActionLabel,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}

/// One stored image, fetched on demand with its screen and capture time.
class _StoredScreenshot extends ConsumerStatefulWidget {
  const _StoredScreenshot({required this.referenceId, required this.screenshot});

  final String referenceId;
  final FeedbackStoredScreenshot screenshot;

  @override
  ConsumerState<_StoredScreenshot> createState() => _StoredScreenshotState();
}

class _StoredScreenshotState extends ConsumerState<_StoredScreenshot> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final Result<Uint8List> result = await ref
        .read(feedbackRepositoryProvider)
        .fetchFeedbackScreenshotImage(
          referenceId: widget.referenceId,
          screenshotId: widget.screenshot.id,
        );
    if (!mounted) {
      return;
    }
    setState(() {
      switch (result) {
        case ResultSuccess<Uint8List>(value: final Uint8List bytes):
          _bytes = bytes;
        case ResultFailure<Uint8List>():
          _failed = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = context.l10n;
    final FeedbackStoredScreenshot screenshot = widget.screenshot;
    final DateTime? capturedAt = screenshot.capturedAt;
    final Uint8List? bytes = _bytes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '${screenshot.sequence}. ${screenshot.screen.label}',
          style: theme.textTheme.labelLarge,
        ),
        if (capturedAt != null)
          Text(
            AppFormatters.dateTime(capturedAt, Localizations.localeOf(context)),
            style: theme.textTheme.bodySmall,
          ),
        if ((screenshot.caption ?? '').isNotEmpty)
          Text(screenshot.caption!, style: theme.textTheme.bodyMedium),
        SizedBox(height: theme.spacing.xs),
        if (_failed)
          Text(
            l10n.feedbackScreenshotLoadErrorMessage,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          )
        else if (bytes == null)
          AppLoadingIndicator(title: l10n.feedbackLoadingTitle)
        else
          ClipRRect(
            key: FeedbackScreenshotsDialog.imageKey(screenshot.id),
            borderRadius: BorderRadius.circular(theme.radius.xs),
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
      ],
    );
  }
}
