# 009 — HR Staff Rows: Full Lifecycle Actions, Visible Demo Protection

**Feedback:** FBK0000020 · **Depends on:** — · **Stack:** frontend (+ backend verification)
**Index:** [000-index.md](000-index.md) (working agreements apply)

## Objective

Every row in the HR staff directory (and the identical Setup → Users list) shows exactly the lifecycle actions the viewer may perform: Edit, Delete (soft), Restore, Permanently delete. When a row can't be changed, the row says why instead of showing an empty actions cell.

**Product decision (2026-09-16):** seeded demo login accounts stay protected. They get a visible "Protected demo account" state, not actions.

## Feedback covered

| Field | Value |
| :--- | :--- |
| Feedback ID | FBK0000020 |
| Submitted (EAT) | 2026-09-15 23:56:30 |
| Category | Problem |
| Feedback (verbatim) | "Some staff members have no delete and edit action buttons. Permitted admins should perform soft and permenent delete too," |
| Reporter | Platform Administrator · `PLATFORM_ADMIN` (59 permissions incl. `platform:admin`, `tenant:admin`, `facility:admin`, `hr:write`) |
| Tenant / facility / plan | DemoCare General Hospital (`TEN-9322E26AFD` / `FAC-FBB67A688F`) · Pro `ACTIVE` |
| Screen / route | `hr` · `/hr` (Staff section, the default) |
| Device | Web, Windows Chrome 152, Desktop 1280×585 @1.5x, `xl` · production · light · `en` |

## Current behavior (verified at `9cb01bb57`)

- **Shared list.** HR → Staff renders `ManageUsersPanel` (`frontend/lib/features/access_admin/presentation/widgets/access_admin_management_dialogs.dart`), the same panel as `/admin/setup?section=users` (`HrWorkspacePage._buildTabBody`, `HrDeskSection.staffDirectory`).
- **Row action rules** in the `actions` column `cellBuilder`:
  - **Active rows:**
    - **Edit** if `_canMutateUser` = `!isDeleted && !isDemo`. There is **no write-permission check**, so read-only viewers see Edit.
    - **Delete** if `canSoftDeleteAccessAdminUser`: not demo, `canWriteAccessAdmin(policy)`, and (`canManagePlatformAdmins()` or `!isSystemCritical`).
  - **Deleted rows:** nothing at all for demo accounts. Otherwise:
    - **Restore** is always shown. There is **no write check** in the cell, and `_confirmRestoreUser` checks only demo.
    - **Permanently delete** if `_canPermanentlyDeleteUser`: `canWrite && isDeleted && !isDemo && (canManageProtected || !isSystemCritical)`.
- **Why rows are empty.** `isDemo` comes from the backend (`is_demo` via `isDemoUser`, `backend/src/config/demo-users.js`, 58 curated emails). DemoCare General Hospital is the demo tenant, so most curated staff rows show no actions. The backend blocks mutations for these accounts in `backend/src/lib/authorization/demo-user-guard.js` (`errors.user.demo_protected`, 403). System-critical users also show no Delete for non-platform admins.
- **Existing copy.** The user detail dialog already explains protection (`accessAdminUserDetailDemoAccountTitle` banner around the `item.isDemo || item.isSystemCritical` block); the list does not.

## Required behavior

1. **Action matrix.** Build one tested function for row actions (`accessAdminUserRowActions(user, policy, workspaceCanWrite)` or similar, in `frontend/lib/features/access_admin/presentation/access_admin_access.dart`). It returns the allowed actions **and** a protection reason. Use it in the table cells, mobile list rows, the user detail dialog and the HR staff detail dialog, so they never disagree.
   - **Edit / Delete:** `canWriteAccessAdmin(policy)` (elevated ∪ access-admin write ∪ `hr:write`), plus not demo, plus the hierarchy rule: system-critical users only when `canManagePlatformAdmins()`.
   - **Restore / Permanently delete:** row is deleted, plus the same write and hierarchy rules, plus not demo.
   - **Read-only viewers:** no actions, and no protection badge either (nothing to explain).
2. **Visible protection.**
   - When the viewer *could* write but the row is protected, render a non-interactive status chip in the actions cell (and in the mobile row trailing area): "Protected demo account" for `isDemo`, "Managed by platform administrators" for hierarchy-protected rows.
   - The chip has a tooltip/semantics sentence explaining why (reuse or align with the detail-dialog banner copy). Icon plus text, not color alone.
3. **Full lifecycle for everything else.** Non-demo, non-protected staff get Edit, Delete, Restore, and Permanently delete (type-to-confirm, existing `_confirmPermanentDeleteUser`), with `AppButton.isLoading` / busy state per row and an instant row patch on success.
4. **Backend parity (no rule change).** Confirm the user update, soft delete, restore and permanent delete routes (`backend/src/modules/user/routes/user.routes.js`, `user.service.js`) authorize the same audience — elevated, access-admin write, and HR user admin through `route-authorization` — and enforce the same hierarchy and demo guard. Fix any mismatch so no button can appear that the API rejects, or the reverse. Map `errors.user.demo_protected` to a localized message if it's ever returned.
5. **Setup view too.** `/admin/setup?section=users` gets identical behavior, since it's the same panel.

## Implementation constraints

- **Keep demo protection.** Don't modify `demo-users.js` / `demo-user-guard.js` behavior (product decision; `.cursor/access/demo-data.mdc`).
- **One source for rules.** Access decisions live in the feature access file, not scattered in widgets (`frontend/.cursor/permissions.mdc`). Backend stays authoritative (`backend/.cursor/auth-security.mdc`).
- **Shared UI.** Status chip via `AppStatusBadge`; tokens; localized copy (`frontend/.cursor/components.mdc`, `ui-workspace.mdc`).
- **Formatting.** `access_admin_management_dialogs.dart` is large — hand-indent, don't reformat.
- **Known test noise.** `test/features/access_admin` has 12 failures at HEAD (missing `ProviderScope` for `AppSpeechToTextButton`). Compare against HEAD before attributing new failures.

## Verification

- **Unit tests** for the action matrix, for each of: platform admin, tenant admin, facility admin, `HR` (`hr:write`), read-only HR (`hr:read`) × demo, system-critical, normal × active/deleted.
- **Widget tests** (`frontend/test/features/access_admin/`, `frontend/test/features/hr/presentation/widgets/`):
  - The HR staff directory shows the protection chip for demo rows and full actions for normal rows.
  - Read-only viewers see neither actions nor chips.
  - Deleted rows show Restore/Permanently delete only when allowed.
  - Mobile list rows match.
- **Backend tests:** route authorization for update/delete/restore/permanent for `HR` versus read-only roles; the demo guard still returns 403.
- **Run:** `cd frontend && flutter gen-l10n && flutter analyze && flutter test test/features/access_admin/ test/features/hr/`; `cd backend && npm run lint && node scripts/run-jest.js src/tests/modules/user src/tests/middlewares/route-authorization.middleware.test.js`.
- **Manual:**
  - As platform admin in DemoCare: HR → Staff → demo rows show the protection chip; create a test staff member → edit → delete → restore → delete → permanently delete.
  - As `hr@hosspi.com` (`HR`): the same lifecycle on normal rows, no Delete on system-critical rows.
  - As a custom role with only `hr:read`: no action or chip on any row.
  - At phone width: the same results in list rows.

## Dependencies

None. **015** redesigns the HR Access tab; this prompt covers the Staff tab only.
