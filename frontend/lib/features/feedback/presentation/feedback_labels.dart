import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';

String feedbackCategoryLabel(AppLocalizations l10n, FeedbackCategory category) {
  return switch (category) {
    FeedbackCategory.general => l10n.feedbackCategoryGeneral,
    FeedbackCategory.problem => l10n.feedbackCategoryProblem,
    FeedbackCategory.complaint => l10n.feedbackCategoryComplaint,
    FeedbackCategory.suggestion => l10n.feedbackCategorySuggestion,
    FeedbackCategory.improvement => l10n.feedbackCategoryImprovement,
  };
}

String feedbackSubmitterTypeLabel(
  AppLocalizations l10n,
  FeedbackSubmitterType type,
) {
  return switch (type) {
    FeedbackSubmitterType.authenticated => l10n.feedbackSubmitterSignedIn,
    FeedbackSubmitterType.anonymous => l10n.feedbackSubmitterAnonymous,
  };
}

String feedbackDeviceTypeLabel(AppLocalizations l10n, FeedbackDeviceType type) {
  return switch (type) {
    FeedbackDeviceType.mobile => l10n.feedbackDeviceTypeMobile,
    FeedbackDeviceType.tablet => l10n.feedbackDeviceTypeTablet,
    FeedbackDeviceType.desktop => l10n.feedbackDeviceTypeDesktop,
  };
}

/// Display name for a stored `client_platform`; unknown values show as stored.
String feedbackPlatformName(AppLocalizations l10n, String platform) {
  return switch (platform.toLowerCase()) {
    'web' => l10n.feedbackPlatformWeb,
    'android' => l10n.feedbackPlatformAndroid,
    'ios' => l10n.feedbackPlatformIos,
    'windows' => l10n.feedbackPlatformWindows,
    'macos' => l10n.feedbackPlatformMacos,
    'linux' => l10n.feedbackPlatformLinux,
    _ => platform,
  };
}
