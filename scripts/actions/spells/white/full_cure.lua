-----------------------------------
-- Spell: Full Cure
-- Consumes remaining MP when the cast completes.
-----------------------------------
local healing = require('scripts/globals/spells/healing_spell')

---@type TSpell
local spellObject = {}

spellObject.onMagicCastingCheck = function(caster, target, spell)
    if not isValidHealTarget(caster, target) then
        return xi.msg.basic.CANNOT_PERFORM_TARG
    end

    return 0
end

spellObject.onSpellCast = function(caster, target, spell)
    local spentMP = spell:getMPCost()
    if spentMP == 0 or not isValidHealTarget(caster, target) then
        spell:setMsg(xi.msg.basic.MAGIC_NO_EFFECT)
        return 0
    end

    -- The observed inputs are MND, Healing Magic skill, MP and cure modifiers.
    -- This base calculation models those inputs without assuming a full heal.
    local base = healing.getFullCureBase(caster, spentMP)
    local cure = getCureFinal(caster, spell, base, 1, false)
    if
        caster:hasStatusEffect(xi.effect.AFFLATUS_SOLACE) and
        not target:hasStatusEffect(xi.effect.STONESKIN)
    then
        local stoneskin = math.floor(cure * 0.25 * (1 + caster:getMerit(xi.merit.ANIMUS_SOLACE) / 100))
        target:addStatusEffect(xi.effect.STONESKIN, { power = stoneskin, duration = 30, origin = caster, tier = 1 })
    end

    -- Square Enix specifies a threshold, not a cost per ailment.
    if spentMP > 30 then
        xi.job_utils.white_mage.removeHealingAilments(target)
    end

    cure = healing.applyReceivedPotency(target, cure, true)
    local restored = target:restoreHP(math.min(cure, target:getMaxHP() - target:getHP()))
    target:wakeUp()
    caster:updateEnmityFromCure(target, restored)
    return restored
end

return spellObject
