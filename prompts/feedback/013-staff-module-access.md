# 013 — Per-Staff Module Access

**Feedback:** FBK0000023 · **Depends on:** 012 · **Stack:** backend + frontend
**Index:** [000-index.md](000-index.md) (working agreements apply)

## Objective

Authorized admins can limit which modules a staff member can use, whatever their roles grant. From staff details they either leave "All modules the roles allow" (the default) or restrict the staff member to selected modules. The restriction applies server-side on every request, and the staff member's menus, routes and actions update without re-login.

## Feedback covered

| Field | Value |
| :--- | :--- |
| Feedback ID | FBK0000023 |
| Submitted (EAT) | 2026-09-16 00:13:41 |
| Category | Suggestion |
| Feedback (verbatim) | "Implement a way to grant/deny module access to a staff. This limits the modules the users can access irrespective of their roles." |
| Reporter | Platform Administrator · `PLATFORM_ADMIN` · DemoCare General Hospital · Pro `ACTIVE` (29 commercial modules on Pro, `.cursor/access/modules.mdc`) |
| Screen / route | `hr` · `/hr?section=staff` (staff details) |
| Device | Web, Windows Chrome 152, Desktop 1280×585 @1.5x, `xl` · production · light · `en` |

## Already in place (verified at `9cb01bb57`) — build on it, don't duplicate

- **Data model.** `user_module_assignment` (`backend/prisma/schema.prisma`: `user_id`, `module_id`, `tenant_id`, `facility_id`, soft delete, unique per user/module/tenant/facility).
- **Loading.** `module_assignments` are loaded with the live user (`backend/src/modules/auth/repositories/auth.repository.js`).
- **Enforcement.** Step 3 of effective access in `backend/src/lib/authorization/effective-access.js`: `resolveAssignedModuleCodes` → `filterPermissionNamesByAssignedModules`, applied by `live-access.middleware.js` (`applyAssignedModuleGate: true`) and returned as `assigned_modules` by `auth.service.js`.
  - Platform-elevated actors are exempt.
  - An **empty** list means "no extra restriction".
  - Only module-scoped permissions are affected; core keys (`profile:*`, `setup:read`, `reports:read` baseline, etc.) are not (`.cursor/access/permissions.mdc`).
- **What's missing:** there is no API to read or write assignments, no UI, and no way to express "restricted to zero modules" (empty = unrestricted).
- **Frontend.** `AppAccessPolicy.fromSession` uses the backend's hydrated permission set, which is already filtered. There's no client step 3 (a documented deviation) and nothing reads `assigned_modules`.

## Required behavior

1. **Explicit restriction mode.**
   - Persist whether a user is restricted: e.g. `user.module_access_mode` enum `ALL | RESTRICTED` (default `ALL`), per tenant context if users can span tenants.
   - `RESTRICTED` with zero assignments must deny all module-scoped permissions.
   - Update `resolveEffectiveAccess` / `resolveAssignedModuleCodes` so the gate applies when mode is `RESTRICTED` (not only when the list is non-empty).
   - Migration plus a regression test for existing users (mode `ALL`, behavior unchanged).
2. **API** (under the user or HR workspace module; kebab-case, `human_friendly_id`):
   - `GET /api/v1/users/:id/module-access` → `{ mode, modules: [{ slug, name, min_tier, entitled, granted_by_roles, assigned }] }`, listing the tenant-entitled commercial modules only (platform infrastructure modules are always on and not shown).
   - `PUT /api/v1/users/:id/module-access` with `{ mode, module_slugs[] }`. It replaces the set atomically: soft-delete removed rows, restore or create added ones. Validate slugs against `plan-module-matrix.js` and the tenant entitlement. Unknown or unentitled → 400.
3. **Authorization** (backend authoritative):
   - Actor needs user-admin rights (the same audience as editing staff: elevated ∪ access-admin write ∪ `hr:write`) within ABAC scope.
   - Actors can't change their own module access.
   - Can't restrict users at or above their hierarchy (e.g. `HR` can't restrict `TENANT_ADMIN`; system-critical users only by platform admins).
   - Platform-elevated targets stay exempt: show a read-only note.
   - Demo accounts stay protected (009).
4. **Audit and realtime.**
   - Audit before/after mode and module sets with actor and scope (`backend/.cursor/compliance.mdc`: changes to modules/permissions need a before/after trail and restore capability).
   - After commit, publish a user-scoped event so the affected user's client re-fetches `/auth/me` and rebuilds `AppAccessPolicy`, and HR/access views refresh. Reuse the existing access/entitlement refresh path if one exists (`RealtimeEventGroups.subscriptions` includes `module.entitlement_updated`). Otherwise add one, with constants in `backend/src/lib/websocket/events.js` and `frontend/lib/core/realtime/realtime_events.dart`.
5. **UI — "Module access" section in HR staff details** (`frontend/lib/features/hr/presentation/widgets/hr_staff_details_body.dart`), next to Roles:
   - Summary: "All modules allowed by roles" or "Restricted to N modules".
   - Edit dialog (`AppWorkspaceMutationDialog`):
     - Mode radio: All / Restrict to selected.
     - An `AppListTable` of entitled modules with checkboxes, module name, tier, and "Granted by roles" or "Not granted by roles". Modules not granted by roles can be ticked, but show a hint that ticking doesn't grant access (the gate only narrows).
     - Search, and select all/none.
   - Save uses `AppButton.isLoading` and patches the section instantly.
   - Also reachable from the Setup → Users detail dialog through the same shared widget.
6. **Effective access preview.** Show which workspaces the staff member will reach after save — resolved server-side via the GET, or a preview endpoint using `resolveEffectiveAccess`.
7. **Unauthorized actors don't see the section's edit action.** Read-only viewers with `hr:read` see the summary only.

## Implementation constraints

- **Access pipeline order stays intact:** union(grants) → ∩ plan modules → ∩ assigned modules → ∩ plan caps → ∪ `reports:read` → − version-disabled (`.cursor/access/permissions.mdc`). Update that rule file's step-3 wording to describe `module_access_mode` and keep it under the word limits in `.cursor/rule-file-standards.mdc`.
- **Module identifiers.** Module slugs (not codes) at runtime (`.cursor/access/modules.mdc`). Version-disabled modules may be listed but never grant anything (`version-disabled-screens.mdc`).
- **Backend structure.** Layering, Zod, OpenAPI, migration committed (`backend/.cursor/*`).
- **Frontend.** No client re-implementation of step 3 beyond consuming the hydrated permissions (`frontend/.cursor/permissions.mdc`). Localized module names come from existing module label localizations.

## Verification

- **Backend tests** (`backend/src/tests/lib/authorization/effective-access.test.js` and the new module/route tests):
  - Mode `ALL` is unchanged.
  - `RESTRICTED` with [lab] removes pharmacy permissions and keeps core keys.
  - `RESTRICTED` with [] denies all module-scoped keys.
  - Elevated users are exempt.
  - PUT is atomic, restores soft-deleted rows, and rejects unentitled slugs.
  - Hierarchy, self-change and demo guards hold.
  - Audit and event are emitted.
  - `/auth/me` reflects the change.
- **Frontend tests** (`frontend/test/features/hr/presentation/widgets/`):
  - The section renders mode/summary; the dialog saves the selection and patches instantly.
  - Gating per role.
  - The realtime event triggers session re-hydration (controller test with a fake realtime stream).
- **Run:** `cd backend && npm run prisma:migrate && npm run lint && node scripts/run-jest.js src/tests/lib/authorization src/tests/modules/user src/tests/modules/hr-workspace && npm run openapi:validate`; `cd frontend && flutter gen-l10n && flutter analyze && flutter test test/features/hr/ test/core/permissions/`.
- **Manual:**
  1. As platform admin: restrict a nurse to Nursing + Lab.
  2. In another browser the nurse, already signed in, loses OPD/IPD menus within seconds without re-login; direct API calls to OPD return 403.
  3. Switch the nurse back to All → access returns.

## Dependencies

- **012:** staff-details access area and assignment identifier fixes.
