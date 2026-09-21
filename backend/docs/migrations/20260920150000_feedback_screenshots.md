# Feedback screenshots and scope (20260920150000)

## Affected tables

- `feedback` (altered): new `scope` column,
  `ENUM('SCREEN','APP','SCREENS') NOT NULL DEFAULT 'SCREEN'`, with an index.
  It records what a report applies to: the screen it was raised from
  (`SCREEN`), the app as a whole (`APP`), or the screens the reporter picked
  (`SCREENS`). Existing rows take the default, which is what they already
  meant — the feedback's own `route_path` / `route_name` is its screen.
- `feedback_scope_screen` (new): one row per screen a reporter picked, with
  `route_name`, `route_path` and `screen_title` as the app knows them, ordered
  by `sequence`. Only `SCREENS` reports carry rows.
- `feedback_screenshot` (new): metadata for images attached to a report —
  `storage_key`, `content_type`, `byte_size`, `width`, `height`, `caption`,
  the screen the shot was taken on (which may differ from the feedback's own
  screen), `client_context_json` and `captured_at`, ordered by `sequence`.

Both children have `ON DELETE CASCADE` on `feedback_id`.

## Images are not in the database

Only metadata is stored here. The image bytes go to the configured storage
provider (`STORAGE_PROVIDER`: local directory or S3) through
`createStorageService()`, encrypted at rest, under a flat key built by
`buildFeedbackScreenshotKey()`
(`fbshot-<feedback id8>-<sequence>-<random>.<ext>`). Both providers flatten
path separators, so the key has none.

Screenshots of this app can contain patient data. They are served only to
`PLATFORM_OWNER` and `PLATFORM_ADMIN`, streamed through
`GET /api/v1/feedback/:human_friendly_id/screenshots/:screenshot_id`, and
never from `/uploads` or any other public path.

## Deleting

Clearing feedback stays permanent. The service reads the storage keys of the
records it is about to delete, removes the rows (the two children cascade),
and then deletes every image from storage, so no blob outlives its row.
Deleting an image that is already gone is not an error, which makes a retry
safe.

## Deployment

1. Apply migration `20260920150000_feedback_screenshots`
   (`npm run prisma:migrate:deploy`).
2. Deploy application code. `POST /api/v1/feedback` accepts
   `multipart/form-data` with up to 10 images (3 when anonymous) and keeps
   accepting the previous JSON body, so older app builds are unaffected.
3. Verify:
   - `POST /api/v1/feedback` as `multipart/form-data` with `screenshots[]`
     returns 201 and `screenshot_count` matching what was sent.
   - `GET /api/v1/feedback/:id/screenshots` returns the metadata for a
     platform admin and 403 for a tenant admin.
   - `GET /api/v1/feedback/export` returns
     `HOSSPI-FEEDBACK-DDMMYYYY-HHmmss.zip` holding the workbook,
     `screenshots/FBK…jpg` and `feedback-prompts-generator.md`.
   - `DELETE /api/v1/feedback` removes the rows and their images; the storage
     directory (or bucket prefix) holds no `fbshot-…` file for them.

## Recovery

Forward-only. Deleting feedback from the app is permanent, so download the
archive first when a copy may be needed. Removing the feature needs no data
migration: add `rollback_20260920150000_feedback_screenshots` dropping
`feedback_screenshot`, `feedback_scope_screen` and `feedback`.`scope` if
required. Dropping `feedback_screenshot` leaves the stored images orphaned in
the provider; delete the `fbshot-*` objects with it.
