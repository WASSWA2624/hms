# 003 — Continuous Speech-to-Text Until Stopped Manually

**Feedback:** FBK0000014 · **Depends on:** — · **Stack:** frontend
**Index:** [000-index.md](000-index.md) (working agreements apply)

## Objective

Once a user turns on the microphone on any field, dictation keeps listening across pauses and after each phrase. It stops only when the user turns it off or a clear lifecycle reason ends it (another field starts dictation, the field/dialog/route goes away, the app goes to background, permission is lost). Text already dictated is never lost or overwritten when the recognizer restarts internally.

## Feedback covered

| Field | Value |
| :--- | :--- |
| Feedback ID | FBK0000014 |
| Submitted (EAT) | 2026-09-15 09:32:22 |
| Category | General feedback |
| Feedback (verbatim) | "I don't know why the detect with microphone functionality doesn't work well. It will detect the audio on mobile but after speaking or after a few moments, it goes off by itself. It should remain actively on unless it's switched off manually." |
| Reporter | Platform Administrator · `PLATFORM_ADMIN` · DemoCare General Hospital · Pro `ACTIVE` |
| Screen / route | `tenantFacilitySetup` · `/admin/setup?section=tenants` (the field was in setup, but the component is shared) |
| Device | Android app (`Dart/3.12`), Mobile 393×886 @2.75x, portrait, `sm` · production · light · `en` · time zone `EAT` · online |

## Current behavior (verified at `9cb01bb57`)

- **One shared implementation.** Everything goes through `frontend/lib/shared/components/app_speech_to_text.dart` (`speech_to_text: 7.4.0`): `AppSpeechRecognizer` interface → `SpeechToTextAppSpeechRecognizer`, `AppSpeechToTextCoordinator` (one active owner), `AppSpeechToTextButton` (used by `AppTextField` and other shared inputs).
- **No continuous-mode settings.** `startListening` calls `_speech.listen` with `SpeechListenOptions(cancelOnError: true, listenMode: ListenMode.dictation)` and no `listenFor`/`pauseFor`.
- **The platform ends the session.** Android's recognizer ends a session after a final result or a short silence. It emits status `done`/`notListening`, often with soft errors such as `error_speech_timeout` / `error_no_match`.
- **The coordinator gives up.** On `done`/`notListening`, when `!_recognizer.isListening`, it calls `_endSession()`, and any `onError` also ends the session. The mic switches off by itself — exactly the reported symptom.

## Required behavior

1. **Continuous session model.** In `AppSpeechToTextCoordinator`, treat the user's on/off intent as the source of truth. While intent is "on", a platform `done`/`notListening`, or a soft error (`error_speech_timeout`, `error_no_match`, `error_client` right after a stop, and their web equivalents), triggers a quick automatic restart of the recognizer for the same owner and controller.
2. **Keep dictated text across restarts.** Before restarting, commit the current final span. Rebase `_sessionPrefix`/`_sessionSuffix` on the controller's current text and selection, so the next recognizer session appends at the caret instead of rewriting earlier words. The AI final-format pass (`_formatFinalTranscript`) must not race a restart. Apply it per committed span, or defer it until the session truly ends; either way it must not duplicate text.
3. **Hard stops end intent.** Explicit mic tap, another field starting dictation (the existing single-owner rule), owner widget disposal, the dialog/route closing, `AppLifecycleState.paused`/`inactive`, permission revoked, recognizer unavailable, or repeated hard errors (e.g. 3 consecutive failures in a short window, with backoff between attempts). A hard stop shows the existing localized error/unavailable feedback. Never show raw plugin error strings.
4. **Stable visual state.** The mic button stays in its "listening" state through internal restarts; no flicker between idle and listening. Add a localized semantics label / tooltip ("Listening — tap to stop").
5. **Longer pauses.** Pass sensible `listenFor`/`pauseFor` values and `partialResults: true` where the platform honors them, so restarts happen less often. Restart-on-done is still the guarantee on Android.
6. **Web and desktop.** Same behavior on Chrome/Edge (`ListenMode.dictation`, which is continuous on web). No regression on platforms where speech is unavailable. The button stays hidden/disabled as it is today.
7. **Consistent everywhere.** All hosts of `AppSpeechToTextButton` get this for free. Fields that opt out (`enableSpeechToText: false`) are unchanged.

## Implementation constraints

- **Keep it in shared code.** Change only `frontend/lib/shared/components/app_speech_to_text.dart` (plus the button host if needed). No feature-local speech code (`frontend/.cursor/components.mdc`).
- **Lifecycle and privacy.** Riverpod owns the coordinator lifecycle. Don't start listening from `build()` (`frontend/.cursor/state_management.mdc`). Stop and release the microphone on background/dispose — no hidden recording (`frontend/.cursor/security.mdc`, `platform_guidelines.mdc`).
- **No new dependency.** Solve it with `speech_to_text` (`frontend/.cursor/dependencies.mdc`).
- **Known limit.** Android may play the system "start listening" tone on each restart. Where the plugin allows, suppress it or keep restart gaps minimal, and note the limitation in the PR.
- **Copy.** Localized strings in `app_en.arb`.

## Verification

- **Unit/widget tests** in `frontend/test/shared/components/app_speech_to_text_test.dart`, using a fake `AppSpeechRecognizer` that emits `done` / soft errors:
  - The session auto-restarts and the button stays listening.
  - Text from two consecutive recognizer sessions is concatenated at the caret, not replaced.
  - An explicit stop, another owner starting, owner dispose and lifecycle pause each end the session with no restart.
  - Repeated hard errors end the session after the backoff limit and surface a localized error.
- **Run:** `cd frontend && flutter gen-l10n && flutter analyze && flutter test test/shared/components/app_speech_to_text_test.dart`.
- **Manual (Android phone):** tenant setup form field → mic on → speak, pause 10 s, speak again, pause 30 s, speak again → all text present, mic still on → tap to stop. Repeat in a dialog field, close the dialog while listening (the mic must stop), and background the app while listening (the mic must stop). Spot-check Chrome desktop.

## Dependencies

None.
