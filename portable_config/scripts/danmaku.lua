-- B站XML弹幕转ASS格式
local ASS_HEADER = [[[Script Info]
Title: Bilibili Danmaku to ASS
ScriptType: v4.00+
Collisions: Normal
PlayResX: 1920
PlayResY: 1080
Timer: 100.0000
WrapStyle: 2

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

-- UTF8字符串长度计算（中文=1，英文=0.5）
local function utf8_len(s)
    if not s then return 0 end
    local len = 0
    for char in string.gmatch(s, "[%z\1-\127\194-\244][\128-\191]*") do
        len = len + (#char > 1 and 1 or 0.5)
    end
    return len
end

-- 秒数转ASS时间格式 HH:MM:SS.cc
local function sec_to_ass_time(seconds)
    seconds = math.max(0, seconds)
    local total = math.floor(seconds * 100)
    local h = math.floor(total / 360000)
    local m = math.floor(total / 6000) % 60
    local s = math.floor(total / 100) % 60
    local cs = total % 100
    return string.format("%02d:%02d:%02d.%02d", h, m, s, cs)
end

-- B站颜色转ASS颜色（RRGGBB → BBGGRR）
local function convert_bili_color_to_ass(color)
    color = tonumber(color) or 0xFFFFFF
    local hex = string.format("%06X", color)
    return "&H"..hex:sub(5,6)..hex:sub(3,4)..hex:sub(1,2)
end

-- XML转义字符还原 + ASS大括号转义
local function xml_unescape(s)
    return s and s:gsub("&amp;", "&")
                  :gsub("&lt;", "<")
                  :gsub("&gt;", ">")
                  :gsub("&quot;", "\"")
                  :gsub("&apos;", "'")
                  :gsub("[{}]", "\\%1")
end

-- 解析B站弹幕属性（官方标准格式）
local function parse_danmaku_attr(attr_str)
    local attrs = {start_time = 0, mode = 1, font_size = 40, color = 0xFFFFFF, duration = 3}
    if not attr_str then return attrs end
    local parts = {}
    for p in attr_str:gmatch("[^,]+") do table.insert(parts, p) end

    -- 逐字段解析（严格对应B站官方顺序）
    attrs.start_time = tonumber(parts[1]) or 0
    attrs.mode = tonumber(parts[2]) or 1
    attrs.font_size = math.max(tonumber(parts[3]) or 40, 40)  -- 不小于40
    attrs.color = tonumber(parts[4]) or 0xFFFFFF
    attrs.send_time = tonumber(parts[5]) or 0
    attrs.pool_type = tonumber(parts[6]) or 0
    attrs.user_id = parts[7] or ""
    attrs.row_id = parts[8] or ""
    attrs.weight = tonumber(parts[9]) or 0

    return attrs
end

-- 解析XML弹幕数据
local function parse_xml_danmaku(xml_content)
    local danmaku = {}
    local pattern = '<d[^>]+p="([^"]-)"[^>]*>(.-)</d>'
    for p_attr, text in string.gmatch(xml_content, pattern) do
        table.insert(danmaku, {attrs = parse_danmaku_attr(p_attr), text = xml_unescape(text)})
    end
    return danmaku
end

-- 弹幕轨道管理：防止弹幕重叠，自动分配轨道
local track_pool = {}
local function alloc_track(start_time, duration, max_tracks)
    local best_track, min_time = 1, 1/0
    for i = 1, max_tracks do
        if not track_pool[i] or track_pool[i] <= start_time then best_track=i break end
        if track_pool[i] < min_time then min_time=track_pool[i] best_track=i end
    end
    track_pool[best_track] = start_time + duration
    return best_track - 1
end

-- 生成滚动弹幕移动动画
local function generate_move_effect(danmaku_text, attrs, data)
    local text_len = utf8_len(danmaku_text)
    local text_width = text_len*attrs.font_size*0.88
    local speed = data.fps*(data.width+4*text_width)*2.8
    local move_duration = data.width*(data.width+8*text_width)/speed

    local track_height = attrs.font_size + 2
    local max_tracks = math.min(math.floor(data.height/track_height), 20)
    local track = alloc_track(attrs.start_time, move_duration, max_tracks)
    local y_pos = track * track_height
    
    return {string.format("\\move(1920,%d,-%d,%d)", y_pos, text_width, y_pos)}, move_duration
end

local function danmaku_to_ass(danmaku_text, attrs, data)
    if not danmaku_text then return "" end
    local color = convert_bili_color_to_ass(attrs.color)
    local style = "Default"
    local effect = {}

    if attrs.mode == 5 then
        style = "Top"
    elseif attrs.mode == 4 then
        style = "Bottom"
    else
        effect, attrs.duration = generate_move_effect(danmaku_text, attrs, data)
    end

    if color ~= "&HFFFFFF" then table.insert(effect, 1,"\\1c"..color ) end
    if attrs.font_size ~= 40 then table.insert(effect, 1, "\\fs"..attrs.font_size) end
    effect = next(effect) and "{" .. table.concat(effect) .. "}" or ""

    return string.format("Dialogue: 0,%s,%s,%s,,0,0,0,,%s%s",
        sec_to_ass_time(attrs.start_time),
        sec_to_ass_time(attrs.start_time + attrs.duration),
        style, effect, danmaku_text)
end

-- 获取B站弹幕URL、视频帧率、分辨率
local function get_danmaku_info()
    local result = mp.get_property_native("user-data/mpv/ytdl/json-subprocess-result") or {}
    local data = require 'mp.utils'.parse_json(result.stdout or "") or {}
    return {
        url = ((data.requested_subtitles or {}).danmaku or {}).url,
        fps = data.fps or 30,
        width = data.width or 1920,
        height = data.height or 1080
    }
end

local function process_danmaku(data)
    if not data.url then return end
    local userAgent = mp.get_property("file-local-options/user-agent", "")
    local res = mp.command_native({
        name = "subprocess", capture_stdout = true, capture_stderr = true,
        args = {"curl", "-fs", data.url, "-A", userAgent, "--compressed"}})
    if not res.stdout or res.stderr ~= "" then return end

    local danmaku = parse_xml_danmaku(res.stdout)
    local ass_content = {ASS_HEADER}
    track_pool = {}

    table.sort(danmaku, function(a, b)
        return a.attrs.start_time < b.attrs.start_time
    end)
    
    for _, dm in ipairs(danmaku) do
        local ass_line = danmaku_to_ass(dm.text, dm.attrs, data)
        if ass_line ~= "" then table.insert(ass_content, ass_line) end
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
end

mp.add_hook("on_preloaded", 50, function()
    process_danmaku(get_danmaku_info())
end)
