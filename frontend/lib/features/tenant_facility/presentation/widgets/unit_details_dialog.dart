import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hosspi_hms/app/theme/app_theme_extensions.dart';
import 'package:hosspi_hms/core/errors/app_failure.dart';
import 'package:hosspi_hms/core/errors/result.dart';
import 'package:hosspi_hms/core/permissions/permission_providers.dart';
import 'package:hosspi_hms/core/utils/app_formatters.dart';
import 'package:hosspi_hms/features/tenant_facility/domain/entities/tenant_facility_setup.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/controllers/tenant_facility_setup_controller.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/pages/tenant_facility_setup_page.dart';
import 'package:hosspi_hms/features/tenant_facility/presentation/widgets/tenant_facility_setup_helpers.dart';
import 'package:hosspi_hms/l10n/app_localizations.dart';
import 'package:hosspi_hms/l10n/app_localizations_x.dart';
import 'package:hosspi_hms/shared/actions/app_action_dialogs.dart';
import 'package:hosspi_hms/shared/components/components.dart';
import 'package:hosspi_hms/shared/layout/layout.dart';

Future<bool?> showUnitDetailsDialog(
  BuildContext context, {
  required UnitProfile unit,
  String? tenantName,
  String? facilityName,
  String? departmentName,
  FacilitySetupSnapshot? snapshot,
}) {
  return showAppDialog<bool>(
    context: context,
    builder: (_) => _UnitDetailsDialog(
      unit: unit,
      tenantName: tenantName,
      facilityName: facilityName,
      departmentName: departmentName,
      snapshot: snapshot,
    ),
  );
}

class _UnitDetailsDialog extends ConsumerStatefulWidget {
  const _UnitDetailsDialog({
    required this.unit,
    this.tenantName,
    this.facilityName,
    this.departmentName,
    this.snapshot,
  });

  final UnitProfile unit;
  final String? tenantName;
  final String? facilityName;
  final String? departmentName;
  final FacilitySetupSnapshot? snapshot;

  @override
  ConsumerState<_UnitDetailsDialog> createState() => _UnitDetailsDialogState();
}

class _UnitDetailsDialogState extends ConsumerState<_UnitDetailsDialog> {
  static const String _emptyValue = '—';

  late UnitProfile _unit;
  bool _mutated = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _unit = widget.unit;
  }

  bool get _canEditStructure =>
      ref.read(appAccessPolicyProvider).canEditFacilitySetupStructure();

  bool get _canMutate => _canEditStructure && !_unit.isDeleted && !_busy;

  FacilitySetupSnapshot? get _effectiveSnapshot {
    final AsyncValue<Result<FacilitySetupSnapshot>> setup =
        ref.read(tenantFacilitySetupControllerProvider);
    final FacilitySetupSnapshot? fromController = setup.value?.when(
      success: (FacilitySetupSnapshot value) => value,
      failure: (_) => null,
    );
    return fromController ?? widget.snapshot;
  }

  String _statusLabel(AppLocalizations l10n) {
    if (_unit.isDeleted) {
      return l10n.tenantFacilityStructureDeletedStatus;
    }
    return _unit.isActive
        ? l10n.tenantFacilityStatusActive
        : l10n.tenantFacilityStatusInactive;
  }

  AppWorkspaceStatusTone _statusTone() {
    if (_unit.isDeleted) {
      return AppWorkspaceStatusTone.error;
    }
    return _unit.isActive
        ? AppWorkspaceStatusTone.success
        : AppWorkspaceStatusTone.neutral;
  }

  String _resolveTenantName() {
    final String? provided = widget.tenantName?.trim();
    if (provided != null && provided.isNotEmpty && provided != _emptyValue) {
      return provided;
    }
    final FacilitySetupSnapshot? snapshot = _effectiveSnapshot;
    final TenantProfile? tenant = snapshot?.tenant;
    if (tenant != null && tenant.id == _unit.tenantId) {
      return tenant.name;
    }
    return _emptyValue;
  }

  String? _resolveFacilityName() {
    final String? provided = widget.facilityName?.trim();
    if (provided != null &&
        provided.isNotEmpty &&
        provided != _emptyValue) {
      return provided;
    }
    final String? facilityId = _unit.facilityId?.trim();
    if (facilityId == null || facilityId.isEmpty) {
      return null;
    }
    final FacilitySetupSnapshot? snapshot = _effectiveSnapshot;
    if (snapshot == null) {
      return null;
    }
    final FacilityProfile? facility = snapshot.facility;
    if (facility != null && facility.id == facilityId) {
      return facility.name;
    }
    for (final FacilityProfile item in snapshot.facilities) {
      if (item.id == facilityId) {
        return item.name;
      }
    }
    return null;
  }

  String _resolveDepartmentName() {
    final String? provided = widget.departmentName?.trim();
    if (provided != null &&
        provided.isNotEmpty &&
        provided != _emptyValue) {
      return provided;
    }
    final String? departmentId = _unit.departmentId?.trim();
    if (departmentId == null || departmentId.isEmpty) {
      return _emptyValue;
    }
    final FacilitySetupSnapshot? snapshot = _effectiveSnapshot;
    if (snapshot == null) {
      return _emptyValue;
    }
    for (final DepartmentProfile department in snapshot.departments) {
      if (department.id == departmentId) {
        if (department.isDeleted) {
          return '${department.name} (${context.l10n.tenantFacilityStructureDeletedStatus})';
        }
        return department.name;
      }
    }
    return _emptyValue;
  }

  UnitProfile? _findUnitInSetup() {
    final FacilitySetupSnapshot? snapshot = _effectiveSnapshot;
    if (snapshot == null) {
      return null;
    }
    for (final UnitProfile item in snapshot.units) {
      if (item.id == _unit.id) {
        return item;
      }
    }
    return null;
  }

  void _refreshUnitAfterMutation() {
    final Object? saved =
        ref.read(tenantFacilitySetupSubmissionProvider).lastSavedEntity;
    if (saved is UnitProfile && saved.id == _unit.id) {
      setState(() {
        _unit = saved;
      });
      return;
    }

    final UnitProfile? updated = _findUnitInSetup();
    if (updated != null) {
      setState(() {
        _unit = updated;
      });
    }
  }

  Future<void> _editUnit() async {
    final FacilitySetupSnapshot? snapshot = _effectiveSnapshot;
    if (snapshot == null || _busy) {
      return;
    }

    final int versionBefore =
        ref.read(tenantFacilitySetupSubmissionProvider).successVersion;

    setState(() {
      _busy = true;
    });
    try {
      await showTenantFacilityUnitFormDialog(
        context,
        snapshot,
        unit: _unit,
        openDetailsOnSave: false,
      );
      if (!mounted) {
        return;
      }

      final TenantFacilitySetupSubmissionState submission =
          ref.read(tenantFacilitySetupSubmissionProvider);
      if (submission.successVersion <= versionBefore) {
        return;
      }

      _mutated = true;
      _refreshUnitAfterMutation();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _deleteUnit() async {
    if (_busy) {
      return;
    }
    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AppConfirmActionDialog(
        title: l10n.tenantFacilitySoftDeleteStructureTitle,
        body: l10n.tenantFacilitySoftDeleteStructureBody(_unit.name),
        highlightedText: _unit.name,
        submitLabel: l10n.tenantFacilityDeleteConfirmAction,
        destructive: true,
        icon: const Icon(Icons.delete_outline),
        onConfirm: () async {
          final bool deleted = await ref
              .read(tenantFacilitySetupSubmissionProvider.notifier)
              .deleteUnit(_unit.mutationId);
          if (deleted) {
            return null;
          }
          return ref.read(tenantFacilitySetupSubmissionProvider).failure ??
              const AppFailure.unexpected();
        },
      ),
    );

    if (!mounted || confirmed != true) {
      return;
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final String statusLabel = _statusLabel(l10n);
    final String? facilityName = _resolveFacilityName();
    final String departmentName = _resolveDepartmentName();
    final String? displayId = tenantFacilityHumanFriendlyDisplayId(
      _unit.displayId,
      opaqueId: _unit.resourceUuid ?? _unit.id,
    );
    final Locale locale = Localizations.localeOf(context);
    final String? createdAt = _unit.createdAt == null
        ? null
        : AppFormatters.dateTime(_unit.createdAt!, locale);
    final String? updatedAt = _unit.updatedAt == null
        ? null
        : AppFormatters.dateTime(_unit.updatedAt!, locale);

    const Set<String> emptyPlaceholders = <String>{_emptyValue};

    final List<AppInfoSheetItem> overviewItems = <AppInfoSheetItem>[
      AppInfoSheetItem(
        label: l10n.tenantFacilityUnitNameLabel,
        value: _unit.name,
      ),
      AppInfoSheetItem(
        label: l10n.tenantFacilityTenantStatusLabel,
        value: statusLabel,
      ),
      if (displayId != null)
        AppInfoSheetItem(
          label: l10n.tenantFacilityUnitIdLabel,
          value: displayId,
          copyable: true,
          copyTooltip: l10n.copyIdentifierAction,
          copiedMessage: l10n.identifierCopiedMessage,
          copyPlaceholderValues: emptyPlaceholders,
        ),
    ];

    final List<AppInfoSheetItem> structureItems = <AppInfoSheetItem>[
      AppInfoSheetItem(
        label: l10n.tenantFacilityUnitDepartmentLabel,
        value: departmentName,
      ),
      AppInfoSheetItem(
        label: l10n.profileTenantLabel,
        value: _resolveTenantName(),
      ),
      if (facilityName != null)
        AppInfoSheetItem(
          label: l10n.profileFacilityLabel,
          value: facilityName,
        ),
    ];

    final List<AppInfoSheetItem> activityItems = <AppInfoSheetItem>[
      if (createdAt != null)
        AppInfoSheetItem(
          label: l10n.tenantFacilityCreatedAtLabel,
          value: createdAt,
        ),
      if (updatedAt != null)
        AppInfoSheetItem(
          label: l10n.tenantFacilityUpdatedAtLabel,
          value: updatedAt,
        ),
    ];

    return AppDialog(
      title: Text(l10n.tenantFacilityUnitDetailsTitle),
      icon: const Icon(Icons.account_tree_outlined),
      scrollable: true,
      pinActionsToBottom: true,
      maxWidth: 720,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: appCollapsibleSectionSpacing(context, <Widget>[
          AppCollapsibleSection(
            titleIcon: Icons.account_tree_outlined,
            eyebrow: displayId,
            title: _unit.name,
            subtitle: departmentName == _emptyValue ? null : departmentName,
            collapsible: false,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _UnitStatusBadge(
                label: statusLabel,
                tone: _statusTone(),
              ),
            ),
          ),
          if (_busy)
            const Center(child: AppLoadingIndicator.compact(expand: false)),
          AppCollapsibleSection(
            title: l10n.hrStaffOverviewSectionTitle,
            titleIcon: Icons.info_outline,
            child: AppInfoSheetGrid(
              emptyValue: _emptyValue,
              items: overviewItems,
            ),
          ),
          AppCollapsibleSection(
            title: l10n.tenantFacilityFacilityDetailsStructureHeading,
            titleIcon: Icons.account_tree_outlined,
            child: AppInfoSheetGrid(
              emptyValue: _emptyValue,
              items: structureItems,
            ),
          ),
          if (activityItems.isNotEmpty)
            AppCollapsibleSection(
              title: l10n.workspaceToolbarSectionActivity,
              titleIcon: Icons.schedule_outlined,
              child: AppInfoSheetGrid(
                emptyValue: _emptyValue,
                items: activityItems,
              ),
            ),
        ]),
      ),
      actions: <Widget>[
        if (_canEditStructure && !_unit.isDeleted)
          AppButton.secondary(
            label: l10n.tenantFacilityEditUnitDetailsAction,
            leadingIcon: Icons.edit_outlined,
            enabled: _canMutate,
            onPressed: () => unawaited(_editUnit()),
          ),
        if (_canEditStructure && !_unit.isDeleted)
          AppButton.primary(
            label: l10n.tenantFacilityDeleteUnitDetailsAction,
            leadingIcon: Icons.delete_outline,
            color: colorScheme.error,
            enabled: _canMutate,
            isLoading: _busy,
            onPressed: () => unawaited(_deleteUnit()),
          ),
        AppButton.secondary(
          label: l10n.commonCloseActionLabel,
          leadingIcon: Icons.close,
          enabled: !_busy,
          onPressed: () => Navigator.of(context).pop(_mutated ? true : null),
        ),
      ],
    );
  }
}

class _UnitStatusBadge extends StatelessWidget {
  const _UnitStatusBadge({required this.label, required this.tone});

  final String label;
  final AppWorkspaceStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final Color foreground = switch (tone) {
      AppWorkspaceStatusTone.success => colorScheme.primary,
      AppWorkspaceStatusTone.error => colorScheme.error,
      AppWorkspaceStatusTone.warning => colorScheme.tertiary,
      AppWorkspaceStatusTone.info => colorScheme.secondary,
      AppWorkspaceStatusTone.neutral => colorScheme.onSurfaceVariant,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(theme.radius.sm),
        border: theme.borders.all(color: foreground.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: foreground,
            fontWeight: AppFontWeight.emphasis,
          ),
        ),
      ),
    );
  }
}
