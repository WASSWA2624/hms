import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/network/api_client.dart';
import 'package:hosspi_hms/core/network/api_endpoints.dart';
import 'package:hosspi_hms/core/network/api_response.dart';
import 'package:hosspi_hms/core/network/network_providers.dart';
import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';
import 'package:hosspi_hms/features/feedback/domain/repositories/feedback_repository.dart';
import 'package:hosspi_hms/shared/data/app_pagination.dart';

final feedbackRepositoryProvider = Provider<FeedbackRepository>((ref) {
  return FeedbackRepositoryImpl(
    apiClient: ref.watch(apiClientProvider),
    publicApiClient: ref.watch(publicApiClientProvider),
  );
});

final class FeedbackRepositoryImpl implements FeedbackRepository {
  const FeedbackRepositoryImpl({
    required ApiClient apiClient,
    required ApiClient publicApiClient,
  }) : _apiClient = apiClient,
       _publicApiClient = publicApiClient;

  final ApiClient _apiClient;
  final ApiClient _publicApiClient;

  @override
  Future<Result<FeedbackReceipt>> submitFeedback(
    FeedbackSubmission submission, {
    required bool signedIn,
  }) {
    // The public client sends no session, so feedback from a sign-in screen
    // can never trigger a token refresh or a logout.
    final ApiClient client = signedIn ? _apiClient : _publicApiClient;
    final Map<String, Object?> payload = feedbackSubmissionPayload(submission);

    return client.post<FeedbackReceipt>(
      ApiEndpoints.collection(HmsApiResource.feedback),
      // Pictures travel as multipart, with the same JSON body in `payload`;
      // feedback without them stays a plain JSON request.
      data: submission.screenshots.isEmpty
          ? payload
          : feedbackSubmissionFormData(payload, submission.screenshots),
      decoder: (Object? data) =>
          ApiResponseEnvelope.decodeData<FeedbackReceipt>(
            data,
            decoder: _decodeReceipt,
          ),
    );
  }

  @override
  Future<Result<List<FeedbackStoredScreenshot>>> fetchFeedbackScreenshots({
    required String referenceId,
  }) {
    return _apiClient.get<List<FeedbackStoredScreenshot>>(
      ApiEndpoints.apiV1(<String>[
        HmsApiResource.feedback.path,
        referenceId,
        'screenshots',
      ]),
      decoder: (Object? data) =>
          ApiResponseEnvelope.decodeData<List<FeedbackStoredScreenshot>>(
            data,
            decoder: _decodeStoredScreenshots,
          ),
    );
  }

  @override
  Future<Result<Uint8List>> fetchFeedbackScreenshotImage({
    required String referenceId,
    required String screenshotId,
  }) {
    return _apiClient.get<Uint8List>(
      ApiEndpoints.apiV1(<String>[
        HmsApiResource.feedback.path,
        referenceId,
        'screenshots',
        screenshotId,
      ]),
      options: Options(responseType: ResponseType.bytes),
      decoder: _decodeBytes,
    );
  }

  @override
  Future<Result<AppPage<FeedbackRecord>>> fetchFeedbackPage({
    required FeedbackFilters filters,
    required AppPageRequest request,
    FeedbackSort sort = FeedbackSort.newestFirst,
  }) {
    return _apiClient.get<AppPage<FeedbackRecord>>(
      ApiEndpoints.apiV1(
        <String>[HmsApiResource.feedback.path],
        queryParameters: <String, String>{
          'page': '${request.pageIndex + 1}',
          'limit': '${request.pageSize}',
          'sort_by': sort.field.apiValue,
          'order': sort.apiOrder,
          ...feedbackFilterQueryParameters(filters),
        },
      ),
      decoder: (Object? data) => _decodeRecordPage(data, request),
    );
  }

  @override
  Future<Result<FeedbackFacets>> fetchFeedbackFacets({
    required FeedbackFilters filters,
  }) {
    return _apiClient.get<FeedbackFacets>(
      ApiEndpoints.apiV1(<String>[
        HmsApiResource.feedback.path,
        'facets',
      ], queryParameters: feedbackFilterQueryParameters(filters)),
      decoder: (Object? data) => ApiResponseEnvelope.decodeData<FeedbackFacets>(
        data,
        decoder: _decodeFacets,
      ),
    );
  }

  @override
  Future<Result<Uint8List>> downloadFeedbackExport({
    required int utcOffsetMinutes,
    Set<String> referenceIds = const <String>{},
    FeedbackFilters filters = FeedbackFilters.none,
  }) {
    // The picked ids are too many for a URL, so the export is posted. Ids win
    // over filters: the user picked exactly those records.
    return _apiClient.post<Uint8List>(
      ApiEndpoints.apiV1(<String>[HmsApiResource.feedback.path, 'export']),
      data: <String, Object?>{
        'utc_offset_minutes': utcOffsetMinutes,
        if (referenceIds.isNotEmpty)
          'human_friendly_ids': _sortedValues(referenceIds)
        else
          ...feedbackFilterBody(filters),
      },
      options: Options(responseType: ResponseType.bytes),
      decoder: _decodeBytes,
    );
  }

  @override
  Future<Result<FeedbackDeleteResult>> deleteFeedback({
    required Set<String> referenceIds,
  }) {
    return _delete(<String, Object?>{
      'human_friendly_ids': referenceIds.toList(growable: false),
    });
  }

  @override
  Future<Result<FeedbackDeleteResult>> deleteMatchingFeedback({
    required FeedbackFilters filters,
  }) {
    return _delete(<String, Object?>{
      'all_matching': true,
      'filters': feedbackFilterBody(filters),
    });
  }

  Future<Result<FeedbackDeleteResult>> _delete(Map<String, Object?> target) {
    return _apiClient.delete<FeedbackDeleteResult>(
      ApiEndpoints.collection(HmsApiResource.feedback),
      // The API requires explicit confirmation before deleting.
      data: <String, Object?>{'confirm': true, ...target},
      decoder: (Object? data) =>
          ApiResponseEnvelope.decodeData<FeedbackDeleteResult>(
            data,
            decoder: _decodeDeleteResult,
          ),
    );
  }
}

/// Body for `POST /api/v1/feedback`.
///
/// Context values are capped to the API's limits, so an unusually long URL
/// cannot cause a validation error that loses the user's feedback.
Map<String, Object?> feedbackSubmissionPayload(FeedbackSubmission submission) {
  final FeedbackContext context = submission.context;
  final double? viewportWidth = context.viewportWidth;
  final double? viewportHeight = context.viewportHeight;
  final double? screenWidth = context.screenWidth;
  final double? screenHeight = context.screenHeight;
  final DateTime submittedAtUtc = DateTime.fromMillisecondsSinceEpoch(
    submission.submittedAt.millisecondsSinceEpoch,
    isUtc: true,
  );

  final Map<String, Object?> contextPayload = <String, Object?>{
    'route_path': _capText(context.routePath, 512),
    'route_name': _capText(context.routeName, 120),
    'page_url': _capText(context.pageUrl, 2048),
    'platform': _capText(context.platform, 40),
    'device_type': context.deviceType?.apiValue,
    'app_version': _capText(context.appVersion, 64),
    'app_environment': _capText(context.appEnvironment, 40),
    'locale': _capText(context.locale, 35),
    'timezone': _capText(context.timezone, 64),
    'utc_offset_minutes': context.utcOffsetMinutes,
    'breakpoint': _capText(context.breakpoint, 16),
    'theme_mode': _capText(context.themeMode, 16),
    'text_scale': context.textScale,
    'connectivity': _capText(context.connectivity, 16),
    'session_status': _capText(context.sessionStatus, 24),
    'orientation': _capText(context.orientation, 16),
    if (viewportWidth != null && viewportHeight != null)
      'viewport': <String, Object?>{
        'width': viewportWidth,
        'height': viewportHeight,
        if (context.devicePixelRatio != null)
          'device_pixel_ratio': context.devicePixelRatio,
      },
    if (screenWidth != null && screenHeight != null)
      'screen': <String, Object?>{'width': screenWidth, 'height': screenHeight},
    'client_submitted_at': submittedAtUtc.toIso8601String(),
  }..removeWhere((String _, Object? value) => value == null);

  return <String, Object?>{
    'category': submission.category.apiValue,
    'message': submission.message.trim(),
    'scope': submission.scope.apiValue,
    if (submission.scope == FeedbackScope.screens)
      'scope_screens': <Map<String, Object?>>[
        for (final FeedbackScreenReference screen in submission.screens)
          if (screen.isAddressable)
            <String, Object?>{
              if (screen.routeName != null)
                'route_name': _capText(screen.routeName, 120),
              if (screen.routePath != null)
                'route_path': _capText(screen.routePath, 512),
              if (screen.screenTitle != null)
                'screen_title': _capText(screen.screenTitle, 255),
            },
      ],
    if (submission.screenshots.isNotEmpty)
      'screenshots': <Map<String, Object?>>[
        for (final FeedbackScreenshot screenshot in submission.screenshots)
          <String, Object?>{
            if (screenshot.width != null) 'width': screenshot.width,
            if (screenshot.height != null) 'height': screenshot.height,
            if (_capText(screenshot.caption, 255) case final String caption)
              'caption': caption,
            if (_capText(screenshot.screen.routeName, 120)
                case final String routeName)
              'route_name': routeName,
            if (_capText(screenshot.screen.routePath, 512)
                case final String routePath)
              'route_path': routePath,
            if (_capText(screenshot.screen.screenTitle, 255)
                case final String screenTitle)
              'screen_title': screenTitle,
            if (_screenshotContextPayload(screenshot.context)
                case final Map<String, Object?> context)
              'client_context': context,
            'captured_at': screenshot.capturedAt.toUtc().toIso8601String(),
          },
      ],
    'context': contextPayload,
  };
}

/// The window one shot was taken in, or null when the app could not read it.
Map<String, Object?>? _screenshotContextPayload(
  FeedbackScreenshotContext? context,
) {
  if (context == null || context.isEmpty) {
    return null;
  }
  return <String, Object?>{
    if (context.viewportWidth != null) 'viewport_width': context.viewportWidth,
    if (context.viewportHeight != null)
      'viewport_height': context.viewportHeight,
    if (context.devicePixelRatio != null)
      'device_pixel_ratio': context.devicePixelRatio,
    if (_capText(context.orientation, 16) case final String orientation)
      'orientation': orientation,
    if (_capText(context.themeMode, 16) case final String themeMode)
      'theme_mode': themeMode,
    if (_capText(context.breakpoint, 16) case final String breakpoint)
      'breakpoint': breakpoint,
  };
}

/// The multipart form for a submission with pictures.
///
/// The whole JSON body rides in `payload`, so the API validates one shape
/// however the request arrived, and the files follow in capture order: the
/// server pairs each with its metadata by position.
FormData feedbackSubmissionFormData(
  Map<String, Object?> payload,
  List<FeedbackScreenshot> screenshots,
) {
  final FormData formData = FormData();
  formData.fields.add(MapEntry<String, String>('payload', jsonEncode(payload)));
  for (int index = 0; index < screenshots.length; index += 1) {
    final FeedbackScreenshot screenshot = screenshots[index];
    formData.files.add(
      MapEntry<String, MultipartFile>(
        'screenshots',
        MultipartFile.fromBytes(
          screenshot.bytes,
          filename: 'screenshot-${index + 1}.jpg',
          contentType: DioMediaType.parse(screenshot.contentType),
        ),
      ),
    );
  }
  return formData;
}

/// Filters as a JSON body, for exporting and for `DELETE /api/v1/feedback`
/// with `all_matching`: lists stay lists, and submission dates become the UTC
/// bounds of whole local days.
Map<String, Object?> feedbackFilterBody(FeedbackFilters filters) {
  final String search = filters.search.trim();
  final FeedbackSubmitterType? submitterType = filters.submitterType;
  final DateTime? from = filters.submittedFrom;
  final DateTime? to = filters.submittedTo;

  return <String, Object?>{
    if (search.isNotEmpty) 'search': search,
    if (filters.categories.isNotEmpty)
      'category': _sortedValues(
        filters.categories.map((FeedbackCategory value) => value.apiValue),
      ),
    if (submitterType != null) 'submitter_type': submitterType.apiValue,
    if (filters.deviceTypes.isNotEmpty)
      'device_type': _sortedValues(
        filters.deviceTypes.map((FeedbackDeviceType value) => value.apiValue),
      ),
    for (final FeedbackFilterDimension dimension
        in FeedbackFilterDimension.values)
      if (filters.valuesFor(dimension).isNotEmpty)
        dimension.apiKey: _sortedValues(filters.valuesFor(dimension)),
    if (from != null)
      'from': _utcIso(DateTime(from.year, from.month, from.day)),
    if (to != null)
      'to': _utcIso(DateTime(to.year, to.month, to.day, 23, 59, 59, 999)),
  };
}

/// The same filters as query parameters, with multi-value filters
/// comma-separated.
Map<String, String> feedbackFilterQueryParameters(FeedbackFilters filters) {
  return feedbackFilterBody(filters).map(
    (String key, Object? value) => MapEntry<String, String>(
      key,
      value is List ? value.join(',') : '$value',
    ),
  );
}

List<String> _sortedValues(Iterable<String> values) {
  return values.toSet().toList()..sort();
}

String _utcIso(DateTime local) {
  return DateTime.fromMillisecondsSinceEpoch(
    local.millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();
}

String? _capText(String? value, int maxLength) {
  final String? text = value?.trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text.length > maxLength ? text.substring(0, maxLength) : text;
}

FeedbackReceipt _decodeReceipt(Object? data) {
  final Map<String, Object?> json = _asJsonMap(data);
  return FeedbackReceipt(
    referenceId: _readText(json['human_friendly_id']) ?? _readText(json['id']),
    submitterType: FeedbackSubmitterType.fromApiValue(json['submitter_type']),
    submittedAt: _readDate(json['submitted_at']),
    screenshotCount: _readInt(json['screenshot_count']),
    screenshotsDropped: _readInt(json['screenshots_dropped']),
  );
}

List<FeedbackStoredScreenshot> _decodeStoredScreenshots(Object? data) {
  final Map<String, Object?> json = _asJsonMap(data);
  final Object? rows = json['items'];
  if (rows is! List) {
    return const <FeedbackStoredScreenshot>[];
  }
  return <FeedbackStoredScreenshot>[
    for (final Object? row in rows)
      if (row is Map) _decodeStoredScreenshot(_asJsonMap(row)),
  ];
}

FeedbackStoredScreenshot _decodeStoredScreenshot(Map<String, Object?> json) {
  return FeedbackStoredScreenshot(
    id: _readText(json['id']) ?? '',
    sequence: _readInt(json['sequence']),
    contentType: _readText(json['content_type']) ?? 'image/jpeg',
    byteSize: _readInt(json['byte_size']),
    fileName: _readText(json['file_name']) ?? '',
    width: _readOptionalInt(json['width']),
    height: _readOptionalInt(json['height']),
    caption: _readText(json['caption']),
    screen: _decodeScreen(json),
    capturedAt: _readDate(json['captured_at'])?.toLocal(),
  );
}

FeedbackScreenReference _decodeScreen(Map<String, Object?> json) {
  return FeedbackScreenReference(
    routeName: _readText(json['route_name']),
    routePath: _readText(json['route_path']),
    screenTitle: _readText(json['screen_title']),
  );
}

AppPage<FeedbackRecord> _decodeRecordPage(
  Object? data,
  AppPageRequest request,
) {
  final Map<String, Object?> response = _asJsonMap(data);
  final Object? rows = response['data'];
  final List<FeedbackRecord> items = rows is List
      ? rows
            .map((Object? row) => _decodeRecord(_asJsonMap(row)))
            .toList(growable: false)
      : const <FeedbackRecord>[];
  final Object? pagination = response['pagination'];
  final Object? total = pagination is Map ? pagination['total'] : null;

  return AppPage<FeedbackRecord>(
    items: items,
    request: request,
    totalItemCount: total == null ? null : _readInt(total),
  );
}

FeedbackRecord _decodeRecord(Map<String, Object?> json) {
  final Object? scopeScreens = json['scope_screens'];

  return FeedbackRecord(
    referenceId:
        _readText(json['human_friendly_id']) ?? _readText(json['id']) ?? '',
    category: FeedbackCategory.fromApiValue(json['category']),
    submitterType: FeedbackSubmitterType.fromApiValue(json['submitter_type']),
    messagePreview: _readText(json['message_preview']) ?? '',
    scope: FeedbackScope.fromApiValue(json['scope']),
    scopeScreens: scopeScreens is! List
        ? const <FeedbackScreenReference>[]
        : <FeedbackScreenReference>[
            for (final Object? row in scopeScreens)
              if (row is Map) _decodeScreen(_asJsonMap(row)),
          ],
    screenshotCount: _readInt(json['screenshot_count']),
    submittedAt: _readDate(json['submitted_at'])?.toLocal(),
    userEmail: _readText(json['user_email']),
    userName: _readText(json['user_name']),
    tenantName: _readText(json['tenant_name']),
    facilityName: _readText(json['facility_name']),
    routePath: _readText(json['route_path']),
    deviceType: FeedbackDeviceType.fromApiValue(json['device_type']),
    platform: _readText(json['client_platform']),
  );
}

FeedbackFacets _decodeFacets(Object? data) {
  final Map<String, Object?> json = _asJsonMap(data);
  final Object? rawFacets = json['facets'];
  final Map<String, Object?> facets = rawFacets == null
      ? const <String, Object?>{}
      : _asJsonMap(rawFacets);

  List<FeedbackFacetValue> valuesOf(String key) {
    final Object? rows = facets[key];
    if (rows is! List) {
      return const <FeedbackFacetValue>[];
    }
    return <FeedbackFacetValue>[
      for (final Object? row in rows)
        if (row is Map)
          if (_readText(row['value']) case final String value)
            FeedbackFacetValue(
              value: value,
              label: _readText(row['label']),
              count: _readInt(row['count']),
            ),
    ];
  }

  return FeedbackFacets(
    total: _readInt(json['total']),
    categories: valuesOf('category'),
    submitterTypes: valuesOf('submitter_type'),
    deviceTypes: valuesOf('device_type'),
    values: <FeedbackFilterDimension, List<FeedbackFacetValue>>{
      for (final FeedbackFilterDimension dimension
          in FeedbackFilterDimension.values)
        dimension: valuesOf(dimension.apiKey),
    },
  );
}

FeedbackDeleteResult _decodeDeleteResult(Object? data) {
  final Map<String, Object?> json = _asJsonMap(data);
  return FeedbackDeleteResult(
    deletedCount: _readInt(json['deleted_count']),
    deletedAt: _readDate(json['deleted_at']),
    deletedScreenshotCount: _readInt(json['deleted_screenshot_count']),
  );
}

Uint8List _decodeBytes(Object? data) {
  if (data is Uint8List) {
    return data;
  }
  if (data is List) {
    return Uint8List.fromList(data.whereType<int>().toList(growable: false));
  }
  throw const FormatException('Expected file bytes.');
}

Map<String, Object?> _asJsonMap(Object? data) {
  if (data is Map<String, Object?>) {
    return data;
  }
  if (data is Map) {
    return data.map(
      (Object? key, Object? value) => MapEntry<String, Object?>('$key', value),
    );
  }
  throw const FormatException('Expected a feedback response object.');
}

String? _readText(Object? value) {
  final String text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

int? _readOptionalInt(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}

int _readInt(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _readDate(Object? value) {
  final String? text = _readText(value);
  return text == null ? null : DateTime.tryParse(text);
}
