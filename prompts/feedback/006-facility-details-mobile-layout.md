# 006 — Facility Details on Mobile: Scrollable Header, List-Style Users

**Feedback:** FBK0000017 · **Depends on:** 002 · **Stack:** frontend
**Index:** [000-index.md](000-index.md) (working agreements apply)

## Objective

On phones (`xs`/`sm`, and `md` where needed), the Facility details dialog scrolls as one surface. The facility summary, contacts, metrics and panel selector scroll away naturally, and the scroll then continues into the selected panel. The users panel (and the other structure panels) render as the same mobile list rows used elsewhere, not as a squeezed table.

## Feedback covered

| Field | Value |
| :--- | :--- |
| Feedback ID | FBK0000017 |
| Submitted (EAT) | 2026-09-15 11:43:48 |
| Category | Problem |
| Feedback (verbatim) | "On mobile, and under facility details, I want the facility details, contacts and all other sections above the user details to be scrollable. But when one scrolls to the table, the now becomes scrollable as usual but it should responsovely display like how other tables render lists on mobile screen sizes." |
| Reporter | Platform Administrator · `PLATFORM_ADMIN` · DemoCare General Hospital · Pro `ACTIVE` |
| Screen / route | `tenantFacilitySetup` · `/admin/setup?section=tenants` → tenant → facility details |
| Device | Android app, Mobile 393×886 @2.75x, portrait, `sm` · production · light · `en` · online |

## Current behavior (verified at `9cb01bb57`)

- **Fixed layout.** `_FacilityDetailsDialogState.build` (`frontend/lib/features/tenant_facility/presentation/widgets/tenant_facility_management_dialogs.dart`) wraps the content in `SizedBox(height: 560)`, then uses `LayoutBuilder` with `wide = maxWidth >= 720`:
  - **Wide:** a `Row` with the summary in a 320 px `SingleChildScrollView` and the right panel `Expanded`. This works.
  - **Narrow:** a `Column(summary, Expanded(rightPanel))`. The summary (`_FacilityDetailsSummary`: logo, identity, contacts, metrics, panel selector) is **not scrollable** and eats most of the 560 px. The right panel (`_FacilityDetailsUsersPanel` → `AppListTable` with a `mobileItemBuilder`, or `_FacilityStructureCrudPanel` for departments/units/wards/rooms/beds) gets a sliver of height or overflows, so the list can't render or be used properly.
- **Hard-coded dimensions.** The 560 height and the 320/720 widths break `.cursor/mandatories.mdc` ("do not hard-code widths").
- **Tenant details has the same bug.** `_TenantDetailsDialog` (around line 1836, `height: 560`, `wide >= 720`, `Expanded(child: facilitiesPanel)`) has the same narrow-layout problem.

## Required behavior

1. **Narrow widths** (use `AppBreakpoints`/`lib/core/responsive/`, not a magic 720):
   - The dialog body is one vertical scroll surface (`CustomScrollView`/`NestedScrollView`).
   - The summary sections are scrollable header slivers.
   - The panel selector may pin while the list scrolls, so switching panels stays reachable.
   - The selected panel's list continues the same scroll. There are no nested fighting scrollables and no fixed 560 px box.
   - The dialog fills the available mobile height (full-screen dialog behavior on phones if `AppDialog` supports it), respecting safe areas and keyboard insets.
2. **Users panel on phones:**
   - Rows render through `AppListTable`'s list layout (`AppListTableMobileItem`: name, role/status meta, avatar) with row actions (edit, delete, restore, permanent delete) reachable from each row (trailing menu or buttons, 48 px targets).
   - Search stays at the top of the panel.
   - Pagination switches to infinite-scroll loading on phones: loading indicator at the end, "no more" state, pull to refresh if the shared table supports it.
3. **Other panels.** Departments, units, wards, rooms and beds (`_FacilityStructureCrudPanel`) use the same scroll model and mobile rows.
4. **Wide layouts stay as they are** (two columns), but replace the literal 320/560/720 values with responsive tokens/constraints.
5. **Tenant details dialog.** Apply the same fix to `_TenantDetailsDialog` for consistency. It's the same pattern, and users hit it on the way to facility details.
6. **Preserve state.** Scroll position, selected panel, search text and loaded pages survive opening and closing nested dialogs (user edit, staff details) and returning from them.
7. **Feedback states.** Loading/empty/error states render inside the scrolling body with localized messages (`AsyncStateScaffold`/`AppLoadingIndicator`).

## Implementation constraints

- **Shared layout primitives.** Reuse `AppListTable` list mode, `AppDialog` and `ResponsivePage` utilities. If a reusable "scrolling dialog with header slivers + table" is needed, add it under `frontend/lib/shared/` instead of building it privately in the feature (`frontend/.cursor/components.mdc`, `layouts.mdc`, `ui-workspace.mdc`).
- **No duplicate screens.** Don't create a separate mobile screen; the interaction model stays the same (`frontend/.cursor/layouts.mdc`).
- **Tokens and copy.** Design tokens only; localized strings; 48 px targets (`frontend/.cursor/accessibility.mdc`).
- **Formatting.** This file is large and not `dart format`-clean. Hand-indent edits and don't reformat the file.

## Verification

- **Widget tests** (`frontend/test/features/tenant_facility/presentation/`):
  - At 393×886: the facility details body scrolls; after scrolling past the summary the users list is visible as list rows; row actions are tappable; no overflow errors.
  - At 1280×800: the two-column layout is unchanged.
  - The same checks for tenant details.
  - Switching panels keeps the scroll/header usable.
- **Run:** `cd frontend && flutter gen-l10n && flutter analyze && flutter test test/features/tenant_facility/`.
- **Manual:**
  - Android phone and Chrome device emulation at 360×740 and 393×886 → open tenant → facility details → scroll through summary into users → load more → edit a user and return (position kept) → switch to departments/beds.
  - Tablet 768×1024 and desktop 1280×585 @1.5x (the reporter's desktop) in light and dark themes.

## Dependencies

- **002 (facility contact fallback)** changes `_FacilityDetailsSummary` contents in the same file. Land it first and rebase this layout work on it.
