import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/core/responsive/app_breakpoints.dart';

/// Where the feedback form sits on screen.
enum FeedbackPresentation {
  /// Beside the app, as an opaque panel pinned to the trailing edge. The app
  /// keeps its own layout and stays usable, so a reporter can look at what
  /// they are reporting while they write about it.
  docked,

  /// Centred over the app, for narrow windows and for reporters who want the
  /// form in front of them.
  dialog,
}

/// Narrowest window that can hold the panel and still show a usable app
/// beside it. Below this the form is a dialog whatever the preference says.
const double feedbackDockMinWidth = AppBreakpoints.lg;

/// The panel's width for a window of [windowWidth]: wide enough for the form,
/// never more than about a third of the screen.
double feedbackDockWidth(double windowWidth) {
  return math.max(320, math.min(440, windowWidth * 0.34));
}

/// Whether the panel fits beside the app in a window of [windowWidth].
bool feedbackCanDock(double windowWidth) => windowWidth >= feedbackDockMinWidth;

/// How the reporter wants the form shown, for the rest of the session.
///
/// Docked by default: seeing the screen and the form together is the point of
/// the flow, and the app is overlaid rather than resized, so nothing about
/// the screen being reported on changes while the panel is open.
final feedbackPresentationProvider =
    NotifierProvider<FeedbackPresentationController, FeedbackPresentation>(
      FeedbackPresentationController.new,
    );

final class FeedbackPresentationController extends Notifier<FeedbackPresentation> {
  @override
  FeedbackPresentation build() => FeedbackPresentation.docked;

  void set(FeedbackPresentation presentation) {
    state = presentation;
  }

  void toggle() {
    state = state == FeedbackPresentation.docked
        ? FeedbackPresentation.dialog
        : FeedbackPresentation.docked;
  }
}
