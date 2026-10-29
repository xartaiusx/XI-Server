-----------------------------------
-- Native release lifecycle; only synthetic fixture identities are changed.
-----------------------------------
describe('Ordinary Trust return compatibility', function()
    ---@type CClientEntityPair
    local owner
    local sequence = 0

    local function summon(count)
        local ids = {}
        for spell = xi.magic.spell.NAJI, xi.magic.spell.NAJI + count - 1 do
            local trust = owner:spawnTrust(spell)
            assert(trust, 'native fixture summon must succeed')
            trust:removeAllGambits()
            trust:setAutoAttackEnabled(false)
            trust:setMobAbilityEnabled(false)
            ids[#ids + 1] = trust:getID()
        end

        return ids
    end

    local function request(all, trust, issued)
        sequence = sequence + 1
        return string.format('%08x%08x %u %u %s %u %u', issued or GetSystemTime(), sequence,
            owner:getID(), owner:getZoneID(), all and 'all' or 'one', trust and trust:getID() or 0, trust and trust:getTargID() or 0)
    end

    local function ending(text, expected)
        assert(text:sub(-#expected) == expected, text)
    end

    before_each(function()
        -- Normalize inherited test-world calendar offsets before nonce creation.
        SetTimeOffset(0)
        xi.test.world:setSetting('main.ENABLE_MOCHIRII_TWILLS_TRUST_GAMEPLAY', true)
        xi.test.world:setSetting('main.ENABLE_MOCHIRII_TWILLS_FULL_ALLIANCE', true)
        xi.test.world:setSetting('main.MOCHIRII_TWILLS_FULL_ALLIANCE_MAX_PARTIES', 3)
        owner = xi.test.world:spawnPlayer({ name = 'Twills', zone = xi.zone.WEST_RONFAURE, job = xi.job.RDM, level = 99 })
        owner:setGMLevel(5)
        owner:setVisibleGMLevel(0)
        owner:setCharVar('MochiriiTrustAllianceAccess', 1)
        assert(owner.actions:prepareSoloTrustParty())
        assert(owner:canUseTwillsTrustGameplay())
    end)

    it('releases all seventeen through the native delay and rejects replay against replacements', function()
        local ids = summon(17)
        local text = request(true)
        ending(owner:returnOrdinaryTrusts(text), 'ACCEPTED 17 OK')
        assert(#owner:getPartyWithTrusts() == 18, 'release must keep the native delay')
        xi.test.world:skipTime(1)
        assert(#owner:getPartyWithTrusts() == 18, 'the two-second native queue must not become immediate')
        xi.test.world:skipTime(3)
        xi.test.world:skipTime(3)
        assert(#owner:getPartyWithTrusts() == 1)
        for _, id in ipairs(ids) do
            assert(not owner.actions:hasTrustEntity(id), 'the released exact identity must retire')
        end

        local replacement = summon(1)[1]
        local replay = owner:returnOrdinaryTrusts(text)
        assert(replay:match(' DENIED 0 REPLAY$') or replay:match(' DENIED 0 STALE$'), replay)
        assert(owner:getPartyWithTrusts()[2]:getID() == replacement)
    end)

    it('keeps one initial callback and the existing natural terminal callback', function()
        local ids = summon(17)
        local first = owner:getPartyWithTrusts()[18]
        assert(first and first:isTrust(), 'the first single release must select the seventeenth Trust')
        local firstId = first:getID()
        local removed = {}
        local function assertRemaining()
            local party = owner:getPartyWithTrusts()
            local index = 2
            for _, id in ipairs(ids) do
                if not removed[id] then
                    assert(party[index] and party[index]:getID() == id, 'native compaction must preserve every remaining exact identity')
                    index = index + 1
                end
            end

            assert(#party == index - 1, 'native release must remove only the selected identities')
        end

        local messages = spy('xi.trust.message')
        local savedMessage = xi.trust.message
        local threw = false
        local text = request(false, first)
        rawset(xi.trust, 'message', function(mob, offset)
            savedMessage(mob, offset)
            if
                not threw and
                mob:getID() == firstId and
                offset == xi.trust.messageOffset.DESPAWN
            then
                threw = true
                error('ordinary_return_intentional_callback_error', 0)
            end
        end)

        local ok, result = pcall(function()
            return owner:returnOrdinaryTrusts(text)
        end)

        rawset(xi.trust, 'message', savedMessage) -- Finally restore before an assertion can exit.
        assert(ok, result)
        ending(result, 'UNCERTAIN 1 PARTIAL')
        assert(threw and owner:canUseTwillsTrustGameplay(), 'callback error must be observed without policy drift')
        messages:called(1)
        ending(owner:returnOrdinaryTrusts(text), 'DENIED 0 REPLAY')
        xi.test.world:skipTime(3)
        xi.test.world:skipTime(3)
        messages:called(2)
        removed[firstId] = true
        assert(not owner.actions:hasTrustEntity(firstId), 'callback error must not cancel the native queued retirement')
        assertRemaining()

        local second = owner:getPartyWithTrusts()[2]
        assert(second and second:isTrust())
        local secondId = second:getID()
        local revoked = false
        local secondText = request(false, second)
        rawset(xi.trust, 'message', function(mob, offset)
            savedMessage(mob, offset)
            if
                not revoked and
                mob:getID() == secondId and
                offset == xi.trust.messageOffset.DESPAWN
            then
                revoked = true
                owner:setCharVar('MochiriiTrustAllianceAccess', 0)
            end
        end)

        local secondOk, secondResult = pcall(function()
            return owner:returnOrdinaryTrusts(secondText)
        end)

        rawset(xi.trust, 'message', savedMessage) -- Finally restore before an assertion can exit.
        assert(secondOk, secondResult)
        ending(secondResult, 'UNCERTAIN 1 PARTIAL')
        assert(revoked and not owner:canUseTwillsTrustGameplay(), 'the second real callback must change admission without throwing')
        owner:setCharVar('MochiriiTrustAllianceAccess', 1)
        assert(owner:canUseTwillsTrustGameplay())
        messages:called(3)
        xi.test.world:skipTime(3)
        xi.test.world:skipTime(3)
        messages:called(4)
        removed[secondId] = true
        assert(not owner.actions:hasTrustEntity(secondId))
        assertRemaining()
    end)

    it('rejects a mismatched full identity and stale nonce without release', function()
        summon(1)
        local trust = owner:getPartyWithTrusts()[2]
        local text = request(false, trust):gsub(' one %d+ ', ' one 1 ')
        ending(owner:returnOrdinaryTrusts(text), 'DENIED 0 TARGET')
        ending(owner:returnOrdinaryTrusts(request(false, trust, GetSystemTime() - 5)), 'DENIED 0 STALE')
        assert(#owner:getPartyWithTrusts() == 2)
    end)

    it('rejects a native blocked state without force disengagement or release', function()
        summon(1)
        owner:addStatusEffect(xi.effect.GESTATION, { origin = owner, power = 1, duration = 60 })
        ending(owner:returnOrdinaryTrusts(request(true)), 'DENIED 0 CONTEXT')
        assert(owner:hasStatusEffect(xi.effect.GESTATION))
        assert(#owner:getPartyWithTrusts() == 2)
    end)

    it('does not turn an oversized revoked ordinary roster into native fallback', function()
        summon(17)
        owner:setCharVar('MochiriiTrustAllianceAccess', 0)
        ending(owner:returnOrdinaryTrusts(request(true)), 'DENIED 0 POLICY')
        assert(#owner:getPartyWithTrusts() == 18, 'this request must not use administrative clear')
    end)

    it('classifies positive retail and QA lanes without custom release', function()
        summon(1)
        owner:setCharVar('MochiriiTrustAllianceAccess', 0)
        ending(owner:returnOrdinaryTrusts(request(true)), 'NATIVE 0 RETAIL')
        owner:setCharVar('MochiriiTrustAllianceAccess', 1)
        assert(owner:setTwillsFullAllianceState(1))
        owner:setLocalVar('MochiriiTrustEvidenceMode', 2)
        ending(owner:returnOrdinaryTrusts(request(true)), 'NATIVE 0 QA')
        assert(owner:getTwillsFullAllianceState() == 1)
        assert(owner:getLocalVar('MochiriiTrustEvidenceMode') == 2)
        assert(#owner:getPartyWithTrusts() == 2)
    end)
end)
