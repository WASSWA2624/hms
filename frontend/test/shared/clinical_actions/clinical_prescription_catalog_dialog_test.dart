import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hosspi_hms/app/theme/app_theme.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/shared/clinical_actions/clinical_actions.dart';
import 'package:hosspi_hms/shared/components/components.dart';

void main() {
  group('ClinicalPrescriptionCatalogDialog', () {
    testWidgets('renders list rows on phones and a table on desktop', (
      WidgetTester tester,
    ) async {
      await _openPicker(tester, drugs: _catalog, width: 393);
      expect(find.byType(AppListTableMobileItem), findsWidgets);
      expect(find.text('Available'), findsNothing);

      await _openPicker(tester, drugs: _catalog, width: 1400);
      expect(find.byType(AppListTableMobileItem), findsNothing);
      // Column headers only exist in the table layout.
      expect(find.text('Available'), findsOneWidget);
    });

    testWidgets(
      'one tap selects one medicine when two tenants share a drug id',
      (WidgetTester tester) async {
        final _PickerResult result = await _openPicker(
          tester,
          drugs: _catalogWithCrossTenantIdCollision,
          width: 393,
        );

        await tester.tap(find.textContaining('Amoxicillin').first);
        await tester.pumpAndSettle();

        expect(find.text('1 selected'), findsOneWidget);
        expect(_checkedCheckboxes(), findsOneWidget);

        await tester.tap(
          find.widgetWithText(AppButton, 'Add selected medicines'),
        );
        await tester.pumpAndSettle();

        expect(result.value, isNotNull);
        expect(result.value!.map((ClinicalActionCatalogOption option) {
          return option.name;
        }), <String?>['Amoxicillin']);
      },
    );

    testWidgets('identical rows returned twice render once', (
      WidgetTester tester,
    ) async {
      await _openPicker(
        tester,
        drugs: const <ClinicalActionCatalogOption>[
          _amoxicillin,
          _amoxicillin,
          _ibuprofen,
        ],
        width: 393,
      );

      expect(find.textContaining('Amoxicillin'), findsOneWidget);

      await tester.tap(find.textContaining('Amoxicillin'));
      await tester.pumpAndSettle();

      expect(find.text('1 selected'), findsOneWidget);
      expect(_checkedCheckboxes(), findsOneWidget);
    });

    testWidgets('tapping a selected row again clears it', (
      WidgetTester tester,
    ) async {
      await _openPicker(tester, drugs: _catalog, width: 393);

      await tester.tap(find.textContaining('Ibuprofen'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);

      await tester.tap(find.textContaining('Ibuprofen'));
      await tester.pumpAndSettle();
      expect(find.text('0 selected'), findsOneWidget);
      expect(_checkedCheckboxes(), findsNothing);
    });

    testWidgets('keeps row order stable while selecting', (
      WidgetTester tester,
    ) async {
      await _openPicker(tester, drugs: _catalog, width: 393);
      final double ibuprofenTop = tester
          .getTopLeft(find.textContaining('Ibuprofen'))
          .dy;

      await tester.tap(find.textContaining('Ibuprofen'));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.textContaining('Ibuprofen')).dy,
          ibuprofenTop);
    });

    testWidgets('excludes medicines already on the order', (
      WidgetTester tester,
    ) async {
      await _openPicker(
        tester,
        drugs: _catalog,
        alreadySelectedDrugIds: const <String>{'dru0000006'},
        width: 393,
      );

      expect(find.textContaining('Amoxicillin'), findsOneWidget);
      expect(find.textContaining('Ibuprofen'), findsNothing);
    });
  });
}

const ClinicalActionCatalogOption _amoxicillin = ClinicalActionCatalogOption(
  id: 'DRU0000005',
  publicId: 'DRU0000005',
  name: 'Amoxicillin',
  code: 'AMOX',
  metadata: <String, Object?>{'tenant_id': 'TEN0000001'},
);

const ClinicalActionCatalogOption _ibuprofen = ClinicalActionCatalogOption(
  id: 'DRU0000006',
  publicId: 'DRU0000006',
  name: 'Ibuprofen',
  code: 'IBU',
  metadata: <String, Object?>{'tenant_id': 'TEN0000001'},
);

const List<ClinicalActionCatalogOption> _catalog =
    <ClinicalActionCatalogOption>[_amoxicillin, _ibuprofen];

/// Friendly drug ids restart per tenant, so a catalog spanning two tenants can
/// carry the same `DRU…` id for different medicines.
const List<ClinicalActionCatalogOption> _catalogWithCrossTenantIdCollision =
    <ClinicalActionCatalogOption>[
      _amoxicillin,
      ClinicalActionCatalogOption(
        id: 'DRU0000005',
        publicId: 'DRU0000005',
        name: 'Metformin',
        code: 'MET',
        metadata: <String, Object?>{'tenant_id': 'TEN0000003'},
      ),
      _ibuprofen,
    ];

final class _PickerResult {
  List<ClinicalActionCatalogOption>? value;
}

Finder _checkedCheckboxes() {
  return find.byWidgetPredicate(
    (Widget widget) => widget is Checkbox && widget.value == true,
  );
}

Future<_PickerResult> _openPicker(
  WidgetTester tester, {
  required List<ClinicalActionCatalogOption> drugs,
  required double width,
  Set<String> alreadySelectedDrugIds = const <String>{},
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 886);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final _PickerResult result = _PickerResult();
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      child: MaterialApp(
        theme: AppTheme.light,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) {
              return Center(
                child: TextButton(
                  onPressed: () async {
                    result.value = await showClinicalPrescriptionCatalogDialog(
                      context: context,
                      drugs: drugs,
                      alreadySelectedDrugIds: alreadySelectedDrugIds,
                    );
                  },
                  child: const Text('Open picker'),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open picker'));
  await tester.pumpAndSettle();
  expect(find.text('CHOOSE MEDICINES'), findsOneWidget);
  return result;
}
