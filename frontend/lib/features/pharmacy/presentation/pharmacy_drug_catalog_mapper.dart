import 'package:hosspi_hms/features/pharmacy/domain/entities/pharmacy_entities.dart';
import 'package:hosspi_hms/shared/clinical_actions/clinical_action_models.dart';
import 'package:hosspi_hms/shared/clinical_actions/dialogs/clinical_action_dialog_helpers.dart';

/// Maps pharmacy catalog rows into the clinical prescription picker option shape.
ClinicalActionCatalogOption pharmacyDrugToClinicalCatalogOption(
  PharmacyDrug drug,
) {
  final String id = drug.id.trim();
  final String? displayId = drug.displayId?.trim();
  final String? publicId = (displayId != null && displayId.isNotEmpty)
      ? displayId
      : (id.isEmpty ? null : id);
  final String? secondary = clinicalActionJoinDisplay(<String?>[
    drug.form,
    drug.strength,
  ], separator: ' · ');
  final String? searchText = clinicalActionJoinDisplay(<String?>[
    drug.name,
    drug.brandName,
    drug.genericName,
    drug.code,
    drug.form,
    drug.strength,
    drug.batchNumber,
  ], separator: ' ');

  return ClinicalActionCatalogOption(
    id: id,
    publicId: publicId,
    name: drug.name,
    code: drug.code,
    secondaryText: secondary,
    searchText: searchText,
    unitPrice: drug.pharmacyUnitPrice ?? drug.unitPrice,
    currency: drug.pharmacyCurrency ?? drug.currency,
    metadata: <String, Object?>{
      'catalog_type': 'DRUG',
      // Friendly drug ids repeat across tenants; pickers use this to keep
      // same-id rows from different tenants apart.
      'tenant_id': drug.tenantId,
      'generic_name': drug.genericName,
      'brand_name': drug.brandName,
      'form': drug.form,
      'strength': drug.strength,
      'unit_price': drug.unitPrice,
      'pharmacy_unit_price': drug.pharmacyUnitPrice ?? drug.unitPrice,
      'facility_unit_price': drug.facilityUnitPrice,
      'buy_unit_price': drug.buyUnitPrice,
      'transfer_unit_price': drug.transferUnitPrice,
      'currency': drug.currency,
      'pharmacy_currency': drug.pharmacyCurrency ?? drug.currency,
      'facility_currency': drug.facilityCurrency,
      'stock_status': drug.stockStatus,
      'available_quantity': drug.availableQuantity,
    },
  );
}

List<ClinicalActionCatalogOption> pharmacyDrugsToClinicalCatalogOptions(
  Iterable<PharmacyDrug> drugs,
) {
  return drugs
      .map(pharmacyDrugToClinicalCatalogOption)
      .where((ClinicalActionCatalogOption option) => option.apiId.isNotEmpty)
      .toList(growable: false);
}
