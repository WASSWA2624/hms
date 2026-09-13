/**
 * Public routes
 */

const express = require('express');
const router = express.Router();
const publicController = require('@controllers/public/public.controller');
const { validateRequest } = require('@middlewares/validate.middleware');
const {
  listPublicResourcesQuerySchema,
  facilityLogoKeyParamsSchema
} = require('@validations/public/public.schema');

router.get('/services', validateRequest({ query: listPublicResourcesQuerySchema }), publicController.listPublicServices);
router.get('/providers', validateRequest({ query: listPublicResourcesQuerySchema }), publicController.listPublicProviders);

// Facility logos. Unauthenticated on purpose: the same files are already public
// as static assets, and serving them through the app is what attaches the CORS
// headers a browser needs to decode the image cross-origin.
router.get(
  '/facility-logos/:key',
  validateRequest({ params: facilityLogoKeyParamsSchema }),
  publicController.getFacilityLogo
);

module.exports = router;
