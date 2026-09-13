/**
 * @jest-environment node
 */

const {
  clearForeignKeyReferenceCache,
  countReferencingRows,
  deleteReferencingRows,
  listForeignKeyReferences,
} = require('@lib/database/foreign-key-references');

describe('foreign-key-references', () => {
  beforeEach(() => {
    clearForeignKeyReferenceCache();
  });

  it('reads referencing columns from the schema catalog once per table', async () => {
    const client = {
      $queryRaw: jest.fn().mockResolvedValue([
        { table_name: 'audit_log', column_name: 'user_id' },
        { table_name: 'user_role', column_name: 'user_id' },
      ]),
    };

    await expect(listForeignKeyReferences(client, 'user')).resolves.toEqual([
      { table: 'audit_log', column: 'user_id' },
      { table: 'user_role', column: 'user_id' },
    ]);
    await listForeignKeyReferences(client, 'user');

    expect(client.$queryRaw).toHaveBeenCalledTimes(1);
  });

  it('counts and deletes with bound ids', async () => {
    const client = {
      $queryRawUnsafe: jest.fn().mockResolvedValue([{ total: 3n }]),
      $executeRawUnsafe: jest.fn().mockResolvedValue(2),
    };

    await expect(
      countReferencingRows(client, { table: 'audit_log', column: 'user_id' }, ['u-1'])
    ).resolves.toBe(3);
    expect(client.$queryRawUnsafe).toHaveBeenCalledWith(
      'SELECT COUNT(*) AS total FROM `audit_log` WHERE `user_id` IN (?)',
      'u-1'
    );

    await expect(
      deleteReferencingRows(client, { table: 'user_role', column: 'user_id' }, ['u-1', 'u-2'])
    ).resolves.toBe(2);
    expect(client.$executeRawUnsafe).toHaveBeenCalledWith(
      'DELETE FROM `user_role` WHERE `user_id` IN (?, ?)',
      'u-1',
      'u-2'
    );
  });

  it('skips the query when there is nothing to match', async () => {
    const client = { $queryRawUnsafe: jest.fn(), $executeRawUnsafe: jest.fn() };

    await expect(countReferencingRows(client, { table: 'user_role', column: 'user_id' }, [])).resolves.toBe(0);
    await expect(deleteReferencingRows(client, { table: 'user_role', column: 'user_id' }, [])).resolves.toBe(0);
    expect(client.$queryRawUnsafe).not.toHaveBeenCalled();
    expect(client.$executeRawUnsafe).not.toHaveBeenCalled();
  });

  it('refuses identifiers that are not plain table or column names', async () => {
    const client = { $queryRawUnsafe: jest.fn() };

    await expect(
      countReferencingRows(client, { table: 'user`; DROP TABLE user; --', column: 'id' }, ['x'])
    ).rejects.toThrow('unsafe SQL identifier');
    expect(client.$queryRawUnsafe).not.toHaveBeenCalled();
  });
});
