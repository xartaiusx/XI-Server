describe('Player gift spell persistence', function()
    it('persists defined gifts without inserting undefined gift rows', function()
        local player = xi.test.world:spawnPlayer({ job = xi.job.BLM, level = 99, zone = xi.zone.WEST_RONFAURE })
        local definedGift = xi.magic.spell.FIRE_VI
        -- Aspir III has a gift entry and no active spell definition in this era.
        local undefinedGift = xi.magic.spell.ASPIR_III

        assert(not player:hasPersistedSpell(definedGift))
        assert(not player:hasPersistedSpell(undefinedGift))

        player:masterJob()
        assert(player:getSpentJobPoints() >= 550)
        assert(player:hasSpell(definedGift))
        assert(player:hasPersistedSpell(definedGift))
        assert(not player:hasSpell(undefinedGift))
        assert(not player:hasPersistedSpell(undefinedGift))
    end)
end)
