-----------------------------------
-- xi.effect.ENLIGHT
-----------------------------------
---@type TEffect
local effectObject = {}

effectObject.onEffectGain = function(target, effect)
    local jpValue = target:getJobPointLevel(xi.jp.ENLIGHT_EFFECT)

    effect:addMod(xi.mod.ENSPELL, xi.element.LIGHT)
    if target:isDevelopedTrust() and effect:getTier() == 2 then
        -- Enlight II stores its complete cast-time potency, including JP once.
        -- Native accuracy follows the decaying ENSPELL_DMG value.
        effect:addMod(xi.mod.ENSPELL_DMG, effect:getPower())
    else
        effect:addMod(xi.mod.ENSPELL_DMG, effect:getPower() + jpValue)
        if not target:isDevelopedTrust() then
            effect:addMod(xi.mod.ACC, jpValue)
        end
    end
end

effectObject.onEffectTick = function(target, effect)
end

effectObject.onEffectLose = function(target, effect)
end

return effectObject
