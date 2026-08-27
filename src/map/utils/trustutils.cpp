/*
===========================================================================

  Copyright (c) 2024 LandSandBoat Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see http://www.gnu.org/licenses/

===========================================================================
*/

#include "trustutils.h"

#include "common/earth_time.h"
#include "common/settings.h"
#include "common/utils.h"
#include "common/version.h"

#include <common/types/hash_map.h>

#include <algorithm>
#include <cctype>
#include <cstring>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <limits>
#include <sstream>
#include <vector>

#include "battleutils.h"
#include "mobutils.h"
#include "roe.h"
#include "zoneutils.h"

#include "alliance.h"
#include "grades.h"
#include "mob_spell_list.h"
#include "party.h"

#include "action/action.h"
#include "ai/ai_container.h"
#include "ai/controllers/trust_controller.h"
#include "ai/helpers/gambits_container.h"
#include "enmity_container.h"
#include "entities/char_entity.h"
#include "entities/mob_entity.h"
#include "entities/trust_entity.h"
#include "enums/action/category.h"
#include "enums/action/info.h"
#include "enums/action/resolution.h"
#include "items/item_weapon.h"
#include "mobskill.h"
#include "status_effect_container.h"
#include "weapon_skill.h"

//
// Forward declarations
//

void BuildTrustData(uint32 TrustID);
auto LoadTrust(CCharEntity* PMaster, uint32 TrustID) -> CTrustEntity*;
void LoadTrustStatsAndSkills(CTrustEntity* PTrust);

namespace
{

constexpr auto   TwillsCharacterName        = "Twills";
constexpr auto   TrustAllianceAccessVar     = "MochiriiTrustAllianceAccess";
constexpr auto   TrustSessionStateVar       = "MochiriiTrustSessionState";
constexpr auto   TrustEvidenceModeVar       = "MochiriiTrustEvidenceMode";
constexpr auto   TrustSessionGenerationVar  = "MochiriiTrustSessionGeneration";
constexpr auto   TrustSessionStartedVar     = "MochiriiTrustSessionStarted";
constexpr auto   TrustSessionZoneVar        = "MochiriiTrustSessionZone";
constexpr auto   TrustEvidenceSequenceVar   = "MochiriiTrustEvidenceSeq";
constexpr auto   TrustEvidenceSchemaVar     = "MochiriiTrustEvidenceSchema";
constexpr auto   TrustLogTruncatedVar       = "MochiriiTrustLogTruncated";
constexpr uint32 TrustEvidenceSchemaVersion = 2;

auto GetTwillsFullAllianceAccessContext(CCharEntity* PMaster) -> trustutils::TwillsFullAllianceAccessContext
{
    if (!PMaster)
    {
        return {};
    }

    return {
        .characterName  = PMaster->getName(),
        .actualGmLevel  = PMaster->m_GMlevel,
        .visibleGmLevel = PMaster->visibleGmLevel,
        .entitlement    = charutils::GetCharVar(PMaster, TrustAllianceAccessVar),
        .featureEnabled = settings::get<bool>("main.ENABLE_MOCHIRII_TWILLS_FULL_ALLIANCE"),
        .maxParties     = settings::get<uint8>("main.MOCHIRII_TWILLS_FULL_ALLIANCE_MAX_PARTIES"),
    };
}

auto GetTwillsTrustEvidenceMode(CCharEntity* PMaster) -> std::optional<trustutils::TwillsTrustEvidenceMode>
{
    if (!PMaster)
    {
        return std::nullopt;
    }

    const auto rawMode = PMaster->GetLocalVar(TrustEvidenceModeVar);
    if (rawMode > static_cast<uint32>(trustutils::TwillsTrustEvidenceMode::FullAllianceQualityAssurance))
    {
        return std::nullopt;
    }

    return static_cast<trustutils::TwillsTrustEvidenceMode>(rawMode);
}

auto HasSupportedTrustSessionPartyShape(CCharEntity* PMaster) -> bool
{
    if (!PMaster || !PMaster->PParty)
    {
        return PMaster != nullptr;
    }

    auto* PParty = PMaster->PParty;
    return PParty->m_PAlliance == nullptr &&
           PParty->members.size() == 1 &&
           PParty->members.front() == PMaster &&
           PParty->GetLeader() == PMaster;
}

} // namespace

auto trustutils::CanUseTwillsFullAlliance(const TwillsFullAllianceAccessContext& context) -> bool
{
    return context.featureEnabled &&
           context.maxParties == kFullAlliancePartyLimit &&
           context.characterName == TwillsCharacterName &&
           context.actualGmLevel == 5 &&
           context.visibleGmLevel == 0 &&
           context.entitlement == 1;
}

auto trustutils::CanUseTwillsFullAlliance(CCharEntity* PMaster) -> bool
{
    return PMaster && CanUseTwillsFullAlliance(GetTwillsFullAllianceAccessContext(PMaster));
}

auto trustutils::GetTwillsFullAllianceState(CCharEntity* PMaster) -> TwillsFullAllianceState
{
    if (!PMaster)
    {
        return TwillsFullAllianceState::Failed;
    }

    const auto rawState = PMaster->GetLocalVar(TrustSessionStateVar);
    if (rawState > static_cast<uint32>(TwillsFullAllianceState::Failed))
    {
        return TwillsFullAllianceState::Failed;
    }

    return static_cast<TwillsFullAllianceState>(rawState);
}

auto trustutils::IsTwillsFullAllianceActive(
    const TwillsFullAllianceAccessContext& context,
    TwillsFullAllianceState                state,
    TwillsTrustEvidenceMode                evidenceMode) -> bool
{
    return CanUseTwillsFullAlliance(context) &&
           evidenceMode == TwillsTrustEvidenceMode::FullAllianceQualityAssurance &&
           (state == TwillsFullAllianceState::Spawning || state == TwillsFullAllianceState::Ready);
}

auto trustutils::IsTwillsFullAllianceActive(CCharEntity* PMaster) -> bool
{
    const auto evidenceMode = GetTwillsTrustEvidenceMode(PMaster);
    return PMaster && evidenceMode &&
           IsTwillsFullAllianceActive(
               GetTwillsFullAllianceAccessContext(PMaster),
               GetTwillsFullAllianceState(PMaster),
               *evidenceMode);
}

auto trustutils::IsTwillsFullAllianceTransitionAllowed(TwillsFullAllianceState current, TwillsFullAllianceState next) -> bool
{
    // Returning to Idle is cleanup-safe from every state and makes `clear`
    // idempotent. Other same-state transitions are not lifecycle progress.
    if (next == TwillsFullAllianceState::Idle)
    {
        return true;
    }

    switch (current)
    {
        case TwillsFullAllianceState::Idle:
            return next == TwillsFullAllianceState::Spawning;
        case TwillsFullAllianceState::Spawning:
            return next == TwillsFullAllianceState::Ready || next == TwillsFullAllianceState::Failed;
        case TwillsFullAllianceState::Ready:
            return next == TwillsFullAllianceState::Failed;
        case TwillsFullAllianceState::Failed:
        default:
            return false;
    }
}

auto trustutils::SetTwillsFullAllianceState(CCharEntity* PMaster, TwillsFullAllianceState next) -> bool
{
    if (!PMaster || !IsTwillsFullAllianceTransitionAllowed(GetTwillsFullAllianceState(PMaster), next))
    {
        return false;
    }

    PMaster->SetLocalVar(TrustSessionStateVar, static_cast<uint32>(next));
    return true;
}

auto trustutils::MapTwillsFullAllianceSlot(std::size_t globalMemberIndex) -> std::optional<TrustPartySlot>
{
    if (globalMemberIndex >= kFullAllianceMemberLimit)
    {
        return std::nullopt;
    }

    return TrustPartySlot{
        .partyNo  = static_cast<uint8>(globalMemberIndex / kRetailPartyMemberLimit),
        .memberNo = static_cast<uint8>(globalMemberIndex % kRetailPartyMemberLimit),
    };
}

auto trustutils::ResolveTrustPartyProjection(
    const TwillsFullAllianceAccessContext& context,
    TwillsFullAllianceState                state,
    TwillsTrustEvidenceMode                evidenceMode,
    std::size_t                            globalMemberIndex) -> std::optional<TrustPartyProjection>
{
    if (IsTwillsFullAllianceActive(context, state, evidenceMode))
    {
        const auto slot = MapTwillsFullAllianceSlot(globalMemberIndex);
        if (!slot)
        {
            return std::nullopt;
        }

        return TrustPartyProjection{ .kind = PartyKind::Alliance, .slot = *slot };
    }

    const bool retailSession   = evidenceMode == TwillsTrustEvidenceMode::RetailControl &&
                                 CanUseTwillsFullAlliance(context) &&
                                 (state == TwillsFullAllianceState::Spawning || state == TwillsFullAllianceState::Ready);
    const bool ordinarySession = evidenceMode == TwillsTrustEvidenceMode::Idle && state == TwillsFullAllianceState::Idle;
    if ((!retailSession && !ordinarySession) || globalMemberIndex >= kRetailPartyMemberLimit)
    {
        return std::nullopt;
    }

    return TrustPartyProjection{
        .kind = PartyKind::Party,
        .slot = TrustPartySlot{ .partyNo = 0, .memberNo = static_cast<uint8>(globalMemberIndex) },
    };
}

auto trustutils::ResolveTrustPartyProjection(CCharEntity* PMaster, std::size_t globalMemberIndex) -> std::optional<TrustPartyProjection>
{
    const auto evidenceMode = GetTwillsTrustEvidenceMode(PMaster);
    if (!PMaster || !evidenceMode)
    {
        return std::nullopt;
    }

    if (*evidenceMode != TwillsTrustEvidenceMode::Idle && !HasSupportedTrustSessionPartyShape(PMaster))
    {
        return std::nullopt;
    }

    return ResolveTrustPartyProjection(
        GetTwillsFullAllianceAccessContext(PMaster),
        GetTwillsFullAllianceState(PMaster),
        *evidenceMode,
        globalMemberIndex);
}

auto trustutils::ResolveTrustMemberLimit(
    const TwillsFullAllianceAccessContext& context,
    TwillsFullAllianceState                state,
    TwillsTrustEvidenceMode                evidenceMode) -> std::optional<std::size_t>
{
    if (evidenceMode == TwillsTrustEvidenceMode::Idle && state == TwillsFullAllianceState::Idle)
    {
        return kRetailPartyMemberLimit;
    }

    if (state != TwillsFullAllianceState::Spawning || !CanUseTwillsFullAlliance(context))
    {
        return std::nullopt;
    }

    if (evidenceMode == TwillsTrustEvidenceMode::RetailControl)
    {
        return kRetailPartyMemberLimit;
    }

    if (evidenceMode == TwillsTrustEvidenceMode::FullAllianceQualityAssurance)
    {
        return kFullAllianceMemberLimit;
    }

    return std::nullopt;
}

auto trustutils::ResolveTrustMemberLimit(CCharEntity* PMaster) -> std::optional<std::size_t>
{
    const auto evidenceMode = GetTwillsTrustEvidenceMode(PMaster);
    if (!PMaster || !evidenceMode)
    {
        return std::nullopt;
    }

    if (*evidenceMode != TwillsTrustEvidenceMode::Idle && !HasSupportedTrustSessionPartyShape(PMaster))
    {
        return std::nullopt;
    }

    return ResolveTrustMemberLimit(
        GetTwillsFullAllianceAccessContext(PMaster),
        GetTwillsFullAllianceState(PMaster),
        *evidenceMode);
}

auto SafeLogValue(std::string value) -> std::string
{
    for (auto& ch : value)
    {
        if (ch == '\r' || ch == '\n' || ch == '\t')
        {
            ch = ' ';
        }
    }

    return value;
}

auto SafeLogName(const std::string& value) -> std::string
{
    auto safe = SafeLogValue(value);
    for (auto& ch : safe)
    {
        const auto byte = static_cast<unsigned char>(ch);
        if (!std::isalnum(byte) && ch != '_' && ch != '-' && ch != '.')
        {
            ch = '_';
        }
    }

    return safe.empty() ? "unknown" : safe;
}

struct TrustLogStamp
{
    int64       epoch{};
    std::string utc;
};

auto CurrentTrustLogStamp() -> TrustLogStamp
{
    const auto now   = earth_time::now();
    const auto epoch = std::chrono::duration_cast<std::chrono::seconds>(now.time_since_epoch()).count();
    const auto utc   = earth_time::to_utc_tm(now);
    char       buffer[32]{};
    std::strftime(buffer, sizeof(buffer), "%Y-%m-%dT%H:%M:%SZ", &utc);
    return { .epoch = epoch, .utc = buffer };
}

auto ActionCategoryName(ActionCategory category) -> const char*
{
    switch (category)
    {
        case ActionCategory::BasicAttack:
            return "BasicAttack";
        case ActionCategory::RangedFinish:
            return "RangedFinish";
        case ActionCategory::SkillFinish:
            return "SkillFinish";
        case ActionCategory::MagicFinish:
            return "MagicFinish";
        case ActionCategory::ItemFinish:
            return "ItemFinish";
        case ActionCategory::AbilityFinish:
            return "AbilityFinish";
        case ActionCategory::SkillStart:
            return "SkillStart";
        case ActionCategory::MagicStart:
            return "MagicStart";
        case ActionCategory::ItemStart:
            return "ItemStart";
        case ActionCategory::AbilityStart:
            return "AbilityStart";
        case ActionCategory::MobSkillFinish:
            return "MobSkillFinish";
        case ActionCategory::RangedStart:
            return "RangedStart";
        case ActionCategory::PetSkillFinish:
            return "PetSkillFinish";
        case ActionCategory::Dancer:
            return "Dancer";
        case ActionCategory::RuneFencer:
            return "RuneFencer";
        case ActionCategory::None:
        default:
            return "None";
    }
}

auto ActionResolutionName(ActionResolution resolution) -> const char*
{
    switch (resolution)
    {
        case ActionResolution::Hit:
            return "hit";
        case ActionResolution::Miss:
            return "miss";
        case ActionResolution::Guard:
            return "guard";
        case ActionResolution::Parry:
            return "parry";
        case ActionResolution::Block:
            return "block";
        default:
            return "unknown";
    }
}

auto MsgBasicName(MsgBasic messageId) -> const char*
{
    switch (static_cast<uint16>(messageId))
    {
        case 24:
            return "target_recovers_hp_simple";
        case 83:
            return "magic_remove_effect";
        case 103:
            return "uses_skill_recovers_hp";
        case 102:
            return "uses_recovers_hp";
        case 115:
            return "uses_ability_berserk_effect";
        case 117:
            return "uses_ability_defender_effect";
        case 119:
            return "uses_ability_provoke";
        case 159:
            return "skill_erase";
        case 194:
            return "uses_skill_effect_self";
        case 229:
            return "additional_effect_damage";
        case 231:
            return "disappear_num";
        case 268:
            return "target_receives_effect_song";
        case 271:
            return "uses_skill_effect";
        case 280:
            return "target_receives_effect_2";
        case 288:
            return "skillchain_light";
        case 289:
            return "skillchain_darkness";
        case 290:
            return "skillchain_gravitation";
        case 291:
            return "skillchain_fragmentation";
        case 292:
            return "skillchain_distortion";
        case 293:
            return "skillchain_fusion";
        case 294:
            return "skillchain_compression";
        case 295:
            return "skillchain_liquefaction";
        case 296:
            return "skillchain_induration";
        case 297:
            return "skillchain_reverberation";
        case 298:
            return "skillchain_transfixion";
        case 299:
            return "skillchain_scission";
        case 300:
            return "skillchain_detonation";
        case 301:
            return "skillchain_impaction";
        case 302:
            return "skillchain_radiance";
        case 303:
            return "skillchain_umbra";
        case 365:
            return "status_boost_2";
        case 341:
            return "magic_erase";
        case 385:
            return "skillchain_absorbed_light";
        case 386:
            return "skillchain_absorbed_darkness";
        case 387:
            return "skillchain_absorbed_gravitation";
        case 388:
            return "skillchain_absorbed_fragmentation";
        case 389:
            return "skillchain_absorbed_distortion";
        case 390:
            return "skillchain_absorbed_fusion";
        case 391:
            return "skillchain_absorbed_compression";
        case 392:
            return "skillchain_absorbed_liquefaction";
        case 393:
            return "skillchain_absorbed_induration";
        case 394:
            return "skillchain_absorbed_reverberation";
        case 395:
            return "skillchain_absorbed_transfixion";
        case 396:
            return "skillchain_absorbed_scission";
        case 397:
            return "skillchain_absorbed_detonation";
        case 398:
            return "skillchain_absorbed_impaction";
        case 399:
            return "skillchain_absorbed_radiance";
        case 400:
            return "skillchain_absorbed_umbra";
        case 762:
            return "monberaux_mix_samsons_strength_self";
        case 519:
            return "dancer_quickstep";
        case 520:
            return "dancer_box_step";
        case 522:
            return "violent_flourish_stun";
        case 524:
            return "no_finishing_moves";
        default:
            break;
    }

    switch (messageId)
    {
        case MsgBasic::None:
            return "none";
        case MsgBasic::AttackHits:
            return "attack_hits";
        case MsgBasic::AttackMisses:
            return "attack_misses";
        case MsgBasic::AttackCrit:
            return "attack_crit";
        case MsgBasic::StartsCastingSelf:
            return "starts_casting_self";
        case MsgBasic::MagicRecoversHP:
            return "magic_recovers_hp";
        case MsgBasic::TargetParries:
            return "target_parries";
        case MsgBasic::TargetDodges:
            return "target_dodges";
        case MsgBasic::ShadowAbsorb:
            return "shadow_absorb";
        case MsgBasic::CounterAbsByShadow:
            return "counter_absorbed_by_shadow";
        case MsgBasic::AttackCounteredDamage:
            return "attack_countered_damage";
        case MsgBasic::MagicDamage:
            return "magic_damage";
        case MsgBasic::MagicNoEffect:
            return "magic_no_effect";
        case MsgBasic::MagicResisted:
            return "magic_resisted";
        case MsgBasic::MagicDrainsHP:
            return "magic_drains_hp";
        case MsgBasic::MagicGainsEffect:
            return "magic_gains_effect";
        case MsgBasic::MagicStatus:
            return "magic_status";
        case MsgBasic::MagicReceivesEffect:
            return "magic_receives_effect";
        case MsgBasic::MagicBurstDamage:
            return "magic_burst_damage";
        case MsgBasic::UsesJobAbility:
            return "uses_job_ability";
        case MsgBasic::UsesJobAbility2:
            return "uses_job_ability_2";
        case MsgBasic::UsesJobAbilityTakeDamage:
            return "uses_job_ability_take_damage";
        case MsgBasic::UsesAbilityTakesDamage:
            return "uses_ability_takes_damage";
        case MsgBasic::UsesAbilityGainsEffect:
            return "uses_ability_gains_effect";
        case MsgBasic::UsesAbilityReceivesEffect:
            return "uses_ability_receives_effect";
        case MsgBasic::UsesAbilityNoEffect:
            return "uses_ability_no_effect";
        case MsgBasic::UsesAbilityDispel:
            return "uses_ability_dispel";
        case MsgBasic::AbilityMisses:
            return "ability_misses";
        case MsgBasic::UsesSkillTakesDamage:
            return "uses_skill_takes_damage";
        case MsgBasic::UsesSkillGainsEffect:
            return "uses_skill_gains_effect";
        case MsgBasic::UsesSkillHPDrained:
            return "uses_skill_hp_drained";
        case MsgBasic::UsesSkillMisses:
            return "uses_skill_misses";
        case MsgBasic::UsesSkillNoEffect:
            return "uses_skill_no_effect";
        case MsgBasic::UsesSkillRecoversMP:
            return "uses_skill_recovers_mp";
        case MsgBasic::UsesSkillRecoversHPAreaOfEffect:
            return "uses_skill_recovers_hp_aoe";
        case MsgBasic::UsesSkillStatus:
            return "uses_skill_status";
        case MsgBasic::UsesSkillReceivesEffect:
            return "uses_skill_receives_effect";
        case MsgBasic::UsesSkillTPReduced:
            return "uses_skill_tp_reduced";
        case MsgBasic::TargetTPReduced:
            return "target_tp_reduced";
        case MsgBasic::TargetRecoversHP:
            return "target_recovers_hp";
        case MsgBasic::TargetRecoversHP2:
            return "target_recovers_hp_2";
        case MsgBasic::TargetRecoversMP:
            return "target_recovers_mp";
        case MsgBasic::TargetTakesDamage:
            return "target_takes_damage";
        case MsgBasic::TargetGainsEffect:
            return "target_gains_effect";
        case MsgBasic::TargetReceivesEffectAbility:
            return "target_receives_effect_ability";
        case MsgBasic::TargetStatus:
            return "target_status";
        case MsgBasic::TargetReceivesEffect:
            return "target_receives_effect";
        case MsgBasic::TargetEffectDisappears:
            return "target_effect_disappears";
        case MsgBasic::TargetNoEffect:
            return "target_no_effect";
        case MsgBasic::ReadiesWeaponskill:
            return "readies_weaponskill";
        case MsgBasic::ReadiesSkill:
            return "readies_skill";
        case MsgBasic::RangedAttackHit:
            return "ranged_attack_hit";
        case MsgBasic::RangedAttackCrit:
            return "ranged_attack_crit";
        case MsgBasic::RangedAttackMiss:
            return "ranged_attack_miss";
        case MsgBasic::RangedAttackNoEffect:
            return "ranged_attack_no_effect";
        case MsgBasic::RangedAttackAbsorbs:
            return "ranged_attack_absorbs";
        case MsgBasic::RangedAttackSquarely:
            return "ranged_attack_squarely";
        case MsgBasic::RangedAttackPummels:
            return "ranged_attack_pummels";
        case MsgBasic::IsInterrupted:
            return "interrupted";
        case MsgBasic::IsParalyzed:
        case MsgBasic::IsParalyzed2:
            return "paralyzed";
        case MsgBasic::IsIntimidated:
            return "intimidated";
        case MsgBasic::RollMain:
            return "roll_main";
        case MsgBasic::ReceivesEffectAbility:
            return "receives_effect_ability";
        case MsgBasic::RollMainFail:
            return "roll_main_fail";
        case MsgBasic::RollSubFail:
            return "roll_sub_fail";
        case MsgBasic::DoubleUp:
            return "double_up";
        case MsgBasic::DoubleUpFail:
            return "double_up_fail";
        case MsgBasic::DoubleUpBust:
            return "double_up_bust";
        case MsgBasic::DoubleUpBustSub:
            return "double_up_bust_sub";
        case MsgBasic::SwordplayGain:
            return "swordplay_gain";
        case MsgBasic::VallationGain:
            return "vallation_gain";
        case MsgBasic::ValianceGainPartyMember:
            return "valiance_gain_party_member";
        case MsgBasic::TargetOutOfRange:
        case MsgBasic::OutOfRangeUnableCast:
        case MsgBasic::TooFarAway:
        case MsgBasic::TooFarAwayRed:
            return "out_of_range";
        default:
            return "msg_unknown";
    }
}

auto BoolLog(bool value) -> const char*
{
    return value ? "true" : "false";
}

auto EntityName(const CBaseEntity* PEntity) -> std::string
{
    return PEntity ? SafeLogValue(PEntity->getName()) : "none";
}

auto TargetTargId(uint32 entityId) -> uint16
{
    return static_cast<uint16>(entityId & 0xFFFF);
}

auto EntityDistance(const CBaseEntity* PSource, const CBaseEntity* PTarget) -> std::string
{
    if (!PSource || !PTarget)
    {
        return "nil";
    }

    return fmt::format("{:.2f}", distance(PSource->loc.p, PTarget->loc.p));
}

void AddEntityFields(std::ostringstream& line, const char* prefix, const CBaseEntity* PEntity)
{
    line << '\t' << prefix << "_name=" << EntityName(PEntity);
    line << '\t' << prefix << "_id=" << (PEntity ? PEntity->id : 0);
    line << '\t' << prefix << "_targid=" << (PEntity ? PEntity->targid : 0);
    line << '\t' << prefix << "_objtype=" << (PEntity ? static_cast<uint16>(PEntity->objtype) : 0);
    line << '\t' << prefix << "_x=" << (PEntity ? fmt::format("{:.3f}", PEntity->loc.p.x) : "nil");
    line << '\t' << prefix << "_y=" << (PEntity ? fmt::format("{:.3f}", PEntity->loc.p.y) : "nil");
    line << '\t' << prefix << "_z=" << (PEntity ? fmt::format("{:.3f}", PEntity->loc.p.z) : "nil");
    line << '\t' << prefix << "_rotation=" << (PEntity ? std::to_string(PEntity->loc.p.rotation) : "nil");

    if (const auto* PBattle = dynamic_cast<const CBattleEntity*>(PEntity))
    {
        line << '\t' << prefix << "_hp=" << PBattle->health.hp;
        line << '\t' << prefix << "_maxhp=" << PBattle->GetMaxHP();
        line << '\t' << prefix << "_hpp=" << static_cast<uint16>(PBattle->GetHPP());
        line << '\t' << prefix << "_mp=" << PBattle->health.mp;
        line << '\t' << prefix << "_maxmp=" << PBattle->GetMaxMP();
        line << '\t' << prefix << "_mpp=" << static_cast<uint16>(PBattle->GetMPP());
        line << '\t' << prefix << "_tp=" << PBattle->health.tp;
    }
}

void AddEnmityFields(std::ostringstream& line, CTrustEntity* PTrust, const CBattleEntity* PTarget)
{
    const auto* PMob = dynamic_cast<const CMobEntity*>(PTarget);
    if (!PTrust || !PMob || !PMob->PEnmityContainer)
    {
        line << "\tenmity_ce=nil\tenmity_ve=nil\tenmity_total=nil";
        return;
    }

    const auto ce = PMob->PEnmityContainer->GetCE(PTrust);
    const auto ve = PMob->PEnmityContainer->GetVE(PTrust);
    line << "\tenmity_ce=" << ce;
    line << "\tenmity_ve=" << ve;
    line << "\tenmity_total=" << (ce + ve);
}

struct TrustEvidenceSession
{
    trustutils::TwillsTrustEvidenceMode mode{};
    trustutils::TwillsFullAllianceState state{};
    uint32                              generation{};
    uint32                              startedAt{};
    uint16                              zone{};
    std::string                         sessionId;
    std::string                         serverCommit;
};

auto EvidenceModeName(trustutils::TwillsTrustEvidenceMode mode) -> const char*
{
    switch (mode)
    {
        case trustutils::TwillsTrustEvidenceMode::RetailControl:
            return "retail_control";
        case trustutils::TwillsTrustEvidenceMode::FullAllianceQualityAssurance:
            return "twills_full_alliance_qa";
        case trustutils::TwillsTrustEvidenceMode::Idle:
        default:
            return "idle";
    }
}

auto EvidenceTopologyName(trustutils::TwillsTrustEvidenceMode mode) -> const char*
{
    return mode == trustutils::TwillsTrustEvidenceMode::FullAllianceQualityAssurance ? "virtual_trust_alliance_5_6_6" : "retail_party_1_plus_5";
}

auto EvidenceStateName(trustutils::TwillsFullAllianceState state) -> const char*
{
    switch (state)
    {
        case trustutils::TwillsFullAllianceState::Spawning:
            return "spawning";
        case trustutils::TwillsFullAllianceState::Ready:
            return "ready";
        case trustutils::TwillsFullAllianceState::Failed:
            return "failed";
        case trustutils::TwillsFullAllianceState::Idle:
        default:
            return "idle";
    }
}

auto IsFullCommitIdentity(std::string_view commit) -> bool
{
    if (commit.size() != 40)
    {
        return false;
    }

    return std::ranges::all_of(commit, [](unsigned char ch)
                               {
                                   return std::isdigit(ch) || (ch >= 'a' && ch <= 'f');
                               });
}

auto GetTrustEvidenceSession(
    CCharEntity* PMaster,
    bool         requirePacketResults,
    bool         truncationMarkerContext = false) -> std::optional<TrustEvidenceSession>
{
    if (!PMaster || !settings::get<bool>("main.ENABLE_TRUST_ACTION_LOG") ||
        (requirePacketResults && !settings::get<bool>("main.TRUST_ACTION_LOG_PACKET_RESULTS")))
    {
        return std::nullopt;
    }

    const auto configuredOwner = settings::get<std::string>("main.TRUST_ACTION_LOG_PLAYER");
    const auto evidenceMode    = GetTwillsTrustEvidenceMode(PMaster);
    const auto state           = trustutils::GetTwillsFullAllianceState(PMaster);
    const auto generation      = PMaster->GetLocalVar(TrustSessionGenerationVar);
    const auto startedAt       = PMaster->GetLocalVar(TrustSessionStartedVar);
    const auto sessionZone     = PMaster->GetLocalVar(TrustSessionZoneVar);
    const auto evidenceSchema  = PMaster->GetLocalVar(TrustEvidenceSchemaVar);
    const auto logTruncated    = PMaster->GetLocalVar(TrustLogTruncatedVar);
    const auto serverCommit    = std::string(version::GetGitSha());

    const auto validActionState =
        state == trustutils::TwillsFullAllianceState::Spawning ||
        state == trustutils::TwillsFullAllianceState::Ready;
    const auto validMarkerState = truncationMarkerContext && state == trustutils::TwillsFullAllianceState::Failed;
    const auto validOwnerPolicy =
        truncationMarkerContext ? PMaster->getName() == TwillsCharacterName : configuredOwner == PMaster->getName() && trustutils::CanUseTwillsFullAlliance(PMaster);

    if (!validOwnerPolicy ||
        !evidenceMode ||
        (*evidenceMode != trustutils::TwillsTrustEvidenceMode::RetailControl &&
         *evidenceMode != trustutils::TwillsTrustEvidenceMode::FullAllianceQualityAssurance) ||
        (!validActionState && !validMarkerState) ||
        generation == 0 || startedAt == 0 || sessionZone != PMaster->getZone() ||
        evidenceSchema != TrustEvidenceSchemaVersion || (!truncationMarkerContext && logTruncated != 0) ||
        !IsFullCommitIdentity(serverCommit))
    {
        return std::nullopt;
    }

    const auto sessionId = fmt::format(
        "{}-{}-{}-{}",
        SafeLogName(PMaster->getName()),
        PMaster->id,
        startedAt,
        generation);

    return TrustEvidenceSession{
        .mode         = *evidenceMode,
        .state        = state,
        .generation   = generation,
        .startedAt    = startedAt,
        .zone         = static_cast<uint16>(sessionZone),
        .sessionId    = sessionId,
        .serverCommit = serverCommit,
    };
}

auto LogPathForOwner(const std::string& ownerName) -> std::optional<std::filesystem::path>
{
    auto            root = std::filesystem::path(settings::get<std::string>("main.TRUST_ACTION_LOG_DIR"));
    auto            live = root / "live";
    std::error_code error;
    std::filesystem::create_directories(live, error);
    if (error)
    {
        ShowWarningFmt("Mochirii TrustLog: failed to create {}: {}", live.string(), error.message());
        return std::nullopt;
    }

    return live / fmt::format("{}.log", SafeLogName(ownerName));
}

auto ArchivePathForSession(const std::string& sessionId) -> std::optional<std::filesystem::path>
{
    auto            root    = std::filesystem::path(settings::get<std::string>("main.TRUST_ACTION_LOG_DIR"));
    auto            archive = root / "archive";
    std::error_code error;
    std::filesystem::create_directories(archive, error);
    if (error)
    {
        ShowWarningFmt("Mochirii TrustLog: failed to create {}: {}", archive.string(), error.message());
        return std::nullopt;
    }

    return archive / fmt::format("{}.log", SafeLogName(sessionId));
}

auto WriteTrustLogLine(const std::filesystem::path& path, const std::string& line) -> bool
{
    std::ofstream file(path, std::ios::app);
    if (!file)
    {
        ShowWarningFmt("Mochirii TrustLog: failed to open {}", path.string());
        return false;
    }

    file << line << '\n';
    file.flush();
    if (!file)
    {
        ShowWarningFmt("Mochirii TrustLog: failed to write {}", path.string());
        return false;
    }

    return true;
}

auto WouldExceedTrustLogLimit(const std::filesystem::path& path, std::size_t lineBytes, uint32 maxBytes) -> bool
{
    if (maxBytes == 0)
    {
        return false;
    }

    std::error_code error;
    const auto      currentBytes = std::filesystem::exists(path, error) ? std::filesystem::file_size(path, error) : 0;
    return error || currentBytes + lineBytes + 1U > maxBytes;
}

void trustutils::MarkTrustEvidenceTruncated(CCharEntity* PMaster, std::string_view reason)
{
    if (!PMaster)
    {
        return;
    }

    // Capture the session even after the lifecycle pre-hook has transitioned
    // it to Failed, and even if Lua already set the fail-closed local. The
    // marker is deliberately allowed to exceed the logical session cap: its
    // bounded size makes a partial prefix durably unfit for acceptance.
    const auto session = GetTrustEvidenceSession(PMaster, false, true);
    PMaster->SetLocalVar(TrustLogTruncatedVar, 1);
    if (!session)
    {
        return;
    }

    const auto currentSequence = PMaster->GetLocalVar(TrustEvidenceSequenceVar);
    const auto markerSequence  = currentSequence == std::numeric_limits<uint32>::max() ? currentSequence : currentSequence + 1U;
    if (currentSequence != std::numeric_limits<uint32>::max())
    {
        PMaster->SetLocalVar(TrustEvidenceSequenceVar, markerSequence);
    }

    const auto         stamp      = CurrentTrustLogStamp();
    const auto         safeReason = SafeLogValue(std::string(reason.substr(0, 64)));
    std::ostringstream line;
    line << "schema_version=" << TrustEvidenceSchemaVersion;
    line << "\trecord_type=logger";
    line << "\tsession_id=" << session->sessionId;
    line << "\tserver_commit=" << session->serverCommit;
    line << "\tsequence=" << std::max<uint32>(1U, markerSequence);
    line << "\ttimestamp_epoch=" << stamp.epoch;
    line << "\ttimestamp_utc=" << stamp.utc;
    line << "\ttime=" << stamp.utc;
    line << "\towner=" << SafeLogValue(PMaster->getName());
    line << "\towner_id=" << PMaster->id;
    line << "\tevidence_mode=" << EvidenceModeName(session->mode);
    line << "\ttopology=" << EvidenceTopologyName(session->mode);
    line << "\tstate=" << EvidenceStateName(session->state);
    line << "\tgeneration=" << session->generation;
    line << "\tsession_started=" << session->startedAt;
    line << "\tzone=" << session->zone;
    line << "\ttrust_engage_type=" << charutils::GetCharVar(PMaster, "TrustEngageType");
    line << "\tevent=log_truncated";
    line << "\tlog_truncated=true";
    line << "\treason=" << (safeReason.empty() ? "unknown" : safeReason);

    const auto archivePath = ArchivePathForSession(session->sessionId);
    const auto livePath    = LogPathForOwner(PMaster->getName());
    const auto marker      = line.str();

    // Attempt each sink independently. Failure of one must never suppress the
    // invalidation marker in the other.
    const auto archiveWritten = archivePath && WriteTrustLogLine(*archivePath, marker);
    const auto liveWritten    = livePath && WriteTrustLogLine(*livePath, marker);
    if (!archiveWritten || !liveWritten)
    {
        ShowWarningFmt(
            "Mochirii TrustLog: truncation marker was not durable in every sink (archive={}, live={})",
            archiveWritten,
            liveWritten);
    }
}

auto AppendTrustLogLine(CCharEntity* PMaster, const TrustEvidenceSession& session, const std::string& line) -> bool
{
    const auto livePath    = LogPathForOwner(PMaster->getName());
    const auto archivePath = ArchivePathForSession(session.sessionId);
    const auto maxBytes    = settings::get<uint32>("main.TRUST_ACTION_LOG_MAX_BYTES_PER_SESSION");

    if (!livePath || !archivePath)
    {
        trustutils::MarkTrustEvidenceTruncated(PMaster, "log_path_unavailable");
        return false;
    }

    if (WouldExceedTrustLogLimit(*livePath, line.size(), maxBytes) ||
        WouldExceedTrustLogLimit(*archivePath, line.size(), maxBytes))
    {
        trustutils::MarkTrustEvidenceTruncated(PMaster, "session_size_limit");
        return false;
    }

    // Keep the per-session archive authoritative. Any partial dual-sink write
    // still marks the session truncated and permanently suppresses later C++
    // rows, while Lua retains the terminal session_end path for rejection.
    if (!WriteTrustLogLine(*archivePath, line))
    {
        trustutils::MarkTrustEvidenceTruncated(PMaster, "archive_write_failed");
        return false;
    }

    if (!WriteTrustLogLine(*livePath, line))
    {
        trustutils::MarkTrustEvidenceTruncated(PMaster, "live_write_failed");
        return false;
    }

    if (settings::get<bool>("main.TRUST_ACTION_LOG_MAP_ECHO"))
    {
        ShowInfoFmt("{}", line);
    }

    return true;
}

auto AddTrustEvidenceFields(std::ostringstream& line, CCharEntity* PMaster, const TrustEvidenceSession& session) -> bool
{
    const auto currentSequence = PMaster->GetLocalVar(TrustEvidenceSequenceVar);
    if (currentSequence == std::numeric_limits<uint32>::max())
    {
        trustutils::MarkTrustEvidenceTruncated(PMaster, "sequence_overflow");
        return false;
    }

    const auto nextSequence = currentSequence + 1U;
    PMaster->SetLocalVar(TrustEvidenceSequenceVar, nextSequence);

    const auto stamp = CurrentTrustLogStamp();
    line << "schema_version=" << TrustEvidenceSchemaVersion;
    line << "\trecord_type=combat";
    line << "\tsession_id=" << session.sessionId;
    line << "\tserver_commit=" << session.serverCommit;
    line << "\tsequence=" << nextSequence;
    line << "\ttimestamp_epoch=" << stamp.epoch;
    line << "\ttimestamp_utc=" << stamp.utc;
    line << "\ttime=" << stamp.utc;
    line << "\towner=" << SafeLogValue(PMaster->getName());
    line << "\towner_id=" << PMaster->id;
    line << "\tevidence_mode=" << EvidenceModeName(session.mode);
    line << "\ttopology=" << EvidenceTopologyName(session.mode);
    line << "\tstate=" << EvidenceStateName(session.state);
    line << "\tgeneration=" << session.generation;
    line << "\tsession_started=" << session.startedAt;
    line << "\tzone=" << session.zone;
    line << "\ttrust_engage_type=" << charutils::GetCharVar(PMaster, "TrustEngageType");
    line << "\tentitlement=" << charutils::GetCharVar(PMaster, TrustAllianceAccessVar);
    line << "\tactual_gm_level=" << static_cast<uint16>(PMaster->m_GMlevel);
    line << "\tvisible_gm_level=" << static_cast<uint16>(PMaster->visibleGmLevel);
    return true;
}

auto BuildTrustActionUid(CCharEntity* PMaster, const TrustEvidenceSession& session, CTrustEntity* PTrust) -> std::string
{
    return fmt::format(
        "{}-{}-{}",
        session.sessionId,
        PTrust ? PTrust->id : 0,
        static_cast<uint64>(PMaster->GetLocalVar(TrustEvidenceSequenceVar)) + 1U);
}

void LogTrustProgressionBonus(CTrustEntity* PTrust)
{
    auto*      PMaster = PTrust ? dynamic_cast<CCharEntity*>(PTrust->PMaster) : nullptr;
    const auto session = GetTrustEvidenceSession(PMaster, false);
    if (!session)
    {
        return;
    }

    std::ostringstream line;
    if (!AddTrustEvidenceFields(line, PMaster, *session))
    {
        return;
    }

    line << "\tevent=progression_bonus";
    line << "\ttrust=" << SafeLogValue(PTrust->getName());
    line << "\ttrust_id=" << PTrust->trustID();
    line << "\ttrust_entity_id=" << PTrust->id;
    line << "\ttrust_targid=" << PTrust->targid;
    line << "\ttrust_hp=" << PTrust->health.hp;
    line << "\ttrust_maxhp=" << PTrust->GetMaxHP();
    line << "\ttrust_hpp=" << static_cast<uint16>(PTrust->GetHPP());
    line << "\ttrust_mp=" << PTrust->health.mp;
    line << "\ttrust_maxmp=" << PTrust->GetMaxMP();
    line << "\ttrust_mpp=" << static_cast<uint16>(PTrust->GetMPP());
    line << "\ttrust_tp=" << PTrust->health.tp;
    line << "\taep_hp_rank=" << PTrust->GetLocalVar("MochiTrustAepHpRank");
    line << "\taep_mp_rank=" << PTrust->GetLocalVar("MochiTrustAepMpRank");
    line << "\taep_stat_rank=" << PTrust->GetLocalVar("MochiTrustAepStatRank");
    line << "\taep_combat_rank=" << PTrust->GetLocalVar("MochiTrustAepCombatRank");
    line << "\taep_magic_rank=" << PTrust->GetLocalVar("MochiTrustAepMagicRank");
    line << "\tunity_parity_rank=" << PTrust->GetLocalVar("MochiTrustUnityRank");
    line << "\tunity_parity_stat_bonus=" << PTrust->GetLocalVar("MochiTrustUnityStatBonus");
    AppendTrustLogLine(PMaster, *session, line.str());
}

auto AddTrustActionContext(
    std::ostringstream&         line,
    CTrustEntity*               PTrust,
    CCharEntity*                PMaster,
    const TrustEvidenceSession& session,
    const std::string&          actionUid,
    const action_t&             action,
    const CBattleEntity*        PPrimaryTarget,
    const char*                 source,
    const char*                 eventName,
    const char*                 decision,
    const char*                 rejectionReason,
    const char*                 outcome) -> bool
{
    auto* PBattleTarget = PTrust->GetBattleTarget();

    if (!AddTrustEvidenceFields(line, PMaster, session))
    {
        return false;
    }

    line << "\tevent=" << SafeLogValue(eventName ? eventName : "action_packet");
    line << "\taction_uid=" << SafeLogValue(actionUid);
    line << "\tdecision=" << SafeLogValue(decision ? decision : "unknown");
    line << "\trejection_reason=" << SafeLogValue(rejectionReason ? rejectionReason : "none");
    line << "\toutcome=" << SafeLogValue(outcome ? outcome : "unknown");
    line << "\ttrust=" << SafeLogValue(PTrust->getName());
    line << "\ttrust_id=" << PTrust->trustID();
    line << "\ttrust_entity_id=" << PTrust->id;
    line << "\ttrust_targid=" << PTrust->targid;
    line << "\ttrust_hp=" << PTrust->health.hp;
    line << "\ttrust_maxhp=" << PTrust->GetMaxHP();
    line << "\ttrust_hpp=" << static_cast<uint16>(PTrust->GetHPP());
    line << "\ttrust_mp=" << PTrust->health.mp;
    line << "\ttrust_maxmp=" << PTrust->GetMaxMP();
    line << "\ttrust_mpp=" << static_cast<uint16>(PTrust->GetMPP());
    line << "\ttrust_tp=" << PTrust->health.tp;
    line << "\taep_hp_rank=" << PTrust->GetLocalVar("MochiTrustAepHpRank");
    line << "\taep_mp_rank=" << PTrust->GetLocalVar("MochiTrustAepMpRank");
    line << "\taep_stat_rank=" << PTrust->GetLocalVar("MochiTrustAepStatRank");
    line << "\taep_combat_rank=" << PTrust->GetLocalVar("MochiTrustAepCombatRank");
    line << "\taep_magic_rank=" << PTrust->GetLocalVar("MochiTrustAepMagicRank");
    line << "\tunity_parity_rank=" << PTrust->GetLocalVar("MochiTrustUnityRank");
    line << "\tunity_parity_stat_bonus=" << PTrust->GetLocalVar("MochiTrustUnityStatBonus");
    line << "\tsource=" << SafeLogValue(source ? source : "unknown");
    line << "\taction_category=" << static_cast<uint16>(action.actiontype);
    line << "\taction_category_name=" << ActionCategoryName(action.actiontype);
    line << "\taction_id=" << action.actionid;
    line << "\taction_recast_ms=" << std::chrono::duration_cast<std::chrono::milliseconds>(action.recast).count();
    line << "\tspell_group=" << static_cast<uint16>(action.spellgroup);
    line << "\tfocus_target_targid=" << PTrust->GetLocalVar("MochiTrustFocusTargetTargId");
    line << "\tfocus_reason=" << PTrust->GetLocalVar("MochiTrustFocusReason");
    line << "\trole_enmity_action=" << PTrust->GetLocalVar("MochiTrustRoleEnmityAction");
    line << "\trole_enmity_target_targid=" << PTrust->GetLocalVar("MochiTrustRoleEnmityTargetTargId");
    line << "\tgambit_target=" << PTrust->GetLocalVar("MochiTrustGambitTargetSelector");
    line << "\tgambit_reaction=" << PTrust->GetLocalVar("MochiTrustGambitReaction");
    line << "\tgambit_select=" << PTrust->GetLocalVar("MochiTrustGambitSelect");
    line << "\tgambit_select_arg=" << PTrust->GetLocalVar("MochiTrustGambitSelectArg");
    line << "\tgambit_resolved_id=" << PTrust->GetLocalVar("MochiTrustGambitResolvedId");
    line << "\tgambit_target_targid=" << PTrust->GetLocalVar("MochiTrustGambitTargetTargId");
    line << "\tcurrent_battle_target_name=" << EntityName(PBattleTarget);
    line << "\tcurrent_battle_target_targid=" << (PBattleTarget ? PBattleTarget->targid : 0);
    line << "\tdistance_to_current_target=" << EntityDistance(PTrust, PBattleTarget);
    line << "\tdistance_to_primary_target=" << EntityDistance(PTrust, PPrimaryTarget);
    line << "\taction_range=" << EntityDistance(PTrust, PPrimaryTarget);
    line << "\tdistance_to_master=" << EntityDistance(PTrust, PMaster);
    AddEntityFields(line, "actor", PTrust);
    AddEntityFields(line, "master", PMaster);
    AddEntityFields(line, "current_target", PBattleTarget);
    AddEntityFields(line, "primary_target", PPrimaryTarget);
    return true;
}

auto ResultIsCritical(const action_result_t& result) -> bool
{
    return (static_cast<uint8>(result.info) & static_cast<uint8>(ActionInfo::CriticalHit)) != 0 ||
           result.messageID == MsgBasic::AttackCrit ||
           result.messageID == MsgBasic::RangedAttackCrit;
}

auto ResultIsDefeated(const action_result_t& result) -> bool
{
    return (static_cast<uint8>(result.info) & static_cast<uint8>(ActionInfo::Defeated)) != 0;
}

auto ResolvePacketTarget(CTrustEntity* PTrust, CCharEntity* PMaster, const CBattleEntity* PPrimaryTarget, uint32 targetId) -> const CBaseEntity*
{
    if (PPrimaryTarget && PPrimaryTarget->id == targetId)
    {
        return PPrimaryTarget;
    }

    if (targetId == 0 && PMaster)
    {
        return PMaster;
    }

    if (targetId < 0x1000)
    {
        if (PPrimaryTarget && PPrimaryTarget->targid == targetId)
        {
            return PPrimaryTarget;
        }

        return nullptr;
    }

    if (auto* PTarget = zoneutils::GetEntity(targetId))
    {
        return PTarget;
    }

    const auto targId = TargetTargId(targetId);
    if (PTrust && targId < 0x1000)
    {
        return PTrust->GetEntity(targId);
    }

    return nullptr;
}

void trustutils::LogTrustActionSkip(CBattleEntity* PActor, const CBattleEntity* PTarget, uint16 actionId, const char* source, const char* reason)
{
    auto* PTrust = dynamic_cast<CTrustEntity*>(PActor);
    if (!PTrust)
    {
        return;
    }

    auto*      PMaster = dynamic_cast<CCharEntity*>(PTrust->PMaster);
    const auto session = GetTrustEvidenceSession(PMaster, true);
    if (!session)
    {
        return;
    }

    auto* PBattleTarget = PTrust->GetBattleTarget();

    std::ostringstream line;
    const auto         actionUid = BuildTrustActionUid(PMaster, *session, PTrust);
    if (!AddTrustEvidenceFields(line, PMaster, *session))
    {
        return;
    }

    line << "\tevent=stale_target_skip";
    line << "\taction_uid=" << actionUid;
    line << "\tdecision=rejected";
    line << "\trejection_reason=" << SafeLogValue(reason ? reason : "unknown");
    line << "\toutcome=skipped";
    line << "\ttrust=" << SafeLogValue(PTrust->getName());
    line << "\ttrust_id=" << PTrust->trustID();
    line << "\ttrust_entity_id=" << PTrust->id;
    line << "\ttrust_targid=" << PTrust->targid;
    line << "\ttrust_hp=" << PTrust->health.hp;
    line << "\ttrust_maxhp=" << PTrust->GetMaxHP();
    line << "\ttrust_hpp=" << static_cast<uint16>(PTrust->GetHPP());
    line << "\ttrust_mp=" << PTrust->health.mp;
    line << "\ttrust_maxmp=" << PTrust->GetMaxMP();
    line << "\ttrust_mpp=" << static_cast<uint16>(PTrust->GetMPP());
    line << "\ttrust_tp=" << PTrust->health.tp;
    line << "\tsource=" << SafeLogValue(source ? source : "unknown");
    line << "\taction_category_name=MagicSkip";
    line << "\taction_category=0";
    line << "\taction_id=" << actionId;
    line << "\taction_recast_ms=nil";
    line << "\tskip_reason=" << SafeLogValue(reason ? reason : "unknown");
    line << "\tfocus_target_targid=" << PTrust->GetLocalVar("MochiTrustFocusTargetTargId");
    line << "\tfocus_reason=" << PTrust->GetLocalVar("MochiTrustFocusReason");
    line << "\tgambit_target=" << PTrust->GetLocalVar("MochiTrustGambitTargetSelector");
    line << "\tgambit_reaction=" << PTrust->GetLocalVar("MochiTrustGambitReaction");
    line << "\tgambit_select=" << PTrust->GetLocalVar("MochiTrustGambitSelect");
    line << "\tgambit_select_arg=" << PTrust->GetLocalVar("MochiTrustGambitSelectArg");
    line << "\tgambit_resolved_id=" << PTrust->GetLocalVar("MochiTrustGambitResolvedId");
    line << "\tgambit_target_targid=" << PTrust->GetLocalVar("MochiTrustGambitTargetTargId");
    line << "\tcurrent_battle_target_name=" << EntityName(PBattleTarget);
    line << "\tcurrent_battle_target_targid=" << (PBattleTarget ? PBattleTarget->targid : 0);
    line << "\tdistance_to_current_target=" << EntityDistance(PTrust, PBattleTarget);
    line << "\tdistance_to_packet_target=" << EntityDistance(PTrust, PTarget);
    line << "\taction_range=" << EntityDistance(PTrust, PTarget);
    AddEntityFields(line, "actor", PTrust);
    AddEntityFields(line, "master", PMaster);
    AddEntityFields(line, "current_target", PBattleTarget);
    AddEntityFields(line, "packet_target", PTarget);
    AddEnmityFields(line, PTrust, PTarget);

    AppendTrustLogLine(PMaster, *session, line.str());
}

void trustutils::LogTrustActionPacket(CBattleEntity* PActor, const action_t& action, const CBattleEntity* PPrimaryTarget, const char* source)
{
    auto* PTrust = dynamic_cast<CTrustEntity*>(PActor);
    if (!PTrust)
    {
        return;
    }

    auto*      PMaster = dynamic_cast<CCharEntity*>(PTrust->PMaster);
    const auto session = GetTrustEvidenceSession(PMaster, true);
    if (!session)
    {
        return;
    }

    const auto actionUid = BuildTrustActionUid(PMaster, *session, PTrust);

    uint32 resultCount = 0;
    int64  totalParam  = 0;
    for (const auto& actionTarget : action.targets)
    {
        resultCount += static_cast<uint32>(actionTarget.results.size());
        for (const auto& result : actionTarget.results)
        {
            totalParam += result.param;
        }
    }

    {
        std::ostringstream line;
        if (!AddTrustActionContext(
                line,
                PTrust,
                PMaster,
                *session,
                actionUid,
                action,
                PPrimaryTarget,
                source,
                "action_packet",
                "executed",
                "none",
                "packet_emitted"))
        {
            return;
        }

        line << "\tpacket_actor_id=" << action.actorId;
        line << "\ttarget_count=" << action.targets.size();
        line << "\tresult_count=" << resultCount;
        line << "\ttotal_param=" << totalParam;
        AddEnmityFields(line, PTrust, PPrimaryTarget);

        if (!AppendTrustLogLine(PMaster, *session, line.str()))
        {
            return;
        }
    }

    if (settings::get<std::string>("main.TRUST_ACTION_LOG_RESULT_DETAIL") != "full")
    {
        return;
    }

    uint32 targetIndex = 0;
    for (const auto& actionTarget : action.targets)
    {
        auto*       PPacketTarget          = dynamic_cast<const CBattleEntity*>(ResolvePacketTarget(PTrust, PMaster, PPrimaryTarget, actionTarget.actorId));
        const char* packetResolutionReason = PPacketTarget ? "entity" : "none";
        if (actionTarget.actorId == 0 && PMaster)
        {
            PPacketTarget          = PMaster;
            packetResolutionReason = "master_zero_id";
        }

        uint32 resultIndex = 0;
        for (const auto& result : actionTarget.results)
        {
            std::ostringstream line;
            if (!AddTrustActionContext(
                    line,
                    PTrust,
                    PMaster,
                    *session,
                    actionUid,
                    action,
                    PPacketTarget,
                    source,
                    "action_result",
                    "executed",
                    "none",
                    ActionResolutionName(result.resolution)))
            {
                return;
            }

            line << "\tpacket_actor_id=" << action.actorId;
            line << "\tpacket_raw_target_id=" << actionTarget.actorId;
            line << "\tpacket_raw_target_targid=" << TargetTargId(actionTarget.actorId);
            line << "\tpacket_target_resolution=" << packetResolutionReason;
            line << "\ttarget_index=" << targetIndex;
            line << "\tresult_index=" << resultIndex;
            line << "\tresult_resolution=" << static_cast<uint16>(result.resolution);
            line << "\tresult_resolution_name=" << ActionResolutionName(result.resolution);
            line << "\tresult_kind=" << static_cast<uint16>(result.kind);
            line << "\tresult_animation=" << static_cast<uint16>(result.animation);
            line << "\tresult_info=" << static_cast<uint16>(result.info);
            line << "\tresult_param=" << result.param;
            line << "\tmessage_id=" << static_cast<uint16>(result.messageID);
            line << "\tmessage_name=" << MsgBasicName(result.messageID);
            line << "\tis_critical=" << BoolLog(ResultIsCritical(result));
            line << "\tis_defeated=" << BoolLog(ResultIsDefeated(result));
            line << "\thas_additional_effect=" << BoolLog(result.hasAdditionalEffect());
            line << "\tadditional_effect_info=" << static_cast<uint16>(result.addEffectInfo);
            line << "\tadditional_effect_param=" << result.addEffectParam;
            line << "\tadditional_effect_message_id=" << static_cast<uint16>(result.addEffectMessage);
            line << "\tadditional_effect_message_name=" << MsgBasicName(result.addEffectMessage);
            line << "\tspikes_info=" << static_cast<uint16>(result.spikesInfo);
            line << "\tspikes_param=" << result.spikesParam;
            line << "\tspikes_message_id=" << static_cast<uint16>(result.spikesMessage);
            line << "\tspikes_message_name=" << MsgBasicName(result.spikesMessage);
            line << "\tdistance_to_packet_target=" << EntityDistance(PTrust, PPacketTarget);
            AddEntityFields(line, "packet_target", PPacketTarget);
            AddEnmityFields(line, PTrust, PPacketTarget);

            if (!AppendTrustLogLine(PMaster, *session, line.str()))
            {
                return;
            }
            ++resultIndex;
        }

        ++targetIndex;
    }
}

// List of trusts that are essentially walking GEO bubbles that should not be targetable
static std::unordered_set<SpellID> passiveTrustIDs = {
    SpellID::Sakura,
    SpellID::Moogle,
    SpellID::Star_Sibyl,
    SpellID::Kuyin_Hathdenna,
    SpellID::Brygid,
    SpellID::Kupofried,
    SpellID::Cornelia,
};

struct TrustData
{
    uint32        trustID{};
    bool          isPassiveTrust{};
    uint32        pool{};
    look_t        look;        // appearance data
    std::string   name;        // script name string
    std::string   packet_name; // packet name string
    xi::Ecosystem EcoSystem{}; // ecosystem

    uint8  name_prefix{};
    uint8  modelSize{ 0 };
    float  modelHitboxSize{ 0.0f };
    uint16 m_Species{};

    uint8 mJob{};
    uint8 sJob{};
    float HPscale{}; // HP boost percentage
    float MPscale{}; // MP boost percentage

    uint8  cmbSkill{};
    uint16 cmbDmgMult{};
    uint16 cmbDelay{};
    uint8  baseSpeed{};
    uint8  animationSpeed{};

    // stat ranks
    uint8 strRank{};
    uint8 dexRank{};
    uint8 vitRank{};
    uint8 agiRank{};
    uint8 intRank{};
    uint8 mndRank{};
    uint8 chrRank{};
    uint8 attRank{};
    uint8 defRank{};
    uint8 evaRank{};
    uint8 accRank{};

    uint16 m_MobSkillList{};

    // magic stuff
    uint16 spellList{};

    // resists
    int16 slash_sdt{};
    int16 pierce_sdt{};
    int16 hth_sdt{};
    int16 impact_sdt{};

    int16 magical_sdt{};

    int16 fire_sdt{};
    int16 ice_sdt{};
    int16 wind_sdt{};
    int16 earth_sdt{};
    int16 thunder_sdt{};
    int16 water_sdt{};
    int16 light_sdt{};
    int16 dark_sdt{};

    int8 fire_res_rank{};
    int8 ice_res_rank{};
    int8 wind_res_rank{};
    int8 earth_res_rank{};
    int8 thunder_res_rank{};
    int8 water_res_rank{};
    int8 light_res_rank{};
    int8 dark_res_rank{};

    int8 paralyze_res_rank{};
    int8 bind_res_rank{};
    int8 silence_res_rank{};
    int8 slow_res_rank{};
    int8 poison_res_rank{};
    int8 light_sleep_res_rank{};
    int8 dark_sleep_res_rank{};
    int8 blind_res_rank{};
    int8 stun_res_rank{};
    int8 gravity_res_rank{};
};

HashMap<uint16, std::unique_ptr<TrustData>> g_PTrustData;

auto ClampAlterEgoPointRank(int32 value) -> uint8
{
    return static_cast<uint8>(std::clamp(value, 0, 50));
}

auto GetAlterEgoPointRank(CCharEntity* PMaster, const std::string& varName) -> uint8
{
    if (!PMaster)
    {
        return 0;
    }

    // Alter Ego Point ranks are durable account-style progression for Trust
    // stat calculation. Read the persisted value directly so an online
    // character with an older char-var cache cannot summon unboosted Trusts
    // after an admin repair or DB-side bootstrap.
    return ClampAlterEgoPointRank(charutils::FetchCharVar(PMaster->id, varName).first);
}

template <typename T>
auto AddClamped(T value, uint32 bonus) -> T
{
    const auto widened = static_cast<uint32>(std::max<T>(value, 0)) + bonus;
    return static_cast<T>(std::min<uint32>(widened, static_cast<uint32>(std::numeric_limits<T>::max())));
}

void AddSkillRangeBonus(CTrustEntity* PTrust, int firstSkill, int lastSkill, uint8 bonus)
{
    if (!PTrust || bonus == 0)
    {
        return;
    }

    for (int skillId = firstSkill; skillId <= lastSkill; ++skillId)
    {
        PTrust->WorkingSkills.skill[skillId] = AddClamped(PTrust->WorkingSkills.skill[skillId], bonus);
    }
}

auto GetTrustUnityRank(CCharEntity* PMaster) -> uint8
{
    auto rank = settings::get<uint8>("main.TRUST_UNITY_PARITY_DEFAULT_RANK");

    if (PMaster && PMaster->profile.unity_leader > 0 && PMaster->profile.unity_leader <= 11)
    {
        const auto liveRank = roeutils::RoeSystem.unityLeaderRank[PMaster->profile.unity_leader - 1];
        if (liveRank > 0)
        {
            rank = liveRank;
        }
    }

    return static_cast<uint8>(std::clamp(rank, static_cast<uint8>(1), static_cast<uint8>(11)));
}

auto GetTrustUnityStatBonus(CCharEntity* PMaster) -> uint8
{
    if (!settings::get<bool>("main.ENABLE_TRUST_UNITY_RANK_STAT_PARITY") || !trustutils::IsTwillsFullAllianceActive(PMaster))
    {
        return 0;
    }

    const auto maxBonus = settings::get<uint8>("main.TRUST_UNITY_PARITY_MAX_STAT_BONUS");
    const auto rank     = GetTrustUnityRank(PMaster);

    return static_cast<uint8>(((12U - rank) * maxBonus) / 11U);
}

void ApplyTrustStatBonus(CTrustEntity* PTrust, uint8 bonus)
{
    if (!PTrust || bonus == 0)
    {
        return;
    }

    PTrust->stats.STR = AddClamped(PTrust->stats.STR, bonus);
    PTrust->stats.DEX = AddClamped(PTrust->stats.DEX, bonus);
    PTrust->stats.VIT = AddClamped(PTrust->stats.VIT, bonus);
    PTrust->stats.AGI = AddClamped(PTrust->stats.AGI, bonus);
    PTrust->stats.INT = AddClamped(PTrust->stats.INT, bonus);
    PTrust->stats.MND = AddClamped(PTrust->stats.MND, bonus);
    PTrust->stats.CHR = AddClamped(PTrust->stats.CHR, bonus);
}

void ApplyTrustAlterEgoPointVitals(CTrustEntity* PTrust)
{
    if (!PTrust || !settings::get<bool>("main.ENABLE_TRUST_ALTER_EGO_POINT_BONUSES"))
    {
        return;
    }

    auto* PMaster = dynamic_cast<CCharEntity*>(PTrust->PMaster);
    if (!PMaster)
    {
        return;
    }

    const auto hpRank  = GetAlterEgoPointRank(PMaster, "AlterEgoPoints_HP");
    const auto mpRank  = GetAlterEgoPointRank(PMaster, "AlterEgoPoints_MP");
    const auto hpBonus = hpRank * settings::get<uint8>("main.TRUST_ALTER_EGO_POINT_HP_PER_RANK");
    const auto mpBonus = mpRank * settings::get<uint8>("main.TRUST_ALTER_EGO_POINT_MP_PER_RANK");

    if (PTrust->GetLocalVar("MochiTrustAepVitalsApplied") == 0)
    {
        PTrust->addModifier(xi::Mod::HP, hpBonus);
        PTrust->addModifier(xi::Mod::MP, mpBonus);
        PTrust->SetLocalVar("MochiTrustAepVitalsApplied", 1);
    }

    PTrust->SetLocalVar("MochiTrustAepHpRank", hpRank);
    PTrust->SetLocalVar("MochiTrustAepMpRank", mpRank);
    PTrust->SetLocalVar("MochiTrustAepHpBonus", hpBonus);
    PTrust->SetLocalVar("MochiTrustAepMpBonus", mpBonus);
}

void ApplyTrustAlterEgoPointStats(CTrustEntity* PTrust)
{
    if (!PTrust || !settings::get<bool>("main.ENABLE_TRUST_ALTER_EGO_POINT_BONUSES"))
    {
        return;
    }

    auto* PMaster = dynamic_cast<CCharEntity*>(PTrust->PMaster);
    if (!PMaster)
    {
        return;
    }

    PTrust->stats.STR = AddClamped(PTrust->stats.STR, GetAlterEgoPointRank(PMaster, "AlterEgoPoints_STR"));
    PTrust->stats.DEX = AddClamped(PTrust->stats.DEX, GetAlterEgoPointRank(PMaster, "AlterEgoPoints_DEX"));
    PTrust->stats.VIT = AddClamped(PTrust->stats.VIT, GetAlterEgoPointRank(PMaster, "AlterEgoPoints_VIT"));
    PTrust->stats.AGI = AddClamped(PTrust->stats.AGI, GetAlterEgoPointRank(PMaster, "AlterEgoPoints_AGI"));
    PTrust->stats.INT = AddClamped(PTrust->stats.INT, GetAlterEgoPointRank(PMaster, "AlterEgoPoints_INT"));
    PTrust->stats.MND = AddClamped(PTrust->stats.MND, GetAlterEgoPointRank(PMaster, "AlterEgoPoints_MND"));
    PTrust->stats.CHR = AddClamped(PTrust->stats.CHR, GetAlterEgoPointRank(PMaster, "AlterEgoPoints_CHR"));

    PTrust->SetLocalVar("MochiTrustAepStatRank", GetAlterEgoPointRank(PMaster, "AlterEgoPoints_STR"));
}

void ApplyTrustAlterEgoPointSkills(CTrustEntity* PTrust)
{
    if (!PTrust || !settings::get<bool>("main.ENABLE_TRUST_ALTER_EGO_POINT_BONUSES"))
    {
        return;
    }

    auto* PMaster = dynamic_cast<CCharEntity*>(PTrust->PMaster);
    if (!PMaster)
    {
        return;
    }

    const auto combatBonus = GetAlterEgoPointRank(PMaster, "AlterEgoPoints_CombatSkills");
    const auto magicBonus  = GetAlterEgoPointRank(PMaster, "AlterEgoPoints_MagicSkills");

    AddSkillRangeBonus(
        PTrust,
        static_cast<int>(xi::SkillType::HandToHand),
        static_cast<int>(xi::SkillType::Staff),
        combatBonus);
    AddSkillRangeBonus(
        PTrust,
        static_cast<int>(xi::SkillType::DivineMagic),
        static_cast<int>(xi::SkillType::BlueMagic),
        magicBonus);

    PTrust->SetLocalVar("MochiTrustAepCombatRank", combatBonus);
    PTrust->SetLocalVar("MochiTrustAepMagicRank", magicBonus);
}

void ApplyTrustUnityRankParity(CTrustEntity* PTrust)
{
    if (!PTrust)
    {
        return;
    }

    auto*      PMaster = dynamic_cast<CCharEntity*>(PTrust->PMaster);
    const auto rank    = GetTrustUnityRank(PMaster);
    const auto bonus   = GetTrustUnityStatBonus(PMaster);

    ApplyTrustStatBonus(PTrust, bonus);

    PTrust->SetLocalVar("MochiTrustUnityRank", rank);
    PTrust->SetLocalVar("MochiTrustUnityStatBonus", bonus);
}

void ApplyTrustMasterProgressionBonuses(CTrustEntity* PTrust)
{
    if (!PTrust)
    {
        return;
    }

    ApplyTrustAlterEgoPointVitals(PTrust);
    ApplyTrustAlterEgoPointStats(PTrust);
    ApplyTrustUnityRankParity(PTrust);
    ApplyTrustAlterEgoPointSkills(PTrust);

    PTrust->UpdateHealth();
    if (PTrust->GetLocalVar("MochiTrustAepVitalsEffectiveApplied") == 0)
    {
        PTrust->health.modhp = AddClamped(PTrust->health.modhp, static_cast<uint32>(PTrust->GetLocalVar("MochiTrustAepHpBonus")));
        PTrust->health.modmp = AddClamped(PTrust->health.modmp, static_cast<uint32>(PTrust->GetLocalVar("MochiTrustAepMpBonus")));
        PTrust->SetLocalVar("MochiTrustAepVitalsEffectiveApplied", 1);
    }

    PTrust->health.hp = PTrust->GetMaxHP();
    PTrust->health.mp = PTrust->GetMaxMP();
    PTrust->updatemask |= UPDATE_HP;

    LogTrustProgressionBonus(PTrust);
}

void trustutils::LoadTrustList()
{
    const auto rset = db::preparedStmt("SELECT "
                                       "spell_list.spellid, mob_pools.poolid "
                                       "FROM spell_list, mob_pools "
                                       "WHERE spell_list.spellid >= 896 AND mob_pools.poolid = (spell_list.spellid + 5000) ORDER BY spell_list.spellid");

    if (rset && rset->rowsCount())
    {
        while (rset->next())
        {
            const auto trustSpellId = rset->get<uint32>(0);
            BuildTrustData(trustSpellId);
        }
    }
}

auto trustutils::SpawnTrust(CCharEntity* PMaster, uint32 TrustID) -> CTrustEntity*
{
    if (!PMaster)
    {
        ShowWarning("trustutils::SpawnTrust - Master was null.");
        return nullptr;
    }

    const auto memberLimit = ResolveTrustMemberLimit(PMaster);
    if (!memberLimit)
    {
        ShowWarningFmt("trustutils::SpawnTrust - Rejected Trust {} for {} because the session policy is not spawnable.", TrustID, PMaster->getName());
        return nullptr;
    }

    if (PMaster->PParty && PMaster->PParty->m_PAlliance)
    {
        ShowWarningFmt("trustutils::SpawnTrust - Rejected Trust {} for {} because a real alliance is active.", TrustID, PMaster->getName());
        return nullptr;
    }

    const auto duplicate = std::ranges::find_if(PMaster->PTrusts, [TrustID](CTrustEntity* PTrust)
                                                {
                                                    return PTrust && PTrust->trustID() == TrustID;
                                                });
    if (duplicate != PMaster->PTrusts.end())
    {
        ShowWarningFmt("trustutils::SpawnTrust - Rejected duplicate Trust {} for {}.", TrustID, PMaster->getName());
        return nullptr;
    }

    const auto realMemberCount = PMaster->PParty ? PMaster->PParty->members.size() : 1U;
    if (realMemberCount + PMaster->PTrusts.size() >= *memberLimit)
    {
        ShowWarningFmt(
            "trustutils::SpawnTrust - Rejected Trust {} for {} at the {}-member hard cap.",
            TrustID,
            PMaster->getName(),
            *memberLimit);
        return nullptr;
    }

    CTrustEntity* PTrust = LoadTrust(PMaster, TrustID);
    if (PTrust == nullptr)
    {
        return nullptr;
    }

    if (PMaster->PParty == nullptr)
    {
        PMaster->PParty = new CParty(PMaster);
    }

    PMaster->PTrusts.insert(PMaster->PTrusts.end(), PTrust);
    PMaster->StatusEffectContainer->CopyConfrontationEffect(PTrust);
    PTrust->setBattleID(PMaster->getBattleID());

    if (PMaster->PBattlefield)
    {
        PTrust->PBattlefield = PMaster->PBattlefield;
    }

    if (PMaster->PInstance)
    {
        PTrust->PInstance = PMaster->PInstance;
    }

    PMaster->loc.zone->InsertTRUST(PTrust);
    PTrust->Spawn();
    ApplyTrustMasterProgressionBonuses(PTrust);

    PMaster->PParty->ReloadParty();

    return PTrust;
}

void BuildTrustData(uint32 TrustID)
{
    const auto rset = db::preparedStmt("SELECT "
                                       "mob_pools.poolid, "
                                       "mob_pools.name, "
                                       "mob_pools.packet_name, "
                                       "mob_pools.modelid, "
                                       "mob_pools.speciesid, "
                                       "mob_pools.mJob, "
                                       "mob_pools.sJob, "
                                       "mob_pools.spellList, "
                                       "mob_pools.cmbSkill, "
                                       "mob_pools.cmbDelay, "
                                       "mob_pools.cmbDmgMult, "
                                       "mob_pools.name_prefix, "
                                       "mob_pools.skill_list_id, "
                                       "mob_pools.modelSize, "
                                       "mob_pools.modelHitboxSize, "
                                       "spell_list.spellid, "
                                       "mob_species_system.ecosystemID, "
                                       "(mob_species_system.HP / 100) AS HP, "
                                       "(mob_species_system.MP / 100) AS MP, "
                                       "mob_species_system.speed, "
                                       "mob_species_system.STR, "
                                       "mob_species_system.DEX, "
                                       "mob_species_system.VIT, "
                                       "mob_species_system.AGI, "
                                       "mob_species_system.INT, "
                                       "mob_species_system.MND, "
                                       "mob_species_system.CHR, "
                                       "mob_species_system.DEF, "
                                       "mob_species_system.ATT, "
                                       "mob_species_system.ACC, "
                                       "mob_species_system.EVA, "
                                       "mob_resistances.slash_sdt, mob_resistances.pierce_sdt, "
                                       "mob_resistances.h2h_sdt, mob_resistances.impact_sdt, "
                                       "mob_resistances.magical_sdt, "
                                       "mob_resistances.fire_sdt, mob_resistances.ice_sdt, "
                                       "mob_resistances.wind_sdt, mob_resistances.earth_sdt, "
                                       "mob_resistances.lightning_sdt, mob_resistances.water_sdt, "
                                       "mob_resistances.light_sdt, mob_resistances.dark_sdt, "
                                       "mob_resistances.fire_res_rank, mob_resistances.ice_res_rank, "
                                       "mob_resistances.wind_res_rank, mob_resistances.earth_res_rank, "
                                       "mob_resistances.lightning_res_rank, mob_resistances.water_res_rank, "
                                       "mob_resistances.light_res_rank, mob_resistances.dark_res_rank, "
                                       "mob_resistances.paralyze_res_rank, mob_resistances.bind_res_rank, "
                                       "mob_resistances.silence_res_rank, mob_resistances.slow_res_rank, "
                                       "mob_resistances.poison_res_rank, mob_resistances.light_sleep_res_rank, "
                                       "mob_resistances.dark_sleep_res_rank, mob_resistances.blind_res_rank, "
                                       "mob_resistances.stun_res_rank, mob_resistances.gravity_res_rank "
                                       "FROM spell_list, mob_pools, mob_species_system, mob_resistances "
                                       "WHERE spell_list.spellid = ? "
                                       "AND (spell_list.spellid + 5000) = mob_pools.poolid "
                                       "AND mob_pools.resist_id = mob_resistances.resist_id "
                                       "AND mob_pools.speciesid = mob_species_system.speciesID "
                                       "ORDER BY spell_list.spellid",
                                       TrustID);

    if (rset && rset->rowsCount())
    {
        while (rset->next())
        {
            auto data = std::make_unique<TrustData>();

            data->trustID = TrustID;

            if (passiveTrustIDs.contains(static_cast<SpellID>(data->trustID)))
            {
                data->isPassiveTrust = true;
            }

            data->pool        = rset->get<uint32>("poolid");
            data->name        = rset->get<std::string>("name");
            data->packet_name = rset->get<std::string>("packet_name");

            db::extractFromBlob(rset, "modelid", data->look);

            data->m_Species = rset->get<uint16>("speciesid");
            data->mJob      = rset->get<uint8>("mJob");
            data->sJob      = rset->get<uint8>("sJob");
            data->spellList = rset->get<uint16>("spellList");

            data->cmbSkill   = rset->get<uint8>("cmbSkill");
            data->cmbDelay   = rset->get<uint16>("cmbDelay");
            data->cmbDmgMult = rset->get<uint16>("cmbDmgMult");

            data->name_prefix    = rset->get<uint8>("name_prefix");
            data->m_MobSkillList = rset->get<uint16>("skill_list_id");

            data->modelSize       = rset->getOrDefault<uint8>("modelSize", 0);
            data->modelHitboxSize = std::max<float>(0.0f, rset->getOrDefault<float>("modelHitboxSize", 0) / 10.f);
            data->EcoSystem       = rset->get<xi::Ecosystem>("ecosystemID");
            data->HPscale         = rset->get<float>("HP");
            data->MPscale         = rset->get<float>("MP");

            data->baseSpeed      = 62;
            data->animationSpeed = 50;

            data->strRank = rset->get<uint8>("STR");
            data->dexRank = rset->get<uint8>("DEX");
            data->vitRank = rset->get<uint8>("VIT");
            data->agiRank = rset->get<uint8>("AGI");
            data->intRank = rset->get<uint8>("INT");
            data->mndRank = rset->get<uint8>("MND");
            data->chrRank = rset->get<uint8>("CHR");
            data->defRank = rset->get<uint8>("DEF");
            data->attRank = rset->get<uint8>("ATT");
            data->accRank = rset->get<uint8>("ACC");
            data->evaRank = rset->get<uint8>("EVA");

            // resistances
            data->slash_sdt  = rset->get<int16>("slash_sdt");
            data->pierce_sdt = rset->get<int16>("pierce_sdt");
            data->hth_sdt    = rset->get<int16>("h2h_sdt");
            data->impact_sdt = rset->get<int16>("impact_sdt");

            data->magical_sdt = rset->get<int16>("magical_sdt"); // Modifier 389, base 10000 stored as signed integer. Positives signify less damage.

            data->fire_sdt    = rset->get<int16>("fire_sdt");      // Modifier 54, base 10000 stored as signed integer. Positives signify less damage.
            data->ice_sdt     = rset->get<int16>("ice_sdt");       // Modifier 55, base 10000 stored as signed integer. Positives signify less damage.
            data->wind_sdt    = rset->get<int16>("wind_sdt");      // Modifier 56, base 10000 stored as signed integer. Positives signify less damage.
            data->earth_sdt   = rset->get<int16>("earth_sdt");     // Modifier 57, base 10000 stored as signed integer. Positives signify less damage.
            data->thunder_sdt = rset->get<int16>("lightning_sdt"); // Modifier 58, base 10000 stored as signed integer. Positives signify less damage.
            data->water_sdt   = rset->get<int16>("water_sdt");     // Modifier 59, base 10000 stored as signed integer. Positives signify less damage.
            data->light_sdt   = rset->get<int16>("light_sdt");     // Modifier 60, base 10000 stored as signed integer. Positives signify less damage.
            data->dark_sdt    = rset->get<int16>("dark_sdt");      // Modifier 61, base 10000 stored as signed integer. Positives signify less damage.

            data->fire_res_rank    = rset->get<int8>("fire_res_rank");
            data->ice_res_rank     = rset->get<int8>("ice_res_rank");
            data->wind_res_rank    = rset->get<int8>("wind_res_rank");
            data->earth_res_rank   = rset->get<int8>("earth_res_rank");
            data->thunder_res_rank = rset->get<int8>("lightning_res_rank");
            data->water_res_rank   = rset->get<int8>("water_res_rank");
            data->light_res_rank   = rset->get<int8>("light_res_rank");
            data->dark_res_rank    = rset->get<int8>("dark_res_rank");

            data->paralyze_res_rank    = rset->get<int8>("paralyze_res_rank");
            data->bind_res_rank        = rset->get<int8>("bind_res_rank");
            data->silence_res_rank     = rset->get<int8>("silence_res_rank");
            data->slow_res_rank        = rset->get<int8>("slow_res_rank");
            data->poison_res_rank      = rset->get<int8>("poison_res_rank");
            data->light_sleep_res_rank = rset->get<int8>("light_sleep_res_rank");
            data->dark_sleep_res_rank  = rset->get<int8>("dark_sleep_res_rank");
            data->blind_res_rank       = rset->get<int8>("blind_res_rank");
            data->stun_res_rank        = rset->get<int8>("stun_res_rank");
            data->gravity_res_rank     = rset->get<int8>("gravity_res_rank");

            g_PTrustData[TrustID] = std::move(data);
        }
    }
}

auto LoadTrust(CCharEntity* PMaster, uint32 TrustID) -> CTrustEntity*
{
    const auto itr = g_PTrustData.find(TrustID);
    if (itr == g_PTrustData.end())
    {
        ShowError(fmt::format("Could not look up trust data for id: {}", TrustID));
        return nullptr;
    }

    auto* trustData = itr->second.get();

    auto* PTrust = new CTrustEntity(PMaster, trustData->trustID, IsPassiveTrust{ trustData->isPassiveTrust });

    PTrust->loc              = PMaster->loc;
    PTrust->m_OwnerID.id     = PMaster->id;
    PTrust->m_OwnerID.targid = PMaster->targid;

    // spawn me randomly around master
    PTrust->loc.p = nearPosition(PMaster->loc.p, CTrustController::SpawnDistance + (PMaster->PTrusts.size() * CTrustController::SpawnDistance), (float)M_PI);
    PTrust->look  = trustData->look;
    PTrust->name  = trustData->name;

    PTrust->m_Pool         = trustData->pool;
    PTrust->packetName     = trustData->packet_name;
    PTrust->m_name_prefix  = trustData->name_prefix;
    PTrust->m_Species      = trustData->m_Species;
    PTrust->m_MobSkillList = trustData->m_MobSkillList;
    PTrust->HPscale        = trustData->HPscale;
    PTrust->MPscale        = trustData->MPscale;
    PTrust->baseSpeed      = trustData->baseSpeed;
    PTrust->animationSpeed = trustData->animationSpeed;

    PTrust->UpdateSpeed();

    PTrust->status          = xi::Status::Normal;
    PTrust->modelSize       = trustData->modelSize;
    PTrust->modelHitboxSize = trustData->modelHitboxSize;
    PTrust->m_EcoSystem     = trustData->EcoSystem;

    PTrust->SetMJob(trustData->mJob);
    PTrust->SetSJob(trustData->sJob);

    // assume level matches master
    PTrust->SetMLevel(PMaster->GetMLevel());
    PTrust->SetSLevel(std::floor(PMaster->GetMLevel() / 2));

    LoadTrustStatsAndSkills(PTrust);

    // Use Mob formulas to work out base "weapon" damage, but scale down to reasonable values.
    // TODO: Verify trust base damage.
    const float  mobStyleDamage   = static_cast<float>(mobutils::GetBaseWeaponDamage(PTrust, SLOT_MAIN));
    const float  baseDamage       = mobStyleDamage * 0.5f;
    const float  damageMultiplier = static_cast<float>(trustData->cmbDmgMult) / 100.0f;
    const float  adjustedDamage   = baseDamage * damageMultiplier;
    const uint16 finalDamage      = static_cast<uint16>(std::max(adjustedDamage, 1.0f));

    // Trust do not really have weapons, but they are modelled internally as
    // if they do.
    if (auto* mainWeapon = dynamic_cast<CItemWeapon*>(PTrust->m_Weapons[SLOT_MAIN]))
    {
        mainWeapon->setMaxHit(1);
        mainWeapon->setSkillType(static_cast<xi::SkillType>(trustData->cmbSkill));

        mainWeapon->setDamage(finalDamage);
        mainWeapon->setDelay(trustData->cmbDelay);
        mainWeapon->setBaseDelay(trustData->cmbDelay);

        // Compute DPS so rune/enchantment calculations that rely on getDPS() return meaningful values for trusts.
        // Use damage per second: damage / (delay_seconds). Delay is stored in ms.
        if (mainWeapon->getDelay() > 0)
        {
            double dps = static_cast<double>(mainWeapon->getDamage()) / (static_cast<double>(mainWeapon->getDelay()) / 1000.0);
            mainWeapon->setDPS(dps);
        }
    }

    if (auto* subWeapon = dynamic_cast<CItemWeapon*>(PTrust->m_Weapons[SLOT_SUB]))
    {
        subWeapon->setDamage(finalDamage);
        subWeapon->setDelay(trustData->cmbDelay);
        subWeapon->setBaseDelay(trustData->cmbDelay);

        if (subWeapon->getDelay() > 0)
        {
            double dps = static_cast<double>(subWeapon->getDamage()) / (static_cast<double>(subWeapon->getDelay()) / 1000.0);
            subWeapon->setDPS(dps);
        }
    }

    if (auto* rangedWeapon = dynamic_cast<CItemWeapon*>(PTrust->m_Weapons[SLOT_RANGED]))
    {
        rangedWeapon->setDamage(finalDamage);
        rangedWeapon->setDelay(trustData->cmbDelay);
        rangedWeapon->setBaseDelay(trustData->cmbDelay);

        if (rangedWeapon->getDelay() > 0)
        {
            double dps = static_cast<double>(rangedWeapon->getDamage()) / (static_cast<double>(rangedWeapon->getDelay()) / 1000.0);
            rangedWeapon->setDPS(dps);
        }
    }

    if (auto* ammoWeapon = dynamic_cast<CItemWeapon*>(PTrust->m_Weapons[SLOT_AMMO]))
    {
        ammoWeapon->setDamage(finalDamage);
        ammoWeapon->setDelay(trustData->cmbDelay);
        ammoWeapon->setBaseDelay(trustData->cmbDelay);

        if (ammoWeapon->getDelay() > 0)
        {
            double dps = static_cast<double>(ammoWeapon->getDamage()) / (static_cast<double>(ammoWeapon->getDelay()) / 1000.0);
            ammoWeapon->setDPS(dps);
        }
    }

    // NOTE: Trusts don't really have weapons, and they don't really have combat skills. They only have
    // a damage type, and whether or not they are multi-hit. We handle this wrong everywhere.
    // To give any Trust multi-hit, you need to give them cmbSkill == xi::SkillType::HandToHand (1).
    if (trustData->cmbSkill == static_cast<uint8>(xi::SkillType::HandToHand))
    {
        PTrust->m_dualWield = true;
    }

    if (auto* spellList = mobSpellList::GetMobSpellList(trustData->spellList); spellList != nullptr)
    {
        mobutils::SetSpellList(PTrust, trustData->spellList);
    }

    return PTrust;
}

void LoadTrustStatsAndSkills(CTrustEntity* PTrust)
{
    auto* PMaster = dynamic_cast<CCharEntity*>(PTrust->PMaster);
    // Keep the optional Expo stat campaign inside the explicit QA extension;
    // retail-control and ordinary Trusts retain upstream stats.
    if (settings::get<uint8>("main.ENABLE_TRUST_ALTER_EGO_EXPO") > 0 &&
        trustutils::IsTwillsFullAllianceActive(PMaster))
    {
        PTrust->addModifier(xi::Mod::HPP, 50);
        PTrust->addModifier(xi::Mod::MPP, 50);
        PTrust->addModifier(xi::Mod::STATUSRES, 25);
    }

    // add mob pool mods ahead of applying stats
    mobutils::AddSqlModifiers(PTrust);

    xi::Job mJob = PTrust->GetMJob();
    xi::Job sJob = PTrust->GetSJob();
    uint8   mLvl = PTrust->GetMLevel();
    uint8   sLvl = PTrust->GetSLevel();

    // Helpers to map HP/MPScale around 100 to 1-7 grades
    // std::clamp doesn't play nice with uint8, so -> unsigned int
    auto mapRanges = [](unsigned int inputStart, unsigned int inputEnd, unsigned int outputStart, unsigned int outputEnd, unsigned int inputVal) -> unsigned int
    {
        unsigned int inputRange  = inputEnd - inputStart;
        unsigned int outputRange = outputEnd - outputStart;

        unsigned int output = (inputVal - inputStart) * outputRange / inputRange + outputStart;

        return std::clamp(output, outputStart, outputEnd);
    };

    auto scaleToGrade = [mapRanges](float input) -> unsigned int
    {
        unsigned int multipliedInput    = static_cast<unsigned int>(input * 100U);
        unsigned int reverseMappedGrade = mapRanges(70U, 140U, 1U, 7U, multipliedInput);
        unsigned int outputGrade        = std::clamp(7U - reverseMappedGrade, 1U, 7U);
        return outputGrade;
    };

    // HP/MP ========================
    // This is the same system as used in charutils.cpp, but modified
    // to use parts from mob_species_system instead of hardcoded player
    // race tables.

    // http://ffxi-stat-calc.sourceforge.net/cgi-bin/ffxistats.cgi?mode=document

    // HP
    float raceStat  = 0;
    float jobStat   = 0;
    float sJobStat  = 0;
    int32 bonusStat = 0;

    int32 baseValueColumn   = 0;
    int32 scaleTo60Column   = 1;
    int32 scaleOver30Column = 2;
    int32 scaleOver60Column = 3;
    int32 scaleOver75Column = 4;
    int32 scaleOver60       = 2;
    // int32 scaleOver75       = 3;

    uint8 grade = 0;

    int32 mainLevelOver30     = std::clamp(mLvl - 30, 0, 30);
    int32 mainLevelUpTo60     = (mLvl < 60 ? mLvl - 1 : 59);
    int32 mainLevelOver60To75 = std::clamp(mLvl - 60, 0, 15);
    int32 mainLevelOver75     = (mLvl < 75 ? 0 : mLvl - 75);

    int32 mainLevelOver10           = (mLvl < 10 ? 0 : mLvl - 10);
    int32 mainLevelOver50andUnder60 = std::clamp(mLvl - 50, 0, 10);
    int32 mainLevelOver60           = (mLvl < 60 ? 0 : mLvl - 60);

    int32 subLevelOver10 = std::clamp(sLvl - 10, 0, 20);
    int32 subLevelOver30 = (sLvl < 30 ? 0 : sLvl - 30);

    grade = scaleToGrade(PTrust->HPscale);

    raceStat = grade::GetHPScale(grade, baseValueColumn) + (grade::GetHPScale(grade, scaleTo60Column) * mainLevelUpTo60) +
               (grade::GetHPScale(grade, scaleOver30Column) * mainLevelOver30) + (grade::GetHPScale(grade, scaleOver60Column) * mainLevelOver60To75) +
               (grade::GetHPScale(grade, scaleOver75Column) * mainLevelOver75);

    grade = grade::GetJobGrade(mJob, 0);

    jobStat = grade::GetHPScale(grade, baseValueColumn) + (grade::GetHPScale(grade, scaleTo60Column) * mainLevelUpTo60) +
              (grade::GetHPScale(grade, scaleOver30Column) * mainLevelOver30) + (grade::GetHPScale(grade, scaleOver60Column) * mainLevelOver60To75) +
              (grade::GetHPScale(grade, scaleOver75Column) * mainLevelOver75);

    bonusStat = (mainLevelOver10 + mainLevelOver50andUnder60) * 2;

    if (sLvl > 0)
    {
        grade = grade::GetJobGrade(sJob, 0);

        sJobStat = grade::GetHPScale(grade, baseValueColumn) + (grade::GetHPScale(grade, scaleTo60Column) * (sLvl - 1)) +
                   (grade::GetHPScale(grade, scaleOver30Column) * subLevelOver30) + subLevelOver30 + subLevelOver10;
    }

    auto hpMultiplierTrust = settings::get<float>("map.ALTER_EGO_HP_MULTIPLIER");
    hpMultiplierTrust      = (hpMultiplierTrust >= 0.1f && hpMultiplierTrust <= 2.0f) ? hpMultiplierTrust : 1.0f;
    PTrust->health.maxhp   = (int16)((raceStat + jobStat + bonusStat + sJobStat) * hpMultiplierTrust);

    // MP
    raceStat = 0;
    jobStat  = 0;
    sJobStat = 0;

    grade = scaleToGrade(PTrust->MPscale);

    if (grade::GetJobGrade(mJob, 1) == 0)
    {
        if (grade::GetJobGrade(sJob, 1) != 0 && sLvl > 0)
        {
            raceStat = (grade::GetMPScale(grade, 0) + grade::GetMPScale(grade, scaleTo60Column) * (sLvl - 1)) / settings::get<uint8>("map.SJ_MP_DIVISOR");
        }
    }
    else
    {
        raceStat = grade::GetMPScale(grade, 0) + grade::GetMPScale(grade, scaleTo60Column) * mainLevelUpTo60 +
                   grade::GetMPScale(grade, scaleOver60) * mainLevelOver60;
    }

    grade = grade::GetJobGrade(mJob, 1);

    if (grade > 0)
    {
        jobStat = grade::GetMPScale(grade, 0) + grade::GetMPScale(grade, scaleTo60Column) * mainLevelUpTo60 +
                  grade::GetMPScale(grade, scaleOver60) * mainLevelOver60;
    }

    if (sLvl > 0)
    {
        grade    = grade::GetJobGrade(sJob, 1);
        sJobStat = grade::GetMPScale(grade, 0) + grade::GetMPScale(grade, scaleTo60Column);
    }

    auto mpMultiplierTrust = settings::get<float>("map.ALTER_EGO_MP_MULTIPLIER");
    mpMultiplierTrust      = (mpMultiplierTrust >= 0.1f && mpMultiplierTrust <= 2.0f) ? mpMultiplierTrust : 1.0f;
    PTrust->health.maxmp   = (int16)((raceStat + jobStat + sJobStat) * mpMultiplierTrust);

    PTrust->health.tp = 0;
    PTrust->UpdateHealth();
    PTrust->health.hp = PTrust->GetMaxHP();
    PTrust->health.mp = PTrust->GetMaxMP();

    // Stats ========================
    uint16 fSTR = mobutils::GetBaseToRank(PTrust->strRank, mLvl);
    uint16 fDEX = mobutils::GetBaseToRank(PTrust->dexRank, mLvl);
    uint16 fVIT = mobutils::GetBaseToRank(PTrust->vitRank, mLvl);
    uint16 fAGI = mobutils::GetBaseToRank(PTrust->agiRank, mLvl);
    uint16 fINT = mobutils::GetBaseToRank(PTrust->intRank, mLvl);
    uint16 fMND = mobutils::GetBaseToRank(PTrust->mndRank, mLvl);
    uint16 fCHR = mobutils::GetBaseToRank(PTrust->chrRank, mLvl);

    uint16 mSTR = mobutils::GetBaseToRank(grade::GetJobGrade(PTrust->GetMJob(), 2), mLvl);
    uint16 mDEX = mobutils::GetBaseToRank(grade::GetJobGrade(PTrust->GetMJob(), 3), mLvl);
    uint16 mVIT = mobutils::GetBaseToRank(grade::GetJobGrade(PTrust->GetMJob(), 4), mLvl);
    uint16 mAGI = mobutils::GetBaseToRank(grade::GetJobGrade(PTrust->GetMJob(), 5), mLvl);
    uint16 mINT = mobutils::GetBaseToRank(grade::GetJobGrade(PTrust->GetMJob(), 6), mLvl);
    uint16 mMND = mobutils::GetBaseToRank(grade::GetJobGrade(PTrust->GetMJob(), 7), mLvl);
    uint16 mCHR = mobutils::GetBaseToRank(grade::GetJobGrade(PTrust->GetMJob(), 8), mLvl);

    uint16 sSTR = mobutils::GetBaseToRank(grade::GetJobGrade(PTrust->GetSJob(), 2), sLvl);
    uint16 sDEX = mobutils::GetBaseToRank(grade::GetJobGrade(PTrust->GetSJob(), 3), sLvl);
    uint16 sVIT = mobutils::GetBaseToRank(grade::GetJobGrade(PTrust->GetSJob(), 4), sLvl);
    uint16 sAGI = mobutils::GetBaseToRank(grade::GetJobGrade(PTrust->GetSJob(), 5), sLvl);
    uint16 sINT = mobutils::GetBaseToRank(grade::GetJobGrade(PTrust->GetSJob(), 6), sLvl);
    uint16 sMND = mobutils::GetBaseToRank(grade::GetJobGrade(PTrust->GetSJob(), 7), sLvl);
    uint16 sCHR = mobutils::GetBaseToRank(grade::GetJobGrade(PTrust->GetSJob(), 8), sLvl);

    if (sLvl > 15)
    {
        sSTR /= 2;
        sDEX /= 2;
        sAGI /= 2;
        sINT /= 2;
        sMND /= 2;
        sCHR /= 2;
        sVIT /= 2;
    }
    else
    {
        sSTR = 0;
        sDEX = 0;
        sAGI = 0;
        sINT = 0;
        sMND = 0;
        sCHR = 0;
        sVIT = 0;
    }

    auto statMultiplier = settings::get<float>("map.ALTER_EGO_STAT_MULTIPLIER");
    statMultiplier      = (statMultiplier >= 0.1f && statMultiplier <= 2.0f) ? statMultiplier : 1.0f;
    PTrust->stats.STR   = static_cast<uint16>((fSTR + mSTR + sSTR) * statMultiplier);
    PTrust->stats.DEX   = static_cast<uint16>((fDEX + mDEX + sDEX) * statMultiplier);
    PTrust->stats.VIT   = static_cast<uint16>((fVIT + mVIT + sVIT) * statMultiplier);
    PTrust->stats.AGI   = static_cast<uint16>((fAGI + mAGI + sAGI) * statMultiplier);
    PTrust->stats.INT   = static_cast<uint16>((fINT + mINT + sINT) * statMultiplier);
    PTrust->stats.MND   = static_cast<uint16>((fMND + mMND + sMND) * statMultiplier);
    PTrust->stats.CHR   = static_cast<uint16>((fCHR + mCHR + sCHR) * statMultiplier);

    // Skills =======================
    for (int i = static_cast<int>(xi::SkillType::DivineMagic); i <= static_cast<int>(xi::SkillType::BlueMagic); i++)
    {
        uint16 maxSkill = battleutils::GetMaxSkill((xi::SkillType)i, mJob, mLvl > 99 ? 99 : mLvl);
        if (maxSkill != 0)
        {
            PTrust->WorkingSkills.skill[i] = static_cast<uint16>(maxSkill * settings::get<float>("map.ALTER_EGO_SKILL_MULTIPLIER"));
        }
        else // if the mob is WAR/BLM and can cast spell
        {
            // set skill as high as main level, so their spells won't get resisted
            uint16 maxSubSkill = battleutils::GetMaxSkill((xi::SkillType)i, sJob, mLvl > 99 ? 99 : mLvl);

            if (maxSubSkill != 0)
            {
                PTrust->WorkingSkills.skill[i] = static_cast<uint16>(maxSubSkill * settings::get<float>("map.ALTER_EGO_SKILL_MULTIPLIER"));
            }
        }
    }

    for (int i = static_cast<int>(xi::SkillType::HandToHand); i <= static_cast<int>(xi::SkillType::Staff); i++)
    {
        uint16 maxSkill = battleutils::GetMaxSkill(static_cast<uint8>(i), mLvl > 99 ? 99 : mLvl);
        if (maxSkill != 0)
        {
            PTrust->WorkingSkills.skill[i] = static_cast<uint16>(maxSkill * settings::get<float>("map.ALTER_EGO_SKILL_MULTIPLIER"));
        }
    }

    PTrust->addModifier(xi::Mod::DEF, mobutils::GetBaseSkill(PTrust, PTrust->defRank));
    PTrust->addModifier(xi::Mod::EVA, mobutils::GetBaseSkill(PTrust, PTrust->evaRank));
    PTrust->addModifier(xi::Mod::ATT, mobutils::GetBaseSkill(PTrust, PTrust->attRank));
    PTrust->addModifier(xi::Mod::ACC, mobutils::GetBaseSkill(PTrust, PTrust->accRank));

    PTrust->addModifier(xi::Mod::RATT, mobutils::GetBaseSkill(PTrust, PTrust->attRank));
    PTrust->addModifier(xi::Mod::RACC, mobutils::GetBaseSkill(PTrust, PTrust->accRank));

    // Natural magic evasion
    PTrust->addModifier(xi::Mod::MEVA, mobutils::GetMagicEvasion(PTrust));

    // Add traits for sub and main
    battleutils::AddTraits(PTrust, traits::GetTraits(mJob), mLvl);
    battleutils::AddTraits(PTrust, traits::GetTraits(sJob), sLvl);

    mobutils::SetupJob(PTrust);

    // Skills
    using namespace gambits;
    auto* controller = dynamic_cast<CTrustController*>(PTrust->PAI->GetController());

    if (!controller)
    {
        ShowWarning("trustutils::LoadTrustStatsAndSkills() - Trust Controller was null.");
        return;
    }

    // Default TP selectors
    controller->m_GambitsContainer->tp_trigger = G_TP_TRIGGER::ASAP;
    controller->m_GambitsContainer->tp_select  = G_SELECT::RANDOM;

    auto skillList = battleutils::GetMobSkillList(PTrust->m_MobSkillList);
    for (uint16 skill_id : skillList)
    {
        TrustSkill_t skill;
        if (skill_id <= 255) // Player WSs
        {
            CWeaponSkill* PWeaponSkill = battleutils::GetWeaponSkill(skill_id);
            if (!PWeaponSkill)
            {
                ShowWarning("LoadTrustStatsAndSkills: Error loading WeaponSkill id %d for trust %s", skill_id, PTrust->name);
                break;
            }

            skill = TrustSkill_t{
                G_REACTION::WS,
                skill_id,
                PWeaponSkill->getPrimarySkillchain(),
                PWeaponSkill->getSecondarySkillchain(),
                PWeaponSkill->getTertiarySkillchain(),
                battleutils::isValidSelfTargetWeaponskill(skill_id) ? TARGET_SELF : TARGET_ENEMY,
            };
        }
        else // MobSkills
        {
            CMobSkill* PMobSkill = battleutils::GetMobSkill(skill_id);
            if (!PMobSkill)
            {
                ShowWarning("LoadTrustStatsAndSkills: Error loading MobSkill id %d for trust %s", skill_id, PTrust->name);
                break;
            }
            skill = {
                G_REACTION::MS,
                skill_id,
                PMobSkill->getPrimarySkillchain(),
                PMobSkill->getSecondarySkillchain(),
                PMobSkill->getTertiarySkillchain(),
                static_cast<TARGETTYPE>(PMobSkill->getValidTargets()),
            };

            controller->m_GambitsContainer->tp_skills.emplace_back(skill);
        }

        // Only get access to skills that produce Lv3 SCs after Lv60
        bool canFormLv3Skillchain = skill.primary >= SC_GRAVITATION || skill.secondary >= SC_GRAVITATION || skill.tertiary >= SC_GRAVITATION;

        // Special case for Zeid II and others who only have Lv3+ skills
        bool onlyHasLv3Skillchains = canFormLv3Skillchain && controller->m_GambitsContainer->tp_skills.empty();

        if (!canFormLv3Skillchain || PTrust->GetMLevel() >= 60 || onlyHasLv3Skillchains)
        {
            controller->m_GambitsContainer->tp_skills.emplace_back(skill);
        }
    }
}
