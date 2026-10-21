require('scripts/globals/caskets')

describe('Treasure casket capacity', function()
    ---@type CClientEntityPair
    local player
    local mob
    local baseId

    before_each(function()
        player = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE })
        if player:isInEvent() then
            player.events:finish()
        end

        local zone    = GetZone(xi.zone.WEST_RONFAURE)
        local caskets = zone:queryEntitiesByName('Treasure_Casket')
        assert(#caskets == 16, 'expected sixteen native casket slots')
        baseId = caskets[1]:getID()
        assert(baseId > 0 and GetNPCByID(baseId), 'native casket fixture is missing')

        mob =
        {
            getZone = function()
                return zone
            end,
        }

        -- Exercise allocation without spawning rewards or claiming real actors.
        xi.test.world:setSetting('main.CASKET_DROP_RATE', 0)
    end)

    it('does not query an NPC when the zone has no caskets', function()
        mob.getZone = function()
            return
            {
                queryEntitiesByName = function()
                    return {}
                end,
            }
        end

        local lookup = stub('GetNPCByID', function()
            return nil
        end)

        xi.caskets.spawnCasket(player, mob, 0, 0, 0, 0)

        lookup:called(0)
    end)

    it('does not query NPC zero when all sixteen slots are occupied', function()
        local seen = {}
        local lookup = stub('GetNPCByID', function(npcId)
            assert(npcId > 0, 'capacity exhaustion queried NPC zero')
            seen[#seen + 1] = npcId
            return
            {
                getLocalVar = function(_, name)
                    assert(name == '[caskets]SPAWNSTATUS')
                    return 1
                end,
            }
        end)

        xi.caskets.spawnCasket(player, mob, 0, 0, 0, 0)

        lookup:called(16)
        for offset = 0, 15 do
            assert(seen[offset + 1] == baseId + offset, 'casket capacity scan changed')
        end
    end)

    it('reuses the first available slot without scanning later slots', function()
        local availableId = baseId + 5
        local seen        = {}
        local lookup = stub('GetNPCByID', function(npcId)
            assert(npcId > 0)
            seen[#seen + 1] = npcId
            return
            {
                getLocalVar = function(_, name)
                    assert(name == '[caskets]SPAWNSTATUS')
                    return npcId == availableId and 0 or 1
                end,
            }
        end)

        xi.caskets.spawnCasket(player, mob, 0, 0, 0, 0)

        lookup:called(8)
        for offset = 0, 5 do
            assert(seen[offset + 1] == baseId + offset, 'casket reuse order changed')
        end

        assert(seen[7] == availableId and seen[8] == availableId, 'selected casket was not revalidated')
    end)

    it('still queries every nonzero actor when the native slots are missing', function()
        local lookup = stub('GetNPCByID', function(npcId)
            assert(npcId >= baseId and npcId <= baseId + 15, 'unexpected missing-actor lookup')
            return nil
        end)

        xi.caskets.spawnCasket(player, mob, 0, 0, 0, 0)

        lookup:called(16)
        for offset = 0, 15 do
            lookup:calledWith(baseId + offset)
        end
    end)

    it('revalidates a selected nonzero actor that disappears before use', function()
        local calls = 0
        local lookup = stub('GetNPCByID', function(npcId)
            assert(npcId == baseId, 'selected casket identity changed')
            calls = calls + 1
            if calls == 1 then
                return
                {
                    getLocalVar = function()
                        return 0
                    end,
                }
            end

            return nil
        end)

        xi.caskets.spawnCasket(player, mob, 0, 0, 0, 0)

        lookup:called(2)
    end)
end)
