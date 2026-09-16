/**
 * Feedback repository tests
 *
 * @module tests/modules/feedback/repositories
 * Per testing.mdc: Mock all Prisma operations
 */

jest.mock('@prisma/client', () => ({
  feedback: {
    count: jest.fn(),
    deleteMany: jest.fn(),
    findFirst: jest.fn(),
    findMany: jest.fn(),
    groupBy: jest.fn()
  }
}));

const prisma = require('@prisma/client');
const {
  FEEDBACK_FILTER_KEYS,
  buildActiveFeedbackWhere,
  deleteFeedbackPermanently,
  listActiveFeedbackForExport,
  listActiveFeedbackPage,
  summarizeActiveFeedback,
  summarizeFeedbackFacets
} = require('@repositories/feedback/feedback.repository');

const conditionsOf = (where) => (where.AND ? where.AND : [where]);

describe('feedback repository', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('buildActiveFeedbackWhere', () => {
    it('always excludes soft-deleted rows', () => {
      expect(buildActiveFeedbackWhere()).toEqual({ deleted_at: null });
    });

    it.each([
      ['tenant_id', ['TEN-9322E26AFD'], { tenant_human_friendly_id: { in: ['TEN-9322E26AFD'] } }],
      ['facility_id', ['FAC-FBB67A688F'], { facility_human_friendly_id: { in: ['FAC-FBB67A688F'] } }],
      ['plan_tier', ['PRO'], { subscription_tier_code: { in: ['PRO'] } }],
      ['subscription_status', ['ACTIVE'], { subscription_status: { in: ['ACTIVE'] } }],
      ['route_name', ['hr', 'home'], { route_name: { in: ['hr', 'home'] } }],
      ['app_environment', ['production'], { app_environment: { in: ['production'] } }],
      ['app_version', ['1.4.0+12'], { app_version: { in: ['1.4.0+12'] } }],
      ['locale', ['en'], { locale: { in: ['en'] } }],
      ['platform', ['web'], { client_platform: { in: ['web'] } }]
    ])('filters %s on its indexed column', (key, values, condition) => {
      expect(conditionsOf(buildActiveFeedbackWhere({ [key]: values }))).toEqual([
        { deleted_at: null },
        condition
      ]);
    });

    it('matches any listed role inside user_roles_json', () => {
      expect(conditionsOf(buildActiveFeedbackWhere({ role: ['PLATFORM_ADMIN', 'NURSE'] }))).toEqual([
        { deleted_at: null },
        {
          OR: [
            { user_roles_json: { array_contains: ['PLATFORM_ADMIN'] } },
            { user_roles_json: { array_contains: ['NURSE'] } }
          ]
        }
      ]);
    });

    it.each([
      ['breakpoint', 'breakpoint', 'xl'],
      ['theme', 'theme_mode', 'dark'],
      ['connectivity', 'connectivity', 'offline'],
      ['orientation', 'orientation', 'landscape']
    ])('reads %s from client_context_json with a parameterized path filter', (key, path, value) => {
      expect(conditionsOf(buildActiveFeedbackWhere({ [key]: [value] }))).toEqual([
        { deleted_at: null },
        { OR: [{ client_context_json: { path: `$.${path}`, equals: value } }] }
      ]);
    });

    it('combines every active filter and leaves omitted dimensions out', () => {
      const filters = { tenant_id: ['TEN0000001'], route_name: ['hr'], breakpoint: ['xl'] };

      expect(conditionsOf(buildActiveFeedbackWhere(filters))).toHaveLength(4);
      expect(
        conditionsOf(buildActiveFeedbackWhere(filters, { omit: ['route_name', 'breakpoint'] }))
      ).toEqual([{ deleted_at: null }, { tenant_human_friendly_id: { in: ['TEN0000001'] } }]);
    });

    it('ignores keys that are not filter dimensions', () => {
      expect(buildActiveFeedbackWhere({ has_user: true, tenant: 'TEN0000001' })).toEqual({
        deleted_at: null
      });
    });
  });

  describe('list, summary, export, and delete', () => {
    const filters = {
      tenant_id: ['TEN-9322E26AFD'],
      role: ['PLATFORM_ADMIN'],
      route_name: ['hr'],
      breakpoint: ['xl']
    };

    it('narrows every operation with the same where clause', async () => {
      prisma.feedback.findMany.mockResolvedValue([]);
      prisma.feedback.count.mockResolvedValue(0);
      prisma.feedback.findFirst.mockResolvedValue(null);
      prisma.feedback.deleteMany.mockResolvedValue({ count: 0 });
      const expected = buildActiveFeedbackWhere(filters);

      await listActiveFeedbackPage({ filters, skip: 0, take: 20 });
      const listWhere = prisma.feedback.findMany.mock.calls[0][0].where;
      await summarizeActiveFeedback(filters);
      const summaryWhere = prisma.feedback.count.mock.calls[1][0].where;
      await listActiveFeedbackForExport(filters);
      const exportWhere = prisma.feedback.findMany.mock.calls[1][0].where;
      await deleteFeedbackPermanently({ filters });
      const deleteWhere = prisma.feedback.deleteMany.mock.calls[0][0].where;

      expect(listWhere).toEqual(expected);
      expect(summaryWhere).toEqual(expected);
      expect(exportWhere).toEqual(expected);
      expect(deleteWhere).toEqual(expected);
    });
  });

  describe('summarizeFeedbackFacets', () => {
    const rolesAndContext = [
      {
        id: 'f-1',
        user_roles_json: ['PLATFORM_ADMIN', 'TENANT_ADMIN'],
        client_context_json: { breakpoint: 'xl', theme_mode: 'light', connectivity: 'online' }
      },
      {
        id: 'f-2',
        user_roles_json: ['PLATFORM_ADMIN'],
        client_context_json: { breakpoint: 'sm', theme_mode: 'dark', orientation: 'portrait' }
      },
      { id: 'f-3', user_roles_json: null, client_context_json: { breakpoint: 'xl' } }
    ];

    beforeEach(() => {
      prisma.feedback.count.mockResolvedValue(3);
      prisma.feedback.groupBy.mockImplementation(async ({ by }) => {
        if (by[0] === 'tenant_human_friendly_id') {
          return [
            { tenant_human_friendly_id: 'TEN-1', tenant_name: 'DemoCare', _count: { _all: 2 } },
            { tenant_human_friendly_id: 'TEN-1', tenant_name: 'Old Name', _count: { _all: 1 } },
            { tenant_human_friendly_id: null, tenant_name: null, _count: { _all: 4 } }
          ];
        }
        if (by[0] === 'route_name') {
          return [
            { route_name: 'home', _count: { _all: 1 } },
            { route_name: 'hr', _count: { _all: 2 } }
          ];
        }
        return [];
      });
      prisma.feedback.findMany.mockResolvedValue(rolesAndContext);
    });

    it('returns every dimension with values counted and blanks dropped', async () => {
      const result = await summarizeFeedbackFacets({});

      expect(result.total).toBe(3);
      expect(Object.keys(result.facets).sort()).toEqual([...FEEDBACK_FILTER_KEYS].sort());
      expect(result.facets.tenant_id).toEqual([{ value: 'TEN-1', label: 'DemoCare', count: 3 }]);
      expect(result.facets.route_name).toEqual([
        { value: 'hr', count: 2 },
        { value: 'home', count: 1 }
      ]);
      expect(result.facets.role).toEqual([
        { value: 'PLATFORM_ADMIN', count: 2 },
        { value: 'TENANT_ADMIN', count: 1 }
      ]);
      expect(result.facets.breakpoint).toEqual([
        { value: 'xl', count: 2 },
        { value: 'sm', count: 1 }
      ]);
      expect(result.facets.theme).toEqual([
        { value: 'dark', count: 1 },
        { value: 'light', count: 1 }
      ]);
      expect(result.facets.orientation).toEqual([{ value: 'portrait', count: 1 }]);
      expect(result.facets.platform).toEqual([]);
    });

    it('counts each dimension under every active filter except its own', async () => {
      const filters = { route_name: ['hr'], breakpoint: ['xl'] };

      const result = await summarizeFeedbackFacets(filters);

      const routeCall = prisma.feedback.groupBy.mock.calls.find(([args]) => args.by[0] === 'route_name');
      expect(conditionsOf(routeCall[0].where)).toEqual([
        { deleted_at: null },
        { OR: [{ client_context_json: { path: '$.breakpoint', equals: 'xl' } }] }
      ]);
      const tenantCall = prisma.feedback.groupBy.mock.calls.find(
        ([args]) => args.by[0] === 'tenant_human_friendly_id'
      );
      expect(tenantCall[0].where).toEqual(buildActiveFeedbackWhere(filters));
      expect(prisma.feedback.count).toHaveBeenCalledWith({ where: buildActiveFeedbackWhere(filters) });

      // JSON rows are read under the column filters only, then filtered here.
      expect(prisma.feedback.findMany.mock.calls[0][0].where).toEqual(
        buildActiveFeedbackWhere({ route_name: ['hr'] })
      );
      // The breakpoint facet ignores its own filter; the others keep only xl rows.
      expect(result.facets.breakpoint).toEqual([
        { value: 'xl', count: 2 },
        { value: 'sm', count: 1 }
      ]);
      expect(result.facets.theme).toEqual([{ value: 'light', count: 1 }]);
      expect(result.facets.role).toEqual([
        { value: 'PLATFORM_ADMIN', count: 1 },
        { value: 'TENANT_ADMIN', count: 1 }
      ]);
    });
  });
});
