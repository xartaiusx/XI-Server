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

// Exercise spy declarations before the central return-wrapper traits.
#include "test/lua/lua_spy.h"

#include "common/lua.h"

#include <catch2/catch_test_macros.hpp>

#include <array>
#include <functional>
#include <map>
#include <string>
#include <type_traits>
#include <vector>

using ReturnObjects = std::vector<sol::object>;
static_assert(!sol::is_container_v<sol::as_returns_t<ReturnObjects>>);
static_assert(!sol::is_container_v<sol::as_returns_t<std::array<int, 2>>>);
static_assert(!sol::is_container_v<sol::as_returns_t<std::reference_wrapper<ReturnObjects>>>);
static_assert(sol::is_container_v<std::vector<int>>);
static_assert(sol::is_container_v<std::map<int, int>>);
static_assert(!sol::is_container_v<std::string>);
static_assert(!sol::is_container_v<sol::object>);
static_assert(!sol::is_container_v<sol::variadic_results>);

TEST_CASE("Lua return wrappers preserve multiple values and ordinary container userdata", "[lua][returns]")
{
    sol::state    localLua;
    ReturnObjects values{ sol::make_object(localLua, 7), sol::make_object(localLua, "alpha"), sol::make_object(localLua, sol::lua_nil) };
    localLua.set_function("empty", []
                          {
                              return sol::as_returns(ReturnObjects{});
                          });
    localLua.set_function("one", [&]
                          {
                              return sol::as_returns(ReturnObjects{ values.front() });
                          });
    localLua.set_function("many", [&]
                          {
                              return sol::as_returns(values);
                          });
    localLua.set_function("reference", [&]
                          {
                              return sol::as_returns(std::cref(values));
                          });
    localLua.set_function("raw", []
                          {
                              return std::vector<int>{ 11, 13 };
                          });
    const int stack = lua_gettop(localLua.lua_state());
    {
        sol::protected_function call   = localLua["empty"];
        auto                    result = call();
        REQUIRE(result.valid());
        CHECK(result.return_count() == 0);
    }
    {
        sol::protected_function call   = localLua["one"];
        auto                    result = call();
        REQUIRE(result.valid());
        REQUIRE(result.return_count() == 1);
        CHECK(result.get<int>(0) == 7);
    }
    for (const auto* name : { "many", "reference" })
    {
        CAPTURE(name);
        sol::protected_function call   = localLua[name];
        auto                    result = call();
        REQUIRE(result.valid());
        REQUIRE(result.return_count() == 3);
        CHECK(result.get<int>(0) == 7);
        CHECK(result.get<std::string>(1) == "alpha");
        CHECK(result.get<sol::object>(2).get_type() == sol::type::nil);
    }
    {
        sol::protected_function call   = localLua["raw"];
        auto                    result = call();
        REQUIRE(result.valid());
        REQUIRE(result.return_count() == 1);
        const auto object = result.get<sol::object>(0);
        REQUIRE(object.get_type() == sol::type::userdata);
        CHECK(object.as<std::vector<int>>() == (std::vector<int>{ 11, 13 }));
    }
    CHECK(lua_gettop(localLua.lua_state()) == stack);
}
