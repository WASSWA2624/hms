import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/components/components.dart';
import 'package:hosspi_hms/shared/printing/printing.dart';

/// Column choice for Setup workspace list print (aligned with exportable fields).
final class TenantFacilitySetupPrintColumn {
  const TenantFacilitySetupPrintColumn({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}

final class TenantFacilitySetupPrintOptionsController extends ChangeNotifier {
  TenantFacilitySetupPrintOptionsController({
    required List<TenantFacilitySetupPrintColumn> columns,
  }) : _columns = List<TenantFacilitySetupPrintColumn>.unmodifiable(columns) {
    _selectedColumnIds =
        columns.map((TenantFacilitySetupPrintColumn c) => c.id).toSet();
    _includeSummary = true;
    _includeRows = true;
  }

  final List<TenantFacilitySetupPrintColumn> _columns;
  late Set<String> _selectedColumnIds;
  late bool _includeSummary;
  late bool _includeRows;

  List<TenantFacilitySetupPrintColumn> get columns => _columns;

  Set<String> get selectedColumnIds =>
      Set<String>.unmodifiable(_selectedColumnIds);

  bool get includeSummary => _includeSummary;

  bool get includeRows => _includeRows;

  bool get canPrint =>
      (_includeSummary || _includeRows) &&
      (!_includeRows || _selectedColumnIds.isNotEmpty);

  void setIncludeSummary(bool value) {
    if (_includeSummary == value) {
      return;
    }
    _includeSummary = value;
    notifyListeners();
  }

  void setIncludeRows(bool value) {
    if (_includeRows == value) {
      return;
    }
    _includeRows = value;
    notifyListeners();
  }

  void setSelectedColumns(Set<String> selected) {
    final Set<String> next = selected
        .where(
          (String id) =>
              _columns.any((TenantFacilitySetupPrintColumn c) => c.id == id),
        )
        .toSet();
    if (setEquals(next, _selectedColumnIds)) {
      return;
    }
    _selectedColumnIds = next;
    notifyListeners();
  }
}

/// Preview-first worklist print for Setup queue tables.
Future<void> printTenantFacilitySetupList({
  required WidgetRef ref,
  required BuildContext context,
  required String title,
  required List<TenantFacilitySetupPrintColumn> columns,
  required List<Map<String, String>> rows,
  required String emptyText,
}) async {
  final AppLocalizations l10n = context.l10n;
  final TenantFacilitySetupPrintOptionsController options =
      TenantFacilitySetupPrintOptionsController(columns: columns);

  String buildBodyHtml() {
    return tenantFacilitySetupListHtml(
      l10n: l10n,
      rows: rows,
      options: options,
      emptyText: emptyText,
    );
  }

  try {
    await PrintDocumentTemplates.registry(
      ref: ref,
      context: context,
      title: title,
      previewDialogTitle: l10n.printPreviewTitle,
      subtitle: options.includeSummary
          ? l10n.commonPrintRowCountLabel(rows.length)
          : null,
      recordReference: PrintFormContextReference(
        label: title,
        value: l10n.commonPrintRowCountLabel(rows.length),
      ),
      bodyHtml: buildBodyHtml(),
      bodyHtmlBuilder: buildBodyHtml,
      previewSectionsExtra: TenantFacilitySetupPrintOptionsSection(
        controller: options,
      ),
      previewDocumentRevision: options,
      isPrintEnabled: () => options.canPrint,
    );
  } finally {
    options.dispose();
  }
}

/// Maps [AppListTable] exportable columns + rows into Setup list print.
Future<void> printTenantFacilitySetupListTable<T>({
  required WidgetRef ref,
  required BuildContext context,
  required String title,
  required List<AppListTableColumn<T>> columns,
  required List<T> items,
  required String emptyText,
}) async {
  final List<AppListTableColumn<T>> exportColumns = columns
      .where((AppListTableColumn<T> column) => column.includesInExport)
      .toList(growable: false);
  final List<TenantFacilitySetupPrintColumn> printColumns =
      <TenantFacilitySetupPrintColumn>[
        for (final AppListTableColumn<T> column in exportColumns)
          TenantFacilitySetupPrintColumn(id: column.key, label: column.label),
      ];
  final List<Map<String, String>> printRows = <Map<String, String>>[
    for (final T item in items)
      <String, String>{
        for (final AppListTableColumn<T> column in exportColumns)
          column.key:
              resolveAppListTableExportValue(
                column: column,
                item: item,
                context: context,
              )?.toString() ??
              '',
      },
  ];
  await printTenantFacilitySetupList(
    ref: ref,
    context: context,
    title: title,
    columns: printColumns,
    rows: printRows,
    emptyText: emptyText,
  );
}

String tenantFacilitySetupListHtml({
  required AppLocalizations l10n,
  required List<Map<String, String>> rows,
  required TenantFacilitySetupPrintOptionsController options,
  required String emptyText,
}) {
  final StringBuffer buffer = StringBuffer();

  if (options.includeSummary) {
    buffer.write(
      PrintFormTemplate.section(
        title: l10n.commonPrintSummarySectionLabel,
        bodyHtml:
            '<p>${PrintFormTemplate.escape(l10n.commonPrintRowCountLabel(rows.length))}</p>',
      ),
    );
  }

  if (options.includeRows) {
    final List<TenantFacilitySetupPrintColumn> selected = options.columns
        .where(
          (TenantFacilitySetupPrintColumn column) =>
              options.selectedColumnIds.contains(column.id),
        )
        .toList(growable: false);
    final List<List<String>> tableRows = <List<String>>[
      for (final Map<String, String> row in rows)
        <String>[
          for (final TenantFacilitySetupPrintColumn column in selected)
            row[column.id] ?? '',
        ],
    ];
    buffer.write(
      PrintFormTemplate.section(
        title: l10n.commonPrintRowsSectionLabel,
        bodyHtml: PrintFormTemplate.table(
          headers: <String>[
            for (final TenantFacilitySetupPrintColumn column in selected)
              column.label,
          ],
          rows: tableRows,
          emptyText: emptyText,
        ),
      ),
    );
  }

  return buffer.toString();
}

class TenantFacilitySetupPrintOptionsSection extends StatelessWidget {
  const TenantFacilitySetupPrintOptionsSection({
    required this.controller,
    super.key,
  });

  final TenantFacilitySetupPrintOptionsController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = context.l10n;

    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        return AppCollapsibleSection(
          title: l10n.commonPrintSectionsLabel,
          titleIcon: Icons.print_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppReportSectionPicker(
                compact: true,
                sections: <AppReportSectionData>[
                  AppReportSectionData(
                    id: 'summary',
                    title: l10n.commonPrintSummarySectionLabel,
                    icon: Icons.summarize_outlined,
                  ),
                  AppReportSectionData(
                    id: 'rows',
                    title: l10n.commonPrintRowsSectionLabel,
                    icon: Icons.list_alt_outlined,
                  ),
                ],
                selectedIds: <Object>{
                  if (controller.includeSummary) 'summary',
                  if (controller.includeRows) 'rows',
                },
                onSelectionChanged: (Set<Object> selected) {
                  controller.setIncludeSummary(selected.contains('summary'));
                  controller.setIncludeRows(selected.contains('rows'));
                },
              ),
              SizedBox(height: theme.spacing.xs),
              if (controller.includeRows)
                AppReportSectionPicker(
                  compact: true,
                  sections: <AppReportSectionData>[
                    for (final TenantFacilitySetupPrintColumn column
                        in controller.columns)
                      AppReportSectionData(
                        id: column.id,
                        title: column.label,
                        icon: Icons.view_column_outlined,
                      ),
                  ],
                  selectedIds: controller.selectedColumnIds,
                  onSelectionChanged: (Set<Object> selected) {
                    controller.setSelectedColumns(
                      selected.map((Object id) => id.toString()).toSet(),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
