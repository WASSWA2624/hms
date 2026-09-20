/**
 * Procedure service
 *
 * @module modules/procedure/services
 * @description Business logic layer for procedure operations.
 * Per module-creation.mdc: Services only import/use their own repository.
 * Per prisma.mdc: All mutations call createAuditLog.
 */

const prisma = require('@prisma/client');
const procedureRepository = require('@repositories/procedure/procedure.repository');
const { createAuditLog } = require('@lib/audit');
const { HttpError } = require('@lib/errors');
const {
  persistProcedureBilling,
  reverseClinicalRequestBilling,
  extractStoredClinicalBilling,
  buildProcedureBillingFromRequest} = require('@lib/billing/clinical-request-billing');
const { resolveModelIdByIdentifier } = require('@lib/identifiers/resolve-entity-id');

/**
 * Resolve an encounter UUID from either a UUID or a human-friendly id (ENC…).
 *
 * @param {string} identifier - Encounter UUID or human-friendly id
 * @returns {Promise<string|null>} Encounter UUID, or null when unresolvable
 */
const resolveEncounterId = async (identifier) => {
  const normalized = typeof identifier === 'string' ? identifier.trim() : '';
  if (!normalized) return null;
  return resolveModelIdByIdentifier({ model: 'encounter', identifier: normalized });
};

/**
 * List procedures with pagination and filtering
 *
 * @param {Object} filters - Query filters
 * @param {number} page - Page number
 * @param {number} limit - Items per page
 * @param {string} sortBy - Sort field
 * @param {string} order - Sort order
 * @param {string} userId - User ID for audit
 * @param {string} ipAddress - User IP for audit
 * @returns {Promise<Object>} Procedures and pagination data
 */
const listProcedures = async (filters, page, limit, sortBy, order, userId, ipAddress) => {
  try {
    const skip = (page - 1) * limit;
    const orderBy = sortBy ? { [sortBy]: order } : { created_at: 'desc' };

    // Build filter object
    const whereClause = {};
    
    if (filters.encounter_id) {
      // Fall back to the raw value when it cannot be resolved: it simply matches
      // no rows, rather than turning into an `IS NULL` filter.
      whereClause.encounter_id =
        (await resolveEncounterId(filters.encounter_id)) || filters.encounter_id;
    }
    if (filters.code) whereClause.code = { contains: filters.code };

    const [procedures, total] = await Promise.all([
      procedureRepository.findMany(whereClause, skip, limit, orderBy),
      procedureRepository.count(whereClause)
    ]);

    return {
      procedures,
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
        hasNextPage: page < Math.ceil(total / limit),
        hasPreviousPage: page > 1
      }
    };
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Get procedure by ID
 *
 * @param {string} id - Procedure ID
 * @param {string} userId - User ID for audit
 * @param {string} ipAddress - User IP for audit
 * @returns {Promise<Object>} Procedure data
 */
const getProcedureById = async (id, userId, ipAddress) => {
  try {
    const procedure = await procedureRepository.findById(id);

    if (!procedure) {
      throw new HttpError('errors.procedure.not_found', 404);
    }

    return procedure;
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Create new procedure
 * Per prisma.mdc: Mutations must create audit logs
 *
 * @param {Object} data - Procedure data
 * @param {string} userId - User ID for audit
 * @param {string} ipAddress - User IP for audit
 * @returns {Promise<Object>} Created procedure
 */
const createProcedure = async (data, userId, ipAddress) => {
  try {
    const { billing: requestBilling, ...procedureData } = data;
    procedureData.encounter_id = await resolveEncounterId(procedureData.encounter_id);
    if (!procedureData.encounter_id) {
      throw new HttpError('errors.encounter.not_found', 404, [{ field: 'encounter_id' }]);
    }
    const procedure = await procedureRepository.create(procedureData);

    const encounter = await prisma.encounter.findFirst({
      where: { id: procedureData.encounter_id, deleted_at: null },
      select: { id: true, tenant_id: true, facility_id: true, patient_id: true }});
    let billing = requestBilling;
    if (!billing && encounter) {
      billing = await buildProcedureBillingFromRequest({
        catalogItemId: procedureData.catalog_item_id || procedureData.code || null,
        code: procedureData.code || null,
        description: procedureData.description || 'Procedure',
        unitPrice: procedureData.unit_price || null,
        currency: procedureData.currency || 'USD',
        tenantId: encounter.tenant_id,
        facilityId: encounter.facility_id || null,
      });
    }
    if (billing && encounter) {
      await prisma.$transaction(async (tx) => {
        await persistProcedureBilling(tx, {
          procedureId: procedure.id,
          billing,
          tenantId: encounter.tenant_id,
          facilityId: encounter.facility_id || null,
          patientId: encounter.patient_id,
          description: `Procedure: ${procedureData.description || ''}`.trim()});
      });
    }

    // Create audit log (non-blocking)
    createAuditLog({
      user_id: userId,
      action: 'CREATE',
      entity: 'procedure',
      entity_id: procedure.id,
      diff: { after: procedure },
      ip_address: ipAddress
    }).catch(() => {});

    return procedure;
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Update procedure
 * Per prisma.mdc: Mutations must create audit logs
 *
 * @param {string} id - Procedure ID
 * @param {Object} data - Update data
 * @param {string} userId - User ID for audit
 * @param {string} ipAddress - User IP for audit
 * @returns {Promise<Object>} Updated procedure
 */
const updateProcedure = async (id, data, userId, ipAddress) => {
  try {
    // Get current state for audit
    const before = await procedureRepository.findById(id);

    if (!before) {
      throw new HttpError('errors.procedure.not_found', 404);
    }

    const procedure = await procedureRepository.update(id, data);

    // Create audit log (non-blocking)
    createAuditLog({
      user_id: userId,
      action: 'UPDATE',
      entity: 'procedure',
      entity_id: procedure.id,
      diff: { before, after: procedure },
      ip_address: ipAddress
    }).catch(() => {});

    return procedure;
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

/**
 * Delete procedure (soft delete)
 * Per prisma.mdc: Mutations must create audit logs
 *
 * @param {string} id - Procedure ID
 * @param {string} userId - User ID for audit
 * @param {string} ipAddress - User IP for audit
 * @returns {Promise<void>}
 */
const deleteProcedure = async (id, userId, ipAddress) => {
  try {
    // Get current state for audit
    const before = await procedureRepository.findById(id);

    if (!before) {
      throw new HttpError('errors.procedure.not_found', 404);
    }

    const existingSnapshot = extractStoredClinicalBilling(before);
    if (existingSnapshot?.invoice_id) {
      await prisma.$transaction(async (tx) => {
        await reverseClinicalRequestBilling(tx, { existingSnapshot });
      });
    }

    await procedureRepository.softDelete(id);

    // Create audit log (non-blocking)
    createAuditLog({
      user_id: userId,
      action: 'DELETE',
      entity: 'procedure',
      entity_id: id,
      diff: { before },
      ip_address: ipAddress
    }).catch(() => {});
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError('errors.server.unexpected', 500, [{ originalError: error.message }]);
  }
};

module.exports = {
  listProcedures,
  getProcedureById,
  createProcedure,
  updateProcedure,
  deleteProcedure
};
