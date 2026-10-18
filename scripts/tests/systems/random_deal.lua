-----------------------------------
-- Large recast collections must not wrap a byte-sized loop index.
-----------------------------------
describe('Random Deal recast boundaries', function()
    local mobId

    after_each(function()
        local mob = mobId and GetEntityByID(mobId, nil, true)
        if mob then
            DespawnMob(mobId)
            for _ = 1, 10 do
                xi.test.world:tick()
                if GetEntityByID(mobId, nil, true) == nil then
                    break
                end
            end

            assert(GetEntityByID(mobId, nil, true) == nil, 'Disposable recast fixture was not destroyed')
        end

        mobId = nil
    end)

    it('terminates and resets an ability with more than 256 recasts', function()
        local player = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE, job = xi.job.COR, level = 99 })
        local mob    = player:getZone():insertDynamicEntity({
            objtype              = xi.objType.MOB,
            name                 = 'Recast_Boundary',
            groupId              = 5,
            groupZoneId          = 154,
            minLevel             = 1,
            maxLevel             = 1,
            respawn              = 0,
            releaseIdOnDisappear = true,
        })
        assert(mob, 'Disposable recast fixture could not be created')
        mobId = mob:getID()
        SpawnMob(mobId)

        -- A mob uses the same native recast collection without constructing
        -- unsupported client recast packets or persisting synthetic ability IDs.
        -- Its entire collection is destroyed during after_each.
        player:setMod(xi.mod.RANDOM_DEAL_BONUS, 0)
        for id = 1000, 1256 do
            mob:addRecast(xi.recast.ABILITY, id, 3600)
            assert(mob:hasRecast(xi.recast.ABILITY, id))
        end

        assert(player:doRandomDeal(mob), 'Random Deal did not reset an active recast')
        local remaining = 0
        for id = 1000, 1256 do
            if mob:hasRecast(xi.recast.ABILITY, id) then
                remaining = remaining + 1
            end
        end

        assert(remaining == 256, string.format('Expected one reset, found %d remaining recasts', remaining))
    end)
end)
