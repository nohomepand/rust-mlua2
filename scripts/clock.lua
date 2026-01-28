local function analog_clock()
    local cx, cy = 200, 200 -- center of clock
    local radius = 150
    local w = egui.create_window("clock", (radius * 2 - cx / 2) * 2, (radius * 2 - cy / 2) * 2)

    local start = os.clock()

    while true do
        w:cls()
        -- Draw clock face
        for i = 0, 59 do
            local angle = math.rad(i * 6)
            local x1 = cx + math.cos(angle) * (radius - 10)
            local y1 = cy + math.sin(angle) * (radius - 10)
            local x2 = cx + math.cos(angle) * radius
            local y2 = cy + math.sin(angle) * radius
            local r, g, b = 0.7 * 255, 0.7 * 255, 0.7 * 255
            if i % 5 == 0 then
                r, g, b = 0.3 * 255, 0.3 * 255, 0.3 * 255 -- hour marks darker
                x1 = cx + math.cos(angle) * (radius - 20)
                y1 = cx + math.sin(angle) * (radius - 20)
            end
            w:line(x1, y1, x2, y2, r, g, b)
        end

        -- Get current time (smooth)
        local t = os.date("*t")
        local now = os.clock() - start
        local sec = t.sec -- + (now % 1)
        local min = t.min + sec / 60
        local hour = (t.hour % 12) + min / 60

        -- Draw hour hand
        local hour_angle = math.rad((hour) * 30 - 90)
        local hx = cx + math.cos(hour_angle) * (radius * 0.5)
        local hy = cy + math.sin(hour_angle) * (radius * 0.5)
        w:line(cx, cy, hx, hy, 0.2 * 255, 0.2 * 255, 0.6 * 255)

        -- Draw minute hand
        local min_angle = math.rad((min) * 6 - 90)
        local mx = cx + math.cos(min_angle) * (radius * 0.8)
        local my = cy + math.sin(min_angle) * (radius * 0.8)
        w:line(cx, cy, mx, my, 0.2 * 255, 0.6 * 255, 0.2 * 255)

        -- Draw second hand (smooth)
        local sec_angle = math.rad(sec * 6 - 90)
        local sx = cx + math.cos(sec_angle) * (radius * 0.9)
        local sy = cy + math.sin(sec_angle) * (radius * 0.9)
        w:line(cx, cy, sx, sy, 0.8 * 255, 0.1 * 255, 0.1 * 255)

        coroutine.yield()
    end
end

local function digital_clock()
    local w = egui.create_window("digital clock", 300, 200)
    local init_now = os.clock()
    while true do
        -- w:cls()
        local t = os.date("*t")
        local time_str = string.format("%02d:%02d:%02d", t.hour, t.min, t.sec)
        -- w:text(80, 140, time_str)
        w:text(0, 0, time_str, os.clock() - init_now)
        coroutine.yield()
        w:scroll(0, w:gettextfontsize())
    end
end

local threads = {}
table.insert(threads, coroutine.wrap(analog_clock))
table.insert(threads, coroutine.wrap(digital_clock))
while true do
    for _, thf in ipairs(threads) do
        thf()
    end
    -- sleep(10)
    coroutine.yield()
end
