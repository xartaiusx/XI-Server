/*
===========================================================================

  Copyright (c) 2026 LandSandBoat Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

===========================================================================
*/

#include <glaze/glaze.hpp>

#include <catch2/catch_test_macros.hpp>

#include <algorithm>
#include <array>
#include <cstdint>
#include <sstream>
#include <string>
#include <string_view>
#include <type_traits>
#include <vector>

// Automatic reflection needs an externally linked record type.
namespace glaze_skip_test
{

struct KnownField
{
    int id{};
};

} // namespace glaze_skip_test

namespace
{

struct NoncopyableContext : glz::context
{
    NoncopyableContext()                                             = default;
    ~NoncopyableContext()                                            = default;
    NoncopyableContext(const NoncopyableContext&)                    = delete;
    NoncopyableContext(NoncopyableContext&&)                         = delete;
    auto operator=(const NoncopyableContext&) -> NoncopyableContext& = delete;
    auto operator=(NoncopyableContext&&) -> NoncopyableContext&      = delete;
};

struct ValidatingOptions : glz::opts
{
    bool validate_skipped = true;
};

template <auto Format, auto Options, class Context = glz::context>
void checkSkip(std::string_view input, glz::error_code error, std::size_t consumed, unsigned depth = 0)
{
    for (const bool rvalue : { false, true })
    {
        Context     context{};
        const char* iterator = input.data();
        context.depth        = depth;
        if (rvalue)
        {
            // Exercise reference categories without copying either object.
            glz::skip_value<Format>::template op<Options>(static_cast<Context&&>(context), static_cast<const char*&&>(iterator), input.data() + input.size());
        }
        else
        {
            glz::skip_value<Format>::template op<Options>(context, iterator, input.data() + input.size());
        }
        CHECK(context.error == error);
        CHECK(context.depth == depth);
        CHECK(iterator == input.data() + consumed);
    }
}

} // namespace

TEST_CASE("Glaze numeric predicates preserve byte classification and bounded parsing", "[glaze][skip][number][bounds]")
{
    constexpr auto predicate = static_cast<bool (*)(uint8_t) noexcept>(&glz::is_digit);
    static_assert(std::is_same_v<decltype(predicate), bool (*const)(uint8_t) noexcept>);
    for (unsigned value = 0; value != 256; ++value)
    {
        const auto byte = static_cast<std::uint8_t>(value);
        CHECK(predicate(byte) == glz::is_digit(byte));
        CHECK(predicate(byte) == (value >= '0' && value <= '9'));
    }

    struct NumberCase
    {
        std::string_view text;
        std::size_t      consumed;
        glz::error_code  error;
    };

    constexpr std::array cases{
        NumberCase{ "", 0, glz::error_code::syntax_error },
        NumberCase{ "0", 1, glz::error_code::none },
        NumberCase{ "-0", 2, glz::error_code::none },
        NumberCase{ "7", 1, glz::error_code::none },
        NumberCase{ "-12", 3, glz::error_code::none },
        NumberCase{ "12.5e-2", 7, glz::error_code::none },
        NumberCase{ "0e4", 3, glz::error_code::none },
        NumberCase{ "-0.5E+2", 7, glz::error_code::none },
        NumberCase{ "123x", 3, glz::error_code::none },
        NumberCase{ "1.", 2, glz::error_code::syntax_error },
        NumberCase{ "1e", 2, glz::error_code::syntax_error },
        NumberCase{ "1e+", 3, glz::error_code::syntax_error },
        NumberCase{ "-", 1, glz::error_code::syntax_error },
        NumberCase{ "+1", 0, glz::error_code::syntax_error },
        NumberCase{ "01", 1, glz::error_code::none },
        NumberCase{ ".5", 0, glz::error_code::syntax_error },
    };
    for (const auto& item : cases)
    {
        for (const bool rvalue : { false, true })
        {
            CAPTURE(item.text, rvalue);
            std::vector<char> bytes(item.text.size() + 2, 'Z');
            std::copy(item.text.begin(), item.text.end(), bytes.begin() + 1);
            const auto         original = bytes;
            const char*        begin    = bytes.data() + 1;
            const char*        iterator = begin;
            const char*        end      = begin + item.text.size();
            NoncopyableContext context{};
            context.depth = 9;
            if (rvalue)
            {
                glz::skip_number_with_validation(static_cast<NoncopyableContext&&>(context), static_cast<const char*&&>(iterator), end);
            }
            else
            {
                glz::skip_number_with_validation(context, iterator, end);
            }
            CHECK(iterator == begin + item.consumed);
            CHECK(context.error == item.error);
            CHECK(context.depth == 9);
            CHECK(bytes == original);
        }
    }
}

TEST_CASE("Glaze skip overloads preserve forwarding and bounds", "[glaze][skip][bounds]")
{
    constexpr auto plain              = glz::opts{ .null_terminated = false };
    constexpr auto comments           = glz::opts{ .null_terminated = false, .comments = true };
    constexpr auto binary             = glz::opts{ .format = glz::BEVE, .null_terminated = false };
    constexpr auto validating         = ValidatingOptions{ { .null_terminated = false } };
    constexpr auto validatingComments = ValidatingOptions{ { .null_terminated = false, .comments = true } };
    constexpr char nullTag[]          = { static_cast<char>(glz::tag::null) };
    constexpr char numberTag[]        = { static_cast<char>(glz::tag::number) };

    SECTION("all three forms forward lvalues and rvalues without context copies")
    {
        constexpr std::string_view json  = R"([1,{"x":true}] )";
        constexpr std::string_view jsonc = R"({"x":/*note*/true} )";
        checkSkip<glz::JSON, plain>(json, glz::error_code::none, json.size() - 1);
        checkSkip<glz::JSON, comments>(jsonc, glz::error_code::none, jsonc.size() - 1);
        checkSkip<glz::BEVE, binary>({ nullTag, 1 }, glz::error_code::none, 1);
        checkSkip<glz::JSON, plain, NoncopyableContext>(json, glz::error_code::none, json.size() - 1);
        checkSkip<glz::JSON, comments, NoncopyableContext>(jsonc, glz::error_code::none, jsonc.size() - 1);
        checkSkip<glz::BEVE, binary, NoncopyableContext>({ nullTag, 1 }, glz::error_code::none, 1);
    }

    SECTION("truncated input preserves the existing error and depth contracts")
    {
        checkSkip<glz::JSON, plain>("[", glz::error_code::unexpected_end, 1);
        checkSkip<glz::JSON, comments>("[", glz::error_code::unexpected_end, 1);
        checkSkip<glz::BEVE, binary>({ numberTag, 1 }, glz::error_code::unexpected_end, 1);
    }

    SECTION("depth rejection changes neither the iterator nor the saturated depth")
    {
        constexpr auto depth = static_cast<unsigned>(glz::max_recursive_depth_limit);
        checkSkip<glz::JSON, validating>("[] ", glz::error_code::exceeded_max_recursive_depth, 0, depth);
        checkSkip<glz::JSON, validatingComments>("[] ", glz::error_code::exceeded_max_recursive_depth, 0, depth);
        checkSkip<glz::BEVE, binary>({ nullTag, 1 }, glz::error_code::exceeded_max_recursive_depth, 0, depth);
    }

    SECTION("streaming skips oversized unknown values without losing the following field")
    {
        constexpr auto options = glz::opts{ .error_on_unknown_keys = false };
        std::string    document{ R"({"ignored":[)" };
        for (int index = 0; index < 64; ++index)
        {
            if (index != 0)
            {
                document.push_back(',');
            }
            document += R"({"values":[1,2,3],"text":"quoted \" ] }"})";
        }
        document += R"(],"id":73})";
        REQUIRE(document.size() > 512);

        glaze_skip_test::KnownField reference{};
        const auto                  bufferedError = glz::read<options>(reference, document);
        REQUIRE(bufferedError.ec == glz::error_code::none);
        REQUIRE(reference.id == 73);

        std::istringstream       input(document);
        glz::istream_buffer<512> buffer(input);
        const auto               initialWindow = buffer.size();
        REQUIRE(initialWindow == 512);
        glz::streaming_context      context{};
        glaze_skip_test::KnownField decoded{};
        const auto                  streamingError = glz::read_streaming<options>(decoded, buffer, context);
        CHECK(streamingError.ec == bufferedError.ec);
        CHECK(decoded.id == reference.id);
        CHECK(context.stream.enabled());
        CHECK(context.error == glz::error_code::none);
        CHECK(context.depth == 0);
        CHECK_FALSE(context.padded_input);
        CHECK(buffer.bytes_consumed() == document.size());
        CHECK(buffer.bytes_consumed() > initialWindow);

        std::istringstream          brokenInput(document.substr(0, document.size() / 2));
        glz::istream_buffer<512>    brokenBuffer(brokenInput);
        glz::streaming_context      brokenContext{};
        glaze_skip_test::KnownField broken{};
        const auto                  brokenError = glz::read_streaming<options>(broken, brokenBuffer, brokenContext);
        CHECK(brokenError.ec == glz::error_code::unexpected_end);
        CHECK(broken.id == 0);
        CHECK(brokenContext.stream.enabled());
        CHECK(brokenContext.depth == 0);
    }
}
