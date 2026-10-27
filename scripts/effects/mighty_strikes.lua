-----------------------------------
-- xi.effect.MIGHTY_STRIKES
-----------------------------------
---@type TEffect
local effectObject = {}

effectObject.onEffectGain = function(target, effect)
    local jpLevel = target:getJobPointLevel(xi.jp.MIGHTY_STRIKES_EFFECT)

    effect:addMod(xi.mod.CRITHITRATE, 100)
    effect:addMod(xi.mod.ACC, jpLevel * 2)
    effect:addMod(xi.mod.RACC, jpLevel * 2)
end

effectObject.onEffectTick = function(target, effect)
end

effectObject.onEffectLose = function(target, effect)
end

return effectObject
