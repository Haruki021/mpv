local msg = require 'mp.msg'
local utils = require 'mp.utils'

local resume_data_path = mp.command_native({"expand-path", "~~/cache/resume.jsonl"})
local data = {}

--加载已保存的播放进度
local function load_resume_data()
    local f = io.open(resume_data_path, "r")
    if not f then return {} end
    local content = f:read()
    f:close()
    return utils.parse_json(content or "") or {}
end

--保存播放进度到文件
local function save_resume_data()
    if not data.path then return end
    local f = io.open(resume_data_path, "w")
    f:write(utils.format_json(data), "\n")
    f:close()
end

--恢复已保存的播放进度
local function resume_playback()
    if not mp.get_property_bool("idle-active") then return end

    local data = load_resume_data()
    if not utils.file_info(data.path or "") and not data.path:match("..+://") then
        mp.osd_message("No valid records found.", 3)
        return
    end

    --mp.commandv("loadfile", data.path, "replace", 1, "start="..data.time)
    mp.commandv("loadfile", data.path)
    local function init_handler()
        if data.time then mp.commandv("seek", data.time, "absolute") end
        mp.unregister_event(init_handler)
    end
    mp.register_event("file-loaded", init_handler)
end

-- Using hook, as at the "end-file" event the playback position info is already unset.
mp.add_hook("on_unload", 50, function()
    data.path = mp.get_property("path", "")
    if mp.get_property_bool("seekable") then data.time = mp.get_property_number("time-pos", 0) end
    if data.path:match("..+://") then data.path = mp.get_property('playlist-path', data.path) end
end)

mp.register_event("shutdown", save_resume_data)
mp.add_key_binding("w", "resume_playback", resume_playback)

