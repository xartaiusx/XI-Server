-----------------------------------
-- Developed-Trust action formula boundaries. Native execution and AI tests
-- are separate from these assertions about the shared Lua consumers.
-----------------------------------
describe('Valaineral action formula boundaries', function()
    local owner
    local val
    local dummyId

    before_each(function()
        xi.test.world:setSetting('main.TRUST_JOB99_VALAINERAL', true)
        xi.test.world:setSetting('main.USE_ADOULIN_WEAPON_SKILL_CHANGES', true)
        owner = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE, job = xi.job.PLD, level = 99 })
        val = owner:spawnTrust(xi.magic.spell.VALAINERAL)
        assert(val)
        val:removeAllGambits()
        val:setAutoAttackEnabled(false)
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

    it('converts native merit values at the actual meritWS consumers', function()
        assert(val:getMerit(xi.merit.REQUIESCAT) == 15)
        assert(val:getMerit(xi.merit.RESOLUTION) == 9)
        assert(val:getMerit(xi.merit.UPHEAVAL) == 3)
        assert(xi.weaponskills.getMeritRanks(val, xi.merit.REQUIESCAT) == 5)
        assert(xi.weaponskills.getMeritRanks(val, xi.merit.RESOLUTION) == 3)
        assert(xi.weaponskills.getMeritRanks(val, xi.merit.UPHEAVAL) == 1)

        local mob = owner:getZone():insertDynamicEntity({
            objtype              = xi.objType.MOB,
            name                 = 'Job99_Formula',
            groupId              = 5,
            groupZoneId          = 154,
            minLevel             = 1,
            maxLevel             = 1,
            respawn              = 0,
            releaseIdOnDisappear = true,
        })
        assert(mob)
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

        local modifiers = {}
        local resolution = require('scripts.actions.weaponskills.resolution')
        stub('xi.weaponskills.doPhysicalWeaponskill', function(actor, target, id, params, tp, action, primary, taChar)
            modifiers[id] = params
            if id == xi.weaponskill.REQUIESCAT then
                -- Reuse the real action only inside its native callback frame.
                -- Resolution's parameter callback is checked here; its native
                -- off-weapon rejection is covered by job99_valaineral.lua.
                resolution.onUseWeaponSkill(actor, target, xi.weaponskill.RESOLUTION, tp, primary, action, taChar)
            end

            return 0, false, 0, 0
        end)

        val:setTP(3000)
        assert(owner.actions:useTrustWeaponskill(val, mob, xi.weaponskill.REQUIESCAT))
        xi.test.world:tickEntity(val)
        xi.test.world:skipTime(3)
        assert(modifiers[xi.weaponskill.REQUIESCAT] and modifiers[xi.weaponskill.RESOLUTION])
        assert(math.abs(modifiers[xi.weaponskill.REQUIESCAT].mnd_wsc - 0.85) < 0.000001)
        assert(math.abs(modifiers[xi.weaponskill.RESOLUTION].str_wsc - 0.79) < 0.000001)
    end)

    it('keeps the documented EnlightII model continuous at500 and adds JP once', function()
        -- This is the published measurement model, not a claim of exact retail
        -- parity at unmeasured skill values; see the capability catalog.
        local potency = xi.job_utils.paladin.enlightIIPotency
        assert(potency(424, 0) == 97)
        assert(potency(424, 20) == 117)
        assert(potency(500, 0) == 112)
        assert(potency(501, 0) == 112)
        assert(potency(605, 0) == 125)
        assert(potency(605, 20) == 145)
    end)

    it('adds DivineEmblem JP as40 base divine damage and never to elemental spells', function()
        local base = xi.spells.damage.calculateBaseDamage
        local function divine()
            return base(val, owner, xi.magic.spell.HOLY_II, xi.magic.spellGroup.WHITE, xi.skill.DIVINE_MAGIC, xi.mod.MND)
        end

        local function elemental()
            return base(val, owner, xi.magic.spell.FIRE, xi.magic.spellGroup.BLACK, xi.skill.ELEMENTAL_MAGIC, xi.mod.INT)
        end

        local divineBefore, elementalBefore = divine(), elemental()
        val:addStatusEffect(xi.effect.DIVINE_EMBLEM, { power = 50, duration = 60, origin = val })
        assert(divine() - divineBefore == 40)
        assert(elemental() == elementalBefore)
        val:delStatusEffect(xi.effect.DIVINE_EMBLEM)
        assert(divine() == divineBefore)
    end)
end)
