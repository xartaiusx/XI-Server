-----------------------------------
-- Trust: Matsui-P
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

    mob:addMobMod(xi.mobMod.CAN_PARRY, 3)
    mob:addMod(xi.mod.DUAL_WIELD, 25)
    mob:addMod(xi.mod.FASTCAST, 30)
    mob:addMod(xi.mod.ACC, xi.trust.modGrowthValMax(mob, 120))
    mob:addMod(xi.mod.EVA, xi.trust.modGrowthValMax(mob, 120))
    mob:addMod(xi.mod.UTSUSEMI_BONUS, 1)

    mob:setSpellList(435)

    mob:addGambit(ai.t.SELF, { ai.c.NOT_STATUS, xi.effect.COPY_IMAGE }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.UTSUSEMI })
    mob:addGambit(ai.t.TARGET, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.BLINDNESS }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.KURAYAMI }, 30)
    mob:addGambit(ai.t.TARGET, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.SLOW }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.HOJO }, 30)
    mob:addGambit(ai.t.TARGET, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.PARALYSIS }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.JUBAKU }, 45)
    mob:addGambit(ai.t.TARGET, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.POISON }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.DOKUMORI }, 60)

    mob:setTrustTPSkillSettings(ai.tp.CLOSER_UNTIL_TP, ai.s.RANDOM, 2000)
    mob:setLocalVar('TrustParityMatsuiP', 1)
end

spellObject.onMobDespawn = function(mob)
    xi.trust.message(mob, xi.trust.messageOffset.DESPAWN)
end

spellObject.onMobDeath = function(mob)
    xi.trust.message(mob, xi.trust.messageOffset.DEATH)
end

return spellObject
