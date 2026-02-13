-- ============================================
--  Random Moving Points + Delaunay Triangulation
--  Bowyer-Watson Algorithm
-- ============================================

local width = 800
local height = 600
local win = egui.create_window("Delaunay", width, height)

local POINT_COUNT = 100
local points = {}

-- 初期化
for i = 1, POINT_COUNT do
    table.insert(points, {
        x = math.random() * width,
        y = math.random() * height,
        vx = (math.random() - 0.5) * 2,
        vy = (math.random() - 0.5) * 2
    })
end

-- 外接円計算
local function circumcircle(tri)
    local ax, ay = tri[1].x, tri[1].y
    local bx, by = tri[2].x, tri[2].y
    local cx, cy = tri[3].x, tri[3].y

    local d = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
    if d == 0 then return nil end

    local ux = ((ax * ax + ay * ay) * (by - cy) + (bx * bx + by * by) * (cy - ay) + (cx * cx + cy * cy) * (ay - by)) / d
    local uy = ((ax * ax + ay * ay) * (cx - bx) + (bx * bx + by * by) * (ax - cx) + (cx * cx + cy * cy) * (bx - ax)) / d

    local dx = ux - ax
    local dy = uy - ay
    return { x = ux, y = uy, r = math.sqrt(dx * dx + dy * dy) }
end

-- ドロネー計算
local function delaunay(pts)
    local triangles = {}

    -- スーパートライアングル
    local margin = 1000
    local st = {
        { x = -margin,      y = -margin },
        { x = width + margin, y = -margin },
        { x = width / 2,    y = height + margin }
    }
    table.insert(triangles, { st[1], st[2], st[3] })

    for _, p in ipairs(pts) do
        local bad = {}
        for i, tri in ipairs(triangles) do
            local cc = circumcircle(tri)
            if cc then
                local dx = p.x - cc.x
                local dy = p.y - cc.y
                if dx * dx + dy * dy < cc.r * cc.r then
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
                local found = false
                for j, pe in ipairs(polygon) do
                    if (pe[1] == e[2] and pe[2] == e[1]) then
                        table.remove(polygon, j)
                        found = true
                        break
                    end
                end
                if not found then
                    table.insert(polygon, e)
                end
            end
        end

        for _, e in ipairs(polygon) do
            table.insert(triangles, { e[1], e[2], p })
        end
    end

    -- スーパートライアングル除去
    local final = {}
    for _, tri in ipairs(triangles) do
        local keep = true
        for _, v in ipairs(st) do
            if tri[1] == v or tri[2] == v or tri[3] == v then
                keep = false
                break
            end
        end
        if keep then
            table.insert(final, tri)
        end
    end

    return final
end

-- メインループ
while true do
    win:cls(0, 0, 0)

    -- 点移動
    for _, p in ipairs(points) do
        p.x = p.x + p.vx
        p.y = p.y + p.vy

        if p.x < 0 or p.x > width then p.vx = -p.vx end
        if p.y < 0 or p.y > height then p.vy = -p.vy end
    end

    -- ドロネー計算
    local tris = delaunay(points)

    -- 線描画
    for _, tri in ipairs(tris) do
        win:line(tri[1].x, tri[1].y, tri[2].x, tri[2].y, 0, 255, 0)
        win:line(tri[2].x, tri[2].y, tri[3].x, tri[3].y, 0, 255, 0)
        win:line(tri[3].x, tri[3].y, tri[1].x, tri[1].y, 0, 255, 0)
    end

    -- 点描画
    for _, p in ipairs(points) do
        win:point(p.x, p.y, 255, 255, 255)
    end

    coroutine.yield()
end
