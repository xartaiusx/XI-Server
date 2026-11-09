-----------------------------------
-- Exercise ordinary native action resolution with Twills and two owned Trusts.
-----------------------------------
describe('Ordinary Trust engagement', function()
    local owner
    local val
    local iroha
    local targets

    local function fixtureMob(name, dx)
        local mob = owner:getZone():insertDynamicEntity({
            objtype              = xi.objType.MOB,
            name                 = name,
            groupId              = 5,
            groupZoneId          = 154,
            minLevel             = 99,
            maxLevel             = 99,
            respawn              = 0,
            releaseIdOnDisappear = true,
        })
        assert(mob)
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
        mob:setDropID(0)
        local x, y, z = owner:getXPos(), owner:getYPos(), owner:getZPos()
        mob:setPos(x + dx, y, z + 2)
        assert(owner.entities:moveTo(mob))
        owner:setPos(x, y, z)
        return mob
    end

    local function onTarget(trust, mob)
        local target = trust:getTarget()
        return trust:isEngaged() and target and target:getID() == mob:getID()
    end

    local function playerSpell(target, spell, rejected)
        local started = false
        local completed = false
        owner:addListener('MAGIC_START', 'ORDINARY_TRUST_CAST_START', function(_, recipient, actionSpell)
            started = recipient:getID() == target:getID() and actionSpell:getID() == spell
        end)

        owner:addListener('MAGIC_USE', 'ORDINARY_TRUST_CAST_FINISH', function(_, recipient, actionSpell)
            completed = recipient:getID() == target:getID() and actionSpell:getID() == spell
        end)

        owner.actions:useSpell(target, spell)
        xi.test.world:tickEntity(owner)
        xi.test.world:skipTime(8)
        -- Trusts tick before PCs. Give them the completed event and let the owner's 2.5-second action lock expire.
        xi.test.world:skipTime(3)

        owner:removeListener('ORDINARY_TRUST_CAST_START')
        owner:removeListener('ORDINARY_TRUST_CAST_FINISH')
        if rejected then
            assert(not started and not completed, 'the rejected spell cannot start or complete')
        else
            assert(started, 'the requested spell must start on its exact recipient')
            assert(completed, 'the requested spell must complete on its exact recipient')
        end
    end

    before_each(function()
        xi.test.world:setSetting('main.ENABLE_MOCHIRII_TWILLS_TRUST_GAMEPLAY', true)
        xi.test.world:setSetting('main.ENABLE_MOCHIRII_TWILLS_FULL_ALLIANCE', true)
        xi.test.world:setSetting('main.MOCHIRII_TWILLS_FULL_ALLIANCE_MAX_PARTIES', 3)
        xi.test.world:setSetting('main.ENABLE_TRUST_SHARED_TARGETING', true)
        xi.test.world:setSetting('main.ENABLE_TRUST_DEFENSIVE_MODE', true)
        xi.test.world:setSetting('main.TRUST_JOB99_VALAINERAL', true)
        xi.test.world:setSetting('main.TRUST_JOB99_IROHA_II', true)
        xi.test.world:setSeed(123456)

        owner = xi.test.world:spawnPlayer({ name = 'Twills', zone = xi.zone.WEST_RONFAURE, job = xi.job.RDM, level = 99 })
        owner:setGMLevel(5)
        owner:setVisibleGMLevel(0)
        owner:setCharVar('MochiriiTrustAllianceAccess', 1)
        assert(owner.actions:prepareSoloTrustParty())
        assert(owner:canUseTwillsTrustGameplay())
        owner:setUnkillable(true)
        for _, spell in ipairs({ xi.magic.spell.CURE, xi.magic.spell.DIA, xi.magic.spell.PARALYZE, xi.magic.spell.STONE }) do
            owner:addSpell(spell)
        end

        val = owner:spawnTrust(xi.magic.spell.VALAINERAL)
        iroha = owner:spawnTrust(xi.magic.spell.IROHA_II)
        assert(val and iroha and #owner:getPartyWithTrusts() == 3)
        local x, y, z = owner:getXPos(), owner:getYPos(), owner:getZPos()
        for index, trust in ipairs({ val, iroha }) do
            trust:removeAllGambits()
            trust:setAutoAttackEnabled(false)
            trust:setMobAbilityEnabled(false)
            trust:setPos(x + index * 0.5, y, z)
        end

        targets = {}
    end)

    after_each(function()
        for _, id in ipairs(targets or {}) do
            if GetEntityByID(id, nil, true) then
                DespawnMob(id)
            end
        end

        for _ = 1, 10 do
            xi.test.world:tick()
        end

        for _, id in ipairs(targets or {}) do
            assert(not GetEntityByID(id, nil, true), 'retire the exact synthetic attacker')
        end
    end)

    it('focuses on completed spells and switches without an owner melee swing', function()
        local first = fixtureMob('Ordinary_Trust_First', 0)
        local second = fixtureMob('Ordinary_Trust_Second', 2)
        local hp = owner:getMaxHP() - 100
        owner:setHP(hp)
        playerSpell(owner, xi.magic.spell.CURE)
        assert(owner:getHP() > hp, 'the friendly spell must actually resolve')
        assert(not val:isEngaged() and not iroha:isEngaged(), 'a friendly completion cannot pull')

        playerSpell(first, xi.magic.spell.PARALYZE)
        assert(not owner:isEngaged() and onTarget(val, first) and onTarget(iroha, first))

        assert(iroha:getMP() >= GetSpell(xi.magic.spell.IMPACT):getMPCost())
        for _, spell in ipairs({ xi.magic.spell.DIAGA_II, xi.magic.spell.DISPELGA, xi.magic.spell.IMPACT }) do
            assert(not owner.actions:hasTrustSpell(iroha, spell), string.format('spell %d is outside the job catalog', spell))
            assert(not owner.actions:useTrustSpell(iroha, first, spell), string.format('spell %d fails native admission', spell))
        end

        playerSpell(second, xi.magic.spell.DIA)
        assert(not owner:isEngaged() and onTarget(val, second) and onTarget(iroha, second))
    end)

    it('follows completed melee and spell actions without following stale melee intent', function()
        local first = fixtureMob('Ordinary_Trust_Melee', 0)
        local second = fixtureMob('Ordinary_Trust_Spell', 2)
        owner.actions:engage(first)
        for _ = 1, 8 do
            xi.test.world:skipTime(2)
            if onTarget(val, first) and onTarget(iroha, first) then
                break
            end
        end

        assert(onTarget(val, first) and onTarget(iroha, first), 'a resolved melee round selects its recipient')
        local x, y, z = owner:getXPos(), owner:getYPos(), owner:getZPos()
        owner:setPos(first:getXPos(), y, first:getZPos() - 8)
        owner:lookAt(second:getXPos(), second:getYPos(), second:getZPos())
        playerSpell(second, xi.magic.spell.DIA)
        assert(owner:isEngaged() and owner:getTarget():getID() == first:getID())
        assert(onTarget(val, second) and onTarget(iroha, second), 'old melee target cannot beat a later spell')

        playerSpell(first, xi.magic.spell.FIRE_VI, true)
        assert(onTarget(val, second) and onTarget(iroha, second), 'a rejected spell cannot change focus')

        owner:setPos(x, y, z)
        owner:lookAt(first:getXPos(), first:getYPos(), first:getZPos())
        for _ = 1, 8 do
            xi.test.world:skipTime(2)
            if onTarget(val, first) and onTarget(iroha, first) then
                break
            end
        end

        assert(onTarget(val, first) and onTarget(iroha, first), 'the next resolved melee round becomes latest')
    end)

    it('retaliates when a mob lands a native attack on Iroha with Twills idle', function()
        local mob = fixtureMob('Ordinary_Trust_Attacker', 1)
        local startingHp = iroha:getHP()
        stub('xi.combat.physicalHitRate.getPhysicalHitRate', 1)
        stub('xi.combat.physical.isParried', false)
        stub('xi.combat.physical.isGuarded', false)
        stub('xi.combat.physical.isBlocked', false)
        mob:setDamage(20, xi.slot.MAIN)
        mob:setAutoAttackEnabled(true)
        mob:addBaseEnmity(iroha)
        mob:setCE(iroha, 10000)
        mob:updateEnmity(iroha)
        for _ = 1, 6 do
            xi.test.world:skipTime(2)
        end

        assert(iroha:getHP() < startingHp, 'a real mob swing must reach the Trust')
        assert(not owner:isEngaged() and onTarget(val, mob) and onTarget(iroha, mob))
    end)

    it('rejects a queued hostile effect when its target is put to sleep', function()
        local mob = fixtureMob('Ordinary_Trust_Queued', 0)
        playerSpell(mob, xi.magic.spell.PARALYZE)
        assert(onTarget(val, mob))
        local targetId = mob:getID()
        local spellId = xi.magic.spell.HOLY_II
        local started = false
        local completed = false
        local retired = false
        val:addListener('MAGIC_START', 'ORDINARY_TRUST_QUEUED_START', function(_, target, spell)
            started = target:getID() == targetId and spell:getID() == spellId
        end)

        val:addListener('MAGIC_USE', 'ORDINARY_TRUST_QUEUED_FINISH', function(_, target, spell)
            completed = target:getID() == targetId and spell:getID() == spellId
        end)

        val:addListener('MAGIC_STATE_EXIT', 'ORDINARY_TRUST_QUEUED_EXIT', function(_, spell)
            retired = spell:getID() == spellId
        end)

        local startingHp = mob:getHP()
        local startingMp = val:getMP()
        assert(owner.actions:useTrustSpell(val, mob, spellId))
        assert(started, 'Holy II must enter the native cast state before Sleep is applied')
        assert(mob:addStatusEffect(xi.effect.SLEEP_I, { power = 1, duration = 60, origin = owner }))
        xi.test.world:skipTime(8)
        xi.test.world:tickEntity(val)
        val:removeListener('ORDINARY_TRUST_QUEUED_START')
        val:removeListener('ORDINARY_TRUST_QUEUED_FINISH')
        val:removeListener('ORDINARY_TRUST_QUEUED_EXIT')

        assert(retired, 'the exact queued cast must leave its native state')
        assert(not completed and val:getMP() == startingMp, 'protected Sleep cancels the cast before completion or MP cost')
        assert(mob:getHP() == startingHp and mob:hasStatusEffect(xi.effect.SLEEP_I))
        assert(not owner.actions:useTrustSpell(val, mob, xi.magic.spell.FLASH), 'protected Sleep also blocks admission')
    end)

    it('keeps a sleeping collateral target out of Uriel Blade', function()
        local primary = fixtureMob('Ordinary_Trust_Aoe_Primary', 0)
        local sleeping = fixtureMob('Ordinary_Trust_Aoe_Collateral', 2)
        local awake = fixtureMob('Ordinary_Trust_Aoe_Awake', 2)
        for _, mob in ipairs({ primary, sleeping, awake }) do
            mob:setMobMod(xi.mobMod.NO_REST, 1)
        end

        owner:addSpell(xi.magic.spell.BLIND)
        owner:addSpell(xi.magic.spell.SLOW)
        playerSpell(sleeping, xi.magic.spell.PARALYZE)
        assert(sleeping:addStatusEffect(xi.effect.SLEEP_I, { power = 1, duration = 60, origin = owner }))
        playerSpell(awake, xi.magic.spell.BLIND)
        playerSpell(primary, xi.magic.spell.SLOW)
        assert(onTarget(val, primary))

        local actorId = val:getID()
        local primaryId = primary:getID()
        local awakeId = awake:getID()
        local sleepingId = sleeping:getID()
        local recipients = {}
        val:addListener('WEAPONSKILL_USE', 'ORDINARY_TRUST_URIEL_RECIPIENT', function(actor, recipient, skill, spentTp, _, amount)
            if
                actor:getID() == actorId and
                skill:getID() == xi.mobSkill.URIEL_BLADE_1 and
                spentTp == 3000
            then
                recipients[recipient:getID()] = { amount = amount, hp = recipient:getHP() }
            end
        end)

        local primaryHp = primary:getHP()
        local awakeHp = awake:getHP()
        local sleepingHp = sleeping:getHP()
        -- Exercise recipient selection and real damage without a random one-hit miss.
        stub('xi.combat.physicalHitRate.getPhysicalHitRate', 1)
        owner.packets:clear()
        val:setMobAbilityEnabled(true)
        val:setTP(3000)
        val:addGambit(ai.t.TARGET, { ai.c.ALWAYS, 0 }, { ai.r.MS, ai.s.SPECIFIC, xi.mobSkill.URIEL_BLADE_1 })
        for _ = 1, 6 do
            xi.test.world:skipTime(2)
            if recipients[primaryId] then
                break
            end
        end

        val:removeListener('ORDINARY_TRUST_URIEL_RECIPIENT')
        val:removeAllGambits()
        local primaryHit = assert(recipients[primaryId], 'the selected focus must be a native recipient')
        local awakeHit = assert(recipients[awakeId], 'the awake collateral must be a native recipient')
        assert(primaryHit.amount > 0 and primaryHit.hp == primaryHp - primaryHit.amount and primary:getHP() == primaryHit.hp,
            string.format('primary script result=%d HP=%d/%d/%d', primaryHit.amount, primaryHp, primaryHit.hp, primary:getHP()))
        assert(awakeHit.amount > 0 and awakeHit.hp == awakeHp - awakeHit.amount and awake:getHP() == awakeHit.hp,
            string.format('awake script result=%d HP=%d/%d/%d', awakeHit.amount, awakeHp, awakeHit.hp, awake:getHP()))
        assert(not recipients[sleepingId] and sleeping:getHP() == sleepingHp and sleeping:hasStatusEffect(xi.effect.SLEEP_I),
            'the protected sleeper cannot be a recipient, take damage, or lose Sleep')

        local packetRecipients = {}
        local finishCount = 0
        for _, packet in ipairs(owner.packets:actionPackets()) do
            if
                packet.m_uID == actorId and
                packet.cmd_no == xi.action.category.WEAPONSKILL_FINISH and
                packet.cmd_arg == xi.mobSkill.URIEL_BLADE_1
            then
                finishCount = finishCount + 1
                for _, target in ipairs(packet.target) do
                    assert(#target.result == 1 and not packetRecipients[target.m_uID])
                    packetRecipients[target.m_uID] = target.result[1].value
                end
            end
        end

        assert(finishCount == 1, 'exactly one native Uriel finish packet')
        assert(packetRecipients[primaryId] == primaryHit.amount and packetRecipients[awakeId] == awakeHit.amount,
            'native packet damage must match the resolved primary and awake collateral amounts')
        assert(not packetRecipients[sleepingId], 'the protected sleeper cannot appear in the native finish packet')
    end)

    it('releases only the current Sleep application after a resisted damaging spell', function()
        local mob = fixtureMob('Ordinary_Trust_Sleep', 0)
        assert(mob:addStatusEffect(xi.effect.SLEEP_I, { power = 1, duration = 60, origin = owner }))
        playerSpell(mob, xi.magic.spell.PARALYZE)
        assert(not val:isEngaged(), 'a non-damaging enfeeble cannot release Sleep')

        stub('xi.spells.damage.useDamageSpell', function(_, _, spell)
            spell:setMsg(xi.msg.basic.MAGIC_RESIST)
            return 0
        end)

        playerSpell(mob, xi.magic.spell.STONE)
        assert(mob:hasStatusEffect(xi.effect.SLEEP_I), 'the resisted owner attack cannot remove native Sleep')
        assert(onTarget(val, mob) and onTarget(iroha, mob), 'both Trusts may engage after a completed damaging attempt')

        mob:delStatusEffect(xi.effect.SLEEP_I)
        assert(mob:addStatusEffect(xi.effect.SLEEP_I, { power = 1, duration = 60, origin = owner }))
        assert(not owner.actions:useTrustSpell(val, mob, xi.magic.spell.FLASH), 'a fresh application must be protected')
    end)

    it('lets Iroha recover Valaineral through native Arise during an ongoing fight', function()
        local mob = fixtureMob('Ordinary_Trust_Recovery', 0)
        playerSpell(mob, xi.magic.spell.PARALYZE)
        assert(onTarget(val, mob) and onTarget(iroha, mob))
        local id = val:getID()
        local index = val:getTargID()
        local started
        local finished
        iroha:addListener('MAGIC_START', 'IROHA_ARISE_START', function(caster, target, spell)
            if spell:getID() == xi.magic.spell.ARISE then
                started = { target = target:getID(), engaged = caster:isEngaged(), mp = caster:getMP() }
            end
        end)

        iroha:addListener('MAGIC_USE', 'IROHA_ARISE_USE', function(caster, target, spell)
            if spell:getID() == xi.magic.spell.ARISE then
                finished = { target = target:getID(), mp = caster:getMP() }
            end
        end)

        val:setHP(0)
        xi.test.world:tickEntity(val)
        assert(val:isDead() and val:canReceiveTrustRaise())
        assert(#owner:getPartyWithTrusts() == 3)
        for _ = 1, 38 do
            xi.test.world:skipTime(1)
            if not val:isDead() then
                break
            end
        end

        assert(started and started.engaged and started.target == id)
        assert(finished and finished.target == id and finished.mp < started.mp)
        assert(not val:isDead() and val:getID() == id and val:getTargID() == index)
        assert(val:getStatusEffect(xi.effect.WEAKNESS):getDuration() == 180000)
        assert(val:getStatusEffect(xi.effect.RERAISE):getPower() == 3)
        assert(#owner:getPartyWithTrusts() == 3)
    end)

    it('uses Rise from Ashes on living party recipients when they are asleep', function()
        local mob = fixtureMob('Ordinary_Trust_Rise', 0)
        playerSpell(mob, xi.magic.spell.PARALYZE)
        assert(onTarget(iroha, mob))
        local outsider = xi.test.world:spawnPlayer({ name = 'RiseOutside', zone = xi.zone.WEST_RONFAURE, job = xi.job.PLD, level = 99 })
        local x, y, z = iroha:getXPos(), iroha:getYPos(), iroha:getZPos()
        owner:setPos(x, y, z)
        val:setPos(x + 1, y, z)
        outsider:setPos(x + 2, y, z)
        for _, member in ipairs({ owner, val, outsider }) do
            member:setHP(math.floor(member:getMaxHP() / 2))
            assert(member:addStatusEffect(xi.effect.SLEEP_I, { power = 1, duration = 60, origin = mob }))
        end

        local ownerHp = owner:getHP()
        local valHp = val:getHP()
        local outsiderHp = outsider:getHP()
        iroha:setMobAbilityEnabled(true)
        iroha:setTP(1000)
        iroha:addGambit(ai.t.SELF, { { ai.c.IROHA_RECOVERY, 0 }, { ai.c.TP_GTE, 1000 } }, { ai.r.MS, ai.s.SPECIFIC, 3738 })
        for _ = 1, 10 do
            xi.test.world:skipTime(1)
            if not owner:hasStatusEffect(xi.effect.SLEEP_I) then
                break
            end
        end

        assert(iroha:getTP() == 0)
        assert(owner:getHP() > ownerHp and not owner:hasStatusEffect(xi.effect.SLEEP_I))
        assert(val:getHP() > valHp and not val:hasStatusEffect(xi.effect.SLEEP_I))
        assert(outsider:getHP() == outsiderHp and outsider:hasStatusEffect(xi.effect.SLEEP_I))
    end)

    it('reserves a recipient while a developed Trust is casting Cure or Raise', function()
        owner:setHP(1)
        assert(owner.actions:useTrustSpell(val, owner, xi.magic.spell.CURE_IV))
        assert(not owner.actions:useTrustSpell(iroha, owner, xi.magic.spell.CURE_V))
        xi.test.world:skipTime(6)
        assert(owner:getHP() > 1)

        owner:setUnkillable(false)
        owner:die({ expLoss = false })
        xi.test.world:tickEntity(owner)
        assert(owner:isDead())
        assert(owner.actions:useTrustSpell(val, owner, xi.magic.spell.RAISE))
        assert(not owner.actions:useTrustSpell(iroha, owner, xi.magic.spell.ARISE))
    end)
end)
