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

Future<bool?> showWardDetailsDialog(
  BuildContext context, {
  required WardProfile ward,
  String? tenantName,
  String? facilityName,
  String? departmentName,
  FacilitySetupSnapshot? snapshot,
}) {
  return showAppDialog<bool>(
    context: context,
    builder: (_) => _WardDetailsDialog(
      ward: ward,
      tenantName: tenantName,
      facilityName: facilityName,
      departmentName: departmentName,
      snapshot: snapshot,
    ),
  );
}

class _WardDetailsDialog extends ConsumerStatefulWidget {
  const _WardDetailsDialog({
    required this.ward,
    this.tenantName,
    this.facilityName,
    this.departmentName,
    this.snapshot,
  });

  final WardProfile ward;
  final String? tenantName;
  final String? facilityName;
  final String? departmentName;
  final FacilitySetupSnapshot? snapshot;

  @override
  ConsumerState<_WardDetailsDialog> createState() => _WardDetailsDialogState();
}

class _WardDetailsDialogState extends ConsumerState<_WardDetailsDialog> {
  static const String _emptyValue = '—';

  late WardProfile _ward;
  bool _mutated = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ward = widget.ward;
  }

  bool get _canEditStructure =>
      ref.read(appAccessPolicyProvider).canEditFacilitySetupStructure();

  bool get _canMutate => _canEditStructure && !_ward.isDeleted && !_busy;

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
    if (_ward.isDeleted) {
      return l10n.tenantFacilityStructureDeletedStatus;
    }
    return _ward.isActive
        ? l10n.tenantFacilityStatusActive
        : l10n.tenantFacilityStatusInactive;
  }

  AppWorkspaceStatusTone _statusTone() {
    if (_ward.isDeleted) {
      return AppWorkspaceStatusTone.error;
    }
    return _ward.isActive
        ? AppWorkspaceStatusTone.success
        : AppWorkspaceStatusTone.neutral;
  }

  IconData _typeIcon(WardSetupType type) {
    return switch (type) {
      WardSetupType.general => Icons.hotel_outlined,
      WardSetupType.icu => Icons.monitor_heart_outlined,
      WardSetupType.maternity => Icons.pregnant_woman_outlined,
      WardSetupType.pediatric => Icons.child_care_outlined,
      WardSetupType.surgical => Icons.local_hospital_outlined,
      WardSetupType.other => Icons.category_outlined,
    };
  }

  String _resolveTenantName() {
    final String? provided = widget.tenantName?.trim();
    if (provided != null && provided.isNotEmpty && provided != _emptyValue) {
      return provided;
    }
    final FacilitySetupSnapshot? snapshot = _effectiveSnapshot;
    final TenantProfile? tenant = snapshot?.tenant;
    if (tenant != null && tenant.id == _ward.tenantId) {
      return tenant.name;
    }
    return _emptyValue;
  }

  String? _resolveFacilityName() {
    final String? provided = widget.facilityName?.trim();
    if (provided != null && provided.isNotEmpty && provided != _emptyValue) {
      return provided;
    }
    final String facilityId = _ward.facilityId.trim();
    if (facilityId.isEmpty) {
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
    if (provided != null && provided.isNotEmpty && provided != _emptyValue) {
      return provided;
    }
    final String? departmentId = _ward.departmentId?.trim();
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

  WardProfile? _findWardInSetup() {
    final FacilitySetupSnapshot? snapshot = _effectiveSnapshot;
    if (snapshot == null) {
      return null;
    }
    for (final WardProfile item in snapshot.wards) {
      if (item.id == _ward.id) {
        return item;
      }
    }
    return null;
  }

  void _refreshWardAfterMutation() {
    final Object? saved =
        ref.read(tenantFacilitySetupSubmissionProvider).lastSavedEntity;
    if (saved is WardProfile && saved.id == _ward.id) {
      setState(() {
        _ward = saved;
      });
      return;
    }

    final WardProfile? updated = _findWardInSetup();
    if (updated != null) {
      setState(() {
        _ward = updated;
      });
    }
  }

  Future<void> _editWard() async {
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
      await showTenantFacilityWardFormDialog(
        context,
        snapshot,
        ward: _ward,
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
      _refreshWardAfterMutation();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _deleteWard() async {
    if (_busy) {
      return;
    }
    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AppConfirmActionDialog(
        title: l10n.tenantFacilitySoftDeleteStructureTitle,
        body: l10n.tenantFacilitySoftDeleteStructureBody(_ward.name),
        highlightedText: _ward.name,
        submitLabel: l10n.tenantFacilityDeleteConfirmAction,
        destructive: true,
        icon: const Icon(Icons.delete_outline),
        onConfirm: () async {
          final bool deleted = await ref
              .read(tenantFacilitySetupSubmissionProvider.notifier)
              .deleteWard(_ward.id);
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
    final String typeLabel = _wardTypeLabel(l10n, _ward.type);
    final String departmentName = _resolveDepartmentName();
    final String? displayId = tenantFacilityHumanFriendlyDisplayId(
      _ward.displayId,
      opaqueId: _ward.resourceUuid ?? _ward.id,
    );
    final Locale locale = Localizations.localeOf(context);
    final String? createdAt = _ward.createdAt == null
        ? null
        : AppFormatters.dateTime(_ward.createdAt!, locale);
    final String? updatedAt = _ward.updatedAt == null
        ? null
        : AppFormatters.dateTime(_ward.updatedAt!, locale);

    const Set<String> emptyPlaceholders = <String>{_emptyValue};

    final List<AppInfoSheetItem> overviewItems = <AppInfoSheetItem>[
      AppInfoSheetItem(
        label: l10n.tenantFacilityWardNameLabel,
        value: _ward.name,
      ),
      AppInfoSheetItem(
        label: l10n.tenantFacilityWardTypeLabel,
        value: typeLabel,
      ),
      AppInfoSheetItem(
        label: l10n.tenantFacilityTenantStatusLabel,
        value: statusLabel,
      ),
      if (displayId != null)
        AppInfoSheetItem(
          label: l10n.tenantFacilityWardIdLabel,
          value: displayId,
          copyable: true,
          copyTooltip: l10n.copyIdentifierAction,
          copiedMessage: l10n.identifierCopiedMessage,
          copyPlaceholderValues: emptyPlaceholders,
        ),
    ];

    final List<AppInfoSheetItem> structureItems = <AppInfoSheetItem>[
      AppInfoSheetItem(
        label: l10n.tenantFacilityWardDepartmentLabel,
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
      title: Text(l10n.tenantFacilityWardDetailsTitle),
      icon: const Icon(Icons.hotel_outlined),
      scrollable: true,
      pinActionsToBottom: true,
      maxWidth: 720,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: appCollapsibleSectionSpacing(context, <Widget>[
          AppCollapsibleSection(
            titleIcon: _typeIcon(_ward.type),
            eyebrow: displayId,
            title: _ward.name,
            subtitle: typeLabel,
            collapsible: false,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _WardStatusBadge(
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
        if (_canEditStructure && !_ward.isDeleted)
          AppButton.secondary(
            label: l10n.tenantFacilityEditWardDetailsAction,
            leadingIcon: Icons.edit_outlined,
            enabled: _canMutate,
            onPressed: () => unawaited(_editWard()),
          ),
        if (_canEditStructure && !_ward.isDeleted)
          AppButton.primary(
            label: l10n.tenantFacilityDeleteWardDetailsAction,
            leadingIcon: Icons.delete_outline,
            color: colorScheme.error,
            enabled: _canMutate,
            isLoading: _busy,
            onPressed: () => unawaited(_deleteWard()),
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

class _WardStatusBadge extends StatelessWidget {
  const _WardStatusBadge({required this.label, required this.tone});

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

String _wardTypeLabel(AppLocalizations l10n, WardSetupType type) {
  return switch (type) {
    WardSetupType.general => l10n.tenantFacilityWardTypeGeneral,
    WardSetupType.icu => l10n.tenantFacilityWardTypeIcu,
    WardSetupType.maternity => l10n.tenantFacilityWardTypeMaternity,
    WardSetupType.pediatric => l10n.tenantFacilityWardTypePediatric,
    WardSetupType.surgical => l10n.tenantFacilityWardTypeSurgical,
    WardSetupType.other => l10n.tenantFacilityWardTypeOther,
  };
}
