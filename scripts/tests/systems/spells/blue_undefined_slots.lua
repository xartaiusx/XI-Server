describe('Undefined Blue Magic slots', function()
    -- The native dataset has no spell at 0x200 + 2.
    local undefinedSpell = 514
    local footKick = xi.magic.spell.FOOT_KICK

    ---@type CClientEntityPair
    local player

    before_each(function()
        player = xi.test.world:spawnPlayer({ job = xi.job.BLU, level = 99, zone = xi.zone.GM_HOME })
        player:addSpell(footKick)
    end)

    it('replaces an undefined occupied slot with a learned spell', function()
        local agility = player:getMod(xi.mod.AGI)
        assert(player.actions:seedUndefinedBlueSpell(0, undefinedSpell))
        assert(player:getSetBlueSpells()[1] == undefinedSpell)

        player.actions:setBlueSpells({ footKick })

        local spells = player:getSetBlueSpells()
        assert(#spells == 1 and spells[1] == footKick)
        assert(player:getMod(xi.mod.AGI) == agility + 1)
    end)

    it('clears undefined and valid slots when leaving Blue Mage', function()
        player.actions:setBlueSpells({ footKick })
        assert(player.actions:seedUndefinedBlueSpell(1, undefinedSpell))
        local spells = player:getSetBlueSpells()
        assert(#spells == 2 and spells[1] == footKick and spells[2] == undefinedSpell)

        player:changeJob(xi.job.WAR)

        assert(#player:getSetBlueSpells() == 0)
    end)

    it('clears an undefined slot when validating a level change', function()
        player.actions:setBlueSpells({ footKick })
        assert(player.actions:seedUndefinedBlueSpell(1, undefinedSpell))
        local spells = player:getSetBlueSpells()
        assert(#spells == 2 and spells[1] == footKick and spells[2] == undefinedSpell)

        player:setLevel(98)

        spells = player:getSetBlueSpells()
        assert(#spells == 1 and spells[1] == footKick)
    end)
end)
