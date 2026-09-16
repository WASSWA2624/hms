import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/security/auth_session.dart';
import 'package:hosspi_hms/core/security/secure_session_storage.dart';
import 'package:hosspi_hms/core/security/session_controller.dart';
import 'package:hosspi_hms/core/security/session_state.dart';
import 'package:hosspi_hms/core/security/session_tokens.dart';
import 'package:hosspi_hms/core/storage/preferences/app_preferences_store.dart';
import 'package:hosspi_hms/core/storage/storage_providers.dart';
import 'package:hosspi_hms/features/ipd/data/repositories/ipd_repository_impl.dart';
import 'package:hosspi_hms/features/ipd/domain/repositories/ipd_repository.dart';
import 'package:hosspi_hms/features/patients/data/dtos/patient_dtos.dart';
import 'package:hosspi_hms/features/patients/data/repositories/patient_repository_impl.dart';
import 'package:hosspi_hms/features/patients/domain/entities/patient_entities.dart';
import 'package:hosspi_hms/features/patients/domain/repositories/patient_repository.dart';
import 'package:hosspi_hms/features/patients/presentation/controllers/patient_registry_controller.dart';
import 'package:hosspi_hms/shared/data/data.dart';
import 'package:mocktail/mocktail.dart';

class _MockPatientRepository extends Mock implements PatientRepository {}

class _MockIpdRepository extends Mock implements IpdRepository {}

final class _TestSecureSessionStorage implements SecureSessionStorage {
  @override
  Future<SessionTokens?> readTokens() async =>
      SessionTokens(accessToken: 'test-access-token');

  @override
  Future<void> writeTokens(SessionTokens tokens) async {}

  @override
  Future<void> clear() async {}
}

final class _TestAppPreferencesStore implements AppPreferencesStore {
  final Map<String, Object> _data = <String, Object>{};

  @override
  String? getString(String key) => _data[key] as String?;

  @override
  bool? getBool(String key) => _data[key] as bool?;

  @override
  int? getInt(String key) => _data[key] as int?;

  @override
  Future<bool> setString(String key, String value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> setBool(String key, {required bool value}) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> setInt(String key, int value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    _data.remove(key);
    return true;
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(const PatientListQuery());
    registerFallbackValue(<String, Object?>{});
  });

  const Patient activePatient = Patient(
    id: 'pat-1',
    publicId: 'PAT0000001',
    firstName: 'Ada',
    lastName: 'Lovelace',
    isActive: true,
  );

  group('PatientListQuery record state', () {
    test('defaults to current and maps URI params', () {
      expect(const PatientListQuery().recordState, PatientRecordState.current);
      expect(const PatientListQuery().effectiveIncludeDeleted, isFalse);

      final PatientListQuery deleted = PatientListQuery.fromUri(
        Uri.parse('/patients?record_state=deleted'),
      );
      expect(deleted.recordState, PatientRecordState.deleted);
      expect(deleted.effectiveIncludeDeleted, isTrue);

      final PatientListQuery all = PatientListQuery.fromUri(
        Uri.parse('/patients?include_deleted=true'),
      );
      expect(all.recordState, PatientRecordState.all);
      expect(all.effectiveIncludeDeleted, isTrue);
    });

    test('PatientDto maps deleted_at to isDeleted', () {
      final Patient patient = PatientDto.fromJson(<String, Object?>{
        'id': 'pat-1',
        'human_friendly_id': 'PAT0000001',
        'first_name': 'Ada',
        'deleted_at': '2026-09-16T10:00:00.000Z',
      }).toEntity();
      expect(patient.isDeleted, isTrue);
      expect(patient.deletedAt, isNotNull);
    });

    test('PatientDeletionImpactDto maps blockers and category counts', () {
      final PatientDeletionImpact impact =
          PatientDeletionImpactDto.fromResponse(<String, Object?>{
            'data': <String, Object?>{
              'patient_id': 'PAT0000001',
              'human_friendly_id': 'PAT0000001',
              'blockers': <Object?>[
                <String, Object?>{
                  'code': 'active_admission',
                  'model': 'admission',
                  'count': 1,
                },
              ],
              'counts': <String, Object?>{
                'by_category': <String, Object?>{'clinical': 3, 'orders': 2},
                'by_model': <String, Object?>{'encounter': 3},
              },
            },
          }).toEntity();
      expect(impact.hasBlockers, isTrue);
      expect(impact.blockers.single.code, 'active_admission');
      expect(impact.counts['clinical'], 3);
      expect(impact.counts['orders'], 2);
    });
  });

  group('PatientRegistryController cascade lifecycle', () {
    late _MockPatientRepository patients;
    late ProviderContainer container;
    late List<Patient> listItems;

    Future<void> pumpController({
      PatientListQuery query = const PatientListQuery(),
      List<Patient> items = const <Patient>[activePatient],
    }) async {
      patients = _MockPatientRepository();
      listItems = List<Patient>.from(items);
      PatientRecordState expectedRecordState = PatientRecordState.current;
      when(() => patients.loadOverview()).thenAnswer(
        (_) async => Result<PatientRegistryOverview>.success(
          PatientRegistryOverview(
            totalPatients: listItems.length,
            activePatients: listItems.where((Patient p) => p.isActive).length,
          ),
        ),
      );
      when(() => patients.loadReferenceData()).thenAnswer(
        (_) async => const Result<PatientReferenceData>.success(
          PatientReferenceData(),
        ),
      );
      when(() => patients.listPatients(any())).thenAnswer((
        Invocation invocation,
      ) async {
        final PatientListQuery requested =
            invocation.positionalArguments.first as PatientListQuery;
        expect(requested.recordState, expectedRecordState);
        return Result<AppPage<Patient>>.success(
          AppPage<Patient>(
            items: List<Patient>.from(listItems),
            request: requested.pageRequest,
            totalItemCount: listItems.length,
          ),
        );
      });

      container = ProviderContainer(
        overrides: [
          initialSessionStateProvider.overrideWithValue(
            SessionState.authenticated(
              session: AuthSession(
                tokens: SessionTokens(accessToken: 'token'),
                subject: 'admin@example.com',
                user: const AuthUserProfile(
                  id: 'user-1',
                  email: 'admin@example.com',
                  roles: <String>['FACILITY_ADMIN'],
                  tenantId: 'tenant-1',
                  facilityId: 'facility-1',
                ),
              ),
            ),
          ),
          secureSessionStorageProvider.overrideWithValue(
            _TestSecureSessionStorage(),
          ),
          appPreferencesStoreProvider.overrideWithValue(
            _TestAppPreferencesStore(),
          ),
          patientRepositoryProvider.overrideWithValue(patients),
          ipdRepositoryProvider.overrideWithValue(_MockIpdRepository()),
        ],
      );
      addTearDown(container.dispose);

      await container.read(patientRegistryControllerProvider.future);
      if (query.recordState != PatientRecordState.current) {
        expectedRecordState = query.recordState;
        await container
            .read(patientRegistryControllerProvider.notifier)
            .applyQuery(query);
      }
    }

    PatientRegistryState requireState() {
      final Result<PatientRegistryState>? result = container
          .read(patientRegistryControllerProvider)
          .asData
          ?.value;
      return switch (result) {
        ResultSuccess<PatientRegistryState>(:final value) => value,
        _ => fail('expected loaded PatientRegistryState'),
      };
    }

    test('soft delete removes row when filter is current', () async {
      await pumpController();
      when(() => patients.deletePatient(activePatient.id)).thenAnswer((
        _,
      ) async {
        listItems = <Patient>[];
        return Result<PatientMutationResult>.success(
          PatientMutationResult(patientId: activePatient.id),
        );
      });

      final AppFailure? failure = await container
          .read(patientRegistryControllerProvider.notifier)
          .deletePatient(activePatient.id);

      expect(failure, isNull);
      expect(requireState().page.items, isEmpty);
      expect(requireState().isSaving, isFalse);
    });

    test('soft delete patches deletedAt when filter is all', () async {
      await pumpController(
        query: const PatientListQuery(recordState: PatientRecordState.all),
      );
      when(() => patients.deletePatient(activePatient.id)).thenAnswer((
        _,
      ) async {
        listItems = <Patient>[
          activePatient.copyWith(
            deletedAt: DateTime.utc(2026, 9, 16),
            isActive: false,
          ),
        ];
        return Result<PatientMutationResult>.success(
          PatientMutationResult(patientId: activePatient.id),
        );
      });

      final AppFailure? failure = await container
          .read(patientRegistryControllerProvider.notifier)
          .deletePatient(activePatient.id);

      expect(failure, isNull);
      expect(requireState().page.items, hasLength(1));
      expect(requireState().page.items.single.isDeleted, isTrue);
    });

    test('restore clears deletedAt and removes from deleted filter', () async {
      final Patient deleted = activePatient.copyWith(
        deletedAt: DateTime.utc(2026, 9, 16),
        isActive: false,
      );
      await pumpController(
        query: const PatientListQuery(recordState: PatientRecordState.deleted),
        items: <Patient>[deleted],
      );
      when(() => patients.restorePatient(deleted.id)).thenAnswer((_) async {
        listItems = <Patient>[];
        return Result<Patient>.success(
          deleted.copyWith(clearDeletedAt: true, isActive: true),
        );
      });

      final AppFailure? failure = await container
          .read(patientRegistryControllerProvider.notifier)
          .restorePatient(deleted.id);

      expect(failure, isNull);
      expect(requireState().page.items, isEmpty);
    });

    test('permanent delete removes the row', () async {
      final Patient deleted = activePatient.copyWith(
        deletedAt: DateTime.utc(2026, 9, 16),
      );
      await pumpController(
        query: const PatientListQuery(recordState: PatientRecordState.deleted),
        items: <Patient>[deleted],
      );
      when(() => patients.permanentDeletePatient(deleted.id)).thenAnswer((
        _,
      ) async {
        listItems = <Patient>[];
        return Result<PatientMutationResult>.success(
          PatientMutationResult(patientId: deleted.id),
        );
      });

      final AppFailure? failure = await container
          .read(patientRegistryControllerProvider.notifier)
          .permanentDeletePatient(deleted.id);

      expect(failure, isNull);
      expect(requireState().page.items, isEmpty);
    });

    test('surfaces conflict failure from soft delete', () async {
      await pumpController();
      when(() => patients.deletePatient(activePatient.id)).thenAnswer(
        (_) async => Result<PatientMutationResult>.failure(
          AppFailure.conflict(
            conflictEntries: const <Map<String, Object?>>[
              <String, Object?>{'code': 'active_admission', 'count': 1},
            ],
          ),
        ),
      );

      final AppFailure? failure = await container
          .read(patientRegistryControllerProvider.notifier)
          .deletePatient(activePatient.id);

      expect(failure, isA<ConflictFailure>());
      expect(requireState().page.items, hasLength(1));
      expect(requireState().lastFailure, isA<ConflictFailure>());
    });
  });
}
