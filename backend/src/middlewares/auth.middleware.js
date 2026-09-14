/**
 * Authentication & Authorization Middleware
 * 
 * JWT authentication and RBAC enforcement per auth-security.mdc
 * - Step 1.18: JWT authentication, extracts user from token
 * - Step 1.19: RBAC enforcement (checks roles/permissions)
 * 
 * Per auth-security.mdc:
 * - JWT must be used for all protected routes
 * - Role-based access control must be enforced via middleware
 * - Controllers must not bypass RBAC checks
 */

const { verifyToken } = require('@lib/jwt');
const { verifyApiKey } = require('@lib/crypto');
const { createAuditLog } = require('@lib/audit');
const { HttpError } = require('@lib/errors');
const { normalizeRoleName } = require('@config/roles');
const { markSpanError, recordSecurityEvent } = require('@lib/telemetry/metrics');
const apiKeyRepository = require('@repositories/api-key/api-key.repository');

const API_KEY_ALLOWED_ROUTE_SEGMENTS = new Set([
  'integrations',
  'integration-logs',
  'webhook-subscriptions',
  'interop']);

const isApiKeyContext = (user = {}) =>
  String(user.auth_type || user.authType || '').toLowerCase() === 'api_key';

/**
 * Normalize decoded JWT payload into a consistent request user object.
 * This keeps compatibility with code that expects either snake_case or camelCase fields.
 *
 * @param {Object} decoded - Decoded JWT payload
 * @returns {Object} Normalized user context
 */
const normalizeUserContext = (decoded = {}) => {
  const userId = decoded.id || decoded.user_id || decoded.userId || null;
  const tenantId = decoded.tenant_id || decoded.tenantId || null;
  const facilityId =
    decoded.facility_id ||
    decoded.facilityId ||
    decoded.hospital_id ||
    decoded.hospitalId ||
    null;
  const authType = decoded.auth_type || decoded.authType || 'jwt';
  const apiKeyAuth = String(authType).toLowerCase() === 'api_key';

  const rawRoles = Array.isArray(decoded.roles)
    ? decoded.roles
    : decoded.role
      ? [decoded.role]
      : [];
  const roles = rawRoles
    .map((role) => normalizeRoleName(role) || String(role || '').trim().toUpperCase())
    .filter(Boolean);
  const effectiveRoles = apiKeyAuth ? [] : roles;

  const permissions = Array.isArray(decoded.permissions)
    ? decoded.permissions
    : [];
  const role = apiKeyAuth ? null : effectiveRoles[0] || null;

  return {
    ...decoded,
    id: userId,
    user_id: userId,
    userId,
    tenant_id: tenantId,
    tenantId,
    facility_id: facilityId,
    facilityId,
    auth_type: authType,
    api_key_id: decoded.api_key_id || decoded.apiKeyId || null,
    apiKeyId: decoded.api_key_id || decoded.apiKeyId || null,
    role,
    roles: effectiveRoles,
    permissions
  };
};

/**
 * Resolve effective permissions from request user context.
 * Prefers explicit token permissions, then falls back to role-permission mapping.
 *
 * @param {Object} user - Normalized user context
 * @returns {string[]} Effective permission list
 */
const getUserPermissions = (user = {}) => {
  const {
    resolveRequestPermissionNames} = require('@lib/authorization/effective-access');

  if (isApiKeyContext(user)) {
    const explicitPermissions = Array.isArray(user.permissions)
      ? user.permissions.map((permission) => String(permission || '').trim()).filter(Boolean)
      : [];
    return Array.from(new Set(explicitPermissions));
  }

  return resolveRequestPermissionNames(user);
};

/**
 * Extract JWT token from Authorization header
 * 
 * @param {Object} req - Express request object
 * @returns {string|null} JWT token or null
 */
const extractToken = (req) => {
  const authHeader = req.headers.authorization;
  
  if (!authHeader) {
    return null;
  }
  
  // Support "Bearer <token>" format
  const parts = authHeader.split(' ');
  if (parts.length === 2 && parts[0] === 'Bearer') {
    return parts[1];
  }
  
  return null;
};

const extractApiKey = (req) => {
  const headerValue = req.headers?.['x-api-key'];
  if (typeof headerValue === 'string' && headerValue.trim()) {
    return headerValue.trim();
  }

  const authHeader = req.headers?.authorization;
  if (!authHeader) {
    return null;
  }

  const parts = authHeader.split(' ');
  if (parts.length === 2 && String(parts[0]).toLowerCase() === 'apikey') {
    return parts[1].trim();
  }

  return null;
};

const getRouteSegment = (req) =>
  String(req.path || req.originalUrl || '')
    .replace(/^\/+/, '')
    .split('/')[0]
    .toLowerCase();

const isApiKeyAllowedForRoute = (req) => API_KEY_ALLOWED_ROUTE_SEGMENTS.has(getRouteSegment(req));

const normalizeApiKeyPermissions = (apiKeyRecord = {}) =>
  (Array.isArray(apiKeyRecord.permissions) ? apiKeyRecord.permissions : [])
    .flatMap((entry) => {
      const permission = entry?.permission && typeof entry.permission === 'object'
        ? entry.permission
        : entry;
      return [
        permission?.name,
        permission?.code,
        entry?.permission_name];
    })
    .map((permission) => String(permission || '').trim())
    .filter(Boolean);

const buildApiKeyUserContext = (apiKeyRecord = {}) => {
  const linkedUser = apiKeyRecord.user || {};
  const rawRoles = Array.isArray(linkedUser.roles)
    ? linkedUser.roles.map((entry) => entry?.role?.name || entry?.name || entry?.role_name || entry)
    : [];
  const linkedRoles = rawRoles
    .map((role) => normalizeRoleName(role) || String(role || '').trim().toUpperCase())
    .filter(Boolean);
  const scopedPermissions = normalizeApiKeyPermissions(apiKeyRecord);

  return normalizeUserContext({
    ...linkedUser,
    id: linkedUser.id || linkedUser.user_id || linkedUser.userId || apiKeyRecord.user_id,
    user_id: linkedUser.id || linkedUser.user_id || linkedUser.userId || apiKeyRecord.user_id,
    tenant_id: apiKeyRecord.tenant_id || linkedUser.tenant_id || linkedUser.tenantId || null,
    facility_id: linkedUser.facility_id || linkedUser.facilityId || null,
    linked_user_roles: linkedRoles,
    role: null,
    roles: [],
    permissions: scopedPermissions,
    auth_type: 'api_key',
    api_key_id: apiKeyRecord.id});
};

const parseApiKeyHint = (rawApiKey) => {
  const normalized = String(rawApiKey || '').trim();
  const [hint, ...rest] = normalized.split('.');
  if (!hint || rest.length === 0) {
    return { hint: null, presentedKey: normalized };
  }

  return {
    hint: hint.trim().toUpperCase(),
    presentedKey: normalized};
};

const resolveApiKeyCandidates = async (presentedApiKey) => {
  const { hint } = parseApiKeyHint(presentedApiKey);
  if (hint) {
    const candidates = await apiKeyRepository.findAuthCandidatesByFriendlyId(hint);
    if (Array.isArray(candidates) && candidates.length > 0) {
      return candidates;
    }
  }

  return apiKeyRepository.findAuthCandidates();
};

const authenticateWithApiKey = async (req, apiKey) => {
  if (!isApiKeyAllowedForRoute(req)) {
    recordSecurityEvent('auth.api_key_not_allowed', {
      'http.route': String(req.originalUrl || req.path || '').split('?')[0]});
    throw new HttpError('errors.auth.api_key_not_allowed', 403);
  }

  const candidates = await resolveApiKeyCandidates(apiKey);
  const record = Array.isArray(candidates)
    ? (await Promise.all(
        candidates.map(async (candidate) =>
          (await verifyApiKey(candidate.key_hash, apiKey)) ? candidate : null
        )
      )).find(Boolean)
    : null;

  if (!record) {
    recordSecurityEvent('auth.api_key_invalid', {
      'http.route': String(req.originalUrl || req.path || '').split('?')[0]});
    throw new HttpError('errors.auth.api_key_invalid', 401);
  }

  req.user = buildApiKeyUserContext(record);
  await apiKeyRepository.touchLastUsed(record.id);
  createAuditLog({
    tenant_id: record.tenant_id,
    user_id: record.user_id,
    action: 'API_KEY_USED',
    entity: 'api_key',
    entity_id: record.id,
    ip_address: req.ip,
    user_agent: req.get?.('user-agent'),
    details: {
      route: String(req.originalUrl || req.path || '').split('?')[0],
      auth_type: 'api_key'}}).catch(() => {});
};

/**
 * JWT Authentication Middleware
 * Verifies JWT token and attaches user to request
 * 
 * @returns {Function} Express middleware
 */
const authenticate = () => {
  return async (req, res, next) => {
    try {
      // Support idempotent auth middleware usage (global + route-level).
      if (
        req.user &&
        ((req.user.id || req.user.userId || req.user.user_id) ||
          req.user.api_key_id ||
          req.user.apiKeyId)
      ) {
        req.user = normalizeUserContext(req.user);
        return next();
      }

      const token = extractToken(req);
      const apiKey = extractApiKey(req);
      
      if (!token && !apiKey) {
        recordSecurityEvent('auth.missing_token', {
          'http.route': String(req.originalUrl || req.path || '').split('?')[0]});
        return next(new HttpError('errors.auth.missing_token', 401));
      }

      if (token) {
        try {
          const decoded = verifyToken(token);
          req.user = normalizeUserContext(decoded);
          return next();
        } catch (tokenError) {
          recordSecurityEvent('auth.invalid_token', {
            'http.route': String(req.originalUrl || req.path || '').split('?')[0]});
          markSpanError(tokenError, {
            'hms.security.event': 'auth.invalid_token'});
          return next(new HttpError('errors.auth.invalid_token', 401));
        }
      }

      try {
        await authenticateWithApiKey(req, apiKey);
        return next();
      } catch (apiKeyError) {
        if (apiKeyError instanceof HttpError) {
          return next(apiKeyError);
        }
        recordSecurityEvent('auth.api_key_invalid', {
          'http.route': String(req.originalUrl || req.path || '').split('?')[0]});
        markSpanError(apiKeyError, {
          'hms.security.event': 'auth.api_key_invalid'});
        return next(new HttpError('errors.auth.api_key_invalid', 401));
      }
    } catch (err) {
      next(err);
    }
  };
};

/**
 * Optional JWT authentication for routes that also serve anonymous callers.
 *
 * A valid bearer token attaches the user exactly as `authenticate()` does. A
 * missing, malformed, or expired token leaves `req.user` unset instead of
 * failing the request. API keys are ignored: they identify integrations, not
 * people.
 *
 * @returns {Function} Express middleware
 */
const authenticateOptional = () => {
  return (req, res, next) => {
    if (req.user && (req.user.id || req.user.userId || req.user.user_id)) {
      req.user = normalizeUserContext(req.user);
      return next();
    }

    const token = extractToken(req);
    if (!token) {
      return next();
    }

    try {
      req.user = normalizeUserContext(verifyToken(token));
    } catch (tokenError) {
      req.user = undefined;
      recordSecurityEvent('auth.optional_invalid_token', {
        'http.route': String(req.originalUrl || req.path || '').split('?')[0]});
    }
    return next();
  };
};

/**
 * RBAC Authorization Middleware
 * Checks if user has required role or permission
 * 
 * @param {string|string[]} requiredRole - Required role(s) or permission(s)
 * @param {string} [type='role'] - Type of check: 'role' or 'permission'
 * @returns {Function} Express middleware
 */
const authorize = (requiredRole, type = 'role') => {
  return (req, res, next) => {
    try {
      if (!req.user) {
        return next(new HttpError('errors.auth.unauthorized', 403));
      }
      
      if (type === 'role') {
        if (isApiKeyContext(req.user)) {
          recordSecurityEvent('auth.role_denied', {
            'http.route': String(req.originalUrl || req.path || '').split('?')[0],
            'auth.check.type': 'role',
            'auth.context': 'api_key'});
          return next(new HttpError('errors.auth.insufficient_permissions', 403));
        }

        const userRoles = (req.user.roles || [req.user.role])
          .map((role) => normalizeRoleName(role) || String(role || '').toUpperCase())
          .filter(Boolean);
        const rolesArray = (Array.isArray(requiredRole) ? requiredRole : [requiredRole])
          .map((role) => normalizeRoleName(role) || String(role || '').toUpperCase())
          .filter(Boolean);

        const hasRequiredRole = rolesArray.some((role) =>
          userRoles.some((userRole) => userRole === role)
        );
        
        if (!hasRequiredRole) {
          recordSecurityEvent('auth.role_denied', {
            'http.route': String(req.originalUrl || req.path || '').split('?')[0],
            'auth.check.type': 'role'});
          return next(new HttpError('errors.auth.insufficient_permissions', 403));
        }
      } else if (type === 'permission') {
        // Permission-based check
        const userPermissions = getUserPermissions(req.user);
        const permissionsArray = Array.isArray(requiredRole) ? requiredRole : [requiredRole];
        
        const hasRequiredPermission = permissionsArray.some(permission => 
          userPermissions.includes(permission)
        );
        
        if (!hasRequiredPermission) {
          recordSecurityEvent('auth.permission_denied', {
            'http.route': String(req.originalUrl || req.path || '').split('?')[0],
            'auth.check.type': 'permission'});
          return next(new HttpError('errors.auth.insufficient_permissions', 403));
        }
      }
      
      next();
    } catch (err) {
      next(err);
    }
  };
};

/**
 * Explicitly deny selected roles after authentication.
 *
 * This is useful for staff-only route groups where broad read permissions are
 * also used by portal or support roles in other, narrower contexts.
 *
 * @param {string|string[]} disallowedRoles - Role(s) not allowed on the route.
 * @returns {Function} Express middleware
 */
const denyRoles = (disallowedRoles) => {
  const normalizedDisallowedRoles = new Set(
    (Array.isArray(disallowedRoles) ? disallowedRoles : [disallowedRoles])
      .map((role) => normalizeRoleName(role) || String(role || '').toUpperCase())
      .filter(Boolean)
  );

  return (req, res, next) => {
    try {
      if (!req.user) {
        return next(new HttpError('errors.auth.unauthorized', 403));
      }

      const userRoles = (Array.isArray(req.user.roles) ? req.user.roles : [req.user.role])
        .map((role) => normalizeRoleName(role) || String(role || '').toUpperCase())
        .filter(Boolean);

      if (userRoles.some((role) => normalizedDisallowedRoles.has(role))) {
        recordSecurityEvent('auth.role_denied', {
          'http.route': String(req.originalUrl || req.path || '').split('?')[0],
          'auth.check.type': 'role_denylist'});
        return next(new HttpError('errors.auth.insufficient_permissions', 403));
      }

      return next();
    } catch (err) {
      return next(err);
    }
  };
};

/**
 * Combined authentication and authorization middleware
 * 
 * @param {string|string[]} [requiredRole] - Optional required role(s)
 * @param {string} [type='role'] - Type of check: 'role' or 'permission'
 * @returns {Function[]} Array of Express middlewares
 */
const requireAuth = (requiredRole = null, type = 'role') => {
  const middlewares = [authenticate()];
  
  if (requiredRole) {
    middlewares.push(authorize(requiredRole, type));
  }
  
  return middlewares;
};

module.exports = {
  authenticate,
  authenticateOptional,
  authorize,
  denyRoles,
  requireAuth,
  normalizeUserContext,
  getUserPermissions};

