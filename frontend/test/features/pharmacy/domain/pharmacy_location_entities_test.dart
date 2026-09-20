import 'package:flutter_test/flutter_test.dart';
import 'package:hosspi_hms/features/pharmacy/data/dtos/pharmacy_location_dtos.dart';
import 'package:hosspi_hms/features/pharmacy/domain/entities/pharmacy_location_entities.dart';

void main() {
  group('PharmacyLocation', () {
    PharmacyLocation build({
      PharmacyLocationKind kind = PharmacyLocationKind.hospital,
      PharmacyLocationAccessLevel? accessLevel,
      String? suppliedByLocationId,
    }) {
      return PharmacyLocation(
        id: 'loc-1',
        name: 'Hospital Pharmacy',
        kind: kind,
        accessLevel: accessLevel,
        suppliedByLocationId: suppliedByLocationId,
      );
    }

    test('MANAGE satisfies dispense and view, DISPENSE does not satisfy manage', () {
      final manage = build(accessLevel: PharmacyLocationAccessLevel.manage);
      expect(manage.canManage, isTrue);
      expect(manage.canDispense, isTrue);
      expect(manage.canView, isTrue);

      final dispense = build(accessLevel: PharmacyLocationAccessLevel.dispense);
      expect(dispense.canManage, isFalse);
      expect(dispense.canDispense, isTrue);

      final view = build(accessLevel: PharmacyLocationAccessLevel.view);
      expect(view.canDispense, isFalse);
      expect(view.canView, isTrue);
    });

    test('a pharmacy with no grant can do nothing', () {
      final none = build();
      expect(none.canView, isFalse);
      expect(none.canDispense, isFalse);
      expect(none.canManage, isFalse);
    });

    test('knows whether it orders its stock from another pharmacy', () {
      expect(build().ordersFromAnotherPharmacy, isFalse);
      expect(
        build(suppliedByLocationId: 'loc-main').ordersFromAnotherPharmacy,
        isTrue,
      );
    });
  });

  group('PharmacyAvailabilityRow', () {
    PharmacyAvailabilityRow build({
      int quantity = 20,
      int reorderLevel = 50,
      int? supplierAvailable,
    }) {
      return PharmacyAvailabilityRow(
        inventoryItemId: 'item-1',
        quantity: quantity,
        reorderLevel: reorderLevel,
        supplierAvailable: supplierAvailable,
      );
    }

    test('flags a row at or below its reorder level', () {
      expect(build(quantity: 20, reorderLevel: 50).belowReorderLevel, isTrue);
      expect(build(quantity: 50, reorderLevel: 50).belowReorderLevel, isTrue);
      expect(build(quantity: 51, reorderLevel: 50).belowReorderLevel, isFalse);
    });

    test('says whether the supplier can cover the shortfall', () {
      // Short by 30; the supplier has 800.
      expect(
        build(quantity: 20, reorderLevel: 50, supplierAvailable: 800)
            .supplierCanCoverShortfall,
        isTrue,
      );
      expect(
        build(quantity: 20, reorderLevel: 50, supplierAvailable: 10)
            .supplierCanCoverShortfall,
        isFalse,
      );
      // No supplier at all.
      expect(build().supplierCanCoverShortfall, isFalse);
    });
  });

  group('PharmacyStockOrder', () {
    PharmacyStockOrder build({
      PharmacyStockOrderStatus status = PharmacyStockOrderStatus.submitted,
      List<PharmacyStockOrderItem> items = const <PharmacyStockOrderItem>[],
    }) {
      return PharmacyStockOrder(
        id: 'pso-1',
        status: status,
        requestingLocationId: 'loc-hospital',
        supplyingLocationId: 'loc-main',
        items: items,
      );
    }

    const line = PharmacyStockOrderItem(
      id: 'psi-1',
      drugId: 'drug-1',
      requestedQuantity: 100,
      approvedQuantity: 60,
      issuedQuantity: 60,
      receivedQuantity: 45,
    );

    test('reports what is still in transit between the two pharmacies', () {
      final order = build(
        status: PharmacyStockOrderStatus.partiallyReceived,
        items: const <PharmacyStockOrderItem>[line],
      );
      expect(order.issuedTotal, 60);
      expect(order.receivedTotal, 45);
      expect(order.inTransitTotal, 15);
      expect(line.outstandingQuantity, 15);
    });

    test('routes the next step to the pharmacy that owns it', () {
      // Awaiting review: the supplier must act, the requester waits.
      final submitted = build();
      expect(submitted.isActionableBy('loc-main'), isTrue);
      expect(submitted.isActionableBy('loc-hospital'), isFalse);

      // Approved: still the supplier, who now issues.
      final approved = build(status: PharmacyStockOrderStatus.approved);
      expect(approved.isActionableBy('loc-main'), isTrue);
      expect(approved.isActionableBy('loc-hospital'), isFalse);

      // Issued: now the requester books it in.
      final issued = build(status: PharmacyStockOrderStatus.issued);
      expect(issued.isActionableBy('loc-hospital'), isTrue);
      expect(issued.isActionableBy('loc-main'), isFalse);

      // Draft: only the requester, who submits it.
      final draft = build(status: PharmacyStockOrderStatus.draft);
      expect(draft.isActionableBy('loc-hospital'), isTrue);
      expect(draft.isActionableBy('loc-main'), isFalse);
    });

    test('a finished order asks nothing of either pharmacy', () {
      for (final status in <PharmacyStockOrderStatus>[
        PharmacyStockOrderStatus.received,
        PharmacyStockOrderStatus.rejected,
        PharmacyStockOrderStatus.cancelled,
      ]) {
        final order = build(status: status);
        expect(order.isTerminal, isTrue);
        expect(order.isActionableBy('loc-main'), isFalse);
        expect(order.isActionableBy('loc-hospital'), isFalse);
      }
    });

    test('is cancellable only while no stock has moved', () {
      expect(build(status: PharmacyStockOrderStatus.draft).isCancellable, isTrue);
      expect(build(status: PharmacyStockOrderStatus.approved).isCancellable, isTrue);
      // Once issued, the transfer must be received rather than cancelled, so
      // the two movement legs always balance.
      expect(build(status: PharmacyStockOrderStatus.issued).isCancellable, isFalse);
    });
  });

  group('PharmacyLocationDtos', () {
    test('parses a location with its access annotation', () {
      final location = PharmacyLocationDtos.location(<String, Object?>{
        'id': 'loc-main',
        'human_friendly_id': 'PLO0000001',
        'name': 'Main Pharmacy',
        'kind': 'MAIN',
        'handles_procurement': true,
        'handles_walk_in': true,
        'handles_prescriptions': false,
        'access_level': 'MANAGE',
        'can_view_supplier_stock': true,
      });

      expect(location.kind, PharmacyLocationKind.main);
      expect(location.handlesProcurement, isTrue);
      expect(location.canManage, isTrue);
      expect(location.effectiveId, 'PLO0000001');
    });

    test('keeps a withheld supply price and cost null', () {
      // The backend omits these fields for a caller who does not manage the
      // pharmacy; nothing must invent a value in their place.
      final price = PharmacyLocationDtos.price(<String, Object?>{
        'pharmacy_location_id': 'loc-main',
        'drug_id': 'drug-1',
        'sell_price': '300.00',
        'currency': 'UGX',
      });

      expect(price.sellPrice, 300);
      expect(price.supplyPrice, isNull);
      expect(price.acquisitionCost, isNull);
      expect(price.margin, isNull);
    });

    test('computes margin over what the pharmacy actually paid', () {
      final price = PharmacyLocationDtos.price(<String, Object?>{
        'pharmacy_location_id': 'loc-hospital',
        'drug_id': 'drug-1',
        'sell_price': '350.00',
        'acquisition_cost': '200.00',
      });

      expect(price.margin, 150);
    });

    test('parses an availability row with a quantity-only supplier side', () {
      final row = PharmacyLocationDtos.availabilityRow(<String, Object?>{
        'inventory_item_id': 'item-1',
        'inventory_item': <String, Object?>{'id': 'item-1', 'name': 'Paracetamol 500mg'},
        'drug_id': 'drug-1',
        'quantity': 20,
        'reorder_level': 50,
        'supplier_location': <String, Object?>{
          'id': 'loc-main',
          'name': 'Main Pharmacy',
          'kind': 'MAIN',
          'available': 800,
        },
        'can_order': true,
      });

      expect(row.quantity, 20);
      expect(row.supplierAvailable, 800);
      expect(row.supplierLocationKind, PharmacyLocationKind.main);
      expect(row.canOrder, isTrue);
      expect(row.belowReorderLevel, isTrue);
    });

    test('leaves the supplier side null when there is no supplying pharmacy', () {
      final row = PharmacyLocationDtos.availabilityRow(<String, Object?>{
        'inventory_item_id': 'item-1',
        'quantity': 20,
        'reorder_level': 50,
        'can_order': false,
      });

      expect(row.supplierAvailable, isNull);
      expect(row.supplierLocationId, isNull);
      expect(row.canOrder, isFalse);
    });

    test('parses a stock order and its lines', () {
      final order = PharmacyLocationDtos.stockOrder(<String, Object?>{
        'id': 'pso-1',
        'human_friendly_id': 'PSO0000001',
        'status': 'PARTIALLY_RECEIVED',
        'requesting_location_id': 'loc-hospital',
        'supplying_location_id': 'loc-main',
        'requesting_location': <String, Object?>{'name': 'Hospital Pharmacy'},
        'supplying_location': <String, Object?>{'name': 'Main Pharmacy'},
        'supply_total': '12000.00',
        'items': <Object?>[
          <String, Object?>{
            'id': 'psi-1',
            'drug_id': 'drug-1',
            'drug': <String, Object?>{'id': 'drug-1', 'name': 'Paracetamol 500mg'},
            'requested_quantity': 100,
            'approved_quantity': 60,
            'issued_quantity': 60,
            'received_quantity': 45,
            'unit_supply_price': '200.00',
            'status': 'ISSUED',
          },
        ],
      });

      expect(order.status, PharmacyStockOrderStatus.partiallyReceived);
      expect(order.supplyTotal, 12000);
      expect(order.items.single.unitSupplyPrice, 200);
      expect(order.inTransitTotal, 15);
      expect(order.awaitsReceipt, isTrue);
    });
  });

  group('origin routing', () {
    test('maps origins both ways', () {
      expect(pharmacyOrderOriginFromApi('WALK_IN'), PharmacyOrderOrigin.walkIn);
      expect(pharmacyOrderOriginFromApi('HOSPITAL'), PharmacyOrderOrigin.hospital);
      // Anything unrecognised is hospital work, the safer default, because a
      // hospital prescription must not be filled at the walk-in counter.
      expect(pharmacyOrderOriginFromApi(null), PharmacyOrderOrigin.hospital);
      expect(
        pharmacyOrderOriginToApi(PharmacyOrderOrigin.walkIn),
        'WALK_IN',
      );
    });
  });
}
