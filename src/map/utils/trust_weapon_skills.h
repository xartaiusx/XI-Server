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

class CBattleEntity;
class CTrustEntity;
class CWeaponSkill;

namespace trustweaponskills
{

// Weapon admission is separate from the complete learned job catalog and from
// transient TP/status conditions. A wrong weapon does not erase learning.
auto IsAvailableForWeapon(CTrustEntity* trust, CWeaponSkill* skill) -> bool;
auto CanUse(CTrustEntity* trust, CWeaponSkill* skill) -> bool;
auto HasFencerWeapon(CBattleEntity* entity) -> bool;

} // namespace trustweaponskills
