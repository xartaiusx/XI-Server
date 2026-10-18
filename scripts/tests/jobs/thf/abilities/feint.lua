describe('Feint effect gain boundary', function()
    ---@type CClientEntityPair
    local player
    ---@type CTestEntity
    local mob
    local previousNoMove

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
        previousNoMove = mob:getMobMod(xi.mobMod.NO_MOVE)
        mob:setMobMod(xi.mobMod.NO_MOVE, 1)
        -- Spawn already starts a roam path; cancel it before advancing the zone.
        mob:clearPath()
        mob:setUnkillable(true)
        assert(not mob:hasStatusEffect(xi.effect.EVASION_DOWN), 'Fresh target has evasion down')
        assert(mob:getMod(xi.mod.TREASURE_HUNTER_PROC) == 0, 'Fresh target has a Feint bonus')
    end)

    after_each(function()
        if player then
            player:removeListener('FEINT_CONTACT_BOUNDARY')
        end

        if mob then
            mob:removeListener('FEINT_GAIN_BOUNDARY')
            mob:delStatusEffect(xi.effect.EVASION_DOWN)
            mob:setUnkillable(false)
            if previousNoMove ~= nil then
                mob:setMobMod(xi.mobMod.NO_MOVE, previousNoMove)
            end

            mob:respawn()
        end
    end)

    local function applyFeint()
        local contacted = false
        player:addListener('MELEE_SWING_HIT', 'FEINT_CONTACT_BOUNDARY', function(attacker, target)
            if target:getID() == mob:getID() then
                contacted = true
            end
        end)

        player:addStatusEffect(xi.effect.FEINT,
        {
            power    = 150,
            duration = 60,
            origin   = player,
            subPower = 25,
        })
        player.actions:engage(mob)
        xi.test.world:tickEntity(player)
        assert(player:isEngaged(), 'Feint fixture did not engage')
        -- The native attack state waits three seconds before its first swing.
        xi.test.world:skipTime(4)
        assert(contacted, 'Feint fixture did not land its first native swing')
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
