/**
 * effective-facility-contact unit tests
 */

const {
  FACILITY_CONTACT_SOURCES,
  pickFacilityOwnContact,
  resolveEffectiveFacilityContact,
} = require('@lib/facility/effective-facility-contact');

const tenantWithExtensionContact = {
  extension_json: {
    contact: {
      name: 'Acme Front Desk',
      email: 'hello@acme.test',
      phone: '+256700000100',
    },
  },
  user_roles: [
    {
      user: {
        email: 'owner@acme.test',
        phone: '+256700000111',
        profile: { first_name: 'Ada', last_name: 'Admin' },
      },
    },
  ],
};

const legacyTenant = {
  extension_json: null,
  user_roles: [
    {
      user: {
        email: 'owner@acme.test',
        phone: '+256700000111',
        profile: { first_name: 'Ada', last_name: 'Admin' },
      },
    },
  ],
};

describe('resolveEffectiveFacilityContact', () => {
  it('keeps the facility own phone and email', () => {
    expect(
      resolveEffectiveFacilityContact(
        { phone: '+256700000200', email: 'main@acme.test' },
        tenantWithExtensionContact
      )
    ).toEqual({
      phone: '+256700000200',
      email: 'main@acme.test',
      phone_source: FACILITY_CONTACT_SOURCES.FACILITY,
      email_source: FACILITY_CONTACT_SOURCES.FACILITY,
    });
  });

  it('inherits each missing field independently', () => {
    expect(
      resolveEffectiveFacilityContact(
        { phone: '+256700000200', email: '   ' },
        tenantWithExtensionContact
      )
    ).toEqual({
      phone: '+256700000200',
      email: 'hello@acme.test',
      phone_source: 'FACILITY',
      email_source: 'TENANT',
    });

    expect(
      resolveEffectiveFacilityContact(
        { phone: null, email: 'main@acme.test' },
        tenantWithExtensionContact
      )
    ).toEqual({
      phone: '+256700000100',
      email: 'main@acme.test',
      phone_source: 'TENANT',
      email_source: 'FACILITY',
    });
  });

  it('inherits what the tenant already shows as its contact', () => {
    expect(resolveEffectiveFacilityContact({}, tenantWithExtensionContact)).toEqual(
      expect.objectContaining({
        phone: '+256700000100',
        email: 'hello@acme.test',
      })
    );
    // Legacy tenants without extension contact show the primary admin's.
    expect(resolveEffectiveFacilityContact({}, legacyTenant)).toEqual({
      phone: '+256700000111',
      email: 'owner@acme.test',
      phone_source: 'TENANT',
      email_source: 'TENANT',
    });
  });

  it('reports NONE when neither the facility nor the tenant has a value', () => {
    const empty = {
      phone: null,
      email: null,
      phone_source: 'NONE',
      email_source: 'NONE',
    };
    expect(resolveEffectiveFacilityContact({}, { extension_json: {} })).toEqual(empty);
    expect(resolveEffectiveFacilityContact()).toEqual(empty);
  });
});

describe('pickFacilityOwnContact', () => {
  it('prefers primary rows and skips deleted ones', () => {
    expect(
      pickFacilityOwnContact([
        { contact_type: 'PHONE', value: '+256700000001' },
        { contact_type: 'PHONE', value: '+256700000002', is_primary: true },
        {
          contact_type: 'EMAIL',
          value: 'old@acme.test',
          is_primary: true,
          deleted_at: new Date('2026-01-01T00:00:00Z'),
        },
        { contact_type: 'EMAIL', value: ' main@acme.test ' },
      ])
    ).toEqual({ phone: '+256700000002', email: 'main@acme.test' });
  });

  it('returns nulls for missing contacts', () => {
    expect(pickFacilityOwnContact()).toEqual({ phone: null, email: null });
    expect(pickFacilityOwnContact(null)).toEqual({ phone: null, email: null });
  });
});
