/*
===========================================================================

  Copyright (c) 2026 LandSandBoat Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

===========================================================================
*/

#include <asio/any_io_executor.hpp>
#include <asio/detail/work_dispatcher.hpp>
#include <asio/io_context.hpp>
#include <asio/post.hpp>

#include <catch2/catch_test_macros.hpp>

#include <type_traits>

namespace
{

template <typename Function>
concept HasWorkResult = requires { typename asio::detail::work_result<Function>::type; };

struct ValueWork
{
    auto operator()() const -> const int&;
};

using VoidWork = void (*)();

static_assert(HasWorkResult<ValueWork>);
static_assert(std::is_same_v<asio::detail::work_result_t<ValueWork>, int>);
static_assert(HasWorkResult<VoidWork>);
static_assert(std::is_same_v<asio::detail::work_result_t<VoidWork>, void>);
static_assert(!HasWorkResult<int>);
static_assert(!HasWorkResult<const asio::any_io_executor&>);

} // namespace

TEST_CASE("ASIO posts through a type-erased executor exactly once", "[asio][executor][sfinae]")
{
    asio::io_context            context;
    const asio::any_io_executor executor = context.get_executor();
    int                         completions{};

    asio::post(executor,
               [&completions]
               {
                   ++completions;
               });

    REQUIRE(completions == 0);
    CHECK(context.run() == 1);
    CHECK(completions == 1);
    context.restart();
    CHECK(context.poll() == 0);
    CHECK(completions == 1);
}
