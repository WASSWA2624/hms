import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hosspi_hms/app/theme/app_theme.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/permissions/access_policy.dart';
import 'package:hosspi_hms/core/permissions/permission_providers.dart';
import 'package:hosspi_hms/core/security/auth_session.dart';
import 'package:hosspi_hms/core/security/session_controller.dart';
import 'package:hosspi_hms/core/security/session_state.dart';
import 'package:hosspi_hms/core/security/session_tokens.dart';
import 'package:hosspi_hms/core/storage/storage_providers.dart';
import 'package:hosspi_hms/features/access_admin/data/repositories/access_admin_repository_impl.dart';
import 'package:hosspi_hms/features/access_admin/domain/entities/access_admin_entities.dart';
import 'package:hosspi_hms/features/access_admin/domain/repositories/access_admin_repository.dart';
import 'package:hosspi_hms/features/tenant_facility/data/repositories/tenant_facility_repository_impl.dart';
import 'package:hosspi_hms/features/tenant_facility/domain/entities/tenant_facility_setup.dart';
import 'package:hosspi_hms/features/tenant_facility/domain/repositories/tenant_facility_repository.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/pages/tenant_facility_setup_page.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/widgets/tenant_facility_management_dialogs.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/shared/data/data.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockTenantFacilityRepository extends Mock
    implements TenantFacilityRepository {}

class _MockAccessAdminRepository extends Mock
    implements AccessAdminRepository {}

const String _tenantPhone = '+256700000100';
const String _tenantEmail = 'desk@democare.test';

// The facility has no phone/email of its own; the server resolved the
// tenant's contact as its effective contact.
const FacilityEffectiveContact _inherited = FacilityEffectiveContact(
  phone: _tenantPhone,
  email: _tenantEmail,
  phoneSource: FacilityContactSource.tenant,
  emailSource: FacilityContactSource.tenant,
);

const FacilityProfile _facility = FacilityProfile(
  id: 'FAC-DEMO',
  tenantId: 'tenant-1',
  name: 'DemoCare General Hospital',
  type: FacilitySetupType.hospital,
  resourceUuid: 'facility-uuid',
  displayId: 'FAC-DEMO',
  addressLine1: '1 Demo Avenue',
  effectiveContact: _inherited,
);

const FacilitySetupSnapshot _snapshot = FacilitySetupSnapshot(
  tenant: TenantProfile(
    id: 'TEN-DEMO',
    name: 'DemoCare Tenant',
    contactPhone: _tenantPhone,
    contactEmail: _tenantEmail,
  ),
  facility: _facility,
  facilities: <FacilityProfile>[_facility],
  contactAddress: FacilityContactAddress(addressLine1: '1 Demo Avenue'),
  effectiveContact: _inherited,
);

Future<void> _pumpHost(
  WidgetTester tester, {
  required void Function(BuildContext context) onOpen,
}) async {
  final _MockTenantFacilityRepository tenantRepository =
      _MockTenantFacilityRepository();
  final _MockAccessAdminRepository accessRepository =
      _MockAccessAdminRepository();
  when(
    () => tenantRepository.getFacility(any()),
  ).thenAnswer((_) async => const Result<FacilityProfile>.success(_facility));
  when(
    () => tenantRepository.loadSetup(
      facilityId: any(named: 'facilityId'),
      tenantId: any(named: 'tenantId'),
      includeDeleted: any(named: 'includeDeleted'),
      includeStructure: any(named: 'includeStructure'),
    ),
  ).thenAnswer(
    (_) async => const Result<FacilitySetupSnapshot>.success(_snapshot),
  );
  when(() => accessRepository.getWorkspace(any())).thenAnswer(
    (_) async => const Result<AccessAdminWorkspaceData>.success(
      AccessAdminWorkspaceData(
        items: <AccessAdminItem>[],
        page: AppPage<AccessAdminItem>(
          items: <AccessAdminItem>[],
          request: AppPageRequest(pageSize: 12),
          totalItemCount: 0,
        ),
        query: AccessAdminWorkspaceQuery(),
      ),
    ),
  );

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences preferences = await SharedPreferences.getInstance();
  final AppAccessPolicy policy = AppAccessPolicy.fromSession(
    AuthSession(
      tokens: SessionTokens(accessToken: 'access-token'),
      user: const AuthUserProfile(
        tenantId: 'tenant-1',
        facilityId: 'facility-uuid',
        roles: <String>['PLATFORM_ADMIN'],
      ),
      isAuthorizationHydrated: true,
    ),
  );

  tester.view.physicalSize = const Size(1280, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tenantFacilityRepositoryProvider.overrideWithValue(tenantRepository),
        accessAdminRepositoryProvider.overrideWithValue(accessRepository),
        sharedPreferencesProvider.overrideWithValue(preferences),
        initialSessionStateProvider.overrideWithValue(
          const SessionState.ready(),
        ),
        appAccessPolicyProvider.overrideWithValue(policy),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => onOpen(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(const AccessAdminWorkspaceQuery());
  });

  testWidgets('facility details mark contacts inherited from the tenant', (
    WidgetTester tester,
  ) async {
    await _pumpHost(
      tester,
      onOpen: (BuildContext context) => showFacilityDetailsDialog(
        context,
        facility: _facility,
        tenantName: 'DemoCare Tenant',
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining(_tenantPhone), findsWidgets);
    expect(find.textContaining(_tenantEmail), findsWidgets);
    expect(find.textContaining('Phone · From tenant'), findsOneWidget);
    expect(find.textContaining('Email · From tenant'), findsOneWidget);
    expect(
      find.text(
        "Contacts marked From tenant use the tenant's details until this "
        'facility adds its own.',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.apartment_outlined), findsWidgets);
  });

  testWidgets('facility edit form hints inherited contacts without prefilling', (
    WidgetTester tester,
  ) async {
    await _pumpHost(
      tester,
      onOpen: (BuildContext context) => showTenantFacilityFacilityFormDialog(
        context,
        tenantId: _facility.tenantId,
        facility: _facility,
        managementMode: true,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.text('Leave empty to keep using the tenant phone: $_tenantPhone'),
      findsOneWidget,
    );
    expect(
      find.text('Leave empty to keep using the tenant email: $_tenantEmail'),
      findsOneWidget,
    );
    // No editable field holds the tenant's values, so saving cannot copy them.
    final Iterable<String> fieldValues = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .map((EditableText field) => field.controller.text);
    expect(fieldValues, isNot(contains(_tenantEmail)));
    expect(
      fieldValues.where((String value) => value.contains('700000100')),
      isEmpty,
    );
  });
}
