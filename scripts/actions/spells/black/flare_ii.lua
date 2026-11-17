-----------------------------------
-- Spell: Flare II
-----------------------------------
---@type TSpell
local spellObject = {}

spellObject.onMagicCastingCheck = function(caster, target, spell)
    if
        caster:isDevelopedTrust() and
        caster:getTrustID() == xi.magic.spell.IROHA_II
    then
        -- This signature has a quick cast. The native burst window still applies.
        spell:setCastTime(1000)
    end

    return 0
end

spellObject.onSpellCast = function(caster, target, spell)
    target:addStatusEffect(xi.effect.NINJUTSU_ELE_DEBUFF, { power = 30, duration = 10, origin = caster, icon = 0, subPower = xi.mod.WATER_MEVA })

    return xi.spells.damage.useDamageSpell(caster, target, spell)
end

return spellObject
