/**
 * WebSocket Event Types
 * 
 * Centralized WebSocket event type constants per websockets.mdc
 * All WebSocket messages must follow format: { "event": "event_name", "payload": {} }
 * Event types must be centralized in lib/websocket/events.js
 * 
 * Only services may emit WebSocket events
 * Controllers must not emit events directly
 */

/**
 * Connection Events
 * Events related to WebSocket connection lifecycle
 */
const CONNECTION_EVENTS = {
  CONNECT: 'connect',
  DISCONNECT: 'disconnect',
  RECONNECT: 'reconnect',
  HEARTBEAT: 'heartbeat',
  PING: 'ping',
  PONG: 'pong',
  ERROR: 'error'
};

/**
 * Authentication Events
 * Events related to user authentication
 */
const AUTH_EVENTS = {
  AUTHENTICATED: 'authenticated',
  AUTHENTICATION_FAILED: 'authentication_failed',
  SESSION_EXPIRED: 'session_expired',
  UNAUTHORIZED: 'unauthorized'
};

/**
 * Appointment Events
 */
const APPOINTMENT_EVENTS = {
  APPOINTMENT_CREATED: 'appointment.created',
  APPOINTMENT_RESCHEDULED: 'appointment.rescheduled',
  APPOINTMENT_CANCELED: 'appointment.canceled'
};

/**
 * Patient Events
 */
const PATIENT_EVENTS = {
  PATIENT_CREATED: 'patient.created',
  PATIENT_UPDATED: 'patient.updated',
  PATIENT_DELETED: 'patient.deleted',
  PATIENT_REPORT_JOB_CREATED: 'patient_report_job.created',
  PATIENT_REPORT_JOB_UPDATED: 'patient_report_job.updated'
};

/**
 * Encounter Events
 */
const ENCOUNTER_EVENTS = {
  ENCOUNTER_CREATED: 'encounter.created',
  ENCOUNTER_UPDATED: 'encounter.updated',
  ENCOUNTER_DELETED: 'encounter.deleted'
};

/**
 * OPD Flow Events
 */
const OPD_EVENTS = {
  OPD_FLOW_UPDATED: 'opd.flow.updated'
};

/**
 * IPD Flow Events
 */
const IPD_EVENTS = {
  IPD_FLOW_UPDATED: 'ipd.flow.updated'
};

/**
 * Visit Queue Events
 */
const VISIT_QUEUE_EVENTS = {
  VISIT_QUEUE_CREATED: 'visit_queue.created',
  VISIT_QUEUE_UPDATED: 'visit_queue.updated',
  VISIT_QUEUE_DELETED: 'visit_queue.deleted',
  VISIT_QUEUE_POSITION_CHANGED: 'visit_queue.position_changed',
  VISIT_QUEUE_TRIAGE_UPDATED: 'visit_queue.triage_updated'
};

/**
 * Admission & Bed Assignment Events
 */
const ADMISSION_BED_EVENTS = {
  PATIENT_ADMITTED: 'admission.patient_admitted',
  PATIENT_TRANSFERRED: 'admission.patient_transferred',
  PATIENT_DISCHARGED: 'admission.patient_discharged',
  BED_ASSIGNMENT_CHANGED: 'admission.bed_assignment_changed'
};

/**
 * Critical Alert Events
 */
const CRITICAL_ALERT_EVENTS = {
  CRITICAL_ALERT_RAISED: 'critical_alert.raised',
  CRITICAL_ALERT_RESOLVED: 'critical_alert.resolved'
};

/**
 * Diagnostics Events (Lab/Radiology)
 */
const DIAGNOSTIC_EVENTS = {
  LAB_WORKFLOW_UPDATED: 'diagnostic.lab_workflow_updated',
  LAB_CATALOG_UPDATED: 'diagnostic.lab_catalog_updated',
  LAB_RESULT_READY: 'diagnostic.lab_result_ready',
  LAB_RESULT_UPDATED: 'diagnostic.lab_result_updated',
  LAB_RESULT_CRITICAL: 'diagnostic.lab_result_critical',
  RADIOLOGY_WORKFLOW_UPDATED: 'diagnostic.radiology_workflow_updated',
  RADIOLOGY_CATALOG_UPDATED: 'diagnostic.radiology_catalog_updated',
  RADIOLOGY_RESULT_READY: 'diagnostic.radiology_result_ready',
  RADIOLOGY_RESULT_UPDATED: 'diagnostic.radiology_result_updated'
};

/**
 * Pharmacy Events
 */
const PHARMACY_EVENTS = {
  PHARMACY_WORKSPACE_UPDATED: 'pharmacy.workspace_updated',
  PHARMACY_ORDER_UPDATED: 'pharmacy.order_updated',
  PHARMACY_ORDER_CREATED: 'pharmacy.order_created',
  PHARMACY_ORDER_DISPENSED: 'pharmacy.order_dispensed',
  PHARMACY_ORDER_CANCELED: 'pharmacy.order_canceled',
  PHARMACY_CATALOG_UPDATED: 'pharmacy.catalog_updated'
};

/**
 * HR Events
 */
const HR_EVENTS = {
  HR_WORKSPACE_UPDATED: 'hr.workspace_updated'
};

/**
 * Housekeeping Events
 */
const HOUSEKEEPING_EVENTS = {
  HOUSEKEEPING_WORKSPACE_UPDATED: 'housekeeping.workspace_updated',
  HOUSEKEEPING_TASK_UPDATED: 'housekeeping.task_updated',
  MAINTENANCE_REQUEST_TRIAGED: 'housekeeping.maintenance_request_triaged',
  MAINTENANCE_REQUEST_CONVERTED: 'housekeeping.maintenance_request_converted'
};

/**
 * Biomedical Events
 */
const BIOMEDICAL_EVENTS = {
  BIOMEDICAL_WORKSPACE_UPDATED: 'biomedical.workspace_updated',
  BIOMEDICAL_FAULT_REPORTED: 'biomedical.fault_reported',
  BIOMEDICAL_WORK_ORDER_ASSIGNED: 'biomedical.work_order_assigned',
  BIOMEDICAL_WORK_ORDER_STARTED: 'biomedical.work_order_started',
  BIOMEDICAL_WORK_ORDER_RETURNED_TO_SERVICE: 'biomedical.work_order_returned_to_service',
  BIOMEDICAL_OVERDUE_CHANGED: 'biomedical.overdue_changed'
};

/**
 * Inventory Events
 */
const INVENTORY_EVENTS = {
  INVENTORY_STOCK_UPDATED: 'inventory.stock_updated',
  INVENTORY_LOW_STOCK: 'inventory.low_stock',
  INVENTORY_STOCK_ADJUSTED: 'inventory.stock_adjusted'
};

/**
 * Emergency Dispatch Events
 */
const EMERGENCY_EVENTS = {
  EMERGENCY_CASE_ASSIGNED: 'emergency.case_assigned',
  AMBULANCE_DISPATCHED: 'emergency.ambulance_dispatched',
  AMBULANCE_ARRIVAL_UPDATED: 'emergency.ambulance_arrival_updated'
};

/**
 * Payment Events
 */
const PAYMENT_EVENTS = {
  PAYMENT_CREATED: 'payment.created',
  PAYMENT_UPDATED: 'payment.updated',
  PAYMENT_DELETED: 'payment.deleted',
  PAYMENT_RECONCILED: 'payment.reconciled'
};

/**
 * Billing Events
 */
const BILLING_EVENTS = {
  BILLING_INVOICE_ISSUED: 'billing.invoice_issued',
  BILLING_PAYMENT_RECEIVED: 'billing.payment_received',
  BILLING_REFUND_PROCESSED: 'billing.refund_processed',
  INVOICE_UPDATED: 'invoice.updated',
  BILLING_BALANCE_UPDATED: 'billing.balance_updated'
};

/**
 * Notification & Message Events
 */
const NOTIFICATION_EVENTS = {
  NOTIFICATION_CREATED: 'notification.created',
  CONVERSATION_MESSAGE_CREATED: 'conversation.message_created',
  CONVERSATION_THREAD_UPDATED: 'conversation.thread_updated',
  CONVERSATION_READ_STATE_UPDATED: 'conversation.read_state_updated',
  CONVERSATION_CALL_UPDATED: 'conversation.call_updated',
  NOTIFICATION_DELIVERY_UPDATED: 'notification.delivery_updated'
};

/**
 * Subscription & Entitlement Events
 */
const SUBSCRIPTION_EVENTS = {
  SUBSCRIPTION_CREATED: 'subscription.created',
  SUBSCRIPTION_UPDATED: 'subscription.updated',
  SUBSCRIPTION_DELETED: 'subscription.deleted',
  SUBSCRIPTION_ACTIVATED: 'subscription.activated',
  SUBSCRIPTION_DEACTIVATED: 'subscription.deactivated',
  SUBSCRIPTION_EXPIRING: 'subscription.expiring',
  MODULE_ENTITLEMENT_UPDATED: 'module.entitlement_updated'
};

/**
 * Facility layout events (wards, rooms, beds)
 */
const FACILITY_LAYOUT_EVENTS = {
  FACILITY_LAYOUT_UPDATED: 'facility.layout_updated'
};

/**
 * Platform admin profile events (tenants, facilities, access control)
 */
const PLATFORM_ADMIN_EVENTS = {
  TENANT_CREATED: 'tenant.created',
  TENANT_UPDATED: 'tenant.updated',
  TENANT_DELETED: 'tenant.deleted',
  TENANT_RESTORED: 'tenant.restored',
  TENANT_PERMANENTLY_DELETED: 'tenant.permanently_deleted',
  FACILITY_CREATED: 'facility.created',
  FACILITY_UPDATED: 'facility.updated',
  FACILITY_DELETED: 'facility.deleted',
  FACILITY_RESTORED: 'facility.restored',
  FACILITY_PERMANENTLY_DELETED: 'facility.permanently_deleted',
  ROLE_CREATED: 'role.created',
  ROLE_UPDATED: 'role.updated',
  ROLE_DELETED: 'role.deleted',
  ROLE_RESTORED: 'role.restored',
  ROLE_PERMANENTLY_DELETED: 'role.permanently_deleted',
  USER_CREATED: 'user.created',
  USER_UPDATED: 'user.updated',
  USER_DELETED: 'user.deleted',
  USER_RESTORED: 'user.restored',
  USER_PERMANENTLY_DELETED: 'user.permanently_deleted',
  PLATFORM_DASHBOARD_INVALIDATE: 'platform.dashboard.invalidate'
};

/**
 * Integration Events
 */
const INTEGRATION_EVENTS = {
  INTEGRATION_WEBHOOK_RETRY: 'integration.webhook_retry',
  INTEGRATION_FAILURE: 'integration.failure',
  INTEGRATION_REPLAY_COMPLETE: 'integration.replay_complete'
};

const ACCESS_CONTROL_EVENTS = {
  BREAK_GLASS_REQUESTED: 'access.break_glass_requested',
  BREAK_GLASS_REVIEWED: 'access.break_glass_reviewed',
  BREAK_GLASS_REVOKED: 'access.break_glass_revoked'
};

const LAST_OFFICE_EVENTS = {
  OFFICE_CONTEXT_OPENED: 'last_office.office_context_opened',
  SHIFT_CLOSE_SUBMITTED: 'last_office.shift_close_submitted',
  SHIFT_CLOSE_APPROVED: 'last_office.shift_close_approved',
  DAY_CLOSE_SUBMITTED: 'last_office.day_close_submitted',
  DAY_CLOSE_APPROVED: 'last_office.day_close_approved',
  HANDOVER_ACCEPTED: 'last_office.handover_accepted',
  CUSTODY_SNAPSHOT_FINALIZED: 'last_office.custody_snapshot_finalized',
  CLOSEOUT_PACK_READY: 'last_office.closeout_pack_ready'
};

/**
 * All WebSocket Events
 * Combined export of all event types
 */
const WS_EVENTS = {
  ...CONNECTION_EVENTS,
  ...AUTH_EVENTS,
  ...APPOINTMENT_EVENTS,
  ...PATIENT_EVENTS,
  ...ENCOUNTER_EVENTS,
  ...OPD_EVENTS,
  ...IPD_EVENTS,
  ...VISIT_QUEUE_EVENTS,
  ...ADMISSION_BED_EVENTS,
  ...CRITICAL_ALERT_EVENTS,
  ...DIAGNOSTIC_EVENTS,
  ...PHARMACY_EVENTS,
  ...HR_EVENTS,
  ...HOUSEKEEPING_EVENTS,
  ...BIOMEDICAL_EVENTS,
  ...INVENTORY_EVENTS,
  ...EMERGENCY_EVENTS,
  ...PAYMENT_EVENTS,
  ...BILLING_EVENTS,
  ...NOTIFICATION_EVENTS,
  ...SUBSCRIPTION_EVENTS,
  ...FACILITY_LAYOUT_EVENTS,
  ...PLATFORM_ADMIN_EVENTS,
  ...INTEGRATION_EVENTS,
  ...ACCESS_CONTROL_EVENTS,
  ...LAST_OFFICE_EVENTS
};

module.exports = {
  // Individual event groups
  CONNECTION_EVENTS,
  AUTH_EVENTS,
  APPOINTMENT_EVENTS,
  PATIENT_EVENTS,
  ENCOUNTER_EVENTS,
  OPD_EVENTS,
  IPD_EVENTS,
  VISIT_QUEUE_EVENTS,
  ADMISSION_BED_EVENTS,
  CRITICAL_ALERT_EVENTS,
  DIAGNOSTIC_EVENTS,
  PHARMACY_EVENTS,
  HR_EVENTS,
  HOUSEKEEPING_EVENTS,
  BIOMEDICAL_EVENTS,
  INVENTORY_EVENTS,
  EMERGENCY_EVENTS,
  PAYMENT_EVENTS,
  BILLING_EVENTS,
  NOTIFICATION_EVENTS,
  SUBSCRIPTION_EVENTS,
  FACILITY_LAYOUT_EVENTS,
  PLATFORM_ADMIN_EVENTS,
  INTEGRATION_EVENTS,
  ACCESS_CONTROL_EVENTS,
  LAST_OFFICE_EVENTS,
  
  // Combined events
  WS_EVENTS
};

