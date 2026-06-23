-----------------------------------
-- func: bot
-- desc: Compatibility notice for autonomous server bots.
-----------------------------------
---@type TCommand
local commandObj = {}

commandObj.cmdprops =
{
    permission = 0,
    parameters = 'ssss',
}

local function printLine(player, line)
    player:printToPlayer(line, xi.msg.channel.SYSTEM_3, '')
end

commandObj.onTrigger = function(player)
    printLine(player, 'Server bots are autonomous world adventurers and do not accept player orders.')
    printLine(player, 'Use Trusts for player companion gameplay.')
end

return commandObj
