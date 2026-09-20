import 'package:flutter/material.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/core/responsive/app_breakpoints.dart';
import 'package:hosspi_hms/features/pharmacy/domain/entities/pharmacy_entities.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';

@immutable
final class PharmacyCatalogTabDescriptor {
  const PharmacyCatalogTabDescriptor({
    required this.tab,
    required this.icon,
    required this.label,
  });

  final PharmacyCatalogTab tab;
  final IconData icon;
  final String label;
}

class PharmacyCatalogIconTabBar extends StatelessWidget {
  const PharmacyCatalogIconTabBar({
    required this.tabs,
    required this.selectedTab,
    required this.onTabSelected,
    super.key,
  });

  final List<PharmacyCatalogTabDescriptor> tabs;
  final PharmacyCatalogTab selectedTab;
  final ValueChanged<PharmacyCatalogTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final bool compact =
        AppBreakpoints.of(context).index < AppBreakpoint.md.index;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: theme.borders.only(bottom: true),
      ),
      child: Row(
        children: <Widget>[
          for (final PharmacyCatalogTabDescriptor descriptor in tabs)
            Expanded(
              child: _PharmacyCatalogIconTab(
                descriptor: descriptor,
                selected: descriptor.tab == selectedTab,
                compact: compact,
                onTap: () => onTabSelected(descriptor.tab),
              ),
            ),
        ],
      ),
    );
  }
}

class _PharmacyCatalogIconTab extends StatelessWidget {
  const _PharmacyCatalogIconTab({
    required this.descriptor,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final PharmacyCatalogTabDescriptor descriptor;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final Color activeColor = colorScheme.primary;
    final Color inactiveColor = colorScheme.onSurfaceVariant;

    return Tooltip(
      message: descriptor.label,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? theme.spacing.sm : theme.spacing.md,
            vertical: theme.spacing.sm,
          ),
          decoration: BoxDecoration(
            border: theme.borders.only(
              bottom: true,
              color: selected ? activeColor : Colors.transparent,
              weight: AppBorderWeight.thick,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                descriptor.icon,
                size: theme.appTokens.listIconSize,
                color: selected ? activeColor : inactiveColor,
              ),
              if (!compact) ...<Widget>[
                SizedBox(width: theme.spacing.xs),
                Flexible(
                  child: Text(
                    descriptor.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: selected ? activeColor : inactiveColor,
                      fontWeight: selected ? AppFontWeight.emphasis : AppFontWeight.regular,
                    ),
                  ),
                ),
              ],
              if (selected) ...<Widget>[
                SizedBox(width: theme.spacing.xs),
                Icon(
                  Icons.check_circle,
                  size: theme.appTokens.listIconSize - 4,
                  color: activeColor,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

List<PharmacyCatalogTabDescriptor> pharmacyCatalogTabDescriptors(
  AppLocalizations l10n,
) {
  return <PharmacyCatalogTabDescriptor>[
    PharmacyCatalogTabDescriptor(
      tab: PharmacyCatalogTab.drugs,
      icon: Icons.medication_outlined,
      label: l10n.pharmacyCatalogTabDrugs,
    ),
    PharmacyCatalogTabDescriptor(
      tab: PharmacyCatalogTab.formulary,
      icon: Icons.list_alt_outlined,
      label: l10n.pharmacyCatalogTabFormulary,
    ),
    PharmacyCatalogTabDescriptor(
      tab: PharmacyCatalogTab.inventory,
      icon: Icons.inventory_2_outlined,
      label: l10n.pharmacyCatalogTabInventory,
    ),
    PharmacyCatalogTabDescriptor(
      tab: PharmacyCatalogTab.storageLayout,
      icon: Icons.warehouse_outlined,
      label: l10n.pharmacyCatalogTabStorage,
    ),
    PharmacyCatalogTabDescriptor(
      tab: PharmacyCatalogTab.shelves,
      icon: Icons.view_week_outlined,
      label: l10n.pharmacyCatalogTabShelves,
    ),
    PharmacyCatalogTabDescriptor(
      tab: PharmacyCatalogTab.stockOrders,
      icon: Icons.sync_alt_outlined,
      label: l10n.pharmacyCatalogTabStockOrders,
    ),
  ];
}
