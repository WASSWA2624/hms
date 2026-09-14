import 'package:hosspi_hms/core/permissions/access_policy.dart';

/// Roles that may download and clear feedback: the platform owner (owner admin)
/// and the platform admin.
///
/// Stored feedback spans every tenant, anonymous submissions included, so no
/// tenant or facility role qualifies. `GET /api/v1/feedback/export` and
/// `DELETE /api/v1/feedback` enforce the same roles; hiding the menu entries is
/// not the control.
const List<AppRole> feedbackAdminRoles = <AppRole>[
  AppRole.platformOwner,
  AppRole.platformAdmin,
];

/// Every user, signed in or not, may give feedback. Only [feedbackAdminRoles]
/// see Download feedback and Clear feedback.
bool canManageFeedback(AppAccessPolicy policy) {
  return feedbackAdminRoles.any(policy.hasRole);
}
