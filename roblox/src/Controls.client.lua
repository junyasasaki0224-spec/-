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
local audioConfig = require(ReplicatedStorage:WaitForChild("AudioConfig"))
local world = workspace:WaitForChild("Minato")
local templates = ReplicatedStorage:WaitForChild("MinatoTemplates")
local boat = templates:WaitForChild("Boat1")
local visuals=require(ReplicatedStorage:WaitForChild("VisualModels"))
local outfit=require(ReplicatedStorage:WaitForChild("Outfit"))
local STUDS_PER_METRE = 3.5
local BOAT_SCALE = STUDS_PER_METRE * (2.9 / 7)
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
    local first = Instance.new("Attachment")
    first.Position = Vector3.new(-1,0,3)*BOAT_SCALE
    first.Parent = visual.PrimaryPart
    local second = Instance.new("Attachment")
    second.Position = Vector3.new(1,0,3)*BOAT_SCALE
    second.Parent = visual.PrimaryPart
    local trail = Instance.new("Trail")
    trail.Attachment0,trail.Attachment1 = first,second
    trail.Color = ColorSequence.new(Color3.fromRGB(220,244,245))
    trail.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,0.45),NumberSequenceKeypoint.new(1,1)})
    trail.Lifetime = 1.2
    trail.FaceCamera = true
    trail.Enabled = false
    trail.Parent = visual.PrimaryPart
    local spray = Instance.new("ParticleEmitter")
    spray.Texture = "rbxasset://textures/particles/smoke_main.dds"
    spray.Color = ColorSequence.new(Color3.fromRGB(226,244,246))
    spray.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,0.4),NumberSequenceKeypoint.new(1,1)})
    spray.Size = NumberSequence.new({NumberSequenceKeypoint.new(0,0.7*STUDS_PER_METRE),NumberSequenceKeypoint.new(1,2.5*STUDS_PER_METRE)})
    spray.Lifetime = NumberRange.new(0.35,0.7)
    spray.Speed = NumberRange.new(STUDS_PER_METRE,3*STUDS_PER_METRE)
    spray.Rate = 0
    spray.Parent = first
    local fanAnchor = Instance.new("Attachment")
    fanAnchor.Position = Vector3.new(0,0.15,3.3)*BOAT_SCALE
    fanAnchor.Parent = visual.PrimaryPart
    local fan = Instance.new("ParticleEmitter")
    fan.Texture = "rbxasset://textures/particles/smoke_main.dds"
    fan.Color = ColorSequence.new(Color3.fromRGB(233,248,250))
    fan.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,0.45),NumberSequenceKeypoint.new(1,1)})
    fan.Size = NumberSequence.new({NumberSequenceKeypoint.new(0,0.3*STUDS_PER_METRE),NumberSequenceKeypoint.new(1,1.5*STUDS_PER_METRE)})
    fan.Lifetime = NumberRange.new(0.7,1.2)
    fan.Speed = NumberRange.new(5*STUDS_PER_METRE,12*STUDS_PER_METRE)
    fan.Acceleration = Vector3.new(0,-9.8*STUDS_PER_METRE,0)
    fan.EmissionDirection = Enum.NormalId.Front
    fan.SpreadAngle = Vector2.new(18,35)
    fan.Rate = 0
    fan.Parent = fanAnchor
    local engine
    if audioConfig.engineAssetId ~= "" then
        engine = Instance.new("Sound")
        engine.SoundId = audioConfig.engineAssetId
        engine.Looped = true
        engine.Volume = 0
        engine.RollOffMaxDistance = 80*STUDS_PER_METRE
        engine.Parent = visual.PrimaryPart
        engine:Play()
    end
    wakes[i] = {trail=trail,spray=spray,fan=fan,fanAnchor=fanAnchor,engine=engine}
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
    rankedPanel.Visible = phase == "waiting" or phase == "finished" or phase == "incomplete"
    local names = {ranked="シーズン", online="オンライン", event="イベント", ta="タイムアタック"}
    rankedPanel.Text = phase == "finished" and "終了：ロビーに戻る" or phase == "incomplete" and "参加者が来ませんでした：ロビーに戻る"
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
roomRemote.OnClientEvent:Connect(function(kind, text)
    if kind == "ta" and type(text) == "string" then
        taResult.Text = text
        taResult.Visible = true
    elseif type(kind) == "string" then
        rankedPanel.Text = kind
    end
end)

local status = label("Status","みなとグランプリ",UDim2.fromOffset(180,75),UDim2.fromOffset(12,12),16)
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
    result.Position = gui.AbsoluteSize.X >= 700 and UDim2.new(1,-372,0,58) or UDim2.new(1,-268,0,160)
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
        local title = world:GetAttribute("MatchMode") == "ta" and "タイムアタック" or world:GetAttribute("EventName")
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
tiltButton.BackgroundColor3 = Color3.fromRGB(15,32,43)
tiltButton.TextColor3 = Color3.new(1,1,1)
tiltButton.Font,tiltButton.TextSize = Enum.Font.GothamBold,16
tiltButton.Parent = gui
local tiltCorner = Instance.new("UICorner")
tiltCorner.CornerRadius = UDim.new(0,8)
tiltCorner.Parent = tiltButton
local tiltNames = {"-0.5°","0°","+1.5°","+3.0°"}
local clockFace = Instance.new("Frame")
clockFace.Size = UDim2.fromOffset(64,64)
clockFace.Position = UDim2.new(1,-88,0,60)
clockFace.BackgroundColor3 = Color3.fromRGB(237,239,230)
clockFace.Parent = gui
local faceCorner = Instance.new("UICorner")
faceCorner.CornerRadius = UDim.new(1,0)
faceCorner.Parent = clockFace
local hand = Instance.new("Frame")
hand.Size = UDim2.fromOffset(3,27)
hand.Position = UDim2.new(0.5,0,0.5,0)
hand.AnchorPoint = Vector2.new(0.5,1)
hand.BackgroundColor3 = Color3.fromRGB(209,54,45)
hand.Parent = clockFace
local clockText = label("Clock","",UDim2.fromOffset(82,24),UDim2.new(1,-97,0,128),14)
tiltButton.Activated:Connect(function()
    if running and predicted and (serverClock or 0)<0 then
        setupRemote:FireServer(((boat:GetAttribute("Tilt") or 2)%4)+1,predictionRace)
    end
end)
local help = label("Help","W / S でスロットル　A / D で旋回",UDim2.fromOffset(310,34),UDim2.new(0.5,-155,1,-45),14)
local controls = {steer=0, throttle=0}
local activeTouches = {}
local function lever(name, caption, position, horizontal)
    local item = Instance.new("TextButton")
    item.Name, item.Text = name, ""
    item.Size = horizontal and UDim2.fromOffset(150,74) or UDim2.fromOffset(74,150)
    item.Position = position
    item.BackgroundColor3 = Color3.fromRGB(20,52,67)
    item.BackgroundTransparency = 0.25
    item.AutoButtonColor = false
    item.Parent = gui
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0,18)
    corner.Parent = item
    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(44,44)
    knob.AnchorPoint = Vector2.new(0.5,0.5)
    knob.BackgroundColor3 = Color3.fromRGB(235,240,238)
    knob.Parent = item
    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1,0)
    knobCorner.Parent = knob
    local title = label(name.."Label",caption,UDim2.new(1,0,0,24),UDim2.new(0,0,0,-28),14)
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
if UserInputService.TouchEnabled then help.Text = "左で旋回　右でスロットル" end
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
    help.Visible=driving==true
    clockText.Visible=driving==true
    clockFace.Visible=driving==true
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
            wakes[i].trail.Enabled = speed > 3
            wakes[i].spray.Rate = math.clamp((speed-5)*3,0,45)
            local side = math.abs(lateralSpeed)>0.1 and (lateralSpeed>0 and 1 or -1) or -turnSign
            local fanDirection = Vector3.new(side*0.85,0.6,0.55)
            wakes[i].fanAnchor.CFrame = CFrame.lookAt(wakes[i].fanAnchor.Position,wakes[i].fanAnchor.Position+fanDirection)
            local visibility = i == boatNumber and 0.3 or 1
            wakes[i].fan.Rate = math.min(140,420*sprayIntensity*(0.3+0.7*th)*(0.4+0.6*math.clamp(speed/22.6,0,1)))*visibility
            if wakes[i].engine then
                wakes[i].engine.Volume = out=="" and (0.12 + 0.38*math.clamp(speed/22.6,0,1)) or 0
                wakes[i].engine.PlaybackSpeed = 0.75 + 0.9*math.clamp(speed/22.6,0,1)
            end
            local sink=math.clamp(sinkTime/1.2,0,1)
            local pos = Vector3.new(x,0.5-0.3*sink-math.max(0,sinkTime-2.5)*0.26,z)*STUDS_PER_METRE
            local destination = CFrame.lookAt(pos,pos+Vector3.new(math.cos(h),0,math.sin(h)))
                * CFrame.Angles(0,-view.yaw,0) * CFrame.Angles(view.pitch+0.4*sink,0,view.roll+1.2*sink)
            local current = visual:GetPivot()
            if (current.Position-destination.Position).Magnitude > 30*STUDS_PER_METRE then visual:PivotTo(destination)
            else visual:PivotTo(current:Lerp(destination,1-math.exp(-12*dt))) end
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
    end
    local time = world:GetAttribute("Time") or -8
    hand.Rotation = (time*30)%360
    local startTime = boat:GetAttribute("StartTime")
    clockText.Text = startTime and string.format("ST %.2f",startTime) or string.format("%.1f 秒",time)
    local speed = boat:GetAttribute("Speed") or 0
    local lap = boat:GetAttribute("Lap") or 1
    local rank = boat:GetAttribute("Rank") or 1
    tiltButton.Visible = driving==true and time < 0
    tiltButton.Text = "チルト "..tiltNames[boat:GetAttribute("Tilt") or 2]
    local message = time < -14 and string.format("参加受付中　あと %d 秒",math.ceil(-14-time)) or (time < 0 and string.format("スタートまで %.1f",-time) or string.format("%d / 3 周　　%d km/h",lap,speed))
    if boat:GetAttribute("Finished") then message=string.format("ゴール！　%d 着",boat:GetAttribute("Place") or 0) end
    if boat:GetAttribute("Flying") then message="フライング失格" end
    if boatNumber == 0 and time >= -14 then message="観戦中・次のレースから参加\n"..message end
    if boatNumber > 0 then message=boatNumber.."号艇　"..rank.."位\n"..message end
    if reason~="" then message=reason=="F" and "フライング失格" or (reason=="沈" and "沈没失格" or "途中退出") end
    if watching then message=viewing.exited and "待合　次のレースから参加" or (viewing.lane.."号艇を観戦中") end
    result.Visible=drawResults(resultRows, boatNumber, time)
    if resultRows then
        message="レース終了"
    end
    status.TextColor3=reason~="" and not watching and Color3.fromRGB(255,90,77) or Color3.new(1,1,1)
    status.Text = "みなとグランプリ\n"..message
end)
