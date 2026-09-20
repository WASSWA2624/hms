import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/features/pharmacy/domain/entities/pharmacy_location_entities.dart';
import 'package:hosspi_hms/features/pharmacy/presentation/controllers/pharmacy_location_controller.dart';
import 'package:hosspi_hms/features/pharmacy/presentation/widgets/pharmacy_location_display.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/components/components.dart';
import 'package:hosspi_hms/shared/layout/app_workspace.dart';

/// Picks which pharmacy the user is working in.
///
/// Everything else on the pharmacy screens is scoped to this choice, so it sits
/// at the top of the workspace rather than inside a menu: a dispenser has to be
/// able to tell at a glance whether they are looking at Main Pharmacy stock or
/// their own.
///
/// Hidden when the user only has one pharmacy, because then there is nothing to
/// choose and the header stays quiet.
class PharmacyLocationSwitcher extends ConsumerWidget {
  const PharmacyLocationSwitcher({this.compact = false, super.key});

  /// Renders as a single chip rather than a labelled row.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final PharmacyLocationState? state = ref
        .watch(pharmacyLocationControllerProvider)
        .asData
        ?.value
        .when(
          success: (PharmacyLocationState value) => value,
          failure: (_) => null,
        );

    if (state == null) {
      return const SizedBox.shrink();
    }

    final List<PharmacyLocation> locations = state.switchableLocations;
    if (locations.isEmpty) {
      return AppWorkspaceStatePanel.empty(
        title: l10n.pharmacyLocationNoneTitle,
        body: l10n.pharmacyLocationNoneBody,
        icon: Icons.local_pharmacy_outlined,
      );
    }

    final PharmacyLocation? active = state.activeLocation;
    if (locations.length == 1) {
      return _PharmacyLocationBadge(location: locations.single);
    }

    final Widget selector = _PharmacyLocationDropdown(
      locations: locations,
      active: active,
      enabled: !state.isRefreshing,
      onChanged: (String locationId) => unawaited(
        ref
            .read(pharmacyLocationControllerProvider.notifier)
            .selectLocation(locationId),
      ),
    );

    if (compact) {
      return selector;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          l10n.pharmacyLocationSwitcherLabel,
          style: theme.textTheme.labelLarge,
        ),
        SizedBox(width: theme.spacing.sm),
        Flexible(child: selector),
        if (active != null && active.ordersFromAnotherPharmacy) ...<Widget>[
          SizedBox(width: theme.spacing.sm),
          _SupplierHint(state: state),
        ],
      ],
    );
  }
}

class _PharmacyLocationDropdown extends StatelessWidget {
  const _PharmacyLocationDropdown({
    required this.locations,
    required this.active,
    required this.enabled,
    required this.onChanged,
  });

  final List<PharmacyLocation> locations;
  final PharmacyLocation? active;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Tooltip(
      message: l10n.pharmacyLocationSwitcherTooltip,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: const ValueKey<String>('pharmacyLocationSwitcher'),
          value: active?.id,
          isDense: true,
          borderRadius: BorderRadius.circular(8),
          onChanged: enabled
              ? (String? value) {
                  if (value != null) onChanged(value);
                }
              : null,
          items: <DropdownMenuItem<String>>[
            for (final PharmacyLocation location in locations)
              DropdownMenuItem<String>(
                value: location.id,
                child: _PharmacyLocationOption(location: location),
              ),
          ],
        ),
      ),
    );
  }
}

class _PharmacyLocationOption extends StatelessWidget {
  const _PharmacyLocationOption({required this.location});

  final PharmacyLocation location;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(pharmacyLocationKindIcon(location.kind), size: 18),
        SizedBox(width: theme.spacing.xs),
        Text(pharmacyLocationDisplayName(l10n, location)),
        // A pharmacy the user can only look at is called out here so a failed
        // write is never a surprise.
        if (!location.canDispense) ...<Widget>[
          SizedBox(width: theme.spacing.xs),
          Text(
            '(${l10n.pharmacyLocationReadOnlyBadge})',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _PharmacyLocationBadge extends StatelessWidget {
  const _PharmacyLocationBadge({required this.location});

  final PharmacyLocation location;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return AppStatusBadge(
      label: pharmacyLocationDisplayName(l10n, location),
      icon: pharmacyLocationKindIcon(location.kind),
      tone: location.canDispense
          ? AppWorkspaceStatusTone.info
          : AppWorkspaceStatusTone.neutral,
    );
  }
}

class _SupplierHint extends StatelessWidget {
  const _SupplierHint({required this.state});

  final PharmacyLocationState state;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final PharmacyLocation? supplier = state.supplyingLocation;
    if (supplier == null) {
      return const SizedBox.shrink();
    }
    return AppStatusBadge(
      label: l10n.pharmacyLocationSuppliedByLabel(
        pharmacyLocationDisplayName(l10n, supplier),
      ),
      icon: Icons.sync_alt_outlined,
    );
  }
}
