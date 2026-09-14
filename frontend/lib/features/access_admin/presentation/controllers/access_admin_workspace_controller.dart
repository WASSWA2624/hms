import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/realtime/realtime_event_groups.dart';
import 'package:hosspi_hms/core/realtime/realtime_events.dart';
import 'package:hosspi_hms/core/realtime/realtime_message.dart';
import 'package:hosspi_hms/core/realtime/realtime_refresh.dart';
import 'package:hosspi_hms/core/security/auth_session.dart';
import 'package:hosspi_hms/core/security/session_controller.dart';
import 'package:hosspi_hms/core/security/session_isolation.dart';
import 'package:hosspi_hms/core/workspace/realtime_delta.dart';
import 'package:hosspi_hms/core/workspace/realtime_sync_action.dart';
import 'package:hosspi_hms/core/workspace/workspace_event_refresh_plan.dart';
import 'package:hosspi_hms/core/workspace/workspace_fast_sync.dart';
import 'package:hosspi_hms/core/workspace/workspace_session_guard.dart';
import 'package:hosspi_hms/features/access_admin/data/repositories/access_admin_repository_impl.dart';
import 'package:hosspi_hms/features/access_admin/domain/entities/access_admin_entities.dart';
import 'package:hosspi_hms/features/access_admin/domain/repositories/access_admin_repository.dart';
import 'package:hosspi_hms/features/access_admin/presentation/access_admin_access.dart';
import 'package:hosspi_hms/features/access_admin/presentation/controllers/access_admin_realtime_delta_applier.dart';
import 'package:hosspi_hms/core/permissions/permission_providers.dart';
import 'package:hosspi_hms/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:hosspi_hms/shared/data/data.dart';

final accessAdminWorkspaceControllerProvider =
    AsyncNotifierProvider<
      AccessAdminWorkspaceController,
      Result<AccessAdminWorkspaceState>
    >(AccessAdminWorkspaceController.new);

final class AccessAdminWorkspaceController
    extends AsyncNotifier<Result<AccessAdminWorkspaceState>> {
  final WorkspacePendingRefresh _pendingRefresh = WorkspacePendingRefresh();

  AccessAdminRepository get _repository =>
      ref.read(accessAdminRepositoryProvider);

  @override
  Future<Result<AccessAdminWorkspaceState>> build() {
    watchSessionEpoch(ref);
    listenForRealtimeRefresh(
      ref: ref,
      events: RealtimeEventGroups.accessAdmin,
      includeCrudMutations: true,
      shouldDefer: () => _currentState?.isSaving ?? false,
      onRefresh: _syncFromRealtime,
    );
    return runWorkspaceInitialLoad(ref, _loadInitialState);
  }

  Future<void> _syncFromRealtime(RealtimeMessage message) async {
    if (message.event == RealtimeEvents.moduleEntitlementUpdated ||
        message.event == RealtimeEvents.roleUpdated ||
        message.event == RealtimeEvents.roleDeleted ||
        message.event == RealtimeEvents.userUpdated) {
      await _refreshSession();
    }

    await handleWorkspaceListRealtimeSync<AccessAdminWorkspaceState>(
      message: message,
      profile: WorkspaceRefreshProfile.accessAdmin,
      currentState: _currentState,
      isDeferred: _currentState?.isSaving ?? false,
      pendingRefresh: _pendingRefresh,
      applyDelta: AccessAdminRealtimeDeltaApplier.apply,
      emit: _emit,
      syncHttp: ({required WorkspaceRefreshPlan plan}) async {
        await _refreshWorkspace(
          preferredSelectedId: _currentState?.selectedItem?.id,
        );
      },
    );
  }

  Future<AppFailure?> applyRouteQuery(AccessAdminWorkspaceQuery query) async {
    final AccessAdminWorkspaceQuery resolved = await _resolveRouteQuery(query);
    return _loadQuery(
      resolved.copyWith(pageRequest: resolved.pageRequest.first()),
      preserveSelectedId: resolved.recordId,
    );
  }

  Future<AppFailure?> refresh() async {
    final AccessAdminWorkspaceState? current = _currentState;
    if (current == null) {
      state = const AsyncLoading<Result<AccessAdminWorkspaceState>>();
      final Result<AccessAdminWorkspaceState> result =
          await _loadInitialState();
      state = AsyncData<Result<AccessAdminWorkspaceState>>(result);
      return _failureOrNull(result);
    }
    _emit(current.copyWith(isRefreshing: true, clearLastFailure: true));
    return _refreshWorkspace(preferredSelectedId: current.selectedItem?.id);
  }

  Future<AppFailure?> applySearch(String value) {
    final AccessAdminWorkspaceState? current = _currentState;
    if (current == null) return refresh();
    return _loadQuery(
      current.query.copyWith(
        search: value.trim(),
        pageRequest: current.query.pageRequest.first(),
      ),
    );
  }

  Future<AppFailure?> applyPanel(AccessAdminPanel panel) {
    final AccessAdminPanel resolved = panel == AccessAdminPanel.overview
        ? AccessAdminPanel.directory
        : panel;
    final AccessAdminResource resource = _defaultResourceForPanel(resolved);
    return applyResource(resource, panel: resolved);
  }

  Future<AppFailure?> applyResource(
    AccessAdminResource resource, {
    AccessAdminPanel? panel,
  }) {
    final AccessAdminWorkspaceState? current = _currentState;
    if (current == null) return refresh();
    return _loadQuery(
      current.query.copyWith(
        panel: panel ?? resource.defaultPanel,
        resource: resource,
        pageRequest: current.query.pageRequest.first(),
      ),
      clearSelectedItem: true,
    );
  }

  Future<AppFailure?> applyStatusFilter(String? status) {
    final AccessAdminWorkspaceState? current = _currentState;
    if (current == null) return refresh();
    return _loadQuery(
      current.query.copyWith(
        status: status,
        pageRequest: current.query.pageRequest.first(),
      ),
      clearSelectedItem: true,
    );
  }

  Future<AppFailure?> applyRoleScopeFilter(String? roleScope) {
    final AccessAdminWorkspaceState? current = _currentState;
    if (current == null) return refresh();
    return _loadQuery(
      current.query.copyWith(
        roleScope: roleScope,
        pageRequest: current.query.pageRequest.first(),
      ),
      clearSelectedItem: true,
    );
  }

  Future<AppFailure?> applyContext({String? tenantId, String? facilityId}) {
    final AccessAdminWorkspaceState? current = _currentState;
    if (current == null) return refresh();
    return _loadQuery(
      current.query.copyWith(
        tenantId: tenantId,
        facilityId: facilityId,
        pageRequest: current.query.pageRequest.first(),
      ),
      clearSelectedItem: true,
    );
  }

  Future<AppFailure?> changePage(AppPageRequest request) {
    final AccessAdminWorkspaceState? current = _currentState;
    if (current == null) return refresh();
    return _loadQuery(current.query.copyWith(pageRequest: request));
  }

  void selectItem(AccessAdminItem item) {
    final AccessAdminWorkspaceState? current = _currentState;
    if (current == null) return;
    _emit(
      current.copyWith(
        selectedItem: item,
        clearLastFailure: true,
        selectedUserDetail: null,
      ),
    );
  }

  Future<AppFailure?> loadUserDetail(AccessAdminItem item) async {
    final AccessAdminWorkspaceState? current = _currentState;
    if (current == null) return refresh();

    _emit(
      current.copyWith(
        selectedItem: item,
        isSaving: true,
        clearLastFailure: true,
        selectedUserDetail: null,
      ),
    );

    final Result<AccessAdminUserDetail> result = await _repository
        .getUserDetail(
          item.effectiveDisplayId,
          tenantId: current.query.tenantId,
          facilityId: current.query.facilityId,
        );

    return result.when(
      success: (AccessAdminUserDetail detail) {
        final AccessAdminWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(latest.copyWith(selectedUserDetail: detail, isSaving: false));
        }
        return null;
      },
      failure: (AppFailure failure) {
        final AccessAdminWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(latest.copyWith(isSaving: false, lastFailure: failure));
        }
        return failure;
      },
    );
  }

  Future<AppFailure?> setUserStatus(AccessAdminItem item, String status) {
    if (!canMutateAccessAdminDemoAccount(item)) {
      return Future<AppFailure?>.value(AppFailure.validation());
    }
    return _submitAction(
      () => _repository.setUserStatus(item.mutationId, status),
      refreshSession: true,
    );
  }

  /// Sets a new password directly. Nothing the list shows changes, so it does
  /// not refresh.
  Future<Result<void>> setUserPassword(String userId, String password) {
    return _repository.setUserPassword(userId, password);
  }

  /// Issues a single-use credential reset, then refreshes the list so it
  /// reflects the account as the API now reports it.
  Future<Result<AccessAdminCredentialResetResult>> resetUserCredentials(
    AccessAdminItem item,
  ) async {
    if (!canMutateAccessAdminDemoAccount(item)) {
      return Result<AccessAdminCredentialResetResult>.failure(
        AppFailure.validation(),
      );
    }
    final AccessAdminWorkspaceState? current = _currentState;
    if (current != null) {
      _emit(current.copyWith(isSaving: true, clearLastFailure: true));
    }

    final Result<AccessAdminCredentialResetResult> result = await _repository
        .resetUserCredentials(item.mutationId);
    final bool succeeded = result.when(
      success: (_) => true,
      failure: (_) => false,
    );
    if (succeeded) {
      await _refreshWorkspace(preferredSelectedId: current?.selectedItem?.id);
    }
    // The confirm dialog shows a failure inline; keep the page banner clear.
    final AccessAdminWorkspaceState? latest = _currentState;
    if (latest != null) {
      _emit(latest.copyWith(isSaving: false, isRefreshing: false));
    }
    return result;
  }

  Future<AppFailure?> deleteUser(AccessAdminItem item) {
    if (!canMutateAccessAdminDemoAccount(item)) {
      return Future<AppFailure?>.value(AppFailure.validation());
    }
    return _submitAction(
      () => _repository.deleteUser(item.mutationId),
      removeItemId: item.id,
      refreshSession: true,
    );
  }

  Future<AppFailure?> createUser(AccessAdminUserDraft draft) {
    return _mutateWithLocalUpsert(
      () => _repository.createUser(draft),
      onSuccess: (String id) => _upsertCreatedUser(id, draft),
    );
  }

  Future<AppFailure?> createUserWithRoles(
    AccessAdminUserDraft draft,
    List<String> roleIds,
  ) {
    return _submitAction(() async {
      final Result<String> createResult = await _repository.createUser(draft);
      if (createResult case ResultFailure<String>(:final failure)) {
        return Result<void>.failure(failure);
      }
      final String userId = createResult.when(
        success: (String value) => value,
        failure: (_) => '',
      );
      _upsertCreatedUser(userId, draft);
      if (roleIds.isEmpty) {
        return const Result<void>.success(null);
      }
      return _repository.syncUserRoles(
        userId: userId,
        tenantId: draft.tenantId,
        facilityId: draft.facilityId,
        roleIds: roleIds,
      );
    }, refreshSession: true);
  }

  /// Create a user and return the created (or refreshed) item so callers can
  /// open User Details without a list flash. Mirrors [createRole].
  Future<Result<AccessAdminItem>> createUserReviewed(
    AccessAdminUserDraft draft,
  ) async {
    final AccessAdminWorkspaceState? current = _currentState;
    if (current != null) {
      _emit(current.copyWith(isSaving: true, clearLastFailure: true));
    }

    final Result<String> createResult = await _repository.createUser(draft);
    return createResult.when(
      success: (String id) async {
        _upsertCreatedUser(id, draft);
        await _refreshWorkspace(preferredSelectedId: id);
        final AccessAdminItem created = _createdUserItem(id, draft);
        final AccessAdminWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(latest.copyWith(isSaving: false, isRefreshing: false));
        }
        await _flushPendingRefresh();
        _scheduleSessionRehydrate();
        return Result<AccessAdminItem>.success(created);
      },
      failure: (AppFailure failure) async {
        final AccessAdminWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(
            latest.copyWith(
              isSaving: false,
              isRefreshing: false,
              lastFailure: failure,
            ),
          );
        }
        return Result<AccessAdminItem>.failure(failure);
      },
    );
  }

  /// Resolve the created user from the refreshed page when present, else build
  /// a minimal item from the draft (details view reloads from the id anyway).
  AccessAdminItem _createdUserItem(String id, AccessAdminUserDraft draft) {
    final AccessAdminWorkspaceState? current = _currentState;
    if (current != null &&
        current.query.resource == AccessAdminResource.users) {
      for (final AccessAdminItem item in current.data.page.items) {
        if (item.id == id ||
            item.mutationId == id ||
            item.effectiveDisplayId == id) {
          return item;
        }
      }
    }
    return AccessAdminItem(
      id: id,
      resource: AccessAdminResource.users,
      displayId: id,
      title: <String?>[draft.firstName, draft.lastName]
              .whereType<String>()
              .map((String value) => value.trim())
              .where((String value) => value.isNotEmpty)
              .join(' ')
              .trim()
              .isEmpty
          ? draft.email
          : <String?>[draft.firstName, draft.lastName]
                .whereType<String>()
                .map((String value) => value.trim())
                .where((String value) => value.isNotEmpty)
                .join(' '),
      email: draft.email,
      phone: draft.phone,
      positionTitle: draft.positionTitle,
      firstName: draft.firstName,
      lastName: draft.lastName,
      profileName: <String?>[draft.firstName, draft.lastName]
          .whereType<String>()
          .map((String value) => value.trim())
          .where((String value) => value.isNotEmpty)
          .join(' '),
      status: draft.status,
      tenantId: draft.tenantId,
      facilityId: draft.facilityId,
    );
  }

  Future<Result<AccessAdminItem>> updateUserReviewed(
    String userId,
    AccessAdminUserDraft draft,
  ) async {
    final AccessAdminWorkspaceState? current = _currentState;
    if (current != null) {
      _emit(current.copyWith(isSaving: true, clearLastFailure: true));
    }

    final Result<void> updateResult = await _repository.updateUser(
      userId,
      draft,
    );
    return updateResult.when(
      success: (_) async {
        await _refreshWorkspace(preferredSelectedId: userId);
        final AccessAdminItem updated = _updatedUserItem(userId, draft);
        final AccessAdminWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(latest.copyWith(isSaving: false, isRefreshing: false));
        }
        await _flushPendingRefresh();
        _scheduleSessionRehydrate();
        return Result<AccessAdminItem>.success(updated);
      },
      failure: (AppFailure failure) async {
        final AccessAdminWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(
            latest.copyWith(
              isSaving: false,
              isRefreshing: false,
              lastFailure: failure,
            ),
          );
        }
        return Result<AccessAdminItem>.failure(failure);
      },
    );
  }

  AccessAdminItem _updatedUserItem(String userId, AccessAdminUserDraft draft) {
    final AccessAdminWorkspaceState? current = _currentState;
    if (current != null &&
        current.query.resource == AccessAdminResource.users) {
      for (final AccessAdminItem item in current.data.page.items) {
        if (item.id == userId ||
            item.mutationId == userId ||
            item.effectiveDisplayId == userId) {
          return item.copyWith(
            email: draft.email,
            phone: draft.phone,
            positionTitle: draft.positionTitle,
            firstName: draft.firstName,
            lastName: draft.lastName,
            profileName: <String?>[draft.firstName, draft.lastName]
                .whereType<String>()
                .map((String value) => value.trim())
                .where((String value) => value.isNotEmpty)
                .join(' '),
            status: draft.status,
            tenantId: draft.tenantId,
            facilityId: draft.facilityId,
            tenantName: draft.tenantName ?? item.tenantName,
            facilityName: draft.facilityName ?? item.facilityName,
          );
        }
      }
    }
    return _createdUserItem(userId, draft);
  }

  Future<AppFailure?> updateUserWithRoles(
    String userId,
    AccessAdminUserDraft draft,
    List<String> roleIds,
  ) {
    return _submitAction(() async {
      final Result<void> updateResult = await _repository.updateUser(
        userId,
        draft,
      );
      if (updateResult case ResultFailure<void>(:final failure)) {
        return Result<void>.failure(failure);
      }
      return _repository.syncUserRoles(
        userId: userId,
        tenantId: draft.tenantId,
        facilityId: draft.facilityId,
        roleIds: roleIds,
      );
    }, refreshSession: true);
  }

  Future<Result<AccessAdminItem>> createRole(AccessAdminRoleDraft draft) async {
    final AccessAdminWorkspaceState? current = _currentState;
    if (current != null) {
      _emit(current.copyWith(isSaving: true, clearLastFailure: true));
    }

    final Result<AccessAdminItem> result = await _repository.createRole(draft);
    return result.when(
      success: (AccessAdminItem created) async {
        await _refreshWorkspace(preferredSelectedId: created.id);
        final AccessAdminWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(latest.copyWith(isSaving: false, isRefreshing: false));
        }
        await _flushPendingRefresh();
        _scheduleSessionRehydrate();
        return Result<AccessAdminItem>.success(created);
      },
      failure: (AppFailure failure) async {
        final AccessAdminWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(
            latest.copyWith(
              isSaving: false,
              isRefreshing: false,
              lastFailure: failure,
            ),
          );
        }
        return Result<AccessAdminItem>.failure(failure);
      },
    );
  }

  Future<AppFailure?> updateRole(String roleId, AccessAdminRoleDraft draft) {
    return _submitAction(
      () => _repository.updateRole(roleId, draft),
      refreshSession: true,
    );
  }

  Future<AppFailure?> assignUserRole(AccessAdminUserRoleDraft draft) {
    return _submitAction(
      () => _repository.assignUserRole(draft),
      refreshSession: true,
    );
  }

  Future<AppFailure?> revokeUserRole(String userRoleId) {
    return _submitAction(
      () => _repository.revokeUserRole(userRoleId),
      refreshSession: true,
    );
  }

  Future<AppFailure?> syncUserRoles({
    required String userId,
    required String tenantId,
    required List<String> roleIds,
    String? facilityId,
  }) {
    return _submitAction(
      () => _repository.syncUserRoles(
        userId: userId,
        tenantId: tenantId,
        roleIds: roleIds,
        facilityId: facilityId,
      ),
      refreshSession: true,
    );
  }

  Future<AppFailure?> syncUserDirectPermissions({
    required String userId,
    required List<String> permissionIds,
  }) {
    return _submitAction(
      () => _repository.syncUserDirectPermissions(
        userId: userId,
        permissionIds: permissionIds,
      ),
      refreshSession: true,
    );
  }

  Future<AppFailure?> assignRolePermission(
    AccessAdminRolePermissionDraft draft,
  ) {
    return _submitAction(
      () => _repository.assignRolePermission(draft),
      refreshSession: true,
    );
  }

  Future<AppFailure?> deleteRole(AccessAdminItem item) {
    final policy = ref.read(appAccessPolicyProvider);
    if (!canMutateAccessAdminSystemCatalog(
      policy,
      isSystemCritical: item.isSystemCritical,
    )) {
      return Future<AppFailure?>.value(AppFailure.validation());
    }
    return _submitAction(
      () => _repository.deleteRole(item.mutationId),
      removeItemId: item.id,
      refreshSession: true,
    );
  }

  /// Rehydrates the signed-in user's live grants from `/auth/me`.
  Future<void> rehydrateSession() => _refreshSession();

  void _scheduleSessionRehydrate() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!ref.mounted) {
        return;
      }
      unawaited(_refreshSession());
    });
  }

  Future<AppFailure?> resetDemoPassword(AccessAdminItem item) {
    return _submitAction(
      () => _repository.resetDemoUserPassword(item.effectiveDisplayId),
    );
  }

  Future<AppFailure?> approveRegistration(AccessAdminItem item) {
    return _submitAction(
      () => _repository.approveRegistration(item.mutationId),
    );
  }

  Future<AppFailure?> rejectRegistration(AccessAdminItem item) {
    return _submitAction(
      () => _repository.rejectRegistration(item.mutationId),
    );
  }

  AccessAdminWorkspaceState? get _currentState {
    final Result<AccessAdminWorkspaceState>? currentResult =
        state.asData?.value;
    return switch (currentResult) {
      ResultSuccess<AccessAdminWorkspaceState>(value: final value) => value,
      _ => null,
    };
  }

  Future<Result<AccessAdminWorkspaceState>> _loadInitialState() async {
    final Result<AccessAdminWorkspaceData> workspaceResult = await _repository
        .getWorkspace(const AccessAdminWorkspaceQuery());
    return workspaceResult.when(
      success: (AccessAdminWorkspaceData data) {
        return Result<AccessAdminWorkspaceState>.success(
          AccessAdminWorkspaceState(data: data, query: data.query),
        );
      },
      failure: (AppFailure failure) {
        return Result<AccessAdminWorkspaceState>.failure(failure);
      },
    );
  }

  Future<AppFailure?> _loadQuery(
    AccessAdminWorkspaceQuery query, {
    bool clearSelectedItem = false,
    String? preserveSelectedId,
  }) async {
    _emitSaving(clearSelectedItem: clearSelectedItem);
    final Result<AccessAdminWorkspaceData> result = await _repository
        .getWorkspace(query);
    return result.when(
      success: (AccessAdminWorkspaceData data) {
        AccessAdminItem? selected = clearSelectedItem
            ? null
            : _currentState?.selectedItem;
        if (preserveSelectedId != null) {
          for (final AccessAdminItem item in data.items) {
            if (item.id == preserveSelectedId ||
                item.effectiveDisplayId == preserveSelectedId) {
              selected = item;
              break;
            }
          }
        }
        _emit(
          AccessAdminWorkspaceState(
            data: data,
            query: data.query,
            selectedItem: selected,
          ),
        );
        if (selected != null &&
            (selected.resource == AccessAdminResource.users ||
                selected.resource == AccessAdminResource.demoUsers)) {
          unawaited(loadUserDetail(selected));
        }
        return null;
      },
      failure: (AppFailure failure) {
        final AccessAdminWorkspaceState? current = _currentState;
        if (current != null) {
          _emit(
            current.copyWith(
              isRefreshing: false,
              isSaving: false,
              lastFailure: failure,
            ),
          );
        } else {
          state = AsyncData<Result<AccessAdminWorkspaceState>>(
            Result<AccessAdminWorkspaceState>.failure(failure),
          );
        }
        return failure;
      },
    );
  }

  Future<AppFailure?> _refreshWorkspace({String? preferredSelectedId}) {
    final AccessAdminWorkspaceState? current = _currentState;
    if (current == null) return refresh();
    return _loadQuery(current.query, preserveSelectedId: preferredSelectedId);
  }

  Future<AccessAdminWorkspaceQuery> _resolveRouteQuery(
    AccessAdminWorkspaceQuery query,
  ) async {
    final String? recordId = query.recordId;
    if (recordId == null) return query;

    final Result<AccessAdminLegacyRouteResolution> result = await _repository
        .resolveLegacyRoute(query.resource, recordId);
    return result.when(
      success: (AccessAdminLegacyRouteResolution resolution) {
        return query.copyWith(
          panel: resolution.panel,
          resource: resolution.resource,
          recordId: resolution.id ?? recordId,
        );
      },
      failure: (_) => query,
    );
  }

  Future<AppFailure?> _submitAction(
    Future<Result<void>> Function() action, {
    bool refreshSession = false,
    String? removeItemId,
  }) async {
    final AccessAdminWorkspaceState? current = _currentState;
    if (current != null) {
      _emit(current.copyWith(isSaving: true, clearLastFailure: true));
    }

    final Result<void> result = await action();
    return result.when(
      success: (_) async {
        if (removeItemId != null) {
          final bool removed = _removeLocalItem(removeItemId);
          if (!removed) {
            await _refreshWorkspace(
              preferredSelectedId: current?.selectedItem?.id,
            );
          }
        } else {
          await _refreshWorkspace(
            preferredSelectedId: current?.selectedItem?.id,
          );
        }
        final AccessAdminWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(latest.copyWith(isSaving: false, isRefreshing: false));
        }
        await _flushPendingRefresh();
        if (refreshSession) {
          // Defer past dialog/overlay pop so GoRouter/shell refresh does not
          // dispose InheritedWidgets while dependents are still mounted.
          _scheduleSessionRehydrate();
        }
        return null;
      },
      failure: (AppFailure failure) {
        final AccessAdminWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(latest.copyWith(isSaving: false, lastFailure: failure));
        }
        return failure;
      },
    );
  }

  Future<AppFailure?> _mutateWithLocalUpsert<T>(
    Future<Result<T>> Function() action, {
    required void Function(T value) onSuccess,
  }) async {
    final AccessAdminWorkspaceState? current = _currentState;
    if (current != null) {
      _emit(current.copyWith(isSaving: true, clearLastFailure: true));
    }

    final Result<T> result = await action();
    return result.when(
      success: (T value) async {
        onSuccess(value);
        final AccessAdminWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(latest.copyWith(isSaving: false, isRefreshing: false));
        }
        await _flushPendingRefresh();
        return null;
      },
      failure: (AppFailure failure) {
        final AccessAdminWorkspaceState? latest = _currentState;
        if (latest != null) {
          _emit(latest.copyWith(isSaving: false, lastFailure: failure));
        }
        return failure;
      },
    );
  }

  void _upsertCreatedUser(String id, AccessAdminUserDraft draft) {
    final AccessAdminWorkspaceState? current = _currentState;
    if (current == null ||
        current.query.resource != AccessAdminResource.users) {
      return;
    }

    final AccessAdminWorkspaceState? patched =
        AccessAdminRealtimeDeltaApplier.apply(
          current,
          RealtimeDelta(
            action: RealtimeSyncAction.upsert,
            entity: <String, Object?>{
              'id': id,
              'display_id': id,
              'email': draft.email,
              'first_name': draft.firstName,
              'last_name': draft.lastName,
              'profile_name': <String?>[draft.firstName, draft.lastName]
                  .whereType<String>()
                  .map((String value) => value.trim())
                  .where((String value) => value.isNotEmpty)
                  .join(' '),
              'position_title': draft.positionTitle,
              'status': draft.status,
              'tenant_id': draft.tenantId,
              'facility_id': draft.facilityId,
            },
            resourceId: id,
            resourceType: 'user',
          ),
        );
    if (patched != null) {
      _emit(patched);
    }
  }

  bool _removeLocalItem(String id) {
    final AccessAdminWorkspaceState? current = _currentState;
    if (current == null) {
      return false;
    }
    final AccessAdminWorkspaceState? patched =
        AccessAdminRealtimeDeltaApplier.apply(
          current,
          RealtimeDelta(
            action: RealtimeSyncAction.remove,
            resourceId: id,
            resourceType: current.query.resource.serverValue == 'roles'
                ? 'role'
                : 'user',
          ),
        );
    if (patched != null) {
      _emit(patched);
      return true;
    }
    return false;
  }

  Future<void> _flushPendingRefresh() async {
    if (!_pendingRefresh.refreshPending) {
      return;
    }
    final WorkspaceRefreshPlan plan = _pendingRefresh.takePending();
    if (plan.isEmpty) {
      return;
    }
    await _refreshWorkspace(
      preferredSelectedId: _currentState?.selectedItem?.id,
    );
  }

  void _emitSaving({bool clearSelectedItem = false}) {
    final AccessAdminWorkspaceState? current = _currentState;
    if (current == null) return;
    _emit(
      current.copyWith(
        isRefreshing: true,
        isSaving: true,
        clearLastFailure: true,
        selectedItem: clearSelectedItem ? null : current.selectedItem,
        selectedUserDetail: clearSelectedItem
            ? null
            : current.selectedUserDetail,
      ),
    );
  }

  /// Clears a page-level failure banner (e.g. after an inline dialog handles it).
  void clearLastFailure() {
    final AccessAdminWorkspaceState? current = _currentState;
    if (current == null || current.lastFailure == null) {
      return;
    }
    _emit(current.copyWith(clearLastFailure: true));
  }

  void _emit(AccessAdminWorkspaceState next) {
    state = AsyncData<Result<AccessAdminWorkspaceState>>(
      Result<AccessAdminWorkspaceState>.success(next),
    );
  }

  Future<void> _refreshSession() async {
    final session = ref.read(sessionStateProvider).session;
    if (session == null) {
      return;
    }

    // Prefer /auth/me so role/permission CRUD is reflected immediately in the
    // shell without waiting for a new JWT snapshot.
    final meResult = await ref
        .read(authRepositoryProvider)
        .fetchCurrentUser(session);
    final bool persisted = await meResult.when<Future<bool>>(
      success: (AuthSession refreshed) async {
        await ref
            .read(sessionStateProvider.notifier)
            .persistSession(refreshed);
        return true;
      },
      failure: (_) async => false,
    );
    if (persisted || !session.tokens.hasRefreshToken) {
      return;
    }

    final refreshResult = await ref
        .read(authRepositoryProvider)
        .refreshSession(session.tokens);
    await refreshResult.when<Future<void>>(
      success: (AuthSession refreshed) {
        return ref.read(sessionStateProvider.notifier).persistSession(refreshed);
      },
      failure: (_) async {},
    );
  }

  AppFailure? _failureOrNull(Result<AccessAdminWorkspaceState> result) {
    return result.when(
      success: (_) => null,
      failure: (AppFailure failure) => failure,
    );
  }

  AccessAdminResource _defaultResourceForPanel(AccessAdminPanel panel) {
    return switch (panel) {
      AccessAdminPanel.overview => AccessAdminResource.users,
      AccessAdminPanel.directory => AccessAdminResource.users,
      AccessAdminPanel.roles => AccessAdminResource.roles,
      AccessAdminPanel.permissions => AccessAdminResource.permissions,
      AccessAdminPanel.entitlements => AccessAdminResource.moduleEntitlements,
      AccessAdminPanel.registrations =>
        AccessAdminResource.registrationFollowUps,
      AccessAdminPanel.payments =>
        AccessAdminResource.subscriptionPaymentRequests,
      AccessAdminPanel.demo => AccessAdminResource.demoUsers,
    };
  }
}
