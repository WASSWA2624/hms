import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hosspi_hms/app/theme/app_theme.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
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
import 'package:hosspi_hms/features/feedback/presentation/controllers/feedback_draft_controller.dart';
import 'package:hosspi_hms/features/feedback/presentation/feedback_capture_session.dart';
import 'package:hosspi_hms/features/feedback/presentation/widgets/app_feedback_host.dart';
import 'package:hosspi_hms/features/feedback/presentation/widgets/feedback_delete_dialog.dart';
import 'package:hosspi_hms/features/feedback/presentation/widgets/feedback_download_dialog.dart';
import 'package:hosspi_hms/features/feedback/presentation/widgets/feedback_submit_dialog.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/shared/actions/app_action_dialogs.dart';
import 'package:hosspi_hms/shared/components/components.dart';
import 'package:hosspi_hms/shared/data/app_pagination.dart';

import '../../../../helpers/test_harness.dart';

typedef _SavedFile = ({Uint8List bytes, String fileName});

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

/// Stands in for the render-to-image capture, which a widget test cannot
/// drive: it records every request and hands back a canned picture of
/// whatever screen the router is on.
final class _FakeScreenCapturer {
  _FakeScreenCapturer({this.succeeds = true});

  bool succeeds;
  final List<({String? routeName, bool hideForm})> calls =
      <({String? routeName, bool hideForm})>[];

  FeedbackScreenCapturer get capture {
    return ({
      required WidgetRef ref,
      required GoRouter router,
      required AppLocalizations l10n,
      bool hideForm = false,
    }) async {
      final String? routeName = router.state.topRoute?.name;
      calls.add((routeName: routeName, hideForm: hideForm));
      if (!succeeds) {
        return null;
      }
      return FeedbackScreenshot(
        bytes: _pngBytes,
        contentType: 'image/png',
        screen: FeedbackScreenReference(
          routeName: routeName,
          routePath: '/${routeName ?? 'unknown'}',
          screenTitle: routeName,
        ),
        capturedAt: DateTime(2026, 9, 20, 10, 30),
      );
    };
  }
}
typedef _MenuLayout = ({String name, Size size, Offset? moveTo});

final class _FakeFeedbackRepository implements FeedbackRepository {
  final List<({FeedbackSubmission submission, bool signedIn})> submissions =
      <({FeedbackSubmission submission, bool signedIn})>[];
  final List<int> exportOffsets = <int>[];
  final List<Set<String>> exportedIds = <Set<String>>[];
  final Uint8List exportBytes = Uint8List.fromList(<int>[80, 75, 3, 4]);
  final List<FeedbackRecord> records = <FeedbackRecord>[
    for (int index = 1; index <= 3; index += 1)
      FeedbackRecord(
        referenceId: 'FBK000000$index',
        category: FeedbackCategory.suggestion,
        submitterType: FeedbackSubmitterType.anonymous,
        messagePreview: 'Stored feedback $index',
      ),
  ];
  final List<Set<String>> deletedIds = <Set<String>>[];

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
  Future<Result<AppPage<FeedbackRecord>>> fetchFeedbackPage({
    required FeedbackFilters filters,
    required AppPageRequest request,
    FeedbackSort sort = FeedbackSort.newestFirst,
  }) async {
    return Result<AppPage<FeedbackRecord>>.success(
      AppPage<FeedbackRecord>(
        items: List<FeedbackRecord>.of(records),
        request: request,
        totalItemCount: records.length,
      ),
    );
  }

  @override
  Future<Result<FeedbackFacets>> fetchFeedbackFacets({
    required FeedbackFilters filters,
  }) async {
    return const Result<FeedbackFacets>.success(FeedbackFacets(total: 0));
  }

  @override
  Future<Result<Uint8List>> downloadFeedbackExport({
    required int utcOffsetMinutes,
    Set<String> referenceIds = const <String>{},
    FeedbackFilters filters = FeedbackFilters.none,
  }) async {
    exportOffsets.add(utcOffsetMinutes);
    exportedIds.add(Set<String>.of(referenceIds));
    return Result<Uint8List>.success(exportBytes);
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
    final int count = records.length;
    records.clear();
    return Result<FeedbackDeleteResult>.success(
      FeedbackDeleteResult(deletedCount: count),
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
  _FakeScreenCapturer? capturer,
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
        appConfigProvider.overrideWithValue(
          testAppConfig().copyWith(appVersion: '1.4.0+12'),
        ),
        initialSessionStateProvider.overrideWithValue(session),
        feedbackRepositoryProvider.overrideWithValue(repository),
        feedbackScreenCapturerProvider.overrideWithValue(
          (capturer ?? _FakeScreenCapturer()).capture,
        ),
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

Finder _typeOption(String label) =>
    find.widgetWithText(AppCheckboxField, label);

/// Scrolls a control of the form into view before tapping it: the form is
/// taller than a phone screen once it carries screenshots.
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openLauncher(WidgetTester tester) async {
  await tester.tap(_launcher);
  await tester.pumpAndSettle();
}

/// The surface of the open feedback menu.
Rect _menuRect(WidgetTester tester) {
  return tester.getRect(
    find
        .ancestor(
          of: find.text('Give us feedback'),
          matching: find.byType(Material),
        )
        .first,
  );
}

Future<TestGesture> _addMouse(WidgetTester tester) async {
  final TestGesture mouse = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
  );
  await mouse.addPointer(location: const Offset(4, 4));
  addTearDown(mouse.removePointer);
  await tester.pump();
  return mouse;
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
      expect(_launcher, findsOneWidget);

      await _openLauncher(tester);

      expect(find.byType(FeedbackSubmitDialog), findsOneWidget);
      expect(find.text('GIVE US FEEDBACK'), findsOneWidget);
      expect(find.text('Download feedback'), findsNothing);
      // The control steps aside while its own form is open.
      expect(_launcher, findsNothing);

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
      expect(sent.submission.context.appVersion, '1.4.0+12');
      // An IANA zone or a UTC offset, never an abbreviation such as `EAT`.
      expect(
        sent.submission.context.timezone,
        matches(
          RegExp(r'^([A-Za-z_]+(/[A-Za-z0-9_+\-]+)+|UTC|UTC[+-]\d\d:\d\d)$'),
        ),
      );
      expect(sent.submission.context.viewportWidth, 1280);
      expect(sent.submission.context.screenWidth, isNotNull);
      expect(
        find.text('Thank you. Your feedback was sent (reference FBK0000001).'),
        findsOneWidget,
      );
      expect(_launcher.hitTestable(), findsOneWidget);
    },
  );

  testWidgets(
    'is a small square icon with a minimal radius and its label on hover',
    (WidgetTester tester) async {
      await _pumpHost(
        tester,
        session: const SessionState.unauthenticated(),
        repository: _FakeFeedbackRepository(),
      );

      final double radius = Theme.of(tester.element(_launcher)).radius.xs;
      expect(
        tester.widget<Material>(_launcher).shape,
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      );
      final Size iconOnly = tester.getSize(_launcher);
      expect(iconOnly.width, lessThanOrEqualTo(32));
      expect(iconOnly.height, lessThanOrEqualTo(32));
      expect(find.text('Feedback'), findsNothing);
      final Rect resting = tester.getRect(_launcher);

      final TestGesture mouse = await _addMouse(tester);
      await mouse.moveTo(tester.getCenter(_launcher));
      await tester.pumpAndSettle();

      expect(find.text('Feedback'), findsOneWidget);
      // At the right edge the label opens leftward, into the screen.
      expect(tester.getSize(_launcher).width, greaterThan(iconOnly.width));
      expect(tester.getRect(_launcher).right, moreOrLessEquals(resting.right));

      await mouse.moveTo(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text('Feedback'), findsNothing);

      // On the left half of the screen it opens rightward instead.
      await tester.drag(_launcher, const Offset(-1000, -400));
      await tester.pumpAndSettle();
      final double left = tester.getRect(_launcher).left;
      await mouse.moveTo(tester.getCenter(_launcher));
      await tester.pumpAndSettle();

      expect(find.text('Feedback'), findsOneWidget);
      expect(tester.getRect(_launcher).left, moreOrLessEquals(left));
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
    // The control hides behind its own form, and comes back when it closes.
    expect(_launcher, findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(FeedbackSubmitDialog),
        matching: find.widgetWithText(AppButton, 'Close'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FeedbackSubmitDialog), findsNothing);
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

  testWidgets('tapping the button shows and hides the feedback menu', (
    WidgetTester tester,
  ) async {
    await _pumpHost(
      tester,
      session: _signedInAs('PLATFORM_OWNER'),
      repository: _FakeFeedbackRepository(),
    );

    await _openLauncher(tester);
    expect(find.text('Download feedback'), findsOneWidget);
    expect(_launcher.hitTestable(), findsOneWidget);

    await tester.tap(_launcher);
    await tester.pumpAndSettle();
    expect(find.text('Download feedback'), findsNothing);

    await tester.tap(_launcher);
    await tester.pumpAndSettle();
    expect(find.text('Download feedback'), findsOneWidget);

    // Hiding and showing again before the exit animation ends is safe too.
    await tester.tap(_launcher);
    await tester.pump();
    await tester.tap(_launcher);
    await tester.pumpAndSettle();
    expect(find.text('Download feedback'), findsOneWidget);

    await tester.tap(_launcher);
    await tester.pumpAndSettle();
    expect(find.text('Download feedback'), findsNothing);
    expect(find.byType(FeedbackSubmitDialog), findsNothing);
  });

  for (final _MenuLayout layout in const <_MenuLayout>[
    (name: 'desktop, default corner', size: Size(1280, 900), moveTo: null),
    (
      name: 'desktop, screen centre',
      size: Size(1280, 900),
      moveTo: Offset(640, 450),
    ),
    (
      name: 'desktop, top-left corner',
      size: Size(1280, 900),
      moveTo: Offset.zero,
    ),
    (name: 'phone, default corner', size: Size(390, 844), moveTo: null),
    (
      name: 'phone, screen centre',
      size: Size(390, 844),
      moveTo: Offset(195, 422),
    ),
    (
      name: 'narrow phone, left of centre',
      size: Size(320, 640),
      moveTo: Offset(150, 320),
    ),
    (
      name: 'narrow phone, right of centre',
      size: Size(320, 640),
      moveTo: Offset(172, 320),
    ),
  ]) {
    testWidgets('the button never covers its menu: ${layout.name}', (
      WidgetTester tester,
    ) async {
      await _pumpHost(
        tester,
        session: _signedInAs('PLATFORM_ADMIN'),
        repository: _FakeFeedbackRepository(),
        size: layout.size,
      );
      final Offset? moveTo = layout.moveTo;
      if (moveTo != null) {
        await tester.drag(_launcher, moveTo - tester.getCenter(_launcher));
        await tester.pumpAndSettle();
      }

      // Open it while hovered, so the label is showing as the menu opens.
      final TestGesture mouse = await _addMouse(tester);
      await mouse.moveTo(tester.getCenter(_launcher));
      await tester.pumpAndSettle();
      expect(find.text('Feedback'), findsOneWidget);
      await tester.tap(_launcher);
      await tester.pumpAndSettle();

      expect(find.text('Download feedback'), findsOneWidget);
      expect(find.text('Feedback'), findsNothing);
      final Rect menu = _menuRect(tester);
      final Rect button = tester.getRect(_launcher);
      expect(
        menu.overlaps(button),
        isFalse,
        reason: 'menu $menu overlaps button $button',
      );
      expect(menu.left, greaterThanOrEqualTo(0));
      expect(menu.right, lessThanOrEqualTo(layout.size.width));
    });
  }

  testWidgets('dragging the button closes its menu at once', (
    WidgetTester tester,
  ) async {
    await _pumpHost(
      tester,
      session: _signedInAs('PLATFORM_OWNER'),
      repository: _FakeFeedbackRepository(),
    );
    await _openLauncher(tester);
    expect(find.text('Download feedback'), findsOneWidget);

    await tester.drag(_launcher, const Offset(-500, -300));
    await tester.pump();

    // Gone within a frame: no exit animation for the button to pass over.
    expect(find.text('Download feedback'), findsNothing);
    await tester.pumpAndSettle();
    await _openLauncher(tester);
    expect(find.text('Download feedback'), findsOneWidget);
  });

  testWidgets('resizing the window closes the menu', (
    WidgetTester tester,
  ) async {
    await _pumpHost(
      tester,
      session: _signedInAs('PLATFORM_OWNER'),
      repository: _FakeFeedbackRepository(),
    );
    await _openLauncher(tester);
    expect(find.text('Download feedback'), findsOneWidget);

    tester.view.physicalSize = const Size(900, 700);
    await tester.pump();
    await tester.pump();

    expect(find.text('Download feedback'), findsNothing);
    expect(_launcher.hitTestable(), findsOneWidget);
  });

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

  testWidgets('download saves the picked records as a named archive', (
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

    expect(find.byType(FeedbackDownloadDialog), findsOneWidget);
    expect(find.text('Stored feedback 2'), findsOneWidget);
    expect(savedFiles, isEmpty);

    await tester.tap(
      find.byKey(FeedbackDownloadDialog.rowCheckboxKey('FBK0000002')),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(AppButton, 'Download'));
    await tester.pumpAndSettle();

    expect(find.byType(FeedbackDownloadDialog), findsNothing);
    expect(repository.exportOffsets, <int>[
      DateTime.now().timeZoneOffset.inMinutes,
    ]);
    expect(repository.exportedIds.single, <String>{'FBK0000002'});
    final _SavedFile saved = savedFiles.single;
    expect(saved.bytes, repository.exportBytes);
    expect(
      saved.fileName,
      matches(RegExp(r'^HOSSPI-FEEDBACK-\d{8}-\d{6}\.zip$')),
    );
    expect(find.text('Feedback downloaded.'), findsOneWidget);
  });

  testWidgets('downloading without a pick exports every matching record', (
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
    await tester.tap(find.widgetWithText(AppButton, 'Download'));
    await tester.pumpAndSettle();

    // No ids means the whole matching list, which the API resolves.
    expect(repository.exportedIds.single, isEmpty);
    expect(savedFiles, hasLength(1));
  });

  testWidgets('closing Download feedback downloads nothing', (
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
    await tester.tap(
      find.descendant(
        of: find.byType(FeedbackDownloadDialog),
        matching: find.widgetWithText(AppButton, 'Close'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FeedbackDownloadDialog), findsNothing);
    expect(repository.exportOffsets, isEmpty);
    expect(savedFiles, isEmpty);
    expect(_launcher.hitTestable(), findsOneWidget);
  });

  testWidgets('clear feedback lets owners pick records to delete permanently', (
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

    expect(find.byType(FeedbackDeleteDialog), findsOneWidget);
    expect(find.text('Stored feedback 2'), findsOneWidget);
    expect(_launcher, findsNothing);

    await tester.tap(
      find.byKey(FeedbackDeleteDialog.rowCheckboxKey('FBK0000002')),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(AppButton, 'Delete permanently'));
    await tester.pumpAndSettle();

    expect(find.byType(AppConfirmActionDialog), findsOneWidget);
    expect(repository.deletedIds, isEmpty);

    await tester.tap(
      find.descendant(
        of: find.byType(AppConfirmActionDialog),
        matching: find.widgetWithText(AppButton, 'Delete permanently'),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.deletedIds.single, <String>{'FBK0000002'});
    expect(find.byType(FeedbackDeleteDialog), findsNothing);
    expect(find.text('Deleted 1 feedback record permanently.'), findsOneWidget);
  });

  testWidgets('closing Clear feedback keeps feedback', (
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
        of: find.byType(FeedbackDeleteDialog),
        matching: find.widgetWithText(AppButton, 'Close'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FeedbackDeleteDialog), findsNothing);
    expect(repository.deletedIds, isEmpty);
    expect(find.textContaining('permanently.'), findsNothing);
  });

  testWidgets('shows the same small icon-only control at phone width', (
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
    expect(launcherSize.width, lessThanOrEqualTo(32));
    expect(launcherSize.height, lessThanOrEqualTo(32));
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

  testWidgets(
    'attaches a picture of the screen the control was tapped on, without the '
    'control itself',
    (WidgetTester tester) async {
      final _FakeFeedbackRepository repository = _FakeFeedbackRepository();
      final _FakeScreenCapturer capturer = _FakeScreenCapturer();
      await _pumpHost(
        tester,
        session: const SessionState.unauthenticated(),
        repository: repository,
        capturer: capturer,
      );

      await _openLauncher(tester);

      // Taken before the form opened, of the screen behind it.
      expect(capturer.calls, hasLength(1));
      expect(capturer.calls.single.routeName, 'patients');
      expect(find.text('1 of 3'), findsOneWidget);

      await tester.enterText(_messageField, 'The save button does nothing');
      await tester.tap(find.widgetWithText(AppButton, 'Send feedback'));
      await tester.pumpAndSettle();

      final FeedbackSubmission sent = repository.submissions.single.submission;
      expect(sent.screenshots, hasLength(1));
      expect(sent.screenshots.single.screen.routeName, 'patients');
    },
  );

  testWidgets('sends the feedback when the screen cannot be captured', (
    WidgetTester tester,
  ) async {
    final _FakeFeedbackRepository repository = _FakeFeedbackRepository();
    await _pumpHost(
      tester,
      session: const SessionState.unauthenticated(),
      repository: repository,
      capturer: _FakeScreenCapturer(succeeds: false),
    );

    await _openLauncher(tester);
    await tester.enterText(_messageField, 'No pictures on this device');
    await tester.tap(find.widgetWithText(AppButton, 'Send feedback'));
    await tester.pumpAndSettle();

    // A screenshot is never worth the reporter's words.
    expect(repository.submissions.single.submission.screenshots, isEmpty);
    expect(
      find.text('Thank you. Your feedback was sent (reference FBK0000001).'),
      findsOneWidget,
    );
  });

  testWidgets(
    'keeps capturing screen after screen until the reporter goes back',
    (WidgetTester tester) async {
      final _FakeFeedbackRepository repository = _FakeFeedbackRepository();
      final _FakeScreenCapturer capturer = _FakeScreenCapturer();
      final GoRouter router = await _pumpHost(
        tester,
        session: const SessionState.unauthenticated(),
        repository: repository,
        capturer: capturer,
      );

      await _openLauncher(tester);
      await tester.enterText(_messageField, 'Both screens are wrong');
      await tester.tap(_typeOption('Problem'));
      await tester.pump();
      await _tapVisible(
        tester,
        find.byKey(FeedbackSubmitDialog.captureAnotherScreenKey),
      );

      // The control has become the capture bar; the form is put aside.
      expect(find.byType(FeedbackSubmitDialog), findsNothing);
      expect(find.byKey(AppFeedbackHost.captureBarKey), findsOneWidget);
      expect(find.text('Capturing · 1 of 3'), findsOneWidget);

      // Walk to another screen and take two shots of it.
      router.goNamed('billing');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, 'Capture'));
      await tester.pumpAndSettle();
      expect(find.text('Capturing · 2 of 3'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppButton, 'Capture'));
      await tester.pumpAndSettle();
      expect(find.text('Capturing · 3 of 3'), findsOneWidget);

      // The cap is reached: capture is offered but refused.
      final AppButton captureButton = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Capture'),
      );
      expect(captureButton.onPressed, isNull);

      await tester.tap(find.widgetWithText(AppButton, 'Back to feedback'));
      await tester.pumpAndSettle();

      // Everything typed and captured came back with the form.
      expect(find.byType(FeedbackSubmitDialog), findsOneWidget);
      expect(find.text('Both screens are wrong'), findsOneWidget);
      expect(find.text('3 of 3'), findsOneWidget);

      await tester.tap(find.widgetWithText(AppButton, 'Send feedback'));
      await tester.pumpAndSettle();

      final FeedbackSubmission sent = repository.submissions.single.submission;
      expect(sent.category, FeedbackCategory.problem);
      expect(
        sent.screenshots
            .map((FeedbackScreenshot shot) => shot.screen.routeName)
            .toList(),
        <String>['patients', 'billing', 'billing'],
      );
      // Capturing another screen says the feedback is about it too.
      expect(sent.scope, FeedbackScope.screens);
      expect(
        sent.screens.map((FeedbackScreenReference screen) => screen.routeName),
        containsAll(<String>['patients', 'billing']),
      );
    },
  );

  testWidgets('discarding a draft throws away its screenshots too', (
    WidgetTester tester,
  ) async {
    final _FakeFeedbackRepository repository = _FakeFeedbackRepository();
    await _pumpHost(
      tester,
      session: const SessionState.unauthenticated(),
      repository: repository,
    );

    await _openLauncher(tester);
    await tester.enterText(_messageField, 'Never mind');
    await _tapVisible(
      tester,
      find.byKey(FeedbackSubmitDialog.captureAnotherScreenKey),
    );
    await tester.tap(find.widgetWithText(AppButton, 'Discard feedback'));
    await tester.pumpAndSettle();
    // Once on the capture bar, once in the confirmation it opens.
    await tester.tap(find.widgetWithText(AppButton, 'Discard feedback').last);
    await tester.pumpAndSettle();

    // The control is itself again, and the next report starts blank.
    expect(find.byKey(AppFeedbackHost.captureBarKey), findsNothing);
    expect(_launcher, findsOneWidget);
    await _openLauncher(tester);
    expect(find.text('Never mind'), findsNothing);
  });
}
