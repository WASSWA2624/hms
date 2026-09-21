import 'package:flutter/material.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';

/// Shows a localized failure message as a [SnackBar] when [failure] is non-null.
///
/// This is the standard workspace-level feedback pattern. All workspace pages
/// and shared dialogs should use this instead of inlining their own
/// `ScaffoldMessenger.of(context).showSnackBar(...)` calls.
///
/// Returns silently when [failure] is null or [context] is not mounted.
void showAppFailureSnackBar(BuildContext context, AppFailure? failure) {
  if (failure == null) {
    return;
  }
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(context.l10n.failureMessage(failure))));
}

/// Shows a localized success message as a [SnackBar].
void showAppSuccessSnackBar(BuildContext context, String message) {
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Shows a plain notice as a [SnackBar]: something the app is telling the
/// user that is neither a success nor an [AppFailure] the API returned — a
/// limit reached, a step the platform could not do.
void showAppNoticeSnackBar(BuildContext context, String message) {
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
