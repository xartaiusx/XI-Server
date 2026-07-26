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

#include <array>
#include <cstddef>

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
