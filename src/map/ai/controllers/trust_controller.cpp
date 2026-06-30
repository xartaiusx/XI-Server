/*
===========================================================================

  Copyright (c) 2018 Darkstar Dev Teams

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

#include "trust_controller.h"

#include "ability.h"
#include "ai/helpers/gambits_container.h"
#include "ai/states/despawn_state.h"
#include "ai/states/magic_state.h"
#include "ai/states/range_state.h"
#include "common/settings.h"
#include "enmity_container.h"
#include "entities/char_entity.h"
#include "entities/trust_entity.h"
#include "items/item_weapon.h"
#include "mob_modifier.h"
#include "mob_spell_container.h"
#include "modifier.h"
#include "notoriety_container.h"
#include "packets/basic.h"
#include "player_controller.h"
#include "recast_container.h"
#include "status_effect_container.h"
#include "utils/charutils.h"
#include "zone.h"

#include <algorithm>
#include <cctype>
#include <limits>
#include <string>
#include <unordered_set>
#include <vector>

namespace
{

enum TRUST_MOVEMENT_TYPE : int8
{
    // NOTE: If you need to add special movement types, add descending into the minus values.
    //     : All of the positive values are taken for the ranged movement range.
    // NOTE: You can use any positive value as a distance, and it will act as MID_RANGE or LONG_RANGE, but with the value you've provided.
    //     : For example:
    //     :     mob:setMobMod(xi.mobMod.TRUST_DISTANCE, 20)
    //     : Will set the combat distance the trust tries to stick to to 20'
    // NOTE: If a Trust doesn't immediately sprint to a certain distance at the start of battle, it's probably NO_MOVE or MELEE.
    NO_MOVE    = -1, // Will stand still providing they're within casting distance of their master and target when the fight starts. Otherwise will reposition to be within 9.0' of both
    NON_COMBAT = -2, // Will follow the master if first trust in party and will follow the trust in front if lower in the list.
    MELEE      = 0,  // Default: will continually reposition to stay within melee range of the target
    MID_RANGE  = 6,  // Will path at the start of battle to 6' away from the target, and try to stay at that distance
    LONG_RANGE = 12, // Will path at the start of battle to 12' away from the target, and try to stay at that distance
};

constexpr float DefensiveEngageDistance       = 40.0f;
constexpr float CasterRestFollowBreakDistance = 12.0f;
constexpr auto  TrustRestModeVar              = "MochiTrustRestMode";
constexpr auto  TrustRestStartReasonVar       = "MochiTrustRestStartReason";
constexpr auto  TrustRestStopReasonVar        = "MochiTrustRestStopReason";
constexpr auto  TrustRestBlockReasonVar       = "MochiTrustRestBlockReason";
constexpr auto  TrustFocusTargetTargIdVar     = "MochiTrustFocusTargetTargId";
constexpr auto  TrustFocusReasonVar           = "MochiTrustFocusReason";
constexpr auto  TrustRoleEnmityActionVar      = "MochiTrustRoleEnmityAction";
constexpr auto  TrustRoleEnmityTargetVar      = "MochiTrustRoleEnmityTargetTargId";

enum class TrustRestMode : uint8
{
    None        = 0,
    OutOfCombat = 1,
    Combat      = 2,
};

enum class TrustRestStartReason : uint8
{
    None     = 0,
    LowMp    = 1,
    LowHp    = 2,
    LowMpHp  = 3,
    CombatMp = 4,
};

enum class TrustRestStopReason : uint8
{
    None          = 0,
    Engaged       = 1,
    FollowBreak   = 2,
    RecoveryFloor = 3,
    FullyHealed   = 4,
    CombatUnsafe  = 5,
};

enum class TrustRestBlockReason : uint8
{
    None                = 0,
    NotNeeded           = 1,
    CombatMpAboveStart  = 2,
    CombatRestDisabled  = 3,
    PersonalThreat      = 4,
    ImmediateMpRecovery = 5,
    PartyNeedsCaster    = 6,
    RecentDamage        = 7,
    FollowingPath       = 8,
    TooFarFromMaster    = 9,
    CannotRest          = 10,
    CannotChangeState   = 11,
    OutOfCombatCooldown = 12,
};

enum class TrustFocusReason : uint8
{
    None          = 0,
    MasterTarget  = 1,
    Defensive     = 2,
    CurrentTarget = 3,
};

enum class TrustRoleEnmityAction : uint8
{
    None       = 0,
    TankAssist = 1,
    Shed       = 2,
};

struct TrustFocusResult
{
    CMobEntity*      PMob   = nullptr;
    TrustFocusReason reason = TrustFocusReason::None;
};

template <typename F>
void ForTrustDefendedGroup(CCharEntity* PMaster, F&& func)
{
    if (!PMaster)
    {
        return;
    }

    std::unordered_set<uint32> seen;
    auto visit = [&](CBattleEntity* PEntity)
    {
        if (PEntity && seen.insert(PEntity->id).second)
        {
            func(PEntity);
        }
    };

    PMaster->ForAlliance([&](CBattleEntity* PMember)
    {
        visit(PMember);

        if (auto* PCharMember = dynamic_cast<CCharEntity*>(PMember))
        {
            for (auto* PTrust : PCharMember->PTrusts)
            {
                visit(PTrust);
            }
        }
    });

    // Mochirii's Trust auto-alliance is virtual at the packet layer, so keep
    // the master's active Trust vector in the defended set even when there is
    // no real CAlliance row backing the extra Trust parties.
    for (auto* PTrust : PMaster->PTrusts)
    {
        visit(PTrust);
    }
}

auto MobThreatensEntity(CMobEntity* PMob, CBattleEntity* PEntity) -> bool
{
    if (!PMob || !PEntity || !PMob->PEnmityContainer || !PMob->isAlive() || PMob->allegiance == PEntity->allegiance)
    {
        return false;
    }

    const auto* enmityList = PMob->PEnmityContainer->GetEnmityList();
    if (!enmityList)
    {
        return false;
    }

    const auto enmityObject = enmityList->find(PEntity->id);
    if (enmityObject == enmityList->end())
    {
        return false;
    }

    const auto& entry = enmityObject->second;
    return entry.active && entry.PEnmityOwner && ((entry.CE + entry.VE) > 0 || PMob->GetBattleTargetID() == PEntity->targid);
}

auto MobThreatensTrustParty(CMobEntity* PMob, CCharEntity* PMaster) -> bool
{
    bool threatens = false;
    ForTrustDefendedGroup(PMaster, [&](CBattleEntity* PEntity)
    {
        if (!threatens && MobThreatensEntity(PMob, PEntity))
        {
            threatens = true;
        }
    });

    return threatens;
}

auto DefensiveThreatDistance(CMobEntity* PMob, CCharEntity* PMaster) -> float
{
    auto closestDistance = std::numeric_limits<float>::max();

    ForTrustDefendedGroup(PMaster, [&](CBattleEntity* PEntity)
    {
        if (MobThreatensEntity(PMob, PEntity))
        {
            closestDistance = std::min(closestDistance, distance(PEntity->loc.p, PMob->loc.p));
        }
    });

    return closestDistance;
}

auto GetDefensiveTargetFrom(CBattleEntity* PDefendedEntity, CCharEntity* PMaster) -> CMobEntity*
{
    if (!PDefendedEntity || !PMaster || !PDefendedEntity->PNotorietyContainer || !PDefendedEntity->PNotorietyContainer->hasEnmity())
    {
        return nullptr;
    }

    for (auto* PEntity : *PDefendedEntity->PNotorietyContainer)
    {
        auto* PMob = dynamic_cast<CMobEntity*>(PEntity);
        if (!PMob || !MobThreatensTrustParty(PMob, PMaster) || PMob->PAI->IsUntargetable())
        {
            continue;
        }

        if (distance(PDefendedEntity->loc.p, PMob->loc.p) > DefensiveEngageDistance &&
            distance(PMaster->loc.p, PMob->loc.p) > DefensiveEngageDistance)
        {
            continue;
        }

        return PMob;
    }

    return nullptr;
}

auto GetDefensiveTargetByScanningZone(CCharEntity* PMaster) -> CMobEntity*
{
    if (!PMaster || !PMaster->loc.zone)
    {
        return nullptr;
    }

    CMobEntity* PBestTarget  = nullptr;
    auto        bestDistance = std::numeric_limits<float>::max();

    PMaster->loc.zone->ForEachMob([&](CMobEntity* PMob)
    {
        if (!PMob || !PMob->isAlive() || !PMob->PEnmityContainer || PMob->PAI->IsUntargetable())
        {
            return;
        }

        if (!MobThreatensTrustParty(PMob, PMaster))
        {
            return;
        }

        const auto threatDistance = DefensiveThreatDistance(PMob, PMaster);
        if (threatDistance > DefensiveEngageDistance || threatDistance >= bestDistance)
        {
            return;
        }

        PBestTarget  = PMob;
        bestDistance = threatDistance;
    });

    return PBestTarget;
}

auto GetTrustDefensiveTarget(CCharEntity* PMaster) -> CMobEntity*
{
    if (!PMaster || !settings::get<bool>("main.ENABLE_TRUST_DEFENSIVE_MODE"))
    {
        return nullptr;
    }

    if (auto* PMob = dynamic_cast<CMobEntity*>(PMaster->GetBattleTarget()); MobThreatensTrustParty(PMob, PMaster))
    {
        return PMob;
    }

    CMobEntity* PTarget = nullptr;
    ForTrustDefendedGroup(PMaster, [&](CBattleEntity* PEntity)
    {
        if (PTarget == nullptr)
        {
            PTarget = GetDefensiveTargetFrom(PEntity, PMaster);
        }
    });

    if (PTarget == nullptr)
    {
        PTarget = GetDefensiveTargetByScanningZone(PMaster);
    }

    return PTarget;
}

auto IsValidTrustFocusTarget(CMobEntity* PMob, CCharEntity* PMaster) -> bool
{
    return PMob && PMaster && PMob->isAlive() && PMob->allegiance != PMaster->allegiance && !PMob->PAI->IsUntargetable();
}

auto TrustProfileKey(CBattleEntity* PEntity) -> std::string
{
    std::string key;
    if (!PEntity)
    {
        return key;
    }

    for (const auto ch : PEntity->getName())
    {
        if (std::isalnum(static_cast<unsigned char>(ch)))
        {
            key += static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
        }
    }

    return key;
}

auto IsTankTrust(CBattleEntity* PEntity) -> bool
{
    if (!PEntity)
    {
        return false;
    }

    const auto key = TrustProfileKey(PEntity);
    return key == "valaineral" ||
           key == "august" ||
           key == "amchuchu" ||
           key == "trion" ||
           key == "curilla" ||
           key == "aaev" ||
           key == "rughadjeen" ||
           key == "gessho" ||
           key == "mnejing";
}

auto IsDefendedGroupMember(CCharEntity* PMaster, CBattleEntity* PTarget) -> bool
{
    bool found = false;
    ForTrustDefendedGroup(PMaster, [&](CBattleEntity* PEntity)
    {
        if (PEntity == PTarget)
        {
            found = true;
        }
    });

    return found;
}

auto FindTankTrust(CCharEntity* PMaster, CMobEntity* PMob) -> CTrustEntity*
{
    CTrustEntity* PTank = nullptr;
    ForTrustDefendedGroup(PMaster, [&](CBattleEntity* PEntity)
    {
        if (PTank || !PEntity || PEntity->objtype != TYPE_TRUST || !PEntity->isAlive() || !IsTankTrust(PEntity))
        {
            return;
        }

        if (PMob && distance(PEntity->loc.p, PMob->loc.p) > DefensiveEngageDistance)
        {
            return;
        }

        PTank = static_cast<CTrustEntity*>(PEntity);
    });

    return PTank;
}

void SetTrustFocusVars(CTrustEntity* PTrust, const TrustFocusResult& focus)
{
    if (!PTrust)
    {
        return;
    }

    PTrust->SetLocalVar(TrustFocusTargetTargIdVar, focus.PMob ? focus.PMob->targid : 0);
    PTrust->SetLocalVar(TrustFocusReasonVar, static_cast<uint16>(focus.reason));
}

auto ResolveTrustFocusTarget(CCharEntity* PMaster, CTrustEntity* PTrust) -> TrustFocusResult
{
    if (!PMaster || !PTrust)
    {
        return {};
    }

    const bool sharedTargeting = settings::get<bool>("main.ENABLE_TRUST_SHARED_TARGETING");

    if (sharedTargeting && PMaster->PAI->IsEngaged())
    {
        if (auto* PMob = dynamic_cast<CMobEntity*>(PMaster->GetBattleTarget()); IsValidTrustFocusTarget(PMob, PMaster))
        {
            return { PMob, TrustFocusReason::MasterTarget };
        }
    }

    if (auto* PDefensiveTarget = GetTrustDefensiveTarget(PMaster); IsValidTrustFocusTarget(PDefensiveTarget, PMaster))
    {
        return { PDefensiveTarget, TrustFocusReason::Defensive };
    }

    if (sharedTargeting)
    {
        return {};
    }

    if (auto* PCurrentTarget = dynamic_cast<CMobEntity*>(PTrust->GetBattleTarget()); IsValidTrustFocusTarget(PCurrentTarget, PMaster))
    {
        return { PCurrentTarget, TrustFocusReason::CurrentTarget };
    }

    return {};
}

auto IsBacklineMagicTrust(CTrustEntity* PTrust) -> bool
{
    if (!PTrust || PTrust->GetMaxMP() <= 0)
    {
        return false;
    }

    switch (PTrust->GetMJob())
    {
        case JOB_WHM:
        case JOB_BLM:
        case JOB_RDM:
        case JOB_BRD:
        case JOB_SMN:
        case JOB_BLU:
        case JOB_SCH:
        case JOB_GEO:
            break;
        default:
            return false;
    }

    return PTrust->getMobMod(MOBMOD_TRUST_DISTANCE) != TRUST_MOVEMENT_TYPE::MELEE;
}

auto IsTrustResting(CTrustEntity* PTrust) -> bool
{
    return PTrust && PTrust->GetLocalVar(TrustRestModeVar) != static_cast<uint16>(TrustRestMode::None);
}

auto IsHealerCasterTrust(CTrustEntity* PTrust) -> bool
{
    if (!PTrust)
    {
        return false;
    }

    return PTrust->GetMJob() == JOB_WHM ||
           PTrust->GetMJob() == JOB_SCH ||
           PTrust->GetSJob() == JOB_WHM;
}

auto IsSupportCasterTrust(CTrustEntity* PTrust) -> bool
{
    if (!PTrust)
    {
        return false;
    }

    switch (PTrust->GetMJob())
    {
        case JOB_RDM:
        case JOB_BRD:
        case JOB_SMN:
        case JOB_GEO:
            return true;
        default:
            return PTrust->GetSJob() == JOB_SCH;
    }
}

auto ResolveTrustCombatDistance(CTrustEntity* PTrust, int16 configuredDistance) -> int16
{
    // Mochirii already exposes per-Trust positioning through MOBMOD_TRUST_DISTANCE
    // and xi.trust.movementType. Keep that setting authoritative instead of inferring
    // combat range from broad job families.
    (void)PTrust;
    return configuredDistance;
}

void SetTrustRoleEnmityVars(CTrustEntity* PTrust, TrustRoleEnmityAction action, CBattleEntity* PTarget)
{
    if (!PTrust)
    {
        return;
    }

    PTrust->SetLocalVar(TrustRoleEnmityActionVar, static_cast<uint16>(action));
    PTrust->SetLocalVar(TrustRoleEnmityTargetVar, PTarget ? PTarget->targid : 0);
}

void ApplyTrustRoleEnmity(CTrustEntity* PTrust, CCharEntity* PMaster, CMobEntity* PMob)
{
    if (!PTrust || !PMaster || !PMob || !PMob->PEnmityContainer || !settings::get<bool>("main.ENABLE_TRUST_ROLE_ENMITY"))
    {
        return;
    }

    SetTrustRoleEnmityVars(PTrust, TrustRoleEnmityAction::None, nullptr);

    auto* PHighest = PMob->PEnmityContainer->GetHighestEnmity();
    if (!PHighest || !IsDefendedGroupMember(PMaster, PHighest))
    {
        return;
    }

    if (IsTankTrust(PTrust))
    {
        if (PHighest != PTrust)
        {
            PMob->PEnmityContainer->UpdateEnmity(
                PTrust,
                settings::get<int32>("main.TRUST_TANK_ENMITY_ASSIST_CE"),
                settings::get<int32>("main.TRUST_TANK_ENMITY_ASSIST_VE"),
                false,
                false,
                false);
            SetTrustRoleEnmityVars(PTrust, TrustRoleEnmityAction::TankAssist, PHighest);
        }

        return;
    }

    if (PHighest == PTrust)
    {
        auto* PTank = FindTankTrust(PMaster, PMob);
        PMob->PEnmityContainer->LowerEnmityByPercent(
            PTrust,
            settings::get<uint8>("main.TRUST_NON_TANK_ENMITY_SHED_PERCENT"),
            PTank != PTrust ? PTank : nullptr);
        SetTrustRoleEnmityVars(PTrust, TrustRoleEnmityAction::Shed, PTank);
    }
}

auto GetCasterCombatRestStopMpp(CTrustEntity* PTrust) -> uint8
{
    if (IsHealerCasterTrust(PTrust))
    {
        return settings::get<uint8>("main.TRUST_CASTER_COMBAT_REST_HEALER_STOP_MPP");
    }

    if (IsSupportCasterTrust(PTrust))
    {
        return settings::get<uint8>("main.TRUST_CASTER_COMBAT_REST_SUPPORT_STOP_MPP");
    }

    return settings::get<uint8>("main.TRUST_CASTER_COMBAT_REST_NUKER_STOP_MPP");
}

auto TrustHasImmediateMpRecovery(CTrustEntity* PTrust) -> bool
{
    if (!PTrust)
    {
        return false;
    }

    if (PTrust->StatusEffectContainer->HasStatusEffect({
            xi::StatusEffect::Refresh,
            xi::StatusEffect::Ballad,
            xi::StatusEffect::GeoRefresh,
            xi::StatusEffect::EvokersRoll,
            xi::StatusEffect::SublimationComplete,
            xi::StatusEffect::AutoRefresh,
        }))
    {
        return true;
    }

    return PTrust->getMod(Mod::REFRESH) > PTrust->getMod(Mod::REFRESH_DOWN);
}

auto TrustPartyNeedsCasterNow(CTrustEntity* PTrust, CCharEntity* PMaster, uint8 hppFloor) -> bool
{
    if (!PTrust || !PMaster)
    {
        return true;
    }

    auto needsCaster = [hppFloor](CBattleEntity* PEntity) -> bool
    {
        return !PEntity || PEntity->isDead() || PEntity->GetHPP() <= hppFloor;
    };

    bool needs = false;
    ForTrustDefendedGroup(PMaster, [&](CBattleEntity* PEntity)
    {
        if (!needs && needsCaster(PEntity))
        {
            needs = true;
        }
    });

    return needs;
}

auto TrustHasPersonalThreat(CTrustEntity* PTrust) -> bool
{
    if (!PTrust)
    {
        return true;
    }

    if (auto* PMob = dynamic_cast<CMobEntity*>(PTrust->GetBattleTarget()); MobThreatensEntity(PMob, PTrust))
    {
        return true;
    }

    if (!PTrust->PNotorietyContainer || !PTrust->PNotorietyContainer->hasEnmity())
    {
        return false;
    }

    for (auto* PEntity : *PTrust->PNotorietyContainer)
    {
        auto* PMob = dynamic_cast<CMobEntity*>(PEntity);
        if (!PMob || !MobThreatensEntity(PMob, PTrust) || PMob->PAI->IsUntargetable())
        {
            continue;
        }

        if (distance(PTrust->loc.p, PMob->loc.p) <= DefensiveEngageDistance)
        {
            return true;
        }
    }

    return false;
}

void ApplyTrustLogicalRestTick(CTrustEntity* PTrust, timer::time_point tick, timer::time_point& lastHealTickTime, std::size_t& numHealingTicks, const std::vector<std::chrono::seconds>& tickDelays)
{
    if (!PTrust || tickDelays.empty())
    {
        return;
    }

    const auto tickDelay = tickDelays.at(std::min(numHealingTicks, tickDelays.size() - 1U));
    if (tick - lastHealTickTime <= tickDelay)
    {
        return;
    }

    if (PTrust->health.hp == PTrust->health.maxhp && PTrust->health.mp == PTrust->health.maxmp)
    {
        return;
    }

    const auto recoverHP = std::max<uint32>(1U, static_cast<uint32>(PTrust->health.maxhp * 0.05));
    const auto recoverMP = std::max<uint32>(1U, static_cast<uint32>(PTrust->health.maxmp * 0.05));
    PTrust->addHP(recoverHP);
    PTrust->addMP(recoverMP);
    PTrust->updatemask |= UPDATE_HP;
    lastHealTickTime = tick;
    numHealingTicks  = std::clamp(numHealingTicks + 1, static_cast<std::size_t>(0U), tickDelays.size() - 1U);
}

void SetTrustRestBlockReason(CTrustEntity* PTrust, TrustRestBlockReason blockReason)
{
    if (!PTrust)
    {
        return;
    }

    PTrust->SetLocalVar(TrustRestBlockReasonVar, static_cast<uint16>(blockReason));
}

void SetTrustResting(CTrustEntity* PTrust, bool enabled, TrustRestStartReason startReason = TrustRestStartReason::None, TrustRestStopReason stopReason = TrustRestStopReason::None, TrustRestMode mode = TrustRestMode::None)
{
    if (!PTrust)
    {
        return;
    }

    if (enabled)
    {
        if (IsTrustResting(PTrust) || PTrust->StatusEffectContainer->HasPreventActionEffect())
        {
            return;
        }

        PTrust->SetLocalVar(TrustRestModeVar, static_cast<uint16>(mode));
        PTrust->SetLocalVar(TrustRestStartReasonVar, static_cast<uint16>(startReason));
        PTrust->SetLocalVar(TrustRestStopReasonVar, static_cast<uint16>(TrustRestStopReason::None));
        SetTrustRestBlockReason(PTrust, TrustRestBlockReason::None);

        if (PTrust->PAI->IsEngaged())
        {
            PTrust->PAI->Internal_Disengage();
        }

        PTrust->PAI->PathFind->Clear();
    }
    else
    {
        if (!IsTrustResting(PTrust))
        {
            return;
        }

        PTrust->SetLocalVar(TrustRestStopReasonVar, static_cast<uint16>(stopReason));
        PTrust->SetLocalVar(TrustRestModeVar, static_cast<uint16>(TrustRestMode::None));
    }
}

} // namespace

CTrustController::CTrustController(CCharEntity* PChar, CTrustEntity* PTrust)
: CMobController(PTrust)
, m_GambitsContainer(std::make_unique<gambits::CGambitsContainer>(PTrust))
, m_LastTopEnmity(nullptr)
, m_failedRepositionAttempts(0)
, m_InTransit(false)
{
}

CTrustController::~CTrustController()
{
    if (POwner->PAI->IsEngaged())
    {
        POwner->PAI->Internal_Disengage();
    }
    POwner->PAI->PathFind.reset();
    POwner->allegiance = ALLEGIANCE_TYPE::PLAYER;
    POwner->status     = STATUS_TYPE::DISAPPEAR;
    m_LastTopEnmity    = nullptr;
}

void CTrustController::Despawn()
{
    POwner->PMaster   = nullptr;
    POwner->animation = ANIMATION_DESPAWN;
    CMobController::Despawn();
}

auto CTrustController::Tick(timer::time_point tick) -> Task<void>
{
    TracyZoneScoped;
    TracyZoneString(POwner->getName());

    m_Tick = tick;

    auto* PTrust = static_cast<CTrustEntity*>(POwner);

    if (!PTrust->PMaster)
    {
        co_return;
    }

    if (PTrust->PMaster->isCharmed)
    {
        this->Despawn();
        co_return;
    }

    const bool nonCombatFollowTrust = PTrust->getMobMod(MOBMOD_TRUST_DISTANCE) == TRUST_MOVEMENT_TYPE::NON_COMBAT;

    if (PTrust->PMaster->PAI->IsEngaged() && nonCombatFollowTrust)
    {
        co_await DoNonCombatTick(tick);
    }
    else if (POwner->PAI->IsEngaged())
    {
        co_await DoCombatTick(tick);
    }
    else if (!POwner->isDead())
    {
        co_await DoRoamTick(tick);
    }

    co_return;
}

auto CTrustController::DoCombatTick(timer::time_point tick) -> Task<void>
{
    TracyZoneScoped;

    CTrustEntity* PTrust  = static_cast<CTrustEntity*>(POwner);
    CCharEntity*  PMaster = static_cast<CCharEntity*>(POwner->PMaster);
    auto          focus   = ResolveTrustFocusTarget(PMaster, PTrust);
    SetTrustFocusVars(PTrust, focus);

    if (focus.PMob)
    {
        if (PTrust->GetBattleTargetID() != focus.PMob->targid)
        {
            PTrust->PAI->Internal_ChangeTarget(focus.PMob->targid);
            m_LastTopEnmity = nullptr;
        }

        PTarget = focus.PMob;
    }
    else
    {
        PTrust->PAI->Internal_Disengage();
        m_LastTopEnmity = nullptr;
        m_CombatEndTime = m_Tick;
        co_return;
    }

    const auto roleEnmityDelay = std::chrono::seconds(settings::get<uint8>("main.TRUST_ROLE_ENMITY_TICK_SECONDS"));
    if (m_Tick - m_LastRoleEnmityTime > roleEnmityDelay)
    {
        ApplyTrustRoleEnmity(PTrust, PMaster, focus.PMob);
        m_LastRoleEnmityTime = m_Tick;
    }

    // If busy, don't run around!
    if (PTrust->PAI->IsCurrentState<CMagicState>() || PTrust->PAI->IsCurrentState<CRangeState>())
    {
        co_return;
    }

    if (PTarget)
    {
        if (PTrust->PAI->CanFollowPath() && PTrust->GetSpeed() > 0)
        {
            float currentDistanceToTarget = distance(PTrust->loc.p, PTarget->loc.p);
            float currentDistanceToMaster = distance(PTrust->loc.p, PMaster->loc.p);

            if (!PMaster->PAI->IsEngaged() && currentDistanceToTarget > WarpDistance)
            {
                PTrust->PAI->PathFind->WarpTo(PTarget->loc.p);
            }

            PTrust->PAI->PathFind->LookAt(PTarget->loc.p);

            int16 movementDistance = ResolveTrustCombatDistance(PTrust, PTrust->getMobMod(MOBMOD_TRUST_DISTANCE));

            switch (movementDistance)
            {
                case TRUST_MOVEMENT_TYPE::NO_MOVE:
                {
                    if (currentDistanceToMaster > CastingDistance)
                    {
                        PathOutToDistance(PTarget, 9.0f);
                    }
                    else if (currentDistanceToTarget > CastingDistance)
                    {
                        PathOutToDistance(PTarget, 9.0f);
                    }
                    break;
                }
                case TRUST_MOVEMENT_TYPE::NON_COMBAT:
                {
                    // Non-combat followers should not use target-distance positioning.
                    break;
                }
                case TRUST_MOVEMENT_TYPE::MELEE:
                {
                    std::unique_ptr<CBasicPacket> err;
                    if (!PTrust->CanAttack(PTarget, err) && PTrust->GetSpeed() > 0)
                    {
                        if (currentDistanceToTarget > RoamDistance)
                        {
                            if (currentDistanceToTarget < RoamDistance * 3.0f &&
                                PTrust->PAI->PathFind->PathAround(PTarget->loc.p, RoamDistance, PATHFLAG_RUN | PATHFLAG_WALLHACK))
                            {
                                PTrust->PAI->PathFind->FollowPath(m_Tick);
                            }
                            else if (PTrust->GetSpeed() > 0)
                            {
                                PTrust->PAI->PathFind->StepTo(PTarget->loc.p, true);
                            }
                        }
                    }
                    break;
                }
                case TRUST_MOVEMENT_TYPE::MID_RANGE:
                    [[fallthrough]];
                case TRUST_MOVEMENT_TYPE::LONG_RANGE:
                    [[fallthrough]];
                default: // Using the positive-non-zero movementDistance mobMod value
                {
                    PathOutToDistance(PTarget, static_cast<float>(movementDistance));
                    break;
                }
            }

            if (!PTrust->PAI->PathFind->IsFollowingPath())
            {
                Declump(PMaster, PTarget);
            }
        }

        if (!m_InTransit)
        {
            PTrust->PAI->PathFind->FollowPath(m_Tick);
        }

        co_await m_GambitsContainer->Tick(tick);

        PTrust->PAI->EventHandler.triggerListener("COMBAT_TICK", PTrust, PMaster, PTarget);
    }

    co_return;
}

auto CTrustController::DoNonCombatTick(timer::time_point tick) -> Task<void>
{
    TracyZoneScoped;

    auto* PTrust  = static_cast<CTrustEntity*>(POwner);
    auto* PMaster = static_cast<CCharEntity*>(POwner->PMaster);

    if (!PMaster)
    {
        co_return;
    }

    // Keep COMBAT_TICK target valid for listeners/gambits.
    auto focus = ResolveTrustFocusTarget(PMaster, PTrust);
    SetTrustFocusVars(PTrust, focus);
    PTarget = focus.PMob ? static_cast<CBattleEntity*>(focus.PMob) : PMaster->GetBattleTarget();

    // Non-combat trust follow order:
    // - first trust follows master
    // - others follow the trust directly in front of them
    uint8 currentPartyPos = GetPartyPosition();

    CBattleEntity* PFollowTarget = PMaster;
    if (currentPartyPos > 0 && static_cast<size_t>(currentPartyPos - 1) < PMaster->PTrusts.size())
    {
        if (auto* PLeadTrust = PMaster->PTrusts.at(currentPartyPos - 1); PLeadTrust && PLeadTrust != PTrust)
        {
            PFollowTarget = PLeadTrust;
        }
    }

    // First trust keeps a bit more space from master.
    constexpr float FirstTrustFollowDistance = 3.0f; // tune as needed
    const float     desiredFollowDistance    = (currentPartyPos == 0) ? FirstTrustFollowDistance : RoamDistance;

    float currentDistance = distance(PTrust->loc.p, PFollowTarget->loc.p);

    // Simple declump so non-combat trusts don't stack on each other.
    for (auto* POtherTrust : PMaster->PTrusts)
    {
        if (POtherTrust != PTrust &&
            distance(POtherTrust->loc.p, PTrust->loc.p) < 1.0f &&
            !PTrust->PAI->PathFind->IsFollowingPath())
        {
            auto diff_angle = worldAngle(PTrust->loc.p, POtherTrust->loc.p) + 64;
            auto amount     = (currentPartyPos % 2) ? 1.0f : -1.0f;

            position_t new_pos = {
                PTrust->loc.p.x - (cosf(rotationToRadian(diff_angle)) * amount),
                POtherTrust->loc.p.y,
                PTrust->loc.p.z + (sinf(rotationToRadian(diff_angle)) * amount),
                0,
                0,
            };

            if (PTrust->PAI->PathFind->ValidPosition(new_pos) &&
                PTrust->PAI->PathFind->PathAround(new_pos, desiredFollowDistance, PATHFLAG_RUN | PATHFLAG_WALLHACK))
            {
                PTrust->PAI->PathFind->FollowPath(m_Tick);
            }
            break;
        }
    }

    if (currentDistance > WarpDistance)
    {
        PTrust->PAI->PathFind->WarpTo(PFollowTarget->loc.p);
    }
    else if (currentDistance > desiredFollowDistance)
    {
        if (currentDistance < desiredFollowDistance * 3.0f &&
            PTrust->PAI->PathFind->PathAround(PFollowTarget->loc.p, desiredFollowDistance, PATHFLAG_RUN | PATHFLAG_WALLHACK))
        {
            PTrust->PAI->PathFind->FollowPath(m_Tick);
        }
        else if (PTrust->GetSpeed() > 0)
        {
            PTrust->PAI->PathFind->StepTo(PFollowTarget->loc.p, true);
        }
    }

    if (PTrust->PAI->PathFind->IsFollowingPath())
    {
        PTrust->PAI->PathFind->FollowPath(m_Tick);
    }

    // Keep gambits active in combat, but only while stationary.
    if (PMaster->PAI->IsEngaged() && !PTrust->PAI->PathFind->IsFollowingPath())
    {
        co_await m_GambitsContainer->Tick(tick);
        PTrust->PAI->EventHandler.triggerListener("COMBAT_TICK", PTrust, PMaster, PTarget);
    }

    co_return;
}

auto CTrustController::DoRoamTick(timer::time_point tick) -> Task<void>
{
    TracyZoneScoped;

    auto* PTrust               = static_cast<CTrustEntity*>(POwner);
    auto* PMaster              = static_cast<CCharEntity*>(POwner->PMaster);
    auto  masterLastAttackTime = static_cast<CPlayerController*>(PMaster->PAI->GetController())->getLastAttackTime();
    bool  masterMeleeSwing     = masterLastAttackTime > timer::now() - 1s;

    bool  trustEngageCondition  = false;
    auto  focus                 = ResolveTrustFocusTarget(PMaster, PTrust);
    auto* PDefensiveTarget      = focus.reason == TrustFocusReason::Defensive ? focus.PMob : nullptr;
    auto  trustEngageTargetID   = focus.PMob ? focus.PMob->targid : 0;
    bool  casterResting         = settings::get<bool>("main.ENABLE_TRUST_CASTER_RESTING") && IsBacklineMagicTrust(PTrust);
    bool  trustCurrentlyResting = casterResting && IsTrustResting(PTrust);

    SetTrustFocusVars(PTrust, focus);

    if (PDefensiveTarget)
    {
        trustEngageCondition = true;
    }

    // NOTE: charvars are now cached, this is essentially a localvar read now.
    switch (PDefensiveTarget ? 1 : charutils::GetCharVar(PMaster, "TrustEngageType"))
    {
        case 1: // Master engages a monster, no melee swing required
        {
            trustEngageCondition = trustEngageCondition || PMaster->GetBattleTarget();
            break;
        }
        case 0: // Nothing set
            [[fallthrough]];
        default: // Something invalid set
        {
            // Default retail behavior: Master engages a monster and executes a melee swing
            trustEngageCondition = trustEngageCondition || (PMaster->GetBattleTarget() && masterMeleeSwing);
            break;
        }
    }

    const bool partyInCombat = PMaster->PAI->IsEngaged() || PDefensiveTarget != nullptr;
    const auto restCooldown  = std::chrono::seconds(settings::get<uint8>("main.TRUST_CASTER_REST_COOLDOWN"));
    const bool wantsCombatRest =
        casterResting &&
        settings::get<bool>("main.ENABLE_TRUST_CASTER_COMBAT_RESTING") &&
        partyInCombat &&
        POwner->GetMPP() <= settings::get<uint8>("main.TRUST_CASTER_COMBAT_REST_MPP_START") &&
        distance(POwner->loc.p, PMaster->loc.p) <= CasterRestFollowBreakDistance &&
        m_Tick - POwner->LastAttacked > restCooldown &&
        !TrustHasPersonalThreat(PTrust) &&
        !TrustHasImmediateMpRecovery(PTrust) &&
        !TrustPartyNeedsCasterNow(PTrust, PMaster, settings::get<uint8>("main.TRUST_CASTER_COMBAT_REST_PARTY_HPP_MIN"));

    const uint16 modelID_Cornelia = 3119; // Cornielia does not have an Attack Schedule so do not engage.

    if (!trustCurrentlyResting && !wantsCombatRest &&
        (PMaster->PAI->IsEngaged() || PDefensiveTarget) && focus.PMob && trustEngageCondition && trustEngageTargetID != 0 && POwner->GetModelId() != modelID_Cornelia)
    {
        POwner->PAI->Internal_Engage(trustEngageTargetID);
    }

    uint8          currentPartyPos = GetPartyPosition();
    CBattleEntity* PFollowTarget   = (GetPartyPosition() > 0) ? (CBattleEntity*)PMaster->PTrusts.at(currentPartyPos - 1) : POwner->PMaster;
    float          currentDistance = distance(POwner->loc.p, PFollowTarget->loc.p);

    // Formation following thresholds (in yalms)
    // First trust follows master more closely than other trusts follow each other
    bool isFirstTrust = (currentPartyPos == 0);

    float declumpDistance = isFirstTrust ? 1.0f : 1.5f; // Too close, need to move away
    float followMax       = isFirstTrust ? 2.0f : 3.5f; // Maximum follow distance before moving closer
    float followTarget    = isFirstTrust ? 1.5f : 3.0f; // Ideal follow distance

    if (casterResting && IsTrustResting(PTrust))
    {
        SetTrustRestBlockReason(PTrust, TrustRestBlockReason::None);

        const auto restStopMpp       = settings::get<uint8>("main.TRUST_CASTER_REST_MPP_STOP");
        const auto restStopHpp       = settings::get<uint8>("main.TRUST_CASTER_REST_HPP_STOP");
        const auto combatRestStopMpp = GetCasterCombatRestStopMpp(PTrust);
        const auto masterDistance    = distance(POwner->loc.p, PMaster->loc.p);
        const auto followGrace       = std::chrono::seconds(settings::get<uint8>("main.TRUST_CASTER_REST_FOLLOW_GRACE_SECONDS"));
        const bool followGraceActive = m_Tick - m_CasterRestStartTime < followGrace;
        const bool currentlyInCombat = PMaster->PAI->IsEngaged() || PDefensiveTarget != nullptr;
        const bool combatRestUnsafe =
            currentlyInCombat &&
            (!settings::get<bool>("main.ENABLE_TRUST_CASTER_COMBAT_RESTING") ||
             TrustHasPersonalThreat(PTrust) ||
             TrustHasImmediateMpRecovery(PTrust) ||
             TrustPartyNeedsCasterNow(PTrust, PMaster, settings::get<uint8>("main.TRUST_CASTER_COMBAT_REST_PARTY_HPP_MIN")));
        const bool reachedRestFloor = currentlyInCombat ? POwner->GetMPP() >= combatRestStopMpp : (POwner->GetMPP() >= restStopMpp && POwner->GetHPP() >= restStopHpp);

        TrustRestStopReason stopReason = TrustRestStopReason::None;
        if (POwner->PAI->IsEngaged())
        {
            stopReason = TrustRestStopReason::Engaged;
        }
        else if (masterDistance > CasterRestFollowBreakDistance && !followGraceActive)
        {
            stopReason = TrustRestStopReason::FollowBreak;
        }
        else if (reachedRestFloor)
        {
            stopReason = TrustRestStopReason::RecoveryFloor;
        }
        else if (combatRestUnsafe)
        {
            stopReason = TrustRestStopReason::CombatUnsafe;
        }

        if (stopReason != TrustRestStopReason::None)
        {
            SetTrustResting(PTrust, false, TrustRestStartReason::None, stopReason);
            m_NumHealingTicks = 0;
        }
        else
        {
            ApplyTrustLogicalRestTick(PTrust, m_Tick, m_LastHealTickTime, m_NumHealingTicks, m_tickDelays);
            PTrust->PAI->EventHandler.triggerListener("COMBAT_TICK", PTrust, PMaster, PTarget);
            co_return;
        }
    }

    // Handle formation movement based on distance thresholds
    if (currentDistance < declumpDistance)
    {
        // Too close to follow target - push away to maintain formation spacing
        if (PFollowTarget && POwner->PAI->PathFind->PathAround(PFollowTarget->loc.p, followTarget + 0.5f, PATHFLAG_RUN | PATHFLAG_WALLHACK))
        {
            POwner->PAI->PathFind->FollowPath(m_Tick);
        }
    }
    else if (currentDistance > followMax)
    {
        // Too far from follow target - move closer to maintain formation
        if (currentDistance > WarpDistance)
        {
            // Warp if extremely too far
            POwner->PAI->PathFind->WarpTo(PFollowTarget->loc.p);
        }
        else
        {
            // Path or step closer to follow target
            if (currentDistance < RoamDistance * 3.0f && POwner->PAI->PathFind->PathAround(PFollowTarget->loc.p, followTarget, PATHFLAG_RUN | PATHFLAG_WALLHACK))
            {
                POwner->PAI->PathFind->FollowPath(m_Tick);
            }
            else if (POwner->GetSpeed() > 0)
            {
                POwner->PAI->PathFind->StepTo(PFollowTarget->loc.p, true);
            }
        }
    }
    else
    {
        // In formation range - stop pathfinding to prevent circling
        if (POwner->PAI->PathFind->IsFollowingPath())
        {
            POwner->PAI->PathFind->Clear();
        }
    }

    if (casterResting)
    {
        const auto restStartMpp       = settings::get<uint8>("main.TRUST_CASTER_REST_MPP_START");
        const auto restStartHpp       = settings::get<uint8>("main.TRUST_CASTER_REST_HPP_START");
        const auto combatRestStartMpp = settings::get<uint8>("main.TRUST_CASTER_COMBAT_REST_MPP_START");
        const auto partyHppFloor      = settings::get<uint8>("main.TRUST_CASTER_COMBAT_REST_PARTY_HPP_MIN");
        const auto masterDistance     = distance(POwner->loc.p, PMaster->loc.p);
        const bool currentlyInCombat  = PMaster->PAI->IsEngaged() || PDefensiveTarget != nullptr;
        const bool wantsOutOfCombatMp = POwner->GetMPP() <= restStartMpp;
        const bool wantsOutOfCombatHp = POwner->GetHPP() <= restStartHpp;
        const bool hasPersonalThreat  = TrustHasPersonalThreat(PTrust);
        const bool hasImmediateMpTool = TrustHasImmediateMpRecovery(PTrust);
        const bool partyNeedsCaster   = TrustPartyNeedsCasterNow(PTrust, PMaster, partyHppFloor);
        const bool recentDamageClear  = m_Tick - POwner->LastAttacked > restCooldown;
        const bool canRest            = POwner->CanRest();
        const bool canChangeState     = POwner->PAI->CanChangeState();
        const bool isFollowingPath    = POwner->PAI->PathFind->IsFollowingPath();
        const bool canStartOutOfCombatRest =
            !currentlyInCombat &&
            m_Tick - m_CombatEndTime > restCooldown &&
            (wantsOutOfCombatMp || wantsOutOfCombatHp);
        const bool canStartCombatRest =
            currentlyInCombat &&
            settings::get<bool>("main.ENABLE_TRUST_CASTER_COMBAT_RESTING") &&
            POwner->GetMPP() <= combatRestStartMpp &&
            !hasPersonalThreat &&
            !hasImmediateMpTool &&
            !partyNeedsCaster;
        const bool readyToRest =
            canRest && canChangeState && !isFollowingPath && masterDistance <= CasterRestFollowBreakDistance && recentDamageClear;
        const bool wantsAnyRest = currentlyInCombat ? POwner->GetMPP() <= combatRestStartMpp : (wantsOutOfCombatMp || wantsOutOfCombatHp);

        TrustRestBlockReason blockReason = TrustRestBlockReason::None;
        if (!wantsAnyRest)
        {
            blockReason = TrustRestBlockReason::NotNeeded;
        }
        else if (!canRest)
        {
            blockReason = TrustRestBlockReason::CannotRest;
        }
        else if (!canChangeState)
        {
            blockReason = TrustRestBlockReason::CannotChangeState;
        }
        else if (isFollowingPath)
        {
            blockReason = TrustRestBlockReason::FollowingPath;
        }
        else if (masterDistance > CasterRestFollowBreakDistance)
        {
            blockReason = TrustRestBlockReason::TooFarFromMaster;
        }
        else if (!recentDamageClear)
        {
            blockReason = TrustRestBlockReason::RecentDamage;
        }
        else if (currentlyInCombat && !settings::get<bool>("main.ENABLE_TRUST_CASTER_COMBAT_RESTING"))
        {
            blockReason = TrustRestBlockReason::CombatRestDisabled;
        }
        else if (currentlyInCombat && POwner->GetMPP() > combatRestStartMpp)
        {
            blockReason = TrustRestBlockReason::CombatMpAboveStart;
        }
        else if (currentlyInCombat && hasPersonalThreat)
        {
            blockReason = TrustRestBlockReason::PersonalThreat;
        }
        else if (currentlyInCombat && hasImmediateMpTool)
        {
            blockReason = TrustRestBlockReason::ImmediateMpRecovery;
        }
        else if (currentlyInCombat && partyNeedsCaster)
        {
            blockReason = TrustRestBlockReason::PartyNeedsCaster;
        }
        else if (!currentlyInCombat && !canStartOutOfCombatRest)
        {
            blockReason = TrustRestBlockReason::OutOfCombatCooldown;
        }

        SetTrustRestBlockReason(PTrust, blockReason);

        if ((!POwner->PAI->IsEngaged() || canStartCombatRest) &&
            readyToRest &&
            (canStartOutOfCombatRest || canStartCombatRest))
        {
            const auto startReason = canStartCombatRest ? TrustRestStartReason::CombatMp : (wantsOutOfCombatMp && wantsOutOfCombatHp ? TrustRestStartReason::LowMpHp : wantsOutOfCombatMp ? TrustRestStartReason::LowMp
                                                                                                                                                                                          : TrustRestStartReason::LowHp);
            const auto restMode    = canStartCombatRest ? TrustRestMode::Combat : TrustRestMode::OutOfCombat;
            SetTrustResting(PTrust, true, startReason, TrustRestStopReason::None, restMode);
            m_CasterRestStartTime = m_Tick;
            m_LastHealTickTime    = m_Tick;
            m_NumHealingTicks     = 0;
            PTrust->PAI->EventHandler.triggerListener("COMBAT_TICK", PTrust, PMaster, PTarget);
        }

        co_return;
    }

    if (POwner->CanRest() && m_Tick - POwner->LastAttacked > m_tickDelays.at(0) && m_Tick - m_CombatEndTime > m_tickDelays.at(0) &&
        m_Tick - m_LastHealTickTime > m_tickDelays.at(m_NumHealingTicks))
    {
        if (POwner->health.hp != POwner->health.maxhp || POwner->health.mp != POwner->health.maxmp)
        {
            // recover 5% HP & MP
            uint32 recoverHP = (uint32)(POwner->health.maxhp * 0.05);
            uint32 recoverMP = (uint32)(POwner->health.maxmp * 0.05);
            POwner->addHP(recoverHP);
            POwner->addMP(recoverMP);
            m_LastHealTickTime = m_Tick;
            POwner->updatemask |= UPDATE_HP;
            m_NumHealingTicks = std::clamp(m_NumHealingTicks + 1, static_cast<std::size_t>(0U), m_tickDelays.size() - 1U);
        }
    }

    co_return;
}

void CTrustController::Declump(CCharEntity* PMaster, CBattleEntity* PTarget)
{
    TracyZoneScoped;

    uint8 currentPartyPos = GetPartyPosition();
    for (auto* POtherTrust : PMaster->PTrusts)
    {
        if (POtherTrust != POwner && !POtherTrust->PAI->PathFind->IsFollowingPath() && distance(POtherTrust->loc.p, POwner->loc.p) < 1.5f)
        {
            auto diffAngle  = worldAngle(POwner->loc.p, PTarget->loc.p) + 64;
            auto moveAmount = xirand::GetRandomNumber(0.0f, 1.5f) * ((currentPartyPos % 2) ? 1.0f : -1.0f);

            // clang-format off
            position_t newPos =
            {
                POwner->loc.p.x - (cosf(rotationToRadian(diffAngle)) * moveAmount),
                PTarget->loc.p.y,
                POwner->loc.p.z + (sinf(rotationToRadian(diffAngle)) * moveAmount),
                0,
                0,
            };
            // clang-format on

            if (POwner->PAI->PathFind->ValidPosition(newPos))
            {
                POwner->PAI->PathFind->PathTo(newPos, PATHFLAG_RUN | PATHFLAG_WALLHACK);
            }
            break;
        }
    }
}

void CTrustController::PathOutToDistance(CBattleEntity* PTarget, float amount)
{
    TracyZoneScoped;

    float      currentDistanceToTarget = distance(POwner->loc.p, PTarget->loc.p);
    position_t target_position         = POwner->loc.p;

    if (GetTopEnmity() == POwner)
    {
        ++m_failedRepositionAttempts;
    }
    else
    {
        m_failedRepositionAttempts = 0;
    }

    // Invalidate position and pick new one (limit: every 3s)
    if ((currentDistanceToTarget < amount - 2.5f || currentDistanceToTarget > amount + 2.5f || !POwner->PAI->PathFind->ValidPosition(POwner->loc.p)) &&
        m_Tick - m_LastRepositionTime > 3s && !m_InTransit)
    {
        std::vector<position_t> positions(5);
        for (auto& position : positions)
        {
            int        random_angle       = xirand::GetRandomNumber(256);
            position_t potential_position = {
                PTarget->loc.p.x - (cosf(rotationToRadian(random_angle)) * amount),
                PTarget->loc.p.y,
                PTarget->loc.p.z + (sinf(rotationToRadian(random_angle)) * amount),
                0,
                0,
            };
            position = potential_position;
        }

        bool position_found = false;
        for (auto& potential_position : positions)
        {
            // Validate position
            if (!position_found &&
                POwner->PAI->PathFind->ValidPosition(potential_position) &&
                POwner->CanSeeTarget(potential_position))
            {
                position_found  = true;
                target_position = potential_position;
                m_InTransit     = true;
            }
        }

        m_LastRepositionTime = m_Tick;
    }

    // Get somewhat close to the target destination
    if (distance(POwner->loc.p, target_position) > 2.0f && m_failedRepositionAttempts < 3)
    {
        POwner->PAI->PathFind->PathTo(target_position, PATHFLAG_RUN | PATHFLAG_WALLHACK);
    }
    else
    {
        FaceTarget(PTarget->targid);
        m_InTransit = false;
    }
}

bool CTrustController::Ability(uint16 targid, uint16 abilityid)
{
    TracyZoneScoped;

    if (static_cast<CMobEntity*>(POwner)->PRecastContainer->HasRecast(RECAST_ABILITY, static_cast<Recast>(abilityid), 0s))
    {
        return false;
    }

    if (POwner->PAI->CanChangeState())
    {
        return POwner->PAI->Internal_Ability(targid, abilityid);
    }

    return false;
}

bool CTrustController::RangedAttack(uint16 targid)
{
    TracyZoneScoped;

    timer::duration rangedDelay = 10s;
    if (CItemWeapon* PRange = dynamic_cast<CItemWeapon*>(POwner->m_Weapons[SLOT_RANGED]))
    {
        rangedDelay = std::chrono::milliseconds(PRange->getDelay());
    }

    if (m_Tick - m_LastRangedAttackTime > rangedDelay && !m_InTransit)
    {
        FaceTarget(PTarget->targid);
        if (POwner->PAI->CanChangeState() && POwner->PAI->Internal_RangedAttack(targid))
        {
            m_LastRangedAttackTime = m_Tick;
        }
        return true;
    }
    return false;
}

bool CTrustController::Cast(uint16 targid, SpellID spellid)
{
    TracyZoneScoped;

    FaceTarget(targid);

    if (static_cast<CMobEntity*>(POwner)->PRecastContainer->Has(RECAST_MAGIC, static_cast<Recast>(spellid)))
    {
        return false;
    }

    auto* PSpell = spell::GetSpell(spellid);
    if (PSpell->getValidTarget() == TARGET_SELF)
    {
        targid = POwner->targid;
    }

    auto PTarget      = (CBattleEntity*)POwner->GetEntity(targid, TYPE_MOB | TYPE_PC | TYPE_PET | TYPE_TRUST);
    auto PSpellFamily = PSpell->getSpellFamily();
    bool canCast      = true;

    // clang-format off
    static_cast<CCharEntity*>(POwner->PMaster)->ForPartyWithTrusts([&](CBattleEntity* PMember)
    {
        if (PMember->objtype == TYPE_TRUST && PMember->PAI->IsCurrentState<CMagicState>())
        {
            auto MState = static_cast<CMagicState*>(PMember->PAI->GetCurrentState());

            if (MState)
            {
                auto MSpell       = MState->GetSpell();
                auto MTarget      = MState->GetTarget();
                auto MSpellFamily = MSpell->getSpellFamily();
                auto MSpellID     = MSpell->getID();

                if (PSpell->isBuff())
                {
                    if (PSpellFamily == MSpellFamily && spellid <= MSpellID)
                    {
                        canCast = false;
                    }
                }
                if (PSpell->isCure())
                {
                    if (PTarget == MTarget && PTarget->GetHPP() > 50)
                    {
                        canCast = false;
                    }
                }
                if (PSpell->isDebuff())
                {
                    if (PSpellFamily == MSpellFamily && spellid <= MSpellID)
                    {
                        canCast = false;
                    }
                }
                if (PSpell->isNa())
                {
                    if (PSpellFamily == MSpellFamily && spellid == MSpellID)
                    {
                        canCast = false;
                    }
                }
            }
        }
    });
    // clang-format on

    if (!canCast)
    {
        return false;
    }

    return CMobController::Cast(targid, spellid);
}

CBattleEntity* CTrustController::GetTopEnmity()
{
    TracyZoneScoped;

    CBattleEntity* PEntity = nullptr;
    if (auto* PMob = dynamic_cast<CMobEntity*>(POwner->GetBattleTarget()))
    {
        return PMob->PEnmityContainer->GetHighestEnmity();
    }
    return PEntity;
}

uint8 CTrustController::GetPartyPosition()
{
    TracyZoneScoped;

    auto& trustList = static_cast<CCharEntity*>(POwner->PMaster)->PTrusts;
    for (std::size_t i = 0; i < trustList.size(); ++i)
    {
        if (trustList.at(i)->id == POwner->id)
        {
            return static_cast<uint8>(i);
        }
    }
    return 0;
}
