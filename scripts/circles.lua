local w, h = 600, 600
local win = egui.create_window("Circles", w, h)

for r = 1, math.floor(math.min(w / 2, h / 2)), 10 do
    win:circle(w / 2, h / 2, r, 255, 255, 255)
end