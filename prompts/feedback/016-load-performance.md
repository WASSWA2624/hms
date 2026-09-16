# 016 — Load Performance: Dashboard, Schedule Appointment, Start OPD Encounter

**Feedback:** FBK0000028, FBK0000029, FBK0000030 · **Depends on:** 001–015 (soft: profile the shipped UI) · **Stack:** backend + frontend
**Index:** [000-index.md](000-index.md) (working agreements apply)

## Objective

Make the three reported surfaces feel instant and actually load faster in production web:

- **Home dashboard (`/`):** first meaningful content paints quickly, and the rest fills in progressively.
- **Reception "Schedule appointment" dialog (`/reception`):** opens on click, without waiting for a registry refresh.
- **OPD "Start encounter" dialog (`/opd`):** the form is usable as soon as its essential lookups arrive; secondary data loads inline.

Measure before and after, fix the proven bottlenecks, and add guards so they don't regress.

## Feedback covered

| Field | FBK0000030 | FBK0000029 | FBK0000028 |
| :--- | :--- | :--- | :--- |
| Submitted (EAT) | 2026-09-16 00:40:52 | 2026-09-16 00:39:53 | 2026-09-16 00:34:50 |
| Category | Problem | Problem | Problem |
| Feedback (verbatim) | "The dashboard screen content takes long to load/render" | "The start OPD Encounter takes long to load UI contents" | "The schedule appointment dialog takes long to load" |
| Screen / route | `home` · `/` | `opd` · `/opd` | `reception` · `/reception` |

**Shared context (all three):**

- **Reporter:** Platform Administrator, `PLATFORM_ADMIN` in tenant context (59 permissions, so the widest dashboard profile).
- **Tenant:** DemoCare General Hospital (demo tenant with volume seed data), Pro `ACTIVE`.
- **Client:** production `https://app.hosspi.com`, Flutter web on Windows Chrome 152, viewport 1280×585 @1.5x (display 853×480), `xl`, light, `en`, online, client in Uganda.
- **Timing:** reported within 6 minutes in one session, so these are warm-app navigations, not first boot.

## Current behavior and suspects (verified in code at `9cb01bb57`; timing is unmeasured)

- **Schedule appointment (FBK0000028):**
  - `openReceptionScheduleAppointment` (`frontend/lib/features/reception/presentation/widgets/reception_patient_actions.dart`) first reads `patientRegistryControllerProvider`.
  - If there's no cached state (typical on `/reception`), it **awaits `patientRegistryControllerProvider.notifier.refresh()`** — a full patient registry load — **before** calling `showAppDialog`. No loading feedback is shown during that wait.
  - The dialog only needs `referenceData` (+ `PatientRegistrationScope`), not the registry list.
- **Start OPD encounter (FBK0000029):**
  - `showOpdEncounterDialog` (`frontend/lib/shared/components/opd_encounter_dialog.dart`) fires five lookups on open: `_loadPatientOptions` (page 50), `_loadAppointmentOptions`, `_loadProviderOptions`, `_loadPatientReferenceData`, `_loadBillingDefaults`.
  - `_isInitialLoading` ORs all five, and `_showLoadingOverlay` covers the **whole form** with an opaque `AppLoadingIndicator` and blocks dismiss (`_blocksDismiss`) until the **slowest** one returns.
  - Reference data and providers are refetched on every open; there's no cache.
- **Dashboard (FBK0000030):**
  - `HomePage` (`frontend/lib/features/home/presentation/pages/home_page.dart`) watches `homeCoreControllerProvider` (phase `core`), `homeControllerProvider` (phase `full`) and `homeLookupsControllerProvider`. All are `FutureProvider.autoDispose`, so each visit to `/` can refetch everything.
  - Backend: `dashboard-workspace.service.js` builds platform/tenant/facility summaries with many `Promise.all` aggregate queries (`phase = 'core'` versus `'full'`).
  - For a platform admin inside a Pro demo tenant, the `full` phase spans most modules over volume seed data.
- **Existing guard pattern:** `frontend/test/features/tenant_facility/presentation/tenant_facility_setup_performance_test.dart` asserts load-shape decisions (context-only bootstrap). Reuse that style.

## Required behavior

1. **Baseline first.** Record a reproducible baseline and put it in the PR:
   - **Client:** Flutter web **release** build, Chrome DevTools Performance + Network. Time from click/navigation → first content → fully interactive, request count, largest payloads.
   - **Server:** per-endpoint p50/p95 latency and query counts on a production-sized dataset (demo tenant volume seed). Use Prisma query logging, or add `Server-Timing` headers behind a config flag.
   - **Network:** note the RTT from the client region.
   - Don't optimize without numbers (`backend/.cursor/performance.mdc`: "Profile before introducing caches").
2. **Schedule appointment.**
   - Open the dialog immediately with an inline loading state (`AppLoadingIndicator` with a localized title).
   - Load **only** patient reference data, through a shared cached provider: keep-alive with an explicit invalidation on reference-data realtime events or tenant/facility switch.
   - Never refresh the registry list to open this dialog.
3. **Start OPD encounter.**
   - Split essential from secondary lookups. Patient search is remote and debounced; providers and reference data come from the shared cached providers; billing defaults and appointments load after the form is interactive.
   - Replace the full-form overlay with per-field/section loading (a field shows its own spinner or skeleton; submit is disabled until required lookups exist).
   - Dismiss must never be blocked by loading — only by an in-flight save.
   - Deduplicate identical concurrent requests.
4. **Dashboard.**
   - Paint the `core` phase as soon as it arrives, with section skeletons for `full`-phase panels. Load lookups lazily when a panel needs them.
   - Keep the last successful dashboard for the same session scope while revalidating: stale-while-revalidate within the session, so returning to `/` is instant. Keep the existing scope-change safety (`_awaitingFreshDashboard`) so another account's metrics are never shown.
   - Backend: fix what profiling finds — N+1 or unindexed aggregates (add indexes via migration), over-wide `select`/`include`, per-module queries that can be batched. Consider a short-TTL, tenant/facility/role-scoped cache for expensive aggregates, invalidated by the same domain events that drive dashboard realtime.
   - Realtime deltas (`home_dashboard_sync.dart`, `home_dashboard_optimistic_patch.dart`) must keep working.
5. **Payloads and requests.** Remove unused fields from these three responses, and confirm gzip/brotli compression is enabled on API responses in production. No surface may issue duplicate identical GETs during one open.
6. **Targets** (verify on the release build against the reporter-like setup; adjust with PR evidence):
   - Dialogs visible in < 150 ms after click.
   - OPD form interactive in < 1 s at p50.
   - Dashboard core content in < 1 s and full content in < 2.5 s at p50 on warm navigation.
   - Endpoint p95 < 800 ms for the dashboard core phase and each dialog lookup.
7. **Regression guards.**
   - Tests that assert the load shape: the appointment dialog doesn't call registry refresh; the OPD dialog renders the form while secondary lookups are pending; the dashboard keeps prior data on revisit.
   - Backend tests asserting query counts / narrow selects for the dashboard core phase.

## Implementation constraints

- **Loading feedback** follows `.cursor/mandatories.mdc`: localized, region-level loaders, `AppButton.isLoading` for in-place actions.
- **Caching.** Riverpod is the single source of truth; caches live in providers with explicit invalidation — no ad-hoc static caches (`frontend/.cursor/state_management.mdc`, `performance.mdc`, `instant_ui_sync.mdc`). Realtime reconciles with the smallest refresh (`realtime_sync.mdc`).
- **Backend.** Keep changes inside module layers; expensive work stays off the request thread where possible; indexes via committed migrations (`backend/.cursor/performance.mdc`, `prisma.mdc`, `architecture.mdc`).
- **Access and scope.** Caches are keyed by tenant/facility/actor scope and must not leak data across sessions (`backend/.cursor/auth-security.mdc`, `frontend/.cursor/security.mdc`). Permission filtering of dashboard atoms (`filterHomeDashboardForAccess`) is unchanged.
- **Flows.** Don't alter OPD/reception flows (`.cursor/flows/opd-flow.mdc`).

## Verification

- **Frontend tests:**
  - `frontend/test/features/reception/`: opening Schedule appointment with an empty registry cache shows the dialog immediately and never calls registry refresh.
  - `frontend/test/shared/components/` or `frontend/test/features/opd/`: the OPD encounter dialog renders interactive fields while billing defaults/appointments are pending; dismiss works while loading.
  - `frontend/test/features/home/`: revisiting home within the session shows cached content while revalidating; a scope change still blanks it.
- **Backend tests:** `backend/src/tests/modules/dashboard-workspace/` — the core phase issues bounded queries with narrow selects; the cache is scoped and invalidated.
- **Run:** `cd frontend && flutter gen-l10n && flutter analyze && flutter test test/features/reception test/features/opd test/features/home test/shared/components`; `cd backend && npm run lint && node scripts/run-jest.js src/tests/modules/dashboard-workspace`.
- **Manual (release web build against a production-sized DB):**
  1. As platform admin in the demo tenant at 1280×585 @1.5x: `/` → `/reception` → Schedule appointment → close → `/opd` → Start encounter → back to `/`.
  2. Record before/after timings and request counts in the PR; spot-check Android.

## Dependencies

Soft dependency on **001–015**: run the baseline after those UI changes land so measurements reflect shipped screens. No code dependency.
