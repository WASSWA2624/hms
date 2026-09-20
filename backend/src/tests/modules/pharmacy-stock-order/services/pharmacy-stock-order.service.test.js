/**
 * Hospital Pharmacy -> Main Pharmacy stock ordering.
 *
 * Requirement 6: the order itself never changes stock. Only the issue and
 * receipt legs do, and each side of the workflow is restricted to the pharmacy
 * that owns that step.
 */

jest.mock('@lib/audit', () => ({ createAuditLog: jest.fn().mockResolvedValue({}) }));
jest.mock('@prisma/client', () => ({
  $transaction: jest.fn(),
  assignFriendlyIdIfMissing: jest.fn().mockResolvedValue(undefined),
  pharmacy_stock_order: { findFirst: jest.fn(), update: jest.fn(), create: jest.fn() },
  pharmacy_stock_order_item: { update: jest.fn(), updateMany: jest.fn(), create: jest.fn() },
  pharmacy_location: { findFirst: jest.fn() },
  pharmacy_location_user: { findFirst: jest.fn(), findMany: jest.fn() },
  pharmacy_location_price: { findFirst: jest.fn(), update: jest.fn(), create: jest.fn() },
  inventory_stock: { findFirst: jest.fn(), update: jest.fn(), create: jest.fn() },
  stock_movement: { create: jest.fn() },
  drug_inventory_map: { findFirst: jest.fn() },
}));

const prisma = require('@prisma/client');
const stockOrderService = require('@services/pharmacy-stock-order/pharmacy-stock-order.service');
const { HttpError } = require('@lib/errors');

const MAIN = {
  id: 'loc-main',
  tenant_id: 'ten-1',
  facility_id: 'fac-1',
  name: 'Main Pharmacy',
  kind: 'MAIN',
  is_active: true,
  handles_procurement: true,
  currency: 'UGX',
};

const HOSPITAL = {
  id: 'loc-hospital',
  tenant_id: 'ten-1',
  facility_id: 'fac-1',
  name: 'Hospital Pharmacy',
  kind: 'HOSPITAL',
  is_active: true,
  handles_procurement: false,
  supplied_by_location_id: MAIN.id,
  currency: 'UGX',
};

const mainPharmacist = { id: 'usr-main', roles: ['PHARMACIST'], tenant_id: 'ten-1' };
const hospitalPharmacist = { id: 'usr-hosp', roles: ['PHARMACIST'], tenant_id: 'ten-1' };

const buildOrder = (overrides = {}) => ({
  id: 'pso-1',
  human_friendly_id: 'PSO0000001',
  tenant_id: 'ten-1',
  requesting_location_id: HOSPITAL.id,
  supplying_location_id: MAIN.id,
  requesting_location: HOSPITAL,
  supplying_location: MAIN,
  status: 'SUBMITTED',
  transfer_group_id: null,
  currency: 'UGX',
  items: [
    {
      id: 'psi-1',
      drug_id: 'drug-1',
      inventory_item_id: 'item-1',
      requested_quantity: 100,
      approved_quantity: null,
      issued_quantity: 0,
      received_quantity: 0,
      unit_supply_price: null,
      status: 'REQUESTED',
      drug: { id: 'drug-1', name: 'Paracetamol 500mg', transfer_unit_price: '200.00', currency: 'UGX' },
    },
  ],
  ...overrides,
});

/** Grant table used by the access guard. */
let grants = [];
/** Balances keyed `${itemId}:${locationId}`. */
let balances = {};

const wireCommonMocks = () => {
  prisma.$transaction.mockImplementation(async (fn) => fn(prisma));

  prisma.pharmacy_location.findFirst.mockImplementation(async ({ where }) =>
    [MAIN, HOSPITAL].find((location) => {
      if (where.id && location.id !== where.id) return false;
      if (where.kind && location.kind !== where.kind) return false;
      if (where.code && where.code !== location.kind) return false;
      if (where.human_friendly_id) return false;
      return true;
    }) || null
  );

  prisma.pharmacy_location_user.findFirst.mockImplementation(async ({ where }) =>
    grants.find(
      (grant) =>
        grant.user_id === where.user_id && grant.pharmacy_location_id === where.pharmacy_location_id
    ) || null
  );
  prisma.pharmacy_location_user.findMany.mockImplementation(async ({ where }) =>
    grants.filter((grant) => grant.user_id === where.user_id)
  );

  prisma.inventory_stock.findFirst.mockImplementation(async ({ where }) => {
    const key = `${where.inventory_item_id}:${where.pharmacy_location_id}`;
    return balances[key] || null;
  });
  prisma.inventory_stock.update.mockImplementation(async ({ where, data }) => {
    const row = Object.values(balances).find((candidate) => candidate.id === where.id);
    Object.assign(row, data);
    return row;
  });
  prisma.inventory_stock.create.mockImplementation(async ({ data }) => {
    const row = { id: `stock-${Object.keys(balances).length + 1}`, ...data };
    balances[`${data.inventory_item_id}:${data.pharmacy_location_id}`] = row;
    return row;
  });

  prisma.stock_movement.create.mockImplementation(async ({ data }) => ({ id: 'mov-1', ...data }));
  prisma.pharmacy_stock_order_item.update.mockResolvedValue({});
  prisma.pharmacy_location_price.findFirst.mockResolvedValue(null);
  prisma.pharmacy_location_price.create.mockResolvedValue({});
  prisma.pharmacy_stock_order.update.mockResolvedValue({});
};

describe('pharmacy stock order workflow', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    grants = [
      {
        user_id: mainPharmacist.id,
        pharmacy_location_id: MAIN.id,
        access_level: 'MANAGE',
        is_active: true,
      },
      {
        user_id: hospitalPharmacist.id,
        pharmacy_location_id: HOSPITAL.id,
        access_level: 'MANAGE',
        is_active: true,
      },
    ];
    balances = {
      [`item-1:${MAIN.id}`]: {
        id: 'stock-main',
        inventory_item_id: 'item-1',
        pharmacy_location_id: MAIN.id,
        quantity: 1000,
      },
      [`item-1:${HOSPITAL.id}`]: {
        id: 'stock-hosp',
        inventory_item_id: 'item-1',
        pharmacy_location_id: HOSPITAL.id,
        quantity: 20,
      },
    };
    wireCommonMocks();
  });

  describe('review', () => {
    it('records a partial approval without moving any stock', async () => {
      const order = buildOrder();
      prisma.pharmacy_stock_order.findFirst.mockResolvedValue(order);

      await stockOrderService.reviewStockOrder(
        'pso-1',
        { decision: 'APPROVE', items: [{ id: 'psi-1', approved_quantity: 60 }] },
        mainPharmacist
      );

      expect(prisma.pharmacy_stock_order_item.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: 'psi-1' },
          data: expect.objectContaining({ approved_quantity: 60, status: 'PARTIALLY_APPROVED' }),
        })
      );
      expect(prisma.pharmacy_stock_order.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ status: 'PARTIALLY_APPROVED' }),
        })
      );

      // The decisive assertion: reviewing changed no balance.
      expect(prisma.inventory_stock.update).not.toHaveBeenCalled();
      expect(prisma.stock_movement.create).not.toHaveBeenCalled();
      expect(balances[`item-1:${MAIN.id}`].quantity).toBe(1000);
    });

    it('rejects the whole order without moving stock', async () => {
      prisma.pharmacy_stock_order.findFirst.mockResolvedValue(buildOrder());

      await stockOrderService.reviewStockOrder('pso-1', { decision: 'REJECT' }, mainPharmacist);

      expect(prisma.pharmacy_stock_order.update).toHaveBeenCalledWith(
        expect.objectContaining({ data: expect.objectContaining({ status: 'REJECTED' }) })
      );
      expect(prisma.inventory_stock.update).not.toHaveBeenCalled();
    });

    it('will not let the requesting pharmacy approve its own request', async () => {
      prisma.pharmacy_stock_order.findFirst.mockResolvedValue(buildOrder());

      await expect(
        stockOrderService.reviewStockOrder('pso-1', { decision: 'APPROVE' }, hospitalPharmacist)
      ).rejects.toBeInstanceOf(HttpError);
      expect(prisma.pharmacy_stock_order.update).not.toHaveBeenCalled();
    });
  });

  describe('issue', () => {
    it('takes the approved quantity out of the supplying pharmacy at its supply price', async () => {
      prisma.pharmacy_stock_order.findFirst.mockResolvedValue(
        buildOrder({
          status: 'APPROVED',
          items: [
            {
              ...buildOrder().items[0],
              approved_quantity: 60,
              status: 'APPROVED',
            },
          ],
        })
      );

      await stockOrderService.issueStockOrder('pso-1', {}, mainPharmacist);

      expect(balances[`item-1:${MAIN.id}`].quantity).toBe(940);
      // Not received yet, so the hospital balance is untouched.
      expect(balances[`item-1:${HOSPITAL.id}`].quantity).toBe(20);

      // Priced at the supply price (200), never the walk-in price.
      expect(prisma.pharmacy_stock_order_item.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ issued_quantity: 60, unit_supply_price: '200.00' }),
        })
      );
      expect(prisma.pharmacy_stock_order.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ status: 'ISSUED', supply_total: '12000.00' }),
        })
      );
    });

    it('will not let the requesting pharmacy issue from the supplier', async () => {
      prisma.pharmacy_stock_order.findFirst.mockResolvedValue(
        buildOrder({
          status: 'APPROVED',
          items: [{ ...buildOrder().items[0], approved_quantity: 60, status: 'APPROVED' }],
        })
      );

      await expect(
        stockOrderService.issueStockOrder('pso-1', {}, hospitalPharmacist)
      ).rejects.toBeInstanceOf(HttpError);
      expect(balances[`item-1:${MAIN.id}`].quantity).toBe(1000);
    });

    it('refuses to issue an order that has not been approved', async () => {
      prisma.pharmacy_stock_order.findFirst.mockResolvedValue(buildOrder({ status: 'SUBMITTED' }));

      await expect(
        stockOrderService.issueStockOrder('pso-1', {}, mainPharmacist)
      ).rejects.toBeInstanceOf(HttpError);
      expect(balances[`item-1:${MAIN.id}`].quantity).toBe(1000);
    });
  });

  describe('receive', () => {
    const issuedOrder = () =>
      buildOrder({
        status: 'ISSUED',
        transfer_group_id: 'grp-1',
        items: [
          {
            ...buildOrder().items[0],
            approved_quantity: 60,
            issued_quantity: 60,
            received_quantity: 0,
            unit_supply_price: '200.00',
            currency: 'UGX',
            status: 'ISSUED',
          },
        ],
      });

    it('brings the delivery into the requesting pharmacy', async () => {
      prisma.pharmacy_stock_order.findFirst.mockResolvedValue(issuedOrder());

      await stockOrderService.receiveStockOrder('pso-1', {}, hospitalPharmacist);

      expect(balances[`item-1:${HOSPITAL.id}`].quantity).toBe(80);
      expect(prisma.pharmacy_stock_order.update).toHaveBeenCalledWith(
        expect.objectContaining({ data: expect.objectContaining({ status: 'RECEIVED' }) })
      );
    });

    it('records the supply price as the receiving pharmacy acquisition cost', async () => {
      prisma.pharmacy_stock_order.findFirst.mockResolvedValue(issuedOrder());

      await stockOrderService.receiveStockOrder('pso-1', {}, hospitalPharmacist);

      // The cost it carries is what Main charged it, not Main's walk-in price
      // and not the hospital's own selling price.
      expect(prisma.pharmacy_location_price.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            pharmacy_location_id: HOSPITAL.id,
            drug_id: 'drug-1',
            acquisition_cost: '200.00',
          }),
        })
      );
    });

    it('leaves a short delivery partially received rather than writing it off', async () => {
      prisma.pharmacy_stock_order.findFirst.mockResolvedValue(issuedOrder());

      await stockOrderService.receiveStockOrder(
        'pso-1',
        { items: [{ id: 'psi-1', received_quantity: 45 }] },
        hospitalPharmacist
      );

      expect(balances[`item-1:${HOSPITAL.id}`].quantity).toBe(65);
      expect(prisma.pharmacy_stock_order.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ status: 'PARTIALLY_RECEIVED' }),
        })
      );
    });

    it('will not let the supplying pharmacy book the delivery for the requester', async () => {
      prisma.pharmacy_stock_order.findFirst.mockResolvedValue(issuedOrder());

      await expect(
        stockOrderService.receiveStockOrder('pso-1', {}, mainPharmacist)
      ).rejects.toBeInstanceOf(HttpError);
      expect(balances[`item-1:${HOSPITAL.id}`].quantity).toBe(20);
    });
  });

  describe('cancel', () => {
    it('cancels an order that has not moved stock', async () => {
      prisma.pharmacy_stock_order.findFirst.mockResolvedValue(buildOrder({ status: 'SUBMITTED' }));

      await stockOrderService.cancelStockOrder('pso-1', { reason: 'Duplicate' }, hospitalPharmacist);

      expect(prisma.pharmacy_stock_order.update).toHaveBeenCalledWith(
        expect.objectContaining({ data: expect.objectContaining({ status: 'CANCELLED' }) })
      );
    });

    it('refuses to cancel once stock has been issued', async () => {
      prisma.pharmacy_stock_order.findFirst.mockResolvedValue(buildOrder({ status: 'ISSUED' }));

      await expect(
        stockOrderService.cancelStockOrder('pso-1', {}, hospitalPharmacist)
      ).rejects.toBeInstanceOf(HttpError);
    });
  });

  describe('status rollups', () => {
    it('reports full approval only when every line is approved in full', () => {
      expect(
        stockOrderService.rollupReviewStatus([
          { requested_quantity: 10, approved_quantity: 10, status: 'APPROVED' },
          { requested_quantity: 5, approved_quantity: 5, status: 'APPROVED' },
        ])
      ).toBe('APPROVED');

      expect(
        stockOrderService.rollupReviewStatus([
          { requested_quantity: 10, approved_quantity: 10, status: 'APPROVED' },
          { requested_quantity: 5, approved_quantity: 0, status: 'REJECTED' },
        ])
      ).toBe('PARTIALLY_APPROVED');

      expect(
        stockOrderService.rollupReviewStatus([
          { requested_quantity: 10, approved_quantity: 0, status: 'REJECTED' },
        ])
      ).toBe('REJECTED');
    });

    it('reports receipt against what was issued, not what was requested', () => {
      expect(
        stockOrderService.rollupReceiveStatus([
          { issued_quantity: 60, received_quantity: 60, status: 'RECEIVED' },
        ])
      ).toBe('RECEIVED');

      expect(
        stockOrderService.rollupReceiveStatus([
          { issued_quantity: 60, received_quantity: 45, status: 'ISSUED' },
        ])
      ).toBe('PARTIALLY_RECEIVED');
    });
  });
});
