import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/responsive/app_breakpoints.dart';
import 'package:hosspi_hms/features/tenant_facility/data/repositories/tenant_facility_repository_impl.dart';
import 'package:hosspi_hms/features/tenant_facility/domain/entities/tenant_facility_setup.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/controllers/tenant_facility_setup_controller.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/widgets/tenant_facility_setup_helpers.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/components/components.dart';
import 'package:hosspi_hms/shared/data/data.dart';
import 'package:hosspi_hms/shared/layout/layout.dart';

class TenantFacilitySetupWizard extends StatefulWidget {
  const TenantFacilitySetupWizard({
    required this.snapshot,
    required this.canManageTenant,
    required this.canManageFacility,
    required this.canCreateTenant,
    required this.onOpenStep,
    this.onManageTenants,
    this.onManageFacilities,
    this.onSelectFacility,
    this.onOpenCatalog,
    super.key,
  });

  final FacilitySetupSnapshot snapshot;
  final bool canManageTenant;
  final bool canManageFacility;
  final bool canCreateTenant;
  final ValueChanged<TenantFacilitySetupWizardStep> onOpenStep;
  final VoidCallback? onManageTenants;
  final VoidCallback? onManageFacilities;
  final ValueChanged<String>? onSelectFacility;
  final VoidCallback? onOpenCatalog;

  @override
  State<TenantFacilitySetupWizard> createState() =>
      _TenantFacilitySetupWizardState();
}

class _TenantFacilitySetupWizardState extends State<TenantFacilitySetupWizard> {
  TenantFacilitySetupWizardStep? _selectedStep;

  List<TenantFacilitySetupWizardStep> get _steps {
    return tenantFacilityVisibleWizardSteps(
      canManageTenant: widget.canManageTenant,
      canManageFacility: widget.canManageFacility,
    );
  }

  TenantFacilitySetupWizardStep get _currentStep {
    final List<TenantFacilitySetupWizardStep> steps = _steps;
    if (steps.isEmpty) {
      return TenantFacilitySetupWizardStep.facility;
    }
    final TenantFacilitySetupWizardStep? selected = _selectedStep;
    if (selected != null &&
        steps.contains(selected) &&
        tenantFacilityWizardStepReachable(widget.snapshot, steps, selected)) {
      return selected;
    }
    return tenantFacilityNextIncompleteWizardStep(
          widget.snapshot,
          steps: steps,
        ) ??
        steps.last;
  }

  @override
  void didUpdateWidget(covariant TenantFacilitySetupWizard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final TenantFacilitySetupWizardStep? selected = _selectedStep;
    if (selected == null) {
      return;
    }
    if (!_steps.contains(selected) ||
        !tenantFacilityWizardStepReachable(widget.snapshot, _steps, selected)) {
      _selectedStep = null;
    }
  }

  void _selectStep(TenantFacilitySetupWizardStep step) {
    if (!tenantFacilityWizardStepReachable(widget.snapshot, _steps, step)) {
      return;
    }
    setState(() => _selectedStep = step);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final List<TenantFacilitySetupWizardStep> steps = _steps;
    if (steps.isEmpty) {
      return AppCollapsibleSection(
        title: l10n.tenantFacilityWizardTitle,
        description: l10n.tenantFacilityPermissionRequired,
        child: const SizedBox.shrink(),
      );
    }

    final TenantFacilitySetupWizardStep current = _currentStep;
    final int currentIndex = steps.indexOf(current).clamp(0, steps.length - 1);
    final bool currentOptional = tenantFacilityWizardStepOptional(current);
    final bool currentCompleted = tenantFacilityWizardStepCompleted(
      widget.snapshot,
      current,
    );
    final bool hasRecords = tenantFacilityWizardStepHasRecords(
      widget.snapshot,
      current,
    );
    final TenantFacilitySetupWizardStep? nextStep =
        currentIndex + 1 < steps.length ? steps[currentIndex + 1] : null;
    // Enabled only when the current step does not block progress (required
    // steps must be fully configured; optional steps never block).
    final bool canGoNext =
        nextStep != null &&
        !tenantFacilityWizardStepBlocksProgress(widget.snapshot, current);
    final String? navigationLabel = nextStep == null
        ? null
        : tenantFacilityWizardContinueToStepLabel(l10n, nextStep);
    final TenantFacilitySetupWizardStep? navigateTarget = canGoNext
        ? nextStep
        : null;
    final VoidCallback? navigationAction = navigateTarget == null
        ? null
        : () => _selectStep(navigateTarget);

    return AppCollapsibleSection(
      title: l10n.tenantFacilityWizardTitle,
      description: l10n.tenantFacilityWizardBody,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(theme.radius.md),
              border: theme.borders.all(),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                theme.spacing.md,
                theme.spacing.md,
                theme.spacing.md,
                theme.spacing.sm,
              ),
              child: AppWizardStepper(
                steps: <AppWizardStepItem>[
                  for (final TenantFacilitySetupWizardStep step in steps)
                    AppWizardStepItem(
                      id: step,
                      label: tenantFacilityWizardStepLabel(l10n, step),
                      optional: tenantFacilityWizardStepOptional(step),
                      completed: tenantFacilityWizardStepCompleted(
                        widget.snapshot,
                        step,
                      ),
                      enabled: tenantFacilityWizardStepReachable(
                        widget.snapshot,
                        steps,
                        step,
                      ),
                    ),
                ],
                currentIndex: currentIndex,
                showCurrentTitle: false,
                progressCaption: tenantFacilityWizardProgressCaption(
                  currentIndex: currentIndex,
                  totalSteps: steps.length,
                  stepLabel: tenantFacilityWizardStepLabel(l10n, current),
                  optional: currentOptional,
                ),
                onStepSelected: (int index) => _selectStep(steps[index]),
                onDisabledStepSelected: (int index) {
                  final TenantFacilitySetupWizardStep locked = steps[index];
                  final String hint =
                      tenantFacilityWizardLockedStepBlockersMessage(
                        l10n,
                        widget.snapshot,
                        locked,
                        steps: steps,
                      );
                  final TenantFacilitySetupWizardStep? fixStep =
                      tenantFacilityWizardFirstBlockingStep(
                        l10n,
                        widget.snapshot,
                        locked,
                        steps: steps,
                      );
                  if (fixStep != null &&
                      tenantFacilityWizardStepReachable(
                        widget.snapshot,
                        steps,
                        fixStep,
                      )) {
                    _selectStep(fixStep);
                  }
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text(hint)));
                },
              ),
            ),
          ),
          SizedBox(height: theme.spacing.lg),
          _SetupStepPanel(
            step: current,
            snapshot: widget.snapshot,
            steps: steps,
            optional: currentOptional,
            completed: currentCompleted,
            hasRecords: hasRecords,
            canManageTenant: widget.canManageTenant,
            canCreateTenant: widget.canCreateTenant,
            canManageFacility: widget.canManageFacility,
            onOpenStep: () => widget.onOpenStep(current),
            onOpenFixStep: (TenantFacilitySetupWizardStep fixStep) {
              if (fixStep == current) {
                widget.onOpenStep(current);
                return;
              }
              if (tenantFacilityWizardStepReachable(
                widget.snapshot,
                steps,
                fixStep,
              )) {
                _selectStep(fixStep);
              }
              widget.onOpenStep(fixStep);
            },
            onManageTenants: widget.onManageTenants,
            onManageFacilities: widget.onManageFacilities,
            onSelectFacility: widget.onSelectFacility,
            onOpenCatalog: widget.onOpenCatalog,
            navigationLabel: navigationLabel,
            navigationEnabled: canGoNext,
            onNavigate: navigationAction,
          ),
        ],
      ),
    );
  }
}

class _SetupStepPanel extends StatelessWidget {
  const _SetupStepPanel({
    required this.step,
    required this.snapshot,
    required this.steps,
    required this.optional,
    required this.completed,
    required this.hasRecords,
    required this.canManageTenant,
    required this.canCreateTenant,
    required this.canManageFacility,
    required this.onOpenStep,
    required this.onOpenFixStep,
    this.onManageTenants,
    this.onManageFacilities,
    this.onSelectFacility,
    this.onOpenCatalog,
    this.navigationLabel,
    this.navigationEnabled = false,
    this.onNavigate,
  });

  final TenantFacilitySetupWizardStep step;
  final FacilitySetupSnapshot snapshot;
  final List<TenantFacilitySetupWizardStep> steps;
  final bool optional;
  final bool completed;
  final bool hasRecords;
  final bool canManageTenant;
  final bool canCreateTenant;
  final bool canManageFacility;
  final VoidCallback onOpenStep;
  final ValueChanged<TenantFacilitySetupWizardStep> onOpenFixStep;
  final VoidCallback? onManageTenants;
  final VoidCallback? onManageFacilities;
  final ValueChanged<String>? onSelectFacility;
  final VoidCallback? onOpenCatalog;
  final String? navigationLabel;
  final bool navigationEnabled;
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final String title = tenantFacilityWizardStepLabel(l10n, step);
    final bool wide =
        AppBreakpoints.of(context).index >= AppBreakpoint.md.index;

    final List<Widget> actions = <Widget>[
      AppButton.primary(
        label: tenantFacilityWizardPrimaryActionLabel(
          l10n,
          step: step,
          snapshot: snapshot,
          canCreateTenant: canCreateTenant,
        ),
        leadingIcon: tenantFacilityWizardPrimaryActionIcon(
          step: step,
          snapshot: snapshot,
        ),
        onPressed: onOpenStep,
      ),
      if (step == TenantFacilitySetupWizardStep.tenant &&
          canManageTenant &&
          onManageTenants != null)
        AppButton.secondary(
          label: l10n.tenantFacilityManageTenantsTitle,
          leadingIcon: Icons.corporate_fare_outlined,
          onPressed: onManageTenants,
        ),
      if (step == TenantFacilitySetupWizardStep.facility &&
          canManageFacility &&
          onManageFacilities != null)
        AppButton.secondary(
          label: l10n.tenantFacilityManageFacilitiesTitle,
          leadingIcon: Icons.domain_outlined,
          onPressed: onManageFacilities,
        ),
      if (step == TenantFacilitySetupWizardStep.facility &&
          snapshot.facility?.id != null &&
          onOpenCatalog != null)
        AppButton.tertiary(
          label: l10n.tenantFacilityCatalogShortAction,
          leadingIcon: Icons.medical_information_outlined,
          onPressed: onOpenCatalog,
        ),
      if (navigationLabel != null)
        AppButton.secondary(
          label: navigationLabel!,
          leadingIcon: Icons.arrow_forward,
          enabled: navigationEnabled,
          tooltip: navigationEnabled
              ? null
              : tenantFacilityWizardStepPendingBannerMessage(
                  l10n,
                  snapshot: snapshot,
                  step: step,
                  nextActionLabel: navigationLabel,
                  steps: steps,
                ),
          onPressed: navigationEnabled ? onNavigate : null,
        ),
    ];

    final Widget actionRow = Align(
      alignment: Alignment.centerRight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int index = 0; index < actions.length; index += 1) ...<Widget>[
              if (index > 0) SizedBox(width: theme.spacing.sm),
              actions[index],
            ],
          ],
        ),
      ),
    );

    final List<TenantFacilityWizardStepRequirement> blockers =
        tenantFacilityWizardBlockersForStep(l10n, snapshot, step, steps: steps);
    final List<TenantFacilityWizardStepRequirement> outstanding = blockers
        .where((TenantFacilityWizardStepRequirement item) => !item.satisfied)
        .toList(growable: false);
    final String? pendingIntro = outstanding.isEmpty
        ? null
        : tenantFacilityWizardStepPendingIntro(
            l10n,
            snapshot: snapshot,
            step: step,
            nextActionLabel: navigationLabel,
            steps: steps,
          );
    final bool hasPrerequisiteBlockers = outstanding.any(
      (TenantFacilityWizardStepRequirement item) => item.isPrerequisite,
    );
    final TenantFacilityWizardStepRequirement? primaryOutstanding =
        outstanding.isEmpty ? null : outstanding.first;

    final Widget badgeRow = Wrap(
      spacing: theme.spacing.sm,
      runSpacing: theme.spacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        if (optional)
          _StepBadge(label: 'Optional', tone: colorScheme.tertiary),
        _StepBadge(
          label: completed
              ? l10n.tenantFacilityStatusActive
              : l10n.nursingChecklistPendingStatus,
          tone: completed
              ? theme.statusColors.success
              : colorScheme.onSurfaceVariant,
        ),
      ],
    );

    return AppCollapsibleSection(
      titleIcon: tenantFacilityWizardStepIcon(step),
      title: title,
      subtitle: tenantFacilityWizardStepSummary(l10n, snapshot, step),
      collapsible: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (wide)
            Row(
              children: <Widget>[
                Expanded(child: badgeRow),
                SizedBox(width: theme.spacing.md),
                Flexible(child: actionRow),
              ],
            )
          else ...<Widget>[
            badgeRow,
            SizedBox(height: theme.spacing.md),
            actionRow,
          ],
          if (pendingIntro != null && blockers.isNotEmpty) ...<Widget>[
            SizedBox(height: theme.spacing.md),
            AppFormInformationBanner(
              title: hasPrerequisiteBlockers
                  ? l10n.tenantFacilityWizardBlockersTitle
                  : l10n.tenantFacilityWizardPendingTitle,
              message: pendingIntro,
              variant: optional && !hasPrerequisiteBlockers
                  ? AppFormInformationVariant.info
                  : AppFormInformationVariant.warning,
              icon: optional && !hasPrerequisiteBlockers
                  ? Icons.info_outline
                  : Icons.playlist_add_check_circle_outlined,
              children: <Widget>[
                _SetupStepRequirementsChecklist(
                  requirements: blockers,
                  optional: optional && !hasPrerequisiteBlockers,
                  onFixRequirement:
                      (TenantFacilityWizardStepRequirement item) {
                        onOpenFixStep(item.fixStep);
                      },
                ),
                if (primaryOutstanding != null)
                  AppButton.secondary(
                    label: tenantFacilityWizardPrimaryActionLabel(
                      l10n,
                      step: primaryOutstanding.fixStep,
                      snapshot: snapshot,
                      canCreateTenant: canCreateTenant,
                    ),
                    leadingIcon: tenantFacilityWizardPrimaryActionIcon(
                      step: primaryOutstanding.fixStep,
                      snapshot: snapshot,
                    ),
                    onPressed: () =>
                        onOpenFixStep(primaryOutstanding.fixStep),
                  ),
              ],
            ),
          ],
          if (step == TenantFacilitySetupWizardStep.tenant &&
              canCreateTenant) ...<Widget>[
            SizedBox(height: theme.spacing.md),
            _SetupTenantContextPicker(selectedTenantId: snapshot.tenant?.id),
          ],
          SizedBox(height: theme.spacing.lg),
          _SetupStepRecordSelector(
            step: step,
            snapshot: snapshot,
            onSelectFacility: onSelectFacility,
          ),
          if (!canManageTenant &&
              step == TenantFacilitySetupWizardStep.tenant) ...<Widget>[
            SizedBox(height: theme.spacing.md),
            AppFormInformationBanner(
              title: l10n.tenantFacilityPermissionsTitle,
              message: l10n.tenantFacilityPermissionRequired,
            ),
          ],
        ],
      ),
    );
  }
}

class _SetupStepRequirementsChecklist extends StatelessWidget {
  const _SetupStepRequirementsChecklist({
    required this.requirements,
    required this.optional,
    this.onFixRequirement,
  });

  final List<TenantFacilityWizardStepRequirement> requirements;
  final bool optional;
  final ValueChanged<TenantFacilityWizardStepRequirement>? onFixRequirement;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final Color pendingTone = optional
        ? colorScheme.tertiary
        : theme.statusColors.warning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final TenantFacilityWizardStepRequirement item in requirements)
          Padding(
            padding: EdgeInsets.only(top: theme.spacing.xs),
            child: Semantics(
              button: !item.satisfied && onFixRequirement != null,
              label: item.satisfied
                  ? '${l10n.tenantFacilityWizardRequirementDoneLabel}: ${item.label}'
                  : '${l10n.tenantFacilityWizardRequirementPendingLabel}: ${item.label}',
              child: InkWell(
                onTap: item.satisfied || onFixRequirement == null
                    ? null
                    : () => onFixRequirement!(item),
                borderRadius: BorderRadius.circular(theme.radius.sm),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: theme.spacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        item.satisfied
                            ? Icons.check_circle_outline
                            : Icons.radio_button_unchecked,
                        size: theme.appTokens.listIconSize,
                        color: item.satisfied
                            ? theme.statusColors.success
                            : pendingTone,
                      ),
                      SizedBox(width: theme.spacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              item.label,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: item.satisfied
                                    ? colorScheme.onSurfaceVariant
                                    : colorScheme.onSurface,
                                fontWeight: item.satisfied
                                    ? AppFontWeight.regular
                                    : AppFontWeight.emphasis,
                                decoration: item.satisfied
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            if (!item.satisfied) ...<Widget>[
                              const SizedBox(height: 2),
                              Text(
                                l10n.tenantFacilityWizardFixInStep(
                                  tenantFacilityWizardStepLabel(
                                    l10n,
                                    item.fixStep,
                                  ),
                                ),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: pendingTone,
                                  fontWeight: AppFontWeight.emphasis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (!item.satisfied && onFixRequirement != null)
                        Icon(
                          Icons.chevron_right,
                          size: theme.appTokens.listIconSize,
                          color: pendingTone,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SetupStepRecordSelector extends StatefulWidget {
  const _SetupStepRecordSelector({
    required this.step,
    required this.snapshot,
    this.onSelectFacility,
  });

  final TenantFacilitySetupWizardStep step;
  final FacilitySetupSnapshot snapshot;
  final ValueChanged<String>? onSelectFacility;

  @override
  State<_SetupStepRecordSelector> createState() =>
      _SetupStepRecordSelectorState();
}

class _SetupStepRecordSelectorState extends State<_SetupStepRecordSelector> {
  String? _localSelectedId;

  @override
  void didUpdateWidget(covariant _SetupStepRecordSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.step != widget.step ||
        oldWidget.snapshot != widget.snapshot) {
      _localSelectedId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final FacilitySetupSnapshot snapshot = widget.snapshot;
    final TenantFacilitySetupWizardStep step = widget.step;

    return switch (step) {
      TenantFacilitySetupWizardStep.tenant => _buildSelector(
        context,
        label: l10n.tenantFacilityWizardStepTenant,
        emptyMessage: tenantFacilityWizardStepEmptyMessage(l10n, step),
        options: snapshot.tenant == null
            ? const <AppSelectOption<String>>[]
            : <AppSelectOption<String>>[
                AppSelectOption<String>(
                  value: snapshot.tenant!.id,
                  label:
                      '${snapshot.tenant!.name} · ${tenantFacilityActiveStatusLabel(l10n, snapshot.tenant!.isActive)}',
                  searchText: snapshot.tenant!.name,
                ),
              ],
        value: snapshot.tenant?.id,
        onChanged: null,
      ),
      TenantFacilitySetupWizardStep.facility => _buildSelector(
        context,
        label: l10n.tenantFacilityFacilitySelectLabel,
        emptyMessage: tenantFacilityWizardStepEmptyMessage(l10n, step),
        options: <AppSelectOption<String>>[
          for (final FacilityProfile facility in snapshot.facilities)
            AppSelectOption<String>(
              value: facility.id,
              label:
                  '${facility.name} · ${tenantFacilityFacilityTypeLabel(l10n, facility.type)}',
              searchText: facility.name,
            ),
        ],
        value:
            snapshot.facility?.id ??
            (snapshot.facilities.length == 1
                ? snapshot.facilities.first.id
                : null),
        onChanged: widget.onSelectFacility == null
            ? null
            : (String? value) {
                if (value == null || value == snapshot.facility?.id) {
                  return;
                }
                widget.onSelectFacility!(value);
              },
      ),
      TenantFacilitySetupWizardStep.departments => _buildListSelector(
        context,
        label: l10n.tenantFacilityWizardStepDepartments,
        emptyMessage: l10n.tenantFacilityNoDepartments,
        items: snapshot.departments,
        idOf: (DepartmentProfile item) => item.id,
        labelOf: (DepartmentProfile item) =>
            '${item.name} · ${tenantFacilityDepartmentTypeLabel(l10n, item.type)}',
        searchOf: (DepartmentProfile item) => item.name,
      ),
      TenantFacilitySetupWizardStep.units => _buildListSelector(
        context,
        label: l10n.tenantFacilityWizardStepUnits,
        emptyMessage: l10n.tenantFacilityNoUnits,
        items: snapshot.units,
        idOf: (UnitProfile item) => item.id,
        labelOf: (UnitProfile item) =>
            '${item.name} · ${tenantFacilityActiveStatusLabel(l10n, item.isActive)}',
        searchOf: (UnitProfile item) => item.name,
      ),
      TenantFacilitySetupWizardStep.wards => _buildListSelector(
        context,
        label: l10n.tenantFacilityWizardStepWards,
        emptyMessage: l10n.tenantFacilityNoWards,
        items: snapshot.wards,
        idOf: (WardProfile item) => item.id,
        labelOf: (WardProfile item) =>
            '${item.name} · ${tenantFacilityWardTypeLabel(l10n, item.type)}',
        searchOf: (WardProfile item) => item.name,
      ),
      TenantFacilitySetupWizardStep.rooms => _buildListSelector(
        context,
        label: l10n.tenantFacilityWizardStepRooms,
        emptyMessage: l10n.tenantFacilityNoRooms,
        items: snapshot.rooms,
        idOf: (RoomProfile item) => item.id,
        labelOf: (RoomProfile item) =>
            '${item.name} · ${item.floor?.trim().isNotEmpty == true ? item.floor! : '—'}',
        searchOf: (RoomProfile item) => item.name,
      ),
      TenantFacilitySetupWizardStep.beds => _buildListSelector(
        context,
        label: l10n.tenantFacilityWizardStepBeds,
        emptyMessage: l10n.tenantFacilityNoBeds,
        items: snapshot.beds,
        idOf: (BedProfile item) => item.id,
        labelOf: (BedProfile item) =>
            '${item.label} · ${tenantFacilityBedStatusLabel(l10n, item.status)}',
        searchOf: (BedProfile item) => item.label,
      ),
    };
  }

  Widget _buildListSelector<T>(
    BuildContext context, {
    required String label,
    required String emptyMessage,
    required List<T> items,
    required String Function(T item) idOf,
    required String Function(T item) labelOf,
    required String Function(T item) searchOf,
  }) {
    final String? fallbackId = items.isEmpty ? null : idOf(items.first);
    final String? selectedId =
        _localSelectedId != null &&
            items.any((T item) => idOf(item) == _localSelectedId)
        ? _localSelectedId
        : fallbackId;

    return _buildSelector(
      context,
      label: label,
      emptyMessage: emptyMessage,
      options: <AppSelectOption<String>>[
        for (final T item in items)
          AppSelectOption<String>(
            value: idOf(item),
            label: labelOf(item),
            searchText: searchOf(item),
          ),
      ],
      value: selectedId,
      onChanged: items.isEmpty
          ? null
          : (String? value) {
              if (value == null) {
                return;
              }
              setState(() => _localSelectedId = value);
            },
    );
  }

  Widget _buildSelector(
    BuildContext context, {
    required String label,
    required String emptyMessage,
    required List<AppSelectOption<String>> options,
    required String? value,
    required ValueChanged<String?>? onChanged,
  }) {
    if (options.isEmpty) {
      return _SetupEmptyRecords(message: emptyMessage);
    }

    return AppSelectField<String>.searchable(
      labelText: label,
      value: value,
      allowClear: false,
      menuHeight: 320,
      options: options,
      onChanged: onChanged ?? (_) {},
      enabled: onChanged != null,
    );
  }
}

class _SetupEmptyRecords extends StatelessWidget {
  const _SetupEmptyRecords({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(theme.radius.md),
        border: theme.borders.all(),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: theme.spacing.md,
          vertical: theme.spacing.lg,
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.inbox_outlined, color: colorScheme.onSurfaceVariant),
            SizedBox(width: theme.spacing.sm),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupTenantContextPicker extends ConsumerStatefulWidget {
  const _SetupTenantContextPicker({this.selectedTenantId});

  final String? selectedTenantId;

  @override
  ConsumerState<_SetupTenantContextPicker> createState() =>
      _SetupTenantContextPickerState();
}

class _SetupTenantContextPickerState
    extends ConsumerState<_SetupTenantContextPicker> {
  List<TenantProfile> _tenants = const <TenantProfile>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final Result<AppPage<TenantProfile>> result = await ref
        .read(tenantFacilityRepositoryProvider)
        .listTenants(request: const AppPageRequest(pageSize: 100));
    if (!mounted) {
      return;
    }
    result.when(
      success: (AppPage<TenantProfile> page) {
        setState(() {
          _tenants = page.items
              .where((TenantProfile tenant) => !tenant.isDeleted)
              .toList(growable: false);
          _loading = false;
        });
      },
      failure: (_) {
        setState(() => _loading = false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    if (_loading || _tenants.length < 2) {
      return const SizedBox.shrink();
    }

    return AppSelectField<String>(
      labelText: l10n.tenantFacilityTenantSectionTitle,
      value: widget.selectedTenantId,
      allowClear: false,
      options: <AppSelectOption<String>>[
        for (final TenantProfile tenant in _tenants)
          AppSelectOption<String>(value: tenant.id, label: tenant.name),
      ],
      onChanged: (String? value) {
        if (value == null) {
          return;
        }
        unawaited(
          ref
              .read(tenantFacilitySetupControllerProvider.notifier)
              .selectTenant(value),
        );
      },
    );
  }
}

class _StepBadge extends StatelessWidget {
  const _StepBadge({required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: theme.spacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: tone,
          fontWeight: AppFontWeight.emphasis,
        ),
      ),
    );
  }
}

class TenantFacilityPermissionStrip extends StatelessWidget {
  const TenantFacilityPermissionStrip({
    required this.canManageTenant,
    required this.canManageFacility,
    super.key,
  });

  final bool canManageTenant;
  final bool canManageFacility;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(theme.radius.md),
        border: theme.borders.all(),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: theme.spacing.md,
          vertical: theme.spacing.sm,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.verified_user_outlined,
              size: 18,
              color: colorScheme.primary,
            ),
            SizedBox(width: theme.spacing.sm),
            Expanded(
              child: Wrap(
                spacing: theme.spacing.md,
                runSpacing: theme.spacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text(
                    l10n.tenantFacilityPermissionsTitle,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: AppFontWeight.emphasis,
                    ),
                  ),
                  _PermissionChip(
                    label: l10n.tenantFacilityTenantAdminPermission,
                    allowed: canManageTenant,
                  ),
                  _PermissionChip(
                    label: l10n.tenantFacilityFacilityAdminPermission,
                    allowed: canManageFacility,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionChip extends StatelessWidget {
  const _PermissionChip({required this.label, required this.allowed});

  final String label;
  final bool allowed;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final Color tone = allowed
        ? theme.statusColors.success
        : theme.colorScheme.error;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          allowed ? Icons.lock_open_outlined : Icons.lock_outline,
          size: 16,
          color: tone,
        ),
        SizedBox(width: theme.spacing.xs),
        Text(
          '$label · ${allowed ? l10n.tenantFacilityPermissionAllowed : l10n.tenantFacilityPermissionDenied}',
          style: theme.textTheme.labelMedium?.copyWith(
            color: tone,
            fontWeight: AppFontWeight.emphasis,
          ),
        ),
      ],
    );
  }
}
