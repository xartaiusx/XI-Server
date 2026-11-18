-----------------------------------
-- The Enemybar display receives a private snapshot of the authenticated player's visible target.
-----------------------------------
local ffi = require('ffi')

describe('Mochirii Enemybar target data', function()
    local owner
    local outsider
    local mob
    local nonce = '0000000000000001'

    local function selectTarget(player, targetIndex)
        local packet = ffi.new('uint8_t[32]')
        local position = ffi.cast('float*', packet)
        position[1], position[2], position[3] = player:getXPos(), player:getYPos(), player:getZPos()
        packet[22] = targetIndex % 256
        packet[23] = math.floor(targetIndex / 256)
        player.packets:send(0x015, packet, assert(ffi.sizeof(packet)))
    end

    local function request(player, token, index)
        local message = string.format('!mochienemybar %s %u %u %u', token, player:getZoneID(), mob:getID(), index)
        local packet = ffi.new('uint8_t[128]')
        ffi.copy(ffi.cast('uint8_t*', packet) + 6, message, #message)
        player.packets:send(0x0B5, packet, 4 * math.ceil((#message + 7) / 4))
    end

    local function packetString(packet, first, last)
        local bytes = {}
        for i = first, last do
            local char = packet.data[i]
            if char == 0 then
                break
            end

            bytes[#bytes + 1] = string.char(char)
        end

        return table.concat(bytes)
    end

    local function responses(player)
        local messages = {}
        for _, packet in ipairs(player.packets:getIncoming()) do
            if
                packet.type == 0x017 and
                packet.data[4] == 6 and
                packet.data[5] == 0 and
                packetString(packet, 8, 22) == 'MochiEnemybar'
            then
                messages[#messages + 1] = packetString(packet, 23, packet.size - 1)
            end
        end

        return messages
    end

    before_each(function()
        xi.test.world:setSetting('main.ENABLE_MOCHIRII_TWILLS_TRUST_GAMEPLAY', true)
        xi.test.world:setSetting('main.ENABLE_MOCHIRII_TWILLS_FULL_ALLIANCE', true)
        xi.test.world:setSetting('main.MOCHIRII_TWILLS_FULL_ALLIANCE_MAX_PARTIES', 3)
        owner = xi.test.world:spawnPlayer({ name = 'Twills', zone = xi.zone.WEST_RONFAURE, job = xi.job.RDM, level = 99 })
        outsider = xi.test.world:spawnPlayer({ name = 'EnemybarGuest', zone = xi.zone.WEST_RONFAURE, job = xi.job.RDM, level = 99 })
        owner:setGMLevel(5)
        owner:setVisibleGMLevel(0)
        owner:setCharVar('MochiriiTrustAllianceAccess', 1)
        assert(owner.actions:prepareSoloTrustParty())
        assert(owner:canUseTwillsTrustGameplay())
        assert(not outsider:canUseTwillsTrustGameplay())

        mob = owner:getZone():insertDynamicEntity({
            objtype              = xi.objType.MOB,
            name                 = 'EnemybarFixture',
            groupId              = 5,
            groupZoneId          = 154,
            minLevel             = 99,
            maxLevel             = 99,
            respawn              = 0,
            releaseIdOnDisappear = true,
        })
        assert(mob)
        SpawnMob(mob:getID())
        assert(owner.entities:moveTo(mob))
        assert(outsider.entities:moveTo(mob))
        mob:setAggressive(false)
        mob:setMobMod(xi.mobMod.NO_MOVE, 1)
        xi.test.world:skipTime(1)
        owner.packets:clear()
        outsider.packets:clear()
    end)

    after_each(function()
        if mob and mob:isSpawned() then
            DespawnMob(mob:getID())
        end
    end)

    it('sends actual target resources only to the entitled viewer and rate-limits repeats', function()
        selectTarget(owner, mob:getTargID())
        selectTarget(outsider, mob:getTargID())
        mob:setMod(xi.mod.HPP, 25)
        mob:setMod(xi.mod.MPP, 25)
        mob:setMaxHP(4321)
        mob:setHP(3456)
        mob:setMaxMP(700)
        mob:setMP(123)
        mob:setTP(777)
        assert(mob:addStatusEffect(xi.effect.SLEEP_I, { power = 1, duration = 30, origin = owner, icon = xi.effect.SLEEP_I }))

        -- The health setters assign base maxima. Read the effective values after modifiers.
        local hp, maxHP = mob:getHP(), mob:getMaxHP()
        local mp, maxMP = mob:getMP(), mob:getMaxMP()
        local tp = mob:getTP()
        assert(hp == 3456 and maxHP > hp and mp == 123 and maxMP > mp and tp == 777,
            string.format('unexpected fixture resources: HP %d/%d, MP %d/%d, TP %d', hp, maxHP, mp, maxMP, tp))

        local expected = string.format(
            'MEB1 %s %u %u %u %d %d %d %d %d 1 1 %u',
            nonce, owner:getZoneID(), mob:getID(), mob:getTargID(), hp, maxHP, mp, maxMP, tp, xi.effect.SLEEP_I)
        request(owner, nonce, mob:getTargID())
        request(outsider, nonce, mob:getTargID())
        local messages = responses(owner)
        assert(#messages == 1 and #responses(outsider) == 0)
        assert(messages[1] == expected, string.format('expected %q, got %q', expected, messages[1]))

        owner.packets:clear()
        request(owner, '0000000000000002', mob:getTargID())
        assert(#responses(owner) == 0)
    end)

    it('sends a complete numbered snapshot when the target has more than eight icons', function()
        selectTarget(owner, mob:getTargID())
        local icons = {
            xi.effect.PROTECT, xi.effect.SHELL, xi.effect.REGEN, xi.effect.REFRESH, xi.effect.AQUAVEIL,
            xi.effect.STONESKIN, xi.effect.BLINK, xi.effect.PHALANX, xi.effect.ENMITY_BOOST,
        }
        for _, icon in ipairs(icons) do
            assert(mob:addStatusEffect(icon, { power = 1, duration = 30, origin = owner, icon = icon }))
        end

        table.sort(icons)
        request(owner, nonce, mob:getTargID())
        local messages = responses(owner)
        local header = string.format('MEB1 %s %u %u %u %d %d %d %d %d', nonce, owner:getZoneID(), mob:getID(),
            mob:getTargID(), mob:getHP(), mob:getMaxHP(), mob:getMP(), mob:getMaxMP(), mob:getTP())
        assert(#messages == 2)
        assert(messages[1] == header .. ' 1 2 ' .. table.concat(icons, ',', 1, 8))
        assert(messages[2] == header .. ' 2 2 ' .. tostring(icons[9]))
    end)

    it('ignores malformed requests and withholds data when the native cursor does not match', function()
        selectTarget(owner, 0)
        request(owner, 'NOT_A_NONCE', mob:getTargID())
        assert(#responses(owner) == 0)

        request(owner, nonce, mob:getTargID())
        local messages = responses(owner)
        assert(#messages == 1 and messages[1] == string.format(
            'MEB1 %s %u %u %u unavailable', nonce, owner:getZoneID(), mob:getID(), mob:getTargID()))
    end)
end)
