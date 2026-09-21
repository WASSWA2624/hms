import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The boundary around the app, published by `AppFeedbackHost`.
///
/// Screenshots are taken from this boundary, which wraps everything the app
/// paints and nothing the feedback control paints, so the control is never in
/// a picture of the screen it was used on.
final feedbackCaptureBoundaryProvider =
    NotifierProvider<FeedbackCaptureBoundaryController, GlobalKey?>(
      FeedbackCaptureBoundaryController.new,
    );

final class FeedbackCaptureBoundaryController extends Notifier<GlobalKey?> {
  @override
  GlobalKey? build() => null;

  void register(GlobalKey key) {
    state = key;
  }
}

/// Whether the feedback form paints itself.
///
/// The form sits inside the app's own boundary, so a shot of "the screen
/// behind the form" is taken with the form held invisible for a frame. It
/// stays mounted throughout: the draft, the cursor and the scroll position
/// are all still there when it comes back.
final feedbackFormVisibleProvider =
    NotifierProvider<FeedbackFormVisibilityController, bool>(
      FeedbackFormVisibilityController.new,
    );

final class FeedbackFormVisibilityController extends Notifier<bool> {
  @override
  bool build() => true;

  void hide() {
    state = false;
  }

  void show() {
    state = true;
  }
}
