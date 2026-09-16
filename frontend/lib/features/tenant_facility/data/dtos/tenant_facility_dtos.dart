import 'package:hosspi_hms/core/network/api_response.dart';
import 'package:hosspi_hms/features/tenant_facility/domain/entities/tenant_facility_setup.dart';

final class TenantProfileDto {
  const TenantProfileDto({
    required this.id,
    required this.name,
    this.slug,
    required this.isActive,
    this.currency,
    this.standardConsultationFee,
    this.contactName,
    this.contactEmail,
    this.contactPhone,
    this.resourceUuid,
    this.displayId,
    this.deletedAt,
    this.subscription,
  });

  factory TenantProfileDto.fromJson(JsonMap json) {
    final JsonMap extensionJson = _map(json['extension_json']);
    final JsonMap billing = _map(extensionJson['billing']);
    final JsonMap contactJson = _map(extensionJson['contact']);
    final JsonMap primaryAdmin = _map(json['primary_tenant_admin']);

    String? preferContact(String? preferred, String? fallback) {
      if (preferred != null && preferred.trim().isNotEmpty) {
        return preferred.trim();
      }
      if (fallback != null && fallback.trim().isNotEmpty) {
        return fallback.trim();
      }
      return null;
    }

    return TenantProfileDto(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      slug: _optionalString(json, 'slug'),
      isActive: _optionalBool(json, 'is_active') ?? true,
      currency: _optionalString(extensionJson, 'currency'),
      standardConsultationFee: _optionalDecimalString(
        billing,
        'standard_consultation_fee',
      ),
      contactName: preferContact(
        _optionalString(contactJson, 'name'),
        _optionalString(primaryAdmin, 'full_name'),
      ),
      contactEmail: preferContact(
        _optionalString(contactJson, 'email'),
        _optionalString(primaryAdmin, 'email'),
      ),
      contactPhone: preferContact(
        _optionalString(contactJson, 'phone'),
        _optionalString(primaryAdmin, 'phone'),
      ),
      resourceUuid:
          _optionalString(json, 'resource_uuid') ?? _requiredString(json, 'id'),
      displayId: _optionalString(json, 'display_id'),
      deletedAt: _optionalDateTime(json, 'deleted_at'),
      subscription: _tenantSubscription(json['current_subscription']),
    );
  }

  final String id;
  final String name;
  final String? slug;
  final bool isActive;
  final String? currency;
  final String? standardConsultationFee;
  final String? contactName;
  final String? contactEmail;
  final String? contactPhone;
  final String? resourceUuid;
  final String? displayId;
  final DateTime? deletedAt;
  final TenantSubscriptionProfile? subscription;

  TenantProfile toEntity() {
    return TenantProfile(
      id: id,
      name: name,
      slug: slug,
      isActive: isActive,
      currency: currency,
      standardConsultationFee: standardConsultationFee,
      contactName: contactName,
      contactEmail: contactEmail,
      contactPhone: contactPhone,
      resourceUuid: resourceUuid,
      displayId: displayId,
      deletedAt: deletedAt,
      subscription: subscription,
    );
  }
}

final class FacilityProfileDto {
  const FacilityProfileDto({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.type,
    required this.isActive,
    this.logoUrl,
    this.currency,
    this.standardConsultationFee,
    this.phone,
    this.email,
    this.addressLine1,
    this.city,
    this.country,
    this.effectiveContact,
    this.resourceUuid,
    this.displayId,
    this.deletedAt,
  });

  factory FacilityProfileDto.fromJson(JsonMap json) {
    final JsonMap extensionJson = _map(json['extension_json']);
    final JsonMap billing = _map(extensionJson['billing']);
    final String? phoneFromContacts = _primaryContactValue(json, 'PHONE');
    final String? emailFromContacts = _primaryContactValue(json, 'EMAIL');
    final JsonMap? primaryAddress = _primaryAddress(json);

    return FacilityProfileDto(
      id: _requiredString(json, 'id'),
      tenantId: _requiredString(json, 'tenant_id'),
      name: _requiredString(json, 'name'),
      type: FacilitySetupTypeX.fromApiValue(
        _optionalString(json, 'facility_type'),
      ),
      isActive: _optionalBool(json, 'is_active') ?? true,
      logoUrl: _optionalString(extensionJson, 'logo_url'),
      currency: _optionalString(extensionJson, 'currency'),
      standardConsultationFee: _optionalDecimalString(
        billing,
        'standard_consultation_fee',
      ),
      phone: _optionalString(json, 'phone') ?? phoneFromContacts,
      email: _optionalString(json, 'email') ?? emailFromContacts,
      addressLine1: _optionalString(json, 'address_line1') ??
          (primaryAddress == null
              ? null
              : _optionalString(primaryAddress, 'line1')),
      city: _optionalString(json, 'city') ??
          (primaryAddress == null
              ? null
              : _optionalString(primaryAddress, 'city')),
      country: _optionalString(json, 'country') ??
          (primaryAddress == null
              ? null
              : _optionalString(primaryAddress, 'country')),
      effectiveContact: _effectiveFacilityContact(json['effective_contact']),
      resourceUuid:
          _optionalString(json, 'resource_uuid') ?? _requiredString(json, 'id'),
      displayId: _optionalString(json, 'display_id') ??
          _optionalString(json, 'human_friendly_id'),
      deletedAt: _optionalDateTime(json, 'deleted_at'),
    );
  }

  final String id;
  final String tenantId;
  final String name;
  final FacilitySetupType type;
  final bool isActive;
  final String? logoUrl;
  final String? currency;
  final String? standardConsultationFee;
  final String? phone;
  final String? email;
  final String? addressLine1;
  final String? city;
  final String? country;
  final FacilityEffectiveContact? effectiveContact;
  final String? resourceUuid;
  final String? displayId;
  final DateTime? deletedAt;

  FacilityProfile toEntity() {
    return FacilityProfile(
      id: id,
      tenantId: tenantId,
      name: name,
      type: type,
      isActive: isActive,
      logoUrl: logoUrl,
      currency: currency,
      standardConsultationFee: standardConsultationFee,
      phone: phone,
      email: email,
      addressLine1: addressLine1,
      city: city,
      country: country,
      effectiveContact: effectiveContact,
      resourceUuid: resourceUuid,
      displayId: displayId,
      deletedAt: deletedAt,
    );
  }
}

final class DepartmentProfileDto {
  const DepartmentProfileDto({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.type,
    this.shortName,
    this.facilityId,
    required this.isActive,
    this.resourceUuid,
    this.displayId,
    this.deletedAt,
  });

  factory DepartmentProfileDto.fromJson(JsonMap json) {
    return DepartmentProfileDto(
      id: _requiredString(json, 'id'),
      tenantId: _requiredString(json, 'tenant_id'),
      name: _requiredString(json, 'name'),
      type: DepartmentSetupTypeX.fromApiValue(
        _optionalString(json, 'department_type'),
      ),
      shortName: _optionalString(json, 'short_name'),
      facilityId: _optionalString(json, 'facility_id'),
      isActive: _optionalBool(json, 'is_active') ?? true,
      resourceUuid:
          _optionalString(json, 'resource_uuid') ?? _requiredString(json, 'id'),
      displayId: _optionalString(json, 'display_id') ??
          _optionalString(json, 'human_friendly_id'),
      deletedAt: _optionalDateTime(json, 'deleted_at'),
    );
  }

  final String id;
  final String tenantId;
  final String name;
  final DepartmentSetupType type;
  final String? shortName;
  final String? facilityId;
  final bool isActive;
  final String? resourceUuid;
  final String? displayId;
  final DateTime? deletedAt;

  DepartmentProfile toEntity() {
    return DepartmentProfile(
      id: id,
      tenantId: tenantId,
      name: name,
      type: type,
      shortName: shortName,
      facilityId: facilityId,
      isActive: isActive,
      resourceUuid: resourceUuid,
      displayId: displayId,
      deletedAt: deletedAt,
    );
  }
}

final class UnitProfileDto {
  const UnitProfileDto({
    required this.id,
    required this.tenantId,
    required this.name,
    this.facilityId,
    this.departmentId,
    required this.isActive,
    this.resourceUuid,
    this.displayId,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  factory UnitProfileDto.fromJson(JsonMap json) {
    return UnitProfileDto(
      id: _requiredString(json, 'id'),
      tenantId: _requiredString(json, 'tenant_id'),
      name: _requiredString(json, 'name'),
      facilityId: _optionalString(json, 'facility_id'),
      departmentId: _optionalString(json, 'department_id'),
      isActive: _optionalBool(json, 'is_active') ?? true,
      resourceUuid:
          _optionalString(json, 'resource_uuid') ?? _requiredString(json, 'id'),
      displayId: _optionalString(json, 'display_id') ??
          _optionalString(json, 'human_friendly_id'),
      createdAt: _optionalDateTime(json, 'created_at'),
      updatedAt: _optionalDateTime(json, 'updated_at'),
      deletedAt: _optionalDateTime(json, 'deleted_at'),
    );
  }

  final String id;
  final String tenantId;
  final String name;
  final String? facilityId;
  final String? departmentId;
  final bool isActive;
  final String? resourceUuid;
  final String? displayId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  UnitProfile toEntity() {
    return UnitProfile(
      id: id,
      tenantId: tenantId,
      name: name,
      facilityId: facilityId,
      departmentId: departmentId,
      isActive: isActive,
      resourceUuid: resourceUuid,
      displayId: displayId,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
    );
  }
}

final class WardProfileDto {
  const WardProfileDto({
    required this.id,
    required this.tenantId,
    required this.facilityId,
    required this.name,
    required this.type,
    this.departmentId,
    required this.isActive,
    this.resourceUuid,
    this.displayId,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  factory WardProfileDto.fromJson(JsonMap json) {
    return WardProfileDto(
      id: _requiredString(json, 'id'),
      tenantId: _requiredString(json, 'tenant_id'),
      facilityId: _requiredString(json, 'facility_id'),
      name: _requiredString(json, 'name'),
      type: WardSetupTypeX.fromApiValue(_optionalString(json, 'ward_type')),
      departmentId: _optionalString(json, 'department_id'),
      isActive: _optionalBool(json, 'is_active') ?? true,
      resourceUuid:
          _optionalString(json, 'resource_uuid') ?? _requiredString(json, 'id'),
      displayId: _optionalString(json, 'display_id') ??
          _optionalString(json, 'human_friendly_id'),
      createdAt: _optionalDateTime(json, 'created_at'),
      updatedAt: _optionalDateTime(json, 'updated_at'),
      deletedAt: _optionalDateTime(json, 'deleted_at'),
    );
  }

  final String id;
  final String tenantId;
  final String facilityId;
  final String name;
  final WardSetupType type;
  final String? departmentId;
  final bool isActive;
  final String? resourceUuid;
  final String? displayId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  WardProfile toEntity() {
    return WardProfile(
      id: id,
      tenantId: tenantId,
      facilityId: facilityId,
      name: name,
      type: type,
      departmentId: departmentId,
      isActive: isActive,
      resourceUuid: resourceUuid,
      displayId: displayId,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
    );
  }
}

final class RoomProfileDto {
  const RoomProfileDto({
    required this.id,
    required this.tenantId,
    required this.facilityId,
    required this.name,
    this.wardId,
    this.floor,
    this.resourceUuid,
    this.displayId,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  factory RoomProfileDto.fromJson(JsonMap json) {
    return RoomProfileDto(
      id: _requiredString(json, 'id'),
      tenantId: _requiredString(json, 'tenant_id'),
      facilityId: _requiredString(json, 'facility_id'),
      name: _requiredString(json, 'name'),
      wardId: _optionalString(json, 'ward_id'),
      floor: _optionalString(json, 'floor'),
      resourceUuid:
          _optionalString(json, 'resource_uuid') ?? _requiredString(json, 'id'),
      displayId: _optionalString(json, 'display_id') ??
          _optionalString(json, 'human_friendly_id'),
      createdAt: _optionalDateTime(json, 'created_at'),
      updatedAt: _optionalDateTime(json, 'updated_at'),
      deletedAt: _optionalDateTime(json, 'deleted_at'),
    );
  }

  final String id;
  final String tenantId;
  final String facilityId;
  final String name;
  final String? wardId;
  final String? floor;
  final String? resourceUuid;
  final String? displayId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  RoomProfile toEntity() {
    return RoomProfile(
      id: id,
      tenantId: tenantId,
      facilityId: facilityId,
      name: name,
      wardId: wardId,
      floor: floor,
      resourceUuid: resourceUuid,
      displayId: displayId,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
    );
  }
}

final class BedProfileDto {
  const BedProfileDto({
    required this.id,
    required this.tenantId,
    required this.facilityId,
    required this.wardId,
    required this.label,
    required this.status,
    this.roomId,
    this.displayId,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  factory BedProfileDto.fromJson(JsonMap json) {
    return BedProfileDto(
      id: _requiredString(json, 'id'),
      tenantId: _requiredString(json, 'tenant_id'),
      facilityId: _requiredString(json, 'facility_id'),
      wardId: _requiredString(json, 'ward_id'),
      label: _requiredString(json, 'label'),
      status: BedSetupStatusX.fromApiValue(_optionalString(json, 'status')),
      roomId: _optionalString(json, 'room_id'),
      displayId: _optionalString(json, 'display_id') ??
          _optionalString(json, 'human_friendly_id'),
      createdAt: _optionalDateTime(json, 'created_at'),
      updatedAt: _optionalDateTime(json, 'updated_at'),
      deletedAt: _optionalDateTime(json, 'deleted_at'),
    );
  }

  final String id;
  final String tenantId;
  final String facilityId;
  final String wardId;
  final String label;
  final BedSetupStatus status;
  final String? roomId;
  final String? displayId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  BedProfile toEntity() {
    return BedProfile(
      id: id,
      tenantId: tenantId,
      facilityId: facilityId,
      wardId: wardId,
      label: label,
      status: status,
      roomId: roomId,
      displayId: displayId,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
    );
  }
}

final class ContactDto {
  const ContactDto({required this.id, required this.type, required this.value});

  factory ContactDto.fromJson(JsonMap json) {
    return ContactDto(
      id: _requiredString(json, 'id'),
      type: _requiredString(json, 'contact_type'),
      value: _requiredString(json, 'value'),
    );
  }

  final String id;
  final String type;
  final String value;
}

final class AddressDto {
  const AddressDto({
    required this.id,
    required this.line1,
    this.city,
    this.country,
  });

  factory AddressDto.fromJson(JsonMap json) {
    return AddressDto(
      id: _requiredString(json, 'id'),
      line1: _requiredString(json, 'line1'),
      city: _optionalString(json, 'city'),
      country: _optionalString(json, 'country'),
    );
  }

  final String id;
  final String line1;
  final String? city;
  final String? country;
}

List<T> decodeList<T>(Object? data, T Function(JsonMap json) decoder) {
  if (data is! Iterable<Object?>) {
    throw const FormatException('Expected API list data.');
  }

  return data.whereType<JsonMap>().map(decoder).toList(growable: false);
}

String _requiredString(JsonMap json, String key) {
  final String? value = _optionalString(json, key);
  if (value == null) {
    throw FormatException('Expected $key.');
  }

  return value;
}

String? _optionalString(JsonMap json, String key) {
  final Object? value = json[key];
  if (value is! String || value.trim().isEmpty) {
    return null;
  }

  return value.trim();
}

String? _primaryContactValue(JsonMap json, String contactType) {
  final Object? contacts = json['contacts'];
  if (contacts is! Iterable<Object?>) {
    return null;
  }
  final String normalizedType = contactType.trim().toUpperCase();
  for (final Object? entry in contacts) {
    if (entry is! JsonMap) {
      continue;
    }
    final String? type = _optionalString(entry, 'contact_type')?.toUpperCase();
    if (type != normalizedType) {
      continue;
    }
    final String? value = _optionalString(entry, 'value');
    if (value != null) {
      return value;
    }
  }
  return null;
}

JsonMap? _primaryAddress(JsonMap json) {
  final Object? addresses = json['addresses'];
  if (addresses is! Iterable<Object?>) {
    return null;
  }
  for (final Object? entry in addresses) {
    if (entry is JsonMap) {
      return entry;
    }
  }
  return null;
}

bool? _optionalBool(JsonMap json, String key) {
  final Object? value = json[key];
  return value is bool ? value : null;
}

DateTime? _optionalDateTime(JsonMap json, String key) {
  final Object? value = json[key];
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  final String text = value.toString().trim();
  if (text.isEmpty) {
    return null;
  }
  return DateTime.tryParse(text);
}

/// Decodes the `current_subscription` payload the tenants API returns for the
/// live subscription (absent/null when the tenant has none).
TenantSubscriptionProfile? _tenantSubscription(Object? value) {
  if (value is! JsonMap) {
    return null;
  }
  final TenantSubscriptionProfile subscription = TenantSubscriptionProfile(
    planName: _optionalString(value, 'plan_name'),
    planCode: _optionalString(value, 'plan_code'),
    status: _optionalString(value, 'status'),
    startDate: _optionalDateTime(value, 'start_date'),
    endDate: _optionalDateTime(value, 'end_date'),
  );
  final bool isEmpty =
      subscription.packageLabel == null &&
      subscription.status == null &&
      subscription.startDate == null &&
      subscription.endDate == null;
  return isEmpty ? null : subscription;
}

JsonMap _map(Object? value) {
  return value is JsonMap ? value : const <String, Object?>{};
}

String? _optionalDecimalString(JsonMap json, String key) {
  final Object? value = json[key];
  if (value == null) {
    return null;
  }
  final String text = value.toString().trim();
  if (text.isEmpty) {
    return null;
  }
  return text;
}

final class TenantSubscriptionSummaryDto {
  const TenantSubscriptionSummaryDto({
    this.planLabel,
    this.status,
    this.activeModulesCount = 0,
    this.subscriptionId,
  });

  factory TenantSubscriptionSummaryDto.fromJson(JsonMap json) {
    return TenantSubscriptionSummaryDto(
      planLabel: _optionalString(json, 'plan_label'),
      status: _optionalString(json, 'status'),
      activeModulesCount: _optionalInt(json, 'active_modules_count') ?? 0,
      subscriptionId: _optionalString(json, 'subscription_id'),
    );
  }

  final String? planLabel;
  final String? status;
  final int activeModulesCount;
  final String? subscriptionId;

  TenantSubscriptionSummary toEntity() {
    return TenantSubscriptionSummary(
      planLabel: planLabel,
      status: status,
      activeModulesCount: activeModulesCount,
      subscriptionId: subscriptionId,
    );
  }
}

final class FacilitySetupPermissionsDto {
  const FacilitySetupPermissionsDto({
    required this.canManageTenant,
    required this.canManageFacility,
    required this.canManageHrSetup,
    required this.canViewSubscriptions,
    required this.isHrSetupOnly,
  });

  factory FacilitySetupPermissionsDto.fromJson(JsonMap json) {
    return FacilitySetupPermissionsDto(
      canManageTenant: _optionalBool(json, 'can_manage_tenant') ?? false,
      canManageFacility: _optionalBool(json, 'can_manage_facility') ?? false,
      canManageHrSetup: _optionalBool(json, 'can_manage_hr_setup') ?? false,
      canViewSubscriptions:
          _optionalBool(json, 'can_view_subscriptions') ?? false,
      isHrSetupOnly: _optionalBool(json, 'is_hr_setup_only') ?? false,
    );
  }

  final bool canManageTenant;
  final bool canManageFacility;
  final bool canManageHrSetup;
  final bool canViewSubscriptions;
  final bool isHrSetupOnly;

  FacilitySetupPermissions toEntity() {
    return FacilitySetupPermissions(
      canManageTenant: canManageTenant,
      canManageFacility: canManageFacility,
      canManageHrSetup: canManageHrSetup,
      canViewSubscriptions: canViewSubscriptions,
      isHrSetupOnly: isHrSetupOnly,
    );
  }
}

final class FacilitySetupWorkspaceDto {
  const FacilitySetupWorkspaceDto({required this.snapshot});

  factory FacilitySetupWorkspaceDto.fromResponse(Object? data) {
    return ApiResponseEnvelope.decodeData<FacilitySetupWorkspaceDto>(
      data,
      decoder: (Object? payload) {
        final JsonMap json = payload is JsonMap
            ? payload
            : _requireWorkspaceMap(payload);
        return FacilitySetupWorkspaceDto.fromJson(json);
      },
    );
  }

  factory FacilitySetupWorkspaceDto.fromJson(JsonMap json) {
    final JsonMap contactAddressJson = _map(json['contact_address']);
    final JsonMap permissionsJson = _map(json['permissions']);
    final Object? subscriptionSummaryJson = json['subscription_summary'];

    return FacilitySetupWorkspaceDto(
      snapshot: FacilitySetupSnapshot(
        tenant: json['tenant'] is JsonMap
            ? TenantProfileDto.fromJson(json['tenant'] as JsonMap).toEntity()
            : null,
        facility: json['facility'] is JsonMap
            ? FacilityProfileDto.fromJson(
                json['facility'] as JsonMap,
              ).toEntity()
            : null,
        facilities: _decodeOptionalList<FacilityProfileDto>(
          json['facilities'],
          FacilityProfileDto.fromJson,
        ).map((dto) => dto.toEntity()).toList(growable: false),
        contactAddress: FacilityContactAddress(
          phone: _optionalString(contactAddressJson, 'phone'),
          email: _optionalString(contactAddressJson, 'email'),
          addressLine1: _optionalString(contactAddressJson, 'address_line1'),
          city: _optionalString(contactAddressJson, 'city'),
          country: _optionalString(contactAddressJson, 'country'),
        ),
        effectiveContact: _effectiveFacilityContact(json['effective_contact']),
        departments: _decodeOptionalList<DepartmentProfileDto>(
          json['departments'],
          DepartmentProfileDto.fromJson,
        ).map((dto) => dto.toEntity()).toList(growable: false),
        units: _decodeOptionalList<UnitProfileDto>(
          json['units'],
          UnitProfileDto.fromJson,
        ).map((dto) => dto.toEntity()).toList(growable: false),
        wards: _decodeOptionalList<WardProfileDto>(
          json['wards'],
          WardProfileDto.fromJson,
        ).map((dto) => dto.toEntity()).toList(growable: false),
        rooms: _decodeOptionalList<RoomProfileDto>(
          json['rooms'],
          RoomProfileDto.fromJson,
        ).map((dto) => dto.toEntity()).toList(growable: false),
        beds: _decodeOptionalList<BedProfileDto>(
          json['beds'],
          BedProfileDto.fromJson,
        ).map((dto) => dto.toEntity()).toList(growable: false),
        subscriptionSummary: subscriptionSummaryJson is JsonMap
            ? TenantSubscriptionSummaryDto.fromJson(
                subscriptionSummaryJson,
              ).toEntity()
            : null,
        permissions: permissionsJson.isEmpty
            ? const FacilitySetupPermissions()
            : FacilitySetupPermissionsDto.fromJson(permissionsJson).toEntity(),
      ),
    );
  }

  final FacilitySetupSnapshot snapshot;

  FacilitySetupSnapshot toEntity() => snapshot;
}

/// `effective_contact`: facility phone/email with tenant fallback, or null
/// when the server did not resolve one.
FacilityEffectiveContact? _effectiveFacilityContact(Object? value) {
  if (value is! JsonMap) {
    return null;
  }
  return FacilityEffectiveContact(
    phone: _optionalString(value, 'phone'),
    email: _optionalString(value, 'email'),
    phoneSource: FacilityContactSource.fromApi(value['phone_source']),
    emailSource: FacilityContactSource.fromApi(value['email_source']),
  );
}

JsonMap _requireWorkspaceMap(Object? value) {
  if (value is! JsonMap) {
    throw const FormatException('Expected tenant facility workspace data.');
  }

  return value;
}

int? _optionalInt(JsonMap json, String key) {
  final Object? value = json[key];
  if (value is int) {
    return value;
  }

  if (value is String) {
    return int.tryParse(value.trim());
  }

  return null;
}

List<T> _decodeOptionalList<T>(Object? data, T Function(JsonMap json) decoder) {
  if (data == null) {
    return <T>[];
  }

  return decodeList<T>(data, decoder);
}
