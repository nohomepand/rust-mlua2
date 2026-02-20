-- ウィンドウサイズ
local width, height = 800, 600
local win = egui.create_window("N-Body Simulation", width, height)

-- N体の数
local N = arg[1] or 50

-- 重力定数
local G = arg[2] or 100

-- 時間ステップ
local dt = 0.016

-- 質量、位置、速度の初期化
local bodies = {}
math.randomseed(os.time())
for i = 1, N do
    bodies[i] = {
        x = math.random(100, width - 100),
        y = math.random(100, height - 100),
        vx = (math.random() - 0.5) * 40,
        vy = (math.random() - 0.5) * 40,
        m = math.random(5, 20)
    }
end

local function update_kinect()
    -- 力の計算
    for i = 1, N do
        local fx, fy = 0, 0
        for j = 1, N do
            if i ~= j then
                local dx = bodies[j].x - bodies[i].x
                local dy = bodies[j].y - bodies[i].y
                local dist2 = dx * dx + dy * dy + 25 -- ソフト化
                local dist = math.sqrt(dist2)
                local force = G * bodies[i].m * bodies[j].m / dist2
                fx = fx + force * dx / dist
                fy = fy + force * dy / dist
            end
        end
        bodies[i].fx = fx
        bodies[i].fy = fy
    end
end

local function update_position()
    -- 位置と速度の更新
    for i = 1, N do
        local ax = bodies[i].fx / bodies[i].m
        local ay = bodies[i].fy / bodies[i].m
        bodies[i].vx = bodies[i].vx + ax * dt
        bodies[i].vy = bodies[i].vy + ay * dt
        bodies[i].x = bodies[i].x + bodies[i].vx * dt
        bodies[i].y = bodies[i].y + bodies[i].vy * dt

        -- 画面外に出たら跳ね返す
        if bodies[i].x < 0 then
            bodies[i].x = 0; bodies[i].vx = -bodies[i].vx
        end
        if bodies[i].x > width then
            bodies[i].x = width; bodies[i].vx = -bodies[i].vx
        end
        if bodies[i].y < 0 then
            bodies[i].y = 0; bodies[i].vy = -bodies[i].vy
        end
        if bodies[i].y > height then
            bodies[i].y = height; bodies[i].vy = -bodies[i].vy
        end
    end
end

local function merge_bodies()
    for i = N - 1, 1, -1 do
        local b1 = bodies[i]
        for k = N, i + 1, -1 do
            local b2 = bodies[k]
            local dx = b1.x - b2.x
            local dy = b1.y - b2.y
            local dist2 = dx * dx + dy * dy
            local r1 = math.max(2, b1.m)
            local r2 = math.max(2, b2.m)
            local min_dist = (r1 + r2) / 8
            if dist2 < min_dist * min_dist then
                -- マージ
                local m_total = b1.m + b2.m
                local vx = (b1.vx * b1.m + b2.vx * b2.m) / m_total
                local vy = (b1.vy * b1.m + b2.vy * b2.m) / m_total
                local x = (b1.x * b1.m + b2.x * b2.m) / m_total
                local y = (b1.y * b1.m + b2.y * b2.m) / m_total
                bodies[i] = {x = x, y = y, vx = vx, vy = vy, m = m_total}
                table.remove(bodies, k)
                N = N - 1
            end
        end
    end
end

local function draw()
    win:cls(0, 0, 0)
    -- 描画
    for i = 1, N do
        local r = math.max(2, bodies[i].m)
        win:circle(bodies[i].x, bodies[i].y, r, 255, 255, 0)
    end
end

-- メインループ
while true do
    update_kinect()
    update_position()
    merge_bodies()
    draw()
    coroutine.yield()
end
