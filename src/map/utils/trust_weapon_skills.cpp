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

#include "trust_weapon_skills.h"

#include "entities/trust_entity.h"
#include "items/item_weapon.h"
#include "status_effect_container.h"
#include "trust_job_development.h"
#include "weapon_skill.h"

#include <array>
#include <utility>

namespace trustweaponskills
{
namespace
{

constexpr std::array meritSkills{
    std::pair{ uint16{ 15 }, xi::Merit::ShijinSpiral },
    std::pair{ uint16{ 60 }, xi::Merit::Resolution },
    std::pair{ uint16{ 77 }, xi::Merit::Ruinator },
    std::pair{ uint16{ 93 }, xi::Merit::Upheaval },
    std::pair{ uint16{ 109 }, xi::Merit::Entropy },
    std::pair{ uint16{ 125 }, xi::Merit::Stardiver },
    std::pair{ uint16{ 141 }, xi::Merit::BladeShun },
    std::pair{ uint16{ 157 }, xi::Merit::TachiShoha },
    std::pair{ uint16{ 174 }, xi::Merit::Realmrazer },
    std::pair{ uint16{ 191 }, xi::Merit::Shattersoul },
    std::pair{ uint16{ 203 }, xi::Merit::ApexArrow },
    std::pair{ uint16{ 221 }, xi::Merit::LastStand },
    std::pair{ uint16{ 224 }, xi::Merit::Exenterator },
    std::pair{ uint16{ 226 }, xi::Merit::Requiescat },
};

} // namespace

auto IsAvailableForWeapon(CTrustEntity* trust, CWeaponSkill* skill) -> bool
{
    if (!trustdevelopment::IsEnabled(trust) || !skill)
    {
        return false;
    }

    const auto  type   = static_cast<xi::SkillType>(skill->getType());
    const bool  ranged = type == xi::SkillType::Archery || type == xi::SkillType::Marksmanship;
    const auto* weapon = dynamic_cast<CItemWeapon*>(trust->m_Weapons[ranged ? SLOT_RANGED : SLOT_MAIN]);
    if (!weapon || type == xi::SkillType::None || weapon->getSkillType() != type || trust->GetSkill(type) < skill->getSkillLevel())
    {
        return false;
    }

    const auto* profile   = trustdevelopment::GetProfile(trust->trustID());
    const bool  signature = trust->trustID() == 910 && skill->getID() == 238; // Uriel Blade
    if (!signature && skill->getJob(profile->mainJob) == 0 && skill->getJob(profile->supportJob) == 0)
    {
        // Equipment-only WSs, including Knights of Round, are not job unlocks.
        return false;
    }
    for (const auto& [id, merit] : meritSkills)
    {
        if (skill->getID() == id && trustdevelopment::GetSelectedMeritRank(trust->trustID(), merit) == 0)
        {
            return false;
        }
    }

    // The approved developed-job catalog includes normal quest/permanent WS
    // unlocks. Actual weapon type remains authoritative; no weapon is swapped.
    return true;
}

auto CanUse(CTrustEntity* trust, CWeaponSkill* skill) -> bool
{
    if (!IsAvailableForWeapon(trust, skill) || !trust->isAlive() || trust->health.tp < 1000 ||
        trust->StatusEffectContainer->HasPreventActionEffect() || trust->StatusEffectContainer->HasStatusEffect(xi::StatusEffect::Amnesia))
    {
        return false;
    }
    const auto* impairment = trust->StatusEffectContainer->GetStatusEffect(xi::StatusEffect::Impairment);
    return !impairment || (impairment->GetPower() != 2 && impairment->GetPower() != 3);
}

auto HasFencerWeapon(CBattleEntity* entity) -> bool
{
    auto* trust = dynamic_cast<CTrustEntity*>(entity);
    if (!trustdevelopment::IsEnabled(trust))
    {
        return false;
    }
    const auto* main = dynamic_cast<CItemWeapon*>(trust->m_Weapons[SLOT_MAIN]);
    const auto* sub  = dynamic_cast<CItemWeapon*>(trust->m_Weapons[SLOT_SUB]);
    return main && main->getSkillType() != xi::SkillType::None && !main->isTwoHanded() && !main->isHandToHand() &&
           (!sub || sub->getSkillType() == xi::SkillType::None);
}

} // namespace trustweaponskills
