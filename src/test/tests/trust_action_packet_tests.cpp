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

#include "map/action/action_packet_batch.h"
#include "map/packets/s2c/0x028_battle2.h"

#include <catch2/catch_test_macros.hpp>

namespace
{

auto MakeAction(std::size_t count) -> action_t
{
    action_t action{
        .actorId    = 90,
        .actiontype = ActionCategory::MagicFinish,
        .actionid   = 49,
        .recast     = 10s,
        .spellgroup = SPELLGROUP_WHITE,
    };
    for (std::size_t index = 0; index < count; ++index)
    {
        auto& target     = action.addTarget(static_cast<uint32>(100 + index));
        auto& result     = target.addResult();
        result.param     = static_cast<int32>(index + 1);
        result.messageID = MsgBasic::MagicGainsEffect;
    }
    return action;
}

void CheckPacket(action_t batch)
{
    std::size_t bits = actionpacket::HeaderBits;
    for (const auto& target : batch.targets)
    {
        bits += actionpacket::TargetBits(target);
    }
    GP_SERV_COMMAND_BATTLE2 packet(batch);
    REQUIRE(packet.getSize() == actionpacket::PaddedBytes(bits));
    REQUIRE(packet.getSize() <= actionpacket::MaxPacketBytes);
    REQUIRE(packet.ref<uint8>(0x04) == (bits + 7) / 8);
    REQUIRE(static_cast<std::size_t>(packet.ref<uint8>(0x04)) + 1 <= 256);

    auto* data = &packet.ref<uint8>(0);
    REQUIRE(unpackBitsBE(data, 40, 32) == batch.actorId);
    REQUIRE(unpackBitsBE(data, 72, 6) == batch.targets.size());
    uint32 offset = actionpacket::HeaderBits;
    for (const auto& target : batch.targets)
    {
        REQUIRE(unpackBitsBE(data, offset, 32) == target.actorId);
        offset += 32;
        REQUIRE(unpackBitsBE(data, offset, 4) == target.results.size());
        offset += 4;
        for (const auto& result : target.results)
        {
            REQUIRE(unpackBitsBE(data, offset + 27, 17) == result.param);
            offset += 85;
            REQUIRE(unpackBitsBE(data, offset, 1) == static_cast<uint64>(result.hasAdditionalEffect()));
            offset += 1;
            if (result.hasAdditionalEffect())
            {
                REQUIRE(unpackBitsBE(data, offset + 10, 17) == result.addEffectParam);
                offset += 37;
            }
            REQUIRE(unpackBitsBE(data, offset, 1) == static_cast<uint64>(result.spikesEffect != ActionReactKind::None));
            offset += 1;
            if (result.spikesEffect != ActionReactKind::None)
            {
                REQUIRE(unpackBitsBE(data, offset + 10, 14) == result.spikesParam);
                offset += 34;
            }
        }
    }
    REQUIRE(offset == bits);
}

} // namespace

TEST_CASE("Ordinary Trust party packets preserve every recipient in order", "[trust][action][packet]")
{
    for (std::size_t count = 15; count <= 18; ++count)
    {
        for (const auto category : { ActionCategory::MagicFinish, ActionCategory::AbilityFinish })
        {
            auto action        = MakeAction(count);
            action.actiontype  = category;
            const auto batches = actionpacket::BuildBatches(action);
            REQUIRE(batches);
            REQUIRE(batches->size() == (count == 15 ? 1 : 2));
            std::size_t targetIndex = 0;
            for (const auto& batch : *batches)
            {
                REQUIRE(batch.actorId == action.actorId);
                REQUIRE(batch.actiontype == action.actiontype);
                REQUIRE(batch.actionid == action.actionid);
                REQUIRE(batch.recast == action.recast);
                REQUIRE(batch.spellgroup == action.spellgroup);
                REQUIRE(batch.targets.size() <= 15);
                for (const auto& target : batch.targets)
                {
                    REQUIRE(target.actorId == action.targets[targetIndex].actorId);
                    REQUIRE(target.results.size() == 1);
                    REQUIRE(target.results[0].param == action.targets[targetIndex].results[0].param);
                    REQUIRE(target.results[0].messageID == action.targets[targetIndex].results[0].messageID);
                    ++targetIndex;
                }
                CheckPacket(batch);
            }
            REQUIRE(targetIndex == action.targets.size());
            REQUIRE(action.targets.size() == count);
            REQUIRE(action.targets[0].results[0].kind == 0); // Packing copies never normalizes the native action.
            REQUIRE(action.recast == 10s);
        }
    }
}

TEST_CASE("Ordinary Trust packet budgets include every proc and reaction block", "[trust][action][packet]")
{
    auto action = MakeAction(18);
    for (auto& target : action.targets)
    {
        target.results.resize(8, target.results.front());
        for (std::size_t index = 0; index < target.results.size(); ++index)
        {
            auto& result = target.results[index];
            result.param += static_cast<int32>(index * 100);
            result.animation        = static_cast<ActionAnimation>(index + 100);
            result.additionalEffect = ActionProcAddEffect::LightDamage;
            result.addEffectInfo    = 3;
            result.addEffectParam   = result.param + 1;
            result.addEffectMessage = MsgBasic::MagicGainsEffect;
            result.spikesEffect     = ActionReactKind::Counter;
            result.spikesInfo       = 2;
            result.spikesParam      = static_cast<uint16>(result.param + 2);
            result.spikesMessage    = MsgBasic::MagicGainsEffect;
        }
        REQUIRE(actionpacket::TargetBits(target) == 36 + 8 * (87 + 37 + 34));
    }
    const auto batches = actionpacket::BuildBatches(action);
    REQUIRE(batches);
    REQUIRE(batches->size() == 18); // A second maximum-size target would exceed256 bytes.
    for (std::size_t index = 0; index < batches->size(); ++index)
    {
        const auto& batch = (*batches)[index];
        REQUIRE(batch.targets.size() == 1);
        REQUIRE(batch.targets[0].actorId == action.targets[index].actorId);
        REQUIRE(batch.targets[0].results.size() == 8);
        for (std::size_t resultIndex = 0; resultIndex < 8; ++resultIndex)
        {
            const auto& expected = action.targets[index].results[resultIndex];
            const auto& actual   = batch.targets[0].results[resultIndex];
            REQUIRE(actual.param == expected.param);
            REQUIRE(actual.animation == expected.animation);
            REQUIRE(actual.messageID == expected.messageID);
            REQUIRE(actual.additionalEffect == expected.additionalEffect);
            REQUIRE(actual.addEffectInfo == expected.addEffectInfo);
            REQUIRE(actual.addEffectParam == expected.addEffectParam);
            REQUIRE(actual.addEffectMessage == expected.addEffectMessage);
            REQUIRE(actual.spikesEffect == expected.spikesEffect);
            REQUIRE(actual.spikesInfo == expected.spikesInfo);
            REQUIRE(actual.spikesParam == expected.spikesParam);
            REQUIRE(actual.spikesMessage == expected.spikesMessage);
        }
        CheckPacket(batch);
    }
}

TEST_CASE("Ordinary Trust packet batching rejects malformed action cohorts", "[trust][action][packet]")
{
    REQUIRE_FALSE(actionpacket::BuildBatches(MakeAction(0)));
    REQUIRE_FALSE(actionpacket::BuildBatches(MakeAction(19)));
    auto action    = MakeAction(18);
    action.actorId = 0;
    REQUIRE_FALSE(actionpacket::BuildBatches(action));
    action                        = MakeAction(18);
    action.targets.back().actorId = action.targets.front().actorId;
    REQUIRE_FALSE(actionpacket::BuildBatches(action));
    action                        = MakeAction(18);
    action.targets.back().actorId = 0;
    REQUIRE_FALSE(actionpacket::BuildBatches(action));
    action = MakeAction(18);
    action.targets.back().results.clear();
    REQUIRE_FALSE(actionpacket::BuildBatches(action));
    action = MakeAction(18);
    action.targets.back().results.resize(9);
    REQUIRE_FALSE(actionpacket::BuildBatches(action));
}
