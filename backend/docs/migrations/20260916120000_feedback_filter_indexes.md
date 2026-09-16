# Feedback filter indexes (20260916120000)

## Affected tables

- `feedback` (indexes only): "Download feedback" and "Clear feedback" filter
  and count records by these columns, and `GET /api/v1/feedback/facets` groups
  by them to list filter choices.
  - `feedback_tenant_human_friendly_id_idx`, `feedback_facility_human_friendly_id_idx`:
    the `tenant_id` and `facility_id` filters take public ids and match the
    ids snapshotted on each record, so feedback from a tenant or facility that
    was later removed stays filterable.
  - `feedback_subscription_tier_code_idx`, `feedback_subscription_status_idx`:
    the `plan_tier` and `subscription_status` filters.
  - `feedback_route_name_idx`, `feedback_client_platform_idx`,
    `feedback_app_environment_idx`, `feedback_app_version_idx`,
    `feedback_locale_idx`: the `route_name`, `platform`, `app_environment`,
    `app_version`, and `locale` filters.
- No columns or data change. The `role`, `breakpoint`, `theme`,
  `connectivity`, and `orientation` filters read `user_roles_json` and
  `client_context_json` through parameterized JSON filters and need no index.

## Deployment

1. Apply migration `20260916120000_feedback_filter_indexes`
   (`npm run prisma:migrate:deploy`) after `20260914130000_feedback_device_context`.
   Each index is created only when missing, so a re-run is harmless.
2. Deploy application code.
3. Verify `GET /api/v1/feedback/facets` returns filter values, and that
   downloading with tenant, route, and breakpoint filters exports only matching
   rows.

## Recovery

Forward-only and additive. To roll back, add
`rollback_20260916120000_feedback_filter_indexes` dropping the nine indexes
above; queries keep working without them, only slower.
