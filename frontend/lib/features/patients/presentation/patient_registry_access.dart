import 'package:hosspi_hms/core/permissions/access_policy.dart';
import 'package:hosspi_hms/core/permissions/access_requirement.dart';
import 'package:hosspi_hms/core/permissions/app_permission.dart';
import 'package:hosspi_hms/core/permissions/route_access_catalog.dart';
import 'package:hosspi_hms/features/patients/domain/entities/patient_entities.dart';
import 'package:hosspi_hms/features/patients/presentation/widgets/patient_active_work_helpers.dart';
import 'package:hosspi_hms/shared/components/opd_encounter_dialog.dart';

/// Module entitlement for the patients registry route and tabs.
const String patientRegistryModule = 'patient-registry';

/// View / read UI (matrix ∩ `patient:read`).
///
/// [PermissionModuleMap] also requires [patientRegistryModule] via the
/// permission domain. Matches [AppRoutes.patients] `requiredPermissions`.
/// [RouteAccessCatalog.patientsEntry] historically uses `patients:read` — keep
/// catalog; page / atom maps use this matrix ∩ key.
const AccessRequirement patientRegistryReadRequirement = AccessRequirement(
  allPermissions: <AppPermission>[AppPermissions.patientRead],
);

/// Alias used by tab atom maps / prompts.
const AccessRequirement patientReadRequirement = patientRegistryReadRequirement;

/// Route entry — AppRoutes ∩ `patient:read` + module (matrix). Catalog atom
/// [RouteAccessCatalog.patientsEntry] uses `patients:read` — note in tests.
const AccessRequirement patientRegistryEntryRequirement = AccessRequirement(
  allPermissions: <AppPermission>[AppPermissions.patientRead],
  activeModules: <String>[patientRegistryModule],
);

/// Catalog route-entry atom (`patients:read` + module) — reuse only when
/// matching shell catalog checks; UI chrome uses [patientRegistryReadRequirement].
const AccessRequirement patientRegistryCatalogEntryRequirement =
    RouteAccessCatalog.patientsEntry;

/// Create / update (register, edit, complete record, schedule, duplicate).
///
/// Matrix ∩ `patient:write`. Source inventory (`screens/patients.md`) documents
/// the same gate for register / edit / complete / schedule / duplicate review.
const AccessRequirement patientRegistryWriteRequirement = AccessRequirement(
  allPermissions: <AppPermission>[AppPermissions.patientWrite],
);

/// Alias used by tab atom maps / prompts.
const AccessRequirement patientWriteRequirement = patientRegistryWriteRequirement;

/// Delete patient / related records (matrix ∩ `patient:delete`).
const AccessRequirement patientRegistryDeleteRequirement = AccessRequirement(
  allPermissions: <AppPermission>[AppPermissions.patientDelete],
);

/// Alias used by tab atom maps / prompts.
const AccessRequirement patientDeleteRequirement =
    patientRegistryDeleteRequirement;

/// Soft-delete restore uses the same `patient:delete` gate.
const AccessRequirement patientRegistryRestoreRequirement =
    patientRegistryDeleteRequirement;

/// Permanent purge: `patient:delete` ∩ any admin grant.
const AccessRequirement patientRegistryPermanentDeleteRequirement =
    AccessRequirement(
      allPermissions: <AppPermission>[AppPermissions.patientDelete],
      anyPermissions: <AppPermission>[
        AppPermissions.facilityAdmin,
        AppPermissions.tenantAdmin,
        AppPermissions.platformAdmin,
        AppPermissions.platformOwner,
      ],
    );

/// Schedule appointment / appointment Active Work continue (source ∩ write).
const AccessRequirement patientAppointmentWriteRequirement =
    patientRegistryWriteRequirement;

/// Start / continue OPD — source keeps [opdEncounterPermissionRequirement]
/// (roles + `scheduling-queue`), not matrix ∩ alone.
const AccessRequirement patientOpdEncounterRequirement =
    opdEncounterPermissionRequirement;

/// View / continue active OPD when no Active Work OPD item (source ∪).
const AccessRequirement patientOpdViewActiveRequirement = AccessRequirement(
  anyPermissions: <AppPermission>[
    AppPermissions.clinicalRead,
    AppPermissions.clinicalWrite,
    AppPermissions.billingRead,
    AppPermissions.billingWrite,
  ],
);

/// Request admission / discharge handoff (source ∪ clinical:write + IPD module).
const AccessRequirement patientAdmissionWriteRequirement = AccessRequirement(
  anyPermissions: <AppPermission>[AppPermissions.clinicalWrite],
  activeModules: <String>['inpatient-bed-management'],
);

/// Lab order create / Active Work continue.
///
/// Source inventory shorthand used `lab`; subscription slug is `lab-workflows`
/// ([PermissionModuleMap] / [labWorkflowsModule]).
const AccessRequirement patientLabOrderWriteRequirement = AccessRequirement(
  anyPermissions: <AppPermission>[AppPermissions.clinicalWrite],
  activeModules: <String>['lab-workflows'],
);

/// Radiology order create / Active Work continue (`radiology-workflows`).
const AccessRequirement patientRadiologyOrderWriteRequirement =
    AccessRequirement(
      anyPermissions: <AppPermission>[AppPermissions.clinicalWrite],
      activeModules: <String>['radiology-workflows'],
    );

/// Theater schedule create / Active Work continue (`theatre-anesthesia`).
const AccessRequirement patientTheaterWriteRequirement = AccessRequirement(
  anyPermissions: <AppPermission>[AppPermissions.clinicalWrite],
  activeModules: <String>['theatre-anesthesia'],
);

/// Physiotherapy create / Active Work continue.
const AccessRequirement patientPhysiotherapyWriteRequirement = AccessRequirement(
  anyPermissions: <AppPermission>[AppPermissions.clinicalWrite],
  activeModules: <String>['physiotherapy'],
);

/// Enroll insurance (source ∪ patient|billing|clinical write + claims module).
///
/// Prompt narrative mentions billing:read/write ∩; source inventory keeps this
/// union — keep source and map in tests.
const AccessRequirement patientEnrollInsuranceRequirement = AccessRequirement(
  anyPermissions: <AppPermission>[
    AppPermissions.patientWrite,
    AppPermissions.billingWrite,
    AppPermissions.clinicalWrite,
  ],
  activeModules: <String>['insurance-claims'],
);

/// Patient report preview (matrix / source ∩ `reports:read`).
const AccessRequirement patientReportReadRequirement = AccessRequirement(
  allPermissions: <AppPermission>[AppPermissions.reportsRead],
);

/// Registry list Export / Print (worklist Excel + preview print).
///
/// Uses ∩ `evidence:export` (same atom as Reception desk export gate).
const AccessRequirement patientRegistryExportRequirement = AccessRequirement(
  allPermissions: <AppPermission>[AppPermissions.evidenceExport],
);

/// Alias — Print uses the same registry export gate.
const AccessRequirement patientRegistryPrintRequirement =
    patientRegistryExportRequirement;

bool canExportPatientRegistry(AppAccessPolicy policy) {
  return patientRegistryExportRequirement.isAllowed(policy);
}

bool canPrintPatientRegistry(AppAccessPolicy policy) {
  return patientRegistryPrintRequirement.isAllowed(policy);
}

/// Billing context panel open-workbench (matrix ∩ `billing:write` + module).
///
/// Balance-due nested write row; Active reuses the same helper.
const AccessRequirement patientBillingWorkbenchRequirement = AccessRequirement(
  allPermissions: <AppPermission>[AppPermissions.billingWrite],
  activeModules: <String>['billing-payments'],
);

/// Balance due tab view / read UI (matrix ∩ `patient:read` + `billing:read`).
///
/// Plan modules resolve via [PermissionModuleMap] to `patient-registry` and
/// `billing-payments`.
const AccessRequirement patientBalanceDueReadRequirement = AccessRequirement(
  allPermissions: <AppPermission>[
    AppPermissions.patientRead,
    AppPermissions.billingRead,
  ],
);

/// Nested billing write on Balance due (matrix ∩ `billing:write`).
const AccessRequirement patientBalanceDueBillingWriteRequirement =
    patientBillingWorkbenchRequirement;

/// Pharmacy context panel open-workbench (∩ `pharmacy:read`).
const AccessRequirement patientPharmacyWorkbenchRequirement = AccessRequirement(
  allPermissions: <AppPermission>[AppPermissions.pharmacyRead],
);

bool isPharmacyRegistryReader(AppAccessPolicy policy) {
  return policy.grants(AppPermissions.pharmacyRead) &&
      !policy.grants(AppPermissions.patientWrite);
}

bool isBillingRegistryReader(AppAccessPolicy policy) {
  return policy.grants(AppPermissions.billingRead) &&
      !policy.grants(AppPermissions.patientWrite);
}

bool canReadPatientRegistry(AppAccessPolicy policy) {
  return patientRegistryReadRequirement.isAllowed(policy);
}

bool canWritePatientRegistry(AppAccessPolicy policy) {
  return patientRegistryWriteRequirement.isAllowed(policy);
}

bool canDeletePatientRegistry(AppAccessPolicy policy) {
  return patientRegistryDeleteRequirement.isAllowed(policy);
}

bool canRestorePatientRegistry(AppAccessPolicy policy) {
  return patientRegistryRestoreRequirement.isAllowed(policy);
}

bool canPermanentlyDeletePatientRegistry(AppAccessPolicy policy) {
  return patientRegistryPermanentDeleteRequirement.isAllowed(policy);
}

bool canEnterPatientRegistry(AppAccessPolicy policy) {
  return patientRegistryEntryRequirement.isAllowed(policy);
}

bool canViewPatientAllTab(AppAccessPolicy policy) {
  return PatientAllAtomPermissions.tab.isAllowed(policy);
}

bool canViewPatientActiveTab(AppAccessPolicy policy) {
  return PatientActiveAtomPermissions.tab.isAllowed(policy);
}

bool canViewPatientBalanceDueTab(AppAccessPolicy policy) {
  return PatientBalanceDueAtomPermissions.tab.isAllowed(policy);
}

bool canViewPatientAdmittedTab(AppAccessPolicy policy) {
  return PatientAdmittedAtomPermissions.tab.isAllowed(policy);
}

/// Admitted nested cross-module read (matrix ∪ `clinical:read` | `billing:read`).
///
/// Gates admission visit/status columns, financial status, and clinical Active
/// Work bodies on the Admitted tab. Write chips keep their source module gates.
const AccessRequirement patientAdmittedNestedReadRequirement =
    AccessRequirement(
      anyPermissions: <AppPermission>[
        AppPermissions.clinicalRead,
        AppPermissions.billingRead,
      ],
    );

/// Financial status / outstanding-balance chrome on Admitted (∩ `billing:read`).
const AccessRequirement patientAdmittedFinancialStatusRequirement =
    AccessRequirement(
      allPermissions: <AppPermission>[AppPermissions.billingRead],
    );

/// Active Work Continue gate per in-flight kind (matches Quick Action sources).
AccessRequirement patientActiveWorkContinueRequirement(
  PatientActiveWorkKind kind,
) {
  return switch (kind) {
    PatientActiveWorkKind.appointment => patientAppointmentWriteRequirement,
    PatientActiveWorkKind.encounter ||
    PatientActiveWorkKind.queue => patientOpdEncounterRequirement,
    PatientActiveWorkKind.admission => patientAdmissionWriteRequirement,
    PatientActiveWorkKind.labOrder => patientLabOrderWriteRequirement,
    PatientActiveWorkKind.radiologyOrder =>
      patientRadiologyOrderWriteRequirement,
    PatientActiveWorkKind.theater => patientTheaterWriteRequirement,
    PatientActiveWorkKind.therapy => patientPhysiotherapyWriteRequirement,
  };
}

/// Whether an Active Work kind exposes nested clinical/billing data on Admitted.
bool patientActiveWorkKindRequiresAdmittedNestedRead(
  PatientActiveWorkKind kind,
) {
  return switch (kind) {
    PatientActiveWorkKind.appointment => false,
    PatientActiveWorkKind.encounter ||
    PatientActiveWorkKind.queue ||
    PatientActiveWorkKind.admission ||
    PatientActiveWorkKind.labOrder ||
    PatientActiveWorkKind.radiologyOrder ||
    PatientActiveWorkKind.theater ||
    PatientActiveWorkKind.therapy => true,
  };
}

/// Filters Active Work for Admitted nested-read: clinical/billing kinds absent
/// without ∪ `clinical:read` | `billing:read`; appointments remain.
List<PatientActiveWorkItem> filterPatientActiveWorkForAdmittedNestedRead(
  List<PatientActiveWorkItem> items,
  AppAccessPolicy policy,
) {
  if (PatientAdmittedAtomPermissions.nestedRead.isAllowed(policy)) {
    return items;
  }
  return items
      .where(
        (PatientActiveWorkItem item) =>
            !patientActiveWorkKindRequiresAdmittedNestedRead(item.kind),
      )
      .toList(growable: false);
}

/// Per-tab read gates. Balance due needs ∩ `patient:read` + `billing:read`;
/// other tabs keep ∩ `patient:read`.
AccessRequirement patientRegistrySectionTabRequirement(
  PatientRegistrySection section,
) {
  return switch (section) {
    PatientRegistrySection.all => PatientAllAtomPermissions.tab,
    PatientRegistrySection.active => PatientActiveAtomPermissions.tab,
    PatientRegistrySection.admitted => PatientAdmittedAtomPermissions.tab,
    PatientRegistrySection.balanceDue => PatientBalanceDueAtomPermissions.tab,
  };
}

/// Register-patient CTA for the selected section (search-bar trailing action).
AccessRequirement patientRegistryRegisterAtom(PatientRegistrySection section) {
  return switch (section) {
    PatientRegistrySection.all => PatientAllAtomPermissions.register,
    PatientRegistrySection.active => PatientActiveAtomPermissions.register,
    PatientRegistrySection.admitted => PatientAdmittedAtomPermissions.register,
    PatientRegistrySection.balanceDue =>
      PatientBalanceDueAtomPermissions.register,
  };
}

/// Duplicate-review strip secondary for the selected section.
AccessRequirement patientRegistryDuplicateReviewAtom(
  PatientRegistrySection section,
) {
  return switch (section) {
    PatientRegistrySection.all => PatientAllAtomPermissions.duplicateReview,
    PatientRegistrySection.active =>
      PatientActiveAtomPermissions.duplicateReview,
    PatientRegistrySection.admitted =>
      PatientAdmittedAtomPermissions.duplicateReview,
    PatientRegistrySection.balanceDue =>
      PatientBalanceDueAtomPermissions.duplicateReview,
  };
}

/// Next-action Complete record for the selected section.
AccessRequirement patientRegistryNextActionCompleteAtom(
  PatientRegistrySection section,
) {
  return switch (section) {
    PatientRegistrySection.all => PatientAllAtomPermissions.nextActionComplete,
    PatientRegistrySection.active =>
      PatientActiveAtomPermissions.nextActionComplete,
    PatientRegistrySection.admitted =>
      PatientAdmittedAtomPermissions.nextActionComplete,
    PatientRegistrySection.balanceDue =>
      PatientBalanceDueAtomPermissions.nextActionComplete,
  };
}

/// Section-aware nested atom resolver for detail Quick Actions / workbench.
///
/// Falls back to the shared `*Requirement` helper when [section] is null
/// (dialogs opened outside the registry strip).
AccessRequirement patientRegistrySectionNestedAtom(
  PatientRegistrySection? section, {
  required AccessRequirement all,
  required AccessRequirement active,
  required AccessRequirement admitted,
  required AccessRequirement balanceDue,
  required AccessRequirement fallback,
}) {
  return switch (section) {
    PatientRegistrySection.all => all,
    PatientRegistrySection.active => active,
    PatientRegistrySection.admitted => admitted,
    PatientRegistrySection.balanceDue => balanceDue,
    null => fallback,
  };
}

AccessRequirement patientRegistryScheduleAppointmentAtom(
  PatientRegistrySection? section,
) {
  return patientRegistrySectionNestedAtom(
    section,
    all: PatientAllAtomPermissions.scheduleAppointment,
    active: PatientActiveAtomPermissions.scheduleAppointment,
    admitted: PatientAdmittedAtomPermissions.scheduleAppointment,
    balanceDue: PatientBalanceDueAtomPermissions.scheduleAppointment,
    fallback: patientAppointmentWriteRequirement,
  );
}

AccessRequirement patientRegistryStartOpdAtom(PatientRegistrySection? section) {
  return patientRegistrySectionNestedAtom(
    section,
    all: PatientAllAtomPermissions.startOpd,
    active: PatientActiveAtomPermissions.startOpd,
    admitted: PatientAdmittedAtomPermissions.startOpd,
    balanceDue: PatientBalanceDueAtomPermissions.startOpd,
    fallback: patientOpdEncounterRequirement,
  );
}

AccessRequirement patientRegistryViewActiveOpdAtom(
  PatientRegistrySection? section,
) {
  return patientRegistrySectionNestedAtom(
    section,
    all: PatientAllAtomPermissions.viewActiveOpd,
    active: PatientActiveAtomPermissions.viewActiveOpd,
    admitted: PatientAdmittedAtomPermissions.viewActiveOpd,
    balanceDue: PatientBalanceDueAtomPermissions.viewActiveOpd,
    fallback: patientOpdViewActiveRequirement,
  );
}

AccessRequirement patientRegistryRequestAdmissionAtom(
  PatientRegistrySection? section,
) {
  return patientRegistrySectionNestedAtom(
    section,
    all: PatientAllAtomPermissions.requestAdmission,
    active: PatientActiveAtomPermissions.requestAdmission,
    admitted: PatientAdmittedAtomPermissions.requestAdmission,
    balanceDue: PatientBalanceDueAtomPermissions.requestAdmission,
    fallback: patientAdmissionWriteRequirement,
  );
}

AccessRequirement patientRegistryDischargeAtom(PatientRegistrySection? section) {
  return patientRegistrySectionNestedAtom(
    section,
    all: PatientAllAtomPermissions.discharge,
    active: PatientActiveAtomPermissions.discharge,
    admitted: PatientAdmittedAtomPermissions.discharge,
    balanceDue: PatientBalanceDueAtomPermissions.discharge,
    fallback: patientAdmissionWriteRequirement,
  );
}

AccessRequirement patientRegistryLabOrderAtom(PatientRegistrySection? section) {
  return patientRegistrySectionNestedAtom(
    section,
    all: PatientAllAtomPermissions.labOrder,
    active: PatientActiveAtomPermissions.labOrder,
    admitted: PatientAdmittedAtomPermissions.labOrder,
    balanceDue: PatientBalanceDueAtomPermissions.labOrder,
    fallback: patientLabOrderWriteRequirement,
  );
}

AccessRequirement patientRegistryRadiologyOrderAtom(
  PatientRegistrySection? section,
) {
  return patientRegistrySectionNestedAtom(
    section,
    all: PatientAllAtomPermissions.radiologyOrder,
    active: PatientActiveAtomPermissions.radiologyOrder,
    admitted: PatientAdmittedAtomPermissions.radiologyOrder,
    balanceDue: PatientBalanceDueAtomPermissions.radiologyOrder,
    fallback: patientRadiologyOrderWriteRequirement,
  );
}

AccessRequirement patientRegistryTheaterScheduleAtom(
  PatientRegistrySection? section,
) {
  return patientRegistrySectionNestedAtom(
    section,
    all: PatientAllAtomPermissions.theaterSchedule,
    active: PatientActiveAtomPermissions.theaterSchedule,
    admitted: PatientAdmittedAtomPermissions.theaterSchedule,
    balanceDue: PatientBalanceDueAtomPermissions.theaterSchedule,
    fallback: patientTheaterWriteRequirement,
  );
}

AccessRequirement patientRegistryPhysiotherapyAtom(
  PatientRegistrySection? section,
) {
  return patientRegistrySectionNestedAtom(
    section,
    all: PatientAllAtomPermissions.physiotherapy,
    active: PatientActiveAtomPermissions.physiotherapy,
    admitted: PatientAdmittedAtomPermissions.physiotherapy,
    balanceDue: PatientBalanceDueAtomPermissions.physiotherapy,
    fallback: patientPhysiotherapyWriteRequirement,
  );
}

AccessRequirement patientRegistryEnrollInsuranceAtom(
  PatientRegistrySection? section,
) {
  return patientRegistrySectionNestedAtom(
    section,
    all: PatientAllAtomPermissions.enrollInsurance,
    active: PatientActiveAtomPermissions.enrollInsurance,
    admitted: PatientAdmittedAtomPermissions.enrollInsurance,
    balanceDue: PatientBalanceDueAtomPermissions.enrollInsurance,
    fallback: patientEnrollInsuranceRequirement,
  );
}

AccessRequirement patientRegistryReportAtom(PatientRegistrySection? section) {
  return patientRegistrySectionNestedAtom(
    section,
    all: PatientAllAtomPermissions.report,
    active: PatientActiveAtomPermissions.report,
    admitted: PatientAdmittedAtomPermissions.report,
    balanceDue: PatientBalanceDueAtomPermissions.report,
    fallback: patientReportReadRequirement,
  );
}

AccessRequirement patientRegistryBillingWorkbenchAtom(
  PatientRegistrySection? section,
) {
  return patientRegistrySectionNestedAtom(
    section,
    all: PatientAllAtomPermissions.billingWorkbench,
    active: PatientActiveAtomPermissions.billingWorkbench,
    admitted: PatientAdmittedAtomPermissions.billingWorkbench,
    balanceDue: PatientBalanceDueAtomPermissions.billingWorkbench,
    fallback: patientBillingWorkbenchRequirement,
  );
}

AccessRequirement patientRegistryPharmacyWorkbenchAtom(
  PatientRegistrySection? section,
) {
  return patientRegistrySectionNestedAtom(
    section,
    all: PatientAllAtomPermissions.pharmacyWorkbench,
    active: PatientActiveAtomPermissions.pharmacyWorkbench,
    admitted: PatientAdmittedAtomPermissions.pharmacyWorkbench,
    balanceDue: PatientBalanceDueAtomPermissions.pharmacyWorkbench,
    fallback: patientPharmacyWorkbenchRequirement,
  );
}

bool canViewPatientRegistrySection(
  AppAccessPolicy policy,
  PatientRegistrySection section,
) {
  return patientRegistrySectionTabRequirement(section).isAllowed(policy);
}

/// Tabs the user may open; empty when registry read fails.
List<PatientRegistrySection> patientRegistryAllowedSections(
  AppAccessPolicy policy,
) {
  return PatientRegistrySection.values
      .where(
        (PatientRegistrySection section) =>
            canViewPatientRegistrySection(policy, section),
      )
      .toList(growable: false);
}

/// First allowed section when a deep link targets a denied tab.
PatientRegistrySection? patientRegistryFallbackSection(
  AppAccessPolicy policy,
) {
  final List<PatientRegistrySection> allowed =
      patientRegistryAllowedSections(policy);
  if (allowed.isEmpty) {
    return null;
  }
  return allowed.first;
}

/// Atom → requirement map for Patients registry **All patients**
/// (`/patients` / `?section=all`).
///
/// Inventory: `screens/patients.md` → full registry list; Register patient +
/// Duplicate review on search trailing. Nested matrix rows are _(n/a)_; Quick Action /
/// Active Work continues keep source module + clinical gates (documented
/// below). Route entry uses AppRoutes ∩ `patient:read` ([entry]); catalog
/// `patients:read` is [catalogEntry].
///
/// | Atom | Kind | Gate |
/// | --- | --- | --- |
/// | All patients strip tab / count | navigate | read ∩ `patient:read` |
/// | Register patient (search trailing) | create | write ∩ `patient:write` |
/// | Duplicate review (search trailing) | update | write ∩ |
/// | Search / Clear / Filters / Settings / columns | read chrome | read ∩ |
/// | Export / Print (table toolbar) | export | ∩ `evidence:export` |
/// | Empty / loading / error / retry | read chrome | read ∩ |
/// | Success snackbar / validation (authorized) | visible feedback | write ∩ |
/// | Row select → patient detail | read | read ∩ |
/// | Next action Complete record | update | write ∩ |
/// | Next action Open record (label) | progressive disclosure | read ∩ |
/// | Detail Edit | update | write ∩ |
/// | Detail Delete | delete | delete ∩ `patient:delete` |
/// | Detail Restore | update | delete ∩ `patient:delete` |
/// | Detail Permanent delete | delete | delete ∩ + admin grant |
/// | Active Work Continue (appointment) | update | write ∩ |
/// | Active Work Continue (OPD) | update / navigate | OPD encounter source |
/// | Active Work Continue (admission) | update | clinical write + IPD module |
/// | Active Work Continue (lab/rad/theater/therapy) | navigate | clinical write + module |
/// | Quick Action Schedule appointment | create | write ∩ |
/// | Quick Action Start OPD | create | OPD encounter source |
/// | Quick Action View/Continue OPD | navigate | clinical\|billing ∪ |
/// | Quick Action Request admission / Discharge | create / update | clinical write + IPD |
/// | Quick Action Lab / Radiology / Theater / Physio | create | clinical write + module |
/// | Quick Action Enroll insurance | create | source ∪ + claims module |
/// | Quick Action Report | export / read | reports:read ∩ |
/// | Related record add/edit | create / update | write ∩ |
/// | Related record delete | delete | delete ∩ |
/// | Pharmacy / billing context panels | nested read | role reader helpers |
/// | Open billing workbench | navigate | billing:write ∪ + module |
/// | Open pharmacy workbench | navigate | pharmacy:read ∩ |
/// | Route entry (deep link) | navigate | patient:read ∩ + module |
abstract final class PatientAllAtomPermissions {
  static const AccessRequirement tab = patientRegistryReadRequirement;
  static const AccessRequirement listChrome = patientRegistryReadRequirement;
  static const AccessRequirement search = patientRegistryReadRequirement;
  static const AccessRequirement filters = patientRegistryReadRequirement;
  static const AccessRequirement settings = patientRegistryReadRequirement;
  static const AccessRequirement export = patientRegistryExportRequirement;
  static const AccessRequirement print = patientRegistryPrintRequirement;
  static const AccessRequirement pagination = patientRegistryReadRequirement;
  static const AccessRequirement empty = patientRegistryReadRequirement;
  static const AccessRequirement loading = patientRegistryReadRequirement;
  static const AccessRequirement retry = patientRegistryReadRequirement;
  static const AccessRequirement success = patientRegistryWriteRequirement;
  static const AccessRequirement validation = patientRegistryWriteRequirement;
  static const AccessRequirement rowSelect = patientRegistryReadRequirement;
  static const AccessRequirement detail = patientRegistryReadRequirement;
  static const AccessRequirement nextActionComplete =
      patientRegistryWriteRequirement;
  static const AccessRequirement nextActionOpenRecord =
      patientRegistryReadRequirement;
  static const AccessRequirement create = patientRegistryWriteRequirement;
  static const AccessRequirement update = patientRegistryWriteRequirement;
  static const AccessRequirement delete = patientRegistryDeleteRequirement;
  static const AccessRequirement restore = patientRegistryRestoreRequirement;
  static const AccessRequirement permanentDelete =
      patientRegistryPermanentDeleteRequirement;
  static const AccessRequirement write = patientRegistryWriteRequirement;
  static const AccessRequirement register = patientRegistryWriteRequirement;
  static const AccessRequirement duplicateReview =
      patientRegistryWriteRequirement;
  static const AccessRequirement edit = patientRegistryWriteRequirement;
  static const AccessRequirement scheduleAppointment =
      patientAppointmentWriteRequirement;
  static const AccessRequirement startOpd = patientOpdEncounterRequirement;
  static const AccessRequirement viewActiveOpd = patientOpdViewActiveRequirement;
  static const AccessRequirement requestAdmission =
      patientAdmissionWriteRequirement;
  static const AccessRequirement discharge = patientAdmissionWriteRequirement;
  static const AccessRequirement labOrder = patientLabOrderWriteRequirement;
  static const AccessRequirement radiologyOrder =
      patientRadiologyOrderWriteRequirement;
  static const AccessRequirement theaterSchedule = patientTheaterWriteRequirement;
  static const AccessRequirement physiotherapy =
      patientPhysiotherapyWriteRequirement;
  static const AccessRequirement enrollInsurance =
      patientEnrollInsuranceRequirement;
  static const AccessRequirement report = patientReportReadRequirement;
  static const AccessRequirement activeWorkContinueAppointment =
      patientAppointmentWriteRequirement;
  static const AccessRequirement activeWorkContinueOpd =
      patientOpdEncounterRequirement;
  static const AccessRequirement activeWorkContinueAdmission =
      patientAdmissionWriteRequirement;
  static const AccessRequirement activeWorkContinueLab =
      patientLabOrderWriteRequirement;
  static const AccessRequirement activeWorkContinueRadiology =
      patientRadiologyOrderWriteRequirement;
  static const AccessRequirement activeWorkContinueTheater =
      patientTheaterWriteRequirement;
  static const AccessRequirement activeWorkContinueTherapy =
      patientPhysiotherapyWriteRequirement;
  static const AccessRequirement billingWorkbench =
      patientBillingWorkbenchRequirement;
  static const AccessRequirement pharmacyWorkbench =
      patientPharmacyWorkbenchRequirement;
  /// Nested cross-module write — matrix _(n/a)_; reuses clinical+module sources.
  static const AccessRequirement nestedWrite = patientAdmissionWriteRequirement;
  /// Nested cross-module read — matrix _(n/a)_; reuses registry read.
  static const AccessRequirement nestedRead = patientRegistryReadRequirement;
  static const AccessRequirement entry = patientRegistryEntryRequirement;
  static const AccessRequirement routeEntry = patientRegistryEntryRequirement;
  static const AccessRequirement catalogEntry =
      patientRegistryCatalogEntryRequirement;
  static const AccessRequirement read = patientRegistryReadRequirement;
}

/// Atom → requirement map for Patients registry **Active**
/// (`/patients?section=active`).
///
/// Inventory: `screens/patients.md` → Active tab (active outpatients / open
/// visits; same CRUD as registry). Nested matrix rows are _(n/a)_; Quick Action
/// / Active Work continues keep source module + clinical gates (documented
/// below). Route entry uses AppRoutes ∩ `patient:read` ([entry]); catalog
/// `patients:read` is [catalogEntry].
///
/// | Atom | Kind | Gate |
/// | --- | --- | --- |
/// | Active strip tab / count | navigate | read ∩ `patient:read` |
/// | Register patient (search trailing) | create | write ∩ `patient:write` |
/// | Duplicate review (search trailing) | update | write ∩ |
/// | Search / Clear / Filters / Settings / columns | read chrome | read ∩ |
/// | Export / Print (table toolbar) | export | ∩ `evidence:export` |
/// | Empty / loading / error / retry | read chrome | read ∩ |
/// | Success snackbar / validation (authorized) | visible feedback | write ∩ |
/// | Row select → patient detail | read | read ∩ |
/// | Next action Complete record | update | write ∩ |
/// | Next action Open record (label) | progressive disclosure | read ∩ |
/// | Detail Edit | update | write ∩ |
/// | Detail Delete | delete | delete ∩ `patient:delete` |
/// | Detail Restore | update | delete ∩ `patient:delete` |
/// | Detail Permanent delete | delete | delete ∩ + admin grant |
/// | Active Work Continue (appointment) | update | write ∩ |
/// | Active Work Continue (OPD) | update / navigate | OPD encounter source |
/// | Active Work Continue (admission) | update | clinical write + IPD module |
/// | Active Work Continue (lab/rad/theater/therapy) | navigate | clinical write + module |
/// | Quick Action Schedule appointment | create | write ∩ |
/// | Quick Action Start OPD | create | OPD encounter source |
/// | Quick Action View/Continue OPD | navigate | clinical\|billing ∪ |
/// | Quick Action Request admission / Discharge | create / update | clinical write + IPD |
/// | Quick Action Lab / Radiology / Theater / Physio | create | clinical write + module |
/// | Quick Action Enroll insurance | create | source ∪ + claims module |
/// | Quick Action Report | export / read | reports:read ∩ |
/// | Related record add/edit | create / update | write ∩ |
/// | Related record delete | delete | delete ∩ |
/// | Pharmacy / billing context panels | nested read | role reader helpers |
/// | Open billing workbench | navigate | billing:write ∪ + module |
/// | Open pharmacy workbench | navigate | pharmacy:read ∩ |
/// | Route entry (deep link) | navigate | patient:read ∩ + module |
abstract final class PatientActiveAtomPermissions {
  static const AccessRequirement tab = patientRegistryReadRequirement;
  static const AccessRequirement listChrome = patientRegistryReadRequirement;
  static const AccessRequirement search = patientRegistryReadRequirement;
  static const AccessRequirement filters = patientRegistryReadRequirement;
  static const AccessRequirement settings = patientRegistryReadRequirement;
  static const AccessRequirement export = patientRegistryExportRequirement;
  static const AccessRequirement print = patientRegistryPrintRequirement;
  static const AccessRequirement pagination = patientRegistryReadRequirement;
  static const AccessRequirement empty = patientRegistryReadRequirement;
  static const AccessRequirement loading = patientRegistryReadRequirement;
  static const AccessRequirement retry = patientRegistryReadRequirement;
  static const AccessRequirement success = patientRegistryWriteRequirement;
  static const AccessRequirement validation = patientRegistryWriteRequirement;
  static const AccessRequirement rowSelect = patientRegistryReadRequirement;
  static const AccessRequirement detail = patientRegistryReadRequirement;
  static const AccessRequirement nextActionComplete =
      patientRegistryWriteRequirement;
  static const AccessRequirement nextActionOpenRecord =
      patientRegistryReadRequirement;
  static const AccessRequirement create = patientRegistryWriteRequirement;
  static const AccessRequirement update = patientRegistryWriteRequirement;
  static const AccessRequirement delete = patientRegistryDeleteRequirement;
  static const AccessRequirement restore = patientRegistryRestoreRequirement;
  static const AccessRequirement permanentDelete =
      patientRegistryPermanentDeleteRequirement;
  static const AccessRequirement write = patientRegistryWriteRequirement;
  static const AccessRequirement register = patientRegistryWriteRequirement;
  static const AccessRequirement duplicateReview =
      patientRegistryWriteRequirement;
  static const AccessRequirement edit = patientRegistryWriteRequirement;
  static const AccessRequirement scheduleAppointment =
      patientAppointmentWriteRequirement;
  static const AccessRequirement startOpd = patientOpdEncounterRequirement;
  static const AccessRequirement viewActiveOpd = patientOpdViewActiveRequirement;
  static const AccessRequirement requestAdmission =
      patientAdmissionWriteRequirement;
  static const AccessRequirement discharge = patientAdmissionWriteRequirement;
  static const AccessRequirement labOrder = patientLabOrderWriteRequirement;
  static const AccessRequirement radiologyOrder =
      patientRadiologyOrderWriteRequirement;
  static const AccessRequirement theaterSchedule = patientTheaterWriteRequirement;
  static const AccessRequirement physiotherapy =
      patientPhysiotherapyWriteRequirement;
  static const AccessRequirement enrollInsurance =
      patientEnrollInsuranceRequirement;
  static const AccessRequirement report = patientReportReadRequirement;
  static const AccessRequirement activeWorkContinueAppointment =
      patientAppointmentWriteRequirement;
  static const AccessRequirement activeWorkContinueOpd =
      patientOpdEncounterRequirement;
  static const AccessRequirement activeWorkContinueAdmission =
      patientAdmissionWriteRequirement;
  static const AccessRequirement activeWorkContinueLab =
      patientLabOrderWriteRequirement;
  static const AccessRequirement activeWorkContinueRadiology =
      patientRadiologyOrderWriteRequirement;
  static const AccessRequirement activeWorkContinueTheater =
      patientTheaterWriteRequirement;
  static const AccessRequirement activeWorkContinueTherapy =
      patientPhysiotherapyWriteRequirement;
  static const AccessRequirement billingWorkbench =
      patientBillingWorkbenchRequirement;
  static const AccessRequirement pharmacyWorkbench =
      patientPharmacyWorkbenchRequirement;
  /// Nested cross-module write — matrix _(n/a)_; reuses clinical+module sources.
  static const AccessRequirement nestedWrite = patientAdmissionWriteRequirement;
  /// Nested cross-module read — matrix _(n/a)_; reuses registry read.
  static const AccessRequirement nestedRead = patientRegistryReadRequirement;
  static const AccessRequirement entry = patientRegistryEntryRequirement;
  static const AccessRequirement routeEntry = patientRegistryEntryRequirement;
  static const AccessRequirement catalogEntry =
      patientRegistryCatalogEntryRequirement;
  static const AccessRequirement read = patientRegistryReadRequirement;
}

/// Atom → requirement map for Patients registry **Admitted**
/// (`/patients?section=admitted`).
///
/// Inventory: `screens/patients.md` → Admitted tab (inpatient admissions).
/// Nested matrix ∪ `clinical:read` | `billing:read` gates visit/admission
/// status columns, financial status, and clinical Active Work bodies. Admit /
/// discharge keep source clinical write + IPD module. Quick Actions keep source
/// module + clinical gates. Route entry uses AppRoutes ∩ `patient:read`
/// ([entry]); catalog `patients:read` is [catalogEntry].
///
/// | Atom | Kind | Gate |
/// | --- | --- | --- |
/// | Admitted strip tab / count | navigate | read ∩ `patient:read` |
/// | Register patient (search trailing) | create | write ∩ `patient:write` |
/// | Duplicate review (search trailing) | update | write ∩ |
/// | Search / Clear / Filters / Settings / columns | read chrome | read ∩ |
/// | Export / Print (table toolbar) | export | ∩ `evidence:export` |
/// | Visit column (admission context) | nested read | ∪ clinical\|billing read |
/// | Status badge (admission status) | nested read | ∪ clinical\|billing read |
/// | Outstanding balance filter | nested read | ∩ `billing:read` |
/// | Empty / loading / error / retry | read chrome | read ∩ |
/// | Success snackbar / validation (authorized) | visible feedback | write ∩ |
/// | Row select → patient detail | read | read ∩ |
/// | Next action Complete record | update | write ∩ |
/// | Next action Open record (label) | progressive disclosure | read ∩ |
/// | Detail Edit | update | write ∩ |
/// | Detail Delete | delete | delete ∩ `patient:delete` |
/// | Active Work clinical body | nested read | ∪ clinical\|billing read |
/// | Active Work Continue (appointment) | update | write ∩ |
/// | Active Work Continue (OPD) | update / navigate | OPD encounter source |
/// | Active Work Continue (admission) | update | clinical write + IPD module |
/// | Active Work Continue (lab/rad/theater/therapy) | navigate | clinical write + module |
/// | Quick Action Schedule appointment | create | write ∩ |
/// | Quick Action Start OPD | create | OPD encounter source |
/// | Quick Action View/Continue OPD | navigate | clinical\|billing ∪ |
/// | Quick Action Request admission / Discharge | create / update | clinical write + IPD |
/// | Quick Action Lab / Radiology / Theater / Physio | create | clinical write + module |
/// | Quick Action Enroll insurance | create | source ∪ + claims module |
/// | Quick Action Report | export / read | reports:read ∩ |
/// | Related record add/edit | create / update | write ∩ |
/// | Related record delete | delete | delete ∩ |
/// | Pharmacy / billing context panels | nested read | role reader helpers |
/// | Open billing workbench | navigate | billing:write ∪ + module |
/// | Open pharmacy workbench | navigate | pharmacy:read ∩ |
/// | Route entry (deep link) | navigate | patient:read ∩ + module |
abstract final class PatientAdmittedAtomPermissions {
  static const AccessRequirement tab = patientRegistryReadRequirement;
  static const AccessRequirement listChrome = patientRegistryReadRequirement;
  static const AccessRequirement search = patientRegistryReadRequirement;
  static const AccessRequirement filters = patientRegistryReadRequirement;
  static const AccessRequirement settings = patientRegistryReadRequirement;
  static const AccessRequirement export = patientRegistryExportRequirement;
  static const AccessRequirement print = patientRegistryPrintRequirement;
  static const AccessRequirement pagination = patientRegistryReadRequirement;
  static const AccessRequirement empty = patientRegistryReadRequirement;
  static const AccessRequirement loading = patientRegistryReadRequirement;
  static const AccessRequirement retry = patientRegistryReadRequirement;
  static const AccessRequirement success = patientRegistryWriteRequirement;
  static const AccessRequirement validation = patientRegistryWriteRequirement;
  static const AccessRequirement rowSelect = patientRegistryReadRequirement;
  static const AccessRequirement detail = patientRegistryReadRequirement;
  static const AccessRequirement nextActionComplete =
      patientRegistryWriteRequirement;
  static const AccessRequirement nextActionOpenRecord =
      patientRegistryReadRequirement;
  static const AccessRequirement create = patientRegistryWriteRequirement;
  static const AccessRequirement update = patientRegistryWriteRequirement;
  static const AccessRequirement delete = patientRegistryDeleteRequirement;
  static const AccessRequirement restore = patientRegistryRestoreRequirement;
  static const AccessRequirement permanentDelete =
      patientRegistryPermanentDeleteRequirement;
  static const AccessRequirement write = patientRegistryWriteRequirement;
  static const AccessRequirement register = patientRegistryWriteRequirement;
  static const AccessRequirement duplicateReview =
      patientRegistryWriteRequirement;
  static const AccessRequirement edit = patientRegistryWriteRequirement;
  static const AccessRequirement scheduleAppointment =
      patientAppointmentWriteRequirement;
  static const AccessRequirement startOpd = patientOpdEncounterRequirement;
  static const AccessRequirement viewActiveOpd = patientOpdViewActiveRequirement;
  static const AccessRequirement requestAdmission =
      patientAdmissionWriteRequirement;
  static const AccessRequirement discharge = patientAdmissionWriteRequirement;
  static const AccessRequirement labOrder = patientLabOrderWriteRequirement;
  static const AccessRequirement radiologyOrder =
      patientRadiologyOrderWriteRequirement;
  static const AccessRequirement theaterSchedule = patientTheaterWriteRequirement;
  static const AccessRequirement physiotherapy =
      patientPhysiotherapyWriteRequirement;
  static const AccessRequirement enrollInsurance =
      patientEnrollInsuranceRequirement;
  static const AccessRequirement report = patientReportReadRequirement;
  static const AccessRequirement activeWorkContinueAppointment =
      patientAppointmentWriteRequirement;
  static const AccessRequirement activeWorkContinueOpd =
      patientOpdEncounterRequirement;
  static const AccessRequirement activeWorkContinueAdmission =
      patientAdmissionWriteRequirement;
  static const AccessRequirement activeWorkContinueLab =
      patientLabOrderWriteRequirement;
  static const AccessRequirement activeWorkContinueRadiology =
      patientRadiologyOrderWriteRequirement;
  static const AccessRequirement activeWorkContinueTheater =
      patientTheaterWriteRequirement;
  static const AccessRequirement activeWorkContinueTherapy =
      patientPhysiotherapyWriteRequirement;
  static const AccessRequirement billingWorkbench =
      patientBillingWorkbenchRequirement;
  static const AccessRequirement pharmacyWorkbench =
      patientPharmacyWorkbenchRequirement;
  /// Nested cross-module read — matrix ∪ `clinical:read` | `billing:read`.
  static const AccessRequirement nestedRead =
      patientAdmittedNestedReadRequirement;
  /// Visit / admission-status column data on Admitted.
  static const AccessRequirement visitColumn =
      patientAdmittedNestedReadRequirement;
  /// Admission status badge when showing API admission status.
  static const AccessRequirement admissionStatus =
      patientAdmittedNestedReadRequirement;
  /// Outstanding balance / financial status chrome.
  static const AccessRequirement financialStatus =
      patientAdmittedFinancialStatusRequirement;
  /// Nested cross-module write — matrix _(n/a)_; reuses clinical+module sources.
  static const AccessRequirement nestedWrite = patientAdmissionWriteRequirement;
  static const AccessRequirement entry = patientRegistryEntryRequirement;
  static const AccessRequirement routeEntry = patientRegistryEntryRequirement;
  static const AccessRequirement catalogEntry =
      patientRegistryCatalogEntryRequirement;
  static const AccessRequirement read = patientRegistryReadRequirement;
}

/// Atom → requirement map for Patients registry **Balance due**
/// (`/patients?section=balance-due`).
///
/// Inventory: `screens/patients.md` (shared registry chrome / detail /
/// Quick Actions). Tab read is matrix ∩ `patient:read` + `billing:read`.
/// Nested write ∩ `billing:write` (billing workbench). Enroll insurance keeps
/// source ∪ (patient|billing|clinical write + claims) — note in tests.
/// Other Quick Actions / Active Work keep source clinical+module gates.
///
/// | Atom | Kind | Gate |
/// | --- | --- | --- |
/// | Balance due strip tab / count | navigate | read ∩ patient:read + billing:read |
/// | Register patient (search trailing) | create | write ∩ patient:write |
/// | Duplicate review (search trailing) | update | write ∩ |
/// | Search / Clear / Filters / Settings / columns | read chrome | tab read ∩ |
/// | Export / Print (table toolbar) | export | ∩ `evidence:export` |
/// | Empty / loading / error / retry | read chrome | tab read ∩ |
/// | Success snackbar / validation (authorized) | visible feedback | write ∩ |
/// | Row select → patient detail | read | tab read ∩ |
/// | Next action Complete record | update | write ∩ |
/// | Next action Open record (label) | progressive disclosure | tab read ∩ |
/// | Detail Edit | update | write ∩ |
/// | Detail Delete | delete | delete ∩ patient:delete |
/// | Active Work Continue (appointment) | update | write ∩ |
/// | Active Work Continue (OPD) | update / navigate | OPD encounter source |
/// | Active Work Continue (admission) | update | clinical write + IPD module |
/// | Active Work Continue (lab/rad/theater/therapy) | navigate | clinical write + module |
/// | Quick Action Schedule appointment | create | write ∩ |
/// | Quick Action Start OPD | create | OPD encounter source |
/// | Quick Action View/Continue OPD | navigate | clinical\|billing ∪ |
/// | Quick Action Request admission / Discharge | create / update | clinical write + IPD |
/// | Quick Action Lab / Radiology / Theater / Physio | create | clinical write + module |
/// | Quick Action Enroll insurance | create | source ∪ + claims (not matrix ∩ alone) |
/// | Quick Action Report | export / read | reports:read ∩ |
/// | Related record add/edit | create / update | write ∩ |
/// | Related record delete | delete | delete ∩ |
/// | Billing context panel | nested read | tab read ∩ (Balance due mounts for all viewers) |
/// | Open billing workbench | nested write / navigate | billing:write ∩ + module |
/// | Open pharmacy workbench | navigate | pharmacy:read ∩ |
/// | Route entry (deep link) | navigate | patient:read ∩ + module |
abstract final class PatientBalanceDueAtomPermissions {
  static const AccessRequirement tab = patientBalanceDueReadRequirement;
  static const AccessRequirement listChrome = patientBalanceDueReadRequirement;
  static const AccessRequirement search = patientBalanceDueReadRequirement;
  static const AccessRequirement filters = patientBalanceDueReadRequirement;
  static const AccessRequirement settings = patientBalanceDueReadRequirement;
  static const AccessRequirement export = patientRegistryExportRequirement;
  static const AccessRequirement print = patientRegistryPrintRequirement;
  static const AccessRequirement pagination = patientBalanceDueReadRequirement;
  static const AccessRequirement empty = patientBalanceDueReadRequirement;
  static const AccessRequirement loading = patientBalanceDueReadRequirement;
  static const AccessRequirement retry = patientBalanceDueReadRequirement;
  static const AccessRequirement success = patientRegistryWriteRequirement;
  static const AccessRequirement validation = patientRegistryWriteRequirement;
  static const AccessRequirement rowSelect = patientBalanceDueReadRequirement;
  static const AccessRequirement detail = patientBalanceDueReadRequirement;
  static const AccessRequirement nextActionComplete =
      patientRegistryWriteRequirement;
  static const AccessRequirement nextActionOpenRecord =
      patientBalanceDueReadRequirement;
  static const AccessRequirement create = patientRegistryWriteRequirement;
  static const AccessRequirement update = patientRegistryWriteRequirement;
  static const AccessRequirement delete = patientRegistryDeleteRequirement;
  static const AccessRequirement restore = patientRegistryRestoreRequirement;
  static const AccessRequirement permanentDelete =
      patientRegistryPermanentDeleteRequirement;
  static const AccessRequirement write = patientRegistryWriteRequirement;
  static const AccessRequirement register = patientRegistryWriteRequirement;
  static const AccessRequirement duplicateReview =
      patientRegistryWriteRequirement;
  static const AccessRequirement edit = patientRegistryWriteRequirement;
  static const AccessRequirement scheduleAppointment =
      patientAppointmentWriteRequirement;
  static const AccessRequirement startOpd = patientOpdEncounterRequirement;
  static const AccessRequirement viewActiveOpd = patientOpdViewActiveRequirement;
  static const AccessRequirement requestAdmission =
      patientAdmissionWriteRequirement;
  static const AccessRequirement discharge = patientAdmissionWriteRequirement;
  static const AccessRequirement labOrder = patientLabOrderWriteRequirement;
  static const AccessRequirement radiologyOrder =
      patientRadiologyOrderWriteRequirement;
  static const AccessRequirement theaterSchedule = patientTheaterWriteRequirement;
  static const AccessRequirement physiotherapy =
      patientPhysiotherapyWriteRequirement;
  /// Source ∪ (patient|billing|clinical write + claims); matrix narrative
  /// mentions billing read/write ∩ — keep source and map in tests.
  static const AccessRequirement enrollInsurance =
      patientEnrollInsuranceRequirement;
  static const AccessRequirement report = patientReportReadRequirement;
  static const AccessRequirement activeWorkContinueAppointment =
      patientAppointmentWriteRequirement;
  static const AccessRequirement activeWorkContinueOpd =
      patientOpdEncounterRequirement;
  static const AccessRequirement activeWorkContinueAdmission =
      patientAdmissionWriteRequirement;
  static const AccessRequirement activeWorkContinueLab =
      patientLabOrderWriteRequirement;
  static const AccessRequirement activeWorkContinueRadiology =
      patientRadiologyOrderWriteRequirement;
  static const AccessRequirement activeWorkContinueTheater =
      patientTheaterWriteRequirement;
  static const AccessRequirement activeWorkContinueTherapy =
      patientPhysiotherapyWriteRequirement;
  static const AccessRequirement billingWorkbench =
      patientBalanceDueBillingWriteRequirement;
  static const AccessRequirement pharmacyWorkbench =
      patientPharmacyWorkbenchRequirement;
  /// Nested cross-module write — matrix ∩ `billing:write`.
  static const AccessRequirement nestedWrite =
      patientBalanceDueBillingWriteRequirement;
  /// Nested cross-module read — matrix _(n/a)_; reuses tab read ∩.
  static const AccessRequirement nestedRead = patientBalanceDueReadRequirement;
  static const AccessRequirement entry = patientRegistryEntryRequirement;
  static const AccessRequirement routeEntry = patientRegistryEntryRequirement;
  static const AccessRequirement catalogEntry =
      patientRegistryCatalogEntryRequirement;
  static const AccessRequirement read = patientBalanceDueReadRequirement;
}
