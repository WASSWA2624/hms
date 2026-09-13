/**
 * Public module validation schemas
 */

const { z } = require('zod');
const { listQuerySchema } = require('@lib/validation/zod');

const listPublicResourcesQuerySchema = listQuerySchema.extend({
  search: z.string().trim().optional()
});

/**
 * Facility logo storage keys only: `logo-{id8}.png`.
 *
 * Deliberately narrow. This route is unauthenticated, so the key shape - not a
 * lookup - is what keeps it from reaching anything else in the uploads dir.
 */
const facilityLogoKeyParamsSchema = z.object({
  key: z
    .string()
    .trim()
    .regex(/^logo-[a-z0-9]{1,16}\.(png|jpe?g|webp)$/i)
});

module.exports = {
  listPublicResourcesQuerySchema,
  facilityLogoKeyParamsSchema
};
