-----------------------------------
-- Trust: Iroha II
-----------------------------------
---@type TSpellTrust
local spellObject = {}

spellObject.onMagicCastingCheck = function(caster, target, spell)
    return xi.trust.canCast(caster, spell, xi.magic.spell.IROHA)
end

spellObject.onSpellCast = function(caster, target, spell)
    return xi.trust.spawn(caster, spell)
end

local cleanses =
{
    { xi.effect.DOOM,        xi.magic.spell.CURSNA    },
    { xi.effect.PETRIFICATION, xi.magic.spell.STONA  },
    { xi.effect.SILENCE,     xi.magic.spell.SILENA   },
    { xi.effect.PARALYSIS,   xi.magic.spell.PARALYNA },
    { xi.effect.CURSE_I,     xi.magic.spell.CURSNA   },
    { xi.effect.CURSE_II,    xi.magic.spell.CURSNA   },
    { xi.effect.PLAGUE,      xi.magic.spell.VIRUNA   },
    { xi.effect.DISEASE,     xi.magic.spell.VIRUNA   },
    { xi.effect.BLINDNESS,   xi.magic.spell.BLINDNA  },
    { xi.effect.POISON,      xi.magic.spell.POISONA  },
}

local function addGambits(mob)
    -- Recovery can take precedence over weapon skills without turning a
    -- healthy party's Samurai into a full-time healer.
    mob:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 20 }, { ai.c.CASTER_MPP_LT, 15 } }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.BENEDICTION })
    mob:addGambit(ai.t.SELF, { { ai.c.IROHA_RECOVERY, 0 }, { ai.c.TP_GTE, 1000 } }, { ai.r.MS, ai.s.SPECIFIC, 3738 })
    mob:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 20 }, { ai.c.HP_MISSING, 850 } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURE_VI })
    mob:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 30 }, { ai.c.HP_MISSING, 600 } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURE_V })
    mob:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 15 }, { ai.c.HP_MISSING, 1200 }, { ai.c.CASTER_MPP_GTE, 80 } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.FULL_CURE })
    mob:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 40 }, { ai.c.HP_MISSING, 250 } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURE_IV })

    for _, status in ipairs({ xi.effect.SLEEP_I, xi.effect.SLEEP_II, xi.effect.LULLABY }) do
        mob:addGambit(ai.t.PARTY, { ai.c.STATUS, status }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURE })
    end

    for _, cleanse in ipairs(cleanses) do
        mob:addGambit(ai.t.PARTY, { ai.c.STATUS, cleanse[1] }, { ai.r.MA, ai.s.SPECIFIC, cleanse[2] })
    end

    mob:addGambit(ai.t.PARTY, { ai.c.STATUS_FLAG, xi.effectFlag.ERASABLE }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.ERASE })
    mob:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 65 }, { ai.c.HP_MISSING, 150 } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURE_III })
    mob:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 55 }, { ai.c.HP_MISSING, 60 } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURE_II })
    mob:addGambit(ai.t.PARTY, { ai.c.HPP_LT, 40 }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURE })

    mob:addGambit(ai.t.SELF, { { ai.c.HAS_TOP_ENMITY, 0 }, { ai.c.NOT_STATUS, xi.effect.SEIGAN } }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.SEIGAN })
    mob:addGambit(ai.t.SELF, { { ai.c.HAS_TOP_ENMITY, 0 }, { ai.c.NOT_STATUS, xi.effect.THIRD_EYE } }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.THIRD_EYE })
    mob:addGambit(ai.t.SELF, { { ai.c.NOT_HAS_TOP_ENMITY, 0 }, { ai.c.NOT_STATUS, xi.effect.HASSO } }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.HASSO })
    mob:addGambit(ai.t.SELF, { { ai.c.TP_LT, 1500 }, { ai.c.HPP_GTE, 50 } }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.MEDITATE })
    mob:addGambit(ai.t.TARGET, { { ai.c.MB_ELEMENT_AVAILABLE, xi.element.FIRE }, { ai.c.CASTER_MPP_GTE, 65 } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.FLARE_II })

    mob:addGambit(ai.t.SELF, { { ai.c.MPP_GTE, 40 }, { ai.c.NOT_STATUS, xi.effect.AFFLATUS_SOLACE }, { ai.c.NOT_STATUS, xi.effect.AFFLATUS_MISERY } }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.AFFLATUS_SOLACE })
    mob:addGambit(ai.t.SELF, { { ai.c.PARTY_DEFENSE_MISSING, xi.effect.PROTECT }, { ai.c.CASTER_MPP_GTE, 70 } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.PROTECTRA_V }, 15)
    mob:addGambit(ai.t.SELF, { { ai.c.PARTY_DEFENSE_MISSING, xi.effect.SHELL }, { ai.c.CASTER_MPP_GTE, 70 } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.SHELLRA_V }, 15)
    mob:addGambit(ai.t.SELF, { { ai.c.MPP_GTE, 85 }, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.RERAISE } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.RERAISE_IV })
    mob:setTrustTPSkillSettings(ai.tp.CLOSER_UNTIL_TP, ai.s.HIGHEST, 3000)
end

spellObject.onMobSpawn = function(mob)
    xi.trust.message(mob, xi.trust.messageOffset.SPAWN)

    if mob:isDevelopedTrust() then
        addGambits(mob)
    end
end

spellObject.onMobDespawn = function(mob)
    xi.trust.message(mob, xi.trust.messageOffset.DESPAWN)
end

spellObject.onMobDeath = function(mob)
    xi.trust.message(mob, xi.trust.messageOffset.DEATH)
end

return spellObject
