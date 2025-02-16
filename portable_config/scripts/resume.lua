local msg = require 'mp.msg'
local utils = require 'mp.utils'

local resume_data_path = mp.command_native({"expand-path", "~~/cache/resume.json"})
local data = {}

--加载已保存的播放进度
local function load_resume_data()
    local f = assert(io.open(resume_data_path, "r"))
    local content = f:read("*a")
    f:close()
    return utils.parse_json(content) or {}
end

--保存压缩包浏览记录
local function archive_resume_data()
    if data.path:match("archive://") then
        data.pos = data.path
        data.path = data.path:match("archive://(.+)|/")
    end
end

--跳转压缩包浏览位置
local function archive_reposition(data)
    local current_pos = mp.get_property_number("playlist-current-pos")
    while mp.get_property("playlist/"..current_pos.."/filename")~=data.pos do
        current_pos = current_pos+1
    end
    mp.set_property("playlist-pos", current_pos)
end

--保存播放进度到文件
local function save_resume_data()
    if not data.path or not data.path:match("%.%w+$") then return end
    archive_resume_data()
    local f = assert(io.open(resume_data_path, "w"))
    f:write(utils.format_json(data))
    f:close()
end

--恢复已保存的播放进度
local function resume_playback()
    if not mp.get_property_bool("idle-active") then return end

    local data = load_resume_data()
    if not utils.file_info(data.path) then
        mp.osd_message("Invalid: No watched record !")
        return
    end

    --mp.commandv("loadfile", data.file_path, "replace", 1, "start="..data.time_pos)
    mp.commandv("loadfile", data.path)
    local function init_handler()
        if data.pos then
            archive_reposition(data)
        else
            mp.commandv("seek", data.time, "absolute")
        end
        mp.unregister_event(init_handler)
    end
    mp.register_event("file-loaded", init_handler)
end


-- Using hook, as at the "end-file" event the playback position info is already unset.
mp.add_hook("on_unload", 50, function()
    data.path = mp.get_property("path", "")
    if mp.get_property_bool("seekable") then data.time = mp.get_property_number("time-pos", 0) end
end)

mp.register_event("shutdown", save_resume_data)
mp.add_key_binding("w", "resume_playback", resume_playback)
