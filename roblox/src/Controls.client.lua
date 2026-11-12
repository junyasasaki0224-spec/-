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
local STUDS_PER_METRE = 3.5
local BOAT_SCALE = STUDS_PER_METRE * (2.9 / 7)
local camera = workspace.CurrentCamera
local renderBoats, wakes, motion, latest = {}, {}, {}, {}
for i = 1, 6 do
    local original = templates:WaitForChild("Boat"..i)
    local visual = original:Clone()
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
snapshotRemote.OnClientEvent:Connect(function(states, active, acknowledged, raceNumber)
    latest, running = states, active
    local number = player:GetAttribute("MinatoBoat") or 0
    local state = states[number]
    if not active or not state then
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
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")
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
    while gui.Parent and not roomCode do
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

local status = label("Status","みなとグランプリ",UDim2.fromOffset(180,75),UDim2.fromOffset(12,12),16)
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
    if (world:GetAttribute("Time") or 0)<0 and (player:GetAttribute("MinatoBoat") or 0)>0 then
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
    local boatNumber = player:GetAttribute("MinatoBoat") or 0
    boat = templates:FindFirstChild("Boat"..math.max(boatNumber,1)) or boat
    local left = held(Enum.KeyCode.A) or held(Enum.KeyCode.Left)
    local right = held(Enum.KeyCode.D) or held(Enum.KeyCode.Right)
    local up = held(Enum.KeyCode.W) or held(Enum.KeyCode.Up)
    local down = held(Enum.KeyCode.S) or held(Enum.KeyCode.Down)
    if up or down then
        controls.throttle = math.clamp(controls.throttle + ((up and 1 or 0)-(down and 1 or 0))*dt,0,1)
        updateThrottle()
    end
    local throttle = controls.throttle
    local steer = left and 1 or (right and -1 or controls.steer)
    nextSend += dt
    if nextSend >= 0.05 and boatNumber > 0 and running and predictionRace then
        nextSend = 0
        inputSequence += 1
        currentSequence = inputSequence
        sentThrottle,sentSteer = throttle,steer
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
                wakes[i].engine.Volume = 0.12 + 0.38*math.clamp(speed/22.6,0,1)
                wakes[i].engine.PlaybackSpeed = 0.75 + 0.9*math.clamp(speed/22.6,0,1)
            end
            local pos = Vector3.new(x,0.5,z)*STUDS_PER_METRE
            local destination = CFrame.lookAt(pos,pos+Vector3.new(math.cos(h),0,math.sin(h)))
                * CFrame.Angles(0,-view.yaw,0) * CFrame.Angles(view.pitch,0,view.roll)
            local current = visual:GetPivot()
            if (current.Position-destination.Position).Magnitude > 30*STUDS_PER_METRE then visual:PivotTo(destination)
            else visual:PivotTo(current:Lerp(destination,1-math.exp(-12*dt))) end
        end
    end
    local visibleBoat = renderBoats[math.max(boatNumber,1)]
    local cf = visibleBoat:GetPivot()
    camera.CameraType = Enum.CameraType.Scriptable
    local forward = Vector3.new(cf.LookVector.X,0,cf.LookVector.Z).Unit
    local desired = cf.Position - forward*(15*STUDS_PER_METRE) + Vector3.new(0,7*STUDS_PER_METRE,0)
    local target = CFrame.lookAt(desired,cf.Position+forward*(15*STUDS_PER_METRE)+Vector3.new(0,STUDS_PER_METRE,0))
    camera.CFrame = camera.CFrame:Lerp(target,1-math.exp(-5*dt))
    local time = world:GetAttribute("Time") or -8
    hand.Rotation = (time*30)%360
    local startTime = boat:GetAttribute("StartTime")
    clockText.Text = startTime and string.format("ST %.2f",startTime) or string.format("%.1f 秒",time)
    local speed = boat:GetAttribute("Speed") or 0
    local lap = boat:GetAttribute("Lap") or 1
    local rank = boat:GetAttribute("Rank") or 1
    tiltButton.Visible = boatNumber > 0 and time < 0
    tiltButton.Text = "チルト "..tiltNames[boat:GetAttribute("Tilt") or 2]
    local message = time < -14 and string.format("参加受付中　あと %d 秒",math.ceil(-14-time)) or (time < 0 and string.format("スタートまで %.1f",-time) or string.format("%d / 3 周　　%d km/h",lap,speed))
    if boat:GetAttribute("Finished") then message=string.format("ゴール！　%d 着",boat:GetAttribute("Place") or 0) end
    if boat:GetAttribute("Flying") then message="フライング失格" end
    if boatNumber == 0 and time >= -14 then message="観戦中・次のレースから参加\n"..message end
    if boatNumber > 0 then message=boatNumber.."号艇　"..rank.."位\n"..message end
    status.Text = "みなとグランプリ\n"..message
end)
