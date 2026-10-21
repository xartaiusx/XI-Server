describe('Player fixture loading', function()
    local onGameIn

    before_each(function()
        onGameIn = spy('xi.player.onGameIn')
    end)

    it('loads an ordinary player before its single initial game-in callback', function()
        local player = xi.test.world:spawnPlayer(
            {
                zone  = xi.zone.GM_HOME,
                race  = xi.race.HUME_F,
                job   = xi.job.WHM,
                level = 37,
                name  = 'FixtureNormal',
            })

        onGameIn:called(1)
        assert(onGameIn.calls[1].args[2] == false, 'ordinary fixture was treated as a new player')
        assert(onGameIn.calls[1].args[3] == false, 'initial login was treated as zoning')
        assert(player:getID() > 0, 'fixture has no character ID')
        assert(player:getZoneID() == xi.zone.GM_HOME, 'initial zone changed')
        assert(player:getRace() == xi.race.HUME_F, 'fixture race changed')
        assert(player:getName() == 'FixtureNormal', 'in-memory name override was lost')
        assert(player:getMainJob() == xi.job.WHM, 'fixture job override was lost')
        assert(player:getMainLvl() == 37, 'fixture level override was lost')
    end)

    it('preserves first-login initialization for an explicitly new player', function()
        local player = xi.test.world:spawnPlayer({ zone = xi.zone.GM_HOME, new = true })

        onGameIn:called(1)
        assert(onGameIn.calls[1].args[2] == true, 'new fixture skipped first-login initialization')
        assert(onGameIn.calls[1].args[3] == false, 'new-player login was treated as zoning')
        assert(player:hasTitle(xi.title.NEW_ADVENTURER), 'first-login title was not granted')
        assert(player:getCharVar('spokeKindlix') == 1, 'native character initialization did not run')
    end)

    it('reloads once for direct zoning and refreshes the wrapper entity', function()
        local player = xi.test.world:spawnPlayer({ zone = xi.zone.GM_HOME, name = 'FixtureZone' })
        local charId = player:getID()

        player:setCharVar('FixtureLoadPersist', 73)
        player:setLocalVar('FixtureLoadLocal', 41)
        assert(player:getCharVar('FixtureLoadPersist') == 73, 'persistent fixture setup failed')
        assert(player:getLocalVar('FixtureLoadLocal') == 41, 'local fixture setup failed')

        -- Do not retain the spy's wrapper for the entity that zoning will replace.
        onGameIn:clear()
        player:gotoZone(xi.zone.WEST_RONFAURE)

        onGameIn:called(1)
        assert(onGameIn.calls[1].args[2] == false, 'zoning repeated first-login initialization')
        assert(onGameIn.calls[1].args[3] == true, 'direct zoning lost its zoning flag')
        assert(player:getID() == charId, 'zoning replaced character identity')
        assert(player:getZoneID() == xi.zone.WEST_RONFAURE, 'wrapper retained the previous zone')
        assert(player:getName() == 'FixtureZone', 'zoning lost the in-memory name override')
        assert(player:getCharVar('FixtureLoadPersist') == 73, 'zoning lost persistent character state')
        assert(player:getLocalVar('FixtureLoadLocal') == 0, 'zoning reused the old entity')
    end)

    it('reloads once for a server-requested zone transition', function()
        local player = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE })
        local charId = player:getID()

        player:setCharVar('FixtureLoadPersist', 97)
        player:setLocalVar('FixtureLoadLocal', 53)
        assert(player:getCharVar('FixtureLoadPersist') == 97, 'persistent fixture setup failed')
        assert(player:getLocalVar('FixtureLoadLocal') == 53, 'local fixture setup failed')

        onGameIn:clear()
        player:setPos(0, 0, 0, 0, xi.zone.GM_HOME)
        for _ = 1, 4 do
            xi.test.world:skipTime(1)
        end

        onGameIn:called(1)
        assert(onGameIn.calls[1].args[2] == false, 'server zoning repeated first-login initialization')
        assert(onGameIn.calls[1].args[3] == true, 'server zoning lost its zoning flag')
        assert(player:getID() == charId, 'server zoning replaced character identity')
        assert(player:getZoneID() == xi.zone.GM_HOME, 'server-requested zoning did not complete')
        assert(player:getCharVar('FixtureLoadPersist') == 97, 'server zoning lost persistent character state')
        assert(player:getLocalVar('FixtureLoadLocal') == 0, 'server zoning reused the old entity')
    end)
end)
