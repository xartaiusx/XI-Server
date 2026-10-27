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

#include "map/status_effect.h"
#include "map/utils/trust_holy_circle.h"

#include <catch2/catch_approx.hpp>
#include <catch2/catch_test_macros.hpp>

TEST_CASE("Developed Holy Circle requires exact cast provenance", "[trust][holy-circle]")
{
    REQUIRE(trustholycircle::IsApprovedSource(SOURCE_DEVELOPED_TRUST, 910, 1));
    REQUIRE_FALSE(trustholycircle::IsApprovedSource(SOURCE_MOB, 910, 1));
    REQUIRE_FALSE(trustholycircle::IsApprovedSource(SOURCE_DEVELOPED_TRUST, 1018, 1));
    REQUIRE_FALSE(trustholycircle::IsApprovedSource(SOURCE_DEVELOPED_TRUST, 910, 0));
}

TEST_CASE("Developed Holy Circle preserves the existing integer ecosystem model", "[trust][holy-circle]")
{
    REQUIRE(trustholycircle::ResolveMultiplier(0, 0, false, false) == 1.0);
    REQUIRE(trustholycircle::ResolveMultiplier(15, 0, false, false) == Catch::Approx(1.15));
    REQUIRE(trustholycircle::ResolveMultiplier(0, 35, false, false) == Catch::Approx(0.65));
    REQUIRE(trustholycircle::ResolveMultiplier(15, 0, false, true) == Catch::Approx(1.07));
    REQUIRE(trustholycircle::ResolveMultiplier(0, 35, true, false) == Catch::Approx(0.83));
    REQUIRE(trustholycircle::ResolveMultiplier(15, 35, false, false) == Catch::Approx(0.80));
    REQUIRE(trustholycircle::ResolveMultiplier(500, 0, false, false) == 1.5);
    REQUIRE(trustholycircle::ResolveMultiplier(0, 500, false, false) == 0.5);
}

TEST_CASE("Developed Holy Circle cannot alter unattributed or non-damage input", "[trust][holy-circle]")
{
    REQUIRE(trustholycircle::GetMultiplier(nullptr, nullptr) == 1.0);
    REQUIRE(trustholycircle::Apply(nullptr, nullptr, 100) == 100);
    REQUIRE(trustholycircle::Apply(nullptr, nullptr, 0) == 0);
    REQUIRE(trustholycircle::Apply(nullptr, nullptr, -100) == -100);
}
