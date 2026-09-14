/**
 * Root Router
 *
 * Health endpoints are at root level (not under /api/v1/)
 * Per health-checks.md: Health endpoints are public at root level
 * Per api-versioning.md: All API endpoints must be versioned under /api/v1/
 */

const express = require('express');
const router = express.Router();

// Health check utilities
const { healthCheck, readinessCheck, livenessCheck } = require('@lib/health');
const { asyncHandler } = require('@lib/async');
const { authenticate } = require('@middlewares/auth.middleware');
const { hydrateRequestScope, enforceTenantScope } = require('@middlewares/tenant-scope.middleware');
const { hydrateRequestContext } = require('@middlewares/request-context.middleware');
const { enforceModuleEntitlement } = require('@middlewares/module-entitlement.middleware');
const { enforceAbacAccess } = require('@middlewares/abac.middleware');

/**
 * @description Health check endpoint (public)
 * @method GET
 * @route /health
 * @authentication None
 * @permissions Public
 * @urlParams None
 * @queryParams None
 * @bodyParams None
 * @returns {Object} Health status payload
 * @throws 503 Service unavailable
 */
router.get('/health', (req, res) => {
  const health = healthCheck();
  const statusCode = health.status === 'healthy' ? 200 : 503;
  return res.status(statusCode).json(health);
});

/**
 * @description Readiness check endpoint (public)
 * @method GET
 * @route /ready
 * @authentication None
 * @permissions Public
 * @urlParams None
 * @queryParams None
 * @bodyParams None
 * @returns {Object} Readiness status payload
 * @throws 503 Service unavailable
 */
router.get('/ready', asyncHandler(async (req, res) => {
  const readiness = await readinessCheck();
  const statusCode = readiness.status === 'ready' ? 200 : 503;
  return res.status(statusCode).json(readiness);
}));

/**
 * @description Liveness check endpoint (public)
 * @method GET
 * @route /live
 * @authentication None
 * @permissions Public
 * @urlParams None
 * @queryParams None
 * @bodyParams None
 * @returns {Object} Liveness status payload
 */
router.get('/live', (req, res) => {
  const liveness = livenessCheck();
  return res.status(200).json(liveness);
});

/**
 * API v1 Router
 * Per api-versioning.mdc: All API endpoints must be versioned
 * Per module-creation.mdc: Modules are mounted under /api/v1/<module>
 */
const apiV1Router = express.Router();

/**
 * Lazily mount a module's route tree.
 *
 * Requiring every module route tree at boot also pulls in that module's
 * controllers, services, repositories and schemas, so the whole codebase is
 * resident before the server can listen. Deferring each require() to the
 * module's first request keeps startup memory proportional to the routes
 * actually exercised, which matters on memory-capped hosts.
 */
const lazyRoutes = (modulePath) => {
  let routes = null;

  return (req, res, next) => {
    if (!routes) {
      routes = require(modulePath);
    }

    return routes(req, res, next);
  };
};

// Mount module routes under /api/v1/
// Per module-creation.mdc step 7: Use relative paths to mount modules
apiV1Router.use('/auth', lazyRoutes('../modules/auth/routes/auth.routes'));
apiV1Router.use('/public', lazyRoutes('../modules/public/routes/public.routes'));
// "Give us feedback" must work signed out, so these routes authenticate per
// route. Unmatched /feedback paths fall through to the protected router below.
apiV1Router.use('/feedback', lazyRoutes('../modules/feedback/routes/app-feedback.routes'));

// Global protection for all non-auth API v1 routes.
apiV1Router.use(authenticate());
apiV1Router.use(hydrateRequestScope());
apiV1Router.use(enforceTenantScope());
apiV1Router.use(hydrateRequestContext());
apiV1Router.use(require('../middlewares/live-access.middleware').hydrateLiveAccess());
apiV1Router.use(enforceModuleEntitlement());
apiV1Router.use(enforceAbacAccess());

apiV1Router.use('/user-sessions', lazyRoutes('../modules/user-session/routes/user-session.routes'));
apiV1Router.use('/tenants', lazyRoutes('../modules/tenant/routes/tenant.routes'));
apiV1Router.use('/facilities', lazyRoutes('../modules/facility/routes/facility.routes'));
apiV1Router.use('/departments', lazyRoutes('../modules/department/routes/department.routes'));
apiV1Router.use('/units', lazyRoutes('../modules/unit/routes/unit.routes'));
apiV1Router.use('/rooms', lazyRoutes('../modules/room/routes/room.routes'));
apiV1Router.use('/wards', lazyRoutes('../modules/ward/routes/ward.routes'));
apiV1Router.use('/beds', lazyRoutes('../modules/bed/routes/bed.routes'));
apiV1Router.use('/addresses', lazyRoutes('../modules/address/routes/address.routes'));
apiV1Router.use('/contacts', lazyRoutes('../modules/contact/routes/contact.routes'));
apiV1Router.use('/users', lazyRoutes('../modules/user/routes/user.routes'));
apiV1Router.use('/user-profiles', lazyRoutes('../modules/user-profile/routes/user-profile.routes'));
apiV1Router.use('/roles', lazyRoutes('../modules/role/routes/role.routes'));
apiV1Router.use('/permissions', lazyRoutes('../modules/permission/routes/permission.routes'));
apiV1Router.use('/role-permissions', lazyRoutes('../modules/role-permission/routes/role-permission.routes'));
apiV1Router.use('/user-roles', lazyRoutes('../modules/user-role/routes/user-role.routes'));
apiV1Router.use('/user-mfas', lazyRoutes('../modules/user-mfa/routes/user-mfa.routes'));
apiV1Router.use('/oauth-accounts', lazyRoutes('../modules/oauth-account/routes/oauth-account.routes'));
apiV1Router.use('/api-keys', lazyRoutes('../modules/api-key/routes/api-key.routes'));
apiV1Router.use('/api-key-permissions', lazyRoutes('../modules/api-key-permission/routes/api-key-permission.routes'));
apiV1Router.use('/abac-policies', lazyRoutes('../modules/abac-policy/routes/abac-policy.routes'));
apiV1Router.use('/patients', lazyRoutes('../modules/patient/routes/patient.routes'));
apiV1Router.use('/patient-identifiers', lazyRoutes('../modules/patient-identifier/routes/patient-identifier.routes'));
apiV1Router.use('/patient-contacts', lazyRoutes('../modules/patient-contact/routes/patient-contact.routes'));
apiV1Router.use('/patient-guardians', lazyRoutes('../modules/patient-guardian/routes/patient-guardian.routes'));
apiV1Router.use('/patient-allergies', lazyRoutes('../modules/patient-allergy/routes/patient-allergy.routes'));
apiV1Router.use('/patient-medical-histories', lazyRoutes('../modules/patient-medical-history/routes/patient-medical-history.routes'));
apiV1Router.use('/patient-reports', lazyRoutes('../modules/patient-report/routes/patient-report.routes'));
apiV1Router.use('/consents', lazyRoutes('../modules/consent/routes/consent.routes'));
apiV1Router.use('/terms-acceptances', lazyRoutes('../modules/terms-acceptance/routes/terms-acceptance.routes'));
apiV1Router.use('/appointments', lazyRoutes('../modules/appointment/routes/appointment.routes'));
apiV1Router.use('/appointment-participants', lazyRoutes('../modules/appointment-participant/routes/appointment-participant.routes'));
apiV1Router.use('/appointment-reminders', lazyRoutes('../modules/appointment-reminder/routes/appointment-reminder.routes'));
apiV1Router.use('/provider-schedules', lazyRoutes('../modules/provider-schedule/routes/provider-schedule.routes'));
apiV1Router.use('/availability-slots', lazyRoutes('../modules/availability-slot/routes/availability-slot.routes'));
apiV1Router.use('/scheduling', lazyRoutes('../modules/scheduling-workspace/routes/scheduling-workspace.routes'));
apiV1Router.use('/doctors', lazyRoutes('../modules/doctor/routes/doctor.routes'));
apiV1Router.use('/admissions', lazyRoutes('../modules/admission/routes/admission.routes'));
apiV1Router.use('/bed-assignments', lazyRoutes('../modules/bed-assignment/routes/bed-assignment.routes'));
apiV1Router.use('/ward-rounds', lazyRoutes('../modules/ward-round/routes/ward-round.routes'));
apiV1Router.use('/visit-queues', lazyRoutes('../modules/visit-queue/routes/visit-queue.routes'));
apiV1Router.use('/triage', lazyRoutes('../modules/triage/routes/triage.routes'));
apiV1Router.use('/opd-flows', lazyRoutes('../modules/opd-flow/routes/opd-flow.routes'));
apiV1Router.use('/ipd-flows', lazyRoutes('../modules/ipd-flow/routes/ipd-flow.routes'));
apiV1Router.use('/referrals', lazyRoutes('../modules/referral/routes/referral.routes'));
apiV1Router.use('/campaigns', lazyRoutes('../modules/campaign/routes/campaign.routes'));
apiV1Router.use('/feedback', lazyRoutes('../modules/feedback/routes/feedback.routes'));
apiV1Router.use('/follow-ups', lazyRoutes('../modules/follow-up/routes/follow-up.routes'));
apiV1Router.use('/vital-signs', lazyRoutes('../modules/vital-sign/routes/vital-sign.routes'));
apiV1Router.use('/care-plans', lazyRoutes('../modules/care-plan/routes/care-plan.routes'));
apiV1Router.use('/clinical-alerts', lazyRoutes('../modules/clinical-alert/routes/clinical-alert.routes'));
apiV1Router.use('/clinical-alert-thresholds', lazyRoutes('../modules/clinical-alert-threshold/routes/clinical-alert-threshold.routes'));
apiV1Router.use('/clinical-terms', lazyRoutes('../modules/clinical-term/routes/clinical-term.routes'));
apiV1Router.use('/clinical-catalog', lazyRoutes('../modules/clinical-term/routes/clinical-catalog.routes'));
apiV1Router.use('/clinical-term-favorites', lazyRoutes('../modules/clinical-term/routes/clinical-term-favorite.routes'));
apiV1Router.use('/encounters', lazyRoutes('../modules/encounter/routes/encounter.routes'));
apiV1Router.use('/clinical-notes', lazyRoutes('../modules/clinical-note/routes/clinical-note.routes'));
apiV1Router.use('/diagnoses', lazyRoutes('../modules/diagnosis/routes/diagnosis.routes'));
apiV1Router.use('/procedures', lazyRoutes('../modules/procedure/routes/procedure.routes'));
apiV1Router.use('/nursing-notes', lazyRoutes('../modules/nursing-note/routes/nursing-note.routes'));
apiV1Router.use('/medication-administrations', lazyRoutes('../modules/medication-administration/routes/medication-administration.routes'));
apiV1Router.use('/discharge-summaries', lazyRoutes('../modules/discharge-summary/routes/discharge-summary.routes'));
apiV1Router.use('/transfer-requests', lazyRoutes('../modules/transfer-request/routes/transfer-request.routes'));
apiV1Router.use('/icu-stays', lazyRoutes('../modules/icu-stay/routes/icu-stay.routes'));
apiV1Router.use('/icu-observations', lazyRoutes('../modules/icu-observation/routes/icu-observation.routes'));
apiV1Router.use('/critical-alerts', lazyRoutes('../modules/critical-alert/routes/critical-alert.routes'));
apiV1Router.use('/theatre-cases', lazyRoutes('../modules/theatre-case/routes/theatre-case.routes'));
apiV1Router.use('/anesthesia-records', lazyRoutes('../modules/anesthesia-record/routes/anesthesia-record.routes'));
apiV1Router.use('/post-op-notes', lazyRoutes('../modules/post-op-note/routes/post-op-note.routes'));
apiV1Router.use('/theatre-flows', lazyRoutes('../modules/theatre-flow/routes/theatre-flow.routes'));
apiV1Router.use('/therapy-flows', lazyRoutes('../modules/therapy-flow/routes/therapy-flow.routes'));
apiV1Router.use('/drugs', lazyRoutes('../modules/drug/routes/drug.routes'));
apiV1Router.use('/drug-batches', lazyRoutes('../modules/drug-batch/routes/drug-batch.routes'));
apiV1Router.use('/formulary-items', lazyRoutes('../modules/formulary-item/routes/formulary-item.routes'));
apiV1Router.use('/pharmacy-orders', lazyRoutes('../modules/pharmacy-order/routes/pharmacy-order.routes'));
apiV1Router.use('/pharmacy-order-items', lazyRoutes('../modules/pharmacy-order-item/routes/pharmacy-order-item.routes'));
apiV1Router.use('/radiology-procedures', lazyRoutes('../modules/radiology-procedure/routes/radiology-procedure.routes'));
apiV1Router.use('/radiology-tests', lazyRoutes('../modules/radiology-procedure/routes/radiology-procedure.routes'));
apiV1Router.use('/radiology-orders', lazyRoutes('../modules/radiology-order/routes/radiology-order.routes'));
apiV1Router.use('/radiology-results', lazyRoutes('../modules/radiology-result/routes/radiology-result.routes'));
apiV1Router.use('/dispense-logs', lazyRoutes('../modules/dispense-log/routes/dispense-log.routes'));
apiV1Router.use('/adverse-events', lazyRoutes('../modules/adverse-event/routes/adverse-event.routes'));
apiV1Router.use('/inventory-items', lazyRoutes('../modules/inventory-item/routes/inventory-item.routes'));
apiV1Router.use('/inventory-stocks', lazyRoutes('../modules/inventory-stock/routes/inventory-stock.routes'));
apiV1Router.use('/stock-movements', lazyRoutes('../modules/stock-movement/routes/stock-movement.routes'));
apiV1Router.use('/suppliers', lazyRoutes('../modules/supplier/routes/supplier.routes'));
apiV1Router.use('/purchase-requests', lazyRoutes('../modules/purchase-request/routes/purchase-request.routes'));
apiV1Router.use('/purchase-orders', lazyRoutes('../modules/purchase-order/routes/purchase-order.routes'));
apiV1Router.use('/goods-receipts', lazyRoutes('../modules/goods-receipt/routes/goods-receipt.routes'));
apiV1Router.use('/stock-adjustments', lazyRoutes('../modules/stock-adjustment/routes/stock-adjustment.routes'));
apiV1Router.use('/lab-tests', lazyRoutes('../modules/lab-test/routes/lab-test.routes'));
apiV1Router.use('/lab-panels', lazyRoutes('../modules/lab-panel/routes/lab-panel.routes'));
apiV1Router.use('/facility-lab-catalog', lazyRoutes('../modules/facility-lab-catalog/routes/facility-lab-catalog.routes'));
apiV1Router.use('/facility-radiology-catalog', lazyRoutes('../modules/facility-radiology-catalog/routes/facility-radiology-catalog.routes'));
apiV1Router.use('/facility-pharmacy-catalog', lazyRoutes('../modules/facility-pharmacy-catalog/routes/facility-pharmacy-catalog.routes'));
apiV1Router.use('/lab-orders', lazyRoutes('../modules/lab-order/routes/lab-order.routes'));
apiV1Router.use('/lab-order-items', lazyRoutes('../modules/lab-order-item/routes/lab-order-item.routes'));
apiV1Router.use('/lab-samples', lazyRoutes('../modules/lab-sample/routes/lab-sample.routes'));
apiV1Router.use('/lab-results', lazyRoutes('../modules/lab-result/routes/lab-result.routes'));
apiV1Router.use('/lab-qc-logs', lazyRoutes('../modules/lab-qc-log/routes/lab-qc-log.routes'));
apiV1Router.use('/lab', lazyRoutes('../modules/lab-workspace/routes/lab-workspace.routes'));
apiV1Router.use('/radiology', lazyRoutes('../modules/radiology-workspace/routes/radiology-workspace.routes'));
apiV1Router.use('/pharmacy', lazyRoutes('../modules/pharmacy-workspace/routes/pharmacy-workspace.routes'));
apiV1Router.use('/imaging-studies', lazyRoutes('../modules/imaging-study/routes/imaging-study.routes'));
apiV1Router.use('/imaging-assets', lazyRoutes('../modules/imaging-asset/routes/imaging-asset.routes'));
apiV1Router.use('/pacs-links', lazyRoutes('../modules/pacs-link/routes/pacs-link.routes'));
apiV1Router.use('/emergency-cases', lazyRoutes('../modules/emergency-case/routes/emergency-case.routes'));
apiV1Router.use('/triage-assessments', lazyRoutes('../modules/triage-assessment/routes/triage-assessment.routes'));
apiV1Router.use('/emergency-responses', lazyRoutes('../modules/emergency-response/routes/emergency-response.routes'));
apiV1Router.use('/ambulances', lazyRoutes('../modules/ambulance/routes/ambulance.routes'));
apiV1Router.use('/ambulance-dispatches', lazyRoutes('../modules/ambulance-dispatch/routes/ambulance-dispatch.routes'));
apiV1Router.use('/ambulance-trips', lazyRoutes('../modules/ambulance-trip/routes/ambulance-trip.routes'));
apiV1Router.use('/invoices', lazyRoutes('../modules/invoice/routes/invoice.routes'));
apiV1Router.use('/invoice-items', lazyRoutes('../modules/invoice-item/routes/invoice-item.routes'));
apiV1Router.use('/payments', lazyRoutes('../modules/payment/routes/payment.routes'));
apiV1Router.use('/refunds', lazyRoutes('../modules/refund/routes/refund.routes'));
apiV1Router.use('/billing', lazyRoutes('../modules/billing/routes/billing.routes'));
apiV1Router.use('/accounts', lazyRoutes('../modules/accounts-workspace/routes/accounts-workspace.routes'));
apiV1Router.use('/pricing-rules', lazyRoutes('../modules/pricing-rule/routes/pricing-rule.routes'));
apiV1Router.use('/price-book-entries', lazyRoutes('../modules/price-book-entry/routes/price-book-entry.routes'));
apiV1Router.use('/chart-accounts', lazyRoutes('../modules/chart-account/routes/chart-account.routes'));
apiV1Router.use(
  '/accounts-invoices',
  require('../modules/accounts-invoice/routes/accounts-invoice.routes')
);
apiV1Router.use('/insurance-companies', lazyRoutes('../modules/insurance-company/routes/insurance-company.routes'));
apiV1Router.use('/coverage-plans', lazyRoutes('../modules/coverage-plan/routes/coverage-plan.routes'));
apiV1Router.use('/scheme-offers', lazyRoutes('../modules/scheme-offer/routes/scheme-offer.routes'));
apiV1Router.use('/patient-insurance-enrollments', lazyRoutes('../modules/patient-insurance-enrollment/routes/patient-insurance-enrollment.routes'));
apiV1Router.use('/insurer-integrations', lazyRoutes('../modules/insurer-integration/routes/insurer-integration.routes'));
apiV1Router.use('/insurance-claims', lazyRoutes('../modules/insurance-claim/routes/insurance-claim.routes'));
apiV1Router.use('/pre-authorizations', lazyRoutes('../modules/pre-authorization/routes/pre-authorization.routes'));
apiV1Router.use('/claims-workspace', lazyRoutes('../modules/claims-workspace/routes/claims-workspace.routes'));
apiV1Router.use('/billing-adjustments', lazyRoutes('../modules/billing-adjustment/routes/billing-adjustment.routes'));
apiV1Router.use('/payroll-runs', lazyRoutes('../modules/payroll-run/routes/payroll-run.routes'));
apiV1Router.use('/payroll-items', lazyRoutes('../modules/payroll-item/routes/payroll-item.routes'));
apiV1Router.use('/hr', lazyRoutes('../modules/hr-workspace/routes/hr-workspace.routes'));
apiV1Router.use('/housekeeping', lazyRoutes('../modules/housekeeping-workspace/routes/housekeeping-workspace.routes'));
apiV1Router.use('/biomedical', lazyRoutes('../modules/biomedical-workspace/routes/biomedical-workspace.routes'));
apiV1Router.use('/mortuary', lazyRoutes('../modules/mortuary-workspace/routes/mortuary-workspace.routes'));
apiV1Router.use('/staff-positions', lazyRoutes('../modules/staff-position/routes/staff-position.routes'));
apiV1Router.use('/staff-profiles', lazyRoutes('../modules/staff-profile/routes/staff-profile.routes'));
apiV1Router.use('/staff-assignments', lazyRoutes('../modules/staff-assignment/routes/staff-assignment.routes'));
apiV1Router.use('/staff-leaves', lazyRoutes('../modules/staff-leave/routes/staff-leave.routes'));
apiV1Router.use('/housekeeping-tasks', lazyRoutes('../modules/housekeeping-task/routes/housekeeping-task.routes'));
apiV1Router.use('/housekeeping-schedules', lazyRoutes('../modules/housekeeping-schedule/routes/housekeeping-schedule.routes'));
apiV1Router.use('/maintenance-requests', lazyRoutes('../modules/maintenance-request/routes/maintenance-request.routes'));
apiV1Router.use('/assets', lazyRoutes('../modules/asset/routes/asset.routes'));
apiV1Router.use('/asset-service-logs', lazyRoutes('../modules/asset-service-log/routes/asset-service-log.routes'));
apiV1Router.use('/equipment-categories', lazyRoutes('../modules/equipment-category/routes/equipment-category.routes'));
apiV1Router.use('/equipment-registries', lazyRoutes('../modules/equipment-registry/routes/equipment-registry.routes'));
apiV1Router.use('/equipment-location-histories', lazyRoutes('../modules/equipment-location-history/routes/equipment-location-history.routes'));
apiV1Router.use('/equipment-maintenance-plans', lazyRoutes('../modules/equipment-maintenance-plan/routes/equipment-maintenance-plan.routes'));
apiV1Router.use('/equipment-work-orders', lazyRoutes('../modules/equipment-work-order/routes/equipment-work-order.routes'));
apiV1Router.use('/equipment-calibration-logs', lazyRoutes('../modules/equipment-calibration-log/routes/equipment-calibration-log.routes'));
apiV1Router.use('/equipment-safety-test-logs', lazyRoutes('../modules/equipment-safety-test-log/routes/equipment-safety-test-log.routes'));
apiV1Router.use('/equipment-downtime-logs', lazyRoutes('../modules/equipment-downtime-log/routes/equipment-downtime-log.routes'));
apiV1Router.use('/equipment-spare-parts', lazyRoutes('../modules/equipment-spare-part/routes/equipment-spare-part.routes'));
apiV1Router.use('/equipment-warranty-contracts', lazyRoutes('../modules/equipment-warranty-contract/routes/equipment-warranty-contract.routes'));
apiV1Router.use('/equipment-service-providers', lazyRoutes('../modules/equipment-service-provider/routes/equipment-service-provider.routes'));
apiV1Router.use('/equipment-incident-reports', lazyRoutes('../modules/equipment-incident-report/routes/equipment-incident-report.routes'));
apiV1Router.use('/equipment-recall-notices', lazyRoutes('../modules/equipment-recall-notice/routes/equipment-recall-notice.routes'));
apiV1Router.use('/equipment-utilization-snapshots', lazyRoutes('../modules/equipment-utilization-snapshot/routes/equipment-utilization-snapshot.routes'));
apiV1Router.use('/equipment-disposal-transfers', lazyRoutes('../modules/equipment-disposal-transfer/routes/equipment-disposal-transfer.routes'));
apiV1Router.use('/shifts', lazyRoutes('../modules/shift/routes/shift.routes'));
apiV1Router.use('/shift-assignments', lazyRoutes('../modules/shift-assignment/routes/shift-assignment.routes'));
apiV1Router.use('/shift-swap-requests', lazyRoutes('../modules/shift-swap-request/routes/shift-swap-request.routes'));
apiV1Router.use('/office-contexts', lazyRoutes('../modules/office-context/routes/office-context.routes'));
apiV1Router.use('/shift-closes', lazyRoutes('../modules/shift-close/routes/shift-close.routes'));
apiV1Router.use('/day-closes', lazyRoutes('../modules/day-close/routes/day-close.routes'));
apiV1Router.use('/handovers', lazyRoutes('../modules/handover/routes/handover.routes'));
apiV1Router.use('/custody-snapshots', lazyRoutes('../modules/custody-snapshot/routes/custody-snapshot.routes'));
apiV1Router.use('/closeout-packs', lazyRoutes('../modules/closeout-pack/routes/closeout-pack.routes'));
apiV1Router.use('/rosters', lazyRoutes('../modules/roster/routes/roster.routes'));
apiV1Router.use('/shift-templates', lazyRoutes('../modules/shift-template/routes/shift-template.routes'));
apiV1Router.use('/roster-day-offs', lazyRoutes('../modules/roster-day-off/routes/roster-day-off.routes'));
apiV1Router.use('/staff-availabilities', lazyRoutes('../modules/staff-availability/routes/staff-availability.routes'));
apiV1Router.use('/notifications', lazyRoutes('../modules/notification/routes/notification.routes'));
apiV1Router.use('/notification-deliveries', lazyRoutes('../modules/notification-delivery/routes/notification-delivery.routes'));
apiV1Router.use('/conversations', lazyRoutes('../modules/conversation/routes/conversation.routes'));
apiV1Router.use('/messages', lazyRoutes('../modules/message/routes/message.routes'));
apiV1Router.use('/communications-workspace', lazyRoutes('../modules/communications-workspace/routes/communications-workspace.routes'));
apiV1Router.use('/report-definitions', lazyRoutes('../modules/report-definition/routes/report-definition.routes'));
apiV1Router.use('/report-runs', lazyRoutes('../modules/report-run/routes/report-run.routes'));
apiV1Router.use('/report-schedules', lazyRoutes('../modules/report-schedule/routes/report-schedule.routes'));
apiV1Router.use('/dashboard-widgets', lazyRoutes('../modules/dashboard-widget/routes/dashboard-widget.routes'));
apiV1Router.use('/dashboard-workspace', lazyRoutes('../modules/dashboard-workspace/routes/dashboard-workspace.routes'));
apiV1Router.use('/settings-workspace', lazyRoutes('../modules/settings-workspace/routes/settings-workspace.routes'));
apiV1Router.use('/tenant-facility-workspace', lazyRoutes('../modules/tenant-facility-workspace/routes/tenant-facility-workspace.routes'));
apiV1Router.use('/access-admin-workspace', lazyRoutes('../modules/access-admin-workspace/routes/access-admin-workspace.routes'));
apiV1Router.use('/kpi-snapshots', lazyRoutes('../modules/kpi-snapshot/routes/kpi-snapshot.routes'));
apiV1Router.use('/analytics-events', lazyRoutes('../modules/analytics-event/routes/analytics-event.routes'));
apiV1Router.use('/reports-workspace', lazyRoutes('../modules/reports-workspace/routes/reports-workspace.routes'));
apiV1Router.use('/audit-logs', lazyRoutes('../modules/audit-log/routes/audit-log.routes'));
apiV1Router.use('/phi-access-logs', lazyRoutes('../modules/phi-access-log/routes/phi-access-log.routes'));
apiV1Router.use('/data-processing-logs', lazyRoutes('../modules/data-processing-log/routes/data-processing-log.routes'));
apiV1Router.use('/break-glass-access', lazyRoutes('../modules/break-glass-access/routes/break-glass-access.routes'));
apiV1Router.use('/break-glass-reviews', lazyRoutes('../modules/break-glass-review/routes/break-glass-review.routes'));
apiV1Router.use('/templates', lazyRoutes('../modules/template/routes/template.routes'));
apiV1Router.use('/template-variables', lazyRoutes('../modules/template-variable/routes/template-variable.routes'));
apiV1Router.use('/subscriptions-workspace', lazyRoutes('../modules/subscriptions-workspace/routes/subscriptions-workspace.routes'));
apiV1Router.use('/subscription-plans', lazyRoutes('../modules/subscription-plan/routes/subscription-plan.routes'));
apiV1Router.use('/subscriptions', lazyRoutes('../modules/subscription/routes/subscription.routes'));
apiV1Router.use('/subscription-invoices', lazyRoutes('../modules/subscription-invoice/routes/subscription-invoice.routes'));
apiV1Router.use('/modules', lazyRoutes('../modules/module/routes/module.routes'));
apiV1Router.use('/module-subscriptions', lazyRoutes('../modules/module-subscription/routes/module-subscription.routes'));
apiV1Router.use('/licenses', lazyRoutes('../modules/license/routes/license.routes'));
apiV1Router.use('/breach-notifications', lazyRoutes('../modules/breach-notification/routes/breach-notification.routes'));
apiV1Router.use('/system-change-logs', lazyRoutes('../modules/system-change-log/routes/system-change-log.routes'));
apiV1Router.use('/integrations', lazyRoutes('../modules/integration/routes/integration.routes'));
apiV1Router.use('/integration-logs', lazyRoutes('../modules/integration-log/routes/integration-log.routes'));
apiV1Router.use('/webhook-subscriptions', lazyRoutes('../modules/webhook-subscription/routes/webhook-subscription.routes'));
apiV1Router.use('/interop', lazyRoutes('../modules/interop/routes/interop.routes'));
apiV1Router.use('/ai', lazyRoutes('../modules/ai/routes/ai.routes'));

// Mount API v1 router
router.use('/api/v1', apiV1Router);

module.exports = router;
