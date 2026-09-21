import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';
import 'package:hosspi_hms/features/feedback/presentation/controllers/feedback_draft_controller.dart';

const FeedbackContext _opdContext = FeedbackContext(
  routePath: '/opd',
  routeName: 'opd',
);

FeedbackScreenshot _screenshot({required String routeName, String? title}) {
  return FeedbackScreenshot(
    bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
    contentType: 'image/jpeg',
    screen: FeedbackScreenReference(
      routeName: routeName,
      routePath: '/$routeName',
      screenTitle: title ?? routeName,
    ),
    capturedAt: DateTime(2026, 9, 20, 9, 15),
  );
}

ProviderContainer _container() {
  final ProviderContainer container = ProviderContainer();
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('starting twice comes back to the draft in hand', () {
    final ProviderContainer container = _container();
    final FeedbackDraftController drafts = container.read(
      feedbackDraftProvider.notifier,
    );

    drafts.start(context: _opdContext, signedIn: true);
    drafts.saveEntry(
      category: FeedbackCategory.problem,
      message: 'Half written',
    );
    drafts.beginCapturing();

    // Reopening the form must not wipe what is in it.
    final FeedbackDraft resumed = drafts.start(
      context: const FeedbackContext(routeName: 'pharmacy'),
      signedIn: true,
    );

    expect(resumed.message, 'Half written');
    expect(resumed.category, FeedbackCategory.problem);
    expect(resumed.context.routeName, 'opd');
    expect(resumed.isCapturing, isFalse);
  });

  test('capturing another screen says the feedback is about it too', () {
    final ProviderContainer container = _container();
    final FeedbackDraftController drafts = container.read(
      feedbackDraftProvider.notifier,
    );
    drafts.start(context: _opdContext, signedIn: true);

    // The screen the form was opened on stays the report's own context.
    drafts.addScreenshot(_screenshot(routeName: 'opd'));
    expect(container.read(feedbackDraftProvider)!.scope, FeedbackScope.screen);

    drafts.addScreenshot(_screenshot(routeName: 'pharmacy', title: 'Pharmacy'));

    final FeedbackDraft draft = container.read(feedbackDraftProvider)!;
    expect(draft.scope, FeedbackScope.screens);
    expect(
      draft.screens.map((FeedbackScreenReference screen) => screen.routeName),
      <String>['opd', 'pharmacy'],
    );
    expect(draft.screenshots, hasLength(2));
  });

  test('a report about the whole app stays about the whole app', () {
    final ProviderContainer container = _container();
    final FeedbackDraftController drafts = container.read(
      feedbackDraftProvider.notifier,
    );
    drafts.start(context: _opdContext, signedIn: true);
    drafts.setScope(FeedbackScope.app);

    drafts.addScreenshot(_screenshot(routeName: 'pharmacy'));

    final FeedbackDraft draft = container.read(feedbackDraftProvider)!;
    expect(draft.scope, FeedbackScope.app);
    expect(draft.screens, isEmpty);
    expect(draft.screenshots, hasLength(1));
  });

  test('several shots of one screen are all kept', () {
    final ProviderContainer container = _container();
    final FeedbackDraftController drafts = container.read(
      feedbackDraftProvider.notifier,
    );
    drafts.start(context: _opdContext, signedIn: true);

    drafts.addScreenshot(_screenshot(routeName: 'pharmacy'));
    drafts.addScreenshot(_screenshot(routeName: 'pharmacy'));
    drafts.addScreenshot(_screenshot(routeName: 'pharmacy'));

    final FeedbackDraft draft = container.read(feedbackDraftProvider)!;
    expect(draft.screenshots, hasLength(3));
    // One screen, however many pictures of it.
    expect(draft.screens, hasLength(2));
  });

  test('the cap is the submitter\'s, and it refuses the next shot', () {
    final ProviderContainer container = _container();
    final FeedbackDraftController drafts = container.read(
      feedbackDraftProvider.notifier,
    );
    drafts.start(context: _opdContext, signedIn: false);

    for (int index = 0; index < feedbackMaxAnonymousScreenshots; index += 1) {
      expect(drafts.addScreenshot(_screenshot(routeName: 'opd')), isTrue);
    }

    expect(container.read(feedbackDraftProvider)!.canCaptureMore, isFalse);
    expect(drafts.addScreenshot(_screenshot(routeName: 'opd')), isFalse);
    expect(
      container.read(feedbackDraftProvider)!.screenshots,
      hasLength(feedbackMaxAnonymousScreenshots),
    );
  });

  test('picked screens are deduplicated and droppable', () {
    final ProviderContainer container = _container();
    final FeedbackDraftController drafts = container.read(
      feedbackDraftProvider.notifier,
    );
    drafts.start(context: _opdContext, signedIn: true);
    drafts.setScope(FeedbackScope.screens);

    drafts.setScreens(<FeedbackScreenReference>[
      const FeedbackScreenReference(routeName: 'opd', routePath: '/opd'),
      const FeedbackScreenReference(routeName: 'opd', routePath: '/opd'),
      const FeedbackScreenReference(
        routeName: 'pharmacy',
        routePath: '/pharmacy',
      ),
      // Nothing to address: dropped.
      const FeedbackScreenReference(screenTitle: 'Somewhere'),
    ]);
    expect(container.read(feedbackDraftProvider)!.screens, hasLength(2));

    drafts.removeScreen(
      const FeedbackScreenReference(routeName: 'opd', routePath: '/opd'),
    );
    expect(container.read(feedbackDraftProvider)!.screens, hasLength(1));

    drafts.removeScreen(
      const FeedbackScreenReference(
        routeName: 'pharmacy',
        routePath: '/pharmacy',
      ),
    );
    // "Selected screens" with nothing picked would say nothing at all.
    expect(container.read(feedbackDraftProvider)!.scope, FeedbackScope.screen);
  });

  test('removing and replacing a shot keeps the rest in order', () {
    final ProviderContainer container = _container();
    final FeedbackDraftController drafts = container.read(
      feedbackDraftProvider.notifier,
    );
    drafts.start(context: _opdContext, signedIn: true);
    drafts.addScreenshot(_screenshot(routeName: 'opd'));
    drafts.addScreenshot(_screenshot(routeName: 'pharmacy'));
    drafts.addScreenshot(_screenshot(routeName: 'lab'));

    drafts.removeScreenshot(1);
    drafts.replaceScreenshot(
      1,
      container
          .read(feedbackDraftProvider)!
          .screenshots[1]
          .copyWith(caption: 'look here'),
    );

    final List<FeedbackScreenshot> screenshots = container
        .read(feedbackDraftProvider)!
        .screenshots;
    expect(
      screenshots.map((FeedbackScreenshot shot) => shot.screen.routeName),
      <String>['opd', 'lab'],
    );
    expect(screenshots.last.caption, 'look here');
  });

  test('a sent or discarded draft is gone', () {
    final ProviderContainer container = _container();
    final FeedbackDraftController drafts = container.read(
      feedbackDraftProvider.notifier,
    );
    drafts.start(context: _opdContext, signedIn: true);
    drafts.addScreenshot(_screenshot(routeName: 'opd'));

    drafts.reset();

    expect(container.read(feedbackDraftProvider), isNull);
  });
}
