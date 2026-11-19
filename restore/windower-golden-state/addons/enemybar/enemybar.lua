--[[
Copyright © 2015, Mike McKee
All rights reserved.
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of enemybar nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL Mike McKee BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--]]

_addon.name = 'enemybar'
_addon.author = 'mmckee'
_addon.version = '1.0.3-mochirii'
_addon.language = 'English'

local packets = require('packets')
local socket = require('socket')
local protocol = require('mochi_protocol')
local ui = require('targetBar')
local state = protocol.new()
local mordian_gaol = 131

local function integer_in(value, minimum, maximum)
    return type(value) == 'number' and value >= minimum and value <= maximum and value % 1 == 0
end

local function selected_monster()
    local info = windower.ffxi.get_info()
    if not info or not info.logged_in then return end

    local target = windower.ffxi.get_mob_by_target('t')
    if not target or not target.valid_target or not target.is_npc or target.spawn_type ~= 16 or
        target.in_party or target.in_alliance or target.charmed or
        not integer_in(target.hpp, 1, 100) or not integer_in(target.id, 1, 4294967295) or
        not integer_in(target.index, 1, 4095) then
        return
    end

    local player = windower.ffxi.get_player()
    -- The server does not dispatch private commands during ordinary jail speech.
    if not player or player.name ~= 'Twills' or player.id ~= 2 or
        info.zone == mordian_gaol or not integer_in(info.zone, 1, 65535) then
        return target
    end

    return target, { owner = player.id, zone = info.zone, id = target.id, index = target.index }
end

local function render_target_bar()
    local target, key = selected_monster()
    local request = state:request(key, socket.gettime())
    if target then
        ui.draw(target, state.snapshot)
    else
        ui.hide()
    end

    if request then
        local ok = pcall(packets.inject, 'outgoing', 0x0B5, {
            Mode = 0,
            GM = 0,
            Message = request,
        })
        if not ok then state.pending = nil end
    end
end

windower.register_event('incoming chunk', function(id, original, _, injected, blocked)
    if id ~= 0x017 or injected ~= false or blocked ~= false or type(original) ~= 'string' or
        #original < 24 or #original > 256 then
        return
    end

    local ok, packet = pcall(packets.parse, 'incoming', original)
    if not ok or not packet or packet.Mode ~= 6 or packet.GM ~= false or packet['Sender Name'] ~= 'MochiEnemybar' then
        return
    end

    local reply = protocol.parse(packet.Message)
    if reply then
        local _, key = selected_monster()
        state:receive(key, socket.gettime(), reply)
        -- This native private reply is data for the overlay, not a chat message.
        return true
    end
end)

local function reset()
    state:clear()
    ui.hide()
end

windower.register_event('prerender', render_target_bar)
windower.register_event('target change', reset)
windower.register_event('zone change', reset)
windower.register_event('logout', reset)
windower.register_event('unload', function()
    state:clear()
    ui.destroy()
end)
