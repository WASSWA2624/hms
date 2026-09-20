const subject = require('@routes/pharmacy-location/pharmacy-location.routes');

describe('pharmacy-location.routes contract', () => {
  it('exports an express router with registered handlers', () => {
    expect(subject).toBeDefined();
    expect(typeof subject).toBe('function');
    expect(Array.isArray(subject.stack)).toBe(true);
    expect(subject.stack.length).toBeGreaterThan(0);
  });

  it('registers the cross-pharmacy availability read', () => {
    const paths = subject.stack
      .map((layer) => layer.route?.path)
      .filter(Boolean);
    expect(paths).toContain('/:id/availability');
    expect(paths).toContain('/:id/prices');
    expect(paths).toContain('/:id/access');
  });
});
