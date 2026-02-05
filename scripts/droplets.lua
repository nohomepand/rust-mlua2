local width, height = 600, 600
local w = egui.create_window("Droplets", width, height)
local rnd = function (r, lb)
    return math.random() * r + (lb or 0)
end
local Droplet = {x = 0, y = 0, r = 0, ur = 0, ms = 0}
function Droplet:new(x, y)
    local o = {x = x, y = y, r = 0, ur = math.floor(rnd(10, 5)), ms = rnd(50)}
    setmetatable(o, self)
    self.__index = self
    return o
end

function Droplet:draw()
    self.r = self.r + 1
    for i = 0, self.ur do
        local c = (math.sin(math.rad(self.r + i) * self.ms) + 1) / 2 * 255
        w:circle(self.x, self.y, self.r + i, c, c, c, 127)
    end
end


local droplets = {}
while true do
    for i = 0, math.floor(rnd(5, 1)) do
        table.insert(droplets, Droplet:new(rnd(width), rnd(height)))
    end
    local avail_droplets = {}
    for _, d in pairs(droplets) do
        d:draw()
        if rnd(1) < 0.95 then
            table.insert(avail_droplets, d)
        end
    end
    droplets = avail_droplets
    coroutine.yield()
    w:cls()
end