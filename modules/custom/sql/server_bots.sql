-- Server-wide AI bot persistence and audit tables.
-- Runtime v1 uses dynamic NPC actors backed by these durable records.

CREATE TABLE IF NOT EXISTS `server_bot_profiles` (
    `profile_key` varchar(64) NOT NULL,
    `display_name` varchar(32) NOT NULL,
    `role` varchar(32) NOT NULL,
    `main_job` tinyint unsigned NOT NULL DEFAULT 1,
    `sub_job` tinyint unsigned NOT NULL DEFAULT 0,
    `min_level` tinyint unsigned NOT NULL DEFAULT 1,
    `max_level` tinyint unsigned NOT NULL DEFAULT 99,
    `model_id` smallint unsigned NOT NULL DEFAULT 2430,
    `behavior_profile` varchar(64) NOT NULL DEFAULT 'ambient',
    `gear_profile` varchar(64) NOT NULL DEFAULT 'starter',
    `can_claim` tinyint(1) NOT NULL DEFAULT 0,
    `can_loot` tinyint(1) NOT NULL DEFAULT 0,
    `can_trade` tinyint(1) NOT NULL DEFAULT 0,
    `can_use_auction_house` tinyint(1) NOT NULL DEFAULT 0,
    `enabled` tinyint(1) NOT NULL DEFAULT 1,
    `notes` text NULL,
    PRIMARY KEY (`profile_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

ALTER TABLE `server_bot_profiles` ADD COLUMN IF NOT EXISTS `race` tinyint unsigned NOT NULL DEFAULT 1 AFTER `model_id`;
ALTER TABLE `server_bot_profiles` ADD COLUMN IF NOT EXISTS `nation` tinyint unsigned NOT NULL DEFAULT 0 AFTER `race`;
ALTER TABLE `server_bot_profiles` ADD COLUMN IF NOT EXISTS `home_zone_id` smallint unsigned NOT NULL DEFAULT 0 AFTER `nation`;
ALTER TABLE `server_bot_profiles` ADD COLUMN IF NOT EXISTS `home_x` float NOT NULL DEFAULT 0 AFTER `home_zone_id`;
ALTER TABLE `server_bot_profiles` ADD COLUMN IF NOT EXISTS `home_y` float NOT NULL DEFAULT 0 AFTER `home_x`;
ALTER TABLE `server_bot_profiles` ADD COLUMN IF NOT EXISTS `home_z` float NOT NULL DEFAULT 0 AFTER `home_y`;
ALTER TABLE `server_bot_profiles` ADD COLUMN IF NOT EXISTS `persona_key` varchar(64) NOT NULL DEFAULT 'ambient_adventurer' AFTER `gear_profile`;
ALTER TABLE `server_bot_profiles` ADD COLUMN IF NOT EXISTS `strategy_stack` varchar(255) NOT NULL DEFAULT 'ambient' AFTER `persona_key`;
ALTER TABLE `server_bot_profiles` ADD COLUMN IF NOT EXISTS `route_key` varchar(96) NULL AFTER `strategy_stack`;
ALTER TABLE `server_bot_profiles` ADD COLUMN IF NOT EXISTS `camp_key` varchar(96) NULL AFTER `route_key`;
ALTER TABLE `server_bot_profiles` ADD COLUMN IF NOT EXISTS `mob_group_id` smallint unsigned NOT NULL DEFAULT 1 AFTER `camp_key`;
ALTER TABLE `server_bot_profiles` ADD COLUMN IF NOT EXISTS `mob_group_zone_id` smallint unsigned NOT NULL DEFAULT 210 AFTER `mob_group_id`;
ALTER TABLE `server_bot_profiles` ADD COLUMN IF NOT EXISTS `can_vendor` tinyint(1) NOT NULL DEFAULT 0 AFTER `can_use_auction_house`;
ALTER TABLE `server_bot_profiles` ADD COLUMN IF NOT EXISTS `can_upgrade_gear` tinyint(1) NOT NULL DEFAULT 0 AFTER `can_vendor`;
ALTER TABLE `server_bot_profiles` ADD COLUMN IF NOT EXISTS `can_party` tinyint(1) NOT NULL DEFAULT 0 AFTER `can_upgrade_gear`;
ALTER TABLE `server_bot_profiles` ADD COLUMN IF NOT EXISTS `can_llm_chat` tinyint(1) NOT NULL DEFAULT 0 AFTER `can_party`;
ALTER TABLE `server_bot_profiles` ADD COLUMN IF NOT EXISTS `commandable` tinyint(1) NOT NULL DEFAULT 0 AFTER `can_llm_chat`;
ALTER TABLE `server_bot_profiles` ADD COLUMN IF NOT EXISTS `wallet_floor_gil` int unsigned NOT NULL DEFAULT 0 AFTER `commandable`;
ALTER TABLE `server_bot_profiles` ADD COLUMN IF NOT EXISTS `wallet_ceiling_gil` int unsigned NOT NULL DEFAULT 5000 AFTER `wallet_floor_gil`;

CREATE TABLE IF NOT EXISTS `server_bot_spawn_rules` (
    `rule_key` varchar(96) NOT NULL,
    `zone_id` smallint unsigned NOT NULL,
    `zone_name` varchar(64) NOT NULL,
    `zone_kind` enum('city','town','leveling','travel') NOT NULL,
    `target_count` tinyint unsigned NOT NULL DEFAULT 6,
    `max_count` tinyint unsigned NOT NULL DEFAULT 24,
    `anchor_x` float NOT NULL DEFAULT 0,
    `anchor_y` float NOT NULL DEFAULT 0,
    `anchor_z` float NOT NULL DEFAULT 0,
    `radius` float NOT NULL DEFAULT 8,
    `profile_filter` varchar(64) NOT NULL DEFAULT 'any',
    `enabled` tinyint(1) NOT NULL DEFAULT 1,
    PRIMARY KEY (`rule_key`),
    KEY `idx_server_bot_spawn_rules_zone` (`zone_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

ALTER TABLE `server_bot_spawn_rules` ADD COLUMN IF NOT EXISTS `priority` tinyint unsigned NOT NULL DEFAULT 10 AFTER `zone_kind`;
ALTER TABLE `server_bot_spawn_rules` ADD COLUMN IF NOT EXISTS `max_combat_count` tinyint unsigned NOT NULL DEFAULT 8 AFTER `max_count`;
ALTER TABLE `server_bot_spawn_rules` ADD COLUMN IF NOT EXISTS `min_level` tinyint unsigned NOT NULL DEFAULT 1 AFTER `profile_filter`;
ALTER TABLE `server_bot_spawn_rules` ADD COLUMN IF NOT EXISTS `max_level` tinyint unsigned NOT NULL DEFAULT 99 AFTER `min_level`;
ALTER TABLE `server_bot_spawn_rules` ADD COLUMN IF NOT EXISTS `route_key` varchar(96) NULL AFTER `max_level`;
ALTER TABLE `server_bot_spawn_rules` ADD COLUMN IF NOT EXISTS `camp_key` varchar(96) NULL AFTER `route_key`;
ALTER TABLE `server_bot_spawn_rules` ADD COLUMN IF NOT EXISTS `required_player_count` tinyint unsigned NOT NULL DEFAULT 1 AFTER `camp_key`;
ALTER TABLE `server_bot_spawn_rules` ADD COLUMN IF NOT EXISTS `allow_combat` tinyint(1) NOT NULL DEFAULT 0 AFTER `required_player_count`;
ALTER TABLE `server_bot_spawn_rules` ADD COLUMN IF NOT EXISTS `allow_economy` tinyint(1) NOT NULL DEFAULT 0 AFTER `allow_combat`;

CREATE TABLE IF NOT EXISTS `server_bot_state` (
    `bot_key` varchar(128) NOT NULL,
    `profile_key` varchar(64) NOT NULL,
    `current_zone_id` smallint unsigned NOT NULL DEFAULT 0,
    `current_level` tinyint unsigned NOT NULL DEFAULT 1,
    `main_job` tinyint unsigned NOT NULL DEFAULT 1,
    `pos_x` float NOT NULL DEFAULT 0,
    `pos_y` float NOT NULL DEFAULT 0,
    `pos_z` float NOT NULL DEFAULT 0,
    `wallet_gil` int unsigned NOT NULL DEFAULT 0,
    `gear_profile` varchar(64) NOT NULL DEFAULT 'starter',
    `inventory_summary` text NULL,
    `progression_state` text NULL,
    `cooldown_state` text NULL,
    `status` varchar(32) NOT NULL DEFAULT 'inactive',
    `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `last_seen` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`bot_key`),
    KEY `idx_server_bot_state_zone` (`current_zone_id`),
    KEY `idx_server_bot_state_profile` (`profile_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

ALTER TABLE `server_bot_state` ADD COLUMN IF NOT EXISTS `current_exp` int unsigned NOT NULL DEFAULT 0 AFTER `current_level`;
ALTER TABLE `server_bot_state` ADD COLUMN IF NOT EXISTS `familiarity` smallint unsigned NOT NULL DEFAULT 0 AFTER `current_exp`;
ALTER TABLE `server_bot_state` ADD COLUMN IF NOT EXISTS `sub_job` tinyint unsigned NOT NULL DEFAULT 0 AFTER `main_job`;
ALTER TABLE `server_bot_state` ADD COLUMN IF NOT EXISTS `role_state` varchar(64) NOT NULL DEFAULT 'idle' AFTER `cooldown_state`;
ALTER TABLE `server_bot_state` ADD COLUMN IF NOT EXISTS `strategy_state` text NULL AFTER `role_state`;
ALTER TABLE `server_bot_state` ADD COLUMN IF NOT EXISTS `target_mob_id` int unsigned NOT NULL DEFAULT 0 AFTER `strategy_state`;
ALTER TABLE `server_bot_state` ADD COLUMN IF NOT EXISTS `party_owner_charid` int unsigned NOT NULL DEFAULT 0 AFTER `target_mob_id`;
ALTER TABLE `server_bot_state` ADD COLUMN IF NOT EXISTS `bot_party_key` varchar(128) NULL AFTER `party_owner_charid`;
ALTER TABLE `server_bot_state` ADD COLUMN IF NOT EXISTS `last_action_at` timestamp NULL DEFAULT NULL AFTER `last_seen`;

CREATE TABLE IF NOT EXISTS `server_bot_audit_log` (
    `audit_id` bigint unsigned NOT NULL AUTO_INCREMENT,
    `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `action` varchar(64) NOT NULL,
    `zone_id` smallint unsigned NOT NULL DEFAULT 0,
    `bot_key` varchar(128) NULL,
    `bot_name` varchar(32) NULL,
    `details` text NULL,
    PRIMARY KEY (`audit_id`),
    KEY `idx_server_bot_audit_action` (`action`),
    KEY `idx_server_bot_audit_zone` (`zone_id`),
    KEY `idx_server_bot_audit_bot` (`bot_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

ALTER TABLE `server_bot_audit_log` ADD COLUMN IF NOT EXISTS `severity` enum('debug','info','warning','error') NOT NULL DEFAULT 'info' AFTER `action`;
ALTER TABLE `server_bot_audit_log` ADD COLUMN IF NOT EXISTS `actor_charid` int unsigned NOT NULL DEFAULT 0 AFTER `bot_name`;
ALTER TABLE `server_bot_audit_log` ADD COLUMN IF NOT EXISTS `target_id` int unsigned NOT NULL DEFAULT 0 AFTER `actor_charid`;

CREATE TABLE IF NOT EXISTS `server_bot_route_points` (
    `route_key` varchar(96) NOT NULL,
    `point_index` smallint unsigned NOT NULL,
    `zone_id` smallint unsigned NOT NULL,
    `x` float NOT NULL DEFAULT 0,
    `y` float NOT NULL DEFAULT 0,
    `z` float NOT NULL DEFAULT 0,
    `wait_ms` int unsigned NOT NULL DEFAULT 3000,
    `point_type` enum('patrol','camp','zone_line','vendor','auction','home') NOT NULL DEFAULT 'patrol',
    `enabled` tinyint(1) NOT NULL DEFAULT 1,
    PRIMARY KEY (`route_key`, `point_index`),
    KEY `idx_server_bot_route_points_zone` (`zone_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `server_bot_camps` (
    `camp_key` varchar(96) NOT NULL,
    `zone_id` smallint unsigned NOT NULL,
    `camp_name` varchar(96) NOT NULL,
    `min_level` tinyint unsigned NOT NULL DEFAULT 1,
    `max_level` tinyint unsigned NOT NULL DEFAULT 99,
    `x` float NOT NULL DEFAULT 0,
    `y` float NOT NULL DEFAULT 0,
    `z` float NOT NULL DEFAULT 0,
    `radius` float NOT NULL DEFAULT 25,
    `safe_x` float NOT NULL DEFAULT 0,
    `safe_y` float NOT NULL DEFAULT 0,
    `safe_z` float NOT NULL DEFAULT 0,
    `allowed_families` text NULL,
    `excluded_mob_names` text NULL,
    `max_bots` tinyint unsigned NOT NULL DEFAULT 6,
    `enabled` tinyint(1) NOT NULL DEFAULT 1,
    PRIMARY KEY (`camp_key`),
    KEY `idx_server_bot_camps_zone` (`zone_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `server_bot_strategies` (
    `strategy_key` varchar(64) NOT NULL,
    `layer` enum('ambient','movement','combat','party','recovery','economy','social','safety') NOT NULL,
    `priority` tinyint unsigned NOT NULL DEFAULT 50,
    `tick_interval_seconds` smallint unsigned NOT NULL DEFAULT 10,
    `params` text NULL,
    `enabled` tinyint(1) NOT NULL DEFAULT 1,
    PRIMARY KEY (`strategy_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `server_bot_inventory_ledger` (
    `ledger_id` bigint unsigned NOT NULL AUTO_INCREMENT,
    `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `bot_key` varchar(128) NOT NULL,
    `item_id` int unsigned NOT NULL DEFAULT 0,
    `quantity` int NOT NULL DEFAULT 0,
    `source_action` varchar(64) NOT NULL,
    `details` text NULL,
    PRIMARY KEY (`ledger_id`),
    KEY `idx_server_bot_inventory_ledger_bot` (`bot_key`),
    KEY `idx_server_bot_inventory_ledger_action` (`source_action`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `server_bot_economy_ledger` (
    `ledger_id` bigint unsigned NOT NULL AUTO_INCREMENT,
    `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `bot_key` varchar(128) NOT NULL,
    `action` varchar(64) NOT NULL,
    `item_id` int unsigned NOT NULL DEFAULT 0,
    `quantity` int NOT NULL DEFAULT 0,
    `gil_delta` int NOT NULL DEFAULT 0,
    `counterparty` varchar(64) NULL,
    `capability` varchar(64) NOT NULL DEFAULT 'none',
    `status` enum('queued','applied','skipped','failed') NOT NULL DEFAULT 'queued',
    `details` text NULL,
    PRIMARY KEY (`ledger_id`),
    KEY `idx_server_bot_economy_ledger_bot` (`bot_key`),
    KEY `idx_server_bot_economy_ledger_action` (`action`),
    KEY `idx_server_bot_economy_ledger_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `server_bot_chat_personas` (
    `persona_key` varchar(64) NOT NULL,
    `display_style` varchar(64) NOT NULL DEFAULT 'adventurer',
    `topic_tags` varchar(255) NOT NULL DEFAULT 'travel,leveling',
    `template_lines` text NOT NULL,
    `llm_enabled` tinyint(1) NOT NULL DEFAULT 0,
    `cooldown_seconds` smallint unsigned NOT NULL DEFAULT 60,
    `moderation_profile` varchar(64) NOT NULL DEFAULT 'safe_ffxi',
    `enabled` tinyint(1) NOT NULL DEFAULT 1,
    PRIMARY KEY (`persona_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `server_bot_chat_memory` (
    `memory_id` bigint unsigned NOT NULL AUTO_INCREMENT,
    `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `bot_key` varchar(128) NOT NULL,
    `player_charid` int unsigned NOT NULL DEFAULT 0,
    `zone_id` smallint unsigned NOT NULL DEFAULT 0,
    `memory_type` varchar(64) NOT NULL DEFAULT 'interaction',
    `content` text NOT NULL,
    `expires_at` timestamp NULL DEFAULT NULL,
    PRIMARY KEY (`memory_id`),
    KEY `idx_server_bot_chat_memory_bot` (`bot_key`),
    KEY `idx_server_bot_chat_memory_player` (`player_charid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `server_bot_command_permissions` (
    `command_key` varchar(64) NOT NULL,
    `min_gm_level` tinyint unsigned NOT NULL DEFAULT 0,
    `player_enabled` tinyint(1) NOT NULL DEFAULT 0,
    `rate_limit_seconds` smallint unsigned NOT NULL DEFAULT 3,
    `enabled` tinyint(1) NOT NULL DEFAULT 1,
    PRIMARY KEY (`command_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `server_bot_performance_snapshots` (
    `snapshot_id` bigint unsigned NOT NULL AUTO_INCREMENT,
    `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `zone_id` smallint unsigned NOT NULL DEFAULT 0,
    `active_bots` smallint unsigned NOT NULL DEFAULT 0,
    `combat_bots` smallint unsigned NOT NULL DEFAULT 0,
    `tick_budget_ms` smallint unsigned NOT NULL DEFAULT 0,
    `tick_elapsed_ms` smallint unsigned NOT NULL DEFAULT 0,
    `over_budget` tinyint(1) NOT NULL DEFAULT 0,
    `details` text NULL,
    PRIMARY KEY (`snapshot_id`),
    KEY `idx_server_bot_performance_zone` (`zone_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `server_bot_player_orders` (
    `order_id` bigint unsigned NOT NULL AUTO_INCREMENT,
    `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `expires_at` timestamp NULL DEFAULT NULL,
    `player_charid` int unsigned NOT NULL DEFAULT 0,
    `player_name` varchar(32) NOT NULL DEFAULT '',
    `bot_key` varchar(128) NOT NULL,
    `order_type` varchar(32) NOT NULL,
    `order_args` text NULL,
    `status` enum('queued','active','complete','cancelled','failed') NOT NULL DEFAULT 'queued',
    PRIMARY KEY (`order_id`),
    KEY `idx_server_bot_player_orders_player` (`player_charid`),
    KEY `idx_server_bot_player_orders_bot` (`bot_key`),
    KEY `idx_server_bot_player_orders_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `server_bot_parties` (
    `party_key` varchar(128) NOT NULL,
    `zone_id` smallint unsigned NOT NULL DEFAULT 0,
    `camp_key` varchar(96) NULL,
    `strategy_profile` varchar(64) NOT NULL DEFAULT 'balanced',
    `status` enum('forming','active','resting','traveling','disbanded') NOT NULL DEFAULT 'forming',
    `max_members` tinyint unsigned NOT NULL DEFAULT 6,
    `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `last_seen` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `disband_reason` text NULL,
    PRIMARY KEY (`party_key`),
    KEY `idx_server_bot_parties_zone` (`zone_id`),
    KEY `idx_server_bot_parties_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `server_bot_party_members` (
    `party_key` varchar(128) NOT NULL,
    `bot_key` varchar(128) NOT NULL,
    `profile_key` varchar(64) NOT NULL,
    `party_role` varchar(32) NOT NULL DEFAULT 'member',
    `joined_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `last_seen` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `status` enum('active','resting','traveling','dead','left') NOT NULL DEFAULT 'active',
    PRIMARY KEY (`party_key`, `bot_key`),
    KEY `idx_server_bot_party_members_bot` (`bot_key`),
    KEY `idx_server_bot_party_members_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `server_bot_strategy_memory` (
    `memory_id` bigint unsigned NOT NULL AUTO_INCREMENT,
    `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `bot_key` varchar(128) NOT NULL,
    `profile_key` varchar(64) NOT NULL,
    `zone_id` smallint unsigned NOT NULL DEFAULT 0,
    `camp_key` varchar(96) NULL,
    `strategy_key` varchar(64) NOT NULL,
    `situation_key` varchar(96) NOT NULL DEFAULT 'general',
    `success_count` int unsigned NOT NULL DEFAULT 0,
    `failure_count` int unsigned NOT NULL DEFAULT 0,
    `last_result` enum('success','failure','skipped') NOT NULL DEFAULT 'skipped',
    `details` text NULL,
    PRIMARY KEY (`memory_id`),
    KEY `idx_server_bot_strategy_memory_bot` (`bot_key`),
    KEY `idx_server_bot_strategy_memory_strategy` (`strategy_key`),
    KEY `idx_server_bot_strategy_memory_zone` (`zone_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `server_bot_encounter_ledger` (
    `encounter_id` bigint unsigned NOT NULL AUTO_INCREMENT,
    `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `bot_key` varchar(128) NOT NULL,
    `party_key` varchar(128) NULL,
    `zone_id` smallint unsigned NOT NULL DEFAULT 0,
    `target_id` int unsigned NOT NULL DEFAULT 0,
    `encounter_type` enum('simulated','combat_actor','travel','rest','death') NOT NULL DEFAULT 'simulated',
    `result` enum('queued','success','failure','skipped') NOT NULL DEFAULT 'queued',
    `xp_delta` int unsigned NOT NULL DEFAULT 0,
    `gil_delta` int NOT NULL DEFAULT 0,
    `details` text NULL,
    PRIMARY KEY (`encounter_id`),
    KEY `idx_server_bot_encounter_ledger_bot` (`bot_key`),
    KEY `idx_server_bot_encounter_ledger_party` (`party_key`),
    KEY `idx_server_bot_encounter_ledger_zone` (`zone_id`),
    KEY `idx_server_bot_encounter_ledger_result` (`result`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `server_bot_runtime_flags` (
    `flag_key` varchar(64) NOT NULL,
    `flag_value` varchar(255) NOT NULL,
    `updated_by` varchar(64) NOT NULL DEFAULT 'system',
    `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`flag_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO `server_bot_profiles`
    (`profile_key`, `display_name`, `role`, `main_job`, `sub_job`, `min_level`, `max_level`, `model_id`, `behavior_profile`, `gear_profile`, `can_claim`, `can_loot`, `can_trade`, `can_use_auction_house`, `notes`)
VALUES
    ('ambient_town_adventurer', 'Aldreda', 'ambient', 1, 0, 1, 99, 2430, 'town_patrol', 'starter', 0, 0, 0, 0, 'Ambient city and town patrol actor.'),
    ('ambient_crafter', 'Borghest', 'ambient', 9, 0, 1, 99, 2431, 'town_chat', 'crafting', 0, 0, 0, 0, 'Talks about guilds, markets, and travel.'),
    ('traveling_adventurer', 'Celenne', 'travel', 6, 1, 10, 99, 2432, 'travel_patrol', 'traveler', 0, 0, 0, 0, 'Moves near zone lines and outposts.'),
    ('leveling_vanguard', 'Darric', 'fighter', 1, 6, 1, 75, 2433, 'leveling_patrol', 'melee', 1, 1, 0, 0, 'Future claim and loot capable adventuring actor.'),
    ('leveling_healer', 'Eloise', 'support', 3, 4, 1, 75, 2434, 'leveling_support', 'healer', 1, 1, 0, 0, 'Future support bot for parties and roaming groups.')
ON DUPLICATE KEY UPDATE
    `display_name` = VALUES(`display_name`),
    `role` = VALUES(`role`),
    `main_job` = VALUES(`main_job`),
    `sub_job` = VALUES(`sub_job`),
    `min_level` = VALUES(`min_level`),
    `max_level` = VALUES(`max_level`),
    `model_id` = VALUES(`model_id`),
    `behavior_profile` = VALUES(`behavior_profile`),
    `gear_profile` = VALUES(`gear_profile`),
    `can_claim` = VALUES(`can_claim`),
    `can_loot` = VALUES(`can_loot`),
    `can_trade` = VALUES(`can_trade`),
    `can_use_auction_house` = VALUES(`can_use_auction_house`),
    `notes` = VALUES(`notes`);

UPDATE `server_bot_profiles` SET
    `persona_key` = 'ambient_adventurer',
    `strategy_stack` = 'ambient,travel,social',
    `commandable` = 0
WHERE `profile_key` = 'ambient_town_adventurer';

UPDATE `server_bot_profiles` SET
    `persona_key` = 'crafter_market',
    `strategy_stack` = 'ambient,vendor,social',
    `can_vendor` = 1,
    `can_upgrade_gear` = 1
WHERE `profile_key` = 'ambient_crafter';

UPDATE `server_bot_profiles` SET
    `persona_key` = 'traveling_adventurer',
    `strategy_stack` = 'travel,ambient,social',
    `commandable` = 0,
    `can_party` = 1
WHERE `profile_key` = 'traveling_adventurer';

UPDATE `server_bot_profiles` SET
    `persona_key` = 'leveling_vanguard',
    `strategy_stack` = 'grind,party_assist,tank,rest,return_home,vendor',
    `can_vendor` = 1,
    `can_upgrade_gear` = 1,
    `can_party` = 1,
    `commandable` = 0,
    `wallet_ceiling_gil` = 15000
WHERE `profile_key` = 'leveling_vanguard';

UPDATE `server_bot_profiles` SET
    `persona_key` = 'leveling_healer',
    `strategy_stack` = 'grind,party_assist,healer,support,rest,return_home,vendor',
    `can_vendor` = 1,
    `can_upgrade_gear` = 1,
    `can_party` = 1,
    `commandable` = 0,
    `wallet_ceiling_gil` = 12000
WHERE `profile_key` = 'leveling_healer';

INSERT INTO `server_bot_profiles`
    (`profile_key`, `display_name`, `role`, `main_job`, `sub_job`, `min_level`, `max_level`, `model_id`, `behavior_profile`, `gear_profile`, `persona_key`, `strategy_stack`, `can_claim`, `can_loot`, `can_trade`, `can_use_auction_house`, `can_vendor`, `can_upgrade_gear`, `can_party`, `can_llm_chat`, `commandable`, `wallet_ceiling_gil`, `notes`)
VALUES
    ('leveling_ranger', 'Sibylle', 'ranged', 11, 1, 10, 75, 2435, 'leveling_ranged', 'ranged', 'leveling_vanguard', 'grind,party_assist,ranged,rest,return_home,vendor', 1, 1, 0, 0, 1, 1, 1, 0, 0, 14000, 'Ranged autonomous adventuring bot for camps and bot-only parties.'),
    ('leveling_black_mage', 'Maudriel', 'caster', 4, 3, 10, 75, 2436, 'leveling_caster', 'caster', 'leveling_healer', 'grind,party_assist,black_mage,rest,return_home,vendor', 1, 1, 0, 0, 1, 1, 1, 0, 0, 13000, 'Caster autonomous adventuring bot with conservative spell-like behavior hooks.'),
    ('market_supplier', 'Nimia', 'merchant', 9, 0, 1, 99, 2437, 'market_supplier', 'crafting', 'crafter_market', 'ambient,vendor,auction,social', 0, 0, 1, 1, 1, 1, 0, 0, 0, 50000, 'Economy simulation profile for vendor and optional AH ledgers.')
ON DUPLICATE KEY UPDATE
    `display_name` = VALUES(`display_name`),
    `role` = VALUES(`role`),
    `main_job` = VALUES(`main_job`),
    `sub_job` = VALUES(`sub_job`),
    `min_level` = VALUES(`min_level`),
    `max_level` = VALUES(`max_level`),
    `model_id` = VALUES(`model_id`),
    `behavior_profile` = VALUES(`behavior_profile`),
    `gear_profile` = VALUES(`gear_profile`),
    `persona_key` = VALUES(`persona_key`),
    `strategy_stack` = VALUES(`strategy_stack`),
    `can_claim` = VALUES(`can_claim`),
    `can_loot` = VALUES(`can_loot`),
    `can_trade` = VALUES(`can_trade`),
    `can_use_auction_house` = VALUES(`can_use_auction_house`),
    `can_vendor` = VALUES(`can_vendor`),
    `can_upgrade_gear` = VALUES(`can_upgrade_gear`),
    `can_party` = VALUES(`can_party`),
    `can_llm_chat` = VALUES(`can_llm_chat`),
    `commandable` = VALUES(`commandable`),
    `wallet_ceiling_gil` = VALUES(`wallet_ceiling_gil`),
    `notes` = VALUES(`notes`);

UPDATE `server_bot_profiles` SET
    `commandable` = 0
WHERE `commandable` <> 0;

INSERT INTO `server_bot_spawn_rules`
    (`rule_key`, `zone_id`, `zone_name`, `zone_kind`, `target_count`, `max_count`, `anchor_x`, `anchor_y`, `anchor_z`, `radius`, `profile_filter`)
VALUES
    ('city_southern_sandoria', 230, 'Southern San dOria', 'city', 12, 24, -100.0, 1.0, -40.0, 18.0, 'ambient'),
    ('city_northern_sandoria', 231, 'Northern San dOria', 'city', 12, 24, 40.0, -0.2, 30.0, 18.0, 'ambient'),
    ('city_port_sandoria', 232, 'Port San dOria', 'city', 12, 24, -40.0, -2.0, 20.0, 18.0, 'ambient'),
    ('city_bastok_mines', 234, 'Bastok Mines', 'city', 12, 24, 76.0, 0.0, -66.0, 18.0, 'ambient'),
    ('city_bastok_markets', 235, 'Bastok Markets', 'city', 12, 24, -240.0, -2.0, 63.0, 18.0, 'ambient'),
    ('city_port_bastok', 236, 'Port Bastok', 'city', 12, 24, -80.0, 7.0, -30.0, 18.0, 'ambient'),
    ('city_windurst_waters', 238, 'Windurst Waters', 'city', 12, 24, 193.0, -12.0, 220.0, 18.0, 'ambient'),
    ('city_windurst_walls', 239, 'Windurst Walls', 'city', 12, 24, 0.0, -16.0, 130.0, 18.0, 'ambient'),
    ('city_port_windurst', 240, 'Port Windurst', 'city', 12, 24, 185.0, -12.0, 223.0, 18.0, 'ambient'),
    ('city_windurst_woods', 241, 'Windurst Woods', 'city', 12, 24, -20.0, -5.0, -120.0, 18.0, 'ambient'),
    ('city_lower_jeuno', 245, 'Lower Jeuno', 'city', 12, 24, 30.0, 0.0, -30.0, 18.0, 'ambient'),
    ('city_aht_urhgan_whitegate', 50, 'Aht Urhgan Whitegate', 'city', 12, 24, 120.0, 1.5, 47.0, 18.0, 'ambient'),
    ('town_selbina', 248, 'Selbina', 'town', 6, 12, 14.0, -14.5, 66.0, 12.0, 'ambient'),
    ('town_mhaura', 249, 'Mhaura', 'town', 6, 12, 3.0, -4.0, 72.0, 12.0, 'ambient'),
    ('town_kazham', 250, 'Kazham', 'town', 6, 12, -80.0, -10.0, -20.0, 12.0, 'ambient'),
    ('town_norg', 252, 'Norg', 'town', 6, 12, 0.0, 0.0, 0.0, 12.0, 'ambient'),
    ('town_nashmau', 53, 'Nashmau', 'town', 6, 12, 0.0, 0.0, 0.0, 12.0, 'ambient'),
    ('level_west_ronfaure', 100, 'West Ronfaure', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_east_ronfaure', 101, 'East Ronfaure', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_la_theine_plateau', 102, 'La Theine Plateau', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_valkurm_dunes', 103, 'Valkurm Dunes', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_jugner_forest', 104, 'Jugner Forest', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_batallia_downs', 105, 'Batallia Downs', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_north_gustaberg', 106, 'North Gustaberg', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_south_gustaberg', 107, 'South Gustaberg', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_konschtat_highlands', 108, 'Konschtat Highlands', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_pashhow_marshlands', 109, 'Pashhow Marshlands', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_rolanberry_fields', 110, 'Rolanberry Fields', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_beaucedine_glacier', 111, 'Beaucedine Glacier', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_xarcabard', 112, 'Xarcabard', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_cape_teriggan', 113, 'Cape Teriggan', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_eastern_altepa_desert', 114, 'Eastern Altepa Desert', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_west_sarutabaruta', 115, 'West Sarutabaruta', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_east_sarutabaruta', 116, 'East Sarutabaruta', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_tahrongi_canyon', 117, 'Tahrongi Canyon', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_buburimu_peninsula', 118, 'Buburimu Peninsula', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_meriphataud_mountains', 119, 'Meriphataud Mountains', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_sauromugue_champaign', 120, 'Sauromugue Champaign', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_sanctuary_of_zitah', 121, 'The Sanctuary of ZiTah', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_yuhtunga_jungle', 123, 'Yuhtunga Jungle', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_yhoator_jungle', 124, 'Yhoator Jungle', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_western_altepa_desert', 125, 'Western Altepa Desert', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_qufim_island', 126, 'Qufim Island', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_king_ranperres_tomb', 190, 'King Ranperres Tomb', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_dangruf_wadi', 191, 'Dangruf Wadi', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_ghelsba_outpost', 140, 'Ghelsba Outpost', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_fort_ghelsba', 141, 'Fort Ghelsba', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_yughott_grotto', 142, 'Yughott Grotto', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_palborough_mines', 143, 'Palborough Mines', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_giddeus', 145, 'Giddeus', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_beadeaux', 147, 'Beadeaux', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_davoi', 149, 'Davoi', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_castle_oztroja', 151, 'Castle Oztroja', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_zeruhn_mines', 172, 'Zeruhn Mines', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_korroloka_tunnel', 173, 'Korroloka Tunnel', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_crawlers_nest', 197, 'Crawlers Nest', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_garlaige_citadel', 200, 'Garlaige Citadel', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_gustav_tunnel', 212, 'Gustav Tunnel', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling'),
    ('level_labyrinth_of_onzozo', 213, 'Labyrinth of Onzozo', 'leveling', 8, 24, 0.0, 0.0, 0.0, 10.0, 'leveling')
ON DUPLICATE KEY UPDATE
    `target_count` = VALUES(`target_count`),
    `max_count` = VALUES(`max_count`),
    `anchor_x` = VALUES(`anchor_x`),
    `anchor_y` = VALUES(`anchor_y`),
    `anchor_z` = VALUES(`anchor_z`),
    `radius` = VALUES(`radius`),
    `profile_filter` = VALUES(`profile_filter`);

UPDATE `server_bot_spawn_rules` SET
    `allow_combat` = CASE WHEN `zone_kind` = 'leveling' THEN 1 ELSE 0 END,
    `allow_economy` = CASE WHEN `zone_kind` IN ('city','town','leveling') THEN 1 ELSE 0 END,
    `max_combat_count` = CASE WHEN `zone_kind` = 'leveling' THEN 8 ELSE 0 END,
    `min_level` = CASE WHEN `zone_kind` = 'leveling' THEN 1 ELSE 1 END,
    `max_level` = CASE WHEN `zone_kind` = 'leveling' THEN 75 ELSE 99 END;

UPDATE `server_bot_spawn_rules` SET `camp_key` = 'camp_west_ronfaure_gate' WHERE `zone_id` = 100;
UPDATE `server_bot_spawn_rules` SET `camp_key` = 'camp_south_gustaberg_gate' WHERE `zone_id` = 107;
UPDATE `server_bot_spawn_rules` SET `camp_key` = 'camp_east_sarutabaruta_gate' WHERE `zone_id` = 116;
UPDATE `server_bot_spawn_rules` SET `camp_key` = 'camp_valkurm_dunes_oasis' WHERE `zone_id` = 103;
UPDATE `server_bot_spawn_rules` SET `camp_key` = 'camp_qufim_island_lake' WHERE `zone_id` = 126;
UPDATE `server_bot_spawn_rules` SET `camp_key` = 'camp_crawlers_nest_entrance' WHERE `zone_id` = 197;

INSERT INTO `server_bot_camps`
    (`camp_key`, `zone_id`, `camp_name`, `min_level`, `max_level`, `x`, `y`, `z`, `radius`, `safe_x`, `safe_y`, `safe_z`, `allowed_families`, `excluded_mob_names`, `max_bots`)
VALUES
    ('camp_west_ronfaure_gate', 100, 'West Ronfaure Gate', 1, 12, -420.0, -20.0, -220.0, 45.0, -420.0, -20.0, -220.0, 'rabbit,beetle,orc,sheep', 'Jaggedy-Eared Jack', 6),
    ('camp_south_gustaberg_gate', 107, 'South Gustaberg Gate', 1, 12, -280.0, 40.0, 150.0, 45.0, -280.0, 40.0, 150.0, 'bee,quadav,worm,lizard', '', 6),
    ('camp_east_sarutabaruta_gate', 116, 'East Sarutabaruta Gate', 1, 12, -80.0, -30.0, 300.0, 45.0, -80.0, -30.0, 300.0, 'mandragora,bee,crawler,yagudo', '', 6),
    ('camp_valkurm_dunes_oasis', 103, 'Valkurm Dunes Oasis', 10, 25, 150.0, -8.0, 90.0, 65.0, 150.0, -8.0, 90.0, 'crab,fly,pugil,goblin', 'Valkurm Emperor', 8),
    ('camp_qufim_island_lake', 126, 'Qufim Island Lake', 18, 30, -260.0, -20.0, 320.0, 65.0, -260.0, -20.0, 320.0, 'worm,crab,giant,weapon', 'Kraken', 8),
    ('camp_crawlers_nest_entrance', 197, 'Crawlers Nest Entrance', 30, 45, 20.0, 0.0, -140.0, 60.0, 20.0, 0.0, -140.0, 'crawler,fly,beetle', '', 8)
ON DUPLICATE KEY UPDATE
    `zone_id` = VALUES(`zone_id`),
    `camp_name` = VALUES(`camp_name`),
    `min_level` = VALUES(`min_level`),
    `max_level` = VALUES(`max_level`),
    `x` = VALUES(`x`),
    `y` = VALUES(`y`),
    `z` = VALUES(`z`),
    `radius` = VALUES(`radius`),
    `safe_x` = VALUES(`safe_x`),
    `safe_y` = VALUES(`safe_y`),
    `safe_z` = VALUES(`safe_z`),
    `allowed_families` = VALUES(`allowed_families`),
    `excluded_mob_names` = VALUES(`excluded_mob_names`),
    `max_bots` = VALUES(`max_bots`);

INSERT INTO `server_bot_route_points`
    (`route_key`, `point_index`, `zone_id`, `x`, `y`, `z`, `wait_ms`, `point_type`)
VALUES
    ('city_southern_sandoria_route', 1, 230, -100.0, 1.0, -40.0, 4000, 'patrol'),
    ('city_southern_sandoria_route', 2, 230, -92.0, 1.0, -32.0, 4000, 'patrol'),
    ('city_southern_sandoria_route', 3, 230, -108.0, 1.0, -30.0, 4000, 'patrol'),
    ('town_selbina_route', 1, 248, 14.0, -14.5, 66.0, 4000, 'patrol'),
    ('town_selbina_route', 2, 248, 26.0, -14.5, 70.0, 4000, 'vendor'),
    ('town_selbina_route', 3, 248, 8.0, -14.5, 58.0, 4000, 'zone_line'),
    ('camp_valkurm_dunes_oasis_route', 1, 103, 150.0, -8.0, 90.0, 3000, 'camp'),
    ('camp_valkurm_dunes_oasis_route', 2, 103, 165.0, -8.0, 104.0, 3000, 'patrol'),
    ('camp_valkurm_dunes_oasis_route', 3, 103, 136.0, -8.0, 78.0, 3000, 'patrol')
ON DUPLICATE KEY UPDATE
    `zone_id` = VALUES(`zone_id`),
    `x` = VALUES(`x`),
    `y` = VALUES(`y`),
    `z` = VALUES(`z`),
    `wait_ms` = VALUES(`wait_ms`),
    `point_type` = VALUES(`point_type`);

UPDATE `server_bot_spawn_rules` SET `route_key` = 'city_southern_sandoria_route' WHERE `rule_key` = 'city_southern_sandoria';
UPDATE `server_bot_spawn_rules` SET `route_key` = 'town_selbina_route' WHERE `rule_key` = 'town_selbina';
UPDATE `server_bot_spawn_rules` SET `route_key` = 'camp_valkurm_dunes_oasis_route' WHERE `rule_key` = 'level_valkurm_dunes';

INSERT INTO `server_bot_strategies`
    (`strategy_key`, `layer`, `priority`, `tick_interval_seconds`, `params`)
VALUES
    ('ambient', 'ambient', 20, 20, 'patrol=true;chat=true'),
    ('travel', 'movement', 30, 15, 'prefer_route=true;avoid_combat=true'),
    ('grind', 'combat', 40, 8, 'target=easy_even;max_distance=35;respect_claims=true'),
    ('party_assist', 'party', 35, 5, 'bot_party=true;orders=false;role_coordination=true'),
    ('tank', 'combat', 45, 6, 'enmity=high;protect_party=true'),
    ('healer', 'party', 45, 6, 'heal_threshold=65;rest_mp=35'),
    ('support', 'party', 50, 8, 'buff=true;debuff=false'),
    ('ranged', 'combat', 50, 8, 'distance=12;ammo_budget=low'),
    ('black_mage', 'combat', 50, 10, 'nuke=conservative;rest_mp=45'),
    ('rest', 'recovery', 60, 10, 'hp_threshold=45;mp_threshold=35'),
    ('vendor', 'economy', 70, 60, 'rate_limit=300;ledger_only=false'),
    ('auction', 'economy', 80, 300, 'requires_global_ah=true;ledger_first=true'),
    ('return_home', 'recovery', 90, 15, 'death_delay=30;home=true'),
    ('panic_disable', 'safety', 1, 1, 'despawn=true;disable_combat=true')
ON DUPLICATE KEY UPDATE
    `layer` = VALUES(`layer`),
    `priority` = VALUES(`priority`),
    `tick_interval_seconds` = VALUES(`tick_interval_seconds`),
    `params` = VALUES(`params`);

INSERT INTO `server_bot_chat_personas`
    (`persona_key`, `display_style`, `topic_tags`, `template_lines`, `llm_enabled`, `cooldown_seconds`, `moderation_profile`)
VALUES
    ('ambient_adventurer', 'adventurer', 'travel,signet,parties', 'I heard the outpost roads are safer lately.|A full pack and a good map. That is how you start a journey.|The best parties are the ones that remember to bring Signet.', 0, 60, 'safe_ffxi'),
    ('crafter_market', 'crafter', 'guilds,materials,shops', 'The guilds are busy today.|Materials move quickly when adventurers are out leveling.|Good tools save more gil than they cost.', 0, 90, 'safe_ffxi'),
    ('traveling_adventurer', 'traveler', 'routes,outposts,weather', 'I am checking the next zone line before dusk.|Roads feel shorter when someone else is nearby.|I should restock before the next leg.', 0, 60, 'safe_ffxi'),
    ('leveling_vanguard', 'frontline adventurer', 'camps,pulls,links', 'I am looking for even matches nearby.|Pull carefully. The links here can get ugly.|I will check the camp and circle back.', 0, 45, 'safe_ffxi'),
    ('leveling_healer', 'healer', 'cures,resting,party safety', 'I have cures ready if the camp gets busy.|Rest before the next pull. It saves lives.|A steady party beats a reckless one.', 0, 45, 'safe_ffxi')
ON DUPLICATE KEY UPDATE
    `display_style` = VALUES(`display_style`),
    `topic_tags` = VALUES(`topic_tags`),
    `template_lines` = VALUES(`template_lines`),
    `llm_enabled` = VALUES(`llm_enabled`),
    `cooldown_seconds` = VALUES(`cooldown_seconds`),
    `moderation_profile` = VALUES(`moderation_profile`);

INSERT INTO `server_bot_command_permissions`
    (`command_key`, `min_gm_level`, `player_enabled`, `rate_limit_seconds`)
VALUES
    ('serverbot.status', 1, 0, 1),
    ('serverbot.reload', 1, 0, 5),
    ('serverbot.spawn', 1, 0, 3),
    ('serverbot.despawn', 1, 0, 3),
    ('serverbot.trace', 1, 0, 1),
    ('serverbot.profile', 1, 0, 1),
    ('serverbot.rule', 1, 0, 1),
    ('serverbot.camp', 1, 0, 1),
    ('serverbot.strategy', 1, 0, 1),
    ('serverbot.audit', 1, 0, 2),
    ('serverbot.economy', 1, 0, 2),
    ('serverbot.perf', 1, 0, 2),
    ('serverbot.pause', 1, 0, 2),
    ('serverbot.resume', 1, 0, 2),
    ('serverbot.enable', 1, 0, 2),
    ('serverbot.disable', 1, 0, 2),
    ('serverbot.llm', 1, 0, 2),
    ('serverbot.panic', 1, 0, 1),
    ('bot.invite', 0, 0, 5),
    ('bot.dismiss', 0, 0, 3),
    ('bot.follow', 0, 0, 2),
    ('bot.attack', 0, 0, 2),
    ('bot.rest', 0, 0, 2),
    ('bot.orders', 0, 0, 2),
    ('bot.trade', 0, 0, 5)
ON DUPLICATE KEY UPDATE
    `min_gm_level` = VALUES(`min_gm_level`),
    `player_enabled` = VALUES(`player_enabled`),
    `rate_limit_seconds` = VALUES(`rate_limit_seconds`);

UPDATE `server_bot_command_permissions` SET
    `player_enabled` = 0,
    `enabled` = 0
WHERE `command_key` LIKE 'bot.%';

INSERT INTO `server_bot_runtime_flags`
    (`flag_key`, `flag_value`, `updated_by`)
VALUES
    ('runtime_enabled', '1', 'seed'),
    ('runtime_paused', '0', 'seed'),
    ('llm_enabled', '0', 'seed'),
    ('panic_disable', '0', 'seed'),
    ('autonomous_parties_enabled', '1', 'seed')
ON DUPLICATE KEY UPDATE
    `flag_key` = `flag_key`;
