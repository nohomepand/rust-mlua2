-- eg2.lua: imageロード・描画・保存・キャプチャのテスト
local w = egui.create_window("imgtest", 320, 240)
local rnd = function (n, l) return math.random() * (n or 100) + (l or 0) end
for i = 1, 1000 do
    w:line(rnd(320), rnd(240), rnd(320), rnd(240), rnd(150, 100), rnd(150, 100), rnd(150, 100))
    print(i)
end
local cap = w:captureimage(0, 0, w:getwidth(), w:getheight())
print(cap)
cap:save("y:/aaa.png")

local dx = math.floor(w:getwidth() / 3)
local dy = math.floor(w:getheight() / 3)
for x = 1, 3 do
    for y = 1, 3 do
        print(x, y, dx, dy)
        local subcap = cap:subimage((x - 1) * dx, (y - 1) * dy, dx, dy)
        print(subcap)
        local filename = string.format("y:/sub-%d-%d.png", x, y)
        subcap:save(filename)
    end
end
return
-- local img = image.load("assets/test.png")
-- w:cls(0,0,0)
-- w:drawimage(img, 10, 10)
-- local cap = w:captureimage(10, 10, 32, 32)
-- cap:save("cap_out.png")
-- img:save("img_out.png")
-- print("image test done")
