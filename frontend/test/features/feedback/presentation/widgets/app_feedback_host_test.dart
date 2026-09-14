import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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

Future<GoRouter> _pumpHost(
  WidgetTester tester, {
  required SessionState session,
  required _FakeFeedbackRepository repository,
  Size size = const Size(1280, 900),
  List<_SavedFile>? savedFiles,
}) async {
  setTestViewport(tester, size);
  final GoRouter router = GoRouter(
    initialLocation: '/patients?tab=registry',
    routes: <RouteBase>[
      GoRoute(
        path: '/patients',
        name: 'patients',
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('Patients page'))),
      ),
      GoRoute(
        path: '/billing',
        name: 'billing',
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('Billing page'))),
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
  return router;
}

Finder get _launcher => find.byKey(AppFeedbackHost.launcherKey);

Finder get _messageField => find.descendant(
  of: find.byType(FeedbackSubmitDialog),
  matching: find.byType(TextFormField),
);

Future<void> _openLauncher(WidgetTester tester) async {
  await tester.tap(_launcher);
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
      expect(tester.getSize(_launcher).height, lessThanOrEqualTo(40));

      await _openLauncher(tester);

      expect(find.byType(FeedbackSubmitDialog), findsOneWidget);
      expect(find.text('GIVE US FEEDBACK'), findsOneWidget);
      expect(find.text('Download feedback'), findsNothing);
      // The control stays on top of the open form but does not open another.
      expect(_launcher.hitTestable(), findsOneWidget);
      await tester.tap(_launcher);
      await tester.pumpAndSettle();
      expect(find.byType(FeedbackSubmitDialog), findsOneWidget);

      await tester.enterText(_messageField, 'The save button does nothing');
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
      expect(sent.submission.context.deviceType, FeedbackDeviceType.desktop);
      expect(sent.submission.context.viewportWidth, 1280);
      expect(sent.submission.context.screenWidth, isNotNull);
      expect(
        find.text('Thank you. Your feedback was sent (reference FBK0000001).'),
        findsOneWidget,
      );
      expect(_launcher.hitTestable(), findsOneWidget);
    },
  );

  testWidgets('stays on top of other modal dialogs and opens feedback over them', (
    WidgetTester tester,
  ) async {
    final GoRouter router = await _pumpHost(
      tester,
      session: const SessionState.unauthenticated(),
      repository: _FakeFeedbackRepository(),
    );

    unawaited(
      showDialog<void>(
        context: router.routerDelegate.navigatorKey.currentContext!,
        builder: (_) => const Dialog.fullscreen(
          child: Center(child: Text('Register new patient')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Register new patient'), findsOneWidget);
    expect(_launcher.hitTestable(), findsOneWidget);

    await _openLauncher(tester);

    expect(find.byType(FeedbackSubmitDialog), findsOneWidget);
    expect(find.text('Register new patient'), findsOneWidget);
    expect(_launcher.hitTestable(), findsOneWidget);
  });

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
      // The menu opens beside the control, which stays painted on top.
      final Rect launcherRect = tester.getRect(_launcher);
      for (final String item in <String>[
        'Give us feedback',
        'Download feedback',
        'Clear feedback',
      ]) {
        expect(tester.getRect(find.text(item)).overlaps(launcherRect), isFalse);
      }
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

    await tester.enterText(_messageField, 'Please add bulk discharge');
    await tester.tap(find.widgetWithText(AppButton, 'Send feedback'));
    await tester.pumpAndSettle();

    expect(repository.submissions.single.signedIn, isTrue);
    expect(
      repository.submissions.single.submission.context.sessionStatus,
      'authenticated',
    );
  });

  testWidgets('dragging moves the button and keeps its place for the session', (
    WidgetTester tester,
  ) async {
    final GoRouter router = await _pumpHost(
      tester,
      session: const SessionState.unauthenticated(),
      repository: _FakeFeedbackRepository(),
    );
    final Offset start = tester.getTopLeft(_launcher);

    await tester.drag(_launcher, const Offset(-400, -300));
    await tester.pumpAndSettle();

    final Offset moved = tester.getTopLeft(_launcher);
    expect(
      moved,
      offsetMoreOrLessEquals(start + const Offset(-400, -300), epsilon: 1),
    );
    // A drag is not a tap.
    expect(find.byType(FeedbackSubmitDialog), findsNothing);

    router.go('/billing');
    await tester.pumpAndSettle();

    expect(find.text('Billing page'), findsOneWidget);
    expect(tester.getTopLeft(_launcher), offsetMoreOrLessEquals(moved));

    await _openLauncher(tester);
    expect(find.byType(FeedbackSubmitDialog), findsOneWidget);
  });

  testWidgets('the button stays on screen however far it is dragged', (
    WidgetTester tester,
  ) async {
    await _pumpHost(
      tester,
      session: const SessionState.unauthenticated(),
      repository: _FakeFeedbackRepository(),
    );

    await tester.drag(_launcher, const Offset(3000, 3000));
    await tester.pumpAndSettle();
    Rect rect = tester.getRect(_launcher);
    expect(rect.right, lessThanOrEqualTo(1280));
    expect(rect.bottom, lessThanOrEqualTo(900));

    await tester.drag(_launcher, const Offset(-5000, -5000));
    await tester.pumpAndSettle();
    rect = tester.getRect(_launcher);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.top, greaterThanOrEqualTo(0));
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
    await tester.tap(
      find.descendant(
        of: find.byType(AppConfirmActionDialog),
        matching: find.widgetWithText(AppButton, 'Close'),
      ),
    );
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

  testWidgets('shows a small icon-only control at phone width', (
    WidgetTester tester,
  ) async {
    final _FakeFeedbackRepository repository = _FakeFeedbackRepository();
    await _pumpHost(
      tester,
      session: const SessionState.unauthenticated(),
      repository: repository,
      size: const Size(390, 844),
    );

    expect(_launcher, findsOneWidget);
    expect(find.text('Feedback'), findsNothing);
    final Size launcherSize = tester.getSize(_launcher);
    expect(launcherSize.width, lessThanOrEqualTo(40));
    expect(launcherSize.height, lessThanOrEqualTo(40));
    final Icon launcherIcon = tester.widget<Icon>(
      find.descendant(of: _launcher, matching: find.byType(Icon)),
    );
    expect(launcherIcon.semanticLabel, 'Give us feedback');

    await _openLauncher(tester);
    await tester.enterText(_messageField, 'Table is cut off on my phone');
    await tester.tap(find.widgetWithText(AppButton, 'Send feedback'));
    await tester.pumpAndSettle();

    expect(
      repository.submissions.single.submission.context.deviceType,
      FeedbackDeviceType.mobile,
    );
  });
}
