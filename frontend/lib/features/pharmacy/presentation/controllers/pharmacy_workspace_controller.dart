import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/realtime/realtime_event_groups.dart';
import 'package:hosspi_hms/core/realtime/realtime_message.dart';
import 'package:hosspi_hms/core/realtime/realtime_refresh.dart';
import 'package:hosspi_hms/core/security/session_controller.dart';
import 'package:hosspi_hms/core/security/session_isolation.dart';
import 'package:hosspi_hms/core/security/session_state.dart';
import 'package:hosspi_hms/core/workspace/workspace_adaptive_polling.dart';
import 'package:hosspi_hms/core/workspace/workspace_event_refresh_plan.dart';
import 'package:hosspi_hms/core/workspace/workspace_fast_sync.dart';
import 'package:hosspi_hms/core/workspace/workspace_session_guard.dart';
import 'package:hosspi_hms/features/home/presentation/controllers/home_dashboard_mutation.dart';
import 'package:hosspi_hms/features/pharmacy/data/repositories/pharmacy_repository_impl.dart';
import 'package:hosspi_hms/features/pharmacy/domain/entities/pharmacy_drug_import.dart';
import 'package:hosspi_hms/features/pharmacy/domain/entities/pharmacy_entities.dart';
import 'package:hosspi_hms/features/pharmacy/domain/repositories/pharmacy_repository.dart';
import 'package:hosspi_hms/shared/data/data.dart';

final pharmacyWorkspaceControllerProvider =
    AsyncNotifierProvider<
      PharmacyWorkspaceController,
      Result<PharmacyWorkspaceState>
    >(PharmacyWorkspaceController.new);

final class PharmacyWorkspaceController
    extends AsyncNotifier<Result<PharmacyWorkspaceState>> {
  static const Duration _syncInterval = Duration(seconds: 10);

  PharmacyRepository get _repository => ref.read(pharmacyRepositoryProvider);

  final WorkspaceAdaptivePolling _adaptivePolling = WorkspaceAdaptivePolling();
  final WorkspacePendingRefresh _pendingRefresh = WorkspacePendingRefresh();
  bool _isSyncing = false;
  bool _disposed = false;

  @override
  Future<Result<PharmacyWorkspaceState>> build() async {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    watchSessionEpoch(ref);
    listenForRealtimeRefresh(
      ref: ref,
      events: RealtimeEventGroups.pharmacyWorkspace,
      includeCrudMutations: true,
      shouldDefer: () => _isSyncing || (_currentState?.isSaving ?? false),
      onRefresh: _syncFromRealtime,
    );
    final Result<PharmacyWorkspaceState> result = await runWorkspaceInitialLoad(
      ref,
      _loadInitialState,
    );
    _startAdaptivePolling();
    return result;
  }

  Future<void> _syncFromRealtime(RealtimeMessage message) async {
    if (_isSyncing || (_currentState?.isSaving ?? false)) {
      _pendingRefresh.defer(
        WorkspaceEventRefreshPlan.forMessage(
          message,
          profile: WorkspaceRefreshProfile.pharmacy,
        ),
      );
      return;
    }
    final WorkspaceRefreshPlan plan = WorkspaceEventRefreshPlan.forMessage(
      message,
      profile: WorkspaceRefreshProfile.pharmacy,
    );
    if (plan.isEmpty) {
      return;
    }
    await _syncVisibleData(plan: plan);
  }

  Future<AppFailure?> refresh({
    bool refreshCatalog = true,
    bool refreshInventory = true,
  }) {
    return _syncVisibleData(
      showLoading: true,
      plan: WorkspaceRefreshPlan(
        primaryList: true,
        selectedDetail: true,
        catalogs: refreshCatalog,
        inventory: refreshInventory || refreshCatalog,
      ),
    );
  }

  /// Soft-refresh pharmacist home KPIs/charts without remounting the home shell.
  void _notifyHomeDashboard() {
    if (_disposed) {
      return;
    }
    homeInvalidateDashboard(ref);
  }

  Future<AppFailure?> applySearch(String search) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return refresh();
    }

    _emit(
      current.copyWith(
        query: current.query.copyWith(
          search: search.trim(),
          pageRequest: current.query.pageRequest.first(),
        ),
        isRefreshingOrders: true,
        clearLastFailure: true,
      ),
    );
    return _refreshOrders(showLoading: true);
  }

  Future<AppFailure?> applyFilter(PharmacyOrderFilter filter) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return refresh();
    }

    _emit(
      current.copyWith(
        query: PharmacyWorkbenchQuery.fromChip(filter).copyWith(
          search: current.query.search,
          pageRequest: current.query.pageRequest.first(),
        ),
        isRefreshingOrders: true,
        clearLastFailure: true,
      ),
    );
    return _refreshOrders(showLoading: true);
  }

  Future<AppFailure?> applyAdvancedFilters(PharmacyWorkbenchQuery query) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return refresh();
    }

    _emit(
      current.copyWith(
        query: query.copyWith(
          search: current.query.search,
          pageRequest: current.query.pageRequest.first(),
        ),
        isRefreshingOrders: true,
        clearLastFailure: true,
      ),
    );
    return _refreshOrders(showLoading: true);
  }

  Future<AppFailure?> changePage(AppPageRequest request) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return refresh();
    }

    _emit(
      current.copyWith(
        query: current.query.copyWith(pageRequest: request),
        isRefreshingOrders: true,
        clearLastFailure: true,
      ),
    );
    return _refreshOrders(showLoading: true);
  }

  Future<Result<List<PharmacyOrder>>> loadMatchingOrders() {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return Future<Result<List<PharmacyOrder>>>.value(
        const Result<List<PharmacyOrder>>.success(<PharmacyOrder>[]),
      );
    }
    final PharmacyWorkbenchQuery query = current.query;
    return loadMatchingAppPageItems<PharmacyOrder>(
      loadPage: (AppPageRequest request) async {
        final Result<PharmacyWorkbench> result = await _repository
            .loadWorkbench(query.copyWith(pageRequest: request));
        return result.map((PharmacyWorkbench workbench) => workbench.orders);
      },
    );
  }

  Future<AppFailure?> selectOrder(PharmacyOrder order) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return refresh();
    }

    _emit(current.copyWith(isRefreshingDetail: true, clearLastFailure: true));
    final Result<PharmacyOrderWorkflow> result = await _repository
        .loadOrderWorkflow(order.id);
    return result.when(
      success: (PharmacyOrderWorkflow workflow) {
        final PharmacyWorkspaceState? latest = _currentState;
        if (latest != null) {
          // Prefer workflow items; fall back to the worklist row snapshot when
          // the workflow payload omits lines so detail never looks empty.
          final PharmacyOrderWorkflow resolved = _withFallbackItems(
            workflow,
            order,
          );
          _emit(
            latest.copyWith(
              selectedWorkflow: resolved,
              workbench: _replaceOrder(latest.workbench, resolved.order),
              isRefreshingDetail: false,
            ),
          );
        }
        return null;
      },
      failure: (AppFailure failure) {
        final PharmacyWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(
            latest.copyWith(isRefreshingDetail: false, lastFailure: failure),
          );
        }
        return failure;
      },
    );
  }

  Future<AppFailure?> applyDrugSearch(String search) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return refresh();
    }

    _emit(
      current.copyWith(
        drugQuery: current.drugQuery.copyWith(
          search: search.trim(),
          pageRequest: current.drugQuery.pageRequest.first(),
        ),
        isRefreshingDrugs: true,
        clearLastFailure: true,
      ),
    );
    return _refreshDrugs(showLoading: true);
  }

  Future<AppFailure?> applyDrugStockStatus(String? stockStatus) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return refresh();
    }

    _emit(
      current.copyWith(
        drugQuery: current.drugQuery.copyWith(
          stockStatus: stockStatus,
          clearStockStatus: stockStatus == null,
          pageRequest: current.drugQuery.pageRequest.first(),
        ),
        isRefreshingDrugs: true,
        clearLastFailure: true,
      ),
    );
    return _refreshDrugs(showLoading: true);
  }

  Future<AppFailure?> applyDrugStorageFilter({
    String? storageRoomId,
    String? storageShelfId,
    bool clearStorageRoomId = false,
    bool clearStorageShelfId = false,
  }) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return refresh();
    }

    _emit(
      current.copyWith(
        drugQuery: current.drugQuery.copyWith(
          storageRoomId: storageRoomId,
          storageShelfId: storageShelfId,
          clearStorageRoomId: clearStorageRoomId,
          clearStorageShelfId: clearStorageShelfId,
          pageRequest: current.drugQuery.pageRequest.first(),
        ),
        isRefreshingDrugs: true,
        clearLastFailure: true,
      ),
    );
    return _refreshDrugs(showLoading: true);
  }

  Future<AppFailure?> changeDrugPage(AppPageRequest request) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return refresh();
    }

    _emit(
      current.copyWith(
        drugQuery: current.drugQuery.copyWith(pageRequest: request),
        isRefreshingDrugs: true,
        clearLastFailure: true,
      ),
    );
    return _refreshDrugs(showLoading: true);
  }

  Future<AppFailure?> applyFormularySearch(String search) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return refresh();
    }

    _emit(
      current.copyWith(
        formularyQuery: current.formularyQuery.copyWith(
          search: search.trim(),
          pageRequest: current.formularyQuery.pageRequest.first(),
        ),
        isRefreshingFormulary: true,
        clearLastFailure: true,
      ),
    );
    return _refreshFormulary(showLoading: true);
  }

  Future<AppFailure?> changeFormularyPage(AppPageRequest request) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return refresh();
    }

    _emit(
      current.copyWith(
        formularyQuery: current.formularyQuery.copyWith(pageRequest: request),
        isRefreshingFormulary: true,
        clearLastFailure: true,
      ),
    );
    return _refreshFormulary(showLoading: true);
  }

  Future<AppFailure?> applyFormularyActiveFilter({
    bool? isActive,
    bool clearIsActive = false,
  }) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return refresh();
    }

    _emit(
      current.copyWith(
        formularyQuery: current.formularyQuery.copyWith(
          isActive: isActive,
          clearIsActive: clearIsActive,
          pageRequest: current.formularyQuery.pageRequest.first(),
        ),
        isRefreshingFormulary: true,
        clearLastFailure: true,
      ),
    );
    return _refreshFormulary(showLoading: true);
  }

  Future<AppFailure?> applyFormularyCatalogFilters({
    String? name,
    String? code,
    String? form,
    String? strength,
    bool? isActive,
    bool clearIsActive = false,
    bool clearAll = false,
  }) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return refresh();
    }

    if (clearAll) {
      _emit(
        current.copyWith(
          formularyQuery: PharmacyFormularyQuery(
            search: current.formularyQuery.search,
            pageRequest: current.formularyQuery.pageRequest.first(),
          ),
          isRefreshingFormulary: true,
          clearLastFailure: true,
        ),
      );
      return _refreshFormulary(showLoading: true);
    }

    _emit(
      current.copyWith(
        formularyQuery: current.formularyQuery.copyWith(
          name: name,
          code: code,
          form: form,
          strength: strength,
          isActive: isActive,
          clearName: name == null,
          clearCode: code == null,
          clearForm: form == null,
          clearStrength: strength == null,
          clearIsActive: clearIsActive || isActive == null,
          pageRequest: current.formularyQuery.pageRequest.first(),
        ),
        isRefreshingFormulary: true,
        clearLastFailure: true,
      ),
    );
    return _refreshFormulary(showLoading: true);
  }

  Future<AppFailure?> clearFormularyFilters() async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return refresh();
    }

    _emit(
      current.copyWith(
        formularyQuery: PharmacyFormularyQuery(
          search: current.formularyQuery.search,
          pageRequest: current.formularyQuery.pageRequest.first(),
        ),
        isRefreshingFormulary: true,
        clearLastFailure: true,
      ),
    );
    return _refreshFormulary(showLoading: true);
  }

  Future<AppFailure?> applyDrugCatalogFilters({
    String? stockStatus,
    String? storageRoomId,
    String? storageShelfId,
    String? name,
    String? code,
    String? form,
    String? strength,
    bool clearAll = false,
  }) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return refresh();
    }

    if (clearAll) {
      _emit(
        current.copyWith(
          drugQuery: PharmacyDrugQuery(
            search: current.drugQuery.search,
            pageRequest: current.drugQuery.pageRequest.first(),
          ),
          isRefreshingDrugs: true,
          clearLastFailure: true,
        ),
      );
      return _refreshDrugs(showLoading: true);
    }

    String? resolvedShelfId = storageShelfId;
    if (storageRoomId != null &&
        storageShelfId != null &&
        !_shelfBelongsToRoom(
          current.storageLayout,
          storageRoomId,
          storageShelfId,
        )) {
      resolvedShelfId = null;
    }

    _emit(
      current.copyWith(
        drugQuery: current.drugQuery.copyWith(
          stockStatus: stockStatus,
          clearStockStatus: stockStatus == null,
          storageRoomId: storageRoomId,
          storageShelfId: resolvedShelfId,
          clearStorageRoomId: storageRoomId == null,
          clearStorageShelfId: resolvedShelfId == null,
          name: name,
          clearName: name == null,
          code: code,
          clearCode: code == null,
          form: form,
          clearForm: form == null,
          strength: strength,
          clearStrength: strength == null,
          pageRequest: current.drugQuery.pageRequest.first(),
        ),
        isRefreshingDrugs: true,
        clearLastFailure: true,
      ),
    );
    return _refreshDrugs(showLoading: true);
  }

  Future<AppFailure?> applyInventoryCatalogFilters({
    String? stockStatusChoice,
    String? storageRoomId,
    String? storageShelfId,
    String? itemName,
    String? sku,
    String? facilityName,
    bool? pendingStockOnly,
    bool clearPendingStockOnly = false,
    bool clearAll = false,
  }) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return refresh();
    }

    if (clearAll) {
      return clearInventoryFilters();
    }

    String? resolvedShelfId = storageShelfId;
    if (storageRoomId != null &&
        storageShelfId != null &&
        !_shelfBelongsToRoom(
          current.storageLayout,
          storageRoomId,
          storageShelfId,
        )) {
      resolvedShelfId = null;
    }

    final String? normalizedStatus = stockStatusChoice?.trim().toUpperCase();
    final bool isStockStatusFilter =
        normalizedStatus == 'IN_STOCK' ||
        normalizedStatus == 'ALMOST_OUT_OF_STOCK' ||
        normalizedStatus == 'LOW_STOCK' ||
        normalizedStatus == 'OUT_OF_STOCK';

    final PharmacyInventoryStockQuery nextQuery = current.inventoryQuery
        .copyWith(
          storageRoomId: storageRoomId,
          storageShelfId: resolvedShelfId,
          clearStorageRoomId: storageRoomId == null,
          clearStorageShelfId: resolvedShelfId == null,
          itemName: itemName,
          sku: sku,
          facilityName: facilityName,
          clearItemName: itemName == null,
          clearSku: sku == null,
          clearFacilityName: facilityName == null,
          pendingStockOnly: pendingStockOnly,
          clearPendingStockOnly:
              clearPendingStockOnly || pendingStockOnly == null,
          lowStockOnly: false,
          expiredOnly: normalizedStatus == 'EXPIRED',
          expiringWithinDays: normalizedStatus == 'EXPIRING_SOON' ? 30 : null,
          stockStatus: isStockStatusFilter ? normalizedStatus : null,
          clearStockStatus: !isStockStatusFilter,
          clearExpiringWithinDays: normalizedStatus != 'EXPIRING_SOON',
          pageRequest: current.inventoryQuery.pageRequest.first(),
        );

    _emit(
      current.copyWith(
        inventoryQuery: nextQuery,
        isRefreshingInventory: true,
        clearLastFailure: true,
      ),
    );
    return _refreshInventory(showLoading: true);
  }

  bool _shelfBelongsToRoom(
    PharmacyStorageLayout layout,
    String roomId,
    String shelfId,
  ) {
    return layout.rooms
        .where((PharmacyStorageRoom room) => room.id == roomId)
        .expand((PharmacyStorageRoom room) => room.shelves)
        .any((PharmacyStorageShelf shelf) => shelf.id == shelfId);
  }

  Future<AppFailure?> applyInventorySearch(String search) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return refresh();
    }

    _emit(
      current.copyWith(
        inventoryQuery: current.inventoryQuery.copyWith(
          search: search.trim(),
          pageRequest: current.inventoryQuery.pageRequest.first(),
        ),
        isRefreshingInventory: true,
        clearLastFailure: true,
      ),
    );
    return _refreshInventory(showLoading: true);
  }

  Future<AppFailure?> applyInventoryLowStockOnly(bool lowStockOnly) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return refresh();
    }

    _emit(
      current.copyWith(
        inventoryQuery: current.inventoryQuery.copyWith(
          lowStockOnly: lowStockOnly,
          clearStockStatus: !lowStockOnly,
          clearExpiringWithinDays: true,
          expiredOnly: false,
          pageRequest: current.inventoryQuery.pageRequest.first(),
        ),
        isRefreshingInventory: true,
        clearLastFailure: true,
      ),
    );
    return _refreshInventory(showLoading: true);
  }

  Future<AppFailure?> applyInventoryFilter(
    PharmacyInventoryFilter filter,
  ) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return refresh();
    }

    _emit(
      current.copyWith(
        catalogTab: PharmacyCatalogTab.inventory,
        inventoryQuery: PharmacyInventoryStockQuery.forFilter(filter).copyWith(
          search: current.inventoryQuery.search,
          pageRequest: current.inventoryQuery.pageRequest.first(),
        ),
        isRefreshingInventory: true,
        clearLastFailure: true,
      ),
    );
    return _refreshInventory(showLoading: true);
  }

  /// Loads Catalog → Inventory with the desk stock-alert filter applied.
  ///
  /// Sibling badges stay on [PharmacyWorkspaceState.stockAlertSummary]; the
  /// active stock-alert tab badge uses filtered inventory
  /// `stocks.totalItemCount`. The UI reuses the Catalog Inventory table.
  Future<AppFailure?> applyDeskStockFilter(
    PharmacyInventoryStockQuery query,
  ) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return refresh();
    }

    _emit(
      current.copyWith(
        catalogTab: PharmacyCatalogTab.inventory,
        inventoryQuery: query.copyWith(facilityId: resolveFacilityId()),
        isRefreshingInventory: true,
        clearLastFailure: true,
      ),
    );
    final AppFailure? failure = await _refreshInventory(showLoading: true);
    unawaited(_refreshStockAlertSummary());
    return failure;
  }

  Future<AppFailure?> applyInventoryStockStatus(String? stockStatus) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return refresh();
    }

    _emit(
      current.copyWith(
        inventoryQuery: current.inventoryQuery.copyWith(
          stockStatus: stockStatus,
          clearStockStatus: stockStatus == null,
          lowStockOnly: false,
          clearExpiringWithinDays: true,
          expiredOnly: false,
          pageRequest: current.inventoryQuery.pageRequest.first(),
        ),
        isRefreshingInventory: true,
        clearLastFailure: true,
      ),
    );
    return _refreshInventory(showLoading: true);
  }

  Future<AppFailure?> clearInventoryFilters() async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return refresh();
    }

    _emit(
      current.copyWith(
        inventoryQuery: PharmacyInventoryStockQuery(
          search: current.inventoryQuery.search,
          pageRequest: current.inventoryQuery.pageRequest.first(),
        ),
        isRefreshingInventory: true,
        clearLastFailure: true,
      ),
    );
    return _refreshInventory(showLoading: true);
  }

  Future<AppFailure?> applyInventoryStorageFilter({
    String? storageRoomId,
    String? storageShelfId,
    bool clearStorageRoomId = false,
    bool clearStorageShelfId = false,
  }) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return refresh();
    }

    _emit(
      current.copyWith(
        inventoryQuery: current.inventoryQuery.copyWith(
          storageRoomId: storageRoomId,
          storageShelfId: storageShelfId,
          clearStorageRoomId: clearStorageRoomId,
          clearStorageShelfId: clearStorageShelfId,
          pageRequest: current.inventoryQuery.pageRequest.first(),
        ),
        isRefreshingInventory: true,
        clearLastFailure: true,
      ),
    );
    return _refreshInventory(showLoading: true);
  }

  Future<AppFailure?> changeInventoryPage(AppPageRequest request) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return refresh();
    }

    _emit(
      current.copyWith(
        inventoryQuery: current.inventoryQuery.copyWith(pageRequest: request),
        isRefreshingInventory: true,
        clearLastFailure: true,
      ),
    );
    return _refreshInventory(showLoading: true);
  }

  /// Currently selected nested catalog tab, defaulting to Drugs before load.
  PharmacyCatalogTab get currentCatalogTab =>
      _currentState?.catalogTab ?? PharmacyCatalogTab.drugs;

  /// Loads drugs for nested pickers without mutating Catalog Drugs filters.
  Future<Result<AppPage<PharmacyDrug>>> loadDrugPickerPage({
    String search = '',
  }) {
    return _repository.searchDrugs(
      _scopedDrugQuery(
        PharmacyDrugQuery(
          search: search,
          pageRequest: const AppPageRequest(
            pageSize: AppPageRequest.maxPageSize,
          ),
        ),
      ),
    );
  }

  /// Loads suppliers for drug-edit pickers without mutating Catalog Suppliers filters.
  Future<Result<AppPage<PharmacySupplier>>> loadSupplierPickerPage({
    String search = '',
  }) {
    return _repository.listSuppliers(PharmacySupplierQuery(search: search));
  }

  Future<AppFailure?> applySupplierSearch(String search) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return refresh();
    }

    _emit(
      current.copyWith(
        supplierQuery: current.supplierQuery.copyWith(
          search: search.trim(),
          pageRequest: current.supplierQuery.pageRequest.first(),
        ),
        isRefreshingSuppliers: true,
        clearLastFailure: true,
      ),
    );
    return _refreshSuppliers(showLoading: true);
  }

  Future<AppFailure?> setSupplierPage(AppPageRequest request) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return refresh();
    }

    _emit(
      current.copyWith(
        supplierQuery: current.supplierQuery.copyWith(pageRequest: request),
        isRefreshingSuppliers: true,
        clearLastFailure: true,
      ),
    );
    return _refreshSuppliers(showLoading: true);
  }

  Future<Result<PharmacySupplier>> createSupplier(
    PharmacySupplierInput input,
  ) async {
    final Result<PharmacySupplier> result = await _repository.createSupplier(
      input,
    );
    if (result.isSuccess) {
      await _refreshSuppliers();
    }
    return result;
  }

  Future<Result<PharmacySupplierSimilarityResult>> checkSupplierSimilarity({
    required String name,
    String? contactEmail,
    String? phone,
    String? location,
    String? excludeSupplierId,
  }) {
    return _repository.checkSupplierSimilarity(
      name: name,
      contactEmail: contactEmail,
      phone: phone,
      location: location,
      tenantId: resolveTenantId(),
      excludeSupplierId: excludeSupplierId,
    );
  }

  Future<Result<PharmacySupplier>> updateSupplier(
    String supplierId,
    PharmacySupplierUpdateInput input,
  ) async {
    final Result<PharmacySupplier> result = await _repository.updateSupplier(
      supplierId,
      input,
    );
    if (result.isSuccess) {
      await _refreshSuppliers();
    }
    return result;
  }

  Future<AppFailure?> deleteSupplier(String supplierId) async {
    final Result<void> result = await _repository.deleteSupplier(supplierId);
    return result.when(
      success: (_) async {
        await _refreshSuppliers();
        return null;
      },
      failure: (AppFailure failure) => failure,
    );
  }

  void setCatalogTab(PharmacyCatalogTab tab) {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null || current.catalogTab == tab) {
      return;
    }
    _emit(current.copyWith(catalogTab: tab));
    _refreshCatalogTabData(tab, current);
  }

  void prepareCatalogTab(PharmacyCatalogTab tab) {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return;
    }
    if (current.catalogTab != tab) {
      _emit(current.copyWith(catalogTab: tab));
    }
    _refreshCatalogTabData(tab, current);
  }

  void _refreshCatalogTabData(
    PharmacyCatalogTab tab,
    PharmacyWorkspaceState current,
  ) {
    switch (tab) {
      case PharmacyCatalogTab.drugs:
        unawaited(_refreshDrugs(showLoading: current.drugs.items.isEmpty));
      case PharmacyCatalogTab.formulary:
        unawaited(
          _refreshFormulary(showLoading: current.formularyItems.items.isEmpty),
        );
      case PharmacyCatalogTab.inventory:
        unawaited(
          _refreshInventory(
            showLoading: current.inventoryWorkbench.stocks.items.isEmpty,
          ),
        );
      case PharmacyCatalogTab.storageLayout:
      case PharmacyCatalogTab.shelves:
        unawaited(
          _refreshStorageLayout(
            showLoading: current.storageLayout.rooms.isEmpty,
          ),
        );
      case PharmacyCatalogTab.stockOrders:
        // Owned by pharmacyLocationControllerProvider, which loads itself and
        // refreshes on pharmacy realtime events.
        break;
    }
  }

  /// Hydrates the desk Suppliers section (not a nested Catalog tab).
  void prepareSuppliers() {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return;
    }
    unawaited(
      _refreshSuppliers(showLoading: current.suppliers.items.isEmpty),
    );
  }

  Future<AppFailure?> _refreshSuppliers({bool showLoading = false}) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return null;
    }
    if (showLoading) {
      _emit(current.copyWith(isRefreshingSuppliers: true));
    }
    final Result<AppPage<PharmacySupplier>> result = await _repository
        .listSuppliers(current.supplierQuery);
    return result.when(
      success: (AppPage<PharmacySupplier> suppliers) {
        final PharmacyWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(
            latest.copyWith(
              suppliers: suppliers,
              isRefreshingSuppliers: false,
              clearLastFailure: true,
            ),
          );
        }
        return null;
      },
      failure: (AppFailure failure) {
        final PharmacyWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(
            latest.copyWith(
              isRefreshingSuppliers: false,
              lastFailure: failure,
            ),
          );
        }
        return failure;
      },
    );
  }

  Future<void> _refreshStorageLayout({
    bool showLoading = false,
    bool includeDeleted = false,
  }) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return;
    }
    if (showLoading) {
      _emit(current.copyWith(isRefreshingStorage: true));
    }
    final Result<PharmacyStorageLayout> result = await _repository
        .loadStorageLayout(
          includeInactive: true,
          includeDeleted: true,
          facilityId: resolveFacilityId(),
        );
    final PharmacyWorkspaceState? latest = _currentState;
    if (latest == null) {
      return;
    }
    result.when(
      success: (PharmacyStorageLayout layout) {
        _emit(
          latest.copyWith(storageLayout: layout, isRefreshingStorage: false),
        );
      },
      failure: (_) {
        _emit(latest.copyWith(isRefreshingStorage: false));
      },
    );
  }

  Future<Result<PharmacyStorageRoomSimilarityResult>>
  checkStorageRoomSimilarity({
    required String name,
    String? code,
    String? excludeRoomId,
  }) {
    return _repository.checkStorageRoomSimilarity(
      name: name,
      code: code,
      facilityId: resolveFacilityId(),
      excludeRoomId: excludeRoomId,
    );
  }

  Future<Result<PharmacyStorageShelfSimilarityResult>>
  checkStorageShelfSimilarity({
    required String roomId,
    required String label,
    String? shelfCode,
    String? excludeShelfId,
  }) {
    return _repository.checkStorageShelfSimilarity(
      roomId: roomId,
      label: label,
      shelfCode: shelfCode,
      excludeShelfId: excludeShelfId,
    );
  }

  Future<Result<PharmacyDrugSimilarityResult>> checkDrugSimilarity({
    required String genericName,
    String? name,
    String? brandName,
    String? code,
    String? form,
    String? strength,
    String? tenantId,
    String? excludeDrugId,
  }) {
    return _repository.checkDrugSimilarity(
      genericName: genericName,
      name: name,
      brandName: brandName,
      code: code,
      form: form,
      strength: strength,
      tenantId: tenantId ?? resolveTenantId(),
      excludeDrugId: excludeDrugId,
    );
  }

  Future<Result<PharmacyStorageRoom>> createStorageRoom(
    PharmacyStorageRoomInput input,
  ) async {
    final Result<PharmacyStorageRoom> result = await _repository
        .createStorageRoom(input);
    if (result.isSuccess) {
      await _refreshStorageLayout(includeDeleted: true);
    }
    return result;
  }

  Future<Result<PharmacyStorageRoom>> updateStorageRoom(
    String roomId,
    PharmacyStorageRoomUpdateInput input,
  ) async {
    final Result<PharmacyStorageRoom> result = await _repository
        .updateStorageRoom(roomId, input);
    if (result.isSuccess) {
      await _refreshStorageLayout(includeDeleted: true);
    }
    return result;
  }

  Future<Result<PharmacyStorageShelf>> createStorageShelf(
    String roomId,
    PharmacyStorageShelfInput input,
  ) async {
    final Result<PharmacyStorageShelf> result = await _repository
        .createStorageShelf(roomId, input);
    if (result.isSuccess) {
      await _refreshStorageLayout();
    }
    return result;
  }

  Future<Result<PharmacyStorageShelf>> updateStorageShelf(
    String shelfId,
    PharmacyStorageShelfUpdateInput input,
  ) async {
    final Result<PharmacyStorageShelf> result = await _repository
        .updateStorageShelf(shelfId, input);
    if (result.isSuccess) {
      await _refreshStorageLayout();
    }
    return result;
  }

  Future<AppFailure?> deleteStorageRoom(String roomId) async {
    final Result<void> result = await _repository.deleteStorageRoom(roomId);
    return result.when(
      success: (_) async {
        await _refreshStorageLayout(includeDeleted: true);
        return null;
      },
      failure: (AppFailure failure) => failure,
    );
  }

  Future<Result<PharmacyStorageRoom>> restoreStorageRoom(String roomId) async {
    final Result<PharmacyStorageRoom> result = await _repository
        .restoreStorageRoom(roomId);
    if (result.isSuccess) {
      await _refreshStorageLayout(includeDeleted: true);
    }
    return result;
  }

  Future<AppFailure?> permanentDeleteStorageRoom(String roomId) async {
    final Result<void> result = await _repository.permanentDeleteStorageRoom(
      roomId,
    );
    return result.when(
      success: (_) async {
        await _refreshStorageLayout(includeDeleted: true);
        return null;
      },
      failure: (AppFailure failure) => failure,
    );
  }

  Future<AppFailure?> deleteStorageShelf(String shelfId) async {
    final Result<void> result = await _repository.deleteStorageShelf(shelfId);
    return result.when(
      success: (_) async {
        await _refreshStorageLayout();
        return null;
      },
      failure: (AppFailure failure) => failure,
    );
  }

  Future<Result<PharmacyDrugImportPreview>> previewDrugImport({
    required PharmacyDrugImportSource source,
    required PharmacyDrugImportFile file,
  }) {
    return _repository.previewDrugImport(source: source, file: file);
  }

  /// Applies a reviewed import, then reloads the catalog and stock it touched.
  Future<Result<PharmacyDrugImportResult>> commitDrugImport(
    PharmacyDrugImportCommitInput input,
  ) async {
    final Result<PharmacyDrugImportResult> result = await _repository
        .commitDrugImport(input);
    if (result case ResultSuccess<PharmacyDrugImportResult>()) {
      await _refreshDrugs(showLoading: false);
      await _refreshInventory(showLoading: false);
      unawaited(_refreshStockAlertSummary());
    }
    return result;
  }

  Future<Result<PharmacyDrug>> createDrug(
    PharmacyDrugInput input, {
    PharmacyFacilityOfferingInput? facilityOffering,
  }) async {
    final Result<PharmacyDrug> result = await _repository.createDrug(input);
    if (result case ResultFailure<PharmacyDrug>(failure: final failure)) {
      return Result<PharmacyDrug>.failure(failure);
    }

    PharmacyDrug created =
        (result as ResultSuccess<PharmacyDrug>).value;

    if (facilityOffering != null) {
      final Result<PharmacyDrug> offeringResult = await _repository
          .upsertFacilityOffering(
            created.id,
            PharmacyFacilityOfferingInput(
              unitPrice: facilityOffering.unitPrice,
              currency: facilityOffering.currency,
              isActive: facilityOffering.isActive,
              facilityId:
                  facilityOffering.facilityId ??
                  input.facilityId ??
                  resolveFacilityId(),
              defaultStorageShelfId:
                  facilityOffering.defaultStorageShelfId ??
                  input.storageShelfId,
            ),
          );
      if (offeringResult
          case ResultFailure<PharmacyDrug>(failure: final failure)) {
        return Result<PharmacyDrug>.failure(failure);
      }
      created = (offeringResult as ResultSuccess<PharmacyDrug>).value;
    } else if (input.storageShelfId != null) {
      final String? facilityId = input.facilityId ?? resolveFacilityId();
      if (facilityId != null) {
        final Result<PharmacyDrug> offeringResult = await _repository
            .upsertFacilityOffering(
              created.id,
              PharmacyFacilityOfferingInput(
                facilityId: facilityId,
                defaultStorageShelfId: input.storageShelfId,
              ),
            );
        if (offeringResult
            case ResultFailure<PharmacyDrug>(failure: final failure)) {
          return Result<PharmacyDrug>.failure(failure);
        }
        created = (offeringResult as ResultSuccess<PharmacyDrug>).value;
      }
    }

    await _refreshDrugs(showLoading: false);
    if (input.hasStockSetup) {
      await _refreshInventory(showLoading: false);
    }
    return Result<PharmacyDrug>.success(created);
  }

  Future<Result<PharmacyDrug>> updateDrug(
    String drugId,
    PharmacyDrugUpdateInput input, {
    PharmacyFacilityOfferingInput? facilityOffering,
  }) async {
    final Result<PharmacyDrug> result = await _repository.updateDrug(
      drugId,
      input,
    );
    if (result case ResultFailure<PharmacyDrug>(failure: final failure)) {
      return Result<PharmacyDrug>.failure(failure);
    }

    PharmacyDrug current = (result as ResultSuccess<PharmacyDrug>).value;
    if (facilityOffering != null) {
      final Result<PharmacyDrug> offeringResult = await _repository
          .upsertFacilityOffering(drugId, facilityOffering);
      if (offeringResult
          case ResultFailure<PharmacyDrug>(failure: final failure)) {
        return Result<PharmacyDrug>.failure(failure);
      }
      current = (offeringResult as ResultSuccess<PharmacyDrug>).value;
    }
    await _refreshDrugs(showLoading: false);
    return Result<PharmacyDrug>.success(
      _findDrugInState(drugId) ?? current,
    );
  }

  PharmacyDrug? _findDrugInState(String drugId) {
    final AsyncValue<Result<PharmacyWorkspaceState>> asyncState = state;
    if (!asyncState.hasValue) {
      return null;
    }
    PharmacyDrug? found;
    asyncState.requireValue.when(
      success: (PharmacyWorkspaceState value) {
        for (final PharmacyDrug item in value.drugs.items) {
          if (item.id == drugId) {
            found = item;
            return;
          }
        }
      },
      failure: (_) {},
    );
    return found;
  }

  Future<AppFailure?> upsertFacilityOffering(
    String drugId,
    PharmacyFacilityOfferingInput input,
  ) async {
    final Result<PharmacyDrug> result = await _repository
        .upsertFacilityOffering(drugId, input);
    return result.when(
      success: (_) async {
        await _refreshDrugs(showLoading: false);
        return null;
      },
      failure: (AppFailure failure) => failure,
    );
  }

  Future<AppFailure?> deleteDrug(String drugId) async {
    final Result<void> result = await _repository.deleteDrug(drugId);
    return result.when(
      success: (_) async {
        final PharmacyWorkspaceState? current = _currentState;
        if (current != null) {
          _emit(
            current.copyWith(
              drugQuery: current.drugQuery.copyWith(
                pageRequest: current.drugQuery.pageRequest.first(),
              ),
            ),
          );
        }
        await _refreshDrugs(showLoading: false);
        return null;
      },
      failure: (AppFailure failure) => failure,
    );
  }

  Future<AppFailure?> createFormularyItem(
    PharmacyFormularyItemInput input,
  ) async {
    final Result<PharmacyFormularyItem> result = await _repository
        .createFormularyItem(input);
    return result.when(
      success: (_) async {
        await _refreshFormulary(showLoading: false);
        return null;
      },
      failure: (AppFailure failure) => failure,
    );
  }

  Future<AppFailure?> updateFormularyItem(
    String formularyItemId, {
    bool? isActive,
  }) async {
    final Result<PharmacyFormularyItem> result = await _repository
        .updateFormularyItem(formularyItemId, isActive: isActive);
    return result.when(
      success: (_) async {
        await _refreshFormulary(showLoading: false);
        return null;
      },
      failure: (AppFailure failure) => failure,
    );
  }

  Future<AppFailure?> deleteFormularyItem(String formularyItemId) async {
    final Result<void> result = await _repository.deleteFormularyItem(
      formularyItemId,
    );
    return result.when(
      success: (_) async {
        await _refreshFormulary(showLoading: false);
        return null;
      },
      failure: (AppFailure failure) => failure,
    );
  }

  Future<AppFailure?> adjustInventoryStock(
    PharmacyInventoryAdjustInput input,
  ) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return AppFailure.validation();
    }

    _emit(current.copyWith(isSaving: true, clearLastFailure: true));
    final Result<PharmacyInventoryWorkbench> result = await _repository
        .adjustInventoryStock(input);
    return result.when(
      success: (_) async {
        final AppFailure? failure = await _refreshInventory(showLoading: false);
        // Keep Catalog & Stock drug rows (reorder / stock status) in sync.
        await _refreshDrugs(showLoading: false);
        unawaited(_refreshStockAlertSummary());
        final PharmacyWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(latest.copyWith(isSaving: false));
        }
        _notifyHomeDashboard();
        return failure;
      },
      failure: (AppFailure failure) {
        final PharmacyWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(latest.copyWith(isSaving: false, lastFailure: failure));
        }
        return failure;
      },
    );
  }

  Future<AppFailure?> recordOrderBilling(Map<String, Object?> billing) async {
    final PharmacyWorkspaceState? current = _currentState;
    final PharmacyOrderWorkflow? workflow = current?.selectedWorkflow;
    if (current == null || workflow == null) {
      return AppFailure.validation();
    }

    _emit(current.copyWith(isSaving: true, clearLastFailure: true));
    final Result<PharmacyOrderWorkflow> result = await _repository
        .recordOrderBilling(workflow.order.id, billing);
    return result.when(
      success: (PharmacyOrderWorkflow updated) {
        final PharmacyWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(
            latest.copyWith(
              selectedWorkflow: updated,
              workbench: _replaceOrder(latest.workbench, updated.order),
              isSaving: false,
            ),
          );
        }
        _notifyHomeDashboard();
        return null;
      },
      failure: (AppFailure failure) {
        final PharmacyWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(latest.copyWith(isSaving: false, lastFailure: failure));
        }
        return failure;
      },
    );
  }

  /// Creates a walk-in pharmacy order (no encounter), then refreshes the
  /// workbench and selects the new order workflow for detail follow-up.
  Future<AppFailure?> createPharmacyOrder(Map<String, Object?> payload) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return refresh();
    }

    _emit(current.copyWith(isSaving: true, clearLastFailure: true));
    final Result<PharmacyMutationResult> result = await _repository
        .createPharmacyOrder(payload);
    return result.when(
      success: (PharmacyMutationResult mutation) async {
        final PharmacyWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(
            latest.copyWith(
              selectedWorkflow: mutation.workflow,
              workbench: _replaceOrder(
                latest.workbench.copyWith(
                  summary: mutation.summary ?? latest.workbench.summary,
                ),
                mutation.workflow.order,
              ),
              isSaving: false,
            ),
          );
        }
        // Refresh the filtered worklist so the new order appears in queue tabs.
        await _refreshOrders(showLoading: false);
        final PharmacyWorkspaceState? afterRefresh = _currentState;
        if (afterRefresh != null) {
          _emit(
            afterRefresh.copyWith(selectedWorkflow: mutation.workflow),
          );
        }
        _notifyHomeDashboard();
        return null;
      },
      failure: (AppFailure failure) {
        final PharmacyWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(latest.copyWith(isSaving: false, lastFailure: failure));
        }
        return failure;
      },
    );
  }

  String? resolveTenantId() {
    final SessionState sessionState = ref.read(sessionStateProvider);
    return sessionState.session?.user?.tenantId;
  }

  String? resolveFacilityId() {
    final SessionState sessionState = ref.read(sessionStateProvider);
    return sessionState.session?.user?.facilityId;
  }

  PharmacyDrugQuery _scopedDrugQuery(PharmacyDrugQuery query) {
    final String? facilityId = resolveFacilityId();
    if (facilityId == null || query.facilityId != null) {
      return query;
    }
    return query.copyWith(facilityId: facilityId);
  }

  PharmacyInventoryStockQuery _scopedInventoryQuery(
    PharmacyInventoryStockQuery query,
  ) {
    final String? facilityId = resolveFacilityId();
    if (facilityId == null || query.facilityId != null) {
      return query;
    }
    return query.copyWith(facilityId: facilityId);
  }

  Future<AppFailure?> prepareDispense({
    required List<PharmacyDispenseLineInput> items,
    String? dispenseBatchRef,
    String? statement,
    String? reason,
  }) {
    return _mutateSelected(
      (PharmacyOrderWorkflow workflow) => _repository.prepareDispense(
        orderId: workflow.order.id,
        items: items,
        dispenseBatchRef: dispenseBatchRef,
        statement: statement,
        reason: reason,
      ),
      refreshDrugsAfter: true,
    );
  }

  Future<AppFailure?> attestDispense({
    required String dispenseBatchRef,
    String? statement,
    String? reason,
  }) {
    return _mutateSelected(
      (PharmacyOrderWorkflow workflow) => _repository.attestDispense(
        orderId: workflow.order.id,
        dispenseBatchRef: dispenseBatchRef,
        statement: statement,
        reason: reason,
        attestedAt: DateTime.now(),
      ),
      refreshDrugsAfter: true,
    );
  }

  Future<AppFailure?> cancelOrder({required String reason, String? notes}) {
    return _mutateSelected(
      (PharmacyOrderWorkflow workflow) => _repository.cancelOrder(
        orderId: workflow.order.id,
        reason: reason,
        notes: notes,
      ),
    );
  }

  Future<AppFailure?> cancelOrderItem({
    required String itemId,
    required String reason,
    String? notes,
  }) {
    return _mutateSelected(
      (PharmacyOrderWorkflow workflow) => _repository.cancelOrderItem(
        orderId: workflow.order.id,
        itemId: itemId,
        reason: reason,
        notes: notes,
      ),
    );
  }

  Future<AppFailure?> returnDispense({
    required List<PharmacyReturnLineInput> items,
    String? reason,
    String? notes,
  }) {
    return _mutateSelected(
      (PharmacyOrderWorkflow workflow) => _repository.returnDispense(
        orderId: workflow.order.id,
        items: items,
        reason: reason,
        notes: notes,
      ),
      refreshDrugsAfter: true,
    );
  }

  Future<Result<PharmacyWorkspaceState>> _loadInitialState() async {
    const PharmacyWorkbenchQuery query = PharmacyWorkbenchQuery();
    final String? facilityId = resolveFacilityId();
    final PharmacyDrugQuery drugQuery = PharmacyDrugQuery(
      facilityId: facilityId,
    );
    const PharmacyFormularyQuery formularyQuery = PharmacyFormularyQuery();
    final PharmacyInventoryStockQuery inventoryQuery =
        PharmacyInventoryStockQuery(facilityId: facilityId);
    final Result<PharmacyWorkbench> workbenchResult = await _repository
        .loadWorkbench(query);
    final PharmacyWorkbench? workbench = _successOrNull(workbenchResult);
    if (workbench == null) {
      return Result<PharmacyWorkspaceState>.failure(
        _failureOrNull(workbenchResult)!,
      );
    }

    final List<Future<Object?>> initialLoads = <Future<Object?>>[
      _loadDrugPage(drugQuery),
      _repository
          .getInventoryStock(inventoryQuery)
          .then(
            (Result<PharmacyInventoryWorkbench> result) => result.when(
              success: (PharmacyInventoryWorkbench value) => value,
              failure: (_) => null,
            ),
          ),
      _repository
          .loadStorageLayout(facilityId: facilityId)
          .then(
            (Result<PharmacyStorageLayout> result) => result.when(
              success: (PharmacyStorageLayout value) => value,
              failure: (_) => null,
            ),
          ),
    ];
    final List<Object?> loadResults = await Future.wait(initialLoads);
    final AppPage<PharmacyDrug> drugs =
        loadResults[0]! as AppPage<PharmacyDrug>;
    final PharmacyInventoryWorkbench inventoryWorkbench =
        loadResults[1] as PharmacyInventoryWorkbench? ??
        PharmacyInventoryWorkbench(
          summary: const PharmacyInventoryStockSummary(),
          stocks: AppPage<PharmacyInventoryStock>(
            items: const <PharmacyInventoryStock>[],
            request: inventoryQuery.pageRequest,
            totalItemCount: 0,
          ),
        );
    final PharmacyStorageLayout storageLayout =
        loadResults[2] as PharmacyStorageLayout? ??
        const PharmacyStorageLayout();
    return Result<PharmacyWorkspaceState>.success(
      PharmacyWorkspaceState(
        query: query,
        workbench: workbench,
        drugQuery: drugQuery,
        drugs: drugs,
        formularyQuery: formularyQuery,
        formularyItems: AppPage<PharmacyFormularyItem>(
          items: const <PharmacyFormularyItem>[],
          request: formularyQuery.pageRequest,
          totalItemCount: 0,
        ),
        inventoryQuery: inventoryQuery,
        inventoryWorkbench: inventoryWorkbench,
        stockAlertSummary: inventoryWorkbench.summary,
        storageLayout: storageLayout,
      ),
    );
  }

  void _startAdaptivePolling() {
    installWorkspaceAdaptivePolling(
      ref: ref,
      polling: _adaptivePolling,
      intervalWhenDisconnected: _syncInterval,
      disconnectProfile: WorkspaceRefreshProfile.pharmacy,
      syncOnDisconnect: (WorkspaceRefreshPlan plan) =>
          _syncVisibleData(plan: plan),
    );
  }

  Future<AppFailure?> _syncVisibleData({
    bool showLoading = false,
    WorkspaceRefreshPlan plan = WorkspaceRefreshPlan.full,
  }) async {
    if (plan.isEmpty) {
      return null;
    }
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null || _isSyncing || current.isSaving) {
      _pendingRefresh.defer(plan);
      return null;
    }

    final bool refreshOrders = workspacePlanRefreshesPrimaryList(plan);
    final bool refreshCatalogs = plan.catalogs;
    final bool refreshInventory = plan.inventory;
    final bool refreshDetail = plan.selectedDetail;
    if (!refreshOrders &&
        !refreshCatalogs &&
        !refreshInventory &&
        !refreshDetail) {
      return null;
    }

    _isSyncing = true;
    if (showLoading) {
      _emit(
        current.copyWith(
          isRefreshingOrders: true,
          isRefreshingDetail: current.selectedWorkflow != null,
          isRefreshingDrugs: refreshCatalogs,
          isRefreshingFormulary: refreshCatalogs,
          isRefreshingInventory: refreshInventory,
          clearLastFailure: true,
        ),
      );
    }

    try {
      if (refreshOrders) {
        final AppFailure? failure = await _refreshOrders(
          showLoading: showLoading,
        );
        if (failure != null) {
          return failure;
        }
      }

      if (refreshCatalogs) {
        await _refreshDrugs(showLoading: showLoading);
        await _refreshFormulary(showLoading: showLoading);
      }
      if (refreshInventory) {
        await _refreshInventory(showLoading: showLoading);
        unawaited(_refreshStockAlertSummary());
      }

      if (refreshDetail) {
        final PharmacyOrderWorkflow? selected = _currentState?.selectedWorkflow;
        if (selected != null) {
          await selectOrder(selected.order);
        }
      }

      return null;
    } finally {
      final PharmacyWorkspaceState? latest = _currentState;
      if (showLoading && latest != null) {
        _emit(
          latest.copyWith(
            isRefreshingOrders: false,
            isRefreshingDetail: false,
            isRefreshingDrugs: false,
            isRefreshingFormulary: false,
            isRefreshingInventory: false,
          ),
        );
      }
      _isSyncing = false;
      if (_pendingRefresh.refreshPending &&
          !(_currentState?.isSaving ?? false)) {
        final WorkspaceRefreshPlan pendingPlan = _pendingRefresh.takePending();
        if (!pendingPlan.isEmpty) {
          unawaited(_syncVisibleData(plan: pendingPlan));
        }
      }
    }
  }

  Future<AppFailure?> _refreshOrders({required bool showLoading}) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return null;
    }

    final Result<PharmacyWorkbench> result = await _repository.loadWorkbench(
      current.query,
    );
    return result.when(
      success: (PharmacyWorkbench workbench) {
        final PharmacyWorkspaceState? latest = _currentState;
        if (latest != null) {
          final PharmacyOrderWorkflow? selected =
              _selectedAfterWorkbenchRefresh(
                workbench,
                latest.selectedWorkflow,
              );
          _emit(
            latest.copyWith(
              workbench: workbench,
              selectedWorkflow: selected,
              clearSelectedWorkflow:
                  latest.selectedWorkflow != null && selected == null,
              isRefreshingOrders: false,
              clearLastFailure: true,
            ),
          );
        }
        return null;
      },
      failure: (AppFailure failure) {
        final PharmacyWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(
            latest.copyWith(isRefreshingOrders: false, lastFailure: failure),
          );
        }
        return failure;
      },
    );
  }

  Future<AppFailure?> _refreshDrugs({required bool showLoading}) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return null;
    }

    final Result<AppPage<PharmacyDrug>> result = await _repository.searchDrugs(
      _scopedDrugQuery(current.drugQuery),
    );
    return result.when(
      success: (AppPage<PharmacyDrug> drugs) {
        final PharmacyWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(
            latest.copyWith(
              drugs: drugs,
              isRefreshingDrugs: false,
              clearLastFailure: true,
            ),
          );
        }
        return null;
      },
      failure: (AppFailure failure) {
        final PharmacyWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(
            latest.copyWith(isRefreshingDrugs: false, lastFailure: failure),
          );
        }
        return failure;
      },
    );
  }

  Future<AppFailure?> _refreshFormulary({required bool showLoading}) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return null;
    }

    final Result<AppPage<PharmacyFormularyItem>> result = await _repository
        .listFormularyItems(current.formularyQuery);
    return result.when(
      success: (AppPage<PharmacyFormularyItem> items) {
        final PharmacyWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(
            latest.copyWith(
              formularyItems: items,
              isRefreshingFormulary: false,
              clearLastFailure: true,
            ),
          );
        }
        return null;
      },
      failure: (AppFailure failure) {
        final PharmacyWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(
            latest.copyWith(isRefreshingFormulary: false, lastFailure: failure),
          );
        }
        return failure;
      },
    );
  }

  Future<AppFailure?> _refreshInventory({required bool showLoading}) async {
    final PharmacyWorkspaceState? current = _currentState;
    if (current == null) {
      return null;
    }

    final Result<PharmacyInventoryWorkbench> result = await _repository
        .getInventoryStock(_scopedInventoryQuery(current.inventoryQuery));
    return result.when(
      success: (PharmacyInventoryWorkbench workbench) {
        final PharmacyWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(
            latest.copyWith(
              inventoryWorkbench: workbench,
              isRefreshingInventory: false,
              clearLastFailure: true,
            ),
          );
        }
        return null;
      },
      failure: (AppFailure failure) {
        final PharmacyWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(
            latest.copyWith(isRefreshingInventory: false, lastFailure: failure),
          );
        }
        return failure;
      },
    );
  }

  /// Refreshes the unfiltered stock-alert counters used for the desk stock tab
  /// badges, independent of the active inventory filter.
  Future<void> _refreshStockAlertSummary() async {
    if (_disposed || _currentState == null) {
      return;
    }
    final Result<PharmacyInventoryWorkbench> result = await _repository
        .getInventoryStock(
          PharmacyInventoryStockQuery(facilityId: resolveFacilityId()),
        );
    if (_disposed) {
      return;
    }
    final PharmacyWorkspaceState? latest = _currentState;
    if (latest == null) {
      return;
    }
    result.when(
      success: (PharmacyInventoryWorkbench workbench) {
        _emit(latest.copyWith(stockAlertSummary: workbench.summary));
      },
      failure: (_) {},
    );
  }

  Future<AppPage<PharmacyDrug>> _loadDrugPage(PharmacyDrugQuery query) async {
    final Result<AppPage<PharmacyDrug>> result = await _repository.searchDrugs(
      _scopedDrugQuery(query),
    );
    return result.when(
      success: (AppPage<PharmacyDrug> drugs) => drugs,
      failure: (_) => AppPage<PharmacyDrug>(
        items: const <PharmacyDrug>[],
        request: query.pageRequest,
        totalItemCount: 0,
      ),
    );
  }

  Future<AppFailure?> _mutateSelected(
    Future<Result<PharmacyMutationResult>> Function(
      PharmacyOrderWorkflow workflow,
    )
    action, {
    bool refreshDrugsAfter = false,
  }) async {
    final PharmacyWorkspaceState? current = _currentState;
    final PharmacyOrderWorkflow? workflow = current?.selectedWorkflow;
    if (current == null || workflow == null) {
      return AppFailure.validation();
    }

    _emit(current.copyWith(isSaving: true, clearLastFailure: true));
    final Result<PharmacyMutationResult> result = await action(workflow);
    return result.when(
      success: (PharmacyMutationResult mutation) async {
        final PharmacyWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(
            latest.copyWith(
              selectedWorkflow: mutation.workflow,
              workbench: _replaceOrder(
                latest.workbench.copyWith(
                  summary: mutation.summary ?? latest.workbench.summary,
                ),
                mutation.workflow.order,
              ),
              isSaving: false,
            ),
          );
        }
        if (refreshDrugsAfter) {
          unawaited(_refreshDrugs(showLoading: false));
        }
        _notifyHomeDashboard();
        return null;
      },
      failure: (AppFailure failure) {
        final PharmacyWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(latest.copyWith(isSaving: false, lastFailure: failure));
        }
        return failure;
      },
    );
  }

  PharmacyOrderWorkflow? _selectedAfterWorkbenchRefresh(
    PharmacyWorkbench workbench,
    PharmacyOrderWorkflow? selected,
  ) {
    if (selected == null) {
      return null;
    }

    for (final PharmacyOrder item in workbench.orders.items) {
      if (_isSameOrder(item, selected.order)) {
        return PharmacyOrderWorkflow(
          order: selected.order.copyWith(
            status: item.status,
            updatedAt: item.updatedAt,
            itemCount: item.itemCount,
            quantityPrescribedTotal: item.quantityPrescribedTotal,
            quantityDispensedTotal: item.quantityDispensedTotal,
            quantityPendingTotal: item.quantityPendingTotal,
            quantityReturnedTotal: item.quantityReturnedTotal,
            quantityRemainingTotal: item.quantityRemainingTotal,
            pendingAttestationBatchCount: item.pendingAttestationBatchCount,
            pendingAttestationBatches: item.pendingAttestationBatches,
            paymentStatus: item.paymentStatus,
            billing: item.billing,
          ),
          items: selected.items,
          attestations: selected.attestations,
          timeline: selected.timeline,
          nextActions: selected.nextActions,
        );
      }
    }

    return selected;
  }

  PharmacyOrderWorkflow _withFallbackItems(
    PharmacyOrderWorkflow workflow,
    PharmacyOrder listOrder,
  ) {
    if (workflow.items.isNotEmpty || listOrder.items.isEmpty) {
      return workflow;
    }
    return PharmacyOrderWorkflow(
      order: workflow.order.copyWith(
        items: listOrder.items,
        itemCount: listOrder.items.length,
      ),
      items: listOrder.items,
      attestations: workflow.attestations,
      timeline: workflow.timeline,
      nextActions: workflow.nextActions,
    );
  }

  PharmacyWorkbench _replaceOrder(
    PharmacyWorkbench workbench,
    PharmacyOrder order,
  ) {
    var replaced = false;
    final List<PharmacyOrder> items = <PharmacyOrder>[];
    for (final PharmacyOrder item in workbench.orders.items) {
      if (_isSameOrder(item, order)) {
        if (!replaced) {
          items.add(order);
          replaced = true;
        }
      } else {
        items.add(item);
      }
    }

    if (!replaced) {
      items.insert(0, order);
    }

    return workbench.copyWith(
      orders: AppPage<PharmacyOrder>(
        items: items
            .take(workbench.orders.request.pageSize)
            .toList(growable: false),
        request: workbench.orders.request,
        totalItemCount: workbench.orders.totalItemCount == null || replaced
            ? workbench.orders.totalItemCount
            : workbench.orders.totalItemCount! + 1,
      ),
    );
  }

  bool _isSameOrder(PharmacyOrder left, PharmacyOrder right) {
    return left.id == right.id ||
        (left.displayId != null && left.displayId == right.displayId);
  }

  T? _successOrNull<T>(Result<T> result) {
    return result.when(success: (T value) => value, failure: (_) => null);
  }

  AppFailure? _failureOrNull<T>(Result<T> result) {
    return result.when(
      success: (_) => null,
      failure: (AppFailure failure) => failure,
    );
  }

  PharmacyWorkspaceState? get _currentState {
    final Result<PharmacyWorkspaceState>? currentResult = state.asData?.value;
    return switch (currentResult) {
      ResultSuccess<PharmacyWorkspaceState>(value: final value) => value,
      _ => null,
    };
  }

  void _emit(PharmacyWorkspaceState nextState) {
    state = AsyncData<Result<PharmacyWorkspaceState>>(
      Result<PharmacyWorkspaceState>.success(nextState),
    );
  }
}
