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

#include "common/cbasetypes.h"
#include "common/timer.h"

#include <algorithm>

// Recovery tier, shortened weakness and the Arise Reraise grant are independent.
struct TrustRaiseOptions
{
    uint8 tier{};
    bool  shortWeakness{};
    bool  grantReraiseIII{};
};

namespace trustrecovery
{

constexpr auto CorpseLifetime = 60min;

constexpr auto IsValid(TrustRaiseOptions options) -> bool
{
    return options.tier >= 1 && options.tier <= 4 &&
           (!options.shortWeakness || options.tier == 4) &&
           (!options.grantReraiseIII || (options.tier == 4 && options.shortWeakness));
}

constexpr auto ReraiseOptions(uint8 tier) -> TrustRaiseOptions
{
    return { tier, tier == 4, false };
}

constexpr auto WeaknessDuration(TrustRaiseOptions options) -> timer::duration
{
    return options.shortWeakness ? 3min : 5min;
}

constexpr auto ReturnedHP(int32 weakenedMaxHP, uint8 tier) -> int32
{
    const int32 percent = tier == 1 ? 10 : tier == 2 ? 25
                                       : tier == 3   ? 50
                                       : tier == 4   ? 100
                                                     : 0;
    return percent == 0 ? 0 : std::max<int32>(1, static_cast<int32>(static_cast<int64>(weakenedMaxHP) * percent / 100));
}

} // namespace trustrecovery
