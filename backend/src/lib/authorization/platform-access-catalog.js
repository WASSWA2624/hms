/**
 * Platform-scoped access catalog (roles + permissions with tenant_id null).
 *
 * Default/system roles and permissions live once at platform scope. Tenant actors
 * can read them; only platform admins may mutate them. Organizations use these
 * roles as they are, or extend them as custom roles under their own name — never
 * as a same-name tenant copy.
 *
 * @module lib/authorization/platform-access-catalog
 */

const crypto = require('crypto');
const prisma = require('@prisma/client');
const { PERMISSIONS, ROLE_PERMISSIONS } = require('@config/permissions');
const {
  getPermissionMetadata,
  getRoleMetadata,
} = require('@config/permission-catalog-metadata');
const {
  countReferencingRows,
  listForeignKeyReferences,
} = require('@lib/database/foreign-key-references');
const { runWithoutTenantGuard } = require('../../prisma/tenant-guard');

const CANONICAL_PERMISSION_KEYS = Object.freeze(
  Array.from(new Set(Object.values(PERMISSIONS))).sort()
);

const SYSTEM_ROLE_CODES = Object.freeze(Object.keys(ROLE_PERMISSIONS).sort());

const friendlyId = (prefix, key) =>
  `${prefix}-${crypto
    .createHash('sha256')
    .update(String(key || ''))
    .digest('hex')
    .slice(0, 10)
    .toUpperCase()}`;

const nowIso = () => new Date();

const findPlatformPermissionByName = async (name, client = prisma) =>
  client.permission.findFirst({
    where: {
      tenant_id: null,
      name,
      deleted_at: null,
    },
    orderBy: [{ created_at: 'asc' }],
  });

const findPlatformRoleByName = async (name, client = prisma) =>
  client.role.findFirst({
    where: {
      tenant_id: null,
      facility_id: null,
      name,
      deleted_at: null,
    },
    orderBy: [{ created_at: 'asc' }],
  });

const upsertPlatformPermission = async (name, client = prisma) => {
  const { displayName, description } = getPermissionMetadata(name);
  const existing = await findPlatformPermissionByName(name, client);
  if (existing) {
    return client.permission.update({
      where: { id: existing.id },
      data: {
        display_name: displayName,
        description,
        tenant_id: null,
      },
    });
  }

  return client.permission.create({
    data: {
      tenant_id: null,
      name,
      display_name: displayName,
      description,
      human_friendly_id: friendlyId('PERM', `platform:${name}`),
    },
  });
};

const upsertRolePermissionLink = async (roleId, permissionId, client = prisma) => {
  const existing = await client.role_permission.findFirst({
    where: {
      role_id: roleId,
      permission_id: permissionId,
    },
  });

  if (existing) {
    if (existing.deleted_at) {
      return client.role_permission.update({
        where: { id: existing.id },
        data: { deleted_at: null },
      });
    }
    return existing;
  }

  return client.role_permission.create({
    data: {
      role_id: roleId,
      permission_id: permissionId,
      human_friendly_id: friendlyId('RPERM', `${roleId}:${permissionId}`),
    },
  });
};

const upsertPlatformRole = async (roleName, permissionMap, client = prisma) => {
  const { displayName, description } = getRoleMetadata(roleName);
  let role = await findPlatformRoleByName(roleName, client);

  if (!role) {
    role = await client.role.create({
      data: {
        tenant_id: null,
        facility_id: null,
        name: roleName,
        display_name: displayName,
        description,
        human_friendly_id: friendlyId('ROLE', `platform:${roleName}`),
      },
    });
  } else {
    role = await client.role.update({
      where: { id: role.id },
      data: {
        display_name: displayName,
        description,
        tenant_id: null,
        facility_id: null,
      },
    });
  }

  const desiredNames = new Set(ROLE_PERMISSIONS[roleName] || []);
  const existingLinks = await client.role_permission.findMany({
    where: { role_id: role.id, deleted_at: null },
    include: { permission: true },
  });

  for (const link of existingLinks) {
    const permissionName = link.permission?.name;
    if (!desiredNames.has(permissionName)) {
      await client.role_permission.update({
        where: { id: link.id },
        data: { deleted_at: nowIso() },
      });
    }
  }

  for (const permissionName of desiredNames) {
    let permission = permissionMap.get(permissionName);
    if (!permission) {
      permission = await upsertPlatformPermission(permissionName, client);
      permissionMap.set(permissionName, permission);
    }
    await upsertRolePermissionLink(role.id, permission.id, client);
  }

  return role;
};

/**
 * Seed / refresh the single platform catalog (no tenant copies).
 */
const ensurePlatformAccessCatalog = async ({ force = false } = {}) =>
  runWithoutTenantGuard(async () => {
    const permissionMap = new Map();
    for (const name of CANONICAL_PERMISSION_KEYS) {
      const permission = await upsertPlatformPermission(name);
      permissionMap.set(name, permission);
    }

    for (const roleName of SYSTEM_ROLE_CODES) {
      await upsertPlatformRole(roleName, permissionMap);
    }

    // Soft-delete duplicate platform rows (keep oldest active).
    for (const name of CANONICAL_PERMISSION_KEYS) {
      const rows = await prisma.permission.findMany({
        where: { tenant_id: null, name, deleted_at: null },
        orderBy: [{ created_at: 'asc' }],
      });
      for (const duplicate of rows.slice(1)) {
        await prisma.permission.update({
          where: { id: duplicate.id },
          data: { deleted_at: nowIso() },
        });
      }
    }

    for (const roleName of SYSTEM_ROLE_CODES) {
      const rows = await prisma.role.findMany({
        where: {
          tenant_id: null,
          facility_id: null,
          name: roleName,
          deleted_at: null,
        },
        orderBy: [{ created_at: 'asc' }],
      });
      for (const duplicate of rows.slice(1)) {
        await prisma.role.update({
          where: { id: duplicate.id },
          data: { deleted_at: nowIso() },
        });
      }
    }

    const [permissions, roles] = await Promise.all([
      prisma.permission.count({
        where: {
          tenant_id: null,
          deleted_at: null,
          name: { in: [...CANONICAL_PERMISSION_KEYS] },
        },
      }),
      prisma.role.count({
        where: {
          tenant_id: null,
          facility_id: null,
          deleted_at: null,
          name: { in: [...SYSTEM_ROLE_CODES] },
        },
      }),
    ]);

    return {
      permissions,
      roles,
      force: Boolean(force),
    };
  });

const loadPlatformPermissionMap = async () =>
  runWithoutTenantGuard(async () => {
    const records = await prisma.permission.findMany({
      where: {
        tenant_id: null,
        deleted_at: null,
        name: { in: [...CANONICAL_PERMISSION_KEYS] },
      },
    });
    return new Map(records.map((entry) => [entry.name, entry]));
  });

const loadPlatformRoleMap = async () =>
  runWithoutTenantGuard(async () => {
    const records = await prisma.role.findMany({
      where: {
        tenant_id: null,
        facility_id: null,
        deleted_at: null,
        name: { in: [...SYSTEM_ROLE_CODES] },
      },
    });
    return new Map(records.map((entry) => [entry.name, entry]));
  });

/**
 * The platform role callers should assign instead of creating a tenant copy.
 * Seeds the catalog first on a database that has never been seeded.
 *
 * @param {string} roleName
 * @param {Object} [client] - Prisma client or transaction client for the lookup
 * @returns {Promise<Object|null>}
 */
const resolvePlatformRole = async (roleName, client = prisma) =>
  runWithoutTenantGuard(async () => {
    const existing = await findPlatformRoleByName(roleName, client);
    if (existing) {
      return existing;
    }
    await ensurePlatformAccessCatalog();
    // Read outside any caller transaction: its snapshot predates the seed.
    return findPlatformRoleByName(roleName);
  });

/**
 * Active platform role with this name, or null. The database collation makes
 * the match case-insensitive.
 *
 * @param {string} name
 * @returns {Promise<{ id: string, name: string }|null>}
 */
const findActivePlatformRoleByName = async (name) => {
  const trimmed = String(name || '').trim();
  if (!trimmed) {
    return null;
  }
  return runWithoutTenantGuard(async () =>
    prisma.role.findFirst({
      where: { tenant_id: null, facility_id: null, deleted_at: null, name: trimmed },
      select: { id: true, name: true },
    })
  );
};

/**
 * Active platform permission with this name, or null.
 *
 * @param {string} name
 * @returns {Promise<{ id: string, name: string }|null>}
 */
const findActivePlatformPermissionByName = async (name) => {
  const trimmed = String(name || '').trim();
  if (!trimmed) {
    return null;
  }
  return runWithoutTenantGuard(async () =>
    prisma.permission.findFirst({
      where: { tenant_id: null, deleted_at: null, name: trimmed },
      select: { id: true, name: true },
    })
  );
};

const roleNameKey = (name) => String(name || '').trim().toUpperCase();
const permissionNameKey = (name) => String(name || '').trim().toLowerCase();

/** Tables that grant a permission to a holder, keyed by the holder column. */
const PERMISSION_LINK_TABLES = Object.freeze({
  role_permission: 'role_id',
  user_permission: 'user_id',
  api_key_permission: 'api_key_id',
});

const ROLE_LINK_TABLES = Object.freeze(new Set(['user_role', 'role_permission']));

const REVIEW_LIMIT = 50;

const indexByName = (records, keyOf) => {
  const index = new Map();
  for (const record of records) {
    const key = keyOf(record.name);
    if (key && !index.has(key)) {
      index.set(key, record);
    }
  }
  return index;
};

const grantedPermissionNames = (role) =>
  new Set(
    (role.permissions || [])
      .map((link) => permissionNameKey(link.permission?.name))
      .filter(Boolean)
  );

/** Tables outside `expectedTables` that still reference the row. */
const findUnexpectedReferences = async (table, id, expectedTables) => {
  const unexpected = [];
  for (const reference of await listForeignKeyReferences(prisma, table)) {
    if (expectedTables.has(reference.table)) {
      continue;
    }
    if ((await countReferencingRows(prisma, reference, [id])) > 0) {
      unexpected.push(reference.table);
    }
  }
  return unexpected;
};

/**
 * Point a link row at the platform record. When the holder already has that
 * link, drop the copy's row instead, reviving the platform link if only the
 * copy's link was active.
 */
const moveLink = async (delegate, link, platformLinkWhere, data) => {
  const existing = await delegate.findFirst({ where: platformLinkWhere });
  if (!existing) {
    await delegate.update({ where: { id: link.id }, data });
    return { remapped: 1, restored: 0, removed: 0 };
  }

  let restored = 0;
  if (!link.deleted_at && existing.deleted_at) {
    await delegate.update({ where: { id: existing.id }, data: { deleted_at: null } });
    restored = 1;
  }
  await delegate.delete({ where: { id: link.id } });
  return { remapped: 0, restored, removed: 1 };
};

/**
 * Merge tenant copies of platform roles and permissions into the platform catalog.
 *
 * A tenant role or permission with the same name as a platform one is a copy.
 * Its user assignments, permission links and API-key grants move to the
 * platform record, then the copy is deleted. A role copy that grants permissions
 * the platform role does not is an extension under the platform name: it is
 * left in place and reported, so nobody silently loses access — rename it to
 * keep it as a custom role.
 *
 * Seed the platform catalog first (`ensurePlatformAccessCatalog`) so every
 * system role has a platform record to merge into.
 *
 * @param {Object} [options]
 * @param {boolean} [options.dryRun=false] - Report what would change, write nothing
 * @returns {Promise<Object>} Counts, affected tenants, and copies needing review
 */
const consolidateTenantCatalogDuplicates = async ({ dryRun = false } = {}) =>
  runWithoutTenantGuard(async () => {
    const [platformRoles, platformPermissions] = await Promise.all([
      prisma.role.findMany({
        where: { tenant_id: null, facility_id: null, deleted_at: null },
        include: {
          permissions: {
            where: { deleted_at: null },
            include: { permission: { select: { name: true } } },
          },
        },
        orderBy: [{ created_at: 'asc' }],
      }),
      prisma.permission.findMany({
        where: { tenant_id: null, deleted_at: null },
        orderBy: [{ created_at: 'asc' }],
      }),
    ]);
    const platformRoleByName = indexByName(platformRoles, roleNameKey);
    const platformPermissionByName = indexByName(platformPermissions, permissionNameKey);

    const tenants = new Set();
    const roles = {
      copies: 0,
      merged: 0,
      remapped_user_roles: 0,
      restored_user_roles: 0,
      removed_user_roles: 0,
      removed_role_permissions: 0,
      needs_review: [],
    };
    const permissions = {
      copies: 0,
      merged: 0,
      remapped_links: 0,
      restored_links: 0,
      removed_links: 0,
      needs_review: [],
    };
    const flag = (bucket, entry) => {
      if (bucket.needs_review.length < REVIEW_LIMIT) {
        bucket.needs_review.push(entry);
      }
    };

    const tenantRoles = await prisma.role.findMany({
      where: { NOT: { tenant_id: null } },
      include: {
        permissions: {
          where: { deleted_at: null },
          include: { permission: { select: { name: true } } },
        },
        tenant: { select: { name: true } },
      },
      orderBy: [{ created_at: 'asc' }],
    });

    for (const copy of tenantRoles) {
      const platformRole = platformRoleByName.get(roleNameKey(copy.name));
      if (!platformRole) {
        continue;
      }
      roles.copies += 1;
      const tenantName = copy.tenant?.name || copy.tenant_id;

      const platformGrants = grantedPermissionNames(platformRole);
      const extraGrants = [...grantedPermissionNames(copy)].filter(
        (name) => !platformGrants.has(name)
      );
      if (extraGrants.length > 0) {
        flag(roles, {
          tenant: tenantName,
          role: copy.name,
          role_id: copy.id,
          reason: 'extends_platform_role',
          extra_permissions: extraGrants.sort(),
        });
        continue;
      }

      const unexpected = await findUnexpectedReferences('role', copy.id, ROLE_LINK_TABLES);
      if (unexpected.length > 0) {
        flag(roles, {
          tenant: tenantName,
          role: copy.name,
          role_id: copy.id,
          reason: 'referenced_elsewhere',
          tables: unexpected,
        });
        continue;
      }

      tenants.add(tenantName);
      roles.merged += 1;

      if (dryRun) {
        roles.remapped_user_roles += await prisma.user_role.count({ where: { role_id: copy.id } });
        roles.removed_role_permissions += await prisma.role_permission.count({
          where: { role_id: copy.id },
        });
        continue;
      }

      await prisma.$transaction(async (tx) => {
        const assignments = await tx.user_role.findMany({ where: { role_id: copy.id } });
        for (const assignment of assignments) {
          const moved = await moveLink(
            tx.user_role,
            assignment,
            {
              user_id: assignment.user_id,
              role_id: platformRole.id,
              tenant_id: assignment.tenant_id,
              facility_id: assignment.facility_id,
            },
            { role_id: platformRole.id }
          );
          roles.remapped_user_roles += moved.remapped;
          roles.restored_user_roles += moved.restored;
          roles.removed_user_roles += moved.removed;
        }

        const links = await tx.role_permission.deleteMany({ where: { role_id: copy.id } });
        roles.removed_role_permissions += links.count || 0;
        await tx.role.delete({ where: { id: copy.id } });
      });
    }

    const tenantPermissions = await prisma.permission.findMany({
      where: { NOT: { tenant_id: null } },
      include: { tenant: { select: { name: true } } },
      orderBy: [{ created_at: 'asc' }],
    });
    const permissionLinkTables = new Set(Object.keys(PERMISSION_LINK_TABLES));

    for (const copy of tenantPermissions) {
      const platformPermission = platformPermissionByName.get(permissionNameKey(copy.name));
      if (!platformPermission) {
        continue;
      }
      permissions.copies += 1;
      const tenantName = copy.tenant?.name || copy.tenant_id;

      const unexpected = await findUnexpectedReferences(
        'permission',
        copy.id,
        permissionLinkTables
      );
      if (unexpected.length > 0) {
        flag(permissions, {
          tenant: tenantName,
          permission: copy.name,
          permission_id: copy.id,
          reason: 'referenced_elsewhere',
          tables: unexpected,
        });
        continue;
      }

      tenants.add(tenantName);
      permissions.merged += 1;

      if (dryRun) {
        for (const table of permissionLinkTables) {
          permissions.remapped_links += await prisma[table].count({
            where: { permission_id: copy.id },
          });
        }
        continue;
      }

      await prisma.$transaction(async (tx) => {
        for (const [table, holderColumn] of Object.entries(PERMISSION_LINK_TABLES)) {
          const links = await tx[table].findMany({ where: { permission_id: copy.id } });
          for (const link of links) {
            const moved = await moveLink(
              tx[table],
              link,
              { [holderColumn]: link[holderColumn], permission_id: platformPermission.id },
              { permission_id: platformPermission.id }
            );
            permissions.remapped_links += moved.remapped;
            permissions.restored_links += moved.restored;
            permissions.removed_links += moved.removed;
          }
        }
        await tx.permission.delete({ where: { id: copy.id } });
      });
    }

    return {
      dry_run: Boolean(dryRun),
      platform_roles: platformRoleByName.size,
      platform_permissions: platformPermissionByName.size,
      tenants_affected: [...tenants].sort(),
      roles,
      permissions,
    };
  });

const listPlatformPermissions = async () =>
  runWithoutTenantGuard(() =>
    prisma.permission.findMany({
      where: {
        tenant_id: null,
        deleted_at: null,
        name: { in: [...CANONICAL_PERMISSION_KEYS] },
      },
      orderBy: { name: 'asc' },
    })
  );

module.exports = {
  CANONICAL_PERMISSION_KEYS,
  SYSTEM_ROLE_CODES,
  consolidateTenantCatalogDuplicates,
  ensurePlatformAccessCatalog,
  findActivePlatformPermissionByName,
  findActivePlatformRoleByName,
  listPlatformPermissions,
  loadPlatformPermissionMap,
  loadPlatformRoleMap,
  resolvePlatformRole,
};
