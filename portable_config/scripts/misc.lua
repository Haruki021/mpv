local utils = require 'mp.utils'
---------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------
mp.add_key_binding("e", "open-in-explorer", function()
    local path = mp.get_property("path")
    if utils.file_info(path or "") then
        mp.command_native({
            name = "subprocess",
            playback_only = false,
            detach = true,
            args = { 'explorer', '/select,', path},
        })
    else
        mp.osd_message("No valid path found.", 3)
    end
end)
---------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------
mp.observe_property("window-minimized", "bool", function(name, value)
    if not mp.get_property_bool("current-tracks/video/image", true) then
        mp.set_property_bool("pause", value)
    end
end)

mp.observe_property("current-tracks/video", "native", function(name, value)
    if value and value.image and not value.albumart and mp.get_property("geometry")=="" then
        mp.set_property("geometry", "88%x88%+50%+50%")
        mp.set_property("osc", "no")
        mp.input_enable_section("section", "allow-hide-cursor")
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
