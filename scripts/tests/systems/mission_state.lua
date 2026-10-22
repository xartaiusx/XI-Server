local ffi = require('ffi')

describe('Mission state boundaries', function()
    ---@type CClientEntityPair
    local player

    local zilart = xi.mission.log_id.ZILART
    local first  = xi.mission.id.zilart.THE_NEW_FRONTIER
    local later  = xi.mission.id.zilart.WELCOME_TNORG
    local none   = xi.mission.id.zilart.NONE

    before_each(function()
        player = xi.test.world:spawnPlayer({ zone = xi.zone.GM_HOME })
    end)

    local function reloadMissionState()
        local charId = player:getID()
        player:setLocalVar('MissionReloadProbe', 1)
        player:gotoZone(xi.zone.WEST_RONFAURE)
        assert(player:getID() == charId, 'reload changed character identity')
        assert(player:getLocalVar('MissionReloadProbe') == 0, 'zoning did not reload the entity')
    end

    it('starts Zilart with NONE rather than the real first mission', function()
        assert(first == 0, 'the first Zilart mission is not zero')
        assert(none ~= first, 'NONE aliases the first Zilart mission')
        assert(player:getCurrentMission(zilart) == none, 'fresh Zilart log is not empty')
        assert(not player:hasCompletedMission(zilart, first), 'fresh first mission is completed')
        reloadMissionState()
        assert(player:getCurrentMission(zilart) == none, 'reload changed empty Zilart state')
    end)

    it('preserves stored Zilart mission zero across an entity reload', function()
        player:addMission(zilart, first)
        player:setCharVar('MissionStateUnrelated', 73)
        assert(player:getCurrentMission(zilart) == first, 'mission zero was not added')

        reloadMissionState()

        assert(player:getCurrentMission(zilart) == first, 'stored zero was rewritten as NONE')
        assert(not player:hasCompletedMission(zilart, first), 'stored zero became completed')
        assert(player:getCharVar('MissionStateUnrelated') == 73, 'unrelated state changed')
    end)

    it('deletes Zilart mission zero back to NONE and persists it', function()
        player:addMission(zilart, first)
        player:delMission(zilart, first)
        assert(player:getCurrentMission(zilart) == none, 'deleting zero left it active')
        assert(not player:hasCompletedMission(zilart, first), 'deleting zero completed it')

        reloadMissionState()

        assert(player:getCurrentMission(zilart) == none, 'deleted mission zero returned')
        assert(not player:hasCompletedMission(zilart, first), 'reload marked zero completed')
    end)

    it('completes Zilart mission zero without restarting it after reload', function()
        player:addMission(zilart, first)
        player:completeMission(zilart, first)
        assert(player:getCurrentMission(zilart) == none, 'completion restarted mission zero')
        assert(player:hasCompletedMission(zilart, first), 'completion bit was not set')

        reloadMissionState()

        assert(player:getCurrentMission(zilart) == none, 'reload restarted mission zero')
        assert(player:hasCompletedMission(zilart, first), 'completion bit did not persist')
    end)

    it('deletes a later Zilart mission without clearing its status or variables', function()
        player:setMissionStatus(zilart, 7)
        player:setCharVar('Mission[3][4]Status', 2)
        player:addMission(zilart, later)
        player:delMission(zilart, later)
        assert(player:getCurrentMission(zilart) == none, 'later mission did not clear to NONE')

        reloadMissionState()

        assert(player:getCurrentMission(zilart) == none, 'later mission returned')
        assert(player:getMissionStatus(zilart) == 7, 'deletion cleared mission status')
        assert(player:getCharVar('Mission[3][4]Status') == 2, 'deletion cleared mission variables')
        assert(not player:hasCompletedMission(zilart, later), 'deletion completed the mission')
    end)

    it('completes a later Zilart mission while retaining earlier completion', function()
        player:addMission(zilart, first)
        player:completeMission(zilart, first)
        player:addMission(zilart, later)
        player:completeMission(zilart, later)

        reloadMissionState()

        assert(player:getCurrentMission(zilart) == none, 'later completion did not stay empty')
        assert(player:hasCompletedMission(zilart, first), 'earlier completion was lost')
        assert(player:hasCompletedMission(zilart, later), 'later completion was lost')
    end)

    it('does not clear active mission zero when a different mission is deleted', function()
        player:addMission(zilart, first)
        player:delMission(zilart, later)

        reloadMissionState()

        assert(player:getCurrentMission(zilart) == first, 'noncurrent deletion erased zero')
        assert(not player:hasCompletedMission(zilart, first), 'noncurrent deletion completed zero')
    end)

    it('keeps the Windurst boundary log using NONE and completion bits', function()
        local logId     = xi.mission.log_id.WINDURST
        local missionId = xi.mission.id.windurst.THE_HORUTOTO_RUINS_EXPERIMENT
        assert(player:getCurrentMission(logId) == xi.mission.id.windurst.NONE)

        player:addMission(logId, missionId)
        player:delMission(logId, missionId)
        assert(player:getCurrentMission(logId) == xi.mission.id.windurst.NONE)

        player:addMission(logId, missionId)
        player:completeMission(logId, missionId)
        reloadMissionState()

        assert(player:getCurrentMission(logId) == xi.mission.id.windurst.NONE)
        assert(player:hasCompletedMission(logId, missionId), 'nation completion bit was lost')
    end)

    it('keeps the ToAU boundary log using zero after deletion and completion', function()
        local logId     = xi.mission.log_id.TOAU
        local missionId = xi.mission.id.toau.IMMORTAL_SENTRIES
        assert(player:getCurrentMission(logId) == 0)

        player:addMission(logId, missionId)
        player:delMission(logId, missionId)
        assert(player:getCurrentMission(logId) == 0)

        player:addMission(logId, missionId)
        player:completeMission(logId, missionId)
        reloadMissionState()

        assert(player:getCurrentMission(logId) == 0, 'ToAU empty state changed')
        assert(player:hasCompletedMission(logId, missionId), 'ToAU completion bit was lost')
        assert(player:getCurrentMission(zilart) == none, 'unrelated Zilart state changed')
    end)

    it('keeps CoP ordered completion and zero-empty behavior unchanged', function()
        local logId = xi.mission.log_id.COP
        assert(player:getCurrentMission(logId) == xi.mission.id.cop.ANCIENT_FLAMES_BECKON)
        player:delMission(logId, xi.mission.id.cop.ANCIENT_FLAMES_BECKON)
        assert(player:getCurrentMission(logId) == 0)

        player:addMission(logId, xi.mission.id.cop.BELOW_THE_ARKS)
        player:completeMission(logId, xi.mission.id.cop.BELOW_THE_ARKS)
        assert(player:getCurrentMission(logId) == 0)
        assert(not player:hasCompletedMission(logId, xi.mission.id.cop.BELOW_THE_ARKS))

        player:addMission(logId, xi.mission.id.cop.THE_MOTHERCRYSTALS)
        assert(player:hasCompletedMission(logId, xi.mission.id.cop.BELOW_THE_ARKS))
        player:delMission(logId, xi.mission.id.cop.THE_MOTHERCRYSTALS)
        reloadMissionState()

        assert(player:getCurrentMission(logId) == 0, 'CoP empty state changed')
        assert(not player:hasCompletedMission(logId, xi.mission.id.cop.BELOW_THE_ARKS))
    end)

    it('dispatches a real mission completion to an active RoE objective', function()
        assert(xi.settings.main.ENABLE_ROE == 1, 'mission completion control requires RoE')
        local record = ffi.new('uint8_t[8]')
        record[4] = 1313 % 256
        record[5] = math.floor(1313 / 256)
        player.packets:send(0x10C, record, assert(ffi.sizeof(record)))
        assert(player:hasEminenceRecord(1313), 'mission completion objective was not taken')
        local missionCompletion = spy('xi.roe.onRecordTrigger')

        local logId     = xi.mission.log_id.SANDORIA
        local missionId = xi.mission.id.sandoria.SMASH_THE_ORCISH_SCOUTS
        player:addMission(logId, missionId)
        player:completeMission(logId, missionId)

        missionCompletion:called(1)
        assert(missionCompletion.calls[1].args[2] == 1313, 'wrong RoE objective was dispatched')
        assert(player:getEminenceCompleted(1313), 'positive mission objective did not complete')
    end)
end)
