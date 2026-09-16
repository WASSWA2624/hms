jest.mock('@repositories/feedback/feedback.repository', () => ({
  createFeedback: jest.fn(),
  createFeedbackEvent: jest.fn(),
  deleteFeedbackPermanently: jest.fn(),
  findCurrentSubscriptionSnapshot: jest.fn(),
  findFacilitySnapshot: jest.fn(),
  listActiveFeedbackForExport: jest.fn(),
  listActiveFeedbackPage: jest.fn(),
  summarizeActiveFeedback: jest.fn()
}));
jest.mock('@repositories/auth/auth.repository', () => ({
  findUserById: jest.fn()
}));
jest.mock('@lib/audit', () => ({
  createAuditLog: jest.fn().mockResolvedValue(undefined)
}));
jest.mock('@lib/subscriptions/tenant-entitlements', () => ({
  resolveTenantModuleEntitlements: jest.fn()
}));
jest.mock('@lib/authorization/effective-access', () => ({
  getRoleNames: jest.fn(),
  resolveEffectiveAccess: jest.fn()
}));

const ExcelJS = require('exceljs');
const feedbackRepository = require('@repositories/feedback/feedback.repository');
const authRepository = require('@repositories/auth/auth.repository');
const { createAuditLog } = require('@lib/audit');
const { resolveTenantModuleEntitlements } = require('@lib/subscriptions/tenant-entitlements');
const { getRoleNames, resolveEffectiveAccess } = require('@lib/authorization/effective-access');
const { HttpError } = require('@lib/errors');
const {
  deleteFeedback,
  exportFeedback,
  getFeedbackSummary,
  listFeedback,
  submitFeedback
} = require('@services/feedback/feedback.service');

const submittedAt = new Date('2026-09-14T11:35:27.000Z');

const buildLiveUser = (overrides = {}) => ({
  id: 'user-1',
  human_friendly_id: 'USR0000007',
  email: 'nurse@example.com',
  position_title: 'Charge nurse',
  status: 'ACTIVE',
  tenant_id: 'tenant-1',
  facility_id: 'facility-home',
  profile: { first_name: 'Amina', middle_name: null, last_name: 'Nakato' },
  tenant: { id: 'tenant-1', human_friendly_id: 'TEN0000001', name: 'IHK Group' },
  roles: [],
  ...overrides
});

const tokenUser = {
  id: 'user-1',
  tenant_id: 'tenant-1',
  facility_id: 'facility-2',
  roles: ['NURSE'],
  permissions: ['patient:read']
};

describe('feedback service', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    createAuditLog.mockResolvedValue(undefined);
    feedbackRepository.createFeedback.mockImplementation(async (data) => ({
      id: 'feedback-1',
      human_friendly_id: 'FBK0000001',
      category: data.category,
      submitter_type: data.submitter_type,
      tenant_id: data.tenant_id,
      submitted_at: submittedAt
    }));
    feedbackRepository.findFacilitySnapshot.mockResolvedValue({
      id: 'facility-2',
      human_friendly_id: 'FAC0000002',
      name: 'IHK Kampala',
      tenant_id: 'tenant-1'
    });
    feedbackRepository.findCurrentSubscriptionSnapshot.mockResolvedValue({
      status: 'ACTIVE',
      plan: { code: 'ADVANCED', name: 'Advanced', tier_code: 'ADVANCED' }
    });
    authRepository.findUserById.mockResolvedValue(buildLiveUser());
    getRoleNames.mockReturnValue(['NURSE', 'NURSE']);
    resolveTenantModuleEntitlements.mockResolvedValue([{ code: 'nursing' }]);
    resolveEffectiveAccess.mockReturnValue({
      permissions: ['patient:write', 'nursing:read', 'patient:write']
    });
  });

  describe('submitFeedback', () => {
    it('records anonymous feedback with scrubbed page context when nobody is signed in', async () => {
      const receipt = await submitFeedback(
        {
          category: 'PROBLEM',
          message: 'Login page froze',
          context: {
            route_path: '/reset-password?token=abc&email=a%40b.com',
            route_name: 'resetPassword',
            page_url: 'https://app.example.com/reset-password?token=abc',
            platform: 'web',
            viewport: { width: 390, height: 844 },
            client_submitted_at: '2026-09-14T11:35:20.000Z'
          }
        },
        {
          user: null,
          ip_address: '10.0.0.5',
          user_agent: 'Mozilla/5.0',
          locale: 'en',
          timezone: 'Africa/Kampala'
        }
      );

      expect(authRepository.findUserById).not.toHaveBeenCalled();
      expect(feedbackRepository.createFeedback).toHaveBeenCalledWith(
        expect.objectContaining({
          category: 'PROBLEM',
          message: 'Login page froze',
          submitter_type: 'ANONYMOUS',
          user_id: null,
          tenant_id: null,
          facility_id: null,
          route_path: '/reset-password?token=redacted&email=redacted',
          route_name: 'resetPassword',
          page_url: 'https://app.example.com/reset-password?token=redacted',
          client_platform: 'web',
          locale: 'en',
          timezone: 'Africa/Kampala',
          user_agent: 'Mozilla/5.0',
          ip_address: '10.0.0.5',
          device_type: 'MOBILE',
          viewport_width: 390,
          viewport_height: 844,
          screen_width: null,
          screen_height: null,
          client_context_json: null,
          client_submitted_at: new Date('2026-09-14T11:35:20.000Z')
        })
      );
      const stored = feedbackRepository.createFeedback.mock.calls[0][0];
      expect(stored.user_email).toBeUndefined();
      expect(stored.user_roles_json).toBeUndefined();
      expect(createAuditLog).not.toHaveBeenCalled();
      expect(receipt).toEqual({
        human_friendly_id: 'FBK0000001',
        category: 'PROBLEM',
        submitter_type: 'ANONYMOUS',
        submitted_at: submittedAt
      });
    });

    it('snapshots live identity, tenant, facility, subscription, and access for signed-in users', async () => {
      await submitFeedback({ message: 'Great update' }, { user: tokenUser, ip_address: '10.0.0.9' });

      expect(authRepository.findUserById).toHaveBeenCalledWith('user-1');
      expect(feedbackRepository.findFacilitySnapshot).toHaveBeenCalledWith('facility-2');
      expect(feedbackRepository.findCurrentSubscriptionSnapshot).toHaveBeenCalledWith('tenant-1');
      expect(resolveEffectiveAccess).toHaveBeenCalledWith(
        expect.objectContaining({ id: 'user-1', tenant_id: 'tenant-1', facility_id: 'facility-2' }),
        expect.objectContaining({ moduleEntitlements: [{ code: 'nursing' }], applyPlanGate: true })
      );
      expect(feedbackRepository.createFeedback).toHaveBeenCalledWith(
        expect.objectContaining({
          category: 'GENERAL',
          submitter_type: 'AUTHENTICATED',
          user_id: 'user-1',
          tenant_id: 'tenant-1',
          facility_id: 'facility-2',
          user_human_friendly_id: 'USR0000007',
          user_email: 'nurse@example.com',
          user_name: 'Amina Nakato',
          user_position_title: 'Charge nurse',
          user_roles_json: ['NURSE'],
          user_permissions_json: ['nursing:read', 'patient:write'],
          tenant_human_friendly_id: 'TEN0000001',
          tenant_name: 'IHK Group',
          facility_human_friendly_id: 'FAC0000002',
          facility_name: 'IHK Kampala',
          subscription_plan_code: 'ADVANCED',
          subscription_plan_name: 'Advanced',
          subscription_tier_code: 'ADVANCED',
          subscription_status: 'ACTIVE'
        })
      );
      expect(createAuditLog).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'CREATE',
          entity: 'feedback',
          entity_id: 'feedback-1',
          tenant_id: 'tenant-1',
          user_id: 'user-1'
        })
      );
    });

    it('records a token whose user cannot be found as anonymous', async () => {
      authRepository.findUserById.mockResolvedValue(null);

      await submitFeedback({ message: 'Still here' }, { user: tokenUser });

      expect(feedbackRepository.createFeedback).toHaveBeenCalledWith(
        expect.objectContaining({ submitter_type: 'ANONYMOUS', user_id: null, tenant_id: null })
      );
      expect(feedbackRepository.findFacilitySnapshot).not.toHaveBeenCalled();
    });

    it('never attributes a facility that belongs to another tenant', async () => {
      feedbackRepository.findFacilitySnapshot.mockResolvedValue({
        id: 'facility-9',
        human_friendly_id: 'FAC0000009',
        name: 'Other Hospital',
        tenant_id: 'tenant-9'
      });

      await submitFeedback({ message: 'Wrong facility?' }, { user: { ...tokenUser, facility_id: 'facility-9' } });

      expect(feedbackRepository.createFeedback).toHaveBeenCalledWith(
        expect.objectContaining({ facility_id: null, facility_name: null, tenant_id: 'tenant-1' })
      );
    });

    it('keeps the submission when context lookups fail', async () => {
      resolveTenantModuleEntitlements.mockRejectedValue(new Error('entitlements offline'));
      feedbackRepository.findCurrentSubscriptionSnapshot.mockRejectedValue(new Error('db timeout'));

      await submitFeedback({ message: 'Partial context' }, { user: tokenUser });

      expect(feedbackRepository.createFeedback).toHaveBeenCalledWith(
        expect.objectContaining({
          submitter_type: 'AUTHENTICATED',
          user_roles_json: ['NURSE'],
          user_permissions_json: ['patient:read'],
          subscription_plan_name: null
        })
      );
    });

    it('stores the reported screen size class with whole-pixel sizes', async () => {
      await submitFeedback(
        {
          message: 'Table overflows',
          context: {
            device_type: 'TABLET',
            viewport: { width: 1180.4, height: 820.6, device_pixel_ratio: 2 },
            screen: { width: 1366, height: 1024 },
            orientation: 'landscape'
          }
        },
        { user: null }
      );

      expect(feedbackRepository.createFeedback).toHaveBeenCalledWith(
        expect.objectContaining({
          device_type: 'TABLET',
          viewport_width: 1180,
          viewport_height: 821,
          screen_width: 1366,
          screen_height: 1024,
          client_context_json: { orientation: 'landscape', device_pixel_ratio: 2 }
        })
      );
    });
  });

  describe('feedback administration', () => {
    const ownerContext = {
      user: { id: 'owner-1', roles: ['PLATFORM_OWNER'], email: 'owner@example.com' },
      user_id: 'owner-1',
      tenant_id: 'tenant-platform',
      ip_address: '10.0.0.1'
    };

    it.each([
      ['TENANT_ADMIN'],
      ['FACILITY_ADMIN'],
      ['DOCTOR']
    ])('rejects %s for every management action', async (role) => {
      const context = { user: { id: 'user-2', roles: [role] }, user_id: 'user-2' };

      await expect(listFeedback({}, context)).rejects.toBeInstanceOf(HttpError);
      await expect(getFeedbackSummary({}, context)).rejects.toBeInstanceOf(HttpError);
      await expect(exportFeedback({}, context)).rejects.toBeInstanceOf(HttpError);
      await expect(
        deleteFeedback({ confirm: true, human_friendly_ids: ['FBK0000001'] }, context)
      ).rejects.toBeInstanceOf(HttpError);
      expect(feedbackRepository.listActiveFeedbackPage).not.toHaveBeenCalled();
      expect(feedbackRepository.summarizeActiveFeedback).not.toHaveBeenCalled();
      expect(feedbackRepository.listActiveFeedbackForExport).not.toHaveBeenCalled();
      expect(feedbackRepository.deleteFeedbackPermanently).not.toHaveBeenCalled();
    });

    it('lists a page newest first with short message previews', async () => {
      feedbackRepository.listActiveFeedbackPage.mockResolvedValue({
        rows: [
          {
            human_friendly_id: 'FBK0000003',
            category: 'PROBLEM',
            message: 'x'.repeat(400),
            submitter_type: 'ANONYMOUS',
            user_email: null,
            submitted_at: submittedAt,
            device_type: 'MOBILE',
            client_platform: 'web'
          }
        ],
        total: 45
      });

      const result = await listFeedback(
        { page: 2, limit: 20, category: ['PROBLEM'], search: 'print' },
        ownerContext
      );

      expect(feedbackRepository.listActiveFeedbackPage).toHaveBeenCalledWith({
        filters: { category: ['PROBLEM'], search: 'print' },
        skip: 20,
        take: 20,
        orderBy: [{ submitted_at: 'desc' }, { id: 'desc' }]
      });
      expect(result.pagination).toEqual({
        page: 2,
        limit: 20,
        total: 45,
        totalPages: 3,
        hasNextPage: true,
        hasPreviousPage: true
      });
      expect(result.items[0]).toEqual(
        expect.objectContaining({
          human_friendly_id: 'FBK0000003',
          submitter_type: 'ANONYMOUS',
          device_type: 'MOBILE',
          client_platform: 'web'
        })
      );
      expect(result.items[0].message_preview).toHaveLength(280);
      expect(result.items[0]).not.toHaveProperty('message');
    });

    it('sorts by an allowed column with submission time and id as tie-breakers', async () => {
      feedbackRepository.listActiveFeedbackPage.mockResolvedValue({ rows: [], total: 0 });

      await listFeedback({ sort_by: 'tenant_name', order: 'asc' }, ownerContext);

      expect(feedbackRepository.listActiveFeedbackPage).toHaveBeenCalledWith(
        expect.objectContaining({
          skip: 0,
          take: 20,
          orderBy: [{ tenant_name: 'asc' }, { submitted_at: 'desc' }, { id: 'desc' }]
        })
      );
    });

    it('summarizes active feedback for platform admins', async () => {
      feedbackRepository.summarizeActiveFeedback.mockResolvedValue({
        total: 5,
        anonymous: 2,
        latest_submitted_at: submittedAt
      });

      const summary = await getFeedbackSummary(
        { category: ['PROBLEM'] },
        { user: { id: 'admin-1', roles: ['PLATFORM_ADMIN'] } }
      );

      expect(feedbackRepository.summarizeActiveFeedback).toHaveBeenCalledWith({ category: ['PROBLEM'] });
      expect(summary).toEqual({
        total: 5,
        authenticated: 3,
        anonymous: 2,
        latest_submitted_at: submittedAt
      });
    });

    it('exports a named workbook and audits the download', async () => {
      feedbackRepository.listActiveFeedbackForExport.mockResolvedValue([
        {
          human_friendly_id: 'FBK0000001',
          category: 'GENERAL',
          message: 'Hello',
          submitter_type: 'ANONYMOUS',
          submitted_at: submittedAt
        }
      ]);

      const result = await exportFeedback(
        { category: ['GENERAL'], utc_offset_minutes: 180 },
        ownerContext
      );

      expect(feedbackRepository.listActiveFeedbackForExport).toHaveBeenCalledWith(
        { category: ['GENERAL'] },
        { humanFriendlyIds: null }
      );
      expect(result.file_name).toMatch(/^HOSSPI-FEEDBACK-\d{8}-\d{6}\.xlsx$/);
      expect(result.mime_type).toBe(
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
      );
      expect(result.record_count).toBe(1);

      const workbook = new ExcelJS.Workbook();
      await workbook.xlsx.load(result.buffer);
      const sheet = workbook.getWorksheet('Feedback');
      expect(sheet.getRow(1).values).toContain('Submitted At (UTC+03:00)');
      expect(sheet.getRow(2).values).toContain('FBK0000001');

      expect(createAuditLog).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'EXPORT',
          entity: 'feedback',
          tenant_id: 'tenant-platform',
          user_id: 'owner-1',
          diff: {
            after: {
              record_count: 1,
              human_friendly_ids: null,
              filters: { category: ['GENERAL'] }
            }
          }
        })
      );
    });

    it('exports exactly the picked records when ids are supplied', async () => {
      feedbackRepository.listActiveFeedbackForExport.mockResolvedValue([
        {
          human_friendly_id: 'FBK0000002',
          category: 'PROBLEM',
          message: 'Printer jam',
          submitter_type: 'AUTHENTICATED',
          submitted_at: submittedAt
        }
      ]);

      const result = await exportFeedback(
        { human_friendly_ids: ['fbk0000002', 'FBK0000002', ' '], utc_offset_minutes: 0 },
        ownerContext
      );

      expect(feedbackRepository.listActiveFeedbackForExport).toHaveBeenCalledWith(
        {},
        { humanFriendlyIds: ['FBK0000002'] }
      );
      expect(result.record_count).toBe(1);
      expect(createAuditLog).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'EXPORT',
          diff: {
            after: {
              record_count: 1,
              human_friendly_ids: ['FBK0000002'],
              filters: {}
            }
          }
        })
      );
    });

    it('permanently deletes the selected feedback and audits the ids', async () => {
      feedbackRepository.deleteFeedbackPermanently.mockResolvedValue(2);

      const result = await deleteFeedback(
        { confirm: true, human_friendly_ids: ['fbk0000001', 'FBK0000002', 'FBK0000001'] },
        ownerContext
      );

      expect(feedbackRepository.deleteFeedbackPermanently).toHaveBeenCalledWith({
        humanFriendlyIds: ['FBK0000001', 'FBK0000002']
      });
      expect(result).toEqual({ deleted_count: 2, deleted_at: expect.any(Date) });
      expect(createAuditLog).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'DELETE',
          entity: 'feedback',
          tenant_id: 'tenant-platform',
          diff: expect.objectContaining({
            before: {
              human_friendly_ids: ['FBK0000001', 'FBK0000002'],
              filters: null,
              matched: 2
            }
          })
        })
      );
    });

    it('permanently deletes every record matching the filters when asked to', async () => {
      feedbackRepository.deleteFeedbackPermanently.mockResolvedValue(17);
      const filters = { category: ['PROBLEM'], from: '2026-09-01T00:00:00.000Z' };

      const result = await deleteFeedback({ confirm: true, all_matching: true, filters }, ownerContext);

      expect(feedbackRepository.deleteFeedbackPermanently).toHaveBeenCalledWith({ filters });
      expect(result.deleted_count).toBe(17);
    });

    it('refuses a deletion without a target', async () => {
      await expect(deleteFeedback({ confirm: true }, ownerContext)).rejects.toBeInstanceOf(HttpError);
      await expect(
        deleteFeedback({ confirm: true, human_friendly_ids: ['  '] }, ownerContext)
      ).rejects.toBeInstanceOf(HttpError);
      expect(feedbackRepository.deleteFeedbackPermanently).not.toHaveBeenCalled();
    });
  });
});
