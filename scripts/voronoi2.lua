-- ============================================
--  Random Moving Points + Voronoi Diagram
-- ============================================

local width = 400
local height = 400
local win = egui.create_window("Voronoi", width, height)

local POINT_COUNT = 100
local points = {}
local BACKGROUND_DEFAULT_COLOR = {r = 0, g = 0, b = 0}
local BOUNDARY_COLOR = {r = 99, g = 99, b = 99} -- BACKGROUND_DEFAULT_COLOR と異なる色でないと塗りつぶせない

math.randomseed(os.time())

-- 初期化
for i = 1, POINT_COUNT do
    table.insert(points, {
        x = math.random() * width,
        y = math.random() * height,
        vx = (math.random() - 0.5) * 2,
        vy = (math.random() - 0.5) * 2,
        r = math.random(100, 255),
        g = math.random(150, 255),
        b = math.random(100, 255),
    })
end
for x = 0, 1 do
    for y = 0, 1 do
        table.insert(points, {
        x = x * width,
        y = y * height,
        vx = 0,
        vy = 0,
        r = math.random(100, 255),
        g = math.random(150, 255),
        b = math.random(100, 255),
    })
    end
end

-- 外接円
local function circumcircle(tri)
    local ax, ay = tri[1].x, tri[1].y
    local bx, by = tri[2].x, tri[2].y
    local cx, cy = tri[3].x, tri[3].y

    local d = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
    if math.abs(d) < 1e-6 then return nil end

    local ux = ((ax * ax + ay * ay) * (by - cy) + (bx * bx + by * by) * (cy - ay) + (cx * cx + cy * cy) * (ay - by)) / d
    local uy = ((ax * ax + ay * ay) * (cx - bx) + (bx * bx + by * by) * (ax - cx) + (cx * cx + cy * cy) * (bx - ax)) / d

    return { x = ux, y = uy }
end

-- Delaunay (Bowyer-Watson)
local function delaunay(pts)
    local triangles = {}

    local margin = 2000
    local st = {
        { x = -margin,     y = -margin },
        { x = width + margin, y = -margin },
        { x = width / 2,   y = height + margin }
    }
    table.insert(triangles, { st[1], st[2], st[3] })

    for _, p in ipairs(pts) do
        local bad = {}
        local circles = {}

        for i, tri in ipairs(triangles) do
            local cc = circumcircle(tri)
            if cc then
                local dx = p.x - cc.x
                local dy = p.y - cc.y
                if dx * dx + dy * dy <
                    ((tri[1].x - cc.x) ^ 2 + (tri[1].y - cc.y) ^ 2) then
                    table.insert(bad, i)
                end
            end
        end

        local polygon = {}

        for i = #bad, 1, -1 do
            local tri = table.remove(triangles, bad[i])
            local edges = {
                { tri[1], tri[2] },
                { tri[2], tri[3] },
                { tri[3], tri[1] }
            }

            for _, e in ipairs(edges) do
                local shared = false
                for j, pe in ipairs(polygon) do
                    if (pe[1] == e[2] and pe[2] == e[1]) then
                        table.remove(polygon, j)
                        shared = true
                        break
                    end
                end
                if not shared then
                    table.insert(polygon, e)
                end
            end
        end

        for _, e in ipairs(polygon) do
            table.insert(triangles, { e[1], e[2], p })
        end
    end

    local final = {}
    for _, tri in ipairs(triangles) do
        local keep = true
        for _, v in ipairs(st) do
            if tri[1] == v or tri[2] == v or tri[3] == v then
                keep = false
                break
            end
        end
        if keep then table.insert(final, tri) end
    end

    return final
end

-- メインループ
while true do
    win:cls(BACKGROUND_DEFAULT_COLOR.r, BACKGROUND_DEFAULT_COLOR.g, BACKGROUND_DEFAULT_COLOR.b)

    -- 点移動
    for _, p in ipairs(points) do
        p.x = p.x + p.vx
        p.y = p.y + p.vy

        if p.x < 0 or p.x > width then p.vx = -p.vx end
        if p.y < 0 or p.y > height then p.vy = -p.vy end
    end

    local tris = delaunay(points)

    -- 各三角形の外接円中心を保存
    local centers = {}
    for i, tri in ipairs(tris) do
        centers[i] = circumcircle(tri)
    end

    -- ボロノイ描画
    for i = 1, #tris do
        for j = i + 1, #tris do
            local shared = 0
            for a = 1, 3 do
                for b = 1, 3 do
                    if tris[i][a] == tris[j][b] then
                        shared = shared + 1
                    end
                end
            end

            if shared == 2 then
                local c1 = centers[i]
                local c2 = centers[j]
                if c1 and c2 then
                    win:line(c1.x, c1.y, c2.x, c2.y, BOUNDARY_COLOR.r, BOUNDARY_COLOR.g, BOUNDARY_COLOR.b)
                end
            end
        end
    end

    -- 点描画
    for _, p in ipairs(points) do
        win:point(p.x, p.y, p.r, p.g, p.b)
        -- local count = win:paint(p.x, p.y, p.r, p.g, p.b, 255, BOUNDARY_COLOR.r, BOUNDARY_COLOR.g, BOUNDARY_COLOR.b)
    end

    coroutine.yield()
end
