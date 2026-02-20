local midiplayer = require"scripts.mod.midiplayer"
-- local player = midiplayer:new("test1.mid")
-- local player = midiplayer:new("test3.mid")
-- local player = midiplayer:new("ED5_sougen_Field.mid")
-- local player = midiplayer:new("ED5OP2.mid")

local player = midiplayer:new(arg[1] or "ED5_sougen_Field.mid")

local midiout = nil
for _, port in ipairs(midi.midiout()) do
    midiout = midi.openoutput(port)
end

while true do
    player:play(midiout)
    if not player:isplaying() then
        player:reset()
    end
    sleep(0.01)
    print(player:isplaying(), player.last_index)
    coroutine.yield()
end
