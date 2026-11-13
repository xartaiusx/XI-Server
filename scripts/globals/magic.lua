-----------------------------------
require('scripts/globals/spells/damage_spell')
-----------------------------------
xi = xi or {}
xi.magic = xi.magic or {}
-----------------------------------

-----------------------------------
--   getCurePower returns the caster's cure power
--   getCureFinal returns the final cure amount
--   Source: http://members.shaw.ca/pizza_steve/cure/Cure_Calculator.html
-----------------------------------
function getCurePower(caster, isBlueMagic)
    local mnd = caster:getStat(xi.mod.MND)
    local vit = caster:getStat(xi.mod.VIT)
    local skill = caster:getSkillLevel(xi.skill.HEALING_MAGIC)
    local power = math.floor(mnd / 2) + math.floor(vit / 4) + skill
    return power
end

function getCurePowerOld(caster)
    local mnd = caster:getStat(xi.mod.MND)
    local vit = caster:getStat(xi.mod.VIT)
    local skill = caster:getSkillLevel(xi.skill.HEALING_MAGIC) -- it's healing magic skill for the BLU cures as well
    local power = (3 * mnd) + vit + (3 * math.floor(skill / 5))
    return power
end

function getBaseCure(power, divisor, constant, basepower)
    return (power - basepower) / divisor + constant
end

function getBaseCureOld(power, divisor, constant)
    return (power / 2) / divisor + constant
end

local function curePotency(caster)
    local curePot = math.min(caster:getMod(xi.mod.CURE_POTENCY), 50) / 100
    local curePotII = math.min(caster:getMod(xi.mod.CURE_POTENCY_II), 30) / 100
    return 1 + curePot + curePotII
end

local function cureStatusMultipliers(caster, isBlueMagic)
    local dSeal = caster:hasStatusEffect(xi.effect.DIVINE_SEAL) and 2 or 1
    local hasRapture = not isBlueMagic and caster:hasStatusEffect(xi.effect.RAPTURE)
    local rapture = hasRapture and (1.5 + caster:getMod(xi.mod.RAPTURE_AMOUNT) / 100) or 1
    return dSeal, rapture, hasRapture
end

local function modifiedCure(basecure, minCure, potency, dayWeatherBonus, rapture, dSeal)
    local final = math.floor(math.max(basecure, minCure))
    final = math.floor(final * potency)
    final = math.floor(final * dayWeatherBonus)
    final = math.floor(final * rapture)
    final = math.floor(final * dSeal)
    return final
end

function getCureFinal(caster, spell, basecure, minCure, isBlueMagic)
    local potency = curePotency(caster)
    local dayWeatherBonus = xi.spells.damage.calculateDayAndWeather(caster, spell:getElement(), false)
    local dSeal, rapture, hasRapture = cureStatusMultipliers(caster, isBlueMagic)
    if hasRapture then
        caster:delStatusEffectSilent(xi.effect.RAPTURE)
    end

    return modifiedCure(basecure, minCure, potency, dayWeatherBonus, rapture, dSeal)
end

xi.magic.getWhiteCureFinalRange = function(caster, basecure, minCure, weatherLow, weatherHigh)
    local potency = curePotency(caster)
    local dSeal, rapture = cureStatusMultipliers(caster, false)
    local a = modifiedCure(basecure, minCure, potency, weatherLow, rapture, dSeal)
    local b = modifiedCure(basecure, minCure, potency, weatherHigh, rapture, dSeal)
    return math.min(a, b), math.max(a, b)
end

function isValidHealTarget(caster, target)
    return target:getAllegiance() == caster:getAllegiance() and
            (target:getObjType() == xi.objType.PC or
            target:getObjType() == xi.objType.MOB or
            target:getObjType() == xi.objType.TRUST or
            target:getObjType() == xi.objType.FELLOW)
end

-- Applies resistance for additional effects
function applyResistanceAddEffect(actor, target, element, bonusMacc)
    return xi.combat.magicHitRate.calculateResistRate(actor, target, { magicalElement = element, bonusMacc = bonusMacc })
end

function addBonusesAbility(caster, ele, target, dmg, params)
    local affinityBonus = xi.spells.damage.calculateElementalStaffBonus(caster, ele)
    dmg = math.floor(dmg * affinityBonus)

    local magicDefense = xi.combat.damage.magicalElementSDT(target, ele)
    dmg = math.floor(dmg * magicDefense)

    local dayWeatherBonus = xi.spells.damage.calculateDayAndWeather(caster, ele, false)
    dmg = math.floor(dmg * dayWeatherBonus)

    local mab = 1
    local mdefBarBonus = 0
    if
        ele >= xi.element.FIRE and
        ele <= xi.element.WATER and
        target:hasStatusEffect(xi.data.element.getAssociatedBarspellEffect(ele))
    then -- bar- spell magic defense bonus
        mdefBarBonus = target:getStatusEffect(xi.data.element.getAssociatedBarspellEffect(ele)):getSubPower()
    end

    if params ~= nil and params.bonusmab ~= nil and params.includemab then
        mab = (100 + caster:getMod(xi.mod.MATT) + params.bonusmab) / (100 + target:getMod(xi.mod.MDEF) + mdefBarBonus)
    elseif params == nil or (params ~= nil and params.includemab) then
        mab = (100 + caster:getMod(xi.mod.MATT)) / (100 + target:getMod(xi.mod.MDEF) + mdefBarBonus)
    end

    if mab < 0 then
        mab = 0
    end

    dmg = math.floor(dmg * mab)

    return dmg
end
