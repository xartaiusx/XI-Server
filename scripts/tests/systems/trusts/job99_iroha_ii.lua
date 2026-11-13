-----------------------------------
-- Native Iroha II profile and action admission
-----------------------------------
describe('Iroha II developed jobs', function()
    local function spawn(level)
        local owner = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE, job = xi.job.PLD, level = level or 99 })
        local iroha = assert(owner:spawnTrust(xi.magic.spell.IROHA_II))
        iroha:removeAllGambits()
        iroha:setAutoAttackEnabled(false)
        return owner, iroha
    end

    before_each(function()
        xi.test.world:setSetting('main.TRUST_JOB99_VALAINERAL', false)
        xi.test.world:setSetting('main.TRUST_JOB99_IROHA_II', true)
    end)

    it('uses both native main-job catalogs and a two-handed polearm', function()
        local owner, iroha = spawn(50)
        assert(iroha:isDevelopedTrust())
        assert(iroha:getMainJob() == xi.job.SAM and iroha:getSubJob() == xi.job.WHM)
        assert(iroha:getMainLvl() == 99 and iroha:getSubLvl() == 99)
        assert(iroha:getLocalVar('MochiTrustJob99StatLevel') == 50)
        assert(iroha:getMaxMP() == 365 and iroha:getMP() == 365)
        assert(iroha:getWeaponSkillType(xi.slot.MAIN) == xi.skill.POLEARM)
        assert(iroha:hasMainJobAccess(xi.job.SAM) and iroha:hasMainJobAccess(xi.job.WHM))
        assert(not iroha:hasMainJobAccess(xi.job.BLM))
        assert(owner.actions:hasTrustSpell(iroha, xi.magic.spell.RERAISE_IV))
        assert(owner.actions:hasTrustSpell(iroha, xi.magic.spell.FULL_CURE))
        assert(owner.actions:hasTrustSpell(iroha, xi.magic.spell.FLARE_II))
        assert(not owner.actions:hasTrustSpell(iroha, xi.magic.spell.FIRE_VI))
        assert(not owner.actions:hasTrustSpell(iroha, xi.magic.spell.VALAINERAL))
        assert(not owner.actions:hasTrustSpell(iroha, xi.magic.spell.IROHA_II))
        assert(owner.actions:hasTrustSpell(iroha, xi.magic.spell.SACRIFICE))
        assert(owner:addStatusEffect(xi.effect.BLINDNESS, { power = 1, duration = 60, origin = owner }))
        assert(owner.actions:useTrustSpell(iroha, owner, xi.magic.spell.SACRIFICE))
        xi.test.world:skipTime(2)
        assert(not owner:hasStatusEffect(xi.effect.BLINDNESS) and iroha:hasStatusEffect(xi.effect.BLINDNESS))
        iroha:delStatusEffect(xi.effect.BLINDNESS)
        xi.test.world:skipTime(2)
        assert(owner.actions:useTrustAbility(iroha, iroha, xi.jobAbility.HASSO))
        xi.test.world:skipTime(2)
        assert(iroha:hasStatusEffect(xi.effect.HASSO))
        assert(owner.actions:useTrustAbility(iroha, iroha, xi.jobAbility.SEIGAN))
        xi.test.world:skipTime(2)
        assert(iroha:hasStatusEffect(xi.effect.SEIGAN))
        assert(not iroha:hasStatusEffect(xi.effect.HASSO))
    end)

    it('does not activate when only Valaineral is enabled', function()
        xi.test.world:setSetting('main.TRUST_JOB99_VALAINERAL', true)
        xi.test.world:setSetting('main.TRUST_JOB99_IROHA_II', false)
        local owner, iroha = spawn(50)
        assert(not iroha:isDevelopedTrust())
        assert(iroha:getMainLvl() == 50 and iroha:getSubLvl() == 25)
        assert(not owner.actions:hasTrustSpell(iroha, xi.magic.spell.FULL_CURE))
        assert(not owner.actions:hasTrustSpell(iroha, xi.magic.spell.RERAISE_IV))
    end)

    it('rejects developed signatures for baseline Iroha II and another developed Trust', function()
        xi.test.world:setSetting('main.TRUST_JOB99_VALAINERAL', true)
        xi.test.world:setSetting('main.TRUST_JOB99_IROHA_II', false)
        local owner, iroha = spawn()
        local valaineral = assert(owner:spawnTrust(xi.magic.spell.VALAINERAL))
        valaineral:removeAllGambits()
        valaineral:setAutoAttackEnabled(false)
        assert(not iroha:isDevelopedTrust() and valaineral:isDevelopedTrust())

        local starts = 0
        for _, trust in ipairs({ iroha, valaineral }) do
            trust:addListener('WEAPONSKILL_STATE_ENTER', 'IROHA_SIGNATURE_REJECT', function(_, skillId)
                if skillId == 3738 then
                    starts = starts + 1
                end
            end)

            trust:setTP(1000)
            trust:useMobAbility(3738, trust)
            xi.test.world:tickEntity(trust)
            xi.test.world:skipTime(3)
            assert(trust:getTP() == 1000, 'a rejected signature cannot spend TP')
            trust:removeListener('IROHA_SIGNATURE_REJECT')
        end

        assert(starts == 0, 'only developed Iroha II may enter the signature state')
    end)

    it('scales White Mage MP from equipment without changing the Samurai role or refilling resources', function()
        local owner, iroha = spawn()
        local id = iroha:getID()
        assert(iroha:getLocalVar('MochiTrustJob99StatLevel') == 99 and iroha:getMaxMP() == 747)
        iroha:setHP(100)
        iroha:setMP(31)
        iroha:setTP(1234)

        local equipment = {}
        local items =
        {
            { xi.item.NAEGLING, xi.slot.MAIN },
            { xi.item.SULEVIAS_MASK_P2, xi.slot.HEAD },
            { xi.item.SULEVIAS_PLATEMAIL_P2, xi.slot.BODY },
            { xi.item.SULEVIAS_GAUNTLETS_P2, xi.slot.HANDS },
            { xi.item.SULEVIAS_CUISSES_P2, xi.slot.LEGS },
            { xi.item.SULEVIAS_LEGGINGS_P2, xi.slot.FEET },
        }
        for _, item in ipairs(items) do
            owner:addItem(item[1])
            table.insert(equipment, {
                index = assert(owner:getItemInvSlot(item[1], 1)),
                kind = item[2], container = xi.inv.INVENTORY,
            })
        end

        owner.actions:equipSet(equipment)
        owner.actions:flushEquipmentBatch()
        assert(owner:getAverageItemLevel() == 119 and iroha:getLocalVar('MochiTrustJob99StatLevel') == 119)
        assert(iroha:getID() == id and iroha:getMainJob() == xi.job.SAM and iroha:getSubJob() == xi.job.WHM)
        assert(iroha:getMaxMP() == 907 and iroha:getMP() == 31 and iroha:getHP() == 100 and iroha:getTP() == 1234)

        owner.actions:flushEquipmentBatch()
        assert(iroha:getMaxMP() == 907 and iroha:getMP() == 31)
        for _, slot in ipairs(equipment) do
            slot.index = 0
        end

        owner.actions:equipSet(equipment)
        owner.actions:flushEquipmentBatch()
        assert(iroha:getLocalVar('MochiTrustJob99StatLevel') == 99)
        assert(iroha:getMaxMP() == 747 and iroha:getMP() == 31 and iroha:getHP() == 100 and iroha:getTP() == 1234)
    end)

    local function observeFullCureSpend(iroha, capacity)
        iroha:setMod(xi.mod.REFRESH, 0)
        iroha:setMaxMP(capacity)
        assert(iroha:getMaxMP() == capacity)
        local spent
        iroha:addListener('MAGIC_USE', 'IROHA_TEST_FULL_CURE_SPEND', function(_, _, spell)
            if spell:getID() == xi.magic.spell.FULL_CURE then
                spent = spell:getMPCost()
            end
        end)

        return function()
            return spent
        end
    end

    it('restores Benediction job-point MP only to Iroha while healing the party', function()
        xi.test.world:setSetting('main.TRUST_JOB99_VALAINERAL', true)
        local owner, iroha = spawn()
        local valaineral = assert(owner:spawnTrust(xi.magic.spell.VALAINERAL))
        valaineral:removeAllGambits()
        valaineral:setAutoAttackEnabled(false)

        local x, y, z = owner:getXPos(), owner:getYPos(), owner:getZPos()
        for _, member in ipairs({ iroha, valaineral }) do
            member:setMobMod(xi.mobMod.NO_MOVE, 1)
            member:setPos(x, y, z)
        end

        for _, member in ipairs({ owner, iroha, valaineral }) do
            member:setMod(xi.mod.REFRESH, 0)
            member:setHP(1)
        end

        owner:setMP(13)
        valaineral:setMP(11)
        iroha:setMP(7)
        local maxMP = iroha:getMaxMP()
        assert(iroha:getJobPointLevel(xi.jp.BENEDICTION_EFFECT) == 20)
        assert(maxMP == 747 and owner:getMP() == 13 and valaineral:getMP() == 11 and iroha:getMP() == 7)

        local completions = 0
        iroha:addListener('ABILITY_USE', 'IROHA_TEST_BENEDICTION', function(_, _, ability, action)
            if ability:getID() == xi.jobAbility.BENEDICTION then
                completions = completions + 1
                assert(ability:getRecast() == 2700 and action:getRecast() == 2700)
            end
        end)

        assert(owner.actions:useTrustAbility(iroha, iroha, xi.jobAbility.BENEDICTION))
        xi.test.world:tickEntity(iroha)
        xi.test.world:skipTime(1)

        assert(completions == 1)
        assert(iroha:getMP() == 7 + math.floor(maxMP * 20 / 100))
        assert(owner:getMP() == 13 and valaineral:getMP() == 11)
        for _, member in ipairs({ owner, iroha, valaineral }) do
            assert(member:getHP() == member:getMaxHP())
        end

        assert(iroha:hasRecast(xi.recast.ABILITY, xi.recastID.SPECIAL))
        assert(not owner.actions:useTrustAbility(iroha, iroha, xi.jobAbility.BENEDICTION))
    end)

    it('spends all MP on a completed Full Cure and retains native recast', function()
        local owner, iroha = spawn()
        local spent = observeFullCureSpend(iroha, 31)
        iroha:setMP(0)
        assert(not owner.actions:useTrustSpell(iroha, owner, xi.magic.spell.FULL_CURE))

        iroha:setMP(31)
        owner:setHP(1)
        assert(owner:addStatusEffect(xi.effect.POISON, { power = 1, duration = 60, origin = owner }))
        assert(owner:addStatusEffect(xi.effect.BLINDNESS, { power = 1, duration = 60, origin = owner }))
        assert(owner.actions:useTrustSpell(iroha, owner, xi.magic.spell.FULL_CURE))
        xi.test.world:skipTime(2)
        assert(spent() == 31 and iroha:getMP() == 0)
        assert(owner:getHP() > 1)
        assert(not owner:hasStatusEffect(xi.effect.POISON) and not owner:hasStatusEffect(xi.effect.BLINDNESS))
        assert(iroha:hasRecast(xi.recast.MAGIC, xi.magic.spell.FULL_CURE))
        iroha:setMP(31)
        assert(not owner.actions:useTrustSpell(iroha, owner, xi.magic.spell.FULL_CURE))
    end)

    it('heals but leaves ordinary ailments below the Full Cure removal threshold', function()
        local owner, iroha = spawn()
        local spent = observeFullCureSpend(iroha, 30)
        iroha:setMP(30)
        owner:setHP(1)
        assert(owner:addStatusEffect(xi.effect.BLINDNESS, { power = 1, duration = 60, origin = owner }))
        assert(owner.actions:useTrustSpell(iroha, owner, xi.magic.spell.FULL_CURE))
        xi.test.world:skipTime(2)
        assert(spent() == 30 and iroha:getMP() == 0 and owner:getHP() > 1)
        assert(owner:hasStatusEffect(xi.effect.BLINDNESS))
    end)

    it('casts and consumes Reraise IV through the same Iroha II entity', function()
        local owner, iroha = spawn()
        local id = iroha:getID()
        local index = iroha:getTargID()
        local mp = iroha:getMP()
        assert(mp == iroha:getMaxMP() and mp == 747)
        assert(owner.actions:useTrustSpell(iroha, iroha, xi.magic.spell.RERAISE_IV))
        for _ = 1, 10 do
            xi.test.world:skipTime(1)
            if iroha:hasStatusEffect(xi.effect.RERAISE) then
                break
            end
        end

        assert(iroha:getStatusEffect(xi.effect.RERAISE):getPower() == 4)
        assert(iroha:getMP() < mp)
        assert(iroha:hasRecast(xi.recast.MAGIC, xi.magic.spell.RERAISE_IV))
        iroha:setHP(0)
        xi.test.world:tickEntity(iroha)
        assert(iroha:isDead())
        xi.test.world:skipTime(7)
        assert(iroha:isDead() and iroha:getHP() == 0)
        xi.test.world:skipTime(2)
        xi.test.world:skipTime(3)
        assert(not iroha:isDead())
        assert(iroha:getID() == id and iroha:getTargID() == index and #owner:getPartyWithTrusts() == 2)
        assert(iroha:getStatusEffect(xi.effect.WEAKNESS):getDuration() == 180000)
        assert(not iroha:hasStatusEffect(xi.effect.RERAISE))
    end)

    it('offers the owner a native Raise without accepting for the player', function()
        local owner, iroha = spawn()
        local id = iroha:getID()
        local raiseUses = 0
        iroha:addListener('MAGIC_USE', 'IROHA_TEST_OWNER_ARISE', function(_, target, spell)
            if spell:getID() == xi.magic.spell.ARISE then
                assert(target:getID() == owner:getID())
                raiseUses = raiseUses + 1
            end
        end)

        owner:die({ expLoss = false })
        xi.test.world:tickEntity(owner)
        assert(owner:isDead())
        for _ = 1, 30 do
            xi.test.world:skipTime(1)
            if owner:hasRaiseTractorMenu() then
                break
            end
        end

        assert(owner:isDead() and owner:hasRaiseTractorMenu() and raiseUses == 1)
        assert(iroha:getID() == id and #owner:getPartyWithTrusts() == 2)
        owner.actions:acceptRaise()
        xi.test.world:skipTime(3)
        xi.test.world:skipTime(3)
        assert(not owner:isDead())
    end)

    describe('Iroha II native Flare II', function()
        local owner
        local iroha
        local mob
        local mobId
        local spellId = xi.magic.spell.FLARE_II

        before_each(function()
            xi.test.world:setSeed(123456)
            owner, iroha = spawn()
            iroha:setMobAbilityEnabled(false)
            iroha:setMod(xi.mod.REFRESH, 0)

            mob = assert(owner:getZone():insertDynamicEntity({
                objtype              = xi.objType.MOB,
                name                 = 'Iroha_Flare_Burst',
                groupId              = 5,
                groupZoneId          = 154,
                minLevel             = 99,
                maxLevel             = 99,
                respawn              = 0,
                releaseIdOnDisappear = true,
                onMobDespawn         = function()
                    -- Native releaseIdOnDisappear owns retirement.
                end,
            }))
            mobId = mob:getID()
            SpawnMob(mobId)
            mob:setMaxHP(1000000)
            mob:setHP(1000000)
            mob:setUnkillable(true)
            mob:setAutoAttackEnabled(false)
            mob:setMagicCastingEnabled(false)
            mob:setMobAbilityEnabled(false)
            mob:setMobMod(xi.mobMod.NO_MOVE, 1)
            mob:setDropID(0)

            local x, y, z = owner:getXPos(), owner:getYPos(), owner:getZPos()
            mob:setPos(x, y, z + 2)
            iroha:setPos(x, y, z + 1)
            assert(owner.entities:moveTo(mob))
            owner:setPos(x, y, z)
            owner.actions:engage(mob)
            owner:setPos(x, y, z)
            owner:lookAt(x, y, z - 2)
            mob:updateEnmity(owner)
            iroha:engage(mob:getTargID())
            xi.test.world:skipTime(1)
            assert(owner:isEngaged() and not owner:isFacing(mob))
            assert(iroha:isEngaged() and iroha:getTarget():getID() == mobId)
        end)

        after_each(function()
            if mobId and GetEntityByID(mobId, nil, true) then
                DespawnMob(mobId)
                for _ = 1, 10 do
                    xi.test.world:tick()
                    if not GetEntityByID(mobId, nil, true) then
                        break
                    end
                end

                assert(not GetEntityByID(mobId, nil, true), 'retire the exact burst fixture')
            end

            mobId = nil
        end)

        local function resonance(kind, seconds)
            assert(mob:addStatusEffect(xi.effect.SKILLCHAIN, {
                icon     = 0,
                power    = kind,
                subPower = 1,
                tier     = 2,
                duration = seconds,
                origin   = owner,
            }))
        end

        local function watchFlare()
            local actions = {}
            iroha:addListener('MAGIC_START', 'IROHA_TEST_FLARE_START', function(actor, target, spell)
                if spell:getID() == spellId then
                    assert(actor:getID() == iroha:getID() and target:getID() == mobId)
                    table.insert(actions, { phase = 'start', baseCast = spell:getCastTime() })
                end
            end)

            iroha:addListener('MAGIC_USE', 'IROHA_TEST_FLARE_FINISH', function(actor, target, spell, action)
                if spell:getID() == spellId then
                    assert(actor:getID() == iroha:getID() and target:getID() == mobId)
                    table.insert(actions, {
                        phase   = 'finish',
                        cost    = spell:getMPCost(),
                        recast  = action:getRecast(),
                        message = action:getMsg(mobId),
                        damage  = action:getParam(mobId),
                    })
                end
            end)

            -- Same two predicates and native action as the developed Iroha profile.
            iroha:addGambit(ai.t.TARGET, {
                { ai.c.MB_ELEMENT_AVAILABLE, xi.element.FIRE },
                { ai.c.CASTER_MPP_GTE, 65 },
            }, { ai.r.MA, ai.s.SPECIFIC, spellId })
            return actions
        end

        for _, stance in ipairs({
            { name = 'Hasso', ability = xi.jobAbility.HASSO, effect = xi.effect.HASSO },
            { name = 'Seigan', ability = xi.jobAbility.SEIGAN, effect = xi.effect.SEIGAN },
        }) do
            it('bursts on a Fire-compatible chain using native ' .. stance.name .. ' cast and recast timing', function()
                assert(GetSpell(spellId):getCastTime() == 7000)
                assert(owner.actions:useTrustAbility(iroha, iroha, stance.ability))
                xi.test.world:skipTime(2)
                assert(iroha:hasStatusEffect(stance.effect))

                local hp = mob:getHP()
                local mp = iroha:getMP()
                local actions = watchFlare()
                -- Seed the native resolved-chain status as a test prerequisite.
                -- Damage, spell completion, MP and recast still run through the actual engine.
                resonance(xi.skillchainType.FUSION, 9)
                for _ = 1, 4 do
                    xi.test.world:skipTime(1)
                    if #actions > 0 then
                        break
                    end
                end

                assert(#actions == 1 and actions[1].phase == 'start' and actions[1].baseCast == 1000)
                assert(iroha:getMP() == mp and mob:getHP() == hp)
                xi.test.world:skipTime(1)
                assert(#actions == 1, 'the stance penalty must keep the cast active past one second')
                xi.test.world:skipTime(1)

                assert(#actions == 2 and actions[2].phase == 'finish')
                local finish = actions[2]
                assert(finish.message == xi.msg.basic.MAGIC_BURST_DAMAGE and finish.damage > 0)
                assert(mob:getHP() == hp - finish.damage and finish.cost == 280 and iroha:getMP() == mp - finish.cost)
                assert(finish.recast == 90 and iroha:hasRecast(xi.recast.MAGIC, spellId))
                assert(iroha:hasStatusEffect(stance.effect))
                assert(GetSpell(spellId):getCastTime() == 7000, 'the player spell template must retain its ordinary cast time')
            end)
        end

        it('does not select Flare II for a wrong element or an expired Fire window', function()
            local mp = iroha:getMP()
            local hp = mob:getHP()
            local actions = watchFlare()
            resonance(xi.skillchainType.DISTORTION, 9)
            for _ = 1, 4 do
                xi.test.world:skipTime(1)
            end

            assert(mob:hasStatusEffect(xi.effect.SKILLCHAIN) and #actions == 0)
            mob:delStatusEffect(xi.effect.SKILLCHAIN)
            resonance(xi.skillchainType.FUSION, 1)
            for _ = 1, 4 do
                xi.test.world:skipTime(1)
            end

            assert(not mob:hasStatusEffect(xi.effect.SKILLCHAIN) and #actions == 0)
            assert(iroha:getMP() == mp and mob:getHP() == hp and not iroha:hasRecast(xi.recast.MAGIC, spellId))
        end)
    end)
end)
