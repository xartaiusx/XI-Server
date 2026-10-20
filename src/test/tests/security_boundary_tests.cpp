/*
===========================================================================

  Copyright (c) 2026 LandSandBoat Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

===========================================================================
*/

#include "map/ai/helpers/gambits_container.h"
#include "map/entities/battle_entity.h"
#include "map/entities/char_entity.h"
#include "map/entities/trust_entity.h"
#include "map/enums/four_cc.h"
#include "map/monstrosity.h"
#include "map/packets/s2c/0x038_schedulor.h"
#include "map/packets/s2c/0x039_mapschedulor.h"
#include "map/recast_container.h"

#include "common/database.h"

#include <catch2/catch_test_macros.hpp>
#include <fmt/chrono.h>

#include <array>
#include <cstddef>
#include <ctime>
#include <future>
#include <limits>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <utility>

TEST_CASE("Scheduler FOURCC packets preserve exactly four bytes", "[security][packets][fourcc]")
{
    CBattleEntity owner;
    CBattleEntity target;
    owner.id      = 1;
    owner.targid  = 0x400;
    target.id     = 2;
    target.targid = 0x401;

    const std::array<std::string, 3> codes{ "sp00", std::string("\0\x80\xff\x01", 4), std::string("a\0bc", 4) };
    for (const auto& code : codes)
    {
        GP_SERV_COMMAND_SCHEDULOR    scheduler(&owner, &target, code);
        GP_SERV_COMMAND_MAPSCHEDULOR mapScheduler(&owner, code);
        GP_SERV_COMMAND_MAPSCHEDULOR noEntity(nullptr, code);

        CHECK(scheduler.getType() == 0x038);
        CHECK(mapScheduler.getType() == 0x039);
        CHECK(scheduler.ref<uint32>(0x04) == owner.id);
        CHECK(scheduler.ref<uint32>(0x08) == target.id);
        CHECK(scheduler.ref<uint16>(0x10) == owner.targid);
        CHECK(scheduler.ref<uint16>(0x12) == target.targid);
        CHECK(mapScheduler.ref<uint32>(0x04) == owner.id);
        CHECK(mapScheduler.ref<uint32>(0x08) == owner.id);
        CHECK(mapScheduler.ref<uint16>(0x10) == owner.targid);
        CHECK(mapScheduler.ref<uint16>(0x12) == owner.targid);
        CHECK(noEntity.ref<uint32>(0x04) == 0);
        CHECK(noEntity.ref<uint32>(0x08) == 0);

        constexpr auto schedulerOffset = sizeof(GP_SERV_HEADER) + offsetof(GP_SERV_COMMAND_SCHEDULOR::PacketData, id);
        constexpr auto mapOffset       = sizeof(GP_SERV_HEADER) + offsetof(GP_SERV_COMMAND_MAPSCHEDULOR::PacketData, id);
        for (std::size_t i = 0; i < code.size(); ++i)
        {
            CHECK(scheduler.ref<uint8>(schedulerOffset + i) == static_cast<uint8>(code[i]));
            CHECK(mapScheduler.ref<uint8>(mapOffset + i) == static_cast<uint8>(code[i]));
            CHECK(noEntity.ref<uint8>(mapOffset + i) == static_cast<uint8>(code[i]));
        }
    }

    GP_SERV_COMMAND_SCHEDULOR enumScheduler(&owner, &target, FourCC::FadeOut);
    CHECK(enumScheduler.ref<FourCC>(0x0C) == FourCC::FadeOut);
}

TEST_CASE("Scheduler FOURCC packets reject invalid byte counts", "[security][packets][fourcc]")
{
    CBattleEntity owner;
    CBattleEntity target;
    for (const auto& code : std::array<std::string, 5>{ "", "a", "ab", "abc", "abcde" })
    {
        CHECK_THROWS_AS(GP_SERV_COMMAND_SCHEDULOR(&owner, &target, code), std::invalid_argument);
        CHECK_THROWS_AS(GP_SERV_COMMAND_MAPSCHEDULOR(&owner, code), std::invalid_argument);
    }
}

TEST_CASE("Monipulator conversion rejects null and invalid dynamic types", "[security][monstrosity]")
{
    CHECK(monstrosity::AsMonipulator(nullptr) == nullptr);
    CBattleEntity nonPlayer;
    nonPlayer.objtype = TYPE_PC;
    CHECK(monstrosity::AsMonipulator(&nonPlayer) == nullptr);
    nonPlayer.objtype = TYPE_PET;
    CHECK(monstrosity::AsMonipulator(&nonPlayer) == nullptr);
}

TEST_CASE("Ability recast indices do not truncate at the byte boundary", "[security][recast]")
{
    CBattleEntity target;
    auto&         recasts = *target.PRecastContainer->GetRecastList(RECAST_ABILITY);
    recasts.resize(257);
    for (auto& recast : recasts)
    {
        recast.RecastTime = 60s;
    }
    target.PRecastContainer->DeleteByIndex(RECAST_ABILITY, std::size_t{ 256 });
    CHECK(recasts.size() == 257);
    CHECK(recasts.at(0).RecastTime == 60s);
    CHECK(recasts.at(255).RecastTime == 60s);
    CHECK(recasts.at(256).RecastTime == 0s);
}

TEST_CASE("Missing gambit cooldown abilities do not dereference null", "[security][gambits]")
{
    // A raw PC's destructor writes history. Intercept the complete fixture
    // lifetime rather than allowing a unit test to touch the configured database.
    class FixtureDatabase final : public db::Database
    {
    public:
        FixtureDatabase()
        : previous_(&db::getDatabase())
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
            queries.push_back(query);
            return {};
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

        std::vector<std::string> queries;

    private:
        db::Database* previous_;
    } database;

    {
        CCharEntity master;
        master.health.hp = 1;
        master.status    = xi::Status::Normal;
        CTrustEntity      trust(&master, 0, IsPassiveTrust::No);
        gambits::Gambit_t gambit;
        gambit.target_selector = gambits::G_TARGET::SELF;
        gambit.predicate_groups.emplace_back(
            gambits::G_LOGIC::AND,
            std::vector<gambits::Predicate_t>{
                { gambits::G_CONDITION::JA_ON_COOLDOWN, std::numeric_limits<uint16>::max() },
            });
        auto* controller = static_cast<CTrustController*>(trust.PAI->GetController());
        REQUIRE_FALSE(controller->m_GambitsContainer->AddGambit(gambit).empty());

        asio::io_context context;
        bool             completed = false;
        asio::co_spawn(context, controller->m_GambitsContainer->Tick(timer::now()), [&](std::exception_ptr exception)
                       {
                           CHECK_FALSE(exception);
                           completed = true;
                       });
        context.run();
        CHECK(completed);
        CHECK_FALSE(trust.PAI->IsEngaged());
    }
    REQUIRE(database.queries.size() == 1);
    CHECK(database.queries.front().starts_with("INSERT INTO char_history SET "));
}

TEST_CASE("fmt UTC conversion selects the supported thread-safe platform API", "[security][time]")
{
    using namespace fmt::detail;
#if FMT_MSC_VERSION
    static_assert(std::is_same_v<decltype(gmtime_s(std::declval<std::tm*>(), std::declval<const std::time_t*>())), int>);
#else
    static_assert(std::is_same_v<decltype(gmtime_r(std::declval<const std::time_t*>(), std::declval<std::tm*>())), std::tm*>);
#endif

    std::array<std::future<bool>, 4> workers;
    for (std::size_t worker = 0; worker < workers.size(); ++worker)
    {
        workers[worker] = std::async(std::launch::async, [worker]
                                     {
                                         for (std::size_t iteration = 0; iteration < 256; ++iteration)
                                         {
                                             const bool later = ((iteration + worker) % 2) != 0;
                                             const auto value = fmt::gmtime(static_cast<std::time_t>(later ? 946684800 : 0));
                                             if (value.tm_year != (later ? 100 : 70) || value.tm_mon != 0 || value.tm_mday != 1 ||
                                                 value.tm_hour != 0 || value.tm_min != 0 || value.tm_sec != 0 ||
                                                 value.tm_wday != (later ? 6 : 4) || value.tm_yday != 0 || value.tm_isdst != 0)
                                             {
                                                 return false;
                                             }
                                         }
                                         return true;
                                     });
    }
    for (auto& worker : workers)
    {
        CHECK(worker.get());
    }
}
