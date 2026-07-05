-- Mochirii Twills RDM/SCH profile.
-- Uses only gear verified in Twills' local inventory and wardrobes.

local role_mode = 'idle'
local idle_mode = 'dt'
local enfeeble_mode = 'accuracy'
local nuke_mode = 'free'
local weapon_mode = 'daybreak'

local mode_order = { 'idle', 'healer', 'buffer', 'debuffer', 'caster', 'melee' }

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

    chat('Twills RDM/SCH GearSwap v11 loaded; role=' .. role_mode)
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
        chat('Commands: idle, healer, buffer, debuffer, caster, melee, cycle, dt, refresh, enf acc/mnd/int/potency, nuke free/burst, weapon daybreak/crocea/naegling/maxentius/bunzi/tauret, validate, status, gearscore, reset')
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
