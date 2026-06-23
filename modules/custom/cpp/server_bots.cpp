/************************************************************************
 * Server-wide AI Bot Bridge
 *
 * Lua owns behavior. This module only exposes narrow DB helpers, runtime
 * flags, and the character zone-in hook needed to materialize active zones.
 ************************************************************************/

#include "common/database.h"
#include "common/logging.h"
#include "common/macros.h"
#include "map/entities/char_entity.h"
#include "map/lua/lua_base_entity.h"
#include "map/utils/moduleutils.h"

#include <string>

class ServerBotsModule : public CPPModule
{
public:
    void OnInit() override
    {
        auto xi         = lua["xi"].get_or_create<sol::table>();
        auto serverBots = xi["server_bots"].get_or_create<sol::table>();
        auto native     = serverBots["native"].get_or_create<sol::table>();

        loadRuntimeEnabled();

        native["audit"] = [](const std::string& action, uint16 zoneId, const std::string& botKey, const std::string& botName, const std::string& details, const std::string& severity, uint32 actorCharId, uint32 targetId)
        {
            db::preparedStmt("INSERT INTO server_bot_audit_log "
                             "(action, severity, zone_id, bot_key, bot_name, actor_charid, target_id, details) "
                             "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                             action,
                             severity,
                             zoneId,
                             botKey,
                             botName,
                             actorCharId,
                             targetId,
                             details);
        };

        native["touchState"] = [](const std::string& botKey, const std::string& profileKey, uint16 zoneId, uint8 level, uint8 mainJob, uint8 subJob, float x, float y, float z, uint32 currentExp, uint16 familiarity, uint32 walletGil, const std::string& gearProfile, const std::string& inventorySummary, const std::string& progressionState, const std::string& cooldownState, const std::string& roleState, const std::string& strategyState, uint32 targetMobId, uint32 partyOwnerCharId, const std::string& botPartyKey, const std::string& status)
        {
            db::preparedStmt("INSERT INTO server_bot_state "
                             "(bot_key, profile_key, current_zone_id, current_level, current_exp, familiarity, main_job, sub_job, pos_x, pos_y, pos_z, wallet_gil, gear_profile, inventory_summary, progression_state, cooldown_state, role_state, strategy_state, target_mob_id, party_owner_charid, bot_party_key, status, last_seen, last_action_at) "
                             "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) "
                             "ON DUPLICATE KEY UPDATE "
                             "profile_key = VALUES(profile_key), current_zone_id = VALUES(current_zone_id), current_level = VALUES(current_level), current_exp = VALUES(current_exp), familiarity = VALUES(familiarity), "
                             "main_job = VALUES(main_job), sub_job = VALUES(sub_job), pos_x = VALUES(pos_x), pos_y = VALUES(pos_y), pos_z = VALUES(pos_z), wallet_gil = VALUES(wallet_gil), "
                             "gear_profile = VALUES(gear_profile), inventory_summary = VALUES(inventory_summary), progression_state = VALUES(progression_state), cooldown_state = VALUES(cooldown_state), "
                             "role_state = VALUES(role_state), strategy_state = VALUES(strategy_state), target_mob_id = VALUES(target_mob_id), party_owner_charid = VALUES(party_owner_charid), bot_party_key = VALUES(bot_party_key), "
                             "status = VALUES(status), last_seen = CURRENT_TIMESTAMP, last_action_at = CURRENT_TIMESTAMP",
                             botKey,
                             profileKey,
                             zoneId,
                             level,
                             currentExp,
                             familiarity,
                             mainJob,
                             subJob,
                             x,
                             y,
                             z,
                             walletGil,
                             gearProfile,
                             inventorySummary,
                             progressionState,
                             cooldownState,
                             roleState,
                             strategyState,
                             targetMobId,
                             partyOwnerCharId,
                             botPartyKey,
                             status);
        };

        native["writeEconomy"] = [](const std::string& botKey, const std::string& action, uint32 itemId, int32 quantity, int32 gilDelta, const std::string& counterparty, const std::string& capability, const std::string& status, const std::string& details)
        {
            db::preparedStmt("INSERT INTO server_bot_economy_ledger "
                             "(bot_key, action, item_id, quantity, gil_delta, counterparty, capability, status, details) "
                             "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                             botKey,
                             action,
                             itemId,
                             quantity,
                             gilDelta,
                             counterparty,
                             capability,
                             status,
                             details);
        };

        native["writeInventory"] = [](const std::string& botKey, uint32 itemId, int32 quantity, const std::string& sourceAction, const std::string& details)
        {
            db::preparedStmt("INSERT INTO server_bot_inventory_ledger "
                             "(bot_key, item_id, quantity, source_action, details) "
                             "VALUES (?, ?, ?, ?, ?)",
                             botKey,
                             itemId,
                             quantity,
                             sourceAction,
                             details);
        };

        native["writeChatMemory"] = [](const std::string& botKey, uint32 playerCharId, uint16 zoneId, const std::string& memoryType, const std::string& content, uint32 ttlSeconds)
        {
            db::preparedStmt("INSERT INTO server_bot_chat_memory "
                             "(bot_key, player_charid, zone_id, memory_type, content, expires_at) "
                             "VALUES (?, ?, ?, ?, ?, CASE WHEN ? = 0 THEN NULL ELSE DATE_ADD(CURRENT_TIMESTAMP, INTERVAL ? SECOND) END)",
                             botKey,
                             playerCharId,
                             zoneId,
                             memoryType,
                             content,
                             ttlSeconds,
                             ttlSeconds);
        };

        native["writePlayerOrder"] = [](uint32 playerCharId, const std::string& playerName, const std::string& botKey, const std::string& orderType, const std::string& orderArgs, const std::string& status, uint32 ttlSeconds)
        {
            db::preparedStmt("INSERT INTO server_bot_player_orders "
                             "(player_charid, player_name, bot_key, order_type, order_args, status, expires_at) "
                             "VALUES (?, ?, ?, ?, ?, ?, CASE WHEN ? = 0 THEN NULL ELSE DATE_ADD(CURRENT_TIMESTAMP, INTERVAL ? SECOND) END)",
                             playerCharId,
                             playerName,
                             botKey,
                             orderType,
                             orderArgs,
                             status,
                             ttlSeconds,
                             ttlSeconds);
        };

        native["writePerformance"] = [](uint16 zoneId, uint16 activeBots, uint16 combatBots, uint16 tickBudgetMs, uint16 tickElapsedMs, bool overBudget, const std::string& details)
        {
            db::preparedStmt("INSERT INTO server_bot_performance_snapshots "
                             "(zone_id, active_bots, combat_bots, tick_budget_ms, tick_elapsed_ms, over_budget, details) "
                             "VALUES (?, ?, ?, ?, ?, ?, ?)",
                             zoneId,
                             activeBots,
                             combatBots,
                             tickBudgetMs,
                             tickElapsedMs,
                             overBudget,
                             details);
        };

        native["setRuntimeEnabled"] = [this](bool enabled)
        {
            runtimeEnabled_ = enabled;
            setRuntimeFlag("runtime_enabled", enabled ? "1" : "0", "serverbot");
        };

        native["isRuntimeEnabled"] = [this]() -> bool
        {
            return runtimeEnabled_;
        };

        native["setRuntimeFlag"] = [this](const std::string& key, const std::string& value, const std::string& updatedBy)
        {
            setRuntimeFlag(key, value, updatedBy);
        };

        native["deactivatePersistedState"] = [](const std::string& reason)
        {
            db::preparedStmt("UPDATE server_bot_state "
                             "SET status = 'inactive', role_state = 'idle', bot_party_key = NULL, target_mob_id = 0, last_action_at = CURRENT_TIMESTAMP "
                             "WHERE status NOT IN ('inactive', 'despawned', 'dead')");

            db::preparedStmt("UPDATE server_bot_parties "
                             "SET status = 'disbanded', last_seen = CURRENT_TIMESTAMP, disband_reason = ? "
                             "WHERE status = 'active'",
                             reason);
        };

        native["loadProfiles"] = [this]() -> sol::table
        {
            return loadProfiles();
        };

        native["loadSpawnRules"] = [this]() -> sol::table
        {
            return loadSpawnRules();
        };

        native["loadRoutePoints"] = [this]() -> sol::table
        {
            return loadRoutePoints();
        };

        native["loadCamps"] = [this]() -> sol::table
        {
            return loadCamps();
        };

        native["loadStrategies"] = [this]() -> sol::table
        {
            return loadStrategies();
        };

        native["loadPersonas"] = [this]() -> sol::table
        {
            return loadPersonas();
        };

        native["loadCommandPermissions"] = [this]() -> sol::table
        {
            return loadCommandPermissions();
        };

        native["latestAudit"] = [this](uint32 limit) -> sol::table
        {
            return latestAudit(limit);
        };

        native["latestEconomy"] = [this](uint32 limit) -> sol::table
        {
            return latestEconomy(limit);
        };

        native["latestPerformance"] = [this](uint32 limit) -> sol::table
        {
            return latestPerformance(limit);
        };

        native["commandAllowed"] = [](const std::string& commandKey, uint8 gmLevel, bool playerFacing) -> bool
        {
            const auto rset = db::preparedStmt("SELECT min_gm_level, player_enabled, enabled "
                                               "FROM server_bot_command_permissions "
                                               "WHERE command_key = ? LIMIT 1",
                                               commandKey);
            FOR_DB_SINGLE_RESULT(rset)
            {
                if (!rset->get<uint8>("enabled"))
                {
                    return false;
                }

                if (playerFacing)
                {
                    return rset->get<uint8>("player_enabled") != 0;
                }

                return gmLevel >= rset->get<uint8>("min_gm_level");
            }

            return playerFacing ? false : gmLevel >= 1;
        };

        ShowInfo("ServerBots: native bridge loaded");
    }

    void OnCharZoneIn(CCharEntity* PChar) override
    {
        if (!runtimeEnabled_ || PChar == nullptr)
        {
            return;
        }

        sol::protected_function onCharZoneIn = lua["xi"]["server_bots"]["onCharZoneIn"];
        if (!onCharZoneIn.valid())
        {
            return;
        }

        const auto result = onCharZoneIn(CLuaBaseEntity(PChar));
        if (!result.valid())
        {
            const sol::error err = result;
            ShowError("ServerBots: onCharZoneIn failed: %s", err.what());
        }
    }

private:
    void loadRuntimeEnabled()
    {
        const auto rset = db::preparedStmt("SELECT flag_value FROM server_bot_runtime_flags WHERE flag_key = 'runtime_enabled' LIMIT 1");
        FOR_DB_SINGLE_RESULT(rset)
        {
            runtimeEnabled_ = rset->get<std::string>("flag_value") != "0";
        }
    }

    void setRuntimeFlag(const std::string& key, const std::string& value, const std::string& updatedBy)
    {
        db::preparedStmt("INSERT INTO server_bot_runtime_flags (flag_key, flag_value, updated_by, updated_at) "
                         "VALUES (?, ?, ?, CURRENT_TIMESTAMP) "
                         "ON DUPLICATE KEY UPDATE flag_value = VALUES(flag_value), updated_by = VALUES(updated_by), updated_at = CURRENT_TIMESTAMP",
                         key,
                         value,
                         updatedBy);
    }

    sol::table loadProfiles()
    {
        auto rows = lua.create_table();
        const auto rset = db::preparedStmt("SELECT profile_key, display_name, role, main_job, sub_job, min_level, max_level, model_id, race, nation, home_zone_id, home_x, home_y, home_z, "
                                           "behavior_profile, gear_profile, persona_key, strategy_stack, route_key, camp_key, mob_group_id, mob_group_zone_id, "
                                           "can_claim, can_loot, can_trade, can_use_auction_house, can_vendor, can_upgrade_gear, can_party, can_llm_chat, commandable, "
                                           "wallet_floor_gil, wallet_ceiling_gil, enabled, notes "
                                           "FROM server_bot_profiles WHERE enabled = 1 ORDER BY profile_key");

        FOR_DB_MULTIPLE_RESULTS(rset)
        {
            auto row = lua.create_table();
            row["profile_key"]           = rset->get<std::string>("profile_key");
            row["display_name"]          = rset->get<std::string>("display_name");
            row["role"]                  = rset->get<std::string>("role");
            row["main_job"]              = rset->get<uint8>("main_job");
            row["sub_job"]               = rset->get<uint8>("sub_job");
            row["min_level"]             = rset->get<uint8>("min_level");
            row["max_level"]             = rset->get<uint8>("max_level");
            row["model_id"]              = rset->get<uint16>("model_id");
            row["race"]                  = rset->get<uint8>("race");
            row["nation"]                = rset->get<uint8>("nation");
            row["home_zone_id"]          = rset->get<uint16>("home_zone_id");
            row["home_x"]                = rset->get<float>("home_x");
            row["home_y"]                = rset->get<float>("home_y");
            row["home_z"]                = rset->get<float>("home_z");
            row["behavior_profile"]      = rset->get<std::string>("behavior_profile");
            row["gear_profile"]          = rset->get<std::string>("gear_profile");
            row["persona_key"]           = rset->get<std::string>("persona_key");
            row["strategy_stack"]        = rset->get<std::string>("strategy_stack");
            row["route_key"]             = rset->getOrDefault<std::string>("route_key", std::string(""));
            row["camp_key"]              = rset->getOrDefault<std::string>("camp_key", std::string(""));
            row["mob_group_id"]          = rset->get<uint16>("mob_group_id");
            row["mob_group_zone_id"]     = rset->get<uint16>("mob_group_zone_id");
            row["can_claim"]             = rset->get<uint8>("can_claim");
            row["can_loot"]              = rset->get<uint8>("can_loot");
            row["can_trade"]             = rset->get<uint8>("can_trade");
            row["can_use_auction_house"] = rset->get<uint8>("can_use_auction_house");
            row["can_vendor"]            = rset->get<uint8>("can_vendor");
            row["can_upgrade_gear"]      = rset->get<uint8>("can_upgrade_gear");
            row["can_party"]             = rset->get<uint8>("can_party");
            row["can_llm_chat"]          = rset->get<uint8>("can_llm_chat");
            row["commandable"]           = rset->get<uint8>("commandable");
            row["wallet_floor_gil"]      = rset->get<uint32>("wallet_floor_gil");
            row["wallet_ceiling_gil"]    = rset->get<uint32>("wallet_ceiling_gil");
            row["enabled"]               = rset->get<uint8>("enabled");
            row["notes"]                 = rset->getOrDefault<std::string>("notes", std::string(""));
            rows.add(row);
        }

        return rows;
    }

    sol::table loadSpawnRules()
    {
        auto rows = lua.create_table();
        const auto rset = db::preparedStmt("SELECT rule_key, zone_id, zone_name, zone_kind, priority, target_count, max_count, max_combat_count, anchor_x, anchor_y, anchor_z, radius, "
                                           "profile_filter, min_level, max_level, route_key, camp_key, required_player_count, allow_combat, allow_economy, enabled "
                                           "FROM server_bot_spawn_rules WHERE enabled = 1 ORDER BY zone_id, priority, rule_key");

        FOR_DB_MULTIPLE_RESULTS(rset)
        {
            auto row = lua.create_table();
            row["rule_key"]              = rset->get<std::string>("rule_key");
            row["zone_id"]               = rset->get<uint16>("zone_id");
            row["zone_name"]             = rset->get<std::string>("zone_name");
            row["zone_kind"]             = rset->get<std::string>("zone_kind");
            row["priority"]              = rset->get<uint8>("priority");
            row["target_count"]          = rset->get<uint8>("target_count");
            row["max_count"]             = rset->get<uint8>("max_count");
            row["max_combat_count"]      = rset->get<uint8>("max_combat_count");
            row["anchor_x"]              = rset->get<float>("anchor_x");
            row["anchor_y"]              = rset->get<float>("anchor_y");
            row["anchor_z"]              = rset->get<float>("anchor_z");
            row["radius"]                = rset->get<float>("radius");
            row["profile_filter"]        = rset->get<std::string>("profile_filter");
            row["min_level"]             = rset->get<uint8>("min_level");
            row["max_level"]             = rset->get<uint8>("max_level");
            row["route_key"]             = rset->getOrDefault<std::string>("route_key", std::string(""));
            row["camp_key"]              = rset->getOrDefault<std::string>("camp_key", std::string(""));
            row["required_player_count"] = rset->get<uint8>("required_player_count");
            row["allow_combat"]          = rset->get<uint8>("allow_combat");
            row["allow_economy"]         = rset->get<uint8>("allow_economy");
            row["enabled"]               = rset->get<uint8>("enabled");
            rows.add(row);
        }

        return rows;
    }

    sol::table loadRoutePoints()
    {
        auto rows = lua.create_table();
        const auto rset = db::preparedStmt("SELECT route_key, point_index, zone_id, x, y, z, wait_ms, point_type "
                                           "FROM server_bot_route_points WHERE enabled = 1 ORDER BY route_key, point_index");

        FOR_DB_MULTIPLE_RESULTS(rset)
        {
            auto row = lua.create_table();
            row["route_key"]   = rset->get<std::string>("route_key");
            row["point_index"] = rset->get<uint16>("point_index");
            row["zone_id"]     = rset->get<uint16>("zone_id");
            row["x"]           = rset->get<float>("x");
            row["y"]           = rset->get<float>("y");
            row["z"]           = rset->get<float>("z");
            row["wait_ms"]     = rset->get<uint32>("wait_ms");
            row["point_type"]  = rset->get<std::string>("point_type");
            rows.add(row);
        }

        return rows;
    }

    sol::table loadCamps()
    {
        auto rows = lua.create_table();
        const auto rset = db::preparedStmt("SELECT camp_key, zone_id, camp_name, min_level, max_level, x, y, z, radius, safe_x, safe_y, safe_z, allowed_families, excluded_mob_names, max_bots "
                                           "FROM server_bot_camps WHERE enabled = 1 ORDER BY zone_id, min_level, camp_key");

        FOR_DB_MULTIPLE_RESULTS(rset)
        {
            auto row = lua.create_table();
            row["camp_key"]           = rset->get<std::string>("camp_key");
            row["zone_id"]            = rset->get<uint16>("zone_id");
            row["camp_name"]          = rset->get<std::string>("camp_name");
            row["min_level"]          = rset->get<uint8>("min_level");
            row["max_level"]          = rset->get<uint8>("max_level");
            row["x"]                  = rset->get<float>("x");
            row["y"]                  = rset->get<float>("y");
            row["z"]                  = rset->get<float>("z");
            row["radius"]             = rset->get<float>("radius");
            row["safe_x"]             = rset->get<float>("safe_x");
            row["safe_y"]             = rset->get<float>("safe_y");
            row["safe_z"]             = rset->get<float>("safe_z");
            row["allowed_families"]   = rset->getOrDefault<std::string>("allowed_families", std::string(""));
            row["excluded_mob_names"] = rset->getOrDefault<std::string>("excluded_mob_names", std::string(""));
            row["max_bots"]           = rset->get<uint8>("max_bots");
            rows.add(row);
        }

        return rows;
    }

    sol::table loadStrategies()
    {
        auto rows = lua.create_table();
        const auto rset = db::preparedStmt("SELECT strategy_key, layer, priority, tick_interval_seconds, params "
                                           "FROM server_bot_strategies WHERE enabled = 1 ORDER BY priority, strategy_key");

        FOR_DB_MULTIPLE_RESULTS(rset)
        {
            auto row = lua.create_table();
            row["strategy_key"]          = rset->get<std::string>("strategy_key");
            row["layer"]                 = rset->get<std::string>("layer");
            row["priority"]              = rset->get<uint8>("priority");
            row["tick_interval_seconds"] = rset->get<uint16>("tick_interval_seconds");
            row["params"]                = rset->getOrDefault<std::string>("params", std::string(""));
            rows.add(row);
        }

        return rows;
    }

    sol::table loadPersonas()
    {
        auto rows = lua.create_table();
        const auto rset = db::preparedStmt("SELECT persona_key, display_style, topic_tags, template_lines, llm_enabled, cooldown_seconds, moderation_profile "
                                           "FROM server_bot_chat_personas WHERE enabled = 1 ORDER BY persona_key");

        FOR_DB_MULTIPLE_RESULTS(rset)
        {
            auto row = lua.create_table();
            row["persona_key"]        = rset->get<std::string>("persona_key");
            row["display_style"]      = rset->get<std::string>("display_style");
            row["topic_tags"]         = rset->get<std::string>("topic_tags");
            row["template_lines"]     = rset->get<std::string>("template_lines");
            row["llm_enabled"]        = rset->get<uint8>("llm_enabled");
            row["cooldown_seconds"]   = rset->get<uint16>("cooldown_seconds");
            row["moderation_profile"] = rset->get<std::string>("moderation_profile");
            rows.add(row);
        }

        return rows;
    }

    sol::table loadCommandPermissions()
    {
        auto rows = lua.create_table();
        const auto rset = db::preparedStmt("SELECT command_key, min_gm_level, player_enabled, rate_limit_seconds, enabled "
                                           "FROM server_bot_command_permissions ORDER BY command_key");

        FOR_DB_MULTIPLE_RESULTS(rset)
        {
            auto row = lua.create_table();
            row["command_key"]        = rset->get<std::string>("command_key");
            row["min_gm_level"]       = rset->get<uint8>("min_gm_level");
            row["player_enabled"]     = rset->get<uint8>("player_enabled");
            row["rate_limit_seconds"] = rset->get<uint16>("rate_limit_seconds");
            row["enabled"]            = rset->get<uint8>("enabled");
            rows.add(row);
        }

        return rows;
    }

    sol::table latestAudit(uint32 limit)
    {
        auto rows = lua.create_table();
        const auto rset = db::preparedStmt("SELECT DATE_FORMAT(created_at, '%Y-%m-%d %H:%i:%s') AS created_at, action, severity, zone_id, bot_key, bot_name, details "
                                           "FROM server_bot_audit_log ORDER BY audit_id DESC LIMIT ?",
                                           limit);

        FOR_DB_MULTIPLE_RESULTS(rset)
        {
            auto row = lua.create_table();
            row["created_at"] = rset->get<std::string>("created_at");
            row["action"]     = rset->get<std::string>("action");
            row["severity"]   = rset->get<std::string>("severity");
            row["zone_id"]    = rset->get<uint16>("zone_id");
            row["bot_key"]    = rset->getOrDefault<std::string>("bot_key", std::string(""));
            row["bot_name"]   = rset->getOrDefault<std::string>("bot_name", std::string(""));
            row["details"]    = rset->getOrDefault<std::string>("details", std::string(""));
            rows.add(row);
        }

        return rows;
    }

    sol::table latestEconomy(uint32 limit)
    {
        auto rows = lua.create_table();
        const auto rset = db::preparedStmt("SELECT DATE_FORMAT(created_at, '%Y-%m-%d %H:%i:%s') AS created_at, bot_key, action, item_id, quantity, gil_delta, capability, status, details "
                                           "FROM server_bot_economy_ledger ORDER BY ledger_id DESC LIMIT ?",
                                           limit);

        FOR_DB_MULTIPLE_RESULTS(rset)
        {
            auto row = lua.create_table();
            row["created_at"] = rset->get<std::string>("created_at");
            row["bot_key"]    = rset->get<std::string>("bot_key");
            row["action"]     = rset->get<std::string>("action");
            row["item_id"]    = rset->get<uint32>("item_id");
            row["quantity"]   = rset->get<int32>("quantity");
            row["gil_delta"]  = rset->get<int32>("gil_delta");
            row["capability"] = rset->get<std::string>("capability");
            row["status"]     = rset->get<std::string>("status");
            row["details"]    = rset->getOrDefault<std::string>("details", std::string(""));
            rows.add(row);
        }

        return rows;
    }

    sol::table latestPerformance(uint32 limit)
    {
        auto rows = lua.create_table();
        const auto rset = db::preparedStmt("SELECT DATE_FORMAT(created_at, '%Y-%m-%d %H:%i:%s') AS created_at, zone_id, active_bots, combat_bots, tick_budget_ms, tick_elapsed_ms, over_budget, details "
                                           "FROM server_bot_performance_snapshots ORDER BY snapshot_id DESC LIMIT ?",
                                           limit);

        FOR_DB_MULTIPLE_RESULTS(rset)
        {
            auto row = lua.create_table();
            row["created_at"]      = rset->get<std::string>("created_at");
            row["zone_id"]         = rset->get<uint16>("zone_id");
            row["active_bots"]     = rset->get<uint16>("active_bots");
            row["combat_bots"]     = rset->get<uint16>("combat_bots");
            row["tick_budget_ms"]  = rset->get<uint16>("tick_budget_ms");
            row["tick_elapsed_ms"] = rset->get<uint16>("tick_elapsed_ms");
            row["over_budget"]     = rset->get<uint8>("over_budget");
            row["details"]         = rset->getOrDefault<std::string>("details", std::string(""));
            rows.add(row);
        }

        return rows;
    }

    bool runtimeEnabled_ = true;
};

REGISTER_CPP_MODULE(ServerBotsModule);
