-- Pharmacy locations: Main Pharmacy and Hospital Pharmacy as separate
-- stock-holding, price-setting dispensing points inside a facility.
--
-- Inventory, pricing and permissions are all keyed on `pharmacy_location_id`
-- rather than duplicated into a second pharmacy module, so a Branch, Theatre or
-- Ward pharmacy is a new row rather than new code.
--
-- Guarded with information_schema + PREPARE because MySQL has no
-- `ADD COLUMN IF NOT EXISTS` / `CREATE INDEX IF NOT EXISTS`, and Prisma cannot
-- run DELIMITER.

-- ---------------------------------------------------------------- new tables

CREATE TABLE IF NOT EXISTS `pharmacy_location` (
  `id` VARCHAR(36) NOT NULL,
  `human_friendly_id` VARCHAR(32) NULL,
  `tenant_id` VARCHAR(36) NOT NULL,
  `facility_id` VARCHAR(36) NOT NULL,
  `name` VARCHAR(255) NOT NULL,
  `code` VARCHAR(80) NULL,
  `kind` ENUM('MAIN','HOSPITAL','BRANCH','THEATRE','WARD','OTHER') NOT NULL DEFAULT 'OTHER',
  `is_active` BOOLEAN NOT NULL DEFAULT true,
  `is_default` BOOLEAN NOT NULL DEFAULT false,
  `handles_procurement` BOOLEAN NOT NULL DEFAULT false,
  `handles_walk_in` BOOLEAN NOT NULL DEFAULT false,
  `handles_prescriptions` BOOLEAN NOT NULL DEFAULT false,
  `supplied_by_location_id` VARCHAR(36) NULL,
  `currency` VARCHAR(10) NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3) NOT NULL,
  `deleted_at` DATETIME(3) NULL,
  `version` INTEGER NOT NULL DEFAULT 1,
  UNIQUE INDEX `pharmacy_location_facility_code_key`(`facility_id`, `code`),
  INDEX `pharmacy_location_tenant_id_idx`(`tenant_id`),
  INDEX `pharmacy_location_facility_id_idx`(`facility_id`),
  INDEX `pharmacy_location_kind_idx`(`kind`),
  INDEX `pharmacy_location_is_active_idx`(`is_active`),
  INDEX `pharmacy_location_is_default_idx`(`is_default`),
  INDEX `pharmacy_location_supplied_by_location_id_idx`(`supplied_by_location_id`),
  INDEX `pharmacy_location_deleted_at_idx`(`deleted_at`),
  INDEX `pharmacy_location_human_friendly_id_idx`(`human_friendly_id`),
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `pharmacy_location_user` (
  `id` VARCHAR(36) NOT NULL,
  `human_friendly_id` VARCHAR(32) NULL,
  `tenant_id` VARCHAR(36) NOT NULL,
  `pharmacy_location_id` VARCHAR(36) NOT NULL,
  `user_id` VARCHAR(36) NOT NULL,
  `access_level` ENUM('VIEW','DISPENSE','MANAGE') NOT NULL DEFAULT 'DISPENSE',
  `can_view_supplier_stock` BOOLEAN NOT NULL DEFAULT true,
  `is_active` BOOLEAN NOT NULL DEFAULT true,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3) NOT NULL,
  `deleted_at` DATETIME(3) NULL,
  `version` INTEGER NOT NULL DEFAULT 1,
  UNIQUE INDEX `pharmacy_location_user_key`(`pharmacy_location_id`, `user_id`),
  INDEX `pharmacy_location_user_tenant_id_idx`(`tenant_id`),
  INDEX `pharmacy_location_user_pharmacy_location_id_idx`(`pharmacy_location_id`),
  INDEX `pharmacy_location_user_user_id_idx`(`user_id`),
  INDEX `pharmacy_location_user_access_level_idx`(`access_level`),
  INDEX `pharmacy_location_user_is_active_idx`(`is_active`),
  INDEX `pharmacy_location_user_deleted_at_idx`(`deleted_at`),
  INDEX `pharmacy_location_user_human_friendly_id_idx`(`human_friendly_id`),
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `pharmacy_location_price` (
  `id` VARCHAR(36) NOT NULL,
  `human_friendly_id` VARCHAR(32) NULL,
  `tenant_id` VARCHAR(36) NOT NULL,
  `pharmacy_location_id` VARCHAR(36) NOT NULL,
  `drug_id` VARCHAR(36) NOT NULL,
  `sell_price` DECIMAL(12, 2) NULL,
  `supply_price` DECIMAL(12, 2) NULL,
  `acquisition_cost` DECIMAL(12, 2) NULL,
  `currency` VARCHAR(10) NULL,
  `is_active` BOOLEAN NOT NULL DEFAULT true,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3) NOT NULL,
  `deleted_at` DATETIME(3) NULL,
  `version` INTEGER NOT NULL DEFAULT 1,
  UNIQUE INDEX `pharmacy_location_price_key`(`pharmacy_location_id`, `drug_id`),
  INDEX `pharmacy_location_price_tenant_id_idx`(`tenant_id`),
  INDEX `pharmacy_location_price_pharmacy_location_id_idx`(`pharmacy_location_id`),
  INDEX `pharmacy_location_price_drug_id_idx`(`drug_id`),
  INDEX `pharmacy_location_price_is_active_idx`(`is_active`),
  INDEX `pharmacy_location_price_deleted_at_idx`(`deleted_at`),
  INDEX `pharmacy_location_price_human_friendly_id_idx`(`human_friendly_id`),
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `pharmacy_stock_order` (
  `id` VARCHAR(36) NOT NULL,
  `human_friendly_id` VARCHAR(32) NULL,
  `tenant_id` VARCHAR(36) NOT NULL,
  `requesting_location_id` VARCHAR(36) NOT NULL,
  `supplying_location_id` VARCHAR(36) NOT NULL,
  `status` ENUM('DRAFT','SUBMITTED','UNDER_REVIEW','APPROVED','PARTIALLY_APPROVED','REJECTED','ISSUED','PARTIALLY_RECEIVED','RECEIVED','CANCELLED') NOT NULL DEFAULT 'DRAFT',
  `requested_by_user_id` VARCHAR(36) NULL,
  `reviewed_by_user_id` VARCHAR(36) NULL,
  `issued_by_user_id` VARCHAR(36) NULL,
  `received_by_user_id` VARCHAR(36) NULL,
  `notes` TEXT NULL,
  `review_notes` TEXT NULL,
  `currency` VARCHAR(10) NULL,
  `supply_total` DECIMAL(14, 2) NULL,
  `submitted_at` DATETIME(3) NULL,
  `reviewed_at` DATETIME(3) NULL,
  `issued_at` DATETIME(3) NULL,
  `received_at` DATETIME(3) NULL,
  `cancelled_at` DATETIME(3) NULL,
  `transfer_group_id` VARCHAR(36) NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3) NOT NULL,
  `deleted_at` DATETIME(3) NULL,
  `version` INTEGER NOT NULL DEFAULT 1,
  INDEX `pharmacy_stock_order_tenant_id_idx`(`tenant_id`),
  INDEX `pharmacy_stock_order_requesting_location_id_idx`(`requesting_location_id`),
  INDEX `pharmacy_stock_order_supplying_location_id_idx`(`supplying_location_id`),
  INDEX `pharmacy_stock_order_status_idx`(`status`),
  INDEX `pharmacy_stock_order_submitted_at_idx`(`submitted_at`),
  INDEX `pharmacy_stock_order_transfer_group_id_idx`(`transfer_group_id`),
  INDEX `pharmacy_stock_order_deleted_at_idx`(`deleted_at`),
  INDEX `pharmacy_stock_order_human_friendly_id_idx`(`human_friendly_id`),
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `pharmacy_stock_order_item` (
  `id` VARCHAR(36) NOT NULL,
  `human_friendly_id` VARCHAR(32) NULL,
  `stock_order_id` VARCHAR(36) NOT NULL,
  `drug_id` VARCHAR(36) NOT NULL,
  `inventory_item_id` VARCHAR(36) NULL,
  `requested_quantity` INTEGER NOT NULL DEFAULT 0,
  `approved_quantity` INTEGER NULL,
  `issued_quantity` INTEGER NOT NULL DEFAULT 0,
  `received_quantity` INTEGER NOT NULL DEFAULT 0,
  `unit_supply_price` DECIMAL(12, 2) NULL,
  `currency` VARCHAR(10) NULL,
  `status` ENUM('REQUESTED','APPROVED','PARTIALLY_APPROVED','REJECTED','ISSUED','RECEIVED','CANCELLED') NOT NULL DEFAULT 'REQUESTED',
  `notes` TEXT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3) NOT NULL,
  `deleted_at` DATETIME(3) NULL,
  `version` INTEGER NOT NULL DEFAULT 1,
  INDEX `pharmacy_stock_order_item_stock_order_id_idx`(`stock_order_id`),
  INDEX `pharmacy_stock_order_item_drug_id_idx`(`drug_id`),
  INDEX `pharmacy_stock_order_item_inventory_item_id_idx`(`inventory_item_id`),
  INDEX `pharmacy_stock_order_item_status_idx`(`status`),
  INDEX `pharmacy_stock_order_item_deleted_at_idx`(`deleted_at`),
  INDEX `pharmacy_stock_order_item_human_friendly_id_idx`(`human_friendly_id`),
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- ------------------------------------------------- location columns on stock

SET @exists := (
  SELECT COUNT(1) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'inventory_stock'
    AND COLUMN_NAME = 'pharmacy_location_id'
);
SET @sql := IF(@exists = 0,
  'ALTER TABLE `inventory_stock` ADD COLUMN `pharmacy_location_id` VARCHAR(36) NULL',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'inventory_stock'
    AND INDEX_NAME = 'inventory_stock_pharmacy_location_id_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `inventory_stock_pharmacy_location_id_idx` ON `inventory_stock`(`pharmacy_location_id`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'inventory_stock'
    AND INDEX_NAME = 'inventory_stock_inventory_item_id_pharmacy_location_id_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `inventory_stock_inventory_item_id_pharmacy_location_id_idx` ON `inventory_stock`(`inventory_item_id`, `pharmacy_location_id`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ---------------------------------------------- location columns on movement

SET @exists := (
  SELECT COUNT(1) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'stock_movement'
    AND COLUMN_NAME = 'pharmacy_location_id'
);
SET @sql := IF(@exists = 0,
  'ALTER TABLE `stock_movement` ADD COLUMN `pharmacy_location_id` VARCHAR(36) NULL, ADD COLUMN `from_pharmacy_location_id` VARCHAR(36) NULL, ADD COLUMN `to_pharmacy_location_id` VARCHAR(36) NULL',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'stock_movement'
    AND INDEX_NAME = 'stock_movement_pharmacy_location_id_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `stock_movement_pharmacy_location_id_idx` ON `stock_movement`(`pharmacy_location_id`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'stock_movement'
    AND INDEX_NAME = 'stock_movement_from_pharmacy_location_id_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `stock_movement_from_pharmacy_location_id_idx` ON `stock_movement`(`from_pharmacy_location_id`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'stock_movement'
    AND INDEX_NAME = 'stock_movement_to_pharmacy_location_id_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `stock_movement_to_pharmacy_location_id_idx` ON `stock_movement`(`to_pharmacy_location_id`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- -------------------------------------------- location column on adjustment

SET @exists := (
  SELECT COUNT(1) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'stock_adjustment'
    AND COLUMN_NAME = 'pharmacy_location_id'
);
SET @sql := IF(@exists = 0,
  'ALTER TABLE `stock_adjustment` ADD COLUMN `pharmacy_location_id` VARCHAR(36) NULL',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'stock_adjustment'
    AND INDEX_NAME = 'stock_adjustment_pharmacy_location_id_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `stock_adjustment_pharmacy_location_id_idx` ON `stock_adjustment`(`pharmacy_location_id`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ------------------------------------------------ location column on batches

SET @exists := (
  SELECT COUNT(1) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'drug_batch'
    AND COLUMN_NAME = 'pharmacy_location_id'
);
SET @sql := IF(@exists = 0,
  'ALTER TABLE `drug_batch` ADD COLUMN `pharmacy_location_id` VARCHAR(36) NULL',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'drug_batch'
    AND INDEX_NAME = 'drug_batch_pharmacy_location_id_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `drug_batch_pharmacy_location_id_idx` ON `drug_batch`(`pharmacy_location_id`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ------------------------------------------ location column on storage rooms

SET @exists := (
  SELECT COUNT(1) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pharmacy_storage_room'
    AND COLUMN_NAME = 'pharmacy_location_id'
);
SET @sql := IF(@exists = 0,
  'ALTER TABLE `pharmacy_storage_room` ADD COLUMN `pharmacy_location_id` VARCHAR(36) NULL',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pharmacy_storage_room'
    AND INDEX_NAME = 'pharmacy_storage_room_pharmacy_location_id_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `pharmacy_storage_room_pharmacy_location_id_idx` ON `pharmacy_storage_room`(`pharmacy_location_id`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ------------------------------------- origin + location on pharmacy orders

SET @exists := (
  SELECT COUNT(1) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pharmacy_order'
    AND COLUMN_NAME = 'origin'
);
SET @sql := IF(@exists = 0,
  'ALTER TABLE `pharmacy_order` ADD COLUMN `origin` ENUM(''HOSPITAL'',''WALK_IN'') NOT NULL DEFAULT ''HOSPITAL'', ADD COLUMN `pharmacy_location_id` VARCHAR(36) NULL',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- Existing anonymous orders had no patient and no encounter: those were the
-- walk-in sales, so they keep their meaning after the column is introduced.
UPDATE `pharmacy_order`
SET `origin` = 'WALK_IN'
WHERE `patient_id` IS NULL AND `encounter_id` IS NULL;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pharmacy_order'
    AND INDEX_NAME = 'pharmacy_order_origin_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `pharmacy_order_origin_idx` ON `pharmacy_order`(`origin`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pharmacy_order'
    AND INDEX_NAME = 'pharmacy_order_pharmacy_location_id_idx'
);
SET @sql := IF(@exists = 0,
  'CREATE INDEX `pharmacy_order_pharmacy_location_id_idx` ON `pharmacy_order`(`pharmacy_location_id`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ----------------------------------------------------------- foreign keys

SET @exists := (
  SELECT COUNT(1) FROM information_schema.TABLE_CONSTRAINTS
  WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'pharmacy_location'
    AND CONSTRAINT_NAME = 'pharmacy_location_tenant_id_fkey'
);
SET @sql := IF(@exists = 0,
  'ALTER TABLE `pharmacy_location`
     ADD CONSTRAINT `pharmacy_location_tenant_id_fkey` FOREIGN KEY (`tenant_id`) REFERENCES `tenant`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE,
     ADD CONSTRAINT `pharmacy_location_facility_id_fkey` FOREIGN KEY (`facility_id`) REFERENCES `facility`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE,
     ADD CONSTRAINT `pharmacy_location_supplied_by_location_id_fkey` FOREIGN KEY (`supplied_by_location_id`) REFERENCES `pharmacy_location`(`id`) ON DELETE SET NULL ON UPDATE CASCADE',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.TABLE_CONSTRAINTS
  WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'pharmacy_location_user'
    AND CONSTRAINT_NAME = 'pharmacy_location_user_tenant_id_fkey'
);
SET @sql := IF(@exists = 0,
  'ALTER TABLE `pharmacy_location_user`
     ADD CONSTRAINT `pharmacy_location_user_tenant_id_fkey` FOREIGN KEY (`tenant_id`) REFERENCES `tenant`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE,
     ADD CONSTRAINT `pharmacy_location_user_pharmacy_location_id_fkey` FOREIGN KEY (`pharmacy_location_id`) REFERENCES `pharmacy_location`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE,
     ADD CONSTRAINT `pharmacy_location_user_user_id_fkey` FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.TABLE_CONSTRAINTS
  WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'pharmacy_location_price'
    AND CONSTRAINT_NAME = 'pharmacy_location_price_tenant_id_fkey'
);
SET @sql := IF(@exists = 0,
  'ALTER TABLE `pharmacy_location_price`
     ADD CONSTRAINT `pharmacy_location_price_tenant_id_fkey` FOREIGN KEY (`tenant_id`) REFERENCES `tenant`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE,
     ADD CONSTRAINT `pharmacy_location_price_pharmacy_location_id_fkey` FOREIGN KEY (`pharmacy_location_id`) REFERENCES `pharmacy_location`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE,
     ADD CONSTRAINT `pharmacy_location_price_drug_id_fkey` FOREIGN KEY (`drug_id`) REFERENCES `drug`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.TABLE_CONSTRAINTS
  WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'pharmacy_stock_order'
    AND CONSTRAINT_NAME = 'pharmacy_stock_order_tenant_id_fkey'
);
SET @sql := IF(@exists = 0,
  'ALTER TABLE `pharmacy_stock_order`
     ADD CONSTRAINT `pharmacy_stock_order_tenant_id_fkey` FOREIGN KEY (`tenant_id`) REFERENCES `tenant`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE,
     ADD CONSTRAINT `pharmacy_stock_order_requesting_location_id_fkey` FOREIGN KEY (`requesting_location_id`) REFERENCES `pharmacy_location`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE,
     ADD CONSTRAINT `pharmacy_stock_order_supplying_location_id_fkey` FOREIGN KEY (`supplying_location_id`) REFERENCES `pharmacy_location`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE,
     ADD CONSTRAINT `pharmacy_stock_order_requested_by_user_id_fkey` FOREIGN KEY (`requested_by_user_id`) REFERENCES `user`(`id`) ON DELETE SET NULL ON UPDATE CASCADE,
     ADD CONSTRAINT `pharmacy_stock_order_reviewed_by_user_id_fkey` FOREIGN KEY (`reviewed_by_user_id`) REFERENCES `user`(`id`) ON DELETE SET NULL ON UPDATE CASCADE,
     ADD CONSTRAINT `pharmacy_stock_order_issued_by_user_id_fkey` FOREIGN KEY (`issued_by_user_id`) REFERENCES `user`(`id`) ON DELETE SET NULL ON UPDATE CASCADE,
     ADD CONSTRAINT `pharmacy_stock_order_received_by_user_id_fkey` FOREIGN KEY (`received_by_user_id`) REFERENCES `user`(`id`) ON DELETE SET NULL ON UPDATE CASCADE',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.TABLE_CONSTRAINTS
  WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'pharmacy_stock_order_item'
    AND CONSTRAINT_NAME = 'pharmacy_stock_order_item_stock_order_id_fkey'
);
SET @sql := IF(@exists = 0,
  'ALTER TABLE `pharmacy_stock_order_item`
     ADD CONSTRAINT `pharmacy_stock_order_item_stock_order_id_fkey` FOREIGN KEY (`stock_order_id`) REFERENCES `pharmacy_stock_order`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE,
     ADD CONSTRAINT `pharmacy_stock_order_item_drug_id_fkey` FOREIGN KEY (`drug_id`) REFERENCES `drug`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE,
     ADD CONSTRAINT `pharmacy_stock_order_item_inventory_item_id_fkey` FOREIGN KEY (`inventory_item_id`) REFERENCES `inventory_item`(`id`) ON DELETE SET NULL ON UPDATE CASCADE',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.TABLE_CONSTRAINTS
  WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'inventory_stock'
    AND CONSTRAINT_NAME = 'inventory_stock_pharmacy_location_id_fkey'
);
SET @sql := IF(@exists = 0,
  'ALTER TABLE `inventory_stock` ADD CONSTRAINT `inventory_stock_pharmacy_location_id_fkey` FOREIGN KEY (`pharmacy_location_id`) REFERENCES `pharmacy_location`(`id`) ON DELETE SET NULL ON UPDATE CASCADE',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.TABLE_CONSTRAINTS
  WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'stock_movement'
    AND CONSTRAINT_NAME = 'stock_movement_pharmacy_location_id_fkey'
);
SET @sql := IF(@exists = 0,
  'ALTER TABLE `stock_movement`
     ADD CONSTRAINT `stock_movement_pharmacy_location_id_fkey` FOREIGN KEY (`pharmacy_location_id`) REFERENCES `pharmacy_location`(`id`) ON DELETE SET NULL ON UPDATE CASCADE,
     ADD CONSTRAINT `stock_movement_from_pharmacy_location_id_fkey` FOREIGN KEY (`from_pharmacy_location_id`) REFERENCES `pharmacy_location`(`id`) ON DELETE SET NULL ON UPDATE CASCADE,
     ADD CONSTRAINT `stock_movement_to_pharmacy_location_id_fkey` FOREIGN KEY (`to_pharmacy_location_id`) REFERENCES `pharmacy_location`(`id`) ON DELETE SET NULL ON UPDATE CASCADE',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.TABLE_CONSTRAINTS
  WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'stock_adjustment'
    AND CONSTRAINT_NAME = 'stock_adjustment_pharmacy_location_id_fkey'
);
SET @sql := IF(@exists = 0,
  'ALTER TABLE `stock_adjustment` ADD CONSTRAINT `stock_adjustment_pharmacy_location_id_fkey` FOREIGN KEY (`pharmacy_location_id`) REFERENCES `pharmacy_location`(`id`) ON DELETE SET NULL ON UPDATE CASCADE',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.TABLE_CONSTRAINTS
  WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'drug_batch'
    AND CONSTRAINT_NAME = 'drug_batch_pharmacy_location_id_fkey'
);
SET @sql := IF(@exists = 0,
  'ALTER TABLE `drug_batch` ADD CONSTRAINT `drug_batch_pharmacy_location_id_fkey` FOREIGN KEY (`pharmacy_location_id`) REFERENCES `pharmacy_location`(`id`) ON DELETE SET NULL ON UPDATE CASCADE',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.TABLE_CONSTRAINTS
  WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'pharmacy_storage_room'
    AND CONSTRAINT_NAME = 'pharmacy_storage_room_pharmacy_location_id_fkey'
);
SET @sql := IF(@exists = 0,
  'ALTER TABLE `pharmacy_storage_room` ADD CONSTRAINT `pharmacy_storage_room_pharmacy_location_id_fkey` FOREIGN KEY (`pharmacy_location_id`) REFERENCES `pharmacy_location`(`id`) ON DELETE SET NULL ON UPDATE CASCADE',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists := (
  SELECT COUNT(1) FROM information_schema.TABLE_CONSTRAINTS
  WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'pharmacy_order'
    AND CONSTRAINT_NAME = 'pharmacy_order_pharmacy_location_id_fkey'
);
SET @sql := IF(@exists = 0,
  'ALTER TABLE `pharmacy_order` ADD CONSTRAINT `pharmacy_order_pharmacy_location_id_fkey` FOREIGN KEY (`pharmacy_location_id`) REFERENCES `pharmacy_location`(`id`) ON DELETE SET NULL ON UPDATE CASCADE',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
