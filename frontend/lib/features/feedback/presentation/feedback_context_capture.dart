import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hosspi_hms/core/config/app_config.dart';
import 'package:hosspi_hms/core/network/app_connectivity_status.dart';
import 'package:hosspi_hms/core/responsive/app_breakpoints.dart';
import 'package:hosspi_hms/core/security/session_state.dart';
import 'package:hosspi_hms/core/utils/client_timezone.dart';
import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';

/// Replacement for redacted query values.
const String feedbackRedactedValue = 'redacted';

/// Query parameter words that mark a value as a credential or personal data.
const Set<String> _sensitiveParamWords = <String>{
  'token',
  'jwt',
  'code',
  'otp',
  'pin',
  'password',
  'passcode',
  'passwd',
  'pwd',
  'secret',
  'signature',
  'sig',
  'credential',
  'credentials',
  'auth',
  'authorization',
  'session',
  'sid',
  'cookie',
  'email',
  'phone',
  'mobile',
  'msisdn',
  'key',
  'apikey',
};

/// Parameters whose value is itself a location (post-login redirects).
const Set<String> _nestedLocationParams = <String>{
  'from',
  'next',
  'continue',
  'redirect',
  'redirect_to',
  'redirecturl',
  'return_to',
  'returnto',
};

final RegExp _camelCaseBoundary = RegExp('([a-z0-9])([A-Z])');
final RegExp _nonWordCharacters = RegExp('[^a-z0-9]+');

/// Whether a query parameter holds a credential or personal data.
///
/// Matches whole words (`resetToken`, `api_key`) rather than substrings, so
/// ordinary parameters such as `shipping` or `author` are kept.
bool isSensitiveFeedbackParam(String name) {
  final List<String> words = name
      .replaceAllMapped(
        _camelCaseBoundary,
        (Match match) => '${match.group(1)} ${match.group(2)}',
      )
      .toLowerCase()
      .split(_nonWordCharacters)
      .where((String word) => word.isNotEmpty)
      .toList(growable: false);

  return words.any(_sensitiveParamWords.contains) ||
      _sensitiveParamWords.contains(words.join());
}

/// Strips credentials and personal data from a location before it leaves the
/// device.
///
/// The reset-password and verify-email screens carry a token and an email
/// address in their query, and hash URLs carry that query in the fragment. The
/// server scrubs again; this keeps secrets off the wire in the first place.
String redactFeedbackLocation(Uri location, {bool redactNested = true}) {
  final StringBuffer buffer = StringBuffer();
  if (location.hasScheme) {
    buffer.write('${location.scheme}:');
  }
  if (location.hasAuthority) {
    // User-info is dropped on purpose: it can hold credentials.
    final String host = location.host.contains(':')
        ? '[${location.host}]'
        : location.host;
    buffer.write('//$host');
    if (location.hasPort) {
      buffer.write(':${location.port}');
    }
  }
  buffer.write(location.path);

  if (location.hasQuery) {
    final String query = _redactQuery(
      location.query,
      redactNested: redactNested,
    );
    if (query.isNotEmpty) {
      buffer.write('?$query');
    }
  }
  if (location.hasFragment) {
    buffer.write(
      '#${_redactFragment(location.fragment, redactNested: redactNested)}',
    );
  }

  return buffer.toString();
}

String _redactQuery(String query, {required bool redactNested}) {
  final List<String> pairs = <String>[];
  for (final String pair in query.split('&')) {
    if (pair.isEmpty) {
      continue;
    }
    final int separator = pair.indexOf('=');
    final String rawName = separator < 0 ? pair : pair.substring(0, separator);
    final String rawValue = separator < 0 ? '' : pair.substring(separator + 1);
    final String name = _decodeQueryComponent(rawName);

    if (isSensitiveFeedbackParam(name)) {
      pairs.add('$rawName=$feedbackRedactedValue');
      continue;
    }
    if (redactNested && _nestedLocationParams.contains(name.toLowerCase())) {
      final Uri? nested = Uri.tryParse(_decodeQueryComponent(rawValue));
      if (nested != null) {
        final String scrubbed = redactFeedbackLocation(
          nested,
          redactNested: false,
        );
        pairs.add('$rawName=${Uri.encodeQueryComponent(scrubbed)}');
        continue;
      }
    }
    pairs.add(pair);
  }
  return pairs.join('&');
}

String _redactFragment(String fragment, {required bool redactNested}) {
  final int queryStart = fragment.indexOf('?');
  if (queryStart < 0) {
    return fragment;
  }
  final String path = fragment.substring(0, queryStart);
  final String query = _redactQuery(
    fragment.substring(queryStart + 1),
    redactNested: redactNested,
  );
  return query.isEmpty ? path : '$path?$query';
}

String _decodeQueryComponent(String value) {
  try {
    return Uri.decodeQueryComponent(value);
  } on FormatException {
    return value;
  } on ArgumentError {
    return value;
  }
}

/// `HOSSPI-FEEDBACK-DDMMYYYY-HHmmss.xlsx` on the device's local clock, in
/// 24-hour time.
String buildFeedbackExportFileName(DateTime moment) {
  final DateTime local = moment.toLocal();
  String twoDigits(int value) => value.toString().padLeft(2, '0');

  return 'HOSSPI-FEEDBACK-'
      '${twoDigits(local.day)}${twoDigits(local.month)}'
      '${local.year.toString().padLeft(4, '0')}-'
      '${twoDigits(local.hour)}${twoDigits(local.minute)}'
      '${twoDigits(local.second)}.xlsx';
}

/// `web`, or the native platform name (`android`, `ios`, `windows`, ...).
String feedbackPlatformLabel() {
  return kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();
}

/// Screen size class for a window [width] in logical pixels: phone layouts
/// below [AppBreakpoints.md], tablet layouts below [AppBreakpoints.xl], and
/// desktop layouts from there. The API applies the same thresholds when a
/// client sends only a viewport.
FeedbackDeviceType feedbackDeviceTypeForWidth(double width) {
  if (width < AppBreakpoints.md) {
    return FeedbackDeviceType.mobile;
  }
  if (width < AppBreakpoints.xl) {
    return FeedbackDeviceType.tablet;
  }
  return FeedbackDeviceType.desktop;
}

/// The router's current location, or null before the first navigation.
Uri? currentFeedbackLocation(GoRouter router) {
  final configuration = router.routerDelegate.currentConfiguration;
  return configuration.isEmpty ? null : configuration.uri;
}

/// The matched route's name, e.g. `patients` or `login`.
String? currentFeedbackRouteName(GoRouter router) {
  if (router.routerDelegate.currentConfiguration.isEmpty) {
    return null;
  }
  return router.state.topRoute?.name;
}

/// The device's IANA time zone, else its UTC offset at [moment]
/// (`UTC+03:00`). Never an abbreviation such as `EAT`, which several zones
/// share.
String feedbackTimeZoneLabel(
  DateTime moment, {
  String? Function() readTimeZoneId = readClientTimeZoneId,
}) {
  return readTimeZoneId() ?? formatUtcOffsetLabel(moment.timeZoneOffset);
}

/// Snapshot of the screen and device a user is giving feedback from.
///
/// [context] must sit below the app's `MediaQuery`, `Theme`, and
/// `Localizations`; the router's own navigator context is not required.
FeedbackContext captureFeedbackContext({
  required BuildContext context,
  required GoRouter router,
  required SessionState session,
  required AppConfig config,
  AppConnectivityStatus? connectivity,
  DateTime? now,
  String? Function() readTimeZoneId = readClientTimeZoneId,
}) {
  final DateTime moment = now ?? DateTime.now();
  final Uri? location = currentFeedbackLocation(router);
  final Size viewport = MediaQuery.sizeOf(context);
  final display = View.maybeOf(context)?.display;
  final Size? screen = display == null || display.devicePixelRatio <= 0
      ? null
      : display.size / display.devicePixelRatio;

  return FeedbackContext(
    routePath: location == null ? null : redactFeedbackLocation(location),
    routeName: currentFeedbackRouteName(router),
    pageUrl: kIsWeb ? redactFeedbackLocation(Uri.base) : null,
    platform: feedbackPlatformLabel(),
    deviceType: feedbackDeviceTypeForWidth(viewport.width),
    appVersion: config.appVersion,
    appEnvironment: config.environment.name,
    locale: Localizations.maybeLocaleOf(context)?.toLanguageTag(),
    timezone: feedbackTimeZoneLabel(moment, readTimeZoneId: readTimeZoneId),
    utcOffsetMinutes: moment.timeZoneOffset.inMinutes,
    breakpoint: AppBreakpoints.of(context).token,
    themeMode: Theme.of(context).brightness.name,
    textScale: MediaQuery.textScalerOf(context).scale(1),
    connectivity: connectivity?.name,
    sessionStatus: session.status.name,
    orientation: MediaQuery.orientationOf(context).name,
    viewportWidth: viewport.width,
    viewportHeight: viewport.height,
    devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    screenWidth: screen?.width,
    screenHeight: screen?.height,
  );
}
