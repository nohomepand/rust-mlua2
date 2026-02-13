local FPS            = 60

------------------------------------------------------------
-- BGM（MIDIループ再生）
------------------------------------------------------------
local bgm_notes = {60, 62, 64, 67, 69, 67, 64, 62} -- 簡易BGM
local bgm_index = 1
local bgm_timer = 0
local bgm_interval = FPS / 4  -- 4分音符

local function play_bgm()
    if not midiout then return end
    bgm_timer = bgm_timer + 1
    if bgm_timer >= bgm_interval then
        bgm_timer = 0
        local note = bgm_notes[bgm_index]
        midiout:send(0x90, note, 80) -- ノートオン
        midiout:send(0x80, note, 0)  -- ノートオフ（即時）
        bgm_index = bgm_index % #bgm_notes + 1
    end
end
------------------------------------------------------------
-- GRADIUS SFC RECREATION (Lua + egui)
------------------------------------------------------------

------------------------------------------------------------
-- 定数
------------------------------------------------------------
local WIDTH          = 600 -- 256
local HEIGHT         = 600 -- 224

local win            = egui.create_window("GRADIUS", WIDTH, HEIGHT)

------------------------------------------------------------
-- MIDI 初期化
------------------------------------------------------------
local midiout        = nil
local first_out_port = nil
for i, port in ipairs(midi.midiout()) do
    if first_out_port == nil then
        first_out_port = port
    end
end

if first_out_port ~= nil then
    midiout = midi.openoutput(first_out_port)
end


local function sfx_shot()
    if midiout then
        midiout:send(0x99, 42, 80)
    end
end

local function sfx_explosion()
    if midiout then
        midiout:send(0x99, 35, 120)
    end
end

local keys = {}


-- 敵弾
local enemy_bullets = {}
local enemy_shot_timer = 0

local function spawn_enemy_bullet(ex, ey, px, py)
    -- 自機狙い方向
    local dx, dy = px - ex, py - ey
    local len = math.sqrt(dx*dx + dy*dy)
    if len < 1 then len = 1 end
    local speed = 3
    table.insert(enemy_bullets, {
        x = ex, y = ey,
        vx = dx/len * speed,
        vy = dy/len * speed
    })
end
function egui.keyhandler(state, vk, code)
    keys[vk] = state == "Pressed"
end

local function key(vk)
    return keys[vk] == true
end

------------------------------------------------------------
-- プレイヤー
------------------------------------------------------------
local player = {
    x = 40,
    y = HEIGHT / 2,
    speed = 5,
    lives = 3,
    invincible = 0
}

------------------------------------------------------------
-- ショット
------------------------------------------------------------
local shots = {}
local shot_cool = 0

local function spawn_shot()
    table.insert(shots, {
        x = player.x + 10,
        y = player.y,
        vx = 5
    })
    sfx_shot()
end

------------------------------------------------------------
-- 敵
------------------------------------------------------------
local enemies = {}
local enemy_timer = 0

local function spawn_enemy()
    table.insert(enemies, {
        x = WIDTH + 10,
        y = math.random(20, HEIGHT - 20),
        vx = -2,
        hp = 1,
        shot_cool = math.random(30, 90)
    })
end

------------------------------------------------------------
-- 衝突判定
------------------------------------------------------------
local function hit(ax, ay, bx, by, r)
    return math.abs(ax - bx) < r and math.abs(ay - by) < r
end

------------------------------------------------------------
-- スコア
------------------------------------------------------------
local score = 0

------------------------------------------------------------
-- ボス
------------------------------------------------------------
local boss = nil
local boss_spawned = false

local function spawn_boss()
    boss = {
        x = WIDTH - 40,
        y = HEIGHT / 2,
        hp = 50
    }
end

------------------------------------------------------------
-- 更新処理
------------------------------------------------------------
local function update()
    play_bgm()
    -- プレイヤー移動
    if key("Left") then player.x = player.x - player.speed end  -- ←
    if key("Right") then player.x = player.x + player.speed end -- →
    if key("Up") then player.y = player.y - player.speed end    -- ↑
    if key("Down") then player.y = player.y + player.speed end  -- ↓

    -- 画面制限
    if player.x < 10 then player.x = 10 end
    if player.x > WIDTH - 10 then player.x = WIDTH - 10 end
    if player.y < 10 then player.y = 10 end
    if player.y > HEIGHT - 10 then player.y = HEIGHT - 10 end


    -- N-wayショット
    if shot_cool > 0 then shot_cool = shot_cool - 1 end
    local nway = math.max(1, math.floor(score / 1000) + 1)
    if key("Space") and shot_cool <= 0 then
        local spread = math.pi / 6  -- 30度範囲
        local base_angle = 0
        if nway > 1 then base_angle = -spread/2 end
        for i = 1, nway do
            local angle = base_angle + spread * (i-1)/(math.max(1,nway-1))
            table.insert(shots, {
                x = player.x + 10,
                y = player.y,
                vx = 5 * math.cos(angle),
                vy = 5 * math.sin(angle)
            })
        end
        sfx_shot()
        shot_cool = 2
    end

    -- ショット更新
    for i = #shots, 1, -1 do
        local s = shots[i]
        s.x = s.x + (s.vx or 5)
        s.y = s.y + (s.vy or 0)
        if s.x > WIDTH or s.x < 0 or s.y < 0 or s.y > HEIGHT then
            table.remove(shots, i)
        end
    end

    -- 敵出現
    enemy_timer = enemy_timer + 1
    if enemy_timer > 60 and not boss_spawned then
        spawn_enemy()
        enemy_timer = 0
    end

    -- 敵更新
    for i = #enemies, 1, -1 do
        local e = enemies[i]
        e.x = e.x + e.vx
        -- 敵弾発射
        e.shot_cool = e.shot_cool - 1
        if e.shot_cool <= 0 then
            spawn_enemy_bullet(e.x, e.y, player.x, player.y)
            e.shot_cool = math.random(60, 120)
        end
        -- プレイヤー衝突
        if hit(player.x, player.y, e.x, e.y, 8) and player.invincible <= 0 then
            player.lives = player.lives - 1
            player.invincible = 120
            sfx_explosion()
        end
        -- ショット衝突
        for j = #shots, 1, -1 do
            local s = shots[j]
            if hit(s.x, s.y, e.x, e.y, 8) then
                e.hp = e.hp - 1
                table.remove(shots, j)
                if e.hp <= 0 then
                    score = score + 100
                    sfx_explosion()
                    table.remove(enemies, i)
                end
                break
            end
        end
        if e.x < -20 then
            table.remove(enemies, i)
        end
    end

    -- 敵弾更新
    for i = #enemy_bullets, 1, -1 do
        local b = enemy_bullets[i]
        b.x = b.x + b.vx
        b.y = b.y + b.vy
        -- 自機当たり
        if hit(player.x, player.y, b.x, b.y, 8) and player.invincible <= 0 then
            player.invincible = 60
            score = math.max(0, score - 100)
            sfx_explosion()
            table.remove(enemy_bullets, i)
        elseif b.x < 0 or b.x > WIDTH or b.y < 0 or b.y > HEIGHT then
            table.remove(enemy_bullets, i)
        end
    end

    -- ボス出現
    if score > 20000 and not boss_spawned then
        spawn_boss()
        boss_spawned = true
    end

    -- ボス更新
    if boss then
        -- ボス被弾
        for j = #shots, 1, -1 do
            local s = shots[j]
            if boss and hit(s.x, s.y, boss.x, boss.y, 20) then
                boss.hp = boss.hp - 1
                table.remove(shots, j)
                if boss.hp <= 0 then
                    score = score + 5000
                    sfx_explosion()
                    boss = nil
                end
            end
        end
    end

    -- 無敵時間
    if player.invincible > 0 then
        player.invincible = player.invincible - 1
    end
end

------------------------------------------------------------
-- 描画処理
------------------------------------------------------------
local function draw()
    win:cls(0, 0, 20)

    -- 星背景
    for i = 1, 50 do
        local x = (i * 37 + os.clock() * 50) % WIDTH
        local y = (i * 53) % HEIGHT
        win:point(x, y, 255, 255, 255)
    end

    -- プレイヤー
    if player.invincible % 4 < 2 then
        win:fillrect(player.x - 4, player.y - 4, player.x + 4, player.y + 4, 0, 255, 255)
    end

    -- ショット
    for _, s in ipairs(shots) do
        win:fillrect(s.x - 2, s.y - 1, s.x + 2, s.y + 1, 255, 255, 0)
    end
    -- 敵弾
    for _, b in ipairs(enemy_bullets) do
        win:fillrect(b.x - 2, b.y - 2, b.x + 2, b.y + 2, 255, 128, 0)
    end

    -- 敵
    for _, e in ipairs(enemies) do
        win:fillrect(e.x - 6, e.y - 6, e.x + 6, e.y + 6, 255, 0, 0)
    end

    -- ボス
    if boss then
        win:fillrect(boss.x - 20, boss.y - 20, boss.x + 20, boss.y + 20, 200, 0, 200)
    end

    -- UI
    win:fillrect(0, 0, WIDTH, 12, 0, 0, 0)
    win:text(0, 0, string.format("SCORE: %d", score))
    win:text(120, 0, string.format("N-WAY: %d", math.max(1, math.floor(score/1000)+1)))
end

------------------------------------------------------------
-- メインループ
------------------------------------------------------------
while true do
    update()
    draw()
    coroutine.yield()
end
