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
#include "utils/charutils.h"
#include "utils/itemutils.h"

#include <array>
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
            "`case` = GREATEST(`case`, 80), wardrobe = GREATEST(wardrobe, 80), wardrobe2 = GREATEST(wardrobe2, 80), "
            "wardrobe3 = GREATEST(wardrobe3, 80), wardrobe4 = GREATEST(wardrobe4, 80), "
            "wardrobe5 = GREATEST(wardrobe5, 80), wardrobe6 = GREATEST(wardrobe6, 80), "
            "wardrobe7 = GREATEST(wardrobe7, 80), wardrobe8 = GREATEST(wardrobe8, 80) "
            "WHERE charid = ? LIMIT 1",
            kMaxInventorySize,
            charId);

        db::preparedStmt(
            "UPDATE chars SET nation = 0, gmlevel = 5 WHERE charid = ? LIMIT 1",
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
            repairMerits(charId);
            repairAlterEgoPoints(charId);
            repairProfileAndStorage(charId);

            return true;
        };

        native["grantGear"] = grantGear;
    }
};

REGISTER_CPP_MODULE(TwillsAdminModule);
