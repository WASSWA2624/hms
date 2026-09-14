/// Kind of feedback a user is giving. [apiValue] matches the API enum.
enum FeedbackCategory {
  general('GENERAL'),
  problem('PROBLEM'),
  complaint('COMPLAINT'),
  suggestion('SUGGESTION'),
  improvement('IMPROVEMENT');

  const FeedbackCategory(this.apiValue);

  final String apiValue;
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
}

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

final class FeedbackSummary {
  const FeedbackSummary({
    required this.total,
    required this.authenticated,
    required this.anonymous,
    this.latestSubmittedAt,
  });

  final int total;
  final int authenticated;
  final int anonymous;
  final DateTime? latestSubmittedAt;
}

final class FeedbackClearResult {
  const FeedbackClearResult({required this.clearedCount, this.clearedAt});

  final int clearedCount;
  final DateTime? clearedAt;
}
