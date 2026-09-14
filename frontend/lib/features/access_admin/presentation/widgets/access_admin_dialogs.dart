import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/permissions/access_policy.dart';
import 'package:hosspi_hms/core/permissions/permission_providers.dart';
import 'package:hosspi_hms/core/security/session_controller.dart';
import 'package:hosspi_hms/features/access_admin/data/repositories/access_admin_repository_impl.dart';
import 'package:hosspi_hms/features/access_admin/domain/entities/access_admin_entities.dart';
import 'package:hosspi_hms/features/access_admin/domain/entities/role_similarity.dart';
import 'package:hosspi_hms/features/access_admin/domain/entities/user_similarity.dart';
import 'package:hosspi_hms/features/access_admin/domain/repositories/access_admin_repository.dart';
import 'package:hosspi_hms/features/access_admin/presentation/access_admin_access.dart';
import 'package:hosspi_hms/features/access_admin/presentation/controllers/access_admin_workspace_controller.dart';
import 'package:hosspi_hms/features/access_admin/presentation/pages/access_admin_workspace_page.dart';
import 'package:hosspi_hms/features/access_admin/presentation/widgets/role_mutation_dialog.dart';
import 'package:hosspi_hms/features/access_admin/presentation/widgets/role_similarity_dialog.dart';
import 'package:hosspi_hms/features/access_admin/presentation/widgets/user_mutation_dialog.dart';
import 'package:hosspi_hms/features/access_admin/presentation/widgets/user_similarity_dialog.dart';
import 'package:hosspi_hms/features/tenant_facility/data/repositories/tenant_facility_repository_impl.dart';
import 'package:hosspi_hms/features/tenant_facility/domain/entities/tenant_facility_setup.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/components/components.dart';
import 'package:hosspi_hms/shared/data/data.dart';

Future<void> showAccessAdminWorkspaceDialog(
  BuildContext context, {
  AccessAdminPanel? initialPanel,
}) async {
  await showAppDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) =>
        _AccessAdminWorkspaceDialogShell(initialPanel: initialPanel),
  );
}

Future<bool?> showAccessAdminCreateUserDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final AccessAdminWorkspaceController controller = ref.read(
    accessAdminWorkspaceControllerProvider.notifier,
  );
  final Result<AccessAdminWorkspaceState> stateResult = await ref.read(
    accessAdminWorkspaceControllerProvider.future,
  );
  final AccessAdminWorkspaceState? state = stateResult.when(
    success: (AccessAdminWorkspaceState value) => value,
    failure: (_) => null,
  );
  if (state == null) {
    await controller.refresh();
  }
  final Result<AccessAdminWorkspaceState> refreshed = await ref.read(
    accessAdminWorkspaceControllerProvider.future,
  );
  return refreshed.when(
    success: (AccessAdminWorkspaceState value) async {
      final AccessAdminItem? created = await openAccessAdminCreateUserDialog(
        context,
        ref,
        value,
      );
      return created != null;
    },
    failure: (AppFailure failure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.failureMessage(failure))),
      );
      return null;
    },
  );
}

Future<AccessAdminItem?> showAccessAdminCreateRoleDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  if (!context.mounted) {
    return null;
  }
  return openAccessAdminCreateRoleDialog(
    context,
    ref,
    _emptyCreateRoleWorkspaceState(),
  );
}

AccessAdminWorkspaceState _emptyCreateRoleWorkspaceState() {
  return const AccessAdminWorkspaceState(
    data: AccessAdminWorkspaceData(state: 'tenant_context_required'),
  );
}

class _AccessAdminWorkspaceDialogShell extends ConsumerStatefulWidget {
  const _AccessAdminWorkspaceDialogShell({this.initialPanel});

  final AccessAdminPanel? initialPanel;

  @override
  ConsumerState<_AccessAdminWorkspaceDialogShell> createState() =>
      _AccessAdminWorkspaceDialogShellState();
}

class _AccessAdminWorkspaceDialogShellState
    extends ConsumerState<_AccessAdminWorkspaceDialogShell> {
  @override
  void initState() {
    super.initState();
    if (widget.initialPanel != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(accessAdminWorkspaceControllerProvider.notifier)
            .applyPanel(widget.initialPanel!);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Result<AccessAdminWorkspaceState>> workspace = ref.watch(
      accessAdminWorkspaceControllerProvider,
    );

    return AppDialog(
      title: Text(context.l10n.accessAdminTitle),
      icon: const Icon(Icons.manage_accounts_outlined),
      pinActionsToBottom: true,
      maxWidth: 1180,
      content: SizedBox(
        height: 640,
        child: workspace.when(
          data: (Result<AccessAdminWorkspaceState> result) => result.when(
            success: (AccessAdminWorkspaceState state) =>
                AccessAdminWorkspacePage(
                  initialQuery: AccessAdminWorkspaceQuery(
                    panel: state.query.panel,
                    resource: state.query.resource,
                  ),
                ),
            failure: (AppFailure failure) => AppFailureStateView(
              failure: failure,
              onRetry: () {
                ref.invalidate(accessAdminWorkspaceControllerProvider);
              },
            ),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace stackTrace) => AppFailureStateView(
            failure: const AppFailure.unexpected(),
            onRetry: () {
              ref.invalidate(accessAdminWorkspaceControllerProvider);
            },
          ),
        ),
      ),
      actions: <Widget>[
        AppButton.secondary(
          label: context.l10n.commonCloseActionLabel,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

Future<void> showAccessAdminUserFormDialog(
  BuildContext context,
  WidgetRef ref,
  AccessAdminWorkspaceState state,
) {
  return openAccessAdminCreateUserDialog(context, ref, state);
}

Future<AccessAdminItem?> openAccessAdminCreateUserDialog(
  BuildContext context,
  WidgetRef ref,
  AccessAdminWorkspaceState state,
) async {
  if (!context.mounted) {
    return null;
  }
  final AppAccessPolicy accessPolicy = ref.read(appAccessPolicyProvider);
  // Directory/Demo create ∩: tenant:admin (+ elevated) and workspace canWrite.
  // Same write gate; panel-specific helpers keep inventory/AC tracing clear.
  final bool canCreateUser = state.query.panel == AccessAdminPanel.demo
      ? canMutateAccessAdminDemo(
          accessPolicy,
          workspaceCanWrite: state.data.permissions.canWrite,
        )
      : canMutateAccessAdminDirectory(
          accessPolicy,
          workspaceCanWrite: state.data.permissions.canWrite,
        );
  if (!canCreateUser) {
    return null;
  }

  AccessAdminItem? createdUser;
  AccessAdminItem? existingUserToOpen;

  final bool? saved = await showUserMutationDialog(
    context: context,
    ref: ref,
    mode: UserMutationMode.create,
    state: state,
    onSubmit: (AccessAdminUserDraft draft, List<String> roleIds) async {
      var similarityAccepted = draft.confirmSimilar;
      var pending = draft.copyWith(confirmSimilar: similarityAccepted);

      // Create always opens the review before persisting (including zero
      // matches), mirroring the role create flow.
      if (!pending.confirmSimilar) {
        if (!context.mounted) {
          return const AppFailure.cancelled();
        }
        final AppFailure? reviewFailure = await _reviewUserSimilarity(
          context,
          ref,
          pending: pending,
          onAccepted: () => similarityAccepted = true,
          onUseExisting: (AccessAdminItem user) {
            existingUserToOpen = user;
          },
        );
        if (reviewFailure != null) {
          return reviewFailure;
        }
        if (existingUserToOpen != null) {
          return null;
        }
        pending = pending.copyWith(confirmSimilar: similarityAccepted);
      }

      final Result<AccessAdminItem> result = await ref
          .read(accessAdminWorkspaceControllerProvider.notifier)
          .createUserReviewed(pending);
      AppFailure? failure = result.when(
        success: (AccessAdminItem created) {
          createdUser ??= created;
          return null;
        },
        failure: (AppFailure value) => value,
      );

      // Backend uniqueness is authoritative; never surface it as an inline
      // create-dialog conflict banner — reopen the dedicated review dialog.
      if (failure != null &&
          failure.category == AppFailureCategory.conflict) {
        if (!context.mounted) {
          return const AppFailure.cancelled();
        }

        // Conflicts that are not about similar people (an email still held by
        // a deleted user, a staff number race) carry field messages the form
        // shows directly; only similarity conflicts reopen the review.
        if (!_isUserSimilarityConflict(failure)) {
          return failure;
        }

        final bool isExactContactConflict =
            _isUserDuplicateContactConflict(failure);
        final bool alreadyConfirmed = pending.confirmSimilar;
        // similar_exists after confirm_similar should not reopen an empty
        // "no similar" dialog — create once was already attempted.
        if (alreadyConfirmed && !isExactContactConflict) {
          return failure;
        }

        similarityAccepted = false;
        final AppFailure? reviewFailure = await _reviewUserSimilarity(
          context,
          ref,
          pending: pending.copyWith(confirmSimilar: false),
          backendFailure: failure,
          forceReviewMatches: true,
          conflictEntries: failure is ConflictFailure
              ? failure.conflictEntries
              : const <Map<String, Object?>>[],
          onAccepted: () => similarityAccepted = true,
          onUseExisting: (AccessAdminItem user) {
            existingUserToOpen = user;
          },
        );
        if (reviewFailure != null) {
          return reviewFailure;
        }
        if (existingUserToOpen != null) {
          return null;
        }
        if (!similarityAccepted || isExactContactConflict) {
          return const AppFailure.cancelled();
        }

        final Result<AccessAdminItem> retry = await ref
            .read(accessAdminWorkspaceControllerProvider.notifier)
            .createUserReviewed(pending.copyWith(confirmSimilar: true));
        final AppFailure? retryFailure = retry.when(
          success: (AccessAdminItem created) {
            createdUser ??= created;
            return null;
          },
          failure: (AppFailure value) => value,
        );
        if (retryFailure != null &&
            retryFailure.category == AppFailureCategory.conflict) {
          // Exact contact conflicts cannot be bypassed with confirm_similar.
          return const AppFailure.cancelled();
        }
        if (retryFailure != null) {
          return retryFailure;
        }
        failure = null;
      }

      if (failure != null) {
        return failure;
      }
      return null;
    },
  );

  if (existingUserToOpen != null) {
    return existingUserToOpen;
  }
  if (saved == true) {
    return createdUser;
  }
  return null;
}

Future<AppFailure?> _reviewUserSimilarity(
  BuildContext context,
  WidgetRef ref, {
  required AccessAdminUserDraft pending,
  required VoidCallback onAccepted,
  required ValueChanged<AccessAdminItem> onUseExisting,
  String? excludeUserId,
  bool isEdit = false,
  bool forceReviewMatches = false,
  List<Map<String, Object?>> conflictEntries = const <Map<String, Object?>>[],
  AppFailure? backendFailure,
}) async {
  final _UserSimilarityPeers peerLookup = await _loadUserSimilarityPeers(
    ref,
    tenantId: pending.tenantId,
    email: pending.email,
    phone: pending.phone,
    positionTitle: pending.positionTitle,
    firstName: pending.firstName,
    lastName: pending.lastName,
  );
  if (!context.mounted) {
    return const AppFailure.cancelled();
  }
  // A failed peer lookup must never be reported as "no similar user found".
  if (peerLookup.failure != null) {
    return peerLookup.failure;
  }
  final List<AccessAdminItem> peers = peerLookup.items;

  String? proposedFacilityName = pending.facilityName?.trim().isNotEmpty == true
      ? pending.facilityName!.trim()
      : null;
  String? proposedTenantName = pending.tenantName?.trim().isNotEmpty == true
      ? pending.tenantName!.trim()
      : null;
  for (final AccessAdminItem peer in peers) {
    if (proposedFacilityName == null &&
        pending.facilityId != null &&
        peer.facilityId == pending.facilityId &&
        (peer.facilityName ?? '').trim().isNotEmpty) {
      proposedFacilityName = peer.facilityName;
    }
    if (proposedTenantName == null &&
        peer.tenantId == pending.tenantId &&
        (peer.tenantName ?? '').trim().isNotEmpty) {
      proposedTenantName = peer.tenantName;
    }
  }

  final UserDuplicateCheckResult check = checkUserDuplicates(
    email: pending.email,
    phone: pending.phone,
    positionTitle: pending.positionTitle,
    firstName: pending.firstName,
    lastName: pending.lastName,
    facilityId: pending.facilityId,
    facilityName: proposedFacilityName ?? pending.facilityName,
    tenantId: pending.tenantId,
    existing: peers,
    excludeUserId: excludeUserId,
  );

  List<UserSimilarityMatch> reviewMatches;
  if (forceReviewMatches) {
    reviewMatches = check.similarMatches;
  } else if (check.hasExactConflict) {
    reviewMatches = check.similarMatches
        .where(
          (UserSimilarityMatch match) =>
              match.exactEmailConflict || match.exactPhoneConflict,
        )
        .toList(growable: false);
    if (reviewMatches.isEmpty) {
      reviewMatches = check.similarMatches;
    }
  } else {
    reviewMatches = check.overridableMatches;
  }

  // When peer load missed identity rows, hydrate from the authoritative
  // backend uniqueness payload so conflict reopen is never empty "no similar".
  if (reviewMatches.isEmpty && conflictEntries.isNotEmpty) {
    reviewMatches = userSimilarityMatchesFromConflictEntries(conflictEntries);
  }

  final bool hasExactConflict =
      check.hasExactConflict ||
      reviewMatches.any(
        (UserSimilarityMatch match) =>
            match.exactEmailConflict || match.exactPhoneConflict,
      );

  // Force-review after backend conflict must not reopen a false empty
  // "no similar" confirmation — that loops Continue create without creating.
  if (forceReviewMatches && reviewMatches.isEmpty) {
    // Keep the API's field messages so the form can point at the field.
    return backendFailure ?? AppFailure.conflict(code: 'EMAIL_EXISTS_IN_TENANT');
  }

  final UserSimilarityDialogResult review = await showUserSimilarityDialog(
    context,
    proposed: UserSimilarityProposedValues(
      email: pending.email,
      phone: pending.phone,
      positionTitle: pending.positionTitle,
      firstName: pending.firstName,
      lastName: pending.lastName,
      tenantId: pending.tenantId,
      facilityId: pending.facilityId,
      tenantName: proposedTenantName,
      facilityName: proposedFacilityName,
    ),
    matches: reviewMatches,
    allowProceed: !hasExactConflict,
    isEdit: isEdit,
  );
  if (!context.mounted) {
    return const AppFailure.cancelled();
  }

  switch (review.action) {
    case UserSimilarityAction.cancel:
      return const AppFailure.cancelled();
    case UserSimilarityAction.useExisting:
      final AccessAdminItem? existing = review.selectedUser?.user;
      if (existing != null) {
        onUseExisting(existing);
      }
      return null;
    case UserSimilarityAction.proceed:
      onAccepted();
      return null;
  }
}

bool _isUserDuplicateContactConflict(AppFailure failure) {
  final String code = failure.code.trim().toUpperCase();
  if (code == 'EMAIL_EXISTS_IN_TENANT' ||
      code == 'PHONE_EXISTS_IN_TENANT' ||
      code == 'CONTACT_EXISTS_IN_TENANT' ||
      code.endsWith('_EXISTS_IN_TENANT')) {
    return true;
  }
  if (failure is ConflictFailure && failure.conflictEntries.isNotEmpty) {
    return failure.conflictEntries.any(
      (Map<String, Object?> entry) =>
          entry['exactEmailConflict'] == true ||
          entry['exactPhoneConflict'] == true ||
          entry['isExact'] == true,
    );
  }
  return false;
}

/// Similarity and exact-contact conflicts open the review; every other 409 is
/// a field-level error for the form.
bool _isUserSimilarityConflict(AppFailure failure) {
  final String code = failure.code.trim().toUpperCase();
  return code == 'SIMILAR_EXISTS' ||
      _isUserDuplicateContactConflict(failure) ||
      (failure is ConflictFailure && failure.conflictEntries.isNotEmpty);
}

/// Matches backend `USER_SIMILARITY_LOOKUP_LIMIT`.
const int _userSimilarityPeerLimit = 500;

@immutable
final class _UserSimilarityPeers {
  const _UserSimilarityPeers({required this.items, this.failure});

  final List<AccessAdminItem> items;
  final AppFailure? failure;
}

Future<_UserSimilarityPeers> _loadUserSimilarityPeers(
  WidgetRef ref, {
  String? tenantId,
  required String email,
  String? phone,
  String? positionTitle,
  String? firstName,
  String? lastName,
}) async {
  // Users are always tenant-scoped for uniqueness. Load the tenant workspace
  // across all facilities, plus search-biased pages on email/phone/position so
  // identity peers past the alphabetical window still surface.
  final String? scopedTenantId =
      (tenantId ?? '').trim().isEmpty ? null : tenantId!.trim();
  final Map<String, AccessAdminItem> alphabeticalPeers =
      <String, AccessAdminItem>{};
  final Map<String, AccessAdminItem> searchedPeers =
      <String, AccessAdminItem>{};

  Future<AppFailure?> appendPeers({
    String search = '',
    required Map<String, AccessAdminItem> target,
  }) async {
    var request = const AppPageRequest(pageSize: AppPageRequest.maxPageSize);
    while (target.length < _userSimilarityPeerLimit) {
      final Result<AccessAdminWorkspaceData> result = await ref
          .read(accessAdminRepositoryProvider)
          .getWorkspace(
            AccessAdminWorkspaceQuery(
              panel: AccessAdminPanel.directory,
              resource: AccessAdminResource.users,
              tenantId: scopedTenantId,
              allTenants: scopedTenantId == null,
              allFacilities: true,
              lean: true,
              skipLookups: true,
              search: search,
              pageRequest: request,
            ),
          );

      final AppFailure? failure = result.when(
        success: (AccessAdminWorkspaceData data) =>
            data.state == 'tenant_context_required'
            ? AppFailure.unexpectedResponse()
            : null,
        failure: (AppFailure value) => value,
      );
      if (failure != null) {
        return failure;
      }

      final AppPage<AccessAdminItem> page = result.when(
        success: (AccessAdminWorkspaceData data) => data.page,
        failure: (_) => const AppPage<AccessAdminItem>(
          items: <AccessAdminItem>[],
          request: AppPageRequest(),
        ),
      );
      for (final AccessAdminItem item in page.items) {
        // Keep only same-tenant peers so the client set mirrors BE uniqueness.
        if (scopedTenantId != null) {
          final String? itemTenant = item.tenantId?.trim();
          if (itemTenant != null &&
              itemTenant.isNotEmpty &&
              itemTenant != scopedTenantId) {
            continue;
          }
        }
        final String key = <String?>[
          item.id,
          item.mutationId,
          item.resourceUuid,
          item.effectiveDisplayId,
        ].whereType<String>().firstWhere(
          (String value) => value.trim().isNotEmpty,
          orElse: () => item.email ?? item.title,
        );
        target.putIfAbsent(key, () => item);
        if (target.length >= _userSimilarityPeerLimit) {
          break;
        }
      }
      if (!page.hasNextPage || page.items.isEmpty) {
        break;
      }
      request = request.next();
    }
    return null;
  }

  final AppFailure? baseFailure = await appendPeers(target: alphabeticalPeers);
  if (baseFailure != null) {
    return _UserSimilarityPeers(
      items: alphabeticalPeers.values.toList(growable: false),
      failure: baseFailure,
    );
  }

  final Set<String> searchTerms = <String>{
    if (email.trim().isNotEmpty) email.trim(),
    if ((phone ?? '').trim().isNotEmpty) phone!.trim(),
    if ((positionTitle ?? '').trim().isNotEmpty) positionTitle!.trim(),
    if ((firstName ?? '').trim().isNotEmpty) firstName!.trim(),
    if ((lastName ?? '').trim().isNotEmpty) lastName!.trim(),
    if ((firstName ?? '').trim().isNotEmpty || (lastName ?? '').trim().isNotEmpty)
      <String?>[firstName, lastName]
          .whereType<String>()
          .map((String value) => value.trim())
          .where((String value) => value.isNotEmpty)
          .join(' '),
  };
  for (final String term in searchTerms) {
    final Map<String, AccessAdminItem> scopedSearchPeers =
        <String, AccessAdminItem>{};
    final AppFailure? scopedSearchFailure = await appendPeers(
      search: term,
      target: scopedSearchPeers,
    );
    searchedPeers.addAll(scopedSearchPeers);
    if (scopedSearchFailure != null) {
      return _UserSimilarityPeers(
        items: <AccessAdminItem>[
          ...searchedPeers.values,
          ...alphabeticalPeers.values,
        ],
        failure: scopedSearchFailure,
      );
    }
  }

  final Map<String, AccessAdminItem> prioritizedPeers =
      <String, AccessAdminItem>{...searchedPeers};
  for (final MapEntry<String, AccessAdminItem> entry
      in alphabeticalPeers.entries) {
    prioritizedPeers.putIfAbsent(entry.key, () => entry.value);
  }
  return _UserSimilarityPeers(
    items: prioritizedPeers.values
        .take(_userSimilarityPeerLimit)
        .toList(growable: false),
  );
}

Future<AccessAdminItem?> openAccessAdminEditUserDialog(
  BuildContext context,
  WidgetRef ref,
  AccessAdminWorkspaceState state, {
  required AccessAdminItem user,
  AccessAdminUserDetail? detail,
}) async {
  if (!context.mounted) {
    return null;
  }
  if (!canMutateAccessAdminDemoAccount(detail?.item ?? user)) {
    return null;
  }

  final AccessAdminItem baseline = detail?.item ?? user;
  final String excludeUserId = baseline.mutationId.trim().isNotEmpty
      ? baseline.mutationId
      : baseline.id;

  AccessAdminItem? updatedUser;
  AccessAdminItem? existingUserToOpen;

  Future<AppFailure?> saveDetails(AccessAdminUserDraft draft) async {
    var similarityAccepted = draft.confirmSimilar;
    var pending = draft.copyWith(confirmSimilar: similarityAccepted);

    // Edit mirrors create: always open review before persisting (including
    // zero matches). Peers exclude the user being edited.
    if (!pending.confirmSimilar) {
      if (!context.mounted) {
        return const AppFailure.cancelled();
      }
      final AppFailure? reviewFailure = await _reviewUserSimilarity(
        context,
        ref,
        pending: pending,
        excludeUserId: excludeUserId,
        isEdit: true,
        onAccepted: () => similarityAccepted = true,
        onUseExisting: (AccessAdminItem existing) {
          existingUserToOpen = existing;
        },
      );
      if (reviewFailure != null) {
        return reviewFailure;
      }
      if (existingUserToOpen != null) {
        return null;
      }
      pending = pending.copyWith(confirmSimilar: similarityAccepted);
    }

    final Result<AccessAdminItem> result = await ref
        .read(accessAdminWorkspaceControllerProvider.notifier)
        .updateUserReviewed(excludeUserId, pending);
    AppFailure? failure = result.when(
      success: (AccessAdminItem updated) {
        updatedUser ??= updated;
        return null;
      },
      failure: (AppFailure value) => value,
    );

    if (failure != null &&
        failure.category == AppFailureCategory.conflict) {
      if (!context.mounted) {
        return const AppFailure.cancelled();
      }

      if (!_isUserSimilarityConflict(failure)) {
        return failure;
      }

      final bool isExactContactConflict =
          _isUserDuplicateContactConflict(failure);
      final bool alreadyConfirmed = pending.confirmSimilar;
      if (alreadyConfirmed && !isExactContactConflict) {
        return failure;
      }

      similarityAccepted = false;
      final AppFailure? reviewFailure = await _reviewUserSimilarity(
        context,
        ref,
        pending: pending.copyWith(confirmSimilar: false),
        backendFailure: failure,
        excludeUserId: excludeUserId,
        isEdit: true,
        forceReviewMatches: true,
        conflictEntries: failure is ConflictFailure
            ? failure.conflictEntries
            : const <Map<String, Object?>>[],
        onAccepted: () => similarityAccepted = true,
        onUseExisting: (AccessAdminItem existing) {
          existingUserToOpen = existing;
        },
      );
      if (reviewFailure != null) {
        return reviewFailure;
      }
      if (existingUserToOpen != null) {
        return null;
      }
      if (!similarityAccepted || isExactContactConflict) {
        return const AppFailure.cancelled();
      }

      final Result<AccessAdminItem> retry = await ref
          .read(accessAdminWorkspaceControllerProvider.notifier)
          .updateUserReviewed(
            excludeUserId,
            pending.copyWith(confirmSimilar: true),
          );
      final AppFailure? retryFailure = retry.when(
        success: (AccessAdminItem updated) {
          updatedUser ??= updated;
          return null;
        },
        failure: (AppFailure value) => value,
      );
      if (retryFailure != null &&
          retryFailure.category == AppFailureCategory.conflict) {
        return const AppFailure.cancelled();
      }
      if (retryFailure != null) {
        return retryFailure;
      }
      failure = null;
    }

    if (failure != null) {
      return failure;
    }
    return null;
  }

  final bool? saved = await showUserMutationDialog(
    context: context,
    ref: ref,
    mode: UserMutationMode.edit,
    state: state,
    initialUser: baseline,
    initialDetail: detail,
    onSubmit: (AccessAdminUserDraft draft, List<String> roleIds) async {
      final String? newPassword = draft.password;
      // A password-only change has no details to review or update.
      if (newPassword == null || _userDetailsChanged(baseline, draft)) {
        final AppFailure? detailsFailure = await saveDetails(
          draft.copyWith(clearPassword: true),
        );
        if (detailsFailure != null || existingUserToOpen != null) {
          return detailsFailure;
        }
      }
      if (newPassword == null) {
        return null;
      }
      final Result<void> passwordResult = await ref
          .read(accessAdminWorkspaceControllerProvider.notifier)
          .setUserPassword(excludeUserId, newPassword);
      final AppFailure? passwordFailure = passwordResult.when(
        success: (_) => null,
        failure: (AppFailure value) => value,
      );
      return passwordFailure;
    },
  );

  if (existingUserToOpen != null) {
    return existingUserToOpen;
  }
  if (saved == true) {
    return updatedUser ?? baseline;
  }
  return null;
}

/// Whether an edit changes anything the profile update sends. Phones compare by
/// digits because the field formats them.
bool _userDetailsChanged(AccessAdminItem baseline, AccessAdminUserDraft draft) {
  String text(String? value) => (value ?? '').trim();
  String digits(String? value) => text(value).replaceAll(RegExp(r'\D'), '');
  return text(draft.firstName) != text(baseline.firstName) ||
      text(draft.lastName) != text(baseline.lastName) ||
      text(draft.email).toLowerCase() != text(baseline.email).toLowerCase() ||
      digits(draft.phone) != digits(baseline.phone) ||
      text(draft.positionTitle) != text(baseline.positionTitle) ||
      text(draft.status).toUpperCase() != text(baseline.status).toUpperCase() ||
      text(draft.facilityId) != text(baseline.facilityId);
}

Future<AccessAdminItem?> openAccessAdminCreateRoleDialog(
  BuildContext context,
  WidgetRef ref,
  AccessAdminWorkspaceState state,
) async {
  final AppAccessPolicy accessPolicy = ref.read(appAccessPolicyProvider);
  // Roles create ∩: tenant:admin (+ elevated) and workspace canWrite.
  if (!canMutateAccessAdminRoles(
    accessPolicy,
    workspaceCanWrite: state.data.permissions.canWrite,
  )) {
    return null;
  }
  final bool isCrossTenantAdmin = accessPolicy.canCreateTenant();
  final bool allowTenantWideScope = accessPolicy.canCreateTenantWideRole();
  final String? workspaceTenantId = state.query.tenantId;
  final String? sessionTenantId = ref
      .read(sessionStateProvider)
      .session
      ?.user
      ?.tenantId;
  final String? sessionFacilityId = ref
      .read(sessionStateProvider)
      .session
      ?.user
      ?.facilityId;
  final String? initialTenantId = isCrossTenantAdmin
      ? workspaceTenantId
      : (workspaceTenantId ?? sessionTenantId);
  final String? initialFacilityId =
      state.query.facilityId ??
      (allowTenantWideScope ? null : sessionFacilityId);
  final bool needsFacilityScope = !allowTenantWideScope;
  final bool provideAllFacilitiesLoader = isCrossTenantAdmin;
  final bool provideTenantLoader =
      allowTenantWideScope ||
      (initialTenantId == null) ||
      !provideAllFacilitiesLoader;
  if (!context.mounted) {
    return null;
  }

  AccessAdminLookups? prefetched;
  if ((initialTenantId ?? '').isNotEmpty) {
    prefetched = await _prefetchRoleDialogLookups(
      ref,
      tenantId: initialTenantId!,
      facilityId: needsFacilityScope ? initialFacilityId : null,
      includeFacilities: needsFacilityScope || initialFacilityId != null,
    );
  }

  if (!context.mounted) {
    return null;
  }

  final AppLocalizations l10n = context.l10n;
  final String? sessionFacilityName = ref
      .read(sessionStateProvider)
      .session
      ?.user
      ?.facilityName;

  List<AccessAdminLookupOption> initialFacilityOptions =
      List<AccessAdminLookupOption>.from(
        prefetched?.facilities ?? state.data.lookups.facilities,
      );
  // HR / facility admins create exactly one facility-scoped role at their
  // session facility — never fan out across every campus in the tenant.
  if (needsFacilityScope && (sessionFacilityId ?? '').trim().isNotEmpty) {
    final String pinnedFacilityId = sessionFacilityId!.trim();
    final AccessAdminLookupOption? matched = _matchPinnedFacilityOption(
      options: initialFacilityOptions,
      pinnedFacilityId: pinnedFacilityId,
      sessionFacilityName: sessionFacilityName,
    );
    initialFacilityOptions = <AccessAdminLookupOption>[
      AccessAdminLookupOption(
        id: matched?.id ?? pinnedFacilityId,
        label: _facilityScopeUiLabel(
          l10n: l10n,
          sessionFacilityName: sessionFacilityName,
          optionLabel: matched?.label,
        ),
        displayName: matched?.displayName,
        permissionCount: matched?.permissionCount ?? 0,
        meta: matched?.meta ?? initialTenantId,
      ),
    ];
  }

  AccessAdminItem? createdRole;
  AccessAdminItem? existingRoleToOpen;
  final bool? saved = await showRoleMutationDialog(
    context: context,
    mode: RoleMutationMode.create,
    includePermissions: false,
    permissionLookups:
        prefetched?.permissions ?? state.data.lookups.permissions,
    initialFacilityOptions: initialFacilityOptions,
    loadTenantOptions: provideTenantLoader
        ? () => loadAccessAdminTenantOptions(
            ref,
            state,
            preferTenantFacilityApi: isCrossTenantAdmin,
          )
        : null,
    loadFacilityOptions: (String tenantId) async {
      final List<AccessAdminLookupOption> loaded =
          await loadAccessAdminFacilityOptions(ref, tenantId);
      if (!needsFacilityScope || (sessionFacilityId ?? '').trim().isEmpty) {
        return loaded;
      }
      final String pinnedFacilityId = sessionFacilityId!.trim();
      final AccessAdminLookupOption? matched = _matchPinnedFacilityOption(
        options: loaded,
        pinnedFacilityId: pinnedFacilityId,
        sessionFacilityName: sessionFacilityName,
      );
      return <AccessAdminLookupOption>[
        AccessAdminLookupOption(
          id: matched?.id ?? pinnedFacilityId,
          label: _facilityScopeUiLabel(
            l10n: l10n,
            sessionFacilityName: sessionFacilityName,
            optionLabel: matched?.label,
          ),
          displayName: matched?.displayName,
          permissionCount: matched?.permissionCount ?? 0,
          meta: matched?.meta ?? tenantId,
        ),
      ];
    },
    loadAllFacilityOptions: provideAllFacilitiesLoader
        ? () => loadAccessAdminAllFacilityOptions(ref, state)
        : null,
    tenantId: initialTenantId,
    facilityId: initialFacilityId,
    allowTenantWideScope: allowTenantWideScope,
    forceFacilityScope: !allowTenantWideScope,
    allowPlatformScope: isCrossTenantAdmin,
    allowTenantScope: allowTenantWideScope,
    onSubmit: (List<AccessAdminRoleDraft> drafts) async {
      // Facility-scoped create must never create more than one role.
      final List<AccessAdminRoleDraft> draftsToCreate = needsFacilityScope
          ? drafts.take(1).toList(growable: false)
          : drafts;
      for (final AccessAdminRoleDraft draft in draftsToCreate) {
        // Acceptance belongs to this exact scoped draft. Do not carry it to a
        // second tenant/facility target or a later Save after form edits.
        var similarityAccepted = draft.confirmSimilar;
        var pending = draft.copyWith(
          confirmSimilar: similarityAccepted,
        );

        if (!pending.confirmSimilar) {
          if (!context.mounted) {
            return const AppFailure.cancelled();
          }
          final AppFailure? reviewFailure = await _reviewRoleSimilarity(
            context,
            ref,
            pending: pending,
            onAccepted: () => similarityAccepted = true,
            onUseExisting: (AccessAdminItem role) {
              existingRoleToOpen = role;
            },
          );
          if (reviewFailure != null) {
            return reviewFailure;
          }
          if (existingRoleToOpen != null) {
            return null;
          }
          pending = pending.copyWith(confirmSimilar: similarityAccepted);
        }

        final Result<AccessAdminItem> result = await ref
            .read(accessAdminWorkspaceControllerProvider.notifier)
            .createRole(pending);
        AppFailure? failure = result.when(
          success: (AccessAdminItem created) {
            createdRole ??= created;
            return null;
          },
          failure: (AppFailure value) => value,
        );

        // Backend uniqueness is authoritative; never surface it as an inline
        // create-dialog conflict banner — reopen the dedicated review dialog.
        if (failure != null &&
            failure.category == AppFailureCategory.conflict) {
          if (!context.mounted) {
            return const AppFailure.cancelled();
          }

          final bool isExactNameConflict = _isRoleDuplicateNameConflict(failure);
          final bool alreadyConfirmed = pending.confirmSimilar;
          // similar_exists after confirm_similar should not reopen an empty
          // "no similar" dialog — create once was already attempted.
          if (alreadyConfirmed && !isExactNameConflict) {
            return failure;
          }

          similarityAccepted = false;
          final AppFailure? reviewFailure = await _reviewRoleSimilarity(
            context,
            ref,
            pending: pending.copyWith(confirmSimilar: false),
            forceReviewMatches: true,
            conflictEntries: failure is ConflictFailure
                ? failure.conflictEntries
                : const <Map<String, Object?>>[],
            onAccepted: () => similarityAccepted = true,
            onUseExisting: (AccessAdminItem role) {
              existingRoleToOpen = role;
            },
          );
          if (reviewFailure != null) {
            return reviewFailure;
          }
          if (existingRoleToOpen != null) {
            return null;
          }
          if (!similarityAccepted || isExactNameConflict) {
            return const AppFailure.cancelled();
          }

          final Result<AccessAdminItem> retry = await ref
              .read(accessAdminWorkspaceControllerProvider.notifier)
              .createRole(pending.copyWith(confirmSimilar: true));
          final AppFailure? retryFailure = retry.when(
            success: (AccessAdminItem created) {
              createdRole ??= created;
              return null;
            },
            failure: (AppFailure value) => value,
          );
          if (retryFailure != null &&
              retryFailure.category == AppFailureCategory.conflict) {
            // Exact conflicts cannot be bypassed with confirm_similar.
            return const AppFailure.cancelled();
          }
          if (retryFailure != null) {
            return retryFailure;
          }
          failure = null;
        }

        if (failure != null) {
          return failure;
        }
        if (existingRoleToOpen != null) {
          return null;
        }
      }
      return null;
    },
  );

  if (existingRoleToOpen != null) {
    return existingRoleToOpen;
  }
  if (saved == true) {
    return createdRole;
  }
  return null;
}

Future<AppFailure?> _reviewRoleSimilarity(
  BuildContext context,
  WidgetRef ref, {
  required AccessAdminRoleDraft pending,
  required VoidCallback onAccepted,
  required ValueChanged<AccessAdminItem> onUseExisting,
  String? excludeRoleId,
  bool forceReviewMatches = false,
  List<Map<String, Object?>> conflictEntries = const <Map<String, Object?>>[],
}) async {
  final _RoleSimilarityPeers peerLookup = await _loadRoleSimilarityPeers(
    ref,
    tenantId: pending.tenantId,
    name: pending.name,
    displayName: pending.displayName,
  );
  if (!context.mounted) {
    return const AppFailure.cancelled();
  }
  // A failed peer lookup must never be reported as "no similar role found".
  if (peerLookup.failure != null) {
    return peerLookup.failure;
  }
  final List<AccessAdminItem> peers = peerLookup.items;

  String? proposedFacilityName;
  String? proposedTenantName;
  for (final AccessAdminItem peer in peers) {
    if (proposedFacilityName == null &&
        pending.facilityId != null &&
        peer.facilityId == pending.facilityId &&
        (peer.facilityName ?? '').trim().isNotEmpty) {
      proposedFacilityName = peer.facilityName;
    }
    if (proposedTenantName == null &&
        pending.tenantId != null &&
        peer.tenantId == pending.tenantId &&
        (peer.tenantName ?? '').trim().isNotEmpty) {
      proposedTenantName = peer.tenantName;
    }
  }

  final RoleDuplicateCheckResult check = checkRoleDuplicates(
    name: pending.name,
    displayName: pending.displayName ?? '',
    description: pending.description,
    tenantId: pending.tenantId,
    facilityId: pending.facilityId,
    tenantName: proposedTenantName,
    facilityName: proposedFacilityName,
    scope: pending.scope,
    existing: peers,
    excludeRoleId: excludeRoleId,
  );

  List<RoleSimilarityMatch> reviewMatches;
  if (forceReviewMatches) {
    reviewMatches = check.similarMatches;
  } else if (check.hasExactConflict) {
    reviewMatches = check.similarMatches
        .where(
          (RoleSimilarityMatch match) =>
              match.exactNameConflict || match.exactDisplayNameConflict,
        )
        .toList(growable: false);
    if (reviewMatches.isEmpty) {
      reviewMatches = check.similarMatches;
    }
  } else {
    reviewMatches = check.overridableMatches;
  }

  // When peer load missed identity rows, hydrate from the authoritative
  // backend uniqueness payload so conflict reopen is never empty "no similar".
  if (reviewMatches.isEmpty && conflictEntries.isNotEmpty) {
    reviewMatches = roleSimilarityMatchesFromConflictEntries(conflictEntries);
  }

  final bool hasExactConflict =
      check.hasExactConflict ||
      reviewMatches.any(
        (RoleSimilarityMatch match) =>
            match.exactNameConflict || match.exactDisplayNameConflict,
      );

  // Force-review after backend conflict must not reopen a false empty
  // "no similar" confirmation — that loops Continue create without creating.
  if (forceReviewMatches && reviewMatches.isEmpty) {
    return AppFailure.conflict(code: 'DUPLICATE_NAME');
  }

  // Create always opens review (including zero matches). Force-review is used
  // when the backend returns a uniqueness conflict after the client scan.
  final RoleSimilarityDialogResult review = await showRoleSimilarityDialog(
    context,
    proposed: RoleSimilarityProposedValues(
      name: pending.name,
      displayName: pending.displayName ?? '',
      description: pending.description,
      tenantId: pending.tenantId,
      facilityId: pending.facilityId,
      tenantName: proposedTenantName,
      facilityName: proposedFacilityName,
      scope: pending.scope,
    ),
    matches: reviewMatches,
    allowProceed: !hasExactConflict,
  );
  if (!context.mounted) {
    return const AppFailure.cancelled();
  }

  switch (review.action) {
    case RoleSimilarityAction.cancel:
      return const AppFailure.cancelled();
    case RoleSimilarityAction.useExisting:
      final AccessAdminItem? existing = review.selectedRole?.role;
      if (existing != null) {
        onUseExisting(existing);
      }
      return null;
    case RoleSimilarityAction.proceed:
      onAccepted();
      return null;
  }
}

bool _isRoleDuplicateNameConflict(AppFailure failure) {
  final String code = failure.code.trim().toUpperCase();
  if (code == 'DUPLICATE_NAME' || code.endsWith('_DUPLICATE_NAME')) {
    return true;
  }
  if (failure is ConflictFailure && failure.conflictEntries.isNotEmpty) {
    return failure.conflictEntries.any(
      (Map<String, Object?> entry) =>
          entry['exactNameConflict'] == true ||
          entry['exactDisplayNameConflict'] == true ||
          entry['isExact'] == true,
    );
  }
  return false;
}

/// Matches backend `ROLE_SIMILARITY_LOOKUP_LIMIT`.
const int _roleSimilarityPeerLimit = 500;

@immutable
final class _RoleSimilarityPeers {
  const _RoleSimilarityPeers({required this.items, this.failure});

  final List<AccessAdminItem> items;
  final AppFailure? failure;
}

Future<_RoleSimilarityPeers> _loadRoleSimilarityPeers(
  WidgetRef ref, {
  String? tenantId,
  String? name,
  String? displayName,
}) async {
  // Load tenant-wide (all facilities) or all tenants for platform proposals so
  // org/facility peers are visible. Same-scope hard conflicts remain enforced
  // in checkRoleDuplicates. Search-biased pages catch identity peers that sit
  // past the alphabetical ROLE_SIMILARITY_LOOKUP_LIMIT window.
  final bool allTenants = tenantId == null || tenantId.trim().isEmpty;
  final Map<String, AccessAdminItem> alphabeticalPeers =
      <String, AccessAdminItem>{};
  final Map<String, AccessAdminItem> searchedPeers =
      <String, AccessAdminItem>{};

  Future<AppFailure?> appendPeers({
    required bool requestAllTenants,
    String? scopedTenantId,
    String search = '',
    required Map<String, AccessAdminItem> target,
  }) async {
    // Pages stay within the backend `limit` ceiling; a larger page size is
    // rejected by validation and would leave review with zero peers.
    var request = const AppPageRequest(pageSize: AppPageRequest.maxPageSize);
    while (target.length < _roleSimilarityPeerLimit) {
      final Result<AccessAdminWorkspaceData> result = await ref
          .read(accessAdminRepositoryProvider)
          .getWorkspace(
            AccessAdminWorkspaceQuery(
              panel: AccessAdminPanel.roles,
              resource: AccessAdminResource.roles,
              tenantId: requestAllTenants ? null : scopedTenantId,
              allTenants: requestAllTenants,
              allFacilities: true,
              includeDeleted: true,
              lean: true,
              skipLookups: true,
              search: search,
              pageRequest: request,
            ),
          );

      // A tenant-context-required response carries zero items on success; scoring
      // against it would look like "no similar found".
      final AppFailure? failure = result.when(
        success: (AccessAdminWorkspaceData data) =>
            data.state == 'tenant_context_required'
            ? AppFailure.unexpectedResponse()
            : null,
        failure: (AppFailure value) => value,
      );
      if (failure != null) {
        return failure;
      }

      final AppPage<AccessAdminItem> page = result.when(
        success: (AccessAdminWorkspaceData data) => data.page,
        failure: (_) => const AppPage<AccessAdminItem>(
          items: <AccessAdminItem>[],
          request: AppPageRequest(),
        ),
      );
      for (final AccessAdminItem item in page.items) {
        // Tenant proposals keep same-tenant and platform peers only so the
        // client peer set mirrors BE uniqueness filters.
        if (!allTenants && requestAllTenants) {
          final String? itemTenant = item.tenantId?.trim();
          if (itemTenant != null &&
              itemTenant.isNotEmpty &&
              itemTenant != tenantId) {
            continue;
          }
        }
        final String key = <String?>[
          item.id,
          item.mutationId,
          item.resourceUuid,
          item.effectiveDisplayId,
        ].whereType<String>().firstWhere(
          (String value) => value.trim().isNotEmpty,
          orElse: () => item.title,
        );
        target.putIfAbsent(key, () => item);
        if (target.length >= _roleSimilarityPeerLimit) {
          break;
        }
      }
      if (!page.hasNextPage || page.items.isEmpty) {
        break;
      }
      request = request.next();
    }
    return null;
  }

  final AppFailure? baseFailure = await appendPeers(
    requestAllTenants: allTenants,
    scopedTenantId: allTenants ? null : tenantId,
    target: alphabeticalPeers,
  );
  if (baseFailure != null) {
    return _RoleSimilarityPeers(
      items: alphabeticalPeers.values.toList(growable: false),
      failure: baseFailure,
    );
  }

  final Set<String> searchTerms = <String>{
    if ((name ?? '').trim().isNotEmpty) name!.trim(),
    if ((displayName ?? '').trim().isNotEmpty) displayName!.trim(),
  };
  for (final String term in searchTerms) {
    final Map<String, AccessAdminItem> scopedSearchPeers =
        <String, AccessAdminItem>{};
    final AppFailure? scopedSearchFailure = await appendPeers(
      requestAllTenants: allTenants,
      scopedTenantId: allTenants ? null : tenantId,
      search: term,
      target: scopedSearchPeers,
    );
    searchedPeers.addAll(scopedSearchPeers);
    if (scopedSearchFailure != null) {
      return _RoleSimilarityPeers(
        items: <AccessAdminItem>[
          ...searchedPeers.values,
          ...alphabeticalPeers.values,
        ],
        failure: scopedSearchFailure,
      );
    }
    // Tenant/facility proposals: also search platform-wide so platform peers
    // matching the identity are not missed (BE uniqueness includes them).
    if (!allTenants) {
      final Map<String, AccessAdminItem> platformSearchPeers =
          <String, AccessAdminItem>{};
      final AppFailure? platformSearchFailure = await appendPeers(
        requestAllTenants: true,
        search: term,
        target: platformSearchPeers,
      );
      searchedPeers.addAll(platformSearchPeers);
      if (platformSearchFailure != null) {
        return _RoleSimilarityPeers(
          items: <AccessAdminItem>[
            ...searchedPeers.values,
            ...alphabeticalPeers.values,
          ],
          failure: platformSearchFailure,
        );
      }
    }
  }

  // Search hits must win the fixed peer budget. Previously the alphabetical
  // page filled the shared map to 500, so these identity searches never ran.
  final Map<String, AccessAdminItem> prioritizedPeers =
      <String, AccessAdminItem>{...searchedPeers};
  for (final MapEntry<String, AccessAdminItem> entry
      in alphabeticalPeers.entries) {
    prioritizedPeers.putIfAbsent(entry.key, () => entry.value);
  }
  return _RoleSimilarityPeers(
    items: prioritizedPeers.values
        .take(_roleSimilarityPeerLimit)
        .toList(growable: false),
  );
}

Future<AccessAdminItem?> openAccessAdminEditRoleDialog(
  BuildContext context,
  WidgetRef ref,
  AccessAdminWorkspaceState state,
  AccessAdminItem role,
) async {
  if (!context.mounted) {
    return null;
  }
  if (role.isSystemCritical) {
    final AppAccessPolicy accessPolicy = ref.read(appAccessPolicyProvider);
    if (!canMutateAccessAdminSystemCatalog(
      accessPolicy,
      isSystemCritical: true,
    )) {
      return null;
    }
  }

  final AppAccessPolicy accessPolicy = ref.read(appAccessPolicyProvider);
  // Roles update ∩: tenant:admin (+ elevated) and workspace canWrite.
  if (!canMutateAccessAdminRoles(
    accessPolicy,
    workspaceCanWrite: state.data.permissions.canWrite,
  )) {
    return null;
  }
  final bool isCrossTenantAdmin = accessPolicy.canCreateTenant();
  final bool allowTenantWideScope = accessPolicy.canCreateTenantWideRole();
  // Prefill from the role's actual ABAC scope — never session/workspace tenant
  // for platform roles (null tenant_id).
  final String? roleTenantId = role.tenantId;
  final String? roleFacilityId = role.facilityId;
  final bool needsFacilityScope = !allowTenantWideScope && !role.isPlatformScopedRole;
  final bool provideAllFacilitiesLoader = isCrossTenantAdmin;
  final bool provideTenantLoader =
      allowTenantWideScope ||
      role.isTenantScopedRole ||
      ((roleTenantId ?? '').isEmpty && !role.isPlatformScopedRole) ||
      !provideAllFacilitiesLoader;

  // Permissions are managed from role details — edit only identity/scope.
  AccessAdminLookups? prefetched;
  if ((roleTenantId ?? '').isNotEmpty) {
    prefetched = await _prefetchRoleDialogLookups(
      ref,
      tenantId: roleTenantId!,
      facilityId: roleFacilityId,
      includeFacilities: needsFacilityScope || roleFacilityId != null,
      includePermissions: false,
    );
  }

  if (!context.mounted) {
    return null;
  }

  final String excludeRoleId =
      role.mutationId.trim().isNotEmpty ? role.mutationId : role.id;
  final String baselineName = (role.name ?? role.title).trim();
  final String baselineDisplayName = (role.displayName ?? role.title).trim();
  final String baselineDescription = (role.subtitle ?? '').trim();
  final String? baselineTenantId = role.tenantId;
  final String? baselineFacilityId = role.facilityId;
  final String? baselineScope = role.isPlatformScopedRole
      ? 'platform'
      : (role.isFacilityScopedRole ? 'facility' : 'tenant');

  AccessAdminItem? updatedRole;
  final bool? saved = await showRoleMutationDialog(
    context: context,
    mode: RoleMutationMode.edit,
    includePermissions: false,
    initialFacilityOptions:
        prefetched?.facilities ?? state.data.lookups.facilities,
    initialName: role.name ?? role.title,
    initialDisplayName: role.displayName,
    initialDescription: role.subtitle,
    tenantId: roleTenantId,
    facilityId: roleFacilityId,
    allowTenantWideScope: allowTenantWideScope,
    forceFacilityScope: needsFacilityScope,
    allowPlatformScope: isCrossTenantAdmin,
    allowTenantScope: allowTenantWideScope,
    allowFacilityScope: true,
    loadTenantOptions: provideTenantLoader
        ? () => loadAccessAdminTenantOptions(
            ref,
            state,
            preferTenantFacilityApi: isCrossTenantAdmin,
          )
        : null,
    loadFacilityOptions: (String resolvedTenantId) =>
        loadAccessAdminFacilityOptions(ref, resolvedTenantId),
    loadAllFacilityOptions: provideAllFacilitiesLoader
        ? () => loadAccessAdminAllFacilityOptions(ref, state)
        : null,
    onSubmit: (List<AccessAdminRoleDraft> drafts) async {
      final AccessAdminRoleDraft draft = drafts.first;
      final bool identityChanged =
          draft.name.trim() != baselineName ||
          (draft.displayName ?? '').trim() != baselineDisplayName ||
          (draft.description ?? '').trim() != baselineDescription ||
          (draft.tenantId ?? '') != (baselineTenantId ?? '') ||
          (draft.facilityId ?? '') != (baselineFacilityId ?? '') ||
          (draft.scope ?? '') != (baselineScope ?? '');

      var similarityAccepted = draft.confirmSimilar;
      var pending = draft.copyWith(confirmSimilar: similarityAccepted);

      // Edit skips empty review when identity is unchanged; create always opens.
      if (identityChanged && !pending.confirmSimilar) {
        if (!context.mounted) {
          return const AppFailure.cancelled();
        }
        final AppFailure? reviewFailure = await _reviewRoleSimilarity(
          context,
          ref,
          pending: pending,
          excludeRoleId: excludeRoleId,
          onAccepted: () => similarityAccepted = true,
          onUseExisting: (_) {
            // Edit has no "use existing" handoff — treat as cancel.
          },
        );
        if (reviewFailure != null) {
          return reviewFailure;
        }
        if (!similarityAccepted) {
          return const AppFailure.cancelled();
        }
        pending = pending.copyWith(confirmSimilar: true);
      }

      AppFailure? failure = await _submitAccessAdminRoleUpdate(
        ref,
        role.id,
        pending,
      );

      if (failure != null &&
          failure.category == AppFailureCategory.conflict) {
        if (!context.mounted) {
          return const AppFailure.cancelled();
        }

        final bool isExactNameConflict = _isRoleDuplicateNameConflict(failure);
        final bool alreadyConfirmed = pending.confirmSimilar;
        if (alreadyConfirmed && !isExactNameConflict) {
          return failure;
        }

        similarityAccepted = false;
        final AppFailure? reviewFailure = await _reviewRoleSimilarity(
          context,
          ref,
          pending: pending.copyWith(confirmSimilar: false),
          excludeRoleId: excludeRoleId,
          forceReviewMatches: true,
          conflictEntries: failure is ConflictFailure
              ? failure.conflictEntries
              : const <Map<String, Object?>>[],
          onAccepted: () => similarityAccepted = true,
          onUseExisting: (_) {},
        );
        if (reviewFailure != null) {
          return reviewFailure;
        }
        if (!similarityAccepted || isExactNameConflict) {
          return const AppFailure.cancelled();
        }

        failure = await _submitAccessAdminRoleUpdate(
          ref,
          role.id,
          pending.copyWith(confirmSimilar: true),
        );
        if (failure != null &&
            failure.category == AppFailureCategory.conflict) {
          return const AppFailure.cancelled();
        }
        if (failure == null) {
          updatedRole = accessAdminRoleAfterEdit(
            role,
            pending.copyWith(confirmSimilar: true),
          );
        }
        return failure;
      }

      if (failure == null) {
        updatedRole = accessAdminRoleAfterEdit(role, pending);
      }
      return failure;
    },
  );

  if (saved == true) {
    return updatedRole ?? role;
  }
  return null;
}

/// Local projection of [role] after a successful identity/scope edit.
@visibleForTesting
AccessAdminItem accessAdminRoleAfterEdit(
  AccessAdminItem role,
  AccessAdminRoleDraft draft,
) {
  final String displayName = (draft.displayName ?? draft.name).trim();
  final String scope = (draft.scope ?? '').trim().toLowerCase();
  final bool isPlatform =
      scope == 'platform' ||
      ((draft.tenantId ?? '').trim().isEmpty &&
          (draft.facilityId ?? '').trim().isEmpty);
  final bool isFacility =
      scope == 'facility' || (draft.facilityId ?? '').trim().isNotEmpty;

  return AccessAdminItem(
    id: role.id,
    resource: role.resource,
    displayId: role.displayId,
    title: displayName.isNotEmpty ? displayName : role.title,
    resourceUuid: role.resourceUuid,
    name: draft.name.trim().isNotEmpty ? draft.name.trim() : role.name,
    displayName: displayName.isNotEmpty ? displayName : role.displayName,
    subtitle: draft.description,
    tenantId: isPlatform ? null : draft.tenantId ?? role.tenantId,
    tenantName: isPlatform ? null : role.tenantName,
    facilityId: isFacility ? draft.facilityId : null,
    facilityName: isFacility ? role.facilityName : null,
    roleScope: isPlatform
        ? 'platform'
        : (isFacility ? 'facility' : 'tenant'),
    permissionCount: role.permissionCount,
    permissions: role.permissions,
    userCount: role.userCount,
    isClinicalFlowRole: role.isClinicalFlowRole,
    isSystemCritical: role.isSystemCritical,
    deletedAt: role.deletedAt,
    updatedAt: DateTime.now(),
  );
}

Future<AppFailure?> _submitAccessAdminRoleUpdate(
  WidgetRef ref,
  String roleId,
  AccessAdminRoleDraft draft,
) async {
  return ref
      .read(accessAdminWorkspaceControllerProvider.notifier)
      .updateRole(roleId, draft);
}

Future<AccessAdminLookups?> _prefetchRoleDialogLookups(
  WidgetRef ref, {
  required String tenantId,
  String? facilityId,
  bool includeFacilities = false,
  bool includePermissions = true,
}) async {
  final List<String> include = <String>[
    if (includePermissions) 'permissions',
    if (includeFacilities) 'facilities',
  ];
  if (include.isEmpty) {
    return null;
  }
  final Result<AccessAdminLookups> result = await ref
      .read(accessAdminRepositoryProvider)
      .getReferenceData(
        tenantId: tenantId,
        facilityId: facilityId,
        include: include,
      );
  return result.when(
    success: (AccessAdminLookups lookups) => lookups,
    failure: (_) => null,
  );
}

Future<Result<List<AccessAdminLookupOption>>> _loadAccessAdminPermissionLookups(
  WidgetRef ref,
  AccessAdminWorkspaceState state, {
  String? tenantId,
  String? facilityId,
  bool forceRefresh = false,
}) async {
  final String? resolvedTenantId = tenantId ?? state.query.tenantId;
  final String? resolvedFacilityId = facilityId ?? state.query.facilityId;
  if ((resolvedTenantId ?? '').isEmpty) {
    return const Result<List<AccessAdminLookupOption>>.success(
      <AccessAdminLookupOption>[],
    );
  }

  if (!forceRefresh &&
      resolvedTenantId == state.query.tenantId &&
      resolvedFacilityId == state.query.facilityId &&
      state.data.lookups.permissions.isNotEmpty) {
    return Result<List<AccessAdminLookupOption>>.success(
      state.data.lookups.permissions,
    );
  }

  final Result<AccessAdminLookups> result = await ref
      .read(accessAdminRepositoryProvider)
      .getReferenceData(
        tenantId: resolvedTenantId,
        facilityId: resolvedFacilityId,
        include: const <String>['permissions'],
        forceRefresh: forceRefresh,
      );

  return result.when(
    success: (AccessAdminLookups lookups) =>
        Result<List<AccessAdminLookupOption>>.success(lookups.permissions),
    failure: (AppFailure failure) =>
        Result<List<AccessAdminLookupOption>>.failure(failure),
  );
}

Future<List<AccessAdminLookupOption>> loadAccessAdminAllFacilityOptions(
  WidgetRef ref,
  AccessAdminWorkspaceState state,
) async {
  final List<AccessAdminLookupOption> tenants =
      await loadAccessAdminTenantOptions(
        ref,
        state,
        preferTenantFacilityApi: true,
      );
  if (tenants.isEmpty) {
    return const <AccessAdminLookupOption>[];
  }

  final List<AccessAdminLookupOption> facilities = <AccessAdminLookupOption>[];
  for (final AccessAdminLookupOption tenant in tenants) {
    final List<AccessAdminLookupOption> tenantFacilities =
        await loadAccessAdminFacilityOptions(ref, tenant.id);
    for (final AccessAdminLookupOption facility in tenantFacilities) {
      facilities.add(
        AccessAdminLookupOption(
          id: facility.id,
          label: tenants.length > 1
              ? '${facility.label} (${tenant.label})'
              : facility.label,
          meta: tenant.id,
        ),
      );
    }
  }
  return facilities;
}

bool _looksLikeUuid(String value) {
  return RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value.trim());
}

/// Never surface raw UUIDs in the create-role Scope checkbox list.
String _facilityScopeUiLabel({
  required AppLocalizations l10n,
  String? sessionFacilityName,
  String? optionLabel,
}) {
  final String sessionName = (sessionFacilityName ?? '').trim();
  if (sessionName.isNotEmpty) {
    return sessionName;
  }
  final String optionName = (optionLabel ?? '').trim();
  if (optionName.isNotEmpty && !_looksLikeUuid(optionName)) {
    return optionName;
  }
  return l10n.tenantFacilitySetupTabFacility;
}

AccessAdminLookupOption? _matchPinnedFacilityOption({
  required List<AccessAdminLookupOption> options,
  required String pinnedFacilityId,
  String? sessionFacilityName,
}) {
  for (final AccessAdminLookupOption option in options) {
    if (option.id == pinnedFacilityId) {
      return option;
    }
  }
  final String sessionName = (sessionFacilityName ?? '').trim().toLowerCase();
  if (sessionName.isNotEmpty) {
    for (final AccessAdminLookupOption option in options) {
      if (option.label.trim().toLowerCase() == sessionName) {
        return option;
      }
    }
  }
  if (options.length == 1) {
    return options.first;
  }
  return null;
}

Future<List<AccessAdminLookupOption>> loadAccessAdminFacilityOptions(
  WidgetRef ref,
  String tenantId,
) async {
  final Result<AccessAdminLookups> cached = await ref
      .read(accessAdminRepositoryProvider)
      .getReferenceData(
        tenantId: tenantId,
        include: const <String>['facilities'],
      );
  final List<AccessAdminLookupOption>? fromReference = cached.when(
    success: (AccessAdminLookups lookups) =>
        lookups.facilities.isEmpty ? null : lookups.facilities,
    failure: (_) => null,
  );
  if (fromReference != null) {
    return fromReference
        .map(
          (AccessAdminLookupOption facility) => AccessAdminLookupOption(
            id: facility.id,
            label: facility.label,
            displayName: facility.displayName,
            permissionCount: facility.permissionCount,
            meta: tenantId,
          ),
        )
        .toList(growable: false);
  }

  final Result<AppPage<FacilityProfile>> result = await ref
      .read(tenantFacilityRepositoryProvider)
      .listFacilities(
        tenantId: tenantId,
        request: const AppPageRequest(pageSize: 100),
      );
  return result.when(
    success: (AppPage<FacilityProfile> page) => page.items
        .map(
          (FacilityProfile facility) {
            final String name = facility.name.trim();
            final String publicId = facility.id.trim();
            final String mutationId = facility.mutationId.trim();
            return AccessAdminLookupOption(
              // Prefer public id for UI identity; mutation id remains API-safe.
              id: publicId.isNotEmpty ? publicId : mutationId,
              label: name.isNotEmpty
                  ? name
                  : (publicId.isNotEmpty && !_looksLikeUuid(publicId)
                        ? publicId
                        : mutationId),
              meta: tenantId,
            );
          },
        )
        .toList(growable: false),
    failure: (_) => const <AccessAdminLookupOption>[],
  );
}

Future<List<AccessAdminLookupOption>> loadAccessAdminTenantOptions(
  WidgetRef ref,
  AccessAdminWorkspaceState state, {
  bool preferTenantFacilityApi = false,
}) async {
  if (!preferTenantFacilityApi && state.data.lookups.tenants.isNotEmpty) {
    return state.data.lookups.tenants;
  }

  if (preferTenantFacilityApi || state.data.lookups.tenants.isEmpty) {
    final Result<AppPage<TenantProfile>> tenantPageResult = await ref
        .read(tenantFacilityRepositoryProvider)
        .listTenants(request: const AppPageRequest(pageSize: 100));
    final List<AccessAdminLookupOption>? tenantFacilityOptions =
        tenantPageResult.when(
          success: (AppPage<TenantProfile> page) => page.items
              .map(
                (TenantProfile tenant) => AccessAdminLookupOption(
                  id: tenant.mutationId,
                  label: tenant.name,
                ),
              )
              .toList(growable: false),
          failure: (_) => null,
        );
    if (tenantFacilityOptions != null && tenantFacilityOptions.isNotEmpty) {
      return tenantFacilityOptions;
    }
  }

  if (state.data.lookups.tenants.isNotEmpty) {
    return state.data.lookups.tenants;
  }

  final Result<AccessAdminLookups> result = await ref
      .read(accessAdminRepositoryProvider)
      .getReferenceData();
  return result.when(
    success: (AccessAdminLookups lookups) => lookups.tenants,
    failure: (_) => const <AccessAdminLookupOption>[],
  );
}
