-----------------------------------
-- Trust: Ulmia
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
    xi.trust.teamworkMessage(mob, {
        [xi.magic.spell.PRISHE] = xi.trust.messageOffset.TEAMWORK_1,
        [xi.magic.spell.MILDAURION] = xi.trust.messageOffset.TEAMWORK_2,
    })

    -- Retail-shaped support priority: emergency protection and MP recovery
    -- first, then march/offensive songs as the normal baseline.
    mob:addGambit(ai.t.PARTY, {
        { ai.c.HPP_LT, 40 },
        { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.SCHERZO },
    }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.SENTINELS_SCHERZO })

    mob:addGambit(ai.t.PARTY, {
        { ai.c.MPP_LT, 75 },
        { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.BALLAD },
    }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.MAGES_BALLAD })

    mob:addGambit(ai.t.SELF, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.MARCH }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.MARCH })
    mob:addGambit(ai.t.SELF, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.PRELUDE }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.PRELUDE })
    mob:addGambit(ai.t.SELF, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.MINUET }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.VALOR_MINUET })
    mob:addGambit(ai.t.SELF, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.MADRIGAL }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.MADRIGAL })

    mob:setAutoAttackEnabled(false)

    mob:setMobMod(xi.mobMod.TRUST_DISTANCE, xi.trust.movementType.MID_RANGE)
    mob:setLocalVar('TrustParityUlmia', 1)
end

spellObject.onMobDespawn = function(mob)
    xi.trust.message(mob, xi.trust.messageOffset.DESPAWN)
end

spellObject.onMobDeath = function(mob)
    xi.trust.message(mob, xi.trust.messageOffset.DEATH)
end

return spellObject
