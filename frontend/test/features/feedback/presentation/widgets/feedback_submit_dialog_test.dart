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
import 'package:hosspi_hms/features/feedback/presentation/controllers/feedback_draft_controller.dart';
import 'package:hosspi_hms/features/feedback/presentation/widgets/feedback_screenshot_strip.dart';
import 'package:hosspi_hms/features/feedback/presentation/widgets/feedback_submit_dialog.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/shared/components/components.dart';
import 'package:hosspi_hms/shared/data/app_pagination.dart';

final class _ScriptedFeedbackRepository implements FeedbackRepository {
  _ScriptedFeedbackRepository({this.failure});

  final AppFailure? failure;
  final List<({FeedbackSubmission submission, bool signedIn})> submissions =
      <({FeedbackSubmission submission, bool signedIn})>[];

  @override
  Future<Result<FeedbackReceipt>> submitFeedback(
    FeedbackSubmission submission, {
    required bool signedIn,
  }) async {
    submissions.add((submission: submission, signedIn: signedIn));
    final AppFailure? scriptedFailure = failure;
    if (scriptedFailure != null) {
      return Result<FeedbackReceipt>.failure(scriptedFailure);
    }
    return const Result<FeedbackReceipt>.success(
      FeedbackReceipt(
        referenceId: 'FBK0000002',
        submitterType: FeedbackSubmitterType.authenticated,
      ),
    );
  }

  @override
  Future<Result<AppPage<FeedbackRecord>>> fetchFeedbackPage({
    required FeedbackFilters filters,
    required AppPageRequest request,
    FeedbackSort sort = FeedbackSort.newestFirst,
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

  @override
  Future<Result<FeedbackDeleteResult>> deleteFeedback({
    required Set<String> referenceIds,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<FeedbackFacets>> fetchFeedbackFacets({
    required FeedbackFilters filters,
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
  Future<Result<List<FeedbackStoredScreenshot>>> fetchFeedbackScreenshots({
    required String referenceId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<Uint8List>> fetchFeedbackScreenshotImage({
    required String referenceId,
    required String screenshotId,
  }) {
    throw UnimplementedError();
  }
}

const FeedbackContext _billingContext = FeedbackContext(
  routePath: '/billing?tab=invoices',
  routeName: 'billing',
);

/// A 1x1 PNG, enough for `Image.memory` to paint a thumbnail.
final Uint8List _pngBytes = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, //
  0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
  0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
  0x42, 0x60, 0x82,
]);

FeedbackScreenshot _screenshot({
  String routeName = 'billing',
  String screenTitle = 'Billing',
}) {
  return FeedbackScreenshot(
    bytes: _pngBytes,
    contentType: 'image/png',
    screen: FeedbackScreenReference(
      routeName: routeName,
      routePath: '/$routeName',
      screenTitle: screenTitle,
    ),
    capturedAt: DateTime(2026, 9, 20, 10, 30),
  );
}

Future<ProviderContainer> _openDialog(
  WidgetTester tester, {
  required _ScriptedFeedbackRepository repository,
  bool signedIn = false,
  List<FeedbackScreenshot> screenshots = const <FeedbackScreenshot>[],
  ValueChanged<FeedbackSubmitOutcome?>? onResult,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 1400);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final ProviderContainer container = ProviderContainer(
    overrides: [feedbackRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  // The form reads the draft the control started for it.
  container
      .read(feedbackDraftProvider.notifier)
      .start(context: _billingContext, signedIn: signedIn);
  for (final FeedbackScreenshot screenshot in screenshots) {
    container.read(feedbackDraftProvider.notifier).addScreenshot(screenshot);
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) {
              return TextButton(
                onPressed: () async {
                  final FeedbackSubmitOutcome? outcome =
                      await showAppDialog<FeedbackSubmitOutcome>(
                        context: context,
                        builder: (_) => const FeedbackSubmitDialog(),
                      );
                  onResult?.call(outcome);
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
  return container;
}

/// Scrolls a control of the form into view before tapping it: the form is
/// taller than a phone screen once it carries screenshots.
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder get _messageField => find.descendant(
  of: find.byType(FeedbackSubmitDialog),
  matching: find.byType(TextFormField),
);

Finder _typeOption(String label) =>
    find.widgetWithText(AppCheckboxField, label);

/// Labels of the checkboxes that render as checked.
List<String> _checkedTypes(WidgetTester tester) {
  return tester
      .widgetList<CheckboxListTile>(
        find.descendant(
          of: find.byType(FeedbackSubmitDialog),
          matching: find.byType(CheckboxListTile),
        ),
      )
      .where((CheckboxListTile tile) => tile.value ?? false)
      .map((CheckboxListTile tile) => (tile.title! as Text).data!)
      .toList(growable: false);
}

void main() {
  testWidgets(
    'shows every feedback type as a checkbox with one checked at a time',
    (WidgetTester tester) async {
      await _openDialog(tester, repository: _ScriptedFeedbackRepository());

      expect(find.byType(AppSelectField<FeedbackCategory>), findsNothing);
      for (final String label in <String>[
        'General feedback',
        'Problem',
        'Complaint',
        'Suggestion',
        'Improvement',
      ]) {
        expect(_typeOption(label), findsOneWidget);
      }
      expect(_checkedTypes(tester), <String>['General feedback']);

      await tester.tap(_typeOption('Problem'));
      await tester.pump();
      expect(_checkedTypes(tester), <String>['Problem']);

      // Tapping the checked type keeps it checked.
      await tester.tap(_typeOption('Problem'));
      await tester.pump();
      expect(_checkedTypes(tester), <String>['Problem']);
    },
  );

  testWidgets('requires feedback details before sending', (
    WidgetTester tester,
  ) async {
    final _ScriptedFeedbackRepository repository =
        _ScriptedFeedbackRepository();
    await _openDialog(tester, repository: repository);

    await tester.tap(find.widgetWithText(AppButton, 'Send feedback'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your feedback.'), findsOneWidget);

    await tester.enterText(_messageField, 'ok');
    await tester.tap(find.widgetWithText(AppButton, 'Send feedback'));
    await tester.pumpAndSettle();
    expect(find.text('Enter at least 3 characters.'), findsOneWidget);

    expect(repository.submissions, isEmpty);
    expect(find.byType(FeedbackSubmitDialog), findsOneWidget);
  });

  testWidgets('sends the checked type and returns the receipt', (
    WidgetTester tester,
  ) async {
    final _ScriptedFeedbackRepository repository =
        _ScriptedFeedbackRepository();
    FeedbackSubmitOutcome? outcome;
    final ProviderContainer container = await _openDialog(
      tester,
      repository: repository,
      signedIn: true,
      onResult: (FeedbackSubmitOutcome? value) => outcome = value,
    );

    await tester.tap(_typeOption('Complaint'));
    await tester.pump();

    await tester.enterText(_messageField, '  Invoices print twice  ');
    await tester.tap(find.widgetWithText(AppButton, 'Send feedback'));
    await tester.pumpAndSettle();

    final ({FeedbackSubmission submission, bool signedIn}) sent =
        repository.submissions.single;
    expect(sent.signedIn, isTrue);
    expect(sent.submission.category, FeedbackCategory.complaint);
    expect(sent.submission.message, 'Invoices print twice');
    expect(sent.submission.context.routeName, 'billing');
    // Feedback is about the screen it was raised from unless it says so.
    expect(sent.submission.scope, FeedbackScope.screen);
    expect(outcome?.receipt?.referenceId, 'FBK0000002');
    expect(find.byType(FeedbackSubmitDialog), findsNothing);
    // A sent draft is finished with.
    expect(container.read(feedbackDraftProvider), isNull);
  });

  testWidgets('keeps the dialog and message when sending fails', (
    WidgetTester tester,
  ) async {
    final _ScriptedFeedbackRepository repository = _ScriptedFeedbackRepository(
      failure: const AppFailure.network(),
    );
    await _openDialog(tester, repository: repository);

    await tester.enterText(_messageField, 'Cannot print invoices');
    await tester.tap(find.widgetWithText(AppButton, 'Send feedback'));
    await tester.pumpAndSettle();

    expect(repository.submissions, hasLength(1));
    expect(find.byType(FeedbackSubmitDialog), findsOneWidget);
    expect(find.text('Cannot print invoices'), findsOneWidget);
    expect(find.byType(AppFormInformationBanner), findsOneWidget);
    final AppButton sendButton = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'Send feedback'),
    );
    expect(sendButton.isLoading, isFalse);
  });

  testWidgets('asks what the feedback applies to, this screen by default', (
    WidgetTester tester,
  ) async {
    final _ScriptedFeedbackRepository repository =
        _ScriptedFeedbackRepository();
    final ProviderContainer container = await _openDialog(
      tester,
      repository: repository,
    );

    expect(find.text('What does this apply to?'), findsOneWidget);
    expect(
      container.read(feedbackDraftProvider)?.scope,
      FeedbackScope.screen,
    );

    await tester.tap(find.text('The whole app'));
    await tester.pumpAndSettle();
    expect(container.read(feedbackDraftProvider)?.scope, FeedbackScope.app);

    await tester.enterText(_messageField, 'Slow everywhere');
    await tester.tap(find.widgetWithText(AppButton, 'Send feedback'));
    await tester.pumpAndSettle();

    expect(repository.submissions.single.submission.scope, FeedbackScope.app);
  });

  testWidgets('will not send selected screens with nothing picked', (
    WidgetTester tester,
  ) async {
    final _ScriptedFeedbackRepository repository =
        _ScriptedFeedbackRepository();
    final ProviderContainer container = await _openDialog(
      tester,
      repository: repository,
    );

    await tester.enterText(_messageField, 'Both queues are slow');
    // Picking the scope opens the picker; closing it leaves nothing picked.
    await tester.tap(find.text('Selected screens'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, 'Close').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(AppButton, 'Send feedback'));
    await tester.pumpAndSettle();

    expect(repository.submissions, isEmpty);
    expect(find.text('Pick at least one screen.'), findsOneWidget);
    expect(container.read(feedbackDraftProvider)?.message, isNotEmpty);
  });

  testWidgets('sends every attached screenshot, in capture order', (
    WidgetTester tester,
  ) async {
    final _ScriptedFeedbackRepository repository =
        _ScriptedFeedbackRepository();
    await _openDialog(
      tester,
      repository: repository,
      signedIn: true,
      screenshots: <FeedbackScreenshot>[
        _screenshot(routeName: 'billing', screenTitle: 'Billing'),
        _screenshot(routeName: 'pharmacy', screenTitle: 'Pharmacy'),
        // A second shot of one screen is kept, not merged away.
        _screenshot(routeName: 'pharmacy', screenTitle: 'Pharmacy'),
      ],
    );

    expect(find.byType(FeedbackScreenshotStrip), findsOneWidget);
    expect(find.text('3 of 10'), findsOneWidget);
    expect(find.text('1. Billing'), findsOneWidget);
    expect(find.text('2. Pharmacy'), findsOneWidget);
    expect(find.text('3. Pharmacy'), findsOneWidget);
    expect(
      find.text(
        'Screenshots can show patient data. '
        'Crop out anything that should not be sent.',
      ),
      findsOneWidget,
    );

    await tester.enterText(_messageField, 'Two screens are wrong');
    await tester.tap(find.widgetWithText(AppButton, 'Send feedback'));
    await tester.pumpAndSettle();

    final FeedbackSubmission sent = repository.submissions.single.submission;
    expect(sent.screenshots, hasLength(3));
    expect(
      sent.screenshots
          .map((FeedbackScreenshot shot) => shot.screen.routeName)
          .toList(),
      <String>['billing', 'pharmacy', 'pharmacy'],
    );
    // Capturing other screens says the feedback is about them too.
    expect(sent.scope, FeedbackScope.screens);
    expect(
      sent.screens.map((FeedbackScreenReference screen) => screen.routeName),
      containsAll(<String>['billing', 'pharmacy']),
    );
  });

  testWidgets('removes a screenshot from the strip', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await _openDialog(
      tester,
      repository: _ScriptedFeedbackRepository(),
      signedIn: true,
      screenshots: <FeedbackScreenshot>[
        _screenshot(routeName: 'billing', screenTitle: 'Billing'),
        _screenshot(routeName: 'pharmacy', screenTitle: 'Pharmacy'),
      ],
    );

    await _tapVisible(tester, find.byKey(FeedbackScreenshotStrip.removeKey(1)));

    expect(container.read(feedbackDraftProvider)?.screenshots, hasLength(1));
    expect(find.text('1. Pharmacy'), findsOneWidget);
    expect(find.text('1 of 10'), findsOneWidget);
  });

  testWidgets('leaves to capture another screen with the draft intact', (
    WidgetTester tester,
  ) async {
    FeedbackSubmitOutcome? outcome;
    final ProviderContainer container = await _openDialog(
      tester,
      repository: _ScriptedFeedbackRepository(),
      signedIn: true,
      onResult: (FeedbackSubmitOutcome? value) => outcome = value,
    );

    await tester.tap(_typeOption('Problem'));
    await tester.pump();
    await tester.enterText(_messageField, 'Look at the next screen too');
    await _tapVisible(
      tester,
      find.byKey(FeedbackSubmitDialog.captureAnotherScreenKey),
    );

    expect(find.byType(FeedbackSubmitDialog), findsNothing);
    expect(outcome?.capturesMoreScreens, isTrue);
    final FeedbackDraft draft = container.read(feedbackDraftProvider)!;
    expect(draft.isCapturing, isTrue);
    expect(draft.message, 'Look at the next screen too');
    expect(draft.category, FeedbackCategory.problem);
  });

  testWidgets('anonymous reporters get the lower screenshot limit', (
    WidgetTester tester,
  ) async {
    await _openDialog(
      tester,
      repository: _ScriptedFeedbackRepository(),
      screenshots: <FeedbackScreenshot>[_screenshot()],
    );

    expect(find.text('1 of 3'), findsOneWidget);
  });
}
