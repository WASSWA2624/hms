import 'dart:typed_data';

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

/// What a report applies to. [apiValue] matches the API enum.
enum FeedbackScope {
  /// The screen the feedback was raised from.
  screen('SCREEN'),

  /// Not confined to one screen.
  app('APP'),

  /// The screens the reporter picked; see [FeedbackSubmission.screens].
  screens('SCREENS');

  const FeedbackScope(this.apiValue);

  final String apiValue;

  static FeedbackScope fromApiValue(Object? value) {
    for (final FeedbackScope scope in values) {
      if (scope.apiValue == value) {
        return scope;
      }
    }
    return screen;
  }
}

/// Message bounds enforced by `POST /api/v1/feedback`.
const int feedbackMessageMinLength = 3;
const int feedbackMessageMaxLength = 5000;

/// Screenshot limits enforced by `POST /api/v1/feedback`. The app applies the
/// same ones before uploading, so a reporter is told while they can still fix
/// it. Change these with the server's own constants.
const int feedbackMaxScreenshots = 10;
const int feedbackMaxAnonymousScreenshots = 3;
const int feedbackScreenshotMaxBytes = 2 * 1024 * 1024;
const int feedbackScreenshotsMaxTotalBytes = 12 * 1024 * 1024;

/// Longest edge a capture is scaled down to before it is encoded.
const double feedbackScreenshotMaxEdge = 1600;

/// How many shots a submitter may attach.
int feedbackScreenshotLimit({required bool signedIn}) {
  return signedIn ? feedbackMaxScreenshots : feedbackMaxAnonymousScreenshots;
}

/// A screen of the app, as the router and the navigation name it.
final class FeedbackScreenReference {
  const FeedbackScreenReference({
    this.routeName,
    this.routePath,
    this.screenTitle,
  });

  final String? routeName;
  final String? routePath;

  /// What the navigation calls the screen, e.g. `Outpatients`.
  final String? screenTitle;

  /// Whether the API would accept this screen: it needs one of the two.
  bool get isAddressable =>
      (routeName?.trim().isNotEmpty ?? false) ||
      (routePath?.trim().isNotEmpty ?? false);

  /// Screens are the same screen when they name the same route.
  String get key => '${routeName ?? ''}|${routePath ?? ''}';

  String get label {
    final String title = screenTitle?.trim() ?? '';
    if (title.isNotEmpty) {
      return title;
    }
    final String name = routeName?.trim() ?? '';
    return name.isNotEmpty ? name : (routePath?.trim() ?? '');
  }

  @override
  bool operator ==(Object other) =>
      other is FeedbackScreenReference && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// The app as it was when one shot was taken, which can differ from the
/// feedback's own context: a reporter rotates the device, switches theme, or
/// resizes the window between pictures.
final class FeedbackScreenshotContext {
  const FeedbackScreenshotContext({
    this.viewportWidth,
    this.viewportHeight,
    this.devicePixelRatio,
    this.orientation,
    this.themeMode,
    this.breakpoint,
  });

  final double? viewportWidth;
  final double? viewportHeight;
  final double? devicePixelRatio;
  final String? orientation;
  final String? themeMode;
  final String? breakpoint;

  bool get isEmpty =>
      viewportWidth == null &&
      viewportHeight == null &&
      devicePixelRatio == null &&
      orientation == null &&
      themeMode == null &&
      breakpoint == null;
}

/// One screenshot a reporter attached, held in memory until it is submitted.
final class FeedbackScreenshot {
  const FeedbackScreenshot({
    required this.bytes,
    required this.contentType,
    required this.screen,
    required this.capturedAt,
    this.width,
    this.height,
    this.caption,
    this.context,
  });

  /// The encoded image, already scaled down for upload.
  final Uint8List bytes;
  final String contentType;

  /// The screen this shot was taken on, which need not be the screen the
  /// feedback was raised from.
  final FeedbackScreenReference screen;
  final DateTime capturedAt;
  final int? width;
  final int? height;
  final String? caption;

  /// The window this shot was taken in.
  final FeedbackScreenshotContext? context;

  int get byteSize => bytes.length;

  FeedbackScreenshot copyWith({
    Uint8List? bytes,
    int? width,
    int? height,
    String? caption,
  }) {
    return FeedbackScreenshot(
      bytes: bytes ?? this.bytes,
      contentType: contentType,
      screen: screen,
      capturedAt: capturedAt,
      width: width ?? this.width,
      height: height ?? this.height,
      caption: caption ?? this.caption,
      context: context,
    );
  }
}

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
    this.appVersion,
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

  /// The running build as `version+build`, e.g. `1.4.0+12`.
  final String? appVersion;
  final String? appEnvironment;
  final String? locale;

  /// IANA zone id (`Africa/Kampala`), else the UTC offset (`UTC+03:00`).
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
    this.scope = FeedbackScope.screen,
    this.screens = const <FeedbackScreenReference>[],
    this.screenshots = const <FeedbackScreenshot>[],
  });

  final FeedbackCategory category;
  final String message;
  final FeedbackContext context;

  /// Device clock at submission; the server records its own time as well.
  final DateTime submittedAt;

  /// What the feedback applies to.
  final FeedbackScope scope;

  /// The screens picked for [FeedbackScope.screens]; ignored otherwise.
  final List<FeedbackScreenReference> screens;

  /// Attached shots, in capture order.
  final List<FeedbackScreenshot> screenshots;
}

final class FeedbackReceipt {
  const FeedbackReceipt({
    required this.submitterType,
    this.referenceId,
    this.submittedAt,
    this.screenshotCount = 0,
    this.screenshotsDropped = 0,
  });

  /// Human-friendly feedback id (`FBK…`) to quote in follow-up.
  final String? referenceId;
  final FeedbackSubmitterType submitterType;
  final DateTime? submittedAt;

  /// Shots stored with the feedback.
  final int screenshotCount;

  /// Shots that were sent but could not be stored, so the app can say so
  /// rather than imply every screen arrived.
  final int screenshotsDropped;
}

/// A stored feedback record as listed for platform owners and admins.
final class FeedbackRecord {
  const FeedbackRecord({
    required this.referenceId,
    required this.category,
    required this.submitterType,
    required this.messagePreview,
    this.scope = FeedbackScope.screen,
    this.scopeScreens = const <FeedbackScreenReference>[],
    this.screenshotCount = 0,
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

  /// What the report applies to, and the screens it named.
  final FeedbackScope scope;
  final List<FeedbackScreenReference> scopeScreens;

  /// Images attached to the record.
  final int screenshotCount;
  final DateTime? submittedAt;
  final String? userEmail;
  final String? userName;
  final String? tenantName;
  final String? facilityName;
  final String? routePath;
  final FeedbackDeviceType? deviceType;
  final String? platform;
}

/// A column stored feedback can be ordered by. [apiValue] matches the API's
/// `sort_by` values.
enum FeedbackSortField {
  submittedAt('submitted_at'),
  reference('human_friendly_id'),
  category('category'),
  submitterType('submitter_type'),
  submitter('user_email'),
  tenant('tenant_name'),
  facility('facility_name'),
  deviceType('device_type'),
  platform('client_platform'),
  routePath('route_path');

  const FeedbackSortField(this.apiValue);

  final String apiValue;
}

/// How a page of stored feedback is ordered.
final class FeedbackSort {
  const FeedbackSort({required this.field, this.ascending = false});

  /// The API's own default: the most recent feedback first.
  static const FeedbackSort newestFirst = FeedbackSort(
    field: FeedbackSortField.submittedAt,
  );

  final FeedbackSortField field;
  final bool ascending;

  String get apiOrder => ascending ? 'asc' : 'desc';

  @override
  bool operator ==(Object other) {
    return other is FeedbackSort &&
        other.field == field &&
        other.ascending == ascending;
  }

  @override
  int get hashCode => Object.hash(field, ascending);
}

/// A stored value feedback can be filtered by, beyond its category,
/// submitter, device type, and submission date. [apiKey] is the filter's query
/// and facet key.
enum FeedbackFilterDimension {
  // Who
  tenant('tenant_id'),
  facility('facility_id'),
  role('role'),
  planTier('plan_tier'),
  subscriptionStatus('subscription_status'),
  // Where
  routeName('route_name'),
  appliesTo('applies_to'),
  appliesToRoute('applies_to_route'),
  appEnvironment('app_environment'),
  appVersion('app_version'),
  // Device
  platform('platform'),
  breakpoint('breakpoint'),
  orientation('orientation'),
  theme('theme'),
  locale('locale'),
  connectivity('connectivity');

  const FeedbackFilterDimension(this.apiKey);

  final String apiKey;
}

/// Narrows stored feedback while browsing, downloading, or deleting it.
///
/// Submission dates are local calendar days; [submittedTo] includes the whole
/// day. [values] holds the stored values picked per dimension; a record
/// matches when it holds any picked value of every narrowed dimension.
final class FeedbackFilters {
  const FeedbackFilters({
    this.search = '',
    this.categories = const <FeedbackCategory>{},
    this.submitterType,
    this.deviceTypes = const <FeedbackDeviceType>{},
    this.values = const <FeedbackFilterDimension, Set<String>>{},
    this.submittedFrom,
    this.submittedTo,
  });

  static const FeedbackFilters none = FeedbackFilters();

  final String search;
  final Set<FeedbackCategory> categories;
  final FeedbackSubmitterType? submitterType;
  final Set<FeedbackDeviceType> deviceTypes;
  final Map<FeedbackFilterDimension, Set<String>> values;
  final DateTime? submittedFrom;
  final DateTime? submittedTo;

  Set<String> valuesFor(FeedbackFilterDimension dimension) {
    return values[dimension] ?? const <String>{};
  }

  /// Whether a filter other than [search] narrows the list.
  bool get hasActiveFilters {
    return categories.isNotEmpty ||
        submitterType != null ||
        deviceTypes.isNotEmpty ||
        values.values.any((Set<String> picked) => picked.isNotEmpty) ||
        submittedFrom != null ||
        submittedTo != null;
  }

  FeedbackFilters withSearch(String value) {
    return FeedbackFilters(
      search: value.trim(),
      categories: categories,
      submitterType: submitterType,
      deviceTypes: deviceTypes,
      values: values,
      submittedFrom: submittedFrom,
      submittedTo: submittedTo,
    );
  }
}

/// One stored value of a filter dimension and how many records hold it.
final class FeedbackFacetValue {
  const FeedbackFacetValue({
    required this.value,
    required this.count,
    this.label,
  });

  /// As stored and as sent back in a filter, e.g. `TEN-9322E26AFD` or `xl`.
  final String value;

  /// The stored name beside a public id, e.g. the tenant or facility name.
  final String? label;
  final int count;
}

/// Filter choices counted from stored feedback. Each dimension's counts apply
/// every other active filter but not its own, so values that could still be
/// added stay listed.
final class FeedbackFacets {
  const FeedbackFacets({
    required this.total,
    this.categories = const <FeedbackFacetValue>[],
    this.submitterTypes = const <FeedbackFacetValue>[],
    this.deviceTypes = const <FeedbackFacetValue>[],
    this.values = const <FeedbackFilterDimension, List<FeedbackFacetValue>>{},
  });

  /// Records matching every active filter.
  final int total;
  final List<FeedbackFacetValue> categories;
  final List<FeedbackFacetValue> submitterTypes;
  final List<FeedbackFacetValue> deviceTypes;
  final Map<FeedbackFilterDimension, List<FeedbackFacetValue>> values;

  List<FeedbackFacetValue> valuesFor(FeedbackFilterDimension dimension) {
    return values[dimension] ?? const <FeedbackFacetValue>[];
  }
}

final class FeedbackDeleteResult {
  const FeedbackDeleteResult({
    required this.deletedCount,
    this.deletedAt,
    this.deletedScreenshotCount = 0,
  });

  final int deletedCount;
  final DateTime? deletedAt;

  /// Images removed with those records; they never outlive their feedback.
  final int deletedScreenshotCount;
}

/// A screenshot stored with a feedback record, as listed for review. The
/// bytes are fetched separately, one image at a time.
final class FeedbackStoredScreenshot {
  const FeedbackStoredScreenshot({
    required this.id,
    required this.sequence,
    required this.contentType,
    required this.byteSize,
    required this.fileName,
    this.width,
    this.height,
    this.caption,
    this.screen = const FeedbackScreenReference(),
    this.capturedAt,
  });

  final String id;
  final int sequence;
  final String contentType;
  final int byteSize;

  /// The name this image takes in a download archive, e.g. `FBK0000011-2.jpg`.
  final String fileName;
  final int? width;
  final int? height;
  final String? caption;
  final FeedbackScreenReference screen;
  final DateTime? capturedAt;
}
