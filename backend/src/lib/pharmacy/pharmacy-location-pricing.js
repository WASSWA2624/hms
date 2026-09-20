/**
 * Pharmacy location pricing
 *
 * @module lib/pharmacy
 * @description Price resolution for a drug at one pharmacy location.
 *
 * Each pharmacy keeps its own row in `pharmacy_location_price` with two
 * independent columns:
 *
 * * `sell_price`   - charged to this pharmacy's own customers. For Main
 *                    Pharmacy that is the walk-in price; for Hospital Pharmacy
 *                    it is the dispensing price.
 * * `supply_price` - charged when this pharmacy supplies another pharmacy.
 *                    Main Pharmacy -> Hospital Pharmacy uses this.
 *
 * Nothing here ever falls back from one context to the other. A transfer is
 * priced at the supplier's `supply_price`, never at its walk-in `sell_price`
 * (requirement 9), and editing a walk-in price cannot move a supply price or
 * another pharmacy's dispensing price because they are different columns on
 * different rows.
 *
 * The legacy `drug.unit_price` / `drug.transfer_unit_price` columns remain the
 * tenant-wide default for a location that has not set its own price yet, so a
 * facility that never configures per-location pricing keeps working.
 */

const { HttpError } = require('@lib/errors');

const PRICE_CONTEXTS = Object.freeze({
  /** This pharmacy selling to its own customer or patient. */
  SELL: 'SELL',
  /** This pharmacy supplying another pharmacy location. */
  SUPPLY: 'SUPPLY',
});

const toDecimalString = (value) => {
  if (value === null || value === undefined || value === '') return null;
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return null;
  return numeric.toFixed(2);
};

const firstDefinedPrice = (...candidates) => {
  for (const candidate of candidates) {
    const normalized = toDecimalString(candidate);
    if (normalized !== null) return normalized;
  }
  return null;
};

const normalizeCurrency = (...candidates) => {
  for (const candidate of candidates) {
    const normalized = String(candidate || '').trim().toUpperCase();
    if (normalized) return normalized;
  }
  return null;
};

const delegateFor = (client, model) => {
  const delegate = client?.[model];
  return delegate && typeof delegate.findFirst === 'function' ? delegate : null;
};

/**
 * Load the price row a pharmacy holds for a drug.
 *
 * @param {Object} client - Prisma client or transaction
 * @param {Object} params
 * @param {string} params.pharmacyLocationId - Pharmacy holding the price
 * @param {string} params.drugId - Catalog drug
 * @returns {Promise<Object|null>} Price row, or null when not configured
 */
const findLocationPrice = async (client, { pharmacyLocationId, drugId }) => {
  const delegate = delegateFor(client, 'pharmacy_location_price');
  if (!delegate || !pharmacyLocationId || !drugId) return null;

  return delegate.findFirst({
    where: {
      deleted_at: null,
      is_active: true,
      pharmacy_location_id: pharmacyLocationId,
      drug_id: drugId,
    },
  });
};

/**
 * Resolve the price to charge for a drug at a pharmacy, in one commercial
 * context.
 *
 * @param {Object} client - Prisma client or transaction
 * @param {Object} params
 * @param {Object} params.location - Pharmacy location row
 * @param {Object} params.drug - Drug row (used for the tenant-wide fallback)
 * @param {string} [params.context] - `SELL` or `SUPPLY`, default `SELL`
 * @returns {Promise<{unit_price: string|null, currency: string|null, source: string, context: string}>}
 *   Resolved price, with `source` naming where it came from
 */
const resolveLocationPrice = async (client, { location, drug, context = PRICE_CONTEXTS.SELL }) => {
  const normalizedContext =
    String(context || '').trim().toUpperCase() === PRICE_CONTEXTS.SUPPLY
      ? PRICE_CONTEXTS.SUPPLY
      : PRICE_CONTEXTS.SELL;

  if (!location || !drug) {
    return { unit_price: null, currency: null, source: 'none', context: normalizedContext };
  }

  const priceRow = await findLocationPrice(client, {
    pharmacyLocationId: location.id,
    drugId: drug.id,
  });

  if (normalizedContext === PRICE_CONTEXTS.SUPPLY) {
    const configured = toDecimalString(priceRow?.supply_price);
    if (configured !== null) {
      return {
        unit_price: configured,
        currency: normalizeCurrency(priceRow?.currency, location.currency, drug.currency),
        source: 'location_supply_price',
        context: normalizedContext,
      };
    }
    // Tenant-wide fallback is the transfer price, never the walk-in price.
    const legacy = toDecimalString(drug.transfer_unit_price);
    return {
      unit_price: legacy,
      currency: normalizeCurrency(location.currency, drug.currency),
      source: legacy === null ? 'none' : 'drug_transfer_unit_price',
      context: normalizedContext,
    };
  }

  const configured = toDecimalString(priceRow?.sell_price);
  if (configured !== null) {
    return {
      unit_price: configured,
      currency: normalizeCurrency(priceRow?.currency, location.currency, drug.currency),
      source: 'location_sell_price',
      context: normalizedContext,
    };
  }

  const legacy = toDecimalString(drug.unit_price);
  return {
    unit_price: legacy,
    currency: normalizeCurrency(location.currency, drug.currency),
    source: legacy === null ? 'none' : 'drug_unit_price',
    context: normalizedContext,
  };
};

/**
 * Resolve the supply price a pharmacy charges another pharmacy, and fail loudly
 * rather than quietly falling back to a retail price.
 *
 * @param {Object} client - Prisma client or transaction
 * @param {Object} params
 * @param {Object} params.supplyingLocation - Pharmacy issuing the stock
 * @param {Object} params.drug - Drug being supplied
 * @returns {Promise<{unit_price: string, currency: string|null, source: string}>}
 *   Resolved supply price
 * @throws {HttpError} 400 when no supply price is configured
 */
const requireSupplyPrice = async (client, { supplyingLocation, drug }) => {
  const resolved = await resolveLocationPrice(client, {
    location: supplyingLocation,
    drug,
    context: PRICE_CONTEXTS.SUPPLY,
  });

  if (resolved.unit_price === null) {
    throw new HttpError('errors.pharmacy_location_price.supply_price_required', 400, [
      { drug_id: drug?.id || null, pharmacy_location_id: supplyingLocation?.id || null },
    ]);
  }

  return resolved;
};

/**
 * Per-location price snapshot for a drug, for catalog and cross-pharmacy views.
 *
 * `supply_price` is included only when the caller is allowed to see the
 * supplying pharmacy's commercial terms; `acquisition_cost` is never included
 * for a pharmacy the caller does not manage.
 *
 * @param {Object} params
 * @param {Object|null} params.priceRow - `pharmacy_location_price` row
 * @param {Object} params.location - Pharmacy location row
 * @param {Object} params.drug - Drug row
 * @param {boolean} [params.includeSupplyPrice] - Include the supply price
 * @param {boolean} [params.includeCost] - Include the acquisition cost
 * @returns {Object} Serializable price snapshot
 */
const buildLocationPriceSnapshot = ({
  priceRow,
  location,
  drug,
  includeSupplyPrice = false,
  includeCost = false,
}) => ({
  pharmacy_location_id: location?.id || null,
  pharmacy_location_name: location?.name || null,
  pharmacy_location_kind: location?.kind || null,
  drug_id: drug?.id || null,
  sell_price: firstDefinedPrice(priceRow?.sell_price, drug?.unit_price),
  ...(includeSupplyPrice
    ? { supply_price: firstDefinedPrice(priceRow?.supply_price, drug?.transfer_unit_price) }
    : {}),
  ...(includeCost
    ? { acquisition_cost: firstDefinedPrice(priceRow?.acquisition_cost, drug?.buy_unit_price) }
    : {}),
  currency: normalizeCurrency(priceRow?.currency, location?.currency, drug?.currency),
  is_configured: Boolean(priceRow),
});

module.exports = {
  PRICE_CONTEXTS,
  findLocationPrice,
  resolveLocationPrice,
  requireSupplyPrice,
  buildLocationPriceSnapshot,
  toDecimalString,
};
