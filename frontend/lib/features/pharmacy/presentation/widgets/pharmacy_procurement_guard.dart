import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/features/pharmacy/domain/entities/pharmacy_location_entities.dart';
import 'package:hosspi_hms/features/pharmacy/presentation/controllers/pharmacy_location_controller.dart';
import 'package:hosspi_hms/features/pharmacy/presentation/widgets/pharmacy_location_display.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/components/app_state_view.dart';
import 'package:hosspi_hms/shared/layout/app_workspace.dart';

/// Shows procurement surfaces only for the pharmacy that actually procures.
///
/// Requirement 4: suppliers, purchase orders, goods receiving, batches, expiry
/// records and costs belong to the Main Pharmacy. A Hospital Pharmacy user gets
/// an explanation and a pointer to the pharmacy that owns them, instead of a
/// form whose every save the backend would reject.
///
/// A facility that has not configured pharmacy locations renders [child]
/// unchanged, so nothing disappears for an install that has not adopted them.
class PharmacyProcurementGuard extends ConsumerWidget {
  const PharmacyProcurementGuard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final PharmacyLocationState? state = ref
        .watch(pharmacyLocationControllerProvider)
        .asData
        ?.value
        .when(
          success: (PharmacyLocationState value) => value,
          failure: (_) => null,
        );

    final PharmacyLocation? active = state?.activeLocation;
    if (state == null || active == null || active.handlesProcurement) {
      return child;
    }

    final PharmacyLocation? procurementPharmacy = _findProcurementPharmacy(state);

    return AppWorkspaceStatePanel.state(
      key: const ValueKey<String>('pharmacyProcurementRestricted'),
      variant: AppStateViewVariant.forbidden,
      title: l10n.pharmacyProcurementRestrictedTitle(
        pharmacyLocationDisplayName(l10n, procurementPharmacy),
      ),
      body: l10n.pharmacyProcurementRestrictedBody,
      icon: Icons.lock_outline,
    );
  }

  PharmacyLocation? _findProcurementPharmacy(PharmacyLocationState state) {
    for (final PharmacyLocation location in state.locations) {
      if (location.handlesProcurement) return location;
    }
    return state.supplyingLocation;
  }
}
