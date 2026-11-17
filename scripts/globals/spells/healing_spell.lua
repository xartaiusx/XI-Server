-----------------------------------
-- Single-target white cure formulas shared by their effects and Iroha II's
-- emergency healing decision.
-----------------------------------
require('scripts/globals/magic')

xi.spells.healing = xi.spells.healing or {}
local healing = xi.spells.healing

-- Old rows are descending exclusive lower bounds (power, divisor, constant).
-- Modern rows are ascending exclusive upper bounds and add a base power.
local curves =
{
    {
        minimum = 10,
        old =
        {
            { 100, 57, 29.125 },
            { 60, 2, 5 },
            { -math.huge, 1, -10 },
        },
        modern =
        {
            { 20, 4, 10, 0 },
            { 40, 1.3333, 15, 20 },
            { 125, 8.5, 30, 40 },
            { 200, 15, 40, 125 },
            { 600, 20, 40, 200 },
            { math.huge, 999999, 65, 0 },
        },
    },
    {
        minimum = 60,
        old =
        {
            { 170, 35.6666, 87.62 },
            { 110, 2, 47.5 },
            { -math.huge, 1, 20 },
        },
        modern =
        {
            { 70, 1, 60, 40 },
            { 125, 5.5, 90, 70 },
            { 200, 7.5, 100, 125 },
            { 400, 10, 110, 200 },
            { 700, 20, 130, 400 },
            { math.huge, 999999, 145, 0 },
        },
    },
    {
        minimum = 130,
        old =
        {
            { 300, 15.6666, 180.43 },
            { 180, 2, 115 },
            { -math.huge, 1, 70 },
        },
        modern =
        {
            { 125, 2.2, 130, 70 },
            { 200, 75 / 65, 155, 125 },
            { 300, 2.5, 220, 200 },
            { 700, 5, 260, 300 },
            { math.huge, 999999, 340, 0 },
        },
    },
    {
        minimum = 270,
        old =
        {
            { 460, 6.5, 354.6666 },
            { 220, 2, 275 },
            { -math.huge, 0.6666, 165 },
        },
        modern =
        {
            { 200, 1, 270, 70 },
            { 300, 2, 400, 200 },
            { 400, 10 / 7, 450, 300 },
            { 700, 2.5, 520, 400 },
            { math.huge, 999999, 640, 0 },
        },
    },
    {
        minimum = 450,
        old =
        {
            { 560, 2.8333, 591.2 },
            { 320, 1, 410 },
            { -math.huge, 0.6666, 330 },
        },
        modern =
        {
            { 150, 0.70, 450, 80 },
            { 190, 1.25, 550, 150 },
            { 260, 70 / 38, 582, 190 },
            { 300, 2, 620, 260 },
            { 500, 2.5, 640, 300 },
            { 700, 10 / 3, 720, 500 },
            { math.huge, 999999, 780, 0 },
        },
    },
    {
        minimum = 600,
        modern =
        {
            { 210, 1.5, 600, 90 },
            { 300, 0.9, 680, 210 },
            { 400, 10 / 7, 780, 300 },
            { 500, 2.5, 850, 400 },
            { 700, 5 / 3, 890, 500 },
            { math.huge, 999999, 1010, 0 },
        },
    },
}

healing.getBaseCure = function(caster, tier, useOldFormula)
    local curve = curves[tier]
    if useOldFormula and curve.old then
        local power = getCurePowerOld(caster)
        for _, row in ipairs(curve.old) do
            if power > row[1] then
                return getBaseCureOld(power, row[2], row[3]), curve.minimum
            end
        end
    end

    local power = getCurePower(caster)
    for _, row in ipairs(curve.modern) do
        if power < row[1] then
            -- Cure VI uses its modern power curve even when an NPC's
            -- non-friendly fallback applies the old base calculation.
            local base = useOldFormula and getBaseCureOld(power, row[2], row[3]) or getBaseCure(power, row[2], row[3], row[4])
            return base, curve.minimum
        end
    end
end

healing.getFullCureBase = function(caster, spentMP)
    return math.floor(caster:getStat(xi.mod.MND) / 2) + caster:getSkillLevel(xi.skill.HEALING_MAGIC) + spentMP
end

healing.applyReceivedPotency = function(target, amount, fullCure)
    local received = target:getMod(xi.mod.CURE_POTENCY_RCVD) / 100
    if fullCure then
        return math.floor(amount * (1 + received) * xi.settings.main.CURE_POWER)
    end

    return (amount + amount * received) * xi.settings.main.CURE_POWER
end

local function reachesTarget(target, amount, fullCure, needed)
    return math.floor(healing.applyReceivedPotency(target, amount, fullCure)) >= needed
end

-- Native readiness bits cover Cure I-VI in ascending MP order, followed by
-- Full Cure. Cast admission remains in the native Trust action path.
healing.selectIrohaEmergencyCure = function(caster, target, ready)
    if not target:isAlive() or not isValidHealTarget(caster, target) then
        return 0
    end

    local needed = math.ceil(target:getMaxHP() * 0.30) - target:getHP()
    if needed <= 0 then
        return 0
    end

    local weatherLow, weatherHigh = xi.spells.damage.getDayAndWeatherRange(caster, xi.element.LIGHT)
    local ordinaryMightSuffice = false
    for tier = 1, #curves do
        if bit.band(ready, bit.lshift(1, tier - 1)) ~= 0 then
            local useOldFormula = tier < #curves and xi.settings.main.USE_OLD_CURE_FORMULA
            local base, minimum = healing.getBaseCure(caster, tier, useOldFormula)
            local low, high = xi.magic.getWhiteCureFinalRange(caster, base, minimum, weatherLow, weatherHigh)
            if reachesTarget(target, low, false, needed) then
                return xi.magic.spell.CURE + tier - 1
            end

            ordinaryMightSuffice = ordinaryMightSuffice or reachesTarget(target, high, false, needed)
        end
    end

    if not ordinaryMightSuffice and bit.band(ready, bit.lshift(1, #curves)) ~= 0 then
        local base = healing.getFullCureBase(caster, caster:getMP())
        local low = xi.magic.getWhiteCureFinalRange(caster, base, 1, weatherLow, weatherHigh)
        if reachesTarget(target, low, true, needed) then
            return xi.magic.spell.FULL_CURE
        end
    end

    return 0
end

return healing
