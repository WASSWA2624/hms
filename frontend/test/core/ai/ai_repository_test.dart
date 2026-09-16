import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hosspi_hms/core/ai/ai_clinical_note_formatter.dart';
import 'package:hosspi_hms/core/ai/ai_drug_pack_extractor.dart';
import 'package:hosspi_hms/core/ai/ai_models.dart';
import 'package:hosspi_hms/core/ai/ai_remote_data_source.dart';
import 'package:hosspi_hms/core/ai/ai_repository.dart';
import 'package:hosspi_hms/core/ai/ai_repository_impl.dart';
import 'package:hosspi_hms/core/ai/ai_speech_formatter.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/network/api_result.dart';
import 'package:hosspi_hms/shared/components/app_speech_ai.dart';
import 'package:hosspi_hms/shared/scan/scan.dart';

final class _FakeAiRemoteDataSource implements AiRemoteDataSource {
  _FakeAiRemoteDataSource({
    this.statusResult,
    this.taskResult,
  });

  ApiResult<AiStatus>? statusResult;
  ApiResult<AiTaskResult>? taskResult;
  int statusCalls = 0;
  int taskCalls = 0;
  String? lastTaskKey;
  Map<String, Object?>? lastBody;

  @override
  Future<ApiResult<AiStatus>> status({cancelToken}) async {
    statusCalls += 1;
    return statusResult ??
        const Result.success(
          AiStatus(
            enabled: true,
            provider: 'ollama',
            model: 'llama3.2:3b',
            ready: true,
          ),
        );
  }

  @override
  Future<ApiResult<AiTaskResult>> runTask(
    String taskKey,
    Map<String, Object?> body, {
    cancelToken,
  }) async {
    taskCalls += 1;
    lastTaskKey = taskKey;
    lastBody = body;
    return taskResult ??
        Result.success(
          AiTaskResult(
            taskKey: taskKey,
            output: const <String, Object?>{'formatted_text': 'ok', 'mode': 'text'},
            degraded: false,
            model: 'llama3.2:3b',
            provider: 'ollama',
          ),
        );
  }
}

void main() {
  test('status is cached and runTask posts speech_format', () async {
    final _FakeAiRemoteDataSource remote = _FakeAiRemoteDataSource();
    final AiRepository repository = AiRepositoryImpl(
      remoteDataSource: remote,
      statusCacheTtl: const Duration(seconds: 30),
    );

    await repository.status();
    await repository.status();
    expect(remote.statusCalls, 1);

    final result = await repository.runTask('speech_format', <String, Object?>{
      'transcript': 'hello',
      'mode': 'text',
    });
    expect(result.isSuccess, isTrue);
    expect(remote.lastTaskKey, 'speech_format');
    expect(remote.lastBody?['transcript'], 'hello');
  });

  test('formatter skips the task when AI is not ready', () async {
    final _FakeAiRemoteDataSource remote = _FakeAiRemoteDataSource(
      statusResult: const Result.success(
        AiStatus(
          enabled: true,
          provider: 'ollama',
          model: 'llama3.2:3b',
          ready: false,
        ),
      ),
    );
    final formatter = createAiSpeechFormatter(
      AiRepositoryImpl(remoteDataSource: remote),
    );

    final String? formatted = await formatter(
      transcript: 'hello',
      mode: 'text',
      abort: AppSpeechAiAbort(),
    );

    expect(formatted, isNull);
    expect(remote.taskCalls, 0);
  });

  test('formatter returns null when the task is degraded', () async {
    final _FakeAiRemoteDataSource remote = _FakeAiRemoteDataSource(
      taskResult: const Result.success(
        AiTaskResult(
          taskKey: 'speech_format',
          output: <String, Object?>{
            'formatted_text': 'hello',
            'mode': 'text',
          },
          degraded: true,
        ),
      ),
    );
    final formatter = createAiSpeechFormatter(
      AiRepositoryImpl(remoteDataSource: remote),
    );

    final String? formatted = await formatter(
      transcript: 'hello',
      mode: 'text',
      abort: AppSpeechAiAbort(),
    );

    expect(formatted, isNull);
  });

  test('formatter returns formatted_text when the provider succeeds', () async {
    final _FakeAiRemoteDataSource remote = _FakeAiRemoteDataSource(
      taskResult: const Result.success(
        AiTaskResult(
          taskKey: 'speech_format',
          output: <String, Object?>{
            'formatted_text': 'name@hospital.com',
            'mode': 'email',
          },
          degraded: false,
          model: 'llama3.2:3b',
          provider: 'ollama',
        ),
      ),
    );
    final formatter = createAiSpeechFormatter(
      AiRepositoryImpl(remoteDataSource: remote),
    );

    final String? formatted = await formatter(
      transcript: 'name at hospital dot com',
      mode: 'email',
      abort: AppSpeechAiAbort(),
    );

    expect(formatted, 'name@hospital.com');
    expect(remote.lastTaskKey, 'speech_format');
    expect(remote.lastBody?['mode'], 'email');
    expect(remote.lastBody?.containsKey('context_before'), isFalse);
  });

  test('formatter sends the text before a long-form dictation', () async {
    final _FakeAiRemoteDataSource remote = _FakeAiRemoteDataSource(
      taskResult: const Result.success(
        AiTaskResult(
          taskKey: 'speech_format',
          output: <String, Object?>{
            'formatted_text': 'since yesterday.',
            'mode': 'text',
          },
          degraded: false,
        ),
      ),
    );
    final formatter = createAiSpeechFormatter(
      AiRepositoryImpl(remoteDataSource: remote),
    );

    await formatter(
      transcript: 'since yesterday',
      mode: 'text',
      abort: AppSpeechAiAbort(),
      context: 'The patient has had a fever',
    );

    expect(remote.lastBody?['context_before'], 'The patient has had a fever');
  });

  test('clinical note formatter calls clinical_note_format', () async {
    final _FakeAiRemoteDataSource remote = _FakeAiRemoteDataSource(
      taskResult: const Result.success(
        AiTaskResult(
          taskKey: 'clinical_note_format',
          output: <String, Object?>{
            'formatted_text':
                'The patient reports fever since yesterday.',
          },
          degraded: false,
          model: 'llama3.2:3b',
          provider: 'ollama',
        ),
      ),
    );
    final formatter = createAiClinicalNoteFormatter(
      AiRepositoryImpl(remoteDataSource: remote),
    );

    final AppClinicalNoteAiFormatResult formatted = await formatter(
      text: 'pt c/o fever since yesterday',
      abort: AppSpeechAiAbort(),
      hint: 'Clinical note',
    );

    expect(formatted.text, 'The patient reports fever since yesterday.');
    expect(formatted.failure, isNull);
    expect(remote.lastTaskKey, 'clinical_note_format');
    expect(remote.lastBody?['text'], 'pt c/o fever since yesterday');
    expect(remote.lastBody?['hint'], 'Clinical note');
  });

  test('clinical note formatter still runs when status ready is false', () async {
    final _FakeAiRemoteDataSource remote = _FakeAiRemoteDataSource(
      statusResult: const Result.success(
        AiStatus(
          enabled: true,
          provider: 'ollama',
          model: 'llama3.2:3b',
          ready: false,
        ),
      ),
      taskResult: const Result.success(
        AiTaskResult(
          taskKey: 'clinical_note_format',
          output: <String, Object?>{
            'formatted_text': 'Patient is febrile.',
          },
          degraded: false,
        ),
      ),
    );
    final formatter = createAiClinicalNoteFormatter(
      AiRepositoryImpl(remoteDataSource: remote),
    );

    final AppClinicalNoteAiFormatResult formatted = await formatter(
      text: 'pt febrile',
      abort: AppSpeechAiAbort(),
    );

    expect(formatted.text, 'Patient is febrile.');
    expect(remote.taskCalls, 1);
    expect(remote.statusCalls, 0);
  });

  test('clinical note formatter returns null when the task is degraded', () async {
    final _FakeAiRemoteDataSource remote = _FakeAiRemoteDataSource(
      taskResult: const Result.success(
        AiTaskResult(
          taskKey: 'clinical_note_format',
          output: <String, Object?>{
            'formatted_text': 'pt febrile',
          },
          degraded: true,
        ),
      ),
    );
    final formatter = createAiClinicalNoteFormatter(
      AiRepositoryImpl(remoteDataSource: remote),
    );

    final AppClinicalNoteAiFormatResult formatted = await formatter(
      text: 'pt febrile',
      abort: AppSpeechAiAbort(),
    );

    expect(formatted.text, isNull);
    expect(formatted.failure, isNull);
    expect(remote.taskCalls, 1);
  });

  test('runTask rejects a blank task key', () async {
    final AiRepository repository = AiRepositoryImpl(
      remoteDataSource: _FakeAiRemoteDataSource(),
    );
    final Result<AiTaskResult> result = await repository.runTask(
      '  ',
      const <String, Object?>{},
    );
    expect(result.isFailure, isTrue);
    result.when(
      success: (_) => fail('expected validation failure'),
      failure: (AppFailure failure) {
        expect(failure.category, AppFailureCategory.validation);
      },
    );
  });

  test('drug pack mapper posts photos to drug_pack_extract', () async {
    final _FakeAiRemoteDataSource remote = _FakeAiRemoteDataSource(
      taskResult: const Result.success(
        AiTaskResult(
          taskKey: 'drug_pack_extract',
          output: <String, Object?>{
            'generic_name': 'Paracetamol',
            'brand_name': 'AGOMO',
            'form': 'Tablet',
            'strength': '500 mg',
            'raw_text': 'AGOMO Paracetamol Tablets 500 mg',
          },
          degraded: false,
          model: 'gemma3:4b',
          provider: 'ollama',
        ),
      ),
    );
    final DrugPackRemoteAiMapper mapper = DrugPackRemoteAiMapper(
      repository: AiRepositoryImpl(remoteDataSource: remote),
    );

    final DrugPackAiMapResult mapped = await mapper.map(
      rawText: '',
      images: <DrugPackAiImage>[
        DrugPackAiImage(
          bytes: Uint8List.fromList(<int>[
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00,
            0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00,
            0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
            0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63,
            0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4,
            0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60,
            0x82,
          ]),
          mimeType: 'image/png',
        ),
      ],
    );

    expect(mapped.unavailable, isFalse);
    expect(mapped.candidates?.genericName, 'Paracetamol');
    expect(mapped.candidates?.brandName, 'AGOMO');
    expect(remote.lastTaskKey, 'drug_pack_extract');
    final Object? images = remote.lastBody?['images'];
    expect(images, isA<List<Object?>>());
    expect((images! as List<Object?>).single, isA<Map<String, Object?>>());
    final Map<String, Object?> encoded =
        (images as List<Object?>).single as Map<String, Object?>;
    expect(encoded['mime_type'], 'image/jpeg');
    expect(encoded['data'], isA<String>());
    expect((encoded['data']! as String).length, greaterThan(8));
  });

  test('drug pack mapper is unavailable when the task is degraded', () async {
    final _FakeAiRemoteDataSource remote = _FakeAiRemoteDataSource(
      taskResult: const Result.success(
        AiTaskResult(
          taskKey: 'drug_pack_extract',
          output: <String, Object?>{
            'generic_name': null,
            'raw_text': 'Paracetamol',
          },
          degraded: true,
        ),
      ),
    );
    final DrugPackRemoteAiMapper mapper = DrugPackRemoteAiMapper(
      repository: AiRepositoryImpl(remoteDataSource: remote),
    );

    final DrugPackAiMapResult mapped = await mapper.map(
      rawText: 'Paracetamol Tablets 500 mg',
    );

    expect(mapped.unavailable, isTrue);
    expect(mapped.hasCandidates, isFalse);
    expect(remote.lastTaskKey, 'drug_pack_extract');
    expect(remote.lastBody?['ocr_text'], 'Paracetamol Tablets 500 mg');
  });
}
