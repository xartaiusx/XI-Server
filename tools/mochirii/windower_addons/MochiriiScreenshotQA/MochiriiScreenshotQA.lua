_addon.name = 'MochiriiScreenshotQA'
_addon.author = 'Mochirii'
_addon.version = '1.0.0'
_addon.commands = {'mochiriiscreenshotqa', 'mscreenshotqa'}

local trigger_path = 'C:/Users/xtyty/Documents/FFXI-Runtime/screenshots/native_screenshot_request.txt'
local last_check = 0

local function trim(value)
    return (value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function read_request()
    local handle = io.open(trigger_path, 'r')
    if not handle then
        return nil
    end

    local request = handle:read('*a') or ''
    handle:close()
    os.remove(trigger_path)
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

windower.register_event('prerender', function()
    local now = os.clock()
    if now - last_check < 0.25 then
        return
    end

    last_check = now
    local request = read_request()
    if request and request ~= '' then
        run_request(request)
    end
end)

windower.register_event('addon command', function(command)
    command = (command or 'status'):lower()
    if command == 'status' or command == 's' then
        windower.add_to_chat(207, 'MochiriiScreenshotQA: watching ' .. trigger_path)
    end
end)
