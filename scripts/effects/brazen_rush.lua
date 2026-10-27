-----------------------------------
-- xi.effect.BRAZEN_RUSH
-----------------------------------
---@type TEffect
local effectObject = {}

effectObject.onEffectGain = function(target, effect)
    local jpLevel = target:getJobPointLevel(xi.jp.BRAZEN_RUSH_EFFECT)

    effect:addMod(xi.mod.ATT, 4 * jpLevel)
    effect:addMod(xi.mod.DOUBLE_ATTACK, effect:getPower())
end

effectObject.onEffectTick = function(target, effect)
    local prevPower = effect:getPower()
    local nextPower = prevPower - 10

    effect:addMod(xi.mod.DOUBLE_ATTACK, nextPower - prevPower)
    effect:setPower(nextPower)
end

effectObject.onEffectLose = function(target, effect)
end

return effectObject
