-- Feedback device context: the screen size a report came from, so fixes can
-- target specific layouts.
--
-- `device_type` classifies the app window width the way the app lays out:
-- MOBILE below 600 logical px, TABLET 600-1199, DESKTOP 1200 and up.
-- `viewport_*` is that window in logical pixels; `screen_*` is the whole
-- display, so a narrow browser window on a desktop monitor is visible as such.
-- Columns rather than JSON so exports and reports can filter and group by them.
--
-- Guarded with information_schema + PREPARE because MySQL has no
-- `ADD COLUMN IF NOT EXISTS`, and Prisma cannot run DELIMITER.

SET @exists := (
  SELECT COUNT(1) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback'
    AND COLUMN_NAME = 'device_type'
);
SET @sql := IF(@exists = 0,
  'ALTER TABLE `feedback` ADD COLUMN `device_type` ENUM(''MOBILE'', ''TABLET'', ''DESKTOP'') NULL AFTER `client_platform`',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback'
    AND COLUMN_NAME = 'viewport_width'
);
SET @sql := IF(@exists = 0,
  'ALTER TABLE `feedback` ADD COLUMN `viewport_width` INTEGER NULL AFTER `device_type`',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback'
    AND COLUMN_NAME = 'viewport_height'
);
SET @sql := IF(@exists = 0,
  'ALTER TABLE `feedback` ADD COLUMN `viewport_height` INTEGER NULL AFTER `viewport_width`',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback'
    AND COLUMN_NAME = 'screen_width'
);
SET @sql := IF(@exists = 0,
  'ALTER TABLE `feedback` ADD COLUMN `screen_width` INTEGER NULL AFTER `viewport_height`',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback'
    AND COLUMN_NAME = 'screen_height'
);
SET @sql := IF(@exists = 0,
  'ALTER TABLE `feedback` ADD COLUMN `screen_height` INTEGER NULL AFTER `screen_width`',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feedback'
    AND INDEX_NAME = 'feedback_device_type_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `feedback_device_type_idx` ON `feedback`(`device_type`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
