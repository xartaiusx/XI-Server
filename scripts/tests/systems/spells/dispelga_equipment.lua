describe('Dispelga equipment requirement', function()
    local spellId = xi.magic.spell.DISPELGA
    local hareId = 17186876 -- West Ronfaure Forest Hare.
    ---@type CTestEntity?
    local resetTarget

    after_each(function()
        if resetTarget then
            resetTarget:respawn()
            resetTarget = nil
        end
    end)

    local function prepareCaster(job)
        local player = xi.test.world:spawnPlayer({ job = job, level = 99, zone = xi.zone.WEST_RONFAURE })
        local rabbit = assert(player.entities:get(hareId))
        resetTarget = rabbit
        rabbit:respawn()
        assert(player.entities:moveTo(hareId), 'could not place the caster at the fresh target')
        assert(rabbit:isAlive(), 'expected a living Dispelga target')
        assert(player:getMainJob() == job and player:getMainLvl() == 99, 'unexpected caster job or level')

        local trace = { started = 0, finished = 0 }
        player:addListener('MAGIC_START', 'DISPELGA_EQUIPMENT_START', function(_, _, spell)
            if spell:getID() == spellId then
                trace.started = trace.started + 1
            end
        end)

        player:addListener('MAGIC_USE', 'DISPELGA_EQUIPMENT_USE', function(_, _, spell)
            if spell:getID() == spellId then
                trace.finished = trace.finished + 1
            end
        end)

        return player, rabbit, trace
    end

    local function describeCast(player, rabbit, trace, mp)
        local messages = {}
        for _, packet in ipairs(player.packets:getIncoming()) do
            if packet.type == 0x029 and packet.size >= 0x1C then
                -- GP_SERV_COMMAND_BATTLE_MESSAGE stores the message ID at offset 0x18.
                messages[#messages + 1] = tostring(packet.data[0x18] + 256 * packet.data[0x19])
            end
        end

        return string.format('job=%d target=%d starts=%d finishes=%d MP=%d->%d battle messages=%s',
            player:getMainJob(), rabbit:getID(), trace.started, trace.finished, mp, player:getMP(),
            table.concat(messages, ','))
    end

    it('rejects an old learned bit without Daybreak in the main hand', function()
        local player, rabbit, trace = prepareCaster(xi.job.RDM)
        player:addSpell(spellId, { saveToDB = false })
        assert(player:hasSpell(spellId))
        assert(player:getEquipID(xi.slot.MAIN) ~= xi.item.DAYBREAK)
        local mp = player:getMP()

        player.packets:clear()
        player.actions:useSpell(rabbit, spellId)
        xi.test.world:skipTime(5)
        assert(trace.started == 0 and trace.finished == 0 and player:getMP() == mp,
            describeCast(player, rabbit, trace, mp))
        assert(not player:hasRecast(xi.recast.MAGIC, spellId))
    end)

    local function checkMainHandGrant(job, replacement)
        local player, rabbit, trace = prepareCaster(job)
        assert(not player:hasSpell(spellId))
        assert(player:canLearnSpell(spellId) == 0, 'native job eligibility rejected Dispelga before equip')
        player:addItem(xi.item.DAYBREAK)
        player:equipItem(xi.item.DAYBREAK, nil, xi.slot.MAIN)
        assert(player:getEquipID(xi.slot.MAIN) == xi.item.DAYBREAK)
        assert(player:hasSpell(spellId))
        player:setMP(player:getMaxMP())
        local mp = player:getMP()
        assert(mp >= 200, 'Dispelga fixture has less than the base spell cost')

        player.packets:clear()
        player.actions:useSpell(rabbit, spellId)
        xi.test.world:skipTime(5)
        local details = describeCast(player, rabbit, trace, mp)
        assert(trace.started == 1, 'Dispelga start: ' .. details)
        assert(trace.finished == 1, 'Dispelga completion: ' .. details)
        assert(player:getMP() < mp, 'Dispelga MP charge: ' .. details)
        assert(player:hasRecast(xi.recast.MAGIC, spellId), 'Dispelga recast: ' .. details)

        player:addItem(replacement)
        player:equipItem(replacement, nil, xi.slot.MAIN)
        assert(player:getEquipID(xi.slot.MAIN) == replacement)
        assert(not player:hasSpell(spellId))
    end

    it('grants, admits and revokes the temporary spell for RDM', function()
        checkMainHandGrant(xi.job.RDM, xi.item.BRONZE_SWORD)
    end)

    it('grants, admits and revokes the temporary spell for GEO', function()
        checkMainHandGrant(xi.job.GEO, xi.item.ASH_CLUB)
    end)
end)
