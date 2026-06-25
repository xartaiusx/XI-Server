-----------------------------------
-- func: trustparty
-- desc: Inspect and repair active Trust retail parity profiles.
-----------------------------------
---@type TCommand
local commandObj = {}

commandObj.cmdprops =
{
    permission = 5,
    parameters = 'ss',
}

local function printLine(player, line)
    player:printToPlayer(line, xi.msg.channel.SYSTEM_3, '')
end

local function printClientSummary(player, line)
    local text = tostring(line or '')
    if #text > 180 then
        text = text:sub(1, 177) .. '...'
    end

    printLine(player, text)
end

local function ensureModule()
    if xi.trustRetailParity ~= nil and xi.trustRetailParity.partyRows ~= nil then
        return xi.trustRetailParity
    end

    require('modules/custom/lua/trust_retail_parity')
    return xi.trustRetailParity
end

local function printRows(player, rows)
    local clientRows = 0
    for _, row in ipairs(rows) do
        print('Mochirii TrustParty: ' .. row)
        if clientRows < 6 then
            printClientSummary(player, row)
            clientRows = clientRows + 1
        end
    end

    if #rows > clientRows then
        printLine(player, string.format('%u more row(s) written to the map log and Trust parity report.', #rows - clientRows))
    end
end

commandObj.onTrigger = function(player, action, target)
    local parity = ensureModule()

    if action == nil or action == 'status' then
        printLine(player, 'Active Trust retail parity status:')
        printRows(player, parity.partyRows(player, false))
        return
    end

    if action == 'repair' then
        if parity.isQaSummonRunning ~= nil and parity.isQaSummonRunning(player) then
            printLine(player, 'Mochirii Trust QA summon is still running. Wait for the completion message before repair.')
            return
        end

        printLine(player, 'Applying active Trust retail parity repair:')
        printRows(player, parity.partyRows(player, true))
        return
    end

    if action == 'audit' then
        if
            (target == nil or target == 'active') and
            parity.isQaSummonRunning ~= nil and
            parity.isQaSummonRunning(player)
        then
            local active = 0
            local expected = 0
            if parity.qaAllianceReady ~= nil then
                local _
                _, active, expected = parity.qaAllianceReady(player)
            end

            printLine(player, string.format(
                'Mochirii Trust QA summon is still running (%u/%u active). Wait before audit active.',
                active,
                expected
            ))
            return
        end

        printRows(player, parity.auditRows(player, target or 'active'))
        return
    end

    if action == 'composition' then
        if parity.compositionRows == nil then
            printLine(player, 'Trust QA composition helper is not available.')
            return
        end

        printRows(player, parity.compositionRows())
        return
    end

    if action == 'summonqa' then
        if parity.autoSummonQaParty == nil then
            printLine(player, 'Trust QA summon helper is not available.')
            return
        end

        if parity.isQaSummonRunning ~= nil and parity.isQaSummonRunning(player) then
            local active = 0
            local expected = 0
            if parity.qaAllianceReady ~= nil then
                local _
                _, active, expected = parity.qaAllianceReady(player)
            end

            printLine(player, string.format(
                'Mochirii Trust QA summon is already running (%u/%u active). Wait for the completion message.',
                active,
                expected
            ))
            return
        end

        printLine(player, 'Starting Mochirii Trust QA summon sequence.')
        printLine(player, 'Do not run repair manually; summonqa auto-repairs once all Trusts are active.')
        parity.autoSummonQaParty(player)
        return
    end

    printLine(player, '!trustparty status')
    printLine(player, '!trustparty repair')
    printLine(player, '!trustparty audit active|all|<trust>')
    printLine(player, '!trustparty composition')
    printLine(player, '!trustparty summonqa')
end

return commandObj
