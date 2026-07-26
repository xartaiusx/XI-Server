-----------------------------------
-- Mochirii Trust retail parity helpers.
--
-- Keep Trusts retail-shaped: add only source-backed behavior that Mochirii already
-- supports safely, and prefer per-Trust profiles over generic player cloning.
-----------------------------------
require('modules/module_utils')
-----------------------------------

xi = xi or {}
xi.trustRetailParity = xi.trustRetailParity or {}

local trustRetailParity = xi.trustRetailParity
local m = Module:new('trust_retail_parity')

local qaAdminName = 'Twills'
local entitlementVar = 'MochiriiTrustAllianceAccess'
local evidenceModeVar = 'MochiriiTrustEvidenceMode'
local evidenceSchemaVar = 'MochiriiTrustEvidenceSchema'
local sessionGenerationVar = 'MochiriiTrustSessionGeneration'
local sessionStartedVar = 'MochiriiTrustSessionStarted'
local sessionZoneVar = 'MochiriiTrustSessionZone'
local evidenceSequenceVar = 'MochiriiTrustEvidenceSeq'
local pendingTimersVar = 'MochiriiTrustAlliancePendingTimers'
local logTruncatedVar = 'MochiriiTrustLogTruncated'
local clearTrustsTestHook
local spawnTrustTestHook

local sessionState =
{
    IDLE = 0,
    SPAWNING = 1,
    READY = 2,
    FAILED = 3,
}

local evidenceMode =
{
    IDLE = 0,
    RETAIL = 1,
    QA = 2,
}

local stateNames =
{
    [sessionState.IDLE] = 'idle',
    [sessionState.SPAWNING] = 'spawning',
    [sessionState.READY] = 'ready',
    [sessionState.FAILED] = 'failed',
}

local modeNames =
{
    [evidenceMode.IDLE] = 'idle',
    [evidenceMode.RETAIL] = 'retail_control',
    [evidenceMode.QA] = 'twills_full_alliance_qa',
}

local topologyNames =
{
    [evidenceMode.IDLE] = 'none',
    [evidenceMode.RETAIL] = 'retail_party_1_plus_5',
    [evidenceMode.QA] = 'virtual_trust_alliance_5_6_6',
}

trustRetailParity.sessionState = sessionState
trustRetailParity.evidenceMode = evidenceMode

local function setting(name, default)
    if
        xi.settings == nil or
        xi.settings.main == nil or
        xi.settings.main[name] == nil
    then
        return default
    end

    return xi.settings.main[name]
end

local function settingEnabled(name, default)
    local value = setting(name, default)
    return value == true or value == 1
end

local function boolString(value)
    return value and 'true' or 'false'
end

local function safeCall(entity, methodName, ...)
    if entity == nil or type(entity[methodName]) ~= 'function' then
        return nil, false
    end

    local ok, value = pcall(entity[methodName], entity, ...)
    if not ok then
        return nil, false
    end

    return value, true
end

local function testEnvironmentActive()
    return xi.test ~= nil and xi.test.world ~= nil
end

local function normalizeTrustName(name)
    return tostring(name or ''):lower():gsub('[^%w]', '')
end

trustRetailParity.profiles =
{
    [xi.magic.spell.VALAINERAL] =
    {
        name = 'Valaineral',
        role = 'tank',
        jobModel = 'PLD/WAR',
        movement = 'melee tank',
        enmity = 'tank_assist',
        mpRest = 'none',
        status = 'implemented_partial',
        spellListId = 322,
        localVar = 'TrustParityValaineral',
        notes =
        {
            'PLD/WAR tank',
            'Banish III added to Trust spell list',
            'Palisade gambit added at level 95',
            'Banish III gambit is conservative: undead targets only until in-client retail timing is verified',
        },
    },

    [xi.magic.spell.QULTADA] =
    {
        name = 'Qultada',
        role = 'cor_support',
        jobModel = 'COR/NIN',
        movement = 'ranged support',
        enmity = 'shed',
        mpRest = 'none',
        status = 'implemented_partial',
        localVar = 'TrustParityQultada',
        runtimeVar = 'TrustParityQultadaV2',
        notes =
        {
            'COR/NIN support',
            'Chaos Roll plus Fighter\'s Roll baseline',
            'Corsair\'s Roll when Dedication or Commitment is active',
            'Double-Up when Mochirii marks an active roll as eligible',
            'Evoker\'s Roll as a guarded low-MP alternate second roll',
            'Triple Shot at level 87',
            'Dark Shot dispel and Light Shot Dia enhancement',
        },
    },

    [xi.magic.spell.JOACHIM] =
    {
        name = 'Joachim',
        role = 'bard_support',
        jobModel = 'BRD/WHM',
        movement = 'mid range',
        enmity = 'shed',
        mpRest = 'support',
        status = 'implemented_partial',
        localVar = 'TrustParityJoachim',
        runtimeVar = 'TrustParityJoachimV2',
        notes =
        {
            'BRD/WHM support',
            'March plus Madrigal baseline',
            'Elegy on engaged targets',
            'Ballad/Paeon recovery songs when party MP/HP is low',
            'Status removal, curing, and ranged attack behavior remain from Mochirii',
        },
    },

    [xi.magic.spell.ULMIA] =
    {
        name = 'Ulmia',
        role = 'bard_support',
        jobModel = 'BRD',
        movement = 'mid range',
        enmity = 'shed',
        mpRest = 'support',
        status = 'implemented_partial',
        localVar = 'TrustParityUlmia',
        runtimeVar = 'TrustParityUlmiaV2',
        notes =
        {
            'BRD support',
            'March baseline support',
            'Ballad when party MP is low',
            'Sentinel\'s Scherzo during danger windows',
            'Minuet/Madrigal offensive filler songs',
            'Auto-attacks disabled and mid-range positioning retained from Mochirii',
        },
    },

    [xi.magic.spell.KUPIPI] =
    {
        name = 'Kupipi',
        role = 'healer',
        jobModel = 'WHM/SCH',
        movement = 'backline caster',
        enmity = 'shed',
        mpRest = 'healer',
        status = 'implemented_partial',
        spellListId = 310,
        localVar = 'TrustParityKupipi',
        runtimeVar = 'TrustParityKupipiV2',
        playerLikeVar = 'TrustParityKupipiWhmSchV5',
        notes =
        {
            'WHM/SCH backline healer',
            'Cure I-VI, -na spells, Erase, Slow, Paralyze, Flash, Starlight, and Moonlight are already local Mochirii data',
            'Single-target Protect/Shell refreshes added alongside existing Protectra/Shellra with Protect V and Shell V at local level 76',
            'Mochirii player-like extension adds SCH subjob data plus Light Arts, Addendum: White, Penury, Celerity, Accession, Sublimation, storm spells, Haste, Regen, Dia, Addle, Repose, Auspice, Boost-MND, Curaga/Cura, Raise/Arise, Reraise, Bar-spells, Afflatus Solace, Divine Seal, Divine Caress, Asylum, Benediction, and Sacrosanctity',
            'Esuna is present in the spell list but is not auto-used until a Trust-safe targeting helper exists; Sacrifice is deferred because this checkout does not classify it as a clean mob-castable spell',
            'Auto-attacks disabled so she behaves like a backline healer',
        },
    },
}

trustRetailParity.nameProfiles =
{
    aaev = { name = 'AAEV', role = 'tank', jobModel = 'PLD/WHM', movement = 'melee tank', enmity = 'tank_assist', mpRest = 'none', status = 'audit_only' },
    adelheid = { name = 'Adelheid', role = 'nuker_control', jobModel = 'SCH/BLM', movement = 'backline caster', enmity = 'shed', mpRest = 'support_nuker', status = 'audit_profiled' },
    amchuchu = { name = 'Amchuchu', role = 'tank', jobModel = 'RUN/WAR', movement = 'melee tank', enmity = 'tank_assist', mpRest = 'none', status = 'qa_profiled', spellListId = 382, expected = 'runes, Provoke, Flash, Foil, Vallation/Valiance, Lunge/Swipe bursts, Battuta, One for All, Dimidiation', deferred = 'no broad movement changes before combat logs' },
    apururuuc = { name = 'Apururu UC', role = 'healer', jobModel = 'WHM/RDM', movement = 'backline caster', enmity = 'shed', mpRest = 'healer', status = 'qa_profiled', spellListId = 367, expected = 'Cure/Curaga, -na, Erase, Haste, Stoneskin, Protectra/Shellra, Nott, Convert', deferred = 'Devotion/Martyr until Trust-safe JA targeting is verified' },
    arcielaii = { name = 'Arciela II', role = 'hybrid_support_dps', jobModel = 'hybrid support', movement = 'mid range', enmity = 'shed', mpRest = 'support', status = 'qa_profiled' },
    august = { name = 'August', role = 'tank', jobModel = 'PLD/WAR', movement = 'melee tank', enmity = 'tank_assist', mpRest = 'none', status = 'audit_profiled', spellListId = 397, expected = 'Daybreak, Flash, Provoke, Sentinel, Palisade, Reprisal, Holy during Daybreak, unique WS chain', deferred = 'generic PLD cloning that would erase August identity' },
    cornelia = { name = 'Cornelia', role = 'haste_aura', jobModel = 'noncombat aura support', movement = 'backline aura', enmity = 'shed', mpRest = 'none', status = 'qa_profiled', expected = 'noncombat Haste aura only', deferred = 'melee, spellcasting, or generic GEO behavior' },
    joachim = { name = 'Joachim', role = 'bard_support', jobModel = 'BRD/WHM', movement = 'mid range', enmity = 'shed', mpRest = 'support', status = 'implemented_partial', spellListId = 323, expected = 'March/Madrigal, Ballad/Paeon recovery, Elegy, Magic Finale, cures, -na support, ranged attack', deferred = 'Lullaby/Soul Voice until target-sleep behavior is verified' },
    korumoru = { name = 'Koru-Moru', role = 'rdm_support', jobModel = 'RDM/WHM', movement = 'backline caster', enmity = 'shed', mpRest = 'support', status = 'implemented_partial', spellListId = 364, expected = 'Haste II, Refresh II, Phalanx II, Convert, Dia III, Slow II, Paralyze II, Addle, Frazzle II, Gravity II, Dispel', deferred = 'Refresh III/Frazzle III/Addle II until local spell rows are real' },
    kupipi = { name = 'Kupipi', role = 'healer', jobModel = 'WHM/SCH', movement = 'backline caster', enmity = 'shed', mpRest = 'healer', status = 'implemented_partial' },
    lilisetteii = { name = 'Lilisette II', role = 'melee_support', jobModel = 'DNC', movement = 'melee support', enmity = 'shed', mpRest = 'none', status = 'implemented_partial', skillListId = 1128, expected = 'Haste Samba, Box Step, Quickstep, Violent Flourish, Curing/Healing/Divine Waltz, Reverse Flourish, dagger WS', deferred = 'signature Lilisette II mobskills until action scripts exist' },
    luzaf = { name = 'Luzaf', role = 'melee_cor', jobModel = 'COR/NIN', movement = 'melee', enmity = 'shed', mpRest = 'none', status = 'audit_profiled' },
    matsuip = { name = 'Matsui-P', role = 'special_melee', jobModel = 'NIN/BLM', movement = 'melee', enmity = 'shed', mpRest = 'none', status = 'implemented_partial', spellListId = 435, skillListId = 1148, expected = 'Utsusemi, Hojo, Kurayami, Jubaku, Dokumori, katana WS, no tank assist', deferred = 'special Matsui-P-only behavior until sourced and locally supported' },
    monberaux = { name = 'Monberaux', role = 'special_healer', jobModel = 'special support', movement = 'non-engaging support', enmity = 'shed', mpRest = 'none', status = 'audit_profiled_non_tank' },
    mumorii = { name = 'Mumor II', role = 'melee_support', jobModel = 'DNC', movement = 'melee support', enmity = 'shed', mpRest = 'none', status = 'alternate_profiled' },
    qultada = { name = 'Qultada', role = 'cor_support', jobModel = 'COR/NIN', movement = 'ranged support', enmity = 'shed', mpRest = 'none', status = 'implemented_partial' },
    rosulatia = { name = 'Rosulatia', role = 'magic_support', jobModel = 'special support', movement = 'backline support', enmity = 'shed', mpRest = 'support', status = 'alternate_profiled' },
    selhteus = { name = 'Selh\'teus', role = 'special_support', jobModel = 'special PLD-coded support', movement = 'melee special', enmity = 'shed', mpRest = 'none', status = 'implemented_partial_non_tank', skillListId = 1094, expected = 'Rejuvenation, Luminous Lance, Revelation, melee special support, no tank assist', deferred = 'full retail AoE Rejuvenation tuning until combat logs prove target scope' },
    shantottoii = { name = 'Shantotto II', role = 'nuker', jobModel = 'BLM', movement = 'backline caster', enmity = 'shed', mpRest = 'nuker', status = 'audit_profiled', spellListId = 428, expected = 'scaled tier-I elemental nukes, magic burst, unique WS, backline nuker behavior', deferred = 'generic full BLM spellbook because local script intentionally scales her spell model' },
    starsibyl = { name = 'Star Sibyl', role = 'magic_attack_aura', jobModel = 'noncombat aura support', movement = 'backline aura', enmity = 'shed', mpRest = 'none', status = 'qa_profiled', expected = 'noncombat Magic Attack aura only', deferred = 'spellcasting or melee behavior' },
    sylvieuc = { name = 'Sylvie UC', role = 'geo_support', jobModel = 'GEO/WHM', movement = 'backline support', enmity = 'shed', mpRest = 'support', status = 'implemented_partial', spellListId = 394, expected = 'Cure, -na, Erase, Haste, Indi choices, Entrust, Nott, Unity parity', deferred = 'new Indi policy beyond BEST_INDI until combat logs show wrong aura choice' },
    ulmia = { name = 'Ulmia', role = 'bard_support', jobModel = 'BRD', movement = 'mid range', enmity = 'shed', mpRest = 'support', status = 'implemented_partial', spellListId = 326, expected = 'March, Prelude, Minuet, Madrigal, Ballad recovery, Scherzo danger support', deferred = 'Lullaby/Finale until logs show she needs enemy control' },
    valaineral = { name = 'Valaineral', role = 'tank', jobModel = 'PLD/WAR', movement = 'melee tank', enmity = 'tank_assist', mpRest = 'none', status = 'implemented_partial', spellListId = 322, skillListId = 1025, expected = 'Provoke, Shield Bash, Sentinel, Rampart, Chivalry, Majesty, Fealty, Palisade, Flash, Reprisal, Uriel Blade', deferred = 'Shell V because local PLD Trust data does not currently support it as a clean retail PLD tool' },
    yoranoranuc = { name = 'Yoran-Oran UC', role = 'healer', jobModel = 'WHM', movement = 'backline caster', enmity = 'shed', mpRest = 'healer', status = 'implemented_partial', spellListId = 393, skillListId = 1095, expected = 'Cure I-VI, -na, Erase, Haste, Protectra/Shellra, Stoneskin, Afflatus Solace, Nott', deferred = 'Devotion/Martyr until local Trust-safe JA targeting exists' },
}

local qaProfileAnnotations =
{
    amchuchu = { supportScope = 'alliance defensive response; self-tank mitigation and magic-tank tools', buffPolicy = 'runes and defensive buffs only when missing or expiring', rangeGoal = 'melee tank range', identity = 'preserve RUN magic-tank identity' },
    apururuuc = { supportScope = 'all 18 alliance members for cures, status removal, Erase, Haste, and recovery tools', buffPolicy = 'healer buffs and recovery tools only when missing, expiring, or emergency-gated', rangeGoal = 'backline caster range', identity = 'preserve Apururu UC healer/MP recovery identity' },
    august = { supportScope = 'alliance defensive response; tank protection and self sustain', buffPolicy = 'tank defensive buffs only when missing, expiring, or danger-gated', rangeGoal = 'melee tank range', identity = 'preserve August unique tank and weaponskill behavior' },
    cornelia = { supportScope = 'alliance aura support only', buffPolicy = 'passive aura; no spell or melee maintenance', rangeGoal = 'noncombat aura range', identity = 'preserve noncombat limited-time aura Trust identity' },
    joachim = { supportScope = 'Mochirii alliance song support plus BRD/WHM recovery where eligible', buffPolicy = 'songs and debuffs only when missing, expiring, recovery-gated, resisted, or dispelled', rangeGoal = 'mid-range bard support', identity = 'preserve Joachim ranged BRD/WHM support identity' },
    korumoru = { supportScope = 'all 18 alliance members for Refresh, Haste, Phalanx, and emergency support where eligible', buffPolicy = 'RDM buffs/debuffs only when missing, expiring, resisted, dispelled, or tier-upgraded', rangeGoal = 'backline RDM caster range', identity = 'preserve non-engaging Koru-Moru support/debuffer identity' },
    lilisetteii = { supportScope = 'melee support through samba, steps, and waltzes where local actions are safe', buffPolicy = 'DNC support actions only when missing, expiring, or tactical state requires them', rangeGoal = 'melee support range', identity = 'preserve Lilisette II melee-support identity' },
    matsuip = { supportScope = 'self shadows and target debuff ninjutsu; no tank assist', buffPolicy = 'Utsusemi and ninjutsu debuffs only when missing, expiring, resisted, or tactically useful', rangeGoal = 'melee NIN range', identity = 'preserve special Matsui-P identity instead of generic tank behavior' },
    monberaux = { supportScope = 'all 18 alliance members for special medicine support where local target rules allow', buffPolicy = 'special medicine actions only when needed; no melee or generic WHM clone behavior', rangeGoal = 'non-engaging support range', identity = 'preserve Monberaux non-engaging special healer identity' },
    qultada = { supportScope = 'Mochirii alliance roll support plus ranged COR actions', buffPolicy = 'rolls only when missing, expiring, bust-safe, or role context changes', rangeGoal = 'ranged COR support range', identity = 'preserve Qultada COR roll/ranged support identity' },
    selhteus = { supportScope = 'special alliance recovery with Rejuvenation-style tools where local action scope allows', buffPolicy = 'special support only when TP and party pressure justify it', rangeGoal = 'melee special support range', identity = "preserve Selh'teus special support identity and no tank assist" },
    shantottoii = { supportScope = 'hostile magic and burst pressure; support only through Trust-specific actions', buffPolicy = 'nukes follow target validity, MP, enmity, and burst opportunities', rangeGoal = 'backline nuker range', identity = 'preserve Shantotto II scaled elemental Trust model' },
    starsibyl = { supportScope = 'alliance magic aura support only', buffPolicy = 'passive aura; no spell or melee maintenance', rangeGoal = 'noncombat aura range', identity = 'preserve Star Sibyl noncombat aura identity' },
    sylvieuc = { supportScope = 'Mochirii alliance GEO/WHM support plus Unity parity', buffPolicy = 'Indi/Entrust/Haste/Erase support only when missing, expiring, or context-gated', rangeGoal = 'backline GEO support range', identity = 'preserve Sylvie UC support GEO identity' },
    ulmia = { supportScope = 'Mochirii alliance song support', buffPolicy = 'songs only when missing, expiring, or recovery/danger-gated', rangeGoal = 'mid-range bard support', identity = 'preserve Ulmia pure BRD support identity' },
    valaineral = { supportScope = 'alliance defensive response; PLD tank protection and enmity tools', buffPolicy = 'PLD defensive buffs only when missing, expiring, or danger-gated', rangeGoal = 'melee tank range', identity = 'preserve Valaineral PLD/WAR tank identity' },
    yoranoranuc = { supportScope = 'all 18 alliance members for cures, status removal, Erase, Haste, and recovery tools', buffPolicy = 'healer buffs and emergency tools only when missing, expiring, or emergency-gated', rangeGoal = 'backline caster range', identity = 'preserve Yoran-Oran UC non-melee healer identity' },
}

for profileKey, annotations in pairs(qaProfileAnnotations) do
    local profile = trustRetailParity.nameProfiles[profileKey]
    if profile ~= nil then
        for field, value in pairs(annotations) do
            if profile[field] == nil then
                profile[field] = value
            end
        end
    end
end

trustRetailParity.qaAllianceComposition =
{
    {
        party = 1,
        name = 'Twills RDM/SCH magic core',
        notes = 'RDM-led mixed party for debuff, magic burst, COR rolls, and one top-tier healer.',
        trusts =
        {
            { spell = xi.magic.spell.AUGUST, name = 'August', reason = 'PLD/WAR tank baseline for hate, Flash-style tanking, and tank-rest interaction checks.' },
            { spell = xi.magic.spell.YORAN_ORAN_UC, name = 'Yoran-Oran UC', reason = 'WHM healer baseline and Unity healer parity check.' },
            { spell = xi.magic.spell.KORU_MORU, name = 'Koru-Moru', reason = 'RDM support/debuffer for Haste II, Refresh II, Phalanx II, Dia III, Distract, and Convert behavior.' },
            { spell = xi.magic.spell.QULTADA, name = 'Qultada', reason = 'COR support/ranged test for roll priority, ranged distance, Quick Draw, and WS delay behavior.' },
            { spell = xi.magic.spell.CORNELIA, name = 'Cornelia', reason = 'Noncombat Haste aura support and limited-time Trust policy check for Twills core party.' },
        },
    },

    {
        party = 2,
        name = 'Physical support and melee core',
        notes = 'Physical party to test PLD tanking, special healing, BRD support, melee support, and melee DPS uptime.',
        trusts =
        {
            { spell = xi.magic.spell.VALAINERAL, name = 'Valaineral', reason = 'PLD/WAR tank baseline and known leveling/general-purpose tank comparison against August.' },
            { spell = xi.magic.spell.MONBERAUX, name = 'Monberaux', reason = 'Special non-engaging healer/support behavior must stay unique, not generic WHM.' },
            { spell = xi.magic.spell.JOACHIM, name = 'Joachim', reason = 'BRD/WHM support baseline for March/Madrigal, Ballad/Paeon recovery, and ranged behavior.' },
            { spell = xi.magic.spell.ULMIA, name = 'Ulmia', reason = 'BRD support contrast with Joachim for song overwrite and Ballad/Scherzo behavior.' },
            { spell = xi.magic.spell.LILISETTE_II, name = 'Lilisette II', reason = 'DNC melee-support test for melee range, TP use, and support identity.' },
            { spell = xi.magic.spell.MATSUI_P, name = 'Matsui-P', reason = 'Special melee Trust test that must avoid false tank classification.' },
        },
    },

    {
        party = 3,
        name = 'Magic control and special support core',
        notes = 'RUN tank plus GEO, WHM, BLM nuker, magic aura, and special recovery coverage.',
        trusts =
        {
            { spell = xi.magic.spell.AMCHUCHU, name = 'Amchuchu', reason = 'RUN tank baseline for magic-tank behavior and non-PLD tank comparison.' },
            { spell = xi.magic.spell.SYLVIE_UC, name = 'Sylvie UC', reason = 'GEO/WHM support, Unity stat parity, Indi/Geo choices, and support-rest checks.' },
            { spell = xi.magic.spell.APURURU_UC, name = 'Apururu UC', reason = 'WHM Unity healer contrast with Yoran-Oran UC for cure/status/remedy choices.' },
            { spell = xi.magic.spell.SHANTOTTO_II, name = 'Shantotto II', reason = 'BLM nuker test for magic burst, MP floor, and high-risk enmity shed behavior.' },
            { spell = xi.magic.spell.STAR_SIBYL, name = 'Star Sibyl', reason = 'Noncombat Magic Attack aura support for the magic-focused party.' },
            { spell = xi.magic.spell.SELHTEUS, name = 'Selh\'teus', reason = 'Special support/recovery behavior, TP timing, and non-tank PLD-coded classification.' },
        },
    },
}

trustRetailParity.retailControlComposition =
{
    {
        party = 1,
        name = 'Retail control party',
        notes = 'Twills plus the locked five-Trust retail-control roster.',
        trusts =
        {
            { spell = xi.magic.spell.VALAINERAL, name = 'Valaineral' },
            { spell = xi.magic.spell.YORAN_ORAN_UC, name = 'Yoran-Oran UC' },
            { spell = xi.magic.spell.ULMIA, name = 'Ulmia' },
            { spell = xi.magic.spell.LILISETTE_II, name = 'Lilisette II' },
            { spell = xi.magic.spell.SHANTOTTO_II, name = 'Shantotto II' },
        },
    },
}

trustRetailParity.roster =
{
    'aaev', 'aagk', 'aahm', 'aamr', 'aatt', 'abenzio', 'abquhbah', 'adelheid',
    'ajido-marujido', 'aldo', 'aldo_uc', 'amchuchu', 'apururu_uc', 'arciela', 'arciela_ii',
    'areuhat', 'august', 'ayame', 'ayame_uc', 'babban', 'balamor', 'brygid', 'chacharoon',
    'cherukiki', 'cid', 'cornelia', 'curilla', 'd_shantotto', 'darrcuiln', 'elivira',
    'excenmille', 'excenmille_s', 'fablinix', 'ferreous_coffin', 'flaviria_uc', 'gadalar',
    'gessho', 'gilgamesh', 'halver', 'i_shield_uc', 'ingrid', 'ingrid_ii', 'iroha', 'iroha_ii',
    'iron_eater', 'jakoh_uc', 'joachim', 'karaha-baruha', 'kayeel-payeel', 'king_of_hearts',
    'klara', 'koru-moru', 'kukki-chebukki', 'kupipi', 'kupofried', 'kuyin_hathdenna',
    'lehko_habhoka', 'leonoyne', 'lhe_lhangavo', 'lhu_mhakaracca', 'lilisette', 'lilisette_ii',
    'lion', 'lion_ii', 'luzaf', 'maat', 'maat_uc', 'makki-chebukki', 'margret', 'matsui-p',
    'maximilian', 'mayakov', 'mihli_aliapoh', 'mildaurion', 'mnejing', 'monberaux', 'moogle',
    'morimar', 'mumor', 'mumor_ii', 'naja_salaheem', 'naja_uc', 'najelith', 'naji', 'nanaa_mihgo',
    'nashmeira', 'nashmeira_ii', 'noillurie', 'ovjang', 'pieuje_uc', 'prishe', 'prishe_ii',
    'qultada', 'rahal', 'rainemard', 'robel-akbel', 'romaa_mihgo', 'rongelouts', 'rosulatia',
    'rughadjeen', 'sakura', 'selh_teus', 'semih_lafihna', 'shantotto', 'shantotto_ii',
    'shikaree_z', 'star_sibyl', 'sylvie_uc', 'tenzen', 'tenzen_ii', 'teodor', 'trion',
    'uka_totlihn', 'ullegore', 'ulmia', 'valaineral', 'volker', 'ygnas', 'yoran-oran_uc',
    'zazarg', 'zeid', 'zeid_ii',
}

local isTrust
local qaTrustIds
local rosterAudit

local function explicitNameProfileForName(name)
    return trustRetailParity.nameProfiles[normalizeTrustName(name)]
end

local function generatedProfileForName(name)
    return
    {
        name = tostring(name or 'unknown'),
        role = 'audit_pending',
        jobModel = 'local Trust script',
        movement = 'script-defined',
        enmity = 'profile_needed',
        mpRest = 'script-defined',
        status = 'generated_audit_profile',
        supportScope = 'script-defined; compare local Trust script, spell list, skill list, and latest logs',
        buffPolicy = 'maintenance buffs/debuffs must use missing-or-expiring gates',
        rangeGoal = 'script-defined',
        identity = 'preserve current Trust-specific behavior until source-backed parity is added',
        expected = 'profile pending; audit script keeps this Trust visible in roster-wide reports',
        deferred = 'full player-like parity pass pending source-backed audit',
    }
end

local function nameProfileForName(name)
    return explicitNameProfileForName(name) or generatedProfileForName(name)
end

local function profileForTrust(trust)
    if not isTrust(trust) then
        return nil
    end

    return trustRetailParity.profiles[trust:getTrustID()] or nameProfileForName(trust:getName())
end

isTrust = function(entity)
    return entity ~= nil and entity:getObjType() == xi.objType.TRUST
end

local function printLine(player, line)
    player:printToPlayer(line, xi.msg.channel.SYSTEM_3, '')
end

local function getSessionState(player)
    local state, called = safeCall(player, 'getTwillsFullAllianceState')
    state = tonumber(state)
    if not called or stateNames[state] == nil then
        return nil
    end

    return state
end

local function setSessionState(player, state)
    if stateNames[state] == nil then
        return false
    end

    local changed, called = safeCall(player, 'setTwillsFullAllianceState', state)
    return called and changed == true and getSessionState(player) == state
end

local function clearTrustsWithInactiveProjection(player)
    local state = getSessionState(player)
    if state ~= sessionState.IDLE and state ~= sessionState.FAILED then
        return false, 'trust_projection_active'
    end

    if clearTrustsTestHook ~= nil and not testEnvironmentActive() then
        clearTrustsTestHook = nil
    end

    if clearTrustsTestHook ~= nil and testEnvironmentActive() then
        clearTrustsTestHook(player)
    else
        player:clearTrusts()
    end
    return true, 'cleared'
end

trustRetailParity.setClearTrustsTestHook = function(hook)
    if not testEnvironmentActive() or (hook ~= nil and type(hook) ~= 'function') then
        return false
    end

    clearTrustsTestHook = hook
    return true
end

trustRetailParity.isQaSummonRunning = function(player)
    return
        player ~= nil and
        getSessionState(player) == sessionState.SPAWNING and
        player:getLocalVar(evidenceModeVar) == evidenceMode.QA
end

trustRetailParity.qaAllianceReady = function(player)
    if player == nil then
        return false, 0, 0
    end

    local audit = rosterAudit ~= nil and rosterAudit(player, evidenceMode.QA) or nil
    local expected = #qaTrustIds()
    local active = audit ~= nil and audit.activeCount or 0

    return audit ~= nil and audit.exactMatch, active, expected
end

local function applyValaineral(trust, profile)
    local lvl = trust:getMainLvl()
    local changed = false

    if profile.spellListId ~= nil then
        trust:setSpellList(profile.spellListId)
        changed = true
    end

    if trust:getLocalVar(profile.localVar) == 1 then
        return changed, 'spell list refreshed; spawn gambits already present'
    end

    if lvl >= 95 then
        trust:addGambit(ai.t.SELF, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.PALISADE }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.PALISADE })
        changed = true
    end

    if lvl >= 65 then
        trust:addGambit(ai.t.TARGET, { ai.c.IS_ECOSYSTEM, xi.ecosystem.UNDEAD }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.BANISH_III }, 45)
        changed = true
    end

    trust:setLocalVar(profile.localVar, 1)

    return changed, 'active gambits applied'
end

local function applyQultada(trust, profile)
    local changed = false
    local notes = {}

    if trust:getLocalVar(profile.localVar) ~= 1 then
        trust:addGambit(ai.t.TARGET, { ai.c.STATUS_FLAG, xi.effectFlag.DISPELABLE }, { ai.r.MS, ai.s.SPECIFIC, xi.mobSkill.DARK_SHOT }, 45)
        trust:addGambit(ai.t.TARGET, { ai.c.STATUS, xi.effect.DIA }, { ai.r.MS, ai.s.SPECIFIC, xi.mobSkill.LIGHT_SHOT }, 60)

        if trust:getMainLvl() >= 87 then
            trust:addGambit(ai.t.SELF, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.TRIPLE_SHOT }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.TRIPLE_SHOT })
        end

        trust:setLocalVar(profile.localVar, 1)
        changed = true
        notes[#notes + 1] = 'quick draw and Triple Shot gambits applied'
    end

    if trust:getLocalVar(profile.runtimeVar) ~= 1 then
        trust:addGambit(ai.t.SELF, {
            { ai.c.STATUS, xi.effect.DOUBLE_UP_CHANCE },
            { ai.c.TIMER, 8 },
        }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.DOUBLE_UP })

        if trust:getMainLvl() >= 40 then
            trust:addGambit(ai.t.PARTY, {
                { ai.c.MPP_LT, 66 },
                { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.EVOKERS_ROLL },
                { ai.c.NOT_STATUS, xi.effect.CORSAIRS_ROLL },
                { ai.c.NOT_STATUS, xi.effect.FIGHTERS_ROLL },
            }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.EVOKERS_ROLL })
        end

        trust:setLocalVar(profile.runtimeVar, 1)
        changed = true
        notes[#notes + 1] = 'Double-Up and guarded Evoker\'s Roll gambits applied'
    end

    if #notes == 0 then
        return false, 'spawn gambits already present'
    end

    return changed, table.concat(notes, '; ')
end

local function applyJoachim(trust, profile)
    local changed = false
    local notes = {}

    if trust:getLocalVar(profile.localVar) ~= 1 then
        trust:addGambit(ai.t.PARTY, { { ai.c.MPP_LT, 75 }, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.BALLAD } }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.MAGES_BALLAD })
        trust:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 75 }, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.PAEON } }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.ARMYS_PAEON })
        trust:addGambit(ai.t.SELF, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.MADRIGAL }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.MADRIGAL })

        trust:setLocalVar(profile.localVar, 1)
        changed = true
        notes[#notes + 1] = 'recovery song and Madrigal gambits applied'
    end

    if trust:getLocalVar(profile.runtimeVar) ~= 1 then
        trust:addGambit(ai.t.TARGET, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.ELEGY }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.ELEGY }, 60)
        trust:setLocalVar(profile.runtimeVar, 1)
        changed = true
        notes[#notes + 1] = 'Elegy gambit applied'
    end

    if #notes == 0 then
        return false, 'spawn gambits already present'
    end

    return changed, table.concat(notes, '; ')
end

local function applyUlmia(trust, profile)
    local changed = false
    local notes = {}

    if trust:getLocalVar(profile.localVar) ~= 1 then
        trust:addGambit(ai.t.SELF, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.MARCH }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.MARCH })
        trust:addGambit(ai.t.SELF, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.MINUET }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.VALOR_MINUET })
        trust:setLocalVar(profile.localVar, 1)
        changed = true
        notes[#notes + 1] = 'March and Minuet baseline gambits applied'
    end

    if trust:getLocalVar(profile.runtimeVar) ~= 1 then
        trust:addGambit(ai.t.PARTY, {
            { ai.c.HPP_LT, 40 },
            { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.SCHERZO },
        }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.SENTINELS_SCHERZO })

        trust:addGambit(ai.t.PARTY, {
            { ai.c.MPP_LT, 75 },
            { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.BALLAD },
        }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.MAGES_BALLAD })

        trust:addGambit(ai.t.SELF, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.MADRIGAL }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.MADRIGAL })
        trust:setLocalVar(profile.runtimeVar, 1)
        changed = true
        notes[#notes + 1] = 'Scherzo, Ballad, and Madrigal gambits applied'
    end

    if #notes == 0 then
        return false, 'spawn gambits already present'
    end

    return changed, table.concat(notes, '; ')
end

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

local function addKupipiDivineCaressGambits(trust)
    for _, statusEffect in ipairs(kupipiCaressStatuses) do
        trust:addGambit(ai.t.PARTY, { { ai.c.STATUS, statusEffect }, { ai.c.CASTER_MPP_GTE, 20 } }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.DIVINE_CARESS }, 60)
    end
end

local function addKupipiPlayerLikeCureGambits(trust)
    trust:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 20 }, { ai.c.CASTER_MPP_GTE, 35 }, { ai.c.HP_MISSING, 1400 } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURE_VI }, 8)
    trust:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 35 }, { ai.c.CASTER_MPP_GTE, 25 }, { ai.c.HP_MISSING, 800 } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURE_V }, 8)
    trust:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 55 }, { ai.c.CASTER_MPP_GTE, 15 }, { ai.c.HP_MISSING, 350 } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURE_IV }, 8)
    trust:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 75 }, { ai.c.CASTER_MPP_GTE, 18 }, { ai.c.HP_MISSING, 150 } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURE_III }, 8)
    trust:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 85 }, { ai.c.CASTER_MPP_GTE, 12 }, { ai.c.HP_MISSING, 60 } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.CURE_II }, 8)
end

local function addKupipiSustainModeGambits(trust)
    trust:addGambit(ai.t.SELF, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.AFFLATUS_SOLACE }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.AFFLATUS_SOLACE })
    trust:addGambit(ai.t.SELF, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.ADDENDUM_WHITE }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.LIGHT_ARTS })
    trust:addGambit(ai.t.SELF, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.ADDENDUM_WHITE }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.ADDENDUM_WHITE })

    trust:addGambit(ai.t.SELF, {
        { ai.c.MPP_LT, 50 },
        { ai.c.STATUS, xi.effect.SUBLIMATION_COMPLETE },
    }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.SUBLIMATION }, 60)
    trust:addGambit(ai.t.SELF, {
        { ai.c.MPP_LT, 75 },
        { ai.c.HPP_GTE, 75 },
        { ai.c.NOT_STATUS, xi.effect.SUBLIMATION_ACTIVATED },
        { ai.c.NOT_STATUS, xi.effect.SUBLIMATION_COMPLETE },
    }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.SUBLIMATION }, 60)
end

local function addKupipiPlayerLikeGambits(trust)
    trust:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 35 }, { ai.c.CASTER_MPP_LT, 8 } }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.BENEDICTION }, 300)
    trust:addGambit(ai.t.PARTY, { ai.c.HPP_LT, 15 }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.BENEDICTION }, 300)
    trust:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 35 }, { ai.c.CASTER_MPP_GTE, 15 }, { ai.c.CASTER_NOT_STATUS, xi.effect.DIVINE_SEAL } }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.DIVINE_SEAL }, 120)
    trust:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 30 }, { ai.c.CASTER_HPP_GTE, 40 }, { ai.c.CASTER_MPP_GTE, 20 }, { ai.c.STATUS_FLAG, xi.effectFlag.ERASABLE } }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.ASYLUM }, 3600)
    trust:addGambit(ai.t.SELF, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.AFFLATUS_SOLACE }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.AFFLATUS_SOLACE })

    trust:addGambit(ai.t.SELF, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.ADDENDUM_WHITE }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.LIGHT_ARTS })
    trust:addGambit(ai.t.SELF, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.ADDENDUM_WHITE }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.ADDENDUM_WHITE })

    trust:addGambit(ai.t.SELF, {
        { ai.c.MPP_LT, 50 },
        { ai.c.STATUS, xi.effect.SUBLIMATION_COMPLETE },
    }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.SUBLIMATION }, 60)
    trust:addGambit(ai.t.SELF, {
        { ai.c.MPP_LT, 75 },
        { ai.c.HPP_GTE, 75 },
        { ai.c.NOT_STATUS, xi.effect.SUBLIMATION_ACTIVATED },
        { ai.c.NOT_STATUS, xi.effect.SUBLIMATION_COMPLETE },
    }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.SUBLIMATION }, 60)

    trust:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 45 }, { ai.c.CASTER_MPP_GTE, 45 }, { ai.c.HP_MISSING, 600 } }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.PENURY }, 120)
    trust:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 45 }, { ai.c.CASTER_MPP_GTE, 45 }, { ai.c.HP_MISSING, 600 } }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.CURAGA }, 20)
    trust:addGambit(ai.t.PARTY_DEAD, { ai.c.CASTER_MPP_GTE, 35 }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.CELERITY }, 120)
    trust:addGambit(ai.t.PARTY_DEAD, { ai.c.CASTER_MPP_GTE, 35 }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.RAISE }, 30)
    trust:addGambit(ai.t.SELF, { { ai.c.MPP_GTE, 75 }, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.RERAISE } }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.RERAISE }, 300)

    trust:addGambit(ai.t.SELF, { { ai.c.MPP_GTE, 35 }, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.AQUAVEIL } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.AQUAVEIL }, 120)
    trust:addGambit(ai.t.SELF, { { ai.c.MPP_GTE, 35 }, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.STONESKIN } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.STONESKIN }, 120)
    trust:addGambit(ai.t.SELF, { { ai.c.MPP_GTE, 40 }, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.BLINK } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.BLINK }, 120)
    trust:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 45 }, { ai.c.CASTER_HPP_GTE, 50 }, { ai.c.CASTER_MPP_GTE, 20 } }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.SACROSANCTITY }, 300)
    trust:addGambit(ai.t.TARGET, { { ai.c.CASTER_MPP_GTE, 65 }, { ai.c.CAST_ELE_MA_SELF, 0 }, { ai.c.NEED_ELE_BAREFFECT, 0 } }, { ai.r.MA, ai.s.DEF_BAR_ELEMENT, 0 }, 20)
    trust:addGambit(ai.t.SELF, { { ai.c.MPP_GTE, 55 }, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.AUSPICE } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.AUSPICE }, 120)
    trust:addGambit(ai.t.SELF, { { ai.c.MPP_GTE, 45 }, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.MND_BOOST } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.BOOST_MND }, 300)
    trust:addGambit(ai.t.SELF, { { ai.c.MPP_GTE, 60 }, { ai.c.NO_STORM, 0 } }, { ai.r.MA, ai.s.STORM_DAY, 0 }, 60)

    trust:addGambit(ai.t.TANK, { { ai.c.CASTER_HPP_GTE, 75 }, { ai.c.CASTER_MPP_GTE, 55 }, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.HASTE } }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.HASTE })
    trust:addGambit(ai.t.MELEE, { { ai.c.CASTER_MPP_GTE, 55 }, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.HASTE } }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.HASTE })
    trust:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 75 }, { ai.c.CASTER_HPP_GTE, 75 }, { ai.c.CASTER_MPP_GTE, 65 }, { ai.c.HP_MISSING, 250 }, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.REGEN } }, { ai.r.JA, ai.s.SPECIFIC, xi.ja.ACCESSION }, 180)
    trust:addGambit(ai.t.PARTY, { { ai.c.HPP_LT, 85 }, { ai.c.CASTER_MPP_GTE, 30 }, { ai.c.HP_MISSING, 120 }, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.REGEN } }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.REGEN }, 45)

    trust:addGambit(ai.t.TARGET, { { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.SLOW }, { ai.c.CASTER_MPP_GTE, 45 } }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.SLOW }, 60)
    trust:addGambit(ai.t.TARGET, { { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.PARALYSIS }, { ai.c.CASTER_MPP_GTE, 45 } }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.PARALYZE }, 60)
    trust:addGambit(ai.t.TARGET, { { ai.c.CASTER_MPP_GTE, 60 }, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.DIA } }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.DIA }, 60)
    trust:addGambit(ai.t.TARGET, { { ai.c.CASTER_MPP_GTE, 50 }, { ai.c.CASTING_MA, 0 }, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.ADDLE } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.ADDLE }, 90)
    trust:addGambit(ai.t.TARGET, { { ai.c.CASTER_MPP_GTE, 50 }, { ai.c.CASTING_MA, 0 }, { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.SLEEP_I } }, { ai.r.MA, ai.s.SPECIFIC, xi.magic.spell.REPOSE }, 120)
end

local function applyKupipi(trust, profile)
    local changed = false
    local notes = {}

    if profile.spellListId ~= nil then
        trust:setSpellList(profile.spellListId)
        changed = true
        notes[#notes + 1] = 'spell list refreshed'
    end

    if trust:getLocalVar(profile.localVar) ~= 1 then
        trust:addGambit(ai.t.PARTY, { { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.PROTECT }, { ai.c.CASTER_MPP_GTE, 70 }, { ai.c.TIMER, 30 } }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.PROTECT })
        trust:addGambit(ai.t.PARTY, { { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.SHELL }, { ai.c.CASTER_MPP_GTE, 70 }, { ai.c.TIMER, 30 } }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.SHELL })
        trust:setAutoAttackEnabled(false)
        trust:setMobMod(xi.mobMod.TRUST_DISTANCE, xi.trust.movementType.NO_MOVE)
        trust:setLocalVar(profile.localVar, 1)
        changed = true
        notes[#notes + 1] = 'single-target Protect/Shell and no-auto-attack applied'
    end

    if trust:getLocalVar(profile.runtimeVar) ~= 1 then
        trust:addGambit(ai.t.SELF, { { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.PROTECT }, { ai.c.CASTER_MPP_GTE, 85 } }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.PROTECTRA })
        trust:addGambit(ai.t.SELF, { { ai.c.STATUS_MISSING_OR_EXPIRING, xi.effect.SHELL }, { ai.c.CASTER_MPP_GTE, 85 } }, { ai.r.MA, ai.s.HIGHEST, xi.magic.spellFamily.SHELLRA })
        trust:setLocalVar(profile.runtimeVar, 1)
        changed = true
        notes[#notes + 1] = 'Protectra/Shellra fallback refreshed'
    end

    if trust:getLocalVar(profile.playerLikeVar) ~= 1 then
        addKupipiPlayerLikeCureGambits(trust)
        addKupipiSustainModeGambits(trust)
        addKupipiDivineCaressGambits(trust)
        addKupipiPlayerLikeGambits(trust)
        trust:setLocalVar('TrustParityKupipiWhmSchV2', 1)
        trust:setLocalVar('TrustParityKupipiWhmSchV4', 1)
        trust:setLocalVar(profile.playerLikeVar, 1)
        changed = true
        notes[#notes + 1] = 'player-like WHM/SCH V5 caster-resource and rest-safe gambits applied'
    end

    if #notes == 0 then
        return false, 'spawn gambits already present'
    end

    return changed, table.concat(notes, '; ')
end

trustRetailParity.applyTrust = function(trust)
    if not isTrust(trust) then
        return false, 'not a Trust'
    end

    local owner = trust:getMaster()
    local authorized, predicateAvailable = safeCall(owner, 'canUseTwillsFullAlliance')
    if not predicateAvailable or authorized ~= true then
        return false, 'Twills full-alliance authorization required'
    end

    local trustId = trust:getTrustID()
    local profile = trustRetailParity.profiles[trustId] or nameProfileForName(trust:getName())
    if profile == nil then
        return false, 'no Mochirii parity profile yet'
    end

    local changed = false
    local notes = {}

    if profile.spellListId ~= nil then
        trust:setSpellList(profile.spellListId)
        changed = true
        notes[#notes + 1] = string.format('spell list %u refreshed', profile.spellListId)
    end

    if trustId == xi.magic.spell.VALAINERAL then
        return applyValaineral(trust, profile)
    elseif trustId == xi.magic.spell.QULTADA then
        return applyQultada(trust, profile)
    elseif trustId == xi.magic.spell.JOACHIM then
        return applyJoachim(trust, profile)
    elseif trustId == xi.magic.spell.ULMIA then
        return applyUlmia(trust, profile)
    elseif trustId == xi.magic.spell.KUPIPI then
        return applyKupipi(trust, profile)
    end

    if #notes > 0 then
        return changed, table.concat(notes, '; ')
    end

    return false, 'profile is script/SQL-applied on summon'
end

trustRetailParity.partyRows = function(player, apply)
    local rows = {}
    local party = player:getPartyWithTrusts()

    if apply then
        local authorized, predicateAvailable = safeCall(player, 'canUseTwillsFullAlliance')
        if not predicateAvailable or authorized ~= true then
            return { 'Repair denied: Twills full-alliance authorization required.' }
        end
    end

    for _, member in ipairs(party) do
        if isTrust(member) then
            local trustId = member:getTrustID()
            local profile = profileForTrust(member)
            local profileName = profile ~= nil and profile.name or 'unprofiled'
            local changed = false
            local note = profile == nil and 'no Mochirii parity profile yet' or 'profile available'

            if apply then
                changed, note = trustRetailParity.applyTrust(member)
            end

            rows[#rows + 1] = string.format(
                '%s trustId=%u lvl=%u profile=%s role=%s job=%s enmity=%s rest=%s status=%s changed=%s note=%s',
                member:getName(),
                trustId,
                member:getMainLvl(),
                profileName,
                profile ~= nil and (profile.role or 'unspecified') or 'missing',
                profile ~= nil and (profile.jobModel or 'unknown') or 'unknown',
                profile ~= nil and (profile.enmity or 'unknown') or 'unknown',
                profile ~= nil and (profile.mpRest or 'unknown') or 'unknown',
                profile ~= nil and (profile.status or 'audit_needed') or 'audit_needed',
                tostring(changed),
                note
            )
        end
    end

    if #rows == 0 then
        rows[#rows + 1] = 'No active Trusts found for this player.'
    end

    return rows
end

local function auditProfileRow(name, profile)
    if profile == nil then
        return string.format('%s profile=missing status=audit_needed', name)
    end

    local role = profile.role or 'unspecified'
    local supportScope = profile.supportScope
    if supportScope == nil then
        if role:find('healer') ~= nil then
            supportScope = 'alliance cures/status/recovery for eligible 18 members'
        elseif
            role:find('support') ~= nil or
            role:find('bard') ~= nil or
            role:find('cor') ~= nil or
            role:find('geo') ~= nil or
            role:find('aura') ~= nil or
            role:find('rdm') ~= nil
        then
            supportScope = 'Mochirii alliance support extension with logged target/result counts'
        elseif role == 'tank' then
            supportScope = 'shared alliance focus plus tank self/party protection'
        else
            supportScope = 'self/target actions; support only when Trust identity supports it'
        end
    end

    local buffPolicy = profile.buffPolicy or 'buffs/debuffs must use missing-or-expiring maintenance gates'
    local rangeGoal = profile.rangeGoal or profile.movement or 'script-defined'
    local identity = profile.identity or 'preserve Trust identity before generic player cloning'

    return string.format(
        '%s role=%s job=%s movement=%s range=%s enmity=%s rest=%s support=%s buff_policy=%s identity=%s status=%s expected=%s deferred=%s',
        profile.name or name,
        role,
        profile.jobModel or 'unknown',
        profile.movement or 'unknown',
        rangeGoal,
        profile.enmity or 'unknown',
        profile.mpRest or 'unknown',
        supportScope,
        buffPolicy,
        identity,
        profile.status or 'audit_needed',
        profile.expected or 'not specified',
        profile.deferred or 'none'
    )
end

trustRetailParity.compositionRows = function()
    local rows = {}

    rows[#rows + 1] = 'Recommended Mochirii Trust QA alliance composition:'
    rows[#rows + 1] = 'Party 1: Twills + August, Yoran-Oran UC, Koru-Moru, Qultada, Cornelia'

    for _, party in ipairs(trustRetailParity.qaAllianceComposition) do
        rows[#rows + 1] = string.format('Party %u - %s: %s', party.party, party.name, party.notes)

        for slot, entry in ipairs(party.trusts) do
            local partySlot = party.party == 1 and slot + 1 or slot
            rows[#rows + 1] = string.format('  P%u.%u %s - %s', party.party, partySlot, entry.name, entry.reason)
        end
    end

    return rows
end

qaTrustIds = function()
    local trustIds = {}

    for _, party in ipairs(trustRetailParity.qaAllianceComposition) do
        for _, entry in ipairs(party.trusts) do
            trustIds[#trustIds + 1] = entry.spell
        end
    end

    return trustIds
end

local function compositionForMode(mode)
    if mode == evidenceMode.RETAIL then
        return trustRetailParity.retailControlComposition
    elseif mode == evidenceMode.QA then
        return trustRetailParity.qaAllianceComposition
    end

    return nil
end

local function expectedRoster(mode)
    local entries = {}
    local parties = { {}, {}, {} }
    local composition = compositionForMode(mode) or {}

    for _, party in ipairs(composition) do
        for _, entry in ipairs(party.trusts) do
            entries[#entries + 1] = entry
            parties[party.party][#parties[party.party] + 1] = entry
        end
    end

    return entries, parties
end

local function csv(values)
    if #values == 0 then
        return 'none'
    end

    local result = {}
    for _, value in ipairs(values) do
        result[#result + 1] = tostring(value)
    end

    return table.concat(result, ',')
end

local function entryIds(entries)
    local values = {}
    for _, entry in ipairs(entries) do
        values[#values + 1] = entry.spell
    end

    return values
end

local function entryNames(entries)
    local values = {}
    for _, entry in ipairs(entries) do
        values[#values + 1] = entry.name
    end

    return values
end

rosterAudit = function(player, mode)
    local expectedEntries, parties = expectedRoster(mode)
    local expectedIds = entryIds(expectedEntries)
    local expectedSet = {}
    for _, trustId in ipairs(expectedIds) do
        expectedSet[trustId] = true
    end

    local party = player ~= nil and player:getPartyWithTrusts() or {}
    local activeIds = {}
    local activeNames = {}
    local seen = {}
    local realPcCount = 0
    local duplicateCount = 0
    local unexpectedCount = 0

    for _, member in ipairs(party) do
        if isTrust(member) then
            local trustId = member:getTrustID()
            activeIds[#activeIds + 1] = trustId
            activeNames[#activeNames + 1] = member:getName()
            if seen[trustId] then
                duplicateCount = duplicateCount + 1
            end

            seen[trustId] = true
            if not expectedSet[trustId] then
                unexpectedCount = unexpectedCount + 1
            end
        else
            realPcCount = realPcCount + 1
        end
    end

    local orderMatch = #activeIds == #expectedIds
    if orderMatch then
        for index, trustId in ipairs(expectedIds) do
            if activeIds[index] ~= trustId then
                orderMatch = false
                break
            end
        end
    end

    local party1Count = #party
    local party2Count = 0
    local party3Count = 0
    if mode == evidenceMode.QA then
        party1Count = math.min(#party, 6)
        party2Count = math.min(math.max(#party - 6, 0), 6)
        party3Count = math.max(#party - 12, 0)
    end

    local exactMatch =
        realPcCount == 1 and
        #party == #expectedIds + 1 and
        duplicateCount == 0 and
        unexpectedCount == 0 and
        orderMatch

    return
    {
        expectedEntries = expectedEntries,
        expectedIds = expectedIds,
        expectedNames = entryNames(expectedEntries),
        expectedParties = parties,
        expectedCount = #expectedIds,
        activeIds = activeIds,
        activeNames = activeNames,
        activeCount = #activeIds,
        realPcCount = realPcCount,
        party1Count = party1Count,
        party2Count = party2Count,
        party3Count = party3Count,
        duplicateCount = duplicateCount,
        unexpectedCount = unexpectedCount,
        orderMatch = orderMatch,
        exactMatch = exactMatch,
    }
end

trustRetailParity.rosterAudit = rosterAudit

local function rosterFields(player, mode)
    local audit = rosterAudit(player, mode)
    local party1 = audit.expectedParties[1]
    local party2 = audit.expectedParties[2]
    local party3 = audit.expectedParties[3]
    local attachedCount = 0
    if
        xi.trustActionLogger ~= nil and
        type(xi.trustActionLogger.attachmentCount) == 'function'
    then
        attachedCount = xi.trustActionLogger.attachmentCount(player)
    end

    return
    {
        'expected_count=' .. audit.expectedCount,
        'expected_trust_ids=' .. csv(audit.expectedIds),
        'expected_trust_names=' .. csv(audit.expectedNames),
        'expected_party1_trusts=' .. csv(entryNames(party1)),
        'expected_party2_trusts=' .. csv(entryNames(party2)),
        'expected_party3_trusts=' .. csv(entryNames(party3)),
        'expected_party1_count=' .. #party1,
        'expected_party2_count=' .. #party2,
        'expected_party3_count=' .. #party3,
        'expected_party1_trust_ids=' .. csv(entryIds(party1)),
        'expected_party2_trust_ids=' .. csv(entryIds(party2)),
        'expected_party3_trust_ids=' .. csv(entryIds(party3)),
        'active_count=' .. audit.activeCount,
        'active_trust_ids=' .. csv(audit.activeIds),
        'active_trust_names=' .. csv(audit.activeNames),
        'real_pc_count=' .. audit.realPcCount,
        'party1_count=' .. audit.party1Count,
        'party2_count=' .. audit.party2Count,
        'party3_count=' .. audit.party3Count,
        'duplicate_count=' .. audit.duplicateCount,
        'unexpected_count=' .. audit.unexpectedCount,
        'order_match=' .. boolString(audit.orderMatch),
        'exact_match=' .. boolString(audit.exactMatch),
        'attached_count=' .. attachedCount,
        'pending_timers=' .. (player:getLocalVar(pendingTimersVar) or 0),
    }, audit
end

local function appendFields(destination, source)
    for _, field in ipairs(source or {}) do
        destination[#destination + 1] = field
    end

    return destination
end

local function authorization(player)
    local authorized, called = safeCall(player, 'canUseTwillsFullAlliance')
    local active, activeCalled = safeCall(player, 'isTwillsFullAllianceActive')

    return
    {
        authorized = called and authorized == true,
        active = activeCalled and active == true,
        actualGm = tonumber(player and player:getGMLevel() or 0) or 0,
        visibleGm = tonumber(player and player:getVisibleGMLevel() or 0) or 0,
        entitlement = tonumber(player and player:getCharVar(entitlementVar) or 0) or 0,
        featureEnabled = settingEnabled('ENABLE_MOCHIRII_TWILLS_FULL_ALLIANCE', false),
        maxParties = tonumber(setting('MOCHIRII_TWILLS_FULL_ALLIANCE_MAX_PARTIES', 0)) or 0,
        predicateAvailable = called,
    }
end

trustRetailParity.authorization = authorization

local function authorizationFields(player)
    local auth = authorization(player)
    return
    {
        'entitlement=' .. auth.entitlement,
        'actual_gm=' .. auth.actualGm,
        'visible_gm=' .. auth.visibleGm,
        'authorized=' .. boolString(auth.authorized),
        'alliance_active=' .. boolString(auth.active),
        'authorization_predicate_available=' .. boolString(auth.predicateAvailable),
        'feature_enabled=' .. boolString(auth.featureEnabled),
        'max_parties=' .. auth.maxParties,
    }, auth
end

local function settingsFields(mode)
    local qa = mode == evidenceMode.QA
    local aep = settingEnabled('ENABLE_TRUST_ALTER_EGO_POINT_BONUSES', false)
    local unity = settingEnabled('ENABLE_TRUST_UNITY_RANK_STAT_PARITY', false)
    local defensive = settingEnabled('ENABLE_TRUST_DEFENSIVE_MODE', false)
    local sharedTarget = settingEnabled('ENABLE_TRUST_SHARED_TARGETING', false)
    local roleEnmity = settingEnabled('ENABLE_TRUST_ROLE_ENMITY', false)
    local combatRest = settingEnabled('ENABLE_TRUST_CASTER_COMBAT_RESTING', false)
    local extravaganza = tonumber(setting('ENABLE_TRUST_ALTER_EGO_EXTRAVAGANZA', 0)) or 0
    local expo = tonumber(setting('ENABLE_TRUST_ALTER_EGO_EXPO', 0)) or 0
    local expoEffective = qa and expo ~= 0

    return
    {
        'aep_setting=' .. boolString(aep),
        'aep_effective=' .. boolString(aep),
        'unity_setting=' .. boolString(unity),
        'unity_effective=' .. boolString(qa and unity),
        'campaign_extravaganza_setting=' .. extravaganza,
        'campaign_expo_setting=' .. expo,
        'campaign_extravaganza_effective=false',
        'campaign_expo_effective=' .. boolString(expoEffective),
        'campaign_effective=' .. boolString(expoEffective),
        'combat_summoning_setting=false',
        'combat_summoning_effective=false',
        'defensive_setting=' .. boolString(defensive),
        'defensive_effective=' .. boolString(qa and defensive),
        'shared_target_setting=' .. boolString(sharedTarget),
        'shared_target_effective=' .. boolString(qa and sharedTarget),
        'role_enmity_setting=' .. boolString(roleEnmity),
        'role_enmity_effective=' .. boolString(qa and roleEnmity),
        'combat_rest_setting=' .. boolString(combatRest),
        'combat_rest_effective=' .. boolString(qa and combatRest),
        'qa_extension=' .. boolString(qa),
        'qa_watermark=' .. (qa and 'MOCHIRII EXTENSION — NOT RETAIL ACCEPTANCE' or 'none'),
    }
end

local function loggerEvent(player, recordType, eventName, fields)
    if
        xi.trustActionLogger == nil or
        type(xi.trustActionLogger.recordSessionEvent) ~= 'function'
    then
        return false, 'logger_unavailable'
    end

    local called, success, reason = pcall(
        xi.trustActionLogger.recordSessionEvent,
        player,
        recordType,
        eventName,
        fields)
    if not called then
        return false, 'logger_exception'
    end

    return success == true, reason
end

local function resetLoggerLive(player)
    if
        xi.trustActionLogger == nil or
        type(xi.trustActionLogger.resetForLogin) ~= 'function'
    then
        return false
    end

    local called, success = pcall(xi.trustActionLogger.resetForLogin, player)
    return called and success == true
end

local function stateRows(player)
    local mode = tonumber(player:getLocalVar(evidenceModeVar) or 0) or 0
    local state = getSessionState(player)
    local fields, audit = rosterFields(player, mode)
    local auth = authorization(player)
    local rows =
    {
        string.format(
            'authorization name=%s actual_gm=%u visible_gm=%u entitlement=%u authorized=%s feature=%s max_parties=%u',
            player:getName(),
            auth.actualGm,
            auth.visibleGm,
            auth.entitlement,
            boolString(auth.authorized),
            boolString(auth.featureEnabled),
            auth.maxParties
        ),
        string.format(
            'session state=%s mode=%s topology=%s schema=%u generation=%u zone=%u engage_type=%u active=%s pending_timers=%u log_truncated=%s',
            stateNames[state] or 'invalid',
            modeNames[mode] or 'invalid',
            topologyNames[mode] or 'invalid',
            player:getLocalVar(evidenceSchemaVar),
            player:getLocalVar(sessionGenerationVar),
            player:getLocalVar(sessionZoneVar),
            player:getCharVar('TrustEngageType'),
            boolString(auth.active),
            player:getLocalVar(pendingTimersVar),
            boolString(player:getLocalVar(logTruncatedVar) == 1)
        ),
        string.format(
            'roster active=%u expected=%u real_pcs=%u parties=%u/%u/%u duplicate=%u unexpected=%u order=%s exact=%s ids=%s',
            audit.activeCount,
            audit.expectedCount,
            audit.realPcCount,
            audit.party1Count,
            audit.party2Count,
            audit.party3Count,
            audit.duplicateCount,
            audit.unexpectedCount,
            boolString(audit.orderMatch),
            boolString(audit.exactMatch),
            csv(audit.activeIds)
        ),
    }

    -- Keep the full machine-readable vector in the map log without flooding chat.
    print('Mochirii Trust mode: ' .. table.concat(fields, '\t'))
    return rows
end

trustRetailParity.modeRows = stateRows

trustRetailParity.sessionProgress = function(player)
    if player == nil then
        return 0, 0
    end

    local mode = player:getLocalVar(evidenceModeVar)
    if compositionForMode(mode) == nil then
        return 0, 0
    end

    local audit = rosterAudit(player, mode)
    return audit.activeCount, audit.expectedCount
end

local function resetSessionLocals(player)
    player:setCharVar('TrustEngageType', 0)
    player:setLocalVar(evidenceModeVar, evidenceMode.IDLE)
    player:setLocalVar(evidenceSchemaVar, 0)
    player:setLocalVar(sessionStartedVar, 0)
    player:setLocalVar(sessionZoneVar, 0)
    player:setLocalVar(evidenceSequenceVar, 0)
    player:setLocalVar(pendingTimersVar, 0)
    player:setLocalVar(logTruncatedVar, 0)
end

local function advanceSessionGeneration(player)
    local generation = tonumber(player:getLocalVar(sessionGenerationVar) or 0) or 0
    generation = generation >= 2147483646 and 1 or generation + 1
    player:setLocalVar(sessionGenerationVar, generation)
    return generation
end

local function preflight(player, mode)
    if player == nil then
        return false, 'missing_player'
    elseif compositionForMode(mode) == nil then
        return false, 'invalid_evidence_mode'
    end

    local auth = authorization(player)
    if not auth.predicateAvailable then
        return false, 'authorization_predicate_unavailable'
    elseif not auth.authorized then
        return false, 'twills_authorization_denied'
    elseif getSessionState(player) ~= sessionState.IDLE then
        return false, 'session_not_idle'
    elseif player:getLocalVar(evidenceModeVar) ~= evidenceMode.IDLE then
        return false, 'stale_evidence_mode'
    elseif player:getLocalVar(evidenceSchemaVar) ~= 0 then
        return false, 'stale_evidence_schema'
    elseif not settingEnabled('ENABLE_TRUST_CASTING', true) then
        return false, 'trust_casting_disabled'
    elseif player:checkSoloPartyAlliance() == 2 then
        return false, 'real_alliance_present'
    elseif not player:canUseMisc(xi.zoneMisc.TRUST) then
        return false, 'zone_disallows_trusts'
    elseif player:getZoneID() <= 0 then
        return false, 'invalid_zone'
    elseif player:getBattlefield() ~= nil or player:getBattlefieldID() ~= 0 then
        return false, 'battlefield_present'
    elseif player:getInstance() ~= nil then
        return false, 'instance_present'
    elseif player:hasEnmity() then
        return false, 'player_has_enmity'
    elseif player:isSeekingParty() then
        return false, 'seeking_party'
    end

    local audit = rosterAudit(player, mode)
    if audit.realPcCount ~= 1 then
        return false, 'real_player_roster_mismatch'
    end

    return true, 'ready'
end

trustRetailParity.preflight = preflight

local function guardSession(player, generation, mode, requiredState, summonGates)
    if player == nil then
        return false, 'missing_player'
    elseif type(generation) ~= 'number' or generation <= 0 then
        return false, 'invalid_generation'
    elseif player:getLocalVar(sessionGenerationVar) ~= generation then
        return false, 'stale_generation'
    elseif compositionForMode(mode) == nil then
        return false, 'invalid_evidence_mode'
    elseif player:getLocalVar(evidenceModeVar) ~= mode then
        return false, 'mode_changed'
    elseif player:getLocalVar(evidenceSchemaVar) ~= 2 then
        return false, 'invalid_evidence_schema'
    elseif player:getLocalVar(logTruncatedVar) ~= 0 then
        return false, 'log_truncated'
    elseif getSessionState(player) ~= requiredState then
        return false, 'state_changed'
    elseif player:getLocalVar(sessionStartedVar) <= 0 then
        return false, 'invalid_session_start'
    elseif player:getLocalVar(sessionZoneVar) ~= player:getZoneID() then
        return false, 'zone_changed'
    elseif not authorization(player).authorized then
        return false, 'authorization_revoked'
    elseif player:checkSoloPartyAlliance() == 2 then
        return false, 'real_alliance_present'
    end

    if rosterAudit(player, mode).realPcCount ~= 1 then
        return false, 'real_party_member_present'
    end

    if summonGates then
        if not settingEnabled('ENABLE_TRUST_CASTING', true) then
            return false, 'trust_casting_disabled'
        elseif not player:canUseMisc(xi.zoneMisc.TRUST) then
            return false, 'zone_disallows_trusts'
        elseif player:getBattlefield() ~= nil or player:getBattlefieldID() ~= 0 then
            return false, 'battlefield_present'
        elseif player:getInstance() ~= nil then
            return false, 'instance_present'
        elseif player:hasEnmity() then
            return false, 'player_has_enmity'
        elseif player:isSeekingParty() then
            return false, 'seeking_party'
        end
    end

    return true, 'current'
end

local function scheduleSessionTimer(player, generation, delay, callback)
    if
        player == nil or
        player:getLocalVar(sessionGenerationVar) ~= generation
    then
        return false
    end

    player:setLocalVar(pendingTimersVar, player:getLocalVar(pendingTimersVar) + 1)
    player:timer(delay, function(playerArg)
        if
            playerArg ~= nil and
            playerArg:getLocalVar(sessionGenerationVar) == generation
        then
            playerArg:setLocalVar(pendingTimersVar, math.max(0, playerArg:getLocalVar(pendingTimersVar) - 1))
            callback(playerArg, generation)
        end
    end)

    return true
end

local function finishEvidenceSession(player, mode, completion, reason)
    local fields = rosterFields(player, mode)
    appendFields(fields, authorizationFields(player))
    appendFields(fields, settingsFields(mode))
    fields[#fields + 1] = 'final_pending_timers=' .. player:getLocalVar(pendingTimersVar)

    if
        xi.trustActionLogger ~= nil and
        type(xi.trustActionLogger.endSession) == 'function'
    then
        local called, success = pcall(
            xi.trustActionLogger.endSession,
            player,
            completion,
            reason,
            fields)
        return called and success == true
    end

    return false
end

local function clearTrustsAndVerify(player, mode)
    local fields
    local audit
    local clearReason = 'clear_not_attempted'
    for _ = 1, 2 do
        player:setLocalVar(pendingTimersVar, 0)
        local cleared
        cleared, clearReason = clearTrustsWithInactiveProjection(player)
        if not cleared then
            return false, fields, audit, clearReason
        end

        fields, audit = rosterFields(player, mode)
        if audit.activeCount == 0 and player:getLocalVar(pendingTimersVar) == 0 then
            return true, fields, audit, 'cleared'
        end

        clearReason = 'clear_verification_mismatch'
    end

    return false, fields, audit, clearReason
end

local function abortPreparedSession(player, mode, reason)
    local failureReason = reason or 'prepared_session_failed'
    player:setLocalVar(pendingTimersVar, 0)
    player:setCharVar('TrustEngageType', 0)

    local fields = rosterFields(player, mode)
    fields[#fields + 1] = 'reason=' .. failureReason
    loggerEvent(player, 'roster', 'failure', fields)
    loggerEvent(player, 'session_state', 'idle', {
        'reason=' .. failureReason,
    })
    finishEvidenceSession(player, mode, 'failed', failureReason)
    advanceSessionGeneration(player)
    resetSessionLocals(player)
    resetLoggerLive(player)

    print(string.format(
        'Mochirii Trust prepared session aborted: player=%s reason=%s',
        player:getName(),
        failureReason
    ))
    printLine(player, string.format(
        'Mochirii Trust summon aborted before spawning (%s).',
        failureReason
    ))
    return false, failureReason
end


local function failSession(player, generation, reason)
    if
        player == nil or
        player:getLocalVar(sessionGenerationVar) ~= generation
    then
        return false
    end

    local mode = player:getLocalVar(evidenceModeVar)
    local state = getSessionState(player)
    if modeNames[mode] == nil or mode == evidenceMode.IDLE then
        if
            state ~= sessionState.IDLE and
            state ~= sessionState.FAILED and
            not setSessionState(player, sessionState.FAILED)
        then
            return false
        end

        if not clearTrustsWithInactiveProjection(player) then
            return false
        end

        if
            getSessionState(player) == sessionState.FAILED and
            not setSessionState(player, sessionState.IDLE)
        then
            return false
        end

        resetSessionLocals(player)
        return false
    end

    if
        state ~= sessionState.FAILED and
        not setSessionState(player, sessionState.FAILED)
    then
        print(string.format(
            'Mochirii Trust session cleanup blocked: player=%s reason=%s state=%s',
            player:getName(),
            tostring(reason),
            stateNames[state] or 'invalid'
        ))
        return false
    end

    local stateFields = authorizationFields(player)
    stateFields[#stateFields + 1] = 'reason=' .. tostring(reason or 'unknown_failure')
    loggerEvent(player, 'session_state', 'failed', stateFields)

    local failureFields = rosterFields(player, mode)
    failureFields[#failureFields + 1] = 'reason=' .. tostring(reason or 'unknown_failure')
    loggerEvent(player, 'roster', 'failure', failureFields)

    player:setLocalVar(pendingTimersVar, 0)
    player:setCharVar('TrustEngageType', 0)
    local cleared, clearedFields, _, clearReason = clearTrustsAndVerify(player, mode)
    local terminalReason = tostring(reason or 'unknown_failure')
    clearedFields = clearedFields or rosterFields(player, mode)
    clearedFields[#clearedFields + 1] = 'reason=' .. terminalReason
    if cleared then
        loggerEvent(player, 'roster', 'cleared', clearedFields)
    else
        terminalReason = terminalReason .. '_' .. tostring(clearReason or 'cleanup_failed')
        clearedFields[#clearedFields + 1] = 'cleanup_mismatch=true'
        loggerEvent(player, 'roster', 'failure', clearedFields)
    end

    if not setSessionState(player, sessionState.IDLE) then
        safeCall(player, 'setLocalVar', 'MochiriiTrustSessionState', sessionState.IDLE)
    end

    loggerEvent(player, 'session_state', 'idle', {
        'reason=' .. terminalReason,
    })

    finishEvidenceSession(player, mode, 'failed', terminalReason)
    advanceSessionGeneration(player)
    resetSessionLocals(player)
    resetLoggerLive(player)

    print(string.format('Mochirii Trust session failed: player=%s reason=%s', player:getName(), tostring(reason)))
    printLine(player, string.format('Mochirii Trust session failed safely (%s); partial Trusts were cleared.', tostring(reason)))
    return false
end

trustRetailParity.failSession = failSession

trustRetailParity.setSpawnTrustTestHook = function(hook)
    if not testEnvironmentActive() or (hook ~= nil and type(hook) ~= 'function') then
        return false
    end

    spawnTrustTestHook = hook
    return true
end

trustRetailParity.spawnTrust = function(player, trustId)
    if player == nil then
        return nil, 'missing_player'
    end

    local mode = player:getLocalVar(evidenceModeVar)
    local generation = player:getLocalVar(sessionGenerationVar)
    local current, reason = guardSession(
        player,
        generation,
        mode,
        sessionState.SPAWNING,
        true)
    if not current then
        return nil, reason
    end

    local expected = false
    for _, entry in ipairs(expectedRoster(mode)) do
        if entry.spell == trustId then
            expected = true
            break
        end
    end
    if not expected then
        return nil, 'trust_not_in_locked_roster'
    end

    if spawnTrustTestHook ~= nil and testEnvironmentActive() then
        return spawnTrustTestHook(player, trustId)
    end

    return player:spawnTrust(trustId)
end

local function readyWatchdog(player, generation)
    local mode = player:getLocalVar(evidenceModeVar)
    local current, reason = guardSession(player, generation, mode, sessionState.READY, false)
    if not current then
        failSession(player, generation, 'watchdog_' .. reason)
        return
    end

    local _, audit = rosterFields(player, mode)
    local attached =
        xi.trustActionLogger ~= nil and
        xi.trustActionLogger.attachmentCount ~= nil and
        xi.trustActionLogger.attachmentCount(player) or 0
    if not audit.exactMatch or attached ~= audit.expectedCount then
        failSession(player, generation, not audit.exactMatch and 'watchdog_roster_mismatch' or 'watchdog_logger_mismatch')
        return
    end

    -- Keep a single bounded health timer live without adding periodic evidence
    -- rows. Any generation-changing clear invalidates the callback in
    -- scheduleSessionTimer before it can inspect or reschedule the old session.
    scheduleSessionTimer(player, generation, 5000, readyWatchdog)
end

local function completeSummon(player, generation, mode)
    local current, reason = guardSession(player, generation, mode, sessionState.SPAWNING, true)
    if not current then
        failSession(player, generation, reason)
        return false
    end

    local _, audit = rosterFields(player, mode)
    local attached =
        xi.trustActionLogger ~= nil and
        xi.trustActionLogger.attachmentCount ~= nil and
        xi.trustActionLogger.attachmentCount(player) or 0
    if not audit.exactMatch then
        failSession(player, generation, 'summon_roster_mismatch')
        return false
    elseif attached ~= audit.expectedCount then
        failSession(player, generation, 'logger_attachment_mismatch')
        return false
    end

    -- Profile repair is deterministic and mode-neutral; it cannot select or
    -- alter the evidence lane or TrustEngageType.
    local repairRows = trustRetailParity.partyRows(player, true)
    for _, row in ipairs(repairRows) do
        print('Mochirii Trust session repair: ' .. row)
    end

    if not setSessionState(player, sessionState.READY) then
        failSession(player, generation, 'ready_transition_rejected')
        return false
    end

    local stateFields = authorizationFields(player)
    appendFields(stateFields, settingsFields(mode))
    if not loggerEvent(player, 'session_state', 'ready', stateFields) then
        failSession(player, generation, 'ready_state_log_failed')
        return false
    end

    scheduleSessionTimer(player, generation, 5000, readyWatchdog)

    local fields = rosterFields(player, mode)
    appendFields(fields, authorizationFields(player))
    appendFields(fields, settingsFields(mode))
    if not loggerEvent(player, 'roster', 'summon_complete', fields) then
        failSession(player, generation, 'summon_complete_log_failed')
        return false
    end

    local checkpointFields = rosterFields(player, mode)
    appendFields(checkpointFields, authorizationFields(player))
    appendFields(checkpointFields, settingsFields(mode))
    checkpointFields[#checkpointFields + 1] = 'combat_acceptance=not_run'
    if not loggerEvent(player, 'checkpoint', 'summon_complete', checkpointFields) then
        failSession(player, generation, 'checkpoint_log_failed')
        return false
    end

    print(string.format(
        'Mochirii Trust session ready: player=%s mode=%s active=%u topology=%s',
        player:getName(),
        modeNames[mode],
        audit.activeCount,
        topologyNames[mode]
    ))
    printLine(player, string.format(
        'Mochirii Trust summon complete: mode=%s Trusts=%u topology=%s.',
        modeNames[mode],
        audit.activeCount,
        topologyNames[mode]
    ))

    if mode == evidenceMode.QA then
        printLine(player, 'MOCHIRII EXTENSION — NOT RETAIL ACCEPTANCE')
    end

    return true
end


local function spawnRoster(player, generation, mode, index)
    local current, reason = guardSession(player, generation, mode, sessionState.SPAWNING, true)
    if not current then
        failSession(player, generation, reason)
        return
    end

    if GetSystemTime() - player:getLocalVar(sessionStartedVar) > 45 then
        failSession(player, generation, 'summon_timeout')
        return
    end

    local entries = expectedRoster(mode)
    if index > #entries then
        completeSummon(player, generation, mode)
        return
    end

    local entry = entries[index]
    local called, trust = pcall(trustRetailParity.spawnTrust, player, entry.spell)
    if not called or trust == nil then
        local fields = rosterFields(player, mode)
        fields[#fields + 1] = 'trust_id=' .. entry.spell
        fields[#fields + 1] = 'trust_name=' .. entry.name
        fields[#fields + 1] = 'spawn_index=' .. index
        fields[#fields + 1] = 'spawn_ok=false'
        loggerEvent(player, 'roster', 'spawn_result', fields)
        failSession(player, generation, 'spawn_returned_nil_' .. entry.spell)
        return
    elseif not isTrust(trust) or trust:getTrustID() ~= entry.spell then
        failSession(player, generation, 'spawn_identity_mismatch_' .. entry.spell)
        return
    end

    local attached, attachReason = false, 'logger_unavailable'
    if
        xi.trustActionLogger ~= nil and
        type(xi.trustActionLogger.attach) == 'function'
    then
        local attachCalled
        attachCalled, attached, attachReason = pcall(
            xi.trustActionLogger.attach,
            trust,
            'evidence-spawn',
            generation)
        if not attachCalled then
            attached = false
            attachReason = 'logger_attach_exception'
        end
    end

    if not attached then
        loggerEvent(player, 'logger', 'logger_attach_failed', {
            'trust_id=' .. entry.spell,
            'trust_name=' .. entry.name,
            'attach_reason=' .. tostring(attachReason or 'unknown'),
            'attached_count=' .. (
                xi.trustActionLogger ~= nil and
                xi.trustActionLogger.attachmentCount ~= nil and
                xi.trustActionLogger.attachmentCount(player) or 0
            ),
        })
        failSession(player, generation, 'logger_attach_failed_' .. entry.spell)
        return
    end

    local spawnFields = rosterFields(player, mode)
    spawnFields[#spawnFields + 1] = 'trust_id=' .. entry.spell
    spawnFields[#spawnFields + 1] = 'trust_name=' .. entry.name
    spawnFields[#spawnFields + 1] = 'spawn_index=' .. index
    spawnFields[#spawnFields + 1] = 'spawn_ok=true'
    if not loggerEvent(player, 'roster', 'spawn_result', spawnFields) then
        failSession(player, generation, 'spawn_result_log_failed_' .. entry.spell)
        return
    end

    scheduleSessionTimer(player, generation, 500, function(nextPlayer)
        spawnRoster(nextPlayer, generation, mode, index + 1)
    end)
end

local function beginEvidenceSession(player, mode)
    local allowed, reason = preflight(player, mode)
    if not allowed then
        printLine(player, string.format('Mochirii Trust summon denied: %s.', reason))
        return false, reason
    end

    local generation = advanceSessionGeneration(player)
    local startedAt = GetSystemTime()
    player:setLocalVar(evidenceModeVar, mode)
    player:setLocalVar(evidenceSchemaVar, 2)
    player:setLocalVar(sessionGenerationVar, generation)
    player:setLocalVar(sessionStartedVar, startedAt)
    player:setLocalVar(sessionZoneVar, player:getZoneID())
    player:setLocalVar(evidenceSequenceVar, 0)
    player:setLocalVar(pendingTimersVar, 0)
    player:setLocalVar(logTruncatedVar, 0)
    player:setCharVar('TrustEngageType', mode == evidenceMode.QA and 1 or 0)

    local beginFields = rosterFields(player, mode)
    appendFields(beginFields, authorizationFields(player))
    appendFields(beginFields, settingsFields(mode))

    if
        xi.trustActionLogger == nil or
        type(xi.trustActionLogger.beginSession) ~= 'function'
    then
        resetSessionLocals(player)
        return false, 'logger_unavailable'
    end

    local beginCalled, began, beginReason = pcall(xi.trustActionLogger.beginSession, player, beginFields)
    if not beginCalled then
        began = false
        beginReason = 'logger_exception'
    end
    if not began then
        resetSessionLocals(player)
        printLine(player, string.format('Mochirii Trust summon denied: evidence logger %s.', tostring(beginReason)))
        return false, beginReason or 'session_begin_failed'
    end

    local preflightFields = rosterFields(player, mode)
    appendFields(preflightFields, authorizationFields(player))
    if not loggerEvent(player, 'roster', 'preflight', preflightFields) then
        return abortPreparedSession(player, mode, 'preflight_log_failed')
    end

    -- Rotate evidence and record the preflight while the native projection is
    -- still inactive. Existing Trusts are not touched unless both operations
    -- succeed, so logger preparation failures preserve the player's roster.
    local cleared, clearedFields, clearedAudit, clearReason = clearTrustsAndVerify(player, mode)
    if
        not cleared or
        clearedAudit == nil or
        clearedAudit.activeCount ~= 0 or
        clearedAudit.realPcCount ~= 1
    then
        return abortPreparedSession(player, mode, 'initial_clear_' .. tostring(clearReason or 'mismatch'))
    end

    if not loggerEvent(player, 'roster', 'cleared', clearedFields) then
        return abortPreparedSession(player, mode, 'cleared_log_failed')
    end

    if not setSessionState(player, sessionState.SPAWNING) then
        return abortPreparedSession(player, mode, 'spawning_transition_rejected')
    end

    local stateFields = authorizationFields(player)
    appendFields(stateFields, settingsFields(mode))
    if not loggerEvent(player, 'session_state', 'spawning', stateFields) then
        failSession(player, generation, 'spawning_state_log_failed')
        return false, 'spawning_state_log_failed'
    end

    local checkpointFields = rosterFields(player, mode)
    appendFields(checkpointFields, authorizationFields(player))
    appendFields(checkpointFields, settingsFields(mode))
    if not loggerEvent(player, 'checkpoint', 'summon_attempt', checkpointFields) then
        failSession(player, generation, 'summon_attempt_log_failed')
        return false, 'summon_attempt_log_failed'
    end
    scheduleSessionTimer(player, generation, 250, function(nextPlayer)
        spawnRoster(nextPlayer, generation, mode, 1)
    end)
    scheduleSessionTimer(player, generation, 45000, function(timeoutPlayer)
        if getSessionState(timeoutPlayer) == sessionState.SPAWNING then
            failSession(timeoutPlayer, generation, 'summon_timeout')
        end
    end)

    printLine(player, string.format(
        'Starting Mochirii Trust summon: mode=%s expected=%u.',
        modeNames[mode],
        #expectedRoster(mode)
    ))
    return true, 'spawning'
end

trustRetailParity.beginEvidenceSession = beginEvidenceSession
trustRetailParity.summonRetail = function(player)
    return beginEvidenceSession(player, evidenceMode.RETAIL)
end

trustRetailParity.summonQa = function(player)
    return beginEvidenceSession(player, evidenceMode.QA)
end

trustRetailParity.autoSummonQaParty = trustRetailParity.summonQa

trustRetailParity.clearSession = function(player, reason)
    if player == nil then
        return false, 'missing_player'
    elseif player:getName() ~= qaAdminName then
        return false, 'wrong_character'
    end

    local mode = player:getLocalVar(evidenceModeVar)
    local state = getSessionState(player)
    if state == nil then
        return false, 'invalid_session_state'
    end

    if mode == evidenceMode.IDLE and state == sessionState.IDLE then
        local cleared = clearTrustsAndVerify(player, evidenceMode.IDLE)

        advanceSessionGeneration(player)
        resetSessionLocals(player)
        resetLoggerLive(player)

        return cleared, cleared and 'already_idle' or 'idle_clear_verification_failed'
    end

    if mode == evidenceMode.IDLE then
        failSession(player, player:getLocalVar(sessionGenerationVar), 'manual_clear_stale_state')
        return false, 'manual_clear_stale_state'
    elseif not setSessionState(player, sessionState.IDLE) then
        failSession(player, player:getLocalVar(sessionGenerationVar), 'manual_clear_idle_transition_rejected')
        return false, 'manual_clear_idle_transition_rejected'
    end

    player:setLocalVar(pendingTimersVar, 0)
    player:setCharVar('TrustEngageType', 0)
    local cleared, clearedFields, _, clearReason = clearTrustsAndVerify(player, mode)
    local terminalReason = tostring(reason or 'manual_clear')
    clearedFields = clearedFields or rosterFields(player, mode)
    clearedFields[#clearedFields + 1] = 'reason=' .. terminalReason
    local rosterLogged
    if cleared then
        rosterLogged = loggerEvent(player, 'roster', 'cleared', clearedFields)
    else
        terminalReason = terminalReason .. '_' .. tostring(clearReason or 'cleanup_failed')
        clearedFields[#clearedFields + 1] = 'cleanup_mismatch=true'
        rosterLogged = loggerEvent(player, 'roster', 'failure', clearedFields)
    end

    local idleLogged = loggerEvent(player, 'session_state', 'idle', {
        'reason=' .. terminalReason,
    })

    local ended = finishEvidenceSession(
        player,
        mode,
        cleared and 'cleared' or 'failed',
        terminalReason)
    advanceSessionGeneration(player)
    resetSessionLocals(player)
    local liveReset = resetLoggerLive(player)

    local evidenceClosed = rosterLogged and idleLogged and ended and liveReset
    if cleared and evidenceClosed then
        printLine(player, 'Mochirii Trust session cleared: zero Trusts, idle mode, TrustEngageType=0.')
        return true, 'cleared'
    end

    printLine(player, string.format(
        'Mochirii Trust cleanup completed with a failed evidence close (%s).',
        terminalReason
    ))
    return false, cleared and 'evidence_close_failed' or 'manual_clear_verification_failed'
end

trustRetailParity.isCombatTestReady = function(player)
    local mode = player ~= nil and player:getLocalVar(evidenceModeVar) or evidenceMode.IDLE
    local state = player ~= nil and getSessionState(player) or nil
    if
        (mode ~= evidenceMode.RETAIL and mode ~= evidenceMode.QA) or
        state ~= sessionState.READY
    then
        return false, 'evidence_session_not_ready'
    end

    local current, reason = guardSession(
        player,
        player:getLocalVar(sessionGenerationVar),
        mode,
        sessionState.READY,
        false)
    if not current then
        return false, reason
    end

    local audit = rosterAudit(player, mode)
    if not audit.exactMatch then
        return false, 'roster_mismatch'
    end

    return true, modeNames[mode]
end

trustRetailParity.auditRows = function(player, target)
    local rows = {}
    local scope = target or 'active'

    if scope == 'active' then
        rows[#rows + 1] = 'Active Trust retail-player parity audit:'
        for _, member in ipairs(player:getPartyWithTrusts()) do
            if isTrust(member) then
                rows[#rows + 1] = auditProfileRow(member:getName(), profileForTrust(member))
            end
        end

        if #rows == 1 then
            rows[#rows + 1] = 'No active Trusts found for this player.'
        end

        return rows
    end

    if scope == 'all' then
        local explicitProfiles = 0
        local generatedProfiles = 0
        for _, rosterName in ipairs(trustRetailParity.roster) do
            if explicitNameProfileForName(rosterName) ~= nil then
                explicitProfiles = explicitProfiles + 1
            else
                generatedProfiles = generatedProfiles + 1
            end
        end

        rows[#rows + 1] = string.format('Trust roster audit: local_scripts=%u explicit_profiles=%u generated_audit_profiles=%u behavior_patches=%u', #trustRetailParity.roster, explicitProfiles, generatedProfiles, 13)
        rows[#rows + 1] = 'Full file/log comparison: run tools/mochirii/trust_parity_audit.ps1 from the repo.'
        rows[#rows + 1] = 'Default QA alliance: Twills/August/Yoran-Oran UC/Koru-Moru/Qultada/Cornelia; Valaineral/Monberaux/Joachim/Ulmia/Lilisette II/Matsui-P; Amchuchu/Sylvie UC/Apururu UC/Shantotto II/Star Sibyl/Selh\'teus.'
        rows[#rows + 1] = 'Next implementation priority: recommended QA alliance profiles first, then role batches, then remaining roster.'
        return rows
    end

    local profile = nameProfileForName(scope)
    if profile ~= nil then
        rows[#rows + 1] = auditProfileRow(scope, profile)
    else
        rows[#rows + 1] = string.format('%s profile=missing status=audit_needed', scope)
    end

    return rows
end


local function closeAndClearLifecycleSession(player, reason)
    if player == nil or player:getName() ~= qaAdminName then
        return
    end

    local mode = player:getLocalVar(evidenceModeVar)
    local state = getSessionState(player)
    if
        state ~= nil and
        state ~= sessionState.IDLE
    then
        failSession(player, player:getLocalVar(sessionGenerationVar), reason)
    else
        if state == sessionState.IDLE then
            clearTrustsWithInactiveProjection(player)
        end

        resetSessionLocals(player)
    end
end

local function beginLifecycleClose(player, reason)
    if player == nil or player:getName() ~= qaAdminName then
        return false, 'not_twills'
    end

    local mode = player:getLocalVar(evidenceModeVar)
    local state = getSessionState(player)
    if mode == evidenceMode.IDLE or state == nil or state == sessionState.IDLE then
        return false, 'session_not_active'
    end

    if state ~= sessionState.FAILED and not setSessionState(player, sessionState.FAILED) then
        return false, 'lifecycle_failed_transition_rejected'
    end

    player:setLocalVar(pendingTimersVar, 0)
    player:setCharVar('TrustEngageType', 0)

    local closeReason = tostring(reason or 'zone_or_logout')
    local stateFields = authorizationFields(player)
    stateFields[#stateFields + 1] = 'reason=' .. closeReason
    local stateLogged = loggerEvent(player, 'session_state', 'failed', stateFields)

    local failureFields = rosterFields(player, mode)
    failureFields[#failureFields + 1] = 'reason=' .. closeReason
    local failureLogged = loggerEvent(player, 'roster', 'failure', failureFields)
    return stateLogged and failureLogged, closeReason
end

local function finishLifecycleClose(player, reason)
    if player == nil or player:getName() ~= qaAdminName then
        return false, 'not_twills'
    end

    local mode = player:getLocalVar(evidenceModeVar)
    local state = getSessionState(player)
    if mode == evidenceMode.IDLE or state ~= sessionState.FAILED then
        return false, 'lifecycle_close_not_pending'
    end

    player:setLocalVar(pendingTimersVar, 0)
    player:setCharVar('TrustEngageType', 0)

    local closeReason = tostring(reason or 'zone_or_logout')
    local clearedFields, clearedAudit = rosterFields(player, mode)
    clearedFields[#clearedFields + 1] = 'reason=' .. closeReason
    local rosterCleared = clearedAudit.activeCount == 0 and player:getLocalVar(pendingTimersVar) == 0
    local rosterLogged
    if rosterCleared then
        rosterLogged = loggerEvent(player, 'roster', 'cleared', clearedFields)
    else
        clearedFields[#clearedFields + 1] = 'cleanup_mismatch=true'
        rosterLogged = loggerEvent(player, 'roster', 'failure', clearedFields)
        closeReason = 'native_clear_mismatch'
    end

    local idleTransitioned = setSessionState(player, sessionState.IDLE)
    local idleLogged = false
    local ended = false
    if idleTransitioned then
        idleLogged = loggerEvent(player, 'session_state', 'idle', {
            'reason=' .. closeReason,
        })
        ended = finishEvidenceSession(player, mode, 'failed', closeReason)
    end

    advanceSessionGeneration(player)
    resetSessionLocals(player)
    local liveReset = resetLoggerLive(player)
    return
        rosterCleared and
        rosterLogged and
        idleTransitioned and
        idleLogged and
        ended and
        liveReset,
        closeReason
end

local function bestEffortLifecyclePreFallback(player)
    if player == nil then
        return
    end

    safeCall(player, 'setLocalVar', pendingTimersVar, 0)
    safeCall(player, 'setCharVar', 'TrustEngageType', 0)
    local state = getSessionState(player)
    if state == sessionState.SPAWNING or state == sessionState.READY then
        setSessionState(player, sessionState.FAILED)
    end
end

local function bestEffortLifecyclePostFallback(player)
    if player == nil then
        return
    end

    if
        xi.trustActionLogger ~= nil and
        type(xi.trustActionLogger.markLogTruncated) == 'function'
    then
        pcall(xi.trustActionLogger.markLogTruncated, player, 'lifecycle_post_exception')
    else
        safeCall(player, 'setLocalVar', logTruncatedVar, 1)
    end

    safeCall(player, 'setLocalVar', pendingTimersVar, 0)
    safeCall(player, 'setCharVar', 'TrustEngageType', 0)
    if getSessionState(player) ~= sessionState.IDLE and not setSessionState(player, sessionState.IDLE) then
        safeCall(player, 'setLocalVar', 'MochiriiTrustSessionState', sessionState.IDLE)
    end

    local generation = tonumber(player:getLocalVar(sessionGenerationVar) or 0) or 0
    safeCall(
        player,
        'setLocalVar',
        sessionGenerationVar,
        generation >= 2147483646 and 1 or generation + 1)
    pcall(resetSessionLocals, player)
    pcall(resetLoggerLive, player)
end

-- Called before upstream's first effective ClearTrusts and after its existing
-- later idempotent teardown. These wrappers never throw into the C++
-- zone/logout path; C++ still performs its own final state reset if evidence
-- I/O or Lua cleanup reports failure.
trustRetailParity.beginLifecycleClose = function(player, reason)
    local called, success, detail = pcall(beginLifecycleClose, player, reason)
    if not called then
        pcall(bestEffortLifecyclePreFallback, player)
        return false, 'lifecycle_pre_exception'
    end

    return success == true, detail
end


trustRetailParity.finishLifecycleClose = function(player, reason)
    local called, success, detail = pcall(finishLifecycleClose, player, reason)
    if not called then
        pcall(bestEffortLifecyclePostFallback, player)
        return false, 'lifecycle_post_exception'
    end

    return success == true, detail
end

m:addOverride('xi.player.onGameIn', function(player, firstLogin, zoning)
    super(player, firstLogin, zoning)
    if
        player ~= nil and
        player:getName() == qaAdminName and
        getSessionState(player) == sessionState.IDLE
    then
        resetSessionLocals(player)
    end

    resetLoggerLive(player)
end)

m:addOverride('xi.player.onPlayerDeath', function(player)
    super(player)
    closeAndClearLifecycleSession(player, 'player_death')
end)

return m
