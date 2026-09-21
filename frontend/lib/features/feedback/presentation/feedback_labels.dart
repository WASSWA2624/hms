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

/// What a report says it applies to, in words.
String feedbackScopeLabel(AppLocalizations l10n, FeedbackScope scope) {
  return switch (scope) {
    FeedbackScope.screen => l10n.feedbackScopeThisScreen,
    FeedbackScope.app => l10n.feedbackScopeWholeApp,
    FeedbackScope.screens => l10n.feedbackScopeSelectedScreens,
  };
}

/// Readable name for a stored filter value, e.g. `Extra large` for the `xl`
/// breakpoint or the tenant's name for its public id. Values the app has no
/// name for show as stored; role and screen codes are spelled out.
String feedbackFacetValueLabel(
  AppLocalizations l10n,
  FeedbackFilterDimension dimension,
  FeedbackFacetValue facet,
) {
  final String value = facet.value;
  return switch (dimension) {
    FeedbackFilterDimension.tenant ||
    FeedbackFilterDimension.facility => facet.label ?? value,
    FeedbackFilterDimension.platform => feedbackPlatformName(l10n, value),
    FeedbackFilterDimension.role ||
    FeedbackFilterDimension.routeName ||
    FeedbackFilterDimension.appliesToRoute => feedbackHumanizeCode(value),
    FeedbackFilterDimension.appliesTo => feedbackScopeLabel(
      l10n,
      FeedbackScope.fromApiValue(value.toUpperCase()),
    ),
    FeedbackFilterDimension.planTier => switch (value.toUpperCase()) {
      'FREE' => l10n.feedbackPlanTierFree,
      'BASIC' => l10n.feedbackPlanTierBasic,
      'ADVANCED' => l10n.feedbackPlanTierAdvanced,
      'PRO' => l10n.feedbackPlanTierPro,
      'CUSTOM' => l10n.feedbackPlanTierCustom,
      'DEVELOPER' => l10n.feedbackPlanTierDeveloper,
      _ => feedbackHumanizeCode(value),
    },
    FeedbackFilterDimension.subscriptionStatus => switch (value.toUpperCase()) {
      'ACTIVE' => l10n.feedbackSubscriptionStatusActive,
      'TRIAL' => l10n.feedbackSubscriptionStatusTrial,
      'PAST_DUE' => l10n.feedbackSubscriptionStatusPastDue,
      'CANCELLED' => l10n.feedbackSubscriptionStatusCancelled,
      _ => feedbackHumanizeCode(value),
    },
    FeedbackFilterDimension.appEnvironment => switch (value.toLowerCase()) {
      'development' => l10n.feedbackEnvironmentDevelopment,
      'staging' => l10n.feedbackEnvironmentStaging,
      'production' => l10n.feedbackEnvironmentProduction,
      _ => value,
    },
    FeedbackFilterDimension.appVersion => value,
    FeedbackFilterDimension.breakpoint => switch (value.toLowerCase()) {
      'xs' => l10n.feedbackBreakpointXs,
      'sm' => l10n.feedbackBreakpointSm,
      'md' => l10n.feedbackBreakpointMd,
      'lg' => l10n.feedbackBreakpointLg,
      'xl' => l10n.feedbackBreakpointXl,
      'xxl' => l10n.feedbackBreakpointXxl,
      _ => value,
    },
    FeedbackFilterDimension.orientation => switch (value.toLowerCase()) {
      'portrait' => l10n.feedbackOrientationPortrait,
      'landscape' => l10n.feedbackOrientationLandscape,
      _ => value,
    },
    FeedbackFilterDimension.theme => switch (value.toLowerCase()) {
      'light' => l10n.feedbackThemeLight,
      'dark' => l10n.feedbackThemeDark,
      _ => value,
    },
    FeedbackFilterDimension.locale => switch (value.toLowerCase()) {
      'en' => l10n.feedbackLocaleEnglish,
      _ => value,
    },
    FeedbackFilterDimension.connectivity => switch (value.toLowerCase()) {
      'online' => l10n.feedbackConnectivityOnline,
      'offline' => l10n.feedbackConnectivityOffline,
      _ => value,
    },
  };
}

/// How many records hold a filter value, after the stored value itself
/// whenever the label does not already show it (`xl · 19 records`).
String feedbackFacetCaption(
  AppLocalizations l10n,
  FeedbackFilterDimension dimension,
  FeedbackFacetValue facet,
) {
  final String records = l10n.feedbackFacetCountCaption(facet.count);
  return feedbackFacetValueLabel(l10n, dimension, facet) == facet.value
      ? records
      : l10n.feedbackFacetValueCaption(facet.value, records);
}

final RegExp _camelCaseBoundary = RegExp('([a-z0-9])([A-Z])');
final RegExp _codeSeparators = RegExp(r'[_\-\s]+');

/// `PLATFORM_ADMIN` → `Platform admin`, `tenantFacilitySetup` →
/// `Tenant facility setup`.
String feedbackHumanizeCode(String code) {
  final String words = code
      .replaceAllMapped(
        _camelCaseBoundary,
        (Match match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAll(_codeSeparators, ' ')
      .trim()
      .toLowerCase();
  if (words.isEmpty) {
    return code;
  }
  return '${words[0].toUpperCase()}${words.substring(1)}';
}
