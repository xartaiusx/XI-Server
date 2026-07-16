-----------------------------------
-- func: twillsrepair
-- desc: Runs one explicit, reviewable Twills repair surface.
-----------------------------------
---@type TCommand
local commandObj = {}

commandObj.cmdprops = {
    permission = 5,
    parameters = 'ss',
}

local function ensureAdminModule()
    if
        xi.twills_admin == nil or
        xi.twills_admin.contentRegistry == nil or
        type(xi.twills_admin.repairCore) ~= 'function'
    then
        require('modules/custom/lua/twills_admin_bootstrap')
    end
end

local function printLine(player, line)
    print('Mochirii TwillsRepair: ' .. line)
    player:printToPlayer(line, xi.msg.channel.SYSTEM_3, '')
end

local function printUsage(player)
    printLine(player, 'Usage: !twillsrepair core|metadata|merits|currency|unsupported --dry-run|gear --dry-run')
    printLine(player, 'No repair runs without an explicit operation. Unsupported/gear apply remains gated by reviewed manifests and GearSwap replacement QA.')
end

local function callNative(target, functionName)
    if
        xi.twills_admin == nil or
        xi.twills_admin.native == nil or
        type(xi.twills_admin.native[functionName]) ~= 'function'
    then
        return false
    end

    return xi.twills_admin.native[functionName](target) == true
end

local function printUnsupportedDryRun(player)
    local registry = xi.twills_admin and xi.twills_admin.contentRegistry
    if registry == nil or registry.systems == nil then
        printLine(player, '[FIX] Content parity registry is not loaded.')
        return
    end

    local count = 0
    for _, system in pairs(registry.systems) do
        if system.repairPolicy == 'quarantine_rewards' or system.repairPolicy == 'reset_cycle_state' then
            count = count + 1
            printLine(player, string.format('[INFO] dry-run %s: status=%s, policy=%s', system.key, system.status, system.repairPolicy))
        end
    end

    printLine(player, string.format('[INFO] %i content systems require the external exact-delta report before any apply.', count))
end

commandObj.onTrigger = function(player, operation, mode)
    if operation == nil then
        printUsage(player)
        return
    end

    ensureAdminModule()

    if xi.twills_admin == nil then
        printLine(player, 'Twills admin module is not loaded.')
        return
    end

    local target = GetPlayerByName(xi.twills_admin.adminName or 'Twills')
    if target == nil then
        printLine(player, 'Twills must be logged in before running !twillsrepair.')
        return
    end

    operation = string.lower(operation)
    mode = mode and string.lower(mode) or nil

    if operation == 'core' then
        if
            type(xi.twills_admin.repairCore) == 'function' and
            xi.twills_admin.repairCore(target)
        then
            printLine(
                player,
                'Twills core repair completed. No merits, veteran metadata, monthly/unsupported currencies, mission/quest completion, or content reward state changed.'
            )
        else
            printLine(player, '[FIX] Twills core repair did not complete; inspect xi_map logs.')
        end
    elseif operation == 'metadata' then
        if callNative(target, 'repairMetadata') then
            printLine(
                player,
                'Twills simulated veteran metadata set to 2011-07-11 and 10,000 hours; last-login timestamps were preserved. This is a documented QA exception.'
            )
        else
            printLine(player, '[FIX] Veteran metadata repair helper is unavailable or failed.')
        end
    elseif operation == 'merits' then
        if callNative(target, 'repairMerits') then
            printLine(player, 'Twills retail-legal merit profile applied and reloaded in server memory. Relog before menu verification.')
        else
            printLine(player, '[FIX] Merit repair helper is unavailable or failed.')
        end
    elseif operation == 'currency' then
        if callNative(target, 'repairCurrencyPolicy') then
            printLine(
                player,
                'Twills currency policy applied: Ballista capped at 2,000; current Ambuscade, Odyssey, Sortie, and current-Limbus balances reset. Unverified Escha balances were preserved for acquisition-path testing.'
            )
        else
            printLine(player, '[FIX] Currency repair helper is unavailable or failed.')
        end
    elseif
        operation == 'unsupported' and
        mode == '--dry-run'
    then
        printUnsupportedDryRun(player)
    elseif
        operation == 'unsupported' and
        mode == '--apply'
    then
        printLine(player, '[FIX] Unsupported-state apply is gated. Generate and review the exact external dry-run plus passing GearSwap replacement QA first.')
    elseif
        operation == 'gear' and
        mode == '--dry-run'
    then
        printLine(
            player,
            '[INFO] Gear repair is audit-only in this gate. Run supported-item, 16-slot, augment, inventory, and model validation before a later explicit apply.'
        )
    elseif operation == 'gear' and mode == '--apply' then
        if type(xi.twills_admin.repairGear) ~= 'function' then
            printLine(player, '[FIX] Supported gear repair helper is unavailable.')
            return
        end

        local repaired, granted = xi.twills_admin.repairGear(target)
        if repaired then
            printLine(player, string.format('Supported GearSwap gear repaired; %i missing item(s) granted.', granted))
        else
            printLine(player, '[FIX] Supported GearSwap gear repair failed; inspect inventory capacity and xi_map logs.')
        end
    else
        printUsage(player)
    end
end

return commandObj
