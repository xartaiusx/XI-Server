-- Mochirii Master Level support.
--
-- Retail Master Levels are per-job progression after job mastery.  Mochirii does
-- not currently ship durable Master Level storage in this checkout, so this
-- module stores only the authoritative per-job level needed by packets and
-- gameplay calculations.

CREATE TABLE IF NOT EXISTS `char_master_levels` (
  `charid` int(10) unsigned NOT NULL,
  `jobid` tinyint(2) unsigned NOT NULL,
  `master_level` tinyint(2) unsigned NOT NULL DEFAULT '0',
  `exemplar_points` int(10) unsigned NOT NULL DEFAULT '0',
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`charid`,`jobid`),
  CONSTRAINT `char_master_levels_jobid_chk` CHECK (`jobid` BETWEEN 1 AND 22),
  CONSTRAINT `char_master_levels_level_chk` CHECK (`master_level` <= 50)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
