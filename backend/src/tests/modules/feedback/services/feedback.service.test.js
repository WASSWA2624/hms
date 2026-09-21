jest.mock('@repositories/feedback/feedback.repository', () => ({
  createFeedback: jest.fn(),
  createFeedbackEvent: jest.fn(),
  createFeedbackScreenshots: jest.fn(),
  deleteFeedbackPermanently: jest.fn(),
  findCurrentSubscriptionSnapshot: jest.fn(),
  findFacilitySnapshot: jest.fn(),
  findFeedbackScreenshot: jest.fn(),
  findFeedbackWithScreenshots: jest.fn(),
  listActiveFeedbackForExport: jest.fn(),
  listActiveFeedbackPage: jest.fn(),
  summarizeActiveFeedback: jest.fn(),
  summarizeFeedbackFacets: jest.fn()
}));
jest.mock('@lib/storage/feedback-screenshot-storage', () => ({
  deleteFeedbackScreenshotObjects: jest.fn(),
  readFeedbackScreenshot: jest.fn(),
  storeFeedbackScreenshots: jest.fn()
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
const JSZip = require('jszip');
const feedbackRepository = require('@repositories/feedback/feedback.repository');
const {
  deleteFeedbackScreenshotObjects,
  readFeedbackScreenshot,
  storeFeedbackScreenshots
} = require('@lib/storage/feedback-screenshot-storage');
const authRepository = require('@repositories/auth/auth.repository');
const { createAuditLog } = require('@lib/audit');
const { resolveTenantModuleEntitlements } = require('@lib/subscriptions/tenant-entitlements');
const { getRoleNames, resolveEffectiveAccess } = require('@lib/authorization/effective-access');
const { HttpError } = require('@lib/errors');
const {
  deleteFeedback,
  exportFeedback,
  getFeedbackFacets,
  getFeedbackScreenshotImage,
  getFeedbackSummary,
  listFeedback,
  listFeedbackScreenshots,
  submitFeedback
} = require('@services/feedback/feedback.service');

const submittedAt = new Date('2026-09-14T11:35:27.000Z');

/** A PNG's magic bytes, padded out: enough for the API to sniff the type. */
const pngBytes = (size = 64) =>
  Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    Buffer.alloc(Math.max(4, size - 8), 1)
  ]);

const uploadedFile = (buffer) => ({ buffer, mimetype: 'image/png' });

const collectStream = (stream) =>
  new Promise((resolve, reject) => {
    const chunks = [];
    stream.on('data', (chunk) => chunks.push(chunk));
    stream.on('end', () => resolve(Buffer.concat(chunks)));
    stream.on('error', reject);
  });

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
      scope: data.scope,
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
    feedbackRepository.createFeedbackScreenshots.mockImplementation(
      async (_feedbackId, rows) => rows.length
    );
    feedbackRepository.deleteFeedbackPermanently.mockResolvedValue({
      count: 0,
      storage_keys: []
    });
    storeFeedbackScreenshots.mockImplementation(async ({ screenshots = [] }) => ({
      stored: screenshots.map((screenshot, index) => ({
        ...screenshot,
        sequence: index + 1,
        storage_key: `fbshot-key-${index + 1}.jpg`
      })),
      failed: 0
    }));
    deleteFeedbackScreenshotObjects.mockResolvedValue({ deleted: 0, failed: [] });
    readFeedbackScreenshot.mockResolvedValue(pngBytes(32));
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
          scope: 'SCREEN',
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
          client_submitted_at: new Date('2026-09-14T11:35:20.000Z'),
          scope_screens: []
        })
      );
      const stored = feedbackRepository.createFeedback.mock.calls[0][0];
      expect(stored.user_email).toBeUndefined();
      expect(stored.user_roles_json).toBeUndefined();
      expect(createAuditLog).not.toHaveBeenCalled();
      expect(receipt).toEqual({
        human_friendly_id: 'FBK0000001',
        category: 'PROBLEM',
        scope: 'SCREEN',
        submitter_type: 'ANONYMOUS',
        submitted_at: submittedAt,
        screenshot_count: 0,
        screenshots_dropped: 0
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

  describe('screenshots and scope', () => {
    it('stores the pictures, records them in capture order, and reports the count', async () => {
      const receipt = await submitFeedback(
        {
          message: 'Two screens are wrong',
          screenshots: [
            { route_name: 'opd', screen_title: 'Outpatients', width: 1280, height: 800 },
            { route_name: 'pharmacy', caption: 'and here', captured_at: '2026-09-14T11:30:00.000Z' }
          ]
        },
        { user: null, files: [uploadedFile(pngBytes()), uploadedFile(pngBytes())] }
      );

      expect(storeFeedbackScreenshots).toHaveBeenCalledWith({
        feedbackId: 'feedback-1',
        screenshots: [
          expect.objectContaining({ route_name: 'opd', screen_title: 'Outpatients', width: 1280 }),
          expect.objectContaining({ route_name: 'pharmacy', caption: 'and here' })
        ]
      });
      expect(feedbackRepository.createFeedbackScreenshots).toHaveBeenCalledWith(
        'feedback-1',
        [
          expect.objectContaining({ sequence: 1, storage_key: 'fbshot-key-1.jpg' }),
          expect.objectContaining({ sequence: 2, storage_key: 'fbshot-key-2.jpg' })
        ]
      );
      expect(receipt.screenshot_count).toBe(2);
      expect(receipt.screenshots_dropped).toBe(0);
    });

    it('keeps the words when the provider refuses a picture', async () => {
      storeFeedbackScreenshots.mockResolvedValue({ stored: [], failed: 1 });

      const receipt = await submitFeedback(
        { message: 'Storage is down' },
        { user: null, files: [uploadedFile(pngBytes())] }
      );

      expect(receipt.human_friendly_id).toBe('FBK0000001');
      expect(receipt.screenshot_count).toBe(0);
      // The reporter is told what did not arrive rather than left guessing.
      expect(receipt.screenshots_dropped).toBe(1);
      expect(feedbackRepository.createFeedbackScreenshots).not.toHaveBeenCalled();
    });

    it('takes stored pictures back out when their rows cannot be written', async () => {
      feedbackRepository.createFeedbackScreenshots.mockRejectedValue(new Error('db down'));

      const receipt = await submitFeedback(
        { message: 'Orphans not allowed' },
        { user: null, files: [uploadedFile(pngBytes())] }
      );

      expect(deleteFeedbackScreenshotObjects).toHaveBeenCalledWith(['fbshot-key-1.jpg']);
      expect(receipt.screenshot_count).toBe(0);
      expect(receipt.screenshots_dropped).toBe(1);
    });

    it.each([
      [
        'more pictures than an anonymous reporter may send',
        null,
        [pngBytes(), pngBytes(), pngBytes(), pngBytes()]
      ],
      [
        'anything that is not an image',
        null,
        [Buffer.from('<?php echo "not an image"; ?>          ')]
      ]
    ])('refuses %s', async (_label, user, buffers) => {
      await expect(
        submitFeedback({ message: 'Take this' }, { user, files: buffers.map(uploadedFile) })
      ).rejects.toBeInstanceOf(HttpError);
      expect(storeFeedbackScreenshots).not.toHaveBeenCalled();
      expect(feedbackRepository.createFeedback).not.toHaveBeenCalled();
    });

    it('lets a signed-in reporter send more pictures than an anonymous one', async () => {
      const files = Array.from({ length: 10 }, () => uploadedFile(pngBytes()));

      await expect(
        submitFeedback({ message: 'Ten screens' }, { user: tokenUser, files })
      ).resolves.toEqual(expect.objectContaining({ screenshot_count: 10 }));

      await expect(
        submitFeedback({ message: 'Eleven screens' }, {
          user: tokenUser,
          files: [...files, uploadedFile(pngBytes())]
        })
      ).rejects.toBeInstanceOf(HttpError);
    });

    it('refuses a submission whose pictures are too large together', async () => {
      // Six 2 MB images clear the per-file cap but not the 12 MB request cap.
      const files = Array.from({ length: 7 }, () => uploadedFile(pngBytes(2 * 1024 * 1024)));

      await expect(
        submitFeedback({ message: 'Too much' }, { user: tokenUser, files })
      ).rejects.toBeInstanceOf(HttpError);
      expect(storeFeedbackScreenshots).not.toHaveBeenCalled();
    });

    it('records the screens a report applies to, without repeats', async () => {
      await submitFeedback(
        {
          message: 'Both queues are slow',
          scope: 'SCREENS',
          scope_screens: [
            { route_name: 'opd', route_path: '/opd', screen_title: 'Outpatients' },
            { route_name: 'opd', route_path: '/opd', screen_title: 'Outpatients' },
            { route_name: 'pharmacy', route_path: '/pharmacy?token=abc' }
          ]
        },
        { user: null }
      );

      expect(feedbackRepository.createFeedback).toHaveBeenCalledWith(
        expect.objectContaining({
          scope: 'SCREENS',
          scope_screens: [
            { route_name: 'opd', route_path: '/opd', screen_title: 'Outpatients' },
            // Credentials are scrubbed from a picked screen's path too.
            { route_name: 'pharmacy', route_path: '/pharmacy?token=redacted', screen_title: null }
          ]
        })
      );
    });

    it('keeps no screens for a report about this screen or the whole app', async () => {
      await submitFeedback(
        {
          message: 'Everywhere',
          scope: 'APP',
          scope_screens: [{ route_name: 'opd' }]
        },
        { user: null }
      );

      expect(feedbackRepository.createFeedback).toHaveBeenCalledWith(
        expect.objectContaining({ scope: 'APP', scope_screens: [] })
      );
    });
  });

  describe('reviewing screenshots', () => {
    const ownerContext = {
      user: { id: 'owner-1', roles: ['PLATFORM_ADMIN'], email: 'admin@example.com' },
      user_id: 'owner-1',
      tenant_id: 'tenant-platform',
      ip_address: '10.0.0.1'
    };

    const storedScreenshot = {
      id: '11111111-1111-4111-8111-111111111111',
      sequence: 2,
      storage_key: 'fbshot-key-2.jpg',
      content_type: 'image/jpeg',
      byte_size: 2048,
      width: 1280,
      height: 800,
      caption: null,
      route_path: '/pharmacy',
      route_name: 'pharmacy',
      screen_title: 'Pharmacy',
      captured_at: submittedAt
    };

    it('lists a record\'s screenshots with the name each takes in an archive', async () => {
      feedbackRepository.findFeedbackWithScreenshots.mockResolvedValue({
        id: 'feedback-1',
        human_friendly_id: 'FBK0000011',
        submitted_at: submittedAt,
        screenshots: [{ ...storedScreenshot, sequence: 1 }, storedScreenshot]
      });

      const result = await listFeedbackScreenshots('FBK0000011', ownerContext);

      expect(result.items.map((item) => item.file_name)).toEqual([
        'FBK0000011.jpg',
        'FBK0000011-2.jpg'
      ]);
      expect(result.items[1]).toEqual(expect.objectContaining({ screen_title: 'Pharmacy' }));
    });

    it('streams one image and audits the read', async () => {
      feedbackRepository.findFeedbackScreenshot.mockResolvedValue(storedScreenshot);
      readFeedbackScreenshot.mockResolvedValue(Buffer.from('image-bytes'));

      const result = await getFeedbackScreenshotImage(
        'fbk0000011',
        storedScreenshot.id,
        ownerContext
      );

      expect(result).toEqual({
        buffer: Buffer.from('image-bytes'),
        mime_type: 'image/jpeg',
        file_name: 'FBK0000011-2.jpg'
      });
      // These images can show patient data, so every look is evidence.
      expect(createAuditLog).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'VIEW',
          entity: 'feedback_screenshot',
          entity_id: storedScreenshot.id
        })
      );
    });

    it.each([
      ['TENANT_ADMIN'],
      ['DOCTOR']
    ])('refuses %s', async (role) => {
      const context = { user: { id: 'user-2', roles: [role] }, user_id: 'user-2' };

      await expect(listFeedbackScreenshots('FBK0000011', context)).rejects.toBeInstanceOf(
        HttpError
      );
      await expect(
        getFeedbackScreenshotImage('FBK0000011', storedScreenshot.id, context)
      ).rejects.toBeInstanceOf(HttpError);
      expect(feedbackRepository.findFeedbackWithScreenshots).not.toHaveBeenCalled();
      expect(readFeedbackScreenshot).not.toHaveBeenCalled();
    });

    it('reports a missing record and a missing image as not found', async () => {
      feedbackRepository.findFeedbackWithScreenshots.mockResolvedValue(null);
      feedbackRepository.findFeedbackScreenshot.mockResolvedValue(storedScreenshot);
      readFeedbackScreenshot.mockResolvedValue(null);

      await expect(listFeedbackScreenshots('FBK0009999', ownerContext)).rejects.toBeInstanceOf(
        HttpError
      );
      await expect(
        getFeedbackScreenshotImage('FBK0000011', storedScreenshot.id, ownerContext)
      ).rejects.toBeInstanceOf(HttpError);
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
      await expect(getFeedbackFacets({}, context)).rejects.toBeInstanceOf(HttpError);
      await expect(exportFeedback({}, context)).rejects.toBeInstanceOf(HttpError);
      await expect(
        deleteFeedback({ confirm: true, human_friendly_ids: ['FBK0000001'] }, context)
      ).rejects.toBeInstanceOf(HttpError);
      expect(feedbackRepository.listActiveFeedbackPage).not.toHaveBeenCalled();
      expect(feedbackRepository.summarizeActiveFeedback).not.toHaveBeenCalled();
      expect(feedbackRepository.summarizeFeedbackFacets).not.toHaveBeenCalled();
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
      expect(result.file_name).toMatch(/^HOSSPI-FEEDBACK-\d{8}-\d{6}\.zip$/);
      expect(result.mime_type).toBe('application/zip');
      expect(result.record_count).toBe(1);
      expect(result.image_count).toBe(0);

      const archive = await JSZip.loadAsync(await collectStream(result.stream));
      const workbookName = result.file_name.replace(/\.zip$/, '.xlsx');
      expect(Object.keys(archive.files).sort()).toEqual([
        workbookName,
        'feedback-prompts-generator.md'
      ].sort());

      const workbook = new ExcelJS.Workbook();
      await workbook.xlsx.load(await archive.file(workbookName).async('nodebuffer'));
      const sheet = workbook.getWorksheet('Feedback');
      expect(sheet.getRow(1).values).toContain('Submitted At (UTC+03:00)');
      expect(sheet.getRow(2).values).toContain('FBK0000001');

      // The generator ships as it is kept in the repository.
      const generator = await archive.file('feedback-prompts-generator.md').async('string');
      expect(generator).toContain('# Feedback prompts generator');

      expect(createAuditLog).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'EXPORT',
          entity: 'feedback',
          tenant_id: 'tenant-platform',
          user_id: 'owner-1',
          diff: {
            after: {
              record_count: 1,
              image_count: 0,
              human_friendly_ids: null,
              filters: { category: ['GENERAL'] }
            }
          }
        })
      );
    });

    it('packs every screenshot beside the workbook, named as the sheet names it', async () => {
      feedbackRepository.listActiveFeedbackForExport.mockResolvedValue([
        {
          human_friendly_id: 'FBK0000011',
          category: 'PROBLEM',
          message: 'Two screens',
          scope: 'SCREENS',
          submitter_type: 'AUTHENTICATED',
          submitted_at: submittedAt,
          scope_screens: [
            { sequence: 1, route_name: 'opd', screen_title: 'Outpatients' },
            { sequence: 2, route_name: 'pharmacy', screen_title: 'Pharmacy' }
          ],
          screenshots: [
            {
              id: 'shot-1',
              sequence: 1,
              storage_key: 'fbshot-a.jpg',
              content_type: 'image/jpeg',
              byte_size: 2048
            },
            {
              id: 'shot-2',
              sequence: 2,
              storage_key: 'fbshot-b.png',
              content_type: 'image/png',
              byte_size: 4096
            }
          ]
        }
      ]);
      readFeedbackScreenshot.mockImplementation(async (key) =>
        key === 'fbshot-a.jpg' ? Buffer.from('first-image') : Buffer.from('second-image')
      );

      const result = await exportFeedback({ utc_offset_minutes: 0 }, ownerContext);
      const archive = await JSZip.loadAsync(await collectStream(result.stream));

      expect(result.image_count).toBe(2);
      // The first shot takes the record's id; later ones are suffixed.
      expect(Object.keys(archive.files)).toEqual(
        expect.arrayContaining([
          'screenshots/FBK0000011.jpg',
          'screenshots/FBK0000011-2.png'
        ])
      );
      expect(await archive.file('screenshots/FBK0000011.jpg').async('string')).toBe('first-image');
      expect(readFeedbackScreenshot).toHaveBeenCalledWith('fbshot-a.jpg');

      const workbook = new ExcelJS.Workbook();
      await workbook.xlsx.load(
        await archive.file(result.file_name.replace(/\.zip$/, '.xlsx')).async('nodebuffer')
      );
      const feedbackSheet = workbook.getWorksheet('Feedback');
      const headers = feedbackSheet.getRow(1).values.slice(1);
      const cell = (header) =>
        feedbackSheet.getRow(2).getCell(headers.indexOf(header) + 1).value;
      expect(cell('Applies To')).toBe('Selected screens');
      expect(cell('Screens')).toBe('Outpatients, Pharmacy');
      expect(cell('Screenshots')).toBe(2);

      const imageSheet = workbook.getWorksheet('Screenshots');
      expect(imageSheet.getRow(2).getCell(1).value).toBe('FBK0000011');
      expect(imageSheet.getRow(3).getCell(1).value).toBe('FBK0000011-2');
      expect(imageSheet.getRow(3).getCell(6).value).toBe('FBK0000011-2.png');
    });

    it('leaves an unreadable image out of the archive rather than failing the download', async () => {
      feedbackRepository.listActiveFeedbackForExport.mockResolvedValue([
        {
          human_friendly_id: 'FBK0000012',
          category: 'GENERAL',
          message: 'Gone',
          scope: 'SCREEN',
          submitter_type: 'ANONYMOUS',
          submitted_at: submittedAt,
          screenshots: [
            {
              id: 'shot-1',
              sequence: 1,
              storage_key: 'missing.jpg',
              content_type: 'image/jpeg',
              byte_size: 10
            }
          ]
        }
      ]);
      readFeedbackScreenshot.mockResolvedValue(null);

      const result = await exportFeedback({ utc_offset_minutes: 0 }, ownerContext);
      const archive = await JSZip.loadAsync(await collectStream(result.stream));

      expect(Object.keys(archive.files)).not.toContain('screenshots/FBK0000012.jpg');
      expect(archive.file(result.file_name.replace(/\.zip$/, '.xlsx'))).toBeTruthy();
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
              image_count: 0,
              human_friendly_ids: ['FBK0000002'],
              filters: {}
            }
          }
        })
      );
    });

    it('permanently deletes the selected feedback and audits the ids', async () => {
      feedbackRepository.deleteFeedbackPermanently.mockResolvedValue({
        count: 2,
        storage_keys: []
      });

      const result = await deleteFeedback(
        { confirm: true, human_friendly_ids: ['fbk0000001', 'FBK0000002', 'FBK0000001'] },
        ownerContext
      );

      expect(feedbackRepository.deleteFeedbackPermanently).toHaveBeenCalledWith({
        humanFriendlyIds: ['FBK0000001', 'FBK0000002']
      });
      expect(result).toEqual({
        deleted_count: 2,
        deleted_at: expect.any(Date),
        deleted_screenshot_count: 0
      });
      expect(createAuditLog).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'DELETE',
          entity: 'feedback',
          tenant_id: 'tenant-platform',
          diff: expect.objectContaining({
            before: {
              human_friendly_ids: ['FBK0000001', 'FBK0000002'],
              filters: null,
              matched: 2,
              images: 0
            }
          })
        })
      );
    });

    it('permanently deletes every record matching the filters when asked to', async () => {
      feedbackRepository.deleteFeedbackPermanently.mockResolvedValue({
        count: 17,
        storage_keys: []
      });
      const filters = { category: ['PROBLEM'], from: '2026-09-01T00:00:00.000Z' };

      const result = await deleteFeedback({ confirm: true, all_matching: true, filters }, ownerContext);

      expect(feedbackRepository.deleteFeedbackPermanently).toHaveBeenCalledWith({ filters });
      expect(result.deleted_count).toBe(17);
    });

    it('returns filter values with counts for platform admins', async () => {
      const facets = {
        total: 2,
        facets: { tenant_id: [{ value: 'TEN0000001', label: 'IHK Group', count: 2 }] }
      };
      feedbackRepository.summarizeFeedbackFacets.mockResolvedValue(facets);
      const filters = { route_name: ['hr'], breakpoint: ['xl'] };

      await expect(getFeedbackFacets(filters, ownerContext)).resolves.toEqual(facets);
      expect(feedbackRepository.summarizeFeedbackFacets).toHaveBeenCalledWith(filters);
    });

    it('exports and deletes with the same new filters it was given', async () => {
      const filters = { tenant_id: ['TEN0000001'], route_name: ['hr'], breakpoint: ['xl'] };
      feedbackRepository.listActiveFeedbackForExport.mockResolvedValue([]);
      feedbackRepository.deleteFeedbackPermanently.mockResolvedValue({
        count: 0,
        storage_keys: []
      });

      await exportFeedback({ ...filters, utc_offset_minutes: 180 }, ownerContext);
      await deleteFeedback({ confirm: true, all_matching: true, filters }, ownerContext);

      expect(feedbackRepository.listActiveFeedbackForExport).toHaveBeenCalledWith(filters, {
        humanFriendlyIds: null
      });
      expect(feedbackRepository.deleteFeedbackPermanently).toHaveBeenCalledWith({ filters });
    });

    it('deletes the images of every record it removes', async () => {
      feedbackRepository.deleteFeedbackPermanently.mockResolvedValue({
        count: 2,
        storage_keys: ['fbshot-a.jpg', 'fbshot-b.jpg']
      });
      deleteFeedbackScreenshotObjects.mockResolvedValue({ deleted: 2, failed: [] });

      const result = await deleteFeedback(
        { confirm: true, all_matching: true, filters: { category: ['PROBLEM'] } },
        ownerContext
      );

      expect(deleteFeedbackScreenshotObjects).toHaveBeenCalledWith([
        'fbshot-a.jpg',
        'fbshot-b.jpg'
      ]);
      expect(result.deleted_count).toBe(2);
      expect(result.deleted_screenshot_count).toBe(2);
      expect(createAuditLog).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'DELETE',
          diff: expect.objectContaining({
            after: expect.objectContaining({ deleted_images: 2, orphaned_images: 0 })
          })
        })
      );
    });

    it('records the images it could not delete as orphans', async () => {
      feedbackRepository.deleteFeedbackPermanently.mockResolvedValue({
        count: 1,
        storage_keys: ['fbshot-a.jpg']
      });
      deleteFeedbackScreenshotObjects.mockResolvedValue({ deleted: 0, failed: ['fbshot-a.jpg'] });

      const result = await deleteFeedback(
        { confirm: true, human_friendly_ids: ['FBK0000011'] },
        ownerContext
      );

      // The records are still gone; the audit says an image outlived them.
      expect(result.deleted_count).toBe(1);
      expect(createAuditLog).toHaveBeenCalledWith(
        expect.objectContaining({
          diff: expect.objectContaining({
            after: expect.objectContaining({ orphaned_images: 1 })
          })
        })
      );
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
