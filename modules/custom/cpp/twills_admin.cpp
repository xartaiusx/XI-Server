/************************************************************************
 * Twills Admin DB Repair
 *
 * Lua owns the character repair flow. This module exposes the narrow DB
 * updates needed for state that is not fully mutable through Lua APIs.
 ************************************************************************/

#include "common/database.h"
#include "common/logging.h"
#include "entities/char_entity.h"
#include "lua/lua_base_entity.h"
#include "map/utils/moduleutils.h"
#include "map/utils/trustutils.h"
#include "merit.h"
#include "roe.h"
#include "utils/charutils.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <chrono>
#include <limits>
#include <string>
#include <tuple>
#include <unordered_map>
#include <unordered_set>

namespace
{

constexpr uint16      kMaxCapacityPoints         = 29999;
constexpr uint16      kMaxJobPoints              = 500;
constexpr uint16      kMaxJobPointsSpent         = 2100;
constexpr uint8       kMaxJobPointCategory       = 20;
constexpr uint8       kMaxAlterEgoCategory       = 50;
constexpr uint16      kMaxAlterEgoPointWallet    = 1350;
constexpr uint16      kMaxFameValue              = 613;
constexpr uint16      kMaxAbysseaFameValue       = 425;
constexpr uint8       kMaxInventorySize          = 80;
constexpr uint32      kGuildPointWallet          = 200000;
constexpr uint16      kMaxChocobucks             = 1000;
constexpr uint8       kMaxFewell                 = 99;
constexpr uint8       kMaxMasterLevel            = 50;
constexpr uint8       kCurrentBootVersion        = 9;
constexpr uint8       kSylvieUnityLeader         = 11;
constexpr uint32      kVeteranPlaytimeSeconds    = 36000000;
constexpr uint32      kBallistaPointCap          = 2000;
constexpr uint16      kMaxHeldMerits             = 75;
constexpr uint16      kMaxLimitPoints            = 9999;
constexpr const char* kVeteranTimestamp          = "2011-07-11 00:00:00";
constexpr auto        kMartialTechniquePrimer    = static_cast<KeyItem>(3224);
constexpr auto        kMartialTechniqueTreatise  = static_cast<KeyItem>(3225);
constexpr auto        kTrustAllianceAccessVar    = "MochiriiTrustAllianceAccess";
constexpr auto        kTrustSessionStateVar      = "MochiriiTrustSessionState";
constexpr auto        kTrustEvidenceModeVar      = "MochiriiTrustEvidenceMode";
constexpr auto        kTrustSessionGenerationVar = "MochiriiTrustSessionGeneration";
constexpr auto        kTrustSessionStartedVar    = "MochiriiTrustSessionStarted";
constexpr auto        kTrustSessionZoneVar       = "MochiriiTrustSessionZone";
constexpr auto        kTrustEvidenceSequenceVar  = "MochiriiTrustEvidenceSeq";
constexpr auto        kTrustEvidenceSchemaVar    = "MochiriiTrustEvidenceSchema";
constexpr auto        kTrustPendingTimersVar     = "MochiriiTrustAlliancePendingTimers";
constexpr auto        kTrustLogTruncatedVar      = "MochiriiTrustLogTruncated";

constexpr uint32 kOutpostMask       = ((1u << 19) - 1u) << 5; // Region bits 5-23.
constexpr uint32 kRunicPortalMask   = 0x0000007Eu;            // Runic portal bits 1-6.
constexpr uint32 kMawMask           = 0x000001FFu;            // Cavernous Maw bits 0-8.
constexpr uint32 kCampaignMask      = 0x001FFFFEu;            // Campaign teleport bits 1-20.
constexpr uint32 kExpectedHomepoint = 122;
constexpr uint32 kExpectedSurvival  = 96;
constexpr uint32 kExpectedAbyssea   = 72;
constexpr uint32 kExpectedWaypoint  = 55;
constexpr uint32 kExpectedEscha     = 32;

constexpr const char* kHomepointBlob =
    "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFF03000000000000000000000000000000000000000000"
    "00000000000000000000000000000000000000";
constexpr const char* kSurvivalBlob =
    "FFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000000000000000000000"
    "00000000000000000000000000000000000000";
constexpr const char* kAbysseaConfluxBlob = "FFFFFFFFFFFFFFFFFF";
constexpr const char* kWaypointBlob       = "FFFFFFFFFFFF7F0001";
constexpr const char* kEschaPortalBlob    = "FFFFFFFF";

struct MeritAllocation
{
    uint16 meritId;
    uint8  upgrades;
};

// Retail-legal veteran profile. General categories use their current category
// limits, each job group uses 10 points, and five weapon skills use the
// 25-point capacity granted by Martial Technique Primer/Treatise.
static constexpr auto kVeteranMeritProfile = std::to_array<MeritAllocation>({
    { 64, 15 },
    { 66, 15 },
    { 68, 45 },
    { 128, 15 },
    { 130, 15 },
    { 132, 15 },
    { 134, 15 },
    { 136, 15 },
    { 138, 15 },
    { 140, 15 },
    { 192, 8 },
    { 194, 8 },
    { 196, 8 },
    { 198, 8 },
    { 200, 8 },
    { 202, 8 },
    { 204, 8 },
    { 206, 8 },
    { 208, 8 },
    { 210, 8 },
    { 212, 8 },
    { 214, 8 },
    { 216, 8 },
    { 218, 8 },
    { 220, 8 },
    { 222, 8 },
    { 224, 8 },
    { 226, 8 },
    { 228, 8 },
    { 256, 8 },
    { 258, 8 },
    { 260, 8 },
    { 262, 8 },
    { 264, 8 },
    { 266, 8 },
    { 268, 8 },
    { 270, 8 },
    { 272, 8 },
    { 274, 8 },
    { 276, 8 },
    { 278, 8 },
    { 280, 8 },
    { 282, 8 },
    { 324, 5 },
    { 328, 5 },

    // Job Group 1, two five-point categories per job.
    { 384, 5 },
    { 392, 5 },
    { 454, 5 },
    { 456, 5 },
    { 514, 5 },
    { 516, 5 },
    { 580, 5 },
    { 586, 5 },
    { 644, 5 },
    { 646, 5 },
    { 708, 5 },
    { 712, 5 },
    { 772, 5 },
    { 776, 5 },
    { 836, 5 },
    { 838, 5 },
    { 898, 5 },
    { 902, 5 },
    { 966, 5 },
    { 968, 5 },
    { 1028, 5 },
    { 1032, 5 },
    { 1092, 5 },
    { 1094, 5 },
    { 1152, 5 },
    { 1162, 5 },
    { 1218, 5 },
    { 1220, 5 },
    { 1280, 5 },
    { 1284, 5 },
    { 1350, 5 },
    { 1352, 5 },
    { 1408, 5 },
    { 1410, 5 },
    { 1472, 5 },
    { 1478, 5 },
    { 1538, 5 },
    { 1540, 5 },
    { 1600, 5 },
    { 1606, 5 },
    { 1728, 5 },
    { 1734, 5 },
    { 1794, 5 },
    { 1796, 5 },

    // Job Group 2, two five-point categories per job.
    { 2050, 5 },
    { 2052, 5 },
    { 2112, 5 },
    { 2118, 5 },
    { 2178, 5 },
    { 2184, 5 },
    { 2256, 5 },
    { 2262, 5 },
    { 2318, 5 },
    { 2322, 5 },
    { 2368, 5 },
    { 2370, 5 },
    { 2434, 5 },
    { 2438, 5 },
    { 2496, 5 },
    { 2502, 5 },
    { 2562, 5 },
    { 2564, 5 },
    { 2624, 5 },
    { 2626, 5 },
    { 2692, 5 },
    { 2694, 5 },
    { 2756, 5 },
    { 2758, 5 },
    { 2836, 5 },
    { 2838, 5 },
    { 2882, 5 },
    { 2884, 5 },
    { 2946, 5 },
    { 2952, 5 },
    { 3010, 5 },
    { 3014, 5 },
    { 3072, 5 },
    { 3076, 5 },
    { 3140, 5 },
    { 3142, 5 },
    { 3204, 5 },
    { 3206, 5 },
    { 3272, 5 },
    { 3274, 5 },
    { 3392, 5 },
    { 3398, 5 },
    { 3456, 5 },
    { 3458, 5 },

    { 1666, 5 },
    { 1668, 5 },
    { 1670, 5 },
    { 1686, 5 },
    { 1690, 5 },
});

auto expectedMeritCategoryTotal(uint8 categoryId) -> uint16
{
    switch (categoryId)
    {
        case 0:
            return 75;
        case 1:
            return 105;
        case 2:
            return 152;
        case 3:
            return 112;
        case 4:
            return 10;
        case 25:
            return 25;
        default:
            if ((categoryId >= 5 && categoryId <= 24) ||
                (categoryId >= 26 && categoryId <= 27) ||
                (categoryId >= 31 && categoryId <= 50) ||
                (categoryId >= 52 && categoryId <= 53))
            {
                return 10;
            }

            return 0;
    }
}

auto validateMeritProfile() -> bool
{
    struct MeritDefinition
    {
        uint8 maxUpgrades;
        uint8 categoryId;
    };

    std::unordered_map<uint16, MeritDefinition> definitions;
    const auto                                  rset = db::preparedStmt("SELECT meritid, upgrade, catagoryid FROM merits");
    if (!rset)
    {
        return false;
    }

    while (rset->next())
    {
        definitions.emplace(
            rset->get<uint16>("meritid"),
            MeritDefinition{ rset->get<uint8>("upgrade"), rset->get<uint8>("catagoryid") });
    }

    std::unordered_set<uint16> seen;
    std::array<uint16, 54>     categoryTotals{};
    for (const auto& allocation : kVeteranMeritProfile)
    {
        const auto definition = definitions.find(allocation.meritId);
        if (definition == definitions.end() ||
            allocation.upgrades > definition->second.maxUpgrades ||
            definition->second.categoryId >= categoryTotals.size() ||
            !seen.emplace(allocation.meritId).second)
        {
            return false;
        }

        categoryTotals.at(definition->second.categoryId) += allocation.upgrades;
    }

    for (uint8 categoryId = 0; categoryId < categoryTotals.size(); ++categoryId)
    {
        if (categoryTotals.at(categoryId) != expectedMeritCategoryTotal(categoryId))
        {
            return false;
        }
    }

    return true;
}

auto getCharacter(CLuaBaseEntity* luaEntity) -> CCharEntity*
{
    if (luaEntity == nullptr)
    {
        return nullptr;
    }

    return dynamic_cast<CCharEntity*>(luaEntity->GetBaseEntity());
}

void addAuditLine(sol::table& rows, uint32& index, bool ok, const std::string& label, const std::string& details)
{
    rows[index++] = std::string(ok ? "[OK] " : "[FIX] ") + label + ": " + details;
}

void addAuditInfo(sol::table& rows, uint32& index, const std::string& label, const std::string& details)
{
    rows[index++] = "[INFO] " + label + ": " + details;
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

auto isLongTimeVisitedZone(const uint16 zoneId, const uint16 zonePort, const std::string& name) -> bool
{
    if (zoneId == 0 || zonePort == 0 || name.empty() || name == "unknown" ||
        name == "none" || name == "GM_Home")
    {
        return false;
    }

    return !std::all_of(name.begin(), name.end(), [](const unsigned char c)
                        {
                            return std::isdigit(c) != 0;
                        });
}

auto countExpectedLongTimeVisitedZones() -> uint32
{
    uint32 count = 0;

    if (const auto rset =
            db::preparedStmt("SELECT zoneid, zoneport, name FROM zone_settings "
                             "WHERE zoneid BETWEEN 1 AND 303 ORDER BY zoneid");
        rset && rset->rowsCount())
    {
        while (rset->next())
        {
            if (isLongTimeVisitedZone(rset->get<uint16>("zoneid"),
                                      rset->get<uint16>("zoneport"),
                                      rset->get<std::string>("name")))
            {
                ++count;
            }
        }
    }

    return count;
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
            "j.unlocked, j.genkai, j.rdm, j.sch, ml.master_level, "
            "ml.exemplar_points "
            "FROM chars c "
            "JOIN char_stats s ON s.charid = c.charid "
            "JOIN char_jobs j ON j.charid = c.charid "
            "LEFT JOIN char_master_levels ml ON ml.charid = c.charid AND "
            "ml.jobid = 5 "
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

        const bool ok = gmLevel == 5 && nation == 0 && mainJob == 5 &&
                        subJob == 20 && mainLevel == 99 && subLevel == 59 &&
                        unlocked == 8388607 && genkai == 99 && rdmLevel == 99 &&
                        schLevel == 99 && masterLevel == kMaxMasterLevel;

        addAuditLine(
            rows, index, ok, "Core RDM/SCH", "gm=" + std::to_string(gmLevel) + ", nation=" + std::to_string(nation) + ", active=" + std::to_string(mainJob) + "/" + std::to_string(subJob) + " " + std::to_string(mainLevel) + "/" + std::to_string(subLevel) + ", rdm=" + std::to_string(rdmLevel) + ", sch=" + std::to_string(schLevel) + ", ml=" + std::to_string(masterLevel));
    }
    else
    {
        addAuditLine(rows, index, false, "Core RDM/SCH", "character rows missing");
    }

    if (const auto rset = db::preparedStmt(
            "SELECT COUNT(*) AS master_rows FROM char_master_levels WHERE charid "
            "= ? AND master_level = ?",
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
            "AND jptype0 = ? AND jptype1 = ? AND jptype2 = ? AND jptype3 = ? AND "
            "jptype4 = ? "
            "AND jptype5 = ? AND jptype6 = ? AND jptype7 = ? AND jptype8 = ? AND "
            "jptype9 = ?",
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
        addAuditLine(
            rows, index, goodRows == 22, "Job Points", std::to_string(goodRows) + "/22 jobs at 2100 spent JP, 500 held JP, 20/20 categories");
    }

    if (const auto rset = db::preparedStmt(
            "SELECT "
            "(SELECT COUNT(*) FROM spell_list WHERE spellid IN (882, 883, 884, "
            "894, 895)) AS server_defs, "
            "(SELECT COUNT(*) FROM char_spells WHERE charid = ? AND spellid IN "
            "(882, 883, 884, 894, 895)) AS learned",
            charId);
        rset && rset->rowsCount() && rset->next())
    {
        const auto serverDefs = rset->get<uint8>("server_defs");
        const auto learned    = rset->get<uint8>("learned");
        addAuditLine(rows, index, serverDefs == 5 && learned == 5, "RDM JP Spells", std::to_string(learned) + "/5 learned, " + std::to_string(serverDefs) + "/5 server definitions");
    }

    if (const auto rset = db::preparedStmt(
            "SELECT "
            "(SELECT COUNT(*) FROM char_spells cs LEFT JOIN spell_list sl ON "
            "sl.spellid = cs.spellid WHERE cs.charid = ? AND sl.spellid IS NULL) "
            "AS undefined_spells, "
            "(SELECT COUNT(*) FROM spell_list WHERE spellid = 1002) AS "
            "cornelia_def, "
            "(SELECT COUNT(*) FROM char_spells WHERE charid = ? AND spellid = "
            "1002) AS cornelia_learned",
            charId,
            charId);
        rset && rset->rowsCount() && rset->next())
    {
        const auto undefinedSpells = rset->get<uint16>("undefined_spells");
        const auto corneliaDef     = rset->get<uint8>("cornelia_def");
        const auto corneliaLearned = rset->get<uint8>("cornelia_learned");
        const bool ok =
            undefinedSpells == 0 && (corneliaDef == 0 || corneliaLearned == 1);
        addAuditLine(rows, index, ok, "Spellbook Consistency", std::to_string(undefinedSpells) + " undefined learned spells, Cornelia " + (corneliaDef == 0 ? "not locally defined" : (corneliaLearned == 1 ? "learned" : "missing")));
    }

    if (const auto rset = db::preparedStmt(
            "SELECT "
            "(SELECT alter_ego_points FROM char_points WHERE charid = ?) AS "
            "wallet, "
            "(SELECT COUNT(*) FROM char_vars WHERE charid = ? AND value = ? AND "
            "varname IN ("
            "'AlterEgoPoints_HP', 'AlterEgoPoints_MP', 'AlterEgoPoints_STR', "
            "'AlterEgoPoints_DEX', "
            "'AlterEgoPoints_VIT', 'AlterEgoPoints_AGI', 'AlterEgoPoints_INT', "
            "'AlterEgoPoints_MND', "
            "'AlterEgoPoints_CHR', 'AlterEgoPoints_CombatSkills', "
            "'AlterEgoPoints_MagicSkills')) AS categories",
            charId,
            charId,
            kMaxAlterEgoCategory);
        rset && rset->rowsCount() && rset->next())
    {
        const auto wallet     = rset->get<uint16>("wallet");
        const auto categories = rset->get<uint8>("categories");
        addAuditLine(
            rows, index, wallet == kMaxAlterEgoPointWallet && categories == 11, "Alter Ego Points", "wallet=" + std::to_string(wallet) + ", categories=" + std::to_string(categories) + "/11 at 50");
    }

    if (const auto rset =
            db::preparedStmt("SELECT inventory, safe, locker, satchel, sack, "
                             "`case`, wardrobe, wardrobe2, wardrobe3, wardrobe4, "
                             "wardrobe5, wardrobe6, wardrobe7, wardrobe8 FROM "
                             "char_storage WHERE charid = ? LIMIT 1",
                             charId);
        rset && rset->rowsCount() && rset->next())
    {
        const bool ok =
            rset->get<uint8>("inventory") == 80 && rset->get<uint8>("safe") == 80 &&
            rset->get<uint8>("locker") == 80 && rset->get<uint8>("satchel") == 80 &&
            rset->get<uint8>("sack") == 80 && rset->get<uint8>("case") == 80 &&
            rset->get<uint8>("wardrobe") == 80 &&
            rset->get<uint8>("wardrobe2") == 80 &&
            rset->get<uint8>("wardrobe3") == 80 &&
            rset->get<uint8>("wardrobe4") == 80 &&
            rset->get<uint8>("wardrobe5") == 80 &&
            rset->get<uint8>("wardrobe6") == 80 &&
            rset->get<uint8>("wardrobe7") == 80 &&
            rset->get<uint8>("wardrobe8") == 80;
        addAuditLine(rows, index, ok, "Storage", ok ? "all tracked containers at 80" : "one or more tracked containers below 80");
    }

    if (const auto rset =
            db::preparedStmt("SELECT COUNT(*) AS good_crafts FROM char_skills "
                             "WHERE charid = ? AND ("
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
            "SELECT rank_sandoria, rank_bastok, rank_windurst, fame_sandoria, "
            "fame_bastok, fame_windurst, fame_norg, fame_jeuno, fame_adoulin "
            "FROM char_profile WHERE charid = ? LIMIT 1",
            charId);
        rset && rset->rowsCount() && rset->next())
    {
        const bool ok = rset->get<uint8>("rank_sandoria") == 10 &&
                        rset->get<uint8>("rank_bastok") == 10 &&
                        rset->get<uint8>("rank_windurst") == 10 &&
                        rset->get<uint16>("fame_sandoria") == kMaxFameValue &&
                        rset->get<uint16>("fame_bastok") == kMaxFameValue &&
                        rset->get<uint16>("fame_windurst") == kMaxFameValue &&
                        rset->get<uint16>("fame_norg") == kMaxFameValue &&
                        rset->get<uint16>("fame_jeuno") == kMaxFameValue &&
                        rset->get<uint16>("fame_adoulin") == kMaxFameValue;
        addAuditLine(rows, index, ok, "Ranks/Fame", ok ? "all nations rank 10 and major fame values capped" : "rank/fame mismatch");
    }

    if (const auto rset = db::preparedStmt(
            "SELECT color, strength, endurance, ability1, ability2, conditions "
            "FROM char_chocobos WHERE charid = ? LIMIT 1",
            charId);
        rset && rset->rowsCount() && rset->next())
    {
        const bool ok = rset->get<uint8>("color") == 1 &&
                        rset->get<uint8>("strength") == 255 &&
                        rset->get<uint8>("endurance") == 255 &&
                        rset->get<uint8>("ability1") == 1 &&
                        rset->get<uint8>("ability2") == 2 &&
                        rset->get<uint32>("conditions") == 0;
        addAuditLine(
            rows, index, ok, "Chocobo", ok ? "black Gallop/Canter, max strength/endurance, no bad conditions" : "raised chocobo state mismatch");
    }

    if (const auto rset =
            db::preparedStmt("SELECT outpost_sandy, outpost_bastok, "
                             "outpost_windy, runic_portal, maw, "
                             "campaign_sandy, campaign_bastok, campaign_windy, "
                             "homepoints, survivals, "
                             "abyssea_conflux, waypoints, eschan_portals "
                             "FROM char_unlocks WHERE charid = ? LIMIT 1",
                             charId);
        rset && rset->rowsCount() && rset->next())
    {
        const bool fixedMaskOk =
            (rset->get<uint32>("outpost_sandy") & kOutpostMask) == kOutpostMask &&
            (rset->get<uint32>("outpost_bastok") & kOutpostMask) == kOutpostMask &&
            (rset->get<uint32>("outpost_windy") & kOutpostMask) == kOutpostMask &&
            (rset->get<uint32>("runic_portal") & kRunicPortalMask) ==
                kRunicPortalMask &&
            (rset->get<uint32>("maw") & kMawMask) == kMawMask &&
            (rset->get<uint32>("campaign_sandy") & kCampaignMask) ==
                kCampaignMask &&
            (rset->get<uint32>("campaign_bastok") & kCampaignMask) ==
                kCampaignMask &&
            (rset->get<uint32>("campaign_windy") & kCampaignMask) == kCampaignMask;

        const auto homepoints = countBlobBits(rset, "homepoints", 16);
        const auto survivals  = countBlobBits(rset, "survivals", 16);
        const auto abyssea    = countBlobBits(rset, "abyssea_conflux", 9);
        const auto waypoints  = countBlobBits(rset, "waypoints", 8);
        const auto escha      = countBlobBits(rset, "eschan_portals", 4);
        const bool blobOk =
            homepoints >= kExpectedHomepoint && survivals >= kExpectedSurvival &&
            abyssea >= kExpectedAbyssea && waypoints >= kExpectedWaypoint &&
            escha >= kExpectedEscha;

        addAuditLine(
            rows, index, fixedMaskOk && blobOk, "Travel Unlocks", "HP " + std::to_string(homepoints) + "/" + std::to_string(kExpectedHomepoint) + ", SG " + std::to_string(survivals) + "/" + std::to_string(kExpectedSurvival) + ", Abyssea " + std::to_string(abyssea) + "/" + std::to_string(kExpectedAbyssea) + ", Waypoints " + std::to_string(waypoints) + "/" + std::to_string(kExpectedWaypoint) + ", Escha " + std::to_string(escha) + "/" + std::to_string(kExpectedEscha) + (fixedMaskOk ? ", fixed masks complete" : ", fixed mask category missing"));
    }

    if (const auto rset = db::preparedStmt(
            "SELECT p.unity_leader, us.members_prev, us.points_prev "
            "FROM char_points cp "
            "JOIN char_profile p ON p.charid = cp.charid "
            "LEFT JOIN unity_system us ON us.leader = p.unity_leader "
            "WHERE cp.charid = ? LIMIT 1",
            charId);
        rset && rset->rowsCount() && rset->next())
    {
        const bool ok = rset->get<uint8>("unity_leader") == kSylvieUnityLeader &&
                        rset->get<uint32>("members_prev") >= 1 &&
                        rset->get<double>("points_prev") >= 1000000.0;

        addAuditLine(
            rows, index, ok, "Unity", "Sylvie leader=" + std::to_string(rset->get<uint8>("unity_leader")) + ", previous members=" + std::to_string(rset->get<uint32>("members_prev")) + ", previous evaluation=" + std::to_string(rset->get<uint32>("points_prev")));
    }

    if (const auto rset = db::preparedStmt(
            "SELECT "
            "SUM(varname = 'TwillsBootVersion' AND value >= ?) AS boot_ok, "
            "SUM(varname = 'TwillsRdmSchGearVersion' AND value >= 3) AS gear_ok, "
            "SUM(varname = 'MochiriiTrustAllianceAccess' AND value = 1) AS trust_access_ok "
            "FROM char_vars WHERE charid = ? AND varname IN "
            "('TwillsBootVersion', 'TwillsRdmSchGearVersion', 'MochiriiTrustAllianceAccess')",
            kCurrentBootVersion,
            charId);
        rset && rset->rowsCount() && rset->next())
    {
        const bool ok = rset->get<uint8>("boot_ok") == 1 &&
                        rset->get<uint8>("gear_ok") == 1 &&
                        rset->get<uint8>("trust_access_ok") == 1;
        addAuditLine(rows, index, ok, "Repair Markers", ok ? "boot v9, gear v3, Trust alliance entitlement 1" : "repair marker mismatch");
    }

    if (const auto rset =
            db::preparedStmt("SELECT assault, campaign, eminence, titles, zones, "
                             "weaponskills FROM chars WHERE charid = ? LIMIT 1",
                             charId);
        rset && rset->rowsCount() && rset->next())
    {
        const auto assaultBits  = countBlobBits(rset, "assault", 130);
        const auto campaignBits = countBlobBits(rset, "campaign", 514);
        const auto roeBits      = countBlobBits(rset, "eminence", 700);
        const auto titleBits    = countBlobBits(rset, "titles", 143);
        const auto zoneBits     = countBlobBits(rset, "zones", 38);
        const auto wsBits       = countBlobBits(rset, "weaponskills", 8);

        const auto expectedZones = countExpectedLongTimeVisitedZones();
        addAuditLine(rows, index, assaultBits > 0, "Assault Progression", std::to_string(assaultBits) + " assault completion bits set through local mission APIs");
        addAuditLine(
            rows, index, true, "Campaign Progression", std::to_string(campaignBits) + " campaign bits set; local Campaign mission table is intentionally "
                                                                                      "empty, campaign teleport masks are handled by Travel Unlocks");
        addAuditLine(rows, index, roeBits > 0, "Records of Eminence", std::to_string(roeBits) + " supported record bits set");
        addAuditLine(rows, index, expectedZones == 0 || zoneBits >= expectedZones, "Zone Visitation", std::to_string(zoneBits) + "/" + std::to_string(expectedZones) + " locally visitable zone bits set");
        addAuditLine(rows, index, titleBits >= 100, "Titles", std::to_string(titleBits) + " local title-history bits set");
        addAuditLine(rows, index, wsBits >= 60, "Learned Weapon Skills", std::to_string(wsBits) + " active learned-weapon-skill bits set");
    }

    if (const auto rset = db::preparedStmt(
            "SELECT claimed_deeds FROM char_unlocks WHERE charid = ? LIMIT 1",
            charId);
        rset && rset->rowsCount() && rset->next())
    {
        const auto deedBits = countBlobBits(rset, "claimed_deeds", 20);
        addAuditLine(rows, index, deedBits > 0, "Claimed Deeds", std::to_string(deedBits) + " A.M.A.N. Validator reward bits claimed");
    }

    if (const auto rset = db::preparedStmt(
            "SELECT unlocked_weapons FROM chars WHERE charid = ? LIMIT 1",
            charId);
        rset && rset->rowsCount() && rset->next())
    {
        const auto legacyWeaponBits = countBlobBits(rset, "unlocked_weapons", 20);
        addAuditLine(rows, index, true, "Legacy Unlocked Weapons", std::to_string(legacyWeaponBits) + " legacy bits set; current server uses active learned "
                                                                                                      "weapon-skill bits");
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
        "(charid, guild_fishing, guild_woodworking, guild_smithing, "
        "guild_goldsmithing, "
        "guild_weaving, guild_leathercraft, guild_bonecraft, guild_alchemy, "
        "guild_cooking, "
        "fire_fewell, ice_fewell, wind_fewell, earth_fewell, lightning_fewell, "
        "water_fewell, "
        "light_fewell, dark_fewell, chocobuck_sandoria, chocobuck_bastok, "
        "chocobuck_windurst) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
        "ON DUPLICATE KEY UPDATE "
        "guild_fishing = VALUES(guild_fishing), guild_woodworking = "
        "VALUES(guild_woodworking), "
        "guild_smithing = VALUES(guild_smithing), guild_goldsmithing = "
        "VALUES(guild_goldsmithing), "
        "guild_weaving = VALUES(guild_weaving), guild_leathercraft = "
        "VALUES(guild_leathercraft), "
        "guild_bonecraft = VALUES(guild_bonecraft), guild_alchemy = "
        "VALUES(guild_alchemy), "
        "guild_cooking = VALUES(guild_cooking), fire_fewell = "
        "VALUES(fire_fewell), "
        "ice_fewell = VALUES(ice_fewell), wind_fewell = VALUES(wind_fewell), "
        "earth_fewell = VALUES(earth_fewell), lightning_fewell = "
        "VALUES(lightning_fewell), "
        "water_fewell = VALUES(water_fewell), light_fewell = "
        "VALUES(light_fewell), "
        "dark_fewell = VALUES(dark_fewell), chocobuck_sandoria = "
        "VALUES(chocobuck_sandoria), "
        "chocobuck_bastok = VALUES(chocobuck_bastok), chocobuck_windurst = "
        "VALUES(chocobuck_windurst)",
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
            "jptype0, jptype1, jptype2, jptype3, jptype4, jptype5, jptype6, "
            "jptype7, jptype8, jptype9) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
            "ON DUPLICATE KEY UPDATE "
            "capacity_points = VALUES(capacity_points), "
            "job_points = VALUES(job_points), "
            "job_points_spent = VALUES(job_points_spent), "
            "jptype0 = VALUES(jptype0), jptype1 = VALUES(jptype1), jptype2 = "
            "VALUES(jptype2), "
            "jptype3 = VALUES(jptype3), jptype4 = VALUES(jptype4), jptype5 = "
            "VALUES(jptype5), "
            "jptype6 = VALUES(jptype6), jptype7 = VALUES(jptype7), jptype8 = "
            "VALUES(jptype8), "
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
        "updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE "
        "current_timestamp(), "
        "PRIMARY KEY (charid, jobid), "
        "CONSTRAINT char_master_levels_jobid_chk CHECK (jobid BETWEEN 1 AND 22), "
        "CONSTRAINT char_master_levels_level_chk CHECK (master_level <= 50)"
        ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci");

    for (uint8 jobId = 1; jobId <= 22; ++jobId)
    {
        db::preparedStmt("INSERT INTO char_master_levels (charid, jobid, "
                         "master_level, exemplar_points) "
                         "VALUES (?, ?, ?, 0) "
                         "ON DUPLICATE KEY UPDATE master_level = "
                         "VALUES(master_level), exemplar_points = 0",
                         charId,
                         jobId,
                         kMaxMasterLevel);
    }

    db::preparedStmt("UPDATE char_stats SET mjob = ?, sjob = ?, mlvl = 99, slvl "
                     "= 59 WHERE charid = ? LIMIT 1",
                     static_cast<uint8>(xi::Job::RDM),
                     static_cast<uint8>(xi::Job::SCH),
                     charId);
}

void repairTravelUnlocks(uint32 charId)
{
    db::preparedStmt("INSERT INTO char_unlocks (charid) VALUES (?) ON DUPLICATE "
                     "KEY UPDATE charid = VALUES(charid)",
                     charId);

    db::preparedStmt("UPDATE char_unlocks SET "
                     "outpost_sandy = outpost_sandy | ?, outpost_bastok = "
                     "outpost_bastok | ?, outpost_windy = outpost_windy | ?, "
                     "runic_portal = runic_portal | ?, maw = maw | ?, "
                     "campaign_sandy = campaign_sandy | ?, campaign_bastok = "
                     "campaign_bastok | ?, campaign_windy = campaign_windy | ?, "
                     "homepoints = UNHEX(?), survivals = UNHEX(?), "
                     "abyssea_conflux = UNHEX(?), "
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

void repairUnitySylvie(uint32 charId)
{
    db::preparedStmt(
        "UPDATE char_profile SET unity_leader = ? WHERE charid = ? LIMIT 1",
        kSylvieUnityLeader,
        charId);

    for (uint8 leader = 1; leader <= 11; ++leader)
    {
        const bool sylvie = leader == kSylvieUnityLeader;
        db::preparedStmt("INSERT INTO unity_system (leader, members_current, "
                         "points_current, members_prev, points_prev) "
                         "VALUES (?, 1, ?, 1, ?) "
                         "ON DUPLICATE KEY UPDATE members_current = 1, "
                         "points_current = VALUES(points_current), "
                         "members_prev = 1, points_prev = VALUES(points_prev)",
                         leader,
                         sylvie ? 1000000 : 1,
                         sylvie ? 1000000 : 1);
    }

    roeutils::UpdateUnityRankings();
}

void repairSpellbook(uint32 charId)
{
    db::preparedStmt("DELETE cs FROM char_spells cs "
                     "LEFT JOIN spell_list sl ON sl.spellid = cs.spellid "
                     "WHERE cs.charid = ? AND sl.spellid IS NULL",
                     charId);

    db::preparedStmt("INSERT IGNORE INTO char_spells (charid, spellid) "
                     "SELECT ?, 1002 FROM spell_list WHERE spellid = 1002",
                     charId);
}

auto repairMerits(uint32 charId) -> bool
{
    if (!validateMeritProfile())
    {
        return false;
    }

    return db::transaction([&]()
                           {
                               db::preparedStmt("DELETE FROM char_merit WHERE charid = ?", charId);
                               for (const auto& allocation : kVeteranMeritProfile)
                               {
                                   db::preparedStmt(
                                       "INSERT INTO char_merit (charid, meritid, upgrades) VALUES (?, ?, ?)",
                                       charId,
                                       allocation.meritId,
                                       allocation.upgrades);
                               }

                               db::preparedStmt(
                                   "UPDATE char_exp SET merits = ?, limits = ? WHERE charid = ? LIMIT 1",
                                   kMaxHeldMerits,
                                   kMaxLimitPoints,
                                   charId);
                           });
}

auto repairMeritsForPlayer(CLuaBaseEntity* luaEntity) -> bool
{
    auto* PChar = getCharacter(luaEntity);
    if (PChar == nullptr || PChar->PMeritPoints == nullptr)
    {
        return false;
    }

    if (!charutils::hasKeyItem(PChar, kMartialTechniquePrimer) ||
        !charutils::hasKeyItem(PChar, kMartialTechniqueTreatise))
    {
        return false;
    }

    if (!repairMerits(PChar->id))
    {
        return false;
    }

    PChar->PMeritPoints->LoadMeritPoints(PChar->id);
    PChar->PMeritPoints->SetMeritPoints(kMaxHeldMerits);
    PChar->PMeritPoints->SetLimitPoints(kMaxLimitPoints);
    charutils::BuildingCharSkillsTable(PChar);
    charutils::CalculateStats(PChar);
    charutils::CheckValidEquipment(PChar);
    charutils::BuildingCharAbilityTable(PChar);
    charutils::BuildingCharTraitsTable(PChar);
    PChar->UpdateHealth();
    return true;
}

auto auditMeritState(sol::this_state state, uint32 charId) -> sol::table
{
    sol::state_view lua(state);
    auto            rows  = lua.create_table();
    uint32          index = 1;

    addAuditLine(
        rows,
        index,
        validateMeritProfile(),
        "Merit Profile Definition",
        "all selected merit IDs, per-row upgrades, and category totals match local retail limits");

    std::unordered_map<uint16, uint8> actual;
    if (const auto rset = db::preparedStmt(
            "SELECT meritid, upgrades FROM char_merit WHERE charid = ?", charId);
        rset)
    {
        while (rset->next())
        {
            actual.emplace(rset->get<uint16>("meritid"),
                           rset->get<uint8>("upgrades"));
        }
    }

    uint32 mismatches = 0;
    for (const auto& expected : kVeteranMeritProfile)
    {
        const auto actualIt = actual.find(expected.meritId);
        if (actualIt == actual.end() || actualIt->second != expected.upgrades)
        {
            ++mismatches;
        }
    }

    if (actual.size() > kVeteranMeritProfile.size())
    {
        mismatches +=
            static_cast<uint32>(actual.size() - kVeteranMeritProfile.size());
    }

    addAuditLine(
        rows, index, mismatches == 0 && actual.size() == kVeteranMeritProfile.size(), "Retail Merit Profile", std::to_string(actual.size()) + "/" + std::to_string(kVeteranMeritProfile.size()) + " selected merit rows; mismatches=" + std::to_string(mismatches));

    if (const auto rset = db::preparedStmt(
            "SELECT merits, limits FROM char_exp WHERE charid = ? LIMIT 1",
            charId);
        rset && rset->rowsCount() && rset->next())
    {
        const auto merits = rset->get<uint16>("merits");
        const auto limits = rset->get<uint16>("limits");
        addAuditLine(rows, index, merits == kMaxHeldMerits && limits == kMaxLimitPoints, "Held Merit/Limit Points", "merits=" + std::to_string(merits) + ", limits=" + std::to_string(limits));
    }

    return rows;
}

auto repairVeteranMetadata(uint32 charId) -> bool
{
    return db::transaction([&]()
                           {
                               db::preparedStmt("UPDATE accounts a JOIN chars c ON c.accid = a.id "
                                                "SET a.timecreate = ? WHERE c.charid = ?",
                                                kVeteranTimestamp,
                                                charId);
                               db::preparedStmt("UPDATE chars SET timecreated = ?, playtime = ? WHERE "
                                                "charid = ? LIMIT 1",
                                                kVeteranTimestamp,
                                                kVeteranPlaytimeSeconds,
                                                charId);
                               db::preparedStmt("UPDATE char_points SET daily_tally = CASE WHEN "
                                                "daily_tally = -1 THEN 50 ELSE daily_tally END "
                                                "WHERE charid = ? LIMIT 1",
                                                charId);
                           });
}

auto repairVeteranMetadataForPlayer(CLuaBaseEntity* luaEntity) -> bool
{
    auto* PChar = getCharacter(luaEntity);
    if (PChar == nullptr)
    {
        return false;
    }

    if (!repairVeteranMetadata(PChar->id))
    {
        return false;
    }

    PChar->SetPlayTime(std::chrono::seconds(kVeteranPlaytimeSeconds));
    return true;
}

auto auditMetadataState(sol::this_state state, uint32 charId) -> sol::table
{
    sol::state_view lua(state);
    auto            rows  = lua.create_table();
    uint32          index = 1;

    if (const auto rset = db::preparedStmt(
            "SELECT c.timecreated, c.playtime, a.timecreate, cp.daily_tally "
            "FROM chars c JOIN accounts a ON a.id = c.accid "
            "JOIN char_points cp ON cp.charid = c.charid "
            "WHERE c.charid = ? LIMIT 1",
            charId);
        rset && rset->rowsCount() && rset->next())
    {
        const auto characterCreated = rset->get<std::string>("timecreated");
        const auto accountCreated   = rset->get<std::string>("timecreate");
        const auto playtime         = rset->get<uint32>("playtime");
        const auto dailyTally       = rset->get<int32>("daily_tally");
        const bool ok               = characterCreated == kVeteranTimestamp &&
                                      accountCreated == kVeteranTimestamp &&
                                      playtime == kVeteranPlaytimeSeconds && dailyTally >= 0;

        addAuditLine(rows, index, ok, "Simulated Veteran Metadata", "account=" + accountCreated + ", character=" + characterCreated + ", playtime=" + std::to_string(playtime) + "s, daily tally=" + std::to_string(dailyTally) + "; intentional QA metadata exception");
    }

    return rows;
}

auto repairCurrencyPolicy(uint32 charId) -> bool
{
    const auto insertResult = db::preparedStmt(
        "INSERT INTO char_points (charid) VALUES (?) ON DUPLICATE KEY UPDATE charid = VALUES(charid)",
        charId);
    const auto updateResult = db::preparedStmt(
        "UPDATE char_points SET ballista_point = LEAST(ballista_point, ?), "
        "current_hallmarks = 0, total_hallmarks = 0, gallantry = 0, "
        "mog_segments = 0, gallimaufry = 0, "
        "temenos_units = 0, apollyon_units = 0 "
        "WHERE charid = ? LIMIT 1",
        kBallistaPointCap,
        charId);

    return insertResult != nullptr && updateResult != nullptr;
}

auto repairCurrencyPolicyForPlayer(CLuaBaseEntity* luaEntity) -> bool
{
    auto* PChar = getCharacter(luaEntity);
    return PChar != nullptr && repairCurrencyPolicy(PChar->id);
}

auto auditCurrencyState(sol::this_state state, uint32 charId) -> sol::table
{
    sol::state_view lua(state);
    auto            rows  = lua.create_table();
    uint32          index = 1;

    if (const auto rset =
            db::preparedStmt("SELECT ballista_point, current_hallmarks, "
                             "total_hallmarks, gallantry, "
                             "mog_segments, gallimaufry, temenos_units, "
                             "apollyon_units, escha_beads, escha_silt, "
                             "domain_points, domain_points_daily "
                             "FROM char_points WHERE charid = ? LIMIT 1",
                             charId);
        rset && rset->rowsCount() && rset->next())
    {
        const auto ballista       = rset->get<uint32>("ballista_point");
        const auto hallmarks      = rset->get<uint32>("current_hallmarks");
        const auto totalHallmarks = rset->get<uint32>("total_hallmarks");
        const auto gallantry      = rset->get<uint32>("gallantry");
        const auto segments       = rset->get<uint32>("mog_segments");
        const auto gallimaufry    = rset->get<uint32>("gallimaufry");
        const auto temenos        = rset->get<uint32>("temenos_units");
        const auto apollyon       = rset->get<uint32>("apollyon_units");
        const bool currentCycleOk =
            hallmarks == 0 && totalHallmarks == 0 && gallantry == 0;
        const bool unsupportedContentOk =
            segments == 0 && gallimaufry == 0 && temenos == 0 && apollyon == 0;

        addAuditLine(rows, index, ballista <= kBallistaPointCap && currentCycleOk, "Retail Currency Policy", "Ballista=" + std::to_string(ballista) + "/" + std::to_string(kBallistaPointCap) + ", current Hallmarks=" + std::to_string(hallmarks) + ", total Hallmarks=" + std::to_string(totalHallmarks) + ", Gallantry=" + std::to_string(gallantry));
        addAuditLine(rows, index, unsupportedContentOk, "Unsupported Content Currency Policy", "segments=" + std::to_string(segments) + ", gallimaufry=" + std::to_string(gallimaufry) + ", Temenos=" + std::to_string(temenos) + ", Apollyon=" + std::to_string(apollyon));

        addAuditInfo(
            rows, index, "Unverified Escha Currencies", "preserved pending acquisition-path acceptance: beads=" + std::to_string(rset->get<uint32>("escha_beads")) + ", silt=" + std::to_string(rset->get<uint32>("escha_silt")) + ", Domain=" + std::to_string(rset->get<uint32>("domain_points")) + ", Domain daily=" + std::to_string(rset->get<uint32>("domain_points_daily")));
    }

    return rows;
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

void repairTrustAllianceEntitlement(uint32 charId)
{
    charutils::SetCharVar(charId, kTrustAllianceAccessVar, 1, 0);
}

void resetTwillsTrustSession(CCharEntity* PChar)
{
    if (!PChar || PChar->getName() != "Twills")
    {
        return;
    }

    // Active sessions are closed by the paired pre/post zone-out Lua callbacks.
    // This fallback only normalizes an already-idle session.
    if (PChar->GetLocalVar(kTrustSessionStateVar) != 0 || PChar->GetLocalVar(kTrustEvidenceModeVar) != 0)
    {
        return;
    }

    const auto generation = PChar->GetLocalVar(kTrustSessionGenerationVar);
    PChar->SetLocalVar(
        kTrustSessionGenerationVar,
        generation == std::numeric_limits<uint32>::max() ? 1U : generation + 1U);
    PChar->SetLocalVar(kTrustSessionStateVar, 0);
    PChar->SetLocalVar(kTrustEvidenceModeVar, 0);
    PChar->SetLocalVar(kTrustSessionStartedVar, 0);
    PChar->SetLocalVar(kTrustSessionZoneVar, 0);
    PChar->SetLocalVar(kTrustEvidenceSequenceVar, 0);
    PChar->SetLocalVar(kTrustEvidenceSchemaVar, 0);
    PChar->SetLocalVar(kTrustPendingTimersVar, 0);
    PChar->SetLocalVar(kTrustLogTruncatedVar, 0);
    charutils::SetCharVar(PChar, "TrustEngageType", 0, 0);
}

void forceDeactivateTwillsTrustSession(CCharEntity* PChar)
{
    if (!PChar || PChar->getName() != "Twills")
    {
        return;
    }

    const auto state = trustutils::GetTwillsFullAllianceState(PChar);
    if (state == trustutils::TwillsFullAllianceState::Spawning || state == trustutils::TwillsFullAllianceState::Ready)
    {
        trustutils::SetTwillsFullAllianceState(PChar, trustutils::TwillsFullAllianceState::Failed);
    }
    else if (state != trustutils::TwillsFullAllianceState::Failed && PChar->GetLocalVar(kTrustEvidenceModeVar) != 0)
    {
        // A malformed non-idle mode must still become projection-inactive before
        // native teardown. The post-zone fallback normalizes it to Idle.
        PChar->SetLocalVar(kTrustSessionStateVar, static_cast<uint32>(trustutils::TwillsFullAllianceState::Failed));
    }

    PChar->SetLocalVar(kTrustPendingTimersVar, 0);
    charutils::SetCharVar(PChar, "TrustEngageType", 0, 0);
}

void forceResetTwillsTrustSession(CCharEntity* PChar)
{
    if (!PChar || PChar->getName() != "Twills")
    {
        return;
    }

    const auto generation = PChar->GetLocalVar(kTrustSessionGenerationVar);
    PChar->SetLocalVar(
        kTrustSessionGenerationVar,
        generation == std::numeric_limits<uint32>::max() ? 1U : generation + 1U);
    PChar->SetLocalVar(kTrustSessionStateVar, static_cast<uint32>(trustutils::TwillsFullAllianceState::Idle));
    PChar->SetLocalVar(kTrustEvidenceModeVar, 0);
    PChar->SetLocalVar(kTrustSessionStartedVar, 0);
    PChar->SetLocalVar(kTrustSessionZoneVar, 0);
    PChar->SetLocalVar(kTrustEvidenceSequenceVar, 0);
    PChar->SetLocalVar(kTrustEvidenceSchemaVar, 0);
    PChar->SetLocalVar(kTrustPendingTimersVar, 0);
    PChar->SetLocalVar(kTrustLogTruncatedVar, 0);
    charutils::SetCharVar(PChar, "TrustEngageType", 0, 0);
}

auto lifecycleCloseReason(const CCharEntity* PChar) -> const char*
{
    return PChar && PChar->status == xi::Status::Shutdown ? "logout" : "zone";
}

bool repairChocobo(uint32 charId)
{
    static constexpr uint32 kAdultAgeSeconds = 64u * 86400u;

    const auto rset = db::preparedStmt(
        "INSERT INTO char_chocobos "
        "(charid, first_name, last_name, sex, created, last_update_age, stage, "
        "location, color, "
        "allele1, allele2, allele3, strength, endurance, discernment, "
        "receptivity, affection, "
        "energy, satisfaction, conditions, ability1, ability2, personality, "
        "weather_preference, "
        "hunger, care_plan, held_item) "
        "VALUES (?, 'Mochi', 'Galloper', 1, FROM_UNIXTIME(UNIX_TIMESTAMP() - ?), "
        "64, 6, 1, 1, "
        "1, 1, 1, 255, 255, 159, 159, 255, 100, 255, 0, 1, 2, 2, 0, 7, 0, 0) "
        "ON DUPLICATE KEY UPDATE "
        "first_name = VALUES(first_name), last_name = VALUES(last_name), sex = "
        "VALUES(sex), "
        "created = VALUES(created), last_update_age = VALUES(last_update_age), "
        "stage = VALUES(stage), location = VALUES(location), color = "
        "VALUES(color), "
        "allele1 = VALUES(allele1), allele2 = VALUES(allele2), allele3 = "
        "VALUES(allele3), "
        "strength = VALUES(strength), endurance = VALUES(endurance), "
        "discernment = VALUES(discernment), receptivity = VALUES(receptivity), "
        "affection = VALUES(affection), energy = VALUES(energy), "
        "satisfaction = VALUES(satisfaction), conditions = VALUES(conditions), "
        "ability1 = VALUES(ability1), ability2 = VALUES(ability2), "
        "personality = VALUES(personality), weather_preference = "
        "VALUES(weather_preference), "
        "hunger = VALUES(hunger), care_plan = VALUES(care_plan), held_item = "
        "VALUES(held_item)",
        charId,
        kAdultAgeSeconds);

    return static_cast<bool>(rset);
}

void repairProfileAndStorage(uint32 charId)
{
    db::preparedStmt("UPDATE char_profile SET "
                     "rank_points = 0, "
                     "rank_sandoria = 10, rank_bastok = 10, rank_windurst = 10, "
                     "fame_sandoria = ?, fame_bastok = ?, fame_windurst = ?, "
                     "fame_norg = ?, fame_jeuno = ?, "
                     "fame_aby_konschtat = ?, fame_aby_tahrongi = ?, "
                     "fame_aby_latheine = ?, fame_aby_misareaux = ?, "
                     "fame_aby_vunkerl = ?, fame_aby_attohwa = ?, "
                     "fame_aby_altepa = ?, fame_aby_grauberg = ?, "
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
        "wardrobe3 = GREATEST(wardrobe3, 80), wardrobe4 = GREATEST(wardrobe4, "
        "80), "
        "wardrobe5 = GREATEST(wardrobe5, 80), wardrobe6 = GREATEST(wardrobe6, "
        "80), "
        "wardrobe7 = GREATEST(wardrobe7, 80), wardrobe8 = GREATEST(wardrobe8, "
        "80) "
        "WHERE charid = ? LIMIT 1",
        kMaxInventorySize,
        charId);

    db::preparedStmt(
        "UPDATE chars SET nation = 0, gmlevel = 5 WHERE charid = ? LIMIT 1",
        charId);

    db::preparedStmt("INSERT IGNORE INTO char_pet (charid) VALUES (?)", charId);
}

} // namespace

class TwillsAdminModule : public CPPModule
{
public:
    void OnCharZoneIn(CCharEntity* PChar) override
    {
        resetTwillsTrustSession(PChar);
    }

    void OnCharPreZoneOut(CCharEntity* PChar) override
    {
        if (!PChar || PChar->getName() != "Twills")
        {
            return;
        }

        const auto state      = trustutils::GetTwillsFullAllianceState(PChar);
        const auto mode       = PChar->GetLocalVar(kTrustEvidenceModeVar);
        const auto hasSession = state != trustutils::TwillsFullAllianceState::Idle || mode != 0;
        if (!hasSession)
        {
            return;
        }

        const auto callbackSucceeded = callTrustLifecycle("beginLifecycleClose", PChar, lifecycleCloseReason(PChar));
        const auto luaDeactivated =
            trustutils::GetTwillsFullAllianceState(PChar) == trustutils::TwillsFullAllianceState::Failed &&
            PChar->GetLocalVar(kTrustPendingTimersVar) == 0 &&
            charutils::GetCharVar(PChar, "TrustEngageType") == 0;
        if (!callbackSucceeded || !luaDeactivated)
        {
            trustutils::MarkTrustEvidenceTruncated(
                PChar,
                callbackSucceeded ? "lifecycle_pre_incomplete" : "lifecycle_pre_failed");
        }

        // Lua owns the evidence rows. C++ owns the teardown invariant: the QA
        // projection and its pending callbacks must be inactive before the
        // upstream zone-out path's first effective ClearTrusts call, even if
        // Lua or evidence I/O fails.
        forceDeactivateTwillsTrustSession(PChar);
    }

    void OnCharZoneOut(CCharEntity* PChar) override
    {
        if (!PChar || PChar->getName() != "Twills")
        {
            return;
        }

        const auto state        = trustutils::GetTwillsFullAllianceState(PChar);
        const auto mode         = PChar->GetLocalVar(kTrustEvidenceModeVar);
        const auto pendingClose = state == trustutils::TwillsFullAllianceState::Failed && mode != 0;

        if (pendingClose)
        {
            const auto callbackSucceeded = callTrustLifecycle("finishLifecycleClose", PChar, lifecycleCloseReason(PChar));
            const auto cleanupComplete =
                trustutils::GetTwillsFullAllianceState(PChar) == trustutils::TwillsFullAllianceState::Idle &&
                PChar->GetLocalVar(kTrustEvidenceModeVar) == 0 &&
                PChar->GetLocalVar(kTrustPendingTimersVar) == 0 &&
                charutils::GetCharVar(PChar, "TrustEngageType") == 0 &&
                PChar->PTrusts.empty();

            if (!cleanupComplete)
            {
                trustutils::MarkTrustEvidenceTruncated(PChar, "lifecycle_post_incomplete");
                forceResetTwillsTrustSession(PChar);
            }
            else if (!callbackSucceeded)
            {
                ShowWarning("Mochirii Trust lifecycle: post callback reported an evidence sink failure after cleanup");
            }

            return;
        }

        if (state != trustutils::TwillsFullAllianceState::Idle || mode != 0)
        {
            trustutils::MarkTrustEvidenceTruncated(PChar, "lifecycle_post_stale_state");
            forceResetTwillsTrustSession(PChar);
            return;
        }

        resetTwillsTrustSession(PChar);
    }

    void OnInit() override
    {
        auto xi          = lua["xi"].get_or_create<sol::table>();
        auto twillsAdmin = xi["twills_admin"].get_or_create<sol::table>();
        auto native      = twillsAdmin["native"].get_or_create<sol::table>();

        native["repairCoreState"] = [](uint32 charId)
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
            repairAlterEgoPoints(charId);
            repairCrafts(charId);
            repairTravelUnlocks(charId);
            repairUnitySylvie(charId);
            repairSpellbook(charId);
            repairTrustAllianceEntitlement(charId);
            repairProfileAndStorage(charId);

            return true;
        };

        native["auditDbState"]         = auditDbState;
        native["auditMetadataState"]   = auditMetadataState;
        native["auditMeritState"]      = auditMeritState;
        native["auditCurrencyState"]   = auditCurrencyState;
        native["repairMetadata"]       = repairVeteranMetadataForPlayer;
        native["repairMerits"]         = repairMeritsForPlayer;
        native["repairCurrencyPolicy"] = repairCurrencyPolicyForPlayer;
        native["repairChocobo"]        = repairChocobo;
    }

private:
    auto callTrustLifecycle(const char* functionName, CCharEntity* PChar, const char* reason) -> bool
    {
        try
        {
            const sol::object xiObject = lua["xi"];
            if (xiObject.get_type() != sol::type::table)
            {
                ShowWarningFmt("Mochirii Trust lifecycle: xi table unavailable for {}", functionName);
                return false;
            }

            const auto        xiObjectTable = xiObject.as<sol::table>();
            const sol::object parityObject  = xiObjectTable["trustRetailParity"];
            if (parityObject.get_type() != sol::type::table)
            {
                ShowWarningFmt("Mochirii Trust lifecycle: trustRetailParity table unavailable for {}", functionName);
                return false;
            }

            const auto        parityTable    = parityObject.as<sol::table>();
            const sol::object callbackObject = parityTable[functionName];
            if (callbackObject.get_type() != sol::type::function)
            {
                ShowWarningFmt("Mochirii Trust lifecycle: {} callback unavailable", functionName);
                return false;
            }

            auto       callback = callbackObject.as<sol::protected_function>();
            const auto result   = callback(PChar, reason);
            if (!result.valid())
            {
                const sol::error error = result;
                ShowWarningFmt("Mochirii Trust lifecycle: {} failed: {}", functionName, error.what());
                return false;
            }

            return result.get_type(0) != sol::type::boolean || result.get<bool>(0);
        }
        catch (const std::exception& error)
        {
            ShowWarningFmt("Mochirii Trust lifecycle: {} threw: {}", functionName, error.what());
            return false;
        }
        catch (...)
        {
            ShowWarningFmt("Mochirii Trust lifecycle: {} threw an unknown exception", functionName);
            return false;
        }
    }
};

REGISTER_CPP_MODULE(TwillsAdminModule);
