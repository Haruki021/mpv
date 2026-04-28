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

-- 生成的ASS文件保存路径（MPV缓存目录）
local ass_path = mp.command_native({"expand-path", "~~/cache/danmaku.ass"})

-- UTF8字符串长度计算（半角=1，全角=2）
local function utf8_len(s)
    local len, char = 0, {string.byte(s, 1, -1)}
    for i = 1, #char do
        if char[i] >= 0xC0 then len = len + 2 end
        if char[i] <= 0x7F then len = len + 1 end
    end
    return len
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

-- B站颜色转ASS颜色（RRGGBB → BBGGRR）
local function convert_bili_color_to_ass(color)
    color = tonumber(color) or 0xFFFFFF
    local hex = string.format("%06X", color)
    return string.format("&H%s%s%s", hex:sub(5,6), hex:sub(3,4), hex:sub(1,2))
end

-- XML转义字符还原（&lt; → < 等）
local function xml_unescape(s)
    return s:gsub("&(lt|gt|quot|apos|amp);", {lt="<",gt=">",quot='"',apos="'",amp="&"})
            :gsub("[{}]", "\\%0")
end

-- 解析B站弹幕属性（官方标准格式）
local function parse_danmaku_attr(attr_str)
    local attrs = {start = 0, mode = 1, fs = 40, color = 0xFFFFFF, duration = 3}
    local parts = {}
    for p in attr_str:gmatch("[^,]+") do table.insert(parts, p) end

    attrs.start = tonumber(parts[1]) or 0
    attrs.mode = tonumber(parts[2]) or 1
    attrs.fs = math.min((tonumber(parts[3]) or 25)*2, 40)
    attrs.color = tonumber(parts[4]) or 0xFFFFFF
    return attrs
end

-- 正则解析XML弹幕数据
local function parse_xml_danmaku(xml_content)
    local danmaku = {}
    for p_attr, text in string.gmatch(xml_content, '<d%s+p="([^"]*)"[^>]*>%s*(.-)%s*</d>') do
        table.insert(danmaku, {attrs=parse_danmaku_attr(p_attr), text=xml_unescape(text)})
    end
    return danmaku
end

-- 弹幕轨道管理：防止弹幕重叠，自动分配轨道
local tracks = {}
local function alloc_track(start, duration, max_tracks)
    local best_track, min_time = 1, math.huge
    for i = 1, max_tracks do
        if not tracks[i] or tracks[i] <= start then best_track=i break end
        if tracks[i] < min_time then min_time=tracks[i] best_track=i end
    end
    tracks[best_track] = start+duration
    return best_track-1
end

-- 生成滚动弹幕移动动画（从右向左滑动）
local function generate_move_effect(danmaku, fps)
    local text_len = utf8_len(danmaku.text)
    local text_width = text_len*danmaku.attrs.fs*0.45
    local speed  = fps<60 and 4*fps or 2*fps
    local move_duration = (1920+text_width)/(speed+math.random(text_len))

    local track_height = danmaku.attrs.fs+2
    local max_tracks = math.floor(810/track_height)
    local track = alloc_track(danmaku.attrs.start, move_duration, max_tracks)
    local y_pos = track*track_height

    return {string.format("\\move(1920,%d,-%d,%d)", y_pos, text_width, y_pos)}, move_duration
end

-- 弹幕行转换为ASS字幕
local function danmaku_to_ass(danmaku, fps)
    local color = convert_bili_color_to_ass(danmaku.attrs.color)
    local style = "Default"
    local effect = {}

    if danmaku.attrs.mode == 5 then
        style = "Top"
    elseif danmaku.attrs.mode == 4 then
        style = "Bottom"
    else
        effect, danmaku.attrs.duration = generate_move_effect(danmaku, fps)
    end

    if color ~= "&HFFFFFF" then table.insert(effect, 1,"\\1c"..color ) end
    if danmaku.attrs.fs ~= 40 then table.insert(effect, 1, "\\fs"..danmaku.attrs.fs) end
    effect = next(effect) and "{" .. table.concat(effect) .. "}" or ""

    return string.format("Dialogue: 0,%s,%s,%s,,0,0,0,,%s%s",
        sec_to_ass_time(danmaku.attrs.start),
        sec_to_ass_time(danmaku.attrs.start+danmaku.attrs.duration),
        style, effect, danmaku.text)
end

-- 获取B站弹幕URL、视频帧率
local function danmaku_info()
    local result = mp.get_property_native("user-data/mpv/ytdl/json-subprocess-result") or {}
    local data = require 'mp.utils'.parse_json(result.stdout or "") or {}
    return {
        url = ((data.requested_subtitles or {}).danmaku or {}).url,
        fps = data.fps or 30
    }
end

local function process_danmaku(data)
    if not data.url then return false end
    local userAgent = mp.get_property("file-local-options/user-agent", "")
    local res = mp.command_native({
        name = "subprocess", capture_stdout = true, capture_stderr = true,
        args = {"curl", "-fs", data.url, "-A", userAgent, "--compressed"}})

    if not res.stdout or res.stderr ~= "" then return false end

    local danmaku = parse_xml_danmaku(res.stdout)
    local ass_content = {ASS_HEADER}
    tracks = {}

    table.sort(danmaku, function(a, b)
        return a.attrs.start < b.attrs.start
    end)

    for _, dm in ipairs(danmaku) do
        table.insert(ass_content, danmaku_to_ass(dm, data.fps))
    end

    local ass_file = io.open(ass_path, "w")
    if not ass_file then return end
    ass_file:write(table.concat(ass_content, "\n"))
    ass_file:close()

    mp.commandv("sub-remove", 1)
    mp.set_property("secondary-sub-ass-override", "scale")
    mp.commandv("sub-add", ass_path, "auto")
    mp.set_property_number("secondary-sid", 1)
    mp.msg.info("Total "..#danmaku.." danmakus loaded.")
    return data.fps < 60 and 2*data.fps
end

-- 帧率滤镜控制（优化弹幕流畅度）
local function danmaku_vfilter(status, filter)
    if status then
        mp.commandv("vf", "add", ("@danmaku:lavfi=[fps=fps=%d:round=down]"):format(status))
    end
    if not status and filter then
        mp.commandv("vf", "remove", "@danmaku")
        mp.remove_key_binding("@danmaku")
    end
    if status and not filter then
        mp.add_key_binding("Ctrl+d", "@danmaku", function()
            mp.commandv("vf", "toggle", "@danmaku")
        end)
    end
end

mp.add_hook("on_preloaded", 50, function()
    local status = process_danmaku(danmaku_info())
    local filter = mp.get_property("vf", ""):match("@danmaku")
    danmaku_vfilter(status, filter)
end)
