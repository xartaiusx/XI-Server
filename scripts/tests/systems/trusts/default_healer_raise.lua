-----------------------------------
-- Native isolated fixtures only. LIVE validation keeps the full approved default18.
-----------------------------------
describe('Ordinary default WHM recovery', function()
    ---@type CClientEntityPair|nil
    local owner
    local healers = { xi.magic.spell.CHERUKIKI, xi.magic.spell.KARAHA_BARUHA }

    local function findTrust(spell)
        local owner = assert(owner)
        for _, member in ipairs(owner:getPartyWithTrusts()) do
            if member:isTrust() and member:getTrustID() == spell then
                return member
            end
        end

        return nil
    end

    local function fixture(spell, level, name)
        if owner then
            owner:clearTrusts()
        end

        owner = xi.test.world:spawnPlayer({ name = name or 'Twills', zone = xi.zone.WEST_RONFAURE,
            job = xi.job.RDM, level = level or 99 })
        owner:setGMLevel(5)
        owner:setVisibleGMLevel(0)
        owner:setCharVar('MochiriiTrustAllianceAccess', 1)
        owner:addKeyItem(xi.keyItem.SAN_DORIA_TRUST_PERMIT)
        owner:addKeyItem(xi.keyItem.RHAPSODY_IN_WHITE)
        owner:addKeyItem(xi.keyItem.RHAPSODY_IN_CRIMSON)
        assert(owner.actions:prepareSoloTrustParty())
        assert(owner:spawnTrust(spell) ~= nil)
        assert(owner:spawnTrust(xi.magic.spell.VALAINERAL) ~= nil)
        local healer = assert(findTrust(spell))
        local val = assert(findTrust(xi.magic.spell.VALAINERAL))
        assert(healer:getMainJob() == xi.job.WHM and not healer:isDevelopedTrust())
        assert(healer:getMainLvl() == (level or 99), 'native baseline level premise must be exact')
        return healer, val
    end

    local function observe(healer, val, rows)
        rows = rows or { starts = {}, uses = {}, interrupts = {} }
        for _, pair in ipairs({ { 'MAGIC_START', 'starts' }, { 'MAGIC_USE', 'uses' }, { 'MAGIC_INTERRUPTED', 'interrupts' } }) do
            local kind, bucket = pair[1], pair[2]
            healer:addListener(kind, 'DEFAULT_RAISE_' .. kind, function(caster, target, spell)
                if
                    target:getID() == val:getID() and
                    (spell:getID() == 12 or spell:getID() == 13 or spell:getID() == 140)
                then
                    table.insert(rows[bucket], { actor = caster:getID(), spell = spell:getID(), mp = caster:getMP(),
                        targetHP = target:getHP(), raiseEligible = target:canReceiveTrustRaise() })
                end
            end)
        end

        return rows
    end

    local function knockOut(val)
        val:setHP(0) -- Isolated native fixture setup, never part of production behavior.
        xi.test.world:tickEntity(val)
        assert(val:isDead() and val:canReceiveTrustRaise())
    end

    local function waitFor(predicate)
        for _ = 1, 45 do
            xi.test.world:skipTime(1)
            if predicate() then
                return
            end
        end

        assert(false, 'bounded natural default healer recovery did not complete')
    end

    local function natural(spell, level, expected)
        local healer, val = fixture(spell, level)
        local owner = assert(owner)
        local rows = observe(healer, val)
        local id, index = val:getID(), val:getTargID()
        local main, sub, mlvl, slvl = healer:getMainJob(), healer:getSubJob(), healer:getMainLvl(), healer:getSubLvl()
        local list = healer:getSpellListId()
        local spawned = 0
        val:addListener('SPAWN', 'DEFAULT_RAISE_NO_SPAWN', function()
            spawned = spawned + 1
        end)

        assert(healer:getMP() >= 150, 'native baseline mana must support the positive premise')
        knockOut(val)
        waitFor(function()
            return not val:isDead()
        end)

        assert(#rows.starts == 1 and #rows.uses == 1 and #rows.interrupts == 0)
        assert(rows.starts[1].spell == expected and rows.uses[1].spell == expected)
        assert(rows.uses[1].mp < rows.starts[1].mp, 'native completion must debit mana')
        assert(healer:hasRecast(xi.recast.MAGIC, expected))
        assert(findTrust(xi.magic.spell.VALAINERAL):getID() == id and val:getTargID() == index)
        assert(#owner:getPartyWithTrusts() == 3 and spawned == 0 and val:hasStatusEffect(xi.effect.WEAKNESS))
        assert(healer:getMainJob() == main and healer:getSubJob() == sub and
            healer:getMainLvl() == mlvl and healer:getSubLvl() == slvl and not healer:isDevelopedTrust())
        assert(healer:getSpellListId() == list, 'the shared native catalog identity must not be replaced')
        assert(not owner:isEngaged() and not healer:isEngaged())
    end

    before_each(function()
        owner = nil
        xi.test.world:setSetting('main.ENABLE_TRUST_CASTING', 1)
        xi.test.world:setSetting('main.ENABLE_MOCHIRII_TWILLS_TRUST_GAMEPLAY', true)
        xi.test.world:setSetting('main.ENABLE_MOCHIRII_TWILLS_FULL_ALLIANCE', false)
        xi.test.world:setSetting('main.TRUST_JOB99_VALAINERAL', true)
    end)

    it('lets baseline Cherukiki naturally Raise retained Val with native costs', function()
        natural(xi.magic.spell.CHERUKIKI, 99, xi.magic.spell.RAISE_III)
    end)

    it('lets baseline Karaha Baruha naturally Raise retained Val without job conversion', function()
        natural(xi.magic.spell.KARAHA_BARUHA, 99, xi.magic.spell.RAISE_III)
    end)

    it('uses canonical WHM Raise level thresholds for both ordinary baseline healers', function()
        for _, spell in ipairs(healers) do
            local healer, val = fixture(spell, 24)
            local rows = observe(healer, val)
            knockOut(val)
            xi.test.world:skipTime(3)
            xi.test.world:skipTime(3)
            assert(#rows.starts == 0 and val:getHP() == 0 and val:canReceiveTrustRaise())
            for _, tier in ipairs({ { 25, 12 }, { 55, 12 }, { 56, 13 }, { 69, 13 }, { 70, 140 } }) do
                natural(spell, tier[1], tier[2])
            end
        end
    end)

    it('keeps native mana Silence recast and range rejection for both default healers', function()
        for _, spell in ipairs(healers) do
            for _, blocked in ipairs({ 'mp', 'silence', 'recast', 'range' }) do
                local healer, val = fixture(spell, 99)
                local owner = assert(owner)
                local rows = observe(healer, val)
                knockOut(val)
                if blocked == 'mp' then
                    assert(healer:addStatusEffect(xi.effect.PLAGUE, { power = 5, duration = 30, origin = healer }))
                    healer:setMP(0)
                elseif blocked == 'silence' then
                    assert(healer:addStatusEffect(xi.effect.SILENCE, { power = 1, duration = 30, origin = healer }))
                elseif blocked == 'recast' then
                    for _, id in ipairs({ 12, 13, 140 }) do
                        healer:addRecast(xi.recast.MAGIC, id, 60)
                    end
                else
                    val:setPos(owner:getXPos() + 1000, owner:getYPos(), owner:getZPos())
                end

                xi.test.world:skipTime(3)
                if blocked == 'range' then
                    assert(healer:checkDistance(val) > 40)
                end

                xi.test.world:skipTime(3)
                if blocked == 'range' then
                    assert(healer:checkDistance(val) > 40)
                end

                if blocked == 'mp' then
                    assert(healer:getMP() == 0 and healer:hasStatusEffect(xi.effect.PLAGUE))
                end

                assert(#rows.starts == 0 and val:getHP() == 0 and val:canReceiveTrustRaise(), blocked)
            end
        end
    end)

    it('does not install ordinary default healer recovery for another character', function()
        for _, spell in ipairs(healers) do
            local healer, val = fixture(spell, 99, 'OtherRaiseProbe')
            local owner = assert(owner)
            assert(not owner:canUseTwillsTrustGameplay())
            local rows = observe(healer, val)
            knockOut(val)
            xi.test.world:skipTime(3)
            xi.test.world:skipTime(3)
            assert(#rows.starts == 0 and val:getHP() == 0 and val:canReceiveTrustRaise())
        end
    end)

    it('preserves preexisting native Raise catalog entries without duplicate casts', function()
        for _, spell in ipairs(healers) do
            local healer, val = fixture(spell, 99)
            healer:setSpellList(356) -- Isolated preexisting native Raise list; no production list mutation.
            local rows = observe(healer, val)
            knockOut(val)
            waitFor(function()
                return not val:isDead()
            end)

            assert(#rows.starts == 1 and #rows.uses == 1 and rows.uses[1].spell == xi.magic.spell.RAISE_III)
            assert(healer:getSpellListId() == 356 and not healer:isDevelopedTrust())
        end
    end)

    it('lets two default WHM healers produce one effective native recovery without suppressing their AI', function()
        local first, val = fixture(xi.magic.spell.CHERUKIKI, 99)
        local owner = assert(owner)
        assert(owner:spawnTrust(xi.magic.spell.KARAHA_BARUHA) ~= nil)
        local second = assert(findTrust(xi.magic.spell.KARAHA_BARUHA))
        local rows = observe(first, val)
        observe(second, val, rows)
        local gains, spawned = 0, 0
        val:addListener('EFFECT_GAIN', 'DEFAULT_RAISE_ONE_WEAKNESS', function(_, effect)
            if effect:getEffectType() == xi.effect.WEAKNESS then
                gains = gains + 1
            end
        end)

        val:addListener('SPAWN', 'DEFAULT_RAISE_RACE_NO_SPAWN', function()
            spawned = spawned + 1
        end)

        local id, index = val:getID(), val:getTargID()
        knockOut(val)
        waitFor(function()
            return #rows.uses > 0
        end)

        assert(rows.uses[1].targetHP == 0 and not rows.uses[1].raiseEligible,
            'the native USE callback must observe the first pending offer on the same corpse')
        waitFor(function()
            return not val:isDead()
        end)

        assert(gains == 1 and spawned == 0 and #owner:getPartyWithTrusts() == 4)
        assert(val:getID() == id and val:getTargID() == index)
        assert(#rows.starts >= 1 and #rows.uses >= 1)
        for _, row in ipairs(rows.starts) do
            assert(row.spell == xi.magic.spell.RAISE_III)
        end

        for _, row in ipairs(rows.uses) do
            assert(row.spell == xi.magic.spell.RAISE_III)
        end

        assert(not first:isDevelopedTrust() and not second:isDevelopedTrust())
        -- A losing native cast may interrupt/no-effect; do not force one START or disable a healer.
    end)

    local function probe(healer, overrides, exerciseException)
        local result = xi.test.world:probeTrustRaiseCatalog(healer, overrides, exerciseException)
        assert(result.valid)
        assert(result.storedCatalogUnchanged and result.storedVectorsUnchanged and
            result.probeVectorsUnchanged and result.resourcesUnchanged)
        assert(result.selected == result.repeated, 'repeated native queries must be stable')
        return result
    end

    it('keeps higher existing native minima including explicit255 authoritative', function()
        for _, spell in ipairs(healers) do
            local healer = fixture(spell, 99)
            for _, minimum in ipairs({ 120, 255 }) do
                local result = probe(healer, { { spellId = 140, minLevel = minimum, maxLevel = 255 } })
                assert(result.selected == 13 and result.minimums[140] == minimum)
                assert(result.originalMinimums[140] == 255 and not result.compatibility[140] and not result.canUse[140])
                assert(result.compatibility[12] and result.compatibility[13])
            end

            local excluded = probe(healer, { { spellId = 140, minLevel = 1, maxLevel = 30 } })
            assert(excluded.selected == 13 and not excluded.compatibility[140],
                'presence must preserve the native family maximum-level exclusion')
            -- Native baseline CanUseSpell historically checks minimum only; preserve that generic behavior.
            assert(excluded.canUse[140])
        end
    end)

    it('preserves existing native Arise priority and repeated-query catalog counts', function()
        for _, spell in ipairs(healers) do
            local healer = fixture(spell, 99)
            assert(healer:getMP() >= 300, 'Arise native cost premise')
            local result = probe(healer, {
                { spellId = 12, minLevel = 25, maxLevel = 255 },
                { spellId = 13, minLevel = 56, maxLevel = 255 },
                { spellId = 140, minLevel = 70, maxLevel = 255 },
                { spellId = 494, minLevel = 91, maxLevel = 255 },
            })
            assert(result.selected == 494 and result.probeRaiseCount == 4)
            for _, id in ipairs({ 12, 13, 140, 494 }) do
                assert(not result.compatibility[id] and result.canUse[id])
            end

            local normal = probe(healer)
            assert(normal.selected == 140 and normal.probeRaiseCount == 0,
                'temporary native fixture entries must not persist or append duplicate catalog rows')
        end
    end)

    it('rechecks the new native seam under explicit private QA and retail modes', function()
        for _, spell in ipairs(healers) do
            local healer = fixture(spell, 99)
            local owner = assert(owner)
            assert(probe(healer).selected == 140)
            -- Deliberate isolated synchronous query fixture; no tick/action while mode is changed.
            -- This is not a live/public transition workflow and does not replace its clear controls.
            for _, mode in ipairs({ xi.trustRetailParity.evidenceMode.QA, xi.trustRetailParity.evidenceMode.RETAIL }) do
                owner:setLocalVar('MochiriiTrustEvidenceMode', mode)
                local result = probe(healer)
                assert(result.selected == nil)
                for _, id in ipairs({ 12, 13, 140 }) do
                    assert(not result.compatibility[id] and not result.canUse[id])
                end

                owner:setLocalVar('MochiriiTrustEvidenceMode', xi.trustRetailParity.evidenceMode.IDLE)
                assert(probe(healer).selected == 140)
            end
        end
    end)

    it('leaves the currently approved developed Val catalog route unchanged', function()
        local _, val = fixture(xi.magic.spell.CHERUKIKI, 99)
        assert(val:isDevelopedTrust() and val:getMainJob() == xi.job.PLD and val:getSubJob() == xi.job.WAR)
        local result = probe(val)
        assert(result.selected == xi.magic.spell.RAISE and result.canUse[12] and not result.canUse[140])
        for _, id in ipairs({ 12, 13, 140, 494 }) do
            assert(not result.compatibility[id])
        end

        -- No currently unapproved WHM profile is enabled to manufacture future overlap.
    end)

    it('naturally interrupts a queued default Raise when ordinary entitlement is revoked', function()
        for _, spell in ipairs(healers) do
            local healer, val = fixture(spell, 99)
            local owner = assert(owner)
            local rows = observe(healer, val)
            assert(healer:getMP() == healer:getMaxMP(), 'full native spawn mana makes a zero-cost rejection observable')
            knockOut(val)
            waitFor(function()
                return #rows.starts == 1
            end)

            assert(#rows.uses == 0 and val:canReceiveTrustRaise())
            local startMP = rows.starts[1].mp
            assert(startMP == healer:getMaxMP())
            owner.packets:clear() -- Isolate the later native interrupt; START is already recorded by the listener.
            owner:setCharVar('MochiriiTrustAllianceAccess', 0) -- Isolated native admission-revocation fixture only.
            assert(not owner:canUseTwillsTrustGameplay())
            local function nativeInterruptCount()
                local packets = owner.packets:actionPackets()
                assert(#packets <= 128, 'bounded native interrupt packet scan')
                local count = 0
                for _, packet in ipairs(packets) do
                    if
                        packet.m_uID == healer:getID() and packet.cmd_no == xi.action.category.MAGIC_START and
                        packet.cmd_arg == xi.action.fourCC.WHITE_MAGIC_INTERRUPT
                    then
                        assert(packet.trg_sum == 1)
                        for _, target in ipairs(packet.target) do
                            if target.m_uID == healer:getID() then
                                for _, result in ipairs(target.result) do
                                    if result.value == xi.magic.spell.RAISE_III then
                                        count = count + 1
                                    end
                                end
                            end
                        end
                    end
                end

                return count
            end

            -- End-of-cast legality rejection emits this native packet, not MAGIC_INTERRUPTED.
            waitFor(function()
                return nativeInterruptCount() > 0
            end)

            assert(nativeInterruptCount() == 1)
            assert(#rows.uses == 0 and val:getHP() == 0 and val:canReceiveTrustRaise())
            assert(healer:getMP() == startMP, 'rejected cast must not spend mana; native Refresh remains capped')
            assert(not healer:hasRecast(xi.recast.MAGIC, xi.magic.spell.RAISE_III))
        end
    end)

    it('restores the original native list after a caught test-only C++ exception', function()
        for _, spell in ipairs(healers) do
            local healer = fixture(spell, 99)
            local result = probe(healer, { { spellId = 140, minLevel = 120, maxLevel = 255 } }, true)
            assert(result.exceptionExercised and result.selected == 13)
            local normal = probe(healer)
            assert(not normal.exceptionExercised and normal.selected == 140 and normal.originalMinimums[140] == 255)
        end
    end)

    it('rejects wrong actors and bounded invalid probe rows without changing a native catalog', function()
        local healer = fixture(xi.magic.spell.CHERUKIKI, 99)
        local owner = assert(owner)
        assert(not xi.test.world:probeTrustRaiseCatalog(owner).valid, 'a simulation PC is not a Trust actor')
        for _, rows in ipairs({
            { { spellId = 1, minLevel = 1, maxLevel = 255 } },
            { { spellId = 140, minLevel = 256, maxLevel = 255 } },
            { { spellId = 140, minLevel = 0, maxLevel = 255 } },
            { { spellId = 140, minLevel = 70, maxLevel = 69 } },
            { { spellId = 140, minLevel = 0 / 0, maxLevel = 255 } },
            { { spellId = 140, minLevel = 70, maxLevel = math.huge } },
            { { spellId = 12, minLevel = 25, maxLevel = 255 }, { spellId = 12, minLevel = 25, maxLevel = 255 } },
            { { spellId = 12, minLevel = 25, maxLevel = 255 }, { spellId = 13, minLevel = 56, maxLevel = 255 },
                { spellId = 140, minLevel = 70, maxLevel = 255 }, { spellId = 494, minLevel = 91, maxLevel = 255 },
                { spellId = 12, minLevel = 25, maxLevel = 255 } },
        }) do
            assert(not xi.test.world:probeTrustRaiseCatalog(healer, rows).valid)
            assert(probe(healer).selected == 140)
        end
    end)
end)
