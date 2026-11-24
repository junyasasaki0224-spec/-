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
local Visor=require(ReplicatedStorage:WaitForChild("Visor"))
local STUDS_PER_METRE = 3.5
local Wake = require(ReplicatedStorage:WaitForChild("BoatWake"))
local quality=require(ReplicatedStorage:WaitForChild("DisplayQuality"))
local Opening=require(ReplicatedStorage:WaitForChild("Opening"))
local function applyQuality() quality.apply(player:GetAttribute("MinatoQuality")) end
player:GetAttributeChangedSignal("MinatoQuality"):Connect(applyQuality)
applyQuality()
local camera = workspace.CurrentCamera
-- 検証用(Studio で、ロビーと会場をまとめた場所 dev.project.json): ホームを見ている間は、レースの画面とカメラを止める
local devCombined = RunService:IsStudio() and ReplicatedStorage:FindFirstChild("MinatoDevCombined") ~= nil
local function devAway() return devCombined and player:GetAttribute("MinatoDevRace") ~= true end
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
        outfit(visual,original:GetAttribute("Skin"),original:GetAttribute("HelmetStyle"),
            original:GetAttribute("CowlStyle"),original:GetAttribute("WheelStyle"),original:GetAttribute("FlagStyle"))
        Visor.apply(visual,original:GetAttribute("VisorUp")==true)
    end
    original:GetAttributeChangedSignal("Skin"):Connect(refreshOutfit)
    original:GetAttributeChangedSignal("HelmetStyle"):Connect(refreshOutfit)
    -- 着せ替えのモーターカバー・ステアリング・艇首旗
    for _,name in ipairs({"CowlStyle","WheelStyle","FlagStyle"}) do original:GetAttributeChangedSignal(name):Connect(refreshOutfit) end
    original:GetAttributeChangedSignal("VisorUp"):Connect(refreshOutfit)
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
-- 人間の艇には、その人のアバターをレーサーとして乗せる(サーバーが RacerAvatars に Lane1〜6 の名前で置く)
local RacerAvatar = require(ReplicatedStorage:WaitForChild("RacerAvatar"))
local avatarFolder = ReplicatedStorage:WaitForChild("RacerAvatars")
local function syncAvatar(lane)
    local visual = renderBoats[lane]
    if not visual then return end
    local template = avatarFolder:FindFirstChild("Lane"..lane)
    -- 乗せ替える前にシールドを下ろし、乗せた後でその艇の設定に戻す(頭の見せ方もそろえる)
    Visor.apply(visual, false)
    if template then RacerAvatar.attach(visual, template) else RacerAvatar.detach(visual) end
    local original = templates:FindFirstChild("Boat"..lane)
    Visor.apply(visual, original ~= nil and original:GetAttribute("VisorUp") == true)
end
local function laneOf(child) return tonumber(child.Name:match("^Lane(%d)$")) end
avatarFolder.ChildAdded:Connect(function(child)
    -- 中身が届き終わるのを少し待つ
    local lane = laneOf(child)
    if lane then task.delay(0.2, syncAvatar, lane) end
end)
avatarFolder.ChildRemoved:Connect(function(child)
    local lane = laneOf(child)
    if lane then syncAvatar(lane) end
end)
for lane = 1, 6 do syncAvatar(lane) end
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
-- ほかの艇(と予測していない時の自分の艇)は、位置が1秒に15回しか届かない。届いた状態から手元でも同じ物理で進め、
-- 次に届いた位置とのずれは表示の上で少しずつ消す(届くたびに速さが揺れて、かくついて見えるのを防ぐ)
local remoteSims = {}
local predOff = {x=0, z=0, h=0}
local function wrapAngle(a) return (a + math.pi) % (2*math.pi) - math.pi end
local function syncRemote(states, raceNumber)
    for i, state in states do
        local old = remoteSims[i]
        local sim = reconcile(state, {}, 0, stepBoat)
        local off = {x=0, z=0, h=0}
        if old and old.race == raceNumber and old.out == "" and state[17] == "" then
            off.x = old.sim.x + old.off.x - sim.x
            off.z = old.sim.z + old.off.z - sim.z
            off.h = wrapAngle(old.sim.h + old.off.h - sim.h)
            -- 大きく離れた時(衝突で弾かれた・場所の入れ替え)はそのまま新しい位置へ
            if off.x*off.x + off.z*off.z > 36 then off = {x=0, z=0, h=0} end
        end
        remoteSims[i] = {sim=sim, off=off, race=raceNumber, out=state[17], throttle=state[7], steer=state[8], acc=0}
    end
end
local function advanceRemote(dt, moving)
    local fade = math.exp(-dt*7)
    for _, r in remoteSims do
        if moving and r.out == "" then
            r.acc = math.min(r.acc + dt, 0.25)
            while r.acc >= 1/120 do
                stepBoat(r.sim, r.throttle, r.steer, 1/120)
                r.acc -= 1/120
            end
        end
        r.off.x *= fade; r.off.z *= fade; r.off.h *= fade
    end
    predOff.x *= fade; predOff.z *= fade; predOff.h *= fade
end
snapshotRemote.OnClientEvent:Connect(function(states, active, acknowledged, raceNumber, clock, seat, results, ghost)
    if predictionRace ~= raceNumber then roundChanged=true end
    syncRemote(states, raceNumber)
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
    local before = predicted
    predicted,pendingSteps = reconcile(state,pendingSteps,acknowledged,stepBoat)
    -- 予測の直し分も、表示の上で少しずつ消す
    if before then
        local dx, dz = before.x + predOff.x - predicted.x, before.z + predOff.z - predicted.z
        if dx*dx + dz*dz < 9 then
            predOff = {x=dx, z=dz, h=wrapAngle(before.h + predOff.h - predicted.h)}
        else
            predOff = {x=0, z=0, h=0}
        end
    end
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
    local names = {ranked="ランク戦", online="オンライン", event="イベント", ta="タイムアタック", gp="大会"}
    rankedPanel.Text = phase == "finished" and "終了：ロビーに戻る" or phase == "incomplete" and "参加者が来ませんでした：ロビーに戻る"
        or phase == "between" and "大会：次の走りの準備中"
        or (names[world:GetAttribute("MatchMode")] or "ランク戦").."：参加者の到着を待っています"
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
    -- 色見本: 色だけの品はその色、着せ替えの品は模様の主な色と差し色
    local hullColor, trimColor = Meta.swatch(skin)
    line.paint.BackgroundColor3 = hex(hullColor); line.trim.BackgroundColor3 = hex(trimColor)
    line.helmet.BackgroundColor3 = hex((Meta.swatch(helmet)))
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
-- 視点の切り替え(ブラウザ版の 🎥 と C キーと同じ): 追尾 → 接近 → オンボード → 中継 → 上空
local CAM_NAMES = {"追尾","接近","オンボード","中継","上空"}
local camMode = 1
local camButton = tiltButton:Clone()
camButton.Name = "Camera"
camButton.Size = UDim2.fromOffset(112,40)
camButton.Text = "視点 追尾"
camButton.Visible = false
camButton.Parent = gui
local camSwitched = false
local function cycleCam()
    camMode = camMode % #CAM_NAMES + 1
    camButton.Text = "視点 "..CAM_NAMES[camMode]
    camSwitched = true
end
camButton.Activated:Connect(cycleCam)
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.C and camButton.Visible then cycleCam() end
end)
-- 中継カメラの場所(メートル): スタンドの屋根 / 1マークの奥 / 対岸 / 2マークの奥。4つ目は望遠の強さ
local TV_SPOTS = {{20,27,80,13},{257,8,-14,8.5},{44,12,-85,12},{-265,7.5,50,8.5}}
-- 走行ガイド(ブラウザ版の gfx/guide.js): サーバーから届いた理想のラインを、艇の先26区間だけ水面に点線で描く。
-- ふだんは水色、ターンの円の区間は黄、「レバーを落とす」時は手前45mを赤。遠いほど薄く、進む向きへ光が流れる
local guidePlan = nil
local guideRemote = ReplicatedStorage:WaitForChild("MinatoGuide", 10)
if guideRemote then
    guideRemote.OnClientEvent:Connect(function(race, xs, zs, turnStart)
        if type(xs) ~= "table" or type(zs) ~= "table" or #xs ~= #zs or #xs < 2 or #xs > 400 then return end
        guidePlan = {race = race, xs = xs, zs = zs, turnStart = tonumber(turnStart) or 1, k = 1}
    end)
end
local GUIDE_N = 26
local guideFolder = Instance.new("Folder")
guideFolder.Name = "MinatoGuideLine"
guideFolder.Parent = workspace
local guideParts = {}
for i = 1, GUIDE_N do
    local p = Instance.new("Part")
    p.Name = "Guide"..i
    p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
    p.Material = Enum.Material.Neon
    p.Size = Vector3.new(1.1*STUDS_PER_METRE, 0.06, 1)
    p.Transparency = 1
    p.Parent = guideFolder
    guideParts[i] = p
end
local guideShown = false
local function hideGuide()
    if not guideShown then return end
    guideShown = false
    for _, p in guideParts do p.Transparency = 1 end
end
local function drawGuide(x, z, lift, now)
    local P = guidePlan
    local xs, zs, count = P.xs, P.zs, #P.xs
    -- いちばん近い点(前のコマの近くだけを探す)
    local best, k = math.huge, P.k
    for i = math.max(1, P.k - 3), math.min(count, P.k + 14) do
        local d = (xs[i]-x)^2 + (zs[i]-z)^2
        if d < best then best, k = d, i end
    end
    P.k = k
    guideShown = true
    local dist, px, pz = 0, x, z
    for i = 1, GUIDE_N do
        local part = guideParts[i]
        local a = k + i
        if a >= count then
            part.Transparency = 1
        else
            local ax, az, cx, cz = xs[a], zs[a], xs[a+1], zs[a+1]
            dist += math.sqrt((ax-px)^2 + (az-pz)^2)
            px, pz = ax, az
            local len = math.sqrt((cx-ax)^2 + (cz-az)^2)
            if len < 0.05 then
                part.Transparency = 1
            else
                -- 区間の6割の長さの板を、区間の真ん中に置く(すき間が点線に見える)
                local from = Vector3.new(ax, 0.1, az)*STUDS_PER_METRE
                local to = Vector3.new(cx, 0.1, cz)*STUDS_PER_METRE
                part.Size = Vector3.new(1.1*STUDS_PER_METRE, 0.06, len*STUDS_PER_METRE*0.6)
                part.CFrame = CFrame.lookAt((from+to)/2, to)
                local inArc = a >= P.turnStart and a <= P.turnStart + 14
                local red = lift and dist < 45
                part.Color = red and Color3.fromRGB(255,64,51) or (inArc and Color3.fromRGB(255,204,51) or Color3.fromRGB(77,230,255))
                local alpha = math.min(1, dist/6) * math.max(0, 1 - dist/95) * 0.8
                local wave = (dist/14 - now*1.2) % 1
                alpha *= 0.6 + 0.4*math.cos(wave*2*math.pi)
                part.Transparency = 1 - alpha*0.8
            end
        end
    end
end
-- メニュー(右上)。1人で走るフリーレースだけ。押すとレースが止まり、「再開する・やり直す・タイトルへ戻る」を選べる。
-- 大時計が回り始めてから押せる(スタート前でも、大時計ごと止まる)。P キーでも開く・閉じる
local pauseButton = tiltButton:Clone()
pauseButton.Name = "Pause"
pauseButton.Size = UDim2.fromOffset(112,40)
pauseButton.Text = "≡ メニュー"
pauseButton.Visible = false
pauseButton.Parent = gui
local pauseScreen = Instance.new("Frame")
pauseScreen.Name = "PauseScreen"
pauseScreen.Size = UDim2.fromScale(1,1)
pauseScreen.BackgroundColor3 = Color3.fromRGB(4,12,28)
pauseScreen.BackgroundTransparency = 0.35
pauseScreen.Visible = false
pauseScreen.ZIndex = 30
pauseScreen.Parent = gui
local pauseTitle = Instance.new("TextLabel")
pauseTitle.BackgroundTransparency = 1
pauseTitle.AnchorPoint = Vector2.new(0.5,0.5)
pauseTitle.Position = UDim2.new(0.5,0,0.5,-120)
pauseTitle.Size = UDim2.fromOffset(320,50)
pauseTitle.Font, pauseTitle.TextSize = Enum.Font.GothamBlack, 34
pauseTitle.TextColor3 = Color3.fromRGB(255,210,60)
pauseTitle.Text = "一時停止中"
pauseTitle.ZIndex = 31
pauseTitle.Parent = pauseScreen
-- レースを離れる時(ロビーへ・やり直し)は、エンジン・水・観客の音をすぐ止める(移動の間も鳴り続けないように)
local leavingAt = -100
local function leaveRace()
    leavingAt = os.clock()
    roomRemote:FireServer("return")
    return true
end
local function pauseChoice(name, text, y, action, primary)
    local b = tiltButton:Clone()
    b.Name = name
    b.Text = text
    b.AnchorPoint = Vector2.new(0.5,0.5)
    b.Position = UDim2.new(0.5,0,0.5,y)
    b.Size = UDim2.fromOffset(240,50)
    b.ZIndex = 31
    b.Visible = true
    if primary then
        b.BackgroundColor3 = Color3.new(1,1,1)
        b.TextColor3 = Color3.fromRGB(26,18,0)
        local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(Color3.fromRGB(255,224,102),Color3.fromRGB(245,164,0)); g.Rotation = 90; g.Parent = b
    end
    b.Parent = pauseScreen
    b.Activated:Connect(function()
        if action == "return" then leavingAt = os.clock() end
        roomRemote:FireServer(action)
    end)
    return b
end
pauseChoice("Resume","再開する",-46,"resume",true)
pauseChoice("Restart","やり直す（最初から）",14,"restart")
pauseChoice("Quit","タイトルへ戻る",74,"return")
pauseButton.Activated:Connect(function() roomRemote:FireServer("pause") end)
UserInputService.InputBegan:Connect(function(input, processed)
    if processed or input.KeyCode ~= Enum.KeyCode.P then return end
    if world:GetAttribute("Paused") then roomRemote:FireServer("resume")
    elseif pauseButton.Visible then roomRemote:FireServer("pause") end
end)
-- 「▼ レバーを落とす」の合図(ブラウザ版の #lift)。ターンの手前で全開のままの時に、右下で点滅する
local liftHint = Instance.new("TextLabel")
liftHint.Name = "LiftHint"
liftHint.Text = "▼ レバーを落とす"
liftHint.Font, liftHint.TextSize = Enum.Font.GothamBlack, 18
liftHint.TextColor3 = Color3.new(1,1,1)
liftHint.BackgroundColor3 = Color3.fromRGB(214,40,40)
liftHint.BackgroundTransparency = 0.08
liftHint.AnchorPoint = Vector2.new(1,1)
liftHint.Size = UDim2.fromOffset(176,36)
liftHint.Visible = false
liftHint.Parent = gui
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,9); c.Parent = liftHint end
tiltButton.Activated:Connect(function()
    -- アクセルを踏んだ後は変えられない(サーバーも受け付けない)
    if boat:GetAttribute("TiltLocked") then return end
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
local predictedST, shownST = nil, nil
local smoothClock = nil
local function predictStart(state, clock)
    if not state or state.x + predOff.x >= 0 then return nil end
    local b = {x=state.x+predOff.x,z=state.z+predOff.z,h=state.h,vx=state.vx,vz=state.vz,w=state.w,throttle=state.throttle,steer=state.steer,
        accF=state.accF,topF=state.topF,gripSet=state.gripSet,gripF=state.gripF,thrustF=state.thrustF,windX=state.windX,windZ=state.windZ,motor=state.motor}
    local t, step = 0, 1/30
    while t < 20 do
        local before = b.x
        stepBoat(b, 1, 0, step)
        t += step
        if b.x >= 0 then
            -- 線を越えた刻みの中の、どの時点で越えたかを割合で求める(1/30秒ずつ跳ねないように)
            local f = (0 - before) / math.max(b.x - before, 1e-6)
            return clock + t - step + step*math.clamp(f, 0, 1)
        end
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
-- オープニング(出走前の演出)。サーバーが Opening を出している間に1回だけ見せる
-- 追尾カメラ(ブラウザ版 src/gfx/camera.js の「追尾」と同じ距離・高さ・視野・傾き)
local chase = {init=false, race=nil, dir=0, ti=0, pos=Vector3.zero, look=Vector3.zero, catch=0, fromPos=Vector3.zero, fromLook=Vector3.zero}
local chaseBoat = nil
local function angLerp(a, b, t)
    local d = (b - a + math.pi) % (2*math.pi) - math.pi
    return a + d*t
end
local openingShow, openingRace = nil, nil
local openingWaitFrom = nil
-- この会場で何走目か(出走表の「第N R」。サーバーの番号は待ち時間の区切りでも増えるので使わない)
local openingCount = 0
local function startOpening(duration)
    local boatsShown, goals, rows = {}, {}, {}
    for i = 1, 6 do
        local t, state = templates:FindFirstChild("Boat"..i), latest[i]
        if t and state and not t:GetAttribute("Absent") then
            local pos = Vector3.new(state[1], 0.5, state[2])*STUDS_PER_METRE
            boatsShown[i] = renderBoats[i]
            goals[i] = CFrame.lookAt(pos, pos+Vector3.new(math.cos(state[3]), 0, math.sin(state[3])))
            renderBoats[i].Parent = workspace
            table.insert(rows, {number = i, name = t:GetAttribute("Racer") or "", cls = t:GetAttribute("Class") or ""})
        end
    end
    local name = world:GetAttribute("TournamentName") or world:GetAttribute("EventName") or "みなとグランプリ"
    gui.Enabled = false
    resultView:hide()
    openingShow = Opening.play({
        camera = camera, venue = world, boats = boatsShown, finalCFrames = goals, rows = rows,
        title = name.."　第"..tostring(openingCount).."R", duration = duration, gui = player.PlayerGui,
        onSkip = function() roomRemote:FireServer("skipOpening") end,
    })
    openingShow.Done:Connect(function()
        openingShow = nil
        chase.init = false
        gui.Enabled = true
        -- 会場に1人だけなら、サーバーもすぐ大時計の場面へ進む
        if (serverClock or 0) < -14 then roomRemote:FireServer("skipOpening") end
    end)
end
-- 検証用: ホームとレースの切り替えで、レースの画面(大時計・結果・オープニング)を出し入れする
if devCombined then
    local function devShow()
        local away = devAway()
        for _, name in ipairs({"MinatoHUD", "MinatoResult", "MinatoOpening"}) do
            for _, g in ipairs(player.PlayerGui:GetDescendants()) do
                if g:IsA("ScreenGui") and g.Name == name then g.Enabled = not away end
            end
        end
    end
    player:GetAttributeChangedSignal("MinatoDevRace"):Connect(devShow)
    player.PlayerGui.DescendantAdded:Connect(function(g)
        if g:IsA("ScreenGui") and devAway() then task.defer(devShow) end
    end)
    devShow()
end
-- レースの音(エンジン・水・観客)を止める。ホームを見ている間・ロビーへ移る途中・一時停止中
local function muteRaceSounds()
    for i = 1, 6 do
        if wakes[i] and wakes[i].engine then wakes[i].engine.Volume = 0 end
    end
    if waterLoop then waterLoop.Volume = 0 end
    if crowdLoop then crowdLoop.Volume = 0 end
end
RunService.RenderStepped:Connect(function(dt)
    if devAway() then muteRaceSounds(); return end
    local openingClock = (serverClock or 0) + math.min(os.clock() - snapshotAt, 0.25)
    -- 会場に1人なら、サーバーが待ってくれるので最初から全部見せる。大勢なら残りの時間だけ
    local solo = #Players:GetPlayers() == 1
    -- 設定でオープニングを見ない人は、出さずにすぐ大時計の場面へ(1人の会場ならサーバーも -14秒へ進む)
    local wantsOpening = player:GetAttribute("MinatoOpening") ~= false
    local openingDue = world:GetAttribute("Opening") ~= nil and openingRace ~= predictionRace
    if openingDue then openingWaitFrom = openingWaitFrom or os.clock() else openingWaitFrom = nil end
    -- 本人の設定(見る・見ない)が届くまで少しだけ待つ(届く前に始めて、一瞬だけ見えてしまわないように。最長1.5秒)
    local settingKnown = player:GetAttribute("MinatoOpening") ~= nil or os.clock() - (openingWaitFrom or 0) > 1.5
    if not openingShow and openingDue and settingKnown and (solo or openingClock < -16.5) and next(latest) then
        openingRace = predictionRace
        openingCount += 1
        if wantsOpening then
            startOpening(solo and world:GetAttribute("Opening") or -14 - openingClock)
        else
            chase.init = false
            if (serverClock or 0) < -14 then roomRemote:FireServer("skipOpening") end
        end
    end
    -- 見ている途中で「見ない」設定が届いた時(読み込みの順番による)は、その場で飛ばす
    if openingShow and not wantsOpening then openingShow.skip() end
    if openingShow then
        -- 全員がスキップを押した(サーバーの時計が -14秒へ進んだ)ら終える。大勢の時は押した人数を出す
        if (serverClock or -100) >= -14 then
            openingShow.skip()
        else
            local votes, total = world:GetAttribute("OpeningVotes") or 0, world:GetAttribute("OpeningPlayers") or 1
            if total > 1 and votes > 0 then openingShow.setSkipText(string.format("スキップ %d/%d", votes, total)) end
        end
        -- オープニングの間は、レース用の艇のしぶきと白い波を止める(しぶきはオープニングの部品が速さに合わせて出す)
        for i = 1, 6 do Wake.stop(wakes[i]) end
        return
    end
    if roundChanged then
        leavingAt = -100
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
    -- 対戦で失格した後の観戦: 「ロビーへ」でレースを離れられる(着は失格のまま)。観戦だけの人と1人のレースは「退出」(観戦をやめる)
    local matchMode = world:GetAttribute("MatchMode")
    local leaveToLobby = boatNumber > 0 and reason ~= "" and (matchMode == "ranked" or matchMode == "online" or matchMode == "event"
        or matchMode == "room" or matchMode == "gp")
    viewing.leaveText = leaveToLobby and "ロビーへ" or "退出"
    viewing.onLeave = leaveToLobby and leaveRace or nil
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
        -- 一時停止中は手元の予測も止める(サーバーも止まっている)
        predictionAccumulator = world:GetAttribute("Paused") and 0 or math.min(predictionAccumulator + dt,0.1)
        while predictionAccumulator >= 1/120 do
            stepBoat(predicted, localThrottle, localSteer, 1/120)
            if currentSequence > 0 then
                pendingSteps[#pendingSteps+1] = {sequence=currentSequence,throttle=localThrottle,steer=localSteer}
                if #pendingSteps > 1200 then table.remove(pendingSteps,1) end
            end
            predictionAccumulator -= 1/120
        end
    end
    -- 届いた艇の状態を手元で進める(大時計の -14秒より前は、サーバーも艇を止めている)
    advanceRemote(world:GetAttribute("Paused") and 0 or dt, (serverClock or -100) >= -14)
    for i, visual in ipairs(renderBoats) do
        local state = latest[i]
        if state then
            local x,z,h,w,vx,vz,th = state[1],state[2],state[3],state[6],state[4],state[5],state[7]
            local r = remoteSims[i]
            if r and r.out == "" then
                x,z,h = r.sim.x+r.off.x, r.sim.z+r.off.z, r.sim.h+r.off.h
                w,vx,vz,th = r.sim.w, r.sim.vx, r.sim.vz, r.sim.throttle
            end
            if i == boatNumber and predicted then
                x,z,h,w,vx,vz,th = predicted.x+predOff.x,predicted.z+predOff.z,predicted.h+predOff.h,predicted.w,predicted.vx,predicted.vz,predicted.throttle
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
            if i == math.max(boatNumber,1) then
                chaseBoat = {h=h, w=w, vx=vx, vz=vz, speed=speed, ti=turnIntensity}
            end
            local sprayIntensity = math.clamp(math.abs(lateralSpeed)/5+math.abs(w)*speed/28,0,1)
            local view = motion[i]
            local turnSign = w < 0 and -1 or 1
            view.yaw += (turnSign*turnIntensity*0.2-view.yaw)*(1-math.exp(-5*dt))
            view.roll += (math.clamp(-w*forwardSpeed*0.034,-0.56,0.56)-view.roll)*(1-math.exp(-7*dt))
            local plane = math.clamp((speed-2)/8,0,1)
            local pitch = 0.01+0.07*plane-0.028*math.clamp(speed/22.6,0,1)+0.05*turnIntensity
            view.pitch += (pitch-view.pitch)*(1-math.exp(-5*dt))
            -- 浮き沈み(ブラウザ版 boat.js と同じ): 止まっている時は少し沈み、滑走で浮く。艇底が波を叩く上下動と、ゆるい揺れ
            local f = math.clamp(speed/22.6,0,1)
            view.poundT = (view.poundT or 0.5) - dt*(1.5+7*f)
            if view.poundT <= 0 then
                view.poundT = 0.5 + math.random()
                view.poundV = (view.poundV or 0) + (0.25+math.random()*0.5)*f
            end
            view.poundV = (view.poundV or 0) + (-(view.poundY or 0)*90 - (view.poundV or 0)*9)*dt
            view.poundY = (view.poundY or 0) + view.poundV*dt
            local bob = math.sin(os.clock()*1.7 + i)*0.02*(1-f)
            local lift = -0.12 + bob + math.max(view.poundY,-0.05) + 0.085*plane
            if wakes[i].engine then
                -- 回転数は速さとスロットルで上がる。自分の艇は少し大きく
                local ratio = math.clamp(speed/22.6,0,1)
                local own = i == boatNumber and 1 or 0.7
                wakes[i].engine.Volume = out=="" and (0.14 + 0.3*ratio + 0.16*th)*own*Sfx.master() or 0
                wakes[i].engine.PlaybackSpeed = 0.62 + 0.62*ratio + 0.2*th
            end
            local sink=math.clamp(sinkTime/1.2,0,1)
            -- 0.16m: 艇の基準点から艇底まで約0.14m。止まると艇底が約0.1m水に入り、モーターの足は水の中
            local pos = Vector3.new(x,0.16+lift-0.3*sink-math.max(0,sinkTime-2.5)*0.26,z)*STUDS_PER_METRE
            local destination = CFrame.lookAt(pos,pos+Vector3.new(math.cos(h),0,math.sin(h)))
                * CFrame.Angles(0,-view.yaw,0) * CFrame.Angles(view.pitch+view.poundY*0.35+0.4*sink,0,view.roll+1.2*sink)
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
        local pos = Vector3.new(ghostState[1],0.1,ghostState[2])*STUDS_PER_METRE
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
    if following then
        local pose,focus=viewing.camera(cf)
        camera.CFrame,camera.Focus=pose,focus
    elseif not (watching and viewing.exited) and chaseBoat then
        -- 追尾カメラ: 艇の後ろ 6.4m・高さ 2.4m(速いと少し引き、ターン中は低く近く)。進む向きと艇の向きの間から見る
        local b = chaseBoat
        local f = math.clamp(b.speed/22.6,0,1)
        if chase.race ~= predictionRace then chase.race = predictionRace; chase.init = false end
        chase.ti += (b.ti-chase.ti)*math.min(1,dt*5)
        local ti = chase.ti
        local velA = b.speed > 3 and math.atan2(b.vz,b.vx) or b.h
        local want = angLerp(velA,b.h,0.45)
        if not chase.init then chase.dir = want end
        chase.dir = angLerp(chase.dir,want,1-math.exp(-dt*4.2))
        local cx, cz = math.cos(chase.dir), math.sin(chase.dir)
        local bx, bz = cf.Position.X/STUDS_PER_METRE, cf.Position.Z/STUDS_PER_METRE
        local close = camMode == 2
        local back = close and (4.0 - 0.6*ti) or (6.4 + 1.5*f - 1.5*ti)
        local up = close and (1.3 - 0.25*ti) or (2.35 + 0.3*f - 0.75*ti)
        local wantPos = Vector3.new(bx-cx*back, up, bz-cz*back)*STUDS_PER_METRE
        local wantLook = Vector3.new(bx+cx*6, close and 0.85 or 1.0, bz+cz*6)*STUDS_PER_METRE
        local fov = (close and 68 or 60) + 13*f*f + 13*ti
        local rigid = false
        if camMode == 3 then
            -- オンボード: 選手の目の少し前から前を見る(ターンの傾き・艇の揺れも一緒)
            local upper = visibleBoat:FindFirstChild("RacerUpper")
            local origin = upper and upper:GetAttribute("RestOrigin")
            local frame = (upper and typeof(origin) == "Vector3") and upper:GetPivot()*CFrame.new(-origin) or cf
            wantPos = frame:PointToWorldSpace(Vector3.new(0, 3.15, -0.7))
            wantLook = frame:PointToWorldSpace(Vector3.new(0, 2.3, -40))
            fov = 74 + 10*f*f + 10*ti
            rigid = true
        elseif camMode == 4 then
            -- 中継: 岸の4か所のカメラのうち、艇がいる側の1台から望遠で追う(2.2秒は切り替えない)
            local centre = 8*math.clamp((bx+150)/300,0,1)
            local want = bx > 96 and 2 or (bx < -96 and 4 or (bz >= centre and 1 or 3))
            chase.tvHold = (chase.tvHold or 0) - dt
            if not chase.tv or (want ~= chase.tv and chase.tvHold <= 0) then
                chase.tv, chase.tvHold = want, 2.2
                camSwitched = true
            end
            local spot = TV_SPOTS[chase.tv]
            wantPos = Vector3.new(spot[1], spot[2], spot[3])*STUDS_PER_METRE
            wantLook = Vector3.new(bx + b.vx*0.25, 0.8, bz + b.vz*0.25)*STUDS_PER_METRE
            local d = (wantPos - wantLook).Magnitude/STUDS_PER_METRE
            fov = math.clamp(2*math.deg(math.atan(spot[4]/math.max(d,1))), 7, 46)
        elseif camMode == 5 then
            -- 上空: 艇の斜め上から見下ろす
            wantPos = Vector3.new(bx-6, 64, bz+40)*STUDS_PER_METRE
            wantLook = Vector3.new(bx, 0, bz)*STUDS_PER_METRE
            fov = 46
        end
        if camSwitched and chase.init then
            -- 視点を替えた時は、その場で切り替える(なめらかに寄せない)
            chase.pos, chase.look, chase.catch = wantPos, wantLook, 0
        end
        camSwitched = false
        if not chase.init then
            -- オープニングや前のカメラの位置から、1.5秒かけてなめらかに(ゆっくり動き出して、ゆっくり止まる)追いつく
            chase.init = true
            chase.fromPos = camera.CFrame.Position
            chase.fromLook = camera.Focus.Position
            chase.pos, chase.look = wantPos, wantLook
            chase.catch = 1.5
        end
        chase.catch = math.max(0, chase.catch-dt)
        if rigid then
            chase.pos, chase.look = wantPos, wantLook
        elseif camMode == 4 then
            chase.pos = wantPos
            chase.look = chase.look:Lerp(wantLook, 1-math.exp(-dt*5))
        elseif camMode == 5 then
            chase.pos = chase.pos:Lerp(wantPos, 1-math.exp(-dt*4))
            chase.look = chase.look:Lerp(wantLook, 1-math.exp(-dt*8))
        else
            chase.pos = chase.pos:Lerp(wantPos, 1-math.exp(-dt*14))
            chase.look = chase.look:Lerp(wantLook, 1-math.exp(-dt*12))
        end
        -- 速さとターンで細かく揺らす(選手の目線に近い視点だけ)
        local shakeOn = player:GetAttribute("MinatoShake") ~= false and camMode <= 2
        local s = shakeOn and (0.012*f*f + 0.02*ti)*STUDS_PER_METRE or 0
        local shake = Vector3.new((math.random()-0.5)*s, (math.random()-0.5)*s*1.4, (math.random()-0.5)*s)
        local eye, look = chase.pos + shake, chase.look
        if chase.catch > 0 then
            local a = 1 - chase.catch/1.5
            a = a*a*(3-2*a)
            eye = chase.fromPos:Lerp(chase.pos, a)
            look = chase.fromLook:Lerp(chase.look, a)
        end
        if eye.Y < 0.45*STUDS_PER_METRE then eye = Vector3.new(eye.X, 0.45*STUDS_PER_METRE, eye.Z) end
        local roll = shakeOn and math.clamp(b.w*(0.035+0.05*f)*(1+ti),-0.2,0.2) or 0
        if rigid then
            -- オンボードは艇の傾きそのまま(目線の上を艇の上へそろえる)
            camera.CFrame = CFrame.lookAt(eye, look, visibleBoat:GetPivot().UpVector)
            roll = nil
        end
        if roll then camera.CFrame = CFrame.lookAt(eye, look) * CFrame.Angles(0,0,roll) end
        camera.Focus = CFrame.new(cf.Position)
        -- 視野: 速いほど・ターンほど広く。縦長の画面では横が狭くなるので少し広げる(中継の望遠はそのまま)
        local v = camera.ViewportSize
        local aspect = v.Y > 0 and v.X/v.Y or 1.6
        if aspect < 1.2 and camMode ~= 4 then fov *= 1 + 0.32*math.clamp((1.2-aspect)/0.7,0,1) end
        camera.FieldOfView += (fov-camera.FieldOfView)*math.min(1,dt*(camMode == 4 and 3 or 5))
    end
    local time = world:GetAttribute("Time") or -8
    -- サーバーの時計を手元で進めた時刻(大時計と予想STを滑らかにする)
    -- サーバーの時計は1秒に15回、通信の遅れつきで届く。手元ではコマごとに進め、届いた時計へ少しずつ寄せる
    -- (届くたびに大時計や予想STの印が前後に跳ねないように)
    local rawClock = (serverClock or time) + math.min(os.clock() - snapshotAt, 0.25)
    if not smoothClock or math.abs(rawClock - smoothClock) > 0.5 then
        smoothClock = rawClock
    else
        if not world:GetAttribute("Paused") then smoothClock += dt end
        smoothClock += (rawClock - smoothClock)*math.min(1, dt*2)
    end
    local clock = smoothClock
    updateVenue(clock, os.clock(), world:GetAttribute("Wind") or 0)
    -- 表示する艇: 自分の艇、観戦中は見ている艇
    local shownLane = (watching and not viewing.exited and viewing.lane) or (boatNumber > 0 and boatNumber) or nil
    local shown = shownLane and templates:FindFirstChild("Boat"..shownLane) or nil
    local startTime = shown and shown:GetAttribute("StartTime")
    local lap = shown and shown:GetAttribute("Lap") or 1
    local finished = shown and shown:GetAttribute("Finished") or false
    local shownOut = shownLane and latest[shownLane] and latest[shownLane][17] or ""
    tiltButton.Visible = driving==true and time < 0
    -- 視点のボタン: 走っている間は右上の角。スタート前はチルトの左(画面が狭い時は大時計と重ならないよう出さない)
    -- チルトが「固定」になるとボタンが広がる(幅150)ので、視点のボタンもその分だけ左へ寄せる
    local tiltLocked = boat:GetAttribute("TiltLocked") == true
    local screenW = gui.AbsoluteSize.X
    camButton.Visible = driving==true and (time >= 0 or screenW >= (tiltLocked and 920 or 840))
    camButton.Position = time < 0 and UDim2.new(1,tiltLocked and -282 or -244,0,12) or UDim2.new(1,-124,0,12)
    -- メニュー: 1人で走るフリーレースの、大時計が回り始めてから結果が出るまで(沈没した後も、やり直し・タイトルへ戻るに使う)。
    -- 走っている間は視点のボタンの左。スタート前は、視点のボタンが出ていればその左、出ていなければその場所
    local paused = world:GetAttribute("Paused") == true
    pauseScreen.Visible = paused
    pauseButton.Visible = running and boatNumber > 0 and time >= -14 and not paused and not resultRows
        and world:GetAttribute("MatchMode") == "single" and #Players:GetPlayers() == 1
    if time >= 0 then
        pauseButton.Position = UDim2.new(1,-244,0,12)
    else
        local camX = tiltLocked and -282 or -244
        pauseButton.Position = UDim2.new(1, camButton.Visible and camX-120 or camX, 0, 12)
    end
    -- レバーを落とす合図: 練習の補助と同じく、フリーレース・フレンド・タイムアタックで、設定がオンの時だけ
    local helpModes = {single=true, room=true, ta=true}
    local liftOn = driving==true and time >= 0 and helpModes[world:GetAttribute("MatchMode") or ""] == true
        and player:GetAttribute("MinatoAssist") ~= false and boat:GetAttribute("AdviceLift") == true and controls.throttle > 0.5
    liftHint.Visible = liftOn
    -- 走行ガイド: 練習の補助がオンのモードで、スタートしてからゴールまで
    local startedNow = boat:GetAttribute("StartTime") ~= nil and not boat:GetAttribute("Finished")
    if driving==true and startedNow and helpModes[world:GetAttribute("MatchMode") or ""] == true
        and player:GetAttribute("MinatoAssist") ~= false and guidePlan and guidePlan.race == predictionRace and predicted then
        drawGuide(predicted.x + predOff.x, predicted.z + predOff.z, boat:GetAttribute("AdviceLift") == true, os.clock())
    else
        hideGuide()
    end
    if liftOn then
        -- 0.25秒ごとに色を替えて点滅させる。スロットルのレバーのすぐ左、レバーの上の方に出す
        -- (パソコンでもレバーは出ているので重ねない。設定でレバーの高さを変えた時もついていく)
        liftHint.BackgroundColor3 = (os.clock()*4)%2 < 1 and Color3.fromRGB(214,40,40) or Color3.fromRGB(255,120,60)
        local throttleLever = gui:FindFirstChild("Throttle")
        if throttleLever then
            local at = throttleLever.AbsolutePosition - gui.AbsolutePosition
            liftHint.Position = UDim2.fromOffset(at.X - 10, at.Y + 46)
        end
    end
    -- アクセルを踏んだら「固定」と出して、押せない見た目にする
    tiltButton.Text = "チルト "..tiltNames[boat:GetAttribute("Tilt") or 2]..(tiltLocked and "　固定" or "")
    tiltButton.AutoButtonColor = not tiltLocked
    tiltButton.BackgroundTransparency = tiltLocked and 0.45 or 0
    tiltButton.TextTransparency = tiltLocked and 0.35 or 0
    tiltButton.Size = UDim2.fromOffset(tiltLocked and 150 or 112, 40)
    tiltButton.Position = UDim2.new(1, tiltLocked and -162 or -124, 0, 12)
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
            local function fire(action)
                return function()
                    if action == "return" or action == "requeue" then leavingAt = os.clock() end
                    roomRemote:FireServer(action)
                end
            end
            -- スタート練習: 大きな文字は自分の ST。評価の言葉と、何番目のスタートか(ブラウザ版と同じ)
            local opts = nil
            if world:GetAttribute("Practice") then
                local mineRow, order = nil, 0
                for k, r in ipairs(resultRows) do if r[1] == boatNumber then mineRow, order = r, k end end
                opts = {placeHeader = "ST順", head = "スタート練習", sub = ""}
                if mineRow then
                    local st = mineRow[8]
                    if mineRow[2] == "F" then
                        opts.head, opts.color = "フライング", Color3.fromRGB(255,90,77)
                        opts.sub = string.format("スタート時刻より %.2f秒 早くラインを通過 — 本番なら失格", -(st or 0))
                    elseif mineRow[2] == "沈" then
                        opts.head, opts.color, opts.sub = "沈没", Color3.fromRGB(255,90,77), "本番なら失格"
                    elseif type(st) ~= "number" then
                        opts.head, opts.sub = "出遅れ", "助走をつけて、針が0を指す瞬間にスタートラインを越えよう"
                    else
                        local word = st <= 0.1 and "トップスタート級！" or (st <= 0.2 and "ナイススタート" or (st <= 0.45 and "まずまず" or (st <= 1 and "遅れ気味" or "出遅れ")))
                        opts.head = string.format("ST %.2f", st)
                        opts.color = st <= 0.2 and Color3.fromRGB(255,210,60) or Color3.new(1,1,1)
                        opts.sub = word.."　"..order.."番目のスタート"
                    end
                end
            end
            if world:GetAttribute("Practice") and phase == "finished" then
                buttons = {{"Again","もう一度",true,fire("again")},{"Lobby","ロビーへ",false,fire("return")}}
            elseif (mode == "ta" or mode == "single") and phase == "finished" then
                buttons = {{"Again","もう一度走る",true,fire("again")},{"Lobby","ロビーへ",false,fire("return")}}
            elseif mode == "gp" and eliminated then
                buttons = {{"WatchFinal","優勝戦を観戦する",true,fire("watchFinal")},{"Lobby","ロビーへ",false,fire("return")}}
            elseif (mode == "ranked" or mode == "online" or mode == "event") and phase == "finished" then
                -- 対戦の後: もう一度同じモードで走る(ロビーへ戻って、自動で待ち合わせに入る)か、ロビーへ
                buttons = {{"Again","もう一度レース",true,fire("requeue")},{"Lobby","ロビーへ",false,fire("return")}}
            elseif mode and phase == "finished" then
                buttons = {{"Lobby","ロビーへ戻る",true,fire("return")}}
            end
            -- 沈没した時は、何に当たったかを出す(ブラウザ版と同じ言葉)
            local myTemplate = boatNumber > 0 and templates:FindFirstChild("Boat"..boatNumber)
            local cause = myTemplate and myTemplate:GetAttribute("SinkCause")
            if cause and not world:GetAttribute("Practice") then
                local words = {mark="ターンマーク", unit="ターンマーク横の消波装置", pole="センターポール", wall="外周の消波装置"}
                opts = opts or {}
                opts.sub = (words[cause] or "障害物").."に強く当たりました"
            end
            resultView:show(resultRows, boatNumber, extra, buttons, key, opts)
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
    -- 毎コマ計算し(ブラウザ版と同じ)、表示は少しだけならす
    -- 予想STのバーはスタート練習だけ(ランク戦・オンライン・大会などは大時計だけ)
    -- 予想STのバー: ランク戦・オンライン・大会は出さない(対戦のイメージ)。
    -- 練習・フリーレース・フレンド・タイムアタックは、本人の設定(オン・オフ)で決める
    local barModes = {single=true, room=true, ta=true}
    local assist = barModes[world:GetAttribute("MatchMode") or ""] == true and player:GetAttribute("MinatoAssist") ~= false
    if pre and assist then
        local st = predicted and predictStart(predicted, clock)
        if st and shownST and math.abs(st - shownST) < 0.3 then
            shownST += (st - shownST)*math.min(1, dt*10)
        else
            shownST = st
        end
        predictedST = shownST
    else predictedST, shownST = nil, nil end
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
    -- 前後の艇との秒差(スタート後・ゴール前・失格していない時だけ)。進んだ距離の差を自分の速さで割る
    local gaps = nil
    if shownLane and startTime and not finished and shownOut == "" and not resultRows and not world:GetAttribute("Practice") then
        local me = latest[shownLane]
        local myRank = shown and shown:GetAttribute("Rank")
        if me and me[21] and myRank then
            local v = math.max(math.sqrt(me[4]*me[4]+me[5]*me[5]), 8)
            gaps = {}
            for i = 1, 6 do
                local other, t = latest[i], templates:FindFirstChild("Boat"..i)
                local rank = t and t:GetAttribute("Rank")
                if i ~= shownLane and other and other[21] and other[17] == "" and rank and not t:GetAttribute("Absent") then
                    if rank == myRank - 1 then
                        gaps[1] = {lane = i, text = other[19] and "ゴール" or string.format("+%.1f秒", math.max(0, (other[21]-me[21])/v))}
                    elseif rank == myRank + 1 and t:GetAttribute("StartTime") then
                        gaps[2] = {lane = i, text = string.format("-%.1f秒", math.max(0, (me[21]-other[21])/v))}
                    end
                end
            end
        end
    end
    -- ロビーへ移る途中(押してから15秒)と一時停止中は、レースの音を止めておく
    if os.clock() - leavingAt < 15 or world:GetAttribute("Paused") then muteRaceSounds() end
    hud:update({
        gaps = gaps,
        visible = not (watching and viewing.exited),
        rank = shown and not resultRows and shownOut == "" and (finished and shown:GetAttribute("Place") or shown:GetAttribute("Rank")) or nil,
        out = shown and shownOut ~= "" and (shownOut=="F" and "F" or (shownOut=="沈" and "沈" or "退")) or nil,
        lapText = lapText,
        time = startTime and math.max(0, clock) or (time >= 0 and clock or 0),
        pre = pre,
        clock = clock,
        dist = predicted and -predicted.x or nil,
        st = predictedST,
        assist = assist,
        hint = helpText,
        order = order,
        boats = dots,
        myLane = shownLane,
        speed = shown and shown:GetAttribute("Speed") or nil,
        wind = windText(),
        windRotation = -math.deg(math.atan2(sy, sx)),
    })
end)
