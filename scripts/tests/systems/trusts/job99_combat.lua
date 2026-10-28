-----------------------------------
-- Native developed-Trust combat consumers, not only entitlement getters.
-- Requires the isolated engine. Numerical retail interpretation is documented separately.
-----------------------------------
describe('Valaineral native combat consumers', function()
    local owner
    local val
    local mob
    local dummyId

    local function fixedContact()
        stub('xi.combat.physicalHitRate.getPhysicalHitRate', 1)
        stub('xi.combat.physical.isParried', false)
        stub('xi.combat.physical.isGuarded', false)
        stub('xi.combat.physical.isBlocked', false)
    end

    local function advance(entity, count)
        for _ = 1, count do
            xi.test.world:tickEntity(entity)
            xi.test.world:skipTime(5)
        end
    end

    before_each(function()
        xi.test.world:setSetting('main.TRUST_JOB99_VALAINERAL', true)
        xi.test.world:setSetting('main.ENABLE_TRUST_ALTER_EGO_POINT_BONUSES', false)
        xi.test.world:setSetting('main.ENABLE_TRUST_UNITY_RANK_STAT_PARITY', false)
        xi.test.world:setSetting('map.ALTER_EGO_SKILL_MULTIPLIER', 1)
        xi.test.world:setSetting('map.ENABLE_AUTO_ATTACK_LUA', false)
        xi.test.world:setSeed(123456)
        owner = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE, job = xi.job.PLD, level = 99 })
        owner.actions:setAutoAttackEnabled(false)
        owner:setUnkillable(true)
        val = owner:spawnTrust(xi.magic.spell.VALAINERAL)
        assert(val)
        val:removeAllGambits()
        val:setUnkillable(true)
        val:setAutoAttackEnabled(false)
        val:setMobAbilityEnabled(false)
        val:setMobMod(xi.mobMod.NO_MOVE, 1)
        mob = owner:getZone():insertDynamicEntity({
            objtype              = xi.objType.MOB,
            name                 = 'Job99_Combat',
            groupId              = 5,
            groupZoneId          = 154,
            minLevel             = 99,
            maxLevel             = 99,
            respawn              = 0,
            releaseIdOnDisappear = true,
        })
        assert(mob)
        dummyId = mob:getID()
        SpawnMob(dummyId)
        mob:setMaxHP(1000000)
        mob:setHP(1000000)
        mob:setUnkillable(true)
        mob:setAutoAttackEnabled(false)
        mob:setMagicCastingEnabled(false)
        mob:setMobAbilityEnabled(false)
        mob:setMobMod(xi.mobMod.NO_MOVE, 1)
        mob:setDropID(0)
        local x, y, z = owner:getXPos(), owner:getYPos(), owner:getZPos()
        mob:setPos(x, y, z)
        val:setPos(x, y, z + 1)
        local visible = owner.entities:moveTo(mob) -- Refresh native spawn lists.
        assert(visible and visible:getID() == mob:getID())
        owner:setPos(x, y, z + 2.5)
        owner.actions:engage(mob)
        val:engage(mob:getTargID())
    end)

    after_each(function()
        if dummyId and GetEntityByID(dummyId, nil, true) then
            DespawnMob(dummyId)
            for _ = 1, 10 do
                xi.test.world:tick()
                if GetEntityByID(dummyId, nil, true) == nil then
                    break
                end
            end

            assert(GetEntityByID(dummyId, nil, true) == nil)
        end

        dummyId = nil
    end)

    local function sentinelFlash(withEmblem)
        stub('xi.combat.magicHitRate.calculateResistRate', 1)
        owner.actions:engage(mob)
        assert(owner.actions:useTrustAbility(val, val, xi.jobAbility.SENTINEL))
        xi.test.world:tickEntity(val)
        xi.test.world:skipTime(3)
        assert(val:getStatusEffect(xi.effect.SENTINEL):getSubPower() == 95)
        if withEmblem then
            assert(owner.actions:useTrustAbility(val, val, xi.jobAbility.DIVINE_EMBLEM))
            xi.test.world:tickEntity(val)
            xi.test.world:skipTime(3)
        end

        mob:addBaseEnmity(val)
        mob:setCE(val, 0)
        mob:setVE(val, 0)
        assert(owner.actions:useTrustSpell(val, mob, xi.magic.spell.FLASH))
        xi.test.world:tickEntity(val)
        xi.test.world:skipTime(2)
        return mob:getCE(val)
    end

    it('adds Invincible action points to static CE once and preserves native VE', function()
        mob:updateClaim(owner)
        -- Native in-range JA enmity requires a prior damaging participant.
        mob:updateEnmityFromDamage(val, 1)
        mob:setCE(val, 0)
        mob:setVE(val, 0)
        assert(owner.actions:useTrustAbility(val, val, xi.jobAbility.INVINCIBLE))
        xi.test.world:tickEntity(val)
        xi.test.world:skipTime(1)
        assert(mob:getCE(val) == 2501, '(native1 CE plus2000 JP) times native1.25 ordinary bonus, once')
        local ve = mob:getVE(val)
        assert(ve <= 9000 and ve >= 8800, 'native7200 VE times1.25 may decay; JP must not add volatile enmity')
    end)

    it('generates432 CE from native Flash with Sentinel action points', function()
        assert(sentinelFlash(false) == 432, '180 CE times capped ordinary2 times special1.2')
    end)

    it('generates612 CE with additive Sentinel and Divine Emblem special bonuses', function()
        assert(sentinelFlash(true) == 612, '180 CE times capped ordinary2 times additive special1.7')
        assert(not val:hasStatusEffect(xi.effect.DIVINE_EMBLEM), 'the native divine cast must consume Divine Emblem')
    end)

    it('binds divine damage enmity to the actual cast and excludes counter or invalid spell inputs', function()
        owner.actions:engage(mob)
        assert(owner.actions:useTrustAbility(val, val, xi.jobAbility.SENTINEL))
        xi.test.world:tickEntity(val)
        xi.test.world:skipTime(3)
        assert(owner.actions:useTrustAbility(val, val, xi.jobAbility.DIVINE_EMBLEM))
        xi.test.world:tickEntity(val)
        xi.test.world:skipTime(3)
        mob:addBaseEnmity(val)
        mob:setCE(val, 0)
        mob:setVE(val, 0)
        local original = xi.spells.damage.useDamageSpell
        local observed
        stub('xi.spells.damage.useDamageSpell', function(caster, recipient, spell)
            local dealt = original(caster, recipient, spell)
            assert(dealt > 0)
            observed = { damage = dealt, actualCE = recipient:getCE(caster) }
            recipient:setCE(caster, 0)
            recipient:updateEnmityFromDamage(caster, dealt)
            observed.counterCE = recipient:getCE(caster)
            recipient:setCE(caster, 0)
            recipient:updateEnmityFromDamage(caster, dealt, {})
            observed.invalidCE = recipient:getCE(caster)
            recipient:setCE(caster, observed.actualCE)

            return dealt
        end)

        assert(owner.actions:useTrustSpell(val, mob, xi.magic.spell.HOLY_II))
        xi.test.world:tickEntity(val)
        xi.test.world:skipTime(5)
        assert(observed and observed.damage > 0, 'an actual native divine cast must dispatch and deal damage')
        assert(observed.actualCE > observed.counterCE,
            'actual divine damage must include the native Divine Emblem term')
        assert(observed.counterCE == observed.invalidCE,
            'missing or invalid spell input must not inherit the active cast')
        assert(math.abs(observed.actualCE * 12 - observed.counterCE * 17) <= 17,
            'Sentinel-only2.4 and additive divine3.4 use the same damage-derived base CE')
        assert(mob:getCE(val) == observed.actualCE)
        assert(not val:hasStatusEffect(xi.effect.DIVINE_EMBLEM))
    end)

    it('does not apply Divine Emblem special enmity to an ordinary job ability', function()
        owner.actions:engage(mob)
        assert(owner.actions:useTrustAbility(val, val, xi.jobAbility.SENTINEL))
        xi.test.world:tickEntity(val)
        xi.test.world:skipTime(3)
        assert(owner.actions:useTrustAbility(val, val, xi.jobAbility.DIVINE_EMBLEM))
        xi.test.world:tickEntity(val)
        xi.test.world:skipTime(3)
        mob:addBaseEnmity(val)
        mob:setCE(val, 0)
        mob:setVE(val, 0)
        assert(owner.actions:useTrustAbility(val, mob, xi.jobAbility.PROVOKE))
        xi.test.world:tickEntity(val)
        xi.test.world:skipTime(1)
        assert(mob:getCE(val) == 2, 'ordinary JA gets Sentinel1.2 only, not Divine Emblem1.5')
        assert(val:hasStatusEffect(xi.effect.DIVINE_EMBLEM))
    end)

    it('removes Sentinel action enmity and keeps Guardian loss reduction separate', function()
        fixedContact()
        stub('xi.combat.physical.calculateMeleePDIF', 1)
        assert(sentinelFlash(false) == 432)
        assert(val:getMod(xi.mod.ENMITY_LOSS_REDUCTION) == 95)
        mob:setDamage(1000, xi.slot.MAIN)
        mob:updateEnmity(val)
        mob:setCE(val, 10000)
        mob:setVE(val, 0)
        mob:setAutoAttackEnabled(true)
        advance(mob, 1)
        assert(mob:getCE(val) < 10000, 'Guardian95 must reduce incoming loss, not incorrectly erase it at115')
        assert(mob:getCE(val) > 9900, 'the incoming loss must retain Guardian protection')
        mob:setAutoAttackEnabled(false)
        xi.test.world:skipTime(50)
        assert(not val:hasStatusEffect(xi.effect.SENTINEL))
        assert(val:getMod(xi.mod.ENMITY_LOSS_REDUCTION) == 0)
        mob:setCE(val, 0)
        mob:setVE(val, 0)
        assert(owner.actions:useTrustSpell(val, mob, xi.magic.spell.FLASH))
        xi.test.world:tickEntity(val)
        xi.test.world:skipTime(2)
        assert(mob:getCE(val) == 225, 'expired Sentinel must leave only Valaineral native25 ordinary enmity')
    end)

    it('removes Mighty Strikes snapshotted action points after approval changes', function()
        local accuracy = val:getMod(xi.mod.ACC)
        local rangedAccuracy = val:getMod(xi.mod.RACC)
        local critical = val:getMod(xi.mod.CRITHITRATE)
        val:addStatusEffect(xi.effect.MIGHTY_STRIKES, { power = 1, duration = 1, origin = val })
        assert(val:getMod(xi.mod.ACC) == accuracy + 40)
        assert(val:getMod(xi.mod.RACC) == rangedAccuracy + 40)
        xi.test.world:setSetting('main.TRUST_JOB99_VALAINERAL', false)
        xi.test.world:skipTime(2)
        assert(val:getMod(xi.mod.ACC) == accuracy)
        assert(val:getMod(xi.mod.RACC) == rangedAccuracy)
        assert(val:getMod(xi.mod.CRITHITRATE) == critical)
    end)

    it('decays Brazen Rush and removes its snapshotted points after approval changes', function()
        local attack = val:getMod(xi.mod.ATT)
        local double = val:getMod(xi.mod.DOUBLE_ATTACK)
        val:addStatusEffect(xi.effect.BRAZEN_RUSH, { power = 100, duration = 8, tick = 3, origin = val })
        assert(val:getMod(xi.mod.ATT) == attack + 80)
        assert(val:getMod(xi.mod.DOUBLE_ATTACK) == double + 100)
        xi.test.world:skipTime(4)
        assert(val:getMod(xi.mod.DOUBLE_ATTACK) == double + 90)
        xi.test.world:setSetting('main.TRUST_JOB99_VALAINERAL', false)
        xi.test.world:skipTime(5)
        assert(val:getMod(xi.mod.ATT) == attack)
        assert(val:getMod(xi.mod.DOUBLE_ATTACK) == double)
    end)

    it('redirects real incoming melee to the approved Cover protector and stops at expiration', function()
        fixedContact()
        stub('xi.combat.physical.calculateMeleePDIF', 1)
        assert(owner.actions:useTrustAbility(val, owner, xi.jobAbility.COVER))
        xi.test.world:tickEntity(val)
        xi.test.world:skipTime(3)
        assert(val:hasStatusEffect(xi.effect.COVER))
        local ownerHP, valHP = owner:getHP(), val:getHP()
        mob:setAutoAttackEnabled(true)
        mob:updateEnmity(owner)
        advance(mob, 2)
        assert(owner:getHP() == ownerHP, 'the protected PC must avoid the covered melee damage')
        assert(val:getHP() < valHP, 'native incoming melee must damage the Trust protector')
        assert(not val:isDead())
        val:delStatusEffect(xi.effect.COVER)
        ownerHP = owner:getHP()
        advance(mob, 2)
        assert(owner:getHP() < ownerHP, 'expired Cover must restore the original melee recipient')
    end)

    it('covers a same-party Trust recipient through real melee and restores it after expiration', function()
        fixedContact()
        stub('xi.combat.physical.calculateMeleePDIF', 1)
        local protected = owner:spawnTrust(xi.magic.spell.SHANTOTTO)
        assert(protected)
        protected:removeAllGambits()
        protected:setAutoAttackEnabled(false)
        protected:setMobAbilityEnabled(false)
        protected:setUnkillable(true)
        protected:setMobMod(xi.mobMod.NO_MOVE, 1)
        protected:setPos(owner:getXPos(), owner:getYPos(), owner:getZPos())
        assert(owner.actions:useTrustAbility(val, protected, xi.jobAbility.COVER),
            'native party admission must permit this recipient')
        xi.test.world:tickEntity(val)
        xi.test.world:skipTime(3)
        assert(val:hasStatusEffect(xi.effect.COVER))
        local protectedHP, valHP = protected:getHP(), val:getHP()
        mob:setAutoAttackEnabled(true)
        mob:updateEnmity(protected)
        advance(mob, 2)
        assert(protected:getHP() == protectedHP)
        assert(val:getHP() < valHP, 'native melee must find the approved Trust protector for a Trust recipient')
        val:delStatusEffect(xi.effect.COVER)
        protectedHP = protected:getHP()
        advance(mob, 2)
        assert(protected:getHP() < protectedHP, 'expired Cover must restore the Trust recipient')
    end)

    it('forwards conditional Double Attack JP and the actual Sword type through native swings', function()
        fixedContact()
        local observations = {}
        stub('xi.combat.physical.calculateMeleePDIF', function(actor, _target, weapon, ...)
            local tail = { ... }
            if actor:getID() == val:getID() then
                table.insert(observations, { weapon = weapon, bonus = tail[9] or 0 })
            end

            return 1
        end)

        val:setMod(xi.mod.DOUBLE_ATTACK, 0)
        val:setMod(xi.mod.TRIPLE_ATTACK, 0)
        val:setMod(xi.mod.QUAD_ATTACK, 0)
        local attack = val:getStat(xi.mod.ATT)
        owner.actions:engage(mob)
        val:setAutoAttackEnabled(true)
        val:engage(mob:getTargID())
        advance(val, 2)
        val:setMod(xi.mod.DOUBLE_ATTACK, 100)
        advance(val, 2)
        local normal, double = false, false
        for _, observation in ipairs(observations) do
            assert(observation.weapon == xi.skill.SWORD)
            assert(observation.bonus == 0 or observation.bonus == 20)
            normal = normal or observation.bonus == 0
            double = double or observation.bonus == 20
        end

        assert(normal and double, 'native base and Double Attack swings must use different flat JP inputs')
        assert(val:getStat(xi.mod.ATT) == attack, 'conditional attack must never leak into actor stats')
        assert(mob:getHP() < mob:getMaxHP(), 'native swing completion must apply real damage')
    end)

    it('adds flat conditional attack before the existing pDIF percentage without changing actor stats', function()
        local ratios = {}
        stub('xi.combat.physical.wRatioCapOthers', function(ratio, _cap)
            table.insert(ratios, ratio)
            return 1, 1
        end)

        local attack = val:getStat(xi.mod.ATT)
        xi.combat.physical.calculateMeleePDIF(
            val, mob, xi.skill.SWORD, 1, false, false, false, 0, false, xi.slot.MAIN, false)
        xi.combat.physical.calculateMeleePDIF(
            val, mob, xi.skill.SWORD, 1, false, false, false, 0, false, xi.slot.MAIN, false, 20)
        assert(#ratios == 2)
        assert(math.abs((ratios[2] - ratios[1]) * mob:getStat(xi.mod.DEF) - 20) < 0.0001)
        assert(val:getStat(xi.mod.ATT) == attack)
    end)

    it('applies the native first-swing Restraint JP acceleration', function()
        fixedContact()
        local swings = 0
        stub('xi.combat.physical.calculateMeleePDIF', function(actor, ...)
            if actor:getID() == val:getID() then
                swings = swings + 1
            end

            return 1
        end)

        val:setMod(xi.mod.DOUBLE_ATTACK, 0)
        val:setMod(xi.mod.TRIPLE_ATTACK, 0)
        val:setMod(xi.mod.QUAD_ATTACK, 0)
        val:addStatusEffect(xi.effect.RESTRAINT, { duration = 300, origin = val })
        owner.actions:engage(mob)
        val:setAutoAttackEnabled(true)
        val:engage(mob:getTargID())
        xi.test.world:tickEntity(val)
        xi.test.world:skipTime(4)
        assert(swings == 1, 'this fixture must observe exactly one native first swing')
        local effect = val:getStatusEffect(xi.effect.RESTRAINT)
        local accumulated = effect:getPower() * 100 + effect:getSubPower()
        local expected = val:getBaseDelay() / 385 * 1.4 * 100
        assert(math.abs(accumulated - expected) < 2, 'native Restraint must include the forty-percent JP acceleration')
    end)

    it('executes a real Trust Retaliation counter without normal swings or a player downcast', function()
        fixedContact()
        stub('xi.combat.physical.calculateMeleePDIF', 1)
        assert(owner.actions:useTrustAbility(val, val, xi.jobAbility.RETALIATION))
        xi.test.world:tickEntity(val)
        xi.test.world:skipTime(3)
        assert(val:hasStatusEffect(xi.effect.RETALIATION))
        owner.actions:engage(mob)
        val:engage(mob:getTargID())
        val:lookAt(mob:getPos()) -- Retaliation requires facing even with normal swings disabled.
        local enemyHP = mob:getHP()
        mob:setAutoAttackEnabled(true)
        mob:updateEnmity(val)
        advance(mob, 20)
        assert(mob:getHP() < enemyHP, 'only native Retaliation can damage this enemy while normal swings are disabled')
        assert(not val:isDead())
    end)
end)
