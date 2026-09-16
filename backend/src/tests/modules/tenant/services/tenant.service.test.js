/**
 * Tenant service tests
 *
 * @module tests/modules/tenant/services
 * Per testing.mdc: Mock all external dependencies
 */

const { HttpError } = require('@lib/errors');

// Mock dependencies
jest.mock('@repositories/tenant/tenant.repository');
jest.mock('@lib/audit');
jest.mock('@lib/identifiers/resolve-entity-id', () => ({
  resolveModelIdByIdentifier: jest.fn(async ({ identifier }) => identifier),
  resolveModelRecordByIdentifier: jest.fn().mockResolvedValue(null)}));
jest.mock('@lib/realtime/platform-realtime', () => ({
  publishPlatformRealtimeEvent: jest.fn().mockResolvedValue(1),
  buildTenantDashboardDeltas: jest.fn().mockReturnValue({}),
  buildFacilityDashboardDeltas: jest.fn().mockReturnValue({})}));
jest.mock('@lib/websocket/crud-realtime', () => ({
  publishCrudRealtimeEvent: jest.fn().mockResolvedValue(1)}));

jest.mock('@prisma/client', () => ({
  subscription: {
    count: jest.fn().mockResolvedValue(0)}}));

const tenantRepository = require('@repositories/tenant/tenant.repository');
const { createAuditLog } = require('@lib/audit');
const { resolveModelRecordByIdentifier } = require('@lib/identifiers/resolve-entity-id');
const { publishPlatformRealtimeEvent } = require('@lib/realtime/platform-realtime');
const { publishCrudRealtimeEvent } = require('@lib/websocket/crud-realtime');
const {
  listTenants,
  getTenantById,
  createTenant,
  updateTenant,
  deleteTenant,
  restoreTenant,
  permanentDeleteTenant} = require('@services/tenant/tenant.service');

describe('Tenant Service', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('listTenants', () => {
    it('should list tenants with default pagination', async () => {
      const mockTenants = [
        { id: 'tenant-1', name: 'Hospital A' },
        { id: 'tenant-2', name: 'Hospital B' }
      ];
      tenantRepository.findMany.mockResolvedValue(mockTenants);
      tenantRepository.count.mockResolvedValue(10);

      const result = await listTenants({}, 1, 20);

      expect(result.tenants).toHaveLength(2);
      expect(result.tenants[0]).toEqual(
        expect.objectContaining({ id: 'tenant-1', resource_uuid: 'tenant-1' }),
      );
      expect(result.tenants[1]).toEqual(
        expect.objectContaining({ id: 'tenant-2', resource_uuid: 'tenant-2' }),
      );
      expect(result.pagination).toEqual({
        page: 1,
        limit: 20,
        total: 10,
        totalPages: 1,
        hasNextPage: false,
        hasPreviousPage: false
      });
      expect(tenantRepository.findMany).toHaveBeenCalledWith(
        {},
        0,
        20,
        { created_at: 'desc' },
        { includeDeleted: false }
      );
    });

    it('should filter by is_active=true', async () => {
      const mockTenants = [{ id: 'tenant-1', name: 'Hospital A' }];
      tenantRepository.findMany.mockResolvedValue(mockTenants);
      tenantRepository.count.mockResolvedValue(1);

      const result = await listTenants({ is_active: 'true' }, 1, 20);

      expect(result.tenants).toHaveLength(1);
      expect(result.tenants[0]).toEqual(
        expect.objectContaining({ id: 'tenant-1', resource_uuid: 'tenant-1' }),
      );
      expect(tenantRepository.findMany).toHaveBeenCalledWith(
        { is_active: true },
        0,
        20,
        { created_at: 'desc' },
        { includeDeleted: false }
      );
    });

    it('should filter by is_active=false', async () => {
      const mockTenants = [{ id: 'tenant-1', name: 'Hospital A' }];
      tenantRepository.findMany.mockResolvedValue(mockTenants);
      tenantRepository.count.mockResolvedValue(1);

      const result = await listTenants({ is_active: 'false' }, 1, 20);

      expect(result.tenants).toHaveLength(1);
      expect(result.tenants[0]).toEqual(
        expect.objectContaining({ id: 'tenant-1', resource_uuid: 'tenant-1' }),
      );
      expect(tenantRepository.findMany).toHaveBeenCalledWith(
        { is_active: false },
        0,
        20,
        { created_at: 'desc' },
        { includeDeleted: false }
      );
    });

    it('should expose the current subscription package and window', async () => {
      tenantRepository.findMany.mockResolvedValue([
        {
          id: 'tenant-1',
          name: 'Hospital A',
          subscriptions: [
            {
              id: 'sub-1',
              human_friendly_id: 'SUB0000001',
              status: 'ACTIVE',
              start_date: new Date('2025-12-18T00:00:00.000Z'),
              end_date: new Date('2026-12-18T00:00:00.000Z'),
              plan: { id: 'plan-1', name: 'Pro', code: 'PRO', tier_code: 'PRO' }
            }
          ]
        }
      ]);
      tenantRepository.count.mockResolvedValue(1);

      const result = await listTenants({}, 1, 20);

      expect(result.tenants[0].subscriptions).toBeUndefined();
      expect(result.tenants[0].current_subscription).toEqual(
        expect.objectContaining({
          status: 'ACTIVE',
          plan_name: 'Pro',
          plan_code: 'PRO',
          start_date: new Date('2025-12-18T00:00:00.000Z'),
          end_date: new Date('2026-12-18T00:00:00.000Z')
        })
      );
    });

    it('should report a null current subscription for unsubscribed tenants', async () => {
      tenantRepository.findMany.mockResolvedValue([
        { id: 'tenant-1', name: 'Hospital A', subscriptions: [] }
      ]);
      tenantRepository.count.mockResolvedValue(1);

      const result = await listTenants({}, 1, 20);

      expect(result.tenants[0].current_subscription).toBeNull();
    });

    it('should list only tenants without a live subscription', async () => {
      tenantRepository.findMany.mockResolvedValue([{ id: 'tenant-1', name: 'Hospital A' }]);
      tenantRepository.count.mockResolvedValue(1);

      await listTenants({ subscription: 'none' }, 1, 20);

      expect(tenantRepository.findMany).toHaveBeenCalledWith(
        {
          subscriptions: {
            none: {
              deleted_at: null,
              status: { in: ['ACTIVE', 'TRIAL', 'PAST_DUE'] }
            }
          }
        },
        0,
        20,
        { created_at: 'desc' },
        { includeDeleted: false }
      );
    });

    it('should list only tenants that have a live subscription', async () => {
      tenantRepository.findMany.mockResolvedValue([{ id: 'tenant-2', name: 'Hospital B' }]);
      tenantRepository.count.mockResolvedValue(1);

      await listTenants({ subscription: 'active' }, 1, 20);

      expect(tenantRepository.findMany).toHaveBeenCalledWith(
        {
          subscriptions: {
            some: {
              deleted_at: null,
              status: { in: ['ACTIVE', 'TRIAL', 'PAST_DUE'] }
            }
          }
        },
        0,
        20,
        { created_at: 'desc' },
        { includeDeleted: false }
      );
    });

    it('should ignore an unknown subscription filter', async () => {
      tenantRepository.findMany.mockResolvedValue([]);
      tenantRepository.count.mockResolvedValue(0);

      await listTenants({ subscription: 'bogus' }, 1, 20);

      expect(tenantRepository.findMany).toHaveBeenCalledWith(
        {},
        0,
        20,
        { created_at: 'desc' },
        { includeDeleted: false }
      );
    });

    it('should filter by search term', async () => {
      const mockTenants = [{ id: 'tenant-1', name: 'Test Hospital' }];
      tenantRepository.findMany.mockResolvedValue(mockTenants);
      tenantRepository.count.mockResolvedValue(1);

      const result = await listTenants({ search: 'hospital' }, 1, 20);

      expect(result.tenants).toHaveLength(1);
      expect(result.tenants[0]).toEqual(
        expect.objectContaining({ id: 'tenant-1', resource_uuid: 'tenant-1' }),
      );
      expect(tenantRepository.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          OR: expect.arrayContaining([
            { name: { contains: 'hospital' } },
            { slug: { contains: 'hospital' } }
          ])
        }),
        0,
        20,
        { created_at: 'desc' },
        { includeDeleted: false }
      );
    });

    it('should handle custom sorting', async () => {
      const mockTenants = [];
      tenantRepository.findMany.mockResolvedValue(mockTenants);
      tenantRepository.count.mockResolvedValue(0);

      await listTenants({}, 1, 20, 'name', 'asc');

      expect(tenantRepository.findMany).toHaveBeenCalledWith(
        {},
        0,
        20,
        { name: 'asc' },
        { includeDeleted: false }
      );
    });

    it('should include deleted tenants when requested', async () => {
      const mockTenants = [
        { id: 'tenant-1', name: 'Active', deleted_at: null },
        { id: 'tenant-2', name: 'Deleted', deleted_at: new Date() }];
      tenantRepository.findMany.mockResolvedValue(mockTenants);
      tenantRepository.count.mockResolvedValue(2);

      const result = await listTenants({ include_deleted: true }, 1, 20, 'name', 'asc');

      expect(result.tenants).toHaveLength(2);
      expect(tenantRepository.findMany).toHaveBeenCalledWith(
        {},
        0,
        20,
        [{ deleted_at: 'asc' }, { name: 'asc' }],
        { includeDeleted: true }
      );
      expect(tenantRepository.count).toHaveBeenCalledWith({}, { includeDeleted: true });
    });

    it('should calculate pagination correctly for multiple pages', async () => {
      const mockTenants = [];
      tenantRepository.findMany.mockResolvedValue(mockTenants);
      tenantRepository.count.mockResolvedValue(50);

      const result = await listTenants({}, 2, 20);

      expect(result.pagination).toEqual({
        page: 2,
        limit: 20,
        total: 50,
        totalPages: 3,
        hasNextPage: true,
        hasPreviousPage: true
      });
    });

    it('should expose the primary tenant admin in list payloads when available', async () => {
      tenantRepository.findMany.mockResolvedValue([
        {
          id: 'tenant-1',
          name: 'Hospital A',
          user_roles: [
            {
              id: 'user-role-1',
              human_friendly_id: 'URO0000001',
              role_id: 'role-1',
              facility_id: 'facility-1',
              role: {
                id: 'role-1',
                human_friendly_id: 'ROL0000001',
                name: 'TENANT_ADMIN'},
              user: {
                id: 'user-1',
                human_friendly_id: 'USR0000001',
                email: 'tenant.admin@hms-demo.test',
                phone: '+256700000001',
                status: 'ACTIVE',
                facility_id: 'facility-1',
                profile: {
                  first_name: 'Taylor',
                  middle_name: null,
                  last_name: 'Demo'},
                facility: {
                  id: 'facility-1',
                  human_friendly_id: 'FAC0000001',
                  name: 'DemoCare General Hospital'}}}]}]);
      tenantRepository.count.mockResolvedValue(1);

      const result = await listTenants({}, 1, 20);

      expect(result.tenants).toEqual([
        expect.objectContaining({
          id: 'tenant-1',
          resource_uuid: 'tenant-1',
          name: 'Hospital A',
          extension_json: {
            contact: {
              name: 'Taylor Demo',
              email: 'tenant.admin@hms-demo.test',
              phone: '+256700000001',
            },
          },
          primary_tenant_admin: {
            id: 'user-1',
            human_friendly_id: 'USR0000001',
            email: 'tenant.admin@hms-demo.test',
            phone: '+256700000001',
            status: 'ACTIVE',
            first_name: 'Taylor',
            middle_name: null,
            last_name: 'Demo',
            full_name: 'Taylor Demo',
            facility_id: 'facility-1',
            facility_name: 'DemoCare General Hospital',
            role_id: 'role-1',
            role_human_friendly_id: 'ROL0000001',
            role_name: 'TENANT_ADMIN',
            user_role_id: 'user-role-1',
            user_role_human_friendly_id: 'URO0000001'}})]);
    });
  });

  describe('getTenantById', () => {
    it('should get tenant by ID', async () => {
      const mockTenant = {
        id: 'tenant-123',
        name: 'Test Hospital',
        slug: 'test-hospital',
        is_active: true
      };
      tenantRepository.findById.mockResolvedValue(mockTenant);

      const result = await getTenantById('tenant-123');

      expect(result).toEqual({
        ...mockTenant,
        resource_uuid: 'tenant-123',
        display_id: 'tenant-123'});
      expect(tenantRepository.findById).toHaveBeenCalledWith('tenant-123');
    });

    it('should throw HttpError if tenant not found', async () => {
      tenantRepository.findById.mockResolvedValue(null);

      await expect(getTenantById('tenant-123'))
        .rejects
        .toThrow(HttpError);
    });

    it('should expose the primary tenant admin on detail payloads when available', async () => {
      tenantRepository.findById.mockResolvedValue({
        id: 'tenant-123',
        name: 'Test Hospital',
        slug: 'test-hospital',
        is_active: true,
        user_roles: [
          {
            id: 'user-role-1',
            human_friendly_id: 'URO0000001',
            role_id: 'role-1',
            facility_id: 'facility-1',
            role: {
              id: 'role-1',
              human_friendly_id: 'ROL0000001',
              name: 'TENANT_ADMIN'},
            user: {
              id: 'user-1',
              human_friendly_id: 'USR0000001',
              email: 'tenant.admin@hms-demo.test',
              phone: '+256700000001',
              status: 'ACTIVE',
              facility_id: 'facility-1',
              profile: {
                first_name: 'Taylor',
                middle_name: null,
                last_name: 'Demo'},
              facility: {
                id: 'facility-1',
                human_friendly_id: 'FAC0000001',
                name: 'DemoCare General Hospital'}}}]});

      const result = await getTenantById('tenant-123');

      expect(result).toEqual({
        id: 'tenant-123',
        resource_uuid: 'tenant-123',
        display_id: 'tenant-123',
        name: 'Test Hospital',
        slug: 'test-hospital',
        is_active: true,
        extension_json: {
          contact: {
            name: 'Taylor Demo',
            email: 'tenant.admin@hms-demo.test',
            phone: '+256700000001',
          },
        },
        primary_tenant_admin: {
          id: 'user-1',
          human_friendly_id: 'USR0000001',
          email: 'tenant.admin@hms-demo.test',
          phone: '+256700000001',
          status: 'ACTIVE',
          first_name: 'Taylor',
          middle_name: null,
          last_name: 'Demo',
          full_name: 'Taylor Demo',
          facility_id: 'facility-1',
          facility_name: 'DemoCare General Hospital',
          role_id: 'role-1',
          role_human_friendly_id: 'ROL0000001',
          role_name: 'TENANT_ADMIN',
          user_role_id: 'user-role-1',
          user_role_human_friendly_id: 'URO0000001'}});
    });
  });

  describe('createTenant', () => {
    it('should create tenant successfully', async () => {
      const tenantData = {
        name: 'New Hospital',
        slug: 'new-hospital',
        is_active: true
      };
      const mockCreatedTenant = {
        id: 'tenant-new',
        ...tenantData,
        created_at: new Date(),
        updated_at: new Date(),
        deleted_at: null,
        version: 1
      };
      const mockCreatedFacility = {
        id: 'facility-new',
        tenant_id: mockCreatedTenant.id,
        name: 'New Hospital Main Facility',
        facility_type: 'HOSPITAL',
        is_active: true
      };
      const context = {
        user_id: 'user-123',
        tenant_id: 'tenant-123',
        ip_address: '192.168.1.1'
      };

      tenantRepository.createWithDefaultFacility.mockResolvedValue({
        tenant: mockCreatedTenant,
        facility: mockCreatedFacility
      });
      tenantRepository.findMany.mockResolvedValue([]);
      tenantRepository.releaseSlugFromSoftDeletedTenants.mockResolvedValue(undefined);
      createAuditLog.mockResolvedValue(undefined);

      const result = await createTenant(tenantData, context);

      expect(result).toEqual(
        expect.objectContaining({
          id: mockCreatedTenant.id,
          resource_uuid: mockCreatedTenant.id,
          name: mockCreatedTenant.name
        })
      );
      expect(tenantRepository.releaseSlugFromSoftDeletedTenants).toHaveBeenCalledWith('new-hospital');
      expect(tenantRepository.createWithDefaultFacility).toHaveBeenCalledWith(
        expect.objectContaining({
          name: 'New Hospital',
          slug: 'new-hospital',
          is_active: true,
          extension_json: {
            currency: 'UGX',
            billing: {
              standard_consultation_fee: 25000,
            },
          },
        }),
        { facilityName: 'New Hospital Main Facility' }
      );
      expect(createAuditLog).toHaveBeenCalledWith({
        action: 'TENANT_CREATED',
        entity: 'tenant',
        entity_id: mockCreatedTenant.id,
        user_id: context.user_id,
        tenant_id: context.tenant_id,
        facility_id: undefined,
        ip_address: context.ip_address,
        user_agent: undefined,
        details: {
          name: mockCreatedTenant.name,
          slug: mockCreatedTenant.slug,
          is_active: mockCreatedTenant.is_active,
          default_facility_id: mockCreatedFacility.id,
          confirm_similar: false,
          similar_match_ids: []
        }
      });
      expect(createAuditLog).toHaveBeenCalledWith({
        action: 'FACILITY_CREATED',
        entity: 'facility',
        entity_id: mockCreatedFacility.id,
        user_id: context.user_id,
        tenant_id: mockCreatedTenant.id,
        facility_id: mockCreatedFacility.id,
        ip_address: context.ip_address,
        user_agent: undefined,
        details: {
          tenant_id: mockCreatedFacility.tenant_id,
          name: mockCreatedFacility.name,
          facility_type: mockCreatedFacility.facility_type,
          is_active: mockCreatedFacility.is_active,
          bootstrap: true
        }
      });
      expect(publishPlatformRealtimeEvent).toHaveBeenCalledWith(
        expect.objectContaining({
          event: 'tenant.created',
          resource_type: 'tenant',
          resource_id: mockCreatedTenant.id,
          actor_user_id: context.user_id
        })
      );
      expect(publishPlatformRealtimeEvent).toHaveBeenCalledWith(
        expect.objectContaining({
          event: 'facility.created',
          resource_type: 'facility',
          resource_id: mockCreatedFacility.id,
          actor_user_id: context.user_id
        })
      );
    });

    it('should create tenant without context', async () => {
      const tenantData = {
        name: 'New Hospital'
      };
      const mockCreatedTenant = {
        id: 'tenant-new',
        ...tenantData,
        slug: null,
        is_active: true,
        created_at: new Date(),
        updated_at: new Date(),
        deleted_at: null,
        version: 1
      };
      const mockCreatedFacility = {
        id: 'facility-new',
        tenant_id: mockCreatedTenant.id,
        name: 'New Hospital Main Facility',
        facility_type: 'HOSPITAL',
        is_active: true
      };

      tenantRepository.createWithDefaultFacility.mockResolvedValue({
        tenant: mockCreatedTenant,
        facility: mockCreatedFacility
      });
      tenantRepository.findMany.mockResolvedValue([]);
      createAuditLog.mockResolvedValue(undefined);

      const result = await createTenant(tenantData);

      expect(result).toEqual(
        expect.objectContaining({
          id: mockCreatedTenant.id,
          resource_uuid: mockCreatedTenant.id,
          name: mockCreatedTenant.name
        })
      );
      expect(createAuditLog).toHaveBeenCalled();
    });

    it('should propagate repository errors', async () => {
      const error = new HttpError('errors.database.unique_field', 409);
      tenantRepository.findMany.mockResolvedValue([]);
      tenantRepository.createWithDefaultFacility.mockRejectedValue(error);

      await expect(createTenant({ name: 'Test' }))
        .rejects
        .toThrow(HttpError);
    });

    it('should reject similar tenants unless confirm_similar is true', async () => {
      tenantRepository.findMany.mockResolvedValue([
        {
          id: 'tenant-existing',
          name: 'DemoCare General Hospital',
          slug: 'democare-general-hospital',
          is_active: true,
          extension_json: {
            currency: 'UGX',
            contact: {
              name: 'Jane Doe',
              email: 'jane@example.com',
              phone: '+256700000000'
            },
            billing: { standard_consultation_fee: 50000 }
          }
        }
      ]);

      await expect(
        createTenant({
          name: 'Democare General Hospitl',
          slug: 'another-slug',
          extension_json: {
            currency: 'UGX',
            contact: {
              name: 'Jane Doe',
              email: 'jane@example.com',
              phone: '+256700000000'
            },
            billing: { standard_consultation_fee: 50000 }
          }
        })
      ).rejects.toMatchObject({
        message: 'errors.tenant.similar_exists',
        statusCode: 409
      });
      expect(tenantRepository.createWithDefaultFacility).not.toHaveBeenCalled();
    });

    it('should create anyway when confirm_similar is true', async () => {
      const tenantData = {
        name: 'Democare General Hospitl',
        slug: 'democare-general-hospitl',
        confirm_similar: true,
        extension_json: {
          currency: 'UGX',
          contact: {
            name: 'Jane Doe',
            email: 'jane@example.com',
            phone: '+256700000000'
          }
        }
      };
      const mockCreatedTenant = {
        id: 'tenant-new',
        name: tenantData.name,
        slug: tenantData.slug,
        is_active: true
      };
      const mockCreatedFacility = {
        id: 'facility-new',
        tenant_id: mockCreatedTenant.id,
        name: 'Democare General Hospitl Main Facility',
        facility_type: 'HOSPITAL',
        is_active: true
      };

      tenantRepository.findMany.mockResolvedValue([
        {
          id: 'tenant-existing',
          name: 'DemoCare General Hospital',
          slug: 'democare-general-hospital',
          is_active: true,
          extension_json: tenantData.extension_json
        }
      ]);
      tenantRepository.createWithDefaultFacility.mockResolvedValue({
        tenant: mockCreatedTenant,
        facility: mockCreatedFacility
      });
      tenantRepository.releaseSlugFromSoftDeletedTenants.mockResolvedValue(undefined);
      createAuditLog.mockResolvedValue(undefined);

      const result = await createTenant(tenantData, {
        user_id: 'user-123',
        permissions: ['SYSTEM_ADMIN']
      });

      expect(result.id).toBe('tenant-new');
      expect(tenantRepository.createWithDefaultFacility).toHaveBeenCalledWith(
        expect.not.objectContaining({ confirm_similar: true }),
        expect.any(Object)
      );
      expect(createAuditLog).toHaveBeenCalledWith(
        expect.objectContaining({
          details: expect.objectContaining({
            confirm_similar: true,
            similar_match_ids: ['tenant-existing']
          })
        })
      );
    });

    it('should never override an exact slug conflict', async () => {
      tenantRepository.findMany.mockResolvedValue([
        {
          id: 'tenant-existing',
          name: 'Other Hospital',
          slug: 'shared-slug',
          is_active: true
        }
      ]);

      await expect(
        createTenant({
          name: 'Brand New Hospital',
          slug: 'shared-slug',
          confirm_similar: true
        })
      ).rejects.toMatchObject({
        message: 'errors.tenant.duplicate_slug',
        statusCode: 409
      });
      expect(tenantRepository.createWithDefaultFacility).not.toHaveBeenCalled();
    });
  });

  describe('updateTenant', () => {
    it('should update tenant successfully', async () => {
      const updateData = {
        name: 'Updated Hospital',
        is_active: false
      };
      const mockBeforeTenant = {
        id: 'tenant-123',
        name: 'Test Hospital',
        slug: 'test-hospital',
        is_active: true
      };
      const mockUpdatedTenant = {
        ...mockBeforeTenant,
        ...updateData,
        updated_at: new Date()
      };
      const context = {
        user_id: 'user-123',
        tenant_id: 'tenant-123',
        ip_address: '192.168.1.1'
      };

      tenantRepository.findById.mockResolvedValue(mockBeforeTenant);
      tenantRepository.findMany.mockResolvedValue([mockBeforeTenant]);
      tenantRepository.update.mockResolvedValue(mockUpdatedTenant);
      createAuditLog.mockResolvedValue(undefined);

      const result = await updateTenant('tenant-123', updateData, context);

      expect(result).toEqual(
        expect.objectContaining({
          id: 'tenant-123',
          name: 'Updated Hospital',
          slug: 'test-hospital',
          is_active: false,
          resource_uuid: 'tenant-123',
          display_id: 'tenant-123'
        })
      );
      expect(tenantRepository.findById).toHaveBeenCalledWith('tenant-123');
      expect(tenantRepository.update).toHaveBeenCalledWith('tenant-123', updateData);
      expect(createAuditLog).toHaveBeenCalledWith({
        action: 'TENANT_UPDATED',
        entity: 'tenant',
        entity_id: 'tenant-123',
        user_id: context.user_id,
        tenant_id: context.tenant_id,
        facility_id: undefined,
        ip_address: context.ip_address,
        user_agent: undefined,
        details: {
          before: {
            name: mockBeforeTenant.name,
            slug: mockBeforeTenant.slug,
            is_active: mockBeforeTenant.is_active
          },
          after: {
            name: mockUpdatedTenant.name,
            slug: mockUpdatedTenant.slug,
            is_active: mockUpdatedTenant.is_active
          },
          confirm_similar: false,
          similar_match_ids: []
        }
      });
      // Tenant admins get it too: facility contacts inherit the tenant contact.
      expect(publishCrudRealtimeEvent).toHaveBeenCalledWith(
        expect.objectContaining({
          event: 'tenant.updated',
          resource: { id: 'tenant-123', tenant_id: 'tenant-123' },
          resource_type: 'tenant',
          actor_user_id: 'user-123',
          recipient_roles: ['TENANT_ADMIN', 'FACILITY_ADMIN']
        })
      );
      expect(publishPlatformRealtimeEvent).toHaveBeenCalledWith(
        expect.objectContaining({ event: 'tenant.updated' })
      );
    });

    it('should reject similar tenants on update unless confirm_similar is true', async () => {
      const mockBeforeTenant = {
        id: 'tenant-123',
        name: 'Original Hospital',
        slug: 'original-hospital',
        is_active: true
      };

      tenantRepository.findById.mockResolvedValue(mockBeforeTenant);
      tenantRepository.findMany.mockResolvedValue([
        mockBeforeTenant,
        {
          id: 'tenant-existing',
          name: 'DemoCare General Hospital',
          slug: 'democare-general-hospital',
          is_active: true,
          extension_json: {
            currency: 'UGX',
            contact: {
              name: 'Jane Doe',
              email: 'jane@example.com',
              phone: '+256700000000'
            },
            billing: { standard_consultation_fee: 50000 }
          }
        }
      ]);

      await expect(
        updateTenant('tenant-123', {
          name: 'Democare General Hospitl',
          slug: 'another-slug',
          extension_json: {
            currency: 'UGX',
            contact: {
              name: 'Jane Doe',
              email: 'jane@example.com',
              phone: '+256700000000'
            },
            billing: { standard_consultation_fee: 50000 }
          }
        })
      ).rejects.toMatchObject({
        message: 'errors.tenant.similar_exists',
        statusCode: 409
      });
      expect(tenantRepository.update).not.toHaveBeenCalled();
    });

    it('should exclude the edited tenant from similarity matches', async () => {
      const mockBeforeTenant = {
        id: 'tenant-123',
        name: 'DemoCare General Hospital',
        slug: 'democare-general-hospital',
        is_active: true,
        extension_json: {
          currency: 'UGX',
          contact: {
            name: 'Jane Doe',
            email: 'jane@example.com',
            phone: '+256700000000'
          }
        }
      };
      const mockUpdatedTenant = {
        ...mockBeforeTenant,
        name: 'DemoCare General Hospital',
        updated_at: new Date()
      };

      tenantRepository.findById.mockResolvedValue(mockBeforeTenant);
      tenantRepository.findMany.mockResolvedValue([mockBeforeTenant]);
      tenantRepository.update.mockResolvedValue(mockUpdatedTenant);
      createAuditLog.mockResolvedValue(undefined);

      const result = await updateTenant('tenant-123', {
        name: 'DemoCare General Hospital',
        slug: 'democare-general-hospital',
        extension_json: mockBeforeTenant.extension_json
      });

      expect(result.id).toBe('tenant-123');
      expect(tenantRepository.update).toHaveBeenCalled();
    });

    it('should update anyway when confirm_similar is true', async () => {
      const mockBeforeTenant = {
        id: 'tenant-123',
        name: 'Original Hospital',
        slug: 'original-hospital',
        is_active: true
      };
      const updateData = {
        name: 'Democare General Hospitl',
        slug: 'democare-general-hospitl',
        confirm_similar: true,
        extension_json: {
          currency: 'UGX',
          contact: {
            name: 'Jane Doe',
            email: 'jane@example.com',
            phone: '+256700000000'
          }
        }
      };
      const mockUpdatedTenant = {
        ...mockBeforeTenant,
        name: updateData.name,
        slug: updateData.slug,
        extension_json: updateData.extension_json,
        updated_at: new Date()
      };

      tenantRepository.findById.mockResolvedValue(mockBeforeTenant);
      tenantRepository.findMany.mockResolvedValue([
        mockBeforeTenant,
        {
          id: 'tenant-existing',
          name: 'DemoCare General Hospital',
          slug: 'democare-general-hospital',
          is_active: true,
          extension_json: updateData.extension_json
        }
      ]);
      tenantRepository.update.mockResolvedValue(mockUpdatedTenant);
      createAuditLog.mockResolvedValue(undefined);

      const result = await updateTenant('tenant-123', updateData, {
        user_id: 'user-123'
      });

      expect(result.id).toBe('tenant-123');
      expect(tenantRepository.update).toHaveBeenCalledWith(
        'tenant-123',
        expect.not.objectContaining({ confirm_similar: true })
      );
      expect(createAuditLog).toHaveBeenCalledWith(
        expect.objectContaining({
          details: expect.objectContaining({
            confirm_similar: true,
            similar_match_ids: ['tenant-existing']
          })
        })
      );
    });

    it('should throw HttpError if tenant not found before update', async () => {
      tenantRepository.findById.mockResolvedValue(null);

      await expect(updateTenant('tenant-123', { name: 'Updated' }))
        .rejects
        .toThrow(HttpError);
      
      expect(tenantRepository.update).not.toHaveBeenCalled();
    });

    it('should propagate repository errors', async () => {
      const mockTenant = { id: 'tenant-123', name: 'Test' };
      const error = new HttpError('errors.database.unique_field', 409);
      
      tenantRepository.findById.mockResolvedValue(mockTenant);
      tenantRepository.findMany.mockResolvedValue([]);
      tenantRepository.update.mockRejectedValue(error);

      await expect(updateTenant('tenant-123', { name: 'Updated' }))
        .rejects
        .toThrow(HttpError);
    });
  });

  describe('deleteTenant', () => {
    it('should delete tenant successfully and cascade facilities', async () => {
      const mockTenant = {
        id: 'tenant-123',
        name: 'Test Hospital',
        slug: 'test-hospital',
        is_active: true
      };
      const mockFacilities = [
        {
          id: 'facility-1',
          tenant_id: 'tenant-123',
          name: 'Main Facility',
          facility_type: 'HOSPITAL',
          is_active: true}];
      const context = {
        user_id: 'user-123',
        tenant_id: 'tenant-123',
        ip_address: '192.168.1.1'
      };

      tenantRepository.findById.mockResolvedValue(mockTenant);
      tenantRepository.softDelete.mockResolvedValue({
        tenant: { ...mockTenant, deleted_at: new Date() },
        facilities: mockFacilities});
      createAuditLog.mockResolvedValue(undefined);

      await deleteTenant('tenant-123', context);

      expect(tenantRepository.findById).toHaveBeenCalledWith('tenant-123');
      expect(tenantRepository.softDelete).toHaveBeenCalledWith('tenant-123');
      expect(createAuditLog).toHaveBeenCalledWith({
        action: 'TENANT_DELETED',
        entity: 'tenant',
        entity_id: 'tenant-123',
        user_id: context.user_id,
        tenant_id: context.tenant_id,
        facility_id: undefined,
        ip_address: context.ip_address,
        user_agent: undefined,
        details: {
          name: mockTenant.name,
          slug: mockTenant.slug,
          cascaded_facility_ids: ['facility-1']}
      });
      expect(createAuditLog).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'FACILITY_DELETED',
          entity: 'facility',
          entity_id: 'facility-1'}),
      );
      expect(publishPlatformRealtimeEvent).toHaveBeenCalledWith(
        expect.objectContaining({
          event: 'facility.deleted',
          resource_id: 'facility-1'}),
      );
    });

    it('should throw HttpError if tenant not found', async () => {
      tenantRepository.findById.mockResolvedValue(null);
      resolveModelRecordByIdentifier.mockResolvedValue(null);

      await expect(deleteTenant('tenant-123'))
        .rejects
        .toThrow(HttpError);
      
      expect(tenantRepository.softDelete).not.toHaveBeenCalled();
    });

    it('should no-op when tenant is already soft-deleted', async () => {
      tenantRepository.findById.mockResolvedValue(null);
      resolveModelRecordByIdentifier.mockResolvedValue({
        id: 'tenant-123',
        deleted_at: new Date('2026-01-01')});

      await expect(deleteTenant('tenant-123')).resolves.toBeUndefined();

      expect(tenantRepository.softDelete).not.toHaveBeenCalled();
      expect(createAuditLog).not.toHaveBeenCalled();
    });

    it('should propagate repository errors', async () => {
      const mockTenant = { id: 'tenant-123', name: 'Test' };
      const error = new HttpError('errors.database.unexpected', 500);
      
      tenantRepository.findById.mockResolvedValue(mockTenant);
      tenantRepository.softDelete.mockRejectedValue(error);

      await expect(deleteTenant('tenant-123'))
        .rejects
        .toThrow(HttpError);
    });
  });

  describe('restoreTenant', () => {
    it('should restore tenant successfully and cascade facilities', async () => {
      const mockTenant = {
        id: 'tenant-123',
        name: 'Test Hospital',
        slug: 'test-hospital',
        is_active: true,
        deleted_at: null};
      const mockFacilities = [
        {
          id: 'facility-1',
          tenant_id: 'tenant-123',
          name: 'Main Facility',
          facility_type: 'HOSPITAL',
          is_active: true}];
      tenantRepository.restore.mockResolvedValue({
        tenant: mockTenant,
        facilities: mockFacilities});

      const result = await restoreTenant('tenant-123', { user_id: 'user-1' });

      expect(result).toEqual(
        expect.objectContaining({
          id: 'tenant-123',
          resource_uuid: 'tenant-123',
          display_id: 'tenant-123'}),
      );
      expect(tenantRepository.restore).toHaveBeenCalledWith('tenant-123');
      expect(createAuditLog).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'TENANT_RESTORED',
          entity_id: 'tenant-123',
          details: expect.objectContaining({
            cascaded_facility_ids: ['facility-1']})}),
      );
      expect(createAuditLog).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'FACILITY_RESTORED',
          entity_id: 'facility-1'}),
      );
    });
  });

  describe('permanentDeleteTenant', () => {
    it('should permanently delete a soft-deleted tenant', async () => {
      const mockTenant = {
        id: 'tenant-123',
        name: 'Test Hospital',
        slug: 'test-hospital__deleted__tenant123',
        deleted_at: new Date()};
      tenantRepository.findById.mockResolvedValue(mockTenant);
      tenantRepository.permanentDelete.mockResolvedValue({
        facilityIds: ['facility-1']});

      await permanentDeleteTenant('tenant-123', { user_id: 'user-1' });

      expect(createAuditLog).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'TENANT_PERMANENTLY_DELETED',
          entity_id: 'tenant-123',
          details: expect.objectContaining({ irreversible: true })}),
      );
      expect(tenantRepository.permanentDelete).toHaveBeenCalledWith('tenant-123');
      expect(publishPlatformRealtimeEvent).toHaveBeenCalledWith(
        expect.objectContaining({
          event: 'tenant.permanently_deleted',
          payload: expect.objectContaining({
            cascaded_facility_ids: ['facility-1']})}),
      );
    });

    it('should reject permanent delete for active tenant', async () => {
      tenantRepository.findById.mockResolvedValue({
        id: 'tenant-123',
        name: 'Test Hospital',
        deleted_at: null});

      await expect(permanentDeleteTenant('tenant-123'))
        .rejects
        .toThrow(HttpError);
    });

    it('should no-op when tenant is already permanently deleted', async () => {
      tenantRepository.findById.mockResolvedValue(null);

      await expect(permanentDeleteTenant('tenant-123')).resolves.toBeUndefined();

      expect(tenantRepository.permanentDelete).not.toHaveBeenCalled();
    });

    it('should block permanent delete when an active subscription remains', async () => {
      const prisma = require('@prisma/client');
      tenantRepository.findById.mockResolvedValue({
        id: 'tenant-123',
        name: 'Test Hospital',
        deleted_at: new Date()});
      prisma.subscription.count.mockResolvedValue(1);

      await expect(permanentDeleteTenant('tenant-123')).rejects.toMatchObject({
        messageKey: 'errors.tenant.permanent_delete_blocked',
        statusCode: 409,
        errors: [{ reason: 'active_subscription' }],
      });
      expect(tenantRepository.permanentDelete).not.toHaveBeenCalled();
    });

    it('should permanently delete when force overrides an active subscription', async () => {
      const prisma = require('@prisma/client');
      tenantRepository.findById.mockResolvedValue({
        id: 'tenant-123',
        name: 'Test Hospital',
        slug: 'test-hospital__deleted__tenant123',
        deleted_at: new Date()});
      prisma.subscription.count.mockResolvedValue(1);
      tenantRepository.permanentDelete.mockResolvedValue({
        facilityIds: ['facility-1']});

      await permanentDeleteTenant('tenant-123', { user_id: 'user-1' }, { force: true });

      expect(prisma.subscription.count).not.toHaveBeenCalled();
      expect(tenantRepository.permanentDelete).toHaveBeenCalledWith('tenant-123');
      expect(createAuditLog).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'TENANT_PERMANENTLY_DELETED',
          details: expect.objectContaining({ forced: true })}),
      );
    });
  });
});
