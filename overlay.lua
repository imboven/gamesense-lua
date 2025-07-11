local ui_get, ui_set, ui_new_checkbox, ui_new_multiselect, ui_new_textbox, ui_new_slider, ui_new_color_picker, ui_new_hotkey = 
ui.get, ui.set, ui.new_checkbox, ui.new_multiselect, ui.new_textbox, ui.new_slider, ui.new_color_picker, ui.new_hotkey

local client_screen_size, client_system_time, client_latency, client_userid_to_entindex, client_key_state =
client.screen_size, client.system_time, client.latency, client.userid_to_entindex, client.key_state

local entity_get_local_player, entity_get_players, entity_get_player_name, entity_get_prop, entity_is_alive, entity_is_enemy, entity_is_dormant =
entity.get_local_player, entity.get_players, entity.get_player_name, entity.get_prop, entity.is_alive, entity.is_enemy, entity.is_dormant

local renderer_text, renderer_measure_text, renderer_rectangle, renderer_gradient =
renderer.text, renderer.measure_text, renderer.rectangle, renderer.gradient

local globals_realtime, globals_frametime, globals_mapname, globals_tickinterval =
globals.realtime, globals.frametime, globals.mapname, globals.tickinterval

local math_floor, math_min, math_max, math_sqrt, math_sin, math_abs =
math.floor, math.min, math.max, math.sqrt, math.sin, math.abs

local database_read, database_write = database.read, database.write

local screen_adaptation = {
    base_width = 1920,
    base_height = 1080,
    scale_factor = 1,
    padding_scale = 1,
    font_scale = 1
}

local function update_screen_scale()
    local screen_width, screen_height = client_screen_size()

    screen_adaptation.scale_factor = screen_width / screen_adaptation.base_width

    screen_adaptation.scale_factor = math_max(0.7, math_min(1.5, screen_adaptation.scale_factor))
    
    screen_adaptation.padding_scale = math_max(0.8, math_min(1.2, screen_adaptation.scale_factor))
    screen_adaptation.font_scale = math_max(0.9, math_min(1.1, screen_adaptation.scale_factor))
end

local animation = {
    watermark = 0,
    spectator = 0,
    spectator_height = 0,
    spectator_count = 0,
    hotkeys = 0,
    hotkeys_height = 0,
    hotkeys_count = 0,
    speed = 8,
    threshold = 0.001
}

local function lerp(current, target, speed, threshold)
    local diff = target - current
    if math_abs(diff) < (threshold or animation.threshold) then
        return target
    end
    return current + diff * globals_frametime() * (speed or animation.speed)
end

local refs = {
    rage = {
        aimbot = {
            double_tap = {},
        },
        other = {},
    },
    aa = {
        other = {},
    }
}

refs.rage.aimbot.double_tap.checkbox, refs.rage.aimbot.double_tap.hotkey = ui.reference("RAGE", "Aimbot", "Double tap")
refs.rage.other.duck = ui.reference("RAGE", "Other", "Duck peek assist")
refs.aa.other.onshot = {}
refs.aa.other.onshot.checkbox, refs.aa.other.onshot.hotkey = ui.reference("AA", "Other", "On shot anti-aim")

local enabled = ui_new_checkbox("MISC", "Miscellaneous", "Watermark")
local color_picker = ui_new_color_picker("MISC", "Miscellaneous", "Watermark Color")
ui_set(color_picker, 255, 255, 255, 255)

local sense_color_picker = ui_new_color_picker("MISC", "Miscellaneous", "Sense Color")
ui_set(sense_color_picker, 159, 202, 43, 255)

local watermark_elements = ui_new_multiselect("MISC", "Miscellaneous", "Watermark Elements", {
    "Custom Text", "Fps", "Ping", "Kdr", "Time", "Map name", "Tickrate", 
    "Duck amount", "Enemies", "Server ip", "Username", "Time + seconds"
})

local custom_text = ui_new_textbox("MISC", "Miscellaneous", "Custom Text")
local rainbow_header = ui_new_checkbox("MISC", "Miscellaneous", "Rainbow Header")
local rainbow_speed = ui_new_slider("MISC", "Miscellaneous", "Rainbow Speed", 1, 100, 10)

local spectator_enabled = ui_new_checkbox("MISC", "Miscellaneous", "Spectator List")
local spectator_color = ui_new_color_picker("MISC", "Miscellaneous", "Spectator Color")
ui_set(spectator_color, 255, 255, 255, 255)
local spectator_rainbow = ui_new_checkbox("MISC", "Miscellaneous", "Spectator Rainbow Header")

local hotkeys_enabled = ui_new_checkbox("MISC", "Miscellaneous", "Hotkeys List")
local hotkeys_color = ui_new_color_picker("MISC", "Miscellaneous", "Hotkeys Color")
ui_set(hotkeys_color, 255, 255, 255, 255)
local hotkeys_rainbow = ui_new_checkbox("MISC", "Miscellaneous", "Hotkeys Rainbow Header")

local dragging = {
    watermark = false,
    spectator = false,
    hotkeys = false
}

local drag_offset = {
    watermark = {x = 0, y = 0},
    spectator = {x = 0, y = 0}, 
    hotkeys = {x = 0, y = 0}
}

local positions = database_read("wsh_positions") or {
    watermark = {x = 0, y = 0},
    spectator = {x = 0, y = 0},
    hotkeys = {x = 0, y = 0}
}

local spectator_anims = {}
local hotkey_items = {
    {name = "Double tap", ref_checkbox = refs.rage.aimbot.double_tap.checkbox, ref_hotkey = refs.rage.aimbot.double_tap.hotkey, anim = 0},
    {name = "Hide shots", ref_checkbox = refs.aa.other.onshot.checkbox, ref_hotkey = refs.aa.other.onshot.hotkey, anim = 0},
    {name = "Duck peek assist", ref_checkbox = refs.rage.other.duck, ref_hotkey = nil, anim = 0}
}

local function hsv_to_rgb(h, s, v)
    local r, g, b
    local i = math_floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    
    local remainder = i % 6
    if remainder == 0 then
        r, g, b = v, t, p
    elseif remainder == 1 then
        r, g, b = q, v, p
    elseif remainder == 2 then
        r, g, b = p, v, t
    elseif remainder == 3 then
        r, g, b = p, q, v
    elseif remainder == 4 then
        r, g, b = t, p, v
    else
        r, g, b = v, p, q
    end
    
    return math_floor(r * 255), math_floor(g * 255), math_floor(b * 255)
end

local function get_kdr()
    local local_player = entity_get_local_player()
    if not local_player then return "0.00" end
    
    local player_resource = entity.get_player_resource()
    if not player_resource then return "0.00" end
    
    local kills = entity_get_prop(player_resource, "m_iKills", local_player) or 0
    local deaths = entity_get_prop(player_resource, "m_iDeaths", local_player) or 0
    
    if deaths == 0 then
        return tostring(kills)
    else
        return string.format("%.2f", kills / deaths)
    end
end

local function get_duck_amount()
    local local_player = entity_get_local_player()
    if not local_player then return "0.0" end
    
    local duck_amount = entity_get_prop(local_player, "m_flDuckAmount") or 0
    return string.format("%.1f", math_abs(duck_amount))
end

local function get_enemy_count()
    local enemies = entity_get_players(true)
    return tostring(#enemies)
end

local function get_spectators()
    local local_player = entity_get_local_player()
    if not local_player then return {} end
    
    local spectators = {}
    local target_player
    
    local ob_target, ob_mode = entity_get_prop(local_player, "m_hObserverTarget"), entity_get_prop(local_player, "m_iObserverMode")
    if ob_target and (ob_mode == 4 or ob_mode == 5) then
        target_player = ob_target
    else
        target_player = local_player
    end
    

    for ent = 1, 64 do
        if entity.get_classname(ent) == "CCSPlayer" and ent ~= local_player then
            local cob_target, cob_mode = entity_get_prop(ent, "m_hObserverTarget"), entity_get_prop(ent, "m_iObserverMode")
            
            if cob_target and cob_target == target_player and (cob_mode == 4 or cob_mode == 5) then
                local name = entity_get_player_name(ent)
                if name then
                    table.insert(spectators, {name = name, ent = ent})
                end
            end
        end
    end
    
    return spectators
end

local function get_active_hotkeys()
    local hotkeys = {}
    
    if ui_get(refs.rage.aimbot.double_tap.checkbox) then
        local active, mode = ui_get(refs.rage.aimbot.double_tap.hotkey)
        if active then
            hotkeys[#hotkeys + 1] = {name = "Double tap", state = "on"}
        end
    end
    
    if ui_get(refs.aa.other.onshot.checkbox) then
        local active, mode = ui_get(refs.aa.other.onshot.hotkey)
        if active then
            hotkeys[#hotkeys + 1] = {name = "Hide shots", state = "on"}
        end
    end
    
    if ui_get(refs.rage.other.duck) then
        hotkeys[#hotkeys + 1] = {name = "Duck peek assist", state = "on"}
    end
    
    return hotkeys
end

local function handle_mouse()
    if not ui.is_menu_open() then 
        if dragging.watermark or dragging.spectator or dragging.hotkeys then
            database_write("wsh_positions", positions)
            dragging.watermark = false
            dragging.spectator = false  
            dragging.hotkeys = false
        end
        return 
    end
    
    local mouse_x, mouse_y = ui.mouse_position()
    local is_mouse_down = client_key_state(0x01)
    
    if not is_mouse_down then
        if dragging.watermark or dragging.spectator or dragging.hotkeys then
            database_write("wsh_positions", positions)
        end
        dragging.watermark = false
        dragging.spectator = false
        dragging.hotkeys = false
        return
    end
    
    if dragging.watermark then
        positions.watermark.x = mouse_x - drag_offset.watermark.x
        positions.watermark.y = mouse_y - drag_offset.watermark.y
    end
    
    if dragging.spectator then
        positions.spectator.x = mouse_x - drag_offset.spectator.x
        positions.spectator.y = mouse_y - drag_offset.spectator.y
    end
    
    if dragging.hotkeys then
        positions.hotkeys.x = mouse_x - drag_offset.hotkeys.x  
        positions.hotkeys.y = mouse_y - drag_offset.hotkeys.y
    end
end



local function watermark()
    update_screen_scale()
    
    local should_show = ui_get(enabled) and (entity_get_local_player() ~= nil)
    animation.watermark = lerp(animation.watermark, should_show and 1 or 0, animation.speed)
    
    if animation.watermark < 0.01 then return end
    
    local screen_width, screen_height = client_screen_size()
    local elements = ui_get(watermark_elements)
    
    local rainbow_time = globals_realtime() * (ui_get(rainbow_speed) / 100)
    local rainbow_r, rainbow_g, rainbow_b = hsv_to_rgb(rainbow_time % 1, 1, 1)
    
    local header_part1 = "game"
    local header_part2 = "sense"
    local all_elements = {}
    
    if type(elements) == "table" then
        for i, element in ipairs(elements) do
            if element == "Custom Text" and ui_get(custom_text) ~= "" then
                all_elements[#all_elements + 1] = ui_get(custom_text)
            elseif element == "Username" then
                local local_player = entity_get_local_player()
                local username = local_player and entity_get_player_name(local_player) or "user"
                username = string.gsub(username, "^%s*(.-)%s*$", "%1")
                all_elements[#all_elements + 1] = username
            elseif element == "Fps" then
                local fps = math_floor(1 / globals_frametime())
                all_elements[#all_elements + 1] = fps .. " fps"
            elseif element == "Ping" then
                local ping = math_floor(client_latency() * 1000)
                all_elements[#all_elements + 1] = ping .. "ms"
            elseif element == "Map name" then
                local map = globals_mapname()
                all_elements[#all_elements + 1] = map
            elseif element == "Tickrate" then
                local tickrate = math_floor(1 / globals_tickinterval())
                all_elements[#all_elements + 1] = "delay: " .. tickrate
            elseif element == "Server ip" then
                all_elements[#all_elements + 1] = "server: local"
            elseif element == "Duck amount" then
                local duck = get_duck_amount()
                all_elements[#all_elements + 1] = "duck amount: " .. duck
            elseif element == "Enemies" then
                local enemies = get_enemy_count()
                all_elements[#all_elements + 1] = "enemies: " .. enemies
            elseif element == "Kdr" then
                local kdr = get_kdr()
                all_elements[#all_elements + 1] = kdr .. " kdr"
            elseif element == "Time" then
                local hours, minutes, seconds = client_system_time()
                all_elements[#all_elements + 1] = string.format("%02d:%02d", hours, minutes)
            elseif element == "Time + seconds" then
                local hours, minutes, seconds = client_system_time()
                all_elements[#all_elements + 1] = string.format("%02d:%02d:%02d", hours, minutes, seconds)
            end
        end
    end
    
    local content_text = table.concat(all_elements, " | ")
    local suffix = (#all_elements > 0 and " | " or "") .. content_text
    local measure_text = header_part1 .. header_part2 .. suffix
    local text_width = renderer_measure_text(nil, measure_text)
    local base_padding = math_floor(8 * screen_adaptation.padding_scale)
    local base_height = math_floor(16 * screen_adaptation.padding_scale)
    local w, h = text_width + base_padding, base_height
    
    local padding = math_floor(8 * screen_adaptation.padding_scale)
    local margin = math_floor(16 * screen_adaptation.padding_scale)
    local border_size = math_floor(6 * screen_adaptation.padding_scale)
    
    local x, y
    if positions.watermark.x == 0 and positions.watermark.y == 0 then
        x = screen_width - w - margin
        y = math_floor(12 * screen_adaptation.padding_scale)
        positions.watermark.x = x
        positions.watermark.y = y
    else
        x = positions.watermark.x
        y = positions.watermark.y
    end
    
    if ui.is_menu_open() and not dragging.watermark and not dragging.spectator and not dragging.hotkeys then
        local mouse_x, mouse_y = ui.mouse_position()
        local is_mouse_down = client_key_state(0x01)
        local click_padding = border_size
        
        if is_mouse_down and mouse_x >= x - 5 and mouse_x <= x + w + 5 and 
           mouse_y >= y - 5 and mouse_y <= y + h + 5 then
            dragging.watermark = true
            drag_offset.watermark.x = mouse_x - x
            drag_offset.watermark.y = mouse_y - y
        end
    end
    
    local alpha = math_floor(animation.watermark * 255)
    local border_alpha = math_floor(animation.watermark * 255)
    local outer_border = border_size
    local inner_border = border_size - 1
    
    renderer_rectangle(x - 5, y - 5, w + 10, h + 10, 0, 0, 0, alpha)
    renderer_rectangle(x - 4, y - 4, w + 8, h + 8, 34, 34, 34, alpha)
    renderer_rectangle(x, y, w, h, 0, 0, 0, alpha)
    
    renderer_rectangle(x - 4, y - 4, w + 8, 1, 56, 56, 56, border_alpha)
    renderer_rectangle(x - 4, y - 3, 1, h + 6, 56, 56, 56, border_alpha)
    renderer_rectangle(x + w + 3, y - 3, 1, h + 6, 56, 56, 56, border_alpha)
    renderer_rectangle(x - 4, y + h + 3, w + 8, 1, 56, 56, 56, border_alpha)
    
    renderer_rectangle(x - 1, y - 1, w + 2, 1, 56, 56, 56, border_alpha)
    renderer_rectangle(x - 1, y, 1, h, 56, 56, 56, border_alpha)
    renderer_rectangle(x + w, y, 1, h, 56, 56, 56, border_alpha)
    renderer_rectangle(x - 1, y + h, w + 2, 1, 56, 56, 56, border_alpha)
    
    local gradient_x = x + 1
    local gradient_width = w - 2
    local gradient_alpha = math_floor(animation.watermark * 255)
    local gradient_alpha_half = math_floor(animation.watermark * 130)
    
    if ui_get(rainbow_header) then
        renderer_gradient(gradient_x, y + 1, gradient_width / 2, 1, rainbow_g, rainbow_b, rainbow_r, gradient_alpha, rainbow_r, rainbow_g, rainbow_b, gradient_alpha, true)
        renderer_gradient(gradient_x + gradient_width / 2, y + 1, gradient_width / 2, 1, rainbow_r, rainbow_g, rainbow_b, gradient_alpha, rainbow_b, rainbow_r, rainbow_g, gradient_alpha, true)
        renderer_gradient(gradient_x, y + 2, gradient_width / 2, 1, rainbow_g, rainbow_b, rainbow_r, gradient_alpha_half, rainbow_r, rainbow_g, rainbow_b, gradient_alpha_half, true)
        renderer_gradient(gradient_x + gradient_width / 2, y + 2, gradient_width / 2, 1, rainbow_r, rainbow_g, rainbow_b, gradient_alpha_half, rainbow_b, rainbow_r, rainbow_g, gradient_alpha_half, true)
    else
        renderer_gradient(gradient_x, y + 1, gradient_width / 2, 1, 59, 175, 222, gradient_alpha, 202, 70, 205, gradient_alpha, true)
        renderer_gradient(gradient_x + gradient_width / 2, y + 1, gradient_width / 2, 1, 202, 70, 205, gradient_alpha, 201, 227, 58, gradient_alpha, true)
        renderer_gradient(gradient_x, y + 2, gradient_width / 2, 1, 59, 175, 222, gradient_alpha_half, 202, 70, 205, gradient_alpha_half, true)
        renderer_gradient(gradient_x + gradient_width / 2, y + 2, gradient_width / 2, 1, 202, 70, 205, gradient_alpha_half, 201, 227, 58, gradient_alpha_half, true)
    end
    
    local color_r, color_g, color_b, color_a = ui_get(color_picker)
    local sense_r, sense_g, sense_b, sense_a = ui_get(sense_color_picker)
    local text_alpha = math_floor(animation.watermark * color_a)
    local sense_text_alpha = math_floor(animation.watermark * sense_a)
    local shadow_alpha = math_floor(animation.watermark * 180)
    
    local text_padding_x = math_floor(4 * screen_adaptation.padding_scale)
    local text_padding_y = math_floor(4 * screen_adaptation.padding_scale)
    
    local current_x = x + text_padding_x
    local text_y = y + text_padding_y
    
    renderer_text(current_x, text_y + 1, 0, 0, 0, shadow_alpha, nil, 0, header_part1)
    renderer_text(current_x, text_y, color_r, color_g, color_b, text_alpha, nil, 0, header_part1)
    current_x = current_x + renderer_measure_text(nil, header_part1)

    renderer_text(current_x, text_y + 1, 0, 0, 0, shadow_alpha, nil, 0, header_part2)
    renderer_text(current_x, text_y, sense_r, sense_g, sense_b, sense_text_alpha, nil, 0, header_part2)
    current_x = current_x + renderer_measure_text(nil, header_part2)

    renderer_text(current_x, text_y + 1, 0, 0, 0, shadow_alpha, nil, 0, suffix)
    renderer_text(current_x, text_y, color_r, color_g, color_b, text_alpha, nil, 0, suffix)
end

local function spectator_list()
    update_screen_scale()
    
    local spectators = get_spectators()
    local is_menu_open = ui.is_menu_open()
    
    local target_anims = {}
    for _, spec in ipairs(spectators) do
        target_anims[spec.ent] = 1
    end
    
    for ent, _ in pairs(target_anims) do
        spectator_anims[ent] = lerp(spectator_anims[ent] or 0, 1, animation.speed)
    end
    
    local to_remove = {}
    for ent, anim in pairs(spectator_anims) do
        if not target_anims[ent] then
            spectator_anims[ent] = lerp(anim, 0, animation.speed)
            if spectator_anims[ent] < animation.threshold then
                table.insert(to_remove, ent)
            end
        end
    end
    for _, ent in ipairs(to_remove) do
        spectator_anims[ent] = nil
    end
    
    local display_spectators = {}
    for ent, anim in pairs(spectator_anims) do
        local name = entity_get_player_name(ent)
        if name and anim > 0.01 then
            table.insert(display_spectators, {name = name, progress = anim})
        end
    end
    table.sort(display_spectators, function(a, b) return a.name < b.name end)
    
    local should_show = ui_get(spectator_enabled) and (#display_spectators > 0 or is_menu_open)
    animation.spectator = lerp(animation.spectator, should_show and 1 or 0, animation.speed)
    
    if animation.spectator < 0.01 then return end
    
    if #display_spectators == 0 and is_menu_open then
        display_spectators = {{name = "example spectator", progress = 1}, {name = "another viewer", progress = 1}}
    end
    
    local screen_width, screen_height = client_screen_size()
    local rainbow_time = globals_realtime() * (ui_get(rainbow_speed) / 100)
    local rainbow_r, rainbow_g, rainbow_b = hsv_to_rgb(rainbow_time % 1, 1, 1)
    
    local max_name_width = 0
    for _, spec in ipairs(display_spectators) do
        local name_width = renderer_measure_text(nil, spec.name)
        if name_width > max_name_width then
            max_name_width = name_width
        end
    end
    
    local header_text = "spectators"
    local header_width = renderer_measure_text(nil, header_text)
    local w = math_max(header_width + 16, max_name_width + 16)
    local header_h = 16
    local item_h = 14
    
    local animated_height = 0
    for _, spec in ipairs(display_spectators) do
        animated_height = animated_height + spec.progress * item_h
    end
    local total_h = header_h + animated_height
    
    local x, y
    if positions.spectator.x == 0 and positions.spectator.y == 0 then
        x = 16
        y = screen_height - total_h - 16
    else
        x = positions.spectator.x
        y = positions.spectator.y
    end
    
    if ui.is_menu_open() and not dragging.watermark and not dragging.spectator and not dragging.hotkeys then
        local mouse_x, mouse_y = ui.mouse_position()
        local is_mouse_down = client_key_state(0x01)
        
        if is_mouse_down and mouse_x >= x - 5 and mouse_x <= x + w + 5 and 
           mouse_y >= y - 5 and mouse_y <= y + total_h + 5 then
            dragging.spectator = true
            drag_offset.spectator.x = mouse_x - x
            drag_offset.spectator.y = mouse_y - y
        end
    end
    
    local alpha = math_floor(animation.spectator * 255)
    local border_alpha = math_floor(animation.spectator * 255)
    
    renderer_rectangle(x - 5, y - 5, w + 10, total_h + 10, 0, 0, 0, alpha)
    renderer_rectangle(x - 4, y - 4, w + 8, total_h + 8, 34, 34, 34, alpha)
    renderer_rectangle(x, y, w, header_h, 0, 0, 0, alpha)
    
    renderer_rectangle(x - 4, y - 4, w + 8, 1, 56, 56, 56, border_alpha)
    renderer_rectangle(x - 4, y - 3, 1, total_h + 6, 56, 56, 56, border_alpha)
    renderer_rectangle(x + w + 3, y - 3, 1, total_h + 6, 56, 56, 56, border_alpha)
    renderer_rectangle(x - 4, y + total_h + 3, w + 8, 1, 56, 56, 56, border_alpha)
    
    renderer_rectangle(x - 1, y - 1, w + 2, 1, 56, 56, 56, border_alpha)
    renderer_rectangle(x - 1, y, 1, total_h, 56, 56, 56, border_alpha)
    renderer_rectangle(x + w, y, 1, total_h, 56, 56, 56, border_alpha)
    renderer_rectangle(x - 1, y + total_h, w + 2, 1, 56, 56, 56, border_alpha)
    
    local gradient_x = x + 1
    local gradient_width = w - 2
    local gradient_alpha = math_floor(animation.spectator * 255)
    local gradient_alpha_half = math_floor(animation.spectator * 130)
    
    if ui_get(spectator_rainbow) then
        renderer_gradient(gradient_x, y + 1, gradient_width / 2, 1, rainbow_g, rainbow_b, rainbow_r, gradient_alpha, rainbow_r, rainbow_g, rainbow_b, gradient_alpha, true)
        renderer_gradient(gradient_x + gradient_width / 2, y + 1, gradient_width / 2, 1, rainbow_r, rainbow_g, rainbow_b, gradient_alpha, rainbow_b, rainbow_r, rainbow_g, gradient_alpha, true)
        renderer_gradient(gradient_x, y + 2, gradient_width / 2, 1, rainbow_g, rainbow_b, rainbow_r, gradient_alpha_half, rainbow_r, rainbow_g, rainbow_b, gradient_alpha_half, true)
        renderer_gradient(gradient_x + gradient_width / 2, y + 2, gradient_width / 2, 1, rainbow_r, rainbow_g, rainbow_b, gradient_alpha_half, rainbow_b, rainbow_r, rainbow_g, gradient_alpha_half, true)
    else
        renderer_gradient(gradient_x, y + 1, gradient_width / 2, 1, 59, 175, 222, gradient_alpha, 202, 70, 205, gradient_alpha, true)
        renderer_gradient(gradient_x + gradient_width / 2, y + 1, gradient_width / 2, 1, 202, 70, 205, gradient_alpha, 201, 227, 58, gradient_alpha, true)
        renderer_gradient(gradient_x, y + 2, gradient_width / 2, 1, 59, 175, 222, gradient_alpha_half, 202, 70, 205, gradient_alpha_half, true)
        renderer_gradient(gradient_x + gradient_width / 2, y + 2, gradient_width / 2, 1, 202, 70, 205, gradient_alpha_half, 201, 227, 58, gradient_alpha_half, true)
    end
    
    local color_r, color_g, color_b, color_a = ui_get(spectator_color)
    local header_text_width = renderer_measure_text(nil, header_text)
    local header_x = x + (w / 2) - (header_text_width / 2)
    local text_alpha = math_floor(animation.spectator * color_a)
    local shadow_alpha = math_floor(animation.spectator * 180)
    
    renderer_text(header_x, y + 2 + 1, 0, 0, 0, shadow_alpha, nil, 0, header_text)
    renderer_text(header_x, y + 2, color_r, color_g, color_b, text_alpha, nil, 0, header_text)
    
    local separator_alpha = math_floor(animation.spectator * 255)
    renderer_rectangle(x + 1, y + header_h, w - 2, 1, 45, 45, 45, separator_alpha)

    local current_offset = header_h
    for i, spec in ipairs(display_spectators) do
        local item_progress = spec.progress
        local this_height = item_progress * item_h
        local item_y = y + current_offset
        
        local item_alpha = math_floor(animation.spectator * item_progress * 255)
        local item_bg_alpha = math_floor(animation.spectator * item_progress * 25)
        local item_sep_alpha = math_floor(animation.spectator * item_progress * 45)
        local name_shadow_alpha = math_floor(animation.spectator * item_progress * 180)
        
        if this_height > 0.5 then
            if i > 1 then
                renderer_rectangle(x + 1, item_y, w - 2, 1, 45, 45, 45, item_sep_alpha)
            end
            renderer_rectangle(x, item_y, w, this_height, 25, 25, 25, item_bg_alpha)
            
            local text_y = item_y + 1
            local text_width = renderer_measure_text(nil, spec.name)
            local name_x = x + (w / 2) - (text_width / 2)
            renderer_text(name_x, text_y + 1, 0, 0, 0, name_shadow_alpha, nil, 0, spec.name)
            renderer_text(name_x, text_y, 255, 255, 255, item_alpha, nil, 0, spec.name)
        end
        
        current_offset = current_offset + this_height
    end
end

local function hotkeys_list()
    update_screen_scale()
    
    local is_menu_open = ui.is_menu_open()
    
    for _, item in ipairs(hotkey_items) do
        local active = false
        if ui_get(item.ref_checkbox) then
            if item.ref_hotkey then
                local is_active, mode = ui_get(item.ref_hotkey)
                active = is_active
            else
                active = true
            end
        end
        item.anim = lerp(item.anim, active and 1 or 0, animation.speed)
    end
    
    local display_hotkeys = {}
    for _, item in ipairs(hotkey_items) do
        if item.anim > 0.01 then
            table.insert(display_hotkeys, {name = item.name, state = "on", progress = item.anim})
        end
    end
    
    local should_show = ui_get(hotkeys_enabled) and (#display_hotkeys > 0 or is_menu_open)
    animation.hotkeys = lerp(animation.hotkeys, should_show and 1 or 0, animation.speed)
    
    if animation.hotkeys < 0.01 then return end
    
    if #display_hotkeys == 0 and is_menu_open then
        display_hotkeys = {{name = "Double tap", state = "on", progress = 1}, {name = "Hide shots", state = "on", progress = 1}}
    end
    
    local screen_width, screen_height = client_screen_size()
    local rainbow_time = globals_realtime() * (ui_get(rainbow_speed) / 100)
    local rainbow_r, rainbow_g, rainbow_b = hsv_to_rgb(rainbow_time % 1, 1, 1)
    
    local max_name_width = 0
    for _, hotkey in ipairs(display_hotkeys) do
        local full_text = hotkey.name .. " [" .. hotkey.state .. "]"
        local name_width = renderer_measure_text(nil, full_text)
        if name_width > max_name_width then
            max_name_width = name_width
        end
    end
    
    local header_text = "keybinds"
    local header_width = renderer_measure_text(nil, header_text)
    local w = math_max(header_width + 16, max_name_width + 16)
    local header_h = 16
    local item_h = 14
    
    local animated_height = 0
    for _, hotkey in ipairs(display_hotkeys) do
        animated_height = animated_height + hotkey.progress * item_h
    end
    local total_h = header_h + animated_height
    
    local x, y
    if positions.hotkeys.x == 0 and positions.hotkeys.y == 0 then
        x = screen_width - w - 16
        y = screen_height - total_h - 16
    else
        x = positions.hotkeys.x
        y = positions.hotkeys.y
    end
    
    if ui.is_menu_open() and not dragging.watermark and not dragging.spectator and not dragging.hotkeys then
        local mouse_x, mouse_y = ui.mouse_position()
        local is_mouse_down = client_key_state(0x01)
        
        if is_mouse_down and mouse_x >= x - 5 and mouse_x <= x + w + 5 and 
           mouse_y >= y - 5 and mouse_y <= y + total_h + 5 then
            dragging.hotkeys = true
            drag_offset.hotkeys.x = mouse_x - x
            drag_offset.hotkeys.y = mouse_y - y
        end
    end
    
    local alpha = math_floor(animation.hotkeys * 255)
    local border_alpha = math_floor(animation.hotkeys * 255)
    
    renderer_rectangle(x - 5, y - 5, w + 10, total_h + 10, 0, 0, 0, alpha)
    renderer_rectangle(x - 4, y - 4, w + 8, total_h + 8, 34, 34, 34, alpha)
    renderer_rectangle(x, y, w, header_h, 0, 0, 0, alpha)
    
    renderer_rectangle(x - 4, y - 4, w + 8, 1, 56, 56, 56, border_alpha)
    renderer_rectangle(x - 4, y - 3, 1, total_h + 6, 56, 56, 56, border_alpha)
    renderer_rectangle(x + w + 3, y - 3, 1, total_h + 6, 56, 56, 56, border_alpha)
    renderer_rectangle(x - 4, y + total_h + 3, w + 8, 1, 56, 56, 56, border_alpha)
    
    renderer_rectangle(x - 1, y - 1, w + 2, 1, 56, 56, 56, border_alpha)
    renderer_rectangle(x - 1, y, 1, total_h, 56, 56, 56, border_alpha)
    renderer_rectangle(x + w, y, 1, total_h, 56, 56, 56, border_alpha)
    renderer_rectangle(x - 1, y + total_h, w + 2, 1, 56, 56, 56, border_alpha)
    
    local gradient_x = x + 1
    local gradient_width = w - 2
    local gradient_alpha = math_floor(animation.hotkeys * 255)
    local gradient_alpha_half = math_floor(animation.hotkeys * 130)
    
    if ui_get(hotkeys_rainbow) then
        renderer_gradient(gradient_x, y + 1, gradient_width / 2, 1, rainbow_g, rainbow_b, rainbow_r, gradient_alpha, rainbow_r, rainbow_g, rainbow_b, gradient_alpha, true)
        renderer_gradient(gradient_x + gradient_width / 2, y + 1, gradient_width / 2, 1, rainbow_r, rainbow_g, rainbow_b, gradient_alpha, rainbow_b, rainbow_r, rainbow_g, gradient_alpha, true)
        renderer_gradient(gradient_x, y + 2, gradient_width / 2, 1, rainbow_g, rainbow_b, rainbow_r, gradient_alpha_half, rainbow_r, rainbow_g, rainbow_b, gradient_alpha_half, true)
        renderer_gradient(gradient_x + gradient_width / 2, y + 2, gradient_width / 2, 1, rainbow_r, rainbow_g, rainbow_b, gradient_alpha_half, rainbow_b, rainbow_r, rainbow_g, gradient_alpha_half, true)
    else
        renderer_gradient(gradient_x, y + 1, gradient_width / 2, 1, 59, 175, 222, gradient_alpha, 202, 70, 205, gradient_alpha, true)
        renderer_gradient(gradient_x + gradient_width / 2, y + 1, gradient_width / 2, 1, 202, 70, 205, gradient_alpha, 201, 227, 58, gradient_alpha, true)
        renderer_gradient(gradient_x, y + 2, gradient_width / 2, 1, 59, 175, 222, gradient_alpha_half, 202, 70, 205, gradient_alpha_half, true)
        renderer_gradient(gradient_x + gradient_width / 2, y + 2, gradient_width / 2, 1, 202, 70, 205, gradient_alpha_half, 201, 227, 58, gradient_alpha_half, true)
    end
    
    local color_r, color_g, color_b, color_a = ui_get(hotkeys_color)
    local header_text_width = renderer_measure_text(nil, header_text)
    local header_x = x + (w / 2) - (header_text_width / 2)
    local text_alpha = math_floor(animation.hotkeys * color_a)
    local shadow_alpha = math_floor(animation.hotkeys * 180)
    
    renderer_text(header_x, y + 2 + 1, 0, 0, 0, shadow_alpha, nil, 0, header_text)
    renderer_text(header_x, y + 2, color_r, color_g, color_b, text_alpha, nil, 0, header_text)
    
    local separator_alpha = math_floor(animation.hotkeys * 255)
    renderer_rectangle(x + 1, y + header_h, w - 2, 1, 45, 45, 45, separator_alpha)

    local current_offset = header_h
    for i, hotkey in ipairs(display_hotkeys) do
        local item_progress = hotkey.progress
        local this_height = item_progress * item_h
        local item_y = y + current_offset
        
        local item_alpha = math_floor(animation.hotkeys * item_progress * 255)
        local item_bg_alpha = math_floor(animation.hotkeys * item_progress * 25)
        local item_sep_alpha = math_floor(animation.hotkeys * item_progress * 45)
        local name_shadow_alpha = math_floor(animation.hotkeys * item_progress * 180)
        
        if this_height > 0.5 then
            if i > 1 then
                renderer_rectangle(x + 1, item_y, w - 2, 1, 45, 45, 45, item_sep_alpha)
            end
            renderer_rectangle(x, item_y, w, this_height, 25, 25, 25, item_bg_alpha)
            
            local text_y = item_y + 1
            local full_text = hotkey.name .. " [" .. hotkey.state .. "]"
            local text_width = renderer_measure_text(nil, full_text)
            local name_x = x + (w / 2) - (text_width / 2)
            renderer_text(name_x, text_y + 1, 0, 0, 0, name_shadow_alpha, nil, 0, full_text)
            renderer_text(name_x, text_y, 255, 255, 255, item_alpha, nil, 0, full_text)
        end
        
        current_offset = current_offset + this_height
    end
end

client.set_event_callback("paint", watermark)
client.set_event_callback("paint", spectator_list)
client.set_event_callback("paint", hotkeys_list)
client.set_event_callback("paint_ui", handle_mouse)

client.set_event_callback("setup_command", function(cmd)
    if ui.is_menu_open() and (dragging.watermark or dragging.spectator or dragging.hotkeys) then
        cmd.in_attack = 0
        cmd.in_attack2 = 0
    end
end)
