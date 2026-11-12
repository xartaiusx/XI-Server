describe('Dispelga equipment requirement', function()
    ---@type CClientEntityPair
    local player
    local rabbit
    local starts

    local function prepareCaster(job)
        player = xi.test.world:spawnPlayer({ job = job, level = 99, zone = xi.zone.WEST_RONFAURE })
        rabbit = player.entities:moveTo('Forest_Hare')
        rabbit:spawn()
        starts = 0
        player:addListener('MAGIC_START', 'DISPELGA_EQUIPMENT_START', function(_, _, spell)
            if spell:getID() == xi.magic.spell.DISPELGA then
                starts = starts + 1
            end
        end)
    end

    it('rejects an old learned bit without Daybreak in the main hand', function()
        prepareCaster(xi.job.RDM)
        player:addSpell(xi.magic.spell.DISPELGA, { saveToDB = false })
        assert(player:hasSpell(xi.magic.spell.DISPELGA))
        assert(player:getEquipID(xi.slot.MAIN) ~= xi.item.DAYBREAK)
        local mp = player:getMP()

        player.actions:useSpell(rabbit, xi.magic.spell.DISPELGA)
        xi.test.world:skipTime(5)
        assert(starts == 0 and player:getMP() == mp)
        assert(not player:hasRecast(xi.recast.MAGIC, xi.magic.spell.DISPELGA))
    end)

    local function checkMainHandGrant(job, replacement)
        prepareCaster(job)
        assert(not player:hasSpell(xi.magic.spell.DISPELGA))
        player:addItem(xi.item.DAYBREAK)
        player:equipItem(xi.item.DAYBREAK, nil, xi.slot.MAIN)
        assert(player:getEquipID(xi.slot.MAIN) == xi.item.DAYBREAK)
        assert(player:hasSpell(xi.magic.spell.DISPELGA))
        local mp = player:getMP()

        player.actions:useSpell(rabbit, xi.magic.spell.DISPELGA)
        xi.test.world:skipTime(5)
        assert(starts == 1 and player:getMP() < mp)
        assert(player:hasRecast(xi.recast.MAGIC, xi.magic.spell.DISPELGA))

        player:addItem(replacement)
        player:equipItem(replacement, nil, xi.slot.MAIN)
        assert(player:getEquipID(xi.slot.MAIN) == replacement)
        assert(not player:hasSpell(xi.magic.spell.DISPELGA))
    end

    it('grants, admits and revokes the temporary spell for RDM', function()
        checkMainHandGrant(xi.job.RDM, xi.item.BRONZE_SWORD)
    end)

    it('grants, admits and revokes the temporary spell for GEO', function()
        checkMainHandGrant(xi.job.GEO, xi.item.ASH_CLUB)
    end)
end)
