# Give us feedback: screenshots, feedback scope, and a self-describing download archive

**Source:** direct request (dictated; verbatim transcript at the end) · **Stack:** frontend + backend
**Verified against:** `main` at `a5347239c`
**House style:** [`prompts/feedback/feedback.md`](feedback/feedback.md) working agreements apply

## Objective

Three changes to the feedback flow:

1. **Screenshots.** The screen the report was raised from is captured automatically, and the reporter can then walk through the app capturing more screens without losing the feedback they have already typed.
2. **Scope.** The reporter says what the feedback applies to — this screen, the whole app, or a set of screens they pick.
3. **A usable download.** "Download feedback" returns an archive holding the workbook, the screenshots, and a prompts generator that turns the archive into implementation prompts for this repository.

The existing "Download feedback" **filters are not part of this work** — they are already sufficient (search, category, submitter, device, platform, date range, tenant, facility, role, plan, route, environment, app version, locale, breakpoint, theme, connectivity, orientation).

## What exists today — do not rebuild

- **Floating control:** `AppFeedbackHost` (`frontend/lib/features/feedback/presentation/widgets/app_feedback_host.dart`) mounts above every route, dialog and sheet, is draggable, and hides itself while one of its own dialogs is open.
- **Menu:** platform owner/admin get *Give us feedback*, *Download feedback*, *Clear feedback* (`_FeedbackMenuAction`); everyone else gets the submit flow only (`canManageFeedback`, `feedback_access.dart`). The API enforces the same roles (`FEEDBACK_ADMIN_ROLES`).
- **Submit dialog:** `FeedbackSubmitDialog` (`feedback_submit_dialog.dart`) — category checkboxes plus a details field, sized to content, translucent (`_surfaceOpacity = 0.86`) so the screen behind stays readable. It holds the draft in its own `State`, so closing it loses everything typed.
- **Context capture:** `_openFeedbackDialog` calls `captureFeedbackContext` (`feedback_context_capture.dart`) before opening the dialog — route path/name, page URL, screen title, platform, device type, viewport/display, locale, time zone, breakpoint, theme, text scale, connectivity, orientation.
- **Submit API:** `POST /api/v1/feedback` — JSON, optional authentication (works signed out and on sign-in screens), rate limited (`rateLimitConfig.endpoints.feedback`).
- **Export:** `GET|POST /api/v1/feedback/export` → `feedback-export.js` builds a single-sheet `HOSSPI-FEEDBACK-DDMMYYYY-HHmmss.xlsx` with ExcelJS; `FeedbackDownloadDialog` and `FeedbackRecordsDialog` pick the rows; `appListTableSaveExportFile` saves the bytes.
- **Model:** `feedback` (`backend/prisma/schema.prisma`) stores context snapshots only. **There is no attachment table, no scope column, no upload route and no blob storage for feedback yet** — all of that is new.
- **Reusable pieces:** widget-to-PNG capture via `RepaintBoundary` plus an off-screen overlay (`frontend/lib/shared/reporting/module_reporting_chart_capture.dart`); crop dialog `AppImageCropDialog`; upload/preview components `app_image_upload_field.dart`, `app_file_upload_panel.dart`; the screen catalogue `AppRoutes`/`AppRouteData` (`frontend/lib/app/router/app_routes.dart`) with `RouteAccessCatalog` for what a user may reach; multi-select picker pattern `app_role_selection_table_dialog.dart`; backend `createStorageService()` (`backend/src/lib/storage/factory.js` — local or S3 by env, encrypted at rest) and `multer`, already used by the workspace import routes.

## Required behavior

### 1. Automatic first shot

Tapping *Give us feedback* captures the app frame **as it was when the control was tapped**, before the dialog opens, and attaches it as the first screenshot. The floating control itself must not appear in the image. The shot is removable like any other. The feedback row's own route context stays the screen the flow started on.

### 2. Capture more screens without losing the draft

- Move the draft (category, message, scope, shots) out of `FeedbackSubmitDialog` into a host-owned, session-scoped controller (Riverpod, e.g. `feedbackDraftProvider`) so it survives the dialog closing, navigation and rotation. Clear it on submit, on explicit discard, and on sign-out.
- A **"Capture another screen"** action puts the flow into capture mode: the dialog closes, the draft is kept, and the floating control becomes a capture control offering *Capture*, *Back to feedback* and *Cancel*.
- **Capture mode stays on until the reporter leaves it.** One tap of *Capture* takes one shot and returns to the app, still in capture mode, so the reporter can navigate and shoot repeatedly — several screens in a row, or several shots of the same screen (mid-scroll, a menu open, an error state). Each capture confirms itself briefly and shows a running count ("3 of 10"); the count is the only thing that ends the run, and it says so when the cap is reached.
- Reopening the dialog (or *Back to feedback*) restores the message, the category, the scope and every shot exactly as they were.
- While in capture mode, make the state obvious — the control is labelled, and a dismissible hint says the draft is being kept.

### 3. Capture the dialog itself, or not

A toggle on the capture action — *Include the feedback dialog in this shot* — default **off**. Off captures the app behind the dialog, with the dialog and the floating control excluded; on captures what is on screen, dialog included. The automatic first shot follows the same rule and never includes the control.

### 4. What the feedback applies to

A required scope field in the dialog, directly under the category:

- **This screen** (default) — the screen the flow started on, as captured in the feedback context.
- **The whole app** — not confined to one screen.
- **Selected screens** — opens a searchable multi-select of screens built from `AppRoutes`/`AppRouteData`, labelled with the same names the navigation uses, filtered to what this user can actually reach (`RouteAccessCatalog`, `appAccessPolicyProvider`); signed-out reporters see only public routes. One or more may be picked, and the picker shows the route path as a caption so two similarly named screens are distinguishable.

Capturing a screen in capture mode adds that screen to the selection and switches the scope to *Selected screens* (removable, and switching back to *This screen* or *The whole app* keeps the shots). Store the choice as a `scope` enum on `feedback` (`SCREEN`, `APP`, `SCREENS`) plus a child table `feedback_scope_screen` (`feedback_id`, `sequence`, `route_name`, `route_path`, `screen_title`) so admins can find every report touching a screen. Add an `applies_to[]` filter and an `applies_to_route[]` filter to the shared feedback filter schema — leave the existing `route_name[]` filter's meaning unchanged.

### 5. Managing the shots

In the dialog: a horizontally scrollable thumbnail strip holding every shot, ordered by capture time and numbered, each labelled with its screen name. Several shots of the same screen are normal — do not deduplicate them, and keep them distinguishable by number and capture time. Per shot — preview full size, optional crop (reuse `AppImageCropDialog`, the reporter's way of cropping out anything they don't want to send), optional short caption, remove. Each shot stores its own capture context (route path, route name, screen title, viewport, orientation, theme, captured-at), not the dialog's. The strip must stay usable at `xs` width with the cap reached.

### 6. Limits and failure handling

- Up to **10** shots per submission (**3** when signed out), from any mix of screens; longest edge downscaled to **1600 px**; encoded as JPEG (quality ~80) with the `image` package; hard caps of **2 MB** per file and **12 MB** per request, enforced on the client *and* the server. Put the cap in one named constant per side (`feedbackMaxScreenshots` / `FEEDBACK_MAX_SCREENSHOTS`) so it is one edit to change, and drive the UI's counter and disabled state from it rather than repeating the number.
- Capture is best-effort: if `RenderRepaintBoundary.toImage` fails (notably on web renderers where it can throw), show a plain message, drop that shot, and let the feedback be submitted without it. **Never block submitting feedback because a screenshot failed.**
- Submitting with no shots stays valid and must not get slower.

### 7. Transport and storage

- Accept `multipart/form-data` on the existing `POST /api/v1/feedback` (multer, memory storage, file-count and size limits, MIME sniffed from content rather than extension — PNG, JPEG and WebP only). Keep the current JSON body working unchanged so older builds keep submitting.
- Persist blobs through `createStorageService()` under `feedback/<feedback_id>/<sequence>-<uuid>.<ext>`; never write them into the database row, and never serve them from a public path.
- New Prisma model `feedback_screenshot`: `id`, `feedback_id` (FK, cascade), `sequence`, `storage_key`, `content_type`, `byte_size`, `width`, `height`, `caption`, `route_path`, `route_name`, `screen_title`, `client_context_json`, `captured_at`, `created_at`. One migration covers this, `feedback.scope` and `feedback_scope_screen`, with a note under `backend/docs/migrations/` (pattern: `20260914120000_feedback.md`).
- Saving is resilient, not all-or-nothing: if a blob write fails, the feedback text still saves and the response says which shots were dropped.

### 8. Deleting feedback deletes its screenshots

Deleting feedback — a single record, a selection, or "all matching" through *Clear feedback* — permanently deletes the stored image objects along with the row, in the same operation. Feedback deletion is already permanent, so this must leave nothing behind: no blobs in local storage or S3, no `feedback_screenshot` or `feedback_scope_screen` rows, no empty `feedback/<feedback_id>/` prefix. If a blob delete fails, the operation reports it and retries are safe (deleting an already-deleted object is not an error). Cover orphan-free deletion with a test that asserts the storage service was asked to remove every key. The delete count reported to the admin stays the count of feedback records, not of files.

### 9. Reviewing them in the app

- `GET /api/v1/feedback/:human_friendly_id/screenshots` (metadata) and `GET /api/v1/feedback/:human_friendly_id/screenshots/:screenshot_id` (streamed bytes), both platform owner/admin only, both audited. No signed public URLs.
- `FeedbackRecordsDialog` shows a shot count and the scope per row, and opens a viewer for the images, so the download is not the only way to see a screenshot.

### 10. Download returns an archive

*Download feedback* returns **`HOSSPI-FEEDBACK-DDMMYYYY-HHmmss.zip`**, not a bare workbook, holding:

| Path | Contents |
| :--- | :--- |
| `HOSSPI-FEEDBACK-DDMMYYYY-HHmmss.xlsx` | The workbook, same stamp as the archive. |
| `  └ Feedback` | Today's sheet, plus `Applies To`, `Screens` and `Screenshots` (count) columns. |
| `  └ Screenshots` | One row per image: `Feedback ID` (`FBK0000011`, `FBK0000011-2`, …), captured time, screen, route, caption, file name. |
| `  └ Export Details` | The filters used, record and image counts, and the admin's time zone. |
| `screenshots/FBK0000011.jpg` | Full-size images, `-2`, `-3` … for further shots of the same record. |
| `feedback-prompts-generator.md` | [`backend/src/lib/feedback/feedback-prompts-generator.md`](../backend/src/lib/feedback/feedback-prompts-generator.md), shipped verbatim. |

- The generator file already exists in this repository — ship it as it is, do not rewrite it at export time. Confirm the deploy packaging copies non-JS files under `backend/src/lib/` (`deploy/`), and load it with a path resolved from the module, not the working directory.
- Both `GET` and `POST /api/v1/feedback/export` return the archive, with `Content-Type: application/zip` and the `.zip` file name; the workbook is no longer returned on its own. Stream it rather than buffering every image, and keep the existing filters, row selection and time-zone handling exactly as they are.
- The frontend saves `.zip` bytes through the existing save path; check `appListTableSaveExportFile` handles the extension and MIME on web, Android and desktop.
- Exports with no screenshots still produce an archive — workbook plus generator, no `screenshots/` folder.
- Adding a ZIP library to the backend is a dependency decision (`.cursor` dependency rules): prefer `archiver` for streaming; say so in the PR.

## Implementation constraints

- **Privacy.** Screenshots of this app can contain patient data — treat them as PHI (`backend/.cursor/compliance.mdc`, `auth-security.mdc`): encrypted at rest through the storage service, readable only by platform owner/admin, audit evidence on view, export and delete, never logged, never in URLs or query strings. Show a one-line notice in the dialog that screenshots may contain patient data, and keep the existing credential scrubbing for route and URL context.
- **Anonymous submissions** keep working (sign-in screens, lapsed sessions) with the same caps and rate limit; they must not become a way to upload arbitrary files.
- **Backend:** Zod for every new field, including the multipart text parts and the scope list (`backend/.cursor/validation.mdc`); documented in `backend/docs/api/v1/openapi.yaml` (`api.mdc`, `documentation.mdc`); storage access only through the factory (`storage.mdc`); rate limits reviewed for the larger payload (`rate-limiting.mdc`).
- **Frontend:** shared components only — `AppDialog`, `AppButton`, `AppSearchBar`, `AppLoadingIndicator` with a message, `AppImageCropDialog` (`frontend/.cursor/components.mdc`, `design-system.mdc`). Every new label, tooltip, hint and error localized in `app_en.arb` (`localization_i18n.mdc`); capture, crop and the screen picker must work with touch, mouse and keyboard (`multi_platform_input.mdc`, `accessibility.mdc`). No new dependency without checking `dependencies.mdc`.
- **Performance:** encode off the UI thread where the platform allows; downscale before upload; never hold more than the capped shots in memory; stream the archive.

## Verification

- **Backend** (`backend/src/tests/modules/feedback/`, `backend/src/tests/lib/feedback/`): multipart submit stores rows, scope screens and blobs; JSON submit still works; oversized, too many, and non-image uploads are rejected; anonymous caps enforced; screenshot fetch is 403 for non-admins; `applies_to` and `applies_to_route` filters narrow list, summary, export and delete identically; deleting feedback (by id and all-matching) removes every blob and child row; the archive contains the workbook, the images named as specified, and the generator file byte-for-byte.
- **Frontend** (`frontend/test/features/feedback/`): the first shot is attached automatically and excludes the launcher; capture mode survives repeated captures — several screens in a row plus two shots of the same screen all land in the strip, in order, with the counter tracking them and the cap disabling further capture; entering capture mode, navigating, capturing and reopening preserves message, category, scope and shots; the include-dialog toggle changes what is captured; the screen picker lists only reachable screens and capturing a screen adds it to the selection; remove and crop update the draft; a failed capture surfaces a message and still allows submit; the repository sends multipart with per-shot context and the scope payload; the download saves a `.zip`.
- **Run:** `cd backend && npm run prisma:migrate && npm run lint && node scripts/run-jest.js src/tests/modules/feedback src/tests/lib/feedback && npm run openapi:validate`; `cd frontend && flutter gen-l10n && flutter analyze && flutter test test/features/feedback/`.
- **Manual:** on web and Android — raise feedback from an OPD encounter, confirm the automatic shot; set the scope to two picked screens; capture two more screens, one with the dialog included; submit; download and confirm the archive holds the workbook with `Applies To` and `Screens` filled in, exactly those images, and the generator; clear that record and confirm the images are gone from storage.

## Decisions to confirm before building

1. **Retention.** Screenshots live and die with the feedback row; no separate retention window is assumed.
2. **Caps.** 10 shots signed in, 3 signed out, 2 MB each, 12 MB per submission. Raise them if 10 proves tight in use — it is one constant per side.
3. **ZIP library.** `archiver` is assumed for streaming; `jszip` is the buffered alternative.

## Source (verbatim request)

> Let us update the feedback flow or functionality as follows. Currently, when I click the feedback button, it opens the feedback context menu, which is okay because I am able to give feedback. But I want us to update it such that when I'm on the platform admin account — it currently gives me three menus, that is the *Give us feedback* menu, *Download feedback* and then *Clear feedback*. When I click *Give us feedback*, that dialogue is okay, but I want us to advance it in such a way that I am able to take screenshots. These screenshots should be such that it automatically takes the screenshot of the previous screen where the *Give us feedback* dialogue was triggered from — that should be captured by default. Then I should have buttons where I can take screenshots, I can navigate through the app and take screenshots from different parts of the app, of the device, of the screen; I can navigate to another screen in the app and take screenshots. I can take screenshots including the *Give us feedback* dialogue itself, but I may also exclude it. So I should be able to give different screen feedbacks. And then also, when I am downloading — on *Download feedback* I should be able to have several filters, because right now I can see the submission date, that is okay, the feedback type, which is okay — I think the filters are okay there. But basically we should focus on *Give us feedback*: I should be able to navigate through the app so that as I go it takes screenshots, it takes all the screenshots as I navigate through. So that's what I want us to implement.

> In addition, there should be a way to select the context to which the feedback applies. For example, entire app, or selected screens (allow to select one or more). The download should be an archive which contains the excel, the screenshots and a markdown prompt generator similar to the one shown [in the Tapture generator] but tailored to the HOSSPI HMS.

> Deleting the feedbacks also deletes the associated screenshots.

> One should be able to capture multiple screenshots.
