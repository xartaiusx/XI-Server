-----------------------------------
-- Approved Valaineral Intervene: native action completion and restrictions.
-- The inherited base-damage model remains unverified retail behavior.
-----------------------------------
describe('Valaineral developed Intervene', function()
    local owner
    local val
    local mob
    local dummyId

    local function finish()
        xi.test.world:tickEntity(val)
        xi.test.world:skipTime(1)
        xi.test.world:skipTime(3)
    end

    before_each(function()
        xi.test.world:setSetting('main.TRUST_JOB99_VALAINERAL', true)
        xi.test.world:setSetting('main.ENABLE_TRUST_ALTER_EGO_POINT_BONUSES', false)
        xi.test.world:setSetting('main.ENABLE_TRUST_UNITY_RANK_STAT_PARITY', false)
        xi.test.world:setSetting('map.ALTER_EGO_SKILL_MULTIPLIER', 1)
        owner = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE, job = xi.job.PLD, level = 99 })
        val = owner:spawnTrust(xi.magic.spell.VALAINERAL)
        assert(val)
        val:removeAllGambits()
        val:setAutoAttackEnabled(false)
        val:setMobAbilityEnabled(false)
        val:setMobMod(xi.mobMod.NO_MOVE, 1)
        mob = owner:getZone():insertDynamicEntity({
            objtype              = xi.objType.MOB,
            name                 = 'Job99_Intervene',
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
        mob:setPos(owner:getXPos(), owner:getYPos(), owner:getZPos())
        val:setPos(owner:getXPos() + 1, owner:getYPos(), owner:getZPos())
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

    it('applies real HP damage with the forty-percent action-point bonus and shared secondSP recast', function()
        -- Native Valaineral has a modeled size-three shield, not player inventory.
        assert(val:getShieldSize() == 3)
        assert(val:getJobPointLevel(xi.jp.INTERVENE_EFFECT) == 20)
        local nativeBase = math.floor(val:getMainLvl() * 3.36) + 40
        local expected = math.floor(nativeBase * 1.4)
        local hp, attack, accuracy = mob:getHP(), mob:getStat(xi.mod.ATT), mob:getACC()
        assert(owner.actions:useTrustAbility(val, mob, xi.jobAbility.INTERVENE))
        finish()
        assert(hp - mob:getHP() == expected, 'the reported model damage must be applied exactly once')
        assert(expected > nativeBase, 'JP twenty must affect actual damage, not only the action packet')
        assert(mob:hasStatusEffect(xi.effect.INTERVENE))
        assert(mob:getStat(xi.mod.ATT) < attack and mob:getACC() < accuracy)
        assert(val:hasRecast(xi.recast.ABILITY, xi.recastID.SPECIAL2))
        assert(not owner.actions:useTrustAbility(val, val, xi.jobAbility.BRAZEN_RUSH))
        assert(not val:hasRecast(xi.recast.ABILITY, xi.recastID.SPECIAL))
        mob:delStatusEffect(xi.effect.INTERVENE)
        assert(mob:getStat(xi.mod.ATT) == attack and mob:getACC() == accuracy)
    end)

    it('honors native Stoneskin before applying the action damage', function()
        mob:addStatusEffect(xi.effect.STONESKIN, { power = 1000, duration = 60, origin = mob })
        local hp = mob:getHP()
        assert(owner.actions:useTrustAbility(val, mob, xi.jobAbility.INTERVENE))
        finish()
        assert(mob:getHP() == hp, 'Stoneskin must absorb the actual physical action damage')
        assert(mob:getStatusEffect(xi.effect.STONESKIN):getPower() == 480)
        assert(mob:hasStatusEffect(xi.effect.INTERVENE))
        assert(val:hasRecast(xi.recast.ABILITY, xi.recastID.SPECIAL2))
    end)

    it('rejects Amnesia and out-of-range attempts without damage, effects or recast', function()
        local hp = mob:getHP()
        val:addStatusEffect(xi.effect.AMNESIA, { power = 1, duration = 60, origin = val })
        assert(not owner.actions:useTrustAbility(val, mob, xi.jobAbility.INTERVENE))
        val:delStatusEffect(xi.effect.AMNESIA)
        val:setPos(mob:getXPos() + 100, mob:getYPos(), mob:getZPos())
        assert(not owner.actions:useTrustAbility(val, mob, xi.jobAbility.INTERVENE))
        assert(mob:getHP() == hp and not mob:hasStatusEffect(xi.effect.INTERVENE))
        assert(not val:hasRecast(xi.recast.ABILITY, xi.recastID.SPECIAL2))
        val:setPos(mob:getXPos() + 1, mob:getYPos(), mob:getZPos())
        assert(owner.actions:useTrustAbility(val, mob, xi.jobAbility.INTERVENE))
        finish()
        assert(mob:getHP() < hp, 'rejected conditions must not poison the next valid action')
    end)

    it('preserves the native missing-shield check for an unequipped PC', function()
        -- Trust shieldSize() defaults to three, so zero is not a legal Val model.
        -- Exercise the real zero-shield actor instead of inventing a Trust override.
        assert(owner:getShieldSize() == 0)
        local hp = mob:getHP()
        owner.actions:useAbility(mob, xi.jobAbility.INTERVENE)
        xi.test.world:tickEntity(owner)
        xi.test.world:skipTime(3)
        assert(mob:getHP() == hp and not mob:hasStatusEffect(xi.effect.INTERVENE))
        assert(not owner:hasRecast(xi.recast.ABILITY, xi.recastID.SPECIAL2))
    end)
end)
