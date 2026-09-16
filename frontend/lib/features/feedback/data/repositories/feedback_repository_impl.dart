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

    return client.post<FeedbackReceipt>(
      ApiEndpoints.collection(HmsApiResource.feedback),
      data: feedbackSubmissionPayload(submission),
      decoder: (Object? data) =>
          ApiResponseEnvelope.decodeData<FeedbackReceipt>(
            data,
            decoder: _decodeReceipt,
          ),
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
    'context': contextPayload,
  };
}

/// Filters for `DELETE /api/v1/feedback` with `all_matching`: lists stay lists,
/// and submission dates become the UTC bounds of whole local days.
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
    if (filters.platforms.isNotEmpty)
      'platform': _sortedValues(filters.platforms),
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
  return FeedbackRecord(
    referenceId:
        _readText(json['human_friendly_id']) ?? _readText(json['id']) ?? '',
    category: FeedbackCategory.fromApiValue(json['category']),
    submitterType: FeedbackSubmitterType.fromApiValue(json['submitter_type']),
    messagePreview: _readText(json['message_preview']) ?? '',
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

FeedbackDeleteResult _decodeDeleteResult(Object? data) {
  final Map<String, Object?> json = _asJsonMap(data);
  return FeedbackDeleteResult(
    deletedCount: _readInt(json['deleted_count']),
    deletedAt: _readDate(json['deleted_at']),
  );
}

Uint8List _decodeBytes(Object? data) {
  if (data is Uint8List) {
    return data;
  }
  if (data is List) {
    return Uint8List.fromList(data.whereType<int>().toList(growable: false));
  }
  throw const FormatException('Expected spreadsheet bytes.');
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
