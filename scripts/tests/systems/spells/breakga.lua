describe('Player Breakga', function()
    local scroll = 4889
    local spellId = xi.magic.spell.BREAKGA
    ---@type CTestEntity
    local rabbit

    after_each(function()
        if rabbit then
            rabbit:respawn()
            rabbit = nil
        end
    end)

    local function useScroll(player)
        player:addItem(scroll)
        local item = assert(player:findItem(scroll))
        player.actions:useItem(player, item:getSlotID())
        xi.test.world:tickEntity(player)
        xi.test.world:skipTime(10)
    end

    it('rejects the scroll below BLM95 without consuming it', function()
        local player = xi.test.world:spawnPlayer({ job = xi.job.BLM, level = 94, zone = xi.zone.WEST_RONFAURE })
        assert(player:canLearnSpell(spellId) == 95)
        useScroll(player)
        assert(not player:hasSpell(spellId) and player:hasItem(scroll))
    end)

    it('teaches BLM95 and casts Breakga with the player MP, timing and effect', function()
        local player = xi.test.world:spawnPlayer({ job = xi.job.BLM, level = 95, zone = xi.zone.WEST_RONFAURE })
        assert(not player:hasSpell(spellId) and player:canLearnSpell(spellId) == 0)
        useScroll(player)
        assert(player:hasSpell(spellId) and not player:hasItem(scroll))

        rabbit = player.entities:moveTo('Forest_Hare')
        rabbit:spawn()
        stub('xi.combat.magicHitRate.calculateResistRate', 1)
        local starts = 0
        player:addListener('MAGIC_START', 'PLAYER_BREAKGA_START', function(_, _, spell)
            if spell:getID() == spellId then
                starts = starts + 1
                assert(spell:getMPCost() == 78 and spell:getCastTime() == 3500)
                assert(spell:isAoE() and spell:getRadius() == 10)
            end
        end)

        -- Measure the base MP charge without the Black Mage Conserve MP roll.
        player:setMod(xi.mod.CONSERVE_MP, 0)
        player:setMP(77)
        player.actions:useSpell(rabbit, spellId)
        xi.test.world:skipTime(5)
        assert(starts == 0 and player:getMP() == 77)
        assert(not player:hasRecast(xi.recast.MAGIC, spellId))

        player:setMP(78)
        player.actions:useSpell(rabbit, spellId)
        xi.test.world:skipTime(3)
        assert(starts == 1 and not rabbit:hasStatusEffect(xi.effect.PETRIFICATION))
        xi.test.world:skipTime(1)
        local petrification = assert(rabbit:getStatusEffect(xi.effect.PETRIFICATION))
        assert(petrification:getTier() == 2 and petrification:getSubPower() == 1)
        assert(player:getMP() == 0 and player:hasRecast(xi.recast.MAGIC, spellId))
        xi.test.world:skipTime(42)
        assert(player:hasRecast(xi.recast.MAGIC, spellId))
        xi.test.world:skipTime(5)
        assert(not player:hasRecast(xi.recast.MAGIC, spellId))
    end)

    it('rejects a previously learned Breakga for RDM99/SCH59', function()
        xi.test.world:setSetting('map.SUBJOB_RATIO', 3)
        local player = xi.test.world:spawnPlayer({ job = xi.job.RDM, level = 99, zone = xi.zone.WEST_RONFAURE })
        player:changesJob(xi.job.SCH)
        player:setsLevel(59)
        assert(player:getSubLvl() == 59 and player:canLearnSpell(spellId) == 95)
        player:addSpell(spellId, { saveToDB = false })
        assert(player:hasSpell(spellId))

        rabbit = player.entities:moveTo('Forest_Hare')
        rabbit:spawn()
        local starts = 0
        player:addListener('MAGIC_START', 'PLAYER_BREAKGA_OFF_JOB_START', function()
            starts = starts + 1
        end)
        local mp = player:getMP()
        player.actions:useSpell(rabbit, spellId)
        xi.test.world:skipTime(5)
        assert(starts == 0 and player:getMP() == mp)
        assert(not player:hasRecast(xi.recast.MAGIC, spellId))
    end)
end)
