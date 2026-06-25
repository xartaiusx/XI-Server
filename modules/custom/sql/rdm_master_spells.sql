-- Mochirii RDM job point gift spells.
--
-- Twills receives these through Mochirii's Red Mage job point gift path:
-- Addle II, Distract III, and Frazzle III at 550 spent JP; Refresh III and
-- Temper II at 1200 spent JP.  The base spell_list data only has commented
-- placeholder rows for several of these, so define the castable spell rows here
-- without editing base SQL.

INSERT INTO `spell_list`
    (`spellid`, `name`, `jobs`, `group`, `family`, `element`, `zonemisc`,
     `validTargets`, `skill`, `mpCost`, `castTime`, `recastTime`, `message`,
     `magicBurstMessage`, `animation`, `animationTime`, `AOE`, `base`,
     `multiplier`, `CE`, `VE`, `requirements`, `spell_range`, `radius`,
     `content_tag`)
VALUES
    (882, 'distract_iii', 0x00000000630000000000000000000000000000000000,
     6, 154, 2, 0, 4, 35, 84, 3000, 10000, 0, 0, 288, 1000, 0, 0,
     1.00, 1, 320, 0, 200, 0, 'SOA'),
    (883, 'frazzle_iii', 0x00000000630000000000000000000000000000000000,
     6, 155, 8, 0, 4, 35, 90, 3000, 10000, 0, 0, 288, 1000, 0, 0,
     1.00, 1, 320, 0, 200, 0, 'SOA'),
    (884, 'addle_ii', 0x00000000630000000000000000000000000000000000,
     6, 84, 1, 0, 4, 35, 63, 2000, 20000, 0, 0, 288, 1000, 0, 0,
     1.00, 1, 176, 0, 200, 0, 'SOA'),
    (894, 'refresh_iii', 0x00000000630000000000000000000000000000000000,
     6, 29, 7, 0, 3, 34, 80, 5000, 36000, 0, 0, 288, 1012, 0, 0,
     1.00, 1, 165, 0, 200, 0, 'SOA')
ON DUPLICATE KEY UPDATE
    `name`              = VALUES(`name`),
    `jobs`              = VALUES(`jobs`),
    `group`             = VALUES(`group`),
    `family`            = VALUES(`family`),
    `element`           = VALUES(`element`),
    `zonemisc`          = VALUES(`zonemisc`),
    `validTargets`      = VALUES(`validTargets`),
    `skill`             = VALUES(`skill`),
    `mpCost`            = VALUES(`mpCost`),
    `castTime`          = VALUES(`castTime`),
    `recastTime`        = VALUES(`recastTime`),
    `message`           = VALUES(`message`),
    `magicBurstMessage` = VALUES(`magicBurstMessage`),
    `animation`         = VALUES(`animation`),
    `animationTime`     = VALUES(`animationTime`),
    `AOE`               = VALUES(`AOE`),
    `base`              = VALUES(`base`),
    `multiplier`        = VALUES(`multiplier`),
    `CE`                = VALUES(`CE`),
    `VE`                = VALUES(`VE`),
    `requirements`      = VALUES(`requirements`),
    `spell_range`       = VALUES(`spell_range`),
    `radius`            = VALUES(`radius`),
    `content_tag`       = VALUES(`content_tag`);
