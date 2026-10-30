local ffi = require('ffi')

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

    local function requestAlterEgoPacket(player)
        local request = ffi.new('uint8_t[8]')
        request[4] = 8 -- Native AlterEgoCategory::HP; the current handler returns the menu.
        player.packets:clear()
        player.packets:send(0x0C1, request, assert(ffi.sizeof(request)))
        local matching = {}
        for _, packet in ipairs(player.packets:getIncoming()) do
            if packet.type == 0x08E then
                matching[#matching + 1] = packet
            end
        end

        assert(#matching == 1, 'one native AEP request must serialize exactly one menu packet')
        assert(matching[1].size == 0x68, 'native AEP menu must contain its complete 32-category arrays')
        return matching[1]
    end

    local function expectAlterEgoCategory(packet, index, rank, cost)
        local costOffset = 0x28 + index * 2
        assert(packet.data[0x08 + index] == rank, string.format('AEP category %d must serialize rank %d', index, rank))
        local actualCost = packet.data[costOffset] + packet.data[costOffset + 1] * 256
        assert(actualCost == cost, string.format('AEP category %d must serialize cost %d, got %d', index, cost, actualCost))
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

    it('counts earned HP/MP once at summon and on native health recalculation', function()
        local hp, mp = val:getMaxHP(), val:getMaxMP()
        local hpBonus, mpBonus = val:getLocalVar('MochiTrustAepHpBonus'), val:getLocalVar('MochiTrustAepMpBonus')
        assert(hpBonus == 3 * xi.test.world:getSetting('main.TRUST_ALTER_EGO_POINT_HP_PER_RANK'))
        assert(mpBonus == 2 * xi.test.world:getSetting('main.TRUST_ALTER_EGO_POINT_MP_PER_RANK'))
        assert(val:getMod(xi.mod.HP) == hpBonus and val:getMod(xi.mod.MP) == mpBonus)
        assert(val:getHP() == hp and val:getMP() == mp, 'a normal summon starts at its native maximum')
        val:setHP(1)
        val:setMP(1)
        val:setTP(1234)
        -- Silence changes no HP/MP modifier but invokes the real effect-gain health calculation.
        assert(val:addStatusEffect(xi.effect.SILENCE, { power = 1, duration = 3, origin = val }))
        assert(val:getMaxHP() == hp and val:getMaxMP() == mp, 'a neutral effect must preserve the native summon maximum')
        assert(val:getMod(xi.mod.HP) == hpBonus and val:getMod(xi.mod.MP) == mpBonus)
        assert(val:getHP() == 1 and val:getMP() == 1 and val:getTP() == 1234, 'recalculation must not refill resources')
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
        local hp, mp, strength = val:getMaxHP(), val:getMaxMP(), val:getStat(xi.mod.STR)
        local hpMod, mpMod, level = val:getMod(xi.mod.HP), val:getMod(xi.mod.MP), val:getLocalVar('MochiTrustJob99StatLevel')
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
        -- Expire naturally after the final equipment refresh; no later level change may repair the caps.
        xi.test.world:skipTime(301)
        assert(not val:hasStatusEffect(xi.effect.WEAKNESS))
        assert(val:getLocalVar('MochiTrustJob99StatLevel') == level)
        assert(val:getMaxHP() == hp and val:getMaxMP() == mp, 'natural Weakness expiry must restore the original native maximum')
        assert(val:getMod(xi.mod.HP) == hpMod and val:getMod(xi.mod.MP) == mpMod and val:getStat(xi.mod.STR) == strength)
        assert(val:getHP() < hp and val:getMP() < mp, 'expiry may permit native recovery ticks but must not refill either resource')
    end)

    it('uses the current retail base gains and clamps consumed ranks without rewriting progression', function()
        assert(xi.test.world:getSetting('main.TRUST_ALTER_EGO_POINT_HP_PER_RANK') == 5, 'the shipped retail HP base gain must be 5')
        assert(xi.test.world:getSetting('main.TRUST_ALTER_EGO_POINT_MP_PER_RANK') == 2, 'the shipped retail MP base gain must be 2')
        local rankedOwner = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE, job = xi.job.PLD, level = 99 })
        rankedOwner:setCharVar('AlterEgoPoints_HP', 60)
        rankedOwner:setCharVar('AlterEgoPoints_MP', 61)
        local ranked = assert(rankedOwner:spawnTrust(xi.magic.spell.VALAINERAL))
        ranked:removeAllGambits()
        ranked:setAutoAttackEnabled(false)
        assert(ranked:getLocalVar('MochiTrustAepHpRank') == 60 and ranked:getLocalVar('MochiTrustAepMpRank') == 60)
        assert(ranked:getLocalVar('MochiTrustAepHpBonus') == 300 and ranked:getLocalVar('MochiTrustAepMpBonus') == 120)
        assert(ranked:getMod(xi.mod.HP) == 300 and ranked:getMod(xi.mod.MP) == 120)
        assert(rankedOwner:getCharVar('AlterEgoPoints_HP') == 60 and rankedOwner:getCharVar('AlterEgoPoints_MP') == 61)
        local hp, mp = ranked:getMaxHP(), ranked:getMaxMP()
        assert(ranked:addStatusEffect(xi.effect.SILENCE, { power = 1, duration = 3, origin = ranked }))
        assert(ranked:getMaxHP() == hp and ranked:getMaxMP() == mp, 'rank-cap calibration must still count each bonus only once')
    end)

    it('serializes native AEP rank boundaries and authoritative category slots', function()
        local menuOwner = xi.test.world:spawnPlayer({ job = xi.job.PLD, level = 99 })
        menuOwner:gotoMogHouse(xi.zone.WINDURST_WOODS)
        menuOwner:addKeyItem(xi.ki.CIPHER_BRACELET)
        assert(menuOwner:inMogHouse() and menuOwner:getMainLvl() == 99 and menuOwner:hasKeyItem(xi.ki.CIPHER_BRACELET))
        local keys = { 'AlterEgoPoints_HP', 'AlterEgoPoints_MP', 'AlterEgoPoints_CombatSkills', 'AlterEgoPoints_MagicSkills' }
        local indexes = { 8, 9, 17, 18 }
        -- Cost 6 preserves the existing next-cost formula; it is not a new retail-cost claim.
        local boundaries = {
            { input = { 59, 60, 61, 58 }, rank = { 59, 60, 60, 58 }, cost = { 6, 0, 0, 6 } },
            { input = { 60, 61, 58, 59 }, rank = { 60, 60, 58, 59 }, cost = { 0, 0, 6, 6 } },
            { input = { 61, 58, 59, 60 }, rank = { 60, 58, 59, 60 }, cost = { 0, 6, 6, 0 } },
            { input = { 58, 59, 60, 61 }, rank = { 58, 59, 60, 60 }, cost = { 6, 6, 0, 0 } },
        }
        for _, boundary in ipairs(boundaries) do
            for i, key in ipairs(keys) do
                menuOwner:setCharVar(key, boundary.input[i])
            end

            local packet = requestAlterEgoPacket(menuOwner)
            for i, index in ipairs(indexes) do
                expectAlterEgoCategory(packet, index, boundary.rank[i], boundary.cost[i])
                assert(menuOwner:getCharVar(keys[i]) == boundary.input[i], 'menu serialization must not rewrite stored progression')
            end

            expectAlterEgoCategory(packet, 0, boundary.rank[3], boundary.cost[3])
            expectAlterEgoCategory(packet, 1, boundary.rank[4], boundary.cost[4])
        end
    end)
end)
