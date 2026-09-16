-- Feedback filter indexes: "Download feedback" and "Clear feedback" filter by
-- tenant, facility, plan tier, subscription status, screen, platform,
-- environment, app version, and locale, and group by them for filter choices.
-- Index-only; no data changes.
--
-- Tenants and facilities are filtered by their public ids as snapshotted on
-- each record, so feedback from a tenant that was later removed stays
-- filterable.
--
-- Guarded with information_schema + PREPARE because MySQL has no
-- `CREATE INDEX IF NOT EXISTS`, and Prisma cannot run DELIMITER.

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback'
    AND INDEX_NAME = 'feedback_tenant_human_friendly_id_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `feedback_tenant_human_friendly_id_idx` ON `feedback`(`tenant_human_friendly_id`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback'
    AND INDEX_NAME = 'feedback_facility_human_friendly_id_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `feedback_facility_human_friendly_id_idx` ON `feedback`(`facility_human_friendly_id`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback'
    AND INDEX_NAME = 'feedback_subscription_tier_code_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `feedback_subscription_tier_code_idx` ON `feedback`(`subscription_tier_code`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback'
    AND INDEX_NAME = 'feedback_subscription_status_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `feedback_subscription_status_idx` ON `feedback`(`subscription_status`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback'
    AND INDEX_NAME = 'feedback_route_name_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `feedback_route_name_idx` ON `feedback`(`route_name`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback'
    AND INDEX_NAME = 'feedback_client_platform_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `feedback_client_platform_idx` ON `feedback`(`client_platform`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback'
    AND INDEX_NAME = 'feedback_app_environment_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `feedback_app_environment_idx` ON `feedback`(`app_environment`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback'
    AND INDEX_NAME = 'feedback_app_version_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `feedback_app_version_idx` ON `feedback`(`app_version`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback'
    AND INDEX_NAME = 'feedback_locale_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `feedback_locale_idx` ON `feedback`(`locale`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
