const path = require('path');
const repository = require('@repositories/tenant-facility-workspace/tenant-facility-workspace.repository');
const facilityRepository = require('@repositories/facility/facility.repository');
const { HttpError } = require('@lib/errors');
const { createStorageService, sanitizeFilename } = require('@lib/storage');
const {
  resolveFacilityLogoUploadKey,
  buildFacilityLogoPublicPath,
  deleteFacilityLogoFromStorage,
  buildStableFacilityLogoKey,
  MAX_FACILITY_LOGO_BASENAME,
} = require('@lib/storage/facility-logo-storage');
const { resolveIdentifierForFilter } = require('@lib/billing/identifiers');
const { ROLES } = require('@config/roles');
const { PERMISSIONS } = require('@config/permissions');
const {
  canWriteHrFacilitySetup,
  isHrSetupOnlyUser,
} = require('@lib/setup/hr-facility-setup');
const { resolvePublicIdentifier } = require('@lib/billing/identifiers');
const { serializeSubscription } = require('@lib/subscriptions/serializers');
const {
  resolveTenantContact,
  hasResolvedContact,
} = require('@lib/tenant/resolve-tenant-contact');
const {
  pickFacilityOwnContact,
  resolveEffectiveFacilityContact,
} = require('@lib/facility/effective-facility-contact');

const safePublicId = (...values) => resolvePublicIdentifier(...values) || null;

const buildIdentifierMap = (recordGroups = []) => {
  const map = new Map();

  const register = (record) => {
    if (!record?.id) return;
    const publicId = safePublicId(record.human_friendly_id, record.id);
    if (!publicId) return;
    map.set(String(record.id), publicId);
    if (record.human_friendly_id) {
      map.set(String(record.human_friendly_id), publicId);
    }
  };

  recordGroups.flat().forEach(register);
  return map;
};

const buildSerializeContext = (tenant, facility, facilityRecords = {}) => {
  const scope = {
    tenant_id: safePublicId(tenant?.human_friendly_id, tenant?.id),
    facility_id: safePublicId(facility?.human_friendly_id, facility?.id),
  };

  const idMap = buildIdentifierMap([
    tenant ? [tenant] : [],
    facility ? [facility] : [],
    facilityRecords.departments || [],
    facilityRecords.units || [],
    facilityRecords.wards || [],
    facilityRecords.rooms || [],
    facilityRecords.beds || [],
  ]);

  return { scope, idMap };
};

const resolveFk = (value, context, scopeKey = null) => {
  if (value) {
    const mapped = context.idMap.get(String(value));
    if (mapped) return mapped;
    const direct = safePublicId(value);
    if (direct) return direct;
  }

  return scopeKey ? context.scope[scopeKey] || null : null;
};

const WRITE_ROLES = new Set([
  ROLES.PLATFORM_ADMIN,
  ROLES.TENANT_ADMIN,
  ROLES.FACILITY_ADMIN,
]);

const TENANT_WRITE_ROLES = new Set([ROLES.PLATFORM_ADMIN, ROLES.TENANT_ADMIN]);

const roleList = (user = {}) => {
  const roles = Array.isArray(user.roles) ? user.roles : [user.role];
  return roles
    .map((entry) => String(entry || '').trim().toUpperCase())
    .filter(Boolean);
};

const permissionList = (user = {}) => {
  const permissions = Array.isArray(user.permissions) ? user.permissions : [];
  return permissions
    .map((entry) => String(entry || '').trim().toLowerCase())
    .filter(Boolean);
};

const hasAnyPermission = (user = {}, required = []) => {
  const granted = new Set(permissionList(user));
  return required.some((entry) => granted.has(String(entry).toLowerCase()));
};

const canManageTenant = (user = {}) =>
  roleList(user).some((entry) => TENANT_WRITE_ROLES.has(entry)) ||
  hasAnyPermission(user, [
    PERMISSIONS.TENANT_ADMIN,
    PERMISSIONS.PLATFORM_ADMIN,
  ]);

const canManageFacility = (user = {}) =>
  roleList(user).some((entry) => WRITE_ROLES.has(entry)) ||
  hasAnyPermission(user, [
    PERMISSIONS.FACILITY_ADMIN,
    PERMISSIONS.TENANT_ADMIN,
    PERMISSIONS.PLATFORM_ADMIN,
  ]);

const canViewSubscriptions = (user = {}) =>
  roleList(user).includes(ROLES.PLATFORM_ADMIN);

const serializeTenant = (record) => {
  if (!record) return null;

  const extensionJson =
    record.extension_json && typeof record.extension_json === 'object'
      ? record.extension_json
      : {};
  const currency =
    typeof extensionJson.currency === 'string' && extensionJson.currency.trim()
      ? extensionJson.currency.trim().toUpperCase()
      : null;
  const resolvedContact = resolveTenantContact(record);
  const billingRaw =
    extensionJson.billing && typeof extensionJson.billing === 'object'
      ? extensionJson.billing
      : null;
  const consultationFee = (() => {
    const raw = billingRaw?.standard_consultation_fee;
    if (raw === null || raw === undefined) return null;
    const asString = String(raw).trim();
    return asString ? asString : null;
  })();

  return {
    id: safePublicId(record.human_friendly_id, record.id),
    resource_uuid: record.id,
    display_id: safePublicId(record.human_friendly_id, record.id),
    name: record.name,
    slug: record.slug || null,
    is_active: Boolean(record.is_active),
    extension_json: {
      currency,
      ...(hasResolvedContact(resolvedContact)
        ? {
            contact: {
              name: resolvedContact.name,
              email: resolvedContact.email,
              phone: resolvedContact.phone,
            },
          }
        : {}),
      ...(billingRaw
        ? {
            billing: {
              standard_consultation_fee: consultationFee,
            },
          }
        : {}),
    },
  };
};

/**
 * @param {Object} record - Facility row
 * @param {Object|null} [context] - Serialize context from buildSerializeContext
 * @param {Object|null} [contactAddress] - The facility's own contact/address
 * @param {Object|null} [effectiveContact] - Phone/email with tenant fallback,
 *   only known when the facility's own contacts were loaded
 * @returns {Object|null} Public facility payload
 */
const serializeFacility = (
  record,
  context = null,
  contactAddress = null,
  effectiveContact = null
) => {
  if (!record) return null;

  const extensionJson =
    record.extension_json && typeof record.extension_json === 'object'
      ? record.extension_json
      : {};
  const currency =
    typeof extensionJson.currency === 'string' && extensionJson.currency.trim()
      ? extensionJson.currency.trim().toUpperCase()
      : null;
  const billingRaw =
    extensionJson.billing && typeof extensionJson.billing === 'object'
      ? extensionJson.billing
      : null;
  const consultationFee = (() => {
    const raw = billingRaw?.standard_consultation_fee;
    if (raw === null || raw === undefined) return null;
    const asString = String(raw).trim();
    return asString ? asString : null;
  })();

  return {
    id: safePublicId(record.human_friendly_id, record.id),
    resource_uuid: record.id,
    display_id: safePublicId(record.human_friendly_id, record.id),
    tenant_id: context
      ? resolveFk(record.tenant_id, context, 'tenant_id')
      : safePublicId(record.tenant_id) || record.tenant_id || null,
    name: record.name,
    facility_type: record.facility_type,
    is_active: Boolean(record.is_active),
    phone: contactAddress?.phone || null,
    email: contactAddress?.email || null,
    address_line1: contactAddress?.address_line1 || null,
    city: contactAddress?.city || null,
    country: contactAddress?.country || null,
    // `phone`/`email` stay the facility's own values so edit forms never save
    // an inherited tenant contact as the facility's.
    effective_contact: effectiveContact || null,
    extension_json: {
      logo_url: extensionJson.logo_url || null,
      currency,
      ...(billingRaw
        ? {
            billing: {
              standard_consultation_fee: consultationFee,
            },
          }
        : {}),
    },
  };
};


const serializeDepartment = (record, context = null) => ({
  id: safePublicId(record.human_friendly_id, record.id),
  resource_uuid: record.id,
  display_id: safePublicId(record.human_friendly_id, record.id),
  tenant_id: context
    ? resolveFk(record.tenant_id, context, 'tenant_id')
    : safePublicId(record.tenant_id),
  facility_id: context
    ? resolveFk(record.facility_id, context, 'facility_id')
    : safePublicId(record.facility_id),
  name: record.name,
  short_name: record.short_name || null,
  department_type: record.department_type,
  is_active: Boolean(record.is_active),
  deleted_at: record.deleted_at || null,
});

const serializeUnit = (record, context = null) => ({
  id: safePublicId(record.human_friendly_id, record.id),
  resource_uuid: record.id,
  display_id: safePublicId(record.human_friendly_id, record.id),
  tenant_id: context
    ? resolveFk(record.tenant_id, context, 'tenant_id')
    : safePublicId(record.tenant_id),
  facility_id: context
    ? resolveFk(record.facility_id, context, 'facility_id')
    : safePublicId(record.facility_id),
  department_id: context
    ? resolveFk(record.department_id, context)
    : safePublicId(record.department_id),
  name: record.name,
  is_active: Boolean(record.is_active),
  deleted_at: record.deleted_at || null,
});

const serializeWard = (record, context = null) => ({
  id: safePublicId(record.human_friendly_id, record.id),
  resource_uuid: record.id,
  display_id: safePublicId(record.human_friendly_id, record.id),
  tenant_id: context
    ? resolveFk(record.tenant_id, context, 'tenant_id')
    : safePublicId(record.tenant_id),
  facility_id: context
    ? resolveFk(record.facility_id, context, 'facility_id')
    : safePublicId(record.facility_id),
  department_id: context
    ? resolveFk(record.department_id, context)
    : safePublicId(record.department_id),
  name: record.name,
  ward_type: record.ward_type,
  is_active: Boolean(record.is_active),
  deleted_at: record.deleted_at || null,
});

const serializeRoom = (record, context = null) => ({
  id: safePublicId(record.human_friendly_id, record.id),
  resource_uuid: record.id,
  display_id: safePublicId(record.human_friendly_id, record.id),
  tenant_id: context
    ? resolveFk(record.tenant_id, context, 'tenant_id')
    : safePublicId(record.tenant_id),
  facility_id: context
    ? resolveFk(record.facility_id, context, 'facility_id')
    : safePublicId(record.facility_id),
  ward_id: context ? resolveFk(record.ward_id, context) : safePublicId(record.ward_id),
  name: record.name,
  floor: record.floor || null,
  deleted_at: record.deleted_at || null,
});

const serializeBed = (record, context = null) => ({
  id: safePublicId(record.human_friendly_id, record.id),
  resource_uuid: record.id,
  display_id: safePublicId(record.human_friendly_id, record.id),
  tenant_id: context
    ? resolveFk(record.tenant_id, context, 'tenant_id')
    : safePublicId(record.tenant_id),
  facility_id: context
    ? resolveFk(record.facility_id, context, 'facility_id')
    : safePublicId(record.facility_id),
  ward_id: context ? resolveFk(record.ward_id, context) : safePublicId(record.ward_id),
  room_id: context ? resolveFk(record.room_id, context) : safePublicId(record.room_id),
  label: record.label,
  status: record.status,
  deleted_at: record.deleted_at || null,
});

const buildContactAddress = (contacts = [], addresses = []) => {
  const { phone, email } = pickFacilityOwnContact(contacts);
  const address = addresses[0] || null;

  return {
    phone,
    email,
    address_line1: address?.line1 || null,
    city: address?.city || null,
    country: address?.country || null,
  };
};

const buildChecklist = ({
  tenant,
  facility,
  effectiveContact,
  departments = [],
  units = [],
  wards = [],
  rooms = [],
  beds = [],
}) => {
  const hasTenant = Boolean(tenant);
  // A phone inherited from the tenant is enough to reach the facility.
  const hasFacilityIdentity =
    Boolean(facility?.name?.trim()) && Boolean(effectiveContact?.phone?.trim());
  const hasDepartments = departments.length > 0;
  const hasUnitsConfigured = units.length > 0 || departments.length > 0;
  const hasWardsConfigured = wards.length > 0 || rooms.length > 0 || beds.length > 0;
  const hasRoomsConfigured = rooms.length > 0 || beds.length > 0 || wards.length > 0;
  const hasBedsConfigured = beds.length > 0 || wards.length > 0;

  const items = [
    {
      id: 'tenant',
      label_key: 'tenant_facility.checklist.tenant',
      completed: hasTenant,
      priority: 1,
    },
    {
      id: 'facility_identity',
      label_key: 'tenant_facility.checklist.identity',
      completed: hasFacilityIdentity,
      phone_source: effectiveContact?.phone_source || 'NONE',
      priority: 3,
    },
    {
      id: 'departments',
      label_key: 'tenant_facility.checklist.departments',
      completed: hasDepartments,
      priority: 4,
    },
    {
      id: 'units',
      label_key: 'tenant_facility.checklist.units',
      completed: hasUnitsConfigured,
      priority: 5,
    },
    {
      id: 'wards',
      label_key: 'tenant_facility.checklist.wards',
      completed: hasWardsConfigured,
      priority: 6,
    },
    {
      id: 'rooms',
      label_key: 'tenant_facility.checklist.rooms',
      completed: hasRoomsConfigured,
      priority: 7,
    },
    {
      id: 'beds',
      label_key: 'tenant_facility.checklist.beds',
      completed: hasBedsConfigured,
      priority: 8,
    },
  ];

  return {
    completed_count: items.filter((entry) => entry.completed).length,
    total_count: items.length,
    items,
  };
};

const buildSubscriptionSummary = (summaryRecord) => {
  if (!summaryRecord?.subscription) return null;

  const serialized = serializeSubscription(summaryRecord.subscription);

  return {
    plan_label: serialized?.plan_label || summaryRecord.subscription?.plan?.name || null,
    status: serialized?.status || summaryRecord.subscription?.status || null,
    active_modules_count: summaryRecord.active_modules_count || 0,
    subscription_id: serialized?.id || null,
  };
};

const selectFacility = (facilities = [], facilityId = null) => {
  if (!facilities.length) return null;
  if (!facilityId) return facilities[0];

  const requested = String(facilityId).trim();
  if (!requested) return facilities[0];

  return (
    facilities.find(
      (entry) => safePublicId(entry.human_friendly_id, entry.id) === requested
    ) ||
    facilities.find((entry) => String(entry.id) === requested) ||
    facilities.find(
      (entry) =>
        String(entry.human_friendly_id || '').toUpperCase() ===
        requested.toUpperCase()
    ) ||
    facilities[0]
  );
};

const getSetup = async (filters = {}, user = {}) => {
  const scopeResult = await repository.resolveWorkspaceScope({ filters, user });
  const includeAllTenants = roleList(user).includes(ROLES.PLATFORM_ADMIN);

  if (scopeResult.state === 'tenant_context_required') {
    const tenants = await repository.findTenants(null, includeAllTenants);

    return {
      state: 'tenant_context_required',
      generated_at: new Date().toISOString(),
      tenant: null,
      facility: null,
      facilities: [],
      contact_address: buildContactAddress(),
      effective_contact: resolveEffectiveFacilityContact(),
      departments: [],
      units: [],
      wards: [],
      rooms: [],
      beds: [],
      checklist: buildChecklist({}),
      subscription_summary: null,
      permissions: {
        can_manage_tenant: canManageTenant(user),
        can_manage_facility: canManageFacility(user),
        can_manage_hr_setup: canWriteHrFacilitySetup(user),
        can_view_subscriptions: canViewSubscriptions(user),
        is_hr_setup_only: isHrSetupOnlyUser(user),
      },
      lookups: {
        tenants: tenants.map((entry) => ({
          id: safePublicId(entry.human_friendly_id, entry.id),
          label: entry.name,
        })),
        facilities: [],
      },
    };
  }

  const scope = scopeResult.scope;
  const requestedFacilityId = filters.facility_id || filters.facilityId || scope.facility_id;

  const [tenants, facilities, subscriptionSummary] = await Promise.all([
    repository.findTenants(scope, includeAllTenants),
    repository.findFacilities(scope.tenant_id),
    canViewSubscriptions(user)
      ? repository.findSubscriptionSummary(scope.tenant_id)
      : Promise.resolve(null),
  ]);

  // Platform admins get every tenant for the lookup list; the snapshot tenant
  // must still be the scoped one, since facility contacts inherit from it.
  const tenant =
    tenants.find((entry) => entry?.id === scope.tenant_id) ||
    (includeAllTenants && scope.tenant_id
      ? (await repository.findTenants(scope, false))[0]
      : tenants[0]) ||
    null;
  const selectedFacility = selectFacility(facilities, requestedFacilityId);
  // Desk tabs load structure lists themselves. Default bootstrap is context-only
  // (tenant/facility/facilities) so users/roles/catalog are not blocked on
  // departments/units/wards/rooms/beds. Pass include_structure=true for checklist.
  // Contact/address always load so printed headers and identity checks stay accurate.
  const includeStructure =
    filters.include_structure === true ||
    filters.include_structure === 'true' ||
    filters.includeStructure === true ||
    filters.includeStructure === 'true';
  const facilityScope = {
    tenant_id: scope.tenant_id,
    facility_id: selectedFacility?.id || scope.facility_id || null,
  };
  const includeDeleted =
    filters.include_deleted === true || filters.include_deleted === 'true';
  const facilityRecords = includeStructure
    ? await repository.findFacilityRecords(facilityScope, { includeDeleted })
    : {
        departments: [],
        units: [],
        wards: [],
        rooms: [],
        beds: [],
        ...(await repository.findFacilityContactRecords(facilityScope)),
      };
  const contactAddress = buildContactAddress(
    facilityRecords.contacts,
    facilityRecords.addresses
  );
  const effectiveContact = selectedFacility
    ? resolveEffectiveFacilityContact(contactAddress, tenant)
    : resolveEffectiveFacilityContact();
  const serializeContext = buildSerializeContext(
    tenant,
    selectedFacility,
    facilityRecords
  );

  const payload = {
    state: 'ready',
    generated_at: new Date().toISOString(),
    tenant: serializeTenant(tenant),
    facility: serializeFacility(
      selectedFacility,
      serializeContext,
      contactAddress,
      effectiveContact
    ),
    facilities: facilities.map((entry) => {
      const isSelected = entry?.id === selectedFacility?.id;
      return serializeFacility(
        entry,
        serializeContext,
        isSelected ? contactAddress : null,
        isSelected ? effectiveContact : null
      );
    }),
    contact_address: contactAddress,
    effective_contact: effectiveContact,
    departments: facilityRecords.departments.map((entry) =>
      serializeDepartment(entry, serializeContext)
    ),
    units: facilityRecords.units.map((entry) => serializeUnit(entry, serializeContext)),
    wards: facilityRecords.wards.map((entry) => serializeWard(entry, serializeContext)),
    rooms: facilityRecords.rooms.map((entry) => serializeRoom(entry, serializeContext)),
    beds: facilityRecords.beds.map((entry) => serializeBed(entry, serializeContext)),
    checklist: buildChecklist({
      tenant,
      facility: selectedFacility,
      effectiveContact,
      departments: facilityRecords.departments,
      units: facilityRecords.units,
      wards: facilityRecords.wards,
      rooms: facilityRecords.rooms,
      beds: facilityRecords.beds,
    }),
    subscription_summary: buildSubscriptionSummary(subscriptionSummary),
    permissions: {
      can_manage_tenant: canManageTenant(user),
      can_manage_facility: canManageFacility(user),
      can_manage_hr_setup: canWriteHrFacilitySetup(user),
      can_view_subscriptions: canViewSubscriptions(user),
      is_hr_setup_only: isHrSetupOnlyUser(user),
    },
    lookups: {
      tenants: tenants.map((entry) => ({
        id: safePublicId(entry.human_friendly_id, entry.id),
        label: entry.name,
      })),
      facilities: facilities.map((entry) => ({
        id: safePublicId(entry.human_friendly_id, entry.id),
        label: entry.name,
        facility_type: entry.facility_type,
      })),
    },
  };

  return payload;
};

const ACCEPTED_LOGO_MIME_TYPES = new Set([
  'image/jpeg',
  'image/jpg',
  'image/png',
  'image/webp',
]);

const MAX_LOGO_SIZE_BYTES = 5 * 1024 * 1024;

const normalizeUploadedLogo = (file = {}) => ({
  originalname: String(file?.originalname || file?.name || '').trim(),
  mimetype: String(file?.mimetype || file?.type || '')
    .trim()
    .toLowerCase(),
  size: Number(file?.size || 0),
  buffer: file?.buffer,
});

/** @deprecated Prefer buildStableFacilityLogoKey — kept for tests/compat. */
const buildFacilityLogoBasename = (facilityName, originalName) => {
  const extension = path.extname(originalName || '').toLowerCase() || '.png';
  const safeExt = /^\.(png|jpe?g|webp)$/.test(extension) ? extension : '.png';
  const slug = String(facilityName || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-+|-+$/g, '') || 'facility';
  const logoSuffix = '-logo';
  const maxStem = MAX_FACILITY_LOGO_BASENAME - safeExt.length;
  const maxSlug = Math.max(1, maxStem - logoSuffix.length);
  const clippedSlug =
    slug.length <= maxSlug ? slug : slug.slice(0, maxSlug).replace(/-$/, '');
  return sanitizeFilename(`${clippedSlug || 'facility'}${logoSuffix}${safeExt}`);
};

const uploadFacilityLogo = async (facilityIdentifier, file = {}, user = {}) => {
  const normalizedFile = normalizeUploadedLogo(file);
  if (!normalizedFile.originalname || !Buffer.isBuffer(normalizedFile.buffer)) {
    throw new HttpError('errors.validation.field.required', 400, [{ field: 'logo' }]);
  }
  if (!ACCEPTED_LOGO_MIME_TYPES.has(normalizedFile.mimetype)) {
    throw new HttpError('errors.validation.invalid', 400, [{ field: 'content_type' }]);
  }
  if (normalizedFile.size > MAX_LOGO_SIZE_BYTES) {
    throw new HttpError('errors.validation.invalid', 400, [{ field: 'size' }]);
  }

  const scopeResult = await repository.resolveWorkspaceScope({ filters: {}, user });
  if (scopeResult.state !== 'ready' || !scopeResult.scope?.tenant_id) {
    throw new HttpError('errors.auth.scope_mismatch', 403);
  }

  const facilityId = await resolveIdentifierForFilter({
    value: facilityIdentifier,
    model: 'facility',
    where: { tenant_id: scopeResult.scope.tenant_id },
  });
  if (!facilityId) {
    throw new HttpError('errors.facility.not_found', 404);
  }

  const facility = await facilityRepository.findById(facilityId);
  if (!facility || facility.tenant_id !== scopeResult.scope.tenant_id) {
    throw new HttpError('errors.facility.not_found', 404);
  }

  const extensionJson =
    facility.extension_json && typeof facility.extension_json === 'object'
      ? facility.extension_json
      : {};
  const existingLogoUrl =
    typeof extensionJson.logo_url === 'string' ? extensionJson.logo_url : null;

  const storage = createStorageService();
  const { storageKey, previousKey } = resolveFacilityLogoUploadKey({
    facilityId: facility.id,
    existingLogoUrl,
  });
  const uploaded = await storage.upload(normalizedFile.buffer, storageKey, {
    mimeType: normalizedFile.mimetype,
  });
  const storedPath = uploaded?.path || storageKey;
  // Persist a client-loadable relative URL under /uploads.
  const logoUrl = buildFacilityLogoPublicPath(storedPath, { cacheBust: true });

  await facilityRepository.update(facility.id, {
    extension_json: {
      ...extensionJson,
      logo_url: logoUrl,
    },
  });

  if (previousKey) {
    await deleteFacilityLogoFromStorage(storage, previousKey);
  }

  return {
    logo_url: logoUrl,
    facility_id: safePublicId(facility.human_friendly_id, facility.id),
  };
};

const deleteFacilityLogo = async (facilityIdentifier, user = {}) => {
  const scopeResult = await repository.resolveWorkspaceScope({ filters: {}, user });
  if (scopeResult.state !== 'ready' || !scopeResult.scope?.tenant_id) {
    throw new HttpError('errors.auth.scope_mismatch', 403);
  }

  const facilityId = await resolveIdentifierForFilter({
    value: facilityIdentifier,
    model: 'facility',
    where: { tenant_id: scopeResult.scope.tenant_id },
  });
  if (!facilityId) {
    throw new HttpError('errors.facility.not_found', 404);
  }

  const facility = await facilityRepository.findById(facilityId);
  if (!facility || facility.tenant_id !== scopeResult.scope.tenant_id) {
    throw new HttpError('errors.facility.not_found', 404);
  }

  const extensionJson =
    facility.extension_json && typeof facility.extension_json === 'object'
      ? facility.extension_json
      : {};
  const existingLogoUrl =
    typeof extensionJson.logo_url === 'string' ? extensionJson.logo_url : null;

  if (existingLogoUrl) {
    const storage = createStorageService();
    await deleteFacilityLogoFromStorage(storage, existingLogoUrl);
  }

  await facilityRepository.update(facility.id, {
    extension_json: {
      ...extensionJson,
      logo_url: null,
    },
  });

  return {
    logo_url: null,
    facility_id: safePublicId(facility.human_friendly_id, facility.id),
  };
};

module.exports = {
  buildFacilityLogoBasename,
  buildStableFacilityLogoKey,
  getSetup,
  uploadFacilityLogo,
  deleteFacilityLogo,
};
