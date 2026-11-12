describe('Player enemy-only spell eligibility', function()
    ---@type CTestEntity|nil
    local rabbit

    after_each(function()
        if rabbit then
            rabbit:respawn()
            rabbit = nil
        end
    end)

    local function checkSpell(job, enemySpell, playerSpell)
        local player = xi.test.world:spawnPlayer({ job = job, level = 99, zone = xi.zone.WEST_RONFAURE })
        rabbit = player.entities:get('Forest_Hare')
        rabbit:respawn()
        player.entities:moveTo(rabbit)
        player:setMP(player:getMaxMP())

        assert(not player:hasSpell(enemySpell) and not player:hasSpell(playerSpell))
        assert(player:canLearnSpell(enemySpell) == 95)
        assert(player:canLearnSpell(playerSpell) == 0)
        player:addSpell(enemySpell, { saveToDB = false })
        player:addSpell(playerSpell, { saveToDB = false })
        assert(player:hasSpell(enemySpell) and player:hasSpell(playerSpell))

        local starts = {}
        player:addListener('MAGIC_START', 'PLAYER_ENEMY_ONLY_SPELL_START', function(_, _, spell)
            starts[#starts + 1] = spell:getID()
        end)

        local mp = player:getMP()
        assert(mp >= 112)
        player.actions:useSpell(rabbit, enemySpell)
        xi.test.world:skipTime(5)
        assert(#starts == 0 and player:getMP() == mp)
        assert(not player:hasRecast(xi.recast.MAGIC, enemySpell))

        -- The regional target can roam during the rejected cast's wait.
        player.entities:moveTo(rabbit)
        player.actions:useSpell(rabbit, playerSpell)
        xi.test.world:skipTime(5)
        assert(#starts == 1 and starts[1] == playerSpell)
        assert(player:getMP() < mp and player:hasRecast(xi.recast.MAGIC, playerSpell))
    end

    it('rejects Diaga II while allowing an eligible Red Mage to learn and cast Diaga', function()
        checkSpell(xi.job.RDM, xi.magic.spell.DIAGA_II, xi.magic.spell.DIAGA)
    end)

    it('rejects Poisonga II while allowing an eligible Black Mage to learn and cast Poisonga', function()
        checkSpell(xi.job.BLM, xi.magic.spell.POISONGA_II, xi.magic.spell.POISONGA)
    end)
end)
