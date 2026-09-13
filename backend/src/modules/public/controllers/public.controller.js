/**
 * Public controller
 */

const publicService = require('@services/public/public.service');
const { asyncHandler } = require('@lib/async');
const { sendPaginated } = require('@lib/response');
const { DEFAULT_PAGE, DEFAULT_PAGE_LIMIT } = require('@config/constants');

const getFacilityLogo = asyncHandler(async (req, res) => {
  const result = await publicService.getFacilityLogo(req.params.key);

  res.setHeader('Content-Type', result.mime_type);
  // Long-lived: upload rewrites the key's `?v=` cache buster, so a changed
  // logo arrives under a new URL rather than waiting out this TTL.
  res.setHeader('Cache-Control', 'public, max-age=604800');
  res.status(200).send(result.buffer);
});

const listPublicServices = asyncHandler(async (req, res) => {
  const {
    search,
    page = DEFAULT_PAGE,
    limit = DEFAULT_PAGE_LIMIT,
    sort_by,
    order = 'asc'
  } = req.query;

  const result = await publicService.listPublicServices(
    { search },
    parseInt(page, 10),
    parseInt(limit, 10),
    sort_by || 'name',
    order
  );

  sendPaginated(res, 'messages.public.services.list.success', result.items, result.pagination);
});

const listPublicProviders = asyncHandler(async (req, res) => {
  const {
    search,
    page = DEFAULT_PAGE,
    limit = DEFAULT_PAGE_LIMIT,
    sort_by,
    order = 'desc'
  } = req.query;

  const result = await publicService.listPublicProviders(
    { search },
    parseInt(page, 10),
    parseInt(limit, 10),
    sort_by || 'created_at',
    order
  );

  sendPaginated(res, 'messages.public.providers.list.success', result.items, result.pagination);
});


module.exports = {
  getFacilityLogo,
  listPublicServices,
  listPublicProviders
};
