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

Future<bool?> showBedDetailsDialog(
  BuildContext context, {
  required BedProfile bed,
  String? tenantName,
  String? facilityName,
  String? wardName,
  String? roomName,
  FacilitySetupSnapshot? snapshot,
}) {
  return showAppDialog<bool>(
    context: context,
    builder: (_) => _BedDetailsDialog(
      bed: bed,
      tenantName: tenantName,
      facilityName: facilityName,
      wardName: wardName,
      roomName: roomName,
      snapshot: snapshot,
    ),
  );
}

class _BedDetailsDialog extends ConsumerStatefulWidget {
  const _BedDetailsDialog({
    required this.bed,
    this.tenantName,
    this.facilityName,
    this.wardName,
    this.roomName,
    this.snapshot,
  });

  final BedProfile bed;
  final String? tenantName;
  final String? facilityName;
  final String? wardName;
  final String? roomName;
  final FacilitySetupSnapshot? snapshot;

  @override
  ConsumerState<_BedDetailsDialog> createState() => _BedDetailsDialogState();
}

class _BedDetailsDialogState extends ConsumerState<_BedDetailsDialog> {
  static const String _emptyValue = '—';

  late BedProfile _bed;
  bool _mutated = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _bed = widget.bed;
  }

  bool get _canEditStructure =>
      ref.read(appAccessPolicyProvider).canEditFacilitySetupStructure();

  bool get _canMutate => _canEditStructure && !_bed.isDeleted && !_busy;

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
    if (_bed.isDeleted) {
      return l10n.tenantFacilityStructureDeletedStatus;
    }
    return tenantFacilityBedStatusLabel(l10n, _bed.status);
  }

  AppWorkspaceStatusTone _statusTone() {
    if (_bed.isDeleted) {
      return AppWorkspaceStatusTone.error;
    }
    return switch (_bed.status) {
      BedSetupStatus.available => AppWorkspaceStatusTone.success,
      BedSetupStatus.occupied => AppWorkspaceStatusTone.info,
      BedSetupStatus.reserved => AppWorkspaceStatusTone.warning,
      BedSetupStatus.cleaning ||
      BedSetupStatus.maintenance ||
      BedSetupStatus.blocked ||
      BedSetupStatus.outOfService =>
        AppWorkspaceStatusTone.neutral,
    };
  }

  String _resolveTenantName() {
    final String? provided = widget.tenantName?.trim();
    if (provided != null && provided.isNotEmpty && provided != _emptyValue) {
      return provided;
    }
    final FacilitySetupSnapshot? snapshot = _effectiveSnapshot;
    final TenantProfile? tenant = snapshot?.tenant;
    if (tenant != null && tenant.id == _bed.tenantId) {
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
    final String facilityId = _bed.facilityId.trim();
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

  String _resolveWardName() {
    final String? provided = widget.wardName?.trim();
    if (provided != null && provided.isNotEmpty && provided != _emptyValue) {
      return provided;
    }
    final FacilitySetupSnapshot? snapshot = _effectiveSnapshot;
    if (snapshot != null) {
      for (final WardProfile ward in snapshot.wards) {
        if (ward.id == _bed.wardId) {
          if (ward.isDeleted) {
            return '${ward.name} (${context.l10n.tenantFacilityStructureDeletedStatus})';
          }
          return ward.name;
        }
      }
    }
    return _emptyValue;
  }

  String _resolveRoomName() {
    final String? provided = widget.roomName?.trim();
    if (provided != null && provided.isNotEmpty && provided != _emptyValue) {
      return provided;
    }
    final String? roomId = _bed.roomId?.trim();
    if (roomId == null || roomId.isEmpty) {
      return _emptyValue;
    }
    final FacilitySetupSnapshot? snapshot = _effectiveSnapshot;
    if (snapshot != null) {
      for (final RoomProfile room in snapshot.rooms) {
        if (room.id == roomId) {
          if (room.isDeleted) {
            return '${room.name} (${context.l10n.tenantFacilityStructureDeletedStatus})';
          }
          return room.name;
        }
      }
    }
    return _emptyValue;
  }

  String _formatTimestamp(BuildContext context, DateTime? value) {
    if (value == null) {
      return _emptyValue;
    }
    return AppFormatters.dateTime(
      value.toLocal(),
      Localizations.localeOf(context),
    );
  }

  BedProfile? _findBedInSetup() {
    final FacilitySetupSnapshot? snapshot = _effectiveSnapshot;
    if (snapshot == null) {
      return null;
    }
    for (final BedProfile item in snapshot.beds) {
      if (item.id == _bed.id) {
        return item;
      }
    }
    return null;
  }

  void _refreshBedAfterMutation() {
    final Object? saved =
        ref.read(tenantFacilitySetupSubmissionProvider).lastSavedEntity;
    if (saved is BedProfile && saved.id == _bed.id) {
      setState(() {
        _bed = saved;
      });
      return;
    }

    final BedProfile? updated = _findBedInSetup();
    if (updated != null) {
      setState(() {
        _bed = updated;
      });
    }
  }

  Future<void> _editBed() async {
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
      await showTenantFacilityBedFormDialog(
        context,
        snapshot,
        bed: _bed,
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
      _refreshBedAfterMutation();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _deleteBed() async {
    if (_busy) {
      return;
    }
    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AppConfirmActionDialog(
        title: l10n.tenantFacilitySoftDeleteStructureTitle,
        body: l10n.tenantFacilitySoftDeleteStructureBody(_bed.label),
        highlightedText: _bed.label,
        submitLabel: l10n.tenantFacilityDeleteConfirmAction,
        destructive: true,
        icon: const Icon(Icons.delete_outline),
        onConfirm: () async {
          final bool deleted = await ref
              .read(tenantFacilitySetupSubmissionProvider.notifier)
              .deleteBed(_bed.id);
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
    final String wardName = _resolveWardName();
    final String roomName = _resolveRoomName();
    final String? displayId = tenantFacilityHumanFriendlyDisplayId(
      _bed.displayId,
      opaqueId: _bed.id,
    );

    const Set<String> emptyPlaceholders = <String>{_emptyValue};

    final List<AppInfoSheetItem> overviewItems = <AppInfoSheetItem>[
      AppInfoSheetItem(
        label: l10n.tenantFacilityBedLabelLabel,
        value: _bed.label,
      ),
      if (displayId != null)
        AppInfoSheetItem(
          label: l10n.tenantFacilityBedIdLabel,
          value: displayId,
          copyable: true,
          copyTooltip: l10n.copyIdentifierAction,
          copiedMessage: l10n.identifierCopiedMessage,
          copyPlaceholderValues: emptyPlaceholders,
        ),
      AppInfoSheetItem(
        label: l10n.tenantFacilityBedStatusLabel,
        value: statusLabel,
      ),
    ];

    final List<AppInfoSheetItem> structureItems = <AppInfoSheetItem>[
      AppInfoSheetItem(
        label: l10n.tenantFacilityBedWardLabel,
        value: wardName,
      ),
      AppInfoSheetItem(
        label: l10n.tenantFacilityBedRoomLabel,
        value: roomName,
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
      if (_bed.createdAt != null)
        AppInfoSheetItem(
          label: l10n.tenantFacilityCreatedAtLabel,
          value: _formatTimestamp(context, _bed.createdAt),
        ),
      if (_bed.updatedAt != null)
        AppInfoSheetItem(
          label: l10n.tenantFacilityUpdatedAtLabel,
          value: _formatTimestamp(context, _bed.updatedAt),
        ),
    ];

    return AppDialog(
      title: Text(l10n.tenantFacilityBedDetailsTitle),
      icon: const Icon(Icons.bed_outlined),
      scrollable: true,
      pinActionsToBottom: true,
      maxWidth: 720,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: appCollapsibleSectionSpacing(context, <Widget>[
          AppCollapsibleSection(
            titleIcon: Icons.bed_outlined,
            eyebrow: displayId,
            title: _bed.label,
            subtitle: wardName,
            collapsible: false,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _BedStatusBadge(label: statusLabel, tone: _statusTone()),
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
        if (_canEditStructure && !_bed.isDeleted)
          AppButton.secondary(
            label: l10n.tenantFacilityEditBedDetailsAction,
            leadingIcon: Icons.edit_outlined,
            enabled: _canMutate,
            onPressed: () => unawaited(_editBed()),
          ),
        if (_canEditStructure && !_bed.isDeleted)
          AppButton.primary(
            label: l10n.tenantFacilityDeleteBedDetailsAction,
            leadingIcon: Icons.delete_outline,
            color: colorScheme.error,
            enabled: _canMutate,
            isLoading: _busy,
            onPressed: () => unawaited(_deleteBed()),
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

class _BedStatusBadge extends StatelessWidget {
  const _BedStatusBadge({required this.label, required this.tone});

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
