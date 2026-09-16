const { runWithRequestContext } = require('@lib/context/request-context-store');
const {
  buildGuardedWhere,
  buildTenantGuardModelMetadata,
  createTenantGuardQueryExtension
} = require('../../prisma/tenant-guard');

const ADDRESS_METADATA = {
  hasId: true,
  hasTenantId: true,
  hasDeletedAt: true
};

const createHandlers = (baseClient) =>
  createTenantGuardQueryExtension({
    baseClient,
    modelMetadata: new Map([['address', ADDRESS_METADATA]])
  }).$allModels;

describe('tenant guard query extension', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('scopes id-based reads to the active tenant', async () => {
    const baseClient = {
      address: {
        findFirst: jest.fn().mockResolvedValue({ id: 'address-123' })
      }
    };
    const handlers = createHandlers(baseClient);
    const query = jest.fn();

    const result = await runWithRequestContext(
      {
        actor: { roles: ['NURSE'] },
        scope: { tenant_id: 'tenant-1' }
      },
      () =>
        handlers.findUnique({
          model: 'address',
          args: { where: { id: 'address-123' } },
          query
        })
    );

    expect(result).toEqual({ id: 'address-123' });
    expect(query).not.toHaveBeenCalled();
    expect(baseClient.address.findFirst).toHaveBeenCalledWith({
      where: buildGuardedWhere({ id: 'address-123' }, ADDRESS_METADATA, 'tenant-1', {
        enforceActiveRecord: true
      })
    });
  });

  it('blocks cross-tenant updates with not-found semantics', async () => {
    const baseClient = {
      address: {
        findFirst: jest.fn().mockResolvedValue(null)
      }
    };
    const handlers = createHandlers(baseClient);
    const query = jest.fn();

    await expect(
      runWithRequestContext(
        {
          actor: { roles: ['NURSE'] },
          scope: { tenant_id: 'tenant-1' }
        },
        () =>
          handlers.update({
            model: 'address',
            args: {
              where: { id: 'address-123' },
              data: { city: 'Kampala' }
            },
            query
          })
      )
    ).rejects.toMatchObject({ code: 'P2025' });

    expect(query).not.toHaveBeenCalled();
  });

  it('uses the interactive transaction client for update preflight reads', async () => {
    const txAddress = {
      findFirst: jest.fn().mockResolvedValue({ id: 'address-123' })
    };
    const baseClient = {
      address: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      _createItxClient: jest.fn().mockReturnValue({
        address: txAddress
      })
    };
    const handlers = createHandlers(baseClient);
    const query = jest.fn(async (args) => args);
    const transaction = { kind: 'itx', id: 'tx-1' };

    const result = await runWithRequestContext(
      {
        actor: { roles: ['NURSE'] },
        scope: { tenant_id: 'tenant-1' }
      },
      () =>
        handlers.update({
          model: 'address',
          args: {
            where: { id: 'address-123' },
            data: { city: 'Kampala' }
          },
          query,
          __internalParams: { transaction }
        })
    );

    expect(baseClient._createItxClient).toHaveBeenCalledWith(transaction);
    expect(txAddress.findFirst).toHaveBeenCalled();
    expect(baseClient.address.findFirst).not.toHaveBeenCalled();
    expect(query).toHaveBeenCalled();
    expect(result).toEqual({
      where: { id: 'address-123' },
      data: { city: 'Kampala' }
    });
  });

  it('blocks cross-tenant deletes with not-found semantics', async () => {
    const baseClient = {
      address: {
        findFirst: jest.fn().mockResolvedValue(null)
      }
    };
    const handlers = createHandlers(baseClient);
    const query = jest.fn();

    await expect(
      runWithRequestContext(
        {
          actor: { roles: ['NURSE'] },
          scope: { tenant_id: 'tenant-1' }
        },
        () =>
          handlers.delete({
            model: 'address',
            args: { where: { id: 'address-123' } },
            query
          })
      )
    ).rejects.toMatchObject({ code: 'P2025' });

    expect(query).not.toHaveBeenCalled();
  });

  it('injects tenant_id into create operations', async () => {
    const baseClient = {
      address: {
        findFirst: jest.fn()
      }
    };
    const handlers = createHandlers(baseClient);
    const query = jest.fn(async (args) => args.data);

    const result = await runWithRequestContext(
      {
        actor: { roles: ['NURSE'] },
        scope: { tenant_id: 'tenant-1' }
      },
      () =>
        handlers.create({
          model: 'address',
          args: {
            data: {
              line1: 'Plot 1'
            }
          },
          query
        })
    );

    expect(query).toHaveBeenCalledWith({
      data: {
        tenant_id: 'tenant-1',
        line1: 'Plot 1'
      }
    });
    expect(result).toEqual({
      tenant_id: 'tenant-1',
      line1: 'Plot 1'
    });
  });

  it('bypasses tenant guard for elevated roles', async () => {
    const baseClient = {
      address: {
        findFirst: jest.fn()
      }
    };
    const handlers = createHandlers(baseClient);
    const query = jest.fn(async (args) => args);

    const result = await runWithRequestContext(
      {
        actor: { roles: ['PLATFORM_ADMIN'] },
        scope: { tenant_id: 'tenant-1' }
      },
      () =>
        handlers.findMany({
          model: 'address',
          args: { where: { city: 'Kampala' } },
          query
        })
    );

    expect(baseClient.address.findFirst).not.toHaveBeenCalled();
    expect(query).toHaveBeenCalledWith({
      where: { city: 'Kampala' }
    });
    expect(result).toEqual({
      where: { city: 'Kampala' }
    });
  });

  it('keeps bypassTenantGuard active for sync callbacks that return promises', async () => {
    const {
      getGuardContext,
      runWithoutTenantGuard,
    } = require('../../prisma/tenant-guard');

    // Simulate Prisma query extensions that resume after the sync callback
    // returns a Promise — the previous ALS wiring dropped bypass there.
    const deferredGuardRead = () =>
      new Promise((resolve) => {
        setImmediate(() => {
          resolve(getGuardContext());
        });
      });

    const withoutFixShape = await runWithRequestContext(
      {
        actor: { roles: ['TENANT_ADMIN'] },
        scope: { tenant_id: 'tenant-1' }
      },
      async () => {
        const context = await runWithoutTenantGuard(() => deferredGuardRead());
        return context;
      }
    );

    expect(withoutFixShape.bypass).toBe(true);
    expect(withoutFixShape.context?.bypassTenantGuard).toBe(true);
  });
});

describe('buildTenantGuardModelMetadata', () => {
  it('does not treat required deleted_at as a soft-delete flag', () => {
    const metadata = buildTenantGuardModelMetadata({
      dmmf: {
        datamodel: {
          models: [
            {
              name: 'patient',
              fields: [
                { name: 'id' },
                { name: 'tenant_id' },
                { name: 'deleted_at', isRequired: false },
                { name: 'human_friendly_id' }
              ]
            },
            {
              name: 'patient_deletion_batch',
              fields: [
                { name: 'id' },
                { name: 'tenant_id' },
                { name: 'deleted_at', isRequired: true },
                { name: 'batch_deleted_at', isRequired: false },
                { name: 'human_friendly_id' }
              ]
            },
            {
              name: 'patient_deletion_batch_item',
              fields: [
                { name: 'id' },
                { name: 'batch_id' },
                { name: 'entity_model' },
                { name: 'entity_id' }
              ]
            }
          ]
        }
      }
    });

    expect(metadata.get('patient')).toMatchObject({
      hasDeletedAt: true,
      hasHumanFriendlyId: true,
      hasTenantId: true
    });
    expect(metadata.get('patient_deletion_batch')).toMatchObject({
      hasDeletedAt: false,
      hasHumanFriendlyId: true,
      hasTenantId: true
    });
    expect(metadata.get('patient_deletion_batch_item')).toMatchObject({
      hasDeletedAt: false,
      hasHumanFriendlyId: false,
      hasTenantId: false
    });
  });
});

