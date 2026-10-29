-- Standalone LuaJIT fake tests. Only the explicitly supplied addon file is read.
-- No installed addon is loaded; no packet/native API, process, network, DB or credentials.
local addon_path = assert(arg[1], 'pass the candidate MochiriiTrustReturn.lua path')
local groups = 0

local function fixture()
    local f =
    {
        now = 1000,
        player = { id = 42, name = 'Twills' },
        info = { logged_in = true, zone = 100 },
        target = { id = 17188881, index = 1809, name = 'Prishe', hpp = 100, is_npc = true, spawn_type = 14 },
        party = { p0 = { name = 'Twills' }, a25 = { name = 'Prishe' } },
        events = {}, inputs = {}, messages = {}, shortcuts_inputs = {},
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
    function f:out(original, modified, blocked, ffxi)
        return self.events['outgoing text'](original, modified, blocked or false, ffxi ~= false)
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

-- Isolated model of Shortcuts 2.903's bare return-command path, not a
-- replacement addon. Its independent party-key classification and @input
-- rewrite follow shortcuts.lua:164-181/242-290, targets.lua:96-136 and
-- statics.lua:51/156-159 (installed source hashes are in the proposal).
-- In particular, a25 remains Ally; the return command allows Party and Self.
local function shortcuts_fixture(f)
    local lastsent = ''
    return function(_, modified)
        if modified:sub(1, 1) ~= '/' then return modified end
        if modified == lastsent then
            lastsent = ''
            return modified
        end

        local command = modified:match('^/(%a+)$')
        local commands = { retr = true, returntrust = true, refa = true, returnfaith = true }
        if not commands[command] then return modified end
        local target_type = 'Ally'
        if not f.target then
            target_type = ''
        elseif f.target.hpp == 0 then
            target_type = 'Corpse'
        elseif f.target.is_npc and f.target.spawn_type ~= 14 then
            target_type = 'Enemy'
        else
            for key, member in pairs(f.party) do
                if member.name == f.target.name then
                    if key:sub(1, 1) == 'p' then
                        target_type = key:sub(1, 2) == 'p0' and 'Self' or 'Party'
                    end
                    break
                end
            end
        end

        local target = (target_type == 'Party' or target_type == 'Corpse') and '<t>' or '<me>'
        lastsent = '/' .. command .. ' ' .. target
        f.shortcuts_inputs[#f.shortcuts_inputs + 1] = '@input ' .. lastsent
        return ''
    end
end

local function route_outgoing(handlers, text, blocked, ffxi)
    local modified = text
    for _, handler in ipairs(handlers) do
        local result = handler(text, modified, blocked or false, ffxi ~= false)
        if type(result) == 'string' then modified = result end
    end
    return modified
end

local function check(name, body)
    body()
    groups = groups + 1
    io.write('PASS ', name, '\n')
end

check('outgoing text uses third blocked and fourth FFXI arguments', function()
    for _, ffxi in ipairs({ true, false }) do
        local allowed = fixture()
        assert(allowed:out('/retr all', '/retr all', false, ffxi) == '')
        assert(#allowed.inputs == 1, 'FFXI-generated text is not upstream-blocked text')
        local blocked = fixture()
        assert(blocked:out('/retr all', '/retr all', true, ffxi) == nil)
        assert(#blocked.inputs == 0, 'the third argument must prevent dispatch')
    end
end)

check('Mochirii before Shortcuts captures bare high-slot target before rewrite', function()
    for _, alias in ipairs({ 'retr', 'returntrust', 'refa', 'returnfaith' }) do
        local text = '/' .. alias
        local f = fixture()
        assert(route_outgoing({ f.events['outgoing text'], shortcuts_fixture(f) }, text, false, true) == '')
        assert(#f.shortcuts_inputs == 0, 'Shortcuts must only receive the consumed empty text')
        assert(#f.inputs == 1 and f.inputs[1]:match(' one 17188881 1809$'))
        f:reply('ACCEPTED', 'OK', 1)
        assert(#f.inputs == 1, 'accepted ordinary release must not also emit native input')

        local reversed = fixture()
        assert(route_outgoing({ shortcuts_fixture(reversed), reversed.events['outgoing text'] }, text, false, true) == '')
        assert(#reversed.inputs == 0, 'negative control: the downstream addon only sees empty text')
        assert(reversed.shortcuts_inputs[1] == '@input ' .. text .. ' <me>')
        assert(reversed:out(text .. ' <me>', text .. ' <me>', false, true) == nil)
        assert(#reversed.inputs == 0, 'the rewritten Self target cannot select the high-slot Trust')

        local party = fixture()
        party.party = { p0 = { name = 'Twills' }, p1 = { name = 'Prishe' } }
        shortcuts_fixture(party)(text, text, false, true)
        assert(party.shortcuts_inputs[1] == '@input ' .. text .. ' <t>', 'the independent model must distinguish p1 from a25')
    end
end)

check('native bare one uses one explicit target passthrough through Shortcuts', function()
    for _, alias in ipairs({ 'retr', 'returntrust', 'refa', 'returnfaith', 'ReTr' }) do
        for _, slot in ipairs({ 'p1', 'a25' }) do
            local f = fixture()
            f.party = { p0 = { name = 'Twills' }, [slot] = { name = 'Prishe' } }
            local shortcuts = shortcuts_fixture(f)
            local text = '/' .. alias .. '  '
            local handlers = { f.events['outgoing text'], shortcuts }
            assert(route_outgoing(handlers, text, false, true) == '')
            assert(#f.inputs == 1 and f.inputs[1]:match(' one 17188881 1809$'))
            f:reply('NATIVE', 'RETAIL')
            local emitted = '/' .. alias .. ' <t>'
            assert(#f.inputs == 2 and f.inputs[2] == emitted)
            assert(route_outgoing(handlers, emitted, false, true) == emitted)
            assert(#f.inputs == 2 and #f.shortcuts_inputs == 0, 'no rewritten third input or second classification')
            f:reply('NATIVE', 'RETAIL')
            assert(#f.inputs == 2, 'a duplicate reply cannot emit another native command')
        end
    end
end)

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
        for _, text in ipairs({ '/retr', '/retr <t>' }) do
            local f = fixture()
            f:out(text, text)
            f:reply('NATIVE', 'RETAIL')
            local emitted = f.inputs[2]
            change(f)
            assert(f:out(emitted, emitted) == '')
            assert(#f.inputs == 2, 'cancelled native input cannot become a backend request')
        end
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
