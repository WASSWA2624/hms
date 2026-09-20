/**
 * Pharmacy stock order controller
 *
 * @module modules/pharmacy-stock-order/controllers
 * @description HTTP handlers for the Hospital Pharmacy -> Main Pharmacy stock
 * ordering workflow.
 * Per module-creation.mdc: Controllers handle HTTP, call services, return responses.
 */

const stockOrderService = require('@services/pharmacy-stock-order/pharmacy-stock-order.service');
const { asyncHandler } = require('@lib/async');
const { sendSuccess, sendPaginated, sendCreated } = require('@lib/response');

const listStockOrders = asyncHandler(async (req, res) => {
  const { page, limit, sort_by, order, ...filters } = req.query;

  const result = await stockOrderService.listStockOrders(
    filters,
    { page: parseInt(page, 10) || 1, limit: parseInt(limit, 10) || 20 },
    { sort_by, order },
    req.user || {}
  );

  sendPaginated(res, 'messages.pharmacy_stock_order.list_retrieved', result.data, {
    page: result.page,
    limit: result.limit,
    total: result.total,
    totalPages: result.totalPages,
    hasNextPage: result.hasNextPage,
    hasPreviousPage: result.hasPreviousPage,
  });
});

const getStockOrder = asyncHandler(async (req, res) => {
  const order = await stockOrderService.getStockOrder(req.params.id, req.user || {});
  sendSuccess(res, 200, 'messages.pharmacy_stock_order.retrieved', order);
});

const createStockOrder = asyncHandler(async (req, res) => {
  const order = await stockOrderService.createStockOrder(req.body, req.user || {}, req.ip);
  sendCreated(res, 'messages.pharmacy_stock_order.created', order);
});

const updateStockOrder = asyncHandler(async (req, res) => {
  const order = await stockOrderService.updateStockOrder(
    req.params.id,
    req.body,
    req.user || {},
    req.ip
  );
  sendSuccess(res, 200, 'messages.pharmacy_stock_order.updated', order);
});

const submitStockOrder = asyncHandler(async (req, res) => {
  const order = await stockOrderService.submitStockOrder(req.params.id, req.user || {}, req.ip);
  sendSuccess(res, 200, 'messages.pharmacy_stock_order.submitted', order);
});

const reviewStockOrder = asyncHandler(async (req, res) => {
  const order = await stockOrderService.reviewStockOrder(
    req.params.id,
    req.body,
    req.user || {},
    req.ip
  );
  sendSuccess(res, 200, 'messages.pharmacy_stock_order.reviewed', order);
});

const issueStockOrder = asyncHandler(async (req, res) => {
  const order = await stockOrderService.issueStockOrder(
    req.params.id,
    req.body,
    req.user || {},
    req.ip
  );
  sendSuccess(res, 200, 'messages.pharmacy_stock_order.issued', order);
});

const receiveStockOrder = asyncHandler(async (req, res) => {
  const order = await stockOrderService.receiveStockOrder(
    req.params.id,
    req.body,
    req.user || {},
    req.ip
  );
  sendSuccess(res, 200, 'messages.pharmacy_stock_order.received', order);
});

const cancelStockOrder = asyncHandler(async (req, res) => {
  const order = await stockOrderService.cancelStockOrder(
    req.params.id,
    req.body,
    req.user || {},
    req.ip
  );
  sendSuccess(res, 200, 'messages.pharmacy_stock_order.cancelled', order);
});

module.exports = {
  listStockOrders,
  getStockOrder,
  createStockOrder,
  updateStockOrder,
  submitStockOrder,
  reviewStockOrder,
  issueStockOrder,
  receiveStockOrder,
  cancelStockOrder,
};
