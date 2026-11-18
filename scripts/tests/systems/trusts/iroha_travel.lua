-----------------------------------
-- Travel proof runs with synthetic characters in the isolated native fixture.
-----------------------------------
local ffi = require('ffi')

describe('Ordinary Iroha II travel', function()
    local routes =
    {
        { name = 'holla', spellId = xi.magic.spell.TELEPORT_HOLLA, zone = xi.zone.LA_THEINE_PLATEAU, crystal = xi.keyItem.HOLLA_GATE_CRYSTAL, eventId = 116, cost = 75, destination = xi.teleport.id.HOLLA,
            x = 420.000, y = 19.104, z = 20.000 },
        { name = 'dem', spellId = xi.magic.spell.TELEPORT_DEM, zone = xi.zone.KONSCHTAT_HIGHLANDS, crystal = xi.keyItem.DEM_GATE_CRYSTAL, eventId = 101, cost = 75, destination = xi.teleport.id.DEM,
            x = 220.000, y = 19.104, z = 300.000 },
        { name = 'mea', spellId = xi.magic.spell.TELEPORT_MEA, zone = xi.zone.TAHRONGI_CANYON, crystal = xi.keyItem.MEA_GATE_CRYSTAL, eventId = 32, cost = 75, destination = xi.teleport.id.MEA,
            x = 100.000, y = 35.151, z = 340.000 },
        { name = 'vahzl', spellId = xi.magic.spell.TELEPORT_VAHZL, zone = xi.zone.XARCABARD, crystal = xi.keyItem.VAHZL_GATE_CRYSTAL, eventId = 1, cost = 100, destination = xi.teleport.id.VAHZL,
            x = 150.258, y = -21.048, z = -37.256 },
        { name = 'yhoat', spellId = xi.magic.spell.TELEPORT_YHOAT, zone = xi.zone.YHOATOR_JUNGLE, crystal = xi.keyItem.YHOATOR_GATE_CRYSTAL, eventId = 1, cost = 100, destination = xi.teleport.id.YHOAT,
            x = -280.942, y = 0.596, z = -144.156 },
        { name = 'altep', spellId = xi.magic.spell.TELEPORT_ALTEP, zone = xi.zone.EASTERN_ALTEPA_DESERT, crystal = xi.keyItem.ALTEPA_GATE_CRYSTAL, eventId = 1, cost = 100, destination = xi.teleport.id.ALTEP,
            x = -61.942, y = 3.949, z = 224.900 },
        { name = 'jugner', spellId = xi.magic.spell.RECALL_JUGNER, zone = xi.zone.JUGNER_FOREST_S, crystal = xi.keyItem.JUGNER_GATE_CRYSTAL, eventId = 1, cost = 125, destination = xi.teleport.id.JUGNER,
            x = -122.862, y = 0.000, z = -163.154 },
        { name = 'pashh', spellId = xi.magic.spell.RECALL_PASHH, zone = xi.zone.PASHHOW_MARSHLANDS_S, crystal = xi.keyItem.PASHHOW_GATE_CRYSTAL, eventId = 1, cost = 125, destination = xi.teleport.id.PASHH,
            x = 345.472, y = 24.280, z = -114.731 },
        { name = 'meriph', spellId = xi.magic.spell.RECALL_MERIPH, zone = xi.zone.MERIPHATAUD_MOUNTAINS_S, crystal = xi.keyItem.MERIPHATAUD_GATE_CRYSTAL, eventId = 1, cost = 125, destination = xi.teleport.id.MERIPH,
            x = 305.989, y = -14.978, z = 18.960 },
    }

    local sourceZone = xi.zone.WEST_RONFAURE
    local started = 'Iroha II has started the requested travel spell.'
    ---@type CClientEntityPair
    local owner


    local function requestByPartyChat(player, text)
        -- 0x0B5 GP_CLI_COMMAND_CHAT_STD, including its four-byte header.
        local size = 4 * math.ceil((6 + #text + 1) / 4)
        local packet = ffi.new('uint8_t[?]', size)
        packet[4] = 0x04 -- GP_CLI_COMMAND_CHAT_STD_KIND::Party
        ffi.copy(ffi.cast('uint8_t*', packet) + 6, text, #text)
        player.packets:send(0x0B5, packet, size)
    end

    local function prepareOwner()
        owner:setGMLevel(5)
        owner:setVisibleGMLevel(0)
        owner:setCharVar('MochiriiTrustAllianceAccess', 1)
        assert(owner.actions:prepareSoloTrustParty())
        assert(owner:canUseTwillsTrustGameplay())
    end

    local function summon()
        local iroha = assert(owner:spawnTrust(xi.magic.spell.IROHA_II))
        assert(iroha:isDevelopedTrust())
        return iroha
    end

    local function settle()
        for _ = 1, 6 do
            xi.test.world:skipTime(1)
            owner:tick()
        end
    end

    before_each(function()
        xi.test.world:setSetting('main.ENABLE_MOCHIRII_TWILLS_TRUST_GAMEPLAY', true)
        xi.test.world:setSetting('main.ENABLE_MOCHIRII_TWILLS_FULL_ALLIANCE', true)
        xi.test.world:setSetting('main.MOCHIRII_TWILLS_FULL_ALLIANCE_MAX_PARTIES', 3)
        xi.test.world:setSetting('main.TRUST_JOB99_IROHA_II', true)
        owner = xi.test.world:spawnPlayer({ name = 'Twills', zone = sourceZone, job = xi.job.RDM, level = 99 })
        prepareOwner()
    end)

    for _, route in ipairs(routes) do
        local name, spellId, zone, crystal, eventId = route.name, route.spellId, route.zone, route.crystal, route.eventId
        local cost, destination = route.cost, route.destination
        it('uses the native Telepoint and transports the summoner to ' .. name, function()
            owner:gotoZone(zone)
            owner.entities:gotoAndTrigger('Telepoint', { eventId = eventId, finishOption = 0 })
            owner.assert:hasKI(crystal)
            owner:gotoZone(sourceZone)
            prepareOwner()
            xi.test.world:loadZone(zone)

            local iroha = summon()
            assert(owner.actions:hasTrustSpell(iroha, spellId))
            local mp = iroha:getMP()
            local valaineral = assert(owner:spawnTrust(xi.magic.spell.VALAINERAL))
            local outsider = xi.test.world:spawnPlayer({ zone = sourceZone, job = xi.job.WHM, level = 99 })
            outsider:addKeyItem(crystal)
            outsider:setPos(owner:getXPos(), owner:getYPos(), owner:getZPos())
            local irohaId = iroha:getID()
            local ownerId = owner:getID()

            local starts = 0
            local finishes = 0
            iroha:addListener('MAGIC_START', 'IROHA_TRAVEL_START', function(actor, target, spell)
                if spell:getID() == spellId then
                    starts = starts + 1
                    assert(actor:getID() == irohaId and target:getID() == irohaId and spell:getCastTime() == 20000)
                end
            end)

            iroha:addListener('MAGIC_USE', 'IROHA_TRAVEL_FINISH', function(actor, _, spell, action)
                if spell:getID() == spellId then
                    finishes = finishes + 1
                    assert(actor:getID() == irohaId and spell:getMPCost() == cost and actor:getMP() == mp - cost)
                    assert(action:getRecast() == 10 and action:getMsg(ownerId) == xi.msg.basic.MAGIC_TELEPORT)
                end
            end)

            if name == 'holla' then
                requestByPartyChat(outsider, '!irohatravel holla')
                assert(starts == 0)
                requestByPartyChat(owner, '!irohatravel holla')
            else
                assert(owner:requestIrohaTravel(name) == started)
            end

            assert(owner:requestIrohaTravel(name) ~= started, 'repeat cannot replace a pending cast')
            assert(starts == 1 and finishes == 0 and iroha:getMP() == mp)

            xi.test.world:skipTime(10)
            assert(finishes == 0 and not owner:hasStatusEffect(xi.effect.TELEPORT), 'the native 20-second cast must still be active')
            xi.test.world:skipTime(11)
            assert(finishes == 1 and iroha:hasRecast(xi.recast.MAGIC, spellId))
            local transit = assert(owner:getStatusEffect(xi.effect.TELEPORT))
            assert(transit:getOriginID() == irohaId and transit:getPower() == destination)
            assert(not outsider:hasStatusEffect(xi.effect.TELEPORT) and not valaineral:hasStatusEffect(xi.effect.TELEPORT))
            assert(not iroha:hasStatusEffect(xi.effect.TELEPORT) and owner:getZoneID() == sourceZone)

            settle()
            owner.assert:inZone(zone)
            assert(math.abs(owner:getXPos() - route.x) < 0.1 and math.abs(owner:getYPos() - route.y) < 0.1 and math.abs(owner:getZPos() - route.z) < 0.1)
            outsider.assert:inZone(sourceZone)
            owner.assert:hasKI(crystal)
        end)
    end

    it('rejects malformed requests, ineligible recipients, wrong crystals, distance, MP and a native recast', function()
        local iroha = summon()
        local mp = iroha:getMP()
        local spellId = xi.magic.spell.TELEPORT_HOLLA
        local starts = 0
        iroha:addListener('MAGIC_START', 'IROHA_TRAVEL_DENIAL', function()
            starts = starts + 1
        end)

        assert(owner:requestIrohaTravel('') ~= started)
        assert(owner:requestIrohaTravel('holla dem') ~= started)
        assert(owner:requestIrohaTravel('warp') ~= started)
        assert(owner:requestIrohaTravel('122') ~= started)
        assert(owner:requestIrohaTravel('holla') ~= started)
        owner:addKeyItem(xi.keyItem.DEM_GATE_CRYSTAL)
        assert(owner:requestIrohaTravel('holla') ~= started)
        owner:addKeyItem(xi.keyItem.HOLLA_GATE_CRYSTAL)

        local outsider = xi.test.world:spawnPlayer({ zone = sourceZone, job = xi.job.WHM, level = 99 })
        outsider:addKeyItem(xi.keyItem.HOLLA_GATE_CRYSTAL)
        assert(outsider:requestIrohaTravel('holla') ~= started)
        assert(not outsider:canReceiveIrohaTravel(iroha, spellId))

        iroha:setPos(owner:getXPos() + 11, owner:getYPos(), owner:getZPos())
        assert(owner:requestIrohaTravel('holla') ~= started)
        iroha:setPos(owner:getXPos() + 2, owner:getYPos(), owner:getZPos())
        iroha:setMP(74)
        assert(owner:requestIrohaTravel('holla') ~= started and iroha:getMP() == 74)
        iroha:setMP(mp)
        iroha:addRecast(xi.recast.MAGIC, spellId, 10)
        assert(owner:requestIrohaTravel('holla') ~= started and iroha:hasRecast(xi.recast.MAGIC, spellId))

        assert(starts == 0 and iroha:getMP() == mp and not owner:hasStatusEffect(xi.effect.TELEPORT))
        owner.assert:inZone(sourceZone)
        outsider.assert:inZone(sourceZone)
    end)

    it('does not move the summoner if authority or the required Gate Crystal is lost during the cast', function()
        summon()
        owner:addKeyItem(xi.keyItem.HOLLA_GATE_CRYSTAL)
        assert(owner:requestIrohaTravel('holla') == started)
        owner:delKeyItem(xi.keyItem.HOLLA_GATE_CRYSTAL)
        xi.test.world:skipTime(21)
        assert(not owner:hasStatusEffect(xi.effect.TELEPORT))
        settle()
        owner.assert:inZone(sourceZone)

        xi.test.world:skipTime(10)
        owner:addKeyItem(xi.keyItem.HOLLA_GATE_CRYSTAL)
        assert(owner:requestIrohaTravel('holla') == started)
        owner:setCharVar('MochiriiTrustAllianceAccess', 0)
        xi.test.world:skipTime(21)
        assert(not owner:hasStatusEffect(xi.effect.TELEPORT))
        settle()
        owner.assert:inZone(sourceZone)
    end)

    it('revalidates the same accepted cast instead of permitting general Trust spell execution', function()
        local iroha = summon()
        local spellId = xi.magic.spell.TELEPORT_HOLLA
        owner:addKeyItem(xi.keyItem.HOLLA_GATE_CRYSTAL)
        assert(not owner:canReceiveIrohaTravel(iroha, spellId), 'catalog access grants no consent on its own')
        assert(owner.actions:useTrustSpell(iroha, iroha, spellId))
        assert(not owner:canReceiveIrohaTravel(iroha, spellId), 'an unrelated native cast never grants consent')
        xi.test.world:skipTime(21)
        assert(not owner:hasStatusEffect(xi.effect.TELEPORT))
        settle()
        owner.assert:inZone(sourceZone)
    end)

    it('rejects a blocked or engaged summoner without starting an Iroha spell', function()
        local iroha = summon()
        owner:addKeyItem(xi.keyItem.HOLLA_GATE_CRYSTAL)
        local mp = iroha:getMP()
        local starts = 0
        iroha:addListener('MAGIC_START', 'IROHA_TRAVEL_BLOCKED', function()
            starts = starts + 1
        end)

        assert(owner:addStatusEffect(xi.effect.STUN, { power = 1, duration = 30, origin = owner }))
        assert(owner:requestIrohaTravel('holla') ~= started)
        owner:delStatusEffect(xi.effect.STUN)

        local mob = owner.entities:get('Forest_Hare')
        assert(mob and mob:isAlive())
        owner:setPos(mob:getXPos() + 1, mob:getYPos(), mob:getZPos())
        iroha:setPos(owner:getXPos(), owner:getYPos(), owner:getZPos() + 2)
        owner.actions:engage(mob)
        assert(owner:isEngaged())
        assert(owner:requestIrohaTravel('holla') ~= started)
        assert(starts == 0 and iroha:getMP() == mp and not owner:hasStatusEffect(xi.effect.TELEPORT))
    end)

    it('cancels the authorized state on native interruption and later dismissal', function()
        local iroha = summon()
        local spellId = xi.magic.spell.TELEPORT_HOLLA
        local mp = iroha:getMP()
        owner:addKeyItem(xi.keyItem.HOLLA_GATE_CRYSTAL)

        local interrupted = 0
        iroha:addListener('MAGIC_INTERRUPTED', 'IROHA_TRAVEL_INTERRUPTED', function(_, _, spell)
            if spell:getID() == spellId then
                interrupted = interrupted + 1
            end
        end)

        assert(owner:requestIrohaTravel('holla') == started)
        assert(owner:canReceiveIrohaTravel(iroha, spellId))
        assert(iroha:addStatusEffect(xi.effect.STUN, { power = 1, duration = 30, origin = owner }))
        xi.test.world:skipTime(21)
        assert(interrupted == 1 and iroha:getMP() == mp and not iroha:hasRecast(xi.recast.MAGIC, spellId))
        assert(not owner:canReceiveIrohaTravel(iroha, spellId) and not owner:hasStatusEffect(xi.effect.TELEPORT))
        iroha:delStatusEffect(xi.effect.STUN)
        xi.test.world:skipTime(3)

        assert(owner:requestIrohaTravel('holla') == started)
        local previousId = iroha:getID()
        owner.actions:trigger(iroha) -- Native Talk releases the owned Trust after its delay.
        xi.test.world:skipTime(3)
        xi.test.world:skipTime(3)
        assert(not owner.actions:hasTrustEntity(previousId))
        local replacement = summon()
        assert(not owner:canReceiveIrohaTravel(replacement, spellId))
        xi.test.world:skipTime(21)
        assert(not owner:hasStatusEffect(xi.effect.TELEPORT))
        owner.assert:inZone(sourceZone)
    end)
end)
