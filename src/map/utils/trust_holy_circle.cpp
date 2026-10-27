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

#include "trust_holy_circle.h"

#include "entities/battle_entity.h"
#include "entities/mob_entity.h"
#include "status_effect.h"
#include "status_effect_container.h"

#include <algorithm>
#include <cmath>
#include <limits>

namespace
{

auto HasApprovedCircle(const CBattleEntity* entity) -> bool
{
    const auto* effect = entity ? entity->StatusEffectContainer->GetStatusEffect(xi::StatusEffect::HolyCircle) : nullptr;
    return effect && trustholycircle::IsApprovedSource(effect->GetSourceType(), effect->GetSourceTypeParam(), effect->GetOriginID());
}

auto IsNotorious(const CBattleEntity* entity) -> bool
{
    // Match Lua isNM(): Trusts are not notorious monsters even though they use a mob base.
    return entity && entity->objtype == TYPE_MOB &&
           (static_cast<const CMobEntity*>(entity)->m_Type & xi::MobType::Notorious) != xi::MobType::Normal;
}

} // namespace

namespace trustholycircle
{

auto IsApprovedSource(uint16 sourceType, uint32 sourceParameter, uint32 originId) -> bool
{
    return sourceType == EffectSourceType::SOURCE_DEVELOPED_TRUST && sourceParameter == 910 && originId != 0;
}

auto ResolveMultiplier(int32 outgoingBonus, int32 incomingResistance, bool actorNotorious, bool targetNotorious) -> double
{
    // Preserve the existing Lua ecosystem model, including its integer NM halves.
    const auto bonus      = std::floor(static_cast<double>(outgoingBonus) / (targetNotorious ? 2.0 : 1.0));
    const auto resistance = std::floor(static_cast<double>(incomingResistance) / (actorNotorious ? 2.0 : 1.0));
    return std::clamp(1.0 + bonus / 100.0 - resistance / 100.0, 0.5, 1.5);
}

auto GetMultiplier(const CBattleEntity* actor, const CBattleEntity* target) -> double
{
    if (!actor || !target)
    {
        return 1.0;
    }

    const auto outgoing = target->m_EcoSystem == xi::Ecosystem::Undead && HasApprovedCircle(actor)
                              ? actor->getMod(xi::Mod::UNDEAD_DMG_MULTIPLIER)
                              : 0;
    const auto incoming = actor->m_EcoSystem == xi::Ecosystem::Undead && HasApprovedCircle(target)
                              ? target->getMod(xi::Mod::UNDEAD_RES_MULTIPLIER)
                              : 0;
    return ResolveMultiplier(outgoing, incoming, IsNotorious(actor), IsNotorious(target));
}

auto Apply(const CBattleEntity* actor, const CBattleEntity* target, int32 damage) -> int32
{
    if (damage <= 0)
    {
        return damage;
    }

    const auto adjusted = std::floor(damage * GetMultiplier(actor, target));
    return static_cast<int32>(std::clamp(adjusted, 0.0, static_cast<double>(std::numeric_limits<int32>::max())));
}

} // namespace trustholycircle
