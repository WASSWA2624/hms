jest.mock('@middlewares/auth.middleware', () => ({
  authenticate: jest.fn(() => function authenticate(req, res, next) { next(); }),
  authenticateOptional: jest.fn(() => function authenticateOptional(req, res, next) { next(); }),
  authorize: jest.fn(() => function authorize(req, res, next) { next(); })
}));
jest.mock('@middlewares/live-access.middleware', () => ({
  hydrateLiveAccess: jest.fn(() => function hydrateLiveAccess(req, res, next) { next(); })
}));
jest.mock('@middlewares/rateLimit.middleware', () => ({
  rateLimit: jest.fn(() => function rateLimit(req, res, next) { next(); })
}));
jest.mock('@controllers/feedback/feedback.controller', () => ({
  deleteFeedback: function deleteFeedback() {},
  exportFeedback: function exportFeedback() {},
  getFeedbackFacets: function getFeedbackFacets() {},
  getFeedbackScreenshot: function getFeedbackScreenshot() {},
  getFeedbackSummary: function getFeedbackSummary() {},
  listFeedback: function listFeedback() {},
  listFeedbackScreenshots: function listFeedbackScreenshots() {},
  submitFeedback: function submitFeedback() {}
}));

const { authorize } = require('@middlewares/auth.middleware');
const { rateLimit } = require('@middlewares/rateLimit.middleware');
const rateLimitConfig = require('@config/rateLimit');
const subject = require('@routes/feedback/app-feedback.routes');

// Middleware factories run while the router loads; Jest clears mock calls
// before each test, so keep the load-time calls.
const authorizeCalls = [...authorize.mock.calls];
const rateLimitCalls = [...rateLimit.mock.calls];

const getRouteSignatures = (router) =>
  router.stack
    .filter((layer) => layer.route)
    .flatMap((layer) =>
      Object.keys(layer.route.methods).map((method) => `${method.toUpperCase()} ${layer.route.path}`)
    )
    .sort();

const routeChain = (method, path) =>
  subject.stack
    .find((layer) => layer.route?.path === path && layer.route.methods[method])
    .route.stack.map((layer) => layer.name);

describe('app-feedback.routes contract', () => {
  it('registers public submission and admin management endpoints', () => {
    expect(getRouteSignatures(subject)).toEqual([
      'DELETE /',
      'GET /',
      'GET /:human_friendly_id/screenshots',
      'GET /:human_friendly_id/screenshots/:screenshot_id',
      'GET /export',
      'GET /facets',
      'GET /summary',
      'POST /',
      'POST /export'
    ]);
  });

  it('lets anyone submit, rate limited, with optional authentication', () => {
    const chain = routeChain('post', '/');

    expect(chain.slice(0, 2)).toEqual(['rateLimit', 'authenticateOptional']);
    expect(chain).not.toContain('authenticate');
    expect(chain[chain.length - 1]).toBe('submitFeedback');
    expect(rateLimitCalls).toEqual([[rateLimitConfig.endpoints.feedback]]);
  });

  it('accepts screenshots on submission, after optional authentication', () => {
    const chain = routeChain('post', '/');

    // Images are parsed once the request is identified, and always before
    // validation, so one schema sees the JSON body either way.
    expect(chain).toEqual([
      'rateLimit',
      'authenticateOptional',
      'acceptFeedbackSubmission',
      // The validation middleware is anonymous.
      '<anonymous>',
      'submitFeedback'
    ]);
  });

  it.each([
    ['get', '/', 'listFeedback'],
    ['get', '/summary', 'getFeedbackSummary'],
    ['get', '/facets', 'getFeedbackFacets'],
    ['get', '/export', 'exportFeedback'],
    ['post', '/export', 'exportFeedback'],
    ['get', '/:human_friendly_id/screenshots', 'listFeedbackScreenshots'],
    ['get', '/:human_friendly_id/screenshots/:screenshot_id', 'getFeedbackScreenshot'],
    ['delete', '/', 'deleteFeedback']
  ])('requires live platform roles for %s %s', (method, path, handler) => {
    const chain = routeChain(method, path);

    expect(chain.slice(0, 3)).toEqual(['authenticate', 'hydrateLiveAccess', 'authorize']);
    expect(chain[chain.length - 1]).toBe(handler);
  });

  it('authorizes management for platform owners and platform admins only', () => {
    expect(authorizeCalls).toHaveLength(8);
    authorizeCalls.forEach((call) => {
      expect(call).toEqual([['PLATFORM_OWNER', 'PLATFORM_ADMIN']]);
    });
  });
});
