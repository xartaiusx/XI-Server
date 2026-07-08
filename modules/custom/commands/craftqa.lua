-----------------------------------
-- func: craftqa
-- desc: GM-only Cooking synthesis QA helper for Mochirii.
-----------------------------------
---@type TCommand
local commandObj = {}

commandObj.cmdprops =
{
    permission = 5,
    parameters = 'ssss',
}

local function printLine(player, line)
    player:printToPlayer(line, xi.msg.channel.SYSTEM_3, '')
end

local function native()
    if xi.craftqa ~= nil and xi.craftqa.native ~= nil then
        return xi.craftqa.native
    end

    return nil
end

local function printRows(player, rows)
    if rows == nil then
        printLine(player, 'CraftQA returned no rows.')
        return
    end

    local shown = 0
    for _, row in ipairs(rows) do
        local text = tostring(row)
        print('Mochirii CraftQA: ' .. text)

        if shown < 7 then
            if #text > 180 then
                text = text:sub(1, 177) .. '...'
            end

            printLine(player, text)
            shown = shown + 1
        end
    end

    if #rows > shown then
        printLine(player, string.format('%u more row(s) written to the map log.', #rows - shown))
    end
end

local function usage(player)
    printLine(player, '!craftqa cooking status')
    printLine(player, '!craftqa cooking repair')
    printLine(player, '!craftqa cooking stage <recipeId> [attempts]')
    printLine(player, '!craftqa cooking craft <recipeId>')
    printLine(player, '!craftqa cooking historyproof <recipeId>')
    printLine(player, '!craftqa cooking verbose on|off')
    printLine(player, '!craftqa cooking batch endgame [maxAttempts]')
    printLine(player, '!craftqa cooking pause|resume|report')
end

commandObj.onTrigger = function(player, scope, action, arg1, arg2)
    local api = native()
    if api == nil then
        printLine(player, 'CraftQA native module is not loaded. Rebuild/restart xi_map after enabling custom/cpp/craftqa.cpp.')
        return
    end

    if scope ~= 'cooking' then
        usage(player)
        return
    end

    if action == nil or action == 'status' then
        printRows(player, api.status(player))
        return
    end

    if action == 'repair' then
        printRows(player, api.repairCook(player))
        return
    end

    if action == 'stage' then
        local recipeId = tonumber(arg1)
        if recipeId == nil then
            printLine(player, '!craftqa cooking stage <recipeId> [attempts]')
            return
        end

        printRows(player, api.stageRecipe(player, recipeId, tonumber(arg2) or 1))
        return
    end

    if action == 'craft' then
        local recipeId = tonumber(arg1)
        if recipeId == nil then
            printLine(player, '!craftqa cooking craft <recipeId>')
            return
        end

        printRows(player, api.craftRecipe(player, recipeId))
        return
    end

    if action == 'historyproof' then
        local recipeId = tonumber(arg1)
        if recipeId == nil then
            printLine(player, '!craftqa cooking historyproof <recipeId>')
            return
        end

        printRows(player, api.historyProof(player, recipeId))
        return
    end

    if action == 'verbose' then
        if arg1 ~= 'on' and arg1 ~= 'off' then
            printLine(player, '!craftqa cooking verbose on|off')
            return
        end

        printRows(player, api.verbose(player, arg1))
        return
    end

    if action == 'batch' then
        if arg1 ~= 'endgame' then
            printLine(player, '!craftqa cooking batch endgame [maxAttempts]')
            return
        end

        printRows(player, api.batchEndgame(player, tonumber(arg2) or 50))
        return
    end

    if action == 'pause' then
        printRows(player, api.pause(player, true))
        return
    end

    if action == 'resume' then
        printRows(player, api.pause(player, false))
        return
    end

    if action == 'report' then
        printRows(player, api.report(player))
        return
    end

    usage(player)
end

return commandObj
