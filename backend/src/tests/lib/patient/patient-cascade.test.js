/**
 * Schema-driven coverage for the patient cascade map.
 */

const fs = require('fs');
const path = require('path');
const {
  listCascadeEntries,
  listDirectPatientFkModels,
  getSoftDeleteModels,
} = require('@lib/patient/patient-cascade');

const SCHEMA_PATH = path.resolve(
  __dirname,
  '../../../../prisma/schema.prisma'
);

const DIRECT_FK_FIELDS = [
  'patient_id',
  'participant_patient_id',
  'sender_patient_id',
];

const extractDirectPatientFkModelsFromSchema = (schemaText) => {
  const models = [];
  const modelBlocks = schemaText.matchAll(/model\s+(\w+)\s*\{([\s\S]*?)\n\}/g);
  for (const match of modelBlocks) {
    const modelName = match[1];
    const body = match[2];
    for (const field of DIRECT_FK_FIELDS) {
      const fieldRegex = new RegExp(`^\\s*${field}\\s+`, 'm');
      if (fieldRegex.test(body)) {
        models.push({ model: modelName, field });
      }
    }
  }
  return models;
};

describe('patient-cascade map', () => {
  it('covers every schema model with patient_id / participant_patient_id / sender_patient_id', () => {
    const schemaText = fs.readFileSync(SCHEMA_PATH, 'utf8');
    const schemaModels = extractDirectPatientFkModelsFromSchema(schemaText);
    expect(schemaModels.length).toBeGreaterThan(0);

    const mapped = new Map(
      listDirectPatientFkModels().map((row) => [
        `${row.model}:${row.field}`,
        row,
      ])
    );

    const missing = schemaModels.filter(
      (row) => !mapped.has(`${row.model}:${row.field}`)
    );

    expect(missing).toEqual([]);
  });

  it('declares soft-delete / restore / purge actions for every entry', () => {
    for (const entry of listCascadeEntries()) {
      expect(['soft_delete', 'retain']).toContain(entry.softDelete);
      expect(['restore', 'noop']).toContain(entry.restore);
      expect(['hard_delete', 'anonymize', 'retain']).toContain(entry.purge);
      expect(typeof entry.category).toBe('string');
      expect(entry.category.length).toBeGreaterThan(0);
      expect(['direct', 'via']).toContain(entry.reach.type);
    }
  });

  it('soft-deletes clinical and financial models while retaining audit logs', () => {
    const soft = new Set(getSoftDeleteModels());
    expect(soft.has('visit_queue')).toBe(true);
    expect(soft.has('encounter')).toBe(true);
    expect(soft.has('invoice')).toBe(true);
    expect(soft.has('phi_access_log')).toBe(false);
    expect(soft.has('break_glass_access')).toBe(false);
  });
});
