describe('DRK gift spell admission', function()
    ---@type CClientEntityPair
    local player
    local rabbit
    local starts

    before_each(function()
        player = xi.test.world:spawnPlayer({ job = xi.job.DRK, level = 99, zone = xi.zone.WEST_RONFAURE })
        rabbit = player.entities:moveTo('Forest_Hare')
        rabbit:spawn()
        player:addSpell(xi.magic.spell.DRAIN_III, { saveToDB = false })
        assert(player:hasSpell(xi.magic.spell.DRAIN_III))
        starts = {}
        player:addListener('MAGIC_START', 'DRK_GIFT_START', function(_, _, spell)
            starts[#starts + 1] = spell:getID()
        end)
    end)

    it('rejects known Drain III before its DRK threshold', function()
        assert(player:getSpentJobPoints() < 550)
        local mp = player:getMP()

        player.actions:useSpell(rabbit, xi.magic.spell.DRAIN_III)
        xi.test.world:skipTime(7)

        assert(#starts == 0 and player:getMP() == mp)
        assert(not player:hasRecast(xi.recast.MAGIC, xi.magic.spell.DRAIN_III))
    end)

    it('admits the learned Drain III after DRK reaches its spent-JP requirement', function()
        player:masterJob()
        assert(player:getSpentJobPoints() >= 550)
        local mp = player:getMP()

        player.actions:useSpell(rabbit, xi.magic.spell.DRAIN_III)
        xi.test.world:skipTime(7)

        assert(#starts == 1 and starts[1] == xi.magic.spell.DRAIN_III and player:getMP() < mp)
        assert(player:hasRecast(xi.recast.MAGIC, xi.magic.spell.DRAIN_III))
    end)
end)
