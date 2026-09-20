-- Backfill: give every facility that already runs a pharmacy the two locations
-- the workflow assumes, and attach its existing inventory to them.
--
-- Existing stock was dispensed against hospital prescriptions, so it becomes
-- the Hospital Pharmacy balance. The Main Pharmacy starts empty and owns
-- procurement from here on; stock reaches the Hospital Pharmacy through a stock
-- order and its transfer legs, never by editing a balance directly.
--
-- Re-runnable: every insert is guarded on the target row not already existing.

-- --------------------------------------------------------- Main Pharmacy row

INSERT INTO `pharmacy_location` (
  `id`, `tenant_id`, `facility_id`, `name`, `code`, `kind`,
  `is_active`, `is_default`, `handles_procurement`, `handles_walk_in`,
  `handles_prescriptions`, `created_at`, `updated_at`
)
SELECT
  UUID(), f.`tenant_id`, f.`id`, 'Main Pharmacy', 'MAIN', 'MAIN',
  true, true, true, true,
  false, NOW(3), NOW(3)
FROM `facility` f
WHERE f.`deleted_at` IS NULL
  AND EXISTS (
    SELECT 1 FROM `inventory_stock` s
    WHERE s.`facility_id` = f.`id` AND s.`deleted_at` IS NULL
    UNION ALL
    SELECT 1 FROM `pharmacy_storage_room` r
    WHERE r.`facility_id` = f.`id` AND r.`deleted_at` IS NULL
    UNION ALL
    SELECT 1 FROM `facility_pharmacy_offering` o
    WHERE o.`facility_id` = f.`id` AND o.`deleted_at` IS NULL
  )
  AND NOT EXISTS (
    SELECT 1 FROM `pharmacy_location` p
    WHERE p.`facility_id` = f.`id` AND p.`kind` = 'MAIN' AND p.`deleted_at` IS NULL
  );

-- ----------------------------------------------------- Hospital Pharmacy row

INSERT INTO `pharmacy_location` (
  `id`, `tenant_id`, `facility_id`, `name`, `code`, `kind`,
  `is_active`, `is_default`, `handles_procurement`, `handles_walk_in`,
  `handles_prescriptions`, `supplied_by_location_id`, `created_at`, `updated_at`
)
SELECT
  UUID(), f.`tenant_id`, f.`id`, 'Hospital Pharmacy', 'HOSPITAL', 'HOSPITAL',
  true, true, false, false,
  true,
  (
    SELECT m.`id` FROM `pharmacy_location` m
    WHERE m.`facility_id` = f.`id` AND m.`kind` = 'MAIN' AND m.`deleted_at` IS NULL
    LIMIT 1
  ),
  NOW(3), NOW(3)
FROM `facility` f
WHERE f.`deleted_at` IS NULL
  AND EXISTS (
    SELECT 1 FROM `pharmacy_location` m
    WHERE m.`facility_id` = f.`id` AND m.`kind` = 'MAIN' AND m.`deleted_at` IS NULL
  )
  AND NOT EXISTS (
    SELECT 1 FROM `pharmacy_location` h
    WHERE h.`facility_id` = f.`id` AND h.`kind` = 'HOSPITAL' AND h.`deleted_at` IS NULL
  );

-- ------------------------------------- existing balances -> Hospital Pharmacy

UPDATE `inventory_stock` s
JOIN `pharmacy_location` h
  ON h.`facility_id` = s.`facility_id`
 AND h.`kind` = 'HOSPITAL'
 AND h.`deleted_at` IS NULL
SET s.`pharmacy_location_id` = h.`id`
WHERE s.`pharmacy_location_id` IS NULL
  AND s.`deleted_at` IS NULL;

UPDATE `pharmacy_storage_room` r
JOIN `pharmacy_location` h
  ON h.`facility_id` = r.`facility_id`
 AND h.`kind` = 'HOSPITAL'
 AND h.`deleted_at` IS NULL
SET r.`pharmacy_location_id` = h.`id`
WHERE r.`pharmacy_location_id` IS NULL
  AND r.`deleted_at` IS NULL;

UPDATE `drug_batch` b
JOIN `pharmacy_storage_room` r ON r.`id` = b.`storage_room_id`
SET b.`pharmacy_location_id` = r.`pharmacy_location_id`
WHERE b.`pharmacy_location_id` IS NULL
  AND r.`pharmacy_location_id` IS NOT NULL
  AND b.`deleted_at` IS NULL;

-- Historical movements and adjustments belong to the balance they touched.
UPDATE `stock_movement` m
JOIN `pharmacy_location` h
  ON h.`facility_id` = m.`facility_id`
 AND h.`kind` = 'HOSPITAL'
 AND h.`deleted_at` IS NULL
SET m.`pharmacy_location_id` = h.`id`
WHERE m.`pharmacy_location_id` IS NULL
  AND m.`deleted_at` IS NULL;

UPDATE `stock_adjustment` a
JOIN `pharmacy_location` h
  ON h.`facility_id` = a.`facility_id`
 AND h.`kind` = 'HOSPITAL'
 AND h.`deleted_at` IS NULL
SET a.`pharmacy_location_id` = h.`id`
WHERE a.`pharmacy_location_id` IS NULL
  AND a.`deleted_at` IS NULL;

-- ------------------------------------------- route existing pharmacy orders

-- Hospital prescriptions go to the Hospital Pharmacy of the patient facility.
UPDATE `pharmacy_order` o
JOIN `patient` p ON p.`id` = o.`patient_id`
JOIN `pharmacy_location` h
  ON h.`facility_id` = p.`facility_id`
 AND h.`kind` = 'HOSPITAL'
 AND h.`deleted_at` IS NULL
SET o.`pharmacy_location_id` = h.`id`
WHERE o.`pharmacy_location_id` IS NULL
  AND o.`origin` = 'HOSPITAL'
  AND o.`deleted_at` IS NULL;

-- ---------------------------------------- seed per-location prices from drug

-- `drug.unit_price` was the walk-in price and `drug.transfer_unit_price` the
-- price charged to the facility, so they seed the Main Pharmacy row directly.
INSERT INTO `pharmacy_location_price` (
  `id`, `tenant_id`, `pharmacy_location_id`, `drug_id`,
  `sell_price`, `supply_price`, `acquisition_cost`, `currency`,
  `is_active`, `created_at`, `updated_at`
)
SELECT
  UUID(), m.`tenant_id`, m.`id`, d.`id`,
  d.`unit_price`, d.`transfer_unit_price`, d.`buy_unit_price`, d.`currency`,
  true, NOW(3), NOW(3)
FROM `pharmacy_location` m
JOIN `drug` d
  ON d.`tenant_id` = m.`tenant_id`
 AND d.`deleted_at` IS NULL
WHERE m.`kind` = 'MAIN'
  AND m.`deleted_at` IS NULL
  AND (d.`unit_price` IS NOT NULL OR d.`transfer_unit_price` IS NOT NULL OR d.`buy_unit_price` IS NOT NULL)
  AND NOT EXISTS (
    SELECT 1 FROM `pharmacy_location_price` e
    WHERE e.`pharmacy_location_id` = m.`id` AND e.`drug_id` = d.`id` AND e.`deleted_at` IS NULL
  );

-- The facility offering price was the price charged to patients, so it seeds
-- the Hospital Pharmacy sell price. Its acquisition cost is what Main charges
-- it (the supply price), never the Main walk-in price.
INSERT INTO `pharmacy_location_price` (
  `id`, `tenant_id`, `pharmacy_location_id`, `drug_id`,
  `sell_price`, `supply_price`, `acquisition_cost`, `currency`,
  `is_active`, `created_at`, `updated_at`
)
SELECT
  UUID(), h.`tenant_id`, h.`id`, o.`drug_id`,
  o.`unit_price`, NULL, d.`transfer_unit_price`, COALESCE(o.`currency`, d.`currency`),
  true, NOW(3), NOW(3)
FROM `pharmacy_location` h
JOIN `facility_pharmacy_offering` o
  ON o.`facility_id` = h.`facility_id`
 AND o.`deleted_at` IS NULL
JOIN `drug` d ON d.`id` = o.`drug_id`
WHERE h.`kind` = 'HOSPITAL'
  AND h.`deleted_at` IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM `pharmacy_location_price` e
    WHERE e.`pharmacy_location_id` = h.`id` AND e.`drug_id` = o.`drug_id` AND e.`deleted_at` IS NULL
  );
