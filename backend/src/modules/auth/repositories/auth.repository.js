/**
 * Auth repository
 *
 * @module modules/auth/repositories
 * @description Data access layer for authentication operations.
 * Special repository that works with user and user_session models.
 */

const prisma = require('@prisma/client');
const { HttpError } = require('@lib/errors');
const {
  buildRegistrationContactExtension,
} = require('@lib/tenant/resolve-tenant-contact');
const { resolvePlatformRole } = require('@lib/authorization/platform-access-catalog');
const crypto = require('crypto');

const userInclude = {
  profile: true,
  staff_profile: {
    select: {
      id: true,
      human_friendly_id: true,
      staff_number: true,
      position: true,
      practitioner_type: true,
    },
  },
  permissions: {
    where: { deleted_at: null },
    include: {
      permission: true,
    },
  },
  module_assignments: {
    where: { deleted_at: null },
    include: {
      module: true,
    },
  },
  roles: {
    where: { deleted_at: null },
    include: {
      role: {
        include: {
          permissions: {
            where: { deleted_at: null },
            include: {
              permission: true
            }
          }
        }
      }
    }
  }
};

const facilitySelect = {
  id: true,
  tenant_id: true,
  name: true,
  facility_type: true,
  is_active: true,
  deleted_at: true,
};

const tenantScopedUserInclude = {
  ...userInclude,
  tenant: true,
  facility: {
    select: facilitySelect
  }
};

const tenantScopedUserIncludeWithoutDirectPermissions = {
  profile: true,
  tenant: true,
  facility: {
    select: facilitySelect
  },
  roles: userInclude.roles
};

const minimalTenantScopedUserInclude = {
  profile: true,
  tenant: true,
  facility: {
    select: facilitySelect
  }
};

const sessionIncludeWithDirectPermissions = {
  user: {
    include: tenantScopedUserInclude
  }
};

const sessionIncludeWithoutDirectPermissions = {
  user: {
    include: tenantScopedUserIncludeWithoutDirectPermissions
  }
};

const minimalSessionInclude = {
  user: {
    include: minimalTenantScopedUserInclude
  }
};

const normalizeSlug = (value) =>
  String(value || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .replace(/-{2,}/g, '-');

const buildTenantSlug = (facilityName) => {
  const base = normalizeSlug(facilityName) || 'hms-tenant';
  const suffix = crypto.randomBytes(3).toString('hex');
  const maxBaseLength = 191 - suffix.length - 1;
  return `${base.slice(0, maxBaseLength)}-${suffix}`;
};

const splitAdminName = (value) => {
  const normalized = String(value || '').trim();
  if (!normalized) {
    return { first_name: 'Admin', last_name: null };
  }
  const [firstName, ...rest] = normalized.split(/\s+/);
  return {
    first_name: firstName || 'Admin',
    last_name: rest.length > 0 ? rest.join(' ') : null,
  };
};

/**
 * True when Prisma rejected a write because a column is absent from the client
 * or the database -- the shape a not-yet-applied migration takes.
 *
 * @param {Error} error - Prisma error
 * @returns {boolean} Whether the column is unknown
 */
const isUnknownColumnError = (error) => {
  const message = String(
    error?.message || error?.meta?.cause || error?.meta?.driverAdapterError?.message || ''
  );

  return (
    /Unknown arg(?:ument)? `[^`]+`/i.test(message) ||
    /Unknown field `[^`]+` for (?:data|select|create)/i.test(message) ||
    /Unknown column '[^']+'/i.test(message)
  );
};

const isMissingSchemaArtifactError = (error) => {
  if (error?.code === 'P2021' || error?.code === 'P2022') {
    return true;
  }

  const message = String(
    error?.message || error?.meta?.cause || error?.meta?.driverAdapterError?.message || ''
  );

  // Stale Prisma clients reject unknown include fields before hitting the DB.
  if (
    error?.name === 'PrismaClientValidationError' &&
    /Unknown field `[^`]+` for include statement/i.test(message)
  ) {
    return true;
  }

  // Driver adapters sometimes surface missing-table errors without P2021.
  return /does not exist in the current database/i.test(message);
};

const sortUsersByCreatedAtDesc = (users = []) => {
  return [...users].sort((left, right) => {
    const leftTs = left?.created_at ? new Date(left.created_at).getTime() : 0;
    const rightTs = right?.created_at ? new Date(right.created_at).getTime() : 0;
    return rightTs - leftTs;
  });
};

const RETRYABLE_CONNECTION_ERROR_CODES = new Set(['P1001', 'P1002', 'P2010', 'P2024']);
const RETRYABLE_CONNECTION_ERROR_PATTERN =
  /pool timeout|failed to retrieve a connection from pool|can'?t reach database server|econnrefused|timed out|protocol_connection_lost/i;
const CONNECTION_RETRY_ATTEMPTS = 3;

const getErrorFingerprint = (error) => {
  return [
    error?.message,
    error?.meta?.cause,
    error?.meta?.driverAdapterError?.message,
    error?.meta?.driverAdapterError?.cause?.message,
  ]
    .filter(Boolean)
    .join(' | ');
};

const isRetryableConnectionError = (error) => {
  const fingerprint = getErrorFingerprint(error);
  if (!RETRYABLE_CONNECTION_ERROR_PATTERN.test(fingerprint)) {
    return false;
  }

  const code = error?.code ? String(error.code).toUpperCase() : null;
  if (!code) {
    return true;
  }

  return RETRYABLE_CONNECTION_ERROR_CODES.has(code);
};

const waitFor = (ms) =>
  new Promise((resolve) => {
    setTimeout(resolve, ms);
  });

const withPrismaConnectionRetry = async (queryOperation) => {
  let latestError = null;

  for (let attempt = 1; attempt <= CONNECTION_RETRY_ATTEMPTS; attempt += 1) {
    try {
      return await queryOperation();
    } catch (error) {
      latestError = error;

      const shouldRetry =
        attempt < CONNECTION_RETRY_ATTEMPTS && isRetryableConnectionError(error);
      if (!shouldRetry) {
        throw error;
      }

      // Reset the pooled connection state before retrying a transient adapter timeout.
      try {
        await prisma.$disconnect();
      } catch {
        // Best-effort reset only.
      }
      try {
        await prisma.$connect();
      } catch {
        // The next operation attempt will surface the concrete error if it still fails.
      }

      await waitFor(200 * attempt);
    }
  }

  throw latestError;
};

const toRepositoryHttpError = (error, operation) => {
  throw new HttpError('errors.database.unexpected', 500, [{
    originalError: error?.message,
    errorCode: error?.code || null,
    errorName: error?.name || null,
    meta: error?.meta || null,
    operation,
  }]);
};

const findTenantScopedUserWithFallback = async (where, operation) => {
  const normalizedWhere = {
    ...where,
    deleted_at: null,
  };

  try {
    return await withPrismaConnectionRetry(() =>
      prisma.user.findFirst({
        where: normalizedWhere,
        include: tenantScopedUserInclude
      })
    );
  } catch (error) {
    if (!isMissingSchemaArtifactError(error)) {
      return toRepositoryHttpError(error, operation);
    }
  }

  try {
    return await withPrismaConnectionRetry(() =>
      prisma.user.findFirst({
        where: normalizedWhere,
        include: tenantScopedUserIncludeWithoutDirectPermissions
      })
    );
  } catch (fallbackError) {
    if (!isMissingSchemaArtifactError(fallbackError)) {
      return toRepositoryHttpError(fallbackError, operation);
    }
  }

  try {
    return await withPrismaConnectionRetry(() =>
      prisma.user.findFirst({
        where: normalizedWhere,
        include: minimalTenantScopedUserInclude
      })
    );
  } catch (minimalError) {
    return toRepositoryHttpError(minimalError, operation);
  }
};

/**
 * Find user by email and tenant
 *
 * @param {string} email - User email
 * @param {string} tenantId - Tenant ID
 * @returns {Promise<Object|null>} User object or null
 */
const findUserByEmailAndTenant = async (email, tenantId) => {
  return findTenantScopedUserWithFallback(
    {
      email,
      tenant_id: tenantId,
    },
    'findUserByEmailAndTenant'
  );
};

/**
 * Find user by phone and tenant
 *
 * @param {string} phone - User phone number
 * @param {string} tenantId - Tenant ID
 * @returns {Promise<Object|null>} User object or null
 */
const findUserByPhoneAndTenant = async (phone, tenantId) => {
  return findTenantScopedUserWithFallback(
    {
      phone,
      tenant_id: tenantId,
    },
    'findUserByPhoneAndTenant'
  );
};

/**
 * Find user by ID
 *
 * @param {string} id - User ID
 * @returns {Promise<Object|null>} User object or null
 */
const findUserById = async (id) => {
  return findTenantScopedUserWithFallback(
    { id },
    'findUserById'
  );
};

/**
 * Create new user
 *
 * @param {Object} data - User data
 * @returns {Promise<Object>} Created user
 */
const createUser = async (data) => {
  try {
    const normalizedPositionTitle =
      typeof data?.position_title === 'string' ? data.position_title.trim() : '';
    if (!normalizedPositionTitle) {
      throw new HttpError('errors.validation.field.required', 400, [{ field: 'position_title' }]);
    }

    return await prisma.user.create({
      data: {
        ...data,
        position_title: normalizedPositionTitle,
      },
      include: {
        profile: true
      }
    });
  } catch (error) {
    if (error.code === 'P2002') {
      throw new HttpError('errors.auth.user_exists', 409);
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Self-register facility owner and bootstrap tenant workspace.
 *
 * Tenant, facility, role, user, profile, role assignment, and the registration
 * attempt's email claim all commit or roll back together, so a failure part way
 * through can never leave an orphaned tenant or facility behind.
 *
 * @param {Object} data - Registration data
 * @param {string} [data.registration_attempt_id] - Attempt row that claims the email
 * @returns {Promise<Object>} Created user with tenant/facility/profile/roles
 */
const registerFacilityOwner = async (data) => {
  const {
    email,
    phone,
    password_hash,
    facility_name,
    tenant_name,
    facility_type,
    admin_name,
    status = 'ACTIVE',
    registration_attempt_id = null,
  } = data;
  const parsedName = splitAdminName(admin_name);
  const resolvedTenantName = String(tenant_name || facility_name || '').trim();

  try {
    return await prisma.$transaction(async (tx) => {
      const tenant = await tx.tenant.create({
        data: {
          name: resolvedTenantName,
          slug: buildTenantSlug(resolvedTenantName),
          is_active: true,
          extension_json: buildRegistrationContactExtension({
            admin_name,
            email,
            phone,
          }),
        },
      });

      const facility = await tx.facility.create({
        data: {
          tenant_id: tenant.id,
          name: facility_name,
          facility_type,
          is_active: true,
        },
      });

      // The owner holds the platform TENANT_ADMIN role, never a tenant copy of it.
      const role = await resolvePlatformRole('TENANT_ADMIN', tx);
      if (!role) {
        throw new HttpError('errors.role.not_found', 404);
      }

      const user = await tx.user.create({
        data: {
          tenant_id: tenant.id,
          facility_id: facility.id,
          position_title: 'OWNER',
          email,
          phone,
          password_hash,
          status,
        },
      });

      await tx.user_profile.create({
        data: {
          user_id: user.id,
          facility_id: facility.id,
          first_name: parsedName.first_name,
          last_name: parsedName.last_name,
        },
      });

      await tx.user_role.create({
        data: {
          user_id: user.id,
          role_id: role.id,
          tenant_id: tenant.id,
          facility_id: facility.id,
        },
      });

      if (registration_attempt_id) {
        // Inside the transaction on purpose: the unique index on
        // `claimed_email` is what stops a concurrent retry from bootstrapping a
        // second tenant, and a conflict here rolls the whole bootstrap back.
        await tx.registration_attempt.update({
          where: { id: registration_attempt_id },
          data: {
            claimed_email: email,
            user_id: user.id,
            tenant_id: tenant.id,
            facility_id: facility.id,
          },
        });
      }

      return tx.user.findFirst({
        where: {
          id: user.id,
          deleted_at: null,
        },
        include: {
          profile: true,
          tenant: true,
          facility: {
            select: facilitySelect
          },
          roles: {
            where: { deleted_at: null },
            include: { role: true },
          },
        },
      });
    });
  } catch (error) {
    if (error.code === 'P2002') {
      const target = Array.isArray(error.meta?.target) ? error.meta.target.join(',') : String(error.meta?.target || '');
      // Covers both `user(tenant_id, email)` and the registration email claim.
      if (target.toLowerCase().includes('email')) {
        throw new HttpError('errors.auth.user_exists', 409);
      }
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

// A registration attempt left IN_PROGRESS for longer than this lost its
// process (deploy, crash, killed container). The key is then reusable; the
// `claimed_email` unique index still prevents a double bootstrap if the
// original request is somehow alive.
const REGISTRATION_ATTEMPT_STALE_MS = 5 * 60 * 1000;

const getRegistrationAttemptDelegate = () => {
  const delegate = prisma?.registration_attempt;
  if (!delegate || typeof delegate.create !== 'function') {
    return null;
  }
  return delegate;
};

const isStaleInProgressAttempt = (attempt) => {
  if (!attempt || attempt.status !== 'IN_PROGRESS' || attempt.claimed_email) {
    return false;
  }
  const startedAt = attempt.started_at ? new Date(attempt.started_at).getTime() : 0;
  return Date.now() - startedAt > REGISTRATION_ATTEMPT_STALE_MS;
};

/**
 * Claim an idempotency key for a registration submission.
 *
 * @param {Object} data - Attempt data
 * @param {string} data.idempotency_key - Client-supplied key for this attempt
 * @param {string} data.email - Normalized registration email
 * @param {Date} data.expires_at - When the stored outcome stops being replayable
 * @param {string} [data.request_hash] - Hash of the submitted payload
 * @returns {Promise<{ attempt: Object, replayed: boolean }|null>} Claim result,
 *   or null when the table is not migrated yet
 */
const beginRegistrationAttempt = async ({
  idempotency_key,
  email,
  expires_at,
  request_hash = null,
}) => {
  const delegate = getRegistrationAttemptDelegate();
  if (!delegate) {
    return null;
  }

  try {
    const attempt = await delegate.create({
      data: {
        idempotency_key,
        email,
        request_hash,
        expires_at,
      },
    });
    return { attempt, replayed: false };
  } catch (error) {
    if (isMissingSchemaArtifactError(error)) {
      return null;
    }

    if (error?.code !== 'P2002') {
      throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
    }

    const existing = await delegate.findUnique({ where: { idempotency_key } });
    if (!existing) {
      // Lost the row between the conflict and the read; treat as unusable.
      return null;
    }

    if (!isStaleInProgressAttempt(existing)) {
      return { attempt: existing, replayed: true };
    }

    const reclaimed = await delegate.update({
      where: { id: existing.id },
      data: {
        email,
        request_hash,
        expires_at,
        started_at: new Date(),
        completed_at: null,
        outcome_code: null,
        error_status_code: null,
        error_code: null,
        result_json: null,
        email_status: 'PENDING',
      },
    });
    return { attempt: reclaimed, replayed: false };
  }
};

/**
 * Read a registration attempt by its idempotency key.
 *
 * @param {string} idempotencyKey - Key supplied when the attempt was submitted
 * @returns {Promise<Object|null>} Attempt row or null
 */
const findRegistrationAttemptByKey = async (idempotencyKey) => {
  const delegate = getRegistrationAttemptDelegate();
  if (!delegate) {
    return null;
  }

  try {
    return await delegate.findUnique({ where: { idempotency_key: idempotencyKey } });
  } catch (error) {
    if (isMissingSchemaArtifactError(error)) {
      return null;
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Record the final outcome of a registration attempt.
 *
 * @param {string} attemptId - Attempt row id
 * @param {Object} data - Outcome fields
 * @returns {Promise<Object|null>} Updated attempt row or null
 */
const completeRegistrationAttempt = async (attemptId, data = {}) => {
  const delegate = getRegistrationAttemptDelegate();
  if (!delegate || !attemptId) {
    return null;
  }

  try {
    return await delegate.update({
      where: { id: attemptId },
      data: {
        status: data.status,
        outcome_code: data.outcome_code || null,
        email_status: data.email_status || undefined,
        user_id: data.user_id || undefined,
        tenant_id: data.tenant_id || undefined,
        facility_id: data.facility_id || undefined,
        result_json: data.result_json === undefined ? undefined : data.result_json,
        error_status_code: data.error_status_code ?? null,
        error_code: data.error_code || null,
        completed_at: new Date(),
      },
    });
  } catch (error) {
    if (isMissingSchemaArtifactError(error) || error?.code === 'P2025') {
      return null;
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Record the final verification-email status for an attempt.
 *
 * Narrow on purpose: a background delivery settles after the response has been
 * sent and after `completeRegistrationAttempt` has written the outcome, so it
 * must touch `email_status` and nothing else.
 *
 * @param {string} attemptId - Attempt row id
 * @param {string} emailStatus - `SENT` or `FAILED`
 * @returns {Promise<Object|null>} Updated attempt, or null when unavailable
 */
const updateRegistrationAttemptEmailStatus = async (attemptId, emailStatus) => {
  const delegate = getRegistrationAttemptDelegate();
  if (!delegate || !attemptId || !emailStatus) {
    return null;
  }

  try {
    return await delegate.update({
      where: { id: attemptId },
      data: { email_status: emailStatus },
    });
  } catch (error) {
    if (isMissingSchemaArtifactError(error) || error?.code === 'P2025') {
      return null;
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Drop an attempt that failed for an infrastructure reason so the same key can
 * be retried.
 *
 * Deliberately a `deleteMany` filtered on `claimed_email: null`: an attempt
 * that already claimed an email owns a committed account, and dropping its row
 * would hand that email back and allow a second tenant.
 *
 * @param {string} attemptId - Attempt row id
 * @returns {Promise<void>}
 */
const releaseRegistrationAttempt = async (attemptId) => {
  const delegate = getRegistrationAttemptDelegate();
  if (!delegate || !attemptId) {
    return;
  }

  try {
    await delegate.deleteMany({ where: { id: attemptId, claimed_email: null } });
  } catch (error) {
    if (isMissingSchemaArtifactError(error) || error?.code === 'P2025') {
      return;
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Update user password
 *
 * @param {string} userId - User ID
 * @param {string} passwordHash - New password hash
 * @returns {Promise<Object>} Updated user
 */
const updateUserPassword = async (userId, passwordHash) => {
  try {
    return await prisma.user.update({
      where: { id: userId },
      data: {
        password_hash: passwordHash,
        updated_at: new Date()
      }
    });
  } catch (error) {
    if (error.code === 'P2025') {
      throw new HttpError('errors.auth.user_not_found', 404);
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Find enabled MFA configurations for a user.
 *
 * @param {string} userId - User ID
 * @returns {Promise<Array>} Enabled MFA rows
 */
const findEnabledUserMfas = async (userId) => {
  try {
    return await prisma.user_mfa.findMany({
      where: {
        user_id: userId,
        is_enabled: true,
        deleted_at: null,
      },
      orderBy: [{ last_used_at: 'desc' }, { created_at: 'desc' }],
    });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Update the last-used timestamp for an MFA configuration.
 *
 * @param {string} mfaId - MFA configuration ID
 * @returns {Promise<Object>} Updated MFA row
 */
const touchUserMfaLastUsed = async (mfaId) => {
  try {
    return await prisma.user_mfa.update({
      where: { id: mfaId },
      data: {
        last_used_at: new Date(),
        updated_at: new Date(),
      },
    });
  } catch (error) {
    if (error.code === 'P2025') {
      throw new HttpError('errors.user_mfa.not_found', 404);
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Create user session
 *
 * @param {Object} data - Session data
 * @returns {Promise<Object>} Created session
 */
const createSession = async (data) => {
  try {
    return await withPrismaConnectionRetry(() =>
      prisma.user_session.create({
        data
      })
    );
  } catch (error) {
    if (!isMissingSchemaArtifactError(error) && !isUnknownColumnError(error)) {
      throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
    }
  }

  // The lifetime-policy columns may not exist yet on a host that has the new
  // application code but not migration `20260911140000_session_lifetime_policy`.
  // Signing in must not fail for that: drop the anchors and let the session
  // fall back to the plain refresh TTL until the migration lands.
  const { chain_started_at: _chainStartedAt, last_used_at: _lastUsedAt, ...withoutLifetime } = data;

  try {
    return await withPrismaConnectionRetry(() =>
      prisma.user_session.create({
        data: withoutLifetime
      })
    );
  } catch (fallbackError) {
    throw new HttpError('errors.database.unexpected', 500, [
      { originalError: fallbackError.message }
    ]);
  }
};

/**
 * Find session by refresh token hash
 *
 * @param {string} refreshTokenHash - Refresh token hash
 * @returns {Promise<Object|null>} Session object or null
 */
const findSessionByRefreshToken = async (refreshTokenHash) => {
  const where = {
    refresh_token_hash: refreshTokenHash,
    revoked_at: null,
    deleted_at: null,
    expires_at: {
      gt: new Date()
    }
  };

  try {
    return await withPrismaConnectionRetry(() =>
      prisma.user_session.findFirst({
        where,
        include: sessionIncludeWithDirectPermissions
      })
    );
  } catch (error) {
    if (!isMissingSchemaArtifactError(error)) {
      throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
    }
  }

  try {
    return await withPrismaConnectionRetry(() =>
      prisma.user_session.findFirst({
        where,
        include: sessionIncludeWithoutDirectPermissions
      })
    );
  } catch (fallbackError) {
    if (!isMissingSchemaArtifactError(fallbackError)) {
      throw new HttpError('errors.database.unexpected', 500, [{ originalError: fallbackError.message }]);
    }
  }

  try {
    return await withPrismaConnectionRetry(() =>
      prisma.user_session.findFirst({
        where,
        include: minimalSessionInclude
      })
    );
  } catch (minimalError) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: minimalError.message }]);
  }
};

/**
 * Revoke user session
 *
 * @param {string} sessionId - Session ID
 * @returns {Promise<Object>} Updated session
 */
const revokeSession = async (sessionId) => {
  try {
    return await prisma.user_session.update({
      where: { id: sessionId },
      data: {
        revoked_at: new Date(),
        updated_at: new Date()
      }
    });
  } catch (error) {
    if (error.code === 'P2025') {
      throw new HttpError('errors.auth.session_not_found', 404);
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Revoke all user sessions
 *
 * @param {string} userId - User ID
 * @returns {Promise<Object>} Update result
 */
const revokeAllUserSessions = async (userId) => {
  try {
    return await prisma.user_session.updateMany({
      where: {
        user_id: userId,
        revoked_at: null,
        deleted_at: null
      },
      data: {
        revoked_at: new Date(),
        updated_at: new Date()
      }
    });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Create verification token
 *
 * @param {Object} data - Token data
 * @returns {Promise<Object>} Created token
 */
const createVerificationToken = async (data) => {
  try {
    return await prisma.verification_token.create({
      data
    });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Find verification token by hash and type
 *
 * @param {string} tokenHash - Token hash
 * @param {string} type - Token type (EMAIL_VERIFICATION, PHONE_VERIFICATION, PASSWORD_RESET)
 * @returns {Promise<Object|null>} Token object or null
 */
const findVerificationToken = async (tokenHash, type) => {
  try {
    return await prisma.verification_token.findFirst({
      where: {
        token_hash: tokenHash,
        type,
        used_at: null,
        deleted_at: null,
        expires_at: {
          gt: new Date()
        }
      },
      include: {
        user: true
      }
    });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Mark verification token as used
 *
 * @param {string} tokenId - Token ID
 * @returns {Promise<Object>} Updated token
 */
const markTokenAsUsed = async (tokenId) => {
  try {
    return await prisma.verification_token.update({
      where: { id: tokenId },
      data: {
        used_at: new Date(),
        updated_at: new Date()
      }
    });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Atomically claim an unused, unexpired verification token.
 *
 * The conditional update succeeds for exactly one caller, so two concurrent
 * submissions of the same reset link or code cannot both change the password.
 *
 * @param {string} tokenId - Token ID
 * @returns {Promise<boolean>} True when this call claimed the token
 */
const consumeVerificationToken = async (tokenId) => {
  try {
    const now = new Date();
    const result = await prisma.verification_token.updateMany({
      where: {
        id: tokenId,
        used_at: null,
        deleted_at: null,
        expires_at: { gt: now }
      },
      data: {
        used_at: now,
        updated_at: now
      }
    });
    return result?.count === 1;
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Delete expired verification tokens for user
 *
 * @param {string} userId - User ID
 * @param {string} type - Token type
 * @returns {Promise<Object>} Delete result
 */
const deleteExpiredTokens = async (userId, type) => {
  try {
    return await prisma.verification_token.updateMany({
      where: {
        user_id: userId,
        type,
        deleted_at: null
      },
      data: {
        deleted_at: new Date(),
        updated_at: new Date()
      }
    });
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Create or update registration follow-up tracking profile.
 *
 * @param {Object} data - Tracking data
 * @returns {Promise<Object|null>} Upserted profile or null when model not available
 */
const upsertRegistrationFollowUp = async (data) => {
  const delegate = prisma?.registration_follow_up;
  if (!delegate || typeof delegate.upsert !== 'function') {
    return null;
  }

  const parsedIncrement = Number(data?.registration_attempt_increment);
  const attemptsIncrement = Number.isFinite(parsedIncrement) ? Math.trunc(parsedIncrement) : 1;
  const createAttempts = attemptsIncrement > 0 ? attemptsIncrement : 1;
  const shouldIncrementAttempts = attemptsIncrement > 0;
  const now = new Date();

  const payload = {
    tenant_id: data?.tenant_id || null,
    facility_id: data?.facility_id || null,
    email: data?.email,
    phone: data?.phone || null,
    admin_name: data?.admin_name || null,
    facility_name: data?.facility_name || null,
    facility_type: data?.facility_type || null,
    location: data?.location || null,
    interests: data?.interests || null,
    account_status: data?.account_status,
    locale: data?.locale || null,
    timezone: data?.timezone || null,
    ip_address: data?.ip_address || null,
    user_agent: data?.user_agent || null,
    device_platform: data?.device_platform || null,
    referral_source: data?.referral_source || null,
    campaign: data?.campaign || null,
    follow_up_metadata: data?.follow_up_metadata || null,
  };

  try {
    return await delegate.upsert({
      where: { user_id: data.user_id },
      create: {
        ...payload,
        user_id: data.user_id,
        registration_attempts: createAttempts,
        first_registered_at: now,
        last_registration_attempt_at: now,
      },
      update: {
        ...payload,
        last_registration_attempt_at: now,
        updated_at: now,
        ...(shouldIncrementAttempts
          ? {
              registration_attempts: {
                increment: attemptsIncrement,
              },
            }
          : {}),
      },
    });
  } catch (error) {
    if (error?.code === 'P2021' || error?.code === 'P2022') {
      // Table/column may be missing before migration is applied.
      return null;
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Update registration follow-up account status without mutating other profile fields.
 *
 * @param {string} userId - User ID
 * @param {string} accountStatus - User status enum value
 * @returns {Promise<Object|null>} Update result or null when model not available
 */
const updateRegistrationFollowUpStatus = async (userId, accountStatus) => {
  const delegate = prisma?.registration_follow_up;
  if (!delegate || typeof delegate.updateMany !== 'function') {
    return null;
  }

  try {
    return await delegate.updateMany({
      where: {
        user_id: userId,
        deleted_at: null,
      },
      data: {
        account_status: accountStatus,
        updated_at: new Date(),
      },
    });
  } catch (error) {
    if (error?.code === 'P2021' || error?.code === 'P2022') {
      return null;
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Update user status
 *
 * @param {string} userId - User ID
 * @param {string} status - New status
 * @returns {Promise<Object>} Updated user
 */
const updateUserStatus = async (userId, status) => {
  try {
    return await prisma.user.update({
      where: { id: userId },
      data: {
        status,
        updated_at: new Date()
      }
    });
  } catch (error) {
    if (error.code === 'P2025') {
      throw new HttpError('errors.auth.user_not_found', 404);
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Mark a user's email as verified without activating the account.
 *
 * @param {string} userId - User ID
 * @returns {Promise<Object>} Updated user
 */
const markEmailVerified = async (userId) => {
  try {
    return await prisma.user.update({
      where: { id: userId },
      data: {
        email_verified_at: new Date(),
        updated_at: new Date(),
      },
    });
  } catch (error) {
    if (error.code === 'P2025') {
      throw new HttpError('errors.auth.user_not_found', 404);
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * List registrations awaiting platform approval.
 *
 * @param {Object} options
 * @param {number} options.skip
 * @param {number} options.take
 * @param {string} [options.search]
 * @returns {Promise<{ items: Array<Object>, total: number }>}
 */
const findPendingRegistrationApprovals = async ({ skip = 0, take = 20, search = '' } = {}) => {
  const delegate = prisma?.registration_follow_up;
  if (!delegate || typeof delegate.findMany !== 'function') {
    return { items: [], total: 0 };
  }

  const term = String(search || '').trim();
  const where = {
    deleted_at: null,
    account_status: 'PENDING',
    user: {
      deleted_at: null,
      status: 'PENDING',
      email_verified_at: { not: null },
    },
  };

  if (term) {
    where.OR = [
      { email: { contains: term } },
      { phone: { contains: term } },
      { admin_name: { contains: term } },
      { facility_name: { contains: term } },
      { human_friendly_id: { contains: term } },
    ];
  }

  try {
    const [items, total] = await Promise.all([
      delegate.findMany({
        where,
        skip,
        take,
        orderBy: { first_registered_at: 'desc' },
        include: {
          user: {
            include: {
              tenant: true,
              facility: true,
              profile: true,
            },
          },
          tenant: true,
          facility: true,
        },
      }),
      delegate.count({ where }),
    ]);

    return { items, total };
  } catch (error) {
    if (error?.code === 'P2021' || error?.code === 'P2022') {
      return { items: [], total: 0 };
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Find user by email
 *
 * @param {string} email - User email
 * @returns {Promise<Object|null>} User object or null
 */
const findUserByEmail = async (email) => {
  try {
    return await withPrismaConnectionRetry(() =>
      prisma.user.findFirst({
        where: {
          email,
          deleted_at: null
        },
        include: {
          profile: true,
          tenant: true,
          facility: {
            select: facilitySelect
          }
        }
      })
    );
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{
      originalError: error.message,
      errorCode: error?.code || null,
      errorName: error?.name || null,
      meta: error?.meta || null,
      operation: 'findUsersByIdentifier',
    }]);
  }
};

/**
 * Find user by phone
 *
 * @param {string} phone - User phone
 * @returns {Promise<Object|null>} User object or null
 */
const findUserByPhone = async (phone) => {
  try {
    return await withPrismaConnectionRetry(() =>
      prisma.user.findFirst({
        where: {
          phone,
          deleted_at: null
        },
        include: {
          profile: true,
          tenant: true,
          facility: {
            select: facilitySelect
          }
        }
      })
    );
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Find all users by identifier (email or phone) across all tenants
 *
 * @param {string} identifier - User email or phone
 * @returns {Promise<Array>} Array of user objects with tenant info
 */
const findUsersByIdentifier = async (identifier) => {
  const normalizedIdentifier = String(identifier || '').trim();
  const isEmail = normalizedIdentifier.includes('@');
  const baseWhere = isEmail
    ? { email: normalizedIdentifier.toLowerCase() }
    : { phone: normalizedIdentifier };
  const findManyWithRetry = (args) =>
    withPrismaConnectionRetry(() => prisma.user.findMany(args));

  try {
    const users = await findManyWithRetry({
      where: {
        ...baseWhere,
        deleted_at: null
      },
      include: {
        tenant: {
          select: {
            id: true,
            name: true,
            slug: true,
            deleted_at: true,
          }
        }
      },
      orderBy: {
        created_at: 'desc'
      }
    });

    return users;
  } catch (error) {
    if (isMissingSchemaArtifactError(error)) {
      try {
        const legacyUsers = await findManyWithRetry({
          where: baseWhere,
          include: {
            tenant: {
              select: {
                id: true,
                name: true,
                deleted_at: true,
              }
            }
          }
        });

        const filteredLegacyUsers = legacyUsers.filter((user) =>
          !Object.prototype.hasOwnProperty.call(user, 'deleted_at') || user.deleted_at === null
        );

        return sortUsersByCreatedAtDesc(filteredLegacyUsers);
      } catch (legacyError) {
        if (isMissingSchemaArtifactError(legacyError)) {
          try {
            const minimalUsers = await findManyWithRetry({
              where: baseWhere,
            });

            const filteredMinimalUsers = minimalUsers.filter((user) =>
              !Object.prototype.hasOwnProperty.call(user, 'deleted_at') || user.deleted_at === null
            );

            return sortUsersByCreatedAtDesc(filteredMinimalUsers);
          } catch (minimalError) {
            throw new HttpError('errors.database.unexpected', 500, [{ originalError: minimalError.message }]);
          }
        }
        throw new HttpError('errors.database.unexpected', 500, [{ originalError: legacyError.message }]);
      }
    }
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Get all facilities accessible to a user within a tenant
 *
 * @param {string} userId - User ID
 * @param {string} tenantId - Tenant ID
 * @returns {Promise<Array>} Array of facility objects
 */
const getUserFacilities = async (userId, tenantId) => {
  try {
    // Get user's direct facility
    const user = await prisma.user.findFirst({
      where: {
        id: userId,
        tenant_id: tenantId,
        deleted_at: null
      },
      select: {
        facility_id: true
      }
    });

    const facilityIds = new Set();

    // Add user's direct facility if exists
    if (user?.facility_id) {
      facilityIds.add(user.facility_id);
    }

    // Get facility IDs from user roles (both from role.facility_id and user_role.facility_id)
    const userRoles = await prisma.user_role.findMany({
      where: {
        user_id: userId,
        tenant_id: tenantId,
        deleted_at: null
      },
      include: {
        role: true
      }
    });

    // Collect facility IDs from roles and user_role entries
    userRoles.forEach(ur => {
      if (ur.facility_id) {
        facilityIds.add(ur.facility_id);
      }
      if (ur.role?.facility_id) {
        facilityIds.add(ur.role.facility_id);
      }
    });

    // If no facilities found, return empty array
    if (facilityIds.size === 0) {
      return [];
    }

    // Fetch all unique facilities
    const facilities = await prisma.facility.findMany({
      where: {
        id: { in: Array.from(facilityIds) },
        tenant_id: tenantId,
        deleted_at: null,
        is_active: true
      },
      select: facilitySelect
    });

    return facilities;
  } catch (error) {
    throw new HttpError('errors.database.unexpected', 500, [{ originalError: error.message }]);
  }
};

module.exports = {
  findUserByEmailAndTenant,
  findUserByPhoneAndTenant,
  findUserById,
  findUserByEmail,
  findUserByPhone,
  findUsersByIdentifier,
  getUserFacilities,
  createUser,
  registerFacilityOwner,
  beginRegistrationAttempt,
  findRegistrationAttemptByKey,
  completeRegistrationAttempt,
  updateRegistrationAttemptEmailStatus,
  releaseRegistrationAttempt,
  updateUserPassword,
  findEnabledUserMfas,
  touchUserMfaLastUsed,
  updateUserStatus,
  markEmailVerified,
  findPendingRegistrationApprovals,
  createSession,
  findSessionByRefreshToken,
  revokeSession,
  revokeAllUserSessions,
  createVerificationToken,
  findVerificationToken,
  markTokenAsUsed,
  consumeVerificationToken,
  deleteExpiredTokens,
  upsertRegistrationFollowUp,
  updateRegistrationFollowUpStatus,
};
