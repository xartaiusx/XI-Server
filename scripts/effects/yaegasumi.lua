-----------------------------------
-- xi.effect.YAEGASUMI
-----------------------------------
---@type TEffect
local effectObject = {}

effectObject.onEffectGain = function(target, effect)
    if target:isDevelopedTrust() then
        effect:addMod(xi.mod.TP_BONUS, target:getJobPointLevel(xi.jp.YAEGASUMI_EFFECT) * 30)
    end
end

effectObject.onEffectTick = function(target, effect)
end

effectObject.onEffectLose = function(target, effect)
end

return effectObject
