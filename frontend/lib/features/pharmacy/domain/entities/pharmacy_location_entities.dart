import 'package:flutter/foundation.dart';

/// Kind of pharmacy. `main` owns procurement and supplies the others; `hospital`
/// fills clinical prescriptions. The remaining kinds exist so a branch, theatre
/// or ward pharmacy needs no new code.
enum PharmacyLocationKind { main, hospital, branch, theatre, ward, other }

/// What a user may do inside one pharmacy.
enum PharmacyLocationAccessLevel { view, dispense, manage }

/// Where a prescription was raised, which decides the pharmacy that fills it.
enum PharmacyOrderOrigin { hospital, walkIn }

/// Lifecycle of a stock order raised by one pharmacy against another.
enum PharmacyStockOrderStatus {
  draft,
  submitted,
  underReview,
  approved,
  partiallyApproved,
  rejected,
  issued,
  partiallyReceived,
  received,
  cancelled,
}

enum PharmacyStockOrderItemStatus {
  requested,
  approved,
  partiallyApproved,
  rejected,
  issued,
  received,
  cancelled,
}

PharmacyLocationKind pharmacyLocationKindFromApi(String? value) {
  return switch ((value ?? '').trim().toUpperCase()) {
    'MAIN' => PharmacyLocationKind.main,
    'HOSPITAL' => PharmacyLocationKind.hospital,
    'BRANCH' => PharmacyLocationKind.branch,
    'THEATRE' => PharmacyLocationKind.theatre,
    'WARD' => PharmacyLocationKind.ward,
    _ => PharmacyLocationKind.other,
  };
}

String pharmacyLocationKindToApi(PharmacyLocationKind kind) {
  return switch (kind) {
    PharmacyLocationKind.main => 'MAIN',
    PharmacyLocationKind.hospital => 'HOSPITAL',
    PharmacyLocationKind.branch => 'BRANCH',
    PharmacyLocationKind.theatre => 'THEATRE',
    PharmacyLocationKind.ward => 'WARD',
    PharmacyLocationKind.other => 'OTHER',
  };
}

PharmacyLocationAccessLevel? pharmacyAccessLevelFromApi(String? value) {
  return switch ((value ?? '').trim().toUpperCase()) {
    'VIEW' => PharmacyLocationAccessLevel.view,
    'DISPENSE' => PharmacyLocationAccessLevel.dispense,
    'MANAGE' => PharmacyLocationAccessLevel.manage,
    _ => null,
  };
}

String pharmacyAccessLevelToApi(PharmacyLocationAccessLevel level) {
  return switch (level) {
    PharmacyLocationAccessLevel.view => 'VIEW',
    PharmacyLocationAccessLevel.dispense => 'DISPENSE',
    PharmacyLocationAccessLevel.manage => 'MANAGE',
  };
}

PharmacyOrderOrigin pharmacyOrderOriginFromApi(String? value) {
  return (value ?? '').trim().toUpperCase() == 'WALK_IN'
      ? PharmacyOrderOrigin.walkIn
      : PharmacyOrderOrigin.hospital;
}

String pharmacyOrderOriginToApi(PharmacyOrderOrigin origin) {
  return origin == PharmacyOrderOrigin.walkIn ? 'WALK_IN' : 'HOSPITAL';
}

PharmacyStockOrderStatus pharmacyStockOrderStatusFromApi(String? value) {
  return switch ((value ?? '').trim().toUpperCase()) {
    'DRAFT' => PharmacyStockOrderStatus.draft,
    'SUBMITTED' => PharmacyStockOrderStatus.submitted,
    'UNDER_REVIEW' => PharmacyStockOrderStatus.underReview,
    'APPROVED' => PharmacyStockOrderStatus.approved,
    'PARTIALLY_APPROVED' => PharmacyStockOrderStatus.partiallyApproved,
    'REJECTED' => PharmacyStockOrderStatus.rejected,
    'ISSUED' => PharmacyStockOrderStatus.issued,
    'PARTIALLY_RECEIVED' => PharmacyStockOrderStatus.partiallyReceived,
    'RECEIVED' => PharmacyStockOrderStatus.received,
    'CANCELLED' => PharmacyStockOrderStatus.cancelled,
    _ => PharmacyStockOrderStatus.draft,
  };
}

String pharmacyStockOrderStatusToApi(PharmacyStockOrderStatus status) {
  return switch (status) {
    PharmacyStockOrderStatus.draft => 'DRAFT',
    PharmacyStockOrderStatus.submitted => 'SUBMITTED',
    PharmacyStockOrderStatus.underReview => 'UNDER_REVIEW',
    PharmacyStockOrderStatus.approved => 'APPROVED',
    PharmacyStockOrderStatus.partiallyApproved => 'PARTIALLY_APPROVED',
    PharmacyStockOrderStatus.rejected => 'REJECTED',
    PharmacyStockOrderStatus.issued => 'ISSUED',
    PharmacyStockOrderStatus.partiallyReceived => 'PARTIALLY_RECEIVED',
    PharmacyStockOrderStatus.received => 'RECEIVED',
    PharmacyStockOrderStatus.cancelled => 'CANCELLED',
  };
}

PharmacyStockOrderItemStatus pharmacyStockOrderItemStatusFromApi(String? value) {
  return switch ((value ?? '').trim().toUpperCase()) {
    'APPROVED' => PharmacyStockOrderItemStatus.approved,
    'PARTIALLY_APPROVED' => PharmacyStockOrderItemStatus.partiallyApproved,
    'REJECTED' => PharmacyStockOrderItemStatus.rejected,
    'ISSUED' => PharmacyStockOrderItemStatus.issued,
    'RECEIVED' => PharmacyStockOrderItemStatus.received,
    'CANCELLED' => PharmacyStockOrderItemStatus.cancelled,
    _ => PharmacyStockOrderItemStatus.requested,
  };
}

/// A stock-holding, price-setting dispensing point inside a facility.
@immutable
final class PharmacyLocation {
  const PharmacyLocation({
    required this.id,
    required this.name,
    required this.kind,
    this.publicId,
    this.tenantId,
    this.facilityId,
    this.code,
    this.isActive = true,
    this.isDefault = false,
    this.handlesProcurement = false,
    this.handlesWalkIn = false,
    this.handlesPrescriptions = false,
    this.suppliedByLocationId,
    this.currency,
    this.accessLevel,
    this.canViewSupplierStock = false,
  });

  final String id;
  final String? publicId;
  final String? tenantId;
  final String? facilityId;
  final String name;
  final String? code;
  final PharmacyLocationKind kind;
  final bool isActive;
  final bool isDefault;

  /// Buys from suppliers. Only one pharmacy per facility may hold this.
  final bool handlesProcurement;

  /// Sells to non-hospital clients.
  final bool handlesWalkIn;

  /// Receives prescriptions raised in the hospital.
  final bool handlesPrescriptions;

  /// Pharmacy this one raises stock orders against.
  final String? suppliedByLocationId;
  final String? currency;

  /// What the signed-in user may do here. Null when they hold no grant.
  final PharmacyLocationAccessLevel? accessLevel;
  final bool canViewSupplierStock;

  String get effectiveId => publicId ?? id;

  bool get canManage => accessLevel == PharmacyLocationAccessLevel.manage;

  bool get canDispense =>
      accessLevel == PharmacyLocationAccessLevel.manage ||
      accessLevel == PharmacyLocationAccessLevel.dispense;

  bool get canView => accessLevel != null;

  /// Whether this pharmacy orders its stock from another one.
  bool get ordersFromAnotherPharmacy =>
      (suppliedByLocationId ?? '').trim().isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is PharmacyLocation && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// One pharmacy's own prices for a drug.
///
/// [sellPrice] is what this pharmacy charges its own customers; [supplyPrice] is
/// what it charges another pharmacy it supplies. They move independently, so a
/// walk-in price change never shifts a hospital supply price.
@immutable
final class PharmacyLocationPrice {
  const PharmacyLocationPrice({
    required this.pharmacyLocationId,
    required this.drugId,
    this.id,
    this.publicId,
    this.pharmacyLocationName,
    this.pharmacyLocationKind,
    this.drugName,
    this.drugDisplayId,
    this.sellPrice,
    this.supplyPrice,
    this.acquisitionCost,
    this.currency,
    this.isActive = true,
    this.isConfigured = false,
  });

  final String? id;
  final String? publicId;
  final String pharmacyLocationId;
  final String? pharmacyLocationName;
  final PharmacyLocationKind? pharmacyLocationKind;
  final String drugId;
  final String? drugName;
  final String? drugDisplayId;

  /// Price to this pharmacy's own customers or patients.
  final num? sellPrice;

  /// Price charged when supplying another pharmacy. Absent when the viewer may
  /// not see this pharmacy's commercial terms.
  final num? supplyPrice;

  /// What this pharmacy paid. Absent for a viewer who does not manage it.
  final num? acquisitionCost;
  final String? currency;
  final bool isActive;

  /// False when the pharmacy has not set its own price and a tenant-wide
  /// default is standing in.
  final bool isConfigured;

  /// Margin over what this pharmacy paid, when both are known.
  num? get margin {
    final num? sell = sellPrice;
    final num? cost = acquisitionCost;
    if (sell == null || cost == null) return null;
    return sell - cost;
  }
}

/// One row of the cross-pharmacy availability view.
///
/// The supplier side is a bare quantity: purchase cost, supplier identity and
/// batch detail stay with the pharmacy that owns them.
@immutable
final class PharmacyAvailabilityRow {
  const PharmacyAvailabilityRow({
    required this.inventoryItemId,
    required this.quantity,
    required this.reorderLevel,
    this.inventoryItemName,
    this.inventoryItemDisplayId,
    this.sku,
    this.unit,
    this.drugId,
    this.supplierLocationId,
    this.supplierLocationName,
    this.supplierLocationKind,
    this.supplierAvailable,
    this.canOrder = false,
  });

  final String inventoryItemId;
  final String? inventoryItemName;
  final String? inventoryItemDisplayId;
  final String? sku;
  final String? unit;
  final String? drugId;

  /// This pharmacy's own balance.
  final int quantity;
  final int reorderLevel;

  final String? supplierLocationId;
  final String? supplierLocationName;
  final PharmacyLocationKind? supplierLocationKind;

  /// Quantity the supplying pharmacy holds, or null when there is no supplier.
  final int? supplierAvailable;

  /// Whether a stock order can be raised for this row.
  final bool canOrder;

  bool get belowReorderLevel => quantity <= reorderLevel;

  /// Whether the supplier can cover the gap up to the reorder level.
  bool get supplierCanCoverShortfall {
    final int? available = supplierAvailable;
    if (available == null) return false;
    return available >= (reorderLevel - quantity).clamp(0, 1 << 30);
  }
}

/// A line of a stock order.
@immutable
final class PharmacyStockOrderItem {
  const PharmacyStockOrderItem({
    required this.id,
    required this.drugId,
    required this.requestedQuantity,
    this.publicId,
    this.inventoryItemId,
    this.drugName,
    this.drugDisplayId,
    this.drugStrength,
    this.drugForm,
    this.approvedQuantity,
    this.issuedQuantity = 0,
    this.receivedQuantity = 0,
    this.unitSupplyPrice,
    this.currency,
    this.status = PharmacyStockOrderItemStatus.requested,
    this.notes,
  });

  final String id;
  final String? publicId;
  final String drugId;
  final String? inventoryItemId;
  final String? drugName;
  final String? drugDisplayId;
  final String? drugStrength;
  final String? drugForm;

  final int requestedQuantity;

  /// Null until the supplying pharmacy has reviewed the line.
  final int? approvedQuantity;
  final int issuedQuantity;
  final int receivedQuantity;

  /// Supplying pharmacy's supply price at issue time, not its walk-in price.
  final num? unitSupplyPrice;
  final String? currency;
  final PharmacyStockOrderItemStatus status;
  final String? notes;

  String get effectiveId => publicId ?? id;

  /// Issued but not yet booked in by the requesting pharmacy.
  int get outstandingQuantity =>
      (issuedQuantity - receivedQuantity).clamp(0, 1 << 30);

  num? get lineTotal {
    final num? price = unitSupplyPrice;
    if (price == null) return null;
    return price * (issuedQuantity > 0 ? issuedQuantity : approvedQuantity ?? 0);
  }
}

/// A stock request raised by one pharmacy against another.
///
/// The order itself never moves stock; only [PharmacyStockOrderStatus.issued]
/// and the receipt that follows it do.
@immutable
final class PharmacyStockOrder {
  const PharmacyStockOrder({
    required this.id,
    required this.status,
    required this.requestingLocationId,
    required this.supplyingLocationId,
    this.publicId,
    this.requestingLocationName,
    this.supplyingLocationName,
    this.items = const <PharmacyStockOrderItem>[],
    this.notes,
    this.reviewNotes,
    this.currency,
    this.supplyTotal,
    this.submittedAt,
    this.reviewedAt,
    this.issuedAt,
    this.receivedAt,
    this.cancelledAt,
    this.createdAt,
  });

  final String id;
  final String? publicId;
  final PharmacyStockOrderStatus status;
  final String requestingLocationId;
  final String? requestingLocationName;
  final String supplyingLocationId;
  final String? supplyingLocationName;
  final List<PharmacyStockOrderItem> items;
  final String? notes;
  final String? reviewNotes;
  final String? currency;
  final num? supplyTotal;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final DateTime? issuedAt;
  final DateTime? receivedAt;
  final DateTime? cancelledAt;
  final DateTime? createdAt;

  String get effectiveId => publicId ?? id;

  bool get isTerminal =>
      status == PharmacyStockOrderStatus.received ||
      status == PharmacyStockOrderStatus.rejected ||
      status == PharmacyStockOrderStatus.cancelled;

  /// The requesting pharmacy may still edit and submit it.
  bool get isEditable => status == PharmacyStockOrderStatus.draft;

  /// The supplying pharmacy is being asked to decide.
  bool get awaitsReview =>
      status == PharmacyStockOrderStatus.submitted ||
      status == PharmacyStockOrderStatus.underReview;

  /// Approved, so the supplying pharmacy can release the stock.
  bool get awaitsIssue =>
      status == PharmacyStockOrderStatus.approved ||
      status == PharmacyStockOrderStatus.partiallyApproved;

  /// Issued, so the requesting pharmacy can book it in.
  bool get awaitsReceipt =>
      status == PharmacyStockOrderStatus.issued ||
      status == PharmacyStockOrderStatus.partiallyReceived;

  /// Nothing has moved yet, so either side may call it off.
  bool get isCancellable =>
      status == PharmacyStockOrderStatus.draft ||
      status == PharmacyStockOrderStatus.submitted ||
      status == PharmacyStockOrderStatus.underReview ||
      status == PharmacyStockOrderStatus.approved ||
      status == PharmacyStockOrderStatus.partiallyApproved;

  int get requestedTotal =>
      items.fold(0, (int sum, PharmacyStockOrderItem item) => sum + item.requestedQuantity);

  int get issuedTotal =>
      items.fold(0, (int sum, PharmacyStockOrderItem item) => sum + item.issuedQuantity);

  int get receivedTotal =>
      items.fold(0, (int sum, PharmacyStockOrderItem item) => sum + item.receivedQuantity);

  /// Quantity issued but not yet received: in transit between the pharmacies.
  int get inTransitTotal => (issuedTotal - receivedTotal).clamp(0, 1 << 30);

  /// Which pharmacy must act next, from the point of view of [locationId].
  bool isActionableBy(String locationId) {
    if (isTerminal) return false;
    final bool isRequester = locationId == requestingLocationId;
    final bool isSupplier = locationId == supplyingLocationId;
    if (isRequester && (isEditable || awaitsReceipt)) return true;
    if (isSupplier && (awaitsReview || awaitsIssue)) return true;
    return false;
  }
}

/// Which side of the stock-order workflow a queue shows.
enum PharmacyStockOrderQueue {
  /// Requests this pharmacy must supply.
  inbox,

  /// Requests this pharmacy has raised.
  outbox,
  all,
}

String pharmacyStockOrderQueueToApi(PharmacyStockOrderQueue queue) {
  return switch (queue) {
    PharmacyStockOrderQueue.inbox => 'INBOX',
    PharmacyStockOrderQueue.outbox => 'OUTBOX',
    PharmacyStockOrderQueue.all => 'ALL',
  };
}
