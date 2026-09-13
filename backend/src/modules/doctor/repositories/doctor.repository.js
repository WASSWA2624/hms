const prisma = require('@prisma/client');
const { HttpError } = require('@lib/errors');

const normalizeIdentifier = (value) => (typeof value === 'string' ? value.trim() : '');
const normalizeUpperIdentifier = (value) => normalizeIdentifier(value).toUpperCase();

const runInTransaction = async (handler) => prisma.$transaction(handler);

const findTenantByIdentifier = async (identifier, client = prisma) => {
  try {
    const normalized = normalizeUpperIdentifier(identifier);
    if (!normalized) return null;

    return await client.tenant.findFirst({
      where: {
        deleted_at: null,
        human_friendly_id: normalized,
      },
    });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

const findFacilityByIdentifier = async (identifier, tenantId = null, client = prisma) => {
  try {
    const normalized = normalizeUpperIdentifier(identifier);
    if (!normalized) return null;

    return await client.facility.findFirst({
      where: {
        deleted_at: null,
        ...(tenantId ? { tenant_id: tenantId } : {}),
        human_friendly_id: normalized,
      },
    });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

const findRoleByIdentifier = async (identifier, tenantId, client = prisma) => {
  try {
    const normalized = normalizeIdentifier(identifier);
    if (!normalized) return null;

    // Assignable roles are the platform catalog plus the tenant's own custom roles.
    // The tenant's role wins a friendly-id tie; UUIDs are never ambiguous.
    return await client.role.findFirst({
      where: {
        deleted_at: null,
        AND: [
          { OR: [{ id: normalized }, { human_friendly_id: normalized.toUpperCase() }] },
          { OR: [{ tenant_id: tenantId }, { tenant_id: null, facility_id: null }] },
        ],
      },
      orderBy: [{ tenant_id: 'desc' }],
    });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

const findStaffPositionByIdentifier = async (identifier, tenantId, facilityId = null, client = prisma) => {
  try {
    const normalized = normalizeUpperIdentifier(identifier);
    if (!normalized) return null;

    return await client.staff_position.findFirst({
      where: {
        deleted_at: null,
        tenant_id: tenantId,
        AND: [
          {
            OR: [{ facility_id: facilityId }, { facility_id: null }],
          },
          {
            human_friendly_id: normalized,
          },
        ],
      },
      orderBy: [{ facility_id: 'desc' }, { created_at: 'asc' }],
    });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

const findStaffPositionByName = async (name, tenantId, facilityId = null, client = prisma) => {
  try {
    const normalized = normalizeIdentifier(name);
    if (!normalized) return null;

    return await client.staff_position.findFirst({
      where: {
        deleted_at: null,
        tenant_id: tenantId,
        name: normalized,
        OR: [{ facility_id: facilityId }, { facility_id: null }],
      },
      orderBy: [{ facility_id: 'desc' }, { created_at: 'asc' }],
    });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

const createStaffPosition = async (data, client = prisma) => {
  try {
    return await client.staff_position.create({ data });
  } catch (error) {
    if (error.code === 'P2002') throw new HttpError('errors.database.unique_field', 409);
    if (error.code === 'P2003') throw new HttpError('errors.database.foreign_key_field', 400);
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

const findDoctorByIdentifier = async (identifier, tenantId = null, include, client = prisma) => {
  try {
    const normalized = normalizeUpperIdentifier(identifier);
    if (!normalized) return null;

    return await client.user.findFirst({
      where: {
        deleted_at: null,
        ...(tenantId ? { tenant_id: tenantId } : {}),
        human_friendly_id: normalized,
        staff_profile: {
          isNot: null,
        },
      },
      include,
    });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

const findDoctorById = async (id, include, client = prisma) => {
  try {
    return await client.user.findFirst({
      where: { id, deleted_at: null },
      include,
    });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

const findManyDoctors = async (where = {}, skip = 0, take = 20, orderBy = { created_at: 'desc' }, include, client = prisma) => {
  try {
    return await client.user.findMany({
      where,
      skip,
      take,
      orderBy,
      include,
    });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

const countDoctors = async (where = {}, client = prisma) => {
  try {
    return await client.user.count({ where });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

const findRecurringSchedules = async ({
  tenantId,
  facilityId = null,
  providerUserId,
  dayOfWeek,
  timezone,
  excludeScheduleIds = [],
}, client = prisma) => {
  try {
    return await client.provider_schedule.findMany({
      where: {
        deleted_at: null,
        tenant_id: tenantId,
        facility_id: facilityId ?? null,
        provider_user_id: providerUserId,
        day_of_week: dayOfWeek,
        schedule_type: 'RECURRING',
        timezone,
        ...(excludeScheduleIds.length > 0 ? { id: { notIn: excludeScheduleIds } } : {}),
      },
      select: {
        id: true,
        start_time: true,
        end_time: true,
        effective_from: true,
        effective_to: true,
        human_friendly_id: true,
      },
    });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

const findAvailabilitySlots = async ({
  tenantId,
  facilityId = null,
  providerUserId,
  timezone,
  dayStart,
  dayEnd,
  excludeScheduleIds = [],
}, client = prisma) => {
  try {
    return await client.availability_slot.findMany({
      where: {
        deleted_at: null,
        override_date: {
          gte: dayStart,
          lte: dayEnd,
        },
        schedule: {
          deleted_at: null,
          tenant_id: tenantId,
          facility_id: facilityId ?? null,
          provider_user_id: providerUserId,
          timezone,
          ...(excludeScheduleIds.length > 0 ? { id: { notIn: excludeScheduleIds } } : {}),
        },
      },
      select: {
        start_time: true,
        end_time: true,
        is_available: true,
      },
    });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

const createProviderSchedule = async (data, client = prisma) => {
  try {
    return await client.provider_schedule.create({ data });
  } catch (error) {
    if (error.code === 'P2002') throw new HttpError('errors.database.unique_field', 409);
    if (error.code === 'P2003') throw new HttpError('errors.database.foreign_key_field', 400);
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

const findProviderSchedules = async (where = {}, orderBy = [{ day_of_week: 'asc' }, { created_at: 'asc' }], client = prisma) => {
  try {
    return await client.provider_schedule.findMany({
      where,
      orderBy,
    });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

const createAvailabilitySlot = async (data, client = prisma) => {
  try {
    return await client.availability_slot.create({ data });
  } catch (error) {
    if (error.code === 'P2002') throw new HttpError('errors.database.unique_field', 409);
    if (error.code === 'P2003') throw new HttpError('errors.database.foreign_key_field', 400);
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

const createUser = async (data, client = prisma) => {
  try {
    return await client.user.create({ data });
  } catch (error) {
    if (error.code === 'P2002') throw new HttpError('errors.database.unique_field', 409);
    if (error.code === 'P2003') throw new HttpError('errors.database.foreign_key_field', 400);
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

const updateUser = async (id, data, client = prisma) => {
  try {
    return await client.user.update({
      where: { id },
      data,
    });
  } catch (error) {
    if (error.code === 'P2025') throw new HttpError('errors.user.not_found', 404);
    if (error.code === 'P2002') throw new HttpError('errors.database.unique_field', 409);
    if (error.code === 'P2003') throw new HttpError('errors.database.foreign_key_field', 400);
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

const createUserRoles = async (data = [], client = prisma) => {
  try {
    return await client.user_role.createMany({
      data,
      skipDuplicates: true,
    });
  } catch (error) {
    if (error.code === 'P2003') throw new HttpError('errors.database.foreign_key_field', 400);
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

const findUserRoles = async (where = {}, client = prisma) => {
  try {
    return await client.user_role.findMany({ where });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

const softDeleteUserRoles = async (ids = [], client = prisma) => {
  try {
    return await client.user_role.updateMany({
      where: { id: { in: ids } },
      data: { deleted_at: new Date() },
    });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

const findStaffProfileByUserId = async (userId, client = prisma) => {
  try {
    return await client.staff_profile.findFirst({
      where: {
        deleted_at: null,
        user_id: userId,
      },
    });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

const createStaffProfile = async (data, client = prisma) => {
  try {
    return await client.staff_profile.create({ data });
  } catch (error) {
    if (error.code === 'P2002') throw new HttpError('errors.database.unique_field', 409);
    if (error.code === 'P2003') throw new HttpError('errors.database.foreign_key_field', 400);
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

const updateStaffProfile = async (id, data, client = prisma) => {
  try {
    return await client.staff_profile.update({
      where: { id },
      data,
    });
  } catch (error) {
    if (error.code === 'P2025') throw new HttpError('errors.staff_profile.not_found', 404);
    if (error.code === 'P2002') throw new HttpError('errors.database.unique_field', 409);
    if (error.code === 'P2003') throw new HttpError('errors.database.foreign_key_field', 400);
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

const softDeleteAvailabilitySlotsByScheduleIds = async (scheduleIds = [], client = prisma) => {
  try {
    return await client.availability_slot.updateMany({
      where: {
        deleted_at: null,
        schedule_id: { in: scheduleIds },
      },
      data: { deleted_at: new Date() },
    });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

const softDeleteProviderSchedules = async (scheduleIds = [], client = prisma) => {
  try {
    return await client.provider_schedule.updateMany({
      where: {
        deleted_at: null,
        id: { in: scheduleIds },
      },
      data: { deleted_at: new Date() },
    });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

module.exports = {
  createAvailabilitySlot,
  createStaffPosition,
  createStaffProfile,
  createProviderSchedule,
  createUser,
  createUserRoles,
  countDoctors,
  findAvailabilitySlots,
  findDoctorById,
  findDoctorByIdentifier,
  findFacilityByIdentifier,
  findManyDoctors,
  findProviderSchedules,
  findRecurringSchedules,
  findRoleByIdentifier,
  findStaffPositionByIdentifier,
  findStaffPositionByName,
  findStaffProfileByUserId,
  findTenantByIdentifier,
  findUserRoles,
  runInTransaction,
  softDeleteAvailabilitySlotsByScheduleIds,
  softDeleteProviderSchedules,
  softDeleteUserRoles,
  updateStaffProfile,
  updateUser,
};
