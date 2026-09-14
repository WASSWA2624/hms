import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/network/api_client.dart';
import 'package:hosspi_hms/core/network/api_endpoints.dart';
import 'package:hosspi_hms/core/network/network_providers.dart';
import 'package:hosspi_hms/features/access_admin/data/dtos/access_admin_dtos.dart';
import 'package:hosspi_hms/features/access_admin/domain/entities/access_admin_entities.dart';
import 'package:hosspi_hms/features/access_admin/domain/repositories/access_admin_repository.dart';
import 'package:hosspi_hms/shared/data/data.dart';

final accessAdminRepositoryProvider = Provider<AccessAdminRepository>((ref) {
  return AccessAdminRepositoryImpl(apiClient: ref.watch(apiClientProvider));
});

final class _ReferenceDataCacheEntry {
  const _ReferenceDataCacheEntry({
    required this.lookups,
    required this.cachedAt,
  });

  final AccessAdminLookups lookups;
  final DateTime cachedAt;
}

final class AccessAdminRepositoryImpl implements AccessAdminRepository {
  AccessAdminRepositoryImpl({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;
  final Map<String, _ReferenceDataCacheEntry> _referenceDataCache =
      <String, _ReferenceDataCacheEntry>{};
  static const Duration _referenceDataTtl = Duration(minutes: 2);

  String _referenceDataCacheKey({
    String? tenantId,
    String? facilityId,
    List<String> include = const <String>[],
  }) {
    final List<String> includeKey = List<String>.from(include)..sort();
    return <String>[
      tenantId ?? '',
      facilityId ?? '',
      includeKey.join(','),
    ].join('|');
  }

  @override
  Future<Result<AccessAdminWorkspaceData>> getWorkspace(
    AccessAdminWorkspaceQuery query,
  ) {
    final AppPageRequest request = query.pageRequest;
    return _apiClient.get<AccessAdminWorkspaceData>(
      ApiEndpoints.nested(
        HmsApiResource.accessAdminWorkspace,
        'workspace',
        const <String>[],
      ),
      queryParameters: _withoutEmpty(<String, Object?>{
        'page': request.pageIndex + 1,
        'limit': request.pageSize,
        'panel': query.panel.serverValue,
        'resource': query.resource.serverValue,
        'search': query.search,
        'tenantId': query.allTenants ? null : query.tenantId,
        'facilityId': query.allFacilities ? null : query.facilityId,
        'id': query.recordId,
        'status': query.status,
        'roleScope': query.roleScope,
        'userId': query.userId,
        'roleId': query.roleId,
        'include_deleted': query.includeDeleted ? 'true' : null,
        'lean': query.lean ? 'true' : null,
        'skipLookups': query.skipLookups ? 'true' : null,
        'allTenants': query.allTenants ? 'true' : null,
        'allFacilities': query.allFacilities ? 'true' : null,
      }),
      decoder: (Object? data) {
        return AccessAdminWorkspaceDto.fromResponse(data, query).toEntity();
      },
    );
  }

  @override
  Future<Result<AccessAdminLookups>> getReferenceData({
    String? tenantId,
    String? facilityId,
    List<String> include = const <String>[],
    bool forceRefresh = false,
  }) async {
    final String cacheKey = _referenceDataCacheKey(
      tenantId: tenantId,
      facilityId: facilityId,
      include: include,
    );
    if (!forceRefresh) {
      final _ReferenceDataCacheEntry? cached = _referenceDataCache[cacheKey];
      if (cached != null &&
          DateTime.now().difference(cached.cachedAt) <= _referenceDataTtl) {
        return Result<AccessAdminLookups>.success(cached.lookups);
      }
    }

    final Result<AccessAdminLookups> result = await _apiClient
        .get<AccessAdminLookups>(
          ApiEndpoints.nested(
            HmsApiResource.accessAdminWorkspace,
            'reference-data',
            const <String>[],
          ),
          queryParameters: _withoutEmpty(<String, Object?>{
            'tenantId': tenantId,
            'facilityId': facilityId,
            'include': include.isEmpty ? null : include.join(','),
          }),
          decoder: (Object? data) {
            return AccessAdminLookupsDto.fromResponse(data).toEntity();
          },
        );

    result.when(
      success: (AccessAdminLookups lookups) {
        _referenceDataCache[cacheKey] = _ReferenceDataCacheEntry(
          lookups: lookups,
          cachedAt: DateTime.now(),
        );
      },
      failure: (_) {},
    );
    return result;
  }

  @override
  void invalidateReferenceDataCache() {
    _referenceDataCache.clear();
  }

  Future<Result<T>> _afterAccessMutation<T>(
    Future<Result<T>> Function() action,
  ) async {
    final Result<T> result = await action();
    result.when(
      success: (_) => invalidateReferenceDataCache(),
      failure: (_) {},
    );
    return result;
  }

  @override
  Future<Result<AccessAdminLegacyRouteResolution>> resolveLegacyRoute(
    AccessAdminResource resource,
    String identifier,
  ) {
    return _apiClient.get<AccessAdminLegacyRouteResolution>(
      ApiEndpoints.nested(
        HmsApiResource.accessAdminWorkspace,
        'resolve-legacy',
        <String>[resource.serverValue, identifier],
      ),
      decoder: (Object? data) {
        return AccessAdminLegacyRouteResolutionDto.fromResponse(
          data,
        ).toEntity();
      },
    );
  }

  @override
  Future<Result<AccessAdminUserDetail>> getUserDetail(
    String userId, {
    String? tenantId,
    String? facilityId,
  }) {
    return _apiClient.get<AccessAdminUserDetail>(
      ApiEndpoints.nested(
        HmsApiResource.accessAdminWorkspace,
        'users',
        <String>[userId, 'detail'],
      ),
      queryParameters: _withoutEmpty(<String, Object?>{
        'tenantId': tenantId,
        'facilityId': facilityId,
      }),
      decoder: (Object? data) {
        return AccessAdminUserDetailDto.fromResponse(data).toEntity();
      },
    );
  }

  @override
  Future<Result<String>> createUser(AccessAdminUserDraft draft) {
    return _afterAccessMutation(() async {
      final Result<String?> createResult = await _apiClient.post<String?>(
        ApiEndpoints.collection(HmsApiResource.users),
        data: _withoutEmpty(<String, Object?>{
          'tenant_id': draft.tenantId,
          'facility_id': draft.facilityId,
          'first_name': draft.firstName,
          'last_name': draft.lastName,
          'email': draft.email,
          'phone': draft.phone,
          'position_title': draft.positionTitle,
          'password': draft.password,
          'status': draft.status,
          'permission_ids': draft.permissionIds,
          'role_ids': draft.roleIds,
          // Access admin creates staff accounts: the staff profile is written in
          // the same transaction as the user and its roles.
          'staff_profile': <String, Object?>{'position': draft.positionTitle},
          if (draft.confirmSimilar) 'confirm_similar': true,
        }),
        decoder: (Object? responseData) => _extractRecordId(
          responseData is Map<String, dynamic>
              ? responseData['data'] ?? responseData
              : responseData,
        ),
      );

      return createResult.when(
        success: (String? userId) {
          if (userId == null || userId.isEmpty) {
            return const Result<String>.failure(AppFailure.unexpected());
          }
          return Result<String>.success(userId);
        },
        failure: (AppFailure failure) => Result<String>.failure(failure),
      );
    });
  }

  @override
  Future<Result<void>> updateUser(String userId, AccessAdminUserDraft draft) {
    return _afterAccessMutation(
      () => _apiClient.put<void>(
        ApiEndpoints.byId(HmsApiResource.users, userId),
        data: <String, Object?>{
          ..._withoutEmpty(<String, Object?>{
            'first_name': draft.firstName,
            'last_name': draft.lastName,
            'email': draft.email,
            'phone': draft.phone,
            'position_title': draft.positionTitle,
            'status': draft.status,
            'permission_ids': draft.permissionIds,
            if (draft.confirmSimilar) 'confirm_similar': true,
          }),
          // Sent even when null so choosing every facility clears it; the API
          // ignores an unchanged facility. Credentials are never part of an
          // edit: they change through setUserPassword or resetUserCredentials.
          'facility_id': draft.facilityId,
        },
        decoder: (_) {},
      ),
    );
  }

  @override
  Future<Result<void>> syncUserDirectPermissions({
    required String userId,
    required List<String> permissionIds,
  }) {
    return _afterAccessMutation(
      () => _apiClient.put<void>(
        ApiEndpoints.byId(HmsApiResource.users, userId),
        data: <String, Object?>{'permission_ids': permissionIds},
        decoder: (_) {},
      ),
    );
  }

  @override
  Future<Result<void>> deleteUser(String userId) {
    return _afterAccessMutation(
      () => _apiClient.delete<void>(
        ApiEndpoints.byId(HmsApiResource.users, userId),
        decoder: (_) {},
      ),
    );
  }

  @override
  Future<Result<void>> restoreUser(String userId) {
    return _afterAccessMutation(
      () => _apiClient.post<void>(
        ApiEndpoints.nested(HmsApiResource.users, userId, const <String>[
          'restore',
        ]),
        decoder: (_) {},
      ),
    );
  }

  @override
  Future<Result<void>> permanentDeleteUser(String userId) {
    return _afterAccessMutation(
      () => _apiClient.delete<void>(
        ApiEndpoints.nested(HmsApiResource.users, userId, const <String>[
          'permanent',
        ]),
        decoder: (_) {},
      ),
    );
  }

  @override
  Future<Result<void>> setUserStatus(String userId, String status) {
    return _afterAccessMutation(
      () => _apiClient.put<void>(
        ApiEndpoints.byId(HmsApiResource.users, userId),
        data: <String, Object?>{'status': status},
        decoder: (_) {},
      ),
    );
  }

  @override
  Future<Result<void>> setUserPassword(String userId, String password) {
    return _apiClient.put<void>(
      ApiEndpoints.nested(HmsApiResource.users, userId, const <String>[
        'password',
      ]),
      data: <String, Object?>{'password': password},
      decoder: (_) {},
    );
  }

  @override
  Future<Result<AccessAdminCredentialResetResult>> resetUserCredentials(
    String userId,
  ) {
    return _apiClient.post<AccessAdminCredentialResetResult>(
      ApiEndpoints.nested(HmsApiResource.users, userId, const <String>[
        'reset-credentials',
      ]),
      decoder: (Object? data) {
        return AccessAdminCredentialResetResultDto.fromResponse(
          data,
        ).toEntity();
      },
    );
  }

  @override
  Future<Result<AccessAdminItem>> createRole(AccessAdminRoleDraft draft) {
    return _afterAccessMutation(
      () => _apiClient.post<AccessAdminItem>(
        ApiEndpoints.collection(HmsApiResource.roles),
        data: <String, Object?>{
          ..._withoutEmpty(<String, Object?>{
            'name': draft.name,
            'display_name': draft.displayName,
            'description': draft.description,
            'permission_ids': draft.permissionIds,
            'scope': draft.scope,
            if (draft.confirmSimilar) 'confirm_similar': true,
          }),
          // Explicit nulls required for platform-scoped creates.
          'tenant_id': draft.tenantId,
          'facility_id': draft.facilityId,
        },
        decoder: (Object? data) {
          final Map<String, dynamic> payload = _asStringKeyedMap(
            _asStringKeyedMap(data)['data'] ?? data,
          );
          return AccessAdminItemDto.fromJson(
            payload,
            AccessAdminResource.roles,
          ).toEntity();
        },
      ),
    );
  }

  @override
  Future<Result<void>> updateRole(String roleId, AccessAdminRoleDraft draft) {
    final Map<String, Object?> payload = <String, Object?>{
      ..._withoutEmpty(<String, Object?>{
        'name': draft.name,
        'description': draft.description,
        'scope': draft.scope,
      }),
      'display_name': draft.displayName,
      // Explicit nulls required when moving a role to platform scope.
      'tenant_id': draft.tenantId,
      'facility_id': draft.facilityId,
      if (draft.syncPermissions) 'permission_ids': draft.permissionIds,
      if (draft.confirmSimilar) 'confirm_similar': true,
    };
    return _afterAccessMutation(
      () => _apiClient.put<void>(
        ApiEndpoints.byId(HmsApiResource.roles, roleId),
        data: payload,
        decoder: (_) {},
      ),
    );
  }

  @override
  Future<Result<void>> deleteRole(String roleId) {
    return _afterAccessMutation(
      () => _apiClient.delete<void>(
        ApiEndpoints.byId(HmsApiResource.roles, roleId),
        decoder: (_) {},
      ),
    );
  }

  @override
  Future<Result<void>> restoreRole(String roleId) {
    return _afterAccessMutation(
      () => _apiClient.post<void>(
        ApiEndpoints.nested(HmsApiResource.roles, roleId, const <String>[
          'restore',
        ]),
        decoder: (_) {},
      ),
    );
  }

  @override
  Future<Result<void>> permanentDeleteRole(String roleId) {
    return _afterAccessMutation(
      () => _apiClient.delete<void>(
        ApiEndpoints.nested(HmsApiResource.roles, roleId, const <String>[
          'permanent',
        ]),
        decoder: (_) {},
      ),
    );
  }

  @override
  Future<Result<List<AccessAdminRolePermissionAssignment>>> listRolePermissions(
    String roleId,
  ) async {
    final List<AccessAdminRolePermissionAssignment> all =
        <AccessAdminRolePermissionAssignment>[];
    var pageIndex = 0;
    const int pageSize = AppPageRequest.maxPageSize;

    while (true) {
      final Result<List<AccessAdminRolePermissionAssignment>> result =
          await _fetchRolePermissionsPage(
            roleId: roleId,
            pageIndex: pageIndex,
            pageSize: pageSize,
          );
      final AppFailure? failure = result.when(
        success: (_) => null,
        failure: (AppFailure value) => value,
      );
      if (failure != null) {
        return Result<List<AccessAdminRolePermissionAssignment>>.failure(
          failure,
        );
      }

      final List<AccessAdminRolePermissionAssignment> page = result.when(
        success: (List<AccessAdminRolePermissionAssignment> value) => value,
        failure: (_) => throw StateError('unreachable'),
      );
      all.addAll(page);
      if (page.length < pageSize || pageIndex >= 4) {
        break;
      }
      pageIndex += 1;
    }

    final Set<String> seen = <String>{};
    final List<AccessAdminRolePermissionAssignment> unique =
        <AccessAdminRolePermissionAssignment>[];
    for (final AccessAdminRolePermissionAssignment item in all) {
      final String permissionId = (item.permissionId ?? '').trim().toLowerCase();
      final String code = (item.permissionName ?? '').trim().toLowerCase();
      if (permissionId.isNotEmpty && seen.contains('id:$permissionId')) {
        continue;
      }
      if (code.isNotEmpty && seen.contains('code:$code')) {
        continue;
      }
      if (permissionId.isEmpty && code.isEmpty) {
        if (!seen.add('row:${item.id}')) {
          continue;
        }
      } else {
        if (permissionId.isNotEmpty) {
          seen.add('id:$permissionId');
        }
        if (code.isNotEmpty) {
          seen.add('code:$code');
        }
      }
      unique.add(item);
    }

    return Result<List<AccessAdminRolePermissionAssignment>>.success(unique);
  }

  Future<Result<List<AccessAdminRolePermissionAssignment>>>
  _fetchRolePermissionsPage({
    required String roleId,
    required int pageIndex,
    required int pageSize,
  }) {
    return _apiClient.get<List<AccessAdminRolePermissionAssignment>>(
      ApiEndpoints.collection(HmsApiResource.rolePermissions),
      queryParameters: <String, Object?>{
        'role_id': roleId,
        'page': pageIndex + 1,
        'limit': pageSize,
      },
      decoder: (Object? data) {
        final Map<String, dynamic> response = _asStringKeyedMap(data);
        final List<dynamic> rows = response['data'] is List<dynamic>
            ? response['data']! as List<dynamic>
            : const <dynamic>[];
        return rows
            .map(_asStringKeyedMap)
            .where((Map<String, dynamic> row) => row.isNotEmpty)
            .map((Map<String, dynamic> row) {
              final Map<String, dynamic> permission = _asStringKeyedMap(
                row['permission'],
              );
              final String assignmentId =
                  _string(row['id']) ??
                  _string(row['human_friendly_id']) ??
                  _string(row['display_id']) ??
                  '';
              // Prefer UUID so HFID collisions cannot duplicate or mis-sync.
              final String? permissionId =
                  _string(permission['id']) ??
                  _string(row['permission_id']) ??
                  _string(permission['human_friendly_id']) ??
                  _string(permission['display_id']);
              final String? permissionName =
                  _string(permission['name']) ??
                  _string(row['permission_name']);
              return AccessAdminRolePermissionAssignment(
                id: assignmentId,
                permissionId: permissionId,
                permissionName: permissionName,
              );
            })
            .where(
              (AccessAdminRolePermissionAssignment item) => item.id.isNotEmpty,
            )
            .toList(growable: false);
      },
    );
  }

  @override
  Future<Result<void>> syncRolePermissions({
    required String roleId,
    required List<String> permissionIds,
  }) async {
    // One PUT replaces N sequential role-permission POSTs/DELETEs and keeps
    // backend assignability + soft-delete sync authoritative.
    final Result<void> result = await _afterAccessMutation(
      () => _apiClient.put<void>(
        ApiEndpoints.byId(HmsApiResource.roles, roleId),
        data: <String, Object?>{
          'permission_ids': permissionIds,
        },
        decoder: (_) {},
      ),
    );
    return result;
  }

  @override
  Future<Result<void>> assignUserRole(AccessAdminUserRoleDraft draft) {
    return _afterAccessMutation(
      () => _apiClient.post<void>(
        ApiEndpoints.collection(HmsApiResource.userRoles),
        data: _withoutEmpty(<String, Object?>{
          'user_id': draft.userId,
          'role_id': draft.roleId,
          'tenant_id': draft.tenantId,
          'facility_id': draft.facilityId,
        }),
        decoder: (_) {},
      ),
    );
  }

  @override
  Future<Result<void>> revokeUserRole(String userRoleId) {
    return _afterAccessMutation(
      () => _apiClient.delete<void>(
        ApiEndpoints.byId(HmsApiResource.userRoles, userRoleId),
        decoder: (_) {},
      ),
    );
  }

  @override
  Future<Result<List<AccessAdminUserRoleAssignment>>> listUserRoles({
    required String userId,
    String? tenantId,
  }) async {
    final List<AccessAdminUserRoleAssignment> all =
        <AccessAdminUserRoleAssignment>[];
    var pageIndex = 0;
    const int pageSize = AppPageRequest.maxPageSize;

    while (true) {
      final Result<List<AccessAdminUserRoleAssignment>> result =
          await _fetchUserRolesPage(
            userId: userId,
            tenantId: tenantId,
            pageIndex: pageIndex,
            pageSize: pageSize,
          );
      final AppFailure? failure = result.when(
        success: (_) => null,
        failure: (AppFailure value) => value,
      );
      if (failure != null) {
        return Result<List<AccessAdminUserRoleAssignment>>.failure(failure);
      }

      final List<AccessAdminUserRoleAssignment> page = result.when(
        success: (List<AccessAdminUserRoleAssignment> value) => value,
        failure: (_) => throw StateError('unreachable'),
      );
      all.addAll(page);
      if (page.length < pageSize || pageIndex >= 4) {
        break;
      }
      pageIndex += 1;
    }

    return Result<List<AccessAdminUserRoleAssignment>>.success(all);
  }

  Future<Result<List<AccessAdminUserRoleAssignment>>> _fetchUserRolesPage({
    required String userId,
    String? tenantId,
    required int pageIndex,
    required int pageSize,
  }) {
    return _apiClient.get<List<AccessAdminUserRoleAssignment>>(
      ApiEndpoints.collection(HmsApiResource.userRoles),
      queryParameters: _withoutEmpty(<String, Object?>{
        'user_id': userId,
        'tenant_id': tenantId,
        'page': pageIndex + 1,
        'limit': pageSize,
      }),
      decoder: (Object? data) {
        final Map<String, Object?> response = data is Map<String, Object?>
            ? data
            : <String, Object?>{};
        final List<Object?> rows = response['data'] is List<Object?>
            ? response['data']! as List<Object?>
            : const <Object?>[];
        return rows
            .whereType<Map<String, Object?>>()
            .map((Map<String, Object?> json) {
              final Map<String, Object?> role =
                  json['role'] is Map<String, Object?>
                  ? json['role']! as Map<String, Object?>
                  : <String, Object?>{};
              final String assignmentId =
                  _string(json['id']) ??
                  _string(json['backend_identifier']) ??
                  _string(json['display_id']) ??
                  '';
              final String? roleId =
                  _nullableString(json['role_id']) ??
                  _nullableString(role['id']) ??
                  _nullableString(role['display_id']);
              return AccessAdminUserRoleAssignment(
                id: assignmentId,
                roleId: roleId,
              );
            })
            .where((AccessAdminUserRoleAssignment item) => item.id.isNotEmpty)
            .toList(growable: false);
      },
    );
  }

  @override
  Future<Result<void>> syncUserRoles({
    required String userId,
    required String tenantId,
    required List<String> roleIds,
    String? facilityId,
  }) async {
    final Result<List<AccessAdminUserRoleAssignment>> currentResult =
        await listUserRoles(userId: userId, tenantId: tenantId);
    final List<AccessAdminUserRoleAssignment> currentRoles = currentResult.when(
      success: (List<AccessAdminUserRoleAssignment> value) => value,
      failure: (_) => const <AccessAdminUserRoleAssignment>[],
    );
    final Set<String> desiredRoleIds = roleIds.toSet();
    final Set<String> currentRoleIds = currentRoles
        .map((AccessAdminUserRoleAssignment role) => role.roleId)
        .whereType<String>()
        .toSet();

    AppFailure? lastFailure;
    final List<Future<Result<void>>> mutations = <Future<Result<void>>>[];

    for (final AccessAdminUserRoleAssignment assignment in currentRoles) {
      final String? roleId = assignment.roleId;
      if (roleId == null || desiredRoleIds.contains(roleId)) {
        continue;
      }
      mutations.add(revokeUserRole(assignment.id));
    }

    for (final String roleId in desiredRoleIds) {
      if (currentRoleIds.contains(roleId)) {
        continue;
      }
      mutations.add(
        assignUserRole(
          AccessAdminUserRoleDraft(
            userId: userId,
            roleId: roleId,
            tenantId: tenantId,
            facilityId: facilityId,
          ),
        ),
      );
    }

    final List<Result<void>> results = await Future.wait(mutations);
    for (final Result<void> result in results) {
      if (result case ResultFailure<void>(:final failure)) {
        lastFailure ??= failure;
      }
    }

    if (lastFailure != null) {
      return Result<void>.failure(lastFailure);
    }
    invalidateReferenceDataCache();
    return const Result<void>.success(null);
  }

  String? _nullableString(Object? value) {
    if (value == null) {
      return null;
    }
    final String normalized = value.toString().trim();
    return normalized.isEmpty ? null : normalized;
  }

  String? _string(Object? value) => _nullableString(value);

  Map<String, dynamic> _asStringKeyedMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (Object? key, Object? entry) =>
            MapEntry<String, dynamic>(key.toString(), entry),
      );
    }
    return <String, dynamic>{};
  }

  @override
  Future<Result<void>> assignRolePermission(
    AccessAdminRolePermissionDraft draft,
  ) {
    return _afterAccessMutation(
      () => _apiClient.post<void>(
        ApiEndpoints.collection(HmsApiResource.rolePermissions),
        data: <String, Object?>{
          'role_id': draft.roleId,
          'permission_id': draft.permissionId,
        },
        decoder: (_) {},
      ),
    );
  }

  @override
  Future<Result<void>> revokeRolePermission(String rolePermissionId) {
    return _afterAccessMutation(
      () => _apiClient.delete<void>(
        ApiEndpoints.byId(HmsApiResource.rolePermissions, rolePermissionId),
        decoder: (_) {},
      ),
    );
  }

  @override
  Future<Result<AccessAdminDemoResetResult>> resetDemoUserPassword(
    String userId,
  ) {
    return _apiClient.post<AccessAdminDemoResetResult>(
      ApiEndpoints.nested(
        HmsApiResource.accessAdminWorkspace,
        'demo-users',
        <String>[userId, 'reset-password'],
      ),
      decoder: (Object? data) {
        return AccessAdminDemoResetResultDto.fromResponse(data).toEntity();
      },
    );
  }

  @override
  Future<Result<void>> approveRegistration(String userId) {
    return _apiClient.post<void>(
      ApiEndpoints.nested(
        HmsApiResource.accessAdminWorkspace,
        'registrations',
        <String>[userId, 'approve'],
      ),
      decoder: (_) {},
    );
  }

  @override
  Future<Result<void>> rejectRegistration(String userId) {
    return _apiClient.post<void>(
      ApiEndpoints.nested(
        HmsApiResource.accessAdminWorkspace,
        'registrations',
        <String>[userId, 'reject'],
      ),
      decoder: (_) {},
    );
  }

  @override
  Future<Result<void>> activatePaymentRequest(String requestId) {
    return _apiClient.post<void>(
      ApiEndpoints.nested(
        HmsApiResource.accessAdminWorkspace,
        'payment-requests',
        <String>[requestId, 'activate'],
      ),
      decoder: (_) {},
    );
  }

  @override
  Future<Result<void>> rejectPaymentRequest(String requestId, String reason) {
    return _apiClient.post<void>(
      ApiEndpoints.nested(
        HmsApiResource.accessAdminWorkspace,
        'payment-requests',
        <String>[requestId, 'reject'],
      ),
      data: <String, Object?>{'reason': reason},
      decoder: (_) {},
    );
  }

  Map<String, Object> _withoutEmpty(Map<String, Object?> values) {
    final Map<String, Object> normalized = <String, Object>{};
    values.forEach((String key, Object? value) {
      if (value == null) return;
      if (value is String && value.trim().isEmpty) return;
      if (value is List && value.isEmpty) return;
      normalized[key] = value;
    });
    return normalized;
  }

  String? _extractRecordId(Object? payload) {
    if (payload is! Map<String, dynamic>) {
      return null;
    }
    final Object? id = payload['id'] ?? payload['human_friendly_id'];
    if (id == null) {
      return null;
    }
    final String normalized = id.toString().trim();
    return normalized.isEmpty ? null : normalized;
  }
}
