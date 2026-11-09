-----------------------------------
-- Trust gambits that read the mob's current cast
-----------------------------------

describe('Trust gambits', function()
    -- Amchuchu checks whether the mob's elemental cast is aimed at her.
    it('read a cast whose target has left the zone', function()
        local player = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE, job = xi.job.WAR, level = 75 })
        local mob    = player.entities:moveTo('Wild_Rabbit')
        mob:respawn()
        mob:setMobMod(xi.mobMod.NO_MOVE, 1)
        mob:setUnkillable(true)

        player:spawnTrust(xi.magic.spell.AMCHUCHU)
        xi.test.world:skipTime(1)
        local amchuchu = player:getPartyWithTrusts()[2]
        assert(amchuchu and amchuchu:isTrust(), 'precondition: Amchuchu was summoned')
        -- This regular party uses the retail trigger, so engage and wait for
        -- a real owner melee round before exercising Amchuchu's cast gambit.
        local ownerRound = false
        player:addListener('ATTACK', 'TRUST_GAMBIT_TEST_OWNER_ROUND', function(_, attackTarget)
            ownerRound = ownerRound or attackTarget:getID() == mob:getID()
        end)

        mob:updateEnmity(player)
        player.actions:engage(mob)
        for _ = 1, 8 do
            xi.test.world:skipTime(1)
            xi.test.world:tickEntity(amchuchu)
            local trustTarget = amchuchu:getTarget()
            if ownerRound and trustTarget and trustTarget:getID() == mob:getID() then
                break
            end
        end

        player:removeListener('TRUST_GAMBIT_TEST_OWNER_ROUND')
        assert(ownerRound, 'precondition: owner executed a melee round on the rabbit')
        local trustTarget = amchuchu:getTarget()
        assert(amchuchu:isEngaged() and trustTarget and trustTarget:getID() == mob:getID(),
            'precondition: Amchuchu engaged the rabbit')

        local target = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE })
        target:setPos(mob:getXPos(), mob:getYPos(), mob:getZPos())
        mob:addMod(xi.mod.MP, 1000)
        mob:updateHealth()
        mob:setMP(1000)
        mob:castSpell(xi.magic.spell.QUAKE, target)
        xi.test.world:tickEntity(mob)
        xi.test.world:tickEntity(mob)
        assert(mob:getCurrentAction() == xi.action.category.MAGIC_CASTING, 'precondition: the rabbit is casting')

        target:gotoZone(xi.zone.LA_THEINE_PLATEAU)

        for _ = 1, 10 do
            xi.test.world:skipTime(1)
            xi.test.world:tickEntity(mob)
            xi.test.world:tickEntity(amchuchu)
        end
    end)
end)
