/**
 * Pharmacy order routing
 *
 * @module lib/pharmacy
 * @description Decides which pharmacy fills a prescription, and refuses a
 * dispense attempt from any other one.
 *
 *   Hospital consultation -> HOSPITAL origin -> hospital pharmacy -> dispense
 *   Walk-in / counter sale -> WALK_IN origin -> main pharmacy    -> dispense / sale
 *
 * Origin is derived from where the prescription came from, not from who is
 * looking at it: an order raised against an encounter is hospital work, and one
 * raised without an encounter is a counter sale. A caller may state the origin
 * explicitly when neither rule fits.
 */

const { HttpError } = require('@lib/errors');
const {
  ORDER_ORIGINS,
  resolveDispensingLocationForOrigin,
  findPharmacyLocation,
} = require('@lib/pharmacy/pharmacy-location-access');

const normalizeIdentifier = (value) => (typeof value === 'string' ? value.trim() : '');
const normalizeUpper = (value) => normalizeIdentifier(value).toUpperCase();

/**
 * Derive a prescription's origin.
 *
 * @param {Object} params
 * @param {string} [params.explicitOrigin] - Caller-stated origin
 * @param {string} [params.encounterId] - Encounter the order was raised against
 * @returns {string} `HOSPITAL` or `WALK_IN`
 */
const resolveOrderOrigin = ({ explicitOrigin = null, encounterId = null } = {}) => {
  const stated = normalizeUpper(explicitOrigin);
  if (stated === ORDER_ORIGINS.HOSPITAL || stated === ORDER_ORIGINS.WALK_IN) {
    return stated;
  }
  return normalizeIdentifier(encounterId) ? ORDER_ORIGINS.HOSPITAL : ORDER_ORIGINS.WALK_IN;
};

/**
 * Work out the origin and dispensing pharmacy for a new prescription.
 *
 * Returns a null `pharmacy_location_id` when the facility has no pharmacy
 * locations configured, so an install that has not adopted them yet keeps
 * working exactly as before.
 *
 * @param {Object} client - Prisma client or transaction
 * @param {Object} params
 * @param {string} [params.explicitOrigin] - Caller-stated origin
 * @param {string} [params.explicitLocationId] - Caller-stated pharmacy
 * @param {string} [params.encounterId] - Encounter the order belongs to
 * @param {string} [params.facilityId] - Facility to route inside
 * @param {string} [params.tenantId] - Tenant scope
 * @returns {Promise<{origin: string, pharmacy_location_id: string|null, location: Object|null}>}
 *   Routing decision
 */
const resolvePharmacyOrderRouting = async (
  client,
  { explicitOrigin = null, explicitLocationId = null, encounterId = null, facilityId = null, tenantId = null } = {}
) => {
  const origin = resolveOrderOrigin({ explicitOrigin, encounterId });

  if (explicitLocationId) {
    const location = await findPharmacyLocation(client, explicitLocationId, { tenantId });
    if (!location) {
      throw new HttpError('errors.pharmacy_location.not_found', 404, [
        { field: 'pharmacy_location_id' },
      ]);
    }
    return { origin, pharmacy_location_id: location.id, location };
  }

  if (!facilityId) {
    return { origin, pharmacy_location_id: null, location: null };
  }

  const location = await resolveDispensingLocationForOrigin(client, {
    facilityId,
    origin,
    tenantId,
  });

  return { origin, pharmacy_location_id: location?.id || null, location: location || null };
};

/**
 * Refuse a dispense from a pharmacy the order does not belong to.
 *
 * An order with no pharmacy recorded (pre-migration, or a facility that has not
 * configured locations) is dispensed wherever the user is, so introducing
 * locations does not strand existing prescriptions.
 *
 * @param {Object} params
 * @param {Object} params.order - Pharmacy order row
 * @param {Object|null} params.dispensingLocation - Pharmacy attempting to dispense
 * @returns {void} Returns when the dispense is allowed
 * @throws {HttpError} 403 when the order belongs to another pharmacy
 */
const assertOrderDispensableAt = ({ order, dispensingLocation }) => {
  const orderLocationId = normalizeIdentifier(order?.pharmacy_location_id);
  if (!orderLocationId) return;
  if (!dispensingLocation) return;

  if (String(orderLocationId) !== String(dispensingLocation.id)) {
    throw new HttpError('errors.pharmacy_location.wrong_pharmacy_for_order', 403, [
      {
        pharmacy_order_id: order?.id || null,
        expected_pharmacy_location_id: orderLocationId,
        actual_pharmacy_location_id: dispensingLocation.id,
      },
    ]);
  }
};

module.exports = {
  ORDER_ORIGINS,
  resolveOrderOrigin,
  resolvePharmacyOrderRouting,
  assertOrderDispensableAt,
};
