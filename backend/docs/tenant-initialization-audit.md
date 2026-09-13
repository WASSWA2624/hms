# Tenant Initialization Audit

**Fairbanks fixes — Phase 2, step 04.** Authoritative inventory of every row that
exists under a brand-new tenant, and where each row came from. Steps 05 (removal)
and 06 (platform presets) act on this document.

| | |
| :--- | :--- |
| Repo commit measured | `5ade76524bb36a811f2d23075e5f9af82f54fb8b` |
| Deployed backend on `https://api.hosspi.com` | Same code. Every file on the traced paths is byte-identical to this commit (md5, §6.1). The host keeps no git checkout, so the hash comparison is the version marker. |
| Development schema head | `20260911140000_session_lifetime_policy` |
| Production schema head | `20260911140000_session_lifetime_policy` — **identical, no drift** (§6.2) |
| Development measurement | 2026-09-12T00:22Z, `NODE_ENV=development` |
| Production measurement | 2026-09-12, `NODE_ENV=production`, read-only `count` queries only |

Reproduce with:

```bash
cd backend && npm run db:probe:tenant-init
```

```bash
cd backend && npm run db:audit:tenant-init -- --tenant=<id|slug|TEN…>
```

`audit-tenant-initialization.js` issues `count` queries only and is safe to point
at production. `probe-tenant-initialization.js` creates throwaway tenants and
refuses to run against production through `scripts/demo-safety.js`.

---

## 1. Headline finding

**No forbidden operational data is created by tenant or facility creation.** A
brand-new tenant has zero patients, visits, encounters, admissions, appointments,
prescriptions, lab orders, radiology orders, invoices, payments, bills, dispensing
records, and zero rows in every other patient-linked or transactional table. All
143 tenant-reachable tables were counted; 13 carry rows, and every one of them is
configuration or identity.

Production confirms this independently (§6.4): in the newest production tenant the
bootstrap rows were written in a 0.6-second burst 6 minutes after creation, while
every operational row appeared hours later, spread across two days of real use.

Three problems are real, and they belong to steps 05/06 rather than to a
patient-data deletion fix:

1. **A read endpoint writes 163 rows.** The first `GET` of the HR workspace
   reference data lazily creates 57 roles, 65 staff positions, 20 departments and
   20 units for the tenant. Tenant creation itself writes none of them.
2. **Those lazily-created roles carry zero permissions, and they duplicate.** On
   the fresh dev tenant: 58 tenant-scoped roles, **0** `role_permission` links. In
   production the same bootstrap has run twice on one tenant — 115 roles over 57
   distinct names, still **0** links (§6.5). The bootstrap resolves permissions by
   `tenant_id`, and a new tenant owns no `permission` rows, so every role it
   creates is an empty shell.
3. **The demo dataset is live in the production database** (§6.6): 42,843 rows
   including 1,209 synthetic patients, in a tenant that shows up in the platform
   tenant list. It is not reachable from tenant creation — an operator seeded it
   deliberately — but step 05 should decide whether it stays.

---

## 2. Code paths traced

### 2.1 Tenant creation

| Path | Entry point | Writes |
| :--- | :--- | :--- |
| Self-serve registration | `authService.register` → `authRepository.registerFacilityOwner` ([auth.repository.js:394](../src/modules/auth/repositories/auth.repository.js#L394)) | `tenant`, `facility`, `role`, `user`, `user_profile`, `user_role`, `registration_attempt` — one transaction |
| Platform-admin create | `tenantService.createTenant` ([tenant.service.js:409](../src/modules/tenant/services/tenant.service.js#L409)) → `tenantRepository.createWithDefaultFacility` ([tenant.repository.js:228](../src/modules/tenant/repositories/tenant.repository.js#L228)) | `tenant`, `facility` — one transaction |

Both then write `audit_log`, and registration additionally writes
`verification_token` and `registration_follow_up` after the commit.

### 2.2 Facility creation

`facilityService.createFacility` ([facility.service.js:422](../src/modules/facility/services/facility.service.js#L422))
inserts one `facility` row plus one `audit_log` row. **No catalog copier runs.**
The `facility-lab-catalog`, `facility-pharmacy-catalog` and
`facility-radiology-catalog` modules are never invoked from facility creation;
they are separate, operator-driven APIs.

### 2.3 Post-registration jobs

| Trigger | Code | Writes |
| :--- | :--- | :--- |
| Email verification | `authService.verifyEmail` | `audit_log` |
| Platform approval | `accessAdminWorkspaceService.approveRegistration` ([access-admin-workspace.service.js:1094](../src/modules/access-admin-workspace/services/access-admin-workspace.service.js#L1094)) → `provisionTrialSubscription` ([tenant-onboarding.js:169](../src/lib/subscriptions/tenant-onboarding.js#L169)) | `subscription` (1, 90-day Pro trial), `module_subscription` (35), `audit_log` |
| **First HR workspace read** | `hrWorkspaceService.getReferenceData` ([hr-workspace.service.js:1103](../src/modules/hr-workspace/services/hr-workspace.service.js#L1103)) → `ensureDefaultStaffPositions`, `ensureDefaultFacilityStructure`, `ensureAssignableRoles` | `staff_position` (65), `department` (20), `unit` (20), `role` (57) |

### 2.4 Prisma hooks

The only global Prisma extension is `withHumanFriendlyIdSupport`
([client.js:315](../src/prisma/client.js#L315)), which assigns a
`human_friendly_id` on create. It inserts no additional rows.

### 2.5 Paths that do *not* run at tenant creation

- `prisma/seed.js` — a dev fixture; refuses to run when `NODE_ENV=production`.
- `scripts/seed-demo-data.js` and every pack under `scripts/seeders/` — manual CLI only.
- `ensurePlatformAccessCatalog` / `consolidateTenantCatalogDuplicates` — reachable
  only from the access-admin workspace and `scripts/reseed-platform-access-catalog.js`.
- No seeding runs at server startup, on `postinstall`, `prestart`, or on
  `prisma migrate deploy`.

---

## 3. Table inventory

Measured on tenant `TEN0000014` (`Probe Org 1789172163975`,
`0eaa4a9e-357b-43f9-a85c-b5abf4f46a21`), created through self-serve registration
and carried through approval and a first HR workspace read.

| Table | Rows | Tenant-scoped | Written by | Classification |
| :--- | ---: | :--- | :--- | :--- |
| `staff_position` | 65 | `tenant_id` | first HR workspace read | ✅ Allowed initial configuration |
| `role` | 58 | `tenant_id` | 1 registration + 57 first HR read | ⚠️ Allowed, but see §5.1 |
| `module_subscription` | 35 | via `subscription` | approval → `provisionTrialSubscription` | ✅ Allowed initial configuration |
| `department` | 20 | `tenant_id` | first HR workspace read | ✅ Allowed initial configuration |
| `unit` | 20 | `tenant_id` | first HR workspace read | ✅ Allowed initial configuration |
| `audit_log` | 3 | `tenant_id` | create + verify + approve | ✅ Allowed (compliance record, not operational data) |
| `facility` | 1 | `tenant_id` | registration / tenant create | ✅ Allowed initial configuration |
| `subscription` | 1 | `tenant_id` | approval | ✅ Allowed initial configuration |
| `user` | 1 | `tenant_id` | registration | ✅ Allowed (the owner account) |
| `user_role` | 1 | `tenant_id` | registration | ✅ Allowed initial configuration |
| `user_profile` | 1 | via `user` | registration | ✅ Allowed (owner identity) |
| `verification_token` | 1 | via `user` | post-commit verification issue | ✅ Allowed (transient auth artifact) |
| `registration_follow_up` | 1 | `tenant_id` | post-commit tracking | ✅ Allowed (CRM tracking, no patient linkage) |
| `registration_attempt` | 0–1 | `tenant_id` | registration idempotency claim | ✅ Allowed (auth bookkeeping) |
| **All other 130 tables** | **0** | `tenant_id` / `facility_id` | — | ✅ Empty |

**No unclassified entries.** The 130 empty tables include every forbidden
category: `patient`, `encounter`, `visit_queue`, `admission`, `appointment`,
`invoice`, `payment`, `billable_charge_event`, and every facility-scoped clinical
table (`lab_order`, `radiology_order`, `pharmacy_order`, `dispense_log`,
`vital_sign`, `clinical_note`).

### 3.1 Per-path deltas

```
A1  self-serve registration   audit_log 1, facility 1, registration_follow_up 1,
                              role 1, user 1, user_role 1, user_profile 1,
                              verification_token 1
A1b email verified            audit_log +1
A2  registration approved     subscription +1, module_subscription +35, audit_log +1
A3  first HR workspace read   role +57, staff_position +65, department +20, unit +20
B1  platform-admin tenant     audit_log 1, facility 1
C1  additional facility       facility +1, audit_log +1
```

`B1` shows one `audit_log` row, not two: `TENANT_CREATED` is written against the
*acting* admin's `tenant_id`, so only `FACILITY_CREATED` lands on the new tenant.

---

## 4. Demo, filler and volume seeding

None of these is reachable from tenant or facility creation. Each writes into the
fixed `DemoCare General Hospital` tenant defined by `DEMO_TENANTS`
([seed-catalog.js:238](../scripts/seeders/seed-catalog.js#L238)) — they never
attach rows to a tenant created by a user.

The production opt-in below has in fact been exercised: the demo dataset is
present in the production database today, with 1,209 synthetic patients. See
§6.6.

| Entry point | Trigger in development | Trigger in production |
| :--- | :--- | :--- |
| `prisma/seed.js` (`npm run seed`) | Manual CLI | **Blocked.** Returns early when `NODE_ENV=production`. |
| `scripts/seed-demo-data.js` (`npm run db:seed:demo`) | Manual CLI | Manual CLI, and only with `ALLOW_PRODUCTION_DEMO_SEED=1`. Also run by `deploy/upload-deploys/backend.py --seed-demo`. |
| `seed-filler-pack.js` | Via `seed-demo-data.js` only, when the volume pack skipped | Same, same opt-in |
| `seed-volume-pack.js` | Via `seed-demo-data.js` only, when `SEED_RECORD_COUNT > 0` | Same, same opt-in |
| `seed-volume-extended-pack.js` | Via `seed-demo-data.js` only, when `SEED_RECORD_COUNT > 0` | Same, same opt-in |
| `scripts/reseed-platform-access-catalog.js` | Manual CLI | Manual CLI (writes platform-scoped rows only) |

### 4.1 Environment configuration

| Variable | `.env.development` | `.env.production` | In `env.template.txt`? |
| :--- | :--- | :--- | :--- |
| `SEED_RECORD_COUNT` | `1000` | `1000` | ✅ (documented as `50`) |
| `SEED_RANDOM_SEED` | `20260217` | `20260217` | ✅ |
| `ALLOW_PRODUCTION_DEMO_SEED` | unset | unset | ❌ **undocumented** |

**Gap for step 05/06:** `ALLOW_PRODUCTION_DEMO_SEED` is the single switch that
unlocks demo seeding against production, and it is missing from
`backend/env.template.txt`. It is described only in `deploy/README.md` and
`deploy/backend/DEPLOY.md`.

Note that `.env.production` carries `SEED_RECORD_COUNT=1000`. That value is inert
on its own — `seed-demo-data.js` still refuses to run without the override — but
it means an operator who sets the override gets a 1000-row volume seed by default
rather than a curated-only one.

---

## 5. Findings and removal targets

**Tenant creation produces no forbidden operational data**, so step 05 has no
deletion work against the patient or transactional tables of a newly created
tenant — in either environment. The items below are what step 05 and step 06
should actually act on. One of them (§6.6, the seeded demo tenant in the
production database) does involve patient rows, but it arrives from an operator
running the demo seeder, not from tenant creation.

### 5.1 Tenant-local role clones are created empty — and on a read

- **Where:** `ensureAssignableRoles` ([hr-workspace.service.js:1568](../src/modules/hr-workspace/services/hr-workspace.service.js#L1568)),
  reached from `getReferenceData` ([hr-workspace.service.js:1105](../src/modules/hr-workspace/services/hr-workspace.service.js#L1105)).
- **Measured:** 58 tenant-scoped roles, **0** `role_permission` links.
- **Cause:** the function resolves permission ids with
  `prisma.permission.findMany({ where: { tenant_id: resolvedTenantId } })`. A new
  tenant owns no `permission` rows — the catalog is platform-scoped
  (`tenant_id: null`) since `platform-access-catalog.js` — so `permissionIdByName`
  is empty and every `role_permission` insert is skipped.
- **Removal target (step 06/09):** delete the tenant-local role cloning and read
  the platform role catalog instead. This is exactly what step 09 (global default
  roles) is for.
- **Cleanup for existing tenants:** re-point `user_role` rows at the platform
  role of the same name, then soft-delete the tenant-local clones.
  `consolidateTenantCatalogDuplicates` in
  `@lib/authorization/permission-catalog-sync` already does this shape of work.
- **Update 2026-09-13 — done.** No path creates tenant copies any more:
  `ensureAssignableRoles` is gone and HR reads platform roles, registration and
  doctor onboarding assign the platform `TENANT_ADMIN` / `DOCTOR` roles, the
  ambulance-operator backfill only seeds the platform role, and role/permission
  create, rename and restore refuse a platform name for a tenant.
  `consolidateTenantCatalogDuplicates` now matches every platform role and
  permission by name, moves user assignments, permission links and API-key
  grants onto the platform row, and deletes the copy; a role copy granting more
  than its platform role is reported under `needs_review` instead. Run
  `node scripts/sync-permission-catalog.js --dry-run`, review, then run it
  without `--dry-run`. Development went from 233 role and 416 permission copies
  to none.

### 5.2 A GET endpoint performs writes

- **Where:** `getReferenceData` calls `ensureDefaultStaffPositions`,
  `ensureDefaultFacilityStructure` and `ensureAssignableRoles` before reading.
- **Impact:** 163 rows appear on first page load. None of the three helpers is
  transactional, and each guards only on a prior `count`.
- **Confirmed in production:** the guard does not hold. `FAIRBANKS MEDICAL CENTRE`
  ran the role bootstrap on 2026-09-10 and again on 2026-09-11, ending with 115
  roles over 57 names (§6.5). Every extra page load is a candidate for another
  duplicate set.
- **Removal target (step 06):** move these presets behind the platform-presets
  model so they are either applied once at tenant creation or served from
  platform scope without per-tenant rows.

### 5.3 Legacy tenant-scoped permission rows

- **Development:** 501 `permission` rows — 85 platform-scoped (`tenant_id: null`)
  and 416 tenant-scoped across 5 tenants at ~83 each.
- **Production:** 170 `permission` rows — 85 platform-scoped and 85 tenant-scoped,
  and all 85 tenant-scoped rows belong to the seeded `DemoCare` tenant. The real
  production tenant has **none**.
- **The fresh tenant has 0.** No current code path creates tenant-scoped
  permissions, so development's 416 are residue from a pre-consolidation build and
  production's 85 come from the demo seeder.
- **Cleanup:** development needs
  `scripts/reseed-platform-access-catalog.js`, whose
  `consolidateTenantCatalogDuplicates` pass exists for this. Production needs it
  only if the demo tenant stays (§6.6).

### 5.4 `TENANT_CREATED` audit rows are attributed to the acting admin's tenant

- **Where:** [tenant.service.js:462](../src/modules/tenant/services/tenant.service.js#L462)
  passes `tenant_id: context.tenant_id`, not the created tenant's id.
- **Impact:** a tenant's own audit trail does not contain its creation event.
  Flagged here for step 49 (audit trail verification); no action in step 05.

---

## 6. Production reconciliation

Measured read-only on `hosspi.com` against `.env.production`. Only `count`,
`findMany(select)` and `SELECT` on `_prisma_migrations` ran. Nothing was seeded,
mutated or deleted.

### 6.1 Deployed code

The production host has no git checkout, so the deployed version was established
by md5-comparing every file on the traced paths against this commit:

| File | Result |
| :--- | :--- |
| `src/modules/auth/services/auth.service.js` | identical |
| `src/modules/auth/repositories/auth.repository.js` | identical |
| `src/modules/tenant/services/tenant.service.js` | identical |
| `src/modules/facility/services/facility.service.js` | identical |
| `src/modules/hr-workspace/services/hr-workspace.service.js` | identical |
| `src/lib/subscriptions/tenant-onboarding.js` | identical |
| `package.json` | differs — this audit added two `db:*` script aliases locally |

**Both environments are running the same tenant-creation code.** Node on the host
is v24.20.0.

### 6.2 Schema revision

| | Development | Production |
| :--- | :--- | :--- |
| Head migration | `20260911140000_session_lifetime_policy` | `20260911140000_session_lifetime_policy` |
| Distinct migrations applied | 106 | 106 |
| Rows in `_prisma_migrations` | 111 | 106 |
| Matches repo `prisma/migrations/` exactly | yes | yes |

**No schema drift.** Development carries 5 duplicate `_prisma_migrations` rows —
`20260809140000_rename_nurse_roster_to_roster`, `20260811130000_chart_account`,
`20260813190000_fiscal_period`, `20260814180000_department_cost_centre`,
`20260816090000_sync_schema_drift` — each recorded twice from a re-applied local
run. Bookkeeping only; the applied schema is the same in both environments.

### 6.3 Most recently created production tenant

`FAIRBANKS MEDICAL CENTRE` (`TEN0000003`, `ded22872-0b57-4ca6-a958-37301085e848`),
created 2026-09-10T06:45:37Z. 143 tables scanned, 36 with rows, 432 rows total.

| Table | Prod | Dev fresh | Reconciliation |
| :--- | ---: | ---: | :--- |
| `audit_log` | 129 | 3 | Real activity over 2 days |
| `role` | **115** | 58 | **Bootstrap ran twice** — see §6.5 |
| `staff_position` | 65 | 65 | ✅ exact match |
| `module_subscription` | 35 | 35 | ✅ exact match |
| `department` | 20 | 20 | ✅ exact match |
| `unit` | 20 | 20 | ✅ exact match |
| `facility`, `subscription`, `user_role`, `registration_follow_up`, `verification_token` | 1 each | 1 each | ✅ exact match |
| `user`, `user_profile` | 2 | 1 | Second staff account created by hand |
| `patient` | 2 | 0 | Real use — see §6.4 |
| `invoice`, `payment`, `billable_charge_event`, `patient_contact` | 3 each | 0 | Real use |
| `billing_approval`, `phi_access_log`, `contact`, `pharmacy_storage_shelf` | 2 each | 0 | Real use |
| `encounter`, `visit_queue`, `appointment`, `staff_profile`, `patient_identifier`, `drug`, `inventory_item`, `supplier`, `address`, `drug_inventory_map`, `facility_pharmacy_offering`, `inventory_stock`, `pharmacy_storage_room` | 1 each | 0 | Real use |
| `stock_movement` | 4 | 0 | Real use |

**The configuration profile matches development exactly** for every table the
creation and bootstrap paths write, with the single exception of `role`.

### 6.4 The production operational rows are real usage, not seeding

Row-creation timestamps settle it. The tenant was created at 06:45:37Z; the lazy
bootstrap fired at 06:51:49Z and wrote all 105 staff-position/department/unit rows
inside **0.6 seconds** — the signature of a machine-written batch. Every
operational row, by contrast, is minutes to hours apart and spread across two days:

| Table | First row | Last row | Days |
| :--- | :--- | :--- | :-: |
| `patient` | 09:40:39 | 10:25:26 | 1 |
| `invoice` | 09:42:41 | 10:45:28 | 1 |
| `payment` | 10:07:21 | 2026-09-11 15:03:46 | 2 |
| `appointment` | 10:21:20 | 10:21:20 | 1 |
| `encounter` | 10:31:30 | 10:31:30 | 1 |
| `drug` | 09:30:03 | 09:30:03 | 1 |
| `staff_profile` | 10:40:09 | 10:40:09 | 1 |

The earliest patient appears **2h 55m** after the tenant existed, interleaved with
invoices, payments and a second user account. No seeder produces that pattern.

**Conclusion: production confirms the development finding.** Tenant creation seeds
no operational data in either environment.

### 6.5 Role duplication is confirmed in production

`FAIRBANKS MEDICAL CENTRE` holds 115 tenant-scoped roles across **57 distinct
names — every one of them duplicated**, in three creation clusters:

| Cluster | Rows | Source |
| :--- | ---: | :--- |
| 2026-09-10 06:45 | 1 | `TENANT_ADMIN` from registration |
| 2026-09-10 06:51 | 57 | first HR workspace read |
| 2026-09-11 13:59 | 57 | HR workspace read a day later — **the guard did not hold** |

`role_permission` links across all 115: **0**. The empty-shell defect from §5.1 is
present in production, and the `ensureAssignableRoles` idempotency guard is
demonstrably not idempotent. This makes §5.1 and §5.2 higher priority than the
development-only measurement suggested.

### 6.6 The demo dataset is live in the production database

`DemoCare General Hospital` (`TEN-9322E26AFD`), created 2026-08-16, holds
**42,843 rows across 112 tables**, including:

| Table | Rows |
| :--- | ---: |
| `audit_log` | 5,022 |
| `stock_movement` | 5,001 |
| `stock_adjustment` | 2,232 |
| `clinical_term_catalog` | 1,736 |
| `report_run` | 1,356 |
| **`patient`** | **1,209** |
| `invoice` | 1,207 |
| `payment` | 1,072 |
| `phi_access_log` | 1,019 |
| `encounter` | 1,009 |
| `admission`, `appointment`, `visit_queue`, `mortuary_case`, `emergency_case`, `consent`, `patient_allergy`, `patient_medical_history`, `patient_insurance_enrollment` | ~1,000 each |

This is `seed-demo-data.js` with `SEED_RECORD_COUNT=1000`, run deliberately against
production via the `ALLOW_PRODUCTION_DEMO_SEED=1` override. It is **not** reachable
from tenant creation and it did not touch the Fairbanks tenant — but 1,209
synthetic patient records and 1,019 PHI access-log rows live in the production
database, inside a tenant that appears in the platform tenant list.

Production tenant totals: 2 tenants, 1,211 patients — of which **1,209 are demo
data**. Platform-wide `permission`: 170 rows, 85 platform-scoped and 85
tenant-scoped (all 85 belonging to DemoCare, from the seeder). Platform-wide
`role`: 483, of which 70 platform-scoped and 413 tenant-scoped (298 DemoCare +
115 Fairbanks).

**For step 05:** decide whether the demo tenant belongs in the production database
at all. It is isolated and upsert-based, so removing it is a scoped operation
(`scripts/clear-demo-data.js`, which the safety guard blocks against production by
design and would need a deliberate, reviewed exception).

---

## 7. Step 05 outcome

Step 05 acted on this audit. Summary of what changed and what was deliberately
left alone.

### 7.1 Nothing had to be removed from the creation paths

The audit found no forbidden insert in tenant or facility creation, so there was
no operational seeding to delete. Instead the invariant is now enforced so it
cannot regress:

| Guarantee | Where |
| :--- | :--- |
| One definition of allowed vs forbidden tables | [`src/lib/tenant/tenant-initialization-policy.js`](../src/lib/tenant/tenant-initialization-policy.js) |
| No tenant-reachable table left unclassified | `tenant-initialization-policy.test.js` |
| Creation paths write only configuration and identity | `tenant-creation-writes.test.js` |
| Demo seeding unreachable from any request path | `demo-seed-unreachable.test.js` |
| Onboarding leaves zero operational rows | `scripts/verify-onboarding-e2e.js` |

The classification covers all 141 tenant-reachable tables: 76 allowed as
configuration or presets, 65 forbidden. A newly added model is forbidden by
default, so whoever adds one has to classify it on purpose.

### 7.2 Demo seeding is now structurally gated

`src/server.js` stamps `HMS_PROCESS_ROLE=api-server` before it starts listening,
and `scripts/seeders/seed-runtime.js` throws if it is loaded in that process.
The guard does not branch on `NODE_ENV`, so development and production behave
identically. `ALLOW_PRODUCTION_DEMO_SEED` is now documented in
`backend/env.template.txt` with explicit guidance to leave it unset.

### 7.3 Cleanup script

[`scripts/clean-tenant-operational-seed.js`](../scripts/clean-tenant-operational-seed.js)
(`npm run db:clean:tenant-operational-seed`) reports per tenant and deletes only
on `--yes`. It distinguishes seeder-owned demo tenants — where every operational
row is demo data — from real tenants, where only rows carrying the
`extension_json.seed_pack` marker are removed. Clearing unmarked rows from a real
tenant additionally requires `--include-unmarked --i-have-a-backup`. Production is
blocked by `scripts/demo-safety.js`.

Verified on development: dry-run report, backup guard refusal, marked-only
delete, idempotent re-run, then a confirmed full delete.

### 7.4 Production exceptions

Neither pre-existing production tenant was cleaned. Both are documented here as
deliberate exceptions.

| Tenant | Operational rows | Decision |
| :--- | :--- | :--- |
| `FAIRBANKS MEDICAL CENTRE` (`TEN0000003`) | 432 rows over 36 tables | **Keep.** §6.4 established these are real user activity — 2 patients, 3 invoices, 3 payments created hours apart across two days. Deleting them would destroy live customer data. Not seeded, so not in scope for this step. |
| `DemoCare General Hospital` (`TEN-9322E26AFD`) | 42,843 rows over 112 tables, incl. 1,209 synthetic patients | **Keep for now, pending a decision.** Seeder-owned and safely removable by the cleanup script, but removal is a product call, not a code-correctness one: it is the dataset behind demos on the live host. The safety guard blocks the script against production by design, so removing it needs a deliberate, reviewed exception. |

The step 05 invariant is about what tenant creation *produces*. Neither exception
is produced by tenant creation, and both are now provably impossible to recreate
through a request path.

### 7.5 Production verification after deployment

Deployed 2026-09-12 via `deploy/update-deploys/backend.py` then
`deploy/upload-deploys/backend.py`. The release took a code backup
(`~/api-backup-20260912-040852.tar.gz`) and a database backup
(`~/db-backup-20260912-040852.sql.gz`) first, applied no migrations — the change
carries none — and skipped demo seeding. The before/after row census recorded 232
tables with no table losing rows.

A verification tenant was then created on `https://api.hosspi.com` through the
deployed onboarding path:

| | |
| :--- | :--- |
| Tenant | `E2E Org 1789175531863` (`TEN0000008`, `8513bd2c-f769-403f-b1d6-d85242891a6b`) |
| Created | 2026-09-12T01:12:12Z |
| Tables with rows | 10 of 143 — `module_subscription` 35, `audit_log` 4, and one row each of `facility`, `role`, `subscription`, `user`, `user_profile`, `user_role`, `verification_token`, `registration_follow_up` |
| Operational tables checked | 65 |
| **Operational rows found** | **0** |

It carries 1 role rather than 58, because nobody has opened its HR workspace —
which is the lazy bootstrap of §5.2 showing through, exactly as documented.

Both safety guards were exercised against production and behave as designed:

| Guard | Result on production |
| :--- | :--- |
| `clean-tenant-operational-seed.js` | Refused, exit 1 — demo-safety blocks it |
| `seed-runtime.js` with `HMS_PROCESS_ROLE=api-server` | Refused to load |

---

## Acceptance criteria

| AC | State |
| :-- | :--- |
| **AC1** — every table written by tenant/facility creation listed with its code path | ✅ §2, §3 |
| **AC2** — every listed table classified, none unclassified | ✅ §3 |
| **AC3** — every demo/filler/volume entry point documented with per-environment trigger | ✅ §4 |
| **AC4** — production counts attached and reconciled against development | ✅ §6.3, §6.4, §6.6 |
| **AC5** — each forbidden entry names its removal target and cleanup | ✅ §5, §6.6 — tenant creation produces no forbidden entries; the real removal targets are recorded instead |
| **AC6** — audit reflects code and data of both environments at the same commit | ✅ §6.1, §6.2 — identical code on the traced paths, identical schema head |
