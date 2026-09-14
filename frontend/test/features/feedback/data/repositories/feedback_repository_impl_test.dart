import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hosspi_hms/core/network/api_client.dart';
import 'package:hosspi_hms/core/network/api_result.dart';
import 'package:hosspi_hms/features/feedback/data/repositories/feedback_repository_impl.dart';
import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';

typedef _RecordedCall = ({
  String method,
  Uri endpoint,
  Object? data,
  Options? options,
});

final class _RecordingApiClient implements ApiClient {
  _RecordingApiClient([this.response]);

  final Object? response;
  final List<_RecordedCall> calls = <_RecordedCall>[];

  @override
  Uri get baseUri => Uri.parse('http://localhost:3000');

  @override
  Future<ApiResult<T>> request<T>({
    required String method,
    required Uri endpoint,
    required ApiResponseDecoder<T> decoder,
    Object? data,
    Map<String, Object?>? queryParameters,
    CancelToken? cancelToken,
    Options? options,
  }) async {
    calls.add((
      method: method,
      endpoint: endpoint,
      data: data,
      options: options,
    ));
    return Result<T>.success(decoder(response));
  }

  @override
  Future<ApiResult<T>> get<T>(
    Uri endpoint, {
    required ApiResponseDecoder<T> decoder,
    Map<String, Object?>? queryParameters,
    CancelToken? cancelToken,
    Options? options,
  }) {
    return request<T>(
      method: 'GET',
      endpoint: endpoint,
      decoder: decoder,
      options: options,
    );
  }

  @override
  Future<ApiResult<T>> post<T>(
    Uri endpoint, {
    required ApiResponseDecoder<T> decoder,
    Object? data,
    Map<String, Object?>? queryParameters,
    CancelToken? cancelToken,
    Options? options,
  }) {
    return request<T>(
      method: 'POST',
      endpoint: endpoint,
      decoder: decoder,
      data: data,
      options: options,
    );
  }

  @override
  Future<ApiResult<T>> put<T>(
    Uri endpoint, {
    required ApiResponseDecoder<T> decoder,
    Object? data,
    Map<String, Object?>? queryParameters,
    CancelToken? cancelToken,
    Options? options,
  }) {
    return request<T>(
      method: 'PUT',
      endpoint: endpoint,
      decoder: decoder,
      data: data,
      options: options,
    );
  }

  @override
  Future<ApiResult<T>> patch<T>(
    Uri endpoint, {
    required ApiResponseDecoder<T> decoder,
    Object? data,
    Map<String, Object?>? queryParameters,
    CancelToken? cancelToken,
    Options? options,
  }) {
    return request<T>(
      method: 'PATCH',
      endpoint: endpoint,
      decoder: decoder,
      data: data,
      options: options,
    );
  }

  @override
  Future<ApiResult<T>> delete<T>(
    Uri endpoint, {
    required ApiResponseDecoder<T> decoder,
    Object? data,
    Map<String, Object?>? queryParameters,
    CancelToken? cancelToken,
    Options? options,
  }) {
    return request<T>(
      method: 'DELETE',
      endpoint: endpoint,
      decoder: decoder,
      data: data,
      options: options,
    );
  }
}

Map<String, Object?> _envelope(Map<String, Object?> data) {
  return <String, Object?>{'success': true, 'data': data};
}

FeedbackSubmission _submission({FeedbackContext? context}) {
  return FeedbackSubmission(
    category: FeedbackCategory.problem,
    message: '  Save fails on vitals  ',
    context: context ?? const FeedbackContext(routePath: '/opd'),
    submittedAt: DateTime.utc(2026, 9, 14, 11, 35, 27, 123, 456),
  );
}

void main() {
  test(
    'anonymous feedback uses the public client with capped context',
    () async {
      final _RecordingApiClient apiClient = _RecordingApiClient();
      final _RecordingApiClient publicClient = _RecordingApiClient(
        _envelope(<String, Object?>{
          'human_friendly_id': 'FBK0000009',
          'submitter_type': 'ANONYMOUS',
          'submitted_at': '2026-09-14T11:35:27.000Z',
        }),
      );
      final FeedbackRepositoryImpl repository = FeedbackRepositoryImpl(
        apiClient: apiClient,
        publicApiClient: publicClient,
      );

      final Result<FeedbackReceipt> result = await repository.submitFeedback(
        _submission(
          context: FeedbackContext(
            routePath: '/${'a' * 600}',
            routeName: 'patients',
            deviceType: FeedbackDeviceType.mobile,
            orientation: 'portrait',
            screenWidth: 390,
            screenHeight: 844,
            utcOffsetMinutes: 180,
            viewportWidth: 390,
            viewportHeight: 844,
            devicePixelRatio: 3,
          ),
        ),
        signedIn: false,
      );

      expect(apiClient.calls, isEmpty);
      final _RecordedCall call = publicClient.calls.single;
      expect(call.method, 'POST');
      expect(call.endpoint.path, '/api/v1/feedback');

      final Map<String, Object?> body = call.data! as Map<String, Object?>;
      expect(body['category'], 'PROBLEM');
      expect(body['message'], 'Save fails on vitals');
      final Map<String, Object?> context =
          body['context']! as Map<String, Object?>;
      expect((context['route_path']! as String).length, 512);
      expect(context['route_name'], 'patients');
      expect(context['utc_offset_minutes'], 180);
      expect(context['device_type'], 'MOBILE');
      expect(context['orientation'], 'portrait');
      expect(context['screen'], <String, Object?>{'width': 390, 'height': 844});
      expect(context['viewport'], <String, Object?>{
        'width': 390,
        'height': 844,
        'device_pixel_ratio': 3,
      });
      expect(context['client_submitted_at'], '2026-09-14T11:35:27.123Z');
      expect(context.containsKey('page_url'), isFalse);

      final FeedbackReceipt receipt =
          (result as ResultSuccess<FeedbackReceipt>).value;
      expect(receipt.referenceId, 'FBK0000009');
      expect(receipt.submitterType, FeedbackSubmitterType.anonymous);
    },
  );

  test('signed-in feedback uses the session client', () async {
    final _RecordingApiClient apiClient = _RecordingApiClient(
      _envelope(<String, Object?>{
        'human_friendly_id': 'FBK0000010',
        'submitter_type': 'AUTHENTICATED',
      }),
    );
    final _RecordingApiClient publicClient = _RecordingApiClient();
    final FeedbackRepositoryImpl repository = FeedbackRepositoryImpl(
      apiClient: apiClient,
      publicApiClient: publicClient,
    );

    final Result<FeedbackReceipt> result = await repository.submitFeedback(
      _submission(),
      signedIn: true,
    );

    expect(publicClient.calls, isEmpty);
    expect(apiClient.calls.single.endpoint.path, '/api/v1/feedback');
    expect(
      (result as ResultSuccess<FeedbackReceipt>).value.submitterType,
      FeedbackSubmitterType.authenticated,
    );
  });

  test('downloads the export as bytes on the device UTC offset', () async {
    final _RecordingApiClient apiClient = _RecordingApiClient(<int>[
      80,
      75,
      3,
      4,
    ]);
    final FeedbackRepositoryImpl repository = FeedbackRepositoryImpl(
      apiClient: apiClient,
      publicApiClient: _RecordingApiClient(),
    );

    final Result<Uint8List> result = await repository.downloadFeedbackExport(
      utcOffsetMinutes: -300,
    );

    final _RecordedCall call = apiClient.calls.single;
    expect(call.method, 'GET');
    expect(call.endpoint.path, '/api/v1/feedback/export');
    expect(call.endpoint.queryParameters, <String, String>{
      'utc_offset_minutes': '-300',
    });
    expect(call.options?.responseType, ResponseType.bytes);
    expect(
      (result as ResultSuccess<Uint8List>).value,
      Uint8List.fromList(<int>[80, 75, 3, 4]),
    );
  });

  test('reads the feedback summary', () async {
    final _RecordingApiClient apiClient = _RecordingApiClient(
      _envelope(<String, Object?>{
        'total': 5,
        'authenticated': 3,
        'anonymous': 2,
        'latest_submitted_at': '2026-09-14T11:35:27.000Z',
      }),
    );
    final FeedbackRepositoryImpl repository = FeedbackRepositoryImpl(
      apiClient: apiClient,
      publicApiClient: _RecordingApiClient(),
    );

    final Result<FeedbackSummary> result = await repository
        .fetchFeedbackSummary();

    expect(apiClient.calls.single.endpoint.path, '/api/v1/feedback/summary');
    final FeedbackSummary summary =
        (result as ResultSuccess<FeedbackSummary>).value;
    expect(summary.total, 5);
    expect(summary.authenticated, 3);
    expect(summary.anonymous, 2);
    expect(summary.latestSubmittedAt, DateTime.utc(2026, 9, 14, 11, 35, 27));
  });

  test('clears feedback with explicit confirmation', () async {
    final _RecordingApiClient apiClient = _RecordingApiClient(
      _envelope(<String, Object?>{
        'cleared_count': 7,
        'cleared_at': '2026-09-14T12:00:00.000Z',
      }),
    );
    final FeedbackRepositoryImpl repository = FeedbackRepositoryImpl(
      apiClient: apiClient,
      publicApiClient: _RecordingApiClient(),
    );

    final Result<FeedbackClearResult> result = await repository
        .clearFeedback();

    final _RecordedCall call = apiClient.calls.single;
    expect(call.method, 'DELETE');
    expect(call.endpoint.path, '/api/v1/feedback');
    expect(call.data, <String, Object?>{'confirm': true});
    expect((result as ResultSuccess<FeedbackClearResult>).value.clearedCount, 7);
  });
}
