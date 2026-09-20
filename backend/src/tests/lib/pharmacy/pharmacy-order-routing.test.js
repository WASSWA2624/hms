/**
 * Prescriptions are routed by where they were raised, and cannot be dispensed
 * from the wrong pharmacy.
 *
 * Requirement 5.
 */

const {
  ORDER_ORIGINS,
  resolveOrderOrigin,
  resolvePharmacyOrderRouting,
  assertOrderDispensableAt,
} = require('@lib/pharmacy/pharmacy-order-routing');
const { HttpError } = require('@lib/errors');

const MAIN = {
  id: 'loc-main',
  tenant_id: 'ten-1',
  facility_id: 'fac-1',
  code: 'MAIN',
  kind: 'MAIN',
  is_active: true,
  is_default: true,
  handles_walk_in: true,
  handles_prescriptions: false,
};

const HOSPITAL = {
  id: 'loc-hospital',
  tenant_id: 'ten-1',
  facility_id: 'fac-1',
  code: 'HOSPITAL',
  kind: 'HOSPITAL',
  is_active: true,
  is_default: true,
  handles_walk_in: false,
  handles_prescriptions: true,
};

const buildClient = (locations = [MAIN, HOSPITAL]) => ({
  pharmacy_location: {
    findFirst: jest.fn(async ({ where }) =>
      locations.find((location) => {
        if (where.id && location.id !== where.id) return false;
        if (where.code && location.code !== where.code) return false;
        if (where.kind && location.kind !== where.kind) return false;
        if (where.human_friendly_id) return false;
        if (where.facility_id && location.facility_id !== where.facility_id) return false;
        if (where.handles_walk_in && !location.handles_walk_in) return false;
        if (where.handles_prescriptions && !location.handles_prescriptions) return false;
        return true;
      }) || null
    ),
  },
});

describe('pharmacy order routing', () => {
  it('treats a prescription raised against an encounter as hospital work', () => {
    expect(resolveOrderOrigin({ encounterId: 'enc-1' })).toBe(ORDER_ORIGINS.HOSPITAL);
  });

  it('treats a prescription with no encounter as a counter sale', () => {
    expect(resolveOrderOrigin({})).toBe(ORDER_ORIGINS.WALK_IN);
  });

  it('honours an explicitly stated origin', () => {
    expect(resolveOrderOrigin({ explicitOrigin: 'WALK_IN', encounterId: 'enc-1' })).toBe(
      ORDER_ORIGINS.WALK_IN
    );
  });

  it('sends a hospital consultation prescription to the hospital pharmacy', async () => {
    const routing = await resolvePharmacyOrderRouting(buildClient(), {
      encounterId: 'enc-1',
      facilityId: 'fac-1',
      tenantId: 'ten-1',
    });

    expect(routing.origin).toBe(ORDER_ORIGINS.HOSPITAL);
    expect(routing.pharmacy_location_id).toBe(HOSPITAL.id);
  });

  it('sends a walk-in prescription to the main pharmacy', async () => {
    const routing = await resolvePharmacyOrderRouting(buildClient(), {
      facilityId: 'fac-1',
      tenantId: 'ten-1',
    });

    expect(routing.origin).toBe(ORDER_ORIGINS.WALK_IN);
    expect(routing.pharmacy_location_id).toBe(MAIN.id);
  });

  it('leaves routing unset for a facility with no pharmacy locations', async () => {
    const routing = await resolvePharmacyOrderRouting(buildClient([]), {
      encounterId: 'enc-1',
      facilityId: 'fac-1',
      tenantId: 'ten-1',
    });

    expect(routing.pharmacy_location_id).toBeNull();
  });

  it('refuses to dispense a hospital prescription from the main pharmacy', () => {
    expect(() =>
      assertOrderDispensableAt({
        order: { id: 'ord-1', pharmacy_location_id: HOSPITAL.id },
        dispensingLocation: MAIN,
      })
    ).toThrow(HttpError);
  });

  it('allows the pharmacy the prescription was routed to', () => {
    expect(() =>
      assertOrderDispensableAt({
        order: { id: 'ord-1', pharmacy_location_id: HOSPITAL.id },
        dispensingLocation: HOSPITAL,
      })
    ).not.toThrow();
  });

  it('does not strand an order that predates pharmacy locations', () => {
    expect(() =>
      assertOrderDispensableAt({
        order: { id: 'ord-old', pharmacy_location_id: null },
        dispensingLocation: MAIN,
      })
    ).not.toThrow();
  });
});
