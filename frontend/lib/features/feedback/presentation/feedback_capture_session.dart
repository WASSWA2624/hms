import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';
import 'package:hosspi_hms/features/feedback/presentation/controllers/feedback_capture_controller.dart';
import 'package:hosspi_hms/features/feedback/presentation/feedback_context_capture.dart';
import 'package:hosspi_hms/features/feedback/presentation/feedback_screen_catalog.dart';
import 'package:hosspi_hms/features/feedback/presentation/feedback_screenshot_capture.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';

/// Takes a picture of the screen the app is on right now.
///
/// Behind a provider so a test can hand the flow a canned picture instead of
/// driving a real render.
typedef FeedbackScreenCapturer =
    Future<FeedbackScreenshot?> Function({
      required WidgetRef ref,
      required GoRouter router,
      required AppLocalizations l10n,
      bool hideForm,
    });

final feedbackScreenCapturerProvider = Provider<FeedbackScreenCapturer>(
  (Ref ref) => captureCurrentFeedbackScreen,
);

/// Takes a picture of the screen the app is on right now.
///
/// Used by the floating control for the first shot and for every shot taken
/// while the reporter walks the app, and by the form for "capture this
/// screen". With [hideForm] the form is held invisible for the shot, so the
/// picture shows the screen it is about rather than the form over it.
///
/// Returns null when the platform cannot produce a picture; the caller says
/// so and carries on, because feedback is never lost over a screenshot.
Future<FeedbackScreenshot?> captureCurrentFeedbackScreen({
  required WidgetRef ref,
  required GoRouter router,
  required AppLocalizations l10n,
  bool hideForm = false,
}) async {
  final GlobalKey? boundary = ref.read(feedbackCaptureBoundaryProvider);
  if (boundary == null) {
    return null;
  }

  final FeedbackScreenReference screen =
      feedbackScreenForRoute(
        l10n: l10n,
        routeName: currentFeedbackRouteName(router),
        routePath: currentFeedbackLocation(router)?.toString(),
      ) ??
      const FeedbackScreenReference();

  if (!hideForm) {
    return captureFeedbackScreenshot(boundaryKey: boundary, screen: screen);
  }

  final FeedbackFormVisibilityController visibility = ref.read(
    feedbackFormVisibleProvider.notifier,
  );
  visibility.hide();
  try {
    // Two frames: one to lay the form out invisible, one to paint without it.
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    return await captureFeedbackScreenshot(
      boundaryKey: boundary,
      screen: screen,
    );
  } finally {
    visibility.show();
  }
}
