import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final feedbackLauncherPositionProvider =
    NotifierProvider<FeedbackLauncherPositionController, Offset?>(
      FeedbackLauncherPositionController.new,
    );

/// Where the user dragged the floating feedback button, as its top-left corner
/// in logical pixels.
///
/// Held in memory only, so the position survives navigation for the rest of
/// the app session and resets on the next launch. Null means the default
/// bottom-end corner.
final class FeedbackLauncherPositionController extends Notifier<Offset?> {
  @override
  Offset? build() => null;

  void moveTo(Offset position) {
    state = position;
  }
}
