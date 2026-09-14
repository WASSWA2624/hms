import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hosspi_hms/app/theme/app_theme.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/permissions/access_policy.dart';
import 'package:hosspi_hms/core/permissions/app_permission.dart';
import 'package:hosspi_hms/core/permissions/permission_providers.dart';
import 'package:hosspi_hms/core/security/auth_session.dart';
import 'package:hosspi_hms/core/security/session_controller.dart';
import 'package:hosspi_hms/core/security/session_state.dart';
import 'package:hosspi_hms/core/security/session_tokens.dart';
import 'package:hosspi_hms/core/storage/storage_providers.dart';
import 'package:hosspi_hms/features/access_admin/data/repositories/access_admin_repository_impl.dart';
import 'package:hosspi_hms/features/access_admin/domain/entities/access_admin_entities.dart';
import 'package:hosspi_hms/features/access_admin/domain/repositories/access_admin_repository.dart';
import 'package:hosspi_hms/features/access_admin/presentation/widgets/user_mutation_dialog.dart';
import 'package:hosspi_hms/features/tenant_facility/data/repositories/tenant_facility_repository_impl.dart';
import 'package:hosspi_hms/features/tenant_facility/domain/entities/tenant_facility_setup.dart';
import 'package:hosspi_hms/features/tenant_facility/domain/repositories/tenant_facility_repository.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/shared/components/components.dart';
import 'package:hosspi_hms/shared/data/data.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockAccessAdminRepository extends Mock
    implements AccessAdminRepository {}

class _MockTenantFacilityRepository extends Mock
    implements TenantFacilityRepository {}

const AccessAdminWorkspaceState _workspaceState = AccessAdminWorkspaceState(
  data: AccessAdminWorkspaceData(
    lookups: AccessAdminLookups(userStatuses: <String>['ACTIVE', 'INACTIVE']),
  ),
  query: AccessAdminWorkspaceQuery(tenantId: 'tenant-1'),
);

const String _strongPassword = 'StrongPass123!';

final AppLocalizations l10n = lookupAppLocalizations(const Locale('en'));

AppAccessPolicy _tenantAdminPolicy() {
  return AppAccessPolicy.fromSession(
    AuthSession(
      tokens: SessionTokens(accessToken: 'access-token'),
      user: const AuthUserProfile(
        tenantId: 'tenant-1',
        roles: <String>['TENANT_ADMIN'],
      ),
      permissions: <AppPermission>{AppPermissions.tenantAdmin},
      isAuthorizationHydrated: true,
    ),
  );
}

Finder _textInput(String label) {
  return find
      .descendant(
        of: find.byWidgetPredicate(
          (Widget widget) =>
              (widget is AppTextField && widget.labelText == label) ||
              (widget is AppEmailField && widget.labelText == label),
        ),
        matching: find.byType(EditableText),
      )
      .first;
}

Future<void> _fillRequiredDetails(
  WidgetTester tester, {
  String password = _strongPassword,
}) async {
  await tester.enterText(_textInput(l10n.accessAdminFirstNameLabel), 'Grace');
  await tester.enterText(
    _textInput(l10n.accessAdminEmailLabel),
    'grace.nakato@example.com',
  );
  await tester.enterText(
    _textInput(l10n.accessAdminPositionLabel),
    'Charge Nurse',
  );
  await tester.enterText(_textInput(l10n.accessAdminPasswordLabel), password);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.save_outlined));
  await tester.pumpAndSettle();
}

void main() {
  late _MockAccessAdminRepository accessRepository;
  late _MockTenantFacilityRepository facilityRepository;

  setUpAll(() {
    registerFallbackValue(const AppPageRequest());
  });

  setUp(() {
    accessRepository = _MockAccessAdminRepository();
    facilityRepository = _MockTenantFacilityRepository();
    when(
      () => facilityRepository.listFacilities(
        request: any(named: 'request'),
        tenantId: any(named: 'tenantId'),
      ),
    ).thenAnswer(
      (_) async => const Result<AppPage<FacilityProfile>>.success(
        AppPage<FacilityProfile>(
          items: <FacilityProfile>[],
          request: AppPageRequest(),
        ),
      ),
    );
    when(
      () => accessRepository.getReferenceData(
        tenantId: any(named: 'tenantId'),
        facilityId: any(named: 'facilityId'),
        include: any(named: 'include'),
        forceRefresh: any(named: 'forceRefresh'),
      ),
    ).thenAnswer(
      (_) async => const Result<AccessAdminLookups>.success(
        AccessAdminLookups(
          roles: <AccessAdminLookupOption>[
            AccessAdminLookupOption(
              id: 'role-1',
              label: 'WARD_NURSE',
              displayName: 'Ward Nurse',
              permissionCount: 3,
            ),
          ],
        ),
      ),
    );
  });

  Future<void> openDialog(
    WidgetTester tester, {
    required UserMutationMode mode,
    required UserMutationSubmitHandler onSubmit,
    AccessAdminItem? initialUser,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accessAdminRepositoryProvider.overrideWithValue(accessRepository),
          tenantFacilityRepositoryProvider.overrideWithValue(
            facilityRepository,
          ),
          sharedPreferencesProvider.overrideWithValue(preferences),
          initialSessionStateProvider.overrideWithValue(
            const SessionState.ready(),
          ),
          appAccessPolicyProvider.overrideWithValue(_tenantAdminPolicy()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (BuildContext context, WidgetRef ref, Widget? child) {
                return Center(
                  child: ElevatedButton(
                    onPressed: () => unawaited(
                      showUserMutationDialog(
                        context: context,
                        ref: ref,
                        mode: mode,
                        state: _workspaceState,
                        initialUser: initialUser,
                        onSubmit: onSubmit,
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('create checks the password policy before calling the API', (
    WidgetTester tester,
  ) async {
    var submitted = false;
    await openDialog(
      tester,
      mode: UserMutationMode.create,
      onSubmit: (AccessAdminUserDraft draft, List<String> roleIds) async {
        submitted = true;
        return null;
      },
    );

    await _fillRequiredDetails(tester, password: 'weakpassword1!');
    await _save(tester);

    expect(find.text(l10n.validationPasswordUppercaseMessage), findsOneWidget);
    expect(submitted, isFalse);
  });

  testWidgets('create sends the chosen roles and scope with the account', (
    WidgetTester tester,
  ) async {
    AccessAdminUserDraft? sentDraft;
    List<String>? sentRoles;
    await openDialog(
      tester,
      mode: UserMutationMode.create,
      onSubmit: (AccessAdminUserDraft draft, List<String> roleIds) async {
        sentDraft = draft;
        sentRoles = roleIds;
        return null;
      },
    );

    expect(find.byType(AppRoleAssignmentPicker), findsOneWidget);
    await _fillRequiredDetails(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(const PageStorageKey<String>('role-browse-role-1')),
        matching: find.byType(Checkbox),
      ),
    );
    await tester.pumpAndSettle();
    await _save(tester);

    expect(sentRoles, <String>['role-1']);
    expect(sentDraft?.roleIds, <String>['role-1']);
    expect(sentDraft?.password, _strongPassword);
    expect(sentDraft?.tenantId, 'tenant-1');
    expect(
      sentDraft?.facilityId,
      isNull,
      reason: 'A tenant admin may leave the facility blank',
    );
  });

  testWidgets('shows API field errors on the matching field until it is edited', (
    WidgetTester tester,
  ) async {
    const String serverMessage =
        'A deleted user already uses this email in this tenant. Restore that user instead of creating a new one.';
    await openDialog(
      tester,
      mode: UserMutationMode.create,
      onSubmit: (AccessAdminUserDraft draft, List<String> roleIds) async {
        return AppFailure.conflict(
          code: 'EMAIL_EXISTS_DELETED_IN_TENANT',
          statusCode: 409,
          validationFields: const <String>{'email'},
          fieldMessages: const <String, String>{'email': serverMessage},
        );
      },
    );

    await _fillRequiredDetails(tester);
    await _save(tester);

    final Finder emailErrorOnField = find.descendant(
      of: find.byType(AppEmailField),
      matching: find.text(serverMessage),
    );
    expect(emailErrorOnField, findsOneWidget);

    await tester.enterText(
      _textInput(l10n.accessAdminEmailLabel),
      'grace.n@example.com',
    );
    await tester.pumpAndSettle();

    expect(emailErrorOnField, findsNothing);
  });

  testWidgets('edit has no roles and keeps the password unless one is entered', (
    WidgetTester tester,
  ) async {
    AccessAdminUserDraft? sentDraft;
    await openDialog(
      tester,
      mode: UserMutationMode.edit,
      initialUser: const AccessAdminItem(
        id: 'USR-0042',
        resource: AccessAdminResource.users,
        displayId: 'USR-0042',
        title: 'Grace Nakato',
        email: 'grace.nakato@example.com',
        firstName: 'Grace',
        lastName: 'Nakato',
        positionTitle: 'Charge Nurse',
        status: 'ACTIVE',
        tenantId: 'tenant-1',
      ),
      onSubmit: (AccessAdminUserDraft draft, List<String> roleIds) async {
        sentDraft = draft;
        return null;
      },
    );

    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is AppTextField &&
            widget.labelText == l10n.accessAdminPasswordLabel,
      ),
      findsNothing,
    );
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is AppTextField &&
            widget.labelText == l10n.accessAdminNewPasswordLabel,
      ),
      findsOneWidget,
    );
    expect(find.byType(AppRoleAssignmentPicker), findsNothing);

    await _save(tester);

    expect(sentDraft, isNotNull);
    expect(sentDraft!.password, isNull);
    expect(sentDraft!.roleIds, isEmpty);
    expect(sentDraft!.email, 'grace.nakato@example.com');
  });

  testWidgets('edit sends a new password only once it meets the policy', (
    WidgetTester tester,
  ) async {
    AccessAdminUserDraft? sentDraft;
    await openDialog(
      tester,
      mode: UserMutationMode.edit,
      initialUser: const AccessAdminItem(
        id: 'USR-0042',
        resource: AccessAdminResource.users,
        displayId: 'USR-0042',
        title: 'Grace Nakato',
        email: 'grace.nakato@example.com',
        firstName: 'Grace',
        lastName: 'Nakato',
        positionTitle: 'Charge Nurse',
        status: 'ACTIVE',
        tenantId: 'tenant-1',
      ),
      onSubmit: (AccessAdminUserDraft draft, List<String> roleIds) async {
        sentDraft = draft;
        return null;
      },
    );

    await tester.enterText(
      _textInput(l10n.accessAdminNewPasswordLabel),
      'weakpassword1!',
    );
    await tester.pumpAndSettle();
    await _save(tester);

    expect(find.text(l10n.validationPasswordUppercaseMessage), findsOneWidget);
    expect(sentDraft, isNull);

    await tester.enterText(
      _textInput(l10n.accessAdminNewPasswordLabel),
      _strongPassword,
    );
    await tester.pumpAndSettle();
    await _save(tester);

    expect(sentDraft?.password, _strongPassword);
  });
}
