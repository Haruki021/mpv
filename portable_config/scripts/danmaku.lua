-- B站XML弹幕转ASS格式
local ASS_HEADER = [[[Script Info]
Title: Bilibili Danmaku to ASS
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080
WrapStyle: 0
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Microsoft YaHei,40,&H33FFFFFF,&H000000FF,&H33000000,&H00000000,0,0,0,0,100,100,0,0,1,1,0,7,0,0,0,1
Style: Top,Microsoft YaHei,40,&H33FFFFFF,&H000000FF,&H33000000,&H00000000,0,0,0,0,100,100,0,0,1,1,0,8,0,0,0,1
Style: Bottom,Microsoft YaHei,40,&H33FFFFFF,&H00000000,&H33000000,&H00000000,0,0,0,0,100,100,0,0,1,1,0,2,0,0,0,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
]]

-- ASS文件保存路径（MPV缓存目录）
local ass_path = mp.command_native({"expand-path", "~~/cache/danmaku.ass"})
local utils = require 'mp.utils'
local input = require 'mp.input'

-- XML转义字符还原（&lt; → < 等）
local function xml_unescape(s)
    return s:gsub("&(.-);", {lt="<",gt=">",quot='"',apos="'",amp="&"})
            :gsub("[{}]", "\\%0")
end

-- 解析B站弹幕属性（官方标准格式）
local function parse_danmaku_attr(attr_str)
    local attrs = {start=0, mode=1, fs=40, color=0xFFFFFF, dur=3}
    local parts = {}
    for p in attr_str:gmatch("[^,]+") do parts[#parts+1] = p end

    attrs.start = tonumber(parts[1]) or 0
    attrs.mode = tonumber(parts[2]) or 1
    attrs.fs = math.min((tonumber(parts[3]) or 25)*2, 40)
    attrs.color = tonumber(parts[4]) or 0xFFFFFF
    return attrs
end

-- 正则解析XML弹幕数据
local function parse_xml_danmaku(xml_content)
    local danmaku = {}
    for p_attr, text in xml_content:gmatch('<d%s+p="([^"]*)".->%s*(.-)%s*</d>') do
        danmaku[#danmaku+1] = {attrs=parse_danmaku_attr(p_attr), text=xml_unescape(text)}
    end
    return danmaku
end

-- UTF8字符串长度计算（半角=1，全角=2）
local function utf8_len(s)
    local len, char = 0, {string.byte(s, 1, -1)}
    for i = 1, #char do
        if char[i] >= 0xC0 then len = len + 2
        elseif char[i] <= 0x7F then len = len + 1 end
    end
    return len
end

-- 弹幕轨道管理：防止弹幕重叠，自动分配轨道
local function alloc_track(dm, lim, dt, tracks)
    local sel, tmp, min = nil, 1, math.huge
    for i = 1, lim do
        if not tracks[i] or tracks[i][1] <= dm.attrs.start then sel=i break end
        if not sel and tracks[i][2] <= dm.attrs.start-dt then sel=i break end
        if tracks[i][1] < min then min=tracks[i][1] tmp=i end
    end
    tracks[sel or tmp] = {dm.attrs.start+dm.attrs.dur, dm.attrs.start+dt}
    return (sel or tmp)-1
end

-- 生成滚动弹幕移动动画（从右向左滑动）
local function generate_move_effect(dm, fps, tracks)
    local width = utf8_len(dm.text)*dm.attrs.fs/2
    local speed  = fps<60 and 4*fps or 2*fps
    dm.attrs.dur = (1920 + width)/speed

    local dt = width/speed
    local dh = dm.attrs.fs+1
    local lim = math.floor(810/dh)
    local track = alloc_track(dm, lim, dt, tracks)
    local y_pos = track*dh
    return string.format("\\move(1920,%d,-%d,%d)", y_pos, width, y_pos)
end

-- B站颜色转ASS颜色（RRGGBB → BBGGRR）
local function convert_bili_color_to_ass(color)
    color = tonumber(color) or 0xFFFFFF
    local hex = string.format("%06X", color)
    return string.format("&H%s%s%s&", hex:sub(5,6), hex:sub(3,4), hex:sub(1,2))
end

-- 秒数转ASS时间格式 HH:MM:SS.cc
local function sec_to_ass_time(seconds)
    local total = math.floor(seconds*100)
    local h = math.floor(total/360000)
    local m = math.floor(total/6000)%60
    local s = math.floor(total/100)%60
    local cs = total%100
    return string.format("%02d:%02d:%02d.%02d", h, m, s, cs)
end

-- 弹幕行转换为ASS字幕
local function danmaku_to_ass(dm, fps, tracks)
    local color = convert_bili_color_to_ass(dm.attrs.color)
    local style = "Default"
    local parts = {}

    if dm.attrs.mode == 5 then
        style = "Top"
    elseif dm.attrs.mode == 4 then
        style = "Bottom"
    else
        table.insert(parts, generate_move_effect(dm, fps, tracks))
    end

    if dm.attrs.fs ~= 40 then table.insert(parts, "\\fs"..dm.attrs.fs) end
    if color ~= "&HFFFFFF&" then table.insert(parts, "\\1c"..color) end
    local effect = #parts==0 and "" or "{"..table.concat(parts).."}"

    return string.format("Dialogue: 0,%s,%s,%s,,0,0,0,,%s%s",
        sec_to_ass_time(dm.attrs.start),
        sec_to_ass_time(dm.attrs.start+dm.attrs.dur),
        style, effect, dm.text)
end

-- 解析XML并生成ASS弹幕文件
local function process_danmaku(xml_content, fps)
    local danmaku = parse_xml_danmaku(xml_content)
    if #danmaku==0 then mp.msg.warn("No danmaku parsed.") return false end

    table.sort(danmaku, function(a, b)
        return a.attrs.start < b.attrs.start
    end)

    local ass_content, tracks = {ASS_HEADER}, {}
    for i = 1, #danmaku do
        ass_content[i+1] = danmaku_to_ass(danmaku[i], fps, tracks)
    end

    local ass_file = io.open(ass_path, "w")
    if not ass_file then
        ass_path = os.tmpname()
        ass_file = io.open(ass_path, "w")
    end
    ass_file:write(table.concat(ass_content, "\n"))
    ass_file:close()
    return #danmaku
end

-- 下载XML弹幕原始数据
local function danmaku_fetch(url)
    local res = mp.command_native({
        name = "subprocess", capture_stdout = true, capture_stderr = true,
        args = {"curl", "-fsSL", "-A", "Mozilla/5.0 Chrome", "--compressed", url}})

    if res.status ~= 0 then
        mp.msg.error("Failed to download danmaku: " .. (res.stderr or "unknown error"))
        return false
    end
    return res.stdout
end

-- 获取B站弹幕地址与帧率
local function danmaku_info()
    local result = mp.get_property_native("user-data/mpv/ytdl/json-subprocess-result") or {}
    local data = utils.parse_json(result.stdout or "") or {}
    return {
        url = (((data.subtitles or {}).danmaku or {})[1] or{}).url,
        fps = data.fps or 30
    }
end

-- 帧率滤镜控制（优化弹幕流畅度）
local function danmaku_vfilter(status, fps)
    if status and fps<60 then
        if not mp.get_property("vf", ""):match("@danmaku") then
            mp.add_key_binding("Ctrl+f", "@danmaku", function()
                mp.commandv("vf", "toggle", "@danmaku")
            end)
        end
        mp.commandv("vf", "add", ("@danmaku:lavfi=[fps=%g:round=down]"):format(2*fps))
    else
        if mp.get_property("vf", ""):match("@danmaku") then
            mp.commandv("vf", "remove", "@danmaku")
            mp.remove_key_binding("@danmaku")
        end
    end
end

-- 统一加载流程（下载→解析→加载ASS→滤镜）
local function load_danmaku_from_url(url, fps)
    local xml_content = url and danmaku_fetch(url)
    local cnt = xml_content and process_danmaku(xml_content, fps)
    if cnt then
        mp.commandv("sub-remove", 1)
        mp.commandv("sub-add", ass_path, "auto")
        mp.set_property_number("secondary-sid", 1)
        mp.msg.info(string.format("Total %d danmakus loaded.", cnt))
    end
    danmaku_vfilter(cnt, fps)
    return cnt
end

mp.add_hook("on_preloaded", 50, function()
    local data = danmaku_info()
    load_danmaku_from_url(data.url, data.fps)
end)
-------------------------------------------------------------------------------------------
---以下部分实现加载本地视频弹幕---------------------------------------------------------------
local function danmaku_url(value)
    local bvid = value:match("(BV%w+)")
    if not bvid then
        input.log("无效地址: 请输入包含BV号的链接", "{\\c&H7a77f2&}")
        return
    end
    local api = ("https://api.bilibili.com/x/player/pagelist?bvid=%s"):format(bvid)
    local res = mp.command_native({name = "subprocess",
        capture_stdout = true, capture_stderr = true, playback_only = false,
        args = {"curl", "-fsSL", "-A", "Mozilla/5.0 Chrome", "-e", "https://www.bilibili.com/", api}})
    if res.status==0 then
        local cid = res.stdout:match('"cid":(%d+),')
        local danmaku_url = ('https://comment.bilibili.com/%d.xml'):format(cid)
        mp.osd_message("弹幕正在加载中......")
        return danmaku_url
    end
end

mp.add_key_binding("Ctrl+d", "load-bilibili-danmaku", function()
    input.get({
        prompt = "请输入B站视频链接(含BV号): ",
        keep_open = true,
        default_text = mp.get_property("clipboard/text",""),
        submit = function(value)
            if not value or value=="" then
                input.log("地址不能为空", "{\\c&H7a77f2&}")
                return
            end

            local fps = mp.get_property_number("container-fps", 30)
            local url = danmaku_url(value)
            local cnt = load_danmaku_from_url(url, fps)
            if cnt then mp.osd_message(("%d条弹幕加载成功!"):format(cnt)) end
        end
    })
end)
