_addon.name = 'MochiriiTrustReturn'
_addon.author = 'xartaiusx'
_addon.version = '1.0.0'

-- Ordinary gameplay only. No QA, UUID bridge, debug mode, IO or packet injection.
local packets = require('packets')
local aliases = { retr = true, returntrust = true, refa = true, returnfaith = true }
local reasons =
{
    ACCEPTED = { OK = true },
    NATIVE = { RETAIL = true, QA = true, OTHER = true },
    DENIED = { FORMAT = true, POLICY = true, CONTEXT = true, TARGET = true, BUSY = true, REPLAY = true, STALE = true, CLOCK = true },
    UNCERTAIN = { PARTIAL = true },
}
local denied_text =
{
    FORMAT  = 'The return request was not understood.',
    POLICY  = 'You do not have permission to return these Trusts.',
    CONTEXT = 'Return Trusts while idle with your weapon sheathed.',
    TARGET  = 'Select one of your current Trusts.',
    BUSY    = 'A Trust return is already pending. Check your roster before another command.',
    REPLAY  = 'This return request was already handled. Check your roster before another command.',
    STALE   = 'The return request expired. Check your roster before another command.',
    CLOCK   = 'The command clock is unavailable. Check your clock before another command.',
}

local function result_text(reply)
    local trusts = reply.count == 1 and 'Trust' or 'Trusts'
    if reply.status == 'ACCEPTED' then
        return string.format('Returning %u %s.', reply.count, trusts)
    elseif reply.status == 'UNCERTAIN' then
        return string.format('%u %s queued. Check your roster before another command.', reply.count, trusts)
    end

    return denied_text[reply.reason]
end

local pending
local bypass
local counter = 0
local last_time = os.time()

local function message(text)
    windower.add_to_chat(207, 'Trust return: ' .. text)
end

local function invalidate()
    pending = nil
    if bypass then
        -- Keep just this nonauthorizing exact-text cancellation marker until
        -- its emitted input arrives. It can never become a new request.
        bypass.active = false
    end
end

local function clock()
    local now = os.time()
    if now < last_time then
        invalidate()
        return nil
    end

    last_time = now
    return now
end

local function context()
    local player = windower.ffxi.get_player()
    local info = windower.ffxi.get_info()
    if not player or not info or info.logged_in ~= true then
        return nil
    end

    return player.id, info.zone, player.name
end

local function matches(request, now)
    local owner, zone, name = context()
    if not now or now >= request.deadline or owner ~= request.owner or zone ~= request.zone or name ~= 'Twills' then
        return false
    end

    if request.op == 'one' then
        local target = windower.ffxi.get_mob_by_target('t')
        return target ~= nil and target.id == request.id and target.index == request.index
    end

    return true
end

local function number(value, maximum, zero)
    if not value or not value:match('^%d+$') or (#value > 1 and value:sub(1, 1) == '0') then
        return nil
    end

    local parsed = tonumber(value)
    if not parsed or parsed > maximum or parsed < (zero and 0 or 1) then
        return nil
    end

    return parsed
end

local function parse_reply(text)
    if type(text) ~= 'string' or #text > 126 or text:match('[^ -~]') then
        return nil
    end

    local nonce, owner, zone, op, id, index, status, count, reason = text:match(
        '^MTR1 ([0-9a-f]+) (%d+) (%d+) (%a+) (%d+) (%d+) (%u+) (%d+) (%u+)$')
    if not nonce or #nonce ~= 16 or not reasons[status] or not reasons[status][reason] then
        return nil
    end

    owner = number(owner, 4294967295, false)
    zone = number(zone, 65535, false)
    id = number(id, 4294967295, op == 'all')
    index = number(index, 4095, op == 'all')
    count = number(count, 17, true)
    if not owner or not zone or not id or not index or not count or (op ~= 'one' and op ~= 'all') then
        return nil
    end

    if (op == 'all' and (id ~= 0 or index ~= 0)) or ((status == 'NATIVE' or status == 'DENIED') and count ~= 0) then
        return nil
    end

    return { nonce = nonce, owner = owner, zone = zone, op = op, id = id, index = index, status = status, count = count, reason = reason }
end

windower.register_event('outgoing text', function(_, modified, _, blocked)
    if blocked or type(modified) ~= 'string' or modified == '' then
        return
    end

    -- This check precedes character/zone gating to consume a delayed emitted
    -- passthrough after authorizing state was invalidated.
    if bypass and modified == bypass.text then
        local saved = bypass
        bypass = nil
        if saved.active and matches(saved, clock()) then
            return modified
        end

        message('native passthrough cancelled: context changed or expired')
        return ''
    end

    local owner, zone, name = context()
    if name ~= 'Twills' then
        return
    end

    local alias, argument = modified:match('^/([%a]+)%s*(.-)%s*$')
    if not alias or not aliases[alias:lower()] then
        return
    end

    argument = argument:lower()
    if argument ~= '' and argument ~= 'all' and argument ~= '<t>' then
        return
    end

    if #modified > 64 or modified:match('[^ -~]') then
        message('invalid return command')
        return ''
    end

    local now = clock()
    if pending or bypass then
        message('busy; no command queued')
        return ''
    end

    if not now or now < 1 or now > 4294967295 or counter == 4294967295 then
        message('clock or nonce unavailable')
        return ''
    end

    local op = argument == 'all' and 'all' or 'one'
    local target = op == 'one' and windower.ffxi.get_mob_by_target('t') or nil
    if op == 'one' and (not target or not target.id or not target.index) then
        message('no current target')
        return ''
    end

    counter = counter + 1
    pending =
    {
        nonce = string.format('%08x%08x', now, counter),
        owner = owner, zone = zone, op = op,
        id = target and target.id or 0, index = target and target.index or 0,
        text = modified, deadline = now + 5,
    }
    local request = string.format('!trustreturn %s %u %u %s %u %u', pending.nonce, owner, zone, op, pending.id, pending.index)
    local ok = #request <= 126 and pcall(windower.chat.input, request)
    if not ok then
        invalidate()
        message('request dispatch failed; no fallback')
    end

    return ''
end)

windower.register_event('incoming chunk', function(id, original, _, injected, blocked)
    if id ~= 0x017 or not pending or injected ~= false or blocked ~= false or type(original) ~= 'string' or #original < 24 or #original > 256 then
        return
    end

    local ok, packet = pcall(packets.parse, 'incoming', original)
    if not ok or not packet or packet.Mode ~= 6 or packet.GM ~= false or packet['Sender Name'] ~= 'MochiTrustRet' then
        return
    end

    local reply = parse_reply(packet.Message)
    local request = pending
    if not reply or reply.nonce ~= request.nonce or reply.owner ~= request.owner or reply.zone ~= request.zone or
        reply.op ~= request.op or reply.id ~= request.id or reply.index ~= request.index then
        return
    end

    pending = nil
    if not matches(request, clock()) then
        message('reply cancelled: context changed or expired')
        return
    end

    if reply.status == 'NATIVE' then
        bypass = request
        bypass.active = true
        -- Existing native API, not a queued Windower @input command. The API
        -- does not promise withdrawal after emission or synchronous callbacks.
        if not pcall(windower.chat.input, request.text) then
            invalidate()
            message('native dispatch failed; no retry')
        end
    else
        message(result_text(reply))
    end
end)

windower.register_event('prerender', function()
    local now = clock()
    if (pending and not matches(pending, now)) or (bypass and bypass.active and not matches(bypass, now)) then
        invalidate()
        message('pending command cancelled: context changed or expired')
    end
end)

windower.register_event('zone change', invalidate)
windower.register_event('logout', invalidate)
windower.register_event('unload', function()
    pending = nil
    bypass = nil
end)
