-----------------------------------
-- Iroha II's Zanshin job points affect only the landed follow-up swing.
-----------------------------------
describe('Iroha II native Zanshin job points', function()
    local targetId

    after_each(function()
        if targetId and GetEntityByID(targetId, nil, true) then
            DespawnMob(targetId)
            for _ = 1, 10 do
                xi.test.world:tick()
                if not GetEntityByID(targetId, nil, true) then
                    break
                end
            end

            assert(not GetEntityByID(targetId, nil, true))
        end

        targetId = nil
    end)

    it('adds 40 flat attack to a native Zanshin follow-up and preserves normal attack', function()
        xi.test.world:setSetting('main.TRUST_JOB99_IROHA_II', true)
        xi.test.world:setSetting('main.ENABLE_TRUST_ALTER_EGO_POINT_BONUSES', false)
        xi.test.world:setSetting('main.ENABLE_TRUST_UNITY_RANK_STAT_PARITY', false)
        xi.test.world:setSetting('map.ENABLE_AUTO_ATTACK_LUA', false)
        xi.test.world:setSeed(123456)
        local owner = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE, job = xi.job.PLD, level = 99 })
        local iroha = assert(owner:spawnTrust(xi.magic.spell.IROHA_II))
        assert(iroha:isDevelopedTrust() and iroha:getJobPointLevel(xi.jp.ZANSHIN_EFFECT) == 20)
        iroha:removeAllGambits()
        iroha:setAutoAttackEnabled(false)
        iroha:setMobAbilityEnabled(false)
        iroha:setMobMod(xi.mobMod.NO_MOVE, 1)
        for _, mod in ipairs({
            xi.mod.DOUBLE_ATTACK, xi.mod.TRIPLE_ATTACK, xi.mod.QUAD_ATTACK,
            xi.mod.MYTHIC_OCC_ATT_TWICE, xi.mod.MYTHIC_OCC_ATT_THRICE,
            xi.mod.HASSO_ZANSHIN_BONUS, xi.mod.ZANSHIN_DOUBLE_DAMAGE,
        }) do
            iroha:setMod(mod, 0)
        end

        iroha:setMod(xi.mod.ZANSHIN, 100)
        iroha:setMod(xi.mod.CRITHITRATE, -1000)

        local mob = assert(owner:getZone():insertDynamicEntity({
            objtype              = xi.objType.MOB,
            name                 = 'Iroha_Zanshin',
            groupId              = 5,
            groupZoneId          = 154,
            minLevel             = 99,
            maxLevel             = 99,
            respawn              = 0,
            releaseIdOnDisappear = true,
        }))
        targetId = mob:getID()
        SpawnMob(targetId)
        mob:setMaxHP(1000000)
        mob:setHP(1000000)
        mob:setUnkillable(true)
        mob:setAutoAttackEnabled(false)
        mob:setRangedAttackEnabled(false)
        mob:setMagicCastingEnabled(false)
        mob:setMobAbilityEnabled(false)
        mob:setMobMod(xi.mobMod.NO_MOVE, 1)
        mob:setMobMod(xi.mobMod.NO_REST, 1)
        mob:setDropID(0)
        local x, y, z = owner:getXPos(), owner:getYPos(), owner:getZPos()
        mob:setPos(x, y, z)
        iroha:setPos(x, y, z + 1)
        assert(owner.entities:moveTo(mob):getID() == targetId)
        owner.actions:engage(mob)
        owner:setPos(x, y, z + 2.5)
        owner:lookAt(x, y, z + 5)
        assert(not owner:isFacing(mob))

        local missOpener = false
        local hitRate = xi.combat.physicalHitRate.getPhysicalHitRate
        stub('xi.combat.physicalHitRate.getPhysicalHitRate', function(actor, target, offset, ...)
            if actor:getID() == iroha:getID() and target:getID() == targetId then
                assert(offset == 0 or offset == 35)
                return missOpener and offset == 0 and 0 or 1
            end

            return hitRate(actor, target, offset, ...)
        end)

        stub('xi.combat.physical.isParried', false)
        stub('xi.combat.physical.isGuarded', false)
        stub('xi.combat.physical.isBlocked', false)

        -- Keep the native ratio calculation and damage. Suppress the early
        -- pDIF spike so the calculated ratio is observable on both swings.
        local randomInt = math.randomInt
        stub('math.randomInt', function(minimum, maximum)
            if minimum == 1 and maximum == 10000 then
                return 10000
            end

            return randomInt(minimum, maximum)
        end)

        local ratios = {}
        local capRatio = xi.combat.physical.wRatioCapOthers
        stub('xi.combat.physical.wRatioCapOthers', function(ratio, cap)
            ratios[#ratios + 1] = ratio
            return capRatio(ratio, cap)
        end)

        local function swing(followUp)
            missOpener = followUp
            owner.packets:clear()
            local hp = mob:getHP()
            local results
            iroha:setAutoAttackEnabled(true)
            iroha:engage(mob:getTargID())
            iroha:lookAt(x, y, z)
            local function readRound()
                for _, packet in ipairs(owner.packets:actionPackets()) do
                    if packet.cmd_no == xi.action.category.BASIC_ATTACK then
                        assert(packet.m_uID ~= owner:getID(), 'the facing-away owner must produce no melee action')
                        if packet.m_uID == iroha:getID() then
                            assert(not results and #packet.target == 1 and packet.target[1].m_uID == targetId)
                            results = packet.target[1].result
                        end
                    end
                end

                return results ~= nil
            end

            xi.test.world:tickEntity(iroha)
            if not readRound() then
                for _ = 1, 12 do
                    xi.test.world:skipTime(1)
                    if readRound() then
                        break
                    end
                end
            end

            iroha:setAutoAttackEnabled(false)
            local swings = assert(results, 'no native Iroha melee packet for the controlled target')
            assert(#swings == (followUp and 2 or 1))
            if followUp then
                assert(swings[1].miss == xi.action.resolution.MISS and swings[1].value == 0)
            end

            local landed = swings[#swings]
            assert(landed.miss == xi.action.resolution.HIT and landed.value > 0)
            assert(hp - mob:getHP() == landed.value)
        end

        assert(iroha:getMainLvl() == mob:getMainLvl(), 'hold native level correction equal')
        local attack = iroha:getStat(xi.mod.ATT, xi.slot.MAIN)
        local defense = math.max(1, mob:getStat(xi.mod.DEF))
        swing(false)
        assert(#ratios == 1)
        swing(true)
        assert(#ratios == 2)
        assert(math.abs(ratios[1] - math.max(1, attack) / defense) < 0.0001)
        assert(math.abs((ratios[2] - ratios[1]) * defense - 40) < 0.0001)
        assert(iroha:getStat(xi.mod.ATT, xi.slot.MAIN) == attack)
    end)
end)
