import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hosspi_hms/core/network/api_client.dart';
import 'package:hosspi_hms/core/network/api_result.dart';
import 'package:hosspi_hms/features/feedback/data/repositories/feedback_repository_impl.dart';
import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';
import 'package:hosspi_hms/shared/data/app_pagination.dart';

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

FeedbackRepositoryImpl _repository(_RecordingApiClient apiClient) {
  return FeedbackRepositoryImpl(
    apiClient: apiClient,
    publicApiClient: _RecordingApiClient(),
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
    final FeedbackRepositoryImpl repository = _repository(apiClient);

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

  test('lists a page of feedback with every filter in the query', () async {
    final _RecordingApiClient apiClient = _RecordingApiClient(<String, Object?>{
      'status': 200,
      'data': <Object?>[
        <String, Object?>{
          'human_friendly_id': 'FBK0000021',
          'submitted_at': '2026-09-14T09:30:00.000Z',
          'category': 'PROBLEM',
          'submitter_type': 'ANONYMOUS',
          'message_preview': 'Printer icon does nothing',
          'user_email': null,
          'tenant_name': null,
          'route_path': '/billing',
          'device_type': 'MOBILE',
          'client_platform': 'android',
        },
      ],
      'pagination': <String, Object?>{'page': 2, 'limit': 20, 'total': 41},
    });
    final FeedbackRepositoryImpl repository = _repository(apiClient);
    const AppPageRequest request = AppPageRequest(pageIndex: 1);

    final Result<AppPage<FeedbackRecord>> result = await repository
        .fetchFeedbackPage(
          filters: FeedbackFilters(
            search: '  printer ',
            categories: const <FeedbackCategory>{
              FeedbackCategory.problem,
              FeedbackCategory.complaint,
            },
            submitterType: FeedbackSubmitterType.anonymous,
            deviceTypes: const <FeedbackDeviceType>{FeedbackDeviceType.mobile},
            platforms: const <String>{'web', 'android'},
            submittedFrom: DateTime(2026, 9, 2),
            submittedTo: DateTime(2026, 9, 14),
          ),
          request: request,
        );

    final _RecordedCall call = apiClient.calls.single;
    expect(call.method, 'GET');
    expect(call.endpoint.path, '/api/v1/feedback');
    expect(call.endpoint.queryParameters, <String, String>{
      'page': '2',
      'limit': '20',
      'search': 'printer',
      'category': 'COMPLAINT,PROBLEM',
      'submitter_type': 'ANONYMOUS',
      'device_type': 'MOBILE',
      'platform': 'android,web',
      // Whole local days, sent as UTC instants.
      'from': DateTime(2026, 9, 2).toUtc().toIso8601String(),
      'to': DateTime(2026, 9, 14, 23, 59, 59, 999).toUtc().toIso8601String(),
    });

    final AppPage<FeedbackRecord> page =
        (result as ResultSuccess<AppPage<FeedbackRecord>>).value;
    expect(page.request, request);
    expect(page.totalItemCount, 41);
    final FeedbackRecord record = page.items.single;
    expect(record.referenceId, 'FBK0000021');
    expect(record.category, FeedbackCategory.problem);
    expect(record.submitterType, FeedbackSubmitterType.anonymous);
    expect(record.messagePreview, 'Printer icon does nothing');
    expect(record.submittedAt, DateTime.utc(2026, 9, 14, 9, 30).toLocal());
    expect(record.userEmail, isNull);
    expect(record.routePath, '/billing');
    expect(record.deviceType, FeedbackDeviceType.mobile);
    expect(record.platform, 'android');
  });

  test('deletes the selected feedback permanently', () async {
    final _RecordingApiClient apiClient = _RecordingApiClient(
      _envelope(<String, Object?>{
        'deleted_count': 2,
        'deleted_at': '2026-09-14T12:00:00.000Z',
      }),
    );
    final FeedbackRepositoryImpl repository = _repository(apiClient);

    final Result<FeedbackDeleteResult> result = await repository
        .deleteFeedback(referenceIds: <String>{'FBK0000003', 'FBK0000001'});

    final _RecordedCall call = apiClient.calls.single;
    expect(call.method, 'DELETE');
    expect(call.endpoint.path, '/api/v1/feedback');
    expect(call.data, <String, Object?>{
      'confirm': true,
      'human_friendly_ids': <String>['FBK0000003', 'FBK0000001'],
    });
    final FeedbackDeleteResult deleted =
        (result as ResultSuccess<FeedbackDeleteResult>).value;
    expect(deleted.deletedCount, 2);
    expect(deleted.deletedAt, DateTime.utc(2026, 9, 14, 12));
  });

  test('deletes every record matching the filters', () async {
    final _RecordingApiClient apiClient = _RecordingApiClient(
      _envelope(<String, Object?>{'deleted_count': 12}),
    );
    final FeedbackRepositoryImpl repository = _repository(apiClient);

    final Result<FeedbackDeleteResult> result = await repository
        .deleteMatchingFeedback(
          filters: FeedbackFilters(
            categories: const <FeedbackCategory>{FeedbackCategory.suggestion},
            submittedFrom: DateTime(2026, 9, 14),
          ),
        );

    final _RecordedCall call = apiClient.calls.single;
    expect(call.method, 'DELETE');
    expect(call.data, <String, Object?>{
      'confirm': true,
      'all_matching': true,
      'filters': <String, Object?>{
        'category': <String>['SUGGESTION'],
        'from': DateTime(2026, 9, 14).toUtc().toIso8601String(),
      },
    });
    expect(
      (result as ResultSuccess<FeedbackDeleteResult>).value.deletedCount,
      12,
    );
  });
}
