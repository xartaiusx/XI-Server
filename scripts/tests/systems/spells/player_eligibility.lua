describe('Player spell eligibility', function()
    ---@type CClientEntityPair
    local player
    ---@type CTestEntity|nil
    local rabbit
    local starts

    before_each(function()
        -- The test framework restores the ratio after exercising synthetic SCH59 and SCH70.
        xi.test.world:setSetting('map.SUBJOB_RATIO', 3)
        player = xi.test.world:spawnPlayer({ job = xi.job.RDM, level = 99, zone = xi.zone.WEST_RONFAURE })
        player:changesJob(xi.job.SCH)
        player:setsLevel(59)
        player:setMP(player:getMaxMP())
        assert(player:getMainLvl() == 99 and player:getSubLvl() == 59)

        starts = {}
        player:addListener('MAGIC_START', 'PLAYER_SPELL_ELIGIBILITY_START', function(_, _, spell)
            starts[#starts + 1] = spell:getID()
        end)
    end)

    after_each(function()
        if rabbit then
            rabbit:respawn()
            rabbit = nil
        end
    end)

    it('rejects a learned Diaga III while allowing Dia III on the same target', function()
        rabbit = player.entities:get('Forest_Hare')
        rabbit:respawn()
        player.entities:moveTo(rabbit)
        player:addSpell(xi.magic.spell.DIAGA_III, { saveToDB = false })
        player:addSpell(xi.magic.spell.DIA_III, { saveToDB = false })
        assert(player:hasSpell(xi.magic.spell.DIAGA_III))
        local mp = player:getMP()

        player.actions:useSpell(rabbit, xi.magic.spell.DIAGA_III)
        xi.test.world:skipTime(3)
        assert(#starts == 0 and player:getMP() == mp)
        assert(not player:hasRecast(xi.recast.MAGIC, xi.magic.spell.DIAGA_III))

        -- The regional target can roam during the rejected cast's wait.
        player.entities:moveTo(rabbit)
        player.actions:useSpell(rabbit, xi.magic.spell.DIA_III)
        xi.test.world:skipTime(3)
        assert(#starts == 1 and starts[1] == xi.magic.spell.DIA_III)
        assert(player:hasRecast(xi.recast.MAGIC, xi.magic.spell.DIA_III))
    end)

    it('rejects learned Reraise II at SCH59 even with Addendum White and allows Aurorastorm without it', function()
        player:addSpell(xi.magic.spell.AURORASTORM, { saveToDB = false })
        player:addSpell(xi.magic.spell.RERAISE_II, { saveToDB = false })
        assert(player:hasSpell(xi.magic.spell.RERAISE_II))
        player:addStatusEffect(xi.effect.ADDENDUM_WHITE, { power = 0, duration = 180, origin = player })
        player.assert:hasEffect(xi.effect.ADDENDUM_WHITE)
        local mp = player:getMP()

        player.actions:useSpell(player, xi.magic.spell.RERAISE_II)
        xi.test.world:skipTime(3)
        assert(#starts == 0 and player:getMP() == mp)
        assert(not player:hasRecast(xi.recast.MAGIC, xi.magic.spell.RERAISE_II))
        assert(not player:hasStatusEffect(xi.effect.RERAISE))

        player:delStatusEffect(xi.effect.ADDENDUM_WHITE)
        assert(not player:hasStatusEffect(xi.effect.ADDENDUM_WHITE))
        player.actions:useSpell(player, xi.magic.spell.AURORASTORM)
        xi.test.world:skipTime(3)
        assert(#starts == 1 and starts[1] == xi.magic.spell.AURORASTORM)
        player.assert:hasEffect(xi.effect.AURORASTORM)
        assert(player:hasRecast(xi.recast.MAGIC, xi.magic.spell.AURORASTORM))
    end)

    it('requires Addendum White for Reraise II at SCH70 and applies tier II after completion', function()
        player:setsLevel(70)
        assert(player:getMainLvl() == 99 and player:getSubLvl() == 70)
        player:addSpell(xi.magic.spell.RERAISE_II, { saveToDB = false })
        assert(player:hasSpell(xi.magic.spell.RERAISE_II))
        assert(not player:hasStatusEffect(xi.effect.ADDENDUM_WHITE))

        player.actions:useSpell(player, xi.magic.spell.RERAISE_II)
        xi.test.world:skipTime(3)
        assert(#starts == 0)
        assert(not player:hasRecast(xi.recast.MAGIC, xi.magic.spell.RERAISE_II))
        assert(not player:hasStatusEffect(xi.effect.RERAISE))

        player:addStatusEffect(xi.effect.ADDENDUM_WHITE, { power = 0, duration = 180, origin = player })
        player.assert:hasEffect(xi.effect.ADDENDUM_WHITE)
        local mp = player:getMP()

        player.actions:useSpell(player, xi.magic.spell.RERAISE_II)
        xi.test.world:skipTime(10)
        assert(#starts == 1 and starts[1] == xi.magic.spell.RERAISE_II)
        player.assert:hasEffect(xi.effect.RERAISE)
        assert(player:getStatusEffect(xi.effect.RERAISE):getPower() == 2)
        assert(player:getMP() < mp)
        assert(player:hasRecast(xi.recast.MAGIC, xi.magic.spell.RERAISE_II))
    end)
end)
