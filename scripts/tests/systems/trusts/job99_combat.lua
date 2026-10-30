-----------------------------------
-- Native developed-Trust combat consumers, not only entitlement getters.
-- Requires the isolated engine. Numerical retail interpretation is documented separately.
-----------------------------------
describe('Valaineral native combat consumers', function()
    local owner
    local val
    local mob
    local dummyId

    local function fixedContact(blocked)
        stub('xi.combat.physicalHitRate.getPhysicalHitRate', 1)
        stub('xi.combat.physical.isParried', false)
        stub('xi.combat.physical.isGuarded', false)
        stub('xi.combat.physical.isBlocked', blocked or false)
    end

    local function advance(entity, count)
        for _ = 1, count do
            xi.test.world:tickEntity(entity)
            xi.test.world:skipTime(5)
        end
    end

    local function engageOwnerFacingAway()
        local x, y, z = owner:getXPos(), owner:getYPos(), owner:getZPos()
        owner.actions:engage(mob)
        owner:setPos(x, y, z) -- The native engage helper moves the PC; restore the fixture's intended geometry.

        -- Native PC CanAttack ignores the controller flag; preserve range and Cover positions while blocking swings.
        owner:lookAt(2 * x - mob:getXPos(), y, 2 * z - mob:getZPos())
        assert(not owner:isFacing(mob), 'the engaged fixture owner must face away from the native target')
    end

    before_each(function()
        xi.test.world:setSetting('main.TRUST_JOB99_VALAINERAL', true)
        xi.test.world:setSetting('main.ENABLE_TRUST_ALTER_EGO_POINT_BONUSES', false)
        xi.test.world:setSetting('main.ENABLE_TRUST_UNITY_RANK_STAT_PARITY', false)
        xi.test.world:setSetting('map.ALTER_EGO_SKILL_MULTIPLIER', 1)
        xi.test.world:setSetting('map.ENABLE_AUTO_ATTACK_LUA', false)
        xi.test.world:setSeed(123456)
        owner = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE, job = xi.job.PLD, level = 99 })
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
        engageOwnerFacingAway()
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

    -- Keep native casting, swings, damage, interruption and MP spending. Only contact
    -- outcomes and fixture timing are controlled; no spell/effect handler is called directly.
    local function castUnderNativeHit(actor, recipient, spellId, blocked, ranged)
        local blockChecks = 0
        fixedContact(function(defender, attacker)
            if defender:getID() == actor:getID() and attacker:getID() == mob:getID() then
                blockChecks = blockChecks + 1
                return blocked
            end

            return false
        end)
        stub('xi.combat.physical.calculateMeleePDIF', 1)
        stub('xi.combat.physicalHitRate.getRangedHitRate', 1)
        stub('xi.combat.physical.calculateRangedPDIF', 1)

        actor:setAutoAttackEnabled(false)
        actor:setMod(xi.mod.FASTCAST, 0)
        actor:setMod(xi.mod.QUICK_MAGIC, 0)
        actor:setMod(xi.mod.REFRESH, 0)
        -- At equal levels the native ratio is .5 * 11 = 5.5: every unprotected
        -- melee hit interrupts, independently of the random roll in [0, 1).
        actor:setMod(xi.mod.SPELLINTERRUPT, -1000)
        actor:setMP(actor:getMaxMP())
        mob:setAutoAttackEnabled(false)
        mob:setRangedAttackEnabled(false)
        mob:setMobMod(xi.mobMod.SPECIAL_SKILL, 0)
        mob:setDamage(100, xi.slot.MAIN)
        mob:setDamage(100, xi.slot.RANGED)
        mob:setMod(xi.mod.DOUBLE_ATTACK, 0)
        mob:setMod(xi.mod.TRIPLE_ATTACK, 0)
        mob:setMod(xi.mod.QUAD_ATTACK, 0)
        mob:setMod(xi.mod.RANGED_DELAYP, -100)
        mob:addBaseEnmity(actor)
        mob:setCE(actor, 10000)
        mob:setVE(actor, 0)
        mob:updateEnmity(actor)
        xi.test.world:skipTime(10) -- Run down attack timers while every attack path is disabled.

        local started, completed, interrupted, rangedStarts = 0, 0, 0, 0
        actor:addListener('MAGIC_START', 'JOB99_SHIELD_START', function(_, _, spell)
            if spell:getID() == spellId then
                started = started + 1
            end
        end)
        actor:addListener('MAGIC_USE', 'JOB99_SHIELD_USE', function(_, _, spell)
            if spell:getID() == spellId then
                completed = completed + 1
            end
        end)
        actor:addListener('MAGIC_INTERRUPTED', 'JOB99_SHIELD_INTERRUPTED', function(_, _, spell)
            if spell:getID() == spellId then
                interrupted = interrupted + 1
            end
        end)
        mob:addListener('RANGE_START', 'JOB99_SHIELD_RANGED', function()
            rangedStarts = rangedStarts + 1
        end)

        local mpBefore, hpBefore = actor:getMP(), actor:getHP()
        if actor:getID() == owner:getID() then
            owner.actions:useSpell(recipient, spellId)
        else
            assert(owner.actions:useTrustSpell(actor, recipient, spellId), 'native cast admission must succeed')
        end

        assert(started == 1 and actor:getCurrentAction() == 30, 'the native spell must be casting before contact')
        mob:setAutoAttackEnabled(not ranged)
        mob:setRangedAttackEnabled(ranged)
        xi.test.world:tickEntity(mob)
        xi.test.world:skipTime(1)
        mob:setAutoAttackEnabled(false)
        mob:setRangedAttackEnabled(false)
        assert(actor:getHP() < hpBefore, 'a real native hit must damage the caster before its spell completes')
        assert(completed == 0, 'contact must occur inside the native cast window')
        if ranged then
            assert(rangedStarts > 0 and blockChecks == 0, 'only the native ranged attack path may deliver this hit')
        else
            assert(blockChecks > 0 and rangedStarts == 0, 'the native melee path must evaluate the selected block outcome')
        end

        xi.test.world:skipTime(5)
        actor:removeListener('JOB99_SHIELD_START')
        actor:removeListener('JOB99_SHIELD_USE')
        actor:removeListener('JOB99_SHIELD_INTERRUPTED')
        mob:removeListener('JOB99_SHIELD_RANGED')
        return { completed = completed, interrupted = interrupted, mpBefore = mpBefore, mpAfter = actor:getMP() }
    end

    it('preserves developed Shield Mastery casting through a real blocked melee hit', function()
        assert(val:hasTrait(xi.trait.SHIELD_MASTERY))
        local result = castUnderNativeHit(val, val, xi.magic.spell.CURE_IV, true, false)
        assert(result.completed == 1 and result.interrupted == 0)
        assert(result.mpAfter == result.mpBefore - 88, 'native CureIV must spend its actual MP cost once')
    end)

    it('still interrupts developed Shield Mastery casting on a real unblocked melee hit', function()
        assert(val:hasTrait(xi.trait.SHIELD_MASTERY))
        local result = castUnderNativeHit(val, val, xi.magic.spell.CURE_IV, false, false)
        assert(result.completed == 0 and result.interrupted == 1)
        assert(result.mpAfter == result.mpBefore, 'an interrupted spell must not spend MP')
    end)

    it('does not extend blocked-hit immunity after developed-Trust approval is disabled', function()
        xi.test.world:setSetting('main.TRUST_JOB99_VALAINERAL', false)
        assert(val:hasTrait(xi.trait.SHIELD_MASTERY))
        local result = castUnderNativeHit(val, val, xi.magic.spell.CURE_IV, true, false)
        assert(result.completed == 0 and result.interrupted == 1)
        assert(result.mpAfter == result.mpBefore)
    end)

    it('preserves PC Shield Mastery independently of the developed-Trust setting', function()
        xi.test.world:setSetting('main.TRUST_JOB99_VALAINERAL', false)
        owner:addSpell(xi.magic.spell.CURE_IV)
        assert(owner:hasTrait(xi.trait.SHIELD_MASTERY))
        local result = castUnderNativeHit(owner, owner, xi.magic.spell.CURE_IV, true, false)
        assert(result.completed == 1 and result.interrupted == 0)
        assert(result.mpAfter == result.mpBefore - 88)
    end)

    it('does not grant blocked-hit immunity to an unapproved Trust without Shield Mastery', function()
        local other = owner:spawnTrust(xi.magic.spell.SHANTOTTO)
        assert(other and not other:hasTrait(xi.trait.SHIELD_MASTERY))
        other:removeAllGambits()
        other:setUnkillable(true)
        other:setMobAbilityEnabled(false)
        other:setMobMod(xi.mobMod.NO_MOVE, 1)
        other:setPos(val:getPos())
        local result = castUnderNativeHit(other, mob, xi.magic.spell.STONE, true, false)
        assert(result.completed == 0 and result.interrupted == 1)
        assert(result.mpAfter == result.mpBefore)
    end)

    it('preserves the native ranged noninterruption rule with developed approval disabled', function()
        xi.test.world:setSetting('main.TRUST_JOB99_VALAINERAL', false)
        local result = castUnderNativeHit(val, val, xi.magic.spell.CURE_IV, false, true)
        assert(result.completed == 1 and result.interrupted == 0)
        assert(result.mpAfter == result.mpBefore - 88)
    end)

    local function sentinelFlash(withEmblem)
        stub('xi.combat.magicHitRate.calculateResistRate', 1)
        engageOwnerFacingAway()
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
        engageOwnerFacingAway()
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
        engageOwnerFacingAway()
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
        local hpBefore = val:getHP()
        mob:setAutoAttackEnabled(true)
        advance(mob, 1)
        local damage, ce = hpBefore - val:getHP(), mob:getCE(val)
        assert(damage > 0, string.format('Guardian fixture must take native incoming damage, got %d', damage))
        assert(ce < 10000, string.format('Guardian95 must reduce incoming CE loss: damage %d CE %d', damage, ce))
        assert(ce > 9900, string.format('incoming loss must retain Guardian protection: damage %d CE %d', damage, ce))
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
        local function assertCoverGeometry()
            local x, y, z    = mob:getXPos(), mob:getYPos(), mob:getZPos()
            local ox, oy, oz = owner:getXPos() - x, owner:getYPos() - y, owner:getZPos() - z
            local vx, vy, vz = val:getXPos() - x, val:getYPos() - y, val:getZPos() - z

            local ownerSquared = ox * ox + oy * oy + oz * oz
            local valSquared   = vx * vx + vy * vy + vz * vz
            local dot          = vx * ox + vy * oy + vz * oz
            local crossSquared = valSquared * ownerSquared - dot * dot
            local geometry     = string.format('owner2 %.6f Val2 %.6f dot %.6f cross2 %.6f', ownerSquared, valSquared, dot, crossSquared)

            assert(valSquared < ownerSquared, 'Cover protector must be strictly closer to the attacker: ' .. geometry)
            assert(dot > 0 and dot < ownerSquared and math.abs(crossSquared) < 0.0001,
                'Cover protector must be collinear and between attacker and owner: ' .. geometry)
        end

        fixedContact()
        stub('xi.combat.physical.calculateMeleePDIF', 1)
        assert(owner.actions:useTrustAbility(val, owner, xi.jobAbility.COVER))
        xi.test.world:tickEntity(val)
        xi.test.world:skipTime(3)
        assert(val:hasStatusEffect(xi.effect.COVER))
        assertCoverGeometry()
        local ownerHP, valHP = owner:getHP(), val:getHP()
        mob:setAutoAttackEnabled(true)
        -- Cover adds protector CE and lowers recipient hate; test redirection while the owner remains the actual target.
        mob:addBaseEnmity(owner)
        mob:setCE(owner, 10000)
        mob:setVE(owner, 0)
        mob:updateEnmity(owner)
        advance(mob, 2)
        local actualTarget = mob:getTarget()
        assert(actualTarget and actualTarget:getID() == owner:getID(),
            string.format('covered melee must target owner %d, got %d; owner CE %d Val CE %d',
                owner:getID(), actualTarget and actualTarget:getID() or 0, mob:getCE(owner), mob:getCE(val)))
        assert(owner:getHP() == ownerHP,
            string.format('covered owner HP must remain %d, got %d; Val HP %d/%d', ownerHP, owner:getHP(), val:getHP(), valHP))
        assert(val:getHP() < valHP,
            string.format('native Cover must damage Val: HP %d/%d owner %d/%d', val:getHP(), valHP, owner:getHP(), ownerHP))
        assert(not val:isDead())
        val:delStatusEffect(xi.effect.COVER)
        assertCoverGeometry()
        ownerHP = owner:getHP()
        -- Compare expiration against the same native hostile target, rather than inherited Cover enmity.
        mob:addBaseEnmity(owner)
        mob:setCE(owner, 10000)
        mob:setVE(owner, 0)
        mob:updateEnmity(owner)
        advance(mob, 2)
        actualTarget = mob:getTarget()
        assert(actualTarget and actualTarget:getID() == owner:getID(),
            string.format('expired Cover melee must target owner %d, got %d; owner CE %d Val CE %d',
                owner:getID(), actualTarget and actualTarget:getID() or 0, mob:getCE(owner), mob:getCE(val)))
        assert(owner:getHP() < ownerHP,
            string.format('expired Cover must damage owner: HP %d/%d Val %d', owner:getHP(), ownerHP, val:getHP()))
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
        mob:addBaseEnmity(protected)
        mob:setCE(protected, 10000)
        mob:setVE(protected, 0)
        mob:updateEnmity(protected)
        advance(mob, 2)
        local actualTarget = mob:getTarget()
        assert(actualTarget and actualTarget:getID() == protected:getID(), 'native enmity must retain the intended covered Trust target')
        assert(protected:getHP() == protectedHP,
            string.format('covered Trust HP must remain %d, got %d', protectedHP, protected:getHP()))
        assert(val:getHP() < valHP,
            string.format('native Cover must damage Val: HP %d/%d protected %d/%d', val:getHP(), valHP, protected:getHP(), protectedHP))
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
        engageOwnerFacingAway()
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
        local ratios     = {}
        local spikeRolls = 0
        local randomInt  = math.randomInt

        -- Exercise the ratio path instead of the native random spike early return.
        stub('math.randomInt', function(minimum, maximum)
            if minimum == 1 and maximum == 10000 then
                spikeRolls = spikeRolls + 1
                return 10000
            end

            return randomInt(minimum, maximum)
        end)

        stub('xi.combat.physical.wRatioCapOthers', function(ratio, _cap)
            table.insert(ratios, ratio)
            return 1, 1
        end)

        local attack = val:getStat(xi.mod.ATT)
        xi.combat.physical.calculateMeleePDIF(
            val, mob, xi.skill.SWORD, 1, false, false, false, 0, false, xi.slot.MAIN, false)
        xi.combat.physical.calculateMeleePDIF(
            val, mob, xi.skill.SWORD, 1, false, false, false, 0, false, xi.slot.MAIN, false, 20)
        assert(spikeRolls == 2, string.format('two pDIF calls must make exactly two spike decisions, got %d', spikeRolls))
        assert(#ratios == 2, string.format('two non-spike pDIF calls must reach the ratio hook, got %d', #ratios))
        local defense       = mob:getStat(xi.mod.DEF)
        local impliedAttack = (ratios[2] - ratios[1]) * defense
        assert(math.abs(impliedAttack - 20) < 0.0001,
            string.format('flat20 attack: ratios %.9f/%.9f DEF %d implied %.9f', ratios[1], ratios[2], defense, impliedAttack))
        assert(val:getStat(xi.mod.ATT) == attack,
            string.format('conditional attack must leave native ATT %d unchanged, got %d', attack, val:getStat(xi.mod.ATT)))
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
        engageOwnerFacingAway()
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
        engageOwnerFacingAway()
        val:engage(mob:getTargID())
        val:lookAt(mob:getPos()) -- Retaliation requires facing even with normal swings disabled.
        local enemyHP = mob:getHP()
        local valHP = val:getHP()
        mob:setAutoAttackEnabled(true)
        mob:addBaseEnmity(val)
        mob:setCE(val, 10000)
        mob:setVE(val, 0)
        mob:updateEnmity(val)
        advance(mob, 20)
        local actualTarget = mob:getTarget()
        assert(actualTarget and actualTarget:getID() == val:getID(), 'the native attacker must target the retaliating Trust')
        assert(val:getHP() < valHP, string.format('Retaliation fixture must take incoming damage: HP %d/%d', val:getHP(), valHP))
        assert(mob:getHP() < enemyHP,
            string.format('only native Retaliation can damage this enemy: HP %d/%d Val %d/%d', mob:getHP(), enemyHP, val:getHP(), valHP))
        assert(not val:isDead())
    end)
end)
