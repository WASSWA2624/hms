/**
 * Patient repository tests
 *
 * @module tests/modules/patient/repositories
 * @description Tests for patient repository operations
 * Per testing.mdc: Repository tests must mock Prisma client
 */

const patientRepository = require('@repositories/patient/patient.repository');
const prisma = require('@prisma/client');
const { HttpError } = require('@lib/errors');

// Mock Prisma client
jest.mock('@prisma/client', () => ({
  patient: {
    findFirst: jest.fn(),
    findMany: jest.fn(),
    count: jest.fn(),
    create: jest.fn(),
    update: jest.fn()
  }
}));

describe('Patient Repository', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('findById', () => {
    it('should find patient by id', async () => {
      const mockPatient = {
        id: '550e8400-e29b-41d4-a716-446655440001',
        first_name: 'John',
        last_name: 'Doe'
      };
      prisma.patient.findFirst.mockResolvedValue(mockPatient);

      const result = await patientRepository.findById('550e8400-e29b-41d4-a716-446655440001');
      expect(result).toEqual(mockPatient);
      expect(prisma.patient.findFirst).toHaveBeenCalledWith({
        where: {
          id: '550e8400-e29b-41d4-a716-446655440001',
          deleted_at: null,
          AND: [{ NOT: { first_name: 'Deleted patient' } }],
        },
        include: undefined
      });
    });

    it('should return null if patient not found', async () => {
      prisma.patient.findFirst.mockResolvedValue(null);

      const result = await patientRepository.findById('nonexistent');
      expect(result).toBeNull();
    });

    it('should include optional tenant and facility scope filters', async () => {
      const mockPatient = { id: '123', first_name: 'John' };
      prisma.patient.findFirst.mockResolvedValue(mockPatient);

      await patientRepository.findById(
        'pat0000001',
        {},
        {
          tenant_id: '550e8400-e29b-41d4-a716-446655440010',
          facility_id: '550e8400-e29b-41d4-a716-446655440011'
        }
      );

      expect(prisma.patient.findFirst).toHaveBeenCalledWith({
        where: {
          human_friendly_id: 'PAT0000001',
          deleted_at: null,
          tenant_id: '550e8400-e29b-41d4-a716-446655440010',
          facility_id: '550e8400-e29b-41d4-a716-446655440011',
          AND: [{ NOT: { first_name: 'Deleted patient' } }],
        },
        include: undefined
      });
    });

    it('should not relax facility scope when facility-scoped lookup misses', async () => {
      prisma.patient.findFirst.mockResolvedValue(null);

      const result = await patientRepository.findById(
        'PAT0000001',
        {},
        {
          tenant_id: '550e8400-e29b-41d4-a716-446655440010',
          facility_id: '550e8400-e29b-41d4-a716-446655440011'
        }
      );

      expect(result).toBeNull();
      expect(prisma.patient.findFirst).toHaveBeenCalledTimes(1);
      expect(prisma.patient.findFirst).toHaveBeenCalledWith({
        where: {
          human_friendly_id: 'PAT0000001',
          deleted_at: null,
          tenant_id: '550e8400-e29b-41d4-a716-446655440010',
          facility_id: '550e8400-e29b-41d4-a716-446655440011',
          AND: [{ NOT: { first_name: 'Deleted patient' } }],
        },
        include: undefined
      });
    });

    it('should support tenant and facility scope with human-friendly IDs', async () => {
      const mockPatient = { id: '123', first_name: 'John' };
      prisma.patient.findFirst.mockResolvedValue(mockPatient);

      const result = await patientRepository.findById(
        'PAT0000001',
        {},
        {
          tenant_id: 'TEN0000001',
          facility_id: 'FAC0000001'
        }
      );

      expect(result).toEqual(mockPatient);
      expect(prisma.patient.findFirst).toHaveBeenCalledWith({
        where: {
          human_friendly_id: 'PAT0000001',
          deleted_at: null,
          tenant: {
            human_friendly_id: 'TEN0000001'
          },
          facility: {
            human_friendly_id: 'FAC0000001'
          },
          AND: [{ NOT: { first_name: 'Deleted patient' } }],
        },
        include: undefined
      });
    });

    it('should throw HttpError on database error', async () => {
      prisma.patient.findFirst.mockRejectedValue(new Error('DB Error'));

      await expect(patientRepository.findById('123')).rejects.toThrow(HttpError);
    });
  });

  describe('findMany', () => {
    it('should find many patients with pagination', async () => {
      const mockPatients = [
        { id: '1', first_name: 'John', last_name: 'Doe' },
        { id: '2', first_name: 'Jane', last_name: 'Smith' }
      ];
      prisma.patient.findMany.mockResolvedValue(mockPatients);

      const result = await patientRepository.findMany({}, 0, 20);
      expect(result).toEqual(mockPatients);
      expect(prisma.patient.findMany).toHaveBeenCalled();
    });
  });

  describe('count', () => {
    it('should count patients', async () => {
      prisma.patient.count.mockResolvedValue(42);

      const result = await patientRepository.count({});
      expect(result).toBe(42);
    });
  });

  describe('create', () => {
    it('should create patient', async () => {
      const mockData = { tenant_id: '123', first_name: 'John', last_name: 'Doe' };
      const mockPatient = { id: '456', ...mockData };
      prisma.patient.create.mockResolvedValue(mockPatient);

      const result = await patientRepository.create(mockData);
      expect(result).toEqual(mockPatient);
    });

    it('should throw HttpError on unique constraint violation', async () => {
      const error = new Error('Unique constraint');
      error.code = 'P2002';
      error.meta = { target: ['email'] };
      prisma.patient.create.mockRejectedValue(error);

      await expect(patientRepository.create({})).rejects.toThrow(HttpError);
    });

    it('should throw HttpError on foreign key constraint violation', async () => {
      const error = new Error('Foreign key constraint');
      error.code = 'P2003';
      error.meta = { field_name: 'tenant_id' };
      prisma.patient.create.mockRejectedValue(error);

      await expect(patientRepository.create({})).rejects.toThrow(HttpError);
    });
  });

  describe('update', () => {
    it('should update patient', async () => {
      const mockPatient = { id: '123', first_name: 'Jane', last_name: 'Doe' };
      prisma.patient.findFirst.mockResolvedValue({ id: '123' });
      prisma.patient.update.mockResolvedValue(mockPatient);

      const result = await patientRepository.update('123', { first_name: 'Jane' });
      expect(result).toEqual(mockPatient);
      expect(prisma.patient.update).toHaveBeenCalledWith({
        where: { id: '123' },
        data: { first_name: 'Jane' }
      });
    });

    it('should throw HttpError if patient not found', async () => {
      prisma.patient.findFirst.mockResolvedValue(null);

      await expect(patientRepository.update('nonexistent', {})).rejects.toThrow(HttpError);
    });
  });

  describe('softDelete', () => {
    it('should soft delete patient', async () => {
      const mockPatient = { id: '123', deleted_at: new Date() };
      prisma.patient.findFirst.mockResolvedValue({ id: '123' });
      prisma.patient.update.mockResolvedValue(mockPatient);

      const result = await patientRepository.softDelete('123');
      expect(result).toEqual(mockPatient);
      expect(prisma.patient.update).toHaveBeenCalledWith({
        where: { id: '123' },
        data: { deleted_at: expect.any(Date) }
      });
    });

    it('should throw HttpError if patient not found', async () => {
      prisma.patient.findFirst.mockResolvedValue(null);

      await expect(patientRepository.softDelete('nonexistent')).rejects.toThrow(HttpError);
    });
  });
});
