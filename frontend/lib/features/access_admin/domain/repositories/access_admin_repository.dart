import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/features/access_admin/domain/entities/access_admin_entities.dart';

abstract interface class AccessAdminRepository {
  Future<Result<AccessAdminWorkspaceData>> getWorkspace(
    AccessAdminWorkspaceQuery query,
  );

  Future<Result<AccessAdminLookups>> getReferenceData({
    String? tenantId,
    String? facilityId,
    List<String> include = const <String>[],
    bool forceRefresh = false,
  });

  /// Drops cached role/permission lookups so pickers see fresh CRUD results.
  void invalidateReferenceDataCache();

  Future<Result<AccessAdminLegacyRouteResolution>> resolveLegacyRoute(
    AccessAdminResource resource,
    String identifier,
  );

  Future<Result<AccessAdminUserDetail>> getUserDetail(
    String userId, {
    String? tenantId,
    String? facilityId,
  });

  Future<Result<String>> createUser(AccessAdminUserDraft draft);

  Future<Result<void>> updateUser(String userId, AccessAdminUserDraft draft);

  Future<Result<void>> syncUserDirectPermissions({
    required String userId,
    required List<String> permissionIds,
  });

  Future<Result<void>> deleteUser(String userId);

  Future<Result<void>> restoreUser(String userId);

  /// Permanently deletes a soft-deleted user that has no recorded history.
  Future<Result<void>> permanentDeleteUser(String userId);

  Future<Result<void>> setUserStatus(String userId, String status);

  /// Sets a new password directly. Every session for the account ends and any
  /// reset link already emailed stops working.
  Future<Result<void>> setUserPassword(String userId, String password);

  /// Emails the user a single-use link to choose a new password.
  Future<Result<AccessAdminCredentialResetResult>> resetUserCredentials(
    String userId,
  );

  Future<Result<List<AccessAdminUserRoleAssignment>>> listUserRoles({
    required String userId,
    String? tenantId,
  });

  Future<Result<void>> syncUserRoles({
    required String userId,
    required String tenantId,
    required List<String> roleIds,
    String? facilityId,
  });

  Future<Result<AccessAdminItem>> createRole(AccessAdminRoleDraft draft);

  Future<Result<void>> updateRole(String roleId, AccessAdminRoleDraft draft);

  Future<Result<void>> deleteRole(String roleId);

  Future<Result<void>> restoreRole(String roleId);

  Future<Result<void>> permanentDeleteRole(String roleId);

  Future<Result<List<AccessAdminRolePermissionAssignment>>> listRolePermissions(
    String roleId,
  );

  Future<Result<void>> syncRolePermissions({
    required String roleId,
    required List<String> permissionIds,
  });

  Future<Result<void>> assignUserRole(AccessAdminUserRoleDraft draft);

  Future<Result<void>> revokeUserRole(String userRoleId);

  Future<Result<void>> assignRolePermission(
    AccessAdminRolePermissionDraft draft,
  );

  Future<Result<void>> revokeRolePermission(String rolePermissionId);

  Future<Result<AccessAdminDemoResetResult>> resetDemoUserPassword(
    String userId,
  );

  Future<Result<void>> approveRegistration(String userId);

  Future<Result<void>> rejectRegistration(String userId);

  Future<Result<void>> activatePaymentRequest(String requestId);

  Future<Result<void>> rejectPaymentRequest(String requestId, String reason);
}
