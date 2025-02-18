local msg = require 'mp.msg'
local utils = require 'mp.utils'

local function sub_path()
    local file_path = mp.get_property("path", "")

    --返回当前文件夹下字幕文件夹路径
    local dirname = utils.split_path(file_path) or ""
    local subdirs = utils.readdir(dirname, "dirs") or {}
    for _, v in ipairs(subdirs) do
        if v:lower():match("sub") then
            return utils.join_path(dirname, v)
        end
    end

    --返回父级文件夹下字幕文件夹路径
    local pdir, sdir = dirname:match("(.+[\\/])(.+[\\/])")
    subdirs = utils.readdir(pdir or "", "dirs") or {}
    for _, v in ipairs(subdirs) do
        if v:lower():match("sub") then
            return utils.join_path(pdir..v, sdir)
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



--[[
    local subfiles = utils.readdir(dirname, "files")
    if subfiles==nil then return end
    local subname = filename:match("(.+)%.%w+$"):gsub("%p", "%%".."%1")

    for _,v in ipairs(subfiles) do
        if v:match(subname) then
            mp.commandv("sub-add", dirname..v, "cached")
        end
    end
end
]]--
--mp.add_hook("on_preloaded", 50, load_subs)
