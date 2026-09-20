/**
 * Per-location pricing keeps each pharmacy's commercial contexts apart.
 *
 * Requirement 8/9: Main Pharmacy walk-in, Main Pharmacy -> Hospital supply, and
 * Hospital Pharmacy dispensing are three independent prices. A transfer is
 * priced at the supplier's supply price, never at its walk-in price, and
 * editing one price must not move another.
 */

const {
  PRICE_CONTEXTS,
  resolveLocationPrice,
  requireSupplyPrice,
  buildLocationPriceSnapshot,
} = require('@lib/pharmacy/pharmacy-location-pricing');
const { HttpError } = require('@lib/errors');

const MAIN = {
  id: 'loc-main',
  name: 'Main Pharmacy',
  kind: 'MAIN',
  currency: 'UGX',
};

const HOSPITAL = {
  id: 'loc-hospital',
  name: 'Hospital Pharmacy',
  kind: 'HOSPITAL',
  currency: 'UGX',
};

const PARACETAMOL = {
  id: 'drug-1',
  currency: 'UGX',
  unit_price: '300.00',
  transfer_unit_price: '200.00',
  buy_unit_price: '150.00',
};

/** Prisma stand-in returning one price row per (location, drug). */
const clientWithPrices = (rows) => ({
  pharmacy_location_price: {
    findFirst: jest.fn(async ({ where }) => {
      return (
        rows.find(
          (row) =>
            row.pharmacy_location_id === where.pharmacy_location_id &&
            row.drug_id === where.drug_id
        ) || null
      );
    }),
  },
});

describe('pharmacy location pricing', () => {
  it('charges the walk-in price for a Main Pharmacy sale', async () => {
    const client = clientWithPrices([
      {
        pharmacy_location_id: MAIN.id,
        drug_id: PARACETAMOL.id,
        sell_price: '300.00',
        supply_price: '200.00',
        currency: 'UGX',
      },
    ]);

    const resolved = await resolveLocationPrice(client, {
      location: MAIN,
      drug: PARACETAMOL,
      context: PRICE_CONTEXTS.SELL,
    });

    expect(resolved.unit_price).toBe('300.00');
    expect(resolved.source).toBe('location_sell_price');
  });

  it('charges the supply price, not the walk-in price, when Main supplies Hospital', async () => {
    const client = clientWithPrices([
      {
        pharmacy_location_id: MAIN.id,
        drug_id: PARACETAMOL.id,
        sell_price: '300.00',
        supply_price: '200.00',
        currency: 'UGX',
      },
    ]);

    const resolved = await resolveLocationPrice(client, {
      location: MAIN,
      drug: PARACETAMOL,
      context: PRICE_CONTEXTS.SUPPLY,
    });

    expect(resolved.unit_price).toBe('200.00');
    expect(resolved.unit_price).not.toBe('300.00');
    expect(resolved.source).toBe('location_supply_price');
  });

  it('keeps the Hospital Pharmacy dispensing price independent of Main', async () => {
    const client = clientWithPrices([
      {
        pharmacy_location_id: MAIN.id,
        drug_id: PARACETAMOL.id,
        sell_price: '300.00',
        supply_price: '200.00',
      },
      {
        pharmacy_location_id: HOSPITAL.id,
        drug_id: PARACETAMOL.id,
        sell_price: '350.00',
        acquisition_cost: '200.00',
      },
    ]);

    const hospitalPrice = await resolveLocationPrice(client, {
      location: HOSPITAL,
      drug: PARACETAMOL,
      context: PRICE_CONTEXTS.SELL,
    });

    expect(hospitalPrice.unit_price).toBe('350.00');
  });

  it('never falls back from a supply price to a walk-in price', async () => {
    // No supply price configured anywhere, and the legacy transfer price is
    // absent too: the answer is "no price", not the retail price.
    const client = clientWithPrices([
      { pharmacy_location_id: MAIN.id, drug_id: PARACETAMOL.id, sell_price: '300.00' },
    ]);

    const resolved = await resolveLocationPrice(client, {
      location: MAIN,
      drug: { ...PARACETAMOL, transfer_unit_price: null },
      context: PRICE_CONTEXTS.SUPPLY,
    });

    expect(resolved.unit_price).toBeNull();
  });

  it('falls back to the tenant transfer price, not the tenant retail price', async () => {
    const client = clientWithPrices([]);

    const resolved = await resolveLocationPrice(client, {
      location: MAIN,
      drug: PARACETAMOL,
      context: PRICE_CONTEXTS.SUPPLY,
    });

    expect(resolved.unit_price).toBe('200.00');
    expect(resolved.source).toBe('drug_transfer_unit_price');
  });

  it('refuses to issue stock with no supply price rather than guessing one', async () => {
    const client = clientWithPrices([]);

    await expect(
      requireSupplyPrice(client, {
        supplyingLocation: MAIN,
        drug: { ...PARACETAMOL, transfer_unit_price: null },
      })
    ).rejects.toBeInstanceOf(HttpError);
  });

  it('hides supply price and cost from a pharmacy that does not manage the location', () => {
    const priceRow = {
      sell_price: '300.00',
      supply_price: '200.00',
      acquisition_cost: '150.00',
      currency: 'UGX',
    };

    const forOutsider = buildLocationPriceSnapshot({
      priceRow,
      location: MAIN,
      drug: PARACETAMOL,
    });
    expect(forOutsider.sell_price).toBe('300.00');
    expect(forOutsider).not.toHaveProperty('supply_price');
    expect(forOutsider).not.toHaveProperty('acquisition_cost');

    const forManager = buildLocationPriceSnapshot({
      priceRow,
      location: MAIN,
      drug: PARACETAMOL,
      includeSupplyPrice: true,
      includeCost: true,
    });
    expect(forManager.supply_price).toBe('200.00');
    expect(forManager.acquisition_cost).toBe('150.00');
  });
});
