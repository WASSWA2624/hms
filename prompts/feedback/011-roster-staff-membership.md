# 011 — Roster Membership: Table Picker, Staff Category on Profile, Detach

**Feedback:** FBK0000022, FBK0000024 · **Depends on:** 010 · **Stack:** backend + frontend
**Index:** [000-index.md](000-index.md) (working agreements apply)

## Objective

Make joining and leaving a roster simple and correct:

- **Add staff to roster** uses a searchable, paged staff table (multi-select) instead of searchable selects, and doesn't ask for a staff category.
- **Staff category** becomes a property of the staff member, captured on the staff profile.
- **Staff details** offers **Detach roster** next to **Change roster**. It removes the staff member from the roster and cancels upcoming shifts, and keeps worked history.

## Feedback covered

| Field | FBK0000022 | FBK0000024 |
| :--- | :--- | :--- |
| Submitted (EAT) | 2026-09-16 00:05:32 | 2026-09-16 00:16:53 |
| Category | Improvement | Improvement |
| Feedback (verbatim) | "When adding a staff to a roster template, the add staff dialog should use the app_list_table component to search the staff members isnted of the searcheable select components. No need to select the staff category since this must be a property of the staff." | "On the staff details dialog, when a staff has a roster, in addition to the \"Change roster\" button, add a detach roster button which detaches the roster from the staff." |
| Screen / route | `hr` · `/hr?section=shift-roster&queue=ROSTER_DRAFTS` | `hr` · `/hr?section=staff` |
| Reporter / tenant / plan | Platform Administrator · `PLATFORM_ADMIN` · DemoCare General Hospital · Pro `ACTIVE` | same |
| Device | Web, Windows Chrome 152, Desktop 1280×585 @1.5x, `xl` · production · light · `en` | same |

## Current behavior (verified at `9cb01bb57`)

- **Add staff dialog.** In the roster detail dialog, `_addStaff` (`frontend/lib/features/hr/presentation/widgets/hr_roster_detail_dialog.dart`) opens `showAppWorkspaceMutationDialog` with:
  - an `AppSelectField<String>.searchable` over `referenceData.staffProfiles` (the reference payload caps users at `take: 200` in `hr-workspace.service.js`),
  - an `AppSelectField` staff category defaulting to `FULL_TIME`,
  - then `attachRosterStaff(rosterId, staffProfileId, staffCategory)`. One staff member per dialog.
- **Where category lives today.** Backend `attachRosterStaff` (`backend/src/modules/roster/services/roster.service.js`) stores the category only in roster JSON: `constraints.attached_staff_meta[{staff_profile_id, staff_category}]`. The enum `FULL_TIME | PART_TIME | LOCUM | SPECIALIST | CONTRACT | OTHER` is in `backend/src/modules/roster/schemas/roster.schema.js`. `staff_profile` (`backend/prisma/schema.prisma`) has **no** category field.
- **Category consumers.** Roster staff rows, filters and prints read the category from meta (`_RosterStaffRow.staffCategory`, `_staffCategoryOptions`, the roster print HTML).
- **Detach API exists.** `DELETE /api/v1/rosters/:id/staff/:staffProfileId` → `detachRosterStaff`. It soft-deletes **every** `shift_assignment` of that staff member on the roster, **including past, worked shifts**, one by one outside a transaction, then rewrites `attached_staff_ids/meta`. The frontend `HrWorkspaceController.detachRosterStaff` is used only from the roster detail dialog (`_removeStaff`).
- **Staff details roster section.** `hr_staff_details_body.dart` shows one header action whose label comes from `resolveStaffRosterActionKind` (`add | change | update`, `hr_staff_detail_helpers.dart`) via `_primaryRosterId(detail.shiftAssignments)`. There is no detach.

## Required behavior

### Staff category on the staff profile

1. **Schema.** Add `staff_category` to `staff_profile` (Prisma enum with the same six values, nullable, indexed) through a migration.
   - Backfill it from the most recent `attached_staff_meta` entry per staff member where one exists. Otherwise leave it null.
   - Document the migration and rollback under `backend/docs/migrations/`.
2. **Capture and display.**
   - Staff onboarding/edit (`hr_staff_onboarding_dialog.dart` and the staff profile API) captures `staff_category`. It's optional, with localized labels.
   - Staff details overview shows it.
   - HR staff lists and filters may expose it.
3. **Rosters read it from the profile.**
   - Rosters read category from the staff profile; `attached_staff_meta.staff_category` is no longer written.
   - Attach payloads stop accepting `staff_category`. Accept-and-ignore for one release if old clients exist, and note it in OpenAPI.
   - Roster rows, filters and prints use the profile value ("Not set" when null).

### Add staff to roster (FBK0000022)

4. **Picker dialog.** Replace the select-based dialog with a picker dialog built on `AppListTable`:
   - Server-paged staff search following **010** (infinite scroll, debounced search).
   - Columns: name, staff number, position, department, staff category, current roster/conflict hint.
   - Multi-select checkboxes. Staff already attached are excluded or shown as attached and disabled.
   - Filters: department, position, category.
   - Mobile list rows.
   - Confirm label "Add N staff".
5. **Batch attach endpoint.** Add `POST /api/v1/rosters/:id/staff` accepting `staff_profile_ids[]` (`human_friendly_id`s).
   - It runs the existing schedule-conflict check per staff member, attaches all that pass in one transaction, and returns per-staff results (attached / conflict with reason).
   - The dialog reports partial results clearly and keeps failed rows selectable.
   - Keep the single attach route working for other callers, or migrate them.

### Detach roster from staff details (FBK0000024)

6. **The button.**
   - In the staff details roster section, when the staff member has a roster, show **Detach roster** beside **Change roster**, gated by the same requirement as roster write (`HrHumanResourcesAtomPermissions.nestedRosterWrite`), and hidden for separated staff.
   - If the staff member belongs to several rosters, the action lets the user choose which roster(s) to detach.
7. **Confirmation.** Destructive confirm dialog naming the roster and period, and stating what happens: upcoming shifts removed, past shifts kept.
8. **Fix detach semantics server-side.**
   - In one `prisma.$transaction`, soft-delete only assignments whose shift hasn't started yet (`shift.start_time > now`). Keep started/past assignments for attendance and payroll.
   - Update `attached_staff_ids/meta`.
   - Enforce tenant/facility scope when resolving the roster and staff member.
   - Refuse detaching from `PUBLISHED` rosters only if policy requires approval. Otherwise allow it and audit it.
   - Audit `DETACH_STAFF` with counts removed/kept, and publish the HR/roster realtime event after commit.
9. **Instant UI.** Staff details and roster detail (if open) update immediately from the response: the roster section shows "Add roster", and the calendar preview drops future shifts. Other sessions reconcile via `RealtimeEventGroups.hr`.

## Implementation constraints

- **Migration and layering.** Commit the migration with the schema (`.cursor/mandatories.mdc`, `backend/.cursor/prisma.mdc`). Repositories own Prisma access (`architecture.mdc`). Zod schemas for new bodies (`validation.mdc`). OpenAPI updated.
- **Roster authority.** Roster write/publish/approve permissions (`roster:*`, `hr:write`) and scoped managers only inside their scope (`backend/.cursor/auth-security.mdc` → Roles).
- **Shared UI and states.** Shared components only; `AppButton.isLoading` for confirm; localized copy; responsive picker (`frontend/.cursor/ui-workspace.mdc`, `ui-patterns.mdc`).
- **Identifiers.** `human_friendly_id` in all payloads (`.cursor/api-contract.mdc`).

## Verification

- **Backend tests** (`backend/src/tests/modules/roster/`, `backend/src/tests/modules/staff-profile/`):
  - The migration backfill logic; the profile accepts and returns `staff_category`.
  - Batch attach: all succeed, partial conflicts, already attached, scope violation.
  - Detach keeps past assignments, removes future ones, is atomic, and emits audit plus a realtime event.
  - Attach no longer writes category meta.
- **Frontend tests** (`frontend/test/features/hr/presentation/widgets/`):
  - The picker pages and searches, multi-selects, and reports partial results.
  - No category field in the add dialog; roster rows show the profile category.
  - Detach is visible only with a roster plus permission; confirming patches staff details.
  - Multi-roster selection works.
- **Run:** `cd backend && npm run prisma:migrate && npm run lint && node scripts/run-jest.js src/tests/modules/roster src/tests/modules/staff-profile && npm run openapi:validate`; `cd frontend && flutter gen-l10n && flutter analyze && flutter test test/features/hr/`.
- **Manual:**
  1. `/hr?section=shift-roster&queue=ROSTER_DRAFTS` → open a draft → Add staff → search, select 3 → add → categories come from profiles.
  2. `/hr?section=staff` → staff member with a roster → Detach roster → upcoming shifts gone, past shifts visible in history.
  3. Phone width.

## Dependencies

- **010:** the paged table pattern used by the picker.
