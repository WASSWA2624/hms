/**
 * Rate Limiting Configuration
 * 
 * Rate limit configuration per rate-limiting.mdc
 * Environment-aware (different limits for dev/staging/production)
 */

const { NODE_ENV } = require('@config/env');

const RateLimitConfig = {
  // Global limits
  global: {
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: NODE_ENV === 'development' ? 1000 : 100 // Higher limit in development
  },
  
  // Authenticated user limits (higher than IP-based)
  authenticated: {
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: NODE_ENV === 'development' ? 5000 : 1000
  },
  
  // Endpoint-specific limits
  endpoints: {
    // Authentication endpoints (stricter limits)
    auth: {
      windowMs: 15 * 60 * 1000, // 15 minutes
      max: NODE_ENV === 'development' ? 1000 : 20
    },
    
    // Registration endpoint (strict in prod; higher in development for local testing)
    register: {
      windowMs: 60 * 60 * 1000, // 1 hour
      max: NODE_ENV === 'development' ? 100 : 3
    },
    
    // Registration status lookup. Deliberately looser than `register`: a client
    // that timed out must be able to resolve the truth without being throttled
    // into showing a false failure. The endpoint creates nothing.
    registrationStatus: {
      windowMs: 60 * 60 * 1000, // 1 hour
      max: NODE_ENV === 'development' ? 300 : 60
    },

    // Password reset endpoint
    passwordReset: {
      windowMs: 60 * 60 * 1000, // 1 hour
      max: NODE_ENV === 'development' ? 100 : 3
    },
    
    // File upload endpoints
    upload: {
      windowMs: 60 * 60 * 1000, // 1 hour
      max: 10
    },
    
    // Search endpoints (higher limit for better UX)
    search: {
      windowMs: 60 * 1000, // 1 minute
      max: 60
    },

    // "Give us feedback" accepts anonymous submissions, so cap them per client.
    feedback: {
      windowMs: 60 * 60 * 1000, // 1 hour
      max: NODE_ENV === 'development' ? 300 : 30
    }
  },
  
  // Default window and max (used by defaultRateLimit middleware)
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: NODE_ENV === 'development' ? 1000 : 100
};

module.exports = RateLimitConfig;

