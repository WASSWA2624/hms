/**
 * A prescription can only be filled by the pharmacy it was routed to.
 *
 * Requirement 5, at the point it matters: the dispense itself. Routing decides
 * which pharmacy owns the order; this is the check that stops the other one
 * from taking the stock out of its own shelf.
 */

const { assertOrderDispensableAt } = require('@lib/pharmacy/pharmacy-order-routing');
const { HttpError } = require('@lib/errors');

const MAIN = { id: 'loc-main', name: 'Main Pharmacy', kind: 'MAIN' };
const HOSPITAL = { id: 'loc-hospital', name: 'Hospital Pharmacy', kind: 'HOSPITAL' };

const hospitalPrescription = {
  id: 'ord-1',
  origin: 'HOSPITAL',
  pharmacy_location_id: HOSPITAL.id,
};

const walkInSale = {
  id: 'ord-2',
  origin: 'WALK_IN',
  pharmacy_location_id: MAIN.id,
};

describe('dispense isolation between pharmacies', () => {
  it('lets the hospital pharmacy fill a hospital prescription', () => {
    expect(() =>
      assertOrderDispensableAt({
        order: hospitalPrescription,
        dispensingLocation: HOSPITAL,
      })
    ).not.toThrow();
  });

  it('stops the main pharmacy filling a hospital prescription', () => {
    let thrown;
    try {
      assertOrderDispensableAt({
        order: hospitalPrescription,
        dispensingLocation: MAIN,
      });
    } catch (error) {
      thrown = error;
    }

    expect(thrown).toBeInstanceOf(HttpError);
    expect(thrown.message).toBe('errors.pharmacy_location.wrong_pharmacy_for_order');
    expect(thrown.statusCode ?? thrown.status).toBe(403);
    // The error names both pharmacies so the UI can say where to go instead.
    const detail = Array.isArray(thrown.errors) ? thrown.errors[0] : null;
    expect(detail?.expected_pharmacy_location_id).toBe(HOSPITAL.id);
    expect(detail?.actual_pharmacy_location_id).toBe(MAIN.id);
  });

  it('lets the main pharmacy fill its own walk-in sale', () => {
    expect(() =>
      assertOrderDispensableAt({ order: walkInSale, dispensingLocation: MAIN })
    ).not.toThrow();
  });

  it('stops the hospital pharmacy filling a walk-in sale', () => {
    expect(() =>
      assertOrderDispensableAt({ order: walkInSale, dispensingLocation: HOSPITAL })
    ).toThrow(HttpError);
  });

  it('does not block an order raised before pharmacy locations existed', () => {
    // Backfilled installs and facilities that never configured locations keep
    // dispensing wherever the user is, rather than being stranded.
    expect(() =>
      assertOrderDispensableAt({
        order: { id: 'ord-old', pharmacy_location_id: null },
        dispensingLocation: MAIN,
      })
    ).not.toThrow();
  });

  it('does not block when the caller has no pharmacy context at all', () => {
    expect(() =>
      assertOrderDispensableAt({
        order: hospitalPrescription,
        dispensingLocation: null,
      })
    ).not.toThrow();
  });
});
