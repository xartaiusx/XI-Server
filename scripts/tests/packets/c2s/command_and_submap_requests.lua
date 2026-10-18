local bit = require('bit')
local ffi = require('ffi')

describe('Command and submap requests', function()
    ---@type CClientEntityPair
    local player

    before_each(function()
        player = xi.test.world:spawnPlayer({ job = xi.job.WAR, level = 99 })
        player.packets:clear()
    end)

    after_each(function()
        if player and player:isInEvent() then
            player:release()
        end
    end)

    local function responses(packetType)
        local matching = {}
        for _, packet in ipairs(player.packets:getIncoming()) do
            if packet.type == packetType then
                matching[#matching + 1] = packet
            end
        end

        return matching
    end

    local function requestCommands()
        local packet = ffi.new('uint8_t[12]')
        packet[8] = 1
        player.packets:send(0x01C, packet, ffi.sizeof(packet))
    end

    local function setBoundary(value)
        local packet = ffi.new('uint8_t[8]')
        packet[4] = 1 -- SUBMAPCHANGE_STATE::General
        packet[6] = value % 256
        packet[7] = math.floor(value / 256)
        player.packets:send(0x0F2, packet, ffi.sizeof(packet))
        player.packets:clear()
    end

    local function expectBoundary(expected)
        local request = ffi.new('uint8_t[4]')
        player.packets:send(0x0EB, request, ffi.sizeof(request))
        local matching = responses(0x10E)
        assert(#matching == 1, 'Expected exactly one submap response')
        local packet = matching[1]
        assert(packet.size == 8, 'Unexpected submap packet size')
        local boundary = packet.data[4] + packet.data[5] * 256 + packet.data[6] * 65536 + packet.data[7] * 16777216
        assert(boundary == expected, string.format('Expected submap %d, got %d', expected, boundary))
    end

    it('answers an ability-list request with the current player commands', function()
        requestCommands()
        local matching = responses(0x0AC)
        assert(#matching == 1, 'Expected exactly one command-data response')
        local packet = matching[1]
        assert(packet.size == 0xE4, 'Unexpected command-data packet size')
        for _, ability in ipairs({ xi.jobAbility.BERSERK, xi.jobAbility.PROVOKE }) do
            local byte = packet.data[0x44 + math.floor(ability / 8)]
            assert(bit.band(byte, bit.lshift(1, ability % 8)) ~= 0, 'WAR ability missing from command list')
        end
    end)

    it('does not answer an ability-list request during an event', function()
        player:startEvent(1)
        assert(player:isInEvent(), 'Event did not start')
        player.packets:clear()
        requestCommands()
        assert(#responses(0x0AC) == 0, 'Command-data request bypassed the event lock')
    end)

    for _, boundary in ipairs({ 0, 1, 255, 256, 65535 }) do
        local expected = boundary
        it(string.format('returns tracked submap %d without an event lock', expected), function()
            setBoundary(expected)
            expectBoundary(expected)
        end)
    end

    it('returns the tracked submap during an event', function()
        setBoundary(256)
        player:startEvent(1)
        assert(player:isInEvent(), 'Event did not start')
        player.packets:clear()
        expectBoundary(256)
    end)
end)
