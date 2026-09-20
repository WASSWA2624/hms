# Give us feedback: screenshots captured while navigating the app

**Source:** direct request (dictated; verbatim transcript at the end) · **Stack:** frontend + backend
**Verified against:** `main` at `a5347239c`
**House style:** [`prompts/feedback/feedback.md`](feedback/feedback.md) working agreements apply

## Objective

Let anyone giving feedback attach screenshots to it. The screen the report was raised from is captured automatically, and the reporter can then walk through the app capturing more screens without losing the feedback they have already typed. Platform owners and admins can see those screenshots when they review or download feedback.

"Download feedback" filters are **not** part of this work — they are already sufficient (search, category, submitter, device, platform, date range, tenant, facility, role, plan, route, environment, app version, locale, breakpoint, theme, connectivity, orientation).

## What exists today — do not rebuild

- **Floating control:** `AppFeedbackHost` (`frontend/lib/features/feedback/presentation/widgets/app_feedback_host.dart`) mounts above every route, dialog and sheet, is draggable, and hides itself while one of its own dialogs is open.
- **Menu:** platform owner/admin get *Give us feedback*, *Download feedback*, *Clear feedback* (`_FeedbackMenuAction`); everyone else gets the submit flow only (`canManageFeedback`, `feedback_access.dart`). The API enforces the same roles (`FEEDBACK_ADMIN_ROLES`).
- **Submit dialog:** `FeedbackSubmitDialog` (`feedback_submit_dialog.dart`) — category checkboxes plus a details field, sized to content, translucent (`_surfaceOpacity = 0.86`) so the screen behind stays readable. It holds the draft in its own `State`, so closing it loses everything typed.
- **Context capture:** `_openFeedbackDialog` calls `captureFeedbackContext` (`feedback_context_capture.dart`) before opening the dialog — route path/name, page URL, screen title, platform, device type, viewport/display, locale, time zone, breakpoint, theme, text scale, connectivity, orientation.
- **Submit API:** `POST /api/v1/feedback` — JSON, optional authentication (works signed out and on sign-in screens), rate limited (`rateLimitConfig.endpoints.feedback`).
- **Model:** `feedback` (`backend/prisma/schema.prisma`) stores context snapshots only. **There is no attachment table, no upload route and no blob storage for feedback yet** — all of that is new.
- **Reusable pieces:** widget-to-PNG capture via `RepaintBoundary` plus an off-screen overlay (`frontend/lib/shared/reporting/module_reporting_chart_capture.dart`); crop dialog `AppImageCropDialog`; upload/preview components `app_image_upload_field.dart`, `app_file_upload_panel.dart`; backend `createStorageService()` (`backend/src/lib/storage/factory.js` — local or S3 by env, encrypted at rest) and `multer`, already used by the workspace import routes.

## Required behavior

### 1. Automatic first shot

Tapping *Give us feedback* captures the app frame **as it was when the control was tapped**, before the dialog opens, and attaches it as the first screenshot. The floating control itself must not appear in the image. The shot is removable like any other. The feedback row's own route context stays the screen the flow started on.

### 2. Capture more screens without losing the draft

- Move the draft (category, message, shots) out of `FeedbackSubmitDialog` into a host-owned, session-scoped controller (Riverpod, e.g. `feedbackDraftProvider`) so it survives the dialog closing, navigation and rotation. Clear it on submit, on explicit discard, and on sign-out.
- A **"Capture another screen"** action puts the flow into capture mode: the dialog closes, the draft is kept, and the floating control becomes a capture control offering *Capture*, *Back to feedback* and *Cancel*. The user can navigate anywhere in the app and capture as many screens as the limit allows.
- Reopening the dialog (or *Back to feedback*) restores the message, the category and every shot exactly as they were.
- While in capture mode, make the state obvious — the control is labelled, and a dismissible hint says the draft is being kept.

### 3. Capture the dialog itself, or not

A toggle on the capture action — *Include the feedback dialog in this shot* — default **off**. Off captures the app behind the dialog, with the dialog and the floating control excluded; on captures what is on screen, dialog included. The automatic first shot follows the same rule and never includes the control.

### 4. Managing the shots

In the dialog: a thumbnail strip with each shot's screen name, ordered by capture time. Per shot — preview full size, optional crop (reuse `AppImageCropDialog`, the reporter's way of cropping out anything they don't want to send), optional short caption, remove. Each shot stores its own capture context (route path, route name, screen title, viewport, orientation, theme, captured-at), not the dialog's.

### 5. Limits and failure handling

- At most **5** shots per submission; longest edge downscaled to **1600 px**; encoded as JPEG (quality ~80) with the `image` package; hard caps of **2 MB** per file and **8 MB** per request, enforced on the client *and* the server.
- Capture is best-effort: if `RenderRepaintBoundary.toImage` fails (notably on web renderers where it can throw), show a plain message, drop that shot, and let the feedback be submitted without it. **Never block submitting feedback because a screenshot failed.**
- Submitting with no shots stays valid and must not get slower.

### 6. Transport and storage

- Accept `multipart/form-data` on the existing `POST /api/v1/feedback` (multer, memory storage, file-count and size limits, MIME sniffed from content rather than extension — PNG, JPEG and WebP only). Keep the current JSON body working unchanged so older builds keep submitting.
- Persist blobs through `createStorageService()` under `feedback/<feedback_id>/<sequence>-<uuid>.<ext>`; never write them into the database row, and never serve them from a public path.
- New Prisma model `feedback_screenshot`: `id`, `feedback_id` (FK, cascade), `sequence`, `storage_key`, `content_type`, `byte_size`, `width`, `height`, `caption`, `route_path`, `route_name`, `screen_title`, `client_context_json`, `captured_at`, `created_at`, `deleted_at`. Migration plus a doc under `backend/docs/migrations/` (pattern: `20260914120000_feedback.md`).
- Saving is resilient, not all-or-nothing: if a blob write fails, the feedback text still saves and the response says which shots were dropped.

### 7. Reviewing and removing them

- `GET /api/v1/feedback/:human_friendly_id/screenshots` (metadata) and `GET /api/v1/feedback/:human_friendly_id/screenshots/:screenshot_id` (streamed bytes), both platform owner/admin only, both audited. No signed public URLs.
- `FeedbackRecordsDialog` shows a shot count per row and opens a viewer for them, so Download is not the only way to see a screenshot.
- Deleting feedback — single, selected, or "all matching" through *Clear feedback* — permanently deletes the stored blobs too. No orphans.
- Export: add a **Screenshots** count column to the workbook (`backend/src/lib/feedback/feedback-export.js`), and an *Include screenshots* option in `FeedbackDownloadDialog` that returns a ZIP (`HOSSPI-FEEDBACK-DDMMYYYY-HHmmss.zip`: the workbook plus `screenshots/<FBK…>/<n>.jpg`) instead of a bare `.xlsx`. Check which archive library the backend already depends on before adding one.

## Implementation constraints

- **Privacy.** Screenshots of this app can contain patient data — treat them as PHI (`backend/.cursor/compliance.mdc`, `auth-security.mdc`): encrypted at rest through the storage service, readable only by platform owner/admin, audit evidence on view, export and delete, never logged, never in URLs or query strings. Show a one-line notice in the dialog that screenshots may contain patient data, and keep the existing credential scrubbing for route and URL context.
- **Anonymous submissions** keep working (sign-in screens, lapsed sessions) with the same caps and rate limit; they must not become a way to upload arbitrary files.
- **Backend:** Zod for every new field, including the multipart text parts (`backend/.cursor/validation.mdc`); documented in `backend/docs/api/v1/openapi.yaml` (`api.mdc`, `documentation.mdc`); storage access only through the factory (`storage.mdc`); rate limits reviewed for the larger payload (`rate-limiting.mdc`).
- **Frontend:** shared components only — `AppDialog`, `AppButton`, `AppLoadingIndicator` with a message, `AppImageCropDialog` (`frontend/.cursor/components.mdc`, `design-system.mdc`). Every new label, tooltip, hint and error localized in `app_en.arb` (`localization_i18n.mdc`); capture and crop must work with touch, mouse and keyboard (`multi_platform_input.mdc`, `accessibility.mdc`). No new dependency without checking `dependencies.mdc`.
- **Performance:** encode off the UI thread where the platform allows; downscale before upload; never hold more than the capped shots in memory.

## Verification

- **Backend** (`backend/src/tests/modules/feedback/`, `backend/src/tests/lib/feedback/`): multipart submit stores rows plus blobs; JSON submit still works; oversized, too many, and non-image uploads are rejected; anonymous caps enforced; screenshot fetch is 403 for non-admins; deleting feedback (by id and all-matching) removes blobs; export count column and ZIP contents.
- **Frontend** (`frontend/test/features/feedback/`): the first shot is attached automatically and excludes the launcher; entering capture mode, navigating, capturing and reopening preserves message, category and shots; the include-dialog toggle changes what is captured; remove and crop update the draft; a failed capture surfaces a message and still allows submit; the repository sends multipart with per-shot context.
- **Run:** `cd backend && npm run prisma:migrate && npm run lint && node scripts/run-jest.js src/tests/modules/feedback src/tests/lib/feedback && npm run openapi:validate`; `cd frontend && flutter gen-l10n && flutter analyze && flutter test test/features/feedback/`.
- **Manual:** on web and Android — raise feedback from an OPD encounter and confirm the automatic shot; capture two more screens, one with the dialog included; submit; download with *Include screenshots* and confirm the ZIP holds exactly those images; clear that record and confirm the blobs are gone.

## Decisions to confirm before building

1. **ZIP export vs. images embedded in the workbook.** ZIP is assumed above — smaller, lossless, and the workbook stays usable.
2. **Retention.** Screenshots live and die with the feedback row; no separate retention window is assumed.
3. **Anonymous cap.** A lower cap (2 shots) for signed-out reporters is assumed.

## Source (verbatim request)

> Let us update the feedback flow or functionality as follows. Currently, when I click the feedback button, it opens the feedback context menu, which is okay because I am able to give feedback. But I want us to update it such that when I'm on the platform admin account — it currently gives me three menus, that is the *Give us feedback* menu, *Download feedback* and then *Clear feedback*. When I click *Give us feedback*, that dialogue is okay, but I want us to advance it in such a way that I am able to take screenshots. These screenshots should be such that it automatically takes the screenshot of the previous screen where the *Give us feedback* dialogue was triggered from — that should be captured by default. Then I should have buttons where I can take screenshots, I can navigate through the app and take screenshots from different parts of the app, of the device, of the screen; I can navigate to another screen in the app and take screenshots. I can take screenshots including the *Give us feedback* dialogue itself, but I may also exclude it. So I should be able to give different screen feedbacks. And then also, when I am downloading — on *Download feedback* I should be able to have several filters, because right now I can see the submission date, that is okay, the feedback type, which is okay — I think the filters are okay there. But basically we should focus on *Give us feedback*: I should be able to navigate through the app so that as I go it takes screenshots, it takes all the screenshots as I navigate through. So that's what I want us to implement.
