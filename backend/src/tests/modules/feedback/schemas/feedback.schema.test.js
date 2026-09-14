const {
  FEEDBACK_MESSAGE_MAX_LENGTH,
  clearFeedbackSchema,
  exportFeedbackQuerySchema,
  submitFeedbackSchema
} = require('@validations/feedback/feedback.schema');

describe('feedback schemas', () => {
  it('defaults the category and trims the message', () => {
    expect(submitFeedbackSchema.parse({ message: '  Slow page  ' })).toEqual({
      category: 'GENERAL',
      message: 'Slow page'
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

  it('requires explicit confirmation to clear feedback', () => {
    expect(clearFeedbackSchema.safeParse({}).success).toBe(false);
    expect(clearFeedbackSchema.safeParse({ confirm: 'true' }).success).toBe(false);
    expect(clearFeedbackSchema.safeParse({ confirm: true }).success).toBe(true);
  });

  it('coerces and bounds the export UTC offset from the query string', () => {
    expect(exportFeedbackQuerySchema.parse({ utc_offset_minutes: '-300' })).toEqual({
      utc_offset_minutes: -300
    });
    expect(exportFeedbackQuerySchema.safeParse({ utc_offset_minutes: '900' }).success).toBe(false);
  });
});
