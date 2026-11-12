describe('Player Blue Magic setting', function()
    it('admits a learned spell within the effective Blue Mage support level', function()
        -- Use a scoped synthetic support level to exercise the configured level rather than half the main level.
        xi.test.world:setSetting('map.SUBJOB_RATIO', 3)
        local player = xi.test.world:spawnPlayer({ job = xi.job.RDM, level = 99, zone = xi.zone.WEST_RONFAURE })
        player:changesJob(xi.job.BLU)
        player:setsLevel(58)
        assert(player:getSubLvl() == 58)

        local spellId = xi.magic.spell.MAGIC_FRUIT
        player:addSpell(spellId, { saveToDB = false })
        assert(player:hasSpell(spellId))

        local starts = 0
        player:addListener('MAGIC_START', 'BLUE_SUPPORT_LEVEL_START', function(_, _, spell)
            if spell:getID() == spellId then
                starts = starts + 1
            end
        end)

        player.actions:setBlueSpells({ spellId })
        xi.test.world:skipTime(61)
        player:setHP(player:getMaxHP() - 100)
        player:setMP(player:getMaxMP())
        local hp = player:getHP()

        player.actions:useSpell(player, spellId)
        xi.test.world:skipTime(5)
        assert(starts == 1 and player:getHP() > hp)
    end)
end)
