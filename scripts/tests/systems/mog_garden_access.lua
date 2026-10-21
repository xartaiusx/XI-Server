local ffi = require('ffi')

describe('Mog Garden access foundation', function()
    local function settle()
        for _ = 1, 4 do
            xi.test.world:skipTime(1)
        end
    end

    local function finishEvent(player)
        if player:isInEvent() then
            player.events:finish()
        end
    end

    local function requestExit(player, mode)
        -- 0x05E: RectID at 0x04, exit bit at 0x16, exit mode at 0x17.
        local packet = ffi.new('uint8_t[24]')
        ffi.copy(packet + 4, 'zmrq', 4)
        packet[23] = mode
        player.packets:send(0x05E, packet, assert(ffi.sizeof(packet)))
        settle()
    end

    local function ownMogHouse()
        local player = xi.test.world:spawnPlayer({ zone = xi.zone.BASTOK_MINES })
        finishEvent(player)
        player:setNation(xi.nation.BASTOK)
        player:gotoMogHouse(xi.zone.BASTOK_MINES)
        finishEvent(player)
        assert(player:inMogHouse(xi.mogHouse.OWN), 'own Mog House fixture failed')

        return player
    end

    local function registeredAdoulinPlayer()
        local player = xi.test.world:spawnPlayer({ zone = xi.zone.WESTERN_ADOULIN })
        finishEvent(player)

        -- Only the synthetic player receives this mission fixture.
        player:addMission(xi.mission.log_id.SOA, xi.mission.id.soa.PIONEER_REGISTRATION)
        player:completeMission(xi.mission.log_id.SOA, xi.mission.id.soa.PIONEER_REGISTRATION)
        player:addMission(xi.mission.log_id.SOA, xi.mission.id.soa.LIFE_ON_THE_FRONTIER)
        player:addKeyItem(xi.keyItem.PIONEERS_BADGE)

        return player
    end

    local function progression(player)
        return
        {
            mission              = player:getCurrentMission(xi.mission.log_id.SOA),
            registrationComplete = player:hasCompletedMission(xi.mission.log_id.SOA, xi.mission.id.soa.PIONEER_REGISTRATION),
            frontierComplete     = player:hasCompletedMission(xi.mission.log_id.SOA, xi.mission.id.soa.LIFE_ON_THE_FRONTIER),
            pioneersBadge        = player:hasKeyItem(xi.keyItem.PIONEERS_BADGE),
            adoulinMap           = player:hasKeyItem(xi.keyItem.MAP_OF_ADOULIN),
            bayld                = player:getCurrency('bayld'),
            gil                  = player:getGil(),
        }
    end

    local function assertProgressionUnchanged(player, before)
        local after = progression(player)
        for field, expected in pairs(before) do
            assert(after[field] == expected, 'Garden access changed progression: ' .. field)
        end
    end

    before_each(function()
        xi.test.world:setSetting('main.ENABLE_MOG_GARDEN', 1)
    end)

    it('enters from an own Mog House when access is enabled', function()
        local player = ownMogHouse()
        requestExit(player, 127) -- MogGarden.

        assert(player:getZoneID() == xi.zone.MOG_GARDEN, 'Garden entry failed')
        assert(not player:inMogHouse(), 'Mog House state survived Garden entry')
    end)

    it('uses the ordinary city exit when access is disabled', function()
        xi.test.world:setSetting('main.ENABLE_MOG_GARDEN', 0)
        local player = ownMogHouse()
        requestExit(player, 127)

        assert(player:getZoneID() == xi.zone.BASTOK_MINES, 'wrong fallback zone')
        assert(not player:inMogHouse(), 'fallback did not leave the Mog House')
    end)

    it('preserves the ordinary city exit when Garden access is enabled', function()
        local player = ownMogHouse()
        requestExit(player, 0) -- AreaEnteredFrom.

        assert(player:getZoneID() == xi.zone.BASTOK_MINES, 'ordinary exit changed zone')
        assert(not player:inMogHouse(), 'ordinary exit did not leave the Mog House')
    end)

    it('rejects a Garden exit requested by a Mog House visitor', function()
        local host = xi.test.world:spawnPlayer({ zone = xi.zone.BASTOK_MARKETS })
        local visitor = xi.test.world:spawnPlayer({ zone = xi.zone.BASTOK_MARKETS })
        finishEvent(host)
        finishEvent(visitor)

        visitor:setPos(host:getXPos(), host:getYPos(), host:getZPos())
        host.actions:inviteToParty(visitor)
        visitor.actions:acceptPartyInvite()
        assert(visitor:getPartySize() == 2, 'party fixture failed')

        host:setNation(xi.nation.BASTOK)
        host:gotoMogHouse(xi.zone.BASTOK_MINES)
        finishEvent(host)

        local packet = ffi.new('uint8_t[8]')
        packet[4] = 1 -- Open Mog House.
        host.packets:send(0x0CB, packet, assert(ffi.sizeof(packet)))
        settle()

        visitor.entities:gotoAndTrigger('Hildith', { eventId = 488, finishOption = host:getID() })
        settle()
        assert(visitor:inMogHouse(xi.mogHouse.VISITING), 'visit fixture failed')

        requestExit(visitor, 127)

        assert(visitor:getZoneID() == xi.zone.BASTOK_MINES, 'visitor changed zone')
        assert(visitor:inMogHouse(xi.mogHouse.VISITING), 'visitor left the host')
        assert(visitor:getMogHouseOwner():getID() == host:getID(), 'owner changed')
    end)

    it('enters through Dangueubert after Pioneer Registration', function()
        local player = registeredAdoulinPlayer()
        local before = progression(player)

        player.entities:gotoAndTrigger('Dangueubert', { eventId = 546, finishOption = 1 })
        settle()

        assert(player:getZoneID() == xi.zone.MOG_GARDEN, 'Dangueubert entry failed')
        assert(not player:inMogHouse(), 'NPC route created Mog House state')
        player.assert:hasCompletedMission(xi.mission.log_id.SOA, xi.mission.id.soa.PIONEER_REGISTRATION)
        player.assert:hasMission(xi.mission.log_id.SOA, xi.mission.id.soa.LIFE_ON_THE_FRONTIER)
        player.assert:hasKI(xi.keyItem.PIONEERS_BADGE)
        assertProgressionUnchanged(player, before)
    end)

    it('does not enter through Dangueubert when Garden access is disabled', function()
        xi.test.world:setSetting('main.ENABLE_MOG_GARDEN', 0)
        local player = registeredAdoulinPlayer()
        local before = progression(player)

        player.entities:gotoAndTrigger('Dangueubert', { eventId = 546, finishOption = 1 })
        settle()

        assert(player:getZoneID() == xi.zone.WESTERN_ADOULIN, 'disabled NPC route entered the Garden')
        assert(not player:inMogHouse(), 'disabled NPC route created Mog House state')
        player.events:expectNotInEvent()
        assertProgressionUnchanged(player, before)
    end)

    it('rechecks Garden access when the Dangueubert event finishes', function()
        local player = registeredAdoulinPlayer()
        local before = progression(player)

        player.entities:gotoAndTrigger('Dangueubert')
        assert(player:isInEvent(), 'Dangueubert menu did not start')
        xi.test.world:setSetting('main.ENABLE_MOG_GARDEN', 0)
        player.events:expect({ eventId = 546, finishOption = 1 })
        settle()

        assert(player:getZoneID() == xi.zone.WESTERN_ADOULIN, 'NPC route used a stale enabled setting')
        player.events:expectNotInEvent()
        assertProgressionUnchanged(player, before)
    end)

    it('leaves a cancelled Dangueubert entry in Western Adoulin', function()
        local player = registeredAdoulinPlayer()
        local before = progression(player)

        player.entities:gotoAndTrigger('Dangueubert', { eventId = 546, finishOption = 0 })
        settle()

        assert(player:getZoneID() == xi.zone.WESTERN_ADOULIN, 'cancelled NPC route changed zone')
        player.events:expectNotInEvent()
        assertProgressionUnchanged(player, before)
    end)

    it('does not enter through Dangueubert before Pioneer Registration', function()
        local player = xi.test.world:spawnPlayer({ zone = xi.zone.WESTERN_ADOULIN })
        finishEvent(player)
        assert(not player:hasCompletedMission(xi.mission.log_id.SOA, xi.mission.id.soa.PIONEER_REGISTRATION),
            'unregistered fixture already completed Pioneer Registration')
        local before = progression(player)

        player.entities:gotoAndTrigger('Dangueubert', { eventId = 546, finishOption = 1 })
        settle()

        assert(player:getZoneID() == xi.zone.WESTERN_ADOULIN, 'unregistered NPC route entered the Garden')
        player.events:expectNotInEvent()
        assertProgressionUnchanged(player, before)
    end)

    it('requires completed rather than active Pioneer Registration', function()
        local player = xi.test.world:spawnPlayer({ zone = xi.zone.WESTERN_ADOULIN })
        finishEvent(player)
        player:addMission(xi.mission.log_id.SOA, xi.mission.id.soa.PIONEER_REGISTRATION)
        assert(not player:hasCompletedMission(xi.mission.log_id.SOA, xi.mission.id.soa.PIONEER_REGISTRATION),
            'active mission fixture already completed Pioneer Registration')
        local before = progression(player)

        player.entities:gotoAndTrigger('Dangueubert', { eventId = 546, finishOption = 1 })
        settle()

        assert(player:getZoneID() == xi.zone.WESTERN_ADOULIN, 'active mission bypassed the completion requirement')
        player.events:expectNotInEvent()
        assertProgressionUnchanged(player, before)
    end)
end)
