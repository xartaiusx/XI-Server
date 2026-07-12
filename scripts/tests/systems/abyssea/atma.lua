describe('Abyssea Atma', function()
    ---@type CClientEntityPair
    local player

    local function addAtma(atma, slot)
        slot = slot or 1
        player:addStatusEffect(xi.effect.ATMA, { power = atma, origin = player, subType = slot })

        local effect = player:getStatusEffect(xi.effect.ATMA, slot)
        assert(effect ~= nil)
        return effect
    end

    before_each(function()
        player = xi.test.world:spawnPlayer({ zone = xi.zone.ABYSSEA_KONSCHTAT, job = xi.job.WAR, level = 99 })
    end)

    it('applies and removes static synthetic Atma modifiers', function()
        local baseMpp = player:getMod(xi.mod.MPP)
        local baseDarkMab = player:getMod(xi.mod.DARK_MAB)
        local baseDarkMacc = player:getMod(xi.mod.DARK_MACC)

        addAtma(xi.ki.ATMA_OF_THE_BANISHER)
        assert(player:getMod(xi.mod.MPP) == baseMpp + 5)
        assert(player:getMod(xi.mod.DARK_MAB) == baseDarkMab + 10)
        assert(player:getMod(xi.mod.DARK_MACC) == baseDarkMacc + 20)

        player:delStatusEffect(xi.effect.ATMA, 1)
        assert(player:getMod(xi.mod.MPP) == baseMpp)
        assert(player:getMod(xi.mod.DARK_MAB) == baseDarkMab)
        assert(player:getMod(xi.mod.DARK_MACC) == baseDarkMacc)
    end)

    it('uses source-specific flat and percentage synthetic Atma values', function()
        local baseHp = player:getMod(xi.mod.HP)
        local baseMp = player:getMod(xi.mod.MP)
        local baseSaveTp = player:getMod(xi.mod.SAVETP)

        addAtma(xi.ki.ATMA_OF_THE_BUSHIN)
        assert(player:getMod(xi.mod.HP) == baseHp + 200)
        assert(player:getMod(xi.mod.MP) == baseMp + 200)
        assert(player:getMod(xi.mod.SAVETP) == baseSaveTp + 100)

        player:delStatusEffect(xi.effect.ATMA, 1)
        assert(player:getMod(xi.mod.HP) == baseHp)
        assert(player:getMod(xi.mod.MP) == baseMp)
        assert(player:getMod(xi.mod.SAVETP) == baseSaveTp)

        local baseMagicDamageTaken = player:getMod(xi.mod.DMGMAGIC)
        addAtma(xi.ki.ATMA_OF_THE_SELLSWORD)
        assert(player:getMod(xi.mod.DMGMAGIC) == baseMagicDamageTaken - 1400)
        player:delStatusEffect(xi.effect.ATMA, 1)
        assert(player:getMod(xi.mod.DMGMAGIC) == baseMagicDamageTaken)
    end)

    it('moves day-dependent modifiers to the current element', function()
        xi.test.world:setVanaDay(xi.day.FIRESDAY)
        local effect = addAtma(xi.ki.ATMA_OF_THE_HATEFUL_STREAM)

        assert(player:getMod(xi.mod.FIRE_MACC) == 40)
        assert(player:getMod(xi.mod.FIRE_MAB) == 10)
        assert(player:getMod(xi.mod.FIRE_FTP_BONUS) == 64)

        xi.test.world:setVanaDay(xi.day.ICEDAY)
        xi.atma.onEffectTick(player, effect)

        assert(player:getMod(xi.mod.FIRE_MACC) == 0)
        assert(player:getMod(xi.mod.FIRE_MAB) == 0)
        assert(player:getMod(xi.mod.FIRE_FTP_BONUS) == 0)
        assert(player:getMod(xi.mod.ICE_MACC) == 40)
        assert(player:getMod(xi.mod.ICE_MAB) == 10)
        assert(player:getMod(xi.mod.ICE_FTP_BONUS) == 64)

        player:delStatusEffect(xi.effect.ATMA, 1)
        assert(player:getMod(xi.mod.ICE_MACC) == 0)
        assert(player:getMod(xi.mod.ICE_MAB) == 0)
        assert(player:getMod(xi.mod.ICE_FTP_BONUS) == 0)
    end)

    it('uses the minor day magic-accuracy tier for Echoes', function()
        xi.test.world:setVanaDay(xi.day.FIRESDAY)
        local effect = addAtma(xi.ki.ATMA_OF_ECHOES)

        assert(player:getMod(xi.mod.FIRE_MACC) == 20)
        assert(player:getMod(xi.mod.FIRE_FTP_BONUS) == 128)

        xi.test.world:setVanaDay(xi.day.ICEDAY)
        xi.atma.onEffectTick(player, effect)

        assert(player:getMod(xi.mod.FIRE_MACC) == 0)
        assert(player:getMod(xi.mod.FIRE_FTP_BONUS) == 0)
        assert(player:getMod(xi.mod.ICE_MACC) == 20)
        assert(player:getMod(xi.mod.ICE_FTP_BONUS) == 128)
    end)

    it('updates and clears low-HP conditional modifiers', function()
        local effect = addAtma(xi.ki.ATMA_OF_THE_SHATTERING_STAR)
        assert(player:getMod(xi.mod.VIT) == 0)
        assert(player:getMod(xi.mod.AGI) == 0)
        assert(player:getMod(xi.mod.REGAIN) == 0)

        player:setHP(math.floor(player:getMaxHP() * 0.2))
        xi.atma.onEffectTick(player, effect)
        assert(player:getMod(xi.mod.VIT) == 100)
        assert(player:getMod(xi.mod.AGI) == 50)
        assert(player:getMod(xi.mod.REGAIN) == 40)

        player:setHP(player:getMaxHP())
        xi.atma.onEffectTick(player, effect)
        assert(player:getMod(xi.mod.VIT) == 0)
        assert(player:getMod(xi.mod.AGI) == 0)
        assert(player:getMod(xi.mod.REGAIN) == 0)
    end)

    it('applies two-handed weapon modifiers only while eligible', function()
        local effect = addAtma(xi.ki.ATMA_OF_THE_GRIFFONS_CLAW)
        assert(player:getMod(xi.mod.ALL_WSDMG_FIRST_HIT) == 0)

        player:addItem(xi.item.CLAYMORE)
        player:equipItem(xi.item.CLAYMORE, nil, xi.slot.MAIN)
        xi.atma.onEffectTick(player, effect)
        assert(player:getMod(xi.mod.ALL_WSDMG_FIRST_HIT) == 20)

        player:unequipItem(xi.slot.MAIN)
        xi.atma.onEffectTick(player, effect)
        assert(player:getMod(xi.mod.ALL_WSDMG_FIRST_HIT) == 0)
    end)

    it('applies Illuminator attack only with a two-handed weapon', function()
        local baseAttack = player:getMod(xi.mod.ATT)
        local baseDualWield = player:getMod(xi.mod.DUAL_WIELD)
        local effect = addAtma(xi.ki.ATMA_OF_THE_ILLUMINATOR)
        assert(player:getMod(xi.mod.DUAL_WIELD) == baseDualWield + 1)
        assert(player:getMod(xi.mod.ATT) == baseAttack)

        player:addItem(xi.item.CLAYMORE)
        player:equipItem(xi.item.CLAYMORE, nil, xi.slot.MAIN)
        xi.atma.onEffectTick(player, effect)
        assert(player:getMod(xi.mod.ATT) == baseAttack + 40)

        player:unequipItem(xi.slot.MAIN)
        xi.atma.onEffectTick(player, effect)
        assert(player:getMod(xi.mod.ATT) == baseAttack)
    end)

    it('switches HP-threshold recovery and defensive modifiers', function()
        local aceAngler = addAtma(xi.ki.ATMA_OF_THE_ACE_ANGLER, 1)
        local revelations = addAtma(xi.ki.ATMA_OF_REVELATIONS, 2)
        local ducalGuard = addAtma(xi.ki.ATMA_OF_THE_DUCAL_GUARD, 3)

        assert(player:getMod(xi.mod.REGEN) == 0)
        assert(player:getMod(xi.mod.REFRESH) == 0)
        assert(player:getMod(xi.mod.FASTCAST) == 0)
        assert(player:getMod(xi.mod.DMG) == 0)

        player:setHP(math.floor(player:getMaxHP() * 0.2))
        xi.atma.onEffectTick(player, aceAngler)
        xi.atma.onEffectTick(player, revelations)
        xi.atma.onEffectTick(player, ducalGuard)

        assert(player:getMod(xi.mod.REGEN) == 20)
        assert(player:getMod(xi.mod.REFRESH) == 30)
        assert(player:getMod(xi.mod.FASTCAST) == 15)
        assert(player:getMod(xi.mod.DMG) == -5000)
        assert(player:getMod(xi.mod.MOVE_SPEED_STACKABLE) == -20)

        player:setHP(player:getMaxHP())
        xi.atma.onEffectTick(player, aceAngler)
        xi.atma.onEffectTick(player, revelations)
        xi.atma.onEffectTick(player, ducalGuard)

        assert(player:getMod(xi.mod.REGEN) == 0)
        assert(player:getMod(xi.mod.REFRESH) == 0)
        assert(player:getMod(xi.mod.FASTCAST) == 0)
        assert(player:getMod(xi.mod.DMG) == 0)
        assert(player:getMod(xi.mod.MOVE_SPEED_STACKABLE) == 0)
    end)

    it('switches Cobra Commander between slow and haste thresholds', function()
        local baseDoubleAttack = player:getMod(xi.mod.DOUBLE_ATTACK)
        local baseHaste = player:getMod(xi.mod.HASTE_GEAR)
        local effect = addAtma(xi.ki.ATMA_OF_THE_COBRA_COMMANDER)
        assert(player:getMod(xi.mod.DOUBLE_ATTACK) == baseDoubleAttack + 10)
        assert(player:getMod(xi.mod.HASTE_GEAR) == baseHaste - 2000)

        player:setHP(math.floor(player:getMaxHP() * 0.4))
        xi.atma.onEffectTick(player, effect)
        assert(player:getMod(xi.mod.HASTE_GEAR) == baseHaste + 2000)

        player:setHP(player:getMaxHP())
        xi.atma.onEffectTick(player, effect)
        assert(player:getMod(xi.mod.HASTE_GEAR) == baseHaste - 2000)
    end)

    it('increases Royal Lineage cruor awards by twenty percent', function()
        assert(xi.abyssea.getCruorAward(player, 100) == 100)

        addAtma(xi.ki.ATMA_OF_THE_ROYAL_LINEAGE)
        assert(xi.abyssea.getCruorAward(player, 100) == 120)

        local before = player:getCurrency('cruor')
        assert(xi.abyssea.addCruor(player, 100) == 120)
        assert(player:getCurrency('cruor') == before + 120)
    end)

    it('applies Dragon Rider HP to an active wyvern', function()
        player:changeJob(xi.job.DRG)
        player:setLevel(99)
        player.actions:useAbility(player, xi.jobAbility.CALL_WYVERN)
        xi.test.world:tickEntity(player)

        local wyvern = player:getPet()
        assert(wyvern ~= nil)
        local baseHpp = wyvern:getMod(xi.mod.HPP)

        addAtma(xi.ki.ATMA_OF_THE_DRAGON_RIDER)
        assert(wyvern:getMod(xi.mod.HPP) == baseHpp + 50)

        player:delStatusEffect(xi.effect.ATMA, 1)
        assert(wyvern:getMod(xi.mod.HPP) == baseHpp)
    end)
end)
