/**
 * Public service
 */

const publicRepository = require('@repositories/public/public.repository');
const { HttpError } = require('@lib/errors');
const { createStorageService } = require('@lib/storage');

const FACILITY_LOGO_MIME_TYPES = {
  png: 'image/png',
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  webp: 'image/webp'
};

/**
 * Read a facility logo out of storage for public delivery.
 *
 * Facility logos are branding shown on screens and printed headers, so they are
 * served unauthenticated - the same reach they already had as static files.
 * Going through the app (rather than the web server's static handler) is what
 * puts the CORS middleware in the response path, which browsers require before
 * they will decode a cross-origin image.
 *
 * @param {string} key Storage key, pre-validated against the logo key shape.
 * @returns {Promise<{buffer: Buffer, mime_type: string}>}
 */
const getFacilityLogo = async (key) => {
  const storage = createStorageService();

  const exists = await storage.exists(key);
  if (!exists) {
    throw new HttpError('errors.facility.not_found', 404);
  }

  const extension = String(key).split('.').pop().toLowerCase();
  const buffer = await storage.download(key);

  return {
    buffer,
    mime_type: FACILITY_LOGO_MIME_TYPES[extension] || 'application/octet-stream'
  };
};

const buildPagination = (page, limit, total) => {
  const totalPages = Math.ceil(total / limit);
  return {
    page,
    limit,
    total,
    totalPages,
    hasNextPage: page < totalPages,
    hasPreviousPage: page > 1
  };
};

const listPublicServices = async (filters = {}, page = 1, limit = 20, sortBy = 'name', order = 'asc') => {
  const skip = (page - 1) * limit;
  const orderBy = { [sortBy]: order };

  const { items, total } = await publicRepository.listPublicServices(filters.search, skip, limit, orderBy);

  return {
    items,
    pagination: buildPagination(page, limit, total)
  };
};

const listPublicProviders = async (filters = {}, page = 1, limit = 20, sortBy = 'created_at', order = 'desc') => {
  const skip = (page - 1) * limit;
  const orderBy = { [sortBy]: order };

  const { items, total } = await publicRepository.listPublicProviders(filters.search, skip, limit, orderBy);

  return {
    items,
    pagination: buildPagination(page, limit, total)
  };
};

module.exports = {
  getFacilityLogo,
  listPublicServices,
  listPublicProviders
};
