# 008 — In-App Back Navigation

**Feedback:** FBK0000019 · **Depends on:** — · **Stack:** frontend
**Index:** [000-index.md](000-index.md) (working agreements apply)

## Objective

Every signed-in workspace has a consistent Back control in the app shell. It returns the user to the previous in-app location (workspace, section/tab, or queue), with its URL state. Android system back and the browser back button follow the same history. Back is hidden or disabled when there is nowhere to go back to.

## Feedback covered

| Field | Value |
| :--- | :--- |
| Feedback ID | FBK0000019 |
| Submitted (EAT) | 2026-09-15 21:15:31 |
| Category | Suggestion |
| Feedback (verbatim) | "Implement a back button to make navigation easy." |
| Reporter | Platform Administrator · `PLATFORM_ADMIN` · DemoCare General Hospital · Pro `ACTIVE` |
| Screen / route | `tenantFacilitySetup` · `/admin/setup?section=tenants` · `https://app.hosspi.com/admin/setup?section=tenants` |
| Device | Web, Windows Chrome 152, Desktop 1280×585 @1.5x, `xl` · production · light · `en` |

## Current behavior (verified at `9cb01bb57`)

- **Shell navigation replaces the stack.** Shell destination changes call `context.go(...)` (`frontend/lib/app/router/app_router.dart`, `onDestinationSelected`), so no page stack exists to pop.
- **Section/tab changes replace too.** They go through `syncWorkspaceLocation` (`frontend/lib/shared/routing/workspace_location_sync.dart`), which calls `GoRouter.of(context).go(location)` whenever the query changes — e.g. `TenantFacilitySetupPage._updateUrlForSection`, `HrWorkspacePage._updateUrlForSection`.
- **No Back control.** `ResponsiveShellScaffold` / `AppMenuBar` (`frontend/lib/shared/layout/responsive_shell_scaffold.dart`) render the title, menu, notifications, account and fullscreen controls, but no back affordance. No shell-level `PopScope` handles Android back.
- **Browser back is inconsistent.** It depends on how Flutter web reports each `go`; initial URL syncs (`_syncUrlToCurrentSection`) can add entries the user never chose.

## Required behavior

1. **History service.** Add an app-level navigation history (Riverpod provider under `frontend/lib/app/router/` or `frontend/lib/shared/routing/`) that records authenticated in-app locations (path + query) as the router location changes.
   - Record user-initiated navigation: shell destinations, submenu items, section/tab/queue changes, deep links into workspaces.
   - Don't record: automatic URL normalization (initial section sync, redirects, guard fallbacks such as a forbidden section falling back to a permitted one), auth/splash/session-restore routes, or duplicates of the current location.
   - Expose `canGoBack` and `goBack()`. Cap the length (e.g. 50) and clear it on logout or tenant/facility context switch.
2. **Separate sync from navigation.** Distinguish automatic syncs from real navigation: add a `replace`-style option to `syncWorkspaceLocation` (or a separate helper) used by the initial/normalizing syncs, so they don't create history entries.
3. **Back control in the shell.**
   - A localized icon button ("Back", tooltip includes the destination title when known) at the leading edge of `AppMenuBar` on every breakpoint, before the title and after the drawer/menu button on mobile.
   - Keyboard: `Alt+←` on desktop/web, without conflicting with browser shortcuts (`frontend/.cursor/multi_platform_input.mdc`).
   - Hidden when `canGoBack` is false.
4. **Going back.**
   - `goBack()` navigates to the previous entry and restores its section/tab/queue from the URL. The workspace's existing query parsing handles the rest.
   - If the previous location is no longer permitted (access changed), skip to the nearest permitted entry, or fall back to home.
5. **Android system back.**
   - A dialog/sheet open → close it (default Navigator behavior).
   - Otherwise, if `canGoBack` → `goBack()`.
   - Otherwise, on home → leave the app (or use the platform's double-back-to-exit if the app already has that pattern). On any other root workspace → go to home.
   - Implement once in the shell (`PopScope`), not per page.
6. **Browser back/forward.** Stays coherent with the history service. No double steps; a refresh keeps working from the current URL.
7. **Unsaved work.** Leaving a page with an unsaved mutation dialog uses the dialog's existing dismiss/confirm behavior; Back never discards input silently.

## Implementation constraints

- **Routing.** `go_router` only, named routes / `AppRoutes` helpers, no scattered raw strings. Guards stay authoritative (`frontend/.cursor/navigation.mdc`).
- **Shell.** Shared shell components in `frontend/lib/shared/layout/` (`frontend/.cursor/layouts.mdc`). Minimal rebuilds — watch only `canGoBack` (`frontend/.cursor/performance.mdc`).
- **Accessibility and copy.** Semantics label and tooltip localized in `app_en.arb`; 48 px target; visible focus (`frontend/.cursor/accessibility.mdc`).
- **Platform.** "Mobile: must handle … back behavior" (`frontend/.cursor/platform_guidelines.mdc`).

## Verification

- **Unit tests** for the history service: records user navigation; ignores replace syncs, redirects and duplicates; caps its length; clears on logout/context switch; `goBack` skips entries that are no longer authorized.
- **Widget/router tests** (`frontend/test/app/router/`):
  - Setup `tenants` → setup `facilities` → HR `staff`, then Back returns to setup `facilities`, and Back again to setup `tenants`.
  - No Back on first landing; Android back pops a dialog before history.
  - An initial `?section` normalization creates no entry.
- **Integration test** (`frontend/integration_test/`): shell navigation plus Back on a phone-sized surface.
- **Run:** `cd frontend && flutter gen-l10n && flutter analyze && flutter test test/app/router/`.
- **Manual:**
  - Web desktop (reporter scenario): `/admin/setup?section=tenants` → open another section → HR → Back ×2 → then use browser back/forward.
  - Android: system back through dialogs, sections and workspaces to exit.
  - Tablet rail layout.

## Dependencies

None. Other prompts that add sections/tabs (010, 015) should use the navigation sync helper this task introduces once it lands.
