require('scripts/globals/instance')

describe('Instance entry event context', function()
    local function actor(id, zoneId, inEvent, target)
        local player =
        {
            id          = id,
            zoneId      = zoneId,
            inEvent     = inEvent,
            target      = target,
            targetReads = 0,
            entries     = {},
            timers      = {},
            positions   = {},
            releases    = 0,
        }

        function player:getID()
            return self.id
        end

        function player:getZoneID()
            return self.zoneId
        end

        function player:isInEvent()
            return self.inEvent
        end

        function player:getParty()
            return self.party
        end

        function player:setInstance(instance)
            self.instance = instance
        end

        function player:getEventTarget()
            self.targetReads = self.targetReads + 1
            assert(self.inEvent, 'queried an event target without an event')
            return self.target
        end

        function player:release()
            self.releases = self.releases + 1
            self.inEvent  = false
        end

        function player:startEvent(...)
            self.eventArgs = { ... }
            self.inEvent   = true
        end

        function player:instanceEntry(npc, response)
            self.entries[#self.entries + 1] = { npc, response }
        end

        function player:timer(delay, callback)
            self.timers[#self.timers + 1] = { delay, callback }
        end

        function player:setPos(...)
            self.positions[#self.positions + 1] = { ... }
        end

        return player
    end

    local function context(inEvent, target)
        local leader = actor(1, xi.zone.ALZADAAL_UNDERSEA_RUINS, inEvent, target)
        local member = actor(2, xi.zone.ALZADAAL_UNDERSEA_RUINS, false)
        local remote = actor(3, xi.zone.WEST_RONFAURE, false)
        leader.party = { leader, member, remote }

        local entryInfo
        for _, entry in ipairs(xi.instance.lookup[xi.zone.NYZUL_ISLE]) do
            if entry[1] == 7702 then
                entryInfo = entry
                break
            end
        end

        assert(entryInfo, 'native Waking the Colossus entry data is missing')
        local instance =
        {
            getID = function()
                return 7702
            end,

            getEntranceZoneID = function()
                return xi.zone.ALZADAAL_UNDERSEA_RUINS
            end,

            getZone = function()
                return
                {
                    getID = function()
                        return xi.zone.NYZUL_ISLE
                    end,
                }
            end,
        }

        return leader, member, remote, instance, entryInfo
    end

    local function assertEntranceState(leader, member, remote, instance, entryInfo)
        assert(leader.instance == instance and member.instance == instance, 'same-zone assignment changed')
        assert(remote.instance == nil, 'remote party member was assigned at the entrance')
        assert(member.releases == 1 and member.inEvent, 'member entrance event did not start')
        local memberEvent = entryInfo.memberEvent or entryInfo[4]
        assert(member.eventArgs[1] == memberEvent[1] and member.eventArgs[2] == memberEvent[2],
            'native member event arguments changed')
        for _, player in ipairs({ leader, member }) do
            assert(#player.timers == 1 and player.timers[1][1] == 35000, 'entrance failsafe timer changed')
            assert(type(player.timers[1][2]) == 'function', 'entrance timer callback is missing')
            assert(#player.positions == 0, 'entrance branch bypassed the event or failsafe')
        end

        assert(#remote.timers == 0 and #remote.positions == 0, 'remote member was changed')
    end

    it('assigns a direct solo caller without querying a nonexistent event target', function()
        local leader, _, _, instance, entryInfo = context(false)
        leader.party = { leader }

        xi.instance.onInstanceCreatedCallback(leader, instance, entryInfo)

        assert(leader.instance == instance, 'direct solo caller was not assigned')
        assert(leader.targetReads == 0 and #leader.entries == 0, 'direct solo caller queried an event target')
        assert(#leader.timers == 1 and leader.timers[1][1] == 35000, 'solo failsafe timer changed')
    end)

    it('preserves party assignment and timers for a direct caller without an event', function()
        local leader, member, remote, instance, entryInfo = context(false)

        xi.instance.onInstanceCreatedCallback(leader, instance, entryInfo)

        assertEntranceState(leader, member, remote, instance, entryInfo)
        assert(leader.targetReads == 0, 'direct party caller queried an event target')
        assert(#leader.entries == 0 and #member.entries == 0, 'direct caller emitted an NPC registration')
    end)

    it('retains registration packets when the initiating event has an NPC', function()
        local npc = {}
        local leader, member, remote, instance, entryInfo = context(true, npc)

        xi.instance.onInstanceCreatedCallback(leader, instance, entryInfo)

        assertEntranceState(leader, member, remote, instance, entryInfo)
        assert(leader.targetReads == 2, 'active-event target lookup paths changed')
        for _, player in ipairs({ leader, member }) do
            assert(#player.entries == 1 and player.entries[1][1] == npc and player.entries[1][2] == 4,
                'NPC registration target or response changed')
        end
    end)

    it('still queries an active event whose NPC target is missing', function()
        -- Record the native diagnostic path without intentionally emitting its warning.
        local leader, member, remote, instance, entryInfo = context(true)

        xi.instance.onInstanceCreatedCallback(leader, instance, entryInfo)

        assertEntranceState(leader, member, remote, instance, entryInfo)
        assert(leader.targetReads == 2, 'active-event missing-target diagnostic was bypassed')
        assert(#leader.entries == 0 and #member.entries == 0, 'missing NPC produced registration packets')
    end)

    it('preserves direct transport for the whole party outside the entrance zone', function()
        local leader, member, remote, instance, entryInfo = context(false)
        leader.zoneId = xi.zone.WEST_RONFAURE

        xi.instance.onInstanceCreatedCallback(leader, instance, entryInfo)

        assert(leader.targetReads == 0, 'direct transport queried an event target')
        for _, player in ipairs(leader.party) do
            assert(player.instance == instance and #player.positions == 1, 'direct party transport changed')
            assert(player.positions[1][5] == xi.zone.NYZUL_ISLE, 'direct transport used the wrong instance zone')
            assert(#player.timers == 0 and #player.entries == 0, 'direct transport entered the event path')
        end
    end)

    it('supports the native PC createInstance API without an active event', function()
        local player = xi.test.world:spawnPlayer({ zone = xi.zone.ALZADAAL_UNDERSEA_RUINS })
        if player:isInEvent() then
            player.events:finish()
        end

        assert(not player:isInEvent(), 'direct native API fixture is still in an event')
        player:createInstance(7702)
        xi.test.world:tick(xi.tick.TIME)

        local instance = player:getInstance()
        assert(instance and instance:getID() == 7702, 'native direct instance creation failed')
        assert(instance:getEntranceZoneID() == xi.zone.ALZADAAL_UNDERSEA_RUINS, 'native entrance zone changed')
        assert(not player:isInEvent(), 'native direct API fabricated an entrance event')
    end)
end)
