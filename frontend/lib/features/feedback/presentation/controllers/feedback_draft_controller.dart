import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';

/// The feedback being written, kept outside the dialog that shows it.
///
/// A reporter walks through the app capturing screens while writing, so the
/// dialog closes and reopens several times before anything is sent. Holding
/// the draft here, for the session, is what lets them come back to every word
/// and every picture exactly as they left them.
final feedbackDraftProvider =
    NotifierProvider<FeedbackDraftController, FeedbackDraft?>(
      FeedbackDraftController.new,
    );

/// What the reporter has written, picked and captured so far.
final class FeedbackDraft {
  const FeedbackDraft({
    required this.context,
    required this.signedIn,
    this.category = FeedbackCategory.general,
    this.message = '',
    this.scope = FeedbackScope.screen,
    this.screens = const <FeedbackScreenReference>[],
    this.screenshots = const <FeedbackScreenshot>[],
    this.isCapturing = false,
    this.includeDialogInShot = false,
  });

  /// Where the feedback was raised: the screen, device and session as they
  /// were when the reporter opened the form, never where they wandered to
  /// afterwards.
  final FeedbackContext context;
  final bool signedIn;
  final FeedbackCategory category;
  final String message;
  final FeedbackScope scope;

  /// The screens picked for [FeedbackScope.screens].
  final List<FeedbackScreenReference> screens;

  /// Shots in capture order. Several shots of one screen are normal.
  final List<FeedbackScreenshot> screenshots;

  /// Whether the reporter is walking the app taking shots, with the form put
  /// aside rather than discarded.
  final bool isCapturing;

  /// Whether the next shot shows the feedback form itself.
  final bool includeDialogInShot;

  /// Shots this reporter may still take.
  int get remainingScreenshots =>
      feedbackScreenshotLimit(signedIn: signedIn) - screenshots.length;

  bool get canCaptureMore => remainingScreenshots > 0;

  int get screenshotBytes => screenshots.fold<int>(
    0,
    (int total, FeedbackScreenshot shot) => total + shot.byteSize,
  );

  FeedbackDraft copyWith({
    FeedbackCategory? category,
    String? message,
    FeedbackScope? scope,
    List<FeedbackScreenReference>? screens,
    List<FeedbackScreenshot>? screenshots,
    bool? isCapturing,
    bool? includeDialogInShot,
  }) {
    return FeedbackDraft(
      context: context,
      signedIn: signedIn,
      category: category ?? this.category,
      message: message ?? this.message,
      scope: scope ?? this.scope,
      screens: screens ?? this.screens,
      screenshots: screenshots ?? this.screenshots,
      isCapturing: isCapturing ?? this.isCapturing,
      includeDialogInShot: includeDialogInShot ?? this.includeDialogInShot,
    );
  }
}

final class FeedbackDraftController extends Notifier<FeedbackDraft?> {
  @override
  FeedbackDraft? build() => null;

  /// Starts a draft, or keeps the one already in hand.
  ///
  /// Reopening the form must not wipe what is in it, so an existing draft
  /// wins over a fresh context; only [reset] and a submission end one.
  FeedbackDraft start({
    required FeedbackContext context,
    required bool signedIn,
    FeedbackScreenshot? firstScreenshot,
  }) {
    final FeedbackDraft? existing = state;
    if (existing != null) {
      final FeedbackDraft resumed = existing.copyWith(isCapturing: false);
      state = firstScreenshot == null
          ? resumed
          : _withScreenshot(resumed, firstScreenshot);
      return state!;
    }

    final FeedbackDraft draft = FeedbackDraft(
      context: context,
      signedIn: signedIn,
    );
    state = firstScreenshot == null
        ? draft
        : _withScreenshot(draft, firstScreenshot);
    return state!;
  }

  /// Keeps what the reporter typed, so closing the form loses nothing.
  void saveEntry({required FeedbackCategory category, required String message}) {
    final FeedbackDraft? draft = state;
    if (draft == null) {
      return;
    }
    state = draft.copyWith(category: category, message: message);
  }

  void setScope(FeedbackScope scope) {
    final FeedbackDraft? draft = state;
    if (draft == null) {
      return;
    }
    // Picked screens are kept while the reporter switches scope back and
    // forth; only the scope decides what is sent.
    state = draft.copyWith(scope: scope);
  }

  void setScreens(List<FeedbackScreenReference> screens) {
    final FeedbackDraft? draft = state;
    if (draft == null) {
      return;
    }
    state = draft.copyWith(screens: _dedupeScreens(screens));
  }

  void removeScreen(FeedbackScreenReference screen) {
    final FeedbackDraft? draft = state;
    if (draft == null) {
      return;
    }
    final List<FeedbackScreenReference> screens = draft.screens
        .where((FeedbackScreenReference entry) => entry != screen)
        .toList(growable: false);
    state = draft.copyWith(
      screens: screens,
      // Dropping the last screen would leave "selected screens" meaning
      // nothing, so the report falls back to the screen it came from.
      scope: screens.isEmpty && draft.scope == FeedbackScope.screens
          ? FeedbackScope.screen
          : draft.scope,
    );
  }

  void setIncludeDialogInShot({required bool include}) {
    final FeedbackDraft? draft = state;
    if (draft == null) {
      return;
    }
    state = draft.copyWith(includeDialogInShot: include);
  }

  /// Puts the form aside so the reporter can walk the app taking shots.
  void beginCapturing() {
    final FeedbackDraft? draft = state;
    if (draft == null) {
      return;
    }
    state = draft.copyWith(isCapturing: true);
  }

  void endCapturing() {
    final FeedbackDraft? draft = state;
    if (draft == null) {
      return;
    }
    state = draft.copyWith(isCapturing: false);
  }

  /// Adds a shot and, when it comes from another screen, records that screen
  /// as one the feedback applies to.
  ///
  /// Returns false when the reporter is already at their limit.
  bool addScreenshot(FeedbackScreenshot screenshot) {
    final FeedbackDraft? draft = state;
    if (draft == null || !draft.canCaptureMore) {
      return false;
    }
    state = _withScreenshot(draft, screenshot);
    return true;
  }

  void replaceScreenshot(int index, FeedbackScreenshot screenshot) {
    final FeedbackDraft? draft = state;
    if (draft == null || index < 0 || index >= draft.screenshots.length) {
      return;
    }
    final List<FeedbackScreenshot> screenshots = <FeedbackScreenshot>[
      ...draft.screenshots,
    ];
    screenshots[index] = screenshot;
    state = draft.copyWith(screenshots: screenshots);
  }

  void removeScreenshot(int index) {
    final FeedbackDraft? draft = state;
    if (draft == null || index < 0 || index >= draft.screenshots.length) {
      return;
    }
    final List<FeedbackScreenshot> screenshots = <FeedbackScreenshot>[
      ...draft.screenshots,
    ]..removeAt(index);
    state = draft.copyWith(screenshots: screenshots);
  }

  /// Ends the draft: the feedback was sent, or the reporter discarded it.
  void reset() {
    state = null;
  }

  /// Adds a shot, and with it the screen it was taken on.
  ///
  /// Capturing another screen is the clearest statement that the feedback is
  /// about that screen too, so the scope follows the pictures. The screen the
  /// form was opened on is already the report's own context, so it is not
  /// added again.
  FeedbackDraft _withScreenshot(
    FeedbackDraft draft,
    FeedbackScreenshot screenshot,
  ) {
    final List<FeedbackScreenshot> screenshots = <FeedbackScreenshot>[
      ...draft.screenshots,
      screenshot,
    ];
    final bool isAnotherScreen =
        screenshot.screen.isAddressable &&
        screenshot.screen.routeName != draft.context.routeName;
    if (!isAnotherScreen || draft.scope == FeedbackScope.app) {
      return draft.copyWith(screenshots: screenshots);
    }

    return draft.copyWith(
      screenshots: screenshots,
      scope: FeedbackScope.screens,
      screens: _dedupeScreens(<FeedbackScreenReference>[
        ...draft.screens,
        if (draft.scope == FeedbackScope.screen) _originScreen(draft),
        screenshot.screen,
      ]),
    );
  }

  FeedbackScreenReference _originScreen(FeedbackDraft draft) {
    return FeedbackScreenReference(
      routeName: draft.context.routeName,
      routePath: draft.context.routePath,
    );
  }

  List<FeedbackScreenReference> _dedupeScreens(
    List<FeedbackScreenReference> screens,
  ) {
    final Map<String, FeedbackScreenReference> unique =
        <String, FeedbackScreenReference>{};
    for (final FeedbackScreenReference screen in screens) {
      if (!screen.isAddressable) {
        continue;
      }
      // A later entry usually carries the better label.
      unique[screen.key] = screen;
    }
    return unique.values.toList(growable: false);
  }
}
