import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hosspi_hms/app/router/app_popup_route_tracker.dart';
import 'package:hosspi_hms/app/theme/app_theme.dart';
import 'package:hosspi_hms/core/config/app_config_provider.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/network/app_connectivity_status.dart';
import 'package:hosspi_hms/core/security/auth_session.dart';
import 'package:hosspi_hms/core/security/session_controller.dart';
import 'package:hosspi_hms/core/security/session_state.dart';
import 'package:hosspi_hms/core/security/session_tokens.dart';
import 'package:hosspi_hms/features/feedback/data/repositories/feedback_repository_impl.dart';
import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';
import 'package:hosspi_hms/features/feedback/domain/repositories/feedback_repository.dart';
import 'package:hosspi_hms/features/feedback/presentation/widgets/app_feedback_host.dart';
import 'package:hosspi_hms/features/feedback/presentation/widgets/feedback_submit_dialog.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/shared/actions/app_action_dialogs.dart';
import 'package:hosspi_hms/shared/components/components.dart';

import '../../../../helpers/test_harness.dart';

typedef _SavedFile = ({Uint8List bytes, String fileName});

final class _FakeFeedbackRepository implements FeedbackRepository {
  final List<({FeedbackSubmission submission, bool signedIn})> submissions =
      <({FeedbackSubmission submission, bool signedIn})>[];
  final List<int> exportOffsets = <int>[];
  final Uint8List exportBytes = Uint8List.fromList(<int>[80, 75, 3, 4]);
  FeedbackSummary summary = const FeedbackSummary(
    total: 3,
    authenticated: 2,
    anonymous: 1,
  );
  int clearCalls = 0;

  @override
  Future<Result<FeedbackReceipt>> submitFeedback(
    FeedbackSubmission submission, {
    required bool signedIn,
  }) async {
    submissions.add((submission: submission, signedIn: signedIn));
    return Result<FeedbackReceipt>.success(
      FeedbackReceipt(
        referenceId: 'FBK0000001',
        submitterType: signedIn
            ? FeedbackSubmitterType.authenticated
            : FeedbackSubmitterType.anonymous,
      ),
    );
  }

  @override
  Future<Result<FeedbackSummary>> fetchFeedbackSummary() async {
    return Result<FeedbackSummary>.success(summary);
  }

  @override
  Future<Result<Uint8List>> downloadFeedbackExport({
    required int utcOffsetMinutes,
  }) async {
    exportOffsets.add(utcOffsetMinutes);
    return Result<Uint8List>.success(exportBytes);
  }

  @override
  Future<Result<FeedbackClearResult>> clearFeedback() async {
    clearCalls += 1;
    return Result<FeedbackClearResult>.success(
      FeedbackClearResult(clearedCount: summary.total),
    );
  }
}

SessionState _signedInAs(String role) {
  return SessionState.authenticated(
    session: AuthSession(
      tokens: SessionTokens(accessToken: 'test-access-token'),
      user: AuthUserProfile(
        id: 'user-1',
        email: 'user@example.com',
        tenantId: 'tenant-1',
        roles: <String>[role],
      ),
    ),
  );
}

Future<void> _pumpHost(
  WidgetTester tester, {
  required SessionState session,
  required _FakeFeedbackRepository repository,
  Size size = const Size(1280, 900),
  List<_SavedFile>? savedFiles,
}) async {
  setTestViewport(tester, size);
  final AppPopupRouteTracker tracker = AppPopupRouteTracker();
  addTearDown(tracker.dispose);
  final GoRouter router = GoRouter(
    initialLocation: '/patients?tab=registry',
    observers: <NavigatorObserver>[tracker.createObserver()],
    routes: <RouteBase>[
      GoRoute(
        path: '/patients',
        name: 'patients',
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('Patients page'))),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig()),
        initialSessionStateProvider.overrideWithValue(session),
        feedbackRepositoryProvider.overrideWithValue(repository),
        appPopupRouteTrackerProvider.overrideWithValue(tracker),
        appConnectivityStatusProvider.overrideWith(
          (Ref ref) => Stream<AppConnectivityStatus>.value(
            AppConnectivityStatus.online,
          ),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        routerConfig: router,
        builder: (BuildContext context, Widget? child) {
          return AppFeedbackHost(
            router: router,
            saveExportFile:
                ({required Uint8List bytes, required String fileName}) async {
                  savedFiles?.add((bytes: bytes, fileName: fileName));
                  return true;
                },
            child: child!,
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openLauncher(WidgetTester tester) async {
  await tester.tap(find.byKey(AppFeedbackHost.launcherKey));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'anyone can send feedback from the floating button without signing in',
    (WidgetTester tester) async {
      final _FakeFeedbackRepository repository = _FakeFeedbackRepository();
      await _pumpHost(
        tester,
        session: const SessionState.unauthenticated(),
        repository: repository,
      );

      expect(find.text('Patients page'), findsOneWidget);
      expect(find.text('Feedback'), findsOneWidget);

      await _openLauncher(tester);

      expect(find.byType(FeedbackSubmitDialog), findsOneWidget);
      expect(find.text('GIVE US FEEDBACK'), findsOneWidget);
      expect(find.textContaining('sent anonymously'), findsOneWidget);
      expect(find.text('Download feedback'), findsNothing);
      // The floating control steps aside while the dialog owns the screen.
      expect(
        find.byKey(AppFeedbackHost.launcherKey).hitTestable(),
        findsNothing,
      );

      await tester.enterText(
        find.descendant(
          of: find.byType(FeedbackSubmitDialog),
          matching: find.byType(TextFormField),
        ),
        'The save button does nothing',
      );
      await tester.tap(find.widgetWithText(AppButton, 'Send feedback'));
      await tester.pumpAndSettle();

      expect(find.byType(FeedbackSubmitDialog), findsNothing);
      final ({FeedbackSubmission submission, bool signedIn}) sent =
          repository.submissions.single;
      expect(sent.signedIn, isFalse);
      expect(sent.submission.category, FeedbackCategory.general);
      expect(sent.submission.message, 'The save button does nothing');
      expect(sent.submission.context.routePath, '/patients?tab=registry');
      expect(sent.submission.context.routeName, 'patients');
      expect(sent.submission.context.sessionStatus, 'unauthenticated');
      expect(sent.submission.context.breakpoint, isNotNull);
      expect(
        find.text('Thank you. Your feedback was sent (reference FBK0000001).'),
        findsOneWidget,
      );
      expect(
        find.byKey(AppFeedbackHost.launcherKey).hitTestable(),
        findsOneWidget,
      );
    },
  );

  for (final String role in <String>['PLATFORM_OWNER', 'PLATFORM_ADMIN']) {
    testWidgets('$role gets give, download, and clear feedback', (
      WidgetTester tester,
    ) async {
      await _pumpHost(
        tester,
        session: _signedInAs(role),
        repository: _FakeFeedbackRepository(),
      );

      await _openLauncher(tester);

      expect(find.text('Give us feedback'), findsOneWidget);
      expect(find.text('Download feedback'), findsOneWidget);
      expect(find.text('Clear feedback'), findsOneWidget);
    });
  }

  testWidgets('other signed-in roles only get the feedback form', (
    WidgetTester tester,
  ) async {
    final _FakeFeedbackRepository repository = _FakeFeedbackRepository();
    await _pumpHost(
      tester,
      session: _signedInAs('TENANT_ADMIN'),
      repository: repository,
    );

    await _openLauncher(tester);

    expect(find.byType(FeedbackSubmitDialog), findsOneWidget);
    expect(find.text('Download feedback'), findsNothing);
    expect(find.text('Clear feedback'), findsNothing);
    expect(find.textContaining('Your account, facility'), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byType(FeedbackSubmitDialog),
        matching: find.byType(TextFormField),
      ),
      'Please add bulk discharge',
    );
    await tester.tap(find.widgetWithText(AppButton, 'Send feedback'));
    await tester.pumpAndSettle();

    expect(repository.submissions.single.signedIn, isTrue);
    expect(
      repository.submissions.single.submission.context.sessionStatus,
      'authenticated',
    );
  });

  testWidgets('download saves HOSSPI-FEEDBACK-DDMMYYYY-HHmmss.xlsx', (
    WidgetTester tester,
  ) async {
    final _FakeFeedbackRepository repository = _FakeFeedbackRepository();
    final List<_SavedFile> savedFiles = <_SavedFile>[];
    await _pumpHost(
      tester,
      session: _signedInAs('PLATFORM_ADMIN'),
      repository: repository,
      savedFiles: savedFiles,
    );

    await _openLauncher(tester);
    await tester.tap(find.text('Download feedback'));
    await tester.pumpAndSettle();

    expect(repository.exportOffsets, <int>[
      DateTime.now().timeZoneOffset.inMinutes,
    ]);
    final _SavedFile saved = savedFiles.single;
    expect(saved.bytes, repository.exportBytes);
    expect(
      saved.fileName,
      matches(RegExp(r'^HOSSPI-FEEDBACK-\d{8}-\d{6}\.xlsx$')),
    );
    expect(find.text('Feedback downloaded.'), findsOneWidget);
  });

  testWidgets('clear feedback asks for confirmation first', (
    WidgetTester tester,
  ) async {
    final _FakeFeedbackRepository repository = _FakeFeedbackRepository();
    await _pumpHost(
      tester,
      session: _signedInAs('PLATFORM_OWNER'),
      repository: repository,
    );

    await _openLauncher(tester);
    await tester.tap(find.text('Clear feedback'));
    await tester.pumpAndSettle();

    expect(find.byType(AppConfirmActionDialog), findsOneWidget);
    expect(
      find.textContaining('This clears 3 stored feedback records'),
      findsOneWidget,
    );
    expect(repository.clearCalls, 0);

    await tester.tap(find.widgetWithText(AppButton, 'Clear feedback'));
    await tester.pumpAndSettle();

    expect(repository.clearCalls, 1);
    expect(find.byType(AppConfirmActionDialog), findsNothing);
    expect(find.text('Cleared 3 feedback records.'), findsOneWidget);
  });

  testWidgets('cancelling the confirmation keeps feedback', (
    WidgetTester tester,
  ) async {
    final _FakeFeedbackRepository repository = _FakeFeedbackRepository();
    await _pumpHost(
      tester,
      session: _signedInAs('PLATFORM_OWNER'),
      repository: repository,
    );

    await _openLauncher(tester);
    await tester.tap(find.text('Clear feedback'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(repository.clearCalls, 0);
    expect(find.byType(AppConfirmActionDialog), findsNothing);
  });

  testWidgets('clear reports when there is nothing to clear', (
    WidgetTester tester,
  ) async {
    final _FakeFeedbackRepository repository = _FakeFeedbackRepository()
      ..summary = const FeedbackSummary(
        total: 0,
        authenticated: 0,
        anonymous: 0,
      );
    await _pumpHost(
      tester,
      session: _signedInAs('PLATFORM_OWNER'),
      repository: repository,
    );

    await _openLauncher(tester);
    await tester.tap(find.text('Clear feedback'));
    await tester.pumpAndSettle();

    expect(find.byType(AppConfirmActionDialog), findsNothing);
    expect(find.text('There is no stored feedback to clear.'), findsOneWidget);
    expect(repository.clearCalls, 0);
  });

  testWidgets('shows an icon-only control at phone width', (
    WidgetTester tester,
  ) async {
    await _pumpHost(
      tester,
      session: const SessionState.unauthenticated(),
      repository: _FakeFeedbackRepository(),
      size: const Size(390, 844),
    );

    expect(find.byKey(AppFeedbackHost.launcherKey), findsOneWidget);
    expect(find.text('Feedback'), findsNothing);
    expect(find.bySemanticsLabel('Give us feedback'), findsOneWidget);
  });
}
