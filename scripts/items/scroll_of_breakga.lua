-----------------------------------
-- ID: 4889
-- Scroll of Breakga
-- Teaches the black magic Breakga
-----------------------------------
---@type TItem
local itemObject = {}

itemObject.onItemCheck = function(target, item, caster)
    return target:canLearnSpell(xi.magic.spell.BREAKGA)
end

itemObject.onItemUse = function(target)
    target:addSpell(xi.magic.spell.BREAKGA)
end

return itemObject
