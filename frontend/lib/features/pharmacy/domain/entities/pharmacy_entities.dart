import 'package:flutter/foundation.dart';
import 'package:hosspi_hms/shared/data/data.dart';

enum PharmacyOrderFilter {
  all,
  ready,
  partial,
  completed,
  cancelled,
  pendingPayment,
  outpatient,
  ward,
  discharge,
  partialStock,
  urgent,
}

/// Desk worklist sections for the pharmacy workspace tab strip.
///
/// Order queues come first, followed by the stock-alert sections that surface
/// inventory health (`GET /inventory/stock`).
enum PharmacyDeskSection {
  queue,
  inProgress,
  pendingPayment,
  completed,
  cancelled,
  allOrders,
  catalog,
  suppliers,
  nearExpiry,
  expired,
  lowStock,
  outOfStock,
}

extension PharmacyDeskSectionX on PharmacyDeskSection {
  /// True for stock-alert desk sections that open Catalog → Inventory with a
  /// matching stock filter (not a separate alert-only table).
  bool get isStockSection {
    return switch (this) {
      PharmacyDeskSection.nearExpiry ||
      PharmacyDeskSection.expired ||
      PharmacyDeskSection.lowStock ||
      PharmacyDeskSection.outOfStock => true,
      PharmacyDeskSection.queue ||
      PharmacyDeskSection.inProgress ||
      PharmacyDeskSection.pendingPayment ||
      PharmacyDeskSection.completed ||
      PharmacyDeskSection.cancelled ||
      PharmacyDeskSection.catalog ||
      PharmacyDeskSection.suppliers ||
      PharmacyDeskSection.allOrders => false,
    };
  }

  /// True for the inline catalog-and-stock management section that hosts the
  /// nested Drugs / Formulary / Inventory / Storage / Shelves / Suppliers tabs.
  bool get isCatalogSection => this == PharmacyDeskSection.catalog;

  /// True for the desk tab that opens Catalog focused on the Suppliers nested
  /// tab (supplier CRUD).
  bool get isSuppliersSection => this == PharmacyDeskSection.suppliers;

  /// True when the desk section should render [PharmacyCatalogPanel].
  bool get opensCatalogPanel => isCatalogSection || isStockSection;

  /// True for order-queue desk tabs (not catalog, suppliers, or stock alerts).
  bool get isOrderSection {
    return switch (this) {
      PharmacyDeskSection.queue ||
      PharmacyDeskSection.inProgress ||
      PharmacyDeskSection.pendingPayment ||
      PharmacyDeskSection.completed ||
      PharmacyDeskSection.cancelled ||
      PharmacyDeskSection.allOrders => true,
      PharmacyDeskSection.catalog ||
      PharmacyDeskSection.suppliers ||
      PharmacyDeskSection.nearExpiry ||
      PharmacyDeskSection.expired ||
      PharmacyDeskSection.lowStock ||
      PharmacyDeskSection.outOfStock => false,
    };
  }

  /// Inventory stock query backing a stock section, or null for order sections.
  PharmacyInventoryStockQuery? get stockQuery {
    return switch (this) {
      PharmacyDeskSection.nearExpiry => const PharmacyInventoryStockQuery(
        expiringWithinDays: 30,
      ),
      PharmacyDeskSection.expired => const PharmacyInventoryStockQuery(
        expiredOnly: true,
      ),
      PharmacyDeskSection.lowStock => const PharmacyInventoryStockQuery(
        stockStatus: 'LOW_STOCK',
      ),
      PharmacyDeskSection.outOfStock => const PharmacyInventoryStockQuery(
        stockStatus: 'OUT_OF_STOCK',
      ),
      _ => null,
    };
  }
}

extension PharmacyOrderFilterX on PharmacyOrderFilter {
  String? get backendStatus {
    return switch (this) {
      PharmacyOrderFilter.ready => 'ORDERED',
      PharmacyOrderFilter.partial => 'PARTIALLY_DISPENSED',
      PharmacyOrderFilter.completed => 'DISPENSED',
      PharmacyOrderFilter.cancelled => 'CANCELLED',
      PharmacyOrderFilter.all ||
      PharmacyOrderFilter.pendingPayment ||
      PharmacyOrderFilter.outpatient ||
      PharmacyOrderFilter.ward ||
      PharmacyOrderFilter.discharge ||
      PharmacyOrderFilter.partialStock ||
      PharmacyOrderFilter.urgent => null,
    };
  }

  bool? get backendPendingPayment {
    if (this == PharmacyOrderFilter.pendingPayment) {
      return true;
    }
    return null;
  }

  String? get backendLocation {
    return switch (this) {
      PharmacyOrderFilter.outpatient => 'OUTPATIENT',
      PharmacyOrderFilter.ward => 'INPATIENT',
      PharmacyOrderFilter.discharge => 'DISCHARGE',
      _ => null,
    };
  }

  bool get isBackendBacked {
    return switch (this) {
      PharmacyOrderFilter.all ||
      PharmacyOrderFilter.ready ||
      PharmacyOrderFilter.partial ||
      PharmacyOrderFilter.completed ||
      PharmacyOrderFilter.cancelled ||
      PharmacyOrderFilter.pendingPayment ||
      PharmacyOrderFilter.outpatient ||
      PharmacyOrderFilter.ward ||
      PharmacyOrderFilter.discharge => true,
      PharmacyOrderFilter.partialStock || PharmacyOrderFilter.urgent => true,
    };
  }

  bool? get backendPartialStock {
    if (this == PharmacyOrderFilter.partialStock) {
      return true;
    }
    return null;
  }

  bool? get backendUrgent {
    if (this == PharmacyOrderFilter.urgent) {
      return true;
    }
    return null;
  }
}

enum PharmacyCatalogTab {
  drugs,
  formulary,
  inventory,
  storageLayout,
  shelves,

  /// Cross-pharmacy availability and the stock orders between pharmacies.
  ///
  /// Appended last on purpose: the catalog panel indexes its tab views by
  /// [PharmacyCatalogTab.index], so inserting earlier would shift them.
  stockOrders,
}

enum PharmacyInventoryFilter {
  lowStock,
  almostOutOfStock,
  expiringSoon,
  expired,
}

@immutable
final class PharmacyFormularyQuery {
  const PharmacyFormularyQuery({
    this.search = '',
    this.name,
    this.code,
    this.form,
    this.strength,
    this.isActive,
    this.pageRequest = const AppPageRequest(
      pageSize: AppPageRequest.maxPageSize,
    ),
  });

  final String search;
  final String? name;
  final String? code;
  final String? form;
  final String? strength;
  final bool? isActive;
  final AppPageRequest pageRequest;

  PharmacyFormularyQuery copyWith({
    String? search,
    String? name,
    String? code,
    String? form,
    String? strength,
    bool? isActive,
    AppPageRequest? pageRequest,
    bool clearName = false,
    bool clearCode = false,
    bool clearForm = false,
    bool clearStrength = false,
    bool clearIsActive = false,
  }) {
    return PharmacyFormularyQuery(
      search: search ?? this.search,
      name: clearName ? null : name ?? this.name,
      code: clearCode ? null : code ?? this.code,
      form: clearForm ? null : form ?? this.form,
      strength: clearStrength ? null : strength ?? this.strength,
      isActive: clearIsActive ? null : isActive ?? this.isActive,
      pageRequest: pageRequest ?? this.pageRequest,
    );
  }
}

@immutable
final class PharmacyInventoryStockQuery {
  const PharmacyInventoryStockQuery({
    this.search = '',
    this.itemName,
    this.sku,
    this.facilityName,
    this.lowStockOnly = false,
    this.stockStatus,
    this.expiringWithinDays,
    this.expiredOnly = false,
    this.pendingStockOnly,
    this.storageRoomId,
    this.storageShelfId,
    this.facilityId,
    this.inventoryItemId,
    this.pageRequest = const AppPageRequest(
      pageSize: AppPageRequest.maxPageSize,
    ),
  });

  final String search;
  final String? itemName;
  final String? sku;
  final String? facilityName;
  final bool lowStockOnly;
  final String? stockStatus;
  final int? expiringWithinDays;
  final bool expiredOnly;
  final bool? pendingStockOnly;
  final String? storageRoomId;
  final String? storageShelfId;
  final String? facilityId;
  final String? inventoryItemId;
  final AppPageRequest pageRequest;

  PharmacyInventoryStockQuery copyWith({
    String? search,
    String? itemName,
    String? sku,
    String? facilityName,
    bool? lowStockOnly,
    String? stockStatus,
    int? expiringWithinDays,
    bool? expiredOnly,
    bool? pendingStockOnly,
    String? storageRoomId,
    String? storageShelfId,
    String? facilityId,
    String? inventoryItemId,
    AppPageRequest? pageRequest,
    bool clearItemName = false,
    bool clearSku = false,
    bool clearFacilityName = false,
    bool clearStockStatus = false,
    bool clearExpiringWithinDays = false,
    bool clearPendingStockOnly = false,
    bool clearStorageRoomId = false,
    bool clearStorageShelfId = false,
    bool clearFacilityId = false,
    bool clearInventoryItemId = false,
  }) {
    return PharmacyInventoryStockQuery(
      search: search ?? this.search,
      itemName: clearItemName ? null : itemName ?? this.itemName,
      sku: clearSku ? null : sku ?? this.sku,
      facilityName: clearFacilityName
          ? null
          : facilityName ?? this.facilityName,
      lowStockOnly: lowStockOnly ?? this.lowStockOnly,
      stockStatus: clearStockStatus ? null : stockStatus ?? this.stockStatus,
      expiringWithinDays: clearExpiringWithinDays
          ? null
          : expiringWithinDays ?? this.expiringWithinDays,
      expiredOnly: expiredOnly ?? this.expiredOnly,
      pendingStockOnly: clearPendingStockOnly
          ? null
          : pendingStockOnly ?? this.pendingStockOnly,
      storageRoomId: clearStorageRoomId
          ? null
          : storageRoomId ?? this.storageRoomId,
      storageShelfId: clearStorageShelfId
          ? null
          : storageShelfId ?? this.storageShelfId,
      facilityId: clearFacilityId ? null : facilityId ?? this.facilityId,
      inventoryItemId: clearInventoryItemId
          ? null
          : inventoryItemId ?? this.inventoryItemId,
      pageRequest: pageRequest ?? this.pageRequest,
    );
  }

  static PharmacyInventoryStockQuery forFilter(PharmacyInventoryFilter filter) {
    return switch (filter) {
      PharmacyInventoryFilter.lowStock => const PharmacyInventoryStockQuery(
        lowStockOnly: true,
      ),
      PharmacyInventoryFilter.almostOutOfStock =>
        const PharmacyInventoryStockQuery(stockStatus: 'ALMOST_OUT_OF_STOCK'),
      PharmacyInventoryFilter.expiringSoon => const PharmacyInventoryStockQuery(
        expiringWithinDays: 30,
      ),
      PharmacyInventoryFilter.expired => const PharmacyInventoryStockQuery(
        expiredOnly: true,
      ),
    };
  }
}

@immutable
final class PharmacyInventoryStockSummary {
  const PharmacyInventoryStockSummary({
    this.totalStockRows = 0,
    this.lowStockRows = 0,
    this.almostOutOfStockRows = 0,
    this.outOfStockRows = 0,
    this.pendingStockRows = 0,
    this.expiringSoonRows = 0,
    this.expiredRows = 0,
  });

  final int totalStockRows;
  final int lowStockRows;
  final int almostOutOfStockRows;
  final int outOfStockRows;
  final int pendingStockRows;
  final int expiringSoonRows;
  final int expiredRows;

  int get criticalStockRows => lowStockRows + outOfStockRows;
}

@immutable
final class PharmacyInventoryWorkbench {
  const PharmacyInventoryWorkbench({
    required this.summary,
    required this.stocks,
  });

  final PharmacyInventoryStockSummary summary;
  final AppPage<PharmacyInventoryStock> stocks;
}

@immutable
final class PharmacyFormularyItem {
  const PharmacyFormularyItem({
    required this.id,
    this.displayId,
    this.tenantId,
    this.drugId,
    this.drugDisplayName,
    this.drugCode,
    this.drugForm,
    this.drugStrength,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String? displayId;
  final String? tenantId;
  final String? drugId;
  final String? drugDisplayName;
  final String? drugCode;
  final String? drugForm;
  final String? drugStrength;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayTitle {
    return _firstNonEmpty(<String?>[drugDisplayName, drugCode]) ?? id;
  }

  String? get drugNameLabel => drugDisplayName;
}

@immutable
final class PharmacyDrugInput {
  const PharmacyDrugInput({
    required this.tenantId,
    required this.name,
    this.brandName,
    this.genericName,
    this.code,
    this.form,
    this.strength,
    this.buyUnitPrice,
    this.unitPrice,
    this.transferUnitPrice,
    this.currency,
    this.supplierId,
    this.inventoryUnit,
    this.initialStock,
    this.reorderLevel,
    this.batchNumber,
    this.manufacturedAt,
    this.expiryDate,
    this.expiryAlertLeadDays,
    this.storageRoomId,
    this.storageShelfId,
    this.defaultStorageShelfId,
    this.facilityId,
    this.confirmSimilar = false,
  });

  final String tenantId;
  final String name;
  final String? brandName;
  final String? genericName;
  final String? code;
  final String? form;
  final String? strength;
  final num? buyUnitPrice;
  final num? unitPrice;
  final num? transferUnitPrice;
  final String? currency;
  final String? supplierId;
  final String? inventoryUnit;
  final int? initialStock;
  final int? reorderLevel;
  final String? batchNumber;
  final DateTime? manufacturedAt;
  final DateTime? expiryDate;
  final int? expiryAlertLeadDays;
  final String? storageRoomId;
  final String? storageShelfId;
  final String? defaultStorageShelfId;
  final String? facilityId;
  final bool confirmSimilar;

  bool get hasStockSetup =>
      (initialStock != null && initialStock! > 0) ||
      (reorderLevel != null && reorderLevel! > 0) ||
      (batchNumber != null && batchNumber!.trim().isNotEmpty) ||
      manufacturedAt != null ||
      expiryDate != null;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'tenant_id': tenantId,
      'name': name,
      if (brandName != null && brandName!.trim().isNotEmpty)
        'brand_name': brandName!.trim(),
      if (genericName != null && genericName!.trim().isNotEmpty)
        'generic_name': genericName!.trim(),
      'code': code,
      'form': form,
      'strength': strength,
      if (buyUnitPrice != null) 'buy_unit_price': buyUnitPrice,
      if (unitPrice != null) 'unit_price': unitPrice,
      if (transferUnitPrice != null) 'transfer_unit_price': transferUnitPrice,
      if (currency != null) 'currency': currency,
      if (supplierId != null && supplierId!.trim().isNotEmpty)
        'supplier_id': supplierId!.trim(),
      if (confirmSimilar) 'confirm_similar': true,
    };
  }

  Map<String, Object?> toSetupJson() {
    return <String, Object?>{
      ...toJson(),
      if (inventoryUnit != null) 'inventory_unit': inventoryUnit,
      if (initialStock != null) 'initial_stock': initialStock,
      if (reorderLevel != null) 'reorder_level': reorderLevel,
      if (batchNumber != null && batchNumber!.trim().isNotEmpty)
        'batch_number': batchNumber!.trim(),
      if (manufacturedAt != null)
        'manufactured_at': manufacturedAt!.toUtc().toIso8601String(),
      if (expiryDate != null)
        'expiry_date': expiryDate!.toUtc().toIso8601String(),
      if (expiryAlertLeadDays != null)
        'expiry_alert_lead_days': expiryAlertLeadDays,
      if (storageRoomId != null) 'storage_room_id': storageRoomId,
      if (storageShelfId != null) 'storage_shelf_id': storageShelfId,
      if (defaultStorageShelfId != null || storageShelfId != null)
        'default_storage_shelf_id': defaultStorageShelfId ?? storageShelfId,
      if (facilityId != null) 'facility_id': facilityId,
    };
  }
}

@immutable
final class PharmacyDrugUpdateInput {
  const PharmacyDrugUpdateInput({
    this.name,
    this.brandName,
    this.genericName,
    this.code,
    this.form,
    this.strength,
    this.buyUnitPrice,
    this.unitPrice,
    this.transferUnitPrice,
    this.currency,
    this.supplierId,
    this.clearSupplierId = false,
    this.confirmSimilar = false,
  });

  final String? name;
  final String? brandName;
  final String? genericName;
  final String? code;
  final String? form;
  final String? strength;
  final num? buyUnitPrice;
  final num? unitPrice;
  final num? transferUnitPrice;
  final String? currency;
  final String? supplierId;
  final bool clearSupplierId;
  final bool confirmSimilar;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (name != null) 'name': name,
      if (brandName != null) 'brand_name': brandName,
      if (genericName != null) 'generic_name': genericName,
      if (code != null) 'code': code,
      if (form != null) 'form': form,
      if (strength != null) 'strength': strength,
      if (buyUnitPrice != null) 'buy_unit_price': buyUnitPrice,
      if (unitPrice != null) 'unit_price': unitPrice,
      if (transferUnitPrice != null) 'transfer_unit_price': transferUnitPrice,
      if (currency != null) 'currency': currency,
      if (clearSupplierId)
        'supplier_id': null
      else if (supplierId != null)
        'supplier_id': supplierId,
      if (confirmSimilar) 'confirm_similar': true,
    };
  }
}

@immutable
final class PharmacyFacilityOfferingInput {
  const PharmacyFacilityOfferingInput({
    this.unitPrice,
    this.currency,
    this.isActive,
    this.facilityId,
    this.defaultStorageShelfId,
  });

  final num? unitPrice;
  final String? currency;
  final bool? isActive;
  final String? facilityId;
  final String? defaultStorageShelfId;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (unitPrice != null) 'unit_price': unitPrice,
      if (currency != null) 'currency': currency,
      if (isActive != null) 'is_active': isActive,
      if (facilityId != null) 'facility_id': facilityId,
      if (defaultStorageShelfId != null)
        'default_storage_shelf_id': defaultStorageShelfId,
    };
  }
}

@immutable
final class PharmacyFormularyItemInput {
  const PharmacyFormularyItemInput({
    required this.tenantId,
    required this.drugId,
    this.isActive = true,
  });

  final String tenantId;
  final String drugId;
  final bool isActive;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'tenant_id': tenantId,
      'drug_id': drugId,
      'is_active': isActive,
    };
  }
}

@immutable
final class PharmacyInventoryAdjustInput {
  const PharmacyInventoryAdjustInput({
    required this.inventoryItemId,
    this.quantityDelta = 0,
    this.reorderLevel,
    this.reason,
    this.notes,
    this.facilityId,
    this.batchNumber,
    this.manufacturedAt,
    this.expiryDate,
    this.expiryAlertLeadDays,
    this.drugId,
    this.storageRoomId,
    this.storageShelfId,
  });

  final String inventoryItemId;
  final int quantityDelta;
  final int? reorderLevel;
  final String? reason;
  final String? notes;
  final String? facilityId;
  final String? batchNumber;
  final DateTime? manufacturedAt;
  final DateTime? expiryDate;
  final int? expiryAlertLeadDays;
  final String? drugId;
  final String? storageRoomId;
  final String? storageShelfId;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'inventory_item_id': inventoryItemId,
      if (quantityDelta != 0) 'quantity_delta': quantityDelta,
      if (reorderLevel != null) 'reorder_level': reorderLevel,
      'reason': reason,
      'notes': notes,
      'facility_id': facilityId,
      if (batchNumber != null && batchNumber!.trim().isNotEmpty)
        'batch_number': batchNumber!.trim(),
      if (manufacturedAt != null)
        'manufactured_at': manufacturedAt!.toUtc().toIso8601String(),
      if (expiryDate != null)
        'expiry_date': expiryDate!.toUtc().toIso8601String(),
      if (expiryAlertLeadDays != null)
        'expiry_alert_lead_days': expiryAlertLeadDays,
      if (drugId != null) 'drug_id': drugId,
      if (storageRoomId != null) 'storage_room_id': storageRoomId,
      if (storageShelfId != null) 'storage_shelf_id': storageShelfId,
    };
  }
}

@immutable
final class PharmacyWorkbenchQuery {
  const PharmacyWorkbenchQuery({
    this.search = '',
    this.status,
    this.location,
    this.pendingPayment,
    this.openOrders,
    this.todayOnly,
    this.partialStock,
    this.urgent,
    this.priority,
    this.from,
    this.to,
    this.pageRequest = const AppPageRequest(),
  });

  final String search;
  final String? status;
  final String? location;

  /// Tri-state payment gate: `true` = only orders awaiting payment (Pending
  /// payment), `false` = only payment-cleared orders (New orders / Partial),
  /// `null` = no payment constraint.
  final bool? pendingPayment;

  /// When true, lists all open orders (`ORDERED` + `PARTIALLY_DISPENSED`)
  /// regardless of payment state — matches the pharmacist Pending KPI.
  final bool? openOrders;

  /// Scopes Completed / Cancelled to the current server day.
  final bool? todayOnly;
  final bool? partialStock;
  final bool? urgent;
  final String? priority;
  final DateTime? from;
  final DateTime? to;
  final AppPageRequest pageRequest;

  bool get isDefaultFilters {
    return status == null &&
        location == null &&
        pendingPayment == null &&
        openOrders != true &&
        todayOnly != true &&
        partialStock != true &&
        urgent != true &&
        priority == null &&
        from == null &&
        to == null;
  }

  PharmacyWorkbenchQuery copyWith({
    String? search,
    String? status,
    String? location,
    bool? pendingPayment,
    bool? openOrders,
    bool? todayOnly,
    bool? partialStock,
    bool? urgent,
    String? priority,
    DateTime? from,
    DateTime? to,
    AppPageRequest? pageRequest,
    bool clearStatus = false,
    bool clearLocation = false,
    bool clearPendingPayment = false,
    bool clearOpenOrders = false,
    bool clearTodayOnly = false,
    bool clearPartialStock = false,
    bool clearUrgent = false,
    bool clearPriority = false,
    bool clearFrom = false,
    bool clearTo = false,
  }) {
    return PharmacyWorkbenchQuery(
      search: search ?? this.search,
      status: clearStatus ? null : status ?? this.status,
      location: clearLocation ? null : location ?? this.location,
      pendingPayment: clearPendingPayment
          ? null
          : pendingPayment ?? this.pendingPayment,
      openOrders: clearOpenOrders ? null : openOrders ?? this.openOrders,
      todayOnly: clearTodayOnly ? null : todayOnly ?? this.todayOnly,
      partialStock: clearPartialStock
          ? null
          : partialStock ?? this.partialStock,
      urgent: clearUrgent ? null : urgent ?? this.urgent,
      priority: clearPriority ? null : priority ?? this.priority,
      from: clearFrom ? null : from ?? this.from,
      to: clearTo ? null : to ?? this.to,
      pageRequest: pageRequest ?? this.pageRequest,
    );
  }

  static PharmacyWorkbenchQuery fromChip(PharmacyOrderFilter filter) {
    return switch (filter) {
      PharmacyOrderFilter.all => const PharmacyWorkbenchQuery(),
      // New orders: unattended, payment-cleared open orders (Pending payment
      // claims those still awaiting payment).
      PharmacyOrderFilter.ready => const PharmacyWorkbenchQuery(
        status: 'ORDERED',
        pendingPayment: false,
      ),
      PharmacyOrderFilter.partial => const PharmacyWorkbenchQuery(
        status: 'PARTIALLY_DISPENSED',
        pendingPayment: false,
      ),
      // Completed / Cancelled orders are scoped to the current day.
      PharmacyOrderFilter.completed => const PharmacyWorkbenchQuery(
        status: 'DISPENSED',
        todayOnly: true,
      ),
      PharmacyOrderFilter.cancelled => const PharmacyWorkbenchQuery(
        status: 'CANCELLED',
        todayOnly: true,
      ),
      PharmacyOrderFilter.pendingPayment => const PharmacyWorkbenchQuery(
        pendingPayment: true,
      ),
      PharmacyOrderFilter.outpatient => const PharmacyWorkbenchQuery(
        location: 'OUTPATIENT',
      ),
      PharmacyOrderFilter.ward => const PharmacyWorkbenchQuery(
        location: 'INPATIENT',
      ),
      PharmacyOrderFilter.discharge => const PharmacyWorkbenchQuery(
        location: 'DISCHARGE',
      ),
      PharmacyOrderFilter.partialStock => const PharmacyWorkbenchQuery(
        partialStock: true,
      ),
      PharmacyOrderFilter.urgent => const PharmacyWorkbenchQuery(urgent: true),
    };
  }
}

@immutable
final class PharmacyDrugQuery {
  const PharmacyDrugQuery({
    this.search = '',
    this.name,
    this.code,
    this.form,
    this.strength,
    this.stockStatus,
    this.storageRoomId,
    this.storageShelfId,
    this.facilityId,
    this.pageRequest = const AppPageRequest(
      pageSize: AppPageRequest.maxPageSize,
    ),
  });

  final String search;
  final String? name;
  final String? code;
  final String? form;
  final String? strength;
  final String? stockStatus;
  final String? storageRoomId;
  final String? storageShelfId;
  final String? facilityId;
  final AppPageRequest pageRequest;

  PharmacyDrugQuery copyWith({
    String? search,
    String? name,
    String? code,
    String? form,
    String? strength,
    String? stockStatus,
    String? storageRoomId,
    String? storageShelfId,
    String? facilityId,
    AppPageRequest? pageRequest,
    bool clearStockStatus = false,
    bool clearStorageRoomId = false,
    bool clearStorageShelfId = false,
    bool clearName = false,
    bool clearCode = false,
    bool clearForm = false,
    bool clearStrength = false,
    bool clearFacilityId = false,
  }) {
    return PharmacyDrugQuery(
      search: search ?? this.search,
      name: clearName ? null : name ?? this.name,
      code: clearCode ? null : code ?? this.code,
      form: clearForm ? null : form ?? this.form,
      strength: clearStrength ? null : strength ?? this.strength,
      stockStatus: clearStockStatus ? null : stockStatus ?? this.stockStatus,
      storageRoomId: clearStorageRoomId
          ? null
          : storageRoomId ?? this.storageRoomId,
      storageShelfId: clearStorageShelfId
          ? null
          : storageShelfId ?? this.storageShelfId,
      facilityId: clearFacilityId ? null : facilityId ?? this.facilityId,
      pageRequest: pageRequest ?? this.pageRequest,
    );
  }
}

@immutable
final class PharmacySupplierQuery {
  const PharmacySupplierQuery({
    this.search = '',
    this.pageRequest = const AppPageRequest(
      pageSize: AppPageRequest.maxPageSize,
    ),
  });

  final String search;
  final AppPageRequest pageRequest;

  PharmacySupplierQuery copyWith({
    String? search,
    AppPageRequest? pageRequest,
  }) {
    return PharmacySupplierQuery(
      search: search ?? this.search,
      pageRequest: pageRequest ?? this.pageRequest,
    );
  }
}

@immutable
final class PharmacySupplier {
  const PharmacySupplier({
    required this.id,
    this.displayId,
    this.name,
    this.contactEmail,
    this.phone,
    this.location,
    this.addressId,
    this.tenantId,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String? displayId;
  final String? name;
  final String? contactEmail;
  final String? phone;
  final String? location;
  final String? addressId;
  final String? tenantId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get primaryName => (name ?? '').trim();
}

@immutable
final class PharmacySupplierFieldComparison {
  const PharmacySupplierFieldComparison({
    required this.field,
    this.inputValue,
    this.candidateValue,
    this.score,
    this.status,
  });

  final String field;
  final String? inputValue;
  final String? candidateValue;
  final int? score;
  final String? status;

  bool get isExact => status == 'MATCH' || score == 100;
}

@immutable
final class PharmacySupplierSimilarityMatch {
  const PharmacySupplierSimilarityMatch({
    required this.supplier,
    required this.score,
    this.isExact = false,
    this.exactNameConflict = false,
    this.exactEmailConflict = false,
    this.exactPhoneConflict = false,
    this.nameScore,
    this.emailScore,
    this.phoneScore,
    this.locationScore,
    this.fieldComparisons = const <PharmacySupplierFieldComparison>[],
  });

  final PharmacySupplier supplier;
  final int score;
  final bool isExact;
  final bool exactNameConflict;
  final bool exactEmailConflict;
  final bool exactPhoneConflict;
  final int? nameScore;
  final int? emailScore;
  final int? phoneScore;
  final int? locationScore;
  final List<PharmacySupplierFieldComparison> fieldComparisons;

  bool get hasExactConflict =>
      exactNameConflict || exactEmailConflict || exactPhoneConflict;
}

@immutable
final class PharmacySupplierSimilarityResult {
  const PharmacySupplierSimilarityResult({
    this.exactNameConflict = false,
    this.exactEmailConflict = false,
    this.exactPhoneConflict = false,
    this.closestScore = 0,
    this.matches = const <PharmacySupplierSimilarityMatch>[],
  });

  final bool exactNameConflict;
  final bool exactEmailConflict;
  final bool exactPhoneConflict;
  final int closestScore;
  final List<PharmacySupplierSimilarityMatch> matches;

  bool get hasExactConflict =>
      exactNameConflict || exactEmailConflict || exactPhoneConflict;
}

@immutable
final class PharmacySupplierInput {
  const PharmacySupplierInput({
    required this.tenantId,
    required this.name,
    this.contactEmail,
    this.phone,
    this.location,
    this.confirmSimilar = false,
  });

  final String tenantId;
  final String name;
  final String? contactEmail;
  final String? phone;
  final String? location;
  final bool confirmSimilar;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'tenant_id': tenantId,
      'name': name.trim(),
      if (contactEmail != null && contactEmail!.trim().isNotEmpty)
        'contact_email': contactEmail!.trim(),
      if (phone != null && phone!.trim().isNotEmpty) 'phone': phone!.trim(),
      if (confirmSimilar) 'confirm_similar': true,
    };
  }
}

@immutable
final class PharmacySupplierUpdateInput {
  const PharmacySupplierUpdateInput({
    this.name,
    this.contactEmail,
    this.phone,
    this.location,
    this.clearContactEmail = false,
    this.clearPhone = false,
    this.confirmSimilar = false,
  });

  final String? name;
  final String? contactEmail;
  final String? phone;
  final String? location;
  final bool clearContactEmail;
  final bool clearPhone;
  final bool confirmSimilar;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (name != null) 'name': name!.trim(),
      if (clearContactEmail)
        'contact_email': null
      else if (contactEmail != null)
        'contact_email': contactEmail!.trim().isEmpty
            ? null
            : contactEmail!.trim(),
      if (clearPhone)
        'phone': null
      else if (phone != null)
        'phone': phone!.trim().isEmpty ? null : phone!.trim(),
      if (confirmSimilar) 'confirm_similar': true,
    };
  }
}

@immutable
final class PharmacyWorkbenchSummary {
  const PharmacyWorkbenchSummary({
    this.totalOrders = 0,
    this.orderedQueue = 0,
    this.partiallyDispensedQueue = 0,
    this.dispensedOrders = 0,
    this.cancelledOrders = 0,
    this.dischargePendingQueue = 0,
    this.outpatientQueue = 0,
    this.wardQueue = 0,
    this.pendingPaymentQueue = 0,
    this.pendingAttestations = 0,
  });

  final int totalOrders;
  final int orderedQueue;
  final int partiallyDispensedQueue;
  final int dispensedOrders;
  final int cancelledOrders;
  final int dischargePendingQueue;
  final int outpatientQueue;
  final int wardQueue;
  final int pendingPaymentQueue;
  final int pendingAttestations;
}

@immutable
final class PharmacyWorkbench {
  const PharmacyWorkbench({required this.summary, required this.orders});

  final PharmacyWorkbenchSummary summary;
  final AppPage<PharmacyOrder> orders;

  PharmacyWorkbench copyWith({
    PharmacyWorkbenchSummary? summary,
    AppPage<PharmacyOrder>? orders,
  }) {
    return PharmacyWorkbench(
      summary: summary ?? this.summary,
      orders: orders ?? this.orders,
    );
  }
}

@immutable
final class PharmacyOrder {
  const PharmacyOrder({
    required this.id,
    this.displayId,
    this.encounterId,
    this.encounterType,
    this.location,
    this.patientId,
    this.patientDisplayName,
    this.orderSource,
    this.priority,
    this.status,
    this.orderedAt,
    this.createdAt,
    this.updatedAt,
    this.itemCount = 0,
    this.quantityPrescribedTotal = 0,
    this.quantityDispensedTotal = 0,
    this.quantityPendingTotal = 0,
    this.quantityReturnedTotal = 0,
    this.quantityRemainingTotal = 0,
    this.pendingAttestationBatchCount = 0,
    this.pendingAttestationBatches = const <PharmacyPendingBatch>[],
    this.items = const <PharmacyOrderItem>[],
    this.attestations = const <PharmacyAttestation>[],
    this.paymentStatus,
    this.billing = const <String, Object?>{},
    this.prescriberDisplayName,
  });

  final String id;
  final String? displayId;
  final String? encounterId;
  final String? encounterType;
  final String? location;
  final String? patientId;
  final String? patientDisplayName;
  final String? orderSource;
  final String? priority;
  final String? status;
  final DateTime? orderedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int itemCount;
  final num quantityPrescribedTotal;
  final num quantityDispensedTotal;
  final num quantityPendingTotal;
  final num quantityReturnedTotal;
  final num quantityRemainingTotal;
  final int pendingAttestationBatchCount;
  final List<PharmacyPendingBatch> pendingAttestationBatches;
  final List<PharmacyOrderItem> items;
  final List<PharmacyAttestation> attestations;
  final String? paymentStatus;
  final Map<String, Object?> billing;
  final String? prescriberDisplayName;

  String get displayTitle {
    return _firstNonEmpty(<String?>[patientDisplayName, displayId]) ?? '';
  }

  bool get isInpatientOrder {
    return (location ?? '').toUpperCase() == 'INPATIENT';
  }

  bool get isDischargePending {
    return isInpatientOrder &&
        <String>[
          'ORDERED',
          'PARTIALLY_DISPENSED',
        ].contains((status ?? '').toUpperCase());
  }

  bool get hasPendingAttestation {
    return pendingAttestationBatchCount > 0 ||
        pendingAttestationBatches.isNotEmpty;
  }

  bool get canPrepareDispense {
    return <String>[
          'ORDERED',
          'PARTIALLY_DISPENSED',
        ].contains((status ?? '').toUpperCase()) &&
        !hasPendingAttestation &&
        items.any((PharmacyOrderItem item) => item.quantityRemaining > 0);
  }

  bool get canAttestDispense {
    return <String>[
          'ORDERED',
          'PARTIALLY_DISPENSED',
        ].contains((status ?? '').toUpperCase()) &&
        hasPendingAttestation;
  }

  bool get canCancel {
    return <String>[
      'ORDERED',
      'PARTIALLY_DISPENSED',
    ].contains((status ?? '').toUpperCase());
  }

  bool get canReturn {
    return <String>[
          'DISPENSED',
          'PARTIALLY_DISPENSED',
        ].contains((status ?? '').toUpperCase()) &&
        items.any((PharmacyOrderItem item) => item.quantityDispensed > 0);
  }

  String? get firstPendingBatchRef {
    for (final PharmacyPendingBatch batch in pendingAttestationBatches) {
      final String value = batch.dispenseBatchRef.trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  bool get hasBillingGate {
    return effectivePaymentStatus != null;
  }

  String? get effectivePaymentStatus {
    final String? direct = _trimmedOrNull(paymentStatus);
    if (direct != null) {
      return direct;
    }
    final Object? nested = billing['payment_status'];
    return _trimmedOrNull(nested?.toString());
  }

  num? get billingTotalAmount {
    final Object? value = billing['total_amount'] ?? billing['line_amount'];
    if (value is num) {
      return value;
    }
    if (value is String) {
      return num.tryParse(value.trim());
    }
    return null;
  }

  String? get billingCurrency {
    return _trimmedOrNull(billing['currency']?.toString());
  }

  bool get isPaymentSatisfied {
    final String normalized = (effectivePaymentStatus ?? '').toUpperCase();
    return <String>{'PAID', 'NOT_REQUIRED', 'NO_CHARGE'}.contains(normalized);
  }

  bool get requiresPaymentBeforeDispense {
    if (!hasBillingGate) {
      return false;
    }
    final String normalized = (effectivePaymentStatus ?? '').toUpperCase();
    return <String>{'UNPAID', 'PARTIAL'}.contains(normalized);
  }

  static String? _trimmedOrNull(String? value) {
    final String normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  PharmacyOrder copyWith({
    String? status,
    DateTime? updatedAt,
    int? itemCount,
    num? quantityPrescribedTotal,
    num? quantityDispensedTotal,
    num? quantityPendingTotal,
    num? quantityReturnedTotal,
    num? quantityRemainingTotal,
    int? pendingAttestationBatchCount,
    List<PharmacyPendingBatch>? pendingAttestationBatches,
    List<PharmacyOrderItem>? items,
    List<PharmacyAttestation>? attestations,
    String? paymentStatus,
    Map<String, Object?>? billing,
  }) {
    return PharmacyOrder(
      id: id,
      displayId: displayId,
      encounterId: encounterId,
      encounterType: encounterType,
      location: location,
      patientId: patientId,
      patientDisplayName: patientDisplayName,
      orderSource: orderSource,
      priority: priority,
      status: status ?? this.status,
      orderedAt: orderedAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      itemCount: itemCount ?? this.itemCount,
      quantityPrescribedTotal:
          quantityPrescribedTotal ?? this.quantityPrescribedTotal,
      quantityDispensedTotal:
          quantityDispensedTotal ?? this.quantityDispensedTotal,
      quantityPendingTotal: quantityPendingTotal ?? this.quantityPendingTotal,
      quantityReturnedTotal:
          quantityReturnedTotal ?? this.quantityReturnedTotal,
      quantityRemainingTotal:
          quantityRemainingTotal ?? this.quantityRemainingTotal,
      pendingAttestationBatchCount:
          pendingAttestationBatchCount ?? this.pendingAttestationBatchCount,
      pendingAttestationBatches:
          pendingAttestationBatches ?? this.pendingAttestationBatches,
      items: items ?? this.items,
      attestations: attestations ?? this.attestations,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      billing: billing ?? this.billing,
      prescriberDisplayName: prescriberDisplayName,
    );
  }
}

@immutable
final class PharmacyPendingBatch {
  const PharmacyPendingBatch({
    required this.dispenseBatchRef,
    this.preparedAt,
    this.preparedByRole,
  });

  final String dispenseBatchRef;
  final DateTime? preparedAt;
  final String? preparedByRole;
}

@immutable
final class PharmacyOrderItem {
  const PharmacyOrderItem({
    required this.id,
    this.displayId,
    this.pharmacyOrderId,
    this.drugId,
    this.drugDisplayName,
    this.drugCode,
    this.drugForm,
    this.drugStrength,
    this.dosage,
    this.doseAmount,
    this.doseUnit,
    this.frequency,
    this.route,
    this.durationValue,
    this.durationUnit,
    this.instructions,
    this.customPrescription,
    this.status,
    this.quantity = 0,
    this.quantityUnit,
    this.quantityPrescribed = 0,
    this.quantityDispensed = 0,
    this.quantityPending = 0,
    this.quantityReturned = 0,
    this.quantityRemaining = 0,
    this.dispenseLogs = const <PharmacyDispenseLog>[],
    this.stockMappings = const <PharmacyStockMapping>[],
    this.defaultStockMapping,
    this.pharmacyUnitPrice,
    this.facilityUnitPrice,
    this.pharmacyCurrency,
    this.facilityCurrency,
    this.isOfferedAtFacility = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String? displayId;
  final String? pharmacyOrderId;
  final String? drugId;
  final String? drugDisplayName;
  final String? drugCode;
  final String? drugForm;
  final String? drugStrength;
  final String? dosage;
  final num? doseAmount;
  final String? doseUnit;
  final String? frequency;
  final String? route;
  final num? durationValue;
  final String? durationUnit;
  final String? instructions;
  final String? customPrescription;
  final String? status;
  final num quantity;
  final String? quantityUnit;
  final num quantityPrescribed;
  final num quantityDispensed;
  final num quantityPending;
  final num quantityReturned;
  final num quantityRemaining;
  final List<PharmacyDispenseLog> dispenseLogs;
  final List<PharmacyStockMapping> stockMappings;
  final PharmacyStockMapping? defaultStockMapping;
  final num? pharmacyUnitPrice;
  final num? facilityUnitPrice;
  final String? pharmacyCurrency;
  final String? facilityCurrency;
  final bool isOfferedAtFacility;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get medicationLabel {
    return _firstNonEmpty(<String?>[
          drugDisplayName,
          customPrescription,
          drugCode,
          displayId,
        ]) ??
        '';
  }

  String get doseLine {
    final String? structuredDose = _doseDisplay(doseAmount, doseUnit);
    // Prefer structured amount/unit when present so "500 mg" is not duplicated
    // as both dosage text and amount+unit.
    return _joinDisplay(<String?>[
      structuredDose ?? dosage,
      route,
      frequency,
      _durationDisplay(durationValue, durationUnit),
    ]);
  }

  /// Human-readable SIG for tables (avoids pipe-joined duplicates).
  String get simplifiedDoseLine {
    final String? structuredDose = _doseDisplay(doseAmount, doseUnit);
    final String dose = structuredDose ?? (dosage ?? '').trim();
    final String duration = _durationDisplay(durationValue, durationUnit) ?? '';
    return <String?>[
      dose.isEmpty ? null : dose.replaceAll(' | ', ' '),
      (route ?? '').trim().isEmpty ? null : route!.trim(),
      (frequency ?? '').trim().isEmpty ? null : frequency!.trim(),
      duration.isEmpty ? null : 'for ${duration.replaceAll(' | ', ' ')}',
    ].whereType<String>().where((String part) => part.isNotEmpty).join(' · ');
  }

  String get quantityLine {
    return _joinDisplay(<String?>[
      _quantityDisplay(quantityPrescribed, quantityUnit),
      if (quantityDispensed > 0) '${_trimNumber(quantityDispensed)} dispensed',
      if (quantityPending > 0) '${_trimNumber(quantityPending)} pending',
      if (quantityReturned > 0) '${_trimNumber(quantityReturned)} returned',
      if (quantityRemaining > 0) '${_trimNumber(quantityRemaining)} remaining',
    ]);
  }
}

@immutable
final class PharmacyStockMapping {
  const PharmacyStockMapping({
    required this.id,
    this.displayId,
    this.drugId,
    this.inventoryItemId,
    this.isDefault = false,
    this.deductionFactor = 1,
    this.inventoryItem,
  });

  final String id;
  final String? displayId;
  final String? drugId;
  final String? inventoryItemId;
  final bool isDefault;
  final num deductionFactor;
  final PharmacyInventoryItem? inventoryItem;

  String get displayTitle {
    return _firstNonEmpty(<String?>[
          inventoryItem?.name,
          inventoryItem?.sku,
          inventoryItemId,
          displayId,
          id,
        ]) ??
        id;
  }
}

@immutable
final class PharmacyInventoryItem {
  const PharmacyInventoryItem({
    required this.id,
    this.displayId,
    this.tenantId,
    this.name,
    this.category,
    this.sku,
    this.unit,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String? displayId;
  final String? tenantId;
  final String? name;
  final String? category;
  final String? sku;
  final String? unit;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayTitle {
    return _joinDisplay(<String?>[name, sku, unit]).isNotEmpty
        ? _joinDisplay(<String?>[name, sku, unit])
        : id;
  }
}

@immutable
final class PharmacyDispenseLog {
  const PharmacyDispenseLog({
    required this.id,
    this.displayId,
    this.pharmacyOrderItemId,
    this.dispenseBatchRef,
    this.status,
    this.quantityDispensed = 0,
    this.dispensedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String? displayId;
  final String? pharmacyOrderItemId;
  final String? dispenseBatchRef;
  final String? status;
  final num quantityDispensed;
  final DateTime? dispensedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

@immutable
final class PharmacyAttestation {
  const PharmacyAttestation({
    required this.id,
    this.displayId,
    this.pharmacyOrderId,
    this.dispenseBatchRef,
    this.phase,
    this.attestedByUserId,
    this.attestedRole,
    this.statement,
    this.reason,
    this.attestedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String? displayId;
  final String? pharmacyOrderId;
  final String? dispenseBatchRef;
  final String? phase;
  final String? attestedByUserId;
  final String? attestedRole;
  final String? statement;
  final String? reason;
  final DateTime? attestedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

@immutable
final class PharmacyTimelineItem {
  const PharmacyTimelineItem({
    required this.id,
    this.type,
    this.labelKey,
    this.labelParams = const <String, Object?>{},
    this.at,
  });

  final String id;
  final String? type;
  final String? labelKey;
  final Map<String, Object?> labelParams;
  final DateTime? at;
}

@immutable
final class PharmacyNextActions {
  const PharmacyNextActions({
    this.canPrepareDispense = false,
    this.canAttestDispense = false,
    this.canCancel = false,
    this.canReturn = false,
    this.canAdjustInventory = false,
  });

  final bool canPrepareDispense;
  final bool canAttestDispense;
  final bool canCancel;
  final bool canReturn;
  final bool canAdjustInventory;
}

@immutable
final class PharmacyOrderWorkflow {
  const PharmacyOrderWorkflow({
    required this.order,
    this.items = const <PharmacyOrderItem>[],
    this.attestations = const <PharmacyAttestation>[],
    this.timeline = const <PharmacyTimelineItem>[],
    this.nextActions = const PharmacyNextActions(),
  });

  final PharmacyOrder order;
  final List<PharmacyOrderItem> items;
  final List<PharmacyAttestation> attestations;
  final List<PharmacyTimelineItem> timeline;
  final PharmacyNextActions nextActions;
}

@immutable
final class PharmacyDrug {
  const PharmacyDrug({
    required this.id,
    this.displayId,
    this.name,
    this.brandName,
    this.genericName,
    this.code,
    this.form,
    this.strength,
    this.unitPrice,
    this.buyUnitPrice,
    this.pharmacyUnitPrice,
    this.transferUnitPrice,
    this.facilityUnitPrice,
    this.currency,
    this.pharmacyCurrency,
    this.facilityCurrency,
    this.supplierId,
    this.supplierName,
    this.isOfferedAtFacility = false,
    this.quantityOnHand = 0,
    this.availableQuantity = 0,
    this.stockLevel = 0,
    this.stockStatus,
    this.lowStock = false,
    this.pendingStock = false,
    this.stockMappings = const <PharmacyDrugStockMapping>[],
    this.stockRows = const <PharmacyInventoryStock>[],
    this.batchNumber,
    this.manufacturedAt,
    this.expiryDate,
    this.nextExpiry,
    this.expiryAlertLeadDays,
    this.storageRoomId,
    this.storageRoomLabel,
    this.storageShelfId,
    this.storageShelfCode,
    this.storageLocationLabel,
    this.tenantId,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String? displayId;
  final String? name;
  final String? brandName;
  final String? genericName;
  final String? code;
  final String? form;
  final String? strength;
  final num? unitPrice;
  final num? buyUnitPrice;
  final num? pharmacyUnitPrice;
  final num? transferUnitPrice;
  final num? facilityUnitPrice;
  final String? currency;
  final String? pharmacyCurrency;
  final String? facilityCurrency;
  final String? supplierId;
  final String? supplierName;
  final bool isOfferedAtFacility;
  final num quantityOnHand;
  final num availableQuantity;
  final num stockLevel;
  final String? stockStatus;
  final bool lowStock;
  final bool pendingStock;
  final List<PharmacyDrugStockMapping> stockMappings;
  final List<PharmacyInventoryStock> stockRows;
  final String? batchNumber;
  final DateTime? manufacturedAt;
  final DateTime? expiryDate;
  final DateTime? nextExpiry;
  final int? expiryAlertLeadDays;
  final String? storageRoomId;
  final String? storageRoomLabel;
  final String? storageShelfId;
  final String? storageShelfCode;
  final String? storageLocationLabel;
  final String? tenantId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Primary display name: prefer the brand, then the generic, then [name].
  String get primaryName {
    final String brand = (brandName ?? '').trim();
    if (brand.isNotEmpty) {
      return brand;
    }
    final String generic = (genericName ?? '').trim();
    if (generic.isNotEmpty) {
      return generic;
    }
    return (name ?? '').trim();
  }

  /// Generic/scientific subtitle shown when a distinct brand name exists.
  String? get genericSubtitle {
    final String generic = (genericName ?? '').trim();
    final String brand = (brandName ?? '').trim();
    if (generic.isEmpty || generic == brand) {
      return null;
    }
    return generic;
  }

  String get displayTitle {
    final String base = primaryName.isNotEmpty ? primaryName : (name ?? '');
    final String joined = _joinDisplay(<String?>[base, strength, form]);
    return joined.isNotEmpty ? joined : id;
  }
}

@immutable
final class PharmacyDrugStockMapping {
  const PharmacyDrugStockMapping({
    required this.id,
    this.displayId,
    this.inventoryItemId,
    this.isDefault = false,
    this.deductionFactor = 1,
    this.inventoryItem,
    this.stocks = const <PharmacyInventoryStock>[],
  });

  final String id;
  final String? displayId;
  final String? inventoryItemId;
  final bool isDefault;
  final num deductionFactor;
  final PharmacyInventoryItem? inventoryItem;
  final List<PharmacyInventoryStock> stocks;
}

@immutable
final class PharmacyInventoryStock {
  const PharmacyInventoryStock({
    required this.id,
    this.displayId,
    this.inventoryItemId,
    this.inventoryItem,
    this.facilityId,
    this.facilityName,
    this.quantity = 0,
    this.reorderLevel = 0,
    this.pendingStock = false,
    this.stockStatus,
    this.lowStock = false,
    this.batchCount = 0,
    this.nextExpiry,
    this.expiryAlertStatus,
    this.storageRoomId,
    this.storageRoomLabel,
    this.storageShelfId,
    this.storageShelfCode,
    this.storageLocationLabel,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String? displayId;
  final String? inventoryItemId;
  final PharmacyInventoryItem? inventoryItem;
  final String? facilityId;
  final String? facilityName;
  final num quantity;
  final num reorderLevel;
  final bool pendingStock;
  final String? stockStatus;
  final bool lowStock;
  final int batchCount;
  final DateTime? nextExpiry;
  final String? expiryAlertStatus;
  final String? storageRoomId;
  final String? storageRoomLabel;
  final String? storageShelfId;
  final String? storageShelfCode;
  final String? storageLocationLabel;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

@immutable
final class PharmacyStorageShelf {
  const PharmacyStorageShelf({
    required this.id,
    this.displayId,
    this.storageRoomId,
    this.shelfCode,
    this.label,
    this.isActive = true,
    this.storageRoomLabel,
  });

  final String id;
  final String? displayId;
  final String? storageRoomId;
  final String? shelfCode;
  final String? label;
  final bool isActive;
  final String? storageRoomLabel;

  String get displayLabel {
    final String code = (shelfCode ?? '').trim();
    final String friendly = (label ?? '').trim();
    if (friendly.isNotEmpty && friendly != code) {
      return '$friendly ($code)';
    }
    return code.isNotEmpty ? code : id;
  }
}

@immutable
final class PharmacyStorageRoom {
  const PharmacyStorageRoom({
    required this.id,
    this.displayId,
    this.name,
    this.code,
    this.isActive = true,
    this.createdAt,
    this.deletedAt,
    this.shelves = const <PharmacyStorageShelf>[],
  });

  final String id;
  final String? displayId;
  final String? name;
  final String? code;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? deletedAt;
  final List<PharmacyStorageShelf> shelves;

  bool get isSoftDeleted => deletedAt != null;
}

@immutable
final class PharmacyStorageLayout {
  const PharmacyStorageLayout({
    this.rooms = const <PharmacyStorageRoom>[],
    this.roomCount = 0,
    this.shelfCount = 0,
  });

  final List<PharmacyStorageRoom> rooms;
  final int roomCount;
  final int shelfCount;
}

@immutable
final class PharmacyStorageRoomInput {
  const PharmacyStorageRoomInput({
    required this.name,
    this.code,
    this.tenantId,
    this.facilityId,
    this.isActive = true,
    this.confirmSimilar = false,
  });

  final String name;
  final String? code;
  final String? tenantId;
  final String? facilityId;
  final bool isActive;
  final bool confirmSimilar;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    if (code != null) 'code': code,
    if (tenantId != null) 'tenant_id': tenantId,
    if (facilityId != null) 'facility_id': facilityId,
    'is_active': isActive,
    if (confirmSimilar) 'confirm_similar': true,
  };
}

@immutable
final class PharmacyStorageRoomUpdateInput {
  const PharmacyStorageRoomUpdateInput({
    this.name,
    this.code,
    this.isActive,
    this.confirmSimilar = false,
  });

  final String? name;
  final String? code;
  final bool? isActive;
  final bool confirmSimilar;

  Map<String, Object?> toJson() => <String, Object?>{
    if (name != null) 'name': name,
    if (code != null) 'code': code,
    if (isActive != null) 'is_active': isActive,
    if (confirmSimilar) 'confirm_similar': true,
  };
}

@immutable
final class PharmacyStorageRoomFieldComparison {
  const PharmacyStorageRoomFieldComparison({
    required this.field,
    this.inputValue,
    this.candidateValue,
    this.score,
    this.status,
  });

  final String field;
  final String? inputValue;
  final String? candidateValue;
  final int? score;
  final String? status;

  bool get isExact =>
      status == 'MATCH' || score == 100;
}

@immutable
final class PharmacyStorageRoomSimilarityMatch {
  const PharmacyStorageRoomSimilarityMatch({
    required this.room,
    required this.score,
    this.isExact = false,
    this.exactNameConflict = false,
    this.exactCodeConflict = false,
    this.nameScore,
    this.codeScore,
    this.fieldComparisons = const <PharmacyStorageRoomFieldComparison>[],
  });

  final PharmacyStorageRoom room;
  final int score;
  final bool isExact;
  final bool exactNameConflict;
  final bool exactCodeConflict;
  final int? nameScore;
  final int? codeScore;
  final List<PharmacyStorageRoomFieldComparison> fieldComparisons;

  bool get hasExactConflict => exactNameConflict || exactCodeConflict;
}

@immutable
final class PharmacyStorageRoomSimilarityResult {
  const PharmacyStorageRoomSimilarityResult({
    this.exactNameConflict = false,
    this.exactCodeConflict = false,
    this.closestScore = 0,
    this.matches = const <PharmacyStorageRoomSimilarityMatch>[],
  });

  final bool exactNameConflict;
  final bool exactCodeConflict;
  final int closestScore;
  final List<PharmacyStorageRoomSimilarityMatch> matches;

  bool get hasExactConflict => exactNameConflict || exactCodeConflict;
}

@immutable
final class PharmacyStorageShelfFieldComparison {
  const PharmacyStorageShelfFieldComparison({
    required this.field,
    this.inputValue,
    this.candidateValue,
    this.score,
    this.status,
  });

  final String field;
  final String? inputValue;
  final String? candidateValue;
  final int? score;
  final String? status;

  bool get isExact => status == 'MATCH' || score == 100;
}

@immutable
final class PharmacyStorageShelfSimilarityMatch {
  const PharmacyStorageShelfSimilarityMatch({
    required this.shelf,
    required this.score,
    this.isExact = false,
    this.exactLabelConflict = false,
    this.exactCodeConflict = false,
    this.labelScore,
    this.codeScore,
    this.fieldComparisons = const <PharmacyStorageShelfFieldComparison>[],
  });

  final PharmacyStorageShelf shelf;
  final int score;
  final bool isExact;
  final bool exactLabelConflict;
  final bool exactCodeConflict;
  final int? labelScore;
  final int? codeScore;
  final List<PharmacyStorageShelfFieldComparison> fieldComparisons;

  bool get hasExactConflict => exactLabelConflict || exactCodeConflict;
}

@immutable
final class PharmacyStorageShelfSimilarityResult {
  const PharmacyStorageShelfSimilarityResult({
    this.exactLabelConflict = false,
    this.exactCodeConflict = false,
    this.closestScore = 0,
    this.matches = const <PharmacyStorageShelfSimilarityMatch>[],
  });

  final bool exactLabelConflict;
  final bool exactCodeConflict;
  final int closestScore;
  final List<PharmacyStorageShelfSimilarityMatch> matches;

  bool get hasExactConflict => exactLabelConflict || exactCodeConflict;
}

@immutable
final class PharmacyDrugFieldComparison {
  const PharmacyDrugFieldComparison({
    required this.field,
    this.inputValue,
    this.candidateValue,
    this.score,
    this.status,
  });

  final String field;
  final String? inputValue;
  final String? candidateValue;
  final int? score;
  final String? status;

  bool get isExact => status == 'MATCH' || score == 100;
}

@immutable
final class PharmacyDrugSimilarityMatch {
  const PharmacyDrugSimilarityMatch({
    required this.drug,
    required this.score,
    this.isExact = false,
    this.exactIdentityConflict = false,
    this.exactCodeConflict = false,
    this.genericScore,
    this.brandScore,
    this.codeScore,
    this.formScore,
    this.strengthScore,
    this.fieldComparisons = const <PharmacyDrugFieldComparison>[],
  });

  final PharmacyDrug drug;
  final int score;
  final bool isExact;
  final bool exactIdentityConflict;
  final bool exactCodeConflict;
  final int? genericScore;
  final int? brandScore;
  final int? codeScore;
  final int? formScore;
  final int? strengthScore;
  final List<PharmacyDrugFieldComparison> fieldComparisons;

  bool get hasExactConflict => exactIdentityConflict || exactCodeConflict;
}

@immutable
final class PharmacyDrugSimilarityResult {
  const PharmacyDrugSimilarityResult({
    this.exactIdentityConflict = false,
    this.exactCodeConflict = false,
    this.closestScore = 0,
    this.matches = const <PharmacyDrugSimilarityMatch>[],
  });

  final bool exactIdentityConflict;
  final bool exactCodeConflict;
  final int closestScore;
  final List<PharmacyDrugSimilarityMatch> matches;

  bool get hasExactConflict => exactIdentityConflict || exactCodeConflict;
}

@immutable
final class PharmacyStorageShelfInput {
  const PharmacyStorageShelfInput({
    this.shelfCode,
    required this.label,
    this.isActive = true,
    this.confirmSimilar = false,
  });

  final String? shelfCode;
  final String label;
  final bool isActive;
  final bool confirmSimilar;

  Map<String, Object?> toJson() => <String, Object?>{
    if (shelfCode != null && shelfCode!.trim().isNotEmpty)
      'shelf_code': shelfCode!.trim(),
    'label': label,
    'is_active': isActive,
    if (confirmSimilar) 'confirm_similar': true,
  };
}

@immutable
final class PharmacyStorageShelfUpdateInput {
  const PharmacyStorageShelfUpdateInput({
    this.shelfCode,
    this.label,
    this.isActive,
    this.confirmSimilar = false,
  });

  final String? shelfCode;
  final String? label;
  final bool? isActive;
  final bool confirmSimilar;

  Map<String, Object?> toJson() => <String, Object?>{
    if (shelfCode != null) 'shelf_code': shelfCode,
    if (label != null) 'label': label,
    if (isActive != null) 'is_active': isActive,
    if (confirmSimilar) 'confirm_similar': true,
  };
}

@immutable
final class PharmacyMutationResult {
  const PharmacyMutationResult({
    required this.workflow,
    this.summary,
    this.dispenseBatchRef,
  });

  final PharmacyOrderWorkflow workflow;
  final PharmacyWorkbenchSummary? summary;
  final String? dispenseBatchRef;
}

@immutable
final class PharmacyDispenseLineInput {
  const PharmacyDispenseLineInput({
    required this.orderItemId,
    required this.quantity,
    this.inventoryItemId,
    this.notes,
  });

  final String orderItemId;
  final int quantity;
  final String? inventoryItemId;
  final String? notes;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'order_item_id': orderItemId,
      'quantity': quantity,
      'inventory_item_id': inventoryItemId,
      'notes': notes,
    };
  }
}

@immutable
final class PharmacyReturnLineInput {
  const PharmacyReturnLineInput({
    required this.orderItemId,
    required this.quantity,
    this.inventoryItemId,
  });

  final String orderItemId;
  final int quantity;
  final String? inventoryItemId;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'order_item_id': orderItemId,
      'quantity': quantity,
      'inventory_item_id': inventoryItemId,
    };
  }
}

@immutable
final class PharmacyWorkspaceQuery {
  const PharmacyWorkspaceQuery({
    this.section = '',
    this.encounterId = '',
    this.orderId = '',
    this.search = '',
    this.from,
    this.to,
  });

  factory PharmacyWorkspaceQuery.fromUri(Uri uri) {
    final Map<String, String> params = uri.queryParameters;
    String pick(List<String> keys) {
      for (final String key in keys) {
        final String value = (params[key] ?? '').trim();
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    DateTime? parseDate(String raw) {
      final String value = raw.trim();
      if (value.isEmpty) {
        return null;
      }
      return DateTime.tryParse(value)?.toLocal();
    }

    return PharmacyWorkspaceQuery(
      section: pick(<String>['section']),
      encounterId: pick(<String>['encounterId', 'encounter_id', 'encounter']),
      orderId: pick(<String>['orderId', 'order_id', 'order']),
      search: pick(<String>['search', 'q']),
      from: parseDate(pick(<String>['from', 'date_from', 'ordered_from'])),
      to: parseDate(pick(<String>['to', 'date_to', 'ordered_to'])),
    );
  }

  final String section;
  final String encounterId;
  final String orderId;
  final String search;
  final DateTime? from;
  final DateTime? to;

  bool get hasRouteTargeting =>
      section.isNotEmpty ||
      encounterId.isNotEmpty ||
      orderId.isNotEmpty ||
      search.isNotEmpty ||
      from != null ||
      to != null;

  bool get hasDateRange => from != null || to != null;

  String get signature =>
      '$section|$encounterId|$orderId|$search|${from?.toIso8601String() ?? ''}|${to?.toIso8601String() ?? ''}';
}

@immutable
final class PharmacyWorkspaceState {
  const PharmacyWorkspaceState({
    required this.query,
    required this.workbench,
    required this.drugQuery,
    required this.drugs,
    required this.formularyQuery,
    required this.formularyItems,
    required this.inventoryQuery,
    required this.inventoryWorkbench,
    this.selectedWorkflow,
    this.lastFailure,
    this.isRefreshingOrders = false,
    this.isRefreshingDetail = false,
    this.isRefreshingDrugs = false,
    this.isRefreshingFormulary = false,
    this.isRefreshingInventory = false,
    this.isSaving = false,
    this.catalogTab = PharmacyCatalogTab.drugs,
    this.storageLayout = const PharmacyStorageLayout(),
    this.isRefreshingStorage = false,
    this.stockAlertSummary = const PharmacyInventoryStockSummary(),
    this.supplierQuery = const PharmacySupplierQuery(),
    this.suppliers = const AppPage<PharmacySupplier>(
      items: <PharmacySupplier>[],
      request: AppPageRequest(pageSize: AppPageRequest.maxPageSize),
      totalItemCount: 0,
    ),
    this.isRefreshingSuppliers = false,
  });

  final PharmacyWorkbenchQuery query;
  final PharmacyWorkbench workbench;
  final PharmacyDrugQuery drugQuery;
  final AppPage<PharmacyDrug> drugs;
  final PharmacyFormularyQuery formularyQuery;
  final AppPage<PharmacyFormularyItem> formularyItems;
  final PharmacyInventoryStockQuery inventoryQuery;
  final PharmacyInventoryWorkbench inventoryWorkbench;

  /// Unfiltered stock-alert counters used for the desk stock tab badges,
  /// kept independent of the catalog inventory filter.
  final PharmacyInventoryStockSummary stockAlertSummary;
  final PharmacyOrderWorkflow? selectedWorkflow;
  final Object? lastFailure;
  final bool isRefreshingOrders;
  final bool isRefreshingDetail;
  final bool isRefreshingDrugs;
  final bool isRefreshingFormulary;
  final bool isRefreshingInventory;
  final bool isSaving;
  final PharmacyCatalogTab catalogTab;
  final PharmacyStorageLayout storageLayout;
  final bool isRefreshingStorage;
  final PharmacySupplierQuery supplierQuery;
  final AppPage<PharmacySupplier> suppliers;
  final bool isRefreshingSuppliers;

  int get workloadCount {
    return workbench.summary.orderedQueue +
        workbench.summary.partiallyDispensedQueue +
        workbench.summary.pendingAttestations;
  }

  PharmacyWorkspaceState copyWith({
    PharmacyWorkbenchQuery? query,
    PharmacyWorkbench? workbench,
    PharmacyDrugQuery? drugQuery,
    AppPage<PharmacyDrug>? drugs,
    PharmacyFormularyQuery? formularyQuery,
    AppPage<PharmacyFormularyItem>? formularyItems,
    PharmacyInventoryStockQuery? inventoryQuery,
    PharmacyInventoryWorkbench? inventoryWorkbench,
    PharmacyOrderWorkflow? selectedWorkflow,
    Object? lastFailure,
    bool? isRefreshingOrders,
    bool? isRefreshingDetail,
    bool? isRefreshingDrugs,
    bool? isRefreshingFormulary,
    bool? isRefreshingInventory,
    bool? isSaving,
    PharmacyCatalogTab? catalogTab,
    PharmacyStorageLayout? storageLayout,
    bool? isRefreshingStorage,
    PharmacyInventoryStockSummary? stockAlertSummary,
    PharmacySupplierQuery? supplierQuery,
    AppPage<PharmacySupplier>? suppliers,
    bool? isRefreshingSuppliers,
    bool clearSelectedWorkflow = false,
    bool clearLastFailure = false,
  }) {
    return PharmacyWorkspaceState(
      query: query ?? this.query,
      workbench: workbench ?? this.workbench,
      drugQuery: drugQuery ?? this.drugQuery,
      drugs: drugs ?? this.drugs,
      formularyQuery: formularyQuery ?? this.formularyQuery,
      formularyItems: formularyItems ?? this.formularyItems,
      inventoryQuery: inventoryQuery ?? this.inventoryQuery,
      inventoryWorkbench: inventoryWorkbench ?? this.inventoryWorkbench,
      selectedWorkflow: clearSelectedWorkflow
          ? null
          : selectedWorkflow ?? this.selectedWorkflow,
      lastFailure: clearLastFailure ? null : lastFailure ?? this.lastFailure,
      isRefreshingOrders: isRefreshingOrders ?? this.isRefreshingOrders,
      isRefreshingDetail: isRefreshingDetail ?? this.isRefreshingDetail,
      isRefreshingDrugs: isRefreshingDrugs ?? this.isRefreshingDrugs,
      isRefreshingFormulary:
          isRefreshingFormulary ?? this.isRefreshingFormulary,
      isRefreshingInventory:
          isRefreshingInventory ?? this.isRefreshingInventory,
      isSaving: isSaving ?? this.isSaving,
      catalogTab: catalogTab ?? this.catalogTab,
      storageLayout: storageLayout ?? this.storageLayout,
      isRefreshingStorage: isRefreshingStorage ?? this.isRefreshingStorage,
      stockAlertSummary: stockAlertSummary ?? this.stockAlertSummary,
      supplierQuery: supplierQuery ?? this.supplierQuery,
      suppliers: suppliers ?? this.suppliers,
      isRefreshingSuppliers:
          isRefreshingSuppliers ?? this.isRefreshingSuppliers,
    );
  }
}

String? _firstNonEmpty(Iterable<String?> values) {
  for (final String? value in values) {
    final String normalized = value?.trim() ?? '';
    if (normalized.isNotEmpty) {
      return normalized;
    }
  }
  return null;
}

String _joinDisplay(Iterable<String?> values) {
  return values
      .map((String? value) => value?.trim() ?? '')
      .where((String value) => value.isNotEmpty)
      .join(' | ');
}

String? _doseDisplay(num? amount, String? unit) {
  if (amount == null && (unit ?? '').trim().isEmpty) {
    return null;
  }
  return _joinDisplay(<String?>[
    amount == null ? null : _trimNumber(amount),
    unit,
  ]);
}

String? _durationDisplay(num? value, String? unit) {
  if (value == null && (unit ?? '').trim().isEmpty) {
    return null;
  }
  return _joinDisplay(<String?>[
    value == null ? null : _trimNumber(value),
    unit,
  ]);
}

String? _quantityDisplay(num value, String? unit) {
  if (value <= 0) {
    return null;
  }
  return _joinDisplay(<String?>[_trimNumber(value), unit]);
}

String _trimNumber(num value) {
  if (value is int || value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toString();
}
