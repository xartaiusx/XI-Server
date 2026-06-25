-----------------------------------
-- Trust: Qultada
-----------------------------------
---@type TSpellTrust
local spellObject = {}

spellObject.onMagicCastingCheck = function(caster, target, spell)
    return xi.trust.canCast(caster, spell)
end

spellObject.onSpellCast = function(caster, target, spell)
    return xi.trust.spawn(caster, spell)
end

spellObject.onMobSpawn = function(mob)
    xi.trust.message(mob, xi.trust.messageOffset.SPAWN)

    -- Mochirii's Corsair utilities mark eligible rolls with DOUBLE_UP_CHANCE.
    -- Let Qultada press the roll safely instead of guessing roll totals here.
    mob:addGambit(ai.t.SELF, {
        { ai.c.STATUS, xi.effect.DOUBLE_UP_CHANCE },
        { ai.c.TIMER, 8 },
    }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.DOUBLE_UP })

    mob:addGambit(ai.t.PARTY, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.CHAOS_ROLL }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.CHAOS_ROLL })

    if mob:getMainLvl() >= 75 then
        mob:addGambit(ai.t.SELF, {
            { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.SNAKE_EYE },
            { ai.c.NOT_STATUS, xi.effect.DOUBLE_UP_CHANCE },
        }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.SNAKE_EYE }, 60)
    end

    -- Retail Qultada favors Corsair's Roll when EXP/CP bonus effects are active.
    mob:addGambit(ai.t.MASTER, {
        { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.CORSAIRS_ROLL },
        ai.l.OR(
            { ai.c.STATUS, xi.effect.DEDICATION },
            { ai.c.STATUS, xi.effect.COMMITMENT }
        ),
    }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.CORSAIRS_ROLL })

    if mob:getMainLvl() >= 40 then
        mob:addGambit(ai.t.PARTY, {
            { ai.c.MPP_LT, 66 },
            { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.EVOKERS_ROLL },
            { ai.c.NOT_STATUS, xi.effect.CORSAIRS_ROLL },
            { ai.c.NOT_STATUS, xi.effect.FIGHTERS_ROLL },
        }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.EVOKERS_ROLL })
    end

    if mob:getMainLvl() >= 49 then
        mob:addGambit(ai.t.PARTY, {
            { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.HUNTERS_ROLL },
            { ai.c.NOT_STATUS, xi.effect.CORSAIRS_ROLL },
            { ai.c.NOT_STATUS, xi.effect.EVOKERS_ROLL },
            { ai.c.NOT_STATUS, xi.effect.FIGHTERS_ROLL },
        }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.HUNTERS_ROLL })

        mob:addGambit(ai.t.PARTY, {
            { ai.c.NOT_STATUS, xi.effect.FIGHTERS_ROLL },
            { ai.c.NOT_STATUS, xi.effect.CORSAIRS_ROLL },
            { ai.c.NOT_STATUS, xi.effect.HUNTERS_ROLL },
        }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.FIGHTERS_ROLL })
    end

    if mob:getMainLvl() >= 87 then
        mob:addGambit(ai.t.SELF, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.TRIPLE_SHOT }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.TRIPLE_SHOT })
    end

    mob:addGambit(ai.t.TARGET, { ai.c.STATUS_FLAG, xi.effectFlag.DISPELABLE }, { ai.r.MS, ai.s.SPECIFIC, xi.mobSkill.DARK_SHOT }, 45)
    mob:addGambit(ai.t.TARGET, { ai.c.STATUS, xi.effect.DIA }, { ai.r.MS, ai.s.SPECIFIC, xi.mobSkill.LIGHT_SHOT }, 60)

    mob:addGambit(ai.t.TARGET, { ai.c.ALWAYS, 0 }, { ai.r.RATTACK, 0, 0 }, 10)

    -- Notable: Uses a balance of melee and ranged attacks.
    -- TODO: Observe his WS behavior on retail
    mob:setTrustTPSkillSettings(ai.tp.OPENER, ai.s.RANDOM)

    -- https://forum.square-enix.com/ffxi/threads/49425-Dec-10-2015-%28JST%29-Version-Update?p=567979&viewfull=1#post567979
    -- Per the December 10, 2015 update:
    -- "The "Enhanced Magic Accuracy" attribute has been added."
    local power = mob:getMainLvl() / 5
    mob:addMod(xi.mod.MACC, power)

    mob:setLocalVar('TrustParityQultada', 1)
    mob:setLocalVar('TrustParityQultadaV2', 1)
end

spellObject.onMobDespawn = function(mob)
    xi.trust.message(mob, xi.trust.messageOffset.DESPAWN)
end

spellObject.onMobDeath = function(mob)
    xi.trust.message(mob, xi.trust.messageOffset.DEATH)
end

return spellObject
