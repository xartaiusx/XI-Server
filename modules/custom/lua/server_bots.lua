-----------------------------------
-- Server-wide AI bots
-----------------------------------
require('modules/module_utils')
-----------------------------------

xi.server_bots = xi.server_bots or {}

local serverBots = xi.server_bots

serverBots.runtime = serverBots.runtime or {}
serverBots.runtime.activeByZone = serverBots.runtime.activeByZone or {}
serverBots.runtime.totalActive  = serverBots.runtime.totalActive or 0
serverBots.runtime.paused       = serverBots.runtime.paused or false
serverBots.runtime.llmEnabled   = serverBots.runtime.llmEnabled or false
serverBots.runtime.partySeq     = serverBots.runtime.partySeq or 0
serverBots.runtime.cache        = serverBots.runtime.cache or nil

local tickIntervalMs = 5000

local densityProfiles =
{
    light =
    {
        city     = 6,
        town     = 3,
        leveling = 4,
        travel   = 3,
    },
    moderate =
    {
        city     = 12,
        town     = 6,
        leveling = 8,
        travel   = 4,
    },
    dense =
    {
        city     = 20,
        town     = 10,
        leveling = 14,
        travel   = 8,
    },
}

local fallbackPersonas =
{
    ambient_adventurer =
    {
        cooldown = 60,
        llm = false,
        lines =
        {
            'I heard the outpost roads are safer lately.',
            'A full pack and a good map. That is how you start a journey.',
            'The best parties are the ones that remember to bring Signet.',
        },
    },
    crafter_market =
    {
        cooldown = 90,
        llm = false,
        lines =
        {
            'The guilds are busy today.',
            'Materials move quickly when adventurers are out leveling.',
            'Good tools save more gil than they cost.',
        },
    },
    traveling_adventurer =
    {
        cooldown = 60,
        llm = false,
        lines =
        {
            'I am checking the next zone line before dusk.',
            'Roads feel shorter when someone else is nearby.',
            'I should restock before the next leg.',
        },
    },
    leveling_vanguard =
    {
        cooldown = 45,
        llm = false,
        lines =
        {
            'I am looking for even matches nearby.',
            'Pull carefully. The links here can get ugly.',
            'I will check the camp and circle back.',
        },
    },
    leveling_healer =
    {
        cooldown = 45,
        llm = false,
        lines =
        {
            'I have cures ready if the camp gets busy.',
            'Rest before the next pull. It saves lives.',
            'A steady party beats a reckless one.',
        },
    },
}

local fallbackStrategies =
{
    ambient       = { layer = 'ambient', interval = 20 },
    travel        = { layer = 'movement', interval = 15 },
    social        = { layer = 'social', interval = 30 },
    grind         = { layer = 'combat', interval = 8 },
    party_assist  = { layer = 'party', interval = 5 },
    tank          = { layer = 'combat', interval = 6 },
    healer        = { layer = 'party', interval = 6 },
    support       = { layer = 'party', interval = 8 },
    ranged        = { layer = 'combat', interval = 8 },
    black_mage    = { layer = 'combat', interval = 10 },
    rest          = { layer = 'recovery', interval = 10 },
    vendor        = { layer = 'economy', interval = 60 },
    auction       = { layer = 'economy', interval = 300 },
    return_home   = { layer = 'recovery', interval = 15 },
    panic_disable = { layer = 'safety', interval = 1 },
}

local profileNamePools =
{
    ambient_town_adventurer =
    {
        'Aldreda',
        'Brunhild',
        'Diemoux',
        'Evrard',
        'Firmina',
        'Gavrie',
    },
    ambient_crafter =
    {
        'Borghest',
        'Eliane',
        'Fhalko',
        'Griselda',
        'Hildegard',
        'Irmela',
    },
    traveling_adventurer =
    {
        'Celenne',
        'Haurant',
        'Ilyssa',
        'Javert',
        'Kateline',
        'Lothaire',
    },
    market_supplier =
    {
        'Nimia',
        'Odelyn',
        'Perriane',
        'Quentin',
        'Raimbaut',
        'Sylvie',
    },
    leveling_vanguard =
    {
        'Darric',
        'Kaela',
        'Lorimar',
        'Mirelle',
        'Neric',
        'Orianne',
    },
    leveling_healer =
    {
        'Eloise',
        'Neriah',
        'Orlan',
        'Perrine',
        'Roselle',
        'Sibrecht',
    },
    leveling_ranger =
    {
        'Sibylle',
        'Tirion',
        'Ursanne',
        'Vachel',
        'Willem',
        'Yselte',
    },
    leveling_black_mage =
    {
        'Maudriel',
        'Noemie',
        'Olivier',
        'Pascal',
        'Roux',
        'Sabine',
    },
}

local fallbackProfiles =
{
    {
        key           = 'ambient_town_adventurer',
        displayName   = 'Aldreda',
        role          = 'ambient',
        mainJob       = 1,
        subJob        = 0,
        level         = 18,
        minLevel      = 1,
        maxLevel      = 99,
        look          = 2430,
        personaKey    = 'ambient_adventurer',
        strategyStack = { 'ambient', 'travel', 'social' },
        names         = { 'Aldreda', 'Brunhild', 'Carrion', 'Diemoux' },
    },
    {
        key           = 'ambient_crafter',
        displayName   = 'Borghest',
        role          = 'ambient',
        mainJob       = 9,
        subJob        = 0,
        level         = 30,
        minLevel      = 1,
        maxLevel      = 99,
        look          = 2431,
        personaKey    = 'crafter_market',
        strategyStack = { 'ambient', 'vendor', 'social' },
        canVendor     = true,
        names         = { 'Borghest', 'Eliane', 'Fhalko', 'Griselda' },
    },
    {
        key           = 'traveling_adventurer',
        displayName   = 'Celenne',
        role          = 'travel',
        mainJob       = 6,
        subJob        = 1,
        level         = 24,
        minLevel      = 10,
        maxLevel      = 99,
        look          = 2432,
        personaKey    = 'traveling_adventurer',
        strategyStack = { 'travel', 'ambient', 'social' },
        canParty      = true,
        names         = { 'Celenne', 'Haurant', 'Ilyssa', 'Javert' },
    },
    {
        key           = 'leveling_vanguard',
        displayName   = 'Darric',
        role          = 'fighter',
        mainJob       = 1,
        subJob        = 6,
        level         = 16,
        minLevel      = 1,
        maxLevel      = 75,
        look          = 2433,
        personaKey    = 'leveling_vanguard',
        strategyStack = { 'grind', 'party_assist', 'tank', 'rest', 'return_home', 'vendor' },
        canClaim      = true,
        canLoot       = true,
        canVendor     = true,
        canParty      = true,
        walletCeiling = 15000,
        names         = { 'Darric', 'Kaela', 'Lorimar', 'Mirelle' },
    },
    {
        key           = 'leveling_healer',
        displayName   = 'Eloise',
        role          = 'support',
        mainJob       = 3,
        subJob        = 4,
        level         = 16,
        minLevel      = 1,
        maxLevel      = 75,
        look          = 2434,
        personaKey    = 'leveling_healer',
        strategyStack = { 'grind', 'party_assist', 'healer', 'support', 'rest', 'return_home', 'vendor' },
        canClaim      = true,
        canLoot       = true,
        canVendor     = true,
        canParty      = true,
        walletCeiling = 12000,
        names         = { 'Eloise', 'Neriah', 'Orlan', 'Perrine' },
    },
}

local fallbackCityRules =
{
    [xi.zone.SOUTHERN_SAN_DORIA]     = { key = 'city_southern_sandoria', kind = 'city', x = -100, y = 1, z = -40, radius = 18, targetCount = 12, maxCount = 24, profileFilter = 'ambient' },
    [xi.zone.NORTHERN_SAN_DORIA]     = { key = 'city_northern_sandoria', kind = 'city', x = 39.4, y = -0.2, z = 25, radius = 18, targetCount = 12, maxCount = 24, profileFilter = 'ambient' },
    [xi.zone.PORT_SAN_DORIA]         = { key = 'city_port_sandoria', kind = 'city', x = -40, y = -2, z = 20, radius = 18, targetCount = 12, maxCount = 24, profileFilter = 'ambient' },
    [xi.zone.BASTOK_MINES]           = { key = 'city_bastok_mines', kind = 'city', x = 76.82, y = 0, z = -66.12, radius = 18, targetCount = 12, maxCount = 24, profileFilter = 'ambient' },
    [xi.zone.BASTOK_MARKETS]         = { key = 'city_bastok_markets', kind = 'city', x = -241.293, y = -2, z = 63.406, radius = 18, targetCount = 12, maxCount = 24, profileFilter = 'ambient' },
    [xi.zone.PORT_BASTOK]            = { key = 'city_port_bastok', kind = 'city', x = -80, y = 7, z = -30, radius = 18, targetCount = 12, maxCount = 24, profileFilter = 'ambient' },
    [xi.zone.WINDURST_WATERS]        = { key = 'city_windurst_waters', kind = 'city', x = 193, y = -12, z = 220, radius = 18, targetCount = 12, maxCount = 24, profileFilter = 'ambient' },
    [xi.zone.WINDURST_WALLS]         = { key = 'city_windurst_walls', kind = 'city', x = 0, y = -16.75, z = 130, radius = 18, targetCount = 12, maxCount = 24, profileFilter = 'ambient' },
    [xi.zone.PORT_WINDURST]          = { key = 'city_port_windurst', kind = 'city', x = 185.6, y = -12, z = 223.5, radius = 18, targetCount = 12, maxCount = 24, profileFilter = 'ambient' },
    [xi.zone.WINDURST_WOODS]         = { key = 'city_windurst_woods', kind = 'city', x = -20, y = -5, z = -120, radius = 18, targetCount = 12, maxCount = 24, profileFilter = 'ambient' },
    [xi.zone.RULUDE_GARDENS]         = { key = 'city_rulude_gardens', kind = 'city', x = 0, y = 0, z = 0, radius = 18, targetCount = 12, maxCount = 24, profileFilter = 'ambient' },
    [xi.zone.UPPER_JEUNO]            = { key = 'city_upper_jeuno', kind = 'city', x = 0, y = 0, z = 0, radius = 18, targetCount = 12, maxCount = 24, profileFilter = 'ambient' },
    [xi.zone.LOWER_JEUNO]            = { key = 'city_lower_jeuno', kind = 'city', x = 30, y = 0, z = -30, radius = 18, targetCount = 12, maxCount = 24, profileFilter = 'ambient' },
    [xi.zone.PORT_JEUNO]             = { key = 'city_port_jeuno', kind = 'city', x = 0, y = 0, z = 0, radius = 18, targetCount = 12, maxCount = 24, profileFilter = 'ambient' },
    [xi.zone.AHT_URHGAN_WHITEGATE]   = { key = 'city_whitegate', kind = 'city', x = 120, y = 1.5, z = 47, radius = 18, targetCount = 12, maxCount = 24, profileFilter = 'ambient' },
    [xi.zone.AL_ZAHBI]               = { key = 'city_al_zahbi', kind = 'city', x = 0, y = 0, z = 0, radius = 18, targetCount = 12, maxCount = 24, profileFilter = 'ambient' },
    [xi.zone.SELBINA]                = { key = 'town_selbina', kind = 'town', x = 14.67, y = -14.56, z = 66.69, radius = 12, targetCount = 6, maxCount = 12, profileFilter = 'ambient' },
    [xi.zone.MHAURA]                 = { key = 'town_mhaura', kind = 'town', x = 2.87, y = -4, z = 71.95, radius = 12, targetCount = 6, maxCount = 12, profileFilter = 'ambient' },
    [xi.zone.KAZHAM]                 = { key = 'town_kazham', kind = 'town', x = -80, y = -10, z = -20, radius = 12, targetCount = 6, maxCount = 12, profileFilter = 'ambient' },
    [xi.zone.NORG]                   = { key = 'town_norg', kind = 'town', x = 0, y = 0, z = 0, radius = 12, targetCount = 6, maxCount = 12, profileFilter = 'ambient' },
    [xi.zone.NASHMAU]                = { key = 'town_nashmau', kind = 'town', x = 0, y = 0, z = 0, radius = 12, targetCount = 6, maxCount = 12, profileFilter = 'ambient' },
    [xi.zone.RABAO]                  = { key = 'town_rabao', kind = 'town', x = 0, y = 0, z = 0, radius = 12, targetCount = 6, maxCount = 12, profileFilter = 'ambient' },
}

local fallbackLevelingZones =
{
    [xi.zone.WEST_RONFAURE] = true,
    [xi.zone.EAST_RONFAURE] = true,
    [xi.zone.LA_THEINE_PLATEAU] = true,
    [xi.zone.VALKURM_DUNES] = true,
    [xi.zone.JUGNER_FOREST] = true,
    [xi.zone.BATALLIA_DOWNS] = true,
    [xi.zone.NORTH_GUSTABERG] = true,
    [xi.zone.SOUTH_GUSTABERG] = true,
    [xi.zone.KONSCHTAT_HIGHLANDS] = true,
    [xi.zone.PASHHOW_MARSHLANDS] = true,
    [xi.zone.ROLANBERRY_FIELDS] = true,
    [xi.zone.BEAUCEDINE_GLACIER] = true,
    [xi.zone.XARCABARD] = true,
    [xi.zone.CAPE_TERIGGAN] = true,
    [xi.zone.EASTERN_ALTEPA_DESERT] = true,
    [xi.zone.WEST_SARUTABARUTA] = true,
    [xi.zone.EAST_SARUTABARUTA] = true,
    [xi.zone.TAHRONGI_CANYON] = true,
    [xi.zone.BUBURIMU_PENINSULA] = true,
    [xi.zone.MERIPHATAUD_MOUNTAINS] = true,
    [xi.zone.SAUROMUGUE_CHAMPAIGN] = true,
    [xi.zone.THE_SANCTUARY_OF_ZITAH] = true,
    [xi.zone.YUHTUNGA_JUNGLE] = true,
    [xi.zone.YHOATOR_JUNGLE] = true,
    [xi.zone.WESTERN_ALTEPA_DESERT] = true,
    [xi.zone.QUFIM_ISLAND] = true,
    [xi.zone.KING_RANPERRES_TOMB] = true,
    [xi.zone.DANGRUF_WADI] = true,
    [xi.zone.GHELSBA_OUTPOST] = true,
    [xi.zone.FORT_GHELSBA] = true,
    [xi.zone.YUGHOTT_GROTTO] = true,
    [xi.zone.PALBOROUGH_MINES] = true,
    [xi.zone.GIDDEUS] = true,
    [xi.zone.BEADEAUX] = true,
    [xi.zone.DAVOI] = true,
    [xi.zone.CASTLE_OZTROJA] = true,
    [xi.zone.ZERUHN_MINES] = true,
    [xi.zone.KORROLOKA_TUNNEL] = true,
    [xi.zone.CRAWLERS_NEST] = true,
    [xi.zone.GARLAIGE_CITADEL] = true,
    [xi.zone.GUSTAV_TUNNEL] = true,
    [xi.zone.LABYRINTH_OF_ONZOZO] = true,
}

local excludedZones =
{
    [xi.zone.UNKNOWN] = true,
    [xi.zone.GM_HOME] = true,
    [xi.zone.RESIDENTIAL_AREA] = true,
    [xi.zone.MORDION_GAOL] = true,
    [xi.zone.DYNAMIS_VALKURM] = true,
    [xi.zone.DYNAMIS_BUBURIMU] = true,
    [xi.zone.DYNAMIS_QUFIM] = true,
    [xi.zone.DYNAMIS_TAVNAZIA] = true,
    [xi.zone.DYNAMIS_BEAUCEDINE] = true,
    [xi.zone.DYNAMIS_XARCABARD] = true,
    [xi.zone.DYNAMIS_SAN_DORIA] = true,
    [xi.zone.DYNAMIS_BASTOK] = true,
    [xi.zone.DYNAMIS_WINDURST] = true,
    [xi.zone.DYNAMIS_JEUNO] = true,
    [xi.zone.TEMENOS] = true,
    [xi.zone.APOLLYON] = true,
}

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

local function now()
    return GetSystemTime()
end

local function split(value, separator)
    local rows = {}
    if value == nil or value == '' then
        return rows
    end

    separator = separator or ','
    for token in string.gmatch(value, string.format('([^%s]+)', separator)) do
        local trimmed = string.gsub(token, '^%s*(.-)%s*$', '%1')
        if trimmed ~= '' then
            table.insert(rows, trimmed)
        end
    end

    return rows
end

local function boolValue(value)
    return value == true or value == 1
end

local function tableCount(tbl)
    local count = 0
    for _, _ in pairs(tbl or {}) do
        count = count + 1
    end

    return count
end

local function zonePlayerCount(zone)
    local players = zone:getPlayers()
    local count   = 0

    for _, _ in pairs(players) do
        count = count + 1
    end

    return count
end

local function audit(action, zoneId, botKey, botName, details, severity, actorCharId, targetId)
    if serverBots.native ~= nil and serverBots.native.audit ~= nil then
        serverBots.native.audit(
            action,
            zoneId or 0,
            botKey or '',
            botName or '',
            details or '',
            severity or 'info',
            actorCharId or 0,
            targetId or 0
        )
    end
end

local function writeEconomy(bot, action, itemId, quantity, gilDelta, capability, status, details)
    if serverBots.native ~= nil and serverBots.native.writeEconomy ~= nil then
        serverBots.native.writeEconomy(
            bot and bot.botKey or '',
            action,
            itemId or 0,
            quantity or 0,
            gilDelta or 0,
            bot and bot.displayName or '',
            capability or 'none',
            status or 'queued',
            details or ''
        )
    end
end

local function writeInventory(bot, itemId, quantity, sourceAction, details)
    if serverBots.native ~= nil and serverBots.native.writeInventory ~= nil then
        serverBots.native.writeInventory(bot.botKey, itemId or 0, quantity or 0, sourceAction or 'unknown', details or '')
    end
end

local function writePerformance(zoneId, activeBots, combatBots, tickBudgetMs, tickElapsedMs, details)
    if serverBots.native ~= nil and serverBots.native.writePerformance ~= nil then
        serverBots.native.writePerformance(zoneId, activeBots, combatBots, tickBudgetMs, tickElapsedMs, tickElapsedMs > tickBudgetMs, details or '')
    end
end

local function writeChatMemory(bot, player, memoryType, content)
    if serverBots.native ~= nil and serverBots.native.writeChatMemory ~= nil then
        serverBots.native.writeChatMemory(
            bot.botKey,
            player and player:getID() or 0,
            player and player:getZoneID() or bot.zoneId,
            memoryType or 'interaction',
            content or '',
            86400
        )
    end
end

local function writePlayerOrder(player, bot, orderType, orderArgs, status)
    if serverBots.native ~= nil and serverBots.native.writePlayerOrder ~= nil then
        serverBots.native.writePlayerOrder(
            player:getID(),
            player:getName(),
            bot.botKey,
            orderType,
            orderArgs or '',
            status or 'queued',
            3600
        )
    end
end

local function touchState(bot, status)
    if
        serverBots.native == nil or
        serverBots.native.touchState == nil or
        bot == nil
    then
        return
    end

    local pos = bot.pos or { x = 0, y = 0, z = 0 }
    if bot.entity ~= nil then
        pcall(function()
            pos =
            {
                x = bot.entity:getXPos(),
                y = bot.entity:getYPos(),
                z = bot.entity:getZPos(),
            }
        end)
    end

    bot.pos = pos
    serverBots.native.touchState(
        bot.botKey,
        bot.profile.key,
        bot.zoneId or 0,
        bot.level or bot.profile.level or bot.profile.minLevel or 1,
        bot.profile.mainJob or 1,
        bot.profile.subJob or 0,
        pos.x,
        pos.y,
        pos.z,
        bot.exp or 0,
        bot.familiarity or 0,
        bot.wallet or 0,
        bot.profile.gearProfile or 'starter',
        bot.inventorySummary or '',
        bot.progressionState or '',
        bot.cooldownState or '',
        bot.roleState or 'idle',
        bot.strategyState or '',
        bot.targetMobId or 0,
        bot.ownerCharId or 0,
        bot.partyKey or '',
        status or bot.status or 'active'
    )
end

local function getConfig()
    local densityName = setting('SERVER_BOT_DENSITY', 'moderate')
    local density     = densityProfiles[densityName] or densityProfiles.moderate

    return
    {
        density          = density,
        globalCap        = setting('SERVER_BOT_GLOBAL_CAP', 350),
        zoneCap          = setting('SERVER_BOT_MAX_PER_ZONE', 24),
        idleDespawnMs    = setting('SERVER_BOT_IDLE_DESPAWN_SECONDS', 300) * 1000,
        fullSim          = settingEnabled('SERVER_BOT_FULL_SIM_ENABLED', true),
        visibleTag       = settingEnabled('SERVER_BOT_VISIBLE_AI_TAG', false),
        combatEnabled    = settingEnabled('SERVER_BOT_COMBAT_ENABLED', true),
        dynamicMobActors = settingEnabled('SERVER_BOT_DYNAMIC_MOB_ACTORS_ENABLED', false),
        economyEnabled   = settingEnabled('SERVER_BOT_ECONOMY_ENABLED', true),
        ahEnabled        = settingEnabled('SERVER_BOT_AH_ENABLED', false),
        llmEnabled       = settingEnabled('SERVER_BOT_LLM_CHAT_ENABLED', false) or serverBots.runtime.llmEnabled,
        playerCommands   = settingEnabled('SERVER_BOT_PLAYER_COMMANDS_ENABLED', false),
        autonomousParties = settingEnabled('SERVER_BOT_AUTONOMOUS_PARTIES_ENABLED', true),
        maxPartySize     = setting('SERVER_BOT_MAX_BOT_PARTY_SIZE', 6),
        partyInterval    = setting('SERVER_BOT_PARTY_FORMATION_INTERVAL_SECONDS', 60),
        maxPartiesPerZone = setting('SERVER_BOT_MAX_ACTIVE_PARTIES_PER_ZONE', 3),
        combatActorMode  = setting('SERVER_BOT_COMBAT_ACTOR_MODE', 'simulated_npc'),
        maxCombatPerZone = setting('SERVER_BOT_MAX_COMBAT_BOTS_PER_ZONE', 8),
        tickBudgetMs     = setting('SERVER_BOT_TICK_BUDGET_MS', 4),
    }
end

local function isEnabled()
    if not settingEnabled('ENABLE_SERVER_BOTS', true) then
        return false
    end

    local native = serverBots.native
    if
        native ~= nil and
        native.isRuntimeEnabled ~= nil and
        not native.isRuntimeEnabled()
    then
        return false
    end

    return true
end

local function nativeRows(name)
    if serverBots.native == nil or serverBots.native[name] == nil then
        return {}
    end

    local ok, rows = pcall(serverBots.native[name])
    if ok and rows ~= nil then
        return rows
    end

    audit('db_load_failed', 0, '', '', string.format('native.%s failed; using fallback bootstrap data.', name), 'warning')
    return {}
end

local function normalizePersona(row)
    return
    {
        key      = row.persona_key,
        style    = row.display_style,
        topics   = row.topic_tags,
        lines    = split(row.template_lines, '|'),
        llm      = boolValue(row.llm_enabled),
        cooldown = row.cooldown_seconds or 60,
    }
end

local function normalizeProfile(row)
    local stack = split(row.strategy_stack or row.behavior_profile or 'ambient', ',')
    if #stack == 0 then
        stack = { 'ambient' }
    end

    return
    {
        key                = row.profile_key,
        displayName        = row.display_name,
        role               = row.role,
        mainJob            = row.main_job or 1,
        subJob             = row.sub_job or 0,
        level              = row.min_level or 1,
        minLevel           = row.min_level or 1,
        maxLevel           = row.max_level or 99,
        look               = row.model_id or 2430,
        race               = row.race or 1,
        nation             = row.nation or 0,
        homeZoneId         = row.home_zone_id or 0,
        homeX              = row.home_x or 0,
        homeY              = row.home_y or 0,
        homeZ              = row.home_z or 0,
        behaviorProfile    = row.behavior_profile or 'ambient',
        gearProfile        = row.gear_profile or 'starter',
        personaKey         = row.persona_key or 'ambient_adventurer',
        strategyStack      = stack,
        routeKey           = row.route_key,
        campKey            = row.camp_key,
        mobGroupId         = row.mob_group_id or 1,
        mobGroupZoneId     = row.mob_group_zone_id or xi.zone.GM_HOME,
        canClaim           = boolValue(row.can_claim),
        canLoot            = boolValue(row.can_loot),
        canTrade           = boolValue(row.can_trade),
        canUseAuctionHouse = boolValue(row.can_use_auction_house),
        canVendor          = boolValue(row.can_vendor),
        canUpgradeGear     = boolValue(row.can_upgrade_gear),
        canParty           = boolValue(row.can_party),
        canLlmChat         = boolValue(row.can_llm_chat),
        commandable        = boolValue(row.commandable),
        walletFloor        = row.wallet_floor_gil or 0,
        walletCeiling      = row.wallet_ceiling_gil or 5000,
        notes              = row.notes or '',
    }
end

local function normalizeRule(row)
    return
    {
        key                 = row.rule_key,
        zoneId              = row.zone_id,
        zoneName            = row.zone_name,
        kind                = row.zone_kind,
        priority            = row.priority or 10,
        targetCount         = row.target_count,
        maxCount            = row.max_count,
        maxCombatCount      = row.max_combat_count or 0,
        x                   = row.anchor_x or 0,
        y                   = row.anchor_y or 0,
        z                   = row.anchor_z or 0,
        radius              = row.radius or 8,
        profileFilter       = row.profile_filter or 'any',
        minLevel            = row.min_level or 1,
        maxLevel            = row.max_level or 99,
        routeKey            = row.route_key,
        campKey             = row.camp_key,
        requiredPlayerCount = row.required_player_count or 1,
        allowCombat         = boolValue(row.allow_combat),
        allowEconomy        = boolValue(row.allow_economy),
    }
end

local function loadCache(force)
    if serverBots.runtime.cache ~= nil and not force then
        return serverBots.runtime.cache
    end

    local cache =
    {
        profiles = {},
        profilesByKey = {},
        personas = {},
        rulesByZone = {},
        routePointsByKey = {},
        campsByKey = {},
        campsByZone = {},
        strategies = {},
        commandPermissions = {},
        dbBacked = false,
    }

    for key, persona in pairs(fallbackPersonas) do
        cache.personas[key] = persona
    end

    for key, strategy in pairs(fallbackStrategies) do
        cache.strategies[key] = strategy
    end

    for _, row in ipairs(nativeRows('loadPersonas')) do
        cache.personas[row.persona_key] = normalizePersona(row)
        cache.dbBacked = true
    end

    local profileRows = nativeRows('loadProfiles')
    if #profileRows > 0 then
        cache.dbBacked = true
        for _, row in ipairs(profileRows) do
            local profile = normalizeProfile(row)
            table.insert(cache.profiles, profile)
            cache.profilesByKey[profile.key] = profile
        end
    else
        for _, profile in ipairs(fallbackProfiles) do
            table.insert(cache.profiles, profile)
            cache.profilesByKey[profile.key] = profile
        end
    end

    for _, row in ipairs(nativeRows('loadSpawnRules')) do
        local rule = normalizeRule(row)
        cache.rulesByZone[rule.zoneId] = cache.rulesByZone[rule.zoneId] or {}
        table.insert(cache.rulesByZone[rule.zoneId], rule)
        cache.dbBacked = true
    end

    for _, row in ipairs(nativeRows('loadRoutePoints')) do
        cache.routePointsByKey[row.route_key] = cache.routePointsByKey[row.route_key] or {}
        table.insert(cache.routePointsByKey[row.route_key], {
            x = row.x,
            y = row.y,
            z = row.z,
            wait = row.wait_ms or 3000,
            pointType = row.point_type or 'patrol',
        })
        cache.dbBacked = true
    end

    for _, row in ipairs(nativeRows('loadCamps')) do
        local camp =
        {
            key = row.camp_key,
            zoneId = row.zone_id,
            name = row.camp_name,
            minLevel = row.min_level,
            maxLevel = row.max_level,
            x = row.x,
            y = row.y,
            z = row.z,
            radius = row.radius,
            safeX = row.safe_x,
            safeY = row.safe_y,
            safeZ = row.safe_z,
            allowedFamilies = row.allowed_families,
            excludedMobNames = row.excluded_mob_names or '',
            maxBots = row.max_bots or 6,
        }

        cache.campsByKey[camp.key] = camp
        cache.campsByZone[camp.zoneId] = cache.campsByZone[camp.zoneId] or {}
        table.insert(cache.campsByZone[camp.zoneId], camp)
        cache.dbBacked = true
    end

    for _, row in ipairs(nativeRows('loadStrategies')) do
        cache.strategies[row.strategy_key] =
        {
            key = row.strategy_key,
            layer = row.layer,
            priority = row.priority,
            interval = row.tick_interval_seconds or 10,
            params = row.params or '',
        }
        cache.dbBacked = true
    end

    for _, row in ipairs(nativeRows('loadCommandPermissions')) do
        cache.commandPermissions[row.command_key] =
        {
            gm = row.min_gm_level or 0,
            player = boolValue(row.player_enabled),
            rateLimit = row.rate_limit_seconds or 3,
            enabled = boolValue(row.enabled),
        }
        cache.dbBacked = true
    end

    serverBots.runtime.cache = cache
    return cache
end

local function commandAllowed(player, commandKey, playerFacing)
    local cache = loadCache()
    local perm  = cache.commandPermissions[commandKey]
    if perm ~= nil then
        if not perm.enabled then
            return false
        end

        if playerFacing then
            return perm.player
        end

        return player:getGMLevel() >= perm.gm
    end

    if serverBots.native ~= nil and serverBots.native.commandAllowed ~= nil then
        return serverBots.native.commandAllowed(commandKey, player:getGMLevel(), playerFacing)
    end

    return playerFacing or player:getGMLevel() >= 1
end

local function getRule(zoneId, player)
    if excludedZones[zoneId] then
        return nil
    end

    local cache = loadCache()
    local rules = cache.rulesByZone[zoneId]
    if rules ~= nil and #rules > 0 then
        local rule = rules[1]
        local copy = {}
        for key, value in pairs(rule) do
            copy[key] = value
        end

        if
            copy.kind == 'leveling' and
            copy.x == 0 and
            copy.y == 0 and
            copy.z == 0 and
            player ~= nil
        then
            copy.x = player:getXPos()
            copy.y = player:getYPos()
            copy.z = player:getZPos()
        end

        return copy
    end

    local fallback = fallbackCityRules[zoneId]
    if fallback ~= nil then
        return fallback
    end

    if fallbackLevelingZones[zoneId] and player ~= nil then
        return
        {
            key = string.format('fallback_level_%u', zoneId),
            kind = 'leveling',
            x = player:getXPos(),
            y = player:getYPos(),
            z = player:getZPos(),
            radius = 10,
            targetCount = 8,
            maxCount = 24,
            maxCombatCount = 8,
            profileFilter = 'leveling',
            allowCombat = true,
            allowEconomy = true,
        }
    end

    return nil
end

local function profileMatches(profile, kind, filter)
    filter = filter or 'any'

    if filter ~= 'any' and filter ~= '' then
        if filter == 'ambient' then
            return profile.role == 'ambient' or profile.role == 'travel' or profile.role == 'merchant'
        elseif filter == 'leveling' then
            return profile.canClaim or profile.role == 'fighter' or profile.role == 'support' or profile.role == 'ranged' or profile.role == 'caster'
        elseif profile.key == filter or profile.role == filter then
            return true
        end
    end

    if kind == 'leveling' then
        return profile.canClaim or profile.canParty or profile.role == 'fighter' or profile.role == 'support'
    end

    return profile.role == 'ambient' or profile.role == 'travel' or profile.role == 'merchant'
end

local function chooseProfile(kind, profileKey, index, rule)
    local cache = loadCache()
    local requested = cache.profilesByKey[profileKey or '']
    if requested ~= nil then
        return requested
    end

    local pool = {}
    for _, profile in ipairs(cache.profiles) do
        if profileMatches(profile, kind, rule and rule.profileFilter or 'any') then
            table.insert(pool, profile)
        end
    end

    if #pool == 0 then
        pool = cache.profiles
    end

    return pool[((index - 1) % #pool) + 1]
end

local function botDisplayName(profile, index, config)
    local name = profile.displayName
    local names = profile.names or profileNamePools[profile.key]
    if names ~= nil and #names > 0 then
        name = names[((index - 1) % #names) + 1]
    end

    if config.visibleTag then
        return string.format('[AI] %s', name)
    end

    return name
end

local function resolveCamp(rule, profile)
    local cache = loadCache()
    local campKey = profile.campKey
    if campKey == nil or campKey == '' then
        campKey = rule.campKey
    end

    if campKey ~= nil and campKey ~= '' then
        return cache.campsByKey[campKey]
    end

    local camps = cache.campsByZone[rule.zoneId]
    if camps ~= nil and #camps > 0 then
        return camps[1]
    end

    return nil
end

local function botPosition(rule, profile, index)
    local camp   = resolveCamp(rule, profile)
    local anchor = camp or rule
    local spread = anchor.radius or rule.radius or 8
    local side   = (index % 2 == 0) and 1 or -1
    local step   = math.floor((index - 1) / 2) + 1

    return
    {
        x        = anchor.x + (side * math.min(step * 2.5, spread)),
        y        = anchor.y,
        z        = anchor.z + (((index % 3) - 1) * 2.5),
        rotation = (index * 37) % 255,
    }
end

local function patrolFor(pos, rule, profile, index)
    local cache = loadCache()
    local routeKey = profile.routeKey
    if routeKey == nil or routeKey == '' then
        routeKey = rule.routeKey
    end

    if
        routeKey ~= nil and
        routeKey ~= '' and
        cache.routePointsByKey[routeKey] ~= nil
    then
        return cache.routePointsByKey[routeKey]
    end

    local radius = math.min(rule.radius or 8, 12)
    local side   = (index % 2 == 0) and 1 or -1

    return
    {
        { x = pos.x, y = pos.y, z = pos.z, wait = 3000 },
        { x = pos.x + side * radius * 0.45, y = pos.y, z = pos.z + radius * 0.25, wait = 3000 },
        { x = pos.x - side * radius * 0.25, y = pos.y, z = pos.z - radius * 0.35, wait = 3000 },
    }
end

local function ready(bot, key, seconds)
    local expires = bot.cooldowns[key]
    if expires ~= nil and expires > now() then
        return false
    end

    bot.cooldowns[key] = now() + seconds
    return true
end

local function isCombatProfile(profile)
    return profile.canClaim or profile.role == 'fighter' or profile.role == 'support' or profile.role == 'ranged' or profile.role == 'caster'
end

local function shouldUseCombatActor(profile, rule, config, active)
    if
        not config.fullSim or
        not config.combatEnabled or
        not config.dynamicMobActors or
        config.combatActorMode ~= 'safe_cpp_bridge' or
        not rule.allowCombat
    then
        return false
    end

    if not isCombatProfile(profile) then
        return false
    end

    local ruleCap = rule.maxCombatCount or config.maxCombatPerZone
    local cap = math.min(config.maxCombatPerZone, ruleCap)
    return (active.combatBots or 0) < cap
end

local function botCanAutonomousParty(bot)
    return
        bot ~= nil and
        bot.profile ~= nil and
        bot.profile.canParty and
        bot.status ~= 'dead' and
        bot.status ~= 'despawned'
end

local function activePartyCount(active)
    local count = 0
    if active.parties == nil then
        return count
    end

    for _, party in pairs(active.parties) do
        if party.status == 'active' then
            count = count + 1
        end
    end

    return count
end

local function setBotPartyState(bot, partyKey, roleState, size)
    bot.partyKey = partyKey
    bot.roleState = roleState
    bot.strategyState = string.format('party=%s;size=%u;mode=autonomous', partyKey or 'solo', size or 1)
    touchState(bot, bot.status or 'active')
end

local function disbandSmallParties(active)
    if active.parties == nil then
        return
    end

    for partyKey, party in pairs(active.parties) do
        local remaining = {}
        for _, botKey in ipairs(party.members or {}) do
            local bot = active.bots[botKey]
            if botCanAutonomousParty(bot) and bot.partyKey == partyKey then
                table.insert(remaining, botKey)
            end
        end

        if #remaining < 2 then
            for _, botKey in ipairs(remaining) do
                local bot = active.bots[botKey]
                if bot ~= nil then
                    setBotPartyState(bot, nil, 'solo_adventuring', 1)
                end
            end

            party.status = 'disbanded'
            audit('party_disband', active.zoneId or 0, partyKey, '', 'Autonomous bot party disbanded because fewer than two members remained.')
        else
            party.members = remaining
        end
    end
end

local function formAutonomousParties(active, config)
    if
        not config.autonomousParties or
        not active.rule.allowCombat
    then
        return
    end

    disbandSmallParties(active)

    local currentTime = now()
    if
        active.nextPartyFormation ~= nil and
        active.nextPartyFormation > currentTime
    then
        return
    end

    active.nextPartyFormation = currentTime + math.max(config.partyInterval or 60, 15)
    active.parties = active.parties or {}

    if activePartyCount(active) >= (config.maxPartiesPerZone or 3) then
        return
    end

    local candidates = {}
    for _, bot in pairs(active.bots) do
        if
            botCanAutonomousParty(bot) and
            (bot.partyKey == nil or bot.partyKey == '')
        then
            table.insert(candidates, bot)
        end
    end

    table.sort(candidates, function(a, b)
        return a.botKey < b.botKey
    end)

    local index = 1
    while
        index <= #candidates and
        activePartyCount(active) < (config.maxPartiesPerZone or 3)
    do
        local size = math.min(config.maxPartySize or 6, #candidates - index + 1)
        if size < 2 then
            local solo = candidates[index]
            if solo ~= nil then
                setBotPartyState(solo, nil, 'solo_adventuring', 1)
            end

            break
        end

        serverBots.runtime.partySeq = serverBots.runtime.partySeq + 1
        local partyKey = string.format('server_bot_party_%u_%03u', active.zoneId or 0, serverBots.runtime.partySeq)
        local members = {}

        for offset = 0, size - 1 do
            local bot = candidates[index + offset]
            table.insert(members, bot.botKey)
            setBotPartyState(bot, partyKey, 'party_adventuring', size)
        end

        active.parties[partyKey] =
        {
            key = partyKey,
            status = 'active',
            members = members,
            createdAt = currentTime,
        }

        audit('party_form', active.zoneId or 0, partyKey, '', string.format('Autonomous bot party formed with %u members.', size))
        index = index + size
    end
end

local function despawnEntity(bot)
    if bot.entity == nil then
        return
    end

    local ok = false
    if bot.actorType == 'mob' and DespawnMob ~= nil then
        ok = pcall(function()
            DespawnMob(bot.entity:getID(), bot.entity:getZone())
        end)
    end

    if not ok then
        pcall(function()
            bot.entity:setStatus(xi.status.DISAPPEAR)
        end)
    end
end

local function findBotByEntity(entity)
    local zoneId = entity:getZoneID()
    local active = serverBots.runtime.activeByZone[zoneId]
    if active == nil then
        return nil
    end

    local localKey = entity:getLocalVar('[ServerBot]LocalKey')
    for _, bot in pairs(active.bots) do
        if bot.localKey == localKey then
            return bot
        end
    end

    return nil
end

local function onBotDeath(mob)
    local bot = findBotByEntity(mob)
    if bot == nil then
        return
    end

    bot.status = 'dead'
    bot.roleState = 'dead'
    bot.targetMobId = 0
    touchState(bot, 'dead')
    audit('death', bot.zoneId, bot.botKey, bot.displayName, 'Bot actor died and will return home on a later tick.', 'warning')
end

local function spawnActor(zone, actorType, botKey, displayName, profile, pos, level, onTrigger)
    if actorType == 'mob' then
        local mob = zone:insertDynamicEntity({
            objtype              = xi.objType.MOB,
            allegiance           = xi.allegiance.PLAYER,
            name                 = botKey,
            packetName           = displayName,
            look                 = profile.look,
            x                    = pos.x,
            y                    = pos.y,
            z                    = pos.z,
            rotation             = pos.rotation,
            groupId              = profile.mobGroupId or 1,
            groupZoneId          = profile.mobGroupZoneId or xi.zone.GM_HOME,
            minLevel             = level,
            maxLevel             = level,
            releaseIdOnDisappear = true,
            specialSpawnAnimation = true,
            onMobDeath           = function(mobArg)
                onBotDeath(mobArg)
            end,
        })

        if mob == nil then
            return nil
        end

        mob:setSpawn(pos.x, pos.y, pos.z, pos.rotation)
        mob:setMobMod(xi.mobMod.NO_DROPS, 1)
        mob:setRoamFlags(xi.roamFlag.SCRIPTED)
        mob:spawn()

        if DisallowRespawn ~= nil then
            DisallowRespawn(mob:getID(), true)
        end

        mob:setBaseSpeed(22)
        mob:setAllegiance(1)
        mob:setMagicCastingEnabled(false)
        mob:setMobAbilityEnabled(false)

        return mob
    end

    local npc = zone:insertDynamicEntity({
        objtype    = xi.objType.NPC,
        name       = botKey,
        packetName = displayName,
        look       = profile.look,
        x          = pos.x,
        y          = pos.y,
        z          = pos.z,
        rotation   = pos.rotation,
        widescan   = 0,
        releaseIdOnDisappear = true,
        onTrigger  = onTrigger,
    })

    if npc ~= nil then
        npc:initNpcAi()
    end

    return npc
end

local function chooseBotLevel(profile, rule)
    local camp = resolveCamp(rule, profile)
    local minLevel = camp and camp.minLevel or rule.minLevel or profile.minLevel or 1
    local maxLevel = camp and camp.maxLevel or rule.maxLevel or profile.maxLevel or minLevel

    minLevel = math.max(minLevel, profile.minLevel or 1)
    maxLevel = math.min(maxLevel, profile.maxLevel or maxLevel)

    if maxLevel < minLevel then
        maxLevel = minLevel
    end

    return minLevel + ((maxLevel - minLevel) > 0 and math.floor((maxLevel - minLevel) / 2) or 0)
end

local function onTriggerBot(player, npc)
    local bot = findBotByEntity(npc)
    local line = 'Safe travels.'

    if bot ~= nil then
        local cache = loadCache()
        local persona = cache.personas[bot.profile.personaKey] or fallbackPersonas.ambient_adventurer
        if persona ~= nil and persona.lines ~= nil and #persona.lines > 0 then
            line = persona.lines[((bot.talkIndex or 0) % #persona.lines) + 1]
        end

        bot.talkIndex = (bot.talkIndex or 0) + 1
        audit('talk', player:getZoneID(), bot.botKey, bot.displayName, line, 'info', player:getID())
        writeChatMemory(bot, player, 'talk', line)

        local config = getConfig()
        if config.llmEnabled and bot.profile.canLlmChat then
            audit('llm_fallback', player:getZoneID(), bot.botKey, bot.displayName, 'LLM chat is enabled but no provider bridge is configured; template line used.', 'warning', player:getID())
        end
    end

    player:printToPlayer(line, xi.msg.channel.SAY, npc:getPacketName())
end

local function findCombatTarget(bot, zone)
    local camp = resolveCamp(bot.rule, bot.profile)
    local maxDistance = (camp and camp.radius) or math.max(bot.rule.radius or 10, 30)
    local excluded = camp and camp.excludedMobNames or ''

    for _, mob in pairs(zone:getMobs()) do
        local ok, valid = pcall(function()
            if mob:getLocalVar('[ServerBot]LocalKey') ~= 0 then
                return false
            end

            if not mob:isSpawned() or not mob:isAlive() or mob:isEngaged() then
                return false
            end

            if mob:getAllegiance() ~= xi.allegiance.MOB then
                return false
            end

            if
                excluded ~= '' and
                string.find(excluded, mob:getName(), 1, true) ~= nil
            then
                return false
            end

            local level = mob:getMainLvl()
            local botLevel = bot.level or bot.profile.minLevel or 1
            if level > botLevel + 3 or level < math.max(botLevel - 10, 1) then
                return false
            end

            return bot.entity:checkDistance(mob) <= maxDistance
        end)

        if ok and valid then
            return mob
        end
    end

    return nil
end

local function engageTarget(bot, target, source)
    if bot.actorType ~= 'mob' or bot.entity == nil or target == nil then
        return false, 'Bot is not a combat actor.'
    end

    local ok, message = pcall(function()
        if not target:isAlive() or not target:isSpawned() then
            return false, 'Target is not available.'
        end

        if target:getAllegiance() ~= xi.allegiance.MOB then
            return false, 'Target is not a mob enemy.'
        end

        if target:isEngaged() and not bot.entity:hasClaim(target) then
            return false, 'Target is already engaged.'
        end

        target:updateEnmity(bot.entity)
        bot.entity:updateEnmity(target)
        target:addEnmity(bot.entity, 1, 60)
        bot.entity:addEnmity(target, 1, 60)
        bot.targetMobId = target:getID()
        bot.status = 'fighting'
        bot.roleState = source or 'grind'
        touchState(bot, 'fighting')
        audit('claim', bot.zoneId, bot.botKey, bot.displayName, string.format('Engaged target %s (%u) via %s.', target:getName(), target:getID(), source or 'grind'), 'info', bot.ownerCharId or 0, target:getID())

        return true, 'Engaged target.'
    end)

    if not ok then
        audit('combat_error', bot.zoneId, bot.botKey, bot.displayName, tostring(message), 'error')
        return false, tostring(message)
    end

    return message
end

local function simulateProgression(bot, config)
    if
        not config.economyEnabled or
        not bot.profile.canLoot or
        not ready(bot, 'simulated_loot', 90)
    then
        return
    end

    local level = bot.level or bot.profile.minLevel or 1
    local xp = math.max(level * 8, 20)
    local gil = math.max(math.floor(level * 7), 5)
    bot.exp = (bot.exp or 0) + xp
    bot.wallet = math.min((bot.wallet or bot.profile.walletFloor or 0) + gil, bot.profile.walletCeiling or 5000)
    bot.familiarity = math.min((bot.familiarity or 0) + 1, 10000)

    if bot.exp >= level * 150 and level < (bot.profile.maxLevel or 75) then
        bot.exp = bot.exp - (level * 150)
        bot.level = level + 1
        audit('level_up', bot.zoneId, bot.botKey, bot.displayName, string.format('Bot reached level %u.', bot.level))
    end

    writeEconomy(bot, 'loot', 0, 0, gil, 'loot', 'applied', string.format('Simulated adventuring reward xp=%u gil=%u.', xp, gil))
    writeInventory(bot, 0, 1, 'loot', 'Simulated inventory summary increment; no player item created.')
    touchState(bot, bot.status or 'active')
end

local function executeOrder(bot, order, config)
    if order == nil then
        return
    end

    local owner = GetPlayerByID ~= nil and GetPlayerByID(bot.ownerCharId or 0) or nil
    if owner == nil then
        return
    end

    if order == 'follow' then
        if bot.entity ~= nil and xi.followType ~= nil then
            pcall(function()
                bot.entity:follow(owner, xi.followType.ROAM)
            end)
        end

        bot.roleState = 'following'
        touchState(bot, 'following')
    elseif order == 'attack' and config.combatEnabled then
        if bot.actorType ~= 'mob' then
            audit('command_attack_deferred', bot.zoneId, bot.botKey, bot.displayName, 'Attack order requires dynamic MOB actors; SERVER_BOT_DYNAMIC_MOB_ACTORS_ENABLED is false.', 'warning', bot.ownerCharId or 0)
            return
        end

        local target = owner:getCursorTarget() or owner:getTarget()
        if target ~= nil then
            engageTarget(bot, target, 'party_assist')
        end
    elseif order == 'rest' then
        if bot.entity ~= nil then
            pcall(function()
                bot.entity:disengage()
            end)
        end

        bot.roleState = 'resting'
        bot.status = 'resting'
        touchState(bot, 'resting')
    end
end

local function executeStrategy(bot, strategyKey, active, config)
    local cache = loadCache()
    local strategy = cache.strategies[strategyKey] or fallbackStrategies[strategyKey]
    local interval = strategy and strategy.interval or 10

    if not ready(bot, 'strategy_' .. strategyKey, interval) then
        return
    end

    if strategyKey == 'panic_disable' and not isEnabled() then
        bot.status = 'panic'
        touchState(bot, 'panic')
        return
    elseif strategyKey == 'party_assist' then
        if bot.partyKey ~= nil and bot.partyKey ~= '' then
            if ready(bot, 'party_assist_audit', 120) then
                audit('party_assist', bot.zoneId, bot.botKey, bot.displayName, string.format('Bot-only party coordination active: %s.', bot.partyKey), 'debug')
            end
        end
    elseif strategyKey == 'grind' then
        if
            config.combatEnabled and
            active.rule.allowCombat
        then
            if bot.actorType == 'mob' then
                local zone = bot.entity and bot.entity:getZone() or nil
                local target = zone and findCombatTarget(bot, zone) or nil
                if target ~= nil then
                    engageTarget(bot, target, 'grind')
                elseif ready(bot, 'combat_scan_empty', 45) then
                    audit('combat_scan', bot.zoneId, bot.botKey, bot.displayName, 'No safe unengaged target found near camp.', 'debug')
                end
            elseif ready(bot, 'combat_deferred', 120) then
                bot.status = 'active'
                bot.roleState = bot.partyKey and 'party_adventuring' or 'solo_adventuring'
                bot.strategyState = string.format('party=%s;mode=simulated_npc_combat', bot.partyKey or 'solo')
                touchState(bot, 'active')
                audit('combat_deferred', bot.zoneId, bot.botKey, bot.displayName, 'Dynamic MOB actors disabled; bot remains a safe adventuring NPC until C++ combat bridge is verified.', 'warning')
            end
        end
    elseif strategyKey == 'rest' then
        if bot.actorType ~= 'mob' then
            return
        end

        local shouldRest = false
        if bot.entity ~= nil then
            pcall(function()
                shouldRest = bot.entity:getHPP() < 45
            end)
        end

        if shouldRest then
            bot.status = 'resting'
            bot.roleState = 'resting'
            pcall(function()
                bot.entity:disengage()
            end)

            touchState(bot, 'resting')
            audit('rest', bot.zoneId, bot.botKey, bot.displayName, 'Bot entered recovery behavior.')
        end
    elseif strategyKey == 'return_home' and bot.status == 'dead' then
        if ready(bot, 'return_home', 30) then
            bot.status = 'return_home'
            bot.roleState = 'return_home'
            touchState(bot, 'return_home')
            audit('return_home', bot.zoneId, bot.botKey, bot.displayName, 'Dead bot marked for home return; despawning actor.')
            despawnEntity(bot)
        end
    elseif
        strategyKey == 'vendor' and
        config.economyEnabled and
        bot.profile.canVendor
    then
        if ready(bot, 'vendor', 300) then
            writeEconomy(bot, 'vendor', 0, 0, 0, 'vendor', 'applied', 'Bot checked vendor shopping/upgrades ledger.')
            audit('vendor', bot.zoneId, bot.botKey, bot.displayName, 'Vendor behavior tick recorded.')
        end
    elseif strategyKey == 'auction' and bot.profile.canUseAuctionHouse then
        if config.ahEnabled then
            writeEconomy(bot, 'auction', 0, 0, 0, 'auction', 'queued', 'AH integration is enabled; listing queued for verified implementation.')
            audit('auction', bot.zoneId, bot.botKey, bot.displayName, 'Auction behavior queued in ledger.')
        else
            writeEconomy(bot, 'auction', 0, 0, 0, 'auction', 'skipped', 'SERVER_BOT_AH_ENABLED is false.')
        end
    elseif strategyKey == 'ambient' or strategyKey == 'travel' then
        if ready(bot, 'ambient_audit', 120) then
            audit('ambient_tick', bot.zoneId, bot.botKey, bot.displayName, string.format('strategy=%s state=%s', strategyKey, bot.roleState or 'idle'), 'debug')
        end
    end
end

local function scheduleZoneTick(zoneId)
    local active = serverBots.runtime.activeByZone[zoneId]
    if active == nil or active.tickScheduled then
        return
    end

    local anchor = nil
    for _, bot in pairs(active.bots) do
        if bot.entity ~= nil then
            anchor = bot.entity
            break
        end
    end

    if anchor == nil then
        return
    end

    active.tickScheduled = true
    anchor:timer(tickIntervalMs, function()
        local current = serverBots.runtime.activeByZone[zoneId]
        if current == nil then
            return
        end

        current.tickScheduled = false
        serverBots.tickZone(zoneId)
    end)
end

local function scheduleIdleCheck(zoneId, botKey, bot)
    local config = getConfig()
    bot.entity:timer(config.idleDespawnMs, function(entity)
        local active = serverBots.runtime.activeByZone[zoneId]
        if active == nil then
            return
        end

        local zone = entity:getZone()
        if zone == nil then
            return
        end

        if zonePlayerCount(zone) == 0 then
            despawnEntity(bot)
            active.bots[botKey] = nil
            serverBots.runtime.totalActive = math.max(serverBots.runtime.totalActive - 1, 0)
            touchState(bot, 'despawned')
            audit('despawn_idle', zoneId, botKey, bot.displayName, 'Zone has no players.')

            if tableCount(active.bots) == 0 then
                serverBots.runtime.activeByZone[zoneId] = nil
            end

            return
        end

        scheduleIdleCheck(zoneId, botKey, bot)
    end)
end

function serverBots.tickZone(zoneId)
    local active = serverBots.runtime.activeByZone[zoneId]
    if active == nil then
        return
    end

    local config = getConfig()
    local ticked = 0
    local combatBots = 0

    if not serverBots.runtime.paused and isEnabled() then
        formAutonomousParties(active, config)

        for _, bot in pairs(active.bots) do
            if bot.actorType == 'mob' then
                combatBots = combatBots + 1
            end

            for _, strategyKey in ipairs(bot.profile.strategyStack or { 'ambient' }) do
                executeStrategy(bot, strategyKey, active, config)
            end

            if
                bot.status == 'fighting' or
                (
                    active.rule.allowCombat and
                    (
                        bot.roleState == 'adventuring' or
                        bot.roleState == 'solo_adventuring' or
                        bot.roleState == 'party_adventuring'
                    )
                )
            then
                simulateProgression(bot, config)
            end

            if ready(bot, 'state_heartbeat', 60) then
                touchState(bot, bot.status or 'active')
            end

            ticked = ticked + 1
            if ticked >= math.max(config.tickBudgetMs, 1) * 12 then
                audit('tick_budget_soft_stop', zoneId, '', '', 'Stopped bot strategy loop early for tick budget safety.', 'warning')
                break
            end
        end
    end

    writePerformance(zoneId, tableCount(active.bots), combatBots, config.tickBudgetMs, 0, string.format('processed=%u paused=%s', ticked, tostring(serverBots.runtime.paused)))
    scheduleZoneTick(zoneId)
end

function serverBots.spawnZone(zone, player, profileKey, requestedCount)
    if not isEnabled() or zone == nil or player == nil then
        return 0, 'Server bots are disabled or no zone is available.'
    end

    if serverBots.runtime.paused then
        return 0, 'Server bots are paused.'
    end

    local zoneId = zone:getID()
    local rule   = getRule(zoneId, player)
    if rule == nil then
        return 0, 'This zone is not eligible for server bots.'
    end

    rule.zoneId = zoneId

    local active = serverBots.runtime.activeByZone[zoneId]
    if active ~= nil and tableCount(active.bots) > 0 then
        return tableCount(active.bots), 'Server bots are already active in this zone.'
    end

    local config      = getConfig()
    local targetCount = requestedCount or rule.targetCount or config.density[rule.kind] or config.density.leveling
    targetCount       = math.max(1, math.floor(targetCount))
    targetCount       = math.min(targetCount, config.zoneCap, rule.maxCount or config.zoneCap)

    local remainingGlobal = config.globalCap - serverBots.runtime.totalActive
    if remainingGlobal <= 0 then
        return 0, 'Global server bot cap has been reached.'
    end

    targetCount = math.min(targetCount, remainingGlobal)
    active =
    {
        zoneId = zoneId,
        kind = rule.kind,
        rule = rule,
        bots = {},
        parties = {},
        combatBots = 0,
        tickScheduled = false,
        nextPartyFormation = 0,
    }

    serverBots.runtime.activeByZone[zoneId] = active
    local profileCounts = {}

    for i = 1, targetCount do
        local profile     = chooseProfile(rule.kind, profileKey, i, rule)
        local pos         = botPosition(rule, profile, i)
        profileCounts[profile.key] = (profileCounts[profile.key] or 0) + 1

        local displayName = botDisplayName(profile, profileCounts[profile.key], config)
        local actorType   = shouldUseCombatActor(profile, rule, config, active) and 'mob' or 'npc'
        local botLevel    = chooseBotLevel(profile, rule)
        local localKey    = i
        local botKey      = string.format('server_bot_%u_%02u_%s', zoneId, i, profile.key)
        local roleState   = 'ambient'

        if actorType == 'mob' or (rule.allowCombat and isCombatProfile(profile)) then
            roleState = 'adventuring'
        end

        local entity = spawnActor(zone, actorType, botKey, displayName, profile, pos, botLevel, onTriggerBot)

        if entity ~= nil then
            entity:setLocalVar('[ServerBot]LocalKey', localKey)

            local pathNodes = patrolFor(pos, rule, profile, i)
            entity:setPos(xi.path.first(pathNodes))
            entity:pathThrough(pathNodes, xi.path.flag.PATROL)

            local bot =
            {
                botKey = botKey,
                localKey = localKey,
                displayName = displayName,
                actorType = actorType,
                entity = entity,
                profile = profile,
                rule = rule,
                zoneId = zoneId,
                pos = pos,
                level = botLevel,
                exp = 0,
                familiarity = 0,
                wallet = profile.walletFloor or 0,
                status = 'active',
                roleState = roleState,
                targetMobId = 0,
                ownerCharId = 0,
                partyKey = nil,
                cooldowns = {},
                talkIndex = 0,
            }

            active.bots[botKey] = bot
            if actorType == 'mob' then
                active.combatBots = active.combatBots + 1
            end

            serverBots.runtime.totalActive = serverBots.runtime.totalActive + 1
            touchState(bot, 'active')
            audit('spawn', zoneId, botKey, displayName, string.format('kind=%s actor=%s fullSim=%s dbBacked=%s', rule.kind, actorType, tostring(config.fullSim), tostring(loadCache().dbBacked)))
            scheduleIdleCheck(zoneId, botKey, bot)
        else
            audit('spawn_failed', zoneId, botKey, displayName, string.format('actor=%s profile=%s', actorType, profile.key), 'error')
        end
    end

    local spawned = tableCount(active.bots)
    if spawned == 0 then
        serverBots.runtime.activeByZone[zoneId] = nil
    else
        scheduleZoneTick(zoneId)
    end

    return spawned, 'Server bots spawned.'
end

local function resetPersistedRuntimeStateOnStartup()
    if serverBots.runtime.startupStateReset then
        return
    end

    if
        serverBots.native == nil or
        serverBots.native.deactivatePersistedState == nil
    then
        return
    end

    serverBots.runtime.startupStateReset = true
    serverBots.runtime.activeByZone = {}
    serverBots.runtime.totalActive = 0
    serverBots.native.deactivatePersistedState('map startup reset')
    audit('startup_state_reset', 0, '', '', 'Marked persisted active bot state inactive on map startup.')
end

function serverBots.onCharZoneIn(player)
    resetPersistedRuntimeStateOnStartup()

    if player == nil then
        return
    end

    local zone = player:getZone(true)
    if zone == nil then
        return
    end

    serverBots.spawnZone(zone, player)
end

function serverBots.status()
    resetPersistedRuntimeStateOnStartup()

    local zoneCount = 0
    local botCount  = 0
    local combatBots = 0

    for _, active in pairs(serverBots.runtime.activeByZone) do
        zoneCount = zoneCount + 1
        botCount  = botCount + tableCount(active.bots)
        combatBots = combatBots + (active.combatBots or 0)
    end

    local cache = loadCache()
    return
    {
        enabled = isEnabled(),
        paused = serverBots.runtime.paused,
        dbBacked = cache.dbBacked,
        zones = zoneCount,
        bots = botCount,
        combatBots = combatBots,
        profiles = #cache.profiles,
        rules = tableCount(cache.rulesByZone),
    }
end

function serverBots.despawnZone(zoneId)
    local active = serverBots.runtime.activeByZone[zoneId]
    if active == nil then
        return 0
    end

    local count = 0
    for botKey, bot in pairs(active.bots) do
        despawnEntity(bot)
        bot.status = 'despawned'
        touchState(bot, 'despawned')
        audit('despawn_command', zoneId, botKey, bot.displayName, 'GM command despawn.')
        count = count + 1
    end

    serverBots.runtime.totalActive = math.max(serverBots.runtime.totalActive - count, 0)
    serverBots.runtime.activeByZone[zoneId] = nil

    return count
end

function serverBots.despawnAll()
    local count = 0
    local zones = {}

    for zoneId, _ in pairs(serverBots.runtime.activeByZone) do
        table.insert(zones, zoneId)
    end

    for _, zoneId in ipairs(zones) do
        count = count + serverBots.despawnZone(zoneId)
    end

    return count
end

function serverBots.reload()
    serverBots.runtime.cache = nil
    loadCache(true)
end

function serverBots.setRuntimeEnabled(enabled)
    if serverBots.native ~= nil and serverBots.native.setRuntimeEnabled ~= nil then
        serverBots.native.setRuntimeEnabled(enabled)
    end

    if not enabled then
        serverBots.despawnAll()
    end

    audit(enabled and 'enable' or 'disable', 0, '', '', 'GM command changed runtime state.')
end

function serverBots.pause()
    serverBots.runtime.paused = true
    if serverBots.native ~= nil and serverBots.native.setRuntimeFlag ~= nil then
        serverBots.native.setRuntimeFlag('runtime_paused', '1', 'serverbot')
    end

    audit('pause', 0, '', '', 'Server bot strategy ticks paused.')
end

function serverBots.resume()
    serverBots.runtime.paused = false
    if serverBots.native ~= nil and serverBots.native.setRuntimeFlag ~= nil then
        serverBots.native.setRuntimeFlag('runtime_paused', '0', 'serverbot')
    end

    audit('resume', 0, '', '', 'Server bot strategy ticks resumed.')
end

function serverBots.setLlmEnabled(enabled)
    serverBots.runtime.llmEnabled = enabled
    if serverBots.native ~= nil and serverBots.native.setRuntimeFlag ~= nil then
        serverBots.native.setRuntimeFlag('llm_enabled', enabled and '1' or '0', 'serverbot')
    end

    audit(enabled and 'llm_enable' or 'llm_disable', 0, '', '', 'Optional LLM chat runtime flag changed.')
end

function serverBots.panic()
    serverBots.runtime.paused = true
    if serverBots.native ~= nil and serverBots.native.setRuntimeFlag ~= nil then
        serverBots.native.setRuntimeFlag('panic_disable', '1', 'serverbot')
    end

    serverBots.setRuntimeEnabled(false)
    audit('panic_disable', 0, '', '', 'Panic disable despawned all bots and disabled runtime.', 'warning')
end

function serverBots.trace(zoneId)
    local active = serverBots.runtime.activeByZone[zoneId]
    if active == nil then
        return {}
    end

    local rows = {}
    for botKey, bot in pairs(active.bots) do
        table.insert(rows, string.format('%s profile=%s actor=%s state=%s party=%s name=%s', botKey, bot.profile.key, bot.actorType, bot.roleState or 'idle', bot.partyKey or 'solo', bot.displayName))
    end

    table.sort(rows)
    return rows
end

function serverBots.profileRows(profileKey)
    local cache = loadCache()
    local rows = {}

    for _, profile in ipairs(cache.profiles) do
        if profileKey == nil or profileKey == '' or profile.key == profileKey then
            table.insert(rows, string.format('%s role=%s job=%u/%u level=%u-%u strategies=%s autonomousParty=%s', profile.key, profile.role, profile.mainJob, profile.subJob, profile.minLevel, profile.maxLevel, table.concat(profile.strategyStack, ','), tostring(profile.canParty)))
        end
    end

    table.sort(rows)
    return rows
end

function serverBots.ruleRows(zoneId)
    local cache = loadCache()
    local rows = {}

    for currentZoneId, rules in pairs(cache.rulesByZone) do
        if zoneId == nil or zoneId == 0 or zoneId == currentZoneId then
            for _, rule in ipairs(rules) do
                table.insert(rows, string.format('%s zone=%u kind=%s count=%u max=%u combat=%s camp=%s', rule.key, currentZoneId, rule.kind, rule.targetCount or 0, rule.maxCount or 0, tostring(rule.allowCombat), rule.campKey or ''))
            end
        end
    end

    table.sort(rows)
    return rows
end

function serverBots.campRows(zoneIdOrKey)
    local cache = loadCache()
    local rows = {}

    for _, camp in pairs(cache.campsByKey) do
        if
            zoneIdOrKey == nil or
            zoneIdOrKey == '' or
            tostring(camp.zoneId) == tostring(zoneIdOrKey) or
            camp.key == zoneIdOrKey
        then
            table.insert(rows, string.format('%s zone=%u level=%u-%u radius=%.1f name=%s', camp.key, camp.zoneId, camp.minLevel, camp.maxLevel, camp.radius, camp.name))
        end
    end

    table.sort(rows)
    return rows
end

function serverBots.strategyRows(strategyKey)
    local cache = loadCache()
    local rows = {}

    for key, strategy in pairs(cache.strategies) do
        if strategyKey == nil or strategyKey == '' or key == strategyKey then
            table.insert(rows, string.format('%s layer=%s interval=%us params=%s', key, strategy.layer or 'unknown', strategy.interval or 0, strategy.params or ''))
        end
    end

    table.sort(rows)
    return rows
end

local function nativeLatest(name, limit)
    if serverBots.native == nil or serverBots.native[name] == nil then
        return {}
    end

    local ok, rows = pcall(serverBots.native[name], limit or 10)
    if ok and rows ~= nil then
        local output = {}
        for _, row in ipairs(rows) do
            if name == 'latestAudit' then
                table.insert(output, string.format('%s [%s] z%u %s %s', row.created_at, row.severity, row.zone_id, row.action, row.details or ''))
            elseif name == 'latestEconomy' then
                table.insert(output, string.format('%s %s %s gil=%s status=%s', row.created_at, row.bot_key, row.action, tostring(row.gil_delta), row.status))
            elseif name == 'latestPerformance' then
                table.insert(output, string.format('%s z%u active=%u combat=%u budget=%ums details=%s', row.created_at, row.zone_id, row.active_bots, row.combat_bots, row.tick_budget_ms, row.details or ''))
            end
        end

        return output
    end

    return {}
end

function serverBots.auditRows(limit)
    return nativeLatest('latestAudit', limit)
end

function serverBots.economyRows(limit)
    return nativeLatest('latestEconomy', limit)
end

function serverBots.performanceRows(limit)
    return nativeLatest('latestPerformance', limit)
end

local function findCommandableBot(player, allowAssign)
    local active = serverBots.runtime.activeByZone[player:getZoneID()]
    if active == nil then
        return nil
    end

    local playerId = player:getID()
    for _, bot in pairs(active.bots) do
        if bot.profile.commandable and bot.ownerCharId == playerId then
            return bot
        end
    end

    if not allowAssign then
        return nil
    end

    for _, bot in pairs(active.bots) do
        if
            bot.profile.commandable and
            (bot.ownerCharId == nil or bot.ownerCharId == 0)
        then
            return bot
        end
    end

    return nil
end

function serverBots.playerOrder(player, action, arg1)
    return false, 'Server bots are autonomous world adventurers and do not accept player orders. Use Trusts for player companion gameplay.'
end

serverBots.commandAllowed = commandAllowed

return serverBots
