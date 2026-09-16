import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hosspi_hms/app/theme/app_theme.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/features/lab/domain/entities/lab_entities.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/shared/components/components.dart';
import 'package:hosspi_hms/shared/lab_catalog/lab_catalog_dialogs.dart';

const LabCatalogItem _availableTest = LabCatalogItem(
  id: 'LBT0000001',
  type: LabCatalogItemType.test,
  name: 'Complete blood count',
  code: 'CBC',
  category: 'Hematology',
);

const LabCatalogItem _availablePanel = LabCatalogItem(
  id: 'LBP0000001',
  type: LabCatalogItemType.panel,
  name: 'Metabolic panel',
  code: 'CMP',
  category: 'Chemistry',
  unitPrice: 102000,
);

const LabCatalogItem _alreadyOfferedTest = LabCatalogItem(
  id: 'LBT0000002',
  type: LabCatalogItemType.test,
  name: 'Lipid panel',
  code: 'LIP',
  category: 'Chemistry',
  isOfferedAtFacility: true,
);

const LabCatalogItem _duplicateTestA = LabCatalogItem(
  id: 'LBT0000099',
  displayId: 'DUP-001',
  type: LabCatalogItemType.test,
  name: 'Duplicate glucan A',
  code: 'GLU-A',
  category: 'CHEMISTRY',
);

const LabCatalogItem _duplicateTestB = LabCatalogItem(
  id: 'LBT0000099-copy',
  displayId: 'DUP-001',
  type: LabCatalogItemType.test,
  name: 'Duplicate glucan B',
  code: 'GLU-B',
  category: 'CHEMISTRY',
);

void main() {
  group('LabEnableFacilityOfferingDialog', () {
    testWidgets('catalog footer is Back, Next, Close with disabled Next', (
      WidgetTester tester,
    ) async {
      await _pumpEnableDialog(tester, showBackAction: true);

      expect(find.text('ENABLE LAB TESTS AND PANELS'), findsOneWidget);

      final Finder nextButton = find.widgetWithText(AppButton, 'Next');
      expect(nextButton, findsOneWidget);
      expect(
        find.widgetWithIcon(AppButton, Icons.arrow_back_outlined),
        findsWidgets,
      );
      expect(find.widgetWithIcon(AppButton, Icons.close), findsWidgets);
      expect(
        find.byTooltip('Select at least one test or panel.'),
        findsOneWidget,
      );

      final AppButton next = tester.widget<AppButton>(nextButton);
      expect(next.enabled, isFalse);
      expect(next.onPressed, isNull);
    });

    testWidgets('shows Available and Configured status values', (
      WidgetTester tester,
    ) async {
      await _pumpEnableDialog(
        tester,
        kind: LabEnableOfferingKind.all,
        items: const <LabCatalogItem>[
          _availableTest,
          _alreadyOfferedTest,
          _availablePanel,
        ],
      );

      expect(find.text('Complete blood count'), findsWidgets);
      expect(find.text('Metabolic panel'), findsWidgets);
      expect(find.text('Lipid panel'), findsWidgets);
      expect(find.text('Available'), findsWidgets);
      expect(find.text('Configured'), findsWidgets);

      // Select-all only covers available rows.
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      expect(find.widgetWithText(AppButton, 'Next (2)'), findsOneWidget);

      // Offered row tap must not change selection.
      await tester.tap(find.text('Lipid panel').first);
      await tester.pump();
      expect(find.widgetWithText(AppButton, 'Next (2)'), findsOneWidget);

      final List<Checkbox> checkboxes = tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .toList(growable: false);
      expect(
        checkboxes.where((Checkbox box) => box.onChanged == null),
        isNotEmpty,
      );
    });

    testWidgets('status advanced filter keeps only Configured rows', (
      WidgetTester tester,
    ) async {
      await _pumpEnableDialog(
        tester,
        kind: LabEnableOfferingKind.all,
        items: const <LabCatalogItem>[
          _availableTest,
          _alreadyOfferedTest,
          _availablePanel,
        ],
      );

      await tester.tap(find.text('Laboratory filters'));
      await tester.pumpAndSettle();

      // The filter panel's heading names the group; the field itself carries
      // that name only for assistive tech.
      final Finder statusField = find.byWidgetPredicate(
        (Widget widget) =>
            widget is AppSelectField<String> && widget.semanticLabel == 'Status',
      );
      expect(statusField, findsOneWidget);
      tester
          .widget<AppSelectField<String>>(statusField)
          .onChanged
          ?.call('configured');
      await tester.pump();
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();

      expect(find.text('Lipid panel'), findsWidgets);
      expect(find.text('Configured'), findsWidgets);
      expect(find.text('Complete blood count'), findsNothing);
      expect(find.text('Metabolic panel'), findsNothing);
    });

    testWidgets('configured filter shows offered items missing from platform page', (
      WidgetTester tester,
    ) async {
      // Simulates merge result: platform page had no overlap, offered row appended.
      await _pumpEnableDialog(
        tester,
        kind: LabEnableOfferingKind.all,
        items: const <LabCatalogItem>[
          _availableTest,
          LabCatalogItem(
            id: 'LBP0000099',
            type: LabCatalogItemType.panel,
            name: 'Facility only panel',
            code: 'FOP',
            category: 'Chemistry',
            isOfferedAtFacility: true,
          ),
        ],
      );

      await tester.tap(find.text('Laboratory filters'));
      await tester.pumpAndSettle();
      // The filter panel's heading names the group; the field itself carries
      // that name only for assistive tech.
      final Finder statusField = find.byWidgetPredicate(
        (Widget widget) =>
            widget is AppSelectField<String> && widget.semanticLabel == 'Status',
      );
      tester
          .widget<AppSelectField<String>>(statusField)
          .onChanged
          ?.call('configured');
      await tester.pump();
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();

      expect(find.text('Facility only panel'), findsWidgets);
      expect(find.text('Configured'), findsWidgets);
      expect(find.text('Complete blood count'), findsNothing);
      expect(find.text('All platform items are already offered at this facility.'), findsNothing);
      expect(find.text('No matching lab catalog items'), findsNothing);
    });

    testWidgets('select-all excludes already offered rows', (
      WidgetTester tester,
    ) async {
      await _pumpEnableDialog(
        tester,
        kind: LabEnableOfferingKind.all,
        items: const <LabCatalogItem>[
          _availableTest,
          _alreadyOfferedTest,
          _availablePanel,
        ],
      );

      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      expect(find.widgetWithText(AppButton, 'Next (2)'), findsOneWidget);
      expect(find.text('Configured'), findsWidgets);
    });

    testWidgets('all kind lists tests and panels', (WidgetTester tester) async {
      await _pumpEnableDialog(
        tester,
        kind: LabEnableOfferingKind.all,
        items: const <LabCatalogItem>[_availableTest, _availablePanel],
      );

      expect(find.text('Complete blood count'), findsWidgets);
      expect(find.text('Metabolic panel'), findsWidgets);
      expect(find.text('ENABLE LAB TESTS AND PANELS'), findsOneWidget);
    });

    testWidgets('header checkbox selects and clears listed rows', (
      WidgetTester tester,
    ) async {
      await _pumpEnableDialog(
        tester,
        kind: LabEnableOfferingKind.all,
        items: const <LabCatalogItem>[_availableTest, _availablePanel],
      );

      expect(find.text('Select all'), findsNothing);
      expect(find.text('Clear selection'), findsNothing);

      final Finder headerCheckbox = find.byType(Checkbox).first;
      await tester.tap(headerCheckbox);
      await tester.pump();

      final AppButton nextAfterSelect = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Next (2)'),
      );
      expect(nextAfterSelect.enabled, isTrue);

      await tester.tap(headerCheckbox);
      await tester.pump();

      final AppButton nextAfterClear = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Next'),
      );
      expect(nextAfterClear.enabled, isFalse);
      expect(find.textContaining('of'), findsNothing);
    });

    testWidgets('dedupes catalog rows that share type and apiId', (
      WidgetTester tester,
    ) async {
      await _pumpEnableDialog(
        tester,
        kind: LabEnableOfferingKind.all,
        items: const <LabCatalogItem>[
          _duplicateTestA,
          _duplicateTestB,
          _availablePanel,
        ],
      );

      expect(find.text('Duplicate glucan A'), findsWidgets);
      expect(find.text('Duplicate glucan B'), findsNothing);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      await tester.tap(_nextButton());
      await tester.pumpAndSettle();

      expect(find.byType(AppCurrencyAmountField), findsNWidgets(2));
    });

    testWidgets('does not prefill panel prices from catalog defaults', (
      WidgetTester tester,
    ) async {
      await _pumpEnableDialog(
        tester,
        kind: LabEnableOfferingKind.panel,
        items: const <LabCatalogItem>[_availablePanel],
      );

      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pumpAndSettle();
      await tester.tap(_nextButton());
      await tester.pumpAndSettle();

      expect(find.text('SET FACILITY PRICES'), findsOneWidget);
      final Finder amountFields = find.descendant(
        of: find.byType(AppCurrencyAmountField),
        matching: find.byType(EditableText),
      );
      expect(amountFields, findsOneWidget);
      expect(
        tester.widget<EditableText>(amountFields).controller?.text ?? '',
        isEmpty,
      );
    });

    testWidgets('prefills test prices from catalog with thousand separators', (
      WidgetTester tester,
    ) async {
      await _pumpEnableDialog(
        tester,
        kind: LabEnableOfferingKind.test,
        items: const <LabCatalogItem>[
          LabCatalogItem(
            id: 'LBT0000091',
            type: LabCatalogItemType.test,
            name: 'Glucose',
            code: 'GLU',
            category: 'CHEMISTRY',
            unitPrice: 18000,
          ),
        ],
      );

      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pumpAndSettle();
      await tester.tap(_nextButton());
      await tester.pumpAndSettle();

      final Finder amountFields = find.descendant(
        of: find.byType(AppCurrencyAmountField),
        matching: find.byType(EditableText),
      );
      expect(amountFields, findsOneWidget);
      expect(
        tester.widget<EditableText>(amountFields).controller?.text,
        '18,000',
      );
    });

    testWidgets('price step can remove an item from the batch', (
      WidgetTester tester,
    ) async {
      await _pumpEnableDialog(
        tester,
        kind: LabEnableOfferingKind.all,
        items: const <LabCatalogItem>[_availableTest, _availablePanel],
      );

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      await tester.tap(_nextButton());
      await tester.pumpAndSettle();

      expect(find.text('SET FACILITY PRICES'), findsOneWidget);
      expect(find.byType(AppCurrencyAmountField), findsNWidgets(2));
      expect(find.text('Complete blood count'), findsWidgets);
      expect(find.text('Metabolic panel'), findsWidgets);

      await tester.tap(find.byTooltip('Remove').first);
      await tester.pumpAndSettle();

      expect(find.byType(AppCurrencyAmountField), findsOneWidget);
      expect(find.text('2 items selected. Set a unit price for each item.'),
          findsNothing);
      expect(find.text('1 item selected. Set a unit price for each item.'),
          findsOneWidget);
    });

    testWidgets('price fields stay independent across selected items', (
      WidgetTester tester,
    ) async {
      await _pumpEnableDialog(
        tester,
        kind: LabEnableOfferingKind.all,
        items: const <LabCatalogItem>[_availableTest, _availablePanel],
      );

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      await tester.tap(_nextButton());
      await tester.pumpAndSettle();

      final Finder amountFields = find.descendant(
        of: find.byType(AppCurrencyAmountField),
        matching: find.byType(EditableText),
      );
      expect(amountFields, findsNWidgets(2));
      await tester.enterText(amountFields.at(0), '1000');
      await tester.enterText(amountFields.at(1), '2500');
      await tester.pump();

      final String firstAmount =
          tester.widget<EditableText>(amountFields.at(0)).controller?.text ??
          '';
      final String secondAmount =
          tester.widget<EditableText>(amountFields.at(1)).controller?.text ??
          '';
      expect(firstAmount.replaceAll(',', ''), '1000');
      expect(secondAmount.replaceAll(',', ''), '2500');
      expect(firstAmount, isNot(equals(secondAmount)));
    });

    testWidgets('selection goes to batch price then preview then enable', (
      WidgetTester tester,
    ) async {
      final List<Map<String, Object?>> enables = <Map<String, Object?>>[];
      await _pumpEnableDialog(
        tester,
        kind: LabEnableOfferingKind.all,
        items: const <LabCatalogItem>[_availableTest, _availablePanel],
        onEnable: (LabCatalogItem item, Map<String, Object?> payload) async {
          enables.add(payload);
          return null;
        },
      );

      await tester.tap(find.byType(Checkbox).at(1));
      await tester.tap(find.byType(Checkbox).at(2));
      await tester.pump();
      await tester.tap(_nextButton());
      await tester.pumpAndSettle();

      expect(find.text('SET FACILITY PRICES'), findsOneWidget);
      expect(find.byType(AppCurrencyAmountField), findsNWidgets(2));

      final Finder amountFields = find.descendant(
        of: find.byType(AppCurrencyAmountField),
        matching: find.byType(EditableText),
      );
      expect(amountFields, findsNWidgets(2));
      await tester.enterText(amountFields.at(0), '1000');
      await tester.enterText(amountFields.at(1), '2500');
      await tester.pumpAndSettle();

      await tester.tap(_nextButton());
      await tester.pumpAndSettle();

      expect(find.text('REVIEW SELECTION'), findsOneWidget);
      expect(find.text('Complete blood count'), findsWidgets);
      expect(find.text('Metabolic panel'), findsWidgets);
      expect(find.text('Unit price'), findsWidgets);
      expect(find.textContaining('1,000'), findsWidgets);
      expect(find.textContaining('2,500'), findsWidgets);

      await tester.tap(find.text('Enable selected').first);
      await tester.pumpAndSettle();

      expect(enables, hasLength(2));
      expect(
        enables.map((Map<String, Object?> p) => p['unit_price']),
        containsAll(<Object?>[1000, 2500]),
      );

      // Dialog stays open; enabled rows are marked Configured and locked.
      expect(find.text('ENABLE LAB TESTS AND PANELS'), findsOneWidget);
      expect(find.text('Configured'), findsNWidgets(2));
      expect(find.widgetWithText(AppButton, 'Next'), findsOneWidget);
      final AppButton next = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Next'),
      );
      expect(next.enabled, isFalse);
    });

    testWidgets('post-enable rows stay non-selectable in session', (
      WidgetTester tester,
    ) async {
      await _pumpEnableDialog(
        tester,
        kind: LabEnableOfferingKind.all,
        items: const <LabCatalogItem>[_availableTest, _availablePanel],
      );

      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();
      await tester.tap(_nextButton());
      await tester.pumpAndSettle();

      final Finder amountFields = find.descendant(
        of: find.byType(AppCurrencyAmountField),
        matching: find.byType(EditableText),
      );
      await tester.enterText(amountFields.first, '1500');
      await tester.pumpAndSettle();
      await tester.tap(_nextButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enable selected').first);
      await tester.pumpAndSettle();

      expect(find.text('Configured'), findsOneWidget);
      expect(find.text('Complete blood count'), findsWidgets);
      expect(find.text('Metabolic panel'), findsWidgets);

      await tester.tap(find.text('Complete blood count').first);
      await tester.pump();
      expect(find.widgetWithText(AppButton, 'Next'), findsOneWidget);

      // Remaining available panel can still be selected.
      await tester.tap(find.text('Metabolic panel').first);
      await tester.pump();
      expect(find.widgetWithText(AppButton, 'Next (1)'), findsOneWidget);
    });

    testWidgets('preview allows deselect and back to batch price', (
      WidgetTester tester,
    ) async {
      await _pumpEnableDialog(
        tester,
        kind: LabEnableOfferingKind.all,
        items: const <LabCatalogItem>[_availableTest, _availablePanel],
      );

      await tester.tap(find.byType(Checkbox).at(1));
      await tester.tap(find.byType(Checkbox).at(2));
      await tester.pump();
      await tester.tap(_nextButton());
      await tester.pumpAndSettle();

      final Finder amountFields = find.descendant(
        of: find.byType(AppCurrencyAmountField),
        matching: find.byType(EditableText),
      );
      await tester.enterText(amountFields.at(0), '1000');
      await tester.enterText(amountFields.at(1), '2500');
      await tester.pumpAndSettle();
      await tester.tap(_nextButton());
      await tester.pumpAndSettle();

      expect(find.text('REVIEW SELECTION'), findsOneWidget);
      expect(find.byType(Checkbox), findsNWidgets(2));

      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithIcon(AppButton, Icons.arrow_back_outlined));
      await tester.pumpAndSettle();

      expect(find.text('SET FACILITY PRICES'), findsOneWidget);
    });
  });
}

Finder _nextButton() => find.byWidgetPredicate(
  (Widget widget) =>
      widget is AppButton && widget.label.trim().startsWith('Next'),
);

Future<void> _pumpEnableDialog(
  WidgetTester tester, {
  LabEnableOfferingKind kind = LabEnableOfferingKind.test,
  bool showBackAction = false,
  List<LabCatalogItem> items = const <LabCatalogItem>[_availableTest],
  Future<AppFailure?> Function(
    LabCatalogItem item,
    Map<String, Object?> payload,
  )?
  onEnable,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: LabEnableFacilityOfferingDialog(
            kind: kind,
            showBackAction: showBackAction,
            scope: const LabCatalogScope(
              tenantId: 'TEN0000001',
              facilityId: 'FAC0000001',
            ),
            onSearchCatalog:
                ({
                  required LabEnableOfferingKind kind,
                  required LabCatalogScope scope,
                  String? query,
                  int limit = 100,
                }) async {
                  return Result<List<LabCatalogItem>>.success(items);
                },
            onEnable:
                onEnable ??
                (LabCatalogItem item, Map<String, Object?> payload) async {
                  return null;
                },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
