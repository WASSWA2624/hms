/**
 * Feedback controller
 */

const feedbackService = require('@services/feedback/feedback.service');
const { asyncHandler } = require('@lib/async');
const { sendPaginated, sendSuccess } = require('@lib/response');

const buildFeedbackContext = (req) => ({
  user: req.user || null,
  user_id: req.user?.id || req.user?.user_id || null,
  tenant_id: req.user?.tenant_id || req.user?.tenantId || null,
  ip_address: req.ip,
  user_agent: req.get('user-agent') || null,
  locale: req.get('x-locale') || null,
  timezone: req.get('x-timezone') || null,
  platform: req.get('x-platform') || null
});

const submitNpsFeedback = asyncHandler(async (req, res) => {
  const result = await feedbackService.submitNpsFeedback(req.body, {
    user_id: req.user?.id,
    tenant_id: req.user?.tenant_id,
    ip_address: req.ip
  });

  sendSuccess(res, 201, 'messages.feedback.nps.success', result);
});

const submitCsatFeedback = asyncHandler(async (req, res) => {
  const result = await feedbackService.submitCsatFeedback(req.body, {
    user_id: req.user?.id,
    tenant_id: req.user?.tenant_id,
    ip_address: req.ip
  });

  sendSuccess(res, 201, 'messages.feedback.csat.success', result);
});

const submitFeedback = asyncHandler(async (req, res) => {
  const result = await feedbackService.submitFeedback(req.body, buildFeedbackContext(req));
  sendSuccess(res, 201, 'messages.feedback.submit.success', result);
});

const listFeedback = asyncHandler(async (req, res) => {
  const result = await feedbackService.listFeedback(req.query, buildFeedbackContext(req));
  sendPaginated(res, 'messages.feedback.list.success', result.items, result.pagination);
});

const getFeedbackSummary = asyncHandler(async (req, res) => {
  const result = await feedbackService.getFeedbackSummary(req.query, buildFeedbackContext(req));
  sendSuccess(res, 200, 'messages.feedback.summary.success', result);
});

const exportFeedback = asyncHandler(async (req, res) => {
  const result = await feedbackService.exportFeedback(req.query, buildFeedbackContext(req));
  res.setHeader('Content-Type', result.mime_type);
  res.setHeader('Content-Disposition', `attachment; filename="${result.file_name}"`);
  res.setHeader('Cache-Control', 'no-store');
  res.status(200).send(result.buffer);
});

const deleteFeedback = asyncHandler(async (req, res) => {
  const result = await feedbackService.deleteFeedback(req.body, buildFeedbackContext(req));
  sendSuccess(res, 200, 'messages.feedback.delete.success', result);
});

module.exports = {
  deleteFeedback,
  exportFeedback,
  getFeedbackSummary,
  listFeedback,
  submitCsatFeedback,
  submitFeedback,
  submitNpsFeedback
};
