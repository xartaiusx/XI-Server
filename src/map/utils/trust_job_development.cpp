/*
===========================================================================
  Copyright (c) 2026 xartaiusx

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program. If not, see <https://www.gnu.org/licenses/>.
===========================================================================
*/

#include "trust_job_development.h"

#include "ability.h"
#include "common/settings.h"
#include "entities/char_entity.h"
#include "entities/trust_entity.h"
#include "merit.h"

#include <algorithm>
#include <array>

namespace
{

constexpr std::array profiles{
    trustdevelopment::Profile{ 910, xi::Job::PLD, xi::Job::WAR, true },
    trustdevelopment::Profile{ 1018, xi::Job::SAM, xi::Job::WHM, false },
};

struct MeritAllocation
{
    xi::Merit merit;
    uint8     rank;
};

// Each job group totals ten; the shared weapon-skill allocation totals fifteen.
// Values are read from the already-loaded native merits dataset, not duplicated.
constexpr std::array valaineralMerits{
    MeritAllocation{ xi::Merit::SentinelRecast, 5 },
    MeritAllocation{ xi::Merit::RampartRecast, 5 },
    MeritAllocation{ xi::Merit::Fealty, 1 },
    MeritAllocation{ xi::Merit::Chivalry, 1 },
    MeritAllocation{ xi::Merit::IronWill, 3 },
    MeritAllocation{ xi::Merit::Guardian, 5 },
    MeritAllocation{ xi::Merit::DefenderRecast, 5 },
    MeritAllocation{ xi::Merit::WarcryRecast, 5 },
    MeritAllocation{ xi::Merit::WarriorsCharge, 4 },
    MeritAllocation{ xi::Merit::Tomahawk, 1 },
    MeritAllocation{ xi::Merit::Savagery, 5 },
    MeritAllocation{ xi::Merit::Requiescat, 5 },
    MeritAllocation{ xi::Merit::Resolution, 3 },
    MeritAllocation{ xi::Merit::Exenterator, 1 },
    MeritAllocation{ xi::Merit::Ruinator, 1 },
    MeritAllocation{ xi::Merit::Upheaval, 1 },
    MeritAllocation{ xi::Merit::Entropy, 1 },
    MeritAllocation{ xi::Merit::Stardiver, 1 },
    MeritAllocation{ xi::Merit::Realmrazer, 1 },
    MeritAllocation{ xi::Merit::Shattersoul, 1 },
};

// Preparation only; Iroha II remains inactive in GetProfile/IsEnabled.
constexpr std::array irohaMerits{
    MeritAllocation{ xi::Merit::MeditateRecast, 5 },
    MeritAllocation{ xi::Merit::StoreTpEffect, 5 },
    MeritAllocation{ xi::Merit::Shikikoyo, 1 },
    MeritAllocation{ xi::Merit::BladeBash, 1 },
    MeritAllocation{ xi::Merit::Ikishoten, 3 },
    MeritAllocation{ xi::Merit::Overwhelm, 5 },
    MeritAllocation{ xi::Merit::CureCastTime, 5 },
    MeritAllocation{ xi::Merit::RegenEffect, 5 },
    MeritAllocation{ xi::Merit::Martyr, 1 },
    MeritAllocation{ xi::Merit::Devotion, 3 },
    MeritAllocation{ xi::Merit::AnimusSolace, 5 },
    MeritAllocation{ xi::Merit::AnimusMisery, 1 },
    MeritAllocation{ xi::Merit::Stardiver, 5 },
    MeritAllocation{ xi::Merit::TachiShoha, 5 },
    MeritAllocation{ xi::Merit::Realmrazer, 2 },
    MeritAllocation{ xi::Merit::Requiescat, 1 },
    MeritAllocation{ xi::Merit::Shattersoul, 1 },
    MeritAllocation{ xi::Merit::ApexArrow, 1 },
};

} // namespace

namespace trustdevelopment
{

auto GetProfile(uint32 trustId) -> const Profile*
{
    const auto entry = std::ranges::find(profiles, trustId, &Profile::trustId);
    return entry == profiles.end() ? nullptr : &*entry;
}

auto HasAssignedJob(const Profile& profile, xi::Job job) -> bool
{
    return job != xi::Job::NONE && (job == profile.mainJob || job == profile.supportJob);
}

auto GetSelectedMeritRank(uint32 trustId, xi::Merit merit) -> uint8
{
    if (trustId == 1018)
    {
        const auto entry = std::ranges::find(irohaMerits, merit, &MeritAllocation::merit);
        return entry == irohaMerits.end() ? 0 : entry->rank;
    }
    if (trustId != 910)
    {
        return 0;
    }
    const auto entry = std::ranges::find(valaineralMerits, merit, &MeritAllocation::merit);
    return entry == valaineralMerits.end() ? 0 : entry->rank;
}

auto GetDevelopedJobPointLevel(uint32 trustId, uint16 jpType) -> uint8
{
    const auto* profile = GetProfile(trustId);
    if (!profile || !profile->approved)
    {
        return 0;
    }
    for (const auto job : { profile->mainJob, profile->supportJob })
    {
        const auto base = static_cast<uint16>(job) * 0x20;
        if (job != xi::Job::NONE && jpType >= base && jpType < base + 10)
        {
            return 20;
        }
    }
    return 0;
}

auto ResolveStatScalingLevel(uint8 summonLevel, uint8 itemLevelDifference) -> uint8
{
    return summonLevel < 99 ? std::max<uint8>(summonLevel, 1) : 99 + std::min<uint8>(itemLevelDifference, 20);
}

auto ReplaceBaseContribution(int32 current, int32 previousBase, int32 nextBase, int32 maximum) -> int32
{
    return static_cast<int32>(std::clamp<int64>(static_cast<int64>(current) + nextBase - previousBase, 0, std::max(maximum, 0)));
}

auto IsApprovedSummon(uint32 trustId, bool featureEnabled, uint32 evidenceMode, xi::Job mainJob, xi::Job supportJob) -> bool
{
    const auto* profile = GetProfile(trustId);
    return featureEnabled && evidenceMode == 0 && profile && profile->approved && mainJob == profile->mainJob && supportJob == profile->supportJob;
}

auto IsEnabled(const CTrustEntity* PTrust) -> bool
{
    if (!PTrust || !settings::get<bool>("main.TRUST_JOB99_VALAINERAL"))
    {
        return false;
    }
    const auto* master = dynamic_cast<const CCharEntity*>(PTrust->PMaster);
    return master && IsApprovedSummon(PTrust->trustID(), true, master->GetLocalVar("MochiriiTrustEvidenceMode"), PTrust->GetMJob(), PTrust->GetSJob());
}

auto HasMainJobAccess(const CBattleEntity* PEntity, xi::Job job) -> bool
{
    if (!PEntity || job == xi::Job::NONE)
    {
        return false;
    }
    if (const auto* trust = dynamic_cast<const CTrustEntity*>(PEntity); IsEnabled(trust))
    {
        return HasAssignedJob(*GetProfile(trust->trustID()), job);
    }
    return PEntity->GetMJob() == job;
}

auto GetActionJobLevel(const CBattleEntity* PEntity, xi::Job job) -> uint8
{
    if (!PEntity || job == xi::Job::NONE)
    {
        return 0;
    }
    if (const auto* trust = dynamic_cast<const CTrustEntity*>(PEntity); IsEnabled(trust) && HasAssignedJob(*GetProfile(trust->trustID()), job))
    {
        return 99;
    }
    return PEntity->GetMJob() == job ? PEntity->GetMLevel() : PEntity->GetSJob() == job ? PEntity->GetSLevel()
                                                                                        : 0;
}

auto GetMeritValue(const CBattleEntity* PEntity, xi::Merit merit) -> int32
{
    const auto* trust = dynamic_cast<const CTrustEntity*>(PEntity);
    if (!IsEnabled(trust))
    {
        return 0;
    }
    const auto* definition = meritNameSpace::GetMeritDefinition(merit);
    return definition ? std::min(GetSelectedMeritRank(trust->trustID(), merit), definition->upgrade) * definition->value : 0;
}

auto GetJobPointLevel(const CBattleEntity* PEntity, uint16 jpType) -> uint8
{
    const auto* trust = dynamic_cast<const CTrustEntity*>(PEntity);
    return IsEnabled(trust) ? GetDevelopedJobPointLevel(trust->trustID(), jpType) : 0;
}

auto CanUseAbility(const Profile& profile, xi::Job job, uint8 level, uint16 addType, xi::Merit merit) -> bool
{
    constexpr auto supportedTypes = ADDTYPE_MAIN_ONLY | ADDTYPE_MERIT;
    return profile.approved && HasAssignedJob(profile, job) && level <= 99 && (addType & ~supportedTypes) == 0 &&
           (!(addType & ADDTYPE_MERIT) || GetSelectedMeritRank(profile.trustId, merit) > 0);
}

auto CanUseAbility(CTrustEntity* PTrust, CAbility* PAbility) -> bool
{
    // Ability states copy the catalog entry before adjusting recast/enmity.
    // Admit its immutable catalog identity, not the address of that copy.
    auto* definition = PAbility ? ability::GetAbility(PAbility->getID()) : nullptr;
    if (!IsEnabled(PTrust) || !definition || definition->isPetAbility())
    {
        return false;
    }
    if ((definition->getAddType() & ADDTYPE_MERIT) && GetMeritValue(PTrust, static_cast<xi::Merit>(definition->getMeritModID())) == 0)
    {
        return false;
    }
    return CanUseAbility(*GetProfile(PTrust->trustID()), definition->getJob(), definition->getLevel(), definition->getAddType(), static_cast<xi::Merit>(definition->getMeritModID()));
}

} // namespace trustdevelopment
