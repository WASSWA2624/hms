import 'package:hosspi_hms/core/realtime/realtime_events.dart';

/// Reusable event groups used by workspace controllers to keep visible data
/// synchronized without duplicating long event lists across modules.
abstract final class RealtimeEventGroups {
  static const Set<String> appointments = <String>{
    RealtimeEvents.appointmentCreated,
    RealtimeEvents.appointmentUpdated,
    RealtimeEvents.appointmentRescheduled,
    RealtimeEvents.appointmentCanceled,
  };

  static const Set<String> encounters = <String>{
    RealtimeEvents.encounterCreated,
    RealtimeEvents.encounterUpdated,
    RealtimeEvents.encounterDeleted,
  };

  static const Set<String> patients = <String>{
    RealtimeEvents.patientCreated,
    RealtimeEvents.patientUpdated,
    RealtimeEvents.patientDeleted,
  };

  static const Set<String> visitQueue = <String>{
    RealtimeEvents.visitQueueCreated,
    RealtimeEvents.visitQueueUpdated,
    RealtimeEvents.visitQueueDeleted,
    RealtimeEvents.visitQueuePositionChanged,
    RealtimeEvents.visitQueueTriageUpdated,
  };

  static const Set<String> opdFlow = <String>{
    RealtimeEvents.opdFlowUpdated,
    ...encounters,
    ...visitQueue,
  };

  static const Set<String> admissions = <String>{
    RealtimeEvents.ipdFlowUpdated,
    RealtimeEvents.patientAdmitted,
    RealtimeEvents.patientTransferred,
    RealtimeEvents.patientDischarged,
    RealtimeEvents.bedAssignmentChanged,
  };

  static const Set<String> criticalAlerts = <String>{
    RealtimeEvents.criticalAlertRaised,
    RealtimeEvents.criticalAlertResolved,
  };

  static const Set<String> diagnostics = <String>{
    RealtimeEvents.labWorkflowUpdated,
    RealtimeEvents.labResultReady,
    RealtimeEvents.labResultUpdated,
    RealtimeEvents.labResultCritical,
    RealtimeEvents.radiologyWorkflowUpdated,
    RealtimeEvents.radiologyResultReady,
    RealtimeEvents.radiologyResultUpdated,
  };

  static const Set<String> pharmacy = <String>{
    RealtimeEvents.pharmacyWorkspaceUpdated,
    RealtimeEvents.pharmacyOrderCreated,
    RealtimeEvents.pharmacyOrderUpdated,
    RealtimeEvents.pharmacyOrderDispensed,
    RealtimeEvents.pharmacyOrderCanceled,
    RealtimeEvents.pharmacyCatalogUpdated,
    RealtimeEvents.inventoryStockUpdated,
    RealtimeEvents.inventoryLowStock,
    RealtimeEvents.inventoryStockAdjusted,
  };

  static const Set<String> payments = <String>{
    RealtimeEvents.paymentCreated,
    RealtimeEvents.paymentUpdated,
    RealtimeEvents.paymentDeleted,
    RealtimeEvents.paymentReconciled,
  };

  static const Set<String> billing = <String>{
    RealtimeEvents.billingInvoiceIssued,
    RealtimeEvents.billingPaymentReceived,
    RealtimeEvents.billingRefundProcessed,
    RealtimeEvents.invoiceUpdated,
    RealtimeEvents.billingBalanceUpdated,
    ...payments,
  };

  static const Set<String> emergency = <String>{
    RealtimeEvents.emergencyCaseAssigned,
    RealtimeEvents.ambulanceDispatched,
    RealtimeEvents.ambulanceArrivalUpdated,
  };

  static const Set<String> operations = <String>{
    RealtimeEvents.housekeepingWorkspaceUpdated,
    RealtimeEvents.housekeepingTaskUpdated,
    RealtimeEvents.maintenanceRequestTriaged,
    RealtimeEvents.maintenanceRequestConverted,
  };

  static const Set<String> hr = <String>{RealtimeEvents.hrWorkspaceUpdated};

  static const Set<String> accounts = <String>{
    RealtimeEvents.accountsWorkspaceUpdated,
  };

  static const Set<String> housekeeping = <String>{
    ...operations,
    ...admissions,
  };

  static const Set<String> communications = <String>{
    RealtimeEvents.notificationCreated,
    RealtimeEvents.notificationDeliveryUpdated,
    RealtimeEvents.conversationMessageCreated,
    RealtimeEvents.conversationThreadUpdated,
    RealtimeEvents.conversationReadStateUpdated,
    RealtimeEvents.conversationCallUpdated,
  };

  static const Set<String> patientRegistry = <String>{
    ...patients,
    ...appointments,
    ...opdFlow,
    ...admissions,
    ...criticalAlerts,
    ...diagnostics,
    ...pharmacy,
    ...billing,
    ...emergency,
  };

  static const Set<String> opd = <String>{
    ...appointments,
    ...opdFlow,
    ...admissions,
    ...criticalAlerts,
    ...diagnostics,
    ...pharmacy,
    ...billing,
    ...emergency,
  };

  static const Set<String> clinical = <String>{
    ...opdFlow,
    ...admissions,
    ...criticalAlerts,
    ...diagnostics,
    ...pharmacy,
    ...billing,
  };

  static const Set<String> physiotherapy = <String>{
    ...appointments,
    ...clinical,
  };

  static const Set<String> ipd = <String>{
    ...admissions,
    ...criticalAlerts,
    ...diagnostics,
    ...pharmacy,
    ...billing,
  };

  static const Set<String> icu = <String>{
    ...admissions,
    ...criticalAlerts,
    ...diagnostics,
    ...pharmacy,
    ...billing,
  };

  static const Set<String> nursing = <String>{
    ...admissions,
    ...criticalAlerts,
    ...diagnostics,
    ...pharmacy,
    ...billing,
  };

  static const Set<String> lab = <String>{
    RealtimeEvents.labWorkflowUpdated,
    RealtimeEvents.labCatalogUpdated,
    RealtimeEvents.labResultReady,
    RealtimeEvents.labResultUpdated,
    RealtimeEvents.labResultCritical,
    ...billing,
  };

  static const Set<String> radiology = <String>{
    RealtimeEvents.radiologyWorkflowUpdated,
    RealtimeEvents.radiologyCatalogUpdated,
    RealtimeEvents.radiologyResultReady,
    RealtimeEvents.radiologyResultUpdated,
    ...billing,
  };

  static const Set<String> pharmacyWorkspace = <String>{
    ...pharmacy,
    ...admissions,
    ...criticalAlerts,
    ...billing,
  };

  static const Set<String> biomedical = <String>{
    RealtimeEvents.biomedicalWorkspaceUpdated,
    RealtimeEvents.biomedicalFaultReported,
    RealtimeEvents.biomedicalWorkOrderAssigned,
    RealtimeEvents.biomedicalWorkOrderStarted,
    RealtimeEvents.biomedicalWorkOrderReturnedToService,
    RealtimeEvents.biomedicalOverdueChanged,
  };

  static const Set<String> emergencyWorkspace = <String>{
    ...emergency,
    ...appointments,
    ...opdFlow,
    ...admissions,
    ...criticalAlerts,
    ...billing,
  };

  // Billing must reflect charges/settlements that originate anywhere in the
  // app. Besides billing events themselves, include the clinical/OPD workflow
  // events that create or settle invoices (consultation payments, lab/radiology
  // orders, pharmacy dispensing, admissions) so the workspace stays live even
  // when the mutating module only emits its own workflow event.
  static const Set<String> billingWorkspace = <String>{
    ...billing,
    ...opdFlow,
    ...diagnostics,
    ...pharmacy,
    ...admissions,
  };

  /// Accounts desk — dedicated accounts events plus billing workspace fan-in.
  static const Set<String> accountsWorkspace = <String>{
    ...accounts,
    ...billingWorkspace,
  };

  static const Set<String> claims = <String>{...billing, ...admissions};

  static const Set<String> discharge = <String>{
    ...admissions,
    ...pharmacy,
    ...billing,
  };

  static const Set<String> mortuary = <String>{...admissions, ...billing};

  static const Set<String> theater = <String>{
    ...admissions,
    ...criticalAlerts,
    ...billing,
  };

  static const Set<String> roomsBeds = <String>{
    RealtimeEvents.facilityLayoutUpdated,
    ...admissions,
  };

  static const Set<String> subscriptions = <String>{
    RealtimeEvents.subscriptionCreated,
    RealtimeEvents.subscriptionUpdated,
    RealtimeEvents.subscriptionDeleted,
    RealtimeEvents.subscriptionActivated,
    RealtimeEvents.subscriptionDeactivated,
    RealtimeEvents.subscriptionExpiring,
    RealtimeEvents.moduleEntitlementUpdated,
  };

  static const Set<String> integrations = <String>{
    RealtimeEvents.integrationWebhookRetry,
    RealtimeEvents.integrationFailure,
    RealtimeEvents.integrationReplayComplete,
  };

  static const Set<String> reports = <String>{
    RealtimeEvents.facilityLayoutUpdated,
    ...subscriptions,
    ...integrations,
    ...patients,
    ...appointments,
    ...opdFlow,
    ...diagnostics,
    ...billing,
  };

  static const Set<String> tenantFacility = <String>{
    RealtimeEvents.facilityLayoutUpdated,
    RealtimeEvents.facilityCreated,
    RealtimeEvents.facilityUpdated,
    RealtimeEvents.facilityDeleted,
    RealtimeEvents.facilityRestored,
    RealtimeEvents.facilityPermanentlyDeleted,
    ...subscriptions,
  };

  static const Set<String> platformAdmin = <String>{
    RealtimeEvents.tenantCreated,
    RealtimeEvents.tenantUpdated,
    RealtimeEvents.tenantDeleted,
    RealtimeEvents.tenantRestored,
    RealtimeEvents.tenantPermanentlyDeleted,
    RealtimeEvents.facilityCreated,
    RealtimeEvents.facilityUpdated,
    RealtimeEvents.facilityDeleted,
    RealtimeEvents.facilityRestored,
    RealtimeEvents.facilityPermanentlyDeleted,
    RealtimeEvents.roleCreated,
    RealtimeEvents.roleUpdated,
    RealtimeEvents.roleDeleted,
    RealtimeEvents.userCreated,
    RealtimeEvents.userUpdated,
    RealtimeEvents.userDeleted,
    RealtimeEvents.userRestored,
    RealtimeEvents.userPermanentlyDeleted,
    RealtimeEvents.platformDashboardInvalidate,
    ...subscriptions,
  };

  static const Set<String> settings = <String>{
    ...subscriptions,
    ...integrations,
  };

  static const Set<String> accessAdmin = <String>{...platformAdmin};
}
