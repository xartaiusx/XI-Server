-----------------------------------
-- Approved Valaineral development: native controller/state integration.
-- These fixtures require the isolated native test engine and active module SQL.
-- They never use castSpell(), which deletes a mob/Trust spell's recast.
-----------------------------------
describe('Valaineral developed jobs', function()
    local dummyId

    local function spawn(level)
        local owner = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE, job = xi.job.PLD, level = level or 99 })
        assert(owner:getID() > 0 and owner:getZoneID() == xi.zone.WEST_RONFAURE, 'initial fixture wrapper must have its native character')
        local val = owner:spawnTrust(xi.magic.spell.VALAINERAL)
        assert(val, 'fixture Valaineral must spawn')
        val:removeAllGambits()
        val:setAutoAttackEnabled(false)
        val:setMobAbilityEnabled(false) -- Disable autonomous TP selection, not controller admission.
        return owner, val
    end

    local function target(owner)
        local mob = owner:getZone():insertDynamicEntity({
            objtype              = xi.objType.MOB,
            name                 = 'Job99_Action',
            groupId              = 5,
            groupZoneId          = 154,
            minLevel             = 1,
            maxLevel             = 1,
            respawn              = 0,
            releaseIdOnDisappear = true,
        })
        assert(mob, 'disposable action target must exist')
        dummyId = mob:getID()
        SpawnMob(dummyId)
        mob:setPos(owner:getXPos() + 1, owner:getYPos(), owner:getZPos())
        mob:setMaxHP(1000000)
        mob:setHP(1000000)
        mob:setUnkillable(true)
        mob:setAutoAttackEnabled(false)
        mob:setMagicCastingEnabled(false)
        mob:setMobAbilityEnabled(false)
        mob:setDropID(0)
        return mob
    end

    local function finish(actor, seconds)
        xi.test.world:tickEntity(actor)
        xi.test.world:skipTime(seconds or 10)
        xi.test.world:skipTime(3)
    end

    local function engageWithoutOwnerSwings(owner, val, mob)
        owner.actions:engage(mob)
        local x, y, z = owner:getXPos(), owner:getYPos(), owner:getZPos()
        -- Native owner engagement keeps the Trust target valid; facing away
        -- prevents PC swings from contaminating the spell HP measurements.
        owner:lookAt(2 * x - mob:getXPos(), y, 2 * z - mob:getZPos())
        local ownerTarget = owner:getTarget()
        assert(owner:isEngaged() and ownerTarget and ownerTarget:getID() == mob:getID())
        assert(not owner:isFacing(mob), 'the engaged fixture owner must face away from the target')
        val:engage(mob:getTargID())
        local trustTarget = val:getTarget()
        assert(trustTarget and trustTarget:getID() == mob:getID(), 'Valaineral must retain the actual native cast target')
    end

    before_each(function()
        xi.test.world:setSetting('main.TRUST_JOB99_VALAINERAL', true)
        xi.test.world:setSetting('main.ENABLE_TRUST_ALTER_EGO_POINT_BONUSES', false)
        xi.test.world:setSetting('main.ENABLE_TRUST_UNITY_RANK_STAT_PARITY', false)
        xi.test.world:setSetting('map.ALTER_EGO_SKILL_MULTIPLIER', 1)
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

            assert(GetEntityByID(dummyId, nil, true) == nil, 'disposable action target must be destroyed')
        end

        dummyId = nil
    end)

    it('has literal99/99, both main privileges, legal native merits and exact JP categories', function()
        local owner, val = spawn(50)
        assert(val:getMainLvl() == 99 and val:getSubLvl() == 99)
        assert(val:getMainJob() == xi.job.PLD and val:getSubJob() == xi.job.WAR)
        assert(val:isDevelopedTrust())
        assert(val:hasMainJobAccess(xi.job.PLD) and val:hasMainJobAccess(xi.job.WAR))
        assert(not val:hasMainJobAccess(xi.job.BLM))
        assert(val:getLocalVar('MochiTrustJob99StatLevel') == 50, 'regular stat input must remain the summon snapshot')
        assert(val:getMerit(xi.merit.GUARDIAN) == 95)
        assert(val:getMerit(xi.merit.IRON_WILL) == 57)
        assert(val:getMerit(xi.merit.SAVAGERY) == 500)
        assert(val:getMerit(xi.merit.REQUIESCAT) == 15)
        assert(val:getMerit(xi.merit.AGGRESSIVE_AIM) == 0)
        assert(val:getJobPointLevel(xi.jp.SENTINEL_EFFECT) == 20)
        assert(val:getJobPointLevel(xi.jp.DEFENDER_EFFECT) == 20)
        assert(val:getJobPointLevel(xi.jp.BENEDICTION_EFFECT) == 0)
        assert(val:getMod(xi.mod.ONE_HOUR_RECAST) == 15, 'shared SP gift must be applied once')

        local pld = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE, job = xi.job.PLD, level = 99 })
        local war = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE, job = xi.job.WAR, level = 99 })
        pld:capAllSkills()
        war:capAllSkills()
        assert(val:getSkillLevel(xi.skill.SWORD) == math.max(pld:getSkillLevel(xi.skill.SWORD), war:getSkillLevel(xi.skill.SWORD)))
        assert(val:getSkillLevel(xi.skill.GREAT_AXE) == war:getSkillLevel(xi.skill.GREAT_AXE))
        assert(val:getSkillLevel(xi.skill.DIVINE_MAGIC) == pld:getSkillLevel(xi.skill.DIVINE_MAGIC))
        assert(val:hasTrait(xi.trait.DEFENSE_BONUS) and val:hasTrait(xi.trait.FENCER))
        assert(not owner.actions:useTrustAbility(val, val, xi.jobAbility.BENEDICTION), 'unassigned job must not acquire its actions')
    end)

    it('keeps unapproved variants and evidence lanes native', function()
        local owner, val = spawn(50)
        local other = owner:spawnTrust(xi.magic.spell.SHANTOTTO)
        assert(other and not other:isDevelopedTrust())
        assert(other:getMainLvl() == 50 and other:getSubLvl() == 25)
        assert(val:getMainLvl() == 99 and val:getSubLvl() == 99)
        xi.test.world:setSetting('main.ENABLE_MOCHIRII_TWILLS_FULL_ALLIANCE', true)
        xi.test.world:setSetting('main.MOCHIRII_TWILLS_FULL_ALLIANCE_MAX_PARTIES', 3)
        for _, mode in ipairs({ 1, 2 }) do
            -- The name override is in memory; the engine owns a generated DB identity.
            local control = xi.test.world:spawnPlayer({ name = 'Twills', zone = xi.zone.WEST_RONFAURE, job = xi.job.PLD, level = 50 })
            control:setGMLevel(5)
            control:setVisibleGMLevel(0)
            control:setCharVar('MochiriiTrustAllianceAccess', 1)
            assert(control:canUseTwillsFullAlliance())
            assert(control:setTwillsFullAllianceState(1))
            control:setLocalVar('MochiriiTrustEvidenceMode', mode)
            local native = control:spawnTrust(xi.magic.spell.VALAINERAL)
            assert(native and not native:isDevelopedTrust())
            assert(native:getMainLvl() == 50 and native:getSubLvl() == 25)
        end
    end)

    it('preserves native scaling multipliers and half-level support stats', function()
        xi.test.world:setSetting('map.ALTER_EGO_HP_MULTIPLIER', 1.25)
        xi.test.world:setSetting('map.ALTER_EGO_MP_MULTIPLIER', 1.25)
        xi.test.world:setSetting('map.ALTER_EGO_STAT_MULTIPLIER', 1.25)
        xi.test.world:setSetting('map.ALTER_EGO_SKILL_MULTIPLIER', 1.25)
        xi.test.world:setSetting('main.TRUST_JOB99_VALAINERAL', false)
        local _, native = spawn()
        local hp, mp, strength = native:getMaxHP(), native:getMaxMP(), native:getStat(xi.mod.STR)
        local nativeHpTrait, nativeHpp = native:getMod(xi.mod.BASE_HP), native:getMod(xi.mod.HPP)
        xi.test.world:setSetting('main.TRUST_JOB99_VALAINERAL', true)
        local _, developed = spawn()
        assert(developed:getMainLvl() == 99 and developed:getSubLvl() == 99)
        -- WAR99 legitimately upgrades Max HP Boost beyond PLD99/WAR49. Its
        -- flat trait is separate from the unchanged half-level stat formula.
        assert(nativeHpTrait == 60 and developed:getMod(xi.mod.BASE_HP) == 180,
            string.format('native/developed Max HP Boost must be 60/180, got %d/%d', nativeHpTrait, developed:getMod(xi.mod.BASE_HP)))
        assert(developed:getMod(xi.mod.HPP) == nativeHpp, 'the developed trait must not add a percentage gift-stat package')
        local traitHp = math.floor((180 - 60) * (100 + nativeHpp) / 100)
        assert(developed:getMaxHP() == hp + traitHp and developed:getMaxMP() == mp,
            string.format('base/multiplier parity plus %d trait HP: HP %d/%d MP %d/%d', traitHp, developed:getMaxHP(), hp + traitHp, developed:getMaxMP(), mp))
        assert(developed:getStat(xi.mod.STR) == strength, 'literal support99 must not double the native support stat contribution')
        local pld = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE, job = xi.job.PLD, level = 99 })
        pld:capAllSkills()
        assert(developed:getSkillLevel(xi.skill.DIVINE_MAGIC) == math.floor(pld:getSkillLevel(xi.skill.DIVINE_MAGIC) * 1.25))
    end)

    it('refreshes once per equipment batch without healing, TP reset or modifier accumulation', function()
        xi.test.world:setSetting('main.ENABLE_TRUST_UNITY_RANK_STAT_PARITY', true)
        local owner, val = spawn()
        local ident = val:getID()
        val:addMod(xi.mod.STR, 7)
        val:addStatusEffect(xi.effect.PROTECT, { power = 80, duration = 600, origin = val })
        local baseHP, baseMP, baseSTR = val:getMaxHP(), val:getMaxMP(), val:getStat(xi.mod.STR)
        local protectDEF = val:getMod(xi.mod.DEF)
        val:setHP(1)
        val:setMP(1)
        val:setTP(1234)
        owner:addItem(xi.item.NAEGLING)
        owner:addItem(xi.item.SULEVIAS_PLATEMAIL_P2)
        local weaponIndex = owner:getItemInvSlot(xi.item.NAEGLING, 1)
        local armorIndex = owner:getItemInvSlot(xi.item.SULEVIAS_PLATEMAIL_P2, 1)
        assert(weaponIndex and armorIndex, 'the disposable fixture must own both equipment items')
        owner.actions:equipSet({
            { index = weaponIndex, kind = xi.slot.MAIN, container = xi.inv.INVENTORY },
            { index = armorIndex, kind = xi.slot.BODY, container = xi.inv.INVENTORY },
        })
        assert(val:getLocalVar('MochiTrustJob99StatLevel') == 99, 'per-item work must defer the Trust refresh until batch closure')
        owner.actions:flushEquipmentBatch()
        assert(val:getLocalVar('MochiTrustJob99StatLevel') == owner:getAverageItemLevel())
        assert(val:getLocalVar('MochiTrustJob99StatLevel') == 111)
        assert(val:getID() == ident and val:getMainLvl() == 99 and val:getSubLvl() == 99)
        assert(val:getMaxHP() > baseHP and val:getStat(xi.mod.STR) > baseSTR)
        assert(val:getHP() == 1 and val:getMP() == 1 and val:getTP() == 1234)
        assert(val:getStatusEffect(xi.effect.PROTECT):getPower() == 80)
        local scaledProtectedDEF = val:getMod(xi.mod.DEF)
        val:delStatusEffect(xi.effect.PROTECT)
        assert(val:getMod(xi.mod.DEF) == scaledProtectedDEF - 80, 'refresh must preserve exactly one effect-owned Protect contribution')
        val:addStatusEffect(xi.effect.PROTECT, { power = 80, duration = 600, origin = val })
        assert(val:getMod(xi.mod.DEF) == scaledProtectedDEF)
        local scaledHP, scaledSTR = val:getMaxHP(), val:getStat(xi.mod.STR)
        owner.actions:flushEquipmentBatch()
        assert(val:getMaxHP() == scaledHP and val:getStat(xi.mod.STR) == scaledSTR)

        owner.actions:equipSet({
            { index = 0, kind = xi.slot.MAIN, container = xi.inv.INVENTORY },
            { index = 0, kind = xi.slot.BODY, container = xi.inv.INVENTORY },
        })
        owner.actions:flushEquipmentBatch()
        assert(val:getLocalVar('MochiTrustJob99StatLevel') == 99)
        assert(val:getMaxHP() == baseHP and val:getMaxMP() == baseMP and val:getStat(xi.mod.STR) == baseSTR)
        assert(val:getHP() == 1 and val:getMP() == 1 and val:getTP() == 1234)
        assert(val:getMod(xi.mod.DEF) == protectDEF and val:getMod(xi.mod.ONE_HOUR_RECAST) == 15)
    end)

    it('casts Crusade and EnlightII with MP and native spell recasts, without duplicate JP accuracy', function()
        local owner, val = spawn()
        local before = val:getMP()
        assert(owner.actions:useTrustSpell(val, val, xi.magic.spell.CRUSADE))
        finish(val)
        assert(val:hasStatusEffect(xi.effect.ENMITY_BOOST))
        assert(val:getMP() < before)
        assert(val:hasRecast(xi.recast.MAGIC, xi.magic.spell.CRUSADE))
        assert(not owner.actions:useTrustSpell(val, val, xi.magic.spell.CRUSADE), 'controller must keep the native spell recast')

        local acc = val:getMod(xi.mod.ACC)
        assert(owner.actions:useTrustSpell(val, val, xi.magic.spell.ENLIGHT_II))
        finish(val)
        local effect = val:getStatusEffect(xi.effect.ENLIGHT)
        assert(effect and effect:getTier() == 2)
        assert(val:getMod(xi.mod.ENSPELL_DMG) == effect:getPower(), 'JP must be included exactly once')
        assert(val:getMod(xi.mod.ACC) == acc, 'EnlightII accuracy follows its native decaying damage term')
    end)

    it('casts missing HolyII and rejects unassigned spells and insufficient MP', function()
        local owner, val = spawn()
        local mob = target(owner)
        val:engage(mob:getTargID())
        local before = mob:getHP()
        assert(owner.actions:useTrustSpell(val, mob, xi.magic.spell.HOLY_II))
        finish(val)
        assert(mob:getHP() < before)
        assert(val:hasRecast(xi.recast.MAGIC, xi.magic.spell.HOLY_II))
        assert(not owner.actions:useTrustSpell(val, mob, xi.magic.spell.METEOR))
        val:setMP(0)
        assert(not owner.actions:useTrustSpell(val, val, xi.magic.spell.CRUSADE), 'provided supplies must not remove MP cost')
    end)

    it('learns and casts Banish I and II but rejects unqualified developed Banish III', function()
        local owner, val = spawn()
        assert(owner.actions:hasTrustSpell(val, xi.magic.spell.BANISH))
        assert(owner.actions:hasTrustSpell(val, xi.magic.spell.BANISH_II))
        assert(not owner.actions:hasTrustSpell(val, xi.magic.spell.BANISH_III), 'developed learning must exclude the unqualified legacy exception')
        local mob = target(owner)
        engageWithoutOwnerSwings(owner, val, mob)
        local hp, mp = mob:getHP(), val:getMP()
        assert(not owner.actions:useTrustSpell(val, mob, xi.magic.spell.BANISH_III), 'native controller/state admission must also reject Banish III')
        xi.test.world:tickEntity(val)
        xi.test.world:skipTime(1)
        assert(mob:getHP() == hp and val:getMP() == mp, 'rejected Banish III must spend no MP or target HP')
        assert(not val:hasRecast(xi.recast.MAGIC, xi.magic.spell.BANISH_III))

        for _, spellId in ipairs({ xi.magic.spell.BANISH, xi.magic.spell.BANISH_II }) do
            hp, mp = mob:getHP(), val:getMP()
            assert(owner.actions:useTrustSpell(val, mob, spellId), string.format('native Banish admission failed for spell %d', spellId))
            finish(val)
            assert(mob:getHP() < hp and val:getMP() < mp,
                string.format('spell %d must damage and spend MP: HP %d/%d MP %d/%d', spellId, mob:getHP(), hp, val:getMP(), mp))
            assert(val:hasRecast(xi.recast.MAGIC, spellId), string.format('spell %d must retain its native recast', spellId))
        end
    end)

    it('preserves legacy Valaineral Banish III learning and native execution', function()
        xi.test.world:setSetting('main.TRUST_JOB99_VALAINERAL', false)
        local owner, val = spawn()
        assert(not val:isDevelopedTrust())
        assert(owner.actions:hasTrustSpell(val, xi.magic.spell.BANISH_III), 'unchanged legacy SQL list must still supply Banish III')
        local mob = target(owner)
        engageWithoutOwnerSwings(owner, val, mob)
        local hp, mp = mob:getHP(), val:getMP()
        assert(owner.actions:useTrustSpell(val, mob, xi.magic.spell.BANISH_III))
        finish(val)
        assert(mob:getHP() < hp and val:getMP() < mp,
            string.format('legacy Banish III must damage and spend MP: HP %d/%d MP %d/%d', mob:getHP(), hp, val:getMP(), mp))
        assert(val:hasRecast(xi.recast.MAGIC, xi.magic.spell.BANISH_III))
    end)

    it('restricts learned-membership reads to current owned fixture Trusts', function()
        local owner, val = spawn()
        local foreignOwner, foreignVal = spawn()
        assert(owner.actions:hasTrustSpell(val, xi.magic.spell.BANISH_II))
        assert(not owner.actions:hasTrustSpell(owner, xi.magic.spell.BANISH_II), 'PC actor must be rejected')
        assert(not owner.actions:hasTrustSpell(foreignVal, xi.magic.spell.BANISH_II), 'another fixture owner must be rejected')
        assert(foreignOwner.actions:hasTrustSpell(foreignVal, xi.magic.spell.BANISH_II))
        foreignOwner:clearTrusts()
        -- No tick or expired userdata: native ClearTrusts removes the roster
        -- synchronously, while the existing three-second despawn still owns it.
        assert(#foreignOwner:getPartyWithTrusts() == 1)
        assert(not foreignOwner.actions:hasTrustSpell(foreignVal, xi.magic.spell.BANISH_II), 'removed roster membership must be rejected')
    end)

    it('offers native Raise while ownerKO and keeps PC acceptance manual', function()
        local owner, val = spawn()
        owner:die({ expLoss = false })
        xi.test.world:tickEntity(owner)
        assert(owner:isDead())
        assert(owner.actions:useTrustSpell(val, owner, xi.magic.spell.RAISE))
        finish(val)
        assert(owner:isDead() and owner:hasRaiseTractorMenu())
        owner.actions:acceptRaise()
        xi.test.world:skipTime(3)
        xi.test.world:skipTime(3)
        assert(not owner:isDead())
    end)

    it('uses selected Sentinel recast and party Rampart IronWill once with no expiration leak', function()
        local owner, val = spawn()
        assert(owner.actions:useTrustAbility(val, val, xi.jobAbility.SENTINEL))
        xi.test.world:tickEntity(val)
        xi.test.world:skipTime(1)
        local effect = val:getStatusEffect(xi.effect.SENTINEL)
        assert(effect and effect:getSubPower() == 95, 'Guardian loss reduction must remain separate from Sentinel action points')
        assert(val:hasRecast(xi.recast.ABILITY, 75))
        xi.test.world:skipTime(248)
        assert(val:hasRecast(xi.recast.ABILITY, 75), 'Sentinel must still be on its selected250-second recast')
        xi.test.world:skipTime(2)
        assert(not val:hasRecast(xi.recast.ABILITY, 75))

        local valBase, pcBase = val:getMod(xi.mod.SPELLINTERRUPT), owner:getMod(xi.mod.SPELLINTERRUPT)
        assert(not owner:hasTrait(xi.trait.IRON_WILL), 'recipient fixture must not supply its own IronWill contribution')
        val:setPos(owner:getXPos() + 1, owner:getYPos(), owner:getZPos())
        assert(owner.actions:useTrustAbility(val, val, xi.jobAbility.RAMPART))
        finish(val, 1)
        assert(val:getMod(xi.mod.SPELLINTERRUPT) == valBase + 57)
        assert(owner:getMod(xi.mod.SPELLINTERRUPT) == pcBase + 57, 'party recipients use caster IronWill, without duplication')
        xi.test.world:skipTime(35)
        assert(val:getMod(xi.mod.SPELLINTERRUPT) == valBase and owner:getMod(xi.mod.SPELLINTERRUPT) == pcBase)
    end)

    it('shares both assigned firstSPs on the native2700-second recast without repeated Lua reductions', function()
        local owner, val = spawn()
        local recasts = {}
        val:addListener('ABILITY_USE', 'JOB99_SP_RECAST', function(_actor, _target, ability, action)
            if ability:getID() == xi.jobAbility.MIGHTY_STRIKES then
                table.insert(recasts, { ability = ability:getRecast(), action = action:getRecast() })
            end
        end)

        assert(owner.actions:useTrustAbility(val, val, xi.jobAbility.MIGHTY_STRIKES))
        xi.test.world:tickEntity(val)
        xi.test.world:skipTime(1) -- Execute, then measure recast elapsed from this native dispatch.
        xi.test.world:skipTime(3)
        assert(val:hasStatusEffect(xi.effect.MIGHTY_STRIKES))
        assert(#recasts == 1, 'the native SP must complete exactly once')
        local recast = assert(recasts[1])
        assert(recast.ability == 2700 and recast.action == 2700,
            string.format('SP native ability/action recasts must be 2700, got %d/%d', recast.ability, recast.action))
        assert(not owner.actions:useTrustAbility(val, val, xi.jobAbility.INVINCIBLE))
        -- skipTime also adds a 400ms zone tick. Keep a safe pre-expiry margin;
        -- exact duration is asserted from both native completion values above.
        xi.test.world:skipTime(2685)
        assert(val:hasRecast(xi.recast.ABILITY, xi.recastID.SPECIAL), 'two Lua checks must not shorten2700to1800')
        assert(not owner.actions:useTrustAbility(val, val, xi.jobAbility.INVINCIBLE))
        xi.test.world:skipTime(11)
        assert(not val:hasRecast(xi.recast.ABILITY, xi.recastID.SPECIAL))
        assert(owner.actions:useTrustAbility(val, val, xi.jobAbility.INVINCIBLE))
    end)

    it('executes only learned current-weapon playerWS and spends native TP', function()
        local owner, val = spawn()
        local mob = target(owner)
        assert(val:getWeaponSkillType(xi.slot.MAIN) == xi.skill.SWORD)
        val:setTP(3000)
        assert(not owner.actions:useTrustWeaponskill(val, mob, xi.weaponskill.RESOLUTION), 'GreatSword WS requires the correct weapon')
        assert(not owner.actions:useTrustWeaponskill(val, mob, xi.weaponskill.KNIGHTS_OF_ROUND), 'equipment-only WS must not become a job unlock')
        assert(val:getTP() == 3000)
        assert(owner.actions:useTrustWeaponskill(val, mob, xi.weaponskill.REQUIESCAT))
        finish(val, 3)
        assert(val:getTP() < 1000, 'real playerWS completion must spend native TP')
    end)

    it('shares secondSPs and provides Tomahawk without player ammunition', function()
        local owner, val = spawn()
        local mob = target(owner)
        assert(owner:getEquipID(xi.slot.AMMO) == 0)
        assert(owner.actions:useTrustAbility(val, mob, xi.jobAbility.TOMAHAWK))
        finish(val, 1)
        assert(mob:hasStatusEffect(xi.effect.TOMAHAWK))
        assert(owner:getEquipID(xi.slot.AMMO) == 0, 'Trust-provided consumables must not debit or refill player inventory')
        assert(owner.actions:useTrustAbility(val, val, xi.jobAbility.BRAZEN_RUSH))
        xi.test.world:tickEntity(val)
        xi.test.world:skipTime(1)
        xi.test.world:skipTime(3)
        assert(val:hasRecast(xi.recast.ABILITY, xi.recastID.SPECIAL2))
        assert(not owner.actions:useTrustAbility(val, mob, xi.jobAbility.INTERVENE))
        assert(not val:hasRecast(xi.recast.ABILITY, xi.recastID.SPECIAL), 'first and second native SP keys remain separate')
    end)

    it('rejects another fixture owner using the test-only action adapter', function()
        local owner, val = spawn()
        local stranger = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE, job = xi.job.PLD, level = 99 })
        assert(not stranger.actions:useTrustSpell(val, val, xi.magic.spell.CRUSADE))
        assert(not stranger.actions:useTrustAbility(val, val, xi.jobAbility.SENTINEL))
        assert(not stranger.actions:useTrustWeaponskill(val, owner, xi.weaponskill.REQUIESCAT))

        local ident = stranger:getID()
        stranger:setLocalVar('Job99ZoneRebind', 1)
        stranger:gotoZone(xi.zone.EAST_RONFAURE)
        assert(stranger:getID() == ident and stranger:getZoneID() == xi.zone.EAST_RONFAURE)
        assert(stranger:getLocalVar('Job99ZoneRebind') == 0, 'zoning must rebind the wrapper to the newly loaded native entity')
        stranger:setLocalVar('Job99ZoneRebind', 2)
        stranger:gotoZone(xi.zone.WEST_RONFAURE)
        assert(stranger:getID() == ident and stranger:getZoneID() == xi.zone.WEST_RONFAURE)
        assert(stranger:getLocalVar('Job99ZoneRebind') == 0, 'subsequent zone entries must retain the default reload mode')
    end)
end)
