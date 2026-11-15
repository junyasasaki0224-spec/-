local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Run=game:GetService("RunService")
local player=Players.LocalPlayer
local cards=require(RS:WaitForChild("CardImages"))
local visuals=require(RS:WaitForChild("VisualModels"))
local Meta=require(RS:WaitForChild("Meta"))
local outfit=require(RS:WaitForChild("Outfit"))
local remote=RS:WaitForChild("MinatoMeta")
local gui=Instance.new("ScreenGui")
gui.Name="MinatoHome";gui.ResetOnSpawn=false;gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets
gui.Parent=player:WaitForChild("PlayerGui")
local navy=Color3.fromRGB(11,29,58)
local gold=Color3.fromRGB(255,210,60)
local pale=Color3.fromRGB(169,189,219)
local white=Color3.new(1,1,1)
local rarity={N=white,R=Color3.fromRGB(57,140,255),SR=Color3.fromRGB(172,110,255),SSR=gold}
local mode="シーズン"
local m,page,pending=nil,"ホーム",nil
local redraw,request
local function box(class,parent,name,text)
    local x=Instance.new(class);x.Name=name;x.Parent=parent
    x.BackgroundColor3=navy;x.BackgroundTransparency=.12;x.BorderSizePixel=0
    if x:IsA("TextLabel") or x:IsA("TextButton") then
        x.Text=text or "";x.TextColor3=white;x.TextSize=18;x.Font=Enum.Font.GothamBold
        x.TextTruncate=Enum.TextTruncate.AtEnd
    end
    local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(0,12);corner.Parent=x
    return x
end
local function frame(parent,name,x,y,w,h)
    local f=box("Frame",parent,name);f.Position=UDim2.new(0,x,0,y);f.Size=UDim2.new(0,w,0,h);return f
end
local function stroke(x,color,thickness)
    local s=Instance.new("UIStroke");s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
    s.Color=color;s.Thickness=thickness or 1;s.Transparency=.2;s.Parent=x;return s
end
local function button(parent,title,x,y,w,action,primary)
    local b=box("TextButton",parent,title,title);b.Position=UDim2.fromOffset(x,y);b.Size=UDim2.fromOffset(w,46)
    stroke(b,gold,1)
    if primary then
        b.BackgroundTransparency=0;b.BackgroundColor3=white;b.TextColor3=Color3.fromRGB(26,18,0)
        local g=Instance.new("UIGradient");g.Color=ColorSequence.new(Color3.fromRGB(255,224,102),Color3.fromRGB(245,164,0));g.Rotation=90;g.Parent=b
    end
    b.Activated:Connect(action);return b
end
local function icon(parent,index)
    local patterns={
        {{4,10,22,18},{10,4,10,28},{4,18,22,2}},
        {{3,9,24,20},{3,9,24,2},{14,9,2,20}},
        {{6,3,20,26},{9,10,12,2},{9,17,12,2},{9,24,8,2}},
        {{3,22,6,8},{12,14,6,16},{21,5,6,25}},
    }
    for _,r in ipairs(patterns[index]) do
        local line=frame(parent,"Icon",r[1]+8,r[2]+7,r[3],r[4])
        line.BackgroundTransparency=1;stroke(line,gold,1)
    end
end
local function label(parent,text,x,y,w,h,size)
    local t=box("TextLabel",parent,"Text",text);t.BackgroundTransparency=1
    t.Position=UDim2.fromOffset(x,y);t.Size=UDim2.fromOffset(w,h);t.TextSize=math.max(size or 18,16);t.TextXAlignment=Enum.TextXAlignment.Left;return t
end
local function part(parent,name,size,pos,color)
    local p=Instance.new("Part");p.Name=name;p.Size=size;p.CFrame=CFrame.new(pos);p.Color=color;p.Anchored=true;p.CanCollide=false;p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth;p.Parent=parent;return p
end
local function boat(parent)
    local imported=visuals.boat(parent)
    if imported then return imported end
    local model=Instance.new("Model");model.Name="MyBoat";model.Parent=parent
    part(model,"Hull",Vector3.new(1.34,.22,2.65),Vector3.new(0,.1,0),white)
    local bow=Instance.new("WedgePart");bow.Name="Bow";bow.Size=Vector3.new(1.3,.22,.72);bow.CFrame=CFrame.new(0,.1,-1.65)*CFrame.Angles(0,math.pi,0);bow.Color=white;bow.Anchored=true;bow.Parent=model
    part(model,"Deck",Vector3.new(1.14,.15,1.7),Vector3.new(0,.28,-.2),white)
    for _,x in ipairs({-.5,.5}) do part(model,"Side",Vector3.new(.08,.38,1.3),Vector3.new(x,.47,.18),white) end
    part(model,"Mount",Vector3.new(.2,.20,.48),Vector3.new(0,.27,1.29),navy)
    part(model,"Motor",Vector3.new(.37,.58,.4),Vector3.new(0,.5,1.52),navy)
    part(model,"Racer",Vector3.new(.55,.42,.65),Vector3.new(0,.64,.18),white)
    local helmet=part(model,"Helmet",Vector3.new(.40,.40,.40),Vector3.new(0,1,-.09),white);helmet.Shape=Enum.PartType.Ball
    return model
end
local scenery=Instance.new("Folder");scenery.Name="MinatoHomeScene";scenery.Parent=workspace
local water=part(scenery,"Water",Vector3.new(1900,.5,600),Vector3.new(0,-.5,0),Color3.fromRGB(23,100,127));water.Material=Enum.Material.Glass
local detailedVenue=visuals.venue(scenery)
for i=1,detailedVenue and 0 or 8 do
    part(scenery,"Terrace",Vector3.new(160,2,5),Vector3.new(0,i*1.5,53+i*4),Color3.fromRGB(137,158,169))
end
if not detailedVenue then part(scenery,"Roof",Vector3.new(175,1,30),Vector3.new(0,22,72),navy) end
for i=-7,detailedVenue and -8 or 7 do
    part(scenery,"Column",Vector3.new(.7,22,.7),Vector3.new(i*11,11,72),Color3.fromRGB(202,213,220))
end
local model=boat(scenery)
if not model:GetAttribute("Detailed") then model:ScaleTo(3.5) end
model:PivotTo(CFrame.new(0,0,100))
local root=box("Frame",gui,"Content");root.BackgroundTransparency=1;root.Size=UDim2.fromScale(1,1)
local toast=label(gui,"読み込み中…",8,8,300,40,14);toast.TextColor3=gold
local sceneClock=0
Run.RenderStepped:Connect(function(dt)
    sceneClock+=dt
    local cam=workspace.CurrentCamera
    if gui.Enabled then
        cam.CameraType=Enum.CameraType.Scriptable
        local angle=.65+sceneClock*.012
        local portrait=gui.AbsoluteSize.X<gui.AbsoluteSize.Y
        local dist=portrait and 24 or 14
        cam.CFrame=CFrame.lookAt(Vector3.new(math.sin(angle)*dist,7,100+math.cos(angle)*dist),Vector3.new(0,1,100))
        if page=="倉庫" and not portrait then cam.CFrame=cam.CFrame*CFrame.new(-5,0,0) end
        cam.Focus=CFrame.new(0,1,100)
    end
end)
local modes={"シーズン","オンライン","タイムアタック","フレンド","大会","イベント","フリーレース","スタート練習"}
local descriptions={"級別を上げて頂点へ","6人で水面を競う","1艇・無風で自己ベスト","合言葉で仲間と集合","得点を重ねて優勝へ","日替わりの特別レース","気軽に走って練習","スタートを磨く"}
local function go(p) page=p;redraw() end
local function legacy()
    local old=player.PlayerGui:FindFirstChild("MinatoLobby")
    if old then old.Enabled=true;gui.Enabled=false else toast.Text="通信機能を準備中です" end
end
local matchEvent
local waitingMode
local matchMessage=""
local matchNames={online="オンライン",ranked="シーズン"}
local function bindMatch(event)
    if event.Name~="MinatoRankedLobby" or matchEvent==event then return end
    matchEvent=event
    event.OnClientEvent:Connect(function(message,waiting,kind)
        waitingMode=waiting and (kind or waitingMode or "ranked") or nil
        matchMessage=message
        if m and (page=="オンライン" or page=="シーズン" or page=="ホーム") then redraw() end
    end)
    if m then redraw() end
end
RS.ChildAdded:Connect(bindMatch)
local existingMatch=RS:FindFirstChild("MinatoRankedLobby")
if existingMatch then bindMatch(existingMatch) end
local function swatch(parent,it,x,y,w,h)
    local colors=it.kind=="skin" and {it.hull,it.trim,it.deck,it.cowl} or {it.base,it.stripe}
    for i,c in ipairs(colors) do
        local f=frame(parent,"Color",x+(i-1)*w/#colors,y,w/#colors,h)
        if it.kind=="helmet" then f:FindFirstChildOfClass("UICorner").CornerRadius=UDim.new(1,0) end
        f.BackgroundTransparency=0;f.BackgroundColor3=Color3.fromRGB(bit32.rshift(c,16),bit32.band(bit32.rshift(c,8),255),bit32.band(c,255))
    end
end
local function preview(parent,index,width,height)
    height=height or 115
    local names={"season","online","ta","friend","gp","event","single","practice"}
    local id=cards[names[index]]
    if id and id~="" then
        local picture=Instance.new("ImageLabel")
        picture.Name="SceneImage";picture.Image=id;picture.ScaleType=Enum.ScaleType.Crop
        picture.Size=UDim2.fromOffset(width,height);picture.Position=UDim2.fromOffset(0,37)
        picture.BorderSizePixel=0;picture.Parent=parent
        local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(0,10);corner.Parent=picture
        return
    end
    local v=Instance.new("ViewportFrame");v.Size=UDim2.fromOffset(width,height);v.Position=UDim2.fromOffset(0,37)
    v.BackgroundColor3=Color3.fromRGB(25+index*2,83,107);v.Ambient=white;v.LightColor=white;v.Parent=parent
    local w=Instance.new("WorldModel");w.Parent=v
    local b=boat(w);outfit(b,m and m.skin or "s0",m and m.helmet or "h0")
    local c=Instance.new("Camera");local angle=index*.62;c.CFrame=CFrame.lookAt(Vector3.new(math.sin(angle)*4,2+index*.15,math.cos(angle)*4),Vector3.new(0,.3,0));c.Parent=v;v.CurrentCamera=c
end
function redraw()
    for _,c in ipairs(root:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
    if not m then return end
    outfit(model,m.skin,m.helmet)
    local w,h=gui.AbsoluteSize.X,gui.AbsoluteSize.Y
    local portrait=w<h
    toast.Position=UDim2.fromOffset(16,page=="ホーム" and 130 or 58)
    toast.Size=UDim2.fromOffset(w-32,30)
    toast.ZIndex=10
    local grade=Meta.grade(m.rate);local g=Meta.GRADES[grade];local nextGrade=Meta.GRADES[grade+1]
    if page=="ホーム" then
        local badge=frame(root,"GradeBadge",20,17,40,40)
        badge.Rotation=45;badge.BackgroundColor3=gold;stroke(badge,gold,2)
        label(root,g.name,22,17,42,40,20).TextColor3=navy
        label(root,Run:IsStudio() and "テストレーサー" or player.DisplayName,78,12,math.min(220,w-100),32,21).TextColor3=gold
        label(root,"RATE "..m.rate..(nextGrade and "　"..nextGrade.name.."まで あと"..(nextGrade.rate-m.rate).."点" or "　最高級"),78,46,math.min(310,w-90),24,14)
        local progress=frame(root,"RateProgress",14,76,180,4);progress.BackgroundColor3=pale
        local fill=frame(progress,"Fill",0,0,nextGrade and 180*math.clamp((m.rate-g.rate)/(nextGrade.rate-g.rate),0,1) or 180,4);fill.BackgroundColor3=gold
        label(root,"● "..m.coins.." コイン",portrait and 14 or w-420,portrait and 92 or 12,190,32,20).TextColor3=gold
        button(root,"パス "..m.tier.."段",portrait and w-150 or (h<450 and w-272 or w-220),portrait and 90 or 6,136,function() go("シーズンパス") end)
        button(root,"設定",w-126,portrait and 199 or (h<450 and 60 or 116),112,function() go("設定") end)
        button(root,"メール "..#m.mail,w-126,portrait and 145 or (h<450 and 6 or 64),112,function() go("メール") end)
        local short=not portrait and h<450
        local tileY=portrait and h-196 or (short and h-110 or 130)
        local tw=portrait and (w-40)/4 or (short and 124 or 172)
        for i,name in ipairs({"ガチャ","倉庫","ミッション","ランキング"}) do
            local title=name
            if name=="ミッション" then
                local n=0;for _,mis in ipairs(Meta.MISSIONS) do if not m.misDone[mis.id] and (m.mis[mis.id] or 0)>=mis.goal then n+=1 end end
                if n>0 then title=name.." "..n end
            end
            local tile=button(root,title,portrait and (8+(i-1)*(tw+8)) or (short and 14+((i-1)%2)*132 or 14),portrait and tileY or (short and tileY+math.floor((i-1)/2)*54 or tileY+(i-1)*58),tw,function() if name=="ランキング" then legacy() else go(name) end end)
            if portrait then
                tile.TextYAlignment=Enum.TextYAlignment.Bottom
                local symbol=frame(tile,"Symbol",tw/2-10,-2,28,28)
                symbol.BackgroundTransparency=1
                local scale=Instance.new("UIScale");scale.Scale=.45;scale.Parent=symbol
                icon(symbol,i)
            else
                tile.Text="        "..title;icon(tile,i)
            end
            local accent=frame(tile,"Accent",1,9,3,28);accent.BackgroundColor3=gold
        end
        button(root,"通信対戦",portrait and 8 or w-186,portrait and h-139 or (short and h-164 or h-190),portrait and (w-24)/2 or 172,legacy)
        button(root,"遊び方",portrait and w/2+4 or w-186,portrait and h-139 or (short and h-110 or h-132),portrait and (w-24)/2 or 172,function() go("遊び方") end)
        label(root,waitingMode and (matchNames[waitingMode].." 待機中") or mode,w-214,h-79,200,24,14)
        button(root,"レース",portrait and 8 or w-250,h-54,portrait and w-16 or 236,function() go(waitingMode and matchNames[waitingMode] or "レースを選ぶ") end,true)
        return
    end
    local panelWidth=page=="倉庫" and math.min(w-16,640) or w-16
    local panel=frame(root,"Panel",8,8,panelWidth,h-16);stroke(panel,white)
    button(panel,"ホーム",8,8,88,function() go("ホーム") end)
    label(panel,page,108,8,math.max(90,panelWidth-220),44,portrait and 16 or 22)
    label(panel,"● "..m.coins,panelWidth-105,8,97,44,16).TextColor3=gold
    local list=box("ScrollingFrame",panel,"List")
    list.Position=UDim2.fromOffset(8,98);list.Size=UDim2.new(1,-16,1,-106);list.BackgroundTransparency=1
    list.ScrollBarThickness=4
    local width=panelWidth-24
    local function row(title,body,y,action,caption)
        label(list,title,8,y,width-16,30,17)
        label(list,body,8,y+31,width-16,28,14).TextColor3=pale
        if action then button(list,caption or "受け取る",8,y+65,math.min(width-16,170),action,true) end
        return y+(action and 125 or 75)
    end
    local y=0
    if page=="レースを選ぶ" then
        list.ScrollingDirection=Enum.ScrollingDirection.XY
        local shortCard=h<450
        for i,name in ipairs(modes) do
            local card=frame(list,"Mode"..i,(i-1)*222,0,210,shortCard and 204 or 330);stroke(card,gold,mode==name and 3 or 1)
            label(card,name,12,0,154,36,20);preview(card,i,210,shortCard and 64 or 115)
            local emblem=frame(card,"Emblem",174,3,32,32);emblem.BackgroundTransparency=1
            local scale=Instance.new("UIScale");scale.Scale=.65;scale.Parent=emblem;icon(emblem,(i-1)%4+1)
            label(card,descriptions[i],10,shortCard and 102 or 164,190,32,16)
            if not shortCard then button(card,mode==name and "選択中" or "選ぶ",8,204,194,function() mode=name;redraw() end,true) end
            button(card,"出走の準備",8,shortCard and 146 or 260,194,function()
                mode=name
                if name=="シーズン" or name=="オンライン" then go(name)
                elseif name=="フレンド" or name=="フリーレース" then legacy()
                else toast.Text=name.."の対戦機能は次回の作業で追加します" end
            end)
        end
        list.CanvasSize=UDim2.fromOffset(8*222,shortCard and 204 or 330);return
    elseif page=="オンライン" or page=="シーズン" then
        local kind=page=="オンライン" and "online" or "ranked"
        if kind=="online" then
            y=row("6人で対戦","着順でレートは変わりません",y)
        else
            y=row("シーズン戦","近いレートの選手から相手を探します",y)
        end
        if waitingMode and waitingMode~=kind then
            y=row(matchNames[waitingMode].."で待機中","モードを切り替えるには待機を終了してください",y,
                function() go(matchNames[waitingMode]) end,"待機画面へ")
        elseif matchEvent then
            y=row(waitingMode and "対戦相手を待っています" or "出走受付",matchMessage,y,function()
                matchEvent:FireServer(waitingMode and "cancel" or (kind=="online" and "online" or "join"))
            end,waitingMode and "待機をやめる" or "参加する")
        else
            y=row("受付の準備中","通信の準備ができると参加できます",y)
        end
    elseif page=="ガチャ" then
        y=row("コインで見た目を集めよう","N 60%　R 28%　SR 10%　SSR 2%",y)
        y=row("ゲーム内コイン限定","コインはお金で買えません",y)
        button(list,"1回 100コイン",8,y,math.min(width-16,250),function() request("pull",1) end,true);y+=58
        button(list,"10回 900コイン",8,y,math.min(width-16,250),function() request("pull",10) end,true);y+=62
        if type(m.last)=="table" then
            for index,v in ipairs(m.last) do
                local it=Meta.item(v.id)
                local card=frame(list,"Draw"..index,8,y,width-16,112);stroke(card,rarity[it.r],2)
                swatch(card,it,8,8,64,88)
                label(card,it.r.."　"..it.name,82,10,width-106,32,16)
                label(card,v.dupe>0 and ("重複 +"..v.dupe.." コイン") or "倉庫に届きました",82,50,width-106,30,14)
                card.Visible=false
                task.delay(index*.12,function() if card.Parent then card.Visible=true end end)
                y+=124
            end
        end
        y=row("所持 "..#m.own.." / "..#Meta.ITEMS.." 種","重複時 N15 / R40 / SR120 / SSR400 コイン",y)
    elseif page=="倉庫" then
        local columns=math.max(1,math.floor(width/175));local cw=math.floor(width/columns)-8
        for i,it in ipairs(Meta.ITEMS) do
            local x=((i-1)%columns)*(cw+8);local cy=math.floor((i-1)/columns)*156
            local card=frame(list,it.id,x,cy,cw,146)
            local owned=table.find(m.own,it.id)
            card.BackgroundTransparency=owned and .1 or .7
            stroke(card,(m.skin==it.id or m.helmet==it.id) and gold or rarity[it.r],(m.skin==it.id or m.helmet==it.id) and 3 or 1)
            swatch(card,it,8,8,cw-16,34)
            label(card,it.name,8,48,cw-16,24,14)
            label(card,(it.kind=="skin" and "塗装 " or "ヘルメット ")..it.r,8,74,cw-16,20,12)
            if owned then button(card,(m.skin==it.id or m.helmet==it.id) and "装備中" or "装備する",8,96,cw-16,function() request("equip",it.id) end)
            else label(card,"未入手",8,99,cw-16,40,14) end
        end
        y=math.ceil(#Meta.ITEMS/columns)*156
    elseif page=="メール" then
        for _,v in ipairs(m.mail) do y=row(v.title,v.body.."　+"..v.coins.." コイン",y,function() request("mail",v.id) end) end
        if #m.mail==0 then y=row("メールはありません","次のログインやレースで報酬が届きます",y) end
    elseif page=="ミッション" then
        for _,v in ipairs(Meta.MISSIONS) do
            local done=m.misDone[v.id]
            local track=frame(list,"Progress",8,y+58,width-16,3);track.BackgroundColor3=pale
            local fill=frame(track,"ProgressFill",0,0,(width-16)*math.min(1,(m.mis[v.id] or 0)/v.goal),3);fill.BackgroundColor3=gold
            y=row(v.name,math.min(m.mis[v.id] or 0,v.goal).."/"..v.goal.."　+"..v.coins.." コイン",y,
                not done and function() request("mission",v.id) end or nil, "受け取る")
        end
    elseif page=="設定" then
        y=row("画面","Robloxのメニューから音量・画質を調整できます",y)
        y=row("日付の切り替え","ミッションとログインは日本時間の0時に更新",y)
    elseif page=="シーズンパス" then
        y=row("現在 "..m.tier.."段","経験値 "..m.xp.."　次の段まで "..((m.tier+1)*100-m.xp),y)
        for tier=m.tier+1,m.tier+10 do y=row(tier.."段",(tier*100).." XP　"..(tier%5==0 and 300 or 100).." コイン（メールに届きます）",y) end
    else
        y=row("レースの準備","レースを選び、出走表から会場へ進みます",y)
        y=row("コインを集める","レース・ミッション・メールで獲得できます",y)
        y=row("見た目を変える","倉庫の装備はホームとレースに反映されます",y)
    end
    list.CanvasSize=UDim2.fromOffset(0,y+12)
end
request=function(action,arg)
    if pending then return end
    local token=m and m.token
    pending={action=action,arg=arg,token=token}
    task.spawn(function()
        local intent=pending
        local ok,data,message=pcall(remote.InvokeServer,remote,action,arg,token)
        if ok and data then
            m=data;pending=nil;toast.Text=type(m.last)=="string" and m.last or "";redraw()
            local feedback=toast.Text
            task.delay(3,function() if toast.Text==feedback then toast.Text="" end end)
        else
            toast.Text=ok and message or "通信を確認できません。再試行できます"
            pending=nil
            -- Reuse the original token after an uncertain save, even if this client lost the response.
            local retry=button(root,"同じ操作を再試行",8,gui.AbsoluteSize.Y-58,220,function()
                if pending then return end
                local saved=m and m.token
                if m then m.token=intent.token end
                request(intent.action,intent.arg)
                if m then m.token=saved end
            end,true)
            retry.Name="Retry"
        end
    end)
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() if m then redraw() end end)
player.PlayerGui.ChildAdded:Connect(function(child)
    if child.Name=="MinatoLobby" then child.Enabled=false end
end)
local old=player.PlayerGui:FindFirstChild("MinatoLobby")
if old then old.Enabled=false end
task.spawn(function()
    while not m do request("get");task.wait(6) end
end)

task.spawn(function()
    while gui.Parent do
        task.wait(60)
        if not pending then request("get") end
    end
end)
