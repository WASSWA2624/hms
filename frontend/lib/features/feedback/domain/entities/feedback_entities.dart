/// Kind of feedback a user is giving. [apiValue] matches the API enum.
enum FeedbackCategory {
  general('GENERAL'),
  problem('PROBLEM'),
  complaint('COMPLAINT'),
  suggestion('SUGGESTION'),
  improvement('IMPROVEMENT');

  const FeedbackCategory(this.apiValue);

  final String apiValue;

  static FeedbackCategory fromApiValue(Object? value) {
    for (final FeedbackCategory category in values) {
      if (category.apiValue == value) {
        return category;
      }
    }
    return general;
  }
}

/// Whether the server identified who submitted the feedback.
enum FeedbackSubmitterType {
  authenticated('AUTHENTICATED'),
  anonymous('ANONYMOUS');

  const FeedbackSubmitterType(this.apiValue);

  final String apiValue;

  static FeedbackSubmitterType fromApiValue(Object? value) {
    return value == authenticated.apiValue ? authenticated : anonymous;
  }
}

/// Screen size class of the app window feedback came from, so fixes can
/// target specific layouts. [apiValue] matches the API enum.
enum FeedbackDeviceType {
  mobile('MOBILE'),
  tablet('TABLET'),
  desktop('DESKTOP');

  const FeedbackDeviceType(this.apiValue);

  final String apiValue;

  static FeedbackDeviceType? fromApiValue(Object? value) {
    for (final FeedbackDeviceType type in values) {
      if (type.apiValue == value) {
        return type;
      }
    }
    return null;
  }
}

/// Client platforms the app reports, as stored in `client_platform`.
const List<String> feedbackPlatforms = <String>[
  'web',
  'android',
  'ios',
  'windows',
  'macos',
  'linux',
];

/// Message bounds enforced by `POST /api/v1/feedback`.
const int feedbackMessageMinLength = 3;
const int feedbackMessageMaxLength = 5000;

/// Where, and on what device, feedback was raised.
///
/// Identity, tenant, facility, subscription, and role are resolved by the
/// server from the session; they are never sent from the client.
final class FeedbackContext {
  const FeedbackContext({
    this.routePath,
    this.routeName,
    this.pageUrl,
    this.platform,
    this.deviceType,
    this.appEnvironment,
    this.locale,
    this.timezone,
    this.utcOffsetMinutes,
    this.breakpoint,
    this.themeMode,
    this.textScale,
    this.connectivity,
    this.sessionStatus,
    this.orientation,
    this.viewportWidth,
    this.viewportHeight,
    this.devicePixelRatio,
    this.screenWidth,
    this.screenHeight,
  });

  /// Router location with credentials redacted, e.g. `/patients?tab=registry`.
  final String? routePath;
  final String? routeName;

  /// Browser address with credentials redacted; web only.
  final String? pageUrl;
  final String? platform;

  /// Size class of the app window when feedback was opened.
  final FeedbackDeviceType? deviceType;
  final String? appEnvironment;
  final String? locale;
  final String? timezone;
  final int? utcOffsetMinutes;
  final String? breakpoint;
  final String? themeMode;
  final double? textScale;
  final String? connectivity;
  final String? sessionStatus;
  final String? orientation;

  /// App window size in logical pixels.
  final double? viewportWidth;
  final double? viewportHeight;
  final double? devicePixelRatio;

  /// Whole display size in logical pixels; larger than the viewport when the
  /// app runs in a resized window.
  final double? screenWidth;
  final double? screenHeight;
}

final class FeedbackSubmission {
  const FeedbackSubmission({
    required this.category,
    required this.message,
    required this.context,
    required this.submittedAt,
  });

  final FeedbackCategory category;
  final String message;
  final FeedbackContext context;

  /// Device clock at submission; the server records its own time as well.
  final DateTime submittedAt;
}

final class FeedbackReceipt {
  const FeedbackReceipt({
    required this.submitterType,
    this.referenceId,
    this.submittedAt,
  });

  /// Human-friendly feedback id (`FBK…`) to quote in follow-up.
  final String? referenceId;
  final FeedbackSubmitterType submitterType;
  final DateTime? submittedAt;
}

/// A stored feedback record as listed for platform owners and admins.
final class FeedbackRecord {
  const FeedbackRecord({
    required this.referenceId,
    required this.category,
    required this.submitterType,
    required this.messagePreview,
    this.submittedAt,
    this.userEmail,
    this.userName,
    this.tenantName,
    this.facilityName,
    this.routePath,
    this.deviceType,
    this.platform,
  });

  /// Human-friendly feedback id (`FBK…`); also the deletion key.
  final String referenceId;
  final FeedbackCategory category;
  final FeedbackSubmitterType submitterType;

  /// The start of the message; the API sends at most a few hundred characters.
  final String messagePreview;
  final DateTime? submittedAt;
  final String? userEmail;
  final String? userName;
  final String? tenantName;
  final String? facilityName;
  final String? routePath;
  final FeedbackDeviceType? deviceType;
  final String? platform;
}

/// Narrows stored feedback while browsing or deleting it.
///
/// Submission dates are local calendar days; [submittedTo] includes the whole
/// day.
final class FeedbackFilters {
  const FeedbackFilters({
    this.search = '',
    this.categories = const <FeedbackCategory>{},
    this.submitterType,
    this.deviceTypes = const <FeedbackDeviceType>{},
    this.platforms = const <String>{},
    this.submittedFrom,
    this.submittedTo,
  });

  static const FeedbackFilters none = FeedbackFilters();

  final String search;
  final Set<FeedbackCategory> categories;
  final FeedbackSubmitterType? submitterType;
  final Set<FeedbackDeviceType> deviceTypes;
  final Set<String> platforms;
  final DateTime? submittedFrom;
  final DateTime? submittedTo;

  /// Whether a filter other than [search] narrows the list.
  bool get hasActiveFilters {
    return categories.isNotEmpty ||
        submitterType != null ||
        deviceTypes.isNotEmpty ||
        platforms.isNotEmpty ||
        submittedFrom != null ||
        submittedTo != null;
  }

  FeedbackFilters withSearch(String value) {
    return FeedbackFilters(
      search: value.trim(),
      categories: categories,
      submitterType: submitterType,
      deviceTypes: deviceTypes,
      platforms: platforms,
      submittedFrom: submittedFrom,
      submittedTo: submittedTo,
    );
  }
}

final class FeedbackDeleteResult {
  const FeedbackDeleteResult({required this.deletedCount, this.deletedAt});

  final int deletedCount;
  final DateTime? deletedAt;
}
