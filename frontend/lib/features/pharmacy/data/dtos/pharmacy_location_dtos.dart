import 'package:hosspi_hms/features/pharmacy/domain/entities/pharmacy_location_entities.dart';
import 'package:hosspi_hms/shared/data/data.dart';

typedef PharmacyJsonMap = Map<String, Object?>;

/// Parses the pharmacy-location, availability and stock-order payloads.
///
/// Fields the backend withholds - a supplying pharmacy's supply price or
/// purchase cost when the caller does not manage it - arrive absent rather than
/// null, so the entities keep them null and the UI simply does not show them.
abstract final class PharmacyLocationDtos {
  static PharmacyLocation location(Object? value) {
    final PharmacyJsonMap json = _map(value);
    return PharmacyLocation(
      id: _string(json['id']) ?? '',
      publicId: _string(json['human_friendly_id']),
      tenantId: _string(json['tenant_id']),
      facilityId: _string(json['facility_id']),
      name: _string(json['name']) ?? '',
      code: _string(json['code']),
      kind: pharmacyLocationKindFromApi(_string(json['kind'])),
      isActive: _bool(json['is_active'], fallback: true),
      isDefault: _bool(json['is_default']),
      handlesProcurement: _bool(json['handles_procurement']),
      handlesWalkIn: _bool(json['handles_walk_in']),
      handlesPrescriptions: _bool(json['handles_prescriptions']),
      suppliedByLocationId: _string(json['supplied_by_location_id']),
      currency: _string(json['currency']),
      accessLevel: pharmacyAccessLevelFromApi(_string(json['access_level'])),
      canViewSupplierStock: _bool(json['can_view_supplier_stock']),
    );
  }

  static List<PharmacyLocation> locationList(Object? value) {
    return _list(value).map(location).toList(growable: false);
  }

  static AppPage<PharmacyLocation> locationPage(
    Object? responseData,
    AppPageRequest request,
  ) {
    final PharmacyJsonMap response = _map(responseData);
    final PharmacyJsonMap meta = _map(response['meta']);
    final PharmacyJsonMap pagination = _map(meta['pagination']);
    return AppPage<PharmacyLocation>(
      items: locationList(response['data']),
      request: request,
      totalItemCount: _int(pagination['total']) ?? 0,
    );
  }

  static PharmacyLocationPrice price(Object? value) {
    final PharmacyJsonMap json = _map(value);
    final PharmacyJsonMap drug = _map(json['drug']);
    return PharmacyLocationPrice(
      id: _string(json['id']),
      publicId: _string(json['human_friendly_id']),
      pharmacyLocationId: _string(json['pharmacy_location_id']) ?? '',
      pharmacyLocationName: _string(json['pharmacy_location_name']),
      pharmacyLocationKind: json['pharmacy_location_kind'] == null
          ? null
          : pharmacyLocationKindFromApi(_string(json['pharmacy_location_kind'])),
      drugId: _string(json['drug_id']) ?? _string(drug['id']) ?? '',
      drugName: _string(drug['name']),
      drugDisplayId: _string(drug['human_friendly_id']),
      sellPrice: _number(json['sell_price']),
      supplyPrice: _number(json['supply_price']),
      acquisitionCost: _number(json['acquisition_cost']),
      currency: _string(json['currency']),
      isActive: _bool(json['is_active'], fallback: true),
      isConfigured: _bool(json['is_configured']),
    );
  }

  static AppPage<PharmacyLocationPrice> pricePage(
    Object? responseData,
    AppPageRequest request,
  ) {
    final PharmacyJsonMap response = _map(responseData);
    final PharmacyJsonMap meta = _map(response['meta']);
    final PharmacyJsonMap pagination = _map(meta['pagination']);
    return AppPage<PharmacyLocationPrice>(
      items: _list(response['data']).map(price).toList(growable: false),
      request: request,
      totalItemCount: _int(pagination['total']) ?? 0,
    );
  }

  static PharmacyAvailabilityRow availabilityRow(Object? value) {
    final PharmacyJsonMap json = _map(value);
    final PharmacyJsonMap item = _map(json['inventory_item']);
    final PharmacyJsonMap supplier = _map(json['supplier_location']);
    final bool hasSupplier = json['supplier_location'] != null;

    return PharmacyAvailabilityRow(
      inventoryItemId:
          _string(json['inventory_item_id']) ?? _string(item['id']) ?? '',
      inventoryItemName: _string(item['name']),
      inventoryItemDisplayId: _string(item['human_friendly_id']),
      sku: _string(item['sku']),
      unit: _string(item['unit']),
      drugId: _string(json['drug_id']),
      quantity: _int(json['quantity']) ?? 0,
      reorderLevel: _int(json['reorder_level']) ?? 0,
      supplierLocationId: hasSupplier ? _string(supplier['id']) : null,
      supplierLocationName: hasSupplier ? _string(supplier['name']) : null,
      supplierLocationKind: hasSupplier
          ? pharmacyLocationKindFromApi(_string(supplier['kind']))
          : null,
      supplierAvailable: hasSupplier ? _int(supplier['available']) : null,
      canOrder: _bool(json['can_order']),
    );
  }

  /// Availability comes back paginated with the two locations in `meta`.
  static PharmacyAvailabilityPage availabilityPage(
    Object? responseData,
    AppPageRequest request,
  ) {
    final PharmacyJsonMap response = _map(responseData);
    final PharmacyJsonMap meta = _map(response['meta']);
    final PharmacyJsonMap pagination = _map(meta['pagination']);
    return PharmacyAvailabilityPage(
      page: AppPage<PharmacyAvailabilityRow>(
        items: _list(response['data']).map(availabilityRow).toList(growable: false),
        request: request,
        totalItemCount: _int(pagination['total']) ?? 0,
      ),
      location: meta['location'] == null ? null : location(meta['location']),
      comparisonLocation: meta['comparison_location'] == null
          ? null
          : location(meta['comparison_location']),
    );
  }

  static PharmacyStockOrderItem stockOrderItem(Object? value) {
    final PharmacyJsonMap json = _map(value);
    final PharmacyJsonMap drug = _map(json['drug']);
    return PharmacyStockOrderItem(
      id: _string(json['id']) ?? '',
      publicId: _string(json['human_friendly_id']),
      drugId: _string(json['drug_id']) ?? _string(drug['id']) ?? '',
      inventoryItemId: _string(json['inventory_item_id']),
      drugName: _string(drug['name']),
      drugDisplayId: _string(drug['human_friendly_id']),
      drugStrength: _string(drug['strength']),
      drugForm: _string(drug['form']),
      requestedQuantity: _int(json['requested_quantity']) ?? 0,
      approvedQuantity: _int(json['approved_quantity']),
      issuedQuantity: _int(json['issued_quantity']) ?? 0,
      receivedQuantity: _int(json['received_quantity']) ?? 0,
      unitSupplyPrice: _number(json['unit_supply_price']),
      currency: _string(json['currency']),
      status: pharmacyStockOrderItemStatusFromApi(_string(json['status'])),
      notes: _string(json['notes']),
    );
  }

  static PharmacyStockOrder stockOrder(Object? value) {
    final PharmacyJsonMap json = _map(value);
    final PharmacyJsonMap requesting = _map(json['requesting_location']);
    final PharmacyJsonMap supplying = _map(json['supplying_location']);
    return PharmacyStockOrder(
      id: _string(json['id']) ?? '',
      publicId: _string(json['human_friendly_id']),
      status: pharmacyStockOrderStatusFromApi(_string(json['status'])),
      requestingLocationId: _string(json['requesting_location_id']) ??
          _string(requesting['id']) ??
          '',
      requestingLocationName: _string(requesting['name']),
      supplyingLocationId:
          _string(json['supplying_location_id']) ?? _string(supplying['id']) ?? '',
      supplyingLocationName: _string(supplying['name']),
      items: _list(json['items']).map(stockOrderItem).toList(growable: false),
      notes: _string(json['notes']),
      reviewNotes: _string(json['review_notes']),
      currency: _string(json['currency']),
      supplyTotal: _number(json['supply_total']),
      submittedAt: _date(json['submitted_at']),
      reviewedAt: _date(json['reviewed_at']),
      issuedAt: _date(json['issued_at']),
      receivedAt: _date(json['received_at']),
      cancelledAt: _date(json['cancelled_at']),
      createdAt: _date(json['created_at']),
    );
  }

  static PharmacyStockOrder stockOrderFromResponse(Object? responseData) {
    final PharmacyJsonMap response = _map(responseData);
    return stockOrder(response['data']);
  }

  static AppPage<PharmacyStockOrder> stockOrderPage(
    Object? responseData,
    AppPageRequest request,
  ) {
    final PharmacyJsonMap response = _map(responseData);
    final PharmacyJsonMap meta = _map(response['meta']);
    final PharmacyJsonMap pagination = _map(meta['pagination']);
    return AppPage<PharmacyStockOrder>(
      items: _list(response['data']).map(stockOrder).toList(growable: false),
      request: request,
      totalItemCount: _int(pagination['total']) ?? 0,
    );
  }
}

/// Availability rows plus the two pharmacies they compare.
final class PharmacyAvailabilityPage {
  const PharmacyAvailabilityPage({
    required this.page,
    this.location,
    this.comparisonLocation,
  });

  final AppPage<PharmacyAvailabilityRow> page;

  /// The pharmacy whose stock the rows describe.
  final PharmacyLocation? location;

  /// The pharmacy its availability is compared against, usually its supplier.
  final PharmacyLocation? comparisonLocation;
}

PharmacyJsonMap _map(Object? value) {
  if (value is PharmacyJsonMap) {
    return value;
  }
  if (value is Map<Object?, Object?>) {
    return PharmacyJsonMap.fromEntries(
      value.entries
          .where((MapEntry<Object?, Object?> entry) => entry.key != null)
          .map(
            (MapEntry<Object?, Object?> entry) =>
                MapEntry<String, Object?>(entry.key.toString(), entry.value),
          ),
    );
  }
  return const <String, Object?>{};
}

List<Object?> _list(Object? value) {
  return value is List<Object?> ? value : const <Object?>[];
}

String? _string(Object? value) {
  if (value == null) {
    return null;
  }
  final String normalized = value.toString().trim();
  return normalized.isEmpty ? null : normalized;
}

DateTime? _date(Object? value) {
  final String? normalized = _string(value);
  if (normalized == null) {
    return null;
  }
  return DateTime.tryParse(normalized);
}

num? _number(Object? value) {
  if (value is num) {
    return value;
  }
  if (value is String) {
    return num.tryParse(value);
  }
  return null;
}

int? _int(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

bool _bool(Object? value, {bool fallback = false}) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    final String normalized = value.trim().toLowerCase();
    if (<String>['true', '1', 'yes', 'on'].contains(normalized)) {
      return true;
    }
    if (<String>['false', '0', 'no', 'off'].contains(normalized)) {
      return false;
    }
  }
  if (value is num) {
    return value != 0;
  }
  return fallback;
}
