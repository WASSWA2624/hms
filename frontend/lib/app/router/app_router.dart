import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hosspi_hms/app/router/app_route_icons.dart';
import 'package:hosspi_hms/app/router/app_routes.dart';
import 'package:hosspi_hms/app/router/route_guards.dart';
import 'package:hosspi_hms/app/router/route_refresh_listenable.dart';
import 'package:hosspi_hms/app/router/route_status_pages.dart';
import 'package:hosspi_hms/app/router/shell_badge_counts.dart';
import 'package:hosspi_hms/app/router/shell_route_access.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/network/app_connectivity_status.dart';
import 'package:hosspi_hms/core/permissions/access_policy.dart';
import 'package:hosspi_hms/core/permissions/permission_providers.dart';
import 'package:hosspi_hms/core/security/auth_session.dart';
import 'package:hosspi_hms/core/security/session_controller.dart';
import 'package:hosspi_hms/core/subscriptions/tenant_subscription_summary.dart';
import 'package:hosspi_hms/features/access_admin/domain/entities/access_admin_entities.dart';
import 'package:hosspi_hms/features/access_admin/presentation/pages/access_admin_workspace_page.dart';
import 'package:hosspi_hms/features/accounts/domain/entities/accounts_entities.dart';
import 'package:hosspi_hms/features/accounts/presentation/controllers/accounts_workspace_controller.dart';
import 'package:hosspi_hms/features/accounts/presentation/pages/accounts_workspace_page.dart';
import 'package:hosspi_hms/features/accounts/presentation/widgets/accounts_scope_navigation.dart';
import 'package:hosspi_hms/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:hosspi_hms/features/auth/presentation/pages/forgot_password_page.dart';
import 'package:hosspi_hms/features/auth/presentation/pages/login_page.dart';
import 'package:hosspi_hms/features/auth/presentation/pages/register_page.dart';
import 'package:hosspi_hms/features/auth/presentation/pages/reset_password_page.dart';
import 'package:hosspi_hms/features/auth/presentation/pages/verify_email_page.dart';
import 'package:hosspi_hms/features/auth/presentation/widgets/auth_shell_layout.dart';
import 'package:hosspi_hms/features/billing/domain/entities/billing_entities.dart';
import 'package:hosspi_hms/features/billing/presentation/pages/billing_workspace_page.dart';
import 'package:hosspi_hms/features/biomedical/domain/entities/biomedical_entities.dart';
import 'package:hosspi_hms/features/biomedical/presentation/pages/biomedical_workspace_page.dart';
import 'package:hosspi_hms/features/claims/domain/entities/claims_entities.dart';
import 'package:hosspi_hms/features/claims/presentation/pages/claims_workspace_page.dart';
import 'package:hosspi_hms/features/clinical/domain/entities/clinical_entities.dart';
import 'package:hosspi_hms/features/clinical/presentation/pages/clinical_workspace_page.dart';
import 'package:hosspi_hms/features/communications/domain/entities/communications_entities.dart';
import 'package:hosspi_hms/features/communications/presentation/pages/communications_workspace_page.dart';
import 'package:hosspi_hms/features/discharge/domain/entities/discharge_entities.dart';
import 'package:hosspi_hms/features/discharge/presentation/pages/discharge_workspace_page.dart';
import 'package:hosspi_hms/features/emergency/domain/entities/emergency_entities.dart';
import 'package:hosspi_hms/features/emergency/presentation/pages/emergency_workspace_page.dart';
import 'package:hosspi_hms/features/home/domain/entities/home_dashboard.dart';
import 'package:hosspi_hms/features/home/presentation/pages/home_page.dart';
import 'package:hosspi_hms/features/housekeeping/domain/entities/housekeeping_entities.dart';
import 'package:hosspi_hms/features/housekeeping/presentation/pages/housekeeping_workspace_page.dart';
import 'package:hosspi_hms/features/hr/domain/entities/hr_entities.dart';
import 'package:hosspi_hms/features/hr/presentation/pages/hr_workspace_page.dart';
import 'package:hosspi_hms/features/icu/domain/entities/icu_entities.dart';
import 'package:hosspi_hms/features/icu/presentation/pages/icu_workspace_page.dart';
import 'package:hosspi_hms/features/integrations/domain/entities/integration_entities.dart';
import 'package:hosspi_hms/features/integrations/presentation/pages/integrations_workspace_page.dart';
import 'package:hosspi_hms/features/ipd/domain/entities/ipd_entities.dart';
import 'package:hosspi_hms/features/ipd/presentation/pages/ipd_workspace_page.dart';
import 'package:hosspi_hms/features/lab/domain/entities/lab_entities.dart';
import 'package:hosspi_hms/features/lab/presentation/pages/lab_workspace_page.dart';
import 'package:hosspi_hms/features/mortuary/domain/entities/mortuary_entities.dart';
import 'package:hosspi_hms/features/mortuary/presentation/pages/mortuary_workspace_page.dart';
import 'package:hosspi_hms/features/nursing/domain/entities/nursing_entities.dart';
import 'package:hosspi_hms/features/nursing/presentation/pages/nursing_workspace_page.dart';
import 'package:hosspi_hms/features/opd/domain/entities/opd_entities.dart';
import 'package:hosspi_hms/features/opd/presentation/pages/opd_workspace_page.dart';
import 'package:hosspi_hms/features/operations/domain/entities/operations_entities.dart';
import 'package:hosspi_hms/features/operations/presentation/pages/operations_workspace_page.dart';
import 'package:hosspi_hms/features/patients/domain/entities/patient_entities.dart';
import 'package:hosspi_hms/features/patients/presentation/pages/patient_registry_page.dart';
import 'package:hosspi_hms/features/pharmacy/domain/entities/pharmacy_entities.dart';
import 'package:hosspi_hms/features/pharmacy/presentation/pages/pharmacy_workspace_page.dart';
import 'package:hosspi_hms/features/physiotherapy/domain/entities/physiotherapy_entities.dart';
import 'package:hosspi_hms/features/physiotherapy/presentation/pages/physiotherapy_workspace_page.dart';
import 'package:hosspi_hms/features/radiology/domain/entities/radiology_entities.dart';
import 'package:hosspi_hms/features/radiology/presentation/pages/radiology_workspace_page.dart';
import 'package:hosspi_hms/features/reception/domain/entities/reception_entities.dart';
import 'package:hosspi_hms/features/reception/presentation/pages/reception_workspace_page.dart';
import 'package:hosspi_hms/features/reports/presentation/pages/reports_workspace_page.dart';
import 'package:hosspi_hms/features/rooms_beds/domain/entities/rooms_beds_entities.dart';
import 'package:hosspi_hms/features/rooms_beds/presentation/pages/rooms_beds_workspace_page.dart';
import 'package:hosspi_hms/features/settings/presentation/pages/settings_page.dart'
    show SettingsPage, SettingsPageQuery;
import 'package:hosspi_hms/features/settings/presentation/widgets/settings_account_section.dart';
import 'package:hosspi_hms/features/subscriptions/domain/entities/subscription_entities.dart';
import 'package:hosspi_hms/features/subscriptions/presentation/pages/subscriptions_workspace_page.dart';
import 'package:hosspi_hms/features/subscriptions/presentation/widgets/subscription_expired_prompt.dart';
import 'package:hosspi_hms/features/subscriptions/presentation/widgets/subscription_header_button.dart';
import 'package:hosspi_hms/features/subscriptions/presentation/widgets/subscription_report_admins_dialog.dart';
import 'package:hosspi_hms/features/subscriptions/presentation/widgets/subscription_upgrade_dialog.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/pages/tenant_facility_setup_page.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/widgets/tenant_facility_setup_helpers.dart';
import 'package:hosspi_hms/features/theater/domain/entities/theater_entities.dart';
import 'package:hosspi_hms/features/theater/presentation/pages/theater_workspace_page.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/layout/app_shell_sidebar_preference.dart';
import 'package:hosspi_hms/shared/layout/responsive_shell_scaffold.dart';
import 'package:hosspi_hms/shared/layout/shell_navigation_loading.dart';

final appInitialLocationProvider = Provider<String?>((ref) {
  return null;
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final String? initialLocation = ref.watch(appInitialLocationProvider);
  final RouteRefreshListenable refreshListenable = ref.watch(
    routeRefreshListenableProvider,
  );

  return GoRouter(
    initialLocation: initialLocation,
    overridePlatformDefaultLocation: initialLocation != null,
    refreshListenable: refreshListenable,
    redirect: (_, GoRouterState state) {
      final AppRouteGuards guards = AppRouteGuards(
        sessionState: ref.read(sessionStateProvider),
      );

      return guards.redirect(
        AppRouteGuardRequest(
          location: state.uri,
          grantedPermissions: ref.read(grantedAppPermissionsProvider),
        ),
      );
    },
    routes: <RouteBase>[
      ShellRoute(
        builder: (_, GoRouterState state, Widget child) {
          return _AppShell(location: state.uri, child: child);
        },
        routes: <RouteBase>[
          GoRoute(
            path: AppRoutes.home.path,
            name: AppRoutes.home.name,
            builder: (_, GoRouterState state) => HomePage(
              request: HomeDashboardRequest.fromQuery(
                state.uri.queryParameters,
              ),
            ),
          ),
          GoRoute(
            path: AppRoutes.patients.path,
            name: AppRoutes.patients.name,
            builder: (_, GoRouterState state) => PatientRegistryPage(
              initialQuery: PatientListQuery.fromUri(state.uri),
            ),
          ),
          GoRoute(
            path: AppRoutes.reception.path,
            name: AppRoutes.reception.name,
            builder: (_, GoRouterState state) {
              return ReceptionWorkspacePage(
                initialQuery: ReceptionWorkspaceQuery.fromUri(state.uri),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.billing.path,
            name: AppRoutes.billing.name,
            builder: (_, GoRouterState state) => BillingWorkspacePage(
              initialQuery: BillingWorkspaceQuery.fromUri(state.uri),
            ),
          ),
          GoRoute(
            path: AppRoutes.accounts.path,
            name: AppRoutes.accounts.name,
            builder: (_, GoRouterState state) => AccountsWorkspacePage(
              initialQuery: AccountsWorkspaceQuery.fromUri(state.uri),
            ),
          ),
          GoRoute(
            path: AppRoutes.claims.path,
            name: AppRoutes.claims.name,
            builder: (_, GoRouterState state) {
              return ClaimsWorkspacePage(
                initialQuery: ClaimsWorkspaceQuery.fromUri(state.uri),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.subscriptions.path,
            name: AppRoutes.subscriptions.name,
            builder: (_, GoRouterState state) {
              return SubscriptionsWorkspacePage(
                initialQuery: SubscriptionsWorkspaceQuery.fromUri(state.uri),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.opd.path,
            name: AppRoutes.opd.name,
            builder: (_, GoRouterState state) {
              return OpdWorkspacePage(
                initialQuery: OpdWorkspaceQuery.fromUri(state.uri),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.emergency.path,
            name: AppRoutes.emergency.name,
            builder: (_, GoRouterState state) {
              return EmergencyWorkspacePage(
                initialQuery: EmergencyWorkspaceQuery.fromUri(state.uri),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.ipd.path,
            name: AppRoutes.ipd.name,
            builder: (_, GoRouterState state) {
              return IpdWorkspacePage(
                initialQuery: IpdAdmissionQuery.fromUri(state.uri),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.roomsBeds.path,
            name: AppRoutes.roomsBeds.name,
            builder: (_, GoRouterState state) {
              return RoomsBedsWorkspacePage(
                initialQuery: RoomsBedsQuery.fromUri(state.uri),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.icu.path,
            name: AppRoutes.icu.name,
            builder: (_, GoRouterState state) {
              return IcuWorkspacePage(
                initialQuery: IcuBoardQuery.fromUri(state.uri),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.nursing.path,
            name: AppRoutes.nursing.name,
            builder: (_, GoRouterState state) {
              return NursingWorkspacePage(
                initialQuery: NursingWorkspaceQuery.fromUri(state.uri),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.clinical.path,
            name: AppRoutes.clinical.name,
            builder: (_, GoRouterState state) {
              return ClinicalWorkspacePage(
                initialQuery: ClinicalWorkspaceQuery.fromUri(state.uri),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.physiotherapy.path,
            name: AppRoutes.physiotherapy.name,
            builder: (_, GoRouterState state) {
              return PhysiotherapyWorkspacePage(
                initialQuery: PhysiotherapyWorkspaceQuery.fromUri(state.uri),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.lab.path,
            name: AppRoutes.lab.name,
            builder: (_, GoRouterState state) {
              return LabWorkspacePage(
                initialQuery: LabWorkspaceQuery.fromUri(state.uri),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.radiology.path,
            name: AppRoutes.radiology.name,
            builder: (_, GoRouterState state) {
              return RadiologyWorkspacePage(
                initialQuery: RadiologyWorkspaceQuery.fromUri(state.uri),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.pharmacy.path,
            name: AppRoutes.pharmacy.name,
            builder: (_, GoRouterState state) {
              return PharmacyWorkspacePage(
                initialQuery: PharmacyWorkspaceQuery.fromUri(state.uri),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.operations.path,
            name: AppRoutes.operations.name,
            builder: (_, GoRouterState state) {
              return OperationsWorkspacePage(
                initialQuery: OperationsWorkspaceQuery.fromUri(state.uri),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.housekeeping.path,
            name: AppRoutes.housekeeping.name,
            builder: (_, GoRouterState state) {
              final String? section = state.uri.queryParameters['section'];
              final String? search = state.uri.queryParameters['search'];
              return HousekeepingWorkspacePage(
                initialSection: HousekeepingSection.fromQueryValue(section),
                initialSearch: search ?? '',
              );
            },
          ),
          GoRoute(
            path: AppRoutes.hr.path,
            name: AppRoutes.hr.name,
            builder: (_, GoRouterState state) {
              return HrWorkspacePage(
                initialQuery: HrWorkspaceQuery.fromUri(state.uri),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.biomedical.path,
            name: AppRoutes.biomedical.name,
            builder: (_, GoRouterState state) => BiomedicalWorkspacePage(
              initialQuery: BiomedicalRouteQuery.fromUri(state.uri),
            ),
          ),
          GoRoute(
            path: AppRoutes.communications.path,
            name: AppRoutes.communications.name,
            builder: (_, GoRouterState state) {
              return CommunicationsWorkspacePage(
                initialQuery: CommunicationsWorkspaceQuery.fromUri(state.uri),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.integrations.path,
            name: AppRoutes.integrations.name,
            builder: (_, GoRouterState state) {
              return IntegrationsWorkspacePage(
                initialQuery: IntegrationWorkspaceQuery.fromUri(state.uri),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.discharge.path,
            name: AppRoutes.discharge.name,
            builder: (_, GoRouterState state) {
              return DischargeWorkspacePage(
                initialQuery: DischargeWorklistQuery.fromUri(state.uri),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.mortuary.path,
            name: AppRoutes.mortuary.name,
            builder: (_, GoRouterState state) => MortuaryWorkspacePage(
              initialQuery: MortuaryRouteQuery.fromUri(state.uri),
            ),
          ),
          GoRoute(
            path: AppRoutes.theater.path,
            name: AppRoutes.theater.name,
            builder: (_, GoRouterState state) {
              return TheaterWorkspacePage(
                initialQuery: TheaterBoardQuery.fromUri(state.uri),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.reports.path,
            name: AppRoutes.reports.name,
            builder: (_, GoRouterState state) => ReportsWorkspacePage(
              initialQuery: ReportsWorkspacePageQuery.fromUri(state.uri),
            ),
          ),
          GoRoute(
            path: AppRoutes.settings.path,
            name: AppRoutes.settings.name,
            builder: (_, GoRouterState state) => SettingsPage(
              initialQuery: SettingsPageQuery.fromUri(state.uri),
            ),
          ),
          GoRoute(
            path: AppRoutes.tenantFacilitySetup.path,
            name: AppRoutes.tenantFacilitySetup.name,
            builder: (_, GoRouterState state) => TenantFacilitySetupPage(
              initialQuery: TenantFacilitySetupPageQuery.fromUri(state.uri),
            ),
          ),
          GoRoute(
            path: AppRoutes.accessAdmin.path,
            name: AppRoutes.accessAdmin.name,
            builder: (_, GoRouterState state) {
              return AccessAdminWorkspacePage(
                initialQuery: AccessAdminWorkspaceQuery.fromUri(state.uri),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.profile.path,
            name: AppRoutes.profile.name,
            redirect: (_, _) => const SettingsPageQuery(
              tab: 'account',
              panel: SettingsAccountSection.profilePanel,
            ).location(),
          ),
        ],
      ),
      ShellRoute(
        builder: (_, _, Widget child) => AuthShellLayout(child: child),
        routes: <RouteBase>[
          GoRoute(
            path: AppRoutes.login.path,
            name: AppRoutes.login.name,
            pageBuilder: (_, GoRouterState state) {
              return NoTransitionPage<void>(
                key: state.pageKey,
                child: LoginPage(from: state.uri.queryParameters['from']),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.register.path,
            name: AppRoutes.register.name,
            pageBuilder: (_, GoRouterState state) {
              return NoTransitionPage<void>(
                key: state.pageKey,
                child: const RegisterPage(),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.verifyEmail.path,
            name: AppRoutes.verifyEmail.name,
            pageBuilder: (_, GoRouterState state) {
              return NoTransitionPage<void>(
                key: state.pageKey,
                child: VerifyEmailPage(
                  token: state.uri.queryParameters['token'],
                  email: state.uri.queryParameters['email'],
                  reason: state.uri.queryParameters['reason'],
                ),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.forgotPassword.path,
            name: AppRoutes.forgotPassword.name,
            pageBuilder: (_, GoRouterState state) {
              return NoTransitionPage<void>(
                key: state.pageKey,
                child: const ForgotPasswordPage(),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.resetPassword.path,
            name: AppRoutes.resetPassword.name,
            pageBuilder: (_, GoRouterState state) {
              return NoTransitionPage<void>(
                key: state.pageKey,
                child: ResetPasswordPage(
                  token: state.uri.queryParameters['token'],
                  email: state.uri.queryParameters['email'],
                ),
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.sessionRestoring.path,
        name: AppRoutes.sessionRestoring.name,
        builder: (_, _) => const SessionRestoringPage(),
      ),
      GoRoute(
        path: AppRoutes.authRequired.path,
        name: AppRoutes.authRequired.name,
        builder: (_, _) => const AuthRequiredPage(),
      ),
      GoRoute(
        path: AppRoutes.forbidden.path,
        name: AppRoutes.forbidden.name,
        builder: (_, _) => const ForbiddenPage(),
      ),
    ],
    errorBuilder: (_, GoRouterState state) {
      return NotFoundPage(location: state.uri.path);
    },
  );
});

final class _ShellDestinationRoute {
  const _ShellDestinationRoute({
    required this.route,
    required this.destination,
  });

  final AppRouteData route;
  final ResponsiveShellDestination destination;
}

List<_ShellDestinationRoute> _localizedShellDestinations(
  AppLocalizations l10n, {
  required AppAccessPolicy accessPolicy,
  int? billingWorkloadCount,
  int? accountsWorkloadCount,
  int? claimsWorkloadCount,
  int? subscriptionsWorkloadCount,
  int? receptionPatientCount,
  int? opdWorkloadCount,
  int? emergencyWorkloadCount,
  int? ipdWorkloadCount,
  int? roomsBedsWorkloadCount,
  int? icuCriticalCount,
  int? nursingWorkloadCount,
  int? clinicalWorkloadCount,
  int? labWorkloadCount,
  int? radiologyWorkloadCount,
  int? pharmacyWorkloadCount,
  int? operationsWorkloadCount,
  int? housekeepingWorkloadCount,
  int? hrWorkloadCount,
  int? biomedicalWorkloadCount,
  int? communicationsWorkloadCount,
  int? integrationsWorkloadCount,
  int? dischargeWorkloadCount,
  int? mortuaryWorkloadCount,
  int? theaterWorkloadCount,
  List<ShellSubmenuItem> accountsMenuChildren = const <ShellSubmenuItem>[],
}) {
  // Navigation groups follow primary hospital workflows:
  // - Overview: landing dashboard
  // - Patient intake: register â†’ outpatient visit â†’ emergency triage
  // - Inpatient care: admit â†’ bed capacity â†’ ICU â†’ ward nursing
  // - Clinical care: documentation, rehab, surgery, discharge planning
  // - Diagnostics & pharmacy: investigations and medication dispensing
  // - Billing & revenue: charges â†’ insurance claims â†’ subscription plans
  // - Facility services: non-clinical hospital operations
  // - Administration: people, comms, integrations, reporting, configuration
  final String overviewGroup = l10n.navigationGroupOverviewLabel;
  final String patientIntakeGroup = l10n.navigationGroupPatientAccessLabel;
  final String inpatientCareGroup = l10n.navigationGroupInpatientCareLabel;
  final String clinicalCareGroup = l10n.navigationGroupClinicalServicesLabel;
  final String diagnosticsPharmacyGroup =
      l10n.navigationGroupDiagnosticsMedicationLabel;
  final String billingRevenueGroup = l10n.navigationGroupRevenueCycleLabel;
  final String facilityServicesGroup =
      l10n.navigationGroupFacilityOperationsLabel;
  final String administrationGroup = l10n.navigationGroupAdministrationLabel;

  return <_ShellDestinationRoute>[
    _ShellDestinationRoute(
      route: AppRoutes.home,
      destination: ResponsiveShellDestination(
        label: l10n.navigationHomeLabel,
        shortLabel: l10n.navigationHomeShortLabel,
        groupLabel: overviewGroup,
        icon: AppRouteIcons.home,
        selectedIcon: AppRouteIcons.homeSelected,
      ),
    ),
    _ShellDestinationRoute(
      route: AppRoutes.reception,
      destination: ResponsiveShellDestination(
        label: l10n.navigationReceptionLabel,
        shortLabel: l10n.navigationReceptionShortLabel,
        groupLabel: patientIntakeGroup,
        icon: AppRouteIcons.reception,
        selectedIcon: AppRouteIcons.receptionSelected,
        badgeCount: receptionPatientCount,
      ),
    ),
    _ShellDestinationRoute(
      route: AppRoutes.patients,
      destination: ResponsiveShellDestination(
        label: l10n.navigationPatientsLabel,
        shortLabel: l10n.navigationPatientsShortLabel,
        groupLabel: patientIntakeGroup,
        icon: AppRouteIcons.patients,
        selectedIcon: AppRouteIcons.patientsSelected,
      ),
    ),
    _ShellDestinationRoute(
      route: AppRoutes.opd,
      destination: ResponsiveShellDestination(
        label: l10n.navigationOpdLabel,
        shortLabel: l10n.navigationOpdShortLabel,
        groupLabel: patientIntakeGroup,
        icon: AppRouteIcons.opd,
        selectedIcon: AppRouteIcons.opdSelected,
        badgeCount: opdWorkloadCount,
      ),
    ),
    _ShellDestinationRoute(
      route: AppRoutes.emergency,
      destination: ResponsiveShellDestination(
        label: l10n.navigationEmergencyLabel,
        shortLabel: l10n.navigationEmergencyShortLabel,
        groupLabel: patientIntakeGroup,
        icon: AppRouteIcons.emergency,
        selectedIcon: AppRouteIcons.emergencySelected,
        badgeCount: emergencyWorkloadCount,
      ),
    ),
    _ShellDestinationRoute(
      route: AppRoutes.ipd,
      destination: ResponsiveShellDestination(
        label: l10n.navigationIpdLabel,
        shortLabel: l10n.navigationIpdShortLabel,
        groupLabel: inpatientCareGroup,
        icon: AppRouteIcons.ipd,
        selectedIcon: AppRouteIcons.ipdSelected,
        badgeCount: ipdWorkloadCount,
      ),
    ),
    _ShellDestinationRoute(
      route: AppRoutes.roomsBeds,
      destination: ResponsiveShellDestination(
        label: l10n.navigationRoomsBedsLabel,
        shortLabel: l10n.navigationRoomsBedsShortLabel,
        groupLabel: inpatientCareGroup,
        icon: AppRouteIcons.roomsBeds,
        selectedIcon: AppRouteIcons.roomsBedsSelected,
        badgeCount: roomsBedsWorkloadCount,
      ),
    ),
    _ShellDestinationRoute(
      route: AppRoutes.icu,
      destination: ResponsiveShellDestination(
        label: l10n.navigationIcuLabel,
        shortLabel: l10n.navigationIcuShortLabel,
        groupLabel: inpatientCareGroup,
        icon: AppRouteIcons.icu,
        selectedIcon: AppRouteIcons.icuSelected,
        badgeCount: icuCriticalCount,
      ),
    ),
    _ShellDestinationRoute(
      route: AppRoutes.nursing,
      destination: ResponsiveShellDestination(
        label: l10n.navigationNursingLabel,
        shortLabel: l10n.navigationNursingShortLabel,
        groupLabel: inpatientCareGroup,
        icon: AppRouteIcons.nursing,
        selectedIcon: AppRouteIcons.nursingSelected,
        badgeCount: nursingWorkloadCount,
      ),
    ),
    _ShellDestinationRoute(
      route: AppRoutes.clinical,
      destination: ResponsiveShellDestination(
        label: l10n.navigationClinicalLabel,
        shortLabel: l10n.navigationClinicalShortLabel,
        groupLabel: clinicalCareGroup,
        icon: AppRouteIcons.clinical,
        selectedIcon: AppRouteIcons.clinicalSelected,
        badgeCount: clinicalWorkloadCount,
      ),
    ),
    _ShellDestinationRoute(
      route: AppRoutes.physiotherapy,
      destination: ResponsiveShellDestination(
        label: l10n.navigationPhysiotherapyLabel,
        shortLabel: l10n.navigationPhysiotherapyShortLabel,
        groupLabel: clinicalCareGroup,
        icon: AppRouteIcons.physiotherapy,
        selectedIcon: AppRouteIcons.physiotherapySelected,
      ),
    ),
    _ShellDestinationRoute(
      route: AppRoutes.theater,
      destination: ResponsiveShellDestination(
        label: l10n.navigationTheaterLabel,
        shortLabel: l10n.navigationTheaterShortLabel,
        groupLabel: clinicalCareGroup,
        icon: AppRouteIcons.theater,
        selectedIcon: AppRouteIcons.theaterSelected,
        badgeCount: theaterWorkloadCount,
      ),
    ),
    _ShellDestinationRoute(
      route: AppRoutes.discharge,
      destination: ResponsiveShellDestination(
        label: l10n.navigationDischargeLabel,
        shortLabel: l10n.navigationDischargeShortLabel,
        groupLabel: clinicalCareGroup,
        icon: AppRouteIcons.discharge,
        selectedIcon: AppRouteIcons.dischargeSelected,
        badgeCount: dischargeWorkloadCount,
      ),
    ),
    _ShellDestinationRoute(
      route: AppRoutes.lab,
      destination: ResponsiveShellDestination(
        label: l10n.navigationLabLabel,
        shortLabel: l10n.navigationLabShortLabel,
        groupLabel: diagnosticsPharmacyGroup,
        icon: AppRouteIcons.lab,
        selectedIcon: AppRouteIcons.labSelected,
        badgeCount: labWorkloadCount,
      ),
    ),
    _ShellDestinationRoute(
      route: AppRoutes.radiology,
      destination: ResponsiveShellDestination(
        label: l10n.navigationRadiologyLabel,
        shortLabel: l10n.navigationRadiologyShortLabel,
        groupLabel: diagnosticsPharmacyGroup,
        icon: AppRouteIcons.radiology,
        selectedIcon: AppRouteIcons.radiologySelected,
        badgeCount: radiologyWorkloadCount,
      ),
    ),
    _ShellDestinationRoute(
      route: AppRoutes.pharmacy,
      destination: ResponsiveShellDestination(
        label: l10n.navigationPharmacyLabel,
        shortLabel: l10n.navigationPharmacyShortLabel,
        groupLabel: diagnosticsPharmacyGroup,
        icon: AppRouteIcons.pharmacy,
        selectedIcon: AppRouteIcons.pharmacySelected,
        badgeCount: pharmacyWorkloadCount,
      ),
    ),
    _ShellDestinationRoute(
      route: AppRoutes.billing,
      destination: ResponsiveShellDestination(
        label: l10n.navigationBillingLabel,
        shortLabel: l10n.navigationBillingShortLabel,
        groupLabel: billingRevenueGroup,
        icon: AppRouteIcons.billing,
        selectedIcon: AppRouteIcons.billingSelected,
        badgeCount: billingWorkloadCount,
      ),
    ),
    _ShellDestinationRoute(
      route: AppRoutes.accounts,
      destination: ResponsiveShellDestination(
        label: l10n.navigationAccountsLabel,
        shortLabel: l10n.navigationAccountsShortLabel,
        groupLabel: billingRevenueGroup,
        icon: AppRouteIcons.accounts,
        selectedIcon: AppRouteIcons.accountsSelected,
        badgeCount: accountsWorkloadCount,
        // Accounts & Finance is the one expandable finance menu; its
        // categories and leaves are menu items, never in-page tabs.
        children: accountsMenuChildren,
      ),
    ),
    _ShellDestinationRoute(
      route: AppRoutes.claims,
      destination: ResponsiveShellDestination(
        label: l10n.navigationClaimsLabel,
        shortLabel: l10n.navigationClaimsShortLabel,
        groupLabel: billingRevenueGroup,
        icon: AppRouteIcons.claims,
        selectedIcon: AppRouteIcons.claimsSelected,
        badgeCount: claimsWorkloadCount,
      ),
    ),
    _ShellDestinationRoute(
      route: AppRoutes.subscriptions,
      destination: ResponsiveShellDestination(
        label: l10n.navigationSubscriptionsLabel,
        shortLabel: l10n.navigationSubscriptionsShortLabel,
        groupLabel: billingRevenueGroup,
        icon: AppRouteIcons.subscriptions,
        selectedIcon: AppRouteIcons.subscriptionsSelected,
        badgeCount: subscriptionsWorkloadCount,
      ),
    ),
    _ShellDestinationRoute(
      route: AppRoutes.operations,
      destination: ResponsiveShellDestination(
        label: l10n.navigationOperationsLabel,
        shortLabel: l10n.navigationOperationsShortLabel,
        groupLabel: facilityServicesGroup,
        icon: AppRouteIcons.operations,
        selectedIcon: AppRouteIcons.operationsSelected,
        badgeCount: operationsWorkloadCount,
      ),
    ),
    _ShellDestinationRoute(
      route: AppRoutes.housekeeping,
      destination: ResponsiveShellDestination(
        label: l10n.navigationHousekeepingLabel,
        shortLabel: l10n.navigationHousekeepingShortLabel,
        groupLabel: facilityServicesGroup,
        icon: AppRouteIcons.housekeeping,
        selectedIcon: AppRouteIcons.housekeepingSelected,
        badgeCount: housekeepingWorkloadCount,
      ),
    ),
    _ShellDestinationRoute(
      route: AppRoutes.biomedical,
      destination: ResponsiveShellDestination(
        label: l10n.navigationBiomedicalLabel,
        shortLabel: l10n.navigationBiomedicalShortLabel,
        groupLabel: facilityServicesGroup,
        icon: AppRouteIcons.biomedical,
        selectedIcon: AppRouteIcons.biomedicalSelected,
        badgeCount: biomedicalWorkloadCount,
      ),
    ),
    _ShellDestinationRoute(
      route: AppRoutes.mortuary,
      destination: ResponsiveShellDestination(
        label: l10n.navigationMortuaryLabel,
        shortLabel: l10n.navigationMortuaryShortLabel,
        groupLabel: facilityServicesGroup,
        icon: AppRouteIcons.mortuary,
        selectedIcon: AppRouteIcons.mortuarySelected,
        badgeCount: mortuaryWorkloadCount,
      ),
    ),
    _ShellDestinationRoute(
      route: AppRoutes.hr,
      destination: ResponsiveShellDestination(
        label: l10n.navigationHrLabel,
        shortLabel: l10n.navigationHrShortLabel,
        groupLabel: administrationGroup,
        icon: AppRouteIcons.hr,
        selectedIcon: AppRouteIcons.hrSelected,
        badgeCount: hrWorkloadCount,
      ),
    ),
    _ShellDestinationRoute(
      route: AppRoutes.communications,
      destination: ResponsiveShellDestination(
        label: l10n.navigationCommunicationsLabel,
        shortLabel: l10n.navigationCommunicationsShortLabel,
        groupLabel: administrationGroup,
        icon: AppRouteIcons.communications,
        selectedIcon: AppRouteIcons.communicationsSelected,
        badgeCount: communicationsWorkloadCount,
      ),
    ),
    _ShellDestinationRoute(
      route: AppRoutes.integrations,
      destination: ResponsiveShellDestination(
        label: l10n.navigationIntegrationsLabel,
        shortLabel: l10n.navigationIntegrationsShortLabel,
        groupLabel: administrationGroup,
        icon: AppRouteIcons.integrations,
        selectedIcon: AppRouteIcons.integrationsSelected,
        badgeCount: integrationsWorkloadCount,
      ),
    ),
    _ShellDestinationRoute(
      route: AppRoutes.reports,
      destination: ResponsiveShellDestination(
        label: l10n.navigationReportsLabel,
        shortLabel: l10n.navigationReportsShortLabel,
        groupLabel: administrationGroup,
        icon: AppRouteIcons.reports,
        selectedIcon: AppRouteIcons.reportsSelected,
      ),
    ),
    _ShellDestinationRoute(
      route: AppRoutes.settings,
      destination: ResponsiveShellDestination(
        label: l10n.navigationSettingsLabel,
        shortLabel: l10n.navigationSettingsShortLabel,
        groupLabel: administrationGroup,
        icon: AppRouteIcons.settings,
        selectedIcon: AppRouteIcons.settingsSelected,
      ),
    ),
    _ShellDestinationRoute(
      route: AppRoutes.tenantFacilitySetup,
      destination: ResponsiveShellDestination(
        label: tenantFacilitySetupNavigationLabel(accessPolicy, l10n),
        shortLabel: l10n.navigationSetupShortLabel,
        groupLabel: administrationGroup,
        icon: AppRouteIcons.setup,
        selectedIcon: AppRouteIcons.setupSelected,
      ),
    ),
  ];
}

class _AppShell extends ConsumerWidget {
  const _AppShell({required this.location, required this.child});

  final Uri location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final accessPolicy = ref.watch(appAccessPolicyProvider);
    final bool canAccessCommunications = _canAccessShellRoute(
      AppRoutes.communications,
      accessPolicy,
    );
    final ShellBadgeCounts badges = ref.watch(shellBadgeCountsProvider);
    final bool canAccessAccounts = _canAccessShellRoute(
      AppRoutes.accounts,
      accessPolicy,
    );
    // Category badges sum their sections' scope totals from the workspace
    // summary the shell already loads. Filtered counts stay on the workspace
    // tab strip, which owns the query; the menu must not depend on panel state.
    final AccountsSummary? accountsSummary = canAccessAccounts
        ? ref.watch(
            accountsWorkspaceControllerProvider.select(
              (AsyncValue<Result<AccountsWorkspaceState>> value) =>
                  switch (value.asData?.value) {
                    ResultSuccess<AccountsWorkspaceState>(value: final state) =>
                      state.overview.summary,
                    _ => null,
                  },
            ),
          )
        : null;
    final List<ShellSubmenuItem> accountsMenuChildren = canAccessAccounts
        ? accountsShellMenuChildren(
            accessPolicy: accessPolicy,
            badgeCount: accountsSummary == null
                ? null
                : (AccountsDeskCategory category) =>
                      accountsCategorySummaryCount(
                        accountsSummary,
                        accountsVisibleCategorySections(accessPolicy, category),
                      ),
          )
        : const <ShellSubmenuItem>[];
    final List<_ShellDestinationRoute> shellDestinations =
        _localizedShellDestinations(
              l10n,
              accessPolicy: accessPolicy,
              accountsMenuChildren: accountsMenuChildren,
              billingWorkloadCount: badges.billingWorkloadCount,
              accountsWorkloadCount: badges.accountsWorkloadCount,
              claimsWorkloadCount: badges.claimsWorkloadCount,
              subscriptionsWorkloadCount: badges.subscriptionsWorkloadCount,
              receptionPatientCount: badges.receptionPatientCount,
              opdWorkloadCount: badges.opdWorkloadCount,
              emergencyWorkloadCount: badges.emergencyWorkloadCount,
              ipdWorkloadCount: badges.ipdWorkloadCount,
              roomsBedsWorkloadCount: badges.roomsBedsWorkloadCount,
              icuCriticalCount: badges.icuCriticalCount,
              nursingWorkloadCount: badges.nursingWorkloadCount,
              clinicalWorkloadCount: badges.clinicalWorkloadCount,
              labWorkloadCount: badges.labWorkloadCount,
              radiologyWorkloadCount: badges.radiologyWorkloadCount,
              pharmacyWorkloadCount: badges.pharmacyWorkloadCount,
              operationsWorkloadCount: badges.operationsWorkloadCount,
              housekeepingWorkloadCount: badges.housekeepingWorkloadCount,
              hrWorkloadCount: badges.hrWorkloadCount,
              biomedicalWorkloadCount: badges.biomedicalWorkloadCount,
              communicationsWorkloadCount: badges.communicationsWorkloadCount,
              integrationsWorkloadCount: badges.integrationsWorkloadCount,
              dischargeWorkloadCount: badges.dischargeWorkloadCount,
              mortuaryWorkloadCount: badges.mortuaryWorkloadCount,
              theaterWorkloadCount: badges.theaterWorkloadCount,
            )
            .where((_ShellDestinationRoute destination) {
              return _canAccessShellRoute(destination.route, accessPolicy);
            })
            .toList(growable: false);
    final int selectedIndex = _selectedIndexForPath(
      location.path,
      shellDestinations,
    );
    final AuthSession? session = ref.watch(
      sessionStateProvider.select((state) => state.session),
    );
    final AppConnectivityStatus connectivityStatus = ref
        .watch(appConnectivityStatusProvider)
        .when(
          data: (AppConnectivityStatus status) => status,
          error: (_, _) => AppConnectivityStatus.online,
          loading: () => AppConnectivityStatus.online,
        );
    final bool isShellLoading = ref.watch(shellNavigationLoadingProvider);

    return SubscriptionExpiredPromptHost(
      summary: session?.subscriptionSummary,
      platformAdminContact: session?.platformAdminContact,
      platformAdminContacts:
          session?.platformAdminContacts ?? const <OrgAdminContact>[],
      tenantAdminContacts:
          session?.tenantAdminContacts ?? const <OrgAdminContact>[],
      facilityAdminContacts:
          session?.facilityAdminContacts ?? const <OrgAdminContact>[],
      canManageBilling: ref
          .watch(appAccessPolicyProvider)
          .canManageSubscriptionBilling(),
      onRenewed: () async {
        if (session == null) {
          return;
        }
        final refreshResult = await ref
            .read(authRepositoryProvider)
            .fetchCurrentUser(session);
        refreshResult.when(
          success: (AuthSession refreshed) {
            ref.read(sessionStateProvider.notifier).persistSession(refreshed);
          },
          failure: (_) {},
        );
      },
      child: ResponsiveAppShell(
        title: l10n.appTitle,
        compactTitle: l10n.appShortTitle,
        initialSidebarCollapsed: ref.watch(appShellSidebarCollapsedProvider),
        onSidebarCollapsedChanged: (bool collapsed) {
          unawaited(
            ref
                .read(appShellSidebarCollapsedProvider.notifier)
                .setCollapsed(collapsed: collapsed),
          );
        },
        connectivityStatus: connectivityStatus,
        onlineLabel: l10n.appStatusOnlineLabel,
        offlineLabel: l10n.appStatusOfflineLabel,
        fullscreenEnterLabel: l10n.workspaceFullscreenEnterLabel,
        fullscreenExitLabel: l10n.workspaceFullscreenExitLabel,
        openMenuTooltip: l10n.appOpenNavigationMenuTooltip,
        closeDrawerTooltip: l10n.appCloseNavigationMenuTooltip,
        toggleSidebarTooltip: l10n.appToggleSidebarTooltip,
        navigationSearchLabel: l10n.appNavigationSearchLabel,
        navigationSearchHint: l10n.appNavigationSearchHint,
        navigationSearchNoResultsLabel: l10n.appNavigationSearchNoResultsLabel,
        accountTooltip: l10n.appAccountTooltip,
        notificationsTooltip: l10n.appNotificationsTooltip,
        unreadNotificationCount: badges.notificationUnreadCount ?? 0,
        notificationsUnreadLabel: l10n.appNotificationsUnreadLabel(
          badges.notificationUnreadCount ?? 0,
        ),
        onNotificationsSelected: canAccessCommunications
            ? () {
                context.go(
                  AppRoutes.communications.location(
                    queryParameters: <String, String>{
                      'panel': CommunicationsPanel.notifications.serverValue,
                    },
                  ),
                );
              }
            : null,
        profileLabel: l10n.appUserMenuProfileLabel,
        settingsLabel: l10n.appUserMenuSettingsLabel,
        changePasswordLabel: l10n.appUserMenuChangePasswordLabel,
        logoutLabel: l10n.appUserMenuLogoutLabel,
        signedInLabel: l10n.appUserMenuSignedInLabel,
        userProfile: _userMenuProfile(session),
        showUserAvatar: session != null,
        onProfileSelected: () {
          final String target = const SettingsPageQuery(
            tab: 'account',
            panel: SettingsAccountSection.profilePanel,
          ).location();
          context.go(target);
        },
        onSettingsSelected: () {
          if (!AppRoutes.settings.matchesPath(location.path)) {
            context.go(AppRoutes.settings.location());
          }
        },
        onChangePasswordSelected: () {
          final String target = const SettingsPageQuery(
            tab: 'account',
            panel: SettingsAccountSection.changePasswordPanel,
          ).location();
          context.go(target);
        },
        onLogoutSelected: () async {
          await ref.read(authRepositoryProvider).logout();
          await ref.read(sessionStateProvider.notifier).logout();
          if (context.mounted) {
            context.go(AppRoutes.login.location());
          }
        },
        headerTrailingActions: _subscriptionHeaderAction(
          context: context,
          ref: ref,
          session: session,
          l10n: l10n,
        ),
        destinations: <ResponsiveShellDestination>[
          for (final _ShellDestinationRoute destination in shellDestinations)
            destination.destination,
        ],
        selectedIndex: selectedIndex,
        selectedChildId: _selectedAccountsCategory(accountsMenuChildren),
        onChildSelected: (String categoryId) {
          // A category opens on its first authorized section; the workspace
          // tab strip covers the rest of that category.
          for (final AccountsDeskCategory category
              in AccountsDeskCategory.values) {
            if (category.name != categoryId) {
              continue;
            }
            final AccountsDeskSection? landing = accountsCategoryLandingSection(
              accessPolicy,
              category,
            );
            if (landing == null) {
              return;
            }
            context.go(
              AppRoutes.accounts.location(
                queryParameters: <String, String>{
                  'section': landing.sectionQueryValue,
                },
              ),
            );
            return;
          }
        },
        onDestinationSelected: (int index) {
          if (index == selectedIndex) {
            return;
          }

          context.go(shellDestinations[index].route.location());
        },
        isShellLoading: isShellLoading,
        shellRouteKey: location.path,
        child: child,
      ),
    );
  }

  /// Accounts leaf the current location resolves to, or null when elsewhere.
  ///
  /// Legacy aliases resolve to their canonical section so an old deep link
  /// still highlights and expands the owning menu item.
  AccountsDeskSection? _activeAccountsSection() {
    if (!AppRoutes.accounts.matchesPath(location.path)) {
      return null;
    }
    return AccountsDeskSection.resolveDeskSlug(
          location.queryParameters['section'] ??
              location.queryParameters['tab'],
        ) ??
        AccountsDeskSection.fallback;
  }

  /// Menu item id of the category owning the active section, when authorized.
  String? _selectedAccountsCategory(
    List<ShellSubmenuItem> accountsMenuChildren,
  ) {
    final AccountsDeskSection? section = _activeAccountsSection();
    if (section == null || accountsMenuChildren.isEmpty) {
      return null;
    }
    final String categoryId = AccountsDeskCategory.of(section).name;
    final bool visible = accountsMenuChildren.any(
      (ShellSubmenuItem item) => item.id == categoryId,
    );
    return visible ? categoryId : null;
  }

  int _selectedIndexForPath(
    String locationPath,
    List<_ShellDestinationRoute> shellDestinations,
  ) {
    final int index = shellDestinations.indexWhere((
      _ShellDestinationRoute destination,
    ) {
      return destination.route.matchesPath(locationPath);
    });

    return index < 0 ? 0 : index;
  }
}

bool _canAccessShellRoute(AppRouteData route, AppAccessPolicy accessPolicy) {
  return canAccessShellRoute(route, accessPolicy);
}

Widget? _subscriptionHeaderAction({
  required BuildContext context,
  required WidgetRef ref,
  required AuthSession? session,
  required AppLocalizations l10n,
}) {
  if (session == null) {
    return null;
  }

  final TenantSubscriptionSummary? summary = session.subscriptionSummary;
  if (summary == null || !summary.headerState.isHydrated) {
    return null;
  }

  final bool canManageBilling = ref
      .watch(appAccessPolicyProvider)
      .canManageSubscriptionBilling();

  VoidCallback? onPressed;
  if (canManageBilling) {
    onPressed = () async {
      final SubscriptionUpgradeDialogResult? submitted =
          await showSubscriptionUpgradeDialog(
            context,
            initialSummary: summary,
            initialAdminContact: session.platformAdminContact,
          );
      if (submitted == null || !context.mounted) {
        return;
      }

      final String message = switch (submitted) {
        SubscriptionUpgradeDialogResult.freeSubmitted =>
          l10n.subscriptionUpgradeFreeSubmittedMessage,
        SubscriptionUpgradeDialogResult.paidSubmitted =>
          l10n.subscriptionUpgradeSubmittedMessage,
      };

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));

      final refreshResult = await ref
          .read(authRepositoryProvider)
          .fetchCurrentUser(session);
      refreshResult.when(
        success: (AuthSession refreshed) {
          ref.read(sessionStateProvider.notifier).persistSession(refreshed);
        },
        failure: (_) {},
      );
    };
  } else {
    onPressed = () {
      unawaited(
        showSubscriptionReportAdminsDialog(
          context,
          summary: summary,
          tenantAdmins: session.tenantAdminContacts,
          facilityAdmins: session.facilityAdminContacts,
          platformAdmins: session.platformAdminContacts,
          platformAdminContact: session.platformAdminContact,
        ),
      );
    };
  }

  return SubscriptionHeaderButton(
    summary: summary,
    onPressed: onPressed,
    showUpgradeHint: canManageBilling,
  );
}

UserMenuProfileData? _userMenuProfile(AuthSession? session) {
  if (session == null) {
    return null;
  }

  final AuthUserProfile? user = session.user;
  final String? subject = _nonEmpty(session.subject);
  final String? email = _nonEmpty(user?.email) ?? _emailFromSubject(subject);
  final String? name =
      _nonEmpty(user?.fullName) ??
      _nonEmpty(user?.effectiveTitle) ??
      _distinct(subject, email) ??
      email;
  final String? initials =
      _nonEmpty(user?.initials) ?? _initialsFrom(name ?? email);

  return UserMenuProfileData(
    name: name,
    email: email,
    title:
        _distinct(user?.facilityName, name) ??
        _distinct(user?.effectiveTitle, name),
    overallRole: user?.overallRole,
    userType: user?.userType,
    initials: initials,
  );
}

String? _emailFromSubject(String? subject) {
  if (subject == null || !subject.contains('@')) {
    return null;
  }

  return subject;
}

final RegExp _initialsDelimiterPattern = RegExp(r'[@._-]+');
final RegExp _whitespacePattern = RegExp(r'\s+');

String? _initialsFrom(String? value) {
  final String? normalized = _nonEmpty(value);
  if (normalized == null) {
    return null;
  }

  final List<String> words = normalized
      .replaceAll(_initialsDelimiterPattern, ' ')
      .split(_whitespacePattern)
      .where((String word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) {
    return null;
  }
  if (words.length == 1) {
    return words.first.substring(0, 1).toUpperCase();
  }

  return <String>[
    words.first.substring(0, 1),
    words.last.substring(0, 1),
  ].join().toUpperCase();
}

String? _distinct(String? value, String? other) {
  final String? normalized = _nonEmpty(value);
  final String? normalizedOther = _nonEmpty(other);
  if (normalized == null) {
    return null;
  }
  if (normalizedOther != null &&
      normalized.toLowerCase() == normalizedOther.toLowerCase()) {
    return null;
  }

  return normalized;
}

String? _nonEmpty(String? value) {
  final String? normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
