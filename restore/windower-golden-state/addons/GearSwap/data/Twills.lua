-- Mochirii Twills RDM/SCH profile.
-- Uses only gear verified in Twills' local inventory and wardrobes.
-- Static coverage companion: tools/mochirii/gearswap_action_qa.py

local role_mode = 'idle'
local idle_mode = 'dt'
local enfeeble_mode = 'accuracy'
local nuke_mode = 'free'
local weapon_mode = 'daybreak'

local mode_order = { 'idle', 'healer', 'buffer', 'debuffer', 'caster', 'melee' }
local qa_sets_path = 'C:/Users/xtyty/Documents/FFXI-Runtime/logs/gearswap_qa/Twills-live-sets.tsv'
local qa_equipment_path = 'C:/Users/xtyty/Documents/FFXI-Runtime/logs/gearswap_qa/Twills-live-equipment.tsv'
local qa_visual_path = 'C:/Users/xtyty/Documents/FFXI-Runtime/logs/gearswap_qa/Twills-live-visual-models.tsv'
local gear_slots = {
    'main', 'sub', 'range', 'ammo', 'head', 'body', 'hands', 'legs',
    'feet', 'neck', 'waist', 'left_ear', 'right_ear', 'left_ring',
    'right_ring', 'back',
}
local qa_visual_slots = { 'main', 'sub', 'head', 'body', 'hands', 'legs', 'feet' }
local qa_visual_items = {
    ["Agwu's Pigaches"] = { item_id = 23770, model_id = 442 },
    ["Agwu's Robe"] = { item_id = 23764, model_id = 442 },
    ["Amalric Coif +1"] = { item_id = 25541, model_id = 442 },
    ["Amalric Doublet +1"] = { item_id = 25755, model_id = 442 },
    ["Amalric Gages +1"] = { item_id = 25805, model_id = 442 },
    ["Amalric Nails +1"] = { item_id = 25927, model_id = 442 },
    ["Amalric Slops +1"] = { item_id = 25864, model_id = 442 },
    ["Ammurapi Shield"] = { item_id = 26419, model_id = 42 },
    ["Atrophy Boots +3"] = { item_id = 23647, model_id = 286 },
    ["Atrophy Gloves +3"] = { item_id = 23513, model_id = 286 },
    ["Atrophy Tabard +3"] = { item_id = 23446, model_id = 286 },
    ["Bunzi's Hat"] = { item_id = 23754, model_id = 451 },
    ["Bunzi's Pants"] = { item_id = 23766, model_id = 451 },
    ["Bunzi's Rod"] = { item_id = 22122, model_id = 531 },
    ["Crocea Mors"] = { item_id = 21611, model_id = 529 },
    ["Daybreak"] = { item_id = 22040, model_id = 532 },
    ["Ea Houppelande +1"] = { item_id = 25765, model_id = 442 },
    ["Genmei Shield"] = { item_id = 26421, model_id = 42 },
    ["Jhakri Cuffs +2"] = { item_id = 25821, model_id = 287 },
    ["Jhakri Pigaches +2"] = { item_id = 25941, model_id = 287 },
    ["Jhakri Robe +2"] = { item_id = 25783, model_id = 287 },
    ["Kaykaus Boots +1"] = { item_id = 25922, model_id = 442 },
    ["Kaykaus Cuffs +1"] = { item_id = 25800, model_id = 442 },
    ["Kaykaus Mitra +1"] = { item_id = 25536, model_id = 442 },
    ["Kaykaus Tights +1"] = { item_id = 25859, model_id = 442 },
    ["Leth. Chappel +2"] = { item_id = 23089, model_id = 286 },
    ["Leth. Fuseau +2"] = { item_id = 23290, model_id = 286 },
    ["Leth. Ganth. +2"] = { item_id = 23223, model_id = 286 },
    ["Leth. Houseaux +2"] = { item_id = 23357, model_id = 286 },
    ["Lethargy Sayon +2"] = { item_id = 23156, model_id = 286 },
    ["Malignance Boots"] = { item_id = 23736, model_id = 458 },
    ["Malignance Chapeau"] = { item_id = 23732, model_id = 458 },
    ["Malignance Gloves"] = { item_id = 23734, model_id = 458 },
    ["Malignance Tabard"] = { item_id = 23733, model_id = 458 },
    ["Malignance Tights"] = { item_id = 23735, model_id = 458 },
    ["Maxentius"] = { item_id = 22043, model_id = 532 },
    ["Naegling"] = { item_id = 21684, model_id = 529 },
    ["Nyame Flanchard"] = { item_id = 23782, model_id = 451 },
    ["Nyame Gauntlets"] = { item_id = 23775, model_id = 451 },
    ["Nyame Helm"] = { item_id = 23753, model_id = 451 },
    ["Nyame Mail"] = { item_id = 23760, model_id = 451 },
    ["Nyame Sollerets"] = { item_id = 23789, model_id = 451 },
    ["Tauret"] = { item_id = 21694, model_id = 530 },
    ["Telchine Braconi"] = { item_id = 25843, model_id = 289 },
    ["Telchine Cap"] = { item_id = 25547, model_id = 289 },
    ["Telchine Gloves"] = { item_id = 25809, model_id = 289 },
    ["Telchine Pigaches"] = { item_id = 25933, model_id = 289 },
    ["Viti. Chapeau +3"] = { item_id = 23402, model_id = 286 },
    ["Vitiation Boots +3"] = { item_id = 23670, model_id = 286 },
    ["Vitiation Tights +2"] = { item_id = 23268, model_id = 286 },
    ["Volte Gaiters"] = { item_id = 23726, model_id = 132 },
}

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
        if status == 'FAIL' then
            fail_count = fail_count + 1
        end
        handle:write(table.concat({ os.date('!%Y-%m-%dT%H:%M:%SZ'), slot, item, item_id, model_id, status }, '\t') .. '\n')
    end
    handle:close()
    chat('QA visual FAIL=' .. fail_count .. '; evidence=' .. qa_visual_path)
    return fail_count == 0
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
    chat('QA sets PASS=' .. counts.PASS .. ', FAIL=' .. counts.FAIL .. '; evidence=' .. qa_sets_path)
end

local function qa_status()
    chat('QA static: python3 tools/mochirii/gearswap_action_qa.py --repo-root .')
    chat('QA live sets: ' .. qa_sets_path)
    chat('QA live equipment: ' .. qa_equipment_path)
    chat('QA live visual models: ' .. qa_visual_path)
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
        left_ring="Defending Ring", right_ring="Moonlight Ring",
        back="Sucellos's Cape",
    }

    sets.idle.Refresh = set_combine(sets.idle, {
        main="Daybreak", sub="Ammurapi Shield",
        legs="Assiduity Pants +1", feet="Volte Gaiters",
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
        left_ring="Defending Ring", right_ring="Moonlight Ring",
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
    sets.precast.WS['Sanguine Blade'] = set_combine(sets.weapons.bunzi, {
        range=empty, ammo="Pemphredo Tathlum",
        head="Nyame Helm", body="Nyame Mail", hands="Nyame Gauntlets",
        legs="Nyame Flanchard", feet="Nyame Sollerets",
        neck="Baetyl Pendant", waist="Orpheus's Sash",
        left_ear="Friomisi Earring", right_ear="Malignance Earring",
        left_ring="Freke Ring", right_ring="Archon Ring",
        back="Sucellos's Cape",
    })
    sets.precast.WS['Seraph Blade'] = set_combine(sets.precast.WS['Sanguine Blade'], sets.weapons.daybreak)
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
        ['Weapon Skills'] = 'Nyame Path B core with Naegling/Maxentius/Bunzi swaps',
    }

    chat('Twills RDM/SCH GearSwap v12 loaded; role=' .. role_mode)
    equip_current()
end

function pretarget(spell)
end

function precast(spell)
    if spell.type == 'WeaponSkill' then
        equip(sets.precast.WS[spell.english] or sets.precast.WS)
    elseif spell.type == 'JobAbility' then
        equip(sets.precast.JA[spell.english] or sets.precast.JA)
    elseif spell.action_type == 'Magic' then
        equip(sets.precast.FC)
    end
end

function midcast(spell)
    if starts_with(spell.english, 'Cure') or starts_with(spell.english, 'Curaga') then
        equip(sets.midcast.Cure)
        if spell_matches_day_or_weather(spell) then
            equip(sets.utility.Obi)
        end
    elseif status_removal_spells[spell.english] then
        equip(sets.midcast.StatusRemoval)
    elseif starts_with(spell.english, 'Raise') or starts_with(spell.english, 'Reraise') then
        equip(sets.midcast.Raise)
    elseif skill_is(spell, 'Healing Magic', 'HealingMagic') then
        equip(sets.midcast.Cure)
    elseif skill_is(spell, 'Enhancing Magic', 'EnhancingMagic') then
        if starts_with(spell.english, 'Refresh') then
            equip(sets.midcast.Refresh)
        elseif starts_with(spell.english, 'Phalanx') then
            equip(sets.midcast.Phalanx)
        elseif spell.english == 'Stoneskin' then
            equip(sets.midcast.Stoneskin)
        elseif spell.english == 'Aquaveil' then
            equip(sets.midcast.Aquaveil)
        elseif is_barspell(spell) then
            equip(sets.midcast.Barspell)
        elseif is_enspell(spell) or enhancing_skill_spells[spell.english] then
            equip(sets.midcast.Enspell)
        elseif is_storm_spell(spell) then
            equip(sets.midcast.Storm)
        elseif duration_spells[spell.english] then
            equip(is_self_target(spell) and sets.midcast.EnhancingSelf or sets.midcast.EnhancingDuration)
        else
            equip(sets.midcast.EnhancingSkill)
        end
    elseif skill_is(spell, 'Enfeebling Magic', 'EnfeeblingMagic') then
        equip(enfeebling_set_for(spell))
    elseif skill_is(spell, 'Elemental Magic', 'ElementalMagic') then
        equip(nuke_set_for(spell))
        equip_waist_for_magic(spell)
    elseif skill_is(spell, 'Dark Magic', 'DarkMagic') then
        equip(sets.midcast.Dark)
        equip_waist_for_magic(spell)
    end
end

function aftercast()
    equip_current()
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
        chat('Commands: idle, healer, buffer, debuffer, caster, melee, cycle, dt, refresh, enf acc/mnd/int/potency, nuke free/burst, weapon daybreak/crocea/naegling/maxentius/bunzi/tauret, validate, qa all/status/snapshot/visual, status, gearscore, reset')
    end
end

function equip_current()
    if player and player.status == 'Engaged' and role_mode == 'melee' then
        equip(set_combine(sets.engaged, sets.weapons[weapon_mode] or sets.weapons.crocea))
        return
    end

    if role_mode == 'idle' then
        equip(idle_mode == 'refresh' and sets.idle.Refresh or sets.idle)
        return
    end

    equip(sets.role[role_mode] or sets.idle)
end
