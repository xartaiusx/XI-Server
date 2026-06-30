-- Mochirii Twills RDM/SCH profile.
-- Uses only gear verified in Twills' local inventory and wardrobes.

local role_mode = 'idle'
local enfeeble_mode = 'accuracy'
local nuke_mode = 'free'

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

local duration_spells = {
    ['Aquaveil'] = true,
    ['Blink'] = true,
    ['Flurry'] = true, ['Flurry II'] = true,
    ['Haste'] = true, ['Haste II'] = true,
    ['Protect'] = true, ['Protect II'] = true, ['Protect III'] = true,
    ['Protect IV'] = true, ['Protect V'] = true,
    ['Regen'] = true, ['Regen II'] = true,
    ['Shell'] = true, ['Shell II'] = true, ['Shell III'] = true,
    ['Shell IV'] = true, ['Shell V'] = true,
}

local enhancing_skill_spells = {
    ['Barfire'] = true, ['Barblizzard'] = true, ['Baraero'] = true,
    ['Barstone'] = true, ['Barthunder'] = true, ['Barwater'] = true,
    ['Barsleep'] = true, ['Barpoison'] = true, ['Barparalyze'] = true,
    ['Barblind'] = true, ['Barsilence'] = true, ['Barpetrify'] = true,
    ['Barvirus'] = true, ['Gain-STR'] = true, ['Gain-DEX'] = true,
    ['Gain-VIT'] = true, ['Gain-AGI'] = true, ['Gain-INT'] = true,
    ['Gain-MND'] = true, ['Gain-CHR'] = true,
    ['Temper'] = true, ['Temper II'] = true,
}

local status_removal_spells = {
    ['Erase'] = true, ['Poisona'] = true, ['Paralyna'] = true,
    ['Blindna'] = true, ['Silena'] = true, ['Cursna'] = true,
    ['Viruna'] = true, ['Stona'] = true,
}

local stratagems = {
    ['Penury'] = true, ['Celerity'] = true, ['Accession'] = true,
    ['Parsimony'] = true, ['Alacrity'] = true, ['Manifestation'] = true,
    ['Addendum: White'] = true, ['Addendum: Black'] = true,
    ['Light Arts'] = true, ['Dark Arts'] = true,
}

local function chat(message)
    add_to_chat(122, '[Twills] ' .. message)
end

local function starts_with(text, prefix)
    return text and text:sub(1, #prefix) == prefix
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

local function enfeebling_set_for(spell)
    if enfeeble_mode == 'mnd' or mnd_enfeebles[spell.english] then
        return sets.midcast.EnfeeblingMND
    elseif enfeeble_mode == 'int' or int_enfeebles[spell.english] then
        return sets.midcast.EnfeeblingINT
    end
    return sets.midcast.Enfeebling
end

local function nuke_set_for(spell)
    if spell and starts_with(spell.english, 'Impact') then
        return sets.midcast.Dark
    end
    return nuke_mode == 'burst' and sets.midcast.MagicBurst or sets.midcast.Nuke
end

function get_sets()
    sets = {}

    sets.idle = {
        main="Daybreak", sub="Ammurapi Shield", range=empty, ammo="Staunch Tathlum +1",
        head="Malignance Chapeau", body="Malignance Tabard", hands="Malignance Gloves",
        legs="Malignance Tights", feet="Malignance Boots",
        neck="Loricate Torque +1", waist="Carrier's Sash",
        left_ear="Etiolation Earring", right_ear="Malignance Earring",
        left_ring="Defending Ring", right_ring="Stikini Ring +1",
        back="Sucellos's Cape",
    }

    sets.idle.Refresh = set_combine(sets.idle, {
        main="Daybreak",
    })

    sets.engaged = {
        main="Crocea Mors", sub="Ammurapi Shield", range=empty, ammo="Coiste Bodhar",
        head="Malignance Chapeau", body="Malignance Tabard", hands="Malignance Gloves",
        legs="Malignance Tights", feet="Malignance Boots",
        neck="Anu Torque", waist="Sailfi Belt +1",
        left_ear="Telos Earring", right_ear="Sherida Earring",
        left_ring="Chirich Ring +1", right_ring="Chirich Ring +1",
        back="Sucellos's Cape",
    }

    sets.precast = {}
    sets.precast.FC = {
        main="Crocea Mors", sub="Ammurapi Shield", range=empty, ammo="Sapience Orb",
        head="Viti. Chapeau +3", body="Lethargy Sayon +2", hands="Aya. Manopolas +2",
        legs="Aya. Cosciales +2", feet="Carmine Greaves +1",
        neck="Dls. Torque +2", waist="Embla Sash",
        left_ear="Etiolation Earring", right_ear="Malignance Earring",
        left_ring="Kishar Ring", right_ring="Prolix Ring",
        back="Sucellos's Cape",
    }

    sets.precast.JA = set_combine(sets.idle, {})
    sets.precast.JA['Chainspell'] = set_combine(sets.precast.FC, { body="Atrophy Tabard +3" })
    sets.precast.JA['Composure'] = set_combine(sets.idle, {
        head="Leth. Chappel +2", body="Lethargy Sayon +2", hands="Leth. Ganth. +2",
        legs="Leth. Fuseau +2", feet="Leth. Houseaux +2",
    })
    sets.precast.JA['Convert'] = set_combine(sets.idle, {
        body="Viti. Tabard +2", legs="Viti. Tights +2", feet="Vitiation Boots +3",
    })
    sets.precast.JA['Saboteur'] = set_combine(sets.idle, {
        main="Crocea Mors", ammo="Regal Gem", head="Viti. Chapeau +3",
        body="Lethargy Sayon +2", hands="Leth. Ganth. +2", legs="Leth. Fuseau +2",
        feet="Vitiation Boots +3", neck="Dls. Torque +2", waist="Acuity Belt +1",
        left_ear="Digni. Earring", right_ear="Snotra Earring",
        left_ring="Stikini Ring +1", right_ring="Metamor. Ring +1",
    })
    sets.precast.JA['Stymie'] = set_combine(sets.precast.JA['Saboteur'], {})
    sets.precast.JA['Spontaneity'] = set_combine(sets.precast.FC, {})
    sets.precast.JA['Sublimation'] = set_combine(sets.idle.Refresh, {})
    for name in pairs(stratagems) do
        sets.precast.JA[name] = set_combine(sets.precast.FC, {})
    end

    sets.precast.WS = {
        main="Naegling", sub="Ammurapi Shield", range=empty, ammo="Regal Gem",
        head="Nyame Helm", body="Nyame Mail", hands="Nyame Gauntlets",
        legs="Nyame Flanchard", feet="Nyame Sollerets",
        neck="Fotia Gorget", waist="Fotia Belt",
        left_ear="Telos Earring", right_ear="Sherida Earring",
        left_ring="Epaminondas's Ring", right_ring="Sroda Ring",
        back="Sucellos's Cape",
    }
    sets.precast.WS['Savage Blade'] = sets.precast.WS
    sets.precast.WS['Black Halo'] = set_combine(sets.precast.WS, { main="Maxentius" })
    sets.precast.WS['Sanguine Blade'] = {
        main="Bunzi's Rod", sub="Ammurapi Shield", range=empty, ammo="Pemphredo Tathlum",
        head="Nyame Helm", body="Nyame Mail", hands="Nyame Gauntlets",
        legs="Nyame Flanchard", feet="Nyame Sollerets",
        neck="Baetyl Pendant", waist="Orpheus's Sash",
        left_ear="Friomisi Earring", right_ear="Malignance Earring",
        left_ring="Freke Ring", right_ring="Archon Ring",
        back="Sucellos's Cape",
    }

    sets.midcast = {}
    sets.midcast.Cure = {
        main="Daybreak", sub="Ammurapi Shield", range=empty, ammo="Staunch Tathlum +1",
        head="Kaykaus Mitra +1", body="Kaykaus Bliaut +1", hands="Kaykaus Cuffs +1",
        legs="Kaykaus Tights +1", feet="Kaykaus Boots +1",
        neck="Incanter's Torque", waist="Bishop's Sash",
        left_ear="Mendi. Earring", right_ear="Mimir Earring",
        left_ring="Sirona's Ring", right_ring="Metamor. Ring +1",
        back="Sucellos's Cape",
    }
    sets.midcast.StatusRemoval = set_combine(sets.midcast.Cure, {
        main="Daybreak", ammo="Staunch Tathlum +1",
    })

    sets.midcast.EnhancingSkill = {
        main="Crocea Mors", sub="Ammurapi Shield", range=empty, ammo="Staunch Tathlum +1",
        head="Telchine Cap", body="Telchine Chas.", hands="Atrophy Gloves +3",
        legs="Telchine Braconi", feet="Leth. Houseaux +2",
        neck="Incanter's Torque", waist="Olympus Sash",
        left_ear="Andoaa Earring", right_ear="Mimir Earring",
        left_ring="Stikini Ring +1", right_ring="Stikini Ring +1",
        back="Sucellos's Cape",
    }
    sets.midcast.Enhancing = sets.midcast.EnhancingSkill

    sets.midcast.EnhancingDuration = {
        main="Crocea Mors", sub="Ammurapi Shield", range=empty, ammo="Staunch Tathlum +1",
        head="Telchine Cap", body="Telchine Chas.", hands="Telchine Gloves",
        legs="Telchine Braconi", feet="Telchine Pigaches",
        neck="Dls. Torque +2", waist="Embla Sash",
        left_ear="Andoaa Earring", right_ear="Mimir Earring",
        left_ring="Stikini Ring +1", right_ring="Stikini Ring +1",
        back="Sucellos's Cape",
    }

    sets.midcast.EnhancingSelf = set_combine(sets.midcast.EnhancingDuration, {
        body="Lethargy Sayon +2", hands="Atrophy Gloves +3",
        legs="Leth. Fuseau +2", feet="Leth. Houseaux +2",
    })

    sets.midcast.Refresh = set_combine(sets.midcast.EnhancingDuration, {
        head="Leth. Chappel +2", body="Atrophy Tabard +3",
        hands="Atrophy Gloves +3", legs="Leth. Fuseau +2",
    })

    sets.midcast.Phalanx = set_combine(sets.midcast.EnhancingSkill, {
        main="Crocea Mors", body="Lethargy Sayon +2", hands="Atrophy Gloves +3",
        feet="Leth. Houseaux +2",
    })

    sets.midcast.Stoneskin = set_combine(sets.midcast.EnhancingSkill, {
        waist="Siegel Sash", legs="Shedir Seraweels",
    })

    sets.midcast.Enfeebling = {
        main="Crocea Mors", sub="Ammurapi Shield", range=empty, ammo="Regal Gem",
        head="Viti. Chapeau +3", body="Lethargy Sayon +2", hands="Leth. Ganth. +2",
        legs="Leth. Fuseau +2", feet="Vitiation Boots +3",
        neck="Dls. Torque +2", waist="Acuity Belt +1",
        left_ear="Digni. Earring", right_ear="Mimir Earring",
        left_ring="Stikini Ring +1", right_ring="Metamor. Ring +1",
        back="Sucellos's Cape",
    }
    sets.midcast.EnfeeblingMND = set_combine(sets.midcast.Enfeebling, {
        right_ear="Snotra Earring",
        left_ring="Stikini Ring +1", right_ring="Metamor. Ring +1",
    })
    sets.midcast.EnfeeblingINT = set_combine(sets.midcast.Enfeebling, {
        ammo="Pemphredo Tathlum", right_ear="Regal Earring",
        left_ring="Freke Ring", right_ring="Metamor. Ring +1",
    })

    sets.midcast.Nuke = {
        main="Crocea Mors", sub="Ammurapi Shield", range=empty, ammo="Pemphredo Tathlum",
        head="Amalric Coif +1", body="Amalric Doublet +1", hands="Amalric Gages +1",
        legs="Amalric Slops +1", feet="Amalric Nails +1",
        neck="Baetyl Pendant", waist="Acuity Belt +1",
        left_ear="Friomisi Earring", right_ear="Regal Earring",
        left_ring="Freke Ring", right_ring="Metamor. Ring +1",
        back="Sucellos's Cape",
    }
    sets.midcast.MagicBurst = {
        main="Crocea Mors", sub="Ammurapi Shield", range=empty, ammo="Pemphredo Tathlum",
        head="Ea Hat +1", body="Ea Houppe. +1", hands="Ea Cuffs +1",
        legs="Ea Slops +1", feet="Ea Pigaches +1",
        neck="Baetyl Pendant", waist="Hachirin-no-Obi",
        left_ear="Friomisi Earring", right_ear="Regal Earring",
        left_ring="Freke Ring", right_ring="Metamor. Ring +1",
        back="Sucellos's Cape",
    }
    sets.midcast.Dark = set_combine(sets.midcast.Nuke, {
        left_ring="Archon Ring", right_ring="Metamor. Ring +1",
    })

    sets.role = {
        idle = sets.idle.Refresh,
        healer = sets.midcast.Cure,
        buffer = sets.midcast.EnhancingDuration,
        debuffer = sets.midcast.Enfeebling,
        caster = sets.midcast.MagicBurst,
        melee = sets.engaged,
    }

    chat('Twills RDM/SCH GearSwap v9 loaded; role=' .. role_mode)
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
            equip({ waist="Hachirin-no-Obi" })
        end
    elseif skill_is(spell, 'Healing Magic', 'HealingMagic') then
        equip(status_removal_spells[spell.english] and sets.midcast.StatusRemoval or sets.midcast.Cure)
    elseif skill_is(spell, 'Enhancing Magic', 'EnhancingMagic') then
        if starts_with(spell.english, 'Refresh') then
            equip(sets.midcast.Refresh)
        elseif starts_with(spell.english, 'Phalanx') then
            equip(sets.midcast.Phalanx)
        elseif spell.english == 'Stoneskin' then
            equip(sets.midcast.Stoneskin)
        elseif enhancing_skill_spells[spell.english] or starts_with(spell.english, 'En') then
            equip(sets.midcast.EnhancingSkill)
        elseif duration_spells[spell.english] then
            equip(is_self_target(spell) and sets.midcast.EnhancingSelf or sets.midcast.EnhancingDuration)
        else
            equip(sets.midcast.EnhancingSkill)
        end
    elseif skill_is(spell, 'Enfeebling Magic', 'EnfeeblingMagic') then
        equip(enfeebling_set_for(spell))
    elseif skill_is(spell, 'Elemental Magic', 'ElementalMagic') then
        equip(nuke_set_for(spell))
        if spell_matches_day_or_weather(spell) then
            equip({ waist="Hachirin-no-Obi" })
        elseif (target_distance() or 99) <= 10 then
            equip({ waist="Orpheus's Sash" })
        end
    elseif skill_is(spell, 'Dark Magic', 'DarkMagic') then
        equip(sets.midcast.Dark)
        if spell_matches_day_or_weather(spell) then
            equip({ waist="Hachirin-no-Obi" })
        end
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

function self_command(command)
    command = command and command:lower() or ''

    if command == 'healer' or command == 'heal' then
        role_mode = 'healer'
    elseif command == 'buffer' or command == 'buff' then
        role_mode = 'buffer'
    elseif command == 'debuffer' or command == 'debuff' then
        role_mode = 'debuffer'
    elseif command == 'melee' or command == 'damage' then
        role_mode = 'melee'
    elseif command == 'caster' or command == 'nuker' then
        role_mode = 'caster'
    elseif command == 'cycle' then
        local order = { 'idle', 'healer', 'buffer', 'debuffer', 'caster', 'melee' }
        for index, value in ipairs(order) do
            if role_mode == value then
                role_mode = order[(index % #order) + 1]
                break
            end
        end
    elseif command == 'enf acc' or command == 'enf accuracy' then
        enfeeble_mode = 'accuracy'
        role_mode = 'debuffer'
    elseif command == 'enf mnd' then
        enfeeble_mode = 'mnd'
        role_mode = 'debuffer'
    elseif command == 'enf int' then
        enfeeble_mode = 'int'
        role_mode = 'debuffer'
    elseif command == 'nuke' then
        nuke_mode = nuke_mode == 'free' and 'burst' or 'free'
        role_mode = 'caster'
    elseif command == 'burst' then
        nuke_mode = 'burst'
        role_mode = 'caster'
    elseif command == 'free' then
        nuke_mode = 'free'
        role_mode = 'caster'
    elseif command == 'idle' or command == 'status' then
        role_mode = 'idle'
    else
        chat('Commands: idle, healer, buffer, debuffer, melee, caster, cycle, enf acc, enf mnd, enf int, nuke, burst, free')
        return
    end

    chat('Role=' .. role_mode .. ', Enfeeble=' .. enfeeble_mode .. ', Nuke=' .. nuke_mode)
    equip_current()
end

function equip_current()
    if role_mode == 'debuffer' then
        if enfeeble_mode == 'mnd' then
            equip(sets.midcast.EnfeeblingMND)
        elseif enfeeble_mode == 'int' then
            equip(sets.midcast.EnfeeblingINT)
        else
            equip(sets.midcast.Enfeebling)
        end
    elseif role_mode == 'caster' then
        equip(nuke_mode == 'burst' and sets.midcast.MagicBurst or sets.midcast.Nuke)
    else
        equip(sets.role[role_mode] or sets.idle.Refresh or sets.idle)
    end
end
