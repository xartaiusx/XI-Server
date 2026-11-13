-----------------------------------
-- Iroha II: Amatsu Hanadoki
-----------------------------------
local irohaSkills = require('scripts/globals/iroha_ii_skills')

---@type TMobSkill
local mobskillObject = irohaSkills.elemental(xi.element.LIGHT, xi.damageType.LIGHT, true)

return mobskillObject
