# 002 — Facility Contacts Fall Back to Tenant Contacts

**Feedback:** FBK0000013 · **Depends on:** — · **Stack:** backend + frontend
**Index:** [000-index.md](000-index.md) (working agreements apply)

## Objective

When a facility has no phone and/or no email of its own, every place that shows or prints facility contacts uses the tenant's contact for the missing value and marks it as inherited. The facility's own contact always wins, and inheritance is computed when read, so later tenant contact changes flow through automatically.

## Feedback covered

| Field | Value |
| :--- | :--- |
| Feedback ID | FBK0000013 |
| Submitted (EAT) | 2026-09-15 08:39:57 |
| Category | Improvement |
| Feedback (verbatim) | "If a facility does not have contacts (phone + email), assign it the tennant contacts." |
| Reporter | Platform Administrator · `PLATFORM_ADMIN` |
| Tenant / facility / plan | DemoCare General Hospital (`TEN-9322E26AFD` / `FAC-FBB67A688F`) · Pro `ACTIVE` |
| Screen / route | `tenantFacilitySetup` · `/admin/setup?section=tenants` |
| Device | Web, Windows Chrome 152, Desktop 1280×585 @1.5x, `xl` · production · light · `en` |

## Current behavior (verified at `9cb01bb57`)

- **Facility contact source:** `contact` rows with `facility_id` (`contact_type` `PHONE`/`EMAIL`) plus the first `address`. `buildContactAddress` and `serializeFacility` in `backend/src/modules/tenant-facility-workspace/services/tenant-facility-workspace.service.js` turn them into `phone`, `email`, `address_line1`, `city`, `country`. Missing values are `null`.
- **Tenant contact source:** `resolveTenantContact` (`backend/src/lib/tenant/resolve-tenant-contact.js`) takes `extension_json.contact` first. If that is empty it falls back to the **primary tenant admin's personal** email/phone, then to the first tenant user role.
- **Setup checklist:** `buildChecklist` treats facility identity as incomplete when the facility has no phone.
- **Frontend:** facility details summary (`_FacilityDetailsSummary` in `frontend/lib/features/tenant_facility/presentation/widgets/tenant_facility_management_dialogs.dart`, `FacilityContactAddress`) and print branding (`frontend/lib/app/printing/print_form_template_context.dart`, `frontend/lib/shared/printing/print_facility_sections.dart`) show only the facility's own values.

## Required behavior

1. **One backend helper.** Add a single helper, e.g. `resolveEffectiveFacilityContact(facility, tenant)` in `backend/src/lib/facility/` or `backend/src/lib/tenant/`. Per field (`phone`, `email`), use the facility's own primary value, otherwise the tenant contact. Return provenance per field: `phone_source` / `email_source` = `FACILITY` | `TENANT` | `NONE`.
2. **Tenant contact = what tenant details already shows.** Inherit exactly what `resolveTenantContact` returns, so admins see one consistent "tenant contact". For legacy tenants that value comes from the primary tenant admin, and it is already displayed as the tenant's contact. Don't widen it with any other source (other users, facility staff). Load the tenant with `PRIMARY_TENANT_ADMIN_INCLUDE` wherever the helper runs, to avoid N+1 queries on facility lists (`backend/.cursor/performance.mdc`).
3. **Apply everywhere facility contacts leave the API.** That means the tenant-facility workspace facility serializer/snapshot, facility list/detail endpoints, and whatever feeds print branding. Keep the existing `phone`/`email` fields as the effective values and add the `*_source` fields, so current clients keep working (non-breaking, `.cursor/api-contract.mdc`).
4. **No data copy.** Don't create `contact` rows for the facility, and don't backfill. Editing tenant contacts must change inherited facility values right away, and adding a facility's own contact must stop inheritance for that field.
5. **Edit forms.** Facility edit forms show only the facility's own values. Show the inherited value as a hint (e.g. "Using tenant phone: +256…"), never as a saved field value, so saving a form never silently persists the tenant value.
6. **Facility details summary.** Show the effective phone/email with a small localized "From tenant" marker when inherited (icon + text, not color alone).
7. **Print branding.** Use effective values, so facility headers/letterheads print a contact when only the tenant has one.
8. **Setup checklist.** An inherited phone satisfies "facility identity", and the checklist item says the phone is inherited.
9. **Realtime.** Tenant contact updates must refresh open facility details and print-branding caches through existing tenant/facility realtime events (`WorkspaceSyncEngine` smallest refresh). Don't add polling.

## Implementation constraints

- **Layering.** route → controller → service → repository. The helper stays stateless in `src/lib` (`backend/.cursor/architecture.mdc`, `coding-standards.mdc` — JSDoc required).
- **Contract.** Public payloads use `snake_case` and `human_friendly_id` only (`backend/.cursor/api.mdc`). Update `backend/docs/api/v1/openapi.yaml`.
- **Frontend mapping.** DTOs map the new fields explicitly (`frontend/.cursor/data_modeling.mdc`). Add the marker copy to `app_en.arb`.
- **Scope.** Module boundaries: tenant/facility settings own structure (`.cursor/app-write-up.mdc`). No schema change is expected; if one becomes necessary, follow the migration rule in `.cursor/mandatories.mdc`.

## Verification

- **Backend unit tests** for the helper: own values win; each field inherits independently; the inherited value equals `resolveTenantContact` output (extension contact first, legacy admin fallback second); `NONE` when neither exists.
- **Backend service/route tests:** the facility payload exposes effective values + sources, and a tenant contact update changes the inherited output.
- **Frontend widget tests** (`frontend/test/features/tenant_facility/presentation/`): the summary shows the "From tenant" marker; the edit form doesn't pre-fill inherited values; print branding uses effective values.
- **Run:** `cd backend && npm run lint && node scripts/run-jest.js <new/changed tests> && npm run openapi:validate`; `cd frontend && flutter gen-l10n && flutter analyze && flutter test test/features/tenant_facility/`.
- **Manual:** `/admin/setup?section=tenants`.
  1. Clear a facility's phone/email → details and a printout show tenant values marked as inherited.
  2. Add a facility phone → inheritance stops for phone only.
  3. Change the tenant email → the facility view updates without reload.

## Dependencies

None. **006** edits the same dialog file afterwards (mobile layout) — land 002 first.
