describe('Rolanberry Goblin Pathfinder death callback', function()
    local player
    local mob
    local onMobDeath

    local function assertRegimeCall(regime, expectedPlayer)
        regime:called(1)
        local args = regime.calls[1].args

        if expectedPlayer then
            assert(args[1]:getID() == expectedPlayer:getID(), 'regime received the wrong player')
        else
            assert(args[1] == nil, 'regime did not receive the native nil player')
        end

        assert(args[2]:getID() == mob:getID(), 'regime received the wrong mob')
        assert(args[3] == 86 and args[4] == 2 and args[5] == xi.regime.type.FIELDS,
            'existing regime contract changed')
    end

    before_each(function()
        xi.test.world:setSetting('main.ENABLE_ACP', 1)
        player = xi.test.world:spawnPlayer({ zone = xi.zone.ROLANBERRY_FIELDS })
        mob    = player.entities:get(17228224)

        -- Use the same cached script table as native entity callback dispatch.
        local scriptObject = xi.zones[mob:getZoneName()].mobs[mob:getName()]
        assert(scriptObject and type(scriptObject.onMobDeath) == 'function', 'native mob script was not cached')
        onMobDeath = scriptObject.onMobDeath
    end)

    it('accepts a nil player without rolling or granting an ACP reward', function()
        local regime = spy('xi.regime.checkRegime')
        local award  = spy('npcUtil.giveKeyItem')
        local roll   = stub('math.randomInt', 1)

        onMobDeath(mob, nil, { noKiller = true, isKiller = false, isWeaponSkillKill = false })

        assertRegimeCall(regime, nil)
        roll:called(0)
        award:called(0)
        assert(not player:hasKeyItem(xi.keyItem.JUG_OF_GREASY_GOBLIN_JUICE), 'no-killer callback granted a key item')
    end)

    it('supports the native no-killer death path used by test despawn', function()
        -- respawn() establishes an alive owner before recording the one native death.
        mob:respawn()
        local regime = spy('xi.regime.checkRegime')
        local award  = spy('npcUtil.giveKeyItem')

        mob:despawn()

        assertRegimeCall(regime, nil)
        award:called(0)
        assert(not player:hasKeyItem(xi.keyItem.JUG_OF_GREASY_GOBLIN_JUICE), 'native no-killer death granted a key item')
    end)

    it('preserves the eligible player reward at the existing fifteen-percent boundary', function()
        player:addMission(xi.mission.log_id.ACP, xi.mission.id.acp.THE_ECHO_AWAKENS)
        local regime = spy('xi.regime.checkRegime')
        local award  = spy('npcUtil.giveKeyItem')
        local roll   = stub('math.randomInt', 15)

        onMobDeath(mob, player, { noKiller = false, isKiller = true, isWeaponSkillKill = false })

        assertRegimeCall(regime, player)
        roll:called(1)
        roll:calledWith(1, 100)
        award:called(1)
        award:calledWith(player, xi.keyItem.JUG_OF_GREASY_GOBLIN_JUICE)
        player.assert:hasKI(xi.keyItem.JUG_OF_GREASY_GOBLIN_JUICE)
    end)

    it('does not grant the reward above the existing roll boundary', function()
        player:addMission(xi.mission.log_id.ACP, xi.mission.id.acp.THE_ECHO_AWAKENS)
        local regime = spy('xi.regime.checkRegime')
        local award  = spy('npcUtil.giveKeyItem')
        local roll   = stub('math.randomInt', 16)

        onMobDeath(mob, player, { noKiller = false, isKiller = true })

        assertRegimeCall(regime, player)
        roll:called(1)
        roll:calledWith(1, 100)
        award:called(0)
        assert(not player:hasKeyItem(xi.keyItem.JUG_OF_GREASY_GOBLIN_JUICE), 'failed roll granted a key item')
    end)

    it('preserves the disabled ACP gate for a real player', function()
        player:addMission(xi.mission.log_id.ACP, xi.mission.id.acp.THE_ECHO_AWAKENS)
        xi.test.world:setSetting('main.ENABLE_ACP', 0)
        local regime = spy('xi.regime.checkRegime')
        local award  = spy('npcUtil.giveKeyItem')
        local roll   = stub('math.randomInt', 1)

        onMobDeath(mob, player, { noKiller = false, isKiller = true })

        assertRegimeCall(regime, player)
        roll:called(0)
        award:called(0)
        assert(not player:hasKeyItem(xi.keyItem.JUG_OF_GREASY_GOBLIN_JUICE), 'disabled ACP granted a key item')
    end)

    it('preserves the mission eligibility gate', function()
        player:addMission(xi.mission.log_id.ACP, xi.mission.id.acp.A_CRYSTALLINE_PROPHECY)
        local regime = spy('xi.regime.checkRegime')
        local award  = spy('npcUtil.giveKeyItem')
        local roll   = stub('math.randomInt', 1)

        onMobDeath(mob, player, { noKiller = false, isKiller = true })

        assertRegimeCall(regime, player)
        roll:called(0)
        award:called(0)
        assert(not player:hasKeyItem(xi.keyItem.JUG_OF_GREASY_GOBLIN_JUICE), 'ineligible mission granted a key item')
    end)

    it('does not reroll or regrant an already owned reward', function()
        player:addMission(xi.mission.log_id.ACP, xi.mission.id.acp.THE_ECHO_AWAKENS)
        player:addKeyItem(xi.keyItem.JUG_OF_GREASY_GOBLIN_JUICE)
        local regime = spy('xi.regime.checkRegime')
        local award  = spy('npcUtil.giveKeyItem')
        local roll   = stub('math.randomInt', 1)

        onMobDeath(mob, player, { noKiller = false, isKiller = true })

        assertRegimeCall(regime, player)
        roll:called(0)
        award:called(0)
        player.assert:hasKI(xi.keyItem.JUG_OF_GREASY_GOBLIN_JUICE)
    end)
end)
