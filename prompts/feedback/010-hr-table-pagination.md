# 010 — HR Tables: Server Pagination and Scroll Loading

**Feedback:** FBK0000021 · **Depends on:** — · **Stack:** backend + frontend
**Index:** [000-index.md](000-index.md) (working agreements apply)

## Objective

Every list table in the HR workspace, and in its dialogs, pages from the server. Search, filters and sorting apply server-side, and scrolling to the end shows the shared loading indicator while the next page loads. No HR table silently caps at the first 100 rows or filters only what happens to be loaded.

## Feedback covered

| Field | Value |
| :--- | :--- |
| Feedback ID | FBK0000021 |
| Submitted (EAT) | 2026-09-15 23:58:29 |
| Category | General feedback |
| Feedback (verbatim) | "Some tables in the hr screen tabs dont have pagiations and loading indicator when one scrolls down." |
| Reporter | Platform Administrator · `PLATFORM_ADMIN` · DemoCare General Hospital · Pro `ACTIVE` (HR module `hr-rosters`, PRO tier) |
| Screen / route | `hr` · `/hr?section=positions` |
| Device | Web, Windows Chrome 152, Desktop 1280×585 @1.5x, `xl` · production · light · `en` |

## Current behavior (verified at `9cb01bb57`)

- **How the shared table pages.** `AppListTable` (`frontend/lib/shared/components/app_list_table.dart`) supports `AppListTablePaginationMode.infinite` (the default: loads the next page near the bottom and shows the loader) and `buttons`. Both only engage when the host passes `page: AppPage<T>` with `totalItemCount` **and** `onPageChanged`.
- **Correct reference in HR:** `_HrWorkQueueTable` (`frontend/lib/features/hr/presentation/pages/hr_workspace_page.dart`) passes `page: state.workItems`, `isLoading`, and `onPageChanged: controller.changeWorkItemsPage`.
- **Broken tables** (load one request at `AppPageRequest.maxPageSize` = 100, no `onPageChanged`, local filtering):

  | Table | File | Problem |
  | :--- | :--- | :--- |
  | Positions (reported) | `widgets/hr_positions_panel.dart` | Loads 100, then `_applyLocalFilters`; sets `totalItemCount: filtered.length` |
  | Assign position picker | `widgets/hr_assign_position_dialog.dart` | `_items` from one 100-row page |
  | Assign roster: roster templates / copy-from-staff candidates | `widgets/hr_assign_roster_dialog.dart` | `_items` / `_candidates` from 100-row requests |
  | Position details: assigned staff + candidates | `widgets/hr_position_details_dialog.dart` | `maxVisibleItems` + full list, `_candidates` unpaged |
  | Roster detail: staff rows | `widgets/hr_roster_detail_dialog.dart` | `AppPage` built locally, `maxVisibleItems` |
  | Payroll detail breakdown | `widgets/hr_payroll_detail_dialog.dart` | Local `AppPage`, `maxVisibleItems` |

  All paths are under `frontend/lib/features/hr/presentation/`.
- **Backend.** HR list endpoints already accept `page`/`limit`/`search` (e.g. `staffPositions` in `frontend/lib/features/hr/data/repositories/hr_repository_impl.dart`), but some filters used locally (record state, scope, name/description) aren't server-side.

## Required behavior

1. **Audit.** Inventory every `AppListTable` under `frontend/lib/features/hr/` and record per table: data size bound, current paging, filters. Anything that can grow with tenant data must page from the server. Small bounded lists (a user's roles, compensation lines, one payroll run's items when capped) may stay local, but only if they render with `AppPage` + an accurate `totalItemCount`, and you justify it in the PR.
2. **Server paging for growable tables.**
   - Pass `page` + `onPageChanged` and use `AppListTablePaginationMode.infinite`, so a bottom loader shows while fetching; `buttons` mode where a dialog UX needs it.
   - Keep already-loaded rows while the next page loads.
   - Reset to page 1 on search, filter or sort change.
   - Show loading, empty ("no matches" versus "none yet") and error-with-retry states.
3. **Move local filters to the API.** Every filter applied locally today (positions: record state current/deleted/all, active, scope facility/shared, name, description; candidate filters) becomes a validated query param on the HR endpoints. Sorting goes server-side where the table exposes it.
4. **Accurate counts.** Counts and badges use the server `total` (e.g. `setPositionsTotalCount`), not the filtered page length.
5. **State lives in controllers.** Paging state (request, accumulated items, `hasMore`, loading-more flag) lives in the HR controller/provider, not in widget `setState` spread across dialogs. Consolidate into a reusable paged-list helper if one already exists in `frontend/lib/shared/data/`; otherwise add one there.
6. **Mutations and realtime.** After create/edit/delete/assign, patch the affected row and count in place and keep scroll position (`frontend/.cursor/instant_ui_sync.mdc`). HR realtime events (`RealtimeEventGroups.hr`) trigger the smallest refresh: the current pages, not a reset to page 1.
7. **Out of scope.** The Access tab tables in `widgets/hr_access_dialogs.dart` are replaced by **015**. Don't refactor them here.

## Implementation constraints

- **Frontend rules.** Lazy lists, pagination, debounced search (`frontend/.cursor/ui-patterns.mdc`, `performance.mdc`); workspace contract and state feedback (`ui-workspace.mdc`, `ui-feedback.mdc`); controllers own state (`state_management.mdc`).
- **Backend rules.** List endpoints paginate by default with a consistent `meta` (`backend/.cursor/api.mdc`, `.cursor/api-contract.mdc`). Zod schemas for new query params (`validation.mdc`). Indexes for new filter columns via migration if needed (`prisma.mdc`). Update `backend/docs/api/v1/openapi.yaml`.
- **Access.** Permissions unchanged (`frontend/lib/features/hr/presentation/hr_access.dart`); ABAC scope applies to every page request server-side.
- **Responsive.** Mobile list rows keep infinite scroll too.

## Verification

- **Backend tests** (`backend/src/tests/modules/staff-position/` and the relevant HR modules): the new filter params, pagination `meta`, and scope enforcement.
- **Frontend tests** (`frontend/test/features/hr/presentation/`):
  - With a fake repository returning 250 positions across pages, the positions panel shows 50/100 rows first, scrolling triggers the next page with the loader visible, and search resets paging and sends `search`.
  - The record-state filter goes to the API.
  - Counts come from the server total.
  - Same pattern for at least the assign position picker and roster detail staff.
- **Run:** `cd backend && npm run lint && node scripts/run-jest.js <changed HR tests> && npm run openapi:validate`; `cd frontend && flutter gen-l10n && flutter analyze && flutter test test/features/hr/`.
- **Manual:**
  - Seed or create >120 positions in a local tenant → `/hr?section=positions` → scroll → loader and more rows; filter "Deleted"; search a name beyond the first 100.
  - Repeat in the assign position / roster / position details dialogs.
  - Phone width.

## Dependencies

None. **011**, **014** and **015** must follow the paging pattern established here.
