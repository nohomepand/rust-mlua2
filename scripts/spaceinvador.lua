-- スペースインベーダー風シューティングゲーム
-- 必要API: egui.create_window, win:cls, win:rect, egui.keyhandler

local width, height = 480, 640
local win = egui.create_window("Space Invader", width, height)

local player = { x = width / 2 - 20, y = height - 40, w = 40, h = 10, speed = 6 }
local bullets = {}
local invaders = {}
local enemy_bullets = {}
local invader_dir = 1
local invader_speed = 16
local invader_step = 20
local invader_timer = 0
local left_pressed, right_pressed, space_pressed = false, false, false

-- 弾避けブロック配置
local blocks = {}
local block_w, block_h = 60, 20
local block_y = player.y - 80
for i = 1, 3 do
    local bx = 60 + (i - 1) * 140
    table.insert(blocks, {x = bx, y = block_y, w = block_w, h = block_h, hp = 6})
end

-- インベーダー初期配置
local rows, cols = 5, 10
for row = 1, rows do
    for col = 1, cols do
        table.insert(invaders, {
            x = 40 + (col - 1) * 36,
            y = 40 + (row - 1) * 32,
            w = 28, h = 20, alive = true
        })
    end
end

function egui.keyhandler(state, vk, code)
    if vk == "Left" then left_pressed = (state == "Pressed") end
    if vk == "Right" then right_pressed = (state == "Pressed") end
    if vk == "Space" then space_pressed = (state == "Pressed") end
end

local function update()
    -- プレイヤー移動
    if left_pressed then player.x = math.max(player.x - player.speed, 0) end
    if right_pressed then player.x = math.min(player.x + player.speed, width - player.w) end

    -- 弾発射
    if space_pressed then
        if #bullets == 0 or (bullets[#bullets].y < player.y - 60) then
            table.insert(bullets, { x = player.x + player.w / 2 - 2, y = player.y, w = 4, h = 10, speed = 8 })
        end
    end

    -- 弾移動
    for i = #bullets, 1, -1 do
        local b = bullets[i]
        b.y = b.y - b.speed
        if b.y < -b.h then table.remove(bullets, i) end
    end

    -- 敵弾発射
    if math.random() < 0.03 then
        -- 一番下の生きているインベーダーからランダムで発射
        local candidates = {}
        for col = 1, 10 do
            local lowest = nil
            for row = 5, 1, -1 do
                local idx = (row - 1) * 10 + col
                local inv = invaders[idx]
                if inv and inv.alive then lowest = inv break end
            end
            if lowest then table.insert(candidates, lowest) end
        end
        if #candidates > 0 then
            local shooter = candidates[math.random(1, #candidates)]
            table.insert(enemy_bullets, {x = shooter.x + shooter.w/2 - 2, y = shooter.y + shooter.h, w = 4, h = 10, speed = 5})
        end
    end

    -- 敵弾移動
    for i = #enemy_bullets, 1, -1 do
        local b = enemy_bullets[i]
        b.y = b.y + b.speed
        if b.y > height then table.remove(enemy_bullets, i) end
    end

    -- インベーダー移動
    invader_timer = invader_timer + 1
    if invader_timer % 20 == 0 then
        local move_x = invader_dir * invader_speed
        local should_descend = false
        for _, inv in ipairs(invaders) do
            if inv.alive then
                inv.x = inv.x + move_x
                if inv.x < 0 or inv.x + inv.w > width then
                    should_descend = true
                end
            end
        end
        if should_descend then
            invader_dir = -invader_dir
            for _, inv in ipairs(invaders) do
                if inv.alive then
                    inv.y = inv.y + invader_step
                end
            end
        end
    end

    -- 弾とインベーダーの当たり判定
    for bi = #bullets, 1, -1 do
        local b = bullets[bi]
        for ii, inv in ipairs(invaders) do
            if inv.alive and b.x < inv.x + inv.w and b.x + b.w > inv.x and b.y < inv.y + inv.h and b.y + b.h > inv.y then
                inv.alive = false
                table.remove(bullets, bi)
                break
            end
        end
    end

    -- 弾とブロックの当たり判定
    for bi = #bullets, 1, -1 do
        local b = bullets[bi]
        for i, block in ipairs(blocks) do
            if block.hp > 0 and b.x < block.x + block.w and b.x + b.w > block.x and b.y < block.y + block.h and b.y + b.h > block.y then
                block.hp = block.hp - 1
                table.remove(bullets, bi)
                break
            end
        end
    end

    -- 敵弾とブロックの当たり判定
    for ei = #enemy_bullets, 1, -1 do
        local b = enemy_bullets[ei]
        for i, block in ipairs(blocks) do
            if block.hp > 0 and b.x < block.x + block.w and b.x + b.w > block.x and b.y < block.y + block.h and b.y + b.h > block.y then
                block.hp = block.hp - 1
                table.remove(enemy_bullets, ei)
                break
            end
        end
    end

    -- 敵弾とプレイヤーの当たり判定
    for ei = #enemy_bullets, 1, -1 do
        local b = enemy_bullets[ei]
        if b.x < player.x + player.w and b.x + b.w > player.x and b.y < player.y + player.h and b.y + b.h > player.y then
            -- プレイヤーに当たったらゲームオーバー処理等（ここでは削除のみ）
            table.remove(enemy_bullets, ei)
        end
    end
end

local function draw()
    win:cls(0, 0, 0)
    -- プレイヤー
    win:rect(player.x, player.y, player.x + player.w, player.y + player.h, 0, 255, 0)
    -- 弾
    for _, b in ipairs(bullets) do
        win:rect(b.x, b.y, b.x + b.w, b.y + b.h, 255, 255, 0)
    end
    -- 敵弾
    for _, b in ipairs(enemy_bullets) do
        win:rect(b.x, b.y, b.x + b.w, b.y + b.h, 255, 0, 255)
    end
    -- ブロック
    for _, block in ipairs(blocks) do
        if block.hp > 0 then
            win:rect(block.x, block.y, block.x + block.w, block.y + block.h, 128, 255, 128)
        end
    end
    -- インベーダー
    for _, inv in ipairs(invaders) do
        if inv.alive then
            win:rect(inv.x, inv.y, inv.x + inv.w, inv.y + inv.h, 0, 179, 255)
        end
    end
end

while true do
    local begin = hpc()
    update()
    draw()
    local asleep = hpc() - begin - 0.016
    if asleep > 0 then sleep(asleep) end
    -- egui.sleep(0.016)
    coroutine.yield()
end
