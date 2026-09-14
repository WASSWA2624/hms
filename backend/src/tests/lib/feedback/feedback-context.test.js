const {
  REDACTED_VALUE,
  buildFeedbackClientContextJson,
  isSensitiveParam,
  resolveFeedbackDeviceType,
  sanitizeFeedbackLocation,
  toFeedbackPixelCount,
  truncateFeedbackText
} = require('@lib/feedback/feedback-context');

describe('feedback context sanitising', () => {
  it('redacts credentials and personal data from route queries', () => {
    expect(
      sanitizeFeedbackLocation('/reset-password?token=abc123&email=jane%40example.com&tab=security', 512)
    ).toBe(`/reset-password?token=${REDACTED_VALUE}&email=${REDACTED_VALUE}&tab=security`);
  });

  it('scrubs queries carried inside a hash-strategy fragment', () => {
    expect(
      sanitizeFeedbackLocation('https://app.hosspi.com/#/verify-email?token=abc&reason=expired', 2048)
    ).toBe(`https://app.hosspi.com/#/verify-email?token=${REDACTED_VALUE}&reason=expired`);
  });

  it('drops user-info from absolute URLs', () => {
    expect(
      sanitizeFeedbackLocation('https://user:secret@app.hosspi.com/home?view=list', 2048)
    ).toBe('https://app.hosspi.com/home?view=list');
  });

  it('scrubs redirect locations nested in the query', () => {
    const value = sanitizeFeedbackLocation('/login?from=%2Freset-password%3Ftoken%3Dabc', 512);
    const nested = new URL(value, 'http://feedback.test').searchParams.get('from');

    expect(nested).toBe(`/reset-password?token=${REDACTED_VALUE}`);
  });

  it('matches parameter words rather than substrings', () => {
    expect(isSensitiveParam('resetToken')).toBe(true);
    expect(isSensitiveParam('api_key')).toBe(true);
    expect(isSensitiveParam('email')).toBe(true);
    expect(isSensitiveParam('shipping')).toBe(false);
    expect(isSensitiveParam('author')).toBe(false);
    expect(isSensitiveParam('tab')).toBe(false);
  });

  it('caps stored length and blanks empty values', () => {
    expect(sanitizeFeedbackLocation('   ', 512)).toBeNull();
    expect(sanitizeFeedbackLocation(`/${'a'.repeat(600)}`, 512)).toHaveLength(512);
    expect(truncateFeedbackText('  hello  ', 3)).toBe('hel');
    expect(truncateFeedbackText(undefined, 3)).toBeNull();
  });

  it('keeps only recognised display and device context', () => {
    expect(
      buildFeedbackClientContextJson({
        breakpoint: 'md',
        theme_mode: 'dark',
        connectivity: 'online',
        session_status: 'authenticated',
        text_scale: 1.2,
        utc_offset_minutes: 180,
        orientation: 'landscape',
        viewport: { width: 1280, height: 800, device_pixel_ratio: 2 },
        screen: { width: 1920, height: 1080 },
        route_path: '/home'
      })
    ).toEqual({
      breakpoint: 'md',
      theme_mode: 'dark',
      connectivity: 'online',
      session_status: 'authenticated',
      orientation: 'landscape',
      text_scale: 1.2,
      utc_offset_minutes: 180,
      device_pixel_ratio: 2
    });
    expect(buildFeedbackClientContextJson({})).toBeNull();
  });

  it('classifies the window as mobile, tablet, or desktop like the app breakpoints', () => {
    expect(resolveFeedbackDeviceType({ viewport: { width: 390, height: 844 } })).toBe('MOBILE');
    expect(resolveFeedbackDeviceType({ viewport: { width: 599, height: 900 } })).toBe('MOBILE');
    expect(resolveFeedbackDeviceType({ viewport: { width: 600, height: 900 } })).toBe('TABLET');
    expect(resolveFeedbackDeviceType({ viewport: { width: 1199, height: 900 } })).toBe('TABLET');
    expect(resolveFeedbackDeviceType({ viewport: { width: 1200, height: 900 } })).toBe('DESKTOP');
    expect(
      resolveFeedbackDeviceType({ device_type: 'tablet', viewport: { width: 390, height: 844 } })
    ).toBe('TABLET');
    expect(resolveFeedbackDeviceType({ device_type: 'WATCH' })).toBeNull();
    expect(resolveFeedbackDeviceType({})).toBeNull();
  });

  it('rounds logical pixel sizes for storage', () => {
    expect(toFeedbackPixelCount(1180.6)).toBe(1181);
    expect(toFeedbackPixelCount(undefined)).toBeNull();
    expect(toFeedbackPixelCount(-1)).toBeNull();
  });
});
