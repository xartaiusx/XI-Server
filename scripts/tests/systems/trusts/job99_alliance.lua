-----------------------------------
-- Ordinary individual Trust summons, separate from QA evidence sessions.
-- Source: spell.h IDs897..914 and each corresponding Trust casting check.
-- These are normal, non-Unity variants; none of their mutually exclusive
-- alternate variants are in this roster. Ulmia914 is the distinct overflow.
-- name='Twills' is an in-memory policy override. The test engine creates a
-- unique generated DB identity; learning below affects that fixture only.
-----------------------------------
describe('Ordinary entitled Trust alliance', function()
    ---@type CClientEntityPair
    local player
    local originalLogger = xi.trustActionLogger

    local roster =
    {
        xi.magic.spell.NAJI,
        xi.magic.spell.KUPIPI,
        xi.magic.spell.EXCENMILLE,
        xi.magic.spell.AYAME,
        xi.magic.spell.NANAA_MIHGO,
        xi.magic.spell.CURILLA,
        xi.magic.spell.VOLKER,
        xi.magic.spell.AJIDO_MARUJIDO,
        xi.magic.spell.TRION,
        xi.magic.spell.ZEID,
        xi.magic.spell.LION,
        xi.magic.spell.TENZEN,
        xi.magic.spell.MIHLI_ALIAPOH,
        xi.magic.spell.VALAINERAL,
        xi.magic.spell.JOACHIM,
        xi.magic.spell.NAJA_SALAHEEM,
        xi.magic.spell.PRISHE,
    }

    local function findTrust(id)
        for _, member in ipairs(player:getPartyWithTrusts()) do
            if member:isTrust() and member:getTrustID() == id then
                return member
            end
        end

        return nil
    end

    local function attempt(id, expectedMembers, successful)
        -- Reset only the synthetic PC's recasts to isolate admission and prevent
        -- a duplicate's own summon cooldown from masking the policy under test.
        player:resetRecasts()
        player.actions:useSpell(player, id)
        xi.test.world:tickEntity(player)
        if successful then
            xi.test.world:skipTime(3)
            xi.test.world:skipTime(3)
        else
            xi.test.world:skipTime(1)
        end

        assert(#player:getPartyWithTrusts() == expectedMembers, 'native summon admission produced an unexpected roster size')
        if successful then
            local trust = findTrust(id)
            assert(trust, 'eligible learned Trust must exist after its native summon')
            trust:removeAllGambits()
            trust:setAutoAttackEnabled(false)
            trust:setMobAbilityEnabled(false)
        end
    end

    local function summonRoster(count)
        local ids = {}
        for index = 1, count do
            local spell = roster[index]
            attempt(spell, index + 1, true)
            local trust = findTrust(spell)
            assert(trust, 'the native roster member must exist before revocation')
            table.insert(ids, trust:getID())
        end

        return ids
    end

    local function assertNativeCleanup(ids)
        xi.test.world:tickEntity(player)
        assert(#player:getPartyWithTrusts() == 1, 'revoked oversized ordinary rosters must be cleared')
        xi.test.world:skipTime(3)
        xi.test.world:skipTime(3)
        for _, id in ipairs(ids) do
            assert(not player.actions:hasTrustEntity(id), 'cleanup must retire every exact native Trust entity')
        end

        assert(player:getTwillsFullAllianceState() == 0 and player:getLocalVar('MochiriiTrustEvidenceMode') == 0)
    end

    local function assertWarcryScope(expectFar)
        local caster = findTrust(xi.magic.spell.NAJI)
        local near = findTrust(xi.magic.spell.PRISHE)
        local far = findTrust(xi.magic.spell.KUPIPI)
        assert(caster and near and far, 'the cross-projection fixture requires all three native Trusts')
        assert(caster:getMainJob() == xi.job.WAR)
        local x, y, z = player:getXPos(), player:getYPos(), player:getZPos()
        for _, member in ipairs(player:getPartyWithTrusts()) do
            if member:isTrust() then
                member:setMobMod(xi.mobMod.NO_MOVE, 1)
                member:setPos(x, y, z)
            end
        end

        -- Native Warcry32 has radius14. Naji is projected group0, Prishe group2.
        near:setPos(x + 2, y, z)
        far:setPos(x + 25, y, z)
        player.packets:clear()
        assert(player.actions:useTrustAbility(caster, caster, xi.jobAbility.WARCRY))
        xi.test.world:tickEntity(caster)
        xi.test.world:skipTime(1)
        assert(near:checkDistance(caster) < 14 and far:checkDistance(caster) > 14, 'the native action must retain a near/far control')
        assert(near:hasStatusEffect(xi.effect.WARCRY), 'a near last-group recipient must receive party support across UI projection')
        assert(near:getStatusEffect(xi.effect.WARCRY):getOriginID() == caster:getID())
        assert(far:hasStatusEffect(xi.effect.WARCRY) == expectFar, 'only qualified lanes should change the legacy radius bypass')
        local targets = {}
        for _, packet in ipairs(player.packets:actionPackets()) do
            if
                packet.m_uID == caster:getID() and
                packet.cmd_no == xi.action.category.JOBABILITY_FINISH
            then
                for _, victim in ipairs(packet.target) do
                    targets[victim.m_uID] = true
                end
            end
        end

        assert(targets[near:getID()] == true)
        assert((targets[far:getID()] == true) == expectFar, 'native action recipients must match applied buff scope')
    end

    before_each(function()
        xi.test.world:setSetting('main.ENABLE_TRUST_CASTING', 1)
        xi.test.world:setSetting('main.ENABLE_MOCHIRII_TWILLS_TRUST_GAMEPLAY', true)
        xi.test.world:setSetting('main.ENABLE_MOCHIRII_TWILLS_FULL_ALLIANCE', false)
        xi.test.world:setSetting('main.MOCHIRII_TWILLS_FULL_ALLIANCE_MAX_PARTIES', 3)
        xi.test.world:setSetting('main.TRUST_JOB99_VALAINERAL', true)
        xi.test.world:setSetting('main.ENABLE_TRUST_ACTION_LOG', false)
        xi.trustActionLogger = nil
        player = xi.test.world:spawnPlayer({ name = 'Twills', zone = xi.zone.WEST_RONFAURE, job = xi.job.RDM, level = 99 })
        player:setGMLevel(5)
        player:setVisibleGMLevel(0) -- Do not use the visible-GM Trust casting bypass.
        player:setCharVar('MochiriiTrustAllianceAccess', 1)
        player:addKeyItem(xi.keyItem.SAN_DORIA_TRUST_PERMIT)
        player:addKeyItem(xi.keyItem.RHAPSODY_IN_WHITE)
        player:addKeyItem(xi.keyItem.RHAPSODY_IN_CRIMSON)
        for _, id in ipairs(roster) do
            player:addSpell(id)
        end

        player:addSpell(xi.magic.spell.ULMIA)
        assert(player.actions:prepareSoloTrustParty(), 'named fixture needs a native solo party leader')
        local leader = player:getPartyLeader()
        assert(leader and leader:getID() == player:getID(), 'native party leader must be this fixture PC')
        assert(#player:getPartyWithTrusts() == 1)
        assert(not player.actions:prepareSoloTrustParty(), 'bootstrap must not replace an existing party')
        assert(player:canUseTwillsTrustGameplay())
        assert(not player:canUseTwillsFullAlliance(), 'ordinary admission must not require or activate the QA feature')
        assert(player:getTwillsFullAllianceState() == 0 and player:getLocalVar('MochiriiTrustEvidenceMode') == 0)
    end)

    after_each(function()
        xi.trustActionLogger = originalLogger
    end)

    it('summons seventeen individually and retains corpse capacity until native dismissal', function()
        for index, id in ipairs(roster) do
            attempt(id, index + 1, true)
            assert(player:canUseTwillsTrustGameplay(), 'virtual alliance display must preserve the physical solo-owner admission shape')
        end

        assert(#player:getPartyWithTrusts() == 18)
        attempt(xi.magic.spell.ULMIA, 18, false)
        assert(findTrust(xi.magic.spell.ULMIA) == nil, 'an eighteenth Trust must not enter the roster')

        local val = findTrust(xi.magic.spell.VALAINERAL)
        assert(val, 'the seventeen-summon fixture must contain Valaineral')
        local oldId = val:getID()
        val:setHP(0)
        xi.test.world:tickEntity(val)
        assert(val:isDead() and val:canReceiveTrustRaise())
        assert(val:offerTrustRaise(1, false, false))
        assert(#player:getPartyWithTrusts() == 18)
        attempt(xi.magic.spell.VALAINERAL, 18, false)
        attempt(xi.magic.spell.ULMIA, 18, false)

        -- The native Talk action releases an owned Trust and runs its delayed
        -- removal. Never keep/dereference the old Lua entity after removal.
        player.actions:trigger(val)
        xi.test.world:skipTime(3)
        xi.test.world:skipTime(3)
        assert(findTrust(xi.magic.spell.VALAINERAL) == nil)
        assert(#player:getPartyWithTrusts() == 17)
        assert(not player.actions:hasTrustEntity(oldId), 'native dismissal must retire the retained corpse')
        attempt(xi.magic.spell.VALAINERAL, 18, true)
        local replacement = findTrust(xi.magic.spell.VALAINERAL)
        assert(replacement, 'the dismissed Valaineral must be replaced by the native summon')
        assert(replacement:isAlive() and not replacement:hasStatusEffect(xi.effect.WEAKNESS))
        assert(player:getTwillsFullAllianceState() == 0 and player:getLocalVar('MochiriiTrustEvidenceMode') == 0)
    end)

    it('keeps the normal five-Trust cap when feature or authorization is absent', function()
        xi.test.world:setSetting('main.ENABLE_MOCHIRII_TWILLS_TRUST_GAMEPLAY', false)
        assert(not player:canUseTwillsTrustGameplay())
        for index = 1, 5 do
            attempt(roster[index], index + 1, true)
        end

        attempt(roster[6], 6, false)
        xi.test.world:setSetting('main.ENABLE_MOCHIRII_TWILLS_TRUST_GAMEPLAY', true)
        player:setVisibleGMLevel(1)
        assert(not player:canUseTwillsTrustGameplay())
        attempt(roster[6], 6, false)
        player:setVisibleGMLevel(0)
        player:setCharVar('MochiriiTrustAllianceAccess', 0)
        assert(not player:canUseTwillsTrustGameplay())
        attempt(roster[6], 6, false)
        player:setCharVar('MochiriiTrustAllianceAccess', 1)
        assert(player:canUseTwillsTrustGameplay())
        attempt(roster[6], 7, true)
    end)

    it('supports the last projected group while honoring the native ordinary Warcry radius', function()
        summonRoster(17)
        assert(player:canUseTwillsTrustGameplay())
        assertWarcryScope(false)
    end)

    it('preserves the legacy QA Warcry recipient behavior', function()
        summonRoster(17)
        xi.test.world:setSetting('main.ENABLE_MOCHIRII_TWILLS_FULL_ALLIANCE', true)
        player:setLocalVar('MochiriiTrustEvidenceMode', 2)
        assert(player:setTwillsFullAllianceState(1))
        assert(player:setTwillsFullAllianceState(2))
        assert(player:isTwillsFullAllianceActive() and not player:canUseTwillsTrustGameplay())
        assertWarcryScope(true)
    end)

    it('retires all seventeen native Trusts when ordinary entitlement is revoked', function()
        local ids = summonRoster(17)
        player:setCharVar('MochiriiTrustAllianceAccess', 0)
        assert(not player:canUseTwillsTrustGameplay())
        assertNativeCleanup(ids)
        assert(player:getCharVar('MochiriiTrustAllianceAccess') == 0)
    end)

    it('retires all seventeen native Trusts when the ordinary feature is disabled', function()
        local ids = summonRoster(17)
        xi.test.world:setSetting('main.ENABLE_MOCHIRII_TWILLS_TRUST_GAMEPLAY', false)
        assert(not player:canUseTwillsTrustGameplay())
        assertNativeCleanup(ids)
        assert(player:getCharVar('MochiriiTrustAllianceAccess') == 1, 'cleanup must preserve the permanent entitlement')
    end)

    it('preserves exactly five native Trusts after ordinary authorization is lost', function()
        local ids = summonRoster(5)
        player:setCharVar('MochiriiTrustAllianceAccess', 0)
        assert(not player:canUseTwillsTrustGameplay())
        xi.test.world:tickEntity(player)
        xi.test.world:skipTime(3)
        assert(#player:getPartyWithTrusts() == 6)
        for _, id in ipairs(ids) do
            assert(player.actions:hasTrustEntity(id), 'a retail-sized roster must retain its exact native entities')
        end
    end)

    it('leaves evidence mode and nonidle session cleanup outside the ordinary revocation guard', function()
        local ids = summonRoster(6)
        xi.test.world:setSetting('main.ENABLE_MOCHIRII_TWILLS_TRUST_GAMEPLAY', false)
        player:setLocalVar('MochiriiTrustEvidenceMode', 2)
        xi.test.world:tickEntity(player)
        assert(#player:getPartyWithTrusts() == 7, 'nonidle evidence mode must retain its own lifecycle')
        player:setLocalVar('MochiriiTrustEvidenceMode', 0)
        assert(player:setTwillsFullAllianceState(1))
        xi.test.world:tickEntity(player)
        assert(#player:getPartyWithTrusts() == 7, 'nonidle session state must retain its own lifecycle')
        xi.test.world:setSetting('main.ENABLE_MOCHIRII_TWILLS_FULL_ALLIANCE', true)
        player:setLocalVar('MochiriiTrustEvidenceMode', 2)
        assert(player:setTwillsFullAllianceState(2))
        assert(player:isTwillsFullAllianceActive())
        xi.test.world:tickEntity(player)
        xi.test.world:skipTime(3)
        assert(#player:getPartyWithTrusts() == 7 and player:isTwillsFullAllianceActive())
        for _, id in ipairs(ids) do
            assert(player.actions:hasTrustEntity(id), 'ordinary cleanup must not retire a QA-state native entity')
        end
    end)

    it('does not turn evidence lanes into ordinary admission', function()
        for _, mode in ipairs({ 1, 2 }) do
            player:setLocalVar('MochiriiTrustEvidenceMode', mode)
            assert(not player:canUseTwillsTrustGameplay())
        end

        player:setLocalVar('MochiriiTrustEvidenceMode', 0)
        assert(player:canUseTwillsTrustGameplay())
    end)

    it('preserves actual learning and mutually exclusive variant restrictions', function()
        assert(not player:hasSpell(xi.magic.spell.CHERUKIKI))
        attempt(xi.magic.spell.CHERUKIKI, 1, false)
        assert(not player:hasSpell(xi.magic.spell.CHERUKIKI), 'ordinary entitlement must not grant spells')
        attempt(xi.magic.spell.PRISHE, 2, true)
        player:addSpell(xi.magic.spell.PRISHE_II) -- Synthetic fixture only.
        attempt(xi.magic.spell.PRISHE_II, 2, false)
        assert(findTrust(xi.magic.spell.PRISHE_II) == nil, 'ordinary capacity must preserve exclusive alternate-variant checks')
    end)
end)
