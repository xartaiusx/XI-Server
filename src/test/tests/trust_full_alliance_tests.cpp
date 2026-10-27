/*
===========================================================================

  Copyright (c) 2026 LandSandBoat Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

===========================================================================
*/

#include "map/utils/trustutils.h"

#include <catch2/catch_test_macros.hpp>

#include <algorithm>
#include <array>
#include <cstddef>
#include <limits>

namespace
{

auto AuthorizedTwills() -> trustutils::TwillsFullAllianceAccessContext
{
    return {
        .characterName  = "Twills",
        .actualGmLevel  = 5,
        .visibleGmLevel = 0,
        .entitlement    = 1,
        .featureEnabled = true,
        .maxParties     = 3,
    };
}

} // namespace

TEST_CASE("Twills full-alliance authorization is exact and fail-closed", "[trust][policy]")
{
    auto context = AuthorizedTwills();
    CHECK(trustutils::CanUseTwillsFullAlliance(context));
    CHECK(trustutils::IsTwillsFullAllianceActive(
        context,
        trustutils::TwillsFullAllianceState::Spawning,
        trustutils::TwillsTrustEvidenceMode::FullAllianceQualityAssurance));
    CHECK(trustutils::IsTwillsFullAllianceActive(
        context,
        trustutils::TwillsFullAllianceState::Ready,
        trustutils::TwillsTrustEvidenceMode::FullAllianceQualityAssurance));
    CHECK_FALSE(trustutils::IsTwillsFullAllianceActive(
        context,
        trustutils::TwillsFullAllianceState::Spawning,
        trustutils::TwillsTrustEvidenceMode::RetailControl));
    CHECK_FALSE(trustutils::IsTwillsFullAllianceActive(
        context,
        trustutils::TwillsFullAllianceState::Failed,
        trustutils::TwillsTrustEvidenceMode::FullAllianceQualityAssurance));

    SECTION("character name")
    {
        context.characterName = "twills";
        CHECK_FALSE(trustutils::CanUseTwillsFullAlliance(context));
    }

    SECTION("actual GM level")
    {
        context.actualGmLevel = 4;
        CHECK_FALSE(trustutils::CanUseTwillsFullAlliance(context));
        context.actualGmLevel = 6;
        CHECK_FALSE(trustutils::CanUseTwillsFullAlliance(context));
    }

    SECTION("visible GM level")
    {
        context.visibleGmLevel = 1;
        CHECK_FALSE(trustutils::CanUseTwillsFullAlliance(context));
    }

    SECTION("persisted entitlement")
    {
        context.entitlement = 0;
        CHECK_FALSE(trustutils::CanUseTwillsFullAlliance(context));
        context.entitlement = 2;
        CHECK_FALSE(trustutils::CanUseTwillsFullAlliance(context));
    }

    SECTION("feature and exact topology")
    {
        context.featureEnabled = false;
        CHECK_FALSE(trustutils::CanUseTwillsFullAlliance(context));
        context.featureEnabled = true;
        context.maxParties     = 2;
        CHECK_FALSE(trustutils::CanUseTwillsFullAlliance(context));
    }
}

TEST_CASE("Twills full-alliance session transitions reject unsafe jumps", "[trust][state]")
{
    using State = trustutils::TwillsFullAllianceState;

    CHECK(trustutils::IsTwillsFullAllianceTransitionAllowed(State::Idle, State::Spawning));
    CHECK(trustutils::IsTwillsFullAllianceTransitionAllowed(State::Spawning, State::Ready));
    CHECK(trustutils::IsTwillsFullAllianceTransitionAllowed(State::Spawning, State::Failed));
    CHECK(trustutils::IsTwillsFullAllianceTransitionAllowed(State::Ready, State::Failed));
    CHECK(trustutils::IsTwillsFullAllianceTransitionAllowed(State::Spawning, State::Idle));
    CHECK(trustutils::IsTwillsFullAllianceTransitionAllowed(State::Ready, State::Idle));
    CHECK(trustutils::IsTwillsFullAllianceTransitionAllowed(State::Failed, State::Idle));
    CHECK(trustutils::IsTwillsFullAllianceTransitionAllowed(State::Idle, State::Idle));

    CHECK_FALSE(trustutils::IsTwillsFullAllianceTransitionAllowed(State::Idle, State::Ready));
    CHECK_FALSE(trustutils::IsTwillsFullAllianceTransitionAllowed(State::Ready, State::Spawning));
    CHECK_FALSE(trustutils::IsTwillsFullAllianceTransitionAllowed(State::Failed, State::Ready));
    CHECK_FALSE(trustutils::IsTwillsFullAllianceTransitionAllowed(State::Spawning, State::Spawning));
    CHECK_FALSE(trustutils::IsTwillsFullAllianceTransitionAllowed(State::Ready, State::Ready));
    CHECK_FALSE(trustutils::IsTwillsFullAllianceTransitionAllowed(State::Failed, State::Failed));
}

TEST_CASE("Virtual Trust slots map exactly to three parties of six", "[trust][projection]")
{
    struct ExpectedSlot
    {
        std::size_t index;
        uint8       party;
        uint8       member;
    };

    constexpr std::array cases{
        ExpectedSlot{ 0, 0, 0 },
        ExpectedSlot{ 5, 0, 5 },
        ExpectedSlot{ 6, 1, 0 },
        ExpectedSlot{ 11, 1, 5 },
        ExpectedSlot{ 12, 2, 0 },
        ExpectedSlot{ 17, 2, 5 },
    };

    for (const auto& expected : cases)
    {
        const auto slot = trustutils::MapTwillsFullAllianceSlot(expected.index);
        REQUIRE(slot);
        CHECK(slot->partyNo == expected.party);
        CHECK(slot->memberNo == expected.member);
    }

    CHECK_FALSE(trustutils::MapTwillsFullAllianceSlot(18));
}

TEST_CASE("Trust party projection isolates retail and full-alliance evidence lanes", "[trust][projection]")
{
    using Mode  = trustutils::TwillsTrustEvidenceMode;
    using State = trustutils::TwillsFullAllianceState;

    auto authorized        = AuthorizedTwills();
    auto ordinary          = authorized;
    ordinary.characterName = "Ordinary";
    ordinary.actualGmLevel = 0;
    ordinary.entitlement   = 0;

    const auto ordinaryLast = trustutils::ResolveTrustPartyProjection(ordinary, State::Idle, Mode::Idle, 5);
    REQUIRE(ordinaryLast);
    CHECK(ordinaryLast->kind == PartyKind::Party);
    CHECK(ordinaryLast->slot.partyNo == 0);
    CHECK(ordinaryLast->slot.memberNo == 5);
    CHECK_FALSE(trustutils::ResolveTrustPartyProjection(ordinary, State::Idle, Mode::Idle, 6));

    const auto retailLast = trustutils::ResolveTrustPartyProjection(authorized, State::Ready, Mode::RetailControl, 5);
    REQUIRE(retailLast);
    CHECK(retailLast->kind == PartyKind::Party);
    CHECK_FALSE(trustutils::ResolveTrustPartyProjection(authorized, State::Ready, Mode::RetailControl, 6));

    std::array<std::size_t, 3> totalMembers{};
    std::array<std::size_t, 3> trustMembers{};
    for (std::size_t index = 0; index < trustutils::kFullAllianceMemberLimit; ++index)
    {
        const auto projection = trustutils::ResolveTrustPartyProjection(
            authorized,
            State::Ready,
            Mode::FullAllianceQualityAssurance,
            index);
        REQUIRE(projection);
        CHECK(projection->kind == PartyKind::Alliance);
        ++totalMembers.at(projection->slot.partyNo);
        if (index > 0)
        {
            ++trustMembers.at(projection->slot.partyNo);
        }
    }

    constexpr std::array<std::size_t, 3> expectedTotalMembers{ 6, 6, 6 };
    constexpr std::array<std::size_t, 3> expectedTrustMembers{ 5, 6, 6 };
    CHECK(totalMembers == expectedTotalMembers);
    CHECK(trustMembers == expectedTrustMembers);
    CHECK_FALSE(trustutils::ResolveTrustPartyProjection(
        authorized,
        State::Ready,
        Mode::FullAllianceQualityAssurance,
        18));

    authorized.entitlement = 0;
    CHECK_FALSE(trustutils::ResolveTrustPartyProjection(
        authorized,
        State::Ready,
        Mode::FullAllianceQualityAssurance,
        0));
    CHECK_FALSE(trustutils::ResolveTrustPartyProjection(
        AuthorizedTwills(),
        State::Failed,
        Mode::FullAllianceQualityAssurance,
        0));
}

TEST_CASE("Trust spawn member limits are state and lane aware", "[trust][spawn]")
{
    using Mode  = trustutils::TwillsTrustEvidenceMode;
    using State = trustutils::TwillsFullAllianceState;

    const auto authorized  = AuthorizedTwills();
    auto       ordinary    = authorized;
    ordinary.characterName = "Ordinary";
    ordinary.actualGmLevel = 0;
    ordinary.entitlement   = 0;

    CHECK(trustutils::ResolveTrustMemberLimit(ordinary, State::Idle, Mode::Idle) == trustutils::kRetailPartyMemberLimit);
    CHECK(trustutils::ResolveTrustMemberLimit(authorized, State::Spawning, Mode::RetailControl) == trustutils::kRetailPartyMemberLimit);
    CHECK(trustutils::ResolveTrustMemberLimit(authorized, State::Spawning, Mode::FullAllianceQualityAssurance) == trustutils::kFullAllianceMemberLimit);

    CHECK_FALSE(trustutils::ResolveTrustMemberLimit(authorized, State::Ready, Mode::RetailControl));
    CHECK_FALSE(trustutils::ResolveTrustMemberLimit(authorized, State::Ready, Mode::FullAllianceQualityAssurance));
    CHECK_FALSE(trustutils::ResolveTrustMemberLimit(ordinary, State::Spawning, Mode::FullAllianceQualityAssurance));
}

TEST_CASE("Ordinary Twills alliance admission requires exact authorization and idle solo context", "[trust][gameplay][policy]")
{
    using Mode          = trustutils::TwillsTrustEvidenceMode;
    using State         = trustutils::TwillsFullAllianceState;
    auto       context  = AuthorizedTwills();
    const auto admitted = [&context](State state = State::Idle, Mode mode = Mode::Idle, bool solo = true)
    {
        return trustutils::CanUseTwillsTrustGameplay(context, state, mode, solo);
    };
    CHECK(admitted());
    CHECK_FALSE(admitted(State::Idle, Mode::Idle, false));
    for (const auto state : { State::Spawning, State::Ready, State::Failed, static_cast<State>(255) })
    {
        CHECK_FALSE(admitted(state));
    }
    for (const auto mode : { Mode::RetailControl, Mode::FullAllianceQualityAssurance, static_cast<Mode>(255) })
    {
        CHECK_FALSE(admitted(State::Idle, mode));
    }

    SECTION("exact name")
    {
        for (const auto name : { "twills", "Twills ", "Other", "" })
        {
            context.characterName = name;
            CHECK_FALSE(admitted());
        }
    }
    SECTION("actual and visible GM levels")
    {
        for (const auto level : { uint8{ 0 }, uint8{ 4 }, uint8{ 6 }, uint8{ 255 } })
        {
            context.actualGmLevel = level;
            CHECK_FALSE(admitted());
        }
        context.actualGmLevel  = 5;
        context.visibleGmLevel = 1;
        CHECK_FALSE(admitted());
    }
    SECTION("exact persisted entitlement")
    {
        for (const auto entitlement : { -1, 0, 2 })
        {
            context.entitlement = entitlement;
            CHECK_FALSE(admitted());
        }
    }
    SECTION("feature and topology")
    {
        context.featureEnabled = false;
        CHECK_FALSE(admitted());
        context.featureEnabled = true;
        for (const auto parties : { uint8{ 0 }, uint8{ 2 }, uint8{ 4 } })
        {
            context.maxParties = parties;
            CHECK_FALSE(admitted());
        }
    }
}

TEST_CASE("Ordinary alliance projection switches at six and maps every occupied slot without overflow", "[trust][gameplay][projection]")
{
    using Mode          = trustutils::TwillsTrustEvidenceMode;
    using State         = trustutils::TwillsFullAllianceState;
    const auto context  = AuthorizedTwills();
    const bool gameplay = trustutils::CanUseTwillsTrustGameplay(context, State::Idle, Mode::Idle, true);
    REQUIRE(gameplay);

    for (const auto members : { std::size_t{ 6 }, std::size_t{ 7 }, std::size_t{ 12 }, std::size_t{ 13 }, std::size_t{ 18 } })
    {
        CAPTURE(members);
        std::array<std::array<bool, 6>, 3> occupied{};
        std::array<std::size_t, 3>         totals{};
        std::size_t                        trustCount = 0;
        for (std::size_t index = 0; index < members; ++index)
        {
            const auto projection = trustutils::ResolveTrustPartyProjection(context, State::Idle, Mode::Idle, index, gameplay, members);
            REQUIRE(projection);
            CHECK(projection->kind == (members > 6 ? PartyKind::Alliance : PartyKind::Party));
            CHECK(projection->slot.partyNo == index / 6);
            CHECK(projection->slot.memberNo == index % 6);
            CHECK_FALSE(occupied.at(projection->slot.partyNo).at(projection->slot.memberNo));
            occupied.at(projection->slot.partyNo).at(projection->slot.memberNo) = true;
            ++totals.at(projection->slot.partyNo);
            trustCount += index > 0;
        }
        CHECK(trustCount == members - 1);
        CHECK(totals[0] == 6);
        CHECK(totals[1] == (members > 6 ? std::min<std::size_t>(members - 6, 6) : 0));
        CHECK(totals[2] == (members > 12 ? members - 12 : 0));
        CHECK_FALSE(trustutils::ResolveTrustPartyProjection(context, State::Idle, Mode::Idle, members, gameplay, members));
    }
    // One PC plus seventeen Trusts fills eighteen slots. An eighteenth Trust
    // cannot acquire a projection, even if the supplied roster count is wrong.
    CHECK_FALSE(trustutils::ResolveTrustPartyProjection(context, State::Idle, Mode::Idle, 18, gameplay, 18));
    CHECK_FALSE(trustutils::ResolveTrustPartyProjection(context, State::Idle, Mode::Idle, 18, gameplay, 19));
    CHECK_FALSE(trustutils::ResolveTrustPartyProjection(context, State::Idle, Mode::Idle, 0, gameplay, 19));
    CHECK_FALSE(trustutils::ResolveTrustPartyProjection(context, State::Idle, Mode::Idle, 0, gameplay, 0));
    CHECK_FALSE(trustutils::ResolveTrustPartyProjection(context, State::Idle, Mode::Idle, std::numeric_limits<std::size_t>::max(), gameplay, 18));
}

TEST_CASE("Ordinary expansion cannot increase retail or QA admission or bypass failed context", "[trust][gameplay][spawn]")
{
    using Mode         = trustutils::TwillsTrustEvidenceMode;
    using State        = trustutils::TwillsFullAllianceState;
    const auto context = AuthorizedTwills();
    CHECK(trustutils::ResolveTrustMemberLimit(context, State::Idle, Mode::Idle, true) == 18);
    CHECK(trustutils::ResolveTrustMemberLimit(context, State::Idle, Mode::Idle, false) == 6);
    CHECK_FALSE(trustutils::ResolveTrustPartyProjection(context, State::Idle, Mode::Idle, 6, false, 18));

    // Existing evidence lanes keep their previous independent semantics.
    CHECK(trustutils::ResolveTrustMemberLimit(context, State::Spawning, Mode::RetailControl, true) == 6);
    CHECK(trustutils::ResolveTrustMemberLimit(context, State::Spawning, Mode::FullAllianceQualityAssurance, true) == 18);
    CHECK_FALSE(trustutils::ResolveTrustMemberLimit(context, State::Ready, Mode::RetailControl, true));
    CHECK_FALSE(trustutils::ResolveTrustMemberLimit(context, State::Ready, Mode::FullAllianceQualityAssurance, true));
    CHECK_FALSE(trustutils::ResolveTrustMemberLimit(context, State::Spawning, Mode::Idle, true));
    CHECK_FALSE(trustutils::ResolveTrustMemberLimit(context, State::Failed, Mode::Idle, true));
    CHECK_FALSE(trustutils::ResolveTrustPartyProjection(context, State::Ready, Mode::RetailControl, 6, true, 18));
    const auto retail = trustutils::ResolveTrustPartyProjection(context, State::Ready, Mode::RetailControl, 5, true, 18);
    REQUIRE(retail);
    CHECK(retail->kind == PartyKind::Party);
    const auto qa = trustutils::ResolveTrustPartyProjection(context, State::Ready, Mode::FullAllianceQualityAssurance, 17, true, 1);
    REQUIRE(qa);
    CHECK(qa->kind == PartyKind::Alliance);
    CHECK(qa->slot.partyNo == 2);
    CHECK(qa->slot.memberNo == 5);

    auto unauthorized        = context;
    unauthorized.entitlement = 0;
    CHECK(trustutils::ResolveTrustMemberLimit(unauthorized, State::Idle, Mode::Idle, true) == 6);
    CHECK_FALSE(trustutils::ResolveTrustPartyProjection(unauthorized, State::Idle, Mode::Idle, 6, true, 18));
    CHECK_FALSE(trustutils::ResolveTrustMemberLimit(context, State::Idle, static_cast<Mode>(255), true));
}
