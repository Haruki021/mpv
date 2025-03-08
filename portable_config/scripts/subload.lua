local msg = require 'mp.msg'
local utils = require 'mp.utils'

local function sub_path()
    local file_path = mp.get_property("path", "")
    local dir_path = "sub,subs,subtitle,subtitles,字幕"

    --返回当前文件夹下字幕文件夹路径
    local dirname = utils.split_path(file_path)
    local subdirs = utils.readdir(dirname or "", "dirs") or {}
    for _, v in ipairs(subdirs) do
        if dir_path:match(v:lower()) then
            return v
        end
    end

    --返回父级文件夹下字幕文件夹路径
    local pdir, sdir = dirname:match("(.+[\\/])(.+[\\/])")
    subdirs = utils.readdir(pdir or "", "dirs") or {}
    for _, v in ipairs(subdirs) do
        if dir_path:match(v:lower()) then
            return utils.join_path("../"..v, sdir)
        end
    end
end

local function load_subs()
    local path = sub_path()
    if path then mp.set_property("sub-file-paths", path) end
    --mp.commandv("change-list", "sub-file-paths", "set", path)
    mp.unregister_event(load_subs)
end

mp.register_event("start-file", load_subs)
