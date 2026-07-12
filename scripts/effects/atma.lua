-----------------------------------
-- xi.effect.ATMA
-- Notes: Effect sourceTypeParam = Atma slot.  See: scripts/globals/abyssea/atma.lua
-----------------------------------
---@type TEffect
local effectObject = {}

effectObject.onEffectGain = function(target, effect)
    xi.atma.onEffectGain(target, effect)
end

effectObject.onEffectTick = function(target, effect)
    xi.atma.onEffectTick(target, effect)
end

effectObject.onEffectLose = function(target, effect)
    xi.atma.onEffectLose(target, effect)
end

return effectObject
