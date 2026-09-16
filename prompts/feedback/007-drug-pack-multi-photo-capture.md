# 007 — Drug Pack Scan: Native Multi-Photo Capture and OCR

**Feedback:** FBK0000018 · **Depends on:** — · **Stack:** frontend
**Index:** [000-index.md](000-index.md) (working agreements apply)

## Objective

On the Android (and iOS) app, "Scan pack or use AI capture" works the way it already does on web:

- The user takes several photos of a medicine package back to back (front, back, sides, blister, label), and/or picks several images.
- The user reviews, crops, rotates or removes them.
- Extraction (OCR and/or AI) runs across **all** photos, and the merged result pre-fills the drug form.

## Feedback covered

| Field | Value |
| :--- | :--- |
| Feedback ID | FBK0000018 |
| Submitted (EAT) | 2026-09-15 16:15:38 |
| Category | Improvement |
| Feedback (verbatim) | "When creating a new pharmacy order with scan and capture, implement multiple photo capute and or upload so that the OCR is bases on multiple photos and one can take all photos of the package." |
| Reporter | Platform Administrator · `PLATFORM_ADMIN` · DemoCare General Hospital · Pro `ACTIVE` |
| Screen / route | `pharmacy` · `/pharmacy?section=catalog` (catalog → create drug → "Scan pack or use AI capture") |
| Device | Android app (`Dart/3.12`), Mobile 393×886 @2.75x, portrait, `sm` · production · light · `en` · online |

"New pharmacy order" in the text refers to creating a catalog drug. The route is the catalog section, and scan & capture exists only in `pharmacy_drug_edit_dialog.dart` → `showPharmacyDrugPackScanDialog`.

## Current behavior (verified at `9cb01bb57`)

- **The dialog already handles multiple photos.** `frontend/lib/features/pharmacy/presentation/widgets/pharmacy_drug_pack_scan_dialog.dart` keeps a session list `_photos`, supports crop/rotate/remove, and runs `_processPhotos` over all photos, for both `_PhotoEngine.ocr` (`_runOcrAcrossPhotos`) and `_PhotoEngine.ai` (`DrugPackRemoteAiMapper` with every image). This landed in `1befef8e7`/`7d4e6502c` (2026-08-02).
- **Camera capture doesn't work on native apps.** `takeEphemeralImage` (`frontend/lib/shared/scan/app_ephemeral_image_capture.dart`) only works on web:
  - `app_live_camera_stub.dart`: `liveCameraCaptureSupported => false`.
  - `app_ephemeral_camera_stub.dart`: `pickEphemeralCameraImageBytes()` returns `null`.
  - So "Take photo" on Android always ends with "camera unavailable" and never adds a photo.
- **OCR is a no-op on native apps.** `app_ocr_service_stub.dart` returns `AppNoOpOcrService`; only web has Tesseract.js (`app_ocr_service_web.dart`). On Android only the AI engine can extract text.
- **Upload.** "Upload" uses `pickAppImageFiles` → `file_selector.openFiles`, which opens the Android document picker rather than the photo gallery, and each image goes through the crop dialog one by one.
- **No camera plugins.** `pubspec.yaml` has no camera/image picker or on-device OCR package.

## Required behavior

1. **Native camera capture.**
   - Implement the native side of the ephemeral capture boundary (conditional import next to the existing `*_stub.dart` / `*_web.dart`), so `takeEphemeralImage` returns photos on Android/iOS.
   - Keep bytes in memory only; never upload them to media APIs (the existing contract).
   - Request camera permission with a localized rationale and handle denial/"don't ask again" with a settings hint.
2. **Burst capture flow.**
   - After a capture, return to a capture-ready state with "Take another", "Done", and a thumbnail strip with a count badge ("4 photos"), so a whole pack can be shot without reopening the camera each time.
   - Cropping is optional per photo from the strip, not forced after every shot.
3. **Gallery multi-select** on Android/iOS through the system photo picker (multi-select). Keep `file_selector` for desktop/web. Skip per-image forced crop when many images are picked; allow cropping afterwards.
4. **Extraction on native.**
   - Provide a native on-device OCR implementation of `AppOcrService` (text recognition over each photo, merged in `_runOcrAcrossPhotos`), so both engines work offline-capable on phones.
   - If an on-device OCR dependency isn't approved, hide the OCR engine on native, make AI the default with a clear localized note, and keep the rest of this task.
5. **Limits and performance.**
   - Cap the session (e.g. 10 photos) with a localized message.
   - Downscale/compress before AI (the existing `encodeAppImageForAi`) and run OCR off the UI thread (isolate/compute where the plugin allows), showing progress "Reading photo 2 of 5" (`frontend/.cursor/performance.mdc`).
6. **Merge rules unchanged.** Reuse `DrugPackFieldCandidates.merge` and the parser. Fields filled from photos are marked "suggested" as today.
7. **Web stays the same:** live camera, Tesseract.js, multi-upload.
8. **All hosts benefit.** Every other user of `takeEphemeralImage`/`uploadEphemeralImages` gets native capture automatically; confirm none of them break.

## Implementation constraints

- **Dependencies.** New packages (camera/image picker, on-device text recognition) need approval under `frontend/.cursor/dependencies.mdc`: document owner, purpose, platform compatibility (Android, iOS, Web, Windows, macOS, Linux), maintenance status and binary-size impact in the PR. Prefer one well-maintained package per responsibility, and keep platform checks at the infrastructure boundary (`frontend/.cursor/platform_guidelines.mdc`).
- **Native permissions.** Android `CAMERA` in `frontend/android/app/src/main/AndroidManifest.xml`; iOS `NSCameraUsageDescription` / `NSPhotoLibraryUsageDescription` in `Info.plist`. Use localized in-app rationale.
- **Privacy.** Pack photos can include patient labels. Never persist, log or upload them outside the AI extraction request (`frontend/.cursor/security.mdc`).
- **UI.** Shared capture components live in `frontend/lib/shared/scan/`. Loading uses `AppLoadingIndicator` with messages. Tokens, localization, 48 px targets, safe areas.

## Verification

- **Unit/widget tests:**
  - `frontend/test/features/pharmacy/presentation/pharmacy_drug_pack_scan_dialog_test.dart`: burst capture appends N photos through a fake capture service; multi-pick adds N; removing and cropping from the strip; processing sends all photos to the AI mapper and OCR across all photos; the session cap message.
  - `frontend/test/shared/scan/`: the native OCR/capture adapters are selected by platform via the conditional import; fakes are used in tests.
- **Run:** `cd frontend && flutter pub get && flutter gen-l10n && flutter analyze && flutter test test/features/pharmacy/presentation/pharmacy_drug_pack_scan_dialog_test.dart test/shared/scan/`.
- **Manual (real Android device, release or profile build):** Pharmacy → Catalog → Create drug → Scan pack.
  1. Take 4 photos in one flow → review → Extract with AI and with OCR → the form pre-fills from text spread across photos.
  2. Pick 3 gallery images → extract.
  3. Deny camera permission → a helpful message.
  4. Airplane mode → OCR still works, and AI shows its unavailable message.
- **Spot-check:** Chrome desktop, where web behavior is unchanged.

## Dependencies

None. Pharmacy prompt 001 touches different files.
