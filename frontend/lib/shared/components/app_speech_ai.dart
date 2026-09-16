/// Cancels an in-flight AI format request.
final class AppSpeechAiAbort {
  void Function()? _onAbort;

  void attach(void Function() onAbort) {
    _onAbort = onAbort;
  }

  void abort() {
    _onAbort?.call();
  }
}

/// Optional backend formatter. Returns null to keep the STT text.
///
/// [context] is the field text right before [transcript] (long-form fields),
/// so a continuation is capitalized and punctuated as part of its sentence.
typedef AppSpeechAiFormatter =
    Future<String?> Function({
      required String transcript,
      required String mode,
      required AppSpeechAiAbort abort,
      String? locale,
      String? hint,
      String? context,
    });
