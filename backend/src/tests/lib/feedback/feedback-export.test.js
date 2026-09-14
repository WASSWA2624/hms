const ExcelJS = require('exceljs');
const {
  FEEDBACK_EXPORT_COLUMNS,
  buildFeedbackExportFileName,
  renderFeedbackWorkbook,
  resolveExportClock
} = require('@lib/feedback/feedback-export');

describe('feedback export', () => {
  const instant = new Date('2026-09-14T11:35:27.000Z');

  it('names files HOSSPI-FEEDBACK-DDMMYYYY-HHmmss on the client time zone', () => {
    const clock = resolveExportClock({ timeZone: 'Africa/Kampala' });

    expect(clock.label).toBe('Africa/Kampala');
    expect(buildFeedbackExportFileName(instant, clock)).toBe('HOSSPI-FEEDBACK-14092026-143527.xlsx');
  });

  it('uses 24-hour time and the UTC offset when no time zone is known', () => {
    const evening = new Date('2026-09-14T20:05:09.000Z');

    expect(resolveExportClock({ utcOffsetMinutes: 180 }).label).toBe('UTC+03:00');
    expect(
      buildFeedbackExportFileName(evening, resolveExportClock({ utcOffsetMinutes: 180 }))
    ).toBe('HOSSPI-FEEDBACK-14092026-230509.xlsx');
    expect(
      buildFeedbackExportFileName(evening, resolveExportClock({ utcOffsetMinutes: 240 }))
    ).toBe('HOSSPI-FEEDBACK-15092026-000509.xlsx');
  });

  it('falls back to UTC for unknown zones and offsets', () => {
    const clock = resolveExportClock({ timeZone: 'Mars/Olympus', utcOffsetMinutes: 5000 });

    expect(clock.label).toBe('UTC');
    expect(buildFeedbackExportFileName(instant, clock)).toBe('HOSSPI-FEEDBACK-14092026-113527.xlsx');
  });

  it('writes every feedback field with local and UTC submission times', async () => {
    const buffer = await renderFeedbackWorkbook({
      rows: [
        {
          human_friendly_id: 'FBK0000002',
          category: 'PROBLEM',
          message: 'Save button does nothing',
          submitter_type: 'AUTHENTICATED',
          user_email: 'admin@example.com',
          user_name: 'Jane Admin',
          user_human_friendly_id: 'USR0000001',
          user_position_title: 'Administrator',
          user_roles_json: ['TENANT_ADMIN'],
          user_permissions_json: ['patient:read', 'patient:write'],
          tenant_name: 'IHK',
          tenant_human_friendly_id: 'TEN0000001',
          facility_name: 'IHK Main',
          facility_human_friendly_id: 'FAC0000001',
          subscription_plan_name: 'Advanced',
          subscription_plan_code: 'ADVANCED',
          subscription_tier_code: 'ADVANCED',
          subscription_status: 'ACTIVE',
          screen_title: 'Patients',
          route_path: '/patients?tab=registry',
          route_name: 'patients',
          page_url: 'https://app.example.com/patients',
          client_platform: 'web',
          app_version: '0.1.0+1',
          app_environment: 'production',
          locale: 'en',
          timezone: 'Africa/Kampala',
          client_context_json: {
            viewport: { width: 1280, height: 800, device_pixel_ratio: 2 },
            breakpoint: 'lg',
            theme_mode: 'light',
            text_scale: 1,
            connectivity: 'online'
          },
          client_submitted_at: new Date('2026-09-14T11:35:20.000Z'),
          user_agent: 'Mozilla/5.0',
          ip_address: '10.0.0.1',
          submitted_at: instant
        },
        {
          human_friendly_id: 'FBK0000001',
          category: 'SUGGESTION',
          message: 'Add dark mode',
          submitter_type: 'ANONYMOUS',
          route_path: '/login',
          submitted_at: new Date('2026-09-13T08:00:00.000Z')
        }
      ],
      clock: resolveExportClock({ timeZone: 'Africa/Kampala' }),
      generatedAt: instant,
      generatedBy: 'owner@example.com'
    });

    const workbook = new ExcelJS.Workbook();
    await workbook.xlsx.load(buffer);
    const sheet = workbook.getWorksheet('Feedback');
    const headers = sheet.getRow(1).values.slice(1);
    const cell = (row, header) => sheet.getRow(row).getCell(headers.indexOf(header) + 1).value;

    expect(headers).toHaveLength(FEEDBACK_EXPORT_COLUMNS.length);
    expect(headers).toEqual(
      expect.arrayContaining([
        'Feedback ID',
        'Submitted At (Africa/Kampala)',
        'Submitted At (UTC)',
        'Category',
        'Feedback',
        'Submitted By',
        'User Email',
        'Roles',
        'Permissions',
        'Tenant',
        'Facility',
        'Subscription Plan',
        'Screen',
        'Route',
        'Page URL',
        'Platform',
        'User Agent',
        'IP Address'
      ])
    );

    expect(cell(2, 'Feedback ID')).toBe('FBK0000002');
    expect(cell(2, 'Category')).toBe('Problem');
    expect(cell(2, 'Submitted By')).toBe('Signed-in user');
    expect(cell(2, 'Permissions')).toBe('patient:read, patient:write');
    expect(cell(2, 'Submitted At (UTC)')).toBe('2026-09-14T11:35:27.000Z');
    expect(cell(2, 'Viewport')).toBe('1280x800 @2x');
    const local = cell(2, 'Submitted At (Africa/Kampala)');
    expect(local).toBeInstanceOf(Date);
    expect(local.toISOString()).toBe('2026-09-14T14:35:27.000Z');

    expect(cell(3, 'Submitted By')).toBe('Anonymous');
    expect(cell(3, 'User Email')).toBeNull();

    const details = workbook.getWorksheet('Export Details');
    expect(details.getRow(3).values.slice(1)).toEqual(['Time Zone', 'Africa/Kampala']);
    expect(details.getRow(5).values.slice(1)).toEqual(['Records', 2]);
  });
});
