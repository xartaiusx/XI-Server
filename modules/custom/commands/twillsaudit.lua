-----------------------------------
-- func: twillsaudit
-- desc: Runs explicit Twills core, parity, content, merit, currency, or gear audits.
-----------------------------------
---@type TCommand
local commandObj = {}

commandObj.cmdprops = {
    permission = 5,
    parameters = 'ss',
}

local adminName = 'Twills'

local function ensureAdminModule()
    if
        xi.twills_admin == nil or
        xi.twills_admin.contentRegistry == nil or
        type(xi.twills_admin.repairCore) ~= 'function'
    then
        require('modules/custom/lua/twills_admin_bootstrap')
    end
end

local rdmJobPointSpells = {
    { 'Addle II', 884 },
    { 'Distract III', 882 },
    { 'Frazzle III', 883 },
    { 'Refresh III', 894 },
    { 'Temper II', 895 },
}

local function printLine(player, line)
    print('Mochirii TwillsAudit: ' .. line)
    player:printToPlayer(line, xi.msg.channel.SYSTEM_3, '')
end

local function summarizeRows(player, label, rows)
    local ok = 0
    local fix = 0
    local info = 0
    local importantRows = {}

    for _, row in ipairs(rows) do
        if string.sub(row, 1, 4) == '[OK]' then
            ok = ok + 1
        elseif string.sub(row, 1, 5) == '[FIX]' then
            fix = fix + 1
            table.insert(importantRows, row)
        else
            info = info + 1
            table.insert(importantRows, row)
        end
    end

    printLine(player, string.format('%s: %i OK, %i FIX, %i info', label, ok, fix, info))
    for index = 1, math.min(#importantRows, 6) do
        printLine(player, importantRows[index])
    end

    if #importantRows > 6 then
        printLine(player, string.format('[INFO] %s: %i additional rows are in the map log.', label, #importantRows - 6))
    end
end

local function nativeAudit(player, target, functionName, label)
    if
        xi.twills_admin == nil or
        xi.twills_admin.native == nil or
        type(xi.twills_admin.native[functionName]) ~= 'function'
    then
        printLine(player, string.format('[FIX] %s helper is not loaded; rebuild and restart xi_map.', label))
        return
    end

    summarizeRows(player, label, xi.twills_admin.native[functionName](target:getID()))
end

local function auditCore(player, target)
    nativeAudit(player, target, 'auditDbState', 'Core DB audit')

    local entitlementVar = xi.twills_admin.trustAllianceAccessVar or 'MochiriiTrustAllianceAccess'
    local entitlement = target:getCharVar(entitlementVar)
    local actualGm = target:getGMLevel()
    local visibleGm = target:getVisibleGMLevel()
    local authorized = target:canUseTwillsFullAlliance()
    printLine(player, string.format(
        '%s Twills Trust alliance authorization: entitlement=%u, actual_gm=%u, visible_gm=%u, predicate=%s',
        entitlement == 1 and actualGm == 5 and visibleGm == 0 and authorized and '[OK]' or '[FIX]',
        entitlement,
        actualGm,
        visibleGm,
        authorized and 'authorized' or 'denied'
    ))

    local learned = 0
    local missing = {}
    for _, spell in ipairs(rdmJobPointSpells) do
        if target:hasSpell(spell[2]) then
            learned = learned + 1
        else
            table.insert(missing, spell[1])
        end
    end

    printLine(
        player,
        string.format(
            '%s RDM JP spells: %i/%i learned%s',
            learned == #rdmJobPointSpells and '[OK]' or '[FIX]',
            learned,
            #rdmJobPointSpells,
            #missing > 0 and ('; missing ' .. table.concat(missing, ', ')) or ''
        )
    )
end

local function auditParity(player, target)
    nativeAudit(player, target, 'auditMetadataState', 'Veteran metadata audit')

    local registry = xi.twills_admin and xi.twills_admin.contentRegistry
    if registry == nil or registry.systems == nil then
        printLine(player, '[FIX] Content parity registry is not loaded.')
        return
    end

    local counts = {}
    for _, status in ipairs(registry.allowedStatuses or {}) do
        counts[status] = 0
    end

    for _, system in pairs(registry.systems) do
        counts[system.status] = (counts[system.status] or 0) + 1
    end

    for _, status in ipairs(registry.allowedStatuses or {}) do
        printLine(player, string.format('[INFO] Content parity %s: %i systems', status, counts[status] or 0))
    end
end

local function auditContent(player, key)
    local registry = xi.twills_admin and xi.twills_admin.contentRegistry
    local system = registry and registry.systems and registry.systems[key]
    if system == nil then
        printLine(player, string.format('[FIX] Unknown content key %s. Use the generated runtime parity report for valid keys.', tostring(key)))
        return
    end

    printLine(
        player,
        string.format('[INFO] %s: status=%s, lifecycle=%s, repair=%s', system.name, system.status, system.lifecycle or 'unspecified', system.repairPolicy)
    )
    printLine(player, '[INFO] ' .. system.reason)
end

local function auditGear(player)
    printLine(
        player,
        '[INFO] Gear parity is intentionally external: run GearSwap static QA, visual-model QA, inventory validation, and the unsupported-state dry run before applying reward removals.'
    )
    printLine(player, '[INFO] No content reward is classified as supported solely because Twills owns it.')
end

local function auditMerits(player, target)
    nativeAudit(player, target, 'auditMeritState', 'Merit audit')

    local primer = xi.ki.PRIMER_ON_MARTIAL_TECHNIQUES
    local treatise = xi.ki.TREATISE_ON_MARTIAL_TECHNIQUES
    local hasPrimer = primer ~= nil and target:hasKeyItem(primer)
    local hasTreatise = treatise ~= nil and target:hasKeyItem(treatise)
    printLine(player, string.format(
        '%s Martial Technique capacity: Primer=%s, Treatise=%s; 25 weapon-skill upgrades require both.',
        hasPrimer and hasTreatise and '[OK]' or '[FIX]',
        hasPrimer and 'yes' or 'no',
        hasTreatise and 'yes' or 'no'
    ))
end

local function printUsage(player)
    printLine(player, 'Usage: !twillsaudit core|parity|content <key>|merits|currency|gear')
end

commandObj.onTrigger = function(player, section, argument)
    ensureAdminModule()

    local target = GetPlayerByName(adminName)
    if target == nil then
        printLine(player, 'Twills must be logged in before running !twillsaudit.')
        return
    end

    section = string.lower(section or 'core')
    if section == 'core' then
        auditCore(player, target)
    elseif section == 'parity' then
        auditParity(player, target)
    elseif section == 'content' and argument ~= nil then
        auditContent(player, string.lower(argument))
    elseif section == 'merits' then
        auditMerits(player, target)
    elseif section == 'currency' then
        nativeAudit(player, target, 'auditCurrencyState', 'Currency audit')
    elseif section == 'gear' then
        auditGear(player)
    else
        printUsage(player)
    end
end

return commandObj
