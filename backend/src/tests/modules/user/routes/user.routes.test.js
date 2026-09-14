const subject = require('@routes/user/user.routes');

describe('user.routes contract', () => {
  it('exports an express router with registered handlers', () => {
    expect(subject).toBeDefined();
    expect(typeof subject).toBe('function');
    expect(Array.isArray(subject.stack)).toBe(true);
    expect(subject.stack.length).toBeGreaterThan(0);
  });

  it('registers the credential reset route', () => {
    const layer = subject.stack.find(
      (entry) => entry.route?.path === '/:id/reset-credentials'
    );
    expect(layer?.route?.methods?.post).toBe(true);
  });

  it('registers the set password route', () => {
    const layer = subject.stack.find(
      (entry) => entry.route?.path === '/:id/password'
    );
    expect(layer?.route?.methods?.put).toBe(true);
  });

  it('registers the permanent delete route', () => {
    const layer = subject.stack.find(
      (entry) => entry.route?.path === '/:id/permanent'
    );
    expect(layer?.route?.methods?.delete).toBe(true);
  });
});
