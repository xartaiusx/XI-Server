-----------------------------------
-- Iroha II: Rise from Ashes
-----------------------------------
local irohaSkills = require('scripts/globals/iroha_ii_skills')

---@type TMobSkill
local mobskillObject = {}

mobskillObject.onMobSkillCheck = function(target, mob, skill)
    return irohaSkills.canUse(mob) and mob:getTP() >= 1000 and 0 or 1
end

mobskillObject.onMobWeaponSkill = function(mob, target, skill, action)
    if not irohaSkills.canUse(mob) or not target:isAlive() then
        return 0
    end

    local restored = target:restoreHP(math.min(math.floor(target:getMaxHP() * 0.25), target:getMaxHP() - target:getHP()))
    target:wakeUp()
    -- The absorption value is a provisional community measurement.
    if not target:hasStatusEffect(xi.effect.STONESKIN) then
        target:addStatusEffect(xi.effect.STONESKIN, { power = 500, duration = 900, origin = mob })
    end

    mob:updateEnmityFromCure(target, restored)
    skill:setMsg(xi.msg.basic.SKILL_RECOVERS_HP)
    return restored
end

return mobskillObject
