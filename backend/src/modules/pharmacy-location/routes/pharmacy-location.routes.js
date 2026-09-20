/**
 * Pharmacy location routes
 *
 * @module modules/pharmacy-location/routes
 * @description Express routes for pharmacy locations, their access grants,
 * their prices and cross-pharmacy availability.
 * Per api.mdc: All endpoints under /api/v1/pharmacy-locations
 *
 * Route permissions are the coarse gate (is this a pharmacy user at all).
 * Which pharmacy they may touch, and whether they may only look, is decided
 * per row by the `pharmacy_location_user` grant inside the service.
 */

const express = require('express');
const { validateRequest } = require('@middlewares/validate.middleware');
const { authenticate, authorize } = require('@middlewares/auth.middleware');
const { PERMISSIONS } = require('@config/permissions');
const pharmacyLocationController = require('@controllers/pharmacy-location/pharmacy-location.controller');
const {
  pharmacyLocationIdParamsSchema,
  listPharmacyLocationsQuerySchema,
  createPharmacyLocationSchema,
  updatePharmacyLocationSchema,
  upsertPharmacyLocationAccessSchema,
  revokePharmacyLocationAccessParamsSchema,
  upsertPharmacyLocationPriceSchema,
  listPharmacyLocationPricesQuerySchema,
  getPharmacyLocationAvailabilityQuerySchema,
} = require('@validations/pharmacy-location/pharmacy-location.schema');

const router = express.Router();

const READ_SCOPES = [PERMISSIONS.PHARMACY_READ, PERMISSIONS.OPERATIONS_READ];
const WRITE_SCOPES = [PERMISSIONS.PHARMACY_WRITE];
const PRICE_READ_SCOPES = [PERMISSIONS.PRICING_PHARMACY_READ, PERMISSIONS.PHARMACY_READ];
const PRICE_WRITE_SCOPES = [PERMISSIONS.PRICING_PHARMACY_WRITE];
const ADMIN_SCOPES = [PERMISSIONS.FACILITY_ADMIN, PERMISSIONS.TENANT_ADMIN];

/**
 * @description List pharmacy locations visible to the caller
 * @method GET
 * @route /api/v1/pharmacy-locations
 * @authentication Required (JWT)
 * @permissions pharmacy:read or operations:read
 * @queryParams {string} [facility_id] - Restrict to one facility
 * @queryParams {string} [kind] - MAIN, HOSPITAL, BRANCH, THEATRE, WARD, OTHER
 * @queryParams {boolean} [mine_only] - Only locations the caller has a grant on
 * @returns {Object} Paginated locations with the caller's access level
 * @throws 401 Unauthorized
 * @throws 403 Tenant scope mismatch
 */
router.get(
  '/',
  validateRequest({ query: listPharmacyLocationsQuerySchema }),
  authenticate(),
  authorize(READ_SCOPES, 'permission'),
  pharmacyLocationController.listPharmacyLocations
);

/**
 * @description Create a pharmacy location
 * @method POST
 * @route /api/v1/pharmacy-locations
 * @authentication Required (JWT)
 * @permissions facility:admin or tenant:admin
 * @bodyParams {string} facility_id - Facility the pharmacy sits in
 * @bodyParams {string} name - Display name
 * @bodyParams {string} [kind] - Location kind
 * @bodyParams {boolean} [handles_procurement] - Buys from suppliers (one per facility)
 * @bodyParams {string} [supplied_by_location_id] - Pharmacy it orders stock from
 * @returns {Object} Created location
 * @throws 403 Tenant scope mismatch
 * @throws 409 Another pharmacy already holds procurement for the facility
 */
router.post(
  '/',
  validateRequest({ body: createPharmacyLocationSchema }),
  authenticate(),
  authorize(ADMIN_SCOPES, 'permission'),
  pharmacyLocationController.createPharmacyLocation
);

/**
 * @description Read this pharmacy's stock beside its supplier's availability
 * @method GET
 * @route /api/v1/pharmacy-locations/:id/availability
 * @authentication Required (JWT)
 * @permissions pharmacy:read or operations:read
 * @urlParams {string} id - Requesting pharmacy identifier
 * @queryParams {string} [compare_location_id] - Compare against this pharmacy
 * @queryParams {boolean} [below_reorder_level] - Only rows at or below reorder level
 * @returns {Object} Paginated availability rows; supplier side is quantity only
 * @throws 403 No grant on the pharmacy and no supply link to it
 */
router.get(
  '/:id/availability',
  validateRequest({
    params: pharmacyLocationIdParamsSchema,
    query: getPharmacyLocationAvailabilityQuerySchema,
  }),
  authenticate(),
  authorize(READ_SCOPES, 'permission'),
  pharmacyLocationController.getPharmacyLocationAvailability
);

/**
 * @description List who may act in a pharmacy location
 * @method GET
 * @route /api/v1/pharmacy-locations/:id/access
 * @authentication Required (JWT)
 * @permissions pharmacy:write
 * @urlParams {string} id - Location identifier
 * @returns {Object} Access grants
 * @throws 403 Caller does not manage this location
 */
router.get(
  '/:id/access',
  validateRequest({ params: pharmacyLocationIdParamsSchema }),
  authenticate(),
  authorize(WRITE_SCOPES, 'permission'),
  pharmacyLocationController.listPharmacyLocationAccess
);

/**
 * @description Grant or change a user's access to a pharmacy location
 * @method PUT
 * @route /api/v1/pharmacy-locations/:id/access
 * @authentication Required (JWT)
 * @permissions pharmacy:write
 * @urlParams {string} id - Location identifier
 * @bodyParams {string} user_id - User being granted access
 * @bodyParams {string} [access_level] - VIEW, DISPENSE or MANAGE
 * @returns {Object} The grant
 * @throws 403 Caller does not manage this location
 */
router.put(
  '/:id/access',
  validateRequest({
    params: pharmacyLocationIdParamsSchema,
    body: upsertPharmacyLocationAccessSchema,
  }),
  authenticate(),
  authorize(WRITE_SCOPES, 'permission'),
  pharmacyLocationController.upsertPharmacyLocationAccess
);

/**
 * @description Revoke a user's access to a pharmacy location
 * @method DELETE
 * @route /api/v1/pharmacy-locations/:id/access/:userId
 * @authentication Required (JWT)
 * @permissions pharmacy:write
 * @urlParams {string} id - Location identifier
 * @urlParams {string} userId - User whose access is revoked
 * @returns {void} 204 No Content
 * @throws 404 No such grant
 */
router.delete(
  '/:id/access/:userId',
  validateRequest({ params: revokePharmacyLocationAccessParamsSchema }),
  authenticate(),
  authorize(WRITE_SCOPES, 'permission'),
  pharmacyLocationController.revokePharmacyLocationAccess
);

/**
 * @description List a pharmacy's own prices
 * @method GET
 * @route /api/v1/pharmacy-locations/:id/prices
 * @authentication Required (JWT)
 * @permissions pricing:pharmacy_read or pharmacy:read
 * @urlParams {string} id - Location identifier
 * @returns {Object} Paginated prices; supply price and cost only for managers
 * @throws 403 No visibility of this pharmacy
 */
router.get(
  '/:id/prices',
  validateRequest({
    params: pharmacyLocationIdParamsSchema,
    query: listPharmacyLocationPricesQuerySchema,
  }),
  authenticate(),
  authorize(PRICE_READ_SCOPES, 'permission'),
  pharmacyLocationController.listPharmacyLocationPrices
);

/**
 * @description Set a pharmacy's own price for a drug
 * @method PUT
 * @route /api/v1/pharmacy-locations/:id/prices
 * @authentication Required (JWT)
 * @permissions pricing:pharmacy_write
 * @urlParams {string} id - Location identifier
 * @bodyParams {string} drug_id - Catalog drug
 * @bodyParams {number} [sell_price] - Price to this pharmacy's own customers
 * @bodyParams {number} [supply_price] - Price when supplying another pharmacy
 * @returns {Object} Stored price row
 * @throws 403 Caller does not manage this location
 */
router.put(
  '/:id/prices',
  validateRequest({
    params: pharmacyLocationIdParamsSchema,
    body: upsertPharmacyLocationPriceSchema,
  }),
  authenticate(),
  authorize(PRICE_WRITE_SCOPES, 'permission'),
  pharmacyLocationController.upsertPharmacyLocationPrice
);

/**
 * @description Get one pharmacy location
 * @method GET
 * @route /api/v1/pharmacy-locations/:id
 * @authentication Required (JWT)
 * @permissions pharmacy:read or operations:read
 * @urlParams {string} id - Location id, friendly id, code or kind
 * @returns {Object} Location with the caller's access level
 * @throws 404 Location not found in scope
 */
router.get(
  '/:id',
  validateRequest({ params: pharmacyLocationIdParamsSchema }),
  authenticate(),
  authorize(READ_SCOPES, 'permission'),
  pharmacyLocationController.getPharmacyLocation
);

/**
 * @description Update a pharmacy location
 * @method PUT
 * @route /api/v1/pharmacy-locations/:id
 * @authentication Required (JWT)
 * @permissions pharmacy:write
 * @urlParams {string} id - Location identifier
 * @returns {Object} Updated location
 * @throws 403 Caller does not manage this location
 */
router.put(
  '/:id',
  validateRequest({
    params: pharmacyLocationIdParamsSchema,
    body: updatePharmacyLocationSchema,
  }),
  authenticate(),
  authorize(WRITE_SCOPES, 'permission'),
  pharmacyLocationController.updatePharmacyLocation
);

/**
 * @description Remove a pharmacy location
 * @method DELETE
 * @route /api/v1/pharmacy-locations/:id
 * @authentication Required (JWT)
 * @permissions facility:admin or tenant:admin
 * @urlParams {string} id - Location identifier
 * @returns {void} 204 No Content
 * @throws 409 Location still holds stock or supplies another pharmacy
 */
router.delete(
  '/:id',
  validateRequest({ params: pharmacyLocationIdParamsSchema }),
  authenticate(),
  authorize(ADMIN_SCOPES, 'permission'),
  pharmacyLocationController.deletePharmacyLocation
);

module.exports = router;
