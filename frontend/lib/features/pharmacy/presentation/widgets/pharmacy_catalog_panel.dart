import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/permissions/access_gate.dart';
import 'package:hosspi_hms/core/permissions/access_policy.dart';
import 'package:hosspi_hms/core/permissions/access_requirement.dart';
import 'package:hosspi_hms/core/permissions/permission_providers.dart';
import 'package:hosspi_hms/core/security/session_controller.dart';
import 'package:hosspi_hms/core/utils/app_formatters.dart';
import 'package:hosspi_hms/features/pharmacy/domain/entities/pharmacy_drug_import.dart';
import 'package:hosspi_hms/features/pharmacy/domain/entities/pharmacy_entities.dart';
import 'package:hosspi_hms/features/pharmacy/presentation/controllers/pharmacy_workspace_controller.dart';
import 'package:hosspi_hms/features/pharmacy/presentation/pharmacy_access.dart';
import 'package:hosspi_hms/features/pharmacy/presentation/widgets/pharmacy_catalog_tabs.dart';
import 'package:hosspi_hms/features/pharmacy/presentation/widgets/pharmacy_stock_orders_panel.dart';
import 'package:hosspi_hms/features/pharmacy/presentation/widgets/pharmacy_drug_details_dialog.dart';
import 'package:hosspi_hms/features/pharmacy/presentation/widgets/pharmacy_drug_edit_dialog.dart';
import 'package:hosspi_hms/features/pharmacy/presentation/widgets/pharmacy_drug_import_dialog.dart';
import 'package:hosspi_hms/features/pharmacy/presentation/widgets/pharmacy_storage_panel.dart';
import 'package:hosspi_hms/features/pharmacy/presentation/widgets/pharmacy_workspace_print_helpers.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/actions/app_action_dialogs.dart';
import 'package:hosspi_hms/shared/components/components.dart';
import 'package:hosspi_hms/shared/data/data.dart';
import 'package:hosspi_hms/shared/forms/forms.dart';
import 'package:hosspi_hms/shared/layout/app_workspace.dart';
import 'package:hosspi_hms/shared/layout/app_workspace_feedback.dart';

const String _inventoryStockStatusFilterKey = 'stock_status';
const String _storageRoomFilterKey = 'storage_room';
const String _storageShelfFilterKey = 'storage_shelf';
const String _formularyActiveFilterKey = 'is_active';
const String _drugStockStatusFilterKey = 'stock_status';
const String _drugNameFilterKey = 'name';
const String _drugCodeFilterKey = 'code';
const String _drugFormFilterKey = 'form';
const String _drugStrengthFilterKey = 'strength';
const String _inventoryItemNameFilterKey = 'item_name';
const String _inventorySkuFilterKey = 'sku';
const String _inventoryFacilityFilterKey = 'facility';
const String _inventoryPendingFilterKey = 'pending_stock';

class PharmacyCatalogPanel extends ConsumerStatefulWidget {
  const PharmacyCatalogPanel({
    required this.state,
    this.fillHeight = false,
    super.key,
  });

  final PharmacyWorkspaceState state;
  final bool fillHeight;

  @override
  ConsumerState<PharmacyCatalogPanel> createState() =>
      _PharmacyCatalogPanelState();
}

class _PharmacyCatalogPanelState extends ConsumerState<PharmacyCatalogPanel> {
  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final PharmacyWorkspaceState state =
        ref
            .watch(pharmacyWorkspaceControllerProvider)
            .value
            ?.when(
              success: (PharmacyWorkspaceState value) => value,
              failure: (_) => widget.state,
            ) ??
        widget.state;
    final PharmacyWorkspaceController controller = ref.read(
      pharmacyWorkspaceControllerProvider.notifier,
    );
    final PharmacyCatalogTab tab = state.catalogTab;
    final List<PharmacyCatalogTabDescriptor> tabDescriptors =
        pharmacyCatalogTabDescriptors(l10n);

    final List<Widget> tabViews = <Widget>[
      _DrugCatalogTab(
        state: state,
        writeRequirement: pharmacyCatalogWriteRequirement,
        fillHeight: widget.fillHeight,
      ),
      _FormularyCatalogTab(
        state: state,
        writeRequirement: pharmacyCatalogWriteRequirement,
        fillHeight: widget.fillHeight,
      ),
      _InventoryCatalogTab(
        state: state,
        writeRequirement: pharmacyCatalogWriteRequirement,
        fillHeight: widget.fillHeight,
      ),
      _StorageLayoutCatalogTab(
        state: state,
        writeRequirement: pharmacyCatalogWriteRequirement,
        fillHeight: widget.fillHeight,
      ),
      _ShelvesCatalogTab(
        state: state,
        writeRequirement: pharmacyCatalogWriteRequirement,
        fillHeight: widget.fillHeight,
      ),
      // Scoped to the selected pharmacy rather than the facility, so Main and
      // Hospital stock never appear as one balance.
      //
      // Built only while selected. IndexedStack builds every child eagerly, and
      // this one owns its own async load, so mounting it behind the other tabs
      // would leave a progress indicator animating in a hidden branch and stop
      // the catalog from ever settling.
      if (tab == PharmacyCatalogTab.stockOrders)
        const SingleChildScrollView(child: PharmacyStockOrdersPanel())
      else
        const SizedBox.shrink(),
    ];
    final Widget tabContent = IndexedStack(
      index: tab.index,
      sizing: StackFit.expand,
      children: tabViews,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PharmacyCatalogIconTabBar(
          tabs: tabDescriptors,
          selectedTab: tab,
          onTabSelected: controller.setCatalogTab,
        ),
        SizedBox(height: Theme.of(context).spacing.md),
        if (widget.fillHeight) Expanded(child: tabContent) else tabContent,
      ],
    );
  }
}

class _DrugCatalogTab extends ConsumerStatefulWidget {
  const _DrugCatalogTab({
    required this.state,
    required this.writeRequirement,
    this.fillHeight = false,
  });

  final PharmacyWorkspaceState state;
  final AccessRequirement writeRequirement;
  final bool fillHeight;

  @override
  ConsumerState<_DrugCatalogTab> createState() => _DrugCatalogTabState();
}

class _DrugCatalogTabState extends ConsumerState<_DrugCatalogTab> {
  late final TextEditingController _searchController;
  final Set<String> _selectedDrugIds = <String>{};
  final ValueNotifier<int> _selectionTick = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: widget.state.drugQuery.search,
    );
  }

  @override
  void dispose() {
    _selectionTick.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _mutateDrugSelection(void Function() mutate) {
    mutate();
    _selectionTick.value++;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final PharmacyWorkspaceController controller = ref.read(
      pharmacyWorkspaceControllerProvider.notifier,
    );

    final PharmacyDrugQuery drugQuery = widget.state.drugQuery;
    final bool isBusy = widget.state.isRefreshingDrugs;
    final bool hasSelection = _selectedDrugIds.isNotEmpty;
    final AppAccessPolicy policy = ref.watch(appAccessPolicyProvider);
    final bool canExport = canExportPharmacyWorkspace(policy);
    final bool canPrint = canPrintPharmacyWorkspace(policy);

    final Widget table = AppListTable<PharmacyDrug>(
      page: widget.state.drugs,
      isLoading: isBusy,
      rowsVersion: _selectionTick.value,
      columnVisibilityStorageKey: 'pharmacy_catalog_drugs',
      columnVisibilityLabel: l10n.commonTableSettingsActionLabel,
      columnVisibilityTitle: l10n.commonTableSettingsTitle,
      columnVisibilityApplyLabel: l10n.receptionApplyColumnsAction,
      columnVisibilityResetLabel: l10n.receptionResetColumnsAction,
      columnVisibilityCloseLabel: l10n.commonCloseActionLabel,
      shrinkWrap: !widget.fillHeight,
      enableExport: true,
      canExport: canExport,
      exportLabel: l10n.commonTableExportActionLabel,
      exportDialogTitle: l10n.commonTableExportDialogTitle,
      exportCancelLabel: l10n.commonCancelActionLabel,
      exportColumnsSectionLabel: l10n.commonTableExportColumnsSectionLabel,
      exportFiltersSectionLabel: l10n.commonTableExportFiltersSectionLabel,
      exportEmptyColumnsMessage: l10n.commonTableExportEmptyColumnsMessage,
      exportEmptyRowsMessage: l10n.commonTableExportEmptyRowsMessage,
      exportSuccessMessage: l10n.commonTableExportSuccessMessage,
      exportFailureMessage: l10n.commonTableExportFailureMessage,
      enablePrint: true,
      canPrint: canPrint,
      printLabel: l10n.commonPrintActionLabel,
      onPrint: (List<PharmacyDrug> items) => _printPharmacyDrugsList(
        context,
        ref,
        l10n: l10n,
        drugs: items,
      ),
      goToTopLabel: l10n.commonGoToTopActionLabel,
      loadingMoreLabel: l10n.commonLoadingMoreLabel,
      allRowsLoadedLabel: l10n.commonAllRowsLoadedLabel,
      exportConfig: AppListTableExportConfig<PharmacyDrug>(
        fileNameStem: 'pharmacy_drugs',
        dateOf: (PharmacyDrug item) => item.createdAt,
        dateFromLabel: l10n.commonTableExportDateFromLabel,
        dateToLabel: l10n.commonTableExportDateToLabel,
      ),
      loadingBuilder: (BuildContext context) {
        final ThemeData theme = Theme.of(context);
        return Padding(
          padding: EdgeInsets.symmetric(vertical: theme.spacing.xl),
          child: AppLoadingIndicator.compact(
            title: l10n.pharmacyDrugsLoadingTitle,
            body: l10n.pharmacyDrugsLoadingBody,
          ),
        );
      },
      search: AppListTableSearch<PharmacyDrug>(
        controller: _searchController,
        semanticLabel: l10n.pharmacyDrugSearchLabel,
        hintText: l10n.pharmacyDrugSearchHint,
        matcher: (_, _) => true,
        onSubmitted: controller.applyDrugSearch,
        onClear: () => unawaited(controller.applyDrugSearch('')),
        showAdvancedFilterButton: true,
        advancedFilterButtonLabel: l10n.commonFiltersActionLabel,
        advancedFilterTitle: l10n.commonAdvancedFiltersTitle,
        advancedFilterApplyLabel: l10n.opdApplyFiltersAction,
        advancedFilterResetLabel: l10n.opdClearFiltersAction,
        advancedFilterCloseLabel: l10n.commonCloseActionLabel,
        enableDateFilter: false,
        allFieldsLabel: l10n.opdAllFieldsFilterLabel,
        textFilters: <AppSearchBarTextFilter>[
          AppSearchBarTextFilter(
            key: _drugNameFilterKey,
            label: l10n.pharmacyDrugGenericNameLabel,
            hintText: l10n.pharmacyDrugGenericNameLabel,
            icon: Icons.medication_outlined,
          ),
          AppSearchBarTextFilter(
            key: _drugCodeFilterKey,
            label: l10n.pharmacyDrugCodeLabel,
            icon: Icons.qr_code_2_outlined,
          ),
          AppSearchBarTextFilter(
            key: _drugFormFilterKey,
            label: l10n.pharmacyDrugFormLabel,
            icon: Icons.science_outlined,
          ),
          AppSearchBarTextFilter(
            key: _drugStrengthFilterKey,
            label: l10n.pharmacyDrugStrengthLabel,
            icon: Icons.straighten_outlined,
          ),
        ],
        filterGroups: _drugCatalogFilterGroups(
          l10n: l10n,
          layout: widget.state.storageLayout,
          storageRoomId: drugQuery.storageRoomId,
        ),
        filterValue: _drugCatalogFilterValue(drugQuery),
        hasActiveFilters: _hasDrugCatalogFilters(drugQuery),
        onFilterChanged: (AppSearchBarFilterValue value) {
          unawaited(_applyDrugCatalogFilter(controller, value));
        },
        trailingActions: _catalogSearchTrailingActions(
          ref: ref,
          writeRequirement: widget.writeRequirement,
          isBusy: isBusy,
          hasSelection: hasSelection,
          importLabel: l10n.pharmacyDrugImportAction,
          importSemanticLabel: l10n.pharmacyDrugImportActionTooltip,
          onImport: () => unawaited(_openDrugImportDialog(context)),
          addLabel: l10n.commonCreateActionLabel,
          addSemanticLabel: l10n.pharmacyAddDrugAction,
          onAdd: () => _openDrugDialog(context),
          selectionLabel: l10n.pharmacyDeleteSelectedDrugsAction,
          onSelectionAction: () => _confirmDeleteSelectedDrugs(context),
        ),
      ),
      onPageChanged: controller.changeDrugPage,
      emptyBuilder: (_) => AppWorkspaceStatePanel.state(
        variant: AppStateViewVariant.empty,
        title: l10n.pharmacyNoDrugsTitle,
        body: l10n.pharmacyNoDrugsBody,
        icon: Icons.medication_outlined,
      ),
      columns: <AppListTableColumn<PharmacyDrug>>[
        _selectionColumn<PharmacyDrug>(
          visibleItems: widget.state.drugs.items,
          selectedKeys: _selectedDrugIds,
          selectionTick: _selectionTick,
          isBusy: isBusy,
          itemKey: (PharmacyDrug item) => item.id,
          onToggle: (PharmacyDrug item, bool selected) {
            _mutateDrugSelection(() {
              if (selected) {
                _selectedDrugIds.add(item.id);
              } else {
                _selectedDrugIds.remove(item.id);
              }
            });
          },
          onToggleAll: (List<PharmacyDrug> items, bool selected) {
            _mutateDrugSelection(() {
              if (!selected) {
                for (final PharmacyDrug item in items) {
                  _selectedDrugIds.remove(item.id);
                }
                return;
              }
              for (final PharmacyDrug item in items) {
                _selectedDrugIds.add(item.id);
              }
            });
          },
        ),
        AppListTableColumn<PharmacyDrug>(
          id: 'code',
          label: l10n.pharmacyDrugCodeLabel,
          preferredWidth: 120,
          alwaysVisible: true,
          exportValue: (PharmacyDrug item) => item.code ?? '',
          cellBuilder: (_, PharmacyDrug item) => Text(item.code ?? ''),
        ),
        AppListTableColumn<PharmacyDrug>(
          id: 'generic_name',
          label: l10n.pharmacyDrugGenericNameLabel,
          preferredWidth: 180,
          alwaysVisible: true,
          cellBuilder: (_, PharmacyDrug item) {
            final String generic = (item.genericName ?? '').trim();
            if (generic.isNotEmpty) {
              return Text(generic);
            }
            // Legacy rows stored the scientific name in `name`.
            final String legacy = (item.name ?? '').trim();
            return Text(legacy.isEmpty ? '—' : legacy);
          },
          exportValue: (PharmacyDrug item) {
            final String generic = (item.genericName ?? '').trim();
            if (generic.isNotEmpty) {
              return generic;
            }
            return item.name ?? '';
          },
        ),
        AppListTableColumn<PharmacyDrug>(
          id: 'brand_name',
          label: l10n.pharmacyDrugBrandNameLabel,
          preferredWidth: 160,
          alwaysVisible: true,
          cellBuilder: (_, PharmacyDrug item) =>
              Text((item.brandName ?? '').trim().isEmpty
                  ? '—'
                  : item.brandName!.trim()),
          exportValue: (PharmacyDrug item) => item.brandName ?? '',
        ),
        AppListTableColumn<PharmacyDrug>(
          id: 'actions',
          label: l10n.pharmacyLineActionsColumnLabel,
          alwaysVisible: true,
          // Wide enough for the dense Edit + Delete buttons; narrower widths
          // make the actions row overflow now that grid columns are fixed.
          fixedWidth: 240,
          cellBuilder: (BuildContext context, PharmacyDrug item) {
            return _catalogRowActions(
              context: context,
              writeRequirement: widget.writeRequirement,
              isBusy: isBusy,
              alignStart: true,
              editLabel: l10n.commonEditActionLabel,
              deleteLabel: l10n.commonDeleteActionLabel,
              editSemanticLabel: l10n.pharmacyEditDrugAction,
              deleteSemanticLabel: l10n.pharmacyDeleteDrugAction,
              onEdit: () => _openDrugDialog(context, drug: item),
              onDelete: () => unawaited(_confirmDeleteDrug(context, item)),
            );
          },
        ),
      ],
      columnChoices: <AppListTableColumn<PharmacyDrug>>[
        AppListTableColumn<PharmacyDrug>(
          id: 'form',
          label: l10n.pharmacyDrugFormLabel,
          preferredWidth: 120,
          cellBuilder: (_, PharmacyDrug item) =>
              Text((item.form ?? '').trim().isEmpty ? '—' : item.form!.trim()),
          exportValue: (PharmacyDrug item) => item.form ?? '',
        ),
        AppListTableColumn<PharmacyDrug>(
          id: 'strength',
          label: l10n.pharmacyDrugStrengthLabel,
          cellBuilder: (_, PharmacyDrug item) => Text(
            (item.strength ?? '').trim().isEmpty ? '—' : item.strength!.trim(),
          ),
          exportValue: (PharmacyDrug item) => item.strength ?? '',
        ),
        AppListTableColumn<PharmacyDrug>(
          id: 'buy_price',
          label: l10n.pharmacyBuyPriceLabel,
          exportValue: (PharmacyDrug item) => _priceText(item.buyUnitPrice),
          cellBuilder: (_, PharmacyDrug item) =>
              Text(_priceText(item.buyUnitPrice)),
        ),
        AppListTableColumn<PharmacyDrug>(
          id: 'pharmacy_price',
          label: l10n.pharmacyPharmacyPriceLabel,
          exportValue: (PharmacyDrug item) =>
              _priceText(item.pharmacyUnitPrice ?? item.unitPrice),
          cellBuilder: (_, PharmacyDrug item) =>
              Text(_priceText(item.pharmacyUnitPrice ?? item.unitPrice)),
        ),
        AppListTableColumn<PharmacyDrug>(
          id: 'transfer_price',
          label: l10n.pharmacyTransferPriceLabel,
          exportValue: (PharmacyDrug item) =>
              _priceText(item.transferUnitPrice),
          cellBuilder: (_, PharmacyDrug item) =>
              Text(_priceText(item.transferUnitPrice)),
        ),
        AppListTableColumn<PharmacyDrug>(
          id: 'facility_price',
          label: l10n.pharmacyFacilityPriceLabel,
          exportValue: (PharmacyDrug item) =>
              _priceText(item.facilityUnitPrice),
          cellBuilder: (_, PharmacyDrug item) =>
              Text(_priceText(item.facilityUnitPrice)),
        ),
        AppListTableColumn<PharmacyDrug>(
          id: 'storage_location',
          label: l10n.pharmacyStorageLocationColumnLabel,
          exportValue: (PharmacyDrug item) => item.storageLocationLabel ?? '',
          cellBuilder: (_, PharmacyDrug item) =>
              Text(item.storageLocationLabel ?? '—'),
        ),
        AppListTableColumn<PharmacyDrug>(
          id: 'reorder_level',
          label: l10n.pharmacyReorderLevelColumnLabel,
          numeric: true,
          exportValue: (PharmacyDrug item) {
            final num reorderLevel = item.stockRows.isNotEmpty
                ? item.stockRows.first.reorderLevel
                : 0;
            return reorderLevel.toString();
          },
          cellBuilder: (_, PharmacyDrug item) {
            final num reorderLevel = item.stockRows.isNotEmpty
                ? item.stockRows.first.reorderLevel
                : 0;
            return Text(reorderLevel.toString());
          },
        ),
        AppListTableColumn<PharmacyDrug>(
          id: 'stock_status',
          label: l10n.pharmacyStockStatusFilterLabel,
          exportValue: (PharmacyDrug item) =>
              _stockStatus(context, item.stockStatus).label,
          cellBuilder: (BuildContext context, PharmacyDrug item) {
            return AppWorkspaceStatusBadge(
              status: _stockStatus(context, item.stockStatus),
            );
          },
        ),
      ],
      onRowSelected: (PharmacyDrug item) {
        unawaited(
          openPharmacyDrugDetailsDialog(
            context,
            ref,
            drug: item,
            writeRequirement: widget.writeRequirement,
            onDelete: (PharmacyDrug drug) => _confirmDeleteDrug(context, drug),
          ),
        );
      },
      mobileItemBuilder: (BuildContext context, PharmacyDrug item) {
        return AppListTableMobileItem(
          leading: Checkbox(
            value: _selectedDrugIds.contains(item.id),
            onChanged: isBusy
                ? null
                : (bool? value) {
                    _mutateDrugSelection(() {
                      if (value ?? false) {
                        _selectedDrugIds.add(item.id);
                      } else {
                        _selectedDrugIds.remove(item.id);
                      }
                    });
                  },
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          title: item.displayTitle,
          caption: item.code,
          showAvatar: false,
        );
      },
    );

    return table;
  }

  Future<void> _openDrugImportDialog(BuildContext context) async {
    final PharmacyWorkspaceController controller = ref.read(
      pharmacyWorkspaceControllerProvider.notifier,
    );
    final PharmacyDrugImportResult? result =
        await showAppDialog<PharmacyDrugImportResult>(
          context: context,
          builder: (_) => PharmacyDrugImportDialog(
            facilityName: ref
                .read(sessionStateProvider)
                .session
                ?.user
                ?.facilityName,
            onPreview: controller.previewDrugImport,
            onCommit: controller.commitDrugImport,
          ),
        );
    if (!context.mounted || result == null) {
      return;
    }
    showAppSuccessSnackBar(
      context,
      context.l10n.pharmacyDrugImportSuccessMessage(result.importedProducts),
    );
  }

  Future<void> _openDrugDialog(BuildContext context, {PharmacyDrug? drug}) async {
    final PharmacyDrugFormResult? result =
        await showAppDialog<PharmacyDrugFormResult>(
          context: context,
          builder: (_) => PharmacyDrugEditDialog(drug: drug),
        );
    if (!context.mounted || result == null) {
      return;
    }
    final PharmacyDrug? detailsDrug = result.drug;
    // After create, edit, replace, or Use existing, open details — same pattern as rooms.
    final bool openDetails =
        detailsDrug != null && (result.useExisting || result.saved);
    if (!openDetails) {
      return;
    }
    await openPharmacyDrugDetailsDialog(
      context,
      ref,
      drug: detailsDrug,
      writeRequirement: widget.writeRequirement,
      onDelete: (PharmacyDrug item) => _confirmDeleteDrug(context, item),
    );
  }

  Future<bool> _confirmDeleteDrug(
    BuildContext context,
    PharmacyDrug drug,
  ) async {
    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (_) => AppConfirmActionDialog(
        title: l10n.pharmacyDeleteDrugDialogTitle,
        body: l10n.pharmacyDeleteDrugDialogBody,
        highlightedText: drug.displayTitle,
        submitLabel: l10n.pharmacyDeleteDrugAction,
        destructive: true,
        icon: const Icon(AppActionIcons.delete),
        submitLeadingIcon: AppActionIcons.delete,
        onConfirm: () => ref
            .read(pharmacyWorkspaceControllerProvider.notifier)
            .deleteDrug(drug.id),
      ),
    );
    if (confirmed != true || !context.mounted) {
      return false;
    }
    setState(() => _selectedDrugIds.remove(drug.id));
    return true;
  }

  Future<void> _confirmDeleteSelectedDrugs(BuildContext context) async {
    final AppLocalizations l10n = context.l10n;
    final int count = _selectedDrugIds.length;
    if (count == 0) {
      return;
    }
    final List<String> ids = _selectedDrugIds.toList(growable: false);
    final PharmacyWorkspaceController controller = ref.read(
      pharmacyWorkspaceControllerProvider.notifier,
    );
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (_) => AppConfirmActionDialog(
        title: l10n.pharmacyDeleteSelectedDrugsDialogTitle,
        body: l10n.pharmacyDeleteSelectedDrugsDialogBody(count),
        submitLabel: l10n.pharmacyDeleteDrugAction,
        destructive: true,
        icon: const Icon(AppActionIcons.delete),
        submitLeadingIcon: AppActionIcons.delete,
        onConfirm: () async {
          for (final String drugId in ids) {
            final AppFailure? failure = await controller.deleteDrug(drugId);
            if (failure != null) {
              return failure;
            }
          }
          return null;
        },
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    setState(_selectedDrugIds.clear);
  }
}

class _FormularyCatalogTab extends ConsumerStatefulWidget {
  const _FormularyCatalogTab({
    required this.state,
    required this.writeRequirement,
    this.fillHeight = false,
  });

  final PharmacyWorkspaceState state;
  final AccessRequirement writeRequirement;
  final bool fillHeight;

  @override
  ConsumerState<_FormularyCatalogTab> createState() =>
      _FormularyCatalogTabState();
}

class _FormularyCatalogTabState extends ConsumerState<_FormularyCatalogTab> {
  final Set<String> _selectedFormularyIds = <String>{};
  final ValueNotifier<int> _selectionTick = ValueNotifier<int>(0);
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: widget.state.formularyQuery.search,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (widget.state.formularyItems.items.isEmpty) {
        unawaited(
          ref
              .read(pharmacyWorkspaceControllerProvider.notifier)
              .applyFormularySearch(''),
        );
      }
    });
  }

  @override
  void dispose() {
    _selectionTick.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _mutateFormularySelection(void Function() mutate) {
    mutate();
    _selectionTick.value++;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final PharmacyWorkspaceController controller = ref.read(
      pharmacyWorkspaceControllerProvider.notifier,
    );
    final bool isBusy = widget.state.isRefreshingFormulary;

    final PharmacyFormularyQuery formularyQuery = widget.state.formularyQuery;
    final bool hasSelection = _selectedFormularyIds.isNotEmpty;
    final AppAccessPolicy policy = ref.watch(appAccessPolicyProvider);
    final bool canExport = canExportPharmacyWorkspace(policy);
    final bool canPrint = canPrintPharmacyWorkspace(policy);

    final Widget table = AppListTable<PharmacyFormularyItem>(
      page: widget.state.formularyItems,
      isLoading: isBusy,
      rowsVersion: _selectionTick.value,
      columnVisibilityStorageKey: 'pharmacy_catalog_formulary',
      columnVisibilityLabel: l10n.commonTableSettingsActionLabel,
      columnVisibilityTitle: l10n.commonTableSettingsTitle,
      columnVisibilityApplyLabel: l10n.receptionApplyColumnsAction,
      columnVisibilityResetLabel: l10n.receptionResetColumnsAction,
      columnVisibilityCloseLabel: l10n.commonCloseActionLabel,
      shrinkWrap: !widget.fillHeight,
      onPageChanged: controller.changeFormularyPage,
      enableExport: true,
      canExport: canExport,
      exportLabel: l10n.commonTableExportActionLabel,
      exportDialogTitle: l10n.commonTableExportDialogTitle,
      exportCancelLabel: l10n.commonCancelActionLabel,
      exportColumnsSectionLabel: l10n.commonTableExportColumnsSectionLabel,
      exportFiltersSectionLabel: l10n.commonTableExportFiltersSectionLabel,
      exportEmptyColumnsMessage: l10n.commonTableExportEmptyColumnsMessage,
      exportEmptyRowsMessage: l10n.commonTableExportEmptyRowsMessage,
      exportSuccessMessage: l10n.commonTableExportSuccessMessage,
      exportFailureMessage: l10n.commonTableExportFailureMessage,
      enablePrint: true,
      canPrint: canPrint,
      printLabel: l10n.commonPrintActionLabel,
      onPrint: (List<PharmacyFormularyItem> items) =>
          _printPharmacyFormularyList(
        context,
        ref,
        l10n: l10n,
        items: items,
      ),
      goToTopLabel: l10n.commonGoToTopActionLabel,
      loadingMoreLabel: l10n.commonLoadingMoreLabel,
      allRowsLoadedLabel: l10n.commonAllRowsLoadedLabel,
      exportConfig: AppListTableExportConfig<PharmacyFormularyItem>(
        fileNameStem: 'pharmacy_formulary',
        dateOf: (PharmacyFormularyItem item) => item.createdAt,
        dateFromLabel: l10n.commonTableExportDateFromLabel,
        dateToLabel: l10n.commonTableExportDateToLabel,
        rowFilter: (PharmacyFormularyItem item, AppSearchBarFilterValue filters) {
          return _matchesFormularyExportFilters(item, filters);
        },
      ),
      search: AppListTableSearch<PharmacyFormularyItem>(
        controller: _searchController,
        semanticLabel: l10n.pharmacyFormularyDrugLabel,
        hintText: l10n.pharmacyDrugSearchHint,
        matcher: (_, _) => true,
        onSubmitted: controller.applyFormularySearch,
        onClear: () => unawaited(controller.applyFormularySearch('')),
        showAdvancedFilterButton: true,
        advancedFilterButtonLabel: l10n.commonFiltersActionLabel,
        advancedFilterTitle: l10n.commonAdvancedFiltersTitle,
        advancedFilterApplyLabel: l10n.opdApplyFiltersAction,
        advancedFilterResetLabel: l10n.opdClearFiltersAction,
        advancedFilterCloseLabel: l10n.commonCloseActionLabel,
        allFieldsLabel: l10n.opdAllFieldsFilterLabel,
        textFilters: <AppSearchBarTextFilter>[
          AppSearchBarTextFilter(
            key: _drugNameFilterKey,
            label: l10n.pharmacyDrugGenericNameLabel,
            hintText: l10n.pharmacyDrugGenericNameLabel,
            icon: Icons.medication_outlined,
          ),
          AppSearchBarTextFilter(
            key: _drugCodeFilterKey,
            label: l10n.pharmacyDrugCodeLabel,
            icon: Icons.qr_code_2_outlined,
          ),
          AppSearchBarTextFilter(
            key: _drugFormFilterKey,
            label: l10n.pharmacyDrugFormLabel,
            icon: Icons.science_outlined,
          ),
          AppSearchBarTextFilter(
            key: _drugStrengthFilterKey,
            label: l10n.pharmacyDrugStrengthLabel,
            icon: Icons.straighten_outlined,
          ),
        ],
        filterGroups: _formularyCatalogFilterGroups(l10n),
        filterValue: _formularyCatalogFilterValue(formularyQuery),
        hasActiveFilters: _hasFormularyCatalogFilters(formularyQuery),
        onFilterChanged: (AppSearchBarFilterValue value) {
          unawaited(_applyFormularyCatalogFilter(controller, value));
        },
        trailingActions: _catalogSearchTrailingActions(
          ref: ref,
          writeRequirement: widget.writeRequirement,
          isBusy: isBusy,
          hasSelection: hasSelection,
          addLabel: l10n.commonAddActionLabel,
          addSemanticLabel: l10n.pharmacyAddFormularyAction,
          onAdd: () => _openFormularyDialog(context),
          selectionLabel: l10n.pharmacyDeleteSelectedFormularyAction,
          onSelectionAction: () => _confirmDeleteSelectedFormulary(context),
        ),
      ),
      emptyBuilder: (_) => AppWorkspaceStatePanel.state(
        variant: AppStateViewVariant.empty,
        title: l10n.pharmacyNoFormularyTitle,
        body: l10n.pharmacyNoFormularyBody,
        icon: Icons.list_alt_outlined,
      ),
      columns: <AppListTableColumn<PharmacyFormularyItem>>[
        _selectionColumn<PharmacyFormularyItem>(
          visibleItems: widget.state.formularyItems.items,
          selectedKeys: _selectedFormularyIds,
          selectionTick: _selectionTick,
          isBusy: isBusy,
          itemKey: (PharmacyFormularyItem item) => item.id,
          onToggle: (PharmacyFormularyItem item, bool selected) {
            _mutateFormularySelection(() {
              if (selected) {
                _selectedFormularyIds.add(item.id);
              } else {
                _selectedFormularyIds.remove(item.id);
              }
            });
          },
          onToggleAll: (List<PharmacyFormularyItem> items, bool selected) {
            _mutateFormularySelection(() {
              if (!selected) {
                for (final PharmacyFormularyItem item in items) {
                  _selectedFormularyIds.remove(item.id);
                }
                return;
              }
              for (final PharmacyFormularyItem item in items) {
                _selectedFormularyIds.add(item.id);
              }
            });
          },
        ),
        AppListTableColumn<PharmacyFormularyItem>(
          id: 'drug_name',
          label: l10n.pharmacyDrugGenericNameLabel,
          preferredWidth: 220,
          alwaysVisible: true,
          cellBuilder: (_, PharmacyFormularyItem item) =>
              Text(item.drugNameLabel ?? '—'),
          exportValue: (PharmacyFormularyItem item) => item.drugNameLabel ?? '',
        ),
        AppListTableColumn<PharmacyFormularyItem>(
          id: 'drug_code',
          label: l10n.pharmacyDrugCodeLabel,
          preferredWidth: 120,
          alwaysVisible: true,
          cellBuilder: (_, PharmacyFormularyItem item) =>
              Text((item.drugCode ?? '').trim().isEmpty ? '—' : item.drugCode!),
          exportValue: (PharmacyFormularyItem item) => item.drugCode ?? '',
        ),
        AppListTableColumn<PharmacyFormularyItem>(
          id: 'is_active',
          label: l10n.pharmacyFormularyActiveLabel,
          alwaysVisible: true,
          cellBuilder: (BuildContext context, PharmacyFormularyItem item) {
            return AppWorkspaceStatusBadge(
              status: AppWorkspaceStatus(
                label: item.isActive ? l10n.commonYesLabel : l10n.commonNoLabel,
                tone: item.isActive
                    ? AppWorkspaceStatusTone.success
                    : AppWorkspaceStatusTone.neutral,
              ),
            );
          },
          exportValue: (PharmacyFormularyItem item) =>
              item.isActive ? l10n.commonYesLabel : l10n.commonNoLabel,
        ),
        AppListTableColumn<PharmacyFormularyItem>(
          id: 'actions',
          label: l10n.pharmacyLineActionsColumnLabel,
          alwaysVisible: true,
          fixedWidth: 240,
          cellBuilder: (BuildContext context, PharmacyFormularyItem item) {
            return _catalogRowActions(
              context: context,
              writeRequirement: widget.writeRequirement,
              isBusy: isBusy,
              editLabel: l10n.commonEditActionLabel,
              deleteLabel: l10n.commonRemoveActionLabel,
              editSemanticLabel: l10n.pharmacyEditFormularyAction,
              deleteSemanticLabel: l10n.pharmacyDeleteFormularyAction,
              onEdit: () => _openFormularyDialog(context, item: item),
              onDelete: () => _confirmDeleteFormulary(context, item),
              alignStart: true,
            );
          },
        ),
      ],
      columnChoices: <AppListTableColumn<PharmacyFormularyItem>>[
        AppListTableColumn<PharmacyFormularyItem>(
          id: 'drug_form',
          label: l10n.pharmacyDrugFormLabel,
          preferredWidth: 120,
          cellBuilder: (_, PharmacyFormularyItem item) => Text(
            (item.drugForm ?? '').trim().isEmpty ? '—' : item.drugForm!.trim(),
          ),
          exportValue: (PharmacyFormularyItem item) => item.drugForm ?? '',
        ),
        AppListTableColumn<PharmacyFormularyItem>(
          id: 'drug_strength',
          label: l10n.pharmacyDrugStrengthLabel,
          preferredWidth: 120,
          cellBuilder: (_, PharmacyFormularyItem item) => Text(
            (item.drugStrength ?? '').trim().isEmpty
                ? '—'
                : item.drugStrength!.trim(),
          ),
          exportValue: (PharmacyFormularyItem item) => item.drugStrength ?? '',
        ),
        AppListTableColumn<PharmacyFormularyItem>(
          id: 'formulary_id',
          label: l10n.pharmacyFormularyIdLabel,
          cellBuilder: (_, PharmacyFormularyItem item) =>
              Text(item.displayId ?? item.id),
          exportValue: (PharmacyFormularyItem item) =>
              item.displayId ?? item.id,
        ),
        AppListTableColumn<PharmacyFormularyItem>(
          id: 'created_at',
          label: l10n.pharmacyStorageCreatedAtColumnLabel,
          preferredWidth: 160,
          cellBuilder: (BuildContext context, PharmacyFormularyItem item) {
            if (item.createdAt == null) {
              return const Text('—');
            }
            return Text(
              AppFormatters.dateTime(
                item.createdAt!,
                Localizations.localeOf(context),
              ),
            );
          },
          exportValue: (PharmacyFormularyItem item) => item.createdAt,
        ),
        AppListTableColumn<PharmacyFormularyItem>(
          id: 'updated_at',
          label: l10n.tenantFacilityUpdatedAtLabel,
          preferredWidth: 160,
          cellBuilder: (BuildContext context, PharmacyFormularyItem item) {
            if (item.updatedAt == null) {
              return const Text('—');
            }
            return Text(
              AppFormatters.dateTime(
                item.updatedAt!,
                Localizations.localeOf(context),
              ),
            );
          },
          exportValue: (PharmacyFormularyItem item) => item.updatedAt,
        ),
      ],
            mobileItemBuilder: (BuildContext context, PharmacyFormularyItem item) {
        return AppListTableMobileItem(
          leading: Checkbox(
            value: _selectedFormularyIds.contains(item.id),
            onChanged: isBusy
                ? null
                : (bool? value) {
                    _mutateFormularySelection(() {
                      if (value ?? false) {
                        _selectedFormularyIds.add(item.id);
                      } else {
                        _selectedFormularyIds.remove(item.id);
                      }
                    });
                  },
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          title: item.drugNameLabel ?? item.displayId ?? item.id,
          caption: item.drugCode,
          showAvatar: false,
        );
      },
    );

    return table;
  }

  Future<void> _openFormularyDialog(
    BuildContext context, {
    PharmacyFormularyItem? item,
  }) {
    return showAppDialog<bool>(
      context: context,
      builder: (_) => _FormularyItemDialog(item: item),
    );
  }

  Future<void> _confirmDeleteFormulary(
    BuildContext context,
    PharmacyFormularyItem item,
  ) async {
    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (_) => AppConfirmActionDialog(
        title: l10n.pharmacyDeleteFormularyDialogTitle,
        body: l10n.pharmacyDeleteFormularyDialogBody,
        highlightedText: item.displayTitle,
        submitLabel: l10n.pharmacyDeleteFormularyAction,
        destructive: true,
        icon: const Icon(AppActionIcons.delete),
        submitLeadingIcon: AppActionIcons.delete,
        onConfirm: () => ref
            .read(pharmacyWorkspaceControllerProvider.notifier)
            .deleteFormularyItem(item.id),
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    setState(() => _selectedFormularyIds.remove(item.id));
  }

  Future<void> _confirmDeleteSelectedFormulary(BuildContext context) async {
    final AppLocalizations l10n = context.l10n;
    final int count = _selectedFormularyIds.length;
    if (count == 0) {
      return;
    }
    final List<String> ids = _selectedFormularyIds.toList(growable: false);
    final PharmacyWorkspaceController controller = ref.read(
      pharmacyWorkspaceControllerProvider.notifier,
    );
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (_) => AppConfirmActionDialog(
        title: l10n.pharmacyDeleteSelectedFormularyDialogTitle,
        body: l10n.pharmacyDeleteSelectedFormularyDialogBody(count),
        submitLabel: l10n.pharmacyDeleteFormularyAction,
        destructive: true,
        icon: const Icon(AppActionIcons.delete),
        submitLeadingIcon: AppActionIcons.delete,
        onConfirm: () async {
          for (final String formularyItemId in ids) {
            final AppFailure? failure = await controller.deleteFormularyItem(
              formularyItemId,
            );
            if (failure != null) {
              return failure;
            }
          }
          return null;
        },
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    setState(_selectedFormularyIds.clear);
  }
}

class _FormularyItemDialog extends ConsumerStatefulWidget {
  const _FormularyItemDialog({this.item});

  final PharmacyFormularyItem? item;

  @override
  ConsumerState<_FormularyItemDialog> createState() =>
      _FormularyItemDialogState();
}

class _FormularyItemDialogState extends ConsumerState<_FormularyItemDialog> {
  final Set<String> _selectedDrugIds = <String>{};
  late bool _isActive;
  bool _isSaving = false;
  late final TextEditingController _drugSearchController;
  AppPage<PharmacyDrug> _pickerDrugs = const AppPage<PharmacyDrug>(
    items: <PharmacyDrug>[],
    request: AppPageRequest(pageSize: AppPageRequest.maxPageSize),
  );
  bool _isLoadingPickerDrugs = false;

  bool get _isEditing => widget.item != null;

  @override
  void initState() {
    super.initState();
    _isActive = widget.item?.isActive ?? true;
    _drugSearchController = TextEditingController();
    if (!_isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(_loadPickerDrugs());
      });
    }
  }

  Future<void> _loadPickerDrugs({String search = ''}) async {
    setState(() => _isLoadingPickerDrugs = true);
    final Result<AppPage<PharmacyDrug>> result = await ref
        .read(pharmacyWorkspaceControllerProvider.notifier)
        .loadDrugPickerPage(search: search);
    if (!mounted) {
      return;
    }
    result.when(
      success: (AppPage<PharmacyDrug> page) {
        setState(() {
          _pickerDrugs = page;
          _isLoadingPickerDrugs = false;
        });
      },
      failure: (_) {
        setState(() => _isLoadingPickerDrugs = false);
      },
    );
  }

  @override
  void dispose() {
    _drugSearchController.dispose();
    super.dispose();
  }

  void _toggleDrug(String drugId, bool selected) {
    setState(() {
      if (selected) {
        _selectedDrugIds.add(drugId);
      } else {
        _selectedDrugIds.remove(drugId);
      }
    });
  }

  void _toggleAllVisible(List<PharmacyDrug> drugs, bool selected) {
    setState(() {
      if (!selected) {
        for (final PharmacyDrug drug in drugs) {
          _selectedDrugIds.remove(drug.id);
        }
        return;
      }
      for (final PharmacyDrug drug in drugs) {
        _selectedDrugIds.add(drug.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppPage<PharmacyDrug> drugsPage = _pickerDrugs;
    final bool isLoadingDrugs = _isLoadingPickerDrugs;
    final List<PharmacyDrug> visibleDrugs = drugsPage.items;
    final bool allVisibleSelected =
        visibleDrugs.isNotEmpty &&
        visibleDrugs.every(
          (PharmacyDrug drug) => _selectedDrugIds.contains(drug.id),
        );
    final bool someVisibleSelected = visibleDrugs.any(
      (PharmacyDrug drug) => _selectedDrugIds.contains(drug.id),
    );

    return AppDialog(
      title: Text(
        _isEditing
            ? l10n.pharmacyEditFormularyAction
            : l10n.pharmacyAddFormularyDialogTitle,
      ),
      scrollable: true,
      pinActionsToBottom: true,
      maxWidth: 880,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_isEditing)
            AppTextField(
              readOnly: true,
              initialValue: widget.item?.displayTitle,
              labelText: l10n.pharmacyFormularyDrugLabel,
            )
          else
            AppListTable<PharmacyDrug>(
              page: drugsPage,
              isLoading: isLoadingDrugs,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              tableHorizontalMargin: 0,
              enableExport: false,
              onPageChanged: (_) {},
              onRowSelected: _isSaving
                  ? null
                  : (PharmacyDrug drug) {
                      _toggleDrug(
                        drug.id,
                        !_selectedDrugIds.contains(drug.id),
                      );
                    },
              search: AppListTableSearch<PharmacyDrug>(
                controller: _drugSearchController,
                semanticLabel: l10n.pharmacyDrugSearchLabel,
                hintText: l10n.pharmacyDrugSearchHint,
                matcher: (_, _) => true,
                enableDateFilter: false,
                onSubmitted: (String value) {
                  unawaited(_loadPickerDrugs(search: value));
                },
                onClear: () => unawaited(_loadPickerDrugs()),
              ),
              columns: <AppListTableColumn<PharmacyDrug>>[
                AppListTableColumn<PharmacyDrug>(
                  id: 'select',
                  label: '',
                  fixedWidth: 40,
                  alwaysVisible: true,
                  exportable: false,
                  headerBuilder: (BuildContext context) {
                    final AppLocalizations headerL10n = context.l10n;
                    final String tooltip = allVisibleSelected
                        ? headerL10n.commonDeselectAllActionLabel
                        : headerL10n.commonSelectAllActionLabel;
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Tooltip(
                        message: tooltip,
                        child: Semantics(
                          label: tooltip,
                          checked: allVisibleSelected,
                          mixed: someVisibleSelected && !allVisibleSelected,
                          child: Checkbox(
                            tristate: true,
                            value: allVisibleSelected
                                ? true
                                : someVisibleSelected
                                ? null
                                : false,
                            onChanged: _isSaving || visibleDrugs.isEmpty
                                ? null
                                : (bool? checked) => _toggleAllVisible(
                                    visibleDrugs,
                                    checked ?? false,
                                  ),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    );
                  },
                  cellBuilder: (BuildContext context, PharmacyDrug drug) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Checkbox(
                        value: _selectedDrugIds.contains(drug.id),
                        onChanged: _isSaving
                            ? null
                            : (bool? value) =>
                                _toggleDrug(drug.id, value ?? false),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    );
                  },
                ),
                AppListTableColumn<PharmacyDrug>(
                  id: 'generic_name',
                  label: l10n.pharmacyDrugGenericNameLabel,
                  preferredWidth: 260,
                  cellBuilder: (_, PharmacyDrug drug) {
                    final String generic = (drug.genericName ?? '').trim();
                    if (generic.isNotEmpty) {
                      return Text(generic);
                    }
                    final String legacy = (drug.name ?? '').trim();
                    return Text(legacy.isEmpty ? drug.displayTitle : legacy);
                  },
                ),
                AppListTableColumn<PharmacyDrug>(
                  id: 'code',
                  label: l10n.pharmacyDrugCodeLabel,
                  preferredWidth: 120,
                  cellBuilder: (_, PharmacyDrug drug) =>
                      Text((drug.code ?? '').trim().isEmpty ? '—' : drug.code!),
                ),
                AppListTableColumn<PharmacyDrug>(
                  id: 'form',
                  label: l10n.pharmacyDrugFormLabel,
                  preferredWidth: 120,
                  cellBuilder: (_, PharmacyDrug drug) => Text(
                    (drug.form ?? '').trim().isEmpty
                        ? '—'
                        : drug.form!.trim(),
                  ),
                ),
                AppListTableColumn<PharmacyDrug>(
                  id: 'strength',
                  label: l10n.pharmacyDrugStrengthLabel,
                  preferredWidth: 120,
                  cellBuilder: (_, PharmacyDrug drug) => Text(
                    (drug.strength ?? '').trim().isEmpty
                        ? '—'
                        : drug.strength!.trim(),
                  ),
                ),
              ],
              mobileItemBuilder: (BuildContext context, PharmacyDrug drug) {
                final bool selected = _selectedDrugIds.contains(drug.id);
                return AppListTableMobileItem(
                  leading: Checkbox(
                    value: selected,
                    onChanged: _isSaving
                        ? null
                        : (bool? value) =>
                              _toggleDrug(drug.id, value ?? false),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  title: drug.displayTitle,
                  caption: drug.code,
                  showAvatar: false,
                );
              },
              emptyBuilder: (_) => AppWorkspaceStatePanel.state(
                variant: AppStateViewVariant.empty,
                title: l10n.pharmacyNoDrugsTitle,
                body: l10n.pharmacyNoDrugsBody,
                icon: Icons.medication_outlined,
              ),
            ),
          AppSwitchField(
            title: l10n.pharmacyFormularyActiveLabel,
            value: _isActive,
            onChanged: _isSaving
                ? null
                : (bool value) => setState(() => _isActive = value),
          ),
        ],
      ),
      actions: <Widget>[
        AppButton.close(
          label: l10n.commonCancelActionLabel,
          leadingIcon: Icons.close,
          enabled: !_isSaving,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton.primary(
          label: _isEditing
              ? l10n.pharmacyEditFormularyAction
              : l10n.pharmacyAddSelectedFormularyItemsAction,
          leadingIcon: _isEditing ? Icons.save_outlined : Icons.add,
          isLoading: _isSaving,
          enabled: _isEditing || _selectedDrugIds.isNotEmpty,
          onPressed: _submit,
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final PharmacyWorkspaceController controller = ref.read(
      pharmacyWorkspaceControllerProvider.notifier,
    );
    setState(() => _isSaving = true);
    final AppFailure? failure;
    if (_isEditing) {
      failure = await controller.updateFormularyItem(
        widget.item!.id,
        isActive: _isActive,
      );
    } else {
      final String? tenantId = controller.resolveTenantId();
      final List<String> drugIds = _selectedDrugIds.toList(growable: false);
      if (tenantId == null || drugIds.isEmpty) {
        setState(() => _isSaving = false);
        return;
      }
      AppFailure? createFailure;
      for (final String drugId in drugIds) {
        createFailure = await controller.createFormularyItem(
          PharmacyFormularyItemInput(
            tenantId: tenantId,
            drugId: drugId,
            isActive: _isActive,
          ),
        );
        if (createFailure != null) {
          break;
        }
      }
      failure = createFailure;
    }
    if (!mounted) {
      return;
    }
    if (failure == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _isSaving = false);
  }
}

class _InventoryCatalogTab extends ConsumerStatefulWidget {
  const _InventoryCatalogTab({
    required this.state,
    required this.writeRequirement,
    this.fillHeight = false,
  });

  final PharmacyWorkspaceState state;
  final AccessRequirement writeRequirement;
  final bool fillHeight;

  @override
  ConsumerState<_InventoryCatalogTab> createState() =>
      _InventoryCatalogTabState();
}

class _InventoryCatalogTabState extends ConsumerState<_InventoryCatalogTab> {
  late final TextEditingController _searchController;
  final Set<String> _selectedInventoryIds = <String>{};
  final ValueNotifier<int> _selectionTick = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: widget.state.inventoryQuery.search,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (widget.state.inventoryWorkbench.stocks.items.isEmpty) {
        unawaited(
          ref
              .read(pharmacyWorkspaceControllerProvider.notifier)
              .applyInventorySearch(''),
        );
      }
    });
  }

  @override
  void dispose() {
    _selectionTick.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _mutateInventorySelection(void Function() mutate) {
    mutate();
    _selectionTick.value++;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final PharmacyWorkspaceController controller = ref.read(
      pharmacyWorkspaceControllerProvider.notifier,
    );
    final bool isBusy = widget.state.isRefreshingInventory;

    final PharmacyInventoryStockQuery inventoryQuery =
        widget.state.inventoryQuery;
    final bool hasSelection = _selectedInventoryIds.isNotEmpty;
    final AppAccessPolicy policy = ref.watch(appAccessPolicyProvider);
    final bool canExport = canExportPharmacyWorkspace(policy);
    final bool canPrint = canPrintPharmacyWorkspace(policy);

    return AppListTable<PharmacyInventoryStock>(
      page: widget.state.inventoryWorkbench.stocks,
      isLoading: isBusy,
      itemKeyBuilder: (PharmacyInventoryStock item) =>
          ValueKey<String>(_inventorySelectionKey(item)),
      rowsVersion: _selectionTick.value,
      columnVisibilityStorageKey: 'pharmacy_catalog_inventory',
      columnVisibilityLabel: l10n.commonTableSettingsActionLabel,
      columnVisibilityTitle: l10n.commonTableSettingsTitle,
      columnVisibilityApplyLabel: l10n.receptionApplyColumnsAction,
      columnVisibilityResetLabel: l10n.receptionResetColumnsAction,
      columnVisibilityCloseLabel: l10n.commonCloseActionLabel,
      shrinkWrap: !widget.fillHeight,
      enableExport: true,
      canExport: canExport,
      exportLabel: l10n.commonTableExportActionLabel,
      exportDialogTitle: l10n.commonTableExportDialogTitle,
      exportCancelLabel: l10n.commonCancelActionLabel,
      exportColumnsSectionLabel: l10n.commonTableExportColumnsSectionLabel,
      exportFiltersSectionLabel: l10n.commonTableExportFiltersSectionLabel,
      exportEmptyColumnsMessage: l10n.commonTableExportEmptyColumnsMessage,
      exportEmptyRowsMessage: l10n.commonTableExportEmptyRowsMessage,
      exportSuccessMessage: l10n.commonTableExportSuccessMessage,
      exportFailureMessage: l10n.commonTableExportFailureMessage,
      enablePrint: true,
      canPrint: canPrint,
      printLabel: l10n.commonPrintActionLabel,
      onPrint: (List<PharmacyInventoryStock> items) =>
          _printPharmacyInventoryList(
        context,
        ref,
        l10n: l10n,
        stocks: items,
      ),
      goToTopLabel: l10n.commonGoToTopActionLabel,
      loadingMoreLabel: l10n.commonLoadingMoreLabel,
      allRowsLoadedLabel: l10n.commonAllRowsLoadedLabel,
      exportConfig: AppListTableExportConfig<PharmacyInventoryStock>(
        fileNameStem: 'pharmacy_inventory',
        dateOf: (PharmacyInventoryStock item) => item.nextExpiry ?? item.createdAt,
        dateFromLabel: l10n.commonTableExportDateFromLabel,
        dateToLabel: l10n.commonTableExportDateToLabel,
        rowFilter: (PharmacyInventoryStock item, AppSearchBarFilterValue filters) {
          return _matchesInventoryExportFilters(item, filters);
        },
      ),
      search: AppListTableSearch<PharmacyInventoryStock>(
        controller: _searchController,
        semanticLabel: l10n.pharmacyInventoryFiltersSemanticLabel,
        hintText: l10n.pharmacyInventorySearchHint,
        matcher: (_, _) => true,
        onSubmitted: controller.applyInventorySearch,
        onClear: () => unawaited(controller.applyInventorySearch('')),
        showAdvancedFilterButton: true,
        advancedFilterButtonLabel: l10n.commonFiltersActionLabel,
        advancedFilterTitle: l10n.commonAdvancedFiltersTitle,
        advancedFilterApplyLabel: l10n.opdApplyFiltersAction,
        advancedFilterResetLabel: l10n.opdClearFiltersAction,
        advancedFilterCloseLabel: l10n.commonCloseActionLabel,
        allFieldsLabel: l10n.opdAllFieldsFilterLabel,
        textFilters: <AppSearchBarTextFilter>[
          AppSearchBarTextFilter(
            key: _inventoryItemNameFilterKey,
            label: l10n.pharmacyInventoryItemLabel,
            hintText: l10n.pharmacyInventoryItemLabel,
            icon: Icons.inventory_2_outlined,
          ),
          AppSearchBarTextFilter(
            key: _inventorySkuFilterKey,
            label: l10n.pharmacyInventorySkuColumnLabel,
            icon: Icons.qr_code_2_outlined,
          ),
          AppSearchBarTextFilter(
            key: _inventoryFacilityFilterKey,
            label: l10n.pharmacyInventoryFacilityColumnLabel,
            icon: Icons.apartment_outlined,
          ),
        ],
        filterGroups: _inventoryCatalogFilterGroups(
          l10n: l10n,
          layout: widget.state.storageLayout,
          storageRoomId: inventoryQuery.storageRoomId,
        ),
        filterValue: _inventoryCatalogFilterValue(inventoryQuery),
        hasActiveFilters: _hasInventoryCatalogFilters(inventoryQuery),
        onFilterChanged: (AppSearchBarFilterValue value) {
          unawaited(_applyInventoryCatalogFilter(controller, value));
        },
        trailingActions: _catalogSearchTrailingActions(
          ref: ref,
          writeRequirement: widget.writeRequirement,
          isBusy: isBusy,
          hasSelection: hasSelection,
          selectionLabel: l10n.pharmacyClearSelectedInventoryAction,
          onSelectionAction: () => _confirmClearSelectedInventory(context),
        ),
      ),
      onPageChanged: controller.changeInventoryPage,
      emptyBuilder: (_) => AppWorkspaceStatePanel.state(
        variant: AppStateViewVariant.empty,
        title: l10n.pharmacyNoInventoryTitle,
        body: l10n.pharmacyNoInventoryBody,
        icon: Icons.warehouse_outlined,
      ),
      columns: <AppListTableColumn<PharmacyInventoryStock>>[
        _selectionColumn<PharmacyInventoryStock>(
          visibleItems: widget.state.inventoryWorkbench.stocks.items,
          selectedKeys: _selectedInventoryIds,
          selectionTick: _selectionTick,
          isBusy: isBusy,
          itemKey: (PharmacyInventoryStock item) =>
              _inventorySelectionKey(item),
          onToggle: (PharmacyInventoryStock item, bool selected) {
            _mutateInventorySelection(() {
              final String key = _inventorySelectionKey(item);
              if (selected) {
                _selectedInventoryIds.add(key);
              } else {
                _selectedInventoryIds.remove(key);
              }
            });
          },
          onToggleAll: (List<PharmacyInventoryStock> items, bool selected) {
            _mutateInventorySelection(() {
              if (!selected) {
                for (final PharmacyInventoryStock item in items) {
                  _selectedInventoryIds.remove(_inventorySelectionKey(item));
                }
                return;
              }
              for (final PharmacyInventoryStock item in items) {
                _selectedInventoryIds.add(_inventorySelectionKey(item));
              }
            });
          },
        ),
        AppListTableColumn<PharmacyInventoryStock>(
          id: 'item',
          label: l10n.pharmacyInventoryItemLabel,
          preferredWidth: 260,
          alwaysVisible: true,
          cellBuilder: (_, PharmacyInventoryStock item) {
            return Text(
              item.inventoryItem?.displayTitle ?? item.displayId ?? '',
            );
          },
          exportValue: (PharmacyInventoryStock item) =>
              item.inventoryItem?.displayTitle ?? item.displayId ?? '',
        ),
        AppListTableColumn<PharmacyInventoryStock>(
          id: 'quantity',
          label: l10n.pharmacyInventoryQuantityColumnLabel,
          numeric: true,
          fixedWidth: 72,
          alwaysVisible: true,
          cellBuilder: (_, PharmacyInventoryStock item) =>
              Text(item.quantity.toString()),
          exportValue: (PharmacyInventoryStock item) => item.quantity,
        ),
        AppListTableColumn<PharmacyInventoryStock>(
          id: 'stock_status',
          label: l10n.pharmacyStockStatusFilterLabel,
          preferredWidth: 130,
          alwaysVisible: true,
          cellBuilder: (BuildContext context, PharmacyInventoryStock item) {
            return AppWorkspaceStatusBadge(
              status: _stockStatus(context, item.stockStatus),
            );
          },
          exportValue: (PharmacyInventoryStock item) =>
              _stockStatus(context, item.stockStatus).label,
        ),
        AppListTableColumn<PharmacyInventoryStock>(
          id: 'actions',
          label: l10n.pharmacyLineActionsColumnLabel,
          alwaysVisible: true,
          fixedWidth: 260,
          cellBuilder: (BuildContext context, PharmacyInventoryStock item) {
            return _catalogRowActions(
              context: context,
              writeRequirement: widget.writeRequirement,
              isBusy: isBusy,
              alignStart: true,
              editLabel: l10n.commonAdjustActionLabel,
              deleteLabel: l10n.commonClearActionLabel,
              editSemanticLabel: l10n.pharmacyAdjustStockAction,
              deleteSemanticLabel: l10n.pharmacyDeleteInventoryStockAction,
              editIcon: Icons.tune,
              onEdit: () => _openAdjustDialog(context, item),
              onDelete: () => _confirmClearInventoryStock(context, item),
            );
          },
        ),
      ],
      columnChoices: <AppListTableColumn<PharmacyInventoryStock>>[
        AppListTableColumn<PharmacyInventoryStock>(
          id: 'reorder_level',
          label: l10n.pharmacyReorderLevelColumnLabel,
          numeric: true,
          fixedWidth: 84,
          cellBuilder: (_, PharmacyInventoryStock item) =>
              Text(item.reorderLevel.toString()),
          exportValue: (PharmacyInventoryStock item) => item.reorderLevel,
        ),
        AppListTableColumn<PharmacyInventoryStock>(
          id: 'storage_location',
          label: l10n.pharmacyStorageLocationColumnLabel,
          preferredWidth: 200,
          cellBuilder: (_, PharmacyInventoryStock item) =>
              Text(item.storageLocationLabel ?? '—'),
          exportValue: (PharmacyInventoryStock item) =>
              item.storageLocationLabel ?? '',
        ),
        AppListTableColumn<PharmacyInventoryStock>(
          id: 'next_expiry',
          label: l10n.pharmacyNextExpiryColumnLabel,
          preferredWidth: 170,
          cellBuilder: (BuildContext context, PharmacyInventoryStock item) {
            return _expiryCell(context, item);
          },
          exportValue: (PharmacyInventoryStock item) => item.nextExpiry,
        ),
        AppListTableColumn<PharmacyInventoryStock>(
          id: 'batch_count',
          label: l10n.pharmacyBatchCountColumnLabel,
          numeric: true,
          fixedWidth: 88,
          cellBuilder: (_, PharmacyInventoryStock item) =>
              Text(item.batchCount.toString()),
          exportValue: (PharmacyInventoryStock item) => item.batchCount,
        ),

        AppListTableColumn<PharmacyInventoryStock>(
          id: 'sku',
          label: l10n.pharmacyInventorySkuColumnLabel,
          preferredWidth: 120,
          cellBuilder: (_, PharmacyInventoryStock item) => Text(
            (item.inventoryItem?.sku ?? '').trim().isEmpty
                ? '—'
                : item.inventoryItem!.sku!.trim(),
          ),
          exportValue: (PharmacyInventoryStock item) =>
              item.inventoryItem?.sku ?? '',
        ),
        AppListTableColumn<PharmacyInventoryStock>(
          id: 'unit',
          label: l10n.pharmacyInventoryUnitLabel,
          preferredWidth: 110,
          cellBuilder: (_, PharmacyInventoryStock item) => Text(
            (item.inventoryItem?.unit ?? '').trim().isEmpty
                ? '—'
                : item.inventoryItem!.unit!.trim(),
          ),
          exportValue: (PharmacyInventoryStock item) =>
              item.inventoryItem?.unit ?? '',
        ),
        AppListTableColumn<PharmacyInventoryStock>(
          id: 'facility',
          label: l10n.pharmacyInventoryFacilityColumnLabel,
          preferredWidth: 160,
          cellBuilder: (_, PharmacyInventoryStock item) =>
              Text((item.facilityName ?? '').trim().isEmpty
                  ? '—'
                  : item.facilityName!.trim()),
          exportValue: (PharmacyInventoryStock item) => item.facilityName ?? '',
        ),
        AppListTableColumn<PharmacyInventoryStock>(
          id: 'storage_room',
          label: l10n.pharmacyStorageRoomLabel,
          preferredWidth: 140,
          cellBuilder: (_, PharmacyInventoryStock item) =>
              Text((item.storageRoomLabel ?? '').trim().isEmpty
                  ? '—'
                  : item.storageRoomLabel!.trim()),
          exportValue: (PharmacyInventoryStock item) =>
              item.storageRoomLabel ?? '',
        ),
        AppListTableColumn<PharmacyInventoryStock>(
          id: 'storage_shelf',
          label: l10n.pharmacyStorageShelfLabel,
          preferredWidth: 120,
          cellBuilder: (_, PharmacyInventoryStock item) =>
              Text((item.storageShelfCode ?? '').trim().isEmpty
                  ? '—'
                  : item.storageShelfCode!.trim()),
          exportValue: (PharmacyInventoryStock item) =>
              item.storageShelfCode ?? '',
        ),
        AppListTableColumn<PharmacyInventoryStock>(
          id: 'pending_stock',
          label: l10n.pharmacyInventoryPendingStockColumnLabel,
          fixedWidth: 120,
          cellBuilder: (_, PharmacyInventoryStock item) => Text(
            item.pendingStock ? l10n.commonYesLabel : l10n.commonNoLabel,
          ),
          exportValue: (PharmacyInventoryStock item) =>
              item.pendingStock ? l10n.commonYesLabel : l10n.commonNoLabel,
        ),
        AppListTableColumn<PharmacyInventoryStock>(
          id: 'stock_id',
          label: l10n.pharmacyInventoryStockIdColumnLabel,
          preferredWidth: 140,
          cellBuilder: (_, PharmacyInventoryStock item) =>
              Text(item.displayId ?? item.id),
          exportValue: (PharmacyInventoryStock item) =>
              item.displayId ?? item.id,
        ),
        AppListTableColumn<PharmacyInventoryStock>(
          id: 'created_at',
          label: l10n.pharmacyStorageCreatedAtColumnLabel,
          preferredWidth: 160,
          cellBuilder: (BuildContext context, PharmacyInventoryStock item) {
            if (item.createdAt == null) {
              return const Text('—');
            }
            return Text(
              AppFormatters.dateTime(
                item.createdAt!,
                Localizations.localeOf(context),
              ),
            );
          },
          exportValue: (PharmacyInventoryStock item) => item.createdAt,
        ),
        AppListTableColumn<PharmacyInventoryStock>(
          id: 'updated_at',
          label: l10n.tenantFacilityUpdatedAtLabel,
          preferredWidth: 160,
          cellBuilder: (BuildContext context, PharmacyInventoryStock item) {
            if (item.updatedAt == null) {
              return const Text('—');
            }
            return Text(
              AppFormatters.dateTime(
                item.updatedAt!,
                Localizations.localeOf(context),
              ),
            );
          },
          exportValue: (PharmacyInventoryStock item) => item.updatedAt,
        ),
      ],
      mobileItemBuilder: (BuildContext context, PharmacyInventoryStock item) {
        final String selectionKey = _inventorySelectionKey(item);
        final String? expiryLabel = item.nextExpiry == null
            ? null
            : () {
                final String formatted = AppFormatters.dateTime(
                  item.nextExpiry!,
                  Localizations.localeOf(context),
                );
                if (item.expiryAlertStatus == 'EXPIRED') {
                  return '$formatted · ${l10n.pharmacyStockExpiredLabel}';
                }
                if (item.expiryAlertStatus == 'EXPIRING_SOON') {
                  return '$formatted · ${l10n.pharmacyStockExpiringSoonLabel}';
                }
                return formatted;
              }();
        return AppListTableMobileItem(
          leading: Checkbox(
            value: _selectedInventoryIds.contains(selectionKey),
            onChanged: isBusy
                ? null
                : (bool? value) {
                    _mutateInventorySelection(() {
                      if (value ?? false) {
                        _selectedInventoryIds.add(selectionKey);
                      } else {
                        _selectedInventoryIds.remove(selectionKey);
                      }
                    });
                  },
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          title: item.inventoryItem?.displayTitle ?? '',
          meta: <AppListTableMobileMeta>[
            AppListTableMobileMeta(
              label: '${item.quantity} · ${l10n.pharmacyReorderLevelColumnLabel}: ${item.reorderLevel}',
            ),
            if (expiryLabel != null)
              AppListTableMobileMeta(
                label: expiryLabel,
                icon: AppActionIcons.calendar,
              ),
          ],
          showAvatar: false,
        );
      },
    );
  }

  String _inventorySelectionKey(PharmacyInventoryStock item) {
    return item.id;
  }

  Future<void> _confirmClearInventoryStock(
    BuildContext context,
    PharmacyInventoryStock stock,
  ) async {
    final AppLocalizations l10n = context.l10n;
    final String title =
        stock.inventoryItem?.displayTitle ?? stock.displayId ?? stock.id;
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (_) => AppConfirmActionDialog(
        title: l10n.pharmacyDeleteInventoryStockDialogTitle,
        body: l10n.pharmacyDeleteInventoryStockDialogBody,
        highlightedText: title,
        submitLabel: l10n.pharmacyDeleteInventoryStockAction,
        destructive: true,
        icon: const Icon(AppActionIcons.delete),
        submitLeadingIcon: AppActionIcons.delete,
        leadingContent: <Widget>[_InventoryClearSelectedTile(stock: stock)],
        onConfirm: () => _clearInventoryStockFailure(stock),
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    _mutateInventorySelection(
      () => _selectedInventoryIds.remove(_inventorySelectionKey(stock)),
    );
  }

  Future<void> _confirmClearSelectedInventory(BuildContext context) async {
    final List<PharmacyInventoryStock> selectedStocks = widget
        .state
        .inventoryWorkbench
        .stocks
        .items
        .where(
          (PharmacyInventoryStock item) =>
              _selectedInventoryIds.contains(_inventorySelectionKey(item)),
        )
        .toList(growable: false);
    if (selectedStocks.isEmpty) {
      return;
    }

    final List<PharmacyInventoryStock>? stocksToClear =
        await showAppDialog<List<PharmacyInventoryStock>>(
          context: context,
          builder: (BuildContext dialogContext) =>
              _ClearSelectedInventoryDialog(stocks: selectedStocks),
        );
    if (stocksToClear == null ||
        stocksToClear.isEmpty ||
        !context.mounted) {
      return;
    }
    for (final PharmacyInventoryStock stock in stocksToClear) {
      if (!context.mounted) {
        return;
      }
      await _clearInventoryStock(context, stock, showFailureSnackBar: false);
    }
    if (context.mounted) {
      _mutateInventorySelection(() {
        for (final PharmacyInventoryStock stock in stocksToClear) {
          _selectedInventoryIds.remove(_inventorySelectionKey(stock));
        }
      });
    }
  }

  Future<AppFailure?> _clearInventoryStockFailure(
    PharmacyInventoryStock stock,
  ) async {
    if (stock.quantity <= 0) {
      return null;
    }
    return ref
        .read(pharmacyWorkspaceControllerProvider.notifier)
        .adjustInventoryStock(
          PharmacyInventoryAdjustInput(
            inventoryItemId:
                stock.inventoryItemId ?? stock.inventoryItem?.id ?? stock.id,
            quantityDelta: -stock.quantity.toInt(),
            reason: 'DAMAGE',
            facilityId: stock.facilityId,
          ),
        );
  }

  Future<void> _clearInventoryStock(
    BuildContext context,
    PharmacyInventoryStock stock, {
    bool showFailureSnackBar = true,
  }) async {
    if (stock.quantity <= 0) {
      _mutateInventorySelection(
        () => _selectedInventoryIds.remove(_inventorySelectionKey(stock)),
      );
      return;
    }
    final AppFailure? failure = await _clearInventoryStockFailure(stock);
    if (!context.mounted) {
      return;
    }
    if (failure == null) {
      _mutateInventorySelection(
        () => _selectedInventoryIds.remove(_inventorySelectionKey(stock)),
      );
      return;
    }
    if (showFailureSnackBar) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.pharmacyCatalogDeleteFailedMessage),
        ),
      );
    }
  }

  Future<void> _openAdjustDialog(
    BuildContext context,
    PharmacyInventoryStock stock,
  ) {
    return showAppDialog<bool>(
      context: context,
      builder: (_) => _InventoryAdjustDialog(stock: stock),
    );
  }
}

class _InventoryAdjustDialog extends ConsumerStatefulWidget {
  const _InventoryAdjustDialog({required this.stock});

  final PharmacyInventoryStock stock;

  @override
  ConsumerState<_InventoryAdjustDialog> createState() =>
      _InventoryAdjustDialogState();
}

class _InventoryAdjustDialogState
    extends ConsumerState<_InventoryAdjustDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _deltaController;
  late final TextEditingController _reorderController;
  late final TextEditingController _batchController;
  late final TextEditingController _notesController;
  String _reason = 'PURCHASE';
  DateTime? _expiryDate;
  String? _storageRoomId;
  String? _storageShelfId;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final int onHand = widget.stock.quantity.round();
    _deltaController = TextEditingController(
      text: onHand == 0 ? '' : onHand.toString(),
    );
    _reorderController = TextEditingController(
      text: widget.stock.reorderLevel > 0
          ? widget.stock.reorderLevel.round().toString()
          : '',
    );
    _batchController = TextEditingController();
    _notesController = TextEditingController();
    _expiryDate = widget.stock.nextExpiry;
    _storageRoomId = widget.stock.storageRoomId;
    _storageShelfId = widget.stock.storageShelfId;
  }

  @override
  void dispose() {
    _deltaController.dispose();
    _reorderController.dispose();
    _batchController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final PharmacyStorageLayout storageLayout =
        ref
            .watch(pharmacyWorkspaceControllerProvider)
            .value
            ?.when(
              success: (PharmacyWorkspaceState state) => state.storageLayout,
              failure: (_) => const PharmacyStorageLayout(),
            ) ??
        const PharmacyStorageLayout();
    final List<PharmacyStorageRoom> activeRooms = _activeStorageRooms(
      storageLayout,
    );
    final List<PharmacyStorageShelf> shelfOptions = activeRooms
        .where((PharmacyStorageRoom room) => room.id == _storageRoomId)
        .expand((PharmacyStorageRoom room) => room.shelves)
        .where((PharmacyStorageShelf shelf) => shelf.isActive)
        .toList(growable: false);
    return AppDialog(
      title: Text(l10n.pharmacyAdjustStockDialogTitle),
      scrollable: true,
      content: AppFormShell(
        formKey: _formKey,
        enabled: !_isSaving,
        children: <Widget>[
          AppTextField(
            controller: _deltaController,
            labelText: l10n.pharmacyInventoryQuantityColumnLabel,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'^-?\d*')),
            ],
          ),
          AppTextField(
            controller: _reorderController,
            labelText: l10n.pharmacyReorderLevelLabel,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
          ),
          AppSelectField<String>(
            value: _reason,
            labelText: l10n.pharmacyStockReasonLabel,
            options: const <AppSelectOption<String>>[
              AppSelectOption<String>(value: 'PURCHASE', label: 'PURCHASE'),
              AppSelectOption<String>(value: 'DISPENSE', label: 'DISPENSE'),
              AppSelectOption<String>(value: 'RETURN', label: 'RETURN'),
              AppSelectOption<String>(value: 'DAMAGE', label: 'DAMAGE'),
              AppSelectOption<String>(value: 'EXPIRY', label: 'EXPIRY'),
              AppSelectOption<String>(value: 'OTHER', label: 'OTHER'),
            ],
            onChanged: (String? value) {
              if (value != null) {
                setState(() => _reason = value);
              }
            },
          ),
          if (_reason == 'PURCHASE') ...<Widget>[
            AppTextField(
              controller: _batchController,
              labelText: l10n.pharmacyBatchNumberLabel,
            ),
            AppDateField(
              labelText: l10n.pharmacyExpiryDateLabel,
              value: _expiryDate,
              pickerButtonLabel: l10n.housekeepingPickDateAction,
              invalidDateMessage: l10n.pharmacyExpiryDateLabel,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
              onChanged: (DateTime? value) =>
                  setState(() => _expiryDate = value),
            ),
            if (activeRooms.isNotEmpty)
              AppResponsiveFieldRow.two(
                gap: AppResponsiveFieldRowGap.form,
                left: AppSelectField<String>(
                  value: _storageRoomId,
                  labelText: l10n.pharmacyStorageRoomLabel,
                  enabled: !_isSaving,
                  options: activeRooms
                      .map(
                        (PharmacyStorageRoom room) => AppSelectOption<String>(
                          value: room.id,
                          label: room.name ?? room.id,
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (String? value) {
                    setState(() {
                      _storageRoomId = value;
                      final List<PharmacyStorageShelf> nextShelves = activeRooms
                          .where((PharmacyStorageRoom room) => room.id == value)
                          .expand((PharmacyStorageRoom room) => room.shelves)
                          .where((PharmacyStorageShelf shelf) => shelf.isActive)
                          .toList(growable: false);
                      if (_storageShelfId != null &&
                          !nextShelves.any(
                            (PharmacyStorageShelf shelf) =>
                                shelf.id == _storageShelfId,
                          )) {
                        _storageShelfId = null;
                      }
                    });
                  },
                ),
                right: AppSelectField<String>(
                  value: _storageShelfId,
                  labelText: l10n.pharmacyStorageShelfLabel,
                  enabled: !_isSaving && _storageRoomId != null,
                  options: shelfOptions
                      .map(
                        (PharmacyStorageShelf shelf) => AppSelectOption<String>(
                          value: shelf.id,
                          label: shelf.displayLabel,
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (String? value) =>
                      setState(() => _storageShelfId = value),
                ),
              ),
          ],
          AppTextField(
            controller: _notesController,
            labelText: l10n.pharmacyNotesLabel,
            maxLines: 2,
          ),
        ],
      ),
      actions: <Widget>[
        AppButton.close(
          label: l10n.commonCancelActionLabel,
          leadingIcon: Icons.close,
          enabled: !_isSaving,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton.primary(
          label: l10n.pharmacyAdjustStockAction,
          leadingIcon: Icons.save_outlined,
          isLoading: _isSaving,
          onPressed: _submit,
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final int currentQty = widget.stock.quantity.round();
    final String qtyText = _deltaController.text.trim();
    final int? enteredQty = qtyText.isEmpty ? null : int.tryParse(qtyText);
    final int delta = enteredQty == null ? 0 : enteredQty - currentQty;
    final int? reorderLevel = int.tryParse(_reorderController.text.trim());
    if (delta == 0 && reorderLevel == null) {
      return;
    }
    if (_expiryDate != null && _batchController.text.trim().isEmpty) {
      return;
    }
    setState(() => _isSaving = true);
    final AppFailure? failure = await ref
        .read(pharmacyWorkspaceControllerProvider.notifier)
        .adjustInventoryStock(
          PharmacyInventoryAdjustInput(
            inventoryItemId:
                widget.stock.inventoryItemId ??
                widget.stock.inventoryItem?.id ??
                widget.stock.id,
            quantityDelta: delta,
            reorderLevel: reorderLevel,
            reason: _reason,
            notes: _emptyToNull(_notesController.text),
            facilityId: widget.stock.facilityId,
            batchNumber: _emptyToNull(_batchController.text),
            expiryDate: _expiryDate,
            storageRoomId: _storageRoomId,
            storageShelfId: _storageShelfId,
          ),
        );
    if (!mounted) {
      return;
    }
    if (failure == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _isSaving = false);
  }
}

/// Storage layout tab: renders storage rooms as a table with per-room Add
/// shelf / Edit / Delete actions. Reuses the shared storage dialogs and
/// controller CRUD so behavior matches the legacy expansion panel.
class _StorageLayoutCatalogTab extends ConsumerStatefulWidget {
  const _StorageLayoutCatalogTab({
    required this.state,
    required this.writeRequirement,
    this.fillHeight = false,
  });

  final PharmacyWorkspaceState state;
  final AccessRequirement writeRequirement;
  final bool fillHeight;

  @override
  ConsumerState<_StorageLayoutCatalogTab> createState() =>
      _StorageLayoutCatalogTabState();
}

class _StorageLayoutCatalogTabState
    extends ConsumerState<_StorageLayoutCatalogTab> {
  late final TextEditingController _searchController;
  bool _includeDeleted = false;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final List<PharmacyStorageRoom> allRooms = widget.state.storageLayout.rooms;
    final List<PharmacyStorageRoom> rooms = allRooms.where((
      PharmacyStorageRoom room,
    ) {
      if (!_includeDeleted && room.isSoftDeleted && _statusFilter != 'deleted') {
        return false;
      }
      switch (_statusFilter) {
        case 'active':
          return !room.isSoftDeleted && room.isActive;
        case 'inactive':
          return !room.isSoftDeleted && !room.isActive;
        case 'deleted':
          return room.isSoftDeleted;
        default:
          return _includeDeleted || !room.isSoftDeleted;
      }
    }).toList(growable: false);
    final AppPage<PharmacyStorageRoom> page = AppPage<PharmacyStorageRoom>(
      items: rooms,
      request: AppPageRequest(pageSize: rooms.isEmpty ? 10 : rooms.length),
    );
    final bool isBusy = widget.state.isRefreshingStorage;
    final AppAccessPolicy policy = ref.watch(appAccessPolicyProvider);
    final bool canExport = canExportPharmacyWorkspace(policy);
    final bool canPrint = canPrintPharmacyWorkspace(policy);

    return AppListTable<PharmacyStorageRoom>(
      page: page,
      isLoading: isBusy,
      shrinkWrap: !widget.fillHeight,
      physics: widget.fillHeight ? null : const NeverScrollableScrollPhysics(),
      columnVisibilityStorageKey: 'pharmacy_catalog_storage_rooms',
      columnVisibilityLabel: l10n.commonTableSettingsActionLabel,
      columnVisibilityTitle: l10n.commonTableSettingsTitle,
      columnVisibilityApplyLabel: l10n.receptionApplyColumnsAction,
      columnVisibilityResetLabel: l10n.receptionResetColumnsAction,
      columnVisibilityCloseLabel: l10n.commonCloseActionLabel,
      enableExport: true,
      canExport: canExport,
      exportLabel: l10n.commonTableExportActionLabel,
      exportDialogTitle: l10n.commonTableExportDialogTitle,
      exportCancelLabel: l10n.commonCancelActionLabel,
      exportColumnsSectionLabel: l10n.commonTableExportColumnsSectionLabel,
      exportFiltersSectionLabel: l10n.commonTableExportFiltersSectionLabel,
      exportEmptyColumnsMessage: l10n.commonTableExportEmptyColumnsMessage,
      exportEmptyRowsMessage: l10n.commonTableExportEmptyRowsMessage,
      exportSuccessMessage: l10n.commonTableExportSuccessMessage,
      exportFailureMessage: l10n.commonTableExportFailureMessage,
      enablePrint: true,
      canPrint: canPrint,
      printLabel: l10n.commonPrintActionLabel,
      onPrint: (List<PharmacyStorageRoom> items) =>
          _printPharmacyStorageRoomsList(
        context,
        ref,
        l10n: l10n,
        rooms: items,
      ),
      exportConfig: AppListTableExportConfig<PharmacyStorageRoom>(
        fileNameStem: 'pharmacy_storage_rooms',
        dateOf: (PharmacyStorageRoom item) => item.createdAt,
        filterGroups: <AppSearchBarFilterGroup>[
          AppSearchBarFilterGroup(
            key: 'room_status',
            label: l10n.pharmacyStorageStatusColumnLabel,
            choices: <AppSearchBarFilterChoice>[
              AppSearchBarFilterChoice(
                value: 'active',
                label: l10n.pharmacyStorageActiveLabel,
              ),
              AppSearchBarFilterChoice(
                value: 'inactive',
                label: l10n.pharmacyStorageInactiveLabel,
              ),
              AppSearchBarFilterChoice(
                value: 'deleted',
                label: l10n.pharmacyStorageDeletedLabel,
              ),
            ],
          ),
        ],
        rowFilter: (PharmacyStorageRoom item, AppSearchBarFilterValue filters) {
          final String? status = filters.options['room_status'];
          if (status == null || status.isEmpty) {
            return true;
          }
          return switch (status) {
            'active' => !item.isSoftDeleted && item.isActive,
            'inactive' => !item.isSoftDeleted && !item.isActive,
            'deleted' => item.isSoftDeleted,
            _ => true,
          };
        },
      ),
      search: AppListTableSearch<PharmacyStorageRoom>(
        controller: _searchController,
        semanticLabel: l10n.pharmacySearchLabel,
        hintText: l10n.pharmacyStorageRoomsSearchHint,
        matcher: (PharmacyStorageRoom item, String query) {
          final String needle = query.trim().toLowerCase();
          if (needle.isEmpty) {
            return true;
          }
          return (item.name ?? '').toLowerCase().contains(needle) ||
              (item.code ?? '').toLowerCase().contains(needle) ||
              item.id.toLowerCase().contains(needle);
        },
        showAdvancedFilterButton: true,
        advancedFilterButtonLabel: l10n.commonFiltersActionLabel,
        advancedFilterTitle: l10n.commonAdvancedFiltersTitle,
        advancedFilterApplyLabel: l10n.opdApplyFiltersAction,
        advancedFilterResetLabel: l10n.opdClearFiltersAction,
        advancedFilterCloseLabel: l10n.commonCloseActionLabel,
        filterGroups: <AppSearchBarFilterGroup>[
          AppSearchBarFilterGroup(
            key: 'room_status',
            label: l10n.pharmacyStorageStatusColumnLabel,
            choices: <AppSearchBarFilterChoice>[
              AppSearchBarFilterChoice(
                value: 'active',
                label: l10n.pharmacyStorageActiveLabel,
              ),
              AppSearchBarFilterChoice(
                value: 'inactive',
                label: l10n.pharmacyStorageInactiveLabel,
              ),
              AppSearchBarFilterChoice(
                value: 'deleted',
                label: l10n.pharmacyStorageDeletedLabel,
              ),
            ],
          ),
          AppSearchBarFilterGroup(
            key: 'include_deleted',
            label: l10n.pharmacyStorageIncludeDeletedFilterLabel,
            choices: <AppSearchBarFilterChoice>[
              AppSearchBarFilterChoice(
                value: 'yes',
                label: l10n.commonYesLabel,
              ),
            ],
          ),
        ],
        filterValue: AppSearchBarFilterValue(
          options: <String, String>{
            if (_statusFilter case final String status) 'room_status': status,
            if (_includeDeleted) 'include_deleted': 'yes',
          },
        ),
        hasActiveFilters: _statusFilter != null || _includeDeleted,
        onFilterChanged: (AppSearchBarFilterValue value) {
          setState(() {
            _statusFilter = value.options['room_status'];
            _includeDeleted = value.options['include_deleted'] == 'yes';
          });
        },
        trailingActions: _catalogSearchTrailingActions(
          ref: ref,
          writeRequirement: widget.writeRequirement,
          isBusy: isBusy,
          hasSelection: false,
          addLabel: l10n.commonCreateActionLabel,
          addSemanticLabel: l10n.pharmacyAddStorageRoomAction,
          onAdd: () async {
            final PharmacyStorageRoomFormResult result =
                await openPharmacyStorageRoomDialog(context, ref);
            if (!context.mounted || result.room == null) {
              return;
            }
            await openPharmacyStorageRoomDetailsDialog(
              context,
              ref,
              room: result.room!,
              writeRequirement: widget.writeRequirement,
            );
          },
        ),
      ),
      emptyBuilder: (_) => AppWorkspaceStatePanel.state(
        variant: AppStateViewVariant.empty,
        title: l10n.pharmacyNoStorageRoomsTitle,
        body: l10n.pharmacyNoStorageRoomsBody,
        icon: Icons.warehouse_outlined,
      ),
      columns: <AppListTableColumn<PharmacyStorageRoom>>[
        AppListTableColumn<PharmacyStorageRoom>(
          id: 'name',
          label: l10n.pharmacyStorageRoomNameLabel,
          preferredWidth: 200,
          cellBuilder: (_, PharmacyStorageRoom item) => Align(
            alignment: Alignment.centerLeft,
            child: Text(item.name ?? item.id, textAlign: TextAlign.start),
          ),
          exportValue: (PharmacyStorageRoom item) => item.name ?? '',
        ),
        AppListTableColumn<PharmacyStorageRoom>(
          id: 'code',
          label: l10n.pharmacyStorageRoomCodeLabel,
          preferredWidth: 110,
          cellBuilder: (_, PharmacyStorageRoom item) => Align(
            alignment: Alignment.centerLeft,
            child: Text(
              (item.code ?? '').isEmpty ? '—' : item.code!,
              textAlign: TextAlign.start,
            ),
          ),
          exportValue: (PharmacyStorageRoom item) => item.code ?? '',
        ),
        AppListTableColumn<PharmacyStorageRoom>(
          id: 'shelves_count',
          label: l10n.pharmacyStorageShelvesCountColumnLabel,
          fixedWidth: 88,
          cellBuilder: (_, PharmacyStorageRoom item) => Align(
            alignment: Alignment.centerLeft,
            child: Text(
              item.shelves.length.toString(),
              textAlign: TextAlign.start,
            ),
          ),
          exportValue: (PharmacyStorageRoom item) => item.shelves.length,
        ),
        AppListTableColumn<PharmacyStorageRoom>(
          id: 'status',
          label: l10n.pharmacyStorageStatusColumnLabel,
          fixedWidth: 110,
          cellBuilder: (BuildContext context, PharmacyStorageRoom item) {
            final String label = item.isSoftDeleted
                ? l10n.pharmacyStorageDeletedLabel
                : item.isActive
                ? l10n.pharmacyStorageActiveLabel
                : l10n.pharmacyStorageInactiveLabel;
            final AppWorkspaceStatusTone tone = item.isSoftDeleted
                ? AppWorkspaceStatusTone.error
                : item.isActive
                ? AppWorkspaceStatusTone.success
                : AppWorkspaceStatusTone.neutral;
            return Align(
              alignment: Alignment.centerLeft,
              child: AppWorkspaceStatusBadge(
                status: AppWorkspaceStatus(label: label, tone: tone),
              ),
            );
          },
          exportValue: (PharmacyStorageRoom item) => item.isSoftDeleted
              ? 'deleted'
              : item.isActive
              ? 'active'
              : 'inactive',
        ),
        AppListTableColumn<PharmacyStorageRoom>(
          id: 'actions',
          label: l10n.pharmacyLineActionsColumnLabel,
          alwaysVisible: true,
          fixedWidth: 320,
          cellBuilder: (BuildContext context, PharmacyStorageRoom item) {
            if (item.isSoftDeleted) {
              return _catalogRowActions(
                context: context,
                writeRequirement: widget.writeRequirement,
                isBusy: isBusy,
                alignStart: true,
                editLabel: l10n.pharmacyRestoreStorageRoomAction,
                deleteLabel: l10n.pharmacyPermanentDeleteStorageRoomAction,
                editSemanticLabel: l10n.pharmacyRestoreStorageRoomAction,
                deleteSemanticLabel:
                    l10n.pharmacyPermanentDeleteStorageRoomAction,
                editIcon: Icons.restore_outlined,
                deleteIcon: Icons.delete_forever_outlined,
                onEdit: () =>
                    confirmRestorePharmacyStorageRoom(context, ref, item),
                onDelete: () => confirmPermanentDeletePharmacyStorageRoom(
                  context,
                  ref,
                  item,
                ),
              );
            }
            return _catalogRowActions(
              context: context,
              writeRequirement: widget.writeRequirement,
              isBusy: isBusy,
              alignStart: true,
              editLabel: l10n.commonEditActionLabel,
              deleteLabel: l10n.commonDeleteActionLabel,
              editSemanticLabel: l10n.pharmacyEditStorageRoomAction,
              deleteSemanticLabel: l10n.pharmacyDeleteStorageRoomAction,
              onEdit: () async {
                final PharmacyStorageRoomFormResult result =
                    await openPharmacyStorageRoomDialog(
                      context,
                      ref,
                      room: item,
                    );
                if (!context.mounted || result.room == null) {
                  return;
                }
                await openPharmacyStorageRoomDetailsDialog(
                  context,
                  ref,
                  room: result.room!,
                  writeRequirement: widget.writeRequirement,
                );
              },
              onDelete: () =>
                  confirmDeletePharmacyStorageRoom(context, ref, item),
            );
          },
        ),
      ],
      columnChoices: <AppListTableColumn<PharmacyStorageRoom>>[
        AppListTableColumn<PharmacyStorageRoom>(
          id: 'created_at',
          label: l10n.pharmacyStorageCreatedAtColumnLabel,
          preferredWidth: 160,
          cellBuilder: (BuildContext context, PharmacyStorageRoom item) {
            if (item.createdAt == null) {
              return const Align(
                alignment: Alignment.centerLeft,
                child: Text('—', textAlign: TextAlign.start),
              );
            }
            return Align(
              alignment: Alignment.centerLeft,
              child: Text(
                AppFormatters.dateTime(
                  item.createdAt!,
                  Localizations.localeOf(context),
                ),
                textAlign: TextAlign.start,
              ),
            );
          },
          exportValue: (PharmacyStorageRoom item) =>
              item.createdAt?.toIso8601String() ?? '',
        ),
      ],
            onRowSelected: (PharmacyStorageRoom item) {
        unawaited(
          openPharmacyStorageRoomDetailsDialog(
            context,
            ref,
            room: item,
            writeRequirement: widget.writeRequirement,
          ),
        );
      },
      mobileItemBuilder: (BuildContext context, PharmacyStorageRoom item) {
        return AppListTableMobileItem(
          title: item.name ?? item.id,
          caption: item.code,
          meta: <AppListTableMobileMeta>[
            AppListTableMobileMeta(
              label:
                  '${item.shelves.length} · ${l10n.pharmacyStorageShelvesCountColumnLabel}',
              icon: Icons.view_week_outlined,
            ),
            AppListTableMobileMeta(
              label: item.isSoftDeleted
                  ? l10n.pharmacyStorageDeletedLabel
                  : item.isActive
                  ? l10n.pharmacyStorageActiveLabel
                  : l10n.pharmacyStorageInactiveLabel,
            ),
          ],
          showAvatar: false,
        );
      },
    );
  }
}

/// Shelves tab: flattens shelves across all rooms into a single table with
/// Add / Edit / Delete actions. Create opens one dialog with room + shelf fields.
class _ShelvesCatalogTab extends ConsumerStatefulWidget {
  const _ShelvesCatalogTab({
    required this.state,
    required this.writeRequirement,
    this.fillHeight = false,
  });

  final PharmacyWorkspaceState state;
  final AccessRequirement writeRequirement;
  final bool fillHeight;

  @override
  ConsumerState<_ShelvesCatalogTab> createState() => _ShelvesCatalogTabState();
}

class _ShelvesCatalogTabState extends ConsumerState<_ShelvesCatalogTab> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final List<PharmacyStorageRoom> rooms = widget.state.storageLayout.rooms;
    final List<_ShelfRow> shelfRows = <_ShelfRow>[
      for (final PharmacyStorageRoom room in rooms)
        for (final PharmacyStorageShelf shelf in room.shelves)
          _ShelfRow(room: room, shelf: shelf),
    ];
    final AppPage<_ShelfRow> page = AppPage<_ShelfRow>(
      items: shelfRows,
      request: AppPageRequest(
        pageSize: shelfRows.isEmpty ? 10 : shelfRows.length,
      ),
    );
    final bool isBusy = widget.state.isRefreshingStorage;
    final List<PharmacyStorageRoom> activeRooms = _activeStorageRooms(
      widget.state.storageLayout,
    );
    final AppAccessPolicy policy = ref.watch(appAccessPolicyProvider);
    final bool canExport = canExportPharmacyWorkspace(policy);
    final bool canPrint = canPrintPharmacyWorkspace(policy);

    return AppListTable<_ShelfRow>(
      page: page,
      isLoading: isBusy,
      shrinkWrap: !widget.fillHeight,
      physics: widget.fillHeight ? null : const NeverScrollableScrollPhysics(),
      columnVisibilityStorageKey: 'pharmacy_catalog_shelves',
      columnVisibilityLabel: l10n.commonTableSettingsActionLabel,
      columnVisibilityTitle: l10n.commonTableSettingsTitle,
      columnVisibilityApplyLabel: l10n.receptionApplyColumnsAction,
      columnVisibilityResetLabel: l10n.receptionResetColumnsAction,
      columnVisibilityCloseLabel: l10n.commonCloseActionLabel,
      enableExport: true,
      canExport: canExport,
      exportLabel: l10n.commonTableExportActionLabel,
      exportDialogTitle: l10n.commonTableExportDialogTitle,
      exportCancelLabel: l10n.commonCancelActionLabel,
      exportColumnsSectionLabel: l10n.commonTableExportColumnsSectionLabel,
      exportFiltersSectionLabel: l10n.commonTableExportFiltersSectionLabel,
      exportEmptyColumnsMessage: l10n.commonTableExportEmptyColumnsMessage,
      exportEmptyRowsMessage: l10n.commonTableExportEmptyRowsMessage,
      exportSuccessMessage: l10n.commonTableExportSuccessMessage,
      exportFailureMessage: l10n.commonTableExportFailureMessage,
      enablePrint: true,
      canPrint: canPrint,
      printLabel: l10n.commonPrintActionLabel,
      onPrint: (List<_ShelfRow> items) => _printPharmacyShelvesList(
        context,
        ref,
        l10n: l10n,
        shelves: items,
      ),
      exportConfig: AppListTableExportConfig<_ShelfRow>(
        fileNameStem: 'pharmacy_shelves',
        dateOf: (_ShelfRow row) => row.room.createdAt,
      ),
      search: AppListTableSearch<_ShelfRow>(
        controller: _searchController,
        semanticLabel: l10n.pharmacySearchLabel,
        hintText: l10n.pharmacySearchHint,
        matcher: (_ShelfRow row, String query) {
          final String needle = query.trim().toLowerCase();
          if (needle.isEmpty) {
            return true;
          }
          return row.shelf.displayLabel.toLowerCase().contains(needle) ||
              (row.shelf.shelfCode ?? '').toLowerCase().contains(needle) ||
              (row.shelf.label ?? '').toLowerCase().contains(needle) ||
              (row.room.name ?? '').toLowerCase().contains(needle);
        },
        enableDateFilter: false,
        trailingActions: _catalogSearchTrailingActions(
          ref: ref,
          writeRequirement: widget.writeRequirement,
          isBusy: isBusy,
          hasSelection: false,
          addLabel: l10n.commonCreateActionLabel,
          addSemanticLabel: l10n.pharmacyAddStorageShelfAction,
          onAdd: activeRooms.isEmpty
              ? null
              : () => unawaited(
                  openPharmacyStorageShelfDialog(
                    context,
                    ref,
                    availableRooms: activeRooms,
                  ),
                ),
        ),
      ),
      emptyBuilder: (_) => AppWorkspaceStatePanel.state(
        variant: AppStateViewVariant.empty,
        title: l10n.pharmacyNoStorageShelvesTitle,
        body: l10n.pharmacyNoStorageShelvesBody,
        icon: Icons.view_week_outlined,
      ),
      columns: <AppListTableColumn<_ShelfRow>>[
        AppListTableColumn<_ShelfRow>(
          id: 'shelf_code',
          label: l10n.pharmacyStorageShelfCodeLabel,
          preferredWidth: 120,
          cellBuilder: (_, _ShelfRow row) => Align(
            alignment: Alignment.centerLeft,
            child: Text(
              row.shelf.shelfCode ?? row.shelf.displayLabel,
              textAlign: TextAlign.start,
            ),
          ),
        ),
        AppListTableColumn<_ShelfRow>(
          id: 'label',
          label: l10n.pharmacyStorageShelfLabelField,
          preferredWidth: 160,
          cellBuilder: (_, _ShelfRow row) {
            final String label = (row.shelf.label ?? '').trim();
            return Align(
              alignment: Alignment.centerLeft,
              child: Text(
                label.isEmpty ? '—' : label,
                textAlign: TextAlign.start,
              ),
            );
          },
        ),
        AppListTableColumn<_ShelfRow>(
          id: 'room',
          label: l10n.pharmacyStorageRoomLabel,
          preferredWidth: 160,
          cellBuilder: (_, _ShelfRow row) => Align(
            alignment: Alignment.centerLeft,
            child: Text(
              row.room.name ?? row.room.id,
              textAlign: TextAlign.start,
            ),
          ),
        ),
        AppListTableColumn<_ShelfRow>(
          id: 'status',
          label: l10n.pharmacyStorageStatusColumnLabel,
          fixedWidth: 110,
          cellBuilder: (BuildContext context, _ShelfRow row) {
            return Align(
              alignment: Alignment.centerLeft,
              child: AppWorkspaceStatusBadge(
                status: AppWorkspaceStatus(
                  label: row.shelf.isActive
                      ? l10n.pharmacyStorageActiveLabel
                      : l10n.pharmacyStorageInactiveLabel,
                  tone: row.shelf.isActive
                      ? AppWorkspaceStatusTone.success
                      : AppWorkspaceStatusTone.neutral,
                ),
              ),
            );
          },
        ),
        AppListTableColumn<_ShelfRow>(
          id: 'actions',
          label: l10n.pharmacyLineActionsColumnLabel,
          alwaysVisible: true,
          fixedWidth: 240,
          cellBuilder: (BuildContext context, _ShelfRow row) {
            return _catalogRowActions(
              context: context,
              writeRequirement: widget.writeRequirement,
              isBusy: isBusy,
              alignStart: true,
              editLabel: l10n.commonEditActionLabel,
              deleteLabel: l10n.commonDeleteActionLabel,
              editSemanticLabel: l10n.pharmacyEditStorageShelfAction,
              deleteSemanticLabel: l10n.pharmacyDeleteStorageShelfAction,
              onEdit: () => unawaited(
                openPharmacyStorageShelfDialog(
                  context,
                  ref,
                  room: row.room,
                  shelf: row.shelf,
                ),
              ),
              onDelete: () =>
                  confirmDeletePharmacyStorageShelf(context, ref, row.shelf),
            );
          },
        ),
      ],
      onRowSelected: (_ShelfRow row) {
        unawaited(
          openPharmacyStorageShelfDetailsDialog(
            context,
            ref,
            room: row.room,
            shelf: row.shelf,
            writeRequirement: widget.writeRequirement,
          ),
        );
      },
      mobileItemBuilder: (BuildContext context, _ShelfRow row) {
        return AppListTableMobileItem(
          title: row.shelf.displayLabel,
          caption: row.room.name,
          meta: <AppListTableMobileMeta>[
            AppListTableMobileMeta(
              label: row.shelf.isActive
                  ? l10n.pharmacyStorageActiveLabel
                  : l10n.pharmacyStorageInactiveLabel,
            ),
          ],
          showAvatar: false,
        );
      },
    );
  }
}

@immutable
class _ShelfRow {
  const _ShelfRow({required this.room, required this.shelf});

  final PharmacyStorageRoom room;
  final PharmacyStorageShelf shelf;
}

AppListTableColumn<T> _selectionColumn<T>({
  required List<T> visibleItems,
  required Set<String> selectedKeys,
  required ValueNotifier<int> selectionTick,
  required bool isBusy,
  required String Function(T item) itemKey,
  required void Function(T item, bool selected) onToggle,
  required void Function(List<T> items, bool selected) onToggleAll,
}) {
  return AppListTableColumn<T>(
    id: 'select',
    label: '',
    alwaysVisible: true,
    exportable: false,
    fixedWidth: 48,
    headerBuilder: (BuildContext context) {
      return ListenableBuilder(
        listenable: selectionTick,
        builder: (BuildContext context, _) {
          final AppLocalizations l10n = context.l10n;
          final bool allSelected =
              visibleItems.isNotEmpty &&
              visibleItems.every(
                (T item) => selectedKeys.contains(itemKey(item)),
              );
          final bool someSelected = visibleItems.any(
            (T item) => selectedKeys.contains(itemKey(item)),
          );
          final String tooltip = allSelected
              ? l10n.commonDeselectAllActionLabel
              : l10n.commonSelectAllActionLabel;
          return Align(
            alignment: Alignment.centerLeft,
            child: Tooltip(
              message: tooltip,
              child: Semantics(
                label: tooltip,
                checked: allSelected,
                mixed: someSelected && !allSelected,
                child: Checkbox(
                  key: ValueKey<Object>(
                    'select-all-$allSelected-$someSelected-${selectionTick.value}',
                  ),
                  tristate: true,
                  value: allSelected
                      ? true
                      : someSelected
                      ? null
                      : false,
                  // Match Material tristate: true → select all, false/null → clear.
                  onChanged: !isBusy && visibleItems.isNotEmpty
                      ? (bool? checked) =>
                            onToggleAll(visibleItems, checked ?? false)
                      : null,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          );
        },
      );
    },
    cellBuilder: (BuildContext context, T item) {
      final String key = itemKey(item);
      return ListenableBuilder(
        listenable: selectionTick,
        builder: (BuildContext context, _) {
          final bool selected = selectedKeys.contains(key);
          return Align(
            alignment: Alignment.centerLeft,
            child: Checkbox(
              key: ValueKey<Object>('select-row-$key-$selected'),
              value: selected,
              onChanged: isBusy
                  ? null
                  : (bool? value) => onToggle(item, value ?? false),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          );
        },
      );
    },
  );
}

class _ClearSelectedInventoryDialog extends StatefulWidget {
  const _ClearSelectedInventoryDialog({required this.stocks});

  final List<PharmacyInventoryStock> stocks;

  @override
  State<_ClearSelectedInventoryDialog> createState() =>
      _ClearSelectedInventoryDialogState();
}

class _ClearSelectedInventoryDialogState
    extends State<_ClearSelectedInventoryDialog> {
  late final TextEditingController _searchController;
  late final Set<String> _selectedIds;
  final ValueNotifier<int> _selectionTick = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(_onSearchChanged);
    _selectedIds = widget.stocks
        .map((PharmacyInventoryStock stock) => stock.id)
        .toSet();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _selectionTick.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {});
  }

  void _mutateSelection(void Function() mutate) {
    mutate();
    _selectionTick.value++;
    setState(() {});
  }

  bool _matchesSearch(PharmacyInventoryStock item, String query) {
    final String normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }
    final String haystack = <String?>[
      item.inventoryItem?.displayTitle,
      item.inventoryItem?.sku,
      item.displayId,
      item.storageLocationLabel,
      item.id,
    ].whereType<String>().join(' ').toLowerCase();
    return haystack.contains(normalized);
  }

  List<PharmacyInventoryStock> get _visibleStocks {
    final String query = _searchController.text;
    return widget.stocks
        .where((PharmacyInventoryStock item) => _matchesSearch(item, query))
        .toList(growable: false);
  }

  List<PharmacyInventoryStock> get _confirmedStocks {
    return widget.stocks
        .where((PharmacyInventoryStock stock) => _selectedIds.contains(stock.id))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final int selectedCount = _selectedIds.length;
    final AppPage<PharmacyInventoryStock> page = AppPage<PharmacyInventoryStock>(
      items: widget.stocks,
      request: AppPageRequest(
        pageSize: widget.stocks.isEmpty ? 1 : widget.stocks.length,
      ),
      totalItemCount: widget.stocks.length,
    );

    return AppDialog(
      title: Text(l10n.pharmacyClearSelectedInventoryDialogTitle),
      initialMaximized: false,
      showMaximizeButton: false,
      pinActionsToBottom: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(l10n.pharmacyClearSelectedInventoryDialogBody(selectedCount)),
          SizedBox(height: theme.spacing.md),
          Expanded(
            child: AppListTable<PharmacyInventoryStock>(
              page: page,
              rowsVersion: _selectionTick.value,
              itemKeyBuilder: (PharmacyInventoryStock item) =>
                  ValueKey<String>(item.id),
              enableExport: false,
              tableHorizontalMargin: 0,
              search: AppListTableSearch<PharmacyInventoryStock>(
                controller: _searchController,
                semanticLabel: l10n.pharmacyInventoryFiltersSemanticLabel,
                hintText: l10n.pharmacyInventorySearchHint,
                matcher: _matchesSearch,
                enableDateFilter: false,
              ),
              columns: <AppListTableColumn<PharmacyInventoryStock>>[
                _selectionColumn<PharmacyInventoryStock>(
                  visibleItems: _visibleStocks,
                  selectedKeys: _selectedIds,
                  selectionTick: _selectionTick,
                  isBusy: false,
                  itemKey: (PharmacyInventoryStock item) => item.id,
                  onToggle: (PharmacyInventoryStock item, bool selected) {
                    _mutateSelection(() {
                      if (selected) {
                        _selectedIds.add(item.id);
                      } else {
                        _selectedIds.remove(item.id);
                      }
                    });
                  },
                  onToggleAll: (List<PharmacyInventoryStock> items, bool selected) {
                    _mutateSelection(() {
                      if (!selected) {
                        for (final PharmacyInventoryStock item in items) {
                          _selectedIds.remove(item.id);
                        }
                        return;
                      }
                      for (final PharmacyInventoryStock item in items) {
                        _selectedIds.add(item.id);
                      }
                    });
                  },
                ),
                AppListTableColumn<PharmacyInventoryStock>(
                  id: 'item',
                  label: l10n.pharmacyInventoryItemLabel,
                  preferredWidth: 280,
                  alwaysVisible: true,
                  cellBuilder: (_, PharmacyInventoryStock item) => Text(
                    item.inventoryItem?.displayTitle ??
                        item.displayId ??
                        item.id,
                  ),
                ),
                AppListTableColumn<PharmacyInventoryStock>(
                  id: 'sku',
                  label: l10n.pharmacyInventorySkuColumnLabel,
                  preferredWidth: 120,
                  cellBuilder: (_, PharmacyInventoryStock item) {
                    final String sku =
                        (item.inventoryItem?.sku ?? '').trim();
                    return Text(sku.isEmpty ? '—' : sku);
                  },
                ),
                AppListTableColumn<PharmacyInventoryStock>(
                  id: 'quantity',
                  label: l10n.pharmacyInventoryQuantityColumnLabel,
                  numeric: true,
                  fixedWidth: 72,
                  alwaysVisible: true,
                  cellBuilder: (_, PharmacyInventoryStock item) =>
                      Text(item.quantity.toString()),
                ),
                AppListTableColumn<PharmacyInventoryStock>(
                  id: 'reorder_level',
                  label: l10n.pharmacyReorderLevelColumnLabel,
                  numeric: true,
                  fixedWidth: 84,
                  cellBuilder: (_, PharmacyInventoryStock item) =>
                      Text(item.reorderLevel.toString()),
                ),
                AppListTableColumn<PharmacyInventoryStock>(
                  id: 'storage_location',
                  label: l10n.pharmacyStorageLocationColumnLabel,
                  preferredWidth: 200,
                  cellBuilder: (_, PharmacyInventoryStock item) =>
                      Text(item.storageLocationLabel ?? '—'),
                ),
              ],
              mobileItemBuilder:
                  (BuildContext context, PharmacyInventoryStock item) {
                final bool selected = _selectedIds.contains(item.id);
                return AppListTableMobileItem(
                  leading: Checkbox(
                    value: selected,
                    onChanged: (bool? value) {
                      _mutateSelection(() {
                        if (value ?? false) {
                          _selectedIds.add(item.id);
                        } else {
                          _selectedIds.remove(item.id);
                        }
                      });
                    },
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  title: item.inventoryItem?.displayTitle ?? item.displayId ?? '',
                  meta: <AppListTableMobileMeta>[
                    AppListTableMobileMeta(
                      label:
                          '${item.quantity} · ${l10n.pharmacyReorderLevelColumnLabel}: ${item.reorderLevel}',
                    ),
                    if ((item.storageLocationLabel ?? '').trim().isNotEmpty)
                      AppListTableMobileMeta(
                        label: item.storageLocationLabel!,
                      ),
                  ],
                  showAvatar: false,
                );
              },
              emptyBuilder: (_) => AppWorkspaceStatePanel.state(
                variant: AppStateViewVariant.empty,
                title: l10n.pharmacyNoInventoryTitle,
                body: l10n.pharmacyNoInventoryBody,
                icon: Icons.warehouse_outlined,
              ),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        AppButton.close(
          label: l10n.commonCancelActionLabel,
          leadingIcon: Icons.close,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton.tertiary(
          label: l10n.pharmacyClearSelectedInventoryAction,
          leadingIcon: AppActionIcons.delete,
          color: theme.colorScheme.error,
          enabled: selectedCount > 0,
          onPressed: selectedCount == 0
              ? null
              : () => Navigator.of(context).pop(_confirmedStocks),
        ),
      ],
    );
  }
}

class _InventoryClearSelectedTile extends StatelessWidget {
  const _InventoryClearSelectedTile({required this.stock});

  final PharmacyInventoryStock stock;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = context.l10n;
    final ColorScheme colors = theme.colorScheme;
    final String title =
        stock.inventoryItem?.displayTitle ?? stock.displayId ?? stock.id;
    final String? sku = stock.inventoryItem?.sku?.trim();
    final String location = (stock.storageLocationLabel ?? '').trim();
    final String meta = <String>[
      '${l10n.pharmacyInventoryQuantityColumnLabel}: ${stock.quantity}',
      '${l10n.pharmacyReorderLevelColumnLabel}: ${stock.reorderLevel}',
      if (location.isNotEmpty) location,
    ].join(' · ');

    return DecoratedBox(
      decoration: BoxDecoration(
        border: theme.borders.all(),
        borderRadius: BorderRadius.circular(theme.radius.sm),
      ),
      child: Padding(
        padding: EdgeInsets.all(theme.spacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: AppFontWeight.emphasis,
              ),
            ),
            if (sku != null && sku.isNotEmpty) ...<Widget>[
              SizedBox(height: theme.spacing.xs / 2),
              Text(
                '${l10n.pharmacyInventorySkuColumnLabel}: $sku',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            SizedBox(height: theme.spacing.xs / 2),
            Text(
              meta,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _catalogRowActions({
  required BuildContext context,
  required AccessRequirement writeRequirement,
  required bool isBusy,
  required String editLabel,
  required String deleteLabel,
  required VoidCallback onEdit,
  required VoidCallback onDelete,
  String? editSemanticLabel,
  String? deleteSemanticLabel,
  IconData editIcon = Icons.edit_outlined,
  IconData deleteIcon = Icons.delete_outline,
  String? addLabel,
  String? addSemanticLabel,
  VoidCallback? onAdd,
  bool addEnabled = true,
  IconData addIcon = Icons.add,
  bool alignStart = false,
}) {
  final ThemeData theme = Theme.of(context);
  final ColorScheme colorScheme = theme.colorScheme;
  final String editSemantic = editSemanticLabel ?? editLabel;
  final String deleteSemantic = deleteSemanticLabel ?? deleteLabel;
  final String? addSemantic = addSemanticLabel ?? addLabel;
  final Alignment alignment = alignStart
      ? Alignment.centerLeft
      : Alignment.centerRight;
  return AppAccessActionGate(
    requirement: writeRequirement,
    builder: (BuildContext context, bool isAllowed) => Align(
      alignment: alignment,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (onAdd != null && addLabel != null) ...<Widget>[
            AppButton.tertiary(
              dense: true,
              leadingIcon: addIcon,
              label: addLabel,
              semanticLabel: addSemantic,
              tooltip: addSemantic,
              enabled: isAllowed && !isBusy && addEnabled,
              onPressed: isAllowed && !isBusy && addEnabled ? onAdd : null,
            ),
            SizedBox(width: theme.spacing.xs),
          ],
          AppButton.tertiary(
            dense: true,
            leadingIcon: editIcon,
            label: editLabel,
            semanticLabel: editSemantic,
            tooltip: editSemantic,
            enabled: isAllowed && !isBusy,
            onPressed: isAllowed && !isBusy ? onEdit : null,
          ),
          SizedBox(width: theme.spacing.xs),
          AppButton.tertiary(
            dense: true,
            leadingIcon: deleteIcon,
            label: deleteLabel,
            semanticLabel: deleteSemantic,
            tooltip: deleteSemantic,
            color: colorScheme.error,
            enabled: isAllowed && !isBusy,
            onPressed: isAllowed && !isBusy ? onDelete : null,
          ),
        ],
      ),
    ),
  );
}

Widget _expiryCell(BuildContext context, PharmacyInventoryStock item) {
  final AppLocalizations l10n = context.l10n;
  if (item.nextExpiry == null) {
    return const Text('—');
  }
  final String formatted = AppFormatters.dateTime(
    item.nextExpiry!,
    Localizations.localeOf(context),
  );
  if (item.expiryAlertStatus == 'EXPIRED') {
    return AppWorkspaceStatusBadge(
      status: AppWorkspaceStatus(
        label: '$formatted · ${l10n.pharmacyStockExpiredLabel}',
        tone: AppWorkspaceStatusTone.error,
      ),
    );
  }
  if (item.expiryAlertStatus == 'EXPIRING_SOON') {
    return AppWorkspaceStatusBadge(
      status: AppWorkspaceStatus(
        label: '$formatted · ${l10n.pharmacyStockExpiringSoonLabel}',
        tone: AppWorkspaceStatusTone.warning,
      ),
    );
  }
  return Text(formatted);
}

AppWorkspaceStatus _stockStatus(BuildContext context, String? value) {
  final AppLocalizations l10n = context.l10n;
  final String normalized = (value ?? '').toUpperCase();
  final String label = switch (normalized) {
    'IN_STOCK' => l10n.pharmacyStockInStock,
    'ALMOST_OUT_OF_STOCK' => l10n.pharmacyStockAlmostOut,
    'LOW_STOCK' => l10n.pharmacyStockLow,
    'OUT_OF_STOCK' => l10n.pharmacyStockOut,
    _ => l10n.pharmacyStockUnknown,
  };
  return AppWorkspaceStatus(
    label: label,
    tone: switch (normalized) {
      'IN_STOCK' => AppWorkspaceStatusTone.success,
      'ALMOST_OUT_OF_STOCK' => AppWorkspaceStatusTone.warning,
      'LOW_STOCK' || 'OUT_OF_STOCK' => AppWorkspaceStatusTone.error,
      _ => AppWorkspaceStatusTone.neutral,
    },
  );
}

String? _emptyToNull(String value) {
  final String normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

String _priceText(num? value) {
  if (value == null) {
    return '';
  }
  return value.toString();
}

List<PharmacyStorageRoom> _activeStorageRooms(PharmacyStorageLayout layout) {
  return layout.rooms
      .where((PharmacyStorageRoom room) => room.isActive)
      .toList(growable: false);
}

List<PharmacyStorageShelf> _shelfOptionsForRoom(
  PharmacyStorageLayout layout,
  String? roomId,
) {
  if (roomId == null) {
    return const <PharmacyStorageShelf>[];
  }
  return _activeStorageRooms(layout)
      .where((PharmacyStorageRoom room) => room.id == roomId)
      .expand((PharmacyStorageRoom room) => room.shelves)
      .where((PharmacyStorageShelf shelf) => shelf.isActive)
      .toList(growable: false);
}

/// Builds search-bar trailing actions (after Filters → Settings → Export).
/// Selection bulk actions replace Import and Add while rows are selected.
List<AppSearchBarAction> _catalogSearchTrailingActions({
  required WidgetRef ref,
  required AccessRequirement writeRequirement,
  required bool isBusy,
  required bool hasSelection,
  String? importLabel,
  String? importSemanticLabel,
  VoidCallback? onImport,
  String? addLabel,
  String? addSemanticLabel,
  VoidCallback? onAdd,
  String? selectionLabel,
  VoidCallback? onSelectionAction,
}) {
  if (!writeRequirement.allows(ref)) {
    return const <AppSearchBarAction>[];
  }

  if (hasSelection &&
      selectionLabel != null &&
      onSelectionAction != null) {
    return <AppSearchBarAction>[
      AppSearchBarAction(
        icon: Icons.delete_outline,
        label: selectionLabel,
        tooltip: selectionLabel,
        enabled: !isBusy,
        destructive: true,
        onPressed: isBusy ? null : onSelectionAction,
      ),
    ];
  }

  if (hasSelection) {
    return const <AppSearchBarAction>[];
  }

  return <AppSearchBarAction>[
    if (importLabel != null && onImport != null)
      AppSearchBarAction(
        icon: Icons.upload_file_outlined,
        label: importLabel,
        tooltip: importSemanticLabel ?? importLabel,
        enabled: !isBusy,
        onPressed: isBusy ? null : onImport,
      ),
    if (addLabel != null && onAdd != null)
      AppSearchBarAction(
        icon: Icons.add,
        label: addLabel,
        tooltip: addSemanticLabel ?? addLabel,
        enabled: !isBusy,
        onPressed: isBusy ? null : onAdd,
      ),
  ];
}

List<AppSearchBarFilterGroup> _storageLocationFilterGroups({
  required AppLocalizations l10n,
  required PharmacyStorageLayout layout,
  required String? storageRoomId,
}) {
  final List<PharmacyStorageRoom> activeRooms = _activeStorageRooms(layout);
  if (activeRooms.isEmpty) {
    return const <AppSearchBarFilterGroup>[];
  }

  final List<AppSearchBarFilterGroup> groups = <AppSearchBarFilterGroup>[
    AppSearchBarFilterGroup(
      key: _storageRoomFilterKey,
      label: l10n.pharmacyStorageRoomLabel,
      allLabel: l10n.pharmacyStorageFilterAll,
      choices: activeRooms
          .map(
            (PharmacyStorageRoom room) => AppSearchBarFilterChoice(
              value: room.id,
              label: room.name ?? room.id,
              icon: Icons.warehouse_outlined,
            ),
          )
          .toList(growable: false),
    ),
  ];

  if (storageRoomId != null) {
    final List<PharmacyStorageShelf> shelves = _shelfOptionsForRoom(
      layout,
      storageRoomId,
    );
    if (shelves.isNotEmpty) {
      groups.add(
        AppSearchBarFilterGroup(
          key: _storageShelfFilterKey,
          label: l10n.pharmacyStorageShelfLabel,
          allLabel: l10n.pharmacyStorageFilterAll,
          choices: shelves
              .map(
                (PharmacyStorageShelf shelf) => AppSearchBarFilterChoice(
                  value: shelf.id,
                  label: shelf.displayLabel,
                  icon: Icons.view_week_outlined,
                ),
              )
              .toList(growable: false),
        ),
      );
    }
  }

  return groups;
}

List<AppSearchBarFilterGroup> _drugCatalogFilterGroups({
  required AppLocalizations l10n,
  required PharmacyStorageLayout layout,
  required String? storageRoomId,
}) {
  return <AppSearchBarFilterGroup>[
    ..._storageLocationFilterGroups(
      l10n: l10n,
      layout: layout,
      storageRoomId: storageRoomId,
    ),
    AppSearchBarFilterGroup(
      key: _drugStockStatusFilterKey,
      label: l10n.pharmacyStockStatusFilterLabel,
      allLabel: l10n.opdAllFieldsFilterLabel,
      choices: <AppSearchBarFilterChoice>[
        AppSearchBarFilterChoice(
          value: 'IN_STOCK',
          label: l10n.pharmacyStockInStock,
          icon: Icons.check_circle_outline,
        ),
        AppSearchBarFilterChoice(
          value: 'ALMOST_OUT_OF_STOCK',
          label: l10n.pharmacyStockAlmostOut,
          icon: Icons.warning_amber_outlined,
        ),
        AppSearchBarFilterChoice(
          value: 'LOW_STOCK',
          label: l10n.pharmacyStockLow,
          icon: Icons.trending_down,
        ),
        AppSearchBarFilterChoice(
          value: 'OUT_OF_STOCK',
          label: l10n.pharmacyStockOut,
          icon: Icons.remove_shopping_cart_outlined,
        ),
      ],
    ),
  ];
}

List<AppSearchBarFilterGroup> _formularyCatalogFilterGroups(
  AppLocalizations l10n,
) {
  return <AppSearchBarFilterGroup>[
    AppSearchBarFilterGroup(
      key: _formularyActiveFilterKey,
      label: l10n.pharmacyFormularyActiveLabel,
      allLabel: l10n.opdAllFieldsFilterLabel,
      choices: <AppSearchBarFilterChoice>[
        AppSearchBarFilterChoice(
          value: 'true',
          label: l10n.commonYesLabel,
          icon: Icons.check_circle_outline,
        ),
        AppSearchBarFilterChoice(
          value: 'false',
          label: l10n.commonNoLabel,
          icon: Icons.cancel_outlined,
        ),
      ],
    ),
  ];
}

List<AppSearchBarFilterGroup> _inventoryCatalogFilterGroups({
  required AppLocalizations l10n,
  required PharmacyStorageLayout layout,
  required String? storageRoomId,
}) {
  return <AppSearchBarFilterGroup>[
    ..._storageLocationFilterGroups(
      l10n: l10n,
      layout: layout,
      storageRoomId: storageRoomId,
    ),
    AppSearchBarFilterGroup(
      key: _inventoryStockStatusFilterKey,
      label: l10n.pharmacyStockStatusFilterLabel,
      allLabel: l10n.opdAllFieldsFilterLabel,
      choices: <AppSearchBarFilterChoice>[
        AppSearchBarFilterChoice(
          value: 'IN_STOCK',
          label: l10n.pharmacyStockInStock,
          icon: Icons.check_circle_outline,
        ),
        AppSearchBarFilterChoice(
          value: 'ALMOST_OUT_OF_STOCK',
          label: l10n.pharmacyStockAlmostOut,
          icon: Icons.warning_amber_outlined,
        ),
        AppSearchBarFilterChoice(
          value: 'LOW_STOCK',
          label: l10n.pharmacyStockLow,
          icon: Icons.trending_down,
        ),
        AppSearchBarFilterChoice(
          value: 'OUT_OF_STOCK',
          label: l10n.pharmacyStockOut,
          icon: Icons.remove_shopping_cart_outlined,
        ),
        AppSearchBarFilterChoice(
          value: 'EXPIRING_SOON',
          label: l10n.pharmacyExpiringSoonFilterLabel,
          icon: Icons.schedule,
        ),
        AppSearchBarFilterChoice(
          value: 'EXPIRED',
          label: l10n.pharmacyExpiredOnlyFilterLabel,
          icon: Icons.event_busy,
        ),
      ],
    ),
    AppSearchBarFilterGroup(
      key: _inventoryPendingFilterKey,
      label: l10n.pharmacyInventoryPendingStockColumnLabel,
      allLabel: l10n.opdAllFieldsFilterLabel,
      choices: <AppSearchBarFilterChoice>[
        AppSearchBarFilterChoice(
          value: 'true',
          label: l10n.commonYesLabel,
          icon: Icons.hourglass_top_outlined,
        ),
        AppSearchBarFilterChoice(
          value: 'false',
          label: l10n.commonNoLabel,
          icon: Icons.hourglass_empty,
        ),
      ],
    ),
  ];
}

AppSearchBarFilterValue _catalogStorageFilterValue({
  String? storageRoomId,
  String? storageShelfId,
}) {
  final Map<String, String> options = <String, String>{};
  if (storageRoomId != null) {
    options[_storageRoomFilterKey] = storageRoomId;
  }
  if (storageShelfId != null) {
    options[_storageShelfFilterKey] = storageShelfId;
  }
  if (options.isEmpty) {
    return AppSearchBarFilterValue.empty;
  }
  return AppSearchBarFilterValue(options: options);
}

AppSearchBarFilterValue _drugCatalogFilterValue(PharmacyDrugQuery query) {
  final Map<String, String> options = Map<String, String>.from(
    _catalogStorageFilterValue(
      storageRoomId: query.storageRoomId,
      storageShelfId: query.storageShelfId,
    ).options,
  );
  if (query.stockStatus != null && query.stockStatus!.isNotEmpty) {
    options[_drugStockStatusFilterKey] = query.stockStatus!;
  }
  final Map<String, String> texts = <String, String>{
    if ((query.name ?? '').trim().isNotEmpty) _drugNameFilterKey: query.name!,
    if ((query.code ?? '').trim().isNotEmpty) _drugCodeFilterKey: query.code!,
    if ((query.form ?? '').trim().isNotEmpty) _drugFormFilterKey: query.form!,
    if ((query.strength ?? '').trim().isNotEmpty)
      _drugStrengthFilterKey: query.strength!,
  };
  if (options.isEmpty && texts.isEmpty) {
    return AppSearchBarFilterValue.empty;
  }
  return AppSearchBarFilterValue(options: options, texts: texts);
}

AppSearchBarFilterValue _formularyCatalogFilterValue(
  PharmacyFormularyQuery query,
) {
  final Map<String, String> options = <String, String>{};
  if (query.isActive != null) {
    options[_formularyActiveFilterKey] = query.isActive! ? 'true' : 'false';
  }
  final Map<String, String> texts = <String, String>{
    if ((query.name ?? '').trim().isNotEmpty) _drugNameFilterKey: query.name!,
    if ((query.code ?? '').trim().isNotEmpty) _drugCodeFilterKey: query.code!,
    if ((query.form ?? '').trim().isNotEmpty) _drugFormFilterKey: query.form!,
    if ((query.strength ?? '').trim().isNotEmpty)
      _drugStrengthFilterKey: query.strength!,
  };
  if (options.isEmpty && texts.isEmpty) {
    return AppSearchBarFilterValue.empty;
  }
  return AppSearchBarFilterValue(options: options, texts: texts);
}

AppSearchBarFilterValue _inventoryCatalogFilterValue(
  PharmacyInventoryStockQuery query,
) {
  final Map<String, String> options = Map<String, String>.from(
    _catalogStorageFilterValue(
      storageRoomId: query.storageRoomId,
      storageShelfId: query.storageShelfId,
    ).options,
  );

  final String? stockChoice;
  if (query.expiredOnly) {
    stockChoice = 'EXPIRED';
  } else if (query.expiringWithinDays != null) {
    stockChoice = 'EXPIRING_SOON';
  } else if (query.lowStockOnly) {
    stockChoice = 'LOW_STOCK';
  } else if (query.stockStatus != null && query.stockStatus!.isNotEmpty) {
    stockChoice = query.stockStatus;
  } else {
    stockChoice = null;
  }
  if (stockChoice != null) {
    options[_inventoryStockStatusFilterKey] = stockChoice;
  }
  if (query.pendingStockOnly != null) {
    options[_inventoryPendingFilterKey] =
        query.pendingStockOnly! ? 'true' : 'false';
  }

  final Map<String, String> texts = <String, String>{
    if ((query.itemName ?? '').trim().isNotEmpty)
      _inventoryItemNameFilterKey: query.itemName!,
    if ((query.sku ?? '').trim().isNotEmpty)
      _inventorySkuFilterKey: query.sku!,
    if ((query.facilityName ?? '').trim().isNotEmpty)
      _inventoryFacilityFilterKey: query.facilityName!,
  };

  if (options.isEmpty && texts.isEmpty) {
    return AppSearchBarFilterValue.empty;
  }
  return AppSearchBarFilterValue(options: options, texts: texts);
}

bool _hasDrugCatalogFilters(PharmacyDrugQuery query) {
  return query.storageRoomId != null ||
      query.storageShelfId != null ||
      (query.stockStatus != null && query.stockStatus!.isNotEmpty) ||
      (query.name ?? '').trim().isNotEmpty ||
      (query.code ?? '').trim().isNotEmpty ||
      (query.form ?? '').trim().isNotEmpty ||
      (query.strength ?? '').trim().isNotEmpty;
}

bool _hasFormularyCatalogFilters(PharmacyFormularyQuery query) {
  return query.isActive != null ||
      (query.name ?? '').trim().isNotEmpty ||
      (query.code ?? '').trim().isNotEmpty ||
      (query.form ?? '').trim().isNotEmpty ||
      (query.strength ?? '').trim().isNotEmpty;
}

bool _hasInventoryCatalogFilters(PharmacyInventoryStockQuery query) {
  return query.storageRoomId != null ||
      query.storageShelfId != null ||
      query.lowStockOnly ||
      query.expiredOnly ||
      query.expiringWithinDays != null ||
      (query.stockStatus != null && query.stockStatus!.isNotEmpty) ||
      query.pendingStockOnly != null ||
      (query.itemName ?? '').trim().isNotEmpty ||
      (query.sku ?? '').trim().isNotEmpty ||
      (query.facilityName ?? '').trim().isNotEmpty;
}

Future<void> _applyDrugCatalogFilter(
  PharmacyWorkspaceController controller,
  AppSearchBarFilterValue value,
) async {
  if (!value.isActive) {
    await controller.applyDrugCatalogFilters(clearAll: true);
    return;
  }

  await controller.applyDrugCatalogFilters(
    stockStatus: value.option(_drugStockStatusFilterKey),
    storageRoomId: value.option(_storageRoomFilterKey),
    storageShelfId: value.option(_storageShelfFilterKey),
    name: value.text(_drugNameFilterKey),
    code: value.text(_drugCodeFilterKey),
    form: value.text(_drugFormFilterKey),
    strength: value.text(_drugStrengthFilterKey),
  );
}

Future<void> _applyFormularyCatalogFilter(
  PharmacyWorkspaceController controller,
  AppSearchBarFilterValue value,
) async {
  if (!value.isActive) {
    await controller.clearFormularyFilters();
    return;
  }

  final String? activeChoice = value.option(_formularyActiveFilterKey);
  await controller.applyFormularyCatalogFilters(
    name: value.text(_drugNameFilterKey),
    code: value.text(_drugCodeFilterKey),
    form: value.text(_drugFormFilterKey),
    strength: value.text(_drugStrengthFilterKey),
    isActive: switch (activeChoice) {
      'true' => true,
      'false' => false,
      _ => null,
    },
    clearIsActive: activeChoice == null,
  );
}

bool _matchesFormularyExportFilters(
  PharmacyFormularyItem item,
  AppSearchBarFilterValue filters,
) {
  final String? activeChoice = filters.option(_formularyActiveFilterKey);
  if (activeChoice == 'true' && !item.isActive) {
    return false;
  }
  if (activeChoice == 'false' && item.isActive) {
    return false;
  }

  bool containsText(String? haystack, String? needle) {
    final String query = (needle ?? '').trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    return (haystack ?? '').toLowerCase().contains(query);
  }

  return containsText(item.drugNameLabel, filters.text(_drugNameFilterKey)) &&
      containsText(item.drugCode, filters.text(_drugCodeFilterKey)) &&
      containsText(item.drugForm, filters.text(_drugFormFilterKey)) &&
      containsText(item.drugStrength, filters.text(_drugStrengthFilterKey));
}

Future<void> _applyInventoryCatalogFilter(
  PharmacyWorkspaceController controller,
  AppSearchBarFilterValue value,
) async {
  if (!value.isActive) {
    await controller.applyInventoryCatalogFilters(clearAll: true);
    return;
  }

  final String? pendingChoice = value.option(_inventoryPendingFilterKey);
  await controller.applyInventoryCatalogFilters(
    stockStatusChoice: value.option(_inventoryStockStatusFilterKey),
    storageRoomId: value.option(_storageRoomFilterKey),
    storageShelfId: value.option(_storageShelfFilterKey),
    itemName: value.text(_inventoryItemNameFilterKey),
    sku: value.text(_inventorySkuFilterKey),
    facilityName: value.text(_inventoryFacilityFilterKey),
    pendingStockOnly: switch (pendingChoice) {
      'true' => true,
      'false' => false,
      _ => null,
    },
    clearPendingStockOnly: pendingChoice == null,
  );
}

bool _matchesInventoryExportFilters(
  PharmacyInventoryStock item,
  AppSearchBarFilterValue filters,
) {
  bool containsText(String? haystack, String? needle) {
    final String query = (needle ?? '').trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    return (haystack ?? '').toLowerCase().contains(query);
  }

  if (!containsText(
    item.inventoryItem?.name ?? item.inventoryItem?.displayTitle,
    filters.text(_inventoryItemNameFilterKey),
  )) {
    return false;
  }
  if (!containsText(item.inventoryItem?.sku, filters.text(_inventorySkuFilterKey))) {
    return false;
  }
  if (!containsText(
    item.facilityName,
    filters.text(_inventoryFacilityFilterKey),
  )) {
    return false;
  }

  final String? pendingChoice = filters.option(_inventoryPendingFilterKey);
  if (pendingChoice == 'true' && !item.pendingStock) {
    return false;
  }
  if (pendingChoice == 'false' && item.pendingStock) {
    return false;
  }

  final String? roomId = filters.option(_storageRoomFilterKey);
  if (roomId != null && roomId.isNotEmpty && item.storageRoomId != roomId) {
    return false;
  }
  final String? shelfId = filters.option(_storageShelfFilterKey);
  if (shelfId != null &&
      shelfId.isNotEmpty &&
      item.storageShelfId != shelfId) {
    return false;
  }

  final String? stockChoice = filters.option(_inventoryStockStatusFilterKey);
  if (stockChoice == null || stockChoice.isEmpty) {
    return true;
  }
  final String status = (item.stockStatus ?? '').toUpperCase();
  return switch (stockChoice) {
    'EXPIRED' => item.expiryAlertStatus == 'EXPIRED',
    'EXPIRING_SOON' => item.expiryAlertStatus == 'EXPIRING_SOON',
    'LOW_STOCK' => status == 'LOW_STOCK' || item.lowStock,
    'OUT_OF_STOCK' => status == 'OUT_OF_STOCK',
    'ALMOST_OUT_OF_STOCK' => status == 'ALMOST_OUT_OF_STOCK',
    'IN_STOCK' => status == 'IN_STOCK',
    _ => true,
  };
}

extension _CatalogAccessRequirement on AccessRequirement {
  bool allows(WidgetRef ref) {
    return isAllowed(ref.read(appAccessPolicyProvider));
  }
}

Future<void> _printPharmacyDrugsList(
  BuildContext context,
  WidgetRef ref, {
  required AppLocalizations l10n,
  required List<PharmacyDrug> drugs,
}) {
  return printPharmacyWorkspaceList(
    ref: ref,
    context: context,
    title: l10n.pharmacyCatalogTabDrugs,
    columns: <PharmacyWorkspacePrintColumn>[
      PharmacyWorkspacePrintColumn(id: 'code', label: l10n.pharmacyDrugCodeLabel),
      PharmacyWorkspacePrintColumn(
        id: 'generic_name',
        label: l10n.pharmacyDrugGenericNameLabel,
      ),
      PharmacyWorkspacePrintColumn(
        id: 'brand_name',
        label: l10n.pharmacyDrugBrandNameLabel,
      ),
      PharmacyWorkspacePrintColumn(id: 'form', label: l10n.pharmacyDrugFormLabel),
      PharmacyWorkspacePrintColumn(
        id: 'strength',
        label: l10n.pharmacyDrugStrengthLabel,
      ),
    ],
    rows: <Map<String, String>>[
      for (final PharmacyDrug item in drugs)
        <String, String>{
          'code': item.code ?? '',
          'generic_name': (item.genericName ?? '').trim().isNotEmpty
              ? item.genericName!.trim()
              : (item.name ?? ''),
          'brand_name': item.brandName ?? '',
          'form': item.form ?? '',
          'strength': item.strength ?? '',
        },
    ],
    emptyText: l10n.pharmacyNoDrugsTitle,
  );
}

Future<void> _printPharmacyFormularyList(
  BuildContext context,
  WidgetRef ref, {
  required AppLocalizations l10n,
  required List<PharmacyFormularyItem> items,
}) {
  return printPharmacyWorkspaceList(
    ref: ref,
    context: context,
    title: l10n.pharmacyCatalogTabFormulary,
    columns: <PharmacyWorkspacePrintColumn>[
      PharmacyWorkspacePrintColumn(
        id: 'drug',
        label: l10n.pharmacyFormularyDrugLabel,
      ),
      PharmacyWorkspacePrintColumn(id: 'code', label: l10n.pharmacyDrugCodeLabel),
      PharmacyWorkspacePrintColumn(id: 'form', label: l10n.pharmacyDrugFormLabel),
      PharmacyWorkspacePrintColumn(
        id: 'strength',
        label: l10n.pharmacyDrugStrengthLabel,
      ),
    ],
    rows: <Map<String, String>>[
      for (final PharmacyFormularyItem item in items)
        <String, String>{
          'drug': item.drugNameLabel ?? '',
          'code': item.drugCode ?? '',
          'form': item.drugForm ?? '',
          'strength': item.drugStrength ?? '',
        },
    ],
    emptyText: l10n.pharmacyNoFormularyTitle,
  );
}

Future<void> _printPharmacyInventoryList(
  BuildContext context,
  WidgetRef ref, {
  required AppLocalizations l10n,
  required List<PharmacyInventoryStock> stocks,
}) {
  return printPharmacyWorkspaceList(
    ref: ref,
    context: context,
    title: l10n.pharmacyCatalogTabInventory,
    columns: <PharmacyWorkspacePrintColumn>[
      PharmacyWorkspacePrintColumn(
        id: 'item',
        label: l10n.pharmacyInventoryItemLabel,
      ),
      PharmacyWorkspacePrintColumn(
        id: 'sku',
        label: l10n.pharmacyInventorySkuColumnLabel,
      ),
      PharmacyWorkspacePrintColumn(
        id: 'quantity',
        label: l10n.pharmacyInventoryQuantityColumnLabel,
      ),
      PharmacyWorkspacePrintColumn(
        id: 'status',
        label: l10n.pharmacyStockStatusFilterLabel,
      ),
    ],
    rows: <Map<String, String>>[
      for (final PharmacyInventoryStock item in stocks)
        <String, String>{
          'item': item.inventoryItem?.displayTitle ?? item.displayId ?? item.id,
          'sku': item.inventoryItem?.sku ?? '',
          'quantity': '${item.quantity}',
          'status': item.stockStatus ?? '',
        },
    ],
    emptyText: l10n.pharmacyNoInventoryTitle,
  );
}

Future<void> _printPharmacyStorageRoomsList(
  BuildContext context,
  WidgetRef ref, {
  required AppLocalizations l10n,
  required List<PharmacyStorageRoom> rooms,
}) {
  return printPharmacyWorkspaceList(
    ref: ref,
    context: context,
    title: l10n.pharmacyCatalogTabStorage,
    columns: <PharmacyWorkspacePrintColumn>[
      PharmacyWorkspacePrintColumn(
        id: 'name',
        label: l10n.pharmacyStorageRoomNameLabel,
      ),
      PharmacyWorkspacePrintColumn(
        id: 'code',
        label: l10n.pharmacyStorageRoomCodeLabel,
      ),
      PharmacyWorkspacePrintColumn(
        id: 'status',
        label: l10n.pharmacyStorageStatusColumnLabel,
      ),
    ],
    rows: <Map<String, String>>[
      for (final PharmacyStorageRoom item in rooms)
        <String, String>{
          'name': item.name ?? '',
          'code': item.code ?? '',
          'status': item.isSoftDeleted
              ? l10n.pharmacyStorageDeletedLabel
              : (item.isActive
                    ? l10n.pharmacyStorageActiveLabel
                    : l10n.pharmacyStorageInactiveLabel),
        },
    ],
    emptyText: l10n.pharmacyNoStorageRoomsTitle,
  );
}

Future<void> _printPharmacyShelvesList(
  BuildContext context,
  WidgetRef ref, {
  required AppLocalizations l10n,
  required List<_ShelfRow> shelves,
}) {
  return printPharmacyWorkspaceList(
    ref: ref,
    context: context,
    title: l10n.pharmacyCatalogTabShelves,
    columns: <PharmacyWorkspacePrintColumn>[
      PharmacyWorkspacePrintColumn(
        id: 'shelf',
        label: l10n.pharmacyStorageShelfLabel,
      ),
      PharmacyWorkspacePrintColumn(
        id: 'room',
        label: l10n.pharmacyStorageRoomNameLabel,
      ),
      PharmacyWorkspacePrintColumn(
        id: 'code',
        label: l10n.pharmacyStorageShelfCodeLabel,
      ),
    ],
    rows: <Map<String, String>>[
      for (final _ShelfRow row in shelves)
        <String, String>{
          'shelf': row.shelf.displayLabel,
          'room': row.room.name ?? '',
          'code': row.shelf.shelfCode ?? '',
        },
    ],
    emptyText: l10n.pharmacyNoStorageShelvesTitle,
  );
}
