-- B站XML弹幕转ASS格式
local ASS_HEADER = [[[Script Info]
Title: Bilibili Danmaku to ASS
ScriptType: v4.00+
Collisions: Normal
PlayResX: 1920
PlayResY: 1080
Timer: 100.0000
WrapStyle: 2
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Microsoft YaHei,40,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,1,1.5,1,7,5,5,8,0
Style: Top,Microsoft YaHei,40,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,1,1.5,1,8,5,5,8,0
Style: Bottom,Microsoft YaHei,40,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,1,1.5,1,2,5,5,8,0

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
]]

local ass_path = mp.command_native({"expand-path", "~~/cache/danmaku.ass"})

-- UTF8字符串长度（中文/全角=1，英文/半角=0.5）
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
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    local ms = math.floor((seconds - math.floor(seconds)) * 100)
    return string.format("%02d:%02d:%02d.%02d", h, m, s, ms)
end

-- B站RRGGBB → ASS BBGGRR
local function convert_bili_color_to_ass(color)
    color = tonumber(color) or 0xFFFFFF
    local hex = string.format("%06X", color)
    return "&H"..hex:sub(5,6)..hex:sub(3,4)..hex:sub(1,2)
end

-- XML转义还原
local function xml_unescape(s)
    return s and s:gsub("&amp;", "&")
                  :gsub("&lt;", "<")
                  :gsub("&gt;", ">")
                  :gsub("&quot;", "\"")
                  :gsub("&apos;", "'") or ""
end

-- 解析XML弹幕
local function parse_xml_danmakus(xml_content)
    local danmakus = {}
    local pattern = '<d%s+p="([^"]-)"[^>]->(.-)</d>'
    for p_attr, text in string.gmatch(xml_content, pattern) do
        table.insert(danmakus, {attr = p_attr, text = xml_unescape(text)})
    end
    return danmakus
end

-- 解析弹幕属性（官方标准）
local function parse_danmaku_attr(attr_str)
    local attrs = {start_time = 0, mode = 1, font_size = 40, color = 0xFFFFFF, duration = 3}
    if not attr_str then return attrs end
    local parts = {}
    for p in attr_str:gmatch("[^,]+") do table.insert(parts, p) end
    attrs.start_time = tonumber(parts[1]) or 0                  -- 弹幕出现时间（秒）
    attrs.mode = tonumber(parts[2]) or 1                        -- 弹幕模式：1-滚动 4-底部 5-顶部
    attrs.font_size = math.max(tonumber(parts[3]) or 40, 40)    -- 字号
    attrs.color = tonumber(parts[4]) or 0xFFFFFF                -- 颜色（十进制）
    --attrs.timestamp = tonumber(parts[5]) or 0                 -- 发送时间戳
    --attrs.pool = tonumber(parts[6]) or 0                      -- 弹幕池
    --attrs.uid = parts[7] or ""                                -- 用户ID
    --attrs.did = parts[8] or ""                                -- 弹幕ID
    return attrs
end

local track_pool = {}  -- 存储每个轨道的【结束占用时间】

-- 轨道分配（B站官方防重叠算法）
local function alloc_track(start_time, duration)
    local best_track, min_time = 1, 1/0
    for i=1, 16 do
        if not track_pool[i] or track_pool[i] <= start_time then best_track=i break end
        if track_pool[i] < min_time then min_time=track_pool[i] best_track=i end
    end
    track_pool[best_track] = start_time+duration
    return best_track
end

-- 滚动弹幕：B站官方速度、位置、运动曲线（极致还原）
local function generate_move_effect(text, font_size, start_time)
    local text_len = utf8_len(text)
    local text_width = text_len*font_size*0.88
    local speed = 70 + text_len*0.2
    local move_duration = (1920+text_width)/speed

    local track = alloc_track(start_time, move_duration)
    local track_height = font_size * 1.2
    local y_pos = track*track_height
    y_pos = math.min(y_pos, 1080-track_height*2)

    local move_effect = string.format("{\\move(1920,%d,-%d,%d)}",
          y_pos, text_width, y_pos)

    return move_effect, move_duration
end

local function danmaku_to_ass(danmaku_text, attrs)
    if not danmaku_text or danmaku_text == "" then return "" end
    local safe_text = string.gsub(danmaku_text, "([{}])", "\\%1") or ""
    local color = convert_bili_color_to_ass(attrs.color)

    local style = "Default"
    local effect = ""
    local duration = attrs.duration

    if attrs.mode == 1 then
        effect, duration = generate_move_effect(safe_text, attrs.font_size, attrs.start_time)
    elseif attrs.mode == 5 then
        style = "Top"
    elseif attrs.mode == 4 then
        style = "Bottom"
    else
        effect, duration = generate_move_effect(safe_text, attrs.font_size, attrs.start_time)
    end

    local ass_text = string.format("{\\fs%d\\1c%s\\alpha&H10&}%s%s", attrs.font_size, color, effect, safe_text)
    local end_time = attrs.start_time + duration

    return string.format("Dialogue: 0,%s,%s,%s,,0,0,0,,%s",
        sec_to_ass_time(attrs.start_time),
        sec_to_ass_time(end_time),
        style, ass_text)
end

local function get_danmaku_url()
    for _, track in ipairs(mp.get_property_native("track-list") or {}) do
        if track.lang == "danmaku" and track["external-filename"] then
            local url = track["external-filename"]:match("https?://.-%.xml")
            return url, track.id
        end
    end
end

local function process_danmaku(url, danmaku_id, callback)
    local userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36 Edg/146.0.0.0"
    mp.command_native_async({
        name = "subprocess", capture_stdout = true, capture_stderr=true,
        args = {"curl", "-fs", url, "-A", userAgent, "--compressed"}},
        function(_, res)
        if not res.stdout or res.stderr~="" then return end

        local danmakus = parse_xml_danmakus(res.stdout)
        local ass_content = {ASS_HEADER}
        track_pool = {}

        table.sort(danmakus, function(a, b)
            return parse_danmaku_attr(a.attr).start_time < parse_danmaku_attr(b.attr).start_time
        end)

        for _, dm in ipairs(danmakus) do
            local ass_line = danmaku_to_ass(dm.text, parse_danmaku_attr(dm.attr))
            if ass_line ~= "" then table.insert(ass_content, ass_line) end
        end

        local ass_file = io.open(ass_path, "w")
        if ass_file then ass_file:write(table.concat(ass_content, "\n")) ass_file:close() end

        pcall(mp.commandv, "sub-add", ass_path, "auto")
        mp.set_property_number("secondary-sid", danmaku_id)
        mp.msg.info("Total "..#danmakus.." danmaku loaded.")
        if callback then callback() end
    end)
end

mp.add_hook("on_preloaded", 50, function(hook)
    local url, danmaku_id = get_danmaku_url()
    if not url or not danmaku_id then return end
    pcall(mp.commandv, "sub-remove", tostring(danmaku_id))
    mp.set_property("secondary-sub-ass-override", "scale")
    hook:defer()
    process_danmaku(url, danmaku_id, function() hook:cont() end)
end)
