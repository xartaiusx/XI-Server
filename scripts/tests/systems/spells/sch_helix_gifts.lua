describe('SCH helix II gift admission', function()
    ---@type CClientEntityPair
    local player
    local rabbit
    local starts
    local helixSpells =
    {
        xi.magic.spell.GEOHELIX_II,
        xi.magic.spell.HYDROHELIX_II,
        xi.magic.spell.ANEMOHELIX_II,
        xi.magic.spell.PYROHELIX_II,
        xi.magic.spell.CRYOHELIX_II,
        xi.magic.spell.IONOHELIX_II,
        xi.magic.spell.NOCTOHELIX_II,
        xi.magic.spell.LUMINOHELIX_II,
    }

    before_each(function()
        player = xi.test.world:spawnPlayer({ job = xi.job.SCH, level = 99, zone = xi.zone.WEST_RONFAURE })
        rabbit = player.entities:moveTo(17186876) -- West Ronfaure Forest Hare, base level 2-3.
        rabbit:setLevelRange(80, 80)
        rabbit:respawn()
        starts = {}
        player:addListener('MAGIC_START', 'SCH_HELIX_GIFT_START', function(_, _, spell)
            starts[#starts + 1] = spell:getID()
        end)
    end)

    after_each(function()
        if rabbit then
            rabbit:setLevelRange(2, 3)
            rabbit:respawn()
        end
    end)

    it('rejects known helix II spells below their spent-JP requirement', function()
        assert(player:getSpentJobPoints() < 1200)
        local mp = player:getMP()

        for _, spellId in ipairs({ xi.magic.spell.HYDROHELIX_II, xi.magic.spell.IONOHELIX_II }) do
            player:addSpell(spellId, { saveToDB = false })
            assert(player:hasSpell(spellId))
            player.actions:useSpell(rabbit, spellId)
            xi.test.world:skipTime(10)
            assert(#starts == 0 and player:getMP() == mp)
            assert(not player:hasRecast(xi.recast.MAGIC, spellId))
        end
    end)

    it('learns and casts defined helix II spells after reaching the normal SCH gift', function()
        for _, spellId in ipairs(helixSpells) do
            assert(not player:hasSpell(spellId))
        end

        player:masterJob()
        assert(player:getSpentJobPoints() >= 1200)
        for _, spellId in ipairs(helixSpells) do
            assert(player:hasSpell(spellId))
        end

        assert(not player:hasSpell(xi.magic.spell.AURORASTORM_II))
        stub('xi.combat.magicHitRate.calculateResistRate', 1)
        local mp = player:getMP()

        player.actions:useSpell(rabbit, xi.magic.spell.HYDROHELIX_II)
        xi.test.world:skipTime(10)
        assert(#starts == 1 and starts[1] == xi.magic.spell.HYDROHELIX_II)
        assert(player:getMP() < mp)
        assert(rabbit:hasStatusEffect(xi.effect.HELIX))
        assert(rabbit:getStatusEffect(xi.effect.HELIX):getTier() == 2)
        assert(player:hasRecast(xi.recast.MAGIC, xi.magic.spell.HYDROHELIX_II))
    end)
end)
