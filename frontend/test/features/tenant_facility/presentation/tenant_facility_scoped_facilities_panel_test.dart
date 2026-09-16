import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hosspi_hms/core/permissions/access_policy.dart';
import 'package:hosspi_hms/core/security/auth_session.dart';
import 'package:hosspi_hms/core/security/session_tokens.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/widgets/tenant_facility_setup_helpers.dart';
import 'package:hosspi_hms/l10n/app_localizations_en.dart';

void main() {
  group('tenantFacilityUsesScopedFacilityPanel', () {
    test('platform creator uses facilities list', () {
      final AppAccessPolicy policy = AppAccessPolicy.fromSession(
        AuthSession(
          tokens: SessionTokens(accessToken: 't'),
          user: const AuthUserProfile(roles: <String>['PLATFORM_ADMIN']),
        ),
      );

      expect(policy.canCreateFacility(), isTrue);
      expect(
        tenantFacilityUsesScopedFacilityPanel(
          canManageFacility: policy.canManageFacility(),
          canCreateFacility: policy.canCreateFacility(),
        ),
        isFalse,
      );
      expect(
        tenantFacilityFacilitiesListScope(policy),
        TenantFacilityFacilitiesListScope.platform,
      );
    });

    test('tenant admin uses tenant-scoped facilities list', () {
      final AppAccessPolicy policy = AppAccessPolicy.fromSession(
        AuthSession(
          tokens: SessionTokens(accessToken: 't'),
          user: const AuthUserProfile(
            roles: <String>['TENANT_ADMIN'],
            tenantId: 'TEN0001',
            facilityId: 'FAC0001',
          ),
        ),
      );

      expect(policy.canCreateFacility(), isTrue);
      expect(
        tenantFacilityUsesScopedFacilityPanel(
          canManageFacility: policy.canManageFacility(),
          canCreateFacility: policy.canCreateFacility(),
        ),
        isFalse,
      );
      expect(
        tenantFacilityFacilitiesListScope(policy),
        TenantFacilityFacilitiesListScope.tenant,
      );
      expect(
        tenantFacilityFacilitiesShowsTenantColumn(
          TenantFacilityFacilitiesListScope.tenant,
        ),
        isFalse,
      );
      expect(
        tenantFacilityFacilitiesShowsCodeColumn(
          TenantFacilityFacilitiesListScope.tenant,
        ),
        isTrue,
      );
      expect(
        tenantFacilityFacilitiesShowsContactColumns(
          TenantFacilityFacilitiesListScope.tenant,
        ),
        isTrue,
      );
    });

    test('facility admin uses scoped facility details panel', () {
      final AppAccessPolicy policy = AppAccessPolicy.fromSession(
        AuthSession(
          tokens: SessionTokens(accessToken: 't'),
          user: const AuthUserProfile(
            roles: <String>['FACILITY_ADMIN'],
            tenantId: 'TEN0001',
            facilityId: 'FAC0001',
          ),
        ),
      );

      expect(policy.canCreateFacility(), isFalse);
      expect(policy.canManageFacility(), isTrue);
      expect(
        tenantFacilityUsesScopedFacilityPanel(
          canManageFacility: policy.canManageFacility(),
          canCreateFacility: policy.canCreateFacility(),
        ),
        isTrue,
      );
      expect(
        tenantFacilityFacilitiesListScope(policy),
        TenantFacilityFacilitiesListScope.facility,
      );
    });
  });

  group('tenantFacilityHumanFriendlyDisplayId', () {
    test('rejects UUIDs and opaque resource ids', () {
      expect(
        tenantFacilityHumanFriendlyDisplayId(
          '550e8400-e29b-41d4-a716-446655440000',
        ),
        isNull,
      );
      expect(
        tenantFacilityHumanFriendlyDisplayId(
          'FAC0001',
          opaqueId: '550e8400-e29b-41d4-a716-446655440000',
        ),
        'FAC0001',
      );
      expect(
        tenantFacilityHumanFriendlyDisplayId(
          '550e8400-e29b-41d4-a716-446655440000',
          opaqueId: '550e8400-e29b-41d4-a716-446655440000',
        ),
        isNull,
      );
    });
  });

  group('desk section singular/plural labels', () {
    final AppLocalizationsEn l10n = AppLocalizationsEn();

    test('platform uses plural Tenants and Facilities', () {
      final AppAccessPolicy policy = AppAccessPolicy.fromSession(
        AuthSession(
          tokens: SessionTokens(accessToken: 't'),
          user: const AuthUserProfile(roles: <String>['PLATFORM_ADMIN']),
        ),
      );

      expect(
        tenantFacilitySetupDeskSectionLabel(
          l10n,
          TenantFacilitySetupDeskSection.tenants,
          policy: policy,
        ),
        'Tenants',
      );
      expect(
        tenantFacilitySetupDeskSectionLabel(
          l10n,
          TenantFacilitySetupDeskSection.facility,
          policy: policy,
        ),
        'Facilities',
      );
    });

    test('tenant admin uses singular Tenant and plural Facilities', () {
      final AppAccessPolicy policy = AppAccessPolicy.fromSession(
        AuthSession(
          tokens: SessionTokens(accessToken: 't'),
          user: const AuthUserProfile(
            roles: <String>['TENANT_ADMIN'],
            tenantId: 'TEN0001',
          ),
        ),
      );

      expect(
        tenantFacilitySetupDeskSectionLabel(
          l10n,
          TenantFacilitySetupDeskSection.tenants,
          policy: policy,
        ),
        'Tenant',
      );
      expect(
        tenantFacilitySetupDeskSectionLabel(
          l10n,
          TenantFacilitySetupDeskSection.facility,
          policy: policy,
        ),
        'Facilities',
      );
    });

    test('facility admin uses singular Facility', () {
      final AppAccessPolicy policy = AppAccessPolicy.fromSession(
        AuthSession(
          tokens: SessionTokens(accessToken: 't'),
          user: const AuthUserProfile(
            roles: <String>['FACILITY_ADMIN'],
            tenantId: 'TEN0001',
            facilityId: 'FAC0001',
          ),
        ),
      );

      expect(
        tenantFacilitySetupDeskSectionLabel(
          l10n,
          TenantFacilitySetupDeskSection.facility,
          policy: policy,
        ),
        'Facility',
      );
    });
  });

  group('ManageFacilitiesPanel scoped wiring', () {
    late String managementDialogsSource;
    late String setupPageSource;

    setUpAll(() {
      managementDialogsSource = File(
        'lib/features/tenant_facility/presentation/widgets/'
        'tenant_facility_management_dialogs.dart',
      ).readAsStringSync();
      setupPageSource = File(
        'lib/features/tenant_facility/presentation/pages/'
        'tenant_facility_setup_page.dart',
      ).readAsStringSync();
    });

    test('setup page passes session facility into ManageFacilitiesPanel', () {
      expect(
        setupPageSource.contains('sessionFacility: snapshot.facility'),
        isTrue,
      );
      expect(
        setupPageSource.contains('sessionTenantId: snapshot.tenant?.id'),
        isTrue,
      );
    });

    test('scoped managers skip listFacilities and render own-facility details', () {
      expect(
        managementDialogsSource.contains('tenantFacilityUsesScopedFacilityPanel'),
        isTrue,
      );
      expect(
        managementDialogsSource.contains('_buildScopedBody'),
        isTrue,
      );
      expect(
        managementDialogsSource.contains('_reloadScopedFacility'),
        isTrue,
      );
      expect(
        managementDialogsSource.contains('_FacilityScopedDetailsSummary'),
        isTrue,
      );
      expect(
        managementDialogsSource.contains('tenantFacilityEditFacilityAction'),
        isTrue,
      );
      // Scoped managers refresh their own facility on realtime updates and
      // return before the list sync, so listFacilities never runs.
      expect(
        managementDialogsSource.contains(
          '_reloadScopedFacility(silent: true),\n'
          '      )..attach();\n'
          '      return;\n'
          '    }\n'
          '    _realtimeSync ??= PlatformManagementListSync(',
        ),
        isTrue,
      );
      expect(
        managementDialogsSource.contains('displayId ?? facility.id'),
        isFalse,
        reason: 'must not fall back to opaque facility ids in the UI',
      );
    });
  });
}
