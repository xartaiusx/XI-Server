/*
===========================================================================

  Copyright (c) 2026 LandSandBoat Dev Teams

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

#include "0x08e_alter_ego_points.h"

#include "enums/alter_ego_points.h"
#include "utils/charutils.h"

#include <algorithm>

namespace
{

constexpr uint8 kAlterEgoCategoryCap            = 50;
constexpr uint8 kLegacyCombatSkillsDisplayIndex = 0;
constexpr uint8 kLegacyMagicSkillsDisplayIndex  = 1;

uint8 clampUpgrade(int32 value)
{
    return static_cast<uint8>(std::clamp(value, 0, static_cast<int32>(kAlterEgoCategoryCap)));
}

uint16 nextUpgradeCost(uint8 upgrade)
{
    if (upgrade >= kAlterEgoCategoryCap)
    {
        return 0;
    }

    return static_cast<uint16>((upgrade / 10) + 1);
}

void populateCategory(CCharEntity* PChar, GP_SERV_PACKET_ALTER_EGO_POINTS::PacketData& packet, AlterEgoCategory category, const char* varName)
{
    const auto index = static_cast<uint8>(category);
    const auto rank  = clampUpgrade(charutils::GetCharVar(PChar, varName));

    packet.Upgrades[index] = rank;
    packet.Costs[index]    = nextUpgradeCost(rank);
}

void populateDisplaySlot(CCharEntity* PChar, GP_SERV_PACKET_ALTER_EGO_POINTS::PacketData& packet, uint8 index, const char* varName)
{
    const auto rank = clampUpgrade(charutils::GetCharVar(PChar, varName));

    packet.Upgrades[index] = rank;
    packet.Costs[index]    = nextUpgradeCost(rank);
}

} // namespace

GP_SERV_PACKET_ALTER_EGO_POINTS::GP_SERV_PACKET_ALTER_EGO_POINTS(CCharEntity* PChar)
{
    auto& packet = this->data();

    packet.Points = charutils::GetPoints(PChar, "alter_ego_points");
    for (auto& upgrade : packet.Upgrades)
    {
        upgrade = 0;
    }

    for (auto& cost : packet.Costs)
    {
        cost = 0;
    }

    populateCategory(PChar, packet, AlterEgoCategory::HP, "AlterEgoPoints_HP");
    populateCategory(PChar, packet, AlterEgoCategory::MP, "AlterEgoPoints_MP");
    populateCategory(PChar, packet, AlterEgoCategory::STR, "AlterEgoPoints_STR");
    populateCategory(PChar, packet, AlterEgoCategory::DEX, "AlterEgoPoints_DEX");
    populateCategory(PChar, packet, AlterEgoCategory::VIT, "AlterEgoPoints_VIT");
    populateCategory(PChar, packet, AlterEgoCategory::AGI, "AlterEgoPoints_AGI");
    populateCategory(PChar, packet, AlterEgoCategory::INT, "AlterEgoPoints_INT");
    populateCategory(PChar, packet, AlterEgoCategory::MND, "AlterEgoPoints_MND");
    populateCategory(PChar, packet, AlterEgoCategory::CHR, "AlterEgoPoints_CHR");
    populateCategory(PChar, packet, AlterEgoCategory::COMBAT_SKILLS, "AlterEgoPoints_CombatSkills");
    populateCategory(PChar, packet, AlterEgoCategory::MAGIC_SKILLS, "AlterEgoPoints_MagicSkills");

    // Older local testing initially treated the two skill rows as visible menu
    // slots. Keep those aliases populated while the client-kind indexes above
    // are the authoritative values used by C2S 0x00C1 and S2C 0x008E.
    populateDisplaySlot(PChar, packet, kLegacyCombatSkillsDisplayIndex, "AlterEgoPoints_CombatSkills");
    populateDisplaySlot(PChar, packet, kLegacyMagicSkillsDisplayIndex, "AlterEgoPoints_MagicSkills");
}
