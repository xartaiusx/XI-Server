local protocol = {}
protocol.__index = protocol

local function integer(text, limit, minimum)
    if not text or #text > 10 or (#text > 1 and text:sub(1, 1) == '0') then
        return nil
    end

    local value = tonumber(text)
    if value and value >= minimum and value <= limit then
        return value
    end
end

local function icons_from(text)
    if text == '-' then
        return {}
    end

    local icons = {}
    for field in text:gmatch('%d+') do
        local id = integer(field, 65535, 1)
        if not id or #icons == 8 then return nil end
        icons[#icons + 1] = id
    end
    if #icons > 0 and table.concat(icons, ',') == text then
        return icons
    end
end

function protocol.parse(line)
    if type(line) ~= 'string' or #line > 150 or line:find('[^ -~]') then
        return nil
    end

    local nonce, zone, id, index, payload = line:match('^MEB1 ([0-9a-f]+) (%d+) (%d+) (%d+) (.+)$')
    if not nonce or #nonce ~= 16 then return nil end

    local reply = {
        nonce = nonce,
        zone = integer(zone, 65535, 1),
        id = integer(id, 4294967295, 1),
        index = integer(index, 4095, 1),
    }
    if not (reply.zone and reply.id and reply.index) then return nil end
    if payload == 'unavailable' then
        reply.unavailable = true
        return reply
    end

    local hp, max_hp, mp, max_mp, tp, part, parts, icons =
        payload:match('^(%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (%d+) ([%d,%-]+)$')
    reply.hp = integer(hp, 2147483647, 0)
    reply.max_hp = integer(max_hp, 2147483647, 1)
    reply.mp = integer(mp, 2147483647, 0)
    reply.max_mp = integer(max_mp, 2147483647, 0)
    reply.tp = integer(tp, 3000, 0)
    reply.part = integer(part, 17, 1)
    reply.parts = integer(parts, 17, 1)
    reply.icons = icons and icons_from(icons)
    if not (reply.hp and reply.max_hp and reply.mp and reply.max_mp and reply.tp and
        reply.part and reply.parts and reply.icons) then
        return nil
    end
    if reply.hp > reply.max_hp or reply.mp > reply.max_mp or reply.part > reply.parts or
        (reply.part < reply.parts and #reply.icons ~= 8) or
        (#reply.icons == 0 and reply.parts ~= 1) then
        return nil
    end

    return reply
end

local function same_target(first, second)
    return first and second and first.zone == second.zone and
        first.id == second.id and first.index == second.index
end

local function same_snapshot(first, second)
    return first.hp == second.hp and first.max_hp == second.max_hp and
        first.mp == second.mp and first.max_mp == second.max_mp and
        first.tp == second.tp and first.parts == second.parts
end

function protocol.new()
    return setmetatable({ counter = 0, next_poll = 0 }, protocol)
end

function protocol:clear()
    self.target = nil
    self.pending = nil
    self.snapshot = nil
end

function protocol:update(target, now)
    if type(now) ~= 'number' or now ~= now or now < 1 or now >= 4294967296 or
        (self.last_clock and now < self.last_clock) then
        self:clear()
        return false
    end
    self.last_clock = now

    if not same_target(self.target, target) or
        (target and self.target.owner ~= target.owner) then
        self:clear()
        self.target = target
    end
    if self.pending and now >= self.pending.deadline then self.pending = nil end
    if self.snapshot and now >= self.snapshot.deadline then self.snapshot = nil end
    return target ~= nil
end

function protocol:request(target, now)
    if not self:update(target, now) or self.pending or now < self.next_poll then return nil end

    local seconds = math.floor(now)
    local microseconds = math.floor((now - seconds) * 1000000)
    self.counter = (self.counter + 1) % 4096
    local nonce = string.format('%08x%08x', seconds, microseconds * 4096 + self.counter)
    self.pending = { nonce = nonce, deadline = now + 3, chunks = {}, count = 0 }
    self.next_poll = now + 1
    return string.format('!mochienemybar %s %u %u %u', nonce, target.zone, target.id, target.index)
end

function protocol:receive(target, now, reply)
    if not self:update(target, now) then return end
    local pending = self.pending
    if not pending or pending.nonce ~= reply.nonce or not same_target(target, reply) then return end

    if reply.unavailable then
        self.pending = nil
        self.snapshot = nil
        return
    end
    if pending.chunks[reply.part] or (pending.header and not same_snapshot(pending.header, reply)) then
        self.pending = nil
        return
    end
    pending.header = pending.header or reply
    pending.chunks[reply.part] = reply.icons
    pending.count = pending.count + 1
    if pending.count ~= reply.parts then return end

    local icons = {}
    for part = 1, reply.parts do
        for _, icon in ipairs(pending.chunks[part]) do
            icons[#icons + 1] = icon
        end
    end
    self.pending = nil
    self.snapshot = {
        deadline = pending.deadline,
        hp = reply.hp,
        max_hp = reply.max_hp,
        mp = reply.mp,
        max_mp = reply.max_mp,
        tp = reply.tp,
        icons = icons,
    }
end

return protocol
