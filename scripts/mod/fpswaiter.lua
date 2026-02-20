local module = {}

local fpswaiter = {}
function fpswaiter:new()
    local o = {
        last = hpc(),
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function fpswaiter:await(fps)
    local secs = 1 / fps
    while hpc() - self.last < secs do
        sleep(0.0001)
    end
    self.last = hpc()
end

module.fpswaiter = fpswaiter
return module