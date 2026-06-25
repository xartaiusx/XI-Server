-- Mochirii Trust retail parity.
-- Valaineral source basis:
-- - Official Trust guide: Trusts have distinct roles and behavior.
-- - BG Wiki Valaineral: PLD/WAR, Banish III, Palisade, Uriel Blade, support PLD kit.
-- Keep this idempotent for dbtool.py update.

INSERT INTO `mob_spell_lists` (`spell_list_name`, `spell_list_id`, `spell_id`, `min_level`, `max_level`)
VALUES ('TRUST_Valaineral', 322, 30, 65, 255) -- Banish III
ON DUPLICATE KEY UPDATE
    `spell_list_name` = VALUES(`spell_list_name`),
    `min_level`       = VALUES(`min_level`),
    `max_level`       = VALUES(`max_level`);

-- Current 17-Trust QA alliance parity data.  These rows keep gambit spell
-- casts and TP skills aligned with local Mochirii data before full testing.
INSERT INTO `mob_spell_lists` (`spell_list_name`, `spell_list_id`, `spell_id`, `min_level`, `max_level`)
VALUES
    ('TRUST_Yoran-Oran_UC', 393, 54, 28, 255), -- Stoneskin
    ('TRUST_Sylvie_UC',    394, 143, 32, 255), -- Erase
    ('TRUST_Koru-Moru',    364, 58,  6, 255), -- Paralyze
    ('TRUST_Koru-Moru',    364, 80, 75, 255), -- Paralyze II
    ('TRUST_Koru-Moru',    364, 216, 21, 255), -- Gravity
    ('TRUST_Koru-Moru',    364, 217, 98, 255), -- Gravity II
    ('TRUST_Koru-Moru',    364, 253, 25, 255), -- Sleep
    ('TRUST_Koru-Moru',    364, 258, 11, 255), -- Bind
    ('TRUST_Koru-Moru',    364, 259, 46, 255), -- Sleep II
    ('TRUST_Koru-Moru',    364, 286, 83, 255), -- Addle
    ('TRUST_Koru-Moru',    364, 843, 42, 255), -- Frazzle
    ('TRUST_Koru-Moru',    364, 844, 92, 255), -- Frazzle II
    ('TRUST_Joachim',      323, 462, 33, 255), -- Magic Finale
    ('TRUST_Matsui-P',     435, 338, 12, 255), -- Utsusemi: Ichi
    ('TRUST_Matsui-P',     435, 339, 37, 255), -- Utsusemi: Ni
    ('TRUST_Matsui-P',     435, 341, 30, 255), -- Jubaku: Ichi
    ('TRUST_Matsui-P',     435, 342, 65, 255), -- Jubaku: Ni
    ('TRUST_Matsui-P',     435, 344, 23, 255), -- Hojo: Ichi
    ('TRUST_Matsui-P',     435, 345, 48, 255), -- Hojo: Ni
    ('TRUST_Matsui-P',     435, 347, 19, 255), -- Kurayami: Ichi
    ('TRUST_Matsui-P',     435, 348, 44, 255), -- Kurayami: Ni
    ('TRUST_Matsui-P',     435, 350, 27, 255), -- Dokumori: Ichi
    ('TRUST_Matsui-P',     435, 351, 56, 255)  -- Dokumori: Ni
ON DUPLICATE KEY UPDATE
    `spell_list_name` = VALUES(`spell_list_name`),
    `min_level`       = VALUES(`min_level`),
    `max_level`       = VALUES(`max_level`);

UPDATE `mob_pools`
SET
    `spellList` = 435,
    `skill_list_id` = 1148
WHERE
    `poolid` = 6003 AND
    `name` = 'matsui-p' AND
    `packet_name` = 'Matsui-P';

INSERT INTO `mob_skill_lists` (`skill_list_name`, `skill_list_id`, `mob_skill_id`)
VALUES
    ('TRUST_Matsui-P',     1148, 128), -- Blade: Rin
    ('TRUST_Matsui-P',     1148, 129), -- Blade: Retsu
    ('TRUST_Matsui-P',     1148, 133), -- Blade: Ei
    ('TRUST_Matsui-P',     1148, 134), -- Blade: Jin
    ('TRUST_Matsui-P',     1148, 136), -- Blade: Ku
    ('TRUST_Matsui-P',     1148, 138), -- Blade: Kamu
    ('TRUST_Matsui-P',     1148, 141), -- Blade: Shun
    ('TRUST_Lilisette_II', 1128, 23),  -- Dancing Edge
    ('TRUST_Lilisette_II', 1128, 25),  -- Evisceration
    ('TRUST_Lilisette_II', 1128, 29),  -- Pyrrhic Kleos
    ('TRUST_Lilisette_II', 1128, 30),  -- Aeolian Edge
    ('TRUST_Lilisette_II', 1128, 31),  -- Rudra's Storm
    ('TRUST_Lilisette_II', 1128, 224), -- Exenterator
    ('TRUST_Selh_teus',    1094, 1508), -- Luminous Lance
    ('TRUST_Selh_teus',    1094, 1509), -- Rejuvenation
    ('TRUST_Selh_teus',    1094, 1510)  -- Revelation
ON DUPLICATE KEY UPDATE
    `skill_list_name` = VALUES(`skill_list_name`);

-- Kupipi source basis:
-- - BG Wiki Kupipi: WHM healer with Cure I-VI, Protect/Protectra I-V,
--   Shell/Shellra I-V, status removals, Erase, Slow, Paralyze, Starlight,
--   and Moonlight.
-- - Local Mochirii data already includes Cure, Protectra, Shellra, -na spells, Erase,
--   Slow, Paralyze, Flash, Starlight, and Moonlight.
-- - Local Mochirii Adelheid data uses Scholar Arts/Addendum and Storm gambits safely.
-- - Mochirii player-like extension keeps Kupipi backline but fills safe WHM
--   and SCH/49 tools that this checkout already supports.
-- - Esuna is deliberately spell-list only until a Trust-safe party-targeting
--   helper is added for its caster-centered script.
-- - Sacrifice is deferred because this checkout's mob spell container does not
--   classify it into a castable mob spell bucket.
UPDATE `mob_pools`
SET `sJob` = 20
WHERE
    `poolid` = 5898 AND
    `name` = 'kupipi' AND
    `packet_name` = 'Kupipi' AND
    `mJob` = 3;

DELETE FROM `mob_spell_lists`
WHERE
    `spell_list_id` = 310 AND
    `spell_id` = 94; -- Sacrifice is not a clean mob-castable spell in this checkout.

INSERT INTO `mob_spell_lists` (`spell_list_name`, `spell_list_id`, `spell_id`, `min_level`, `max_level`)
VALUES
    ('TRUST_Kupipi', 310,  7, 16, 255), -- Curaga
    ('TRUST_Kupipi', 310,  8, 31, 255), -- Curaga II
    ('TRUST_Kupipi', 310,  9, 51, 255), -- Curaga III
    ('TRUST_Kupipi', 310, 10, 71, 255), -- Curaga IV
    ('TRUST_Kupipi', 310, 11, 91, 255), -- Curaga V
    ('TRUST_Kupipi', 310, 12, 25, 255), -- Raise
    ('TRUST_Kupipi', 310, 13, 56, 255), -- Raise II
    ('TRUST_Kupipi', 310, 23,  3, 255), -- Dia
    ('TRUST_Kupipi', 310, 24, 36, 255), -- Dia II
    ('TRUST_Kupipi', 310, 43,  7, 255), -- Protect
    ('TRUST_Kupipi', 310, 44, 27, 255), -- Protect II
    ('TRUST_Kupipi', 310, 45, 47, 255), -- Protect III
    ('TRUST_Kupipi', 310, 46, 63, 255), -- Protect IV
    ('TRUST_Kupipi', 310, 47, 76, 255), -- Protect V
    ('TRUST_Kupipi', 310, 48, 17, 255), -- Shell
    ('TRUST_Kupipi', 310, 49, 37, 255), -- Shell II
    ('TRUST_Kupipi', 310, 50, 57, 255), -- Shell III
    ('TRUST_Kupipi', 310, 51, 68, 255), -- Shell IV
    ('TRUST_Kupipi', 310, 52, 76, 255), -- Shell V
    ('TRUST_Kupipi', 310, 53, 29, 255), -- Blink
    ('TRUST_Kupipi', 310, 54, 44, 255), -- Stoneskin
    ('TRUST_Kupipi', 310, 55, 10, 255), -- Aquaveil
    ('TRUST_Kupipi', 310, 57, 40, 255), -- Haste
    ('TRUST_Kupipi', 310, 66, 17, 255), -- Barfira
    ('TRUST_Kupipi', 310, 67, 21, 255), -- Barblizzara
    ('TRUST_Kupipi', 310, 68, 13, 255), -- Baraera
    ('TRUST_Kupipi', 310, 69,  5, 255), -- Barstonra
    ('TRUST_Kupipi', 310, 70, 25, 255), -- Barthundra
    ('TRUST_Kupipi', 310, 71,  9, 255), -- Barwatera
    ('TRUST_Kupipi', 310, 85, 78, 255), -- Baramnesra
    ('TRUST_Kupipi', 310, 86,  7, 255), -- Barsleepra
    ('TRUST_Kupipi', 310, 87, 10, 255), -- Barpoisonra
    ('TRUST_Kupipi', 310, 88, 12, 255), -- Barparalyzra
    ('TRUST_Kupipi', 310, 89, 18, 255), -- Barblindra
    ('TRUST_Kupipi', 310, 90, 23, 255), -- Barsilencera
    ('TRUST_Kupipi', 310, 91, 43, 255), -- Barpetra
    ('TRUST_Kupipi', 310, 93, 40, 255), -- Cura
    ('TRUST_Kupipi', 310, 95, 61, 255), -- Esuna
    ('TRUST_Kupipi', 310, 96, 55, 255), -- Auspice
    ('TRUST_Kupipi', 310, 98, 48, 255), -- Repose
    ('TRUST_Kupipi', 310, 99, 41, 255), -- Sandstorm
    ('TRUST_Kupipi', 310, 108, 21, 255), -- Regen
    ('TRUST_Kupipi', 310, 110, 44, 255), -- Regen II
    ('TRUST_Kupipi', 310, 111, 66, 255), -- Regen III
    ('TRUST_Kupipi', 310, 113, 42, 255), -- Rainstorm
    ('TRUST_Kupipi', 310, 114, 43, 255), -- Windstorm
    ('TRUST_Kupipi', 310, 115, 44, 255), -- Firestorm
    ('TRUST_Kupipi', 310, 116, 45, 255), -- Hailstorm
    ('TRUST_Kupipi', 310, 117, 46, 255), -- Thunderstorm
    ('TRUST_Kupipi', 310, 118, 47, 255), -- Voidstorm
    ('TRUST_Kupipi', 310, 119, 48, 255), -- Aurorastorm
    ('TRUST_Kupipi', 310, 135, 25, 255), -- Reraise
    ('TRUST_Kupipi', 310, 136, 25, 255), -- Invisible
    ('TRUST_Kupipi', 310, 137, 20, 255), -- Sneak
    ('TRUST_Kupipi', 310, 138, 15, 255), -- Deodorize
    ('TRUST_Kupipi', 310, 140, 70, 255), -- Raise III
    ('TRUST_Kupipi', 310, 141, 56, 255), -- Reraise II
    ('TRUST_Kupipi', 310, 142, 70, 255), -- Reraise III
    ('TRUST_Kupipi', 310, 278, 18, 255), -- Geohelix
    ('TRUST_Kupipi', 310, 279, 20, 255), -- Hydrohelix
    ('TRUST_Kupipi', 310, 280, 22, 255), -- Anemohelix
    ('TRUST_Kupipi', 310, 281, 24, 255), -- Pyrohelix
    ('TRUST_Kupipi', 310, 282, 26, 255), -- Cryohelix
    ('TRUST_Kupipi', 310, 283, 28, 255), -- Ionohelix
    ('TRUST_Kupipi', 310, 284, 30, 255), -- Noctohelix
    ('TRUST_Kupipi', 310, 285, 32, 255), -- Luminohelix
    ('TRUST_Kupipi', 310, 286, 83, 255), -- Addle
    ('TRUST_Kupipi', 310, 287, 46, 255), -- Klimaform
    ('TRUST_Kupipi', 310, 474, 83, 255), -- Cura II
    ('TRUST_Kupipi', 310, 475, 96, 255), -- Cura III
    ('TRUST_Kupipi', 310, 477, 86, 255), -- Regen IV
    ('TRUST_Kupipi', 310, 484, 84, 255), -- Boost-MND
    ('TRUST_Kupipi', 310, 494, 99, 255), -- Arise
    ('TRUST_Kupipi', 310, 848, 99, 255)  -- Reraise IV
ON DUPLICATE KEY UPDATE
    `spell_list_name` = VALUES(`spell_list_name`),
    `min_level`       = VALUES(`min_level`),
    `max_level`       = VALUES(`max_level`);
