local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local SocialService = game:GetService("SocialService")
local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("MinatoInput")
local snapshotRemote = ReplicatedStorage:WaitForChild("MinatoSnapshots")
local setupRemote = ReplicatedStorage:WaitForChild("MinatoSetup")
local roomRemote = ReplicatedStorage:WaitForChild("MinatoRoomRace")
local roomInfo = ReplicatedStorage:WaitForChild("MinatoRoomInfo")
local stepBoat = require(ReplicatedStorage:WaitForChild("BoatPhysics"))
local reconcile = require(ReplicatedStorage:WaitForChild("Reconciliation"))
local Sfx = require(ReplicatedStorage:WaitForChild("Sfx"))
local world = workspace:WaitForChild("Minato")
local templates = ReplicatedStorage:WaitForChild("MinatoTemplates")
local boat = templates:WaitForChild("Boat1")
local updateVenue = require(ReplicatedStorage:WaitForChild("VenueDecor"))(world,templates)
local visuals=require(ReplicatedStorage:WaitForChild("VisualModels"))
local outfit=require(ReplicatedStorage:WaitForChild("Outfit"))
local STUDS_PER_METRE = 3.5
local Wake = require(ReplicatedStorage:WaitForChild("BoatWake"))
local quality=require(ReplicatedStorage:WaitForChild("DisplayQuality"))
local function applyQuality() quality.apply(player:GetAttribute("MinatoQuality")) end
player:GetAttributeChangedSignal("MinatoQuality"):Connect(applyQuality)
applyQuality()
local camera = workspace.CurrentCamera
local renderBoats, wakes, motion, latest = {}, {}, {}, {}
for i = 1, 6 do
    local original = templates:WaitForChild("Boat"..i)
    local visual = original:Clone()
    local baseColors={}
    for _,p in ipairs(visual:GetDescendants()) do if p:IsA("BasePart") then baseColors[p]=p.Color end end
    local function refreshOutfit()
        for part,color in pairs(baseColors) do part.Color=color end
        local stripe=visual:FindFirstChild("HelmetStripe")
        if stripe then stripe:Destroy() end
        outfit(visual,original:GetAttribute("Skin"),original:GetAttribute("HelmetStyle"))
    end
    original:GetAttributeChangedSignal("Skin"):Connect(refreshOutfit)
    original:GetAttributeChangedSignal("HelmetStyle"):Connect(refreshOutfit)
    refreshOutfit()
    visual.Name = "VisualBoat"..i
    visual.Parent = workspace
    local foam = Wake.new(visual.PrimaryPart)
    -- エンジン音は艇の位置から聞こえる(近いほど大きい)
    local engine = Sfx.loop("engine", visual.PrimaryPart)
    if engine then
        engine.RollOffMode = Enum.RollOffMode.InverseTapered
        engine.RollOffMinDistance = 22*STUDS_PER_METRE
        engine.RollOffMaxDistance = 140*STUDS_PER_METRE
    end
    foam.engine = engine
    wakes[i] = foam
    motion[i] = {roll=0,yaw=0,pitch=0}
    renderBoats[i] = visual
end
local predicted, predictedNumber, running = nil, 0, false
local predictionAccumulator = 0
local inputSequence, currentSequence = 0, 0
local sentThrottle, sentSteer = 0,0
local pendingSteps = {}
local predictionRace = nil
local viewing, serverClock, seatNumber, resultRows
-- 最後にサーバーの時計を受け取った時刻(その間の時計は手元で進める)
local snapshotAt = os.clock()
local roundChanged = false
-- タイムアタックのゴースト(世界1位の走り)。半透明の艇で見せる。サーバーから位置だけが届く
local ghostState
local ghostVisual = boat:Clone()
ghostVisual.Name = "GhostBoat"
for _, p in ipairs(ghostVisual:GetDescendants()) do
    if p:IsA("BasePart") then
        p.Transparency = p.Transparency >= 1 and 1 or 0.4
        p.CastShadow = false
        p.Color = p.Color:Lerp(Color3.fromRGB(170,230,255), 0.55)
    end
end
-- 水面の上でも見分けやすいように、水色の輪郭を付ける
local ghostOutline = Instance.new("Highlight")
ghostOutline.FillTransparency = 1
ghostOutline.OutlineColor = Color3.fromRGB(150,225,255)
ghostOutline.OutlineTransparency = 0.1
ghostOutline.DepthMode = Enum.HighlightDepthMode.Occluded
ghostOutline.Parent = ghostVisual
snapshotRemote.OnClientEvent:Connect(function(states, active, acknowledged, raceNumber, clock, seat, results, ghost)
    if predictionRace ~= raceNumber then roundChanged=true end
    serverClock,seatNumber,resultRows=clock,seat,results
    snapshotAt = os.clock()
    ghostState = type(ghost) == "table" and ghost or nil
    latest, running = states, active
    local number = seat
    local state = states[number]
    if not active or not state or state[17] ~= "" or state[19] then
        predicted=nil; predictedNumber=0; pendingSteps={}; currentSequence=0; predictionRace=raceNumber
        sentThrottle,sentSteer=0,0
        return
    end
    if predictedNumber ~= number or predictionRace ~= raceNumber then
        pendingSteps={}
        predictedNumber = number
        predictionRace = raceNumber
        predictionAccumulator = 0
    end
    predicted,pendingSteps = reconcile(state,pendingSteps,acknowledged,stepBoat)
end)

local gui = Instance.new("ScreenGui")
gui.Name = "MinatoHUD"
gui.ResetOnSpawn = false
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
gui.Parent = player:WaitForChild("PlayerGui")
viewing = require(ReplicatedStorage:WaitForChild("Spectator"))(gui)
local function label(name, text, size, position, textSize)
    local item = Instance.new("TextLabel")
    item.Name, item.Text, item.Size, item.Position = name,text,size,position
    item.BackgroundColor3 = Color3.fromRGB(15,32,43)
    item.BackgroundTransparency = 0.22
    item.TextColor3 = Color3.new(1,1,1)
    item.Font = Enum.Font.GothamBold
    item.TextSize = textSize
    item.Parent = gui
    local function height()
        local shift=math.clamp((player:GetAttribute("MinatoLever") or 40)-40,-40,math.max(0,gui.AbsoluteSize.Y-285))
        item.Position=position-UDim2.fromOffset(0,shift)
    end
    player:GetAttributeChangedSignal("MinatoLever"):Connect(height)
    gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(height)
    height()
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0,8)
    corner.Parent = item
    return item
end
local roomPanel = Instance.new("Frame")
roomPanel.Name = "Room"
roomPanel.Size = UDim2.fromOffset(210,70)
roomPanel.Position = UDim2.new(0.5,-105,0,4)
roomPanel.BackgroundTransparency = 1
roomPanel.Visible = false
roomPanel.Parent = gui
local roomTitle = Instance.new("TextLabel")
roomTitle.Size = UDim2.new(1,0,0,28)
roomTitle.BackgroundColor3 = Color3.fromRGB(15,32,43)
roomTitle.TextColor3 = Color3.new(1,1,1)
roomTitle.Font = Enum.Font.GothamBold
roomTitle.TextSize = 14
roomTitle.Parent = roomPanel
local function roomButton(caption,x)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(0.5,-2,0,32)
    button.Position = UDim2.new(x,0,0,31)
    button.BackgroundColor3 = Color3.fromRGB(35,122,137)
    button.TextColor3 = Color3.new(1,1,1)
    button.Font = Enum.Font.GothamBold
    button.TextSize = 14
    button.Text = caption
    button.Parent = roomPanel
    return button
end
local startRoom = roomButton("レース開始",0)
local inviteRoom = roomButton("友達を招待",0.5)
local roomCode
local function updateRoom()
    local mode = world:GetAttribute("RoomMode")
    local code = roomCode
    roomPanel.Visible = mode == true and type(code) == "string"
    roomTitle.Text = "合言葉 "..(code or "")..(world:GetAttribute("RoomWaiting") and "　待機中" or "")
    startRoom.Visible = world:GetAttribute("RoomWaiting") == true and world:GetAttribute("RoomHost") == player.UserId
end
for _, name in ipairs({"RoomMode","RoomWaiting","RoomHost"}) do
    world:GetAttributeChangedSignal(name):Connect(updateRoom)
end
updateRoom()
task.spawn(function()
    -- The folder can arrive before its attributes replicate.
    while gui.Parent and world:GetAttribute("RoomMode") == nil do task.wait(0.2) end
    if not gui.Parent or not world:GetAttribute("RoomMode") then return end
    while gui.Parent and world:GetAttribute("RoomMode") and not roomCode do
        local ok, result = pcall(roomInfo.InvokeServer,roomInfo)
        if ok and type(result) == "string" then roomCode=result; updateRoom(); break end
        task.wait(1)
    end
end)
startRoom.Activated:Connect(function() roomRemote:FireServer("start") end)
inviteRoom.Activated:Connect(function()
    local code = roomCode
    if type(code) ~= "string" then return end
    local ok, canInvite = pcall(SocialService.CanSendGameInviteAsync,SocialService,player)
    if not ok or not canInvite then roomTitle.Text="招待できません。合言葉を伝えてください"; return end
    local options = Instance.new("ExperienceInviteOptions")
    options.LaunchData = code
    local shown = pcall(SocialService.PromptGameInvite,SocialService,player,options)
    if not shown then roomTitle.Text="招待できません。合言葉を伝えてください" end
end)

local rankedPanel = Instance.new("TextButton")
rankedPanel.Size = UDim2.fromOffset(210,42)
rankedPanel.Position = UDim2.new(0.5,-105,0,4)
rankedPanel.BackgroundColor3 = Color3.fromRGB(85,65,32)
rankedPanel.TextColor3 = Color3.new(1,1,1)
rankedPanel.Font = Enum.Font.GothamBold
rankedPanel.TextSize = 14
rankedPanel.Visible = false
rankedPanel.Parent = gui
local function updateRanked()
    local phase=world:GetAttribute("RankedPhase")
    rankedPanel.Visible = phase == "waiting" or phase == "finished" or phase == "incomplete" or phase == "between"
    local names = {ranked="シーズン", online="オンライン", event="イベント", ta="タイムアタック", gp="大会"}
    rankedPanel.Text = phase == "finished" and "終了：ロビーに戻る" or phase == "incomplete" and "参加者が来ませんでした：ロビーに戻る"
        or phase == "between" and "大会：次の走りの準備中"
        or (names[world:GetAttribute("MatchMode")] or "シーズン").."：参加者の到着を待っています"
end
world:GetAttributeChangedSignal("RankedPhase"):Connect(updateRanked)
updateRanked()
rankedPanel.Activated:Connect(function()
    local phase=world:GetAttribute("RankedPhase")
    if phase=="finished" or phase=="incomplete" then roomRemote:FireServer("return") end
end)
-- タイムアタックの結果(タイム・自己ベスト更新・世界の順位)と「もう一度走る」
local taResult = Instance.new("TextLabel")
taResult.Name = "TimeAttackResult"
taResult.Size = UDim2.fromOffset(360,40)
taResult.Position = UDim2.new(0.5,-180,0,50)
taResult.BackgroundColor3 = Color3.fromRGB(11,29,58)
taResult.BackgroundTransparency = 0.12
taResult.TextColor3 = Color3.fromRGB(255,210,60)
taResult.Font = Enum.Font.GothamBold
taResult.TextSize = 16
taResult.TextTruncate = Enum.TextTruncate.AtEnd
taResult.Visible = false
taResult.Parent = gui
do local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,10); corner.Parent = taResult end
local again = Instance.new("TextButton")
again.Name = "Again"
again.Size = UDim2.fromOffset(200,44)
again.Position = UDim2.new(0.5,-100,0,96)
again.BackgroundColor3 = Color3.new(1,1,1)
again.TextColor3 = Color3.fromRGB(26,18,0)
again.Font = Enum.Font.GothamBold
again.TextSize = 16
again.Text = "もう一度走る"
again.Visible = false
again.Parent = gui
do
    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,10); corner.Parent = again
    local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(Color3.fromRGB(255,224,102),Color3.fromRGB(245,164,0)); g.Rotation = 90; g.Parent = again
end
again.Activated:Connect(function()
    taResult.Visible = false
    roomRemote:FireServer("again")
end)
local function updateTimeAttack()
    local ta = world:GetAttribute("MatchMode") == "ta"
    local phase = world:GetAttribute("RankedPhase")
    again.Visible = ta and phase == "finished"
    if ta and phase == "racing" then taResult.Visible = false end
end
world:GetAttributeChangedSignal("RankedPhase"):Connect(updateTimeAttack)
world:GetAttributeChangedSignal("MatchMode"):Connect(updateTimeAttack)
updateTimeAttack()
-- 大会の得点表(サーバーが会場の属性 GpBoard で配る)。レース中は隠し、レースの合間と終わりに出す
local gpBoard = Instance.new("TextLabel")
gpBoard.Name = "TournamentBoard"
gpBoard.Size = UDim2.fromOffset(380,170)
gpBoard.Position = UDim2.new(0.5,-190,0,96)
gpBoard.BackgroundColor3 = Color3.fromRGB(11,29,58)
gpBoard.BackgroundTransparency = 0.12
gpBoard.TextColor3 = Color3.new(1,1,1)
gpBoard.Font = Enum.Font.GothamBold
gpBoard.TextSize = 15
gpBoard.TextXAlignment = Enum.TextXAlignment.Left
gpBoard.TextYAlignment = Enum.TextYAlignment.Top
gpBoard.Visible = false
gpBoard.Parent = gui
do
    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,12); corner.Parent = gpBoard
    local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0,12); pad.PaddingTop = UDim.new(0,8); pad.Parent = gpBoard
    local edge = Instance.new("UIStroke"); edge.Color = Color3.fromRGB(255,210,60); edge.Transparency = 0.3; edge.Parent = gpBoard
end
local watchFinal = again:Clone()
watchFinal.Name = "WatchFinal"
watchFinal.Text = "優勝戦を観戦する"
watchFinal.Position = UDim2.new(0.5,-100,0,274)
watchFinal.Visible = false
watchFinal.Parent = gui
watchFinal.Activated:Connect(function() roomRemote:FireServer("watchFinal") end)
local function updateTournament()
    local text = world:GetAttribute("GpBoard")
    local phase = world:GetAttribute("RankedPhase")
    gpBoard.Text = type(text) == "string" and text or ""
    -- 行の数に合わせて高さを変える(余白を残さない)
    local lines = 1
    for _ in gpBoard.Text:gmatch("\n") do lines += 1 end
    gpBoard.Size = UDim2.fromOffset(380, 18 + lines*20)
    gpBoard.Visible = world:GetAttribute("MatchMode") == "gp" and gpBoard.Text ~= "" and phase ~= "racing"
    watchFinal.Visible = player:GetAttribute("MinatoGp") == "eliminated"
end
world:GetAttributeChangedSignal("GpBoard"):Connect(updateTournament)
world:GetAttributeChangedSignal("RankedPhase"):Connect(updateTournament)
player:GetAttributeChangedSignal("MinatoGp"):Connect(updateTournament)
updateTournament()
roomRemote.OnClientEvent:Connect(function(kind, text)
    if kind == "ta" and type(text) == "string" then
        taResult.Text = text
        taResult.Visible = true
    elseif type(kind) == "string" then
        rankedPanel.Text = kind
    end
end)

-- レース中の表示(ブラウザ版と同じ配置。RaceHud.lua)
local RaceHud = require(ReplicatedStorage:WaitForChild("RaceHud"))
local hud = RaceHud.new(gui)
-- レースの結果の画面(RaceResult.lua)。中身が変わった時だけ作り直す
local RaceResult = require(ReplicatedStorage:WaitForChild("RaceResult"))
local resultView = RaceResult.new(gui)
hud:layout()
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() hud:layout() end)
-- 出走表(スタート前)と結果(ゴール後)の表。艇番の色・着・名前・AI の札・塗装とヘルメットの色見本
-- 名前・AI か・装備はサーバーが艇の属性と結果の行で配る(クライアントの申告は使わない)
local Meta = require(ReplicatedStorage:WaitForChild("Meta"))
local LANE = {{Color3.fromRGB(242,242,240),Color3.fromRGB(17,17,17)},{Color3.fromRGB(22,22,26),Color3.new(1,1,1)},
    {Color3.fromRGB(217,30,46),Color3.new(1,1,1)},{Color3.fromRGB(27,80,212),Color3.new(1,1,1)},
    {Color3.fromRGB(243,210,27),Color3.fromRGB(17,17,17)},{Color3.fromRGB(24,162,76),Color3.new(1,1,1)}}
local GOLD = Color3.fromRGB(255,210,60)
local function hex(n) return Color3.fromRGB(bit32.rshift(n,16),bit32.band(bit32.rshift(n,8),255),bit32.band(n,255)) end
local result = Instance.new("Frame")
result.Name = "Results"
result.Size = UDim2.fromOffset(260,34+6*30)
result.Position = UDim2.new(1,-268,0,58)
result.BackgroundColor3 = Color3.fromRGB(11,29,58)
result.BackgroundTransparency = 0.16
result.Visible = false
result.Parent = gui
do
    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,12); corner.Parent = result
    local edge = Instance.new("UIStroke"); edge.Color = Color3.new(1,1,1); edge.Transparency = 0.7; edge.Parent = result
end
local function cell(parent, class, x, w, text, size)
    local t = Instance.new(class)
    t.BackgroundTransparency = 1; t.BorderSizePixel = 0
    t.Position = UDim2.fromOffset(x,0); t.Size = UDim2.new(0,w,1,0)
    if class == "TextLabel" then
        t.Text = text or ""; t.TextColor3 = Color3.new(1,1,1); t.Font = Enum.Font.GothamBold
        t.TextSize = size or 14; t.TextXAlignment = Enum.TextXAlignment.Left; t.TextTruncate = Enum.TextTruncate.AtEnd
    end
    t.Parent = parent
    return t
end
local resultTitle = cell(result,"TextLabel",12,236,"出走表",15)
resultTitle.Size = UDim2.fromOffset(236,32); resultTitle.TextColor3 = GOLD
local resultLines = {}
for i = 1, 6 do
    local line = Instance.new("Frame")
    line.Name = "Row"..i; line.BackgroundColor3 = GOLD; line.BackgroundTransparency = 1; line.BorderSizePixel = 0
    line.Position = UDim2.fromOffset(6,32+(i-1)*30); line.Size = UDim2.fromOffset(248,28); line.Parent = result
    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,6); corner.Parent = line
    local place = cell(line,"TextLabel",4,34,"",14)
    local lane = cell(line,"TextLabel",40,22,"",14)
    lane.BackgroundTransparency = 0; lane.TextXAlignment = Enum.TextXAlignment.Center; lane.Size = UDim2.fromOffset(22,22); lane.Position = UDim2.fromOffset(40,3)
    local name = cell(line,"TextLabel",68,118,"",14)
    local ai = cell(line,"TextLabel",188,22,"AI",11)
    ai.TextColor3 = Color3.fromRGB(169,189,219)
    local paint = cell(line,"Frame",212,18)
    paint.Size = UDim2.fromOffset(18,18); paint.Position = UDim2.fromOffset(212,5); paint.BackgroundTransparency = 0
    local paintCorner = Instance.new("UICorner"); paintCorner.CornerRadius = UDim.new(0,4); paintCorner.Parent = paint
    local trim = cell(paint,"Frame",9,9); trim.BackgroundTransparency = 0; trim.Size = UDim2.new(0,9,1,0)
    local helmet = cell(line,"Frame",232,14)
    helmet.Size = UDim2.fromOffset(14,14); helmet.Position = UDim2.fromOffset(233,7); helmet.BackgroundTransparency = 0
    local helmetCorner = Instance.new("UICorner"); helmetCorner.CornerRadius = UDim.new(1,0); helmetCorner.Parent = helmet
    resultLines[i] = {frame=line,place=place,lane=lane,name=name,ai=ai,paint=paint,trim=trim,helmet=helmet}
end
-- 1行を描く。number: 艇番、placeText: 着や失格、mine: 自分の行(金の帯)
local function drawLine(i, number, placeText, racer, isAI, skinId, helmetId, mine)
    local line = resultLines[i]
    local skin = Meta.item(skinId ~= "" and skinId or "s0") or Meta.item("s0")
    local helmet = Meta.item(helmetId ~= "" and helmetId or "h0") or Meta.item("h0")
    line.frame.BackgroundTransparency = mine and 0.72 or 1
    line.place.Text = placeText
    line.place.TextColor3 = (placeText == "F" or placeText == "沈" or placeText == "退出") and Color3.fromRGB(255,90,77)
        or (placeText == "1着" and GOLD or Color3.new(1,1,1))
    line.lane.Text = tostring(number)
    line.lane.BackgroundColor3, line.lane.TextColor3 = LANE[number][1], LANE[number][2]
    line.name.Text = racer
    line.ai.Visible = isAI
    line.paint.BackgroundColor3 = hex(skin.hull); line.trim.BackgroundColor3 = hex(skin.trim)
    line.helmet.BackgroundColor3 = hex(helmet.base)
end
-- スタート前の出走表(艇の属性から)と、ゴール後の結果(サーバーの結果の行から)を描き分ける
local function drawResults(rows, mySeat, time)
    -- 右上の大時計(幅約100)をよけて、その左に置く。狭い画面では大時計の下へ
    result.Position = gui.AbsoluteSize.X >= 760 and UDim2.new(1,-276,0,62) or UDim2.new(1,-268,0,86)
    local count = 0
    if rows then
        resultTitle.Text = "レース結果"
        for i = 1, 6 do
            local row = rows[i]
            if row then
                count += 1
                local place = tonumber(row[2])
                drawLine(count, row[1], place and (place.."着") or tostring(row[2]), row[3] or "", row[4] == true, row[5] or "", row[6] or "", row[1] == mySeat)
            end
        end
    else
        if time >= 0 then return false end
        local mode = world:GetAttribute("MatchMode")
        local title = mode == "ta" and "タイムアタック" or (mode == "gp" and world:GetAttribute("TournamentName")) or world:GetAttribute("EventName")
        resultTitle.Text = (title and (title.."　") or "").."出走表"
        for i = 1, 6 do
            local b = templates:FindFirstChild("Boat"..i)
            -- タイムアタックでいない艇は出さない
            if b and not b:GetAttribute("Absent") then
                count += 1
                drawLine(count, i, "", b:GetAttribute("Racer") or "", b:GetAttribute("IsAI") ~= false,
                    b:GetAttribute("Skin") or "", b:GetAttribute("HelmetStyle") or "", i == mySeat)
            end
        end
    end
    for i = 1, 6 do resultLines[i].frame.Visible = i <= count end
    result.Size = UDim2.fromOffset(260,34+count*30)
    return count > 0
end
local tiltButton = Instance.new("TextButton")
tiltButton.Name = "Tilt"
tiltButton.Size = UDim2.fromOffset(112,40)
tiltButton.Position = UDim2.new(1,-124,0,12)
tiltButton.BackgroundColor3 = Color3.fromRGB(11,29,58)
do local edge = Instance.new("UIStroke"); edge.Color = Color3.fromRGB(255,210,60); edge.Transparency = 0.2; edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; edge.Parent = tiltButton end
tiltButton.TextColor3 = Color3.new(1,1,1)
tiltButton.Font,tiltButton.TextSize = Enum.Font.GothamBold,16
tiltButton.Parent = gui
local tiltCorner = Instance.new("UICorner")
tiltCorner.CornerRadius = UDim.new(0,8)
tiltCorner.Parent = tiltButton
local tiltNames = {"-0.5°","0°","+1.5°","+3.0°"}
tiltButton.Activated:Connect(function()
    if running and predicted and (serverClock or 0)<0 then
        setupRemote:FireServer(((boat:GetAttribute("Tilt") or 2)%4)+1,predictionRace)
    end
end)
local helpText = "W / S でスロットル　A / D でハンドル"
local controls = {steer=0, throttle=0}
local activeTouches = {}
local function lever(name, caption, position, horizontal)
    local item = Instance.new("TextButton")
    item.Name, item.Text = name, ""
    item.Size = horizontal and UDim2.fromOffset(150,74) or UDim2.fromOffset(74,150)
    item.Position = position
    item.BackgroundColor3 = Color3.fromRGB(8,24,48)
    item.BackgroundTransparency = 0.35
    item.AutoButtonColor = false
    item.Parent = gui
    local function height()
        local shift=math.clamp((player:GetAttribute("MinatoLever") or 40)-40,-40,math.max(0,gui.AbsoluteSize.Y-285))
        item.Position=position-UDim2.fromOffset(0,shift)
    end
    player:GetAttributeChangedSignal("MinatoLever"):Connect(height)
    gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(height)
    height()
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0,18)
    corner.Parent = item
    local edge = Instance.new("UIStroke")
    edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    edge.Color, edge.Transparency = Color3.new(1,1,1), 0.55
    edge.Parent = item
    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(44,44)
    knob.AnchorPoint = Vector2.new(0.5,0.5)
    knob.BackgroundColor3 = Color3.fromRGB(235,240,238)
    knob.Parent = item
    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1,0)
    knobCorner.Parent = knob
    local title = label(name.."Label",caption,UDim2.new(1,0,0,22),UDim2.new(0,0,0,-26),13)
    title.BackgroundTransparency = 1
    title.TextStrokeTransparency = 0.5
    title.Parent = item
    local function updateKnob()
        if horizontal then knob.Position=UDim2.new(0.15+(1-controls.steer)*0.35,0,0.5,0)
        else knob.Position=UDim2.new(0.5,0,0.15+(1-controls.throttle)*0.7,0) end
    end
    local function updateInput(position)
        if horizontal then
            controls.steer = math.clamp(1-2*(position.X-item.AbsolutePosition.X)/item.AbsoluteSize.X,-1,1)
        else
            controls.throttle = math.clamp(1-(position.Y-item.AbsolutePosition.Y)/item.AbsoluteSize.Y,0,1)
        end
        updateKnob()
    end
    item.InputBegan:Connect(function(obj)
        if obj.UserInputType == Enum.UserInputType.Touch or obj.UserInputType == Enum.UserInputType.MouseButton1 then
            activeTouches[obj] = {update=updateInput, release=function()
                if horizontal then controls.steer=0; updateKnob() end
            end}
            updateInput(obj.Position)
        end
    end)
    updateKnob()
    return updateKnob
end
local updateSteering = lever("Steering","ハンドル",UDim2.new(0,18,1,-110),true)
local updateThrottle = lever("Throttle","スロットル",UDim2.new(1,-92,1,-178),false)
player:GetAttributeChangedSignal("MinatoBoat"):Connect(function()
    controls.throttle, controls.steer = 0, 0
    updateThrottle()
    updateSteering()
end)
UserInputService.InputChanged:Connect(function(obj)
    local active = activeTouches[obj]
    if active then active.update(obj.Position) end
    if obj.UserInputType == Enum.UserInputType.MouseMovement then
        for input, handler in pairs(activeTouches) do
            if input.UserInputType == Enum.UserInputType.MouseButton1 then handler.update(obj.Position) end
        end
    end
end)
UserInputService.InputEnded:Connect(function(obj)
    local active = activeTouches[obj]
    if active then active.release(); activeTouches[obj]=nil end
end)
UserInputService.WindowFocusReleased:Connect(function()
    for input, handler in pairs(activeTouches) do handler.release(); activeTouches[input]=nil end
end)
if UserInputService.TouchEnabled then helpText = "左のレバーでハンドル　右でスロットル" end
-- スタートの予想(今から全開で走ったら、何秒でスタートラインに着くか)。0.1秒ごとに計算する
local predictedST, stTimer = nil, 0
local function predictStart(state, clock)
    if not state or state.x >= 0 then return nil end
    local b = {x=state.x,z=state.z,h=state.h,vx=state.vx,vz=state.vz,w=state.w,throttle=state.throttle,steer=state.steer,
        accF=state.accF,topF=state.topF,gripSet=state.gripSet,gripF=state.gripF,thrustF=state.thrustF,windX=state.windX,windZ=state.windZ,motor=state.motor}
    local t, step = 0, 1/30
    while t < 20 do
        stepBoat(b, 1, 0, step)
        t += step
        if b.x >= 0 then return clock + t end
    end
    return nil
end
-- 風の言葉(ブラウザ版の windLabel と同じ: ホームストレッチを基準に)
local function windText()
    local wind, dir, wave = world:GetAttribute("Wind") or 0, world:GetAttribute("WindDir") or 0, world:GetAttribute("Wave") or 0
    local wavePart = string.format("　波 %dcm", math.floor(wave+0.5))
    if wind < 0.5 then return "無風"..wavePart end
    local wx, wz = math.cos(dir), math.sin(dir)
    local name = math.abs(wx) > math.abs(wz) and (wx > 0 and "追い風" or "向かい風") or (wz > 0 and "横風(スタンドへ)" or "横風(対岸へ)")
    return string.format("%s %dm", name, math.floor(wind+0.5))..wavePart
end
-- 大きな知らせのための、前のフレームの状態
local lastStart, lastLap, lastFinished, lastOut, lastRace = nil, nil, false, "", nil
-- 音: 水切り(自分の艇)、観客、スタートの合図(残り3秒から毎秒と0秒)、衝突
local waterLoop, crowdLoop = Sfx.loop("water"), Sfx.loop("crowd")
local lastBeep, fanfareRace, lastVelocity, lastHit = nil, nil, nil, 0
local function held(key) return UserInputService:IsKeyDown(key) end
local nextSend = 0
RunService.RenderStepped:Connect(function(dt)
    if roundChanged then
        viewing.reset()
        controls.throttle,controls.steer=0,0
        table.clear(activeTouches)
        updateSteering(); updateThrottle()
        roundChanged=false
    end
    local boatNumber = seatNumber or 0
    local mine = latest[boatNumber]
    local reason = mine and mine[17] or ""
    local driving = running and mine and reason=="" and not mine[19]
    local watching = running and (boatNumber==0 or (reason~="" and serverClock-mine[18]>=3))
    viewing.update(watching,latest)
    gui.Steering.Visible=driving==true
    gui.Throttle.Visible=driving==true
    boat = templates:FindFirstChild("Boat"..math.max(boatNumber,1)) or boat
    local left = held(Enum.KeyCode.A) or held(Enum.KeyCode.Left)
    local right = held(Enum.KeyCode.D) or held(Enum.KeyCode.Right)
    local up = held(Enum.KeyCode.W) or held(Enum.KeyCode.Up)
    local down = held(Enum.KeyCode.S) or held(Enum.KeyCode.Down)
    if driving and (up or down) then
        controls.throttle = math.clamp(controls.throttle + ((up and 1 or 0)-(down and 1 or 0))*dt,0,1)
        updateThrottle()
    end
    local throttle = controls.throttle
    local steer = left and 1 or (right and -1 or controls.steer)
    nextSend += dt
    if nextSend >= 0.05 and driving and predictionRace then
        nextSend = 0
        inputSequence += 1
        currentSequence = inputSequence
        -- サーバーと同じく1000分の1にそろえて送る(予測とサーバーの計算をそろえる)
        sentThrottle,sentSteer = math.floor(throttle*1000+0.5)/1000, math.floor(steer*1000+0.5)/1000
        remote:FireServer(sentThrottle,sentSteer,currentSequence,predictionRace)
    end
    if running and predicted and predictedNumber == boatNumber then
        local localThrottle,localSteer=sentThrottle,sentSteer
        if boat:GetAttribute("Finished") or boat:GetAttribute("Flying") then localThrottle=0; localSteer=0 end
        predictionAccumulator = math.min(predictionAccumulator + dt,0.1)
        while predictionAccumulator >= 1/120 do
            stepBoat(predicted, localThrottle, localSteer, 1/120)
            if currentSequence > 0 then
                pendingSteps[#pendingSteps+1] = {sequence=currentSequence,throttle=localThrottle,steer=localSteer}
                if #pendingSteps > 1200 then table.remove(pendingSteps,1) end
            end
            predictionAccumulator -= 1/120
        end
    end
    for i, visual in ipairs(renderBoats) do
        local state = latest[i]
        if state then
            local x,z,h,w,vx,vz,th = state[1],state[2],state[3],state[6],state[4],state[5],state[7]
            if i == boatNumber and predicted then
                x,z,h,w,vx,vz,th = predicted.x,predicted.z,predicted.h,predicted.w,predicted.vx,predicted.vz,predicted.throttle
            end
            local out=state[17]
            local sinkTime=out=="沈" and math.max(0,serverClock-state[18]) or 0
            local hidden=out~="" and (out~="沈" or sinkTime>=8)
            local parent = if hidden then nil else workspace
            if visual.Parent ~= parent then visual.Parent=parent end
            local speed = math.sqrt(vx*vx+vz*vz)
            local forwardSpeed = vx*math.cos(h)+vz*math.sin(h)
            local lateralSpeed = -vx*math.sin(h)+vz*math.cos(h)
            local turnIntensity = math.clamp(math.abs(w)*speed/12,0,1)
            local sprayIntensity = math.clamp(math.abs(lateralSpeed)/5+math.abs(w)*speed/28,0,1)
            local view = motion[i]
            local turnSign = w < 0 and -1 or 1
            view.yaw += (turnSign*turnIntensity*0.2-view.yaw)*(1-math.exp(-5*dt))
            view.roll += (math.clamp(-w*forwardSpeed*0.034,-0.56,0.56)-view.roll)*(1-math.exp(-7*dt))
            local plane = math.clamp((speed-2)/8,0,1)
            local pitch = 0.01+0.07*plane-0.028*math.clamp(speed/22.6,0,1)+0.05*turnIntensity
            view.pitch += (pitch-view.pitch)*(1-math.exp(-5*dt))
            if wakes[i].engine then
                -- 回転数は速さとスロットルで上がる。自分の艇は少し大きく
                local ratio = math.clamp(speed/22.6,0,1)
                local own = i == boatNumber and 1 or 0.7
                wakes[i].engine.Volume = out=="" and (0.14 + 0.3*ratio + 0.16*th)*own*Sfx.master() or 0
                wakes[i].engine.PlaybackSpeed = 0.62 + 0.62*ratio + 0.2*th
            end
            local sink=math.clamp(sinkTime/1.2,0,1)
            local pos = Vector3.new(x,0.5-0.3*sink-math.max(0,sinkTime-2.5)*0.26,z)*STUDS_PER_METRE
            local destination = CFrame.lookAt(pos,pos+Vector3.new(math.cos(h),0,math.sin(h)))
                * CFrame.Angles(0,-view.yaw,0) * CFrame.Angles(view.pitch+0.4*sink,0,view.roll+1.2*sink)
            local current = visual:GetPivot()
            if (current.Position-destination.Position).Magnitude > 30*STUDS_PER_METRE then visual:PivotTo(destination)
            else visual:PivotTo(current:Lerp(destination,1-math.exp(-12*dt))) end
            local side = math.abs(lateralSpeed) > .1 and math.sign(lateralSpeed) or -turnSign
            local followingLane = watching and not viewing.exited and viewing.lane or boatNumber
            Wake.update(wakes[i], predictionRace, out, sinkTime, speed, th, sprayIntensity, side,
                (camera.CFrame.Position-pos).Magnitude, i == followingLane,
                (current.Position-destination.Position).Magnitude > 30*STUDS_PER_METRE, quality.scale)
            visuals.pose(visual,state[8],view.roll)
        end
    end
    -- ゴースト(タイムアタックの世界1位の走り)
    if ghostState and not ghostState[5] then
        if ghostVisual.Parent ~= workspace then ghostVisual.Parent = workspace end
        local pos = Vector3.new(ghostState[1],0.5,ghostState[2])*STUDS_PER_METRE
        local destination = CFrame.lookAt(pos,pos+Vector3.new(math.cos(ghostState[3]),0,math.sin(ghostState[3])))
        local current = ghostVisual:GetPivot()
        if (current.Position-destination.Position).Magnitude > 30*STUDS_PER_METRE then ghostVisual:PivotTo(destination)
        else ghostVisual:PivotTo(current:Lerp(destination,1-math.exp(-12*dt))) end
    elseif ghostVisual.Parent then
        ghostVisual.Parent = nil
    end
    local following=watching and not viewing.exited
    local visibleBoat = renderBoats[following and viewing.lane or math.max(boatNumber,1)]
    local cf = visibleBoat:GetPivot()
    camera.CameraType = Enum.CameraType.Scriptable
    local forward = Vector3.new(cf.LookVector.X,0,cf.LookVector.Z).Unit
    local desired = cf.Position - forward*(15*STUDS_PER_METRE) + Vector3.new(0,7*STUDS_PER_METRE,0)
    local target = CFrame.lookAt(desired,cf.Position+forward*(15*STUDS_PER_METRE)+Vector3.new(0,STUDS_PER_METRE,0))
    if following then
        local pose,focus=viewing.camera(cf)
        camera.CFrame,camera.Focus=pose,focus
    elseif not (watching and viewing.exited) then
        camera.CFrame=camera.CFrame:Lerp(target,1-math.exp(-5*dt))
        camera.Focus=CFrame.new(cf.Position)
        -- 速いほど視野を少し広げて、スピード感を出す(70° → 最大 82°)
        local own = predicted and math.sqrt(predicted.vx*predicted.vx+predicted.vz*predicted.vz) or 0
        local fov = 70 + 12*math.clamp(own/22.6,0,1)^1.5
        camera.FieldOfView += (fov-camera.FieldOfView)*math.min(1,dt*2.5)
    end
    local time = world:GetAttribute("Time") or -8
    -- サーバーの時計を手元で進めた時刻(大時計と予想STを滑らかにする)
    local clock = (serverClock or time) + math.min(os.clock() - snapshotAt, 0.25)
    updateVenue(clock, os.clock(), world:GetAttribute("Wind") or 0)
    -- 表示する艇: 自分の艇、観戦中は見ている艇
    local shownLane = (watching and not viewing.exited and viewing.lane) or (boatNumber > 0 and boatNumber) or nil
    local shown = shownLane and templates:FindFirstChild("Boat"..shownLane) or nil
    local startTime = shown and shown:GetAttribute("StartTime")
    local lap = shown and shown:GetAttribute("Lap") or 1
    local finished = shown and shown:GetAttribute("Finished") or false
    local shownOut = shownLane and latest[shownLane] and latest[shownLane][17] or ""
    tiltButton.Visible = driving==true and time < 0
    tiltButton.Text = "チルト "..tiltNames[boat:GetAttribute("Tilt") or 2]
    -- ゴール後は大きな結果の画面、スタート前は右上の出走表
    result.Visible = (not resultRows) and drawResults(nil, boatNumber, time) or false
    local mode = world:GetAttribute("MatchMode")
    local phase = world:GetAttribute("RankedPhase")
    local eliminated = player:GetAttribute("MinatoGp") == "eliminated"
    if resultRows then
        local extra = ""
        if mode == "ta" and taResult.Text ~= "" then extra = taResult.Text end
        if mode == "gp" then extra = world:GetAttribute("GpBoard") or "" end
        if mode == "gp" and phase == "between" then extra = extra.."\n次の走りの準備中です" end
        if not mode then extra = "次のレースがまもなく始まります" end
        local key = table.concat({tostring(predictionRace), #resultRows, extra, tostring(phase), tostring(eliminated), tostring(boatNumber)}, "|")
        if resultView.key ~= key then
            local buttons = {}
            local function fire(action) return function() roomRemote:FireServer(action) end end
            if (mode == "ta" or mode == "single") and phase == "finished" then
                buttons = {{"Again","もう一度走る",true,fire("again")},{"Lobby","ロビーへ",false,fire("return")}}
            elseif mode == "gp" and eliminated then
                buttons = {{"WatchFinal","優勝戦を観戦する",true,fire("watchFinal")},{"Lobby","ロビーへ",false,fire("return")}}
            elseif mode and phase == "finished" then
                buttons = {{"Lobby","ロビーへ戻る",true,fire("return")}}
            end
            resultView:show(resultRows, boatNumber, extra, buttons, key)
        end
    elseif resultView.key then
        resultView:hide()
    end
    local overlay = resultRows ~= nil
    rankedPanel.Visible = rankedPanel.Visible and not overlay
    again.Visible = again.Visible and not overlay
    watchFinal.Visible = watchFinal.Visible and not overlay
    taResult.Visible = taResult.Visible and not overlay
    gpBoard.Visible = gpBoard.Visible and not overlay
    -- 周回の行(スタート前・周回・ゴール・観戦などの状態)
    local lapText
    if resultRows then lapText = "レース終了"
    elseif watching then lapText = viewing.exited and "待合　次のレースから参加" or (viewing.lane.."号艇を観戦中")
    elseif boatNumber == 0 then lapText = time < -14 and string.format("参加受付中　あと %d 秒",math.ceil(-14-time)) or "観戦中・次のレースから参加"
    elseif time < -14 then lapText = string.format("参加受付中　あと %d 秒",math.ceil(-14-time))
    elseif shownOut ~= "" then lapText = shownOut=="F" and "フライング失格" or (shownOut=="沈" and "沈没失格" or "途中退出")
    elseif finished then lapText = "ゴール"
    elseif not startTime then lapText = "スタート前"
    else lapText = string.format("%d / 3 周", lap) end
    -- 予想ST(自分が走っていて、まだスタートしていない時だけ)
    local pre = driving == true and not startTime and time >= -14
    stTimer -= dt
    if pre and stTimer <= 0 then
        stTimer = 0.1
        local st = predicted and predictStart(predicted, clock)
        predictedST = st
    elseif not pre then predictedST = nil end
    -- 順位表(結果や出走表を出している時は隠す)
    local order = nil
    if not result.Visible then
        local list = {}
        for i = 1, 6 do
            local t = templates:FindFirstChild("Boat"..i)
            if t and not t:GetAttribute("Absent") then
                local out = latest[i] and latest[i][17] or ""
                table.insert(list, {lane=i, rank=t:GetAttribute("Rank") or i, name=t:GetAttribute("Racer") or "", out=out~="" and out or nil, me=i==shownLane})
            end
        end
        table.sort(list, function(a,b) return a.rank < b.rank end)
        for k, o in ipairs(list) do o.mark = o.out and (o.out=="F" and "F" or (o.out=="沈" and "沈" or "退")) or tostring(k) end
        order = list
    end
    -- ミニマップの点
    local dots = {}
    for i = 1, 6 do
        local st = latest[i]
        local t = templates:FindFirstChild("Boat"..i)
        if st then
            local x, z, h = st[1], st[2], st[3]
            if i == boatNumber and predicted then x, z, h = predicted.x, predicted.z, predicted.h end
            local sinkTime = st[17]=="沈" and math.max(0,(serverClock or 0)-(st[18] or 0)) or 0
            dots[i] = {x=x, z=z, h=h, me=i==shownLane, hidden=(t and t:GetAttribute("Absent")) or (st[17]~="" and (st[17]~="沈" or sinkTime>=8))}
        end
    end
    -- 風の矢印を画面の向きに合わせる
    local dir = world:GetAttribute("WindDir") or 0
    local wv = Vector3.new(math.cos(dir), 0, math.sin(dir))
    local right, look = camera.CFrame.RightVector, camera.CFrame.LookVector
    local fwd = Vector3.new(look.X, 0, look.Z)
    local sx, sy = wv:Dot(Vector3.new(right.X,0,right.Z).Unit), fwd.Magnitude > 0 and wv:Dot(fwd.Unit) or 0
    -- 大きな知らせ(ST・周回・ゴール・フライング・沈没)。自分の艇だけ
    local raceKey = predictionRace
    if raceKey ~= lastRace then lastRace, lastStart, lastLap, lastFinished, lastOut = raceKey, nil, nil, false, "" end
    if boatNumber > 0 and not watching then
        local myStart = boat:GetAttribute("StartTime")
        if myStart and not lastStart then
            if myStart < 0 then Sfx.play("buzzer", 0.8) elseif myStart <= 0.15 then Sfx.play("select", 0.8) end
            hud:flash(string.format("ST %.2f", myStart), myStart < 0 and "フライング" or (myStart <= 0.15 and "好スタート！" or ""),
                myStart < 0 and Color3.fromRGB(255,90,77) or (myStart <= 0.15 and Color3.fromRGB(255,210,60) or Color3.new(1,1,1)))
        end
        lastStart = myStart
        local myLap = boat:GetAttribute("Lap")
        if myLap and lastLap and myLap > lastLap and not boat:GetAttribute("Finished") then
            Sfx.play("lap", 0.8, myLap == 3 and 1.12 or 1)
            hud:flash(myLap == 3 and "最終周" or (myLap.."周目"), "", Color3.new(1,1,1), 1.6)
        end
        lastLap = myLap
        local myFinished = boat:GetAttribute("Finished") == true
        if myFinished and not lastFinished then
            local place = boat:GetAttribute("Place") or 0
            Sfx.play(place == 1 and "finishWin" or "finish", 0.9)
            if place <= 3 then Sfx.play("cheer", place == 1 and 0.9 or 0.5) end
            hud:flash("ゴール", place.."着", place == 1 and Color3.fromRGB(255,210,60) or Color3.new(1,1,1), 3)
        end
        lastFinished = myFinished
        if reason ~= "" and lastOut == "" then
            if reason == "沈" then Sfx.play("splash", 1) end
            hud:flash(reason=="F" and "フライング" or (reason=="沈" and "沈没" or "退出"), "失格", Color3.fromRGB(255,90,77), 3)
        end
        lastOut = reason
    end
    -- スタートの合図: 残り3秒から毎秒、0秒で高い音。出走が決まった時(-14秒)にファンファーレ
    if running and time >= -14 then
        if fanfareRace ~= raceKey and clock < -9 then
            fanfareRace = raceKey
            Sfx.play("fanfare", 0.7)
        end
        local second = math.floor(clock)
        if second ~= lastBeep then
            if lastBeep and second >= -3 and second <= -1 then Sfx.play("beep", 0.8)
            elseif lastBeep and second == 0 then Sfx.play("go", 0.9) end
            lastBeep = second
        end
    else
        lastBeep = nil
    end
    -- 水切りの音(自分か、観戦中の艇の速さと横すべり)と、観客のざわめき
    local shownState = shownLane and latest[shownLane]
    if waterLoop then
        local v = 0
        if shownState and shownState[17] == "" then
            local vx, vz = shownState[4], shownState[5]
            if shownLane == boatNumber and predicted then vx, vz = predicted.vx, predicted.vz end
            v = math.clamp(math.sqrt(vx*vx+vz*vz)/22.6, 0, 1)
        end
        waterLoop.Volume += ((0.05 + 0.34*v)*(v > 0.02 and 1 or 0)*Sfx.master() - waterLoop.Volume)*math.min(1, dt*6)
        waterLoop.PlaybackSpeed = 0.8 + 0.5*v
    end
    if crowdLoop then
        crowdLoop.Volume += ((running and 0.16 or 0.08)*Sfx.master() - crowdLoop.Volume)*math.min(1, dt*2)
    end
    -- 衝突: 自分の艇の速さが一瞬で大きく変わった時(サーバーの値で見る)
    local mineState = boatNumber > 0 and latest[boatNumber]
    if mineState and mineState[17] == "" then
        local now = Vector3.new(mineState[4], 0, mineState[5])
        if lastVelocity and lastVelocity.state ~= mineState then
            local jump = (now - lastVelocity.v).Magnitude
            if jump > 2.4 and os.clock() - lastHit > 0.35 and time > -14 then
                lastHit = os.clock()
                Sfx.play("hit", math.clamp(0.35 + jump/10, 0.35, 1), 0.9 + math.random()*0.25)
            end
        end
        if not lastVelocity or lastVelocity.state ~= mineState then lastVelocity = {v = now, state = mineState} end
    else
        lastVelocity = nil
    end
    hud:update({
        visible = not (watching and viewing.exited),
        rank = shown and not resultRows and shownOut == "" and (finished and shown:GetAttribute("Place") or shown:GetAttribute("Rank")) or nil,
        out = shown and shownOut ~= "" and (shownOut=="F" and "F" or (shownOut=="沈" and "沈" or "退")) or nil,
        lapText = lapText,
        time = startTime and math.max(0, clock) or (time >= 0 and clock or 0),
        pre = pre,
        clock = clock,
        dist = predicted and -predicted.x or nil,
        st = predictedST,
        hint = helpText,
        order = order,
        boats = dots,
        myLane = shownLane,
        speed = shown and shown:GetAttribute("Speed") or nil,
        wind = windText(),
        windRotation = -math.deg(math.atan2(sy, sx)),
    })
end)
