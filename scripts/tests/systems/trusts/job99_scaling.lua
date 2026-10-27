-----------------------------------
-- Earned native progression and active effects survive equipment refresh.
-- All progression changes below belong only to disposable isolated fixtures.
-----------------------------------
describe('Valaineral scaling with earned progression', function()
    ---@type CClientEntityPair
    local owner
    local val

    local function equipScaledSet()
        local swordSlot = assert(owner:getItemInvSlot(xi.item.NAEGLING, 1))
        local bodySlot = assert(owner:getItemInvSlot(xi.item.SULEVIAS_PLATEMAIL_P2, 1))
        owner.actions:equipSet({
            { index = swordSlot, kind = xi.slot.MAIN, container = xi.inv.INVENTORY },
            { index = bodySlot, kind = xi.slot.BODY, container = xi.inv.INVENTORY },
        })
        owner.actions:flushEquipmentBatch()
    end

    local function clearScaledSet()
        owner.actions:equipSet({
            { index = 0, kind = xi.slot.MAIN, container = xi.inv.INVENTORY },
            { index = 0, kind = xi.slot.BODY, container = xi.inv.INVENTORY },
        })
        owner.actions:flushEquipmentBatch()
    end

    before_each(function()
        xi.test.world:setSetting('main.TRUST_JOB99_VALAINERAL', true)
        xi.test.world:setSetting('main.ENABLE_TRUST_ALTER_EGO_POINT_BONUSES', true)
        xi.test.world:setSetting('main.ENABLE_TRUST_UNITY_RANK_STAT_PARITY', false)
        xi.test.world:setSetting('map.ALTER_EGO_SKILL_MULTIPLIER', 1)
        owner = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE, job = xi.job.PLD, level = 99 })
        owner:setCharVar('AlterEgoPoints_HP', 3)
        owner:setCharVar('AlterEgoPoints_MP', 2)
        owner:setCharVar('AlterEgoPoints_STR', 4)
        owner:setCharVar('AlterEgoPoints_CombatSkills', 5)
        owner:setCharVar('AlterEgoPoints_MagicSkills', 6)
        val = owner:spawnTrust(xi.magic.spell.VALAINERAL)
        assert(val)
        val:removeAllGambits()
        val:setAutoAttackEnabled(false)
        owner:addItem(xi.item.NAEGLING)
        owner:addItem(xi.item.SULEVIAS_PLATEMAIL_P2)
    end)

    it('preserves earned HP/MP, stats and skills through repeated scaling round trips', function()
        assert(val:getLocalVar('MochiTrustAepHpRank') == 3)
        assert(val:getLocalVar('MochiTrustAepMpRank') == 2)
        assert(val:getLocalVar('MochiTrustAepStatRank') == 4)
        assert(val:getLocalVar('MochiTrustAepCombatRank') == 5)
        assert(val:getLocalVar('MochiTrustAepMagicRank') == 6)
        local hp, mp, strength = val:getMaxHP(), val:getMaxMP(), val:getStat(xi.mod.STR)
        local hpMod, mpMod = val:getMod(xi.mod.HP), val:getMod(xi.mod.MP)
        local sword, divine = val:getSkillLevel(xi.skill.SWORD), val:getSkillLevel(xi.skill.DIVINE_MAGIC)
        val:setHP(1)
        val:setMP(1)
        val:setTP(1234)
        for _ = 1, 2 do
            equipScaledSet()
            assert(val:getLocalVar('MochiTrustJob99StatLevel') == 111)
            assert(val:getMaxHP() > hp)
            assert(val:getHP() == 1 and val:getMP() == 1 and val:getTP() == 1234)
            assert(val:getSkillLevel(xi.skill.SWORD) == sword and val:getSkillLevel(xi.skill.DIVINE_MAGIC) == divine)
            clearScaledSet()
            assert(val:getMaxHP() == hp and val:getMaxMP() == mp and val:getStat(xi.mod.STR) == strength)
            assert(val:getMod(xi.mod.HP) == hpMod and val:getMod(xi.mod.MP) == mpMod)
            assert(val:getHP() == 1 and val:getMP() == 1 and val:getTP() == 1234)
        end
    end)

    it('keeps Weakness and its elapsed duration while clamping to the smaller native maximum', function()
        val:addStatusEffect(xi.effect.WEAKNESS, { power = 1, duration = 300, origin = val })
        xi.test.world:skipTime(10)
        local effect = val:getStatusEffect(xi.effect.WEAKNESS)
        assert(effect)
        local originalDuration = effect:getDuration()
        local originalStart = effect:getStartTime()
        equipScaledSet()
        assert(val:hasStatusEffect(xi.effect.WEAKNESS))
        local scaledMax = val:getMaxHP()
        local scaledMP = val:getMaxMP()
        val:setHP(scaledMax)
        val:setMP(scaledMP)
        val:setTP(1234)
        clearScaledSet()
        assert(val:getMaxHP() < scaledMax)
        assert(val:getHP() == val:getMaxHP() and val:getMP() == math.min(scaledMP, val:getMaxMP()))
        assert(val:getTP() == 1234)
        local remaining = val:getStatusEffect(xi.effect.WEAKNESS)
        assert(remaining and remaining:getPower() == 1)
        assert(remaining:getDuration() == originalDuration and remaining:getStartTime() == originalStart)
    end)
end)
