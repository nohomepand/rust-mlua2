local width, height = 600, 600
local win = egui.create_window("Piano", width, height)
local keystate = {}
local out

local first_out_port = nil
for i, port in ipairs(midi.midiout()) do
    print('out', i, port)
    if first_out_port == nil then
        first_out_port = port
    end
end

if first_out_port == nil then
    print("No MIDI Out port")
    return
else
    out = midi.openoutput(first_out_port)
end

local pitches = {}
pitches["Z"] = 60 + 0       -- C4
    pitches["S"] = 60 + 1   -- C#4
pitches["X"] = 60 + 2       -- D4
    pitches["D"] = 60 + 3   -- D#4
pitches["C"] = 60 + 4       -- E4
pitches["V"] = 60 + 5       -- F4
    pitches["G"] = 60 + 6   -- F#4
pitches["B"] = 60 + 7       -- G4
    pitches["H"] = 60 + 8   -- G#4
pitches["N"] = 60 + 9       -- A4
    pitches["J"] = 60 + 10  -- A#4
pitches["M"] = 60 + 11      -- B4
pitches["Comma"] = 60 + 12  -- C5
-- pitches["Period"] = 60 +

local function on_keychange(state, vk, code)
    local pitch = pitches[vk]
    if pitch == nil then return end
    
    if state == "Pressed" then
        out:send(0x90, pitch, 100) -- ノートオン
    else
        out:send(0x80, pitch, 100) -- ノートオフ
    end
end

function egui.keyhandler(state, vk, code)
    if keystate[vk] ~= state then
        on_keychange(state, vk, code)
    end
    keystate[vk] = state
end

-- out:send(0xC0, 24) -- 0xC0: Program Change, 24 = MIDI program number 25 (0-based)
win:text(0, 0, "Z(C4)~Comma(C5)")
while true do
    coroutine.yield()
end