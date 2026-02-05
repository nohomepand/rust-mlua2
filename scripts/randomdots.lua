local w, h = 1024, 768
local win = egui.create_window("randomdots", w, h)
local rnd = function (r, l)
    return math.random() * r + (l or 0)
end
local function dots()
    for i=0, 10000 do
        local x = rnd(w)
        local y = rnd(h)
        local r, g, b = rnd(150, 100), rnd(150, 100), rnd(150, 100)
        win:point(x, y, r, g, b)
    end
end

local lastts = hpc()
local frames = 0
while true do
    frames = frames + 1
    if hpc() - lastts >= 1.0 then
        print("FPS=", frames)
        frames = 0
        lastts = hpc()
    end
    dots()
    coroutine.yield()
end