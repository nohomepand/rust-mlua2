-- マンデルブロー集合を計算するクラス
local Mandelbrot = {}
Mandelbrot.__index = Mandelbrot

function Mandelbrot.new(width, height, max_iter, x_min, x_max, y_min, y_max)
    local self = setmetatable({}, Mandelbrot)
    self.width = width or 800
    self.height = height or 600
    self.max_iter = max_iter or 100
    self.x_min = x_min or -2.0
    self.x_max = x_max or 1.0
    self.y_min = y_min or -1.5
    self.y_max = y_max or 1.5
    return self
end

function Mandelbrot:compute()
    local result = {}
    local maxiter = 0
    for py = 1, self.height do
        local row = {}
        local y0 = self.y_min + (py - 1) * (self.y_max - self.y_min) / (self.height - 1)
        for px = 1, self.width do
            local x0 = self.x_min + (px - 1) * (self.x_max - self.x_min) / (self.width - 1)
            local x, y = 0.0, 0.0
            local iter = 0
            while x * x + y * y <= 4.0 and iter < self.max_iter do
                local xtemp = x * x - y * y + x0
                y = 2 * x * y + y0
                x = xtemp
                iter = iter + 1
            end
            row[px] = iter
            if maxiter < iter then
                maxiter = iter
            end
        end
        result[py] = row
    end
    return result, maxiter
end

local m = Mandelbrot.new()
local w = egui.create_window("Mandelbrot", m.width, m.height)
local c, mi = m:compute()
for y = 1, m.height do
    for x = 1, m.width do
        local t = c[y][x] / mi
        local r, g, b
        r = t * 255
        g = t * 150
        b = t * 255
        w:point(x, y, r, g, b)
    end
end
