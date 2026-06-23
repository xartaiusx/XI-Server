-----------------------------------
-- func: serverbot
-- desc: Manage custom server-wide AI bots.
-----------------------------------
---@type TCommand
local commandObj = {}

commandObj.cmdprops =
{
    permission = 1,
    parameters = 'ssssss',
}

local function printLine(player, line)
    player:printToPlayer(line, xi.msg.channel.SYSTEM_3, '')
end

local function usage(player)
    printLine(player, '!serverbot status')
    printLine(player, '!serverbot reload')
    printLine(player, '!serverbot spawn <profile> [count]')
    printLine(player, '!serverbot despawn <zone|all>')
    printLine(player, '!serverbot trace [zone]')
    printLine(player, '!serverbot profile [profile]')
    printLine(player, '!serverbot rule [zone]')
    printLine(player, '!serverbot camp [zone|camp]')
    printLine(player, '!serverbot strategy [strategy]')
    printLine(player, '!serverbot audit|economy|perf [limit]')
    printLine(player, '!serverbot pause|resume|enable|disable|panic')
    printLine(player, '!serverbot llm on|off')
end

local function canRun(player, bots, action)
    if
        bots.commandAllowed ~= nil and
        not bots.commandAllowed(player, 'serverbot.' .. action, false)
    then
        printLine(player, 'You do not have permission to run that serverbot command.')
        return false
    end

    return true
end

local function printRows(player, title, rows, emptyLine)
    if rows == nil or #rows == 0 then
        printLine(player, emptyLine or 'No rows found.')
        return
    end

    printLine(player, title)
    for _, row in ipairs(rows) do
        printLine(player, row)
    end
end

commandObj.onTrigger = function(player, action, arg1, arg2)
    local bots = xi.server_bots
    if bots == nil then
        printLine(player, 'server_bots module is not loaded.')
        return
    end

    if action == nil or action == 'help' then
        usage(player)
        return
    end

    if action == 'status' then
        if not canRun(player, bots, action) then
            return
        end

        local status = bots.status()
        printLine(player, string.format(
            'Server bots: enabled=%s paused=%s db=%s activeZones=%u activeBots=%u combatBots=%u profiles=%u ruleZones=%u',
            tostring(status.enabled),
            tostring(status.paused),
            tostring(status.dbBacked),
            status.zones,
            status.bots,
            status.combatBots,
            status.profiles,
            status.rules
        ))
        return
    end

    if action == 'reload' then
        if not canRun(player, bots, action) then
            return
        end

        bots.reload()
        bots.despawnZone(player:getZoneID())
        local count, msg = bots.spawnZone(player:getZone(true), player)
        printLine(player, string.format('%s (%u spawned in current zone)', msg, count))
        return
    end

    if action == 'spawn' then
        if not canRun(player, bots, action) then
            return
        end

        local countArg = tonumber(arg2)
        local count, msg = bots.spawnZone(player:getZone(true), player, arg1, countArg)
        printLine(player, string.format('%s (%u active)', msg, count))
        return
    end

    if action == 'despawn' then
        if not canRun(player, bots, action) then
            return
        end

        if arg1 == 'all' then
            printLine(player, string.format('Despawned %u server bots.', bots.despawnAll()))
            return
        end

        local zoneId = tonumber(arg1) or player:getZoneID()
        printLine(player, string.format('Despawned %u server bots in zone %u.', bots.despawnZone(zoneId), zoneId))
        return
    end

    if action == 'trace' then
        if not canRun(player, bots, action) then
            return
        end

        local zoneId = tonumber(arg1) or player:getZoneID()
        printRows(player, string.format('Server bots in zone %u:', zoneId), bots.trace(zoneId), string.format('No active server bots in zone %u.', zoneId))
        return
    end

    if action == 'enable' then
        if not canRun(player, bots, action) then
            return
        end

        bots.setRuntimeEnabled(true)
        printLine(player, 'Server bots enabled.')
        return
    end

    if action == 'disable' then
        if not canRun(player, bots, action) then
            return
        end

        bots.setRuntimeEnabled(false)
        printLine(player, 'Server bots disabled and despawned.')
        return
    end

    if action == 'pause' then
        if not canRun(player, bots, action) then
            return
        end

        bots.pause()
        printLine(player, 'Server bot strategy ticks paused.')
        return
    end

    if action == 'resume' then
        if not canRun(player, bots, action) then
            return
        end

        bots.resume()
        printLine(player, 'Server bot strategy ticks resumed.')
        return
    end

    if action == 'panic' then
        if not canRun(player, bots, action) then
            return
        end

        bots.panic()
        printLine(player, 'Server bot panic disable applied.')
        return
    end

    if action == 'llm' then
        if not canRun(player, bots, action) then
            return
        end

        if arg1 ~= 'on' and arg1 ~= 'off' then
            printLine(player, '!serverbot llm on|off')
            return
        end

        bots.setLlmEnabled(arg1 == 'on')
        printLine(player, string.format('Server bot LLM chat flag set to %s.', arg1))
        return
    end

    if action == 'profile' then
        if not canRun(player, bots, action) then
            return
        end

        printRows(player, 'Server bot profiles:', bots.profileRows(arg1), 'No server bot profiles found.')
        return
    end

    if action == 'rule' then
        if not canRun(player, bots, action) then
            return
        end

        printRows(player, 'Server bot spawn rules:', bots.ruleRows(tonumber(arg1) or player:getZoneID()), 'No server bot spawn rules found.')
        return
    end

    if action == 'camp' then
        if not canRun(player, bots, action) then
            return
        end

        printRows(player, 'Server bot camps:', bots.campRows(arg1 or tostring(player:getZoneID())), 'No server bot camps found.')
        return
    end

    if action == 'strategy' then
        if not canRun(player, bots, action) then
            return
        end

        printRows(player, 'Server bot strategies:', bots.strategyRows(arg1), 'No server bot strategies found.')
        return
    end

    if action == 'audit' then
        if not canRun(player, bots, action) then
            return
        end

        printRows(player, 'Recent server bot audit rows:', bots.auditRows(tonumber(arg1) or 10), 'No audit rows found.')
        return
    end

    if action == 'economy' then
        if not canRun(player, bots, action) then
            return
        end

        printRows(player, 'Recent server bot economy rows:', bots.economyRows(tonumber(arg1) or 10), 'No economy rows found.')
        return
    end

    if action == 'perf' then
        if not canRun(player, bots, action) then
            return
        end

        printRows(player, 'Recent server bot performance rows:', bots.performanceRows(tonumber(arg1) or 10), 'No performance rows found.')
        return
    end

    usage(player)
end

return commandObj
