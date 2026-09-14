/**
 * Feedback Excel export
 *
 * @module lib/feedback
 * @description Renders stored feedback as an `.xlsx` workbook named
 * `HOSSPI-FEEDBACK-DDMMYYYY-HHmmss.xlsx`. Times use the requesting client's
 * wall clock (IANA time zone, else a UTC offset, else UTC) in 24-hour format,
 * so the file name and the dates inside it match what the admin sees locally.
 */

const ExcelJS = require('exceljs');

const FEEDBACK_EXPORT_MIME_TYPE =
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
const FEEDBACK_EXPORT_FILE_PREFIX = 'HOSSPI-FEEDBACK';
const FEEDBACK_EXPORT_DATE_FORMAT = 'dd/mm/yyyy hh:mm:ss';
const EXCEL_CELL_TEXT_LIMIT = 32767;
const MAX_UTC_OFFSET_MINUTES = 14 * 60;

const FEEDBACK_CATEGORY_LABELS = Object.freeze({
  GENERAL: 'General feedback',
  PROBLEM: 'Problem',
  COMPLAINT: 'Complaint',
  SUGGESTION: 'Suggestion',
  IMPROVEMENT: 'Improvement'
});

const FEEDBACK_SUBMITTER_LABELS = Object.freeze({
  AUTHENTICATED: 'Signed-in user',
  ANONYMOUS: 'Anonymous'
});

const FEEDBACK_DEVICE_TYPE_LABELS = Object.freeze({
  MOBILE: 'Mobile',
  TABLET: 'Tablet',
  DESKTOP: 'Desktop'
});

const pad = (value, length = 2) => String(value).padStart(length, '0');

const isValidTimeZone = (timeZone) => {
  if (typeof timeZone !== 'string' || !timeZone.trim()) {
    return false;
  }
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: timeZone.trim() });
    return true;
  } catch (_) {
    return false;
  }
};

const formatUtcOffsetLabel = (offsetMinutes) => {
  if (!offsetMinutes) {
    return 'UTC';
  }
  const sign = offsetMinutes < 0 ? '-' : '+';
  const absolute = Math.abs(offsetMinutes);
  return `UTC${sign}${pad(Math.floor(absolute / 60))}:${pad(absolute % 60)}`;
};

/**
 * Resolve the clock an export is rendered on.
 *
 * @param {Object} [options]
 * @param {string} [options.timeZone] - IANA zone from the `x-timezone` header
 * @param {number} [options.utcOffsetMinutes] - Fallback for clients without an IANA zone
 * @returns {{ timeZone: string|null, offsetMinutes: number|null, label: string }}
 */
const resolveExportClock = ({ timeZone, utcOffsetMinutes } = {}) => {
  if (isValidTimeZone(timeZone)) {
    const zone = timeZone.trim();
    return { timeZone: zone, offsetMinutes: null, label: zone };
  }

  const offset = Number(utcOffsetMinutes);
  if (
    utcOffsetMinutes !== null &&
    utcOffsetMinutes !== undefined &&
    Number.isInteger(offset) &&
    Math.abs(offset) <= MAX_UTC_OFFSET_MINUTES
  ) {
    return { timeZone: null, offsetMinutes: offset, label: formatUtcOffsetLabel(offset) };
  }

  return { timeZone: null, offsetMinutes: 0, label: 'UTC' };
};

const getWallClockParts = (date, clock) => {
  if (clock?.timeZone) {
    const parts = new Intl.DateTimeFormat('en-GB', {
      timeZone: clock.timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hourCycle: 'h23'
    }).formatToParts(date);
    const read = (type) => Number(parts.find((part) => part.type === type)?.value);
    return {
      year: read('year'),
      month: read('month'),
      day: read('day'),
      hour: read('hour') % 24,
      minute: read('minute'),
      second: read('second')
    };
  }

  const shifted = new Date(date.getTime() + (clock?.offsetMinutes || 0) * 60 * 1000);
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth() + 1,
    day: shifted.getUTCDate(),
    hour: shifted.getUTCHours(),
    minute: shifted.getUTCMinutes(),
    second: shifted.getUTCSeconds()
  };
};

const formatWallClock = (date, clock) => {
  const parts = getWallClockParts(date, clock);
  return `${pad(parts.day)}/${pad(parts.month)}/${pad(parts.year, 4)} ` +
    `${pad(parts.hour)}:${pad(parts.minute)}:${pad(parts.second)}`;
};

/**
 * `HOSSPI-FEEDBACK-DDMMYYYY-HHmmss.xlsx` on the export clock, 24-hour time.
 *
 * @param {Date} [date]
 * @param {Object} [clock] - From `resolveExportClock`
 * @returns {string}
 */
const buildFeedbackExportFileName = (date = new Date(), clock = resolveExportClock()) => {
  const parts = getWallClockParts(date, clock);
  return `${FEEDBACK_EXPORT_FILE_PREFIX}-${pad(parts.day)}${pad(parts.month)}${pad(parts.year, 4)}-` +
    `${pad(parts.hour)}${pad(parts.minute)}${pad(parts.second)}.xlsx`;
};

const toDate = (value) => {
  if (!value) {
    return null;
  }
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
};

// ExcelJS writes dates as UTC serials, so a date whose UTC fields hold the
// wall-clock time displays as that local time in Excel.
const toWallClockCellDate = (value, clock) => {
  const date = toDate(value);
  if (!date) {
    return null;
  }
  const parts = getWallClockParts(date, clock);
  return new Date(Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute, parts.second));
};

const toIsoString = (value) => toDate(value)?.toISOString() || null;

const joinList = (value) => {
  if (Array.isArray(value)) {
    return value.map((entry) => String(entry || '').trim()).filter(Boolean).join(', ');
  }
  return typeof value === 'string' ? value : null;
};

const readClientContext = (row) =>
  row?.client_context_json && typeof row.client_context_json === 'object'
    ? row.client_context_json
    : {};

const formatPixelSize = (width, height, devicePixelRatio) => {
  if (!Number.isFinite(width) || !Number.isFinite(height)) {
    return null;
  }
  const size = `${Math.round(width)}x${Math.round(height)}`;
  return Number.isFinite(devicePixelRatio) ? `${size} @${devicePixelRatio}x` : size;
};

/** Column order is the export contract: identity, what, who, where, device. */
const FEEDBACK_EXPORT_COLUMNS = Object.freeze([
  { key: 'feedback_id', header: 'Feedback ID', width: 16, value: (row) => row.human_friendly_id },
  {
    key: 'submitted_at',
    header: (clock) => `Submitted At (${clock.label})`,
    width: 22,
    date: true,
    value: (row, clock) => toWallClockCellDate(row.submitted_at, clock)
  },
  { key: 'submitted_at_utc', header: 'Submitted At (UTC)', width: 26, value: (row) => toIsoString(row.submitted_at) },
  {
    key: 'category',
    header: 'Category',
    width: 18,
    value: (row) => FEEDBACK_CATEGORY_LABELS[row.category] || row.category
  },
  { key: 'message', header: 'Feedback', width: 60, wrap: true, value: (row) => row.message },
  {
    key: 'submitter',
    header: 'Submitted By',
    width: 16,
    value: (row) => FEEDBACK_SUBMITTER_LABELS[row.submitter_type] || row.submitter_type
  },
  { key: 'user_email', header: 'User Email', width: 30, value: (row) => row.user_email },
  { key: 'user_name', header: 'User Name', width: 24, value: (row) => row.user_name },
  { key: 'user_id', header: 'User ID', width: 16, value: (row) => row.user_human_friendly_id },
  { key: 'position_title', header: 'Position Title', width: 20, value: (row) => row.user_position_title },
  { key: 'roles', header: 'Roles', width: 30, wrap: true, value: (row) => joinList(row.user_roles_json) },
  {
    key: 'permissions',
    header: 'Permissions',
    width: 60,
    wrap: true,
    value: (row) => joinList(row.user_permissions_json)
  },
  { key: 'tenant', header: 'Tenant', width: 24, value: (row) => row.tenant_name },
  { key: 'tenant_id', header: 'Tenant ID', width: 16, value: (row) => row.tenant_human_friendly_id },
  { key: 'facility', header: 'Facility', width: 24, value: (row) => row.facility_name },
  { key: 'facility_id', header: 'Facility ID', width: 16, value: (row) => row.facility_human_friendly_id },
  { key: 'subscription_plan', header: 'Subscription Plan', width: 22, value: (row) => row.subscription_plan_name },
  { key: 'subscription_plan_code', header: 'Plan Code', width: 16, value: (row) => row.subscription_plan_code },
  { key: 'subscription_tier', header: 'Plan Tier', width: 14, value: (row) => row.subscription_tier_code },
  { key: 'subscription_status', header: 'Subscription Status', width: 20, value: (row) => row.subscription_status },
  { key: 'screen', header: 'Screen', width: 24, value: (row) => row.screen_title || row.route_name },
  { key: 'route', header: 'Route', width: 32, wrap: true, value: (row) => row.route_path },
  { key: 'route_name', header: 'Route Name', width: 20, value: (row) => row.route_name },
  { key: 'page_url', header: 'Page URL', width: 40, wrap: true, value: (row) => row.page_url },
  { key: 'platform', header: 'Platform', width: 12, value: (row) => row.client_platform },
  {
    key: 'device_type',
    header: 'Device Type',
    width: 14,
    value: (row) => FEEDBACK_DEVICE_TYPE_LABELS[row.device_type] || row.device_type
  },
  { key: 'app_version', header: 'App Version', width: 14, value: (row) => row.app_version },
  { key: 'app_environment', header: 'Environment', width: 14, value: (row) => row.app_environment },
  { key: 'locale', header: 'Locale', width: 10, value: (row) => row.locale },
  { key: 'timezone', header: 'Time Zone', width: 20, value: (row) => row.timezone },
  {
    key: 'viewport',
    header: 'Viewport (px)',
    width: 18,
    value: (row) =>
      formatPixelSize(row.viewport_width, row.viewport_height, readClientContext(row).device_pixel_ratio)
  },
  {
    key: 'display',
    header: 'Display (px)',
    width: 18,
    value: (row) => formatPixelSize(row.screen_width, row.screen_height)
  },
  { key: 'orientation', header: 'Orientation', width: 12, value: (row) => readClientContext(row).orientation },
  { key: 'breakpoint', header: 'Breakpoint', width: 12, value: (row) => readClientContext(row).breakpoint },
  { key: 'theme_mode', header: 'Theme', width: 10, value: (row) => readClientContext(row).theme_mode },
  { key: 'text_scale', header: 'Text Scale', width: 10, value: (row) => readClientContext(row).text_scale },
  { key: 'connectivity', header: 'Connectivity', width: 14, value: (row) => readClientContext(row).connectivity },
  { key: 'client_submitted_at', header: 'Device Clock (UTC)', width: 26, value: (row) => toIsoString(row.client_submitted_at) },
  { key: 'user_agent', header: 'User Agent', width: 40, wrap: true, value: (row) => row.user_agent },
  { key: 'ip_address', header: 'IP Address', width: 18, value: (row) => row.ip_address }
]);

const toCellValue = (value) => {
  if (value === null || value === undefined) {
    return null;
  }
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : value;
  }
  if (typeof value === 'number' || typeof value === 'boolean') {
    return value;
  }
  const text = String(value);
  return text.length > EXCEL_CELL_TEXT_LIMIT ? text.slice(0, EXCEL_CELL_TEXT_LIMIT) : text;
};

const describeFilterDate = (value, clock) => {
  const date = toDate(value);
  return date ? formatWallClock(date, clock) : 'Any time';
};

/**
 * Build the feedback workbook.
 *
 * @param {Object} options
 * @param {Object[]} [options.rows] - Feedback rows, newest first
 * @param {Object} [options.clock] - From `resolveExportClock`
 * @param {Date} [options.generatedAt]
 * @param {string|null} [options.generatedBy]
 * @param {Object} [options.filters] - Filters applied to `rows`
 * @returns {Promise<Buffer>}
 */
const renderFeedbackWorkbook = async ({
  rows = [],
  clock = resolveExportClock(),
  generatedAt = new Date(),
  generatedBy = null,
  filters = {}
} = {}) => {
  const workbook = new ExcelJS.Workbook();
  workbook.creator = 'HOSSPI HMS';
  workbook.lastModifiedBy = 'HOSSPI HMS';
  workbook.created = generatedAt;
  workbook.modified = generatedAt;
  workbook.subject = 'Feedback export';

  const sheet = workbook.addWorksheet('Feedback', {
    views: [{ state: 'frozen', ySplit: 1 }]
  });
  sheet.columns = FEEDBACK_EXPORT_COLUMNS.map((column) => ({
    key: column.key,
    header: typeof column.header === 'function' ? column.header(clock) : column.header,
    width: column.width
  }));

  rows.forEach((row) => {
    const values = {};
    FEEDBACK_EXPORT_COLUMNS.forEach((column) => {
      values[column.key] = toCellValue(column.value(row, clock));
    });
    sheet.addRow(values);
  });

  FEEDBACK_EXPORT_COLUMNS.forEach((column, index) => {
    const sheetColumn = sheet.getColumn(index + 1);
    if (column.date) {
      sheetColumn.numFmt = FEEDBACK_EXPORT_DATE_FORMAT;
    }
    sheetColumn.alignment = { vertical: 'top', wrapText: Boolean(column.wrap) };
  });
  sheet.getRow(1).font = { bold: true };
  sheet.autoFilter = {
    from: { row: 1, column: 1 },
    to: { row: 1, column: FEEDBACK_EXPORT_COLUMNS.length }
  };

  const details = workbook.addWorksheet('Export Details');
  details.columns = [
    { header: 'Detail', key: 'detail', width: 24 },
    { header: 'Value', key: 'value', width: 60 }
  ];
  details.addRows([
    { detail: 'Generated At', value: formatWallClock(generatedAt, clock) },
    { detail: 'Time Zone', value: clock.label },
    { detail: 'Generated By', value: generatedBy || '' },
    { detail: 'Records', value: rows.length },
    { detail: 'Category', value: FEEDBACK_CATEGORY_LABELS[filters.category] || 'All' },
    { detail: 'Submitted By', value: FEEDBACK_SUBMITTER_LABELS[filters.submitter_type] || 'All' },
    { detail: 'Device Type', value: FEEDBACK_DEVICE_TYPE_LABELS[filters.device_type] || 'All' },
    { detail: 'Submitted From', value: describeFilterDate(filters.from, clock) },
    { detail: 'Submitted To', value: describeFilterDate(filters.to, clock) }
  ]);
  details.getRow(1).font = { bold: true };

  return Buffer.from(await workbook.xlsx.writeBuffer());
};

module.exports = {
  FEEDBACK_CATEGORY_LABELS,
  FEEDBACK_DEVICE_TYPE_LABELS,
  FEEDBACK_EXPORT_COLUMNS,
  FEEDBACK_EXPORT_MIME_TYPE,
  FEEDBACK_SUBMITTER_LABELS,
  buildFeedbackExportFileName,
  formatWallClock,
  renderFeedbackWorkbook,
  resolveExportClock
};
