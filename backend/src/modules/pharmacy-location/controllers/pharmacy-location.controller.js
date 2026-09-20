/**
 * Pharmacy location controller
 *
 * @module modules/pharmacy-location/controllers
 * @description HTTP handlers for pharmacy locations, access grants, prices and
 * cross-pharmacy availability.
 * Per module-creation.mdc: Controllers handle HTTP, call services, return responses.
 */

const pharmacyLocationService = require('@services/pharmacy-location/pharmacy-location.service');
const { asyncHandler } = require('@lib/async');
const { sendSuccess, sendPaginated, sendCreated, sendNoContent } = require('@lib/response');

const readPagination = (query = {}) => ({
  page: parseInt(query.page, 10) || 1,
  limit: parseInt(query.limit, 10) || 20,
});

const listPharmacyLocations = asyncHandler(async (req, res) => {
  const { page, limit, sort_by, order, ...filters } = req.query;
  const pagination = readPagination(req.query);

  const result = await pharmacyLocationService.listPharmacyLocations(
    filters,
    pagination,
    { sort_by, order },
    req.user || {}
  );

  sendPaginated(res, 'messages.pharmacy_location.list_retrieved', result.data, {
    page: result.page,
    limit: result.limit,
    total: result.total,
    totalPages: result.totalPages,
    hasNextPage: result.hasNextPage,
    hasPreviousPage: result.hasPreviousPage,
  });
});

const getPharmacyLocation = asyncHandler(async (req, res) => {
  const location = await pharmacyLocationService.getPharmacyLocation(req.params.id, req.user || {});
  sendSuccess(res, 200, 'messages.pharmacy_location.retrieved', location);
});

const createPharmacyLocation = asyncHandler(async (req, res) => {
  const location = await pharmacyLocationService.createPharmacyLocation(
    req.body,
    req.user || {},
    req.ip
  );
  sendCreated(res, 'messages.pharmacy_location.created', location);
});

const updatePharmacyLocation = asyncHandler(async (req, res) => {
  const location = await pharmacyLocationService.updatePharmacyLocation(
    req.params.id,
    req.body,
    req.user || {},
    req.ip
  );
  sendSuccess(res, 200, 'messages.pharmacy_location.updated', location);
});

const deletePharmacyLocation = asyncHandler(async (req, res) => {
  await pharmacyLocationService.deletePharmacyLocation(req.params.id, req.user || {}, req.ip);
  sendNoContent(res);
});

const listPharmacyLocationAccess = asyncHandler(async (req, res) => {
  const grants = await pharmacyLocationService.listPharmacyLocationAccess(
    req.params.id,
    req.user || {}
  );
  sendSuccess(res, 200, 'messages.pharmacy_location.access_list_retrieved', grants);
});

const upsertPharmacyLocationAccess = asyncHandler(async (req, res) => {
  const grant = await pharmacyLocationService.upsertPharmacyLocationAccess(
    req.params.id,
    req.body,
    req.user || {},
    req.ip
  );
  sendSuccess(res, 200, 'messages.pharmacy_location.access_updated', grant);
});

const revokePharmacyLocationAccess = asyncHandler(async (req, res) => {
  await pharmacyLocationService.revokePharmacyLocationAccess(
    req.params.id,
    req.params.userId,
    req.user || {},
    req.ip
  );
  sendNoContent(res);
});

const listPharmacyLocationPrices = asyncHandler(async (req, res) => {
  const { page, limit, sort_by, order, ...filters } = req.query;
  const pagination = readPagination(req.query);

  const result = await pharmacyLocationService.listPharmacyLocationPrices(
    req.params.id,
    filters,
    pagination,
    req.user || {}
  );

  sendPaginated(res, 'messages.pharmacy_location.price_list_retrieved', result.data, {
    page: result.page,
    limit: result.limit,
    total: result.total,
    totalPages: result.totalPages,
    hasNextPage: result.hasNextPage,
    hasPreviousPage: result.hasPreviousPage,
  });
});

const upsertPharmacyLocationPrice = asyncHandler(async (req, res) => {
  const price = await pharmacyLocationService.upsertPharmacyLocationPrice(
    req.params.id,
    req.body,
    req.user || {},
    req.ip
  );
  sendSuccess(res, 200, 'messages.pharmacy_location.price_updated', price);
});

const getPharmacyLocationAvailability = asyncHandler(async (req, res) => {
  const { page, limit, sort_by, order, ...filters } = req.query;
  const pagination = readPagination(req.query);

  const result = await pharmacyLocationService.getPharmacyLocationAvailability(
    req.params.id,
    filters,
    pagination,
    req.user || {}
  );

  sendPaginated(
    res,
    'messages.pharmacy_location.availability_retrieved',
    result.data,
    {
      page: result.page,
      limit: result.limit,
      total: result.total,
      totalPages: result.totalPages,
      hasNextPage: result.hasNextPage,
      hasPreviousPage: result.hasPreviousPage,
    },
    { location: result.location, comparison_location: result.comparison_location }
  );
});

module.exports = {
  listPharmacyLocations,
  getPharmacyLocation,
  createPharmacyLocation,
  updatePharmacyLocation,
  deletePharmacyLocation,
  listPharmacyLocationAccess,
  upsertPharmacyLocationAccess,
  revokePharmacyLocationAccess,
  listPharmacyLocationPrices,
  upsertPharmacyLocationPrice,
  getPharmacyLocationAvailability,
};
