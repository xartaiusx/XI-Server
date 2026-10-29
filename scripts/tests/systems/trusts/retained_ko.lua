-----------------------------------
-- Approved Trust recovery uses the same native entity and party slot.
-- Native/DB-isolated execution is required; source checks are insufficient.
-----------------------------------
describe('Approved Trust KO recovery', function()
    ---@type CClientEntityPair
    local owner

    local function valaineral()
        for _, member in ipairs(owner:getPartyWithTrusts()) do
            if member:isTrust() and member:getTrustID() == xi.magic.spell.VALAINERAL then
                return member
            end
        end

        return nil
    end

    local function requiredValaineral()
        local trust = valaineral()
        assert(trust, 'the expected Valaineral fixture must exist')

        return trust
    end

    local function knockOut(trust)
        trust:setHP(0)
        xi.test.world:tickEntity(trust)
        assert(trust:isDead(), 'native Trust death must have occurred')
    end

    local function packetUnsigned(packet, offset, count)
        local value = 0
        for byte = 0, count - 1 do
            local part = packet.data[offset + byte]
            assert(type(part) == 'number', 'native packet field must be present')
            value = value + part * 256 ^ byte
        end

        return value
    end

    local function assertRaiseVisual(packets, ident, targetIndex, cullIndex)
        local visualIndex
        local raiseIndex
        for index, packet in ipairs(packets) do
            if packet.type == 0x0E and packetUnsigned(packet, 4, 4) == ident then
                if math.floor(packet.data[0x0A] / 32) % 2 == 1 then
                    assert(index == cullIndex, 'only the earlier pending-offer view cull is allowed')
                end

                if packet.data[0x0A] == 0x0F then
                    assert(packetUnsigned(packet, 8, 2) == targetIndex, 'target index must remain unchanged')
                    assert(packet.data[0x1F] == xi.animation.NONE, 'PostTick must not coalesce Death back over the visual')
                    assert(packetUnsigned(packet, 0x30, 2) == 0, 'Val uses a standard model')
                    assert(packetUnsigned(packet, 0x32, 2) == 3014, 'Val fixed model must remain unchanged')
                    visualIndex = visualIndex or index
                end
            elseif packet.type == 0x028 and packetUnsigned(packet, 5, 4) == ident then
                raiseIndex = raiseIndex or index
            end
        end

        assert(cullIndex and visualIndex and raiseIndex and cullIndex < visualIndex and visualIndex < raiseIndex, 'delivered cull then complete living view must precede the unchanged Raise BATTLE2')
    end

    local function assertRecoveryAnimation(actions, ident, animation, message)
        local count = 0
        for _, action in ipairs(actions) do
            if
                action.m_uID == ident and
                action.cmd_no == xi.action.category.MAGIC_FINISH
            then
                for _, target in ipairs(action.target) do
                    for _, result in ipairs(target.result) do
                        if
                            target.m_uID == ident and
                            result.sub_kind == animation
                        then
                            count = count + 1
                        end
                    end
                end
            end
        end

        assert(count == 1, message)
    end

    local function assertArrivingRecoveryVisual(packets, ident)
        local visualIndex
        local raiseIndex
        for index, packet in ipairs(packets) do
            if
                packet.type == 0x0E and
                packetUnsigned(packet, 4, 4) == ident and
                packet.data[0x0A] == 0x0F
            then
                visualIndex = visualIndex or index
            elseif packet.type == 0x028 and packetUnsigned(packet, 5, 4) == ident then
                raiseIndex = raiseIndex or index
            end
        end

        assert(visualIndex and raiseIndex and visualIndex < raiseIndex, 'an arriving same-zone observer needs a full live view before Raise')
    end

    before_each(function()
        xi.test.world:setSetting('main.TRUST_JOB99_VALAINERAL', true)
        owner = xi.test.world:spawnPlayer({ name = 'TrustKOProbe', zone = xi.zone.WEST_RONFAURE, job = xi.job.PLD, level = 99 })
        assert(owner:spawnTrust(xi.magic.spell.VALAINERAL) ~= nil)
        xi.test.world:skipTime(1)
    end)

    it('retains a corpse identity and rejects duplicate summons and duplicate offers', function()
        local trust = requiredValaineral()
        local ident = trust:getID()
        knockOut(trust)

        assert(requiredValaineral():getID() == ident, 'KO must retain the exact entity')
        assert(#owner:getPartyWithTrusts() == 2, 'KO must retain the party slot')
        assert(owner:spawnTrust(xi.magic.spell.VALAINERAL) == nil, 'KO must still count as already summoned')
        assert(trust:canReceiveTrustRaise())
        assert(trust:offerTrustRaise(1, false, false))
        assert(not trust:canReceiveTrustRaise(), 'a pending offer must prevent another cast')
        assert(not trust:offerTrustRaise(3, false, false), 'a pending offer must not be replaced')
    end)

    it('uses the native Raise delay and weakness without a spawn or MP refill', function()
        local trust = requiredValaineral()
        local ident = trust:getID()
        local targetIndex = trust:getTargID()
        local distant = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE, job = xi.job.WHM, level = 99 })
        distant:setPos(owner:getXPos() + 1000, owner:getYPos(), owner:getZPos() + 1000)
        distant.actions:move(distant:getXPos(), distant:getYPos(), distant:getZPos())
        local arriving = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE, job = xi.job.WHM, level = 99 })
        arriving:setPos(owner:getXPos() + 900, owner:getYPos(), owner:getZPos() + 900)
        arriving.actions:move(arriving:getXPos(), arriving:getYPos(), arriving:getZPos())
        xi.test.world:skipTime(1)
        -- This drains packets without clearing native client spawn lists.
        owner.packets:clear()
        distant.packets:clear()
        trust:setMP(1)
        knockOut(trust)
        xi.test.world:skipTime(1)
        local sawDeath = false
        for _, packet in ipairs(owner.packets:getIncoming()) do
            if packet.type == 0x0E and packetUnsigned(packet, 4, 4) == ident then
                sawDeath = sawDeath or (packet.data[0x1E] == 0 and packet.data[0x1F] == xi.animation.DEATH)
            end
        end

        assert(sawDeath, 'a pending native dead update must precede the coalescing regression')
        local spawnHooks = 0
        trust:addListener('SPAWN', 'RECOVERY_VISUAL_NO_SPAWN', function()
            spawnHooks = spawnHooks + 1
        end)

        trust:setLocalVar('RecoveryVisualSentinel', 77)
        trust:addRecast(xi.recast.MAGIC, xi.magic.spell.CRUSADE, 300)
        assert(trust:offerTrustRaise(1, false, false))
        xi.test.world:skipTime(1)
        local cullPackets = owner.packets:getIncoming()
        local cullIndex
        local cullCount = 0
        for index, packet in ipairs(cullPackets) do
            if
                packet.type == 0x0E and
                packetUnsigned(packet, 4, 4) == ident and
                math.floor(packet.data[0x0A] / 32) % 2 == 1
            then
                cullIndex = index
                cullCount = cullCount + 1
            end
        end

        assert(cullIndex and cullCount == 1, 'native pending-offer cull must be delivered once before recovery')
        -- Preserve the copied cull, then drain it through the normal packet-pop seam.
        owner.packets:clear()
        assert(requiredValaineral():getID() == ident and #owner:getPartyWithTrusts() == 2, 'view removal must not remove the server corpse or slot')
        assert(not trust:offerTrustRaise(1, false, false), 'a rejected duplicate offer must not recull')
        arriving.packets:clear()
        arriving:setPos(owner:getXPos(), owner:getYPos(), owner:getZPos())
        arriving.actions:move(arriving:getXPos(), arriving:getYPos(), arriving:getZPos())
        xi.test.world:skipTime(1)
        for _, packet in ipairs(arriving.packets:getIncoming()) do
            assert(packet.type ~= 0x0E or packetUnsigned(packet, 4, 4) ~= ident, 'an arriving observer must not recreate a pending dead model')
        end

        -- Each skipTime also advances one 400ms zone tick: 1 + 1 + 8 is 11.2s.
        xi.test.world:skipTime(8)
        assert(trust:isDead() and trust:getHP() == 0, 'ordinary Raise must wait for the native twelve-second offer delay')
        for _, packet in ipairs(owner.packets:getIncoming()) do
            if packet.type == 0x0E and packetUnsigned(packet, 4, 4) == ident then
                assert(packet.data[0x0A] ~= 0x0F, 'ordinary pending updates must not re-add a model during the native wait')
            end
        end

        xi.test.world:skipTime(2)
        assert(trust:isDead() and trust:getHP() > 0, 'the native stand-up state must still block actions')
        assert(trust:getAnimation() == xi.animation.NONE, 'the visual must publish a living pose before Raise')
        assert(trust:getMP() == 1, 'the visual must not refill MP')
        assert(trust:getHP() == math.max(1, math.floor(trust:getMaxHP() / 10)), 'RaiseI returns native weakened HP')
        assert(trust:getTP() == 0, 'the visual must not grant TP')
        assert(trust:getLocalVar('RecoveryVisualSentinel') == 77, 'no per-life local reset')
        assert(spawnHooks == 0, 'no native onMobSpawn or SPAWN listener')
        assert(trust:hasRecast(xi.recast.MAGIC, xi.magic.spell.CRUSADE), 'existing cooldown must survive')
        assert(not owner.actions:useTrustAbility(trust, trust, xi.jobAbility.SENTINEL), 'visual alive must not end the recovery lock')

        for _, packet in ipairs(owner.packets:getIncoming()) do
            table.insert(cullPackets, packet)
        end

        assertRaiseVisual(cullPackets, ident, targetIndex, cullIndex)
        assertRecoveryAnimation(owner.packets:actionPackets(), ident, 511, 'exactly one native Raise511 must remain on the same entity')
        assertArrivingRecoveryVisual(arriving.packets:getIncoming(), ident)
        for _, packet in ipairs(distant.packets:getIncoming()) do
            assert(packet.type ~= 0x0E or packetUnsigned(packet, 4, 4) ~= ident, 'an observer outside the native spawn list must not receive the visual')
        end

        xi.test.world:skipTime(1)
        assert(trust:isDead(), 'the visible pose must retain the two-second native lock')
        xi.test.world:skipTime(2)
        assert(not trust:isDead())
        assert(requiredValaineral():getID() == ident and trust:getTargID() == targetIndex)
        assert(#owner:getPartyWithTrusts() == 2)
        assert(trust:hasStatusEffect(xi.effect.WEAKNESS))
        assert(trust:getMP() < trust:getMaxMP(), 'revival must not use the spawn refill path')
        assert(owner.actions:useTrustAbility(trust, trust, xi.jobAbility.SENTINEL), 'normal action admission resumes after native stand')
        xi.test.world:tickEntity(trust)
        assert(spawnHooks == 0 and trust:getLocalVar('RecoveryVisualSentinel') == 77)
    end)

    it('leaves unapproved Trust death and PC resurrection on their native visual paths', function()
        local naji = owner:spawnTrust(xi.magic.spell.NAJI)
        assert(naji, 'unapproved Trust control must exist')
        local legacyID = naji:getID()
        owner.packets:clear()
        naji:setHP(0)
        xi.test.world:tickEntity(naji)
        xi.test.world:skipTime(3)
        for _, member in ipairs(owner:getPartyWithTrusts()) do
            assert(member:getID() ~= legacyID, 'legacy Trust death must still remove its slot')
        end

        for _, packet in ipairs(owner.packets:getIncoming()) do
            if packet.type == 0x0E and packetUnsigned(packet, 4, 4) == legacyID then
                assert(packet.data[0x1E] == 0 or math.floor(packet.data[0x0A] / 32) % 2 == 1, 'legacy death must not publish a living recovery')
            end
        end

        owner:clearTrusts()
        xi.test.world:skipTime(6)
        local healer = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE, job = xi.job.WHM, level = 99 })
        -- A real position packet requests the native PC visibility list.
        healer.actions:move(owner:getXPos(), owner:getYPos(), owner:getZPos())
        healer:addSpell(xi.magic.spell.RAISE)
        xi.test.world:skipTime(1)
        local ownerID = owner:getID()
        local sawPlayerSpawn = false
        for _, packet in ipairs(healer.packets:getIncoming()) do
            if packet.type == 0x0D and packetUnsigned(packet, 4, 4) == ownerID then
                sawPlayerSpawn = true
            end
        end

        assert(sawPlayerSpawn, 'the PC control must establish native observer visibility before KO')
        owner:die({ expLoss = false })
        xi.test.world:tickEntity(owner)
        healer.packets:clear()
        healer.actions:useSpell(owner, xi.magic.spell.RAISE)
        xi.test.world:skipTime(20)
        assert(owner:hasRaiseTractorMenu(), 'normal PC Raise must still require manual acceptance')
        assert(owner:isDead())
        owner.actions:acceptRaise()
        xi.test.world:skipTime(3)
        assert(owner:isAlive(), 'normal PC resurrection must still complete')
        local sawPlayerUpdate = false
        for _, packet in ipairs(healer.packets:getIncoming()) do
            if packet.type == 0x0D and packetUnsigned(packet, 4, 4) == ownerID then
                sawPlayerUpdate = true
            end

            assert(packet.type ~= 0x0E or packetUnsigned(packet, 4, 4) ~= ownerID, 'a PC must never use the Trust visual publisher')
        end

        assert(sawPlayerUpdate, 'the PC control must retain its native0x0D observer update')
    end)

    it('finishes the native stand-up delay when the owner is KO during recovery', function()
        local trust = requiredValaineral()
        local ident = trust:getID()
        knockOut(trust)
        assert(trust:offerTrustRaise(1, false, false))
        xi.test.world:skipTime(13)
        assert(trust:isDead(), 'the accepted Raise must still be in its stand-up delay')
        owner:die({ expLoss = false })
        xi.test.world:tickEntity(owner)
        xi.test.world:skipTime(3)
        assert(not trust:isDead(), 'owner KO must preserve the native recovery state until standing completes')
        assert(trust:getAnimation() == xi.animation.NONE)
        assert(requiredValaineral():getID() == ident)
    end)

    it('consumes Reraise IV with short weakness without granting Reraise III', function()
        local trust = requiredValaineral()
        local ident = trust:getID()
        local targetIndex = trust:getTargID()
        trust:addStatusEffect(xi.effect.RERAISE, { power = 4, duration = 3600, origin = trust })
        owner.packets:clear()
        knockOut(trust)
        xi.test.world:skipTime(7)
        assert(trust:isDead() and trust:getHP() == 0, 'self Reraise must wait for the native eight-second delay')
        local cullPackets = owner.packets:getIncoming()
        local cullIndex
        local cullCount = 0
        for index, packet in ipairs(cullPackets) do
            if
                packet.type == 0x0E and
                packetUnsigned(packet, 4, 4) == ident and
                math.floor(packet.data[0x0A] / 32) % 2 == 1
            then
                cullIndex = index
                cullCount = cullCount + 1
            end
        end

        assert(cullIndex and cullCount == 1, 'automatic Reraise must retire the old view once during the existing eight-second wait')
        -- Snapshot inspection alone does not drain the native coalescing queue.
        owner.packets:clear()
        xi.test.world:skipTime(2)
        assert(trust:isDead() and trust:getHP() > 0 and trust:getAnimation() == xi.animation.NONE, 'Reraise visual setup must preserve the native stand lock')
        for _, packet in ipairs(owner.packets:getIncoming()) do
            table.insert(cullPackets, packet)
        end

        local visualIndex
        local raiseIndex
        for index, packet in ipairs(cullPackets) do
            if
                packet.type == 0x0E and
                packetUnsigned(packet, 4, 4) == ident and
                packet.data[0x0A] == 0x0F
            then
                assert(packetUnsigned(packet, 8, 2) == targetIndex, 'Reraise view must keep the exact native index')
                assert(packetUnsigned(packet, 0x32, 2) == 3014, 'Reraise must keep the Val model')
                visualIndex = visualIndex or index
            elseif packet.type == 0x028 and packetUnsigned(packet, 5, 4) == ident then
                raiseIndex = raiseIndex or index
            end
        end

        assert(visualIndex and raiseIndex and cullIndex < visualIndex and visualIndex < raiseIndex, 'Reraise must publish the full live view before its native animation')
        assertRecoveryAnimation(owner.packets:actionPackets(), ident, 847, 'exactly one native tier-four Reraise animation must be retained')
        xi.test.world:skipTime(3)

        assert(not trust:isDead())
        assert(requiredValaineral():getID() == ident)
        assert(trust:getStatusEffect(xi.effect.WEAKNESS):getDuration() == 180000)
        assert(not trust:hasStatusEffect(xi.effect.RERAISE), 'Reraise IV must not create another Reraise')
    end)

    it('keeps Arise recovery separate from the Reraise IV grant policy', function()
        local trust = requiredValaineral()
        knockOut(trust)
        assert(trust:offerTrustRaise(4, true, true))
        xi.test.world:skipTime(13)
        xi.test.world:skipTime(3)

        assert(not trust:isDead())
        assert(trust:getStatusEffect(xi.effect.WEAKNESS):getDuration() == 180000)
        assert(trust:getStatusEffect(xi.effect.RERAISE):getPower() == 3)
    end)

    it('retains approved support after owner KO while PC acceptance stays manual', function()
        local trust = requiredValaineral()
        local ident = trust:getID()
        assert(owner:spawnTrust(xi.magic.spell.SHANTOTTO) ~= nil)
        owner:die({ expLoss = false })
        xi.test.world:tickEntity(owner)
        assert(owner:isDead())
        assert(requiredValaineral():getID() == ident)
        assert(#owner:getPartyWithTrusts() == 2, 'unapproved Trusts must keep native owner-death cleanup')
        xi.test.world:tickEntity(trust)
        xi.test.world:skipTime(20)
        xi.test.world:skipTime(13)

        assert(owner:isDead(), 'a healer must never accept a PC Raise prompt')
        assert(owner:hasRaiseTractorMenu(), 'the retained healer should offer a legal native Raise')
        owner.actions:acceptRaise()
        xi.test.world:skipTime(3)
        xi.test.world:skipTime(3)
        assert(not owner:isDead())
        assert(requiredValaineral():getID() == ident)
    end)

    it('retains ordinary exact Twills support through the real player-death hook', function()
        -- The existing TrustKOProbe cases do not enter the Twills-only module
        -- lifecycle override. This synthetic actor uses the exact policy name;
        -- its DB identity remains the test engine's unique generated character.
        owner = xi.test.world:spawnPlayer({ name = 'Twills', zone = xi.zone.WEST_RONFAURE, job = xi.job.RDM, level = 99 })
        assert(owner:getName() == 'Twills')
        assert(not owner:isInEvent())
        assert(owner:getTwillsFullAllianceState() == xi.trustRetailParity.sessionState.IDLE)
        assert(owner:getLocalVar('MochiriiTrustEvidenceMode') == xi.trustRetailParity.evidenceMode.IDLE)
        assert(owner:spawnTrust(xi.magic.spell.VALAINERAL) ~= nil)
        xi.test.world:skipTime(1)

        local trust = requiredValaineral()
        local ident = trust:getID()
        assert(trust:isDevelopedTrust())
        assert(trust:getMainLvl() == 99 and trust:getSubLvl() == 99)
        assert(trust:getMP() >= 150, 'normal Valaineral must afford the native Raise MP cost')
        assert(owner:spawnTrust(xi.magic.spell.SHANTOTTO) ~= nil)
        local unapproved
        for _, member in ipairs(owner:getPartyWithTrusts()) do
            if member:isTrust() and member:getTrustID() == xi.magic.spell.SHANTOTTO then
                unapproved = member
            end
        end

        assert(unapproved and not unapproved:isDevelopedTrust())
        local unapprovedId = unapproved:getID()
        assert(#owner:getPartyWithTrusts() == 3)

        -- Native die/tick invokes CCharEntity::Die and the actual
        -- xi.player.onPlayerDeath override, including super. No hook is stubbed
        -- and no Trust cast, player Raise acceptance or recast is forced here.
        owner:die({ expLoss = false, mijin = false })
        xi.test.world:tickEntity(owner)
        assert(owner:isDead())
        assert(requiredValaineral():getID() == ident, 'the real Twills hook must preserve the exact approved native actor')
        assert(#owner:getPartyWithTrusts() == 2, 'native owner-KO cleanup must still remove the unapproved Trust')
        xi.test.world:tickEntity(trust)
        xi.test.world:skipTime(3)
        xi.test.world:skipTime(3)
        assert(not owner.actions:hasTrustEntity(unapprovedId), 'the unapproved native entity must retire without an orphan')
        assert(requiredValaineral():getID() == ident)
        xi.test.world:skipTime(20)
        xi.test.world:skipTime(13)

        assert(owner:isDead(), 'the retained healer must leave PC Raise acceptance manual')
        assert(owner:hasRaiseTractorMenu(), 'ordinary exact Twills must receive a natural native Raise offer')
        owner.actions:acceptRaise()
        xi.test.world:skipTime(3)
        xi.test.world:skipTime(3)
        assert(not owner:isDead())
        assert(requiredValaineral():getID() == ident)
        assert(owner:getTwillsFullAllianceState() == xi.trustRetailParity.sessionState.IDLE)
        assert(owner:getLocalVar('MochiriiTrustEvidenceMode') == xi.trustRetailParity.evidenceMode.IDLE)
    end)

    it('keeps stale Twills evidence cleanup after native owner-KO retention', function()
        owner = xi.test.world:spawnPlayer({ name = 'Twills', zone = xi.zone.WEST_RONFAURE, job = xi.job.RDM, level = 99 })
        assert(owner:getName() == 'Twills')
        assert(owner:getTwillsFullAllianceState() == xi.trustRetailParity.sessionState.IDLE)
        assert(owner:getLocalVar('MochiriiTrustEvidenceMode') == xi.trustRetailParity.evidenceMode.IDLE)
        assert(owner:spawnTrust(xi.magic.spell.VALAINERAL) ~= nil)
        xi.test.world:skipTime(1)
        local trust = requiredValaineral()
        local ident = trust:getID()
        assert(trust:isDevelopedTrust())

        -- A stale evidence schema must not be reclassified as clean ordinary
        -- gameplay. Native eligibility still retains this Valaineral first;
        -- the actual Lua death hook must then preserve its old cleanup.
        owner:setLocalVar('MochiriiTrustEvidenceSchema', 1)
        owner:die({ expLoss = false, mijin = false })
        xi.test.world:tickEntity(owner)
        assert(owner:isDead())
        assert(valaineral() == nil, 'stale evidence state must keep the previous fail-closed lifecycle cleanup')
        assert(#owner:getPartyWithTrusts() == 1)
        xi.test.world:skipTime(3)
        xi.test.world:skipTime(3)
        assert(not owner.actions:hasTrustEntity(ident), 'stale cleanup must retire the exact native actor')
        assert(owner:getLocalVar('MochiriiTrustEvidenceSchema') == 0)
    end)

    it('allows a friendly party PC to cast Raise on another owners retained Trust', function()
        owner = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE, job = xi.job.PLD, level = 99 })
        local healer = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE, job = xi.job.WHM, level = 99 })
        assert(owner.actions:formPartyForInvalidTrustState(healer))
        assert(owner:spawnTrust(xi.magic.spell.VALAINERAL) ~= nil)
        healer:setPos(owner:getXPos(), owner:getYPos(), owner:getZPos())
        healer:addSpell(xi.magic.spell.RAISE)
        local trust = requiredValaineral()
        local ident = trust:getID()
        knockOut(trust)
        healer.actions:useSpell(trust, xi.magic.spell.RAISE)
        xi.test.world:skipTime(20)
        assert(not trust:canReceiveTrustRaise(), 'a legal party PC cast must create a pending offer')
        xi.test.world:skipTime(13)
        xi.test.world:skipTime(3)
        assert(not trust:isDead())
        assert(requiredValaineral():getID() == ident)
    end)

    it('accepts friendly outside-party assistance and rejects a hostile outsider', function()
        local healer = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE, job = xi.job.WHM, level = 99 })
        healer:setPos(owner:getXPos(), owner:getYPos(), owner:getZPos())
        healer:addSpell(xi.magic.spell.RAISE)
        local trust = requiredValaineral()
        knockOut(trust)
        healer:setAllegiance(xi.allegiance.MOB)
        local mp = healer:getMP()
        healer.actions:useSpell(trust, xi.magic.spell.RAISE)
        xi.test.world:skipTime(20)
        assert(trust:canReceiveTrustRaise(), 'hostile assistance must not create an offer')
        assert(healer:getMP() == mp, 'invalid target admission must not spend MP')
        healer:setAllegiance(xi.allegiance.PLAYER)
        healer.actions:useSpell(trust, xi.magic.spell.RAISE)
        xi.test.world:skipTime(20)
        assert(not trust:canReceiveTrustRaise(), 'friendly outside-party Raise must pass the narrow corpse admission')
    end)

    it('rechecks friendly context when a pending native cast completes', function()
        local healer = xi.test.world:spawnPlayer({ zone = xi.zone.WEST_RONFAURE, job = xi.job.WHM, level = 99 })
        healer:setPos(owner:getXPos(), owner:getYPos(), owner:getZPos())
        healer:addSpell(xi.magic.spell.RAISE)
        local trust = requiredValaineral()
        knockOut(trust)
        healer.actions:useSpell(trust, xi.magic.spell.RAISE)
        xi.test.world:skipTime(1)
        healer:setAllegiance(xi.allegiance.MOB)
        xi.test.world:skipTime(20)
        assert(trust:isDead())
        assert(trust:canReceiveTrustRaise(), 'a cast that loses friendly context must not create an offer')
    end)

    it('cancels pending recovery on dismissal without reviving a replacement entity', function()
        for _, accepted in ipairs({ false, true }) do
            local trust = requiredValaineral()
            local ident = trust:getID()
            knockOut(trust)
            assert(trust:offerTrustRaise(1, false, false))
            if accepted then
                xi.test.world:skipTime(13)
                assert(trust:isDead() and trust:getHP() > 0, 'the second control must cancel an accepted but still locked recovery')
            end

            owner.packets:clear()
            owner:clearTrusts()
            xi.test.world:skipTime(20)
            assert(valaineral() == nil)
            assert(#owner:getPartyWithTrusts() == 1)
            assert(not owner.actions:hasTrustEntity(ident), 'dismissal must remove the exact native entity')
            for _, packet in ipairs(owner.packets:getIncoming()) do
                if packet.type == 0x0E and packetUnsigned(packet, 4, 4) == ident then
                    assert(packet.data[0x0A] ~= 0x0F, 'cancelled recovery must not republish a living model')
                end
            end

            if not accepted then
                assert(owner:spawnTrust(xi.magic.spell.VALAINERAL) ~= nil)
                xi.test.world:skipTime(1)
            end
        end
    end)

    it('clears pending recovery through native zoning and logout lifecycle callbacks', function()
        for _, logout in ipairs({ false, true }) do
            local trust = requiredValaineral()
            local ident = trust:getID()
            knockOut(trust)
            assert(trust:offerTrustRaise(1, false, false))
            owner:simulateZoneOutLifecycle(logout)
            xi.test.world:skipTime(20)
            assert(valaineral() == nil, 'a stale pending offer must not survive owner teardown')
            assert(#owner:getPartyWithTrusts() == 1)
            assert(not owner.actions:hasTrustEntity(ident), 'owner teardown must leave no native corpse orphan')
            if not logout then
                assert(owner:spawnTrust(xi.magic.spell.VALAINERAL) ~= nil)
            end
        end
    end)

    it('drops a pending offer when the owner homepoints in another zone', function()
        owner = xi.test.world:spawnPlayer({ zone = xi.zone.EAST_RONFAURE, job = xi.job.PLD, level = 99 })
        assert(not owner:isInEvent(), 'the homepoint fixture must start outside an unrelated zone event')
        owner:setHomePoint()
        owner:gotoZone(xi.zone.WEST_RONFAURE)
        assert(owner:spawnTrust(xi.magic.spell.VALAINERAL) ~= nil)
        local trust = requiredValaineral()
        local ident = trust:getID()
        knockOut(trust)
        assert(trust:offerTrustRaise(1, false, false))
        owner:die({ expLoss = false })
        xi.test.world:tickEntity(owner)
        owner:warp()
        for _ = 1, 8 do
            xi.test.world:skipTime(1)
        end

        assert(owner:getZoneID() == xi.zone.EAST_RONFAURE)
        assert(not owner:isInEvent(), 'the native homepoint return must not leave an unrelated zone event')
        xi.test.world:skipTime(20)
        assert(valaineral() == nil)
        assert(#owner:getPartyWithTrusts() == 1)
        assert(not owner.actions:hasTrustEntity(ident), 'homepoint must remove the old-zone native corpse')
    end)

    it('expires an unraised corpse after the bounded native sixty-minute lifetime', function()
        local ident = requiredValaineral():getID()
        knockOut(requiredValaineral())
        xi.test.world:skipTime(3601)
        assert(valaineral() == nil)
        assert(#owner:getPartyWithTrusts() == 1)
        xi.test.world:skipTime(3)
        assert(not owner.actions:hasTrustEntity(ident), 'expiration must remove the exact native entity')
    end)

    it('keeps unapproved native Trust death behavior unchanged', function()
        xi.test.world:setSetting('main.TRUST_JOB99_VALAINERAL', false)
        knockOut(requiredValaineral())
        xi.test.world:skipTime(3)
        assert(valaineral() == nil)
    end)
end)
