import 'dart:convert';
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

FeedbackSubmission _submission({
  FeedbackContext? context,
  FeedbackScope scope = FeedbackScope.screen,
  List<FeedbackScreenReference> screens = const <FeedbackScreenReference>[],
  List<FeedbackScreenshot> screenshots = const <FeedbackScreenshot>[],
}) {
  return FeedbackSubmission(
    category: FeedbackCategory.problem,
    message: '  Save fails on vitals  ',
    context: context ?? const FeedbackContext(routePath: '/opd'),
    submittedAt: DateTime.utc(2026, 9, 14, 11, 35, 27, 123, 456),
    scope: scope,
    screens: screens,
    screenshots: screenshots,
  );
}

FeedbackScreenshot _screenshot({
  required String routeName,
  String? caption,
}) {
  return FeedbackScreenshot(
    bytes: Uint8List.fromList(<int>[0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]),
    contentType: 'image/jpeg',
    screen: FeedbackScreenReference(
      routeName: routeName,
      routePath: '/$routeName',
      screenTitle: routeName,
    ),
    capturedAt: DateTime.utc(2026, 9, 20, 9, 15),
    width: 1280,
    height: 800,
    caption: caption,
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
            appVersion: '1.4.0+12',
            timezone: 'Africa/Kampala',
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
      expect(context['app_version'], '1.4.0+12');
      expect(context['timezone'], 'Africa/Kampala');
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
    expect(call.method, 'POST');
    expect(call.endpoint.path, '/api/v1/feedback/export');
    expect(call.endpoint.queryParameters, isEmpty);
    expect(call.data, <String, Object?>{'utc_offset_minutes': -300});
    expect(call.options?.responseType, ResponseType.bytes);
    expect(
      (result as ResultSuccess<Uint8List>).value,
      Uint8List.fromList(<int>[80, 75, 3, 4]),
    );
  });

  test('downloads only the picked records when references are given', () async {
    final _RecordingApiClient apiClient = _RecordingApiClient(<int>[80, 75]);
    final FeedbackRepositoryImpl repository = _repository(apiClient);

    await repository.downloadFeedbackExport(
      utcOffsetMinutes: 0,
      referenceIds: <String>{'FBK0000003', 'FBK0000001'},
      // The picked records win: filters only widen what they already chose.
      filters: const FeedbackFilters(search: 'printer'),
    );

    expect(apiClient.calls.single.data, <String, Object?>{
      'utc_offset_minutes': 0,
      'human_friendly_ids': <String>['FBK0000001', 'FBK0000003'],
    });
  });

  test('downloads every record matching the filters when none are picked', () async {
    final _RecordingApiClient apiClient = _RecordingApiClient(<int>[80, 75]);
    final FeedbackRepositoryImpl repository = _repository(apiClient);

    await repository.downloadFeedbackExport(
      utcOffsetMinutes: 0,
      filters: const FeedbackFilters(
        search: 'printer',
        categories: <FeedbackCategory>{FeedbackCategory.problem},
        values: <FeedbackFilterDimension, Set<String>>{
          FeedbackFilterDimension.tenant: <String>{'TEN-9322E26AFD'},
          FeedbackFilterDimension.routeName: <String>{'hr'},
          FeedbackFilterDimension.breakpoint: <String>{'xl', 'lg'},
        },
      ),
    );

    expect(apiClient.calls.single.data, <String, Object?>{
      'utc_offset_minutes': 0,
      'search': 'printer',
      'category': <String>['PROBLEM'],
      'tenant_id': <String>['TEN-9322E26AFD'],
      'route_name': <String>['hr'],
      'breakpoint': <String>['lg', 'xl'],
    });
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
            values: const <FeedbackFilterDimension, Set<String>>{
              FeedbackFilterDimension.platform: <String>{'web', 'android'},
              FeedbackFilterDimension.tenant: <String>{'TEN-9322E26AFD'},
              FeedbackFilterDimension.facility: <String>{'FAC-FBB67A688F'},
              FeedbackFilterDimension.role: <String>{'PLATFORM_ADMIN'},
              FeedbackFilterDimension.planTier: <String>{'PRO'},
              FeedbackFilterDimension.subscriptionStatus: <String>{'ACTIVE'},
              FeedbackFilterDimension.routeName: <String>{'hr', 'home'},
              FeedbackFilterDimension.appEnvironment: <String>{'production'},
              FeedbackFilterDimension.appVersion: <String>{'1.4.0+12'},
              FeedbackFilterDimension.locale: <String>{'en'},
              FeedbackFilterDimension.breakpoint: <String>{'xl'},
              FeedbackFilterDimension.theme: <String>{'light'},
              FeedbackFilterDimension.connectivity: <String>{'online'},
              FeedbackFilterDimension.orientation: <String>{'landscape'},
            },
            submittedFrom: DateTime(2026, 9, 2),
            submittedTo: DateTime(2026, 9, 14),
          ),
          request: request,
          sort: const FeedbackSort(
            field: FeedbackSortField.category,
            ascending: true,
          ),
        );

    final _RecordedCall call = apiClient.calls.single;
    expect(call.method, 'GET');
    expect(call.endpoint.path, '/api/v1/feedback');
    expect(call.endpoint.queryParameters, <String, String>{
      'page': '2',
      'limit': '20',
      'sort_by': 'category',
      'order': 'asc',
      'search': 'printer',
      'category': 'COMPLAINT,PROBLEM',
      'submitter_type': 'ANONYMOUS',
      'device_type': 'MOBILE',
      'platform': 'android,web',
      'tenant_id': 'TEN-9322E26AFD',
      'facility_id': 'FAC-FBB67A688F',
      'role': 'PLATFORM_ADMIN',
      'plan_tier': 'PRO',
      'subscription_status': 'ACTIVE',
      'route_name': 'home,hr',
      'app_environment': 'production',
      'app_version': '1.4.0+12',
      'locale': 'en',
      'breakpoint': 'xl',
      'theme': 'light',
      'connectivity': 'online',
      'orientation': 'landscape',
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

  test('loads filter values and counts under the active filters', () async {
    final _RecordingApiClient apiClient = _RecordingApiClient(
      _envelope(<String, Object?>{
        'total': 19,
        'facets': <String, Object?>{
          'category': <Object?>[
            <String, Object?>{'value': 'PROBLEM', 'count': 11},
          ],
          'submitter_type': <Object?>[
            <String, Object?>{'value': 'AUTHENTICATED', 'count': 19},
          ],
          'tenant_id': <Object?>[
            <String, Object?>{
              'value': 'TEN-9322E26AFD',
              'label': 'DemoCare General Hospital',
              'count': 19,
            },
          ],
          'breakpoint': <Object?>[
            <String, Object?>{'value': 'xl', 'count': 15},
            <String, Object?>{'value': 'sm', 'count': 4},
            // Blank values are not choices.
            <String, Object?>{'value': '', 'count': 2},
          ],
          'app_version': <Object?>[],
        },
      }),
    );
    final FeedbackRepositoryImpl repository = _repository(apiClient);

    final Result<FeedbackFacets> result = await repository.fetchFeedbackFacets(
      filters: const FeedbackFilters(
        search: 'slow',
        values: <FeedbackFilterDimension, Set<String>>{
          FeedbackFilterDimension.routeName: <String>{'hr'},
        },
      ),
    );

    final _RecordedCall call = apiClient.calls.single;
    expect(call.method, 'GET');
    expect(call.endpoint.path, '/api/v1/feedback/facets');
    expect(call.endpoint.queryParameters, <String, String>{
      'search': 'slow',
      'route_name': 'hr',
    });

    final FeedbackFacets facets =
        (result as ResultSuccess<FeedbackFacets>).value;
    expect(facets.total, 19);
    expect(facets.categories.single.value, 'PROBLEM');
    expect(facets.submitterTypes.single.count, 19);
    final FeedbackFacetValue tenant = facets
        .valuesFor(FeedbackFilterDimension.tenant)
        .single;
    expect(tenant.value, 'TEN-9322E26AFD');
    expect(tenant.label, 'DemoCare General Hospital');
    expect(
      facets
          .valuesFor(FeedbackFilterDimension.breakpoint)
          .map((FeedbackFacetValue facet) => '${facet.value}:${facet.count}'),
      <String>['xl:15', 'sm:4'],
    );
    expect(facets.valuesFor(FeedbackFilterDimension.appVersion), isEmpty);
    expect(facets.valuesFor(FeedbackFilterDimension.platform), isEmpty);
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
            values: const <FeedbackFilterDimension, Set<String>>{
              FeedbackFilterDimension.tenant: <String>{'TEN-9322E26AFD'},
              FeedbackFilterDimension.routeName: <String>{'hr'},
              FeedbackFilterDimension.breakpoint: <String>{'xl'},
            },
            submittedFrom: DateTime(2026, 9, 14),
          ),
        );

    final _RecordedCall call = apiClient.calls.single;
    expect(call.method, 'DELETE');
    // The same filters an export of these records would send.
    expect(call.data, <String, Object?>{
      'confirm': true,
      'all_matching': true,
      'filters': <String, Object?>{
        'category': <String>['SUGGESTION'],
        'tenant_id': <String>['TEN-9322E26AFD'],
        'route_name': <String>['hr'],
        'breakpoint': <String>['xl'],
        'from': DateTime(2026, 9, 14).toUtc().toIso8601String(),
      },
    });
    expect(
      (result as ResultSuccess<FeedbackDeleteResult>).value.deletedCount,
      12,
    );
  });

  test('feedback without pictures stays a plain JSON request', () async {
    final _RecordingApiClient apiClient = _RecordingApiClient(
      _envelope(<String, Object?>{'human_friendly_id': 'FBK0000011'}),
    );

    await _repository(apiClient).submitFeedback(
      _submission(
        scope: FeedbackScope.screens,
        screens: <FeedbackScreenReference>[
          const FeedbackScreenReference(
            routeName: 'opd',
            routePath: '/opd',
            screenTitle: 'Outpatients',
          ),
          // A screen the API could not address is left out.
          const FeedbackScreenReference(screenTitle: 'Nowhere'),
        ],
      ),
      signedIn: true,
    );

    final Map<String, Object?> body =
        apiClient.calls.single.data! as Map<String, Object?>;
    expect(body['scope'], 'SCREENS');
    expect(body['scope_screens'], <Map<String, Object?>>[
      <String, Object?>{
        'route_name': 'opd',
        'route_path': '/opd',
        'screen_title': 'Outpatients',
      },
    ]);
    expect(body.containsKey('screenshots'), isFalse);
  });

  test('feedback with pictures is sent as multipart beside its payload', () async {
    final _RecordingApiClient apiClient = _RecordingApiClient(
      _envelope(<String, Object?>{
        'human_friendly_id': 'FBK0000012',
        'submitter_type': 'AUTHENTICATED',
        'screenshot_count': 2,
        'screenshots_dropped': 1,
      }),
    );

    final Result<FeedbackReceipt> result = await _repository(apiClient)
        .submitFeedback(
          _submission(
            screenshots: <FeedbackScreenshot>[
              _screenshot(routeName: 'opd', caption: 'the queue'),
              _screenshot(routeName: 'pharmacy'),
            ],
          ),
          signedIn: true,
        );

    final FormData form = apiClient.calls.single.data! as FormData;
    expect(form.files.map((MapEntry<String, MultipartFile> file) => file.key), <String>[
      'screenshots',
      'screenshots',
    ]);
    expect(form.files.first.value.contentType?.mimeType, 'image/jpeg');

    // The whole JSON body rides in one field, so the API validates one shape.
    final Map<String, Object?> payload =
        jsonDecode(form.fields.single.value) as Map<String, Object?>;
    expect(form.fields.single.key, 'payload');
    expect(payload['message'], 'Save fails on vitals');
    final List<Object?> screenshots = payload['screenshots']! as List<Object?>;
    expect(screenshots, hasLength(2));
    expect(screenshots.first, <String, Object?>{
      'width': 1280,
      'height': 800,
      'caption': 'the queue',
      'route_name': 'opd',
      'route_path': '/opd',
      'screen_title': 'opd',
      'captured_at': '2026-09-20T09:15:00.000Z',
    });

    final FeedbackReceipt receipt =
        (result as ResultSuccess<FeedbackReceipt>).value;
    expect(receipt.screenshotCount, 2);
    // What did not arrive is reported, not glossed over.
    expect(receipt.screenshotsDropped, 1);
  });

  test('lists the screenshots of one record with their screens', () async {
    final _RecordingApiClient apiClient = _RecordingApiClient(
      _envelope(<String, Object?>{
        'human_friendly_id': 'FBK0000011',
        'items': <Map<String, Object?>>[
          <String, Object?>{
            'id': '11111111-1111-4111-8111-111111111111',
            'sequence': 1,
            'content_type': 'image/jpeg',
            'byte_size': 2048,
            'width': 1280,
            'height': 800,
            'caption': 'the queue',
            'route_name': 'opd',
            'route_path': '/opd',
            'screen_title': 'Outpatients',
            'captured_at': '2026-09-20T09:15:00.000Z',
            'file_name': 'FBK0000011.jpg',
          },
        ],
      }),
    );

    final Result<List<FeedbackStoredScreenshot>> result = await _repository(
      apiClient,
    ).fetchFeedbackScreenshots(referenceId: 'FBK0000011');

    expect(
      apiClient.calls.single.endpoint.path,
      '/api/v1/feedback/FBK0000011/screenshots',
    );
    final FeedbackStoredScreenshot screenshot =
        (result as ResultSuccess<List<FeedbackStoredScreenshot>>).value.single;
    expect(screenshot.fileName, 'FBK0000011.jpg');
    expect(screenshot.screen.label, 'Outpatients');
    expect(screenshot.byteSize, 2048);
  });

  test('fetches one screenshot as bytes', () async {
    final _RecordingApiClient apiClient = _RecordingApiClient(
      Uint8List.fromList(<int>[1, 2, 3]),
    );

    final Result<Uint8List> result = await _repository(apiClient)
        .fetchFeedbackScreenshotImage(
          referenceId: 'FBK0000011',
          screenshotId: '11111111-1111-4111-8111-111111111111',
        );

    expect(
      apiClient.calls.single.endpoint.path,
      '/api/v1/feedback/FBK0000011/screenshots/'
          '11111111-1111-4111-8111-111111111111',
    );
    expect(apiClient.calls.single.options?.responseType, ResponseType.bytes);
    expect((result as ResultSuccess<Uint8List>).value, <int>[1, 2, 3]);
  });

  test('reports the images deleted with the records', () async {
    final _RecordingApiClient apiClient = _RecordingApiClient(
      _envelope(<String, Object?>{
        'deleted_count': 2,
        'deleted_screenshot_count': 5,
      }),
    );

    final Result<FeedbackDeleteResult> result = await _repository(apiClient)
        .deleteFeedback(referenceIds: <String>{'FBK0000011'});

    final FeedbackDeleteResult deleted =
        (result as ResultSuccess<FeedbackDeleteResult>).value;
    expect(deleted.deletedCount, 2);
    expect(deleted.deletedScreenshotCount, 5);
  });
}
