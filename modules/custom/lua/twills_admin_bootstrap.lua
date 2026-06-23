-----------------------------------
-- Twills local admin bootstrap
--
-- Versioned local bootstrap and repair for the project admin character. This
-- intentionally uses LSB player APIs and existing GM command helpers for packed
-- character state such as spells, trusts, maps, warps, mounts, attachments,
-- merits, job points, key items, and learned weapon skills.
-----------------------------------
require('modules/module_utils')
require('scripts/globals/player')
require('scripts/globals/missions')
require('scripts/globals/quests')
require('scripts/globals/teleports')
require('scripts/enum/augment')
require('scripts/enum/fame_area')
require('scripts/enum/ws_unlock')
-----------------------------------
local m = Module:new('twills_admin_bootstrap')

local ADMIN_NAME = 'Twills'
local CURRENT_BOOT_VERSION = 5
local VAR_STARTED = 'TwillsBootStartV5'
local VAR_DONE = 'TwillsBootDone'
local VAR_VERSION = 'TwillsBootVersion'
local VAR_GEAR_VERSION = 'TwillsRdmSchGearVersion'
local TARGET_MERITS = 75
local TARGET_JOB_POINTS = 500
local TARGET_CAPACITY_POINTS = 29999
local TARGET_ALTER_EGO_POINTS = 1350
local TARGET_GEAR_VERSION = 1
local TARGET_INVENTORY_SIZE = 80
local TARGET_WARDROBE_SIZE = 80
local TARGET_FAME_VALUE = 613
local TARGET_ABYSSEA_FAME_VALUE = 425

local addAllSpells = require('scripts/commands/addallspells')
xi.commands = xi.commands or {}
xi.commands.addallspells = xi.commands.addallspells or addAllSpells

local commandHelpers =
{
    addAllTrusts       = require('scripts/commands/addalltrusts'),
    addAllMaps         = require('scripts/commands/addallmaps'),
    addAllWarps        = require('scripts/commands/addallwarps'),
    addAllMounts       = require('scripts/commands/addallmounts'),
    addAllAttachments  = require('scripts/commands/addallattachments'),
    addAllWeaponSkills = require('scripts/commands/addallweaponskills'),
}

local requiredKeyItems =
{
    xi.ki.LIMIT_BREAKER,
    xi.ki.JOB_BREAKER,
    xi.ki.MASTER_BREAKER,
    xi.ki.HEART_OF_THE_BUSHIN,
    xi.ki.AIRSHIP_PASS,
    xi.ki.AIRSHIP_PASS_FOR_KAZHAM,
    xi.ki.ARCHDUCAL_AUDIENCE_PERMIT,
    xi.ki.TENSHODO_MEMBERS_CARD,
    xi.ki.WHITE_CARD,
    xi.ki.MONARCH_LINN_PATROL_PERMIT,
    xi.ki.BOARDING_PERMIT,
    xi.ki.RUNIC_PORTAL_USE_PERMIT,
    xi.ki.PURE_WHITE_FEATHER,
    xi.ki.MEDAL_OF_ALTANA,
    xi.ki.LUNAR_ABYSSITE1,
    xi.ki.LUNAR_ABYSSITE2,
    xi.ki.LUNAR_ABYSSITE3,
    xi.ki.PRIMAL_GLOW,
    xi.ki.ADOULINIAN_CHARTER_PERMIT,
    xi.ki.KAZHAM_WARP_RUNE,
    xi.ki.WINDURST_TRUST_PERMIT,
    xi.ki.BASTOK_TRUST_PERMIT,
    xi.ki.SAN_DORIA_TRUST_PERMIT,
    xi.ki.RHAPSODY_IN_WHITE,
    xi.ki.RHAPSODY_IN_UMBER,
    xi.ki.RHAPSODY_IN_AZURE,
    xi.ki.RHAPSODY_IN_CRIMSON,
    xi.ki.RHAPSODY_IN_EMERALD,
    xi.ki.RHAPSODY_IN_MAUVE,
    xi.ki.RHAPSODY_IN_FUCHSIA,
    xi.ki.RHAPSODY_IN_PUCE,
    xi.ki.RHAPSODY_IN_OCHRE,
    xi.ki.SCINTILLATING_RHAPSODY,
    xi.ki.CIPHER_BRACELET,
}

local gobbieBagQuests =
{
    xi.quest.id.jeuno.THE_GOBBIEBAG_PART_I,
    xi.quest.id.jeuno.THE_GOBBIEBAG_PART_II,
    xi.quest.id.jeuno.THE_GOBBIEBAG_PART_III,
    xi.quest.id.jeuno.THE_GOBBIEBAG_PART_IV,
    xi.quest.id.jeuno.THE_GOBBIEBAG_PART_V,
    xi.quest.id.jeuno.THE_GOBBIEBAG_PART_VI,
    xi.quest.id.jeuno.THE_GOBBIEBAG_PART_VII,
    xi.quest.id.jeuno.THE_GOBBIEBAG_PART_VIII,
    xi.quest.id.jeuno.THE_GOBBIEBAG_PART_IX,
    xi.quest.id.jeuno.THE_GOBBIEBAG_PART_X,
}

local rdmSchGear =
{
    -- Core weapons/offhands.
    { id = 21627, name = 'crocea_mors' },
    { id = 22040, name = 'daybreak' },
    { id = 21621, name = 'naegling' },
    { id = 22031, name = 'maxentius' },
    { id = 22041, name = 'bunzis_rod' },
    { id = 21565, name = 'tauret' },
    { id = 20604, name = 'ternion_dagger_+1' },
    { id = 26419, name = 'ammurapi_shield' },
    { id = 27645, name = 'genmei_shield' },
    { id = 22271, name = 'pemphredo_tathlum' },
    { id = 21344, name = 'ghastly_tathlum_+1' },

    -- Melee/TP and defensive baselines.
    { id = 23732, name = 'malignance_chapeau' },
    { id = 23733, name = 'malignance_tabard' },
    { id = 23734, name = 'malignance_gloves' },
    { id = 23735, name = 'malignance_tights' },
    { id = 23736, name = 'malignance_boots' },
    { id = 23761, name = 'nyame_helm' },
    { id = 23768, name = 'nyame_mail' },
    { id = 23775, name = 'nyame_gauntlets' },
    { id = 23782, name = 'nyame_flanchard' },
    { id = 23789, name = 'nyame_sollerets' },
    { id = 25572, name = 'ayanmo_zucchetto_+2' },
    { id = 25795, name = 'ayanmo_corazza_+2' },
    { id = 25833, name = 'ayanmo_manopolas_+2' },
    { id = 25884, name = 'ayanmo_cosciales_+2' },
    { id = 25951, name = 'ayanmo_gambieras_+2' },

    -- Highest locally implemented RDM job-specific pieces. Some newer +3/+4
    -- rows exist in item_equipment but lack item_mods in this checkout.
    { id = 23402, name = 'vitiation_chapeau_+3' },
    { id = 23134, name = 'vitiation_tabard_+2' },
    { id = 23201, name = 'vitiation_gloves_+2' },
    { id = 23268, name = 'vitiation_tights_+2' },
    { id = 23670, name = 'vitiation_boots_+3' },
    { id = 23089, name = 'lethargy_chappel_+2' },
    { id = 23156, name = 'lethargy_sayon_+2' },
    { id = 23223, name = 'lethargy_gantherots_+2' },
    { id = 23290, name = 'lethargy_fuseau_+2' },
    { id = 23357, name = 'lethargy_houseaux_+2' },
    { id = 23379, name = 'atrophy_chapeau_+3' },
    { id = 23446, name = 'atrophy_tabard_+3' },
    { id = 23513, name = 'atrophy_gloves_+3' },
    { id = 23580, name = 'atrophy_tights_+3' },
    { id = 23647, name = 'atrophy_boots_+3' },

    -- Casting, nuking, healing, enhancing, and utility sets.
    { id = 23759, name = 'agwus_cap' },
    { id = 23766, name = 'agwus_robe' },
    { id = 23773, name = 'agwus_gages' },
    { id = 23780, name = 'agwus_slops' },
    { id = 23787, name = 'agwus_pigaches' },
    { id = 23760, name = 'bunzis_hat' },
    { id = 23767, name = 'bunzis_robe' },
    { id = 23774, name = 'bunzis_gloves' },
    { id = 23781, name = 'bunzis_pants' },
    { id = 23788, name = 'bunzis_sabots' },
    { id = 25578, name = 'jhakri_coronal_+2' },
    { id = 25794, name = 'jhakri_robe_+2' },
    { id = 25832, name = 'jhakri_cuffs_+2' },
    { id = 25883, name = 'jhakri_slops_+2' },
    { id = 25950, name = 'jhakri_pigaches_+2' },
    { id = 25616, name = 'amalric_coif_+1' },
    { id = 25689, name = 'amalric_doublet_+1' },
    { id = 27120, name = 'amalric_gages_+1' },
    { id = 27305, name = 'amalric_slops_+1' },
    { id = 27476, name = 'amalric_nails_+1' },
    { id = 25618, name = 'kaykaus_mitra_+1' },
    { id = 25691, name = 'kaykaus_bliaut_+1' },
    { id = 27122, name = 'kaykaus_cuffs_+1' },
    { id = 27307, name = 'kaykaus_tights_+1' },
    { id = 27478, name = 'kaykaus_boots_+1' },

    -- Accessories.
    { id = 25443, name = 'duelists_torque_+2' },
    { id = 26359, name = 'orpheuss_sash' },
    { id = 28419, name = 'hachirin-no-obi' },
    { id = 28428, name = 'sailfi_belt_+1' },
    { id = 26364, name = 'sroda_belt' },
    { id = 28411, name = 'yemaya_belt' },
    { id = 26184, name = 'stikini_ring_+1', targetCount = 2 },
    { id = 26184, name = 'stikini_ring_+1', targetCount = 2 },
    { id = 27563, name = 'metamorph_ring_+1' },
    { id = 26188, name = 'kishar_ring' },
    { id = 28472, name = 'freke_ring' },
    { id = 26221, name = 'sroda_ring' },
    { id = 26186, name = 'ilabrat_ring' },
    { id = 26214, name = 'epaminondass_ring' },
    { id = 26190, name = 'moonlight_ring' },
    { id = 13566, name = 'defending_ring' },
    { id = 26085, name = 'regal_earring' },
    { id = 26088, name = 'malignance_earring' },
    { id = 26109, name = 'snotra_earring' },
    { id = 27547, name = 'dignitarys_earring' },
    { id = 27545, name = 'telos_earring' },
    { id = 28514, name = 'friomisi_earring' },
    { id = 26082, name = 'lugalbanda_earring' },
    { id = 26095, name = 'mimir_earring' },

    -- RDM Ambuscade capes. Multiple capes are retail-legit because each cape
    -- carries one role-specific augment package.
    {
        id = 26250,
        name = 'sucelloss_cape_enfeebling',
        targetCount = 4,
        exdata =
        {
            augmentKind    = xi.augment.kind.HAS_AUGMENTS,
            augmentSubKind = xi.augment.subKind.STANDARD,
            augments =
            {
                { id = 517, value = 29 }, -- MND+30
                { id = 80,  value = 19 }, -- Mag. Acc.+20 / Mag. Dmg.+20
                { id = 140, value = 9  }, -- Fast Cast+10
            },
        },
    },
    {
        id = 26250,
        name = 'sucelloss_cape_tp',
        targetCount = 4,
        exdata =
        {
            augmentKind    = xi.augment.kind.HAS_AUGMENTS,
            augmentSubKind = xi.augment.subKind.STANDARD,
            augments =
            {
                { id = 513, value = 29 }, -- DEX+30
                { id = 129, value = 19 }, -- Accuracy/Rng. Acc.+20
                { id = 130, value = 19 }, -- Attack/Rng. Atk.+20
                { id = 146, value = 9  }, -- Dual Wield+10
            },
        },
    },
    {
        id = 26250,
        name = 'sucelloss_cape_ws',
        targetCount = 4,
        exdata =
        {
            augmentKind    = xi.augment.kind.HAS_AUGMENTS,
            augmentSubKind = xi.augment.subKind.STANDARD,
            augments =
            {
                { id = 512, value = 29 }, -- STR+30
                { id = 129, value = 19 }, -- Accuracy/Rng. Acc.+20
                { id = 130, value = 19 }, -- Attack/Rng. Atk.+20
                { id = 327, value = 9  }, -- Weapon skill damage+10%
            },
        },
    },
    {
        id = 26250,
        name = 'sucelloss_cape_nuke',
        targetCount = 4,
        exdata =
        {
            augmentKind    = xi.augment.kind.HAS_AUGMENTS,
            augmentSubKind = xi.augment.subKind.STANDARD,
            augments =
            {
                { id = 516, value = 29 }, -- INT+30
                { id = 80,  value = 19 }, -- Mag. Acc.+20 / Mag. Dmg.+20
                { id = 133, value = 9  }, -- Mag. Atk. Bns.+10
            },
        },
    },

    -- Enhancing-duration Telchine set. Retail Dark Matter augments vary; this
    -- gives the stable, useful duration package LSB can represent.
    {
        id = 26736,
        name = 'telchine_cap_enhancing',
        exdata = { augmentKind = xi.augment.kind.HAS_AUGMENTS, augmentSubKind = xi.augment.subKind.STANDARD, augments = { { id = 1248, value = 9 } } },
    },
    {
        id = 26894,
        name = 'telchine_chasuble_enhancing',
        exdata = { augmentKind = xi.augment.kind.HAS_AUGMENTS, augmentSubKind = xi.augment.subKind.STANDARD, augments = { { id = 1248, value = 9 } } },
    },
    {
        id = 27048,
        name = 'telchine_gloves_enhancing',
        exdata = { augmentKind = xi.augment.kind.HAS_AUGMENTS, augmentSubKind = xi.augment.subKind.STANDARD, augments = { { id = 1248, value = 9 } } },
    },
    {
        id = 27235,
        name = 'telchine_braconi_enhancing',
        exdata = { augmentKind = xi.augment.kind.HAS_AUGMENTS, augmentSubKind = xi.augment.subKind.STANDARD, augments = { { id = 1248, value = 9 } } },
    },
    {
        id = 27405,
        name = 'telchine_pigaches_enhancing',
        exdata = { augmentKind = xi.augment.kind.HAS_AUGMENTS, augmentSubKind = xi.augment.subKind.STANDARD, augments = { { id = 1248, value = 9 } } },
    },
}

local function callHelper(player, helper)
    if helper and type(helper.onTrigger) == 'function' then
        helper.onTrigger(player)
    end
end

local function unlockJobsAndLevels(player)
    player:unlockJob(0) -- support job
    player:setLevelCap(99)

    for job = xi.job.WAR, xi.job.RUN do
        player:unlockJob(job)
        player:changeJob(job)
        player:setLevel(99)
        player:masterJob()
    end

    player:changeJob(xi.job.RDM)
    player:setLevel(99)
    player:changesJob(xi.job.SCH)
    player:setsLevel(99)
end

local function capSkills(player)
    for skill = 1, 57 do
        if not (skill > 12 and skill < 25) and skill ~= 46 and skill ~= 47 then
            player:setSkillLevel(skill, 5000)
        end
    end
end

local function addRequiredKeyItems(player)
    local added = 0

    for _, keyItemId in ipairs(requiredKeyItems) do
        if keyItemId ~= nil and not player:hasKeyItem(keyItemId) then
            player:addKeyItem(keyItemId)
            added = added + 1
        end
    end

    return added
end

local function ensureRetailStorageGates(player)
    local inventoryAdjustment = TARGET_INVENTORY_SIZE - player:getContainerSize(xi.inv.INVENTORY)
    if inventoryAdjustment > 0 then
        player:changeContainerSize(xi.inv.INVENTORY, inventoryAdjustment)
    end

    for _, containerId in ipairs({
        xi.inv.WARDROBE,
        xi.inv.WARDROBE2,
        xi.inv.WARDROBE3,
        xi.inv.WARDROBE4,
        xi.inv.WARDROBE5,
        xi.inv.WARDROBE6,
        xi.inv.WARDROBE7,
        xi.inv.WARDROBE8,
    }) do
        local adjustment = TARGET_WARDROBE_SIZE - player:getContainerSize(containerId)
        if adjustment > 0 then
            player:changeContainerSize(containerId, adjustment)
        end
    end

    for _, questId in ipairs(gobbieBagQuests) do
        if questId ~= nil and not player:hasCompletedQuest(xi.questLog.JEUNO, questId) then
            player:completeQuest(xi.questLog.JEUNO, questId)
        end
    end
end

local function setMaxFame(player)
    for _, fameArea in pairs(xi.fameArea) do
        local value = fameArea >= xi.fameArea.ABYSSEA_KONSCHTAT and fameArea <= xi.fameArea.ABYSSEA_ULEGUERAND
            and TARGET_ABYSSEA_FAME_VALUE
            or TARGET_FAME_VALUE
        player:setFame(fameArea, value)
    end
end

local function completeKnownMissions(player)
    local completed = 0
    local terminal = 0

    for logId, areaName in pairs(xi.mission.area) do
        if logId ~= xi.mission.log_id.ASSAULT and logId ~= xi.mission.log_id.CAMPAIGN then
            local missions = xi.mission.id[areaName]
            local seen = {}
            local maxMissionId = 0
            local usesCurrentProgress = logId == xi.mission.log_id.COP

            if missions ~= nil then
                for _, missionId in pairs(missions) do
                    if type(missionId) == 'number' and missionId >= 0 and missionId < 65535 then
                        seen[missionId] = true
                        maxMissionId = math.max(maxMissionId, missionId)

                        if missionId >= 64 then
                            usesCurrentProgress = true
                        end
                    end
                end

                for missionId in pairs(seen) do
                    if not usesCurrentProgress or missionId < 64 then
                        player:addMission(logId, missionId)
                        player:completeMission(logId, missionId)
                        completed = completed + 1
                    end
                end

                if usesCurrentProgress and maxMissionId > 0 then
                    -- CoP reaches the engine's MAX_MISSIONID boundary at 850, so
                    -- current=850 represents terminal progression through Dawn
                    -- while The Last Verse remains the terminal current marker.
                    player:addMission(logId, math.min(maxMissionId + 1, 850))
                    player:setMissionStatus(logId, 0)
                    terminal = terminal + 1
                end
            end
        end
    end

    return completed, terminal
end

local function completeKnownQuests(player)
    local completed = 0

    for logId, areaName in pairs(xi.quest.area) do
        local quests = xi.quest.id[areaName]
        local seen = {}

        if quests ~= nil then
            for _, questId in pairs(quests) do
                if type(questId) == 'number' and questId >= 0 and questId < 256 then
                    seen[questId] = true
                end
            end

            for questId in pairs(seen) do
                if not player:hasCompletedQuest(logId, questId) then
                    player:completeQuest(logId, questId)
                    completed = completed + 1
                end
            end
        end
    end

    return completed
end

local function grantRdmSchGear(player)
    if player:getCharVar(VAR_GEAR_VERSION) >= TARGET_GEAR_VERSION then
        return 0, 0
    end

    local granted = 0
    local failed = 0

    if xi.twills_admin.native and type(xi.twills_admin.native.grantGear) == 'function' then
        granted, failed = xi.twills_admin.native.grantGear(player, rdmSchGear)
    else
        for _, item in ipairs(rdmSchGear) do
            local shouldGrant = item.exdata ~= nil or item.name == 'stikini_ring_+1' or not player:hasItem(item.id)

            if shouldGrant then
                local itemData =
                {
                    id       = item.id,
                    quantity = 1,
                    silent   = true,
                }

                if item.exdata ~= nil then
                    itemData.exdata = item.exdata
                end

                local addedItem = player:addItem(itemData)
                if addedItem ~= nil then
                    granted = granted + 1
                else
                    failed = failed + 1
                end
            end
        end
    end

    if failed == 0 then
        player:setCharVar(VAR_GEAR_VERSION, TARGET_GEAR_VERSION)
    end

    return granted, failed
end

local function repair(player, forced)
    if not player or player:getName() ~= ADMIN_NAME then
        return false
    end

    player:setGMLevel(5)
    player:setVisibleGMLevel(0)
    player:setGMHidden(false)
    player:setNation(xi.nation.SANDORIA)
    player:setRank(10)
    player:setRankPoints(0)
    player:setGil(1000000)

    unlockJobsAndLevels(player)
    capSkills(player)
    ensureRetailStorageGates(player)
    setMaxFame(player)

    local nativeDbRepaired = false
    if xi.twills_admin.native and type(xi.twills_admin.native.repairDbState) == 'function' then
        nativeDbRepaired = xi.twills_admin.native.repairDbState(player:getID())
    end

    callHelper(player, commandHelpers.addAllMaps)
    callHelper(player, commandHelpers.addAllWarps)
    callHelper(player, commandHelpers.addAllMounts)
    callHelper(player, commandHelpers.addAllAttachments)
    callHelper(player, commandHelpers.addAllWeaponSkills)

    addAllSpells.onTrigger(player)
    commandHelpers.addAllTrusts.onTrigger(player)
    local addedKeyItems = addRequiredKeyItems(player)

    player:setCurrency('alter_ego_points', TARGET_ALTER_EGO_POINTS)
    player:setMerits(TARGET_MERITS)
    player:setJobPoints(TARGET_JOB_POINTS)
    player:setCapacityPoints(TARGET_CAPACITY_POINTS)

    local missionCount, terminalMissionLogs = completeKnownMissions(player)
    local questCount = completeKnownQuests(player)
    local gearGranted, gearFailed = grantRdmSchGear(player)

    -- Mission and quest logs are completed through local LSB APIs, not direct
    -- blob writes. Content not represented in the local mission/quest enums is
    -- documented in the Twills gear/completion manifest.
    player:setCharVar(VAR_DONE, 1)
    player:setCharVar(VAR_VERSION, CURRENT_BOOT_VERSION)

    local mode = forced and 'repair' or 'bootstrap'
    player:printToPlayer(string.format(
        'Twills admin %s v%i complete: %i key items, %i missions, %i terminal logs, %i quests, %i gear items (%i failed), privileges kept, GM icon hidden%s. Relog to refresh all client-side views.',
        mode,
        CURRENT_BOOT_VERSION,
        addedKeyItems,
        missionCount,
        terminalMissionLogs,
        questCount,
        gearGranted,
        gearFailed,
        nativeDbRepaired and ' with DB gates' or ''
    ), xi.msg.channel.SYSTEM_3)

    return true
end

xi.twills_admin = xi.twills_admin or {}
xi.twills_admin.adminName = ADMIN_NAME
xi.twills_admin.currentVersion = CURRENT_BOOT_VERSION
xi.twills_admin.repair = repair

m:addOverride('xi.player.onGameIn', function(player, firstLogin, zoning)
    super(player, firstLogin, zoning)

    if
        player:getName() ~= ADMIN_NAME or
        player:getCharVar(VAR_VERSION) >= CURRENT_BOOT_VERSION or
        player:getCharVar(VAR_STARTED) == 1
    then
        return
    end

    player:setCharVar(VAR_STARTED, 1)
    player:timer(2500, function(playerArg)
        if playerArg ~= nil then
            repair(playerArg, false)
            playerArg:setCharVar(VAR_STARTED, 0)
        end
    end)
end)

return m
