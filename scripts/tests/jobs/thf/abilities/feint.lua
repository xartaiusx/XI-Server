describe('Feint effect gain boundary', function()
    ---@type CClientEntityPair
    local player
    ---@type CTestEntity
    local mob

    before_each(function()
        player = xi.test.world:spawnPlayer(
        {
            zone  = xi.zone.WEST_RONFAURE,
            job   = xi.job.THF,
            level = 99,
        })
        stub('xi.combat.physicalHitRate.getPhysicalHitRate', 1.0)
        mob = player.entities:moveTo('Wild_Rabbit')
        mob:respawn()
        mob:setUnkillable(true)
    end)

    after_each(function()
        if mob then
            mob:removeListener('FEINT_GAIN_BOUNDARY')
            mob:delStatusEffect(xi.effect.EVASION_DOWN)
            mob:setUnkillable(false)
            mob:respawn()
        end
    end)

    local function applyFeint()
        player:addStatusEffect(xi.effect.FEINT,
        {
            power    = 150,
            duration = 60,
            origin   = player,
            subPower = 25,
        })
        player.actions:engage(mob)
        xi.test.world:tickEntity(player)
        -- The native attack state waits three seconds before its first swing.
        xi.test.world:skipTime(4)
    end

    it('keeps the ordinary treasure hunter bonus on the gained effect', function()
        applyFeint()
        assert(mob:hasStatusEffect(xi.effect.EVASION_DOWN), 'Feint evasion down was not gained')
        assert(mob:getMod(xi.mod.TREASURE_HUNTER_PROC) == 25, 'Feint treasure hunter bonus changed')
        assert(not player:hasStatusEffect(xi.effect.FEINT), 'Feint was not consumed')
    end)

    it('does not dereference an effect removed by its gain callback', function()
        local removed = false
        mob:addListener('EFFECT_GAIN', 'FEINT_GAIN_BOUNDARY', function(target, effect)
            if effect:getEffectType() == xi.effect.EVASION_DOWN then
                target:delStatusEffect(xi.effect.EVASION_DOWN)
                removed = true
            end
        end)

        applyFeint()
        assert(removed, 'Feint gain callback was not exercised')
        assert(not mob:hasStatusEffect(xi.effect.EVASION_DOWN), 'Removed Feint effect reappeared')
        assert(mob:getMod(xi.mod.TREASURE_HUNTER_PROC) == 0, 'Removed Feint effect gained a bonus')
        assert(not player:hasStatusEffect(xi.effect.FEINT), 'Feint was not consumed')
    end)
end)
