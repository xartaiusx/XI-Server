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

#include "action.h"

#include <optional>
#include <utility>
#include <vector>

namespace actionpacket
{

inline constexpr std::size_t MaxTargets     = 15;
inline constexpr std::size_t MaxRoster      = 18;
inline constexpr std::size_t MaxPacketBytes = 256;
inline constexpr std::size_t HeaderBits     = 150; // Header, WorkSize and the complete BATTLE2 action header.

// Keep these sizes aligned with GP_SERV_COMMAND_BATTLE2::pack, including both
// optional blocks and the extra size byte passed to CBasicPacket::setSize.
inline auto TargetBits(const action_target_t& target) -> std::size_t
{
    std::size_t bits = 36; // Full target ID and result count.
    for (const auto& result : target.results)
    {
        bits += 87; // Core85 plus the proc and reaction presence bits.
        if (result.hasAdditionalEffect())
        {
            bits += 37;
        }
        if (result.spikesEffect != ActionReactKind::None)
        {
            bits += 34;
        }
    }
    return bits;
}

inline auto PaddedBytes(std::size_t bits) -> std::size_t
{
    const auto workSize = (bits + 7) / 8;
    return (workSize + 1 + 3) & ~std::size_t{ 3 };
}

// A completed ordinary party action has at most the one-PC/17-Trust roster.
// Slice only its wire representation; the caller keeps the full native action
// for effects, listeners and logging. Malformed inputs never yield partial data.
inline auto BuildBatches(const action_t& action) -> std::optional<std::vector<action_t>>
{
    if (action.actorId == 0 || action.targets.empty() || action.targets.size() > MaxRoster)
    {
        return std::nullopt;
    }

    std::vector<action_t> batches;
    auto                  batch = action;
    batch.targets.clear();
    auto bits = HeaderBits;
    for (std::size_t index = 0; index < action.targets.size(); ++index)
    {
        const auto& target = action.targets[index];
        if (target.actorId == 0 || target.results.empty() || target.results.size() > 8)
        {
            return std::nullopt;
        }
        for (std::size_t previous = 0; previous < index; ++previous)
        {
            if (action.targets[previous].actorId == target.actorId)
            {
                return std::nullopt;
            }
        }

        const auto targetBits = TargetBits(target);
        if (PaddedBytes(HeaderBits + targetBits) > MaxPacketBytes)
        {
            return std::nullopt;
        }
        if (batch.targets.size() == MaxTargets || PaddedBytes(bits + targetBits) > MaxPacketBytes)
        {
            batches.push_back(std::move(batch));
            batch = action;
            batch.targets.clear();
            bits = HeaderBits;
        }
        batch.targets.push_back(target);
        bits += targetBits;
    }
    batches.push_back(std::move(batch));
    return batches;
}

} // namespace actionpacket
