describe('Stable chocobo patrols', function()
    -- Walking can carry a chocobo a hair past its point.
    local margin = 0.2

    local walkers =
    {
        { zone = xi.zone.SOUTHERN_SAN_DORIA, id = 17719338, minX = 11.3, maxX = 18.6, minZ = -92.5, maxZ = -87.6 },
        { zone = xi.zone.SOUTHERN_SAN_DORIA, id = 17719339, minX = 24.2, maxX = 27.6, minZ = -92.4, maxZ = -90.0 },
        { zone = xi.zone.SOUTHERN_SAN_DORIA, id = 17719340, minX = 13.3, maxX = 19.9, minZ = -100.4, maxZ = -96.7 },
        { zone = xi.zone.WINDURST_WOODS,     id = 17764417, minX = 121.0, maxX = 128.3, minZ = -111.2, maxZ = -102.2 },
    }

    local firstPoint = { x = 11.348, y = 2.201, z = -87.631, wait = 2900 }
    ---@type CBaseEntity?
    local headingNpc = nil

    after_each(function()
        if headingNpc then
            headingNpc:clearPath()
            headingNpc:setPos(firstPoint.x, firstPoint.y, firstPoint.z, 0)
            headingNpc:setLocalVar('point', 1)
            headingNpc:pathThrough({ firstPoint }, xi.path.flag.PATROL)
            headingNpc:continuePath()
            headingNpc = nil
        end
    end)

    it('turns to heading 0 when it picks the point it stands on', function()
        local player = xi.test.world:spawnPlayer({ zone = xi.zone.SOUTHERN_SAN_DORIA })
        stub('math.randomInt', 1)

        -- Native arrival allows a small residual, so establish the exact self-point fixture.
        local npc = player.entities:get(17719338)
        headingNpc = npc
        npc:clearPath()
        npc:setPos(firstPoint.x, firstPoint.y, firstPoint.z, 128)
        npc:setLocalVar('point', 1)
        npc:pathThrough({ firstPoint }, xi.path.flag.PATROL)
        npc:continuePath()
        assert(npc:getRotPos() == 128, 'The turn must not be pre-satisfied')

        local turned = false
        for _ = 1, 60 do
            xi.test.world:skipTime(1)

            local pos = npc:getPos()
            if
                math.abs(pos.x - firstPoint.x) < 0.01 and
                math.abs(pos.z - firstPoint.z) < 0.01 and
                npc:getRotPos() == 0
            then
                turned = true
                break
            end
        end

        local pos = npc:getPos()
        assert(turned, string.format('Expected first point (%.3f, %.3f) and heading 0, got (%.6f, %.6f) and heading %d',
            firstPoint.x, firstPoint.z, pos.x, pos.z, npc:getRotPos()))
    end)

    for _, walker in ipairs(walkers) do
        it(string.format('walks between its points (%d)', walker.id), function()
            local player = xi.test.world:spawnPlayer({ zone = walker.zone })

            local npc   = player.entities:get(walker.id)
            local start = npc:getPos()
            local moved = false

            for _ = 1, 120 do
                xi.test.world:skipTime(1)

                local pos = npc:getPos()
                moved     = moved or pos.x ~= start.x or pos.z ~= start.z

                assert(pos.x >= walker.minX - margin and pos.x <= walker.maxX + margin, string.format('x %.3f left the pen', pos.x))
                assert(pos.z >= walker.minZ - margin and pos.z <= walker.maxZ + margin, string.format('z %.3f left the pen', pos.z))
            end

            assert(moved, 'Expected the chocobo to walk')
        end)
    end

    it('walks Eight of Spades around its three points', function()
        local player = xi.test.world:spawnPlayer({ zone = xi.zone.WINDURST_WOODS })

        local npc   = player.entities:get(17764518)
        local start = npc:getPos()
        local moved = false

        for _ = 1, 70 do
            xi.test.world:skipTime(1)

            local pos = npc:getPos()
            moved     = moved or pos.x ~= start.x or pos.z ~= start.z

            assert(pos.x >= 89.8 - margin and pos.x <= 96.9 + margin and pos.z >= -79.9 - margin and pos.z <= -61.8 + margin, string.format('Left the route at %.3f %.3f', pos.x, pos.z))
        end

        assert(moved, 'Expected Eight of Spades to walk')
    end)

    it('turns Femardaque between two headings without moving', function()
        local player = xi.test.world:spawnPlayer({ zone = xi.zone.WINDURST_WOODS })

        local npc      = player.entities:get(17764505)
        local start    = npc:getPos()
        local headings = {}

        for _ = 1, 60 do
            xi.test.world:skipTime(1)

            local pos = npc:getPos()
            assert(pos.x == start.x and pos.z == start.z, 'Expected Femardaque to stay put')
            headings[npc:getRotPos()] = true
        end

        assert(headings[56] and headings[250], 'Expected both headings within a minute')
    end)
end)
