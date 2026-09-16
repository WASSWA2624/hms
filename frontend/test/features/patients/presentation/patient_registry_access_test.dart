import 'package:flutter_test/flutter_test.dart';
import 'package:hosspi_hms/core/permissions/access_policy.dart';
import 'package:hosspi_hms/core/permissions/app_permission.dart';
import 'package:hosspi_hms/core/security/auth_session.dart';
import 'package:hosspi_hms/core/security/session_tokens.dart';
import 'package:hosspi_hms/features/patients/domain/entities/patient_entities.dart';
import 'package:hosspi_hms/features/patients/presentation/patient_registry_access.dart';
import 'package:hosspi_hms/shared/data/data.dart';

void main() {
  group('isPharmacyRegistryReader', () {
    test('returns true for pharmacist without patient write', () {
      final policy = AppAccessPolicy.fromSession(
        AuthSession(
          tokens: SessionTokens(accessToken: 'token'),
          user: const AuthUserProfile(roles: <String>['PHARMACIST']),
        ),
      );

      expect(isPharmacyRegistryReader(policy), isTrue);
    });

    test('returns true for custom role with pharmacy:read only', () {
      final policy = AppAccessPolicy.fromSession(
        AuthSession(
          tokens: SessionTokens(accessToken: 'token'),
          user: const AuthUserProfile(roles: <String>['CUSTOM_PHARMACY']),
          permissions: const <AppPermission>[AppPermissions.pharmacyRead],
          isAuthorizationHydrated: true,
        ),
      );

      expect(isPharmacyRegistryReader(policy), isTrue);
    });

    test('returns false for pharmacist with patient write', () {
      final policy = AppAccessPolicy.fromSession(
        AuthSession(
          tokens: SessionTokens(accessToken: 'token'),
          user: const AuthUserProfile(roles: <String>['PHARMACIST']),
          permissions: const <AppPermission>[
            AppPermissions.pharmacyRead,
            AppPermissions.patientWrite,
          ],
          isAuthorizationHydrated: true,
        ),
      );

      expect(isPharmacyRegistryReader(policy), isFalse);
    });
  });

  group('isBillingRegistryReader', () {
    test('returns true for custom role with billing:read only', () {
      final policy = AppAccessPolicy.fromSession(
        AuthSession(
          tokens: SessionTokens(accessToken: 'token'),
          user: const AuthUserProfile(roles: <String>['CUSTOM_BILLING']),
          permissions: const <AppPermission>[AppPermissions.billingRead],
          isAuthorizationHydrated: true,
        ),
      );

      expect(isBillingRegistryReader(policy), isTrue);
    });
  });

  group('patient registry requirements', () {
    AppAccessPolicy policyFor({
      required Set<AppPermission> permissions,
      List<AppModuleEntitlement> modules = const <AppModuleEntitlement>[
        AppModuleEntitlement(
          code: patientRegistryModule,
          licenseStatus: 'ACTIVE',
        ),
      ],
    }) {
      return AppAccessPolicy.fromSession(
        AuthSession(
          tokens: SessionTokens(accessToken: 'token'),
          user: const AuthUserProfile(
            roles: <String>['DOCTOR'],
            tenantId: 'tenant-1',
            facilityId: 'facility-1',
          ),
          permissions: permissions,
          moduleEntitlements: modules,
          isAuthorizationHydrated: true,
        ),
      );
    }

    test('read ∩ allows Active tab; write ∩ gates Register', () {
      final AppAccessPolicy read = policyFor(
        permissions: <AppPermission>{AppPermissions.patientRead},
      );
      expect(canViewPatientActiveTab(read), isTrue);
      expect(canViewPatientBalanceDueTab(read), isFalse);
      expect(canWritePatientRegistry(read), isFalse);
      expect(canDeletePatientRegistry(read), isFalse);

      final AppAccessPolicy write = policyFor(
        permissions: <AppPermission>{
          AppPermissions.patientRead,
          AppPermissions.patientWrite,
        },
      );
      expect(canWritePatientRegistry(write), isTrue);
      expect(
        patientRegistryAllowedSections(write),
        equals(<PatientRegistrySection>[
          PatientRegistrySection.all,
          PatientRegistrySection.active,
          PatientRegistrySection.admitted,
        ]),
      );
    });

    test(
      'Balance due tab needs ∩ patient:read + billing:read (+ billing module)',
      () {
        final AppAccessPolicy balanceDue = policyFor(
          permissions: <AppPermission>{
            AppPermissions.patientRead,
            AppPermissions.billingRead,
          },
          modules: const <AppModuleEntitlement>[
            AppModuleEntitlement(
              code: patientRegistryModule,
              licenseStatus: 'ACTIVE',
            ),
            AppModuleEntitlement(
              code: 'billing-payments',
              licenseStatus: 'ACTIVE',
            ),
          ],
        );
        expect(canViewPatientBalanceDueTab(balanceDue), isTrue);
        expect(
          patientRegistryAllowedSections(balanceDue),
          equals(PatientRegistrySection.values),
        );
      },
    );
  });

  group('Patient registry export / print gate', () {
    AppAccessPolicy policyFor({
      required Set<AppPermission> permissions,
      List<AppModuleEntitlement> modules = const <AppModuleEntitlement>[
        AppModuleEntitlement(
          code: patientRegistryModule,
          licenseStatus: 'ACTIVE',
        ),
      ],
    }) {
      return AppAccessPolicy.fromSession(
        AuthSession(
          tokens: SessionTokens(accessToken: 'token'),
          user: const AuthUserProfile(
            roles: <String>['CUSTOM'],
            tenantId: 'tenant-1',
            facilityId: 'facility-1',
          ),
          permissions: permissions,
          moduleEntitlements: modules,
          isAuthorizationHydrated: true,
        ),
      );
    }

    test('allows export/print when evidence:export is granted', () {
      final AppAccessPolicy policy = policyFor(
        permissions: <AppPermission>{
          AppPermissions.patientRead,
          AppPermissions.evidenceExport,
        },
      );
      expect(canExportPatientRegistry(policy), isTrue);
      expect(canPrintPatientRegistry(policy), isTrue);
      expect(PatientAllAtomPermissions.export.isAllowed(policy), isTrue);
      expect(PatientAllAtomPermissions.print.isAllowed(policy), isTrue);
      expect(PatientActiveAtomPermissions.export.isAllowed(policy), isTrue);
      expect(PatientAdmittedAtomPermissions.print.isAllowed(policy), isTrue);
      expect(
        PatientBalanceDueAtomPermissions.export.isAllowed(policy),
        isTrue,
      );
    });

    test('denies export/print without evidence:export', () {
      final AppAccessPolicy policy = policyFor(
        permissions: <AppPermission>{
          AppPermissions.patientRead,
          AppPermissions.patientWrite,
          AppPermissions.reportsRead,
        },
      );
      expect(canExportPatientRegistry(policy), isFalse);
      expect(canPrintPatientRegistry(policy), isFalse);
    });
  });

  group('patient cascade delete access', () {
    AppAccessPolicy policyFor({
      required Set<AppPermission> permissions,
      List<AppModuleEntitlement> modules = const <AppModuleEntitlement>[
        AppModuleEntitlement(
          code: patientRegistryModule,
          licenseStatus: 'ACTIVE',
        ),
      ],
    }) {
      return AppAccessPolicy.fromSession(
        AuthSession(
          tokens: SessionTokens(accessToken: 'token'),
          user: const AuthUserProfile(
            roles: <String>['CUSTOM'],
            tenantId: 'tenant-1',
            facilityId: 'facility-1',
          ),
          permissions: permissions,
          moduleEntitlements: modules,
          isAuthorizationHydrated: true,
        ),
      );
    }

    test('soft delete/restore require patient:delete', () {
      final AppAccessPolicy doctor = policyFor(
        permissions: <AppPermission>{
          AppPermissions.patientRead,
          AppPermissions.patientWrite,
        },
      );
      expect(canDeletePatientRegistry(doctor), isFalse);
      expect(canRestorePatientRegistry(doctor), isFalse);
      expect(PatientAllAtomPermissions.delete.isAllowed(doctor), isFalse);
      expect(PatientAllAtomPermissions.restore.isAllowed(doctor), isFalse);

      final AppAccessPolicy deleter = policyFor(
        permissions: <AppPermission>{
          AppPermissions.patientRead,
          AppPermissions.patientDelete,
        },
      );
      expect(canDeletePatientRegistry(deleter), isTrue);
      expect(canRestorePatientRegistry(deleter), isTrue);
      expect(canPermanentlyDeletePatientRegistry(deleter), isFalse);
    });

    test('permanent delete needs patient:delete and admin grant', () {
      final AppAccessPolicy facilityAdmin = policyFor(
        permissions: <AppPermission>{
          AppPermissions.patientDelete,
          AppPermissions.facilityAdmin,
        },
      );
      expect(canPermanentlyDeletePatientRegistry(facilityAdmin), isTrue);
      expect(
        PatientAllAtomPermissions.permanentDelete.isAllowed(facilityAdmin),
        isTrue,
      );

      final AppAccessPolicy deleteOnly = policyFor(
        permissions: <AppPermission>{AppPermissions.patientDelete},
      );
      expect(canPermanentlyDeletePatientRegistry(deleteOnly), isFalse);
    });
  });
}