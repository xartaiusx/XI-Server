/*
===========================================================================

  Copyright (c) 2026 LandSandBoat Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

===========================================================================
*/

#include "profile/irc/irc_session.h"
#include "profile/irc/presence_manager.h"

#include "common/database.h"
#include "common/database/libmariadb/libmariadb_result_set.h"

#include <catch2/catch_test_macros.hpp>

#include <cstddef>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

namespace
{

constexpr uint32 kAccountId = 1234;

enum class Fault
{
    None,
    OpenStatus,
    Announce,
};

class FixtureDatabase final : public db::Database
{
public:
    explicit FixtureDatabase(profile::PresenceManager& presence)
    : previous_(&db::getDatabase())
    , presence_(presence)
    , schema_(std::make_shared<db::ColumnSchema>())
    {
        db::setDatabase(this);
    }

    ~FixtureDatabase() override
    {
        db::setDatabase(previous_);
    }

    FixtureDatabase(const FixtureDatabase&)            = delete;
    FixtureDatabase& operator=(const FixtureDatabase&) = delete;
    FixtureDatabase(FixtureDatabase&&)                 = delete;
    FixtureDatabase& operator=(FixtureDatabase&&)      = delete;

    auto execute(const std::string& query, const std::vector<db::BoundValue>&) -> std::unique_ptr<db::ResultSet> override
    {
        auto point = Fault::None;
        if (query.starts_with("SELECT open_status FROM accounts_profile"))
        {
            ++openStatusCalls;
            point = Fault::OpenStatus;
        }
        else if (query.starts_with("SELECT mine.friend_accid,"))
        {
            ++announceCalls;
            point = Fault::Announce;
        }
        else
        {
            throw std::runtime_error("Unexpected synthetic presence query");
        }

        if (fault == point)
        {
            faultObserved  = true;
            faultSawOnline = presence_.isOnline(kAccountId);
            throw std::runtime_error("Synthetic presence fault");
        }

        // This backend's result container owns rows in memory; no connection is opened.
        // Empty SELECTs mean an unsaved Online status and no visible friends.
        return std::make_unique<db::LibMariaDBResultSet>(query, schema_, std::vector<db::LibMariaDBResultSet::Row>{});
    }

    auto executeBulk(const std::string& query, const std::vector<db::BoundValue>& params) -> std::unique_ptr<db::ResultSet> override
    {
        return execute(query, params);
    }

    auto getSchema() -> std::string override
    {
        return "fixture";
    }

    auto getVersion() -> std::string override
    {
        return "fixture";
    }

    auto getDriverVersion() -> std::string override
    {
        return "fixture";
    }

    Fault       fault{ Fault::None };
    bool        faultObserved{};
    bool        faultSawOnline{};
    std::size_t openStatusCalls{};
    std::size_t announceCalls{};

private:
    db::Database*                           previous_;
    profile::PresenceManager&               presence_;
    std::shared_ptr<const db::ColumnSchema> schema_;
};

} // namespace

TEST_CASE("Profile presence removes an entry when initial status lookup throws", "[security][profile][presence]")
{
    profile::PresenceManager presence;
    FixtureDatabase          database(presence);
    asio::io_context         context;
    asio::ssl::context       tls(asio::ssl::context::tlsv13);
    const auto               credential = profile::accounts::Credential{ .accountId = kAccountId };
    profile::IrcSession      session(profile::Stream(asio::ip::tcp::socket(context), tls), "fixture", credential, presence);

    database.fault = Fault::OpenStatus;
    CHECK_THROWS_AS(presence.signOn(kAccountId, credential.sessionHash, &session), std::runtime_error);
    CHECK(database.faultObserved);
    CHECK(database.openStatusCalls == 1);
    CHECK(database.announceCalls == 0);
    REQUIRE_FALSE(presence.isOnline(kAccountId));

    database.fault = Fault::None;
    const auto id  = presence.signOn(kAccountId, credential.sessionHash, &session);
    REQUIRE(presence.isOnline(kAccountId));
    presence.signOff(kAccountId, id);
    CHECK_FALSE(presence.isOnline(kAccountId));
}

TEST_CASE("Profile presence rolls back an announcement failure after publication", "[security][profile][presence]")
{
    profile::PresenceManager presence;
    FixtureDatabase          database(presence);
    asio::io_context         context;
    asio::ssl::context       tls(asio::ssl::context::tlsv13);
    const auto               credential = profile::accounts::Credential{ .accountId = kAccountId };
    profile::IrcSession      session(profile::Stream(asio::ip::tcp::socket(context), tls), "fixture", credential, presence);

    database.fault = Fault::Announce;
    CHECK_THROWS_AS(presence.signOn(kAccountId, credential.sessionHash, &session), std::runtime_error);
    CHECK(database.faultObserved);
    CHECK(database.faultSawOnline);
    CHECK(database.openStatusCalls == 1);
    CHECK(database.announceCalls == 1);
    REQUIRE_FALSE(presence.isOnline(kAccountId));

    database.fault = Fault::None;
    const auto id  = presence.signOn(kAccountId, credential.sessionHash, &session);
    REQUIRE(presence.isOnline(kAccountId));
    presence.signOff(kAccountId, id);
    CHECK_FALSE(presence.isOnline(kAccountId));
}

TEST_CASE("Profile presence ignores the sign off of a replaced session", "[security][profile][presence]")
{
    profile::PresenceManager presence;
    FixtureDatabase          database(presence);
    asio::io_context         context;
    asio::ssl::context       tls(asio::ssl::context::tlsv13);
    const auto               credential = profile::accounts::Credential{ .accountId = kAccountId };
    profile::IrcSession      first(profile::Stream(asio::ip::tcp::socket(context), tls), "first fixture", credential, presence);
    profile::IrcSession      second(profile::Stream(asio::ip::tcp::socket(context), tls), "second fixture", credential, presence);

    const auto firstId  = presence.signOn(kAccountId, credential.sessionHash, &first);
    const auto secondId = presence.signOn(kAccountId, credential.sessionHash, &second);
    REQUIRE(secondId > firstId);
    REQUIRE(presence.isOnline(kAccountId));
    CHECK(database.openStatusCalls == 1);
    CHECK(database.announceCalls == 2);

    presence.signOff(kAccountId, firstId);
    CHECK(presence.isOnline(kAccountId));
    CHECK(database.announceCalls == 2);
    presence.signOff(kAccountId, secondId);
    CHECK_FALSE(presence.isOnline(kAccountId));
}

TEST_CASE("Profile presence removes a failed replacement and permits a fresh session", "[security][profile][presence]")
{
    profile::PresenceManager presence;
    FixtureDatabase          database(presence);
    asio::io_context         context;
    asio::ssl::context       tls(asio::ssl::context::tlsv13);
    const auto               credential = profile::accounts::Credential{ .accountId = kAccountId };
    profile::IrcSession      first(profile::Stream(asio::ip::tcp::socket(context), tls), "first fixture", credential, presence);
    profile::IrcSession      second(profile::Stream(asio::ip::tcp::socket(context), tls), "second fixture", credential, presence);

    const auto firstId = presence.signOn(kAccountId, credential.sessionHash, &first);
    database.fault     = Fault::Announce;
    CHECK_THROWS_AS(presence.signOn(kAccountId, credential.sessionHash, &second), std::runtime_error);
    CHECK(database.faultObserved);
    CHECK(database.faultSawOnline);
    CHECK(database.openStatusCalls == 1);
    CHECK(database.announceCalls == 2);
    REQUIRE_FALSE(presence.isOnline(kAccountId));

    database.fault = Fault::None;
    presence.signOff(kAccountId, firstId);
    const auto recoveredId = presence.signOn(kAccountId, credential.sessionHash, &second);
    REQUIRE(recoveredId > firstId);
    presence.signOff(kAccountId, firstId);
    CHECK(presence.isOnline(kAccountId));
    presence.signOff(kAccountId, recoveredId);
    CHECK_FALSE(presence.isOnline(kAccountId));
}
