-----------------------------------
-- Trust: Lilisette II
-----------------------------------
---@type TSpellTrust
local spellObject = {}

spellObject.onMagicCastingCheck = function(caster, target, spell)
    return xi.trust.canCast(caster, spell, xi.magic.spell.LILISETTE)
end

spellObject.onSpellCast = function(caster, target, spell)
    return xi.trust.spawn(caster, spell)
end

spellObject.onMobSpawn = function(mob)
    xi.trust.message(mob, xi.trust.messageOffset.SPAWN)

    -- Mochirii retail-player parity: Lilisette II should behave as a
    -- competent DNC-style melee support where local Trust-safe DNC tools exist.
    mob:addMobMod(xi.mobMod.CAN_PARRY, 1)
    mob:addMod(xi.mod.ACC, xi.trust.modGrowthValMax(mob, 100))
    mob:addMod(xi.mod.EVA, xi.trust.modGrowthValMax(mob, 80))
    mob:addMod(xi.mod.DOUBLE_ATTACK, xi.trust.modGrowthValMax(mob, 10))

    mob:addGambit(ai.t.SELF, { ai.c.NO_SAMBA, 0 }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.HASTE_SAMBA })
    mob:addGambit(ai.t.TARGET, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.SLUGGISH_DAZE_5 }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.BOX_STEP }, 20)
    mob:addGambit(ai.t.TARGET, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.LETHARGIC_DAZE_5 }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.QUICKSTEP }, 20)
    mob:addGambit(ai.t.TARGET, { { ai.c.READYING_WS, 0 }, { ai.c.CASTER_STATUS, xi.effect.FINISHING_MOVE_1 } }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.VIOLENT_FLOURISH })
    mob:addGambit(ai.t.TARGET, { { ai.c.READYING_MS, 0 }, { ai.c.CASTER_STATUS, xi.effect.FINISHING_MOVE_1 } }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.VIOLENT_FLOURISH })
    mob:addGambit(ai.t.TARGET, { { ai.c.READYING_JA, 0 }, { ai.c.CASTER_STATUS, xi.effect.FINISHING_MOVE_1 } }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.VIOLENT_FLOURISH })
    mob:addGambit(ai.t.TARGET, { { ai.c.CASTING_MA, 0 }, { ai.c.CASTER_STATUS, xi.effect.FINISHING_MOVE_1 } }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.VIOLENT_FLOURISH })
    mob:addGambit(ai.t.PARTY, { ai.c.HPP_LT, 35 }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.DIVINE_WALTZ }, 30)
    mob:addGambit(ai.t.PARTY, { ai.c.HPP_LT, 60 }, { ai.r.JA, ai.s.HIGHEST_WALTZ, xi.ja.CURING_WALTZ })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS_FLAG, xi.effectFlag.WALTZABLE }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.HEALING_WALTZ })
    mob:addGambit(ai.t.SELF, { ai.c.STATUS, xi.effect.FINISHING_MOVE_5 }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.REVERSE_FLOURISH }, 60)

    mob:setTrustTPSkillSettings(ai.tp.CLOSER_UNTIL_TP, ai.s.RANDOM, 2000)
    mob:setLocalVar('TrustParityLilisetteII', 1)
end

spellObject.onMobDespawn = function(mob)
    xi.trust.message(mob, xi.trust.messageOffset.DESPAWN)
end

spellObject.onMobDeath = function(mob)
    xi.trust.message(mob, xi.trust.messageOffset.DEATH)
end

return spellObject
