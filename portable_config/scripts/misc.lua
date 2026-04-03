---------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------
mp.add_key_binding("e", "open-in-explorer", function()
    local path = mp.get_property("path")
    if require 'mp.utils'.file_info(path or "") then
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
---------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------
mp.add_key_binding("/", "picture-in-picture", function()
    local list = {fullscreen=false, border=false, ontop=true, geometry="20%x20%-50-50"}
    if mp.get_property_native("geometry")==list.geometry then
        for k, v in pairs(list) do
            mp.set_property_native(k, mp.get_property_native("user-data/pip/"..k))
        end
    else
        for k, v in pairs(list) do
            local t = mp.get_property_native(k)
            if k=="geometry" and t=="" then t="50%:50%" end
            mp.set_property_native("user-data/pip/"..k, t)
            mp.set_property_native(k, v)
        end
    end
end)
----------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------
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
