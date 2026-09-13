/**
 * Foreign keys that point at a table, read from the live database schema.
 *
 * Prisma's runtime datamodel omits relation scalar fields (`relationFromFields`),
 * so the database's own constraint catalog is the reliable answer to "which rows
 * reference this record". Table and column names only ever come from
 * `information_schema`, and row ids are always bound parameters.
 *
 * @module lib/database/foreign-key-references
 */

/** @type {Map<string, { table: string, column: string }[]>} */
const referenceCache = new Map();

const SAFE_IDENTIFIER = /^[A-Za-z0-9_]+$/;

const quoteIdentifier = (name) => {
  const value = String(name || '');
  if (!SAFE_IDENTIFIER.test(value)) {
    throw new Error(`Refusing unsafe SQL identifier: ${value}`);
  }
  return `\`${value}\``;
};

/**
 * @param {Object} client - Prisma client or interactive transaction client
 * @param {string} table - Referenced table
 * @returns {Promise<{ table: string, column: string }[]>}
 */
const listForeignKeyReferences = async (client, table) => {
  if (referenceCache.has(table)) {
    return referenceCache.get(table);
  }

  const rows = await client.$queryRaw`
    SELECT TABLE_NAME AS table_name, COLUMN_NAME AS column_name
    FROM information_schema.KEY_COLUMN_USAGE
    WHERE TABLE_SCHEMA = DATABASE()
      AND REFERENCED_TABLE_NAME = ${table}
      AND REFERENCED_COLUMN_NAME = 'id'
    ORDER BY TABLE_NAME, COLUMN_NAME
  `;

  const references = rows.map((row) => ({
    table: String(row.table_name ?? row.TABLE_NAME),
    column: String(row.column_name ?? row.COLUMN_NAME),
  }));
  referenceCache.set(table, references);
  return references;
};

const inClause = (ids) => (Array.isArray(ids) ? ids : [ids]).filter(Boolean);

/**
 * @param {Object} client - Prisma client or interactive transaction client
 * @param {{ table: string, column: string }} reference
 * @param {string|string[]} ids - Referenced row ids
 * @returns {Promise<number>}
 */
const countReferencingRows = async (client, { table, column }, ids) => {
  const values = inClause(ids);
  if (values.length === 0) {
    return 0;
  }
  const rows = await client.$queryRawUnsafe(
    `SELECT COUNT(*) AS total FROM ${quoteIdentifier(table)} WHERE ${quoteIdentifier(column)} IN (${values.map(() => '?').join(', ')})`,
    ...values
  );
  return Number(rows?.[0]?.total ?? 0);
};

/**
 * @param {Object} client - Prisma client or interactive transaction client
 * @param {{ table: string, column: string }} reference
 * @param {string|string[]} ids - Referenced row ids
 * @returns {Promise<number>} Deleted row count
 */
const deleteReferencingRows = async (client, { table, column }, ids) => {
  const values = inClause(ids);
  if (values.length === 0) {
    return 0;
  }
  const deleted = await client.$executeRawUnsafe(
    `DELETE FROM ${quoteIdentifier(table)} WHERE ${quoteIdentifier(column)} IN (${values.map(() => '?').join(', ')})`,
    ...values
  );
  return Number(deleted || 0);
};

const clearForeignKeyReferenceCache = () => {
  referenceCache.clear();
};

module.exports = {
  clearForeignKeyReferenceCache,
  countReferencingRows,
  deleteReferencingRows,
  listForeignKeyReferences,
};
