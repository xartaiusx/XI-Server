describe('RDM gift spell admission', function()
    ---@type CClientEntityPair
    local player
    local starts

    before_each(function()
        player = xi.test.world:spawnPlayer({ job = xi.job.RDM, level = 99, zone = xi.zone.WEST_RONFAURE })
        player:addSpell(xi.magic.spell.TEMPER_II, { saveToDB = false })
        assert(player:hasSpell(xi.magic.spell.TEMPER_II))
        starts = 0
        player:addListener('MAGIC_START', 'RDM_GIFT_START', function(_, _, spell)
            if spell:getID() == xi.magic.spell.TEMPER_II then
                starts = starts + 1
            end
        end)
    end)

    it('rejects a known gift when main-job spent points are below the threshold', function()
        assert(player:getSpentJobPoints() < 1200)
        local mp = player:getMP()

        player.actions:useSpell(player, xi.magic.spell.TEMPER_II)
        xi.test.world:skipTime(10)
        assert(starts == 0 and player:getMP() == mp)
        assert(not player:hasRecast(xi.recast.MAGIC, xi.magic.spell.TEMPER_II))
    end)

    it('admits and applies the same gift after its main-job requirement is met', function()
        player:masterJob()
        assert(player:getSpentJobPoints() >= 1200)
        local mp = player:getMP()

        player.actions:useSpell(player, xi.magic.spell.TEMPER_II)
        xi.test.world:skipTime(10)
        assert(starts == 1 and player:getMP() < mp)
        player.assert:hasEffect(xi.effect.MULTI_STRIKES)
        assert(player:hasRecast(xi.recast.MAGIC, xi.magic.spell.TEMPER_II))
    end)

    it('does not admit the gift through an effective level-99 RDM support job', function()
        -- The test framework restores the ratio after this synthetic support-job case.
        xi.test.world:setSetting('map.SUBJOB_RATIO', 3)
        local blm = xi.test.world:spawnPlayer({ job = xi.job.BLM, level = 99, zone = xi.zone.WEST_RONFAURE })
        blm:changesJob(xi.job.RDM)
        blm:setsLevel(99)
        assert(blm:getSubLvl() == 99)
        blm:addSpell(xi.magic.spell.TEMPER_II, { saveToDB = false })
        assert(blm:hasSpell(xi.magic.spell.TEMPER_II))
        local mp = blm:getMP()

        blm.actions:useSpell(blm, xi.magic.spell.TEMPER_II)
        xi.test.world:skipTime(10)
        assert(blm:getMP() == mp and not blm:hasStatusEffect(xi.effect.MULTI_STRIKES))
        assert(not blm:hasRecast(xi.recast.MAGIC, xi.magic.spell.TEMPER_II))
    end)
end)
