/*
===========================================================================

  Copyright (c) 2026 LandSandBoat Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program. If not, see http://www.gnu.org/licenses/

===========================================================================
*/

#include "common/application.h"
#include "common/engine.h"
#include "common/logging.h"
#include "common/lua.h"

#include <spdlog/spdlog.h>

#include <array>
#include <atomic>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <memory>
#include <string>
#include <string_view>
#include <thread>

namespace
{

struct TeardownState
{
    bool              engineDestroyed  = false;
    bool              schedulerStopped = false;
    bool              loggerAlive      = false;
    std::atomic<bool> workerStarted{ false };
    std::atomic<bool> workerStopped{ false };
    bool              workerJoinedBeforeEngine = false;
};

class ProbeEngine final : public Engine
{
public:
    ProbeEngine(TeardownState& state, Scheduler& scheduler)
    : state_(state)
    , scheduler_(scheduler)
    {
    }

    ~ProbeEngine() override
    {
        state_.engineDestroyed  = true;
        state_.schedulerStopped = scheduler_.closeRequested();
        state_.workerJoinedBeforeEngine =
            state_.workerStopped.load(std::memory_order_acquire);
        state_.loggerAlive = spdlog::get("debug") != nullptr;
        if (state_.loggerAlive)
        {
            // The baseline fails the lifetime assertion without dereferencing
            // its freed logger. Production diagnostics remain unchanged.
            ShowInfo("Lifecycle teardown marker");
        }
    }

private:
    TeardownState& state_;
    Scheduler&     scheduler_;
};

class ProbeApplication final : public Application
{
public:
    ProbeApplication(int argc, char** argv, TeardownState& state)
    : Application(
          {
              .serverName = "lifecycle",
              .arguments  = {
                  { .name = "--no-engine",
                    .description =
                        "Exercise early teardown before engine creation.",
                    .type = ArgumentType::Flag },
                  { .name = "--already-stopped",
                    .description =
                        "Exercise teardown after scheduler stop.",
                    .type = ArgumentType::Flag },
              },
          },
          argc,
          argv)
    , state_(state)
    {
        scheduler_.postToWorkerThread([&state, scheduler = &scheduler_]()
                                      {
                                          state.workerStarted.store(true, std::memory_order_release);
                                          const auto deadline =
                                              std::chrono::steady_clock::now() + std::chrono::seconds(5);
                                          while (!scheduler->closeRequested() &&
                                                 std::chrono::steady_clock::now() < deadline)
                                          {
                                              std::this_thread::sleep_for(std::chrono::milliseconds(1));
                                          }
                                          state.workerStopped.store(scheduler->closeRequested(),
                                                                    std::memory_order_release);
                                      });
        const auto deadline =
            std::chrono::steady_clock::now() + std::chrono::seconds(5);
        while (!state.workerStarted.load(std::memory_order_acquire) &&
               std::chrono::steady_clock::now() < deadline)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
        if (!args().get<bool>("--no-engine"))
        {
            engine_ = createEngine();
        }
        if (args().get<bool>("--already-stopped"))
        {
            scheduler_.stop();
        }
    }

    auto createEngine() -> std::unique_ptr<Engine> override
    {
        return std::make_unique<ProbeEngine>(state_, scheduler_);
    }

private:
    TeardownState& state_;
};

} // namespace

int main(int argc, char** argv)
{
    TeardownState state;
    auto          application = std::make_unique<ProbeApplication>(argc, argv, state);
    const auto    noEngine    = application->args().get<bool>("--no-engine");
    const auto    appendDate  = application->args().get<bool>("--append-date");
    const auto    logPath =
        application->args().present<std::string>("--log").value_or(
            "log/lifecycle-server.log");
    std::error_code                           error;
    const auto                                offset = std::filesystem::file_size(logPath, error);
    constexpr std::array<std::string_view, 4> printedText{
        "LUA_LITERAL_PERCENT:100%",
        "LUA_LITERAL_PRINTF:%s %n %d %% %",
        "LUA_LITERAL_BRACES:{} {name} {1:>8} {{}} } {",
        "LUA_LITERAL_VARIADIC: 50% %s %n {} true nil",
    };
    bool printSucceeded                         = true;
    lua["xi"]["settings"]["logging"]["LOG_LUA"] = true;
    {
        // Release all Lua references before lua_cleanup replaces the state.
        const sol::protected_function print = lua["print"];
        for (std::size_t i = 0; i < printedText.size() - 1; ++i)
        {
            const auto result = print(std::string(printedText[i]));
            printSucceeded    = result.valid() && printSucceeded;
        }
        const auto result = print("LUA_LITERAL_VARIADIC:", "50%", "%s", "%n", "{}", true, sol::lua_nil);
        printSucceeded    = result.valid() && printSucceeded;
    }
    application.reset();
    lua_cleanup();

    if (error || appendDate)
    {
        std::cerr << "Lifecycle probe requires an undated, readable log file.\n";
        return 1;
    }
    if (!state.workerStarted.load() || !state.workerStopped.load())
    {
        std::cerr << "Application did not finish its worker before teardown.\n";
        return 1;
    }
    if (spdlog::get("debug") != nullptr || state.engineDestroyed == noEngine)
    {
        std::cerr << "Application ownership or logging shutdown failed.\n";
        return 1;
    }
    std::ifstream log(logPath, std::ios::binary);
    log.seekg(static_cast<std::streamoff>(offset));
    const std::string tail{ std::istreambuf_iterator<char>(log), std::istreambuf_iterator<char>() };
    if (!log || !printSucceeded || tail.find("logging exception!") != std::string::npos)
    {
        std::cerr << "Literal Lua printing failed.\n";
        return 1;
    }
    for (const auto text : printedText)
    {
        const auto position = tail.find(text);
        if (position == std::string::npos || tail.find(text, position + text.size()) != std::string::npos)
        {
            std::cerr << "Literal Lua text was not emitted exactly once.\n";
            return 1;
        }
    }
    if (!noEngine)
    {
        if (!state.schedulerStopped || !state.workerJoinedBeforeEngine ||
            !state.loggerAlive)
        {
            std::cerr << "Engine teardown outlived its scheduler or logger.\n";
            return 1;
        }
        if (tail.find("Lifecycle teardown marker") == std::string::npos)
        {
            std::cerr << "Engine teardown log was not flushed.\n";
            return 1;
        }
    }
    std::cout << "Application lifecycle regression passed.\n";
    return 0;
}
