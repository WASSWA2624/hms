/**
 * User-Role repository tests
 *
 * @module tests/modules/user-role/repositories
 * Per testing.mdc: Mock all Prisma operations
 */

const { HttpError } = require('@lib/errors');

jest.mock('@prisma/client', () => ({
  user_role: {
    findFirst: jest.fn(),
    findMany: jest.fn(),
    count: jest.fn(),
    create: jest.fn(),
    update: jest.fn()
  },
  facility: {
    findFirst: jest.fn(),
    findMany: jest.fn()}
}));

const {
  findById,
  findMany,
  count,
  create,
  update,
  softDelete
} = require('@repositories/user-role/user-role.repository');

const prisma = require('@prisma/client');

describe('User-Role Repository', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('findById', () => {
    it('should find user-role by ID with related labels', async () => {
      const mock = {
        id: 'ur-123',
        user_id: 'user-123',
        role_id: 'role-123',
        tenant_id: 'tenant-123',
        facility_id: 'facility-123',
        user: { id: 'user-123', email: 'alice@example.com' },
        role: { id: 'role-123', name: 'Admin' },
        tenant: { id: 'tenant-123', name: 'Tenant One', slug: 'tenant-one' }};
      const facility = {
        id: 'facility-123',
        human_friendly_id: 'FAC-001',
        name: 'Main Campus'};
      prisma.user_role.findFirst.mockResolvedValue(mock);
      prisma.facility.findFirst.mockResolvedValue(facility);

      const result = await findById('ur-123');

      expect(result).toEqual({
        ...mock,
        facility});
      expect(prisma.user_role.findFirst).toHaveBeenCalledWith(expect.objectContaining({
        where: {
          id: 'ur-123',
          deleted_at: null},
        include: expect.objectContaining({
          user: expect.any(Object),
          role: expect.any(Object),
          tenant: expect.any(Object)})}));
      expect(prisma.facility.findFirst).toHaveBeenCalledWith({
        where: {
          id: 'facility-123',
          deleted_at: null},
        select: {
          id: true,
          human_friendly_id: true,
          name: true}});
    });

    it('should attach null facility when facility_id is missing', async () => {
      const mock = {
        id: 'ur-123',
        user_id: 'user-123',
        role_id: 'role-123',
        tenant_id: 'tenant-123',
        facility_id: null};
      prisma.user_role.findFirst.mockResolvedValue(mock);

      const result = await findById('ur-123');

      expect(result).toEqual({
        ...mock,
        facility: null});
      expect(prisma.facility.findFirst).not.toHaveBeenCalled();
    });
  });

  describe('findMany', () => {
    it('should find many user-roles with related labels', async () => {
      const mocks = [
        {
          id: 'ur-1',
          tenant: { id: 'tenant-1', name: 'Tenant One' },
          facility_id: 'facility-1'},
        {
          id: 'ur-2',
          tenant: { id: 'tenant-2', name: 'Tenant Two' },
          facility_id: null}];
      const facilities = [
        {
          id: 'facility-1',
          human_friendly_id: 'FAC-001',
          name: 'Main Campus'}];
      prisma.user_role.findMany.mockResolvedValue(mocks);
      prisma.facility.findMany.mockResolvedValue(facilities);

      const result = await findMany({}, 0, 20);

      expect(result).toEqual([
        {
          ...mocks[0],
          facility: facilities[0]},
        {
          ...mocks[1],
          facility: null}]);
      expect(prisma.user_role.findMany).toHaveBeenCalledWith(expect.objectContaining({
        include: expect.objectContaining({
          user: expect.any(Object),
          role: expect.any(Object),
          tenant: expect.any(Object)})}));
      expect(prisma.facility.findMany).toHaveBeenCalledWith({
        where: {
          id: { in: ['facility-1'] },
          deleted_at: null},
        select: {
          id: true,
          human_friendly_id: true,
          name: true}});
    });
  });

  describe('count', () => {
    it('should count user-roles', async () => {
      prisma.user_role.count.mockResolvedValue(5);
      const result = await count({});
      expect(result).toBe(5);
    });
  });

  describe('create', () => {
    it('should create user-role and return the enriched record', async () => {
      const created = {
        id: 'ur-123',
        user_id: 'user-123',
        role_id: 'role-123',
        tenant_id: 'tenant-123',
        facility_id: 'facility-123'};
      const enriched = {
        ...created,
        user: { id: 'user-123', email: 'alice@example.com' },
        role: { id: 'role-123', name: 'Admin' },
        tenant: { id: 'tenant-123', name: 'Tenant One', slug: 'tenant-one' }};
      const facility = {
        id: 'facility-123',
        human_friendly_id: 'FAC-001',
        name: 'Main Campus'};
      prisma.user_role.findFirst
        .mockResolvedValueOnce(null)
        .mockResolvedValueOnce(enriched);
      prisma.user_role.create.mockResolvedValue(created);
      prisma.facility.findFirst.mockResolvedValue(facility);

      const result = await create(created);

      expect(prisma.user_role.create).toHaveBeenCalledWith({
        data: created});
      expect(prisma.user_role.findFirst).toHaveBeenNthCalledWith(
        1,
        expect.objectContaining({
          where: {
            user_id: 'user-123',
            role_id: 'role-123',
            tenant_id: 'tenant-123',
            facility_id: 'facility-123',
            // Naming deleted_at keeps the tenant guard from hiding soft-deleted rows.
            OR: [{ deleted_at: null }, { deleted_at: { not: null } }]}})
      );
      expect(prisma.user_role.findFirst).toHaveBeenNthCalledWith(
        2,
        expect.objectContaining({
          where: {
            id: 'ur-123',
            deleted_at: null}})
      );
      expect(result).toEqual({
        ...enriched,
        facility});
    });

    it('should restore a soft-deleted user-role instead of failing unique', async () => {
      const softDeleted = {
        id: 'ur-123',
        user_id: 'user-123',
        role_id: 'role-123',
        tenant_id: 'tenant-123',
        facility_id: 'facility-123',
        deleted_at: new Date('2026-01-01T00:00:00.000Z')};
      const restored = {
        ...softDeleted,
        deleted_at: null,
        user: { id: 'user-123', email: 'alice@example.com' },
        role: { id: 'role-123', name: 'Admin' },
        tenant: { id: 'tenant-123', name: 'Tenant One', slug: 'tenant-one' }};
      prisma.user_role.findFirst
        .mockResolvedValueOnce(softDeleted)
        .mockResolvedValueOnce(restored);
      prisma.user_role.update.mockResolvedValue(restored);
      prisma.facility.findFirst.mockResolvedValue(null);

      const result = await create({
        user_id: 'user-123',
        role_id: 'role-123',
        tenant_id: 'tenant-123',
        facility_id: 'facility-123'});

      expect(prisma.user_role.create).not.toHaveBeenCalled();
      expect(prisma.user_role.update).toHaveBeenCalledWith({
        where: { id: 'ur-123', deleted_at: { not: null } },
        data: {
          deleted_at: null,
          version: { increment: 1 }}});
      expect(result).toEqual({
        ...restored,
        facility: null});
    });

    it('should return an active user-role when already assigned', async () => {
      const active = {
        id: 'ur-123',
        user_id: 'user-123',
        role_id: 'role-123',
        tenant_id: 'tenant-123',
        facility_id: null,
        deleted_at: null,
        user: { id: 'user-123', email: 'alice@example.com' },
        role: { id: 'role-123', name: 'Admin' },
        tenant: { id: 'tenant-123', name: 'Tenant One', slug: 'tenant-one' }};
      prisma.user_role.findFirst
        .mockResolvedValueOnce(active)
        .mockResolvedValueOnce(active);

      const result = await create({
        user_id: 'user-123',
        role_id: 'role-123',
        tenant_id: 'tenant-123',
        facility_id: null});

      expect(prisma.user_role.create).not.toHaveBeenCalled();
      expect(prisma.user_role.update).not.toHaveBeenCalled();
      expect(result).toEqual({
        ...active,
        facility: null});
    });
  });

  describe('update', () => {
    it('should update user-role and return the enriched record', async () => {
      const updated = { id: 'ur-123', role_id: 'role-456', facility_id: null };
      const enriched = {
        ...updated,
        role: { id: 'role-456', name: 'Billing' }};
      prisma.user_role.update.mockResolvedValue(updated);
      prisma.user_role.findFirst.mockResolvedValue(enriched);

      const result = await update('ur-123', { role_id: 'role-456' });

      expect(prisma.user_role.update).toHaveBeenCalledWith({
        where: { id: 'ur-123' },
        data: { role_id: 'role-456' }});
      expect(result).toEqual({
        ...enriched,
        facility: null});
    });
  });

  describe('softDelete', () => {
    it('should soft delete user-role', async () => {
      const mock = { id: 'ur-123', deleted_at: new Date() };
      prisma.user_role.update.mockResolvedValue(mock);

      const result = await softDelete('ur-123');

      expect(result).toEqual(mock);
    });
  });
});
