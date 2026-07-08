-----------------------------------
-- func: twillsaudit
-- desc: Audits Twills' retail-shaped long-time-player bootstrap state.
-----------------------------------
require('scripts/globals/missions')
require('scripts/globals/quests')

---@type TCommand
local commandObj = {}

commandObj.cmdprops =
{
    permission = 5,
    parameters = '',
}

local adminName = 'Twills'

local importantKeyItems =
{
    { 'Limit Breaker', xi.ki.LIMIT_BREAKER },
    { 'Job Breaker', xi.ki.JOB_BREAKER },
    { 'Master Breaker', xi.ki.MASTER_BREAKER },
    { 'Heart of the Bushin', xi.ki.HEART_OF_THE_BUSHIN },
    { 'Airship Pass', xi.ki.AIRSHIP_PASS },
    { 'Kazham Airship Pass', xi.ki.AIRSHIP_PASS_FOR_KAZHAM },
    { 'Chocobo License', xi.ki.CHOCOBO_LICENSE },
    { 'Gardenia Pass', xi.ki.GARDENIA_PASS },
    { 'Mog Patio Design Document', xi.ki.MOG_PATIO_DESIGN_DOCUMENT },
    { "Trainer's Whistle", xi.ki.TRAINERS_WHISTLE },
    { 'Chocobo Companion', xi.ki.CHOCOBO_COMPANION },
    { "San d'Oria Trust Permit", xi.ki.SAN_DORIA_TRUST_PERMIT },
    { 'Bastok Trust Permit', xi.ki.BASTOK_TRUST_PERMIT },
    { 'Windurst Trust Permit', xi.ki.WINDURST_TRUST_PERMIT },
    { 'Rhapsody in White', xi.ki.RHAPSODY_IN_WHITE },
    { 'Rhapsody in Umber', xi.ki.RHAPSODY_IN_UMBER },
    { 'Rhapsody in Azure', xi.ki.RHAPSODY_IN_AZURE },
    { 'Rhapsody in Crimson', xi.ki.RHAPSODY_IN_CRIMSON },
    { 'Rhapsody in Emerald', xi.ki.RHAPSODY_IN_EMERALD },
    { 'Rhapsody in Mauve', xi.ki.RHAPSODY_IN_MAUVE },
    { 'Rhapsody in Fuchsia', xi.ki.RHAPSODY_IN_FUCHSIA },
    { 'Rhapsody in Puce', xi.ki.RHAPSODY_IN_PUCE },
    { 'Rhapsody in Ochre', xi.ki.RHAPSODY_IN_OCHRE },
    { 'Scintillating Rhapsody', xi.ki.SCINTILLATING_RHAPSODY },
    { 'Cipher Bracelet', xi.ki.CIPHER_BRACELET },
}

local rdmJobPointSpells =
{
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
    local other = 0
    local fixRows = {}

    for _, row in ipairs(rows) do
        if string.sub(row, 1, 4) == '[OK]' then
            ok = ok + 1
        elseif string.sub(row, 1, 5) == '[FIX]' then
            fix = fix + 1
            table.insert(fixRows, row)
        else
            other = other + 1
        end
    end

    printLine(player, string.format('%s: %i OK, %i FIX%s', label, ok, fix, other > 0 and string.format(', %i info', other) or ''))

    for i = 1, math.min(#fixRows, 6) do
        printLine(player, fixRows[i])
    end

    if #fixRows > 6 then
        printLine(player, string.format('[FIX] %s: %i additional FIX rows omitted from in-game output; use runtime audit evidence for full detail.', label, #fixRows - 6))
    end
end

local function countImportantKeyItems(player)
    local found = 0
    local total = 0
    local missing = {}

    for _, entry in ipairs(importantKeyItems) do
        local name = entry[1]
        local id = entry[2]

        if id ~= nil then
            total = total + 1

            if player:hasKeyItem(id) then
                found = found + 1
            else
                table.insert(missing, name)
            end
        end
    end

    return found, total, missing
end

local function countKnownQuests(player)
    local complete = 0
    local expected = 0

    for logId, areaName in pairs(xi.quest.area) do
        local quests = xi.quest.id[areaName]
        local seen = {}

        if quests ~= nil then
            for _, questId in pairs(quests) do
                if type(questId) == 'number' and questId >= 0 and questId < 256 then
                    seen[questId] = true
                end
            end

            for questId in pairs(seen) do
                expected = expected + 1

                if player:hasCompletedQuest(logId, questId) then
                    complete = complete + 1
                end
            end
        end
    end

    return complete, expected
end

local function countKnownMissions(player)
    local complete = 0
    local expected = 0
    local terminalLogs = 0

    for logId, areaName in pairs(xi.mission.area) do
        if
            logId ~= xi.mission.log_id.ASSAULT and
            logId ~= xi.mission.log_id.CAMPAIGN
        then
            local missions = xi.mission.id[areaName]
            local seen = {}
            local maxMissionId = 0
            local usesCurrentProgress = logId == xi.mission.log_id.COP

            if missions ~= nil then
                for _, missionId in pairs(missions) do
                    if type(missionId) == 'number' and missionId >= 0 and missionId < 65535 then
                        seen[missionId] = true
                        maxMissionId = math.max(maxMissionId, missionId)

                        if missionId >= 64 then
                            usesCurrentProgress = true
                        end
                    end
                end

                for missionId in pairs(seen) do
                    if not usesCurrentProgress or missionId < 64 then
                        expected = expected + 1

                        if player:hasCompletedMission(logId, missionId) then
                            complete = complete + 1
                        end
                    end
                end

                if usesCurrentProgress and maxMissionId > 0 then
                    terminalLogs = terminalLogs + 1
                end
            end
        end
    end

    return complete, expected, terminalLogs
end

local function printLiveAudit(invoker, target)
    local learned = 0
    local missingSpells = {}

    for _, entry in ipairs(rdmJobPointSpells) do
        if target:hasSpell(entry[2]) then
            learned = learned + 1
        else
            table.insert(missingSpells, entry[1])
        end
    end

    printLine(invoker, string.format('%s RDM JP spells: %i/%i learned%s',
        learned == #rdmJobPointSpells and '[OK]' or '[FIX]',
        learned,
        #rdmJobPointSpells,
        #missingSpells > 0 and ('; missing ' .. table.concat(missingSpells, ', ')) or ''
    ))

    local keyItems, expectedKeyItems, missingKeyItems = countImportantKeyItems(target)
    printLine(invoker, string.format('%s Key items: %i/%i important gates present%s',
        keyItems == expectedKeyItems and '[OK]' or '[FIX]',
        keyItems,
        expectedKeyItems,
        #missingKeyItems > 0 and ('; missing ' .. table.concat(missingKeyItems, ', ')) or ''
    ))

    local completedQuests, expectedQuests = countKnownQuests(target)
    printLine(invoker, string.format('%s Quests: %i/%i locally represented quests complete',
        completedQuests == expectedQuests and '[OK]' or '[FIX]',
        completedQuests,
        expectedQuests
    ))

    local completedMissions, expectedMissions, terminalLogs = countKnownMissions(target)
    printLine(invoker, string.format('%s Missions: %i/%i directly completable missions complete; %i terminal progress logs tracked',
        completedMissions == expectedMissions and '[OK]' or '[FIX]',
        completedMissions,
        expectedMissions,
        terminalLogs
    ))

    if
        xi.twills_admin ~= nil and
        type(xi.twills_admin.auditLongTimeContent) == 'function'
    then
        summarizeRows(invoker, 'Long-time content audit', xi.twills_admin.auditLongTimeContent(target))
    else
        printLine(invoker, '[FIX] Twills long-time content audit helper is not loaded.')
    end
end

commandObj.onTrigger = function(player)
    local target = GetPlayerByName(adminName)
    if target == nil then
        printLine(player, 'Twills must be logged in before running !twillsaudit.')
        return
    end

    printLine(player, 'Twills retail-shaped audit started.')

    if
        xi.twills_admin ~= nil and
        xi.twills_admin.native ~= nil and
        type(xi.twills_admin.native.auditDbState) == 'function'
    then
        local rows = xi.twills_admin.native.auditDbState(target:getID())
        summarizeRows(player, 'Native DB audit', rows)
    else
        printLine(player, '[FIX] Native audit helper is not loaded; rebuild/restart xi_map.')
    end

    printLiveAudit(player, target)
    printLine(player, 'Twills retail-shaped audit complete. Run !twillsrepair for repairable FIX rows.')
end

return commandObj
