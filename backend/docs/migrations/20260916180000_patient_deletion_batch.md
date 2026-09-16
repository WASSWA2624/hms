# Patient deletion batch (20260916180000)

## Affected tables

- `patient_deletion_batch` (new): one row per patient soft-delete cascade. Stores
  actor, timestamps (`deleted_at`, `restored_at`, `permanently_deleted_at`), and
  `counts_json` (per-entity counts for audit/preview). Soft-delete of the batch
  row itself uses `batch_deleted_at` so it does not collide with the cascade
  `deleted_at` marker.
- `patient_deletion_batch_item` (new): manifest of every entity id soft-deleted
  with the batch (`entity_model` + `entity_id`), including the patient row.
  Restore clears `deleted_at` only for these ids.
- Indexes: `patient_id`, `batch_id`, `(entity_model, entity_id)`, and the
  lifecycle timestamp columns used by restore/purge lookups.
- No change to existing patient clinical tables in this migration; cascade
  queries already use existing `deleted_at` indexes on those models.

## Deployment

1. Apply migration `20260916180000_patient_deletion_batch`
   (`npm run prisma:migrate:deploy`) after `20260916120000_feedback_filter_indexes`.
2. Deploy application code that writes and reads these tables.
3. Verify soft-delete of a patient creates a batch + items, restore clears only
   those rows, and permanent delete sets `permanently_deleted_at`.

## Recovery

Forward-only additive tables. To roll back, add
`rollback_20260916180000_patient_deletion_batch` that drops
`patient_deletion_batch_item` then `patient_deletion_batch` (FK order). Soft-
deleted patients remain soft-deleted; without the manifest, restore of those
batches is unavailable until data is restored from backup.

## Transaction note (v1)

Cascade soft-delete, restore, and permanent purge run in a single
`prisma.$transaction` with ordered hard-deletes (children before parents). If a
tenant's patient graph regularly exceeds transaction timeouts, promote purge to
a resumable job keyed by `patient_deletion_batch.id` (idempotent per batch);
v1 prefers one transaction for correctness of the restore manifest.
