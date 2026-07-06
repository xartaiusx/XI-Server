-- Mochirii Twills GearSwap visible model repair.
-- The Lethargy +2 Red Mage armor rows have complete local stats but shipped
-- with MId=0 placeholders, which makes visible armor slots render invalidly
-- when GearSwap equips them.  Use the implemented Lethargy model already used
-- by local base/+1 Lethargy Sayon rows.

UPDATE `item_equipment`
SET `MId` = 286
WHERE `name` IN (
    'lethargy_chappel_+2',
    'lethargy_sayon_+2',
    'lethargy_gantherots_+2',
    'lethargy_fuseau_+2',
    'lethargy_houseaux_+2'
) AND `MId` = 0;
