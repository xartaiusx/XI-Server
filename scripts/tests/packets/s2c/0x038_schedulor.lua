describe('Scheduler FOURCC packets', function()
    ---@type CClientEntityPair
    local player
    ---@type CTestEntity
    local npc

    before_each(function()
        player = xi.test.world:spawnPlayer({ zone = xi.zone.PORT_SAN_DORIA })
        npc = assert(player.entities:moveTo('Regine'), 'Regine was not found')
        player.packets:clear()
    end)

    local emitters =
    {
        {
            packetType = 0x038,
            send = function(command)
                player:entityAnimationPacket(command, npc)
            end,
        },
        {
            packetType = 0x039,
            send = function(command)
                player:entityVisualPacket(command, npc)
            end,
        },
        {
            packetType = 0x039,
            send = function(command)
                SendEntityVisualPacket(npc:getID(), command)
            end,
        },
    }

    it('preserves four ASCII and binary bytes through every Lua entrypoint', function()
        for _, command in ipairs({ 'sp00', string.char(0, 128, 255, 1), 'a\0bc' }) do
            for _, emitter in ipairs(emitters) do
                player.packets:clear()
                emitter.send(command)

                local matching = {}
                for _, packet in ipairs(player.packets:getIncoming()) do
                    if packet.type == emitter.packetType then
                        matching[#matching + 1] = packet
                    end
                end

                assert(#matching == 1, 'Expected exactly one scheduler packet')
                local packet = matching[1]
                assert(packet.size == 0x14, 'Unexpected scheduler packet size')
                for i = 1, 4 do
                    assert(packet.data[0x0C + i - 1] == string.byte(command, i), 'FOURCC byte was changed or truncated')
                end
            end
        end
    end)

    it('rejects lengths zero through three and five without emitting packets', function()
        for _, command in ipairs({ '', 'a', 'ab', 'abc', 'abcde', 'abcd\0' }) do
            for _, emitter in ipairs(emitters) do
                player.packets:clear()
                local ok, err = pcall(emitter.send, command)
                assert(not ok, 'Invalid FOURCC length was accepted')
                assert(tostring(err):find('FOURCC must contain exactly four bytes.', 1, true), 'Unexpected FOURCC rejection')
                assert(#player.packets:getIncoming() == 0, 'Rejected FOURCC emitted a packet')
            end
        end
    end)
end)
