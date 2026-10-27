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
#include "data/enums/job.h"
#include "data/enums/merit.h"

class CAbility;
class CBattleEntity;
class CTrustEntity;

namespace trustdevelopment
{

struct Profile
{
    uint32  trustId{};
    xi::Job mainJob{ xi::Job::NONE };
    xi::Job supportJob{ xi::Job::NONE };
    bool    approved{};
};

auto GetProfile(uint32 trustId) -> const Profile*;
auto HasAssignedJob(const Profile& profile, xi::Job job) -> bool;
auto GetSelectedMeritRank(uint32 trustId, xi::Merit merit) -> uint8;
auto GetDevelopedJobPointLevel(uint32 trustId, uint16 jpType) -> uint8;
auto ResolveStatScalingLevel(uint8 summonLevel, uint8 itemLevelDifference) -> uint8;
auto ReplaceBaseContribution(int32 current, int32 previousBase, int32 nextBase, int32 maximum) -> int32;
auto IsApprovedSummon(uint32 trustId, bool featureEnabled, uint32 evidenceMode, xi::Job mainJob, xi::Job supportJob) -> bool;

// Ordinary summons only. The per-Trust setting defaults off; evidence lanes
// retain their existing native behavior. Prepared profiles are not activation.
auto IsEnabled(const CTrustEntity* PTrust) -> bool;
auto HasMainJobAccess(const CBattleEntity* PEntity, xi::Job job) -> bool;
auto GetActionJobLevel(const CBattleEntity* PEntity, xi::Job job) -> uint8;
auto GetMeritValue(const CBattleEntity* PEntity, xi::Merit merit) -> int32;
auto GetJobPointLevel(const CBattleEntity* PEntity, uint16 jpType) -> uint8;

// Catalog admission only: the caller still enforces targets, resources,
// recasts, range, line of sight and the native Lua ability check.
auto CanUseAbility(const Profile& profile, xi::Job job, uint8 level, uint16 addType, xi::Merit merit) -> bool;
auto CanUseAbility(CTrustEntity* PTrust, CAbility* PAbility) -> bool;

} // namespace trustdevelopment
