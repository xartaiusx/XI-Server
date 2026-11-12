-----------------------------------
-- Spell: Dispelga
-----------------------------------
---@type TSpell
local spellObject = {}

spellObject.onMagicCastingCheck = function(caster, target, spell)
    if
        caster:isPC() and
        caster:getMainJob() ~= xi.job.MON and
        caster:getEquipID(xi.slot.MAIN) ~= xi.item.DAYBREAK
    then
        return xi.msg.basic.MAGIC_CANNOT_CAST
    end

    return 0
end

spellObject.onSpellCast = function(caster, target, spell)
    return xi.spells.enfeebling.useEnfeeblingSpell(caster, target, spell)
end

return spellObject
