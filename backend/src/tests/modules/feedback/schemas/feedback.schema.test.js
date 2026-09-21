const {
  FEEDBACK_FILTER_MAX_VALUES,
  FEEDBACK_MESSAGE_MAX_LENGTH,
  deleteFeedbackSchema,
  exportFeedbackBodySchema,
  exportFeedbackQuerySchema,
  feedbackFilterQuerySchema,
  listFeedbackQuerySchema,
  submitFeedbackSchema
} = require('@validations/feedback/feedback.schema');

describe('feedback schemas', () => {
  it('defaults the category and trims the message', () => {
    expect(submitFeedbackSchema.parse({ message: '  Slow page  ' })).toEqual({
      category: 'GENERAL',
      message: 'Slow page',
      // Feedback is about the screen it was raised from unless it says so.
      scope: 'SCREEN'
    });
  });

  it('rejects blank, oversized, and unknown-category feedback', () => {
    expect(submitFeedbackSchema.safeParse({ message: '  ' }).success).toBe(false);
    expect(
      submitFeedbackSchema.safeParse({ message: 'x'.repeat(FEEDBACK_MESSAGE_MAX_LENGTH + 1) }).success
    ).toBe(false);
    expect(
      submitFeedbackSchema.safeParse({ message: 'Valid text', category: 'PRAISE' }).success
    ).toBe(false);
    expect(
      submitFeedbackSchema.safeParse({ message: 'Valid text', context: { device_type: 'WATCH' } })
        .success
    ).toBe(false);
  });

  it('accepts client context with a UTC device time and viewport', () => {
    const parsed = submitFeedbackSchema.parse({
      category: 'PROBLEM',
      message: 'Cannot save vitals',
      context: {
        route_path: '/opd?tab=queue',
        route_name: 'opd',
        platform: 'web',
        device_type: 'MOBILE',
        orientation: 'portrait',
        screen: { width: 390, height: 844 },
        utc_offset_minutes: 180,
        viewport: { width: 1280, height: 800, device_pixel_ratio: 2 },
        client_submitted_at: '2026-09-14T11:35:27.123Z'
      }
    });

    expect(parsed.category).toBe('PROBLEM');
    expect(parsed.context.viewport).toEqual({ width: 1280, height: 800, device_pixel_ratio: 2 });
    expect(parsed.context.device_type).toBe('MOBILE');
    expect(parsed.context.screen).toEqual({ width: 390, height: 844 });
  });

  it('accepts comma lists or arrays for multi-value list filters', () => {
    expect(
      listFeedbackQuerySchema.parse({
        category: 'problem, COMPLAINT,problem',
        device_type: ['mobile'],
        platform: 'Web,ANDROID',
        submitter_type: 'ANONYMOUS',
        from: '2026-09-01T00:00:00.000Z',
        to: '2026-09-14T23:59:59.999+03:00',
        page: '2',
        limit: '50',
        sort_by: 'tenant_name',
        order: 'asc'
      })
    ).toEqual({
      category: ['PROBLEM', 'COMPLAINT'],
      device_type: ['MOBILE'],
      platform: ['web', 'android'],
      submitter_type: 'ANONYMOUS',
      from: '2026-09-01T00:00:00.000Z',
      to: '2026-09-14T23:59:59.999+03:00',
      page: 2,
      limit: 50,
      sort_by: 'tenant_name',
      order: 'asc'
    });
  });

  it('normalizes every who, where, and device filter the workbook carries', () => {
    expect(
      feedbackFilterQuerySchema.parse({
        tenant_id: 'ten-9322e26afd, TEN0000002',
        facility_id: ['fac-fbb67a688f'],
        role: 'platform_admin,NURSE',
        plan_tier: 'pro',
        subscription_status: 'active,Trial',
        route_name: 'tenantFacilitySetup,hr',
        app_environment: 'Production',
        app_version: '1.4.0+12',
        locale: 'en-GB,en',
        breakpoint: 'XL,sm',
        theme: 'Dark',
        connectivity: 'online',
        orientation: 'LANDSCAPE'
      })
    ).toEqual({
      tenant_id: ['TEN-9322E26AFD', 'TEN0000002'],
      facility_id: ['FAC-FBB67A688F'],
      role: ['PLATFORM_ADMIN', 'NURSE'],
      plan_tier: ['PRO'],
      subscription_status: ['ACTIVE', 'TRIAL'],
      route_name: ['tenantFacilitySetup', 'hr'],
      app_environment: ['production'],
      app_version: ['1.4.0+12'],
      locale: ['en-GB', 'en'],
      breakpoint: ['xl', 'sm'],
      theme: ['dark'],
      connectivity: ['online'],
      orientation: ['landscape']
    });
  });

  it('rejects unknown filter keys everywhere the filters are shared', () => {
    expect(feedbackFilterQuerySchema.safeParse({ tenant: 'TEN0000001' }).success).toBe(false);
    expect(listFeedbackQuerySchema.safeParse({ has_user: 'true' }).success).toBe(false);
    expect(exportFeedbackQuerySchema.safeParse({ screen: 'hr' }).success).toBe(false);
    expect(exportFeedbackBodySchema.safeParse({ breakpoints: ['xl'] }).success).toBe(false);
    expect(
      deleteFeedbackSchema.safeParse({
        confirm: true,
        all_matching: true,
        filters: { theme_mode: ['dark'] }
      }).success
    ).toBe(false);
    expect(
      deleteFeedbackSchema.safeParse({
        confirm: true,
        all_matching: true,
        filters: { tenant_id: ['TEN0000001'], breakpoint: ['xl'], route_name: ['hr'] }
      }).success
    ).toBe(true);
  });

  it('bounds how many values one filter takes', () => {
    const tooMany = Array.from({ length: FEEDBACK_FILTER_MAX_VALUES + 1 }, (_, index) => `v${index}`);
    expect(feedbackFilterQuerySchema.safeParse({ app_version: tooMany }).success).toBe(false);
    expect(feedbackFilterQuerySchema.safeParse({ role: 'x'.repeat(81) }).success).toBe(false);
  });

  it('rejects unknown filter values, oversized pages, and unsortable columns', () => {
    expect(listFeedbackQuerySchema.safeParse({ category: 'PRAISE' }).success).toBe(false);
    expect(listFeedbackQuerySchema.safeParse({ device_type: 'WATCH' }).success).toBe(false);
    expect(listFeedbackQuerySchema.safeParse({ limit: '500' }).success).toBe(false);
    expect(listFeedbackQuerySchema.safeParse({ sort_by: 'message' }).success).toBe(false);
  });

  it('requires confirmation and exactly one deletion target', () => {
    expect(
      deleteFeedbackSchema.safeParse({ confirm: true, human_friendly_ids: ['FBK0000001'] }).success
    ).toBe(true);
    expect(
      deleteFeedbackSchema.safeParse({
        confirm: true,
        all_matching: true,
        filters: { category: ['PROBLEM'], from: '2026-09-01T00:00:00.000Z' }
      }).success
    ).toBe(true);
    expect(deleteFeedbackSchema.safeParse({ human_friendly_ids: ['FBK0000001'] }).success).toBe(false);
    expect(deleteFeedbackSchema.safeParse({ confirm: true }).success).toBe(false);
    expect(deleteFeedbackSchema.safeParse({ confirm: true, human_friendly_ids: [] }).success).toBe(false);
    expect(
      deleteFeedbackSchema.safeParse({
        confirm: true,
        human_friendly_ids: ['FBK0000001'],
        all_matching: true
      }).success
    ).toBe(false);
  });

  it('coerces and bounds the export UTC offset from the query string', () => {
    expect(exportFeedbackQuerySchema.parse({ utc_offset_minutes: '-300' })).toEqual({
      utc_offset_minutes: -300
    });
    expect(exportFeedbackQuerySchema.safeParse({ utc_offset_minutes: '900' }).success).toBe(false);
  });
});
