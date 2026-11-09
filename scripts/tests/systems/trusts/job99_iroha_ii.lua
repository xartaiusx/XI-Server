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
end)
