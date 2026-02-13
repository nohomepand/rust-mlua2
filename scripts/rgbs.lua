local w, h = 300, 300
local win = egui.create_window("rgbs", w, h)

local function randomdots()
    for x = 0, w do
        for y = 0, h do
            local r = math.random(0, 255)
            local g = math.random(0, 255)
            local b = math.random(0, 255)
            win:point(x, y, r, g, b)
        end
    end
end

local t = {}
function egui.cursorhandler(x, y)
    win:getpointi(x, y, t)
    local r, g, b, a = table.unpack(t)
    print(t, r, g, b, a)
end

randomdots()
while true do
    coroutine.yield()
end

