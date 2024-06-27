util.require_natives(1663599433)
local json = require("json")

-- Auto updater thanks to Hexarobi
util.ensure_package_is_installed("lua/auto-updater")
local auto_updater = require("auto-updater")

auto_updater.run_auto_update({
    source_url="https://raw.githubusercontent.com/Jeremias2402/My-Drift-Mod/main/My-Drift-Mod.lua",
    script_relpath=SCRIPT_RELPATH,
})

local local_drift_score = 0
local local_last_drift_time = util.current_time_millis()
local drift_scores = {}
local last_drift_times = {}
local drift_mod_dir = filesystem.scripts_dir() .. "\\DriftMod"
filesystem.mkdirs(drift_mod_dir)
local player_scores_file = drift_mod_dir .. "\\PlayerScores.json"
local player_scores = {}

local offset_x = 0
local offset_y = 0
local offset_z = 1
local proximity_threshold = 500
local show_distance = false
local show_other_players_scores = true
local drift_mode_enabled = false

local function load_scores(file_path)
    if not filesystem.exists(file_path) then
        return {}
    end
    local file = io.open(file_path, "r")
    if not file then
        util.log("Failed to open scores file for reading")
        return {}
    end
    local content = file:read("*a")
    file:close()
    return json.decode(content) or {}
end

local function save_scores(file_path, data)
    local file = io.open(file_path, "w")
    if not file then
        util.log("Failed to open scores file for writing")
        return
    end
    file:write(json.encode(data))
    file:close()
end

player_scores = load_scores(player_scores_file)

local function get_drift_direction(vehicle)
    local velocity = ENTITY.GET_ENTITY_VELOCITY(vehicle)
    local forward_vector = ENTITY.GET_ENTITY_FORWARD_VECTOR(vehicle)
    local dot_product = velocity.x * forward_vector.x + velocity.y * forward_vector.y
    local cross_product = velocity.x * forward_vector.y - velocity.y * forward_vector.x
    local mag_velocity = math.sqrt(velocity.x^2 + velocity.y^2)
    local mag_forward = math.sqrt(forward_vector.x^2 + forward_vector.y^2)
    local angle = math.acos(dot_product / (mag_velocity * mag_forward))
    angle = angle * (180 / math.pi)
    local direction = "left"
    if cross_product > 0 then
        direction = "right"
    end
    return angle, dot_product, direction
end

local function draw_text(x, y, text, scale, color, font)
    HUD.BEGIN_TEXT_COMMAND_DISPLAY_TEXT("STRING")
    HUD.SET_TEXT_FONT(font)
    HUD.SET_TEXT_SCALE(scale, scale)
    HUD.SET_TEXT_COLOUR(color.r * 255, color.g * 255, color.b * 255, color.a * 255)
    HUD.SET_TEXT_CENTRE(true)
    HUD.ADD_TEXT_COMPONENT_SUBSTRING_PLAYER_NAME(text)
    HUD.END_TEXT_COMMAND_DISPLAY_TEXT(x, y)
end

local function world_to_screen(x, y, z)
    local screen_x_ptr = memory.alloc(8)
    local screen_y_ptr = memory.alloc(8)
    local success = GRAPHICS.GET_SCREEN_COORD_FROM_WORLD_COORD(x, y, z, screen_x_ptr, screen_y_ptr)
    local screen_x = memory.read_float(screen_x_ptr)
    local screen_y = memory.read_float(screen_y_ptr)
    return success, screen_x, screen_y
end

local function draw_large_message(title, message, duration)
    util.create_thread(function()
        local startPos = 0.2
        local endPos = 2
        local stayDuration = 90
        local slideDuration = duration - stayDuration
        local increment = (endPos - startPos) / slideDuration

        for i = 0, duration do
            local m_scaleForm = GRAPHICS.REQUEST_SCALEFORM_MOVIE("MP_BIG_MESSAGE_FREEMODE")
            if GRAPHICS.HAS_SCALEFORM_MOVIE_LOADED(m_scaleForm) then
                GRAPHICS.BEGIN_SCALEFORM_MOVIE_METHOD(m_scaleForm, "OVERRIDE_Y_POSITION")
                GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_FLOAT(startPos)
                GRAPHICS.END_SCALEFORM_MOVIE_METHOD()

                if i > stayDuration then
                    startPos = startPos + increment
                end

                GRAPHICS.BEGIN_SCALEFORM_MOVIE_METHOD(m_scaleForm, "SHOW_CENTERED_MP_MESSAGE_LARGE")
                GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_TEXTURE_NAME_STRING(title)
                GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_TEXTURE_NAME_STRING(message)
                GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_INT(100)
                GRAPHICS.SCALEFORM_MOVIE_METHOD_ADD_PARAM_BOOL(true)
                GRAPHICS.END_SCALEFORM_MOVIE_METHOD()
                
                GRAPHICS.DRAW_SCALEFORM_MOVIE_FULLSCREEN(m_scaleForm, 255, 255, 255, 0, 0)
            end
            util.yield()
        end
    end)
end

local function get_rating_text(score)
    if score >= 5000000 then
        return "DRIFT KING!", {r = 0.8, g = 0, b = 0.8, a = 1.0}
    elseif score >= 2000000 then
        return "Unbelievable!", {r = 1.0, g = 0, b = 0, a = 1.0}
    elseif score >= 1000000 then
        return "Fantastic!", {r = 1.0, g = 0.5, b = 0, a = 1.0}
    elseif score >= 500000 then
        return "Amazing!", {r = 1.0, g = 1.0, b = 0, a = 1.0}
    elseif score >= 250000 then
        return "Awesome!", {r = 0.0, g = 1.0, b = 0.0, a = 1.0}
    elseif score >= 100000 then
        return "Great!", {r = 0.0, g = 0.0, b = 1.0, a = 1.0}
    elseif score >= 50000 then
        return "Good!", {r = 0.0, g = 1.0, b = 1.0, a = 1.0}
    elseif score >= 10000 then
        return "Nice!", {r = 1.0, g = 0.5, b = 0, a = 1.0}
    else
        return "", {r = 1.0, g = 1.0, b = 1.0, a = 1.0}
    end
end

local function get_vehicle_name(vehicle)
    local hash = ENTITY.GET_ENTITY_MODEL(vehicle)
    return VEHICLE.GET_DISPLAY_NAME_FROM_VEHICLE_MODEL(hash)
end

local function get_player_name(player)
    return PLAYER.GET_PLAYER_NAME(player)
end

local function update_drift_score(player)
    local ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(player)
    if PED.IS_PED_IN_ANY_VEHICLE(ped, false) then
        local vehicle = PED.GET_VEHICLE_PED_IS_IN(ped, false)
        local drift_score = drift_scores[player] or 0
        local last_drift_time = last_drift_times[player] or util.current_time_millis()

        local drift_angle, dot_product, drift_direction = get_drift_direction(vehicle)
        local speed = ENTITY.GET_ENTITY_SPEED_VECTOR(vehicle, true).y

        if drift_angle > 15 and dot_product > 0 and speed > 4 then
            drift_score = drift_score + 100
            last_drift_time = util.current_time_millis()
        end

        if util.current_time_millis() - last_drift_time > 1500 then
            if drift_score > 0 then
                local vehicle_name = get_vehicle_name(vehicle)
                local player_name = get_player_name(player)
                if not player_scores[player_name] then
                    player_scores[player_name] = {}
                end
                if not player_scores[player_name][vehicle_name] then
                    player_scores[player_name][vehicle_name] = 0
                end
                local high_score = player_scores[player_name][vehicle_name]
                if drift_score > high_score then
                    player_scores[player_name][vehicle_name] = drift_score
                    save_scores(player_scores_file, player_scores)
                end
                if player == PLAYER.PLAYER_ID() then
                    local message = (drift_score > high_score) and ("New Record: " .. drift_score) or ("Drift Score: " .. drift_score .. " (High Score: " .. high_score .. ")")
                    draw_large_message("Drift Ended", message .. " - Car: " .. vehicle_name, 300)
                end
                drift_score = 0
            end
        end

        drift_scores[player] = drift_score
        last_drift_times[player] = last_drift_time
    end
end

util.create_tick_handler(function()
    if not drift_mode_enabled then return end

    local player_ped = PLAYER.PLAYER_PED_ID()
    if PED.IS_PED_IN_ANY_VEHICLE(player_ped, false) then
        local vehicle = PED.GET_VEHICLE_PED_IS_IN(player_ped, false)

        local drift_angle, dot_product, drift_direction = get_drift_direction(vehicle)
        local speed = ENTITY.GET_ENTITY_SPEED_VECTOR(vehicle, true).y

        if drift_angle > 15 and dot_product > 0 and speed > 1 then
            local_drift_score = local_drift_score + 100
            local_last_drift_time = util.current_time_millis()
        end

        if util.current_time_millis() - local_last_drift_time > 1500 then
            if local_drift_score > 0 then
                local vehicle_name = get_vehicle_name(vehicle)
                local player_name = get_player_name(PLAYER.PLAYER_ID())
                if not player_scores[player_name] then
                    player_scores[player_name] = {}
                end
                if not player_scores[player_name][vehicle_name] then
                    player_scores[player_name][vehicle_name] = 0
                end
                local high_score = player_scores[player_name][vehicle_name]
                if local_drift_score > high_score then
                    player_scores[player_name][vehicle_name] = local_drift_score
                    save_scores(player_scores_file, player_scores)
                end
                local message = (local_drift_score > high_score) and ("New Record: " .. local_drift_score) or ("Drift Score: " .. local_drift_score .. " (High Score: " .. high_score .. ")")
                draw_large_message("Drift Ended", message .. " - Car: " .. vehicle_name, 300)
                local_drift_score = 0
            end
        end
    else
        local_drift_score = 0
    end

    if show_other_players_scores then
        local players = players.list(false, true, true)

        for _, player in ipairs(players) do
            if player ~= PLAYER.PLAYER_ID() then
                local player_pos = ENTITY.GET_ENTITY_COORDS(PLAYER.PLAYER_PED_ID())
                local other_ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(player)
                local other_pos = ENTITY.GET_ENTITY_COORDS(other_ped)
                local distance = MISC.GET_DISTANCE_BETWEEN_COORDS(player_pos.x, player_pos.y, player_pos.z, other_pos.x, other_pos.y, other_pos.z, true)

                if distance <= proximity_threshold then
                    update_drift_score(player)
                end
            end
        end
    end

    util.yield()
end)

util.create_tick_handler(function()
    if not drift_mode_enabled then return end

    local player_ped = PLAYER.PLAYER_PED_ID()
    if PED.IS_PED_IN_ANY_VEHICLE(player_ped, false) then
        local vehicle = PED.GET_VEHICLE_PED_IS_IN(player_ped, false)
        
        local vehicle_pos = ENTITY.GET_ENTITY_COORDS(vehicle)
        local vehicle_heading = ENTITY.GET_ENTITY_HEADING(vehicle)
        
        local _, _, drift_direction = get_drift_direction(vehicle)
        
        local text_offset_x = offset_x
        local text_offset_y = offset_y
        if drift_direction == "right" then
            text_offset_x = text_offset_x - 1.0
        else
            text_offset_x = text_offset_x + 1.0
        end
        
        local text_pos_x = vehicle_pos.x + text_offset_x * math.cos(math.rad(vehicle_heading)) - text_offset_y * math.sin(math.rad(vehicle_heading))
        local text_pos_y = vehicle_pos.y + text_offset_x * math.sin(math.rad(vehicle_heading)) + text_offset_y * math.cos(math.rad(vehicle_heading))
        local text_pos_z = vehicle_pos.z + offset_z
        
        local success, screen_x, screen_y = world_to_screen(text_pos_x, text_pos_y, text_pos_z)
        
        if success and local_drift_score > 0 then
            local score_text = "x" .. math.floor(local_drift_score)
            local rating_text, rating_color = get_rating_text(local_drift_score)
            
            local shadow_offsets = {{0.001, 0}, {-0.001, 0}, {0, 0.001}, {0, -0.001}}
            for _, offset in ipairs(shadow_offsets) do
                draw_text(screen_x + offset[1], screen_y + offset[2], score_text, 0.8, {r = 0, g = 0, b = 0, a = 1.0}, 4)
            end
            draw_text(screen_x, screen_y, score_text, 0.8, {r = 1.0, g = 1.0, b = 1.0, a = 1.0}, 4)
            draw_text(screen_x, screen_y + 0.05, rating_text, 0.6, rating_color, 4)
        end
    end

    if show_other_players_scores then
        local players = players.list(false, true, true)

        for _, player in ipairs(players) do
            if player ~= PLAYER.PLAYER_ID() then
                local ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(player)
                if PED.IS_PED_IN_ANY_VEHICLE(ped, false) then
                    local player_pos = ENTITY.GET_ENTITY_COORDS(PLAYER.PLAYER_PED_ID())
                    local other_pos = ENTITY.GET_ENTITY_COORDS(ped)
                    local distance = MISC.GET_DISTANCE_BETWEEN_COORDS(player_pos.x, player_pos.y, player_pos.z, other_pos.x, other_pos.y, other_pos.z, true)
                    
                    if distance <= proximity_threshold then
                        local vehicle = PED.GET_VEHICLE_PED_IS_IN(ped, false)
                        
                        local vehicle_pos = ENTITY.GET_ENTITY_COORDS(vehicle)
                        local vehicle_heading = ENTITY.GET_ENTITY_HEADING(vehicle)
                        
                        local _, _, drift_direction = get_drift_direction(vehicle)
                        
                        local text_offset_x = offset_x
                        local text_offset_y = offset_y
                        if drift_direction == "right" then
                            text_offset_x = text_offset_x - 1.0
                        else
                            text_offset_x = text_offset_x + 1.0
                        end
                        
                        local text_pos_x = vehicle_pos.x + text_offset_x * math.cos(math.rad(vehicle_heading)) - text_offset_y * math.sin(math.rad(vehicle_heading))
                        local text_pos_y = vehicle_pos.y + text_offset_x * math.sin(math.rad(vehicle_heading)) + text_offset_y * math.cos(math.rad(vehicle_heading))
                        local text_pos_z = vehicle_pos.z + offset_z
                        
                        local success, screen_x, screen_y = world_to_screen(text_pos_x, text_pos_y, text_pos_z)
                        
                        if success and drift_scores[player] > 0 then
                            local drift_score = drift_scores[player] or 0
                            local score_text = "x" .. math.floor(drift_score)
                            local rating_text, rating_color = get_rating_text(drift_score)

                            local scale = 0.05 / (distance / proximity_threshold)
                            if scale < 0.3 then
                                scale = 0.3
                            elseif scale > 0.6 then
                                scale = 0.6
                        end

                            if show_distance then
                                score_text = score_text .. " (" .. math.floor(distance) .. "m)"
                            end

                            local shadow_offsets = {{0.001, 0}, {-0.001, 0}, {0, 0.001}, {0, -0.001}}
                            for _, offset in ipairs(shadow_offsets) do
                                draw_text(screen_x + offset[1], screen_y + offset[2], score_text, scale, {r = 0, g = 0, b = 0, a = 1.0}, 4)
                            end
                            draw_text(screen_x, screen_y, score_text, scale, {r = 1.0, g = 1.0, b = 1.0, a = 1.0}, 4)
                            draw_text(screen_x, screen_y + 0.05 * scale, rating_text, scale * 0.6, rating_color, 4)
                        end
                    end
                end
            end
        end
    end
end)

local function reset_drift_score()
    local_drift_score = 0
end

local function toggle_drift_mode(state)
    drift_mode_enabled = state
    if state then
        util.log("Drift mode enabled")
        util.toast("Drift mode enabled")
        menu.trigger_commands("driftmode on")
    else
        util.log("Drift mode disabled")
        util.toast("Drift mode disabled")
        menu.trigger_commands("driftmode off")
    end
end

menu.slider(menu.my_root(), "Proximity Threshold", {"proximitythreshold"}, "Adjust the proximity threshold for displaying and updating drift scores.", 10, 1000, 500, 10, function(value)
    proximity_threshold = value
end)
menu.toggle(menu.my_root(), "Show Distance", {"showdistance"}, "Toggle displaying the distance next to the drift score for debugging.", function(value)
    show_distance = value
end, false)
menu.toggle(menu.my_root(), "Show Other Players Scores And Save Them To PlayerScores folder", {"showotherscores"}, "Toggle displaying the drift scores for other players.", function(value)
    show_other_players_scores = value
end, true)
menu.toggle(menu.my_root(), "Enable Drift Mode", {"driftmode"}, "Toggle drift mode on or off.", function(state)
    toggle_drift_mode(state)
end, false)
menu.action(menu.my_root(), "Reset Drift Score", {}, "Resets the drift score to zero.", function()
    reset_drift_score()
end)

menu.divider(menu.my_root(), "Drift Mod")
menu.divider(menu.my_root(), "Instructions")
menu.action(menu.my_root(), "How to Use :)", {}, "1. Enable drift mode using the toggle.\n2. Start drifting with your vehicle.\n3. Your drift score will be displayed above the vehicle if it's greater than zero.\n4. Adjust the proximity threshold using the slider.\n5. Toggle display options as needed.\n6. Drift scores are saved and displayed for nearby players within the specified proximity.", function() end)
