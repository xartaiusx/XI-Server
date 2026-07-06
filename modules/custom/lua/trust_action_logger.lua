-----------------------------------
-- Mochirii Trust action logger.
--
-- Captures Trust combat choices for QA without changing Trust behavior.
-- Live logs are reset on player login; archive logs persist per session.
-----------------------------------
require('modules/module_utils')
-----------------------------------

xi = xi or {}
xi.trustActionLogger = xi.trustActionLogger or {}

local trustActionLogger = xi.trustActionLogger
local m = Module:new('trust_action_logger')

local attachedVar = 'MochiTrustLogAttached'
local lastTargetVar = 'MochiTrustLogLastTarget'
local lastRestBlockVar = 'MochiTrustLogLastRestBlock'
local lastRestModeVar = 'MochiTrustLogLastRestMode'
local lastRestMppVar = 'MochiTrustLogLastRestMpp'
local lastDiagnosticVar = 'MochiTrustLogLastDiagnostic'
local lastMagicSpellVar = 'MochiTrustLogMagicSpell'
local lastMagicTargetVar = 'MochiTrustLogMagicTarget'
local lastMagicTargetHpVar = 'MochiTrustLogMagicTargetHp'
local lastMagicTargetMaxHpVar = 'MochiTrustLogMagicTargetMaxHp'
local lastMagicTargetHppVar = 'MochiTrustLogMagicTargetHpp'
local lastMagicTrustMppVar = 'MochiTrustLogMagicTrustMpp'
local defaultLogDir = '/root/projects/FFXI-Runtime/logs/trust_actions'

local activeArchives = {}
local ensuredDirs = {}
local fileErrorShown = {}
local restStates = {}

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

local function clean(value)
    if value == nil then
        return 'nil'
    end

    return tostring(value):gsub('[\r\n\t]', ' ')
end

local function safeName(value)
    return clean(value):gsub('[^%w_%-%.]', '_')
end

local function pathJoin(...)
    local parts = { ... }
    local path = tostring(parts[1] or '')

    for i = 2, #parts do
        local part = tostring(parts[i] or '')
        if path:sub(-1) == '/' or path:sub(-1) == '\\' then
            path = path .. part
        else
            path = path .. '/' .. part
        end
    end

    return path
end

local function ensureDirectory(path)
    if ensuredDirs[path] then
        return
    end

    local sanitized = tostring(path):gsub('"', '')

    if os ~= nil and os.execute ~= nil then
        local command = string.format('mkdir -p "%s"', sanitized)
        if
            package ~= nil and
            package.config ~= nil and
            package.config:sub(1, 1) == '\\'
        then
            command = string.format('mkdir "%s" 2>nul', sanitized)
        end

        pcall(os.execute, command)
    end

    ensuredDirs[path] = true
end

local function rootDir()
    return setting('TRUST_ACTION_LOG_DIR', defaultLogDir)
end

local function ensureLogDirs()
    local root = rootDir()
    ensureDirectory(root)
    ensureDirectory(pathJoin(root, 'live'))
    ensureDirectory(pathJoin(root, 'archive'))
end

local function livePath(ownerName)
    return pathJoin(rootDir(), 'live', safeName(ownerName) .. '.log')
end

local function archivePath(ownerName, stamp)
    return pathJoin(rootDir(), 'archive', safeName(ownerName) .. '-' .. stamp .. '.log')
end

local function restStatePath(ownerName)
    return pathJoin(rootDir(), 'live', safeName(ownerName) .. '-resting.tsv')
end

local function writeFile(path, mode, line)
    local file = io.open(path, mode)
    if file == nil then
        if not fileErrorShown[path] then
            print(string.format('Mochirii TrustLog: failed to open %s', path))
            fileErrorShown[path] = true
        end

        return
    end

    if line ~= nil and line ~= '' then
        file:write(line)
        file:write('\n')
    end

    file:close()
end

local call
local restBlockName
local restModeName
local restStartName
local restStopName

local function writeRestStateFile(ownerName)
    ensureLogDirs()

    local ownerStates = restStates[ownerName] or {}
    local names = {}
    for trustName, _ in pairs(ownerStates) do
        names[#names + 1] = trustName
    end

    table.sort(names)

    local file = io.open(restStatePath(ownerName), 'w')
    if file == nil then
        return
    end

    for _, trustName in ipairs(names) do
        local state = ownerStates[trustName]
        file:write(table.concat({
            trustName,
            clean(state.resting or 0),
            clean(state.mode or 'none'),
            clean(state.reason or 'none'),
            clean(state.mpp or 0),
            clean(state.updated or os.date('%Y-%m-%dT%H:%M:%S')),
        }, '\t'))
        file:write('\n')
    end

    file:close()
end

local function updateRestState(actor, ownerName)
    if actor == nil or ownerName == nil then
        return
    end

    local trustName = call(actor, 'getName') or 'unknown'
    local restMode = call(actor, 'getLocalVar', 'MochiTrustRestMode') or 0
    local stopReason = call(actor, 'getLocalVar', 'MochiTrustRestStopReason') or 0
    local blockReason = call(actor, 'getLocalVar', 'MochiTrustRestBlockReason') or 0
    local modeName = restModeName(restMode)
    local reasonName = restMode ~= 0 and restStartName(call(actor, 'getLocalVar', 'MochiTrustRestStartReason') or 0) or restStopName(stopReason)

    if
        restMode == 0 and
        (tonumber(blockReason) or 0) ~= 0 and
        reasonName == 'none'
    then
        reasonName = restBlockName(blockReason)
    end

    restStates[ownerName] = restStates[ownerName] or {}
    restStates[ownerName][trustName] =
    {
        resting = restMode ~= 0 and 1 or 0,
        mode = modeName,
        reason = reasonName,
        mpp = call(actor, 'getMPP') or 0,
        updated = os.date('%Y-%m-%dT%H:%M:%S'),
    }

    writeRestStateFile(ownerName)
end

local function shouldLogOwner(ownerName)
    if not settingEnabled('ENABLE_TRUST_ACTION_LOG', true) then
        return false
    end

    local configured = setting('TRUST_ACTION_LOG_PLAYER', 'Twills')
    return configured == nil or configured == '' or ownerName == configured
end

call = function(entity, methodName, ...)
    if entity == nil or entity[methodName] == nil then
        return nil
    end

    local ok, value = pcall(entity[methodName], entity, ...)
    if ok then
        return value
    end

    return nil
end

local function ownerForTrust(trust)
    local owner = call(trust, 'getMaster')
    local ownerName = call(owner, 'getName')

    return owner, ownerName
end

local function entityFields(prefix, entity, fields)
    fields[#fields + 1] = prefix .. '_name=' .. clean(call(entity, 'getName') or 'none')
    fields[#fields + 1] = prefix .. '_id=' .. clean(call(entity, 'getID') or 0)
    fields[#fields + 1] = prefix .. '_targid=' .. clean(call(entity, 'getTargID') or 0)
    fields[#fields + 1] = prefix .. '_objtype=' .. clean(call(entity, 'getObjType') or 0)
    fields[#fields + 1] = prefix .. '_hp=' .. clean(call(entity, 'getHP') or 0)
    fields[#fields + 1] = prefix .. '_maxhp=' .. clean(call(entity, 'getMaxHP') or 0)
    fields[#fields + 1] = prefix .. '_hpp=' .. clean(call(entity, 'getHPP') or 0)
    fields[#fields + 1] = prefix .. '_mp=' .. clean(call(entity, 'getMP') or 0)
    fields[#fields + 1] = prefix .. '_maxmp=' .. clean(call(entity, 'getMaxMP') or 0)
    fields[#fields + 1] = prefix .. '_mpp=' .. clean(call(entity, 'getMPP') or 0)
end

local trackedStatuses =
{
    { name = 'protect', effect = xi.effect.PROTECT },
    { name = 'shell', effect = xi.effect.SHELL },
    { name = 'haste', effect = xi.effect.HASTE },
    { name = 'refresh', effect = xi.effect.REFRESH },
    { name = 'regen', effect = xi.effect.REGEN },
    { name = 'phalanx', effect = xi.effect.PHALANX },
    { name = 'reprisal', effect = xi.effect.REPRISAL },
    { name = 'enlight', effect = xi.effect.ENLIGHT },
    { name = 'afflatus_solace', effect = xi.effect.AFFLATUS_SOLACE },
    { name = 'light_arts', effect = xi.effect.LIGHT_ARTS },
    { name = 'dark_arts', effect = xi.effect.DARK_ARTS },
    { name = 'addendum_white', effect = xi.effect.ADDENDUM_WHITE },
    { name = 'addendum_black', effect = xi.effect.ADDENDUM_BLACK },
    { name = 'sublimation_activated', effect = xi.effect.SUBLIMATION_ACTIVATED },
    { name = 'sublimation_complete', effect = xi.effect.SUBLIMATION_COMPLETE },
    { name = 'accession', effect = xi.effect.ACCESSION },
    { name = 'penury', effect = xi.effect.PENURY },
    { name = 'divine_seal', effect = xi.effect.DIVINE_SEAL },
    { name = 'divine_caress', effect = xi.effect.DIVINE_CARESS },
    { name = 'aquaveil', effect = xi.effect.AQUAVEIL },
    { name = 'stoneskin', effect = xi.effect.STONESKIN },
    { name = 'blink', effect = xi.effect.BLINK },
    { name = 'reraise', effect = xi.effect.RERAISE },
    { name = 'auspice', effect = xi.effect.AUSPICE },
    { name = 'mnd_boost', effect = xi.effect.MND_BOOST },
    { name = 'sentinel', effect = xi.effect.SENTINEL },
    { name = 'palisade', effect = xi.effect.PALISADE },
    { name = 'defender', effect = xi.effect.DEFENDER },
    { name = 'majesty', effect = xi.effect.MAJESTY },
    { name = 'foil', effect = xi.effect.FOIL },
    { name = 'berserk', effect = xi.effect.BERSERK },
    { name = 'swordplay', effect = xi.effect.SWORDPLAY },
    { name = 'embolden', effect = xi.effect.EMBOLDEN },
    { name = 'triple_shot', effect = xi.effect.TRIPLE_SHOT },
    { name = 'double_up_chance', effect = xi.effect.DOUBLE_UP_CHANCE },
    { name = 'chaos_roll', effect = xi.effect.CHAOS_ROLL },
    { name = 'fighters_roll', effect = xi.effect.FIGHTERS_ROLL },
    { name = 'evokers_roll', effect = xi.effect.EVOKERS_ROLL },
    { name = 'hunters_roll', effect = xi.effect.HUNTERS_ROLL },
    { name = 'corsairs_roll', effect = xi.effect.CORSAIRS_ROLL },
    { name = 'ballad', effect = xi.effect.BALLAD },
    { name = 'paeon', effect = xi.effect.PAEON },
    { name = 'march', effect = xi.effect.MARCH },
    { name = 'madrigal', effect = xi.effect.MADRIGAL },
    { name = 'minuet', effect = xi.effect.MINUET },
    { name = 'prelude', effect = xi.effect.PRELUDE },
    { name = 'scherzo', effect = xi.effect.SCHERZO },
    { name = 'colure_active', effect = xi.effect.COLURE_ACTIVE },
    { name = 'entrust', effect = xi.effect.ENTRUST },
    { name = 'haste_samba', effect = xi.effect.HASTE_SAMBA },
    { name = 'sluggish_daze_5', effect = xi.effect.SLUGGISH_DAZE_5 },
    { name = 'lethargic_daze_5', effect = xi.effect.LETHARGIC_DAZE_5 },
    { name = 'dia', effect = xi.effect.DIA },
    { name = 'slow', effect = xi.effect.SLOW },
    { name = 'paralysis', effect = xi.effect.PARALYSIS },
    { name = 'addle', effect = xi.effect.ADDLE },
    { name = 'evasion_down', effect = xi.effect.EVASION_DOWN },
    { name = 'magic_evasion_down', effect = xi.effect.MAGIC_EVASION_DOWN },
    { name = 'weight', effect = xi.effect.WEIGHT },
    { name = 'bind', effect = xi.effect.BIND },
    { name = 'blindness', effect = xi.effect.BLINDNESS },
    { name = 'poison', effect = xi.effect.POISON },
    { name = 'flash', effect = xi.effect.FLASH },
    { name = 'elegy', effect = xi.effect.ELEGY },
    { name = 'sleep_i', effect = xi.effect.SLEEP_I },
    { name = 'sleep_ii', effect = xi.effect.SLEEP_II },
    { name = 'skillchain', effect = xi.effect.SKILLCHAIN },
}

local function effectSnapshotEntry(entity, entry)
    local effect = call(entity, 'getStatusEffect', entry.effect)
    if effect == nil then
        return nil
    end

    local remainingMs = tonumber(call(effect, 'getTimeRemaining') or 0) or 0
    local durationMs = tonumber(call(effect, 'getDuration') or 0) or 0
    local parts =
    {
        entry.name,
        'rem=' .. tostring(math.floor(remainingMs / 1000)),
    }

    if durationMs > 0 then
        parts[#parts + 1] = 'dur=' .. tostring(math.floor(durationMs / 1000))
    end

    local power = tonumber(call(effect, 'getPower') or 0) or 0
    if power ~= 0 then
        parts[#parts + 1] = 'pow=' .. tostring(power)
    end

    local tier = tonumber(call(effect, 'getTier') or 0) or 0
    if tier ~= 0 then
        parts[#parts + 1] = 'tier=' .. tostring(tier)
    end

    local subPower = tonumber(call(effect, 'getSubPower') or 0) or 0
    if subPower ~= 0 then
        parts[#parts + 1] = 'sub=' .. tostring(subPower)
    end

    return table.concat(parts, ':')
end

local function statusSnapshot(entity)
    if entity == nil then
        return 'none'
    end

    local active = {}
    for _, entry in ipairs(trackedStatuses) do
        if entry.effect ~= nil then
            local snapshot = effectSnapshotEntry(entity, entry)
            if snapshot ~= nil then
                active[#active + 1] = snapshot
            end
        end
    end

    if #active == 0 then
        return 'none'
    end

    return table.concat(active, ';')
end

local restBlockReasons =
{
    [0] = 'none',
    [1] = 'not_needed',
    [2] = 'combat_mp_above_start',
    [3] = 'combat_rest_disabled',
    [4] = 'personal_threat',
    [5] = 'immediate_mp_recovery',
    [6] = 'party_needs_caster',
    [7] = 'recent_damage',
    [8] = 'following_path',
    [9] = 'too_far_from_master',
    [10] = 'cannot_rest',
    [11] = 'cannot_change_state',
    [12] = 'out_of_combat_cooldown',
}

local restModes =
{
    [0] = 'none',
    [1] = 'out_of_combat',
    [2] = 'combat',
}

local restStartReasons =
{
    [0] = 'none',
    [1] = 'low_mp',
    [2] = 'low_hp',
    [3] = 'low_mp_hp',
    [4] = 'combat_mp',
}

local restStopReasons =
{
    [0] = 'none',
    [1] = 'engaged',
    [2] = 'follow_break',
    [3] = 'recovery_floor',
    [4] = 'fully_healed',
    [5] = 'combat_unsafe',
}

local spellNames = {}

local function mapSpell(id, name)
    if id ~= nil then
        spellNames[id] = name
    end
end

mapSpell(xi.magic.spell.CURE, 'cure')
mapSpell(xi.magic.spell.CURE_II, 'cure_ii')
mapSpell(xi.magic.spell.CURE_III, 'cure_iii')
mapSpell(xi.magic.spell.CURE_IV, 'cure_iv')
mapSpell(xi.magic.spell.CURE_V, 'cure_v')
mapSpell(xi.magic.spell.CURE_VI, 'cure_vi')
mapSpell(xi.magic.spell.CURAGA, 'curaga')
mapSpell(xi.magic.spell.CURAGA_II, 'curaga_ii')
mapSpell(xi.magic.spell.CURAGA_III, 'curaga_iii')
mapSpell(xi.magic.spell.CURAGA_IV, 'curaga_iv')
mapSpell(xi.magic.spell.CURAGA_V, 'curaga_v')
mapSpell(xi.magic.spell.CURA, 'cura')
mapSpell(xi.magic.spell.CURA_II, 'cura_ii')
mapSpell(xi.magic.spell.CURA_III, 'cura_iii')
mapSpell(xi.magic.spell.RAISE, 'raise')
mapSpell(xi.magic.spell.RAISE_II, 'raise_ii')
mapSpell(xi.magic.spell.RAISE_III, 'raise_iii')
mapSpell(xi.magic.spell.RERAISE, 'reraise')
mapSpell(xi.magic.spell.RERAISE_II, 'reraise_ii')
mapSpell(xi.magic.spell.RERAISE_III, 'reraise_iii')
mapSpell(xi.magic.spell.RERAISE_IV, 'reraise_iv')
mapSpell(xi.magic.spell.POISONA, 'poisona')
mapSpell(xi.magic.spell.PARALYNA, 'paralyna')
mapSpell(xi.magic.spell.BLINDNA, 'blindna')
mapSpell(xi.magic.spell.SILENA, 'silena')
mapSpell(xi.magic.spell.STONA, 'stona')
mapSpell(xi.magic.spell.VIRUNA, 'viruna')
mapSpell(xi.magic.spell.CURSNA, 'cursna')
mapSpell(xi.magic.spell.ERASE, 'erase')
mapSpell(xi.magic.spell.PROTECT, 'protect')
mapSpell(xi.magic.spell.PROTECT_II, 'protect_ii')
mapSpell(xi.magic.spell.PROTECT_III, 'protect_iii')
mapSpell(xi.magic.spell.PROTECT_IV, 'protect_iv')
mapSpell(xi.magic.spell.PROTECT_V, 'protect_v')
mapSpell(125, 'protectra')
mapSpell(xi.magic.spell.PROTECTRA_II, 'protectra_ii')
mapSpell(xi.magic.spell.PROTECTRA_III, 'protectra_iii')
mapSpell(xi.magic.spell.PROTECTRA_IV, 'protectra_iv')
mapSpell(xi.magic.spell.PROTECTRA_V, 'protectra_v')
mapSpell(xi.magic.spell.SHELL, 'shell')
mapSpell(xi.magic.spell.SHELL_II, 'shell_ii')
mapSpell(xi.magic.spell.SHELL_III, 'shell_iii')
mapSpell(xi.magic.spell.SHELL_IV, 'shell_iv')
mapSpell(xi.magic.spell.SHELL_V, 'shell_v')
mapSpell(xi.magic.spell.SHELLRA_IV, 'shellra_iv')
mapSpell(xi.magic.spell.SHELLRA_V, 'shellra_v')
mapSpell(xi.magic.spell.HASTE, 'haste')
mapSpell(xi.magic.spell.SLOW, 'slow')
mapSpell(xi.magic.spell.SLOW_II, 'slow_ii')
mapSpell(xi.magic.spell.PARALYZE, 'paralyze')
mapSpell(xi.magic.spell.PARALYZE_II, 'paralyze_ii')
mapSpell(xi.magic.spell.DIA, 'dia')
mapSpell(xi.magic.spell.DIA_II, 'dia_ii')
mapSpell(25, 'dia_iii')
mapSpell(xi.magic.spell.FLASH, 'flash')
mapSpell(xi.magic.spell.ADDLE, 'addle')
mapSpell(xi.magic.spell.REPOSE, 'repose')
mapSpell(xi.magic.spell.AQUAVEIL, 'aquaveil')
mapSpell(xi.magic.spell.STONESKIN, 'stoneskin')
mapSpell(xi.magic.spell.BLINK, 'blink')
mapSpell(xi.magic.spell.AUSPICE, 'auspice')
mapSpell(xi.magic.spell.BOOST_MND, 'boost-mnd')
mapSpell(xi.magic.spell.REGEN, 'regen')
mapSpell(xi.magic.spell.REGEN_II, 'regen_ii')
mapSpell(xi.magic.spell.REGEN_III, 'regen_iii')
mapSpell(xi.magic.spell.REGEN_IV, 'regen_iv')
mapSpell(xi.magic.spell.REGEN_V, 'regen_v')
mapSpell(xi.magic.spell.FIRESTORM, 'firestorm')
mapSpell(xi.magic.spell.HAILSTORM, 'hailstorm')
mapSpell(xi.magic.spell.WINDSTORM, 'windstorm')
mapSpell(xi.magic.spell.SANDSTORM, 'sandstorm')
mapSpell(xi.magic.spell.THUNDERSTORM, 'thunderstorm')
mapSpell(xi.magic.spell.RAINSTORM, 'rainstorm')
mapSpell(xi.magic.spell.AURORASTORM, 'aurorastorm')
mapSpell(xi.magic.spell.VOIDSTORM, 'voidstorm')

-- Active alliance spell IDs that may not be exposed as xi.magic.spell
-- constants in older local Lua bindings.
mapSpell(97, 'reprisal')
mapSpell(106, 'phalanx')
mapSpell(107, 'phalanx_ii')
mapSpell(109, 'refresh')
mapSpell(132, 'shellra_iii')
mapSpell(149, 'blizzard')
mapSpell(164, 'thunder')
mapSpell(258, 'bind')
mapSpell(310, 'enlight')
mapSpell(338, 'utsusemi_ichi')
mapSpell(339, 'utsusemi_ni')
mapSpell(342, 'jubaku_ni')
mapSpell(345, 'hojo_ni')
mapSpell(348, 'kurayami_ni')
mapSpell(351, 'dokumori_ni')
mapSpell(388, 'mages_ballad_iii')
mapSpell(383, 'armys_paeon_vi')
mapSpell(398, 'valor_minuet_v')
mapSpell(400, 'blade_madrigal')
mapSpell(402, 'archers_prelude')
mapSpell(420, 'victory_march')
mapSpell(422, 'carnage_elegy')
mapSpell(462, 'magic_finale')
mapSpell(473, 'refresh_ii')
mapSpell(511, 'haste_ii')
mapSpell(770, 'indi-refresh')
mapSpell(781, 'indi-acumen')
mapSpell(840, 'foil')
mapSpell(846, 'flurry_ii')

local weaponSkillNames =
{
    [23] = 'dancing_edge',
    [163] = 'starlight',
    [164] = 'moonlight',
    [25] = 'evisceration',
    [29] = 'pyrrhic_kleos',
    [30] = 'aeolian_edge',
    [31] = 'rudras_storm',
    [33] = 'burning_blade',
    [38] = 'circle_blade',
    [42] = 'savage_blade',
    [47] = 'sanguine_blade',
    [54] = 'sickle_moon',
    [61] = 'dimidiation',
    [128] = 'blade_rin',
    [129] = 'blade_retsu',
    [133] = 'blade_ei',
    [134] = 'blade_jin',
    [136] = 'blade_ku',
    [138] = 'blade_kamu',
    [141] = 'blade_shun',
    [210] = 'sniper_shot',
    [215] = 'detonator',
    [224] = 'exenterator',
    [238] = 'uriel_blade',
    [1508] = 'luminous_lance',
    [1509] = 'rejuvenation',
    [1510] = 'revelation',
    [2015] = 'light_shot',
    [2016] = 'dark_shot',
    [3502] = 'nott',
    [3648] = 'august_melee_sword',
    [3649] = 'august_melee_axe',
    [3650] = 'august_melee_h2h',
    [3651] = 'august_melee_bow',
    [3652] = 'daybreak',
    [3653] = 'tartaric_sigil',
    [3654] = 'null_field',
    [3655] = 'alabaster_burst',
    [3739] = 'auto_attack_shantotto_ii',
    [3740] = 'final_exam',
    [3741] = 'doctors_orders',
    [3743] = 'lesson_in_pain',
    [4235] = 'hyper-potion',
    [4236] = 'max_potion',
    [4237] = 'mix_max_potion',
    [4247] = 'mix_para-b-gone',
    [4253] = 'mix_panacea-1',
    [4254] = 'mix_dry_ether_concoction',
    [4255] = 'mix_guard_drink',
    [4257] = 'mix_life_water',
    [4261] = 'mix_samsons_strength',
}

local gambitTargets =
{
    [0] = 'self',
    [1] = 'party',
    [2] = 'target',
    [3] = 'master',
    [4] = 'tank',
    [5] = 'melee',
    [6] = 'ranged',
    [7] = 'caster',
    [8] = 'top_enmity',
    [9] = 'curilla',
    [10] = 'party_dead',
    [11] = 'party_multi',
    [12] = 'trigger_self_action_target',
    [13] = 'trigger_target_action_self',
}

local gambitReactions =
{
    [0] = 'attack',
    [1] = 'rattack',
    [2] = 'ma',
    [3] = 'ja',
    [4] = 'ws',
    [5] = 'ms',
    [6] = 'anim_string',
}

local gambitSelects =
{
    [0] = 'highest',
    [1] = 'lowest',
    [2] = 'specific',
    [3] = 'random',
    [4] = 'mb_element',
    [5] = 'special_ayame',
    [6] = 'special_august',
    [7] = 'best_against_target',
    [8] = 'best_samba',
    [9] = 'highest_waltz',
    [10] = 'entrusted',
    [11] = 'best_indi',
    [12] = 'storm_day',
    [13] = 'helix_day',
    [14] = 'en_mob_weakness',
    [15] = 'storm_mob_weakness',
    [16] = 'helix_mob_weakness',
    [17] = 'def_bar_element',
    [18] = 'rune_day',
    [19] = 'random_animation',
}

local focusReasons =
{
    [0] = 'none',
    [1] = 'master_target',
    [2] = 'defensive',
    [3] = 'current_target',
}

local roleEnmityActions =
{
    [0] = 'none',
    [1] = 'tank_assist',
    [2] = 'shed',
}

restBlockName = function(reason)
    return restBlockReasons[tonumber(reason) or 0] or 'unknown'
end

restModeName = function(mode)
    return restModes[tonumber(mode) or 0] or 'unknown'
end

restStartName = function(reason)
    return restStartReasons[tonumber(reason) or 0] or 'unknown'
end

restStopName = function(reason)
    return restStopReasons[tonumber(reason) or 0] or 'unknown'
end

local function spellName(spell)
    local spellId = call(spell, 'getID') or 0
    return spellNames[spellId] or ('spell_' .. tostring(spellId))
end

local function weaponSkillName(skillId)
    return weaponSkillNames[tonumber(skillId) or 0] or ('skill_' .. tostring(skillId or 0))
end

local function gambitTargetName(target)
    return gambitTargets[tonumber(target) or 0] or 'unknown'
end

local function gambitReactionName(reaction)
    return gambitReactions[tonumber(reaction) or 0] or 'unknown'
end

local function gambitSelectName(select)
    return gambitSelects[tonumber(select) or 0] or 'unknown'
end

local function focusReasonName(reason)
    return focusReasons[tonumber(reason) or 0] or 'unknown'
end

local function roleEnmityActionName(action)
    return roleEnmityActions[tonumber(action) or 0] or 'unknown'
end

local tpSkillSkipReasons =
{
    [0] = 'none',
    [1] = 'invalid_target',
    [2] = 'cannot_see',
    [3] = 'out_of_range',
}

local function tpSkillSkipReasonName(reason)
    return tpSkillSkipReasons[tonumber(reason) or 0] or 'unknown'
end

local function hpMissing(entity)
    local hp = call(entity, 'getHP') or 0
    local maxHp = call(entity, 'getMaxHP') or 0
    return math.max(0, maxHp - hp)
end

local function distanceField(name, source, target)
    if source == nil or target == nil then
        return name .. '=none'
    end

    local distance = call(source, 'checkDistance', target)
    if distance == nil then
        return name .. '=none'
    end

    return name .. '=' .. string.format('%.2f', distance)
end

local function restStateFields(actor)
    local mode = call(actor, 'getLocalVar', 'MochiTrustRestMode') or 0
    local startReason = call(actor, 'getLocalVar', 'MochiTrustRestStartReason') or 0
    local stopReason = call(actor, 'getLocalVar', 'MochiTrustRestStopReason') or 0

    return {
        'rest_mode=' .. clean(mode),
        'rest_mode_name=' .. clean(restModeName(mode)),
        'rest_start_reason=' .. clean(startReason),
        'rest_start_reason_name=' .. clean(restStartName(startReason)),
        'rest_stop_reason=' .. clean(stopReason),
        'rest_stop_reason_name=' .. clean(restStopName(stopReason)),
    }
end

local function currentArchive(ownerName)
    if activeArchives[ownerName] == nil then
        local stamp = os.date('%Y%m%d-%H%M%S')
        activeArchives[ownerName] = archivePath(ownerName, stamp)
        writeFile(activeArchives[ownerName], 'a', string.format('# Mochirii Trust action archive for %s, recovered session %s', ownerName, stamp))
    end

    return activeArchives[ownerName]
end

trustActionLogger.resetForLogin = function(player)
    if player == nil then
        return
    end

    local ownerName = player:getName()
    if not shouldLogOwner(ownerName) then
        return
    end

    ensureLogDirs()

    local stamp = os.date('%Y%m%d-%H%M%S')
    activeArchives[ownerName] = archivePath(ownerName, stamp)
    writeFile(livePath(ownerName), 'w', '')
    restStates[ownerName] = {}
    writeFile(restStatePath(ownerName), 'w', '')
    writeFile(activeArchives[ownerName], 'w', string.format('# Mochirii Trust action archive for %s, session %s', ownerName, stamp))
    print(string.format('Mochirii TrustLog: reset live log for %s; archive=%s', ownerName, activeArchives[ownerName]))
end

-- Disable cyclomatic complexity check for the event logger dispatcher:
-- luacheck: ignore 561
trustActionLogger.log = function(trust, eventName, target, extraFields)
    if trust == nil or call(trust, 'getObjType') ~= xi.objType.TRUST then
        return
    end

    local owner, ownerName = ownerForTrust(trust)
    if ownerName == nil or not shouldLogOwner(ownerName) then
        return
    end

    ensureLogDirs()

    local restBlockReason = call(trust, 'getLocalVar', 'MochiTrustRestBlockReason') or 0
    local restMode = call(trust, 'getLocalVar', 'MochiTrustRestMode') or 0
    local restStartReason = call(trust, 'getLocalVar', 'MochiTrustRestStartReason') or 0
    local restStopReason = call(trust, 'getLocalVar', 'MochiTrustRestStopReason') or 0
    local gambitTarget = call(trust, 'getLocalVar', 'MochiTrustGambitTargetSelector') or 0
    local gambitReaction = call(trust, 'getLocalVar', 'MochiTrustGambitReaction') or 0
    local gambitSelect = call(trust, 'getLocalVar', 'MochiTrustGambitSelect') or 0
    local tpSkillSkipReason = call(trust, 'getLocalVar', 'MochiTrustTpSkillSkipReason') or 0
    local focusReason = call(trust, 'getLocalVar', 'MochiTrustFocusReason') or 0
    local roleEnmityAction = call(trust, 'getLocalVar', 'MochiTrustRoleEnmityAction') or 0
    local fields =
    {
        'time=' .. os.date('%Y-%m-%dT%H:%M:%S'),
        'event=' .. clean(eventName),
        'owner=' .. clean(ownerName),
        'trust=' .. clean(call(trust, 'getName') or 'unknown'),
        'trust_id=' .. clean(call(trust, 'getTrustID') or 0),
        'trust_entity_id=' .. clean(call(trust, 'getID') or 0),
        'trust_targid=' .. clean(call(trust, 'getTargID') or 0),
        'trust_hp=' .. clean(call(trust, 'getHP') or 0),
        'trust_maxhp=' .. clean(call(trust, 'getMaxHP') or 0),
        'trust_hpp=' .. clean(call(trust, 'getHPP') or 0),
        'trust_mp=' .. clean(call(trust, 'getMP') or 0),
        'trust_maxmp=' .. clean(call(trust, 'getMaxMP') or 0),
        'trust_mpp=' .. clean(call(trust, 'getMPP') or 0),
        'aep_hp_rank=' .. clean(call(trust, 'getLocalVar', 'MochiTrustAepHpRank') or 0),
        'aep_mp_rank=' .. clean(call(trust, 'getLocalVar', 'MochiTrustAepMpRank') or 0),
        'aep_stat_rank=' .. clean(call(trust, 'getLocalVar', 'MochiTrustAepStatRank') or 0),
        'aep_combat_rank=' .. clean(call(trust, 'getLocalVar', 'MochiTrustAepCombatRank') or 0),
        'aep_magic_rank=' .. clean(call(trust, 'getLocalVar', 'MochiTrustAepMagicRank') or 0),
        'unity_parity_rank=' .. clean(call(trust, 'getLocalVar', 'MochiTrustUnityRank') or 0),
        'unity_parity_stat_bonus=' .. clean(call(trust, 'getLocalVar', 'MochiTrustUnityStatBonus') or 0),
        'zone=' .. clean(call(trust, 'getZoneID') or 0),
        'trust_rest_mode=' .. clean(restMode),
        'trust_rest_mode_name=' .. clean(restModeName(restMode)),
        'trust_rest_start_reason=' .. clean(restStartReason),
        'trust_rest_start_reason_name=' .. clean(restStartName(restStartReason)),
        'trust_rest_stop_reason=' .. clean(restStopReason),
        'trust_rest_stop_reason_name=' .. clean(restStopName(restStopReason)),
        'trust_rest_block_reason=' .. clean(restBlockReason),
        'trust_rest_block=' .. clean(restBlockName(restBlockReason)),
        'focus_target_targid=' .. clean(call(trust, 'getLocalVar', 'MochiTrustFocusTargetTargId') or 0),
        'focus_reason=' .. clean(focusReason),
        'focus_reason_name=' .. clean(focusReasonName(focusReason)),
        'role_enmity_action=' .. clean(roleEnmityAction),
        'role_enmity_action_name=' .. clean(roleEnmityActionName(roleEnmityAction)),
        'role_enmity_target_targid=' .. clean(call(trust, 'getLocalVar', 'MochiTrustRoleEnmityTargetTargId') or 0),
        'gambit_target=' .. clean(gambitTarget),
        'gambit_target_name=' .. clean(gambitTargetName(gambitTarget)),
        'gambit_reaction=' .. clean(gambitReaction),
        'gambit_reaction_name=' .. clean(gambitReactionName(gambitReaction)),
        'gambit_select=' .. clean(gambitSelect),
        'gambit_select_name=' .. clean(gambitSelectName(gambitSelect)),
        'gambit_select_arg=' .. clean(call(trust, 'getLocalVar', 'MochiTrustGambitSelectArg') or 0),
        'gambit_resolved_id=' .. clean(call(trust, 'getLocalVar', 'MochiTrustGambitResolvedId') or 0),
        'gambit_target_targid=' .. clean(call(trust, 'getLocalVar', 'MochiTrustGambitTargetTargId') or 0),
        'tp_skill_skip_reason=' .. clean(tpSkillSkipReason),
        'tp_skill_skip_reason_name=' .. clean(tpSkillSkipReasonName(tpSkillSkipReason)),
        'tp_skill_skip_id=' .. clean(call(trust, 'getLocalVar', 'MochiTrustTpSkillSkipId') or 0),
        'tp_skill_skip_target_targid=' .. clean(call(trust, 'getLocalVar', 'MochiTrustTpSkillSkipTargetTargId') or 0),
    }

    entityFields('target', target, fields)
    fields[#fields + 1] = 'trust_statuses=' .. clean(statusSnapshot(trust))
    fields[#fields + 1] = 'master_statuses=' .. clean(statusSnapshot(owner))
    fields[#fields + 1] = 'target_statuses=' .. clean(statusSnapshot(target))

    if extraFields ~= nil then
        for _, field in ipairs(extraFields) do
            fields[#fields + 1] = field
        end
    end

    local line = table.concat(fields, '\t')
    writeFile(livePath(ownerName), 'a', line)
    writeFile(currentArchive(ownerName), 'a', line)
    updateRestState(trust, ownerName)

    if settingEnabled('TRUST_ACTION_LOG_MAP_ECHO', false) then
        print('Mochirii TrustLog: ' .. line)
    end
end

local function attachMagicListeners(trust)
    trust:addListener('MAGIC_START', 'MOCHIRII_TRUST_LOG_MAGIC_START', function(actor, target, spell)
        local spellId = call(spell, 'getID') or 0
        local targetHp = call(target, 'getHP') or 0
        local targetMaxHp = call(target, 'getMaxHP') or 0

        actor:setLocalVar(lastMagicSpellVar, spellId)
        actor:setLocalVar(lastMagicTargetVar, call(target, 'getTargID') or 0)
        actor:setLocalVar(lastMagicTargetHpVar, targetHp)
        actor:setLocalVar(lastMagicTargetMaxHpVar, targetMaxHp)
        actor:setLocalVar(lastMagicTargetHppVar, call(target, 'getHPP') or 0)
        actor:setLocalVar(lastMagicTrustMppVar, call(actor, 'getMPP') or 0)

        trustActionLogger.log(actor, 'magic_start', target, {
            'spell_id=' .. clean(spellId),
            'spell_name=' .. clean(spellName(spell)),
            'spell_family=' .. clean(call(spell, 'getSpellFamily') or 0),
            'spell_group=' .. clean(call(spell, 'getSpellGroup') or 0),
            'mp_cost=' .. clean(call(spell, 'getMPCost') or 0),
            'target_hp_missing_at_start=' .. clean(math.max(0, targetMaxHp - targetHp)),
            'target_hpp_at_start=' .. clean(call(target, 'getHPP') or 0),
            'trust_mpp_at_start=' .. clean(call(actor, 'getMPP') or 0),
        })
    end)

    trust:addListener('MAGIC_USE', 'MOCHIRII_TRUST_LOG_MAGIC_USE', function(actor, target, spell)
        local startHp = actor:getLocalVar(lastMagicTargetHpVar)
        local startMaxHp = actor:getLocalVar(lastMagicTargetMaxHpVar)
        local startMissing = math.max(0, startMaxHp - startHp)
        local currentHp = call(target, 'getHP') or 0
        local currentMissing = hpMissing(target)

        trustActionLogger.log(actor, 'magic_use', target, {
            'spell_id=' .. clean(call(spell, 'getID') or 0),
            'spell_name=' .. clean(spellName(spell)),
            'spell_family=' .. clean(call(spell, 'getSpellFamily') or 0),
            'spell_group=' .. clean(call(spell, 'getSpellGroup') or 0),
            'target_hp_at_start=' .. clean(startHp),
            'target_hpp_at_start=' .. clean(actor:getLocalVar(lastMagicTargetHppVar)),
            'target_hp_missing_at_start=' .. clean(startMissing),
            'target_hp_delta_since_start=' .. clean(currentHp - startHp),
            'target_hp_missing_delta_since_start=' .. clean(currentMissing - startMissing),
            'trust_mpp_at_start=' .. clean(actor:getLocalVar(lastMagicTrustMppVar)),
            'took_effect=' .. clean(call(spell, 'tookEffect')),
        })
    end)

    trust:addListener('MAGIC_INTERRUPTED', 'MOCHIRII_TRUST_LOG_MAGIC_INTERRUPTED', function(actor, target, spell)
        trustActionLogger.log(actor, 'magic_interrupted', target, {
            'spell_id=' .. clean(call(spell, 'getID') or 0),
            'spell_name=' .. clean(spellName(spell)),
            'spell_family=' .. clean(call(spell, 'getSpellFamily') or 0),
            'spell_group=' .. clean(call(spell, 'getSpellGroup') or 0),
            'target_hp_at_start=' .. clean(actor:getLocalVar(lastMagicTargetHpVar)),
            'target_hpp_at_start=' .. clean(actor:getLocalVar(lastMagicTargetHppVar)),
            'target_hp_missing_at_start=' .. clean(math.max(0, actor:getLocalVar(lastMagicTargetMaxHpVar) - actor:getLocalVar(lastMagicTargetHpVar))),
            'trust_mpp_at_start=' .. clean(actor:getLocalVar(lastMagicTrustMppVar)),
        })
    end)

    trust:addListener('MAGIC_STATE_EXIT', 'MOCHIRII_TRUST_LOG_MAGIC_EXIT', function(actor, spell)
        trustActionLogger.log(actor, 'magic_exit', nil, {
            'spell_id=' .. clean(call(spell, 'getID') or 0),
            'spell_name=' .. clean(spellName(spell)),
            'spell_family=' .. clean(call(spell, 'getSpellFamily') or 0),
            'spell_group=' .. clean(call(spell, 'getSpellGroup') or 0),
            'target_targid_at_start=' .. clean(actor:getLocalVar(lastMagicTargetVar)),
            'target_hp_at_start=' .. clean(actor:getLocalVar(lastMagicTargetHpVar)),
            'target_hpp_at_start=' .. clean(actor:getLocalVar(lastMagicTargetHppVar)),
            'target_hp_missing_at_start=' .. clean(math.max(0, actor:getLocalVar(lastMagicTargetMaxHpVar) - actor:getLocalVar(lastMagicTargetHpVar))),
            'trust_mpp_at_start=' .. clean(actor:getLocalVar(lastMagicTrustMppVar)),
        })
    end)
end

local function attachAbilityListeners(trust)
    trust:addListener('ABILITY_START', 'MOCHIRII_TRUST_LOG_ABILITY_START', function(actor, ability)
        trustActionLogger.log(actor, 'ability_start', nil, {
            'ability_id=' .. clean(call(ability, 'getID') or 0),
            'ability_name=' .. clean(call(ability, 'getName') or 'unknown'),
            'recast_id=' .. clean(call(ability, 'getRecastID') or 0),
        })
    end)

    trust:addListener('ABILITY_USE', 'MOCHIRII_TRUST_LOG_ABILITY_USE', function(actor, target, ability)
        trustActionLogger.log(actor, 'ability_use', target, {
            'ability_id=' .. clean(call(ability, 'getID') or 0),
            'ability_name=' .. clean(call(ability, 'getName') or 'unknown'),
            'recast_id=' .. clean(call(ability, 'getRecastID') or 0),
        })
    end)

    trust:addListener('ABILITY_STATE_EXIT', 'MOCHIRII_TRUST_LOG_ABILITY_EXIT', function(actor, ability)
        trustActionLogger.log(actor, 'ability_exit', nil, {
            'ability_id=' .. clean(call(ability, 'getID') or 0),
            'ability_name=' .. clean(call(ability, 'getName') or 'unknown'),
            'recast_id=' .. clean(call(ability, 'getRecastID') or 0),
        })
    end)
end

local function attachWeaponSkillListeners(trust)
    trust:addListener('WEAPONSKILL_STATE_ENTER', 'MOCHIRII_TRUST_LOG_WS_ENTER', function(actor, skillId)
        trustActionLogger.log(actor, 'weaponskill_start', nil, {
            'skill_id=' .. clean(skillId),
            'skill_name=' .. clean(weaponSkillName(skillId)),
        })
    end)

    trust:addListener('WEAPONSKILL_STATE_EXIT', 'MOCHIRII_TRUST_LOG_WS_EXIT', function(actor, skillId, wasExecuted)
        trustActionLogger.log(actor, 'weaponskill_exit', nil, {
            'skill_id=' .. clean(skillId),
            'skill_name=' .. clean(weaponSkillName(skillId)),
            'executed=' .. clean(wasExecuted),
        })
    end)
end

local function attachTargetListener(trust)
    trust:addListener('COMBAT_TICK', 'MOCHIRII_TRUST_LOG_TARGET', function(actor, master, target)
        local targetTargId = call(target, 'getTargID') or 0
        local previous = actor:getLocalVar(lastTargetVar)

        if targetTargId ~= previous then
            actor:setLocalVar(lastTargetVar, targetTargId)
            trustActionLogger.log(actor, targetTargId == 0 and 'target_clear' or 'target_set', target, {
                'master=' .. clean(call(master, 'getName') or 'none'),
            })
        end
    end)
end

local function attachRestBlockListener(trust)
    trust:addListener('COMBAT_TICK', 'MOCHIRII_TRUST_LOG_REST_BLOCK', function(actor, master, target)
        local blockReason = call(actor, 'getLocalVar', 'MochiTrustRestBlockReason') or 0
        local previous = actor:getLocalVar(lastRestBlockVar)

        if blockReason ~= previous then
            actor:setLocalVar(lastRestBlockVar, blockReason)
            trustActionLogger.log(actor, blockReason == 0 and 'rest_unblocked' or 'rest_block', target, {
                'master=' .. clean(call(master, 'getName') or 'none'),
                'rest_block_reason=' .. clean(blockReason),
                'rest_block=' .. clean(restBlockName(blockReason)),
            })
        end
    end)
end

local function attachCombatDiagnosticListener(trust)
    trust:addListener('COMBAT_TICK', 'MOCHIRII_TRUST_LOG_COMBAT_DIAG', function(actor, master, target)
        local interval = tonumber(setting('TRUST_ACTION_LOG_DIAGNOSTIC_TICK_SECONDS', 3)) or 0
        if interval <= 0 then
            return
        end

        local now = GetSystemTime()
        local last = actor:getLocalVar(lastDiagnosticVar)
        if last ~= 0 and now - last < interval then
            return
        end

        actor:setLocalVar(lastDiagnosticVar, now)

        local currentTarget = call(actor, 'getTarget')
        local activeTarget = target or currentTarget
        trustActionLogger.log(actor, 'combat_diag', activeTarget, {
            'master=' .. clean(call(master, 'getName') or 'none'),
            'actor_is_engaged=' .. clean(call(actor, 'isEngaged') or false),
            'current_target_name=' .. clean(call(currentTarget, 'getName') or 'none'),
            'current_target_targid=' .. clean(call(currentTarget, 'getTargID') or 0),
            distanceField('distance_to_focus_target', actor, target),
            distanceField('distance_to_current_target', actor, currentTarget),
            distanceField('distance_to_master', actor, master),
        })
    end)
end

local function attachRestListeners(trust)
    trust:addListener('COMBAT_TICK', 'MOCHIRII_TRUST_LOG_REST_STATE', function(actor, master, target)
        local restMode = call(actor, 'getLocalVar', 'MochiTrustRestMode') or 0
        local previousMode = actor:getLocalVar(lastRestModeVar)
        local currentMpp = call(actor, 'getMPP') or 0
        local previousMpp = actor:getLocalVar(lastRestMppVar)

        if restMode ~= previousMode then
            actor:setLocalVar(lastRestModeVar, restMode)
            actor:setLocalVar(lastRestMppVar, currentMpp)
            trustActionLogger.log(actor, restMode == 0 and 'rest_stop' or 'rest_start', target, {
                'master=' .. clean(call(master, 'getName') or 'none'),
                unpack(restStateFields(actor)),
            })
            return
        end

        if restMode ~= 0 and currentMpp ~= previousMpp then
            actor:setLocalVar(lastRestMppVar, currentMpp)
            trustActionLogger.log(actor, 'rest_tick', target, {
                'master=' .. clean(call(master, 'getName') or 'none'),
                unpack(restStateFields(actor)),
            })
        end
    end)
end

trustActionLogger.attach = function(trust, reason)
    if trust == nil or call(trust, 'getObjType') ~= xi.objType.TRUST then
        return false
    end

    local _, ownerName = ownerForTrust(trust)
    if ownerName == nil or not shouldLogOwner(ownerName) then
        return false
    end

    if trust:getLocalVar(attachedVar) == 1 then
        return false
    end

    trust:setLocalVar(attachedVar, 1)
    trust:setLocalVar(lastTargetVar, 0)
    trust:setLocalVar(lastRestBlockVar, 0)
    trust:setLocalVar(lastRestModeVar, call(trust, 'getLocalVar', 'MochiTrustRestMode') or 0)
    trust:setLocalVar(lastRestMppVar, call(trust, 'getMPP') or 0)

    attachMagicListeners(trust)
    attachAbilityListeners(trust)
    attachWeaponSkillListeners(trust)
    attachTargetListener(trust)
    attachRestBlockListener(trust)
    attachCombatDiagnosticListener(trust)
    attachRestListeners(trust)

    trustActionLogger.log(trust, 'logger_attached', nil, {
        'reason=' .. clean(reason or 'manual'),
    })

    return true
end

trustActionLogger.attachParty = function(player, reason)
    if player == nil then
        return 0
    end

    local ownerName = player:getName()
    if not shouldLogOwner(ownerName) then
        return 0
    end

    local attached = 0
    for _, member in pairs(player:getPartyWithTrusts()) do
        if trustActionLogger.attach(member, reason or 'party-scan') then
            attached = attached + 1
        end
    end

    return attached
end

trustActionLogger.queueAttachParty = function(player, reason)
    if player == nil then
        return
    end

    player:timer(250, function(playerArg)
        if playerArg ~= nil then
            trustActionLogger.attachParty(playerArg, reason or 'queued')
        end
    end)

    player:timer(1500, function(playerArg)
        if playerArg ~= nil then
            trustActionLogger.attachParty(playerArg, reason or 'queued-late')
        end
    end)
end

m:addOverride('xi.trust.spawn', function(caster, spell)
    local result = super(caster, spell)

    if trustActionLogger ~= nil then
        trustActionLogger.queueAttachParty(caster, 'trust-spell')
    end

    return result
end)

m:addOverride('xi.player.onGameIn', function(player, firstLogin, zoning)
    super(player, firstLogin, zoning)

    if trustActionLogger ~= nil then
        if not zoning then
            trustActionLogger.resetForLogin(player)
        end

        trustActionLogger.queueAttachParty(player, zoning and 'zone-in' or 'login')
    end
end)

return m
