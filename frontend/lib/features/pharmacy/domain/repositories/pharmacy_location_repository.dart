import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/features/pharmacy/data/dtos/pharmacy_location_dtos.dart';
import 'package:hosspi_hms/features/pharmacy/domain/entities/pharmacy_location_entities.dart';
import 'package:hosspi_hms/shared/data/data.dart';

/// Pharmacy locations, their prices, their cross-pharmacy availability view and
/// the stock orders between them.
///
/// Kept apart from [PharmacyRepository] because these calls are about *which*
/// pharmacy is acting, while that one is about the work a pharmacy does.
abstract interface class PharmacyLocationRepository {
  /// Pharmacies the signed-in user can see, each annotated with their access.
  Future<Result<AppPage<PharmacyLocation>>> listLocations({
    String? facilityId,
    PharmacyLocationKind? kind,
    bool? mineOnly,
    bool? isActive,
    String? search,
    AppPageRequest pageRequest,
  });

  Future<Result<PharmacyLocation>> getLocation(String locationId);

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
  });

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
    bool clearSuppliedBy,
    String? currency,
  });

  /// This pharmacy's stock next to what its supplier holds.
  ///
  /// The supplier column is a bare quantity; purchase cost and supplier terms
  /// are never returned.
  Future<Result<PharmacyAvailabilityPage>> getAvailability(
    String locationId, {
    String? compareLocationId,
    String? search,
    bool? belowReorderLevel,
    AppPageRequest pageRequest,
  });

  /// A pharmacy's own prices. Supply price and cost come back only for a user
  /// who manages that pharmacy.
  Future<Result<AppPage<PharmacyLocationPrice>>> listPrices(
    String locationId, {
    String? drugId,
    String? search,
    AppPageRequest pageRequest,
  });

  /// Writes only the price fields supplied, so setting a walk-in price cannot
  /// move a supply price.
  Future<Result<PharmacyLocationPrice>> upsertPrice(
    String locationId, {
    required String drugId,
    num? sellPrice,
    num? supplyPrice,
    num? acquisitionCost,
    String? currency,
    bool? isActive,
  });

  // --------------------------------------------------------- stock orders

  Future<Result<AppPage<PharmacyStockOrder>>> listStockOrders({
    String? locationId,
    PharmacyStockOrderQueue queue,
    PharmacyStockOrderStatus? status,
    String? search,
    AppPageRequest pageRequest,
  });

  Future<Result<PharmacyStockOrder>> getStockOrder(String stockOrderId);

  /// Raises a stock order. Creating it does not change any balance.
  Future<Result<PharmacyStockOrder>> createStockOrder({
    required String requestingLocationId,
    required List<PharmacyStockOrderLineInput> items,
    String? supplyingLocationId,
    String? notes,
    bool submit,
  });

  Future<Result<PharmacyStockOrder>> updateStockOrder(
    String stockOrderId, {
    String? notes,
    List<PharmacyStockOrderLineInput>? items,
  });

  Future<Result<PharmacyStockOrder>> submitStockOrder(String stockOrderId);

  /// Approve, partially approve or reject. Does not change any balance.
  Future<Result<PharmacyStockOrder>> reviewStockOrder(
    String stockOrderId, {
    required bool approve,
    String? reviewNotes,
    List<PharmacyStockOrderDecisionInput>? items,
  });

  /// Releases stock from the supplying pharmacy. First balance change.
  Future<Result<PharmacyStockOrder>> issueStockOrder(
    String stockOrderId, {
    List<PharmacyStockOrderQuantityInput>? items,
    String? notes,
  });

  /// Books the delivery into the requesting pharmacy. Second balance change.
  Future<Result<PharmacyStockOrder>> receiveStockOrder(
    String stockOrderId, {
    List<PharmacyStockOrderQuantityInput>? items,
    String? notes,
  });

  Future<Result<PharmacyStockOrder>> cancelStockOrder(
    String stockOrderId, {
    String? reason,
  });
}

/// A requested line on a new or edited stock order.
final class PharmacyStockOrderLineInput {
  const PharmacyStockOrderLineInput({
    required this.drugId,
    required this.requestedQuantity,
    this.inventoryItemId,
    this.notes,
  });

  final String drugId;
  final String? inventoryItemId;
  final int requestedQuantity;
  final String? notes;

  Map<String, Object?> toJson() => <String, Object?>{
    'drug_id': drugId,
    if (inventoryItemId != null) 'inventory_item_id': inventoryItemId,
    'requested_quantity': requestedQuantity,
    if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
  };
}

/// A per-line review decision. Zero rejects the line.
final class PharmacyStockOrderDecisionInput {
  const PharmacyStockOrderDecisionInput({
    required this.itemId,
    required this.approvedQuantity,
    this.notes,
  });

  final String itemId;
  final int approvedQuantity;
  final String? notes;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': itemId,
    'approved_quantity': approvedQuantity,
    if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
  };
}

/// A per-line issued or received quantity.
final class PharmacyStockOrderQuantityInput {
  const PharmacyStockOrderQuantityInput({
    required this.itemId,
    required this.quantity,
  });

  final String itemId;
  final int quantity;

  Map<String, Object?> issuedJson() => <String, Object?>{
    'id': itemId,
    'issued_quantity': quantity,
  };

  Map<String, Object?> receivedJson() => <String, Object?>{
    'id': itemId,
    'received_quantity': quantity,
  };
}
