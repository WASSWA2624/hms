# 015 — HR Access Tab: One Roles Table with Lifecycle Actions

**Feedback:** FBK0000027 · **Depends on:** 010, 012 · **Stack:** frontend
**Index:** [000-index.md](000-index.md) (working agreements apply)

## Objective

Replace the HR "Manage staff and roles" tab (Users / Roles / Permissions toggle) with a single roles table:

- One `AppListTable` with a **Create role** toolbar action.
- An **actions** column with Edit, Delete (soft), Restore and Permanently delete.
- Behavior and look match the tenant/facility setup lists, reusing the setup roles panel rather than a second implementation.

## Feedback covered

| Field | Value |
| :--- | :--- |
| Feedback ID | FBK0000027 |
| Submitted (EAT) | 2026-09-16 00:33:04 |
| Category | Problem |
| Feedback (verbatim) | "Redesign the \"Manage staff and roles\" to remove nested tabs (Staff, Roles, Permissions). This tab should only consist of the app_list_table component with a create roles button. The table should have an actions column to manages edit, soft and permanent delete of roles. Similar to how it is implemented in the tenant/facility setup screen." |
| Reporter | Platform Administrator · `PLATFORM_ADMIN` · DemoCare General Hospital · Pro `ACTIVE` |
| Screen / route | `hr` · `/hr?section=access` |
| Device | Web, Windows Chrome 152, Desktop 1280×585 @1.5x, `xl` · production · light · `en` |

## Current behavior (verified at `9cb01bb57`)

- **HR Access tab.** `HrDeskSection.access` (label `hrManageAccessAction` = "Manage staff and roles") renders `HrAccessWorkspacePanel(embedded: true)` (`frontend/lib/features/hr/presentation/widgets/hr_access_dialogs.dart`, ~2,300 lines).
  - A description, an `AppWorkspaceBoardToggle<HrAccessPanel>` (users / roles / permissions), and a wrap of buttons (Refresh, Create user / role / permission).
  - Per-panel tables at page size 12, with local filtering over the loaded page (`_filteredUsers`).
  - Roles have no soft/permanent delete lifecycle in this panel.
  - It loads through `HrWorkspaceController.loadAccessUsers/Roles/Permissions`.
- **Setup already has the target.** `/admin/setup?section=roles` renders `ManageRolesPermissionsPanel` (`frontend/lib/features/access_admin/presentation/widgets/access_admin_management_dialogs.dart`).
  - Paged roles table, create via `role_mutation_dialog.dart`, similarity check (`role_similarity_dialog.dart`).
  - Soft delete, restore and type-to-confirm permanent delete with local pending state (`_pendingSoftDeletedRoles`, `_pendingPurgedRoleKeys`), `onListTotalChanged` for counts.
  - Tenant/facility filters (`allTenants = true` by default).
- **Other homes for the removed panels.**
  - Staff (users) already has its own HR tab (`ManageUsersPanel`, `HrDeskSection.staffDirectory`).
  - The permission catalog lives in Setup → Permissions.
  - Per-user direct permission grants/revokes are reachable today through the Access tab's user details (`onRemoveDirectPermission` etc. in `hr_access_dialogs.dart`) and Setup → Users.
- **Unused dialog entry.** `showHrAccessWorkspaceDialog` is defined but not called from other features.

## Required behavior

1. **One table.** HR `?section=access` renders `ManageRolesPermissionsPanel(panel: AccessAdminPanel.roles)` inside the standard HR workspace body, with no toggle, no description block and no extra button wrap.
   - The table toolbar carries search, filters, table settings/export (per permissions) and **Create role**.
2. **HR scope.**
   - In HR, the panel is scoped to the current tenant (and facility for facility-scoped actors).
   - Hide cross-tenant filters for non-platform actors. For platform admins acting inside a tenant, default to that tenant, and don't show all tenants.
   - Add a constructor option such as `scope: AccessAdminListScope.currentTenant`, instead of forking the widget.
3. **Actions column** (same rules as setup):
   - Active custom roles: Edit, Delete.
   - Deleted roles: Restore, Permanently delete (type-to-confirm).
   - Shipped/system/platform-catalog roles: read-only, with a "System role" badge — not deletable, and edit limited to what setup allows.
   - Per-row busy state, instant row patch, count update via `onListTotalChanged` → HR tab badge.
4. **Permissions.**
   - Create/edit/delete gated exactly as setup (`canWriteAccessAdmin`: elevated ∪ access-admin write ∪ `hr:write`) plus role hierarchy/ceiling rules.
   - Read-only HR (`hr:read`) sees the table without actions.
   - The backend already enforces this. Verify the HR audience against `route-authorization` for the role routes.
5. **Tab label and URL.**
   - Rename the tab to "Roles" (new localized key; don't repurpose `hrManageAccessAction` if other copy uses it).
   - Keep `?section=access` working and add `roles` as an alias in `HrDeskSection.fromQuery`. The canonical value can become `roles`, with a normalizing sync that follows **008**'s replace semantics if that has landed.
6. **Nothing lost.**
   - Per-user direct permission management must stay reachable from HR: add a "Permissions" action in HR staff details that opens the existing access-admin user access editor (the same one Setup → Users uses).
   - Update `hrStaffPermissionsManageHint` copy so it no longer points to "Manage staff and roles".
   - Users are managed in the Staff tab; the permission catalog in Setup → Permissions.
7. **Remove dead code.** Delete `HrAccessWorkspacePanel`, its users/roles/permissions tables, `HrAccessPanel`, `showHrAccessWorkspaceDialog`, the related controller loaders/repository methods and now-unused l10n keys, once nothing references them (`backend/.cursor/coding-standards.mdc` treats dead files as defects; apply the same to the frontend). Keep any helper still used by staff details.
8. **Responsive.** On phones the roles table renders list rows with an action menu per row. Create role stays visible.

## Implementation constraints

- **Reuse.** Reuse `ManageRolesPermissionsPanel`; no HR-local roles table (`frontend/.cursor/components.mdc`, `ui-workspace.mdc`).
- **Identifiers.** Role references use UUID for mutations (see **012** / the role friendly-id collision); display uses `human_friendly_id`.
- **Paging.** Follow the server paging pattern from **010**.
- **Formatting and test noise.** Both large files are not `dart format`-clean — hand-indent. `test/features/access_admin` has 12 failures at HEAD; compare against HEAD.

## Verification

- **Widget tests** (`frontend/test/features/hr/presentation/`, `frontend/test/features/access_admin/`):
  - `/hr?section=access` and `?section=roles` render only the roles table with Create role; no toggle.
  - The actions column per role state (custom active/deleted, system role) and per permission (platform admin, `HR`, `hr:read`).
  - Soft delete → restore → permanent delete patch the table and tab count.
  - HR scope hides cross-tenant filters.
  - Staff details exposes the Permissions action.
  - `hr_access_dialogs_test.dart` is updated or removed with the deleted code.
- **Run:** `cd frontend && flutter gen-l10n && flutter analyze && flutter test test/features/hr/ test/features/access_admin/`.
- **Manual:**
  1. As platform admin in DemoCare, `/hr?section=access` → create a custom role → edit → delete → restore → delete → permanently delete. System roles show read-only.
  2. As `HR`: the same, within the ceiling.
  3. As an `hr:read` custom role: no actions.
  4. Staff details → Permissions opens the user access editor.
  5. Phone width.

## Dependencies

- **010:** paging pattern.
- **012:** role identifier (UUID) fixes.
