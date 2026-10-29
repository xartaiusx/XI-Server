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

#include "map/utils/trust_return.h"

#include <catch2/catch_test_macros.hpp>
#include <string>

TEST_CASE("Trust return parser rejects noncanonical or ambiguous requests", "[trust][return]")
{
    const auto one = trustutils::ParseTrustReturn("0000006500000001 42 100 one 17188881 1809");
    REQUIRE(one);
    REQUIRE(one->owner == 42);
    REQUIRE(one->issued == 101);
    REQUIRE(one->id == 17188881);
    REQUIRE(one->index == 1809);
    REQUIRE_FALSE(one->all);
    REQUIRE(trustutils::ParseTrustReturn("0000006500000001 42 100 all 0 0"));
    for (const auto text : {
             "0000006500000001 042 100 all 0 0", "0000006500000001 42 100 all 1 0", "0000006500000001 42 100 one 0 1", "0000006500000001 42 100 one 1 4096", "0000006500000001 4294967296 100 all 0 0", "0000006500000001 42 65536 all 0 0", "000000650000000A 42 100 all 0 0", "0000006500000001 42 100 all 0 0 ", "0000006500000001  42 100 all 0 0", "0000006500000001 42 100 all 0 0\n", "0000006500000001\t42 100 all 0 0", "0000006500000001 42 100 other 0 0" })
    {
        CAPTURE(text);
        REQUIRE_FALSE(trustutils::ParseTrustReturn(text));
    }
}

TEST_CASE("Trust return nonce survives roster and context changes", "[trust][return]")
{
    trustutils::TrustReturnNonceCache cache(100);
    auto                              request = *trustutils::ParseTrustReturn("0000006500000001 42 100 all 0 0");
    REQUIRE(cache.reserve(request, 101) == nullptr);
    request.all   = false;
    request.id    = 1000;
    request.index = 1809;
    request.zone  = 101;
    REQUIRE(std::string(cache.reserve(request, 102)) == "REPLAY");
    request.owner = 43;
    REQUIRE(cache.reserve(request, 102) == nullptr);
    REQUIRE(std::string(cache.reserve(request, 106)) == "STALE");
}

TEST_CASE("Trust return full cache cannot replay an unstored busy nonce", "[trust][return]")
{
    trustutils::TrustReturnNonceCache cache(100);
    auto                              request = *trustutils::ParseTrustReturn("0000006500000001 42 100 all 0 0");
    for (uint64 nonce = 1; nonce <= 8; ++nonce)
    {
        request.nonce = (uint64{ 101 } << 32) | nonce;
        REQUIRE(cache.reserve(request, 101) == nullptr);
    }
    request.nonce = (uint64{ 101 } << 32) | 9;
    REQUIRE(std::string(cache.reserve(request, 102)) == "BUSY");
    request.nonce = (uint64{ 101 } << 32) | 1;
    REQUIRE(std::string(cache.reserve(request, 103)) == "REPLAY");
    request.nonce  = (uint64{ 104 } << 32) | 9;
    request.issued = 104;
    REQUIRE(std::string(cache.reserve(request, 104)) == "BUSY");
    // The original entries expire at106; the unstored104 nonce must remain
    // denied until its own freshness window ends at109.
    REQUIRE(std::string(cache.reserve(request, 106)) == "BUSY");
    REQUIRE(std::string(cache.reserve(request, 109)) == "STALE");
    request.issued = 109;
    request.nonce  = (uint64{ 109 } << 32) | 10;
    REQUIRE(cache.reserve(request, 109) == nullptr);
}

TEST_CASE("Trust return nonce fails closed at startup future expiry and clock reversal", "[trust][return]")
{
    trustutils::TrustReturnNonceCache cache(100);
    auto                              request = *trustutils::ParseTrustReturn("0000006400000001 42 100 all 0 0");
    REQUIRE(std::string(cache.reserve(request, 101)) == "STALE");
    request.issued = 103;
    REQUIRE(std::string(cache.reserve(request, 102)) == "STALE");
    REQUIRE(cache.reserve(request, 103) == nullptr);
    REQUIRE(std::string(cache.reserve(request, 102)) == "CLOCK");
    REQUIRE(std::string(cache.reserve(request, 108)) == "STALE");
}
