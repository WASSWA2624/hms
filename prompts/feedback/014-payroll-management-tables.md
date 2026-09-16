# 014 — Payroll Management Tabs as Tables

**Feedback:** FBK0000026 · **Depends on:** 010 · **Stack:** frontend (backend only if a missing read endpoint is needed)
**Index:** [000-index.md](000-index.md) (working agreements apply)

## Objective

Redesign the staff "Manage payroll" dialog so each tab — Salary, Deductions, Payments — presents its records in `AppListTable`, with clear columns, row actions, totals, and create/edit in shared mutation dialogs. It must look as organized as other HOSSPI workspaces on every breakpoint.

## Feedback covered

| Field | Value |
| :--- | :--- |
| Feedback ID | FBK0000026 |
| Submitted (EAT) | 2026-09-16 00:25:56 |
| Category | General feedback |
| Feedback (verbatim) | "Under the manage payroll, improve the display of data in the salary, deductions and payments tabs. Orgnize these using the existing app_list_table component where applicable, but it currently looks disorganized, and not elegantly organized." |
| Reporter | Platform Administrator · `PLATFORM_ADMIN` · DemoCare General Hospital · Pro `ACTIVE` |
| Screen / route | `hr` · `/hr?section=staff` → staff details → Manage payroll |
| Device | Web, Windows Chrome 152, Desktop 1280×585 @1.5x (short 585 px viewport), `xl` · production · light · `en` |

## Current behavior (verified at `9cb01bb57`)

`showHrStaffPayrollManagementDialog` (`frontend/lib/features/hr/presentation/widgets/hr_staff_payroll_management_dialog.dart`, opened from `hr_staff_details_body.dart`):

- **Tabs and height.** A raw Material `TabBar`/`TabBarView` with a hard-coded body height `MediaQuery.height * 0.55`. On the reporter's 585 px viewport that is ~320 px.
- **Salary tab.**
  - One `ListTile` per active compensation: title, pay type subtitle, and **raw** `row.payFrequency` (e.g. `MONTHLY`) as trailing text.
  - One "Edit salary" button that opens `showHrCompensationDialog`.
  - No effective dates, amount/currency columns or history.
- **Deductions tab.**
  - A stack of `AppContentPanel` inline editors (type select + icon delete, label, mode select, value field) per deduction, then "Add deduction" and "Save deductions".
  - Deduction codes are hard-coded (`TAX`, `NSSF`, `NHIF`, `LOAN`, `OTHER`).
  - Deductions are stored inside `compensation.metadata_json.deductions` of the primary monthly compensation and saved via `updateSelectedStaffProfile({compensations: …})`.
- **Payments tab.**
  - Period start/end date fields, bank reference, "Preview", "Approve & send".
  - A hand-rolled `LinearProgressIndicator`.
  - The preview renders `HrPayrollPreviewBreakdown` cards.
  - **No list of past payments** (payroll items/runs for this staff).

## Required behavior

1. **Dialog shell.**
   - Use the shared tab strip (`AppTabStrip`, `frontend/lib/shared/components/app_tab_strip.dart`) with count badges.
   - Size tab bodies with the dialog's flexible layout (`Expanded` inside `AppDialog`), not a screen-height fraction, so tables fill the space on short and tall viewports.
   - Keep the staff header (name, staff number, position) visible.
2. **Salary tab** — `AppListTable` of compensations, including history:
   - Columns: pay type, amount + currency (formatted), frequency (localized), effective from, effective to, status (Active / Ended / Scheduled via `AppStatusBadge`).
   - Default filter "Active"; filter to show all.
   - Toolbar action "Add salary"; row actions Edit and End/Delete, per `HrPayrollDraftsAtomPermissions` / HR write gates.
   - Create/edit through the existing `showHrCompensationDialog` (restyled if needed) or `AppWorkspaceMutationDialog`.
3. **Deductions tab** — `AppListTable` of the staff member's standing deductions:
   - Columns: type (localized), label, mode (Fixed / Percent), value (formatted currency or %), applies to (compensation), monthly amount estimate.
   - Toolbar "Add deduction"; row actions Edit / Remove, via a mutation dialog (no inline editors).
   - A footer total of estimated monthly deductions and net pay estimate.
   - Save per mutation (no global "Save deductions" button), with an instant table patch.
   - Keep the storage contract (`metadata_json.deductions`) unless 010's server-paging audit shows a dedicated endpoint is needed.
   - Replace hard-coded deduction codes with a localized option source defined once (HR reference data if the backend provides deduction types; otherwise a shared constant with localized labels). Don't hard-code country-specific schemes in widgets.
4. **Payments tab** — two areas:
   - **Payment history:** an `AppListTable` of this staff member's payroll items across runs, server-paged per **010**. Columns: period, run id (`human_friendly_id`), gross, deductions, net, status, paid/approved date, bank reference. Row tap opens the existing payroll detail (`hr_payroll_detail_dialog.dart`).
   - **Generate payment:** a toolbar action "Generate payment" opens a mutation dialog with period + bank reference, preview (breakdown shown as a table: earning/deduction lines with amounts and a totals footer), then Approve & send, with `AppButton.isLoading`.
   - Replace the hand-rolled progress bar with shared loading feedback.
5. **Consistency.** Localized enum labels everywhere (no raw `MONTHLY`/`PER_MONTH`), amounts through the shared currency formatter, empty states with a primary action, error states with retry.
6. **Responsive.** On phones the tables render mobile list rows with the same meaning. The tab strip scrolls; actions stay reachable.
7. **Sync.** Mutations patch staff details (compensation summary) and the HR payroll queue counts immediately. Realtime HR events reconcile other sessions.

## Implementation constraints

- **Workspace contract.** `AppListTable`, `AppWorkspaceMutationDialog`, `AppStatusBadge`, `AsyncStateScaffold`; no feature-local section chrome (`frontend/.cursor/ui-workspace.mdc`, `components.mdc`).
- **Tokens and copy.** No hard-coded colors, spacing or `TextStyle`; localized strings (`frontend/.cursor/design-system.mdc`, `localization_i18n.mdc`).
- **Access.** Payroll is sensitive: keep permission gates (`hr_access.dart` payroll atoms) and audit on the backend (`backend/.cursor/auth-security.mdc`). Approve & send is online-only.
- **Backend.** Change it only when a list endpoint is missing (payroll items by staff), with pagination, scope, Zod and OpenAPI updates.

## Verification

- **Widget tests** (`frontend/test/features/hr/presentation/widgets/`):
  - Each tab renders a table with localized columns and values; add/edit/remove flows patch the tables.
  - The deductions total is correct for fixed + percent.
  - Payment history pages (fake repository with >1 page).
  - Generate payment preview renders the breakdown table; approve shows loading and success.
  - Permission-gated actions are hidden for read-only viewers.
  - At 393×886 list rows render with no overflow; at 1280×585 tables fill the dialog.
- **Run:** `cd frontend && flutter gen-l10n && flutter analyze && flutter test test/features/hr/` (plus backend tests if an endpoint is added).
- **Manual:** `/hr?section=staff` → a staff member with salary → Manage payroll at 1280×585 @1.5x (reporter setup), 1920×1080 and phone width; exercise every tab action in light and dark themes.

## Dependencies

- **010:** paged table pattern for payment history.
