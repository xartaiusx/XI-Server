--[[
        Copyright © 2020, SirEdeonX, Akirane
        All rights reserved.

        Redistribution and use in source and binary forms, with or without
        modification, are permitted provided that the following conditions are met:

            * Redistributions of source code must retain the above copyright
              notice, this list of conditions and the following disclaimer.
            * Redistributions in binary form must reproduce the above copyright
              notice, this list of conditions and the following disclaimer in the
              documentation and/or other materials provided with the distribution.
            * Neither the name of xivhotbar nor the
              names of its contributors may be used to endorse or promote products
              derived from this software without specific prior written permission.

        THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
        ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
        WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
        DISCLAIMED. IN NO EVENT SHALL SirEdeonX OR Akirane BE LIABLE FOR ANY
        DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
        (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
        LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
        ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
        (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
        SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

local action_manager = require('lib/action_manager')
local player = {}
local armed_action
local guarded = { Convert = true, Stymie = true, Spontaneity = true, Composure = true, Saboteur = true }

local party_target_keys = { p1 = 'f2', p2 = 'f3' }
local modifier_keys = {
    [0x1D] = true, [0x9D] = true, -- Control
    [0x2A] = true, [0x36] = true, -- Shift
    [0x38] = true, [0xB8] = true, -- Alt
    [0xDB] = true, [0xDC] = true, -- Windows
}
local held_modifiers = {}
local pending_party_target

local function party_member_id(slot)
    local party = windower.ffxi.get_party()
    local member = party and party[slot]
    local mob = member and member.mob
    return mob and mob.id and mob.id > 0 and mob.id or nil
end

local function send_pending_party_target()
    local request = pending_party_target
    if not request or next(held_modifiers) then return end

    -- Let the last physical modifier release reach the game before the pulse.
    coroutine.schedule(function()
        if pending_party_target ~= request or next(held_modifiers) then return end
        pending_party_target = nil
        local info = windower.ffxi.get_info()
        if info and info.logged_in and not info.chat_open and not info.menu_open and
            info.zone == request.zone and party_member_id(request.slot) == request.id then
            windower.send_command(('setkey %s down; wait 0.1; setkey %s up'):format(request.key, request.key))
        end
    end, 0.05)
end

local function queue_party_target(slot, zone)
    pending_party_target = nil
    local key = party_target_keys[slot]
    local id = key and party_member_id(slot)
    if not id then return end

    local request = { slot = slot, key = key, id = id, zone = zone }
    pending_party_target = request
    coroutine.schedule(function()
        if pending_party_target == request then pending_party_target = nil end
    end, 1)
    send_pending_party_target()
end

windower.register_event('keyboard', function(dik, pressed)
    if not modifier_keys[dik] then return end
    held_modifiers[dik] = pressed and true or nil
    if not pressed then send_pending_party_target() end
end)

windower.register_event('lose focus', 'zone change', 'logout', function()
    pending_party_target = nil
    held_modifiers = {}
    armed_action = nil
end)

--job_functions = {}

player.name = ''
player.main_job = ''
player.sub_job = ''
player.server = ''

player.vitals = {}
player.vitals.mp = 0
player.vitals.tp = 0
player.id = 0
player.current_weapon = 0

local debug = false

function player:get_current_weapontype()
    return current_weaponskill
end

function player:get_hotbar_info()
    local hotbar = action_manager.hotbar
    local active_environment = action_manager.hotbar_settings.active_environment
    local vitals = player.vitals
    return hotbar, active_environment, vitals
end

-- initialize player
function player:initialize(windower_player, server, theme_options)
    self.name      = windower_player.name
    self.main_job  = windower_player.main_job
    self.sub_job   = windower_player.sub_job
    self.server    = server
    self.buffs     = windower_player.buffs
    self.id        = windower_player.id
    self.vitals.mp = windower_player.vitals.mp
    self.vitals.tp = windower_player.vitals.tp
    action_manager:initialize(theme_options)
    action_manager:update_file_path(player.name, player.main_job)
end

function player:remove_action(remove_table)
    action_manager:remove_action(self, remove_table)
end

-- update player jobs
function player:update_job(main, sub)
    self.main_job = main
    self.sub_job = sub
    action_manager:update_file_path(player.name, player.main_job)
end

-- load hotbar for current player and job combination
function player:load_hotbar()
    action_manager:reset_hotbar()
    action_manager:load(self)
end

function player:swap_actions(swap_table)
    action_manager:swap_actions(player, swap_table)
end

function player:load_weaponskill_actions(skill_type)
    player.current_weapon = skill_type
end

function player:load_job_ability_actions(buff_id)
    action_manager:update_stance(buff_id)
    action_manager:load(self)
end

-- toggle bar environment
function player:toggle_environment()
    action_manager:toggle_environment()
end

-- set bar environment to battle
function player:set_battle_environment(in_battle)
    local environment = 'field'
    if in_battle then environment = 'battle' end

    action_manager.hotbar_settings.active_environment = environment
end

-- change active hotbar
function player:change_active_hotbar(new_hotbar)
    action_manager:change_active_hotbar(new_hotbar)
end

function player:insert_action(args)
    action_manager:insert_action(player.sub_job, args)
end

function player:determine_summoner_id(pet_name)
    for buff_id, buff_name in pairs(buff_table) do
        if buff_name == pet_name then
            return buff_id
        end
    end
    return 0
end

function player:get_active_hotbar()
    return action_manager.hotbar_settings.active_hotbar
end

-- execute action from given slot
function player:execute_action(slot)
    local action = action_manager:get_action(slot)
    local info = windower.ffxi.get_info()
    if not action or not info or not info.logged_in or info.chat_open or info.menu_open then
        armed_action = nil
        return
    end

    if action.type == 'ja' and guarded[action.action] then
        local now = os.clock()
        if not armed_action or armed_action.name ~= action.action or now > armed_action.deadline then
            armed_action = { name = action.action, deadline = now + 4 }
            windower.add_to_chat(122, '[XIVHotbar] '..action.action..': press the SAME action again within 4s to confirm.')
            return
        end
    end
    armed_action = nil

    if action.type == 'ct' then
        local command = '/' .. action.action

        if  action.target ~= nil and action.target ~= "" then
            command = command .. ' <' ..  action.target .. '>'
        end

        windower.chat.input(command)
        return
    elseif action.type == 'party_target' then
        queue_party_target(action.target, info.zone)
    elseif action.type == 'macro' then
        windower.chat.input('//'.. action.action)
    elseif action.type == 'ws' then
        windower.chat.input('//'.. action.action .. ' <' .. action.target .. '>')
    elseif action.type == 'gs' then
        coroutine.schedule(function()
            windower.send_command('gs ' .. action.action)
        end, 0.25)
    elseif action.type == 's' then
        windower.chat.input('//send ' .. action.action)
    elseif action.type == 'input' then
        windower.chat.input('//input ' .. action.action)
    else
        windower.chat.input('/' .. action.type .. ' "' .. action.action .. '" <' .. action.target .. '>')
    end
end

return player
