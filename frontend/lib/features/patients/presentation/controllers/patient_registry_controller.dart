import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/realtime/realtime_event_groups.dart';
import 'package:hosspi_hms/core/realtime/realtime_message.dart';
import 'package:hosspi_hms/core/realtime/realtime_refresh.dart';
import 'package:hosspi_hms/core/security/session_isolation.dart';
import 'package:hosspi_hms/core/workspace/workspace_adaptive_polling.dart';
import 'package:hosspi_hms/core/workspace/workspace_event_refresh_plan.dart';
import 'package:hosspi_hms/core/workspace/workspace_fast_sync.dart';
import 'package:hosspi_hms/core/workspace/workspace_session_guard.dart';
import 'package:hosspi_hms/features/ipd/data/repositories/ipd_repository_impl.dart';
import 'package:hosspi_hms/features/ipd/domain/entities/ipd_entities.dart';
import 'package:hosspi_hms/features/ipd/domain/repositories/ipd_repository.dart';
import 'package:hosspi_hms/features/patients/data/repositories/patient_repository_impl.dart';
import 'package:hosspi_hms/features/patients/domain/entities/patient_entities.dart';
import 'package:hosspi_hms/features/patients/domain/repositories/patient_repository.dart';
import 'package:hosspi_hms/shared/data/data.dart';

final patientRegistryControllerProvider =
    AsyncNotifierProvider<
      PatientRegistryController,
      Result<PatientRegistryState>
    >(PatientRegistryController.new);

final class PatientRegistryController
    extends AsyncNotifier<Result<PatientRegistryState>> {
  PatientRepository get _repository => ref.read(patientRepositoryProvider);
  IpdRepository get _ipdRepository => ref.read(ipdRepositoryProvider);

  static const Duration _syncInterval = Duration(seconds: 8);

  final WorkspaceAdaptivePolling _adaptivePolling = WorkspaceAdaptivePolling();
  final WorkspacePendingRefresh _pendingRefresh = WorkspacePendingRefresh();
  bool _isSyncing = false;

  @override
  Future<Result<PatientRegistryState>> build() async {
    watchSessionEpoch(ref);
    listenForRealtimeRefresh(
      ref: ref,
      events: RealtimeEventGroups.patientRegistry,
      includeCrudMutations: true,
      shouldDefer: () => _isSyncing || (_currentState?.isSaving ?? false),
      onRefresh: _syncFromRealtime,
    );
    final Result<PatientRegistryState> result = await runWorkspaceInitialLoad(
      ref,
      _loadInitialState,
    );
    _startAdaptivePolling();
    return result;
  }

  Future<void> _syncFromRealtime(RealtimeMessage message) async {
    if (_isSyncing || (_currentState?.isSaving ?? false)) {
      _pendingRefresh.defer(
        WorkspaceEventRefreshPlan.forMessage(
          message,
          profile: WorkspaceRefreshProfile.patientRegistry,
        ),
      );
      return;
    }
    final WorkspaceRefreshPlan plan = WorkspaceEventRefreshPlan.forMessage(
      message,
      profile: WorkspaceRefreshProfile.patientRegistry,
    );
    if (plan.isEmpty) {
      return;
    }
    await _syncVisibleData(plan: plan);
  }

  Future<AppFailure?> refresh() async {
    final PatientRegistryState? current = _currentState;
    if (current == null) {
      final Result<PatientRegistryState> result = await runWorkspaceInitialLoad(
        ref,
        _loadInitialState,
      );
      state = AsyncData<Result<PatientRegistryState>>(result);
      return _failureOrNull(result);
    }

    return _syncVisibleData(
      showLoading: true,
      refreshReferenceData: true,
      allowWhileSaving: true,
      plan: WorkspaceRefreshPlan.full,
    );
  }

  Future<Result<List<Patient>>> loadMatchingPatients() {
    final PatientRegistryState? current = _currentState;
    if (current == null) {
      return Future<Result<List<Patient>>>.value(
        const Result<List<Patient>>.success(<Patient>[]),
      );
    }
    final PatientListQuery query = current.query;
    return loadMatchingAppPageItems<Patient>(
      loadPage: (AppPageRequest request) {
        return _repository.listPatients(query.copyWith(pageRequest: request));
      },
    );
  }

  Future<AppFailure?> applyQuery(PatientListQuery query) async {
    final PatientRegistryState? current = _currentState;
    if (current == null) {
      return refresh();
    }

    _emit(
      current.copyWith(
        query: query,
        isRefreshingList: true,
        clearLastFailure: true,
      ),
    );

    final Result<AppPage<Patient>> result = await _repository.listPatients(
      query,
    );
    return result.when(
      success: (AppPage<Patient> page) {
        final PatientDetail? selectedDetail = _selectedDetailAfterListRefresh(
          page,
          current.selectedDetail,
        );
        _emit(
          _currentState!.copyWith(
            page: page,
            selectedDetail: selectedDetail,
            isRefreshingList: false,
            clearSelectedDetail: selectedDetail == null,
          ),
        );
        return null;
      },
      failure: (AppFailure failure) {
        _emit(
          _currentState!.copyWith(
            lastFailure: failure,
            isRefreshingList: false,
          ),
        );
        return failure;
      },
    );
  }

  Future<Result<AppPage<Patient>>> loadPatientPage(PatientListQuery query) {
    return _repository.listPatients(query);
  }

  Future<Result<AppPage<PatientDuplicateCandidate>>> loadDuplicateCandidates(
    PatientDuplicateQuery query,
  ) {
    return _repository.listDuplicateCandidates(query);
  }

  Future<AppFailure?> selectPatient(String patientId) async {
    PatientRegistryState? current = _currentState;
    if (current == null) {
      final AppFailure? failure = await refresh();
      if (failure != null) {
        return failure;
      }
      current = _currentState;
      if (current == null) {
        return null;
      }
    }

    _emit(current.copyWith(isRefreshingDetail: true, clearLastFailure: true));

    final Result<PatientDetail> result = await _repository.loadPatientDetail(
      patientId,
    );
    return result.when(
      success: (PatientDetail detail) {
        final PatientRegistryState next = _currentState!.copyWith(
          selectedDetail: detail,
          page: _replacePatientInPage(_currentState!.page, detail.patient),
          isRefreshingDetail: false,
        );
        _emit(next);
        return null;
      },
      failure: (AppFailure failure) {
        _emit(
          _currentState!.copyWith(
            lastFailure: failure,
            isRefreshingDetail: false,
          ),
        );
        return failure;
      },
    );
  }

  void clearSelection() {
    final PatientRegistryState? current = _currentState;
    if (current != null) {
      _emit(current.copyWith(clearSelectedDetail: true));
    }
  }

  Future<Result<Patient>> createPatient(Map<String, Object?> payload) async {
    final PatientRegistryState? current = _currentState;
    if (current == null) {
      final AppFailure? failure = await refresh();
      if (failure != null) {
        return Result<Patient>.failure(failure);
      }
      return createPatient(payload);
    }

    _emit(current.copyWith(isSaving: true, clearLastFailure: true));
    final Result<Patient> result = await _repository.createPatient(payload);
    if (result.isFailure) {
      final AppFailure failure = (result as ResultFailure<Patient>).failure;
      _emit(_currentState!.copyWith(isSaving: false, lastFailure: failure));
      await _flushPendingRefresh();
      return Result<Patient>.failure(failure);
    }

    final Patient patient = (result as ResultSuccess<Patient>).value;
    final PatientRegistryState latest = _currentState!;
    final bool shouldInsert =
        latest.query.pageRequest.pageIndex == 0 &&
        _patientMatchesQuery(patient, latest.query);
    _emit(
      latest.copyWith(
        page: shouldInsert
            ? _upsertPatientInPage(latest.page, patient, insertOnTop: true)
            : latest.page,
      ),
    );
    await _refreshOverviewOnly();
    _emit(_currentState!.copyWith(isSaving: false));
    await _flushPendingRefresh();
    return Result<Patient>.success(patient);
  }

  Future<AppFailure?> mergeDuplicateCandidate(
    PatientDuplicateCandidate duplicate, {
    String? primaryPatientId,
    String? secondaryPatientId,
    Map<String, Object?> summary = const <String, Object?>{},
  }) async {
    final PatientRegistryState? current = _currentState;
    if (current == null) {
      return refresh();
    }
    final _DuplicatePair? pair = _duplicatePair(duplicate);
    final String? resolvedPrimary = (primaryPatientId ?? '').trim().isNotEmpty
        ? primaryPatientId!.trim()
        : pair?.primary.id;
    final String? resolvedSecondary =
        (secondaryPatientId ?? '').trim().isNotEmpty
        ? secondaryPatientId!.trim()
        : pair?.secondary.id;
    if (resolvedPrimary == null ||
        resolvedSecondary == null ||
        resolvedPrimary.isEmpty ||
        resolvedSecondary.isEmpty ||
        resolvedPrimary == resolvedSecondary) {
      return null;
    }

    _emit(current.copyWith(isSaving: true, clearLastFailure: true));
    final Result<PatientMutationResult> result = await _repository
        .mergePatients(
          primaryPatientId: resolvedPrimary,
          secondaryPatientId: resolvedSecondary,
          summary: summary,
        );
    return result.when(
      success: (PatientMutationResult result) async {
        await _syncVisibleData(
          showLoading: true,
          refreshReferenceData: true,
          allowWhileSaving: true,
          plan: WorkspaceRefreshPlan.full,
        );
        final AppFailure? detailFailure = await selectPatient(result.patientId);
        _emit(_currentState!.copyWith(isSaving: false));
        await _flushPendingRefresh();
        return detailFailure;
      },
      failure: (AppFailure failure) async {
        _emit(_currentState!.copyWith(isSaving: false, lastFailure: failure));
        await _flushPendingRefresh();
        return failure;
      },
    );
  }

  Future<AppFailure?> dismissDuplicateCandidate(
    PatientDuplicateCandidate duplicate,
  ) async {
    final PatientRegistryState? current = _currentState;
    if (current == null) {
      return refresh();
    }
    final _DuplicatePair? pair = _duplicatePair(duplicate);
    if (pair == null) {
      return null;
    }

    _emit(current.copyWith(isSaving: true, clearLastFailure: true));
    final Result<PatientMutationResult> result = await _repository
        .dismissDuplicateCandidate(
          reviewId: duplicate.reviewId,
          primaryPatientId: pair.primary.id,
          secondaryPatientId: pair.secondary.id,
        );
    return result.when(
      success: (_) async {
        await _syncVisibleData(
          showLoading: true,
          refreshReferenceData: true,
          allowWhileSaving: true,
          plan: WorkspaceRefreshPlan.full,
        );
        _emit(_currentState!.copyWith(isSaving: false));
        await _flushPendingRefresh();
        return null;
      },
      failure: (AppFailure failure) async {
        _emit(_currentState!.copyWith(isSaving: false, lastFailure: failure));
        await _flushPendingRefresh();
        return failure;
      },
    );
  }

  Future<Result<PatientMergePreview>> previewDuplicateMerge(
    PatientDuplicateCandidate duplicate,
  ) {
    final _DuplicatePair? pair = _duplicatePair(duplicate);
    if (pair == null) {
      return Future<Result<PatientMergePreview>>.value(
        Result<PatientMergePreview>.failure(
          AppFailure.validation(
            validationFields: const <String>{'secondary_patient_id'},
          ),
        ),
      );
    }

    return _repository.previewPatientMerge(
      primaryPatientId: pair.primary.id,
      secondaryPatientId: pair.secondary.id,
    );
  }

  Future<AppFailure?> updatePatient(
    String patientId,
    Map<String, Object?> payload,
  ) async {
    final PatientRegistryState? current = _currentState;
    if (current == null) {
      return refresh();
    }

    _emit(current.copyWith(isSaving: true, clearLastFailure: true));
    final Result<Patient> result = await _repository.updatePatient(
      patientId,
      payload,
    );
    return result.when(
      success: (Patient patient) async {
        final PatientDetail? selectedDetail = _currentState!.selectedDetail;
        _emit(
          _currentState!.copyWith(
            page: _replacePatientInPage(_currentState!.page, patient),
            selectedDetail: selectedDetail?.copyWith(patient: patient),
          ),
        );
        final AppFailure? detailFailure = selectedDetail == null
            ? null
            : await selectPatient(patient.id);
        _emit(_currentState!.copyWith(isSaving: false));
        await _flushPendingRefresh();
        return detailFailure;
      },
      failure: (AppFailure failure) async {
        _emit(_currentState!.copyWith(isSaving: false, lastFailure: failure));
        await _flushPendingRefresh();
        return failure;
      },
    );
  }

  Future<AppFailure?> deletePatient(String patientId) async {
    final PatientRegistryState? current = _currentState;
    if (current == null) {
      return refresh();
    }
    final Patient? patient = _findPatientInState(current, patientId);

    _emit(current.copyWith(isSaving: true, clearLastFailure: true));
    final Result<PatientMutationResult> result = await _repository
        .deletePatient(patientId);
    return result.when(
      success: (_) async {
        final PatientRecordState recordState = _currentState!.query.recordState;
        final Patient softDeleted =
            (patient ?? Patient(id: patientId)).copyWith(
              deletedAt: DateTime.now().toUtc(),
              isActive: false,
            );
        if (recordState == PatientRecordState.current) {
          final AppPage<Patient> page = _removePatientFromPage(
            _currentState!.page,
            patientId,
          );
          _emit(
            _currentState!.copyWith(
              page: page,
              overview: _removePatientFromOverview(
                _currentState!.overview,
                patientId,
                patient,
              ),
              isSaving: false,
              clearSelectedDetail: true,
            ),
          );
        } else {
          _emit(
            _currentState!.copyWith(
              page: _replacePatientInPage(_currentState!.page, softDeleted),
              selectedDetail: _currentState!.selectedDetail?.patient.id ==
                      patientId
                  ? _currentState!.selectedDetail!.copyWith(patient: softDeleted)
                  : _currentState!.selectedDetail,
              isSaving: false,
            ),
          );
        }
        await _refreshOverviewOnly();
        await _flushPendingRefresh();
        return null;
      },
      failure: (AppFailure failure) async {
        _emit(_currentState!.copyWith(isSaving: false, lastFailure: failure));
        await _flushPendingRefresh();
        return failure;
      },
    );
  }

  Future<Result<PatientDeletionImpact>> getDeletionImpact(
    String patientId,
  ) {
    return _repository.getDeletionImpact(patientId);
  }

  Future<AppFailure?> restorePatient(String patientId) async {
    final PatientRegistryState? current = _currentState;
    if (current == null) {
      return refresh();
    }
    final Patient? existing = _findPatientInState(current, patientId);

    _emit(current.copyWith(isSaving: true, clearLastFailure: true));
    final Result<Patient> result = await _repository.restorePatient(patientId);
    return result.when(
      success: (Patient restored) async {
        final PatientRecordState recordState = _currentState!.query.recordState;
        final Patient applied = restored.id.isNotEmpty
            ? restored
            : (existing ?? Patient(id: patientId)).copyWith(
                clearDeletedAt: true,
                isActive: true,
              );
        if (recordState == PatientRecordState.deleted) {
          _emit(
            _currentState!.copyWith(
              page: _removePatientFromPage(_currentState!.page, patientId),
              isSaving: false,
              clearSelectedDetail: true,
            ),
          );
        } else {
          _emit(
            _currentState!.copyWith(
              page: _replacePatientInPage(_currentState!.page, applied),
              selectedDetail:
                  _currentState!.selectedDetail?.patient.id == patientId
                  ? _currentState!.selectedDetail!.copyWith(patient: applied)
                  : _currentState!.selectedDetail,
              isSaving: false,
            ),
          );
        }
        await _refreshOverviewOnly();
        await _flushPendingRefresh();
        return null;
      },
      failure: (AppFailure failure) async {
        _emit(_currentState!.copyWith(isSaving: false, lastFailure: failure));
        await _flushPendingRefresh();
        return failure;
      },
    );
  }

  Future<AppFailure?> permanentDeletePatient(String patientId) async {
    final PatientRegistryState? current = _currentState;
    if (current == null) {
      return refresh();
    }
    final Patient? patient = _findPatientInState(current, patientId);

    _emit(current.copyWith(isSaving: true, clearLastFailure: true));
    final Result<PatientMutationResult> result = await _repository
        .permanentDeletePatient(patientId);
    return result.when(
      success: (_) async {
        _emit(
          _currentState!.copyWith(
            page: _removePatientFromPage(_currentState!.page, patientId),
            overview: _removePatientFromOverview(
              _currentState!.overview,
              patientId,
              patient,
            ),
            isSaving: false,
            clearSelectedDetail: true,
          ),
        );
        await _refreshOverviewOnly();
        await _flushPendingRefresh();
        return null;
      },
      failure: (AppFailure failure) async {
        _emit(_currentState!.copyWith(isSaving: false, lastFailure: failure));
        await _flushPendingRefresh();
        return failure;
      },
    );
  }

  /// Request IPD admission from patient registry quick actions.
  ///
  /// Mutates over HTTP via [IpdRepository.requestAdmission]. On persisted
  /// success, immediately patches admission / visit cues on the selected
  /// patient detail and list row, then reconciles with a targeted detail load.
  ///
  /// [patientId] is the registry entity id used for Riverpod patches.
  /// [apiPatientId] is the public `human_friendly_id` sent to the API when it
  /// differs from [patientId].
  Future<AppFailure?> requestAdmission({
    required String patientId,
    String? apiPatientId,
    String? tenantId,
    String? facilityId,
    String? reason,
    String? notes,
  }) async {
    final String normalizedPatientId = patientId.trim();
    final String normalizedApiPatientId =
        (apiPatientId ?? patientId).trim();
    if (normalizedPatientId.isEmpty || normalizedApiPatientId.isEmpty) {
      return AppFailure.validation();
    }

    PatientRegistryState? current = _currentState;
    if (current == null) {
      final AppFailure? refreshFailure = await refresh();
      if (refreshFailure != null) {
        return refreshFailure;
      }
      current = _currentState;
      if (current == null) {
        return AppFailure.validation();
      }
    }

    _emit(current.copyWith(isSaving: true, clearLastFailure: true));
    final Result<IpdAdmissionDetail> result = await _ipdRepository
        .requestAdmission(<String, Object?>{
          if (tenantId != null && tenantId.trim().isNotEmpty)
            'tenant_id': tenantId.trim(),
          if (facilityId != null && facilityId.trim().isNotEmpty)
            'facility_id': facilityId.trim(),
          'patient_id': normalizedApiPatientId,
          if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        });

    return result.when(
      success: (IpdAdmissionDetail admission) async {
        _patchAdmissionRequest(admission, normalizedPatientId);
        final AppFailure? detailFailure = await selectPatient(
          normalizedPatientId,
        );
        final PatientRegistryState? latest = _currentState;
        if (latest != null) {
          _emit(latest.copyWith(isSaving: false));
        }
        await _flushPendingRefresh();
        return detailFailure;
      },
      failure: (AppFailure failure) async {
        final PatientRegistryState? latest = _currentState;
        if (latest != null) {
          _emit(latest.copyWith(isSaving: false, lastFailure: failure));
        }
        await _flushPendingRefresh();
        return failure;
      },
    );
  }

  Future<AppFailure?> createRelatedRecord(
    PatientRelatedResource resource,
    Map<String, Object?> payload,
  ) async {
    return _mutateRelated(
      () => _repository.createRelatedRecord(resource, payload),
    );
  }

  Future<AppFailure?> updateRelatedRecord(
    PatientRelatedResource resource,
    String recordId,
    Map<String, Object?> payload,
  ) async {
    return _mutateRelated(
      () => _repository.updateRelatedRecord(resource, recordId, payload),
    );
  }

  Future<AppFailure?> deleteRelatedRecord(
    PatientRelatedResource resource,
    String recordId,
  ) async {
    return _mutateRelated(
      () => _repository.deleteRelatedRecord(resource, recordId),
    );
  }

  Future<AppFailure?> _mutateRelated(
    Future<Result<void>> Function() action,
  ) async {
    return _mutateSelectedDetail<void>(action);
  }

  Future<AppFailure?> _mutateSelectedDetail<T>(
    Future<Result<T>> Function() action, {
    String? patientId,
  }) async {
    final PatientRegistryState? current = _currentState;
    final PatientDetail? selectedDetail = current?.selectedDetail;
    if (current == null || selectedDetail == null) {
      return null;
    }

    _emit(current.copyWith(isSaving: true, clearLastFailure: true));
    final Result<T> result = await action();
    return result.when(
      success: (_) async {
        final AppFailure? detailFailure = await selectPatient(
          patientId ?? selectedDetail.patient.id,
        );
        await _refreshOverviewOnly();
        _emit(_currentState!.copyWith(isSaving: false));
        await _flushPendingRefresh();
        return detailFailure;
      },
      failure: (AppFailure failure) async {
        _emit(_currentState!.copyWith(isSaving: false, lastFailure: failure));
        await _flushPendingRefresh();
        return failure;
      },
    );
  }

  Future<AppFailure?> _flushPendingRefresh() async {
    if (!_pendingRefresh.refreshPending ||
        _isSyncing ||
        (_currentState?.isSaving ?? false)) {
      return null;
    }
    final WorkspaceRefreshPlan plan = _pendingRefresh.takePending();
    if (plan.isEmpty) {
      return null;
    }
    return _syncVisibleData(plan: plan);
  }

  Future<Result<PatientRegistryState>> _loadInitialState() async {
    final Result<PatientRegistryOverview> overviewResult = await _repository
        .loadOverview();
    final PatientRegistryOverview? overview = _successOrNull(overviewResult);
    if (overview == null) {
      return Result<PatientRegistryState>.failure(
        _failureOrNull(overviewResult)!,
      );
    }

    final Result<PatientReferenceData> referenceResult = await _repository
        .loadReferenceData();
    final PatientReferenceData referenceData =
        _successOrNull(referenceResult) ?? const PatientReferenceData();

    const PatientListQuery query = PatientListQuery();
    final Result<AppPage<Patient>> pageResult = await _repository.listPatients(
      query,
    );
    final AppPage<Patient>? page = _successOrNull(pageResult);
    if (page == null) {
      return Result<PatientRegistryState>.failure(_failureOrNull(pageResult)!);
    }

    return Result<PatientRegistryState>.success(
      PatientRegistryState(
        query: query,
        page: page,
        overview: overview,
        referenceData: referenceData,
      ),
    );
  }

  Future<void> _refreshOverviewOnly() async {
    final PatientRegistryState? current = _currentState;
    if (current == null) {
      return;
    }

    final Result<PatientRegistryOverview> result = await _repository
        .loadOverview();
    result.when(
      success: (PatientRegistryOverview overview) {
        final PatientRegistryState? latest = _currentState;
        if (latest != null) {
          _emit(latest.copyWith(overview: overview));
        }
      },
      failure: (_) {},
    );
  }

  void _startAdaptivePolling() {
    installWorkspaceAdaptivePolling(
      ref: ref,
      polling: _adaptivePolling,
      intervalWhenDisconnected: _syncInterval,
      disconnectProfile: WorkspaceRefreshProfile.patientRegistry,
      syncOnDisconnect: (WorkspaceRefreshPlan plan) =>
          _syncVisibleData(plan: plan),
    );
  }

  Future<AppFailure?> _syncVisibleData({
    bool showLoading = false,
    bool refreshReferenceData = false,
    bool allowWhileSaving = false,
    WorkspaceRefreshPlan plan = WorkspaceRefreshPlan.admissionWorkspace,
  }) async {
    if (plan.isEmpty) {
      return null;
    }
    final PatientRegistryState? current = _currentState;
    if (current == null) {
      return null;
    }
    if (_isSyncing) {
      _pendingRefresh.defer(plan);
      return null;
    }
    if (!allowWhileSaving && current.isSaving) {
      _pendingRefresh.defer(plan);
      return null;
    }

    final bool refreshOverview = plan.summaryCounts;
    final bool refreshRefs =
        refreshReferenceData || workspacePlanRefreshesReferenceData(plan);
    final bool refreshList = plan.primaryList;
    final bool refreshDetail =
        plan.selectedDetail && current.selectedDetail != null;
    if (!refreshOverview && !refreshRefs && !refreshList && !refreshDetail) {
      return null;
    }

    _isSyncing = true;
    AppFailure? firstFailure;
    if (showLoading) {
      _emit(
        current.copyWith(
          isRefreshingList: refreshList,
          isRefreshingDetail: refreshDetail,
          clearLastFailure: true,
        ),
      );
    }

    try {
      if (refreshOverview) {
        final Result<PatientRegistryOverview> overviewResult = await _repository
            .loadOverview();
        overviewResult.when(
          success: (PatientRegistryOverview overview) {
            final PatientRegistryState? latest = _currentState;
            if (latest != null) {
              _emit(latest.copyWith(overview: overview));
            }
          },
          failure: (AppFailure failure) {
            firstFailure ??= failure;
            final PatientRegistryState? latest = _currentState;
            if (showLoading && latest != null) {
              _emit(latest.copyWith(lastFailure: failure));
            }
          },
        );
      }

      if (refreshRefs) {
        final Result<PatientReferenceData> referenceResult = await _repository
            .loadReferenceData();
        referenceResult.when(
          success: (PatientReferenceData referenceData) {
            final PatientRegistryState? latest = _currentState;
            if (latest != null) {
              _emit(latest.copyWith(referenceData: referenceData));
            }
          },
          failure: (AppFailure failure) {
            firstFailure ??= failure;
            final PatientRegistryState? latest = _currentState;
            if (showLoading && latest != null) {
              _emit(latest.copyWith(lastFailure: failure));
            }
          },
        );
      }

      if (refreshList) {
        final PatientRegistryState? beforeList = _currentState;
        if (beforeList != null) {
          final Result<AppPage<Patient>> pageResult = await _repository
              .listPatients(beforeList.query);
          pageResult.when(
            success: (AppPage<Patient> page) {
              final PatientRegistryState? latest = _currentState;
              if (latest != null) {
                final PatientDetail? selectedDetail =
                    _selectedDetailAfterListRefresh(
                      page,
                      latest.selectedDetail,
                    );
                _emit(
                  latest.copyWith(
                    page: page,
                    selectedDetail: selectedDetail,
                    clearSelectedDetail: selectedDetail == null,
                  ),
                );
              }
            },
            failure: (AppFailure failure) {
              firstFailure ??= failure;
              final PatientRegistryState? latest = _currentState;
              if (showLoading && latest != null) {
                _emit(latest.copyWith(lastFailure: failure));
              }
            },
          );
        }
      }

      if (refreshDetail) {
        final PatientDetail? selectedDetail = _currentState?.selectedDetail;
        if (selectedDetail != null) {
          final Result<PatientDetail> detailResult = await _repository
              .loadPatientDetail(selectedDetail.patient.id);
          detailResult.when(
            success: (PatientDetail detail) {
              final PatientRegistryState? latest = _currentState;
              if (latest != null) {
                _emit(
                  latest.copyWith(
                    selectedDetail: detail,
                    page: _replacePatientInPage(latest.page, detail.patient),
                  ),
                );
              }
            },
            failure: (AppFailure failure) {
              firstFailure ??= failure;
              final PatientRegistryState? latest = _currentState;
              if (showLoading && latest != null) {
                _emit(latest.copyWith(lastFailure: failure));
              }
            },
          );
        }
      }
    } finally {
      final PatientRegistryState? latest = _currentState;
      if (showLoading && latest != null) {
        _emit(
          latest.copyWith(isRefreshingList: false, isRefreshingDetail: false),
        );
      }
      _isSyncing = false;
      if (_pendingRefresh.refreshPending &&
          !(_currentState?.isSaving ?? false)) {
        final WorkspaceRefreshPlan pendingPlan = _pendingRefresh.takePending();
        if (!pendingPlan.isEmpty) {
          unawaited(_syncVisibleData(plan: pendingPlan));
        }
      }
    }

    return firstFailure;
  }

  PatientDetail? _selectedDetailAfterListRefresh(
    AppPage<Patient> page,
    PatientDetail? selectedDetail,
  ) {
    if (selectedDetail == null) {
      return null;
    }
    final Iterable<Patient> matching = page.items.where(
      (Patient patient) => patient.id == selectedDetail.patient.id,
    );
    if (matching.isEmpty) {
      return selectedDetail;
    }

    return selectedDetail.copyWith(patient: matching.first);
  }

  AppPage<Patient> _replacePatientInPage(
    AppPage<Patient> page,
    Patient patient,
  ) {
    return AppPage<Patient>(
      items: <Patient>[
        for (final Patient item in page.items)
          if (item.id == patient.id) patient else item,
      ],
      request: page.request,
      totalItemCount: page.totalItemCount,
    );
  }

  AppPage<Patient> _upsertPatientInPage(
    AppPage<Patient> page,
    Patient patient, {
    bool insertOnTop = false,
  }) {
    final List<Patient> withoutExisting = page.items
        .where((Patient item) => item.id != patient.id)
        .toList(growable: true);
    final int previousLength = withoutExisting.length;
    if (insertOnTop) {
      withoutExisting.insert(0, patient);
    } else {
      withoutExisting.add(patient);
    }
    final int maxItems = page.request.pageSize;
    final List<Patient> items = withoutExisting.length > maxItems
        ? withoutExisting.take(maxItems).toList(growable: false)
        : withoutExisting.toList(growable: false);
    final bool wasInserted = previousLength == page.items.length;
    final int? total = page.totalItemCount == null
        ? null
        : page.totalItemCount! + (wasInserted ? 1 : 0);

    return AppPage<Patient>(
      items: items,
      request: page.request,
      totalItemCount: total,
    );
  }

  AppPage<Patient> _removePatientFromPage(
    AppPage<Patient> page,
    String patientId,
  ) {
    final List<Patient> items = page.items
        .where((Patient item) => item.id != patientId)
        .toList(growable: false);
    final int? total = page.totalItemCount == null
        ? null
        : (page.totalItemCount! - (page.items.length - items.length)).clamp(
            0,
            page.totalItemCount!,
          );

    return AppPage<Patient>(
      items: items,
      request: page.request,
      totalItemCount: total,
    );
  }

  PatientRegistryOverview _removePatientFromOverview(
    PatientRegistryOverview overview,
    String patientId,
    Patient? patient,
  ) {
    final List<Patient> recentPatients = overview.recentPatients
        .where((Patient item) => item.id != patientId)
        .toList(growable: false);
    final List<Patient> waitingQueuePatients = overview.waitingQueuePatients
        .where((Patient item) => item.id != patientId)
        .toList(growable: false);
    final bool wasInRecent =
        recentPatients.length != overview.recentPatients.length;
    final bool wasInWaitingQueue =
        waitingQueuePatients.length != overview.waitingQueuePatients.length;

    return overview.copyWith(
      totalPatients: wasInRecent
          ? (overview.totalPatients - 1).clamp(0, overview.totalPatients)
          : overview.totalPatients,
      activePatients: wasInRecent && (patient?.isActive ?? false)
          ? (overview.activePatients - 1).clamp(0, overview.activePatients)
          : overview.activePatients,
      waitingQueue: wasInWaitingQueue
          ? (overview.waitingQueue - 1).clamp(0, overview.waitingQueue)
          : overview.waitingQueue,
      recentPatients: recentPatients,
      waitingQueuePatients: waitingQueuePatients,
      duplicates: overview.duplicates
          .where(
            (PatientDuplicateCandidate candidate) =>
                candidate.primaryPatient?.id != patientId &&
                candidate.secondaryPatient?.id != patientId &&
                candidate.candidatePatient?.id != patientId,
          )
          .toList(growable: false),
    );
  }

  Patient? _findPatientInState(PatientRegistryState state, String patientId) {
    final List<Patient> candidates = <Patient>[
      ...state.page.items,
      ...state.overview.recentPatients,
      ...state.overview.waitingQueuePatients,
      if (state.selectedDetail != null) state.selectedDetail!.patient,
    ];

    for (final Patient patient in candidates) {
      if (patient.id == patientId) {
        return patient;
      }
    }

    return null;
  }

  void _patchAdmissionRequest(
    IpdAdmissionDetail admission,
    String patientId,
  ) {
    final PatientRegistryState? latest = _currentState;
    if (latest == null) {
      return;
    }

    final IpdAdmissionSummary summary = admission.summary;
    final String admissionId =
        _firstNonEmpty(<String?>[summary.displayId, summary.id]) ?? summary.id;
    final String? admissionStatus = _firstNonEmpty(<String?>[
      summary.admissionStatus,
      'REQUESTED',
    ]);
    final PatientSummaryRecord admissionRecord = PatientSummaryRecord(
      id: admissionId,
      kind: 'admission',
      status: admissionStatus,
      title: _firstNonEmpty(<String?>[
        summary.displayId,
        summary.displayTitle,
        summary.stage,
      ]),
      subtitle: summary.location,
      occurredAt: summary.admittedAt,
    );
    final PatientVisitContext visit = PatientVisitContext(
      kind: 'admission',
      publicId: admissionId,
      status: admissionStatus,
      title: _firstNonEmpty(<String?>[
        summary.location,
        summary.stage,
        summary.displayId,
      ]),
      occurredAt: summary.admittedAt,
    );

    final PatientDetail? selectedDetail = latest.selectedDetail;
    if (selectedDetail != null && selectedDetail.patient.id == patientId) {
      final Patient patchedPatient = selectedDetail.patient.copyWith(
        currentVisit: visit,
      );
      _emit(
        latest.copyWith(
          selectedDetail: selectedDetail.copyWith(
            patient: patchedPatient,
            workspace: selectedDetail.workspace.copyWith(
              admissions: _upsertAdmissionRecord(
                selectedDetail.workspace.admissions,
                admissionRecord,
              ),
            ),
          ),
          page: _replacePatientInPage(latest.page, patchedPatient),
        ),
      );
      return;
    }

    final Patient? listPatient = _findPatientInState(latest, patientId);
    if (listPatient == null) {
      return;
    }
    _emit(
      latest.copyWith(
        page: _replacePatientInPage(
          latest.page,
          listPatient.copyWith(currentVisit: visit),
        ),
      ),
    );
  }

  List<PatientSummaryRecord> _upsertAdmissionRecord(
    List<PatientSummaryRecord> admissions,
    PatientSummaryRecord record,
  ) {
    final List<PatientSummaryRecord> next = <PatientSummaryRecord>[
      for (final PatientSummaryRecord item in admissions)
        if (item.id != record.id) item,
    ];
    next.insert(0, record);
    return next;
  }

  String? _firstNonEmpty(Iterable<String?> values) {
    for (final String? value in values) {
      final String normalized = value?.trim() ?? '';
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return null;
  }

  PatientRegistryState? get _currentState {
    final Result<PatientRegistryState>? currentResult = state.asData?.value;
    return switch (currentResult) {
      ResultSuccess<PatientRegistryState>(value: final value) => value,
      _ => null,
    };
  }

  bool _patientMatchesQuery(Patient patient, PatientListQuery query) {
    if (query.isActive != null && patient.isActive != query.isActive) {
      return false;
    }
    if (query.gender != null &&
        patient.gender?.toUpperCase() != query.gender!.toUpperCase()) {
      return false;
    }
    final String patientId = query.patientId.trim().toLowerCase();
    if (patientId.isNotEmpty &&
        !(patient.id.toLowerCase().contains(patientId) ||
            (patient.publicId ?? '').toLowerCase().contains(patientId) ||
            (patient.effectiveIdentifier ?? '').toLowerCase().contains(
              patientId,
            ))) {
      return false;
    }
    final String search = query.search.trim().toLowerCase();
    if (search.isEmpty) {
      return true;
    }

    return <String?>[
      patient.effectiveDisplayName,
      patient.effectiveIdentifier,
      patient.primaryPhone,
      patient.primaryEmail,
      patient.facilityLabel,
      patient.tenantLabel,
    ].any((String? value) {
      return (value ?? '').toLowerCase().contains(search);
    });
  }

  void _emit(PatientRegistryState nextState) {
    state = AsyncData<Result<PatientRegistryState>>(
      Result<PatientRegistryState>.success(nextState),
    );
  }

  T? _successOrNull<T>(Result<T> result) {
    return result.when(success: (T value) => value, failure: (_) => null);
  }

  AppFailure? _failureOrNull<T>(Result<T> result) {
    return result.when(
      success: (_) => null,
      failure: (AppFailure failure) => failure,
    );
  }
}

final class _DuplicatePair {
  const _DuplicatePair({required this.primary, required this.secondary});

  final Patient primary;
  final Patient secondary;
}

_DuplicatePair? _duplicatePair(PatientDuplicateCandidate duplicate) {
  final Patient? primary = duplicate.primaryPatient;
  final Patient? secondary =
      duplicate.secondaryPatient ?? duplicate.candidatePatient;
  if (primary == null ||
      secondary == null ||
      primary.id.isEmpty ||
      secondary.id.isEmpty ||
      primary.id == secondary.id) {
    return null;
  }

  return _DuplicatePair(primary: primary, secondary: secondary);
}
