local data = {}

local function pip()
    if not data.pip then
        --保存当前状态
        data.fulllscreen = mp.get_property_bool("fullscreen")
        mp.command("no-osd set geometry 20%x20%-5%+5%; no-osd set title-bar no; no-osd set ontop yes")
        if data.fulllscreen then
            --先调整窗口然后退出全屏
            mp.add_timeout(0.08, function()
                mp.command("set fullscreen no")
        end)
        end
        data.pip = true
    else
        if data.fulllscreen then
            --如果原始状态全屏则恢复全屏
            mp.command("set fullscreen yes")
        end
        mp.add_timeout(0.08, function()
            mp.command("no-osd set geometry 50%:50%; no-osd set title-bar yes; no-osd set ontop no")
        end)
        data.pip = false
    end
end

mp.add_key_binding("/", "picture-in-picture", pip)
