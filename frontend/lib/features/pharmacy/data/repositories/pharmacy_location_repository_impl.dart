import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/network/api_client.dart';
import 'package:hosspi_hms/core/network/api_endpoints.dart';
import 'package:hosspi_hms/core/network/network_providers.dart';
import 'package:hosspi_hms/features/pharmacy/data/dtos/pharmacy_location_dtos.dart';
import 'package:hosspi_hms/features/pharmacy/domain/entities/pharmacy_location_entities.dart';
import 'package:hosspi_hms/features/pharmacy/domain/repositories/pharmacy_location_repository.dart';
import 'package:hosspi_hms/shared/data/data.dart';

final pharmacyLocationRepositoryProvider = Provider<PharmacyLocationRepository>(
  (ref) => PharmacyLocationRepositoryImpl(apiClient: ref.watch(apiClientProvider)),
);

final class PharmacyLocationRepositoryImpl implements PharmacyLocationRepository {
  const PharmacyLocationRepositoryImpl({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  Uri _locations([List<String> segments = const <String>[]]) {
    return ApiEndpoints.apiV1(<String>[
      HmsApiResource.pharmacyLocations.path,
      ...segments,
    ]);
  }

  Uri _stockOrders([List<String> segments = const <String>[]]) {
    return ApiEndpoints.apiV1(<String>[
      HmsApiResource.pharmacyStockOrders.path,
      ...segments,
    ]);
  }

  @override
  Future<Result<AppPage<PharmacyLocation>>> listLocations({
    String? facilityId,
    PharmacyLocationKind? kind,
    bool? mineOnly,
    bool? isActive,
    String? search,
    AppPageRequest pageRequest = const AppPageRequest(),
  }) {
    return _apiClient.get<AppPage<PharmacyLocation>>(
      _locations(),
      queryParameters: _withoutEmpty(<String, Object?>{
        'page': pageRequest.pageIndex + 1,
        'limit': pageRequest.pageSize,
        'facility_id': facilityId,
        'kind': kind == null ? null : pharmacyLocationKindToApi(kind),
        'mine_only': mineOnly,
        'is_active': isActive,
        'search': search,
      }),
      decoder: (Object? data) =>
          PharmacyLocationDtos.locationPage(data, pageRequest),
    );
  }

  @override
  Future<Result<PharmacyLocation>> getLocation(String locationId) {
    return _apiClient.get<PharmacyLocation>(
      _locations(<String>[locationId]),
      decoder: (Object? data) =>
          PharmacyLocationDtos.location(_dataOf(data)),
    );
  }

  @override
  Future<Result<PharmacyLocation>> createLocation({
    required String facilityId,
    required String name,
    required PharmacyLocationKind kind,
    String? code,
    bool? handlesProcurement,
    bool? handlesWalkIn,
    bool? handlesPrescriptions,
    String? suppliedByLocationId,
    String? currency,
    bool? isDefault,
  }) {
    return _apiClient.post<PharmacyLocation>(
      _locations(),
      data: _withoutEmpty(<String, Object?>{
        'facility_id': facilityId,
        'name': name,
        'kind': pharmacyLocationKindToApi(kind),
        'code': code,
        'handles_procurement': handlesProcurement,
        'handles_walk_in': handlesWalkIn,
        'handles_prescriptions': handlesPrescriptions,
        'supplied_by_location_id': suppliedByLocationId,
        'currency': currency,
        'is_default': isDefault,
      }),
      decoder: (Object? data) => PharmacyLocationDtos.location(_dataOf(data)),
    );
  }

  @override
  Future<Result<PharmacyLocation>> updateLocation(
    String locationId, {
    String? name,
    String? code,
    PharmacyLocationKind? kind,
    bool? isActive,
    bool? isDefault,
    bool? handlesProcurement,
    bool? handlesWalkIn,
    bool? handlesPrescriptions,
    String? suppliedByLocationId,
    bool clearSuppliedBy = false,
    String? currency,
  }) {
    return _apiClient.put<PharmacyLocation>(
      _locations(<String>[locationId]),
      data: <String, Object?>{
        ..._withoutEmpty(<String, Object?>{
          'name': name,
          'code': code,
          'kind': kind == null ? null : pharmacyLocationKindToApi(kind),
          'is_active': isActive,
          'is_default': isDefault,
          'handles_procurement': handlesProcurement,
          'handles_walk_in': handlesWalkIn,
          'handles_prescriptions': handlesPrescriptions,
          'supplied_by_location_id': suppliedByLocationId,
          'currency': currency,
        }),
        // Explicit null is how the supply link is cleared, so it must survive
        // the empty-value filter above.
        if (clearSuppliedBy) 'supplied_by_location_id': null,
      },
      decoder: (Object? data) => PharmacyLocationDtos.location(_dataOf(data)),
    );
  }

  @override
  Future<Result<PharmacyAvailabilityPage>> getAvailability(
    String locationId, {
    String? compareLocationId,
    String? search,
    bool? belowReorderLevel,
    AppPageRequest pageRequest = const AppPageRequest(),
  }) {
    return _apiClient.get<PharmacyAvailabilityPage>(
      _locations(<String>[locationId, 'availability']),
      queryParameters: _withoutEmpty(<String, Object?>{
        'page': pageRequest.pageIndex + 1,
        'limit': pageRequest.pageSize,
        'compare_location_id': compareLocationId,
        'search': search,
        'below_reorder_level': belowReorderLevel,
      }),
      decoder: (Object? data) =>
          PharmacyLocationDtos.availabilityPage(data, pageRequest),
    );
  }

  @override
  Future<Result<AppPage<PharmacyLocationPrice>>> listPrices(
    String locationId, {
    String? drugId,
    String? search,
    AppPageRequest pageRequest = const AppPageRequest(),
  }) {
    return _apiClient.get<AppPage<PharmacyLocationPrice>>(
      _locations(<String>[locationId, 'prices']),
      queryParameters: _withoutEmpty(<String, Object?>{
        'page': pageRequest.pageIndex + 1,
        'limit': pageRequest.pageSize,
        'drug_id': drugId,
        'search': search,
      }),
      decoder: (Object? data) =>
          PharmacyLocationDtos.pricePage(data, pageRequest),
    );
  }

  @override
  Future<Result<PharmacyLocationPrice>> upsertPrice(
    String locationId, {
    required String drugId,
    num? sellPrice,
    num? supplyPrice,
    num? acquisitionCost,
    String? currency,
    bool? isActive,
  }) {
    // Only the fields the caller passed are sent, so a walk-in price edit never
    // carries a stale supply price along with it.
    return _apiClient.put<PharmacyLocationPrice>(
      _locations(<String>[locationId, 'prices']),
      data: _withoutEmpty(<String, Object?>{
        'drug_id': drugId,
        'sell_price': sellPrice,
        'supply_price': supplyPrice,
        'acquisition_cost': acquisitionCost,
        'currency': currency,
        'is_active': isActive,
      }),
      decoder: (Object? data) => PharmacyLocationDtos.price(_dataOf(data)),
    );
  }

  @override
  Future<Result<AppPage<PharmacyStockOrder>>> listStockOrders({
    String? locationId,
    PharmacyStockOrderQueue queue = PharmacyStockOrderQueue.all,
    PharmacyStockOrderStatus? status,
    String? search,
    AppPageRequest pageRequest = const AppPageRequest(),
  }) {
    return _apiClient.get<AppPage<PharmacyStockOrder>>(
      _stockOrders(),
      queryParameters: _withoutEmpty(<String, Object?>{
        'page': pageRequest.pageIndex + 1,
        'limit': pageRequest.pageSize,
        'location_id': locationId,
        'queue': pharmacyStockOrderQueueToApi(queue),
        'status': status == null ? null : pharmacyStockOrderStatusToApi(status),
        'search': search,
      }),
      decoder: (Object? data) =>
          PharmacyLocationDtos.stockOrderPage(data, pageRequest),
    );
  }

  @override
  Future<Result<PharmacyStockOrder>> getStockOrder(String stockOrderId) {
    return _apiClient.get<PharmacyStockOrder>(
      _stockOrders(<String>[stockOrderId]),
      decoder: PharmacyLocationDtos.stockOrderFromResponse,
    );
  }

  @override
  Future<Result<PharmacyStockOrder>> createStockOrder({
    required String requestingLocationId,
    required List<PharmacyStockOrderLineInput> items,
    String? supplyingLocationId,
    String? notes,
    bool submit = false,
  }) {
    return _apiClient.post<PharmacyStockOrder>(
      _stockOrders(),
      data: _withoutEmpty(<String, Object?>{
        'requesting_location_id': requestingLocationId,
        'supplying_location_id': supplyingLocationId,
        'notes': notes,
        'submit': submit,
        'items': items
            .map((PharmacyStockOrderLineInput item) => item.toJson())
            .toList(growable: false),
      }),
      decoder: PharmacyLocationDtos.stockOrderFromResponse,
    );
  }

  @override
  Future<Result<PharmacyStockOrder>> updateStockOrder(
    String stockOrderId, {
    String? notes,
    List<PharmacyStockOrderLineInput>? items,
  }) {
    return _apiClient.put<PharmacyStockOrder>(
      _stockOrders(<String>[stockOrderId]),
      data: _withoutEmpty(<String, Object?>{
        'notes': notes,
        'items': items
            ?.map((PharmacyStockOrderLineInput item) => item.toJson())
            .toList(growable: false),
      }),
      decoder: PharmacyLocationDtos.stockOrderFromResponse,
    );
  }

  @override
  Future<Result<PharmacyStockOrder>> submitStockOrder(String stockOrderId) {
    return _apiClient.post<PharmacyStockOrder>(
      _stockOrders(<String>[stockOrderId, 'submit']),
      decoder: PharmacyLocationDtos.stockOrderFromResponse,
    );
  }

  @override
  Future<Result<PharmacyStockOrder>> reviewStockOrder(
    String stockOrderId, {
    required bool approve,
    String? reviewNotes,
    List<PharmacyStockOrderDecisionInput>? items,
  }) {
    return _apiClient.post<PharmacyStockOrder>(
      _stockOrders(<String>[stockOrderId, 'review']),
      data: _withoutEmpty(<String, Object?>{
        'decision': approve ? 'APPROVE' : 'REJECT',
        'review_notes': reviewNotes,
        'items': items
            ?.map((PharmacyStockOrderDecisionInput item) => item.toJson())
            .toList(growable: false),
      }),
      decoder: PharmacyLocationDtos.stockOrderFromResponse,
    );
  }

  @override
  Future<Result<PharmacyStockOrder>> issueStockOrder(
    String stockOrderId, {
    List<PharmacyStockOrderQuantityInput>? items,
    String? notes,
  }) {
    return _apiClient.post<PharmacyStockOrder>(
      _stockOrders(<String>[stockOrderId, 'issue']),
      data: _withoutEmpty(<String, Object?>{
        'notes': notes,
        'items': items
            ?.map((PharmacyStockOrderQuantityInput item) => item.issuedJson())
            .toList(growable: false),
      }),
      decoder: PharmacyLocationDtos.stockOrderFromResponse,
    );
  }

  @override
  Future<Result<PharmacyStockOrder>> receiveStockOrder(
    String stockOrderId, {
    List<PharmacyStockOrderQuantityInput>? items,
    String? notes,
  }) {
    return _apiClient.post<PharmacyStockOrder>(
      _stockOrders(<String>[stockOrderId, 'receive']),
      data: _withoutEmpty(<String, Object?>{
        'notes': notes,
        'items': items
            ?.map((PharmacyStockOrderQuantityInput item) => item.receivedJson())
            .toList(growable: false),
      }),
      decoder: PharmacyLocationDtos.stockOrderFromResponse,
    );
  }

  @override
  Future<Result<PharmacyStockOrder>> cancelStockOrder(
    String stockOrderId, {
    String? reason,
  }) {
    return _apiClient.post<PharmacyStockOrder>(
      _stockOrders(<String>[stockOrderId, 'cancel']),
      data: _withoutEmpty(<String, Object?>{'reason': reason}),
      decoder: PharmacyLocationDtos.stockOrderFromResponse,
    );
  }
}

Object? _dataOf(Object? response) {
  if (response is Map<String, Object?>) {
    return response['data'];
  }
  return response;
}

Map<String, Object?> _withoutEmpty(Map<String, Object?> payload) {
  return <String, Object?>{
    for (final MapEntry<String, Object?> entry in payload.entries)
      if (!_isEmptyPayloadValue(entry.value)) entry.key: entry.value,
  };
}

bool _isEmptyPayloadValue(Object? value) {
  if (value == null) {
    return true;
  }
  if (value is String) {
    return value.trim().isEmpty;
  }
  if (value is Iterable) {
    return value.isEmpty;
  }
  if (value is Map) {
    return value.isEmpty;
  }
  return false;
}
