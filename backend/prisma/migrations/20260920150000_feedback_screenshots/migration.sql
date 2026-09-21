-- Feedback screenshots and scope.
--
-- Two additions to "Give us feedback":
--
-- 1. `feedback`.`scope` records what a report applies to — the screen it was
--    raised from (`SCREEN`, the default and what every existing row means),
--    the whole app (`APP`), or the screens the reporter picked (`SCREENS`,
--    listed in `feedback_scope_screen`).
-- 2. `feedback_screenshot` holds the metadata of images attached to a report.
--    The images themselves live in the storage provider under `storage_key`,
--    encrypted at rest; nothing here is servable on its own.
--
-- Both children are ON DELETE CASCADE: clearing feedback is permanent, and
-- the service deletes the stored images in the same operation, so no blob
-- outlives its row.
--
-- Guarded with information_schema + PREPARE because the fleet spans MySQL and
-- MariaDB builds without `ADD COLUMN IF NOT EXISTS` / `CREATE INDEX IF NOT
-- EXISTS`, and Prisma cannot run DELIMITER.

SET @exists := (
  SELECT COUNT(1) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback'
    AND COLUMN_NAME = 'scope'
);
SET @sql := IF(@exists = 0,
  'ALTER TABLE `feedback` ADD COLUMN `scope` ENUM(''SCREEN'', ''APP'', ''SCREENS'') NOT NULL DEFAULT ''SCREEN'' AFTER `message`',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback'
    AND INDEX_NAME = 'feedback_scope_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `feedback_scope_idx` ON `feedback`(`scope`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

CREATE TABLE IF NOT EXISTS `feedback_scope_screen` (
  `id` VARCHAR(36) NOT NULL,
  `feedback_id` VARCHAR(36) NOT NULL,
  `sequence` INTEGER NOT NULL DEFAULT 1,
  `route_name` VARCHAR(120) NULL,
  `route_path` VARCHAR(512) NULL,
  `screen_title` VARCHAR(255) NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `feedback_screenshot` (
  `id` VARCHAR(36) NOT NULL,
  `feedback_id` VARCHAR(36) NOT NULL,
  `sequence` INTEGER NOT NULL DEFAULT 1,
  `storage_key` VARCHAR(255) NOT NULL,
  `content_type` VARCHAR(80) NOT NULL,
  `byte_size` INTEGER NOT NULL,
  `width` INTEGER NULL,
  `height` INTEGER NULL,
  `caption` VARCHAR(255) NULL,
  `route_path` VARCHAR(512) NULL,
  `route_name` VARCHAR(120) NULL,
  `screen_title` VARCHAR(255) NULL,
  `client_context_json` JSON NULL,
  `captured_at` DATETIME(3) NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback_scope_screen'
    AND INDEX_NAME = 'feedback_scope_screen_feedback_id_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `feedback_scope_screen_feedback_id_idx` ON `feedback_scope_screen`(`feedback_id`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback_scope_screen'
    AND INDEX_NAME = 'feedback_scope_screen_route_name_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `feedback_scope_screen_route_name_idx` ON `feedback_scope_screen`(`route_name`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback_screenshot'
    AND INDEX_NAME = 'feedback_screenshot_feedback_id_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `feedback_screenshot_feedback_id_idx` ON `feedback_screenshot`(`feedback_id`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback_screenshot'
    AND INDEX_NAME = 'feedback_screenshot_route_name_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `feedback_screenshot_route_name_idx` ON `feedback_screenshot`(`route_name`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.TABLE_CONSTRAINTS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback_scope_screen'
    AND CONSTRAINT_NAME = 'feedback_scope_screen_feedback_id_fkey'
);
SET @sql := IF(@exists = 0,
  'ALTER TABLE `feedback_scope_screen` ADD CONSTRAINT `feedback_scope_screen_feedback_id_fkey` FOREIGN KEY (`feedback_id`) REFERENCES `feedback`(`id`) ON DELETE CASCADE ON UPDATE CASCADE',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.TABLE_CONSTRAINTS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback_screenshot'
    AND CONSTRAINT_NAME = 'feedback_screenshot_feedback_id_fkey'
);
SET @sql := IF(@exists = 0,
  'ALTER TABLE `feedback_screenshot` ADD CONSTRAINT `feedback_screenshot_feedback_id_fkey` FOREIGN KEY (`feedback_id`) REFERENCES `feedback`(`id`) ON DELETE CASCADE ON UPDATE CASCADE',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
