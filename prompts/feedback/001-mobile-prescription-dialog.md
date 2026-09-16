# 001 — Mobile Prescription Dialog: Add More Medicines, One Tap Selects One

**Feedback:** FBK0000011, FBK0000012 · **Depends on:** — · **Stack:** frontend
**Index:** [000-index.md](000-index.md) (working agreements apply)

## Objective

On phones, a user building a pharmacy order must always be able to find and use "Add medicine". In the "Choose medicines" picker, tapping one medicine must select exactly that medicine.

## Feedback covered

| Field | FBK0000011 | FBK0000012 |
| :--- | :--- | :--- |
| Submitted (EAT) | 2026-09-15 01:33:27 | 2026-09-15 01:36:14 |
| Category | General feedback | General feedback |
| Feedback (verbatim) | "I am on the prescription dialog but I don't see away to prescribe more drugs" | "On the choose medicine dialog, whe I select an item, 2 are selected." |
| Reporter | Platform Administrator · `PLATFORM_ADMIN` | same |
| Tenant / facility / plan | DemoCare General Hospital · Pro `ACTIVE` | same |
| Screen / route | `pharmacy` · `/pharmacy` | `pharmacy` · `/pharmacy` |
| Device | Android app, Mobile, 393×886 @2.75x, portrait, `sm` | same |
| Env / theme / locale | production · light · `en` · text scale 1 · online | same |

## Current behavior (verified in code at `9cb01bb57`)

- **Entry point:** pharmacy "Create order" opens `PharmacyWalkInOrderDialog` (`frontend/lib/features/pharmacy/presentation/widgets/pharmacy_walk_in_order_dialog.dart`). It renders the shared `ClinicalPrescriptionActionDialog` (`frontend/lib/shared/clinical_actions/dialogs/clinical_prescription_action_dialog.dart`).
- **"Add medicine" placement:** it exists only as an `AppSearchBarAction` in the medicines table search toolbar (`_searchTrailingActions`), next to "Remove selected" and "Review billing". On narrow widths `AppSearchBar` (`frontend/lib/shared/components/app_search_bar.dart`) moves trailing actions past `maxTrailingActions` into a "More actions" overflow. `_AppListTableActionBar` (`frontend/lib/shared/components/app_list_table.dart`) drops labels when they don't fit. On a phone the action is icon-only or hidden.
- **Disabled without explanation:** the action stays disabled while `allowAddMedicines` is false. `_canAddMedicines` is false in Existing/New patient mode until a patient is linked, and nothing tells the user why.
- **Picker layout:** "Choose medicines" is `ClinicalPrescriptionCatalogDialog` (`frontend/lib/shared/clinical_actions/dialogs/clinical_prescription_catalog_dialog.dart`). It forces `displayMode: AppListTableDisplayMode.table`, so phones get the desktop table with a checkbox column and a tri-state "select page" header instead of its own `mobileItemBuilder` list.
- **Selection keying:** selection is keyed by `ClinicalActionCatalogOption.apiId` (`publicId ?? id`) in `_stagedIds`. The same key drives highlight (`rowColorBuilder`), the count label and returned options. `_toggleSelection` is idempotent, so a duplicated tap event alone cannot select two rows.
- **Suspected root causes for FBK0000012 (confirm before fixing):**
  1. Two rows returned by `pharmacyPrescriptionCatalogLoader` / `pharmacy_drug_catalog_mapper.dart` share an `apiId` (the same drug per batch or storage location, or a friendly-id collision), so one tap stages and highlights both.
  2. In the compact table, the tap lands on or propagates to the header "select page" checkbox.
  3. Duplicate `itemKeyBuilder` keys (`ValueKey(item.apiId)`) make Flutter reuse row state.

## Required behavior

1. **Reproduce first.** Write failing widget tests at a 393×886 surface for both problems before changing code, and write the confirmed root cause in the PR description.
2. **Visible "Add medicine" on every breakpoint.** On `xs`/`sm`/`md` it must not collapse into overflow or become icon-only. Use a labeled button in the dialog body above the list, or a pinned footer action. After the first line is added, keep an "Add more medicines" affordance visible.
3. **Explain the disabled state.** When adding is not allowed yet, show localized helper text (e.g. "Select or register the patient to add medicines") next to the control. The empty state must say the same.
4. **Adaptive picker.** Switch the picker to `AppListTableDisplayMode.adaptive` so phones use its `mobileItemBuilder` rows. Tapping a row or its checkbox toggles exactly that medicine. Keep the header "select page" control reachable, but don't let it take row taps.
5. **One selection identity everywhere.** Use one stable, unique key per selectable medicine for staging, highlight, count, `itemKeyBuilder`, `alreadySelectedDrugIds` filtering and returned options. If the loader returns several rows per drug (batches/locations), either dedupe to one row per drug or use a composite key consistently. Pick whichever matches how `_submitCreateOrder` expects line items.
6. **Accurate counts.** The "N selected" label equals the number of distinct staged medicines. Confirming adds exactly those lines. Reopening the picker shows already-added medicines as selected or excluded, with no duplicates.
7. **No regressions for other hosts.** Clinical prescribe from OPD/IPD reuses these dialogs and must keep working unchanged on tablet and desktop.
8. **Feedback states.** Catalog loading uses the shared loading state with a localized message. Remote search stays debounced. Submit uses `AppButton.isLoading`.

## Implementation constraints

- **Fix in shared code.** Fix it in `frontend/lib/shared/clinical_actions/` and `frontend/lib/shared/components/`. Don't fork a pharmacy-only copy (`frontend/.cursor/components.mdc`, `ui-patterns.mdc`).
- **Keep the pharmacy flow.** Follow `.cursor/flows/pharmacy-flow.mdc`: keep walk-in order semantics; pharmacy dispenses, it doesn't create encounter prescriptions.
- **Mobile quality.** Touch targets ≥ 48 px, safe-area and keyboard insets respected, no clipped actions at 360–430 px widths (`.cursor/mandatories.mdc`, `frontend/.cursor/accessibility.mdc`, `multi_platform_input.mdc`).
- **Tokens and copy.** Design tokens only. New strings go in `app_en.arb` (`frontend/.cursor/localization_i18n.mdc`).
- **Permissions unchanged.** Keep the existing gates in `frontend/lib/features/pharmacy/presentation/pharmacy_access.dart`.

## Verification

- **Widget tests** in `frontend/test/shared/clinical_actions/`:
  - The action dialog at `sm` shows a labeled, tappable "Add medicine" both with no lines and with lines. The disabled state shows its reason.
  - The picker at `sm` renders list rows. One tap stages one medicine even when the loader returns two rows for the same drug. The count label matches. The returned list has no duplicates.
  - At `xl` the table layout is unchanged.
- **Run:** `cd frontend && flutter gen-l10n && flutter analyze && flutter test test/shared/clinical_actions/`.
- **Manual:** Android phone (or Chrome device emulation at 393×886). Go to Pharmacy → Create order → Anonymous and Existing patient, add medicines, add more, reopen the picker, submit. Repeat at tablet and desktop widths in light and dark themes.

## Dependencies

None. 007 also touches pharmacy (drug pack scan) but different files.
