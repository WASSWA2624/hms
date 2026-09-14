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
  Future<Result<FeedbackSummary>> fetchFeedbackSummary() {
    return _apiClient.get<FeedbackSummary>(
      ApiEndpoints.apiV1(<String>[HmsApiResource.feedback.path, 'summary']),
      decoder: (Object? data) =>
          ApiResponseEnvelope.decodeData<FeedbackSummary>(
            data,
            decoder: _decodeSummary,
          ),
    );
  }

  @override
  Future<Result<Uint8List>> downloadFeedbackExport({
    required int utcOffsetMinutes,
  }) {
    return _apiClient.get<Uint8List>(
      ApiEndpoints.apiV1(
        <String>[HmsApiResource.feedback.path, 'export'],
        queryParameters: <String, String>{
          'utc_offset_minutes': '$utcOffsetMinutes',
        },
      ),
      options: Options(responseType: ResponseType.bytes),
      decoder: _decodeBytes,
    );
  }

  @override
  Future<Result<FeedbackClearResult>> clearFeedback() {
    return _apiClient.delete<FeedbackClearResult>(
      ApiEndpoints.collection(HmsApiResource.feedback),
      // The API requires explicit confirmation before clearing.
      data: const <String, Object?>{'confirm': true},
      decoder: (Object? data) =>
          ApiResponseEnvelope.decodeData<FeedbackClearResult>(
            data,
            decoder: _decodeClearResult,
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
    referenceId: _readText(json['human_friendly_id']),
    submitterType: FeedbackSubmitterType.fromApiValue(json['submitter_type']),
    submittedAt: _readDate(json['submitted_at']),
  );
}

FeedbackSummary _decodeSummary(Object? data) {
  final Map<String, Object?> json = _asJsonMap(data);
  return FeedbackSummary(
    total: _readInt(json['total']),
    authenticated: _readInt(json['authenticated']),
    anonymous: _readInt(json['anonymous']),
    latestSubmittedAt: _readDate(json['latest_submitted_at']),
  );
}

FeedbackClearResult _decodeClearResult(Object? data) {
  final Map<String, Object?> json = _asJsonMap(data);
  return FeedbackClearResult(
    clearedCount: _readInt(json['cleared_count']),
    clearedAt: _readDate(json['cleared_at']),
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
