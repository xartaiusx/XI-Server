-----------------------------------
-- Trust: Selh'teus
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

    mob:addMod(xi.mod.ACC, xi.trust.modGrowthValMax(mob, 100))
    mob:addMod(xi.mod.MACC, xi.trust.modGrowthValMax(mob, 80))
    mob:addMod(xi.mod.REGAIN, 50)
    mob:addMod(xi.mod.DMG, -500)

    mob:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 60 }, { ai.c.TP_GTE, 1000 } }, { ai.r.MS, ai.s.SPECIFIC, 1509 }, 45) -- Rejuvenation
    mob:addGambit(ai.t.PARTY, { { ai.c.MPP_LT, 50 }, { ai.c.TP_GTE, 1000 } }, { ai.r.MS, ai.s.SPECIFIC, 1509 }, 45) -- Rejuvenation
    mob:addGambit(ai.t.TARGET, { ai.c.ALWAYS, 0 }, { ai.r.MS, ai.s.SPECIFIC, 1508 }, 60) -- Luminous Lance

    mob:setTrustTPSkillSettings(ai.tp.CLOSER_UNTIL_TP, ai.s.RANDOM, 2000)
    mob:setLocalVar('TrustParitySelhteus', 1)
end

spellObject.onMobDespawn = function(mob)
    xi.trust.message(mob, xi.trust.messageOffset.DESPAWN)
end

spellObject.onMobDeath = function(mob)
    xi.trust.message(mob, xi.trust.messageOffset.DEATH)
end

return spellObject
