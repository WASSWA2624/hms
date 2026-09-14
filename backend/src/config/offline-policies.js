const normalizePath = (value) =>
  `/${String(value || '')
    .trim()
    .replace(/^\/+/, '')
    .toLowerCase()}`;

const NO_STORE_PREFIXES = Object.freeze([
  '/api/v1/auth',
  '/api/v1/patients',
  '/api/v1/patient-contacts',
  '/api/v1/patient-guardians',
  '/api/v1/patient-allergies',
  '/api/v1/patient-medical-histories',
  '/api/v1/patient-reports',
  '/api/v1/encounters',
  '/api/v1/clinical-notes',
  '/api/v1/nursing-notes',
  '/api/v1/medication-administrations',
  '/api/v1/clinical-alerts',
  '/api/v1/refunds',
  '/api/v1/payments',
  '/api/v1/billing',
  '/api/v1/billing-adjustments',
  '/api/v1/invoices',
  '/api/v1/invoice-items',
  '/api/v1/audit-logs',
  '/api/v1/phi-access-logs',
  '/api/v1/data-processing-logs',
  '/api/v1/breach-notifications',
  '/api/v1/system-change-logs',
  '/api/v1/abac-policies',
  '/api/v1/break-glass-access',
  '/api/v1/break-glass-reviews',
  '/api/v1/office-contexts',
  '/api/v1/shift-closes',
  '/api/v1/day-closes',
  '/api/v1/handovers',
  '/api/v1/custody-snapshots',
  '/api/v1/closeout-packs',
  '/api/v1/feedback',
]);

const SAFE_LIST_SYNC_PREFIXES = Object.freeze([
  '/api/v1/appointments',
  '/api/v1/visit-queues',
  '/api/v1/shifts',
  '/api/v1/shift-assignments',
  '/api/v1/inventory-items',
  '/api/v1/inventory-stocks',
  '/api/v1/equipment-work-orders',
  '/api/v1/report-runs',
]);

const CONDITIONAL_MUTATION_PREFIXES = Object.freeze([
  '/api/v1/equipment-work-orders',
  '/api/v1/shift-closes',
  '/api/v1/day-closes',
  '/api/v1/handovers',
  '/api/v1/custody-snapshots',
  '/api/v1/closeout-packs',
  '/api/v1/break-glass-access',
  '/api/v1/break-glass-reviews',
]);

const IDEMPOTENCY_DISABLED_PREFIXES = Object.freeze([
  '/api/v1/auth',
  '/api/v1/break-glass-access',
  '/api/v1/break-glass-reviews',
  '/api/v1/closeout-packs',
]);

/** Mutations that must never be queued for offline execution. */
const ONLINE_ONLY_MUTATION_PREFIXES = Object.freeze([
  '/api/v1/auth',
  '/api/v1/refunds',
  '/api/v1/payments',
  '/api/v1/billing',
  '/api/v1/billing-adjustments',
  '/api/v1/invoices',
  '/api/v1/invoice-items',
  '/api/v1/break-glass-access',
  '/api/v1/break-glass-reviews',
  '/api/v1/shift-closes',
  '/api/v1/day-closes',
  '/api/v1/closeout-packs',
  '/api/v1/patient-reports',
  '/api/v1/office-contexts',
]);

const matchesAnyPrefix = (path, prefixes) =>
  prefixes.some((prefix) => path === prefix || path.startsWith(`${prefix}/`));

const resolveOfflinePolicy = (req) => {
  const path = normalizePath(req?.originalUrl || req?.url || req?.path);
  const method = String(req?.method || 'GET').toUpperCase();
  const isMutation = ['POST', 'PUT', 'PATCH', 'DELETE'].includes(method);

  const cache =
    matchesAnyPrefix(path, NO_STORE_PREFIXES)
      ? 'no-store'
      : method === 'GET' || method === 'HEAD'
        ? matchesAnyPrefix(path, SAFE_LIST_SYNC_PREFIXES)
          ? 'sync'
          : 'revalidate'
        : 'no-store';

  const onlineOnly =
    isMutation && matchesAnyPrefix(path, ONLINE_ONLY_MUTATION_PREFIXES);

  return {
    path,
    cache,
    allow_validators: cache === 'revalidate' || cache === 'sync',
    allow_sync_metadata: cache === 'sync',
    allow_idempotency: !matchesAnyPrefix(path, IDEMPOTENCY_DISABLED_PREFIXES),
    online_only: onlineOnly,
    // Online-only financial / closeout mutations must not be queued offline.
    allow_offline_queue: isMutation ? !onlineOnly : true,
    require_conditional_mutation:
      isMutation && matchesAnyPrefix(path, CONDITIONAL_MUTATION_PREFIXES),
  };
};

module.exports = {
  NO_STORE_PREFIXES,
  SAFE_LIST_SYNC_PREFIXES,
  CONDITIONAL_MUTATION_PREFIXES,
  IDEMPOTENCY_DISABLED_PREFIXES,
  ONLINE_ONLY_MUTATION_PREFIXES,
  normalizePath,
  resolveOfflinePolicy,
};
