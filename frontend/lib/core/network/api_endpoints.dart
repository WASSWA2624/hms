enum HmsApiEndpointGroup {
  authSession,
  tenantFacility,
  accessControl,
  patientFlow,
  clinicalCare,
  diagnosticsPharmacyBilling,
  operations,
  subscriptions,
  communicationsReportsAuditIntegrations,
}

enum HmsApiResource {
  auth('auth', HmsApiEndpointGroup.authSession),
  public('public', HmsApiEndpointGroup.authSession),
  userSessions('user-sessions', HmsApiEndpointGroup.authSession),
  tenants('tenants', HmsApiEndpointGroup.tenantFacility),
  facilities('facilities', HmsApiEndpointGroup.tenantFacility),
  departments('departments', HmsApiEndpointGroup.tenantFacility),
  units('units', HmsApiEndpointGroup.tenantFacility),
  rooms('rooms', HmsApiEndpointGroup.tenantFacility),
  wards('wards', HmsApiEndpointGroup.tenantFacility),
  beds('beds', HmsApiEndpointGroup.tenantFacility),
  addresses('addresses', HmsApiEndpointGroup.tenantFacility),
  contacts('contacts', HmsApiEndpointGroup.tenantFacility),
  tenantFacilityWorkspace(
    'tenant-facility-workspace',
    HmsApiEndpointGroup.tenantFacility,
  ),
  accessAdminWorkspace(
    'access-admin-workspace',
    HmsApiEndpointGroup.accessControl,
  ),
  users('users', HmsApiEndpointGroup.accessControl),
  userProfiles('user-profiles', HmsApiEndpointGroup.accessControl),
  roles('roles', HmsApiEndpointGroup.accessControl),
  permissions('permissions', HmsApiEndpointGroup.accessControl),
  rolePermissions('role-permissions', HmsApiEndpointGroup.accessControl),
  userRoles('user-roles', HmsApiEndpointGroup.accessControl),
  userMfas('user-mfas', HmsApiEndpointGroup.accessControl),
  oauthAccounts('oauth-accounts', HmsApiEndpointGroup.accessControl),
  apiKeys('api-keys', HmsApiEndpointGroup.accessControl),
  apiKeyPermissions('api-key-permissions', HmsApiEndpointGroup.accessControl),
  abacPolicies('abac-policies', HmsApiEndpointGroup.accessControl),
  patients('patients', HmsApiEndpointGroup.patientFlow),
  patientIdentifiers('patient-identifiers', HmsApiEndpointGroup.patientFlow),
  patientContacts('patient-contacts', HmsApiEndpointGroup.patientFlow),
  patientGuardians('patient-guardians', HmsApiEndpointGroup.patientFlow),
  patientAllergies('patient-allergies', HmsApiEndpointGroup.patientFlow),
  patientMedicalHistories(
    'patient-medical-histories',
    HmsApiEndpointGroup.patientFlow,
  ),
  patientReports('patient-reports', HmsApiEndpointGroup.patientFlow),
  consents('consents', HmsApiEndpointGroup.patientFlow),
  termsAcceptances('terms-acceptances', HmsApiEndpointGroup.patientFlow),
  appointments('appointments', HmsApiEndpointGroup.patientFlow),
  appointmentParticipants(
    'appointment-participants',
    HmsApiEndpointGroup.patientFlow,
  ),
  appointmentReminders(
    'appointment-reminders',
    HmsApiEndpointGroup.patientFlow,
  ),
  providerSchedules('provider-schedules', HmsApiEndpointGroup.patientFlow),
  availabilitySlots('availability-slots', HmsApiEndpointGroup.patientFlow),
  scheduling('scheduling', HmsApiEndpointGroup.patientFlow),
  doctors('doctors', HmsApiEndpointGroup.patientFlow),
  admissions('admissions', HmsApiEndpointGroup.clinicalCare),
  bedAssignments('bed-assignments', HmsApiEndpointGroup.clinicalCare),
  wardRounds('ward-rounds', HmsApiEndpointGroup.clinicalCare),
  visitQueues('visit-queues', HmsApiEndpointGroup.patientFlow),
  triage('triage', HmsApiEndpointGroup.patientFlow),
  opdFlows('opd-flows', HmsApiEndpointGroup.patientFlow),
  ipdFlows('ipd-flows', HmsApiEndpointGroup.clinicalCare),
  referrals('referrals', HmsApiEndpointGroup.patientFlow),
  campaigns('campaigns', HmsApiEndpointGroup.patientFlow),
  feedback('feedback', HmsApiEndpointGroup.patientFlow),
  followUps('follow-ups', HmsApiEndpointGroup.patientFlow),
  vitalSigns('vital-signs', HmsApiEndpointGroup.clinicalCare),
  carePlans('care-plans', HmsApiEndpointGroup.clinicalCare),
  clinicalAlerts('clinical-alerts', HmsApiEndpointGroup.clinicalCare),
  clinicalAlertThresholds(
    'clinical-alert-thresholds',
    HmsApiEndpointGroup.clinicalCare,
  ),
  clinicalTerms('clinical-terms', HmsApiEndpointGroup.clinicalCare),
  clinicalCatalog('clinical-catalog', HmsApiEndpointGroup.clinicalCare),
  clinicalTermFavorites(
    'clinical-term-favorites',
    HmsApiEndpointGroup.clinicalCare,
  ),
  encounters('encounters', HmsApiEndpointGroup.clinicalCare),
  clinicalNotes('clinical-notes', HmsApiEndpointGroup.clinicalCare),
  diagnoses('diagnoses', HmsApiEndpointGroup.clinicalCare),
  procedures('procedures', HmsApiEndpointGroup.clinicalCare),
  nursingNotes('nursing-notes', HmsApiEndpointGroup.clinicalCare),
  medicationAdministrations(
    'medication-administrations',
    HmsApiEndpointGroup.clinicalCare,
  ),
  dischargeSummaries('discharge-summaries', HmsApiEndpointGroup.clinicalCare),
  transferRequests('transfer-requests', HmsApiEndpointGroup.clinicalCare),
  icuStays('icu-stays', HmsApiEndpointGroup.clinicalCare),
  icuObservations('icu-observations', HmsApiEndpointGroup.clinicalCare),
  criticalAlerts('critical-alerts', HmsApiEndpointGroup.clinicalCare),
  theatreCases('theatre-cases', HmsApiEndpointGroup.clinicalCare),
  anesthesiaRecords('anesthesia-records', HmsApiEndpointGroup.clinicalCare),
  postOpNotes('post-op-notes', HmsApiEndpointGroup.clinicalCare),
  theatreFlows('theatre-flows', HmsApiEndpointGroup.clinicalCare),
  therapyFlows('therapy-flows', HmsApiEndpointGroup.clinicalCare),
  drugs('drugs', HmsApiEndpointGroup.diagnosticsPharmacyBilling),
  drugBatches('drug-batches', HmsApiEndpointGroup.diagnosticsPharmacyBilling),
  formularyItems(
    'formulary-items',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  pharmacyOrders(
    'pharmacy-orders',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  pharmacyOrderItems(
    'pharmacy-order-items',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  pharmacyLocations(
    'pharmacy-locations',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  pharmacyStockOrders(
    'pharmacy-stock-orders',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  radiologyProcedures(
    'radiology-procedures',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  radiologyTests(
    'radiology-tests',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  radiologyOrders(
    'radiology-orders',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  radiologyResults(
    'radiology-results',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  dispenseLogs('dispense-logs', HmsApiEndpointGroup.diagnosticsPharmacyBilling),
  adverseEvents('adverse-events', HmsApiEndpointGroup.clinicalCare),
  inventoryItems(
    'inventory-items',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  inventoryStocks(
    'inventory-stocks',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  stockMovements(
    'stock-movements',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  suppliers('suppliers', HmsApiEndpointGroup.diagnosticsPharmacyBilling),
  purchaseRequests(
    'purchase-requests',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  purchaseOrders(
    'purchase-orders',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  goodsReceipts(
    'goods-receipts',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  stockAdjustments(
    'stock-adjustments',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  labTests('lab-tests', HmsApiEndpointGroup.diagnosticsPharmacyBilling),
  labPanels('lab-panels', HmsApiEndpointGroup.diagnosticsPharmacyBilling),
  facilityLabCatalog(
    'facility-lab-catalog',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  facilityRadiologyCatalog(
    'facility-radiology-catalog',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  facilityPharmacyCatalog(
    'facility-pharmacy-catalog',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  labOrders('lab-orders', HmsApiEndpointGroup.diagnosticsPharmacyBilling),
  labOrderItems(
    'lab-order-items',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  labSamples('lab-samples', HmsApiEndpointGroup.diagnosticsPharmacyBilling),
  labResults('lab-results', HmsApiEndpointGroup.diagnosticsPharmacyBilling),
  labQcLogs('lab-qc-logs', HmsApiEndpointGroup.diagnosticsPharmacyBilling),
  lab('lab', HmsApiEndpointGroup.diagnosticsPharmacyBilling),
  radiology('radiology', HmsApiEndpointGroup.diagnosticsPharmacyBilling),
  pharmacy('pharmacy', HmsApiEndpointGroup.diagnosticsPharmacyBilling),
  imagingStudies(
    'imaging-studies',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  imagingAssets(
    'imaging-assets',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  pacsLinks('pacs-links', HmsApiEndpointGroup.diagnosticsPharmacyBilling),
  emergencyCases('emergency-cases', HmsApiEndpointGroup.patientFlow),
  triageAssessments('triage-assessments', HmsApiEndpointGroup.patientFlow),
  emergencyResponses('emergency-responses', HmsApiEndpointGroup.patientFlow),
  ambulances('ambulances', HmsApiEndpointGroup.patientFlow),
  ambulanceDispatches('ambulance-dispatches', HmsApiEndpointGroup.patientFlow),
  ambulanceTrips('ambulance-trips', HmsApiEndpointGroup.patientFlow),
  invoices('invoices', HmsApiEndpointGroup.diagnosticsPharmacyBilling),
  invoiceItems('invoice-items', HmsApiEndpointGroup.diagnosticsPharmacyBilling),
  payments('payments', HmsApiEndpointGroup.diagnosticsPharmacyBilling),
  refunds('refunds', HmsApiEndpointGroup.diagnosticsPharmacyBilling),
  billing('billing', HmsApiEndpointGroup.diagnosticsPharmacyBilling),
  accounts('accounts', HmsApiEndpointGroup.diagnosticsPharmacyBilling),
  chartAccounts('chart-accounts', HmsApiEndpointGroup.diagnosticsPharmacyBilling),
  accountsInvoices(
    'accounts-invoices',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  pricingRules('pricing-rules', HmsApiEndpointGroup.diagnosticsPharmacyBilling),
  priceBookEntries(
    'price-book-entries',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  insuranceCompanies(
    'insurance-companies',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  coveragePlans(
    'coverage-plans',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  schemeOffers('scheme-offers', HmsApiEndpointGroup.diagnosticsPharmacyBilling),
  patientInsuranceEnrollments(
    'patient-insurance-enrollments',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  insurerIntegrations(
    'insurer-integrations',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  insuranceClaims(
    'insurance-claims',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  preAuthorizations(
    'pre-authorizations',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  claimsWorkspace(
    'claims-workspace',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  billingAdjustments(
    'billing-adjustments',
    HmsApiEndpointGroup.diagnosticsPharmacyBilling,
  ),
  payrollRuns('payroll-runs', HmsApiEndpointGroup.operations),
  payrollItems('payroll-items', HmsApiEndpointGroup.operations),
  hr('hr', HmsApiEndpointGroup.operations),
  housekeeping('housekeeping', HmsApiEndpointGroup.operations),
  biomedical('biomedical', HmsApiEndpointGroup.operations),
  mortuary('mortuary', HmsApiEndpointGroup.operations),
  staffPositions('staff-positions', HmsApiEndpointGroup.operations),
  staffProfiles('staff-profiles', HmsApiEndpointGroup.operations),
  staffAssignments('staff-assignments', HmsApiEndpointGroup.operations),
  staffLeaves('staff-leaves', HmsApiEndpointGroup.operations),
  housekeepingTasks('housekeeping-tasks', HmsApiEndpointGroup.operations),
  housekeepingSchedules(
    'housekeeping-schedules',
    HmsApiEndpointGroup.operations,
  ),
  maintenanceRequests('maintenance-requests', HmsApiEndpointGroup.operations),
  facilityAssets('assets', HmsApiEndpointGroup.operations),
  assetServiceLogs('asset-service-logs', HmsApiEndpointGroup.operations),
  equipmentCategories('equipment-categories', HmsApiEndpointGroup.operations),
  equipmentRegistries('equipment-registries', HmsApiEndpointGroup.operations),
  equipmentLocationHistories(
    'equipment-location-histories',
    HmsApiEndpointGroup.operations,
  ),
  equipmentMaintenancePlans(
    'equipment-maintenance-plans',
    HmsApiEndpointGroup.operations,
  ),
  equipmentWorkOrders('equipment-work-orders', HmsApiEndpointGroup.operations),
  equipmentCalibrationLogs(
    'equipment-calibration-logs',
    HmsApiEndpointGroup.operations,
  ),
  equipmentSafetyTestLogs(
    'equipment-safety-test-logs',
    HmsApiEndpointGroup.operations,
  ),
  equipmentDowntimeLogs(
    'equipment-downtime-logs',
    HmsApiEndpointGroup.operations,
  ),
  equipmentSpareParts('equipment-spare-parts', HmsApiEndpointGroup.operations),
  equipmentWarrantyContracts(
    'equipment-warranty-contracts',
    HmsApiEndpointGroup.operations,
  ),
  equipmentServiceProviders(
    'equipment-service-providers',
    HmsApiEndpointGroup.operations,
  ),
  equipmentIncidentReports(
    'equipment-incident-reports',
    HmsApiEndpointGroup.operations,
  ),
  equipmentRecallNotices(
    'equipment-recall-notices',
    HmsApiEndpointGroup.operations,
  ),
  equipmentUtilizationSnapshots(
    'equipment-utilization-snapshots',
    HmsApiEndpointGroup.operations,
  ),
  equipmentDisposalTransfers(
    'equipment-disposal-transfers',
    HmsApiEndpointGroup.operations,
  ),
  shifts('shifts', HmsApiEndpointGroup.operations),
  shiftAssignments('shift-assignments', HmsApiEndpointGroup.operations),
  shiftSwapRequests('shift-swap-requests', HmsApiEndpointGroup.operations),
  officeContexts('office-contexts', HmsApiEndpointGroup.operations),
  shiftCloses('shift-closes', HmsApiEndpointGroup.operations),
  dayCloses('day-closes', HmsApiEndpointGroup.operations),
  handovers('handovers', HmsApiEndpointGroup.operations),
  custodySnapshots('custody-snapshots', HmsApiEndpointGroup.operations),
  closeoutPacks('closeout-packs', HmsApiEndpointGroup.operations),
  rosters('rosters', HmsApiEndpointGroup.operations),
  shiftTemplates('shift-templates', HmsApiEndpointGroup.operations),
  rosterDayOffs('roster-day-offs', HmsApiEndpointGroup.operations),
  staffAvailabilities('staff-availabilities', HmsApiEndpointGroup.operations),
  notifications(
    'notifications',
    HmsApiEndpointGroup.communicationsReportsAuditIntegrations,
  ),
  notificationDeliveries(
    'notification-deliveries',
    HmsApiEndpointGroup.communicationsReportsAuditIntegrations,
  ),
  conversations(
    'conversations',
    HmsApiEndpointGroup.communicationsReportsAuditIntegrations,
  ),
  messages(
    'messages',
    HmsApiEndpointGroup.communicationsReportsAuditIntegrations,
  ),
  communicationsWorkspace(
    'communications-workspace',
    HmsApiEndpointGroup.communicationsReportsAuditIntegrations,
  ),
  reportDefinitions(
    'report-definitions',
    HmsApiEndpointGroup.communicationsReportsAuditIntegrations,
  ),
  reportRuns(
    'report-runs',
    HmsApiEndpointGroup.communicationsReportsAuditIntegrations,
  ),
  reportSchedules(
    'report-schedules',
    HmsApiEndpointGroup.communicationsReportsAuditIntegrations,
  ),
  dashboardWidgets(
    'dashboard-widgets',
    HmsApiEndpointGroup.communicationsReportsAuditIntegrations,
  ),
  dashboardWorkspace(
    'dashboard-workspace',
    HmsApiEndpointGroup.communicationsReportsAuditIntegrations,
  ),
  settingsWorkspace(
    'settings-workspace',
    HmsApiEndpointGroup.communicationsReportsAuditIntegrations,
  ),
  kpiSnapshots(
    'kpi-snapshots',
    HmsApiEndpointGroup.communicationsReportsAuditIntegrations,
  ),
  analyticsEvents(
    'analytics-events',
    HmsApiEndpointGroup.communicationsReportsAuditIntegrations,
  ),
  reportsWorkspace(
    'reports-workspace',
    HmsApiEndpointGroup.communicationsReportsAuditIntegrations,
  ),
  auditLogs(
    'audit-logs',
    HmsApiEndpointGroup.communicationsReportsAuditIntegrations,
  ),
  phiAccessLogs(
    'phi-access-logs',
    HmsApiEndpointGroup.communicationsReportsAuditIntegrations,
  ),
  dataProcessingLogs(
    'data-processing-logs',
    HmsApiEndpointGroup.communicationsReportsAuditIntegrations,
  ),
  breakGlassAccess(
    'break-glass-access',
    HmsApiEndpointGroup.communicationsReportsAuditIntegrations,
  ),
  breakGlassReviews(
    'break-glass-reviews',
    HmsApiEndpointGroup.communicationsReportsAuditIntegrations,
  ),
  templates(
    'templates',
    HmsApiEndpointGroup.communicationsReportsAuditIntegrations,
  ),
  templateVariables(
    'template-variables',
    HmsApiEndpointGroup.communicationsReportsAuditIntegrations,
  ),
  subscriptionsWorkspace(
    'subscriptions-workspace',
    HmsApiEndpointGroup.subscriptions,
  ),
  subscriptionPlans('subscription-plans', HmsApiEndpointGroup.subscriptions),
  subscriptions('subscriptions', HmsApiEndpointGroup.subscriptions),
  subscriptionInvoices(
    'subscription-invoices',
    HmsApiEndpointGroup.subscriptions,
  ),
  subscriptionModules('modules', HmsApiEndpointGroup.subscriptions),
  moduleSubscriptions(
    'module-subscriptions',
    HmsApiEndpointGroup.subscriptions,
  ),
  licenses('licenses', HmsApiEndpointGroup.subscriptions),
  breachNotifications(
    'breach-notifications',
    HmsApiEndpointGroup.communicationsReportsAuditIntegrations,
  ),
  systemChangeLogs(
    'system-change-logs',
    HmsApiEndpointGroup.communicationsReportsAuditIntegrations,
  ),
  integrations(
    'integrations',
    HmsApiEndpointGroup.communicationsReportsAuditIntegrations,
  ),
  integrationLogs(
    'integration-logs',
    HmsApiEndpointGroup.communicationsReportsAuditIntegrations,
  ),
  webhookSubscriptions(
    'webhook-subscriptions',
    HmsApiEndpointGroup.communicationsReportsAuditIntegrations,
  ),
  interop(
    'interop',
    HmsApiEndpointGroup.communicationsReportsAuditIntegrations,
  ),
  ai('ai', HmsApiEndpointGroup.communicationsReportsAuditIntegrations);

  const HmsApiResource(this.path, this.group);

  final String path;
  final HmsApiEndpointGroup group;
}

enum AuthEndpoint {
  csrfToken('csrf-token'),
  identify('identify'),
  login('login'),
  register('register'),
  registrationStatus('registration-status'),
  verifyEmail('verify-email'),
  verifyPhone('verify-phone'),
  resendVerification('resend-verification'),
  forgotPassword('forgot-password'),
  resetPassword('reset-password'),
  refresh('refresh'),
  changePassword('change-password'),
  logout('logout'),
  me('me');

  const AuthEndpoint(this.path);

  final String path;
}

abstract final class ApiEndpoints {
  static const String apiVersion = 'v1';
  static const String apiPrefix = '/api/v1';

  static Uri get health => _root('health');

  static Uri get readiness => _root('ready');

  static Uri get liveness => _root('live');

  static Uri auth(AuthEndpoint endpoint) {
    return apiV1(<String>[HmsApiResource.auth.path, endpoint.path]);
  }

  static Uri collection(
    HmsApiResource resource, {
    Map<String, String>? queryParameters,
  }) {
    return apiV1(<String>[resource.path], queryParameters: queryParameters);
  }

  static Uri byId(
    HmsApiResource resource,
    String id, {
    Map<String, String>? queryParameters,
  }) {
    return apiV1(<String>[resource.path, id], queryParameters: queryParameters);
  }

  static Uri nested(
    HmsApiResource resource,
    String id,
    List<String> pathSegments, {
    Map<String, String>? queryParameters,
  }) {
    return apiV1(<String>[
      resource.path,
      id,
      ...pathSegments,
    ], queryParameters: queryParameters);
  }

  static Uri apiV1(
    List<String> pathSegments, {
    Map<String, String>? queryParameters,
  }) {
    return Uri(
      pathSegments: <String>['', 'api', apiVersion, ...pathSegments],
      queryParameters: queryParameters,
    );
  }

  static Uri _root(String path) {
    return Uri(pathSegments: <String>['', path]);
  }
}
