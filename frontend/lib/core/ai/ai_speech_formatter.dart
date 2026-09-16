import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/core/ai/ai_models.dart';
import 'package:hosspi_hms/core/ai/ai_repository.dart';
import 'package:hosspi_hms/core/ai/ai_repository_impl.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/shared/components/app_speech_ai.dart';

final aiSpeechFormatterProvider = Provider<AppSpeechAiFormatter?>((ref) {
  return createAiSpeechFormatter(ref.watch(aiRepositoryProvider));
});

AppSpeechAiFormatter createAiSpeechFormatter(AiRepository repository) {
  return ({
    required String transcript,
    required String mode,
    required AppSpeechAiAbort abort,
    String? locale,
    String? hint,
    String? context,
  }) async {
    final CancelToken cancelToken = CancelToken();
    abort.attach(() {
      cancelToken.cancel();
    });

    final Result<AiStatus> statusResult = await repository.status(
      cancelToken: cancelToken,
    );
    final bool available = statusResult.when(
      success: (AiStatus status) => status.isAvailable,
      failure: (_) => false,
    );
    if (!available || cancelToken.isCancelled) {
      return null;
    }

    final Result<AiTaskResult> taskResult = await repository.runTask(
      'speech_format',
      <String, Object?>{
        'transcript': transcript,
        'mode': mode,
        if (locale != null && locale.trim().isNotEmpty) 'locale': locale.trim(),
        if (hint != null && hint.trim().isNotEmpty) 'hint': hint.trim(),
        if (context != null && context.trim().isNotEmpty)
          'context_before': context,
      },
      cancelToken: cancelToken,
    );

    return taskResult.when(
      success: (AiTaskResult result) {
        if (result.degraded) {
          return null;
        }
        return result.formattedText;
      },
      failure: (_) => null,
    );
  };
}
