-- Application feedback: the system of record for "Give us feedback".
--
-- One row per submission from any screen, signed in or not. Identity, tenant,
-- facility, subscription, and role columns are point-in-time snapshots taken
-- at submission, so an export still reads correctly after a rename, a plan
-- change, or an account removal. The foreign keys are nullable and SET NULL on
-- delete for the same reason. Anonymous rows carry no identity, only page and
-- technical context.
--
-- "Clear feedback" soft-deletes (`deleted_at`, `deleted_by_user_id`); exports
-- and counts read active rows only.
--
-- Guarded with information_schema + PREPARE because the fleet spans MariaDB
-- builds without `CREATE INDEX IF NOT EXISTS`, and Prisma cannot run DELIMITER.

CREATE TABLE IF NOT EXISTS `feedback` (
  `id` VARCHAR(36) NOT NULL,
  `human_friendly_id` VARCHAR(32) NULL,
  `category` ENUM('GENERAL', 'PROBLEM', 'COMPLAINT', 'SUGGESTION', 'IMPROVEMENT') NOT NULL DEFAULT 'GENERAL',
  `message` TEXT NOT NULL,
  `submitter_type` ENUM('AUTHENTICATED', 'ANONYMOUS') NOT NULL DEFAULT 'ANONYMOUS',
  `user_id` VARCHAR(36) NULL,
  `tenant_id` VARCHAR(36) NULL,
  `facility_id` VARCHAR(36) NULL,
  `user_human_friendly_id` VARCHAR(32) NULL,
  `user_email` VARCHAR(255) NULL,
  `user_name` VARCHAR(255) NULL,
  `user_position_title` VARCHAR(120) NULL,
  `user_roles_json` JSON NULL,
  `user_permissions_json` JSON NULL,
  `tenant_human_friendly_id` VARCHAR(32) NULL,
  `tenant_name` VARCHAR(255) NULL,
  `facility_human_friendly_id` VARCHAR(32) NULL,
  `facility_name` VARCHAR(255) NULL,
  `subscription_plan_code` VARCHAR(80) NULL,
  `subscription_plan_name` VARCHAR(255) NULL,
  `subscription_tier_code` VARCHAR(40) NULL,
  `subscription_status` VARCHAR(40) NULL,
  `route_path` VARCHAR(512) NULL,
  `route_name` VARCHAR(120) NULL,
  `page_url` TEXT NULL,
  `screen_title` VARCHAR(255) NULL,
  `client_platform` VARCHAR(40) NULL,
  `app_version` VARCHAR(64) NULL,
  `app_environment` VARCHAR(40) NULL,
  `locale` VARCHAR(35) NULL,
  `timezone` VARCHAR(64) NULL,
  `user_agent` VARCHAR(512) NULL,
  `ip_address` VARCHAR(45) NULL,
  `client_context_json` JSON NULL,
  `client_submitted_at` DATETIME(3) NULL,
  `submitted_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `deleted_by_user_id` VARCHAR(36) NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3) NOT NULL,
  `deleted_at` DATETIME(3) NULL,
  `version` INTEGER NOT NULL DEFAULT 1,

  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback'
    AND INDEX_NAME = 'feedback_tenant_id_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `feedback_tenant_id_idx` ON `feedback`(`tenant_id`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback'
    AND INDEX_NAME = 'feedback_facility_id_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `feedback_facility_id_idx` ON `feedback`(`facility_id`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback'
    AND INDEX_NAME = 'feedback_user_id_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `feedback_user_id_idx` ON `feedback`(`user_id`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback'
    AND INDEX_NAME = 'feedback_category_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `feedback_category_idx` ON `feedback`(`category`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback'
    AND INDEX_NAME = 'feedback_submitter_type_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `feedback_submitter_type_idx` ON `feedback`(`submitter_type`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback'
    AND INDEX_NAME = 'feedback_submitted_at_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `feedback_submitted_at_idx` ON `feedback`(`submitted_at`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback'
    AND INDEX_NAME = 'feedback_deleted_at_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `feedback_deleted_at_idx` ON `feedback`(`deleted_at`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback'
    AND INDEX_NAME = 'feedback_human_friendly_id_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `feedback_human_friendly_id_idx` ON `feedback`(`human_friendly_id`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.TABLE_CONSTRAINTS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback'
    AND CONSTRAINT_NAME = 'feedback_user_id_fkey'
);
SET @sql := IF(@exists = 0,
  'ALTER TABLE `feedback` ADD CONSTRAINT `feedback_user_id_fkey` FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON DELETE SET NULL ON UPDATE CASCADE',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.TABLE_CONSTRAINTS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback'
    AND CONSTRAINT_NAME = 'feedback_tenant_id_fkey'
);
SET @sql := IF(@exists = 0,
  'ALTER TABLE `feedback` ADD CONSTRAINT `feedback_tenant_id_fkey` FOREIGN KEY (`tenant_id`) REFERENCES `tenant`(`id`) ON DELETE SET NULL ON UPDATE CASCADE',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.TABLE_CONSTRAINTS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback'
    AND CONSTRAINT_NAME = 'feedback_facility_id_fkey'
);
SET @sql := IF(@exists = 0,
  'ALTER TABLE `feedback` ADD CONSTRAINT `feedback_facility_id_fkey` FOREIGN KEY (`facility_id`) REFERENCES `facility`(`id`) ON DELETE SET NULL ON UPDATE CASCADE',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
