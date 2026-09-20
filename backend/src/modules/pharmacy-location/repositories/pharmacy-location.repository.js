/**
 * Pharmacy location repository
 *
 * @module modules/pharmacy-location/repositories
 * @description Data access for pharmacy locations, their access grants and
 * their per-location prices.
 * Per module-creation.mdc: Only standard CRUD operations in repositories.
 * Per prisma.mdc: All queries filter soft deletes (`deleted_at: null`).
 */

const prisma = require('@prisma/client');
const { HttpError } = require('@lib/errors');

const wrap = async (operation, notFoundKey) => {
  try {
    return await operation();
  } catch (error) {
    if (error.code === 'P2025') {
      throw new HttpError(notFoundKey || 'errors.pharmacy_location.not_found', 404);
    }
    if (error.code === 'P2002') {
      const target = error.meta?.target?.[0] || 'field';
      throw new HttpError('errors.database.unique_field', 409, [{ field: target }]);
    }
    if (error.code === 'P2003') {
      const target = error.meta?.field_name || 'field';
      throw new HttpError('errors.database.foreign_key_field', 400, [{ field: target }]);
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

const findById = (id, include) =>
  wrap(() =>
    prisma.pharmacy_location.findFirst({ where: { id, deleted_at: null }, include })
  );

const findMany = (where = {}, skip = 0, take = 20, orderBy = { created_at: 'desc' }, include) =>
  wrap(() =>
    prisma.pharmacy_location.findMany({
      where: { deleted_at: null, ...where },
      skip,
      take,
      orderBy,
      include,
    })
  );

const count = (where = {}) =>
  wrap(() => prisma.pharmacy_location.count({ where: { deleted_at: null, ...where } }));

const create = (data) => wrap(() => prisma.pharmacy_location.create({ data }));

const update = (id, data) => wrap(() => prisma.pharmacy_location.update({ where: { id }, data }));

const softDelete = (id) =>
  wrap(() => prisma.pharmacy_location.update({ where: { id }, data: { deleted_at: new Date() } }));

/** Clears `is_default` on the other locations of the same kind in a facility. */
const clearDefaultForKind = (facilityId, kind, exceptId) =>
  wrap(() =>
    prisma.pharmacy_location.updateMany({
      where: {
        deleted_at: null,
        facility_id: facilityId,
        kind,
        ...(exceptId ? { id: { not: exceptId } } : {}),
      },
      data: { is_default: false },
    })
  );

// ----------------------------------------------------------- access grants

const findAccessGrant = (pharmacyLocationId, userId) =>
  wrap(() =>
    prisma.pharmacy_location_user.findFirst({
      where: { deleted_at: null, pharmacy_location_id: pharmacyLocationId, user_id: userId },
    })
  );

const findAccessGrants = (where = {}, include) =>
  wrap(() =>
    prisma.pharmacy_location_user.findMany({
      where: { deleted_at: null, ...where },
      orderBy: { created_at: 'asc' },
      include,
    })
  );

const createAccessGrant = (data) => wrap(() => prisma.pharmacy_location_user.create({ data }));

const updateAccessGrant = (id, data) =>
  wrap(
    () => prisma.pharmacy_location_user.update({ where: { id }, data }),
    'errors.pharmacy_location_user.not_found'
  );

const softDeleteAccessGrant = (id) =>
  wrap(
    () =>
      prisma.pharmacy_location_user.update({
        where: { id },
        data: { deleted_at: new Date(), is_active: false },
      }),
    'errors.pharmacy_location_user.not_found'
  );

// ------------------------------------------------------------------ prices

const findPrice = (pharmacyLocationId, drugId) =>
  wrap(() =>
    prisma.pharmacy_location_price.findFirst({
      where: { deleted_at: null, pharmacy_location_id: pharmacyLocationId, drug_id: drugId },
    })
  );

const findPrices = (where = {}, skip = 0, take = 20, orderBy = { created_at: 'desc' }, include) =>
  wrap(() =>
    prisma.pharmacy_location_price.findMany({
      where: { deleted_at: null, ...where },
      skip,
      take,
      orderBy,
      include,
    })
  );

const countPrices = (where = {}) =>
  wrap(() => prisma.pharmacy_location_price.count({ where: { deleted_at: null, ...where } }));

const createPrice = (data) => wrap(() => prisma.pharmacy_location_price.create({ data }));

const updatePrice = (id, data) =>
  wrap(
    () => prisma.pharmacy_location_price.update({ where: { id }, data }),
    'errors.pharmacy_location_price.not_found'
  );

module.exports = {
  findById,
  findMany,
  count,
  create,
  update,
  softDelete,
  clearDefaultForKind,
  findAccessGrant,
  findAccessGrants,
  createAccessGrant,
  updateAccessGrant,
  softDeleteAccessGrant,
  findPrice,
  findPrices,
  countPrices,
  createPrice,
  updatePrice,
};
