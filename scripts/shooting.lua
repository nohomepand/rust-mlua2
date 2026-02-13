-- シンプルなシューティングゲーム
-- 必要なAPI: egui.create_window, win:cls, win:rect, egui.keyhandler

local width, height = 480, 640
local win = egui.create_window("Shooting Game", width, height)

local player = { x = width / 2, y = height - 40, w = 40, h = 10, speed = 6, life = 10000 }
local bullets = {}
local enemies = {}
local enemy_bullets = {}
local enemy_timer = 0
local left_pressed, right_pressed, space_pressed = false, false, false

local midiout
local first_out_port = nil
for i, port in ipairs(midi.midiout()) do
    print('out', i, port)
    if first_out_port == nil then
        first_out_port = port
    end
end

if first_out_port == nil then
    print("No MIDI Out port")
    midiout = nil
else
    midiout = midi.openoutput(first_out_port)
end

function egui.keyhandler(state, vk, code)
    if vk == "Left" then left_pressed = (state == "Pressed") end
    if vk == "Right" then right_pressed = (state == "Pressed") end
    if vk == "Space" then space_pressed = (state == "Pressed") end
end

local function spawn_enemy()
    local ex = math.random(20, width - 20)
    table.insert(enemies, { x = ex, y = 0, w = 30, h = 20, speed = math.random() * 8 + 2, shoot_timer = 0 })
end

local function update()
    -- プレイヤー移動
    if left_pressed then player.x = math.max(player.x - player.speed, 0) end
    if right_pressed then player.x = math.min(player.x + player.speed, width - player.w) end

    -- 弾発射
    if space_pressed then
        if #bullets == 0 or (bullets[#bullets].y < player.y - 10) then
            table.insert(bullets, { x = player.x + player.w / 2 - 2, y = player.y, w = 4, h = 10, speed = 8 })
            -- 自分の弾発射時にドラム音（バスドラム）
            if midiout then
                -- チャンネル10, バスドラム(35), ベロシティ100
                midiout:send(0x99, 35, 100)
            end
        end
    end

    -- 弾移動
    for i = #bullets, 1, -1 do
        local b = bullets[i]
        b.y = b.y - b.speed
        if b.y < -b.h then table.remove(bullets, i) end
    end

    -- 敵生成
    enemy_timer = enemy_timer + 1
    if enemy_timer % 60 == 0 then spawn_enemy() end

    -- 敵移動・敵弾発射
    for i = #enemies, 1, -1 do
        local e = enemies[i]
        e.y = e.y + e.speed
        -- 敵弾発射タイマー
        e.shoot_timer = (e.shoot_timer or 0) + 1
        if e.shoot_timer > 6 and e.y < height / 2 then
            -- プレイヤーに向けて弾を撃つ
            local px = player.x + player.w / 2
            local py = player.y
            local ex = e.x + e.w / 2
            local ey = e.y + e.h
            local dx = px - ex
            local dy = py - ey
            local len = math.sqrt(dx * dx + dy * dy)
            if len > 0 then
                local speed = 4
                local vx = dx / len * speed
                local vy = dy / len * speed
                table.insert(enemy_bullets, { x = ex - 2, y = ey, w = 4, h = 10, vx = vx, vy = vy })
            end
            e.shoot_timer = 0
        end
        if e.y > height then table.remove(enemies, i) end
    end

    -- 敵弾移動
    for i = #enemy_bullets, 1, -1 do
        local b = enemy_bullets[i]
        b.x = b.x + b.vx
        b.y = b.y + b.vy
        if b.x < -b.w or b.x > width or b.y > height or b.y < -b.h then
            table.remove(enemy_bullets, i)
        end
    end

    -- 弾と敵の当たり判定
    for bi = #bullets, 1, -1 do
        local b = bullets[bi]
        for ei = #enemies, 1, -1 do
            local e = enemies[ei]
            if b.x < e.x + e.w and b.x + b.w > e.x and b.y < e.y + e.h and b.y + b.h > e.y then
                table.remove(bullets, bi)
                table.remove(enemies, ei)
                break
            end
        end
    end

    -- 敵弾とプレイヤーの当たり判定
    for i = #enemy_bullets, 1, -1 do
        local b = enemy_bullets[i]
        if b.x < player.x + player.w and b.x + b.w > player.x and b.y < player.y + player.h and b.y + b.h > player.y then
            player.life = player.life - 10
            -- 敵弾着弾時にドラム音（スネアドラム）
            if midiout then
                -- チャンネル10, スネアドラム(38), ベロシティ100
                midiout:send(0x99, 38, 100)
            end
            table.remove(enemy_bullets, i)
        end
    end
end

local function draw()
    win:cls(0, 0, 0)
    -- プレイヤー
    win:text(0, 0, player.life)
    win:rect(player.x, player.y, player.x + player.w, player.y + player.h, 0, 255, 0)
    -- 弾
    for _, b in ipairs(bullets) do
        win:rect(b.x, b.y, b.x + b.w, b.y + b.h, 255, 255, 0)
    end
    -- 敵
    for _, e in ipairs(enemies) do
        win:rect(e.x, e.y, e.x + e.w, e.y + e.h, 255, 0, 0)
    end
    -- 敵弾
    for _, b in ipairs(enemy_bullets) do
        win:rect(b.x, b.y, b.x + b.w, b.y + b.h, 0, 255, 255)
    end
end

while true do
    update()
    draw()
    -- sleep(0.016) -- 60FPS
    coroutine.yield()
end
