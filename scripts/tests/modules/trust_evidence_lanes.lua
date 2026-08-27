-----------------------------------
-- Mochirii Trust evidence-lane state machine.
-----------------------------------
describe('Module: Trust evidence lanes', function()
    ---@type CClientEntityPair
    local player
    local records
    local attached
    local beginSucceeds
    local beginFailureReason
    local beginDelegate
    local endSucceeds
    local originalLogDir
    local originalLogPlayer
    local testLogRoot
    local testArchivePath
    local testLivePath
    local testRestPath
    local realBeginSession = xi.trustActionLogger.beginSession

    local function trustCount(target)
        local count = 0
        for _, member in ipairs(target:getPartyWithTrusts()) do
            if member:getObjType() == xi.objType.TRUST then
                count = count + 1
            end
        end

        return count
    end

    local function attachedCount(target)
        local count = 0
        for _, member in ipairs(target:getPartyWithTrusts()) do
            if
                member:getObjType() == xi.objType.TRUST and
                attached[member:getTrustID()]
            then
                count = count + 1
            end
        end

        return count
    end

    local function advanceTimers(count)
        for _ = 1, count do
            xi.test.world:skipTime(1)
        end
    end

    local function fieldValue(fields, key)
        local prefix = key .. '='
        for _, field in ipairs(fields or {}) do
            if field:sub(1, #prefix) == prefix then
                return field:sub(#prefix + 1)
            end
        end

        return nil
    end

    local function findRecord(recordType, event)
        for index = #records, 1, -1 do
            local record = records[index]
            if record.recordType == recordType and record.event == event then
                return record
            end
        end

        return nil
    end

    local function findRecordIndex(recordType, event)
        for index, record in ipairs(records) do
            if record.recordType == recordType and record.event == event then
                return index, record
            end
        end

        return nil, nil
    end

    local function assertFailedSessionClosed()
        local failedIndex = findRecordIndex('session_state', 'failed')
        local failureIndex = findRecordIndex('roster', 'failure')
        local endIndex, sessionEnd = findRecordIndex('session_end', 'session_end')
        assert(failedIndex ~= nil, 'failure path must record an authoritative Failed transition')
        assert(failureIndex ~= nil and failureIndex > failedIndex, 'roster failure must follow Failed')
        assert(endIndex ~= nil and endIndex > failureIndex, 'terminal session_end must follow failure evidence')
        assert(endIndex == #records, 'session_end must be the final evidence record')
        assert(
            sessionEnd ~= nil,
            'terminal session_end record must be available for validation'
        )
        assert(sessionEnd.completion == 'failed')
        assert(sessionEnd.state == xi.trustRetailParity.sessionState.IDLE)
    end

    local function configureTwills(target)
        target:setGMLevel(5)
        target:setVisibleGMLevel(0)
        target:setCharVar('MochiriiTrustAllianceAccess', 1)
    end

    before_each(function()
        records = {}
        attached = {}
        beginSucceeds = true
        beginFailureReason = nil
        beginDelegate = nil
        endSucceeds = true
        originalLogDir = xi.settings.main.TRUST_ACTION_LOG_DIR
        originalLogPlayer = xi.settings.main.TRUST_ACTION_LOG_PLAYER
        testLogRoot = nil
        testArchivePath = nil
        testLivePath = nil
        testRestPath = nil
        assert(xi.trustRetailParity.setSpawnTrustTestHook(nil))
        assert(xi.trustRetailParity.setClearTrustsTestHook(nil))

        stub('xi.trustActionLogger.resetForLogin', function()
            return true
        end)

        stub('xi.trustActionLogger.beginSession', function(target, fields)
            if beginDelegate ~= nil then
                return beginDelegate(target, fields)
            end

            records[#records + 1] =
            {
                recordType = 'session_begin',
                event = 'session_begin',
                fields = fields,
                state = target:getTwillsFullAllianceState(),
                schema = target:getLocalVar('MochiriiTrustEvidenceSchema'),
                allianceActive = target:isTwillsFullAllianceActive(),
            }
            return beginSucceeds, beginFailureReason
        end)

        stub('xi.trustActionLogger.recordSessionEvent', function(target, recordType, event, fields)
            records[#records + 1] =
            {
                recordType = recordType,
                event = event,
                fields = fields,
                state = target:getTwillsFullAllianceState(),
                schema = target:getLocalVar('MochiriiTrustEvidenceSchema'),
                allianceActive = target:isTwillsFullAllianceActive(),
            }
            return true
        end)

        stub('xi.trustActionLogger.endSession', function(target, completion, reason, fields)
            records[#records + 1] =
            {
                recordType = 'session_end',
                event = 'session_end',
                completion = completion,
                reason = reason,
                fields = fields,
                state = target:getTwillsFullAllianceState(),
                schema = target:getLocalVar('MochiriiTrustEvidenceSchema'),
                allianceActive = target:isTwillsFullAllianceActive(),
            }
            return endSucceeds
        end)

        stub('xi.trustActionLogger.attach', function(trust)
            attached[trust:getTrustID()] = true
            return true, 'attached'
        end)

        stub('xi.trustActionLogger.attachmentCount', attachedCount)

        player = xi.test.world:spawnPlayer(
            {
                name = 'Twills',
                zone = xi.zone.WEST_RONFAURE,
                job = xi.job.RDM,
                level = 99,
            })
        configureTwills(player)
    end)

    after_each(function()
        xi.settings.main.TRUST_ACTION_LOG_DIR = originalLogDir
        xi.settings.main.TRUST_ACTION_LOG_PLAYER = originalLogPlayer
        if testLogRoot ~= nil then
            if testArchivePath ~= nil then
                os.remove(testArchivePath)
            end

            if testLivePath ~= nil then
                os.remove(testLivePath)
            end

            if testRestPath ~= nil then
                os.remove(testRestPath)
            end

            os.remove(testLogRoot .. '/archive')
            os.remove(testLogRoot .. '/live')
            os.remove(testLogRoot)
        end
    end)

    it('centralizes exact hidden-GM5 Twills authorization', function()
        assert(player:canUseTwillsFullAlliance())

        player:setVisibleGMLevel(1)
        assert(not player:canUseTwillsFullAlliance())
        player:setVisibleGMLevel(0)

        player:setGMLevel(4)
        assert(not player:canUseTwillsFullAlliance())
        player:setGMLevel(5)

        player:setCharVar('MochiriiTrustAllianceAccess', 0)
        assert(not player:canUseTwillsFullAlliance())
        assert(xi.trustRetailParity.partyRows(player, true)[1]:find('Repair denied', 1, true) ~= nil)
        player:setCharVar('MochiriiTrustAllianceAccess', 1)
        assert(player:canUseTwillsFullAlliance())

        local other = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE })
        configureTwills(other)
        assert(not other:canUseTwillsFullAlliance())
    end)

    it('derives a deterministic session context from native state and the full server commit', function()
        player:setLocalVar('MochiriiTrustEvidenceMode', xi.trustRetailParity.evidenceMode.RETAIL)
        player:setLocalVar('MochiriiTrustEvidenceSchema', 2)
        player:setLocalVar('MochiriiTrustSessionGeneration', 7)
        player:setLocalVar('MochiriiTrustSessionStarted', GetSystemTime())
        player:setLocalVar('MochiriiTrustSessionZone', player:getZoneID())
        player:setCharVar('TrustEngageType', 0)
        assert(player:setTwillsFullAllianceState(xi.trustRetailParity.sessionState.SPAWNING))

        local context, reason = xi.trustActionLogger.sessionContext(player)
        assert(context ~= nil, tostring(reason))
        assert(context.serverCommit:match('^[0-9a-f]+$') and #context.serverCommit == 40)
        assert(context.sessionId:match('^Twills%-%d+%-%d+%-7$') ~= nil)
        assert(context.modeName == 'retail_control')
        assert(context.topology == 'retail_party_1_plus_5')
    end)

    it('accepts the native no-battlefield sentinel during preflight', function()
        assert(player:getBattlefield() == nil)
        assert(player:getBattlefieldID() == -1)

        local allowed, reason = xi.trustRetailParity.preflight(
            player,
            xi.trustRetailParity.evidenceMode.RETAIL)
        assert(allowed, tostring(reason))
    end)

    it('emits an idle prepare sequence before enabling the QA projection', function()
        assert(xi.trustRetailParity.summonQa(player))
        assert(#records >= 5)

        local expected =
        {
            { 'session_begin', 'session_begin', xi.trustRetailParity.sessionState.IDLE, false },
            { 'roster', 'preflight', xi.trustRetailParity.sessionState.IDLE, false },
            { 'roster', 'cleared', xi.trustRetailParity.sessionState.IDLE, false },
            { 'session_state', 'spawning', xi.trustRetailParity.sessionState.SPAWNING, true },
            { 'checkpoint', 'summon_attempt', xi.trustRetailParity.sessionState.SPAWNING, true },
        }
        for index, row in ipairs(expected) do
            local record = records[index]
            assert(record.recordType == row[1] and record.event == row[2])
            assert(record.state == row[3])
            assert(record.allianceActive == row[4])
            assert(record.schema == 2)
        end

        assert(fieldValue(records[1].fields, 'alliance_active') == 'false')
        assert(fieldValue(records[4].fields, 'alliance_active') == 'true')
        assert(fieldValue(records[1].fields, 'combat_summoning_setting') == 'false')
        assert(fieldValue(records[1].fields, 'combat_summoning_effective') == 'false')
        local unexpected, reason = xi.trustRetailParity.spawnTrust(player, xi.magic.spell.KUPIPI)
        assert(unexpected == nil and reason == 'trust_not_in_locked_roster')
        assert(xi.trustRetailParity.clearSession(player, 'prepare_sequence_cleanup'))
    end)

    it('preserves the existing Trust roster when session log creation fails', function()
        assert(player:spawnTrust(xi.magic.spell.VALAINERAL) ~= nil)
        beginSucceeds = false
        beginFailureReason = 'forced_session_begin_failure'

        local started, reason = xi.trustRetailParity.summonQa(player)
        assert(not started and reason == beginFailureReason)
        assert(trustCount(player) == 1)
        assert(player:getTwillsFullAllianceState() == xi.trustRetailParity.sessionState.IDLE)
        assert(player:getLocalVar('MochiriiTrustEvidenceMode') == xi.trustRetailParity.evidenceMode.IDLE)
        assert(player:getLocalVar('MochiriiTrustEvidenceSchema') == 0)
        assert(player:getCharVar('TrustEngageType') == 0)
        assert(#records == 1 and records[1].state == xi.trustRetailParity.sessionState.IDLE)
    end)

    it('preserves an existing archive and roster when a restarted session id collides', function()
        local fixedEpoch = 1785067200
        stub('GetSystemTime', fixedEpoch)

        testLogRoot = os.tmpname()
        os.remove(testLogRoot)
        xi.settings.main.TRUST_ACTION_LOG_DIR = testLogRoot
        xi.settings.main.TRUST_ACTION_LOG_PLAYER = 'Twills'

        player:setLocalVar('MochiriiTrustEvidenceMode', xi.trustRetailParity.evidenceMode.QA)
        player:setLocalVar('MochiriiTrustEvidenceSchema', 2)
        player:setLocalVar('MochiriiTrustSessionGeneration', 1)
        player:setLocalVar('MochiriiTrustSessionStarted', fixedEpoch)
        player:setLocalVar('MochiriiTrustSessionZone', player:getZoneID())
        player:setCharVar('TrustEngageType', 1)

        local seeded, seedReason = realBeginSession(player, { 'fixture=archive_collision' })
        assert(seeded, tostring(seedReason))
        local sessionId = xi.trustActionLogger.sessionIdForPlayer(player)
        testArchivePath = testLogRoot .. '/archive/' .. sessionId .. '.log'
        testLivePath = testLogRoot .. '/live/Twills.log'
        testRestPath = testLogRoot .. '/live/Twills-resting.tsv'

        local archive = assert(io.open(testArchivePath, 'rb'))
        local sealedContent = archive.read(archive, '*a')
        archive.close(archive)
        assert(#sealedContent > 0)

        player:setLocalVar('MochiriiTrustEvidenceMode', xi.trustRetailParity.evidenceMode.IDLE)
        player:setLocalVar('MochiriiTrustEvidenceSchema', 0)
        player:setLocalVar('MochiriiTrustSessionGeneration', 0)
        player:setLocalVar('MochiriiTrustSessionStarted', 0)
        player:setLocalVar('MochiriiTrustSessionZone', 0)
        player:setLocalVar('MochiriiTrustEvidenceSeq', 0)
        player:setLocalVar('MochiriiTrustLogTruncated', 0)
        player:setCharVar('TrustEngageType', 0)
        assert(player:spawnTrust(xi.magic.spell.VALAINERAL) ~= nil)

        beginDelegate = realBeginSession
        local started, reason = xi.trustRetailParity.summonQa(player)
        assert(not started and reason == 'archive_already_exists')
        assert(trustCount(player) == 1)
        assert(player:getTwillsFullAllianceState() == xi.trustRetailParity.sessionState.IDLE)

        archive = assert(io.open(testArchivePath, 'rb'))
        local preservedContent = archive.read(archive, '*a')
        archive.close(archive)
        assert(preservedContent == sealedContent, 'colliding begin must never alter sealed archive bytes')
    end)

    it('preserves ordinary-player Rhapsodies gates and the five-Trust hard cap', function()
        local ordinary = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE })
        assert(not ordinary:canUseTwillsFullAlliance())
        assert(xi.trustRetailParity.spawnTrust(ordinary, xi.magic.spell.VALAINERAL) == nil)

        assert(ordinary:spawnTrust(xi.magic.spell.VALAINERAL) ~= nil)
        assert(ordinary:spawnTrust(xi.magic.spell.YORAN_ORAN_UC) ~= nil)
        assert(ordinary:spawnTrust(xi.magic.spell.ULMIA) ~= nil)

        assert(xi.trust.canCast(ordinary, GetSpell(xi.magic.spell.LILISETTE_II)) == -1)
        ordinary:addKeyItem(xi.ki.RHAPSODY_IN_WHITE)
        assert(xi.trust.canCast(ordinary, GetSpell(xi.magic.spell.LILISETTE_II)) == 0)
        assert(ordinary:spawnTrust(xi.magic.spell.LILISETTE_II) ~= nil)

        assert(xi.trust.canCast(ordinary, GetSpell(xi.magic.spell.SHANTOTTO_II)) == -1)
        ordinary:addKeyItem(xi.ki.RHAPSODY_IN_CRIMSON)
        assert(xi.trust.canCast(ordinary, GetSpell(xi.magic.spell.SHANTOTTO_II)) == 0)
        assert(ordinary:spawnTrust(xi.magic.spell.SHANTOTTO_II) ~= nil)

        assert(xi.trust.canCast(ordinary, GetSpell(xi.magic.spell.AUGUST)) == -1)
        assert(ordinary:spawnTrust(xi.magic.spell.AUGUST) == nil)
        assert(trustCount(ordinary) == 5)
    end)

    it('summons the exact retail-control roster and clears idempotently', function()
        local started = xi.trustRetailParity.summonRetail(player)
        assert(started)
        assert(player:getTwillsFullAllianceState() == xi.trustRetailParity.sessionState.SPAWNING)
        assert(player:getLocalVar('MochiriiTrustEvidenceSchema') == 2)
        assert(player:getCharVar('TrustEngageType') == 0)

        advanceTimers(8)

        local audit = xi.trustRetailParity.rosterAudit(player, xi.trustRetailParity.evidenceMode.RETAIL)
        assert(player:getTwillsFullAllianceState() == xi.trustRetailParity.sessionState.READY)
        assert(audit.exactMatch)
        assert(audit.activeCount == 5)
        assert(audit.party1Count == 6 and audit.party2Count == 0 and audit.party3Count == 0)
        assert(table.concat(audit.activeIds, ',') == '910,980,914,1013,1019')

        local checkpoint = findRecord('checkpoint', 'summon_complete')
        assert(checkpoint ~= nil)
        assert(fieldValue(checkpoint.fields, 'expected_party1_count') == '5')
        assert(fieldValue(checkpoint.fields, 'party1_count') == '6')
        assert(fieldValue(checkpoint.fields, 'party2_count') == '0')
        assert(fieldValue(checkpoint.fields, 'party3_count') == '0')
        assert(fieldValue(checkpoint.fields, 'qa_extension') == 'false')
        assert(fieldValue(checkpoint.fields, 'combat_acceptance') == 'not_run')

        local cleared = xi.trustRetailParity.clearSession(player, 'test_clear')
        assert(cleared)
        assert(trustCount(player) == 0)
        assert(player:getTwillsFullAllianceState() == xi.trustRetailParity.sessionState.IDLE)
        assert(player:getLocalVar('MochiriiTrustEvidenceMode') == xi.trustRetailParity.evidenceMode.IDLE)
        assert(player:getLocalVar('MochiriiTrustEvidenceSchema') == 0)
        assert(player:getLocalVar('MochiriiTrustAlliancePendingTimers') == 0)
        assert(player:getCharVar('TrustEngageType') == 0)

        local sessionEnd = findRecord('session_end', 'session_end')
        assert(sessionEnd ~= nil and sessionEnd.completion == 'cleared')
        assert(sessionEnd.state == xi.trustRetailParity.sessionState.IDLE)
        for _, record in ipairs(records) do
            assert(record.state ~= xi.trustRetailParity.sessionState.FAILED)
            assert(record.event ~= 'failure')
        end

        local clearedAgain, reason = xi.trustRetailParity.clearSession(player, 'test_clear_again')
        assert(clearedAgain and reason == 'already_idle')
    end)

    it('summons exactly one PC plus the locked 17-Trust QA alliance', function()
        assert(xi.trustRetailParity.summonQa(player))
        assert(player:getCharVar('TrustEngageType') == 1)

        advanceTimers(22)

        local audit = xi.trustRetailParity.rosterAudit(player, xi.trustRetailParity.evidenceMode.QA)
        assert(player:getTwillsFullAllianceState() == xi.trustRetailParity.sessionState.READY)
        assert(player:isTwillsFullAllianceActive())
        assert(player:getLocalVar('MochiriiTrustEvidenceSchema') == 2)
        assert(audit.exactMatch)
        assert(audit.realPcCount == 1 and audit.activeCount == 17)
        assert(audit.party1Count == 6 and audit.party2Count == 6 and audit.party3Count == 6)
        assert(table.concat(audit.activeIds, ',') == '984,980,952,967,1002,910,999,911,914,1013,1003,969,981,955,1019,935,979')

        local checkpoint = findRecord('checkpoint', 'summon_complete')
        assert(checkpoint ~= nil)
        assert(fieldValue(checkpoint.fields, 'expected_party1_count') == '5')
        assert(fieldValue(checkpoint.fields, 'expected_party2_count') == '6')
        assert(fieldValue(checkpoint.fields, 'expected_party3_count') == '6')
        assert(fieldValue(checkpoint.fields, 'party1_count') == '6')
        assert(fieldValue(checkpoint.fields, 'party2_count') == '6')
        assert(fieldValue(checkpoint.fields, 'party3_count') == '6')
        assert(fieldValue(checkpoint.fields, 'qa_extension') == 'true')
        assert(fieldValue(checkpoint.fields, 'combat_acceptance') == 'not_run')

        local members = player:getPartyWithTrusts()
        local seenEntities = {}
        assert(#members == 18)
        for _, member in ipairs(members) do
            assert(not seenEntities[member:getID()], 'party traversal returned a duplicate entity')
            seenEntities[member:getID()] = true
        end

        local partyTargets = xi.test.world:getPartyTargetTraversal(player)
        local seenTargets = {}
        assert(#partyTargets == 18)
        for _, member in ipairs(partyTargets) do
            local entityId = member:getID()
            assert(seenEntities[entityId], 'party target traversal returned an unexpected entity')
            assert(not seenTargets[entityId], 'party target traversal returned a duplicate entity')
            seenTargets[entityId] = true
        end

        assert(player:spawnTrust(xi.magic.spell.KUPIPI) == nil, 'an eighteenth Trust must be rejected')
    end)

    it('fails and clears a ready QA session after native evidence truncation', function()
        assert(xi.trustRetailParity.summonQa(player))
        advanceTimers(22)
        assert(player:getTwillsFullAllianceState() == xi.trustRetailParity.sessionState.READY)
        assert(trustCount(player) == 17)

        player:setLocalVar('MochiriiTrustLogTruncated', 1)
        advanceTimers(6)

        assert(trustCount(player) == 0)
        assert(player:getLocalVar('MochiriiTrustAlliancePendingTimers') == 0)
        assert(player:getTwillsFullAllianceState() == xi.trustRetailParity.sessionState.IDLE)
        assert(player:getLocalVar('MochiriiTrustEvidenceMode') == xi.trustRetailParity.evidenceMode.IDLE)
        assert(player:getLocalVar('MochiriiTrustEvidenceSchema') == 0)
        assert(player:getCharVar('TrustEngageType') == 0)
        assertFailedSessionClosed()
    end)

    it('surfaces an evidence-close failure while still completing manual cleanup', function()
        assert(xi.trustRetailParity.summonRetail(player))
        advanceTimers(8)
        endSucceeds = false

        local cleared, reason = xi.trustRetailParity.clearSession(player, 'forced_end_failure')
        assert(not cleared and reason == 'evidence_close_failed')
        assert(trustCount(player) == 0)
        assert(player:getTwillsFullAllianceState() == xi.trustRetailParity.sessionState.IDLE)
        assert(player:getLocalVar('MochiriiTrustEvidenceMode') == xi.trustRetailParity.evidenceMode.IDLE)
        assert(player:getLocalVar('MochiriiTrustEvidenceSchema') == 0)
        assert(player:getLocalVar('MochiriiTrustAlliancePendingTimers') == 0)
        assert(player:getCharVar('TrustEngageType') == 0)
        local sessionEnd = findRecord('session_end', 'session_end')
        assert(sessionEnd ~= nil and sessionEnd.completion == 'cleared')
    end)

    it('never claims completion=cleared when Trust removal cannot be verified', function()
        assert(xi.trustRetailParity.summonRetail(player))
        advanceTimers(8)
        assert(xi.trustRetailParity.setClearTrustsTestHook(function()
            -- Deliberately leave the roster intact across both cleanup attempts.
        end))

        local cleared, reason = xi.trustRetailParity.clearSession(player, 'forced_clear_mismatch')
        assert(not cleared and reason == 'manual_clear_verification_failed')
        assert(trustCount(player) == 5)
        assert(player:getTwillsFullAllianceState() == xi.trustRetailParity.sessionState.IDLE)
        assert(player:getLocalVar('MochiriiTrustEvidenceMode') == xi.trustRetailParity.evidenceMode.IDLE)
        assert(player:getLocalVar('MochiriiTrustEvidenceSchema') == 0)
        assert(player:getLocalVar('MochiriiTrustAlliancePendingTimers') == 0)
        assert(player:getCharVar('TrustEngageType') == 0)
        local sessionEnd = findRecord('session_end', 'session_end')
        assert(sessionEnd ~= nil and sessionEnd.completion == 'failed')
        assert(findRecord('roster', 'failure') ~= nil)

        assert(xi.trustRetailParity.setClearTrustsTestHook(nil))
        player:clearTrusts()
    end)

    it('supports retail clear QA clear retail without stale callbacks', function()
        assert(xi.trustRetailParity.summonRetail(player))
        advanceTimers(8)
        assert(xi.trustRetailParity.clearSession(player, 'transition_retail_clear'))

        assert(xi.trustRetailParity.summonQa(player))
        advanceTimers(22)
        assert(xi.trustRetailParity.clearSession(player, 'transition_qa_clear'))

        assert(xi.trustRetailParity.summonRetail(player))
        advanceTimers(8)
        local audit = xi.trustRetailParity.rosterAudit(player, xi.trustRetailParity.evidenceMode.RETAIL)
        assert(audit.exactMatch)
        assert(player:getCharVar('TrustEngageType') == 0)
    end)

    it('cancels safely while spawning and invalidates every pending callback', function()
        assert(xi.trustRetailParity.summonQa(player))
        local spawningGeneration = player:getLocalVar('MochiriiTrustSessionGeneration')
        assert(xi.trustRetailParity.clearSession(player, 'clear_during_spawn'))

        assert(player:getLocalVar('MochiriiTrustSessionGeneration') ~= spawningGeneration)

        advanceTimers(50)

        assert(trustCount(player) == 0)
        assert(player:getTwillsFullAllianceState() == xi.trustRetailParity.sessionState.IDLE)
        assert(player:getLocalVar('MochiriiTrustEvidenceSchema') == 0)
        assert(player:getLocalVar('MochiriiTrustAlliancePendingTimers') == 0)
        assert(player:getCharVar('TrustEngageType') == 0)
        local sessionEnd = findRecord('session_end', 'session_end')
        assert(sessionEnd ~= nil and sessionEnd.completion == 'cleared')
        assert(sessionEnd.state == xi.trustRetailParity.sessionState.IDLE)
        for _, record in ipairs(records) do
            assert(record.state ~= xi.trustRetailParity.sessionState.FAILED)
        end
    end)

    it('fails closed when zoning interrupts a spawn', function()
        assert(xi.trustRetailParity.summonQa(player))
        advanceTimers(4)
        local activeBeforeZone = trustCount(player)
        assert(activeBeforeZone > 0 and activeBeforeZone < 17)

        player:gotoZone(xi.zone.EAST_RONFAURE)
        advanceTimers(50)

        assert(trustCount(player) == 0)
        assert(player:getTwillsFullAllianceState() == xi.trustRetailParity.sessionState.IDLE)
        assert(player:getLocalVar('MochiriiTrustEvidenceMode') == xi.trustRetailParity.evidenceMode.IDLE)
        assert(player:getLocalVar('MochiriiTrustEvidenceSchema') == 0)
        assert(player:getLocalVar('MochiriiTrustAlliancePendingTimers') == 0)
        assert(player:getCharVar('TrustEngageType') == 0)
        local failure = findRecord('roster', 'failure')
        local cleared = findRecord('roster', 'cleared')
        local sessionEnd = findRecord('session_end', 'session_end')
        assert(failure ~= nil and fieldValue(failure.fields, 'active_count') == tostring(activeBeforeZone))
        assert(cleared ~= nil and fieldValue(cleared.fields, 'active_count') == '0')
        assert(sessionEnd ~= nil and sessionEnd.reason == 'zone')
        assertFailedSessionClosed()
    end)

    it('closes an active session through the native logout lifecycle callbacks', function()
        assert(xi.trustRetailParity.summonQa(player))
        advanceTimers(22)
        assert(trustCount(player) == 17)

        player:simulateZoneOutLifecycle(true)

        assert(trustCount(player) == 0)
        assert(player:getTwillsFullAllianceState() == xi.trustRetailParity.sessionState.IDLE)
        assert(player:getLocalVar('MochiriiTrustEvidenceMode') == xi.trustRetailParity.evidenceMode.IDLE)
        assert(player:getLocalVar('MochiriiTrustEvidenceSchema') == 0)
        assert(player:getLocalVar('MochiriiTrustAlliancePendingTimers') == 0)
        assert(player:getCharVar('TrustEngageType') == 0)
        local failure = findRecord('roster', 'failure')
        local cleared = findRecord('roster', 'cleared')
        local sessionEnd = findRecord('session_end', 'session_end')
        assert(failure ~= nil and fieldValue(failure.fields, 'active_count') == '17')
        assert(cleared ~= nil and fieldValue(cleared.fields, 'active_count') == '0')
        assert(sessionEnd ~= nil and sessionEnd.reason == 'logout')
        assertFailedSessionClosed()
    end)

    it('cleans up a nil spawn and permits a fresh later session', function()
        local nativeSpawn = function(target, trustId)
            return target:spawnTrust(trustId)
        end

        local failNextSpawn = true
        assert(xi.trustRetailParity.setSpawnTrustTestHook(function(target, trustId)
            if failNextSpawn then
                failNextSpawn = false
                return nil
            end

            return nativeSpawn(target, trustId)
        end))

        assert(xi.trustRetailParity.summonRetail(player))
        advanceTimers(2)

        assert(trustCount(player) == 0)
        assert(player:getTwillsFullAllianceState() == xi.trustRetailParity.sessionState.IDLE)
        assert(player:getLocalVar('MochiriiTrustEvidenceSchema') == 0)
        assert(player:getLocalVar('MochiriiTrustEvidenceMode') == xi.trustRetailParity.evidenceMode.IDLE)
        assert(player:getCharVar('TrustEngageType') == 0)
        assertFailedSessionClosed()

        assert(xi.trustRetailParity.summonRetail(player))
        advanceTimers(8)
        assert(xi.trustRetailParity.rosterAudit(
            player,
            xi.trustRetailParity.evidenceMode.RETAIL).exactMatch)
    end)

    it('times out fail-closed and removes the partial roster', function()
        assert(xi.trustRetailParity.summonQa(player))
        player:setLocalVar('MochiriiTrustSessionStarted', GetSystemTime() - 46)

        advanceTimers(2)

        assert(trustCount(player) == 0)
        assert(player:getTwillsFullAllianceState() == xi.trustRetailParity.sessionState.IDLE)
        assert(player:getLocalVar('MochiriiTrustAlliancePendingTimers') == 0)
        assert(player:getCharVar('TrustEngageType') == 0)
        assert(player:getLocalVar('MochiriiTrustEvidenceSchema') == 0)
        assertFailedSessionClosed()
    end)

    it('rejects a real party without clearing the existing Trust roster', function()
        local existing = player:spawnTrust(xi.magic.spell.VALAINERAL)
        assert(existing ~= nil)

        local member = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE })
        player.actions:inviteToParty(member)
        member.actions:acceptPartyInvite()

        local started, reason = xi.trustRetailParity.summonQa(player)
        assert(not started and reason == 'real_player_roster_mismatch')
        assert(trustCount(player) == 1)
        assert(player:getTwillsFullAllianceState() == xi.trustRetailParity.sessionState.IDLE)
    end)

    it('rejects a real alliance without clearing the existing Trust roster', function()
        assert(player:spawnTrust(xi.magic.spell.VALAINERAL) ~= nil)

        local secondLeader = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE })
        local secondMember = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE })
        secondLeader.actions:inviteToParty(secondMember)
        secondMember.actions:acceptPartyInvite()
        player.actions:formAlliance(secondLeader)
        secondLeader.actions:acceptPartyInvite()
        assert(player:checkSoloPartyAlliance() == 2)

        local started, reason = xi.trustRetailParity.summonQa(player)
        assert(not started and reason == 'real_alliance_present')
        assert(trustCount(player) == 1)
        assert(player:getTwillsFullAllianceState() == xi.trustRetailParity.sessionState.IDLE)
    end)

    it('rejects an active battlefield without clearing the existing Trust roster', function()
        player:addMission(xi.mission.log_id.SANDORIA, xi.mission.id.sandoria.SAVE_THE_CHILDREN)
        player:setMissionStatus(xi.mission.log_id.SANDORIA, 2)
        player:gotoZone(xi.zone.GHELSBA_OUTPOST)
        configureTwills(player)
        player.bcnm:enter('Hut_Door', xi.battlefield.id.SAVE_THE_CHILDREN)
        assert(player:getBattlefield() ~= nil or player:getBattlefieldID() >= 0)

        assert(player:spawnTrust(xi.magic.spell.VALAINERAL) ~= nil)
        local started, reason = xi.trustRetailParity.summonQa(player)
        assert(not started and reason == 'battlefield_present')
        assert(trustCount(player) == 1)
        assert(player:getTwillsFullAllianceState() == xi.trustRetailParity.sessionState.IDLE)
    end)

    it('rejects an active instance without clearing the existing Trust roster', function()
        player:gotoZone(xi.zone.ALZADAAL_UNDERSEA_RUINS)
        configureTwills(player)
        assert(player:spawnTrust(xi.magic.spell.VALAINERAL) ~= nil)
        player:createInstance(7702)
        xi.test.world:tick(xi.tick.TIME)
        assert(player:getInstance() ~= nil)

        local started, reason = xi.trustRetailParity.summonQa(player)
        assert(not started and reason == 'instance_present')
        assert(trustCount(player) == 1)
        assert(player:getTwillsFullAllianceState() == xi.trustRetailParity.sessionState.IDLE)
    end)

    it('rejects a Trust-disabled zone without clearing the existing Trust roster', function()
        player:gotoZone(xi.zone.CHOCOBO_CIRCUIT)
        configureTwills(player)
        assert(not player:canUseMisc(xi.zoneMisc.TRUST))

        assert(player:spawnTrust(xi.magic.spell.VALAINERAL) ~= nil)
        local started, reason = xi.trustRetailParity.summonQa(player)
        assert(not started and reason == 'zone_disallows_trusts')
        assert(trustCount(player) == 1)
        assert(player:getTwillsFullAllianceState() == xi.trustRetailParity.sessionState.IDLE)
    end)

    it('rejects enmity without clearing the existing Trust roster', function()
        local mob = player.entities:get(17109014) -- Forest Hare in West Ronfaure.
        assert(mob ~= nil)
        if not mob:isSpawned() then
            mob:spawn()
        end

        assert(player:spawnTrust(xi.magic.spell.VALAINERAL) ~= nil)
        mob:addEnmity(player, 1, 1)
        assert(player:hasEnmity())

        local started, reason = xi.trustRetailParity.summonQa(player)
        assert(not started and reason == 'player_has_enmity')
        assert(trustCount(player) == 1)
        assert(player:getTwillsFullAllianceState() == xi.trustRetailParity.sessionState.IDLE)
    end)

    it('keeps status, mode, audit, and repair lane-neutral', function()
        local trust = player:spawnTrust(xi.magic.spell.VALAINERAL)
        assert(trust ~= nil)
        local initialState = player:getTwillsFullAllianceState()
        local initialMode = player:getLocalVar('MochiriiTrustEvidenceMode')
        local initialSchema = player:getLocalVar('MochiriiTrustEvidenceSchema')
        local initialEngage = player:getCharVar('TrustEngageType')

        local statusRows = xi.trustRetailParity.partyRows(player, false)
        local modeRows = xi.trustRetailParity.modeRows(player)
        local auditRows = xi.trustRetailParity.auditRows(player, 'active')
        local repairRows = xi.trustRetailParity.partyRows(player, true)

        assert(#statusRows > 0 and #modeRows > 0 and #auditRows > 0 and #repairRows > 0)
        assert(player:getTwillsFullAllianceState() == initialState)
        assert(player:getLocalVar('MochiriiTrustEvidenceMode') == initialMode)
        assert(player:getLocalVar('MochiriiTrustEvidenceSchema') == initialSchema)
        assert(player:getCharVar('TrustEngageType') == initialEngage)
        assert(next(attached) == nil, 'read-only and repair paths must not attach evidence listeners')
    end)
end)
