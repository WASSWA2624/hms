import 'package:flutter/material.dart';
import 'package:hosspi_hms/features/pharmacy/domain/entities/pharmacy_location_entities.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/shared/layout/app_workspace.dart';

/// Shared labels, tones and icons for pharmacy locations and stock orders.
///
/// Kept in one place so the switcher, the availability table and the stock
/// order queues all name the same thing the same way.
String pharmacyLocationKindLabel(
  AppLocalizations l10n,
  PharmacyLocationKind kind,
) {
  return switch (kind) {
    PharmacyLocationKind.main => l10n.pharmacyLocationKindMain,
    PharmacyLocationKind.hospital => l10n.pharmacyLocationKindHospital,
    PharmacyLocationKind.branch => l10n.pharmacyLocationKindBranch,
    PharmacyLocationKind.theatre => l10n.pharmacyLocationKindTheatre,
    PharmacyLocationKind.ward => l10n.pharmacyLocationKindWard,
    PharmacyLocationKind.other => l10n.pharmacyLocationKindOther,
  };
}

IconData pharmacyLocationKindIcon(PharmacyLocationKind kind) {
  return switch (kind) {
    PharmacyLocationKind.main => Icons.warehouse_outlined,
    PharmacyLocationKind.hospital => Icons.local_pharmacy_outlined,
    PharmacyLocationKind.branch => Icons.store_outlined,
    PharmacyLocationKind.theatre => Icons.medical_services_outlined,
    PharmacyLocationKind.ward => Icons.bed_outlined,
    PharmacyLocationKind.other => Icons.medication_outlined,
  };
}

/// A pharmacy's display name, falling back to its kind when unnamed.
String pharmacyLocationDisplayName(
  AppLocalizations l10n,
  PharmacyLocation? location,
) {
  final String name = (location?.name ?? '').trim();
  if (name.isNotEmpty) return name;
  if (location == null) return l10n.profileUnknownValue;
  return pharmacyLocationKindLabel(l10n, location.kind);
}

String pharmacyAccessLevelLabel(
  AppLocalizations l10n,
  PharmacyLocationAccessLevel? level,
) {
  return switch (level) {
    PharmacyLocationAccessLevel.manage => l10n.pharmacyLocationAccessManage,
    PharmacyLocationAccessLevel.dispense => l10n.pharmacyLocationAccessDispense,
    PharmacyLocationAccessLevel.view => l10n.pharmacyLocationAccessView,
    null => l10n.pharmacyLocationReadOnlyBadge,
  };
}

String pharmacyStockOrderStatusLabel(
  AppLocalizations l10n,
  PharmacyStockOrderStatus status,
) {
  return switch (status) {
    PharmacyStockOrderStatus.draft => l10n.pharmacyStockOrderStatusDraft,
    PharmacyStockOrderStatus.submitted => l10n.pharmacyStockOrderStatusSubmitted,
    PharmacyStockOrderStatus.underReview =>
      l10n.pharmacyStockOrderStatusUnderReview,
    PharmacyStockOrderStatus.approved => l10n.pharmacyStockOrderStatusApproved,
    PharmacyStockOrderStatus.partiallyApproved =>
      l10n.pharmacyStockOrderStatusPartiallyApproved,
    PharmacyStockOrderStatus.rejected => l10n.pharmacyStockOrderStatusRejected,
    PharmacyStockOrderStatus.issued => l10n.pharmacyStockOrderStatusIssued,
    PharmacyStockOrderStatus.partiallyReceived =>
      l10n.pharmacyStockOrderStatusPartiallyReceived,
    PharmacyStockOrderStatus.received => l10n.pharmacyStockOrderStatusReceived,
    PharmacyStockOrderStatus.cancelled => l10n.pharmacyStockOrderStatusCancelled,
  };
}

AppWorkspaceStatusTone pharmacyStockOrderStatusTone(
  PharmacyStockOrderStatus status,
) {
  return switch (status) {
    PharmacyStockOrderStatus.received => AppWorkspaceStatusTone.success,
    PharmacyStockOrderStatus.approved => AppWorkspaceStatusTone.success,
    PharmacyStockOrderStatus.rejected => AppWorkspaceStatusTone.error,
    PharmacyStockOrderStatus.cancelled => AppWorkspaceStatusTone.neutral,
    PharmacyStockOrderStatus.draft => AppWorkspaceStatusTone.neutral,
    PharmacyStockOrderStatus.submitted => AppWorkspaceStatusTone.warning,
    PharmacyStockOrderStatus.underReview => AppWorkspaceStatusTone.warning,
    PharmacyStockOrderStatus.partiallyApproved => AppWorkspaceStatusTone.warning,
    PharmacyStockOrderStatus.issued => AppWorkspaceStatusTone.info,
    PharmacyStockOrderStatus.partiallyReceived => AppWorkspaceStatusTone.info,
  };
}

IconData pharmacyStockOrderStatusIcon(PharmacyStockOrderStatus status) {
  return switch (status) {
    PharmacyStockOrderStatus.draft => Icons.edit_note_outlined,
    PharmacyStockOrderStatus.submitted => Icons.outbox_outlined,
    PharmacyStockOrderStatus.underReview => Icons.rate_review_outlined,
    PharmacyStockOrderStatus.approved => Icons.check_circle_outline,
    PharmacyStockOrderStatus.partiallyApproved => Icons.rule_outlined,
    PharmacyStockOrderStatus.rejected => Icons.cancel_outlined,
    PharmacyStockOrderStatus.issued => Icons.local_shipping_outlined,
    PharmacyStockOrderStatus.partiallyReceived => Icons.inventory_2_outlined,
    PharmacyStockOrderStatus.received => Icons.inventory_outlined,
    PharmacyStockOrderStatus.cancelled => Icons.block_outlined,
  };
}

/// What the pharmacy identified by [locationId] must do about [order] now.
///
/// Returns an empty string when the ball is in the other pharmacy's court,
/// which is what keeps a status from becoming a dead end.
String pharmacyStockOrderNextActionLabel(
  AppLocalizations l10n,
  PharmacyStockOrder order,
  String? locationId,
) {
  if (locationId == null || order.isTerminal) return '';

  final bool isRequester = order.requestingLocationId == locationId;
  final bool isSupplier = order.supplyingLocationId == locationId;

  if (isRequester && order.isEditable) return l10n.pharmacyStockOrderSubmitAction;
  if (isSupplier && order.awaitsReview) return l10n.pharmacyStockOrderReviewAction;
  if (isSupplier && order.awaitsIssue) return l10n.pharmacyStockOrderIssueAction;
  if (isRequester && order.awaitsReceipt) {
    return l10n.pharmacyStockOrderReceiveAction;
  }
  return '';
}

/// The stock balance tone: empty is an error, at or below reorder a warning.
AppWorkspaceStatusTone pharmacyStockLevelTone(int quantity, int reorderLevel) {
  if (quantity <= 0) return AppWorkspaceStatusTone.error;
  if (quantity <= reorderLevel) return AppWorkspaceStatusTone.warning;
  return AppWorkspaceStatusTone.success;
}
