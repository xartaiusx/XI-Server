/************************************************************************
 * Twills Admin DB Repair
 *
 * Lua owns the character repair flow. This module exposes the narrow DB
 * updates needed for state that is not fully mutable through Lua APIs.
 ************************************************************************/

#include "common/database.h"
#include "entities/char_entity.h"
#include "item_container.h"
#include "items/exdata.h"
#include "lua/lua_base_entity.h"
#include "map/utils/moduleutils.h"
#include "roe.h"
#include "utils/charutils.h"
#include "utils/itemutils.h"

#include <algorithm>
#include <array>
#include <string>
#include <tuple>

namespace
{
constexpr uint16 kMaxCapacityPoints      = 29999;
constexpr uint16 kMaxJobPoints           = 500;
constexpr uint16 kMaxJobPointsSpent      = 2100;
constexpr uint8  kMaxJobPointCategory    = 20;
constexpr uint8  kMaxAlterEgoCategory    = 50;
constexpr uint16 kMaxAlterEgoPointWallet = 1350;
constexpr uint16 kMaxFameValue           = 613;
constexpr uint16 kMaxAbysseaFameValue    = 425;
constexpr uint8  kMaxInventorySize       = 80;
constexpr uint32 kGuildPointWallet       = 200000;
constexpr uint16 kMaxChocobucks          = 1000;
constexpr uint8  kMaxFewell              = 99;
constexpr uint8  kMaxMasterLevel         = 50;
constexpr uint8  kCurrentBootVersion     = 8;
constexpr uint8  kSylvieUnityLeader      = 11;

constexpr uint32 kOutpostMask       = ((1u << 19) - 1u) << 5; // Region bits 5-23.
constexpr uint32 kRunicPortalMask   = 0x0000007Eu;            // Runic portal bits 1-6.
constexpr uint32 kMawMask           = 0x000001FFu;            // Cavernous Maw bits 0-8.
constexpr uint32 kCampaignMask      = 0x001FFFFEu;            // Campaign teleport bits 1-20.
constexpr uint32 kExpectedHomepoint = 122;
constexpr uint32 kExpectedSurvival  = 96;
constexpr uint32 kExpectedAbyssea   = 72;
constexpr uint32 kExpectedWaypoint  = 55;
constexpr uint32 kExpectedEscha     = 32;

constexpr const char* kHomepointBlob      = "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0300000000000000000000000000000000000000000000000000000000000000000000000000000000";
constexpr const char* kSurvivalBlob       = "FFFFFFFFFFFFFFFFFFFFFFFF0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
constexpr const char* kAbysseaConfluxBlob = "FFFFFFFFFFFFFFFFFF";
constexpr const char* kWaypointBlob       = "FFFFFFFFFFFF7F0001";
constexpr const char* kEschaPortalBlob    = "FFFFFFFF";

constexpr std::array<uint8, 9> kGearContainers = {
    LOC_WARDROBE,
    LOC_WARDROBE2,
    LOC_WARDROBE3,
    LOC_WARDROBE4,
    LOC_WARDROBE5,
    LOC_WARDROBE6,
    LOC_WARDROBE7,
    LOC_WARDROBE8,
    LOC_INVENTORY,
};

auto getCharacter(CLuaBaseEntity* luaEntity) -> CCharEntity*
{
    if (luaEntity == nullptr)
    {
        return nullptr;
    }

    return dynamic_cast<CCharEntity*>(luaEntity->GetBaseEntity());
}

auto findGearContainer(CCharEntity* PChar, uint8 preferredContainer) -> uint8
{
    if (preferredContainer < CONTAINER_ID::MAX_CONTAINER_ID && PChar->getStorage(preferredContainer)->GetFreeSlotsCount() > 0)
    {
        return preferredContainer;
    }

    for (const auto containerId : kGearContainers)
    {
        if (containerId != preferredContainer && PChar->getStorage(containerId)->GetFreeSlotsCount() > 0)
        {
            return containerId;
        }
    }

    return ERROR_SLOTID;
}

auto grantGear(CLuaBaseEntity* luaEntity, sol::table gearItems) -> std::tuple<uint16, uint16>
{
    auto* PChar = getCharacter(luaEntity);
    if (PChar == nullptr)
    {
        return { 0, 1 };
    }

    uint16 granted = 0;
    uint16 failed  = 0;

    for (const auto& [_, entryObj] : gearItems)
    {
        if (!entryObj.is<sol::table>())
        {
            continue;
        }

        const auto entry       = entryObj.as<sol::table>();
        const auto itemId      = entry.get_or<uint16>("id", 0);
        const auto targetCount = entry.get_or<uint32>("targetCount", 1);
        if (itemId == 0 || targetCount == 0)
        {
            ++failed;
            continue;
        }

        if (charutils::getItemCount(PChar, itemId) >= targetCount)
        {
            continue;
        }

        auto PItem = xi::items::spawn(itemId);
        if (PItem == nullptr)
        {
            ++failed;
            continue;
        }

        PItem->setQuantity(entry.get_or<uint32>("quantity", 1));

        const sol::object exdataObj = entry["exdata"];
        if (exdataObj.is<sol::table>())
        {
            Exdata::fromTable(PItem.get(), exdataObj.as<sol::table>());
        }

        const auto preferredContainer = entry.get_or<uint8>("container", LOC_WARDROBE);
        const auto containerId        = findGearContainer(PChar, preferredContainer);
        if (containerId == ERROR_SLOTID)
        {
            ++failed;
            continue;
        }

        if (charutils::AddItem(PChar, containerId, std::move(PItem), true) == ERROR_SLOTID)
        {
            ++failed;
        }
        else
        {
            ++granted;
        }
    }

    return { granted, failed };
}

void addAuditLine(sol::table& rows, uint32& index, bool ok, const std::string& label, const std::string& details)
{
    rows[index++] = std::string(ok ? "[OK] " : "[FIX] ") + label + ": " + details;
}

auto countBits(uint32 value) -> uint32
{
    uint32 count = 0;
    while (value != 0)
    {
        count += value & 1u;
        value >>= 1u;
    }

    return count;
}

auto countBits(const std::string& bytes, const size_t maxBytes) -> uint32
{
    uint32     count = 0;
    const auto limit = std::min(bytes.size(), maxBytes);

    for (size_t i = 0; i < limit; ++i)
    {
        count += countBits(static_cast<uint8>(bytes[i]));
    }

    return count;
}

auto countBlobBits(const auto& rset, const std::string& column, const size_t maxBytes) -> uint32
{
    if (rset->isNull(column))
    {
        return 0;
    }

    return countBits(rset->getBlobBytes(column), maxBytes);
}

auto auditDbState(sol::this_state state, uint32 charId) -> sol::table
{
    sol::state_view lua(state);
    auto            rows  = lua.create_table();
    uint32          index = 1;

    if (charId == 0)
    {
        addAuditLine(rows, index, false, "Target", "missing character id");
        return rows;
    }

    if (const auto rset = db::preparedStmt(
            "SELECT c.gmlevel, c.nation, s.mjob, s.sjob, s.mlvl, s.slvl, "
            "j.unlocked, j.genkai, j.rdm, j.sch, ml.master_level, ml.exemplar_points "
            "FROM chars c "
            "JOIN char_stats s ON s.charid = c.charid "
            "JOIN char_jobs j ON j.charid = c.charid "
            "LEFT JOIN char_master_levels ml ON ml.charid = c.charid AND ml.jobid = 5 "
            "WHERE c.charid = ? LIMIT 1",
            charId);
        rset && rset->rowsCount() && rset->next())
    {
        const auto gmLevel     = rset->get<uint16>("gmlevel");
        const auto nation      = rset->get<uint8>("nation");
        const auto mainJob     = rset->get<uint8>("mjob");
        const auto subJob      = rset->get<uint8>("sjob");
        const auto mainLevel   = rset->get<uint8>("mlvl");
        const auto subLevel    = rset->get<uint8>("slvl");
        const auto unlocked    = rset->get<uint32>("unlocked");
        const auto genkai      = rset->get<uint8>("genkai");
        const auto rdmLevel    = rset->get<uint8>("rdm");
        const auto schLevel    = rset->get<uint8>("sch");
        const auto masterLevel = rset->get<uint8>("master_level");

        const bool ok = gmLevel == 5 && nation == 0 && mainJob == 5 && subJob == 20 && mainLevel == 99 && subLevel == 59 &&
                        unlocked == 8388607 && genkai == 99 && rdmLevel == 99 && schLevel == 99 && masterLevel == kMaxMasterLevel;

        addAuditLine(rows, index, ok, "Core RDM/SCH", "gm=" + std::to_string(gmLevel) + ", nation=" + std::to_string(nation) + ", active=" + std::to_string(mainJob) + "/" + std::to_string(subJob) + " " + std::to_string(mainLevel) + "/" + std::to_string(subLevel) + ", rdm=" + std::to_string(rdmLevel) + ", sch=" + std::to_string(schLevel) + ", ml=" + std::to_string(masterLevel));
    }
    else
    {
        addAuditLine(rows, index, false, "Core RDM/SCH", "character rows missing");
    }

    if (const auto rset = db::preparedStmt(
            "SELECT COUNT(*) AS master_rows FROM char_master_levels WHERE charid = ? AND master_level = ?",
            charId,
            kMaxMasterLevel);
        rset && rset->rowsCount() && rset->next())
    {
        const auto masterRows = rset->get<uint8>("master_rows");
        addAuditLine(rows, index, masterRows == 22, "Master Levels", std::to_string(masterRows) + "/22 jobs at ML" + std::to_string(kMaxMasterLevel));
    }

    if (const auto rset = db::preparedStmt(
            "SELECT COUNT(*) AS good_rows FROM char_job_points "
            "WHERE charid = ? AND job_points = ? AND job_points_spent = ? "
            "AND jptype0 = ? AND jptype1 = ? AND jptype2 = ? AND jptype3 = ? AND jptype4 = ? "
            "AND jptype5 = ? AND jptype6 = ? AND jptype7 = ? AND jptype8 = ? AND jptype9 = ?",
            charId,
            kMaxJobPoints,
            kMaxJobPointsSpent,
            kMaxJobPointCategory,
            kMaxJobPointCategory,
            kMaxJobPointCategory,
            kMaxJobPointCategory,
            kMaxJobPointCategory,
            kMaxJobPointCategory,
            kMaxJobPointCategory,
            kMaxJobPointCategory,
            kMaxJobPointCategory,
            kMaxJobPointCategory);
        rset && rset->rowsCount() && rset->next())
    {
        const auto goodRows = rset->get<uint8>("good_rows");
        addAuditLine(rows, index, goodRows == 22, "Job Points", std::to_string(goodRows) + "/22 jobs at 2100 spent JP, 500 held JP, 20/20 categories");
    }

    if (const auto rset = db::preparedStmt(
            "SELECT "
            "(SELECT COUNT(*) FROM spell_list WHERE spellid IN (882, 883, 884, 894, 895)) AS server_defs, "
            "(SELECT COUNT(*) FROM char_spells WHERE charid = ? AND spellid IN (882, 883, 884, 894, 895)) AS learned",
            charId);
        rset && rset->rowsCount() && rset->next())
    {
        const auto serverDefs = rset->get<uint8>("server_defs");
        const auto learned    = rset->get<uint8>("learned");
        addAuditLine(rows, index, serverDefs == 5 && learned == 5, "RDM JP Spells", std::to_string(learned) + "/5 learned, " + std::to_string(serverDefs) + "/5 server definitions");
    }

    if (const auto rset = db::preparedStmt(
            "SELECT "
            "(SELECT COUNT(*) FROM char_spells cs LEFT JOIN spell_list sl ON sl.spellid = cs.spellid WHERE cs.charid = ? AND sl.spellid IS NULL) AS undefined_spells, "
            "(SELECT COUNT(*) FROM spell_list WHERE spellid = 1002) AS cornelia_def, "
            "(SELECT COUNT(*) FROM char_spells WHERE charid = ? AND spellid = 1002) AS cornelia_learned",
            charId,
            charId);
        rset && rset->rowsCount() && rset->next())
    {
        const auto undefinedSpells = rset->get<uint16>("undefined_spells");
        const auto corneliaDef     = rset->get<uint8>("cornelia_def");
        const auto corneliaLearned = rset->get<uint8>("cornelia_learned");
        const bool ok              = undefinedSpells == 0 && (corneliaDef == 0 || corneliaLearned == 1);
        addAuditLine(rows, index, ok, "Spellbook Consistency", std::to_string(undefinedSpells) + " undefined learned spells, Cornelia " + (corneliaDef == 0 ? "not locally defined" : (corneliaLearned == 1 ? "learned" : "missing")));
    }

    if (const auto rset = db::preparedStmt(
            "SELECT "
            "(SELECT COUNT(*) FROM merits) AS expected, "
            "(SELECT COUNT(*) FROM char_merit cm JOIN merits m ON m.meritid = cm.meritid "
            " WHERE cm.charid = ? AND cm.upgrades = m.upgrade) AS matched",
            charId);
        rset && rset->rowsCount() && rset->next())
    {
        const auto expected = rset->get<uint16>("expected");
        const auto matched  = rset->get<uint16>("matched");
        addAuditLine(rows, index, expected == matched, "Merits", std::to_string(matched) + "/" + std::to_string(expected) + " local merits at implemented max");
    }

    if (const auto rset = db::preparedStmt(
            "SELECT "
            "(SELECT alter_ego_points FROM char_points WHERE charid = ?) AS wallet, "
            "(SELECT COUNT(*) FROM char_vars WHERE charid = ? AND value = ? AND varname IN ("
            "'AlterEgoPoints_HP', 'AlterEgoPoints_MP', 'AlterEgoPoints_STR', 'AlterEgoPoints_DEX', "
            "'AlterEgoPoints_VIT', 'AlterEgoPoints_AGI', 'AlterEgoPoints_INT', 'AlterEgoPoints_MND', "
            "'AlterEgoPoints_CHR', 'AlterEgoPoints_CombatSkills', 'AlterEgoPoints_MagicSkills')) AS categories",
            charId,
            charId,
            kMaxAlterEgoCategory);
        rset && rset->rowsCount() && rset->next())
    {
        const auto wallet     = rset->get<uint16>("wallet");
        const auto categories = rset->get<uint8>("categories");
        addAuditLine(rows, index, wallet == kMaxAlterEgoPointWallet && categories == 11, "Alter Ego Points", "wallet=" + std::to_string(wallet) + ", categories=" + std::to_string(categories) + "/11 at 50");
    }

    if (const auto rset = db::preparedStmt(
            "SELECT inventory, safe, locker, satchel, sack, `case`, wardrobe, wardrobe2, wardrobe3, wardrobe4, "
            "wardrobe5, wardrobe6, wardrobe7, wardrobe8 FROM char_storage WHERE charid = ? LIMIT 1",
            charId);
        rset && rset->rowsCount() && rset->next())
    {
        const bool ok = rset->get<uint8>("inventory") == 80 && rset->get<uint8>("safe") == 80 && rset->get<uint8>("locker") == 80 &&
                        rset->get<uint8>("satchel") == 80 && rset->get<uint8>("sack") == 80 && rset->get<uint8>("case") == 80 &&
                        rset->get<uint8>("wardrobe") == 80 && rset->get<uint8>("wardrobe2") == 80 && rset->get<uint8>("wardrobe3") == 80 &&
                        rset->get<uint8>("wardrobe4") == 80 && rset->get<uint8>("wardrobe5") == 80 && rset->get<uint8>("wardrobe6") == 80 &&
                        rset->get<uint8>("wardrobe7") == 80 && rset->get<uint8>("wardrobe8") == 80;
        addAuditLine(rows, index, ok, "Storage", ok ? "all tracked containers at 80" : "one or more tracked containers below 80");
    }

    if (const auto rset = db::preparedStmt(
            "SELECT COUNT(*) AS good_crafts FROM char_skills WHERE charid = ? AND ("
            "(skillid = 48 AND value = 1100 AND rank = 10) OR "
            "(skillid = 49 AND value = 700 AND rank = 6) OR "
            "(skillid = 50 AND value = 700 AND rank = 6) OR "
            "(skillid = 51 AND value = 700 AND rank = 6) OR "
            "(skillid = 52 AND value = 700 AND rank = 6) OR "
            "(skillid = 53 AND value = 700 AND rank = 6) OR "
            "(skillid = 54 AND value = 700 AND rank = 6) OR "
            "(skillid = 55 AND value = 1100 AND rank = 10) OR "
            "(skillid = 56 AND value = 700 AND rank = 6) OR "
            "(skillid = 57 AND value = 800 AND rank = 7))",
            charId);
        rset && rset->rowsCount() && rset->next())
    {
        const auto goodCrafts = rset->get<uint8>("good_crafts");
        addAuditLine(rows, index, goodCrafts == 10, "Crafts", std::to_string(goodCrafts) + "/10 strict retail-shaped craft caps/ranks");
    }

    if (const auto rset = db::preparedStmt(
            "SELECT rank_sandoria, rank_bastok, rank_windurst, fame_sandoria, fame_bastok, fame_windurst, fame_norg, fame_jeuno, fame_adoulin "
            "FROM char_profile WHERE charid = ? LIMIT 1",
            charId);
        rset && rset->rowsCount() && rset->next())
    {
        const bool ok = rset->get<uint8>("rank_sandoria") == 10 && rset->get<uint8>("rank_bastok") == 10 &&
                        rset->get<uint8>("rank_windurst") == 10 && rset->get<uint16>("fame_sandoria") == kMaxFameValue &&
                        rset->get<uint16>("fame_bastok") == kMaxFameValue && rset->get<uint16>("fame_windurst") == kMaxFameValue &&
                        rset->get<uint16>("fame_norg") == kMaxFameValue && rset->get<uint16>("fame_jeuno") == kMaxFameValue &&
                        rset->get<uint16>("fame_adoulin") == kMaxFameValue;
        addAuditLine(rows, index, ok, "Ranks/Fame", ok ? "all nations rank 10 and major fame values capped" : "rank/fame mismatch");
    }

    if (const auto rset = db::preparedStmt(
            "SELECT color, strength, endurance, ability1, ability2, conditions FROM char_chocobos WHERE charid = ? LIMIT 1",
            charId);
        rset && rset->rowsCount() && rset->next())
    {
        const bool ok = rset->get<uint8>("color") == 1 && rset->get<uint8>("strength") == 255 && rset->get<uint8>("endurance") == 255 &&
                        rset->get<uint8>("ability1") == 1 && rset->get<uint8>("ability2") == 2 && rset->get<uint32>("conditions") == 0;
        addAuditLine(rows, index, ok, "Chocobo", ok ? "black Gallop/Canter, max strength/endurance, no bad conditions" : "raised chocobo state mismatch");
    }

    if (const auto rset = db::preparedStmt(
            "SELECT outpost_sandy, outpost_bastok, outpost_windy, runic_portal, maw, "
            "campaign_sandy, campaign_bastok, campaign_windy, homepoints, survivals, "
            "abyssea_conflux, waypoints, eschan_portals "
            "FROM char_unlocks WHERE charid = ? LIMIT 1",
            charId);
        rset && rset->rowsCount() && rset->next())
    {
        const bool fixedMaskOk =
            (rset->get<uint32>("outpost_sandy") & kOutpostMask) == kOutpostMask &&
            (rset->get<uint32>("outpost_bastok") & kOutpostMask) == kOutpostMask &&
            (rset->get<uint32>("outpost_windy") & kOutpostMask) == kOutpostMask &&
            (rset->get<uint32>("runic_portal") & kRunicPortalMask) == kRunicPortalMask &&
            (rset->get<uint32>("maw") & kMawMask) == kMawMask &&
            (rset->get<uint32>("campaign_sandy") & kCampaignMask) == kCampaignMask &&
            (rset->get<uint32>("campaign_bastok") & kCampaignMask) == kCampaignMask &&
            (rset->get<uint32>("campaign_windy") & kCampaignMask) == kCampaignMask;

        const auto homepoints = countBlobBits(rset, "homepoints", 16);
        const auto survivals  = countBlobBits(rset, "survivals", 16);
        const auto abyssea    = countBlobBits(rset, "abyssea_conflux", 9);
        const auto waypoints  = countBlobBits(rset, "waypoints", 8);
        const auto escha      = countBlobBits(rset, "eschan_portals", 4);
        const bool blobOk     = homepoints >= kExpectedHomepoint && survivals >= kExpectedSurvival && abyssea >= kExpectedAbyssea &&
                                waypoints >= kExpectedWaypoint && escha >= kExpectedEscha;

        addAuditLine(rows, index, fixedMaskOk && blobOk, "Travel Unlocks", "HP " + std::to_string(homepoints) + "/" + std::to_string(kExpectedHomepoint) + ", SG " + std::to_string(survivals) + "/" + std::to_string(kExpectedSurvival) + ", Abyssea " + std::to_string(abyssea) + "/" + std::to_string(kExpectedAbyssea) + ", Waypoints " + std::to_string(waypoints) + "/" + std::to_string(kExpectedWaypoint) + ", Escha " + std::to_string(escha) + "/" + std::to_string(kExpectedEscha) + (fixedMaskOk ? ", fixed masks complete" : ", fixed mask category missing"));
    }

    if (const auto rset = db::preparedStmt(
            "SELECT cp.unity_accolades, cp.spark_of_eminence, cp.valor_point, cp.current_accolades, cp.prev_accolades, "
            "cp.domain_points, cp.mog_segments, cp.gallimaufry, cp.temenos_units, cp.apollyon_units, "
            "p.unity_leader, us.members_prev, us.points_prev "
            "FROM char_points cp "
            "JOIN char_profile p ON p.charid = cp.charid "
            "LEFT JOIN unity_system us ON us.leader = p.unity_leader "
            "WHERE cp.charid = ? LIMIT 1",
            charId);
        rset && rset->rowsCount() && rset->next())
    {
        const bool ok = rset->get<uint8>("unity_leader") == kSylvieUnityLeader &&
                        rset->get<uint32>("unity_accolades") >= 99999 &&
                        rset->get<uint32>("spark_of_eminence") >= 99999 &&
                        rset->get<uint32>("valor_point") >= 50000 &&
                        rset->get<uint32>("current_accolades") >= 2500000 &&
                        rset->get<uint32>("prev_accolades") >= 2500000 &&
                        rset->get<uint32>("domain_points") >= 800 &&
                        rset->get<uint32>("mog_segments") >= 999999 &&
                        rset->get<uint32>("gallimaufry") >= 999999 &&
                        rset->get<uint32>("temenos_units") >= 999999 &&
                        rset->get<uint32>("apollyon_units") >= 999999 &&
                        rset->get<uint32>("members_prev") >= 1 &&
                        rset->get<double>("points_prev") >= 1000000.0;

        addAuditLine(rows, index, ok, "Veteran Currencies/Unity", "Sylvie leader=" + std::to_string(rset->get<uint8>("unity_leader")) + ", sparks=" + std::to_string(rset->get<uint32>("spark_of_eminence")) + ", accolades=" + std::to_string(rset->get<uint32>("unity_accolades")) + ", current_eval=" + std::to_string(rset->get<uint32>("current_accolades")) + ", domain=" + std::to_string(rset->get<uint32>("domain_points")) + ", segments=" + std::to_string(rset->get<uint32>("mog_segments")) + ", gallimaufry=" + std::to_string(rset->get<uint32>("gallimaufry")));
    }

    if (const auto rset = db::preparedStmt(
            "SELECT "
            "SUM(varname = 'TwillsBootVersion' AND value >= ?) AS boot_ok, "
            "SUM(varname = 'TwillsRdmSchGearVersion' AND value >= 3) AS gear_ok, "
            "SUM(varname = 'TrustEngageType' AND value = 1) AS trust_ok "
            "FROM char_vars WHERE charid = ? AND varname IN ('TwillsBootVersion', 'TwillsRdmSchGearVersion', 'TrustEngageType')",
            kCurrentBootVersion,
            charId);
        rset && rset->rowsCount() && rset->next())
    {
        const bool ok = rset->get<uint8>("boot_ok") == 1 && rset->get<uint8>("gear_ok") == 1 && rset->get<uint8>("trust_ok") == 1;
        addAuditLine(rows, index, ok, "Repair Markers", ok ? "boot v8, gear v3, TrustEngageType 1" : "repair marker mismatch");
    }

    return rows;
}

void repairCrafts(uint32 charId)
{
    struct CraftSkill
    {
        uint8  skillId;
        uint16 value;
        uint8  rank;
    };

    // Retail-shaped caps: one synthesis craft over 70, plus Fishing/Synergy as
    // exceptions. Values are tenths of a skill level.
    static constexpr std::array<CraftSkill, 10> kCraftSkills = {
        CraftSkill{ 48, 1100, 10 }, // Fishing 110 Expert
        CraftSkill{ 49, 700, 6 },   // Woodworking 70 Craftsman
        CraftSkill{ 50, 700, 6 },   // Smithing 70 Craftsman
        CraftSkill{ 51, 700, 6 },   // Goldsmithing 70 Craftsman
        CraftSkill{ 52, 700, 6 },   // Clothcraft 70 Craftsman
        CraftSkill{ 53, 700, 6 },   // Leathercraft 70 Craftsman
        CraftSkill{ 54, 700, 6 },   // Bonecraft 70 Craftsman
        CraftSkill{ 55, 1100, 10 }, // Alchemy 110 Expert
        CraftSkill{ 56, 700, 6 },   // Cooking 70 Craftsman
        CraftSkill{ 57, 800, 7 },   // Synergy 80 Artisan
    };

    for (const auto& craft : kCraftSkills)
    {
        db::preparedStmt(
            "INSERT INTO char_skills (charid, skillid, value, rank) "
            "VALUES (?, ?, ?, ?) "
            "ON DUPLICATE KEY UPDATE value = VALUES(value), rank = VALUES(rank)",
            charId,
            craft.skillId,
            craft.value,
            craft.rank);
    }

    db::preparedStmt(
        "INSERT INTO char_points "
        "(charid, guild_fishing, guild_woodworking, guild_smithing, guild_goldsmithing, "
        "guild_weaving, guild_leathercraft, guild_bonecraft, guild_alchemy, guild_cooking, "
        "fire_fewell, ice_fewell, wind_fewell, earth_fewell, lightning_fewell, water_fewell, "
        "light_fewell, dark_fewell, chocobuck_sandoria, chocobuck_bastok, chocobuck_windurst) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
        "ON DUPLICATE KEY UPDATE "
        "guild_fishing = VALUES(guild_fishing), guild_woodworking = VALUES(guild_woodworking), "
        "guild_smithing = VALUES(guild_smithing), guild_goldsmithing = VALUES(guild_goldsmithing), "
        "guild_weaving = VALUES(guild_weaving), guild_leathercraft = VALUES(guild_leathercraft), "
        "guild_bonecraft = VALUES(guild_bonecraft), guild_alchemy = VALUES(guild_alchemy), "
        "guild_cooking = VALUES(guild_cooking), fire_fewell = VALUES(fire_fewell), "
        "ice_fewell = VALUES(ice_fewell), wind_fewell = VALUES(wind_fewell), "
        "earth_fewell = VALUES(earth_fewell), lightning_fewell = VALUES(lightning_fewell), "
        "water_fewell = VALUES(water_fewell), light_fewell = VALUES(light_fewell), "
        "dark_fewell = VALUES(dark_fewell), chocobuck_sandoria = VALUES(chocobuck_sandoria), "
        "chocobuck_bastok = VALUES(chocobuck_bastok), chocobuck_windurst = VALUES(chocobuck_windurst)",
        charId,
        kGuildPointWallet,
        kGuildPointWallet,
        kGuildPointWallet,
        kGuildPointWallet,
        kGuildPointWallet,
        kGuildPointWallet,
        kGuildPointWallet,
        kGuildPointWallet,
        kGuildPointWallet,
        kMaxFewell,
        kMaxFewell,
        kMaxFewell,
        kMaxFewell,
        kMaxFewell,
        kMaxFewell,
        kMaxFewell,
        kMaxFewell,
        kMaxChocobucks,
        kMaxChocobucks,
        kMaxChocobucks);
}

void repairJobPoints(uint32 charId)
{
    for (uint8 jobId = 1; jobId <= 22; ++jobId)
    {
        db::preparedStmt(
            "INSERT INTO char_job_points "
            "(charid, jobid, capacity_points, job_points, job_points_spent, "
            "jptype0, jptype1, jptype2, jptype3, jptype4, jptype5, jptype6, jptype7, jptype8, jptype9) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
            "ON DUPLICATE KEY UPDATE "
            "capacity_points = VALUES(capacity_points), "
            "job_points = VALUES(job_points), "
            "job_points_spent = VALUES(job_points_spent), "
            "jptype0 = VALUES(jptype0), jptype1 = VALUES(jptype1), jptype2 = VALUES(jptype2), "
            "jptype3 = VALUES(jptype3), jptype4 = VALUES(jptype4), jptype5 = VALUES(jptype5), "
            "jptype6 = VALUES(jptype6), jptype7 = VALUES(jptype7), jptype8 = VALUES(jptype8), "
            "jptype9 = VALUES(jptype9)",
            charId,
            jobId,
            kMaxCapacityPoints,
            kMaxJobPoints,
            kMaxJobPointsSpent,
            kMaxJobPointCategory,
            kMaxJobPointCategory,
            kMaxJobPointCategory,
            kMaxJobPointCategory,
            kMaxJobPointCategory,
            kMaxJobPointCategory,
            kMaxJobPointCategory,
            kMaxJobPointCategory,
            kMaxJobPointCategory,
            kMaxJobPointCategory);
    }
}

void repairMasterLevels(uint32 charId)
{
    db::preparedStmt(
        "CREATE TABLE IF NOT EXISTS char_master_levels ("
        "charid int(10) unsigned NOT NULL, "
        "jobid tinyint(2) unsigned NOT NULL, "
        "master_level tinyint(2) unsigned NOT NULL DEFAULT 0, "
        "exemplar_points int(10) unsigned NOT NULL DEFAULT 0, "
        "updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(), "
        "PRIMARY KEY (charid, jobid), "
        "CONSTRAINT char_master_levels_jobid_chk CHECK (jobid BETWEEN 1 AND 22), "
        "CONSTRAINT char_master_levels_level_chk CHECK (master_level <= 50)"
        ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci");

    for (uint8 jobId = 1; jobId <= 22; ++jobId)
    {
        db::preparedStmt(
            "INSERT INTO char_master_levels (charid, jobid, master_level, exemplar_points) "
            "VALUES (?, ?, ?, 0) "
            "ON DUPLICATE KEY UPDATE master_level = VALUES(master_level), exemplar_points = 0",
            charId,
            jobId,
            kMaxMasterLevel);
    }

    db::preparedStmt(
        "UPDATE char_stats SET mjob = ?, sjob = ?, mlvl = 99, slvl = 59 WHERE charid = ? LIMIT 1",
        JOB_RDM,
        JOB_SCH,
        charId);
}

void repairTravelUnlocks(uint32 charId)
{
    db::preparedStmt(
        "INSERT INTO char_unlocks (charid) VALUES (?) ON DUPLICATE KEY UPDATE charid = VALUES(charid)",
        charId);

    db::preparedStmt(
        "UPDATE char_unlocks SET "
        "outpost_sandy = outpost_sandy | ?, outpost_bastok = outpost_bastok | ?, outpost_windy = outpost_windy | ?, "
        "runic_portal = runic_portal | ?, maw = maw | ?, "
        "campaign_sandy = campaign_sandy | ?, campaign_bastok = campaign_bastok | ?, campaign_windy = campaign_windy | ?, "
        "homepoints = UNHEX(?), survivals = UNHEX(?), abyssea_conflux = UNHEX(?), "
        "waypoints = UNHEX(?), eschan_portals = UNHEX(?) "
        "WHERE charid = ? LIMIT 1",
        kOutpostMask,
        kOutpostMask,
        kOutpostMask,
        kRunicPortalMask,
        kMawMask,
        kCampaignMask,
        kCampaignMask,
        kCampaignMask,
        kHomepointBlob,
        kSurvivalBlob,
        kAbysseaConfluxBlob,
        kWaypointBlob,
        kEschaPortalBlob,
        charId);
}

void updateCurrencyFloor(uint32 charId, const char* column, uint32 value)
{
    const std::string query = std::string("UPDATE char_points SET ") + column + " = GREATEST(" + column + ", ?) WHERE charid = ? LIMIT 1";
    db::preparedStmt(query, value, charId);
}

void repairVeteranCurrencies(uint32 charId)
{
    db::preparedStmt(
        "INSERT INTO char_points (charid) VALUES (?) ON DUPLICATE KEY UPDATE charid = VALUES(charid)",
        charId);

    struct CurrencyFloor
    {
        const char* column;
        uint32      value;
    };

    static constexpr std::array kCurrencyFloors = {
        CurrencyFloor{ "sandoria_cp", 99999 },
        CurrencyFloor{ "bastok_cp", 99999 },
        CurrencyFloor{ "windurst_cp", 99999 },
        CurrencyFloor{ "beastman_seal", 9999 },
        CurrencyFloor{ "kindred_seal", 9999 },
        CurrencyFloor{ "kindred_crest", 9999 },
        CurrencyFloor{ "high_kindred_crest", 9999 },
        CurrencyFloor{ "sacred_kindred_crest", 9999 },
        CurrencyFloor{ "ancient_beastcoin", 9999 },
        CurrencyFloor{ "valor_point", 50000 },
        CurrencyFloor{ "scyld", 1000 },
        CurrencyFloor{ "ballista_point", 5000 },
        CurrencyFloor{ "fellow_point", 5000 },
        CurrencyFloor{ "moblin_marble", 99999 },
        CurrencyFloor{ "legion_point", 99999 },
        CurrencyFloor{ "spark_of_eminence", 99999 },
        CurrencyFloor{ "shining_star", 99999 },
        CurrencyFloor{ "imperial_standing", 99999 },
        CurrencyFloor{ "leujaoam_assault_point", 99999 },
        CurrencyFloor{ "mamool_assault_point", 99999 },
        CurrencyFloor{ "lebros_assault_point", 99999 },
        CurrencyFloor{ "periqia_assault_point", 99999 },
        CurrencyFloor{ "ilrusi_assault_point", 99999 },
        CurrencyFloor{ "nyzul_isle_assault_point", 99999 },
        CurrencyFloor{ "zeni_point", 99999 },
        CurrencyFloor{ "jetton", 99999 },
        CurrencyFloor{ "therion_ichor", 99999 },
        CurrencyFloor{ "allied_notes", 99999 },
        CurrencyFloor{ "aman_vouchers", 999 },
        CurrencyFloor{ "login_points", 1500 },
        CurrencyFloor{ "bayld", 999999 },
        CurrencyFloor{ "kinetic_unit", 50000 },
        CurrencyFloor{ "obsidian_fragment", 999999 },
        CurrencyFloor{ "lebondopt_wing", 9999 },
        CurrencyFloor{ "pulchridopt_wing", 9999 },
        CurrencyFloor{ "mweya_plasm", 999999 },
        CurrencyFloor{ "cruor", 9999999 },
        CurrencyFloor{ "resistance_credit", 999999 },
        CurrencyFloor{ "dominion_note", 999999 },
        CurrencyFloor{ "fifth_echelon_trophy", 50 },
        CurrencyFloor{ "fourth_echelon_trophy", 50 },
        CurrencyFloor{ "third_echelon_trophy", 50 },
        CurrencyFloor{ "second_echelon_trophy", 50 },
        CurrencyFloor{ "first_echelon_trophy", 50 },
        CurrencyFloor{ "cave_points", 50 },
        CurrencyFloor{ "id_tags", 15 },
        CurrencyFloor{ "op_credits", 255 },
        CurrencyFloor{ "traverser_stones", 9999 },
        CurrencyFloor{ "voidstones", 9999 },
        CurrencyFloor{ "kupofried_corundums", 9999 },
        CurrencyFloor{ "imprimaturs", 15 },
        CurrencyFloor{ "pheromone_sacks", 99 },
        CurrencyFloor{ "rems_ch1", 99 },
        CurrencyFloor{ "rems_ch2", 99 },
        CurrencyFloor{ "rems_ch3", 99 },
        CurrencyFloor{ "rems_ch4", 99 },
        CurrencyFloor{ "rems_ch5", 99 },
        CurrencyFloor{ "rems_ch6", 99 },
        CurrencyFloor{ "rems_ch7", 99 },
        CurrencyFloor{ "rems_ch8", 99 },
        CurrencyFloor{ "rems_ch9", 99 },
        CurrencyFloor{ "rems_ch10", 99 },
        CurrencyFloor{ "reclamation_marks", 999 },
        CurrencyFloor{ "unity_accolades", 99999 },
        CurrencyFloor{ "fire_crystals", 5000 },
        CurrencyFloor{ "ice_crystals", 5000 },
        CurrencyFloor{ "wind_crystals", 5000 },
        CurrencyFloor{ "earth_crystals", 5000 },
        CurrencyFloor{ "lightning_crystals", 5000 },
        CurrencyFloor{ "water_crystals", 5000 },
        CurrencyFloor{ "light_crystals", 5000 },
        CurrencyFloor{ "dark_crystals", 5000 },
        CurrencyFloor{ "deeds", 999 },
        CurrencyFloor{ "current_accolades", 2500000 },
        CurrencyFloor{ "prev_accolades", 2500000 },
        CurrencyFloor{ "mystical_canteen", 3 },
        CurrencyFloor{ "ghastly_stone", 99 },
        CurrencyFloor{ "ghastly_stone_1", 99 },
        CurrencyFloor{ "ghastly_stone_2", 99 },
        CurrencyFloor{ "verdigris_stone", 99 },
        CurrencyFloor{ "verdigris_stone_1", 99 },
        CurrencyFloor{ "verdigris_stone_2", 99 },
        CurrencyFloor{ "wailing_stone", 99 },
        CurrencyFloor{ "wailing_stone_1", 99 },
        CurrencyFloor{ "wailing_stone_2", 99 },
        CurrencyFloor{ "snowslit_stone", 99 },
        CurrencyFloor{ "snowslit_stone_1", 99 },
        CurrencyFloor{ "snowslit_stone_2", 99 },
        CurrencyFloor{ "snowtip_stone", 99 },
        CurrencyFloor{ "snowtip_stone_1", 99 },
        CurrencyFloor{ "snowtip_stone_2", 99 },
        CurrencyFloor{ "snowdim_stone", 99 },
        CurrencyFloor{ "snowdim_stone_1", 99 },
        CurrencyFloor{ "snowdim_stone_2", 99 },
        CurrencyFloor{ "snoworb_stone", 99 },
        CurrencyFloor{ "snoworb_stone_1", 99 },
        CurrencyFloor{ "snoworb_stone_2", 99 },
        CurrencyFloor{ "leafslit_stone", 99 },
        CurrencyFloor{ "leafslit_stone_1", 99 },
        CurrencyFloor{ "leafslit_stone_2", 99 },
        CurrencyFloor{ "leaftip_stone", 99 },
        CurrencyFloor{ "leaftip_stone_1", 99 },
        CurrencyFloor{ "leaftip_stone_2", 99 },
        CurrencyFloor{ "leafdim_stone", 99 },
        CurrencyFloor{ "leafdim_stone_1", 99 },
        CurrencyFloor{ "leafdim_stone_2", 99 },
        CurrencyFloor{ "leaforb_stone", 99 },
        CurrencyFloor{ "leaforb_stone_1", 99 },
        CurrencyFloor{ "leaforb_stone_2", 99 },
    };

    for (const auto& floor : kCurrencyFloors)
    {
        updateCurrencyFloor(charId, floor.column, floor.value);
    }

    static constexpr std::array kMoreCurrencyFloors = {
        CurrencyFloor{ "duskslit_stone", 99 },
        CurrencyFloor{ "duskslit_stone_1", 99 },
        CurrencyFloor{ "duskslit_stone_2", 99 },
        CurrencyFloor{ "dusktip_stone", 99 },
        CurrencyFloor{ "dusktip_stone_1", 99 },
        CurrencyFloor{ "dusktip_stone_2", 99 },
        CurrencyFloor{ "duskdim_stone", 99 },
        CurrencyFloor{ "duskdim_stone_1", 99 },
        CurrencyFloor{ "duskdim_stone_2", 99 },
        CurrencyFloor{ "duskorb_stone", 99 },
        CurrencyFloor{ "duskorb_stone_1", 99 },
        CurrencyFloor{ "duskorb_stone_2", 99 },
        CurrencyFloor{ "pellucid_stone", 99 },
        CurrencyFloor{ "fern_stone", 99 },
        CurrencyFloor{ "taupe_stone", 99 },
        CurrencyFloor{ "escha_beads", 50000 },
        CurrencyFloor{ "escha_silt", 999999 },
        CurrencyFloor{ "potpourri", 999999 },
        CurrencyFloor{ "current_hallmarks", 50000 },
        CurrencyFloor{ "total_hallmarks", 500000 },
        CurrencyFloor{ "gallantry", 50000 },
        CurrencyFloor{ "crafter_points", 999999 },
        CurrencyFloor{ "silver_aman_voucher", 999 },
        CurrencyFloor{ "plaudits", 9999 },
        CurrencyFloor{ "bloodshed_plans", 999 },
        CurrencyFloor{ "umbrage_plans", 999 },
        CurrencyFloor{ "ritualistic_plans", 999 },
        CurrencyFloor{ "tutelary_plans", 999 },
        CurrencyFloor{ "primacy_plans", 999 },
        CurrencyFloor{ "domain_points", 800 },
        CurrencyFloor{ "domain_points_daily", 80 },
        CurrencyFloor{ "mog_segments", 999999 },
        CurrencyFloor{ "gallimaufry", 999999 },
        CurrencyFloor{ "is_accolades", 9999 },
        CurrencyFloor{ "temenos_units", 999999 },
        CurrencyFloor{ "apollyon_units", 999999 },
        CurrencyFloor{ "alter_ego_points", kMaxAlterEgoPointWallet },
    };

    for (const auto& floor : kMoreCurrencyFloors)
    {
        updateCurrencyFloor(charId, floor.column, floor.value);
    }
}

void repairUnitySylvie(uint32 charId)
{
    db::preparedStmt(
        "UPDATE char_profile SET unity_leader = ? WHERE charid = ? LIMIT 1",
        kSylvieUnityLeader,
        charId);

    for (uint8 leader = 1; leader <= 11; ++leader)
    {
        const bool sylvie = leader == kSylvieUnityLeader;
        db::preparedStmt(
            "INSERT INTO unity_system (leader, members_current, points_current, members_prev, points_prev) "
            "VALUES (?, 1, ?, 1, ?) "
            "ON DUPLICATE KEY UPDATE members_current = 1, points_current = VALUES(points_current), "
            "members_prev = 1, points_prev = VALUES(points_prev)",
            leader,
            sylvie ? 1000000 : 1,
            sylvie ? 1000000 : 1);
    }

    roeutils::UpdateUnityRankings();
}

void repairSpellbook(uint32 charId)
{
    db::preparedStmt(
        "DELETE cs FROM char_spells cs "
        "LEFT JOIN spell_list sl ON sl.spellid = cs.spellid "
        "WHERE cs.charid = ? AND sl.spellid IS NULL",
        charId);

    db::preparedStmt(
        "INSERT IGNORE INTO char_spells (charid, spellid) "
        "SELECT ?, 1002 FROM spell_list WHERE spellid = 1002",
        charId);
}

void repairMerits(uint32 charId)
{
    db::preparedStmt(
        "INSERT INTO char_merit (charid, meritid, upgrades) "
        "SELECT ?, meritid, upgrade FROM merits WHERE upgrade > 0 "
        "ON DUPLICATE KEY UPDATE upgrades = VALUES(upgrades)",
        charId);

    db::preparedStmt(
        "UPDATE char_exp SET merits = 75, limits = 9999 WHERE charid = ? LIMIT 1",
        charId);
}

void repairAlterEgoPoints(uint32 charId)
{
    db::preparedStmt(
        "INSERT INTO char_points (charid, alter_ego_points) "
        "VALUES (?, ?) "
        "ON DUPLICATE KEY UPDATE alter_ego_points = VALUES(alter_ego_points)",
        charId,
        kMaxAlterEgoPointWallet);

    static constexpr std::array<const char*, 11> varNames = {
        "AlterEgoPoints_CombatSkills",
        "AlterEgoPoints_MagicSkills",
        "AlterEgoPoints_HP",
        "AlterEgoPoints_MP",
        "AlterEgoPoints_STR",
        "AlterEgoPoints_DEX",
        "AlterEgoPoints_VIT",
        "AlterEgoPoints_AGI",
        "AlterEgoPoints_INT",
        "AlterEgoPoints_MND",
        "AlterEgoPoints_CHR",
    };

    for (const auto* varName : varNames)
    {
        db::preparedStmt(
            "INSERT INTO char_vars (charid, varname, value, expiry) "
            "VALUES (?, ?, ?, 0) "
            "ON DUPLICATE KEY UPDATE value = VALUES(value), expiry = 0",
            charId,
            varName,
            kMaxAlterEgoCategory);
    }
}

void repairTrustEngagement(uint32 charId)
{
    // TrustEngageType=1 is "Attack: Master engage".
    charutils::SetCharVar(charId, "TrustEngageType", 1, 0);
}

void repairRdmSchAugments(uint32 charId)
{
    struct ItemAugment
    {
        uint16      itemId;
        const char* exdataHex;
    };

    // Bundled augment exdata from scripts/data/augments.lua:
    // Crocea Mors Path C R25, Duelist's Torque +2 R25, Nyame Path B R30.
    static constexpr std::array<ItemAugment, 7> kBundledAugments = {
        ItemAugment{ 21627, "03830000B23164013F000000000000000000000000000000" }, // Crocea Mors Path C
        ItemAugment{ 25443, "03830000B0316401CB000000000000000000000000000000" }, // Duelist's Torque +2
        ItemAugment{ 23761, "03830000E167FB05BB010000000000000000000000000000" }, // Nyame Helm Path B
        ItemAugment{ 23768, "03830000E167FB05BC010000000000000000000000000000" }, // Nyame Mail Path B
        ItemAugment{ 23775, "03830000E167FB05BD010000000000000000000000000000" }, // Nyame Gauntlets Path B
        ItemAugment{ 23782, "03830000E167FB05BE010000000000000000000000000000" }, // Nyame Flanchard Path B
        ItemAugment{ 23789, "03830000E167FB05BF010000000000000000000000000000" }, // Nyame Sollerets Path B
    };

    for (const auto& augment : kBundledAugments)
    {
        db::preparedStmt(
            "UPDATE char_inventory SET extra = UNHEX(?) WHERE charid = ? AND itemId = ?",
            augment.exdataHex,
            charId,
            augment.itemId);
    }
}

bool repairChocobo(uint32 charId)
{
    static constexpr uint32 kAdultAgeSeconds = 64u * 86400u;

    const auto rset = db::preparedStmt(
        "INSERT INTO char_chocobos "
        "(charid, first_name, last_name, sex, created, last_update_age, stage, location, color, "
        "allele1, allele2, allele3, strength, endurance, discernment, receptivity, affection, "
        "energy, satisfaction, conditions, ability1, ability2, personality, weather_preference, "
        "hunger, care_plan, held_item) "
        "VALUES (?, 'Mochi', 'Galloper', 1, FROM_UNIXTIME(UNIX_TIMESTAMP() - ?), 64, 6, 1, 1, "
        "1, 1, 1, 255, 255, 159, 159, 255, 100, 255, 0, 1, 2, 2, 0, 7, 0, 0) "
        "ON DUPLICATE KEY UPDATE "
        "first_name = VALUES(first_name), last_name = VALUES(last_name), sex = VALUES(sex), "
        "created = VALUES(created), last_update_age = VALUES(last_update_age), "
        "stage = VALUES(stage), location = VALUES(location), color = VALUES(color), "
        "allele1 = VALUES(allele1), allele2 = VALUES(allele2), allele3 = VALUES(allele3), "
        "strength = VALUES(strength), endurance = VALUES(endurance), "
        "discernment = VALUES(discernment), receptivity = VALUES(receptivity), "
        "affection = VALUES(affection), energy = VALUES(energy), "
        "satisfaction = VALUES(satisfaction), conditions = VALUES(conditions), "
        "ability1 = VALUES(ability1), ability2 = VALUES(ability2), "
        "personality = VALUES(personality), weather_preference = VALUES(weather_preference), "
        "hunger = VALUES(hunger), care_plan = VALUES(care_plan), held_item = VALUES(held_item)",
        charId,
        kAdultAgeSeconds);

    return static_cast<bool>(rset);
}

void repairProfileAndStorage(uint32 charId)
{
    db::preparedStmt(
        "UPDATE char_profile SET "
        "rank_points = 0, "
        "rank_sandoria = 10, rank_bastok = 10, rank_windurst = 10, "
        "fame_sandoria = ?, fame_bastok = ?, fame_windurst = ?, fame_norg = ?, fame_jeuno = ?, "
        "fame_aby_konschtat = ?, fame_aby_tahrongi = ?, fame_aby_latheine = ?, fame_aby_misareaux = ?, "
        "fame_aby_vunkerl = ?, fame_aby_attohwa = ?, fame_aby_altepa = ?, fame_aby_grauberg = ?, "
        "fame_aby_uleguerand = ?, fame_adoulin = ? "
        "WHERE charid = ? LIMIT 1",
        kMaxFameValue,
        kMaxFameValue,
        kMaxFameValue,
        kMaxFameValue,
        kMaxFameValue,
        kMaxAbysseaFameValue,
        kMaxAbysseaFameValue,
        kMaxAbysseaFameValue,
        kMaxAbysseaFameValue,
        kMaxAbysseaFameValue,
        kMaxAbysseaFameValue,
        kMaxAbysseaFameValue,
        kMaxAbysseaFameValue,
        kMaxAbysseaFameValue,
        kMaxFameValue,
        charId);

    db::preparedStmt(
        "UPDATE char_storage SET inventory = ?, safe = GREATEST(safe, 80), "
        "locker = GREATEST(locker, 80), satchel = GREATEST(satchel, 80), "
        "sack = GREATEST(sack, 80), `case` = GREATEST(`case`, 80), "
        "wardrobe = GREATEST(wardrobe, 80), wardrobe2 = GREATEST(wardrobe2, 80), "
        "wardrobe3 = GREATEST(wardrobe3, 80), wardrobe4 = GREATEST(wardrobe4, 80), "
        "wardrobe5 = GREATEST(wardrobe5, 80), wardrobe6 = GREATEST(wardrobe6, 80), "
        "wardrobe7 = GREATEST(wardrobe7, 80), wardrobe8 = GREATEST(wardrobe8, 80) "
        "WHERE charid = ? LIMIT 1",
        kMaxInventorySize,
        charId);

    db::preparedStmt(
        "UPDATE chars SET nation = 0, gmlevel = 5 WHERE charid = ? LIMIT 1",
        charId);

    db::preparedStmt(
        "INSERT IGNORE INTO char_pet (charid) VALUES (?)",
        charId);
}
} // namespace

class TwillsAdminModule : public CPPModule
{
public:
    void OnInit() override
    {
        auto xi          = lua["xi"].get_or_create<sol::table>();
        auto twillsAdmin = xi["twills_admin"].get_or_create<sol::table>();
        auto native      = twillsAdmin["native"].get_or_create<sol::table>();

        native["repairDbState"] = [](uint32 charId)
        {
            if (charId == 0)
            {
                return false;
            }

            db::preparedStmt(
                "UPDATE char_jobs SET "
                "unlocked = 8388607, genkai = 99, "
                "war = 99, mnk = 99, whm = 99, blm = 99, rdm = 99, thf = 99, "
                "pld = 99, drk = 99, bst = 99, brd = 99, rng = 99, sam = 99, "
                "nin = 99, drg = 99, smn = 99, blu = 99, cor = 99, pup = 99, "
                "dnc = 99, sch = 99, geo = 99, run = 99 "
                "WHERE charid = ? LIMIT 1",
                charId);

            repairJobPoints(charId);
            repairMasterLevels(charId);
            repairMerits(charId);
            repairAlterEgoPoints(charId);
            repairCrafts(charId);
            repairTravelUnlocks(charId);
            repairVeteranCurrencies(charId);
            repairUnitySylvie(charId);
            repairSpellbook(charId);
            repairTrustEngagement(charId);
            repairRdmSchAugments(charId);
            repairProfileAndStorage(charId);

            return true;
        };

        native["auditDbState"]  = auditDbState;
        native["grantGear"]     = grantGear;
        native["repairChocobo"] = repairChocobo;
    }
};

REGISTER_CPP_MODULE(TwillsAdminModule);
