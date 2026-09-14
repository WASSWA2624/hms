/**
 * CORS Configuration
 * 
 * CORS configuration per cors.mdc
 * Reads CORS_ORIGINS from @config/env
 * Environment-aware origins (different for dev/staging/production)
 */

const { CORS_ORIGINS, NODE_ENV, ALLOW_PRIVATE_NETWORK_ORIGINS } = require('@config/env');
const { logger } = require('@lib/logging');

const PRIVATE_IPV4_REGEX = /^(10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[0-1])\.\d{1,3}\.\d{1,3})$/;
const PRIVATE_HOSTNAME_REGEX = /^[a-z0-9-]+(\.local)?$/i;
const LOOPBACK_HOSTNAMES = new Set(['localhost', '127.0.0.1', '::1']);

const normalizeHostname = (hostname) => String(hostname || '').replace(/^\[|\]$/g, '').toLowerCase();
const LOCAL_DEV_PORTS = ['3000', '3001', '5201', '8081', '8084', '8085', '8086', '8087', '8088'];

const isPrivateIPv6Host = (hostname) => {
  const normalized = normalizeHostname(hostname);
  if (!normalized.includes(':')) return false;
  if (normalized === '::1') return true;
  if (normalized.startsWith('fc') || normalized.startsWith('fd')) return true; // Unique local
  if (/^fe[89ab]/i.test(normalized)) return true; // Link-local
  return false;
};

const isPrivateNetworkOrigin = (origin) => {
  try {
    const { protocol, hostname } = new URL(origin);
    if (!['http:', 'https:'].includes(protocol)) return false;
    const normalizedHostname = normalizeHostname(hostname);
    if (normalizedHostname === 'localhost' || normalizedHostname === '127.0.0.1') return true;
    if (PRIVATE_IPV4_REGEX.test(normalizedHostname)) return true;
    if (isPrivateIPv6Host(normalizedHostname)) return true;
    // Allow mDNS/local hostnames for same-LAN development (e.g., desktop.local, DESKTOP-1234)
    if (PRIVATE_HOSTNAME_REGEX.test(normalizedHostname)) return true;
    return false;
  } catch (_) {
    return false;
  }
};

const isLoopbackOrigin = (origin) => {
  try {
    const { protocol, hostname } = new URL(origin);
    if (!['http:', 'https:'].includes(protocol)) return false;
    return LOOPBACK_HOSTNAMES.has(normalizeHostname(hostname));
  } catch (_) {
    return false;
  }
};

/**
 * Get CORS configuration
 * 
 * @returns {Object} CORS middleware options
 */
const getCorsConfig = () => {
  // In development, allow localhost origins
  // In production, only allow explicitly configured origins
  const baseOrigins = Array.isArray(CORS_ORIGINS) ? CORS_ORIGINS : [];
  const devOrigins = LOCAL_DEV_PORTS.flatMap((port) => [
    `http://localhost:${port}`,
    `http://127.0.0.1:${port}`
  ]);
  const expandLoopbackOrigins =
    NODE_ENV === 'development' || baseOrigins.some((origin) => isLoopbackOrigin(origin));
  
  const origins = expandLoopbackOrigins
    ? Array.from(new Set([...baseOrigins, ...devOrigins]))
    : baseOrigins;
  const allowPrivateNetworkOrigins = NODE_ENV === 'development' || ALLOW_PRIVATE_NETWORK_ORIGINS;

  // Never use wildcard with credentials; require explicit origins
  const allowedOrigins = origins.filter(Boolean);

  if (NODE_ENV === 'development') {
    logger.info('CORS configuration initialized', { 
      origins: allowedOrigins,
      baseOrigins,
      nodeEnv: NODE_ENV,
      allowPrivateNetworkOrigins
    });
  }
  
  return {
    origin: (origin, callback) => {
      // Allow requests with no origin (mobile apps, Postman, etc.)
      if (!origin) {
        if (NODE_ENV === 'development') {
          logger.info('CORS: No origin header, allowing request');
        }
        return callback(null, true);
      }
      
      // Normalize origin (remove trailing slash if present)
      const normalizedOrigin = origin.endsWith('/') ? origin.slice(0, -1) : origin;
      
      // Check if origin is in allowed list (check both original and normalized)
      const isAllowed = allowedOrigins.includes(origin) || allowedOrigins.includes(normalizedOrigin);
      const isPrivateOrigin = allowPrivateNetworkOrigins && isPrivateNetworkOrigin(normalizedOrigin);
      
      if (isAllowed || isPrivateOrigin) {
        if (NODE_ENV === 'development') {
          logger.info('CORS origin allowed', { origin, normalizedOrigin, isPrivateOrigin });
        }
        callback(null, true);
      } else {
        logger.warn('CORS origin denied', { 
          origin, 
          normalizedOrigin,
          allowedOrigins,
          originInList: allowedOrigins.includes(origin),
          normalizedInList: allowedOrigins.includes(normalizedOrigin),
          privateOriginAllowedByRule: isPrivateNetworkOrigin(normalizedOrigin),
          allowPrivateNetworkOrigins,
          baseOrigins,
          nodeEnv: NODE_ENV
        });
        // CORS middleware expects Error object, not HttpError
        const corsError = new Error('CORS: Origin not allowed');
        corsError.statusCode = 403;
        callback(corsError);
      }
    },
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
    allowedHeaders: [
      'Content-Type',
      'Authorization',
      'X-Requested-With',
      'X-CSRF-Token',
      'Accept-Language',
      'X-Locale',
      'X-Timezone',
      'X-Platform',
      'Sec-CH-UA',
      'Sec-CH-UA-Mobile',
      'Sec-CH-UA-Platform',
      'If-Match',
      'X-Resource-Version',
      'Idempotency-Key'
    ],
    exposedHeaders: [
      'X-RateLimit-Limit',
      'X-RateLimit-Remaining',
      'X-RateLimit-Reset',
      'Content-Disposition'
    ],
    maxAge: 86400 // 24 hours
  };
};

module.exports = {
  getCorsConfig,
  corsOptions: getCorsConfig()
};

