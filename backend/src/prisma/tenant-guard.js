const loadRolesConfig = () => {
  try {
    return require('@config/roles');
  } catch (error) {
    const isMissingAlias =
      error?.code === 'MODULE_NOT_FOUND' &&
      typeof error?.message === 'string' &&
      error.message.includes("'@config/roles'");

    if (!isMissingAlias) {
      throw error;
    }

    return require('../config/roles');
  }
};

const loadRequestContextStore = () => {
  try {
    return require('@lib/context/request-context-store');
  } catch (error) {
    const isMissingAlias =
      error?.code === 'MODULE_NOT_FOUND' &&
      typeof error?.message === 'string' &&
      error.message.includes("'@lib/context/request-context-store'");

    if (!isMissingAlias) {
      throw error;
    }

    return require('../lib/context/request-context-store');
  }
};

const { ELEVATED_ROLES, normalizeRoleName } = loadRolesConfig();
const { getRequestContext } = loadRequestContextStore();

const ELEVATED_ROLE_SET = new Set(ELEVATED_ROLES);
const LOGICAL_KEYS = ['AND', 'OR', 'NOT'];

const buildTenantGuardModelMetadata = (Prisma) => {
  const metadata = new Map();
  const models = Prisma?.dmmf?.datamodel?.models || [];

  for (const model of models) {
    const fields = model.fields || [];
    const fieldNames = new Set(fields.map((field) => field.name));
    const deletedAtField = fields.find((field) => field.name === 'deleted_at');
    // Required `deleted_at` is a real timestamp (e.g. cascade time on
    // patient_deletion_batch). Soft-delete filtering only applies when the
    // column is optional, and never when `batch_deleted_at` is the live flag.
    const isSoftDeleteDeletedAt =
      Boolean(deletedAtField) &&
      deletedAtField.isRequired !== true &&
      !fieldNames.has('batch_deleted_at');
    metadata.set(model.name, {
      hasId: fieldNames.has('id'),
      hasTenantId: fieldNames.has('tenant_id'),
      hasDeletedAt: isSoftDeleteDeletedAt,
      hasHumanFriendlyId: fieldNames.has('human_friendly_id')
    });
  }

  return metadata;
};

const normalizeRoles = (roles = []) =>
  (Array.isArray(roles) ? roles : [roles])
    .map((role) => normalizeRoleName(role) || String(role || '').trim().toUpperCase())
    .filter(Boolean);

const hasElevatedRole = (roles = []) =>
  normalizeRoles(roles).some((role) => ELEVATED_ROLE_SET.has(role));

const getGuardContext = () => {
  const context = getRequestContext();
  const tenantId = context?.scope?.tenant_id ? String(context.scope.tenant_id) : null;
  const actorRoles = context?.actor?.roles || [];
  const bypass =
    Boolean(context?.bypassTenantGuard) ||
    !tenantId ||
    hasElevatedRole(actorRoles);

  return {
    context,
    tenantId,
    bypass
  };
};

/**
 * Run a callback with tenant-guard bypass so platform-scoped catalog rows
 * (tenant_id null) remain readable for tenant actors.
 *
 * Important: the ALS callback must be `async` and `await` the inner work.
 * Prisma query extensions often resume after a sync `() => prisma.*()` callback
 * returns a Promise, which drops `bypassTenantGuard` and re-applies tenant
 * scoping (hiding global catalog rows such as subscription plans).
 *
 * @template T
 * @param {() => T | Promise<T>} callback
 * @returns {Promise<T>}
 */
const runWithoutTenantGuard = (callback) => {
  const { runWithRequestContext } = loadRequestContextStore();
  const parent = getRequestContext() || {};
  return runWithRequestContext(
    {
      ...parent,
      bypassTenantGuard: true,
    },
    async () => callback()
  );
};

const mentionsField = (where, fieldName) => {
  if (!where || typeof where !== 'object') {
    return false;
  }

  if (Object.prototype.hasOwnProperty.call(where, fieldName)) {
    return true;
  }

  return LOGICAL_KEYS.some((key) => {
    const value = where[key];
    if (Array.isArray(value)) {
      return value.some((entry) => mentionsField(entry, fieldName));
    }
    return mentionsField(value, fieldName);
  });
};

const appendConstraint = (where, constraint) => {
  if (!where || typeof where !== 'object' || Object.keys(where).length === 0) {
    return { ...constraint };
  }

  return {
    AND: [where, constraint]
  };
};

const PLATFORM_SHARED_MODELS = new Set(['role', 'permission']);

const buildGuardedWhere = (where, metadata, tenantId, options = {}) => {
  const tenantConstraint = options.includePlatformCatalog
    ? {
        OR: [{ tenant_id: tenantId }, { tenant_id: null }],
      }
    : { tenant_id: tenantId };

  let guardedWhere = appendConstraint(where, tenantConstraint);

  if (
    options.enforceActiveRecord &&
    metadata?.hasDeletedAt &&
    !mentionsField(guardedWhere, 'deleted_at')
  ) {
    guardedWhere = appendConstraint(guardedWhere, { deleted_at: null });
  }

  return guardedWhere;
};

const injectTenantId = (data, tenantId) => {
  if (!data || typeof data !== 'object') {
    return;
  }

  if (Array.isArray(data)) {
    data.forEach((entry) => injectTenantId(entry, tenantId));
    return;
  }

  data.tenant_id = tenantId;
  if (Object.prototype.hasOwnProperty.call(data, 'tenantId')) {
    data.tenantId = tenantId;
  }
};

const createNotFoundError = () => {
  const error = new Error('Record not found for tenant scope');
  error.code = 'P2025';
  return error;
};

const findFirstOrThrow = async (delegate, args) => {
  if (typeof delegate.findFirstOrThrow === 'function') {
    return delegate.findFirstOrThrow(args);
  }

  const record = await delegate.findFirst(args);
  if (!record) {
    throw createNotFoundError();
  }
  return record;
};

const resolveScopedDelegate = ({ baseClient, model, rest }) => {
  const transaction = rest?.__internalParams?.transaction;
  if (
    transaction?.kind === 'itx' &&
    typeof baseClient?._createItxClient === 'function'
  ) {
    try {
      const txClient = baseClient._createItxClient(transaction);
      if (txClient?.[model]) {
        return txClient[model];
      }
    } catch (_) {
      // Fall through to the base delegate when Prisma internals change.
    }
  }

  return baseClient?.[model] || null;
};

const createTenantGuardQueryExtension = ({ baseClient, modelMetadata }) => {
  const guardByQuery = (handler) =>
    async ({ model, args = {}, query, ...rest }) => {
      const metadata = modelMetadata.get(model);
      if (!metadata?.hasTenantId) {
        return query(args);
      }

      const { tenantId, bypass } = getGuardContext();
      if (bypass) {
        return query(args);
      }

      const delegate = resolveScopedDelegate({ baseClient, model, rest });
      if (!delegate) {
        return query(args);
      }

      return handler({
        args,
        query,
        delegate,
        metadata,
        tenantId,
        model,
        includePlatformCatalog: PLATFORM_SHARED_MODELS.has(model),
      });
    };

  return {
    $allModels: {
      findUnique: guardByQuery(async ({ args, delegate, metadata, tenantId, includePlatformCatalog }) =>
        delegate.findFirst({
          ...args,
          where: buildGuardedWhere(args.where, metadata, tenantId, {
            enforceActiveRecord: true,
            includePlatformCatalog,
          })
        })
      ),
      findUniqueOrThrow: guardByQuery(async ({ args, delegate, metadata, tenantId, includePlatformCatalog }) =>
        findFirstOrThrow(delegate, {
          ...args,
          where: buildGuardedWhere(args.where, metadata, tenantId, {
            enforceActiveRecord: true,
            includePlatformCatalog,
          })
        })
      ),
      findFirst: guardByQuery(async ({ args, query, metadata, tenantId, includePlatformCatalog }) =>
        query({
          ...args,
          where: buildGuardedWhere(args.where, metadata, tenantId, {
            enforceActiveRecord: true,
            includePlatformCatalog,
          })
        })
      ),
      findFirstOrThrow: guardByQuery(async ({ args, query, metadata, tenantId, includePlatformCatalog }) =>
        query({
          ...args,
          where: buildGuardedWhere(args.where, metadata, tenantId, {
            enforceActiveRecord: true,
            includePlatformCatalog,
          })
        })
      ),
      findMany: guardByQuery(async ({ args, query, metadata, tenantId, includePlatformCatalog }) =>
        query({
          ...args,
          where: buildGuardedWhere(args.where, metadata, tenantId, {
            includePlatformCatalog,
          })
        })
      ),
      count: guardByQuery(async ({ args, query, metadata, tenantId, includePlatformCatalog }) =>
        query({
          ...args,
          where: buildGuardedWhere(args.where, metadata, tenantId, {
            includePlatformCatalog,
          })
        })
      ),
      aggregate: guardByQuery(async ({ args, query, metadata, tenantId, includePlatformCatalog }) =>
        query({
          ...args,
          where: buildGuardedWhere(args.where, metadata, tenantId, {
            includePlatformCatalog,
          })
        })
      ),
      create: guardByQuery(async ({ args, query, tenantId, model }) => {
        const data = args.data;
        const preservePlatformNull =
          PLATFORM_SHARED_MODELS.has(model) &&
          data &&
          !Array.isArray(data) &&
          Object.prototype.hasOwnProperty.call(data, 'tenant_id') &&
          data.tenant_id == null;
        if (!preservePlatformNull) {
          injectTenantId(args.data, tenantId);
        }
        return query(args);
      }),
      createMany: guardByQuery(async ({ args, query, tenantId, model }) => {
        const rows = Array.isArray(args.data) ? args.data : [args.data];
        const preservePlatformNull =
          PLATFORM_SHARED_MODELS.has(model) &&
          rows.every(
            (row) =>
              row &&
              Object.prototype.hasOwnProperty.call(row, 'tenant_id') &&
              row.tenant_id == null
          );
        if (!preservePlatformNull) {
          injectTenantId(args.data, tenantId);
        }
        return query(args);
      }),
      updateMany: guardByQuery(async ({ args, query, metadata, tenantId, includePlatformCatalog }) =>
        query({
          ...args,
          where: buildGuardedWhere(args.where, metadata, tenantId, {
            enforceActiveRecord: true,
            includePlatformCatalog,
          })
        })
      ),
      deleteMany: guardByQuery(async ({ args, query, metadata, tenantId, includePlatformCatalog }) =>
        query({
          ...args,
          where: buildGuardedWhere(args.where, metadata, tenantId, {
            enforceActiveRecord: true,
            includePlatformCatalog,
          })
        })
      ),
      update: guardByQuery(async ({ args, query, delegate, metadata, tenantId, includePlatformCatalog }) => {
        const existing = await delegate.findFirst({
          where: buildGuardedWhere(args.where, metadata, tenantId, {
            enforceActiveRecord: true,
            includePlatformCatalog,
          }),
          select: { id: true }
        });

        if (!existing) {
          throw createNotFoundError();
        }

        return query(args);
      }),
      delete: guardByQuery(async ({ args, query, delegate, metadata, tenantId, includePlatformCatalog }) => {
        const existing = await delegate.findFirst({
          where: buildGuardedWhere(args.where, metadata, tenantId, {
            enforceActiveRecord: true,
            includePlatformCatalog,
          }),
          select: { id: true }
        });

        if (!existing) {
          throw createNotFoundError();
        }

        return query(args);
      })
    }
  };
};

const withTenantGuard = (prismaClient, options = {}) =>
  prismaClient.$extends({
    query: createTenantGuardQueryExtension(options)
  });

module.exports = {
  buildTenantGuardModelMetadata,
  buildGuardedWhere,
  createTenantGuardQueryExtension,
  getGuardContext,
  withTenantGuard,
  runWithoutTenantGuard,
  injectTenantId,
  hasElevatedRole,
  mentionsField
};
