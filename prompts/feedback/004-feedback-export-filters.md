# 004 — Feedback Download: Finish the Filters and Context Capture

**Feedback:** FBK0000015 (partly resolved) · **Depends on:** — · **Stack:** backend + frontend
**Index:** [000-index.md](000-index.md) (working agreements apply)

## Objective

Complete what FBK0000015 asked for: platform owners/admins can narrow "Download feedback" to exactly the rows they need, using every useful dimension the workbook carries. Then make sure new feedback records actually carry the app version and a proper IANA time zone, so the next workbook is complete.

## Feedback covered

| Field | Value |
| :--- | :--- |
| Feedback ID | FBK0000015 |
| Submitted (EAT) | 2026-09-15 10:13:10 |
| Category | Suggestion |
| Feedback (verbatim) | "The download feedback button should open a dialog similar to the clear feedback dialog where one can filter out what to download. The filters should be extremely comprehensive." |
| Reporter | Platform Administrator · `PLATFORM_ADMIN` · DemoCare General Hospital · Pro `ACTIVE` |
| Screen / route | `home` · `/` (floating feedback control) |
| Device | Web, Windows Chrome 152, Desktop 1280×585 @1.5x, `xl` · production · light · `en` |

## Already resolved — do not rebuild

Commits `9df8d6b09`, `3807c6da8` and `3dee032b8` (2026-09-16, after this report) shipped:

- **Dialog:** `FeedbackDownloadDialog` (`frontend/lib/features/feedback/presentation/widgets/feedback_download_dialog.dart`), built on the shared picker `FeedbackRecordsDialog` (`feedback_records_dialog.dart`) that "Clear feedback" also uses.
- **Existing filters:** free-text search, category, submitter type, device type, platform, and submitted date range. Selecting nothing exports every match.
- **Backend:** `feedbackFiltersSchema` (`backend/src/modules/feedback/schemas/feedback.schema.js`), `buildActiveFeedbackWhere` (`backend/src/modules/feedback/repositories/feedback.repository.js`), `GET|POST /api/v1/feedback/export`, workbook builder `backend/src/lib/feedback/feedback-export.js`.

The dialog part is done. Only the "extremely comprehensive" filter depth and the data-quality gaps below are left.

## Remaining gaps (verified at `9cb01bb57`)

- **Filter dimensions:** the filters don't cover the columns the workbook exports — tenant, facility, reporter role, subscription plan/tier/status, screen/route name, environment, app version, locale, breakpoint, theme, connectivity, orientation.
- **Hard-coded platform choices:** they come from a fixed list (`feedbackPlatforms`), not from stored values.
- **App version never captured:** `captureFeedbackContext` (`frontend/lib/features/feedback/presentation/feedback_context_capture.dart`) never sets it and `feedbackSubmissionPayload` (`frontend/lib/features/feedback/data/repositories/feedback_repository_impl.dart`) never sends `app_version`. All 20 rows in `HOSSPI-FEEDBACK-16092026-110228.xlsx` have a blank App Version.
- **Android time zone is an abbreviation:** it is saved as `EAT` because `readClientTimeZoneId()` returns null there and the code falls back to `DateTime.timeZoneName`.

## Required behavior

1. **New server-side filters,** shared by list, summary, export and delete (the same `feedbackFiltersSchema`):
   - `tenant_id[]`, `facility_id[]` (public `human_friendly_id`s, resolved server-side)
   - `role[]` (matches any role in `user_roles_json`)
   - `plan_tier[]`, `subscription_status[]`
   - `route_name[]`, `app_environment[]`, `app_version[]`, `locale[]`
   - `breakpoint[]`, `theme[]`, `connectivity[]`, `orientation[]` (read from `client_context_json`)
   - `has_user` (signed-in vs anonymous is already `submitter_type`; don't duplicate it)

   Multi-value filters follow the existing `toFilterList` convention (`A,B` query or JSON array). Unknown keys are rejected.
2. **Facets endpoint.** Add `GET /api/v1/feedback/facets`, accepting the same filters, that returns distinct values with counts for each filterable dimension, including platform. Scope it like the list endpoint: platform owner/admin only (`FEEDBACK_ADMIN_ROLES`). The UI builds its filter choices from it. Stop hard-coding platform choices, and hide dimensions with no values.
3. **MySQL JSON queries.** Keep them efficient: column filters use indexed columns. Add indexes for newly filtered scalar columns (`tenant_id` already has one; add `route_name`, `app_environment`, `app_version`, `subscription_tier_code` as needed) through a Prisma migration. JSON-path filters must be parameterized. If raw SQL is needed, justify it (`backend/.cursor/prisma.mdc`).
4. **Filter panel UI.** In `FeedbackRecordsDialog`, group filters into sections — Report (category, submitter, date), Who (tenant, facility, role, plan tier, subscription status), Where (route/screen, environment, app version), Device (platform, device type, breakpoint, orientation, theme, locale, connectivity). Use the shared `AppSearchBar` advanced-filter groups. Active filter count, reset, and "N records match" must stay accurate. Both Download and Clear inherit the new filters, and deleting "all matching" honors them.
5. **Tenant/facility pickers:** searchable choices, labeled by name with the `human_friendly_id` as caption.
6. **Context capture.**
   - Send `app_version` as `version+build` from the running build — use the build-time config or `package_info_plus` if approved (`frontend/.cursor/dependencies.mdc`; prefer a `--dart-define` that the deploy scripts already set, if one exists).
   - Send a real IANA time zone id on Android/iOS/desktop. Fall back to the UTC offset string (`UTC+03:00`), never an abbreviation.
   - Keep existing credential redaction.
7. **Export fidelity.** The workbook still lists every column. Export and delete behave identically for the same filter set.

## Implementation constraints

- **Access.** Platform owner/admin only, enforced in routes and services. Feedback PII (emails, IPs) never leaves that audience (`backend/.cursor/auth-security.mdc`, `compliance.mdc`). Export and delete create audit evidence.
- **Validation.** Zod for every new query/body key (`backend/.cursor/validation.mdc`). Paginated lists stay paginated (`backend/.cursor/api.mdc`). Update `backend/docs/api/v1/openapi.yaml`.
- **Frontend.** Shared search/filter components only (`frontend/.cursor/ui-patterns.mdc`). Localize every filter label and choice (raw values like `xl` or `landscape` need readable labels). Loading uses `AppLoadingIndicator` with a message.
- **Migrations.** Index-only migration plus a doc under `backend/docs/migrations/` (pattern: `20260914120000_feedback.md`).

## Verification

- **Backend** (`backend/src/tests/modules/feedback/`, `backend/src/tests/lib/feedback/`):
  - Schema tests for every new key.
  - Repository/service tests: each filter narrows list/summary/export/delete identically, JSON-path filters work, facets return counts under active filters, non-admins get 403.
- **Frontend** (`frontend/test/features/feedback/`):
  - Filter groups render from facets; applying tenant + route + breakpoint filters sends the right query.
  - Download and Clear share the filters.
  - The payload includes `app_version` and an IANA or offset time zone.
- **Run:** `cd backend && npm run prisma:migrate && npm run lint && node scripts/run-jest.js src/tests/modules/feedback src/tests/lib/feedback && npm run openapi:validate`; `cd frontend && flutter gen-l10n && flutter analyze && flutter test test/features/feedback/`.
- **Manual:**
  - Submit feedback from web and Android → the new rows show App Version and a proper time zone.
  - Download with tenant = DemoCare, route = `hr`, breakpoint = `xl` → the workbook contains only matching rows.
  - Clear with the same filters previews the same count.

## Dependencies

None.
