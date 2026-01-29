print("hello")
w = egui.create_window("TestWin",600,600)
print("HERE")
w:cls(0,0,0)
local i = 0
local rnd = function (n, l) return math.random() * (n or 100) + (l or 0) end
local lissajous = {
    r1 = rnd(10),
    r2 = rnd(10),
    t = 0,
    draw = function (self, window)
        local r1 = self.r1 + math.sin(os.clock() / 500) * 10
        local r2 = self.r2 + math.sin(os.clock() / 500) * 10
        for i = 0, 2000 do
            local ang = math.rad(self.t - i)
            local r = (math.sin(ang) + 1) / 2 * 255
            local g = (math.cos(ang) + 1) / 2 * 255
            local b = 255
            local x1 = math.sin(ang * r1) * 300 + 300
            local y1 = math.cos(ang * r1) * 300 + 300
            local x2 = math.sin(ang * r2) * 300 + 300
            local y2 = math.cos(ang * r2) * 300 + 300
            window:line(x1, y1, x2, y2, r, g, b)
        end
        self.t = self.t + 1
    end
}
while true do
    i = i + 1
    print("repeat", i)
    -- w:point(10,10,255,255,0)
    -- w:circle(rnd(600), rnd(600), rnd(100), 255,0,0)
    -- w:line(20,20,100,100,0,255,0)
    -- w:circle(50,50,20,0,0,255)
    -- w:rect(rnd(600), rnd(600), rnd(600), rnd(600), 0, 255,0)
    -- w:settextcolor(rnd(100, 155), rnd(100, 155), rnd(100, 155))
    -- w:text(5,5,"こんにちわHello Lua!", i)
    lissajous:draw(w)
    coroutine.yield()
    w:cls()
    -- print("coroutine yielded")
end