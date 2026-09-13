const prisma = require('@prisma/client');
const repo = require('@repositories/hr-workspace/hr-workspace.repository');
const { HttpError } = require('@lib/errors');
const { createAuditLog } = require('@lib/audit');
const { normalizeIdentifier, resolveModelRecordByIdentifier } = require('@lib/identifiers/resolve-entity-id');
const { resolveIdentifierForFilter, resolveIdentifierForPayload, resolvePublicIdentifier } = require('@lib/billing/identifiers');
const { emitToUsers, HR_EVENTS } = require('@lib/websocket');
const { ROLES } = require('@config/roles');
const { ROLE_PERMISSIONS } = require('@config/permissions');
const { generateStaffNumber: generateStaffNumberCore } = require('@lib/hr/staff-number');
const {
  buildWorkflow,
  generateRosterAssignments: generateRosterAssignmentsCore,
  resolveRecordOrThrow,
  resolveDisplayId,
} = require('@services/hr-workspace/hr-roster-engine');
const {
  calculateCompensationAmount,
  computeEligibleWorkdays,
  normalizeMoney,
  sumCompensationAmounts,
} = require('@services/hr-workspace/payroll-calculation');
const { loadStaffPayrollActivity } = require('@services/hr-workspace/hr-payroll-activity');

const DEFAULT_PANEL = 'staffing';
const DEFAULT_RESOURCE = 'staff-profiles';

const HR_RECIPIENT_ROLES = Object.freeze([
  ROLES.PLATFORM_ADMIN,
  ROLES.TENANT_ADMIN,
  ROLES.FACILITY_ADMIN,
  ROLES.HR,
  ROLES.OPERATIONS,
  ROLES.NURSE,
  ROLES.DOCTOR,
]);

const WORKBENCH_PANELS = Object.freeze([
  {
    id: 'overview',
    label_key: 'hr.workbench.panels.overview',
    default_resource: 'staff-profiles',
    resources: ['staff-profiles'],
    visible: true,
  },
  {
    id: 'staffing',
    label_key: 'hr.workbench.panels.staffing',
    default_resource: 'staff-profiles',
    resources: ['staff-positions', 'staff-profiles', 'staff-assignments', 'staff-leaves', 'staff-availabilities'],
    visible: true,
  },
  {
    id: 'roster',
    label_key: 'hr.workbench.panels.roster',
    default_resource: 'rosters',
    resources: ['rosters', 'roster-day-offs'],
    visible: true,
  },
  {
    id: 'shifts',
    label_key: 'hr.workbench.panels.shifts',
    default_resource: 'shifts',
    resources: ['shifts', 'shift-assignments', 'shift-swap-requests', 'shift-templates'],
    visible: true,
  },
  {
    id: 'payroll',
    label_key: 'hr.workbench.panels.payroll',
    default_resource: 'payroll-runs',
    resources: ['payroll-runs', 'payroll-items'],
    visible: true,
  },
  {
    id: 'onboarding',
    label_key: 'hr.workbench.panels.onboarding',
    default_resource: 'doctors',
    resources: ['doctors'],
    visible: false,
  },
]);

const RESOURCE_PANEL_MAP = Object.freeze(
  WORKBENCH_PANELS.reduce((acc, panel) => {
    panel.resources.forEach((resource) => {
      acc[resource] = panel.id;
    });
    return acc;
  }, {})
);

const QUEUE_DEFINITIONS = Object.freeze([
  { id: 'LEAVE_REQUESTS', label_key: 'hr.workbench.queues.LEAVE_REQUESTS', panel: 'staffing', resource: 'staff-leaves' },
  { id: 'SWAP_REQUESTS', label_key: 'hr.workbench.queues.SWAP_REQUESTS', panel: 'shifts', resource: 'shift-swap-requests' },
  { id: 'ROSTER_DRAFTS', label_key: 'hr.workbench.queues.ROSTER_DRAFTS', panel: 'roster', resource: 'rosters' },
  { id: 'UNASSIGNED_SHIFTS', label_key: 'hr.workbench.queues.UNASSIGNED_SHIFTS', panel: 'shifts', resource: 'shifts' },
  { id: 'PAYROLL_DRAFTS', label_key: 'hr.workbench.queues.PAYROLL_DRAFTS', panel: 'payroll', resource: 'payroll-runs' },
  { id: 'OVERDUE_SHIFTS', label_key: 'hr.workbench.queues.OVERDUE_SHIFTS', panel: 'shifts', resource: 'shifts' },
]);

const LEGACY_RESOURCE_CONFIG = Object.freeze({
  'staff-positions': { model: 'staff_position', panel: 'staffing', resource: 'staff-positions' },
  'staff-profiles': { model: 'staff_profile', panel: 'staffing', resource: 'staff-profiles' },
  'staff-assignments': { model: 'staff_assignment', panel: 'staffing', resource: 'staff-assignments' },
  'staff-leaves': { model: 'staff_leave', panel: 'staffing', resource: 'staff-leaves' },
  'staff-availabilities': { model: 'staff_availability', panel: 'staffing', resource: 'staff-availabilities' },
  'rosters': { model: 'roster', panel: 'roster', resource: 'rosters' },
  'roster-day-offs': { model: 'roster_day_off', panel: 'roster', resource: 'roster-day-offs' },
  shifts: { model: 'shift', panel: 'shifts', resource: 'shifts' },
  'shift-assignments': { model: 'shift_assignment', panel: 'shifts', resource: 'shift-assignments' },
  'shift-swap-requests': { model: 'shift_swap_request', panel: 'shifts', resource: 'shift-swap-requests' },
  'shift-templates': { model: 'shift_template', panel: 'shifts', resource: 'shift-templates' },
  'payroll-runs': { model: 'payroll_run', panel: 'payroll', resource: 'payroll-runs' },
  'payroll-items': { model: 'payroll_item', panel: 'payroll', resource: 'payroll-items' },
  doctors: { model: 'doctor', panel: 'onboarding', resource: 'doctors' },
});

const RESOURCE_STATUS_ENUMS = Object.freeze({
  'staff-positions': ['ACTIVE', 'INACTIVE'],
  'staff-profiles': ['ACTIVE', 'INACTIVE', 'SUSPENDED', 'PENDING'],
  'staff-leaves': ['REQUESTED', 'APPROVED', 'REJECTED', 'CANCELLED'],
  'staff-availabilities': ['PREFERRED', 'AVAILABLE', 'UNAVAILABLE'],
  'rosters': ['DRAFT', 'PUBLISHED'],
  shifts: ['SCHEDULED', 'COMPLETED', 'CANCELLED'],
  'shift-swap-requests': ['SCHEDULED', 'COMPLETED', 'CANCELLED'],
  'shift-templates': ['ACTIVE', 'INACTIVE'],
  'payroll-runs': ['DRAFT', 'PROCESSED', 'PAID', 'CANCELLED'],
});

const SHIFT_TYPE_OPTIONS = Object.freeze(['DAY', 'NIGHT', 'SWING', 'ON_CALL']);
const {
  DEFAULT_STAFF_POSITION_NAMES,
  practitionerTypeOptions,
  compensationPayTypeOptions,
  leaveTypeOptions,
  leaveHalfDayPeriodOptions,
  enrichStaffPositionOption,
  staffPositionCatalogOptions,
} = require('@lib/hr/reference-data');
const {
  HR_ASSIGNABLE_ROLE_NAMES,
  enrichRoleOption,
  sortRoleRecords,
} = require('@lib/hr/role-catalog');
const {
  DEFAULT_FACILITY_DEPARTMENT_NAMES,
  inferDepartmentType,
} = require('@lib/setup/facility-structure-catalog');
const SYSTEM_CRITICAL_ROLES = new Set(Object.keys(ROLE_PERMISSIONS));

const normalizeString = (value) => String(value || '').trim();
const normalizeDate = (value) => {
  if (!value) return null;
  const parsed = value instanceof Date ? value : new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
};
const normalizeOrder = (value) => (normalizeString(value).toLowerCase() === 'asc' ? 'asc' : 'desc');
const hasText = (value) => Boolean(normalizeString(value));

const formatDateLabel = (value) => {
  const parsed = normalizeDate(value);
  return parsed ? parsed.toISOString().slice(0, 10) : null;
};

const formatDateRangeLabel = (from, to) => {
  const fromText = formatDateLabel(from);
  const toText = formatDateLabel(to);
  if (fromText && toText) return `${fromText} - ${toText}`;
  return fromText || toText || null;
};

const formatTimeLabel = (value) => {
  const parsed = normalizeDate(value);
  return parsed ? parsed.toISOString().slice(11, 16) : null;
};

const formatShiftScheduleLabel = (start, end) => {
  const dateText = formatDateLabel(start);
  const startTime = formatTimeLabel(start);
  const endTime = formatTimeLabel(end);
  if (dateText && startTime && endTime) {
    return `${dateText} ${startTime}-${endTime}`;
  }
  return formatDateRangeLabel(start, end);
};

const formatShiftOptionLabel = (entry) =>
  [
    normalizeString(entry.shift_template?.name),
    entry.shift_type,
    formatShiftScheduleLabel(entry.start_time, entry.end_time),
    normalizeString(entry.roster?.department?.name || entry.roster?.department?.short_name),
    resolvePublicIdentifier(entry.human_friendly_id),
    entry.status,
  ]
    .filter(Boolean)
    .join(' | ');

const buildPagination = (page, limit, total) => ({
  page,
  limit,
  total,
  totalPages: limit > 0 ? Math.ceil(total / limit) : 0,
  hasNextPage: page * limit < total,
  hasPreviousPage: page > 1,
});

const buildWorkbenchPath = (params = {}) => {
  const query = new URLSearchParams();
  [
    'panel',
    'resource',
    'id',
    'action',
    'queue',
    'facilityId',
    'departmentId',
    'staffProfileId',
    'rosterId',
    'payrollRunId',
  ].forEach((key) => {
    const value = normalizeString(params[key]);
    if (value) query.set(key, value);
  });

  const serialized = query.toString();
  return serialized ? `/hr?${serialized}` : '/hr';
};

const buildQueueMeta = (queue, count) => {
  const definition = QUEUE_DEFINITIONS.find((entry) => entry.id === queue);
  return {
    queue,
    label_key: definition?.label_key || `hr.workbench.queues.${queue}`,
    count: Number(count || 0),
    panel: definition?.panel || null,
    resource: definition?.resource || null,
    target_path: buildWorkbenchPath({
      panel: definition?.panel || undefined,
      resource: definition?.resource || undefined,
      queue,
    }),
  };
};

const buildWorkspaceSpotlight = (summary = {}) => {
  const queueValueMap = {
    LEAVE_REQUESTS: Number(summary.leave_requests || 0),
    SWAP_REQUESTS: Number(summary.swap_requests || 0),
    ROSTER_DRAFTS: Number(summary.draft_rosters || 0),
    UNASSIGNED_SHIFTS: Number(summary.unassigned_shifts || 0),
    PAYROLL_DRAFTS: Number(summary.payroll_draft_runs || 0),
    OVERDUE_SHIFTS: Number(summary.overdue_shifts || 0),
  };

  return QUEUE_DEFINITIONS.map((definition) => ({
    queue: definition.id,
    label_key: definition.label_key,
    count: queueValueMap[definition.id] || 0,
    panel: definition.panel,
    resource: definition.resource,
    target_path: buildWorkbenchPath({
      panel: definition.panel,
      resource: definition.resource,
      queue: definition.id,
    }),
  }))
    .filter((entry) => entry.count > 0)
    .sort((left, right) => right.count - left.count)
    .slice(0, 6);
};

const buildPanelSummaries = (summary = {}) =>
  WORKBENCH_PANELS.map((panel) => {
    let count = 0;
    if (panel.id === 'overview') {
      count = Number(summary.total_staff || 0);
    } else if (panel.id === 'staffing') {
      count = Number(summary.total_staff || 0) + Number(summary.leave_requests || 0);
    } else if (panel.id === 'roster') {
      count = Number(summary.draft_rosters || 0);
    } else if (panel.id === 'shifts') {
      count = Number(summary.unassigned_shifts || 0) + Number(summary.swap_requests || 0) + Number(summary.overdue_shifts || 0);
    } else if (panel.id === 'payroll') {
      count = Number(summary.payroll_draft_runs || 0);
    }

    return {
      id: panel.id,
      label_key: panel.label_key,
      default_resource: panel.default_resource,
      resources: panel.resources,
      visible: panel.visible !== false,
      count,
      target_path: buildWorkbenchPath({ panel: panel.id, resource: panel.default_resource }),
    };
  });

const mapLeave = (item) => ({
  id: resolveDisplayId(item),
  queue: 'LEAVE_REQUESTS',
  display_id: resolveDisplayId(item),
  backend_identifier: item.id,
  leave_type: item.leave_type || null,
  status: item.status,
  staff_profile_id: item.staff_profile_id,
  staff_profile_display_id: resolveDisplayId(item.staff_profile || {}),
  staff_number: item.staff_profile?.staff_number || null,
  staff_name: normalizeString(
    `${item.staff_profile?.user?.profile?.first_name || ''} ${item.staff_profile?.user?.profile?.last_name || ''}`
  ) || item.staff_profile?.user?.email || null,
  staff_position: item.staff_profile?.position || null,
  start_date: item.start_date,
  end_date: item.end_date,
  is_half_day: item.is_half_day === true,
  half_day_period: item.half_day_period || null,
  reason: item.reason || null,
  handover_notes: item.handover_notes || null,
  covering_staff_profile_id: item.covering_staff_profile_id || null,
  covering_staff_display_id: resolveDisplayId(item.covering_staff_profile || {}),
  covering_staff_name: normalizeString(
    `${item.covering_staff_profile?.user?.profile?.first_name || ''} ${item.covering_staff_profile?.user?.profile?.last_name || ''}`
  ) || item.covering_staff_profile?.user?.email || null,
  timeline_at: item.updated_at || item.created_at,
  target_path: buildWorkbenchPath({
    panel: 'staffing',
    resource: 'staff-leaves',
    id: resolveDisplayId(item),
    action: 'view',
    staffProfileId: resolveDisplayId(item.staff_profile || {}),
  }),
});

const mapSwap = (item) => ({
  id: resolveDisplayId(item),
  queue: 'SWAP_REQUESTS',
  display_id: resolveDisplayId(item),
  backend_identifier: item.id,
  status: item.status,
  shift_id: item.shift_id,
  shift_display_id: resolveDisplayId(item.shift || {}),
  shift_type: item.shift?.shift_type || null,
  requester_staff_id: item.requester_staff_id,
  requester_staff_display_id: resolveDisplayId(item.requester || {}),
  requester_staff_number: item.requester?.staff_number || null,
  target_staff_id: item.target_staff_id,
  target_staff_display_id: resolveDisplayId(item.target || {}),
  target_staff_number: item.target?.staff_number || null,
  timeline_at: item.updated_at || item.created_at,
  target_path: buildWorkbenchPath({
    panel: 'shifts',
    resource: 'shift-swap-requests',
    id: resolveDisplayId(item),
    action: 'view',
  }),
});

const collectRosterStaffIds = (item = {}) => {
  const ids = new Set();
  const attached = item?.constraints?.attached_staff_ids;
  if (Array.isArray(attached)) {
    for (const id of attached) {
      if (id) ids.add(String(id));
    }
  }
  for (const shift of item.shifts || []) {
    for (const assignment of shift.assignments || []) {
      if (assignment?.staff_profile_id) {
        ids.add(String(assignment.staff_profile_id));
      }
    }
  }
  return ids;
};

const mapRoster = (item) => ({
  id: resolveDisplayId(item),
  queue: 'ROSTER_DRAFTS',
  display_id: resolveDisplayId(item),
  backend_identifier: item.id,
  name: item.name || null,
  roster_name: item.name || null,
  is_recurring: Boolean(item.is_recurring),
  status: item.deleted_at ? 'DELETED' : item.status,
  deleted_at: item.deleted_at || null,
  facility_id: item.facility_id || null,
  facility_display_id: resolveDisplayId(item.facility || {}),
  department_id: item.department_id || null,
  department_display_id: resolveDisplayId(item.department || {}),
  period_start: item.period_start,
  period_end: item.period_end,
  period_label: formatDateRangeLabel(item.period_start, item.period_end),
  assignment_count: item.deleted_at
    ? Array.isArray(item.constraints?.attached_staff_ids)
      ? item.constraints.attached_staff_ids.length
      : collectRosterStaffIds(item).size
    : collectRosterStaffIds(item).size,
  roster_staff_ids: [...collectRosterStaffIds(item)],
  constraints: item.constraints || null,
  timeline_at: item.updated_at || item.created_at,
  target_path: buildWorkbenchPath({
    panel: 'roster',
    resource: 'rosters',
    id: resolveDisplayId(item),
    action: 'view',
    rosterId: resolveDisplayId(item),
  }),
});

const mapShift = (item, queue = 'UNASSIGNED_SHIFTS') => ({
  id: resolveDisplayId(item),
  queue,
  display_id: resolveDisplayId(item),
  backend_identifier: item.id,
  status: item.status,
  shift_type: item.shift_type,
  facility_id: item.facility_id || null,
  facility_display_id: resolveDisplayId(item.facility || {}),
  roster_id: item.roster_id || null,
  roster_display_id: resolveDisplayId(item.roster || {}),
  shift_template_id: item.shift_template_id || null,
  shift_template_display_id: resolveDisplayId(item.shift_template || {}),
  assignment_count: Array.isArray(item.assignments) ? item.assignments.length : 0,
  start_time: item.start_time,
  end_time: item.end_time,
  timeline_at: item.updated_at || item.created_at,
  target_path: buildWorkbenchPath({
    panel: 'shifts',
    resource: 'shifts',
    id: resolveDisplayId(item),
    action: 'view',
    queue,
    rosterId: resolveDisplayId(item.roster || {}),
  }),
});

const mapPayroll = (item) => {
  const preview = item.preview_json && typeof item.preview_json === 'object'
    ? item.preview_json
    : {};
  const totals = preview.totals && typeof preview.totals === 'object'
    ? preview.totals
    : {};
  const items = Array.isArray(item.items) ? item.items : [];
  const itemCount = Number(
    totals.staff_count ??
      item._count?.items ??
      items.length ??
      0
  );
  let totalAmount = Number(totals.total_amount);
  if (!Number.isFinite(totalAmount)) {
    totalAmount = items.reduce(
      (sum, entry) => sum + Number(entry?.amount || 0),
      0
    );
  }
  const currency =
    normalizeString(totals.currency) ||
    normalizeString(items.find((entry) => entry?.currency)?.currency) ||
    null;

  return {
    id: resolveDisplayId(item),
    queue: 'PAYROLL_DRAFTS',
    display_id: resolveDisplayId(item),
    backend_identifier: item.id,
    status: item.status,
    period_start: item.period_start,
    period_end: item.period_end,
    period_label: formatDateRangeLabel(item.period_start, item.period_end),
    start_date: item.period_start,
    end_date: item.period_end,
    staff_count: itemCount,
    total_amount: Number.isFinite(totalAmount)
      ? Number(totalAmount.toFixed(2))
      : 0,
    currency,
    payment_lane: 'HR_TO_FINANCE',
    timeline_at: item.updated_at || item.created_at,
    target_path: buildWorkbenchPath({
      panel: 'payroll',
      resource: 'payroll-runs',
      id: resolveDisplayId(item),
      action: 'view',
      payrollRunId: resolveDisplayId(item),
    }),
  };
};

const buildLeaveSearchWhere = (search) => {
  if (!hasText(search)) return {};
  const term = String(search).trim();
  const status = term.toUpperCase();
  return {
    OR: [
      { human_friendly_id: { contains: term } },
      { reason: { contains: term } },
      ...(
        ['REQUESTED', 'APPROVED', 'REJECTED', 'CANCELLED'].includes(status)
          ? [{ status }]
          : []
      ),
      { staff_profile: { human_friendly_id: { contains: term } } },
      { staff_profile: { staff_number: { contains: term } } },
      { staff_profile: { user: { profile: { first_name: { contains: term } } } } },
      { staff_profile: { user: { profile: { last_name: { contains: term } } } } },
      { staff_profile: { user: { email: { contains: term } } } },
    ],
  };
};

const buildSwapSearchWhere = (search) => {
  if (!hasText(search)) return {};
  const term = String(search).trim();
  const status = term.toUpperCase();
  return {
    OR: [
      { human_friendly_id: { contains: term } },
      ...(
        ['SCHEDULED', 'COMPLETED', 'CANCELLED'].includes(status)
          ? [{ status }]
          : []
      ),
      { shift: { human_friendly_id: { contains: term } } },
      { requester: { human_friendly_id: { contains: term } } },
      { requester: { staff_number: { contains: term } } },
      { target: { human_friendly_id: { contains: term } } },
      { target: { staff_number: { contains: term } } },
    ],
  };
};

const buildRosterSearchWhere = (search) => {
  if (!hasText(search)) return {};
  // MySQL Prisma does not support `mode: 'insensitive'`; collation handles case.
  // `status` is a RosterStatus enum — use equality, not `contains`.
  const term = String(search).trim();
  const status = term.toUpperCase();
  return {
    OR: [
      { human_friendly_id: { contains: term } },
      { name: { contains: term } },
      ...(['DRAFT', 'PUBLISHED'].includes(status) ? [{ status }] : []),
    ],
  };
};

const buildPayrollSearchWhere = (search) => {
  if (!hasText(search)) return {};
  const term = String(search).trim();
  const status = term.toUpperCase();
  return {
    OR: [
      { human_friendly_id: { contains: term } },
      ...(
        ['DRAFT', 'PROCESSED', 'PAID', 'CANCELLED'].includes(status)
          ? [{ status }]
          : []
      ),
    ],
  };
};

const buildShiftSearchWhere = (search) => {
  if (!hasText(search)) return {};
  const term = String(search).trim();
  const status = term.toUpperCase();
  const shiftType = term.toUpperCase().replace(/[\s-]+/g, '_');
  return {
    OR: [
      { human_friendly_id: { contains: term } },
      ...(
        ['DAY', 'NIGHT', 'SWING', 'ON_CALL'].includes(shiftType)
          ? [{ shift_type: shiftType }]
          : []
      ),
      ...(
        ['SCHEDULED', 'COMPLETED', 'CANCELLED'].includes(status)
          ? [{ status }]
          : []
      ),
      { roster: { human_friendly_id: { contains: term } } },
      { shift_template: { human_friendly_id: { contains: term } } },
    ],
  };
};

const buildScope = async (filters = {}) => {
  const facilityId = await resolveIdentifierForFilter({
    value: filters.facility_id,
    model: 'facility',
    where: { deleted_at: null },
  });
  const departmentId = await resolveIdentifierForFilter({
    value: filters.department_id,
    model: 'department',
    where: { deleted_at: null },
  });
  const staffProfileId = await resolveIdentifierForFilter({
    value: filters.staff_profile_id,
    model: 'staff_profile',
    where: { deleted_at: null },
  });
  const rosterId = await resolveIdentifierForFilter({
    value: filters.roster_id,
    model: 'roster',
    where: { deleted_at: null },
  });
  const payrollRunId = await resolveIdentifierForFilter({
    value: filters.payroll_run_id,
    model: 'payroll_run',
    where: { deleted_at: null },
  });

  return {
    panel: normalizeString(filters.panel).toLowerCase() || null,
    resource: normalizeString(filters.resource).toLowerCase() || null,
    queue: normalizeString(filters.queue).toUpperCase() || null,
    status: normalizeString(filters.status).toUpperCase() || null,
    facilityId,
    departmentId,
    staffProfileId,
    rosterId,
    payrollRunId,
    from: normalizeDate(filters.date_from || filters.from),
    to: normalizeDate(filters.date_to || filters.to),
    search: normalizeString(filters.search) || null,
  };
};

const resolveRoleRecipients = async ({ tenantId, facilityId = null }) => {
  if (!tenantId || !prisma?.user_role?.findMany) return [];

  const rows = await prisma.user_role.findMany({
    where: {
      deleted_at: null,
      tenant_id: tenantId,
      role: {
        deleted_at: null,
        name: { in: HR_RECIPIENT_ROLES },
      },
      ...(facilityId ? { OR: [{ facility_id: null }, { facility_id: facilityId }] } : {}),
    },
    select: {
      user_id: true,
    },
  });

  return rows.map((row) => row.user_id).filter(Boolean);
};

const publishHrWorkspaceUpdate = async ({
  action,
  actorUserId = null,
  tenantId = null,
  facilityId = null,
  panel = DEFAULT_PANEL,
  resource = DEFAULT_RESOURCE,
  displayId = null,
  queue = null,
  targetPath = null,
  extra = {},
}) => {
  try {
    if (!tenantId) return;

    const recipientUserIds = await resolveRoleRecipients({ tenantId, facilityId });
    const recipients = recipientUserIds.filter((userId) => userId && userId !== actorUserId);
    if (!recipients.length) return;

    emitToUsers(recipients, HR_EVENTS.HR_WORKSPACE_UPDATED, {
      action: normalizeString(action).toUpperCase() || 'UPDATED',
      panel: panel || DEFAULT_PANEL,
      resource: resource || DEFAULT_RESOURCE,
      id: displayId || null,
      queue: queue || null,
      occurred_at: new Date().toISOString(),
      target_path: targetPath || buildWorkbenchPath({
        panel: panel || DEFAULT_PANEL,
        resource: resource || DEFAULT_RESOURCE,
        ...(displayId ? { id: displayId } : {}),
        ...(queue ? { queue } : {}),
      }),
      ...extra,
    });
  } catch (_error) {
    // realtime delivery must never block a successful mutation
  }
};

const getWorkspace = async (filters = {}, page = 1, limit = 20) => {
  const scope = await buildScope(filters);
  const now = new Date();
  const timelineLimit = Math.max(10, Math.min(limit, 40));

  const [
    totalStaff,
    leaveRequests,
    swapRequests,
    draftRosters,
    draftPayroll,
    unassignedShifts,
    overdueShifts,
    leaves,
    swaps,
    rosters,
    payrollRuns,
    shifts,
  ] = await Promise.all([
    repo.countStaffProfiles({
      ...(scope.departmentId ? { department_id: scope.departmentId } : {}),
    }),
    repo.countStaffLeaves({
      status: 'REQUESTED',
      ...(scope.staffProfileId ? { staff_profile_id: scope.staffProfileId } : {}),
      ...(scope.departmentId ? { staff_profile: { department_id: scope.departmentId } } : {}),
    }),
    repo.countShiftSwaps({
      status: 'SCHEDULED',
      shift: {
        deleted_at: null,
        ...(scope.facilityId ? { facility_id: scope.facilityId } : {}),
      },
    }),
    repo.countRosters({
      ...(scope.facilityId ? { facility_id: scope.facilityId } : {}),
      ...(scope.departmentId ? { department_id: scope.departmentId } : {}),
    }),
    repo.countPayrollRuns({ status: { in: ['DRAFT', 'PROCESSED'] } }),
    repo.countShifts({
      ...(scope.facilityId ? { facility_id: scope.facilityId } : {}),
      assignments: { none: { deleted_at: null } },
    }),
    repo.countShifts({
      ...(scope.facilityId ? { facility_id: scope.facilityId } : {}),
      start_time: { lt: now },
      status: { in: ['SCHEDULED'] },
    }),
    repo.findTimelineLeaves(
      {
        ...(scope.staffProfileId ? { staff_profile_id: scope.staffProfileId } : {}),
        ...(scope.departmentId ? { staff_profile: { department_id: scope.departmentId } } : {}),
      },
      timelineLimit
    ),
    repo.findTimelineSwaps(
      {
        shift: {
          deleted_at: null,
          ...(scope.facilityId ? { facility_id: scope.facilityId } : {}),
        },
      },
      timelineLimit
    ),
    repo.findTimelineRosters(
      {
        ...(scope.facilityId ? { facility_id: scope.facilityId } : {}),
        ...(scope.departmentId ? { department_id: scope.departmentId } : {}),
      },
      timelineLimit
    ),
    repo.findTimelinePayrollRuns({}, timelineLimit),
    repo.findTimelineShifts(
      {
        ...(scope.facilityId ? { facility_id: scope.facilityId } : {}),
      },
      timelineLimit
    ),
  ]);

  const summary = {
    total_staff: totalStaff,
    leave_requests: leaveRequests,
    swap_requests: swapRequests,
    draft_rosters: draftRosters,
    unassigned_shifts: unassignedShifts,
    payroll_draft_runs: draftPayroll,
    overdue_shifts: overdueShifts,
  };

  const queueSummaries = QUEUE_DEFINITIONS.map((definition) =>
    buildQueueMeta(
      definition.id,
      definition.id === 'LEAVE_REQUESTS'
        ? leaveRequests
        : definition.id === 'SWAP_REQUESTS'
          ? swapRequests
          : definition.id === 'ROSTER_DRAFTS'
            ? draftRosters
            : definition.id === 'UNASSIGNED_SHIFTS'
              ? unassignedShifts
              : definition.id === 'PAYROLL_DRAFTS'
                ? draftPayroll
                : overdueShifts
    )
  );

  const timelineItems = [
    ...leaves.map((item) => ({
      type: 'LEAVE',
      action: item.status === 'REQUESTED' ? 'REQUESTED' : 'UPDATED',
      status: item.status,
      display_id: resolveDisplayId(item),
      backend_identifier: item.id,
      timeline_at: item.updated_at || item.created_at,
      target_path: buildWorkbenchPath({
        panel: 'staffing',
        resource: 'staff-leaves',
        id: resolveDisplayId(item),
        action: 'view',
      }),
    })),
    ...swaps.map((item) => ({
      type: 'SWAP',
      action: item.status === 'COMPLETED' ? 'APPROVED' : 'UPDATED',
      status: item.status,
      display_id: resolveDisplayId(item),
      backend_identifier: item.id,
      timeline_at: item.updated_at || item.created_at,
      target_path: buildWorkbenchPath({
        panel: 'shifts',
        resource: 'shift-swap-requests',
        id: resolveDisplayId(item),
        action: 'view',
      }),
    })),
    ...rosters.map((item) => ({
      type: 'ROSTER',
      action: item.status === 'PUBLISHED' ? 'PUBLISHED' : 'UPDATED',
      status: item.status,
      display_id: resolveDisplayId(item),
      backend_identifier: item.id,
      timeline_at: item.updated_at || item.created_at,
      target_path: buildWorkbenchPath({
        panel: 'roster',
        resource: 'rosters',
        id: resolveDisplayId(item),
        action: 'view',
        rosterId: resolveDisplayId(item),
      }),
    })),
    ...payrollRuns.map((item) => ({
      type: 'PAYROLL',
      action: item.status === 'PROCESSED' ? 'PROCESSED' : 'UPDATED',
      status: item.status,
      display_id: resolveDisplayId(item),
      backend_identifier: item.id,
      timeline_at: item.updated_at || item.created_at,
      target_path: buildWorkbenchPath({
        panel: 'payroll',
        resource: 'payroll-runs',
        id: resolveDisplayId(item),
        action: 'view',
        payrollRunId: resolveDisplayId(item),
      }),
    })),
    ...shifts.map((item) => ({
      type: 'SHIFT',
      action: 'UPDATED',
      status: item.status,
      display_id: resolveDisplayId(item),
      backend_identifier: item.id,
      timeline_at: item.updated_at || item.created_at,
      target_path: buildWorkbenchPath({
        panel: 'shifts',
        resource: 'shifts',
        id: resolveDisplayId(item),
        action: 'view',
      }),
    })),
  ]
    .filter((item) => item.timeline_at)
    .sort((left, right) => new Date(right.timeline_at).getTime() - new Date(left.timeline_at).getTime())
    .slice(0, timelineLimit);

  const requestedPanel =
    WORKBENCH_PANELS.find((panel) => panel.id === scope.panel)?.id || DEFAULT_PANEL;
  const requestedResource =
    (scope.resource && RESOURCE_PANEL_MAP[scope.resource] ? scope.resource : null) ||
    WORKBENCH_PANELS.find((panel) => panel.id === requestedPanel)?.default_resource ||
    DEFAULT_RESOURCE;

  return {
    summary,
    panel_summaries: buildPanelSummaries(summary),
    queues: queueSummaries,
    queue_summaries: queueSummaries,
    spotlight_items: buildWorkspaceSpotlight(summary),
    defaults: {
      panel: requestedPanel,
      resource: requestedResource,
      queue: scope.queue || null,
    },
    panels: WORKBENCH_PANELS.map((panel) => ({
      id: panel.id,
      label_key: panel.label_key,
      default_resource: panel.default_resource,
      resources: panel.resources,
      visible: panel.visible !== false,
    })),
    timeline: {
      items: timelineItems,
      pagination: buildPagination(page, timelineLimit, timelineItems.length),
    },
    generated_at: new Date().toISOString(),
  };
};

const listQueueItems = async ({ queue, scope, skip, take, orderBy }) => {
  if (queue === 'LEAVE_REQUESTS') {
    const whereClause = {
      status: scope.status || 'REQUESTED',
      ...(scope.staffProfileId ? { staff_profile_id: scope.staffProfileId } : {}),
      ...(scope.departmentId ? { staff_profile: { department_id: scope.departmentId } } : {}),
      ...(scope.from || scope.to
        ? {
            start_date: {
              ...(scope.from ? { gte: scope.from } : {}),
              ...(scope.to ? { lte: scope.to } : {}),
            },
          }
        : {}),
      ...buildLeaveSearchWhere(scope.search),
    };
    const items = await repo.findManyLeaves({ where: whereClause, skip, take, orderBy });
    const total = await repo.countStaffLeaves(whereClause);
    return { items: items.map(mapLeave), total };
  }

  if (queue === 'SWAP_REQUESTS') {
    const whereClause = {
      status: scope.status || 'SCHEDULED',
      shift: {
        deleted_at: null,
        ...(scope.facilityId ? { facility_id: scope.facilityId } : {}),
        ...(scope.rosterId ? { roster_id: scope.rosterId } : {}),
      },
      ...buildSwapSearchWhere(scope.search),
    };
    const items = await repo.findManyShiftSwaps({ where: whereClause, skip, take, orderBy });
    const total = await repo.countShiftSwaps(whereClause);
    return { items: items.map(mapSwap), total };
  }

  if (queue === 'ROSTER_DRAFTS') {
    const status = String(scope.status || '').trim().toUpperCase();
    const deletedOnly = status === 'DELETED';
    const whereClause = {
      ...(deletedOnly
        ? { deleted_at: { not: null } }
        : {
            deleted_at: null,
            ...(status ? { status } : {}),
          }),
      ...(scope.facilityId ? { facility_id: scope.facilityId } : {}),
      ...(scope.departmentId ? { department_id: scope.departmentId } : {}),
      ...(scope.rosterId ? { id: scope.rosterId } : {}),
      ...buildRosterSearchWhere(scope.search),
    };
    const items = await repo.findManyRosters({ where: whereClause, skip, take, orderBy });
    const total = await repo.countRosters(whereClause);
    return { items: items.map(mapRoster), total };
  }

  if (queue === 'PAYROLL_DRAFTS') {
    const normalizedStatus = String(scope.status || '').trim().toUpperCase();
    let statusClause;
    if (!normalizedStatus || normalizedStatus === 'OUTSTANDING') {
      statusClause = { in: ['DRAFT', 'PROCESSED'] };
    } else if (normalizedStatus === 'PENDING' || normalizedStatus === 'PENDING_REVIEW') {
      statusClause = 'DRAFT';
    } else if (normalizedStatus === 'APPROVED') {
      statusClause = 'PROCESSED';
    } else {
      statusClause = normalizedStatus;
    }

    const whereClause = {
      status: statusClause,
      ...(scope.payrollRunId ? { id: scope.payrollRunId } : {}),
      ...(scope.from || scope.to
        ? {
            AND: [
              ...(scope.from
                ? [{ period_start: { gte: scope.from } }]
                : []),
              ...(scope.to ? [{ period_end: { lte: scope.to } }] : []),
            ],
          }
        : {}),
      ...buildPayrollSearchWhere(scope.search),
    };
    const items = await repo.findManyPayrollRuns({ where: whereClause, skip, take, orderBy });
    const total = await repo.countPayrollRuns(whereClause);
    return { items: items.map(mapPayroll), total };
  }

  if (queue === 'OVERDUE_SHIFTS') {
    const whereClause = {
      ...(scope.facilityId ? { facility_id: scope.facilityId } : {}),
      ...(scope.rosterId ? { roster_id: scope.rosterId } : {}),
      start_time: { lt: new Date() },
      status: scope.status ? { equals: scope.status } : { in: ['SCHEDULED'] },
      ...buildShiftSearchWhere(scope.search),
    };
    const items = await repo.findManyOverdueShifts({ where: whereClause, skip, take, orderBy });
    const total = await repo.countShifts(whereClause);
    return { items: items.map((item) => mapShift(item, 'OVERDUE_SHIFTS')), total };
  }

  const whereClause = {
    ...(scope.facilityId ? { facility_id: scope.facilityId } : {}),
    ...(scope.departmentId ? { roster: { department_id: scope.departmentId } } : {}),
    ...(scope.rosterId ? { roster_id: scope.rosterId } : {}),
    ...(scope.from || scope.to
      ? {
          start_time: {
            ...(scope.from ? { gte: scope.from } : {}),
            ...(scope.to ? { lte: scope.to } : {}),
          },
        }
      : {}),
    ...(scope.status ? { status: scope.status } : {}),
    ...buildShiftSearchWhere(scope.search),
  };

  const items = await repo.findManyUnassignedShifts({ where: whereClause, skip, take, orderBy });
  const total = await repo.countShifts({
    ...whereClause,
    assignments: { none: { deleted_at: null } },
  });
  return { items: items.map((item) => mapShift(item, 'UNASSIGNED_SHIFTS')), total };
};

const getWorkItems = async (filters = {}, page = 1, limit = 20, sortBy = 'updated_at', order = 'desc') => {
  const scope = await buildScope(filters);
  const skip = (page - 1) * limit;
  const safeOrder = normalizeOrder(order);
  const queue = scope.queue || null;

  const queueOrderBy =
    queue === 'ROSTER_DRAFTS' || queue === 'PAYROLL_DRAFTS'
      ? { created_at: safeOrder }
      : queue === 'UNASSIGNED_SHIFTS' || queue === 'OVERDUE_SHIFTS'
        ? { start_time: safeOrder }
        : { updated_at: safeOrder };

  if (queue) {
    const { items, total } = await listQueueItems({
      queue,
      scope,
      skip,
      take: limit,
      orderBy: queueOrderBy,
    });
    return {
      panel: scope.panel || RESOURCE_PANEL_MAP[scope.resource] || null,
      resource: scope.resource || QUEUE_DEFINITIONS.find((entry) => entry.id === queue)?.resource || null,
      queue,
      items,
      pagination: buildPagination(page, limit, total),
      sort_by: normalizeString(sortBy) || null,
      order: safeOrder,
    };
  }

  const grouped = [];

  for (const currentQueue of QUEUE_DEFINITIONS.map((entry) => entry.id)) {
    const { items, total } = await listQueueItems({
      queue: currentQueue,
      scope,
      skip: 0,
      take: Math.min(limit, 8),
      orderBy:
        currentQueue === 'ROSTER_DRAFTS' || currentQueue === 'PAYROLL_DRAFTS'
          ? { created_at: safeOrder }
          : currentQueue === 'UNASSIGNED_SHIFTS' || currentQueue === 'OVERDUE_SHIFTS'
            ? { start_time: safeOrder }
            : { updated_at: safeOrder },
    });
    grouped.push({
      queue: currentQueue,
      total,
      items,
      target_path: buildWorkbenchPath({
        panel: QUEUE_DEFINITIONS.find((entry) => entry.id === currentQueue)?.panel,
        resource: QUEUE_DEFINITIONS.find((entry) => entry.id === currentQueue)?.resource,
        queue: currentQueue,
      }),
    });
  }

  return {
    panel: scope.panel || null,
    resource: scope.resource || null,
    queues: grouped,
  };
};

const getReferenceData = async (filters = {}) => {
  const scope = await buildScope(filters);
  await ensureDefaultStaffPositions(scope);
  await ensureDefaultFacilityStructure(scope);
  const tenantId = await resolveTenantIdForScope(scope);
  const staffPositionWhere = tenantId
    ? {
        deleted_at: null,
        tenant_id: tenantId,
        ...(scope.facilityId
          ? {
              OR: [{ facility_id: scope.facilityId }, { facility_id: null }],
            }
          : {}),
      }
    : {
        deleted_at: null,
        ...(scope.facilityId ? { facility_id: scope.facilityId } : {}),
      };

  const [facilities, departments, units, rooms, staffProfiles, staffPositions, rosters, payrollRuns, shiftTemplates, shifts, roles, users] =
    await Promise.all([
      prisma.facility.findMany({
        where: {
          deleted_at: null,
          ...(scope.facilityId ? { id: scope.facilityId } : {}),
        },
        orderBy: { name: 'asc' },
        take: 200,
        select: { id: true, human_friendly_id: true, name: true, facility_type: true },
      }),
      prisma.department.findMany({
        where: {
          deleted_at: null,
          ...(scope.facilityId ? { facility_id: scope.facilityId } : {}),
          ...(scope.departmentId ? { id: scope.departmentId } : {}),
        },
        orderBy: { name: 'asc' },
        take: 500,
        select: { id: true, human_friendly_id: true, name: true, short_name: true, facility_id: true },
      }),
      prisma.unit.findMany({
        where: {
          deleted_at: null,
          ...(scope.facilityId ? { facility_id: scope.facilityId } : {}),
          ...(scope.departmentId ? { department_id: scope.departmentId } : {}),
        },
        orderBy: { name: 'asc' },
        take: 500,
        select: { id: true, human_friendly_id: true, name: true, facility_id: true, department_id: true },
      }),
      prisma.room.findMany({
        where: {
          deleted_at: null,
          ...(scope.facilityId ? { facility_id: scope.facilityId } : {}),
          ...(scope.departmentId ? { ward: { department_id: scope.departmentId } } : {}),
        },
        orderBy: { name: 'asc' },
        take: 500,
        select: {
          id: true,
          human_friendly_id: true,
          name: true,
          facility_id: true,
          ward: { select: { department_id: true } },
        },
      }),
      prisma.staff_profile.findMany({
        where: {
          deleted_at: null,
          ...(scope.departmentId ? { department_id: scope.departmentId } : {}),
          ...(scope.staffProfileId ? { id: scope.staffProfileId } : {}),
        },
        orderBy: { created_at: 'desc' },
        take: 200,
        select: {
          id: true,
          human_friendly_id: true,
          staff_number: true,
          position: true,
          practitioner_type: true,
          department_id: true,
          user: {
            select: {
              email: true,
              profile: {
                select: {
                  first_name: true,
                  last_name: true,
                },
              },
            },
          },
        },
      }),
      prisma.staff_position.findMany({
        where: staffPositionWhere,
        orderBy: { name: 'asc' },
        take: 200,
        select: {
          id: true,
          human_friendly_id: true,
          name: true,
          department_id: true,
          is_active: true,
        },
      }),
      prisma.roster.findMany({
        where: {
          deleted_at: null,
          ...(scope.facilityId ? { facility_id: scope.facilityId } : {}),
          ...(scope.departmentId ? { department_id: scope.departmentId } : {}),
          ...(scope.rosterId ? { id: scope.rosterId } : {}),
        },
        orderBy: { period_start: 'desc' },
        take: 200,
        select: {
          id: true,
          human_friendly_id: true,
          facility_id: true,
          department_id: true,
          period_start: true,
          period_end: true,
          status: true,
        },
      }),
      prisma.payroll_run.findMany({
        where: {
          deleted_at: null,
          ...(scope.payrollRunId ? { id: scope.payrollRunId } : {}),
        },
        orderBy: { period_start: 'desc' },
        take: 200,
        select: {
          id: true,
          human_friendly_id: true,
          period_start: true,
          period_end: true,
          status: true,
        },
      }),
      prisma.shift_template.findMany({
        where: {
          deleted_at: null,
          ...(scope.facilityId ? { facility_id: scope.facilityId } : {}),
        },
        orderBy: { name: 'asc' },
        take: 200,
        select: {
          id: true,
          human_friendly_id: true,
          name: true,
          shift_type: true,
          facility_id: true,
          default_start_time: true,
          default_end_time: true,
          weekly_schedule_json: true,
          is_active: true,
          created_at: true,
          updated_at: true,
        },
      }),
      prisma.shift.findMany({
        where: {
          deleted_at: null,
          status: 'SCHEDULED',
          ...(scope.facilityId ? { facility_id: scope.facilityId } : {}),
          ...(scope.departmentId
            ? { roster: { department_id: scope.departmentId } }
            : {}),
        },
        orderBy: { start_time: 'desc' },
        take: 200,
        select: {
          id: true,
          human_friendly_id: true,
          shift_type: true,
          status: true,
          start_time: true,
          end_time: true,
          facility_id: true,
          shift_template: {
            select: {
              id: true,
              human_friendly_id: true,
              name: true,
            },
          },
          roster: {
            select: {
              id: true,
              human_friendly_id: true,
              department: {
                select: {
                  id: true,
                  human_friendly_id: true,
                  name: true,
                  short_name: true,
                },
              },
            },
          },
        },
      }),
      prisma.role.findMany({
        where: {
          deleted_at: null,
          name: { in: [...HR_ASSIGNABLE_ROLE_NAMES] },
          // Assignable defaults are the platform catalog; tenants keep no copies.
          tenant_id: null,
          facility_id: null,
        },
        orderBy: { name: 'asc' },
        take: 200,
        select: {
          id: true,
          human_friendly_id: true,
          name: true,
          permissions: {
            where: { deleted_at: null },
            select: { permission_id: true },
          },
        },
      }),
      prisma.user.findMany({
        where: {
          deleted_at: null,
          status: 'ACTIVE',
          ...(scope.facilityId ? { facility_id: scope.facilityId } : {}),
          roles: {
            none: {
              deleted_at: null,
              role: { deleted_at: null, name: ROLES.PATIENT },
            },
          },
        },
        orderBy: { email: 'asc' },
        take: 200,
        select: {
          id: true,
          human_friendly_id: true,
          email: true,
          position_title: true,
          profile: {
            select: {
              first_name: true,
              last_name: true,
            },
          },
          staff_profile: {
            where: { deleted_at: null },
            select: { id: true, human_friendly_id: true },
          },
          roles: {
            where: { deleted_at: null },
            take: 3,
            select: {
              role: { select: { name: true } },
            },
          },
        },
      }),
    ]);

  const toOption = (value, label, extra = {}) => {
    const publicId = resolvePublicIdentifier(value?.human_friendly_id, value?.display_id);
    const optionValue = publicId || (value?.id ? String(value.id) : null);
    if (!optionValue) return null;
    return {
      value: optionValue,
      label,
      display_id: publicId || null,
      ...extra,
    };
  };

  return {
    facilities: facilities
      .map((entry) =>
        toOption(entry, normalizeString(entry.name) || resolvePublicIdentifier(entry.human_friendly_id), {
          facility_type: entry.facility_type || null,
        })
      )
      .filter(Boolean),
    departments: departments
      .map((entry) =>
        toOption(entry, normalizeString(entry.name || entry.short_name) || resolvePublicIdentifier(entry.human_friendly_id), {
          entity_id: entry.id || null,
          facility_id: entry.facility_id || null,
        })
      )
      .filter(Boolean),
    units: units
      .map((entry) =>
        toOption(entry, normalizeString(entry.name) || resolvePublicIdentifier(entry.human_friendly_id), {
          facility_id: entry.facility_id || null,
          department_id: entry.department_id || null,
        })
      )
      .filter(Boolean),
    rooms: rooms
      .map((entry) =>
        toOption(entry, normalizeString(entry.name) || resolvePublicIdentifier(entry.human_friendly_id), {
          facility_id: entry.facility_id || null,
          department_id: entry.ward?.department_id || null,
        })
      )
      .filter(Boolean),
    staff_profiles: staffProfiles
      .map((entry) => {
        const displayId = resolvePublicIdentifier(entry.human_friendly_id);
        if (!displayId) return null;
        const firstName = entry.user?.profile?.first_name || '';
        const lastName = entry.user?.profile?.last_name || '';
        const staffName = normalizeString(
          `${firstName} ${lastName}`
        ) || entry.user?.email || displayId;
        const label = [entry.staff_number || displayId, staffName, entry.position || entry.practitioner_type || null]
          .filter(Boolean)
          .join(' | ');
        return {
          value: displayId,
          label,
          display_id: displayId,
          department_id: entry.department_id || null,
          practitioner_type: entry.practitioner_type || null,
        };
      })
      .filter(Boolean),
    staff_positions: (() => {
      const mapped = staffPositions
        .map((entry) => enrichStaffPositionOption(entry))
        .filter(Boolean);
      return mapped.length > 0 ? mapped : staffPositionCatalogOptions();
    })(),
    rosters: rosters
      .map((entry) =>
        toOption(entry, [resolvePublicIdentifier(entry.human_friendly_id), formatDateRangeLabel(entry.period_start, entry.period_end), entry.status].filter(Boolean).join(' | '), {
          facility_id: entry.facility_id || null,
          department_id: entry.department_id || null,
          status: entry.status || null,
        })
      )
      .filter(Boolean),
    payroll_runs: payrollRuns
      .map((entry) =>
        toOption(entry, [resolvePublicIdentifier(entry.human_friendly_id), formatDateRangeLabel(entry.period_start, entry.period_end), entry.status].filter(Boolean).join(' | '), {
          status: entry.status || null,
        })
      )
      .filter(Boolean),
    shift_templates: shiftTemplates
      .map((entry) =>
        toOption(entry, normalizeString(entry.name) || resolvePublicIdentifier(entry.human_friendly_id), {
          shift_type: entry.shift_type || null,
          facility_id: entry.facility_id || null,
          default_start_time: entry.default_start_time || null,
          default_end_time: entry.default_end_time || null,
          weekly_schedule_json: entry.weekly_schedule_json || null,
          is_active: Boolean(entry.is_active),
          created_at: entry.created_at || null,
          updated_at: entry.updated_at || null,
        })
      )
      .filter(Boolean),
    shifts: shifts
      .map((entry) =>
        toOption(entry, formatShiftOptionLabel(entry), {
          shift_type: entry.shift_type || null,
          status: entry.status || null,
          start_time: entry.start_time || null,
          end_time: entry.end_time || null,
          facility_id: entry.facility_id || null,
          department_id: entry.roster?.department?.id || null,
          department_name:
            normalizeString(entry.roster?.department?.name || entry.roster?.department?.short_name) ||
            null,
          shift_template_name: normalizeString(entry.shift_template?.name) || null,
        })
      )
      .filter(Boolean),
    roles: sortRoleRecords(roles)
      .map((entry) => {
        const roleName = normalizeString(entry.name).toUpperCase();
        const enriched = enrichRoleOption(
          {
            ...entry,
            is_system_critical: SYSTEM_CRITICAL_ROLES.has(roleName),
          }
        );
        if (!enriched) return null;
        return {
          value: enriched.value,
          label: enriched.label,
          label_key: enriched.label_key,
          display_id: enriched.display_id,
          name: enriched.name,
          category: enriched.category,
          permission_count: enriched.permission_count,
          is_system_critical: enriched.is_system_critical,
        };
      })
      .filter(Boolean),
    users: users
      .map((entry) => {
        const displayId = resolvePublicIdentifier(entry.human_friendly_id);
        if (!displayId) return null;
        const firstName = entry.profile?.first_name || '';
        const lastName = entry.profile?.last_name || '';
        const fullName = normalizeString(`${firstName} ${lastName}`);
        const roleHint = (entry.roles || [])
          .map((assignment) => assignment?.role?.name)
          .filter(Boolean)
          .join(', ');
        const label = [fullName || entry.email, entry.email, roleHint || entry.position_title]
          .filter(Boolean)
          .join(' · ');
        return {
          value: displayId,
          label,
          display_id: displayId,
          email: entry.email || null,
          position_title: entry.position_title || null,
          role_hint: roleHint || null,
          has_staff_profile: Boolean(entry.staff_profile),
          staff_profile_id: resolvePublicIdentifier(entry.staff_profile?.human_friendly_id),
        };
      })
      .filter(Boolean),
    shift_types: SHIFT_TYPE_OPTIONS.map((value) => ({ value, label: value })),
    leave_types: leaveTypeOptions(),
    leave_half_day_periods: leaveHalfDayPeriodOptions(),
    practitioner_types: practitionerTypeOptions(),
    compensation_pay_types: compensationPayTypeOptions(),
    resource_statuses: Object.fromEntries(
      Object.entries(RESOURCE_STATUS_ENUMS).map(([resource, values]) => [
        resource,
        values.map((value) => ({ value, label: value })),
      ])
    ),
  };
};

const resolveTenantIdForScope = async (scope) => {
  if (!scope.facilityId) {
    return null;
  }
  const facility = await prisma.facility.findFirst({
    where: { id: scope.facilityId, deleted_at: null },
    select: { tenant_id: true },
  });
  return facility?.tenant_id || null;
};

const buildStaffPositionCatalogWhere = (scope, tenantId) => ({
  deleted_at: null,
  tenant_id: tenantId,
  department_id: null,
  ...(scope.facilityId
    ? {
        OR: [{ facility_id: scope.facilityId }, { facility_id: null }],
      }
    : { facility_id: null }),
});

const ensureDefaultStaffPositions = async (scope) => {
  const tenantId = await resolveTenantIdForScope(scope);
  if (!tenantId) {
    return;
  }

  const existingCount = await prisma.staff_position.count({
    where: buildStaffPositionCatalogWhere(scope, tenantId),
  });
  if (existingCount > 0) {
    return;
  }

  await Promise.all(
    DEFAULT_STAFF_POSITION_NAMES.map((name) =>
      prisma.staff_position.create({
        data: {
          tenant_id: tenantId,
          facility_id: null,
          name,
          is_active: true,
        },
      })
    )
  );
};

const ensureDefaultFacilityStructure = async (scope) => {
  const tenantId = await resolveTenantIdForScope(scope);
  if (!tenantId || !scope.facilityId) {
    return;
  }

  const existingCount = await prisma.department.count({
    where: {
      deleted_at: null,
      facility_id: scope.facilityId,
    },
  });
  if (existingCount > 0) {
    return;
  }

  for (const name of DEFAULT_FACILITY_DEPARTMENT_NAMES) {
    const department = await prisma.department.create({
      data: {
        tenant_id: tenantId,
        facility_id: scope.facilityId,
        name,
        short_name: name.slice(0, 8).toUpperCase(),
        department_type: inferDepartmentType(name),
        is_active: true,
      },
    });

    await prisma.unit.create({
      data: {
        tenant_id: tenantId,
        facility_id: scope.facilityId,
        department_id: department.id,
        name: `${name} Unit`,
        is_active: true,
      },
    });
  }
};

const generateStaffNumber = async ({ tenantId = null, facilityId = null } = {}) => {
  const resolvedTenantId = tenantId
    ? await resolveIdentifierForPayload({
        value: tenantId,
        model: 'tenant',
        field: 'tenant_id',
        where: { deleted_at: null },
        nullable: true,
      })
    : null;
  const resolvedFacilityId = facilityId
    ? await resolveIdentifierForFilter({
        value: facilityId,
        model: 'facility',
        where: { deleted_at: null },
      })
    : null;

  return generateStaffNumberCore({
    tenantId: resolvedTenantId,
    facilityId: resolvedFacilityId,
  });
};

const getRosterWorkflow = async (rosterIdentifier) => buildWorkflow(rosterIdentifier);

const generateRosterAssignments = async ({ rosterIdentifier, constraints, replaceExistingAssignments, dryRun, userId, ipAddress }) => {
  const result = await generateRosterAssignmentsCore({
    rosterIdentifier,
    constraints,
    replaceExistingAssignments,
    dryRun,
    userId,
    ipAddress,
  });

  publishHrWorkspaceUpdate({
    action: 'GENERATE',
    actorUserId: userId || null,
    tenantId: result?.roster?.tenant_id || null,
    facilityId: result?.roster?.facility_id || null,
    panel: 'roster',
    resource: 'rosters',
    displayId: result?.roster?.display_id || null,
    targetPath: buildWorkbenchPath({
      panel: 'roster',
      resource: 'rosters',
      id: result?.roster?.display_id || null,
      rosterId: result?.roster?.display_id || null,
      action: 'view',
    }),
    extra: {
      roster_id: result?.roster?.display_id || null,
      dry_run: Boolean(dryRun),
    },
  }).catch(() => {});

  return result;
};

const publishRoster = async (rosterIdentifier, body = {}, userId = null, ipAddress = null) => {
  const notifyStaff = Boolean(body.notify_staff);
  const allowPartial = Boolean(body.allow_partial_publish);
  const publishNote = normalizeString(body.publish_note) || null;

  const workflow = await buildWorkflow(rosterIdentifier);
  const hasGaps = Array.isArray(workflow.gaps) && workflow.gaps.length > 0;

  if (hasGaps && !allowPartial) {
    throw new HttpError('errors.hr_workspace.publish_blocked_unassigned', 400, [
      { reason: 'unassigned_shifts_present', unassigned_count: workflow.gaps.length },
    ]);
  }

  if (hasGaps && allowPartial && !publishNote) {
    throw new HttpError('errors.validation.invalid', 400, [{ field: 'publish_note' }]);
  }

  const roster = await resolveModelRecordByIdentifier({
    model: 'roster',
    identifier: rosterIdentifier,
    where: { deleted_at: null },
    select: {
      id: true,
      tenant_id: true,
      facility_id: true,
      status: true,
      published_at: true,
      human_friendly_id: true,
    },
  });

  if (!roster?.id) {
    throw new HttpError('errors.roster.not_found', 404);
  }

  const updated = await prisma.roster.update({
    where: { id: roster.id },
    data: { status: 'PUBLISHED', published_at: new Date() },
  });

  createAuditLog({
    user_id: userId,
    action: 'UPDATE',
    entity: 'roster',
    entity_id: roster.id,
    tenant_id: roster.tenant_id,
    diff: {
      before: { status: roster.status, published_at: roster.published_at },
      after: { status: updated.status, published_at: updated.published_at },
      metadata: {
        operation: 'PUBLISH_ROSTER',
        notify_staff: notifyStaff,
        allow_partial_publish: allowPartial,
        publish_note: publishNote,
        gaps: workflow.gaps,
      },
    },
    ip_address: ipAddress,
  }).catch(() => {});

  publishHrWorkspaceUpdate({
    action: 'PUBLISH',
    actorUserId: userId || null,
    tenantId: roster.tenant_id,
    facilityId: roster.facility_id || null,
    panel: 'roster',
    resource: 'rosters',
    displayId: resolveDisplayId(updated),
    targetPath: buildWorkbenchPath({
      panel: 'roster',
      resource: 'rosters',
      id: resolveDisplayId(updated),
      rosterId: resolveDisplayId(updated),
      action: 'view',
    }),
  }).catch(() => {});

  return {
    published_roster: {
      id: resolveDisplayId(updated),
      display_id: resolveDisplayId(updated),
      backend_identifier: updated.id,
      status: updated.status,
      published_at: updated.published_at,
    },
    publish_summary: {
      notify_staff: notifyStaff,
      allow_partial_publish: allowPartial,
      has_unassigned_gaps: hasGaps,
      unassigned_gaps: workflow.gaps,
      coverage: workflow.coverage,
    },
  };
};

const overrideShiftAssignment = async (shiftIdentifier, payload = {}, userId = null, ipAddress = null) => {
  const shiftRecord = await resolveRecordOrThrow({
    model: 'shift',
    identifier: shiftIdentifier,
    where: { deleted_at: null },
    errorKey: 'errors.shift.not_found',
  });

  const shiftWithContext = await prisma.shift.findUnique({
    where: { id: shiftRecord.id },
    select: {
      id: true,
      tenant_id: true,
      facility_id: true,
      roster: {
        select: {
          id: true,
          human_friendly_id: true,
        },
      },
      human_friendly_id: true,
    },
  });

  const staffProfileId = await resolveIdentifierForPayload({
    value: payload.staff_profile_id,
    model: 'staff_profile',
    field: 'staff_profile_id',
    where: { deleted_at: null },
  });

  const reason = normalizeString(payload.reason);

  const assignment = await prisma.$transaction(async (tx) => {
    await tx.shift_assignment.updateMany({
      where: { deleted_at: null, shift_id: shiftRecord.id },
      data: { deleted_at: new Date() },
    });

    return tx.shift_assignment.create({
      data: {
        shift_id: shiftRecord.id,
        staff_profile_id: staffProfileId,
        assigned_at: new Date(),
      },
      include: {
        shift: {
          select: {
            id: true,
            human_friendly_id: true,
            shift_type: true,
            status: true,
            start_time: true,
            end_time: true,
          },
        },
        staff_profile: {
          select: {
            id: true,
            human_friendly_id: true,
            staff_number: true,
          },
        },
      },
    });
  });

  const auditRef = `HR-OVR-${Date.now()}`;

  createAuditLog({
    user_id: userId,
    action: 'UPDATE',
    entity: 'shift_assignment',
    entity_id: assignment.id,
    diff: {
      metadata: {
        operation: 'SHIFT_ASSIGNMENT_OVERRIDE',
        reason,
        audit_ref: auditRef,
        shift_id: shiftRecord.id,
        staff_profile_id: staffProfileId,
      },
    },
    ip_address: ipAddress,
  }).catch(() => {});

  publishHrWorkspaceUpdate({
    action: 'OVERRIDE',
    actorUserId: userId || null,
    tenantId: shiftWithContext?.tenant_id || null,
    facilityId: shiftWithContext?.facility_id || null,
    panel: 'shifts',
    resource: 'shifts',
    displayId: resolveDisplayId(assignment.shift || shiftWithContext || {}),
    queue: 'UNASSIGNED_SHIFTS',
    targetPath: buildWorkbenchPath({
      panel: 'shifts',
      resource: 'shifts',
      id: resolveDisplayId(assignment.shift || shiftWithContext || {}),
      action: 'view',
      rosterId: resolveDisplayId(shiftWithContext?.roster || {}),
    }),
  }).catch(() => {});

  return {
    assignment: {
      id: resolveDisplayId(assignment),
      display_id: resolveDisplayId(assignment),
      backend_identifier: assignment.id,
      shift_id: resolveDisplayId(assignment.shift || {}),
      shift_display_id: resolveDisplayId(assignment.shift || {}),
      staff_profile_id: resolveDisplayId(assignment.staff_profile || {}),
      staff_profile_display_id: resolveDisplayId(assignment.staff_profile || {}),
      assigned_at: assignment.assigned_at,
    },
    shift: {
      id: resolveDisplayId(assignment.shift || {}),
      display_id: resolveDisplayId(assignment.shift || {}),
      backend_identifier: assignment.shift?.id || null,
      shift_type: assignment.shift?.shift_type || null,
      status: assignment.shift?.status || null,
      start_time: assignment.shift?.start_time || null,
      end_time: assignment.shift?.end_time || null,
    },
    audit_ref: auditRef,
  };
};

const approveSwap = async (swapIdentifier, payload = {}, userId = null, ipAddress = null) => {
  const swapRecord = await resolveModelRecordByIdentifier({
    model: 'shift_swap_request',
    identifier: swapIdentifier,
    where: { deleted_at: null },
    select: {
      id: true,
      human_friendly_id: true,
      status: true,
      shift_id: true,
      requester_staff_id: true,
      target_staff_id: true,
      shift: {
        select: {
          tenant_id: true,
          facility_id: true,
          human_friendly_id: true,
        },
      },
    },
  });

  if (!swapRecord?.id) {
    throw new HttpError('errors.shift_swap_request.not_found', 404);
  }

  const result = await prisma.$transaction(async (tx) => {
    const updatedSwap = await tx.shift_swap_request.update({
      where: { id: swapRecord.id },
      data: { status: 'COMPLETED' },
    });

    const mutations = [];

    if (swapRecord.target_staff_id) {
      const existing = await tx.shift_assignment.findFirst({
        where: {
          deleted_at: null,
          shift_id: swapRecord.shift_id,
          staff_profile_id: swapRecord.requester_staff_id,
        },
      });

      if (existing) {
        mutations.push(
          await tx.shift_assignment.update({
            where: { id: existing.id },
            data: { staff_profile_id: swapRecord.target_staff_id },
          })
        );
      } else {
        mutations.push(
          await tx.shift_assignment.create({
            data: {
              shift_id: swapRecord.shift_id,
              staff_profile_id: swapRecord.target_staff_id,
              assigned_at: new Date(),
            },
          })
        );
      }
    }

    return { updatedSwap, mutations };
  });

  createAuditLog({
    user_id: userId,
    action: 'UPDATE',
    entity: 'shift_swap_request',
    entity_id: swapRecord.id,
    diff: {
      metadata: {
        operation: 'SWAP_APPROVE',
        reason: normalizeString(payload.reason) || null,
      },
    },
    ip_address: ipAddress,
  }).catch(() => {});

  publishHrWorkspaceUpdate({
    action: 'APPROVE',
    actorUserId: userId || null,
    tenantId: swapRecord.shift?.tenant_id || null,
    facilityId: swapRecord.shift?.facility_id || null,
    panel: 'shifts',
    resource: 'shift-swap-requests',
    displayId: resolveDisplayId(result.updatedSwap),
    queue: 'SWAP_REQUESTS',
    targetPath: buildWorkbenchPath({
      panel: 'shifts',
      resource: 'shift-swap-requests',
      id: resolveDisplayId(result.updatedSwap),
      action: 'view',
    }),
  }).catch(() => {});

  return {
    swap: {
      id: resolveDisplayId(result.updatedSwap),
      display_id: resolveDisplayId(result.updatedSwap),
      backend_identifier: result.updatedSwap.id,
      status: result.updatedSwap.status,
    },
    shift_assignments: result.mutations.map((entry) => ({
      id: resolveDisplayId(entry),
      display_id: resolveDisplayId(entry),
      backend_identifier: entry.id,
      shift_id: entry.shift_id,
      staff_profile_id: entry.staff_profile_id,
      assigned_at: entry.assigned_at,
    })),
  };
};

const rejectSwap = async (swapIdentifier, payload = {}, userId = null, ipAddress = null) => {
  const swapRecord = await resolveModelRecordByIdentifier({
    model: 'shift_swap_request',
    identifier: swapIdentifier,
    where: { deleted_at: null },
    select: {
      id: true,
      human_friendly_id: true,
      shift: {
        select: {
          tenant_id: true,
          facility_id: true,
        },
      },
    },
  });

  if (!swapRecord?.id) {
    throw new HttpError('errors.shift_swap_request.not_found', 404);
  }

  const updatedSwap = await prisma.shift_swap_request.update({
    where: { id: swapRecord.id },
    data: { status: 'CANCELLED' },
  });

  createAuditLog({
    user_id: userId,
    action: 'UPDATE',
    entity: 'shift_swap_request',
    entity_id: swapRecord.id,
    diff: {
      metadata: {
        operation: 'SWAP_REJECT',
        reason: normalizeString(payload.reason) || null,
      },
    },
    ip_address: ipAddress,
  }).catch(() => {});

  publishHrWorkspaceUpdate({
    action: 'REJECT',
    actorUserId: userId || null,
    tenantId: swapRecord.shift?.tenant_id || null,
    facilityId: swapRecord.shift?.facility_id || null,
    panel: 'shifts',
    resource: 'shift-swap-requests',
    displayId: resolveDisplayId(updatedSwap),
    queue: 'SWAP_REQUESTS',
    targetPath: buildWorkbenchPath({
      panel: 'shifts',
      resource: 'shift-swap-requests',
      id: resolveDisplayId(updatedSwap),
      action: 'view',
    }),
  }).catch(() => {});

  return {
    swap: {
      id: resolveDisplayId(updatedSwap),
      display_id: resolveDisplayId(updatedSwap),
      backend_identifier: updatedSwap.id,
      status: updatedSwap.status,
    },
  };
};

const approveLeave = async (leaveIdentifier, payload = {}, userId = null, ipAddress = null) => {
  const leaveRecord = await resolveModelRecordByIdentifier({
    model: 'staff_leave',
    identifier: leaveIdentifier,
    where: { deleted_at: null },
    select: {
      id: true,
      human_friendly_id: true,
      staff_profile: {
        select: {
          id: true,
          human_friendly_id: true,
          tenant_id: true,
        },
      },
    },
  });

  if (!leaveRecord?.id) {
    throw new HttpError('errors.staff_leave.not_found', 404);
  }

  const updated = await prisma.staff_leave.update({
    where: { id: leaveRecord.id },
    data: { status: 'APPROVED' },
  });

  const { applyApprovedLeaveToSchedule } = require('@services/staff-leave/staff-leave.service');
  const scheduleImpact = await applyApprovedLeaveToSchedule(updated);

  createAuditLog({
    user_id: userId,
    action: 'UPDATE',
    entity: 'staff_leave',
    entity_id: leaveRecord.id,
    diff: {
      metadata: {
        operation: 'LEAVE_APPROVE',
        reason: normalizeString(payload.reason) || null,
        schedule_impact: scheduleImpact,
      },
    },
    ip_address: ipAddress,
  }).catch(() => {});

  publishHrWorkspaceUpdate({
    action: 'APPROVE',
    actorUserId: userId || null,
    tenantId: leaveRecord.staff_profile?.tenant_id || null,
    panel: 'staffing',
    resource: 'staff-leaves',
    displayId: resolveDisplayId(updated),
    queue: 'LEAVE_REQUESTS',
    targetPath: buildWorkbenchPath({
      panel: 'staffing',
      resource: 'staff-leaves',
      id: resolveDisplayId(updated),
      action: 'view',
      staffProfileId: resolveDisplayId(leaveRecord.staff_profile || {}),
    }),
  }).catch(() => {});

  return {
    leave: {
      id: resolveDisplayId(updated),
      display_id: resolveDisplayId(updated),
      backend_identifier: updated.id,
      status: updated.status,
    },
  };
};

const rejectLeave = async (leaveIdentifier, payload = {}, userId = null, ipAddress = null) => {
  const leaveRecord = await resolveModelRecordByIdentifier({
    model: 'staff_leave',
    identifier: leaveIdentifier,
    where: { deleted_at: null },
    select: {
      id: true,
      human_friendly_id: true,
      staff_profile: {
        select: {
          id: true,
          human_friendly_id: true,
          tenant_id: true,
        },
      },
    },
  });

  if (!leaveRecord?.id) {
    throw new HttpError('errors.staff_leave.not_found', 404);
  }

  const updated = await prisma.staff_leave.update({
    where: { id: leaveRecord.id },
    data: { status: 'REJECTED' },
  });

  createAuditLog({
    user_id: userId,
    action: 'UPDATE',
    entity: 'staff_leave',
    entity_id: leaveRecord.id,
    diff: {
      metadata: { operation: 'LEAVE_REJECT', reason: normalizeString(payload.reason) || null },
    },
    ip_address: ipAddress,
  }).catch(() => {});

  publishHrWorkspaceUpdate({
    action: 'REJECT',
    actorUserId: userId || null,
    tenantId: leaveRecord.staff_profile?.tenant_id || null,
    panel: 'staffing',
    resource: 'staff-leaves',
    displayId: resolveDisplayId(updated),
    queue: 'LEAVE_REQUESTS',
    targetPath: buildWorkbenchPath({
      panel: 'staffing',
      resource: 'staff-leaves',
      id: resolveDisplayId(updated),
      action: 'view',
      staffProfileId: resolveDisplayId(leaveRecord.staff_profile || {}),
    }),
  }).catch(() => {});

  return {
    leave: {
      id: resolveDisplayId(updated),
      display_id: resolveDisplayId(updated),
      backend_identifier: updated.id,
      status: updated.status,
    },
  };
};

const buildPayrollProposedItems = async (payrollRunRecord, filters = {}) => {
  const facilityId = await resolveIdentifierForFilter({
    value: filters.facility_id,
    model: 'facility',
    where: { deleted_at: null },
  });
  const departmentId = await resolveIdentifierForFilter({
    value: filters.department_id,
    model: 'department',
    where: { deleted_at: null },
  });
  const staffProfileId = await resolveIdentifierForFilter({
    value: filters.staff_profile_id,
    model: 'staff_profile',
    where: { deleted_at: null, tenant_id: payrollRunRecord.tenant_id },
  });

  const periodStart = payrollRunRecord.period_start;
  const periodEnd = payrollRunRecord.period_end;
  const compensationEffectiveWhere = {
    deleted_at: null,
    effective_from: { lte: periodEnd },
    OR: [{ effective_to: null }, { effective_to: { gte: periodStart } }],
  };

  const staffInclude = {
    id: true,
    human_friendly_id: true,
    staff_number: true,
    user_id: true,
    consultation_fee: true,
    consultation_currency: true,
    compensations: {
      where: compensationEffectiveWhere,
      orderBy: { effective_from: 'desc' },
    },
    user: {
      select: {
        id: true,
        email: true,
        profile: {
          select: {
            first_name: true,
            last_name: true,
          },
        },
      },
    },
  };

  const staffProfiles = await prisma.staff_profile.findMany({
    where: {
      deleted_at: null,
      tenant_id: payrollRunRecord.tenant_id,
      ...(departmentId ? { department_id: departmentId } : {}),
      ...(staffProfileId ? { id: staffProfileId } : {}),
      OR: [
        { compensations: { some: compensationEffectiveWhere } },
        {
          shift_assignments: {
            some: {
              deleted_at: null,
              shift: {
                deleted_at: null,
                ...(facilityId ? { facility_id: facilityId } : {}),
                start_time: { lte: periodEnd },
                end_time: { gte: periodStart },
              },
            },
          },
        },
      ],
    },
    select: staffInclude,
  });

  const activityMap = await loadStaffPayrollActivity({
    staffProfiles,
    periodStart,
    periodEnd,
    tenantId: payrollRunRecord.tenant_id,
    facilityId,
  });

  const proposedItems = staffProfiles.map((profile) => {
    const activity = activityMap.get(profile.id) || {
      assignments: [],
      availability: [],
      leaves: [],
      totalHours: 0,
      assignmentCount: 0,
      consultationCount: 0,
      procedureCount: 0,
    };
    const eligibleWorkdays = computeEligibleWorkdays({
      periodStart,
      periodEnd,
      availabilityRecords: activity.availability,
      assignments: activity.assignments,
      leaves: activity.leaves,
    });

    const compensations = Array.isArray(profile.compensations) && profile.compensations.length
      ? profile.compensations
      : profile.consultation_fee
        ? [
            {
              pay_type: 'PER_CONSULTATION',
              rate: profile.consultation_fee,
              currency: profile.consultation_currency || 'USD',
              effective_from: periodStart,
              metadata_json: { source: 'legacy_consultation_fee' },
            },
          ]
        : [];

    const calculations = compensations.map((compensation) =>
      calculateCompensationAmount({
        compensation,
        totalHours: activity.totalHours,
        periodStart,
        periodEnd,
        eligibleWorkdays,
        consultationCount: activity.consultationCount,
        procedureCount: activity.procedureCount,
      })
    );

    const { amount, currency, warnings, mixedCurrency } = sumCompensationAmounts(calculations);

    return {
      staff_profile_id: profile.id,
      staff_profile_display_id: resolveDisplayId(profile || {}),
      staff_number: profile.staff_number || null,
      staff_name:
        normalizeString(`${profile.user?.profile?.first_name || ''} ${profile.user?.profile?.last_name || ''}`) ||
        profile.user?.email ||
        null,
      assignment_count: activity.assignmentCount,
      total_hours: Number((activity.totalHours || 0).toFixed(2)),
      hourly_rate: calculations.find((item) => item.calculation.pay_type === 'PER_HOUR')?.calculation.rate || 0,
      amount,
      currency,
      calculation: {
        compensation_count: compensations.length,
        components: calculations.map((item) => item.calculation),
        warnings,
        mixed_currency: mixedCurrency,
        eligible_workdays: eligibleWorkdays.eligibleDays,
      },
    };
  });

  const totals = proposedItems.reduce(
    (acc, item) => {
      acc.total_amount += Number(item.amount || 0);
      acc.total_hours += Number(item.total_hours || 0);
      acc.staff_count += 1;
      return acc;
    },
    { total_amount: 0, total_hours: 0, staff_count: 0, currency: proposedItems[0]?.currency || 'USD' }
  );

  totals.total_amount = Number(totals.total_amount.toFixed(2));
  totals.total_hours = Number(totals.total_hours.toFixed(2));

  return { proposedItems, totals };
};

const mapStoredPayrollItemToProposed = (item) => {
  const calculation =
    item?.calculation_json && typeof item.calculation_json === 'object'
      ? item.calculation_json
      : {};
  const profile = item?.staff_profile || {};
  const user = profile.user || {};
  const person = user.profile || {};
  return {
    staff_profile_id: item.staff_profile_id || profile.id || null,
    staff_profile_display_id: resolveDisplayId(profile),
    staff_number: profile.staff_number || null,
    staff_name:
      normalizeString(`${person.first_name || ''} ${person.last_name || ''}`) ||
      user.email ||
      null,
    assignment_count: Number(calculation.assignment_count || 0) || 0,
    total_hours: Number(calculation.total_hours || 0) || 0,
    amount: Number(item.amount || 0) || 0,
    currency: normalizeString(item.currency) || 'USD',
    calculation,
  };
};

const previewPayrollRun = async (payrollRunIdentifier, filters = {}) => {
  const payrollRunRecord = await resolveModelRecordByIdentifier({
    model: 'payroll_run',
    identifier: payrollRunIdentifier,
    where: { deleted_at: null },
    select: {
      id: true,
      human_friendly_id: true,
      tenant_id: true,
      status: true,
      period_start: true,
      period_end: true,
      preview_json: true,
    },
  });

  if (!payrollRunRecord?.id) throw new HttpError('errors.payroll_run.not_found', 404);

  let { proposedItems, totals } = await buildPayrollProposedItems(payrollRunRecord, filters);

  // Live recalculation can return empty when no current compensations match the
  // period. Prefer stored preview / payroll_item rows so detail and print still
  // show the amounts already associated with this pay run.
  if (!Array.isArray(proposedItems) || proposedItems.length === 0) {
    const storedPreview =
      payrollRunRecord.preview_json && typeof payrollRunRecord.preview_json === 'object'
        ? payrollRunRecord.preview_json
        : {};
    const storedItems = Array.isArray(storedPreview.proposed_items)
      ? storedPreview.proposed_items
      : [];
    if (storedItems.length > 0) {
      proposedItems = storedItems;
      totals =
        storedPreview.totals && typeof storedPreview.totals === 'object'
          ? storedPreview.totals
          : totals;
    } else {
      const persistedItems = await prisma.payroll_item.findMany({
        where: {
          deleted_at: null,
          payroll_run_id: payrollRunRecord.id,
        },
        include: {
          staff_profile: {
            select: {
              id: true,
              human_friendly_id: true,
              staff_number: true,
              user: {
                select: {
                  email: true,
                  profile: {
                    select: { first_name: true, last_name: true },
                  },
                },
              },
            },
          },
        },
      });
      if (persistedItems.length > 0) {
        proposedItems = persistedItems.map(mapStoredPayrollItemToProposed);
        totals = proposedItems.reduce(
          (acc, item) => {
            acc.total_amount += Number(item.amount || 0);
            acc.total_hours += Number(item.total_hours || 0);
            acc.staff_count += 1;
            if (!acc.currency && item.currency) acc.currency = item.currency;
            return acc;
          },
          {
            total_amount: 0,
            total_hours: 0,
            staff_count: 0,
            currency: proposedItems[0]?.currency || 'USD',
          }
        );
        totals.total_amount = Number(Number(totals.total_amount || 0).toFixed(2));
        totals.total_hours = Number(Number(totals.total_hours || 0).toFixed(2));
      }
    }
  }

  const preview = {
    run_summary: {
      id: resolveDisplayId(payrollRunRecord),
      display_id: resolveDisplayId(payrollRunRecord),
      backend_identifier: payrollRunRecord.id,
      status: payrollRunRecord.status,
      period_start: payrollRunRecord.period_start,
      period_end: payrollRunRecord.period_end,
    },
    proposed_items: proposedItems,
    totals,
  };
  await prisma.payroll_run.update({
    where: { id: payrollRunRecord.id },
    data: { preview_json: preview },
  }).catch(() => {});
  return preview;
};

const processPayrollRun = async (payrollRunIdentifier, payload = {}, userId = null, ipAddress = null) => {
  const payrollRunRecord = await resolveModelRecordByIdentifier({
    model: 'payroll_run',
    identifier: payrollRunIdentifier,
    where: { deleted_at: null },
    select: {
      id: true,
      human_friendly_id: true,
      tenant_id: true,
      status: true,
      period_start: true,
      period_end: true,
    },
  });

  if (!payrollRunRecord?.id) throw new HttpError('errors.payroll_run.not_found', 404);
  if (String(payrollRunRecord.status || '').toUpperCase() === 'PAID') {
    throw new HttpError('errors.hr_workspace.payroll_already_paid', 400);
  }

  const { proposedItems, totals } = await buildPayrollProposedItems(payrollRunRecord, {});
  const replaceExisting = Boolean(payload.replace_existing_items);

  await prisma.$transaction(async (tx) => {
    if (replaceExisting) {
      await tx.payroll_item.updateMany({
        where: { deleted_at: null, payroll_run_id: payrollRunRecord.id },
        data: { deleted_at: new Date() },
      });
    }

    for (const item of proposedItems) {
      const existing = await tx.payroll_item.findFirst({
        where: { deleted_at: null, payroll_run_id: payrollRunRecord.id, staff_profile_id: item.staff_profile_id },
      });

      if (existing) {
        await tx.payroll_item.update({
          where: { id: existing.id },
          data: {
            amount: String(item.amount.toFixed(2)),
            currency: item.currency,
            calculation_json: item.calculation,
          },
        });
      } else {
        await tx.payroll_item.create({
          data: {
            payroll_run_id: payrollRunRecord.id,
            staff_profile_id: item.staff_profile_id,
            amount: String(item.amount.toFixed(2)),
            currency: item.currency,
            calculation_json: item.calculation,
          },
        });
      }
    }

    await tx.payroll_run.update({
      where: { id: payrollRunRecord.id },
      data: {
        status: 'PROCESSED',
        preview_json: { proposed_items: proposedItems, totals },
        audit_trail_json: {
          operation: 'PAYROLL_PROCESS',
          processed_at: new Date().toISOString(),
          processed_by_user_id: userId || null,
          replace_existing_items: replaceExisting,
          notes: normalizeString(payload.notes) || null,
          totals,
          finance_notification: {
            status: 'READY_FOR_FINANCE',
            notified_at: new Date().toISOString(),
            message:
              'HR approved this pay run. Finance/Accounting can process payment.',
          },
        },
      },
    });
  });

  createAuditLog({
    user_id: userId,
    action: 'UPDATE',
    entity: 'payroll_run',
    entity_id: payrollRunRecord.id,
    tenant_id: payrollRunRecord.tenant_id,
    diff: {
      metadata: {
        operation: 'PAYROLL_PROCESS',
        replace_existing_items: replaceExisting,
        notes: normalizeString(payload.notes) || null,
        processed_items: proposedItems.length,
        totals,
        finance_notification: 'READY_FOR_FINANCE',
      },
    },
    ip_address: ipAddress,
  }).catch(() => {});

  publishHrWorkspaceUpdate({
    action: 'PROCESS',
    actorUserId: userId || null,
    tenantId: payrollRunRecord.tenant_id,
    panel: 'payroll',
    resource: 'payroll-runs',
    displayId: resolveDisplayId(payrollRunRecord),
    queue: 'PAYROLL_DRAFTS',
    targetPath: buildWorkbenchPath({
      panel: 'payroll',
      resource: 'payroll-runs',
      id: resolveDisplayId(payrollRunRecord),
      payrollRunId: resolveDisplayId(payrollRunRecord),
      action: 'view',
    }),
  }).catch(() => {});

  return {
    processed_summary: {
      id: resolveDisplayId(payrollRunRecord),
      display_id: resolveDisplayId(payrollRunRecord),
      backend_identifier: payrollRunRecord.id,
      status: 'PROCESSED',
      processed_items: proposedItems.length,
      totals,
      finance_notification: 'READY_FOR_FINANCE',
    },
    items: proposedItems,
  };
};

const updatePayrollRunLifecycle = async (
  payrollRunIdentifier,
  nextStatus,
  { userId = null, ipAddress = null, operation = null, notes = null } = {}
) => {
  const payrollRunRecord = await resolveModelRecordByIdentifier({
    model: 'payroll_run',
    identifier: payrollRunIdentifier,
    where: { deleted_at: null },
    select: {
      id: true,
      human_friendly_id: true,
      tenant_id: true,
      status: true,
    },
  });

  if (!payrollRunRecord?.id) {
    throw new HttpError('errors.payroll_run.not_found', 404);
  }

  const current = String(payrollRunRecord.status || '').toUpperCase();
  const target = String(nextStatus || '').toUpperCase();

  if (target === 'CANCELLED') {
    if (!['DRAFT', 'PROCESSED'].includes(current)) {
      throw new HttpError('errors.hr_workspace.payroll_cancel_invalid_status', 400);
    }
  } else if (target === 'PAID') {
    if (current === 'PAID') {
      throw new HttpError('errors.hr_workspace.payroll_already_paid', 400);
    }
    if (current !== 'PROCESSED') {
      throw new HttpError('errors.hr_workspace.payroll_mark_paid_requires_processed', 400);
    }
  } else {
    throw new HttpError('errors.validation.invalid_status', 400);
  }

  const resolvedOperation =
    operation || (target === 'PAID' ? 'PAYROLL_MARK_PAID' : 'PAYROLL_CANCEL');

  await prisma.payroll_run.update({
    where: { id: payrollRunRecord.id },
    data: {
      status: target,
      audit_trail_json: {
        operation: resolvedOperation,
        at: new Date().toISOString(),
        by_user_id: userId || null,
        notes: normalizeString(notes) || null,
        previous_status: current,
      },
    },
  });

  createAuditLog({
    user_id: userId,
    action: 'UPDATE',
    entity: 'payroll_run',
    entity_id: payrollRunRecord.id,
    tenant_id: payrollRunRecord.tenant_id,
    diff: {
      metadata: {
        operation: resolvedOperation,
        previous_status: current,
        status: target,
        notes: normalizeString(notes) || null,
      },
    },
    ip_address: ipAddress,
  }).catch(() => {});

  publishHrWorkspaceUpdate({
    action: target === 'PAID' ? 'PAID' : 'CANCEL',
    actorUserId: userId || null,
    tenantId: payrollRunRecord.tenant_id,
    panel: 'payroll',
    resource: 'payroll-runs',
    displayId: resolveDisplayId(payrollRunRecord),
    queue: 'PAYROLL_DRAFTS',
    targetPath: buildWorkbenchPath({
      panel: 'payroll',
      resource: 'payroll-runs',
      id: resolveDisplayId(payrollRunRecord),
      payrollRunId: resolveDisplayId(payrollRunRecord),
      action: 'view',
    }),
  }).catch(() => {});

  return {
    id: resolveDisplayId(payrollRunRecord),
    display_id: resolveDisplayId(payrollRunRecord),
    backend_identifier: payrollRunRecord.id,
    status: target,
  };
};

const cancelPayrollRun = async (payrollRunIdentifier, payload = {}, userId = null, ipAddress = null) =>
  updatePayrollRunLifecycle(payrollRunIdentifier, 'CANCELLED', {
    userId,
    ipAddress,
    operation: 'PAYROLL_CANCEL',
    notes: payload.notes,
  });

const markPayrollRunPaid = async (payrollRunIdentifier, payload = {}, userId = null, ipAddress = null) =>
  updatePayrollRunLifecycle(payrollRunIdentifier, 'PAID', {
    userId,
    ipAddress,
    operation: 'PAYROLL_MARK_PAID',
    notes: payload.notes,
  });

const resolveLegacyRouteIdentifier = async (resource, id) => {
  const config = LEGACY_RESOURCE_CONFIG[normalizeString(resource).toLowerCase()];
  if (!config) throw new HttpError('errors.resource.not_found', 404);

  const normalizedResource = normalizeString(resource).toLowerCase();
  const normalizedIdentifier = normalizeIdentifier(id);

  const record = await resolveModelRecordByIdentifier({
    model: config.model,
    identifier: normalizedIdentifier,
    where: { deleted_at: null },
    select: { id: true, human_friendly_id: true },
  });

  if (!record?.id) throw new HttpError('errors.resource.not_found', 404);

  const publicIdentifier =
    resolvePublicIdentifier(record.human_friendly_id, normalizedIdentifier) || null;

  if (!publicIdentifier) {
    throw new HttpError('errors.resource.not_found', 404);
  }

  const routeState = {
    panel: config.panel,
    resource: config.resource,
    id: publicIdentifier,
    action: 'view',
  };

  return {
    resource: normalizedResource,
    panel: config.panel,
    action: 'view',
    id: publicIdentifier,
    display_id: publicIdentifier,
    backend_identifier: record.id,
    matched_by:
      normalizeString(normalizedIdentifier).toLowerCase() === normalizeString(record.id).toLowerCase()
        ? 'uuid'
        : 'human_friendly_id',
    route_state: routeState,
    target_path: buildWorkbenchPath(routeState),
  };
};

const getStaffAccessSummary = async (staffProfileIdentifier) => {
  const staffRecord = await resolveModelRecordByIdentifier({
    model: 'staff_profile',
    identifier: staffProfileIdentifier,
    where: { deleted_at: null },
    select: {
      id: true,
      human_friendly_id: true,
      tenant_id: true,
      user_id: true,
      department_id: true,
    },
  });

  if (!staffRecord?.id) {
    throw new HttpError('errors.staff_profile.not_found', 404);
  }

  if (!staffRecord.user_id) {
    return {
      staff_profile_id: resolveDisplayId(staffRecord),
      linked_user: null,
      user_roles: [],
      module_access: [],
      effective_permissions: [],
    };
  }

  const [userRoles, linkedUser, subscription] = await Promise.all([
    prisma.user_role.findMany({
      where: {
        deleted_at: null,
        user_id: staffRecord.user_id,
      },
      include: {
        role: {
          select: {
            id: true,
            human_friendly_id: true,
            name: true,
          },
        },
      },
      orderBy: { created_at: 'desc' },
      take: 50,
    }),
    prisma.user.findFirst({
      where: { id: staffRecord.user_id, deleted_at: null },
      select: {
        id: true,
        human_friendly_id: true,
        email: true,
        profile: {
          select: {
            first_name: true,
            last_name: true,
          },
        },
      },
    }),
    prisma.subscription.findFirst({
      where: {
        tenant_id: staffRecord.tenant_id,
        deleted_at: null,
        status: { in: ['ACTIVE', 'TRIAL', 'PAST_DUE'] },
      },
      orderBy: { updated_at: 'desc' },
      include: {
        module_subscriptions: {
          where: { deleted_at: null },
          include: {
            module: {
              select: {
                id: true,
                human_friendly_id: true,
                name: true,
                slug: true,
                module_group: true,
              },
            },
          },
          orderBy: [{ is_active: 'desc' }, { updated_at: 'desc' }],
        },
      },
    }),
  ]);

  const facilityIds = [
    ...new Set(userRoles.map((entry) => entry.facility_id).filter(Boolean)),
  ];
  const facilities = facilityIds.length
    ? await prisma.facility.findMany({
        where: { id: { in: facilityIds }, deleted_at: null },
        select: { id: true, human_friendly_id: true, name: true },
      })
    : [];
  const facilityById = new Map(facilities.map((entry) => [entry.id, entry]));

  const roleIds = userRoles.map((entry) => entry.role_id).filter(Boolean);
  const rolePermissions = roleIds.length
    ? await prisma.role_permission.findMany({
        where: {
          deleted_at: null,
          role_id: { in: roleIds },
        },
        include: {
          permission: {
            select: {
              name: true,
            },
          },
        },
      })
    : [];

  const effectivePermissions = [
    ...new Set(
      rolePermissions
        .map((entry) => entry.permission?.name)
        .filter(Boolean)
    ),
  ].sort();

  const moduleAccess = (subscription?.module_subscriptions || [])
    .map((entry) => ({
      slug: entry.module?.slug || null,
      label: entry.module?.name || null,
      module_group: entry.module?.module_group || null,
      granted: Boolean(entry.is_active) && !Boolean(entry.entitlement_denied),
    }))
    .filter((entry) => entry.slug);

  const mappedRoles = userRoles.map((entry) => {
    const facility = entry.facility_id ? facilityById.get(entry.facility_id) : null;
    return {
      id: resolvePublicIdentifier(entry.human_friendly_id, entry.id),
      display_id: resolvePublicIdentifier(entry.human_friendly_id),
      backend_identifier: entry.id,
      role_id: resolvePublicIdentifier(entry.role?.human_friendly_id, entry.role_id),
      role_name: entry.role?.name || null,
      facility_id: entry.facility_id || null,
      facility_name: facility?.name || null,
      facility_display_id: resolvePublicIdentifier(facility?.human_friendly_id),
      tenant_id: entry.tenant_id || null,
    };
  });

  const firstName = linkedUser?.profile?.first_name || '';
  const lastName = linkedUser?.profile?.last_name || '';

  return {
    staff_profile_id: resolveDisplayId(staffRecord),
    linked_user: linkedUser
      ? {
          id: linkedUser.id,
          display_id: resolvePublicIdentifier(linkedUser.human_friendly_id),
          email: linkedUser.email || null,
          full_name:
            normalizeString(`${firstName} ${lastName}`) || linkedUser.email || null,
        }
      : null,
    user_roles: mappedRoles,
    module_access: moduleAccess,
    effective_permissions: effectivePermissions,
  };
};

const offboardStaff = async (staffProfileIdentifier, payload = {}, userId = null, ipAddress = null) => {
  const staffRecord = await resolveModelRecordByIdentifier({
    model: 'staff_profile',
    identifier: staffProfileIdentifier,
    where: { deleted_at: null },
    select: {
      id: true,
      human_friendly_id: true,
      staff_number: true,
      tenant_id: true,
      user_id: true,
    },
  });

  if (!staffRecord?.id) {
    throw new HttpError('errors.staff_profile.not_found', 404);
  }

  const lastWorkingDay = new Date(payload.last_working_day);
  if (Number.isNaN(lastWorkingDay.getTime())) {
    throw new HttpError('errors.validation.invalid_date', 400);
  }

  const scheduleFinalPayroll = Boolean(payload.schedule_final_payroll);

  await prisma.$transaction(async (tx) => {
    if (payload.end_assignments !== false) {
      await tx.staff_assignment.updateMany({
        where: {
          deleted_at: null,
          staff_profile_id: staffRecord.id,
          OR: [{ end_date: null }, { end_date: { gt: lastWorkingDay } }],
        },
        data: { end_date: lastWorkingDay },
      });
    }

    await tx.shift_assignment.updateMany({
      where: {
        deleted_at: null,
        staff_profile_id: staffRecord.id,
        assigned_at: { gt: lastWorkingDay },
      },
      data: { deleted_at: new Date() },
    });

    await tx.staff_leave.updateMany({
      where: {
        deleted_at: null,
        staff_profile_id: staffRecord.id,
        status: { in: ['REQUESTED'] },
      },
      data: { status: 'CANCELLED' },
    });

    if (payload.revoke_access !== false && staffRecord.user_id) {
      await tx.user.update({
        where: { id: staffRecord.user_id },
        data: { deleted_at: new Date() },
      }).catch(() => {});
    }

    await tx.staff_profile.update({
      where: { id: staffRecord.id },
      data: { deleted_at: lastWorkingDay },
    });
  });

  // Staff compensation draft only — never patient Billing / clinical-request.
  let finalPayrollRun = null;
  if (scheduleFinalPayroll && staffRecord.tenant_id && prisma?.payroll_run?.create) {
    const periodEnd = lastWorkingDay;
    const periodStart = new Date(lastWorkingDay.getTime());
    periodStart.setUTCDate(periodStart.getUTCDate() - 13);
    finalPayrollRun = await prisma.payroll_run.create({
      data: {
        tenant_id: staffRecord.tenant_id,
        period_start: periodStart,
        period_end: periodEnd,
        status: 'DRAFT',
        audit_trail_json: {
          operation: 'SCHEDULE_FINAL_PAYROLL',
          source: 'STAFF_OFFBOARD',
          staff_profile_id: staffRecord.id,
          billing_status: 'NOT_BILLED',
        },
      },
    }).catch(() => null);

    if (finalPayrollRun?.id) {
      publishHrWorkspaceUpdate({
        action: 'CREATE',
        actorUserId: userId || null,
        tenantId: staffRecord.tenant_id,
        panel: 'payroll',
        resource: 'payroll-runs',
        displayId: resolveDisplayId(finalPayrollRun),
        queue: 'PAYROLL_DRAFTS',
        targetPath: buildWorkbenchPath({
          panel: 'payroll',
          resource: 'payroll-runs',
          id: resolveDisplayId(finalPayrollRun),
          payrollRunId: resolveDisplayId(finalPayrollRun),
          action: 'view',
        }),
      }).catch(() => {});
    }
  }

  createAuditLog({
    user_id: userId,
    action: 'UPDATE',
    entity: 'staff_profile',
    entity_id: staffRecord.id,
    tenant_id: staffRecord.tenant_id,
    diff: {
      metadata: {
        operation: 'STAFF_OFFBOARD',
        separation_type: payload.separation_type,
        last_working_day: lastWorkingDay.toISOString(),
        reason: normalizeString(payload.reason) || null,
        schedule_final_payroll: scheduleFinalPayroll,
        final_payroll_run_id: finalPayrollRun?.id || null,
        billing_status: 'NOT_BILLED',
      },
    },
    ip_address: ipAddress,
  }).catch(() => {});

  publishHrWorkspaceUpdate({
    action: 'OFFBOARD',
    actorUserId: userId || null,
    tenantId: staffRecord.tenant_id,
    staffProfileId: staffRecord.id,
  }).catch(() => {});

  return {
    staff_profile_id: resolveDisplayId(staffRecord),
    staff_profile_display_id: resolveDisplayId(staffRecord),
    status: 'SEPARATED',
    separation_type: payload.separation_type,
    separation_date: lastWorkingDay,
    reason: normalizeString(payload.reason) || null,
    schedule_final_payroll: scheduleFinalPayroll,
    final_payroll_run_id: finalPayrollRun ? resolveDisplayId(finalPayrollRun) : null,
    billing_status: 'NOT_BILLED',
  };
};

module.exports = {
  getWorkspace,
  getWorkItems,
  getReferenceData,
  getStaffAccessSummary,
  getRosterWorkflow,
  generateStaffNumber,
  publishHrWorkspaceUpdate,
  generateRosterAssignments,
  publishRoster,
  overrideShiftAssignment,
  approveSwap,
  rejectSwap,
  approveLeave,
  rejectLeave,
  previewPayrollRun,
  processPayrollRun,
  cancelPayrollRun,
  markPayrollRunPaid,
  offboardStaff,
  resolveLegacyRouteIdentifier,
};
