_addon.name = 'MochiriiScreenshotQA'
_addon.author = 'Mochirii'
_addon.version = '1.0.1'
_addon.commands = {'mochiriiscreenshotqa', 'mscreenshotqa'}

local resources = require('resources')

local trigger_path = 'C:/Users/xtyty/Documents/FFXI-Runtime/screenshots/native_screenshot_request.txt'
local command_path = 'C:/Users/xtyty/Documents/FFXI-Runtime/client-tools/windower_command_request.txt'
local equipment_path = 'C:/Users/xtyty/Documents/FFXI-Runtime/client-tools/windower_equipment_snapshot.tsv'
local last_check = 0
local last_screenshot_request = nil
local equipment_slots = {
    'main', 'sub', 'range', 'ammo', 'head', 'body', 'hands', 'legs',
    'feet', 'neck', 'waist', 'left_ear', 'right_ear', 'left_ring',
    'right_ring', 'back',
}

local function trim(value)
    return (value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function read_request(path)
    local handle = io.open(path, 'r')
    if not handle then
        return nil
    end

    local request = handle:read('*a') or ''
    handle:close()

    local removed = os.remove(path)
    if not removed then
        local clear_handle = io.open(path, 'w')
        if clear_handle then
            clear_handle:write('')
            clear_handle:close()
        end
    end

    return trim(request)
end

local function run_request(request)
    local format = request:match('format=(%a+)') or 'jpg'
    format = format:lower()

    if format ~= 'jpg' and format ~= 'png' and format ~= 'bmp' then
        format = 'jpg'
    end

    local hide = request:match('hide=true') ~= nil
    local command = 'screenshot ' .. format
    if hide then
        command = command .. ' hide'
    end

    windower.add_to_chat(207, 'MochiriiScreenshotQA: ' .. command)
    windower.send_command(command)
end

local function clean_cell(value)
    local cleaned = tostring(value or ''):gsub('[\r\n\t]', ' ')
    return cleaned
end

local function write_equipment_snapshot()
    local items = windower.ffxi.get_items()
    local equipment = items and items.equipment or {}
    local handle = io.open(equipment_path, 'w')
    if not handle then
        windower.add_to_chat(207, 'MochiriiScreenshotQA: could not write equipment snapshot')
        return
    end

    handle:write('slot\tbag\tslot_id\titem_id\tname\n')
    for _, slot in ipairs(equipment_slots) do
        local bag = equipment[slot .. '_bag'] or 0
        local inventory_slot = equipment[slot] or 0
        local item = nil
        if inventory_slot ~= 0 then
            item = windower.ffxi.get_items(bag, inventory_slot)
        end
        local item_id = item and item.id or 0
        local item_name = ''
        if item_id ~= 0 and resources.items[item_id] then
            item_name = resources.items[item_id].en or resources.items[item_id].english or ''
        end
        handle:write(table.concat({
            clean_cell(slot),
            clean_cell(bag),
            clean_cell(inventory_slot),
            clean_cell(item_id),
            clean_cell(item_name),
        }, '\t') .. '\n')
    end
    handle:write('# raw equipment\n')
    handle:write('key\tvalue\n')
    for key, value in pairs(equipment) do
        handle:write(clean_cell(key) .. '\t' .. clean_cell(value) .. '\n')
    end
    handle:close()
    windower.add_to_chat(207, 'MochiriiScreenshotQA: equipment snapshot written')
end

local function run_command_request(request)
    for line in request:gmatch('[^\r\n]+') do
        local command = trim(line)
        command = command:gsub('^//', '')
        if command ~= '' and not command:match('^#') then
            if command == 'qa equipment' or command == 'mochirii equipment' then
                write_equipment_snapshot()
            else
                windower.add_to_chat(207, 'MochiriiScreenshotQA: ' .. command)
                windower.send_command(command)
            end
        end
    end
end

windower.register_event('prerender', function()
    local now = os.clock()
    if now - last_check < 0.25 then
        return
    end

    last_check = now
    local request = read_request(trigger_path)
    if request and request ~= '' and request ~= last_screenshot_request then
        last_screenshot_request = request
        run_request(request)
    end

    request = read_request(command_path)
    if request and request ~= '' then
        run_command_request(request)
    end
end)

windower.register_event('addon command', function(command)
    command = (command or 'status'):lower()
    if command == 'status' or command == 's' then
        windower.add_to_chat(207, 'MochiriiScreenshotQA: watching ' .. trigger_path .. ' and ' .. command_path)
    end
end)
