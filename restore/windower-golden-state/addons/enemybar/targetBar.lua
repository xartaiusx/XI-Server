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

local images = require('images')
local texts = require('texts')

local targetBar = {}
local source = windower.addon_path
local icon_directory = source .. '../XivParty/assets/buffIcons/'
local maximum_width = 598
local bar_height = 12
local icon_size = 16
local icon_step = 24
local icon_row_height = 18

local function image(filename, red, green, blue, width, height)
    return images.new({
        size = { width = width, height = height },
        color = { red = red, green = green, blue = blue },
        texture = { path = source .. filename, fit = true },
        draggable = false,
    })
end

local function text(size)
    return texts.new('', {
        text = { size = size, font = 'Arial', stroke = { width = 2 } },
        bg = { visible = false },
        flags = { bold = true, draggable = false },
    })
end

local background = image('bg_body.png', 150, 0, 0, maximum_width, bar_height)
local left_cap = image('bg_cap.png', 150, 0, 0, 1, bar_height)
local right_cap = image('bg_cap.png', 150, 0, 0, 1, bar_height)
local foreground = image('fg_body.png', 255, 51, 0, maximum_width, bar_height)
local name_text = text(12)
local detail_text = text(11)
local base_primitives = { background, left_cap, right_cap, foreground, name_text, detail_text }
local icon_slots = {}
local path_cache, cached_count = {}, 0
local previous_snapshot, previous_screen_width, previous_screen_height
local previous_fill, previous_name, previous_detail
local showing = false

local function icon_slot(index)
    if not icon_slots[index] then
        icon_slots[index] = { artwork = image('', 255, 255, 255, icon_size, icon_size), fallback = text(7) }
    end
    return icon_slots[index]
end

local function icon_path(id)
    local path = path_cache[id]
    if path == nil then
        local candidate = icon_directory .. id .. '.png'
        path = windower.file_exists(candidate) and candidate or false
        if cached_count == 256 then
            path_cache, cached_count = {}, 0
        end
        path_cache[id] = path
        cached_count = cached_count + 1
    end
    return path
end

local function draw_icons(icons, left, top, bar_width)
    local columns = math.max(1, math.floor(bar_width / icon_step))
    local rows = math.ceil(#icons / columns)
    for index, id in ipairs(icons) do
        local slot = icon_slot(index)
        local row = math.floor((index - 1) / columns)
        local column = (index - 1) % columns
        local row_icons = math.min(columns, #icons - row * columns)
        local x = left + math.floor((bar_width - row_icons * icon_step) / 2) + column * icon_step
        local y = top - 22 - (rows - row) * icon_row_height
        local path = icon_path(id)
        if path then
            slot.fallback:hide()
            slot.artwork:path(path)
            slot.artwork:pos(x + 4, y)
            slot.artwork:show()
        else
            slot.artwork:hide()
            slot.fallback:text(tostring(id))
            slot.fallback:pos(x, y + 2)
            slot.fallback:show()
        end
    end

    for index = #icons + 1, #icon_slots do
        icon_slots[index].artwork:hide()
        icon_slots[index].fallback:hide()
    end
end

local no_icons = {}

function targetBar.draw(target, snapshot)
    local screen = windower.get_windower_settings()
    local width = screen and (screen.ui_x_res or screen.x_res)
    local height = screen and (screen.ui_y_res or screen.y_res)
    if not width or width < 360 or not height or height < 480 then
        targetBar.hide()
        return
    end

    local bar_width = math.min(width - 64, maximum_width)
    local left = math.floor((width - bar_width) / 2)
    local top = height - 208
    local resized = width ~= previous_screen_width or height ~= previous_screen_height
    if resized then
        previous_screen_width, previous_screen_height = width, height
        background:pos(left, top)
        background:width(bar_width)
        left_cap:pos(left - 1, top)
        right_cap:pos(left + bar_width, top)
        foreground:pos(left, top)
        name_text:pos(left, top - 20)
        detail_text:pos(left + 4, top + 15)
    end

    local hp_ratio = snapshot and snapshot.hp / snapshot.max_hp or target.hpp / 100
    local fill_width = math.floor(bar_width * hp_ratio)
    if resized or fill_width ~= previous_fill then
        foreground:width(math.max(fill_width, 1))
        previous_fill = fill_width
    end

    local name = type(target.name) == 'string' and target.name:gsub('[%c\\]', ''):sub(1, 48) or 'Enemy'
    if name ~= previous_name then
        name_text:text(name)
        previous_name = name
    end

    local detail = snapshot and string.format('HP %u/%u    MP %u/%u    TP %u',
        snapshot.hp, snapshot.max_hp, snapshot.mp, snapshot.max_mp, snapshot.tp) or
        string.format('HP %u%%', target.hpp)
    if detail ~= previous_detail then
        detail_text:text(detail)
        previous_detail = detail
    end

    if not showing then
        for _, primitive in ipairs(base_primitives) do primitive:show() end
        showing = true
    end
    if fill_width == 0 then foreground:hide() else foreground:show() end

    if snapshot ~= previous_snapshot or resized then
        draw_icons(snapshot and snapshot.icons or no_icons, left, top, bar_width)
        previous_snapshot = snapshot
    end
end

function targetBar.hide()
    if not showing then return end
    for _, primitive in ipairs(base_primitives) do primitive:hide() end
    for _, entry in ipairs(icon_slots) do
        entry.artwork:hide()
        entry.fallback:hide()
    end
    previous_snapshot = nil
    showing = false
end

function targetBar.destroy()
    for _, primitive in ipairs(base_primitives) do primitive:destroy() end
    for _, entry in ipairs(icon_slots) do
        entry.artwork:destroy()
        entry.fallback:destroy()
    end
end

return targetBar
