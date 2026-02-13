local w = arg[1] or 600
local h = arg[2] or 600
local win = egui.create_window("lissajous curve", w, h)
local rnd = function (r, l) return math.random() * r + (l or 0) end

local obj = {
    A = w / 2,
    B = h / 2,
    a = rnd(5, 1),
    b = rnd(5, 1),
    delta = math.pi / 2,
    i = 0,
    draw = function (self)
        local steps = 100
        for p = 1, steps do
            local t = ((self.i + p / steps) / steps) * 2 * math.pi
            local x = self.A * math.sin(self.a * t + self.delta)
            local y = self.B * math.sin(self.b * t)
            win:point(w / 2 + x, h / 2 + y, 255, 255, 255)
        end
        self.i = self.i + 1
    end
}

:: here ::
    obj:draw()
    coroutine.yield()
goto here
