import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/errors/validation_message_presenter.dart';
import 'package:hosspi_hms/core/permissions/access_policy.dart';
import 'package:hosspi_hms/core/permissions/permission_providers.dart';
import 'package:hosspi_hms/core/security/session_controller.dart';
import 'package:hosspi_hms/features/access_admin/data/repositories/access_admin_repository_impl.dart';
import 'package:hosspi_hms/features/access_admin/domain/entities/access_admin_entities.dart';
import 'package:hosspi_hms/features/access_admin/domain/entities/user_account_rules.dart';
import 'package:hosspi_hms/features/tenant_facility/data/repositories/tenant_facility_repository_impl.dart';
import 'package:hosspi_hms/features/tenant_facility/domain/entities/tenant_facility_setup.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/components/components.dart';
import 'package:hosspi_hms/shared/data/data.dart';
import 'package:hosspi_hms/shared/forms/app_form_section.dart';
import 'package:hosspi_hms/shared/forms/app_password_policy.dart';
import 'package:hosspi_hms/shared/forms/app_responsive_field_row.dart';
import 'package:hosspi_hms/shared/forms/app_validators.dart';
import 'package:hosspi_hms/shared/layout/app_workspace_mutation_dialog.dart';

enum UserMutationMode { create, edit }

typedef UserMutationSubmitHandler =
    Future<AppFailure?> Function(
      AccessAdminUserDraft draft,
      List<String> roleIds,
    );

const List<String> _fallbackUserStatuses = <String>[
  'ACTIVE',
  'INACTIVE',
  'SUSPENDED',
  'PENDING',
];

Future<bool?> showUserMutationDialog({
  required BuildContext context,
  required WidgetRef ref,
  required UserMutationMode mode,
  required AccessAdminWorkspaceState state,
  AccessAdminItem? initialUser,
  AccessAdminUserDetail? initialDetail,
  required UserMutationSubmitHandler onSubmit,
}) async {
  final AppLocalizations l10n = context.l10n;
  final AppAccessPolicy accessPolicy = ref.read(appAccessPolicyProvider);
  final bool isCreate = mode == UserMutationMode.create;
  final bool isCrossTenantAdmin = accessPolicy.canCreateTenant();
  // Mirrors the API scope rule: tenant-wide admins may leave the facility blank
  // for an organization-wide account; facility-scoped admins stay in theirs.
  final bool canPlaceTenantWide =
      isCrossTenantAdmin || accessPolicy.canCreateTenantWideRole();
  final bool facilityRequired = !canPlaceTenantWide;
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
  // Admins set another account's password here. Their own changes through
  // account settings, which asks for the current password.
  final String sessionUserId =
      ref.read(sessionStateProvider).session?.user?.id?.trim() ?? '';
  final bool editsOwnAccount =
      !isCreate &&
      sessionUserId.isNotEmpty &&
      (sessionUserId == initialUser?.id.trim() ||
          sessionUserId == initialUser?.mutationId.trim());
  final bool showNewPasswordField = !isCreate && !editsOwnAccount;

  final TextEditingController emailController = TextEditingController(
    text: initialUser?.email,
  );
  final TextEditingController firstNameController = TextEditingController(
    text: initialUser?.firstName,
  );
  final TextEditingController lastNameController = TextEditingController(
    text: initialUser?.lastName,
  );
  final TextEditingController phoneController = TextEditingController(
    text: initialUser?.phone,
  );
  final TextEditingController titleController = TextEditingController(
    text: initialUser?.positionTitle,
  );
  final TextEditingController passwordController = TextEditingController();
  final List<TextEditingController> formControllers = <TextEditingController>[
    emailController,
    firstNameController,
    lastNameController,
    phoneController,
    titleController,
    passwordController,
  ];
  String status = initialUser?.status ?? 'ACTIVE';

  String? selectedTenantId =
      initialUser?.tenantId ??
      state.query.tenantId ??
      (isCrossTenantAdmin ? null : sessionTenantId);
  // Editing starts from the account's real facility, never a workspace default,
  // so saving other details cannot silently move the account.
  String? selectedFacilityId = isCreate
      ? (state.query.facilityId ??
            (isCrossTenantAdmin ? null : sessionFacilityId))
      : initialUser?.facilityId;

  // A facility-scoped admin working in a facility can only use that facility,
  // so it is known context and stays out of the form.
  final bool facilityFixedToSession =
      facilityRequired && (sessionFacilityId ?? '').isNotEmpty;
  if (facilityFixedToSession && isCreate) {
    selectedFacilityId = sessionFacilityId;
  }
  final bool showFacilityPicker = !facilityFixedToSession;
  // The API keeps an account in its tenant; only create chooses one.
  final bool showTenantPicker =
      isCreate && (isCrossTenantAdmin || (selectedTenantId ?? '').isEmpty);

  List<AccessAdminLookupOption> tenantOptions =
      const <AccessAdminLookupOption>[];
  List<AccessAdminLookupOption> facilityOptions =
      const <AccessAdminLookupOption>[];

  bool isLoadingTenants = false;
  bool tenantLoadAttempted = !showTenantPicker;
  bool scheduledInitialTenantLoad = false;

  bool isLoadingFacilities = false;
  bool facilityLoadAttempted =
      !showFacilityPicker || (selectedTenantId ?? '').isEmpty;
  bool scheduledInitialFacilityLoad = false;

  Set<String> selectedRoleIds = <String>{};
  List<AppRoleAssignmentOption> roleOptions =
      const <AppRoleAssignmentOption>[];
  bool isLoadingRoles = false;
  String? rolesLoadedForScope;
  AppFailure? roleLoadFailure;

  // Server field errors stay visible until the user edits that field.
  AppFailure? displayedFailure;
  final Set<String> editedFields = <String>{};
  bool dialogOpen = true;

  String scopeKey() => '${selectedTenantId ?? ''}|${selectedFacilityId ?? ''}';

  void resetRoleSelection() {
    selectedRoleIds = <String>{};
    roleOptions = const <AppRoleAssignmentOption>[];
    rolesLoadedForScope = null;
    roleLoadFailure = null;
  }

  String? serverErrorFor(String field) {
    final AppFailure? failure = displayedFailure;
    if (failure == null || editedFields.contains(field)) {
      return null;
    }
    final String? message = failure.messageForField(field);
    if (message == null || message.trim().isEmpty) {
      return null;
    }
    return ValidationMessagePresenter.humanizeFieldMessage(
      l10n,
      field: field,
      message: message,
    );
  }

  void markEdited(StateSetter setState, String field) {
    if (editedFields.contains(field) ||
        displayedFailure?.messageForField(field) == null) {
      return;
    }
    setState(() => editedFields.add(field));
  }

  String statusLabel(String value) {
    return switch (value.trim().toUpperCase()) {
      'ACTIVE' => l10n.accessAdminUserStatusActiveLabel,
      'INACTIVE' => l10n.accessAdminUserStatusInactiveLabel,
      'SUSPENDED' => l10n.accessAdminUserStatusSuspendedLabel,
      'PENDING' => l10n.accessAdminUserStatusPendingLabel,
      _ => value,
    };
  }

  String passwordRuleMessage(AppPasswordRule rule) {
    return switch (rule) {
      AppPasswordRule.minLength => l10n.validationPasswordMinLengthMessage(
        AppPasswordPolicy.minLength,
      ),
      AppPasswordRule.uppercase => l10n.validationPasswordUppercaseMessage,
      AppPasswordRule.lowercase => l10n.validationPasswordLowercaseMessage,
      AppPasswordRule.number => l10n.validationPasswordNumberMessage,
      AppPasswordRule.symbol => l10n.validationPasswordSymbolMessage,
    };
  }

  Future<void> reloadTenantOptions(StateSetter setState) async {
    setState(() {
      isLoadingTenants = true;
      tenantOptions = const <AccessAdminLookupOption>[];
    });

    final List<AccessAdminLookupOption> loaded = await _loadTenantOptions(
      ref,
      state,
      isCrossTenantAdmin,
    );
    if (!dialogOpen) {
      return;
    }

    setState(() {
      isLoadingTenants = false;
      tenantLoadAttempted = true;
      tenantOptions = loaded;
    });
  }

  Future<void> reloadFacilityOptions(StateSetter setState) async {
    final String? tenantId = selectedTenantId;
    if ((tenantId ?? '').isEmpty) {
      setState(() {
        facilityOptions = const <AccessAdminLookupOption>[];
        facilityLoadAttempted = true;
      });
      return;
    }

    setState(() {
      isLoadingFacilities = true;
      facilityOptions = const <AccessAdminLookupOption>[];
    });

    final Result<AppPage<FacilityProfile>> result = await ref
        .read(tenantFacilityRepositoryProvider)
        .listFacilities(
          tenantId: tenantId,
          request: const AppPageRequest(pageSize: 100),
        );
    if (!dialogOpen) {
      return;
    }

    setState(() {
      isLoadingFacilities = false;
      facilityLoadAttempted = true;
      facilityOptions = result.when(
        success: (AppPage<FacilityProfile> page) => page.items
            .map(
              (FacilityProfile facility) => AccessAdminLookupOption(
                id: facility.mutationId,
                label: facility.name,
              ),
            )
            .toList(growable: false),
        failure: (_) => const <AccessAdminLookupOption>[],
      );
    });
  }

  Future<void> reloadRoleOptions(StateSetter setState) async {
    final String? tenantId = selectedTenantId;
    if ((tenantId ?? '').isEmpty) {
      return;
    }
    final String requestedScope = scopeKey();
    setState(() {
      isLoadingRoles = true;
      roleLoadFailure = null;
    });

    final Result<AccessAdminLookups> result = await ref
        .read(accessAdminRepositoryProvider)
        .getReferenceData(
          tenantId: tenantId,
          facilityId: selectedFacilityId,
          include: const <String>['roles'],
          forceRefresh: true,
        );
    // A newer tenant or facility choice supersedes this response.
    if (!dialogOpen || requestedScope != scopeKey()) {
      return;
    }

    setState(() {
      isLoadingRoles = false;
      rolesLoadedForScope = requestedScope;
      result.when<void>(
        success: (AccessAdminLookups lookups) {
          roleOptions = lookups.roles
              .where((AccessAdminLookupOption role) => role.id.trim().isNotEmpty)
              .map(
                (AccessAdminLookupOption role) => AppRoleAssignmentOption(
                  id: role.id,
                  label: (role.displayName ?? '').trim().isNotEmpty
                      ? role.displayName!.trim()
                      : role.label,
                  description: role.meta,
                  permissionCount: role.permissionCount,
                ),
              )
              .toList(growable: false);
        },
        failure: (AppFailure failure) {
          roleOptions = const <AppRoleAssignmentOption>[];
          roleLoadFailure = failure;
        },
      );
    });
  }

  AppSelectField<String> facilityField(
    StateSetter setState, {
    required bool enabled,
  }) {
    return AppSelectField<String>.searchable(
      value: selectedFacilityId,
      enabled: enabled && facilityOptions.isNotEmpty,
      isLoading: isLoadingFacilities,
      labelText: l10n.tenantFacilityFacilitySelectLabel,
      helperText: facilityRequired ? null : l10n.accessAdminFacilityOptionalHint,
      errorText: serverErrorFor('facility_id'),
      isRequired: facilityRequired,
      allowClear: !facilityRequired,
      menuHeight: 320,
      options: facilityOptions
          .map(
            (AccessAdminLookupOption facility) => AppSelectOption<String>(
              value: facility.id,
              label: facility.label,
            ),
          )
          .toList(growable: false),
      onChanged: enabled
          ? (String? value) {
              setState(() {
                selectedFacilityId = value;
                editedFields.add('facility_id');
                resetRoleSelection();
              });
            }
          : null,
      validator: facilityRequired
          ? (String? value) =>
                (value ?? '').trim().isEmpty ? l10n.validationRequired : null
          : null,
    );
  }

  final bool? saved = await showAppWorkspaceMutationDialog(
    context: context,
    title: Text(
      isCreate ? l10n.accessAdminCreateUserAction : l10n.accessAdminEditUserAction,
    ),
    icon: Icon(
      isCreate ? Icons.person_add_alt_1_outlined : Icons.edit_outlined,
    ),
    submitLabel: l10n.commonSaveActionLabel,
    cancelLabel: l10n.commonCancelActionLabel,
    submitIcon: Icons.save_outlined,
    cancelIcon: Icons.close_outlined,
    maxWidth: 720,
    buildFields:
        (
          BuildContext context,
          GlobalKey<FormState> formKey,
          bool isSubmitting, [
          AppFailure? failure,
        ]) {
          return _UserMutationControllersScope(
            controllers: formControllers,
            child: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              if (!identical(failure, displayedFailure)) {
                displayedFailure = failure;
                editedFields.clear();
              }

              final bool tenantSelected = (selectedTenantId ?? '').isNotEmpty;
              final bool facilitySelected =
                  (selectedFacilityId ?? '').isNotEmpty;
              final bool scopeReady =
                  tenantSelected && (facilitySelected || !facilityRequired);
              final bool fieldsEnabled = !isSubmitting && scopeReady;
              final bool facilityEnabled =
                  !isSubmitting && tenantSelected && !isLoadingFacilities;
              final String? facilityDisabledReason = !tenantSelected
                  ? (showTenantPicker
                        ? l10n.accessAdminCreateUserSelectTenantFirstTooltip
                        : null)
                  : (isLoadingFacilities
                        ? l10n.accessAdminCreateUserLoadingFacilities
                        : null);
              final String? detailsDisabledReason = fieldsEnabled
                  ? null
                  : (isSubmitting
                        ? null
                        : l10n.accessAdminCreateUserSelectScopeTooltip);
              final List<String> statusValues =
                  state.data.lookups.userStatuses.isNotEmpty
                  ? state.data.lookups.userStatuses
                  : _fallbackUserStatuses;

              if (showTenantPicker &&
                  !tenantLoadAttempted &&
                  !isLoadingTenants &&
                  !scheduledInitialTenantLoad) {
                scheduledInitialTenantLoad = true;
                unawaited(reloadTenantOptions(setState));
              }

              if (showFacilityPicker &&
                  tenantSelected &&
                  !facilityLoadAttempted &&
                  !isLoadingFacilities &&
                  !scheduledInitialFacilityLoad) {
                scheduledInitialFacilityLoad = true;
                unawaited(reloadFacilityOptions(setState));
              }

              // Create assigns roles in the same request as the account, so
              // the picker follows the chosen scope.
              if (isCreate &&
                  scopeReady &&
                  !isLoadingRoles &&
                  rolesLoadedForScope != scopeKey()) {
                isLoadingRoles = true;
                unawaited(reloadRoleOptions(setState));
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (showTenantPicker || showFacilityPicker) ...<Widget>[
                    AppFormSection(
                      density: AppFormSectionDensity.compact,
                      framed: false,
                      title: l10n.accessAdminCreateRoleScopeSectionTitle,
                      children: <Widget>[
                        if (showTenantPicker &&
                            !isLoadingTenants &&
                            tenantOptions.isEmpty)
                          AppFormInformationBanner(
                            title: l10n.accessAdminTenantContextRequiredTitle,
                            message: l10n.tenantFacilitySelectTenantLoadError,
                            variant: AppFormInformationVariant.warning,
                            icon: Icons.apartment_outlined,
                            children: <Widget>[
                              AppButton.secondary(
                                label: l10n.commonRetryActionLabel,
                                leadingIcon: Icons.refresh,
                                enabled: !isSubmitting,
                                onPressed: () {
                                  setState(() {
                                    tenantLoadAttempted = false;
                                    scheduledInitialTenantLoad = false;
                                  });
                                  unawaited(reloadTenantOptions(setState));
                                },
                              ),
                            ],
                          )
                        else if (showTenantPicker)
                          AppResponsiveFieldRow.two(
                            gap: AppResponsiveFieldRowGap.form,
                            breakpoint: 560,
                            left: isLoadingTenants
                                ? _UserMutationLoadingIndicator(
                                    label: l10n
                                        .accessAdminCreateRoleLoadingTenants,
                                  )
                                : AppSelectField<String>.searchable(
                                    value: selectedTenantId,
                                    enabled: !isSubmitting,
                                    labelText:
                                        l10n.tenantFacilitySelectTenantLabel,
                                    errorText: serverErrorFor('tenant_id'),
                                    isRequired: true,
                                    menuHeight: 320,
                                    options: tenantOptions
                                        .map(
                                          (AccessAdminLookupOption tenant) =>
                                              AppSelectOption<String>(
                                                value: tenant.id,
                                                label: tenant.label,
                                              ),
                                        )
                                        .toList(growable: false),
                                    onChanged: (String? value) {
                                      setState(() {
                                        selectedTenantId = value;
                                        selectedFacilityId = null;
                                        facilityLoadAttempted = false;
                                        scheduledInitialFacilityLoad = false;
                                        editedFields.add('tenant_id');
                                        resetRoleSelection();
                                      });
                                    },
                                    validator: (String? value) =>
                                        (value ?? '').trim().isEmpty
                                        ? l10n.validationRequired
                                        : null,
                                  ),
                            right: _UserMutationReasonedField(
                              reason: facilityDisabledReason,
                              child: facilityField(
                                setState,
                                enabled: facilityEnabled,
                              ),
                            ),
                          )
                        else
                          _UserMutationReasonedField(
                            reason: facilityDisabledReason,
                            child: facilityField(
                              setState,
                              enabled: facilityEnabled,
                            ),
                          ),
                        if (facilityRequired &&
                            showFacilityPicker &&
                            tenantSelected &&
                            facilityLoadAttempted &&
                            !isLoadingFacilities &&
                            facilityOptions.isEmpty)
                          AppFormInformationBanner(
                            title: l10n.accessAdminCreateUserNoFacilitiesTitle,
                            message:
                                l10n.accessAdminCreateUserNoFacilitiesMessage,
                            variant: AppFormInformationVariant.warning,
                            icon: Icons.local_hospital_outlined,
                            children: <Widget>[
                              AppButton.secondary(
                                label: l10n.commonRetryActionLabel,
                                leadingIcon: Icons.refresh,
                                enabled: !isSubmitting,
                                onPressed: () {
                                  setState(() {
                                    facilityLoadAttempted = false;
                                    scheduledInitialFacilityLoad = false;
                                  });
                                  unawaited(reloadFacilityOptions(setState));
                                },
                              ),
                            ],
                          ),
                      ],
                    ),
                    SizedBox(height: Theme.of(context).spacing.md),
                  ],
                  AppFormSection(
                    density: AppFormSectionDensity.compact,
                    framed: false,
                    title: l10n.accessAdminCreateUserDetailsSectionTitle,
                    children: <Widget>[
                      _UserMutationReasonedField(
                        reason: detailsDisabledReason,
                        child: AppResponsiveFieldRow.two(
                          gap: AppResponsiveFieldRowGap.form,
                          breakpoint: 560,
                          left: AppTextField(
                            controller: firstNameController,
                            enabled: fieldsEnabled,
                            labelText: l10n.accessAdminFirstNameLabel,
                            isRequired: true,
                            textCapitalization: TextCapitalization.words,
                            errorText: serverErrorFor('first_name'),
                            onChanged: (_) =>
                                markEdited(setState, 'first_name'),
                            validator: AppValidators.compose<String>(
                              <FormFieldValidator<String>>[
                                AppValidators.requiredText(
                                  l10n.validationRequired,
                                ),
                                AppValidators.maxLength(
                                  UserAccountRules.nameMaxLength,
                                  l10n.validationMaxLengthMessage(
                                    UserAccountRules.nameMaxLength,
                                  ),
                                  trim: true,
                                ),
                              ],
                            ),
                          ),
                          right: AppTextField(
                            controller: lastNameController,
                            enabled: fieldsEnabled,
                            labelText: l10n.accessAdminLastNameLabel,
                            textCapitalization: TextCapitalization.words,
                            errorText: serverErrorFor('last_name'),
                            onChanged: (_) => markEdited(setState, 'last_name'),
                            validator: AppValidators.maxLength(
                              UserAccountRules.nameMaxLength,
                              l10n.validationMaxLengthMessage(
                                UserAccountRules.nameMaxLength,
                              ),
                              trim: true,
                            ),
                          ),
                        ),
                      ),
                      _UserMutationReasonedField(
                        reason: detailsDisabledReason,
                        child: AppResponsiveFieldRow.two(
                          gap: AppResponsiveFieldRowGap.form,
                          breakpoint: 560,
                          left: AppEmailField(
                            controller: emailController,
                            enabled: fieldsEnabled,
                            labelText: l10n.accessAdminEmailLabel,
                            isRequired: true,
                            requiredMessage: l10n.validationRequired,
                            invalidEmailMessage: l10n.authEmailInvalidMessage,
                            errorText: serverErrorFor('email'),
                            onChanged: (_) => markEdited(setState, 'email'),
                            // Same pattern and limit the API applies, so the
                            // form never accepts an address the API rejects.
                            validator: AppValidators.compose<String>(
                              <FormFieldValidator<String>>[
                                AppValidators.maxLength(
                                  UserAccountRules.emailMaxLength,
                                  l10n.validationMaxLengthMessage(
                                    UserAccountRules.emailMaxLength,
                                  ),
                                  trim: true,
                                ),
                                AppValidators.pattern(
                                  UserAccountRules.emailPattern,
                                  l10n.authEmailInvalidMessage,
                                ),
                              ],
                            ),
                          ),
                          right: AppPhoneField(
                            controller: phoneController,
                            enabled: fieldsEnabled,
                            labelText: l10n.accessAdminPhoneLabel,
                            countryLabelText: l10n.appPhoneCountryLabel,
                            countrySearchLabelText:
                                l10n.appPhoneCountrySearchLabel,
                            countryNoResultsText: l10n.appPhoneCountryNoResults,
                            numberLabelText: l10n.appPhoneNumberLabel,
                            numberHintText: l10n.appPhoneNumberHint,
                            invalidPhoneMessage: l10n.appPhoneInvalidMessage,
                            errorText: serverErrorFor('phone'),
                            onChanged: (_) => markEdited(setState, 'phone'),
                          ),
                        ),
                      ),
                      _UserMutationReasonedField(
                        reason: detailsDisabledReason,
                        child: AppResponsiveFieldRow.two(
                          gap: AppResponsiveFieldRowGap.form,
                          breakpoint: 560,
                          left: AppTextField(
                            controller: titleController,
                            enabled: fieldsEnabled,
                            labelText: l10n.accessAdminPositionLabel,
                            isRequired: true,
                            errorText: serverErrorFor('position_title'),
                            onChanged: (_) =>
                                markEdited(setState, 'position_title'),
                            validator: AppValidators.compose<String>(
                              <FormFieldValidator<String>>[
                                AppValidators.requiredText(
                                  l10n.validationRequired,
                                ),
                                AppValidators.maxLength(
                                  UserAccountRules.positionTitleMaxLength,
                                  l10n.validationMaxLengthMessage(
                                    UserAccountRules.positionTitleMaxLength,
                                  ),
                                  trim: true,
                                ),
                              ],
                            ),
                          ),
                          right: AppSelectField<String>(
                            labelText: l10n.accessAdminStatusLabel,
                            value: status,
                            enabled: fieldsEnabled,
                            allowClear: false,
                            errorText: serverErrorFor('status'),
                            options: statusValues
                                .map(
                                  (String value) => AppSelectOption<String>(
                                    value: value,
                                    label: statusLabel(value),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: fieldsEnabled
                                ? (String? value) {
                                    if (value != null) {
                                      setState(() {
                                        status = value;
                                        editedFields.add('status');
                                      });
                                    }
                                  }
                                : null,
                          ),
                        ),
                      ),
                      // Create chooses the first password. Edit may set a new
                      // one directly; blank keeps the current password. The API
                      // enforces the policy and ends every session either way.
                      if (isCreate || showNewPasswordField)
                        _UserMutationReasonedField(
                          reason: detailsDisabledReason,
                          child: AppTextField(
                            controller: passwordController,
                            enabled: fieldsEnabled,
                            labelText: isCreate
                                ? l10n.accessAdminPasswordLabel
                                : l10n.accessAdminNewPasswordLabel,
                            isRequired: isCreate,
                            obscureText: true,
                            enableObscureTextToggle: true,
                            showObscuredTextLabel: l10n.authShowPasswordLabel,
                            hideObscuredTextLabel: l10n.authHidePasswordLabel,
                            autocorrect: false,
                            enableSuggestions: false,
                            autofillHints: const <String>[
                              AutofillHints.newPassword,
                            ],
                            helperText: isCreate
                                ? l10n.accessAdminPasswordPolicyHint
                                : l10n.accessAdminNewPasswordHint,
                            errorText: serverErrorFor('password'),
                            onChanged: (_) => markEdited(setState, 'password'),
                            validator: (String? value) {
                              if (!isCreate && (value ?? '').trim().isEmpty) {
                                return null;
                              }
                              return AppPasswordPolicy.validator(
                                requiredMessage: l10n.validationRequired,
                                messageFor: passwordRuleMessage,
                              )(value);
                            },
                          ),
                        ),
                    ],
                  ),
                  if (isCreate) ...<Widget>[
                    SizedBox(height: Theme.of(context).spacing.md),
                    AppFormSection(
                      density: AppFormSectionDensity.compact,
                      framed: false,
                      title: l10n.accessAdminCreateUserRolesSectionTitle,
                      children: <Widget>[
                        if (!scopeReady)
                          Text(
                            l10n.accessAdminCreateUserRolesSelectScopeFirst,
                            style: Theme.of(context).textTheme.bodySmall,
                          )
                        else if (isLoadingRoles)
                          _UserMutationLoadingIndicator(
                            label: l10n.accessAdminCreateUserLoadingRoles,
                          )
                        else if (roleLoadFailure != null)
                          AppFormInformationBanner(
                            title: l10n.accessAdminCreateUserRolesLoadErrorTitle,
                            message: l10n.failureMessage(roleLoadFailure!),
                            variant: AppFormInformationVariant.warning,
                            icon: Icons.badge_outlined,
                            children: <Widget>[
                              AppButton.secondary(
                                label: l10n.commonRetryActionLabel,
                                leadingIcon: Icons.refresh,
                                enabled: !isSubmitting,
                                onPressed: () {
                                  setState(() => rolesLoadedForScope = null);
                                },
                              ),
                            ],
                          )
                        else ...<Widget>[
                          AppRoleAssignmentPicker(
                            roles: roleOptions,
                            selectedRoleIds: selectedRoleIds,
                            emptyWarning: l10n
                                .accessAdminUserAccessNoAssignableRolesMessage,
                            onSelectionChanged: (Set<String> next) {
                              setState(() {
                                selectedRoleIds = <String>{...next};
                                editedFields.add('role_ids');
                              });
                            },
                          ),
                          AppFieldErrorText(
                            errorText: serverErrorFor('role_ids'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              );
            },
            ),
          );
        },
    onSubmit: () {
      final String? resolvedTenantId = selectedTenantId;
      final String? resolvedFacilityId =
          (selectedFacilityId ?? '').trim().isEmpty ? null : selectedFacilityId;
      if ((resolvedTenantId ?? '').isEmpty ||
          (facilityRequired && resolvedFacilityId == null)) {
        return Future<AppFailure?>.value(AppFailure.validation());
      }
      if (isCreate && selectedRoleIds.length > UserAccountRules.maxRoles) {
        return Future<AppFailure?>.value(
          AppFailure.validation(
            fieldMessages: <String, String>{
              'role_ids': l10n.validationMaxItemsMessage(
                UserAccountRules.maxRoles,
              ),
            },
          ),
        );
      }

      String? labelFor(
        List<AccessAdminLookupOption> options,
        String? id, {
        List<AccessAdminLookupOption> workspaceOptions =
            const <AccessAdminLookupOption>[],
        String? fallback,
      }) {
        if ((id ?? '').isEmpty) {
          return fallback;
        }
        for (final AccessAdminLookupOption option in <AccessAdminLookupOption>[
          ...options,
          ...workspaceOptions,
        ]) {
          if (option.id == id) {
            final String label = option.label.trim();
            if (label.isNotEmpty) {
              return label;
            }
          }
        }
        return fallback;
      }

      final List<String> roleIds = isCreate
          ? selectedRoleIds.toList(growable: false)
          : const <String>[];
      // Create captures the account, its scope and its roles together; direct
      // permissions stay in User Details.
      return onSubmit(
        AccessAdminUserDraft(
          tenantId: resolvedTenantId!,
          facilityId: resolvedFacilityId,
          tenantName: labelFor(
            tenantOptions,
            resolvedTenantId,
            workspaceOptions: state.data.lookups.tenants,
            fallback: initialUser?.tenantName,
          ),
          facilityName: labelFor(
            facilityOptions,
            resolvedFacilityId,
            workspaceOptions: state.data.lookups.facilities,
            fallback: initialUser?.facilityName,
          ),
          firstName: firstNameController.text.trim(),
          lastName: lastNameController.text.trim().isEmpty
              ? null
              : lastNameController.text.trim(),
          email: emailController.text.trim(),
          phone: phoneController.text.trim().isEmpty
              ? null
              : phoneController.text.trim(),
          positionTitle: titleController.text.trim(),
          password: isCreate
              ? passwordController.text.trim()
              : (showNewPasswordField &&
                        passwordController.text.trim().isNotEmpty
                    ? passwordController.text.trim()
                    : null),
          status: status,
          roleIds: roleIds,
        ),
        roleIds,
      );
    },
  );
  dialogOpen = false;
  // Controllers are disposed by _UserMutationControllersScope once the dialog
  // route is gone; the closing dialog still rebuilds during its exit transition.
  return saved;
}

/// Owns the form's text controllers for as long as the dialog content exists.
class _UserMutationControllersScope extends StatefulWidget {
  const _UserMutationControllersScope({
    required this.controllers,
    required this.child,
  });

  final List<TextEditingController> controllers;
  final Widget child;

  @override
  State<_UserMutationControllersScope> createState() =>
      _UserMutationControllersScopeState();
}

class _UserMutationControllersScopeState
    extends State<_UserMutationControllersScope> {
  @override
  void dispose() {
    for (final TextEditingController controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _UserMutationReasonedField extends StatelessWidget {
  const _UserMutationReasonedField({
    required this.child,
    this.reason,
  });

  final Widget child;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final String? message = reason?.trim();
    if (message == null || message.isEmpty) {
      return child;
    }

    // Hover (desktop) and long-press (touch) surface the disable reason.
    return Tooltip(
      message: message,
      waitDuration: const Duration(milliseconds: 300),
      child: child,
    );
  }
}

class _UserMutationLoadingIndicator extends StatelessWidget {
  const _UserMutationLoadingIndicator({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: theme.spacing.lg),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: theme.colorScheme.primary,
              ),
            ),
            SizedBox(height: theme.spacing.sm),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<List<AccessAdminLookupOption>> _loadTenantOptions(
  WidgetRef ref,
  AccessAdminWorkspaceState state,
  bool preferTenantFacilityApi,
) async {
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
