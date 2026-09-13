/**
 * Sync / reseed the platform-scoped permission + default role catalog.
 *
 * Usage:
 *   node scripts/sync-permission-catalog.js --dry-run   # report tenant copies, write nothing
 *   node scripts/sync-permission-catalog.js             # seed, then merge tenant copies
 *
 * Seeds once at platform scope, then merges tenant copies of platform roles and
 * permissions into the platform catalog and deletes the copies.
 */

const { prisma } = require('./seeders/seed-runtime');
const {
  ensurePlatformAccessCatalog,
  consolidateTenantCatalogDuplicates,
  clearAccessCatalogCache,
} = require('@lib/authorization/permission-catalog-sync');

const main = async () => {
  const dryRun = process.argv.slice(2).includes('--dry-run');
  clearAccessCatalogCache();

  if (dryRun) {
    console.log('Dry run: nothing will be written.');
  } else {
    console.log('Seeding platform access catalog...');
    const seeded = await ensurePlatformAccessCatalog({ force: true });
    console.log(
      `Platform catalog ready: ${seeded.permissions} permissions, ${seeded.roles} roles`
    );
  }

  console.log('Merging tenant copies of platform roles and permissions...');
  const consolidated = await consolidateTenantCatalogDuplicates({ dryRun });
  console.log(JSON.stringify(consolidated, null, 2));
  console.log('Done.');
};

main()
  .catch((error) => {
    console.error('Permission catalog sync failed:', error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
