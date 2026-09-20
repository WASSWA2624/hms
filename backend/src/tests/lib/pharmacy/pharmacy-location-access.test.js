/**
 * Location-based permissions keep the two pharmacies apart.
 *
 * Requirements 4 and 7: a Hospital Pharmacy user must not modify Main Pharmacy
 * stock, purchases, batches or costs, but may read Main Pharmacy availability
 * because Main supplies them - and that read is quantities only.
 */

const {
  ACCESS_LEVELS,
  LOCATION_KINDS,
  ORDER_ORIGINS,
  satisfiesAccessLevel,
  assertLocationAccess,
  assertProcurementAccess,
  canViewSupplierStock,
  assertStockVisibility,
  toSupplierStockProjection,
  resolveDispensingLocationForOrigin,
  findPharmacyLocation,
} = require('@lib/pharmacy/pharmacy-location-access');
const { HttpError } = require('@lib/errors');

const MAIN = {
  id: 'loc-main',
  tenant_id: 'ten-1',
  facility_id: 'fac-1',
  name: 'Main Pharmacy',
  code: 'MAIN',
  kind: LOCATION_KINDS.MAIN,
  is_active: true,
  is_default: true,
  handles_procurement: true,
  handles_walk_in: true,
  handles_prescriptions: false,
  supplied_by_location_id: null,
};

const HOSPITAL = {
  id: 'loc-hospital',
  tenant_id: 'ten-1',
  facility_id: 'fac-1',
  name: 'Hospital Pharmacy',
  code: 'HOSPITAL',
  kind: LOCATION_KINDS.HOSPITAL,
  is_active: true,
  is_default: true,
  handles_procurement: false,
  handles_walk_in: false,
  handles_prescriptions: true,
  supplied_by_location_id: MAIN.id,
};

const LOCATIONS = [MAIN, HOSPITAL];

/**
 * Prisma stand-in over a fixed location list and grant list.
 *
 * @param {Object[]} grants - `pharmacy_location_user` rows
 * @returns {Object} Client
 */
const buildClient = (grants = []) => ({
  pharmacy_location: {
    findFirst: jest.fn(async ({ where }) => {
      return (
        LOCATIONS.find((location) => {
          if (where.id && location.id !== where.id) return false;
          if (where.code && location.code !== where.code) return false;
          if (where.kind && location.kind !== where.kind) return false;
          if (where.human_friendly_id) return false;
          if (where.facility_id && location.facility_id !== where.facility_id) return false;
          if (where.tenant_id && location.tenant_id !== where.tenant_id) return false;
          if (where.handles_walk_in && !location.handles_walk_in) return false;
          if (where.handles_prescriptions && !location.handles_prescriptions) return false;
          return true;
        }) || null
      );
    }),
  },
  pharmacy_location_user: {
    findFirst: jest.fn(async ({ where }) =>
      grants.find(
        (grant) =>
          grant.user_id === where.user_id &&
          grant.pharmacy_location_id === where.pharmacy_location_id
      ) || null
    ),
    findMany: jest.fn(async ({ where }) =>
      grants.filter((grant) => grant.user_id === where.user_id)
    ),
  },
});

const hospitalPharmacist = { id: 'usr-hosp', roles: ['PHARMACIST'], tenant_id: 'ten-1' };
const mainPharmacist = { id: 'usr-main', roles: ['PHARMACIST'], tenant_id: 'ten-1' };
const tenantAdmin = { id: 'usr-admin', roles: ['TENANT_ADMIN'], tenant_id: 'ten-1' };

const GRANTS = [
  {
    user_id: hospitalPharmacist.id,
    pharmacy_location_id: HOSPITAL.id,
    access_level: ACCESS_LEVELS.MANAGE,
    can_view_supplier_stock: true,
    is_active: true,
  },
  {
    user_id: mainPharmacist.id,
    pharmacy_location_id: MAIN.id,
    access_level: ACCESS_LEVELS.MANAGE,
    can_view_supplier_stock: true,
    is_active: true,
  },
];

describe('pharmacy location access', () => {
  it('ranks access levels so MANAGE satisfies DISPENSE and VIEW', () => {
    expect(satisfiesAccessLevel(ACCESS_LEVELS.MANAGE, ACCESS_LEVELS.VIEW)).toBe(true);
    expect(satisfiesAccessLevel(ACCESS_LEVELS.MANAGE, ACCESS_LEVELS.DISPENSE)).toBe(true);
    expect(satisfiesAccessLevel(ACCESS_LEVELS.DISPENSE, ACCESS_LEVELS.MANAGE)).toBe(false);
    expect(satisfiesAccessLevel(ACCESS_LEVELS.VIEW, ACCESS_LEVELS.DISPENSE)).toBe(false);
    expect(satisfiesAccessLevel(null, ACCESS_LEVELS.VIEW)).toBe(false);
  });

  it('lets a hospital pharmacist manage their own pharmacy', async () => {
    const client = buildClient(GRANTS);
    await expect(
      assertLocationAccess(client, {
        location: HOSPITAL,
        user: hospitalPharmacist,
        level: ACCESS_LEVELS.MANAGE,
      })
    ).resolves.toBeTruthy();
  });

  it('stops a hospital pharmacist writing to Main Pharmacy stock', async () => {
    const client = buildClient(GRANTS);
    await expect(
      assertLocationAccess(client, {
        location: MAIN,
        user: hospitalPharmacist,
        level: ACCESS_LEVELS.DISPENSE,
      })
    ).rejects.toBeInstanceOf(HttpError);
  });

  it('stops a hospital pharmacist touching Main Pharmacy procurement records', async () => {
    const client = buildClient(GRANTS);
    await expect(
      assertProcurementAccess(client, { location: MAIN, user: hospitalPharmacist })
    ).rejects.toBeInstanceOf(HttpError);
  });

  it('refuses procurement on a pharmacy that does not procure, even for its manager', async () => {
    const client = buildClient(GRANTS);
    // The hospital pharmacist manages the Hospital Pharmacy, but that pharmacy
    // holds no suppliers, purchases or landed cost.
    await expect(
      assertProcurementAccess(client, { location: HOSPITAL, user: hospitalPharmacist })
    ).rejects.toBeInstanceOf(HttpError);
  });

  it('allows the main pharmacist to run procurement', async () => {
    const client = buildClient(GRANTS);
    await expect(
      assertProcurementAccess(client, { location: MAIN, user: mainPharmacist })
    ).resolves.toBeTruthy();
  });

  it('treats tenant admins as having access without an explicit grant', async () => {
    const client = buildClient([]);
    await expect(
      assertLocationAccess(client, {
        location: MAIN,
        user: tenantAdmin,
        level: ACCESS_LEVELS.MANAGE,
      })
    ).resolves.toBeNull();
  });

  it('lets a supplied pharmacy read its supplier availability without a grant', async () => {
    expect(canViewSupplierStock(HOSPITAL, MAIN)).toBe(true);
    // Not the other way round: Main is not supplied by Hospital.
    expect(canViewSupplierStock(MAIN, HOSPITAL)).toBe(false);

    const client = buildClient(GRANTS);
    await expect(
      assertStockVisibility(client, { target: MAIN, viewer: HOSPITAL, user: hospitalPharmacist })
    ).resolves.toBeUndefined();
  });

  it('still denies the reverse read with no grant and no supply link', async () => {
    const client = buildClient(GRANTS);
    await expect(
      assertStockVisibility(client, { target: HOSPITAL, viewer: MAIN, user: mainPharmacist })
    ).rejects.toBeInstanceOf(HttpError);
  });

  it('exposes only quantities of the supplier stock row', () => {
    const projection = toSupplierStockProjection({
      id: 'stock-1',
      inventory_item_id: 'item-1',
      pharmacy_location_id: MAIN.id,
      quantity: 800,
      reorder_level: 100,
      updated_at: new Date('2026-09-20T00:00:00.000Z'),
      // None of the following may leak to a Hospital Pharmacy user.
      unit_cost: '150.00',
      supplier_id: 'sup-1',
      batch_number: 'B-123',
    });

    expect(projection.quantity).toBe(800);
    expect(projection).not.toHaveProperty('unit_cost');
    expect(projection).not.toHaveProperty('supplier_id');
    expect(projection).not.toHaveProperty('batch_number');
  });

  it('routes hospital prescriptions to the prescription pharmacy', async () => {
    const client = buildClient(GRANTS);
    const location = await resolveDispensingLocationForOrigin(client, {
      facilityId: 'fac-1',
      origin: ORDER_ORIGINS.HOSPITAL,
      tenantId: 'ten-1',
    });
    expect(location.id).toBe(HOSPITAL.id);
  });

  it('routes walk-in sales to the walk-in pharmacy', async () => {
    const client = buildClient(GRANTS);
    const location = await resolveDispensingLocationForOrigin(client, {
      facilityId: 'fac-1',
      origin: ORDER_ORIGINS.WALK_IN,
      tenantId: 'ten-1',
    });
    expect(location.id).toBe(MAIN.id);
  });

  it('resolves a location by kind so MAIN and HOSPITAL work as identifiers', async () => {
    const client = buildClient(GRANTS);
    const byKind = await findPharmacyLocation(client, 'HOSPITAL', { facilityId: 'fac-1' });
    expect(byKind.id).toBe(HOSPITAL.id);
  });
});
