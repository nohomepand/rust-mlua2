local width, height = 600, 600
local win = egui.create_window("test GUI", width, height)
local STATE_PRESS = "Pressed"

local printouts = {}
local keystates = {}
local function on_keychange(state, vk, code)
    table.insert(printouts, "KEY " .. state .. " " .. vk .. " " .. code)
    print("KEY", state, vk, code)
end

function egui.keyhandler(state, vk, code)
    if keystates[vk] ~= state then
        on_keychange(state, vk, code)
    end
    keystates[vk] = state
end

function egui.mousehandler(state, button)
    table.insert(printouts, "MOUSE " .. state .. " " .. button)
    print("MOUSE", state, button)
end

function egui.cursorhandler(x, y)
    local wx, wy = win:getx(), win:gety()
    local px, py = x - wx, y - wy
    table.insert(printouts, "CURSOR " .. px .. " " .. py)
    print("CURSOR", px, py)
end

while true do
    for i = #printouts, 1, -1 do
        win:scroll(0, win:gettextfontsize())
        win:text(0, 0, printouts[i])
        table.remove(printouts, i)
    end
    coroutine.yield()
end
