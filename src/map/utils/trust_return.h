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

#include <algorithm>
#include <array>
#include <charconv>
#include <optional>
#include <string_view>

namespace trustutils
{

struct TrustReturnRequest
{
    std::string_view nonceText;
    uint64           nonce{};
    uint32           issued{};
    uint32           owner{};
    uint16           zone{};
    bool             all{};
    uint32           id{};
    uint16           index{};
};

inline auto ParseTrustReturn(std::string_view text) -> std::optional<TrustReturnRequest>
{
    if (text.empty() || text.size() > 113)
    {
        return std::nullopt;
    }
    std::array<std::string_view, 6> fields{};
    for (std::size_t i = 0; i < fields.size(); ++i)
    {
        const auto separator = text.find(' ');
        fields[i]            = text.substr(0, separator);
        if (fields[i].empty() || (i + 1 == fields.size()) != (separator == std::string_view::npos))
        {
            return std::nullopt;
        }
        if (separator != std::string_view::npos)
        {
            text.remove_prefix(separator + 1);
        }
    }
    TrustReturnRequest result{};
    result.nonceText = fields[0];
    if (fields[0].size() != 16 || !std::ranges::all_of(fields[0], [](char c)
                                                       {
                                                           return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
                                                       }))
    {
        return std::nullopt;
    }
    const auto read = [](std::string_view value, auto& destination, int base = 10)
    {
        if (value.empty() || (base == 10 && value.size() > 1 && value.front() == '0'))
        {
            return false;
        }
        const auto [end, error] = std::from_chars(value.data(), value.data() + value.size(), destination, base);
        return error == std::errc{} && end == value.data() + value.size();
    };
    if (!read(fields[0], result.nonce, 16) || !read(fields[0].substr(0, 8), result.issued, 16) ||
        !read(fields[1], result.owner) || !read(fields[2], result.zone) || !read(fields[4], result.id) || !read(fields[5], result.index) ||
        result.owner == 0 || result.zone == 0 || (fields[3] != "one" && fields[3] != "all"))
    {
        return std::nullopt;
    }
    result.all = fields[3] == "all";
    if (result.all ? (result.id != 0 || result.index != 0) : (result.id == 0 || result.index == 0 || result.index > 4095))
    {
        return std::nullopt;
    }
    return result;
}

// Map-thread-owned, bounded and independent of roster/session lifetime.
class TrustReturnNonceCache
{
public:
    explicit TrustReturnNonceCache(uint64 started)
    : started_(started)
    , lastTime_(started)
    {
    }

    auto reserve(const TrustReturnRequest& request, uint64 now) -> const char*
    {
        if (now < lastTime_)
        {
            return "CLOCK";
        }
        lastTime_          = now;
        const auto expires = static_cast<uint64>(request.issued) + 5;
        if (request.issued <= started_ || request.issued > now || now >= expires)
        {
            return "STALE";
        }
        for (auto& entry : entries_)
        {
            if (entry.expires <= now)
            {
                entry = {};
            }
            if (entry.owner == request.owner && entry.nonce == request.nonce)
            {
                return "REPLAY";
            }
        }
        if (now < barrier_)
        {
            barrier_ = std::max(barrier_, expires);
            return "BUSY";
        }
        const auto empty = std::ranges::find_if(entries_, [](const auto& entry)
                                                {
                                                    return entry.expires == 0;
                                                });
        if (empty == entries_.end())
        {
            barrier_ = now + 5;
            return "BUSY";
        }
        *empty = { request.owner, request.nonce, expires };
        return nullptr;
    }

private:
    struct Entry
    {
        uint32 owner{};
        uint64 nonce{};
        uint64 expires{};
    };

    std::array<Entry, 8> entries_{};
    uint64               started_{};
    uint64               lastTime_{};
    uint64               barrier_{};
};

} // namespace trustutils
