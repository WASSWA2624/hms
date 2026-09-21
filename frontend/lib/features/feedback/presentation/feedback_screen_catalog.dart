import 'package:hosspi_hms/app/router/app_routes.dart';
import 'package:hosspi_hms/core/permissions/access_policy.dart';
import 'package:hosspi_hms/features/feedback/domain/entities/feedback_entities.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';

/// A screen a reporter can say their feedback applies to.
typedef FeedbackScreenChoice = ({FeedbackScreenReference screen, String label});

/// Every screen the app can name, labelled as the navigation labels it.
///
/// The labels come from the same strings the navigation shows, so a reporter
/// picks "Outpatients", not `opd`. Screens outside the navigation — the
/// profile, the setup workspace, the sign-in screens — are here too: feedback
/// is raised from them as often as from anywhere else.
List<FeedbackScreenChoice> feedbackScreenCatalog(AppLocalizations l10n) {
  return <FeedbackScreenChoice>[
    _choice(AppRoutes.home, l10n.navigationHomeLabel),
    _choice(AppRoutes.reception, l10n.navigationReceptionLabel),
    _choice(AppRoutes.patients, l10n.navigationPatientsLabel),
    _choice(AppRoutes.opd, l10n.navigationOpdLabel),
    _choice(AppRoutes.emergency, l10n.navigationEmergencyLabel),
    _choice(AppRoutes.ipd, l10n.navigationIpdLabel),
    _choice(AppRoutes.roomsBeds, l10n.navigationRoomsBedsLabel),
    _choice(AppRoutes.icu, l10n.navigationIcuLabel),
    _choice(AppRoutes.nursing, l10n.navigationNursingLabel),
    _choice(AppRoutes.clinical, l10n.navigationClinicalLabel),
    _choice(AppRoutes.physiotherapy, l10n.navigationPhysiotherapyLabel),
    _choice(AppRoutes.theater, l10n.navigationTheaterLabel),
    _choice(AppRoutes.discharge, l10n.navigationDischargeLabel),
    _choice(AppRoutes.lab, l10n.navigationLabLabel),
    _choice(AppRoutes.radiology, l10n.navigationRadiologyLabel),
    _choice(AppRoutes.pharmacy, l10n.navigationPharmacyLabel),
    _choice(AppRoutes.billing, l10n.navigationBillingLabel),
    _choice(AppRoutes.accounts, l10n.navigationAccountsLabel),
    _choice(AppRoutes.claims, l10n.navigationClaimsLabel),
    _choice(AppRoutes.subscriptions, l10n.navigationSubscriptionsLabel),
    _choice(AppRoutes.operations, l10n.navigationOperationsLabel),
    _choice(AppRoutes.housekeeping, l10n.navigationHousekeepingLabel),
    _choice(AppRoutes.biomedical, l10n.navigationBiomedicalLabel),
    _choice(AppRoutes.mortuary, l10n.navigationMortuaryLabel),
    _choice(AppRoutes.hr, l10n.navigationHrLabel),
    _choice(AppRoutes.communications, l10n.navigationCommunicationsLabel),
    _choice(AppRoutes.integrations, l10n.navigationIntegrationsLabel),
    _choice(AppRoutes.reports, l10n.navigationReportsLabel),
    _choice(AppRoutes.settings, l10n.navigationSettingsLabel),
    _choice(AppRoutes.tenantFacilitySetup, l10n.tenantFacilitySetupTitle),
    _choice(AppRoutes.accessAdmin, l10n.accessAdminTitle),
    _choice(AppRoutes.profile, l10n.profileTitle),
    _choice(AppRoutes.login, l10n.feedbackScreenSignInLabel),
    _choice(AppRoutes.register, l10n.feedbackScreenRegisterLabel),
  ];
}

/// The screens this user can actually reach.
///
/// A reporter should not be able to file feedback against a workspace their
/// account cannot open, and a signed-out one sees only the public screens.
/// The same requirements guard the routes themselves.
List<FeedbackScreenChoice> reachableFeedbackScreens({
  required AppLocalizations l10n,
  required AppAccessPolicy policy,
  required bool signedIn,
}) {
  return feedbackScreenCatalog(l10n)
      .where((FeedbackScreenChoice choice) {
        final AppRouteData? route = _routeByName(choice.screen.routeName);
        if (route == null) {
          return false;
        }
        if (!signedIn) {
          return !route.requiresAuthenticatedSession;
        }
        return route.accessRequirement.isAllowed(policy);
      })
      .toList(growable: false);
}

/// The screen a route belongs to, named the way the catalogue names it.
FeedbackScreenReference? feedbackScreenForRoute({
  required AppLocalizations l10n,
  required String? routeName,
  String? routePath,
}) {
  final String name = routeName?.trim() ?? '';
  if (name.isEmpty) {
    return routePath == null || routePath.trim().isEmpty
        ? null
        : FeedbackScreenReference(routePath: routePath);
  }

  for (final FeedbackScreenChoice choice in feedbackScreenCatalog(l10n)) {
    if (choice.screen.routeName == name) {
      return choice.screen;
    }
  }
  return FeedbackScreenReference(routeName: name, routePath: routePath);
}

FeedbackScreenChoice _choice(AppRouteData route, String label) {
  return (
    screen: FeedbackScreenReference(
      routeName: route.name,
      routePath: route.path,
      screenTitle: label,
    ),
    label: label,
  );
}

AppRouteData? _routeByName(String? name) {
  if (name == null || name.isEmpty) {
    return null;
  }
  for (final AppRouteData route in AppRoutes.all) {
    if (route.name == name) {
      return route;
    }
  }
  return null;
}
