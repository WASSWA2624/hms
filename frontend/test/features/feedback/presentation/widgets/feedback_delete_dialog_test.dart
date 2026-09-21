import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hosspi_hms/app/theme/app_theme.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/features/feedback/data/repositories/feedback_repository_impl.dart';
import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';
import 'package:hosspi_hms/features/feedback/domain/repositories/feedback_repository.dart';
import 'package:hosspi_hms/features/feedback/presentation/widgets/feedback_delete_dialog.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/shared/actions/app_action_dialogs.dart';
import 'package:hosspi_hms/shared/components/components.dart';
import 'package:hosspi_hms/shared/data/app_pagination.dart';

typedef _PageCall = ({
  FeedbackFilters filters,
  AppPageRequest request,
  FeedbackSort sort,
});

FeedbackFacetValue _facet(String value, int count, {String? label}) {
  return FeedbackFacetValue(value: value, count: count, label: label);
}

/// Stored values as the facets endpoint reports them: no app version or
/// connectivity was ever recorded, so those filters have nothing to offer.
final FeedbackFacets _storedFacets = FeedbackFacets(
  total: 45,
  categories: <FeedbackFacetValue>[_facet('PROBLEM', 45)],
  submitterTypes: <FeedbackFacetValue>[_facet('AUTHENTICATED', 45)],
  deviceTypes: <FeedbackFacetValue>[_facet('DESKTOP', 45)],
  values: <FeedbackFilterDimension, List<FeedbackFacetValue>>{
    FeedbackFilterDimension.tenant: <FeedbackFacetValue>[
      _facet('TEN-9322E26AFD', 40, label: 'DemoCare General Hospital'),
      _facet('TEN0000002', 5, label: 'IHK Group'),
    ],
    FeedbackFilterDimension.role: <FeedbackFacetValue>[
      _facet('PLATFORM_ADMIN', 45),
    ],
    FeedbackFilterDimension.routeName: <FeedbackFacetValue>[
      _facet('hr', 30),
      _facet('home', 15),
    ],
    FeedbackFilterDimension.platform: <FeedbackFacetValue>[_facet('web', 45)],
    FeedbackFilterDimension.breakpoint: <FeedbackFacetValue>[
      _facet('xl', 40),
      _facet('sm', 5),
    ],
  },
);

final class _FakeFeedbackRepository implements FeedbackRepository {
  _FakeFeedbackRepository(int count)
    : records = <FeedbackRecord>[
        for (int index = 1; index <= count; index += 1)
          FeedbackRecord(
            referenceId: 'FBK${'$index'.padLeft(7, '0')}',
            category: FeedbackCategory.problem,
            submitterType: FeedbackSubmitterType.authenticated,
            messagePreview: 'Feedback message $index',
            submittedAt: DateTime(2026, 9, 14, 9, index % 60),
            userEmail: 'user$index@example.com',
            deviceType: FeedbackDeviceType.desktop,
            platform: 'web',
          ),
      ];

  final List<FeedbackRecord> records;
  final List<_PageCall> pageCalls = <_PageCall>[];
  final List<FeedbackFilters> facetCalls = <FeedbackFilters>[];
  bool facetsFail = false;
  final List<Set<String>> deletedIds = <Set<String>>[];
  final List<FeedbackFilters> deletedMatching = <FeedbackFilters>[];
  int failuresRemaining = 0;

  @override
  Future<Result<AppPage<FeedbackRecord>>> fetchFeedbackPage({
    required FeedbackFilters filters,
    required AppPageRequest request,
    FeedbackSort sort = FeedbackSort.newestFirst,
  }) async {
    pageCalls.add((filters: filters, request: request, sort: sort));
    if (failuresRemaining > 0) {
      failuresRemaining -= 1;
      return const Result<AppPage<FeedbackRecord>>.failure(
        AppFailure.network(),
      );
    }
    return Result<AppPage<FeedbackRecord>>.success(
      AppPage<FeedbackRecord>(
        items: records
            .skip(request.offset)
            .take(request.pageSize)
            .toList(growable: false),
        request: request,
        totalItemCount: records.length,
      ),
    );
  }

  @override
  Future<Result<FeedbackFacets>> fetchFeedbackFacets({
    required FeedbackFilters filters,
  }) async {
    facetCalls.add(filters);
    if (facetsFail) {
      return const Result<FeedbackFacets>.failure(AppFailure.network());
    }
    return Result<FeedbackFacets>.success(_storedFacets);
  }

  @override
  Future<Result<FeedbackDeleteResult>> deleteFeedback({
    required Set<String> referenceIds,
  }) async {
    deletedIds.add(Set<String>.of(referenceIds));
    final int before = records.length;
    records.removeWhere(
      (FeedbackRecord record) => referenceIds.contains(record.referenceId),
    );
    return Result<FeedbackDeleteResult>.success(
      FeedbackDeleteResult(deletedCount: before - records.length),
    );
  }

  @override
  Future<Result<List<FeedbackStoredScreenshot>>> fetchFeedbackScreenshots({
    required String referenceId,
  }) async {
    return const Result<List<FeedbackStoredScreenshot>>.success(
      <FeedbackStoredScreenshot>[],
    );
  }

  @override
  Future<Result<Uint8List>> fetchFeedbackScreenshotImage({
    required String referenceId,
    required String screenshotId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<FeedbackDeleteResult>> deleteMatchingFeedback({
    required FeedbackFilters filters,
  }) async {
    deletedMatching.add(filters);
    final int count = records.length;
    records.clear();
    return Result<FeedbackDeleteResult>.success(
      FeedbackDeleteResult(deletedCount: count),
    );
  }

  @override
  Future<Result<FeedbackReceipt>> submitFeedback(
    FeedbackSubmission submission, {
    required bool signedIn,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<Uint8List>> downloadFeedbackExport({
    required int utcOffsetMinutes,
    Set<String> referenceIds = const <String>{},
    FeedbackFilters filters = FeedbackFilters.none,
  }) {
    throw UnimplementedError();
  }
}

Future<void> _openDialog(
  WidgetTester tester,
  _FakeFeedbackRepository repository, {
  ValueChanged<int?>? onResult,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [feedbackRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: AppTheme.light,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) {
              return TextButton(
                onPressed: () async {
                  final int? deleted = await showFeedbackDeleteDialog(
                    context: context,
                  );
                  onResult?.call(deleted);
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Finder get _deleteButton => find.descendant(
  of: find.byType(FeedbackDeleteDialog),
  matching: find.widgetWithText(AppButton, 'Delete permanently'),
);

Future<void> _tapRow(WidgetTester tester, String referenceId) async {
  await tester.tap(find.byKey(FeedbackDeleteDialog.rowCheckboxKey(referenceId)));
  await tester.pump();
}

/// How many rows on the page are ticked. The ticked boxes are the only record
/// of the selection; the dialog shows no running count.
int _checkedRowCount(WidgetTester tester) {
  return tester
      .widgetList<Checkbox>(find.byType(Checkbox))
      .where(
        (Checkbox box) =>
            box.key != FeedbackDeleteDialog.pageCheckboxKey &&
            (box.value ?? false),
      )
      .length;
}

/// Whether anything at all is picked, on this page or another.
bool _hasSelection(WidgetTester tester) {
  return tester.widget<AppButton>(_deleteButton).onPressed != null;
}

bool? _rowChecked(WidgetTester tester, String referenceId) {
  return tester
      .widget<Checkbox>(
        find.byKey(FeedbackDeleteDialog.rowCheckboxKey(referenceId)),
      )
      .value;
}

/// Opens the filter dialog; its button counts the picked values once any are.
Future<void> _openFilters(WidgetTester tester, {int active = 0}) async {
  await tester.tap(
    find.byTooltip(active == 0 ? 'Filters' : 'Filters ($active)'),
  );
  await tester.pumpAndSettle();
}

Future<void> _tickFilterChoice(WidgetTester tester, String label) async {
  final Finder choice = find.widgetWithText(CheckboxListTile, label);
  await tester.ensureVisible(choice);
  await tester.pumpAndSettle();
  await tester.tap(choice);
  await tester.pump();
}

Future<void> _confirmDelete(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AppConfirmActionDialog),
      matching: find.widgetWithText(AppButton, 'Delete permanently'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists the first page of stored feedback with nothing selected', (
    WidgetTester tester,
  ) async {
    final _FakeFeedbackRepository repository = _FakeFeedbackRepository(3);
    await _openDialog(tester, repository);

    final _PageCall call = repository.pageCalls.single;
    expect(call.request, const AppPageRequest());
    expect(call.filters.search, isEmpty);
    expect(call.filters.hasActiveFilters, isFalse);
    expect(find.text('Feedback message 3'), findsOneWidget);
    expect(find.text('user2@example.com'), findsOneWidget);
    expect(
      find.byKey(FeedbackDeleteDialog.rowCheckboxKey('FBK0000001')),
      findsOneWidget,
    );
    expect(call.sort, FeedbackSort.newestFirst);
    // Nothing is picked, so there is nothing to delete.
    expect(_checkedRowCount(tester), 0);
    expect(_hasSelection(tester), isFalse);
  });

  testWidgets('deletes exactly the ticked records after confirmation', (
    WidgetTester tester,
  ) async {
    final _FakeFeedbackRepository repository = _FakeFeedbackRepository(3);
    int? result = -1;
    await _openDialog(
      tester,
      repository,
      onResult: (int? value) => result = value,
    );

    await _tapRow(tester, 'FBK0000001');
    await _tapRow(tester, 'FBK0000003');
    expect(_checkedRowCount(tester), 2);
    expect(_rowChecked(tester, 'FBK0000002'), isFalse);

    await tester.tap(_deleteButton);
    await tester.pumpAndSettle();

    expect(find.byType(AppConfirmActionDialog), findsOneWidget);
    expect(
      find.textContaining(
        'Delete 2 feedback records permanently',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(repository.deletedIds, isEmpty);

    await _confirmDelete(tester);

    expect(repository.deletedIds.single, <String>{'FBK0000001', 'FBK0000003'});
    expect(repository.deletedMatching, isEmpty);
    expect(find.byType(FeedbackDeleteDialog), findsNothing);
    expect(result, 2);
  });

  testWidgets('rows toggle from the row itself and the header selects the page', (
    WidgetTester tester,
  ) async {
    final _FakeFeedbackRepository repository = _FakeFeedbackRepository(25);
    await _openDialog(tester, repository);

    await tester.tap(find.text('Feedback message 2'));
    await tester.pump();
    expect(_rowChecked(tester, 'FBK0000002'), isTrue);
    expect(_checkedRowCount(tester), 1);

    await tester.tap(find.byKey(FeedbackDeleteDialog.pageCheckboxKey));
    await tester.pump();
    expect(_checkedRowCount(tester), 20);

    await tester.tap(find.byKey(FeedbackDeleteDialog.pageCheckboxKey));
    await tester.pump();
    expect(_checkedRowCount(tester), 0);
    expect(_rowChecked(tester, 'FBK0000002'), isFalse);
  });

  testWidgets('selections are kept while paging', (WidgetTester tester) async {
    final _FakeFeedbackRepository repository = _FakeFeedbackRepository(25);
    await _openDialog(tester, repository);

    await _tapRow(tester, 'FBK0000001');
    expect(find.text('1-20 of 25'), findsOneWidget);

    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();

    expect(repository.pageCalls.last.request.pageIndex, 1);
    expect(find.text('Feedback message 21'), findsOneWidget);
    expect(find.text('21-25 of 25'), findsOneWidget);
    // The page-one pick is off screen, but still picked.
    expect(_checkedRowCount(tester), 0);
    expect(_hasSelection(tester), isTrue);

    await _tapRow(tester, 'FBK0000025');
    await tester.tap(_deleteButton);
    await tester.pumpAndSettle();
    await _confirmDelete(tester);

    expect(repository.deletedIds.single, <String>{'FBK0000001', 'FBK0000025'});
  });

  testWidgets('sorting a column reorders the whole list from the first page', (
    WidgetTester tester,
  ) async {
    final _FakeFeedbackRepository repository = _FakeFeedbackRepository(45);
    await _openDialog(tester, repository);

    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    await _tapRow(tester, 'FBK0000021');
    expect(_hasSelection(tester), isTrue);

    await tester.tap(find.text('Submitted'));
    await tester.pumpAndSettle();

    final _PageCall sorted = repository.pageCalls.last;
    expect(
      sorted.sort,
      const FeedbackSort(
        field: FeedbackSortField.submittedAt,
        ascending: true,
      ),
    );
    // The same records still match, so the selection survives the reorder.
    expect(sorted.request.pageIndex, 0);
    expect(_hasSelection(tester), isTrue);

    await tester.tap(find.text('Submitted'));
    await tester.pumpAndSettle();

    expect(repository.pageCalls.last.sort, FeedbackSort.newestFirst);
  });

  testWidgets('the details column cannot be sorted', (
    WidgetTester tester,
  ) async {
    final _FakeFeedbackRepository repository = _FakeFeedbackRepository(3);
    await _openDialog(tester, repository);

    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();

    expect(repository.pageCalls, hasLength(1));
  });

  testWidgets(
    'search and filters reload from the first page and clear the selection',
    (WidgetTester tester) async {
      final _FakeFeedbackRepository repository = _FakeFeedbackRepository(45);
      await _openDialog(tester, repository);

      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      await _tapRow(tester, 'FBK0000021');
      expect(_hasSelection(tester), isTrue);

      await tester.enterText(
        find.descendant(
          of: find.byType(AppSearchBar),
          matching: find.byType(TextField),
        ),
        'printer',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(repository.pageCalls.last.filters.search, 'printer');
      expect(repository.pageCalls.last.request.pageIndex, 0);
      expect(_hasSelection(tester), isFalse);

      final AppSearchBar searchBar = tester.widget<AppSearchBar>(
        find.byType(AppSearchBar),
      );
      expect(searchBar.enableDateFilter, isTrue);
      expect(searchBar.dateFilterSection, 'Report');
      expect(searchBar.loadFilterGroups, isNotNull);
      // Without stored values only the filters the app itself knows remain.
      expect(
        searchBar.filterGroups.map((AppSearchBarFilterGroup group) => group.key),
        <String>['category', 'submitter_type', 'device_type'],
      );

      searchBar.onFilterChanged!(
        AppSearchBarFilterValue(
          dateFrom: DateTime(2026, 9, 2),
          dateTo: DateTime(2026, 9, 14),
          options: const <String, String>{'submitter_type': 'ANONYMOUS'},
          selections: const <String, Set<String>>{
            'category': <String>{'PROBLEM', 'COMPLAINT'},
            'device_type': <String>{'MOBILE'},
            'platform': <String>{'android'},
            'tenant_id': <String>{'TEN-9322E26AFD'},
            'route_name': <String>{'hr'},
            'breakpoint': <String>{'xl'},
          },
        ),
      );
      await tester.pumpAndSettle();

      final FeedbackFilters filters = repository.pageCalls.last.filters;
      expect(filters.search, 'printer');
      expect(filters.categories, <FeedbackCategory>{
        FeedbackCategory.problem,
        FeedbackCategory.complaint,
      });
      expect(filters.submitterType, FeedbackSubmitterType.anonymous);
      expect(filters.deviceTypes, <FeedbackDeviceType>{
        FeedbackDeviceType.mobile,
      });
      expect(filters.values, <FeedbackFilterDimension, Set<String>>{
        FeedbackFilterDimension.platform: <String>{'android'},
        FeedbackFilterDimension.tenant: <String>{'TEN-9322E26AFD'},
        FeedbackFilterDimension.routeName: <String>{'hr'},
        FeedbackFilterDimension.breakpoint: <String>{'xl'},
      });
      expect(filters.submittedFrom, DateTime(2026, 9, 2));
      expect(filters.submittedTo, DateTime(2026, 9, 14));
      expect(repository.pageCalls.last.request.pageIndex, 0);
    },
  );

  testWidgets('filter choices come from stored values, grouped in sections', (
    WidgetTester tester,
  ) async {
    final _FakeFeedbackRepository repository = _FakeFeedbackRepository(3);
    await _openDialog(tester, repository);

    await _openFilters(tester);

    expect(repository.facetCalls, hasLength(1));
    expect(repository.facetCalls.single.hasActiveFilters, isFalse);
    for (final String section in <String>['Report', 'Who', 'Where', 'Device']) {
      expect(find.text(section), findsOneWidget);
    }
    // Tenants read by name, with the public id and record count beneath.
    expect(
      find.widgetWithText(CheckboxListTile, 'DemoCare General Hospital'),
      findsOneWidget,
    );
    expect(find.text('TEN-9322E26AFD · 40 records'), findsOneWidget);
    // Raw values get readable names.
    expect(
      find.widgetWithText(CheckboxListTile, 'Extra large'),
      findsOneWidget,
    );
    expect(find.text('xl · 40 records'), findsOneWidget);
    expect(
      find.widgetWithText(CheckboxListTile, 'Platform admin'),
      findsOneWidget,
    );
    // Platforms are the stored ones, not a fixed list.
    expect(find.widgetWithText(CheckboxListTile, 'Web'), findsOneWidget);
    expect(find.widgetWithText(CheckboxListTile, 'Android'), findsNothing);
    // Categories nobody used and filters with no stored values are hidden.
    expect(find.widgetWithText(CheckboxListTile, 'Complaint'), findsNothing);
    expect(find.text('App version'), findsNothing);
    expect(find.text('Connectivity'), findsNothing);

    // Tenants can be searched by name or id.
    await tester.enterText(
      find.descendant(
        of: find.ancestor(
          of: find.text('Search tenants'),
          matching: find.byType(AppTextField),
        ),
        matching: find.byType(TextField),
      ),
      'ihk',
    );
    await tester.pump();
    expect(find.widgetWithText(CheckboxListTile, 'IHK Group'), findsOneWidget);
    expect(
      find.widgetWithText(CheckboxListTile, 'DemoCare General Hospital'),
      findsNothing,
    );
  });

  testWidgets(
    'tenant, screen, and breakpoint filters narrow the list and its choices',
    (WidgetTester tester) async {
      final _FakeFeedbackRepository repository = _FakeFeedbackRepository(3);
      await _openDialog(tester, repository);

      await _openFilters(tester);
      await _tickFilterChoice(tester, 'DemoCare General Hospital');
      await _tickFilterChoice(tester, 'Hr');
      await _tickFilterChoice(tester, 'Extra large');
      await tester.tap(find.text('Apply filters'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      final _PageCall call = repository.pageCalls.last;
      expect(call.request.pageIndex, 0);
      expect(call.filters.values, <FeedbackFilterDimension, Set<String>>{
        FeedbackFilterDimension.tenant: <String>{'TEN-9322E26AFD'},
        FeedbackFilterDimension.routeName: <String>{'hr'},
        FeedbackFilterDimension.breakpoint: <String>{'xl'},
      });
      // One per picked value.
      final AppSearchBar searchBar = tester.widget<AppSearchBar>(
        find.byType(AppSearchBar),
      );
      expect(searchBar.filterValue.activeCount, 3);

      // Reopening counts choices under the applied filters, still ticked.
      await _openFilters(tester, active: 3);
      expect(repository.facetCalls, hasLength(2));
      expect(
        repository.facetCalls.last.valuesFor(FeedbackFilterDimension.routeName),
        <String>{'hr'},
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Extra large'),
            )
            .value,
        isTrue,
      );
    },
  );

  testWidgets('filters fall back to basic choices when values fail to load', (
    WidgetTester tester,
  ) async {
    final _FakeFeedbackRepository repository = _FakeFeedbackRepository(3)
      ..facetsFail = true;
    await _openDialog(tester, repository);

    await _openFilters(tester);

    expect(
      find.textContaining('Filter choices could not be loaded'),
      findsOneWidget,
    );
    expect(find.widgetWithText(CheckboxListTile, 'Complaint'), findsOneWidget);
    expect(find.text('Who'), findsNothing);
  });

  testWidgets('shows an empty state when nothing matches', (
    WidgetTester tester,
  ) async {
    await _openDialog(tester, _FakeFeedbackRepository(0));

    expect(
      find.text('No stored feedback matches the search and filters.'),
      findsOneWidget,
    );
  });

  testWidgets('offers a retry when feedback fails to load', (
    WidgetTester tester,
  ) async {
    final _FakeFeedbackRepository repository = _FakeFeedbackRepository(2)
      ..failuresRemaining = 1;
    await _openDialog(tester, repository);

    expect(find.byType(AppFormInformationBanner), findsOneWidget);
    await tester.tap(find.widgetWithText(AppButton, 'Try again'));
    await tester.pumpAndSettle();

    expect(repository.pageCalls, hasLength(2));
    expect(find.text('Feedback message 1'), findsOneWidget);
    expect(find.byType(AppFormInformationBanner), findsNothing);
  });

  testWidgets('closing without deleting resolves to null', (
    WidgetTester tester,
  ) async {
    final _FakeFeedbackRepository repository = _FakeFeedbackRepository(2);
    int? result = -1;
    await _openDialog(
      tester,
      repository,
      onResult: (int? value) => result = value,
    );

    await _tapRow(tester, 'FBK0000001');
    await tester.tap(
      find.descendant(
        of: find.byType(FeedbackDeleteDialog),
        matching: find.widgetWithText(AppButton, 'Close'),
      ),
    );
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(repository.deletedIds, isEmpty);
    expect(repository.deletedMatching, isEmpty);
  });
}
