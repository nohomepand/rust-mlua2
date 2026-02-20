math.randomseed(os.time())

local N = arg[1] or 128
local SCALE = 3
local SIZE = N + 2

local dt = 0.1
local diff = 0.0001
local visc = 0.0001
local iter = 10

local win = egui.create_window("CFD", N * SCALE, N * SCALE)

local function IX(x, y)
    return x + y * SIZE
end

local s = {}
local density = {}
local Vx = {}
local Vy = {}
local Vx0 = {}
local Vy0 = {}

local function init()
    for i = 0, (SIZE * SIZE) do
        s[i] = 0
        density[i] = 0
        Vx[i] = 0
        Vy[i] = 0
        Vx0[i] = 0
        Vy0[i] = 0
    end
end

-------------------------------------------------
-- 境界条件
-------------------------------------------------
local function set_bnd(b, x)
    local b_eq_1 = b == 1
    for i = 1, N do
        x[IX(0, i)]  = b == 1 and -x[IX(1, i)] or x[IX(1, i)]
        x[IX(N + 1, i)] = b == 1 and -x[IX(N, i)] or x[IX(N, i)]
        x[IX(i, 0)]  = b == 2 and -x[IX(i, 1)] or x[IX(i, 1)]
        x[IX(i, N + 1)] = b == 2 and -x[IX(i, N)] or x[IX(i, N)]
    end

    x[IX(0, 0)]    = 0.5 * (x[IX(1, 0)] + x[IX(0, 1)])
    x[IX(0, N + 1)] = 0.5 * (x[IX(1, N + 1)] + x[IX(0, N)])
    x[IX(N + 1, 0)] = 0.5 * (x[IX(N, 0)] + x[IX(N + 1, 1)])
    x[IX(N + 1, N + 1)] = 0.5 * (x[IX(N, N + 1)] + x[IX(N + 1, N)])
end

-------------------------------------------------
-- 線形解法
-------------------------------------------------
local function lin_solve(b, x, x0, a, c)
    for k = 1, iter do
        for j = 1, N do
            for i = 1, N do
                x[IX(i, j)] =
                    (x0[IX(i, j)] +
                        a * (x[IX(i - 1, j)] +
                            x[IX(i + 1, j)] +
                            x[IX(i, j - 1)] +
                            x[IX(i, j + 1)])) / c
            end
        end
        set_bnd(b, x)
    end
end

-------------------------------------------------
-- 拡散
-------------------------------------------------
local function diffuse(b, x, x0, diff)
    local a = dt * diff * N * N
    lin_solve(b, x, x0, a, 1 + 4 * a)
end

-------------------------------------------------
-- 移流
-------------------------------------------------
local function advect(b, d, d0, u, v)
    local dt0 = dt * N
    for j = 1, N do
        for i = 1, N do
            local x = i - dt0 * u[IX(i, j)]
            local y = j - dt0 * v[IX(i, j)]

            if x < 0.5 then x = 0.5 end
            if x > N + 0.5 then x = N + 0.5 end
            local i0 = math.floor(x)
            local i1 = i0 + 1

            if y < 0.5 then y = 0.5 end
            if y > N + 0.5 then y = N + 0.5 end
            local j0 = math.floor(y)
            local j1 = j0 + 1

            local s1 = x - i0
            local s0 = 1 - s1
            local t1 = y - j0
            local t0 = 1 - t1

            d[IX(i, j)] =
                s0 * (t0 * d0[IX(i0, j0)] + t1 * d0[IX(i0, j1)]) +
                s1 * (t0 * d0[IX(i1, j0)] + t1 * d0[IX(i1, j1)])
        end
    end
    set_bnd(b, d)
end

-------------------------------------------------
-- 発散除去（圧力）
-------------------------------------------------
local function project(u, v, p, div)
    for j = 1, N do
        for i = 1, N do
            div[IX(i, j)] = -0.5 * (
                u[IX(i + 1, j)] - u[IX(i - 1, j)] +
                v[IX(i, j + 1)] - v[IX(i, j - 1)]
            ) / N
            p[IX(i, j)] = 0
        end
    end

    set_bnd(0, div)
    set_bnd(0, p)
    lin_solve(0, p, div, 1, 4)

    for j = 1, N do
        for i = 1, N do
            u[IX(i, j)] = u[IX(i, j)] - 0.5 * N * (p[IX(i + 1, j)] - p[IX(i - 1, j)])
            v[IX(i, j)] = v[IX(i, j)] - 0.5 * N * (p[IX(i, j + 1)] - p[IX(i, j - 1)])
        end
    end

    set_bnd(1, u)
    set_bnd(2, v)
end

-------------------------------------------------
-- 1ステップ更新
-------------------------------------------------
local function step()
    diffuse(1, Vx0, Vx, visc)
    diffuse(2, Vy0, Vy, visc)

    project(Vx0, Vy0, Vx, Vy)

    advect(1, Vx, Vx0, Vx0, Vy0)
    advect(2, Vy, Vy0, Vx0, Vy0)

    project(Vx, Vy, Vx0, Vy0)

    diffuse(0, s, density, diff)
    advect(0, density, s, Vx, Vy)
end

-------------------------------------------------
-- 描画
-------------------------------------------------
local function draw()
    win:cls(0, 0, 0)

    for j = 1, N do
        for i = 1, N do
            local d = density[IX(i, j)]
            if d > 255 then d = 255 end
            if d < 0 then d = 0 end

            win:fillrect(
                (i - 1) * SCALE,
                (j - 1) * SCALE,
                i * SCALE,
                j * SCALE,
                d, d, d
            )
        end
    end
end

-------------------------------------------------
-- 入力
-------------------------------------------------
local keystate = {}
function egui.keyhandler(state, vk, code)
    if state == "Pressed" then
        keystate[vk] = true
    else
        keystate[vk] = nil
    end
end

-------------------------------------------------
-- メインループ
-------------------------------------------------
print("Press arrow-keys to spread smoke.")
print("Press space key to clear.")
print("Press \"S\" key to vacuum.")
init()
while true do
    if next(keystate) ~= nil then
        local cx = math.floor(N / 2)
        local cy = math.floor(N / 2)
        
        if keystate["S"] == nil then
            local sz = 3
            for x = -sz, sz do
                for y = -sz, sz do
                    density[IX(cx + x, cy + y)] = 250
                end
            end
        else
            local sz = 3
            for x = -sz, sz do
                for y = -sz, sz do
                    density[IX(cx + x, cy + y)] = 0
                end
            end
        end
        
        if keystate["Left"] then Vx[IX(cx, cy)] = -50 end
        if keystate["Right"] then Vx[IX(cx, cy)] = 50 end
        if keystate["Up"] then Vy[IX(cx, cy)] = -50 end
        if keystate["Down"] then Vy[IX(cx, cy)] = 50 end
        if keystate["Space"] then init() end
    end
    step()
    draw()
    coroutine.yield()
end
