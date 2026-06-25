-----------------------------------
-- Light Shot
-- Qultada
-----------------------------------
---@type TMobSkill
local mobskillObject = {}

local diaInfo =
{
    [1] = 10,
    [3] = 15,
    [5] = 20,
    [7] = 25,
    [9] = 30,
}

mobskillObject.onMobSkillCheck = function(target, mob, skill)
    return 0
end

mobskillObject.onMobWeaponSkill = function(mob, target, skill, action)
    local dia = target:getStatusEffect(xi.effect.DIA)
    if dia then
        local diaOwner    = dia:getOriginID()
        local diaPower    = dia:getPower()
        local diaSubpower = dia:getSubPower()
        local diaTier     = dia:getTier()
        local startTime   = dia:getStartTime()
        local baseSubpower = diaInfo[diaTier] or diaSubpower

        if diaSubpower > baseSubpower then
            skill:setMsg(xi.msg.basic.SKILL_NO_EFFECT)
            return 0
        end

        diaPower = diaPower + 1
        diaSubpower = diaSubpower + math.floor(100 * 28 / 1024)

        target:delStatusEffectSilent(xi.effect.DIA)
        target:addStatusEffect(xi.effect.DIA, { power = diaPower, duration = dia:getDuration(), origin = mob, tick = dia:getTick(), subType = dia:getSubType(), subPower = diaSubpower, tier = diaTier })

        local newEffect = target:getStatusEffect(xi.effect.DIA)
        if newEffect then
            newEffect:setStartTime(startTime)
            newEffect:setOriginID(diaOwner)
        end

        skill:setMsg(xi.msg.basic.SKILL_ENFEEB)
        return xi.effect.DIA
    end

    skill:setMsg(xi.mobskills.mobStatusEffectMove(mob, target, xi.effect.SLEEP_I, 1, 0, 60))

    return xi.effect.SLEEP_I
end

return mobskillObject
