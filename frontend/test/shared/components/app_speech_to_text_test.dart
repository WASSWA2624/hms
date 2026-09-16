import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hosspi_hms/core/ai/ai_clinical_note_formatter.dart';
import 'package:hosspi_hms/core/ai/ai_speech_formatter.dart';
import 'package:hosspi_hms/core/network/app_connectivity_status.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/shared/components/app_rich_text_editor.dart';
import 'package:hosspi_hms/shared/components/app_select_field.dart';
import 'package:hosspi_hms/shared/components/app_speech_ai.dart';
import 'package:hosspi_hms/shared/components/app_speech_to_text.dart';
import 'package:hosspi_hms/shared/components/app_text_field.dart';

import 'component_test_app.dart';

final class _FakeSpeechRecognizer implements AppSpeechRecognizer {
  AppSpeechInitStatus initStatus = AppSpeechInitStatus.ready;
  bool _listening = false;

  /// Android-like by default: each result carries only the running phrase.
  @override
  bool resendsSessionTranscript = false;
  int startCount = 0;
  int stopCount = 0;
  void Function(String words, {required bool isFinal})? onResult;
  void Function(String status)? onStatus;
  void Function(String error)? onError;

  @override
  bool get isListening => _listening;

  @override
  Future<AppSpeechInitStatus> ensureReady({
    void Function(String status)? onStatus,
    void Function(String error)? onError,
  }) async {
    return initStatus;
  }

  @override
  Future<void> startListening({
    required void Function(String words, {required bool isFinal}) onResult,
    void Function(String status)? onStatus,
    void Function(String error)? onError,
  }) async {
    startCount += 1;
    this.onResult = onResult;
    this.onStatus = onStatus;
    this.onError = onError;
    _listening = true;
  }

  @override
  Future<void> stopListening() async {
    stopCount += 1;
    _listening = false;
  }

  @override
  Future<void> cancelListening() async {
    _listening = false;
  }

  void emit(String words, {bool isFinal = false}) {
    onResult?.call(words, isFinal: isFinal);
  }

  /// The platform ends the recognizer session on its own (end of phrase or
  /// silence), as Android does.
  void finish({String status = 'done'}) {
    _listening = false;
    onStatus?.call(status);
  }

  /// The platform reports [error], then stops listening.
  void fail(String error) {
    onError?.call(error);
    finish(status: 'notListening');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSpeechRecognizer recognizer;
  late AppSpeechToTextCoordinator coordinator;
  // Recognizer callbacks are timed with this clock, so a test can pause.
  late DateTime now;

  setUp(() {
    now = DateTime(2026, 9, 16, 9);
    recognizer = _FakeSpeechRecognizer();
    coordinator = AppSpeechToTextCoordinator(
      recognizer: recognizer,
      now: () => now,
    );
    AppSpeechToTextCoordinator.debugInstance = coordinator;
  });

  tearDown(() {
    AppSpeechToTextCoordinator.debugInstance = null;
    coordinator.dispose();
  });

  Future<void> pumpSpeechApp(
    WidgetTester tester,
    Widget child, {
    AppConnectivityStatus connectivity = AppConnectivityStatus.online,
    AppClinicalNoteAiFormatter? clinicalNoteFormatter,
  }) async {
    await pumpComponent(
      tester,
      ProviderScope(
        overrides: [
          appConnectivityStatusProvider.overrideWith(
            (Ref ref) => Stream<AppConnectivityStatus>.value(connectivity),
          ),
          aiSpeechFormatterProvider.overrideWithValue(null),
          aiClinicalNoteFormatterProvider.overrideWithValue(
            clinicalNoteFormatter,
          ),
        ],
        child: child,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  test('appSpeechJoinDictation preserves surrounding markup markers', () {
    final TextEditingController controller = TextEditingController(
      text: '**bold** middle __under__',
    );
    controller.selection = const TextSelection(baseOffset: 9, extentOffset: 15);

    final ({String prefix, String suffix}) bounds =
        captureSpeechSessionBounds(controller);
    final ({String text, int caret}) joined = appSpeechJoinDictation(
      prefix: bounds.prefix,
      dictated: 'spoken',
      suffix: bounds.suffix,
    );

    expect(joined.text, '**bold** spoken __under__');
    expect(joined.caret, '**bold** spoken'.length);
  });

  test('appSpeechJoinDictation spaces prose against words only', () {
    expect(
      appSpeechJoinDictation(prefix: 'Hello', dictated: 'world', suffix: 'Z'),
      (text: 'Hello world Z', caret: 'Hello world'.length),
    );
    expect(
      appSpeechJoinDictation(prefix: '**', dictated: 'bold', suffix: '**'),
      (text: '**bold**', caret: 6),
    );
    expect(
      appSpeechJoinDictation(
        prefix: '070',
        dictated: '1234',
        suffix: '',
        separator: '',
      ),
      (text: '0701234', caret: 7),
    );
  });

  test('appSpeechSegmentSeparatorForFormatMode spaces prose only', () {
    expect(appSpeechSegmentSeparatorForFormatMode('text'), ' ');
    expect(appSpeechSegmentSeparatorForFormatMode('phone'), '');
    expect(appSpeechSegmentSeparatorForFormatMode('email'), '');
    expect(appSpeechSegmentSeparatorForFormatMode('digits'), '');
  });

  testWidgets('a repeated final result does not duplicate the dictated text', (
    WidgetTester tester,
  ) async {
    final TextEditingController controller = TextEditingController();

    await pumpSpeechApp(
      tester,
      AppTextField(
        controller: controller,
        labelText: 'Note',
        enableSpeechToText: true,
      ),
    );

    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(AppTextField)),
    );
    await tester.tap(find.byTooltip(l10n.speechToTextStartTooltip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    recognizer.emit('hello');
    await tester.pump();
    recognizer.emit('hello world');
    await tester.pump();
    recognizer.emit('hello world', isFinal: true);
    await tester.pump();
    // Some engines flush the same final a second time when the session ends.
    recognizer.emit('hello world', isFinal: true);
    await tester.pump();

    expect(controller.text, 'hello world');
  });

  testWidgets('consecutive phrases in one session append once each', (
    WidgetTester tester,
  ) async {
    final TextEditingController controller = TextEditingController();

    await pumpSpeechApp(
      tester,
      AppTextField(
        controller: controller,
        labelText: 'Note',
        enableSpeechToText: true,
      ),
    );

    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(AppTextField)),
    );
    await tester.tap(find.byTooltip(l10n.speechToTextStartTooltip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    recognizer.emit('patient is', isFinal: true);
    await tester.pump();
    recognizer.emit('stable');
    await tester.pump();
    recognizer.emit('stable today', isFinal: true);
    await tester.pump();

    expect(controller.text, 'patient is stable today');
  });

  test('appSpeechToTextEnabledForField hides passwords only by default', () {
    expect(
      appSpeechToTextEnabledForField(
        enableSpeechToText: null,
        obscureText: true,
        keyboardType: TextInputType.text,
      ),
      isFalse,
    );
    expect(
      appSpeechToTextEnabledForField(
        enableSpeechToText: false,
        obscureText: false,
        keyboardType: TextInputType.multiline,
      ),
      isFalse,
    );
    expect(
      appSpeechToTextEnabledForField(
        enableSpeechToText: null,
        obscureText: false,
        keyboardType: TextInputType.number,
      ),
      isTrue,
    );
    expect(
      appSpeechToTextEnabledForField(
        enableSpeechToText: null,
        obscureText: false,
        keyboardType: TextInputType.phone,
      ),
      isTrue,
    );
    expect(
      appSpeechToTextEnabledForField(
        enableSpeechToText: null,
        obscureText: false,
        keyboardType: TextInputType.multiline,
      ),
      isTrue,
    );
  });

  test('appSpeechDigitsOnlyTranscript extracts spoken digits', () {
    expect(appSpeechDigitsOnlyTranscript('seven eight three'), '783');
    expect(
      appSpeechDigitsOnlyTranscript('one two point five', allowDecimal: true),
      '12.5',
    );
    expect(
      appSpeechDigitsOnlyTranscript('1,250.50', allowDecimal: true),
      '1250.50',
    );
  });

  test('parseSpokenEnglishNumber understands cardinal phrases', () {
    expect(
      parseSpokenEnglishNumber('one thousand two hundred twenty-five'),
      '1225',
    );
    expect(parseSpokenEnglishNumber('one thousand two hundred twenty five'), '1225');
    expect(parseSpokenEnglishNumber('fifteen'), '15');
    expect(parseSpokenEnglishNumber('twelve point five'), '12.5');
    expect(parseSpokenEnglishNumber('two million'), '2000000');
  });

  test('parseSpokenDateParts understands full spoken and numeric dates', () {
    expect(
      parseSpokenDateParts('March 15 2024'),
      isA<AppSpokenDateParts>()
          .having((AppSpokenDateParts p) => p.day, 'day', 15)
          .having((AppSpokenDateParts p) => p.month, 'month', 3)
          .having((AppSpokenDateParts p) => p.year, 'year', 2024),
    );
    expect(
      parseSpokenDateParts('15 March 2024'),
      isA<AppSpokenDateParts>()
          .having((AppSpokenDateParts p) => p.day, 'day', 15)
          .having((AppSpokenDateParts p) => p.month, 'month', 3)
          .having((AppSpokenDateParts p) => p.year, 'year', 2024),
    );
    expect(
      parseSpokenDateParts('march fifteenth twenty twenty four'),
      isA<AppSpokenDateParts>()
          .having((AppSpokenDateParts p) => p.day, 'day', 15)
          .having((AppSpokenDateParts p) => p.month, 'month', 3)
          .having((AppSpokenDateParts p) => p.year, 'year', 2024),
    );
    expect(
      parseSpokenDateParts('15/03/2024'),
      isA<AppSpokenDateParts>()
          .having((AppSpokenDateParts p) => p.day, 'day', 15)
          .having((AppSpokenDateParts p) => p.month, 'month', 3)
          .having((AppSpokenDateParts p) => p.year, 'year', 2024),
    );
    expect(
      parseSpokenDateParts('2024-03-15'),
      isA<AppSpokenDateParts>()
          .having((AppSpokenDateParts p) => p.day, 'day', 15)
          .having((AppSpokenDateParts p) => p.month, 'month', 3)
          .having((AppSpokenDateParts p) => p.year, 'year', 2024),
    );
    expect(
      parseSpokenDateParts('twenty first of december two thousand twenty five'),
      isA<AppSpokenDateParts>()
          .having((AppSpokenDateParts p) => p.day, 'day', 21)
          .having((AppSpokenDateParts p) => p.month, 'month', 12)
          .having((AppSpokenDateParts p) => p.year, 'year', 2025),
    );
  });

  test('parseSpokenDateParts understands partial day month and year speech', () {
    expect(
      parseSpokenDateParts('March'),
      isA<AppSpokenDateParts>()
          .having((AppSpokenDateParts p) => p.month, 'month', 3)
          .having((AppSpokenDateParts p) => p.day, 'day', isNull)
          .having((AppSpokenDateParts p) => p.year, 'year', isNull),
    );
    expect(
      parseSpokenDateParts('fifteenth'),
      isA<AppSpokenDateParts>()
          .having((AppSpokenDateParts p) => p.day, 'day', 15)
          .having((AppSpokenDateParts p) => p.month, 'month', isNull)
          .having((AppSpokenDateParts p) => p.year, 'year', isNull),
    );
    expect(
      parseSpokenDateParts('two thousand twenty four'),
      isA<AppSpokenDateParts>()
          .having((AppSpokenDateParts p) => p.year, 'year', 2024)
          .having((AppSpokenDateParts p) => p.day, 'day', isNull)
          .having((AppSpokenDateParts p) => p.month, 'month', isNull),
    );
    expect(
      parseSpokenDateParts('twenty twenty four'),
      isA<AppSpokenDateParts>()
          .having((AppSpokenDateParts p) => p.year, 'year', 2024),
    );
  });

  test('number fields use cardinal phrases and digit sequences', () {
    expect(
      appSpeechNormalizeTranscript(
        'one thousand two hundred twenty-five',
        mode: AppSpeechTranscriptMode.digits,
      ),
      '1225',
    );
    expect(
      appSpeechNormalizeTranscript(
        'one two two five',
        mode: AppSpeechTranscriptMode.digits,
      ),
      '1225',
    );
    expect(
      appSpeechNormalizeTranscript(
        'one thousand point five',
        mode: AppSpeechTranscriptMode.decimal,
      ),
      '1000.5',
    );
  });

  test('email and text modes apply spoken punctuation', () {
    expect(
      appSpeechEmailTranscript('jane underscore doe at example dot com'),
      'jane_doe@example.com',
    );
    expect(
      appSpeechTextTranscript(
        'hello period buy one thousand units question mark',
      ),
      'hello. buy 1000 units?',
    );
  });

  test('appSpeechAiFormatModeForKeyboard maps field types', () {
    expect(
      appSpeechAiFormatModeForKeyboard(TextInputType.emailAddress),
      'email',
    );
    expect(appSpeechAiFormatModeForKeyboard(TextInputType.phone), 'phone');
    expect(appSpeechAiFormatModeForKeyboard(TextInputType.datetime), 'date');
    expect(appSpeechAiFormatModeForKeyboard(TextInputType.number), 'digits');
    expect(
      appSpeechAiFormatModeForKeyboard(
        const TextInputType.numberWithOptions(decimal: true),
      ),
      'decimal',
    );
    expect(appSpeechAiFormatModeForKeyboard(TextInputType.text), 'text');
  });

  test('final STT inserts before AI format and skips AI on partials', () async {
    final TextEditingController controller = TextEditingController();
    final List<String> formatCalls = <String>[];

    await coordinator.start(
      owner: controller,
      controller: controller,
      onChanged: null,
      transcriptTransform: (String value) => value,
      aiFormatMode: 'email',
      aiFormatter:
          ({
            required String transcript,
            required String mode,
            required AppSpeechAiAbort abort,
            String? locale,
            String? hint,
            String? context,
          }) async {
            formatCalls.add('$mode:$transcript');
            return 'name@hospital.com';
          },
    );

    recognizer.emit('name at', isFinal: false);
    expect(controller.text, 'name at');
    expect(formatCalls, isEmpty);

    recognizer.emit('name at hospital dot com', isFinal: true);
    expect(controller.text, 'name at hospital dot com');
    await Future<void>.delayed(Duration.zero);
    expect(formatCalls, <String>['email:name at hospital dot com']);
    expect(controller.text, 'name@hospital.com');
  });

  test('keeps STT text when AI is unavailable', () async {
    final TextEditingController controller = TextEditingController();
    await coordinator.start(
      owner: controller,
      controller: controller,
      onChanged: null,
      transcriptTransform: (String value) => value,
      aiFormatter: null,
    );

    recognizer.emit('hello comma world', isFinal: true);
    await Future<void>.delayed(Duration.zero);
    expect(controller.text, 'hello comma world');
  });

  test('does not overwrite a user edit during in-flight format', () async {
    final TextEditingController controller = TextEditingController();
    final Completer<String?> completer = Completer<String?>();

    await coordinator.start(
      owner: controller,
      controller: controller,
      onChanged: null,
      transcriptTransform: (String value) => value,
      aiFormatter:
          ({
            required String transcript,
            required String mode,
            required AppSpeechAiAbort abort,
            String? locale,
            String? hint,
            String? context,
          }) {
            return completer.future;
          },
    );

    recognizer.emit('draft', isFinal: true);
    expect(controller.text, 'draft');
    controller.text = 'user typed';
    completer.complete('formatted');
    await Future<void>.delayed(Duration.zero);
    expect(controller.text, 'user typed');
  });

  testWidgets('mic toggles to stop while listening and inserts text', (
    WidgetTester tester,
  ) async {
    final TextEditingController controller = TextEditingController(text: 'Hello ');
    controller.selection = const TextSelection.collapsed(offset: 6);

    await pumpSpeechApp(
      tester,
      AppTextField(
        controller: controller,
        labelText: 'Note',
        enableSpeechToText: true,
      ),
    );

    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(AppTextField)),
    );
    expect(find.byTooltip(l10n.speechToTextStartTooltip), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.speechToTextStartTooltip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byTooltip(l10n.speechToTextListeningTooltip), findsOneWidget);
    expect(find.byIcon(Icons.stop), findsOneWidget);

    recognizer.emit('world', isFinal: true);
    await tester.pump();

    expect(controller.text, 'Hello world');

    await tester.tap(find.byTooltip(l10n.speechToTextListeningTooltip));
    await tester.pump();
    expect(find.byIcon(Icons.mic_none_outlined), findsOneWidget);
  });

  testWidgets('offline disables speech control with localized reason', (
    WidgetTester tester,
  ) async {
    final TextEditingController controller = TextEditingController();

    await pumpSpeechApp(
      tester,
      AppTextField(
        controller: controller,
        labelText: 'Note',
        enableSpeechToText: true,
      ),
      connectivity: AppConnectivityStatus.offline,
    );

    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(AppTextField)),
    );
    expect(find.byTooltip(l10n.speechToTextOfflineMessage), findsOneWidget);
  });

  testWidgets('searchable select and number fields expose speech controls', (
    WidgetTester tester,
  ) async {
    await pumpSpeechApp(
      tester,
      Column(
        children: <Widget>[
          AppSelectField<String>.searchable(
            labelText: 'Facility',
            options: const <AppSelectOption<String>>[
              AppSelectOption<String>(value: 'a', label: 'Alpha'),
              AppSelectOption<String>(value: 'b', label: 'Beta'),
            ],
            onChanged: (_) {},
          ),
          AppTextField(
            controller: TextEditingController(),
            labelText: 'Quantity',
            keyboardType: TextInputType.number,
          ),
        ],
      ),
    );

    expect(find.byIcon(Icons.mic_none_outlined), findsNWidgets(2));
  });

  testWidgets('speech match selects the matching select option', (
    WidgetTester tester,
  ) async {
    String? selected;

    await pumpSpeechApp(
      tester,
      AppSelectField<String>.searchable(
        labelText: 'Status',
        options: const <AppSelectOption<String>>[
          AppSelectOption<String>(value: 'draft', label: 'Draft'),
          AppSelectOption<String>(value: 'live', label: 'Live'),
          AppSelectOption<String>(
            value: 'archived',
            label: 'Archived',
            searchText: 'retired closed',
          ),
        ],
        onChanged: (String? value) => selected = value,
      ),
    );

    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(AppSelectField<String>)),
    );
    await tester.tap(find.byTooltip(l10n.speechToTextStartTooltip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    recognizer.emit('Live', isFinal: true);
    await tester.pump();
    await tester.pump();

    expect(selected, 'live');
    expect(find.byIcon(Icons.mic_none_outlined), findsOneWidget);
  });

  testWidgets('final speech unique search-text match selects the option', (
    WidgetTester tester,
  ) async {
    String? selected;

    await pumpSpeechApp(
      tester,
      AppSelectField<String>(
        labelText: 'Country',
        options: const <AppSelectOption<String>>[
          AppSelectOption<String>(
            value: 'ug',
            label: 'Uganda',
            searchText: 'UG Uganda East Africa',
          ),
          AppSelectOption<String>(
            value: 'ke',
            label: 'Kenya',
            searchText: 'KE Kenya East Africa',
          ),
        ],
        onChanged: (String? value) => selected = value,
      ),
    );

    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(AppSelectField<String>)),
    );
    await tester.tap(find.byTooltip(l10n.speechToTextStartTooltip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    recognizer.emit('Uganda', isFinal: true);
    await tester.pump();
    await tester.pump();

    expect(selected, 'ug');
  });

  testWidgets('ambiguous speech does not select a select option', (
    WidgetTester tester,
  ) async {
    String? selected = 'seed';

    await pumpSpeechApp(
      tester,
      AppSelectField<String>.searchable(
        labelText: 'Region',
        options: const <AppSelectOption<String>>[
          AppSelectOption<String>(value: 'east-a', label: 'East A'),
          AppSelectOption<String>(value: 'east-b', label: 'East B'),
        ],
        onChanged: (String? value) => selected = value,
      ),
    );

    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(AppSelectField<String>)),
    );
    await tester.tap(find.byTooltip(l10n.speechToTextStartTooltip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    recognizer.emit('East', isFinal: true);
    await tester.pump();
    await tester.pump();

    expect(selected, 'seed');
  });

  testWidgets('opt-out and password fields hide speech controls', (
    WidgetTester tester,
  ) async {
    await pumpSpeechApp(
      tester,
      Column(
        children: <Widget>[
          AppTextField(
            controller: TextEditingController(),
            labelText: 'Secret',
            obscureText: true,
            enableObscureTextToggle: true,
            showObscuredTextLabel: 'Show',
            hideObscuredTextLabel: 'Hide',
          ),
          AppTextField(
            controller: TextEditingController(),
            labelText: 'Code',
            enableSpeechToText: false,
          ),
        ],
      ),
    );

    expect(find.byIcon(Icons.mic_none_outlined), findsNothing);
    expect(find.byIcon(Icons.stop), findsNothing);
  });

  testWidgets('rich text caret insert preserves surrounding markup', (
    WidgetTester tester,
  ) async {
    final TextEditingController controller = TextEditingController(
      text: '**keep** | tail',
    );
    controller.selection = const TextSelection.collapsed(offset: 9);

    await pumpSpeechApp(
      tester,
      AppRichTextEditor(
        controller: controller,
        labelText: 'Clinical note',
      ),
    );

    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(AppRichTextEditor)),
    );
    await tester.tap(find.byTooltip(l10n.speechToTextStartTooltip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    recognizer.emit('spoken', isFinal: true);
    await tester.pump();

    expect(controller.text, '**keep** spoken| tail');
  });

  testWidgets('rich text AI format rewrites the note', (
    WidgetTester tester,
  ) async {
    final TextEditingController controller = TextEditingController(
      text: 'pt c/o fever since yesterday',
    );
    var formatCalls = 0;

    await pumpSpeechApp(
      tester,
      AppRichTextEditor(
        controller: controller,
        labelText: 'Clinical note',
      ),
      clinicalNoteFormatter:
          ({
            required String text,
            required AppSpeechAiAbort abort,
            String? locale,
            String? hint,
          }) async {
            formatCalls += 1;
            expect(text, 'pt c/o fever since yesterday');
            return const AppClinicalNoteAiFormatResult(
              text: 'The patient reports fever since yesterday.',
            );
          },
    );

    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(AppRichTextEditor)),
    );
    expect(find.byTooltip(l10n.commonAiFormatTooltip), findsOneWidget);
    await tester.tap(find.byTooltip(l10n.commonAiFormatTooltip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(formatCalls, 1);
    expect(controller.text, 'The patient reports fever since yesterday.');
    expect(find.text(l10n.commonAiFormatSuccessTitle), findsOneWidget);
    expect(find.text(l10n.commonAiFormatSuccessMessage), findsOneWidget);
  });

  testWidgets('rich text AI format shows a color-coded warning banner', (
    WidgetTester tester,
  ) async {
    final TextEditingController controller = TextEditingController(
      text: 'pt c/o fever',
    );

    await pumpSpeechApp(
      tester,
      AppRichTextEditor(
        controller: controller,
        labelText: 'Clinical note',
      ),
      clinicalNoteFormatter:
          ({
            required String text,
            required AppSpeechAiAbort abort,
            String? locale,
            String? hint,
          }) async {
            return const AppClinicalNoteAiFormatResult();
          },
    );

    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(AppRichTextEditor)),
    );
    await tester.tap(find.byTooltip(l10n.commonAiFormatTooltip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text(l10n.commonAiFormatUnavailableTitle), findsOneWidget);
    expect(find.text(l10n.commonAiFormatUnavailableMessage), findsOneWidget);
    expect(controller.text, 'pt c/o fever');
  });

  testWidgets('starting speech on a second field stops the first', (
    WidgetTester tester,
  ) async {
    final TextEditingController first = TextEditingController(text: 'A');
    final TextEditingController second = TextEditingController(text: 'B');
    first.selection = const TextSelection.collapsed(offset: 1);
    second.selection = const TextSelection.collapsed(offset: 1);

    await pumpSpeechApp(
      tester,
      Column(
        children: <Widget>[
          AppTextField(
            controller: first,
            labelText: 'First',
            enableSpeechToText: true,
          ),
          AppTextField(
            controller: second,
            labelText: 'Second',
            enableSpeechToText: true,
          ),
        ],
      ),
    );

    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.text('First')),
    );

    await tester.tap(find.byTooltip(l10n.speechToTextStartTooltip).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(coordinator.isListeningFor(first), isTrue);

    await tester.tap(find.byTooltip(l10n.speechToTextStartTooltip).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(coordinator.isListeningFor(first), isFalse);
    expect(coordinator.isListeningFor(second), isTrue);
    expect(find.text(l10n.speechToTextSwitchedFieldMessage), findsOneWidget);
  });

  group('continuous dictation', () {
    Future<AppLocalizations> startDictation(
      WidgetTester tester,
      TextEditingController controller,
    ) async {
      await pumpSpeechApp(
        tester,
        AppTextField(
          controller: controller,
          labelText: 'Note',
          enableSpeechToText: true,
        ),
      );
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(AppTextField)),
      );
      await tester.tap(find.byTooltip(l10n.speechToTextStartTooltip));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      return l10n;
    }

    testWidgets('restarts after the recognizer ends and stays listening', (
      WidgetTester tester,
    ) async {
      final TextEditingController controller = TextEditingController();
      final AppLocalizations l10n = await startDictation(tester, controller);

      recognizer.emit('hello', isFinal: true);
      recognizer.finish();
      await tester.pump();

      // No flicker back to idle while the recognizer restarts.
      expect(coordinator.isListeningFor(controller), isTrue);
      expect(find.byTooltip(l10n.speechToTextListeningTooltip), findsOneWidget);
      expect(find.byIcon(Icons.stop), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 200));
      expect(recognizer.startCount, 2);

      // After a while of silence the timeout is soft: restart again quietly.
      await tester.pump(const Duration(seconds: 5));
      recognizer.fail('error_speech_timeout');
      await tester.pump(const Duration(milliseconds: 200));
      expect(recognizer.startCount, 3);
      expect(find.byTooltip(l10n.speechToTextListeningTooltip), findsOneWidget);
      expect(find.text(l10n.speechToTextErrorMessage), findsNothing);
    });

    testWidgets('appends each recognizer session at the caret', (
      WidgetTester tester,
    ) async {
      final TextEditingController controller = TextEditingController(
        text: 'A  Z',
      );
      controller.selection = const TextSelection.collapsed(offset: 2);
      await startDictation(tester, controller);

      recognizer.emit('alpha');
      await tester.pump();
      recognizer.emit('alpha beta', isFinal: true);
      recognizer.finish();
      await tester.pump(const Duration(milliseconds: 200));
      expect(recognizer.startCount, 2);

      // A fresh recognizer session starts its transcript from scratch.
      recognizer.emit('gamma');
      await tester.pump();
      recognizer.emit('gamma delta', isFinal: true);
      await tester.pump();

      expect(controller.text, 'A alpha beta gamma delta Z');
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 'A alpha beta gamma delta'.length),
      );
    });

    testWidgets('an explicit stop cancels a pending restart', (
      WidgetTester tester,
    ) async {
      final TextEditingController controller = TextEditingController();
      final AppLocalizations l10n = await startDictation(tester, controller);

      recognizer.finish();
      await tester.tap(find.byTooltip(l10n.speechToTextListeningTooltip));
      await tester.pump(const Duration(seconds: 2));

      expect(recognizer.startCount, 1);
      expect(coordinator.isListening, isFalse);
      expect(find.byIcon(Icons.mic_none_outlined), findsOneWidget);
    });

    testWidgets('another field starting takes over without restarting the first', (
      WidgetTester tester,
    ) async {
      final TextEditingController first = TextEditingController();
      final TextEditingController second = TextEditingController();

      await coordinator.start(owner: first, controller: first, onChanged: null);
      recognizer.finish();
      await coordinator.start(
        owner: second,
        controller: second,
        onChanged: null,
      );
      await tester.pump(const Duration(seconds: 2));

      expect(recognizer.startCount, 2);
      expect(coordinator.isListeningFor(first), isFalse);
      expect(coordinator.isListeningFor(second), isTrue);
      await coordinator.stop();
    });

    testWidgets('disposing the owner field ends dictation', (
      WidgetTester tester,
    ) async {
      final TextEditingController controller = TextEditingController();
      final ValueNotifier<bool> showField = ValueNotifier<bool>(true);
      addTearDown(showField.dispose);

      await pumpSpeechApp(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: showField,
          builder: (BuildContext context, bool visible, _) => visible
              ? AppTextField(
                  controller: controller,
                  labelText: 'Note',
                  enableSpeechToText: true,
                )
              : const SizedBox.shrink(),
        ),
      );
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(AppTextField)),
      );
      await tester.tap(find.byTooltip(l10n.speechToTextStartTooltip));
      await tester.pump(const Duration(milliseconds: 50));
      recognizer.finish();

      showField.value = false;
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(coordinator.isListening, isFalse);
      expect(recognizer.startCount, 1);
      expect(recognizer.stopCount, greaterThanOrEqualTo(1));
    });

    testWidgets('the app leaving the foreground releases the microphone', (
      WidgetTester tester,
    ) async {
      final TextEditingController controller = TextEditingController();
      await startDictation(tester, controller);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump(const Duration(seconds: 2));

      expect(coordinator.isListening, isFalse);
      expect(recognizer.stopCount, 1);
      expect(recognizer.startCount, 1);
    });

    testWidgets('repeated hard errors end dictation with a localized error', (
      WidgetTester tester,
    ) async {
      final TextEditingController controller = TextEditingController();
      final AppLocalizations l10n = await startDictation(tester, controller);

      recognizer.fail('error_network');
      await tester.pump(const Duration(milliseconds: 400));
      // Backoff: no retry yet.
      expect(recognizer.startCount, 1);
      await tester.pump(const Duration(milliseconds: 200));
      expect(recognizer.startCount, 2);

      recognizer.fail('error_network');
      await tester.pump(const Duration(milliseconds: 1100));
      expect(recognizer.startCount, 3);
      expect(find.byTooltip(l10n.speechToTextListeningTooltip), findsOneWidget);

      recognizer.fail('error_network');
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));

      expect(recognizer.startCount, 3);
      expect(coordinator.isListening, isFalse);
      expect(find.byIcon(Icons.mic_none_outlined), findsOneWidget);
      expect(find.text(l10n.speechToTextErrorMessage), findsOneWidget);
      expect(find.textContaining('error_network'), findsNothing);
    });

    testWidgets('revoked permission stops at once with a localized message', (
      WidgetTester tester,
    ) async {
      final TextEditingController controller = TextEditingController();
      final AppLocalizations l10n = await startDictation(tester, controller);

      recognizer.fail('error_permission');
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(recognizer.startCount, 1);
      expect(coordinator.isListening, isFalse);
      expect(
        find.text(l10n.speechToTextPermissionDeniedMessage),
        findsOneWidget,
      );
    });

    test('AI formatting that finishes after a restart does not duplicate', () async {
      final _FakeSpeechRecognizer localRecognizer = _FakeSpeechRecognizer();
      final AppSpeechToTextCoordinator local = AppSpeechToTextCoordinator(
        recognizer: localRecognizer,
        restartDelay: Duration.zero,
      );
      addTearDown(local.dispose);
      final TextEditingController controller = TextEditingController();
      final Completer<String?> firstFormat = Completer<String?>();
      var formatCalls = 0;

      await local.start(
        owner: controller,
        controller: controller,
        onChanged: null,
        transcriptTransform: (String value) => value,
        aiFormatter:
            ({
              required String transcript,
              required String mode,
              required AppSpeechAiAbort abort,
              String? locale,
              String? hint,
              String? context,
            }) {
              formatCalls += 1;
              return formatCalls == 1
                  ? firstFormat.future
                  : Future<String?>.value();
            },
      );

      localRecognizer.emit('patient stable', isFinal: true);
      localRecognizer.finish();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(localRecognizer.startCount, 2);

      firstFormat.complete('Patient is stable.');
      await Future<void>.delayed(Duration.zero);
      expect(controller.text, 'Patient is stable.');

      localRecognizer.emit('next', isFinal: true);
      await Future<void>.delayed(Duration.zero);
      expect(controller.text, 'Patient is stable. next');
      await local.stop();
    });

    test('classifies recognizer errors', () {
      expect(appSpeechErrorKind('error_no_match'), AppSpeechErrorKind.soft);
      expect(appSpeechErrorKind('no-speech'), AppSpeechErrorKind.soft);
      expect(
        appSpeechErrorKind('error_permission'),
        AppSpeechErrorKind.permissionDenied,
      );
      expect(
        appSpeechErrorKind('not-allowed'),
        AppSpeechErrorKind.permissionDenied,
      );
      expect(
        appSpeechErrorKind('error_language_unavailable'),
        AppSpeechErrorKind.unavailable,
      );
      expect(appSpeechErrorKind('error_network'), AppSpeechErrorKind.retryable);
      expect(
        appSpeechErrorKind('error_unknown (42)'),
        AppSpeechErrorKind.retryable,
      );
    });
  });

  group('dictated text across pauses', () {
    String same(String raw) => raw;

    test('keeps each phrase when the recognizer starts the next from empty', () {
      final AppDictationTranscript transcript = AppDictationTranscript(
        transform: same,
      );

      transcript.add('the patient', isFinal: false);
      // Android closes the phrase (final or `intermediate`).
      transcript.add('the patient has a fever', isFinal: true);
      transcript.add('since', isFinal: false);
      expect(transcript.render(), 'the patient has a fever since');

      transcript.add('since yesterday', isFinal: true);
      // Engines sometimes flush the same final again.
      transcript.add('since yesterday', isFinal: true);
      expect(transcript.render(), 'the patient has a fever since yesterday');
    });

    test('keeps the phrase when the engine restarts it after a pause', () {
      DateTime clock = DateTime(2026, 9, 16);
      final AppDictationTranscript transcript = AppDictationTranscript(
        transform: same,
        now: () => clock,
      );

      transcript.add('the patient has a fever', isFinal: false);
      clock = clock.add(const Duration(seconds: 2));
      // No final: the engine silently restarted the running phrase.
      transcript.add('since', isFinal: false);
      clock = clock.add(const Duration(milliseconds: 200));
      transcript.add('since yesterday', isFinal: false);

      expect(transcript.render(), 'the patient has a fever since yesterday');
    });

    test('a revision while speaking replaces only the running phrase', () {
      DateTime clock = DateTime(2026, 9, 16);
      final AppDictationTranscript transcript = AppDictationTranscript(
        transform: same,
        now: () => clock,
      );

      transcript.add('by', isFinal: false);
      clock = clock.add(const Duration(milliseconds: 150));
      transcript.add('buy a', isFinal: false);
      clock = clock.add(const Duration(milliseconds: 150));
      transcript.add('buy a new one', isFinal: false);
      clock = clock.add(const Duration(milliseconds: 150));
      transcript.add('buy a new one for the ward', isFinal: false);

      expect(transcript.render(), 'buy a new one for the ward');
    });

    test('recognizers that resend the session keep earlier sentences', () {
      DateTime clock = DateTime(2026, 9, 16);
      final AppDictationTranscript transcript = AppDictationTranscript(
        transform: same,
        resendsSession: true,
        now: () => clock,
      );

      transcript.add('hello', isFinal: false);
      transcript.add('hello world', isFinal: true);
      transcript.add('hello world how are you', isFinal: false);
      expect(transcript.render(), 'hello world how are you');

      // iOS may drop everything after a long pause.
      clock = clock.add(const Duration(seconds: 3));
      transcript.add('fine thanks', isFinal: false);
      expect(transcript.render(), 'hello world how are you fine thanks');
    });

    test('after a user edit, a resent phrase adds only the new words', () {
      final AppDictationTranscript transcript = AppDictationTranscript(
        transform: same,
      );

      transcript.add('i want to', isFinal: false);
      transcript.freeze();
      transcript.add('i want to go home', isFinal: false);

      expect(transcript.render(), 'go home');
    });

    test('appSpeechTidyProse capitalizes sentences and fixes spacing', () {
      expect(
        appSpeechTidyProse(
          'hello  world . how are you ? i am fine,thanks and i\'m ok',
          startsSentence: true,
        ),
        "Hello world. How are you? I am fine, thanks and I'm ok",
      );
      expect(
        appSpeechTidyProse('first line\nsecond line', startsSentence: false),
        'first line\nSecond line',
      );
    });

    test('appSpeechTidyProse leaves abbreviations, decimals and links', () {
      const String text =
          'dose is 12.5 mg e.g. twice daily, i.e. with dr. smith at hospital.com';
      expect(appSpeechTidyProse(text, startsSentence: false), text);
    });

    test('appSpeechStartsSentence reads the text before the caret', () {
      expect(appSpeechStartsSentence(''), isTrue);
      expect(appSpeechStartsSentence('Done. '), isTrue);
      expect(appSpeechStartsSentence('Line one\n'), isTrue);
      expect(appSpeechStartsSentence('**Note.** '), isTrue);
      expect(appSpeechStartsSentence('The patient '), isFalse);
      expect(appSpeechStartsSentence('Seen by Dr. '), isFalse);
    });

    testWidgets('pausing in a multi-line field keeps and extends the text', (
      WidgetTester tester,
    ) async {
      final TextEditingController controller = TextEditingController();
      await pumpSpeechApp(
        tester,
        AppTextField(
          controller: controller,
          labelText: 'Details',
          keyboardType: TextInputType.multiline,
          minLines: 5,
          maxLines: 10,
        ),
      );
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(AppTextField)),
      );
      await tester.tap(find.byTooltip(l10n.speechToTextStartTooltip));
      await tester.pump(const Duration(milliseconds: 50));

      recognizer.emit('the report page');
      await tester.pump();
      recognizer.emit('the report page is slow');
      await tester.pump();

      // Pause, then the engine starts the next phrase from empty.
      now = now.add(const Duration(seconds: 3));
      recognizer.emit('when i');
      await tester.pump();
      recognizer.emit('when i open it');
      await tester.pump();
      expect(controller.text, 'The report page is slow when I open it');

      // Android ends the phrase, restarts, and the next sentence appends.
      recognizer.emit('when i open it period', isFinal: true);
      recognizer.finish();
      await tester.pump(const Duration(milliseconds: 200));
      now = now.add(const Duration(seconds: 2));
      recognizer.emit('it takes a minute', isFinal: true);
      await tester.pump();

      expect(
        controller.text,
        'The report page is slow when I open it. It takes a minute',
      );
      expect(find.byTooltip(l10n.speechToTextListeningTooltip), findsOneWidget);
    });

    testWidgets('an edit made during a pause is kept', (
      WidgetTester tester,
    ) async {
      final TextEditingController controller = TextEditingController();
      await coordinator.start(
        owner: controller,
        controller: controller,
        onChanged: null,
        longForm: true,
      );

      recognizer.emit('the first part', isFinal: true);
      expect(controller.text, 'The first part');

      // The user fixes a word and leaves the caret at the end.
      controller.value = const TextEditingValue(
        text: 'The opening part',
        selection: TextSelection.collapsed(offset: 16),
      );
      now = now.add(const Duration(seconds: 2));
      recognizer.emit('and more');
      recognizer.emit('and more words', isFinal: true);

      expect(controller.text, 'The opening part and more words');
      await coordinator.stop();
    });

    testWidgets('long-form formatting waits for a pause and uses context', (
      WidgetTester tester,
    ) async {
      final TextEditingController controller = TextEditingController(
        text: 'Intro sentence. ',
      );
      controller.selection = const TextSelection.collapsed(offset: 16);
      final List<({String transcript, String? context})> calls =
          <({String transcript, String? context})>[];

      await coordinator.start(
        owner: controller,
        controller: controller,
        onChanged: null,
        longForm: true,
        aiFormatter:
            ({
              required String transcript,
              required String mode,
              required AppSpeechAiAbort abort,
              String? locale,
              String? hint,
              String? context,
            }) async {
              calls.add((transcript: transcript, context: context));
              return 'The patient has had a fever since yesterday.';
            },
      );

      recognizer.emit(
        'the patient has had a fever since yesterday',
        isFinal: true,
      );
      expect(
        controller.text,
        'Intro sentence. The patient has had a fever since yesterday',
      );

      // Still speaking: formatting holds off.
      await tester.pump(const Duration(milliseconds: 800));
      recognizer.emit('and');
      await tester.pump(const Duration(milliseconds: 800));
      expect(calls, isEmpty);

      await tester.pump(const Duration(milliseconds: 800));
      expect(calls, hasLength(1));
      expect(
        calls.single.transcript,
        'the patient has had a fever since yesterday',
      );
      expect(calls.single.context, 'Intro sentence.');
      expect(
        controller.text,
        'Intro sentence. The patient has had a fever since yesterday. And',
      );
      await coordinator.stop();
    });

    test('stopping formats what was just said', () async {
      final TextEditingController controller = TextEditingController();
      final List<String> transcripts = <String>[];

      await coordinator.start(
        owner: controller,
        controller: controller,
        onChanged: null,
        longForm: true,
        aiFormatter:
            ({
              required String transcript,
              required String mode,
              required AppSpeechAiAbort abort,
              String? locale,
              String? hint,
              String? context,
            }) async {
              transcripts.add(transcript);
              return 'Please review the chart before rounds.';
            },
      );

      recognizer.emit('please review the chart before rounds');
      expect(controller.text, 'Please review the chart before rounds');

      await coordinator.stop(owner: controller, finishFormatting: true);
      await Future<void>.delayed(Duration.zero);

      expect(transcripts, <String>['please review the chart before rounds']);
      expect(controller.text, 'Please review the chart before rounds.');
      expect(coordinator.isFormatting, isFalse);
    });

    test('a field that goes away drops its last formatting pass', () async {
      final TextEditingController controller = TextEditingController();
      final Completer<String?> format = Completer<String?>();

      await coordinator.start(
        owner: controller,
        controller: controller,
        onChanged: null,
        longForm: true,
        aiFormatter:
            ({
              required String transcript,
              required String mode,
              required AppSpeechAiAbort abort,
              String? locale,
              String? hint,
              String? context,
            }) => format.future,
      );
      recognizer.emit('closing the dialog now', isFinal: true);
      await coordinator.stop(owner: controller, finishFormatting: true);
      expect(coordinator.isFormattingFor(controller), isTrue);

      // What the speech button does when its field is disposed.
      await coordinator.stop(owner: controller);
      controller.dispose();
      format.complete('Closing the dialog now.');
      await Future<void>.delayed(Duration.zero);

      expect(coordinator.isFormatting, isFalse);
    });
  });
}
