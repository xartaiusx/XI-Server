-----------------------------------
-- Approved Valaineral Holy Circle: missing native damage-path consumers.
-- Source-model regressions, not a claim of exact retail rounding or JP units.
-----------------------------------
describe('Valaineral developed Holy Circle', function()
    local owner
    local val
    local undead
    local notorious
    local other
    local dummyIds

    local function finish(actor, seconds)
        xi.test.world:tickEntity(actor)
        xi.test.world:skipTime(seconds or 3)
        xi.test.world:skipTime(3)
        for _, packet in ipairs(owner.packets:actionPackets()) do
            assert(packet.m_uID ~= owner:getID() or packet.cmd_no ~= xi.action.category.BASIC_ATTACK,
                'the fixture owner must not contaminate Trust-only damage with a native swing')
        end
    end

    local function engageOwnerFacingAway()
        owner.actions:engage(undead)
        local x, y, z = owner:getXPos(), owner:getYPos(), owner:getZPos()
        -- Native PC CanAttack uses facing rather than the controller's mob-only attack flag.
        owner:lookAt(2 * x - undead:getXPos(), y, 2 * z - undead:getZPos())
        assert(not owner:isFacing(undead), 'the engaged fixture owner must face away from the sampled target')
    end

    local function dummy(group, zone, name)
        local mob = owner:getZone():insertDynamicEntity({
            objtype              = xi.objType.MOB,
            name                 = name,
            groupId              = group,
            groupZoneId          = zone,
            minLevel             = 99,
            maxLevel             = 99,
            respawn              = 0,
            releaseIdOnDisappear = true,
        })
        assert(mob)
        table.insert(dummyIds, mob:getID())
        SpawnMob(mob:getID())
        mob:setMaxHP(1000000)
        mob:setHP(1000000)
        mob:setUnkillable(true)
        mob:setAutoAttackEnabled(false)
        mob:setMagicCastingEnabled(false)
        mob:setMobAbilityEnabled(false)
        mob:setMobMod(xi.mobMod.NO_MOVE, 1)
        mob:setMobMod(xi.mobMod.NO_REST, 1) -- Keep the controlled damage samples free of native idle regeneration.
        mob:setDropID(0)
        mob:setPos(owner:getXPos() + 1, owner:getYPos(), owner:getZPos())
        for _, mod in ipairs({
            xi.mod.UDMGPHYS, xi.mod.DMGPHYS, xi.mod.DMGPHYS_II,
            xi.mod.UDMGMAGIC, xi.mod.DMGMAGIC, xi.mod.DMGMAGIC_II,
            xi.mod.UDMGRANGE, xi.mod.DMGRANGE, xi.mod.UDMGBREATH, xi.mod.DMGBREATH,
            xi.mod.DMG, xi.mod.PHALANX, xi.mod.SLASH_SDT, xi.mod.PIERCE_SDT,
            xi.mod.IMPACT_SDT, xi.mod.HTH_SDT,
        }) do
            mob:setMod(mod, 0)
        end

        return mob
    end

    local function circle()
        assert(owner.actions:useTrustAbility(val, val, xi.jobAbility.HOLY_CIRCLE))
        finish(val)
        assert(val:hasStatusEffect(xi.effect.HOLY_CIRCLE))
        assert(owner:hasStatusEffect(xi.effect.HOLY_CIRCLE), 'the ordinary party recipient must receive the real action')
    end

    local function packetDamage(actor, target, category)
        local total = 0
        local count = 0
        for _, packet in ipairs(owner.packets:actionPackets()) do
            if packet.m_uID == actor:getID() and packet.cmd_no == category then
                for _, victim in ipairs(packet.target) do
                    if victim.m_uID == target:getID() then
                        for _, result in ipairs(victim.result) do
                            total = total + result.value
                            if result.value > 0 then
                                count = count + 1
                            end
                        end
                    end
                end
            end
        end

        return total, count
    end

    local function damageEvidence(actor, target, category, damage)
        local reported, count = packetDamage(actor, target, category)
        local packets = {}
        for _, packet in ipairs(owner.packets:actionPackets()) do
            table.insert(packets, string.format('%d/%d/%d', packet.m_uID, packet.cmd_no, packet.trg_sum))
        end

        return string.format('actor=%d target=%d category=%d HPdamage=%d reported=%d hits=%d packets=%s',
            actor:getID(), target:getID(), category, damage, reported, count, table.concat(packets, ','))
    end

    local function abilityDamage(id)
        owner.packets:clear()
        local hp = undead:getHP()
        assert(owner.actions:useTrustAbility(val, undead, id))
        finish(val)
        local damage = hp - undead:getHP()
        assert(damage > 0)
        -- Both native damaging JAs use SkillFinish (3), not AbilityFinish (6).
        assert(packetDamage(val, undead, xi.action.category.WEAPONSKILL_FINISH) == damage,
            damageEvidence(val, undead, xi.action.category.WEAPONSKILL_FINISH, damage))
        return damage
    end

    local function weaponDamage(id)
        -- Measure this WS's Circle term independently of prior resonance damage.
        undead:delStatusEffect(xi.effect.SKILLCHAIN)
        undead:delStatusEffect(xi.effect.CHAINBOUND)
        assert(not undead:hasStatusEffect(xi.effect.SKILLCHAIN) and not undead:hasStatusEffect(xi.effect.CHAINBOUND))
        undead:addBaseEnmity(val)
        undead:setCE(val, 6000)
        undead:setVE(val, 6000)
        val:setTP(3000)
        owner.packets:clear()
        local hp = undead:getHP()
        assert(owner.actions:useTrustWeaponskill(val, undead, id))
        finish(val)
        local damage = hp - undead:getHP()
        assert(damage > 0 and val:getTP() < 1000)
        assert(packetDamage(val, undead, xi.action.category.WEAPONSKILL_FINISH) == damage,
            damageEvidence(val, undead, xi.action.category.WEAPONSKILL_FINISH, damage))
        return damage
    end

    before_each(function()
        dummyIds = {}
        xi.test.world:setSetting('main.TRUST_JOB99_VALAINERAL', true)
        xi.test.world:setSetting('main.ENABLE_TRUST_ALTER_EGO_POINT_BONUSES', false)
        xi.test.world:setSetting('main.ENABLE_TRUST_UNITY_RANK_STAT_PARITY', false)
        xi.test.world:setSetting('map.ALTER_EGO_SKILL_MULTIPLIER', 1)
        xi.test.world:setSetting('map.ENABLE_AUTO_ATTACK_LUA', false)
        xi.test.world:setSeed(123456)
        stub('xi.combat.physicalHitRate.getPhysicalHitRate', 1)
        stub('xi.combat.physical.isParried', false)
        stub('xi.combat.physical.isGuarded', false)
        stub('xi.combat.physical.isBlocked', false)
        stub('xi.combat.physical.calculateMeleePDIF', 1)
        stub('xi.combat.magicHitRate.calculateResistRate', 1)
        stub('xi.spells.damage.calculateDayAndWeather', 1)
        stub('xi.spells.damage.calculateMagicCriticalMultiplier', 1)
        stub('math.randomInt', function(minimum)
            return minimum
        end)

        owner = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE, job = xi.job.PLD, level = 99 })
        owner:setUnkillable(true)
        val = owner:spawnTrust(xi.magic.spell.VALAINERAL)
        assert(val)
        val:removeAllGambits()
        val:setAutoAttackEnabled(false)
        val:setMobAbilityEnabled(false)
        val:setUnkillable(true)
        val:setMobMod(xi.mobMod.NO_MOVE, 1)
        val:setPos(owner:getXPos(), owner:getYPos(), owner:getZPos())
        val:setMod(xi.mod.DOUBLE_ATTACK, 0)
        val:setMod(xi.mod.TRIPLE_ATTACK, 0)
        val:setMod(xi.mod.QUAD_ATTACK, 0)
        -- Immutable public SQL: Draugar1110 is undead/normal; BlackBartholomew432
        -- is undead/notorious; Fafnir1280 is a non-undead negative control.
        undead = dummy(26, 55, 'Circle_Undead')
        notorious = dummy(2018, 60, 'Circle_NM')
        other = dummy(5, 154, 'Circle_Other')
        assert(undead:isUndead() and not undead:isNM())
        assert(notorious:isUndead() and notorious:isNM())
        assert(not other:isUndead())
        local x, y, z = owner:getXPos(), owner:getYPos(), owner:getZPos()
        local visible = owner.entities:moveTo(undead) -- Refresh native self-centered AoE targets.
        assert(visible and visible:getID() == undead:getID())
        owner:setPos(x, y, z)
        engageOwnerFacingAway()
        val:engage(undead:getTargID())
    end)

    after_each(function()
        for _, id in ipairs(dummyIds) do
            if GetEntityByID(id, nil, true) then
                DespawnMob(id)
                for _ = 1, 10 do
                    xi.test.world:tick()
                    if GetEntityByID(id, nil, true) == nil then
                        break
                    end
                end

                assert(GetEntityByID(id, nil, true) == nil)
            end
        end
    end)

    it('uses exact cast provenance, ordinary party recipients and existing NM halves', function()
        circle()
        local effect = val:getStatusEffect(xi.effect.HOLY_CIRCLE)
        assert(effect:getSourceType() == xi.effectSourceType.DEVELOPED_TRUST)
        assert(effect:getSourceTypeParam() == xi.magic.spell.VALAINERAL)
        assert(effect:getOriginID() == val:getID())
        assert(math.abs(val:getDevelopedHolyCircleMultiplier(undead) - 1.15) < 0.0001)
        assert(math.abs(val:getDevelopedHolyCircleMultiplier(notorious) - 1.07) < 0.0001)
        assert(val:getDevelopedHolyCircleMultiplier(other) == 1)
        assert(math.abs(undead:getDevelopedHolyCircleMultiplier(val) - 0.65) < 0.0001)
        assert(math.abs(notorious:getDevelopedHolyCircleMultiplier(val) - 0.83) < 0.0001)
        assert(math.abs(owner:getDevelopedHolyCircleMultiplier(undead) - 1.15) < 0.0001)
        -- Native JP effect initialization reads the recipient's own JP category.
        assert(math.abs(undead:getDevelopedHolyCircleMultiplier(owner) - 0.85) < 0.0001)
    end)

    it('leaves a PC-origin Circle outside the new native adapter', function()
        owner.actions:useAbility(owner, xi.jobAbility.HOLY_CIRCLE)
        finish(owner)
        assert(owner:hasStatusEffect(xi.effect.HOLY_CIRCLE))
        assert(owner:getStatusEffect(xi.effect.HOLY_CIRCLE):getSourceType() == xi.effectSourceType.NONE)
        assert(owner:getDevelopedHolyCircleMultiplier(undead) == 1)
        assert(undead:getDevelopedHolyCircleMultiplier(owner) == 1)
    end)

    it('retains the snapshot after caster dismissal and removes it on ordinary expiration', function()
        circle()
        local id = val:getID()
        owner.actions:trigger(val)
        finish(owner)
        assert(not owner.actions:hasTrustEntity(id))
        xi.test.world:setSetting('main.TRUST_JOB99_VALAINERAL', false)
        assert(math.abs(owner:getDevelopedHolyCircleMultiplier(undead) - 1.15) < 0.0001)
        xi.test.world:skipTime(181)
        assert(not owner:hasStatusEffect(xi.effect.HOLY_CIRCLE))
        assert(owner:getDevelopedHolyCircleMultiplier(undead) == 1)
        assert(owner:getMod(xi.mod.UNDEAD_DMG_MULTIPLIER) == 0)
    end)

    it('applies the modeled native melee bonus with packet and HP agreement', function()
        engageOwnerFacingAway()
        local function swing()
            owner.packets:clear()
            local hp = undead:getHP()
            val:setAutoAttackEnabled(true)
            val:engage(undead:getTargID())
            val:lookAt(undead:getPos())
            -- Wait for one actual native swing, including any existing action lock.
            -- Do not requeue the attack or assume skipped seconds equal engine ticks.
            for _ = 1, 12 do
                xi.test.world:tickEntity(val)
                xi.test.world:skipTime(1)
                local _, count = packetDamage(val, undead, xi.action.category.BASIC_ATTACK)
                if count > 0 then
                    break
                end
            end

            val:setAutoAttackEnabled(false)
            local damage = hp - undead:getHP()
            assert(damage > 0, damageEvidence(val, undead, xi.action.category.BASIC_ATTACK, damage))
            local reported, count = packetDamage(val, undead, xi.action.category.BASIC_ATTACK)
            assert(reported == damage and count > 0,
                damageEvidence(val, undead, xi.action.category.BASIC_ATTACK, damage))
            return damage / count
        end

        local base = swing()
        circle()
        local enhanced = swing()
        assert(math.abs(enhanced - base * 1.15) < 3)
    end)

    it('applies the native incoming undead resistance before HP and packet values', function()
        engageOwnerFacingAway()
        local function incoming()
            val:setHP(val:getMaxHP()) -- Isolate this sample from the previous sample's damage.
            val:setMod(xi.mod.UNDEAD_KILLER, 0)
            undead:addBaseEnmity(val)
            undead:updateEnmity(val)
            undead:setCE(val, 10000)
            undead:setVE(val, 10000)
            undead:engage(val:getTargID())
            local target = undead:getTarget()
            assert(target and target:getID() == val:getID(), 'incoming damage must target this Valaineral')
            owner.packets:clear()
            local hp = val:getHP()
            undead:setAutoAttackEnabled(true)
            finish(undead, 4)
            undead:setAutoAttackEnabled(false)
            local damage = hp - val:getHP()
            assert(damage > 0)
            local reported, count = packetDamage(undead, val, xi.action.category.BASIC_ATTACK)
            assert(reported == damage and count > 0)
            return damage / count
        end

        local base = incoming()
        circle()
        val:setMod(xi.mod.UNDEAD_KILLER, 0) -- Isolate resistance from the separate intimidation proc.
        local reduced = incoming()
        assert(math.abs(reduced - base * 0.65) < 3)
    end)

    it('applies Circle to actual ShieldBash and Intervene damage once', function()
        circle()
        local bash = abilityDamage(xi.jobAbility.SHIELD_BASH)
        assert(bash == math.floor(math.floor((math.floor(99 * 0.273) + 40 + 200) * 1.01) * 1.15))
        local intervene = abilityDamage(xi.jobAbility.INTERVENE)
        assert(intervene == math.floor((math.floor(99 * 3.36) + 40) * 1.4 * 1.15))
    end)

    it('does not apply a second Circle term to the existing divine-spell path', function()
        local function holy()
            owner.packets:clear()
            local hp = undead:getHP()
            assert(owner.actions:useTrustSpell(val, undead, xi.magic.spell.HOLY_II))
            finish(val, 5)
            local damage = hp - undead:getHP()
            assert(damage > 0)
            assert(packetDamage(val, undead, xi.action.category.MAGIC_FINISH) == damage,
                damageEvidence(val, undead, xi.action.category.MAGIC_FINISH, damage))
            return damage
        end

        local base = holy()
        xi.test.world:skipTime(40)
        circle()
        local enhanced = holy()
        assert(math.abs(enhanced - base * 1.15) < 3)
        assert(enhanced < base * 1.2, 'the existing ecosystem consumer must not be squared')
    end)

    it('does not apply a second Circle term to an existing native breath move', function()
        engageOwnerFacingAway()
        val:setMod(xi.mod.UDMGBREATH, 0)
        val:setMod(xi.mod.DMGBREATH, 0)
        val:setMod(xi.mod.DMG, 0)
        val:setMod(xi.mod.FIRE_SDT, 0)
        local function breath()
            val:setHP(val:getMaxHP())
            undead:addBaseEnmity(val)
            undead:updateEnmity(val)
            undead:setCE(val, 10000)
            undead:setVE(val, 10000)
            undead:engage(val:getTargID()) -- Keep its HP stable in combat until the skill snapshots it.
            local target = undead:getTarget()
            assert(target and target:getID() == val:getID())
            undead:setHP(1000) -- Ten percent stays below Flame Breath's400 damage cap.
            assert(undead:getHP() == 1000 and val:getHP() > 400)
            undead:setTP(3000)
            owner.packets:clear()
            local hp = val:getHP()
            -- Active sql/mob_skills.sql ID642 has no Lua enum in this snapshot.
            undead:useMobAbility(642, val, 2000)
            finish(undead, 4)
            local damage = hp - val:getHP()
            assert(undead:getHP() == 1000, 'the sampled breath source HP must remain 1000, observed ' .. undead:getHP())
            assert(damage > 0)
            assert(packetDamage(undead, val, xi.action.category.MOBABILITY_FINISH) == damage)
            return damage
        end

        val:setMod(xi.mod.UNDEAD_KILLER, 0) -- Isolate damage resistance from intimidation.
        assert(breath() == 100)
        circle()
        val:setMod(xi.mod.UNDEAD_KILLER, 0)
        assert(breath() == 65, 'the existing breath ecosystem path must apply the resistance only once')
    end)

    it('applies the model to the preserved native Uriel mob-skill body', function()
        local function uriel()
            val:setTP(3000)
            owner.packets:clear()
            local hp = undead:getHP()
            val:useMobAbility(xi.mobSkill.URIEL_BLADE_1, undead, 2000)
            finish(val, 4)
            local damage = hp - undead:getHP()
            assert(damage > 0)
            local reported = packetDamage(val, undead, xi.action.category.MOBABILITY_FINISH) +
                packetDamage(val, undead, xi.action.category.WEAPONSKILL_FINISH)
            assert(reported == damage,
                string.format('combined=%d; %s; %s', reported,
                    damageEvidence(val, undead, xi.action.category.MOBABILITY_FINISH, damage),
                    damageEvidence(val, undead, xi.action.category.WEAPONSKILL_FINISH, damage)))
            return damage
        end

        local base = uriel()
        circle()
        assert(math.abs(uriel() - base * 1.15) < 3)
    end)

    it('uses the model once in physical, magical and special SwordWS with native HP damage', function()
        local ids = {
            xi.weaponskill.REQUIESCAT, xi.weaponskill.SERAPH_BLADE,
            xi.weaponskill.ATONEMENT, xi.weaponskill.SPIRITS_WITHIN,
        }
        local base = {}
        for _, id in ipairs(ids) do
            base[id] = weaponDamage(id)
        end

        circle()
        for _, id in ipairs(ids) do
            local enhanced = weaponDamage(id)
            assert(math.abs(enhanced - base[id] * 1.15) < 8, 'per-hit flooring may differ from final-total rounding')
            assert(enhanced < base[id] * 1.2)
        end
    end)

    it('does not square the physical term inherited by controlled hybrid magic', function()
        local physical = xi.weaponskills.doPhysicalWeaponskill
        stub('xi.weaponskills.doPhysicalWeaponskill', function(actor, target, id, _, tp, action, primary, taChar)
            return physical(actor, target, id, {
                numHits = 1, ftpMod = { 1, 1, 1 }, hybridWS = true,
                ele = xi.element.FIRE, skill = xi.skill.SWORD, includemab = true,
            }, tp, action, primary, taChar)
        end)

        stub('addBonusesAbility', function(_, _, _, damage)
            return damage
        end)

        local base = weaponDamage(xi.weaponskill.REQUIESCAT)
        circle()
        local enhanced = weaponDamage(xi.weaponskill.REQUIESCAT)
        assert(math.abs(enhanced - base * 1.15) < 4)
        assert(enhanced < base * 1.2)
    end)
end)
