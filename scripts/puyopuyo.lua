local fpswaiter = require"scripts.mod.fpswaiter"
local waiter = fpswaiter.fpswaiter:new()

math.randomseed(os.time())

local CELL = 32
local W = 6
local H = 12

local win = egui.create_window("PuyoLike+", W*CELL + 120, H*CELL)

local field = {}
local score = 0
local drop_timer = 0
local drop_interval = 30
local chain = 0
local gameover = false
local anim_timer = 0
local anim_delay = 15
local resolving = false

local colors = {
    {255,0,0},
    {0,255,0},
    {0,0,255},
    {255,255,0}
}

for y=1,H do
    field[y]={}
    for x=1,W do field[y][x]=0 end
end

-------------------------------------------------
-- ペア管理（先読み）
-------------------------------------------------
local current = {}
local next_pair = {}

local function random_pair()
    return {
        c1 = math.random(#colors),
        c2 = math.random(#colors)
    }
end

local function new_pair()
    current = {
        x = 3,
        y = 1,
        dir = 0,
        c1 = next_pair.c1,
        c2 = next_pair.c2
    }

    next_pair = random_pair()

    if field[1][3] ~= 0 then
        gameover = true
    end
end

-------------------------------------------------
-- ペア位置
-------------------------------------------------
local function get_pair_pos(px,py,dir)
    local dx = {0,1,0,-1}
    local dy = {-1,0,1,0}
    return px,py, px+dx[dir+1], py+dy[dir+1]
end

-------------------------------------------------
-- 衝突
-------------------------------------------------
local function blocked(x,y)
    return x<1 or x>W or y>H or (y>=1 and field[y][x]~=0)
end

local function collision(nx,ny,ndir)
    local x1,y1,x2,y2 = get_pair_pos(nx,ny,ndir)
    return blocked(x1,y1) or blocked(x2,y2)
end

-------------------------------------------------
-- 壁蹴り回転
-------------------------------------------------
local function try_rotate()
    local ndir=(current.dir+1)%4

    -- 通常
    if not collision(current.x,current.y,ndir) then
        current.dir=ndir
        return
    end

    -- 右蹴り
    if not collision(current.x+1,current.y,ndir) then
        current.x=current.x+1
        current.dir=ndir
        return
    end

    -- 左蹴り
    if not collision(current.x-1,current.y,ndir) then
        current.x=current.x-1
        current.dir=ndir
        return
    end
end

-------------------------------------------------
-- 固定
-------------------------------------------------
local function lock_pair()
    local x1,y1,x2,y2 = get_pair_pos(current.x,current.y,current.dir)
    if y1>=1 then field[y1][x1]=current.c1 end
    if y2>=1 then field[y2][x2]=current.c2 end
end

-------------------------------------------------
-- 重力
-------------------------------------------------
local function apply_gravity()
    local moved=false
    for x=1,W do
        for y=H-1,1,-1 do
            if field[y][x]~=0 and field[y+1][x]==0 then
                field[y+1][x]=field[y][x]
                field[y][x]=0
                moved=true
            end
        end
    end
    return moved
end

-------------------------------------------------
-- 連結
-------------------------------------------------
local function flood(x,y,color,visited,group)
    if x<1 or x>W or y<1 or y>H then return end
    if visited[y][x] then return end
    if field[y][x]~=color then return end

    visited[y][x]=true
    table.insert(group,{x,y})

    flood(x+1,y,color,visited,group)
    flood(x-1,y,color,visited,group)
    flood(x,y+1,color,visited,group)
    flood(x,y-1,color,visited,group)
end

local function clear_groups()
    local visited={}
    for y=1,H do visited[y]={} end

    local cleared=false

    for y=1,H do
        for x=1,W do
            if field[y][x]~=0 and not visited[y][x] then
                local group={}
                flood(x,y,field[y][x],visited,group)
                if #group>=4 then
                    for _,p in ipairs(group) do
                        field[p[2]][p[1]]=0
                    end
                    score = score + #group*10*(chain+1)
                    cleared=true
                end
            end
        end
    end

    return cleared
end

-------------------------------------------------
-- 描画
-------------------------------------------------
local function draw()
    win:cls(0,0,0)

    -- フィールド
    for y=1,H do
        for x=1,W do
            local c=field[y][x]
            if c~=0 then
                local col=colors[c]
                win:circle((x-0.5)*CELL,(y-0.5)*CELL,
                           CELL/2-2,col[1],col[2],col[3])
            end
        end
    end

    -- 現在
    if not gameover then
        local x1,y1,x2,y2 = get_pair_pos(current.x,current.y,current.dir)
        local col1=colors[current.c1]
        local col2=colors[current.c2]

        if y1>=1 then
            win:circle((x1-0.5)*CELL,(y1-0.5)*CELL,CELL/2-2,
                       col1[1],col1[2],col1[3])
        end
        if y2>=1 then
            win:circle((x2-0.5)*CELL,(y2-0.5)*CELL,CELL/2-2,
                       col2[1],col2[2],col2[3])
        end
    end

    -- 次ぷよ表示
    local nx = W*CELL + 40
    local col1=colors[next_pair.c1]
    local col2=colors[next_pair.c2]

    win:circle(nx, 100, CELL/2-2, col1[1],col1[2],col1[3])
    win:circle(nx, 140, CELL/2-2, col2[1],col2[2],col2[3])
end

-------------------------------------------------
-- 更新
-------------------------------------------------
local function update()
    if gameover then return end

    -- 連鎖演出中
    if resolving then
        anim_timer = anim_timer + 1
        if anim_timer >= anim_delay then
            anim_timer=0

            if clear_groups() then
                chain = chain + 1
            else
                if apply_gravity() then
                else
                    resolving=false
                    chain=0
                    new_pair()
                end
            end
        end
        return
    end

    drop_timer = drop_timer + 1
    if drop_timer >= drop_interval then
        drop_timer=0
        if not collision(current.x,current.y+1,current.dir) then
            current.y=current.y+1
        else
            lock_pair()
            resolving=true
            anim_timer=0
        end
    end

    drop_interval = math.max(5, 30 - math.floor(score/500))
end

-------------------------------------------------
-- 入力
-------------------------------------------------
function egui.keyhandler(state,vk,code)
    if state=="Pressed" and not gameover and not resolving then

        if vk=="Left" then
            if not collision(current.x-1,current.y,current.dir) then
                current.x=current.x-1
            end
        end

        if vk=="Right" then
            if not collision(current.x+1,current.y,current.dir) then
                current.x=current.x+1
            end
        end

        if vk=="Down" then
            if not collision(current.x,current.y+1,current.dir) then
                current.y=current.y+1
            end
        end

        if vk=="Up" then
            try_rotate()
        end
    end
end

-------------------------------------------------
-- 開始
-------------------------------------------------
next_pair = random_pair()
new_pair()

while true do
    update()
    draw()
    coroutine.yield()
    waiter:await(60)
end
