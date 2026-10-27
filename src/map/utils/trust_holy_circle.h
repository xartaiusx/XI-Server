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

#pragma once

#include "common/cbasetypes.h"

class CBattleEntity;

namespace trustholycircle
{

auto IsApprovedSource(uint16 sourceType, uint32 sourceParameter, uint32 originId) -> bool;
auto ResolveMultiplier(int32 outgoingBonus, int32 incomingResistance, bool actorNotorious, bool targetNotorious) -> double;
auto GetMultiplier(const CBattleEntity* actor, const CBattleEntity* target) -> double;
auto Apply(const CBattleEntity* actor, const CBattleEntity* target, int32 damage) -> int32;

} // namespace trustholycircle
