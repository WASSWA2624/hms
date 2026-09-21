import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:hosspi_hms/core/responsive/app_breakpoints.dart';
import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';
import 'package:image/image.dart' as img;

/// Quality the capture is encoded at: small enough to upload from a phone on
/// a weak connection, good enough to read a screen's text in the export.
const int _jpegQuality = 80;

/// Encoded image and its size, as it will be uploaded.
typedef _EncodedImage = ({Uint8List bytes, int width, int height});

/// Takes a picture of whatever [boundaryKey] paints.
///
/// The key belongs to the boundary around the app, not around the feedback
/// control, so the control itself is never in the picture. The result is
/// scaled to [feedbackScreenshotMaxEdge] and encoded as JPEG, which keeps a
/// full-screen capture well inside the API's per-image cap.
///
/// Returns null when there is nothing to capture, when the platform refuses
/// (some web renderers throw), or when the encoded image is still too large:
/// a screenshot is never worth losing the reporter's words over.
Future<FeedbackScreenshot?> captureFeedbackScreenshot({
  required GlobalKey boundaryKey,
  required FeedbackScreenReference screen,
  DateTime? capturedAt,
  double maxEdge = feedbackScreenshotMaxEdge,
  int maxBytes = feedbackScreenshotMaxBytes,
}) async {
  final RenderObject? renderObject = boundaryKey.currentContext
      ?.findRenderObject();
  if (renderObject is! RenderRepaintBoundary) {
    return null;
  }
  // A boundary repainted this frame captures the frame before it otherwise.
  if (renderObject.debugNeedsPaint) {
    await WidgetsBinding.instance.endOfFrame;
  }
  final Size size = renderObject.size;
  if (size.isEmpty || size.width <= 0 || size.height <= 0) {
    return null;
  }

  final ByteData? rawPng = await _renderPng(
    renderObject,
    pixelRatio: _capturePixelRatio(size, maxEdge),
  );
  if (rawPng == null) {
    return null;
  }

  final _EncodedImage? encoded = await _encodeForUpload(
    rawPng.buffer.asUint8List(),
    maxEdge: maxEdge,
  );
  if (encoded == null || encoded.bytes.length > maxBytes) {
    return null;
  }

  return FeedbackScreenshot(
    bytes: encoded.bytes,
    contentType: 'image/jpeg',
    screen: screen,
    capturedAt: capturedAt ?? DateTime.now(),
    width: encoded.width,
    height: encoded.height,
    context: _windowContext(boundaryKey.currentContext),
  );
}

/// The window this shot was taken in. A reporter rotates the device, resizes
/// the window or switches theme between pictures, and the picture is only
/// half the evidence without knowing which of those it shows.
FeedbackScreenshotContext? _windowContext(BuildContext? context) {
  if (context == null || !context.mounted) {
    return null;
  }
  final Size viewport = MediaQuery.sizeOf(context);
  return FeedbackScreenshotContext(
    viewportWidth: viewport.width,
    viewportHeight: viewport.height,
    devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    orientation: MediaQuery.orientationOf(context).name,
    themeMode: Theme.of(context).brightness.name,
    breakpoint: AppBreakpoints.of(context).token,
  );
}

/// Scale that keeps the longest edge at [maxEdge] without ever enlarging.
double _capturePixelRatio(Size size, double maxEdge) {
  final double longestEdge = math.max(size.width, size.height);
  if (longestEdge <= 0) {
    return 1;
  }
  return math.min(1, maxEdge / longestEdge);
}

Future<ByteData?> _renderPng(
  RenderRepaintBoundary boundary, {
  required double pixelRatio,
}) async {
  ui.Image? image;
  try {
    image = await boundary.toImage(pixelRatio: pixelRatio);
    return await image.toByteData(format: ui.ImageByteFormat.png);
  } on Object {
    // Capture is best effort: several web renderers throw here, and a failed
    // picture must never block the feedback it belongs to.
    return null;
  } finally {
    image?.dispose();
  }
}

/// Re-encodes the raw capture as a JPEG, downscaling anything still larger
/// than [maxEdge] (a boundary can report a size the compositor grew).
Future<_EncodedImage?> _encodeForUpload(
  Uint8List pngBytes, {
  required double maxEdge,
}) {
  // Decoding and re-encoding is the expensive part; keep it off the UI thread
  // where the platform has threads to spare. On web `compute` runs inline.
  return compute<({Uint8List bytes, double maxEdge}), _EncodedImage?>(
    _encodeScreenshotIsolate,
    (bytes: pngBytes, maxEdge: maxEdge),
  );
}

_EncodedImage? _encodeScreenshotIsolate(
  ({Uint8List bytes, double maxEdge}) request,
) {
  final img.Image? decoded = img.decodePng(request.bytes);
  if (decoded == null) {
    return null;
  }

  final int longestEdge = math.max(decoded.width, decoded.height);
  final img.Image resized = longestEdge > request.maxEdge
      ? img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? request.maxEdge.round() : null,
          height: decoded.width >= decoded.height ? null : request.maxEdge.round(),
          interpolation: img.Interpolation.average,
        )
      : decoded;

  return (
    bytes: img.encodeJpg(resized, quality: _jpegQuality),
    width: resized.width,
    height: resized.height,
  );
}
