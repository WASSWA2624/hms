import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final String dialogsSource = File(
    'lib/features/access_admin/presentation/widgets/access_admin_dialogs.dart',
  ).readAsStringSync();
  final String similarityDialogSource = File(
    'lib/features/access_admin/presentation/widgets/user_similarity_dialog.dart',
  ).readAsStringSync();
  final String managementSource = File(
    'lib/features/access_admin/presentation/widgets/access_admin_management_dialogs.dart',
  ).readAsStringSync();
  final String mutationDialogSource = File(
    'lib/features/access_admin/presentation/widgets/user_mutation_dialog.dart',
  ).readAsStringSync();

  final String createUserSource = dialogsSource.substring(
    dialogsSource.indexOf(
      'Future<AccessAdminItem?> openAccessAdminCreateUserDialog(',
    ),
    dialogsSource.indexOf('Future<AppFailure?> _reviewUserSimilarity('),
  );

  test('create user always opens similarity review before create API', () {
    expect(createUserSource.contains('_reviewUserSimilarity'), isTrue);
    expect(
      createUserSource.contains(
        'Create always opens the review before persisting',
      ),
      isTrue,
    );
    expect(
      dialogsSource.contains('return const AppFailure.cancelled();'),
      isTrue,
      reason: 'Cancel must not surface as validation/conflict failure',
    );
    expect(
      createUserSource.contains('createUserReviewed'),
      isTrue,
      reason: 'Create path returns an AccessAdminItem for details handoff',
    );
  });

  test('create user returns Future<AccessAdminItem?> like role create', () {
    expect(
      dialogsSource.contains(
        'Future<AccessAdminItem?> openAccessAdminCreateUserDialog(',
      ),
      isTrue,
    );
    expect(createUserSource.contains('return createdUser;'), isTrue);
    expect(createUserSource.contains('return existingUserToOpen;'), isTrue);
  });

  test('backend uniqueness conflict reopens similarity review with hydration', () {
    expect(createUserSource.contains('forceReviewMatches: true'), isTrue);
    expect(
      createUserSource.contains(
        'failure.category == AppFailureCategory.conflict',
      ),
      isTrue,
    );
    final String reviewSource = dialogsSource.substring(
      dialogsSource.indexOf('Future<AppFailure?> _reviewUserSimilarity('),
      dialogsSource.indexOf('bool _isUserDuplicateContactConflict('),
    );
    expect(
      reviewSource.contains('userSimilarityMatchesFromConflictEntries'),
      isTrue,
      reason: '409 match payloads must hydrate empty peer reviews',
    );
    expect(
      reviewSource.contains(
        'Force-review after backend conflict must not reopen a false empty',
      ),
      isTrue,
    );
  });

  test('exact contact conflict cannot be bypassed with confirm_similar', () {
    expect(createUserSource.contains('_isUserDuplicateContactConflict'), isTrue);
    expect(
      createUserSource.contains('!similarityAccepted || isExactContactConflict'),
      isTrue,
    );
    expect(
      createUserSource.contains(
        'Exact contact conflicts cannot be bypassed with confirm_similar.',
      ),
      isTrue,
    );
  });

  test('similarity dialog surfaces overall and field-level scores', () {
    expect(
      similarityDialogSource.contains(
        'accessAdminSimilarUserOverallSimilarityLabel',
      ),
      isTrue,
    );
    expect(similarityDialogSource.contains('match.fieldComparisons'), isTrue);
    expect(
      similarityDialogSource.contains('showAppSimilarityReviewDialog'),
      isTrue,
    );
    expect(
      similarityDialogSource.contains(
        'blockProceed: !allowProceed || hasExactConflict',
      ),
      isTrue,
    );
    expect(
      similarityDialogSource.contains('UserSimilarityAction.useExisting'),
      isTrue,
    );
    expect(
      similarityDialogSource.contains('UserSimilarityAction.proceed'),
      isTrue,
    );
  });

  final String peerLoaderSource = dialogsSource.substring(
    dialogsSource.indexOf('Future<_UserSimilarityPeers> _loadUserSimilarityPeers('),
    dialogsSource.indexOf('Future<AccessAdminItem?> openAccessAdminEditUserDialog('),
  );

  test('similarity peer load is not facility-narrowed', () {
    expect(peerLoaderSource.contains('allFacilities: true'), isTrue);
    expect(
      peerLoaderSource.contains('facilityId:'),
      isFalse,
      reason: 'Peer query must not narrow to the draft facility',
    );
  });

  test('peer pages stay within the backend limit ceiling', () {
    expect(
      peerLoaderSource.contains(
        'AppPageRequest(pageSize: AppPageRequest.maxPageSize)',
      ),
      isTrue,
      reason: 'A larger limit is rejected by workspace query validation',
    );
    expect(peerLoaderSource.contains('request = request.next()'), isTrue);
    expect(
      dialogsSource.contains('_userSimilarityPeerLimit = 500'),
      isTrue,
      reason: 'Client peer budget must match USER_SIMILARITY_LOOKUP_LIMIT',
    );
  });

  test('peer load is search-biased for proposed identity', () {
    expect(peerLoaderSource.contains('search: search'), isTrue);
    expect(peerLoaderSource.contains('searchTerms'), isTrue);
    expect(peerLoaderSource.contains('alphabeticalPeers'), isTrue);
    expect(peerLoaderSource.contains('searchedPeers'), isTrue);
    expect(
      peerLoaderSource.indexOf('...searchedPeers') <
          peerLoaderSource.indexOf('...alphabeticalPeers'),
      isTrue,
      reason: 'Identity search hits must win the fixed 500-peer budget',
    );
  });

  test('failed peer lookup surfaces an error instead of no-similar', () {
    expect(
      dialogsSource.contains(
        'A failed peer lookup must never be reported as "no similar user found".',
      ),
      isTrue,
    );
    expect(dialogsSource.contains('return peerLookup.failure;'), isTrue);
    expect(
      dialogsSource.contains("data.state == 'tenant_context_required'"),
      isTrue,
      reason: 'Scope-required responses must not be treated as zero peers',
    );
  });

  test('similarity acceptance is scoped to each submitted draft', () {
    expect(
      createUserSource.contains('var similarityAccepted = draft.confirmSimilar;'),
      isTrue,
    );
  });

  test('create assigns roles with the account; edit omits roles and sets passwords apart', () {
    expect(
      mutationDialogSource.contains('AppRoleAssignmentPicker('),
      isTrue,
      reason: 'Roles are chosen on create so the API writes them atomically',
    );
    expect(mutationDialogSource.contains('if (isCreate) ...<Widget>['), isTrue);
    expect(
      mutationDialogSource.contains('if (mode == UserMutationMode.edit) ...<Widget>['),
      isFalse,
      reason: 'Edit manages roles and direct permissions in User Details',
    );
    expect(mutationDialogSource.contains('roleIds: roleIds'), isTrue);
    expect(
      mutationDialogSource.contains('showNewPasswordField'),
      isTrue,
      reason: 'Edit sends a password only when an admin enters a new one',
    );
    expect(
      mutationDialogSource.contains('permissionIds:'),
      isFalse,
      reason: 'Direct permissions stay in User Details',
    );
    final String repositorySource = File(
      'lib/features/access_admin/data/repositories/access_admin_repository_impl.dart',
    ).readAsStringSync();
    final String updateSource = repositorySource.substring(
      repositorySource.indexOf('Future<Result<void>> updateUser('),
      repositorySource.indexOf('Future<Result<void>> syncUserDirectPermissions('),
    );
    expect(updateSource.contains("'password'"), isFalse);
    expect(
      repositorySource.contains('Future<Result<void>> setUserPassword('),
      isTrue,
      reason: 'A new password goes to its own endpoint, never the profile update',
    );
  });

  test('edit user mirrors create similarity flow excluding self', () {
    final String editSource = dialogsSource.substring(
      dialogsSource.indexOf(
        'Future<AccessAdminItem?> openAccessAdminEditUserDialog(',
      ),
      dialogsSource.indexOf(
        'Future<AccessAdminItem?> openAccessAdminCreateRoleDialog(',
      ),
    );
    expect(editSource.contains('excludeUserId: excludeUserId'), isTrue);
    expect(editSource.contains('isEdit: true'), isTrue);
    expect(editSource.contains('_reviewUserSimilarity'), isTrue);
    expect(editSource.contains('updateUserReviewed'), isTrue);
    expect(
      editSource.contains('always open review before persisting'),
      isTrue,
    );
    expect(
      File(
        'lib/features/access_admin/presentation/widgets/user_similarity_dialog.dart',
      ).readAsStringSync().contains('accessAdminProceedEditUserAction'),
      isTrue,
    );
  });

  test('draft carries confirmSimilar for the review override', () {
    final String entitiesSource = File(
      'lib/features/access_admin/domain/entities/access_admin_entities.dart',
    ).readAsStringSync();
    expect(entitiesSource.contains('this.confirmSimilar = false,'), isTrue);
    expect(
      entitiesSource.contains('AccessAdminUserDraft copyWith('),
      isTrue,
    );
    final String repositorySource = File(
      'lib/features/access_admin/data/repositories/access_admin_repository_impl.dart',
    ).readAsStringSync();
    expect(
      repositorySource.contains("if (draft.confirmSimilar) 'confirm_similar': true,"),
      isTrue,
    );
  });

  test('create-to-detail transition covers the users list immediately', () {
    final String createUserDetailSource = managementSource.substring(
      managementSource.indexOf('Future<void> _openCreateUserDialog() async {'),
      managementSource.indexOf('Future<void> _openUserDetail('),
    );
    expect(
      createUserDetailSource.contains(
        'unawaited(reload(resetPage: true, silent: true))',
      ),
      isTrue,
    );
    expect(
      createUserDetailSource.contains(
        '_openUserDetail(createdOrExisting, coverListImmediately: true)',
      ),
      isTrue,
    );
    final String openDetailSource = managementSource.substring(
      managementSource.indexOf('Future<void> _openUserDetail('),
    );
    expect(
      openDetailSource.contains('bool coverListImmediately = false,'),
      isTrue,
    );
  });

  test('create action remains gated by workspace write access', () {
    expect(
      managementSource.contains('_openCreateUserDialog()'),
      isTrue,
    );
    expect(
      RegExp(
        r'trailingActions:\s*!isPermissions\s*&&\s*canWrite\s*&&\s*'
        r'widget\.showCreateAction',
      ).hasMatch(managementSource),
      isTrue,
    );
  });
}
