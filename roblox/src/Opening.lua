-- Client-only introduction. The caller owns the six display models.
local Run = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local Sfx = require(script.Parent.Sfx)
local Wake = require(script.Parent.BoatWake)
local Opening = {}
local Tween = game:GetService("TweenService")
-- 色と字体はレース中の表示(RaceHud.lua)と同じ
local GOLD = Color3.fromRGB(255,210,60)
local WHITE = Color3.new(1,1,1)
local SUB = Color3.fromRGB(207,220,243)
local LANE = {
    {Color3.fromRGB(242,242,240), Color3.fromRGB(17,17,17)},
    {Color3.fromRGB(22,22,26), WHITE},
    {Color3.fromRGB(217,30,46), WHITE},
    {Color3.fromRGB(27,80,212), WHITE},
    {Color3.fromRGB(243,210,27), Color3.fromRGB(17,17,17)},
    {Color3.fromRGB(24,162,76), WHITE},
}
local NUMBER_FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
local BOLD_FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
local HEAVY_FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)

-- 文字(水面の上でも読めるよう暗い縁取りを薄く付ける)
local function text(parent, words, size, font, color, x, y, w, h)
    local t = Instance.new("TextLabel")
    t.BackgroundTransparency = 1
    t.Text = words
    t.FontFace = font or BOLD_FONT
    t.TextSize = size
    t.TextColor3 = color or WHITE
    t.TextStrokeColor3 = Color3.fromRGB(0,10,30)
    t.TextStrokeTransparency = 0.6
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.TextTruncate = Enum.TextTruncate.AtEnd
    t.Position = UDim2.fromOffset(x, y)
    t.Size = UDim2.fromOffset(w, h)
    t.Parent = parent
    return t
end

local function corner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = parent
end

-- 映画のような上下の黒い帯
local function letterbox(gui, top)
    local bar = Instance.new("Frame")
    bar.BackgroundColor3 = Color3.new(0,0,0)
    bar.BorderSizePixel = 0
    bar.AnchorPoint = Vector2.new(0, top and 1 or 0)
    bar.Position = UDim2.fromScale(0, top and 0 or 1)
    bar.Size = UDim2.new(1,0,0.085,0)
    bar.Parent = gui
    Tween:Create(bar, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Position = UDim2.fromScale(0, top and 0.085 or 0.915)}):Play()
end

-- 待機行動の通り道(ブラウザ版 src/opening.js の buildRoute と同じ。単位は m、Roblox では 3.5倍)。
-- ピットを出て、スタンド寄りを東へ → 右へUターン → バックストレッチを西へ → 右へUターン → 自分のコースへ。
-- 桟橋・マーク・消波装置・ほかの艇と十分離れることをブラウザ版で確かめてある(tools/opening-test.mjs)
local PIT_X, LANE_A, U1X, U1R = -261.8, 30, -110, 21
local BACK_Z = LANE_A - 2*U1R
local function buildRoute(i0, gx, gz, short)
    local pts = {}
    local function push(x, z) pts[#pts+1] = Vector2.new(x, z) end
    if short then
        -- 短い版(2走目から): 自分のコースの60m後ろからまっすぐ
        push(gx-60, gz)
        for x = gx-58, gx-0.01, 2 do push(x, gz) end
        push(gx, gz)
    else
        local x0, x1, z0 = PIT_X, -150, -12 + i0*10
        push(x0, z0)
        for k = 1, 60 do local t = k/60; local e = t*t*(3-2*t); push(x0+(x1-x0)*t, z0+(LANE_A-z0)*e) end
        for x = x1+2, U1X, 2 do push(x, LANE_A) end
        local c1 = LANE_A - U1R
        for k = 1, 48 do local a = math.pi/2 - math.pi*k/48; push(U1X+U1R*math.cos(a), c1+U1R*math.sin(a)) end
        local u2x = i0 < 3 and -178 or -212
        for x = U1X-2, u2x+0.01, -2 do push(x, BACK_Z) end
        push(u2x, BACK_Z)
        local r2 = (gz - BACK_Z)/2
        local c2, n2 = BACK_Z + r2, math.max(16, math.ceil(math.pi*r2/2))
        for k = 1, n2 do local a = -math.pi/2 - math.pi*k/n2; push(u2x+r2*math.cos(a), c2+r2*math.sin(a)) end
        for x = u2x+2, gx-0.01, 2 do push(x, gz) end
        push(gx, gz)
    end
    local cum = {0}
    for k = 2, #pts do cum[k] = cum[k-1] + (pts[k]-pts[k-1]).Magnitude end
    return {pts=pts, cum=cum, len=cum[#cum]}
end
-- 道のり s の位置(m)
local function routeAt(route, s)
    local pts, cum = route.pts, route.cum
    if s <= 0 then return pts[1] end
    if s >= route.len then return pts[#pts] end
    local lo, hi = 1, #cum
    while hi - lo > 1 do local m = (lo+hi)//2; if cum[m] <= s then lo = m else hi = m end end
    local f = (s - cum[lo]) / math.max(cum[hi]-cum[lo], 1e-6)
    return pts[lo]:Lerp(pts[hi], f)
end

function Opening.play(options)
    local camera = options.camera
    local original,focus = camera.CFrame,camera.Focus
    local event = Instance.new("BindableEvent")
    local show = {Done=event.Event}
    local gui = Instance.new("ScreenGui")
    gui.Name = "MinatoOpening"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 15
    gui.Parent = options.gui
    letterbox(gui, true)
    letterbox(gui, false)
    -- 部品ごとに、画面の大きさに合わせて縮める(スマホの横画面でも重ならない。位置は部品の基準点のまま)
    local stage = gui
    local scales = {}
    local function fit()
        local v = camera.ViewportSize
        local k = math.clamp(math.min(v.Y/720, v.X/900), 0.55, 1.15)
        for _, item in scales do item.Scale = k end
    end
    local function scaled(item)
        local u = Instance.new("UIScale")
        u.Parent = item
        table.insert(scales, u)
        return item
    end
    local fitLink = camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
    -- 左: 大会名と出走表のカード(左から滑り込む)
    local rows = options.rows or {}
    local count = math.min(#rows, 6)
    local cardHeight = 92 + count*40
    local card = Instance.new("Frame")
    card.BackgroundColor3 = Color3.fromRGB(8,24,48)
    card.BackgroundTransparency = 0.18
    card.BorderSizePixel = 0
    card.Size = UDim2.fromOffset(380, cardHeight)
    card.AnchorPoint = Vector2.new(0, 0.5)
    card.Position = UDim2.new(0, -440, 0.5, 0)
    card.Parent = stage
    scaled(card)
    corner(card, 12)
    local edge = Instance.new("Frame")
    edge.BackgroundColor3 = GOLD
    edge.BorderSizePixel = 0
    edge.Size = UDim2.new(0,5,1,-24)
    edge.Position = UDim2.fromOffset(0,12)
    edge.Parent = card
    text(card, "出 走 表", 14, HEAVY_FONT, GOLD, 22, 14, 200, 18)
    text(card, options.title or "みなとグランプリ", 26, HEAVY_FONT, WHITE, 22, 34, 340, 34)
    local entries = {}
    for i = 1, count do
        local row = rows[i]
        local line = Instance.new("Frame")
        line.BackgroundTransparency = 1
        line.Size = UDim2.fromOffset(340, 34)
        line.Position = UDim2.fromOffset(52, 80 + (i-1)*40)
        line.Parent = card
        local colors = LANE[row.number] or LANE[1]
        local chip = text(line, tostring(row.number), 20, NUMBER_FONT, colors[2], -30, 2, 30, 30)
        chip.TextXAlignment = Enum.TextXAlignment.Center
        chip.TextStrokeTransparency = 1
        chip.BackgroundTransparency = 0
        chip.BackgroundColor3 = colors[1]
        corner(chip, 5)
        text(line, row.name ~= "" and row.name or "選手", 19, BOLD_FONT, WHITE, 12, 0, 230, 34)
        if row.cls and row.cls ~= "" then
            local cls = text(line, row.cls, 15, NUMBER_FONT, (row.cls == "A1" or row.cls == "S") and GOLD or SUB, 246, 0, 44, 34)
            cls.TextXAlignment = Enum.TextXAlignment.Right
        end
        line.Visible = false
        entries[i] = line
    end
    -- 左下: 今の場面の名前 / 右下: スキップ
    local caption = text(stage, "", 20, HEAVY_FONT, GOLD, 0, 0, 260, 26)
    caption.AnchorPoint = Vector2.new(0,1)
    caption.Position = UDim2.new(0, 28, 0.915, -16)
    scaled(caption)
    local skip = Instance.new("TextButton")
    skip.Text = "スキップ"
    skip.FontFace = HEAVY_FONT
    skip.TextSize = 16
    skip.TextColor3 = WHITE
    skip.BackgroundColor3 = Color3.fromRGB(8,24,48)
    skip.BackgroundTransparency = 0.25
    skip.AnchorPoint = Vector2.new(1,1)
    skip.Size = UDim2.fromOffset(120, 40)
    skip.Position = UDim2.new(1, -24, 0.915, -12)
    skip.Parent = stage
    scaled(skip)
    fit()
    corner(skip, 20)
    local ring = Instance.new("UIStroke")
    ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    ring.Color, ring.Thickness, ring.Transparency = WHITE, 1.5, 0.4
    ring.Parent = skip
    local cardShown, cardHidden = false, false
    local shownRows = 0
    local spray=Instance.new("Folder")
    spray.Name="MinatoOpeningSpray"
    spray.Parent=workspace
    local paths,leader={},nil
    for i=1,6 do
        local boat,goal=options.boats[i],options.finalCFrames[i]
        if boat and goal then
            local last=goal.Position
            local route=buildRoute(i-1,last.X/3.5,last.Z/3.5,(options.duration or 24)<15)
            local first=routeAt(route,0)
            local start=Vector3.new(first.X*3.5,.14,first.Y*3.5)
            local second=routeAt(route,2)
            -- 止まっている時と同じ高さ(艇底が少し水に入る。レースの表示と同じ)
            paths[i]={boat=boat,goal=goal-Vector3.new(0,goal.Y-.14,0),start=start,route=route,y=.14}
            local anchor=Instance.new("Part")
            anchor.Anchored=true
            anchor.CanCollide,anchor.CanTouch,anchor.CanQuery=false,false,false
            anchor.Transparency=1
            anchor.Parent=spray
            paths[i].anchor=anchor
            paths[i].wake=Wake.new(anchor)
            paths[i].last=start
            leader=leader or i
            boat:PivotTo(CFrame.lookAt(start,Vector3.new(second.X*3.5,.14,second.Y*3.5)))
        end
    end
    local links={}
    local timer
    local finished=false
    local reachedEnd=false
    local function finish()
        if finished then return end
        finished=true
        if timer then task.cancel(timer);timer=nil end
        for _,link in links do link:Disconnect() end
        fitLink:Disconnect()
        for _,p in paths do if p.boat.Parent then p.boat:PivotTo(p.goal) end end
        -- カメラは最後の場面のまま渡す(呼び出し側がそこから滑らかに戻す)。途中で消した時だけ元へ
        -- 最後まで見た・スキップした時は、レースのカメラ(スクリプトで動かす)がそのまま引き継ぐ。
        -- 標準のカメラへ戻すと、その1コマだけカメラが飛ぶ
        if not reachedEnd then
            camera.CFrame,camera.Focus=original,focus
            camera.CameraType=Enum.CameraType.Custom
        end
        Sfx.opening(false)
        spray:Destroy()
        gui:Destroy()
        event:Fire()
        task.delay(.2,function() event:Destroy() end)
    end
    -- スキップは今の場面から、レースのカメラへなめらかにつなぐ(元のカメラへは戻さない)
    local function skipNow() reachedEnd=true; finish() end
    show.skip,show.destroy=skipNow,finish
    -- スキップの文字を変える(みんなの票の数など)
    function show.setSkipText(words) skip.Text = words end
    local voted=false
    local function pressSkip()
        if not options.onSkip then skipNow(); return end
        if voted then return end
        voted=true
        skip.Text="待機中…"
        skip.BackgroundTransparency=0.55
        options.onSkip()
    end
    table.insert(links,skip.Activated:Connect(pressSkip))
    table.insert(links,Input.InputBegan:Connect(function(key)
        if key.UserInputType==Enum.UserInputType.Touch or key.UserInputType==Enum.UserInputType.MouseButton1
            or key.KeyCode==Enum.KeyCode.Return or key.KeyCode==Enum.KeyCode.KeypadEnter then pressSkip() end
    end))
    camera.CameraType=Enum.CameraType.Scriptable
    local duration=math.max(.01,options.duration or 24)
    local started=os.clock()
    Sfx.opening(true)
    -- 画面を描く直前に動かす(艇とカメラが同じ瞬間の位置になり、かくつかない)
    table.insert(links,Run.RenderStepped:Connect(function(dt)
        local t=(os.clock()-started)/duration
        if t>=1 then reachedEnd=true;finish();return end
        -- 出走表のカード: 初めに滑り込み、1行ずつ出して、ピット離れの前に左へ下がる
        if not cardShown then
            cardShown = true
            Tween:Create(card, TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                {Position = UDim2.new(0, 28, 0.5, 0)}):Play()
        end
        while shownRows < #entries and t >= .03 + shownRows*.035 do
            shownRows += 1
            local line = entries[shownRows]
            line.Visible = true
            local goal = line.Position
            line.Position = goal + UDim2.fromOffset(24, 0)
            for _, item in line:GetChildren() do
                if item:IsA("TextLabel") and item.BackgroundTransparency == 1 then
                    item.TextTransparency = 1
                    Tween:Create(item, TweenInfo.new(0.35), {TextTransparency = 0}):Play()
                end
            end
            Tween:Create(line, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = goal}):Play()
        end
        if t >= .3 and not cardHidden then
            cardHidden = true
            Tween:Create(card, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
                {Position = UDim2.new(0, -440, 0.5, 0)}):Play()
        end
        caption.Text = t < .3 and "" or (t < .65 and "ピット離れ" or "待機行動")
        for i,p in paths do
            -- 1号艇から順にピットを出る。出だしと止まる所だけゆっくり(速さの山が高くなりすぎないよう、直線と半々)
            -- ブラウザ版と同じ決まり: どの艇も同じ時間をかけて走り、出るのも着くのも1号艇から少しずつずらす
            -- (着く時刻をそろえると、後の艇ほど速くなって前の艇に追いついて重なる)
            local delay=.133+(i-1)*.0217
            local u=math.clamp((t-delay)/.729,0,1)
            u=.5*u+.5*u*u*(3-2*u)
            local s=u*p.route.len
            local here=routeAt(p.route,s)
            local ahead=routeAt(p.route,math.min(s+1.5,p.route.len))
            local behind=routeAt(p.route,math.max(s-1.5,0))
            local pos=Vector3.new(here.X*3.5,p.y,here.Y*3.5)
            local heading=Vector3.new(ahead.X-behind.X,0,ahead.Y-behind.Y)
            -- 終わり近くで、進む向きから待機の向きへ少しずつ回す(最後に向きが飛ばないように)
            local k=math.clamp((u-.8)/.2,0,1)
            k=k*k*(3-2*k)
            local turn=heading.Magnitude>1e-4 and CFrame.lookAt(pos,pos+heading).Rotation or p.goal.Rotation
            local pose=CFrame.new(pos)*turn:Lerp(p.goal.Rotation,k)
            if p.boat.Parent then p.boat:PivotTo(pose) end
            p.anchor.CFrame=pose
            local speed=(pos-p.last).Magnitude/(3.5*math.max(dt,.001))
            Wake.update(p.wake,0,"",0,speed,.65,0,1,(camera.CFrame.Position-pos).Magnitude,i==leader,false,.35)
            p.last=pos
        end
        local target=leader and paths[leader].boat:GetPivot().Position or Vector3.zero
        local eye
        if t<.30 then
            target=target:Lerp(Vector3.zero,.6)
            eye=target+Vector3.new(-210+140*t,185,210)
        elseif t<.65 then
            -- ピット離れ: 先頭の艇を斜め前から迎える(桟橋の屋根に入らないよう水面側から)
            local look=paths[leader] and paths[leader].boat:GetPivot().LookVector or Vector3.xAxis
            look=Vector3.new(look.X,0,look.Z).Unit
            eye=target+look*34+look:Cross(Vector3.yAxis)*20+Vector3.new(0,7,0)
        elseif t<.86 then eye=target+Vector3.new(4,12,44)
        else eye=target+Vector3.new(-42,55,45) end
        camera.CFrame=CFrame.lookAt(eye,target)
        camera.Focus=CFrame.new(target)
    end))
    timer=task.delay(duration+0.5,function() timer=nil;reachedEnd=true;finish() end)
    return show
end
return Opening
