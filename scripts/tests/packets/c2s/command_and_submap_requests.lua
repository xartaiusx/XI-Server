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
        player.packets:send(0x01C, packet, assert(ffi.sizeof(packet)))
    end

    local function setBoundary(value)
        local packet = ffi.new('uint8_t[8]')
        packet[4] = 1 -- SUBMAPCHANGE_STATE::General
        packet[6] = value % 256
        packet[7] = math.floor(value / 256)
        player.packets:send(0x0F2, packet, assert(ffi.sizeof(packet)))
        player.packets:clear()
    end

    local function expectBoundary(expected)
        local request = ffi.new('uint8_t[4]')
        player.packets:send(0x0EB, request, assert(ffi.sizeof(request)))
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

    it('grants Savage Blade only from an eligible main-hand sword until permanently unlocked', function()
        player:changeJob(xi.job.RDM)
        player:setLevel(99)
        player:setSkillLevel(xi.skill.SWORD, 2400)
        assert(not player:hasLearnedWeaponskill(xi.wsUnlock.SAVAGE_BLADE), 'fixture already learned Savage Blade')

        for _, item in ipairs({ xi.item.ELETTA_SWORD, xi.item.KAJA_SWORD, xi.item.NAEGLING }) do
            player:addItem(item)
        end

        local function expectSavageBlade(item, expected)
            player:equipItem(item, nil, xi.slot.MAIN)
            assert(player:getEquipID(xi.slot.MAIN) == item, 'wrong sword equipped')
            player.packets:clear()
            requestCommands()

            local matching = responses(0x0AC)
            assert(#matching == 1, 'Expected exactly one command-data response')
            local id = xi.weaponskill.SAVAGE_BLADE
            local byte = matching[1].data[0x04 + math.floor(id / 8)]
            local available = bit.band(byte, bit.lshift(1, id % 8)) ~= 0
            assert(available == expected, string.format('unexpected Savage Blade availability with item %d', item))
        end

        expectSavageBlade(xi.item.ELETTA_SWORD, false)
        expectSavageBlade(xi.item.KAJA_SWORD, true)
        expectSavageBlade(xi.item.NAEGLING, true)
        expectSavageBlade(xi.item.ELETTA_SWORD, false)
        assert(not player:hasLearnedWeaponskill(xi.wsUnlock.SAVAGE_BLADE), 'equipment permanently learned Savage Blade')

        player:addLearnedWeaponskill(xi.wsUnlock.SAVAGE_BLADE)
        expectSavageBlade(xi.item.ELETTA_SWORD, true)
    end)

    local function expectWeaponSkill(weaponSkill, expected)
        player.packets:clear()
        requestCommands()

        local matching = responses(0x0AC)
        assert(#matching == 1, 'Expected exactly one command-data response')
        local byte = matching[1].data[0x04 + math.floor(weaponSkill / 8)]
        local available = bit.band(byte, bit.lshift(1, weaponSkill % 8)) ~= 0
        assert(available == expected, string.format('unexpected availability for weapon skill %d', weaponSkill))
    end

    local function equipWeapon(item, slot)
        player:equipItem(item, nil, slot)
        assert(player:getEquipID(slot) == item, 'wrong weapon equipped')
    end

    it('grants Evisceration from Kaja Knife and Tauret only in the main hand', function()
        player:changeJob(xi.job.NIN)
        player:setLevel(99)
        player:setSkillLevel(xi.skill.DAGGER, 2300)
        local skill = xi.weaponskill.EVISCERATION
        local unlock = xi.wsUnlock.EVISCERATION
        assert(not player:hasLearnedWeaponskill(unlock), 'fixture already learned Evisceration')

        player:addItem(xi.item.ELETTA_KNIFE)
        equipWeapon(xi.item.ELETTA_KNIFE, xi.slot.MAIN)
        expectWeaponSkill(skill, false)

        for _, weapon in ipairs({ xi.item.KAJA_KNIFE, xi.item.TAURET }) do
            player:addItem(weapon)
            equipWeapon(weapon, xi.slot.SUB)
            expectWeaponSkill(skill, false)

            player:unequipItem(xi.slot.SUB)
            equipWeapon(weapon, xi.slot.MAIN)
            expectWeaponSkill(skill, true)

            equipWeapon(xi.item.ELETTA_KNIFE, xi.slot.MAIN)
            expectWeaponSkill(skill, false)
        end

        assert(not player:hasLearnedWeaponskill(unlock), 'equipment permanently learned Evisceration')
        player:addLearnedWeaponskill(unlock)
        expectWeaponSkill(skill, true)
    end)

    it('offers equipment-granted Evisceration to Puppetmaster', function()
        player:changeJob(xi.job.PUP)
        player:setLevel(99)
        player:setSkillLevel(xi.skill.DAGGER, 2300)

        for _, weapon in ipairs({ xi.item.KAJA_KNIFE, xi.item.TAURET }) do
            player:addItem(weapon)
            equipWeapon(weapon, xi.slot.MAIN)
            expectWeaponSkill(xi.weaponskill.EVISCERATION, true)
        end

        assert(not player:hasLearnedWeaponskill(xi.wsUnlock.EVISCERATION), 'equipment permanently learned Evisceration')
    end)

    it('grants Decimation from Kaja Axe and Dolichenus until unequipped', function()
        player:setSkillLevel(xi.skill.AXE, 2400)
        local skill = xi.weaponskill.DECIMATION
        local unlock = xi.wsUnlock.DECIMATION
        assert(not player:hasLearnedWeaponskill(unlock), 'fixture already learned Decimation')

        for _, weapon in ipairs({ xi.item.ELETTA_AXE, xi.item.KAJA_AXE, xi.item.DOLICHENUS }) do
            player:addItem(weapon)
        end

        equipWeapon(xi.item.ELETTA_AXE, xi.slot.MAIN)
        expectWeaponSkill(skill, false)
        equipWeapon(xi.item.KAJA_AXE, xi.slot.MAIN)
        expectWeaponSkill(skill, true)
        equipWeapon(xi.item.DOLICHENUS, xi.slot.MAIN)
        expectWeaponSkill(skill, true)
        equipWeapon(xi.item.ELETTA_AXE, xi.slot.MAIN)
        expectWeaponSkill(skill, false)

        assert(not player:hasLearnedWeaponskill(unlock), 'equipment permanently learned Decimation')
        player:addLearnedWeaponskill(unlock)
        expectWeaponSkill(skill, true)
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
