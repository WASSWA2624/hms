const subject = require('@routes/pharmacy-stock-order/pharmacy-stock-order.routes');

describe('pharmacy-stock-order.routes contract', () => {
  it('exports an express router with registered handlers', () => {
    expect(subject).toBeDefined();
    expect(typeof subject).toBe('function');
    expect(Array.isArray(subject.stack)).toBe(true);
  });

  it('exposes every step of the stock order workflow', () => {
    const paths = subject.stack
      .map((layer) => layer.route?.path)
      .filter(Boolean);

    // Review and issue are separate endpoints on purpose: approving an order
    // must not move stock.
    expect(paths).toContain('/:id/submit');
    expect(paths).toContain('/:id/review');
    expect(paths).toContain('/:id/issue');
    expect(paths).toContain('/:id/receive');
    expect(paths).toContain('/:id/cancel');
  });
});
