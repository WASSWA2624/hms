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

Future<bool?> showRoomDetailsDialog(
  BuildContext context, {
  required RoomProfile room,
  String? tenantName,
  String? facilityName,
  String? wardName,
  FacilitySetupSnapshot? snapshot,
}) {
  return showAppDialog<bool>(
    context: context,
    builder: (_) => _RoomDetailsDialog(
      room: room,
      tenantName: tenantName,
      facilityName: facilityName,
      wardName: wardName,
      snapshot: snapshot,
    ),
  );
}

class _RoomDetailsDialog extends ConsumerStatefulWidget {
  const _RoomDetailsDialog({
    required this.room,
    this.tenantName,
    this.facilityName,
    this.wardName,
    this.snapshot,
  });

  final RoomProfile room;
  final String? tenantName;
  final String? facilityName;
  final String? wardName;
  final FacilitySetupSnapshot? snapshot;

  @override
  ConsumerState<_RoomDetailsDialog> createState() => _RoomDetailsDialogState();
}

class _RoomDetailsDialogState extends ConsumerState<_RoomDetailsDialog> {
  static const String _emptyValue = '—';

  late RoomProfile _room;
  bool _mutated = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _room = widget.room;
  }

  bool get _canEditStructure =>
      ref.read(appAccessPolicyProvider).canEditFacilitySetupStructure();

  bool get _canMutate => _canEditStructure && !_room.isDeleted && !_busy;

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
    if (_room.isDeleted) {
      return l10n.tenantFacilityStructureDeletedStatus;
    }
    return l10n.tenantFacilityTenantStatusActive;
  }

  AppWorkspaceStatusTone _statusTone() {
    if (_room.isDeleted) {
      return AppWorkspaceStatusTone.error;
    }
    return AppWorkspaceStatusTone.success;
  }

  String _resolveTenantName() {
    final String? provided = widget.tenantName?.trim();
    if (provided != null && provided.isNotEmpty && provided != _emptyValue) {
      return provided;
    }
    final FacilitySetupSnapshot? snapshot = _effectiveSnapshot;
    final TenantProfile? tenant = snapshot?.tenant;
    if (tenant != null && tenant.id == _room.tenantId) {
      return tenant.name;
    }
    return _emptyValue;
  }

  String _resolveFacilityName() {
    final String? provided = widget.facilityName?.trim();
    if (provided != null && provided.isNotEmpty && provided != _emptyValue) {
      return provided;
    }
    final FacilitySetupSnapshot? snapshot = _effectiveSnapshot;
    if (snapshot == null) {
      return _emptyValue;
    }
    final FacilityProfile? facility = snapshot.facility;
    if (facility != null && facility.id == _room.facilityId) {
      return facility.name;
    }
    for (final FacilityProfile item in snapshot.facilities) {
      if (item.id == _room.facilityId) {
        return item.name;
      }
    }
    return _emptyValue;
  }

  String _resolveWardName() {
    final String? provided = widget.wardName?.trim();
    if (provided != null && provided.isNotEmpty && provided != _emptyValue) {
      return provided;
    }
    final String? wardId = _room.wardId?.trim();
    if (wardId == null || wardId.isEmpty) {
      return context.l10n.tenantFacilityRoomOutpatientLabel;
    }
    final FacilitySetupSnapshot? snapshot = _effectiveSnapshot;
    if (snapshot == null) {
      return _emptyValue;
    }
    for (final WardProfile ward in snapshot.wards) {
      if (ward.id == wardId) {
        if (ward.isDeleted) {
          return '${ward.name} (${context.l10n.tenantFacilityStructureDeletedStatus})';
        }
        return ward.name;
      }
    }
    return _emptyValue;
  }

  RoomProfile? _findRoomInSetup() {
    final FacilitySetupSnapshot? snapshot = _effectiveSnapshot;
    if (snapshot == null) {
      return null;
    }
    for (final RoomProfile item in snapshot.rooms) {
      if (item.id == _room.id) {
        return item;
      }
    }
    return null;
  }

  void _refreshRoomAfterMutation() {
    final Object? saved =
        ref.read(tenantFacilitySetupSubmissionProvider).lastSavedEntity;
    if (saved is RoomProfile && saved.id == _room.id) {
      setState(() {
        _room = saved;
      });
      return;
    }

    final RoomProfile? updated = _findRoomInSetup();
    if (updated != null) {
      setState(() {
        _room = updated;
      });
    }
  }

  Future<void> _editRoom() async {
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
      await showTenantFacilityRoomFormDialog(
        context,
        snapshot,
        room: _room,
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
      _refreshRoomAfterMutation();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _deleteRoom() async {
    if (_busy) {
      return;
    }
    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AppConfirmActionDialog(
        title: l10n.tenantFacilitySoftDeleteStructureTitle,
        body: l10n.tenantFacilitySoftDeleteStructureBody(_room.name),
        highlightedText: _room.name,
        submitLabel: l10n.tenantFacilityDeleteConfirmAction,
        destructive: true,
        icon: const Icon(Icons.delete_outline),
        onConfirm: () async {
          final bool deleted = await ref
              .read(tenantFacilitySetupSubmissionProvider.notifier)
              .deleteRoom(_room.id);
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
    final String floor = _room.floor?.trim().isNotEmpty == true
        ? _room.floor!.trim()
        : _emptyValue;
    final String? displayId = tenantFacilityHumanFriendlyDisplayId(
      _room.displayId,
      opaqueId: _room.resourceUuid ?? _room.id,
    );
    final Locale locale = Localizations.localeOf(context);
    final String? createdAt = _room.createdAt == null
        ? null
        : AppFormatters.dateTime(_room.createdAt!, locale);
    final String? updatedAt = _room.updatedAt == null
        ? null
        : AppFormatters.dateTime(_room.updatedAt!, locale);

    const Set<String> emptyPlaceholders = <String>{_emptyValue};

    final List<AppInfoSheetItem> overviewItems = <AppInfoSheetItem>[
      AppInfoSheetItem(
        label: l10n.tenantFacilityRoomNameLabel,
        value: _room.name,
      ),
      AppInfoSheetItem(
        label: l10n.tenantFacilityRoomFloorLabel,
        value: floor,
      ),
      AppInfoSheetItem(
        label: l10n.tenantFacilityTenantStatusLabel,
        value: statusLabel,
      ),
      if (displayId != null)
        AppInfoSheetItem(
          label: l10n.tenantFacilityRoomIdLabel,
          value: displayId,
          copyable: true,
          copyTooltip: l10n.copyIdentifierAction,
          copiedMessage: l10n.identifierCopiedMessage,
          copyPlaceholderValues: emptyPlaceholders,
        ),
    ];

    final List<AppInfoSheetItem> structureItems = <AppInfoSheetItem>[
      AppInfoSheetItem(
        label: l10n.tenantFacilityRoomWardLabel,
        value: _resolveWardName(),
      ),
      AppInfoSheetItem(
        label: l10n.profileFacilityLabel,
        value: _resolveFacilityName(),
      ),
      AppInfoSheetItem(
        label: l10n.profileTenantLabel,
        value: _resolveTenantName(),
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
      title: Text(l10n.tenantFacilityRoomDetailsTitle),
      icon: const Icon(Icons.meeting_room_outlined),
      scrollable: true,
      pinActionsToBottom: true,
      maxWidth: 720,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: appCollapsibleSectionSpacing(context, <Widget>[
          AppCollapsibleSection(
            titleIcon: Icons.meeting_room_outlined,
            eyebrow: displayId,
            title: _room.name,
            subtitle: _resolveWardName(),
            collapsible: false,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _RoomStatusBadge(
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
        if (_canEditStructure && !_room.isDeleted)
          AppButton.secondary(
            label: l10n.tenantFacilityEditRoomDetailsAction,
            leadingIcon: Icons.edit_outlined,
            enabled: _canMutate,
            onPressed: () => unawaited(_editRoom()),
          ),
        if (_canEditStructure && !_room.isDeleted)
          AppButton.primary(
            label: l10n.tenantFacilityDeleteRoomDetailsAction,
            leadingIcon: Icons.delete_outline,
            color: colorScheme.error,
            enabled: _canMutate,
            isLoading: _busy,
            onPressed: () => unawaited(_deleteRoom()),
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

class _RoomStatusBadge extends StatelessWidget {
  const _RoomStatusBadge({required this.label, required this.tone});

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
