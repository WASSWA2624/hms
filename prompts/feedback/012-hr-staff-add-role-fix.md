# 012 — Fix "Add Role" in HR Staff Details

**Feedback:** FBK0000025 · **Depends on:** — · **Stack:** backend + frontend
**Index:** [000-index.md](000-index.md) (working agreements apply)

## Objective

In HR → Staff → staff details → Roles, adding one or more roles assigns exactly the selected roles to that staff member, in the right tenant/facility scope. The UI shows them immediately. Failures are reported per role with a clear, localized reason and are never shown as success.

## Feedback covered

| Field | Value |
| :--- | :--- |
| Feedback ID | FBK0000025 |
| Submitted (EAT) | 2026-09-16 00:21:18 |
| Category | Problem |
| Feedback (verbatim) | "Under staff details in HR screen, add role functionaity does not work. When I add a role to the user,  it is not getting added, yet removing it works." |
| Reporter | Platform Administrator · `PLATFORM_ADMIN` (in tenant context) |
| Tenant / facility / plan | DemoCare General Hospital (`TEN-9322E26AFD` / `FAC-FBB67A688F`) · Pro `ACTIVE` |
| Screen / route | `hr` · `/hr?section=staff` → staff details → Roles |
| Device | Web, Windows Chrome 152, Desktop 1280×585 @1.5x, `xl` · production · light · `en` |

## Current behavior (verified at `9cb01bb57`)

**Flow.** `showHrAssignRoleDialog` (`frontend/lib/features/hr/presentation/widgets/hr_assign_role_dialog.dart`):

1. `_openAddRoles` builds options from `HrWorkspaceState.referenceData.roles`.
2. `showAppRoleSelectionTableDialog` collects the selection.
3. `HrWorkspaceController.assignUserRolesBatch` posts one `POST /api/v1/user-roles` per role via `HrRepositoryImpl.assignUserRole` with `{user_id, role_id, tenant_id, facility_id}`.
4. `_reloadRoles` refreshes the list.

**Findings to confirm (strongest first):**

1. **Ambiguous role identifier.**
   - The role option `value` is the role's `human_friendly_id` (`enrichRoleOption` in `backend/src/lib/hr/role-catalog.js`: `value: entry.human_friendly_id || entry.id`).
   - HR reference roles are platform-catalog rows (`tenant_id: null`, `hr-workspace.service.js` `prisma.role.findMany`).
   - Role friendly ids (`ROL…`) restart per tenant, so the same `ROL0000006` can be a platform catalog role and a tenant custom role.
   - `normalizeUserRolePayload` → `resolveIdentifierForPayload({ model: 'role' })` (`backend/src/modules/user-role/services/user-role.service.js`) can pick the wrong row. Then `assertRoleFitsAssignment` throws `role_tenant_mismatch` / `role_facility_mismatch`, or the wrong role gets assigned.
   - The same bug was fixed for Access Admin on 2026-09-13 by returning role **UUIDs** for assignment. HR was not updated.
2. **Wrong facility.** `facility_id` is the **actor's** session facility (`sessionStateProvider…user.facilityId`), not the staff member's facility. For a platform admin or a cross-facility admin this mis-scopes the assignment or fails the role-facility check.
3. **Mixed identifiers in "already assigned".** `_usedRoleIds` compares `HrUserRole.roleId`. The DTO prefers `role_display_id` / friendly id and falls back to the UUID. Mixed identifier kinds make "already assigned" filtering unreliable.
4. **Batch error handling.** `assignUserRolesBatch` keeps only the first failure. Partial success isn't reported per role, and the reference refresh runs even on failure.
5. **Removal takes a different path.** `revokeUserRole` does `DELETE /user-roles/:id` by the user-role's own id, with no role resolution. That's why removing works.

## Required behavior

1. **Reproduce first.** Write a backend test that reproduces the collision: a tenant custom role and a platform catalog role share `human_friendly_id`, and assigning by that id picks the wrong row. Then fix it.
2. **Assign by role UUID end-to-end.**
   - HR reference roles (and any HR role picker) expose the role UUID for assignment (e.g. `value` = UUID, or an explicit `assign_id`), keeping `display_id` for display only.
   - `HrOptionDto` / `HrUserRole` map the UUID explicitly.
   - The `user-roles` API accepts a role UUID. If friendly ids stay accepted for backward compatibility, they must be resolved **within the target tenant + platform catalog with a deterministic, documented precedence**, and ambiguity must return 409 `errors.user_role.role_ambiguous`, never a guess.
   - Follow the same fix as Access Admin (see commit history around 2026-09-13 in `backend/src/modules/access-admin-workspace/` and `frontend/lib/features/access_admin/`).
3. **Correct scope.**
   - Send the **staff member's** facility (from `HrStaffDetail.profile` / the user's assignment), or omit `facility_id` so the backend defaults to the target user's facility (`resolveAssignmentScope`).
   - Tenant comes from the staff profile.
4. **Available roles.** The picker lists every role the actor may assign to this user:
   - platform catalog roles allowed for HR (`HR_ASSIGNABLE_ROLE_NAMES`) **plus** the tenant's custom roles,
   - filtered by the actor's assignment ceiling (`assertRoleIdAssignable`) and the subscription package,
   - with already-assigned roles excluded by UUID.
5. **Atomic batch.**
   - Add `POST /api/v1/user-roles/batch` (or extend HR's workspace API) that assigns N roles in one transaction and returns per-role results.
   - Re-adding a previously removed role restores the soft-deleted `user_role` row (existing repository behavior from `63e38526a`) instead of failing on the unique constraint.
   - Audit each assignment; publish realtime after commit.
6. **UI outcome.**
   - Success patches the roles table and the staff details access summary immediately (`frontend/.cursor/instant_ui_sync.mdc`).
   - Partial failure lists which roles failed and why (localized mapped codes: ceiling, tenant mismatch, demo-protected account, plan-excluded).
   - Nothing is shown as success unless it persisted.
   - Loading uses `AppButton.isLoading` / table busy state.
7. **Session refresh.** If the staff member is signed in, their permissions refresh through the existing live-access path on their next request. Confirm a role added here changes `/auth/me` without re-login.
8. **Demo accounts stay protected** (see 009). Assigning to a demo login returns the demo-protected error, and the UI explains it.

## Implementation constraints

- **Identifiers.** Payloads use `human_friendly_id` for public identifiers, **except roles for assignment, which must use UUID** (known collision). Document the exception in OpenAPI (`.cursor/api-contract.mdc`).
- **Access authority.** Assignable rights stay within the actor ceiling and tenant subscription (`frontend/.cursor/permissions.mdc`, `.cursor/access/permissions.mdc`). Changes are atomic, audited and restorable (`backend/.cursor/auth-security.mdc`, `compliance.mdc`).
- **Tests and routes.** Repository/service/route tests (`backend/.cursor/testing.mdc`). Keep `backend/docs/api/v1/openapi.yaml` in sync.
- **Known test noise.** Some `role.service` and `assignable-access` tests fail at HEAD (`buildRoleScopeWhere`) — compare against HEAD.

## Verification

- **Backend tests** (`backend/src/tests/modules/user-role/`, `backend/src/tests/modules/hr-workspace/`):
  - Friendly-id collision reproduction; UUID assignment picks the right role.
  - Ambiguous friendly id returns 409.
  - Facility defaults to the target user.
  - Batch: all success, partial ceiling failure, re-add restores a soft-deleted row.
  - Reference roles include tenant custom roles within the ceiling.
- **Frontend tests** (`frontend/test/features/hr/presentation/widgets/`):
  - The add-roles dialog sends UUIDs and the staff facility.
  - Partial results render per role.
  - The table and access summary patch on success.
  - Already-assigned roles are excluded by UUID.
- **Run:** `cd backend && npm run lint && node scripts/run-jest.js src/tests/modules/user-role src/tests/modules/hr-workspace && npm run openapi:validate`; `cd frontend && flutter gen-l10n && flutter analyze && flutter test test/features/hr/`.
- **Manual (local DB with a tenant custom role whose `ROL…` id matches a platform role):**
  1. As platform admin in the tenant: HR → Staff → non-demo staff member → Roles → add NURSE + the custom role → both appear.
  2. Remove NURSE and add it again → it's restored.
  3. The staff member logs in → new menus appear.
  4. As `HR`: roles above the ceiling aren't offered.

## Dependencies

None. **013** (module access) and **015** (Access tab) build on the identifier fixes here.
