jest.mock('@repositories/tenant-facility-workspace/tenant-facility-workspace.repository');

const repository = require('@repositories/tenant-facility-workspace/tenant-facility-workspace.repository');
const service = require('../../../../modules/tenant-facility-workspace/services/tenant-facility-workspace.service');

describe('tenant-facility-workspace service', () => {
  beforeEach(() => {
    jest.clearAllMocks();

    repository.resolveWorkspaceScope.mockResolvedValue({
      state: 'ready',
      scope: { tenant_id: 'tenant-uuid', facility_id: 'facility-uuid' },
    });
    repository.findTenants.mockResolvedValue([
      {
        id: 'tenant-uuid',
        human_friendly_id: 'TEN0001',
        name: 'Acme Hospital',
        slug: 'acme',
        is_active: true,
        extension_json: null,
        user_roles: [
          {
            user: {
              email: 'owner@acme.test',
              phone: '256700000111',
              profile: {
                first_name: 'Ada',
                last_name: 'Admin',
              },
            },
          },
        ],
      },
    ]);
    repository.findFacilities.mockResolvedValue([
      {
        id: 'facility-uuid',
        human_friendly_id: 'FAC0001',
        tenant_id: 'tenant-uuid',
        name: 'Main Campus',
        facility_type: 'HOSPITAL',
        is_active: true,
        extension_json: { logo_url: 'https://example.com/logo.png' },
      },
    ]);
    repository.findFacilityContactRecords.mockResolvedValue({
      contacts: [
        {
          id: 'contact-phone',
          contact_type: 'PHONE',
          value: '+256700000000',
        },
        {
          id: 'contact-email',
          contact_type: 'EMAIL',
          value: 'info@acme.test',
        },
      ],
      addresses: [
        {
          id: 'address-1',
          line1: 'Plot 1 Hospital Road',
          city: 'Kampala',
          country: 'UG',
        },
      ],
    });
    repository.findFacilityRecords.mockResolvedValue({
      departments: [
        {
          id: 'dept-uuid',
          human_friendly_id: 'DEP0001',
          tenant_id: 'tenant-uuid',
          facility_id: 'facility-uuid',
          name: 'Internal Medicine',
          short_name: 'IM',
          department_type: 'CLINICAL',
          is_active: true,
        },
      ],
      units: [
        {
          id: 'unit-uuid',
          human_friendly_id: 'UNT0001',
          tenant_id: 'tenant-uuid',
          facility_id: 'facility-uuid',
          department_id: 'dept-uuid',
          name: 'OPD Clinic',
          is_active: true,
        },
      ],
      wards: [
        {
          id: 'ward-uuid',
          human_friendly_id: 'WRD0001',
          tenant_id: 'tenant-uuid',
          facility_id: 'facility-uuid',
          department_id: 'dept-uuid',
          name: 'General Ward',
          ward_type: 'GENERAL',
          is_active: true,
        },
      ],
      rooms: [],
      beds: [
        {
          id: 'bed-uuid',
          human_friendly_id: 'BED0001',
          tenant_id: 'tenant-uuid',
          facility_id: 'facility-uuid',
          ward_id: 'ward-uuid',
          room_id: null,
          label: 'A1',
          status: 'AVAILABLE',
        },
      ],
      contacts: [
        {
          id: 'contact-phone',
          contact_type: 'PHONE',
          value: '+256700000000',
        },
        {
          id: 'contact-email',
          contact_type: 'EMAIL',
          value: 'info@acme.test',
        },
      ],
      addresses: [
        {
          id: 'address-1',
          line1: 'Plot 1 Hospital Road',
          city: 'Kampala',
          country: 'UG',
        },
      ],
    });
    repository.findSubscriptionSummary.mockResolvedValue({
      subscription: {
        id: 'sub-uuid',
        human_friendly_id: 'SUB0001',
        status: 'ACTIVE',
        plan: {
          id: 'plan-uuid',
          human_friendly_id: 'PLN0001',
          name: 'Premium',
          tier_code: 'PREMIUM',
        },
        module_subscriptions: [{ id: 'ms-1' }, { id: 'ms-2' }],
      },
      active_modules_count: 2,
    });
  });

  it('returns context-only setup with contact address for print branding', async () => {
    const result = await service.getSetup({}, {
      role: 'TENANT_ADMIN',
      permissions: ['subscriptions:read'],
    });

    expect(result.state).toBe('ready');
    expect(result.tenant).toEqual(
      expect.objectContaining({
        id: 'TEN0001',
        name: 'Acme Hospital',
        extension_json: expect.objectContaining({
          contact: {
            name: 'Ada Admin',
            email: 'owner@acme.test',
            phone: '256700000111',
          },
        }),
      })
    );
    expect(result.facility).toEqual(
      expect.objectContaining({
        id: 'FAC0001',
        name: 'Main Campus',
        phone: '+256700000000',
        email: 'info@acme.test',
        address_line1: 'Plot 1 Hospital Road',
      })
    );
    expect(result.departments).toHaveLength(0);
    expect(result.units).toHaveLength(0);
    expect(result.wards).toHaveLength(0);
    expect(result.beds).toHaveLength(0);
    expect(repository.findFacilityContactRecords).toHaveBeenCalledWith({
      tenant_id: 'tenant-uuid',
      facility_id: 'facility-uuid',
    });
    expect(repository.findFacilityRecords).not.toHaveBeenCalled();
    expect(result.contact_address).toEqual(
      expect.objectContaining({
        phone: '+256700000000',
        email: 'info@acme.test',
        address_line1: 'Plot 1 Hospital Road',
      })
    );
    expect(result.checklist.completed_count).toBeGreaterThan(0);
    expect(result.subscription_summary).toBeNull();
    expect(result.permissions.can_manage_tenant).toBe(true);
  });

  it('includes facility billing defaults in setup facility payload', async () => {
    repository.findFacilities.mockResolvedValue([
      {
        id: 'facility-uuid',
        human_friendly_id: 'FAC0001',
        tenant_id: 'tenant-uuid',
        name: 'Main Campus',
        facility_type: 'HOSPITAL',
        is_active: true,
        extension_json: {
          logo_url: 'https://example.com/logo.png',
          currency: 'ugx',
          billing: { standard_consultation_fee: '20000' },
        },
      },
    ]);

    const result = await service.getSetup({}, { role: 'TENANT_ADMIN' });

    expect(result.facility.extension_json).toEqual(
      expect.objectContaining({
        logo_url: 'https://example.com/logo.png',
        currency: 'UGX',
        billing: { standard_consultation_fee: '20000' },
      })
    );
  });

  it('loads structure lists when include_structure is requested', async () => {
    const result = await service.getSetup(
      { include_structure: true },
      { role: 'TENANT_ADMIN' }
    );

    expect(repository.findFacilityRecords).toHaveBeenCalledWith(
      {
        tenant_id: 'tenant-uuid',
        facility_id: 'facility-uuid',
      },
      expect.objectContaining({ includeDeleted: false })
    );
    expect(repository.findFacilityContactRecords).not.toHaveBeenCalled();
    expect(result.departments).toHaveLength(1);
    expect(result.units).toHaveLength(1);
    expect(result.wards).toHaveLength(1);
    expect(result.beds).toHaveLength(1);
    expect(result.contact_address.phone).toBe('+256700000000');
  });

  it('includes subscription summary for platform admins', async () => {
    const result = await service.getSetup(
      { tenant_id: 'TEN0001' },
      { role: 'PLATFORM_ADMIN', permissions: ['subscriptions:read'] }
    );

    expect(result.subscription_summary).toEqual(
      expect.objectContaining({
        plan_label: 'Premium',
        status: 'ACTIVE',
        active_modules_count: 2,
      })
    );
  });

  it('resolves scoped foreign-key public ids from uuid storage', async () => {
    const result = await service.getSetup(
      { include_structure: true },
      { role: 'TENANT_ADMIN' }
    );

    expect(result.facility.tenant_id).toBe('TEN0001');
    expect(result.departments[0].tenant_id).toBe('TEN0001');
    expect(result.departments[0].facility_id).toBe('FAC0001');
    expect(result.departments[0].resource_uuid).toBe('dept-uuid');
    expect(result.departments[0].display_id).toBe('DEP0001');
    expect(result.units[0].department_id).toBe('DEP0001');
    expect(result.units[0].resource_uuid).toBe('unit-uuid');
    expect(result.wards[0].facility_id).toBe('FAC0001');
    expect(result.beds[0].ward_id).toBe('WRD0001');
    expect(result.beds[0].resource_uuid).toBe('bed-uuid');
  });

  it('loads contact records for the selected facility when scope has no facility', async () => {
    repository.resolveWorkspaceScope.mockResolvedValue({
      state: 'ready',
      scope: { tenant_id: 'tenant-uuid', facility_id: null },
    });

    const result = await service.getSetup({}, { role: 'TENANT_ADMIN' });

    expect(repository.findFacilityContactRecords).toHaveBeenCalledWith({
      tenant_id: 'tenant-uuid',
      facility_id: 'facility-uuid',
    });
    expect(result.contact_address.phone).toBe('+256700000000');
    expect(result.facility).toEqual(
      expect.objectContaining({ id: 'FAC0001', name: 'Main Campus' })
    );
  });

  describe('effective facility contact', () => {
    const withoutFacilityContacts = () => {
      repository.findFacilityContactRecords.mockResolvedValue({
        contacts: [],
        addresses: [],
      });
    };

    it('reports the facility own phone and email as its effective contact', async () => {
      const result = await service.getSetup({}, { role: 'TENANT_ADMIN' });

      const expected = {
        phone: '+256700000000',
        email: 'info@acme.test',
        phone_source: 'FACILITY',
        email_source: 'FACILITY',
      };
      expect(result.effective_contact).toEqual(expected);
      expect(result.facility.effective_contact).toEqual(expected);
    });

    it('inherits the tenant contact without changing the facility own values', async () => {
      withoutFacilityContacts();

      const result = await service.getSetup({}, { role: 'TENANT_ADMIN' });

      expect(result.effective_contact).toEqual({
        phone: '256700000111',
        email: 'owner@acme.test',
        phone_source: 'TENANT',
        email_source: 'TENANT',
      });
      // Own values stay empty so saving the facility form never copies them.
      expect(result.contact_address.phone).toBeNull();
      expect(result.contact_address.email).toBeNull();
      expect(result.facility.phone).toBeNull();
      expect(result.facility.effective_contact.phone_source).toBe('TENANT');

      const identity = result.checklist.items.find(
        (item) => item.id === 'facility_identity'
      );
      expect(identity).toEqual(
        expect.objectContaining({ completed: true, phone_source: 'TENANT' })
      );
    });

    it('reflects tenant contact changes on the next read', async () => {
      withoutFacilityContacts();
      const first = await service.getSetup({}, { role: 'TENANT_ADMIN' });
      expect(first.effective_contact.email).toBe('owner@acme.test');

      repository.findTenants.mockResolvedValue([
        {
          id: 'tenant-uuid',
          human_friendly_id: 'TEN0001',
          name: 'Acme Hospital',
          is_active: true,
          extension_json: {
            contact: { email: 'desk@acme.test', phone: '+256700000999' },
          },
        },
      ]);
      const second = await service.getSetup({}, { role: 'TENANT_ADMIN' });

      expect(second.effective_contact).toEqual(
        expect.objectContaining({
          phone: '+256700000999',
          email: 'desk@acme.test',
        })
      );
    });

    it('leaves facility identity incomplete when no phone exists anywhere', async () => {
      withoutFacilityContacts();
      repository.findTenants.mockResolvedValue([
        {
          id: 'tenant-uuid',
          human_friendly_id: 'TEN0001',
          name: 'Acme Hospital',
          is_active: true,
          extension_json: null,
        },
      ]);

      const result = await service.getSetup({}, { role: 'TENANT_ADMIN' });

      expect(result.effective_contact.phone_source).toBe('NONE');
      const identity = result.checklist.items.find(
        (item) => item.id === 'facility_identity'
      );
      expect(identity.completed).toBe(false);
    });

    it('inherits from the scoped tenant when platform admins list every tenant', async () => {
      withoutFacilityContacts();
      repository.findTenants.mockImplementation(async (scope, includeAll) =>
        includeAll
          ? [
              {
                id: 'other-tenant-uuid',
                human_friendly_id: 'TEN0000',
                name: 'Aardvark Clinic',
                is_active: true,
                extension_json: { contact: { phone: '+256711111111' } },
              },
              {
                id: 'tenant-uuid',
                human_friendly_id: 'TEN0001',
                name: 'Acme Hospital',
                is_active: true,
                extension_json: { contact: { phone: '+256722222222' } },
              },
            ]
          : []
      );

      const result = await service.getSetup(
        { tenant_id: 'TEN0001' },
        { role: 'PLATFORM_ADMIN' }
      );

      expect(result.tenant.id).toBe('TEN0001');
      expect(result.effective_contact.phone).toBe('+256722222222');
      expect(result.lookups.tenants).toHaveLength(2);
    });

    it('loads the scoped tenant when it is beyond the platform admin list', async () => {
      withoutFacilityContacts();
      repository.findTenants.mockImplementation(async (scope, includeAll) =>
        includeAll
          ? [
              {
                id: 'other-tenant-uuid',
                human_friendly_id: 'TEN0000',
                name: 'Aardvark Clinic',
                is_active: true,
              },
            ]
          : [
              {
                id: 'tenant-uuid',
                human_friendly_id: 'TEN0001',
                name: 'Acme Hospital',
                is_active: true,
                extension_json: { contact: { phone: '+256722222222' } },
              },
            ]
      );

      const result = await service.getSetup({}, { role: 'PLATFORM_ADMIN' });

      expect(result.tenant.id).toBe('TEN0001');
      expect(result.effective_contact.phone).toBe('+256722222222');
    });
  });

  it('returns tenant context required payload without facility records', async () => {
    repository.resolveWorkspaceScope.mockResolvedValue({
      state: 'tenant_context_required',
      scope: null,
    });
    repository.findTenants.mockResolvedValue([
      {
        id: 'tenant-uuid',
        human_friendly_id: 'TEN0001',
        name: 'Acme Hospital',
        is_active: true,
      },
    ]);

    const result = await service.getSetup({}, { role: 'PLATFORM_ADMIN' });

    expect(result.state).toBe('tenant_context_required');
    expect(result.facility).toBeNull();
    expect(result.lookups.tenants).toHaveLength(1);
    expect(repository.findFacilityRecords).not.toHaveBeenCalled();
    expect(repository.findFacilityContactRecords).not.toHaveBeenCalled();
  });

  describe('buildFacilityLogoBasename', () => {
    it('builds a short slug-logo basename from the facility name', () => {
      expect(service.buildFacilityLogoBasename('Main Campus', 'photo.JPG')).toBe(
        'main-campus-logo.jpg'
      );
      expect(
        service.buildStableFacilityLogoKey('fbb67a68-8fea-4eed-a072-4869585d8466')
      ).toBe('logo-585d8466.png');
    });

    it('clips basename to 32 characters including extension', () => {
      const longName =
        'Very Long Hospital And Medical Center Name That Should Be Clipped For Filesystem Safety';
      const basename = service.buildFacilityLogoBasename(longName, 'logo.webp');
      expect(basename.length).toBeLessThanOrEqual(32);
      expect(basename.endsWith('.webp')).toBe(true);
      expect(basename).toContain('-logo');
    });
  });
});
