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

#include "map/utils/trust_recovery.h"

#include <catch2/catch_test_macros.hpp>

TEST_CASE("Trust recovery separates Reraise IV from Arise", "[trust][recovery]")
{
    const auto              reraise = trustrecovery::ReraiseOptions(4);
    const TrustRaiseOptions arise{ 4, true, true };
    REQUIRE(trustrecovery::IsValid(reraise));
    REQUIRE(trustrecovery::IsValid(arise));
    REQUIRE(reraise.tier == arise.tier);
    REQUIRE(reraise.shortWeakness);
    REQUIRE_FALSE(reraise.grantReraiseIII);
    REQUIRE(arise.grantReraiseIII);
    REQUIRE(trustrecovery::WeaknessDuration(reraise) == 3min);
    REQUIRE(trustrecovery::WeaknessDuration(arise) == 3min);
}

TEST_CASE("Trust recovery returns native weakened HP without a refill", "[trust][recovery]")
{
    // The caller passes the post-Weakness maximum, never the pre-KO full HP.
    REQUIRE(trustrecovery::ReturnedHP(251, 1) == 25);
    REQUIRE(trustrecovery::ReturnedHP(251, 2) == 62);
    REQUIRE(trustrecovery::ReturnedHP(251, 3) == 125);
    REQUIRE(trustrecovery::ReturnedHP(251, 4) == 251);
    REQUIRE(trustrecovery::ReturnedHP(1, 1) == 1);
    REQUIRE(trustrecovery::ReturnedHP(251, 0) == 0);
    REQUIRE(trustrecovery::ReturnedHP(251, 5) == 0);
}

TEST_CASE("Trust recovery rejects invalid and conflated recovery flags", "[trust][recovery]")
{
    REQUIRE_FALSE(trustrecovery::IsValid({ 0, false, false }));
    REQUIRE_FALSE(trustrecovery::IsValid({ 5, true, true }));
    REQUIRE_FALSE(trustrecovery::IsValid({ 3, true, false }));
    REQUIRE_FALSE(trustrecovery::IsValid({ 3, false, true }));
    REQUIRE_FALSE(trustrecovery::IsValid({ 4, false, true }));
    for (uint8 tier = 1; tier <= 3; ++tier)
    {
        const auto options = trustrecovery::ReraiseOptions(tier);
        REQUIRE(trustrecovery::IsValid(options));
        REQUIRE_FALSE(options.shortWeakness);
        REQUIRE_FALSE(options.grantReraiseIII);
        REQUIRE(trustrecovery::WeaknessDuration(options) == 5min);
    }
    REQUIRE(trustrecovery::CorpseLifetime == 60min);
}
