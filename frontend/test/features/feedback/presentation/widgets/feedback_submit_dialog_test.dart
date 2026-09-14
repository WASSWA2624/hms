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
import 'package:hosspi_hms/features/feedback/presentation/widgets/feedback_submit_dialog.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/shared/components/components.dart';

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
  Future<Result<FeedbackSummary>> fetchFeedbackSummary() {
    throw UnimplementedError();
  }

  @override
  Future<Result<Uint8List>> downloadFeedbackExport({
    required int utcOffsetMinutes,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<FeedbackClearResult>> clearFeedback() {
    throw UnimplementedError();
  }
}

Future<void> _openDialog(
  WidgetTester tester, {
  required _ScriptedFeedbackRepository repository,
  bool signedIn = false,
  ValueChanged<FeedbackReceipt?>? onResult,
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
                  final FeedbackReceipt? receipt =
                      await showAppDialog<FeedbackReceipt>(
                        context: context,
                        builder: (_) => FeedbackSubmitDialog(
                          feedbackContext: const FeedbackContext(
                            routePath: '/billing?tab=invoices',
                            routeName: 'billing',
                          ),
                          signedIn: signedIn,
                        ),
                      );
                  onResult?.call(receipt);
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

      expect(find.text('Sent with your feedback'), findsNothing);
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
    FeedbackReceipt? receipt;
    await _openDialog(
      tester,
      repository: repository,
      signedIn: true,
      onResult: (FeedbackReceipt? value) => receipt = value,
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
    expect(receipt?.referenceId, 'FBK0000002');
    expect(find.byType(FeedbackSubmitDialog), findsNothing);
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
}
