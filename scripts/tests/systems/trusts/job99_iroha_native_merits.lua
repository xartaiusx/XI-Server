-----------------------------------
-- Iroha II: native Store TP, Overwhelm and Cure cast-time consumers
-----------------------------------
describe('Iroha II native merit consumers', function()
    local targets

    before_each(function()
        targets = {}
        xi.test.world:setSetting('main.TRUST_JOB99_IROHA_II', true)
        xi.test.world:setSetting('main.ENABLE_TRUST_ALTER_EGO_POINT_BONUSES', false)
        xi.test.world:setSetting('main.ENABLE_TRUST_UNITY_RANK_STAT_PARITY', false)
    end)

    after_each(function()
        for _, id in ipairs(targets) do
            if GetEntityByID(id, nil, true) then
                DespawnMob(id)
            end
        end

        for _ = 1, 10 do
            xi.test.world:tick()
        end

        for _, id in ipairs(targets) do
            assert(not GetEntityByID(id, nil, true), 'retire the exact disposable merit fixture')
        end
    end)

    local function spawn()
        local owner = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE, job = xi.job.PLD, level = 99 })
        local iroha = assert(owner:spawnTrust(xi.magic.spell.IROHA_II))
        assert(iroha:isDevelopedTrust() and iroha:getMainJob() == xi.job.SAM and iroha:getSubJob() == xi.job.WHM)
        iroha:removeAllGambits()
        iroha:setAutoAttackEnabled(false)
        iroha:setMobAbilityEnabled(false)
        iroha:setPos(owner:getXPos(), owner:getYPos(), owner:getZPos())
        return owner, iroha
    end

    local function legSweep(owner, iroha, front, spentTP)
        spentTP = spentTP or 1000
        local mob = assert(owner:getZone():insertDynamicEntity({
            objtype              = xi.objType.MOB,
            name                 = 'Iroha_Merit_Polearm',
            groupId              = 5,
            groupZoneId          = 154,
            minLevel             = 99,
            maxLevel             = 99,
            respawn              = 0,
            releaseIdOnDisappear = true,
        }))
        local id = mob:getID()
        targets[#targets + 1] = id
        SpawnMob(id)
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
        iroha:setPos(x, y, z)
        mob:setPos(x, y, z + 2)
        iroha:lookAt(x, y, z + 2)
        mob:lookAt(x, y, front and z or z + 4)
        assert(iroha:isInfront(mob) == front)

        local hp = mob:getHP()
        local result
        iroha:addListener('WEAPONSKILL_USE', 'IROHA_MERIT_WS', function(actor, recipient, skill, spent, _, damage)
            assert(not result and actor:getID() == iroha:getID() and recipient:getID() == id)
            assert(skill:getID() == xi.weaponskill.LEG_SWEEP and spent == spentTP and damage > 0)
            assert(actor:isInfront(recipient) == front, 'the native action must retain the selected facing')
            result = { damage = damage, tp = actor:getTP() }
        end)

        xi.test.world:setSeed(123456)
        iroha:setTP(spentTP)
        assert(owner.actions:useTrustWeaponskill(iroha, mob, xi.weaponskill.LEG_SWEEP))
        xi.test.world:tickEntity(iroha)
        xi.test.world:skipTime(3)
        xi.test.world:skipTime(3)
        iroha:removeListener('IROHA_MERIT_WS')
        assert(result and mob:getHP() == hp - result.damage and iroha:getTP() == result.tp,
            'native landed damage and TP must match the exact action')

        DespawnMob(id)
        for _ = 1, 10 do
            xi.test.world:tick()
            if not GetEntityByID(id, nil, true) then
                break
            end
        end

        assert(not GetEntityByID(id, nil, true), 'retire this sample before the next native action')
        return result
    end

    it('applies Store TP to landed TP return and Overwhelm only to frontal polearm damage', function()
        local owner, iroha = spawn()
        assert(iroha:getWeaponSkillType(xi.slot.MAIN) == xi.skill.POLEARM)
        assert(iroha:getMerit(xi.merit.STORE_TP_EFFECT) == 10 and iroha:getMerit(xi.merit.OVERWHELM) == 5)
        -- Hold the weapon-skill input to a single landed hit. Keep the actual
        -- native damage, facing and TP consumers and final resource changes.
        stub('xi.combat.physicalHitRate.getPhysicalHitRate', 1)
        stub('xi.combat.physical.calculateMeleePDIF', 3)
        stub('xi.combat.physical.isParried', false)
        stub('xi.combat.physical.isGuarded', false)
        stub('xi.combat.physical.isBlocked', false)
        for _, mod in ipairs({
            xi.mod.DOUBLE_ATTACK, xi.mod.TRIPLE_ATTACK, xi.mod.QUAD_ATTACK, xi.mod.MYTHIC_OCC_ATT_TWICE,
            xi.mod.MYTHIC_OCC_ATT_THRICE, xi.mod.SAVETP, xi.mod.REGAIN,
        }) do
            iroha:setMod(mod, 0)
        end

        local store = iroha:getMod(xi.mod.STORETP)
        local delay = xi.combat.tp.getModifiedDelayAndCanZanshin(iroha, iroha:getBaseDelay()).modifiedDelay
        local baseTP = xi.combat.tp.calculateTPReturn(iroha, delay)
        local rear = legSweep(owner, iroha, false)
        local front = legSweep(owner, iroha, true)
        assert(rear.damage >= 100 and math.abs(front.damage - math.floor(rear.damage + rear.damage * 0.19)) <= 1,
            'front-facing native damage must gain the rank-five bonus within integer rounding')
        assert(rear.tp == math.floor(baseTP * (1 + (store + 10) / 100)) and front.tp == rear.tp)

        -- Cancel only the fixture's known +10 merit contribution using the
        -- native modifier input. The same actor still has the selected merit.
        iroha:setMod(xi.mod.STORETP, store - 10)
        local neutral = legSweep(owner, iroha, false)
        assert(iroha:getMerit(xi.merit.STORE_TP_EFFECT) == 10 and neutral.damage == rear.damage)
        assert(neutral.tp == math.floor(baseTP * (1 + store / 100)) and neutral.tp < rear.tp)
    end)

    it('adds Yaegasumi job-point TP only to effective native weapon-skill TP while active', function()
        local owner, iroha = spawn()
        assert(iroha:getJobPointLevel(xi.jp.YAEGASUMI_EFFECT) == 20)
        iroha:setMod(xi.mod.TP_BONUS, 0)
        stub('xi.combat.physicalHitRate.getPhysicalHitRate', 1)
        stub('xi.combat.physical.calculateMeleePDIF', 3)
        stub('xi.combat.physical.isParried', false)
        stub('xi.combat.physical.isGuarded', false)
        stub('xi.combat.physical.isBlocked', false)

        local effectiveTP = {}
        local physical = xi.weaponskills.doPhysicalWeaponskill
        stub('xi.weaponskills.doPhysicalWeaponskill', function(actor, target, skill, params, tp, action, primary, taChar)
            if
                actor:getID() == iroha:getID() and
                skill == xi.weaponskill.LEG_SWEEP and
                primary
            then
                table.insert(effectiveTP, tp)
            end

            return physical(actor, target, skill, params, tp, action, primary, taChar)
        end)

        legSweep(owner, iroha, false)

        iroha:setTP(1000)
        assert(owner.actions:useTrustAbility(iroha, iroha, xi.jobAbility.YAEGASUMI))
        xi.test.world:tickEntity(iroha)
        xi.test.world:skipTime(1)
        assert(iroha:hasStatusEffect(xi.effect.YAEGASUMI))
        assert(iroha:hasRecast(xi.recast.ABILITY, xi.recastID.SPECIAL2))
        assert(iroha:getTP() == 1000 and iroha:getMod(xi.mod.TP_BONUS) == 600)
        legSweep(owner, iroha, false)
        legSweep(owner, iroha, false, 2700)

        xi.test.world:skipTime(45)
        assert(not iroha:hasStatusEffect(xi.effect.YAEGASUMI))
        assert(iroha:getMod(xi.mod.TP_BONUS) == 0)
        legSweep(owner, iroha, false)

        assert(#effectiveTP == 4)
        assert(effectiveTP[1] == 1000 and effectiveTP[2] == 1600 and effectiveTP[3] == 3000 and effectiveTP[4] == 1000)
    end)

    for _, withMerit in ipairs({ true, false }) do
        it(withMerit and 'finishes Curaga V in the native merit timing window' or 'finishes later when the native merit contribution is neutralized', function()
            local owner, iroha = spawn()
            local spellId = xi.magic.spell.CURAGA_V
            assert(GetSpell(spellId):getCastTime() == 5500 and iroha:getMerit(xi.merit.CURE_CAST_TIME) == 20)
            assert(iroha:getMod(xi.mod.FASTCAST) == 0 and iroha:getMod(xi.mod.UFASTCAST) == 0)
            iroha:setMod(xi.mod.REFRESH, 0)
            iroha:setMod(xi.mod.CURE2MP_PERCENT, 0)
            iroha:setMod(xi.mod.CURE_CAST_TIME, withMerit and 0 or -20)
            owner:setHP(owner:getMaxHP() - 500)
            local hp = owner:getHP()
            local mp = iroha:getMP()
            local started, finished
            iroha:addListener('MAGIC_START', 'IROHA_MERIT_CURE_START', function(actor, recipient, spell)
                assert(not started and actor:getID() == iroha:getID() and recipient:getID() == owner:getID() and spell:getID() == spellId)
                started = xi.test.world:getSteadyTime()
            end)

            iroha:addListener('MAGIC_USE', 'IROHA_MERIT_CURE_FINISH', function(actor, recipient, spell, action)
                assert(not finished and actor:getID() == iroha:getID() and recipient:getID() == owner:getID() and spell:getID() == spellId)
                assert(action:getCategory() == xi.action.category.MAGIC_FINISH)
                finished =
                {
                    time = xi.test.world:getSteadyTime(),
                    restored = action:getParam(recipient:getID()),
                    recast = action:getRecast(),
                }
            end)

            local function assertPending(checkpoint)
                assert(not finished, checkpoint .. ': Curaga V completed too soon')
                assert(owner:getHP() == hp, checkpoint .. ': recipient HP changed before completion')
                assert(iroha:getMP() == mp, checkpoint .. ': caster MP changed before completion')
            end

            assert(owner.actions:useTrustSpell(iroha, owner, spellId))
            xi.test.world:tickEntity(iroha)
            assert(started)

            -- skipTime also ticks the zone, advancing the simulated clock by
            -- another 400ms. Observe near 3.4s, 4.8s and, for the control, 6.2s.
            xi.test.world:skipTime(3)
            local early = xi.test.world:getSteadyTime() - started
            assert(early >= 3.4 and early < 4.4, string.format('early checkpoint outside cast window: %.3fs', early))
            assertPending('early checkpoint')

            xi.test.world:skipTime(1)
            local middle = xi.test.world:getSteadyTime() - started
            assert(middle > 4.4 and middle < 5.5, string.format('middle checkpoint outside cast window: %.3fs', middle))
            if withMerit then
                assert(finished, 'Curaga V with the merit must finish at the middle checkpoint')
            else
                assertPending('middle checkpoint without the merit effect')
                xi.test.world:skipTime(1)
            end

            iroha:removeListener('IROHA_MERIT_CURE_START')
            iroha:removeListener('IROHA_MERIT_CURE_FINISH')
            local completion = assert(finished, 'native Curaga V must complete')
            local elapsed = completion.time - started
            local lower = withMerit and 4.4 or 5.5
            local upper = withMerit and 5.5 or 7.0
            assert(elapsed > lower and elapsed < upper, string.format('completion outside cast window: %.3fs', elapsed))
            assert(completion.restored > 0 and owner:getHP() - hp == completion.restored, 'the primary recipient HP must match the native action')
            assert(iroha:getMP() == mp - 380, 'Curaga V must spend exactly 380 MP')
            assert(completion.recast == 11 and iroha:hasRecast(xi.recast.MAGIC, spellId), 'Curaga V must record and start its 11s recast')
        end)
    end
end)
