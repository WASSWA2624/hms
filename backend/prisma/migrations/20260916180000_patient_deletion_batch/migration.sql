-- Patient deletion manifest tables for cascade soft-delete / restore / purge.
-- Soft delete writes one batch + item rows for every entity id touched so restore
-- clears deleted_at only for those ids. Permanent delete marks the batch.

CREATE TABLE `patient_deletion_batch` (
  `id` VARCHAR(36) NOT NULL,
  `human_friendly_id` VARCHAR(32) NULL,
  `tenant_id` VARCHAR(36) NOT NULL,
  `facility_id` VARCHAR(36) NULL,
  `patient_id` VARCHAR(36) NOT NULL,
  `deleted_by_user_id` VARCHAR(36) NULL,
  `deleted_at` DATETIME(3) NOT NULL,
  `restored_at` DATETIME(3) NULL,
  `permanently_deleted_at` DATETIME(3) NULL,
  `counts_json` JSON NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3) NOT NULL,
  `batch_deleted_at` DATETIME(3) NULL,
  `version` INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `patient_deletion_batch_item` (
  `id` VARCHAR(36) NOT NULL,
  `batch_id` VARCHAR(36) NOT NULL,
  `entity_model` VARCHAR(80) NOT NULL,
  `entity_id` VARCHAR(36) NOT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE UNIQUE INDEX `patient_deletion_batch_human_friendly_id_key`
  ON `patient_deletion_batch`(`human_friendly_id`);
CREATE INDEX `patient_deletion_batch_tenant_id_idx`
  ON `patient_deletion_batch`(`tenant_id`);
CREATE INDEX `patient_deletion_batch_facility_id_idx`
  ON `patient_deletion_batch`(`facility_id`);
CREATE INDEX `patient_deletion_batch_patient_id_idx`
  ON `patient_deletion_batch`(`patient_id`);
CREATE INDEX `patient_deletion_batch_deleted_at_idx`
  ON `patient_deletion_batch`(`deleted_at`);
CREATE INDEX `patient_deletion_batch_restored_at_idx`
  ON `patient_deletion_batch`(`restored_at`);
CREATE INDEX `patient_deletion_batch_permanently_deleted_at_idx`
  ON `patient_deletion_batch`(`permanently_deleted_at`);
CREATE INDEX `patient_deletion_batch_batch_deleted_at_idx`
  ON `patient_deletion_batch`(`batch_deleted_at`);

CREATE INDEX `patient_deletion_batch_item_batch_id_idx`
  ON `patient_deletion_batch_item`(`batch_id`);
CREATE INDEX `patient_deletion_batch_item_entity_model_entity_id_idx`
  ON `patient_deletion_batch_item`(`entity_model`, `entity_id`);

ALTER TABLE `patient_deletion_batch`
  ADD CONSTRAINT `patient_deletion_batch_tenant_id_fkey`
  FOREIGN KEY (`tenant_id`) REFERENCES `tenant`(`id`)
  ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE `patient_deletion_batch`
  ADD CONSTRAINT `patient_deletion_batch_facility_id_fkey`
  FOREIGN KEY (`facility_id`) REFERENCES `facility`(`id`)
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE `patient_deletion_batch`
  ADD CONSTRAINT `patient_deletion_batch_patient_id_fkey`
  FOREIGN KEY (`patient_id`) REFERENCES `patient`(`id`)
  ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE `patient_deletion_batch`
  ADD CONSTRAINT `patient_deletion_batch_deleted_by_user_id_fkey`
  FOREIGN KEY (`deleted_by_user_id`) REFERENCES `user`(`id`)
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE `patient_deletion_batch_item`
  ADD CONSTRAINT `patient_deletion_batch_item_batch_id_fkey`
  FOREIGN KEY (`batch_id`) REFERENCES `patient_deletion_batch`(`id`)
  ON DELETE CASCADE ON UPDATE CASCADE;
