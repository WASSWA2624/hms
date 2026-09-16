/**
 * Effective facility phone/email.
 *
 * A facility without its own phone or email uses the tenant's contact for the
 * missing value. Inheritance is computed on read and never copied into contact
 * rows, so a tenant contact change flows through at once and the facility's own
 * contact always wins.
 *
 * @module lib/facility/effective-facility-contact
 */

const {
  resolveTenantContact,
  normalizeText,
} = require('@lib/tenant/resolve-tenant-contact');

/** Where an effective contact value came from. */
const FACILITY_CONTACT_SOURCES = Object.freeze({
  FACILITY: 'FACILITY',
  TENANT: 'TENANT',
  NONE: 'NONE',
});

const isLiveContact = (entry) => entry && !entry.deleted_at;

/**
 * The facility's own primary phone and email from its `contact` rows: the
 * primary row of each type, else the first one.
 *
 * @param {Array<Object>} [contacts] - Facility `contact` rows
 * @returns {{ phone: string|null, email: string|null }}
 */
const pickFacilityOwnContact = (contacts = []) => {
  const live = Array.isArray(contacts) ? contacts.filter(isLiveContact) : [];
  const pick = (type) => {
    const ofType = live.filter((entry) => entry.contact_type === type);
    const chosen = ofType.find((entry) => entry.is_primary) || ofType[0] || null;
    return normalizeText(chosen?.value);
  };

  return {
    phone: pick('PHONE'),
    email: pick('EMAIL'),
  };
};

/**
 * Effective phone and email for a facility, with where each came from.
 *
 * Each field falls back independently. The tenant value is exactly what
 * `resolveTenantContact` shows as the tenant's contact.
 *
 * @param {{ phone?: string|null, email?: string|null }|null} [ownContact] -
 *   The facility's own contact values
 * @param {Object|null} [tenant] - Tenant record, loaded with
 *   `PRIMARY_TENANT_ADMIN_INCLUDE` so legacy contact fallbacks resolve
 * @returns {{
 *   phone: string|null,
 *   email: string|null,
 *   phone_source: 'FACILITY'|'TENANT'|'NONE',
 *   email_source: 'FACILITY'|'TENANT'|'NONE'
 * }}
 */
const resolveEffectiveFacilityContact = (ownContact = null, tenant = null) => {
  const tenantContact = tenant ? resolveTenantContact(tenant) : {};

  const resolveField = (ownValue, tenantValue) => {
    const own = normalizeText(ownValue);
    if (own) {
      return { value: own, source: FACILITY_CONTACT_SOURCES.FACILITY };
    }
    const inherited = normalizeText(tenantValue);
    if (inherited) {
      return { value: inherited, source: FACILITY_CONTACT_SOURCES.TENANT };
    }
    return { value: null, source: FACILITY_CONTACT_SOURCES.NONE };
  };

  const phone = resolveField(ownContact?.phone, tenantContact.phone);
  const email = resolveField(ownContact?.email, tenantContact.email);

  return {
    phone: phone.value,
    email: email.value,
    phone_source: phone.source,
    email_source: email.source,
  };
};

module.exports = {
  FACILITY_CONTACT_SOURCES,
  pickFacilityOwnContact,
  resolveEffectiveFacilityContact,
};
