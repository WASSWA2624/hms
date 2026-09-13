/**
 * Doctor orchestration service
 *
 * @module modules/doctor/services
 */

const doctorRepository = require('@repositories/doctor/doctor.repository');
const staffProfileService = require('@services/staff-profile/staff-profile.service');
const { HttpError } = require('@lib/errors');
const { hashPassword } = require('@lib/crypto');
const { createAuditLog } = require('@lib/audit');
const { resolvePlatformRole } = require('@lib/authorization/platform-access-catalog');

const BCRYPT_PREFIX_REGEX = /^\$2[aby]\$\d{2}\$/;
const {
  PRACTITIONER_TYPES,
  CONSULTATION_FEE_PRACTITIONER_TYPES,
  CLINICAL_PRESCRIBER_ROLE_NAMES,
} = require('@lib/hr/reference-data');
const ROLE_DOCTOR = 'DOCTOR';
const CLINICAL_ROLE_NAMES = CLINICAL_PRESCRIBER_ROLE_NAMES;
const CONSULTATION_ELIGIBLE_TYPES = Array.from(CONSULTATION_FEE_PRACTITIONER_TYPES);

const DOCTOR_INCLUDE = {
  tenant: true,
  facility: true,
  profile: true,
  roles: {
    where: { deleted_at: null },
    include: { role: true }
  },
  staff_profile: true,
  provider_schedules: {
    where: { deleted_at: null },
    include: {
      facility: true,
      slots: {
        where: { deleted_at: null },
        orderBy: [{ override_date: 'asc' }, { start_time: 'asc' }]
      }
    },
    orderBy: [{ day_of_week: 'asc' }, { start_time: 'asc' }]
  }
};

const normalizeIdentifier = (value) => (typeof value === 'string' ? value.trim() : '');
const buildEmptyPagination = (page, limit) => ({
  page,
  limit,
  total: 0,
  totalPages: 0,
  hasNextPage: false,
  hasPreviousPage: page > 1
});

const resolveTenantByIdentifier = async (tx, identifier) => doctorRepository.findTenantByIdentifier(identifier, tx);

const resolveFacilityByIdentifier = async (tx, identifier, tenantId = null) =>
  doctorRepository.findFacilityByIdentifier(identifier, tenantId, tx);
const toNullable = (value) => {
  if (value === undefined) return undefined;
  if (value === null) return null;
  const normalized = String(value).trim();
  return normalized ? normalized : null;
};

const toDate = (value, field) => {
  const normalized = toNullable(value);
  if (normalized === undefined || normalized === null) return normalized;
  const parsed = new Date(normalized);
  if (Number.isNaN(parsed.getTime())) {
    throw new HttpError('errors.validation.invalid', 400, [{ field }]);
  }
  return parsed;
};

const ensureDateOrder = (startAt, endAt, startField, endField) => {
  if (!startAt || !endAt) return;
  if (startAt.getTime() >= endAt.getTime()) {
    throw new HttpError('errors.validation.invalid', 400, [{ field: startField }, { field: endField }]);
  }
};

const intervalsOverlap = (aStart, aEnd, bStart, bEnd) =>
  aStart.getTime() < bEnd.getTime() && bStart.getTime() < aEnd.getTime();

const dateRangesOverlap = (aFrom, aTo, bFrom, bTo) => {
  const leftStart = aFrom ? aFrom.getTime() : Number.NEGATIVE_INFINITY;
  const leftEnd = aTo ? aTo.getTime() : Number.POSITIVE_INFINITY;
  const rightStart = bFrom ? bFrom.getTime() : Number.NEGATIVE_INFINITY;
  const rightEnd = bTo ? bTo.getTime() : Number.POSITIVE_INFINITY;
  return leftStart <= rightEnd && rightStart <= leftEnd;
};

const normalizePractitionerType = (value) => {
  const normalized = normalizeIdentifier(value).toUpperCase();
  if (!normalized) return null;
  if (!PRACTITIONER_TYPES.has(normalized)) {
    throw new HttpError('errors.validation.invalid', 400, [{ field: 'practitioner_type' }]);
  }
  return normalized;
};

const normalizeCurrencyCode = (value) => {
  const normalized = normalizeIdentifier(value).toUpperCase();
  return normalized || null;
};

const hasMeaningfulValue = (value) => {
  if (value === undefined || value === null) return false;
  if (typeof value === 'number') return Number.isFinite(value);
  if (typeof value === 'string') return value.trim() !== '';
  return true;
};

const normalizeConsultationPayload = (inputData = {}, fallbackPractitionerType = null) => {
  const data = { ...inputData };
  const practitionerType =
    normalizePractitionerType(data.practitioner_type) || normalizePractitionerType(fallbackPractitionerType) || 'MO';
  const hasFee = hasMeaningfulValue(data.consultation_fee);
  const hasCurrency = hasMeaningfulValue(data.consultation_currency);

  data.practitioner_type = practitionerType;
  if (data.consultation_currency !== undefined) {
    data.consultation_currency = normalizeCurrencyCode(data.consultation_currency);
  }

  if (!CONSULTATION_FEE_PRACTITIONER_TYPES.has(practitionerType)) {
    data.consultation_fee = null;
    data.consultation_currency = null;
    data.is_fee_overridden = false;
    return data;
  }

  if (hasFee || hasCurrency) {
    data.is_fee_overridden = data.is_fee_overridden !== undefined ? Boolean(data.is_fee_overridden) : true;
    return data;
  }

  if (data.is_fee_overridden !== undefined) {
    data.is_fee_overridden = Boolean(data.is_fee_overridden);
  }

  return data;
};

// Doctors hold the platform DOCTOR role; organizations never keep a copy of it.
const resolveDoctorRole = async (tx) => {
  const role = await resolvePlatformRole(ROLE_DOCTOR, tx);
  if (!role) {
    throw new HttpError('errors.role.not_found', 404, [{ field: 'role_ids' }]);
  }
  return role;
};

const resolveRoleByIdentifier = async (tx, identifier, tenantId) => {
  const normalized = normalizeIdentifier(identifier);
  if (!normalized) return null;

  return doctorRepository.findRoleByIdentifier(normalized, tenantId, tx);
};

const resolvePositionByIdentifier = async (tx, identifier, tenantId, facilityId = null) => {
  const normalized = normalizeIdentifier(identifier);
  if (!normalized) return null;

  return doctorRepository.findStaffPositionByIdentifier(normalized, tenantId, facilityId, tx);
};

const resolveOrCreatePosition = async (tx, { positionId, positionName, tenantId, facilityId }) => {
  if (positionId) {
    const existing = await resolvePositionByIdentifier(tx, positionId, tenantId, facilityId);
    if (!existing) {
      throw new HttpError('errors.staff_position.not_found', 404, [{ field: 'position_id' }]);
    }
    return existing;
  }

  const normalizedName = normalizeIdentifier(positionName);
  if (!normalizedName) return null;

  const existingByName = await doctorRepository.findStaffPositionByName(normalizedName, tenantId, facilityId, tx);
  if (existingByName) return existingByName;

  return doctorRepository.createStaffPosition(
    {
      tenant_id: tenantId,
      facility_id: facilityId,
      name: normalizedName,
      is_active: true
    },
    tx
  );
};

const normalizePasswordPayload = async (data, isUpdate = false) => {
  const next = { ...(data || {}) };
  const rawPassword = typeof next.password === 'string' ? next.password.trim() : '';
  const providedHash = typeof next.password_hash === 'string' ? next.password_hash.trim() : '';

  if (rawPassword) {
    next.password_hash = await hashPassword(rawPassword);
  } else if (providedHash) {
    next.password_hash = BCRYPT_PREFIX_REGEX.test(providedHash) ? providedHash : await hashPassword(providedHash);
  } else if (!isUpdate) {
    throw new HttpError('errors.validation.field.required', 400, [{ field: 'password' }]);
  }

  delete next.password;
  return next;
};

const resolveDoctorByIdentifier = async (identifier, tenantId = null) => {
  const normalized = normalizeIdentifier(identifier);
  if (!normalized) return null;

  return doctorRepository.findDoctorByIdentifier(normalized, tenantId, DOCTOR_INCLUDE);
};

const mapDoctorResponse = (doctor) => {
  if (!doctor) return null;
  const staffProfile = doctor.staff_profile || {};
  const roles = Array.isArray(doctor.roles)
    ? doctor.roles
        .map((entry) => ({
          id: entry?.role?.human_friendly_id || null,
          name: entry?.role?.name || null
        }))
        .filter((entry) => entry.name)
    : [];

  const schedules = Array.isArray(doctor.provider_schedules)
    ? doctor.provider_schedules.map((schedule) => ({
        id: schedule.human_friendly_id || null,
        schedule_type: schedule.schedule_type || null,
        day_of_week: schedule.day_of_week,
        start_time: schedule.start_time,
        end_time: schedule.end_time,
        timezone: schedule.timezone || 'UTC',
        effective_from: schedule.effective_from || null,
        effective_to: schedule.effective_to || null,
        overrides: Array.isArray(schedule.slots)
          ? schedule.slots.map((slot) => ({
              id: slot.human_friendly_id || null,
              override_date: slot.override_date || null,
              start_time: slot.start_time,
              end_time: slot.end_time,
              is_available: slot.is_available !== false
            }))
          : []
      }))
    : [];

  return {
    id: doctor.human_friendly_id || null,
    email: doctor.email,
    phone: doctor.phone,
    status: doctor.status,
    tenant_id: doctor.tenant?.human_friendly_id || null,
    facility_id: doctor.facility?.human_friendly_id || null,
    position_title: doctor.position_title,
    practitioner_type: staffProfile.practitioner_type || 'MO',
    consultation_fee: staffProfile.consultation_fee || null,
    consultation_currency: staffProfile.consultation_currency || null,
    is_fee_overridden: Boolean(staffProfile.is_fee_overridden),
    position_name: staffProfile.position || null,
    roles,
    schedules,
    profile: doctor.profile || null,
    staff_profile_id: staffProfile.human_friendly_id || null
  };
};

const uniqueDoctorRows = (rows = []) => {
  const seen = new Set();
  const unique = [];
  for (const row of Array.isArray(rows) ? rows : []) {
    const keys = [
      row?.id,
      row?.human_friendly_id,
      row?.email,
      row?.phone,
      row?.staff_profile?.id,
      row?.staff_profile?.human_friendly_id,
      row?.staff_profile?.staff_number
    ]
      .map((value) =>
        String(value || '')
          .trim()
          .toUpperCase()
      )
      .filter(Boolean);
    if (keys.some((key) => seen.has(key))) {
      continue;
    }
    keys.forEach((key) => seen.add(key));
    unique.push(row);
  }
  return unique;
};

const normalizeRecurringSchedules = (entries = []) =>
  (Array.isArray(entries) ? entries : []).map((entry, index) => {
    const scheduleType = normalizeIdentifier(entry?.schedule_type).toUpperCase() || 'RECURRING';
    const dayOfWeek = Number(entry?.day_of_week);
    const startTime = toDate(entry?.start_time, `recurring_schedules.${index}.start_time`);
    const endTime = toDate(entry?.end_time, `recurring_schedules.${index}.end_time`);
    const timezone = normalizeIdentifier(entry?.timezone) || 'UTC';
    const effectiveFrom = toDate(entry?.effective_from, `recurring_schedules.${index}.effective_from`);
    const effectiveTo = toDate(entry?.effective_to, `recurring_schedules.${index}.effective_to`);

    if (!Number.isInteger(dayOfWeek) || dayOfWeek < 0 || dayOfWeek > 6) {
      throw new HttpError('errors.validation.invalid', 400, [{ field: `recurring_schedules.${index}.day_of_week` }]);
    }
    ensureDateOrder(
      startTime,
      endTime,
      `recurring_schedules.${index}.start_time`,
      `recurring_schedules.${index}.end_time`
    );
    if (effectiveFrom && effectiveTo) {
      ensureDateOrder(
        effectiveFrom,
        effectiveTo,
        `recurring_schedules.${index}.effective_from`,
        `recurring_schedules.${index}.effective_to`
      );
    }
    if (scheduleType !== 'RECURRING' && scheduleType !== 'OVERRIDE') {
      throw new HttpError('errors.validation.invalid', 400, [{ field: `recurring_schedules.${index}.schedule_type` }]);
    }

    return {
      schedule_type: scheduleType,
      day_of_week: dayOfWeek,
      start_time: startTime,
      end_time: endTime,
      timezone,
      effective_from: effectiveFrom || null,
      effective_to: effectiveTo || null
    };
  });

const normalizeScheduleOverrides = (entries = []) =>
  (Array.isArray(entries) ? entries : []).map((entry, index) => {
    const overrideDate = toDate(entry?.override_date, `schedule_overrides.${index}.override_date`);
    const startTime = toDate(entry?.start_time, `schedule_overrides.${index}.start_time`);
    const endTime = toDate(entry?.end_time, `schedule_overrides.${index}.end_time`);
    ensureDateOrder(
      startTime,
      endTime,
      `schedule_overrides.${index}.start_time`,
      `schedule_overrides.${index}.end_time`
    );
    return {
      schedule_index:
        entry?.schedule_index !== undefined && entry?.schedule_index !== null ? Number(entry.schedule_index) : null,
      override_date: overrideDate,
      start_time: startTime,
      end_time: endTime,
      is_available: entry?.is_available !== false
    };
  });

const validateRecurringConflictTx = async ({
  tx,
  tenantId,
  facilityId,
  providerUserId,
  dayOfWeek,
  startTime,
  endTime,
  timezone,
  effectiveFrom,
  effectiveTo,
  excludeScheduleIds = []
}) => {
  const existing = await doctorRepository.findRecurringSchedules(
    {
      tenantId,
      facilityId,
      providerUserId,
      dayOfWeek,
      timezone,
      excludeScheduleIds
    },
    tx
  );

  for (const schedule of existing) {
    const overlapsDates = dateRangesOverlap(
      effectiveFrom || null,
      effectiveTo || null,
      schedule.effective_from || null,
      schedule.effective_to || null
    );
    if (!overlapsDates) continue;
    if (!intervalsOverlap(startTime, endTime, schedule.start_time, schedule.end_time)) continue;
    throw new HttpError('errors.provider_schedule.overlap_detected', 409, [
      { field: 'recurring_schedules' },
      {
        field: 'conflicting_schedule_id',
        value: schedule.human_friendly_id || null
      }
    ]);
  }
};

const validateOverrideConflictsTx = async ({
  tx,
  tenantId,
  facilityId,
  providerUserId,
  timezone,
  overrides,
  excludeScheduleIds = []
}) => {
  if (!Array.isArray(overrides) || overrides.length === 0) return;

  const groupedByDate = new Map();
  for (const override of overrides) {
    const dateKey = override.override_date.toISOString().slice(0, 10);
    const existing = groupedByDate.get(dateKey) || [];
    for (const row of existing) {
      if (
        row.is_available &&
        override.is_available &&
        intervalsOverlap(row.start_time, row.end_time, override.start_time, override.end_time)
      ) {
        throw new HttpError('errors.provider_schedule.override_overlap_detected', 409, [
          { field: 'schedule_overrides' }
        ]);
      }
    }
    existing.push(override);
    groupedByDate.set(dateKey, existing);
  }

  for (const override of overrides) {
    const dateKey = override.override_date.toISOString().slice(0, 10);
    const dayStart = new Date(`${dateKey}T00:00:00.000Z`);
    const dayEnd = new Date(`${dateKey}T23:59:59.999Z`);

    const existing = await doctorRepository.findAvailabilitySlots(
      {
        tenantId,
        facilityId,
        providerUserId,
        timezone,
        dayStart,
        dayEnd,
        excludeScheduleIds
      },
      tx
    );

    for (const row of existing) {
      if (!row.is_available || !override.is_available) continue;
      if (intervalsOverlap(override.start_time, override.end_time, row.start_time, row.end_time)) {
        throw new HttpError('errors.provider_schedule.override_overlap_detected', 409, [
          { field: 'schedule_overrides' }
        ]);
      }
    }
  }
};

const createSchedulesTx = async ({
  tx,
  tenantId,
  facilityId,
  providerUserId,
  recurringSchedules = [],
  scheduleOverrides = [],
  excludeScheduleIds = []
}) => {
  const normalizedRecurring = normalizeRecurringSchedules(recurringSchedules || []);
  const normalizedOverrides = normalizeScheduleOverrides(scheduleOverrides || []);
  const createdSchedules = [];

  for (const schedule of normalizedRecurring) {
    await validateRecurringConflictTx({
      tx,
      tenantId,
      facilityId,
      providerUserId,
      dayOfWeek: schedule.day_of_week,
      startTime: schedule.start_time,
      endTime: schedule.end_time,
      timezone: schedule.timezone,
      effectiveFrom: schedule.effective_from,
      effectiveTo: schedule.effective_to,
      excludeScheduleIds
    });

    const created = await doctorRepository.createProviderSchedule(
      {
        tenant_id: tenantId,
        facility_id: facilityId ?? null,
        provider_user_id: providerUserId,
        schedule_type: schedule.schedule_type,
        day_of_week: schedule.day_of_week,
        start_time: schedule.start_time,
        end_time: schedule.end_time,
        timezone: schedule.timezone,
        effective_from: schedule.effective_from || null,
        effective_to: schedule.effective_to || null
      },
      tx
    );
    createdSchedules.push(created);
  }

  if (normalizedOverrides.length > 0) {
    const targetSchedules =
      createdSchedules.length > 0
        ? createdSchedules
        : await doctorRepository.findProviderSchedules(
            {
              deleted_at: null,
              tenant_id: tenantId,
              facility_id: facilityId ?? null,
              provider_user_id: providerUserId,
              ...(excludeScheduleIds.length > 0 ? { id: { notIn: excludeScheduleIds } } : {})
            },
            [{ day_of_week: 'asc' }, { created_at: 'asc' }],
            tx
          );

    if (targetSchedules.length === 0) {
      throw new HttpError('errors.validation.field.required', 400, [{ field: 'recurring_schedules' }]);
    }

    for (const override of normalizedOverrides) {
      const scheduleIndex =
        Number.isInteger(override.schedule_index) && override.schedule_index >= 0 ? override.schedule_index : 0;
      const targetSchedule = targetSchedules[scheduleIndex];
      if (!targetSchedule) {
        throw new HttpError('errors.validation.invalid', 400, [{ field: 'schedule_overrides.schedule_index' }]);
      }

      await validateOverrideConflictsTx({
        tx,
        tenantId,
        facilityId,
        providerUserId,
        timezone: targetSchedule.timezone || 'UTC',
        overrides: [override],
        excludeScheduleIds
      });

      await doctorRepository.createAvailabilitySlot(
        {
          schedule_id: targetSchedule.id,
          override_date: override.override_date,
          start_time: override.start_time,
          end_time: override.end_time,
          is_available: override.is_available !== false
        },
        tx
      );
    }
  }
};

const resolveRoleIds = async (tx, { tenantId, roleIds = [] }) => {
  const resolvedRoleIds = new Set();

  for (const identifier of roleIds || []) {
    const role = await resolveRoleByIdentifier(tx, identifier, tenantId);
    if (!role) {
      throw new HttpError('errors.role.not_found', 404, [{ field: 'role_ids' }]);
    }
    resolvedRoleIds.add(role.id);
  }

  const doctorRole = await resolveDoctorRole(tx);
  resolvedRoleIds.add(doctorRole.id);

  return Array.from(resolvedRoleIds);
};

const listDoctors = async (filters = {}, page = 1, limit = 20, sortBy = 'created_at', order = 'desc') => {
  const skip = (page - 1) * limit;
  const orderBy = sortBy ? { [sortBy]: order } : { created_at: 'desc' };

  let tenantId = null;
  if (filters.tenant_id) {
    const tenant = await resolveTenantByIdentifier(undefined, filters.tenant_id);
    if (!tenant) {
      return { doctors: [], pagination: buildEmptyPagination(page, limit) };
    }
    tenantId = tenant.id;
  }

  let facilityId = null;
  if (filters.facility_id) {
    const facility = await resolveFacilityByIdentifier(undefined, filters.facility_id, tenantId);
    if (!facility) {
      return { doctors: [], pagination: buildEmptyPagination(page, limit) };
    }
    facilityId = facility.id;
  }

  const includeAllStaffHosts =
    filters.meeting_hosts === true ||
    filters.meeting_hosts === 'true' ||
    filters.meeting_hosts === 1 ||
    filters.meeting_hosts === '1';

  const clinicalRoleFilter = {
    OR: [
      {
        roles: {
          some: {
            deleted_at: null,
            role: {
              deleted_at: null,
              name: { in: CLINICAL_ROLE_NAMES }
            }
          }
        }
      },
      {
        staff_profile: {
          is: {
            deleted_at: null,
            practitioner_type: { in: CONSULTATION_ELIGIBLE_TYPES }
          }
        }
      }
    ]
  };

  const where = {
    deleted_at: null,
    status: 'ACTIVE',
    staff_profile: { isNot: null },
    AND: includeAllStaffHosts ? [] : [clinicalRoleFilter],
  };

  if (tenantId) where.tenant_id = tenantId;
  if (facilityId) where.facility_id = facilityId;
  if (filters.position_title) where.position_title = { contains: filters.position_title };
  if (filters.practitioner_type) {
    where.AND.push({
      staff_profile: {
        is: {
          practitioner_type: normalizePractitionerType(filters.practitioner_type)
        }
      }
    });
  }

  if (filters.search) {
    const term = String(filters.search).trim();
    const upper = term.toUpperCase();
    where.AND.push({
      OR: [
        { human_friendly_id: { contains: upper } },
        { email: { contains: term } },
        { phone: { contains: term } },
        { position_title: { contains: term } },
        { profile: { is: { first_name: { contains: term } } } },
        { profile: { is: { last_name: { contains: term } } } },
        { profile: { is: { middle_name: { contains: term } } } },
        { staff_profile: { is: { human_friendly_id: { contains: upper } } } },
        { staff_profile: { is: { position: { contains: term } } } },
        { staff_profile: { is: { staff_number: { contains: term } } } },
        { staff_profile: { is: { practitioner_type: { contains: upper } } } }
      ]
    });
  }

  const [rows, total] = await Promise.all([
    doctorRepository.findManyDoctors(where, skip, limit, orderBy, DOCTOR_INCLUDE),
    doctorRepository.countDoctors(where)
  ]);

  return {
    doctors: uniqueDoctorRows(rows).map(mapDoctorResponse),
    pagination: {
      page,
      limit,
      total,
      totalPages: Math.ceil(total / limit),
      hasNextPage: page < Math.ceil(total / limit),
      hasPreviousPage: page > 1
    }
  };
};

const getDoctorById = async (id) => {
  const doctor = await resolveDoctorByIdentifier(id);
  if (!doctor) {
    throw new HttpError('errors.user.not_found', 404);
  }
  return mapDoctorResponse(doctor);
};

const createDoctor = async (data, actorUserId, ipAddress) => {
  const tenant = await resolveTenantByIdentifier(undefined, data.tenant_id);
  if (!tenant) {
    throw new HttpError('errors.tenant.not_found', 404, [{ field: 'tenant_id' }]);
  }

  let facility = null;
  if (data.facility_id !== undefined && data.facility_id !== null) {
    facility = await resolveFacilityByIdentifier(undefined, data.facility_id, tenant.id);
    if (!facility) {
      throw new HttpError('errors.facility.not_found', 404, [{ field: 'facility_id' }]);
    }
  }

  const tenantId = tenant.id;
  const facilityId = facility?.id || null;
  const payloadWithPassword = await normalizePasswordPayload(data, false);

  const created = await doctorRepository.runInTransaction(async (tx) => {
    const roleIds = await resolveRoleIds(tx, {
      tenantId,
      facilityId,
      roleIds: data.role_ids || []
    });

    const positionCatalog = await resolveOrCreatePosition(tx, {
      positionId: data.position_id,
      positionName: data.position_name,
      tenantId,
      facilityId
    });

    const user = await doctorRepository.createUser(
      {
        tenant_id: tenantId,
        facility_id: facilityId,
        position_title: data.position_title,
        email: data.email,
        phone: data.phone || null,
        password_hash: payloadWithPassword.password_hash,
        status: data.status || 'ACTIVE'
      },
      tx
    );

    await doctorRepository.createUserRoles(
      roleIds.map((roleId) => ({
        user_id: user.id,
        role_id: roleId,
        tenant_id: tenantId,
        facility_id: facilityId
      })),
      tx
    );

    const normalizedStaffProfilePayload = normalizeConsultationPayload(
      {
        practitioner_type: data.practitioner_type || 'MO',
        consultation_fee: data.consultation_fee ?? null,
        consultation_currency: data.consultation_currency ?? null,
        is_fee_overridden: data.is_fee_overridden
      },
      'MO'
    );

    const staffProfilePayload = await staffProfileService.buildStaffProfileCreateData({
      tenant_id: tenantId,
      user_id: user.id,
      position: positionCatalog?.name || data.position_title,
      practitioner_type: normalizedStaffProfilePayload.practitioner_type,
      consultation_fee: normalizedStaffProfilePayload.consultation_fee,
      consultation_currency: normalizedStaffProfilePayload.consultation_currency,
      is_fee_overridden: normalizedStaffProfilePayload.is_fee_overridden,
    });

    await tx.staff_profile.create({ data: staffProfilePayload });

    await createSchedulesTx({
      tx,
      tenantId,
      facilityId,
      providerUserId: user.id,
      recurringSchedules: data.recurring_schedules || [],
      scheduleOverrides: data.schedule_overrides || []
    });

    return doctorRepository.findDoctorById(user.id, DOCTOR_INCLUDE, tx);
  });

  createAuditLog({
    user_id: actorUserId,
    action: 'CREATE',
    entity: 'doctor',
    entity_id: created.id,
    diff: { after: mapDoctorResponse(created) },
    ip_address: ipAddress
  }).catch(() => {});

  return mapDoctorResponse(created);
};

const updateDoctor = async (id, data, actorUserId, ipAddress) => {
  const before = await resolveDoctorByIdentifier(id);
  if (!before) {
    throw new HttpError('errors.user.not_found', 404);
  }

  const payloadWithPassword = await normalizePasswordPayload(data, true);

  const updated = await doctorRepository.runInTransaction(async (tx) => {
    let targetFacilityId = before.facility_id;
    if (data.facility_id !== undefined) {
      if (data.facility_id === null) {
        targetFacilityId = null;
      } else {
        const resolvedFacility = await resolveFacilityByIdentifier(tx, data.facility_id, before.tenant_id);
        if (!resolvedFacility) {
          throw new HttpError('errors.facility.not_found', 404, [{ field: 'facility_id' }]);
        }
        targetFacilityId = resolvedFacility.id;
      }
    }

    const positionCatalog = await resolveOrCreatePosition(tx, {
      positionId: data.position_id,
      positionName: data.position_name,
      tenantId: before.tenant_id,
      facilityId: targetFacilityId || null
    });

    await doctorRepository.updateUser(
      before.id,
      {
        facility_id: targetFacilityId,
        position_title: data.position_title !== undefined ? data.position_title : before.position_title,
        email: data.email !== undefined ? data.email : before.email,
        phone: data.phone !== undefined ? data.phone : before.phone,
        password_hash:
          payloadWithPassword.password_hash !== undefined ? payloadWithPassword.password_hash : before.password_hash,
        status: data.status !== undefined ? data.status : before.status
      },
      tx
    );

    if (data.role_ids !== undefined) {
      const desiredRoleIds = await resolveRoleIds(tx, {
        tenantId: before.tenant_id,
        facilityId: targetFacilityId || null,
        roleIds: data.role_ids || []
      });

      const existingRoles = await doctorRepository.findUserRoles(
        {
          deleted_at: null,
          user_id: before.id,
          tenant_id: before.tenant_id,
          facility_id: targetFacilityId || null
        },
        tx
      );

      const existingRoleIds = new Set(existingRoles.map((entry) => entry.role_id));
      const desiredRoleIdSet = new Set(desiredRoleIds);

      const toDelete = existingRoles.filter((entry) => !desiredRoleIdSet.has(entry.role_id)).map((entry) => entry.id);

      if (toDelete.length > 0) {
        await doctorRepository.softDeleteUserRoles(toDelete, tx);
      }

      const toCreate = desiredRoleIds.filter((roleId) => !existingRoleIds.has(roleId));
      if (toCreate.length > 0) {
        await doctorRepository.createUserRoles(
          toCreate.map((roleId) => ({
            user_id: before.id,
            role_id: roleId,
            tenant_id: before.tenant_id,
            facility_id: targetFacilityId || null
          })),
          tx
        );
      }
    }

    const existingStaffProfile = await doctorRepository.findStaffProfileByUserId(before.id, tx);

    const normalizedStaffProfilePayload = normalizeConsultationPayload(
      {
        practitioner_type:
          data.practitioner_type !== undefined
            ? data.practitioner_type
            : existingStaffProfile?.practitioner_type || 'MO',
        consultation_fee:
          data.consultation_fee !== undefined ? data.consultation_fee : existingStaffProfile?.consultation_fee || null,
        consultation_currency:
          data.consultation_currency !== undefined
            ? data.consultation_currency
            : existingStaffProfile?.consultation_currency || null,
        is_fee_overridden:
          data.is_fee_overridden !== undefined
            ? data.is_fee_overridden
            : existingStaffProfile?.is_fee_overridden || false
      },
      existingStaffProfile?.practitioner_type || 'MO'
    );

    const staffProfileData = {
      tenant_id: before.tenant_id,
      position:
        positionCatalog?.name ||
        (data.position_title !== undefined
          ? data.position_title
          : before.staff_profile?.position || before.position_title),
      practitioner_type: normalizedStaffProfilePayload.practitioner_type,
      consultation_fee: normalizedStaffProfilePayload.consultation_fee,
      consultation_currency: normalizedStaffProfilePayload.consultation_currency,
      is_fee_overridden: normalizedStaffProfilePayload.is_fee_overridden
    };

    if (existingStaffProfile) {
      await doctorRepository.updateStaffProfile(existingStaffProfile.id, staffProfileData, tx);
    } else {
      const staffProfilePayload = await staffProfileService.buildStaffProfileCreateData({
        ...staffProfileData,
        user_id: before.id,
      });
      await tx.staff_profile.create({ data: staffProfilePayload });
    }

    if (data.recurring_schedules !== undefined) {
      const existingSchedules = await doctorRepository.findProviderSchedules(
        {
          deleted_at: null,
          tenant_id: before.tenant_id,
          facility_id: targetFacilityId || null,
          provider_user_id: before.id
        },
        undefined,
        tx
      );
      const existingScheduleIds = existingSchedules.map((entry) => entry.id);

      if (existingScheduleIds.length > 0) {
        await doctorRepository.softDeleteAvailabilitySlotsByScheduleIds(existingScheduleIds, tx);
        await doctorRepository.softDeleteProviderSchedules(existingScheduleIds, tx);
      }

      await createSchedulesTx({
        tx,
        tenantId: before.tenant_id,
        facilityId: targetFacilityId || null,
        providerUserId: before.id,
        recurringSchedules: data.recurring_schedules || [],
        scheduleOverrides: data.schedule_overrides || []
      });
    } else if (data.schedule_overrides !== undefined) {
      await createSchedulesTx({
        tx,
        tenantId: before.tenant_id,
        facilityId: targetFacilityId || null,
        providerUserId: before.id,
        recurringSchedules: [],
        scheduleOverrides: data.schedule_overrides || []
      });
    }

    return doctorRepository.findDoctorById(before.id, DOCTOR_INCLUDE, tx);
  });

  createAuditLog({
    user_id: actorUserId,
    action: 'UPDATE',
    entity: 'doctor',
    entity_id: before.id,
    diff: {
      before: mapDoctorResponse(before),
      after: mapDoctorResponse(updated)
    },
    ip_address: ipAddress
  }).catch(() => {});

  return mapDoctorResponse(updated);
};

module.exports = {
  listDoctors,
  getDoctorById,
  createDoctor,
  updateDoctor
};
