import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/core/ai/ai_speech_formatter.dart';
import 'package:hosspi_hms/core/network/app_connectivity_status.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/components/app_action_label_scope.dart';
import 'package:hosspi_hms/shared/components/app_button.dart';
import 'package:hosspi_hms/shared/components/app_speech_ai.dart';
import 'package:hosspi_hms/shared/layout/app_workspace_feedback.dart';
import 'package:speech_to_text/speech_to_text.dart';

export 'package:hosspi_hms/shared/components/app_speech_ai.dart';

/// Why speech-to-text is inactive for a field.
enum AppSpeechToTextBlockReason {
  offline,
  unavailable,
  permissionDenied,
  noMicrophone,
  fieldDisabled,
}

/// Result of preparing the platform speech engine.
enum AppSpeechInitStatus {
  ready,
  unavailable,
  permissionDenied,
  noMicrophone,
}

/// Platform speech adapter (mockable in tests).
abstract class AppSpeechRecognizer {
  bool get isListening;

  Future<AppSpeechInitStatus> ensureReady({
    void Function(String status)? onStatus,
    void Function(String error)? onError,
  });

  Future<void> startListening({
    required void Function(String words, {required bool isFinal}) onResult,
    void Function(String status)? onStatus,
    void Function(String error)? onError,
  });

  Future<void> stopListening();

  Future<void> cancelListening();
}

/// Longest single recognizer session requested from the platform.
const Duration appSpeechListenFor = Duration(minutes: 5);

/// Silence a recognizer session may sit through before the platform ends it.
const Duration appSpeechPauseFor = Duration(seconds: 30);

/// Default [speech_to_text] backed recognizer.
final class SpeechToTextAppSpeechRecognizer implements AppSpeechRecognizer {
  SpeechToTextAppSpeechRecognizer({SpeechToText? speech})
    : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  bool _initialized = false;
  Future<AppSpeechInitStatus>? _pendingInit;
  AppSpeechInitStatus _lastStatus = AppSpeechInitStatus.unavailable;
  void Function(String status)? _lifecycleStatusListener;
  void Function(String error)? _lifecycleErrorListener;
  void Function(String status)? _sessionStatusListener;
  void Function(String error)? _sessionErrorListener;

  @override
  bool get isListening => _speech.isListening;

  void _dispatchStatus(String status) {
    _lifecycleStatusListener?.call(status);
    _sessionStatusListener?.call(status);
  }

  void _dispatchError(String error) {
    _lifecycleErrorListener?.call(error);
    _sessionErrorListener?.call(error);
  }

  @override
  Future<AppSpeechInitStatus> ensureReady({
    void Function(String status)? onStatus,
    void Function(String error)? onError,
  }) async {
    _lifecycleStatusListener = onStatus;
    _lifecycleErrorListener = onError;
    if (_initialized && _lastStatus == AppSpeechInitStatus.ready) {
      return AppSpeechInitStatus.ready;
    }
    // Every speech button warms up on its first frame; without this a screen
    // full of fields would run `initialize` concurrently, and each call
    // re-registers the platform recognizer.
    final Future<AppSpeechInitStatus>? pending = _pendingInit;
    if (pending != null) {
      return pending;
    }
    final Future<AppSpeechInitStatus> init = _initialize();
    _pendingInit = init;
    try {
      return await init;
    } finally {
      _pendingInit = null;
    }
  }

  Future<AppSpeechInitStatus> _initialize() async {
    try {
      // The plugin only accepts status/error handlers at initialize time, so
      // they fan out through fields that each listen session can swap.
      final bool available = await _speech.initialize(
        onStatus: _dispatchStatus,
        onError: (error) {
          _dispatchError(error.errorMsg);
        },
      );
      if (!available) {
        final bool permitted = await _speech.hasPermission;
        _lastStatus = permitted
            ? AppSpeechInitStatus.unavailable
            : AppSpeechInitStatus.permissionDenied;
        _initialized = true;
        return _lastStatus;
      }
      _initialized = true;
      _lastStatus = AppSpeechInitStatus.ready;
      return _lastStatus;
    } on Object catch (error) {
      _dispatchError(error.toString());
      _lastStatus = AppSpeechInitStatus.unavailable;
      _initialized = true;
      return _lastStatus;
    }
  }

  @override
  Future<void> startListening({
    required void Function(String words, {required bool isFinal}) onResult,
    void Function(String status)? onStatus,
    void Function(String error)? onError,
  }) async {
    _sessionStatusListener = onStatus;
    _sessionErrorListener = onError;
    await _speech.listen(
      onResult: (result) {
        onResult(result.recognizedWords, isFinal: result.finalResult);
      },
      // `cancelOnError` stays off: Android reports every error as permanent,
      // so the plugin would end dictation on a mere silence. Partial results
      // (the default) also keep web recognition continuous.
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        // Long limits keep one recognizer session open across pauses where
        // the platform honors them. Android still ends sessions on its own,
        // and the coordinator restarts them.
        listenFor: appSpeechListenFor,
        pauseFor: appSpeechPauseFor,
      ),
    );
  }

  @override
  Future<void> stopListening() async {
    _sessionStatusListener = null;
    _sessionErrorListener = null;
    await _speech.stop();
  }

  @override
  Future<void> cancelListening() async {
    _sessionStatusListener = null;
    _sessionErrorListener = null;
    await _speech.cancel();
  }
}

/// Inserts [transcript] at the current selection/caret of [controller].
///
/// When [sessionPrefix]/[sessionSuffix] are provided (captured at listen
/// start), each call replaces the live dictation span so partial results do
/// not stack. Surrounding markdown-ish markup outside that span is preserved.
void insertSpeechTranscript(
  TextEditingController controller,
  String transcript, {
  required String sessionPrefix,
  required String sessionSuffix,
}) {
  final String next = '$sessionPrefix$transcript$sessionSuffix';
  final int caret = sessionPrefix.length + transcript.length;
  controller.value = TextEditingValue(
    text: next,
    selection: TextSelection.collapsed(offset: caret.clamp(0, next.length)),
  );
}

/// Folds a freshly recognized [segment] into the text already dictated in this
/// session.
///
/// Platform recognizers disagree about what each callback carries: some resend
/// the whole utterance so far, some resend a final that was already delivered,
/// and some emit only the new phrase. Appending blindly duplicates text in the
/// first two cases, so overlapping content is absorbed instead of repeated.
/// [separator] is empty for digit / email style fields where a space would
/// corrupt the value.
String mergeSpeechSegments(
  String committed,
  String segment, {
  String separator = ' ',
}) {
  if (committed.isEmpty) {
    return segment;
  }
  if (segment.isEmpty) {
    return committed;
  }
  // Recognizer resent the running utterance (web/iOS accumulate).
  if (segment.startsWith(committed)) {
    return segment;
  }
  // Recognizer resent a phrase that is already committed (duplicate final).
  if (committed.endsWith(segment)) {
    return committed;
  }
  if (separator.isEmpty ||
      committed.endsWith(separator) ||
      segment.startsWith(separator)) {
    return '$committed$segment';
  }
  return '$committed$separator$segment';
}

/// Separator used when joining dictated phrases for a backend format mode.
String appSpeechSegmentSeparatorForFormatMode(String aiFormatMode) {
  return aiFormatMode == 'text' ? ' ' : '';
}

({String prefix, String suffix}) captureSpeechSessionBounds(
  TextEditingController controller,
) {
  final TextSelection selection = controller.selection;
  final String text = controller.text;
  final int start = selection.isValid
      ? selection.start.clamp(0, text.length)
      : text.length;
  final int end = selection.isValid
      ? selection.end.clamp(0, text.length)
      : text.length;
  final int from = start <= end ? start : end;
  final int to = start <= end ? end : start;
  return (prefix: text.substring(0, from), suffix: text.substring(to));
}

/// Default speech visibility for shared text fields.
///
/// Opt out always for obscured/password fields. When [enableSpeechToText] is
/// null, speech is shown for every other editable field (including number,
/// phone, email, and datetime keyboards). Set false to force hide, true to
/// force show (still never on [obscureText]).
bool appSpeechToTextEnabledForField({
  required bool? enableSpeechToText,
  required bool obscureText,
  TextInputType? keyboardType,
}) {
  if (obscureText) {
    return false;
  }
  if (enableSpeechToText == false) {
    return false;
  }
  return true;
}

/// How spoken transcripts are normalized before insertion.
enum AppSpeechTranscriptMode {
  /// Running prose: punctuation words and cardinal number phrases.
  text,

  /// Email-oriented tokens (`at`, `dot`, `underscore`, …).
  email,

  /// Integer / phone / date-time digit fields.
  digits,

  /// Amounts and decimal number fields.
  decimal,
}

/// Backend `speech_format` mode for a Flutter [TextInputType].
String appSpeechAiFormatModeForKeyboard(TextInputType? keyboardType) {
  if (keyboardType == TextInputType.emailAddress) {
    return 'email';
  }
  if (keyboardType == TextInputType.phone) {
    return 'phone';
  }
  if (keyboardType == TextInputType.datetime) {
    return 'date';
  }
  return switch (appSpeechTranscriptModeForKeyboard(keyboardType)) {
    AppSpeechTranscriptMode.decimal => 'decimal',
    AppSpeechTranscriptMode.digits => 'digits',
    AppSpeechTranscriptMode.email => 'email',
    AppSpeechTranscriptMode.text => 'text',
  };
}

/// Picks a transcript mode from a Flutter [TextInputType].
AppSpeechTranscriptMode appSpeechTranscriptModeForKeyboard(
  TextInputType? keyboardType,
) {
  if (keyboardType == TextInputType.emailAddress) {
    return AppSpeechTranscriptMode.email;
  }
  if (keyboardType == TextInputType.phone ||
      keyboardType == TextInputType.number ||
      keyboardType == TextInputType.datetime) {
    return AppSpeechTranscriptMode.digits;
  }
  if (keyboardType == const TextInputType.numberWithOptions() ||
      keyboardType == const TextInputType.numberWithOptions(decimal: true) ||
      keyboardType == const TextInputType.numberWithOptions(signed: true) ||
      keyboardType ==
          const TextInputType.numberWithOptions(signed: true, decimal: true)) {
    return AppSpeechTranscriptMode.decimal;
  }
  return AppSpeechTranscriptMode.text;
}

/// Normalizes a spoken transcript for the given [mode].
String appSpeechNormalizeTranscript(
  String transcript, {
  AppSpeechTranscriptMode mode = AppSpeechTranscriptMode.text,
}) {
  final String trimmed = transcript.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }

  return switch (mode) {
    AppSpeechTranscriptMode.digits => _normalizeSpokenNumberField(
      trimmed,
      allowDecimal: false,
    ),
    AppSpeechTranscriptMode.decimal => _normalizeSpokenNumberField(
      trimmed,
      allowDecimal: true,
    ),
    AppSpeechTranscriptMode.email => _normalizeSpokenEmail(trimmed),
    AppSpeechTranscriptMode.text => _normalizeSpokenText(trimmed),
  };
}

/// Convenience transform used by digit-only shared fields.
String appSpeechDigitsOnlyTranscript(
  String transcript, {
  bool allowDecimal = false,
}) {
  return appSpeechNormalizeTranscript(
    transcript,
    mode: allowDecimal
        ? AppSpeechTranscriptMode.decimal
        : AppSpeechTranscriptMode.digits,
  );
}

/// Default transform for free-text / search / select / rich-text fields.
String appSpeechTextTranscript(String transcript) {
  return appSpeechNormalizeTranscript(
    transcript,
    mode: AppSpeechTranscriptMode.text,
  );
}

/// Default transform for email fields.
String appSpeechEmailTranscript(String transcript) {
  return appSpeechNormalizeTranscript(
    transcript,
    mode: AppSpeechTranscriptMode.email,
  );
}

String Function(String transcript) appSpeechTranscriptTransformForMode(
  AppSpeechTranscriptMode mode,
) {
  return (String transcript) =>
      appSpeechNormalizeTranscript(transcript, mode: mode);
}

String Function(String transcript) appSpeechTranscriptTransformForKeyboard(
  TextInputType? keyboardType,
) {
  return appSpeechTranscriptTransformForMode(
    appSpeechTranscriptModeForKeyboard(keyboardType),
  );
}

// --- Token helpers -----------------------------------------------------------

List<String> _speechTokens(String transcript) {
  final String normalized = transcript
      .toLowerCase()
      .replaceAll(RegExp(r'[—–]'), '-')
      .replaceAllMapped(
        RegExp(r'(\d)[,\s]+(?=\d)'),
        (Match match) => match.group(1)!,
      );
  // Keep hyphenated number words as separate tokens ("twenty-five").
  final String spaced = normalized.replaceAll('-', ' ');
  return spaced
      .split(RegExp(r'\s+'))
      .map((String token) => token.trim())
      .where((String token) => token.isNotEmpty)
      .toList(growable: false);
}

const Map<String, int> _speechOnes = <String, int>{
  'zero': 0,
  'oh': 0,
  'o': 0,
  'nought': 0,
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
};

const Map<String, int> _speechTeens = <String, int>{
  'ten': 10,
  'eleven': 11,
  'twelve': 12,
  'thirteen': 13,
  'fourteen': 14,
  'fifteen': 15,
  'sixteen': 16,
  'seventeen': 17,
  'eighteen': 18,
  'nineteen': 19,
};

const Map<String, int> _speechTens = <String, int>{
  'twenty': 20,
  'thirty': 30,
  'forty': 40,
  'fourty': 40,
  'fifty': 50,
  'sixty': 60,
  'seventy': 70,
  'eighty': 80,
  'ninety': 90,
};

const Map<String, int> _speechScales = <String, int>{
  'hundred': 100,
  'thousand': 1000,
  'million': 1000000,
  'billion': 1000000000,
};

bool _isSpokenNumberAtom(String token, {bool allowAnd = false}) {
  if (token == 'and') {
    return allowAnd;
  }
  if (_speechOnes.containsKey(token) ||
      _speechTeens.containsKey(token) ||
      _speechTens.containsKey(token) ||
      _speechScales.containsKey(token) ||
      token == 'point' ||
      token == 'dot') {
    return true;
  }
  return RegExp(r'^\d+(\.\d+)?$').hasMatch(token);
}

bool _spokenNumberPhraseNeedsCardinal(List<String> tokens) {
  for (final String token in tokens) {
    if (_speechTeens.containsKey(token) ||
        _speechTens.containsKey(token) ||
        _speechScales.containsKey(token)) {
      return true;
    }
  }
  return false;
}

/// Parses a spoken English cardinal / decimal phrase into a numeric string.
///
/// Examples: `one thousand two hundred twenty-five` → `1225`,
/// `twelve point five` → `12.5`.
String? parseSpokenEnglishNumber(
  String transcript, {
  bool allowDecimal = true,
}) {
  final List<String> tokens = _speechTokens(transcript)
      .where((String token) => token != 'and')
      .toList(growable: false);
  if (tokens.isEmpty) {
    return null;
  }

  final int pointIndex = tokens.indexWhere(
    (String token) => token == 'point' || token == 'dot',
  );
  final List<String> wholeTokens = pointIndex >= 0
      ? tokens.sublist(0, pointIndex)
      : tokens;
  final List<String> fractionTokens = pointIndex >= 0
      ? tokens.sublist(pointIndex + 1)
      : const <String>[];

  if (!allowDecimal && fractionTokens.isNotEmpty) {
    return null;
  }

  final int? whole = wholeTokens.isEmpty
      ? (pointIndex >= 0 ? 0 : null)
      : _parseSpokenCardinalTokens(wholeTokens);
  if (whole == null) {
    return null;
  }

  if (fractionTokens.isEmpty) {
    return whole.toString();
  }

  final String fractionDigits = _spokenFractionDigits(fractionTokens);
  if (fractionDigits.isEmpty) {
    return whole.toString();
  }
  return '$whole.$fractionDigits';
}

int? _parseSpokenCardinalTokens(List<String> tokens) {
  if (tokens.isEmpty) {
    return null;
  }
  if (!_spokenNumberPhraseNeedsCardinal(tokens) &&
      tokens.every(
        (String token) =>
            _speechOnes.containsKey(token) || RegExp(r'^\d+$').hasMatch(token),
      )) {
    // Digit-by-digit: "one two two five" → 1225, not 1+2+2+5.
    return null;
  }

  var total = 0;
  var current = 0;
  var sawNumber = false;

  for (final String token in tokens) {
    final int? arabic = int.tryParse(token);
    if (arabic != null) {
      current += arabic;
      sawNumber = true;
      continue;
    }
    final int? one = _speechOnes[token];
    if (one != null) {
      current += one;
      sawNumber = true;
      continue;
    }
    final int? teen = _speechTeens[token];
    if (teen != null) {
      current += teen;
      sawNumber = true;
      continue;
    }
    final int? ten = _speechTens[token];
    if (ten != null) {
      current += ten;
      sawNumber = true;
      continue;
    }
    final int? scale = _speechScales[token];
    if (scale != null) {
      if (scale == 100) {
        current = (current == 0 ? 1 : current) * 100;
      } else {
        total += (current == 0 ? 1 : current) * scale;
        current = 0;
      }
      sawNumber = true;
      continue;
    }
    return null;
  }

  if (!sawNumber) {
    return null;
  }
  return total + current;
}

String _spokenFractionDigits(List<String> tokens) {
  final StringBuffer buffer = StringBuffer();
  for (final String token in tokens) {
    final int? arabic = int.tryParse(token);
    if (arabic != null) {
      buffer.write(token);
      continue;
    }
    final int? one = _speechOnes[token];
    if (one != null) {
      buffer.write(one);
      continue;
    }
    final int? teen = _speechTeens[token];
    if (teen != null) {
      buffer.write(teen);
      continue;
    }
    final int? ten = _speechTens[token];
    if (ten != null) {
      buffer.write(ten);
      continue;
    }
  }
  return buffer.toString();
}

String _digitSequenceFromTokens(List<String> tokens, {required bool allowDecimal}) {
  final StringBuffer buffer = StringBuffer();
  var wroteDecimal = false;
  for (final String token in tokens) {
    if (allowDecimal && (token == 'point' || token == 'dot')) {
      if (!wroteDecimal && !buffer.toString().contains('.')) {
        buffer.write('.');
        wroteDecimal = true;
      }
      continue;
    }
    final int? one = _speechOnes[token];
    if (one != null) {
      buffer.write(one);
      continue;
    }
    final int? teen = _speechTeens[token];
    if (teen != null) {
      buffer.write(teen);
      continue;
    }
    final int? ten = _speechTens[token];
    if (ten != null) {
      buffer.write(ten);
      continue;
    }
    for (final int codeUnit in token.codeUnits) {
      final String char = String.fromCharCode(codeUnit);
      if (RegExp(r'[0-9]').hasMatch(char)) {
        buffer.write(char);
      } else if (allowDecimal && (char == '.' || char == ',') && !wroteDecimal) {
        buffer.write('.');
        wroteDecimal = true;
      }
    }
  }
  return buffer.toString();
}

String _normalizeSpokenNumberField(
  String transcript, {
  required bool allowDecimal,
}) {
  final String? cardinal = parseSpokenEnglishNumber(
    transcript,
    allowDecimal: allowDecimal,
  );
  if (cardinal != null) {
    return cardinal;
  }
  return _digitSequenceFromTokens(
    _speechTokens(transcript),
    allowDecimal: allowDecimal,
  );
}

// --- Spoken dates ------------------------------------------------------------

/// Day / month / year fragments recognized from a spoken date utterance.
@immutable
class AppSpokenDateParts {
  const AppSpokenDateParts({this.day, this.month, this.year});

  final int? day;
  final int? month;
  final int? year;

  bool get isEmpty => day == null && month == null && year == null;

  bool get hasAny => !isEmpty;
}

const Map<String, int> _speechMonths = <String, int>{
  'jan': 1,
  'january': 1,
  'feb': 2,
  'february': 2,
  'mar': 3,
  'march': 3,
  'apr': 4,
  'april': 4,
  'may': 5,
  'jun': 6,
  'june': 6,
  'jul': 7,
  'july': 7,
  'aug': 8,
  'august': 8,
  'sep': 9,
  'sept': 9,
  'september': 9,
  'oct': 10,
  'october': 10,
  'nov': 11,
  'november': 11,
  'dec': 12,
  'december': 12,
};

const Map<String, int> _speechOrdinalOnes = <String, int>{
  'first': 1,
  'second': 2,
  'third': 3,
  'fourth': 4,
  'fifth': 5,
  'sixth': 6,
  'seventh': 7,
  'eighth': 8,
  'ninth': 9,
};

const Map<String, int> _speechOrdinals = <String, int>{
  ..._speechOrdinalOnes,
  'tenth': 10,
  'eleventh': 11,
  'twelfth': 12,
  'thirteenth': 13,
  'fourteenth': 14,
  'fifteenth': 15,
  'sixteenth': 16,
  'seventeenth': 17,
  'eighteenth': 18,
  'nineteenth': 19,
  'twentieth': 20,
  'twentyfirst': 21,
  'twentysecond': 22,
  'twentythird': 23,
  'twentyfourth': 24,
  'twentyfifth': 25,
  'twentysixth': 26,
  'twentyseventh': 27,
  'twentyeighth': 28,
  'twentyninth': 29,
  'thirtieth': 30,
  'thirtyfirst': 31,
};

final RegExp _speechOrdinalSuffix = RegExp(r'(?:st|nd|rd|th)$');

/// Parses spoken / typed date phrases into day, month, and year parts.
///
/// Understands common forms such as:
/// - `15/03/2024`, `2024-03-15`, `15.3.24`
/// - `March 15 2024`, `15 March 2024`, `March 15th, 2024`
/// - `march fifteenth twenty twenty four`
/// - partial utterances: `March`, `fifteen`, `two thousand twenty four`
AppSpokenDateParts? parseSpokenDateParts(String transcript) {
  final String trimmed = transcript.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final AppSpokenDateParts? numeric = _parseNumericDateParts(trimmed);
  if (numeric != null && numeric.hasAny) {
    return numeric;
  }

  final List<String> tokens = _speechDateTokens(trimmed);
  if (tokens.isEmpty) {
    return null;
  }

  return _parseSpokenDateTokens(tokens);
}

/// Digits-only fallback for a single focused date part (day/month/year).
String appSpeechDatePartTranscript(String transcript, {required int maxLength}) {
  final AppSpokenDateParts? parts = parseSpokenDateParts(transcript);
  if (parts != null) {
    if (parts.year != null &&
        parts.day == null &&
        parts.month == null &&
        maxLength >= 4) {
      return parts.year.toString().padLeft(4, '0').substring(0, 4);
    }
    if (parts.month != null && parts.day == null && parts.year == null) {
      return parts.month.toString().padLeft(2, '0');
    }
    if (parts.day != null && parts.month == null && parts.year == null) {
      return parts.day.toString().padLeft(2, '0');
    }
  }

  final String digits = appSpeechDigitsOnlyTranscript(transcript);
  if (digits.isEmpty) {
    return digits;
  }
  return digits.length <= maxLength ? digits : digits.substring(0, maxLength);
}

List<String> _speechDateTokens(String transcript) {
  final String normalized = transcript
      .toLowerCase()
      .replaceAll(RegExp(r'[—–]'), '-')
      .replaceAll(RegExp(r'[/.\-,]'), ' ')
      .replaceAll(RegExp(r'\b(of|the|on|in|day|date|slash)\b'), ' ')
      .replaceAll('-', ' ');
  return normalized
      .split(RegExp(r'\s+'))
      .map((String token) => token.trim())
      .where((String token) => token.isNotEmpty)
      .toList(growable: false);
}

AppSpokenDateParts? _parseNumericDateParts(String transcript) {
  final String compact = transcript.trim();
  final Match? iso = RegExp(
    r'^(\d{4})[./\-](\d{1,2})[./\-](\d{1,2})$',
  ).firstMatch(compact);
  if (iso != null) {
    return _validatedDateParts(
      year: int.tryParse(iso.group(1)!),
      month: int.tryParse(iso.group(2)!),
      day: int.tryParse(iso.group(3)!),
    );
  }

  final Match? dmy = RegExp(
    r'^(\d{1,2})[./\-](\d{1,2})[./\-](\d{2,4})$',
  ).firstMatch(compact);
  if (dmy != null) {
    return _validatedDateParts(
      day: int.tryParse(dmy.group(1)!),
      month: int.tryParse(dmy.group(2)!),
      year: _normalizeSpokenYear(int.tryParse(dmy.group(3)!)),
    );
  }

  return null;
}

AppSpokenDateParts? _parseSpokenDateTokens(List<String> tokens) {
  int? day;
  int? month;
  int? year;
  final List<String> numberTokens = <String>[];

  var index = 0;
  while (index < tokens.length) {
    final String token = tokens[index];
    final int? monthValue = _speechMonths[token];
    if (monthValue != null) {
      month = monthValue;
      index += 1;
      continue;
    }

    // "twenty first" / "thirty first" after hyphen splitting.
    if (_speechTens.containsKey(token) && index + 1 < tokens.length) {
      final int? ordinalOne = _speechOrdinalOnes[tokens[index + 1]];
      if (ordinalOne != null) {
        day = _speechTens[token]! + ordinalOne;
        index += 2;
        continue;
      }
    }

    final int? ordinal = _speechDayOrdinal(token);
    if (ordinal != null) {
      day = ordinal;
      index += 1;
      continue;
    }

    if (token == 'and') {
      index += 1;
      continue;
    }

    numberTokens.add(token);
    index += 1;
  }

  if (numberTokens.isNotEmpty) {
    final ({int? day, int? year}) numbers = _extractDayAndYearFromNumberTokens(
      numberTokens,
      dayAlreadySet: day != null,
    );
    day ??= numbers.day;
    year ??= numbers.year;
  }

  final AppSpokenDateParts parts = AppSpokenDateParts(
    day: day,
    month: month,
    year: year,
  );
  return parts.hasAny ? parts : null;
}

({int? day, int? year}) _extractDayAndYearFromNumberTokens(
  List<String> tokens, {
  required bool dayAlreadySet,
}) {
  // Prefer an explicit 4-digit year anywhere in the token list.
  for (var i = 0; i < tokens.length; i++) {
    final int? arabic = int.tryParse(tokens[i]);
    if (arabic != null && arabic >= 1000 && arabic <= 9999) {
      final List<String> remaining = <String>[
        ...tokens.sublist(0, i),
        ...tokens.sublist(i + 1),
      ];
      return (
        day: dayAlreadySet ? null : _parseDayNumberTokens(remaining),
        year: arabic,
      );
    }
  }

  // Whole phrase is a year: "twenty twenty four", "two thousand twenty four".
  final int? wholePairedYear = _parsePairedCenturyYear(tokens);
  if (wholePairedYear != null && _isPlausibleSpokenYear(wholePairedYear)) {
    return (day: null, year: wholePairedYear);
  }
  final bool hasYearScale = tokens.any(
    (String token) => token == 'thousand' || token == 'hundred',
  );
  if (hasYearScale) {
    final int? wholeCardinalYear = _parseCardinalYear(tokens);
    if (wholeCardinalYear != null &&
        wholeCardinalYear >= 1000 &&
        _isPlausibleSpokenYear(wholeCardinalYear)) {
      return (day: null, year: wholeCardinalYear);
    }
  }

  // Leading day + trailing year: "fifteen twenty twenty four".
  if (!dayAlreadySet && tokens.length >= 3) {
    ({int day, int year})? best;
    for (var split = 1; split < tokens.length; split++) {
      final int? maybeDay = _parseDayNumberTokens(tokens.sublist(0, split));
      final int? maybeYear = _parsePairedCenturyYear(tokens.sublist(split)) ??
          _parseCardinalYear(tokens.sublist(split));
      if (maybeDay == null ||
          maybeYear == null ||
          !_isPlausibleSpokenYear(maybeYear)) {
        continue;
      }
      // Prefer the longest year phrase (smallest day split wins ties later).
      if (best == null || maybeYear > 99) {
        best = (day: maybeDay, year: maybeYear);
      }
    }
    if (best != null) {
      return (day: best.day, year: best.year);
    }
  }

  if (!dayAlreadySet) {
    final int? dayOnly = _parseDayNumberTokens(tokens);
    if (dayOnly != null) {
      return (day: dayOnly, year: null);
    }
  }

  final int? yearOnly = _normalizeSpokenYear(int.tryParse(tokens.join()));
  return (day: null, year: yearOnly);
}

bool _isPlausibleSpokenYear(int year) => year >= 1900 && year <= 2100;

int? _parseDayNumberTokens(List<String> tokens) {
  if (tokens.isEmpty) {
    return null;
  }
  if (tokens.length == 1) {
    final String token = tokens.first;
    final int? ordinal = _speechDayOrdinal(token);
    if (ordinal != null) {
      return ordinal;
    }
    final int? arabic = int.tryParse(token.replaceAll(_speechOrdinalSuffix, ''));
    if (arabic != null && arabic >= 1 && arabic <= 31) {
      return arabic;
    }
  }

  final String? cardinal = parseSpokenEnglishNumber(
    tokens.join(' '),
    allowDecimal: false,
  );
  final int? value = int.tryParse(cardinal ?? '');
  if (value != null && value >= 1 && value <= 31) {
    return value;
  }
  return null;
}

int? _speechDayOrdinal(String token) {
  final String compact = token.replaceAll('-', '').replaceAll(' ', '');
  final int? named = _speechOrdinals[compact];
  if (named != null) {
    return named;
  }
  final Match? suffixed = RegExp(
    r'^(\d{1,2})(?:st|nd|rd|th)$',
  ).firstMatch(token);
  if (suffixed != null) {
    final int? value = int.tryParse(suffixed.group(1)!);
    if (value != null && value >= 1 && value <= 31) {
      return value;
    }
  }
  return null;
}

int? _parsePairedCenturyYear(List<String> tokens) {
  // "twenty twenty four" → 2024, "nineteen ninety nine" → 1999
  if (tokens.length < 2 || tokens.length > 4) {
    return null;
  }

  final int? first = _parseTwoDigitSpoken(tokens, 0);
  if (first == null) {
    return null;
  }
  final int? firstLen = _twoDigitTokenLength(tokens, 0);
  if (firstLen == null || firstLen >= tokens.length) {
    return null;
  }
  final int? second = _parseTwoDigitSpoken(tokens, firstLen);
  if (second == null) {
    return null;
  }
  final int secondLen = _twoDigitTokenLength(tokens, firstLen) ?? 0;
  if (firstLen + secondLen != tokens.length) {
    return null;
  }
  if (first < 10 || first > 99 || second > 99) {
    return null;
  }
  return first * 100 + second;
}

int? _parseTwoDigitSpoken(List<String> tokens, int start) {
  if (start >= tokens.length) {
    return null;
  }
  final String first = tokens[start];
  final int? arabic = int.tryParse(first);
  if (arabic != null && arabic >= 0 && arabic <= 99) {
    return arabic;
  }
  if (_speechTeens.containsKey(first)) {
    return _speechTeens[first];
  }
  if (_speechTens.containsKey(first)) {
    if (start + 1 < tokens.length && _speechOnes.containsKey(tokens[start + 1])) {
      return _speechTens[first]! + _speechOnes[tokens[start + 1]]!;
    }
    return _speechTens[first];
  }
  if (_speechOnes.containsKey(first)) {
    return _speechOnes[first];
  }
  return null;
}

int? _twoDigitTokenLength(List<String> tokens, int start) {
  if (start >= tokens.length) {
    return null;
  }
  final String first = tokens[start];
  if (int.tryParse(first) != null ||
      _speechTeens.containsKey(first) ||
      _speechOnes.containsKey(first)) {
    return 1;
  }
  if (_speechTens.containsKey(first)) {
    if (start + 1 < tokens.length && _speechOnes.containsKey(tokens[start + 1])) {
      return 2;
    }
    return 1;
  }
  return null;
}

int? _parseCardinalYear(List<String> tokens) {
  final String? cardinal = parseSpokenEnglishNumber(
    tokens.join(' '),
    allowDecimal: false,
  );
  return _normalizeSpokenYear(int.tryParse(cardinal ?? ''));
}

int? _normalizeSpokenYear(int? value) {
  if (value == null) {
    return null;
  }
  if (value >= 1000 && value <= 9999) {
    return value;
  }
  // Two-digit years: 00-49 → 2000s, 50-99 → 1900s.
  if (value >= 0 && value <= 99) {
    return value <= 49 ? 2000 + value : 1900 + value;
  }
  return null;
}

AppSpokenDateParts? _validatedDateParts({
  int? day,
  int? month,
  int? year,
}) {
  final int? safeDay = (day != null && day >= 1 && day <= 31) ? day : null;
  final int? safeMonth =
      (month != null && month >= 1 && month <= 12) ? month : null;
  final int? safeYear = _normalizeSpokenYear(year);
  if (safeDay == null && safeMonth == null && safeYear == null) {
    return null;
  }
  return AppSpokenDateParts(day: safeDay, month: safeMonth, year: safeYear);
}

// --- Email / text ------------------------------------------------------------

const Map<String, String> _speechEmailSymbols = <String, String>{
  'at': '@',
  'dot': '.',
  'period': '.',
  'underscore': '_',
  'underline': '_',
  'dash': '-',
  'hyphen': '-',
  'minus': '-',
  'plus': '+',
};

const List<(List<String> phrase, String replacement)> _speechTextPhrases =
    <(List<String>, String)>[
      (<String>['question', 'mark'], '?'),
      (<String>['exclamation', 'mark'], '!'),
      (<String>['exclamation', 'point'], '!'),
      (<String>['full', 'stop'], '.'),
      (<String>['new', 'line'], '\n'),
      (<String>['new', 'paragraph'], '\n\n'),
      (<String>['open', 'paren'], '('),
      (<String>['close', 'paren'], ')'),
      (<String>['open', 'parenthesis'], '('),
      (<String>['close', 'parenthesis'], ')'),
      (<String>['open', 'quote'], '"'),
      (<String>['close', 'quote'], '"'),
      (<String>['under', 'score'], '_'),
    ];

const Map<String, String> _speechTextSymbols = <String, String>{
  'period': '.',
  'comma': ',',
  'colon': ':',
  'semicolon': ';',
  'slash': '/',
  'backslash': r'\',
  'apostrophe': "'",
  'quote': '"',
  'ampersand': '&',
  'percent': '%',
  'hash': '#',
  'pound': '#',
  'at': '@',
  'dot': '.',
  'underscore': '_',
  'dash': '-',
  'hyphen': '-',
  'plus': '+',
};

String _normalizeSpokenEmail(String transcript) {
  final List<String> tokens = _speechTokens(transcript);
  final StringBuffer buffer = StringBuffer();
  for (var i = 0; i < tokens.length; i++) {
    if (i + 1 < tokens.length &&
        tokens[i] == 'under' &&
        tokens[i + 1] == 'score') {
      buffer.write('_');
      i++;
      continue;
    }
    final String? symbol = _speechEmailSymbols[tokens[i]];
    if (symbol != null) {
      buffer.write(symbol);
      continue;
    }
    buffer.write(tokens[i]);
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), '');
}

String _normalizeSpokenText(String transcript) {
  final List<String> tokens = _speechTokens(transcript);
  final List<String> output = <String>[];
  var index = 0;
  while (index < tokens.length) {
    final int? phraseEnd = _matchTextPhrase(tokens, index);
    if (phraseEnd != null) {
      final List<String> phrase = tokens.sublist(index, phraseEnd);
      output.add(_replacementForTextPhrase(phrase));
      index = phraseEnd;
      continue;
    }

    if (_isSpokenNumberAtom(tokens[index])) {
      final int numberEnd = _consumeNumberPhrase(tokens, index);
      final List<String> numberTokens = tokens.sublist(index, numberEnd);
      final String phrase = numberTokens.join(' ');
      final String digits = _digitSequenceFromTokens(
        numberTokens,
        allowDecimal: true,
      );
      final String? parsed = parseSpokenEnglishNumber(phrase) ??
          (digits.isEmpty ? null : digits);
      if (parsed != null && parsed.isNotEmpty) {
        output.add(parsed);
        index = numberEnd;
        continue;
      }
    }

    final String? symbol = _speechTextSymbols[tokens[index]];
    if (symbol != null) {
      output.add(symbol);
      index++;
      continue;
    }

    output.add(tokens[index]);
    index++;
  }

  return _joinSpokenTextTokens(output);
}

int? _matchTextPhrase(List<String> tokens, int index) {
  for (final (List<String> phrase, String _) in _speechTextPhrases) {
    if (index + phrase.length > tokens.length) {
      continue;
    }
    var matches = true;
    for (var i = 0; i < phrase.length; i++) {
      if (tokens[index + i] != phrase[i]) {
        matches = false;
        break;
      }
    }
    if (matches) {
      return index + phrase.length;
    }
  }
  return null;
}

String _replacementForTextPhrase(List<String> phrase) {
  for (final (List<String> candidate, String replacement) in _speechTextPhrases) {
    if (candidate.length == phrase.length) {
      var matches = true;
      for (var i = 0; i < candidate.length; i++) {
        if (candidate[i] != phrase[i]) {
          matches = false;
          break;
        }
      }
      if (matches) {
        return replacement;
      }
    }
  }
  return phrase.join(' ');
}

int _consumeNumberPhrase(List<String> tokens, int start) {
  var end = start;
  while (end < tokens.length) {
    final String token = tokens[end];
    if (token == 'and') {
      final bool nextIsNumber =
          end + 1 < tokens.length && _isSpokenNumberAtom(tokens[end + 1]);
      if (nextIsNumber) {
        end++;
        continue;
      }
      break;
    }
    if (!_isSpokenNumberAtom(token)) {
      break;
    }
    end++;
  }
  return end;
}

String _joinSpokenTextTokens(List<String> tokens) {
  final StringBuffer buffer = StringBuffer();
  for (var i = 0; i < tokens.length; i++) {
    final String token = tokens[i];
    if (token.isEmpty) {
      continue;
    }
    final bool isPunctuation = RegExp(r'''^[.,:;!?%@#&/\\_"'()]+$''').hasMatch(
      token,
    );
    final bool isNewline = token.contains('\n');
    if (buffer.isEmpty || isNewline) {
      buffer.write(token);
      continue;
    }
    if (isPunctuation) {
      // Trim a trailing space before punctuation.
      final String current = buffer.toString();
      if (current.endsWith(' ')) {
        buffer.clear();
        buffer.write(current.trimRight());
      }
      buffer.write(token);
      if (token == '.' ||
          token == ',' ||
          token == ';' ||
          token == ':' ||
          token == '!' ||
          token == '?') {
        buffer.write(' ');
      }
      continue;
    }
    if (!buffer.toString().endsWith(' ') &&
        !buffer.toString().endsWith('\n') &&
        !buffer.toString().endsWith('(')) {
      buffer.write(' ');
    }
    buffer.write(token);
  }
  return buffer.toString().replaceAll(RegExp(r'[ \t]+\n'), '\n').trimRight();
}

/// Why dictation ended without the user turning it off.
enum AppSpeechToTextInterruption { permissionDenied, unavailable, error }

/// How the coordinator treats a recognizer error while dictation is on.
enum AppSpeechErrorKind {
  /// Silence, no match or a recognizer that just ended: restart quietly.
  soft,

  /// Network/server/busy style failures: restart with backoff, give up after
  /// repeated failures.
  retryable,

  /// Microphone or speech permission was revoked.
  permissionDenied,

  /// The recognizer or language cannot be used on this device.
  unavailable,
}

const Set<String> _appSpeechSoftErrors = <String>{
  // Android
  'error_speech_timeout',
  'error_no_match',
  'error_client',
  // iOS
  'error_retry',
  // Web SpeechRecognition
  'no-speech',
  'aborted',
};

const Set<String> _appSpeechPermissionErrors = <String>{
  'error_permission',
  'not-allowed',
  'service-not-allowed',
};

const Set<String> _appSpeechUnavailableErrors = <String>{
  'error_language_not_supported',
  'error_language_unavailable',
  'error_speech_recognizer_disabled',
  'audio-capture',
  'language-not-supported',
  'speech_not_supported',
  'not supported',
};

/// Classifies a plugin error string (Android `error_*`, iOS, web).
AppSpeechErrorKind appSpeechErrorKind(String error) {
  final String code = error.trim().toLowerCase();
  if (_appSpeechSoftErrors.contains(code)) {
    return AppSpeechErrorKind.soft;
  }
  if (_appSpeechPermissionErrors.contains(code)) {
    return AppSpeechErrorKind.permissionDenied;
  }
  if (_appSpeechUnavailableErrors.contains(code)) {
    return AppSpeechErrorKind.unavailable;
  }
  return AppSpeechErrorKind.retryable;
}

/// Everything needed to (re)start the recognizer for one field.
final class _SpeechDictation {
  const _SpeechDictation({
    required this.owner,
    required this.controller,
    required this.onChanged,
    required this.transcriptTransform,
    required this.onSpeechResult,
    required this.aiFormatter,
    required this.aiFormatMode,
    required this.aiFormatHint,
    required this.locale,
    required this.separator,
  });

  final Object owner;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String Function(String transcript) transcriptTransform;
  final void Function(String transcript, {required bool isFinal})?
  onSpeechResult;
  final AppSpeechAiFormatter? aiFormatter;
  final String aiFormatMode;
  final String? aiFormatHint;
  final String? locale;
  final String separator;
}

/// Ensures only one field listens at a time, and keeps that field listening
/// until the user turns dictation off.
///
/// Platform recognizers end a session after a phrase or a short silence
/// (Android in particular). While dictation is on, the coordinator restarts
/// the recognizer for the same field and re-anchors at the caret, so earlier
/// words are kept. Dictation only ends on an explicit stop, another field
/// starting, the owner going away, the app leaving the foreground, lost
/// permission, an unavailable recognizer, or repeated failures.
final class AppSpeechToTextCoordinator extends ChangeNotifier
    with WidgetsBindingObserver {
  AppSpeechToTextCoordinator({
    AppSpeechRecognizer? recognizer,
    Duration restartDelay = const Duration(milliseconds: 150),
    Duration failureBackoff = const Duration(milliseconds: 500),
    Duration healthyListenDuration = const Duration(seconds: 1),
    int maxConsecutiveFailures = 3,
  }) : _recognizer = recognizer ?? SpeechToTextAppSpeechRecognizer(),
       _restartDelay = restartDelay,
       _failureBackoff = failureBackoff,
       _healthyListenDuration = healthyListenDuration,
       _maxConsecutiveFailures = maxConsecutiveFailures;

  static AppSpeechToTextCoordinator? _instance;

  static AppSpeechToTextCoordinator get instance =>
      _instance ??= AppSpeechToTextCoordinator();

  @visibleForTesting
  static set debugInstance(AppSpeechToTextCoordinator? value) {
    _instance = value;
  }

  final AppSpeechRecognizer _recognizer;
  final Duration _restartDelay;
  final Duration _failureBackoff;
  final Duration _healthyListenDuration;
  final int _maxConsecutiveFailures;

  /// The user's intent: non-null while dictation is on for a field.
  _SpeechDictation? _dictation;
  String _sessionPrefix = '';
  String _sessionSuffix = '';

  /// Separator still owed before the first phrase after a restart, so the
  /// next phrase does not run into the previous one.
  String _pendingJoiner = '';

  /// Bumped each time the span is re-anchored after a recognizer restart.
  int _spanEpoch = 0;

  /// Phrases already finalized in this recognizer session, as written into
  /// the span.
  String _sessionCommitted = '';

  /// What currently occupies the span (committed phrases plus the live one).
  String _sessionSpan = '';

  /// Identifies the recognizer session callbacks belong to.
  int _listenGeneration = 0;
  bool _listenHealthy = false;
  int _consecutiveFailures = 0;
  int? _failureCountedGeneration;
  Timer? _restartTimer;
  Timer? _healthyTimer;
  bool _observingLifecycle = false;

  int _interruptionSerial = 0;
  ({int serial, Object owner, AppSpeechToTextInterruption reason})?
  _lastInterruption;

  AppSpeechInitStatus _initStatus = AppSpeechInitStatus.unavailable;
  String? _lastError;
  int _formatGeneration = 0;
  AppSpeechAiAbort? _activeFormatAbort;
  Object? _formattingOwner;

  Object? get activeOwner => _dictation?.owner;

  /// True while dictation is on, including the short gaps while the
  /// recognizer restarts, so the mic never flickers back to idle.
  bool get isListening => _dictation != null;
  AppSpeechInitStatus get initStatus => _initStatus;
  String? get lastError => _lastError;
  bool get isFormatting => _formattingOwner != null;

  /// The most recent dictation that ended on its own (lost permission,
  /// unavailable recognizer, repeated failures). [serial] grows with each one.
  ({int serial, Object owner, AppSpeechToTextInterruption reason})?
  get lastInterruption => _lastInterruption;

  bool isListeningFor(Object owner) => _dictation?.owner == owner;

  bool isFormattingFor(Object owner) => _formattingOwner == owner;

  void _cancelInFlightFormat({bool notify = true}) {
    _formatGeneration += 1;
    _activeFormatAbort?.abort();
    _activeFormatAbort = null;
    if (_formattingOwner != null) {
      _formattingOwner = null;
      if (notify) {
        notifyListeners();
      }
    }
  }

  Future<AppSpeechInitStatus> ensureReady() async {
    _initStatus = await _recognizer.ensureReady(
      onStatus: (_) => notifyListeners(),
      onError: (String error) {
        _lastError = error;
        notifyListeners();
      },
    );
    notifyListeners();
    return _initStatus;
  }

  /// Starts dictation for [owner]. If another field was listening, stops it
  /// and returns `true` so the caller can warn the user.
  ///
  /// When [onSpeechResult] is provided, transformed transcripts are delivered
  /// there instead of being inserted into [controller]. Use this for composite
  /// fields (e.g. date parts) that distribute a single utterance.
  Future<({bool started, bool stoppedOther})> start({
    required Object owner,
    required TextEditingController controller,
    required ValueChanged<String>? onChanged,
    String Function(String transcript)? transcriptTransform,
    void Function(String transcript, {required bool isFinal})? onSpeechResult,
    AppSpeechAiFormatter? aiFormatter,
    String aiFormatMode = 'text',
    String? aiFormatHint,
    String? locale,
    String segmentSeparator = ' ',
  }) async {
    var stoppedOther = false;
    final Object? previousOwner = _dictation?.owner;
    if (previousOwner != null && previousOwner != owner) {
      await stop(owner: previousOwner);
      stoppedOther = true;
    }
    _cancelInFlightFormat();

    final AppSpeechInitStatus status = await ensureReady();
    if (status != AppSpeechInitStatus.ready) {
      return (started: false, stoppedOther: stoppedOther);
    }

    final _SpeechDictation dictation = _SpeechDictation(
      owner: owner,
      controller: controller,
      onChanged: onChanged,
      transcriptTransform: transcriptTransform ?? appSpeechTextTranscript,
      onSpeechResult: onSpeechResult,
      aiFormatter: aiFormatter,
      aiFormatMode: aiFormatMode,
      aiFormatHint: aiFormatHint,
      locale: locale,
      separator: segmentSeparator,
    );
    final ({String prefix, String suffix}) bounds =
        captureSpeechSessionBounds(controller);
    _dictation = dictation;
    _sessionPrefix = bounds.prefix;
    _sessionSuffix = bounds.suffix;
    _pendingJoiner = '';
    _sessionCommitted = '';
    _sessionSpan = '';
    _consecutiveFailures = 0;
    _failureCountedGeneration = null;
    _lastError = null;
    _attachLifecycle();
    notifyListeners();

    if (!await _listen(dictation)) {
      if (identical(_dictation, dictation)) {
        _endDictation();
      }
      notifyListeners();
      return (started: false, stoppedOther: stoppedOther);
    }

    notifyListeners();
    return (started: true, stoppedOther: stoppedOther);
  }

  bool _isCurrent(_SpeechDictation dictation, int generation) {
    return identical(_dictation, dictation) && generation == _listenGeneration;
  }

  /// Starts one recognizer session for [dictation]. Returns false when the
  /// recognizer refused to start.
  Future<bool> _listen(_SpeechDictation dictation) async {
    final int generation = ++_listenGeneration;
    _listenHealthy = false;
    _healthyTimer?.cancel();
    _healthyTimer = null;
    try {
      await _recognizer.startListening(
        onResult: (String words, {required bool isFinal}) {
          if (_isCurrent(dictation, generation)) {
            _handleResult(dictation, words, isFinal: isFinal);
          }
        },
        onStatus: (String status) {
          if (!_isCurrent(dictation, generation)) {
            return;
          }
          if ((status == 'done' || status == 'notListening') &&
              !_recognizer.isListening) {
            _handleListenEnded(dictation, generation);
          }
          notifyListeners();
        },
        onError: (String error) {
          if (!_isCurrent(dictation, generation)) {
            return;
          }
          _lastError = error;
          _handleListenError(dictation, generation, error);
          notifyListeners();
        },
      );
    } on Object catch (error) {
      if (identical(_dictation, dictation)) {
        _lastError = error.toString();
      }
      return false;
    }
    if (_isCurrent(dictation, generation) && !_listenHealthy) {
      _healthyTimer = Timer(_healthyListenDuration, () {
        _healthyTimer = null;
        if (_isCurrent(dictation, generation)) {
          _listenHealthy = true;
        }
      });
    }
    return true;
  }

  void _handleResult(
    _SpeechDictation dictation,
    String words, {
    required bool isFinal,
  }) {
    final String transcript = dictation.transcriptTransform(words);
    if (transcript.trim().isNotEmpty) {
      // Speech is getting through: earlier failures are no longer consecutive.
      _listenHealthy = true;
      _consecutiveFailures = 0;
    }
    final String committedBefore = _sessionCommitted;
    final String span = mergeSpeechSegments(
      committedBefore,
      transcript,
      separator: dictation.separator,
    );
    if (span == _sessionSpan && !isFinal) {
      // Recognizer repeated a partial it already delivered.
      return;
    }
    _cancelInFlightFormat();
    _deliverSpan(dictation, span: span, isFinal: isFinal);
    if (isFinal) {
      _sessionCommitted = span;
      unawaited(
        _formatFinalTranscript(
          dictation,
          transcript: transcript,
          committedBefore: committedBefore,
          unformattedSpan: span,
        ),
      );
    }
    notifyListeners();
  }

  /// The recognizer stopped listening on its own (end of phrase, silence, a
  /// soft error). Restart it while dictation is still on.
  void _handleListenEnded(_SpeechDictation dictation, int generation) {
    if (_restartTimer != null) {
      return;
    }
    if (_listenHealthy) {
      _consecutiveFailures = 0;
    } else if (!_registerFailure(dictation, generation)) {
      return;
    }
    _scheduleRestart(dictation);
  }

  void _handleListenError(
    _SpeechDictation dictation,
    int generation,
    String error,
  ) {
    switch (appSpeechErrorKind(error)) {
      case AppSpeechErrorKind.soft:
        _handleListenEnded(dictation, generation);
      case AppSpeechErrorKind.retryable:
        if (_registerFailure(dictation, generation)) {
          _scheduleRestart(dictation);
        }
      case AppSpeechErrorKind.permissionDenied:
        _initStatus = AppSpeechInitStatus.permissionDenied;
        _interrupt(dictation, AppSpeechToTextInterruption.permissionDenied);
      case AppSpeechErrorKind.unavailable:
        _interrupt(dictation, AppSpeechToTextInterruption.unavailable);
    }
  }

  /// Counts one failed recognizer session. Returns false when that was one
  /// failure too many and dictation ended.
  bool _registerFailure(_SpeechDictation dictation, int generation) {
    if (_failureCountedGeneration != generation) {
      _failureCountedGeneration = generation;
      _consecutiveFailures += 1;
    }
    if (_consecutiveFailures >= _maxConsecutiveFailures) {
      _interrupt(dictation, AppSpeechToTextInterruption.error);
      return false;
    }
    return true;
  }

  void _scheduleRestart(_SpeechDictation dictation) {
    _restartTimer?.cancel();
    final Duration delay = _consecutiveFailures == 0
        ? _restartDelay
        : _failureBackoff * (1 << (_consecutiveFailures - 1));
    _restartTimer = Timer(delay, () {
      _restartTimer = null;
      unawaited(_restart(dictation));
    });
  }

  Future<void> _restart(_SpeechDictation dictation) async {
    if (!identical(_dictation, dictation)) {
      return;
    }
    if (_recognizer.isListening) {
      // The platform kept listening after all; its own end restarts us.
      return;
    }
    _reanchorSpan(dictation);
    if (await _listen(dictation) || !identical(_dictation, dictation)) {
      return;
    }
    if (_registerFailure(dictation, _listenGeneration)) {
      _scheduleRestart(dictation);
    }
    notifyListeners();
  }

  /// Keeps what was dictated so far and anchors the next recognizer session
  /// at the caret, so it appends instead of rewriting earlier words.
  void _reanchorSpan(_SpeechDictation dictation) {
    _sessionCommitted = '';
    _sessionSpan = '';
    _spanEpoch += 1;
    if (dictation.onSpeechResult != null) {
      _pendingJoiner = '';
      return;
    }
    final ({String prefix, String suffix}) bounds = captureSpeechSessionBounds(
      dictation.controller,
    );
    _sessionPrefix = bounds.prefix;
    _sessionSuffix = bounds.suffix;
    _pendingJoiner = _joinerAfter(bounds.prefix, dictation.separator);
  }

  static String _joinerAfter(String prefix, String separator) {
    if (separator.isEmpty ||
        prefix.isEmpty ||
        RegExp(r'\s$').hasMatch(prefix)) {
      return '';
    }
    return separator;
  }

  /// Rewrites the dictation span with [span] (everything spoken this
  /// recognizer session).
  void _deliverSpan(
    _SpeechDictation dictation, {
    required String span,
    required bool isFinal,
  }) {
    _sessionSpan = span;
    final void Function(String transcript, {required bool isFinal})?
    onSpeechResult = dictation.onSpeechResult;
    if (onSpeechResult != null) {
      onSpeechResult(span, isFinal: isFinal);
      return;
    }
    if (span.isNotEmpty && _pendingJoiner.isNotEmpty) {
      _sessionPrefix = '$_sessionPrefix$_pendingJoiner';
      _pendingJoiner = '';
    }
    insertSpeechTranscript(
      dictation.controller,
      span,
      sessionPrefix: _sessionPrefix,
      sessionSuffix: _sessionSuffix,
    );
    dictation.onChanged?.call(dictation.controller.text);
  }

  Future<void> _formatFinalTranscript(
    _SpeechDictation dictation, {
    required String transcript,
    required String committedBefore,
    required String unformattedSpan,
  }) async {
    final AppSpeechAiFormatter? aiFormatter = dictation.aiFormatter;
    // A host may stop dictation while handling the result (a select field
    // that matched an option); formatting would then land after the stop.
    if (aiFormatter == null ||
        transcript.trim().isEmpty ||
        !identical(_dictation, dictation)) {
      return;
    }

    final int generation = _formatGeneration;
    final int epoch = _spanEpoch;
    final String prefix = _sessionPrefix;
    final String suffix = _sessionSuffix;
    final AppSpeechAiAbort abort = AppSpeechAiAbort();
    _activeFormatAbort = abort;
    _formattingOwner = dictation.owner;
    notifyListeners();

    final TextEditingController controller = dictation.controller;
    final String expected = '$prefix$unformattedSpan$suffix';
    String? formatted;
    try {
      formatted = await aiFormatter(
        transcript: transcript,
        mode: dictation.aiFormatMode,
        abort: abort,
        locale: dictation.locale,
        hint: dictation.aiFormatHint,
      );
    } on Object {
      formatted = null;
    }

    if (generation != _formatGeneration) {
      return;
    }
    _activeFormatAbort = null;
    _formattingOwner = null;

    final String? next = formatted?.trim();
    if (next == null || next.isEmpty || next == transcript) {
      notifyListeners();
      return;
    }
    if (dictation.onSpeechResult == null && controller.text != expected) {
      notifyListeners();
      return;
    }

    // Swap the raw phrase for the formatted one without disturbing phrases
    // that were already committed earlier in this session.
    final String span = mergeSpeechSegments(
      committedBefore,
      next,
      separator: dictation.separator,
    );
    if (epoch != _spanEpoch) {
      // The recognizer restarted while formatting and re-anchored right after
      // the raw phrase. Nothing was dictated since (any result cancels this
      // pass), so swap the phrase in place and re-anchor after it. Bail if the
      // anchor moved, rather than risk duplicating text.
      if (dictation.onSpeechResult != null ||
          _sessionPrefix != '$prefix$unformattedSpan' ||
          _sessionSuffix != suffix) {
        notifyListeners();
        return;
      }
      _sessionPrefix = '$prefix$span';
      _pendingJoiner = _joinerAfter(_sessionPrefix, dictation.separator);
      insertSpeechTranscript(
        controller,
        '',
        sessionPrefix: _sessionPrefix,
        sessionSuffix: suffix,
      );
      dictation.onChanged?.call(controller.text);
      notifyListeners();
      return;
    }
    _sessionCommitted = span;
    _deliverSpan(dictation, span: span, isFinal: true);
    notifyListeners();
  }

  /// Turns dictation off. With [owner], only if that field is dictating.
  Future<void> stop({Object? owner}) async {
    if (owner != null && _dictation != null && _dictation!.owner != owner) {
      return;
    }
    // End the intent first so a pending restart can never reopen the mic.
    _endDictation();
    _cancelInFlightFormat(notify: false);
    try {
      await _recognizer.stopListening();
    } on Object {
      // Best-effort stop on dispose/disable.
    }
    notifyListeners();
  }

  Future<void> cancel({Object? owner}) async {
    if (owner != null && _dictation != null && _dictation!.owner != owner) {
      return;
    }
    _endDictation();
    _cancelInFlightFormat(notify: false);
    try {
      await _recognizer.cancelListening();
    } on Object {
      // Best-effort cancel.
    }
    notifyListeners();
  }

  /// Ends dictation the user did not stop, and records why for the owner.
  void _interrupt(
    _SpeechDictation dictation,
    AppSpeechToTextInterruption reason,
  ) {
    if (!identical(_dictation, dictation)) {
      return;
    }
    _endDictation();
    _interruptionSerial += 1;
    _lastInterruption = (
      serial: _interruptionSerial,
      owner: dictation.owner,
      reason: reason,
    );
    unawaited(_releaseRecognizer());
  }

  Future<void> _releaseRecognizer() async {
    try {
      await _recognizer.cancelListening();
    } on Object {
      // The recognizer already failed; releasing it is best effort.
    }
  }

  /// Drops session state so the next [start] anchors on a fresh caret span,
  /// and callbacks from the old recognizer session are ignored.
  void _endDictation() {
    _dictation = null;
    _listenGeneration += 1;
    _restartTimer?.cancel();
    _restartTimer = null;
    _healthyTimer?.cancel();
    _healthyTimer = null;
    _sessionCommitted = '';
    _sessionSpan = '';
    _pendingJoiner = '';
    _consecutiveFailures = 0;
    _failureCountedGeneration = null;
    _detachLifecycle();
  }

  void _attachLifecycle() {
    if (_observingLifecycle) {
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _observingLifecycle = true;
  }

  void _detachLifecycle() {
    if (!_observingLifecycle) {
      return;
    }
    WidgetsBinding.instance.removeObserver(this);
    _observingLifecycle = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final Object? owner = _dictation?.owner;
    if (owner == null || state == AppLifecycleState.resumed) {
      return;
    }
    // Browsers report `inactive` on a mere window blur, such as the mic
    // permission prompt; hidden tabs still end dictation.
    if (kIsWeb && state == AppLifecycleState.inactive) {
      return;
    }
    // Never keep the microphone open once the app leaves the foreground.
    unawaited(stop(owner: owner));
  }

  @override
  void dispose() {
    _endDictation();
    _cancelInFlightFormat(notify: false);
    super.dispose();
  }
}

String appSpeechToTextBlockMessage(
  AppLocalizations l10n,
  AppSpeechToTextBlockReason reason,
) {
  return switch (reason) {
    AppSpeechToTextBlockReason.offline => l10n.speechToTextOfflineMessage,
    AppSpeechToTextBlockReason.unavailable =>
      l10n.speechToTextUnavailableMessage,
    AppSpeechToTextBlockReason.permissionDenied =>
      l10n.speechToTextPermissionDeniedMessage,
    AppSpeechToTextBlockReason.noMicrophone =>
      l10n.speechToTextNoMicrophoneMessage,
    AppSpeechToTextBlockReason.fieldDisabled =>
      l10n.speechToTextFieldDisabledMessage,
  };
}

/// Compact mic / stop control for shared text inputs.
class AppSpeechToTextButton extends ConsumerStatefulWidget {
  const AppSpeechToTextButton({
    required this.controller,
    this.enabled = true,
    this.onChanged,
    this.onSpeechResult,
    this.transcriptTransform,
    this.aiFormatter,
    this.aiFormatMode = 'text',
    this.aiFormatHint,
    this.coordinator,
    this.dense = false,
    super.key,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  /// When set, receives each transformed transcript instead of inserting into
  /// [controller]. Useful for multi-part fields such as dates.
  final void Function(String transcript, {required bool isFinal})?
      onSpeechResult;
  /// Optional sanitizer (e.g. [appSpeechDigitsOnlyTranscript] for phone/date).
  final String Function(String transcript)? transcriptTransform;
  /// Test override. Production reads [aiSpeechFormatterProvider].
  final AppSpeechAiFormatter? aiFormatter;
  /// Backend `speech_format` mode (`text`, `email`, `phone`, …).
  final String aiFormatMode;
  final String? aiFormatHint;
  final AppSpeechToTextCoordinator? coordinator;
  final bool dense;

  @override
  ConsumerState<AppSpeechToTextButton> createState() =>
      _AppSpeechToTextButtonState();
}

class _AppSpeechToTextButtonState extends ConsumerState<AppSpeechToTextButton> {
  late final AppSpeechToTextCoordinator _coordinator;
  AppSpeechInitStatus _initStatus = AppSpeechInitStatus.unavailable;
  bool _checking = false;
  int _seenInterruptionSerial = 0;

  @override
  void initState() {
    super.initState();
    _coordinator = widget.coordinator ?? AppSpeechToTextCoordinator.instance;
    _seenInterruptionSerial = _coordinator.lastInterruption?.serial ?? 0;
    _coordinator.addListener(_handleCoordinatorChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _warmUp();
    });
  }

  @override
  void didUpdateWidget(covariant AppSpeechToTextButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled &&
        _coordinator.isListeningFor(widget.controller)) {
      _coordinator.stop(owner: widget.controller);
    }
  }

  @override
  void dispose() {
    if (_coordinator.isListeningFor(widget.controller)) {
      _coordinator.stop(owner: widget.controller);
    }
    _coordinator.removeListener(_handleCoordinatorChanged);
    super.dispose();
  }

  void _handleCoordinatorChanged() {
    if (!mounted) {
      return;
    }
    _showInterruption();
    setState(() {});
  }

  /// Tells the user why dictation on this field ended without them stopping
  /// it. Raw plugin errors are never shown.
  void _showInterruption() {
    final ({int serial, Object owner, AppSpeechToTextInterruption reason})?
    interruption = _coordinator.lastInterruption;
    if (interruption == null ||
        interruption.serial == _seenInterruptionSerial) {
      return;
    }
    _seenInterruptionSerial = interruption.serial;
    if (interruption.owner != widget.controller) {
      return;
    }
    final AppLocalizations l10n = context.l10n;
    final String message = switch (interruption.reason) {
      AppSpeechToTextInterruption.permissionDenied =>
        l10n.speechToTextPermissionDeniedMessage,
      AppSpeechToTextInterruption.unavailable =>
        l10n.speechToTextUnavailableMessage,
      AppSpeechToTextInterruption.error => l10n.speechToTextErrorMessage,
    };
    if (interruption.reason == AppSpeechToTextInterruption.permissionDenied) {
      _initStatus = AppSpeechInitStatus.permissionDenied;
    }
    showAppSuccessSnackBar(context, message);
  }

  Future<void> _warmUp() async {
    if (!mounted || _checking) {
      return;
    }
    setState(() => _checking = true);
    final AppSpeechInitStatus status = await _coordinator.ensureReady();
    if (!mounted) {
      return;
    }
    setState(() {
      _initStatus = status;
      _checking = false;
    });
  }

  AppSpeechToTextBlockReason? _blockReason({required bool online}) {
    if (!widget.enabled) {
      return AppSpeechToTextBlockReason.fieldDisabled;
    }
    if (!online) {
      return AppSpeechToTextBlockReason.offline;
    }
    return switch (_initStatus) {
      AppSpeechInitStatus.ready => null,
      AppSpeechInitStatus.permissionDenied =>
        AppSpeechToTextBlockReason.permissionDenied,
      AppSpeechInitStatus.noMicrophone =>
        AppSpeechToTextBlockReason.noMicrophone,
      AppSpeechInitStatus.unavailable =>
        AppSpeechToTextBlockReason.unavailable,
    };
  }

  Future<void> _toggle() async {
    final AppLocalizations l10n = context.l10n;
    final bool listening = _coordinator.isListeningFor(widget.controller);
    if (listening) {
      await _coordinator.stop(owner: widget.controller);
      return;
    }

    final AsyncValue<AppConnectivityStatus> connectivity = ref.read(
      appConnectivityStatusProvider,
    );
    final bool online = connectivity.maybeWhen(
      data: (AppConnectivityStatus status) => status.isOnline,
      orElse: () => true,
    );
    if (!online) {
      showAppSuccessSnackBar(context, l10n.speechToTextOfflineMessage);
      return;
    }

    setState(() => _checking = true);
    final ({bool started, bool stoppedOther}) result = await _coordinator.start(
      owner: widget.controller,
      controller: widget.controller,
      onChanged: widget.onChanged,
      onSpeechResult: widget.onSpeechResult,
      transcriptTransform:
          widget.transcriptTransform ?? appSpeechTextTranscript,
      aiFormatter: widget.aiFormatter ?? ref.read(aiSpeechFormatterProvider),
      aiFormatMode: widget.aiFormatMode,
      aiFormatHint: widget.aiFormatHint,
      segmentSeparator: appSpeechSegmentSeparatorForFormatMode(
        widget.aiFormatMode,
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _initStatus = _coordinator.initStatus;
      _checking = false;
    });

    if (result.stoppedOther) {
      showAppSuccessSnackBar(context, l10n.speechToTextSwitchedFieldMessage);
    }
    if (!result.started) {
      final AppSpeechToTextBlockReason reason =
          _blockReason(online: true) ??
          AppSpeechToTextBlockReason.unavailable;
      showAppSuccessSnackBar(context, appSpeechToTextBlockMessage(l10n, reason));
      if (_coordinator.lastError != null &&
          reason == AppSpeechToTextBlockReason.unavailable) {
        showAppSuccessSnackBar(context, l10n.speechToTextErrorMessage);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<AppConnectivityStatus> connectivity = ref.watch(
      appConnectivityStatusProvider,
    );
    final bool online = connectivity.maybeWhen(
      data: (AppConnectivityStatus status) => status.isOnline,
      orElse: () => true,
    );
    final bool listening = _coordinator.isListeningFor(widget.controller);
    final bool formatting = _coordinator.isFormattingFor(widget.controller);
    final AppSpeechToTextBlockReason? blockReason = listening
        ? null
        : _blockReason(online: online);
    final bool canPress =
        widget.enabled && (listening || blockReason == null) && !_checking;
    final String tooltip = listening
        ? l10n.speechToTextListeningTooltip
        : (blockReason == null
              ? l10n.speechToTextStartTooltip
              : appSpeechToTextBlockMessage(l10n, blockReason));

    return AppActionLabelScope(
      showLabels: false,
      forceIconOnly: true,
      plainChrome: true,
      child: AppButton(
        iconOnly: true,
        dense: widget.dense,
        variant: AppButtonVariant.tertiary,
        leadingIcon: listening
            ? Icons.stop
            : (formatting ? Icons.hourglass_empty : Icons.mic_none_outlined),
        label: listening
            ? l10n.speechToTextStopTooltip
            : l10n.speechToTextStartTooltip,
        semanticLabel: tooltip,
        tooltip: tooltip,
        enabled: canPress || listening,
        onPressed: (canPress || listening) ? _toggle : null,
      ),
    );
  }
}
