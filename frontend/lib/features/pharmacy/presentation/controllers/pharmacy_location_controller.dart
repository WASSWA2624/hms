import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/realtime/realtime_event_groups.dart';
import 'package:hosspi_hms/core/realtime/realtime_message.dart';
import 'package:hosspi_hms/core/realtime/realtime_refresh.dart';
import 'package:hosspi_hms/core/security/session_isolation.dart';
import 'package:hosspi_hms/features/pharmacy/data/dtos/pharmacy_location_dtos.dart';
import 'package:hosspi_hms/features/pharmacy/data/repositories/pharmacy_location_repository_impl.dart';
import 'package:hosspi_hms/features/pharmacy/domain/entities/pharmacy_location_entities.dart';
import 'package:hosspi_hms/features/pharmacy/domain/repositories/pharmacy_location_repository.dart';
import 'package:hosspi_hms/shared/data/data.dart';

/// Which pharmacy the user is working in, and everything scoped to it.
///
/// Every pharmacy screen reads [PharmacyLocationState.activeLocation] rather
/// than a facility id, so Main and Hospital stock, prices and stock orders stay
/// separate without each screen having to remember to filter.
final pharmacyLocationControllerProvider =
    AsyncNotifierProvider<
      PharmacyLocationController,
      Result<PharmacyLocationState>
    >(PharmacyLocationController.new);

@immutable
final class PharmacyLocationState {
  const PharmacyLocationState({
    this.locations = const <PharmacyLocation>[],
    this.activeLocationId,
    this.availability = const <PharmacyAvailabilityRow>[],
    this.comparisonLocation,
    this.stockOrders = const <PharmacyStockOrder>[],
    this.isRefreshing = false,
    this.lastFailure,
  });

  /// Pharmacies the user may act in, plus any they can see.
  final List<PharmacyLocation> locations;

  /// The pharmacy currently selected.
  final String? activeLocationId;

  /// This pharmacy's stock beside its supplier's availability.
  final List<PharmacyAvailabilityRow> availability;

  /// The pharmacy the availability rows are compared against.
  final PharmacyLocation? comparisonLocation;

  /// Stock orders this pharmacy is a party to, either side.
  final List<PharmacyStockOrder> stockOrders;

  final bool isRefreshing;
  final AppFailure? lastFailure;

  PharmacyLocation? get activeLocation {
    final String? id = activeLocationId;
    if (id == null) return null;
    for (final PharmacyLocation location in locations) {
      if (location.id == id) return location;
    }
    return null;
  }

  /// The pharmacy the active one orders its stock from.
  PharmacyLocation? get supplyingLocation {
    final String? supplierId = activeLocation?.suppliedByLocationId;
    if (supplierId == null) return comparisonLocation;
    for (final PharmacyLocation location in locations) {
      if (location.id == supplierId) return location;
    }
    return comparisonLocation;
  }

  /// Pharmacies the user may switch between.
  List<PharmacyLocation> get switchableLocations => locations
      .where((PharmacyLocation location) => location.canView && location.isActive)
      .toList(growable: false);

  bool get hasMultipleLocations => switchableLocations.length > 1;

  /// Whether the active pharmacy runs procurement, which decides if supplier,
  /// purchase, batch, expiry and cost surfaces are shown at all.
  bool get activeHandlesProcurement => activeLocation?.handlesProcurement ?? true;

  /// Whether the active pharmacy can raise stock orders.
  bool get canOrderStock =>
      (activeLocation?.ordersFromAnotherPharmacy ?? false) &&
      (activeLocation?.canDispense ?? false);

  /// Stock orders waiting on the active pharmacy to review or issue.
  List<PharmacyStockOrder> get inboxOrders {
    final String? id = activeLocationId;
    if (id == null) return const <PharmacyStockOrder>[];
    return stockOrders
        .where(
          (PharmacyStockOrder order) =>
              order.supplyingLocationId == id && !order.isTerminal,
        )
        .toList(growable: false);
  }

  /// Stock orders the active pharmacy has raised.
  List<PharmacyStockOrder> get outboxOrders {
    final String? id = activeLocationId;
    if (id == null) return const <PharmacyStockOrder>[];
    return stockOrders
        .where((PharmacyStockOrder order) => order.requestingLocationId == id)
        .toList(growable: false);
  }

  /// Orders the active pharmacy must do something about right now.
  List<PharmacyStockOrder> get actionableOrders {
    final String? id = activeLocationId;
    if (id == null) return const <PharmacyStockOrder>[];
    return stockOrders
        .where((PharmacyStockOrder order) => order.isActionableBy(id))
        .toList(growable: false);
  }

  /// Rows at or below reorder level, worst shortfall first.
  List<PharmacyAvailabilityRow> get reorderSuggestions {
    final List<PharmacyAvailabilityRow> rows = availability
        .where((PharmacyAvailabilityRow row) => row.belowReorderLevel)
        .toList();
    rows.sort((PharmacyAvailabilityRow a, PharmacyAvailabilityRow b) {
      final int aGap = a.reorderLevel - a.quantity;
      final int bGap = b.reorderLevel - b.quantity;
      return bGap.compareTo(aGap);
    });
    return List<PharmacyAvailabilityRow>.unmodifiable(rows);
  }

  PharmacyLocationState copyWith({
    List<PharmacyLocation>? locations,
    String? activeLocationId,
    List<PharmacyAvailabilityRow>? availability,
    PharmacyLocation? comparisonLocation,
    bool clearComparisonLocation = false,
    List<PharmacyStockOrder>? stockOrders,
    bool? isRefreshing,
    AppFailure? lastFailure,
    bool clearLastFailure = false,
  }) {
    return PharmacyLocationState(
      locations: locations ?? this.locations,
      activeLocationId: activeLocationId ?? this.activeLocationId,
      availability: availability ?? this.availability,
      comparisonLocation: clearComparisonLocation
          ? null
          : comparisonLocation ?? this.comparisonLocation,
      stockOrders: stockOrders ?? this.stockOrders,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      lastFailure: clearLastFailure ? null : lastFailure ?? this.lastFailure,
    );
  }
}

final class PharmacyLocationController
    extends AsyncNotifier<Result<PharmacyLocationState>> {
  PharmacyLocationRepository get _repository =>
      ref.read(pharmacyLocationRepositoryProvider);

  bool _isSyncing = false;
  String? _pendingActiveLocationId;

  @override
  Future<Result<PharmacyLocationState>> build() async {
    watchSessionEpoch(ref);
    listenForRealtimeRefresh(
      ref: ref,
      events: RealtimeEventGroups.pharmacyWorkspace,
      includeCrudMutations: true,
      shouldDefer: () => _isSyncing,
      onRefresh: _refreshFromRealtime,
    );
    return _load();
  }

  PharmacyLocationState? get _currentState {
    return state.asData?.value.when(
      success: (PharmacyLocationState value) => value,
      failure: (_) => null,
    );
  }

  void _emit(PharmacyLocationState value) {
    state = AsyncData<Result<PharmacyLocationState>>(
      Result<PharmacyLocationState>.success(value),
    );
  }

  Future<void> _refreshFromRealtime(RealtimeMessage _) async {
    await refresh();
  }

  /// Switches the pharmacy the user is working in and reloads what it scopes.
  Future<AppFailure?> selectLocation(String locationId) async {
    final PharmacyLocationState? current = _currentState;
    if (current == null || current.activeLocationId == locationId) {
      return null;
    }
    _pendingActiveLocationId = locationId;
    _emit(
      current.copyWith(
        activeLocationId: locationId,
        isRefreshing: true,
        availability: const <PharmacyAvailabilityRow>[],
        stockOrders: const <PharmacyStockOrder>[],
        clearComparisonLocation: true,
        clearLastFailure: true,
      ),
    );
    return refresh();
  }

  Future<AppFailure?> refresh() async {
    final PharmacyLocationState? current = _currentState;
    if (current != null) {
      _emit(current.copyWith(isRefreshing: true, clearLastFailure: true));
    }

    final Result<PharmacyLocationState> result = await _load();
    AppFailure? failure;
    result.when(
      success: _emit,
      failure: (AppFailure value) {
        failure = value;
        final PharmacyLocationState? previous = _currentState;
        if (previous != null) {
          _emit(previous.copyWith(isRefreshing: false, lastFailure: value));
        } else {
          state = AsyncData<Result<PharmacyLocationState>>(result);
        }
      },
    );
    return failure;
  }

  Future<Result<PharmacyLocationState>> _load() async {
    _isSyncing = true;
    try {
      final Result<AppPage<PharmacyLocation>> locationsResult = await _repository
          .listLocations(
            isActive: true,
            pageRequest: const AppPageRequest(
              pageSize: AppPageRequest.maxPageSize,
            ),
          );

      AppFailure? failure;
      AppPage<PharmacyLocation>? locationPage;
      locationsResult.when(
        success: (AppPage<PharmacyLocation> value) => locationPage = value,
        failure: (AppFailure value) => failure = value,
      );
      if (failure != null) {
        return Result<PharmacyLocationState>.failure(failure!);
      }

      final List<PharmacyLocation> locations = locationPage!.items;
      final String? activeId = _resolveActiveLocationId(locations);

      if (activeId == null) {
        // A facility that has not configured pharmacy locations yet still gets
        // a working (empty) state rather than an error.
        return Result<PharmacyLocationState>.success(
          PharmacyLocationState(locations: locations),
        );
      }

      final Results results = await _loadForLocation(activeId);
      if (results.failure != null) {
        return Result<PharmacyLocationState>.failure(results.failure!);
      }

      return Result<PharmacyLocationState>.success(
        PharmacyLocationState(
          locations: locations,
          activeLocationId: activeId,
          availability: results.availability,
          comparisonLocation: results.comparisonLocation,
          stockOrders: results.stockOrders,
        ),
      );
    } finally {
      _isSyncing = false;
    }
  }

  /// Picks the pharmacy to work in: the user's explicit choice, else the one
  /// they can dispense from, else the first they can see.
  String? _resolveActiveLocationId(List<PharmacyLocation> locations) {
    if (locations.isEmpty) return null;

    final String? pending = _pendingActiveLocationId ?? _currentState?.activeLocationId;
    if (pending != null &&
        locations.any((PharmacyLocation location) => location.id == pending)) {
      return pending;
    }

    for (final PharmacyLocation location in locations) {
      if (location.canDispense) return location.id;
    }
    for (final PharmacyLocation location in locations) {
      if (location.canView) return location.id;
    }
    return locations.first.id;
  }

  Future<Results> _loadForLocation(String locationId) async {
    final Result<PharmacyAvailabilityPage> availabilityResult =
        await _repository.getAvailability(
          locationId,
          pageRequest: const AppPageRequest(
            pageSize: AppPageRequest.maxPageSize,
          ),
        );

    AppFailure? failure;
    PharmacyAvailabilityPage? availabilityPage;
    availabilityResult.when(
      success: (PharmacyAvailabilityPage value) => availabilityPage = value,
      failure: (AppFailure value) => failure = value,
    );
    if (failure != null) {
      return Results(failure: failure);
    }

    final Result<AppPage<PharmacyStockOrder>> ordersResult = await _repository
        .listStockOrders(
          locationId: locationId,
          pageRequest: const AppPageRequest(
            pageSize: AppPageRequest.maxPageSize,
          ),
        );

    AppPage<PharmacyStockOrder>? orderPage;
    ordersResult.when(
      success: (AppPage<PharmacyStockOrder> value) => orderPage = value,
      failure: (AppFailure value) => failure = value,
    );
    if (failure != null) {
      return Results(failure: failure);
    }

    return Results(
      availability: availabilityPage!.page.items,
      comparisonLocation: availabilityPage!.comparisonLocation,
      stockOrders: orderPage!.items,
    );
  }

  // ------------------------------------------------------- stock order acts

  /// Raises a stock order against the supplying pharmacy. Changes no balance.
  Future<AppFailure?> createStockOrder({
    required List<PharmacyStockOrderLineInput> items,
    String? notes,
    bool submit = true,
  }) {
    final String? locationId = _currentState?.activeLocationId;
    if (locationId == null || items.isEmpty) {
      return Future<AppFailure?>.value(AppFailure.validation());
    }
    return _mutate(
      () => _repository.createStockOrder(
        requestingLocationId: locationId,
        items: items,
        notes: notes,
        submit: submit,
      ),
    );
  }

  Future<AppFailure?> submitStockOrder(String stockOrderId) {
    return _mutate(() => _repository.submitStockOrder(stockOrderId));
  }

  /// Approve, partially approve or reject. Changes no balance.
  Future<AppFailure?> reviewStockOrder(
    String stockOrderId, {
    required bool approve,
    String? reviewNotes,
    List<PharmacyStockOrderDecisionInput>? items,
  }) {
    return _mutate(
      () => _repository.reviewStockOrder(
        stockOrderId,
        approve: approve,
        reviewNotes: reviewNotes,
        items: items,
      ),
    );
  }

  /// Releases the stock from the supplying pharmacy.
  Future<AppFailure?> issueStockOrder(
    String stockOrderId, {
    List<PharmacyStockOrderQuantityInput>? items,
    String? notes,
  }) {
    return _mutate(
      () => _repository.issueStockOrder(stockOrderId, items: items, notes: notes),
    );
  }

  /// Books the delivery into the requesting pharmacy.
  Future<AppFailure?> receiveStockOrder(
    String stockOrderId, {
    List<PharmacyStockOrderQuantityInput>? items,
    String? notes,
  }) {
    return _mutate(
      () =>
          _repository.receiveStockOrder(stockOrderId, items: items, notes: notes),
    );
  }

  Future<AppFailure?> cancelStockOrder(String stockOrderId, {String? reason}) {
    return _mutate(() => _repository.cancelStockOrder(stockOrderId, reason: reason));
  }

  /// Sets one of the active pharmacy's own prices.
  Future<AppFailure?> setPrice({
    required String drugId,
    num? sellPrice,
    num? supplyPrice,
  }) {
    final String? locationId = _currentState?.activeLocationId;
    if (locationId == null) {
      return Future<AppFailure?>.value(AppFailure.validation());
    }
    return _mutate(
      () => _repository.upsertPrice(
        locationId,
        drugId: drugId,
        sellPrice: sellPrice,
        supplyPrice: supplyPrice,
      ),
    );
  }

  Future<AppFailure?> _mutate<T>(Future<Result<T>> Function() action) async {
    final Result<T> result = await action();
    AppFailure? failure;
    result.when(success: (_) {}, failure: (AppFailure value) => failure = value);
    if (failure != null) {
      final PharmacyLocationState? current = _currentState;
      if (current != null) {
        _emit(current.copyWith(lastFailure: failure));
      }
      return failure;
    }
    return refresh();
  }
}

/// Internal carrier for the three loads that make up a location's state.
@immutable
final class Results {
  const Results({
    this.availability = const <PharmacyAvailabilityRow>[],
    this.comparisonLocation,
    this.stockOrders = const <PharmacyStockOrder>[],
    this.failure,
  });

  final List<PharmacyAvailabilityRow> availability;
  final PharmacyLocation? comparisonLocation;
  final List<PharmacyStockOrder> stockOrders;
  final AppFailure? failure;
}
