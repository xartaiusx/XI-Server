-----------------------------------
-- Twills local admin bootstrap
--
-- Explicit, versioned repair helpers for the project admin character. Nothing in
-- this module mutates Twills automatically at login. Each repair surface is
-- selected through !twillsrepair and unsupported content stays audit-only.
-- luacheck: ignore _legacyAddCompletionTitles _legacyRepairLongTimeContent _legacyAuditLongTimeContent
-- luacheck: ignore _legacyCompleteKnownMissions _legacyCompleteKnownQuests _legacyGrantRdmSchGear _legacyGrantProfessionItems
-----------------------------------
require('modules/module_utils')
require('scripts/globals/player')
require('scripts/globals/missions')
require('scripts/globals/quests')
require('scripts/globals/teleports')
require('scripts/globals/moghouse')
require('scripts/globals/chocobo_raising')
require('scripts/globals/assault/data')
require('scripts/globals/roe_records')
require('scripts/globals/deeds')
-----------------------------------
local m = Module:new('twills_admin_bootstrap')
local contentRegistry = require('modules/custom/lua/twills_content_parity_registry')

local adminName = 'Twills'
local currentBootVersion = 9
local maxEngineTitleId = 1143
local longTimeRepairActiveVar = 'TwillsLongTimeRepairActive'
local varVersion = 'TwillsBootVersion'
local varGearVersion = 'TwillsRdmSchGearVersion'
local targetJobPoints = 500
local targetCapacityPoints = 29999
local targetAlterEgoPoints = 1350
local targetGearVersion = 3
local targetInventorySize = 80
local targetWardrobeSize = 80
local targetLockerLeaseBronze = 7300
local targetFameValue = 613
local targetAbysseaFameValue = 425
local targetMasterLevel = 50
local targetUnityLeader = xi.unityLeader.SYLVIE
local corneliaSpellId = 1002

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
    xi.ki.CHOCOBO_LICENSE,
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
    xi.ki.GARDENIA_PASS,
    xi.ki.GPS_CRYSTAL,
    xi.ki.SYNERGY_CRUCIBLE,
    xi.ki.MOG_PATIO_DESIGN_DOCUMENT,
    xi.ki.TRAINERS_WHISTLE,
    xi.ki.CHOCOBO_COMPANION,
    xi.ki.STORY_OF_AN_IMPATIENT_CHOCOBO,
    xi.ki.STORY_OF_A_CURIOUS_CHOCOBO,
    xi.ki.STORY_OF_A_HAPPY_CHOCOBO,
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

local completionTitles =
{
    xi.title.DARK_DRAGON_SLAYER,
    xi.title.SHADOW_BANISHER,
    xi.title.SHADOW_WALKER,
    xi.title.BELIEVER_OF_ALTANA,
    xi.title.CHAMPION_OF_AHT_URHGAN,
    xi.title.ARK_HUME_HUMILIATOR,
    xi.title.ARK_ELVAAN_EVISCERATOR,
    xi.title.ARK_MITHRA_MALIGNER,
    xi.title.ARK_TARUTARU_TROUNCER,
    xi.title.ARK_GALKA_GOUGER,
    xi.title.THOUSAND_YEAR_TRAVELER,
    xi.title.THE_SAVIOR_OF_VANADIEL,
    xi.title.MASTER_WARLOCK,
    xi.title.MASTER_ACADEMIC,
    xi.title.MASTER_OF_ALL,
    xi.title.DESTINY_MASTER,
    xi.title.CHOCOBO_TRAINER,
    xi.title.CHOCOBO_LOVE_GURU,
    xi.title.MOGS_MASTER,
    xi.title.MOG_HOUSE_HANDYPERSON,
    xi.title.MOG_GARDEN_SEEDLING,
    xi.title.MOG_GARDENER,
    xi.title.GARDENER_FOR_THE_AGES,
    xi.title.ACCOMPLISHED_ALCHEMIST,
    xi.title.LEGENDARY_ALCHEMIST,
    xi.title.LU_SHANG_LIKE_FISHER_KING,
    xi.title.THE_IMMORTAL_FISHER_LU_SHANG,
    xi.title.EXALTED_FISHERMAN,
    xi.title.FISH_WHISPERER,
}

local longTimeKeyItemNames =
{
    TRIBULENS = true,
    RADIALENS = true,
    ESCHAN_URN = true,
    ESCHAN_CELLAR = true,
    ESCHAN_NEF = true,
    REISENJIMA_SANCTORIUM_ORB = true,
    MOGLOPHONE = true,
    MOGLOPHONE_II_1 = true,
    MOGLOPHONE_II_2 = true,
    MOGLOPHONE_II_3 = true,
    AMBUSCADE_PRIMER_VOLUME_ONE = true,
    AMBUSCADE_PRIMER_VOLUME_TWO = true,
    DYNAMIS_VALKURM_SLIVER = true,
    DYNAMIS_BUBURIMU_SLIVER = true,
    DYNAMIS_QUFIM_SLIVER = true,
    DYNAMIS_TAVNAZIA_SLIVER = true,
}

local longTimeGateGroups =
{
    Escha =
    {
        'TRIBULENS',
        'RADIALENS',
        'ESCHAN_URN',
        'ESCHAN_CELLAR',
        'ESCHAN_NEF',
        'REISENJIMA_SANCTORIUM_ORB',
    },
    Odyssey =
    {
        'MOGLOPHONE',
        'MOGLOPHONE_II_1',
        'MOGLOPHONE_II_2',
        'MOGLOPHONE_II_3',
    },
    Ambuscade =
    {
        'AMBUSCADE_PRIMER_VOLUME_ONE',
        'AMBUSCADE_PRIMER_VOLUME_TWO',
    },
    Dynamis =
    {
        'DYNAMIS_VALKURM_SLIVER',
        'DYNAMIS_BUBURIMU_SLIVER',
        'DYNAMIS_QUFIM_SLIVER',
        'DYNAMIS_TAVNAZIA_SLIVER',
    },
}

local blockedRoeFlags =
{
    hidden = true,
    ['repeat'] = true,
    timed = true,
    daily = true,
    weekly = true,
    unity = true,
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
    { id = 22279, name = 'staunch_tathlum_+1' },
    { id = 21396, name = 'regal_gem' },
    { id = 22252, name = 'sapience_orb' },

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
    { id = 27383, name = 'carmine_greaves_+1' },
    { id = 25844, name = 'chironic_hose' },

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
    { id = 25554, name = 'ea_hat_+1' },
    { id = 26530, name = 'ea_houppelande_+1' },
    { id = 25981, name = 'ea_cuffs_+1' },
    { id = 25894, name = 'ea_slops_+1' },
    { id = 25961, name = 'ea_pigaches_+1' },
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
    { id = 28135, name = 'assiduity_pants_+1' },
    { id = 23726, name = 'volte_gaiters' },
    { id = 26735, name = 'taeon_chapeau' },
    { id = 26893, name = 'taeon_tabard' },
    { id = 27047, name = 'taeon_gloves' },
    { id = 27234, name = 'taeon_tights' },
    { id = 27404, name = 'taeon_boots' },
    { id = 10329, name = 'shedir_seraweels' },

    -- Accessories.
    { id = 25443, name = 'duelists_torque_+2' },
    { id = 26016, name = 'incanters_torque' },
    { id = 26029, name = 'anu_torque' },
    { id = 26003, name = 'baetyl_pendant' },
    { id = 26002, name = 'loricate_torque_+1' },
    { id = 27510, name = 'fotia_gorget' },
    { id = 26359, name = 'orpheuss_sash' },
    { id = 26354, name = 'embla_sash' },
    { id = 28419, name = 'hachirin-no-obi' },
    { id = 28428, name = 'sailfi_belt_+1' },
    { id = 10832, name = 'carriers_sash' },
    { id = 10820, name = 'bishops_sash' },
    { id = 10821, name = 'olympus_sash' },
    { id = 15960, name = 'siegel_sash' },
    { id = 28430, name = 'acuity_belt_+1' },
    { id = 26364, name = 'sroda_belt' },
    { id = 28411, name = 'yemaya_belt' },
    { id = 28420, name = 'fotia_belt' },
    { id = 27524, name = 'nodens_gorget' },
    { id = 26184, name = 'stikini_ring_+1', targetCount = 2 },
    { id = 26184, name = 'stikini_ring_+1', targetCount = 2 },
    { id = 27563, name = 'metamorph_ring_+1' },
    { id = 11646, name = 'sironas_ring' },
    { id = 10752, name = 'prolix_ring' },
    { id = 11674, name = 'archon_ring' },
    { id = 26188, name = 'kishar_ring' },
    { id = 28472, name = 'freke_ring' },
    { id = 26221, name = 'sroda_ring' },
    { id = 26182, name = 'chirich_ring_+1', targetCount = 2 },
    { id = 28478, name = 'etiolation_earring' },
    { id = 26088, name = 'malignance_earring' },
    { id = 21431, name = 'coiste_bodhar' },
    { id = 26084, name = 'sherida_earring' },
    { id = 27545, name = 'telos_earring' },
    { id = 26214, name = 'epaminondass_ring' },
    { id = 26186, name = 'ilabrat_ring' },
    { id = 28474, name = 'mendicants_earring' },
    { id = 26095, name = 'mimir_earring' },
    { id = 28506, name = 'andoaa_earring' },
    { id = 26182, name = 'chirich_ring_+1', targetCount = 2 },
    { id = 26186, name = 'ilabrat_ring' },
    { id = 26214, name = 'epaminondass_ring' },
    { id = 26190, name = 'moonlight_ring' },
    { id = 13566, name = 'defending_ring' },
    { id = 26085, name = 'regal_earring' },
    { id = 26088, name = 'malignance_earring' },
    { id = 26084, name = 'sherida_earring' },
    { id = 28478, name = 'etiolation_earring' },
    { id = 28474, name = 'mendicants_earring' },
    { id = 28506, name = 'andoaa_earring' },
    { id = 26109, name = 'snotra_earring' },
    { id = 27547, name = 'dignitarys_earring' },
    { id = 27545, name = 'telos_earring' },
    { id = 28514, name = 'friomisi_earring' },
    { id = 26082, name = 'lugalbanda_earring' },
    { id = 26095, name = 'mimir_earring' },
    { id = 10298, name = 'beatific_earring' },
    { id = 26194, name = 'weatherspoon_ring_+1' },
    { id = 21431, name = 'coiste_bodhar' },
    { id = 20614, name = 'pukulatmuj_+1' },

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
    -- gives the stable, useful duration package Mochirii can represent.
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

local professionItems =
{
    -- Fishing essentials.
    { id = 19321, name = 'ebisu_fishing_rod_+1', container = xi.inv.MOGCASE },
    { id = 19320, name = 'lu_shangs_fishing_rod_+1', container = xi.inv.MOGCASE },
    { id = 10925, name = 'fishers_torque', container = xi.inv.MOGCASE },
    { id = 14400, name = 'fishermans_apron', container = xi.inv.MOGCASE },
    { id = 3631, name = 'fishermens_stall', container = xi.inv.MOGCASE },
    { id = 3670, name = 'net_and_lure', container = xi.inv.MOGCASE },
    { id = 17400, name = 'sinking_minnow', container = xi.inv.MOGCASE },
    { id = 17407, name = 'minnow', container = xi.inv.MOGCASE },
    { id = 17402, name = 'shrimp_lure', container = xi.inv.MOGCASE },

    -- Alchemy master path.
    { id = 14398, name = 'alchemists_apron', container = xi.inv.MOGCASE },
    { id = 10954, name = 'alchemists_torque', container = xi.inv.MOGCASE },
    { id = 3633, name = 'alchemists_stall', container = xi.inv.MOGCASE },

    -- Other guild essentials for 70-cap support crafts.
    { id = 14392, name = 'carpenters_apron', container = xi.inv.MOGCASE },
    { id = 14393, name = 'blacksmiths_apron', container = xi.inv.MOGCASE },
    { id = 14394, name = 'goldsmiths_apron', container = xi.inv.MOGCASE },
    { id = 14395, name = 'weavers_apron', container = xi.inv.MOGCASE },
    { id = 14396, name = 'tanners_apron', container = xi.inv.MOGCASE },
    { id = 14397, name = 'boneworkers_apron', container = xi.inv.MOGCASE },
    { id = 14399, name = 'culinarians_apron', container = xi.inv.MOGCASE },
    { id = 10948, name = 'carvers_torque', container = xi.inv.MOGCASE },
    { id = 10949, name = 'smithys_torque', container = xi.inv.MOGCASE },
    { id = 10950, name = 'goldsmiths_torque', container = xi.inv.MOGCASE },
    { id = 10951, name = 'weavers_torque', container = xi.inv.MOGCASE },
    { id = 10952, name = 'tanners_torque', container = xi.inv.MOGCASE },
    { id = 10953, name = 'boneworkers_torque', container = xi.inv.MOGCASE },
    { id = 10955, name = 'culinarians_torque', container = xi.inv.MOGCASE },
    { id = 3632, name = 'carpenters_stall', container = xi.inv.MOGCASE },
    { id = 3625, name = 'blacksmiths_stall', container = xi.inv.MOGCASE },
    { id = 3626, name = 'goldsmiths_stall', container = xi.inv.MOGCASE },
    { id = 3628, name = 'weavers_stall', container = xi.inv.MOGCASE },
    { id = 3630, name = 'tanners_stall', container = xi.inv.MOGCASE },
    { id = 3627, name = 'boneworkers_stall', container = xi.inv.MOGCASE },
    { id = 3629, name = 'culinarians_stall', container = xi.inv.MOGCASE },

    -- Mount utility.
    { id = 15533, name = 'chocobo_whistle', container = xi.inv.MOGCASE },
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

-- Legacy-inert helpers remain only long enough to compare old state with the
-- generated dry-run manifests. They are deliberately not exported or called.
local function _legacyAddCompletionTitles(player)
    local added = 0

    for _, titleId in ipairs(completionTitles) do
        if titleId ~= nil then
            player:addTitle(titleId)
            added = added + 1
        end
    end

    if xi.title.DESTINY_MASTER ~= nil then
        player:setTitle(xi.title.DESTINY_MASTER)
    end

    return added
end

local function collectNamedIds(source, predicate)
    local entries = {}
    local seen = {}

    for name, id in pairs(source or {}) do
        if
            type(name) == 'string' and
            type(id) == 'number' and
            id > 0 and
            predicate(name, id) and
            not seen[id]
        then
            table.insert(entries, { name = name, id = id })
            seen[id] = true
        end
    end

    table.sort(entries, function(a, b)
        return a.id < b.id
    end)

    return entries
end

local function isLongTimeKeyItem(name, id)
    if name == 'DYNAMIS_DEBUGGER' then
        return false
    end

    return
        string.match(name, '^ATMA_OF_') ~= nil or
        string.find(name, 'ABYSSITE', 1, true) ~= nil or
        longTimeKeyItemNames[name] == true
end

local function getLongTimeKeyItems()
    return collectNamedIds(xi.ki, isLongTimeKeyItem)
end

local function countLongTimeKeyItems(player, predicate)
    local found = 0
    local total = 0
    local missing = {}

    for _, entry in ipairs(collectNamedIds(xi.ki, predicate)) do
        total = total + 1
        if player:hasKeyItem(entry.id) then
            found = found + 1
        else
            table.insert(missing, entry.name)
        end
    end

    return found, total, missing
end

local function countGateGroup(player, groupName)
    local found = 0
    local total = 0
    local missing = {}

    for _, name in ipairs(longTimeGateGroups[groupName] or {}) do
        local id = xi.ki[name]
        if id ~= nil then
            total = total + 1
            if player:hasKeyItem(id) then
                found = found + 1
            else
                table.insert(missing, name)
            end
        end
    end

    return found, total, missing
end

local function getAssaultMissionIds()
    local ids = {}
    local seen = {}

    for _, missions in pairs(xi.assault.missionsByArea or {}) do
        for _, missionId in ipairs(missions) do
            if type(missionId) == 'number' and missionId > 0 and not seen[missionId] then
                table.insert(ids, missionId)
                seen[missionId] = true
            end
        end
    end

    table.sort(ids)
    return ids
end

local function countAssaultProgress(player)
    local complete = 0
    local ids = getAssaultMissionIds()

    for _, missionId in ipairs(ids) do
        if player:hasCompletedAssault(missionId) then
            complete = complete + 1
        end
    end

    return complete, #ids
end

local function isStableRoeRecord(recordId, record)
    if type(recordId) ~= 'number' or record == nil then
        return false
    end

    local flags = record.flags or {}
    for flag in pairs(blockedRoeFlags) do
        if flags[flag] then
            return false
        end
    end

    return true
end

local function getStableRoeRecordIds()
    local ids = {}

    for recordId, record in pairs(xi.roe.records or {}) do
        if isStableRoeRecord(recordId, record) then
            table.insert(ids, recordId)
        end
    end

    table.sort(ids)
    return ids
end

local function countStableRoeProgress(player)
    local completed = 0
    local ids = getStableRoeRecordIds()

    for _, recordId in ipairs(ids) do
        if player:getEminenceCompleted(recordId) then
            completed = completed + 1
        end
    end

    return completed, #ids
end

local function bitCount(value)
    local count = 0
    local current = value or 0

    while current > 0 do
        if bit.band(current, 1) ~= 0 then
            count = count + 1
        end

        current = bit.rshift(current, 1)
    end

    return count
end

local function countClaimedDeeds(player)
    local claimed = player:getClaimedDeedMask() or {}
    local count = 0

    for _, mask in ipairs(claimed) do
        count = count + bitCount(mask)
    end

    return count
end

local function getLocalTitleIds()
    local ids = {}
    local seen = {}

    for _, titleId in pairs(xi.title or {}) do
        if
            type(titleId) == 'number' and
            titleId > 0 and
            titleId <= maxEngineTitleId and
            not seen[titleId]
        then
            table.insert(ids, titleId)
            seen[titleId] = true
        end
    end

    table.sort(ids)
    return ids
end

local function countLocalTitles(player)
    local found = 0
    local ids = getLocalTitleIds()

    for _, titleId in ipairs(ids) do
        if player:hasTitle(titleId) then
            found = found + 1
        end
    end

    return found, #ids
end

local function getLearnedWeaponSkillIds()
    local ids = {}
    local seen = {}

    for _, wsUnlockId in pairs(xi.wsUnlock or {}) do
        if type(wsUnlockId) == 'number' and wsUnlockId > 0 and not seen[wsUnlockId] then
            table.insert(ids, wsUnlockId)
            seen[wsUnlockId] = true
        end
    end

    table.sort(ids)
    return ids
end

local function countLearnedWeaponSkills(player)
    local found = 0
    local ids = getLearnedWeaponSkillIds()

    for _, wsUnlockId in ipairs(ids) do
        if player:hasLearnedWeaponskill(wsUnlockId) then
            found = found + 1
        end
    end

    return found, #ids
end

local function queueLongTimeContentRepair(player)
    if player:getCharVar(longTimeRepairActiveVar) == 1 then
        return false
    end

    player:setCharVar(longTimeRepairActiveVar, 1)

    local deedTarget = math.min(math.floor(player:getCurrency('deeds') / 10), 144)
    local deedBits = {}
    for deedBit = 1, deedTarget do
        table.insert(deedBits, deedBit)
    end

    local keyItems = getLongTimeKeyItems()
    local assaults = getAssaultMissionIds()
    local roeRecords = getStableRoeRecordIds()
    local titles = getLocalTitleIds()
    local weaponSkills = getLearnedWeaponSkillIds()

    local state =
    {
        keyItemsAdded = 0,
        keyItemsTotal = #keyItems,
        assaultsAdded = 0,
        assaultsTotal = #assaults,
        roeAdded = 0,
        roeTotal = #roeRecords,
        deedTarget = deedTarget,
        titleTotal = #titles,
        wsTotal = #weaponSkills,
        zoneAdded = 0,
        zoneExpected = 0,
    }

    local stages =
    {
        {
            name = 'key items',
            ids = keyItems,
            batch = 12,
            process = function(p, entry)
                if not p:hasKeyItem(entry.id) then
                    p:addKeyItem(entry.id)
                    state.keyItemsAdded = state.keyItemsAdded + 1
                end
            end,
        },
        {
            name = 'Assault',
            ids = assaults,
            batch = 3,
            process = function(p, missionId)
                if not p:hasCompletedAssault(missionId) then
                    local currentAssault = p:getCurrentAssault()
                    if currentAssault ~= 0 and currentAssault ~= missionId then
                        p:delAssault(currentAssault)
                    end

                    if p:getCurrentAssault() ~= missionId then
                        p:addAssault(missionId)
                    end

                    p:completeAssault(missionId)
                    state.assaultsAdded = state.assaultsAdded + 1
                end
            end,
        },
        {
            name = 'Records of Eminence',
            ids = roeRecords,
            batch = 20,
            process = function(p, recordId)
                if not p:getEminenceCompleted(recordId) then
                    p:setEminenceCompleted(recordId)
                    state.roeAdded = state.roeAdded + 1
                end
            end,
        },
        {
            name = 'claimed Deeds',
            ids = deedBits,
            batch = 24,
            process = function(p, deedBit)
                p:setClaimedDeed(deedBit)
            end,
        },
        {
            name = 'titles',
            ids = titles,
            batch = 20,
            process = function(p, titleId)
                if not p:hasTitle(titleId) then
                    p:addTitle(titleId)
                end
            end,
        },
        {
            name = 'learned weapon skills',
            ids = weaponSkills,
            batch = 24,
            process = function(p, wsUnlockId)
                p:addLearnedWeaponskill(wsUnlockId)
            end,
        },
        {
            name = 'zone visitation',
            ids = { 1 },
            batch = 1,
            process = function(p)
                if
                    xi.twills_admin.native and
                    type(xi.twills_admin.native.repairLongTimeRuntimeState) == 'function'
                then
                    state.zoneAdded, state.zoneExpected = xi.twills_admin.native.repairLongTimeRuntimeState(p)
                end
            end,
        },
    }

    local stageIndex = 1
    local function runNextBatch(playerArg)
        if playerArg == nil then
            return
        end

        local stage = stages[stageIndex]
        if stage == nil then
            local deedCount = countClaimedDeeds(playerArg)
            local titleFound, titleTotal = countLocalTitles(playerArg)
            local wsFound, wsTotal = countLearnedWeaponSkills(playerArg)
            playerArg:setCharVar(longTimeRepairActiveVar, 0)
            playerArg:printToPlayer(string.format(
                'Twills long-time v9 repair complete: +%i/%i KIs, +%i/%i Assault, +%i/%i RoE, Deeds %i/%i, zones +%i/%i, titles %i/%i, WS %i/%i.',
                state.keyItemsAdded,
                state.keyItemsTotal,
                state.assaultsAdded,
                state.assaultsTotal,
                state.roeAdded,
                state.roeTotal,
                deedCount,
                state.deedTarget,
                state.zoneAdded,
                state.zoneExpected,
                titleFound,
                titleTotal,
                wsFound,
                wsTotal
            ), xi.msg.channel.SYSTEM_3)
            return
        end

        stage.index = stage.index or 1
        local processed = 0
        while processed < stage.batch and stage.index <= #stage.ids do
            stage.process(playerArg, stage.ids[stage.index])
            stage.index = stage.index + 1
            processed = processed + 1
        end

        if stage.index > #stage.ids then
            stageIndex = stageIndex + 1
        end

        playerArg:timer(250, runNextBatch)
    end

    player:timer(250, runNextBatch)
    return true
end

local function _legacyRepairLongTimeContent(player)
    local queued = queueLongTimeContentRepair(player)
    local keyItemsFound, keyItemsTotal = countLongTimeKeyItems(player, isLongTimeKeyItem)
    local assaultsFound, assaultsTotal = countAssaultProgress(player)
    local roeFound, roeTotal = countStableRoeProgress(player)
    local deedCount = countClaimedDeeds(player)
    local deedTarget = math.min(math.floor(player:getCurrency('deeds') / 10), 144)
    local titleFound, titleTotal = countLocalTitles(player)
    local wsFound, wsTotal = countLearnedWeaponSkills(player)

    return
    {
        queued = queued,
        keyItemsAdded = 0,
        keyItemsTotal = keyItemsTotal,
        keyItemsFound = keyItemsFound,
        assaultsAdded = 0,
        assaultsTotal = assaultsTotal,
        assaultsFound = assaultsFound,
        roeAdded = 0,
        roeTotal = roeTotal,
        roeFound = roeFound,
        deedCount = deedCount,
        deedTarget = deedTarget,
        titleAdded = 0,
        titleTotal = titleTotal,
        titleFound = titleFound,
        wsFound = wsFound,
        wsTotal = wsTotal,
        zoneAdded = 0,
        zoneExpected = 0,
    }
end

local function auditLine(ok, label, details)
    return string.format('%s %s: %s', ok and '[OK]' or '[FIX]', label, details)
end

local function _legacyAuditLongTimeContent(player)
    local rows = {}

    local atmaFound, atmaTotal = countLongTimeKeyItems(player, function(name)
        return string.match(name, '^ATMA_OF_') ~= nil
    end)

    table.insert(rows, auditLine(atmaFound == atmaTotal, 'Abyssea Atma', string.format('%i/%i locally defined Atma key items present', atmaFound, atmaTotal)))

    local abyssiteFound, abyssiteTotal = countLongTimeKeyItems(player, function(name)
        return string.find(name, 'ABYSSITE', 1, true) ~= nil
    end)

    table.insert(rows, auditLine(abyssiteFound == abyssiteTotal, 'Abyssea Abyssite', string.format('%i/%i locally defined abyssite key items present', abyssiteFound, abyssiteTotal)))

    for _, groupName in ipairs({ 'Escha', 'Odyssey', 'Ambuscade', 'Dynamis' }) do
        local found, total, missing = countGateGroup(player, groupName)
        table.insert(rows, auditLine(found == total, groupName .. ' Gates', string.format('%i/%i local gate key items present%s', found, total, #missing > 0 and ('; missing ' .. table.concat(missing, ', ')) or '')))
    end

    local assaultComplete, assaultTotal = countAssaultProgress(player)
    table.insert(rows, auditLine(assaultComplete == assaultTotal, 'Assault Progression', string.format('%i/%i local Assault missions complete', assaultComplete, assaultTotal)))

    local campaignMissions = xi.mission.id[xi.mission.area[xi.mission.log_id.CAMPAIGN]] or {}
    local campaignSupported = next(campaignMissions) ~= nil
    table.insert(rows, auditLine(true, 'Campaign Progression', campaignSupported and 'local Campaign missions are represented for future repair' or 'unsupported locally; Campaign mission table is intentionally empty'))

    local roeComplete, roeTotal = countStableRoeProgress(player)
    table.insert(rows, auditLine(roeComplete == roeTotal, 'Records of Eminence', string.format('%i/%i stable non-repeat local records complete', roeComplete, roeTotal)))

    local deedCount = countClaimedDeeds(player)
    local deedTarget = math.min(math.floor(player:getCurrency('deeds') / 10), 144)
    table.insert(rows, auditLine(deedCount >= deedTarget, 'Claimed Deeds', string.format('%i/%i claim bits set from current Deeds balance', deedCount, deedTarget)))

    local titleFound, titleTotal = countLocalTitles(player)
    table.insert(rows, auditLine(titleFound == titleTotal, 'Titles', string.format('%i/%i local title-history entries present', titleFound, titleTotal)))

    local wsFound, wsTotal = countLearnedWeaponSkills(player)
    table.insert(rows, auditLine(wsFound == wsTotal, 'Learned Weapon Skills', string.format('%i/%i local learned weapon-skill unlocks present', wsFound, wsTotal)))

    local sortieFound, sortieTotal = countLongTimeKeyItems(player, function(name)
        return string.find(name, 'SORTIE', 1, true) ~= nil
    end)

    table.insert(rows, auditLine(true, 'Sortie Progression', sortieTotal > 0 and string.format('%i/%i local Sortie key items present', sortieFound, sortieTotal) or 'no local Sortie key-item progression enum; Gallimaufry/canteen currency remains the supported evidence'))

    return rows
end

local function ensureRetailStorageGates(player)
    local inventoryAdjustment = targetInventorySize - player:getContainerSize(xi.inv.INVENTORY)
    if inventoryAdjustment > 0 then
        player:changeContainerSize(xi.inv.INVENTORY, inventoryAdjustment)
    end

    for _, containerId in ipairs({
        xi.inv.MOGSAFE,
        xi.inv.MOGLOCKER,
        xi.inv.MOGSATCHEL,
        xi.inv.MOGSACK,
        xi.inv.MOGCASE,
        xi.inv.WARDROBE,
        xi.inv.WARDROBE2,
        xi.inv.WARDROBE3,
        xi.inv.WARDROBE4,
        xi.inv.WARDROBE5,
        xi.inv.WARDROBE6,
        xi.inv.WARDROBE7,
        xi.inv.WARDROBE8,
    }) do
        local adjustment = targetWardrobeSize - player:getContainerSize(containerId)
        if adjustment > 0 then
            player:changeContainerSize(containerId, adjustment)
        end
    end

    xi.moghouse.unlockMogLocker(player)
    xi.moghouse.setMogLockerAccessType(player, xi.moghouse.lockerAccessType.ALLAREAS)
    xi.moghouse.addMogLockerExpiryTime(player, targetLockerLeaseBronze)

    for _, questId in ipairs(gobbieBagQuests) do
        if
            questId ~= nil and
            not player:hasCompletedQuest(xi.questLog.JEUNO, questId)
        then
            player:completeQuest(xi.questLog.JEUNO, questId)
        end
    end
end

local function setMaxFame(player)
    for _, fameArea in pairs(xi.fameArea) do
        local value = targetFameValue
        if
            fameArea >= xi.fameArea.ABYSSEA_KONSCHTAT and
            fameArea <= xi.fameArea.ABYSSEA_ULEGUERAND
        then
            value = targetAbysseaFameValue
        end

        player:setFame(fameArea, value)
    end
end

local function _legacyCompleteKnownMissions(player)
    local completed = 0
    local terminal = 0

    for logId, areaName in pairs(xi.mission.area) do
        if
            logId ~= xi.mission.log_id.ASSAULT and
            logId ~= xi.mission.log_id.CAMPAIGN
        then
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
                        if not player:hasCompletedMission(logId, missionId) then
                            if player:getCurrentMission(logId) ~= missionId then
                                player:addMission(logId, missionId)
                            end

                            player:completeMission(logId, missionId)
                            completed = completed + 1
                        end
                    end
                end

                if usesCurrentProgress and maxMissionId > 0 then
                    -- CoP reaches the engine's MAX_MISSIONID boundary at 850, so
                    -- current=850 represents terminal progression through Dawn
                    -- while The Last Verse remains the terminal current marker.
                    local terminalMission = math.min(maxMissionId + 1, 850)
                    if player:getCurrentMission(logId) ~= terminalMission then
                        player:addMission(logId, terminalMission)
                    end

                    player:setMissionStatus(logId, 0)
                    terminal = terminal + 1
                end
            end
        end
    end

    return completed, terminal
end

local function addTeleportIfMissing(player, teleType, bitVal, setVal)
    if setVal ~= nil then
        if not player:hasTeleport(teleType, bitVal, setVal) then
            player:addTeleport(teleType, bitVal, setVal)
            return 1
        end
    elseif not player:hasTeleport(teleType, bitVal) then
        player:addTeleport(teleType, bitVal)
        return 1
    end

    return 0
end

local function repairTravelUnlocks(player)
    local added = 0

    for region = 0, 18 do
        local bitVal = region + 5
        added = added + addTeleportIfMissing(player, xi.teleport.type.OUTPOST_SANDORIA, bitVal)
        added = added + addTeleportIfMissing(player, xi.teleport.type.OUTPOST_BASTOK, bitVal)
        added = added + addTeleportIfMissing(player, xi.teleport.type.OUTPOST_WINDURST, bitVal)
    end

    for _, bitVal in pairs(xi.teleport.runic_portal) do
        added = added + addTeleportIfMissing(player, xi.teleport.type.RUNIC_PORTAL, bitVal)
    end

    for bitVal = 0, 8 do
        added = added + addTeleportIfMissing(player, xi.teleport.type.PAST_MAW, bitVal)
    end

    for bitVal = 1, 20 do
        added = added + addTeleportIfMissing(player, xi.teleport.type.CAMPAIGN_SANDORIA, bitVal)
        added = added + addTeleportIfMissing(player, xi.teleport.type.CAMPAIGN_BASTOK, bitVal)
        added = added + addTeleportIfMissing(player, xi.teleport.type.CAMPAIGN_WINDURST, bitVal)
    end

    for setVal = 0, 8 do
        for bitVal = 0, 7 do
            player:addTeleport(xi.teleport.type.ABYSSEA_CONFLUX, bitVal, setVal)
        end
    end

    for bitVal = 0, 54 do
        added = added + addTeleportIfMissing(player, xi.teleport.type.WAYPOINT, bitVal)
    end

    player:setTeleportMenu(xi.teleport.type.WAYPOINT, true)

    for bitVal = 0, 31 do
        player:addTeleport(xi.teleport.type.ESCHAN_PORTAL, bitVal)
    end

    return added
end

local function repairUnityAndLimitedTrusts(player)
    if targetUnityLeader ~= nil then
        player:setUnityLeader(targetUnityLeader)
    end

    if
        xi.settings.main.ENABLE_LIMITED_TIME_TRUST ~= 0 and
        not player:hasSpell(corneliaSpellId)
    then
        player:addSpell(corneliaSpellId, { silentLog = true, saveToDB = true, sendUpdate = true })
    end
end

local function _legacyCompleteKnownQuests(player)
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

local function ensureCustomChocobo(player)
    if
        xi.twills_admin.native and
        type(xi.twills_admin.native.repairChocobo) == 'function'
    then
        player:registerChocobo(xi.chocobo.color.BLACK, { largeTalons = true, fullTail = true, largeBeak = true })
        return xi.twills_admin.native.repairChocobo(player:getID())
    end

    local choco =
    {
        first_name         = 'Mochi',
        last_name          = 'Galloper',
        sex                = xi.chocoboRaising.gender.FEMALE,
        created            = GetSystemTime() - (xi.chocoboRaising.dayLength * xi.chocoboRaising.daysToAdult3),
        last_update_age    = xi.chocoboRaising.daysToAdult3,
        stage              = xi.chocoboRaising.stage.ADULT_3,
        location           = xi.chocoboRaising.raisingLocation[xi.zone.SOUTHERN_SAN_DORIA],
        color              = xi.chocoboRaising.color.BLACK,
        allele1            = 1,
        allele2            = 1,
        allele3            = 1,
        strength           = 255,
        endurance          = 255,
        discernment        = 159,
        receptivity        = 159,
        affection          = 255,
        energy             = 100,
        satisfaction       = 255,
        conditions         = 0,
        ability1           = xi.chocoboRaising.ability.GALLOP,
        ability2           = xi.chocoboRaising.ability.CANTER,
        personality        = xi.chocoboRaising.temperament.VERY_PATIENT,
        weather_preference = xi.chocoboRaising.weather.CLEAR,
        hunger             = xi.chocoboRaising.hunger.COMPLETELY_FULL,
        care_plan          = 0,
        held_item          = 0,
    }

    local raised = player:setChocoboRaisingInfo(choco)
    player:registerChocobo(xi.chocobo.color.BLACK, { largeTalons = true, fullTail = true, largeBeak = true })

    return raised
end

local function _legacyGrantRdmSchGear(player)
    if player:getCharVar(varGearVersion) >= targetGearVersion then
        return 0, 0
    end

    local granted = 0
    local failed = 0

    if
        xi.twills_admin.native and
        type(xi.twills_admin.native.grantGear) == 'function'
    then
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
        player:setCharVar(varGearVersion, targetGearVersion)
    end

    return granted, failed
end

local function _legacyGrantProfessionItems(player)
    if
        xi.twills_admin.native and
        type(xi.twills_admin.native.grantGear) == 'function'
    then
        return xi.twills_admin.native.grantGear(player, professionItems)
    end

    local granted = 0
    local failed = 0

    for _, item in ipairs(professionItems) do
        if not player:hasItem(item.id) then
            local addedItem = player:addItem({ id = item.id, quantity = item.quantity or 1, silent = true })
            if addedItem ~= nil then
                granted = granted + 1
            else
                failed = failed + 1
            end
        end
    end

    return granted, failed
end

local function repairCore(player)
    if not player or player:getName() ~= adminName then
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
    if
        xi.twills_admin.native and
        type(xi.twills_admin.native.repairCoreState) == 'function'
    then
        nativeDbRepaired = xi.twills_admin.native.repairCoreState(player:getID())
    end

    callHelper(player, commandHelpers.addAllMaps)
    callHelper(player, commandHelpers.addAllWarps)
    callHelper(player, commandHelpers.addAllMounts)
    callHelper(player, commandHelpers.addAllAttachments)
    callHelper(player, commandHelpers.addAllWeaponSkills)
    local travelAdded = repairTravelUnlocks(player)

    addAllSpells.onTrigger(player)
    commandHelpers.addAllTrusts.onTrigger(player)
    repairUnityAndLimitedTrusts(player)
    local addedKeyItems = addRequiredKeyItems(player)

    player:setCurrency('alter_ego_points', targetAlterEgoPoints)
    player:setJobPoints(targetJobPoints)
    player:setCapacityPoints(targetCapacityPoints)

    local chocoboRepaired = ensureCustomChocobo(player)

    player:setCharVar(varVersion, currentBootVersion)

    player:printToPlayer(string.format(
        'Twills explicit core repair v%i complete: ML%i RDM/SCH foundation, %i travel unlocks refreshed, %i supported key items, chocobo %s, privileges kept, GM icon hidden. Merits, veteran metadata, currencies, missions, quests, content rewards, and gear were not changed. Relog to refresh client-side views.',
        currentBootVersion,
        targetMasterLevel,
        travelAdded,
        addedKeyItems,
        chocoboRepaired and 'ready' or 'not repaired'
    ), xi.msg.channel.SYSTEM_3)

    return nativeDbRepaired
end

xi.twills_admin = xi.twills_admin or {}
xi.twills_admin.adminName = adminName
xi.twills_admin.currentVersion = currentBootVersion
xi.twills_admin.repairCore = repairCore
xi.twills_admin.contentRegistry = contentRegistry

return m
