local addon_path = assert(arg[1], 'usage: luajit test_enemybar.lua <addon directory>')
package.path = addon_path .. '/?.lua;' .. package.path
local protocol = require('mochi_protocol')
local assertions = 0
local function check(condition, message)
    assertions = assertions + 1
    assert(condition, message)
end

local nonce = '0123456789abcdef'
local prefix = 'MEB1 ' .. nonce .. ' 289 17960999 39 '
local key = { owner = 2, zone = 289, id = 17960999, index = 39 }
local function packet(request, payload)
    return protocol.parse('MEB1 ' .. assert(request:match('^!mochienemybar ([0-9a-f]+ %d+ %d+ %d+)$')) .. ' ' .. payload)
end

local empty = '110 200 0 0 2999 1 1 -'
local first = '110 200 34 90 2999 1 2 1,2,3,4,5,6,7,8'
local second = '110 200 34 90 2999 2 2 9,65535'
check(protocol.parse(prefix .. empty).hp == 110, 'valid no-icon sample')
check(protocol.parse(prefix .. 'unavailable').unavailable, 'valid negative response')
check(protocol.parse(prefix .. first).icons[8] == 8, 'canonical nonfinal part')
check(protocol.parse(prefix .. second).icons[2] == 65535, 'icon upper bound')

for _, text in ipairs({
    'MEB2 ' .. nonce .. ' 289 17960999 39 ' .. empty,
    'MEB1 0123456789ABCDEF 289 17960999 39 ' .. empty,
    'MEB1 0123456789abcde 289 17960999 39 ' .. empty,
    'MEB1 ' .. nonce .. ' 0289 17960999 39 ' .. empty,
    'MEB1 ' .. nonce .. ' 65536 17960999 39 ' .. empty,
    'MEB1 ' .. nonce .. ' 289 4294967296 39 ' .. empty,
    'MEB1 ' .. nonce .. ' 289 17960999 4096 ' .. empty,
    prefix .. empty .. ' ',
    prefix .. empty .. string.char(10),
    prefix .. string.rep('1', 151),
    prefix .. '001 200 0 0 2999 1 1 -',
    prefix .. '201 200 0 0 2999 1 1 -',
    prefix .. '1 0 0 0 1 1 1 -',
    prefix .. '1 200 11 10 1 1 1 -',
    prefix .. '1 200 0 0 3001 1 1 -',
    prefix .. '1 200 0 0 1 0 1 -',
    prefix .. '1 200 0 0 1 3 2 13',
    prefix .. '1 200 0 0 1 1 18 1,2,3,4,5,6,7,8',
    prefix .. '1 200 0 0 1 1 2 1,2',
    prefix .. '1 200 0 0 1 1 2 -',
    prefix .. '1 200 0 0 1 1 1 0',
    prefix .. '1 200 0 0 1 1 1 65536',
    prefix .. '1 200 0 0 1 1 1 0013',
    prefix .. '1 200 0 0 1 1 1 1,,2',
    prefix .. '1 200 0 0 1 1 1 1,2,',
    prefix .. '1 200 0 0 1 1 1 1,2,3,4,5,6,7,8,9',
}) do
    check(protocol.parse(text) == nil, 'rejected: ' .. text)
end

local state = protocol.new()
local now = 1795050000.125
local request = state:request(key, now)
check(request:match('^!mochienemybar [0-9a-f]+ 289 17960999 39$'), 'request shape')
check(state:request(key, now + 1.2) == nil, 'no replacement of pending request')
state:receive(key, now + 1.3, packet(request, second))
check(state.pending and not state.snapshot, 'out of order fragment stays private')
state:receive(key, now + 1.5, packet(request, first))
check(state.snapshot and table.concat(state.snapshot.icons, ',') == '1,2,3,4,5,6,7,8,9,65535', 'exact assembled order')
request = state:request(key, now + 1.5)
check(request and state.snapshot, 'fresh unrelated pending request should retain current snapshot')
state:receive(key, now + 1.6, packet(request, first))
state:receive(key, now + 1.7, packet(request, second:gsub('110 ', '111 ', 1)))
check(not state.pending and state.snapshot.hp == 110, 'inconsistent partial snapshot discarded')
check(state:request(key, now + 2.499) == nil, 'one-second request cadence')
state:update(key, now + 3.0)
check(not state.snapshot, '3s absolute TTL')
request = state:request(key, now + 3.1)
state:receive(key, now + 3.2, packet(request, first))
state:receive(key, now + 3.3, packet(request, first))
check(not state.pending and not state.snapshot, 'duplicate parts are invalid')
request = state:request(key, now + 4.1)
state:receive(key, now + 4.2, packet(request, empty))
check(state.snapshot and not state.pending, 'fresh complete one-part maxMP=0 response')
local next_key = { owner = 2, zone = 289, id = 17960999, index = 40 }
state:update(next_key, now + 4.25)
check(not state.snapshot, 'target index change invalidates same id')
state:receive(next_key, now + 4.3, packet(request, empty))
check(not state.snapshot, 'old target reply rejected')
request = state:request(next_key, now + 5.1)
state:receive(next_key, now + 5.2, packet(request, empty))
check(state.snapshot, 'new target snapshot received')
request = state:request(next_key, now + 6.1)
state:receive(next_key, now + 6.2, packet(request, 'unavailable'))
check(not state.snapshot and not state.pending, 'negative response drops exact data immediately')
request = state:request(next_key, now + 7.1)
state:update(next_key, now + 6.9)
check(not state.pending and not state.snapshot, 'backwards clock invalidates pending state')
check(state:request(next_key, now + 6.95) == nil, 'clock rollback blocks sends')
request = state:request(next_key, now + 8.2)
state:receive(next_key, now + 11.21, packet(request, empty))
check(not state.snapshot, 'late response beyond 3 seconds rejected')

-- Mock the Windows event surface and actual addon, parser, and renderer together.
local callbacks, requests, primitives = {}, {}, {}
local native_message
local chat_attempts = 0
local placeholder = 'HP --/--    MP --/--    TP --'
local player = { id = 2, name = 'Twills' }
local info = { logged_in = true, zone = 289 }
local monster = { id = 17960999, index = 39, valid_target = true, is_npc = true, spawn_type = 16, name = 'Eschan Il’aern', hpp = 75 }
local current_target = monster
local screen = { x_res = 2560, y_res = 1600, ui_x_res = 2560, ui_y_res = 1600 }
local primitive = {}
function primitive:show() self.visible = true end
function primitive:hide() self.visible = false end
function primitive:destroy() self.destroyed = true end
function primitive:path(path) self.path_value = path end
function primitive:text(value) self.text_value = value end
function primitive:width(value) self.draw_width = value end
function primitive:pos(x, y) self.x, self.y = x, y end

local function new_widget(kind)
    local object = setmetatable({ kind = kind }, { __index = primitive })
    primitives[#primitives + 1] = object
    return object
end

package.preload.images = function()
    return { new = function(options)
        local object = new_widget('image')
        object.path_value = options.texture.path
        object.draw_width = options.size.width
        return object
    end }
end
package.preload.texts = function()
    return { new = function(value)
        local object = new_widget('text')
        object.text_value = value
        return object
    end }
end
package.preload.socket = function() return { gettime = function() return now end } end
package.preload.packets = function()
    return {
        parse = function(direction, raw)
            assert(direction == 'incoming' and #raw >= 24)
            return native_message
        end,
        inject = function(direction, id, fields)
            assert(direction == 'outgoing' and id == 0x0B5 and fields.Mode == 0 and fields.GM == 0)
            local request_nonce, zone, entity, index = fields.Message:match('^!mochienemybar ([0-9a-f]+) (%d+) (%d+) (%d+)$')
            assert(request_nonce and #request_nonce == 16 and tonumber(zone) == info.zone and
                tonumber(entity) == current_target.id and tonumber(index) == current_target.index)
            requests[#requests + 1] = fields.Message
        end,
    }
end
windower = {
    addon_path = '/Windower/addons/enemybar/',
    ffxi = {
        get_info = function() return info end,
        get_player = function() return player end,
        get_mob_by_target = function(which) assert(which == 't'); return current_target end,
    },
    chat = { input = function() chat_attempts = chat_attempts + 1 end },
    file_exists = function(path) return not path:find('/65535.png', 1, true) end,
    get_windower_settings = function() return screen end,
    register_event = function(name, event) assert(not callbacks[name]); callbacks[name] = event end,
}
_addon = {}
assert(loadfile(addon_path .. '/enemybar.lua'))()

local function find_widget(value, field, visible)
    for _, object in ipairs(primitives) do
        if object[field] == value and object.visible == visible then return object end
    end
end

local function incoming(message, mode, sender, injected, blocked)
    native_message = { Message = message, Mode = mode, ['Sender Name'] = sender, GM = false }
    return callbacks['incoming chunk'](0x017, string.rep('x', 64), nil, injected, blocked)
end

callbacks.prerender()
check(#requests == 1, 'valid monster queues one reserved outgoing 0x0B5 request')
for _ = 1, 60 do callbacks.prerender() end
check(#requests == 1, 'repeated render frames do not poll again')
check(chat_attempts == 0, 'initial query did not enter chat')
check(find_widget(placeholder, 'text_value', true), 'all three stat labels display before any reply')
check(not find_widget('HP 75%', 'text_value', true), 'HP percent is not a text fallback')
local fill = find_widget('/Windower/addons/enemybar/fg_body.png', 'path_value', true)
check(fill and fill.draw_width == 448, 'the stock HP proportion controls only the fallback fill')
local raw_prefix = 'MEB1 ' .. assert(requests[1]:match('^!mochienemybar (.+)$')) .. ' '
local reply = raw_prefix .. '265 900 23 191 900 1 1 2,65535'
check(not incoming(reply, 3, 'MochiEnemybar', false, false), 'private response mode gate')
check(not incoming(reply, 6, 'OtherSender', false, false), 'exact sender gate')
check(not incoming(reply, 6, 'MochiEnemybar', true, false), 'injected packet gate')
check(not incoming(reply, 6, 'MochiEnemybar', false, true), 'blocked packet gate')
check(incoming(reply, 6, 'MochiEnemybar', false, false), 'authentic private payload hidden from chat')
callbacks.prerender()
check(find_widget('HP 265/900    MP 23/191    TP 900', 'text_value', true), 'exact HP, MP and TP display')
check(find_widget('/Windower/addons/enemybar/../XivParty/assets/buffIcons/2.png', 'path_value', true), 'use installed XivParty art')
check(find_widget('65535', 'text_value', true), 'missing art has numeric fallback')

now = now + 1.1
callbacks.prerender()
check(#requests == 2, 'one additional periodic request')
local header = 'MEB1 ' .. assert(requests[2]:match('^!mochienemybar (.+)$')) .. ' 2147483647 2147483647 2147483647 2147483647 3000 '
for part = 17, 1, -1 do
    local payload = header .. part .. ' 17 65535,1,2,3,4,5,6,7'
    check(#payload <= 150 and incoming(payload, 6, 'MochiEnemybar', false, false), 'well-bounded full status count')
end
callbacks.prerender()
local active_icons, rows = 0, {}
for _, object in ipairs(primitives) do
    if object.visible and object.path_value and object.path_value:find('buffIcons', 1, true) then
        check(object.x >= 981 and object.x <= 1579 and object.y < 1372, 'icon wraps inside the centered overlay')
        active_icons = active_icons + 1
        rows[object.y] = true
    end
end
check(active_icons == 119, 'all artwork slots displayed')
local count = 0
for _ in pairs(rows) do count = count + 1 end
check(count == 6, '136 statuses wrap into six rows')
local details = find_widget('HP 2147483647/2147483647    MP 2147483647/2147483647    TP 3000', 'text_value', true)
check(details and details.y == 1407, 'full exact details position clears 1428 hotbar row')
local bar = find_widget('/Windower/addons/enemybar/bg_body.png', 'path_value', true)
check(bar and bar.x == 981 and bar.draw_width == 598 and bar.y == 1392, 'centered official width')

callbacks['target change']()
for _, object in ipairs(primitives) do check(not object.visible, 'retarget clears overlay and status art immediately') end
current_target = { id = 17960999, index = 39, valid_target = true, is_npc = true, spawn_type = 14, name = 'Trust', hpp = 100 }
now = now + 2
callbacks.prerender()
check(#requests == 2, 'Trust target sends no request')
current_target = monster
player.name = 'OtherPlayer'
callbacks.prerender()
check(#requests == 2 and find_widget(placeholder, 'text_value', true), 'different character sees placeholders without polling')
player.name = 'Twills'
player.id = 3
callbacks.prerender()
check(#requests == 2 and find_widget(placeholder, 'text_value', true), 'matching name with another ID sees placeholders without polling')
local function check_quiet_transitions()
    player.id = 2
    info.zone = 131
    callbacks['zone change']()
    callbacks.prerender()
    check(#requests == 2 and find_widget(placeholder, 'text_value', true), 'Mordion Gaol never transmits reserved speech')
    info.zone = 289
    callbacks['zone change']()
    callbacks.prerender()
    check(#requests == 3, 'normal entitled zone resumes quiet polling')
    local expiry_header = 'MEB1 ' .. assert(requests[3]:match('^!mochienemybar (.+)$')) .. ' '
    check(incoming(expiry_header .. '750 1000 4 5 30 1 1 2', 6, 'MochiEnemybar', false, false),
        'matching fresh private response is consumed')
    now = now + 1.1
    callbacks.prerender()
    check(#requests == 4 and find_widget('HP 750/1000    MP 4/5    TP 30', 'text_value', true),
        'while a quiet refresh is pending, the previous fresh exact snapshot stays visible')
    now = now + 1.9
    callbacks.prerender()
    check(#requests == 4 and find_widget(placeholder, 'text_value', true), 'stale values expire to the same three labels')
    check(not find_widget('/Windower/addons/enemybar/../XivParty/assets/buffIcons/2.png', 'path_value', true),
        'expired private status icons are removed')
    local negative_header = 'MEB1 ' .. assert(requests[4]:match('^!mochienemybar (.+)$')) .. ' '
    check(incoming(negative_header .. 'unavailable', 6, 'MochiEnemybar', false, false),
        'authenticated unavailable response is consumed')
    callbacks.prerender()
    check(#requests == 5 and find_widget(placeholder, 'text_value', true), 'valid unavailable response keeps all labels')
    check(chat_attempts == 0, 'no request or response uses the chat input surface')
end
check_quiet_transitions()
info.logged_in = false
callbacks.logout()
callbacks.prerender()
for _, object in ipairs(primitives) do check(not object.visible, 'logout hides all primitives') end
callbacks.unload()
for _, object in ipairs(primitives) do check(object.destroyed, 'unload destroys owned primitives') end
print('EnemyBar client checks passed: ' .. assertions)
