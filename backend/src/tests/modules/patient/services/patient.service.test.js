/**
 * Patient service tests
 *
 * @module tests/modules/patient/services
 * @description Tests for patient service business logic
 * Per testing.mdc: Service tests must mock repository and audit functions
 */

const patientService = require('@services/patient/patient.service');
const patientRepository = require('@repositories/patient/patient.repository');
const patientDeletionRepository = require('@repositories/patient/patient-deletion.repository');
const patientContactRepository = require('@repositories/patient-contact/patient-contact.repository');
const patientIdentifierRepository = require('@repositories/patient-identifier/patient-identifier.repository');
const prisma = require('@prisma/client');
const { createAuditLog } = require('@lib/audit');
const { HttpError } = require('@lib/errors');
const { findLiveStateBlockers } = require('@lib/patient/patient-cascade');
const { createStorageService } = require('@lib/storage');
const { PERMISSIONS } = require('@config/permissions');

// Mock dependencies
jest.mock('@repositories/patient/patient.repository');
jest.mock('@repositories/patient/patient-deletion.repository');
jest.mock('@repositories/patient-contact/patient-contact.repository');
jest.mock('@repositories/patient-identifier/patient-identifier.repository');
jest.mock('@lib/patient/patient-cascade', () => ({
  ...jest.requireActual('@lib/patient/patient-cascade'),
  findLiveStateBlockers: jest.fn(),
}));
jest.mock('@lib/storage', () => ({
  createStorageService: jest.fn(() => ({
    delete: jest.fn().mockResolvedValue(undefined),
  })),
}));
jest.mock('@prisma/client', () => ({
  $transaction: jest.fn(async (callback) => callback({}))
}));
jest.mock('@lib/audit');

describe('Patient Service', () => {
  const mockUserId = 'user-123';
  const mockIpAddress = '127.0.0.1';

  beforeEach(() => {
    jest.clearAllMocks();
    createAuditLog.mockReturnValue(Promise.resolve());
    findLiveStateBlockers.mockResolvedValue([]);
    prisma.$transaction.mockImplementation(async (callback) => callback({}));
    patientContactRepository.findMany.mockResolvedValue([]);
    patientIdentifierRepository.findMany.mockResolvedValue([]);
  });

  describe('listPatients', () => {
    it('should list patients with pagination', async () => {
      const mockPatients = [{ id: '1', first_name: 'John' }];
      patientRepository.findMany.mockResolvedValue(mockPatients);
      patientRepository.count.mockResolvedValue(1);

      const result = await patientService.listPatients({}, 1, 20, 'created_at', 'desc', mockUserId, mockIpAddress);

      expect(result.patients).toEqual([
        expect.objectContaining({
          id: '1',
          first_name: 'John'
        })
      ]);
      expect(result.pagination.total).toBe(1);
      expect(patientRepository.findMany).toHaveBeenCalled();
      expect(patientRepository.count).toHaveBeenCalled();
    });

    it('should build deep search clauses with multi-token AND semantics', async () => {
      patientRepository.findMany.mockResolvedValue([]);
      patientRepository.count.mockResolvedValue(0);

      await patientService.listPatients(
        { search: 'john guardian' },
        1,
        20,
        null,
        'asc',
        mockUserId,
        mockIpAddress
      );

      const whereClause = patientRepository.findMany.mock.calls[0][0];
      expect(whereClause.AND).toHaveLength(2);

      const firstTokenClause = whereClause.AND[0];
      const relationSearchClauses = firstTokenClause.OR.filter((entry) => entry && typeof entry === 'object');
      const contactSearch = relationSearchClauses.find((entry) => entry.contacts?.some);
      const identifierSearch = relationSearchClauses.find((entry) => entry.identifiers?.some);
      const guardianSearch = relationSearchClauses.find((entry) => entry.guardians?.some);
      const consentSearch = relationSearchClauses.find((entry) => entry.consents?.some);
      const appointmentSearch = relationSearchClauses.find((entry) => entry.appointments?.some);

      expect(contactSearch.contacts.some.deleted_at).toBeNull();
      expect(identifierSearch.identifiers.some.deleted_at).toBeNull();
      expect(guardianSearch.guardians.some.deleted_at).toBeNull();
      expect(consentSearch.consents.some.deleted_at).toBeNull();
      expect(appointmentSearch.appointments.some.deleted_at).toBeNull();
      expect(contactSearch.contacts.some.OR).toEqual(
        expect.arrayContaining([
          expect.objectContaining({ value: { contains: 'john' } })
        ])
      );
    });

    it('should build comprehensive combination filters for patient fields and date ranges', async () => {
      patientRepository.findMany.mockResolvedValue([]);
      patientRepository.count.mockResolvedValue(0);

      await patientService.listPatients(
        {
          patient_id: 'PAT-0200',
          first_name: 'Jan',
          last_name: 'Do',
          date_of_birth: '1990-01-02',
          gender: 'FEMALE',
          contact: '+256700000010',
          appointment_status: 'CONFIRMED',
          created_from: '2026-01-01',
          created_to: '2026-01-31',
          appointment_from: '2026-02-01',
          appointment_to: '2026-02-28'},
        1,
        20,
        'created_at',
        'desc',
        mockUserId,
        mockIpAddress
      );

      const whereClause = patientRepository.findMany.mock.calls[0][0];
      expect(whereClause.human_friendly_id).toEqual({ contains: 'PAT-0200' });
      expect(whereClause.first_name).toEqual({ contains: 'Jan' });
      expect(whereClause.last_name).toEqual({ contains: 'Do' });
      expect(whereClause.gender).toBe('FEMALE');
      expect(whereClause.date_of_birth.gte).toBeInstanceOf(Date);
      expect(whereClause.date_of_birth.lte).toBeInstanceOf(Date);
      expect(whereClause.created_at.gte).toBeInstanceOf(Date);
      expect(whereClause.created_at.lte).toBeInstanceOf(Date);
      expect(whereClause.contacts).toEqual(
        expect.objectContaining({
          some: expect.objectContaining({
            deleted_at: null})})
      );
      expect(whereClause.appointments).toEqual(
        expect.objectContaining({
          some: expect.objectContaining({
            deleted_at: null,
            status: 'CONFIRMED',
            scheduled_start: expect.objectContaining({
              gte: expect.any(Date),
              lte: expect.any(Date)})})})
      );
    });

    it('should cap search token count at five terms', async () => {
      patientRepository.findMany.mockResolvedValue([]);
      patientRepository.count.mockResolvedValue(0);

      await patientService.listPatients(
        { search: 'one two three four five six seven' },
        1,
        20,
        null,
        'desc',
        mockUserId,
        mockIpAddress
      );

      const whereClause = patientRepository.findMany.mock.calls[0][0];
      expect(whereClause.AND).toHaveLength(5);
    });

    it('should include human-readable tenant/facility context in patient list payload', async () => {
      const mockPatients = [
        {
          id: '1',
          first_name: 'John',
          contacts: [
            {
              id: 'contact-1',
              contact_type: 'PHONE',
              value: '+256783230321',
              is_primary: true
            }
          ],
          tenant: {
            human_friendly_id: 'TEN-0001',
            name: 'Alpha Tenant'
          },
          facility: {
            human_friendly_id: 'FAC-0001',
            name: 'Main Facility'
          }
        }
      ];
      patientRepository.findMany.mockResolvedValue(mockPatients);
      patientRepository.count.mockResolvedValue(1);

      const result = await patientService.listPatients({}, 1, 20, null, 'desc', mockUserId, mockIpAddress);

      expect(patientRepository.findMany).toHaveBeenCalledWith(
        expect.any(Object),
        expect.any(Number),
        expect.any(Number),
        expect.any(Object),
        expect.objectContaining({
          tenant: expect.any(Object),
          facility: expect.any(Object),
          contacts: expect.any(Object)
        }),
        expect.anything(),
        expect.objectContaining({ recordState: 'current' })
      );
      expect(result.patients[0]).toEqual(
        expect.objectContaining({
          contact: '+256783230321',
          contact_value: '+256783230321',
          contact_label: '+256783230321',
          primary_contact: '+256783230321',
          primary_contact_details: expect.objectContaining({
            contact_type: 'PHONE',
            value: '+256783230321'
          }),
          tenant_context: {
            id: 'TEN-0001',
            label: 'Alpha Tenant'
          },
          facility_context: {
            id: 'FAC-0001',
            label: 'Main Facility'
          },
          tenant_human_friendly_id: 'TEN-0001',
          facility_human_friendly_id: 'FAC-0001'
        })
      );
      expect(result.patients[0].tenant).toBeUndefined();
      expect(result.patients[0].facility).toBeUndefined();
      expect(result.patients[0].primary_contact_details.id).toBeUndefined();
    });
  });

  describe('getPatientById', () => {
    it('should get patient by id with human-readable context', async () => {
      const mockPatient = {
        id: '123',
        tenant_id: 'tenant-uuid-1',
        facility_id: 'facility-uuid-1',
        first_name: 'John',
        contacts: [
          {
            human_friendly_id: 'CNT-001',
            contact_type: 'PHONE',
            value: '+256700000123',
            is_primary: true
          }
        ],
        identifiers: [
          {
            human_friendly_id: 'PID-001',
            identifier_type: 'MRN',
            identifier_value: 'MRN-1001',
            is_primary: true
          }
        ],
        tenant: {
          human_friendly_id: 'TEN-1001',
          name: 'Tenant One'
        },
        facility: {
          human_friendly_id: 'FAC-1001',
          name: 'City Facility'
        }
      };
      patientRepository.findById.mockResolvedValue(mockPatient);

      const scope = {
        tenant_id: '550e8400-e29b-41d4-a716-446655440020',
        facility_id: '550e8400-e29b-41d4-a716-446655440021'
      };
      const result = await patientService.getPatientById('PAT0000001', mockUserId, mockIpAddress, scope);

      expect(result).toEqual(
        expect.objectContaining({
          id: '123',
          tenant_id: 'tenant-uuid-1',
          facility_id: 'facility-uuid-1',
          tenant_label: 'Tenant One',
          facility_label: 'City Facility',
          primary_phone: '+256700000123',
          primary_identifier_type: 'MRN',
          primary_identifier_value: 'MRN-1001',
          tenant_context: {
            id: 'TEN-1001',
            label: 'Tenant One'
          },
          facility_context: {
            id: 'FAC-1001',
            label: 'City Facility'
          }
        })
      );
      expect(patientRepository.findById).toHaveBeenCalledWith(
        'PAT0000001',
        expect.objectContaining({
          tenant: expect.any(Object),
          facility: expect.any(Object)
        }),
        scope
      );
    });

    it('should throw HttpError if patient not found', async () => {
      patientRepository.findById.mockResolvedValue(null);

      await expect(
        patientService.getPatientById('nonexistent', mockUserId, mockIpAddress)
      ).rejects.toThrow(HttpError);
    });
  });

  describe('createPatient', () => {
    it('should create patient and log audit', async () => {
      const mockData = {
        tenant_id: '550e8400-e29b-41d4-a716-446655440123',
        first_name: 'John',
        last_name: 'Doe'
      };
      const mockPatient = {
        id: '550e8400-e29b-41d4-a716-446655440456',
        ...mockData
      };
      const mockDecoratedPatient = {
        ...mockPatient,
        display_name: 'John Doe'
      };
      patientRepository.create.mockResolvedValue(mockPatient);
      patientRepository.findById.mockResolvedValue(mockDecoratedPatient);

      const result = await patientService.createPatient(mockData, mockUserId, mockIpAddress);

      expect(result).toEqual(
        expect.objectContaining({
          id: mockPatient.id,
          first_name: 'John',
          last_name: 'Doe',
          display_name: 'John Doe'
        })
      );
      expect(patientRepository.create).toHaveBeenCalledWith(
        expect.objectContaining({
          tenant_id: mockData.tenant_id,
          first_name: 'John',
          last_name: 'Doe'
        })
      );
      expect(patientRepository.create.mock.calls[0][0]).not.toHaveProperty('id');
      expect(patientRepository.create.mock.calls[0][0]).not.toHaveProperty(
        'human_friendly_id'
      );
      expect(createAuditLog).toHaveBeenCalledWith(expect.objectContaining({
        tenant_id: mockData.tenant_id,
        user_id: mockUserId,
        action: 'CREATE',
        entity: 'patient'
      }));
    });

    it('should ignore client-provided id and human_friendly_id and keep clinical identifiers separate', async () => {
      const mockData = {
        id: 'CM91052101TYAH',
        human_friendly_id: 'CM91052101TYAH',
        tenant_id: '550e8400-e29b-41d4-a716-446655440123',
        first_name: 'John',
        last_name: 'Doe',
        primary_identifier_type: 'NATIONAL_ID',
        primary_identifier_value: 'CM91052101TYAH'
      };
      const mockPatient = {
        id: '550e8400-e29b-41d4-a716-446655440456',
        tenant_id: mockData.tenant_id,
        first_name: 'John',
        last_name: 'Doe',
        human_friendly_id: 'PAT0000099'
      };
      patientRepository.create.mockResolvedValue(mockPatient);
      patientRepository.findById.mockResolvedValue(mockPatient);

      await patientService.createPatient(mockData, mockUserId, mockIpAddress);

      const createPayload = patientRepository.create.mock.calls[0][0];
      expect(createPayload).not.toHaveProperty('id');
      expect(createPayload).not.toHaveProperty('human_friendly_id');
      expect(createPayload).not.toHaveProperty('primary_identifier_type');
      expect(createPayload).not.toHaveProperty('primary_identifier_value');
      expect(patientIdentifierRepository.create).toHaveBeenCalledWith(
        expect.objectContaining({
          patient_id: mockPatient.id,
          identifier_type: 'NATIONAL_ID',
          identifier_value: 'CM91052101TYAH',
          is_primary: true
        }),
        expect.anything()
      );
    });

    it('should create linked primary contact and identifier records when provided', async () => {
      const mockData = {
        tenant_id: '550e8400-e29b-41d4-a716-446655440123',
        first_name: 'John',
        last_name: 'Doe',
        primary_phone: '+256700000001',
        primary_identifier_type: 'mrn',
        primary_identifier_value: 'MRN-1001'
      };
      const mockPatient = {
        id: '550e8400-e29b-41d4-a716-446655440456',
        tenant_id: mockData.tenant_id,
        first_name: 'John',
        last_name: 'Doe'
      };
      patientRepository.create.mockResolvedValue(mockPatient);
      patientRepository.findById.mockResolvedValue(mockPatient);

      await patientService.createPatient(mockData, mockUserId, mockIpAddress);

      expect(prisma.$transaction).toHaveBeenCalledTimes(1);
      expect(patientContactRepository.create).toHaveBeenCalledWith(
        expect.objectContaining({
          tenant_id: mockData.tenant_id,
          patient_id: mockPatient.id,
          contact_type: 'PHONE',
          value: '+256700000001',
          is_primary: true
        }),
        expect.anything()
      );
      expect(patientIdentifierRepository.create).toHaveBeenCalledWith(
        expect.objectContaining({
          tenant_id: mockData.tenant_id,
          patient_id: mockPatient.id,
          identifier_type: 'MRN',
          identifier_value: 'MRN-1001',
          is_primary: true
        }),
        expect.anything()
      );
    });
  });

  describe('updatePatient', () => {
    it('should keep email secondary when a primary phone still exists', async () => {
      const mockBefore = {
        id: '550e8400-e29b-41d4-a716-446655440060',
        tenant_id: '550e8400-e29b-41d4-a716-446655440123',
        first_name: 'John',
        identifiers: []};
      const mockAfter = { id: mockBefore.id, first_name: 'John' };
      const contactStore = {
        PHONE: [
          {
            id: 'contact-phone-1',
            patient_id: mockBefore.id,
            tenant_id: mockBefore.tenant_id,
            contact_type: 'PHONE',
            value: '+256700000001',
            is_primary: true,
            deleted_at: null}
        ],
        EMAIL: [
          {
            id: 'contact-email-1',
            patient_id: mockBefore.id,
            tenant_id: mockBefore.tenant_id,
            contact_type: 'EMAIL',
            value: 'old@example.com',
            is_primary: false,
            deleted_at: null}
        ]};

      patientRepository.findById
        .mockResolvedValueOnce(mockBefore)
        .mockResolvedValueOnce(mockAfter);
      patientRepository.update.mockResolvedValue(mockAfter);
      patientContactRepository.findMany.mockImplementation(async (filters = {}) => {
        const records = contactStore[filters.contact_type] || [];
        return records.filter((record) => record.deleted_at === null);
      });
      patientContactRepository.update.mockImplementation(async (id, data) => {
        for (const records of Object.values(contactStore)) {
          const match = records.find((record) => record.id === id);
          if (!match) continue;
          Object.assign(match, data);
          return { ...match };
        }
        return null;
      });

      await patientService.updatePatient(
        'PAT0000001',
        {
          primary_email: 'new@example.com'},
        mockUserId,
        mockIpAddress
      );

      expect(patientContactRepository.update).toHaveBeenCalledWith(
        'contact-email-1',
        {
          value: 'new@example.com',
          is_primary: false},
        expect.anything()
      );
      expect(contactStore.EMAIL[0].is_primary).toBe(false);
      expect(contactStore.PHONE[0].is_primary).toBe(true);
    });

    it('should promote email to primary when the primary phone is removed', async () => {
      const mockBefore = {
        id: '550e8400-e29b-41d4-a716-446655440061',
        tenant_id: '550e8400-e29b-41d4-a716-446655440123',
        first_name: 'John',
        identifiers: []};
      const mockAfter = { id: mockBefore.id, first_name: 'John' };
      const contactStore = {
        PHONE: [
          {
            id: 'contact-phone-1',
            patient_id: mockBefore.id,
            tenant_id: mockBefore.tenant_id,
            contact_type: 'PHONE',
            value: '+256700000001',
            is_primary: true,
            deleted_at: null}
        ],
        EMAIL: [
          {
            id: 'contact-email-1',
            patient_id: mockBefore.id,
            tenant_id: mockBefore.tenant_id,
            contact_type: 'EMAIL',
            value: 'email@example.com',
            is_primary: false,
            deleted_at: null}
        ]};

      patientRepository.findById
        .mockResolvedValueOnce(mockBefore)
        .mockResolvedValueOnce(mockAfter);
      patientRepository.update.mockResolvedValue(mockAfter);
      patientContactRepository.findMany.mockImplementation(async (filters = {}) => {
        const records = contactStore[filters.contact_type] || [];
        return records.filter((record) => record.deleted_at === null);
      });
      patientContactRepository.update.mockImplementation(async (id, data) => {
        for (const records of Object.values(contactStore)) {
          const match = records.find((record) => record.id === id);
          if (!match) continue;
          Object.assign(match, data);
          return { ...match };
        }
        return null;
      });

      await patientService.updatePatient(
        'PAT0000001',
        {
          primary_phone: null},
        mockUserId,
        mockIpAddress
      );

      expect(patientContactRepository.update).toHaveBeenCalledWith(
        'contact-phone-1',
        {
          deleted_at: expect.any(Date),
          is_primary: false},
        expect.anything()
      );
      expect(contactStore.PHONE[0].deleted_at).toEqual(expect.any(Date));
      expect(contactStore.EMAIL[0].is_primary).toBe(true);
    });

    it('should update patient and log audit', async () => {
      const mockBefore = {
        id: '123',
        tenant_id: '550e8400-e29b-41d4-a716-446655440123',
        first_name: 'John',
        last_name: 'Doe'
      };
      const mockAfter = { id: '123', first_name: 'Jane', last_name: 'Doe' };
      patientRepository.findById
        .mockResolvedValueOnce(mockBefore)
        .mockResolvedValueOnce(mockAfter);
      patientRepository.update.mockResolvedValue(mockAfter);

      const result = await patientService.updatePatient('123', { first_name: 'Jane' }, mockUserId, mockIpAddress);

      expect(result).toEqual(
        expect.objectContaining({
          id: '123',
          first_name: 'Jane',
          last_name: 'Doe'
        })
      );
      expect(patientRepository.update).toHaveBeenCalledWith('123', { first_name: 'Jane' }, {});
      expect(createAuditLog).toHaveBeenCalledWith(expect.objectContaining({
        tenant_id: mockBefore.tenant_id,
        action: 'UPDATE',
        diff: { before: mockBefore, after: mockAfter }
      }));
    });

    it('should resolve human-friendly route id to canonical UUID for update', async () => {
      const mockBefore = {
        id: '550e8400-e29b-41d4-a716-446655440050',
        tenant_id: '550e8400-e29b-41d4-a716-446655440123',
        first_name: 'John'
      };
      const mockAfter = { id: '550e8400-e29b-41d4-a716-446655440050', first_name: 'Jane' };
      patientRepository.findById
        .mockResolvedValueOnce(mockBefore)
        .mockResolvedValueOnce(mockAfter);
      patientRepository.update.mockResolvedValue(mockAfter);

      await patientService.updatePatient('PAT0000001', { first_name: 'Jane' }, mockUserId, mockIpAddress);

      expect(patientRepository.update).toHaveBeenCalledWith(
        '550e8400-e29b-41d4-a716-446655440050',
        { first_name: 'Jane' },
        {}
      );
    });

    it('should update linked primary contact and identifier records when related fields change', async () => {
      const mockBefore = {
        id: '550e8400-e29b-41d4-a716-446655440050',
        tenant_id: '550e8400-e29b-41d4-a716-446655440123',
        first_name: 'John',
        identifiers: []};
      const mockAfter = {
        id: '550e8400-e29b-41d4-a716-446655440050',
        first_name: 'John'};
      patientRepository.findById
        .mockResolvedValueOnce(mockBefore)
        .mockResolvedValueOnce(mockAfter);
      patientRepository.update.mockResolvedValue(mockAfter);
      patientContactRepository.findMany.mockResolvedValue([{ id: 'contact-1' }]);
      patientIdentifierRepository.findMany.mockResolvedValue([{ id: 'identifier-1' }]);

      await patientService.updatePatient(
        'PAT0000001',
        {
          primary_phone: '+256700000099',
          primary_identifier_type: 'national_id',
          primary_identifier_value: 'CF-1001'},
        mockUserId,
        mockIpAddress
      );

      expect(prisma.$transaction).toHaveBeenCalledTimes(1);
      expect(patientContactRepository.update).toHaveBeenCalledWith(
        'contact-1',
        {
          value: '+256700000099',
          is_primary: true},
        expect.anything()
      );
      expect(patientIdentifierRepository.update).toHaveBeenCalledWith(
        'identifier-1',
        {
          identifier_type: 'NATIONAL_ID',
          identifier_value: 'CF-1001',
          is_primary: true},
        expect.anything()
      );
    });

    it('should throw HttpError if patient not found', async () => {
      patientRepository.findById.mockResolvedValue(null);

      await expect(
        patientService.updatePatient('nonexistent', {}, mockUserId, mockIpAddress)
      ).rejects.toThrow(HttpError);
    });
  });

  describe('deletePatient', () => {
    it('should cascade soft delete patient, write manifest, and log audit', async () => {
      const mockPatient = {
        id: '123',
        first_name: 'John',
        human_friendly_id: 'PAT0000001',
        tenant_id: 'tenant-1',
      };
      const mockBatch = {
        id: 'batch-1',
        human_friendly_id: 'PDB0000001',
      };
      patientRepository.findById.mockResolvedValue(mockPatient);
      patientDeletionRepository.softDeleteCascadeInTx.mockResolvedValue({
        batch: mockBatch,
        counts: { by_model: { visit_queue: 1 }, by_category: { clinical: 1 }, patient: 1 },
        idsByModel: { visit_queue: ['vq-1'] },
      });

      await patientService.deletePatient('123', mockUserId, mockIpAddress);

      expect(findLiveStateBlockers).toHaveBeenCalledWith(prisma, '123');
      expect(patientDeletionRepository.softDeleteCascadeInTx).toHaveBeenCalledWith(
        {},
        expect.objectContaining({
          patient: mockPatient,
          deletedByUserId: mockUserId,
        })
      );
      expect(createAuditLog).toHaveBeenCalledWith(expect.objectContaining({
        action: 'PATIENT_SOFT_DELETED',
        entity: 'patient',
        entity_id: '123',
        diff: expect.objectContaining({
          human_friendly_id: 'PAT0000001',
          batch_id: 'batch-1',
        }),
      }));
    });

    it('should resolve human-friendly route id to canonical UUID for delete', async () => {
      const mockPatient = {
        id: '550e8400-e29b-41d4-a716-446655440051',
        first_name: 'John',
        human_friendly_id: 'PAT0000001',
        tenant_id: 'tenant-1',
      };
      patientRepository.findById.mockResolvedValue(mockPatient);
      patientDeletionRepository.softDeleteCascadeInTx.mockResolvedValue({
        batch: { id: 'batch-1', human_friendly_id: 'PDB0000001' },
        counts: { by_model: {}, by_category: {}, patient: 1 },
        idsByModel: {},
      });

      await patientService.deletePatient('PAT0000001', mockUserId, mockIpAddress);

      expect(patientDeletionRepository.softDeleteCascadeInTx).toHaveBeenCalledWith(
        {},
        expect.objectContaining({
          patient: expect.objectContaining({
            id: '550e8400-e29b-41d4-a716-446655440051',
          }),
        })
      );
      expect(createAuditLog).toHaveBeenCalledWith(
        expect.objectContaining({
          entity_id: '550e8400-e29b-41d4-a716-446655440051',
        })
      );
    });

    it('should refuse soft delete when live state blockers exist', async () => {
      const mockPatient = { id: '123', first_name: 'John', tenant_id: 'tenant-1' };
      patientRepository.findById.mockResolvedValue(mockPatient);
      findLiveStateBlockers.mockResolvedValue([
        { code: 'active_admission', model: 'admission', count: 1 },
      ]);

      await expect(
        patientService.deletePatient('123', mockUserId, mockIpAddress)
      ).rejects.toMatchObject({
        messageKey: 'errors.patient.live_state_blocked',
        statusCode: 409,
      });
      expect(patientDeletionRepository.softDeleteCascadeInTx).not.toHaveBeenCalled();
    });

    it('should throw HttpError if patient not found', async () => {
      patientRepository.findById.mockResolvedValue(null);

      await expect(
        patientService.deletePatient('nonexistent', mockUserId, mockIpAddress)
      ).rejects.toThrow(HttpError);
    });
  });

  describe('restorePatient', () => {
    it('should restore from the latest unrestored batch', async () => {
      const mockPatient = {
        id: '123',
        first_name: 'John',
        human_friendly_id: 'PAT0000001',
        tenant_id: 'tenant-1',
        deleted_at: new Date(),
      };
      const batch = {
        id: 'batch-1',
        human_friendly_id: 'PDB0000001',
        counts_json: { patient: 1 },
        items: [{ entity_model: 'patient', entity_id: '123' }],
      };
      patientRepository.findByIdIncludingDeleted.mockResolvedValue(mockPatient);
      patientDeletionRepository.findLatestUnrestoredBatch.mockResolvedValue(batch);
      patientDeletionRepository.findRestoreConflicts.mockResolvedValue([]);
      patientDeletionRepository.restoreCascadeInTx.mockResolvedValue({
        ...mockPatient,
        deleted_at: null,
      });

      const result = await patientService.restorePatient('123', mockUserId, mockIpAddress);

      expect(patientDeletionRepository.restoreCascadeInTx).toHaveBeenCalled();
      expect(result).toEqual(expect.objectContaining({ id: '123', first_name: 'John' }));
      expect(createAuditLog).toHaveBeenCalledWith(
        expect.objectContaining({ action: 'PATIENT_RESTORED' })
      );
    });

    it('should conflict when identifiers are reused', async () => {
      const mockPatient = {
        id: '123',
        first_name: 'John',
        tenant_id: 'tenant-1',
        deleted_at: new Date(),
      };
      patientRepository.findByIdIncludingDeleted.mockResolvedValue(mockPatient);
      patientDeletionRepository.findLatestUnrestoredBatch.mockResolvedValue({
        id: 'batch-1',
        items: [],
      });
      patientDeletionRepository.findRestoreConflicts.mockResolvedValue([
        { code: 'identifier_in_use', field: 'identifier_value' },
      ]);
      prisma.$transaction.mockImplementation(async (callback) => callback({}));

      await expect(
        patientService.restorePatient('123', mockUserId, mockIpAddress)
      ).rejects.toMatchObject({
        messageKey: 'errors.patient.restore_conflict',
        statusCode: 409,
      });
    });
  });

  describe('permanentDeletePatient', () => {
    it('should require confirm and an admin grant', async () => {
      await expect(
        patientService.permanentDeletePatient('123', mockUserId, mockIpAddress, {}, {
          confirm: false,
          actor: { permissions: [PERMISSIONS.FACILITY_ADMIN] },
        })
      ).rejects.toMatchObject({
        messageKey: 'errors.patient.permanent_confirm_required',
      });

      await expect(
        patientService.permanentDeletePatient('123', mockUserId, mockIpAddress, {}, {
          confirm: true,
          actor: { permissions: [PERMISSIONS.PATIENT_DELETE] },
        })
      ).rejects.toMatchObject({
        messageKey: 'errors.patient.purge_forbidden',
        statusCode: 403,
      });
    });

    it('should purge soft-deleted patient and delete storage keys', async () => {
      const mockPatient = {
        id: '123',
        first_name: 'John',
        human_friendly_id: 'PAT0000001',
        tenant_id: 'tenant-1',
        deleted_at: new Date(),
      };
      const storage = { delete: jest.fn().mockResolvedValue(undefined) };
      createStorageService.mockReturnValue(storage);
      patientRepository.findByIdIncludingDeleted.mockResolvedValue(mockPatient);
      patientDeletionRepository.findLatestUnrestoredBatch.mockResolvedValue({
        id: 'batch-1',
        human_friendly_id: 'PDB0000001',
        counts_json: { patient: 1 },
      });
      patientDeletionRepository.permanentPurgeInTx.mockResolvedValue({
        anonymized: true,
        storageKeys: ['docs/a.pdf'],
        retained_references: 1,
        counts: { patient: 1 },
      });

      await patientService.permanentDeletePatient('123', mockUserId, mockIpAddress, {}, {
        confirm: true,
        actor: { permissions: [PERMISSIONS.FACILITY_ADMIN, PERMISSIONS.PATIENT_DELETE] },
      });

      expect(patientDeletionRepository.permanentPurgeInTx).toHaveBeenCalled();
      expect(storage.delete).toHaveBeenCalledWith('docs/a.pdf');
      expect(createAuditLog).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'PATIENT_PERMANENTLY_DELETED',
          diff: expect.objectContaining({ irreversible: true }),
        })
      );
    });
  });
});
