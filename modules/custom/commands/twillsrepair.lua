-----------------------------------
-- func: twillsrepair
-- desc: Re-runs the local Twills admin repair while Twills is online.
-----------------------------------
---@type TCommand
local commandObj = {}

commandObj.cmdprops =
{
    permission = 5,
    parameters = '',
}

local function printLine(player, line)
    player:printToPlayer(line, xi.msg.channel.SYSTEM_3, '')
end

commandObj.onTrigger = function(player)
    if xi.twills_admin == nil or type(xi.twills_admin.repair) ~= 'function' then
        printLine(player, 'Twills admin repair module is not loaded.')
        return
    end

    local target = GetPlayerByName(xi.twills_admin.adminName or 'Twills')
    if target == nil then
        printLine(player, 'Twills must be logged in before running !twillsrepair.')
        return
    end

    if xi.twills_admin.repair(target, true) then
        printLine(player, 'Twills admin repair completed. Relog Twills to refresh client-side menus.')
    else
        printLine(player, 'Twills admin repair did not run.')
    end
end

return commandObj
