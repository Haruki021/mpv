local msg = require 'mp.msg'
local utils = require 'mp.utils'

function main()
    local pl_count = mp.get_property_number("playlist-count", 2)
    if pl_count>1 then return end

    local path, ext = mp.get_property("path", ""):match("[\\\\%?\\]*(.+%.([^%.]+))$") --windows下长路径前缀
    if not path or not ext then return end

    local dir, filename = utils.split_path(path)
    local files = utils.readdir(dir, "files")
    if #dir==0 or files==nil or #files<=1 then return end

    local exts = exts.filter(ext)
    if not exts then return end
    table.filter(files, exts, filterfunction)
    if #files<=1 then return end

    table.sort(files, sortfunction)
    msg.info("Loading "..#files.." files.")
    Load(dir, filename, files)
end

function exts.filter(k)
    for _,v in ipairs({"video-exts","image-exts","audio-exts","archive-exts","playlist-exts"}) do
        if mp.get_property(v):match(k) then return v end
    end
end

function table.filter(t, f, iter)
    for i=#t, 1, -1 do
        if not iter(t[i], f) then table.remove(t, i) end
    end
end

function filterfunction(v, f)
    local ext = v:lower():match("%.([^%.]+)$")
    return f:match(ext)
end

--按文件名排序，数字部分使用位数+原数字替换
function sortfunction(a, b)
  local function padnum(d)
    local n, dec = string.match(d, "0*(%d+)(%.?)")
    return #dec>0 and ("%03d%d."):format(#n, n) or ("%03d%d%%"):format(#n, n)
  end
  return tostring(a):lower():gsub("%d+%.?",padnum)..("%3d"):format(#b)
       < tostring(b):lower():gsub("%d+%.?",padnum)..("%3d"):format(#a)
end

function Load(dir, filename, files)
    local current
    for i = 1, #files do
        if files[i] == filename then current = i break end
    end
    if current == nil then return end

    for i = 1, current-1 do
        mp.commandv("loadfile", dir..files[i], "insert-at", i-1) --mp.commandv("loadfile", filename, "append")
        --mp.commandv("playlist-move", i, i-1) --Move the playlist entry at index1, so that it takes the place of the entry index2.
    end

    for i = current+1, #files do
        mp.commandv("loadfile", dir..files[i], "append") --mp.commandv("loadfile", filename, "append")
    end
end

mp.register_event("start-file", main)
