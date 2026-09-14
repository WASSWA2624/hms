/**
 * auth middleware tests
 */

jest.mock('@lib/jwt', () => ({
  verifyToken: jest.fn()
}));

jest.mock('@lib/crypto', () => ({
  verifyApiKey: jest.fn()
}));

jest.mock('@lib/audit', () => ({
  createAuditLog: jest.fn(() => Promise.resolve({}))
}));

jest.mock('@repositories/api-key/api-key.repository', () => ({
  findAuthCandidatesByFriendlyId: jest.fn(),
  findAuthCandidates: jest.fn(),
  touchLastUsed: jest.fn()
}));

const {
  authenticate,
  authenticateOptional,
  authorize,
  denyRoles
} = require('@middlewares/auth.middleware');
const { HttpError } = require('@lib/errors');
const { verifyToken } = require('@lib/jwt');
const { verifyApiKey } = require('@lib/crypto');
const apiKeyRepository = require('@repositories/api-key/api-key.repository');

describe('auth middleware', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    apiKeyRepository.findAuthCandidates.mockResolvedValue([]);
    apiKeyRepository.findAuthCandidatesByFriendlyId.mockResolvedValue([]);
    apiKeyRepository.touchLastUsed.mockResolvedValue({});
  });

  it('authorizes permission checks from role-permission mapping when token permissions are missing', () => {
    const middleware = authorize('tenant:admin', 'permission');
    const req = {
      user: {
        role: 'TENANT_ADMIN',
        roles: ['TENANT_ADMIN']
      }
    };
    const res = {};
    const next = jest.fn();

    middleware(req, res, next);

    expect(next).toHaveBeenCalledWith();
  });

  it('rejects permission checks when permission is not granted', () => {
    const middleware = authorize('platform:admin', 'permission');
    const req = {
      user: {
        role: 'DOCTOR',
        roles: ['DOCTOR']
      }
    };
    const res = {};
    const next = jest.fn();

    middleware(req, res, next);

    const [error] = next.mock.calls[0];
    expect(error).toBeInstanceOf(HttpError);
    expect(error.statusCode).toBe(403);
  });

  it('authorizes patient read permission from role mapping', () => {
    const middleware = authorize('patient:read', 'permission');
    const req = {
      user: {
        role: 'RECEPTIONIST',
        roles: ['RECEPTIONIST']
      }
    };
    const res = {};
    const next = jest.fn();

    middleware(req, res, next);

    expect(next).toHaveBeenCalledWith();
  });

  it('merges permissions across multiple simultaneous roles', () => {
    const clinicalMiddleware = authorize('clinical:write', 'permission');
    const biomedMiddleware = authorize('biomed:write', 'permission');
    const req = {
      user: {
        role: 'DOCTOR',
        roles: ['DOCTOR', 'BIOMED']
      }
    };
    const res = {};
    const clinicalNext = jest.fn();
    const biomedNext = jest.fn();

    clinicalMiddleware(req, res, clinicalNext);
    biomedMiddleware(req, res, biomedNext);

    expect(clinicalNext).toHaveBeenCalledWith();
    expect(biomedNext).toHaveBeenCalledWith();
  });

  it('authorizes hospital admin aliases for facility-scoped mortuary permissions', () => {
    const middleware = authorize('mortuary:read', 'permission');
    const req = {
      user: {
        role: 'HOSPITAL_ADMIN',
        roles: ['HOSPITAL_ADMIN']
      }
    };
    const res = {};
    const next = jest.fn();

    middleware(req, res, next);

    expect(next).toHaveBeenCalledWith();
  });

  it('authorizes display-form platform admin roles for permission checks', () => {
    const middleware = authorize('clinical:read', 'permission');
    const req = {
      user: {
        role: 'Platform Admin',
        roles: ['Platform Admin']
      }
    };
    const res = {};
    const next = jest.fn();

    middleware(req, res, next);

    expect(next).toHaveBeenCalledWith();
  });

  it('authorizes display-form platform admin roles for role checks', () => {
    const middleware = authorize('PLATFORM_ADMIN', 'role');
    const req = {
      user: {
        role: 'Platform Admin',
        roles: ['Platform Admin']
      }
    };
    const res = {};
    const next = jest.fn();

    middleware(req, res, next);

    expect(next).toHaveBeenCalledWith();
  });

  it('rejects patient write permission when role is read-only', () => {
    const middleware = authorize('patient:write', 'permission');
    const req = {
      user: {
        role: 'PATIENT',
        roles: ['PATIENT']
      }
    };
    const res = {};
    const next = jest.fn();

    middleware(req, res, next);

    const [error] = next.mock.calls[0];
    expect(error).toBeInstanceOf(HttpError);
    expect(error.statusCode).toBe(403);
  });

  it('explicitly denies selected roles on staff-only route groups', () => {
    const middleware = denyRoles(['PATIENT', 'HOUSE_KEEPER']);
    const req = {
      user: {
        role: 'PATIENT',
        roles: ['PATIENT']
      },
      originalUrl: '/api/v1/patients',
      path: '/patients'
    };
    const res = {};
    const next = jest.fn();

    middleware(req, res, next);

    const [error] = next.mock.calls[0];
    expect(error).toBeInstanceOf(HttpError);
    expect(error.statusCode).toBe(403);
  });

  it('allows roles outside the explicit deny list', () => {
    const middleware = denyRoles(['PATIENT', 'HOUSE_KEEPER']);
    const req = {
      user: {
        role: 'NURSE',
        roles: ['NURSE']
      },
      originalUrl: '/api/v1/triage',
      path: '/triage'
    };
    const res = {};
    const next = jest.fn();

    middleware(req, res, next);

    expect(next).toHaveBeenCalledWith();
  });

  it('authorizes AMBULANCE_OPERATOR emergency write permission from role mapping', () => {
    const middleware = authorize('emergency:write', 'permission');
    const req = {
      user: {
        role: 'AMBULANCE_OPERATOR',
        roles: ['AMBULANCE_OPERATOR']
      }
    };
    const res = {};
    const next = jest.fn();

    middleware(req, res, next);

    expect(next).toHaveBeenCalledWith();
  });

  it('rejects AMBULANCE_OPERATOR emergency delete permission', () => {
    const middleware = authorize('emergency:delete', 'permission');
    const req = {
      user: {
        role: 'AMBULANCE_OPERATOR',
        roles: ['AMBULANCE_OPERATOR']
      }
    };
    const res = {};
    const next = jest.fn();

    middleware(req, res, next);

    const [error] = next.mock.calls[0];
    expect(error).toBeInstanceOf(HttpError);
    expect(error.statusCode).toBe(403);
  });

  it('does not grant role-derived permissions to API key requests', () => {
    const middleware = authorize('tenant:admin', 'permission');
    const req = {
      user: {
        role: 'TENANT_ADMIN',
        roles: ['TENANT_ADMIN'],
        auth_type: 'api_key',
        permissions: []
      }
    };
    const res = {};
    const next = jest.fn();

    middleware(req, res, next);

    const [error] = next.mock.calls[0];
    expect(error).toBeInstanceOf(HttpError);
    expect(error.statusCode).toBe(403);
  });

  it('does not allow API key requests to satisfy role-based guards', () => {
    const middleware = authorize('TENANT_ADMIN', 'role');
    const req = {
      user: {
        role: 'TENANT_ADMIN',
        roles: ['TENANT_ADMIN'],
        auth_type: 'api_key',
        permissions: ['integration:read']
      },
      originalUrl: '/api/v1/api-keys',
      path: '/api-keys'
    };
    const res = {};
    const next = jest.fn();

    middleware(req, res, next);

    const [error] = next.mock.calls[0];
    expect(error).toBeInstanceOf(HttpError);
    expect(error.statusCode).toBe(403);
  });

  it('authenticates valid JWT bearer tokens', async () => {
    verifyToken.mockReturnValue({
      id: 'user-123',
      tenant_id: 'tenant-123',
      roles: ['DOCTOR']
    });

    const req = {
      headers: {
        authorization: 'Bearer valid-token'
      },
      path: '/patients',
      originalUrl: '/api/v1/patients'
    };
    const res = {};
    const next = jest.fn();

    await authenticate()(req, res, next);

    expect(req.user).toEqual(
      expect.objectContaining({
        id: 'user-123',
        tenant_id: 'tenant-123',
        auth_type: 'jwt',
        roles: ['DOCTOR']
      })
    );
    expect(next).toHaveBeenCalledWith();
  });

  it('normalizes hospital id claims to facility scope on JWT bearer tokens', async () => {
    verifyToken.mockReturnValue({
      id: 'user-hospital-admin',
      tenant_id: 'tenant-123',
      hospital_id: 'hospital-123',
      roles: ['HOSPITAL_ADMIN']
    });

    const req = {
      headers: {
        authorization: 'Bearer valid-token'
      },
      path: '/mortuary',
      originalUrl: '/api/v1/mortuary'
    };
    const res = {};
    const next = jest.fn();

    await authenticate()(req, res, next);

    expect(req.user).toEqual(
      expect.objectContaining({
        facility_id: 'hospital-123',
        facilityId: 'hospital-123',
        role: 'FACILITY_ADMIN',
        roles: ['FACILITY_ADMIN']
      })
    );
    expect(next).toHaveBeenCalledWith();
  });

  it('authenticates valid API keys on allowed integration routes', async () => {
    const apiKeyRecord = {
      id: 'key-123',
      tenant_id: 'tenant-123',
      user_id: 'user-123',
      key_hash: 'stored-hash',
      user: {
        id: 'user-123',
        tenant_id: 'tenant-123',
        roles: [{ role: { name: 'TENANT_ADMIN' } }]
      },
      permissions: [{ permission: { name: 'integration:read' } }]
    };

    apiKeyRepository.findAuthCandidatesByFriendlyId.mockResolvedValue([apiKeyRecord]);
    verifyApiKey.mockResolvedValue(true);

    const req = {
      headers: {
        'x-api-key': 'KEY-ABCD1234.secret-part'
      },
      path: '/webhook-subscriptions',
      originalUrl: '/api/v1/webhook-subscriptions',
      ip: '127.0.0.1',
      get: jest.fn(() => 'jest')
    };
    const res = {};
    const next = jest.fn();

    await authenticate()(req, res, next);

    expect(req.user).toEqual(
      expect.objectContaining({
        id: 'user-123',
        tenant_id: 'tenant-123',
        auth_type: 'api_key',
        api_key_id: 'key-123',
        roles: [],
        permissions: ['integration:read']
      })
    );
    expect(apiKeyRepository.touchLastUsed).toHaveBeenCalledWith('key-123');
    expect(next).toHaveBeenCalledWith();
  });

  it('rejects API keys on non-integration routes', async () => {
    const req = {
      headers: {
        'x-api-key': 'KEY-ABCD1234.secret-part'
      },
      path: '/patients',
      originalUrl: '/api/v1/patients',
      ip: '127.0.0.1',
      get: jest.fn(() => 'jest')
    };
    const res = {};
    const next = jest.fn();

    await authenticate()(req, res, next);

    const [error] = next.mock.calls[0];
    expect(error).toBeInstanceOf(HttpError);
    expect(error.messageKey).toBe('errors.auth.api_key_not_allowed');
    expect(error.statusCode).toBe(403);
  });

  it('rejects API keys on API key management routes', async () => {
    const req = {
      headers: {
        'x-api-key': 'KEY-ABCD1234.secret-part'
      },
      path: '/api-keys',
      originalUrl: '/api/v1/api-keys',
      ip: '127.0.0.1',
      get: jest.fn(() => 'jest')
    };
    const res = {};
    const next = jest.fn();

    await authenticate()(req, res, next);

    const [error] = next.mock.calls[0];
    expect(error).toBeInstanceOf(HttpError);
    expect(error.messageKey).toBe('errors.auth.api_key_not_allowed');
    expect(error.statusCode).toBe(403);
  });

  describe('authenticateOptional', () => {
    const buildRequest = (headers = {}) => ({
      headers,
      path: '/',
      originalUrl: '/api/v1/feedback'
    });

    it('attaches the user for a valid bearer token', () => {
      verifyToken.mockReturnValueOnce({ userId: 'user-1', tenant_id: 'tenant-1', roles: ['nurse'] });
      const req = buildRequest({ authorization: 'Bearer good-token' });
      const next = jest.fn();

      authenticateOptional()(req, {}, next);

      expect(next).toHaveBeenCalledWith();
      expect(req.user).toEqual(
        expect.objectContaining({ id: 'user-1', tenant_id: 'tenant-1', roles: ['NURSE'] })
      );
    });

    it('continues anonymously without a token', () => {
      const req = buildRequest();
      const next = jest.fn();

      authenticateOptional()(req, {}, next);

      expect(next).toHaveBeenCalledWith();
      expect(req.user).toBeUndefined();
      expect(verifyToken).not.toHaveBeenCalled();
    });

    it('continues anonymously when the token is invalid or expired', () => {
      verifyToken.mockImplementationOnce(() => {
        throw new Error('jwt expired');
      });
      const req = buildRequest({ authorization: 'Bearer expired-token' });
      const next = jest.fn();

      authenticateOptional()(req, {}, next);

      expect(next).toHaveBeenCalledWith();
      expect(req.user).toBeUndefined();
    });

    it('ignores API keys', () => {
      const req = buildRequest({ 'x-api-key': 'KEY-ABCD1234.secret-part' });
      const next = jest.fn();

      authenticateOptional()(req, {}, next);

      expect(next).toHaveBeenCalledWith();
      expect(req.user).toBeUndefined();
      expect(apiKeyRepository.findAuthCandidates).not.toHaveBeenCalled();
    });
  });
});
