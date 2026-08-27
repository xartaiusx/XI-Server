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
#pragma once

#include "common/cbasetypes.h"
#include "enums/party_kind.h"

#include <cstddef>
#include <optional>
#include <string_view>

class CCharEntity;
class CBattleEntity;
class CTrustEntity;
struct action_t;

namespace trustutils
{

inline constexpr std::size_t kRetailPartyMemberLimit  = 6;
inline constexpr std::size_t kFullAlliancePartyLimit  = 3;
inline constexpr std::size_t kFullAllianceMemberLimit = 18;
inline constexpr std::size_t kRetailTrustSummonLimit  = kRetailPartyMemberLimit - 1;
inline constexpr std::size_t kFullAllianceTrustLimit  = kFullAllianceMemberLimit - 1;

enum class TwillsFullAllianceState : uint8
{
    Idle     = 0,
    Spawning = 1,
    Ready    = 2,
    Failed   = 3,
};

enum class TwillsTrustEvidenceMode : uint8
{
    Idle                         = 0,
    RetailControl                = 1,
    FullAllianceQualityAssurance = 2,
};

struct TwillsFullAllianceAccessContext
{
    std::string_view characterName;
    uint8            actualGmLevel{};
    uint8            visibleGmLevel{};
    int32            entitlement{};
    bool             featureEnabled{};
    uint8            maxParties{};
};

struct TrustPartySlot
{
    uint8 partyNo{};
    uint8 memberNo{};
};

struct TrustPartyProjection
{
    PartyKind      kind{ PartyKind::Party };
    TrustPartySlot slot{};
};

auto CanUseTwillsFullAlliance(const TwillsFullAllianceAccessContext& context) -> bool;
auto CanUseTwillsFullAlliance(CCharEntity* PMaster) -> bool;
auto GetTwillsFullAllianceState(CCharEntity* PMaster) -> TwillsFullAllianceState;
auto IsTwillsFullAllianceActive(
    const TwillsFullAllianceAccessContext& context,
    TwillsFullAllianceState                state,
    TwillsTrustEvidenceMode                evidenceMode) -> bool;
auto IsTwillsFullAllianceActive(CCharEntity* PMaster) -> bool;
auto IsTwillsFullAllianceTransitionAllowed(TwillsFullAllianceState current, TwillsFullAllianceState next) -> bool;
auto SetTwillsFullAllianceState(CCharEntity* PMaster, TwillsFullAllianceState next) -> bool;
auto MapTwillsFullAllianceSlot(std::size_t globalMemberIndex) -> std::optional<TrustPartySlot>;
auto ResolveTrustPartyProjection(
    const TwillsFullAllianceAccessContext& context,
    TwillsFullAllianceState                state,
    TwillsTrustEvidenceMode                evidenceMode,
    std::size_t                            globalMemberIndex) -> std::optional<TrustPartyProjection>;
auto ResolveTrustPartyProjection(CCharEntity* PMaster, std::size_t globalMemberIndex) -> std::optional<TrustPartyProjection>;
auto ResolveTrustMemberLimit(
    const TwillsFullAllianceAccessContext& context,
    TwillsFullAllianceState                state,
    TwillsTrustEvidenceMode                evidenceMode) -> std::optional<std::size_t>;
auto ResolveTrustMemberLimit(CCharEntity* PMaster) -> std::optional<std::size_t>;
void MarkTrustEvidenceTruncated(CCharEntity* PMaster, std::string_view reason);

// We cache all of this so we don't have to hit the database every time a trust is spawned
void LoadTrustList();
auto SpawnTrust(CCharEntity* PMaster, uint32 TrustID) -> CTrustEntity*;
void LogTrustActionPacket(CBattleEntity* PActor, const action_t& action, const CBattleEntity* PPrimaryTarget, const char* source);
void LogTrustActionSkip(CBattleEntity* PActor, const CBattleEntity* PTarget, uint16 actionId, const char* source, const char* reason);

}; // namespace trustutils
