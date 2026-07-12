/************************************************************************
 * Mochirii Craft QA
 *
 * GM-only helpers for testing endgame Cooking through the normal synthesis
 * path. This module stages crystals/ingredients, starts synthutils::startSynth,
 * and lets the character's normal synth state finish the craft.
 ************************************************************************/

#include "common/database.h"
#include "common/logging.h"
#include "common/timer.h"
#include "entities/char_entity.h"
#include "enums/chat_message_type.h"
#include "enums/key_items.h"
#include "item_container.h"
#include "items/item.h"
#include "items/transactions/synth.h"
#include "lua/lua_base_entity.h"
#include "lua/luautils.h"
#include "map/utils/moduleutils.h"
#include "packets/s2c/0x017_chat_std.h"
#include "packets/s2c/0x020_item_attr.h"
#include "status_effect.h"
#include "status_effect_container.h"
#include "utils/charutils.h"
#include "utils/itemutils.h"
#include "utils/synthutils.h"
#include "zone.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdlib>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <map>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace
{

constexpr const char* kRequiredCookName          = "Twills";
constexpr uint8       kAlchemySkillId            = static_cast<uint8>(xi::SkillType::Alchemy);
constexpr uint8       kFishingSkillId            = static_cast<uint8>(xi::SkillType::Fishing);
constexpr uint8       kSynergySkillId            = static_cast<uint8>(xi::SkillType::Synergy);
constexpr uint16      kExpertSkill               = 1100;
constexpr uint8       kExpertRank                = 10;
constexpr uint16      kCommonSkill               = 700;
constexpr uint8       kCommonRank                = 6;
constexpr uint16      kSynergySkill              = 800;
constexpr uint8       kSynergyRank               = 7;
constexpr uint32      kGuildPointFloor           = 200000;
constexpr uint8       kDefaultAttempts           = 50;
constexpr uint8       kQueueCraftIntervalSeconds = 30;
constexpr uint16      kCookingEffectiveSupport   = 6;
constexpr uint16      kCookingImageryLoss        = 10;
constexpr uint8       kTwillsRetailCookingCap    = 70;

auto runtimeEvidenceRoot() -> std::filesystem::path
{
    if (const auto* runtimeRoot = std::getenv("MOCHIRII_RUNTIME_ROOT"); runtimeRoot && *runtimeRoot)
    {
        return std::filesystem::path(runtimeRoot) / "crafting" / "cooking";
    }

    return std::filesystem::path("log") / "craftqa" / "cooking";
}

constexpr std::array<uint8, 5> kArchiveContainers = {
    LOC_MOGCASE,
    LOC_MOGSACK,
    LOC_MOGSATCHEL,
    LOC_MOGSAFE,
    LOC_MOGSAFE2,
};

constexpr std::array<uint16, 6> kCookingKeyItems = {
    2040, // Raw Fish Handling
    2041, // Noodle Kneading
    2042, // Patissier
    2043, // Stewpot Mastery
    2044, // Way of the Culinarian
    2046, // Culinarian's Aurum Tome
};

void setLiveCraftSkill(CCharEntity* PChar, uint8 skillId, uint16 value, uint8 rank)
{
    PChar->RealSkills.skill[skillId]    = value;
    PChar->RealSkills.rank[skillId]     = rank;
    PChar->WorkingSkills.rank[skillId]  = rank;
    PChar->WorkingSkills.skill[skillId] = static_cast<uint16>((value / 10) * 0x20 + rank);

    if (static_cast<uint16>((rank + 1) * 100) <= value)
    {
        PChar->WorkingSkills.skill[skillId] |= 0x8000;
    }
}

struct Recipe
{
    uint32                id{};
    uint8                 desynth{};
    KeyItem               requiredKeyItem{ KeyItem::NONE };
    uint8                 cook{};
    uint16                crystal{};
    std::array<uint16, 8> ingredients{};
    std::array<uint16, 4> results{};
    std::array<uint8, 4>  resultQty{};
    std::string           resultName;
    std::string           contentTag;
};

struct QueueState
{
    bool                          active{ false };
    bool                          paused{ false };
    uint8                         maxAttempts{ kDefaultAttempts };
    uint32                        index{ 0 };
    uint32                        started{ 0 };
    uint32                        completed{ 0 };
    std::vector<uint32>           recipeIds{};
    std::map<uint32, uint8>       attempts{};
    std::map<uint32, std::string> blocked{};
    timer::time_point             nextAttempt{ timer::now() };
};

struct ActiveCraft
{
    uint32            recipeId{};
    std::string       context;
    timer::time_point started{ timer::now() };
};

struct HistoryProof
{
    uint32 recipeId{};
    bool   awaitingNativeFirst{ false };
    bool   firstComplete{ false };
    bool   awaitingLastSynth{ false };
    bool   lastSynthStarted{ false };
    bool   verified{ false };
    bool   mismatchLogged{ false };
};

std::unordered_map<uint32, QueueState>   craftQueues;
std::unordered_map<uint32, uint32>       lastManualRecipeIds;
std::unordered_map<uint32, ActiveCraft>  activeCrafts;
std::unordered_map<uint32, HistoryProof> historyProofs;
std::unordered_map<uint32, bool>         verboseCraftQa;

auto archiveAllEndgameResults(CCharEntity* PChar) -> uint16;
void observeCraftCompletion(CCharEntity* PChar);

auto getCharacter(CLuaBaseEntity* luaEntity) -> CCharEntity*
{
    if (luaEntity == nullptr)
    {
        return nullptr;
    }

    return dynamic_cast<CCharEntity*>(luaEntity->GetBaseEntity());
}

auto newTable(sol::this_state state) -> sol::table
{
    sol::state_view lua(state);
    return lua.create_table();
}

void addRow(sol::table& rows, uint32& index, const std::string& row)
{
    rows[index++] = row;
}

auto loadRecipe(uint32 recipeId) -> std::optional<Recipe>
{
    const auto rset = db::preparedStmt(
        "SELECT ID, Desynth, KeyItem, Cook, Crystal, "
        "Ingredient1, Ingredient2, Ingredient3, Ingredient4, Ingredient5, Ingredient6, Ingredient7, Ingredient8, "
        "Result, ResultHQ1, ResultHQ2, ResultHQ3, "
        "ResultQty, ResultHQ1Qty, ResultHQ2Qty, ResultHQ3Qty, "
        "ResultName, content_tag "
        "FROM synth_recipes WHERE ID = ? LIMIT 1",
        recipeId);

    if (!rset || !rset->next())
    {
        return std::nullopt;
    }

    Recipe recipe{};
    recipe.id              = rset->get<uint32>("ID");
    recipe.desynth         = rset->get<uint8>("Desynth");
    recipe.requiredKeyItem = rset->get<KeyItem>("KeyItem");
    recipe.cook            = rset->get<uint8>("Cook");
    recipe.crystal         = rset->get<uint16>("Crystal");
    recipe.ingredients     = {
        rset->get<uint16>("Ingredient1"),
        rset->get<uint16>("Ingredient2"),
        rset->get<uint16>("Ingredient3"),
        rset->get<uint16>("Ingredient4"),
        rset->get<uint16>("Ingredient5"),
        rset->get<uint16>("Ingredient6"),
        rset->get<uint16>("Ingredient7"),
        rset->get<uint16>("Ingredient8"),
    };
    recipe.results = {
        rset->get<uint16>("Result"),
        rset->get<uint16>("ResultHQ1"),
        rset->get<uint16>("ResultHQ2"),
        rset->get<uint16>("ResultHQ3"),
    };
    recipe.resultQty = {
        rset->get<uint8>("ResultQty"),
        rset->get<uint8>("ResultHQ1Qty"),
        rset->get<uint8>("ResultHQ2Qty"),
        rset->get<uint8>("ResultHQ3Qty"),
    };
    recipe.resultName = rset->get<std::string>("ResultName");
    recipe.contentTag = rset->getOrDefault<std::string>("content_tag", "");

    return recipe;
}

auto getEndgameRecipeIds() -> std::vector<uint32>
{
    std::vector<uint32> recipeIds;
    const auto          rset = db::preparedStmt(
        "SELECT ID FROM synth_recipes "
        "WHERE Desynth = 0 AND Cook >= 90 "
        "ORDER BY Cook DESC, ResultName, ID");

    while (rset && rset->next())
    {
        recipeIds.emplace_back(rset->get<uint32>("ID"));
    }

    return recipeIds;
}

auto uniqueResults(const Recipe& recipe) -> std::vector<uint16>
{
    std::vector<uint16> results;
    for (const auto resultId : recipe.results)
    {
        if (resultId != 0 && std::find(results.begin(), results.end(), resultId) == results.end())
        {
            results.emplace_back(resultId);
        }
    }

    return results;
}

auto targetIsValid(const Recipe& recipe, bool requireEndgame = true) -> std::string
{
    if (recipe.desynth != 0)
    {
        return "desynthesis recipe";
    }

    if (requireEndgame && recipe.cook < 90)
    {
        return "not an endgame Cooking recipe";
    }

    if (!recipe.contentTag.empty() && !luautils::IsContentEnabled(recipe.contentTag))
    {
        return "content tag disabled: " + recipe.contentTag;
    }

    if (recipe.crystal == 0 || xi::items::lookup(recipe.crystal) == nullptr)
    {
        return "missing local crystal item";
    }

    for (const auto itemId : recipe.ingredients)
    {
        if (itemId != 0 && xi::items::lookup(itemId) == nullptr)
        {
            return "missing local ingredient item " + std::to_string(itemId);
        }
    }

    if (recipe.results[0] == 0 || xi::items::lookup(recipe.results[0]) == nullptr)
    {
        return "missing local result item";
    }

    for (const auto itemId : uniqueResults(recipe))
    {
        if (xi::items::lookup(itemId) == nullptr)
        {
            return "missing local HQ result item " + std::to_string(itemId);
        }
    }

    return {};
}

auto retailCraftCapBlockReason(const Recipe& recipe) -> std::string
{
    if (recipe.cook > kTwillsRetailCookingCap)
    {
        return fmt::format("blocked_retail_cap: Twills is Alchemy 110; Cooking is capped at {} for strict retail parity", kTwillsRetailCookingCap);
    }

    return {};
}

auto nowUtcText() -> std::string
{
    const auto now = std::time(nullptr);
    std::tm    tm{};
#if defined(_WIN32)
    gmtime_s(&tm, &now);
#else
    gmtime_r(&now, &tm);
#endif

    std::ostringstream out;
    out << std::put_time(&tm, "%Y-%m-%dT%H:%M:%SZ");
    return out.str();
}

auto evidenceFilePath() -> std::filesystem::path
{
    static const auto path = []()
    {
        const auto now = std::time(nullptr);
        std::tm    tm{};
#if defined(_WIN32)
        gmtime_s(&tm, &now);
#else
        gmtime_r(&now, &tm);
#endif

        std::ostringstream stamp;
        stamp << std::put_time(&tm, "%Y%m%d-%H%M%S");

        auto            dir = runtimeEvidenceRoot() / stamp.str();
        std::error_code ec;
        std::filesystem::create_directories(dir, ec);
        return dir / "craftqa.tsv";
    }();

    return path;
}

auto tsvSafe(std::string value) -> std::string
{
    for (auto& ch : value)
    {
        if (ch == '\t' || ch == '\r' || ch == '\n')
        {
            ch = ' ';
        }
    }

    return value;
}

void logEvidence(CCharEntity* PChar, const Recipe* recipe, const std::string& event, uint32 itemId, uint32 quantity, const std::string& detail)
{
    const auto    path      = evidenceFilePath();
    const bool    writeHead = !std::filesystem::exists(path);
    std::ofstream evidence(path, std::ios::app);
    if (!evidence)
    {
        ShowWarningFmt("Mochirii CraftQA: unable to write evidence file {}", path.string());
        return;
    }

    if (writeHead)
    {
        evidence << "time_utc\tplayer\tevent\trecipe_id\tresult_name\tcook_cap\tcrystal\tkey_item\titem_id\tquantity\tdetail\n";
    }

    evidence << nowUtcText() << '\t'
             << (PChar ? PChar->getName() : "unknown") << '\t'
             << tsvSafe(event) << '\t'
             << (recipe ? recipe->id : 0) << '\t'
             << tsvSafe(recipe ? recipe->resultName : "") << '\t'
             << static_cast<uint32>(recipe ? recipe->cook : 0) << '\t'
             << (recipe ? recipe->crystal : 0) << '\t'
             << static_cast<uint32>(recipe ? recipe->requiredKeyItem : KeyItem::NONE) << '\t'
             << itemId << '\t'
             << quantity << '\t'
             << tsvSafe(detail) << '\n';
}

auto itemDisplayName(uint16 itemId) -> std::string
{
    if (const auto* item = xi::items::lookup(itemId))
    {
        return item->getName();
    }

    return fmt::format("item_{}", itemId);
}

auto synthResultName(uint8 result) -> std::string
{
    switch (result)
    {
        case synthutils::SYNTHESIS_SUCCESS:
            return "nq";
        case synthutils::SYNTHESIS_HQ:
            return "hq1";
        case synthutils::SYNTHESIS_HQ2:
            return "hq2";
        case synthutils::SYNTHESIS_HQ3:
            return "hq3";
        case synthutils::SYNTHESIS_FAIL:
        default:
            return "fail";
    }
}

auto resultForTier(const Recipe& recipe, uint8 result) -> std::pair<uint16, uint8>
{
    if (result >= synthutils::SYNTHESIS_SUCCESS && result <= synthutils::SYNTHESIS_HQ3)
    {
        const auto index = result - 1;
        return { recipe.results[index], recipe.resultQty[index] };
    }

    return { 0, 0 };
}

void printVerbose(CCharEntity* PChar, const std::string& message)
{
    if (PChar == nullptr || !verboseCraftQa[PChar->id])
    {
        return;
    }

    PChar->pushPacket<GP_SERV_COMMAND_CHAT_STD>(PChar, MESSAGE_SYSTEM_3, "CraftQA evidence: " + message, "");
}

auto canArchiveNow(CCharEntity* PChar) -> bool
{
    return PChar != nullptr &&
           !PChar->isCrafting() &&
           PChar->activeTransaction<SynthTransaction>() == nullptr &&
           activeCrafts.find(PChar->id) == activeCrafts.end();
}

auto inventoryCount(CCharEntity* PChar, uint16 itemId) -> uint32
{
    uint32 count = 0;
    auto*  inv   = PChar->getStorage(LOC_INVENTORY);
    if (inv == nullptr)
    {
        return count;
    }

    for (const auto slotId : inv->SearchItems(itemId))
    {
        if (const auto* item = inv->GetItem(slotId))
        {
            count += item->getQuantity();
        }
    }

    return count;
}

auto characterItemCount(uint32 charId, uint16 itemId) -> uint32
{
    const auto rset = db::preparedStmt(
        "SELECT COALESCE(SUM(quantity), 0) AS qty "
        "FROM char_inventory WHERE charid = ? AND itemId = ?",
        charId,
        itemId);

    if (rset && rset->next())
    {
        return rset->get<uint32>("qty");
    }

    return 0;
}

auto recipeIsSaved(CCharEntity* PChar, const Recipe& recipe) -> bool
{
    for (const auto resultId : uniqueResults(recipe))
    {
        if (characterItemCount(PChar->id, resultId) == 0)
        {
            return false;
        }
    }

    return true;
}

auto cookingCoverageStatus(CCharEntity* PChar, const Recipe& recipe) -> std::string
{
    if (const auto invalidReason = targetIsValid(recipe, false); !invalidReason.empty())
    {
        return "unsupported: " + invalidReason;
    }

    if (const auto capReason = retailCraftCapBlockReason(recipe); !capReason.empty())
    {
        return capReason;
    }

    return recipeIsSaved(PChar, recipe) ? "saved" : "craftable_unsaved";
}

auto stageItem(CCharEntity* PChar, uint16 itemId, uint32 quantity) -> bool
{
    if (quantity == 0)
    {
        return true;
    }

    if (charutils::AddItem(PChar, LOC_INVENTORY, itemId, quantity, true) == ERROR_SLOTID)
    {
        ShowWarningFmt("Mochirii CraftQA: failed to stage item {} x{} for {}", itemId, quantity, PChar->getName());
        return false;
    }

    return true;
}

auto stageRecipe(CCharEntity* PChar, const Recipe& recipe, uint8 attempts, std::string& reason) -> bool
{
    std::map<uint16, uint32> required;
    required[recipe.crystal] += attempts;
    for (const auto itemId : recipe.ingredients)
    {
        if (itemId != 0)
        {
            required[itemId] += attempts;
        }
    }

    for (const auto& [itemId, quantity] : required)
    {
        const auto have = inventoryCount(PChar, itemId);
        if (have >= quantity)
        {
            continue;
        }

        const auto stagedQuantity = quantity - have;
        if (!stageItem(PChar, itemId, stagedQuantity))
        {
            reason = fmt::format("could not stage item {} x{}", itemId, stagedQuantity);
            logEvidence(PChar, &recipe, "stage_failed", itemId, stagedQuantity, reason);
            return false;
        }

        logEvidence(PChar, &recipe, "stage_item", itemId, stagedQuantity, "crystal_or_ingredient");
    }

    logEvidence(PChar, &recipe, "stage_complete", 0, attempts, "all required crystal and ingredient quantities are present");
    return true;
}

auto chooseSlot(CItemContainer* inv, uint16 itemId, std::array<uint8, MAX_CONTAINER_SIZE>& slotUse) -> uint8
{
    for (const auto slotId : inv->SearchItems(itemId))
    {
        const auto* item = inv->GetItem(slotId);
        if (item && !item->isBusy() && !item->isSubType(ITEM_LOCKED) && item->getQuantity() > slotUse[slotId])
        {
            slotUse[slotId]++;
            return slotId;
        }
    }

    return ERROR_SLOTID;
}

auto buildOffer(CCharEntity* PChar, const Recipe& recipe, SynthOffer& offer, std::string& reason) -> bool
{
    auto* inv = PChar->getStorage(LOC_INVENTORY);
    if (inv == nullptr)
    {
        reason = "missing inventory container";
        return false;
    }

    std::array<uint8, MAX_CONTAINER_SIZE> slotUse{};

    const auto crystalSlot = chooseSlot(inv, recipe.crystal, slotUse);
    if (crystalSlot == ERROR_SLOTID)
    {
        reason = "missing crystal";
        return false;
    }

    offer.crystal = { recipe.crystal, crystalSlot };

    for (size_t index = 0; index < recipe.ingredients.size(); ++index)
    {
        const auto itemId = recipe.ingredients[index];
        if (itemId == 0)
        {
            continue;
        }

        const auto slotId = chooseSlot(inv, itemId, slotUse);
        if (slotId == ERROR_SLOTID)
        {
            reason = "missing ingredient " + std::to_string(itemId);
            return false;
        }

        offer.ingredients[index] = { itemId, slotId };
    }

    return true;
}

auto moveItemBetweenContainers(CCharEntity* PChar, uint8 srcContainer, uint8 srcSlot, uint8 dstContainer) -> bool
{
    auto* src = PChar->getStorage(srcContainer);
    auto* dst = PChar->getStorage(dstContainer);
    if (src == nullptr || dst == nullptr || dst->GetFreeSlotsCount() == 0)
    {
        return false;
    }

    const auto newSlotId = src->MoveItemTo(srcSlot, *dst);
    if (newSlotId == ERROR_SLOTID)
    {
        return false;
    }

    const auto rset = db::preparedStmt(
        "UPDATE char_inventory SET location = ?, slot = ? "
        "WHERE charid = ? AND location = ? AND slot = ?",
        dstContainer,
        newSlotId,
        PChar->id,
        srcContainer,
        srcSlot);

    if (!rset || !rset->rowsAffected())
    {
        dst->MoveItemTo(newSlotId, *src, srcSlot);
        return false;
    }

    auto* moved = dst->GetItem(newSlotId);
    PChar->pushPacket<GP_SERV_COMMAND_ITEM_ATTR>(nullptr, static_cast<CONTAINER_ID>(srcContainer), srcSlot, moved);
    PChar->pushPacket<GP_SERV_COMMAND_ITEM_ATTR>(moved, static_cast<CONTAINER_ID>(dstContainer), newSlotId);
    return true;
}

auto archiveRecipeResults(CCharEntity* PChar, const Recipe& recipe) -> uint8
{
    uint8 archived = 0;
    if (!canArchiveNow(PChar))
    {
        logEvidence(PChar, &recipe, "archive_deferred", 0, 0, "character is crafting, transaction-owned, or completion evidence is pending");
        return archived;
    }

    auto* inv = PChar->getStorage(LOC_INVENTORY);
    if (inv == nullptr)
    {
        return archived;
    }

    for (const auto resultId : uniqueResults(recipe))
    {
        bool       resultSaved = false;
        const auto saved       = db::preparedStmt(
            "SELECT 1 FROM char_inventory "
            "WHERE charid = ? AND itemId = ? AND location <> ? LIMIT 1",
            PChar->id,
            resultId,
            LOC_INVENTORY);

        if (saved && saved->next())
        {
            resultSaved = true;
        }

        const auto slotIds = inv->SearchItems(resultId);
        for (const auto slotId : slotIds)
        {
            const auto* sourceItem = inv->GetItem(slotId);
            if (sourceItem == nullptr)
            {
                continue;
            }

            const auto quantity = sourceItem->getQuantity();
            if (resultSaved)
            {
                charutils::UpdateItem(PChar, LOC_INVENTORY, slotId, -static_cast<int32>(quantity), true);
                logEvidence(PChar, &recipe, "discard_duplicate_result", resultId, quantity, "one saved copy already exists outside active inventory");
                continue;
            }

            for (const auto dstContainer : kArchiveContainers)
            {
                if (moveItemBetweenContainers(PChar, LOC_INVENTORY, slotId, dstContainer))
                {
                    resultSaved = true;
                    ++archived;
                    logEvidence(PChar, &recipe, "saved_result", resultId, quantity, fmt::format("moved to container {}", dstContainer));
                    break;
                }
            }
        }
    }

    return archived;
}

auto archiveAllEndgameResults(CCharEntity* PChar) -> uint16
{
    uint16 archived = 0;
    for (const auto recipeId : getEndgameRecipeIds())
    {
        const auto recipe = loadRecipe(recipeId);
        if (!recipe)
        {
            continue;
        }

        archived += archiveRecipeResults(PChar, *recipe);
    }

    if (archived > 0)
    {
        logEvidence(PChar, nullptr, "archive_sweep", 0, archived, "moved saved endgame Cooking result(s) out of active inventory before staging");
    }

    return archived;
}

void ensureCookingSupport(CCharEntity* PChar, const Recipe& recipe)
{
    auto* current = PChar->StatusEffectContainer->GetStatusEffect(xi::StatusEffect::CookingImagery);
    if (current != nullptr && current->GetPower() >= kCookingEffectiveSupport)
    {
        return;
    }

    if (current != nullptr)
    {
        PChar->StatusEffectContainer->DelStatusEffect(xi::StatusEffect::CookingImagery);
    }

    PChar->StatusEffectContainer->AddStatusEffect(
        xi::StatusEffect::CookingImagery,
        static_cast<uint16>(xi::StatusEffect::CookingImagery),
        kCookingEffectiveSupport,
        0s,
        480s,
        0,
        kCookingImageryLoss,
        0);

    logEvidence(PChar, &recipe, "support_applied", 0, kCookingEffectiveSupport, "advanced Cooking Imagery plus local Cooking gear effective bonus applied before normal synthesis");
}

auto ensureDedicatedCook(CCharEntity* PChar, std::string& reason) -> bool
{
    if (PChar == nullptr)
    {
        reason = "missing player";
        return false;
    }

    if (PChar->name != kRequiredCookName)
    {
        reason = "Cooking QA must be run on Twills only";
        return false;
    }

    return true;
}

auto repairDedicatedCook(CCharEntity* PChar) -> std::string
{
    db::preparedStmt(
        "UPDATE char_storage SET inventory = GREATEST(inventory, 80), safe = GREATEST(safe, 80), "
        "locker = GREATEST(locker, 80), satchel = GREATEST(satchel, 80), "
        "sack = GREATEST(sack, 80), `case` = GREATEST(`case`, 80) "
        "WHERE charid = ? LIMIT 1",
        PChar->id);

    for (uint8 skillId = static_cast<uint8>(xi::SkillType::Woodworking); skillId <= static_cast<uint8>(xi::SkillType::Cooking); ++skillId)
    {
        const bool isAlchemy = skillId == kAlchemySkillId;
        const auto value     = isAlchemy ? kExpertSkill : kCommonSkill;
        const auto rank      = isAlchemy ? kExpertRank : kCommonRank;

        db::preparedStmt(
            "INSERT INTO char_skills (charid, skillid, value, rank) VALUES (?, ?, ?, ?) "
            "ON DUPLICATE KEY UPDATE value = VALUES(value), rank = VALUES(rank)",
            PChar->id,
            skillId,
            value,
            rank);

        setLiveCraftSkill(PChar, skillId, value, rank);
        charutils::SaveCharSkills(PChar, skillId);
    }

    db::preparedStmt(
        "INSERT INTO char_skills (charid, skillid, value, rank) VALUES (?, ?, ?, ?) "
        "ON DUPLICATE KEY UPDATE value = VALUES(value), rank = VALUES(rank)",
        PChar->id,
        kFishingSkillId,
        kExpertSkill,
        kExpertRank);
    setLiveCraftSkill(PChar, kFishingSkillId, kExpertSkill, kExpertRank);

    db::preparedStmt(
        "INSERT INTO char_skills (charid, skillid, value, rank) VALUES (?, ?, ?, ?) "
        "ON DUPLICATE KEY UPDATE value = VALUES(value), rank = VALUES(rank)",
        PChar->id,
        kSynergySkillId,
        kSynergySkill,
        kSynergyRank);
    setLiveCraftSkill(PChar, kSynergySkillId, kSynergySkill, kSynergyRank);

    db::preparedStmt(
        "INSERT INTO char_points (charid, guild_cooking) VALUES (?, ?) "
        "ON DUPLICATE KEY UPDATE guild_cooking = GREATEST(guild_cooking, VALUES(guild_cooking))",
        PChar->id,
        kGuildPointFloor);

    for (const auto keyItem : kCookingKeyItems)
    {
        const auto typedKeyItem = static_cast<KeyItem>(keyItem);
        if (!charutils::hasKeyItem(PChar, typedKeyItem))
        {
            charutils::addKeyItem(PChar, typedKeyItem);
        }
    }

    charutils::SaveCharSkills(PChar, kFishingSkillId);
    charutils::SaveCharSkills(PChar, kSynergySkillId);

    logEvidence(PChar, nullptr, "repair_craft_caps", 0, 0, "Alchemy 110, Cooking 70, Fishing 110, Synergy 80, other synthesis 70; Cooking KIs retained for QA evidence only");
    return "Twills retail craft caps repaired: Alchemy 110, Cooking 70, Fishing 110, Synergy 80, other synthesis 70. Endgame Cooking is blocked unless Twills is explicitly switched to Cooking 110.";
}

auto startRecipe(CCharEntity* PChar, const Recipe& recipe, std::string& reason, bool requireEndgame = true, const std::string& context = "manual", uint8 stageAttempts = 1) -> bool
{
    if (PChar->isCrafting())
    {
        reason = "player is already crafting";
        logEvidence(PChar, &recipe, "craft_blocked", 0, 0, reason);
        return false;
    }

    const auto invalidReason = targetIsValid(recipe, requireEndgame);
    if (!invalidReason.empty())
    {
        reason = invalidReason;
        logEvidence(PChar, &recipe, "craft_blocked", 0, 0, reason);
        return false;
    }

    if (const auto capReason = retailCraftCapBlockReason(recipe); !capReason.empty())
    {
        reason = capReason;
        logEvidence(PChar, &recipe, "craft_blocked", 0, 0, reason);
        return false;
    }

    if (recipe.requiredKeyItem != KeyItem::NONE && !charutils::hasKeyItem(PChar, recipe.requiredKeyItem))
    {
        reason = "missing required Cooking key item";
        logEvidence(PChar, &recipe, "craft_blocked", 0, 0, reason);
        return false;
    }

    archiveAllEndgameResults(PChar);

    std::string stageReason;
    const auto  attemptsToStage = std::max<uint8>(1, stageAttempts);
    if (!stageRecipe(PChar, recipe, attemptsToStage, stageReason))
    {
        reason = stageReason;
        logEvidence(PChar, &recipe, "craft_blocked", 0, 0, reason);
        return false;
    }

    SynthOffer offer{};
    if (!buildOffer(PChar, recipe, offer, reason))
    {
        logEvidence(PChar, &recipe, "craft_blocked", 0, 0, reason);
        return false;
    }

    ensureCookingSupport(PChar, recipe);

    logEvidence(PChar, &recipe, "craft_start", 0, attemptsToStage, fmt::format("context={} normal synthesis started through synthutils::startSynth", context));
    synthutils::startSynth(PChar, offer);
    if (!PChar->isCrafting())
    {
        reason = "synthesis did not enter crafting state";
        logEvidence(PChar, &recipe, "craft_blocked", 0, 0, reason);
        return false;
    }

    activeCrafts[PChar->id] = ActiveCraft{ recipe.id, context, timer::now() };

    ShowInfoFmt("Mochirii CraftQA: {} started Cooking recipe {} ({})", PChar->getName(), recipe.id, recipe.resultName);
    return true;
}

void observeCraftCompletion(CCharEntity* PChar)
{
    if (PChar == nullptr || PChar->isCrafting() || PChar->activeTransaction<SynthTransaction>() != nullptr)
    {
        return;
    }

    const auto activeIt = activeCrafts.find(PChar->id);
    if (activeIt == activeCrafts.end())
    {
        return;
    }

    const auto active = activeIt->second;
    const auto recipe = loadRecipe(active.recipeId);
    const auto result = PChar->craftState().result();

    uint16 itemId = 0;
    uint8  qty    = 0;
    if (recipe)
    {
        const auto resultItem = resultForTier(*recipe, result);
        itemId                = resultItem.first;
        qty                   = resultItem.second;
    }

    const auto detail = fmt::format(
        "context={} result={} tier={} item={} item_name={} combine_packets=normal_synthutils_result_path",
        active.context,
        synthResultName(result),
        result,
        itemId,
        itemId == 0 ? "none" : itemDisplayName(itemId));

    logEvidence(PChar, recipe ? &*recipe : nullptr, "synth_complete", itemId, qty, detail);
    printVerbose(PChar, detail);

    if (active.context == "historyproof" || active.context == "native_history_seed")
    {
        auto& proof               = historyProofs[PChar->id];
        proof.recipeId            = active.recipeId;
        proof.awaitingNativeFirst = false;
        proof.firstComplete       = true;
        proof.awaitingLastSynth   = true;
        logEvidence(PChar, recipe ? &*recipe : nullptr, "historyproof_ready", itemId, qty, "native client synthesis completed; native /lastsynth should now repeat this recipe from client synthesis history");
        printVerbose(PChar, fmt::format("history proof ready for recipe {}; run /lastsynth", active.recipeId));
    }
    else if (active.context == "lastsynth")
    {
        auto& proof             = historyProofs[PChar->id];
        proof.recipeId          = active.recipeId;
        proof.awaitingLastSynth = false;
        proof.lastSynthStarted  = true;
        proof.verified          = true;
        logEvidence(PChar, recipe ? &*recipe : nullptr, "history_lastsynth_verified", itemId, qty, "native /lastsynth repeated the expected recipe from client synthesis history");
        printVerbose(PChar, fmt::format("native /lastsynth verified for recipe {}", active.recipeId));
    }

    activeCrafts.erase(activeIt);
}

void observeNativeLastSynthStart(CCharEntity* PChar)
{
    if (PChar == nullptr || !PChar->isCrafting() || activeCrafts.find(PChar->id) != activeCrafts.end())
    {
        return;
    }

    auto proofIt = historyProofs.find(PChar->id);
    if (proofIt == historyProofs.end() || proofIt->second.verified || (!proofIt->second.awaitingNativeFirst && !proofIt->second.awaitingLastSynth))
    {
        return;
    }

    const auto activeRecipeId = PChar->craftState().recipeId();
    if (activeRecipeId == proofIt->second.recipeId)
    {
        const auto recipe = loadRecipe(activeRecipeId);
        if (proofIt->second.awaitingNativeFirst && !proofIt->second.firstComplete)
        {
            activeCrafts[PChar->id]             = ActiveCraft{ activeRecipeId, "native_history_seed", timer::now() };
            proofIt->second.awaitingNativeFirst = false;
            logEvidence(PChar, recipe ? &*recipe : nullptr, "history_native_first_start", 0, 1, "observed native client synthesis starting the expected recipe");
            printVerbose(PChar, fmt::format("observed native client synthesis for recipe {}", activeRecipeId));
            return;
        }

        activeCrafts[PChar->id]          = ActiveCraft{ activeRecipeId, "lastsynth", timer::now() };
        proofIt->second.lastSynthStarted = true;
        logEvidence(PChar, recipe ? &*recipe : nullptr, "history_lastsynth_start", 0, 1, "observed native /lastsynth starting the expected recipe");
        printVerbose(PChar, fmt::format("observed native /lastsynth for recipe {}", activeRecipeId));
        return;
    }

    if (!proofIt->second.mismatchLogged)
    {
        proofIt->second.mismatchLogged = true;
        logEvidence(PChar, nullptr, "history_lastsynth_mismatch", 0, 0, fmt::format("expected_recipe={} active_recipe={}", proofIt->second.recipeId, activeRecipeId));
    }
}

auto nativeRows(sol::this_state state, const std::vector<std::string>& rows) -> sol::table
{
    auto   table = newTable(state);
    uint32 index = 1;
    for (const auto& row : rows)
    {
        addRow(table, index, row);
    }

    return table;
}

auto nativeRepairCook(sol::this_state state, CLuaBaseEntity* luaEntity) -> sol::table
{
    auto*       PChar = getCharacter(luaEntity);
    std::string reason;
    if (!ensureDedicatedCook(PChar, reason))
    {
        return nativeRows(state, { "[FAIL] " + reason });
    }

    return nativeRows(state, { "[OK] " + repairDedicatedCook(PChar) });
}

auto nativeStageRecipe(sol::this_state state, CLuaBaseEntity* luaEntity, uint32 recipeId, sol::optional<uint8> attemptsArg) -> sol::table
{
    auto*       PChar = getCharacter(luaEntity);
    std::string reason;
    if (!ensureDedicatedCook(PChar, reason))
    {
        return nativeRows(state, { "[FAIL] " + reason });
    }

    const auto recipe = loadRecipe(recipeId);
    if (!recipe)
    {
        return nativeRows(state, { "[FAIL] recipe not found: " + std::to_string(recipeId) });
    }

    const auto invalidReason = targetIsValid(*recipe, false);
    if (!invalidReason.empty())
    {
        return nativeRows(state, { "[FAIL] " + invalidReason });
    }

    if (const auto capReason = retailCraftCapBlockReason(*recipe); !capReason.empty())
    {
        return nativeRows(state, { "[FAIL] " + capReason });
    }

    const auto attempts = std::max<uint8>(1, attemptsArg.value_or(1));
    if (!stageRecipe(PChar, *recipe, attempts, reason))
    {
        return nativeRows(state, { "[FAIL] " + reason });
    }

    return nativeRows(state, { fmt::format("[OK] staged Cooking recipe {} ({}) for {} attempt(s)", recipe->id, recipe->resultName, attempts) });
}

auto nativeCraftRecipe(sol::this_state state, CLuaBaseEntity* luaEntity, uint32 recipeId) -> sol::table
{
    auto*       PChar = getCharacter(luaEntity);
    std::string reason;
    if (!ensureDedicatedCook(PChar, reason))
    {
        return nativeRows(state, { "[FAIL] " + reason });
    }

    const auto recipe = loadRecipe(recipeId);
    if (!recipe)
    {
        return nativeRows(state, { "[FAIL] recipe not found: " + std::to_string(recipeId) });
    }

    observeCraftCompletion(PChar);
    archiveRecipeResults(PChar, *recipe);

    if (!startRecipe(PChar, *recipe, reason, false, "manual"))
    {
        return nativeRows(state, { "[FAIL] " + reason });
    }

    lastManualRecipeIds[PChar->id] = recipe->id;
    return nativeRows(state, { fmt::format("[OK] started Cooking recipe {} ({}). Wait for synth completion before the next manual craft.", recipe->id, recipe->resultName) });
}

auto nativeHistoryProof(sol::this_state state, CLuaBaseEntity* luaEntity, uint32 recipeId) -> sol::table
{
    auto*       PChar = getCharacter(luaEntity);
    std::string reason;
    if (!ensureDedicatedCook(PChar, reason))
    {
        return nativeRows(state, { "[FAIL] " + reason });
    }

    observeCraftCompletion(PChar);
    if (PChar->isCrafting())
    {
        return nativeRows(state, { "[FAIL] wait for the current synthesis to finish before starting history proof" });
    }

    const auto recipe = loadRecipe(recipeId);
    if (!recipe)
    {
        return nativeRows(state, { "[FAIL] recipe not found: " + std::to_string(recipeId) });
    }

    const auto invalidReason = targetIsValid(*recipe, false);
    if (!invalidReason.empty())
    {
        return nativeRows(state, { "[FAIL] " + invalidReason });
    }

    if (const auto capReason = retailCraftCapBlockReason(*recipe); !capReason.empty())
    {
        return nativeRows(state, { "[FAIL] " + capReason });
    }

    if (auto queueIt = craftQueues.find(PChar->id); queueIt != craftQueues.end() && queueIt->second.active)
    {
        queueIt->second.paused = true;
        logEvidence(PChar, &*recipe, "batch_paused", 0, queueIt->second.attempts[recipeId], "paused for native synthesis history proof");
    }

    HistoryProof proof{};
    proof.recipeId            = recipe->id;
    proof.awaitingNativeFirst = true;
    historyProofs[PChar->id]  = proof;
    logEvidence(PChar, &*recipe, "historyproof_start", 0, 2, "staging two attempts; perform the first synth through the native client synthesis UI, then run /lastsynth after it completes");

    archiveRecipeResults(PChar, *recipe);
    if (!stageRecipe(PChar, *recipe, 2, reason))
    {
        return nativeRows(state, { "[FAIL] " + reason });
    }

    lastManualRecipeIds[PChar->id] = recipe->id;
    return nativeRows(state, {
                                 fmt::format("[OK] staged history proof recipe {} ({})", recipe->id, recipe->resultName),
                                 "Perform the first synth through the native client synthesis UI. After it finishes, run /lastsynth; CraftQA will verify the repeated recipe.",
                             });
}

auto nativeVerbose(sol::this_state state, CLuaBaseEntity* luaEntity, const std::string& mode) -> sol::table
{
    auto* PChar = getCharacter(luaEntity);
    if (PChar == nullptr)
    {
        return nativeRows(state, { "[FAIL] missing player" });
    }

    if (mode == "on")
    {
        verboseCraftQa[PChar->id] = true;
    }
    else if (mode == "off")
    {
        verboseCraftQa[PChar->id] = false;
    }
    else
    {
        return nativeRows(state, { "[FAIL] !craftqa cooking verbose on|off" });
    }

    logEvidence(PChar, nullptr, "verbose", 0, verboseCraftQa[PChar->id] ? 1 : 0, "GM-only CraftQA evidence chat toggled; native synth result chat remains unchanged");
    return nativeRows(state, { verboseCraftQa[PChar->id] ? "[OK] CraftQA verbose evidence chat enabled" : "[OK] CraftQA verbose evidence chat disabled" });
}

auto nativeBatchEndgame(sol::this_state state, CLuaBaseEntity* luaEntity, sol::optional<uint8>) -> sol::table
{
    auto*       PChar = getCharacter(luaEntity);
    std::string reason;
    if (!ensureDedicatedCook(PChar, reason))
    {
        return nativeRows(state, { "[FAIL] " + reason });
    }

    logEvidence(PChar, nullptr, "batch_blocked_retail_cap", 0, 0, "Twills is Alchemy 110 and Cooking 70; endgame Cooking batch requires explicit Cooking 110 QA exception");
    return nativeRows(state, { "[FAIL] Endgame Cooking batch blocked: Twills is Alchemy 110 and Cooking 70 for strict retail parity.", "Use !craftqa cooking report to classify the manifest, or explicitly switch Twills to Cooking 110 in a future QA exception pass." });
}

auto nativePause(sol::this_state state, CLuaBaseEntity* luaEntity, bool paused) -> sol::table
{
    auto* PChar = getCharacter(luaEntity);
    if (PChar == nullptr)
    {
        return nativeRows(state, { "[FAIL] missing player" });
    }

    auto& queue = craftQueues[PChar->id];
    if (!queue.active)
    {
        return nativeRows(state, { "[FAIL] no active Cooking batch" });
    }

    queue.paused = paused;
    return nativeRows(state, { paused ? "[OK] Cooking batch paused" : "[OK] Cooking batch resumed" });
}

auto nativeStatus(sol::this_state state, CLuaBaseEntity* luaEntity) -> sol::table
{
    auto* PChar = getCharacter(luaEntity);
    if (PChar == nullptr)
    {
        return nativeRows(state, { "[FAIL] missing player" });
    }

    std::vector<std::string> rows;
    rows.emplace_back(fmt::format("Cooking QA character: {}{}", PChar->getName(), PChar->getName() == "Twills" ? " [required for Cooking QA]" : ""));
    rows.emplace_back(fmt::format("Crafting now: {}", PChar->isCrafting() ? "yes" : "no"));

    const auto targetIds        = getEndgameRecipeIds();
    uint32     saved            = 0;
    uint32     blockedRetailCap = 0;
    uint32     unsupported      = 0;
    for (const auto recipeId : targetIds)
    {
        const auto recipe = loadRecipe(recipeId);
        if (!recipe)
        {
            ++unsupported;
            continue;
        }

        const auto status = cookingCoverageStatus(PChar, *recipe);
        if (status == "saved")
        {
            ++saved;
        }
        else if (status.starts_with("blocked_retail_cap"))
        {
            ++blockedRetailCap;
        }
        else if (status.starts_with("unsupported"))
        {
            ++unsupported;
        }
    }

    rows.emplace_back(fmt::format("Endgame Cooking coverage: saved={} blocked_retail_cap={} unsupported={} total={}", saved, blockedRetailCap, unsupported, targetIds.size()));
    rows.emplace_back("Retail cap: Twills is Alchemy 110; Cooking is 70. Endgame Cooking completion is intentionally blocked.");

    observeCraftCompletion(PChar);

    if (auto proofIt = historyProofs.find(PChar->id); proofIt != historyProofs.end())
    {
        const auto& proof = proofIt->second;
        rows.emplace_back(fmt::format(
            "History proof: recipe={} awaiting_native_first={} first_complete={} awaiting_lastsynth={} lastsynth_started={} verified={}",
            proof.recipeId,
            proof.awaitingNativeFirst ? "yes" : "no",
            proof.firstComplete ? "yes" : "no",
            proof.awaitingLastSynth ? "yes" : "no",
            proof.lastSynthStarted ? "yes" : "no",
            proof.verified ? "yes" : "no"));
    }

    if (auto it = craftQueues.find(PChar->id); it != craftQueues.end() && it->second.active)
    {
        const auto& queue = it->second;
        rows.emplace_back(fmt::format(
            "Batch: {} index={}/{} started={} completed={} blocked={}",
            queue.paused ? "paused" : "active",
            queue.index,
            queue.recipeIds.size(),
            queue.started,
            queue.completed,
            queue.blocked.size()));
    }
    else
    {
        rows.emplace_back("Batch: inactive");
    }

    return nativeRows(state, rows);
}

auto nativeReport(sol::this_state state, CLuaBaseEntity* luaEntity) -> sol::table
{
    auto* PChar = getCharacter(luaEntity);
    if (PChar == nullptr)
    {
        return nativeRows(state, { "[FAIL] missing player" });
    }

    observeCraftCompletion(PChar);

    if (auto it = lastManualRecipeIds.find(PChar->id); it != lastManualRecipeIds.end())
    {
        if (const auto recipe = loadRecipe(it->second))
        {
            archiveRecipeResults(PChar, *recipe);
        }
    }

    std::vector<std::string> rows;
    if (auto proofIt = historyProofs.find(PChar->id); proofIt != historyProofs.end())
    {
        const auto& proof = proofIt->second;
        rows.emplace_back(fmt::format(
            "History proof recipe={} awaiting_native_first={} first_complete={} awaiting_lastsynth={} lastsynth_started={} verified={}",
            proof.recipeId,
            proof.awaitingNativeFirst ? "yes" : "no",
            proof.firstComplete ? "yes" : "no",
            proof.awaitingLastSynth ? "yes" : "no",
            proof.lastSynthStarted ? "yes" : "no",
            proof.verified ? "yes" : "no"));
    }
    uint32 saved            = 0;
    uint32 blockedRetailCap = 0;
    uint32 unsupported      = 0;
    uint32 craftableUnsaved = 0;
    uint32 target           = 0;

    for (const auto recipeId : getEndgameRecipeIds())
    {
        const auto recipe = loadRecipe(recipeId);
        if (!recipe)
        {
            continue;
        }

        ++target;
        const auto status = cookingCoverageStatus(PChar, *recipe);
        if (status == "saved")
        {
            ++saved;
        }
        else if (status.starts_with("blocked_retail_cap"))
        {
            ++blockedRetailCap;
        }
        else if (status.starts_with("unsupported"))
        {
            ++unsupported;
        }
        else
        {
            ++craftableUnsaved;
        }

        if (rows.size() < 8)
        {
            rows.emplace_back(fmt::format(
                "{} recipe={} cook={} result={}",
                status,
                recipe->id,
                recipe->cook,
                recipe->resultName));
        }
    }

    rows.insert(rows.begin(), fmt::format("Cooking report for {}: saved={} blocked_retail_cap={} craftable_unsaved={} unsupported={} total={}", PChar->getName(), saved, blockedRetailCap, craftableUnsaved, unsupported, target));
    if (rows.size() == 9 && target > 8)
    {
        rows.emplace_back("Use tools/mochirii/crafting/cooking_endgame_manifest.py for the full 111-target report.");
    }

    return nativeRows(state, rows);
}

void processQueue(CCharEntity* PChar, QueueState& queue)
{
    if (!queue.active || queue.paused || PChar == nullptr || PChar->isCrafting() || timer::now() < queue.nextAttempt)
    {
        return;
    }

    while (queue.index < queue.recipeIds.size())
    {
        const auto recipeId = queue.recipeIds[queue.index];
        const auto recipe   = loadRecipe(recipeId);
        if (!recipe)
        {
            queue.blocked[recipeId] = "recipe missing";
            logEvidence(PChar, nullptr, "batch_blocked", 0, 0, fmt::format("recipe {} missing", recipeId));
            ++queue.index;
            continue;
        }

        archiveRecipeResults(PChar, *recipe);

        if (recipeIsSaved(PChar, *recipe))
        {
            ++queue.completed;
            ++queue.index;
            continue;
        }

        if (queue.attempts[recipeId] >= queue.maxAttempts)
        {
            queue.blocked[recipeId] = "max attempts reached before all NQ/HQ results were saved";
            logEvidence(PChar, &*recipe, "batch_blocked", 0, queue.maxAttempts, queue.blocked[recipeId]);
            ++queue.index;
            continue;
        }

        std::string reason;
        if (!startRecipe(PChar, *recipe, reason, true, "batch"))
        {
            if (reason.starts_with("could not stage item"))
            {
                queue.paused = true;
                logEvidence(PChar, &*recipe, "batch_paused", 0, queue.attempts[recipeId], "paused on inventory staging failure: " + reason);
                ShowWarningFmt(
                    "Mochirii CraftQA: Cooking batch paused for {} at recipe {} ({}): {}",
                    PChar->getName(),
                    recipe->id,
                    recipe->resultName,
                    reason);
                return;
            }

            queue.blocked[recipeId] = reason;
            logEvidence(PChar, &*recipe, "batch_blocked", 0, queue.attempts[recipeId], reason);
            ++queue.index;
            continue;
        }

        ++queue.started;
        ++queue.attempts[recipeId];
        queue.nextAttempt = timer::now() + std::chrono::seconds(kQueueCraftIntervalSeconds);
        return;
    }

    queue.active = false;
    logEvidence(PChar, nullptr, "batch_complete", 0, queue.completed, fmt::format("started={} blocked={}", queue.started, queue.blocked.size()));
    ShowInfoFmt(
        "Mochirii CraftQA: Cooking batch complete for {}. completed={} started={} blocked={}",
        PChar->getName(),
        queue.completed,
        queue.started,
        queue.blocked.size());
}

} // namespace

class CraftQaModule : public CPPModule
{
public:
    void OnInit() override
    {
        auto xi      = lua["xi"].get_or_create<sol::table>();
        auto craftqa = xi["craftqa"].get_or_create<sol::table>();
        auto native  = craftqa["native"].get_or_create<sol::table>();

        native["repairCook"]   = nativeRepairCook;
        native["stageRecipe"]  = nativeStageRecipe;
        native["craftRecipe"]  = nativeCraftRecipe;
        native["historyProof"] = nativeHistoryProof;
        native["batchEndgame"] = nativeBatchEndgame;
        native["verbose"]      = nativeVerbose;
        native["pause"]        = nativePause;
        native["status"]       = nativeStatus;
        native["report"]       = nativeReport;
    }

    void OnZoneTick(CZone* PZone) override
    {
        if (PZone == nullptr)
        {
            return;
        }

        PZone->ForEachChar(
            [](CCharEntity* PChar)
            {
                if (PChar == nullptr)
                {
                    return;
                }

                observeNativeLastSynthStart(PChar);
                observeCraftCompletion(PChar);

                auto it = craftQueues.find(PChar->id);
                if (it == craftQueues.end())
                {
                    return;
                }

                processQueue(PChar, it->second);
            });
    }
};

REGISTER_CPP_MODULE(CraftQaModule);
