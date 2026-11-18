-----------------------------------
-- Explicit travel request to the summoner's developed Iroha II.
-----------------------------------
---@type TCommand
local commandObj = {}

commandObj.cmdprops =
{
    permission = 0,
    parameters = 's',
}

commandObj.onTrigger = function(player, request)
    local destination = (request or ''):match('^%s*(.-)%s*$') or ''
    local result = player:requestIrohaTravel(string.lower(destination))
    if result ~= '' then
        player:printToPlayer(result)
    end
end

return commandObj
