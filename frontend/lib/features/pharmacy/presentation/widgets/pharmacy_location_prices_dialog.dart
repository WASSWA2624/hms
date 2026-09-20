import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/features/pharmacy/data/repositories/pharmacy_location_repository_impl.dart';
import 'package:hosspi_hms/features/pharmacy/domain/entities/pharmacy_location_entities.dart';
import 'package:hosspi_hms/features/pharmacy/presentation/controllers/pharmacy_location_controller.dart';
import 'package:hosspi_hms/features/pharmacy/presentation/widgets/pharmacy_location_display.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/components/components.dart';
import 'package:hosspi_hms/shared/data/data.dart';
import 'package:hosspi_hms/shared/layout/app_workspace.dart';
import 'package:hosspi_hms/shared/layout/app_workspace_feedback.dart';

/// Opens the price list for the pharmacy the user is working in.
Future<void> showPharmacyLocationPricesDialog({
  required BuildContext context,
}) {
  return showAppDialog<void>(
    context: context,
    builder: (_) => const _PharmacyLocationPricesDialog(),
  );
}

/// One pharmacy's own prices.
///
/// Requirement 8/9 made visible: a pharmacy sets what it charges its own
/// customers and, separately, what it charges a pharmacy it supplies. The two
/// fields save independently, so raising the Main Pharmacy walk-in price leaves
/// the hospital supply price exactly where it was.
///
/// Supply price and acquisition cost appear only for a user who manages this
/// pharmacy; a Hospital Pharmacy user reading Main Pharmacy prices sees neither.
class _PharmacyLocationPricesDialog extends ConsumerStatefulWidget {
  const _PharmacyLocationPricesDialog();

  @override
  ConsumerState<_PharmacyLocationPricesDialog> createState() =>
      _PharmacyLocationPricesDialogState();
}

class _PharmacyLocationPricesDialogState
    extends ConsumerState<_PharmacyLocationPricesDialog> {
  final TextEditingController _searchController = TextEditingController();

  List<PharmacyLocationPrice> _prices = const <PharmacyLocationPrice>[];
  bool _isLoading = true;
  AppFailure? _failure;
  String? _loadedForLocationId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  PharmacyLocationState? get _locationState => ref
      .read(pharmacyLocationControllerProvider)
      .asData
      ?.value
      .when(
        success: (PharmacyLocationState value) => value,
        failure: (_) => null,
      );

  Future<void> _load() async {
    final String? locationId = _locationState?.activeLocationId;
    if (locationId == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() {
      _isLoading = true;
      _failure = null;
    });

    final Result<AppPage<PharmacyLocationPrice>> result = await ref
        .read(pharmacyLocationRepositoryProvider)
        .listPrices(
          locationId,
          search: _searchController.text.trim().isEmpty
              ? null
              : _searchController.text.trim(),
          pageRequest: const AppPageRequest(
            pageSize: AppPageRequest.maxPageSize,
          ),
        );

    if (!mounted) return;
    result.when(
      success: (AppPage<PharmacyLocationPrice> page) => setState(() {
        _prices = page.items;
        _isLoading = false;
        _loadedForLocationId = locationId;
      }),
      failure: (AppFailure failure) => setState(() {
        _failure = failure;
        _isLoading = false;
      }),
    );
  }

  Future<void> _editPrice(PharmacyLocationPrice price) async {
    final PharmacyLocation? location = _locationState?.activeLocation;
    if (location == null || !location.canManage) return;

    final _PriceEdit? edit = await showAppDialog<_PriceEdit>(
      context: context,
      builder: (_) => _PharmacyPriceEditDialog(price: price, location: location),
    );
    if (edit == null || !mounted) return;

    final AppFailure? failure = await ref
        .read(pharmacyLocationControllerProvider.notifier)
        .setPrice(
          drugId: price.drugId,
          sellPrice: edit.sellPrice,
          supplyPrice: edit.supplyPrice,
        );

    if (!mounted) return;
    if (failure != null) {
      showAppFailureSnackBar(context, failure);
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final PharmacyLocationState? state = ref.watch(
      pharmacyLocationControllerProvider,
    ).asData?.value.when(
      success: (PharmacyLocationState value) => value,
      failure: (_) => null,
    );
    final PharmacyLocation? location = state?.activeLocation;

    // The dialog stays open while the user switches pharmacy in the workspace
    // behind it, so reload rather than show another pharmacy's prices.
    if (location != null &&
        _loadedForLocationId != null &&
        _loadedForLocationId != location.id &&
        !_isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
    }

    return AppDialog(
      title: Text(l10n.pharmacyLocationPricesTitle),
      icon: const Icon(Icons.sell_outlined),
      semanticLabel: l10n.pharmacyLocationPricesTitle,
      scrollable: true,
      maxWidth: 900,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (location != null)
            AppStatusBadge(
              label: pharmacyLocationDisplayName(l10n, location),
              icon: pharmacyLocationKindIcon(location.kind),
              tone: AppWorkspaceStatusTone.info,
            ),
          SizedBox(height: theme.spacing.sm),
          Text(
            l10n.pharmacyLocationPriceIndependenceNotice,
            style: theme.textTheme.bodySmall,
          ),
          SizedBox(height: theme.spacing.md),
          if (_isLoading)
            AppLoadingIndicator.compact(title: l10n.pharmacyLocationPricesTitle)
          else if (_failure != null)
            AppWorkspaceStatePanel.error(
              title: l10n.pharmacyLocationPricesTitle,
              body: l10n.commonRetryActionLabel,
            )
          else if (_prices.isEmpty)
            AppWorkspaceStatePanel.empty(
              title: l10n.pharmacyLocationPriceUnsetLabel,
              body: l10n.pharmacyLocationPriceIndependenceNotice,
              icon: Icons.sell_outlined,
            )
          else
            _PriceTable(
              prices: _prices,
              location: location,
              onEdit: _editPrice,
            ),
        ],
      ),
      actions: <Widget>[
        AppButton.close(
          label: l10n.commonCloseActionLabel,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}

class _PriceTable extends StatelessWidget {
  const _PriceTable({
    required this.prices,
    required this.location,
    required this.onEdit,
  });

  final List<PharmacyLocationPrice> prices;
  final PharmacyLocation? location;
  final ValueChanged<PharmacyLocationPrice> onEdit;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final bool isMain = location?.kind == PharmacyLocationKind.main;
    final bool canManage = location?.canManage ?? false;

    // The Main Pharmacy's own price is its walk-in price; every other pharmacy
    // calls it its dispensing price.
    final String sellLabel = isMain
        ? l10n.pharmacyLocationWalkInPriceLabel
        : l10n.pharmacyLocationSellPriceLabel;

    return AppListTable<PharmacyLocationPrice>(
      items: prices,
      shrinkWrap: true,
      itemKeyBuilder: (PharmacyLocationPrice price) =>
          ValueKey<String>(price.drugId),
      columns: <AppListTableColumn<PharmacyLocationPrice>>[
        AppListTableColumn<PharmacyLocationPrice>(
          id: 'drug',
          label: l10n.pharmacyAvailabilityMedicineColumn,
          preferredWidth: 240,
          alwaysVisible: true,
          cellBuilder: (_, PharmacyLocationPrice price) => AppListItemText(
            title: price.drugName ?? price.drugId,
            subtitle: price.drugDisplayId,
          ),
          exportValue: (PharmacyLocationPrice price) => price.drugName ?? '',
        ),
        AppListTableColumn<PharmacyLocationPrice>(
          id: 'sell',
          label: sellLabel,
          preferredWidth: 150,
          alwaysVisible: true,
          cellBuilder: (_, PharmacyLocationPrice price) =>
              _MoneyCell(amount: price.sellPrice, currency: price.currency),
          exportValue: (PharmacyLocationPrice price) =>
              price.sellPrice?.toString() ?? '',
        ),
        // Only rendered for a manager of this pharmacy. For anyone else the
        // backend omits the value entirely, so there is nothing to show.
        if (canManage)
          AppListTableColumn<PharmacyLocationPrice>(
            id: 'supply',
            label: l10n.pharmacyLocationSupplyPriceLabel,
            preferredWidth: 170,
            cellBuilder: (_, PharmacyLocationPrice price) =>
                _MoneyCell(amount: price.supplyPrice, currency: price.currency),
            exportValue: (PharmacyLocationPrice price) =>
                price.supplyPrice?.toString() ?? '',
          ),
        if (canManage)
          AppListTableColumn<PharmacyLocationPrice>(
            id: 'cost',
            label: l10n.pharmacyLocationAcquisitionCostLabel,
            preferredWidth: 160,
            cellBuilder: (_, PharmacyLocationPrice price) => _MoneyCell(
              amount: price.acquisitionCost,
              currency: price.currency,
            ),
            exportValue: (PharmacyLocationPrice price) =>
                price.acquisitionCost?.toString() ?? '',
          ),
        if (canManage)
          AppListTableColumn<PharmacyLocationPrice>(
            id: 'actions',
            label: l10n.pharmacyLineActionsColumnLabel,
            alwaysVisible: true,
            fixedWidth: 130,
            exportable: false,
            cellBuilder: (_, PharmacyLocationPrice price) => AppButton.tertiary(
              label: l10n.commonEditActionLabel,
              leadingIcon: Icons.edit_outlined,
              onPressed: () => onEdit(price),
            ),
          ),
      ],
      mobileItemBuilder: (BuildContext context, PharmacyLocationPrice price) {
        return AppListTableMobileItem(
          title: price.drugName ?? price.drugId,
          caption: price.drugDisplayId,
          meta: <AppListTableMobileMeta>[
            AppListTableMobileMeta(
              label: '$sellLabel: ${price.sellPrice ?? '—'}',
              icon: Icons.sell_outlined,
            ),
          ],
        );
      },
    );
  }
}

class _MoneyCell extends StatelessWidget {
  const _MoneyCell({required this.amount, required this.currency});

  final num? amount;
  final String? currency;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    if (amount == null) {
      return Text(l10n.pharmacyLocationPriceUnsetLabel);
    }
    final String code = (currency ?? '').trim();
    return Text(code.isEmpty ? '$amount' : '$code $amount');
  }
}

/// The two independent price fields the user edited.
@immutable
class _PriceEdit {
  const _PriceEdit({this.sellPrice, this.supplyPrice});

  final num? sellPrice;
  final num? supplyPrice;
}

class _PharmacyPriceEditDialog extends StatefulWidget {
  const _PharmacyPriceEditDialog({required this.price, required this.location});

  final PharmacyLocationPrice price;
  final PharmacyLocation location;

  @override
  State<_PharmacyPriceEditDialog> createState() =>
      _PharmacyPriceEditDialogState();
}

class _PharmacyPriceEditDialogState extends State<_PharmacyPriceEditDialog> {
  late final TextEditingController _sellController;
  late final TextEditingController _supplyController;

  @override
  void initState() {
    super.initState();
    _sellController = TextEditingController(
      text: widget.price.sellPrice?.toString() ?? '',
    );
    _supplyController = TextEditingController(
      text: widget.price.supplyPrice?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _sellController.dispose();
    _supplyController.dispose();
    super.dispose();
  }

  num? _parse(TextEditingController controller) {
    final String raw = controller.text.trim();
    if (raw.isEmpty) return null;
    return num.tryParse(raw);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final bool isMain = widget.location.kind == PharmacyLocationKind.main;

    return AppDialog(
      title: Text(widget.price.drugName ?? l10n.pharmacyLocationPricesTitle),
      icon: const Icon(Icons.sell_outlined),
      semanticLabel: l10n.pharmacyLocationPricesTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            l10n.pharmacyLocationPriceIndependenceNotice,
            style: theme.textTheme.bodySmall,
          ),
          SizedBox(height: theme.spacing.md),
          TextField(
            controller: _sellController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: isMain
                  ? l10n.pharmacyLocationWalkInPriceLabel
                  : l10n.pharmacyLocationSellPriceLabel,
            ),
          ),
          SizedBox(height: theme.spacing.md),
          // Shown only where it means something: a pharmacy that supplies
          // another one. A ward pharmacy that supplies nobody has no use for it.
          if (isMain)
            TextField(
              controller: _supplyController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l10n.pharmacyLocationSupplyPriceLabel,
              ),
            ),
        ],
      ),
      actions: <Widget>[
        AppButton.secondary(
          label: l10n.commonCancelActionLabel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton.primary(
          label: l10n.commonSaveActionLabel,
          onPressed: () => Navigator.of(context).pop(
            _PriceEdit(
              sellPrice: _parse(_sellController),
              // Never carried over for a pharmacy that supplies nobody, so a
              // save here cannot write a supply price by accident.
              supplyPrice: isMain ? _parse(_supplyController) : null,
            ),
          ),
        ),
      ],
    );
  }
}
