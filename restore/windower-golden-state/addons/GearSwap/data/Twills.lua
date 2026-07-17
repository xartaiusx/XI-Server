-- Mochirii Twills RDM/SCH profile.
-- Uses only gear verified in Twills' local inventory and wardrobes.
-- Static coverage companion: tools/mochirii/gearswap_action_qa.py

local role_mode = 'idle'
local idle_mode = 'dt'
local enfeeble_mode = 'accuracy'
local nuke_mode = 'free'
local weapon_mode = 'daybreak'

local ws_weapon_modes = {
    ['Savage Blade'] = 'naegling',
    ['Sanguine Blade'] = 'crocea',
    ['Black Halo'] = 'maxentius',
    ['Seraph Blade'] = 'crocea',
    ['Red Lotus Blade'] = 'crocea',
    ['Requiescat'] = 'crocea',
    ['Chant du Cygne'] = 'crocea',
    ['Evisceration'] = 'tauret',
}

local mode_order = { 'idle', 'healer', 'buffer', 'debuffer', 'caster', 'melee' }
local qa_sets_path = 'C:/Github Repo\'s/FFXI/Runtime/logs/gearswap_qa/Twills-live-sets.tsv'
local qa_equipment_path = 'C:/Github Repo\'s/FFXI/Runtime/logs/gearswap_qa/Twills-live-equipment.tsv'
local qa_visual_path = 'C:/Github Repo\'s/FFXI/Runtime/logs/gearswap_qa/Twills-live-visual-models.tsv'
local qa_action_path = 'C:/Github Repo\'s/FFXI/Runtime/logs/gearswap_qa/Twills-live-action-family.tsv'
local qa_pending_baseline = nil
local gear_slots = {
    'main', 'sub', 'range', 'ammo', 'head', 'body', 'hands', 'legs',
    'feet', 'neck', 'waist', 'left_ear', 'right_ear', 'left_ring',
    'right_ring', 'back',
}
local qa_visual_slots = { 'main', 'sub', 'head', 'body', 'hands', 'legs', 'feet' }
local qa_visual_manifest_path = windower.addon_path .. 'data/Twills-visual-models.lua'
local qa_visual_items = {}
local qa_visual_manifest_error = nil

do
    local loaded, manifest = pcall(dofile, qa_visual_manifest_path)
    if loaded and type(manifest) == 'table' and type(manifest.items) == 'table' then
        qa_visual_items = manifest.items
    else
        qa_visual_manifest_error = loaded and 'manifest has no items table' or tostring(manifest)
    end
end

local mnd_enfeebles = {
    ['Addle'] = true, ['Addle II'] = true,
    ['Distract'] = true, ['Distract II'] = true, ['Distract III'] = true,
    ['Frazzle'] = true, ['Frazzle II'] = true, ['Frazzle III'] = true,
    ['Paralyze'] = true, ['Paralyze II'] = true,
    ['Silence'] = true,
    ['Slow'] = true, ['Slow II'] = true,
}

local int_enfeebles = {
    ['Bind'] = true,
    ['Blind'] = true, ['Blind II'] = true,
    ['Break'] = true,
    ['Dispel'] = true,
    ['Gravity'] = true, ['Gravity II'] = true,
    ['Poison'] = true, ['Poison II'] = true,
    ['Sleep'] = true, ['Sleep II'] = true, ['Sleepga'] = true,
}

local big_three_debuffs = {
    ['Dia III'] = true,
    ['Distract III'] = true,
    ['Frazzle III'] = true,
}

local status_removal_spells = {
    ['Erase'] = true, ['Poisona'] = true, ['Paralyna'] = true,
    ['Blindna'] = true, ['Silena'] = true, ['Cursna'] = true,
    ['Viruna'] = true, ['Stona'] = true,
}

local duration_spells = {
    ['Aquaveil'] = true,
    ['Blink'] = true,
    ['Deodorize'] = true,
    ['Flurry'] = true, ['Flurry II'] = true,
    ['Haste'] = true, ['Haste II'] = true,
    ['Invisible'] = true,
    ['Protect'] = true, ['Protect II'] = true, ['Protect III'] = true,
    ['Protect IV'] = true, ['Protect V'] = true,
    ['Regen'] = true, ['Regen II'] = true, ['Regen III'] = true,
    ['Shell'] = true, ['Shell II'] = true, ['Shell III'] = true,
    ['Shell IV'] = true, ['Shell V'] = true,
    ['Sneak'] = true,
}

local enhancing_skill_spells = {
    ['Barfire'] = true, ['Barblizzard'] = true, ['Baraero'] = true,
    ['Barstone'] = true, ['Barthunder'] = true, ['Barwater'] = true,
    ['Barsleep'] = true, ['Barpoison'] = true, ['Barparalyze'] = true,
    ['Barblind'] = true, ['Barsilence'] = true, ['Barpetrify'] = true,
    ['Barvirus'] = true,
    ['Gain-STR'] = true, ['Gain-DEX'] = true, ['Gain-VIT'] = true,
    ['Gain-AGI'] = true, ['Gain-INT'] = true, ['Gain-MND'] = true,
    ['Gain-CHR'] = true,
    ['Temper'] = true, ['Temper II'] = true,
}

local stratagems = {
    ['Penury'] = true, ['Celerity'] = true, ['Accession'] = true, ['Rapture'] = true,
    ['Parsimony'] = true, ['Alacrity'] = true, ['Manifestation'] = true, ['Ebullience'] = true,
    ['Addendum: White'] = true, ['Addendum: Black'] = true,
    ['Light Arts'] = true, ['Dark Arts'] = true,
}

local function chat(message)
    add_to_chat(122, '[Twills] ' .. message)
end

local function starts_with(text, prefix)
    return text and text:sub(1, #prefix) == prefix
end

local function contains(text, needle)
    return text and text:lower():find(needle:lower(), 1, true) ~= nil
end

local function skill_is(spell, spaced, compact)
    return spell and (spell.skill == spaced or spell.skill == compact)
end

local function spell_matches_day_or_weather(spell)
    return spell and spell.element and (
        spell.element == world.day_element or
        spell.element == world.weather_element
    )
end

local function target_distance()
    local target = windower.ffxi.get_mob_by_target('t')
    if target and target.distance then
        return math.sqrt(target.distance)
    end
end

local function is_self_target(spell)
    return spell and spell.target and player and (
        spell.target.type == 'SELF' or spell.target.name == player.name
    )
end

local function is_storm_spell(spell)
    return spell and contains(spell.english, 'storm')
end

local function is_helix_spell(spell)
    return spell and contains(spell.english, 'helix')
end

local function is_barspell(spell)
    return spell and starts_with(spell.english, 'Bar')
end

local function is_enspell(spell)
    return spell and (
        starts_with(spell.english, 'Enfire') or starts_with(spell.english, 'Enblizzard') or
        starts_with(spell.english, 'Enaero') or starts_with(spell.english, 'Enstone') or
        starts_with(spell.english, 'Enthunder') or starts_with(spell.english, 'Enwater')
    )
end

local function equip_waist_for_magic(spell)
    if spell_matches_day_or_weather(spell) then
        equip(sets.utility.Obi)
    elseif (target_distance() or 99) <= 10 then
        equip(sets.utility.Orpheus)
    end
end

local function enfeebling_set_for(spell)
    if enfeeble_mode == 'potency' or big_three_debuffs[spell.english] then
        return sets.midcast.EnfeeblingPotency
    elseif enfeeble_mode == 'mnd' or mnd_enfeebles[spell.english] then
        return sets.midcast.EnfeeblingMND
    elseif enfeeble_mode == 'int' or int_enfeebles[spell.english] then
        return sets.midcast.EnfeeblingINT
    end

    return sets.midcast.Enfeebling
end

local function nuke_set_for(spell)
    if spell and starts_with(spell.english, 'Impact') then
        return sets.midcast.Dark
    elseif is_helix_spell(spell) then
        return sets.midcast.Helix
    end

    return nuke_mode == 'burst' and sets.midcast.MagicBurst or sets.midcast.Nuke
end

local function split_words(command)
    local words = {}
    for word in tostring(command or ''):lower():gmatch('%S+') do
        words[#words + 1] = word
    end
    return words
end

local function qa_clean(value)
    if value == nil then
        return ''
    end
    if value == empty then
        return '__empty__'
    end
    if type(value) == 'table' then
        value = value.name or value.en or value.english or tostring(value)
    end

    local cleaned = tostring(value):gsub('%c', ' ')
    return cleaned
end

local function qa_missing_slots(set)
    local missing = {}
    if type(set) ~= 'table' then
        for _, slot in ipairs(gear_slots) do
            missing[#missing + 1] = slot
        end
        return missing
    end

    for _, slot in ipairs(gear_slots) do
        if set[slot] == nil or set[slot] == '' then
            missing[#missing + 1] = slot
        end
    end

    return missing
end

local function qa_slot_payload(set)
    local pieces = {}
    if type(set) == 'table' then
        for _, slot in ipairs(gear_slots) do
            pieces[#pieces + 1] = slot .. '=' .. qa_clean(set[slot])
        end
    end
    return table.concat(pieces, '|')
end

local function qa_skip_set(path)
    return path:match('^sets%.weapons') ~= nil or
        path:match('^sets%.utility') ~= nil or
        path:match('^sets%.gearscore') ~= nil or
        path:match('^sets%.role') ~= nil
end

local function qa_has_equipment_shape(value)
    if type(value) ~= 'table' then
        return false
    end

    local count = 0
    for _, slot in ipairs(gear_slots) do
        if value[slot] ~= nil then
            count = count + 1
        end
    end

    return count >= 8
end

local function qa_write_set_row(handle, label, set)
    local missing = qa_missing_slots(set)
    local status = #missing == 0 and 'PASS' or 'FAIL'
    handle:write(table.concat({
        os.date('!%Y-%m-%dT%H:%M:%SZ'),
        status,
        label,
        table.concat(missing, ','),
        qa_slot_payload(set),
    }, '\t') .. '\n')
    return status
end

local function qa_action_name(spell)
    if type(spell) ~= 'table' then
        return ''
    end

    return qa_clean(spell.english or spell.name)
end

local function qa_action_skill(spell)
    if type(spell) ~= 'table' then
        return ''
    end

    return qa_clean(spell.skill or spell.type or spell.action_type)
end

local function qa_action_target(spell)
    if type(spell) ~= 'table' or type(spell.target) ~= 'table' then
        return ''
    end

    return qa_clean(spell.target.name or spell.target.type)
end

local function qa_baseline_label()
    if player and player.status == 'Engaged' and role_mode == 'melee' then
        return 'engaged:' .. weapon_mode
    elseif role_mode == 'idle' then
        return idle_mode == 'refresh' and 'idle:refresh' or 'idle:dt'
    end

    return 'role:' .. role_mode
end

local function qa_append_action_row(event, phase, spell, label, set, outcome, issues)
    local existed = io.open(qa_action_path, 'r')
    if existed then
        existed:close()
    end

    local handle = io.open(qa_action_path, 'a')
    if not handle then
        return false
    end

    if not existed then
        handle:write('timestamp_utc\tevent\tphase\taction\tskill\ttarget\trole\tidle\tweapon\tenfeeble\tnuke\tplayer_status\texpected_baseline\tselected_set\toutcome\tmissing_or_mismatched_slots\tslots\n')
    end

    local missing = issues or qa_missing_slots(set)
    local row = {
        os.date('!%Y-%m-%dT%H:%M:%SZ'),
        qa_clean(event),
        qa_clean(phase),
        qa_action_name(spell),
        qa_action_skill(spell),
        qa_action_target(spell),
        role_mode,
        idle_mode,
        weapon_mode,
        enfeeble_mode,
        nuke_mode,
        player and qa_clean(player.status) or '',
        qa_baseline_label(),
        qa_clean(label),
        qa_clean(outcome or (#missing == 0 and 'PASS' or 'FAIL')),
        table.concat(missing, ','),
        qa_slot_payload(set),
    }
    handle:write(table.concat(row, '\t') .. '\n')
    handle:close()
    return true
end

local function qa_equip(label, set, spell, phase)
    qa_append_action_row('equip', phase or '', spell, label, set, nil)
    equip(set)
end

local function qa_actual_equipment()
    local actual = {}
    local equipment = player and player.equipment or {}
    for _, slot in ipairs(gear_slots) do
        local value = equipment[slot]
        if value == nil or value == '' or value == 'empty' then
            actual[slot] = empty
        else
            actual[slot] = value
        end
    end
    return actual
end

local function qa_verify_pending_baseline()
    if not qa_pending_baseline then
        chat('QA baseline verification has no pending action.')
        return false
    end

    local pending = qa_pending_baseline
    qa_pending_baseline = nil
    local actual = qa_actual_equipment()
    local mismatched = {}
    for _, slot in ipairs(gear_slots) do
        if qa_clean(actual[slot]) ~= qa_clean(pending.set[slot]) then
            mismatched[#mismatched + 1] = slot
        end
    end

    local outcome = #mismatched == 0 and 'PASS' or 'FAIL'
    qa_append_action_row('verify', 'aftercast_baseline', pending.spell, pending.label, actual, outcome, mismatched)
    chat('QA baseline ' .. outcome .. ' action=' .. qa_action_name(pending.spell) .. ' mismatches=' .. table.concat(mismatched, ','))
    return #mismatched == 0
end

local function qa_settle_pending_baseline()
    if not qa_pending_baseline then
        return false
    end

    local pending = qa_pending_baseline
    local label, set = equip_current()
    qa_pending_baseline = { spell = pending.spell, label = label, set = set }
    send_command('wait 0.5;gs c qa baseline')
    return true
end

local function qa_walk_sets(handle, path, value, visited, counts)
    if type(value) ~= 'table' or visited[value] then
        return
    end

    visited[value] = true
    if not qa_skip_set(path) and qa_has_equipment_shape(value) then
        local status = qa_write_set_row(handle, path, value)
        counts[status] = (counts[status] or 0) + 1
    end

    for key, child in pairs(value) do
        if type(child) == 'table' then
            qa_walk_sets(handle, path .. '.' .. tostring(key), child, visited, counts)
        end
    end
end

local function qa_write_equipment_snapshot()
    local handle = io.open(qa_equipment_path, 'w')
    if not handle then
        chat('QA could not write ' .. qa_equipment_path)
        return false
    end

    handle:write('timestamp_utc\tslot\titem\n')
    local equipment = player and player.equipment or {}
    for _, slot in ipairs(gear_slots) do
        handle:write(table.concat({
            os.date('!%Y-%m-%dT%H:%M:%SZ'),
            slot,
            qa_clean(equipment[slot]),
        }, '\t') .. '\n')
    end
    handle:close()
    return true
end

local function qa_write_visual_snapshot()
    local handle = io.open(qa_visual_path, 'w')
    if not handle then
        chat('QA could not write ' .. qa_visual_path)
        return false
    end

    handle:write('timestamp_utc\tslot\titem\titem_id\tmodel_id\tstatus\n')
    if qa_visual_manifest_error then
        handle:write('# manifest_error\t' .. qa_clean(qa_visual_manifest_error) .. '\n')
    end
    local equipment = player and player.equipment or {}
    local fail_count = 0
    for _, slot in ipairs(qa_visual_slots) do
        local item = qa_clean(equipment[slot])
        local visual = qa_visual_items[item]
        local status = 'UNKNOWN'
        local item_id = ''
        local model_id = ''
        if item == '' or item == '__empty__' then
            status = 'EMPTY'
        elseif visual then
            item_id = tostring(visual.item_id)
            model_id = tostring(visual.model_id)
            status = visual.model_id == 0 and 'FAIL' or 'PASS'
        end
        if status == 'FAIL' or status == 'UNKNOWN' then
            fail_count = fail_count + 1
        end
        handle:write(table.concat({ os.date('!%Y-%m-%dT%H:%M:%SZ'), slot, item, item_id, model_id, status }, '\t') .. '\n')
    end
    handle:close()
    chat('QA visual FAIL=' .. fail_count .. '; evidence=' .. qa_visual_path)
    return fail_count == 0
end

local function qa_write_action_family_matrix()
    local handle = io.open(qa_action_path, 'w')
    if not handle then
        chat('QA could not write ' .. qa_action_path)
        return false
    end

    handle:write('timestamp_utc\tevent\tphase\taction\tskill\ttarget\trole\tidle\tweapon\tenfeeble\tnuke\tplayer_status\texpected_baseline\tselected_set\toutcome\tmissing_or_mismatched_slots\tslots\n')
    local families = {
        { 'idle_dt', 'sets.idle', sets.idle },
        { 'idle_refresh', 'sets.idle.Refresh', sets.idle.Refresh },
        { 'engaged_tp', 'sets.engaged', sets.engaged },
        { 'fast_cast', 'sets.precast.FC', sets.precast.FC },
        { 'cure', 'sets.midcast.Cure', sets.midcast.Cure },
        { 'status_removal', 'sets.midcast.StatusRemoval', sets.midcast.StatusRemoval },
        { 'refresh_iii', 'sets.midcast.Refresh', sets.midcast.Refresh },
        { 'phalanx_ii', 'sets.midcast.Phalanx', sets.midcast.Phalanx },
        { 'temper_enspell', 'sets.midcast.Enspell', sets.midcast.Enspell },
        { 'barspell', 'sets.midcast.Barspell', sets.midcast.Barspell },
        { 'enfeeble_accuracy', 'sets.midcast.Enfeebling', sets.midcast.Enfeebling },
        { 'enfeeble_mnd', 'sets.midcast.EnfeeblingMND', sets.midcast.EnfeeblingMND },
        { 'enfeeble_int', 'sets.midcast.EnfeeblingINT', sets.midcast.EnfeeblingINT },
        { 'nuke', 'sets.midcast.Nuke', sets.midcast.Nuke },
        { 'magic_burst', 'sets.midcast.MagicBurst', sets.midcast.MagicBurst },
        { 'dark_magic', 'sets.midcast.Dark', sets.midcast.Dark },
        { 'savage_blade', "sets.precast.WS['Savage Blade']", sets.precast.WS['Savage Blade'] },
        { 'sanguine_blade', "sets.precast.WS['Sanguine Blade']", sets.precast.WS['Sanguine Blade'] },
        { 'black_halo', "sets.precast.WS['Black Halo']", sets.precast.WS['Black Halo'] },
    }

    local counts = { PASS = 0, FAIL = 0 }
    for _, family in ipairs(families) do
        local missing = qa_missing_slots(family[3])
        local status = #missing == 0 and 'PASS' or 'FAIL'
        counts[status] = (counts[status] or 0) + 1
        handle:write(table.concat({
            os.date('!%Y-%m-%dT%H:%M:%SZ'),
            'family',
            'matrix',
            family[1],
            '',
            '',
            role_mode,
            idle_mode,
            weapon_mode,
            enfeeble_mode,
            nuke_mode,
            player and qa_clean(player.status) or '',
            qa_baseline_label(),
            family[2],
            status,
            table.concat(missing, ','),
            qa_slot_payload(family[3]),
        }, '\t') .. '\n')
    end
    handle:close()
    chat('QA action families PASS=' .. counts.PASS .. ', FAIL=' .. counts.FAIL .. '; evidence=' .. qa_action_path)
    return counts.FAIL == 0
end

local function qa_run_sets()
    local handle = io.open(qa_sets_path, 'w')
    if not handle then
        chat('QA could not write ' .. qa_sets_path)
        return
    end

    handle:write('timestamp_utc\tstatus\tset\tmissing_slots\tslots\n')
    local counts = { PASS = 0, FAIL = 0 }
    qa_walk_sets(handle, 'sets', sets, {}, counts)
    handle:close()
    qa_write_equipment_snapshot()
    qa_write_visual_snapshot()
    qa_write_action_family_matrix()
    chat('QA sets PASS=' .. counts.PASS .. ', FAIL=' .. counts.FAIL .. '; evidence=' .. qa_sets_path)
end

local function qa_status()
    chat('QA static: python3 tools/mochirii/gearswap_action_qa.py --repo-root .')
    chat('QA live sets: ' .. qa_sets_path)
    chat('QA live equipment: ' .. qa_equipment_path)
    chat('QA live visual models: ' .. qa_visual_path)
    chat('QA live action families: ' .. qa_action_path)
end

local function set_role(mode)
    role_mode = mode
    chat('Role=' .. role_mode .. ', Idle=' .. idle_mode .. ', Weapon=' .. weapon_mode .. ', Enf=' .. enfeeble_mode .. ', Nuke=' .. nuke_mode)
    equip_current()
end

function get_sets()
    sets = {}

    sets.weapons = {
        daybreak = { main="Daybreak", sub="Ammurapi Shield" },
        crocea = { main="Crocea Mors", sub="Ammurapi Shield" },
        naegling = { main="Naegling", sub="Ammurapi Shield" },
        maxentius = { main="Maxentius", sub="Ammurapi Shield" },
        bunzi = { main="Bunzi's Rod", sub="Ammurapi Shield" },
        tauret = { main="Tauret", sub="Ammurapi Shield" },
    }

    sets.utility = {
        Obi = { waist="Hachirin-no-Obi" },
        Orpheus = { waist="Orpheus's Sash" },
    }

    sets.idle = {
        main="Daybreak", sub="Genmei Shield", range=empty, ammo="Staunch Tathlum +1",
        head="Malignance Chapeau", body="Malignance Tabard", hands="Malignance Gloves",
        legs="Malignance Tights", feet="Malignance Boots",
        neck="Loricate Torque +1", waist="Carrier's Sash",
        left_ear="Etiolation Earring", right_ear="Malignance Earring",
        left_ring="Defending Ring", right_ring="Vocane Ring +1",
        back="Sucellos's Cape",
    }

    sets.idle.Refresh = set_combine(sets.idle, {
        main="Daybreak", sub="Ammurapi Shield",
        legs="Malignance Tights", feet="Volte Gaiters",
        right_ring="Stikini Ring +1",
    })

    sets.idle.Healer = set_combine(sets.idle.Refresh, sets.weapons.daybreak, {
        ammo="Staunch Tathlum +1", right_ring="Stikini Ring +1",
    })

    sets.idle.Buffer = set_combine(sets.idle.Refresh, sets.weapons.crocea, {
        body="Lethargy Sayon +2", hands="Malignance Gloves",
        right_ring="Stikini Ring +1",
    })

    sets.idle.Debuffer = set_combine(sets.idle.Refresh, sets.weapons.crocea, {
        ammo="Regal Gem", neck="Dls. Torque +2",
        left_ring="Stikini Ring +1", right_ring="Metamor. Ring +1",
    })

    sets.idle.Caster = set_combine(sets.idle.Refresh, sets.weapons.crocea, {
        ammo="Pemphredo Tathlum", neck="Baetyl Pendant",
        left_ring="Freke Ring", right_ring="Metamor. Ring +1",
    })

    sets.engaged = set_combine(sets.weapons.crocea, {
        range=empty, ammo="Coiste Bodhar",
        head="Malignance Chapeau", body="Malignance Tabard", hands="Malignance Gloves",
        legs="Malignance Tights", feet="Malignance Boots",
        neck="Anu Torque", waist="Sailfi Belt +1",
        left_ear="Telos Earring", right_ear="Sherida Earring",
        left_ring="Chirich Ring +1", right_ring="Chirich Ring +1",
        back="Sucellos's Cape",
    })

    sets.precast = {}
    sets.precast.FC = set_combine(sets.weapons.crocea, {
        range=empty, ammo="Sapience Orb",
        head="Viti. Chapeau +3", body="Lethargy Sayon +2", hands="Aya. Manopolas +2",
        legs="Aya. Cosciales +2", feet="Carmine Greaves +1",
        neck="Dls. Torque +2", waist="Acuity Belt +1",
        left_ear="Etiolation Earring", right_ear="Malignance Earring",
        left_ring="Kishar Ring", right_ring="Prolix Ring",
        back="Sucellos's Cape",
    })

    sets.precast.JA = set_combine(sets.idle, {})
    sets.precast.JA['Chainspell'] = set_combine(sets.precast.FC, { body="Atrophy Tabard +3" })
    sets.precast.JA['Composure'] = set_combine(sets.idle, {
        head="Leth. Chappel +2", body="Lethargy Sayon +2", hands="Leth. Ganth. +2",
        legs="Leth. Fuseau +2", feet="Leth. Houseaux +2",
    })
    sets.precast.JA['Convert'] = set_combine(sets.idle.Refresh, {
        body="Viti. Tabard +2", legs="Viti. Tights +2", feet="Vitiation Boots +3",
        left_ring="Defending Ring", right_ring="Vocane Ring +1",
    })
    sets.precast.JA['Saboteur'] = set_combine(sets.idle.Debuffer, {
        head="Viti. Chapeau +3", body="Lethargy Sayon +2", hands="Leth. Ganth. +2",
        legs="Leth. Fuseau +2", feet="Vitiation Boots +3",
        right_ear="Snotra Earring",
    })
    sets.precast.JA['Stymie'] = set_combine(sets.precast.JA['Saboteur'], {})
    sets.precast.JA['Spontaneity'] = set_combine(sets.precast.FC, {})
    sets.precast.JA['Sublimation'] = set_combine(sets.idle.Refresh, {})
    for name in pairs(stratagems) do
        sets.precast.JA[name] = set_combine(sets.precast.FC, {})
    end

    sets.precast.WS = set_combine(sets.weapons.naegling, {
        range=empty, ammo="Regal Gem",
        head="Nyame Helm", body="Nyame Mail", hands="Nyame Gauntlets",
        legs="Nyame Flanchard", feet="Nyame Sollerets",
        neck="Fotia Gorget", waist="Fotia Belt",
        left_ear="Telos Earring", right_ear="Sherida Earring",
        left_ring="Epaminondas's Ring", right_ring="Sroda Ring",
        back="Sucellos's Cape",
    })
    sets.precast.WS['Savage Blade'] = set_combine(sets.precast.WS, sets.weapons.naegling)
    sets.precast.WS['Black Halo'] = set_combine(sets.precast.WS, sets.weapons.maxentius)
    sets.precast.WS['Requiescat'] = set_combine(sets.precast.WS, sets.weapons.crocea)
    sets.precast.WS['Chant du Cygne'] = set_combine(sets.precast.WS, sets.weapons.crocea)
    sets.precast.WS['Evisceration'] = set_combine(sets.precast.WS, sets.weapons.tauret)
    sets.precast.WS['Sanguine Blade'] = set_combine(sets.weapons.crocea, {
        range=empty, ammo="Pemphredo Tathlum",
        head="Nyame Helm", body="Nyame Mail", hands="Nyame Gauntlets",
        legs="Nyame Flanchard", feet="Nyame Sollerets",
        neck="Baetyl Pendant", waist="Orpheus's Sash",
        left_ear="Friomisi Earring", right_ear="Malignance Earring",
        left_ring="Freke Ring", right_ring="Archon Ring",
        back="Sucellos's Cape",
    })
    sets.precast.WS['Seraph Blade'] = set_combine(sets.precast.WS['Sanguine Blade'], sets.weapons.crocea)
    sets.precast.WS['Red Lotus Blade'] = set_combine(sets.precast.WS['Sanguine Blade'], sets.weapons.crocea)

    sets.midcast = {}
    sets.midcast.Cure = set_combine(sets.weapons.daybreak, {
        range=empty, ammo="Staunch Tathlum +1",
        head="Kaykaus Mitra +1", body="Kaykaus Bliaut +1", hands="Kaykaus Cuffs +1",
        legs="Kaykaus Tights +1", feet="Kaykaus Boots +1",
        neck="Incanter's Torque", waist="Bishop's Sash",
        left_ear="Mendi. Earring", right_ear="Mimir Earring",
        left_ring="Sirona's Ring", right_ring="Metamor. Ring +1",
        back="Sucellos's Cape",
    })
    sets.midcast.StatusRemoval = set_combine(sets.midcast.Cure, {
        main="Daybreak", ammo="Staunch Tathlum +1",
    })
    sets.midcast.Raise = set_combine(sets.precast.FC, {})

    sets.midcast.EnhancingSkill = set_combine(sets.weapons.crocea, {
        range=empty, ammo="Staunch Tathlum +1",
        head="Telchine Cap", body="Telchine Chas.", hands="Atrophy Gloves +3",
        legs="Telchine Braconi", feet="Leth. Houseaux +2",
        neck="Incanter's Torque", waist="Olympus Sash",
        left_ear="Andoaa Earring", right_ear="Mimir Earring",
        left_ring="Stikini Ring +1", right_ring="Stikini Ring +1",
        back="Sucellos's Cape",
    })
    sets.midcast.Enhancing = sets.midcast.EnhancingSkill

    sets.midcast.EnhancingDuration = set_combine(sets.weapons.crocea, {
        range=empty, ammo="Staunch Tathlum +1",
        head="Telchine Cap", body="Telchine Chas.", hands="Telchine Gloves",
        legs="Telchine Braconi", feet="Telchine Pigaches",
        neck="Dls. Torque +2", waist="Olympus Sash",
        left_ear="Andoaa Earring", right_ear="Mimir Earring",
        left_ring="Stikini Ring +1", right_ring="Stikini Ring +1",
        back="Sucellos's Cape",
    })
    sets.midcast.EnhancingSelf = set_combine(sets.midcast.EnhancingDuration, {
        body="Lethargy Sayon +2", hands="Atrophy Gloves +3",
        legs="Leth. Fuseau +2", feet="Leth. Houseaux +2",
    })
    sets.midcast.Refresh = set_combine(sets.midcast.EnhancingDuration, {
        head="Leth. Chappel +2", body="Atrophy Tabard +3",
        hands="Atrophy Gloves +3", legs="Leth. Fuseau +2",
    })
    sets.midcast.Phalanx = set_combine(sets.midcast.EnhancingSkill, {
        body="Lethargy Sayon +2", hands="Atrophy Gloves +3",
        feet="Leth. Houseaux +2",
    })
    sets.midcast.Stoneskin = set_combine(sets.midcast.EnhancingSkill, {
        waist="Siegel Sash", legs="Shedir Seraweels",
    })
    sets.midcast.Aquaveil = set_combine(sets.midcast.EnhancingDuration, {
        hands="Telchine Gloves", legs="Shedir Seraweels",
    })
    sets.midcast.Barspell = set_combine(sets.midcast.EnhancingSkill, {
        neck="Incanter's Torque", waist="Olympus Sash", left_ear="Andoaa Earring",
    })
    sets.midcast.Enspell = set_combine(sets.midcast.EnhancingSkill, {
        main="Crocea Mors", body="Lethargy Sayon +2", hands="Atrophy Gloves +3",
    })
    sets.midcast.Storm = set_combine(sets.midcast.EnhancingDuration, {})

    sets.midcast.Enfeebling = set_combine(sets.weapons.crocea, {
        range=empty, ammo="Regal Gem",
        head="Viti. Chapeau +3", body="Lethargy Sayon +2", hands="Leth. Ganth. +2",
        legs="Leth. Fuseau +2", feet="Vitiation Boots +3",
        neck="Dls. Torque +2", waist="Acuity Belt +1",
        left_ear="Digni. Earring", right_ear="Mimir Earring",
        left_ring="Stikini Ring +1", right_ring="Metamor. Ring +1",
        back="Sucellos's Cape",
    })
    sets.midcast.EnfeeblingMND = set_combine(sets.midcast.Enfeebling, {
        right_ear="Snotra Earring",
    })
    sets.midcast.EnfeeblingINT = set_combine(sets.midcast.Enfeebling, {
        ammo="Pemphredo Tathlum", right_ear="Regal Earring",
        left_ring="Freke Ring",
    })
    sets.midcast.EnfeeblingPotency = set_combine(sets.midcast.EnfeeblingMND, {
        head="Viti. Chapeau +3", body="Lethargy Sayon +2", hands="Leth. Ganth. +2",
        legs="Leth. Fuseau +2", feet="Vitiation Boots +3",
    })

    sets.midcast.Nuke = set_combine(sets.weapons.crocea, {
        range=empty, ammo="Pemphredo Tathlum",
        head="Amalric Coif +1", body="Amalric Doublet +1", hands="Amalric Gages +1",
        legs="Amalric Slops +1", feet="Amalric Nails +1",
        neck="Baetyl Pendant", waist="Acuity Belt +1",
        left_ear="Friomisi Earring", right_ear="Regal Earring",
        left_ring="Freke Ring", right_ring="Metamor. Ring +1",
        back="Sucellos's Cape",
    })
    sets.midcast.MagicBurst = set_combine(sets.midcast.Nuke, {
        head="Ea Hat +1", body="Ea Houppe. +1", hands="Ea Cuffs +1",
        legs="Ea Slops +1", feet="Ea Pigaches +1",
        waist="Hachirin-no-Obi",
    })
    sets.midcast.Helix = set_combine(sets.midcast.MagicBurst, {
        head="Agwu's Cap", body="Agwu's Robe", hands="Agwu's Gages",
        legs="Agwu's Slops", feet="Agwu's Pigaches",
    })
    sets.midcast.Dark = set_combine(sets.midcast.Nuke, {
        left_ring="Archon Ring", right_ring="Metamor. Ring +1",
    })

    sets.role = {
        idle = sets.idle,
        healer = sets.idle.Healer,
        buffer = sets.idle.Buffer,
        debuffer = sets.idle.Debuffer,
        caster = sets.idle.Caster,
        melee = sets.engaged,
    }

    sets.gearscore = {
        ['Idle DT'] = 'local-supported DT/MEVA baseline with refresh variant',
        ['Fast Cast'] = 'RDM FC/JSE and locally implemented accessories',
        ['Enhancing'] = 'Crocea, skill gear, Telchine duration, RDM JSE duration',
        ['Enfeebling'] = 'Crocea, Duelist torque, RDM JSE, Stikini, Snotra/Regal split',
        ['Nuking'] = 'Amalric/Ea/Agwu split with Obi/Orpheus logic',
        ['Weapon Skills'] = 'Nyame Path B core with pre-equipped Naegling, Maxentius, Crocea, or Tauret modes',
    }

    chat('Twills RDM/SCH GearSwap v12 loaded; role=' .. role_mode)
    equip_current()
end

function pretarget(spell)
    if spell.type ~= 'WeaponSkill' then
        return
    end

    local required_mode = ws_weapon_modes[spell.english]
    local required_set = required_mode and sets.weapons[required_mode]
    local equipped_main = player and player.equipment and player.equipment.main
    if required_set and equipped_main ~= required_set.main then
        cancel_spell()
        weapon_mode = required_mode
        role_mode = 'melee'
        equip_current()
        chat(string.format('%s requires %s. Weapon equipped; rebuild TP and retry.', spell.english, required_set.main))
    end
end

function precast(spell)
    if spell.type == 'WeaponSkill' then
        qa_equip('sets.precast.WS.' .. spell.english, sets.precast.WS[spell.english] or sets.precast.WS, spell, 'precast')
    elseif spell.type == 'JobAbility' then
        qa_equip('sets.precast.JA.' .. spell.english, sets.precast.JA[spell.english] or sets.precast.JA, spell, 'precast')
    elseif spell.action_type == 'Magic' then
        qa_equip('sets.precast.FC', sets.precast.FC, spell, 'precast')
    end
end

function midcast(spell)
    if starts_with(spell.english, 'Cure') or starts_with(spell.english, 'Curaga') then
        qa_equip('sets.midcast.Cure', sets.midcast.Cure, spell, 'midcast')
        if spell_matches_day_or_weather(spell) then
            equip(sets.utility.Obi)
        end
    elseif status_removal_spells[spell.english] then
        qa_equip('sets.midcast.StatusRemoval', sets.midcast.StatusRemoval, spell, 'midcast')
    elseif starts_with(spell.english, 'Raise') or starts_with(spell.english, 'Reraise') then
        qa_equip('sets.midcast.Raise', sets.midcast.Raise, spell, 'midcast')
    elseif skill_is(spell, 'Healing Magic', 'HealingMagic') then
        qa_equip('sets.midcast.Cure', sets.midcast.Cure, spell, 'midcast')
    elseif skill_is(spell, 'Enhancing Magic', 'EnhancingMagic') then
        if starts_with(spell.english, 'Refresh') then
            qa_equip('sets.midcast.Refresh', sets.midcast.Refresh, spell, 'midcast')
        elseif starts_with(spell.english, 'Phalanx') then
            qa_equip('sets.midcast.Phalanx', sets.midcast.Phalanx, spell, 'midcast')
        elseif spell.english == 'Stoneskin' then
            qa_equip('sets.midcast.Stoneskin', sets.midcast.Stoneskin, spell, 'midcast')
        elseif spell.english == 'Aquaveil' then
            qa_equip('sets.midcast.Aquaveil', sets.midcast.Aquaveil, spell, 'midcast')
        elseif is_barspell(spell) then
            qa_equip('sets.midcast.Barspell', sets.midcast.Barspell, spell, 'midcast')
        elseif is_enspell(spell) or enhancing_skill_spells[spell.english] then
            qa_equip('sets.midcast.Enspell', sets.midcast.Enspell, spell, 'midcast')
        elseif is_storm_spell(spell) then
            qa_equip('sets.midcast.Storm', sets.midcast.Storm, spell, 'midcast')
        elseif duration_spells[spell.english] then
            qa_equip(is_self_target(spell) and 'sets.midcast.EnhancingSelf' or 'sets.midcast.EnhancingDuration', is_self_target(spell) and sets.midcast.EnhancingSelf or sets.midcast.EnhancingDuration, spell, 'midcast')
        else
            qa_equip('sets.midcast.EnhancingSkill', sets.midcast.EnhancingSkill, spell, 'midcast')
        end
    elseif skill_is(spell, 'Enfeebling Magic', 'EnfeeblingMagic') then
        qa_equip('sets.midcast.Enfeebling:' .. enfeeble_mode, enfeebling_set_for(spell), spell, 'midcast')
    elseif skill_is(spell, 'Elemental Magic', 'ElementalMagic') then
        qa_equip('sets.midcast.Nuke:' .. nuke_mode, nuke_set_for(spell), spell, 'midcast')
        equip_waist_for_magic(spell)
    elseif skill_is(spell, 'Dark Magic', 'DarkMagic') then
        qa_equip('sets.midcast.Dark', sets.midcast.Dark, spell, 'midcast')
        equip_waist_for_magic(spell)
    end
end

function aftercast(spell)
    equip_current(spell, 'aftercast')
end

function status_change()
    equip_current()
end

function buff_change()
    equip_current()
end

function buff_refresh()
    equip_current()
end

function sub_job_change()
    equip_current()
end

function self_command(command)
    local words = split_words(command)
    local action = words[1] or ''
    local value = words[2] or ''

    if action == 'healer' or action == 'heal' then
        set_role('healer')
    elseif action == 'buffer' or action == 'buff' then
        set_role('buffer')
    elseif action == 'debuffer' or action == 'debuff' then
        set_role('debuffer')
    elseif action == 'melee' or action == 'damage' then
        set_role('melee')
    elseif action == 'caster' or action == 'nuker' then
        set_role('caster')
    elseif action == 'idle' then
        set_role('idle')
    elseif action == 'cycle' then
        for index, mode in ipairs(mode_order) do
            if role_mode == mode then
                set_role(mode_order[(index % #mode_order) + 1])
                return
            end
        end
        set_role('idle')
    elseif action == 'dt' then
        idle_mode = 'dt'
        set_role(role_mode)
    elseif action == 'refresh' then
        idle_mode = 'refresh'
        set_role(role_mode)
    elseif action == 'enf' and (value == 'acc' or value == 'accuracy') then
        enfeeble_mode = 'accuracy'
        set_role('debuffer')
    elseif action == 'enf' and value == 'mnd' then
        enfeeble_mode = 'mnd'
        set_role('debuffer')
    elseif action == 'enf' and value == 'int' then
        enfeeble_mode = 'int'
        set_role('debuffer')
    elseif action == 'enf' and value == 'potency' then
        enfeeble_mode = 'potency'
        set_role('debuffer')
    elseif action == 'nuke' and value == 'burst' then
        nuke_mode = 'burst'
        set_role('caster')
    elseif action == 'nuke' and value == 'free' then
        nuke_mode = 'free'
        set_role('caster')
    elseif action == 'burst' then
        nuke_mode = 'burst'
        set_role('caster')
    elseif action == 'free' or action == 'nuke' then
        nuke_mode = 'free'
        set_role('caster')
    elseif action == 'weapon' and sets.weapons[value] ~= nil then
        weapon_mode = value
        set_role(role_mode)
    elseif action == 'qa' and (value == 'all' or value == 'sets') then
        qa_run_sets()
    elseif action == 'qa' and (value == 'family' or value == 'families' or value == 'actions') then
        qa_write_action_family_matrix()
    elseif action == 'qa' and value == 'baseline' then
        qa_verify_pending_baseline()
    elseif action == 'qa' and value == 'settle' then
        qa_settle_pending_baseline()
    elseif action == 'qa' and value == 'snapshot' then
        qa_write_equipment_snapshot()
        chat('QA equipment snapshot=' .. qa_equipment_path)
    elseif action == 'qa' and value == 'visual' then
        qa_write_visual_snapshot()
    elseif action == 'qa' and value == 'status' then
        qa_status()
    elseif action == 'validate' then
        send_command('gs validate sets;wait 1;gs validate inv')
    elseif action == 'reset' then
        role_mode = 'idle'
        idle_mode = 'dt'
        enfeeble_mode = 'accuracy'
        nuke_mode = 'free'
        weapon_mode = 'daybreak'
        set_role(role_mode)
    elseif action == 'status' then
        chat('Role=' .. role_mode .. ', Idle=' .. idle_mode .. ', Weapon=' .. weapon_mode .. ', Enf=' .. enfeeble_mode .. ', Nuke=' .. nuke_mode)
    elseif action == 'gearscore' or action == 'score' then
        for label, detail in pairs(sets.gearscore) do
            chat(label .. ': ' .. detail)
        end
    else
        chat('Commands: idle, healer, buffer, debuffer, caster, melee, cycle, dt, refresh, enf acc/mnd/int/potency, nuke free/burst, weapon daybreak/crocea/naegling/maxentius/bunzi/tauret, validate, qa all/status/snapshot/visual/families, status, gearscore, reset')
    end
end

function equip_current(spell, phase)
    local label
    local set
    if role_mode == 'melee' then
        label = player and player.status == 'Engaged' and 'baseline:engaged:' .. weapon_mode or 'baseline:role:melee:' .. weapon_mode
        set = set_combine(sets.engaged, sets.weapons[weapon_mode] or sets.weapons.crocea)
    elseif role_mode == 'idle' then
        label = idle_mode == 'refresh' and 'baseline:idle:refresh' or 'baseline:idle:dt'
        set = idle_mode == 'refresh' and sets.idle.Refresh or sets.idle
    else
        label = 'baseline:role:' .. role_mode
        set = sets.role[role_mode] or sets.idle
    end

    qa_equip(label, set, spell, phase or 'baseline')
    if spell and phase == 'aftercast' then
        qa_pending_baseline = { spell = spell, label = label, set = set }
        send_command('wait 0.5;gs c qa settle')
    end

    return label, set
end
