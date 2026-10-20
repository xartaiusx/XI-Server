/*
===========================================================================

  Copyright (c) 2026 LandSandBoat Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

===========================================================================
*/

#include "map/navmesh/navmesh_builder.h"

#include <DetourNavMesh.h>
#include <Recast.h>
#include <RecastAlloc.h>
#include <catch2/catch_test_macros.hpp>

#include <array>
#include <limits>
#include <string>
#include <vector>

namespace
{

// Only the count predicate sees these borrowed pointers; no mesh builder reads
// their contents. Detach them before rcContourSet's owning destructor runs.
struct ContourCounts
{
    explicit ContourCounts(const int first, const int second = 0)
    {
        contours[0].nverts = first;
        contours[1].nverts = second;
        contours[0].verts  = vertices.data();
        contours[1].verts  = vertices.data();
        set.conts          = contours.data();
        set.nconts         = static_cast<int>(contours.size());
    }

    ~ContourCounts()
    {
        set.conts  = nullptr;
        set.nconts = 0;
    }

    ContourCounts(const ContourCounts&)            = delete;
    ContourCounts& operator=(const ContourCounts&) = delete;
    ContourCounts(ContourCounts&&)                 = delete;
    ContourCounts& operator=(ContourCounts&&)      = delete;

    std::array<int, 4>       vertices{};
    std::array<rcContour, 2> contours{};
    rcContourSet             set;
};

class CapturingRecastContext final : public rcContext
{
public:
    std::string message;

protected:
    void doLog(const rcLogCategory, const char* text, const int length) override
    {
        message.assign(text, static_cast<std::size_t>(length));
    }
};

} // namespace

TEST_CASE("Navmesh polygon limits match Recast and Detour capacity", "[security][navmesh]")
{
    for (const int invalid : std::array{ -1, 0, 2, 7, std::numeric_limits<int>::max() })
    {
        CHECK_FALSE(NavMeshBuilder::supportsPolygonLimit(invalid));
    }
    for (int valid = 3; valid <= DT_VERTS_PER_POLYGON; ++valid)
    {
        CHECK(NavMeshBuilder::supportsPolygonLimit(valid));
    }
}

TEST_CASE("Navmesh contour sums reject before signed addition or index overflow", "[security][navmesh]")
{
    constexpr int limit = RC_MESH_NULL_IDX - 2;
    ContourCounts counts(limit);
    CHECK(NavMeshBuilder::supportsContourSet(counts.set));

    counts.contours[0].nverts = limit + 1;
    CHECK_FALSE(NavMeshBuilder::supportsContourSet(counts.set));

    counts.contours[0].nverts = limit;
    counts.contours[1].nverts = 3;
    CHECK_FALSE(NavMeshBuilder::supportsContourSet(counts.set));

    counts.contours[1].nverts = std::numeric_limits<int>::max();
    CHECK_FALSE(NavMeshBuilder::supportsContourSet(counts.set));

    counts.contours[0].nverts = limit - 3;
    counts.contours[1].nverts = 3;
    CHECK(NavMeshBuilder::supportsContourSet(counts.set));
}

TEST_CASE("Navmesh contour validation rejects malformed counts and active null buffers", "[security][navmesh]")
{
    ContourCounts counts(3);
    counts.set.nconts = -1;
    CHECK_FALSE(NavMeshBuilder::supportsContourSet(counts.set));

    counts.set.nconts = 1;
    counts.set.conts  = nullptr;
    CHECK_FALSE(NavMeshBuilder::supportsContourSet(counts.set));

    counts.set.conts          = counts.contours.data();
    counts.contours[0].nverts = -1;
    CHECK_FALSE(NavMeshBuilder::supportsContourSet(counts.set));

    counts.contours[0].nverts = 3;
    counts.contours[0].verts  = nullptr;
    CHECK_FALSE(NavMeshBuilder::supportsContourSet(counts.set));

    // Recast deliberately skips contours with fewer than three vertices.
    for (const int inactive : std::array{ 0, 1, 2 })
    {
        counts.contours[0].nverts = inactive;
        CHECK(NavMeshBuilder::supportsContourSet(counts.set));
    }
    counts.set.nconts = 0;
    counts.set.conts  = nullptr;
    CHECK(NavMeshBuilder::supportsContourSet(counts.set));
}

TEST_CASE("Any invalid tile rejects mixed results before mesh installation", "[security][navmesh]")
{
    std::vector<TileResult> results(2);
    CHECK_FALSE(NavMeshBuilder::hasTileValidationFailure(results));

    results[0].validationFailed = true;
    CHECK(NavMeshBuilder::hasTileValidationFailure(results));
    results[0].validationFailed = false;
    results[1].validationFailed = true;
    CHECK(NavMeshBuilder::hasTileValidationFailure(results));
    results[0].validationFailed = true;
    CHECK(NavMeshBuilder::hasTileValidationFailure(results));

    results.clear();
    CHECK_FALSE(NavMeshBuilder::hasTileValidationFailure(results));
}

TEST_CASE("Recast logs pointer-sized region counts without truncation", "[security][navmesh][format]")
{
    static_assert(std::numeric_limits<rcSizeType>::digits > std::numeric_limits<int>::digits);
    CapturingRecastContext context;
    for (const rcSizeType count : std::array<rcSizeType, 3>{
             0, 1, static_cast<rcSizeType>(std::numeric_limits<int>::max()) + 42 })
    {
        context.log(RC_LOG_ERROR, "rcBuildRegions: %lld overlapping regions.", static_cast<long long>(count));
        CHECK(context.message == "rcBuildRegions: " + std::to_string(count) + " overlapping regions.");
    }
}
