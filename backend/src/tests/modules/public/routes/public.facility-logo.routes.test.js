jest.mock('@lib/logging', () => ({
  logger: {
    warn: jest.fn(),
    info: jest.fn(),
    error: jest.fn()}}));

const mockStorage = {
  exists: jest.fn(),
  download: jest.fn()};

jest.mock('@lib/storage', () => ({
  createStorageService: jest.fn(() => mockStorage)}));

const APP_ORIGIN = 'https://app.example.com';

const { setEnvForTests } = require('@config/env');

setEnvForTests({
  JWT_SECRET: 'test-jwt-secret-key-minimum-32-characters-long',
  DATABASE_URL: 'mysql://test:test@localhost:3306/test_db',
  NODE_ENV: 'development',
  CORS_ORIGINS: APP_ORIGIN});

const express = require('express');
const request = require('supertest');
const cors = require('cors');
const { corsOptions } = require('@config/cors');
const router = require('@routes/public/public.routes');

// Mirrors the app's ordering: CORS first, then the public router.
const buildApp = () => {
  const app = express();
  app.use(cors(corsOptions));
  app.use('/api/v1/public', router);
  app.use((error, _req, res, _next) =>
    res.status(error.statusCode || (error.name === 'ZodError' ? 400 : 500)).json({
      message: error.message}));
  return app;
};

const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

describe('GET /api/v1/public/facility-logos/:key', () => {
  beforeEach(() => {
    mockStorage.exists.mockReset().mockResolvedValue(true);
    mockStorage.download.mockReset().mockResolvedValue(PNG);
  });

  it('serves the logo bytes as an image', async () => {
    const response = await request(buildApp())
      .get('/api/v1/public/facility-logos/logo-585d8466.png')
      .expect(200);

    expect(response.headers['content-type']).toBe('image/png');
    expect(Buffer.from(response.body)).toEqual(PNG);
  });

  // The reason this route exists: a browser will not decode a cross-origin
  // image without this header, and the static file server that fronts the API
  // answers `uploads/` itself, so those responses never carry it.
  it('carries CORS headers for the app origin', async () => {
    const response = await request(buildApp())
      .get('/api/v1/public/facility-logos/logo-585d8466.png')
      .set('Origin', APP_ORIGIN)
      .expect(200);

    expect(response.headers['access-control-allow-origin']).toBe(APP_ORIGIN);
  });

  it('serves without authentication', async () => {
    await request(buildApp())
      .get('/api/v1/public/facility-logos/logo-585d8466.png')
      .expect(200);
  });

  it('404s when the logo is not in storage', async () => {
    mockStorage.exists.mockResolvedValue(false);

    await request(buildApp())
      .get('/api/v1/public/facility-logos/logo-585d8466.png')
      .expect(404);
  });

  it.each([
    'reports_9322e26a_2026_09_appointment-throughput.pdf',
    'logo-585d8466.pdf',
    'notalogo-585d8466.png'])('rejects %s rather than reaching storage', async (key) => {
    await request(buildApp()).get(`/api/v1/public/facility-logos/${key}`).expect(400);
    expect(mockStorage.download).not.toHaveBeenCalled();
  });

  it('does not expose sibling files through path traversal', async () => {
    const response = await request(buildApp()).get(
      '/api/v1/public/facility-logos/..%2F..%2F.env'
    );

    expect(response.status).toBeGreaterThanOrEqual(400);
    expect(mockStorage.download).not.toHaveBeenCalled();
  });
});
