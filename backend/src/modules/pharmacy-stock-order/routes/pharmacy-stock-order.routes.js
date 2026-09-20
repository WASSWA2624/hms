/**
 * Pharmacy stock order routes
 *
 * @module modules/pharmacy-stock-order/routes
 * @description Express routes for the Hospital Pharmacy -> Main Pharmacy stock
 * ordering workflow.
 * Per api.mdc: All endpoints under /api/v1/pharmacy-stock-orders
 *
 * The route permission is the coarse gate. Which side of an order a caller may
 * act on - request and receive, or review and issue - is decided per order by
 * the pharmacy location grant inside the service.
 */

const express = require('express');
const { validateRequest } = require('@middlewares/validate.middleware');
const { authenticate, authorize } = require('@middlewares/auth.middleware');
const { PERMISSIONS } = require('@config/permissions');
const stockOrderController = require('@controllers/pharmacy-stock-order/pharmacy-stock-order.controller');
const {
  stockOrderIdParamsSchema,
  listStockOrdersQuerySchema,
  createStockOrderSchema,
  updateStockOrderSchema,
  reviewStockOrderSchema,
  issueStockOrderSchema,
  receiveStockOrderSchema,
  cancelStockOrderSchema,
} = require('@validations/pharmacy-stock-order/pharmacy-stock-order.schema');

const router = express.Router();

const READ_SCOPES = [PERMISSIONS.PHARMACY_READ, PERMISSIONS.OPERATIONS_READ];
const WRITE_SCOPES = [PERMISSIONS.PHARMACY_WRITE, PERMISSIONS.OPERATIONS_WRITE];

/**
 * @description List stock orders for the caller's pharmacies
 * @method GET
 * @route /api/v1/pharmacy-stock-orders
 * @authentication Required (JWT)
 * @permissions pharmacy:read or operations:read
 * @queryParams {string} [location_id] - Pharmacy whose queue to read
 * @queryParams {string} [queue] - INBOX (to supply), OUTBOX (raised), ALL
 * @queryParams {string} [status] - Filter by workflow status
 * @returns {Object} Paginated stock orders with their lines
 * @throws 401 Unauthorized
 */
router.get(
  '/',
  validateRequest({ query: listStockOrdersQuerySchema }),
  authenticate(),
  authorize(READ_SCOPES, 'permission'),
  stockOrderController.listStockOrders
);

/**
 * @description Raise a stock order against the supplying pharmacy
 * @method POST
 * @route /api/v1/pharmacy-stock-orders
 * @authentication Required (JWT)
 * @permissions pharmacy:write or operations:write
 * @bodyParams {string} requesting_location_id - Pharmacy asking for stock
 * @bodyParams {string} [supplying_location_id] - Defaults to its configured supplier
 * @bodyParams {Array} items - Lines of `{ drug_id, requested_quantity }`
 * @bodyParams {boolean} [submit] - Submit immediately instead of saving a draft
 * @returns {Object} Created order. Creating an order does not change stock.
 * @throws 400 No supplier configured for the requesting pharmacy
 * @throws 403 Caller has no grant on the requesting pharmacy
 */
router.post(
  '/',
  validateRequest({ body: createStockOrderSchema }),
  authenticate(),
  authorize(WRITE_SCOPES, 'permission'),
  stockOrderController.createStockOrder
);

/**
 * @description Submit a draft order for review
 * @method POST
 * @route /api/v1/pharmacy-stock-orders/:id/submit
 * @authentication Required (JWT)
 * @permissions pharmacy:write or operations:write
 * @urlParams {string} id - Order identifier
 * @returns {Object} Submitted order
 * @throws 400 Order is not a draft, or has no lines
 */
router.post(
  '/:id/submit',
  validateRequest({ params: stockOrderIdParamsSchema }),
  authenticate(),
  authorize(WRITE_SCOPES, 'permission'),
  stockOrderController.submitStockOrder
);

/**
 * @description Approve, partially approve or reject a submitted order
 * @method POST
 * @route /api/v1/pharmacy-stock-orders/:id/review
 * @authentication Required (JWT)
 * @permissions pharmacy:write or operations:write
 * @urlParams {string} id - Order identifier
 * @bodyParams {string} decision - APPROVE or REJECT
 * @bodyParams {Array} [items] - Per-line `approved_quantity` for partial approval
 * @returns {Object} Reviewed order. Review does not change stock.
 * @throws 403 Caller does not manage the supplying pharmacy
 */
router.post(
  '/:id/review',
  validateRequest({ params: stockOrderIdParamsSchema, body: reviewStockOrderSchema }),
  authenticate(),
  authorize(WRITE_SCOPES, 'permission'),
  stockOrderController.reviewStockOrder
);

/**
 * @description Issue approved stock out of the supplying pharmacy
 * @method POST
 * @route /api/v1/pharmacy-stock-orders/:id/issue
 * @authentication Required (JWT)
 * @permissions pharmacy:write or operations:write
 * @urlParams {string} id - Order identifier
 * @bodyParams {Array} [items] - Per-line `issued_quantity`
 * @returns {Object} Issued order. Reduces the supplying pharmacy's balance.
 * @throws 400 Order is not approved, or a line has no mapped inventory item
 * @throws 403 Caller does not manage the supplying pharmacy
 */
router.post(
  '/:id/issue',
  validateRequest({ params: stockOrderIdParamsSchema, body: issueStockOrderSchema }),
  authenticate(),
  authorize(WRITE_SCOPES, 'permission'),
  stockOrderController.issueStockOrder
);

/**
 * @description Receive issued stock into the requesting pharmacy
 * @method POST
 * @route /api/v1/pharmacy-stock-orders/:id/receive
 * @authentication Required (JWT)
 * @permissions pharmacy:write or operations:write
 * @urlParams {string} id - Order identifier
 * @bodyParams {Array} [items] - Per-line `received_quantity`
 * @returns {Object} Received order. Increases the requesting pharmacy's balance.
 * @throws 400 Order has not been issued
 * @throws 403 Caller has no grant on the requesting pharmacy
 */
router.post(
  '/:id/receive',
  validateRequest({ params: stockOrderIdParamsSchema, body: receiveStockOrderSchema }),
  authenticate(),
  authorize(WRITE_SCOPES, 'permission'),
  stockOrderController.receiveStockOrder
);

/**
 * @description Cancel an order that has not moved stock yet
 * @method POST
 * @route /api/v1/pharmacy-stock-orders/:id/cancel
 * @authentication Required (JWT)
 * @permissions pharmacy:write or operations:write
 * @urlParams {string} id - Order identifier
 * @returns {Object} Cancelled order
 * @throws 400 Stock has already been issued against this order
 */
router.post(
  '/:id/cancel',
  validateRequest({ params: stockOrderIdParamsSchema, body: cancelStockOrderSchema }),
  authenticate(),
  authorize(WRITE_SCOPES, 'permission'),
  stockOrderController.cancelStockOrder
);

/**
 * @description Get one stock order
 * @method GET
 * @route /api/v1/pharmacy-stock-orders/:id
 * @authentication Required (JWT)
 * @permissions pharmacy:read or operations:read
 * @urlParams {string} id - Order identifier
 * @returns {Object} Order with its lines
 * @throws 403 Caller's pharmacies are not a party to this order
 */
router.get(
  '/:id',
  validateRequest({ params: stockOrderIdParamsSchema }),
  authenticate(),
  authorize(READ_SCOPES, 'permission'),
  stockOrderController.getStockOrder
);

/**
 * @description Edit a draft order
 * @method PUT
 * @route /api/v1/pharmacy-stock-orders/:id
 * @authentication Required (JWT)
 * @permissions pharmacy:write or operations:write
 * @urlParams {string} id - Order identifier
 * @returns {Object} Updated order
 * @throws 400 Only draft orders are editable
 */
router.put(
  '/:id',
  validateRequest({ params: stockOrderIdParamsSchema, body: updateStockOrderSchema }),
  authenticate(),
  authorize(WRITE_SCOPES, 'permission'),
  stockOrderController.updateStockOrder
);

module.exports = router;
