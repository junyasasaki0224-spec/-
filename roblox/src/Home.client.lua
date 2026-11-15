local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Run=game:GetService("RunService")
local player=Players.LocalPlayer
local cards=require(RS:WaitForChild("CardImages"))
local visuals=require(RS:WaitForChild("VisualModels"))
local Meta=require(RS:WaitForChild("Meta"))
local Ui=require(RS:WaitForChild("HomeUi"))
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
    if x:IsA("TextLabel") or x:IsA("TextButton") or x:IsA("TextBox") then
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
-- 装備した瞬間に、カメラが艇のまわりを素早く1周する(1.1秒。始めと終わりはゆっくり)
local spinStart=-10
local SPIN_TIME=1.1
local waitLabel,matchCount,matchDeadline
local function waitText()
    if not matchDeadline then return "" end
    return string.format("%d/6 人　出走まで あと %d 秒",matchCount or 1,math.max(0,math.ceil(matchDeadline-os.clock())))
end
Run.RenderStepped:Connect(function(dt)
    sceneClock+=dt
    local cam=workspace.CurrentCamera
    if waitLabel and waitLabel.Parent then waitLabel.Text=waitText() end
    if gui.Enabled then
        cam.CameraType=Enum.CameraType.Scriptable
        local t=math.clamp((sceneClock-spinStart)/SPIN_TIME,0,1)
        local angle=.65+sceneClock*.012+math.pi*2*(t*t*(3-2*t))
        local portrait=gui.AbsoluteSize.X<gui.AbsoluteSize.Y
        local dist=portrait and 24 or 14
        cam.CFrame=CFrame.lookAt(Vector3.new(math.sin(angle)*dist,7,100+math.cos(angle)*dist),Vector3.new(0,1,100))
        if (page=="倉庫" or page=="シーズン" or page=="オンライン" or page=="イベント" or page=="タイムアタック") and not portrait then cam.CFrame=cam.CFrame*CFrame.new(-5,0,0) end
        cam.Focus=CFrame.new(0,1,100)
    end
end)
local modes={"シーズン","オンライン","タイムアタック","フレンド","大会","イベント","フリーレース","スタート練習"}
local function go(p) page=p;redraw() end
-- イベント内のランキング(サーバーから。30秒ごとに読み直す)
local eventBoard,eventLoading=nil,false
-- 大会: 一覧のタブ、サーバーから届いた一覧、作る画面の5項目、得点表を見ている大会、合言葉の入力
local gpTab,gpList,gpLoading,gpBoard,gpCode="open",nil,false,nil,""
local gpForm={name="",size=6,format="heats2",start=0,private=false}
local GP_STARTS={[0]="人数がそろったら",[5]="5分後",[15]="15分後",[30]="30分後"}
local GP_FORMATS={heats2="予選2走+優勝戦",single="1レース勝負"}
-- 大会のサーバーへの問い合わせ(結果の文言は画面の上に出す)
local function gpCall(action,arg,after)
    local remoteGp=RS:FindFirstChild("MinatoTournament")
    if not remoteGp then toast.Text="大会の準備中です";return end
    task.spawn(function()
        local ok,res=pcall(remoteGp.InvokeServer,remoteGp,action,arg)
        if not ok or type(res)~="table" then toast.Text="通信を確かめられません";return end
        if res.message then toast.Text=res.message end
        if after then after(res) end
        if page=="大会" or page=="大会を作る" or page=="大会の確認" or page=="大会の得点" then redraw() end
    end)
end
local function gpRefresh()
    if gpLoading then return end
    gpLoading=true
    gpCall("list",nil,function(res) gpLoading=false;if res.ok then gpList=res end end)
    task.delay(4,function() gpLoading=false end)
end
-- 開始の表示(日本時間の時刻、または「人数がそろったら」)
local function gpStartText(v)
    if v.startAt then return os.date("!%H:%M",v.startAt+9*3600).." 開始" end
    return "人数がそろったら開始"
end
-- タイムアタック: 選んだコース(1〜6)、コースごとのランキング(サーバーから)、読み込み中か
local taLane,taBoards,taLoading,taMessage=1,{},{},""
local LANE_COLORS={{Color3.fromRGB(242,242,240),Color3.fromRGB(17,17,17)},{Color3.fromRGB(22,22,26),white},
    {Color3.fromRGB(217,30,46),white},{Color3.fromRGB(27,80,212),white},{Color3.fromRGB(243,210,27),Color3.fromRGB(17,17,17)},{Color3.fromRGB(24,162,76),white}}
-- タイムを 1'40"2 の形にする
local function formatTime(t)
    if type(t)~="number" then return "記録なし" end
    local tenths=math.floor(t*10+.5)
    return string.format("%d'%02d\"%d",tenths//600,(tenths//10)%60,tenths%10)
end
-- コースのランキングをサーバーに聞く(1分以内に聞いた物はそのまま使う)
local function loadBoard(lane,force)
    local remoteTA=RS:FindFirstChild("MinatoTimeAttack")
    local cached=taBoards[lane]
    if not remoteTA or taLoading[lane] or (cached and not force and os.clock()-cached.at<60) then return end
    taLoading[lane]=true
    task.spawn(function()
        local ok,data=pcall(remoteTA.InvokeServer,remoteTA,"board",lane)
        taLoading[lane]=nil
        if ok and type(data)=="table" and not data.busy then taBoards[lane]={at=os.clock(),data=data} end
        if page=="タイムアタック" then redraw() end
    end)
end
local function legacy()
    local old=player.PlayerGui:FindFirstChild("MinatoLobby")
    if old then old.Enabled=true;gui.Enabled=false else toast.Text="通信機能を準備中です" end
end
local matchEvent
local waitingMode
local matchMessage=""
local matchNames={online="オンライン",ranked="シーズン",event="イベント"}
local pageKinds={["シーズン"]="ranked",["オンライン"]="online",["イベント"]="event"}
local joinActions={ranked="join",online="online",event="event"}
-- サーバーから: 文言、待っているか、モード、集まった人数、出走までの残り秒数
local function bindMatch(event)
    if event.Name~="MinatoRankedLobby" or matchEvent==event then return end
    matchEvent=event
    event.OnClientEvent:Connect(function(message,waiting,kind,count,remaining)
        waitingMode=waiting and (kind or waitingMode or "ranked") or nil
        matchMessage=type(message)=="string" and message or ""
        if waiting and type(count)=="number" and type(remaining)=="number" then
            matchCount,matchDeadline=math.clamp(count,1,6),os.clock()+math.clamp(remaining,0,120)
        elseif not waiting then
            matchCount,matchDeadline=nil,nil
        end
        if m and (pageKinds[page] or page=="ホーム") then redraw() end
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
function redraw()
    waitLabel=nil
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
        -- ブラウザ版のホームと同じ配置(左上: 選手の札・コイン・パス / 上中央: 題字 / 右上: メール・設定 /
        -- 左: タイル4つ / 右: タイル2つ / 右下: 今のモードと「レース」)。縦持ちはタイルを下に横並び
        local short=not portrait and h<450
        local misCount=0
        for _,mis in ipairs(Meta.MISSIONS) do if not m.misDone[mis.id] and (m.mis[mis.id] or 0)>=mis.goal then misCount+=1 end end
        local stats="RATE "..m.rate..(nextGrade and "　"..nextGrade.name.."まで あと"..(nextGrade.rate-m.rate).."点" or "　最高級")
        local progress=nextGrade and (m.rate-g.rate)/(nextGrade.rate-g.rate) or 1
        local name=Run:IsStudio() and "テストレーサー" or player.DisplayName
        if portrait then
            Ui.profile(root,12,8,w-24-152,g.name,name,stats,progress)
            Ui.headButton(root,"Mail","メール",w-12-140,17,70,function() go("メール") end,#m.mail)
            Ui.headButton(root,"Settings","設定",w-12-64,17,64,function() go("設定") end)
            Ui.pill(root,"Coins",tostring(m.coins),12,78,110,34,nil,true)
            Ui.pill(root,"Pass","シーズンパス "..m.tier.."段",130,78,160,34,function() go("シーズンパス") end)
            Ui.logo(root,0,122,w,30)
            local raceH=72
            local raceY=h-18-raceH
            local tileH=72
            local tileY=raceY-34-tileH
            local tw=(w-24-3*8)/4
            for i,t in ipairs({{"ガチャ","gacha"},{"倉庫","garage"},{"ミッション","mission"},{"ランキング","ranking"}}) do
                local tile=Ui.tile(root,t[1],t[2],t[1],"",12+(i-1)*(tw+8),tileY,tw,tileH,true,function() if t[1]=="ランキング" then legacy() else go(t[1]) end end)
                if t[1]=="ミッション" then Ui.badge(tile,misCount,tw-14,-8) end
            end
            local sw=(w-24-8)/2
            Ui.tile(root,"通信対戦","online","通信対戦","オンライン・フレンド",12,tileY-8-52,sw,52,false,legacy)
            Ui.tile(root,"遊び方","howto","遊び方","スタートとターンのコツ",20+sw,tileY-8-52,sw,52,false,function() go("遊び方") end)
            if waitingMode then
                local chip=frame(root,"Waiting",12,raceY-30-56,w-24,48);stroke(chip,gold,1)
                label(chip,matchNames[waitingMode].." 待機中",10,0,140,24,14).TextColor3=gold
                waitLabel=label(chip,waitText(),10,22,190,24,14)
                button(chip,"取り消し",w-24-108,1,100,function() matchEvent:FireServer("cancel") end)
            else
                local nowW=math.min(w-24,40+(utf8.len(mode) or 4)*13)
                Ui.pill(root,"Now",mode.."・オンライン対戦",w/2-nowW/2-40,raceY-30,nowW+80,24)
            end
            Ui.raceButton(root,12,raceY,w-24,raceH,"レース","モードを選んで出走",function() go(waitingMode and matchNames[waitingMode] or "レースを選ぶ") end)
            return
        end
        local pw=short and 210 or 236
        Ui.profile(root,16,short and 8 or 14,pw,g.name,name,stats,progress)
        Ui.pill(root,"Coins",tostring(m.coins),16+pw+12,short and 20 or 26,96,36,nil,true)
        Ui.pill(root,"Pass","シーズンパス "..m.tier.."段",16+pw+116,short and 20 or 26,156,36,function() go("シーズンパス") end)
        Ui.headButton(root,"Settings","設定",w-16-72,short and 8 or 14,72,function() go("設定") end)
        Ui.headButton(root,"Mail","メール",w-16-72-8-92,short and 8 or 14,92,function() go("メール") end,#m.mail)
        -- 題字は、左の札と右のボタンの間に入る時だけ
        local logoLeft,logoRight=16+pw+280,w-16-180
        if logoRight-logoLeft>=300 then Ui.logo(root,logoLeft,short and 4 or 8,logoRight-logoLeft,short and 30 or 40) end
        local tw,th,gap=short and 186 or 214,short and 52 or 66,short and 7 or 12
        local total=4*th+3*gap
        local top=math.max(short and 78 or 96,math.floor(h/2-total/2+12))
        for i,t in ipairs({{"ガチャ","gacha","塗装とヘルメットを集める"},{"倉庫","garage","艇の見た目を着せ替える"},{"ミッション","mission","毎日の目標でコイン"},{"ランキング","ranking","レート・タイム・戦績"}}) do
            local tile=Ui.tile(root,t[1],t[2],t[1],t[3],16,top+(i-1)*(th+gap),tw,th,false,function() if t[1]=="ランキング" then legacy() else go(t[1]) end end)
            if t[1]=="ミッション" then Ui.badge(tile,misCount,tw-14,-8) end
        end
        Ui.tile(root,"通信対戦","online","通信対戦","オンライン・フレンド",w-16-tw,short and 70 or 96,tw,th,false,legacy)
        Ui.tile(root,"遊び方","howto","遊び方","スタートとターンのコツ",w-16-tw,(short and 70 or 96)+th+gap,tw,th,false,function() go("遊び方") end)
        local rw=math.min(300,math.floor(w*.44))
        local rh=short and 60 or 76
        local rx,ry=w-16-rw,h-18-rh-6
        if waitingMode then
            -- 待っている間もホームの艇は見えたまま。人数と残り秒数、取り消しをレースボタンの左に出す
            local chip=frame(root,"Waiting",rx-316,ry+rh-48,300,48);stroke(chip,gold,1)
            label(chip,matchNames[waitingMode].." 待機中",10,0,140,24,14).TextColor3=gold
            waitLabel=label(chip,waitText(),10,22,190,24,14)
            button(chip,"取り消し",196,1,100,function() matchEvent:FireServer("cancel") end)
        end
        local nowText=waitingMode and (matchNames[waitingMode].." 待機中") or mode
        local nowW=math.min(rw,40+(utf8.len(nowText) or 4)*13)
        Ui.pill(root,"Now",nowText,rx+rw-nowW,ry-32,nowW,24)
        Ui.raceButton(root,rx,ry,rw,rh,"レース","モードを選んで出走",function() go(waitingMode and matchNames[waitingMode] or "レースを選ぶ") end)
        return
    end
    if page=="レースを選ぶ" then
        -- 横に流して選ぶカード8枚(ブラウザ版の .mcard)。カードを押すとそのモードへ進む
        -- 後ろの水面を少し暗くして、カードを読みやすくする
        local dim=frame(root,"Dim",0,0,w,h);dim.BackgroundColor3=Color3.fromRGB(4,14,32);dim.BackgroundTransparency=.45
        dim:FindFirstChildOfClass("UICorner"):Destroy()
        Ui.headButton(root,"Back","‹ ホーム",16,14,100,function() go("ホーム") end)
        local title=Ui.text(root,"PageTitle","レースを選ぶ",30,Ui.HEAVY_ITALIC,gold)
        title.TextXAlignment=Enum.TextXAlignment.Center
        Ui.place(title,130,14,w-260,44)
        local scroller=Instance.new("ScrollingFrame")
        scroller.Name="List";scroller.BackgroundTransparency=1;scroller.BorderSizePixel=0
        scroller.ScrollBarThickness=4;scroller.ScrollBarImageColor3=gold
        scroller.Position=UDim2.fromOffset(0,68);scroller.Size=UDim2.new(1,0,1,-74)
        scroller.Parent=root
        local names={"season","online","ta","friend","gp","event","single","practice"}
        local texts={
            {"ランク戦。着順でレートと級が動く","B2 → A1 を目指す"},{"6人のカジュアル戦。レートなし","空きは AI（達人）"},
            {"枠を選んで1艇で3周。ベストを狙う","コースごとに記録"},{"合言葉で部屋を作って対戦","フレンドと"},
            {"予選2走＋優勝戦。自分で開催も","優勝を目指す"},{"日替わりの特別レース","コイン2倍"},
            {"好きな枠で気軽に1レース","気軽に"},{"スタートだけを何度でも","STを磨く"},
        }
        local function open(name)
            mode=name
            if pageKinds[name] then go(name)
            elseif name=="タイムアタック" then go(name)
            elseif name=="大会" then gpList=nil;go(name)
            elseif name=="フレンド" or name=="フリーレース" then legacy()
            else toast.Text=name.."は準備中です" end
        end
        if portrait then
            local cw,ch,gap=w-32,250,14
            for i,name in ipairs(modes) do
                Ui.modeCard(scroller,"Mode"..i,name,cards[names[i]],texts[i][1],texts[i][2],16,(i-1)*(ch+gap),cw,ch,mode==name,function() open(name) end)
            end
            scroller.ScrollingDirection=Enum.ScrollingDirection.Y
            scroller.CanvasSize=UDim2.fromOffset(0,8*(ch+gap)+16)
        else
            local ch=math.min(400,h-90)
            local cw=math.min(270,math.max(170,math.floor(w*.3)))
            local gap=w<900 and 14 or 24
            for i,name in ipairs(modes) do
                Ui.modeCard(scroller,"Mode"..i,name,cards[names[i]],texts[i][1],texts[i][2],16+(i-1)*(cw+gap),4,cw,ch,mode==name,function() open(name) end)
            end
            scroller.ScrollingDirection=Enum.ScrollingDirection.X
            scroller.CanvasSize=UDim2.fromOffset(32+8*cw+7*gap,0)
        end
        return
    end
    local side=page=="倉庫" or pageKinds[page]~=nil or page=="タイムアタック" or page=="大会" or page=="大会を作る" or page=="大会の確認" or page=="大会の得点"
    local panelWidth=side and math.min(w-16,(pageKinds[page] or page=="タイムアタック") and 460 or (page=="倉庫" and 640 or 560)) or w-16
    -- 待ち合わせの画面はスマホ縦なら上半分だけにして、下に自分の艇を見せる
    local panelHeight=(pageKinds[page] and portrait) and math.min(h-16,math.floor(h*.55)) or h-16
    -- ブラウザ版の .panel(紺の半透明・白の細枠・角丸18)と、上の「‹ ホーム」・題・コイン
    local panel=frame(root,"Panel",8,8,panelWidth,panelHeight)
    panel.BackgroundColor3=Color3.fromRGB(9,24,50);panel.BackgroundTransparency=.16
    panel:FindFirstChildOfClass("UICorner").CornerRadius=UDim.new(0,18)
    stroke(panel,white,1).Transparency=.78
    Ui.headButton(panel,"ホーム","‹ ホーム",10,10,96,function() go("ホーム") end)
    local head=Ui.text(panel,"PageTitle",page,portrait and 17 or 21,Ui.HEAVY,white)
    head.TextXAlignment=Enum.TextXAlignment.Center
    Ui.place(head,112,10,math.max(90,panelWidth-224),44)
    Ui.pill(panel,"Coins",tostring(m.coins),panelWidth-106,14,96,36,nil,true)
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
    if pageKinds[page] then
        local kind=pageKinds[page]
        if kind=="online" then
            y=row("6人で対戦","着順でレートは変わりません",y)
        elseif kind=="event" then
            local ev=Meta.eventOf(Meta.today())
            y=row("今日のイベント　"..ev.name,ev.desc,y)
            y=row("コイン2倍","レートは変わりません。日本時間0時に入れ替わります",y)
            -- 今日のイベント内のランキング(着順の得点 10・8・6・4・2・1 の合計)
            local remoteEv=RS:FindFirstChild("MinatoEventBoard")
            if remoteEv and (not eventBoard or os.clock()-eventBoard.at>30) and not eventLoading then
                eventLoading=true
                task.spawn(function()
                    local ok,res=pcall(remoteEv.InvokeServer,remoteEv)
                    eventLoading=false
                    if ok and type(res)=="table" and not res.busy then eventBoard={at=os.clock(),data=res} end
                    if page=="イベント" then redraw() end
                end)
            end
            local ev2=eventBoard and eventBoard.data
            local mine=ev2 and ev2.mine
            y=row("今日のランキング",mine and (mine.rank.."位　"..mine.points.."点（"..mine.races.."レース）") or "イベントを走ると、着順の得点（10・8・6・4・2・1）がたまります",y)
            for _,r in ipairs(ev2 and ev2.rows or {}) do
                if r.rank>10 and not r.me then continue end
                local line=frame(list,"EventRank"..r.rank,8,y,width-16,30)
                line.BackgroundTransparency=r.me and .55 or .85
                if r.me then line.BackgroundColor3=gold end
                label(line,r.rank.."位",8,0,56,30,15)
                label(line,r.name,66,0,width-190,30,15)
                local pts=label(line,r.points.."点",width-110,0,90,30,15);pts.TextXAlignment=Enum.TextXAlignment.Right
                y+=34
            end
            y+=8
        else
            y=row("シーズン戦","近いレートの選手から相手を探します",y)
        end
        y=row("待ち合わせ","2人以上なら30秒、1人なら60秒で、空きを AI（達人）で埋めて出走",y)
        if waitingMode and waitingMode~=kind then
            y=row(matchNames[waitingMode].."で待機中","モードを切り替えるには待機を終了してください",y,
                function() go(matchNames[waitingMode]) end,"待機画面へ")
        elseif matchEvent then
            if waitingMode then
                label(list,"参加者を待っています",8,y,width-16,30,17)
                waitLabel=label(list,waitText(),8,y+31,width-16,28,16);waitLabel.TextColor3=gold
                label(list,matchMessage,8,y+59,width-16,24,14).TextColor3=pale
                button(list,"待機をやめる",8,y+89,math.min(width-16,170),function() matchEvent:FireServer("cancel") end,true)
                y+=149
            else
                y=row("出走受付",matchMessage~="" and matchMessage or "参加すると会場を探します",y,function()
                    matchEvent:FireServer(joinActions[kind])
                end,"参加する")
            end
        else
            y=row("受付の準備中","通信の準備ができると参加できます",y)
        end
    elseif page=="タイムアタック" then
        -- コースを選ぶ → 自己ベスト・世界1位・フレンド1位 → 走る → 上位のランキング
        label(list,"コースを選ぶ（1艇・無風で3周）",8,y,width-16,26,15).TextColor3=pale
        y+=30
        local bw=math.min(64,math.floor((width-16-5*6)/6))
        for lane=1,6 do
            local b=box("TextButton",list,"Lane"..lane,tostring(lane))
            b.Position=UDim2.fromOffset(8+(lane-1)*(bw+6),y);b.Size=UDim2.fromOffset(bw,48)
            b.BackgroundTransparency=0;b.BackgroundColor3=LANE_COLORS[lane][1];b.TextColor3=LANE_COLORS[lane][2];b.TextSize=20
            stroke(b,lane==taLane and gold or white,lane==taLane and 3 or 1)
            b.Activated:Connect(function() taLane=lane;taMessage="";redraw() end)
        end
        y+=60
        loadBoard(taLane)
        local entry=taBoards[taLane]
        local data=entry and entry.data
        local best=m.ta and m.ta[tostring(taLane-1)]
        local world,friend=data and data.worldTop,data and data.friendTop
        y=row("自己ベスト　"..formatTime(best),data and data.mine and ("世界 "..data.mine.rank.."位") or "世界ランキングは上位100位まで",y)
        if data and data.offline then
            y=row("世界ランキング","公開したゲームで表示されます（Studio では保存しません）",y)
        elseif data and data.failed then
            y=row("世界ランキング","読み込めませんでした。少し待ってから開き直してください",y)
        elseif data then
            y=row("世界1位　"..(world and formatTime(world.ms/1000) or "記録なし"),world and world.name or "最初の記録を残そう",y)
            y=row("フレンド1位　"..(friend and formatTime(friend.ms/1000) or "記録なし"),friend and (friend.name.."　世界 "..friend.rank.."位") or "上位100位にいるフレンドを表示します",y)
        else
            y=row("世界ランキング","読み込んでいます",y)
        end
        if world then y=row("ゴースト","世界1位の走りが半透明の艇で一緒に走ります",y) end
        button(list,"このコースで走る",8,y,math.min(width-16,240),function()
            local remoteTA=RS:FindFirstChild("MinatoTimeAttack")
            if not remoteTA then return end
            taMessage="会場を探しています"
            redraw()
            task.spawn(function()
                local ok,res=pcall(remoteTA.InvokeServer,remoteTA,"run",taLane)
                taMessage=ok and type(res)=="table" and (res.message or "") or "通信を確認できません"
                if page=="タイムアタック" then redraw() end
            end)
        end,true)
        y+=56
        if taMessage~="" then label(list,taMessage,8,y,width-16,24,14).TextColor3=gold;y+=30 end
        if data and data.top and #data.top>0 then
            label(list,"世界ランキング　"..taLane.."コース",8,y,width-16,28,16).TextColor3=gold
            y+=32
            for _,r in ipairs(data.top) do
                local line=frame(list,"Rank"..r.rank,8,y,width-16,30)
                line.BackgroundTransparency=r.me and .55 or .85
                if r.me then line.BackgroundColor3=gold end
                label(line,r.rank.."位",8,0,56,30,15)
                local who=label(line,r.name..(r.friend and "　フレンド" or ""),66,0,width-200,30,15)
                if r.friend then who.TextColor3=pale end
                local t=label(line,formatTime(r.ms/1000),width-120,0,100,30,15);t.TextXAlignment=Enum.TextXAlignment.Right
                y+=34
            end
        end
    elseif page=="大会" then
        -- タブ(受付中・開催中・終了)と「大会を作る」。カードは名前・主催者・人数・開始・形式・ボタン
        if not gpList then gpRefresh() end
        local tabs={{"open","受付中"},{"running","開催中"},{"done","終了"}}
        local tw=math.floor((width-16-16)/3)
        for i,t in ipairs(tabs) do
            local b=button(list,t[2],8+(i-1)*(tw+8),y,tw,function() gpTab=t[1];redraw() end,gpTab==t[1])
            b.Name="Tab_"..t[1]
        end
        y+=56
        local createB=button(list,"大会を作る",8,y,math.min(width-16,200),function() go("大会を作る") end)
        createB.Name="CreateTournament"
        button(list,"更新",math.min(width-16,200)+16,y,90,function() gpList=nil;gpRefresh();redraw() end)
        y+=58
        local items=gpList and gpList.tabs and gpList.tabs[gpTab] or nil
        if not items then
            y=row("読み込んでいます","少し待ってください",y)
        elseif #items==0 then
            y=row(gpTab=="open" and "受付中の大会はありません" or (gpTab=="running" and "開催中の大会はありません" or "終わった大会はありません"),
                gpTab=="open" and "「大会を作る」で開催できます" or "",y)
        end
        for i,v in ipairs(items or {}) do
            local card=frame(list,"Tournament"..i,8,y,width-16,150);stroke(card,v.entrant and gold or white,v.entrant and 2 or 1)
            label(card,v.name,12,6,width-150,28,17)
            label(card,(v.private and "合言葉　" or "だれでも　")..v.count.."/"..v.size.." 人",width-150,6,130,28,15).TextColor3=gold
            label(card,"主催 "..v.hostName.."　"..v.format.."　"..gpStartText(v),12,36,width-40,24,14).TextColor3=pale
            if v.code then label(card,"合言葉 "..v.code,12,60,width-40,22,14).TextColor3=gold end
            local bx=12
            local function cb(text,fn,primary)
                local b=button(card,text,bx,94,140,fn,primary);bx+=148;return b
            end
            if v.status=="open" or v.status=="starting" then
                if v.host then
                    cb("開始を早める",function() gpCall("startNow",v.id,function() gpList=nil;gpRefresh() end) end,true)
                    cb("中止",function() gpCall("cancel",v.id,function() gpList=nil;gpRefresh() end) end)
                elseif v.entrant then
                    cb("参加をやめる",function() gpCall("leave",v.id,function() gpList=nil;gpRefresh() end) end)
                else
                    if v.private then
                        local input=box("TextBox",card,"Code","");input.Position=UDim2.fromOffset(bx,94);input.Size=UDim2.fromOffset(110,46)
                        input.PlaceholderText="合言葉";input.Text=gpCode;input.ClearTextOnFocus=false;stroke(input,white,1)
                        input.FocusLost:Connect(function() gpCode=string.upper(input.Text) end)
                        bx+=118
                    end
                    cb("参加する",function() gpCall("join",{id=v.id,code=v.private and gpCode or nil},function() gpList=nil;gpRefresh() end) end,true)
                end
            elseif v.status=="running" or v.status=="final" then
                cb("得点表",function() gpBoard=v.id;go("大会の得点") end,true)
                cb("観戦する",function() gpCall("watch",v.id) end)
                if v.host then cb("中止",function() gpCall("cancel",v.id,function() gpList=nil;gpRefresh() end) end) end
            else
                label(card,v.status=="canceled" and "中止" or ("優勝 "..(v.champion or "")),12,98,width-180,36,17).TextColor3=gold
                bx=width-170
                cb("得点表",function() gpBoard=v.id;go("大会の得点") end)
            end
            y+=162
        end
    elseif page=="大会を作る" then
        -- 5項目だけ(ほかは決まった値)。名前は20文字まで、サーバーが文字フィルターに通す
        label(list,"1. 大会名（20文字まで）",8,y,width-16,26,15).TextColor3=pale
        local nameBox=box("TextBox",list,"TournamentName","");nameBox.Position=UDim2.fromOffset(8,y+28);nameBox.Size=UDim2.fromOffset(math.min(width-16,360),46)
        nameBox.PlaceholderText="例: 週末みなと杯";nameBox.Text=gpForm.name;nameBox.ClearTextOnFocus=false;stroke(nameBox,white,1)
        nameBox.TextXAlignment=Enum.TextXAlignment.Left
        local pad=Instance.new("UIPadding");pad.PaddingLeft=UDim.new(0,10);pad.Parent=nameBox
        nameBox:GetPropertyChangedSignal("Text"):Connect(function() gpForm.name=nameBox.Text end)
        y+=86
        local function choices(title,key,options)
            label(list,title,8,y,width-16,26,15).TextColor3=pale
            y+=28
            local bw=math.floor((width-16-8*(#options-1))/#options)
            for i,o in ipairs(options) do
                local b=button(list,o[2],8+(i-1)*(bw+8),y,bw,function() gpForm[key]=o[1];redraw() end,gpForm[key]==o[1])
                b.Name=key.."_"..tostring(o[1])
            end
            y+=58
        end
        choices("2. 人数","size",{{6,"6人"},{12,"12人"},{18,"18人"},{24,"24人"}})
        choices("3. 形式","format",{{"heats2","予選2走+優勝戦"},{"single","1レース勝負"}})
        choices("4. 開始","start",{{0,"そろったら"},{5,"5分後"},{15,"15分後"},{30,"30分後"}})
        choices("5. 公開","private",{{false,"だれでも"},{true,"合言葉"}})
        label(list,"時間になって人数が足りなければ、空きを AI（達人）で埋めます",8,y,width-16,24,14).TextColor3=pale
        y+=32
        local nextB=button(list,"内容を確認する",8,y,math.min(width-16,240),function()
            if (utf8.len(gpForm.name) or 0)<1 then toast.Text="大会名を入れてください";return end
            if (utf8.len(gpForm.name) or 99)>20 then toast.Text="大会名は20文字までです";return end
            go("大会の確認")
        end,true)
        nextB.Name="ToConfirm"
        y+=58
        button(list,"大会の一覧へ",8,y,math.min(width-16,240),function() go("大会") end);y+=58
    elseif page=="大会の確認" then
        -- 作る前に、設定のまとめを1枚で見せる
        y=row("大会名",gpForm.name,y)
        y=row("人数",gpForm.size.." 人（6人ずつの組で予選）",y)
        y=row("形式",GP_FORMATS[gpForm.format],y)
        y=row("開始",GP_STARTS[gpForm.start]..(gpForm.start>0 and "（足りなければ AI で埋める）" or ""),y)
        y=row("公開",gpForm.private and "合言葉（6文字のコードを伝えた人だけ）" or "だれでも参加できる",y)
        y=row("得点","予選の着順 10・8・6・4・2・1 点、得点の上位6人で優勝戦",y)
        local ok=button(list,"この内容で開催",8,y,math.min(width-16,240),function()
            gpCall("create",{name=gpForm.name,size=gpForm.size,format=gpForm.format,start=gpForm.start,private=gpForm.private},function(res)
                if res.ok then gpForm.name="";gpList=nil;gpTab="open";page="大会";gpRefresh() end
            end)
        end,true)
        ok.Name="CreateConfirm"
        y+=58
        button(list,"戻って直す",8,y,math.min(width-16,240),function() go("大会を作る") end);y+=58
    elseif page=="大会の得点" then
        -- 得点表(全員の予選の着順と得点)。優勝戦に進む人に印。観戦のボタン
        local view=gpList and gpList.board
        if not view or view.id~=gpBoard then
            y=row("読み込んでいます","",y)
            gpCall("board",gpBoard,function(res) if res.ok and gpList then gpList.board=res.view elseif res.ok then gpList={board=res.view} end end)
        else
            y=row(view.name,"主催 "..view.hostName.."　"..view.format.."　"..view.count.." 人",y)
            if view.champion then y=row("優勝 "..view.champion,"",y) end
            for i,st in ipairs(view.standings) do
                local line=frame(list,"Standing"..i,8,y,width-16,32)
                line.BackgroundTransparency=st.me and .55 or .85
                if st.me then line.BackgroundColor3=gold end
                local marks={}
                for _,h in ipairs(st.history) do table.insert(marks,tostring(h)) end
                label(line,i.."位",8,0,50,32,15)
                label(line,st.name..(st.final and "　優勝戦" or ""),60,0,width-240,32,15)
                label(line,table.concat(marks,"・"),width-180,0,80,32,14).TextColor3=pale
                local pts=label(line,st.points.." 点",width-100,0,80,32,15);pts.TextXAlignment=Enum.TextXAlignment.Right
                y+=36
            end
            if #view.standings==0 then y=row("まだ得点はありません","予選が終わると表示されます",y) end
            y+=8
            if view.status=="running" or view.status=="final" then
                button(list,"観戦する",8,y,math.min(width-16,200),function() gpCall("watch",view.id) end,true);y+=58
            end
            button(list,"更新",8,y,math.min(width-16,200),function() if gpList then gpList.board=nil end;redraw() end);y+=58
        end
        button(list,"大会の一覧へ",8,y,math.min(width-16,200),function() gpList=nil;go("大会") end);y+=58
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
        -- いちばん上に「装備中」: 塗装とヘルメットを色見本・名前・レア度で出す
        label(list,"装備中",8,0,120,26,16).TextColor3=gold
        for k,id in ipairs({m.skin,m.helmet}) do
            local it=Meta.item(id)
            if it then
                local cardW=math.floor((width-24)/2)
                local now=frame(list,"Equipped"..k,8+(k-1)*(cardW+8),28,cardW,64);stroke(now,rarity[it.r],2)
                swatch(now,it,8,8,44,48)
                label(now,it.name,60,6,cardW-66,28,15)
                label(now,(it.kind=="skin" and "塗装 " or "ヘルメット ")..it.r,60,34,cardW-66,22,12).TextColor3=rarity[it.r]
            end
        end
        y=104
        local columns=math.max(1,math.floor(width/175));local cw=math.floor(width/columns)-8
        for i,it in ipairs(Meta.ITEMS) do
            local x=((i-1)%columns)*(cw+8);local cy=y+math.floor((i-1)/columns)*156
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
        y+=math.ceil(#Meta.ITEMS/columns)*156
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
-- 装備した瞬間の演出: しぶきの粒、レア度の色で光る知らせ(2秒)、レア度に合わせた音、カメラの1周
local RARITY_PITCH={N=1,R=1.12,SR=1.26,SSR=1.45}
local splash=Instance.new("Part");splash.Name="EquipSplash";splash.Anchored=true;splash.CanCollide=false
splash.Transparency=1;splash.Size=Vector3.new(1,1,1);splash.CFrame=CFrame.new(0,1,100);splash.Parent=scenery
local sparks=Instance.new("ParticleEmitter")
sparks.Texture="rbxasset://textures/particles/sparkles_main.dds";sparks.Enabled=false
sparks.Lifetime=NumberRange.new(.6,1.1);sparks.Speed=NumberRange.new(6,14);sparks.SpreadAngle=Vector2.new(70,70)
sparks.Acceleration=Vector3.new(0,-18,0);sparks.Size=NumberSequence.new(.5,.1)
sparks.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(1,1)})
sparks.Parent=splash
local function sound(id,pitch,volume)
    local s=Instance.new("Sound");s.SoundId=id;s.PlaybackSpeed=pitch;s.Volume=volume;s.Parent=gui
    s.Ended:Connect(function() s:Destroy() end);s:Play()
end
local function celebrate(it)
    local color=rarity[it.r]
    spinStart=sceneClock
    sparks.Color=ColorSequence.new(Color3.fromRGB(226,244,246),color)
    sparks:Emit(it.r=="SSR" and 90 or (it.r=="SR" and 60 or 36))
    sound("rbxasset://sounds/impact_water.mp3",1,.5)
    for k=1,(it.r=="SSR" and 3 or (it.r=="SR" and 2 or 1)) do
        task.delay((k-1)*.13,function() sound("rbxasset://sounds/volume_slider.ogg",RARITY_PITCH[it.r]+(k-1)*.12,.7) end)
    end
    local w,h=gui.AbsoluteSize.X,gui.AbsoluteSize.Y
    local portrait=w<h
    local note=box("TextLabel",gui,"EquipNotice",(it.kind=="skin" and "塗装を装備　" or "ヘルメットを装備　")..it.name.."　"..it.r)
    note.Size=UDim2.fromOffset(math.min(w-24,360),48)
    note.Position=portrait and UDim2.fromOffset(12,70) or UDim2.fromOffset(w-math.min(w-24,360)-12,h-120)
    note.TextColor3=color;note.ZIndex=20;note.TextSize=16
    local glow=stroke(note,color,it.r=="N" and 1 or 3);glow.Transparency=0
    task.delay(2,function() note:Destroy() end)
end
request=function(action,arg)
    if pending then return end
    local token=m and m.token
    pending={action=action,arg=arg,token=token}
    task.spawn(function()
        local intent=pending
        local ok,data,message=pcall(remote.InvokeServer,remote,action,arg,token)
        if ok and data then
            local before=m and {m.skin,m.helmet}
            m=data;pending=nil;toast.Text=type(m.last)=="string" and m.last or "";redraw()
            if action=="equip" and before and (m.skin~=before[1] or m.helmet~=before[2]) then
                local it=Meta.item(m.skin~=before[1] and m.skin or m.helmet)
                if it then toast.Text="";celebrate(it) end
            end
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
-- 大会の知らせ(始まった・中止・優勝)を画面の上に6秒出す
task.spawn(function()
    local event=RS:WaitForChild("MinatoTournamentNotice",30)
    if not event then return end
    event.OnClientEvent:Connect(function(message)
        if type(message)~="string" then return end
        toast.Text=message
        task.delay(6,function() if toast.Text==message then toast.Text="" end end)
    end)
end)
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
