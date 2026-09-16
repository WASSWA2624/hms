import 'package:hosspi_hms/core/permissions/access_policy.dart';
import 'package:hosspi_hms/core/permissions/app_permission.dart';

const Object _facilitySetupSnapshotUnset = Object();

abstract final class TenantFacilityPermissions {
  static const AppPermission tenantAdmin = AppPermissions.tenantAdmin;
  static const AppPermission facilityAdmin = AppPermissions.facilityAdmin;
  static const AppPermission platformAdmin = AppPermissions.platformAdmin;

  static final Set<AppPermission> setupAccess = <AppPermission>{
    tenantAdmin,
    facilityAdmin,
    platformAdmin,
  };
}

enum FacilitySetupType { hospital, clinic, lab, pharmacy, other }

enum DepartmentSetupType {
  clinical,
  administrative,
  support,
  diagnostics,
  other,
}

enum WardSetupType { general, icu, maternity, pediatric, surgical, other }

enum BedSetupStatus {
  available,
  occupied,
  reserved,
  cleaning,
  maintenance,
  blocked,
  outOfService,
}

/// Live subscription a tenant is currently on (`ACTIVE`/`TRIAL`/`PAST_DUE`).
/// Null on [TenantProfile] when the tenant has no live subscription.
final class TenantSubscriptionProfile {
  const TenantSubscriptionProfile({
    this.planName,
    this.planCode,
    this.status,
    this.startDate,
    this.endDate,
  });

  final String? planName;
  final String? planCode;
  final String? status;
  final DateTime? startDate;
  final DateTime? endDate;

  /// Package label, falling back to the plan code when the name is missing.
  String? get packageLabel {
    final String? name = planName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    final String? code = planCode?.trim();
    return code != null && code.isNotEmpty ? code : null;
  }

  @override
  bool operator ==(Object other) {
    return other is TenantSubscriptionProfile &&
        other.planName == planName &&
        other.planCode == planCode &&
        other.status == status &&
        other.startDate == startDate &&
        other.endDate == endDate;
  }

  @override
  int get hashCode =>
      Object.hash(planName, planCode, status, startDate, endDate);
}

final class TenantProfile {
  const TenantProfile({
    required this.id,
    required this.name,
    this.slug,
    this.isActive = true,
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

  bool get isDeleted => deletedAt != null;

  String get mutationId =>
      resourceUuid != null && resourceUuid!.isNotEmpty ? resourceUuid! : id;

  TenantProfile copyWith({
    String? id,
    String? name,
    String? slug,
    bool? isActive,
    String? currency,
    String? standardConsultationFee,
    String? contactName,
    String? contactEmail,
    String? contactPhone,
    String? resourceUuid,
    String? displayId,
    DateTime? deletedAt,
    TenantSubscriptionProfile? subscription,
    bool clearSubscription = false,
    bool clearDeletedAt = false,
    bool clearCurrency = false,
    bool clearStandardConsultationFee = false,
    bool clearContactName = false,
    bool clearContactEmail = false,
    bool clearContactPhone = false,
  }) {
    return TenantProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      isActive: isActive ?? this.isActive,
      currency: clearCurrency ? null : (currency ?? this.currency),
      standardConsultationFee: clearStandardConsultationFee
          ? null
          : (standardConsultationFee ?? this.standardConsultationFee),
      contactName: clearContactName ? null : (contactName ?? this.contactName),
      contactEmail: clearContactEmail
          ? null
          : (contactEmail ?? this.contactEmail),
      contactPhone: clearContactPhone
          ? null
          : (contactPhone ?? this.contactPhone),
      resourceUuid: resourceUuid ?? this.resourceUuid,
      displayId: displayId ?? this.displayId,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      subscription: clearSubscription
          ? null
          : (subscription ?? this.subscription),
    );
  }
}

/// Where an effective facility contact value came from.
enum FacilityContactSource {
  facility,
  tenant,
  none;

  static FacilityContactSource fromApi(Object? value) {
    return switch (value?.toString().trim().toUpperCase()) {
      'FACILITY' => FacilityContactSource.facility,
      'TENANT' => FacilityContactSource.tenant,
      _ => FacilityContactSource.none,
    };
  }
}

/// A facility's phone and email with tenant fallback.
///
/// A value the facility lacks is taken from the tenant contact. It is only ever
/// shown, never saved as the facility's own, so forms keep editing own values.
final class FacilityEffectiveContact {
  const FacilityEffectiveContact({
    this.phone,
    this.email,
    this.phoneSource = FacilityContactSource.none,
    this.emailSource = FacilityContactSource.none,
  });

  /// Resolves each field independently: the facility's own value wins, then a
  /// value the server already reported as inherited, then the tenant contact.
  factory FacilityEffectiveContact.resolve({
    String? ownPhone,
    String? ownEmail,
    FacilityEffectiveContact? inherited,
    String? tenantPhone,
    String? tenantEmail,
  }) {
    (String?, FacilityContactSource) field(
      String? own,
      String? inheritedValue,
      FacilityContactSource inheritedSource,
      String? tenantValue,
    ) {
      final String? ownText = _nonBlank(own);
      if (ownText != null) {
        return (ownText, FacilityContactSource.facility);
      }
      final String? inheritedText = _nonBlank(inheritedValue);
      if (inheritedText != null &&
          inheritedSource == FacilityContactSource.tenant) {
        return (inheritedText, FacilityContactSource.tenant);
      }
      final String? tenantText = _nonBlank(tenantValue);
      if (tenantText != null) {
        return (tenantText, FacilityContactSource.tenant);
      }
      return (null, FacilityContactSource.none);
    }

    final (String? phone, FacilityContactSource phoneSource) = field(
      ownPhone,
      inherited?.phone,
      inherited?.phoneSource ?? FacilityContactSource.none,
      tenantPhone,
    );
    final (String? email, FacilityContactSource emailSource) = field(
      ownEmail,
      inherited?.email,
      inherited?.emailSource ?? FacilityContactSource.none,
      tenantEmail,
    );
    return FacilityEffectiveContact(
      phone: phone,
      email: email,
      phoneSource: phoneSource,
      emailSource: emailSource,
    );
  }

  final String? phone;
  final String? email;
  final FacilityContactSource phoneSource;
  final FacilityContactSource emailSource;

  bool get isPhoneInherited =>
      phoneSource == FacilityContactSource.tenant && _nonBlank(phone) != null;

  bool get isEmailInherited =>
      emailSource == FacilityContactSource.tenant && _nonBlank(email) != null;

  bool get hasPhone => _nonBlank(phone) != null;

  static String? _nonBlank(String? value) {
    final String? trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

final class FacilityProfile {
  const FacilityProfile({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.type,
    this.isActive = true,
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

  /// Phone/email with tenant fallback, when the server resolved it. [phone] and
  /// [email] stay the facility's own values.
  final FacilityEffectiveContact? effectiveContact;
  final String? resourceUuid;
  final String? displayId;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  String get mutationId =>
      resourceUuid != null && resourceUuid!.isNotEmpty ? resourceUuid! : id;

  /// Contact to display: own values first, then inherited tenant values.
  FacilityEffectiveContact get displayContact {
    return FacilityEffectiveContact.resolve(
      ownPhone: phone,
      ownEmail: email,
      inherited: effectiveContact,
    );
  }

  FacilityProfile copyWith({
    String? id,
    String? tenantId,
    String? name,
    FacilitySetupType? type,
    bool? isActive,
    String? logoUrl,
    String? currency,
    String? standardConsultationFee,
    String? phone,
    String? email,
    String? addressLine1,
    String? city,
    String? country,
    FacilityEffectiveContact? effectiveContact,
    String? resourceUuid,
    String? displayId,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    bool clearLogoUrl = false,
    bool clearCurrency = false,
    bool clearStandardConsultationFee = false,
  }) {
    return FacilityProfile(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      type: type ?? this.type,
      isActive: isActive ?? this.isActive,
      logoUrl: clearLogoUrl ? null : (logoUrl ?? this.logoUrl),
      currency: clearCurrency ? null : (currency ?? this.currency),
      standardConsultationFee: clearStandardConsultationFee
          ? null
          : (standardConsultationFee ?? this.standardConsultationFee),
      phone: phone ?? this.phone,
      email: email ?? this.email,
      addressLine1: addressLine1 ?? this.addressLine1,
      city: city ?? this.city,
      country: country ?? this.country,
      effectiveContact: effectiveContact ?? this.effectiveContact,
      resourceUuid: resourceUuid ?? this.resourceUuid,
      displayId: displayId ?? this.displayId,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }
}

final class DepartmentProfile {
  const DepartmentProfile({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.type,
    this.shortName,
    this.facilityId,
    this.isActive = true,
    this.resourceUuid,
    this.displayId,
    this.deletedAt,
  });

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

  bool get isDeleted => deletedAt != null;

  String get mutationId =>
      resourceUuid != null && resourceUuid!.isNotEmpty ? resourceUuid! : id;

  DepartmentProfile copyWith({
    String? id,
    String? tenantId,
    String? name,
    DepartmentSetupType? type,
    String? shortName,
    String? facilityId,
    bool? isActive,
    String? resourceUuid,
    String? displayId,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return DepartmentProfile(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      type: type ?? this.type,
      shortName: shortName ?? this.shortName,
      facilityId: facilityId ?? this.facilityId,
      isActive: isActive ?? this.isActive,
      resourceUuid: resourceUuid ?? this.resourceUuid,
      displayId: displayId ?? this.displayId,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }
}

final class UnitProfile {
  const UnitProfile({
    required this.id,
    required this.tenantId,
    required this.name,
    this.facilityId,
    this.departmentId,
    this.isActive = true,
    this.resourceUuid,
    this.displayId,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

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

  bool get isDeleted => deletedAt != null;

  String get mutationId =>
      resourceUuid != null && resourceUuid!.isNotEmpty ? resourceUuid! : id;

  UnitProfile copyWith({
    String? id,
    String? tenantId,
    String? name,
    String? facilityId,
    String? departmentId,
    bool? isActive,
    String? resourceUuid,
    String? displayId,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return UnitProfile(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      facilityId: facilityId ?? this.facilityId,
      departmentId: departmentId ?? this.departmentId,
      isActive: isActive ?? this.isActive,
      resourceUuid: resourceUuid ?? this.resourceUuid,
      displayId: displayId ?? this.displayId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }
}

final class WardProfile {
  const WardProfile({
    required this.id,
    required this.tenantId,
    required this.facilityId,
    required this.name,
    required this.type,
    this.departmentId,
    this.isActive = true,
    this.resourceUuid,
    this.displayId,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

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

  bool get isDeleted => deletedAt != null;

  String get mutationId =>
      resourceUuid != null && resourceUuid!.isNotEmpty ? resourceUuid! : id;

  WardProfile copyWith({
    String? id,
    String? tenantId,
    String? facilityId,
    String? name,
    WardSetupType? type,
    String? departmentId,
    bool? isActive,
    String? resourceUuid,
    String? displayId,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return WardProfile(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      facilityId: facilityId ?? this.facilityId,
      name: name ?? this.name,
      type: type ?? this.type,
      departmentId: departmentId ?? this.departmentId,
      isActive: isActive ?? this.isActive,
      resourceUuid: resourceUuid ?? this.resourceUuid,
      displayId: displayId ?? this.displayId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }
}

final class RoomProfile {
  const RoomProfile({
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

  bool get isDeleted => deletedAt != null;

  String get mutationId =>
      resourceUuid != null && resourceUuid!.isNotEmpty ? resourceUuid! : id;

  RoomProfile copyWith({
    String? id,
    String? tenantId,
    String? facilityId,
    String? name,
    String? wardId,
    String? floor,
    String? resourceUuid,
    String? displayId,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return RoomProfile(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      facilityId: facilityId ?? this.facilityId,
      name: name ?? this.name,
      wardId: wardId ?? this.wardId,
      floor: floor ?? this.floor,
      resourceUuid: resourceUuid ?? this.resourceUuid,
      displayId: displayId ?? this.displayId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }
}

final class BedProfile {
  const BedProfile({
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

  bool get isDeleted => deletedAt != null;

  BedProfile copyWith({
    String? id,
    String? tenantId,
    String? facilityId,
    String? wardId,
    String? label,
    BedSetupStatus? status,
    String? roomId,
    String? displayId,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return BedProfile(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      facilityId: facilityId ?? this.facilityId,
      wardId: wardId ?? this.wardId,
      label: label ?? this.label,
      status: status ?? this.status,
      roomId: roomId ?? this.roomId,
      displayId: displayId ?? this.displayId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }
}

final class FacilityContactAddress {
  const FacilityContactAddress({
    this.phone,
    this.email,
    this.addressLine1,
    this.city,
    this.country,
  });

  final String? phone;
  final String? email;
  final String? addressLine1;
  final String? city;
  final String? country;
}

final class TenantSubscriptionSummary {
  const TenantSubscriptionSummary({
    this.planLabel,
    this.status,
    this.activeModulesCount = 0,
    this.subscriptionId,
  });

  final String? planLabel;
  final String? status;
  final int activeModulesCount;
  final String? subscriptionId;

  bool get hasActivePlan => planLabel != null && planLabel!.trim().isNotEmpty;
}

final class FacilitySetupPermissions {
  const FacilitySetupPermissions({
    this.canManageTenant = false,
    this.canManageFacility = false,
    this.canManageHrSetup = false,
    this.canViewSubscriptions = false,
    this.isHrSetupOnly = false,
  });

  final bool canManageTenant;
  final bool canManageFacility;
  final bool canManageHrSetup;
  final bool canViewSubscriptions;
  final bool isHrSetupOnly;

  bool get canEditStructure => canManageFacility;
}

final class FacilitySetupSnapshot {
  const FacilitySetupSnapshot({
    this.tenant,
    this.facility,
    this.facilities = const <FacilityProfile>[],
    this.contactAddress = const FacilityContactAddress(),
    this.effectiveContact,
    this.departments = const <DepartmentProfile>[],
    this.units = const <UnitProfile>[],
    this.wards = const <WardProfile>[],
    this.rooms = const <RoomProfile>[],
    this.beds = const <BedProfile>[],
    this.subscriptionSummary,
    this.permissions = const FacilitySetupPermissions(),
  });

  final TenantProfile? tenant;
  final FacilityProfile? facility;
  final List<FacilityProfile> facilities;
  /// The facility's own contact and address; what setup forms edit.
  final FacilityContactAddress contactAddress;

  /// Phone/email with tenant fallback as the server resolved it, when known.
  final FacilityEffectiveContact? effectiveContact;
  final List<DepartmentProfile> departments;
  final List<UnitProfile> units;
  final List<WardProfile> wards;
  final List<RoomProfile> rooms;
  final List<BedProfile> beds;
  final TenantSubscriptionSummary? subscriptionSummary;
  final FacilitySetupPermissions permissions;

  FacilitySetupSnapshot copyWith({
    Object? tenant = _facilitySetupSnapshotUnset,
    Object? facility = _facilitySetupSnapshotUnset,
    List<FacilityProfile>? facilities,
    FacilityContactAddress? contactAddress,
    Object? effectiveContact = _facilitySetupSnapshotUnset,
    List<DepartmentProfile>? departments,
    List<UnitProfile>? units,
    List<WardProfile>? wards,
    List<RoomProfile>? rooms,
    List<BedProfile>? beds,
    Object? subscriptionSummary = _facilitySetupSnapshotUnset,
    FacilitySetupPermissions? permissions,
  }) {
    return FacilitySetupSnapshot(
      tenant: identical(tenant, _facilitySetupSnapshotUnset)
          ? this.tenant
          : tenant as TenantProfile?,
      facility: identical(facility, _facilitySetupSnapshotUnset)
          ? this.facility
          : facility as FacilityProfile?,
      facilities: facilities ?? this.facilities,
      contactAddress: contactAddress ?? this.contactAddress,
      effectiveContact:
          identical(effectiveContact, _facilitySetupSnapshotUnset)
          ? this.effectiveContact
          : effectiveContact as FacilityEffectiveContact?,
      departments: departments ?? this.departments,
      units: units ?? this.units,
      wards: wards ?? this.wards,
      rooms: rooms ?? this.rooms,
      beds: beds ?? this.beds,
      subscriptionSummary:
          identical(subscriptionSummary, _facilitySetupSnapshotUnset)
          ? this.subscriptionSummary
          : subscriptionSummary as TenantSubscriptionSummary?,
      permissions: permissions ?? this.permissions,
    );
  }

  static const int setupChecklistTotal = 7;

  bool get hasTenant => tenant != null;
  bool get hasFacility => facility != null;
  bool get hasDepartments => departments.isNotEmpty;
  bool get hasDepartmentsAndUnits => departments.isNotEmpty && units.isNotEmpty;
  int get roomsCount => rooms.length;
  int get wardsCount => wards.length;
  int get bedsCount => beds.length;
  /// Phone/email to display and print for [facility]: its own values, else the
  /// tenant contact. Own values always win, so an unsaved local edit is never
  /// masked by an older inherited value.
  FacilityEffectiveContact get resolvedEffectiveContact {
    if (facility == null) {
      return const FacilityEffectiveContact();
    }
    return FacilityEffectiveContact.resolve(
      ownPhone: contactAddress.phone,
      ownEmail: contactAddress.email,
      inherited: effectiveContact ?? facility?.effectiveContact,
      tenantPhone: tenant?.contactPhone,
      tenantEmail: tenant?.contactEmail,
    );
  }

  bool get hasFacilityIdentity {
    final FacilityProfile? currentFacility = facility;
    if (currentFacility == null) {
      return false;
    }

    // A phone inherited from the tenant is enough to reach the facility.
    return currentFacility.name.trim().isNotEmpty &&
        resolvedEffectiveContact.hasPhone;
  }


  bool get hasUnitsConfigured => units.isNotEmpty;

  bool get hasWardsConfigured => wards.isNotEmpty;

  bool get hasRoomsConfigured => rooms.isNotEmpty;

  bool get hasBedsConfigured => beds.isNotEmpty;

  int get completedChecklistItems {
    return <bool>[
      hasTenant,
      hasFacilityIdentity,
      hasDepartments,
      hasUnitsConfigured || hasDepartments,
      hasWardsConfigured || hasRoomsConfigured || hasBedsConfigured,
      hasRoomsConfigured || hasBedsConfigured,
      hasBedsConfigured,
    ].where((bool completed) => completed).length;
  }
}

extension FacilitySetupTypeX on FacilitySetupType {
  String get apiValue {
    return switch (this) {
      FacilitySetupType.hospital => 'HOSPITAL',
      FacilitySetupType.clinic => 'CLINIC',
      FacilitySetupType.lab => 'LAB',
      FacilitySetupType.pharmacy => 'PHARMACY',
      FacilitySetupType.other => 'OTHER',
    };
  }

  static FacilitySetupType fromApiValue(String? value) {
    return switch (value?.trim().toUpperCase()) {
      'CLINIC' => FacilitySetupType.clinic,
      'LAB' => FacilitySetupType.lab,
      'PHARMACY' => FacilitySetupType.pharmacy,
      'OTHER' => FacilitySetupType.other,
      _ => FacilitySetupType.hospital,
    };
  }
}

extension DepartmentSetupTypeX on DepartmentSetupType {
  String get apiValue {
    return switch (this) {
      DepartmentSetupType.clinical => 'CLINICAL',
      DepartmentSetupType.administrative => 'ADMINISTRATIVE',
      DepartmentSetupType.support => 'SUPPORT',
      DepartmentSetupType.diagnostics => 'DIAGNOSTICS',
      DepartmentSetupType.other => 'OTHER',
    };
  }

  static DepartmentSetupType fromApiValue(String? value) {
    return switch (value?.trim().toUpperCase()) {
      'ADMINISTRATIVE' => DepartmentSetupType.administrative,
      'SUPPORT' => DepartmentSetupType.support,
      'DIAGNOSTICS' => DepartmentSetupType.diagnostics,
      'OTHER' => DepartmentSetupType.other,
      _ => DepartmentSetupType.clinical,
    };
  }
}

extension WardSetupTypeX on WardSetupType {
  String get apiValue {
    return switch (this) {
      WardSetupType.general => 'GENERAL',
      WardSetupType.icu => 'ICU',
      WardSetupType.maternity => 'MATERNITY',
      WardSetupType.pediatric => 'PEDIATRIC',
      WardSetupType.surgical => 'SURGICAL',
      WardSetupType.other => 'OTHER',
    };
  }

  static WardSetupType fromApiValue(String? value) {
    return switch (value?.trim().toUpperCase()) {
      'ICU' => WardSetupType.icu,
      'MATERNITY' => WardSetupType.maternity,
      'PEDIATRIC' => WardSetupType.pediatric,
      'SURGICAL' => WardSetupType.surgical,
      'OTHER' => WardSetupType.other,
      _ => WardSetupType.general,
    };
  }
}

extension BedSetupStatusX on BedSetupStatus {
  String get apiValue {
    return switch (this) {
      BedSetupStatus.available => 'AVAILABLE',
      BedSetupStatus.occupied => 'OCCUPIED',
      BedSetupStatus.reserved => 'RESERVED',
      BedSetupStatus.cleaning => 'CLEANING',
      BedSetupStatus.maintenance => 'MAINTENANCE',
      BedSetupStatus.blocked => 'BLOCKED',
      BedSetupStatus.outOfService => 'OUT_OF_SERVICE',
    };
  }

  static BedSetupStatus fromApiValue(String? value) {
    return switch (value?.trim().toUpperCase()) {
      'OCCUPIED' => BedSetupStatus.occupied,
      'RESERVED' => BedSetupStatus.reserved,
      'CLEANING' => BedSetupStatus.cleaning,
      'MAINTENANCE' => BedSetupStatus.maintenance,
      'BLOCKED' => BedSetupStatus.blocked,
      'OUT_OF_SERVICE' => BedSetupStatus.outOfService,
      _ => BedSetupStatus.available,
    };
  }

  bool get isAssignable => this == BedSetupStatus.available;

  bool get isNonAssignableOperational =>
      this == BedSetupStatus.cleaning ||
      this == BedSetupStatus.maintenance ||
      this == BedSetupStatus.blocked ||
      this == BedSetupStatus.outOfService;
}
