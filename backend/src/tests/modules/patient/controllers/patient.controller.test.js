/**
 * Patient controller tests
 *
 * @module tests/modules/patient/controllers
 * @description Tests for patient controller request handlers
 * Per testing.mdc: Controller tests must mock service layer
 */

const patientController = require('@controllers/patient/patient.controller');
const patientService = require('@services/patient/patient.service');
const { sendSuccess, sendPaginated, sendNoContent } = require('@lib/response');

jest.mock('@services/patient/patient.service');
jest.mock('@lib/response');
jest.mock('@config/constants', () => ({
  ...jest.requireActual('@config/constants'),
  DEFAULT_PAGE: 1,
  DEFAULT_PAGE_LIMIT: 20
}));

describe('Patient Controller', () => {
  let mockReq;
  let mockRes;

  beforeEach(() => {
    jest.clearAllMocks();
    mockReq = {
      query: {},
      params: {},
      body: {},
      user: {
        id: 'user-123',
        tenant_id: '550e8400-e29b-41d4-a716-446655440040',
        facility_id: '550e8400-e29b-41d4-a716-446655440041'
      },
      ip: '127.0.0.1'
    };
    mockRes = {
      status: jest.fn().mockReturnThis(),
      json: jest.fn().mockReturnThis()
    };
  });

  describe('listPatients', () => {
    it('should call service and send paginated response', async () => {
      const mockResult = {
        patients: [{ id: '1', first_name: 'John', last_name: 'Doe' }],
        pagination: { page: 1, limit: 20, total: 1, totalPages: 1, hasNextPage: false, hasPreviousPage: false }
      };
      patientService.listPatients.mockResolvedValue(mockResult);

      await patientController.listPatients(mockReq, mockRes);

      expect(patientService.listPatients).toHaveBeenCalled();
      expect(sendPaginated).toHaveBeenCalledWith(
        mockRes,
        'messages.patient.list.success',
        mockResult.patients,
        mockResult.pagination
      );
    });

    it('should parse query parameters correctly', async () => {
      mockReq.query = {
        page: '2',
        limit: '50',
        sort_by: 'first_name',
        order: 'asc',
        tenant_id: '123',
        gender: 'MALE',
        patient_id: 'PAT-0099',
        date_of_birth: '1990-01-01',
        contact: '0700000000',
        appointment_status: 'CONFIRMED',
        created_from: '2026-01-01',
        created_to: '2026-02-01',
        appointment_from: '2026-02-10',
        appointment_to: '2026-02-20',
        search: 'John'
      };
      patientService.listPatients.mockResolvedValue({
        patients: [],
        pagination: { page: 2, limit: 50, total: 0 }
      });

      await patientController.listPatients(mockReq, mockRes);

      expect(patientService.listPatients).toHaveBeenCalledWith(
        expect.objectContaining({
          tenant_id: '550e8400-e29b-41d4-a716-446655440040',
          facility_id: '550e8400-e29b-41d4-a716-446655440041',
          gender: 'MALE',
          patient_id: 'PAT-0099',
          date_of_birth: '1990-01-01',
          contact: '0700000000',
          appointment_status: 'CONFIRMED',
          created_from: '2026-01-01',
          created_to: '2026-02-01',
          appointment_from: '2026-02-10',
          appointment_to: '2026-02-20',
          search: 'John'
        }),
        2,
        50,
        'first_name',
        'asc',
        'user-123',
        '127.0.0.1'
      );
    });

    it('should use default page and limit when not provided', async () => {
      patientService.listPatients.mockResolvedValue({
        patients: [],
        pagination: {}
      });

      await patientController.listPatients(mockReq, mockRes);

      expect(patientService.listPatients).toHaveBeenCalledWith(
        expect.anything(),
        1,
        20,
        undefined,
        'asc',
        'user-123',
        '127.0.0.1'
      );
    });
  });

  describe('getPatientById', () => {
    it('should call service and send success response', async () => {
      mockReq.params.id = '123';
      const mockPatient = { id: '123', first_name: 'John', last_name: 'Doe' };
      patientService.getPatientById.mockResolvedValue(mockPatient);

      await patientController.getPatientById(mockReq, mockRes);

      expect(patientService.getPatientById).toHaveBeenCalledWith(
        '123',
        'user-123',
        '127.0.0.1',
        {
          tenant_id: '550e8400-e29b-41d4-a716-446655440040',
          facility_id: '550e8400-e29b-41d4-a716-446655440041'
        }
      );
      expect(sendSuccess).toHaveBeenCalledWith(mockRes, 200, 'messages.patient.get.success', mockPatient);
    });

    it('should not force tenant/facility scope for global roles', async () => {
      mockReq.params.id = 'PAT0000001';
      mockReq.query = {
        tenant_id: 'TEN0001',
        facility_id: 'FAC0001'
      };
      mockReq.user = {
        ...mockReq.user,
        role: 'PLATFORM_ADMIN'
      };
      const mockPatient = { id: 'patient-1', human_friendly_id: 'PAT0000001' };
      patientService.getPatientById.mockResolvedValue(mockPatient);

      await patientController.getPatientById(mockReq, mockRes);

      expect(patientService.getPatientById).toHaveBeenCalledWith(
        'PAT0000001',
        'user-123',
        '127.0.0.1',
        {
          tenant_id: 'TEN0001',
          facility_id: 'FAC0001'
        }
      );
    });
  });

  describe('createPatient', () => {
    it('should call service and send success response with 201 status', async () => {
      mockReq.body = {
        tenant_id: '550e8400-e29b-41d4-a716-446655440099',
        facility_id: '550e8400-e29b-41d4-a716-446655440098',
        first_name: 'John',
        last_name: 'Doe',
        date_of_birth: '1990-01-01T00:00:00.000Z',
        gender: 'MALE'
      };
      const mockPatient = {
        id: '550e8400-e29b-41d4-a716-446655440456',
        first_name: 'John',
        last_name: 'Doe'
      };
      patientService.createPatient.mockResolvedValue(mockPatient);

      await patientController.createPatient(mockReq, mockRes);

      expect(patientService.createPatient).toHaveBeenCalledWith(
        {
          ...mockReq.body,
          tenant_id: '550e8400-e29b-41d4-a716-446655440040',
          facility_id: '550e8400-e29b-41d4-a716-446655440041'
        },
        'user-123',
        '127.0.0.1',
        {
          tenant_id: '550e8400-e29b-41d4-a716-446655440040',
          facility_id: '550e8400-e29b-41d4-a716-446655440041'
        }
      );
      expect(sendSuccess).toHaveBeenCalledWith(mockRes, 201, 'messages.patient.create.success', mockPatient);
    });
  });

  describe('updatePatient', () => {
    it('should call service and send success response', async () => {
      mockReq.params.id = '123';
      mockReq.body = { first_name: 'Jane' };
      const mockPatient = { id: '123', first_name: 'Jane', last_name: 'Doe' };
      patientService.updatePatient.mockResolvedValue(mockPatient);

      await patientController.updatePatient(mockReq, mockRes);

      expect(patientService.updatePatient).toHaveBeenCalledWith(
        '123',
        mockReq.body,
        'user-123',
        '127.0.0.1',
        {
          tenant_id: '550e8400-e29b-41d4-a716-446655440040',
          facility_id: '550e8400-e29b-41d4-a716-446655440041'
        }
      );
      expect(sendSuccess).toHaveBeenCalledWith(mockRes, 200, 'messages.patient.update.success', mockPatient);
    });
  });

  describe('deletePatient', () => {
    it('should call service and send no content response', async () => {
      mockReq.params.id = '123';
      patientService.deletePatient.mockResolvedValue();

      await patientController.deletePatient(mockReq, mockRes);

      expect(patientService.deletePatient).toHaveBeenCalledWith(
        '123',
        'user-123',
        '127.0.0.1',
        {
          tenant_id: '550e8400-e29b-41d4-a716-446655440040',
          facility_id: '550e8400-e29b-41d4-a716-446655440041'
        }
      );
      expect(sendNoContent).toHaveBeenCalledWith(mockRes);
    });
  });

  describe('restorePatient', () => {
    it('should call service and send success response', async () => {
      mockReq.params.id = '123';
      const mockPatient = { id: '123', first_name: 'John' };
      patientService.restorePatient.mockResolvedValue(mockPatient);

      await patientController.restorePatient(mockReq, mockRes);

      expect(patientService.restorePatient).toHaveBeenCalledWith(
        '123',
        'user-123',
        '127.0.0.1',
        {
          tenant_id: '550e8400-e29b-41d4-a716-446655440040',
          facility_id: '550e8400-e29b-41d4-a716-446655440041'
        }
      );
      expect(sendSuccess).toHaveBeenCalledWith(
        mockRes,
        200,
        'messages.patient.restore.success',
        mockPatient
      );
    });
  });

  describe('permanentDeletePatient', () => {
    it('should call service with confirm and actor', async () => {
      mockReq.params.id = '123';
      mockReq.body = { confirm: true };
      mockReq.user.permissions = ['facility:admin', 'patient:delete'];
      patientService.permanentDeletePatient.mockResolvedValue();

      await patientController.permanentDeletePatient(mockReq, mockRes);

      expect(patientService.permanentDeletePatient).toHaveBeenCalledWith(
        '123',
        'user-123',
        '127.0.0.1',
        {
          tenant_id: '550e8400-e29b-41d4-a716-446655440040',
          facility_id: '550e8400-e29b-41d4-a716-446655440041'
        },
        {
          confirm: true,
          actor: mockReq.user
        }
      );
      expect(sendNoContent).toHaveBeenCalledWith(mockRes);
    });
  });

  describe('getPatientDeletionImpact', () => {
    it('should call service and send success response', async () => {
      mockReq.params.id = '123';
      const mockImpact = { blockers: [], counts: { by_model: {} } };
      patientService.getPatientDeletionImpact.mockResolvedValue(mockImpact);

      await patientController.getPatientDeletionImpact(mockReq, mockRes);

      expect(patientService.getPatientDeletionImpact).toHaveBeenCalled();
      expect(sendSuccess).toHaveBeenCalledWith(
        mockRes,
        200,
        'messages.patient.deletion_impact.success',
        mockImpact
      );
    });
  });
});
