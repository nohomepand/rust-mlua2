-- MIDIモジュールのテスト
print('--- midi.midiin() ---')
for i, port in ipairs(midi.midiin()) do
    print('in', i, port)
end

print('--- midi.midiout() ---')
local first_out_port = nil
for i, port in ipairs(midi.midiout()) do
    print('out', i, port)
    if first_out_port == nil then
        first_out_port = port
    end
end


if first_out_port ~= nil then
    -- ここから先はポート名が分かる場合のみ
    local out = midi.openoutput(first_out_port)
    -- プログラムチェンジでギター音色（例: 25 = Acoustic Guitar (nylon)）に変更
    out:send(0xC0, 24) -- 0xC0: Program Change, 24 = MIDI program number 25 (0-based)
    -- ピアノソナタK.545冒頭のメロディ（簡易版）
    -- Mozart: Piano Sonata No.16 in C Major, K.545, first theme
    local melody = {
        {60, 0.4}, {64, 0.4}, {67, 0.4}, {72, 0.4}, {71, 0.4}, {69, 0.4}, {67, 0.4},
        {69, 0.4}, {71, 0.4}, {72, 0.4}, {74, 0.4}, {76, 0.4}, {77, 0.4}, {76, 0.4},
        {74, 0.4}, {72, 0.4}, {71, 0.4}, {69, 0.4}, {67, 0.4}, {69, 0.4}, {71, 0.4},
        {72, 0.8},
    }
    -- モーツァルト「きらきら星変奏曲」冒頭のメロディをMIDIで送信
    local melody = {
        {60, 0.4}, {60, 0.4}, {67, 0.4}, {67, 0.4}, {69, 0.4}, {69, 0.4}, {67, 0.8},
        {65, 0.4}, {65, 0.4}, {64, 0.4}, {64, 0.4}, {62, 0.4}, {62, 0.4}, {60, 0.8},
    }

    for _, note in ipairs(melody) do
        local pitch, duration = note[1], note[2]
        out:send(0x90, pitch, 100) -- ノートオン
        local _end = os.clock() + duration
        while os.clock() < _end do
            -- sleep(0.001)
            coroutine.yield()
        end
        out:send(0x80, pitch, 100) -- ノートオフ
    end
end
print("end")