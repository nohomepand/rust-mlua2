local module = {}

function module.tostr(t)
    if t == nil then
        return "nil"
    elseif type(t) == "table" then
        local s = "{"
        for k, v in pairs(t) do
            s = s .. (module.tostr(k) .. "=" .. module.tostr(v) .. ", ")
        end
        s = s .. "}"
        return s
    else
        return tostring(t)
    end
end

function module.dbgprint(t)
    print(module.tostr(t))
end

return module
