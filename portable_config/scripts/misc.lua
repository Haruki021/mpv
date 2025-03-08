local msg = require 'mp.msg'
local utils = require 'mp.utils'

mp.add_key_binding("e", "open-in-explorer", function()
    local path = mp.get_property("path", ""):match("[\\\\%?\\]*(.+)") --windows下长路径前缀
    if path and utils.file_info(path)["is_file"] then
        path = string.gsub(path, "/", "\\")
        mp.command_native({
            name = "subprocess",
            playback_only = false,
            detach = true,
            args = { 'explorer', '/select,',  path .. ' ' },
        })
    else
        mp.osd_message("Invalid: " ..(path or "No valid path found."), 3)
    end
end)

---------------------------------------------------------------------------------------------

--[[-----------------------------------------------------------------------------------------
mp.add_forced_key_binding("KP2", "playlist-prev-playlist", function()
    local current_path = mp.get_property("playlist-path")
    local current_pos = mp.get_property_number("playlist-pos")
    local count = 0
    if not current_path then mp.command("playlist-prev") return end

    while(true) do
        if count==2 then break end
        if current_pos==0 then current_pos=-1 break end
        current_pos = current_pos-1
        if mp.get_property("playlist/"..current_pos.."/playlist-path") ~= current_path then
            current_path = mp.get_property("playlist/"..current_pos.."/playlist-path")
            count = count+1
        end
    end
    mp.commandv("set", "playlist-pos", current_pos+1)
end)
]]--
--------------------------------------------------------------------------------------------
-- This script pauses playback when minimizing the window, and resumes playback
-- if it's brought back again. If the player was already paused when minimizing,
-- then try not to mess with the pause state.

mp.observe_property("window-minimized", "bool", function(name, value)
    if value and not mp.get_property_bool("current-tracks/video/image") then
        mp.set_property_bool("pause", true)
    elseif not value and not mp.get_property_bool("current-tracks/video/image") then
        mp.set_property_bool("pause", false)
    end
end)


mp.observe_property("current-tracks/video/image", "bool", function(name, value)
    if value and not mp.get_property_bool("current-tracks/video/albumart") and mp.get_property("geometry")=="" then
        mp.commandv("set", "geometry", "88%x88%+50%+50%")
    end
end)
---------------------------------------------------------------------------------------------

--[[
-- the coroutine will yield after the clickdown event and resume after the clickup event
local main = coroutine.wrap(function()
    while true do
        local time = mp.get_time()
        coroutine.yield()

        if (mp.get_time() - time) < 0.1 then
            mp.set_property_bool('pause', not mp.get_property_bool('pause'))
        end

        -- wait until the next mousedown event
        coroutine.yield()
    end
end)

-- complex ensures the main function will be called for separate click down/up events
mp.add_forced_key_binding("MBTN_LEFT", "pause-or-drag", main, {complex = true})
---]]
