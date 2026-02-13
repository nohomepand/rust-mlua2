local width, height = 500, 500
local win = egui.create_window("Voronoi", width, height)

local num_points = 10
local points = {}

-- ランダムな色を生成
local function random_color()
    return math.random(0, 255), math.random(0, 255), math.random(0, 255)
end

-- 初期化
for i = 1, num_points do
    points[i] = {
        x = math.random(0, width - 1),
        y = math.random(0, height - 1),
        r, g, b = random_color()
    }
end

-- 点をランダムに動かす
local function move_points()
    for i = 1, num_points do
        points[i].x = math.max(0, math.min(width - 1, points[i].x + math.random(-2, 2)))
        points[i].y = math.max(0, math.min(height - 1, points[i].y + math.random(-2, 2)))
    end
end

-- ボロノイ図を描画
local function draw_voronoi()
    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local min_dist = 1e9
            local idx = 1
            for i = 1, num_points do
                local dx = points[i].x - x
                local dy = points[i].y - y
                local dist = dx * dx + dy * dy
                if dist < min_dist then
                    min_dist = dist
                    idx = i
                end
            end
            win:point(x, y, points[idx].r, points[idx].g, points[idx].b)
        end
    end
end

-- メインループ
while true do
    win:cls(0, 0, 0)
    move_points()
    draw_voronoi()
    -- 母点を強調表示
    for i = 1, num_points do
        win:point(points[i].x, points[i].y, 255, 255, 255)
    end
    coroutine.yield()
end
