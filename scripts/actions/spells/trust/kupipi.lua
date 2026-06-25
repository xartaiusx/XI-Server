-----------------------------------
-- Trust: Kupipi
-----------------------------------
---@type TSpellTrust
local spellObject = {}
local kupipiPlayerLikeVar = 'TrustParityKupipiWhmSchV5'

local kupipiCaressStatuses =
{
    xi.effect.POISON,
    xi.effect.PARALYSIS,
    xi.effect.BLINDNESS,
    xi.effect.SILENCE,
    xi.effect.PETRIFICATION,
    xi.effect.DISEASE,
    xi.effect.PLAGUE,
    xi.effect.CURSE_I,
    xi.effect.CURSE_II,
    xi.effect.BANE,
    xi.effect.DOOM,
}

local function addDivineCaressStatusGambits(mob)
    for _, statusEffect in ipairs(kupipiCaressStatuses) do
        mob:addGambit(ai.t.PARTY, { { ai.c.STATUS, statusEffect }, { ai.c.CASTER_MPP_GTE, 20 } }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.DIVINE_CARESS }, 60)
    end
end

local function addPlayerLikeCureGambits(mob)
    -- Mochirii player-like WHM/SCH extension: choose Cures by real missing HP
    -- first, then HP percentage. At low MP, stop topping people off and save
    -- MP for dangerous damage windows.
    mob:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 20 }, { ai.c.CASTER_MPP_GTE, 45 }, { ai.c.HP_MISSING, 1200 } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURE_VI }, 8)
    mob:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 35 }, { ai.c.CASTER_MPP_GTE, 18 }, { ai.c.HP_MISSING, 500 } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURE_V }, 8)
    mob:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 45 }, { ai.c.CASTER_MPP_GTE, 30 }, { ai.c.HP_MISSING, 800 } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURE_V }, 8)
    mob:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 80 }, { ai.c.CASTER_MPP_GTE, 25 }, { ai.c.HP_MISSING, 350 } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURE_IV }, 8)
    mob:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 55 }, { ai.c.CASTER_MPP_GTE, 15 }, { ai.c.HP_MISSING, 250 } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURE_IV }, 8)
    mob:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 75 }, { ai.c.CASTER_MPP_GTE, 18 }, { ai.c.HP_MISSING, 150 } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURE_III }, 8)
    mob:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 55 }, { ai.c.CASTER_MPP_GTE, 12 }, { ai.c.HP_MISSING, 120 } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURE_III }, 8)
    mob:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 65 }, { ai.c.CASTER_MPP_GTE, 10 }, { ai.c.HP_MISSING, 60 } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURE_II }, 8)
end

local function addSustainModeGambits(mob)
    mob:addGambit(ai.t.SELF, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.AFFLATUS_SOLACE }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.AFFLATUS_SOLACE })
    mob:addGambit(ai.t.SELF, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.ADDENDUM_WHITE }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.LIGHT_ARTS })
    mob:addGambit(ai.t.SELF, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.ADDENDUM_WHITE }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.ADDENDUM_WHITE })

    mob:addGambit(ai.t.SELF, {
        { ai.c.MPP_LT, 50 },
        { ai.c.STATUS, xi.effect.SUBLIMATION_COMPLETE },
    }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.SUBLIMATION }, 60)
    mob:addGambit(ai.t.SELF, {
        { ai.c.MPP_LT, 75 },
        { ai.c.HPP_GTE, 75 },
        { ai.c.NOT_STATUS, xi.effect.SUBLIMATION_ACTIVATED },
        { ai.c.NOT_STATUS, xi.effect.SUBLIMATION_COMPLETE },
    }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.SUBLIMATION }, 60)
end

local function addPlayerLikeWhmSchGambits(mob)
    -- Mochirii player-like extension: retain Kupipi's healer identity while
    -- giving her safe WHM/SCH tools this Mochirii checkout already supports.
    mob:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 35 }, { ai.c.CASTER_MPP_LT, 8 } }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.BENEDICTION }, 300)
    mob:addGambit(ai.t.PARTY, { ai.c.HPP_LT, 15 }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.BENEDICTION }, 300)
    mob:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 35 }, { ai.c.CASTER_MPP_GTE, 15 }, { ai.c.CASTER_NOT_STATUS, xi.effect.DIVINE_SEAL } }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.DIVINE_SEAL }, 120)
    mob:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 30 }, { ai.c.CASTER_HPP_GTE, 40 }, { ai.c.CASTER_MPP_GTE, 20 }, { ai.c.STATUS_FLAG, xi.effectFlag.ERASABLE } }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.ASYLUM }, 3600)
    mob:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 45 }, { ai.c.CASTER_MPP_GTE, 45 }, { ai.c.HP_MISSING, 600 } }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.PENURY }, 120)
    mob:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 45 }, { ai.c.CASTER_MPP_GTE, 45 }, { ai.c.HP_MISSING, 600 } }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.CURAGA }, 20)
    mob:addGambit(ai.t.PARTY_DEAD, { ai.c.CASTER_MPP_GTE, 35 }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.CELERITY }, 120)
    mob:addGambit(ai.t.PARTY_DEAD, { ai.c.CASTER_MPP_GTE, 35 }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.RAISE }, 30)
    mob:addGambit(ai.t.SELF, { { ai.c.MPP_GTE, 90 }, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.RERAISE } }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.RERAISE }, 300)

    mob:addGambit(ai.t.SELF, { { ai.c.MPP_GTE, 55 }, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.AQUAVEIL } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.AQUAVEIL }, 120)
    mob:addGambit(ai.t.SELF, { { ai.c.MPP_GTE, 60 }, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.STONESKIN } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.STONESKIN }, 120)
    mob:addGambit(ai.t.SELF, { { ai.c.MPP_GTE, 65 }, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.BLINK } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.BLINK }, 120)
    mob:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 45 }, { ai.c.CASTER_HPP_GTE, 50 }, { ai.c.CASTER_MPP_GTE, 20 } }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.SACROSANCTITY }, 300)
    mob:addGambit(ai.t.TARGET, { { ai.c.CASTER_MPP_GTE, 75 }, { ai.c.CAST_ELE_MA_SELF, 0 }, { ai.c.NEED_ELE_BAREFFECT, 0 } }, { ai.r.MA, ai.s.DEF_BAR_ELEMENT, 0 }, 20)
    mob:addGambit(ai.t.SELF, { { ai.c.MPP_GTE, 70 }, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.AUSPICE } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.AUSPICE }, 120)
    mob:addGambit(ai.t.SELF, { { ai.c.MPP_GTE, 75 }, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.MND_BOOST } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.BOOST_MND }, 300)
    mob:addGambit(ai.t.SELF, { { ai.c.MPP_GTE, 80 }, { ai.c.NO_STORM, 0 } }, { ai.r.MA, ai.s.STORM_DAY, 0 }, 60)

    mob:addGambit(ai.t.TANK, { { ai.c.CASTER_HPP_GTE, 75 }, { ai.c.CASTER_MPP_GTE, 65 }, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.HASTE } }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.HASTE })
    mob:addGambit(ai.t.MELEE, { { ai.c.CASTER_MPP_GTE, 65 }, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.HASTE } }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.HASTE })
    mob:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 75 }, { ai.c.CASTER_HPP_GTE, 75 }, { ai.c.CASTER_MPP_GTE, 65 }, { ai.c.HP_MISSING, 250 }, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.REGEN } }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.ACCESSION }, 180)
    mob:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 85 }, { ai.c.CASTER_MPP_GTE, 30 }, { ai.c.HP_MISSING, 120 }, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.REGEN } }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.REGEN }, 45)

    mob:addGambit(ai.t.TARGET, { { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.SLOW }, { ai.c.CASTER_MPP_GTE, 55 } }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.SLOW }, 60)
    mob:addGambit(ai.t.TARGET, { { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.PARALYSIS }, { ai.c.CASTER_MPP_GTE, 55 } }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.PARALYZE }, 60)
    mob:addGambit(ai.t.TARGET, { { ai.c.CASTER_MPP_GTE, 70 }, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.DIA } }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.DIA }, 60)
    mob:addGambit(ai.t.TARGET, { { ai.c.CASTER_MPP_GTE, 65 }, { ai.c.CASTING_MA, 0 }, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.ADDLE } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.ADDLE }, 90)
    mob:addGambit(ai.t.TARGET, { { ai.c.CASTER_MPP_GTE, 65 }, { ai.c.CASTING_MA, 0 }, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.SLEEP_I } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.REPOSE }, 120)
end

spellObject.onMagicCastingCheck = function(caster, target, spell)
    return xi.trust.canCast(caster, spell)
end

spellObject.onSpellCast = function(caster, target, spell)
    local windurstFirstTrust = caster:getCharVar('WindurstFirstTrust')
    local zone = caster:getZoneID()

    if
        windurstFirstTrust == 1 and
        (zone == xi.zone.EAST_SARUTABARUTA or zone == xi.zone.WEST_SARUTABARUTA)
    then
        caster:setCharVar('WindurstFirstTrust', 2)
    end

    return xi.trust.spawn(caster, spell)
end

spellObject.onMobSpawn = function(mob)
    xi.trust.teamworkMessage(mob, {
        [xi.magic.spell.SHANTOTTO] = xi.trust.messageOffset.TEAMWORK_1,
        [xi.magic.spell.STAR_SIBYL] = xi.trust.messageOffset.TEAMWORK_2,
    })

    addPlayerLikeCureGambits(mob)

    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.SLEEP_I }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURE })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.SLEEP_II }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURE })

    addSustainModeGambits(mob)

    addDivineCaressStatusGambits(mob)

    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.POISON }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.POISONA })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.PARALYSIS }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.PARALYNA })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.BLINDNESS }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.BLINDNA })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.SILENCE }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.SILENA })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.PETRIFICATION }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.STONA })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.DISEASE }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.VIRUNA })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.PLAGUE }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.VIRUNA })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.CURSE_I }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURSNA })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.CURSE_II }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURSNA })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.BANE }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURSNA })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS, xi.effect.DOOM }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURSNA })

    mob:addGambit(ai.t.SELF, { ai.c.STATUS_FLAG, xi.effectFlag.ERASABLE }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.ERASE })
    mob:addGambit(ai.t.PARTY, { ai.c.STATUS_FLAG, xi.effectFlag.ERASABLE }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.ERASE })

    -- Kupipi refreshes missing/dispelled defenses with single-target
    -- Protect/Shell when possible, then falls back to Protectra/Shellra.
    mob:addGambit(ai.t.PARTY, { { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.PROTECT }, { ai.c.CASTER_MPP_GTE, 80 }, { ai.c.TIMER, 30 } }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.PROTECT })
    mob:addGambit(ai.t.PARTY, { { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.SHELL }, { ai.c.CASTER_MPP_GTE, 80 }, { ai.c.TIMER, 30 } }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.SHELL })
    mob:addGambit(ai.t.SELF, { { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.PROTECT }, { ai.c.CASTER_MPP_GTE, 90 } }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.PROTECTRA })
    mob:addGambit(ai.t.SELF, { { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.SHELL }, { ai.c.CASTER_MPP_GTE, 90 } }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.SHELLRA })

    addPlayerLikeWhmSchGambits(mob)

    mob:addGambit(ai.t.TARGET, { { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.FLASH }, { ai.c.CASTER_MPP_GTE, 70 } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.FLASH }, 60)

    mob:setAutoAttackEnabled(false)
    mob:setMobMod(xi.mobMod.TRUST_DISTANCE, xi.trust.movementType.NO_MOVE)
    mob:setLocalVar('TrustParityKupipi', 1)
    mob:setLocalVar('TrustParityKupipiV2', 1)
    mob:setLocalVar('TrustParityKupipiWhmSchV2', 1)
    mob:setLocalVar('TrustParityKupipiWhmSchV4', 1)
    mob:setLocalVar(kupipiPlayerLikeVar, 1)
end

spellObject.onMobDespawn = function(mob)
    xi.trust.message(mob, xi.trust.messageOffset.DESPAWN)
end

spellObject.onMobDeath = function(mob)
    xi.trust.message(mob, xi.trust.messageOffset.DEATH)
end

return spellObject
