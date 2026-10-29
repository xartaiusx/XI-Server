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

#include <map/entities/trust_entity.h>

#include "action/action.h"
#include "action/interrupts.h"
#include "ai/ai_container.h"
#include "ai/controllers/trust_controller.h"
#include "ai/helpers/pathfind.h"
#include "ai/helpers/targetfind.h"
#include "ai/states/death_state.h"
#include "ai/states/magic_state.h"
#include "ai/states/weaponskill_state.h"
#include "data/enums/mob_mod.h"
#include "enmity_container.h"
#include "entities/char_entity.h"
#include "enums/msg_basic.h"
#include "lua/luautils.h"
#include "packets/entity_set_name.h"
#include "packets/s2c/0x028_battle2.h"
#include "packets/s2c/0x0df_group_attr.h"
#include "party.h"
#include "recast_container.h"
#include "status_effect_container.h"
#include "utils/battleutils.h"
#include "utils/charutils.h"
#include "utils/trust_job_development.h"
#include "utils/trustutils.h"
#include "zone.h"

#include <algorithm>
#include <array>
#include <limits>

namespace
{

constexpr int8 kTrustDefaultShieldSize = 3;

} // namespace

CTrustEntity::CTrustEntity(CCharEntity* PChar, uint32 trustId, IsPassiveTrust isPassiveTrust)
: CMobEntity()
, trustID_(trustId)
, passiveTrust_(isPassiveTrust)
{
    objtype                     = TYPE_TRUST;
    m_EcoSystem                 = xi::Ecosystem::Unclassified;
    allegiance                  = xi::Allegiance::Player;
    m_MobSkillList              = 0;
    PMaster                     = PChar;
    m_bReleaseTargIDOnDisappear = true;
    spawnAnimation              = xi::SpawnAnimation::Special; // Initial spawn has the special spawn-in animation

    PAI = std::make_unique<CAIContainer>(this,
                                         std::make_unique<CPathFind>(this),
                                         std::make_unique<CTrustController>(PChar, this),
                                         std::make_unique<CTargetFind>(this));
}

CTrustEntity::~CTrustEntity()
{
    TracyZoneScoped;
}

auto CTrustEntity::trustID() const -> uint32
{
    return trustID_;
}

auto CTrustEntity::shieldSize() -> int8
{
    const auto shieldSizeMod = static_cast<int8>(getMobMod(xi::MobMod::TrustShieldSize));
    return shieldSizeMod > 0 ? shieldSizeMod : kTrustDefaultShieldSize;
}

auto CTrustEntity::released() -> bool
{
    return released_;
}

void CTrustEntity::setReleased(bool released)
{
    released_ = released;
}

auto CTrustEntity::passiveTrust() -> IsPassiveTrust
{
    return passiveTrust_;
}

auto CTrustEntity::IsRetainedCorpse() const -> bool
{
    return retainedCorpse_;
}

auto CTrustEntity::CanReceiveRaise() const -> bool
{
    const auto* master = dynamic_cast<const CCharEntity*>(PMaster);
    return retainedCorpse_ && health.hp == 0 && !released_ && trustdevelopment::IsEnabled(this) &&
           master && loc.zone && master->loc.zone == loc.zone && master->PInstance == PInstance &&
           master->status != xi::Status::Disappear && master->status != xi::Status::Shutdown &&
           std::ranges::contains(master->PTrusts, this);
}

auto CTrustEntity::HasPendingRaise() const -> bool
{
    return pendingRaise_.has_value();
}

// Reuse native visibility removal/addition; never spawn or replace this entity.
void CTrustEntity::SyncRecoveryView()
{
    const auto* master = dynamic_cast<const CCharEntity*>(PMaster);
    if (!master || !loc.zone || released_ || master->loc.zone != loc.zone || master->PInstance != PInstance ||
        master->status == xi::Status::Disappear || master->status == xi::Status::Shutdown ||
        !std::ranges::contains(master->PTrusts, this))
    {
        return;
    }

    loc.zone->ForEachCharInstance(this, [this](CCharEntity* observer)
                                  {
                                      if (observer->loc.zone == loc.zone && observer->PInstance == PInstance)
                                      {
                                          loc.zone->SpawnTRUSTs(observer);
                                      }
                                  });
}

auto CTrustEntity::OfferRaise(TrustRaiseOptions options) -> bool
{
    auto* state = dynamic_cast<CDeathState*>(PAI->GetCurrentState());
    if (!CanReceiveRaise() || HasPendingRaise() || !state || !trustrecovery::IsValid(options))
    {
        return false;
    }

    pendingRaise_ = options;
    state->allowSendRaise();
    SyncRecoveryView();
    return true;
}

auto CTrustEntity::OfferReraise(uint8 tier) -> bool
{
    const auto options = trustrecovery::ReraiseOptions(tier);
    if (!CanReceiveRaise() || HasPendingRaise() || !trustrecovery::IsValid(options))
    {
        return false;
    }

    // The death state's existing eight-second Reraise delay remains in force.
    pendingRaise_ = options;
    SyncRecoveryView();
    return true;
}

auto CTrustEntity::CompleteRaise() -> bool
{
    if (!CanReceiveRaise() || !pendingRaise_)
    {
        return false;
    }

    const auto options = *pendingRaise_;
    weaknessLevel_     = std::max<uint16>(weaknessLevel_, 1);
    if (!StatusEffectContainer->AddStatusEffect(xi::StatusEffect::Weakness, static_cast<uint16>(xi::StatusEffect::Weakness), weaknessLevel_, 0s, trustrecovery::WeaknessDuration(options)))
    {
        return false;
    }
    pendingRaise_.reset();
    // Native Weakness updates/clamps HP and MP. Raise returns HP, never refills MP.
    addHP(trustrecovery::ReturnedHP(GetMaxHP(), options.tier));

    if (options.grantReraiseIII)
    {
        StatusEffectContainer->AddStatusEffect(xi::StatusEffect::Reraise, static_cast<uint16>(xi::StatusEffect::Reraise), 3, 0s, 1h);
    }

    // The admitted offer culled the old client view during its native wait.
    // Re-add the same living entity before Raise; do not call native Spawn().
    // CDeathState still owns the unchanged two-second recovery lock.
    animation = xi::Animation::None;
    SyncRecoveryView();

    action_t action{ .actorId = id, .actiontype = ActionCategory::MagicFinish };
    auto&    result = action.addTarget(id).addResult();
    switch (options.tier)
    {
        case 1:
            result.animation = ActionAnimation::Raise;
            break;
        case 2:
            result.animation = ActionAnimation::Raise2;
            break;
        case 3:
            result.animation = ActionAnimation::Raise3;
            break;
        case 4:
            result.animation = ActionAnimation::Arise;
            break;
    }
    trustutils::LogTrustActionPacket(this, action, this, "trust_raise_finish");
    loc.zone->PushPacket(this, CHAR_INRANGE_SELF, std::make_unique<GP_SERV_COMMAND_BATTLE2>(action));
    updatemask |= UPDATE_HP;
    return true;
}

void CTrustEntity::FinishRaise()
{
    retainedCorpse_ = false;
    pendingRaise_.reset();
}

void CTrustEntity::PostTick()
{
    // NOTE: This is purposefully calling CBattleEntity's impl.
    // TODO: Calling a grand-parent's impl. of an overridden function is bad
    CBattleEntity::PostTick();
    timer::time_point now = timer::now();
    if (loc.zone && updatemask && status != xi::Status::Disappear && now > m_nextUpdateTimer)
    {
        m_nextUpdateTimer = now + 250ms;
        loc.zone->UpdateEntityPacket(this, ENTITY_UPDATE, updatemask);

        if (PMaster && PMaster->PParty && updatemask & UPDATE_HP)
        {
            PMaster->ForParty(
                [this](auto PMember)
                {
                    static_cast<CCharEntity*>(PMember)->pushPacket<GP_SERV_COMMAND_GROUP_ATTR>(this);
                });
        }

        updatemask = 0;
    }
}

void CTrustEntity::FadeOut()
{
    CBaseEntity::FadeOut();
    loc.zone->UpdateEntityPacket(this, ENTITY_DESPAWN, UPDATE_NONE);
}

void CTrustEntity::Die()
{
    retainedCorpse_ = trustdevelopment::IsEnabled(this);
    pendingRaise_.reset();
    if (retainedCorpse_)
    {
        if (const auto* weakness = StatusEffectContainer->GetStatusEffect(xi::StatusEffect::Weakness))
        {
            weaknessLevel_ = static_cast<uint16>(std::min<uint32>(static_cast<uint32>(weakness->GetPower()) + 1, std::numeric_limits<uint16>::max()));
            StatusEffectContainer->DelStatusEffectSilent(xi::StatusEffect::Weakness);
        }
        else
        {
            weaknessLevel_ = 0;
        }
    }

    luautils::OnMobDeath(this, nullptr);
    PEnmityContainer->Clear();
    PAI->ClearActionQueue();
    PAI->ClearTimerQueue();
    PAI->ClearStateStack();
    health.tp = 0;
    PAI->Internal_Die(retainedCorpse_ ? trustrecovery::CorpseLifetime : 0s);
    if (retainedCorpse_)
    {
        const uint8 reraise = getMod(xi::Mod::RERAISE_III) > 0 ? 3 : getMod(xi::Mod::RERAISE_II) > 0 ? 2
                                                                 : getMod(xi::Mod::RERAISE_I) > 0    ? 1
                                                                                                     : 0;
        if (reraise != 0 && (!pendingRaise_ || pendingRaise_->tier < reraise))
        {
            pendingRaise_ = trustrecovery::ReraiseOptions(reraise);
        }
    }
    if (!retainedCorpse_)
    {
        static_cast<CCharEntity*>(PMaster)->RemoveTrust(this);
    }

    // Preserve native death-listener semantics, then retain the exact owner identity.
    const auto owner = m_OwnerID;
    m_OwnerID.clean();
    CBattleEntity::Die();
    if (retainedCorpse_)
    {
        m_OwnerID = owner;
        if (pendingRaise_)
        {
            // Includes native Reraise modifiers and effect-loss callbacks.
            SyncRecoveryView();
        }
    }
}

void CTrustEntity::OnDeathTimer()
{
    if (retainedCorpse_)
    {
        FinishRaise();
        if (auto* master = dynamic_cast<CCharEntity*>(PMaster))
        {
            master->RemoveTrust(this);
        }
        else
        {
            PAI->Despawn();
        }
        return;
    }
    CMobEntity::OnDeathTimer();
}

void CTrustEntity::Spawn()
{
    // LoadTrust calculated these contributions before Spawn. Preserve only the
    // developed profile's owned cache across the normal per-life local reset.
    constexpr std::array<const char*, 18> developmentKeys = {
        "MochiTrustJob99SummonLevel",
        "MochiTrustJob99StatLevel",
        "MochiTrustJob99BaseHP",
        "MochiTrustJob99BaseMP",
        "MochiTrustJob99BaseSTR",
        "MochiTrustJob99BaseDEX",
        "MochiTrustJob99BaseVIT",
        "MochiTrustJob99BaseAGI",
        "MochiTrustJob99BaseINT",
        "MochiTrustJob99BaseMND",
        "MochiTrustJob99BaseCHR",
        "MochiTrustJob99BaseDEF",
        "MochiTrustJob99BaseEVA",
        "MochiTrustJob99BaseATT",
        "MochiTrustJob99BaseACC",
        "MochiTrustJob99BaseRATT",
        "MochiTrustJob99BaseRACC",
        "MochiTrustJob99BaseMEVA",
    };
    std::array<uint32, developmentKeys.size()> developmentValues{};
    const bool                                 developed = trustdevelopment::IsEnabled(this);
    if (developed)
    {
        for (size_t index = 0; index < developmentKeys.size(); ++index)
        {
            developmentValues[index] = GetLocalVar(developmentKeys[index]);
        }
    }

    // NOTE: This is purposefully calling CBattleEntity's impl.
    // TODO: Calling a grand-parent's impl. of an overridden function is bad
    // we need to skip CMobEntity's spawn because it calculates stats (and our stats are already calculated)
    CBattleEntity::Spawn();
    if (developed)
    {
        for (size_t index = 0; index < developmentKeys.size(); ++index)
        {
            SetLocalVar(developmentKeys[index], developmentValues[index]);
        }
    }

    luautils::OnMobSpawn(this);

    // Recompute derived HP/MP after spawn-time modifiers (e.g. HPP/MPP)
    // and force current HP/MP to max so trusts start in a fully synchronized state.
    UpdateHealth();
    health.hp = GetMaxHP();
    health.mp = GetMaxMP();
    updatemask |= UPDATE_HP;

    static_cast<CCharEntity*>(PMaster)->pushPacket<CEntitySetNamePacket>(this);
}

bool CTrustEntity::ValidTarget(CBattleEntity* PInitiator, uint16 targetFlags)
{
    // Passive GEO trusts like Sakura etc are basically walking indicolures and cant be targeted
    if (passiveTrust_)
    {
        return false;
    }

    if (isDead())
    {
        if (!(targetFlags & TARGET_PLAYER_DEAD) || !CanReceiveRaise() || HasPendingRaise() || !PInitiator ||
            PInitiator->allegiance != allegiance || PInitiator->loc.zone != loc.zone ||
            PInitiator->PInstance != PInstance || PInitiator->PBattlefield != PBattlefield ||
            PInitiator->StatusEffectContainer->GetConfrontationEffect() != StatusEffectContainer->GetConfrontationEffect())
        {
            return false;
        }
        auto* master = static_cast<CCharEntity*>(PMaster);
        if (auto* player = dynamic_cast<CCharEntity*>(PInitiator))
        {
            return !charutils::IsAidBlocked(player, master);
        }
        if (PInitiator->objtype != TYPE_TRUST)
        {
            return false;
        }
        auto* otherMaster = dynamic_cast<CCharEntity*>(PInitiator->PMaster);
        if (otherMaster == master)
        {
            return true;
        }
        if (!otherMaster || !master->PParty || !otherMaster->PParty)
        {
            return false;
        }
        return master->PParty == otherMaster->PParty ||
               (master->PParty->m_PAlliance && master->PParty->m_PAlliance == otherMaster->PParty->m_PAlliance);
    }

    if (PInitiator->objtype == TYPE_TRUST && PMaster == PInitiator->PMaster)
    {
        return true;
    }

    if ((targetFlags & TARGET_PLAYER_PARTY_PIANISSIMO) && PInitiator->allegiance == allegiance && PMaster && PInitiator != this)
    {
        if (PInitiator->StatusEffectContainer->HasStatusEffect(xi::StatusEffect::Pianissimo))
        {
            return true;
        }
    }

    if ((targetFlags & TARGET_PLAYER_PARTY_ENTRUST) && PInitiator->allegiance == allegiance && PMaster && PInitiator != this)
    {
        return true;
    }

    if (targetFlags & TARGET_PLAYER_PARTY && PInitiator->objtype == TYPE_PET && PInitiator->allegiance == allegiance)
    {
        return true;
    }

    if (targetFlags & TARGET_PLAYER_PARTY && PInitiator->allegiance == allegiance && PMaster)
    {
        return PInitiator->PParty == PMaster->PParty;
    }

    return CMobEntity::ValidTarget(PInitiator, targetFlags);
}

void CTrustEntity::OnDespawn(CDespawnState& /*unused*/)
{
    if (GetHPP() > 0)
    {
        // Don't call this when despawning after being killed
        luautils::OnMobDespawn(this);
    }
    FadeOut();
    PAI->EventHandler.triggerListener("DESPAWN", this);
}

void CTrustEntity::OnCastFinished(CMagicState& state, action_t& action)
{
    // NOTE: This is purposefully calling CBattleEntity's impl.
    // TODO: Calling a grand-parent's impl. of an overridden function is bad
    CBattleEntity::OnCastFinished(state, action);

    auto* PSpell = state.GetSpell();

    PRecastContainer->Add(RECAST_MAGIC, static_cast<Recast>(PSpell->getID()), action.recast);
}

void CTrustEntity::OnMobSkillFinished(CMobSkillState& state, action_t& action)
{
    CMobEntity::OnMobSkillFinished(state, action);
}

void CTrustEntity::OnWeaponSkillFinished(CWeaponSkillState& state, action_t& action)
{
    // NOTE: This is purposefully calling CBattleEntity's impl.
    // TODO: Calling a grand-parent's impl. of an overridden function is bad
    CBattleEntity::OnWeaponSkillFinished(state, action);

    auto* PWeaponSkill  = state.GetSkill();
    auto* PBattleTarget = state.target().resolve<CBattleEntity>();
    if (!PBattleTarget)
    {
        return;
    }

    int16 tp = state.GetSpentTP();
    tp       = battleutils::CalculateWeaponSkillTP(this, PWeaponSkill, tp);

    if (distance(loc.p, PBattleTarget->loc.p) <= PWeaponSkill->getRange() + PBattleTarget->modelHitboxSize + modelHitboxSize)
    {
        PAI->TargetFind->reset();
        if (PWeaponSkill->isAoE())
        {
            PAI->TargetFind->findWithinArea(PBattleTarget, AOE_RADIUS::TARGET, PWeaponSkill->getRadius(), FINDFLAGS_NONE, TARGET_NONE);
        }
        else
        {
            PAI->TargetFind->findSingleTarget(PBattleTarget, FINDFLAGS_NONE, TARGET_NONE);
        }

        if (PAI->TargetFind->m_targets.size() == 0)
        {
            // There used to be an assumed interrupt handler
            // Add a test and capture before reintroducing.
            return;
        }

        for (auto&& PTarget : PAI->TargetFind->m_targets)
        {
            bool             primary      = PTarget == PBattleTarget;
            action_target_t& actionTarget = action.addTarget(PTarget->id);
            action_result_t& actionResult = actionTarget.addResult();

            uint16         tpHitsLanded    = 0;
            uint16         extraHitsLanded = 0;
            int32          damage          = 0;
            CBattleEntity* taChar          = battleutils::getAvailableTrickAttackChar(this, PTarget);

            actionResult.resolution                         = ActionResolution::Hit;
            actionResult.animation                          = PWeaponSkill->getAnimationId();
            std::tie(damage, tpHitsLanded, extraHitsLanded) = luautils::OnUseWeaponSkill(this, PTarget, PWeaponSkill, tp, primary, action, taChar);

            if (!battleutils::isValidSelfTargetWeaponskill(PWeaponSkill->getID()))
            {
                if (primary && PBattleTarget->objtype == TYPE_MOB)
                {
                    luautils::OnWeaponskillHit(PBattleTarget, this, PWeaponSkill->getID());
                }
            }
            else // Self-targetting WS restoring MP
            {
                actionResult.messageID  = primary ? MsgBasic::UsesSkillRecoversMP : MsgBasic::TargetRecoversMP;
                actionResult.resolution = ActionResolution::Hit;
                damage                  = std::max(damage, 0);
                actionResult.param      = addMP(damage);
            }

            if (primary)
            {
                if (actionResult.resolution == ActionResolution::Hit)
                {
                    if (PBattleTarget->health.hp > 0 && PWeaponSkill->getPrimarySkillchain() != 0)
                    {
                        // NOTE: GetSkillChainEffect is INSIDE this if statement because it
                        //  ALTERS the state of the resonance, which misses and non-elemental skills should NOT do.
                        const auto effect = battleutils::GetSkillChainEffect(
                            PBattleTarget,
                            PWeaponSkill->getPrimarySkillchain(),
                            PWeaponSkill->getSecondarySkillchain(),
                            PWeaponSkill->getTertiarySkillchain());
                        if (effect != ActionProcSkillChain::None)
                        {
                            actionResult.recordSkillchain(effect, battleutils::TakeSkillchainDamage(this, PBattleTarget, damage, taChar));
                        }
                    }
                }
            }
        }
    }
    else
    {
        ActionInterrupts::WeaponSkillOutOfRange(this, PBattleTarget);
    }

    this->processActionEffectFlags(action);
}

bool CTrustEntity::GetUntargetable() const
{
    // Passive GEO trusts like Sakura etc are basically walking indicolures and cant be targeted
    if (passiveTrust_)
    {
        return true;
    }

    return CMobEntity::GetUntargetable();
}
