local width, height = 600, 600
local win = egui.create_window("Move Box", width, height)

local box = {
    cx = width / 2,
    cy = height / 2,
    size = 30,
    draw = function (self)
        win:rect(self.cx - self.size, self.cy - self.size, self.cx + self.size, self.cy + self.size, 255, 0, 0)
    end,
    move = function (self, dx, dy)
        self.cx = self.cx + dx
        self.cy = self.cy + dy
    end
}

local keystate = {}
function egui.keyhandler(state, vk, code)
    keystate[vk] = state
end

local function is_pressed(...)
    for _, vk in ipairs({...}) do
        if keystate[vk] == "Pressed" then
            return true
        end
    end
    return false
end

while true do
    if is_pressed("Left", "A", "Numpad4") then
        box:move(-box.size / 10, 0)
    end
    if is_pressed("Right", "D", "Numpad6") then
        box:move(box.size / 10, 0)
    end
    if is_pressed("Up", "W", "Numpad8") then
        box:move(0, -box.size / 10)
    end
    if is_pressed("Down", "S", "Numpad2") then
        box:move(0, box.size / 10)
    end
    
    box:draw()
    coroutine.yield()
    win:cls()
end
