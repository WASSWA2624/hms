import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/core/permissions/access_policy.dart';
import 'package:hosspi_hms/core/utils/app_slug.dart';
import 'package:hosspi_hms/features/tenant_facility/domain/entities/tenant_facility_setup.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';

const String tenantFacilityNoneSelection = '__none__';

/// Setup workspace tabs replacing Guided setup as primary navigation.
enum TenantFacilitySetupDeskSection {
  tenants,
  facility,
  departments,
  units,
  wards,
  rooms,
  beds,
  roles,
  permissions,
  users,
  clinicalCatalog,
  /// Platform-only queue of self-registered accounts awaiting Pro trial activation.
  subscriptionApprovals,
  /// Platform-only queue of paid subscription requests awaiting activation.
  subscriptionActivations;

  /// Canonical `?section=` query value for this tab.
  String get routeQueryValue {
    return switch (this) {
      TenantFacilitySetupDeskSection.clinicalCatalog => 'clinical-services',
      TenantFacilitySetupDeskSection.tenants => 'tenants',
      TenantFacilitySetupDeskSection.facility => 'facility',
      TenantFacilitySetupDeskSection.departments => 'departments',
      TenantFacilitySetupDeskSection.units => 'units',
      TenantFacilitySetupDeskSection.wards => 'wards',
      TenantFacilitySetupDeskSection.rooms => 'rooms',
      TenantFacilitySetupDeskSection.beds => 'beds',
      TenantFacilitySetupDeskSection.roles => 'roles',
      TenantFacilitySetupDeskSection.permissions => 'permissions',
      TenantFacilitySetupDeskSection.users => 'users',
      TenantFacilitySetupDeskSection.subscriptionApprovals =>
        'subscription-approvals',
      TenantFacilitySetupDeskSection.subscriptionActivations =>
        'subscription-activations',
    };
  }

  /// Resolves a `?section=` / `?tab=` value to a desk section.
  static TenantFacilitySetupDeskSection? fromQuery(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'clinical-services':
      case 'clinical-catalog':
      case 'clinical':
      case 'catalog':
      case 'services':
        return TenantFacilitySetupDeskSection.clinicalCatalog;
      case 'tenants':
      case 'tenant':
        return TenantFacilitySetupDeskSection.tenants;
      case 'facility':
      case 'facilities':
        return TenantFacilitySetupDeskSection.facility;
      case 'departments':
      case 'department':
        return TenantFacilitySetupDeskSection.departments;
      case 'units':
      case 'unit':
        return TenantFacilitySetupDeskSection.units;
      case 'wards':
      case 'ward':
        return TenantFacilitySetupDeskSection.wards;
      case 'rooms':
      case 'room':
        return TenantFacilitySetupDeskSection.rooms;
      case 'beds':
      case 'bed':
        return TenantFacilitySetupDeskSection.beds;
      case 'roles':
      case 'role':
        return TenantFacilitySetupDeskSection.roles;
      case 'permissions':
      case 'permission':
        return TenantFacilitySetupDeskSection.permissions;
      case 'users':
      case 'user':
        return TenantFacilitySetupDeskSection.users;
      case 'subscription-approvals':
      case 'subscription_approvals':
      case 'approvals':
      case 'account-approvals':
      case 'registration-approvals':
        return TenantFacilitySetupDeskSection.subscriptionApprovals;
      case 'subscription-activations':
      case 'subscription_activations':
      case 'activations':
      case 'payment-activations':
        return TenantFacilitySetupDeskSection.subscriptionActivations;
      default:
        return null;
    }
  }
}

/// Deep-link targeting parsed from the `/admin/setup` route query string.
@immutable
final class TenantFacilitySetupPageQuery {
  const TenantFacilitySetupPageQuery({this.section = '', this.subscription});

  /// Active desk tab from `?section=` or `?tab=`.
  final String section;

  /// Tenants tab subscription filter from `?subscription=` (`none`/`active`).
  final String? subscription;

  factory TenantFacilitySetupPageQuery.fromUri(Uri uri) {
    final Map<String, String> params = uri.queryParameters;
    final String section = (params['section'] ?? params['tab'] ?? '').trim();
    final String subscription = (params['subscription'] ?? '').trim();
    return TenantFacilitySetupPageQuery(
      section: section,
      subscription: subscription.isEmpty ? null : subscription.toLowerCase(),
    );
  }

  String get signature =>
      '${section.toLowerCase()}|${subscription ?? ''}';

  bool get hasRouteTargeting => section.trim().isNotEmpty;
}

/// Shell nav label for `/admin/setup` by admin scope.
String tenantFacilitySetupNavigationLabel(
  AppAccessPolicy policy,
  AppLocalizations l10n,
) {
  if (policy.isPlatformElevated) {
    return l10n.navigationPlatformSetupLabel;
  }
  if (policy.canManageTenant()) {
    return l10n.navigationSetupLabel;
  }
  return l10n.navigationFacilitySetupLabel;
}

/// Page title for setup workspace by admin scope.
String tenantFacilitySetupWorkspaceTitle(
  AppAccessPolicy policy,
  AppLocalizations l10n,
) {
  return tenantFacilitySetupNavigationLabel(policy, l10n);
}

bool tenantFacilitySetupDeskSectionVisible({
  required TenantFacilitySetupDeskSection section,
  required bool canManageTenant,
  required bool canManageFacility,
  required bool canManageAccess,
  bool isElevated = false,
}) {
  return switch (section) {
    TenantFacilitySetupDeskSection.tenants => canManageTenant,
    TenantFacilitySetupDeskSection.facility ||
    TenantFacilitySetupDeskSection.departments ||
    TenantFacilitySetupDeskSection.units ||
    TenantFacilitySetupDeskSection.wards ||
    TenantFacilitySetupDeskSection.rooms ||
    TenantFacilitySetupDeskSection.beds ||
    TenantFacilitySetupDeskSection.clinicalCatalog =>
      canManageFacility || canManageTenant,
    TenantFacilitySetupDeskSection.roles ||
    TenantFacilitySetupDeskSection.permissions ||
    TenantFacilitySetupDeskSection.users => canManageAccess,
    TenantFacilitySetupDeskSection.subscriptionApprovals ||
    TenantFacilitySetupDeskSection.subscriptionActivations => isElevated,
  };
}

List<TenantFacilitySetupDeskSection> tenantFacilityVisibleSetupDeskSections({
  required bool canManageTenant,
  required bool canManageFacility,
  required bool canManageAccess,
  bool isElevated = false,
}) {
  return TenantFacilitySetupDeskSection.values
      .where(
        (TenantFacilitySetupDeskSection section) =>
            tenantFacilitySetupDeskSectionVisible(
              section: section,
              canManageTenant: canManageTenant,
              canManageFacility: canManageFacility,
              canManageAccess: canManageAccess,
              isElevated: isElevated,
            ),
      )
      .toList(growable: false);
}

/// Scoped managers edit their own tenant; platform creators use the full list.
bool tenantFacilityUsesScopedTenantPanel({
  required bool canManageTenant,
  required bool canCreateTenant,
}) {
  return canManageTenant && !canCreateTenant;
}

/// Facility admins edit their own facility; creators/managers use the list.
bool tenantFacilityUsesScopedFacilityPanel({
  required bool canManageFacility,
  required bool canCreateFacility,
}) {
  return canManageFacility && !canCreateFacility;
}

/// Facilities tab list breadth by admin role.
enum TenantFacilityFacilitiesListScope {
  /// Super / platform admin — all facilities across tenants.
  platform,

  /// Tenant admin — facilities under the session tenant.
  tenant,

  /// Facility admin — session facility details only.
  facility,
}

TenantFacilityFacilitiesListScope tenantFacilityFacilitiesListScope(
  AppAccessPolicy policy,
) {
  if (policy.isElevated || policy.canCreateTenant()) {
    return TenantFacilityFacilitiesListScope.platform;
  }
  if (policy.canManageTenant()) {
    return TenantFacilityFacilitiesListScope.tenant;
  }
  return TenantFacilityFacilitiesListScope.facility;
}

bool tenantFacilityFacilitiesShowsTenantColumn(
  TenantFacilityFacilitiesListScope scope,
) {
  return scope == TenantFacilityFacilitiesListScope.platform;
}

bool tenantFacilityFacilitiesShowsCodeColumn(
  TenantFacilityFacilitiesListScope scope,
) {
  return scope == TenantFacilityFacilitiesListScope.tenant;
}

bool tenantFacilityFacilitiesShowsContactColumns(
  TenantFacilityFacilitiesListScope scope,
) {
  return scope == TenantFacilityFacilitiesListScope.tenant;
}

bool tenantFacilityFacilitiesShowsTenantFilter(
  TenantFacilityFacilitiesListScope scope,
) {
  return scope == TenantFacilityFacilitiesListScope.platform;
}

final RegExp _tenantFacilityOpaqueIdPattern = RegExp(
  r'^(?:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|[0-9a-fA-F]{24})$',
);

/// Returns [candidate] only when it is a human-friendly public identifier.
String? tenantFacilityHumanFriendlyDisplayId(
  String? candidate, {
  String? opaqueId,
}) {
  final String? trimmed = candidate?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final String? opaque = opaqueId?.trim();
  if (opaque != null && opaque.isNotEmpty && trimmed == opaque) {
    return null;
  }
  if (_tenantFacilityOpaqueIdPattern.hasMatch(trimmed)) {
    return null;
  }
  return trimmed;
}

/// True when [value] looks like a raw UUID or 24-hex opaque id.
bool tenantFacilityLooksLikeOpaqueId(String? value) {
  final String? trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return false;
  }
  return _tenantFacilityOpaqueIdPattern.hasMatch(trimmed);
}

/// Authoritative tab badge for `/admin/setup`. Prefer [liveCount] (filtered
/// list total) when the tab has loaded; otherwise use workspace snapshot
/// totals for structure lists. Omit when no countable total is available.
int? tenantFacilitySetupDeskSectionCount({
  required TenantFacilitySetupDeskSection section,
  required FacilitySetupSnapshot snapshot,
  int? liveCount,
}) {
  if (liveCount != null) {
    return liveCount;
  }
  return switch (section) {
    TenantFacilitySetupDeskSection.departments => snapshot.departments.length,
    TenantFacilitySetupDeskSection.units => snapshot.units.length,
    TenantFacilitySetupDeskSection.wards => snapshot.wards.length,
    TenantFacilitySetupDeskSection.rooms => snapshot.rooms.length,
    TenantFacilitySetupDeskSection.beds => snapshot.beds.length,
    TenantFacilitySetupDeskSection.facility => snapshot.facilities.length,
    TenantFacilitySetupDeskSection.tenants ||
    TenantFacilitySetupDeskSection.roles ||
    TenantFacilitySetupDeskSection.permissions ||
    TenantFacilitySetupDeskSection.users ||
    TenantFacilitySetupDeskSection.clinicalCatalog ||
    TenantFacilitySetupDeskSection.subscriptionApprovals ||
    TenantFacilitySetupDeskSection.subscriptionActivations => null,
  };
}

/// Single-line atomic table cell (no stacked subtitles, no bold).
Widget tenantFacilitySetupAtomicCell(
  String value, {
  bool muted = false,
}) {
  return Builder(
    builder: (BuildContext context) {
      final ThemeData theme = Theme.of(context);
      return Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: muted
            ? theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )
            : theme.textTheme.bodyMedium,
      );
    },
  );
}

/// Related-name label that never surfaces opaque ids and flags deleted parents.
String tenantFacilityRelatedNameLabel(
  String? name, {
  required bool isDeleted,
  required String deletedLabel,
  String empty = '—',
}) {
  final String? trimmed = name?.trim();
  if (trimmed == null ||
      trimmed.isEmpty ||
      trimmed == empty ||
      tenantFacilityLooksLikeOpaqueId(trimmed)) {
    return empty;
  }
  if (isDeleted) {
    return '$trimmed ($deletedLabel)';
  }
  return trimmed;
}

/// Compact primary/secondary cell for dense tables (max 5 data columns).
class TenantFacilityNestedTableCell extends StatelessWidget {
  const TenantFacilityNestedTableCell({
    required this.title,
    this.details = const <String>[],
    this.titleStyle,
    this.deleted = false,
    super.key,
  });

  final String title;
  final List<String> details;
  final TextStyle? titleStyle;
  final bool deleted;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final List<String> resolvedDetails = details
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty)
        .toList(growable: false);
    final TextStyle? resolvedTitleStyle =
        titleStyle ??
        theme.textTheme.bodyMedium?.copyWith(
          color: deleted ? colorScheme.onSurfaceVariant : null,
          fontWeight: AppFontWeight.emphasis,
        );
    final TextStyle? detailStyle = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
      height: 1.25,
    );

    if (resolvedDetails.isEmpty) {
      return Text(title, style: resolvedTitleStyle);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(title, style: resolvedTitleStyle),
        SizedBox(height: theme.spacing.xs),
        Text(resolvedDetails.join(' · '), style: detailStyle),
      ],
    );
  }
}

/// Departments tab list breadth and default columns by admin role.
enum TenantFacilityDepartmentsListScope {
  /// Super / platform admin — all tenants and facilities.
  platform,

  /// Tenant admin — all facilities under the session tenant.
  tenant,

  /// Facility admin — active facility only.
  facility,
}

TenantFacilityDepartmentsListScope tenantFacilityDepartmentsListScope(
  AppAccessPolicy policy,
) {
  if (policy.isElevated) {
    return TenantFacilityDepartmentsListScope.platform;
  }
  if (policy.canManageTenant()) {
    return TenantFacilityDepartmentsListScope.tenant;
  }
  return TenantFacilityDepartmentsListScope.facility;
}

bool tenantFacilityDepartmentsShowsTenantColumn(
  TenantFacilityDepartmentsListScope scope,
) {
  return scope == TenantFacilityDepartmentsListScope.platform;
}

bool tenantFacilityDepartmentsShowsFacilityColumn(
  TenantFacilityDepartmentsListScope scope,
) {
  return scope == TenantFacilityDepartmentsListScope.platform ||
      scope == TenantFacilityDepartmentsListScope.tenant;
}

bool tenantFacilityDepartmentsShowsDetailColumns(
  TenantFacilityDepartmentsListScope scope,
) {
  return scope == TenantFacilityDepartmentsListScope.facility;
}

/// Advanced-filter keys for the departments tab.
abstract final class TenantFacilityDepartmentsFilterKeys {
  static const String tenant = 'tenant';
  static const String facility = 'facility';
  static const String type = 'type';
  static const String active = 'active';
  static const String status = 'status';
  static const String activeYes = 'yes';
  static const String activeNo = 'no';
}

bool tenantFacilityDepartmentsShowsTenantFilter(
  TenantFacilityDepartmentsListScope scope,
) {
  return scope == TenantFacilityDepartmentsListScope.platform;
}

bool tenantFacilityDepartmentsShowsFacilityFilter(
  TenantFacilityDepartmentsListScope scope,
) {
  return scope == TenantFacilityDepartmentsListScope.platform ||
      scope == TenantFacilityDepartmentsListScope.tenant;
}

/// Units tab reuses the same list-scope rules as departments.
typedef TenantFacilityUnitsListScope = TenantFacilityDepartmentsListScope;

TenantFacilityUnitsListScope tenantFacilityUnitsListScope(
  AppAccessPolicy policy,
) => tenantFacilityDepartmentsListScope(policy);

bool tenantFacilityUnitsShowsTenantColumn(TenantFacilityUnitsListScope scope) =>
    tenantFacilityDepartmentsShowsTenantColumn(scope);

bool tenantFacilityUnitsShowsFacilityColumn(
  TenantFacilityUnitsListScope scope,
) => tenantFacilityDepartmentsShowsFacilityColumn(scope);

bool tenantFacilityUnitsShowsTenantFilter(TenantFacilityUnitsListScope scope) =>
    tenantFacilityDepartmentsShowsTenantFilter(scope);

bool tenantFacilityUnitsShowsFacilityFilter(
  TenantFacilityUnitsListScope scope,
) => tenantFacilityDepartmentsShowsFacilityFilter(scope);

/// Advanced-filter keys for the units tab.
abstract final class TenantFacilityUnitsFilterKeys {
  static const String tenant = 'tenant';
  static const String facility = 'facility';
  static const String department = 'department';
  static const String active = 'active';
  static const String activeYes = 'yes';
  static const String activeNo = 'no';
}

/// Beds tab reuses the same list-scope rules as departments.
typedef TenantFacilityBedsListScope = TenantFacilityDepartmentsListScope;

TenantFacilityBedsListScope tenantFacilityBedsListScope(
  AppAccessPolicy policy,
) => tenantFacilityDepartmentsListScope(policy);

bool tenantFacilityBedsShowsTenantColumn(TenantFacilityBedsListScope scope) =>
    tenantFacilityDepartmentsShowsTenantColumn(scope);

bool tenantFacilityBedsShowsFacilityColumn(TenantFacilityBedsListScope scope) =>
    tenantFacilityDepartmentsShowsFacilityColumn(scope);

bool tenantFacilityBedsShowsTenantFilter(TenantFacilityBedsListScope scope) =>
    tenantFacilityDepartmentsShowsTenantFilter(scope);

bool tenantFacilityBedsShowsFacilityFilter(TenantFacilityBedsListScope scope) =>
    tenantFacilityDepartmentsShowsFacilityFilter(scope);

/// Advanced-filter keys for the beds tab.
abstract final class TenantFacilityBedsFilterKeys {
  static const String tenant = 'tenant';
  static const String facility = 'facility';
  static const String ward = 'ward';
  static const String room = 'room';
  static const String status = 'bed_status';
}

/// Wards tab reuses the same list-scope rules as departments/units.
typedef TenantFacilityWardsListScope = TenantFacilityDepartmentsListScope;

TenantFacilityWardsListScope tenantFacilityWardsListScope(
  AppAccessPolicy policy,
) => tenantFacilityDepartmentsListScope(policy);

bool tenantFacilityWardsShowsTenantColumn(TenantFacilityWardsListScope scope) =>
    tenantFacilityDepartmentsShowsTenantColumn(scope);

bool tenantFacilityWardsShowsFacilityColumn(
  TenantFacilityWardsListScope scope,
) => tenantFacilityDepartmentsShowsFacilityColumn(scope);

bool tenantFacilityWardsShowsTenantFilter(TenantFacilityWardsListScope scope) =>
    tenantFacilityDepartmentsShowsTenantFilter(scope);

bool tenantFacilityWardsShowsFacilityFilter(
  TenantFacilityWardsListScope scope,
) => tenantFacilityDepartmentsShowsFacilityFilter(scope);

/// Advanced-filter keys for the wards tab.
abstract final class TenantFacilityWardsFilterKeys {
  static const String tenant = 'tenant';
  static const String facility = 'facility';
  static const String department = 'department';
  static const String type = 'type';
  static const String active = 'active';
  static const String activeYes = 'yes';
  static const String activeNo = 'no';
}

/// Rooms tab reuses the same list-scope rules as departments/units.
typedef TenantFacilityRoomsListScope = TenantFacilityDepartmentsListScope;

TenantFacilityRoomsListScope tenantFacilityRoomsListScope(
  AppAccessPolicy policy,
) => tenantFacilityDepartmentsListScope(policy);

bool tenantFacilityRoomsShowsTenantColumn(TenantFacilityRoomsListScope scope) =>
    tenantFacilityDepartmentsShowsTenantColumn(scope);

bool tenantFacilityRoomsShowsFacilityColumn(
  TenantFacilityRoomsListScope scope,
) => tenantFacilityDepartmentsShowsFacilityColumn(scope);

bool tenantFacilityRoomsShowsTenantFilter(TenantFacilityRoomsListScope scope) =>
    tenantFacilityDepartmentsShowsTenantFilter(scope);

bool tenantFacilityRoomsShowsFacilityFilter(
  TenantFacilityRoomsListScope scope,
) => tenantFacilityDepartmentsShowsFacilityFilter(scope);

/// Advanced-filter keys for the rooms tab.
abstract final class TenantFacilityRoomsFilterKeys {
  static const String tenant = 'tenant';
  static const String facility = 'facility';
  static const String ward = 'ward';
  static const String status = 'status';
}

String tenantFacilitySetupDeskSectionLabel(
  AppLocalizations l10n,
  TenantFacilitySetupDeskSection section, {
  AppAccessPolicy? policy,
}) {
  final bool scopedTenant = policy != null &&
      tenantFacilityUsesScopedTenantPanel(
        canManageTenant: policy.canManageTenant(),
        canCreateTenant: policy.canCreateTenant(),
      );
  final bool scopedFacility = policy != null &&
      tenantFacilityUsesScopedFacilityPanel(
        canManageFacility: policy.canManageFacility(),
        canCreateFacility: policy.canCreateFacility(),
      );

  return switch (section) {
    TenantFacilitySetupDeskSection.tenants => scopedTenant
        ? l10n.tenantFacilitySetupTabTenant
        : l10n.tenantFacilitySetupTabTenants,
    TenantFacilitySetupDeskSection.facility => scopedFacility
        ? l10n.tenantFacilitySetupTabFacility
        : l10n.tenantFacilitySetupTabFacilities,
    TenantFacilitySetupDeskSection.departments =>
      l10n.tenantFacilityWizardStepDepartments,
    TenantFacilitySetupDeskSection.units => l10n.tenantFacilityWizardStepUnits,
    TenantFacilitySetupDeskSection.wards => l10n.tenantFacilityWizardStepWards,
    TenantFacilitySetupDeskSection.rooms => l10n.tenantFacilityWizardStepRooms,
    TenantFacilitySetupDeskSection.beds => l10n.tenantFacilityWizardStepBeds,
    TenantFacilitySetupDeskSection.clinicalCatalog =>
      l10n.tenantFacilitySetupTabClinicalCatalog,
    TenantFacilitySetupDeskSection.roles => l10n.tenantFacilitySetupTabRoles,
    TenantFacilitySetupDeskSection.permissions =>
      l10n.tenantFacilitySetupTabPermissions,
    TenantFacilitySetupDeskSection.users => l10n.tenantFacilitySetupTabUsers,
    TenantFacilitySetupDeskSection.subscriptionApprovals =>
      l10n.tenantFacilitySetupTabSubscriptionApprovals,
    TenantFacilitySetupDeskSection.subscriptionActivations =>
      l10n.tenantFacilitySetupTabSubscriptionActivations,
  };
}

IconData tenantFacilitySetupDeskSectionIcon(
  TenantFacilitySetupDeskSection section,
) {
  return switch (section) {
    TenantFacilitySetupDeskSection.tenants => Icons.corporate_fare_outlined,
    TenantFacilitySetupDeskSection.facility => Icons.apartment_outlined,
    TenantFacilitySetupDeskSection.departments => Icons.domain_outlined,
    TenantFacilitySetupDeskSection.units => Icons.account_tree_outlined,
    TenantFacilitySetupDeskSection.wards => Icons.maps_home_work_outlined,
    TenantFacilitySetupDeskSection.rooms => Icons.meeting_room_outlined,
    TenantFacilitySetupDeskSection.beds => Icons.bed_outlined,
    TenantFacilitySetupDeskSection.clinicalCatalog =>
      Icons.medical_information_outlined,
    TenantFacilitySetupDeskSection.roles => Icons.badge_outlined,
    TenantFacilitySetupDeskSection.permissions => Icons.key_outlined,
    TenantFacilitySetupDeskSection.users => Icons.people_outline,
    TenantFacilitySetupDeskSection.subscriptionApprovals =>
      Icons.verified_user_outlined,
    TenantFacilitySetupDeskSection.subscriptionActivations =>
      Icons.payments_outlined,
  };
}

/// Add/Create label for the setup desk tab primary action, or null when none.
String? tenantFacilitySetupDeskCreateLabel(
  AppLocalizations l10n,
  TenantFacilitySetupDeskSection section,
) {
  return switch (section) {
    TenantFacilitySetupDeskSection.tenants =>
      l10n.tenantFacilityAddTenantAction,
    TenantFacilitySetupDeskSection.facility =>
      l10n.tenantFacilityAddFacilityAction,
    TenantFacilitySetupDeskSection.departments =>
      l10n.tenantFacilityAddDepartmentAction,
    TenantFacilitySetupDeskSection.units => l10n.tenantFacilityAddUnitAction,
    TenantFacilitySetupDeskSection.wards => l10n.tenantFacilityAddWardAction,
    TenantFacilitySetupDeskSection.rooms => l10n.tenantFacilityAddRoomAction,
    TenantFacilitySetupDeskSection.beds => l10n.tenantFacilityAddBedAction,
    TenantFacilitySetupDeskSection.clinicalCatalog =>
      l10n.clinicalCreateDiagnosisAction,
    TenantFacilitySetupDeskSection.roles => l10n.accessAdminCreateRoleAction,
    TenantFacilitySetupDeskSection.permissions => null,
    TenantFacilitySetupDeskSection.users => l10n.accessAdminCreateUserAction,
    TenantFacilitySetupDeskSection.subscriptionApprovals => null,
    TenantFacilitySetupDeskSection.subscriptionActivations => null,
  };
}

/// Leading icon for the setup desk tab Add/Create primary action.
IconData? tenantFacilitySetupDeskCreateIcon(
  TenantFacilitySetupDeskSection section,
) {
  return switch (section) {
    TenantFacilitySetupDeskSection.tenants => Icons.add_business_outlined,
    TenantFacilitySetupDeskSection.facility => Icons.add_business_outlined,
    TenantFacilitySetupDeskSection.departments ||
    TenantFacilitySetupDeskSection.units ||
    TenantFacilitySetupDeskSection.wards ||
    TenantFacilitySetupDeskSection.rooms ||
    TenantFacilitySetupDeskSection.beds => Icons.add,
    TenantFacilitySetupDeskSection.clinicalCatalog => Icons.add_circle_outline,
    TenantFacilitySetupDeskSection.roles => Icons.badge_outlined,
    TenantFacilitySetupDeskSection.permissions => null,
    TenantFacilitySetupDeskSection.users => Icons.person_add_alt_1_outlined,
    TenantFacilitySetupDeskSection.subscriptionApprovals => null,
    TenantFacilitySetupDeskSection.subscriptionActivations => null,
  };
}

/// Builds a short, OS-safe facility logo basename (≤ 32 chars incl. extension).
///
/// Example: `logo-4869585d.png`
String buildFacilityLogoFileName(
  String facilityName, {
  String extension = 'png',
}) {
  const int maxBasename = 32;
  final String normalizedExt = extension.startsWith('.')
      ? extension.toLowerCase()
      : '.${extension.toLowerCase()}';
  final String slug = slugify(
    facilityName,
  ).replaceAll(RegExp(r'[^a-z0-9]'), '');
  final String suffix = (slug.isEmpty ? 'facility' : slug).substring(
    0,
    math.min(8, (slug.isEmpty ? 'facility' : slug).length),
  );
  final String candidate = 'logo-$suffix$normalizedExt';
  if (candidate.length <= maxBasename) {
    return candidate;
  }
  final int maxStem = maxBasename - normalizedExt.length;
  return '${candidate.substring(0, maxStem)}$normalizedExt';
}

String? tenantFacilityOptionalSelection(String? value) {
  if (value == null || value == tenantFacilityNoneSelection) {
    return null;
  }

  return value;
}

FormFieldValidator<String> tenantFacilityRequiredSelection(
  AppLocalizations l10n,
) {
  return (String? value) => tenantFacilityOptionalSelection(value) == null
      ? l10n.validationRequired
      : null;
}

FormFieldValidator<String> tenantFacilityValidReferenceSelection({
  required List<String> validIds,
  required String invalidMessage,
}) {
  return (String? value) {
    final String? selected = tenantFacilityOptionalSelection(value);
    if (selected == null) {
      return null;
    }

    return validIds.contains(selected) ? null : invalidMessage;
  };
}

String tenantFacilityJoinParts(Iterable<String?> parts) {
  return parts
      .map((String? part) => part?.trim())
      .whereType<String>()
      .where((String part) => part.isNotEmpty)
      .join(' · ');
}

String? tenantFacilityFieldSummary(String label, String? value) {
  final String? trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }

  return '$label: $trimmed';
}

String tenantFacilityActiveStatusLabel(AppLocalizations l10n, bool isActive) {
  return isActive
      ? l10n.tenantFacilityStatusActive
      : l10n.tenantFacilityStatusInactive;
}

String tenantFacilityFacilityTypeLabel(
  AppLocalizations l10n,
  FacilitySetupType type,
) {
  return switch (type) {
    FacilitySetupType.hospital => l10n.authFacilityTypeHospital,
    FacilitySetupType.clinic => l10n.authFacilityTypeClinic,
    FacilitySetupType.lab => l10n.authFacilityTypeLab,
    FacilitySetupType.pharmacy => l10n.authFacilityTypePharmacy,
    FacilitySetupType.other => l10n.authFacilityTypeOther,
  };
}

IconData tenantFacilityFacilityTypeIcon(FacilitySetupType type) {
  return switch (type) {
    FacilitySetupType.hospital => Icons.local_hospital_outlined,
    FacilitySetupType.clinic => Icons.medical_services_outlined,
    FacilitySetupType.lab => Icons.biotech_outlined,
    FacilitySetupType.pharmacy => Icons.medication_outlined,
    FacilitySetupType.other => Icons.domain_outlined,
  };
}

String tenantFacilityDepartmentTypeLabel(
  AppLocalizations l10n,
  DepartmentSetupType type,
) {
  return switch (type) {
    DepartmentSetupType.clinical => l10n.tenantFacilityDepartmentTypeClinical,
    DepartmentSetupType.administrative =>
      l10n.tenantFacilityDepartmentTypeAdministrative,
    DepartmentSetupType.support => l10n.tenantFacilityDepartmentTypeSupport,
    DepartmentSetupType.diagnostics =>
      l10n.tenantFacilityDepartmentTypeDiagnostics,
    DepartmentSetupType.other => l10n.tenantFacilityDepartmentTypeOther,
  };
}

String tenantFacilityWardTypeLabel(AppLocalizations l10n, WardSetupType type) {
  return switch (type) {
    WardSetupType.general => l10n.tenantFacilityWardTypeGeneral,
    WardSetupType.icu => l10n.tenantFacilityWardTypeIcu,
    WardSetupType.maternity => l10n.tenantFacilityWardTypeMaternity,
    WardSetupType.pediatric => l10n.tenantFacilityWardTypePediatric,
    WardSetupType.surgical => l10n.tenantFacilityWardTypeSurgical,
    WardSetupType.other => l10n.tenantFacilityWardTypeOther,
  };
}

String tenantFacilityBedStatusLabel(
  AppLocalizations l10n,
  BedSetupStatus status,
) {
  return switch (status) {
    BedSetupStatus.available => l10n.tenantFacilityBedStatusAvailable,
    BedSetupStatus.occupied => l10n.tenantFacilityBedStatusOccupied,
    BedSetupStatus.reserved => l10n.tenantFacilityBedStatusReserved,
    BedSetupStatus.cleaning => l10n.tenantFacilityBedStatusCleaning,
    BedSetupStatus.maintenance => l10n.tenantFacilityBedStatusMaintenance,
    BedSetupStatus.blocked => l10n.tenantFacilityBedStatusBlocked,
    BedSetupStatus.outOfService => l10n.tenantFacilityBedStatusOutOfService,
  };
}

String? tenantFacilityDepartmentName(
  FacilitySetupSnapshot snapshot,
  String? departmentId,
) {
  return snapshot.departments
      .where((DepartmentProfile department) => department.id == departmentId)
      .map((DepartmentProfile department) => department.name)
      .firstOrNull;
}

String? tenantFacilityWardName(FacilitySetupSnapshot snapshot, String? wardId) {
  return snapshot.wards
      .where((WardProfile ward) => ward.id == wardId)
      .map((WardProfile ward) => ward.name)
      .firstOrNull;
}

String? tenantFacilityRoomName(FacilitySetupSnapshot snapshot, String? roomId) {
  return snapshot.rooms
      .where((RoomProfile room) => room.id == roomId)
      .map((RoomProfile room) => room.name)
      .firstOrNull;
}

String tenantFacilityRecordPreview<T>({
  required List<T> records,
  required String emptyLabel,
  required String Function(T record) labelFor,
}) {
  if (records.isEmpty) {
    return emptyLabel;
  }

  final List<String> labels = records
      .take(2)
      .map(labelFor)
      .map((String label) => label.trim())
      .where((String label) => label.isNotEmpty)
      .toList(growable: false);

  return labels.isEmpty ? emptyLabel : labels.join('; ');
}

enum TenantFacilitySetupWizardStep {
  tenant,
  facility,
  departments,
  units,
  wards,
  rooms,
  beds,
}

bool tenantFacilityWizardStepOptional(TenantFacilitySetupWizardStep step) {
  return switch (step) {
    TenantFacilitySetupWizardStep.units ||
    TenantFacilitySetupWizardStep.wards => true,
    TenantFacilitySetupWizardStep.tenant ||
    TenantFacilitySetupWizardStep.facility ||
    TenantFacilitySetupWizardStep.departments ||
    TenantFacilitySetupWizardStep.rooms ||
    TenantFacilitySetupWizardStep.beds => false,
  };
}

bool tenantFacilityWizardStepVisible({
  required TenantFacilitySetupWizardStep step,
  required bool canManageTenant,
  required bool canManageFacility,
}) {
  return switch (step) {
    TenantFacilitySetupWizardStep.tenant => canManageTenant,
    TenantFacilitySetupWizardStep.facility ||
    TenantFacilitySetupWizardStep.departments ||
    TenantFacilitySetupWizardStep.units ||
    TenantFacilitySetupWizardStep.wards ||
    TenantFacilitySetupWizardStep.rooms ||
    TenantFacilitySetupWizardStep.beds => canManageFacility || canManageTenant,
  };
}

List<TenantFacilitySetupWizardStep> tenantFacilityVisibleWizardSteps({
  required bool canManageTenant,
  required bool canManageFacility,
}) {
  return TenantFacilitySetupWizardStep.values
      .where(
        (TenantFacilitySetupWizardStep step) => tenantFacilityWizardStepVisible(
          step: step,
          canManageTenant: canManageTenant,
          canManageFacility: canManageFacility,
        ),
      )
      .toList(growable: false);
}

bool tenantFacilityWizardStepCompleted(
  FacilitySetupSnapshot snapshot,
  TenantFacilitySetupWizardStep step,
) {
  return switch (step) {
    TenantFacilitySetupWizardStep.tenant => snapshot.hasTenant,
    TenantFacilitySetupWizardStep.facility => snapshot.hasFacilityIdentity,
    TenantFacilitySetupWizardStep.departments => snapshot.hasDepartments,
    TenantFacilitySetupWizardStep.units => snapshot.hasUnitsConfigured,
    TenantFacilitySetupWizardStep.wards => snapshot.hasWardsConfigured,
    TenantFacilitySetupWizardStep.rooms => snapshot.hasRoomsConfigured,
    TenantFacilitySetupWizardStep.beds => snapshot.hasBedsConfigured,
  };
}

/// One completion criterion for a setup wizard step.
class TenantFacilityWizardStepRequirement {
  const TenantFacilityWizardStepRequirement({
    required this.label,
    required this.satisfied,
    required this.fixStep,
    this.isPrerequisite = false,
  });

  final String label;
  final bool satisfied;

  /// Wizard step that can resolve this requirement.
  final TenantFacilitySetupWizardStep fixStep;

  /// True when this item belongs to an earlier prerequisite step.
  final bool isPrerequisite;
}

/// Local requirements for [step] only (no prerequisite chain).
List<TenantFacilityWizardStepRequirement> tenantFacilityWizardStepRequirements(
  AppLocalizations l10n,
  FacilitySetupSnapshot snapshot,
  TenantFacilitySetupWizardStep step,
) {
  return switch (step) {
    TenantFacilitySetupWizardStep.tenant =>
      <TenantFacilityWizardStepRequirement>[
        TenantFacilityWizardStepRequirement(
          label: l10n.tenantFacilityWizardMissingTenant,
          satisfied: snapshot.hasTenant,
          fixStep: TenantFacilitySetupWizardStep.tenant,
        ),
      ],
    TenantFacilitySetupWizardStep.facility => () {
      final FacilityProfile? facility = snapshot.facility;
      final bool hasFacility = facility != null;
      final bool hasName = facility?.name.trim().isNotEmpty == true;
      final FacilityEffectiveContact contact =
          snapshot.resolvedEffectiveContact;
      final bool hasPhone = contact.hasPhone;
      return <TenantFacilityWizardStepRequirement>[
        TenantFacilityWizardStepRequirement(
          label: l10n.tenantFacilityWizardMissingFacility,
          satisfied: hasFacility,
          fixStep: TenantFacilitySetupWizardStep.facility,
        ),
        TenantFacilityWizardStepRequirement(
          label: l10n.tenantFacilityWizardMissingFacilityName,
          satisfied: hasName,
          fixStep: TenantFacilitySetupWizardStep.facility,
        ),
        TenantFacilityWizardStepRequirement(
          label: contact.isPhoneInherited
              ? l10n.tenantFacilityWizardFacilityPhoneInherited
              : l10n.tenantFacilityWizardMissingFacilityPhone,
          satisfied: hasPhone,
          fixStep: TenantFacilitySetupWizardStep.facility,
        ),
      ];
    }(),
    TenantFacilitySetupWizardStep.departments =>
      <TenantFacilityWizardStepRequirement>[
        TenantFacilityWizardStepRequirement(
          label: l10n.tenantFacilityWizardMissingDepartments,
          satisfied: snapshot.hasDepartments,
          fixStep: TenantFacilitySetupWizardStep.departments,
        ),
      ],
    TenantFacilitySetupWizardStep.units =>
      <TenantFacilityWizardStepRequirement>[
        TenantFacilityWizardStepRequirement(
          label: l10n.tenantFacilityWizardMissingUnits,
          satisfied: snapshot.hasUnitsConfigured,
          fixStep: TenantFacilitySetupWizardStep.units,
        ),
      ],
    TenantFacilitySetupWizardStep.wards =>
      <TenantFacilityWizardStepRequirement>[
        TenantFacilityWizardStepRequirement(
          label: l10n.tenantFacilityWizardMissingWards,
          satisfied: snapshot.hasWardsConfigured,
          fixStep: TenantFacilitySetupWizardStep.wards,
        ),
      ],
    TenantFacilitySetupWizardStep.rooms =>
      <TenantFacilityWizardStepRequirement>[
        TenantFacilityWizardStepRequirement(
          label: l10n.tenantFacilityWizardMissingRooms,
          satisfied: snapshot.hasRoomsConfigured,
          fixStep: TenantFacilitySetupWizardStep.rooms,
        ),
      ],
    TenantFacilitySetupWizardStep.beds => <TenantFacilityWizardStepRequirement>[
      TenantFacilityWizardStepRequirement(
        label: l10n.tenantFacilityWizardMissingBeds,
        satisfied: snapshot.hasBedsConfigured,
        fixStep: TenantFacilitySetupWizardStep.beds,
      ),
    ],
  };
}

/// Extra gate requirements that must be true before [step] can be configured.
List<TenantFacilityWizardStepRequirement>
tenantFacilityWizardStepGateRequirements(
  AppLocalizations l10n,
  FacilitySetupSnapshot snapshot,
  TenantFacilitySetupWizardStep step,
) {
  return switch (step) {
    TenantFacilitySetupWizardStep.units =>
      <TenantFacilityWizardStepRequirement>[
        TenantFacilityWizardStepRequirement(
          label: l10n.tenantFacilityWizardMissingDepartments,
          satisfied: snapshot.hasDepartments,
          fixStep: TenantFacilitySetupWizardStep.departments,
          isPrerequisite: true,
        ),
      ],
    TenantFacilitySetupWizardStep.wards =>
      <TenantFacilityWizardStepRequirement>[
        TenantFacilityWizardStepRequirement(
          label: l10n.tenantFacilityWizardMissingDepartments,
          satisfied: snapshot.hasDepartments,
          fixStep: TenantFacilitySetupWizardStep.departments,
          isPrerequisite: true,
        ),
      ],
    TenantFacilitySetupWizardStep.rooms =>
      <TenantFacilityWizardStepRequirement>[
        TenantFacilityWizardStepRequirement(
          label: l10n.tenantFacilityWizardMissingDepartmentOrWard,
          satisfied: snapshot.hasDepartments || snapshot.hasWardsConfigured,
          fixStep: snapshot.hasDepartments
              ? TenantFacilitySetupWizardStep.wards
              : TenantFacilitySetupWizardStep.departments,
          isPrerequisite: true,
        ),
      ],
    TenantFacilitySetupWizardStep.beds => <TenantFacilityWizardStepRequirement>[
      TenantFacilityWizardStepRequirement(
        label: l10n.tenantFacilityWizardMissingWards,
        satisfied: snapshot.hasWardsConfigured,
        fixStep: TenantFacilitySetupWizardStep.wards,
        isPrerequisite: true,
      ),
    ],
    _ => const <TenantFacilityWizardStepRequirement>[],
  };
}

/// Full blocker chain for [step]: earlier required steps + gates + local items.
List<TenantFacilityWizardStepRequirement> tenantFacilityWizardBlockersForStep(
  AppLocalizations l10n,
  FacilitySetupSnapshot snapshot,
  TenantFacilitySetupWizardStep step, {
  List<TenantFacilitySetupWizardStep>? steps,
}) {
  final List<TenantFacilitySetupWizardStep> visible =
      steps ?? TenantFacilitySetupWizardStep.values;
  final int targetIndex = visible.indexOf(step);
  if (targetIndex < 0) {
    return tenantFacilityWizardStepRequirements(l10n, snapshot, step);
  }

  final List<TenantFacilityWizardStepRequirement> blockers =
      <TenantFacilityWizardStepRequirement>[];
  final Set<String> seen = <String>{};

  void addAll(Iterable<TenantFacilityWizardStepRequirement> items) {
    for (final TenantFacilityWizardStepRequirement item in items) {
      if (seen.add('${item.fixStep.name}:${item.label}')) {
        blockers.add(item);
      }
    }
  }

  for (int index = 0; index < targetIndex; index += 1) {
    final TenantFacilitySetupWizardStep prior = visible[index];
    if (tenantFacilityWizardStepOptional(prior)) {
      continue;
    }
    addAll(
      tenantFacilityWizardStepRequirements(l10n, snapshot, prior).map(
        (TenantFacilityWizardStepRequirement item) =>
            TenantFacilityWizardStepRequirement(
              label: item.label,
              satisfied: item.satisfied,
              fixStep: item.fixStep,
              isPrerequisite: true,
            ),
      ),
    );
  }

  addAll(tenantFacilityWizardStepGateRequirements(l10n, snapshot, step));
  addAll(tenantFacilityWizardStepRequirements(l10n, snapshot, step));
  return blockers;
}

/// Outstanding blockers only (unsatisfied).
List<TenantFacilityWizardStepRequirement>
tenantFacilityWizardOutstandingBlockers(
  AppLocalizations l10n,
  FacilitySetupSnapshot snapshot,
  TenantFacilitySetupWizardStep step, {
  List<TenantFacilitySetupWizardStep>? steps,
}) {
  return tenantFacilityWizardBlockersForStep(l10n, snapshot, step, steps: steps)
      .where((TenantFacilityWizardStepRequirement item) => !item.satisfied)
      .toList(growable: false);
}

/// Concrete items still required before [step] is considered complete.
List<String> tenantFacilityWizardStepMissingRequirements(
  AppLocalizations l10n,
  FacilitySetupSnapshot snapshot,
  TenantFacilitySetupWizardStep step,
) {
  return tenantFacilityWizardStepRequirements(l10n, snapshot, step)
      .where((TenantFacilityWizardStepRequirement item) => !item.satisfied)
      .map((TenantFacilityWizardStepRequirement item) => item.label)
      .toList(growable: false);
}

/// First step that still has outstanding required blockers for [targetStep].
TenantFacilitySetupWizardStep? tenantFacilityWizardFirstBlockingStep(
  AppLocalizations l10n,
  FacilitySetupSnapshot snapshot,
  TenantFacilitySetupWizardStep targetStep, {
  List<TenantFacilitySetupWizardStep>? steps,
}) {
  final List<TenantFacilityWizardStepRequirement> outstanding =
      tenantFacilityWizardOutstandingBlockers(
        l10n,
        snapshot,
        targetStep,
        steps: steps,
      );
  if (outstanding.isEmpty) {
    return null;
  }
  return outstanding.first.fixStep;
}

/// Intro line for an incomplete wizard step banner (without the checklist).
String? tenantFacilityWizardStepPendingIntro(
  AppLocalizations l10n, {
  required FacilitySetupSnapshot snapshot,
  required TenantFacilitySetupWizardStep step,
  String? nextActionLabel,
  List<TenantFacilitySetupWizardStep>? steps,
}) {
  final List<TenantFacilityWizardStepRequirement> outstanding =
      tenantFacilityWizardOutstandingBlockers(
        l10n,
        snapshot,
        step,
        steps: steps,
      );
  if (outstanding.isEmpty) {
    return null;
  }

  final bool optional = tenantFacilityWizardStepOptional(step);
  final bool hasPrerequisiteBlockers = outstanding.any(
    (TenantFacilityWizardStepRequirement item) => item.isPrerequisite,
  );

  if (hasPrerequisiteBlockers) {
    return nextActionLabel == null
        ? l10n.tenantFacilityWizardPendingCompleteStep
        : l10n.tenantFacilityWizardPendingUnlockNext(nextActionLabel);
  }

  if (optional) {
    return nextActionLabel == null
        ? l10n.tenantFacilityWizardOptionalPendingStandalone
        : l10n.tenantFacilityWizardOptionalPendingHint(nextActionLabel);
  }

  return nextActionLabel == null
      ? l10n.tenantFacilityWizardPendingCompleteStep
      : l10n.tenantFacilityWizardPendingUnlockNext(nextActionLabel);
}

/// Banner copy for an incomplete wizard step, including why Next may be inactive.
String? tenantFacilityWizardStepPendingBannerMessage(
  AppLocalizations l10n, {
  required FacilitySetupSnapshot snapshot,
  required TenantFacilitySetupWizardStep step,
  String? nextActionLabel,
  List<TenantFacilitySetupWizardStep>? steps,
}) {
  final String? intro = tenantFacilityWizardStepPendingIntro(
    l10n,
    snapshot: snapshot,
    step: step,
    nextActionLabel: nextActionLabel,
    steps: steps,
  );
  if (intro == null) {
    return null;
  }

  final String bullets =
      tenantFacilityWizardOutstandingBlockers(
            l10n,
            snapshot,
            step,
            steps: steps,
          )
          .map(
            (TenantFacilityWizardStepRequirement item) =>
                l10n.tenantFacilityWizardPendingBullet(item.label),
          )
          .join('\n');
  return '$intro\n$bullets';
}

/// Snackbar/detail copy listing every outstanding blocker for a locked step.
String tenantFacilityWizardLockedStepBlockersMessage(
  AppLocalizations l10n,
  FacilitySetupSnapshot snapshot,
  TenantFacilitySetupWizardStep step, {
  List<TenantFacilitySetupWizardStep>? steps,
}) {
  final List<TenantFacilityWizardStepRequirement> outstanding =
      tenantFacilityWizardOutstandingBlockers(
        l10n,
        snapshot,
        step,
        steps: steps,
      );
  if (outstanding.isEmpty) {
    return tenantFacilityWizardStepBlockedHint(l10n, snapshot, step);
  }

  final String bullets = outstanding
      .map(
        (TenantFacilityWizardStepRequirement item) =>
            l10n.tenantFacilityWizardPendingBullet(
              l10n.tenantFacilityWizardBlockerOnStep(
                item.label,
                tenantFacilityWizardStepLabel(l10n, item.fixStep),
              ),
            ),
      )
      .join('\n');
  return '${l10n.tenantFacilityWizardBlockersTitle}\n$bullets';
}

/// Required steps block progress; optional steps never block the next required step.
bool tenantFacilityWizardStepBlocksProgress(
  FacilitySetupSnapshot snapshot,
  TenantFacilitySetupWizardStep step,
) {
  if (tenantFacilityWizardStepOptional(step)) {
    return false;
  }
  return !tenantFacilityWizardStepCompleted(snapshot, step);
}

TenantFacilitySetupWizardStep? tenantFacilityNextIncompleteWizardStep(
  FacilitySetupSnapshot snapshot, {
  List<TenantFacilitySetupWizardStep>? steps,
}) {
  final List<TenantFacilitySetupWizardStep> visible =
      steps ?? TenantFacilitySetupWizardStep.values;
  for (final TenantFacilitySetupWizardStep step in visible) {
    if (tenantFacilityWizardStepBlocksProgress(snapshot, step)) {
      return step;
    }
  }
  for (final TenantFacilitySetupWizardStep step in visible) {
    if (!tenantFacilityWizardStepCompleted(snapshot, step)) {
      return step;
    }
  }
  return null;
}

/// Furthest step index (in [steps]) the user may open.
int tenantFacilityFurthestReachableWizardIndex(
  FacilitySetupSnapshot snapshot,
  List<TenantFacilitySetupWizardStep> steps,
) {
  if (steps.isEmpty) {
    return -1;
  }

  for (int index = 0; index < steps.length; index += 1) {
    if (tenantFacilityWizardStepBlocksProgress(snapshot, steps[index])) {
      return index;
    }
  }
  return steps.length - 1;
}

bool tenantFacilityWizardStepReachable(
  FacilitySetupSnapshot snapshot,
  List<TenantFacilitySetupWizardStep> steps,
  TenantFacilitySetupWizardStep step,
) {
  final int index = steps.indexOf(step);
  if (index < 0) {
    return false;
  }
  if (tenantFacilityWizardStepCompleted(snapshot, step)) {
    return true;
  }
  return index <= tenantFacilityFurthestReachableWizardIndex(snapshot, steps);
}

String tenantFacilityWizardStepLabel(
  AppLocalizations l10n,
  TenantFacilitySetupWizardStep step,
) {
  return switch (step) {
    TenantFacilitySetupWizardStep.tenant => l10n.tenantFacilityWizardStepTenant,
    TenantFacilitySetupWizardStep.facility =>
      l10n.tenantFacilityWizardStepFacility,
    TenantFacilitySetupWizardStep.departments =>
      l10n.tenantFacilityWizardStepDepartments,
    TenantFacilitySetupWizardStep.units => l10n.tenantFacilityWizardStepUnits,
    TenantFacilitySetupWizardStep.wards => l10n.tenantFacilityWizardStepWards,
    TenantFacilitySetupWizardStep.rooms => l10n.tenantFacilityWizardStepRooms,
    TenantFacilitySetupWizardStep.beds => l10n.tenantFacilityWizardStepBeds,
  };
}

IconData tenantFacilityWizardStepIcon(TenantFacilitySetupWizardStep step) {
  return switch (step) {
    TenantFacilitySetupWizardStep.tenant => Icons.apartment_outlined,
    TenantFacilitySetupWizardStep.facility => Icons.local_hospital_outlined,
    TenantFacilitySetupWizardStep.departments => Icons.groups_2_outlined,
    TenantFacilitySetupWizardStep.units => Icons.hub_outlined,
    TenantFacilitySetupWizardStep.wards => Icons.local_hotel_outlined,
    TenantFacilitySetupWizardStep.rooms => Icons.meeting_room_outlined,
    TenantFacilitySetupWizardStep.beds => Icons.bed_outlined,
  };
}

String tenantFacilityWizardStepSummary(
  AppLocalizations l10n,
  FacilitySetupSnapshot snapshot,
  TenantFacilitySetupWizardStep step,
) {
  return switch (step) {
    TenantFacilitySetupWizardStep.tenant =>
      snapshot.tenant?.name.trim().isNotEmpty == true
          ? snapshot.tenant!.name
          : l10n.tenantFacilityChecklistTenant,
    TenantFacilitySetupWizardStep.facility =>
      snapshot.facility?.name.trim().isNotEmpty == true
          ? snapshot.facility!.name
          : l10n.tenantFacilityChecklistIdentity,
    TenantFacilitySetupWizardStep.departments =>
      l10n.tenantFacilitySummaryRecordCount(snapshot.departments.length),
    TenantFacilitySetupWizardStep.units =>
      l10n.tenantFacilitySummaryRecordCount(snapshot.units.length),
    TenantFacilitySetupWizardStep.wards =>
      l10n.tenantFacilitySummaryRecordCount(snapshot.wards.length),
    TenantFacilitySetupWizardStep.rooms =>
      l10n.tenantFacilitySummaryRecordCount(snapshot.rooms.length),
    TenantFacilitySetupWizardStep.beds => l10n.tenantFacilitySummaryRecordCount(
      snapshot.beds.length,
    ),
  };
}

bool tenantFacilityWizardStepHasRecords(
  FacilitySetupSnapshot snapshot,
  TenantFacilitySetupWizardStep step,
) {
  return switch (step) {
    TenantFacilitySetupWizardStep.tenant => snapshot.hasTenant,
    TenantFacilitySetupWizardStep.facility => snapshot.hasFacility,
    TenantFacilitySetupWizardStep.departments =>
      snapshot.departments.isNotEmpty,
    TenantFacilitySetupWizardStep.units => snapshot.units.isNotEmpty,
    TenantFacilitySetupWizardStep.wards => snapshot.wards.isNotEmpty,
    TenantFacilitySetupWizardStep.rooms => snapshot.rooms.isNotEmpty,
    TenantFacilitySetupWizardStep.beds => snapshot.beds.isNotEmpty,
  };
}

String tenantFacilityWizardStepEmptyMessage(
  AppLocalizations l10n,
  TenantFacilitySetupWizardStep step,
) {
  return switch (step) {
    TenantFacilitySetupWizardStep.tenant => l10n.tenantFacilityChecklistTenant,
    TenantFacilitySetupWizardStep.facility => l10n.tenantFacilityNoFacilities,
    TenantFacilitySetupWizardStep.departments =>
      l10n.tenantFacilityNoDepartments,
    TenantFacilitySetupWizardStep.units => l10n.tenantFacilityNoUnits,
    TenantFacilitySetupWizardStep.wards => l10n.tenantFacilityNoWards,
    TenantFacilitySetupWizardStep.rooms => l10n.tenantFacilityNoRooms,
    TenantFacilitySetupWizardStep.beds => l10n.tenantFacilityNoBeds,
  };
}

String tenantFacilityWizardPrimaryActionLabel(
  AppLocalizations l10n, {
  required TenantFacilitySetupWizardStep step,
  required FacilitySetupSnapshot snapshot,
  required bool canCreateTenant,
}) {
  final bool hasRecords = tenantFacilityWizardStepHasRecords(snapshot, step);
  return switch (step) {
    TenantFacilitySetupWizardStep.tenant =>
      hasRecords
          ? l10n.tenantFacilityEditTenantAction
          : (canCreateTenant
                ? l10n.tenantFacilityCreateTenantAction
                : l10n.tenantFacilityEditTenantAction),
    TenantFacilitySetupWizardStep.facility =>
      hasRecords
          ? l10n.tenantFacilityEditFacilityAction
          : l10n.tenantFacilityCreateFacilityTitle,
    TenantFacilitySetupWizardStep.departments =>
      hasRecords
          ? l10n.tenantFacilityManageDepartmentsAction
          : l10n.tenantFacilityCreateDepartmentAction,
    TenantFacilitySetupWizardStep.units =>
      hasRecords
          ? l10n.tenantFacilityManageUnitsAction
          : l10n.tenantFacilityCreateUnitAction,
    TenantFacilitySetupWizardStep.wards =>
      hasRecords
          ? l10n.tenantFacilityManageWardsAction
          : l10n.tenantFacilityCreateWardAction,
    TenantFacilitySetupWizardStep.rooms =>
      hasRecords
          ? l10n.tenantFacilityManageRoomsAction
          : l10n.tenantFacilityCreateRoomAction,
    TenantFacilitySetupWizardStep.beds =>
      hasRecords
          ? l10n.tenantFacilityManageBedsAction
          : l10n.tenantFacilityCreateBedAction,
  };
}

IconData tenantFacilityWizardPrimaryActionIcon({
  required TenantFacilitySetupWizardStep step,
  required FacilitySetupSnapshot snapshot,
}) {
  final bool hasRecords = tenantFacilityWizardStepHasRecords(snapshot, step);
  if (hasRecords) {
    return switch (step) {
      TenantFacilitySetupWizardStep.tenant ||
      TenantFacilitySetupWizardStep.facility => Icons.edit_outlined,
      _ => Icons.list_alt_outlined,
    };
  }
  return Icons.add_circle_outline;
}

String tenantFacilityWizardContinueToStepLabel(
  AppLocalizations l10n,
  TenantFacilitySetupWizardStep step,
) {
  return l10n.tenantFacilityNextStepAction(
    tenantFacilityWizardStepLabel(l10n, step),
  );
}

String tenantFacilityWizardProgressCaption({
  required int currentIndex,
  required int totalSteps,
  required String stepLabel,
  required bool optional,
}) {
  final String base = 'Step ${currentIndex + 1} of $totalSteps · $stepLabel';
  return optional ? '$base · Optional' : base;
}

/// Explains why a locked wizard step cannot be opened yet.
String tenantFacilityWizardStepBlockedHint(
  AppLocalizations l10n,
  FacilitySetupSnapshot snapshot,
  TenantFacilitySetupWizardStep step,
) {
  return switch (step) {
    TenantFacilitySetupWizardStep.tenant =>
      l10n.tenantFacilityPermissionRequired,
    TenantFacilitySetupWizardStep.facility =>
      snapshot.hasTenant
          ? _tenantFacilityWizardMissingSummary(
              l10n,
              snapshot,
              TenantFacilitySetupWizardStep.facility,
              fallback: l10n.tenantFacilityGateNeedFacility,
            )
          : l10n.tenantFacilityGateNeedTenant,
    TenantFacilitySetupWizardStep.departments =>
      snapshot.hasFacilityIdentity
          ? l10n.tenantFacilityWizardMissingDepartments
          : _tenantFacilityWizardMissingSummary(
              l10n,
              snapshot,
              TenantFacilitySetupWizardStep.facility,
              fallback: l10n.tenantFacilityGateNeedFacility,
            ),
    TenantFacilitySetupWizardStep.units =>
      snapshot.hasDepartments
          ? l10n.tenantFacilityGateNeedDepartmentForUnits
          : (snapshot.hasFacilityIdentity
                ? l10n.tenantFacilityGateNeedDepartmentForUnits
                : _tenantFacilityWizardMissingSummary(
                    l10n,
                    snapshot,
                    TenantFacilitySetupWizardStep.facility,
                    fallback: l10n.tenantFacilityGateNeedFacility,
                  )),
    TenantFacilitySetupWizardStep.wards =>
      snapshot.hasDepartments
          ? l10n.tenantFacilityGateNeedDepartmentForWards
          : (snapshot.hasFacilityIdentity
                ? l10n.tenantFacilityGateNeedDepartmentForWards
                : _tenantFacilityWizardMissingSummary(
                    l10n,
                    snapshot,
                    TenantFacilitySetupWizardStep.facility,
                    fallback: l10n.tenantFacilityGateNeedFacility,
                  )),
    TenantFacilitySetupWizardStep.rooms =>
      snapshot.hasFacilityIdentity
          ? l10n.tenantFacilityWizardMissingRooms
          : _tenantFacilityWizardMissingSummary(
              l10n,
              snapshot,
              TenantFacilitySetupWizardStep.facility,
              fallback: l10n.tenantFacilityGateNeedFacilityForRooms,
            ),
    TenantFacilitySetupWizardStep.beds =>
      snapshot.hasWardsConfigured
          ? l10n.tenantFacilityGateNeedWardsForBeds
          : (snapshot.hasFacilityIdentity
                ? l10n.tenantFacilityGateNeedWardsForBeds
                : _tenantFacilityWizardMissingSummary(
                    l10n,
                    snapshot,
                    TenantFacilitySetupWizardStep.facility,
                    fallback: l10n.tenantFacilityGateNeedFacility,
                  )),
  };
}

String _tenantFacilityWizardMissingSummary(
  AppLocalizations l10n,
  FacilitySetupSnapshot snapshot,
  TenantFacilitySetupWizardStep step, {
  required String fallback,
}) {
  final List<String> missing = tenantFacilityWizardStepMissingRequirements(
    l10n,
    snapshot,
    step,
  );
  if (missing.isEmpty) {
    return fallback;
  }
  return '$fallback ${missing.join('; ')}.';
}
