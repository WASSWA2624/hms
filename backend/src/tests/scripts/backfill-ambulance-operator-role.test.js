/**
 * backfill-ambulance-operator-role script tests
 */

jest.mock('@prisma/client', () => ({
  role: {
    count: jest.fn(),
    create: jest.fn()},
  $disconnect: jest.fn()}));

jest.mock('@lib/authorization/platform-access-catalog', () => ({
  ensurePlatformAccessCatalog: jest.fn(),
  findActivePlatformRoleByName: jest.fn()}));

const prisma = require('@prisma/client');
const platformCatalog = require('@lib/authorization/platform-access-catalog');
const {
  parseCliArgs,
  ensureAmbulanceOperatorRole} = require('../../../scripts/backfill-ambulance-operator-role');

describe('backfill-ambulance-operator-role script', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    prisma.role.count.mockResolvedValue(0);
  });

  describe('parseCliArgs', () => {
    it('reads --dry-run', () => {
      expect(parseCliArgs(['--dry-run'])).toEqual({ dryRun: true });
      expect(parseCliArgs([])).toEqual({ dryRun: false });
    });
  });

  describe('ensureAmbulanceOperatorRole', () => {
    it('never creates tenant or facility copies of the platform role', async () => {
      platformCatalog.findActivePlatformRoleByName.mockResolvedValue({ id: 'platform-role' });
      prisma.role.count.mockResolvedValue(2);

      const summary = await ensureAmbulanceOperatorRole({ dryRun: false });

      expect(summary).toEqual({
        dryRun: false,
        platformRoleExists: true,
        platformRoleCreated: false,
        tenantCopies: 2});
      expect(prisma.role.create).not.toHaveBeenCalled();
      expect(platformCatalog.ensurePlatformAccessCatalog).not.toHaveBeenCalled();
    });

    it('seeds the platform catalog when the role is missing', async () => {
      platformCatalog.findActivePlatformRoleByName
        .mockResolvedValueOnce(null)
        .mockResolvedValueOnce({ id: 'platform-role' });

      const summary = await ensureAmbulanceOperatorRole({ dryRun: false });

      expect(platformCatalog.ensurePlatformAccessCatalog).toHaveBeenCalledTimes(1);
      expect(summary).toMatchObject({ platformRoleExists: true, platformRoleCreated: true });
      expect(prisma.role.create).not.toHaveBeenCalled();
    });

    it('writes nothing on a dry run', async () => {
      platformCatalog.findActivePlatformRoleByName.mockResolvedValue(null);

      const summary = await ensureAmbulanceOperatorRole({ dryRun: true });

      expect(summary).toMatchObject({ dryRun: true, platformRoleExists: false, platformRoleCreated: false });
      expect(platformCatalog.ensurePlatformAccessCatalog).not.toHaveBeenCalled();
    });
  });
});
