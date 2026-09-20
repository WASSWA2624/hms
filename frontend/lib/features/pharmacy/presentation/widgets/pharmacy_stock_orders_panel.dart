import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/features/pharmacy/domain/entities/pharmacy_location_entities.dart';
import 'package:hosspi_hms/features/pharmacy/domain/repositories/pharmacy_location_repository.dart';
import 'package:hosspi_hms/features/pharmacy/presentation/controllers/pharmacy_location_controller.dart';
import 'package:hosspi_hms/features/pharmacy/presentation/widgets/pharmacy_location_display.dart';
import 'package:hosspi_hms/features/pharmacy/presentation/widgets/pharmacy_location_prices_dialog.dart';
import 'package:hosspi_hms/features/pharmacy/presentation/widgets/pharmacy_location_switcher.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/components/components.dart';
import 'package:hosspi_hms/shared/layout/app_workspace.dart';
import 'package:hosspi_hms/shared/layout/app_workspace_feedback.dart';

/// Cross-pharmacy stock view and the stock-order queues that follow from it.
///
/// Requirements 6 and 7 in one screen: the Hospital Pharmacy sees its own
/// balance next to what the Main Pharmacy has available (quantities only), and
/// every row that is short carries the Order action that starts the workflow.
/// The orders themselves then sit below, each showing the one step the pharmacy
/// looking at it must take next.
class PharmacyStockOrdersPanel extends ConsumerStatefulWidget {
  const PharmacyStockOrdersPanel({super.key});

  @override
  ConsumerState<PharmacyStockOrdersPanel> createState() =>
      _PharmacyStockOrdersPanelState();
}

class _PharmacyStockOrdersPanelState
    extends ConsumerState<PharmacyStockOrdersPanel> {
  bool _belowReorderOnly = false;

  /// Rows the user has staged for the next stock order: item id -> quantity.
  final Map<String, int> _draftLines = <String, int>{};

  PharmacyLocationController get _controller =>
      ref.read(pharmacyLocationControllerProvider.notifier);

  @override
  Widget build(BuildContext context) {
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
      return AppWorkspaceStatePanel.loading(
        title: l10n.pharmacyAvailabilityTitle,
        body: l10n.pharmacyAvailabilityBody,
      );
    }

    if (state.activeLocation == null) {
      return AppWorkspaceStatePanel.empty(
        title: l10n.pharmacyLocationNoneTitle,
        body: l10n.pharmacyLocationNoneBody,
        icon: Icons.local_pharmacy_outlined,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(child: PharmacyLocationSwitcher()),
            // This pharmacy's own prices, one click from the pharmacy it is
            // looking at, so the two are never confused with each other.
            AppButton.tertiary(
              key: const ValueKey<String>('pharmacyLocationPricesAction'),
              label: l10n.pharmacyLocationPricesTitle,
              leadingIcon: Icons.sell_outlined,
              onPressed: () => unawaited(
                showPharmacyLocationPricesDialog(context: context),
              ),
            ),
          ],
        ),
        SizedBox(height: theme.spacing.md),
        _AvailabilitySection(
          state: state,
          belowReorderOnly: _belowReorderOnly,
          draftLines: _draftLines,
          onBelowReorderChanged: (bool value) =>
              setState(() => _belowReorderOnly = value),
          onOrderRow: _stageRow,
          onSubmitDraft: _submitDraft,
          onClearDraft: () => setState(_draftLines.clear),
        ),
        SizedBox(height: theme.spacing.lg),
        _StockOrdersSection(state: state, onAct: _runOrderAction),
      ],
    );
  }

  void _stageRow(PharmacyAvailabilityRow row) {
    final int shortfall = (row.reorderLevel - row.quantity).clamp(1, 1 << 30);
    setState(() => _draftLines[row.inventoryItemId] = shortfall);
  }

  Future<void> _submitDraft(PharmacyLocationState state) async {
    if (_draftLines.isEmpty) return;

    final List<PharmacyStockOrderLineInput> items = <PharmacyStockOrderLineInput>[];
    for (final PharmacyAvailabilityRow row in state.availability) {
      final int? quantity = _draftLines[row.inventoryItemId];
      if (quantity == null || quantity <= 0) continue;
      final String? drugId = row.drugId;
      // A row with no drug mapping cannot be ordered; the catalog has to map it
      // to an inventory item first.
      if (drugId == null) continue;
      items.add(
        PharmacyStockOrderLineInput(
          drugId: drugId,
          inventoryItemId: row.inventoryItemId,
          requestedQuantity: quantity,
        ),
      );
    }

    if (items.isEmpty) return;

    final AppFailure? failure = await _controller.createStockOrder(items: items);
    if (!mounted) return;
    if (failure == null) {
      setState(_draftLines.clear);
    }
    _reportOutcome(failure);
  }

  Future<void> _runOrderAction(
    PharmacyStockOrder order,
    _StockOrderAction action,
  ) async {
    final AppFailure? failure = switch (action) {
      _StockOrderAction.submit => await _controller.submitStockOrder(order.id),
      _StockOrderAction.approve => await _controller.reviewStockOrder(
        order.id,
        approve: true,
      ),
      _StockOrderAction.reject => await _controller.reviewStockOrder(
        order.id,
        approve: false,
      ),
      _StockOrderAction.issue => await _controller.issueStockOrder(order.id),
      _StockOrderAction.receive => await _controller.receiveStockOrder(order.id),
      _StockOrderAction.cancel => await _controller.cancelStockOrder(order.id),
    };
    if (!mounted) return;
    _reportOutcome(failure);
  }

  void _reportOutcome(AppFailure? failure) {
    if (failure == null) return;
    showAppFailureSnackBar(context, failure);
  }
}

// ------------------------------------------------------------- availability

class _AvailabilitySection extends StatelessWidget {
  const _AvailabilitySection({
    required this.state,
    required this.belowReorderOnly,
    required this.draftLines,
    required this.onBelowReorderChanged,
    required this.onOrderRow,
    required this.onSubmitDraft,
    required this.onClearDraft,
  });

  final PharmacyLocationState state;
  final bool belowReorderOnly;
  final Map<String, int> draftLines;
  final ValueChanged<bool> onBelowReorderChanged;
  final ValueChanged<PharmacyAvailabilityRow> onOrderRow;
  final Future<void> Function(PharmacyLocationState state) onSubmitDraft;
  final VoidCallback onClearDraft;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final PharmacyLocation? supplier = state.supplyingLocation;
    final String supplierName = pharmacyLocationDisplayName(l10n, supplier);

    final List<PharmacyAvailabilityRow> rows = belowReorderOnly
        ? state.reorderSuggestions
        : state.availability;

    return AppCollapsibleSection(
      title: l10n.pharmacyAvailabilityTitle,
      subtitle: l10n.pharmacyAvailabilityBody,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              FilterChip(
                key: const ValueKey<String>('pharmacyAvailabilityBelowReorder'),
                label: Text(l10n.pharmacyAvailabilityBelowReorderFilter),
                selected: belowReorderOnly,
                onSelected: onBelowReorderChanged,
              ),
              const Spacer(),
              if (draftLines.isNotEmpty) ...<Widget>[
                AppButton.secondary(
                  label: l10n.commonCancelActionLabel,
                  onPressed: onClearDraft,
                ),
                SizedBox(width: theme.spacing.sm),
                AppButton.primary(
                  key: const ValueKey<String>('pharmacySubmitStockOrder'),
                  label: l10n.pharmacyStockOrderCreateAction,
                  leadingIcon: Icons.playlist_add_check_outlined,
                  onPressed: state.isRefreshing
                      ? null
                      : () => unawaited(onSubmitDraft(state)),
                ),
              ],
            ],
          ),
          SizedBox(height: theme.spacing.sm),
          if (supplier == null)
            AppWorkspaceStatePanel.empty(
              title: l10n.pharmacyAvailabilityNoSupplierLabel,
              body: l10n.pharmacyStockOrderNoStockChangeNotice,
              icon: Icons.sync_problem_outlined,
            )
          else if (rows.isEmpty)
            AppWorkspaceStatePanel.empty(
              title: l10n.pharmacyAvailabilityEmptyTitle,
              body: l10n.pharmacyAvailabilityEmptyBody,
              icon: Icons.inventory_2_outlined,
            )
          else
            _AvailabilityTable(
              rows: rows,
              supplierName: supplierName,
              draftLines: draftLines,
              canOrder: state.canOrderStock,
              onOrderRow: onOrderRow,
            ),
        ],
      ),
    );
  }
}

class _AvailabilityTable extends StatelessWidget {
  const _AvailabilityTable({
    required this.rows,
    required this.supplierName,
    required this.draftLines,
    required this.canOrder,
    required this.onOrderRow,
  });

  final List<PharmacyAvailabilityRow> rows;
  final String supplierName;
  final Map<String, int> draftLines;
  final bool canOrder;
  final ValueChanged<PharmacyAvailabilityRow> onOrderRow;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return AppListTable<PharmacyAvailabilityRow>(
      items: rows,
      shrinkWrap: true,
      itemKeyBuilder: (PharmacyAvailabilityRow row) =>
          ValueKey<String>(row.inventoryItemId),
      columns: <AppListTableColumn<PharmacyAvailabilityRow>>[
        AppListTableColumn<PharmacyAvailabilityRow>(
          id: 'medicine',
          label: l10n.pharmacyAvailabilityMedicineColumn,
          preferredWidth: 240,
          alwaysVisible: true,
          cellBuilder: (_, PharmacyAvailabilityRow row) => AppListItemText(
            title: row.inventoryItemName ?? row.inventoryItemId,
            subtitle: row.sku,
          ),
          exportValue: (PharmacyAvailabilityRow row) =>
              row.inventoryItemName ?? '',
        ),
        AppListTableColumn<PharmacyAvailabilityRow>(
          id: 'mine',
          label: l10n.pharmacyAvailabilityMineColumn,
          preferredWidth: 120,
          alwaysVisible: true,
          cellBuilder: (_, PharmacyAvailabilityRow row) => AppStatusBadge(
            label: '${row.quantity}',
            tone: pharmacyStockLevelTone(row.quantity, row.reorderLevel),
          ),
          exportValue: (PharmacyAvailabilityRow row) => '${row.quantity}',
        ),
        AppListTableColumn<PharmacyAvailabilityRow>(
          id: 'reorder',
          label: l10n.pharmacyAvailabilityReorderColumn,
          preferredWidth: 110,
          cellBuilder: (_, PharmacyAvailabilityRow row) =>
              Text('${row.reorderLevel}'),
          exportValue: (PharmacyAvailabilityRow row) => '${row.reorderLevel}',
        ),
        AppListTableColumn<PharmacyAvailabilityRow>(
          id: 'supplier',
          label: l10n.pharmacyAvailabilitySupplierColumn(supplierName),
          preferredWidth: 160,
          alwaysVisible: true,
          // Quantity only: the supplying pharmacy's purchase cost, supplier and
          // batches are never part of this view.
          cellBuilder: (_, PharmacyAvailabilityRow row) =>
              Text(row.supplierAvailable == null ? '—' : '${row.supplierAvailable}'),
          exportValue: (PharmacyAvailabilityRow row) =>
              row.supplierAvailable == null ? '' : '${row.supplierAvailable}',
        ),
        AppListTableColumn<PharmacyAvailabilityRow>(
          id: 'actions',
          label: l10n.pharmacyLineActionsColumnLabel,
          alwaysVisible: true,
          fixedWidth: 140,
          exportable: false,
          cellBuilder: (BuildContext context, PharmacyAvailabilityRow row) {
            final bool staged = draftLines.containsKey(row.inventoryItemId);
            if (!canOrder || !row.canOrder) {
              return const SizedBox.shrink();
            }
            return AppButton.tertiary(
              label: staged
                  ? '${l10n.pharmacyAvailabilityOrderAction} · ${draftLines[row.inventoryItemId]}'
                  : l10n.pharmacyAvailabilityOrderAction,
              leadingIcon: staged ? Icons.check : Icons.add_shopping_cart_outlined,
              onPressed: () => onOrderRow(row),
            );
          },
        ),
      ],
      mobileItemBuilder: (BuildContext context, PharmacyAvailabilityRow row) {
        return AppListTableMobileItem(
          title: row.inventoryItemName ?? row.inventoryItemId,
          caption: row.sku,
          meta: <AppListTableMobileMeta>[
            AppListTableMobileMeta(
              label: '${l10n.pharmacyAvailabilityMineColumn}: ${row.quantity}',
              icon: Icons.inventory_2_outlined,
            ),
            if (row.supplierAvailable != null)
              AppListTableMobileMeta(
                label: l10n.pharmacyAvailabilitySupplierColumn(
                  '$supplierName ${row.supplierAvailable}',
                ),
                icon: Icons.warehouse_outlined,
              ),
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------ stock orders

enum _StockOrderAction { submit, approve, reject, issue, receive, cancel }

class _StockOrdersSection extends StatelessWidget {
  const _StockOrdersSection({required this.state, required this.onAct});

  final PharmacyLocationState state;
  final Future<void> Function(PharmacyStockOrder order, _StockOrderAction action)
  onAct;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);

    final List<PharmacyStockOrder> inbox = state.inboxOrders;
    final List<PharmacyStockOrder> outbox = state.outboxOrders;

    return AppCollapsibleSection(
      title: l10n.pharmacyStockOrdersTitle,
      subtitle: l10n.pharmacyStockOrderNoStockChangeNotice,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (inbox.isEmpty && outbox.isEmpty)
            AppWorkspaceStatePanel.empty(
              title: l10n.pharmacyStockOrdersEmptyTitle,
              body: l10n.pharmacyStockOrdersEmptyBody,
              icon: Icons.assignment_outlined,
            )
          else ...<Widget>[
            if (inbox.isNotEmpty) ...<Widget>[
              Text(
                l10n.pharmacyStockOrdersInboxTab,
                style: theme.textTheme.titleSmall,
              ),
              SizedBox(height: theme.spacing.xs),
              _StockOrderTable(
                orders: inbox,
                locationId: state.activeLocationId,
                onAct: onAct,
              ),
              SizedBox(height: theme.spacing.md),
            ],
            if (outbox.isNotEmpty) ...<Widget>[
              Text(
                l10n.pharmacyStockOrdersOutboxTab,
                style: theme.textTheme.titleSmall,
              ),
              SizedBox(height: theme.spacing.xs),
              _StockOrderTable(
                orders: outbox,
                locationId: state.activeLocationId,
                onAct: onAct,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _StockOrderTable extends StatelessWidget {
  const _StockOrderTable({
    required this.orders,
    required this.locationId,
    required this.onAct,
  });

  final List<PharmacyStockOrder> orders;
  final String? locationId;
  final Future<void> Function(PharmacyStockOrder order, _StockOrderAction action)
  onAct;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return AppListTable<PharmacyStockOrder>(
      items: orders,
      shrinkWrap: true,
      itemKeyBuilder: (PharmacyStockOrder order) => ValueKey<String>(order.id),
      columns: <AppListTableColumn<PharmacyStockOrder>>[
        AppListTableColumn<PharmacyStockOrder>(
          id: 'reference',
          label: l10n.pharmacyStockOrderReferenceColumn,
          preferredWidth: 150,
          alwaysVisible: true,
          cellBuilder: (_, PharmacyStockOrder order) =>
              Text(order.effectiveId),
          exportValue: (PharmacyStockOrder order) => order.effectiveId,
        ),
        AppListTableColumn<PharmacyStockOrder>(
          id: 'counterparty',
          label: l10n.pharmacyStockOrderCounterpartyColumn,
          preferredWidth: 180,
          alwaysVisible: true,
          cellBuilder: (_, PharmacyStockOrder order) {
            final bool isRequester = order.requestingLocationId == locationId;
            final String name =
                (isRequester
                    ? order.supplyingLocationName
                    : order.requestingLocationName) ??
                '—';
            return Text(name);
          },
          exportValue: (PharmacyStockOrder order) =>
              order.supplyingLocationName ?? '',
        ),
        AppListTableColumn<PharmacyStockOrder>(
          id: 'lines',
          label: l10n.pharmacyStockOrderLinesColumn,
          preferredWidth: 90,
          cellBuilder: (_, PharmacyStockOrder order) =>
              Text('${order.items.length}'),
          exportValue: (PharmacyStockOrder order) => '${order.items.length}',
        ),
        AppListTableColumn<PharmacyStockOrder>(
          id: 'quantity',
          label: l10n.pharmacyStockOrderQuantityColumn,
          preferredWidth: 140,
          cellBuilder: (_, PharmacyStockOrder order) {
            // In transit is the gap between the two legs, which is the honest
            // answer for a shipment that has left one pharmacy but not arrived.
            if (order.inTransitTotal > 0) {
              return AppStatusBadge(
                label: l10n.pharmacyStockOrderInTransitLabel(
                  order.inTransitTotal,
                ),
                tone: AppWorkspaceStatusTone.info,
                icon: Icons.local_shipping_outlined,
              );
            }
            return Text('${order.requestedTotal}');
          },
          exportValue: (PharmacyStockOrder order) => '${order.requestedTotal}',
        ),
        AppListTableColumn<PharmacyStockOrder>(
          id: 'status',
          label: l10n.pharmacyStockOrderStatusColumn,
          preferredWidth: 160,
          alwaysVisible: true,
          cellBuilder: (_, PharmacyStockOrder order) => AppStatusBadge(
            label: pharmacyStockOrderStatusLabel(l10n, order.status),
            tone: pharmacyStockOrderStatusTone(order.status),
            icon: pharmacyStockOrderStatusIcon(order.status),
          ),
          exportValue: (PharmacyStockOrder order) =>
              pharmacyStockOrderStatusLabel(l10n, order.status),
        ),
        AppListTableColumn<PharmacyStockOrder>(
          id: 'next_action',
          label: l10n.pharmacyStockOrderNextActionColumn,
          alwaysVisible: true,
          fixedWidth: 220,
          exportable: false,
          // The status sits right beside the one thing this pharmacy can do
          // about it, so a queue never becomes a list of read-only states.
          cellBuilder: (BuildContext context, PharmacyStockOrder order) =>
              _StockOrderActions(
                order: order,
                locationId: locationId,
                onAct: onAct,
              ),
        ),
      ],
      mobileItemBuilder: (BuildContext context, PharmacyStockOrder order) {
        return AppListTableMobileItem(
          title: order.effectiveId,
          caption: order.supplyingLocationName,
          meta: <AppListTableMobileMeta>[
            AppListTableMobileMeta(
              label: pharmacyStockOrderStatusLabel(l10n, order.status),
              icon: pharmacyStockOrderStatusIcon(order.status),
            ),
            AppListTableMobileMeta(
              label: '${order.items.length}',
              icon: Icons.list_alt_outlined,
            ),
          ],
        );
      },
    );
  }
}

class _StockOrderActions extends StatelessWidget {
  const _StockOrderActions({
    required this.order,
    required this.locationId,
    required this.onAct,
  });

  final PharmacyStockOrder order;
  final String? locationId;
  final Future<void> Function(PharmacyStockOrder order, _StockOrderAction action)
  onAct;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);

    if (locationId == null || order.isTerminal) {
      return const SizedBox.shrink();
    }

    final bool isRequester = order.requestingLocationId == locationId;
    final bool isSupplier = order.supplyingLocationId == locationId;

    final List<Widget> actions = <Widget>[];

    if (isRequester && order.isEditable) {
      actions.add(
        AppButton.primary(
          label: l10n.pharmacyStockOrderSubmitAction,
          leadingIcon: Icons.send_outlined,
          onPressed: () => unawaited(onAct(order, _StockOrderAction.submit)),
        ),
      );
    }

    if (isSupplier && order.awaitsReview) {
      actions.addAll(<Widget>[
        AppButton.primary(
          label: l10n.pharmacyStockOrderApproveAction,
          leadingIcon: Icons.check_circle_outline,
          onPressed: () => unawaited(onAct(order, _StockOrderAction.approve)),
        ),
        SizedBox(width: theme.spacing.xs),
        AppButton.tertiary(
          label: l10n.pharmacyStockOrderRejectAction,
          leadingIcon: Icons.cancel_outlined,
          onPressed: () => unawaited(onAct(order, _StockOrderAction.reject)),
        ),
      ]);
    }

    if (isSupplier && order.awaitsIssue) {
      actions.add(
        AppButton.primary(
          label: l10n.pharmacyStockOrderIssueAction,
          leadingIcon: Icons.local_shipping_outlined,
          onPressed: () => unawaited(onAct(order, _StockOrderAction.issue)),
        ),
      );
    }

    if (isRequester && order.awaitsReceipt) {
      actions.add(
        AppButton.primary(
          label: l10n.pharmacyStockOrderReceiveAction,
          leadingIcon: Icons.inventory_outlined,
          onPressed: () => unawaited(onAct(order, _StockOrderAction.receive)),
        ),
      );
    }

    if (actions.isEmpty && order.isCancellable) {
      actions.add(
        AppButton.tertiary(
          label: l10n.pharmacyStockOrderCancelAction,
          leadingIcon: Icons.block_outlined,
          onPressed: () => unawaited(onAct(order, _StockOrderAction.cancel)),
        ),
      );
    }

    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: theme.spacing.xs,
      runSpacing: theme.spacing.xs,
      children: actions,
    );
  }
}
