/**
 * Main and Hospital pharmacies hold separate balances of the same catalog item,
 * and stock moves between them only through the two legs of a transfer.
 *
 * Requirement 2: a transfer reduces Main and raises Hospital, and only after
 * the corresponding transaction.
 */

const {
  findLocationStock,
  issueStockToLocation,
  receiveStockAtLocation,
  loadStockMatrix,
} = require('@lib/pharmacy/pharmacy-location-stock');
const { HttpError } = require('@lib/errors');

const MAIN = { id: 'loc-main', facility_id: 'fac-1', name: 'Main Pharmacy', kind: 'MAIN' };
const HOSPITAL = {
  id: 'loc-hospital',
  facility_id: 'fac-1',
  name: 'Hospital Pharmacy',
  kind: 'HOSPITAL',
};

/**
 * In-memory Prisma stand-in holding one balance row per (item, location).
 *
 * @param {Object[]} seed - Initial stock rows
 * @returns {Object} Client with `inventory_stock` and `stock_movement`
 */
const buildClient = (seed = []) => {
  const stocks = seed.map((row, index) => ({
    id: row.id || `stock-${index + 1}`,
    quantity: 0,
    reorder_level: 0,
    deleted_at: null,
    ...row,
  }));
  const movements = [];

  return {
    _stocks: stocks,
    _movements: movements,
    assignFriendlyIdIfMissing: jest.fn(async () => {}),
    inventory_stock: {
      findFirst: jest.fn(async ({ where }) =>
        stocks.find(
          (row) =>
            row.inventory_item_id === where.inventory_item_id &&
            row.pharmacy_location_id === where.pharmacy_location_id &&
            row.deleted_at === null
        ) || null
      ),
      findMany: jest.fn(async ({ where }) =>
        stocks.filter(
          (row) =>
            where.inventory_item_id.in.includes(row.inventory_item_id) &&
            where.pharmacy_location_id.in.includes(row.pharmacy_location_id)
        )
      ),
      create: jest.fn(async ({ data }) => {
        const row = { id: `stock-${stocks.length + 1}`, deleted_at: null, ...data };
        stocks.push(row);
        return row;
      }),
      update: jest.fn(async ({ where, data }) => {
        const row = stocks.find((candidate) => candidate.id === where.id);
        Object.assign(row, data);
        return row;
      }),
    },
    stock_movement: {
      create: jest.fn(async ({ data }) => {
        movements.push(data);
        return { id: `mov-${movements.length}`, ...data };
      }),
    },
  };
};

const quantityAt = (client, itemId, locationId) =>
  Number(
    client._stocks.find(
      (row) => row.inventory_item_id === itemId && row.pharmacy_location_id === locationId
    )?.quantity ?? 0
  );

describe('pharmacy location stock', () => {
  it('keeps Main and Hospital balances of the same item separate', async () => {
    const client = buildClient([
      { inventory_item_id: 'item-1', pharmacy_location_id: MAIN.id, quantity: 1000 },
      { inventory_item_id: 'item-1', pharmacy_location_id: HOSPITAL.id, quantity: 120 },
    ]);

    const main = await findLocationStock(client, {
      inventoryItemId: 'item-1',
      pharmacyLocationId: MAIN.id,
    });
    const hospital = await findLocationStock(client, {
      inventoryItemId: 'item-1',
      pharmacyLocationId: HOSPITAL.id,
    });

    expect(main.quantity).toBe(1000);
    expect(hospital.quantity).toBe(120);
  });

  it('moves stock only on issue and receipt, one leg each', async () => {
    const client = buildClient([
      { inventory_item_id: 'item-1', pharmacy_location_id: MAIN.id, quantity: 1000 },
      { inventory_item_id: 'item-1', pharmacy_location_id: HOSPITAL.id, quantity: 120 },
    ]);

    await issueStockToLocation(client, {
      fromLocation: MAIN,
      toLocation: HOSPITAL,
      inventoryItemId: 'item-1',
      quantity: 80,
      transferGroupId: 'grp-1',
    });

    // Issued but not yet received: Main has dropped, Hospital has not risen.
    expect(quantityAt(client, 'item-1', MAIN.id)).toBe(920);
    expect(quantityAt(client, 'item-1', HOSPITAL.id)).toBe(120);

    await receiveStockAtLocation(client, {
      fromLocation: MAIN,
      toLocation: HOSPITAL,
      inventoryItemId: 'item-1',
      quantity: 80,
      transferGroupId: 'grp-1',
    });

    expect(quantityAt(client, 'item-1', MAIN.id)).toBe(920);
    expect(quantityAt(client, 'item-1', HOSPITAL.id)).toBe(200);

    // Both legs share one group so an in-transit shipment stays traceable.
    expect(client._movements).toHaveLength(2);
    expect(client._movements.every((m) => m.transfer_group_id === 'grp-1')).toBe(true);
    expect(client._movements[0].from_pharmacy_location_id).toBe(MAIN.id);
    expect(client._movements[1].to_pharmacy_location_id).toBe(HOSPITAL.id);
  });

  it('refuses to issue more than the supplying pharmacy holds', async () => {
    const client = buildClient([
      { inventory_item_id: 'item-1', pharmacy_location_id: MAIN.id, quantity: 10 },
    ]);

    await expect(
      issueStockToLocation(client, {
        fromLocation: MAIN,
        toLocation: HOSPITAL,
        inventoryItemId: 'item-1',
        quantity: 50,
        transferGroupId: 'grp-1',
      })
    ).rejects.toBeInstanceOf(HttpError);

    expect(quantityAt(client, 'item-1', MAIN.id)).toBe(10);
  });

  it('will not let one pharmacy draw on another pharmacy stock row', async () => {
    // Hospital holds nothing; Main's 1000 units must not satisfy the issue.
    const client = buildClient([
      { inventory_item_id: 'item-1', pharmacy_location_id: MAIN.id, quantity: 1000 },
    ]);

    await expect(
      issueStockToLocation(client, {
        fromLocation: HOSPITAL,
        toLocation: MAIN,
        inventoryItemId: 'item-1',
        quantity: 1,
        transferGroupId: 'grp-1',
      })
    ).rejects.toBeInstanceOf(HttpError);
  });

  it('opens a zero balance for a pharmacy receiving an item for the first time', async () => {
    const client = buildClient([
      { inventory_item_id: 'item-2', pharmacy_location_id: MAIN.id, quantity: 40 },
    ]);

    await receiveStockAtLocation(client, {
      fromLocation: MAIN,
      toLocation: HOSPITAL,
      inventoryItemId: 'item-2',
      quantity: 15,
      transferGroupId: 'grp-2',
    });

    expect(quantityAt(client, 'item-2', HOSPITAL.id)).toBe(15);
  });

  it('reports availability per pharmacy for a cross-pharmacy view', async () => {
    const client = buildClient([
      { inventory_item_id: 'item-1', pharmacy_location_id: MAIN.id, quantity: 800 },
      { inventory_item_id: 'item-1', pharmacy_location_id: HOSPITAL.id, quantity: 20 },
    ]);

    const matrix = await loadStockMatrix(client, {
      inventoryItemIds: ['item-1'],
      pharmacyLocationIds: [MAIN.id, HOSPITAL.id],
    });

    expect(matrix.get('item-1').get(MAIN.id).quantity).toBe(800);
    expect(matrix.get('item-1').get(HOSPITAL.id).quantity).toBe(20);
  });
});
