import 'package:flutter_test/flutter_test.dart';
import 'package:hosspi_hms/features/tenant_facility/data/dtos/tenant_facility_dtos.dart';
import 'package:hosspi_hms/features/tenant_facility/domain/entities/tenant_facility_setup.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/widgets/tenant_facility_setup_helpers.dart';
import 'package:hosspi_hms/l10n/app_localizations_en.dart';

const FacilityProfile _facility = FacilityProfile(
  id: 'FAC0001',
  tenantId: 'TEN0001',
  name: 'Main Campus',
  type: FacilitySetupType.hospital,
);

void main() {
  group('FacilityEffectiveContact.resolve', () {
    test('keeps the facility own values', () {
      final FacilityEffectiveContact contact = FacilityEffectiveContact.resolve(
        ownPhone: '+256700000200',
        ownEmail: 'main@acme.test',
        tenantPhone: '+256700000100',
        tenantEmail: 'desk@acme.test',
      );

      expect(contact.phone, '+256700000200');
      expect(contact.email, 'main@acme.test');
      expect(contact.phoneSource, FacilityContactSource.facility);
      expect(contact.emailSource, FacilityContactSource.facility);
      expect(contact.isPhoneInherited, isFalse);
    });

    test('inherits each missing field independently', () {
      final FacilityEffectiveContact contact = FacilityEffectiveContact.resolve(
        ownPhone: '  ',
        ownEmail: 'main@acme.test',
        inherited: const FacilityEffectiveContact(
          phone: '+256700000100',
          phoneSource: FacilityContactSource.tenant,
        ),
      );

      expect(contact.phone, '+256700000100');
      expect(contact.isPhoneInherited, isTrue);
      expect(contact.email, 'main@acme.test');
      expect(contact.isEmailInherited, isFalse);
    });

    test('ignores a server value that was the facility own', () {
      final FacilityEffectiveContact contact = FacilityEffectiveContact.resolve(
        inherited: const FacilityEffectiveContact(
          phone: '+256700000200',
          phoneSource: FacilityContactSource.facility,
        ),
      );

      expect(contact.phone, isNull);
      expect(contact.phoneSource, FacilityContactSource.none);
    });
  });

  test('facility identity is complete with an inherited phone', () {
    const FacilitySetupSnapshot snapshot = FacilitySetupSnapshot(
      tenant: TenantProfile(
        id: 'TEN0001',
        name: 'Acme',
        contactPhone: '+256700000100',
      ),
      facility: _facility,
    );

    expect(snapshot.hasFacilityIdentity, isTrue);
    expect(snapshot.resolvedEffectiveContact.isPhoneInherited, isTrue);
    expect(
      tenantFacilityWizardStepRequirements(
        AppLocalizationsEn(),
        snapshot,
        TenantFacilitySetupWizardStep.facility,
      ).map((TenantFacilityWizardStepRequirement item) => item.label),
      contains('Facility phone uses the tenant phone'),
    );
  });

  test('maps effective_contact from facility and workspace payloads', () {
    const Map<String, Object?> effectiveContact = <String, Object?>{
      'phone': '+256700000100',
      'email': 'own@acme.test',
      'phone_source': 'TENANT',
      'email_source': 'FACILITY',
    };
    final FacilityProfile facility = FacilityProfileDto.fromJson(
      <String, Object?>{
        'id': 'facility-uuid',
        'tenant_id': 'tenant-uuid',
        'name': 'Main Campus',
        'facility_type': 'HOSPITAL',
        'contacts': <Object?>[
          <String, Object?>{'contact_type': 'EMAIL', 'value': 'own@acme.test'},
        ],
        'effective_contact': effectiveContact,
      },
    ).toEntity();

    // Own values stay own; the inherited phone only shows on displayContact.
    expect(facility.phone, isNull);
    expect(facility.email, 'own@acme.test');
    expect(facility.displayContact.phone, '+256700000100');
    expect(facility.displayContact.isPhoneInherited, isTrue);
    expect(
      tenantFacilityContactCellLabel(
        AppLocalizationsEn(),
        facility.displayContact.phone,
        inherited: facility.displayContact.isPhoneInherited,
      ),
      '+256700000100 (from tenant)',
    );

    final FacilitySetupSnapshot snapshot =
        FacilitySetupWorkspaceDto.fromResponse(<String, Object?>{
          'success': true,
          'data': <String, Object?>{
            'tenant': <String, Object?>{'id': 'TEN0001', 'name': 'Acme'},
            'facility': <String, Object?>{
              'id': 'FAC0001',
              'tenant_id': 'TEN0001',
              'name': 'Main Campus',
              'facility_type': 'HOSPITAL',
            },
            'contact_address': <String, Object?>{'email': 'own@acme.test'},
            'effective_contact': effectiveContact,
          },
        }).toEntity();

    expect(snapshot.contactAddress.phone, isNull);
    expect(snapshot.effectiveContact?.phoneSource, FacilityContactSource.tenant);
    expect(snapshot.resolvedEffectiveContact.phone, '+256700000100');
    expect(snapshot.resolvedEffectiveContact.email, 'own@acme.test');
  });
}
