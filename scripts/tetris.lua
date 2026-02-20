local fpswaiter = require "scripts.mod.fpswaiter"
local waiter = fpswaiter.fpswaiter:new()
math.randomseed(os.time())

local CELL = 20
local W = 16
local H = 25

local win = egui.create_window("Tetris", W * CELL, H * CELL)

local field = {}
local score = 0
local drop_timer = 0
local drop_interval = 90
local gameover = false
local game_pausing = false

-------------------------------------------------
-- フィールド初期化
-------------------------------------------------
for y = 1, H do
    field[y] = {}
    for x = 1, W do
        field[y][x] = 0
    end
end

local midiout = nil
for _, port in ipairs(midi.midiout()) do
    midiout = midi.openoutput(port)
    break
end

-------------------------------------------------
-- ミノ定義
-------------------------------------------------
local pieces = {
    { color = { 0, 255, 255 }, shape = { { 1, 1, 1, 1 } } },
    { color = { 255, 255, 0 }, shape = { { 1, 1 }, { 1, 1 } } },
    { color = { 128, 0, 128 }, shape = { { 0, 1, 0 }, { 1, 1, 1 } } },
    { color = { 0, 255, 0 },   shape = { { 0, 1, 1 }, { 1, 1, 0 } } },
    { color = { 255, 0, 0 },   shape = { { 1, 1, 0 }, { 0, 1, 1 } } },
    { color = { 0, 0, 255 },   shape = { { 1, 0, 0 }, { 1, 1, 1 } } },
    { color = { 255, 128, 0 }, shape = { { 0, 0, 1 }, { 1, 1, 1 } } },
}

local current = {}


-------------------------------------------------
-- 衝突判定
-------------------------------------------------
local function collision(px, py, shape)
    for y = 1, #shape do
        for x = 1, #shape[y] do
            if shape[y][x] == 1 then
                local fx = px + x - 1
                local fy = py + y - 1

                if fx < 1 or fx > W or fy > H then
                    return true
                end
                if fy >= 1 and field[fy][fx] ~= 0 then
                    return true
                end
            end
        end
    end
    return false
end

-------------------------------------------------
-- 新ミノ生成
-------------------------------------------------
local function new_piece()
    local p = pieces[math.random(#pieces)]
    current = {
        x = 4,
        y = 1,
        shape = p.shape,
        color = p.color
    }

    if collision(current.x, current.y, current.shape) then
        gameover = true
    end
end

-------------------------------------------------
-- 固定
-------------------------------------------------
local function lock_piece()
    for y = 1, #current.shape do
        for x = 1, #current.shape[y] do
            if current.shape[y][x] == 1 then
                local fx = current.x + x - 1
                local fy = current.y + y - 1
                if fy >= 1 then
                    field[fy][fx] = { 127, 127, 127 } -- current.color
                end
            end
        end
    end
end

-------------------------------------------------
-- ライン消去
-------------------------------------------------
local function clear_lines()
    local lines = 0
    local y = H

    while y >= 1 do
        local full = true

        for x = 1, W do
            if field[y][x] == 0 then
                full = false
                break
            end
        end

        if full then
            table.remove(field, y)

            local row = {}
            for x = 1, W do row[x] = 0 end
            table.insert(field, 1, row)

            lines = lines + 1
            -- ★ yを減らさない（同じ位置を再チェック）
        else
            y = y - 1
        end
    end

    if lines > 0 then
        score = score + lines * 100
        drop_interval = math.max(5, 30 - math.floor(score / 500))
    end
end

-------------------------------------------------
-- 回転
-------------------------------------------------
local function rotate(shape)
    local new = {}
    for x = 1, #shape[1] do
        new[x] = {}
        for y = #shape, 1, -1 do
            table.insert(new[x], shape[y][x])
        end
    end
    return new
end

-------------------------------------------------
-- 描画
-------------------------------------------------
local function clear_screen()
    win:cls(0, 0, 0)
end

local function draw()
    win:rect(0, 0, W * CELL - 1, H * CELL - 1, 255, 255, 255)

    for y = 1, H do
        for x = 1, W do
            local cell = field[y][x]
            if cell ~= 0 then
                win:fillrect((x - 1) * CELL, (y - 1) * CELL, x * CELL, y * CELL,
                    cell[1], cell[2], cell[3])
            end
        end
    end

    -- 現在ミノ
    for y = 1, #current.shape do
        for x = 1, #current.shape[y] do
            if current.shape[y][x] == 1 then
                win:fillrect(
                    (current.x + x - 2) * CELL,
                    (current.y + y - 2) * CELL,
                    (current.x + x - 1) * CELL,
                    (current.y + y - 1) * CELL,
                    current.color[1],
                    current.color[2],
                    current.color[3]
                )
            end
        end
    end
    
    win:text(0, 0, score)
end

-------------------------------------------------
-- 更新
-------------------------------------------------
local function update()
    if gameover then return end

    drop_timer = drop_timer + 1

    if drop_timer >= drop_interval * 2 then
        drop_timer = 0
        if not collision(current.x, current.y + 1, current.shape) then
            current.y = current.y + 1
        else
            lock_piece()
            clear_lines()
            new_piece()
        end
    end
end

-------------------------------------------------
-- MIDI
-------------------------------------------------
local last_step = -1
local active_notes = {}

-- 初回だけ音色設定
local initialized = false

local function note_on(ch, note, vel)
    midiout:send(0x90 + ch, note, vel)
end

local function note_off(ch, note)
    midiout:send(0x80 + ch, note, 0)
end

local function program_change(ch, prog)
    midiout:send(0xC0 + ch, prog)
end

local function playmidi(score)
    if not midiout or not midiout.send then return end
    if game_pausing then return end

    if not initialized then
        -- 0=Acoustic Grand, 33=Finger Bass, 48=Strings
        program_change(0, 0)
        program_change(1, 33)
        program_change(2, 48)
        initialized = true
    end

    local now = hpc()

    -- スコアでBPM上昇
    local base_bpm = 140
    local bpm = base_bpm + math.floor((score or 0) / 1000)
    local beat = 60 / bpm

    -- 16分単位
    local step = math.floor(now / (beat / 4))
    if step == last_step then return end
    last_step = step

    -- ===== メロディ（A minor） =====
    local melody = {
        69, 76, 74, 72, 74, 76, 74, 72,
        69, 69, 72, 74, 76, 74, 72, 74,
        76, 81, 79, 77, 79, 81, 79, 77,
        76, 76, 74, 72, 74, 76, 74, 72
    }

    -- ===== ベース =====
    local bass = {
        45, 45, 45, 45, 45, 45, 45, 45,
        41, 41, 41, 41, 41, 41, 41, 41,
        38, 38, 38, 38, 38, 38, 38, 38,
        41, 41, 41, 41, 41, 41, 41, 41
    }

    -- ===== 和音 =====
    local chords = {
        { 57, 60, 64 }, -- Am
        { 57, 60, 64 },
        { 53, 57, 60 }, -- F
        { 55, 59, 62 }, -- G
    }

    local idx = (step % #melody) + 1
    local note_mel = melody[idx]
    local note_bass = bass[idx]

    -- 既存ノート全部OFF
    for _, n in ipairs(active_notes) do
        note_off(n.ch, n.note)
    end
    active_notes = {}

    -- メロディ（ch0）
    note_on(0, note_mel, 110)
    table.insert(active_notes, { ch = 0, note = note_mel })

    -- ベース（ch1）
    if step % 4 == 0 then
        note_on(1, note_bass, 100)
        table.insert(active_notes, { ch = 1, note = note_bass })
    end

    -- 和音（ch2）4拍ごと
    if step % 16 == 0 then
        local chord = chords[(math.floor(step / 16) % #chords) + 1]
        for _, n in ipairs(chord) do
            note_on(2, n, 60)
            table.insert(active_notes, { ch = 2, note = n })
        end
    end

    -- ===== ドラム（ch9 = MIDI 10）=====
    -- キック
    if step % 4 == 0 then
        note_on(9, 36, 120)
    end
    -- スネア
    if step % 8 == 4 then
        note_on(9, 38, 100)
    end
    -- ハイハット
    if step % 2 == 0 then
        note_on(9, 42, 70)
    end
end

-------------------------------------------------
-- 入力
-------------------------------------------------
local keypressed_state = {
    _check = function(self, ...)
        local tmp = { ... }
        for _, vk in ipairs(tmp) do
            if self[vk] then
                return true
            end
        end
        return false
    end,
}
local keyreleased_state = {}
function egui.keyhandler(state, vk, code)
    if state == "Pressed" then
        keypressed_state[vk] = true
    else
        keyreleased_state[vk] = true
        keypressed_state[vk] = nil
    end
end

local _last_key_handled = 0
local function handle_keyinput()
    if hpc() - _last_key_handled < 1 / 15 then return end
    _last_key_handled = hpc()

    if keypressed_state:_check("Left") then
        -- if keypressed_state["Left"] then
        if not collision(current.x - 1, current.y, current.shape) then
            current.x = current.x - 1
        end
    end

    if keypressed_state:_check("Right") then
        -- if keypressed_state["Right"] then
        if not collision(current.x + 1, current.y, current.shape) then
            current.x = current.x + 1
        end
    end

    if keypressed_state:_check("Down") then
        -- if keypressed_state["Down"] then
        if not collision(current.x, current.y + 1, current.shape) then
            current.y = current.y + 1
        end
    end

    -- if keyreleased_state:_check("Up", "Space") then
    if keypressed_state["Up"] or keypressed_state["Space"] then
        keypressed_state["Up"] = nil
        keypressed_state["Space"] = nil
        local r = rotate(current.shape)
        if not collision(current.x, current.y, r) then
            current.shape = r
        end
    end

    if keyreleased_state["Escape"] then
        keyreleased_state["Escape"] = nil
        game_pausing = true
    end
end

local function pause_game()
    if keyreleased_state["Escape"] then
        keyreleased_state["Escape"] = nil
        game_pausing = false
    end
    win:text(0, win:gettextfontsize(), "Pausing (ESC to return game)")
    for _, n in ipairs(active_notes) do
        note_off(n.ch, n.note)
    end
end

-------------------------------------------------
-- 開始
-------------------------------------------------
new_piece()

while true do
    clear_screen()
    draw()
    if not game_pausing then
        handle_keyinput()
        update()
    else
        pause_game()
    end
    playmidi()
    sleep(0.01)
    coroutine.yield()
end
