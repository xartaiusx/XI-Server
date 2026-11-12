describe('Player spell-use override result', function()
    ---@type CClientEntityPair
    local player
    local starts

    before_each(function()
        player = xi.test.world:spawnPlayer({ job = xi.job.RDM, level = 99, zone = xi.zone.WEST_RONFAURE })
        player:addSpell(xi.magic.spell.CURE, { saveToDB = false })
        player:addSpell(xi.magic.spell.CURE_V, { saveToDB = false })
        assert(player:hasSpell(xi.magic.spell.CURE) and player:hasSpell(xi.magic.spell.CURE_V))
        starts = {}
        player:addListener('MAGIC_START', 'SPELL_OVERRIDE_RESULT_START', function(_, _, spell)
            starts[#starts + 1] = spell:getID()
        end)
    end)

    local function checkFallback(callback)
        stub('xi.spells.canUseSpellOverride', callback)
        local mp = player:getMP()

        player.actions:useSpell(player, xi.magic.spell.CURE_V)
        xi.test.world:skipTime(5)
        assert(#starts == 0 and player:getMP() == mp)
        assert(not player:hasRecast(xi.recast.MAGIC, xi.magic.spell.CURE_V))

        player.actions:useSpell(player, xi.magic.spell.CURE)
        xi.test.world:skipTime(5)
        assert(#starts == 1 and starts[1] == xi.magic.spell.CURE)
        assert(player:hasRecast(xi.recast.MAGIC, xi.magic.spell.CURE))
    end

    it('falls back to job eligibility when the override returns no value', function()
        checkFallback(function()
        end)
    end)

    it('falls back to job eligibility when the override returns nil', function()
        checkFallback(function()
            return nil
        end)
    end)

    it('falls back to job eligibility when the override returns a nonboolean value', function()
        checkFallback(function()
            return 1
        end)
    end)

    it('falls back to job eligibility when the override explicitly returns false', function()
        checkFallback(function()
            return false
        end)
    end)

    it('keeps the gift gate when the override result is malformed', function()
        stub('xi.spells.canUseSpellOverride', function()
            return nil
        end)

        local giftCases =
        {
            { xi.job.RDM, xi.magic.spell.TEMPER_II },
            { xi.job.DRK, xi.magic.spell.DRAIN_III },
            { xi.job.SCH, xi.magic.spell.HYDROHELIX_II },
        }
        for _, case in ipairs(giftCases) do
            local subject = xi.test.world:spawnPlayer({ job = case[1], level = 99, zone = xi.zone.WEST_RONFAURE })
            assert(subject:getSpentJobPoints() == 0)
            assert(subject:canLearnSpell(case[2]) == 95)
        end

        local spellId = xi.magic.spell.TEMPER_II
        player:addSpell(spellId, { saveToDB = false })
        assert(player:hasSpell(spellId))
        local mp = player:getMP()
        player.actions:useSpell(player, spellId)
        xi.test.world:skipTime(5)
        assert(#starts == 0 and player:getMP() == mp)
        assert(not player:hasRecast(xi.recast.MAGIC, spellId))
    end)

    it('still admits a known spell when the override explicitly returns true', function()
        stub('xi.spells.canUseSpellOverride', true)

        player.actions:useSpell(player, xi.magic.spell.CURE_V)
        xi.test.world:skipTime(5)

        assert(#starts == 1 and starts[1] == xi.magic.spell.CURE_V)
        assert(player:hasRecast(xi.recast.MAGIC, xi.magic.spell.CURE_V))
    end)
end)
