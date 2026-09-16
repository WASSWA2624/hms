/**
 * Patient deletion cascade repository
 *
 * Owns Prisma operations for cascade soft-delete, restore from manifest, and
 * permanent purge. The service orchestrates the transaction and audit/realtime.
 *
 * @module modules/patient/repositories/patient-deletion
 */

const crypto = require('crypto');
const prisma = require('@prisma/client');
const { HttpError } = require('@lib/errors');
const {
  listCascadeEntries,
  getStorageKeyEntries,
} = require('@lib/patient/patient-cascade');
const {
  purgedPatientFields,
  isPurgedPatient,
} = require('@lib/patient/purged-patient');

const modelDelegate = (client, model) => {
  const delegate = client?.[model];
  if (!delegate) {
    throw new Error(`Prisma model not available: ${model}`);
  }
  return delegate;
};

const uniqueIds = (ids = []) =>
  Array.from(new Set((Array.isArray(ids) ? ids : []).filter(Boolean)));

/**
 * Collect entity ids reachable from a patient using the cascade map.
 * Parents are collected before children so `via` reach can resolve.
 *
 * @returns {Promise<{ idsByModel: Record<string, string[]>, counts: Record<string, number> }>}
 */
const collectCascadeIds = async (client, patientId, { onlyActive = true } = {}) => {
  const idsByModel = {};
  const counts = {};

  for (const entry of listCascadeEntries()) {
    const where = {};
    if (onlyActive && entry.collectOnlyActive !== false) {
      // Models without deleted_at still work; Prisma ignores unknown filters only
      // when the field exists — every cascade model in schema has deleted_at.
      where.deleted_at = null;
    }

    if (entry.reach.type === 'direct') {
      where[entry.reach.field || 'patient_id'] = patientId;
    } else if (entry.reach.type === 'via') {
      const parentIds = idsByModel[entry.reach.parent] || [];
      if (parentIds.length === 0) {
        idsByModel[entry.model] = uniqueIds([
          ...(idsByModel[entry.model] || []),
        ]);
        counts[entry.model] = (idsByModel[entry.model] || []).length;
        continue;
      }
      where[entry.reach.parentField] = { in: parentIds };
    }

    const rows = await modelDelegate(client, entry.model).findMany({
      where,
      select: { id: true },
    });
    idsByModel[entry.model] = uniqueIds([
      ...(idsByModel[entry.model] || []),
      ...rows.map((row) => row.id),
    ]);
    counts[entry.model] = idsByModel[entry.model].length;
  }

  return { idsByModel, counts };
};

const buildCategoryCounts = (counts = {}) => {
  const byCategory = {};
  for (const entry of listCascadeEntries()) {
    const n = counts[entry.model] || 0;
    if (!n) continue;
    byCategory[entry.category] = (byCategory[entry.category] || 0) + n;
  }
  return byCategory;
};

/**
 * Soft-delete cascade + write manifest inside an existing transaction.
 */
const softDeleteCascadeInTx = async (
  tx,
  {
    patient,
    deletedByUserId = null,
    deletedAt = new Date(),
  } = {}
) => {
  const patientId = patient.id;
  const { idsByModel, counts } = await collectCascadeIds(tx, patientId, {
    onlyActive: true,
  });

  for (const entry of listCascadeEntries()) {
    if (entry.softDelete !== 'soft_delete') continue;
    const ids = idsByModel[entry.model] || [];
    if (ids.length === 0) continue;
    await modelDelegate(tx, entry.model).updateMany({
      where: { id: { in: ids }, deleted_at: null },
      data: { deleted_at: deletedAt },
    });
  }

  await tx.patient.update({
    where: { id: patientId },
    data: { deleted_at: deletedAt, is_active: false },
  });

  const batchId = crypto.randomUUID();
  const categoryCounts = buildCategoryCounts(counts);
  const countsJson = {
    by_model: counts,
    by_category: categoryCounts,
    patient: 1,
  };

  const batch = await tx.patient_deletion_batch.create({
    data: {
      id: batchId,
      tenant_id: patient.tenant_id,
      facility_id: patient.facility_id || null,
      patient_id: patientId,
      deleted_by_user_id: deletedByUserId || null,
      deleted_at: deletedAt,
      counts_json: countsJson,
    },
  });

  const itemRows = [{ entity_model: 'patient', entity_id: patientId }];
  for (const [model, ids] of Object.entries(idsByModel)) {
    for (const entityId of ids) {
      itemRows.push({ entity_model: model, entity_id: entityId });
    }
  }

  if (itemRows.length > 0) {
    await tx.patient_deletion_batch_item.createMany({
      data: itemRows.map((row) => ({
        id: crypto.randomUUID(),
        batch_id: batch.id,
        entity_model: row.entity_model,
        entity_id: row.entity_id,
      })),
    });
  }

  return {
    batch,
    counts: countsJson,
    idsByModel,
  };
};

const findLatestUnrestoredBatch = async (patientId, dbClient = prisma) =>
  dbClient.patient_deletion_batch.findFirst({
    where: {
      patient_id: patientId,
      restored_at: null,
      permanently_deleted_at: null,
      batch_deleted_at: null,
    },
    orderBy: { deleted_at: 'desc' },
    include: { items: true },
  });

const findLatestBatchIncludingRestored = async (patientId, dbClient = prisma) =>
  dbClient.patient_deletion_batch.findFirst({
    where: {
      patient_id: patientId,
      permanently_deleted_at: null,
      batch_deleted_at: null,
    },
    orderBy: { deleted_at: 'desc' },
    include: { items: true },
  });

/**
 * Restore only rows listed in the latest unrestored batch.
 */
const restoreCascadeInTx = async (tx, { patientId, batch }) => {
  if (!batch || !Array.isArray(batch.items)) {
    throw new HttpError('errors.patient.not_soft_deleted', 400);
  }

  const byModel = {};
  for (const item of batch.items) {
    if (!byModel[item.entity_model]) byModel[item.entity_model] = [];
    byModel[item.entity_model].push(item.entity_id);
  }

  // Restore children before patient so mid-tx readers see consistent parents.
  for (const entry of listCascadeEntries()) {
    if (entry.restore !== 'restore') continue;
    const ids = uniqueIds(byModel[entry.model] || []);
    if (ids.length === 0) continue;
    await modelDelegate(tx, entry.model).updateMany({
      where: { id: { in: ids } },
      data: { deleted_at: null },
    });
  }

  const patientIds = uniqueIds(byModel.patient || [patientId]);
  await tx.patient.updateMany({
    where: { id: { in: patientIds } },
    data: { deleted_at: null },
  });

  await tx.patient_deletion_batch.update({
    where: { id: batch.id },
    data: { restored_at: new Date() },
  });

  return tx.patient.findFirst({ where: { id: patientId } });
};

/**
 * Detect identifier / MRN collisions that would block restore.
 */
const findRestoreConflicts = async (tx, patient) => {
  const conflicts = [];
  const identifiers = await tx.patient_identifier.findMany({
    where: {
      patient_id: patient.id,
      deleted_at: { not: null },
    },
    select: {
      identifier_value: true,
      identifier_type: true,
    },
  });

  for (const identifier of identifiers) {
    if (!identifier.identifier_value) continue;
    const clash = await tx.patient_identifier.findFirst({
      where: {
        tenant_id: patient.tenant_id,
        identifier_value: identifier.identifier_value,
        deleted_at: null,
        patient_id: { not: patient.id },
        patient: { deleted_at: null },
      },
      select: {
        id: true,
        patient_id: true,
        identifier_type: true,
        identifier_value: true,
      },
    });
    if (clash) {
      conflicts.push({
        code: 'identifier_in_use',
        field: 'identifier_value',
        identifier_type: clash.identifier_type,
        identifier_value: clash.identifier_value,
      });
    }
  }

  if (patient.human_friendly_id) {
    const mrnClash = await tx.patient.findFirst({
      where: {
        tenant_id: patient.tenant_id,
        human_friendly_id: patient.human_friendly_id,
        deleted_at: null,
        id: { not: patient.id },
      },
      select: { id: true, human_friendly_id: true },
    });
    if (mrnClash) {
      conflicts.push({
        code: 'human_friendly_id_in_use',
        field: 'human_friendly_id',
        value: patient.human_friendly_id,
      });
    }
  }

  return conflicts;
};

const collectStorageKeys = async (client, idsByModel) => {
  const keys = [];
  for (const entry of getStorageKeyEntries()) {
    const ids = idsByModel[entry.model] || [];
    if (ids.length === 0 || !entry.storageKeyField) continue;
    const rows = await modelDelegate(client, entry.model).findMany({
      where: { id: { in: ids } },
      select: { [entry.storageKeyField]: true },
    });
    for (const row of rows) {
      const key = row?.[entry.storageKeyField];
      if (typeof key === 'string' && key.trim()) {
        keys.push(key.trim());
      }
    }
  }
  return uniqueIds(keys);
};

/**
 * Permanent purge inside a transaction. Storage keys must be deleted by the
 * service after a successful commit (or best-effort before) via StorageService.
 *
 * Prefer one transaction for v1; see migration doc if timeouts force a job.
 */
const permanentPurgeInTx = async (tx, { patient, batch }) => {
  const patientId = patient.id;
  if (isPurgedPatient(patient)) {
    throw new HttpError('errors.patient.already_purged', 404);
  }

  // Prefer manifest ids when available; otherwise collect current graph.
  let idsByModel = {};
  if (batch?.items?.length) {
    for (const item of batch.items) {
      if (item.entity_model === 'patient') continue;
      if (!idsByModel[item.entity_model]) idsByModel[item.entity_model] = [];
      idsByModel[item.entity_model].push(item.entity_id);
    }
    for (const model of Object.keys(idsByModel)) {
      idsByModel[model] = uniqueIds(idsByModel[model]);
    }
  } else {
    const collected = await collectCascadeIds(tx, patientId, {
      onlyActive: false,
    });
    idsByModel = collected.idsByModel;
  }

  const storageKeys = await collectStorageKeys(tx, idsByModel);
  const entries = listCascadeEntries();

  // Hard-delete children before parents (reverse map order).
  for (let i = entries.length - 1; i >= 0; i -= 1) {
    const entry = entries[i];
    if (entry.purge !== 'hard_delete') continue;
    const ids = idsByModel[entry.model] || [];
    if (ids.length === 0) continue;
    await modelDelegate(tx, entry.model).deleteMany({
      where: { id: { in: ids } },
    });
  }

  for (const entry of entries) {
    if (entry.purge !== 'anonymize') continue;
    const ids = idsByModel[entry.model] || [];
    if (ids.length === 0) continue;
    const data = entry.anonymizeFields || {};
    if (Object.keys(data).length === 0) continue;
    await modelDelegate(tx, entry.model).updateMany({
      where: { id: { in: ids } },
      data,
    });
  }

  // Retain-purge models stay as-is (audit / custody evidence).

  const retainedReferences =
    (await tx.invoice.count({ where: { patient_id: patientId } })) +
    (await tx.payment.count({ where: { patient_id: patientId } })) +
    (await tx.billable_charge_event.count({ where: { patient_id: patientId } })) +
    (await tx.patient_insurance_enrollment.count({
      where: { patient_id: patientId },
    })) +
    (await tx.pre_authorization.count({ where: { patient_id: patientId } })) +
    (await tx.phi_access_log.count({ where: { patient_id: patientId } })) +
    (await tx.break_glass_access.count({ where: { patient_id: patientId } })) +
    (await tx.mortuary_case.count({ where: { patient_id: patientId } }));

  if (batch?.id) {
    await tx.patient_deletion_batch.update({
      where: { id: batch.id },
      data: { permanently_deleted_at: new Date() },
    });
  }

  let anonymized = false;
  if (retainedReferences > 0) {
    await tx.patient.update({
      where: { id: patientId },
      data: {
        ...purgedPatientFields(patientId),
        deleted_at: patient.deleted_at || new Date(),
      },
    });
    anonymized = true;
  } else {
    // Drop manifests before removing the patient row (FK RESTRICT).
    await tx.patient_deletion_batch_item.deleteMany({
      where: { batch: { patient_id: patientId } },
    });
    await tx.patient_deletion_batch.deleteMany({
      where: { patient_id: patientId },
    });
    await tx.patient.delete({ where: { id: patientId } });
  }

  return {
    anonymized,
    storageKeys,
    retained_references: retainedReferences,
    counts: batch?.counts_json || null,
  };
};

const countDeletionImpact = async (patientId, dbClient = prisma) => {
  const { counts } = await collectCascadeIds(dbClient, patientId, {
    onlyActive: true,
  });
  const softDeleteCounts = {};
  for (const entry of listCascadeEntries()) {
    if (entry.softDelete !== 'soft_delete') continue;
    const n = counts[entry.model] || 0;
    if (n > 0) softDeleteCounts[entry.model] = n;
  }
  return {
    by_model: softDeleteCounts,
    by_category: buildCategoryCounts(softDeleteCounts),
  };
};

module.exports = {
  collectCascadeIds,
  buildCategoryCounts,
  softDeleteCascadeInTx,
  findLatestUnrestoredBatch,
  findLatestBatchIncludingRestored,
  restoreCascadeInTx,
  findRestoreConflicts,
  collectStorageKeys,
  permanentPurgeInTx,
  countDeletionImpact,
};
