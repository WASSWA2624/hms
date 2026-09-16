part of '../pages/patient_registry_page.dart';

Future<void> showPatientDetailDialog(
  BuildContext context,
  WidgetRef ref,
  String patientId, {
  bool allowBillingNavigation = true,
  PatientRegistrySection? registrySection,
}) async {
  unawaited(
    ref
        .read(patientRegistryControllerProvider.notifier)
        .selectPatient(patientId)
        .then((AppFailure? failure) async {
          if (context.mounted) {
            await _showFailureIfNeeded(context, failure);
          }
        }),
  );

  await showAppDialog<void>(
    context: context,
    builder: (_) => PatientDetailDialog(
      patientId: patientId,
      allowBillingNavigation: allowBillingNavigation,
      registrySection: registrySection,
    ),
  );

  if (context.mounted) {
    ref.read(patientRegistryControllerProvider.notifier).clearSelection();
  }
}

Future<void> showPatientEditDialog(
  BuildContext context,
  WidgetRef ref,
  Patient patient,
) async {
  final bool? saved = await showAppDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PatientFormDialog(
      patient: patient,
      referenceData:
          _readCurrentState(ref)?.referenceData ??
          const PatientReferenceData(),
      onSubmit: (Map<String, Object?> payload) {
        return ref
            .read(patientRegistryControllerProvider.notifier)
            .updatePatient(patient.id, payload);
      },
    ),
  );

  if (saved == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.patientsSavedMessage)),
    );
  }
}

class PatientDetailDialog extends ConsumerWidget {
  const PatientDetailDialog({
    required this.patientId,
    this.allowBillingNavigation = true,
    this.registrySection,
    super.key,
  });

  final String patientId;
  final bool allowBillingNavigation;
  final PatientRegistrySection? registrySection;

  AccessRequirement get _editRequirement {
    return switch (registrySection) {
      PatientRegistrySection.all => PatientAllAtomPermissions.edit,
      PatientRegistrySection.active => PatientActiveAtomPermissions.edit,
      PatientRegistrySection.admitted => PatientAdmittedAtomPermissions.edit,
      PatientRegistrySection.balanceDue =>
        PatientBalanceDueAtomPermissions.edit,
      null => patientRegistryWriteRequirement,
    };
  }

  AccessRequirement get _deleteRequirement {
    return switch (registrySection) {
      PatientRegistrySection.all => PatientAllAtomPermissions.delete,
      PatientRegistrySection.active => PatientActiveAtomPermissions.delete,
      PatientRegistrySection.admitted => PatientAdmittedAtomPermissions.delete,
      PatientRegistrySection.balanceDue =>
        PatientBalanceDueAtomPermissions.delete,
      null => patientRegistryDeleteRequirement,
    };
  }

  AccessRequirement get _restoreRequirement {
    return switch (registrySection) {
      PatientRegistrySection.all => PatientAllAtomPermissions.restore,
      PatientRegistrySection.active => PatientActiveAtomPermissions.restore,
      PatientRegistrySection.admitted => PatientAdmittedAtomPermissions.restore,
      PatientRegistrySection.balanceDue =>
        PatientBalanceDueAtomPermissions.restore,
      null => patientRegistryRestoreRequirement,
    };
  }

  AccessRequirement get _permanentDeleteRequirement {
    return switch (registrySection) {
      PatientRegistrySection.all => PatientAllAtomPermissions.permanentDelete,
      PatientRegistrySection.active =>
        PatientActiveAtomPermissions.permanentDelete,
      PatientRegistrySection.admitted =>
        PatientAdmittedAtomPermissions.permanentDelete,
      PatientRegistrySection.balanceDue =>
        PatientBalanceDueAtomPermissions.permanentDelete,
      null => patientRegistryPermanentDeleteRequirement,
    };
  }

  AccessRequirement get _writeRequirement {
    return switch (registrySection) {
      PatientRegistrySection.all => PatientAllAtomPermissions.write,
      PatientRegistrySection.active => PatientActiveAtomPermissions.write,
      PatientRegistrySection.admitted => PatientAdmittedAtomPermissions.write,
      PatientRegistrySection.balanceDue =>
        PatientBalanceDueAtomPermissions.write,
      null => patientRegistryWriteRequirement,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final Result<PatientRegistryState>? result = ref
        .watch(patientRegistryControllerProvider)
        .asData
        ?.value;
    final PatientRegistryState? state = switch (result) {
      ResultSuccess<PatientRegistryState>(value: final value) => value,
      _ => null,
    };
    final PatientDetail? selectedDetail = state?.selectedDetail;
    final PatientDetail? detail = selectedDetail?.patient.id == patientId
        ? selectedDetail
        : null;
    final Patient? cachedPatient = _cachedPatientFromState(state, patientId);
    final bool isLoadingDetail =
        (state?.isRefreshingDetail ?? true) && detail == null;

    if (isLoadingDetail) {
      final String dialogTitle = l10n.patientsDetailTitle;
      return AppDialog(
        title: Text(dialogTitle),
        icon: const Icon(Icons.assignment_ind_outlined),
        maxWidth: 980,
        scrollable: true,
        content: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: Column(
            key: ValueKey<String>('loading-$patientId'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const LinearProgressIndicator(),
              if (cachedPatient != null) ...<Widget>[
                SizedBox(height: Theme.of(context).spacing.md),
                _PatientListPreviewHeader(patient: cachedPatient),
                const Divider(),
              ],
              SizedBox(
                height: cachedPatient == null ? 320 : null,
                child: cachedPatient == null
                    ? AppWorkspaceStatePanel.loading(
                        title: l10n.patientsDetailLoadingTitle,
                        body: l10n.patientsDetailLoadingBody,
                        minHeight: 320,
                      )
                    : Padding(
                        padding: EdgeInsets.only(
                          top: Theme.of(context).spacing.md,
                        ),
                        child: const AppPatientDetailSkeleton(),
                      ),
              ),
            ],
          ),
        ),
      );
    }

    if (detail == null) {
      final Object? failure = state?.lastFailure;
      return AppDialog(
        title: Text(l10n.patientsDetailTitle),
        icon: const Icon(Icons.assignment_ind_outlined),
        maxWidth: 960,
        scrollable: true,
        content: failure is AppFailure
            ? AppFailureStateView(failure: failure)
            : AppWorkspaceStatePanel.empty(
                title: l10n.patientsNoSelectionTitle,
                body: l10n.patientsNoSelectionBody,
                icon: Icons.badge_outlined,
                minHeight: 320,
              ),
      );
    }

    final Patient patient = detail.patient;
    final AppAccessPolicy accessPolicy = ref.watch(appAccessPolicyProvider);
    final bool pharmacyReader = isPharmacyRegistryReader(accessPolicy);
    final bool billingReader = isBillingRegistryReader(accessPolicy);
    final bool hideClinicalSections = pharmacyReader || billingReader;
    final bool isAdmittedSection =
        registrySection == PatientRegistrySection.admitted;
    final bool isBalanceDueSection =
        registrySection == PatientRegistrySection.balanceDue;
    final bool isSaving = state?.isSaving ?? false;
    // Balance due tab read already requires billing:read; mount invoice/payment
    // chrome for any authorized Balance due viewer so nested write (Open billing
    // ∩ billing:write) is reachable for writers, not only billing-role readers.
    final bool showBillingContextPanel =
        billingReader ||
        (isBalanceDueSection &&
            PatientBalanceDueAtomPermissions.nestedRead.isAllowed(
              accessPolicy,
            ));
    return AppDialog(
      title: Text(l10n.patientsDetailTitle),
      icon: const Icon(Icons.assignment_ind_outlined),
      maxWidth: 980,
      scrollable: true,
      actions: <Widget>[
        if (!patient.isDeleted) ...<Widget>[
          AppAccessActionGate(
            requirement: _editRequirement,
            builder: (_, bool isAllowed) {
              if (!isAllowed) {
                return const SizedBox.shrink();
              }
              return AppButton.secondary(
                label: l10n.patientsEditAction,
                leadingIcon: Icons.edit_outlined,
                onPressed: () =>
                    unawaited(showPatientEditDialog(context, ref, patient)),
              );
            },
          ),
          AppAccessActionGate(
            requirement: _deleteRequirement,
            builder: (_, bool isAllowed) {
              if (!isAllowed) {
                return const SizedBox.shrink();
              }
              return AppButton.tertiary(
                label: l10n.patientsDeleteAction,
                leadingIcon: Icons.delete_outline,
                isLoading: isSaving,
                onPressed: () => unawaited(
                  _confirmSoftDeletePatient(
                    context,
                    ref,
                    patient,
                    popDetailOnSuccess: true,
                  ),
                ),
              );
            },
          ),
        ] else ...<Widget>[
          AppAccessActionGate(
            requirement: _restoreRequirement,
            builder: (_, bool isAllowed) {
              if (!isAllowed) {
                return const SizedBox.shrink();
              }
              return AppButton.secondary(
                label: l10n.patientsRestoreAction,
                leadingIcon: Icons.restore_outlined,
                isLoading: isSaving,
                onPressed: () => unawaited(
                  _confirmRestorePatient(
                    context,
                    ref,
                    patient,
                    popDetailOnSuccess: true,
                  ),
                ),
              );
            },
          ),
          AppAccessActionGate(
            requirement: _permanentDeleteRequirement,
            builder: (_, bool isAllowed) {
              if (!isAllowed) {
                return const SizedBox.shrink();
              }
              return AppButton.tertiary(
                label: l10n.patientsPermanentDeleteAction,
                leadingIcon: Icons.delete_forever_outlined,
                isLoading: isSaving,
                onPressed: () => unawaited(
                  _confirmPermanentDeletePatient(
                    context,
                    ref,
                    patient,
                    popDetailOnSuccess: true,
                  ),
                ),
              );
            },
          ),
        ],
      ],
      content: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: Column(
          key: ValueKey<String>('detail-${patient.id}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (state?.isRefreshingDetail ?? false)
              const LinearProgressIndicator(),
            AppCollapsibleSection(
              title: l10n.patientsDetailTitle,
              initiallyExpanded: true,
              collapsible: true,
              child: PatientDetailHeader(
                detail: detail,
                referenceData:
                    state?.referenceData ?? const PatientReferenceData(),
              ),
            ),
            SizedBox(height: Theme.of(context).spacing.md),
            if (!hideClinicalSections) ...<Widget>[
              PatientDetailQuickActions(
                detail: detail,
                registrySection: registrySection,
                applyAdmittedNestedReadFilter: isAdmittedSection,
                onAction: (PatientQuickAction action) =>
                    _openPatientQuickAction(
                      context,
                      ref,
                      detail.patient,
                      action,
                    ),
                onContinueActiveWork: (PatientActiveWorkItem item) =>
                    _continuePatientActiveWork(context, ref, detail, item),
              ),
              SizedBox(height: Theme.of(context).spacing.md),
            ],
            if (pharmacyReader) ...<Widget>[
              PatientPharmacyContextPanel(
                detail: detail,
                registrySection: registrySection,
              ),
              SizedBox(height: Theme.of(context).spacing.md),
            ],
            if (showBillingContextPanel) ...<Widget>[
              PatientBillingContextPanel(
                detail: detail,
                allowBillingNavigation: allowBillingNavigation,
                registrySection: registrySection,
              ),
              SizedBox(height: Theme.of(context).spacing.md),
            ],
            ...appCollapsibleSectionSpacing(context, <Widget>[
              if (!billingReader)
                AppExpandableRecordSection<PatientAllergy>(
                  title: l10n.patientsAllergiesSectionTitle,
                  emptyLabel: l10n.patientsNoAllergies,
                  items: detail.allergies,
                  initiallyExpanded: true,
                  responsiveActionButtons: true,
                  itemTitle: (PatientAllergy item) =>
                      '${l10n.patientsAllergiesSectionTitle}: ${item.allergen} (${_apiLabel(item.severity)})',
                  addLabel: l10n.commonAddActionLabel,
                  editLabel: l10n.patientsEditAction,
                  deleteLabel: l10n.patientsDeleteAction,
                  addRequirement: _writeRequirement,
                  editRequirement: _writeRequirement,
                  deleteRequirement: _deleteRequirement,
                  onAdd: () =>
                      _openRelatedForm<PatientAllergy>(context, ref, detail),
                  onEdit: (PatientAllergy item) =>
                      _openRelatedForm(context, ref, detail, item: item),
                  onDelete: (PatientAllergy item) =>
                      _confirmDeleteRelated(context, ref, detail, item.id),
                ),
              if (!hideClinicalSections)
                AppExpandableRecordSection<PatientIdentifier>(
                  title: l10n.patientsIdentifiersSectionTitle,
                  emptyLabel: l10n.patientsNoIdentifiers,
                  items: detail.identifiers,
                  initiallyExpanded: true,
                  responsiveActionButtons: true,
                  itemTitle: (PatientIdentifier item) =>
                      '${_apiLabel(item.type)}: ${item.value}',
                  addLabel: l10n.commonAddActionLabel,
                  editLabel: l10n.patientsEditAction,
                  deleteLabel: l10n.patientsDeleteAction,
                  addRequirement: _writeRequirement,
                  editRequirement: _writeRequirement,
                  deleteRequirement: _deleteRequirement,
                  onAdd: () => _openRelatedForm<PatientIdentifier>(
                    context,
                    ref,
                    detail,
                  ),
                  onEdit: (PatientIdentifier item) =>
                      _openRelatedForm(context, ref, detail, item: item),
                  onDelete: (PatientIdentifier item) =>
                      _confirmDeleteRelated(context, ref, detail, item.id),
                ),
              if (!hideClinicalSections)
                AppExpandableRecordSection<PatientContact>(
                  title: l10n.patientsContactsSectionTitle,
                  emptyLabel: l10n.patientsNoContacts,
                  items: detail.contacts,
                  initiallyExpanded: true,
                  responsiveActionButtons: true,
                  itemTitle: (PatientContact item) =>
                      '${_apiLabel(item.type)}: ${item.value}',
                  addLabel: l10n.commonAddActionLabel,
                  editLabel: l10n.patientsEditAction,
                  deleteLabel: l10n.patientsDeleteAction,
                  addRequirement: _writeRequirement,
                  editRequirement: _writeRequirement,
                  deleteRequirement: _deleteRequirement,
                  onAdd: () =>
                      _openRelatedForm<PatientContact>(context, ref, detail),
                  onEdit: (PatientContact item) =>
                      _openRelatedForm(context, ref, detail, item: item),
                  onDelete: (PatientContact item) =>
                      _confirmDeleteRelated(context, ref, detail, item.id),
                ),
              if (!hideClinicalSections)
                AppExpandableRecordSection<PatientGuardian>(
                  title: l10n.patientsGuardiansSectionTitle,
                  emptyLabel: l10n.patientsNoGuardians,
                  items: detail.guardians,
                  initiallyExpanded: true,
                  responsiveActionButtons: true,
                  itemTitle: (PatientGuardian item) =>
                      '${item.relationship == null ? l10n.patientsGuardiansSectionTitle : _apiLabel(item.relationship!)}: ${item.name}',
                  addLabel: l10n.commonAddActionLabel,
                  editLabel: l10n.patientsEditAction,
                  deleteLabel: l10n.patientsDeleteAction,
                  addRequirement: _writeRequirement,
                  editRequirement: _writeRequirement,
                  deleteRequirement: _deleteRequirement,
                  onAdd: () =>
                      _openRelatedForm<PatientGuardian>(context, ref, detail),
                  onEdit: (PatientGuardian item) =>
                      _openRelatedForm(context, ref, detail, item: item),
                  onDelete: (PatientGuardian item) =>
                      _confirmDeleteRelated(context, ref, detail, item.id),
                ),
              if (!hideClinicalSections)
                AppExpandableRecordSection<PatientMedicalHistory>(
                  title: l10n.patientsMedicalHistorySectionTitle,
                  emptyLabel: l10n.patientsNoMedicalHistory,
                  items: detail.medicalHistories,
                  initiallyExpanded: true,
                  responsiveActionButtons: true,
                  itemTitle: (PatientMedicalHistory item) {
                    final String? date = item.diagnosisDate == null
                        ? null
                        : _formatOptionalDate(context, item.diagnosisDate);
                    return date == null
                        ? item.condition
                        : '${item.condition}: $date';
                  },
                  addLabel: l10n.commonAddActionLabel,
                  editLabel: l10n.patientsEditAction,
                  deleteLabel: l10n.patientsDeleteAction,
                  addRequirement: _writeRequirement,
                  editRequirement: _writeRequirement,
                  deleteRequirement: _deleteRequirement,
                  onAdd: () => _openRelatedForm<PatientMedicalHistory>(
                    context,
                    ref,
                    detail,
                  ),
                  onEdit: (PatientMedicalHistory item) =>
                      _openRelatedForm(context, ref, detail, item: item),
                  onDelete: (PatientMedicalHistory item) =>
                      _confirmDeleteRelated(context, ref, detail, item.id),
                ),
              if (!hideClinicalSections)
                AppExpandableRecordSection<PatientConsent>(
                  title: l10n.patientsConsentsSectionTitle,
                  emptyLabel: l10n.patientsNoConsents,
                  items: detail.consents,
                  initiallyExpanded: true,
                  responsiveActionButtons: true,
                  itemTitle: (PatientConsent item) =>
                      '${_apiLabel(item.consentType)}: ${_apiLabel(item.status)}',
                  addLabel: l10n.commonAddActionLabel,
                  editLabel: l10n.patientsEditAction,
                  deleteLabel: l10n.patientsDeleteAction,
                  addRequirement: _writeRequirement,
                  editRequirement: _writeRequirement,
                  deleteRequirement: _deleteRequirement,
                  onAdd: () =>
                      _openRelatedForm<PatientConsent>(context, ref, detail),
                  onEdit: (PatientConsent item) =>
                      _openRelatedForm(context, ref, detail, item: item),
                  onDelete: (PatientConsent item) =>
                      _confirmDeleteRelated(context, ref, detail, item.id),
                ),
            ]),
            if (!hideClinicalSections) ...<Widget>[
              SizedBox(height: Theme.of(context).spacing.md),
              PatientTimelineList(items: detail.timeline),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openRelatedForm<T>(
    BuildContext context,
    WidgetRef ref,
    PatientDetail detail, {
    T? item,
  }) async {
    final PatientRelatedResource resource = _resourceForItem<T>(item);
    final bool? saved = await showAppDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PatientRelatedRecordDialog<T>(
        detail: detail,
        resource: resource,
        item: item,
        referenceData:
            _readCurrentState(ref)?.referenceData ??
            const PatientReferenceData(),
        onCreate: (Map<String, Object?> payload) {
          return ref
              .read(patientRegistryControllerProvider.notifier)
              .createRelatedRecord(resource, payload);
        },
        onUpdate: (String recordId, Map<String, Object?> payload) {
          return ref
              .read(patientRegistryControllerProvider.notifier)
              .updateRelatedRecord(resource, recordId, payload);
        },
      ),
    );

    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.patientsSavedMessage)),
      );
    }
  }

  Future<void> _confirmDeleteRelated(
    BuildContext context,
    WidgetRef ref,
    PatientDetail detail,
    String recordId,
  ) async {
    final bool? confirmed = await _showDeleteDialog(
      context,
      title: context.l10n.patientsRelatedDeleteTitle,
      body: context.l10n.patientsRelatedDeleteBody,
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    final PatientRelatedResource resource = _resourceForRecordId(
      detail,
      recordId,
    );
    final AppFailure? failure = await ref
        .read(patientRegistryControllerProvider.notifier)
        .deleteRelatedRecord(resource, recordId);
    if (context.mounted && failure == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.patientsDeletedMessage)),
      );
    } else if (context.mounted) {
      await _showFailureIfNeeded(context, failure);
    }
  }
}

class _PatientListPreviewHeader extends StatelessWidget {
  const _PatientListPreviewHeader({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final String gender = patient.gender == null
        ? l10n.profileUnknownValue
        : _genderLabel(l10n, patient.gender!);
    final String unknown = l10n.profileUnknownValue;
    final PatientVisitContext? visit = patient.currentVisit;

    return AppPatientContextFactsRow(
      fields: <AppWorkspacePatientContextField>[
        AppWorkspacePatientContextField(
          label: l10n.patientsNameLabel,
          value: patient.effectiveDisplayName,
          icon: Icons.person_outline,
        ),
        AppWorkspacePatientContextField(
          label: l10n.patientsGenderLabel,
          value: gender,
          icon: Icons.wc_outlined,
        ),
        AppWorkspacePatientContextField(
          label: l10n.patientsAgeColumnLabel,
          value: _patientAgeLabel(context, patient.dateOfBirth),
          icon: Icons.cake_outlined,
        ),
        AppWorkspacePatientContextField(
          label: l10n.patientsPhoneLabel,
          value: (patient.primaryPhone ?? '').trim().isEmpty
              ? unknown
              : patient.primaryPhone!,
          icon: Icons.phone_outlined,
        ),
        AppWorkspacePatientContextField(
          label: l10n.patientsEmailLabel,
          value: (patient.primaryEmail ?? '').trim().isEmpty
              ? unknown
              : patient.primaryEmail!,
          icon: Icons.email_outlined,
        ),
        AppWorkspacePatientContextField(
          label: l10n.patientsStatusColumnLabel,
          value: patient.isActive
              ? l10n.patientsActiveFilter
              : l10n.patientsInactiveFilter,
          icon: patient.isActive
              ? Icons.check_circle_outline
              : Icons.block_outlined,
          tone: patient.isActive
              ? AppWorkspaceStatusTone.success
              : AppWorkspaceStatusTone.neutral,
        ),
        AppWorkspacePatientContextField(
          label: l10n.patientsFacilityLabel,
          value: patient.facilityLabel ?? unknown,
          icon: Icons.business_outlined,
        ),
        if (visit != null && (visit.publicId ?? '').trim().isNotEmpty)
          AppWorkspacePatientContextField(
            label: l10n.patientsVisitColumnLabel,
            value: visit.publicId!,
            icon: Icons.assignment_turned_in_outlined,
            tone: AppWorkspaceStatusTone.info,
            copyable: true,
            copyTooltip: l10n.copyIdentifierAction,
            copiedMessage: l10n.identifierCopiedMessage,
          ),
      ],
    );
  }
}
