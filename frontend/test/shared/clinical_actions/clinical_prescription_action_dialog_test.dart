import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hosspi_hms/app/theme/app_theme.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/shared/clinical_actions/clinical_actions.dart';
import 'package:hosspi_hms/shared/components/components.dart';

void main() {
  group('ClinicalPrescriptionActionDialog', () {
    testWidgets('hides review billing when enableBilling is false', (
      WidgetTester tester,
    ) async {
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
              body: ClinicalPrescriptionActionDialog(
                enableBilling: false,
                dialogTitle: 'Create order',
                submitLabel: 'Create order',
                referenceData: const ClinicalActionReferenceData(
                  drugs: <ClinicalActionCatalogOption>[
                    ClinicalActionCatalogOption(
                      id: 'amox',
                      name: 'Amoxicillin',
                      code: 'AMOX',
                    ),
                  ],
                ),
                onSubmit:
                    ({
                      required List<Map<String, Object?>> items,
                      ClinicalRequestBillingSubmit? billing,
                    }) async {
                      return null;
                    },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Create order'), findsWidgets);
      expect(find.text('Review billing'), findsNothing);
      expect(find.text('Add medicine'), findsWidgets);
      expect(find.text('No medicines added yet'), findsOneWidget);
    });

    testWidgets('hides help copy and payment mode controls', (
      WidgetTester tester,
    ) async {
      await _pumpPrescribeDialog(tester);

      expect(
        find.text(
          'Review selection, add catalog items, then confirm billing.',
        ),
        findsNothing,
      );
      expect(find.text('Bill on dispense'), findsNothing);
      expect(find.text('Pay at prescribe'), findsNothing);
      expect(find.text('Build prescription'), findsNothing);
      expect(find.text('No medicines added yet'), findsOneWidget);
    });

    testWidgets('shows table search actions for prescribe workflow', (
      WidgetTester tester,
    ) async {
      await _pumpPrescribeDialog(tester);

      expect(find.byType(AppSearchBar), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget.runtimeType.toString().startsWith('AppListTable'),
        ),
        findsOneWidget,
      );
      expect(find.text('Filters'), findsWidgets);
      expect(find.text('Settings'), findsWidgets);
      expect(find.text('Add medicine'), findsWidgets);
      expect(find.text('Review billing'), findsWidgets);
      expect(find.text('Remove selected'), findsWidgets);
      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Prescribe'), findsWidgets);
    });

    testWidgets('review billing is disabled when no medicines are listed', (
      WidgetTester tester,
    ) async {
      await _pumpPrescribeDialog(tester);

      final Finder reviewBilling = find.text('Review billing');
      expect(reviewBilling, findsWidgets);
      await tester.tap(reviewBilling.first);
      await tester.pumpAndSettle();

      expect(find.text('Request billing'), findsNothing);
    });

    testWidgets('add medicine opens catalog table picker', (
      WidgetTester tester,
    ) async {
      await _pumpPrescribeDialog(tester);

      await tester.tap(find.text('Add medicine').first);
      await tester.pumpAndSettle();

      expect(find.text('CHOOSE MEDICINES'), findsOneWidget);
      expect(find.text('Available drug'), findsNothing);
      expect(find.textContaining('Amoxicillin'), findsWidgets);
      expect(find.textContaining('Ibuprofen'), findsWidgets);
      expect(find.text('Add selected medicines'), findsOneWidget);
    });

    testWidgets('cancel on catalog picker adds nothing', (
      WidgetTester tester,
    ) async {
      await _pumpPrescribeDialog(tester);

      await tester.tap(find.text('Add medicine').first);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Amoxicillin').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, 'Close').last);
      await tester.pumpAndSettle();

      expect(find.text('No medicines added yet'), findsOneWidget);
      expect(find.textContaining('Amoxicillin'), findsNothing);
    });

    testWidgets(
      'keeps facility price from remote catalog when reference drugs lack it',
      (WidgetTester tester) async {
        await _pumpPrescribeDialog(
          tester,
          referenceData: const ClinicalActionReferenceData(
            drugs: <ClinicalActionCatalogOption>[],
          ),
          loadCatalogDrugs: (String query) async {
            return const <ClinicalActionCatalogOption>[
              ClinicalActionCatalogOption(
                id: 'uuid-amox',
                publicId: 'DRG-D38D9D5D69',
                name: 'Albendazole',
                code: 'ALB400',
                currency: 'UGX',
                metadata: <String, Object?>{
                  'generic_name': 'Albendazole',
                  'strength': '400 mg',
                  'form': 'Tablet',
                  'facility_unit_price': 32650,
                },
              ),
            ];
          },
        );

        await _addMedicinesFromCatalog(tester, <String>['Albendazole']);

        expect(find.textContaining('Albendazole'), findsWidgets);
        expect(find.textContaining('32,650'), findsWidgets);
        expect(find.text('DRG-D38D9D5D69'), findsNothing);

        await tester.enterText(_fieldWithLabel('Quantity').first, '1');
        await tester.pumpAndSettle();

        expect(find.text('Price not set'), findsNothing);
        expect(find.textContaining('32,650'), findsWidgets);
      },
    );

    testWidgets('adds editable table rows with prices and order total', (
      WidgetTester tester,
    ) async {
      await _pumpPrescribeDialog(tester);

      await _addMedicinesFromCatalog(tester, <String>[
        'Amoxicillin',
        'Ibuprofen',
      ]);

      expect(find.byType(AppCollapsibleSection), findsNothing);
      expect(find.textContaining('Amoxicillin (Amoxil) - 500 mg'), findsWidgets);
      expect(find.textContaining('Ibuprofen (Brufen) - 200 mg'), findsWidgets);
      expect(find.text('Price'), findsWidgets);
      expect(find.text('Amount'), findsWidgets);
      expect(find.text('Qty'), findsWidgets);
      expect(find.text('Unit'), findsWidgets);
      expect(find.text('Duration unit'), findsWidgets);
      expect(_fieldWithLabel('Dose amount'), findsWidgets);
      expect(_fieldWithLabel('Quantity'), findsWidgets);
      expect(find.text('capsule'), findsWidgets);
      expect(find.text('tablet'), findsWidgets);
      expect(find.text('Edit'), findsWidgets);
      expect(find.text('Delete'), findsWidgets);
    });

    testWidgets('uses mobile cards on narrow viewports', (
      WidgetTester tester,
    ) async {
      await _pumpPrescribeDialog(tester, width: 390);
      await _addMedicinesFromCatalog(tester, <String>['Amoxicillin']);

      expect(find.byType(AppCollapsibleSection), findsWidgets);
      expect(find.textContaining('Amoxicillin'), findsWidgets);
      expect(find.text('Qty'), findsNothing);
    });

    testWidgets('phones show a labeled add action that stays after adding', (
      WidgetTester tester,
    ) async {
      await _pumpPrescribeDialog(tester, width: 393);

      expect(find.widgetWithText(AppButton, 'Add medicine'), findsOneWidget);
      expect(find.byTooltip('Add medicine'), findsNothing);

      await _addMedicinesFromCatalog(tester, <String>['Amoxicillin']);

      expect(find.textContaining('Amoxicillin'), findsWidgets);
      expect(
        find.widgetWithText(AppButton, 'Add more medicines'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(AppButton, 'Add more medicines'));
      await tester.pumpAndSettle();
      expect(find.text('CHOOSE MEDICINES'), findsOneWidget);
      expect(find.textContaining('Ibuprofen'), findsWidgets);
    });

    testWidgets('tablet portrait also keeps the labeled add action', (
      WidgetTester tester,
    ) async {
      await _pumpPrescribeDialog(tester, width: 768);

      expect(find.widgetWithText(AppButton, 'Add medicine'), findsOneWidget);
    });

    testWidgets('explains why adding is unavailable on phones', (
      WidgetTester tester,
    ) async {
      await _pumpPrescribeDialog(
        tester,
        width: 393,
        allowAddMedicines: false,
        addMedicinesUnavailableMessage: 'Select the patient first.',
      );

      final AppButton add = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Add medicine'),
      );
      expect(add.onPressed, isNull);
      expect(find.text('Select the patient first.'), findsWidgets);
    });

    testWidgets('explains why adding is unavailable on desktop', (
      WidgetTester tester,
    ) async {
      await _pumpPrescribeDialog(
        tester,
        allowAddMedicines: false,
        addMedicinesUnavailableMessage: 'Select the patient first.',
      );

      expect(find.text('Select the patient first.'), findsOneWidget);
      expect(find.text('No medicines added yet'), findsNothing);
    });

    testWidgets('table shows dosing editors without expanding cards', (
      WidgetTester tester,
    ) async {
      await _pumpPrescribeDialog(tester);
      await _addMedicinesFromCatalog(tester, <String>['Amoxicillin']);

      expect(find.byType(AppCollapsibleSection), findsNothing);
      expect(find.text('Prescription details'), findsNothing);
      expect(_fieldWithLabel('Dose amount'), findsWidgets);
      expect(_fieldWithLabel('Duration'), findsWidgets);
      expect(_fieldWithLabel('Quantity'), findsWidgets);
    });

    testWidgets('seeds dose amount and unit from catalog strength', (
      WidgetTester tester,
    ) async {
      await _pumpPrescribeDialog(tester, width: 1800);
      await _addMedicinesFromCatalog(tester, <String>['Amoxicillin']);
      await tester.pumpAndSettle();

      expect(find.byType(AppTextField), findsWidgets);
      final Finder doseAmountField = _fieldWithLabel('Dose amount');
      expect(doseAmountField, findsWidgets);
      final AppTextField field = tester.widget<AppTextField>(
        doseAmountField.first,
      );
      expect(field.controller?.text, '500');

      final AppSelectField<String> doseUnit = tester
          .widget<AppSelectField<String>>(_selectWithLabel('Dose unit').first);
      expect(doseUnit.enabled, isTrue);
      expect(doseUnit.value, 'mg');
      expect(find.text('capsule'), findsWidgets);
    });

    testWidgets('blocks prescribe when quantity is zero', (
      WidgetTester tester,
    ) async {
      var submitted = false;
      await _pumpPrescribeDialog(
        tester,
        onSubmit:
            ({
              required List<Map<String, Object?>> items,
              ClinicalRequestBillingSubmit? billing,
            }) async {
              submitted = true;
              return null;
            },
      );

      await _addMedicinesFromCatalog(tester, <String>['Amoxicillin']);
      final Finder quantityField = _fieldWithLabel('Quantity');
      await tester.enterText(quantityField.first, '0');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithIcon(AppButton, Icons.send_outlined));
      await tester.pumpAndSettle();

      expect(submitted, isFalse);
      expect(find.text('Check the highlighted details.'), findsOneWidget);
      expect(find.text('This field is required.'), findsNothing);

      await tester.enterText(quantityField.first, '1');
      await tester.pumpAndSettle();
      expect(find.text('Check the highlighted details.'), findsNothing);
    });

    testWidgets('adds selected medicines from catalog and removes them', (
      WidgetTester tester,
    ) async {
      await _pumpPrescribeDialog(tester);

      await _addMedicinesFromCatalog(tester, <String>[
        'Amoxicillin',
        'Ibuprofen',
      ]);

      expect(find.textContaining('Amoxicillin'), findsWidgets);
      expect(find.textContaining('Ibuprofen'), findsWidgets);

      await tester.tap(find.byType(Checkbox).last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remove selected').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('REMOVE'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppButton, 'Remove').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('Ibuprofen'), findsNothing);
      expect(find.textContaining('Amoxicillin'), findsWidgets);
    });

    testWidgets('does not add a duplicate medicine already on the list', (
      WidgetTester tester,
    ) async {
      await _pumpPrescribeDialog(tester);

      await _addMedicinesFromCatalog(tester, <String>['Amoxicillin']);
      expect(find.textContaining('Amoxicillin'), findsWidgets);

      await tester.tap(find.text('Add medicine').first);
      await tester.pumpAndSettle();

      expect(find.text('CHOOSE MEDICINES'), findsOneWidget);
      // Already-added Amoxicillin remains on the order behind the catalog.
      expect(find.textContaining('Amoxicillin'), findsWidgets);
      expect(find.textContaining('Ibuprofen'), findsWidgets);

      await tester.tap(find.widgetWithText(AppButton, 'Close').last);
      await tester.pumpAndSettle();
    });

    testWidgets('blocks prescribe when duration is cleared', (
      WidgetTester tester,
    ) async {
      var submitted = false;
      await _pumpPrescribeDialog(
        tester,
        onSubmit:
            ({
              required List<Map<String, Object?>> items,
              ClinicalRequestBillingSubmit? billing,
            }) async {
              submitted = true;
              return null;
            },
      );

      await _addMedicinesFromCatalog(tester, <String>['Amoxicillin']);
      await _setDurationInline(tester, duration: '');

      await tester.tap(find.widgetWithIcon(AppButton, Icons.send_outlined));
      await tester.pumpAndSettle();

      expect(submitted, isFalse);
      expect(find.text('CHOOSE MEDICINES'), findsNothing);
      expect(find.textContaining('Amoxicillin'), findsWidgets);
      expect(_fieldWithLabel('Dose amount'), findsWidgets);
      expect(find.text('Check the highlighted details.'), findsOneWidget);
      expect(find.text('This field is required.'), findsNothing);

      await tester.enterText(_fieldWithLabel('Duration').first, '7');
      await tester.pumpAndSettle();
      expect(find.text('Check the highlighted details.'), findsNothing);
    });

    testWidgets('seeds duration with zero quantity until user enters it', (
      WidgetTester tester,
    ) async {
      List<Map<String, Object?>>? submittedItems;

      await _pumpPrescribeDialog(
        tester,
        onSubmit:
            ({
              required List<Map<String, Object?>> items,
              ClinicalRequestBillingSubmit? billing,
            }) async {
              submittedItems = items;
              return null;
            },
      );

      await _addMedicinesFromCatalog(tester, <String>['Amoxicillin']);
      final AppTextField quantityField = tester.widget<AppTextField>(
        _fieldWithLabel('Quantity').first,
      );
      expect(quantityField.controller?.text, '0');

      await tester.tap(find.widgetWithIcon(AppButton, Icons.send_outlined));
      await tester.pumpAndSettle();
      expect(submittedItems, isNull);

      await tester.enterText(_fieldWithLabel('Quantity').first, '14');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithIcon(AppButton, Icons.send_outlined));
      await tester.pumpAndSettle();

      expect(submittedItems, isNotNull);
      expect(submittedItems!.single['drug_id'], 'DRG-AMOX');
      expect(submittedItems!.single['dose_amount'], 500);
      expect(submittedItems!.single['dose_unit'], 'mg');
      expect(submittedItems!.single['quantity'], 14);
      expect(submittedItems!.single['duration_value'], 7);
      expect(submittedItems!.single['quantity_unit'], 'capsule');
    });

    testWidgets('duration edit does not auto-fill quantity', (
      WidgetTester tester,
    ) async {
      List<Map<String, Object?>>? submittedItems;

      await _pumpPrescribeDialog(
        tester,
        onSubmit:
            ({
              required List<Map<String, Object?>> items,
              ClinicalRequestBillingSubmit? billing,
            }) async {
              submittedItems = items;
              return null;
            },
      );

      await _addMedicinesFromCatalog(tester, <String>['Amoxicillin']);
      await _setDurationInline(tester, duration: '5');

      final AppTextField quantityField = tester.widget<AppTextField>(
        _fieldWithLabel('Quantity').first,
      );
      expect(quantityField.controller?.text, '0');

      await tester.enterText(_fieldWithLabel('Quantity').first, '10');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithIcon(AppButton, Icons.send_outlined));
      await tester.pumpAndSettle();

      expect(submittedItems, isNotNull);
      expect(submittedItems!.single['drug_id'], 'DRG-AMOX');
      expect(submittedItems!.single['dose_amount'], 500);
      expect(submittedItems!.single['dose_unit'], 'mg');
      expect(submittedItems!.single['quantity'], 10);
      expect(submittedItems!.single['duration_value'], 5);
    });
  });
}

Future<void> _addMedicinesFromCatalog(
  WidgetTester tester,
  List<String> medicineNames,
) async {
  Future<void> openCatalog() async {
    final Finder byText = find.text('Add medicine');
    if (byText.evaluate().isNotEmpty) {
      await tester.tap(byText.first);
      return;
    }
    final Finder byTooltip = find.byTooltip('Add medicine');
    if (byTooltip.evaluate().isNotEmpty) {
      await tester.tap(byTooltip.first);
      return;
    }
    final Finder byIcon = find.byIcon(Icons.add_circle_outline);
    if (byIcon.evaluate().isNotEmpty) {
      await tester.tap(byIcon.first);
      return;
    }
    final Finder more = find.byIcon(Icons.more_vert);
    expect(more, findsWidgets);
    await tester.tap(more.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add medicine').first);
  }

  await openCatalog();
  await tester.pumpAndSettle();

  expect(find.text('CHOOSE MEDICINES'), findsOneWidget);

  for (final String name in medicineNames) {
    final Finder row = find.textContaining(name);
    expect(row, findsWidgets);
    await tester.ensureVisible(row.last);
    await tester.tap(row.last);
    await tester.pumpAndSettle();
  }

  final Finder confirm = find.widgetWithText(
    AppButton,
    'Add selected medicines',
  );
  expect(confirm, findsOneWidget);
  await tester.tap(confirm);
  await tester.pumpAndSettle();

  expect(find.text('CHOOSE MEDICINES'), findsNothing);
}

Finder _fieldWithLabel(String label) {
  return find.byWidgetPredicate(
    (Widget widget) =>
        widget is AppTextField &&
        (widget.labelText == label || widget.semanticLabel == label),
  );
}

Finder _selectWithLabel(String label) {
  return find.byWidgetPredicate((Widget widget) {
    if (!widget.runtimeType.toString().startsWith('AppSelectField')) {
      return false;
    }
    final dynamic field = widget;
    return (field.labelText as String?) == label ||
        (field.semanticLabel as String?) == label;
  });
}

Future<void> _setDurationInline(
  WidgetTester tester, {
  required String duration,
}) async {
  final Finder durationField = _fieldWithLabel('Duration');
  expect(durationField, findsWidgets);
  await tester.ensureVisible(durationField.first);
  await tester.enterText(durationField.first, duration);
  await tester.pumpAndSettle();
}

Future<void> _pumpPrescribeDialog(
  WidgetTester tester, {
  Future<AppFailure?> Function({
    required List<Map<String, Object?>> items,
    ClinicalRequestBillingSubmit? billing,
  })?
  onSubmit,
  ClinicalActionReferenceData? referenceData,
  ClinicalPrescriptionCatalogLoader? loadCatalogDrugs,
  double width = 1800,
  bool allowAddMedicines = true,
  String? addMedicinesUnavailableMessage,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1000);
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
          body: ClinicalPrescriptionActionDialog(
            referenceData:
                referenceData ??
                const ClinicalActionReferenceData(
                  drugs: <ClinicalActionCatalogOption>[
                    ClinicalActionCatalogOption(
                      id: 'amox',
                      publicId: 'DRG-AMOX',
                      name: 'Amoxicillin',
                      code: 'AMOX',
                      unitPrice: 12,
                      currency: 'USD',
                      metadata: <String, Object?>{
                        'generic_name': 'Amoxicillin',
                        'brand_name': 'Amoxil',
                        'strength': '500 mg',
                        'form': 'Capsule',
                      },
                    ),
                    ClinicalActionCatalogOption(
                      id: 'ibu',
                      publicId: 'DRG-IBU',
                      name: 'Ibuprofen',
                      code: 'IBU',
                      unitPrice: 8,
                      currency: 'USD',
                      metadata: <String, Object?>{
                        'generic_name': 'Ibuprofen',
                        'brand_name': 'Brufen',
                        'strength': '200 mg',
                        'form': 'Tablet',
                      },
                    ),
                  ],
                ),
            loadCatalogDrugs: loadCatalogDrugs,
            allowAddMedicines: allowAddMedicines,
            addMedicinesUnavailableMessage: addMedicinesUnavailableMessage,
            onSubmit:
                onSubmit ??
                ({
                  required List<Map<String, Object?>> items,
                  ClinicalRequestBillingSubmit? billing,
                }) async {
                  return null;
                },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
