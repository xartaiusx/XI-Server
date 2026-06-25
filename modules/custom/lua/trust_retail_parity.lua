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
local qaAutoVar = 'MochiriiTrustQAAuto'
local qaRunningVar = 'MochiriiTrustQARunning'

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

local function printClientSummary(player, line)
    local text = tostring(line or '')
    if #text > 180 then
        text = text:sub(1, 177) .. '...'
    end

    printLine(player, text)
end

local function hasTrust(player, trustId)
    local party = player:getPartyWithTrusts()

    for _, member in pairs(party) do
        if isTrust(member) and member:getTrustID() == trustId then
            return true
        end
    end

    return false
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

    for _, member in pairs(party) do
        if isTrust(member) then
            if xi.trustActionLogger ~= nil then
                xi.trustActionLogger.attach(member, 'trustparty-scan')
            end

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
        elseif role:find('support') ~= nil or role:find('bard') ~= nil or role:find('cor') ~= nil or role:find('geo') ~= nil or role:find('aura') ~= nil or role:find('rdm') ~= nil then
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

local function qaTrustIds()
    local trustIds = {}

    for _, party in ipairs(trustRetailParity.qaAllianceComposition) do
        for _, entry in ipairs(party.trusts) do
            trustIds[#trustIds + 1] = entry.spell
        end
    end

    return trustIds
end

trustRetailParity.auditRows = function(player, target)
    local rows = {}
    local scope = target or 'active'

    if scope == 'active' then
        rows[#rows + 1] = 'Active Trust retail-player parity audit:'
        for _, member in pairs(player:getPartyWithTrusts()) do
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

trustRetailParity.autoSummonQaParty = function(player)
    local trustIds = qaTrustIds()
    local spawned = 0

    local function spawnNext(playerArg, index)
        if playerArg == nil then
            return
        end

        if index > #trustIds then
            print(string.format('Mochirii Trust QA: spawn sequence complete for %s; spawned=%u', playerArg:getName(), spawned))
            printLine(playerArg, string.format('Mochirii Trust QA: spawned %u Trust(s); applying parity shortly.', spawned))

            playerArg:timer(2500, function(reportPlayer)
                if reportPlayer ~= nil then
                    print(string.format('Mochirii Trust QA: reporting active party for %s', reportPlayer:getName()))
                    printLine(reportPlayer, 'Mochirii Trust QA parity status follows in map log; client rows are shortened.')
                    local rows = trustRetailParity.partyRows(reportPlayer, true)
                    local clientRows = 0
                    for _, row in ipairs(rows) do
                        print('Mochirii Trust QA: ' .. row)
                        if clientRows < 6 then
                            printClientSummary(reportPlayer, row)
                            clientRows = clientRows + 1
                        end
                    end

                    if #rows > clientRows then
                        printLine(reportPlayer, string.format('Mochirii Trust QA: %u more row(s) written to map log/report.', #rows - clientRows))
                    end

                    reportPlayer:setCharVar(qaAutoVar, 0)
                    reportPlayer:setCharVar(qaRunningVar, 0)
                end
            end)

            return
        end

        local trustId = trustIds[index]
        if not hasTrust(playerArg, trustId) then
            print(string.format('Mochirii Trust QA: spawning trustId=%u for %s', trustId, playerArg:getName()))
            playerArg:spawnTrust(trustId)
            if xi.trustActionLogger ~= nil then
                xi.trustActionLogger.queueAttachParty(playerArg, 'trust-qa-spawn')
            end

            spawned = spawned + 1
        else
            print(string.format('Mochirii Trust QA: trustId=%u already active for %s', trustId, playerArg:getName()))
        end

        playerArg:timer(1500, function(nextPlayer)
            spawnNext(nextPlayer, index + 1)
        end)
    end

    if
        xi.trustActionLogger ~= nil and
        xi.trustActionLogger.resetForLogin ~= nil
    then
        xi.trustActionLogger.resetForLogin(player)
    end

    print(string.format('Mochirii Trust QA: rebuilding recommended alliance for %s', player:getName()))
    printLine(player, 'Mochirii Trust QA: reset Trust logs, clearing active Trusts, then summoning the recommended 3-party test alliance.')
    for _, row in ipairs(trustRetailParity.compositionRows()) do
        print('Mochirii Trust QA composition: ' .. row)
    end

    player:clearTrusts()
    player:timer(2500, function(playerArg)
        spawnNext(playerArg, 1)
    end)

    return spawned
end

m:addOverride('xi.player.onGameIn', function(player, firstLogin, zoning)
    super(player, firstLogin, zoning)

    if
        player:getName() ~= qaAdminName or
        player:getCharVar(qaAutoVar) ~= 1
    then
        return
    end

    print(string.format('Mochirii Trust QA: queued for %s on game-in', player:getName()))
    player:timer(10000, function(playerArg)
        if
            playerArg ~= nil and
            playerArg:getCharVar(qaAutoVar) == 1 and
            playerArg:getCharVar(qaRunningVar) ~= 1
        then
            if not playerArg:canUseMisc(xi.zoneMisc.TRUST) then
                print(string.format('Mochirii Trust QA: zone disallows Trusts for %s', playerArg:getName()))
                printLine(playerArg, 'Mochirii Trust QA: current zone does not allow Trust summoning.')
                playerArg:setCharVar(qaAutoVar, 0)
                playerArg:setCharVar(qaRunningVar, 0)
                return
            end

            print(string.format('Mochirii Trust QA: starting summon sequence for %s', playerArg:getName()))
            playerArg:setCharVar(qaRunningVar, 1)
            trustRetailParity.autoSummonQaParty(playerArg)
        elseif playerArg ~= nil then
            print(string.format(
                'Mochirii Trust QA: skipped timer for %s auto=%u running=%u',
                playerArg:getName(),
                playerArg:getCharVar(qaAutoVar),
                playerArg:getCharVar(qaRunningVar)
            ))
        end
    end)
end)

return m
