-----------------------------------
-- Native ordinary Trust return compatibility. Authority stays in the binding.
-----------------------------------
---@type TCommand
local commandObj = {}

commandObj.cmdprops =
{
    permission = 0,
    parameters = 's',
}

commandObj.onTrigger = function(player, request)
    local reply = player:returnOrdinaryTrusts(request or '')
    if reply ~= '' then
        player:printToPlayer(reply, xi.msg.channel.SYSTEM_1, 'MochiTrustRet')
    end
end

return commandObj
