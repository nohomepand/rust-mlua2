local midiplayer   = {}
midiplayer.__index = midiplayer

local band         = bit.band
local bor          = bit.bor
local lshift       = bit.lshift

-------------------------------------------------
-- 可変長整数読み取り
-------------------------------------------------
local function read_varlen(data, pos)
    local value = 0
    while true do
        local b = data:byte(pos)
        value = bor(lshift(value, 7), band(b, 0x7F))
        pos = pos + 1
        if band(b, 0x80) == 0 then break end
    end
    return value, pos
end

-------------------------------------------------
-- big endian 4byte
-------------------------------------------------
local function read_u32(data, pos)
    local b1, b2, b3, b4 = data:byte(pos, pos + 3)
    local v =
        bor(
            lshift(b1, 24),
            bor(
                lshift(b2, 16),
                bor(lshift(b3, 8), b4)
            )
        )
    return v, pos + 4
end

-------------------------------------------------
-- big endian 2byte
-------------------------------------------------
local function read_u16(data, pos)
    local b1, b2 = data:byte(pos, pos + 1)
    local v = bor(lshift(b1, 8), b2)
    return v, pos + 2
end

-------------------------------------------------
-- コンストラクタ
-------------------------------------------------
function midiplayer:new(path)
    local obj = setmetatable({}, self)

    obj.events = {}
    obj.ticks_per_qn = 480
    obj.tempo = 500000 -- default 120 BPM
    obj.start_time = hpc()
    obj.last_index = 1
    obj.tempos = { {tick=0, tempo=500000, abs_time=0} } -- tick, tempo, abs_time

    local f = assert(io.open(path, "rb"))
    local data = f:read("*all")
    f:close()

    local pos = 1

    -- ヘッダ
    assert(data:sub(pos, pos + 3) == "MThd")
    pos = pos + 4

    local header_len
    header_len, pos = read_u32(data, pos)

    local format
    format, pos = read_u16(data, pos)

    local tracks
    tracks, pos = read_u16(data, pos)

    obj.ticks_per_qn, pos = read_u16(data, pos)

    pos = pos + (header_len - 6)

    -------------------------------------------------
    -- トラック読み取り（format 0/1対応）
    -------------------------------------------------
    for t = 1, tracks do
        assert(data:sub(pos, pos + 3) == "MTrk")
        pos = pos + 4

        local length
        length, pos = read_u32(data, pos)
        local track_end = pos + length

        local tick = 0
        local running_status = nil

        while pos < track_end do
            local delta
            delta, pos = read_varlen(data, pos)
            tick = tick + delta

            local status = data:byte(pos)

            if status < 0x80 then
                status = running_status
            else
                pos = pos + 1
                running_status = status
            end

            local ev = { tick = tick }

            if status == 0xFF then
                local meta_type = data:byte(pos)
                pos = pos + 1
                local len
                len, pos = read_varlen(data, pos)

                if meta_type == 0x51 then
                    -- tempo
                    local tempo =
                        bor(
                            lshift(data:byte(pos), 16),
                            bor(
                                lshift(data:byte(pos + 1), 8),
                                data:byte(pos + 2)
                            )
                        )
                    ev.tempo = tempo
                    -- テンポイベントとして記録
                    table.insert(obj.events, {tick=tick, tempo=tempo, is_tempo=true})
                end

                pos = pos + len
            elseif status == 0xF0 then
                -- SysEx
                local len
                len, pos = read_varlen(data, pos)
                local sysex_data = {data:byte(pos, pos + len - 1)}
                pos = pos + len
                ev.status = 0xF0
                ev.sysex_data = sysex_data
                table.insert(obj.events, ev)
            else
                local event_type = band(status, 0xF0)
                local channel    = band(status, 0x0F)

                local p1         = data:byte(pos); pos = pos + 1
                local p2         = 0

                if event_type ~= 0xC0 and event_type ~= 0xD0 then
                    p2 = data:byte(pos); pos = pos + 1
                end

                ev.status = event_type
                ev.channel = channel
                ev.p1 = p1
                ev.p2 = p2

                table.insert(obj.events, ev)
            end
        end
    end

    table.sort(obj.events, function(a, b) return a.tick < b.tick end)

    -- テンポマップ構築
    obj.tempos = { {tick=0, tempo=500000, abs_time=0} }
    local last_tick = 0
    local last_time = 0
    local last_tempo = 500000
    for _, ev in ipairs(obj.events) do
        if ev.tempo then
            local dtick = ev.tick - last_tick
            local dt = (dtick * last_tempo) / (obj.ticks_per_qn * 1000000)
            last_time = last_time + dt
            table.insert(obj.tempos, {tick=ev.tick, tempo=ev.tempo, abs_time=last_time})
            last_tick = ev.tick
            last_tempo = ev.tempo
        end
    end

    return obj
end

-------------------------------------------------
-- 再生
-------------------------------------------------
function midiplayer:tick_to_time(tick)
    local tempos = self.tempos
    local t = tempos[1]
    for i = 2, #tempos do
        if tick < tempos[i].tick then
            local dtick = tick - t.tick
            return t.abs_time + (dtick * t.tempo) / (self.ticks_per_qn * 1000000)
        end
        t = tempos[i]
    end
    -- 最後のテンポ以降
    local dtick = tick - t.tick
    return t.abs_time + (dtick * t.tempo) / (self.ticks_per_qn * 1000000)
end

function midiplayer:play(midiout)
    if not midiout or not midiout.send then return end

    local now = hpc()
    local elapsed = now - self.start_time

    while self.last_index <= #self.events do
        local ev = self.events[self.last_index]
        if ev.is_tempo then
            self.last_index = self.last_index + 1
        else
            local ev_time = self:tick_to_time(ev.tick)
            if ev_time > elapsed then
                break
            end

            if ev.status == 0x90 then
                midiout:send(0x90 + ev.channel, ev.p1, ev.p2)
            elseif ev.status == 0x80 then
                midiout:send(0x80 + ev.channel, ev.p1, ev.p2)
            elseif ev.status == 0xC0 then
                midiout:send(0xC0 + ev.channel, ev.p1)
            elseif ev.status == 0xF0 and midiout.send_sysex and ev.sysex_data then
                midiout:send(0xF0, table.unpack(ev.sysex_data))
            end

            self.last_index = self.last_index + 1
        end
    end
end

function midiplayer:isplaying()
    return self.last_index <= #self.events
end

function midiplayer:reset()
    self.start_time = hpc()
    self.last_index = 1
end

return midiplayer
