local width, height = 600, 600
local win = egui.create_window("test GUI", width, height)

local Entity = {x = 0, y = 0, selected = false}
function Entity:new(x, y, selected)
    local o = {x = x, y = y, selected = selected}
    setmetatable(o, self)
    self.__index = self
    return o
end

function Entity:update()
    if not self.selected then
        return
    end
    
    local keys = getkeys()
    
end

local keystates = {}
local function on_keychange(...)
    print("KEY", ...)
end
function egui.keyhandler(state, vk, code)
    if keystates[vk] ~= state then
        on_keychange(state, vk, code)
    end
    keystates[vk] = state
end

function egui.mousehandler(...)
    print("MOUSE", ...)
end

function egui.cursorhandler(...)
    print("CURSOR", ...)
end

while true do
    
    coroutine.yield()
end
