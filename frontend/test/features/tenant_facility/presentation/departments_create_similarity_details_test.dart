import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Departments tab create similarity and details', () {
    late String setupPageSource;
    late String repositorySource;
    late String controllerSource;
    late String detailsSource;
    late String similarityDialogSource;

    setUpAll(() {
      setupPageSource = File(
        'lib/features/tenant_facility/presentation/pages/tenant_facility_setup_page.dart',
      ).readAsStringSync();
      repositorySource = File(
        'lib/features/tenant_facility/data/repositories/tenant_facility_repository_impl.dart',
      ).readAsStringSync();
      controllerSource = File(
        'lib/features/tenant_facility/presentation/controllers/tenant_facility_setup_controller.dart',
      ).readAsStringSync();
      detailsSource = File(
        'lib/features/tenant_facility/presentation/widgets/department_details_dialog.dart',
      ).readAsStringSync();
      similarityDialogSource = File(
        'lib/features/tenant_facility/presentation/widgets/department_similarity_dialog.dart',
      ).readAsStringSync();
    });

    String departmentSectionSource() {
      final int sectionStart = setupPageSource.indexOf(
        'class _DepartmentSetupSection extends ConsumerStatefulWidget',
      );
      final int nextSectionStart = setupPageSource.indexOf(
        'class _UnitSetupSection extends ConsumerStatefulWidget',
      );
      expect(sectionStart, greaterThanOrEqualTo(0));
      expect(nextSectionStart, greaterThan(sectionStart));
      return setupPageSource.substring(sectionStart, nextSectionStart);
    }

    String departmentFormSource() {
      final int formStart = setupPageSource.indexOf(
        'class _DepartmentFormDialog extends ConsumerStatefulWidget',
      );
      final int nextStart = setupPageSource.indexOf(
        'class _UnitFormDialog extends ConsumerStatefulWidget',
      );
      expect(formStart, greaterThanOrEqualTo(0));
      expect(nextStart, greaterThan(formStart));
      return setupPageSource.substring(formStart, nextStart);
    }

    test('role-aware create pickers and facility gate', () {
      final String sectionSource = departmentSectionSource();
      final String formSource = departmentFormSource();

      expect(
        sectionSource.contains(
          'createScope == TenantFacilityDepartmentsListScope.facility',
        ),
        isTrue,
      );
      expect(formSource.contains('showTenantPicker'), isTrue);
      expect(formSource.contains('showFacilityPicker'), isTrue);
      expect(formSource.contains('_departmentTypeIcon'), isTrue);
      expect(formSource.contains('leadingIcon: Icon(_departmentTypeIcon(type))'), isTrue);
    });

    test('create always opens similarity and supports confirm_similar', () {
      final String formSource = departmentFormSource();
      expect(formSource.contains('showDepartmentSimilarityDialog'), isTrue);
      expect(formSource.contains('confirmSimilar: _similarityAccepted'), isTrue);
      expect(formSource.contains('confirmSimilar: true'), isTrue);
      expect(formSource.contains('_checkingSimilarity'), isTrue);
      expect(
        repositorySource.contains("if (confirmSimilar) 'confirm_similar': true"),
        isTrue,
      );
      expect(
        controllerSource.contains('bool confirmSimilar = false'),
        isTrue,
      );
      expect(
        similarityDialogSource.contains('tenantFacilityUseThisDepartmentAction'),
        isTrue,
      );
      expect(
        similarityDialogSource.contains('showAppSimilarityReviewDialog'),
        isTrue,
      );
      expect(
        similarityDialogSource.contains('proposedReadOnly: true'),
        isTrue,
      );
      expect(
        similarityDialogSource.contains(
          'tenantFacilityDepartmentOverallSimilarityLabel',
        ),
        isTrue,
      );
      expect(
        similarityDialogSource.contains(
          'tenantFacilityDepartmentNoMatchScoreLabel',
        ),
        isTrue,
      );
      expect(
        similarityDialogSource.contains(
          'tenantFacilityProceedCreateDepartmentAction',
        ),
        isTrue,
      );
    });

    test('details open after create and on row select with edit/delete', () {
      final String sectionSource = departmentSectionSource();
      expect(sectionSource.contains('onRowSelected:'), isTrue);
      expect(setupPageSource.contains('showDepartmentDetailsDialog'), isTrue);
      expect(setupPageSource.contains('_openDepartmentDetails'), isTrue);
      expect(detailsSource.contains('showTenantFacilityDepartmentFormDialog'), isTrue);
      expect(detailsSource.contains('deleteDepartment(_department.mutationId)'), isTrue);
      expect(detailsSource.contains('AppCollapsibleSection'), isTrue);
      expect(detailsSource.contains('AppInfoSheetGrid'), isTrue);
      expect(detailsSource.contains('_DepartmentFactTile'), isFalse);
      expect(detailsSource.contains('AppLoadingIndicator.compact'), isTrue);
      expect(
        detailsSource.contains('tenantFacilityEditDepartmentDetailsAction'),
        isTrue,
      );
      expect(
        detailsSource.contains('tenantFacilityDeleteDepartmentDetailsAction'),
        isTrue,
      );
    });

    test('edit opens from table row and department details', () {
      final String sectionSource = departmentSectionSource();
      expect(sectionSource.contains('onEdit: (DepartmentProfile department)'), isTrue);
      expect(
        sectionSource.contains('_openDepartmentDialog('),
        isTrue,
      );
      expect(sectionSource.contains('department: department,'), isTrue);
      expect(
        detailsSource.contains('showTenantFacilityDepartmentFormDialog'),
        isTrue,
      );
      expect(detailsSource.contains('department: _department,'), isTrue);
      expect(
        detailsSource.contains('canEditFacilitySetupStructure()'),
        isTrue,
      );
      expect(
        setupPageSource.contains('showTenantFacilityDepartmentFormDialog'),
        isTrue,
      );
    });

    test('edit reuses create similarity with exclusion and unchanged skip', () {
      final String formSource = departmentFormSource();
      expect(
        formSource.contains(
          'excludeDepartmentId: editing?.mutationId ?? editing?.id',
        ),
        isTrue,
      );
      expect(formSource.contains('excludeDepartment: editing,'), isTrue);
      expect(formSource.contains('normalizeDepartmentName(name)'), isTrue);
      expect(formSource.contains('forceReviewMatches: true'), isTrue);
      expect(formSource.contains('confirmSimilar: _similarityAccepted'), isTrue);
      expect(formSource.contains('confirmSimilar: true'), isTrue);
      expect(formSource.contains('showDepartmentSimilarityDialog'), isTrue);
      expect(
        formSource.contains("errors.department.similar_exists"),
        isTrue,
      );
    });

    test('short name defaults to name when empty', () {
      final String formSource = departmentFormSource();
      expect(formSource.contains('resolveDepartmentShortName'), isTrue);
      expect(
        repositorySource.contains('_normalizedOptional(shortName)'),
        isTrue,
      );
    });
  });
}
