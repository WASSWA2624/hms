import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Beds tab prompt behaviors', () {
    late String setupPageSource;
    late String helpersSource;
    late String repositorySource;
    late String repositoryInterfaceSource;
    late String bedSimilaritySource;
    late String bedSimilarityDialogSource;
    late String bedDetailsSource;
    late String controllerSource;

    setUpAll(() {
      setupPageSource = File(
        'lib/features/tenant_facility/presentation/pages/tenant_facility_setup_page.dart',
      ).readAsStringSync();
      helpersSource = File(
        'lib/features/tenant_facility/presentation/widgets/tenant_facility_setup_helpers.dart',
      ).readAsStringSync();
      repositorySource = File(
        'lib/features/tenant_facility/data/repositories/tenant_facility_repository_impl.dart',
      ).readAsStringSync();
      repositoryInterfaceSource = File(
        'lib/features/tenant_facility/domain/repositories/tenant_facility_repository.dart',
      ).readAsStringSync();
      bedSimilaritySource = File(
        'lib/features/tenant_facility/domain/entities/bed_similarity.dart',
      ).readAsStringSync();
      bedSimilarityDialogSource = File(
        'lib/features/tenant_facility/presentation/widgets/bed_similarity_dialog.dart',
      ).readAsStringSync();
      bedDetailsSource = File(
        'lib/features/tenant_facility/presentation/widgets/bed_details_dialog.dart',
      ).readAsStringSync();
      controllerSource = File(
        'lib/features/tenant_facility/presentation/controllers/tenant_facility_setup_controller.dart',
      ).readAsStringSync();
    });

    String bedSectionSource() {
      final int sectionStart = setupPageSource.indexOf(
        'class _BedSetupSection extends ConsumerStatefulWidget',
      );
      final int nextSectionStart = setupPageSource.indexOf(
        'class _ModalSectionBody extends StatelessWidget',
      );
      expect(sectionStart, greaterThanOrEqualTo(0));
      expect(nextSectionStart, greaterThan(sectionStart));
      return setupPageSource.substring(sectionStart, nextSectionStart);
    }

    String bedFormSource() {
      final int formStart = setupPageSource.indexOf(
        'class _BedFormDialog extends ConsumerStatefulWidget',
      );
      final int nextStart = setupPageSource.indexOf(
        'class _SubmissionFailureBanner extends ConsumerWidget',
      );
      expect(formStart, greaterThanOrEqualTo(0));
      expect(nextStart, greaterThan(formStart));
      return setupPageSource.substring(formStart, nextStart);
    }

    test('bed section gates Add on accessible wards, not snapshot', () {
      final String sectionSource = bedSectionSource().replaceAll('\r\n', '\n');

      expect(sectionSource.contains('_accessibleWards.isNotEmpty'), isTrue);
      expect(
        sectionSource.contains('l10n.tenantFacilityGateNeedWardsForBeds'),
        isTrue,
      );
      expect(
        sectionSource.contains('snapshot.wards.isNotEmpty'),
        isFalse,
      );
      expect(
        sectionSource.contains(
          'canManageRecords &&\n        prerequisitesMet &&\n        !isSubmitting &&\n        _busyBedId == null',
        ),
        isTrue,
      );
    });

    test('bed list loads through scoped listBeds API', () {
      final String sectionSource = bedSectionSource();
      expect(sectionSource.contains('listBeds('), isTrue);
      expect(sectionSource.contains('listWards('), isTrue);
      expect(sectionSource.contains('listRooms('), isTrue);
      expect(sectionSource.contains('tenantFacilityBedsListScope'), isTrue);
      expect(
        repositoryInterfaceSource.contains(
          'Future<Result<AppPage<BedProfile>>> listBeds({',
        ),
        isTrue,
      );
      expect(
        repositorySource.contains(
          'Future<Result<AppPage<BedProfile>>> listBeds({',
        ),
        isTrue,
      );
      expect(repositorySource.contains("'ward_id': wardId"), isTrue);
      expect(repositorySource.contains("'room_id': roomId"), isTrue);
    });

    test('bed mutations keep Add visible with loading while submitting', () {
      final String sectionSource = bedSectionSource();
      expect(sectionSource.contains('isSubmitting: isSubmitting'), isTrue);
      expect(
        sectionSource.contains(
          'canManageRecords = canSubmit && !submission.isSubmitting',
        ),
        isFalse,
      );
      expect(sectionSource.contains('canManageRecords = widget.canSubmit'), isTrue);
    });

    test('bed list uses branded loader and row-scoped mutation busy', () {
      final String sectionSource = bedSectionSource();
      expect(
        sectionSource.contains('AppLoadingIndicator.compact('),
        isTrue,
      );
      expect(
        sectionSource.contains('tenantFacilityBedsLoadingTitle'),
        isTrue,
      );
      expect(
        sectionSource.contains('tenantFacilityBedsLoadingBody'),
        isTrue,
      );
      expect(sectionSource.contains('busyItemId: _busyBedId'), isTrue);
      expect(sectionSource.contains('itemIdBuilder:'), isTrue);
      expect(sectionSource.contains('_runBusyBedAction'), isTrue);
      expect(sectionSource.contains('onRestore:'), isTrue);
      expect(sectionSource.contains('onPermanentDelete:'), isFalse);
    });

    test('default columns nest room/facility/tenant under label', () {
      final String sectionSource = bedSectionSource();
      expect(sectionSource.contains("id: 'ward'"), isTrue);
      expect(sectionSource.contains('nameDetailBuilder:'), isTrue);
      expect(
        sectionSource.contains("id: 'room'"),
        isFalse,
      );
      expect(
        sectionSource.contains("id: 'facility'"),
        isFalse,
      );
      expect(
        sectionSource.contains("id: 'tenant'"),
        isFalse,
      );
      expect(sectionSource.contains("?? '—'"), isTrue);
      expect(sectionSource.contains('?? facilityId'), isFalse);
      expect(sectionSource.contains('?? wardId'), isFalse);
      expect(sectionSource.contains('?? roomId'), isFalse);
    });

    test('role-scoped columns and filters for beds', () {
      final String sectionSource = bedSectionSource();
      expect(
        sectionSource.contains('tenantFacilityBedsShowsTenantColumn'),
        isTrue,
      );
      expect(
        sectionSource.contains('tenantFacilityBedsShowsFacilityColumn'),
        isTrue,
      );
      expect(
        sectionSource.contains('TenantFacilityBedsFilterKeys.tenant'),
        isTrue,
      );
      expect(
        sectionSource.contains('TenantFacilityBedsFilterKeys.facility'),
        isTrue,
      );
      expect(
        sectionSource.contains('TenantFacilityBedsFilterKeys.ward'),
        isTrue,
      );
      expect(
        sectionSource.contains('TenantFacilityBedsFilterKeys.room'),
        isTrue,
      );
      expect(
        sectionSource.contains('TenantFacilityBedsFilterKeys.status'),
        isTrue,
      );
      expect(
        helpersSource.contains('abstract final class TenantFacilityBedsFilterKeys'),
        isTrue,
      );
      expect(
        helpersSource.contains(
          'typedef TenantFacilityBedsListScope = TenantFacilityDepartmentsListScope',
        ),
        isTrue,
      );
    });

    test('role-aware create pickers with required ward and optional room', () {
      final String formSource = bedFormSource();
      expect(formSource.contains('showTenantPicker'), isTrue);
      expect(formSource.contains('showFacilityPicker'), isTrue);
      expect(formSource.contains('tenantFacilityBedsListScope'), isTrue);
      expect(formSource.contains('l10n.tenantFacilityBedWardLabel'), isTrue);
      expect(formSource.contains('l10n.tenantFacilityBedRoomLabel'), isTrue);
      expect(formSource.contains('_onWardChanged'), isTrue);
    });

    test('create and edit always open bed similarity dialog', () {
      final String formSource = bedFormSource();
      expect(formSource.contains('showBedSimilarityDialog'), isTrue);
      expect(formSource.contains('checkBedDuplicates'), isTrue);
      expect(formSource.contains('_checkingSimilarity'), isTrue);
      expect(formSource.contains('excludeBedId'), isTrue);
      expect(bedSimilaritySource.contains('checkBedDuplicates'), isTrue);
      expect(
        bedSimilarityDialogSource.contains('showBedSimilarityDialog'),
        isTrue,
      );
      expect(
        bedSimilarityDialogSource.contains('BedSimilarityAction.proceed'),
        isTrue,
      );
      expect(
        bedSimilarityDialogSource.contains('BedSimilarityAction.cancel'),
        isTrue,
      );
    });

    test('bed form uses full-content loading overlay while busy', () {
      final String formSource = bedFormSource();
      expect(formSource.contains('showLoadingOverlay'), isTrue);
      expect(formSource.contains('AbsorbPointer'), isTrue);
      expect(formSource.contains('Positioned.fill'), isTrue);
      expect(formSource.contains('AppLoadingIndicator('), isTrue);
      expect(formSource.contains('tenantFacilityBedFormLoadingTitle'), isTrue);
      expect(formSource.contains('tenantFacilityBedFormLoadingBody'), isTrue);
      expect(
        formSource.contains(
          'if (_checkingSimilarity || _loadingOptions)\n              Padding(',
        ),
        isFalse,
      );
    });

    test('details open after create/edit and on row select with edit/delete', () {
      final String sectionSource = bedSectionSource();
      expect(sectionSource.contains('onRowSelected:'), isTrue);
      expect(setupPageSource.contains('showBedDetailsDialog'), isTrue);
      expect(setupPageSource.contains('_openBedDetails'), isTrue);
      expect(setupPageSource.contains('lastSavedBed'), isTrue);
      expect(controllerSource.contains('lastSavedBed'), isTrue);
      expect(bedDetailsSource.contains('showTenantFacilityBedFormDialog'), isTrue);
      expect(bedDetailsSource.contains('deleteBed(_bed.id)'), isTrue);
      expect(bedDetailsSource.contains('AppCollapsibleSection'), isTrue);
      expect(bedDetailsSource.contains('AppInfoSheetGrid'), isTrue);
      expect(bedDetailsSource.contains('_BedFactTile'), isFalse);
      expect(bedDetailsSource.contains('tenantFacilityBedIdLabel'), isTrue);
      expect(bedDetailsSource.contains('tenantFacilityCreatedAtLabel'), isTrue);
      expect(bedDetailsSource.contains('tenantFacilityUpdatedAtLabel'), isTrue);
      expect(bedDetailsSource.contains('tenantFacilityHumanFriendlyDisplayId'), isTrue);
      expect(
        bedDetailsSource.contains('tenantFacilityEditBedDetailsAction'),
        isTrue,
      );
      expect(
        bedDetailsSource.contains('tenantFacilityDeleteBedDetailsAction'),
        isTrue,
      );
    });
  });
}
