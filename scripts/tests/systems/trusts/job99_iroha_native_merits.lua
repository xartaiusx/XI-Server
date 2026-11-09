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

    local function legSweep(owner, iroha, front)
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
            assert(skill:getID() == xi.weaponskill.LEG_SWEEP and spent == 1000 and damage > 0)
            assert(actor:isInfront(recipient) == front, 'the native action must retain the selected facing')
            result = { damage = damage, tp = actor:getTP() }
        end)

        xi.test.world:setSeed(123456)
        iroha:setTP(1000)
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

            iroha:addListener('MAGIC_USE', 'IROHA_MERIT_CURE_FINISH', function(actor, recipient, spell)
                assert(not finished and actor:getID() == iroha:getID() and recipient:getID() == owner:getID() and spell:getID() == spellId)
                finished = xi.test.world:getSteadyTime()
            end)

            assert(owner.actions:useTrustSpell(iroha, owner, spellId))
            xi.test.world:tickEntity(iroha)
            assert(started)
            xi.test.world:skipTime(4)
            assert(not finished and owner:getHP() == hp and iroha:getMP() == mp)
            xi.test.world:skipTime(1)
            if not withMerit then
                assert(not finished and owner:getHP() == hp and iroha:getMP() == mp)
                xi.test.world:skipTime(1)
            end

            iroha:removeListener('IROHA_MERIT_CURE_START')
            iroha:removeListener('IROHA_MERIT_CURE_FINISH')
            local elapsed = assert(finished, 'native Curaga V must complete') - started
            assert(withMerit and elapsed >= 4 and elapsed < 5.5 or not withMerit and elapsed >= 5.5)
            assert(owner:getHP() > hp and iroha:getMP() == mp - 380 and iroha:hasRecast(xi.recast.MAGIC, spellId))
        end)
    end
end)
