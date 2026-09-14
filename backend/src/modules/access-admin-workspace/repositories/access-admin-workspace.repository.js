const prisma = require('@prisma/client');
const { HttpError } = require('@lib/errors');
const { resolveIdentifierForFilter } = require('@lib/billing/identifiers');
const { ROLES } = require('@config/roles');
const { buildRoleScopeWhere } = require('@lib/authorization/assignable-access');
const { DEMO_USER_EMAILS, isDemoUser } = require('@config/demo-users');
const { notPurgedWhere } = require('@lib/user/purged-account');
const tenantFacilityRepository = require('@repositories/tenant-facility-workspace/tenant-facility-workspace.repository');

const DEMO_EMAIL_SUFFIX = '@hosspi.com';

const mapError = (error) => {
  if (error instanceof HttpError) throw error;
  throw new HttpError('errors.database.unexpected', 500, [{ originalError: error?.message }]);
};

const scopedWhere = (scope = {}, options = {}) => {
  const {
    includeFacility = false,
    includeDeleted = false,
    includePlatformCatalog = false,
  } = options;
  const where = {};
  if (!includeDeleted) {
    where.deleted_at = null;
  }

  if (includePlatformCatalog && scope.tenant_id) {
    where.OR = [{ tenant_id: null }, { tenant_id: scope.tenant_id }];
  } else if (includePlatformCatalog && !scope.tenant_id) {
    where.tenant_id = null;
  } else if (scope.tenant_id) {
    where.tenant_id = scope.tenant_id;
  }

  if (includeFacility && scope.facility_id) {
    where.facility_id = scope.facility_id;
  }

  return where;
};

const scopedRoleWhere = (scope = {}, options = {}) =>
  buildRoleScopeWhere(scope, options);

const buildSearchFilter = (search = '') => {
  const term = String(search || '').trim();
  if (!term) return null;
  // MySQL/MariaDB Prisma provider does not support `mode: 'insensitive'`.
  // Demo data uses lowercase emails and the default collation is case-insensitive.
  return {
    OR: [
      { email: { contains: term } },
      { position_title: { contains: term } },
      { human_friendly_id: { contains: term } },
      { name: { contains: term } },
      { description: { contains: term } },
    ],
  };
};

const buildRoleSearchFilter = (search = '') => {
  const term = String(search || '').trim();
  if (!term) return null;
  return {
    OR: [
      { human_friendly_id: { contains: term } },
      { name: { contains: term } },
      { display_name: { contains: term } },
      { description: { contains: term } },
    ],
  };
};

const countUsers = async (scope = {}, filters = {}) => {
  try {
    const where = {
      ...scopedWhere(scope, { includeFacility: true }),
      ...(filters.status ? { status: filters.status } : {}),
    };
    const searchFilter = buildSearchFilter(filters.search);
    if (searchFilter) {
      where.OR = searchFilter.OR.filter((entry) => !entry.name && !entry.description);
    }
    return prisma.user.count({ where });
  } catch (error) {
    mapError(error);
  }
};

const countRoles = async (scope = {}, filters = {}, roleOptions = {}) => {
  try {
    const includeDeleted =
      filters.include_deleted === true || filters.include_deleted === 'true';
    const where = {
      ...scopedRoleWhere(scope, {
        includeTenantWide: roleOptions.includeTenantWide !== false,
        roleScope: roleOptions.roleScope || null,
        includeDeleted,
      }),
    };
    const searchFilter = buildRoleSearchFilter(filters.search);
    if (searchFilter) {
      const searchOr = searchFilter.OR;
      if (where.OR) {
        where.AND = [{ OR: where.OR }, { OR: searchOr }];
        delete where.OR;
      } else {
        where.OR = searchOr;
      }
    }
    return prisma.role.count({ where });
  } catch (error) {
    mapError(error);
  }
};

const countPermissions = async (scope = {}, filters = {}) => {
  try {
    const where = scopedWhere(scope);
    const searchFilter = buildSearchFilter(filters.search);
    if (searchFilter) {
      where.OR = searchFilter.OR.filter(
        (entry) => !entry.email && !entry.position_title && !entry.description?.contains
      );
    }
    return prisma.permission.count({ where });
  } catch (error) {
    mapError(error);
  }
};

const countUserRoles = async (scope = {}) => {
  try {
    return prisma.user_role.count({
      where: scopedWhere(scope, { includeFacility: true }),
    });
  } catch (error) {
    mapError(error);
  }
};

const countDemoUsers = async (scope = {}) => {
  try {
    return prisma.user.count({
      where: {
        ...scopedWhere(scope, { includeFacility: true }),
        email: { in: [...DEMO_USER_EMAILS] },
      },
    });
  } catch (error) {
    mapError(error);
  }
};

const findSummary = async (scope = {}) => {
  try {
    const [
      totalUsers,
      activeUsers,
      inactiveUsers,
      totalRoles,
      totalPermissions,
      totalAssignments,
      demoUsers,
    ] = await Promise.all([
      countUsers(scope),
      prisma.user.count({
        where: { ...scopedWhere(scope, { includeFacility: true }), status: 'ACTIVE' },
      }),
      prisma.user.count({
        where: {
          ...scopedWhere(scope, { includeFacility: true }),
          status: { in: ['INACTIVE', 'SUSPENDED'] },
        },
      }),
      countRoles(scope),
      countPermissions(scope),
      countUserRoles(scope),
      countDemoUsers(scope),
    ]);

    return {
      total_users: totalUsers,
      active_users: activeUsers,
      inactive_users: inactiveUsers,
      total_roles: totalRoles,
      total_permissions: totalPermissions,
      total_assignments: totalAssignments,
      demo_users: demoUsers,
    };
  } catch (error) {
    mapError(error);
  }
};

const findUsers = async ({ scope = {}, filters = {}, skip = 0, take = 20, orderBy = { updated_at: 'desc' } }) => {
  try {
    const includeDeleted =
      filters.include_deleted === true || filters.include_deleted === 'true';
    const where = {
      ...scopedWhere(scope, { includeFacility: true, includeDeleted }),
      ...(filters.status ? { status: filters.status } : {}),
      ...(filters.is_demo
        ? { email: { in: [...DEMO_USER_EMAILS] } }
        : {}),
    };

    if (includeDeleted) {
      // Purged accounts stay only as the authors of old records; they never list.
      where.AND = [...(Array.isArray(where.AND) ? where.AND : []), notPurgedWhere()];
    }

    if (filters.role_id) {
      const roleId = await resolveIdentifierForFilter({
        value: filters.role_id,
        model: 'role',
      });
      if (roleId) {
        where.roles = {
          some: {
            deleted_at: null,
            role_id: roleId,
          },
        };
      }
    }

    const searchTerm = String(filters.search || '').trim();
    if (searchTerm) {
      const searchFilter = buildSearchFilter(searchTerm);
      const userFieldOr = (searchFilter?.OR || []).filter(
        (entry) => !entry.name && !entry.description
      );
      where.AND = [
        ...(Array.isArray(where.AND) ? where.AND : []),
        {
          OR: [
            ...userFieldOr,
            {
              profile: {
                is: {
                  deleted_at: null,
                  OR: [
                    { first_name: { contains: searchTerm } },
                    { last_name: { contains: searchTerm } },
                  ],
                },
              },
            },
            {
              roles: {
                some: {
                  deleted_at: null,
                  role: {
                    name: { contains: searchTerm },
                  },
                },
              },
            },
          ],
        },
      ];
    }

    const resolvedOrderBy = includeDeleted
      ? [{ deleted_at: 'asc' }, orderBy]
      : orderBy;

    const [items, total] = await Promise.all([
      prisma.user.findMany({
        where,
        skip,
        take,
        orderBy: resolvedOrderBy,
        include: {
          profile: {
            where: { deleted_at: null },
            select: {
              id: true,
              human_friendly_id: true,
              first_name: true,
              last_name: true,
            },
          },
          roles: {
            where: { deleted_at: null },
            include: {
              role: {
                select: {
                  id: true,
                  human_friendly_id: true,
                  name: true,
                },
              },
            },
          },
          staff_profile: {
            where: { deleted_at: null },
            select: {
              id: true,
              human_friendly_id: true,
            },
          },
          facility: {
            select: {
              id: true,
              human_friendly_id: true,
              name: true,
            },
          },
          tenant: {
            select: {
              id: true,
              human_friendly_id: true,
              name: true,
            },
          },
        },
      }),
      prisma.user.count({ where }),
    ]);

    return { items, total };
  } catch (error) {
    mapError(error);
  }
};

const findRoles = async ({
  scope = {},
  filters = {},
  skip = 0,
  take = 20,
  orderBy = { name: 'asc' },
  includeTenantWide = true,
  roleScope = null,
  includeDeleted = false,
}) => {
  try {
    const where = scopedRoleWhere(scope, {
      includeTenantWide,
      roleScope,
      includeDeleted,
    });
    const searchFilter = buildRoleSearchFilter(filters.search);
    if (searchFilter) {
      const searchOr = searchFilter.OR;
      if (where.OR) {
        where.AND = [{ OR: where.OR }, { OR: searchOr }];
        delete where.OR;
      } else {
        where.OR = searchOr;
      }
    }

    const resolvedOrderBy = includeDeleted
      ? [{ deleted_at: 'asc' }, orderBy]
      : orderBy;

    const [items, total] = await Promise.all([
      prisma.role.findMany({
        where,
        skip,
        take,
        orderBy: resolvedOrderBy,
        include: {
          _count: {
            select: {
              users: { where: { deleted_at: null } },
              permissions: { where: { deleted_at: null } },
            },
          },
        },
      }),
      prisma.role.count({ where }),
    ]);

    const facilityIds = [
      ...new Set(
        items
          .map((entry) => entry.facility_id)
          .filter((value) => value != null && String(value).trim() !== '')
      ),
    ];
    const tenantIds = [
      ...new Set(
        items
          .map((entry) => entry.tenant_id)
          .filter((value) => value != null && String(value).trim() !== '')
      ),
    ];
    let facilityNameById = new Map();
    if (facilityIds.length > 0) {
      const facilities = await prisma.facility.findMany({
        where: { id: { in: facilityIds }, deleted_at: null },
        select: { id: true, name: true, human_friendly_id: true },
      });
      facilityNameById = new Map(
        facilities.map((facility) => [facility.id, facility.name])
      );
    }
    let tenantNameById = new Map();
    if (tenantIds.length > 0) {
      const tenants = await prisma.tenant.findMany({
        where: { id: { in: tenantIds }, deleted_at: null },
        select: { id: true, name: true },
      });
      tenantNameById = new Map(
        tenants.map((tenant) => [tenant.id, tenant.name])
      );
    }

    const enriched = items.map((entry) => ({
      ...entry,
      facility_name: entry.facility_id
        ? facilityNameById.get(entry.facility_id) || null
        : null,
      tenant_name: entry.tenant_id
        ? tenantNameById.get(entry.tenant_id) || null
        : null,
    }));

    return { items: enriched, total };
  } catch (error) {
    mapError(error);
  }
};

const findPermissions = async ({ scope = {}, filters = {}, skip = 0, take = 20, orderBy = { name: 'asc' } }) => {
  try {
    const where = scopedWhere(scope, { includePlatformCatalog: true });
    const searchFilter = buildSearchFilter(filters.search);
    if (searchFilter) {
      const searchOr = searchFilter.OR.filter(
        (entry) => !entry.email && !entry.position_title
      );
      if (where.OR) {
        where.AND = [{ OR: where.OR }, { OR: searchOr }];
        delete where.OR;
      } else {
        where.OR = searchOr;
      }
    }

    const [items, total] = await Promise.all([
      prisma.permission.findMany({
        where,
        skip,
        take,
        orderBy,
        include: {
          _count: {
            select: {
              roles: { where: { deleted_at: null } },
              users: { where: { deleted_at: null } },
            },
          },
        },
      }),
      prisma.permission.count({ where }),
    ]);

    const tenantIds = [
      ...new Set(
        items
          .map((entry) => entry.tenant_id)
          .filter((value) => value != null && String(value).trim() !== '')
      ),
    ];
    let tenantNameById = new Map();
    if (tenantIds.length > 0) {
      const tenants = await prisma.tenant.findMany({
        where: { id: { in: tenantIds }, deleted_at: null },
        select: { id: true, name: true },
      });
      tenantNameById = new Map(
        tenants.map((tenant) => [tenant.id, tenant.name])
      );
    }

    const enriched = items.map((entry) => ({
      ...entry,
      tenant_name: entry.tenant_id
        ? tenantNameById.get(entry.tenant_id) || null
        : null,
    }));

    return { items: enriched, total };
  } catch (error) {
    mapError(error);
  }
};

const findUserRoles = async ({ scope = {}, filters = {}, skip = 0, take = 20, orderBy = { updated_at: 'desc' } }) => {
  try {
    const where = scopedWhere(scope, { includeFacility: true });
    if (filters.user_id) where.user_id = filters.user_id;
    if (filters.role_id) where.role_id = filters.role_id;

    const [items, total] = await Promise.all([
      prisma.user_role.findMany({
        where,
        skip,
        take,
        orderBy,
        include: {
          user: {
            select: {
              id: true,
              human_friendly_id: true,
              email: true,
              position_title: true,
            },
          },
          role: {
            select: {
              id: true,
              human_friendly_id: true,
              name: true,
            },
          },
        },
      }),
      prisma.user_role.count({ where }),
    ]);

    return { items, total };
  } catch (error) {
    mapError(error);
  }
};

const findRolePermissions = async ({ scope = {}, filters = {}, skip = 0, take = 20, orderBy = { updated_at: 'desc' } }) => {
  try {
    const where = { deleted_at: null };
    if (filters.role_id) where.role_id = filters.role_id;
    if (filters.permission_id) where.permission_id = filters.permission_id;

    const roleWhere = scopedWhere(scope, { includeFacility: true });

    const [items, total] = await Promise.all([
      prisma.role_permission.findMany({
        where: {
          ...where,
          role: roleWhere,
        },
        skip,
        take,
        orderBy,
        include: {
          role: {
            select: {
              id: true,
              human_friendly_id: true,
              name: true,
              tenant_id: true,
              facility_id: true,
            },
          },
          permission: {
            select: {
              id: true,
              human_friendly_id: true,
              name: true,
              tenant_id: true,
            },
          },
        },
      }),
      prisma.role_permission.count({
        where: {
          ...where,
          role: roleWhere,
        },
      }),
    ]);

    return { items, total };
  } catch (error) {
    mapError(error);
  }
};

const findModuleEntitlements = async (scope = {}) => {
  try {
    if (!scope.tenant_id) return { items: [], total: 0 };

    const subscription = await prisma.subscription.findFirst({
      where: {
        tenant_id: scope.tenant_id,
        deleted_at: null,
        status: { in: ['ACTIVE', 'TRIAL', 'PAST_DUE'] },
      },
      orderBy: { updated_at: 'desc' },
      include: {
        plan: {
          select: {
            id: true,
            human_friendly_id: true,
            name: true,
            tier_code: true,
          },
        },
        module_subscriptions: {
          where: { deleted_at: null },
          include: {
            module: {
              select: {
                id: true,
                human_friendly_id: true,
                name: true,
                slug: true,
                module_group: true,
              },
            },
          },
          orderBy: [{ is_active: 'desc' }, { updated_at: 'desc' }],
        },
      },
    });

    if (!subscription) {
      return { items: [], total: 0, subscription: null };
    }

    const items = subscription.module_subscriptions || [];
    return { items, total: items.length, subscription };
  } catch (error) {
    mapError(error);
  }
};

const findUserByIdentifier = async (identifier, scope = {}) => {
  try {
    const userId = await resolveIdentifierForFilter({
      value: identifier,
      model: 'user',
      where: scopedWhere(scope, { includeFacility: true }),
    });
    if (!userId) return null;

    return prisma.user.findFirst({
      where: { id: userId, deleted_at: null },
      include: {
        profile: {
          where: { deleted_at: null },
          select: {
            id: true,
            human_friendly_id: true,
            first_name: true,
            last_name: true,
          },
        },
        facility: {
          select: {
            id: true,
            human_friendly_id: true,
            name: true,
          },
        },
        tenant: {
          select: {
            id: true,
            human_friendly_id: true,
            name: true,
          },
        },
        roles: {
          where: { deleted_at: null },
          select: {
            id: true,
            human_friendly_id: true,
            role: {
              select: {
                id: true,
                human_friendly_id: true,
                name: true,
                permissions: {
                  where: { deleted_at: null },
                  select: {
                    permission: {
                      select: {
                        id: true,
                        human_friendly_id: true,
                        name: true,
                      },
                    },
                  },
                },
              },
            },
          },
        },
        permissions: {
          where: { deleted_at: null },
          select: {
            permission: {
              select: {
                id: true,
                human_friendly_id: true,
                name: true,
              },
            },
          },
        },
        staff_profile: {
          where: { deleted_at: null },
          select: {
            id: true,
            human_friendly_id: true,
          },
        },
      },
    });
  } catch (error) {
    mapError(error);
  }
};

const findRegistrationFollowUpUserId = async (identifier) => {
  try {
    const followUpId = await resolveIdentifierForFilter({
      value: identifier,
      model: 'registration_follow_up',
    });
    if (!followUpId) {
      return null;
    }

    const followUp = await prisma.registration_follow_up.findFirst({
      where: { id: followUpId, deleted_at: null },
      select: { user_id: true },
    });
    return followUp?.user_id || null;
  } catch (error) {
    mapError(error);
  }
};

const findLookups = async (
  scope = {},
  includeAllTenants = false,
  options = {}
) => {
  try {
    const {
      includeTenants = true,
      includeFacilities = true,
      includeRoles = true,
      includePermissions = true,
      includeRolePermissions = true,
      includeTenantWide = true,
      roleScope = null,
    } = options;

    const [tenants, facilities, roles, permissions] = await Promise.all([
      includeTenants
        ? tenantFacilityRepository.findTenants(scope, includeAllTenants)
        : Promise.resolve([]),
      includeFacilities
        ? tenantFacilityRepository.findFacilities(scope?.tenant_id)
        : Promise.resolve([]),
      includeRoles
        ? prisma.role.findMany({
            where: scopedRoleWhere(scope, { includeTenantWide, roleScope }),
            orderBy: { name: 'asc' },
            take: 200,
            select: {
              id: true,
              human_friendly_id: true,
              name: true,
              display_name: true,
              facility_id: true,
              _count: {
                select: {
                  permissions: { where: { deleted_at: null } },
                },
              },
              ...(includeRolePermissions
                ? {
                    permissions: {
                      where: { deleted_at: null },
                      select: {
                        permission: {
                          select: { name: true },
                        },
                      },
                    },
                  }
                : {}),
            },
          })
        : Promise.resolve([]),
      includePermissions
        ? prisma.permission.findMany({
            where: scopedWhere(scope),
            orderBy: { name: 'asc' },
            take: 500,
            select: {
              id: true,
              human_friendly_id: true,
              name: true,
              display_name: true,
              description: true,
            },
          })
        : Promise.resolve([]),
    ]);

    return { tenants, facilities, roles, permissions };
  } catch (error) {
    mapError(error);
  }
};

const updateUserStatus = async (userId, status) => {
  try {
    const existing = await prisma.user.findFirst({
      where: { id: userId },
      select: { id: true, email: true },
    });
    if (isDemoUser(existing)) {
      throw new HttpError('errors.user.demo_protected', 403, [
        { field: 'user_id', reason: 'demo_user_protected', operation: 'status' },
      ]);
    }
    return prisma.user.update({
      where: { id: userId },
      data: { status },
    });
  } catch (error) {
    mapError(error);
  }
};

const resetDemoUserPassword = async (userId, passwordHash) => {
  try {
    return prisma.user.update({
      where: { id: userId },
      data: { password_hash: passwordHash },
    });
  } catch (error) {
    mapError(error);
  }
};

module.exports = {
  DEMO_EMAIL_SUFFIX,
  DEMO_USER_EMAILS,
  countDemoUsers,
  countPermissions,
  countRoles,
  countUserRoles,
  countUsers,
  findLookups,
  findModuleEntitlements,
  findPermissions,
  findRolePermissions,
  findRoles,
  findSummary,
  findUserByIdentifier,
  findRegistrationFollowUpUserId,
  findUserRoles,
  findUsers,
  isDemoUser,
  resetDemoUserPassword,
  resolveWorkspaceScope: tenantFacilityRepository.resolveWorkspaceScope,
  ROLES,
  updateUserStatus,
};
