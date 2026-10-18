/*
===========================================================================

  Copyright (c) 2026 LandSandBoat Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

===========================================================================
*/

#include "map/entities/battle_entity.h"
#include "map/monstrosity.h"
#include "map/recast_container.h"

#include <catch2/catch_test_macros.hpp>

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
