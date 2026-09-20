/**
 * Follow-up controller tests
 *
 * @module tests/modules/follow-up/controllers
 * Per testing.mdc: Test request handlers with mocked services
 */

// Mock dependencies
jest.mock('@services/follow-up/follow-up.service');
jest.mock('@lib/response');

const followUpService = require('@services/follow-up/follow-up.service');
const { sendSuccess, sendPaginated, sendNoContent } = require('@lib/response');
const {
  listFollowUps,
  getFollowUpById,
  createFollowUp,
  updateFollowUp,
  deleteFollowUp
} = require('@controllers/follow-up/follow-up.controller');

describe('Follow-up Controller', () => {
  let req, res;

  beforeEach(() => {
    jest.clearAllMocks();
    req = {
      query: {},
      params: {},
      body: {},
      user: { id: 'user-1', tenant_id: 'tenant-1', roles: ['TENANT_ADMIN'] },
      ip: '127.0.0.1'
    };
    res = {};
  });

  describe('listFollowUps', () => {
    it('should list follow-ups', async () => {
      const mockResult = {
        followUps: [{ id: 'fu-1' }],
        pagination: { page: 1, limit: 20, total: 1 }
      };
      followUpService.listFollowUps.mockResolvedValue(mockResult);

      await listFollowUps(req, res);

      expect(followUpService.listFollowUps).toHaveBeenCalledWith(
        expect.objectContaining({
          tenant_id: 'tenant-1',
          is_elevated: false,
        }),
        1,
        20,
        undefined,
        'asc',
        'user-1',
        '127.0.0.1'
      );
      expect(sendPaginated).toHaveBeenCalledWith(
        res,
        'messages.follow_up.list.success',
        mockResult.followUps,
        mockResult.pagination
      );
    });
  });

  describe('getFollowUpById', () => {
    it('should get follow-up by ID', async () => {
      req.params.id = 'fu-1';
      const mockFollowUp = { id: 'fu-1' };
      followUpService.getFollowUpById.mockResolvedValue(mockFollowUp);

      await getFollowUpById(req, res);

      expect(sendSuccess).toHaveBeenCalledWith(
        res,
        200,
        'messages.follow_up.get.success',
        mockFollowUp
      );
    });
  });

  describe('createFollowUp', () => {
    it('should create follow-up', async () => {
      req.body = { encounter_id: 'enc-1', scheduled_at: '2026-01-25' };
      const mockFollowUp = { id: 'fu-1', ...req.body };
      followUpService.createFollowUp.mockResolvedValue(mockFollowUp);

      await createFollowUp(req, res);

      expect(sendSuccess).toHaveBeenCalledWith(
        res,
        201,
        'messages.follow_up.create.success',
        mockFollowUp
      );
    });
  });

  describe('updateFollowUp', () => {
    it('should update follow-up', async () => {
      req.params.id = 'fu-1';
      req.body = { notes: 'Updated notes' };
      const mockFollowUp = { id: 'fu-1', ...req.body };
      followUpService.updateFollowUp.mockResolvedValue(mockFollowUp);

      await updateFollowUp(req, res);

      expect(sendSuccess).toHaveBeenCalledWith(
        res,
        200,
        'messages.follow_up.update.success',
        mockFollowUp
      );
    });
  });

  describe('deleteFollowUp', () => {
    it('should delete follow-up', async () => {
      req.params.id = 'fu-1';
      followUpService.deleteFollowUp.mockResolvedValue();

      await deleteFollowUp(req, res);

      expect(sendNoContent).toHaveBeenCalledWith(res);
    });
  });
});
