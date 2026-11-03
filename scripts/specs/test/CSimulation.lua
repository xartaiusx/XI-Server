---@meta

-- luacheck: ignore 241
---@class CSimulation
local CSimulation = {}

---@class SpawnPlayerParams
---@field zone? xi.zone
---@field job? xi.job
---@field level? integer
---@field race? xi.race
---@field name? string In-memory name override for name-bound policy tests; the database row keeps its generated unique name.
---@field new? boolean If true, spawn as a new player with zero playtime (for testing first login scenarios)

---Spawn a test player with specified configuration
---@param params? SpawnPlayerParams
---@nodiscard
---@return CClientEntityPair player The test player (combined client and entity)
function CSimulation:spawnPlayer(params)
end

---Return entities selected by the production party-target traversal.
---@param entity CBaseEntity
---@nodiscard
---@return CBaseEntity[]
function CSimulation:getPartyTargetTraversal(entity)
end

---@param ... xi.tick? Task boundary types to advance to. Defaults to xi.tick.ZONE if none provided.
---@return nil
function CSimulation:tick(...)
end

---@param entity CBaseEntity
---@return nil
function CSimulation:tickEntity(entity)
end

---@param regionId xi.region
---@param nationId xi.nation
---@return nil
function CSimulation:setRegionOwner(regionId, nationId)
end

---Set the random seed for the simulation's RNG
---@param seed integer
---@return nil
function CSimulation:setSeed(seed)
end

---Sets a new random seed
---@return nil
function CSimulation:seed()
end

---Read a server setting by its fully qualified key
---@param key string Setting key, e.g. 'map.EXP_RETAIN'
---@return boolean|number|string
function CSimulation:getSetting(key)
end

---Override a server setting for the duration of the test, restored automatically afterwards
---@param key string Setting key, e.g. 'map.EXP_RETAIN'
---@param value boolean|number|string
---@return nil
function CSimulation:setSetting(key, value)
end

---Advances the steady clock.
---@param seconds integer
---@return nil
function CSimulation:skipTime(seconds)
end

---Read an active effect's signed monotonic start in integer milliseconds; no state change.
---Returns nil for a missing/nonbattle actor, invalid effect ID or missing effect.
---Also returns nil if the native milliseconds cannot be represented exactly in Lua.
---@param entity CBaseEntity?
---@param effectId xi.effect
---@nodiscard
---@return integer?
function CSimulation:getStatusEffectStartTime(entity, effectId)
end

---@param hour integer
---@param minute integer
---@return nil
function CSimulation:setVanaTime(hour, minute)
end

---@param day xi.day
---@return nil
function CSimulation:setVanaDay(day)
end

---Skip to midnight (00:00) of the next Vana'diel day
---@return nil
function CSimulation:skipToNextVanaDay()
end

---Advance Vana'diel time forward by whole days (does not tick).
---@param days integer
---@return nil
function CSimulation:skipVanaDays(days)
end

---Read the native dynamic-target allocation count, including quarantined IDs.
---Test-only observation; never retires or allocates an ID.
---@param zoneId xi.zone
---@return integer
function CSimulation:getDynamicTargIDsCount(zoneId)
end

---Returns mobs in a spawn slot as a table
---@param zoneId xi.zone
---@param slotId integer
---@return CTestEntity[]
function CSimulation:getSpawnSlot(zoneId, slotId)
end

---Sets the percent chance a slotted mob wins its slot's roll
---@param entity CBaseEntity
---@param chance integer
---@return nil
function CSimulation:setSlotChance(entity, chance)
end

---Synchronous test-only native query using a private copy of a simulation-owned Trust's catalog.
---No shared/stored catalog, tick, cast, job, stat or resource mutation; pointer restored on exceptions.
---@class TrustRaiseProbeRow
---@field spellId integer One of12,13,140,494; unique, maximum four rows.
---@field minLevel integer Native minimum1..255, including explicit255.
---@field maxLevel integer Native maximum at least minLevel and at most255.
---@class TrustRaiseProbe
---@field valid boolean
---@field reason? string
---@field exceptionExercised boolean
---@field selected integer?
---@field repeated integer?
---@field compatibility table<integer, boolean>
---@field canUse table<integer, boolean>
---@field minimums table<integer, integer>
---@field originalMinimums table<integer, integer>
---@field storedCatalogUnchanged boolean
---@field storedVectorsUnchanged boolean
---@field probeVectorsUnchanged boolean
---@field probeRaiseCount integer
---@field resourcesUnchanged boolean
---@param entity CBaseEntity Current Trust attached to one of this simulation's clients.
---@param overrides? TrustRaiseProbeRow[] Bounded private native-list replacements, never shared SQL.
---@nodiscard
---@param exerciseException? boolean Test-only caught C++ unwind to verify RAII restoration.
---@return TrustRaiseProbe
function CSimulation:probeTrustRaiseCatalog(entity, overrides, exerciseException)
end
