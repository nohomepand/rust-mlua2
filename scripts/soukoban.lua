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

local BOXES = 1

-------------------------------------------------
-- 安全確認
-------------------------------------------------
local function inside(x, y)
    return x > 1 and x < W and y > 1 and y < H
end

local function is_empty(x, y)
    return inside(x, y) and map[y][x] == EMPTY
end

-------------------------------------------------
-- 賢いステージ生成
-------------------------------------------------
local function shuffle(tbl)
    for i = #tbl, 2, -1 do
        local j = math.random(1, i)
        tbl[i], tbl[j] = tbl[j], tbl[i]
    end
end

local function new_stage()
    ::re_create::
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

    -- ランダム壁（箱の経路を邪魔しすぎないよう控えめに）
    local fillcount = math.floor((W - 2) * (H - 2) / 8)
    local placed = 0
    while placed < fillcount do
        local x = math.random(2, W - 1)
        local y = math.random(2, H - 1)
        if map[y][x] == EMPTY then
            map[y][x] = WALL
            placed = placed + 1
        end
    end

    -- ゴール配置
    repeat
        goal.x = math.random(6, W - 5)
        goal.y = math.random(6, H - 5)
    until map[goal.y][goal.x] == EMPTY

    -- 複数箱
    local box_count = math.min(1 + math.floor(stage / 5), 4)
    local boxes = {}
    boxes[1] = {x = goal.x, y = goal.y}

    -- ゴールから逆探索で箱を配置
    for i = 2, box_count + 1 do
        local found = false
        for try = 1, 40 do
            local bx, by = boxes[i-1].x, boxes[i-1].y
            local dirs = {{1,0},{-1,0},{0,1},{0,-1}}
            shuffle(dirs)
            for _, d in ipairs(dirs) do
                local px, py = bx + d[1], by + d[2]
                local bx2, by2 = bx - d[1], by - d[2]
                if is_empty(px, py) and is_empty(bx2, by2) then
                    -- 既存の箱と重ならない
                    local overlap = false
                    for j = 1, #boxes do
                        if (boxes[j].x == px and boxes[j].y == py) or (boxes[j].x == bx2 and boxes[j].y == by2) then
                            overlap = true
                            break
                        end
                    end
                    if not overlap then
                        boxes[i] = {x = px, y = py}
                        found = true
                        break
                    end
                end
            end
            if found then break end
        end
        if not found then goto re_create end
    end

    -- 箱を配置
    for i = 2, #boxes do
        map[boxes[i].y][boxes[i].x] = BOX
    end

    -- プレイヤー配置（最後の箱の押し元）
    local last = boxes[#boxes]
    local dirs = {{1,0},{-1,0},{0,1},{0,-1}}
    shuffle(dirs)
    local placed_player = false
    for _, d in ipairs(dirs) do
        local px, py = last.x + d[1], last.y + d[2]
        if is_empty(px, py) then
            player.x = px
            player.y = py
            placed_player = true
            break
        end
    end
    if not placed_player then goto re_create end

    -- ゴールは空きに
    map[goal.y][goal.x] = EMPTY
    if player.x == goal.x and player.y == goal.y then goto re_create end
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
