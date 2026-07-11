_addon.name = 'MochiriiScreenshotQA'
_addon.author = 'Mochirii'
_addon.version = '1.1.0'
_addon.commands = { 'mochiriiscreenshotqa', 'mscreenshotqa' }

local json = require('json')
local resources = require('resources')

local trigger_path = 'C:/Users/xtyty/Documents/FFXI-Runtime/screenshots/native_screenshot_request.txt'
local client_tools_path = 'C:/Users/xtyty/Documents/FFXI-Runtime/client-tools'
local legacy_command_path = client_tools_path .. '/windower_command_request.txt'
local command_bridge_path = client_tools_path .. '/windower-command-bridge'
local command_request_path = command_bridge_path .. '/request.json'
local command_processing_path = command_bridge_path .. '/request.processing.json'
local command_ack_path = command_bridge_path .. '/acks'
local equipment_path = client_tools_path .. '/windower_equipment_snapshot.tsv'
local last_check = 0
local last_screenshot_request = nil
local processed_ids = {}
local processed_order = {}
local max_processed_ids = 256
local equipment_slots = {
    'main', 'sub', 'range', 'ammo', 'head', 'body', 'hands', 'legs',
    'feet', 'neck', 'waist', 'left_ear', 'right_ear', 'left_ring',
    'right_ring', 'back',
}

local function trim(value)
    return (value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function read_text(path)
    local handle = io.open(path, 'r')
    if not handle then
        return nil
    end

    local content = handle:read('*a') or ''
    handle:close()
    return content
end

local function file_exists(path)
    local handle = io.open(path, 'r')
    if not handle then
        return false
    end

    handle:close()
    return true
end

local function read_request(path)
    local request = read_text(path)
    if request == nil then
        return nil
    end

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

local function run_screenshot_request(request)
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
    return tostring(value or ''):gsub('[\r\n\t]', ' ')
end

local function write_equipment_snapshot()
    local items = windower.ffxi.get_items()
    local equipment = items and items.equipment or {}
    local handle = io.open(equipment_path, 'w')
    if not handle then
        error('could not write equipment snapshot')
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

local function is_valid_uuid(value)
    return
        type(value) == 'string' and
        #value == 36 and
        value:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$') ~= nil
end

local function remember_processed(request_id)
    if processed_ids[request_id] then
        return
    end

    processed_ids[request_id] = true
    table.insert(processed_order, request_id)
    if #processed_order > max_processed_ids then
        local oldest = table.remove(processed_order, 1)
        processed_ids[oldest] = nil
    end
end

local function json_escape(value)
    return tostring(value or '')
        :gsub('\\', '\\\\')
        :gsub('"', '\\"')
        :gsub('\r', '\\r')
        :gsub('\n', '\\n')
        :gsub('\t', '\\t')
end

local function get_ack_file(request_id)
    return command_ack_path .. '/' .. request_id .. '.json'
end

local function write_ack(request_id, status, detail)
    if not is_valid_uuid(request_id) then
        return false
    end

    local ack_file = get_ack_file(request_id)
    if file_exists(ack_file) then
        return true
    end

    local temp_file = ack_file .. '.tmp'
    local handle = io.open(temp_file, 'w')
    if not handle then
        return false
    end

    handle:write(string.format(
        '{"schema_version":1,"id":"%s","status":"%s","detail":"%s","processed_unix":%i}\n',
        json_escape(request_id),
        json_escape(status),
        json_escape(detail),
        os.time()
    ))
    handle:close()

    if not os.rename(temp_file, ack_file) then
        os.remove(temp_file)
        return file_exists(ack_file)
    end

    return true
end

local function command_is_mutating(command)
    local game_command = trim(command:match('^input%s+(.+)$') or command):lower()
    if game_command:sub(1, 1) ~= '!' then
        return false
    end

    local tokens = {}
    for token in game_command:gmatch('%S+') do
        table.insert(tokens, token)
    end

    if tokens[1] == '!twillsaudit' then
        return false
    end

    if
        tokens[1] == '!trustparty' and
        (tokens[2] == 'audit' or tokens[2] == 'status')
    then
        return false
    end

    if
        tokens[1] == '!craftqa' and
        tokens[2] == 'cooking' and
        (tokens[3] == 'report' or tokens[3] == 'status')
    then
        return false
    end

    return true
end

local function execute_command(command)
    command = trim(command):gsub('^//', '')
    if command == '' then
        error('empty command')
    end

    if command == 'qa equipment' or command == 'mochirii equipment' then
        write_equipment_snapshot()
        return 'equipment_snapshot_written'
    end

    windower.add_to_chat(207, 'MochiriiScreenshotQA: ' .. command)
    if command:match('^input%s+') then
        local game_command = trim((command:gsub('^input%s+', '', 1)))
        if game_command == '' then
            error('empty input command')
        end
        windower.chat.input('//input ' .. game_command)
    elseif command:match('^/') or command:match('^!') then
        windower.chat.input(command)
    else
        windower.send_command(command)
    end

    return 'dispatched'
end

local function reject_request(request_id, detail)
    if is_valid_uuid(request_id) then
        remember_processed(request_id)
        write_ack(request_id, 'failure', detail)
    end
    windower.add_to_chat(167, 'MochiriiScreenshotQA: command rejected: ' .. detail)
end

local function recover_unacknowledged_processing()
    local content = read_text(command_processing_path)
    if content == nil then
        return
    end

    local request = json.parse(content)
    local request_id = type(request) == 'table' and request.id or content:match('"id"%s*:%s*"([^"]+)"')
    if is_valid_uuid(request_id) and not file_exists(get_ack_file(request_id)) then
        reject_request(request_id, 'recovered_unacknowledged_request')
    end
    os.remove(command_processing_path)
end

local function process_command_request()
    recover_unacknowledged_processing()

    if not os.rename(command_request_path, command_processing_path) then
        return
    end

    local content = read_text(command_processing_path)
    if content == nil then
        os.remove(command_processing_path)
        return
    end

    local request, parse_error = json.parse(content)
    local request_id = type(request) == 'table' and request.id or content:match('"id"%s*:%s*"([^"]+)"')
    if type(request) ~= 'table' then
        reject_request(request_id, 'malformed_json:' .. trim(parse_error or 'unknown'))
        os.remove(command_processing_path)
        return
    end

    if not is_valid_uuid(request_id) then
        windower.add_to_chat(167, 'MochiriiScreenshotQA: command rejected: invalid request id')
        os.remove(command_processing_path)
        return
    end

    if processed_ids[request_id] or file_exists(get_ack_file(request_id)) then
        reject_request(request_id, 'duplicate_request')
        os.remove(command_processing_path)
        return
    end

    local now = os.time()
    local created_unix = tonumber(request.created_unix) or 0
    local expires_unix = tonumber(request.expires_unix) or 0
    local command = type(request.command) == 'string' and request.command or ''
    local calculated_mutating = command_is_mutating(command)
    local validation_error = nil

    if tonumber(request.schema_version) ~= 1 then
        validation_error = 'unsupported_schema'
    elseif created_unix <= 0 or created_unix > now + 60 then
        validation_error = 'invalid_creation_time'
    elseif expires_unix <= now then
        validation_error = 'expired_request'
    elseif expires_unix <= created_unix or expires_unix - created_unix > 300 then
        validation_error = 'invalid_expiry'
    elseif command == '' or #command > 1024 or command:match('[\r\n]') then
        validation_error = 'invalid_command'
    elseif request.mutating ~= calculated_mutating then
        validation_error = 'mutation_metadata_mismatch'
    elseif calculated_mutating and request.allow_mutation ~= true then
        validation_error = 'mutation_not_allowed'
    end

    if validation_error ~= nil then
        reject_request(request_id, validation_error)
        os.remove(command_processing_path)
        return
    end

    remember_processed(request_id)
    local ok, detail = pcall(execute_command, command)
    local status = ok and 'success' or 'failure'
    local ack_written = write_ack(request_id, status, ok and detail or ('dispatch_error:' .. trim(detail)))
    if ack_written then
        os.remove(command_processing_path)
    else
        windower.add_to_chat(167, 'MochiriiScreenshotQA: acknowledgement write failed for ' .. request_id)
    end
end

os.remove(legacy_command_path)
recover_unacknowledged_processing()

windower.register_event('prerender', function()
    local now = os.clock()
    if now - last_check < 0.25 then
        return
    end

    last_check = now
    local request = read_request(trigger_path)
    if request and request ~= '' and request ~= last_screenshot_request then
        last_screenshot_request = request
        run_screenshot_request(request)
    end

    process_command_request()
end)

windower.register_event('addon command', function(command)
    command = (command or 'status'):lower()
    if command == 'status' or command == 's' then
        windower.add_to_chat(207, 'MochiriiScreenshotQA: command bridge v1 watching ' .. command_request_path)
    end
end)
