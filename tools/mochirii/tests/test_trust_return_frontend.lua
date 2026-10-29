-- Standalone LuaJIT fake tests. Only the explicitly supplied addon file is read.
-- No installed addon, packet/native API, process, network, DB or credentials.
local addon_path = assert(arg[1], 'pass the candidate MochiriiTrustReturn.lua path')
local groups = 0

local function fixture()
    local f =
    {
        now = 1000,
        player = { id = 42, name = 'Twills' },
        info = { logged_in = true, zone = 100 },
        target = { id = 17188881, index = 1809 },
        events = {}, inputs = {}, messages = {},
    }
    local windower =
    {
        register_event = function(event, callback)
            assert(f.events[event] == nil, 'one fixed handler per event')
            f.events[event] = callback
        end,
        add_to_chat = function(mode, text)
            assert(mode == 207)
            f.messages[#f.messages + 1] = text
        end,
        chat =
        {
            input = function(text)
                f.inputs[#f.inputs + 1] = text
                if f.dispatch_error then
                    error('synthetic dispatch error')
                end
            end,
        },
        ffxi =
        {
            get_player = function() return f.player end,
            get_info = function() return f.info end,
            get_mob_by_target = function(which) assert(which == 't') return f.target end,
        },
    }
    local env =
    {
        _addon = {},
        windower = windower,
        os = { time = function() return f.now end },
        require = function(name)
            assert(name == 'packets', 'no runtime IO or QA dependency')
            return
            {
                parse = function(direction, bytes)
                    assert(direction == 'incoming' and bytes == string.rep('x', 24))
                    if f.parse_error then error('synthetic parser error') end
                    return f.packet
                end,
            }
        end,
        type = type, tonumber = tonumber, pcall = pcall,
        string = string,
    }
    local chunk = assert(loadfile(addon_path))
    setfenv(chunk, env)()
    function f:out(original, modified, blocked)
        return self.events['outgoing text'](original, modified, 1, blocked or false)
    end
    function f:reply(status, reason, count, mutate)
        local request = self.inputs[1]
        local nonce, owner, zone, op, id, index = request:match('^!trustreturn (%x+) (%d+) (%d+) (%a+) (%d+) (%d+)$')
        assert(nonce, 'a single canonical backend request is required')
        self.packet =
        {
            Mode = 6, GM = false, ['Sender Name'] = 'MochiTrustRet',
            Message = string.format('MTR1 %s %s %s %s %s %s %s %u %s', nonce, owner, zone, op, id, index, status, count or 0, reason),
        }
        if mutate then mutate(self.packet) end
        self.events['incoming chunk'](0x017, string.rep('x', 24), 'not parsed', false, false)
    end
    return f
end

local function check(name, body)
    body()
    groups = groups + 1
    io.write('PASS ', name, '\n')
end

check('four aliases use modified blank then one retransmission', function()
    for _, alias in ipairs({ 'retr', 'returntrust', 'refa', 'returnfaith' }) do
        for _, argument in ipairs({ '<t>', 'all ' }) do
            local f = fixture()
            -- Source-qualified Shortcuts sequence: blank rewrite, then its
            -- nonempty lastsent retransmission. Original is never a fallback.
            assert(f:out('/' .. alias, '', false) == nil)
            assert(#f.inputs == 0)
            local sent = '/' .. alias .. ' ' .. argument
            assert(f:out(sent, sent, false) == '')
            assert(#f.inputs == 1 and f.inputs[1]:sub(1, 13) == '!trustreturn ')
            f:reply('ACCEPTED', 'OK', argument == 'all ' and 17 or 1)
            assert(#f.inputs == 1, 'accepted ordinary release must not also send native return')
            local expected = argument == 'all ' and 'Returning 17 Trusts.' or 'Returning 1 Trust.'
            assert(f.messages[#f.messages] == 'Trust return: ' .. expected)
        end
    end
end)

check('explicit target syntax other characters blank and blocked stay native', function()
    local f = fixture()
    for _, text in ipairs({ '/retr Prishe', '/retr <a25>', '/retr <p1>', '/retr all extra', '/other all' }) do
        assert(f:out(text, text) == nil)
    end
    f.player.name = 'Other'
    assert(f:out('/retr all', '/retr all') == nil)
    assert(f:out('/retr all', '', false) == nil)
    assert(f:out('/retr all', '/retr all', true) == nil)
    assert(#f.inputs == 0)
end)

check('bare and explicit t capture actual full target identity', function()
    for _, text in ipairs({ '/retr', '/retr <t>' }) do
        local f = fixture()
        assert(f:out(text, text) == '')
        assert(f.inputs[1]:match(' one 17188881 1809$'))
    end
    local f = fixture()
    f.target = nil
    assert(f:out('/retr', '/retr') == '' and #f.inputs == 0)
end)

check('native classification authorizes exactly one nonempty passthrough', function()
    local f = fixture()
    f:out('/retr all', '/retr all ')
    f:reply('NATIVE', 'QA')
    assert(#f.inputs == 2 and f.inputs[2] == '/retr all ')
    -- If Shortcuts translates this API emission, its blank event must not
    -- consume the bypass. Only the matching nonempty retransmission may pass.
    assert(f:out('/retr all ', '') == nil)
    assert(f:out('/retr all ', '/retr all ') == '/retr all ')
    f:reply('NATIVE', 'QA')
    assert(#f.inputs == 2, 'a duplicate reply must not emit another native input')
end)

check('native authorization revalidates current target owner and zone', function()
    for _, change in ipairs({
        function(f) f.target.id = f.target.id + 1 end,
        function(f) f.target.index = f.target.index + 1 end,
        function(f) f.player.id = 43 end,
        function(f) f.info.zone = 101 end,
    }) do
        local f = fixture()
        f:out('/retr <t>', '/retr <t>')
        change(f)
        f:reply('NATIVE', 'RETAIL')
        assert(#f.inputs == 1)
    end
end)

check('passthrough consumption revalidates target owner zone and original deadline', function()
    for _, change in ipairs({
        function(f) f.target.id = f.target.id + 1 end,
        function(f) f.target.index = f.target.index + 1 end,
        function(f) f.player.id = 43 end,
        function(f) f.info.zone = 101 end,
        function(f) f.now = 1005 end,
    }) do
        local f = fixture()
        f:out('/retr <t>', '/retr <t>')
        f:reply('NATIVE', 'RETAIL')
        change(f)
        assert(f:out('/retr <t>', '/retr <t>') == '')
        assert(#f.inputs == 2, 'cancelled native input cannot become a backend request')
    end
end)

check('zone logout and expiry retain only bounded late-input cancellation', function()
    for _, change in ipairs({
        function(f) f.info.zone = 101 f.events['zone change']() end,
        function(f) f.info.logged_in = false f.events.logout() end,
        function(f) f.now = 1005 f.events.prerender() end,
    }) do
        local f = fixture()
        f:out('/retr all', '/retr all')
        f:reply('NATIVE', 'QA')
        change(f)
        assert(f:out('/retr all', '/retr all') == '')
        assert(#f.inputs == 2)
    end
end)

check('inactive cancellation cannot be overwritten by a new request or reply', function()
    local f = fixture()
    f:out('/retr <t>', '/retr <t>')
    f:reply('NATIVE', 'RETAIL')
    f.info.zone = 101
    f.events['zone change']()
    assert(f:out('/retr all', '/retr all') == '')
    assert(#f.inputs == 2, 'a different new request must not replace the cancellation marker')
    f:reply('NATIVE', 'RETAIL')
    assert(#f.inputs == 2, 'a late duplicate response must not replace the marker')
    assert(f:out('/retr <t>', '/retr <t>') == '')
    assert(#f.inputs == 2, 'the original late emission must be cancelled without a backend request')
    assert(f:out('/retr all', '/retr all') == '')
    assert(#f.inputs == 3, 'after exact cancellation is consumed a new human request is allowed')
end)

check('normal chat wrong origin and altered reply cannot authorize native', function()
    for _, change in ipairs({
        function(p) p.Mode = 0 end, function(p) p.GM = true end,
        function(p) p['Sender Name'] = 'Other' end,
        function(p) p.Message = p.Message .. ' extra' end,
        function(p) p.Message = p.Message:gsub('MTR1 ', 'MTR1\t') end,
        function(p) p.Message = p.Message:gsub('NATIVE 0 QA', 'NATIVE 1 QA') end,
        function(p) p.Message = p.Message:gsub(' 42 ', ' 042 ') end,
        function(p) p.Message = p.Message:gsub(' 100 all ', ' 101 all ') end,
        function(p) p.Message = p.Message:gsub('NATIVE 0 QA', 'NATIVE 0 UNKNOWN') end,
    }) do
        local f = fixture()
        f:out('/retr all', '/retr all')
        f:reply('NATIVE', 'QA', 0, change)
        assert(#f.inputs == 1)
    end
end)

check('injected blocked parser-error and unrelated original chunks stay inert', function()
    local f = fixture()
    f:out('/retr all', '/retr all')
    f:reply('DENIED', 'POLICY')
    local g = fixture()
    g:out('/retr all', '/retr all')
    g.packet = f.packet
    for _, flags in ipairs({ { true, false }, { false, true } }) do
        g.events['incoming chunk'](0x017, string.rep('x', 24), nil, flags[1], flags[2])
    end
    g.parse_error = true
    g.events['incoming chunk'](0x017, string.rep('x', 24), nil, false, false)
    assert(#g.inputs == 1)
end)

check('denied uncertain timeout and dispatch exception never fallback or retry', function()
    local denials =
    {
        { 'FORMAT', 'The return request was not understood.' },
        { 'POLICY', 'You do not have permission to return these Trusts.' },
        { 'CONTEXT', 'Return Trusts while idle with your weapon sheathed.' },
        { 'TARGET', 'Select one of your current Trusts.' },
        { 'BUSY', 'A Trust return is already pending. Check your roster before another command.' },
        { 'REPLAY', 'This return request was already handled. Check your roster before another command.' },
        { 'STALE', 'The return request expired. Check your roster before another command.' },
        { 'CLOCK', 'The command clock is unavailable. Check your clock before another command.' },
    }
    for _, denial in ipairs(denials) do
        local f = fixture()
        f:out('/retr all', '/retr all')
        f:reply('DENIED', denial[1])
        assert(#f.inputs == 1)
        assert(f.messages[#f.messages] == 'Trust return: ' .. denial[2])
    end
    local uncertain = fixture()
    uncertain:out('/retr all', '/retr all')
    uncertain:reply('UNCERTAIN', 'PARTIAL', 1)
    assert(#uncertain.inputs == 1)
    assert(uncertain.messages[#uncertain.messages] == 'Trust return: 1 Trust queued. Check your roster before another command.')
    local f = fixture()
    f:out('/retr all', '/retr all')
    f.now = 1005
    f.events.prerender()
    f:reply('NATIVE', 'RETAIL')
    assert(#f.inputs == 1)
    local g = fixture()
    g.dispatch_error = true
    g:out('/retr all', '/retr all')
    g:reply('NATIVE', 'RETAIL')
    assert(#g.inputs == 1)
end)

check('busy input does not queue and clock reversal fails closed', function()
    local f = fixture()
    f:out('/retr all', '/retr all')
    f:out('/retr all', '/retr all')
    assert(#f.inputs == 1)
    f.now = 999
    f:reply('NATIVE', 'RETAIL')
    assert(#f.inputs == 1)
end)

check('addon has no QA dependency injection or raw retention API', function()
    local f = fixture()
    local count = 0
    for _ in pairs(f.events) do count = count + 1 end
    assert(count == 6)
    f.events.unload()
    assert(#f.inputs == 0)
end)

io.write(string.format('%u fake groups passed\n', groups))
