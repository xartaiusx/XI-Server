-----------------------------------
-- Spell: Enlight II
-- PLD99, 100 spent job points. See the documented potency-model uncertainty.
-----------------------------------
---@type TSpell
local spellObject = {}

spellObject.onMagicCastingCheck = function(caster, target, spell)
    if
        not caster:isDevelopedTrust() or
        not caster:hasMainJobAccess(xi.job.PLD) or
        caster:getMainLvl() < 99
    then
        return xi.msg.basic.MAGIC_CANNOT_BE_CAST
    end

    return 0
end

spellObject.onSpellCast = function(caster, target, spell)
    local potency = xi.job_utils.paladin.enlightIIPotency(
        target:getSkillLevel(xi.skill.DIVINE_MAGIC), caster:getJobPointLevel(xi.jp.ENLIGHT_EFFECT))

    if target:addStatusEffect(xi.effect.ENLIGHT, { power = potency, duration = 180, tier = 2, origin = caster }) then
        spell:setMsg(xi.msg.basic.MAGIC_GAIN_EFFECT)
    else
        spell:setMsg(xi.msg.basic.MAGIC_NO_EFFECT)
    end

    return xi.effect.ENLIGHT
end

return spellObject
