math.randomseed(os.time())

local TILE = 24
local W = 32
local H = 32

local win = egui.create_window("Sokoban", W * TILE, H * TILE)

local stage = 1
local map = {}
local player = { x = 0, y = 0 }
local goal = { x = 0, y = 0 }

local EMPTY = 0
local WALL = 1
local BOX = 2

-------------------------------------------------
-- 安全確認
-------------------------------------------------
local function inside(x, y)
    return x > 1 and x < W and y > 1 and y < H
end

-------------------------------------------------
-- ステージ生成
-------------------------------------------------
local function pseudo_random_walk(n)
    n = n or 4
    return function ()
        while true do
            local dir = math.random(1, 4)
            for i = 1, math.random(1, n) do
                coroutine.yield(dir)
            end
        end
    end
end

local function new_stage()
    :: re_create ::
    map = {}

    -- 基本マップ
    for y = 1, H do
        map[y] = {}
        for x = 1, W do
            if x == 1 or y == 1 or x == W or y == H then
                map[y][x] = WALL
            else
                map[y][x] = EMPTY
            end
        end
    end

    -- 1/4 をランダム壁で埋める
    local fillcount = math.floor((W - 2) * (H - 2) / 4)
    local placed = 0

    while placed < fillcount do
        local x = math.random(2, W - 1)
        local y = math.random(2, H - 1)

        if map[y][x] == EMPTY then
            map[y][x] = BOX
            placed = placed + 1
        end
    end

    -- ゴールは壁でない場所
    repeat
        goal.x = math.random(6, W - 5)
        goal.y = math.random(6, H - 5)
    until map[goal.y][goal.x] == EMPTY

    player.x = goal.x
    player.y = goal.y

    -------------------------------------------------
    -- 逆生成（既存壁を考慮）
    -------------------------------------------------

    local steps = 60 + stage * 10
    local rndwalk = coroutine.wrap(pseudo_random_walk(2 + math.floor(stage / 10)))
    for i = 1, steps do
        local dir = rndwalk()
        local dx, dy = 0, 0
        if dir == 1 then dx = 1 end
        if dir == 2 then dx = -1 end
        if dir == 3 then dy = 1 end
        if dir == 4 then dy = -1 end

        local frontx = player.x + dx
        local fronty = player.y + dy
        local backx  = player.x - dx
        local backy  = player.y - dy

        if inside(frontx, fronty) and inside(backx, backy) then
            if map[fronty][frontx] == EMPTY and
                map[backy][backx] == EMPTY then
                -- BOX設置（将来ここを押すことになる）
                map[fronty][frontx] = BOX

                -- プレイヤーを後退
                player.x = backx
                player.y = backy
            end
        end
    end
    map[goal.y][goal.x] = EMPTY
    if player.x == goal.x and player.y == goal.y then
        goto re_create
    end
end

-------------------------------------------------
-- 描画
-------------------------------------------------
local function draw()
    win:cls(20, 20, 20)

    for y = 1, H do
        for x = 1, W do
            local sx = (x - 1) * TILE
            local sy = (y - 1) * TILE

            if map[y][x] == WALL then
                win:fillrect(sx, sy, sx + TILE, sy + TILE, 100, 100, 100)
            elseif map[y][x] == BOX then
                win:fillrect(sx, sy, sx + TILE, sy + TILE, 200, 140, 40)
            end
        end
    end

    -- ゴール
    win:rect((goal.x - 1) * TILE, (goal.y - 1) * TILE, goal.x * TILE, goal.y * TILE, 40, 180, 40)

    -- プレイヤー
    win:fillrect((player.x - 1) * TILE, (player.y - 1) * TILE, player.x * TILE, player.y * TILE, 40, 120, 220)
    
    win:text(0, 0, "←→↑↓で移動", "ESCで次ステージ", "stage " .. stage)
end

-------------------------------------------------
-- 移動処理
-------------------------------------------------
local function move(dx, dy)
    local nx = player.x + dx
    local ny = player.y + dy

    if map[ny][nx] == WALL then return end

    if map[ny][nx] == BOX then
        local bx = nx + dx
        local by = ny + dy

        if map[by][bx] == EMPTY then
            map[by][bx] = BOX
            map[ny][nx] = EMPTY
        else
            return
        end
    end

    player.x = nx
    player.y = ny

    if player.x == goal.x and player.y == goal.y then
        stage = stage + 1
        new_stage()
    end
end

-------------------------------------------------
-- キー入力（指定どおり）
-------------------------------------------------
function egui.keyhandler(state, vk, code)
    if state == "Pressed" then
        if vk == "Left" then move(-1, 0) end
        if vk == "Up" then move(0, -1) end
        if vk == "Right" then move(1, 0) end
        if vk == "Down" then move(0, 1) end
        if vk == "Escape" then new_stage() end
    end
end

-------------------------------------------------
-- 開始
-------------------------------------------------
new_stage()

while true do
    draw()
    coroutine.yield()
end
