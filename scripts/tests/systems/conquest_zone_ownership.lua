require('scripts/globals/conquest')

describe('Conquest overseer zone ownership', function()
    local region = xi.region.RONFAURE
    local zoneId = xi.zone.WEST_RONFAURE
    local nationOffsets =
    {
        [xi.nation.SANDORIA] = { 0, 3, 7, 11 },
        [xi.nation.BASTOK]   = { 1, 4, 8, 12 },
        [xi.nation.WINDURST] = { 2, 5, 9, 13 },
        [xi.nation.BEASTMEN] = { 6, 14 },
        [xi.nation.OTHER]    = { 10 },
    }

    local function observeLoadedRegion(owner, missingOffset)
        local player = xi.test.world:spawnPlayer({ zone = zoneId })
        if player:isInEvent() then
            player.events:finish()
        end

        local nativeGetZone = GetZone
        local baseId        = zones[zoneId].npc.OVERSEER_BASE
        assert(nativeGetZone(zoneId) and baseId > 0, 'native outpost zone did not load')
        assert(GetNPCByID(baseId), 'native overseer fixture is missing')

        local states = {}
        local calls  = { baseId = baseId, states = states }
        calls.zone = stub('GetZone', function(requestedZone)
            assert(requestedZone == zoneId, 'wrong conquest zone')
            return nativeGetZone(requestedZone)
        end)

        calls.owner = stub('GetRegionOwner', function(requestedRegion)
            assert(requestedRegion == region, 'wrong conquest region')
            return owner
        end)

        calls.npc = stub('GetNPCByID', function(npcId)
            assert(npcId >= baseId and npcId <= baseId + 14, 'unexpected overseer lookup')
            if missingOffset and npcId == baseId + missingOffset then
                return nil
            end

            return
            {
                setStatus = function(_, status)
                    states[npcId] = status
                end,
            }
        end)

        return calls
    end

    it('does not query overseers or regional ownership for an unloaded zone', function()
        local zoneLookup = stub('GetZone', function()
            return nil
        end)

        local ownerLookup = stub('GetRegionOwner', function()
            return xi.nation.SANDORIA
        end)

        local npcLookup = stub('GetNPCByID', function()
            return nil
        end)

        xi.conquest.setRegionalConquestOverseers(region)

        zoneLookup:called(1)
        zoneLookup:calledWith(zoneId)
        ownerLookup:called(0)
        npcLookup:called(0)
    end)

    local owners =
    {
        { nation = xi.nation.SANDORIA, name = 'San d\'Oria' },
        { nation = xi.nation.BASTOK,   name = 'Bastok' },
        { nation = xi.nation.WINDURST, name = 'Windurst' },
        { nation = xi.nation.BEASTMEN, name = 'beastmen' },
        { nation = xi.nation.NEUTRAL,  name = 'neutral' },
    }

    for _, entry in ipairs(owners) do
        local owner = entry
        it('preserves loaded-zone visibility for ' .. owner.name .. ' ownership', function()
            local calls = observeLoadedRegion(owner.nation)

            xi.conquest.setRegionalConquestOverseers(region)

            calls.zone:called(1)
            calls.owner:called(1)
            calls.npc:called(15)
            for nation, offsets in pairs(nationOffsets) do
                local visible = nation == owner.nation or
                    (nation == xi.nation.OTHER and owner.nation ~= xi.nation.BEASTMEN and owner.nation ~= xi.nation.NEUTRAL)
                local expected = visible and xi.status.NORMAL or xi.status.DISAPPEAR
                for _, offset in ipairs(offsets) do
                    local npcId = calls.baseId + offset
                    calls.npc:calledWith(npcId)
                    assert(calls.states[npcId] == expected, 'loaded overseer visibility changed')
                end
            end
        end)
    end

    it('still queries missing nonzero overseers in a loaded zone', function()
        -- Nil-returning test lookup records the diagnostic path without a native warning.
        local missingOffset = 7
        local calls         = observeLoadedRegion(xi.nation.SANDORIA, missingOffset)

        xi.conquest.setRegionalConquestOverseers(region)

        calls.zone:called(1)
        calls.owner:called(1)
        calls.npc:called(15)
        calls.npc:calledWith(calls.baseId + missingOffset)
        assert(calls.states[calls.baseId + missingOffset] == nil, 'missing actor was mutated')
        assert(calls.states[calls.baseId] == xi.status.NORMAL, 'remaining loaded actors were skipped')
    end)
end)
