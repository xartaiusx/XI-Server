/*
===========================================================================

  Copyright (c) 2026 LandSandBoat Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

===========================================================================
*/

#include "common/cert_helpers.h"

#include <catch2/catch_test_macros.hpp>

#include <chrono>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <string_view>
#include <system_error>
#include <type_traits>

namespace
{

class CertificateFixture
{
public:
    CertificateFixture()
    : directory_(std::filesystem::temp_directory_path() /
                 ("mochirii-certificate-preservation-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count())))
    {
        if (!std::filesystem::create_directory(directory_))
        {
            throw std::runtime_error("Cannot create isolated certificate fixture directory");
        }
    }

    ~CertificateFixture()
    {
        std::error_code ec;
        std::filesystem::remove(key(), ec);
        std::filesystem::remove(cert(), ec);
        std::filesystem::remove(directory_ / "key-target", ec);
        std::filesystem::remove(directory_ / "cert-target", ec);
        std::filesystem::remove(directory_, ec);
    }

    CertificateFixture(const CertificateFixture&)            = delete;
    CertificateFixture& operator=(const CertificateFixture&) = delete;
    CertificateFixture(CertificateFixture&&)                 = delete;
    CertificateFixture& operator=(CertificateFixture&&)      = delete;

    auto name() const -> std::string
    {
        return (directory_ / "server").string();
    }

    auto key() const -> std::filesystem::path
    {
        return directory_ / "server.key";
    }

    auto cert() const -> std::filesystem::path
    {
        return directory_ / "server.cert";
    }

    auto target(const std::string& name) const -> std::filesystem::path
    {
        return directory_ / name;
    }

    static void write(const std::filesystem::path& path, const std::string_view content)
    {
        std::ofstream stream(path, std::ios::binary);
        stream << content;
        REQUIRE(stream.good());
    }

    static auto read(const std::filesystem::path& path) -> std::string
    {
        std::ifstream stream(path, std::ios::binary);
        REQUIRE(stream.good());
        return { std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>() };
    }

private:
    std::filesystem::path directory_;
};

static_assert(!std::is_copy_constructible_v<CertificateFixture>);
static_assert(!std::is_copy_assignable_v<CertificateFixture>);
static_assert(!std::is_move_constructible_v<CertificateFixture>);
static_assert(!std::is_move_assignable_v<CertificateFixture>);

} // namespace

TEST_CASE("Certificate startup preserves existing material and links", "[certificate][preservation]")
{
    CertificateFixture fixture;

    constexpr auto keyText  = "invalid key fixture\n";
    constexpr auto certText = "invalid certificate fixture\n";

    SECTION("malformed existing pair")
    {
        CertificateFixture::write(fixture.key(), keyText);
        CertificateFixture::write(fixture.cert(), certText);

        REQUIRE_THROWS_AS(certificateHelpers::generateSelfSignedCert(fixture.name()), std::runtime_error);
        CHECK(CertificateFixture::read(fixture.key()) == keyText);
        CHECK(CertificateFixture::read(fixture.cert()) == certText);
    }

    SECTION("incomplete existing pair")
    {
        CertificateFixture::write(fixture.key(), keyText);

        REQUIRE_THROWS_AS(certificateHelpers::generateSelfSignedCert(fixture.name()), std::runtime_error);
        CHECK(CertificateFixture::read(fixture.key()) == keyText);
        CHECK_FALSE(std::filesystem::exists(fixture.cert()));
    }

    SECTION("dangling existing key link")
    {
        const auto      missingTarget = fixture.target("key-target");
        std::error_code ec;
        std::filesystem::create_symlink(missingTarget, fixture.key(), ec);
        if (ec)
        {
            SKIP("Host does not permit test symlink creation");
        }

        REQUIRE_THROWS_AS(certificateHelpers::generateSelfSignedCert(fixture.name()), std::runtime_error);
        CHECK(std::filesystem::is_symlink(fixture.key()));
        CHECK(std::filesystem::read_symlink(fixture.key()) == missingTarget);
        CHECK_FALSE(std::filesystem::exists(missingTarget));
        CHECK_FALSE(std::filesystem::exists(fixture.cert()));
    }

    SECTION("malformed linked pair preserves link targets")
    {
        const auto keyTarget  = fixture.target("key-target");
        const auto certTarget = fixture.target("cert-target");
        CertificateFixture::write(keyTarget, keyText);
        CertificateFixture::write(certTarget, certText);
        std::error_code ec;
        std::filesystem::create_symlink(keyTarget, fixture.key(), ec);
        if (ec)
        {
            SKIP("Host does not permit test symlink creation");
        }
        std::filesystem::create_symlink(certTarget, fixture.cert(), ec);
        REQUIRE_FALSE(ec);

        REQUIRE_THROWS_AS(certificateHelpers::generateSelfSignedCert(fixture.name()), std::runtime_error);
        CHECK(std::filesystem::read_symlink(fixture.key()) == keyTarget);
        CHECK(std::filesystem::read_symlink(fixture.cert()) == certTarget);
        CHECK(CertificateFixture::read(keyTarget) == keyText);
        CHECK(CertificateFixture::read(certTarget) == certText);
    }
}
