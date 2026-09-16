import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hosspi_hms/app/theme/app_theme.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/features/feedback/data/repositories/feedback_repository_impl.dart';
import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';
import 'package:hosspi_hms/features/feedback/domain/repositories/feedback_repository.dart';
import 'package:hosspi_hms/features/feedback/presentation/widgets/feedback_delete_dialog.dart';
import 'package:hosspi_hms/features/feedback/presentation/widgets/feedback_download_dialog.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/shared/components/components.dart';
import 'package:hosspi_hms/shared/data/app_pagination.dart';

final class _FakeFeedbackRepository implements FeedbackRepository {
  final List<FeedbackFilters> pageFilters = <FeedbackFilters>[];
  final List<FeedbackFilters> facetFilters = <FeedbackFilters>[];

  @override
  Future<Result<AppPage<FeedbackRecord>>> fetchFeedbackPage({
    required FeedbackFilters filters,
    required AppPageRequest request,
    FeedbackSort sort = FeedbackSort.newestFirst,
  }) async {
    pageFilters.add(filters);
    return Result<AppPage<FeedbackRecord>>.success(
      AppPage<FeedbackRecord>(
        items: <FeedbackRecord>[
          FeedbackRecord(
            referenceId: 'FBK0000001',
            category: FeedbackCategory.suggestion,
            submitterType: FeedbackSubmitterType.authenticated,
            messagePreview: 'Filter the download',
            submittedAt: DateTime(2026, 9, 15, 10, 13),
          ),
        ],
        request: request,
        totalItemCount: 1,
      ),
    );
  }

  @override
  Future<Result<FeedbackFacets>> fetchFeedbackFacets({
    required FeedbackFilters filters,
  }) async {
    facetFilters.add(filters);
    return const Result<FeedbackFacets>.success(
      FeedbackFacets(
        total: 20,
        categories: <FeedbackFacetValue>[
          FeedbackFacetValue(value: 'SUGGESTION', count: 20),
        ],
        values: <FeedbackFilterDimension, List<FeedbackFacetValue>>{
          FeedbackFilterDimension.tenant: <FeedbackFacetValue>[
            FeedbackFacetValue(
              value: 'TEN-9322E26AFD',
              label: 'DemoCare General Hospital',
              count: 19,
            ),
          ],
          FeedbackFilterDimension.routeName: <FeedbackFacetValue>[
            FeedbackFacetValue(value: 'hr', count: 6),
          ],
          FeedbackFilterDimension.breakpoint: <FeedbackFacetValue>[
            FeedbackFacetValue(value: 'xl', count: 18),
          ],
        },
      ),
    );
  }

  @override
  Future<Result<Uint8List>> downloadFeedbackExport({
    required int utcOffsetMinutes,
    Set<String> referenceIds = const <String>{},
    FeedbackFilters filters = FeedbackFilters.none,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<FeedbackDeleteResult>> deleteFeedback({
    required Set<String> referenceIds,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<FeedbackDeleteResult>> deleteMatchingFeedback({
    required FeedbackFilters filters,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<FeedbackReceipt>> submitFeedback(
    FeedbackSubmission submission, {
    required bool signedIn,
  }) {
    throw UnimplementedError();
  }
}

Future<void> _pumpOpener(
  WidgetTester tester,
  _FakeFeedbackRepository repository, {
  required Future<void> Function(BuildContext context) open,
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
            builder: (BuildContext context) => TextButton(
              onPressed: () => open(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _pickFilters(WidgetTester tester, List<String> labels) async {
  await tester.tap(find.byTooltip('Filters'));
  await tester.pumpAndSettle();
  for (final String label in labels) {
    final Finder choice = find.widgetWithText(CheckboxListTile, label);
    await tester.ensureVisible(choice);
    await tester.pumpAndSettle();
    await tester.tap(choice);
    await tester.pump();
  }
  await tester.tap(find.text('Apply filters'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

const Map<FeedbackFilterDimension, Set<String>> _pickedValues =
    <FeedbackFilterDimension, Set<String>>{
      FeedbackFilterDimension.tenant: <String>{'TEN-9322E26AFD'},
      FeedbackFilterDimension.routeName: <String>{'hr'},
      FeedbackFilterDimension.breakpoint: <String>{'xl'},
    };

void main() {
  testWidgets(
    'downloads every record matching tenant, screen, and breakpoint filters',
    (WidgetTester tester) async {
      final _FakeFeedbackRepository repository = _FakeFeedbackRepository();
      FeedbackExportRequest? request;
      await _pumpOpener(
        tester,
        repository,
        open: (BuildContext context) async {
          request = await showFeedbackDownloadDialog(context: context);
        },
      );

      await _pickFilters(tester, <String>[
        'DemoCare General Hospital',
        'Hr',
        'Extra large',
      ]);
      expect(repository.pageFilters.last.values, _pickedValues);

      await tester.tap(
        find.descendant(
          of: find.byType(FeedbackDownloadDialog),
          matching: find.widgetWithText(AppButton, 'Download'),
        ),
      );
      await tester.pumpAndSettle();

      expect(request, isNotNull);
      expect(request!.referenceIds, isEmpty);
      expect(request!.filters.values, _pickedValues);
    },
  );

  testWidgets('Clear offers and applies the same filters as Download', (
    WidgetTester tester,
  ) async {
    final _FakeFeedbackRepository repository = _FakeFeedbackRepository();
    await _pumpOpener(
      tester,
      repository,
      open: (BuildContext context) =>
          showFeedbackDeleteDialog(context: context),
    );

    await _pickFilters(tester, <String>[
      'DemoCare General Hospital',
      'Hr',
      'Extra large',
    ]);

    expect(repository.facetFilters, hasLength(1));
    expect(repository.pageFilters.last.values, _pickedValues);
    expect(find.text('1-1 of 1'), findsOneWidget);
  });
}
