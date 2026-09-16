# HOSSPI Feedback — Implementation Prompts

**Source of truth:** [`HOSSPI-FEEDBACK-16092026-110228.xlsx`](HOSSPI-FEEDBACK-16092026-110228.xlsx) — 20 rows, `FBK0000011`–`FBK0000030`, submitted 2026-09-15 01:33 → 2026-09-16 00:40 (Africa/Kampala).
**Generated:** 2026-09-16 against `main` at `9cb01bb57`, following [`feedback.md`](feedback.md).

20 feedback items → **16 prompts**. 3 merges, 1 partly fixed already, 0 blocked.

## Implementation order

| # | Prompt | Feedback covered | Depends on | Stack |
| :-: | :--- | :--- | :-: | :-: |
| 001 | [Mobile prescription dialog: add more medicines, one tap selects one](001-mobile-prescription-dialog.md) | FBK0000011, FBK0000012 | — | FE |
| 002 | [Facility contacts fall back to tenant contacts](002-facility-contact-fallback.md) | FBK0000013 | — | BE + FE |
| 003 | [Continuous speech-to-text until stopped manually](003-continuous-speech-dictation.md) | FBK0000014 | — | FE |
| 004 | [Feedback download: finish the filters and context capture](004-feedback-export-filters.md) | FBK0000015 | — | BE + FE |
| 005 | [Patient cascade soft delete, restore and permanent delete](005-patient-cascade-delete.md) | FBK0000016 | — | BE + FE |
| 006 | [Facility details on mobile: scrollable header, list-style users](006-facility-details-mobile-layout.md) | FBK0000017 | 002 | FE |
| 007 | [Drug pack scan: native multi-photo capture and OCR](007-drug-pack-multi-photo-capture.md) | FBK0000018 | — | FE |
| 008 | [In-app back navigation](008-in-app-back-navigation.md) | FBK0000019 | — | FE |
| 009 | [HR staff rows: full lifecycle actions, visible demo protection](009-hr-staff-row-actions.md) | FBK0000020 | — | FE (+ BE check) |
| 010 | [HR tables: server pagination and scroll loading](010-hr-table-pagination.md) | FBK0000021 | — | BE + FE |
| 011 | [Roster membership: table picker, staff category on profile, detach](011-roster-staff-membership.md) | FBK0000022, FBK0000024 | 010 | BE + FE |
| 012 | [Fix "Add role" in HR staff details](012-hr-staff-add-role-fix.md) | FBK0000025 | — | BE + FE |
| 013 | [Per-staff module access](013-staff-module-access.md) | FBK0000023 | 012 | BE + FE |
| 014 | [Payroll management tabs as tables](014-payroll-management-tables.md) | FBK0000026 | 010 | FE |
| 015 | [HR Access tab: one roles table with lifecycle actions](015-hr-access-roles-table.md) | FBK0000027 | 010, 012 | FE |
| 016 | [Load performance: dashboard, schedule appointment, start OPD encounter](016-load-performance.md) | FBK0000028, FBK0000029, FBK0000030 | 001–015 (soft) | BE + FE |

## Feedback coverage

Every workbook row is accounted for.

| Feedback ID | Submitted (EAT) | Category | Summary | Disposition | Prompt |
| :--- | :--- | :--- | :--- | :--- | :-: |
| FBK0000011 | 2026-09-15 01:33 | General feedback | No visible way to prescribe more drugs (Android) | Covered — merged with FBK0000012 | 001 |
| FBK0000012 | 2026-09-15 01:36 | General feedback | Choose medicines selects two items for one tap (Android) | Merged into 001 | 001 |
| FBK0000013 | 2026-09-15 08:39 | Improvement | Facility without phone/email should use tenant contacts | Covered | 002 |
| FBK0000014 | 2026-09-15 09:32 | General feedback | Microphone dictation stops by itself on mobile | Covered | 003 |
| FBK0000015 | 2026-09-15 10:13 | Suggestion | Download feedback needs a dialog with comprehensive filters | Partly resolved (`9df8d6b09`, `3dee032b8`); remaining gap covered | 004 |
| FBK0000016 | 2026-09-15 10:28 | Suggestion | Facility admins and above can soft/permanently delete patients with cascade | Covered | 005 |
| FBK0000017 | 2026-09-15 11:43 | Problem | Facility details on mobile: header should scroll, users table should render as a list | Covered | 006 |
| FBK0000018 | 2026-09-15 16:15 | Improvement | Scan & capture should take/upload several photos for OCR (Android) | Covered | 007 |
| FBK0000019 | 2026-09-15 21:15 | Suggestion | Add a back button | Covered | 008 |
| FBK0000020 | 2026-09-15 23:56 | Problem | Some staff rows have no edit/delete; admins need soft + permanent delete | Covered (demo accounts stay protected — see decisions) | 009 |
| FBK0000021 | 2026-09-15 23:58 | General feedback | HR tables lack pagination and scroll loading indicator | Covered | 010 |
| FBK0000022 | 2026-09-16 00:05 | Improvement | Add staff to roster via table search; category should come from staff | Covered — merged with FBK0000024 | 011 |
| FBK0000023 | 2026-09-16 00:13 | Suggestion | Grant/deny module access per staff regardless of roles | Covered | 013 |
| FBK0000024 | 2026-09-16 00:16 | Improvement | "Detach roster" beside "Change roster" in staff details | Merged into 011 | 011 |
| FBK0000025 | 2026-09-16 00:21 | Problem | Adding a role in staff details does nothing; removing works | Covered | 012 |
| FBK0000026 | 2026-09-16 00:25 | General feedback | Payroll salary/deductions/payments tabs look disorganized | Covered | 014 |
| FBK0000027 | 2026-09-16 00:33 | Problem | "Manage staff and roles": drop nested tabs, one roles table with actions | Covered | 015 |
| FBK0000028 | 2026-09-16 00:34 | Problem | Schedule appointment dialog is slow to load | Covered — merged with FBK0000029/30 | 016 |
| FBK0000029 | 2026-09-16 00:39 | Problem | Start OPD encounter is slow to render | Merged into 016 | 016 |
| FBK0000030 | 2026-09-16 00:40 | Problem | Dashboard is slow to load/render | Merged into 016 | 016 |

## Consolidation notes

- **001 (FBK0000011 + FBK0000012):** same person, same Android session, 3 minutes apart, one dialog chain — `ClinicalPrescriptionActionDialog` → `ClinicalPrescriptionCatalogDialog`. Both come from mobile rendering of those shared dialogs.
- **011 (FBK0000022 + FBK0000024):** both change roster membership (`attachRosterStaff` / `detachRosterStaff`, `constraints.attached_staff_meta`). They share the controller methods, realtime refresh and the new staff-category source.
- **016 (FBK0000028 + FBK0000029 + FBK0000030):** same session, same symptom, same production web client, submitted within 6 minutes. They share one profiling baseline and likely root causes: awaits that block first paint, repeated reference-data fetches, heavy first-load payloads.
- **FBK0000015 partly done:** commits `9df8d6b09` and `3dee032b8` (2026-09-16, after the report) shipped `FeedbackDownloadDialog` on the shared `FeedbackRecordsDialog`. It has search, category, submitter type, device type, platform and date range. 004 adds the missing filter dimensions only.
- **FBK0000023 partly in place:** enforcement already exists — step 3 of `resolveEffectiveAccess` reads `user.module_assignments` (`user_module_assignment` table). There is no API or UI to manage it, so 013 builds management only.
- **Separate on purpose:** 009 (staff rows) and 015 (roles table) both ask for an actions column "like tenant setup", but they are different panels (`ManageUsersPanel` vs `ManageRolesPermissionsPanel`).

## Order rationale

Tasks follow submission time, with these dependency exceptions:

- **010 before 011, 014, 015:** 010 sets the paged-table pattern for HR. Later HR tables must follow it and should not rework it.
- **012 (FBK0000025) before 013 (FBK0000023):** both extend the staff-details access area and role/module assignment payloads. Fix identifier resolution before adding module assignment beside it.
- **006 after 002:** both edit `tenant_facility_management_dialogs.dart` (facility details summary/contacts).
- **016 last:** profile after the UI changes above so the baseline measures the shipped screens.

## Decisions

- **FBK0000020 — demo accounts (product owner, 2026-09-16):** keep the 58 seeded demo logins protected (`backend/src/config/demo-users.js`, `backend/src/lib/authorization/demo-user-guard.js`). Show a visible "protected demo account" state instead of an empty actions cell. Every non-demo staff row gets full edit, soft delete, restore and permanent delete.

## Shared workbook context

- **19 of 20 rows:** "Platform Demo", `PLATFORM_ADMIN` (59 permissions incl. `platform:admin`, `tenant:admin`, `facility:admin`, `patient:delete`), tenant/facility DemoCare General Hospital (`TEN-9322E26AFD` / `FAC-FBB67A688F`), plan Pro / `PRO` / `ACTIVE`, environment `production`, locale `en`, light theme, text scale 1, online.
- **FBK0000016:** `FACILITY_ADMIN` (position "Medical Officer", 57 permissions incl. `facility:admin`, `patient:delete`; no `tenant:admin`/`platform:admin`) at FAIRBANKS MEDICAL CENTRE (`TEN0000003` / `FAC0000001`), Pro `TRIAL`, web.
- **Web rows** (FBK0000013, 015, 016, 019–030): Windows, Chrome 152, viewport 1280×585 @1.5x, display 853×480, breakpoint `xl`, `https://app.hosspi.com`.
- **Android rows** (FBK0000011, 012, 014, 017, 018): viewport 393×886 @2.75x, portrait, breakpoint `sm`, app user agent `Dart/3.12 (dart:io)`, no Page URL.
- The prompts leave out user emails, user IDs and IP addresses on purpose. They are in the workbook if needed.

## Observations (not feedback rows)

- **`App Version` is blank in all 20 rows.** `captureFeedbackContext` (`frontend/lib/features/feedback/presentation/feedback_context_capture.dart`) never sets it and `feedbackSubmissionPayload` never sends `app_version`. Folded into 004.
- **Android `Time Zone` is recorded as `EAT`**, an abbreviation rather than an IANA id. Folded into 004.

## Working agreements for every prompt

- **Read first:** `.cursor/index.mdc` (conflict order), `.cursor/mandatories.mdc` (always applies), `.cursor/app-write-up.mdc`, `.cursor/api-contract.mdc`, `.cursor/access/*.mdc`, then `frontend/.cursor/index.mdc` / `backend/.cursor/index.mdc` and the owner files named in each prompt.
- **Mandatories:** localized loading feedback (`AppLoadingIndicator` / `AsyncStateScaffold`, `AppButton.isLoading` for in-place actions); responsive `xs`–`xxl`; instant Riverpod patch plus realtime reconcile; Prisma migration for any schema change; RBAC/ABAC gating in UI **and** API.
- **Copy:** English-first — `frontend/lib/l10n/app_en.arb` then `flutter gen-l10n`; `backend/src/locales/en.json`. Don't bulk-edit other locales.
- **Identifiers:** payloads and URLs use `human_friendly_id`. **Roles are the exception:** `ROL…` friendly ids repeat across tenants and the platform catalog, so assign roles by UUID.
- **Formatting:** don't run `dart format` on existing files. `frontend/` isn't format-clean and it buries the diff. Hand-indent; format only brand-new files. `flutter analyze` is the gate.
- **Git:** never use `git stash` (other sessions share this working tree). Compare with `git show HEAD:<path>`.
- **Baseline test noise:** the frontend suite already had 341 failures at `9d37af135`, and some backend auth/access-admin suites fail at HEAD. Before blaming a change for a failure, run the same test against a `git archive HEAD` copy.
- **Standard gates:** `cd frontend && flutter gen-l10n && flutter analyze && flutter test <touched test paths>`; `cd backend && npm run lint && node scripts/run-jest.js <touched test paths>`; update `backend/docs/api/v1/openapi.yaml` and run `npm run openapi:validate` when the API changes.
