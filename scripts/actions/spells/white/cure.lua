-----------------------------------
-- Spell: Cure
-- Restores target's HP.
-- Shamelessly stolen from http://members.shaw.ca/pizza_steve/cure/Cure_Calculator.html
-----------------------------------
local healing = require('scripts/globals/spells/healing_spell')

---@type TSpell
local spellObject = {}

spellObject.onMagicCastingCheck = function(caster, target, spell)
    return 0
end

spellObject.onSpellCast = function(caster, target, spell)
    local final = 0

    if isValidHealTarget(caster, target) then
        local basecure, minCure = healing.getBaseCure(caster, 1, xi.settings.main.USE_OLD_CURE_FORMULA)
        final = getCureFinal(caster, spell, basecure, minCure, false)
        if
            caster:hasStatusEffect(xi.effect.AFFLATUS_SOLACE) and
            not target:hasStatusEffect(xi.effect.STONESKIN)
        then
            local solaceStoneskin = 0
            local equippedBody = xi.equipment.getUsableEquipID(caster, xi.slot.BODY)
            if equippedBody == xi.item.ORISON_BLIAUT_P1 then
                solaceStoneskin = math.floor(final * 0.30)
            elseif equippedBody == xi.item.ORISON_BLIAUT_P2 then
                solaceStoneskin = math.floor(final * 0.35)
            else
                solaceStoneskin = math.floor(final * 0.25)
            end

            solaceStoneskin = solaceStoneskin * (1 + caster:getMerit(xi.merit.ANIMUS_SOLACE) / 100)

            target:addStatusEffect(xi.effect.STONESKIN, { power = solaceStoneskin, duration = 25, origin = caster, tier = 1 })
        end

        final = healing.applyReceivedPotency(target, final, false)

        local diff = (target:getMaxHP() - target:getHP())
        if final > diff then
            final = diff
        end

        target:addHP(final)

        target:wakeUp()
        caster:updateEnmityFromCure(target, final)
    else
        -- no effect if player casted on mob

        if target:isUndead() then
            spell:setMsg(xi.msg.basic.MAGIC_DMG)

            final = xi.spells.damage.useDamageSpell(caster, target, spell)
        elseif caster:getObjType() == xi.objType.PC then
            spell:setMsg(xi.msg.basic.MAGIC_NO_EFFECT)
        else
            -- e.g. monsters healing themselves.
            local basecure, minCure = healing.getBaseCure(caster, 1, xi.settings.main.USE_OLD_CURE_FORMULA)
            final = getCureFinal(caster, spell, basecure, minCure, false)
            local diff = (target:getMaxHP() - target:getHP())
            if final > diff then
                final = diff
            end

            target:addHP(final)
        end
    end

    local mpBonusPercent = (final * caster:getMod(xi.mod.CURE2MP_PERCENT)) / 100
    if mpBonusPercent > 0 then
        caster:addMP(mpBonusPercent)
    end

    return final
end

return spellObject
