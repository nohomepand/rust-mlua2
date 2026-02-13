local prints = require"scripts.prints"
local jit = jit or nil
if not jit then
    print("No JIT")
    return
end

print("prints.tostr(jit)", prints.tostr(jit))
print("jit.status()", jit.status())

local sb = require"string.buffer"
print("prints.tostr(sb)", prints.tostr(sb))
local buffer = sb.new(1024)
print("type(buffer)", type(buffer))
print("prints.tostr(buffer)", prints.tostr(buffer))
buffer:put("abcdefg")
print("[" .. buffer:tostring() .. "]")

