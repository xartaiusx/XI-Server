local event = require('scripts/events/strange_happenings')

describe('Strange Happenings zone ownership', function()
    local encounters =
    {
        { zone = xi.zone.ALZADAAL_UNDERSEA_RUINS, mob = 'ALEXANDER', name = 'Alzadaal' },
        { zone = xi.zone.RUAUN_GARDENS,          mob = 'KIRIN',     name = 'RuAun' },
        { zone = xi.zone.THE_BOYAHDA_TREE,       mob = 'FAFNIR',    name = 'Boyahda' },
    }

    local function ignoreAction()
        return nil
    end

    local function observeLoadedEncounter(encounter, options)
        options = options or {}

        -- Load real public zone data before installing any lookup or action mocks.
        local player = xi.test.world:spawnPlayer({ zone = encounter.zone })
        if player:isInEvent() then
            player.events:finish()
        end

        local nativeGetZone = GetZone
        local ID            = zones[encounter.zone]
        local mobId         = ID.mob[encounter.mob]
        local chestId       = ID.npc.STRANGE_HAPPENINGS_CHEST

        assert(nativeGetZone(encounter.zone), 'native fixture zone did not load')
        assert(GetMobByID(mobId), 'native fixture encounter mob is missing')
        assert(GetNPCByID(chestId), 'native fixture encounter chest is missing')

        local mob =
        {
            isSpawned = function()
                return options.spawned == true
            end,
        }

        local chest =
        {
            getID = function()
                return chestId
            end,

            getStatus = function()
                return options.chestStatus or xi.status.NORMAL
            end,
        }

        local calls =
        {
            mobId   = mobId,
            chestId = chestId,
            chest   = chest,
        }

        -- Model one process-owned zone, regardless of earlier suites' loaded zones.
        calls.zone = stub('GetZone', function(zoneId)
            if zoneId == encounter.zone then
                return nativeGetZone(zoneId)
            end

            return nil
        end)

        calls.mob = stub('GetMobByID', function()
            if options.missingEntities then
                return nil
            end

            return mob
        end)

        calls.npc = stub('GetNPCByID', function()
            if options.missingEntities then
                return nil
            end

            return chest
        end)

        calls.respawn   = stub('DisallowRespawn', ignoreAction)
        calls.spawn     = stub('SpawnMob', ignoreAction)
        calls.despawn   = stub('DespawnMob', ignoreAction)
        calls.disappear = stub('npcUtil.disappearCrate', ignoreAction)

        return calls
    end

    local function assertNoMutations(calls)
        calls.respawn:called(0)
        calls.spawn:called(0)
        calls.despawn:called(0)
        calls.disappear:called(0)
    end

    before_each(function()
        -- The native encounter actors initialize in their ordinary disabled state.
        xi.test.world:setSetting('main.ENABLE_STRANGE_HAPPENINGS', 0)
    end)

    it('does not query entities in unloaded zones during start or stop', function()
        local zoneLookup = stub('GetZone', function()
            return nil
        end)

        local mobLookup = stub('GetMobByID', function()
            return nil
        end)

        local npcLookup = stub('GetNPCByID', function()
            return nil
        end)

        xi.test.world:setSetting('main.ENABLE_STRANGE_HAPPENINGS', 1)
        event:checkStarting()
        xi.test.world:setSetting('main.ENABLE_STRANGE_HAPPENINGS', 0)
        event:checkEnding()

        zoneLookup:called(6)
        mobLookup:called(0)
        npcLookup:called(0)
    end)

    for _, entry in ipairs(encounters) do
        local encounter = entry

        it('starts only the loaded encounter in ' .. encounter.name, function()
            local calls = observeLoadedEncounter(encounter)

            xi.test.world:setSetting('main.ENABLE_STRANGE_HAPPENINGS', 1)
            event:checkStarting()

            calls.zone:called(3)
            calls.mob:called(1)
            calls.mob:calledWith(calls.mobId)
            calls.npc:called(0)
            calls.respawn:called(1)
            calls.respawn:calledWith(calls.mobId, false)
            calls.spawn:called(1)
            calls.spawn:calledWith(calls.mobId)
            calls.despawn:called(0)
            calls.disappear:called(0)
        end)

        it('stops the loaded encounter and visible chest in ' .. encounter.name, function()
            local calls = observeLoadedEncounter(encounter, { spawned = true })

            event:checkEnding()

            calls.zone:called(3)
            calls.mob:called(1)
            calls.mob:calledWith(calls.mobId)
            calls.npc:called(1)
            calls.npc:calledWith(calls.chestId)
            calls.respawn:called(1)
            calls.respawn:calledWith(calls.mobId, true)
            calls.despawn:called(1)
            calls.despawn:calledWith(calls.mobId)
            calls.disappear:called(1)
            calls.disappear:calledWith(calls.chest)
            calls.spawn:called(0)
        end)
    end

    it('does not respawn an already spawned encounter', function()
        local calls = observeLoadedEncounter(encounters[2], { spawned = true })

        xi.test.world:setSetting('main.ENABLE_STRANGE_HAPPENINGS', 1)
        event:checkStarting()

        calls.mob:called(1)
        calls.npc:called(0)
        assertNoMutations(calls)
    end)

    it('leaves an unspawned encounter and hidden chest untouched', function()
        local calls = observeLoadedEncounter(encounters[2], { chestStatus = xi.status.DISAPPEAR })

        event:checkEnding()

        calls.mob:called(1)
        calls.npc:called(1)
        assertNoMutations(calls)
    end)

    it('still invokes missing-entity lookup paths in a loaded zone', function()
        -- Record nil-returning lookups without emitting an intentional native warning.
        -- Native lookup diagnostics are unchanged; ownership must not bypass them.
        local calls = observeLoadedEncounter(encounters[2], { missingEntities = true })

        event:checkEnding()

        calls.zone:called(3)
        calls.mob:called(1)
        calls.mob:calledWith(calls.mobId)
        calls.npc:called(1)
        calls.npc:calledWith(calls.chestId)
        assertNoMutations(calls)
    end)
end)
