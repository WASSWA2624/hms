import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hosspi_hms/app/theme/app_theme.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/shared/components/components.dart';

import '../../helpers/test_harness.dart';
import 'component_test_app.dart';

void main() {
  test('clampAppSearchQuery collapses whitespace and caps length', () {
    expect(clampAppSearchQuery('  alpha\n\nbeta  '), 'alpha beta');
    expect(
      clampAppSearchQuery('x' * 300).length,
      appSearchQueryMaxLength,
    );
    expect(clampAppSearchQuery('   \n\t  '), isEmpty);
  });

  test('filter value counts scalar and multi-value criteria', () {
    const AppSearchBarFilterValue value = AppSearchBarFilterValue(
      field: 'patient',
      texts: <String, String>{'reason': 'review'},
      options: <String, String>{'legacy': 'open'},
      selections: <String, Set<String>>{
        'status': <String>{'new', 'confirmed'},
      },
    );

    expect(value.activeCount, 5);
    expect(value.optionsFor('legacy'), <String>{'open'});
    expect(value.optionsFor('status'), <String>{'new', 'confirmed'});
  });

  test('date ranges are inclusive and reject an inverted range', () {
    final DateTime day = DateTime(2026, 7, 19);

    expect(appSearchBarDateRangeIsValid(day, day), isTrue);
    expect(appSearchBarDateRangeIsValid(null, day), isTrue);
    expect(appSearchBarDateRangeIsValid(DateTime(2026, 7, 20), day), isFalse);
  });

  testWidgets('multi-select filter returns every checked value on Apply', (
    WidgetTester tester,
  ) async {
    final TextEditingController controller = TextEditingController();
    addTearDown(controller.dispose);
    AppSearchBarFilterValue? applied;

    await pumpComponent(
      tester,
      AppSearchBar(
        controller: controller,
        semanticLabel: 'Search records',
        showAdvancedFilterButton: true,
        enableDateFilter: false,
        filterGroups: const <AppSearchBarFilterGroup>[
          AppSearchBarFilterGroup(
            key: 'status',
            label: 'Status',
            choices: <AppSearchBarFilterChoice>[
              AppSearchBarFilterChoice(value: 'NEW', label: 'New'),
              AppSearchBarFilterChoice(value: 'CONFIRMED', label: 'Confirmed'),
            ],
            allowMultiple: true,
          ),
        ],
        onFilterChanged: (AppSearchBarFilterValue value) => applied = value,
      ),
      size: const Size(720, 640),
    );

    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'New'));
    await tester.pump();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Confirmed'));
    await tester.pump();
    await tester.tap(find.text('Apply filters'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(applied?.optionsFor('status'), <String>{'NEW', 'CONFIRMED'});
  });

  testWidgets('Apply filters shows busy state then closes', (
    WidgetTester tester,
  ) async {
    final TextEditingController controller = TextEditingController();
    addTearDown(controller.dispose);
    AppSearchBarFilterValue? applied;

    await pumpComponent(
      tester,
      AppSearchBar(
        controller: controller,
        semanticLabel: 'Search records',
        showAdvancedFilterButton: true,
        enableDateFilter: false,
        advancedFilterApplyLabel: 'Apply filters',
        filterGroups: const <AppSearchBarFilterGroup>[
          AppSearchBarFilterGroup(
            key: 'status',
            label: 'Status',
            choices: <AppSearchBarFilterChoice>[
              AppSearchBarFilterChoice(value: 'NEW', label: 'New'),
            ],
          ),
        ],
        onFilterChanged: (AppSearchBarFilterValue value) => applied = value,
      ),
      size: const Size(720, 640),
    );

    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply filters'));
    await tester.pump();

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.byType(AppLoadingIndicator), findsOneWidget);
    expect(find.text('Loading'), findsOneWidget);
    expect(find.text('Please wait...'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.byType(AppDialog), findsNothing);
    expect(applied, isNotNull);
  });

  testWidgets('footer Close discards pending filter changes', (
    WidgetTester tester,
  ) async {
    final TextEditingController controller = TextEditingController();
    addTearDown(controller.dispose);
    AppSearchBarFilterValue? applied;

    await pumpComponent(
      tester,
      AppSearchBar(
        controller: controller,
        semanticLabel: 'Search records',
        showAdvancedFilterButton: true,
        enableDateFilter: false,
        advancedFilterCloseLabel: 'Close',
        textFilters: const <AppSearchBarTextFilter>[
          AppSearchBarTextFilter(key: 'patient', label: 'Patient'),
        ],
        onFilterChanged: (AppSearchBarFilterValue value) => applied = value,
      ),
      size: const Size(720, 640),
    );

    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, 'Ada');
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(applied, isNull);
  });

  testWidgets('advanced filter dialog includes rightmost Close on mobile', (
    WidgetTester tester,
  ) async {
    final TextEditingController controller = TextEditingController();
    addTearDown(controller.dispose);

    await pumpComponent(
      tester,
      AppSearchBar(
        controller: controller,
        semanticLabel: 'Search records',
        showAdvancedFilterButton: true,
        advancedFilterTitle: 'Clinical filters',
        advancedFilterApplyLabel: 'Apply filters',
        advancedFilterResetLabel: 'Clear filters',
        enableDateFilter: false,
        textFilters: const <AppSearchBarTextFilter>[
          AppSearchBarTextFilter(key: 'name', label: 'Patient name'),
        ],
      ),
      size: const Size(400, 498),
    );

    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();

    final Finder clearAction = find.text('Clear filters');
    final Finder applyAction = find.text('Apply filters');
    final Finder closeAction = find.text('Close');

    expect(find.text('CLINICAL FILTERS'), findsOneWidget);
    expect(clearAction, findsOneWidget);
    expect(applyAction, findsOneWidget);
    expect(closeAction, findsOneWidget);
    expect(find.text('Close'), findsNothing);
    final Offset applyPosition = tester.getTopLeft(applyAction);
    final Offset closePosition = tester.getTopLeft(closeAction);
    expect(
      closePosition.dy > applyPosition.dy ||
          (closePosition.dy == applyPosition.dy &&
              closePosition.dx > applyPosition.dx),
      isTrue,
    );
  });

  testWidgets('attached toolbar actions show labels on large screens', (
    WidgetTester tester,
  ) async {
    final TextEditingController controller = TextEditingController();
    addTearDown(controller.dispose);

    await pumpComponent(
      tester,
      AppSearchBar(
        controller: controller,
        semanticLabel: 'Search records',
        showAdvancedFilterButton: true,
        advancedFilterButtonLabel: 'Filters',
        trailingActions: <AppSearchBarAction>[
          AppSearchBarAction(
            icon: Icons.settings_outlined,
            label: 'Settings',
            onPressed: () {},
          ),
        ],
      ),
      size: const Size(960, 498),
    );

    expect(find.text('Filters'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('attached toolbar actions stay icon-only on compact screens', (
    WidgetTester tester,
  ) async {
    final TextEditingController controller = TextEditingController();
    addTearDown(controller.dispose);

    await pumpComponent(
      tester,
      AppSearchBar(
        controller: controller,
        semanticLabel: 'Search records',
        showAdvancedFilterButton: true,
        advancedFilterButtonLabel: 'Filters',
        trailingActions: <AppSearchBarAction>[
          AppSearchBarAction(
            icon: Icons.settings_outlined,
            label: 'Settings',
            onPressed: () {},
          ),
        ],
      ),
      size: const Size(720, 498),
    );

    expect(find.text('Filters'), findsNothing);
    expect(find.text('Settings'), findsNothing);
    expect(find.byTooltip('Filters'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
  });

  testWidgets('filter dialog clear leaves placeholder instead of All option', (
    WidgetTester tester,
  ) async {
    final TextEditingController controller = TextEditingController();
    addTearDown(controller.dispose);

    await pumpComponent(
      tester,
      AppSearchBar(
        controller: controller,
        semanticLabel: 'Search records',
        showAdvancedFilterButton: true,
        advancedFilterTitle: 'Workspace filters',
        advancedFilterApplyLabel: 'Apply filters',
        advancedFilterResetLabel: 'Clear filters',
        enableDateFilter: false,
        allFieldsLabel: 'All',
        filterGroups: const <AppSearchBarFilterGroup>[
          AppSearchBarFilterGroup(
            key: 'queue',
            label: 'Queue',
            allLabel: 'All',
            choices: <AppSearchBarFilterChoice>[
              AppSearchBarFilterChoice(
                value: 'processing',
                label: 'Processing',
              ),
              AppSearchBarFilterChoice(
                value: 'awaiting',
                label: 'Awaiting results',
              ),
            ],
          ),
        ],
      ),
      size: const Size(720, 640),
    );

    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();

    final Finder dialog = find.byType(AppDialog);
    final Finder queueField = find.descendant(
      of: dialog,
      matching: find.byType(EditableText),
    );

    await tester.tap(queueField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Processing').hitTestable());
    await tester.pumpAndSettle();

    expect(find.text('Processing'), findsOneWidget);

    final Finder selectClear = find.descendant(
      of: find.descendant(
        of: dialog,
        matching: find.byType(DropdownMenuFormField<String>),
      ),
      matching: find.byIcon(Icons.close),
    );
    await tester.tap(selectClear);
    await tester.pumpAndSettle();

    expect(find.text('Processing'), findsNothing);
    expect(
      find.descendant(of: dialog, matching: find.text('All')),
      findsOneWidget,
    );
  });

  testWidgets(
    'filter dialog shows all options when reopening menu with a selection',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);

      await pumpComponent(
        tester,
        AppSearchBar(
          controller: controller,
          semanticLabel: 'Search records',
          showAdvancedFilterButton: true,
          advancedFilterTitle: 'Workspace filters',
          advancedFilterApplyLabel: 'Apply filters',
          advancedFilterResetLabel: 'Clear filters',
          enableDateFilter: false,
          allFieldsLabel: 'All',
          filterGroups: const <AppSearchBarFilterGroup>[
            AppSearchBarFilterGroup(
              key: 'queue',
              label: 'Queue',
              allLabel: 'All',
              choices: <AppSearchBarFilterChoice>[
                AppSearchBarFilterChoice(
                  value: 'processing',
                  label: 'Processing',
                ),
                AppSearchBarFilterChoice(
                  value: 'awaiting',
                  label: 'Awaiting results',
                ),
              ],
            ),
          ],
        ),
        size: const Size(720, 640),
      );

      await tester.tap(find.byTooltip('Filter'));
      await tester.pumpAndSettle();

      final Finder dialog = find.byType(AppDialog);
      final Finder queueField = find.descendant(
        of: dialog,
        matching: find.byType(EditableText),
      );

      await tester.tap(queueField);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Awaiting results').hitTestable());
      await tester.pumpAndSettle();

      await tester.tap(queueField);
      await tester.pumpAndSettle();

      expect(find.text('Processing').hitTestable(), findsOneWidget);
      expect(find.text('All').hitTestable(), findsOneWidget);
    },
  );

  testWidgets('AppSearchBar truncates overlong pasted search text', (
    WidgetTester tester,
  ) async {
    final TextEditingController controller = TextEditingController();
    addTearDown(controller.dispose);

    await pumpComponent(
      tester,
      AppSearchBar(
        controller: controller,
        semanticLabel: 'Search rows',
        hintText: 'Search',
      ),
    );

    final Finder field = find.byType(TextFormField);
    expect(field, findsOneWidget);

    final String longPaste = '${'word ' * 80}\n\nmore text';
    await tester.enterText(field, longPaste);
    await tester.pump();

    expect(controller.text.contains('\n'), isFalse);
    expect(controller.text.length, lessThanOrEqualTo(appSearchQueryMaxLength));
  });

  testWidgets('filter groups are listed under their section headings', (
    WidgetTester tester,
  ) async {
    final TextEditingController controller = TextEditingController();
    addTearDown(controller.dispose);

    await _pumpScoped(
      tester,
      AppSearchBar(
        controller: controller,
        semanticLabel: 'Search records',
        showAdvancedFilterButton: true,
        dateFilterLabel: 'Submitted',
        dateFilterSection: 'Report',
        filterGroups: const <AppSearchBarFilterGroup>[
          AppSearchBarFilterGroup(
            key: 'category',
            label: 'Category',
            section: 'Report',
            allowMultiple: true,
            choices: <AppSearchBarFilterChoice>[
              AppSearchBarFilterChoice(value: 'BUG', label: 'Bug'),
            ],
          ),
          AppSearchBarFilterGroup(
            key: 'theme',
            label: 'Theme',
            section: 'Device',
            allowMultiple: true,
            choices: <AppSearchBarFilterChoice>[
              AppSearchBarFilterChoice(value: 'dark', label: 'Dark'),
            ],
          ),
          // No choices: hidden, and its section with it.
          AppSearchBarFilterGroup(
            key: 'tenant',
            label: 'Tenant',
            section: 'Who',
            allowMultiple: true,
            choices: <AppSearchBarFilterChoice>[],
          ),
        ],
        onFilterChanged: (_) {},
      ),
      size: const Size(720, 900),
    );

    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();

    expect(find.text('Report'), findsOneWidget);
    expect(find.text('Device'), findsOneWidget);
    expect(find.text('Who'), findsNothing);
    expect(find.text('Tenant'), findsNothing);
    final double report = tester.getTopLeft(find.text('Report')).dy;
    final double submitted = tester.getTopLeft(find.text('Submitted')).dy;
    final double category = tester.getTopLeft(find.text('Category')).dy;
    final double device = tester.getTopLeft(find.text('Device')).dy;
    final double theme = tester.getTopLeft(find.text('Theme')).dy;
    expect(report, lessThan(submitted));
    expect(submitted, lessThan(category));
    expect(category, lessThan(device));
    expect(device, lessThan(theme));
  });

  testWidgets(
    'loaded filter groups replace the fallback and keep picked values',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);
      final Completer<List<AppSearchBarFilterGroup>> groups =
          Completer<List<AppSearchBarFilterGroup>>();
      AppSearchBarFilterValue? applied;

      await _pumpScoped(
        tester,
        AppSearchBar(
          controller: controller,
          semanticLabel: 'Search records',
          showAdvancedFilterButton: true,
          enableDateFilter: false,
          filterGroupsLoadingLabel: 'Loading filter choices',
          filterGroups: const <AppSearchBarFilterGroup>[
            AppSearchBarFilterGroup(
              key: 'status',
              label: 'Status',
              allowMultiple: true,
              choices: <AppSearchBarFilterChoice>[
                AppSearchBarFilterChoice(value: 'NEW', label: 'Fallback new'),
              ],
            ),
          ],
          loadFilterGroups: () => groups.future,
          filterValue: const AppSearchBarFilterValue(
            selections: <String, Set<String>>{
              'tenant': <String>{'TEN-1'},
            },
          ),
          onFilterChanged: (AppSearchBarFilterValue value) => applied = value,
        ),
        size: const Size(720, 900),
      );

      await tester.tap(find.byTooltip('Filter (1)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Loading filter choices'), findsOneWidget);
      expect(find.text('Fallback new'), findsNothing);

      groups.complete(const <AppSearchBarFilterGroup>[
        AppSearchBarFilterGroup(
          key: 'tenant',
          label: 'Tenant',
          allowMultiple: true,
          choices: <AppSearchBarFilterChoice>[
            AppSearchBarFilterChoice(
              value: 'TEN-1',
              label: 'DemoCare',
              caption: 'TEN-1 · 19 records',
            ),
            AppSearchBarFilterChoice(
              value: 'TEN-2',
              label: 'IHK Group',
              caption: 'TEN-2 · 1 record',
            ),
          ],
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Loading filter choices'), findsNothing);
      expect(find.text('Fallback new'), findsNothing);
      expect(find.text('TEN-1 · 19 records'), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'DemoCare'),
            )
            .value,
        isTrue,
      );

      await tester.tap(find.widgetWithText(CheckboxListTile, 'IHK Group'));
      await tester.pump();
      await tester.tap(find.text('Apply filters'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(applied?.optionsFor('tenant'), <String>{'TEN-1', 'TEN-2'});
    },
  );

  testWidgets('filter groups fall back when loading them fails', (
    WidgetTester tester,
  ) async {
    final TextEditingController controller = TextEditingController();
    addTearDown(controller.dispose);

    await _pumpScoped(
      tester,
      AppSearchBar(
        controller: controller,
        semanticLabel: 'Search records',
        showAdvancedFilterButton: true,
        enableDateFilter: false,
        filterGroupsLoadErrorMessage: 'Choices could not be loaded.',
        filterGroups: const <AppSearchBarFilterGroup>[
          AppSearchBarFilterGroup(
            key: 'status',
            label: 'Status',
            allowMultiple: true,
            choices: <AppSearchBarFilterChoice>[
              AppSearchBarFilterChoice(value: 'NEW', label: 'Fallback new'),
            ],
          ),
        ],
        loadFilterGroups: () async => throw StateError('offline'),
        onFilterChanged: (_) {},
      ),
      size: const Size(720, 900),
    );

    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();

    expect(find.text('Choices could not be loaded.'), findsOneWidget);
    expect(find.text('Fallback new'), findsOneWidget);
  });

  testWidgets('searchable groups narrow choices by label or caption', (
    WidgetTester tester,
  ) async {
    final TextEditingController controller = TextEditingController();
    addTearDown(controller.dispose);

    await _pumpScoped(
      tester,
      AppSearchBar(
        controller: controller,
        semanticLabel: 'Search records',
        showAdvancedFilterButton: true,
        enableDateFilter: false,
        filterGroups: const <AppSearchBarFilterGroup>[
          AppSearchBarFilterGroup(
            key: 'facility',
            label: 'Facility',
            allowMultiple: true,
            searchable: true,
            searchHintText: 'Search facilities',
            emptySearchText: 'No matches',
            choices: <AppSearchBarFilterChoice>[
              AppSearchBarFilterChoice(
                value: 'FAC-1',
                label: 'Main Wing',
                caption: 'FAC-1',
              ),
              AppSearchBarFilterChoice(
                value: 'FAC-2',
                label: 'Annex',
                caption: 'FAC-2',
              ),
            ],
          ),
        ],
        onFilterChanged: (_) {},
      ),
      size: const Size(720, 900),
    );

    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();

    final Finder search = find.descendant(
      of: find.ancestor(
        of: find.text('Search facilities'),
        matching: find.byType(AppTextField),
      ),
      matching: find.byType(TextField),
    );
    await tester.enterText(search, 'fac-2');
    await tester.pump();

    expect(find.widgetWithText(CheckboxListTile, 'Annex'), findsOneWidget);
    expect(find.widgetWithText(CheckboxListTile, 'Main Wing'), findsNothing);

    await tester.enterText(search, 'lab');
    await tester.pump();

    expect(find.text('No matches'), findsOneWidget);
  });
}

/// Pumps [child] with the provider scope above the app, so the filter dialog
/// it opens on the root navigator can build provider-backed fields.
Future<void> _pumpScoped(
  WidgetTester tester,
  Widget child, {
  required Size size,
}) async {
  setTestViewport(tester, size);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(24), child: child),
        ),
      ),
    ),
  );
}
