-----------------------------------
-- Developed Iroha II signature skills
-----------------------------------
local irohaSkills = {}

irohaSkills.canUse = function(mob)
    return
        mob:isDevelopedTrust() and
        mob:getTrustID() == xi.magic.spell.IROHA_II and
        mob:getWeaponSkillType(xi.slot.MAIN) == xi.skill.POLEARM
end

irohaSkills.elemental = function(element, damageType, dispels)
    return
    {
        onMobSkillCheck = function(target, mob, skill)
            return irohaSkills.canUse(mob) and mob:getTP() >= 1000 and 0 or 1
        end,

        onMobWeaponSkill = function(mob, target, skill, action)
            if not irohaSkills.canUse(mob) then
                return 0
            end

            -- Use one modeled weapon-damage unit. Retail fTP is unresolved.
            local params =
            {
                baseDamage     = mob:getWeaponDmg(),
                fTP            = { 1.0, 1.0, 1.0 },
                element        = element,
                attackType     = xi.attackType.MAGICAL,
                damageType     = damageType,
                shadowBehavior = xi.mobskills.shadowBehavior.IGNORE_SHADOWS,
            }

            local info = xi.mobskills.mobMagicalMove(mob, target, skill, action, params)
            if xi.mobskills.processDamage(mob, target, skill, action, info) then
                target:takeDamage(info.damage, mob, info.attackType, info.damageType)
                if dispels and target:isAlive() then
                    target:dispelStatusEffect()
                end
            end

            return info.damage
        end,
    }
end

return irohaSkills
