local msg = require 'mp.msg'
local utils = require 'mp.utils'

local range = mp.get_property("video-exts")

local function sub_path()
    local file_path = mp.get_property("path", "")
    if not range:find(file_path:match("%.(%w+)$")) then return end

    local dirname, filename = utils.split_path(file_path)
    local pdir, sdir = dirname:match("(.+[\\/])(.+[\\/])")
    if not pdir then return end
    local subdirs = utils.readdir(pdir, "dirs")

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
