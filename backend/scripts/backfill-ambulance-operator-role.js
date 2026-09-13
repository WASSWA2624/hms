/**
 * Ensure the platform AMBULANCE_OPERATOR role exists.
 *
 * AMBULANCE_OPERATOR is a platform catalog role: organizations assign it as-is
 * and never keep their own copy. This script used to create a tenant or facility
 * copy per organization; it now only makes sure the single platform role is
 * seeded. Merge tenant copies that already exist with
 * `node scripts/sync-permission-catalog.js`.
 *
 * Usage:
 *   node scripts/backfill-ambulance-operator-role.js
 *   node scripts/backfill-ambulance-operator-role.js --dry-run
 *
 * @module scripts/backfill-ambulance-operator-role
 */

// Must be absolute first - register module aliases before any other requires
require('module-alias/register');
const path = require('path');

// Register global aliases for runtime resolution
try {
  const moduleAlias = require('module-alias');
  const prismaRuntimePath = path.join(__dirname, '..', 'node_modules', '@prisma', 'client', 'runtime');

  moduleAlias.addAliases({
    '@app': path.join(__dirname, '..', 'src', 'app'),
    '@lib': path.join(__dirname, '..', 'src', 'lib'),
    '@config': path.join(__dirname, '..', 'src', 'config'),
    '@middlewares': path.join(__dirname, '..', 'src', 'middlewares'),
    '@logs': path.join(process.cwd(), 'logs'),
    '@websockets': path.join(__dirname, '..', 'src', 'websockets'),
    '@modules': path.join(__dirname, '..', 'src', 'modules'),
    '@prisma/client': path.join(__dirname, '..', 'src', 'prisma', 'client.js')
  });

  moduleAlias.addAlias('@prisma/client/runtime', prismaRuntimePath);
} catch (err) {
  console.error('Failed to register module aliases:', err);
  process.exit(1);
}

// Register module-scoped aliases
try {
  const { registerAllModuleAliases } = require('@lib/aliases');
  registerAllModuleAliases();
} catch (err) {
  console.warn('Failed to register module aliases (may not be critical):', err.message);
}

const prisma = require('@prisma/client');
const {
  ensurePlatformAccessCatalog,
  findActivePlatformRoleByName
} = require('@lib/authorization/platform-access-catalog');

const ROLE_NAME = 'AMBULANCE_OPERATOR';

const parseCliArgs = (argv = process.argv.slice(2)) => ({
  dryRun: argv.includes('--dry-run')
});

const ensureAmbulanceOperatorRole = async ({ dryRun = false } = {}) => {
  const tenantCopies = await prisma.role.count({
    where: {
      name: ROLE_NAME,
      deleted_at: null,
      NOT: { tenant_id: null }
    }
  });

  const existing = await findActivePlatformRoleByName(ROLE_NAME);
  if (existing || dryRun) {
    return {
      dryRun,
      platformRoleExists: Boolean(existing),
      platformRoleCreated: false,
      tenantCopies
    };
  }

  await ensurePlatformAccessCatalog();
  const seeded = await findActivePlatformRoleByName(ROLE_NAME);
  return {
    dryRun,
    platformRoleExists: Boolean(seeded),
    platformRoleCreated: Boolean(seeded),
    tenantCopies
  };
};

const printSummary = (summary) => {
  console.log('');
  console.log('AMBULANCE_OPERATOR platform role');
  console.log(`- mode: ${summary.dryRun ? 'dry-run' : 'execute'}`);
  console.log(`- platform role exists: ${summary.platformRoleExists ? 'yes' : 'no'}`);
  if (summary.platformRoleCreated) {
    console.log('- platform role seeded: yes');
  }
  console.log(`- tenant copies still present: ${summary.tenantCopies}`);
  if (summary.tenantCopies > 0) {
    console.log('  Merge them with: node scripts/sync-permission-catalog.js --dry-run, then without --dry-run');
  }
};

const main = async () => {
  try {
    const summary = await ensureAmbulanceOperatorRole(parseCliArgs());
    printSummary(summary);

    if (!summary.dryRun && !summary.platformRoleExists) {
      process.exitCode = 1;
    }
  } catch (error) {
    console.error('Failed to ensure the AMBULANCE_OPERATOR platform role:', error);
    process.exitCode = 1;
  } finally {
    await prisma.$disconnect();
  }
};

if (require.main === module) {
  main();
}

module.exports = {
  ROLE_NAME,
  parseCliArgs,
  ensureAmbulanceOperatorRole
};
