describe('Player ability learning', function()
    it('allows an eligible Corsair to learn and use a roll', function()
        local player = xi.test.world:spawnPlayer({ job = xi.job.COR, level = 49, zone = xi.zone.WEST_RONFAURE })
        local ability = xi.jobAbility.FIGHTERS_ROLL

        assert(player:canLearnAbility(ability) == 0)
        player:addLearnedAbility(ability)
        assert(player:hasLearnedAbility(ability))

        player.actions:useAbility(player, ability)
        xi.test.world:tickEntity(player)
        assert(player:hasStatusEffect(xi.effect.FIGHTERS_ROLL))
    end)

    it('allows an eligible Corsair support job to learn and use a roll', function()
        xi.test.world:setSetting('map.SUBJOB_RATIO', 1)
        local player = xi.test.world:spawnPlayer({ job = xi.job.RDM, level = 99, zone = xi.zone.WEST_RONFAURE })
        player:changesJob(xi.job.COR)
        player:setsLevel(49)
        assert(player:getMainJob() == xi.job.RDM and player:getMainLvl() == 99)
        assert(player:getSubJob() == xi.job.COR and player:getSubLvl() == 49)

        local ability = xi.jobAbility.FIGHTERS_ROLL
        assert(not player:hasLearnedAbility(ability))
        assert(player:canLearnAbility(ability) == 0)
        player:addLearnedAbility(ability)
        assert(player:hasLearnedAbility(ability))

        player.actions:useAbility(player, ability)
        xi.test.world:tickEntity(player)
        assert(player:hasStatusEffect(xi.effect.FIGHTERS_ROLL))
    end)

    it('rejects a roll above the current job level', function()
        local player = xi.test.world:spawnPlayer({ job = xi.job.COR, level = 48, zone = xi.zone.WEST_RONFAURE })
        local ability = xi.jobAbility.FIGHTERS_ROLL

        assert(player:canLearnAbility(ability) == 443)
        player:addLearnedAbility(ability)
        assert(not player:hasLearnedAbility(ability))
    end)

    it('rejects off-job and monster-form grants in an ordinary player form', function()
        local player = xi.test.world:spawnPlayer({ job = xi.job.COR, level = 99, zone = xi.zone.WEST_RONFAURE })
        for _, ability in ipairs({ xi.jobAbility.CHAINSPELL, xi.jobAbility.RELINQUISH }) do
            assert(player:canLearnAbility(ability) == 443)
            player:addLearnedAbility(ability)
            assert(not player:hasLearnedAbility(ability))
        end

        player.actions:useAbility(player, xi.jobAbility.CHAINSPELL)
        xi.test.world:tickEntity(player)
        assert(not player:hasStatusEffect(xi.effect.CHAINSPELL))
    end)

    it('keeps a level-granted ability usable without learning it', function()
        local player = xi.test.world:spawnPlayer({ job = xi.job.RDM, level = 99, zone = xi.zone.WEST_RONFAURE })
        local ability = xi.jobAbility.CHAINSPELL

        assert(player:canLearnAbility(ability) == 443)
        player:addLearnedAbility(ability)
        assert(not player:hasLearnedAbility(ability))

        player.actions:useAbility(player, ability)
        xi.test.world:tickEntity(player)
        assert(player:hasStatusEffect(xi.effect.CHAINSPELL))
    end)
end)
