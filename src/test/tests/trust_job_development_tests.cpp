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

#include "map/ability.h"
#include "map/data/datasets/merits/dataset.h"
#include "map/utils/dataset_loader.h"
#include "map/utils/trust_job_development.h"

#include <catch2/catch_test_macros.hpp>

#include <algorithm>
#include <array>
#include <limits>
#include <map>
#include <utility>

using namespace trustdevelopment;

TEST_CASE("Trust development activation excludes unapproved variants and evidence lanes", "[trust][development]")
{
    REQUIRE(GetProfile(910));
    REQUIRE(GetProfile(1018));
    CHECK(GetProfile(9999) == nullptr);
    CHECK(GetProfile(910)->mainJob == xi::Job::PLD);
    CHECK(GetProfile(910)->supportJob == xi::Job::WAR);
    CHECK(IsApprovedSummon(910, true, 0, xi::Job::PLD, xi::Job::WAR));
    CHECK_FALSE(IsApprovedSummon(910, false, 0, xi::Job::PLD, xi::Job::WAR));
    CHECK_FALSE(IsApprovedSummon(910, true, 1, xi::Job::PLD, xi::Job::WAR));
    CHECK_FALSE(IsApprovedSummon(910, true, 2, xi::Job::PLD, xi::Job::WAR));
    CHECK_FALSE(IsApprovedSummon(910, true, 255, xi::Job::PLD, xi::Job::WAR));
    CHECK_FALSE(IsApprovedSummon(910, true, 0, xi::Job::PLD, xi::Job::NONE));
    CHECK_FALSE(IsApprovedSummon(910, true, 0, xi::Job::WAR, xi::Job::PLD));
    CHECK_FALSE(IsApprovedSummon(1018, true, 0, xi::Job::SAM, xi::Job::WHM));
    CHECK_FALSE(IsApprovedSummon(9999, true, 0, xi::Job::PLD, xi::Job::WAR));
    CHECK_FALSE(HasAssignedJob(*GetProfile(910), xi::Job::NONE));
    CHECK_FALSE(HasAssignedJob(*GetProfile(910), xi::Job::BLM));
}

TEST_CASE("Trust scaling uses a regular-level snapshot and native item-level difference capped at119", "[trust][development]")
{
    CHECK(ResolveStatScalingLevel(1, 20) == 1);
    CHECK(ResolveStatScalingLevel(50, 20) == 50);
    CHECK(ResolveStatScalingLevel(98, 20) == 98);
    CHECK(ResolveStatScalingLevel(99, 0) == 99);
    CHECK(ResolveStatScalingLevel(99, 1) == 100);
    CHECK(ResolveStatScalingLevel(99, 19) == 118);
    CHECK(ResolveStatScalingLevel(99, 20) == 119);
    CHECK(ResolveStatScalingLevel(99, 255) == 119);
    CHECK(ResolveStatScalingLevel(0, 20) == 1);
}

TEST_CASE("Trust base refresh preserves separate additions and cannot accumulate base modifiers", "[trust][development]")
{
    const auto raised = ReplaceBaseContribution(117, 100, 140, 65535);
    CHECK(raised == 157); // Existing17 earned points remain separate.
    CHECK(ReplaceBaseContribution(raised, 140, 140, 65535) == raised);
    CHECK(ReplaceBaseContribution(raised, 140, 100, 65535) == 117);
    CHECK(ReplaceBaseContribution(2, 100, 1, 65535) == 0);
    CHECK(ReplaceBaseContribution(65530, 100, 140, 65535) == 65535);
    CHECK(ReplaceBaseContribution(std::numeric_limits<int32>::max(), 1, 100, std::numeric_limits<int32>::max()) == std::numeric_limits<int32>::max());
}

TEST_CASE("Trust JP grants cover exactly ten categories of each approved assigned job", "[trust][development]")
{
    for (const auto base : { uint16{ 0x20 }, uint16{ 0xE0 } })
    {
        for (uint16 offset = 0; offset < 10; ++offset)
        {
            CHECK(GetDevelopedJobPointLevel(910, base + offset) == 20);
        }
        CHECK(GetDevelopedJobPointLevel(910, base - 1) == 0);
        CHECK(GetDevelopedJobPointLevel(910, base + 10) == 0);
        CHECK(GetDevelopedJobPointLevel(910, base + 31) == 0);
    }
    CHECK(GetDevelopedJobPointLevel(910, 0x80) == 0); // BLM
    CHECK(GetDevelopedJobPointLevel(910, 0xFFFF) == 0);
    CHECK(GetDevelopedJobPointLevel(1018, 0x180) == 0); // Prepared SAM is inactive.
    CHECK(GetDevelopedJobPointLevel(9999, 0x20) == 0);
}

TEST_CASE("Trust merit profiles fit native group caps and use native scaled values", "[trust][development][data]")
{
    const auto records = xi::data::loadDataset<xi::data::datasets::merits::Dataset>();
    for (const auto id : { uint32{ 910 }, uint32{ 1018 } })
    {
        std::map<uint16, uint16> totals;
        for (const auto& entry : records.Entries)
        {
            const auto rank = GetSelectedMeritRank(id, entry.Id);
            CHECK(rank <= entry.MaxUpgrades);
            totals[std::to_underlying(entry.Category)] += rank;
        }
        for (const auto& category : records.Categories)
        {
            CHECK(totals[std::to_underlying(category.Id)] <= category.MaxUpgrades);
        }
        CHECK(totals[0x0680] == 15);
        if (id == 910)
        {
            CHECK(totals[0x0180] == 10);
            CHECK(totals[0x0800] == 10);
            CHECK(totals[0x0300] == 10);
            CHECK(totals[0x0980] == 10);
        }
        else
        {
            CHECK(totals[0x0200] == 10);
            CHECK(totals[0x0880] == 10);
            CHECK(totals[0x0440] == 10);
            CHECK(totals[0x0AC0] == 10);
        }
    }
    const auto scaled = [&records](xi::Merit merit)
    {
        const auto entry = std::ranges::find(records.Entries, merit, &xi::data::MeritData::Id);
        REQUIRE(entry != records.Entries.end());
        return GetSelectedMeritRank(910, merit) * entry->Value;
    };
    CHECK(scaled(xi::Merit::SentinelRecast) == 50);
    CHECK(scaled(xi::Merit::DefenderRecast) == 30);
    CHECK(scaled(xi::Merit::IronWill) == 57);
    CHECK(scaled(xi::Merit::Guardian) == 95);
    CHECK(scaled(xi::Merit::Savagery) == 500);
    CHECK(scaled(xi::Merit::Fealty) == 5);
    CHECK(scaled(xi::Merit::Chivalry) == 5);
    CHECK(scaled(xi::Merit::Requiescat) == 15);
    CHECK(GetSelectedMeritRank(910, xi::Merit::AggressiveAim) == 0);
    CHECK(GetSelectedMeritRank(910, xi::Merit::MaxHp) == 0);
    CHECK(GetSelectedMeritRank(9999, xi::Merit::Fealty) == 0);
}

TEST_CASE("Valaineral admits all13PLD and12WAR native ability definitions including shared SPs", "[trust][development]")
{
    struct AbilityCase
    {
        uint16    id;
        xi::Job   job;
        uint8     level;
        uint16    addType;
        xi::Merit merit;
    };

    constexpr auto       none = static_cast<xi::Merit>(0);
    constexpr std::array cases{
        AbilityCase{ 16, xi::Job::WAR, 0, ADDTYPE_NORMAL, none },
        AbilityCase{ 31, xi::Job::WAR, 15, ADDTYPE_NORMAL, none },
        AbilityCase{ 32, xi::Job::WAR, 35, ADDTYPE_NORMAL, none },
        AbilityCase{ 33, xi::Job::WAR, 25, ADDTYPE_NORMAL, none },
        AbilityCase{ 34, xi::Job::WAR, 45, ADDTYPE_NORMAL, none },
        AbilityCase{ 35, xi::Job::WAR, 5, ADDTYPE_NORMAL, none },
        AbilityCase{ 149, xi::Job::WAR, 75, ADDTYPE_MERIT, xi::Merit::WarriorsCharge },
        AbilityCase{ 150, xi::Job::WAR, 75, ADDTYPE_MERIT, xi::Merit::Tomahawk },
        AbilityCase{ 226, xi::Job::WAR, 60, ADDTYPE_NORMAL, none },
        AbilityCase{ 252, xi::Job::WAR, 77, ADDTYPE_NORMAL, none },
        AbilityCase{ 267, xi::Job::WAR, 87, ADDTYPE_NORMAL, none },
        AbilityCase{ 323, xi::Job::WAR, 96, ADDTYPE_NORMAL, none },
        AbilityCase{ 22, xi::Job::PLD, 0, ADDTYPE_NORMAL, none },
        AbilityCase{ 46, xi::Job::PLD, 15, ADDTYPE_NORMAL, none },
        AbilityCase{ 47, xi::Job::PLD, 5, ADDTYPE_NORMAL, none },
        AbilityCase{ 48, xi::Job::PLD, 30, ADDTYPE_NORMAL, none },
        AbilityCase{ 79, xi::Job::PLD, 35, ADDTYPE_NORMAL, none },
        AbilityCase{ 92, xi::Job::PLD, 62, ADDTYPE_NORMAL, none },
        AbilityCase{ 157, xi::Job::PLD, 75, ADDTYPE_MERIT, xi::Merit::Fealty },
        AbilityCase{ 158, xi::Job::PLD, 75, ADDTYPE_MERIT, xi::Merit::Chivalry },
        AbilityCase{ 255, xi::Job::PLD, 78, ADDTYPE_NORMAL, none },
        AbilityCase{ 277, xi::Job::PLD, 87, ADDTYPE_NORMAL, none },
        AbilityCase{ 278, xi::Job::PLD, 95, ADDTYPE_NORMAL, none },
        AbilityCase{ 329, xi::Job::PLD, 96, ADDTYPE_NORMAL, none },
        AbilityCase{ 394, xi::Job::PLD, 70, ADDTYPE_NORMAL, none },
    };
    const auto& profile = *GetProfile(910);
    for (const auto& entry : cases)
    {
        CAPTURE(entry.id);
        CHECK(CanUseAbility(profile, entry.job, entry.level, entry.addType, entry.merit));
    }
    CHECK(CanUseAbility(profile, xi::Job::WAR, 99, ADDTYPE_MAIN_ONLY, none));
    CHECK_FALSE(CanUseAbility(profile, xi::Job::BLM, 1, ADDTYPE_NORMAL, none));
    CHECK_FALSE(CanUseAbility(profile, xi::Job::PLD, 100, ADDTYPE_NORMAL, none));
    CHECK_FALSE(CanUseAbility(profile, xi::Job::WAR, 75, ADDTYPE_MERIT, xi::Merit::AggressiveAim));
    for (const auto flags : { ADDTYPE_LEARNED, ADDTYPE_ASTRAL_FLOW, ADDTYPE_LIGHT_ARTS, ADDTYPE_DARK_ARTS, ADDTYPE_JUGPET, ADDTYPE_CHARMPET, ADDTYPE_AVATAR, ADDTYPE_AUTOMATON })
    {
        CHECK_FALSE(CanUseAbility(profile, xi::Job::WAR, 1, flags, none));
    }
    CHECK_FALSE(CanUseAbility(*GetProfile(1018), xi::Job::SAM, 1, ADDTYPE_NORMAL, none));
}
