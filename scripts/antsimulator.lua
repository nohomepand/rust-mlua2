local width, height = 800, 800
local gridSize = 100
local cellSize = math.floor(width / gridSize)
local antCount = 10
local foodCount = 15

local win = egui.create_window("Ant Simulator", width, height)

-- Colors
local FOOD_COLOR = { r = 0, g = 255, b = 0 }
local ANT_COLOR = { r = 255, g = 0, b = 0 }
local EMPTY_COLOR = { r = 255, g = 255, b = 255 }

win:cls(EMPTY_COLOR.r, EMPTY_COLOR.g, EMPTY_COLOR.b)
-- Helper to draw cell
local function draw_cell(x, y, color)
    local px = x * cellSize
    local py = y * cellSize
    win:fillrect(px, py, px + cellSize - 1, py + cellSize - 1, color.r, color.g, color.b)
end

-- Ant class
local Ant = {}
Ant.__index = Ant
function Ant:new(x, y)
    return setmetatable({ x = x, y = y, carrying = false }, Ant)
end

function Ant:move()
    local dirs = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }
    -- Pick up food if present
    local r, g, b, _ = win:getpoint((self.x - 1) * cellSize, (self.y - 1) * cellSize)
    if not self.carrying and r == FOOD_COLOR.r and g == FOOD_COLOR.g and b == FOOD_COLOR.b then
        self.carrying = true
        draw_cell(self.x, self.y, EMPTY_COLOR)
    end
    -- Move randomly
    local d = dirs[math.random(1, 4)]
    local nx, ny = self.x + d[1], self.y + d[2]
    if nx >= 1 and nx <= gridSize and ny >= 1 and ny <= gridSize then
        self.x, self.y = nx, ny
    end
end

-- Place food
math.randomseed(os.time())
for i = 1, foodCount do
    local fx, fy
    fx, fy = math.random(1, gridSize), math.random(1, gridSize)
    draw_cell(fx, fy, FOOD_COLOR)
end

-- Place ants
local ants = {}
for i = 1, antCount do
    local ax, ay
    ax, ay = math.random(1, gridSize), math.random(1, gridSize)
    ants[i] = Ant:new(ax, ay)
end

-- Draw ants
local function draw_ants()
    for _, ant in ipairs(ants) do
        draw_cell(ant.x, ant.y, ANT_COLOR)
    end
end

-- Clear ants (draw empty where ants were)
local function clear_ants()
    for _, ant in ipairs(ants) do
        draw_cell(ant.x, ant.y, EMPTY_COLOR)
    end
end

while true do
    clear_ants()
    for _, ant in ipairs(ants) do
        ant:move()
    end
    draw_ants()
    coroutine.yield()
end
