# 005 — Patient Cascade Soft Delete, Restore and Permanent Delete

**Feedback:** FBK0000016 · **Depends on:** — · **Stack:** backend + frontend
**Index:** [000-index.md](000-index.md) (working agreements apply)

## Objective

Facility admins and admins above them can:

- **Soft delete** a patient, which cascades to everything linked to that patient.
- **Restore** that patient and exactly what the cascade removed.
- **Permanently delete** a soft-deleted patient, which purges the patient's personal and clinical data across all linked records.

All three are safe, scoped, atomic and auditable.

## Feedback covered

| Field | Value |
| :--- | :--- |
| Feedback ID | FBK0000016 |
| Submitted (EAT) | 2026-09-15 10:28:22 |
| Category | Suggestion |
| Feedback (verbatim) | "Allow facility admins and admins above them to delete patients (soft delete, then permanent delete). The soft delete and permanent delete should be cascaded to all the information linked to the patient." |
| Reporter | Position "Medical Officer" · role `FACILITY_ADMIN` · 57 permissions incl. `facility:admin`, `patient:delete` (no `tenant:admin` / `platform:admin`) |
| Tenant / facility / plan | FAIRBANKS MEDICAL CENTRE (`TEN0000003` / `FAC0000001`) · Pro · `TRIAL` |
| Screen / route | `patients` · `/patients` · `https://app.hosspi.com/patients` |
| Device | Web, Windows Chrome 152, Desktop 1280×585 @1.5x, `xl` · production · light · `en` |

## Current behavior (verified at `9cb01bb57`)

- **API:** `DELETE /api/v1/patients/:id` (`authorize(PERMISSIONS.PATIENT_DELETE)`), handled by `deletePatient` in `backend/src/modules/patient/services/patient.service.js`. It soft-deletes the `patient` row and its `visit_queue` rows only. There is **no** cascade to other records, **no** restore and **no** permanent delete. The realtime event is `patient.deleted` (`PATIENT_EVENTS` in `backend/src/lib/websocket/events.js`).
- **Who holds `patient:delete`:** only the shipped `ADMIN_ACCESS` pack (`backend/src/config/permissions.js`), i.e. `PLATFORM_OWNER`, `PLATFORM_ADMIN`, `TENANT_ADMIN`, `FACILITY_ADMIN`. Custom roles can also be granted it.
- **UI:** Delete appears only inside the patient detail dialog (`frontend/lib/features/patients/presentation/widgets/patient_detail_dialog_body.dart`, gated by `patientRegistryDeleteRequirement` in `patient_registry_access.dart`). The registry (`frontend/lib/features/patients/presentation/pages/patient_registry_page.dart`) has no deleted-records view and no row lifecycle actions.
- **Linked data:** 29 models carry `patient_id` directly — `address`, `contact`, `patient_identifier`, `patient_contact`, `patient_guardian`, `patient_allergy`, `patient_medical_history`, `patient_document`, `consent`, `appointment`, `visit_queue`, `encounter`, `admission`, `lab_order`, `radiology_order`, `pharmacy_order`, `adverse_event`, `emergency_case`, `invoice`, `billable_charge_event`, `payment`, `patient_insurance_enrollment`, `pre_authorization`, `break_glass_access`, `patient_report_job`, `phi_access_log`, `mortuary_case`, and more. Many more hang off `encounter`/`admission`/orders (vitals, notes, diagnoses, order items, results, MAR, invoice items, claims).
- **Precedent to follow:** user permanent delete (`backend/src/modules/user/services/user.service.js`, `backend/src/lib/user/purged-account.js`). It requires soft delete first, hard-deletes when nothing references the row, and otherwise keeps an anonymized tombstone.

## Required behavior

1. **Cascade map.** Build a single, tested, declarative cascade map (e.g. `backend/src/lib/patient/patient-cascade.js`). It lists every patient-linked model reachable from `patient`, how each is reached (direct `patient_id` or via parent), and its action for soft delete, restore and purge: `soft_delete` | `retain` | `anonymize` | `hard_delete`. A schema test must fail when a new model gains `patient_id` and isn't in the map.
2. **Soft delete** (`DELETE /api/v1/patients/:human_friendly_id`):
   - In one `prisma.$transaction`, set `deleted_at` on the patient and every soft-deletable linked row that isn't already deleted.
   - Persist a deletion manifest (batch id → entity → ids), e.g. a new `patient_deletion_batch` table, so restore is exact.
   - **Refuse with 409 and a localized blocker list** when the patient has live operational state: an active admission/ICU stay/theatre case, an occupied bed, an open OPD encounter, or an in-progress lab/radiology/pharmacy order.
   - Remove the patient from worklists, search and duplicate checks.
3. **Restore** (`POST /api/v1/patients/:human_friendly_id/restore`): in one transaction, clear `deleted_at` only for rows in the latest deletion manifest, never rows deleted independently before. Fail with 409 when a restore conflict exists (e.g. an identifier or MRN now used by another active patient).
4. **Permanent delete** (`DELETE /api/v1/patients/:human_friendly_id/permanent`) — only for already soft-deleted patients:
   - **Purge** personal and clinical data: hard-delete demographic, contact, guardian, identifier, document, consent, allergy, history, clinical note/vital/result rows. Delete stored files through the storage abstraction (`backend/.cursor/storage.mdc`).
   - **Retain, anonymized,** records the business or law must keep: invoices, payments, billable charges, insurance claims/pre-authorizations, accounts journal links, audit logs, `phi_access_log`, `break_glass_access`, and mortuary custody evidence. Keep the `patient` row as a tombstone ("Deleted patient", identifying fields erased, like `purged-account.js`) whenever any retained row references it; otherwise hard-delete the row.
   - Everything runs in one transaction (or a resumable job with idempotency if it's too large for one; document which and why, `backend/.cursor/performance.mdc`).
   - Irreversible: requires type-to-confirm on the client and `confirm: true` in the body.
5. **Authorization, enforced server-side:**
   - Soft delete and restore: `patient:delete` plus ABAC scope. A facility-scoped actor acts only on patients whose `facility_id` is in their facility; patients with `facility_id = null` (tenant-wide) need tenant scope.
   - Permanent delete: `patient:delete` **and** an admin grant (`facility:admin` ∪ `tenant:admin` ∪ platform elevated) plus the same scope, so a custom role with only `patient:delete` cannot purge.
   - Platform-elevated actors acting inside a tenant are capped by that tenant (`.cursor/access/permissions.mdc`).
6. **Audit and realtime.**
   - Each operation writes audit evidence with actor, scope, patient `human_friendly_id`, counts per entity, and the manifest/batch id. No PHI in the audit diff for purge (`backend/.cursor/compliance.mdc`).
   - Publish `patient.deleted`, `patient.restored`, `patient.permanently_deleted` after commit, with `human_friendly_id` only (`backend/.cursor/websockets.mdc`). Add the constants to `PATIENT_EVENTS` and the frontend `RealtimeEvents` / `RealtimeEventGroups.patients`.
7. **Registry UI** (`/patients`):
   - Record-state filter Current / Deleted / All (like other admin lists).
   - Row actions column: Delete for active rows; Restore and Permanently delete for deleted rows. Detail dialog actions match.
   - Soft delete confirm lists what will be hidden (counts per category from a preview endpoint, e.g. `GET /patients/:id/deletion-impact`) and shows blockers when refused.
   - Permanent delete uses type-to-confirm with the patient name and states what is purged versus retained anonymized.
   - `AppButton.isLoading` while running; instant row patch on success.
   - OPD/IPD/pharmacy/billing workspaces drop the patient via realtime reconciliation.
8. **Unauthorized actors don't see the actions at all** (`AppAccessActionGate`).

## Implementation constraints

- **Migration.** Prisma migration for the manifest table plus any missing `deleted_at` indexes, committed with a doc and rollback notes under `backend/docs/migrations/` (`.cursor/mandatories.mdc`, `backend/.cursor/prisma.mdc`).
- **Layering.** Repositories own model operations; the service orchestrates the transaction (`backend/.cursor/architecture.mdc`). Validation uses Zod with `human_friendly_id` params (`backend/.cursor/validation.mdc`). Update `backend/docs/api/v1/openapi.yaml`.
- **Offline.** Delete/restore/purge are online-only and must not be queued offline (`.cursor/api-contract.mdc`, `frontend/.cursor/offline_sync.mdc`).
- **Flow ownership.** Respect `.cursor/flows/*` handoffs. Deletion must not silently close encounters/admissions — that's why live state blocks.
- **Shared UI.** Shared confirm dialogs/table actions, localized copy, and design tokens (`frontend/.cursor/ui-workspace.mdc`).

## Verification

- **Backend tests** (`backend/src/tests/modules/patient/`, `backend/src/tests/lib/patient/`):
  - The cascade map covers every `patient_id` model (a schema-driven test).
  - Soft delete marks linked rows and writes the manifest; live-state blockers return 409.
  - Restore brings back only manifest rows.
  - Purge erases PHI, keeps anonymized financial/audit rows, and deletes files through storage.
  - Scope: a facility admin can't touch another facility's patients; a custom `patient:delete`-only role can't purge.
  - Audit and realtime events are emitted with `human_friendly_id` only.
- **Frontend tests** (`frontend/test/features/patients/`): record-state filter; row actions per state and per permission; blocker dialog; type-to-confirm; instant patch on success; realtime removal.
- **Run:** `cd backend && npm run prisma:migrate && npm run lint && node scripts/run-jest.js src/tests/modules/patient src/tests/lib/patient && npm run openapi:validate`; `cd frontend && flutter gen-l10n && flutter analyze && flutter test test/features/patients/`.
- **Manual (local/demo DB only, never production data):** as `FACILITY_ADMIN`:
  1. Soft-delete a patient with encounters, orders and an invoice → the patient disappears from worklists.
  2. Restore → everything is back.
  3. Soft delete again, then permanently delete → PHI is gone, invoices remain as "Deleted patient", audit exists.
  4. Try an admitted patient → blocked. Try as `DOCTOR` → no actions visible and the API returns 403.

## Dependencies

None.
