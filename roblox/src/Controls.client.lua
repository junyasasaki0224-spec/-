local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("MinatoInput")
local snapshotRemote = ReplicatedStorage:WaitForChild("MinatoSnapshots")
local setupRemote = ReplicatedStorage:WaitForChild("MinatoSetup")
local stepBoat = require(ReplicatedStorage:WaitForChild("BoatPhysics"))
local world = workspace:WaitForChild("Minato")
local boat = world:WaitForChild("Boat1")
local camera = workspace.CurrentCamera
local renderBoats, wakes, latest = {}, {}, {}
for i = 1, 6 do
    local original = world:WaitForChild("Boat"..i)
    local visual = original:Clone()
    visual.Name = "VisualBoat"..i
    visual.Parent = workspace
    local first = Instance.new("Attachment")
    first.Position = Vector3.new(-1,0,3)
    first.Parent = visual.PrimaryPart
    local second = Instance.new("Attachment")
    second.Position = Vector3.new(1,0,3)
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
    spray.Size = NumberSequence.new({NumberSequenceKeypoint.new(0,0.7),NumberSequenceKeypoint.new(1,2.5)})
    spray.Lifetime = NumberRange.new(0.35,0.7)
    spray.Speed = NumberRange.new(1,3)
    spray.Rate = 0
    spray.Parent = first
    wakes[i] = {trail=trail,spray=spray}
    for _, descendant in ipairs(original:GetDescendants()) do
        if descendant:IsA("BasePart") then descendant.LocalTransparencyModifier = 1 end
    end
    renderBoats[i] = visual
end
local predicted, predictedNumber, running = nil, 0, false
local predictionAccumulator = 0
local function angleDifference(a,b) return (a-b+math.pi)%(2*math.pi)-math.pi end
snapshotRemote.OnClientEvent:Connect(function(states, active)
    latest, running = states, active
    local number = player:GetAttribute("MinatoBoat") or 0
    local state = states[number]
    if not active or not state then predicted=nil; predictedNumber=0; return end
    if predictedNumber ~= number or not predicted then
        predicted = {x=state[1],z=state[2],h=state[3],vx=state[4],vz=state[5],w=state[6],throttle=state[7],steer=state[8]}
        predictedNumber = number
        predictionAccumulator = 0
    else
        local dx, dz = state[1]-predicted.x, state[2]-predicted.z
        local correction = dx*dx+dz*dz > 100 and 1 or 0.2
        predicted.x += dx*correction
        predicted.z += dz*correction
        predicted.h += angleDifference(state[3],predicted.h)*correction
        predicted.vx += (state[4]-predicted.vx)*correction
        predicted.vz += (state[5]-predicted.vz)*correction
        predicted.w += (state[6]-predicted.w)*correction
    end
    predicted.accF,predicted.topF,predicted.gripSet,predicted.gripF = state[9],state[10],state[11],state[12]
    predicted.thrustF,predicted.windX,predicted.windZ,predicted.motor = state[13],state[14],state[15],state[16]
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
local status = label("Status","みなとグランプリ",UDim2.fromOffset(245,75),UDim2.fromOffset(18,18),20)
local tiltButton = Instance.new("TextButton")
tiltButton.Name = "Tilt"
tiltButton.Size = UDim2.fromOffset(140,40)
tiltButton.Position = UDim2.new(1,-158,0,18)
tiltButton.BackgroundColor3 = Color3.fromRGB(15,32,43)
tiltButton.TextColor3 = Color3.new(1,1,1)
tiltButton.Font,tiltButton.TextSize = Enum.Font.GothamBold,16
tiltButton.Parent = gui
local tiltCorner = Instance.new("UICorner")
tiltCorner.CornerRadius = UDim.new(0,8)
tiltCorner.Parent = tiltButton
local tiltNames = {"-0.5°","0°","+1.5°","+3.0°"}
tiltButton.Activated:Connect(function()
    if (world:GetAttribute("Time") or 0)<0 and (player:GetAttribute("MinatoBoat") or 0)>0 then
        setupRemote:FireServer(((boat:GetAttribute("Tilt") or 2)%4)+1)
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
    boat = world:FindFirstChild("Boat"..math.max(boatNumber,1)) or boat
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
    if running and predicted and predictedNumber == boatNumber then
        if boat:GetAttribute("Finished") or boat:GetAttribute("Flying") then throttle=0; steer=0 end
        predictionAccumulator = math.min(predictionAccumulator + dt,0.1)
        while predictionAccumulator >= 1/120 do
            stepBoat(predicted, throttle, steer, 1/120)
            predictionAccumulator -= 1/120
        end
    end
    for i, visual in ipairs(renderBoats) do
        local state = latest[i]
        if state then
            local x,z,h,w = state[1],state[2],state[3],state[6]
            if i == boatNumber and predicted then x,z,h,w = predicted.x,predicted.z,predicted.h,predicted.w end
            local speed = math.sqrt(state[4]*state[4]+state[5]*state[5])
            wakes[i].trail.Enabled = speed > 3
            wakes[i].spray.Rate = math.clamp((speed-5)*3,0,45)
            local pos = Vector3.new(x,0.5,z)
            local destination = CFrame.lookAt(pos,pos+Vector3.new(math.cos(h),0,math.sin(h))) * CFrame.Angles(0,0,math.clamp(-w*0.12,-0.18,0.18))
            local current = visual:GetPivot()
            if (current.Position-destination.Position).Magnitude > 30 then visual:PivotTo(destination)
            else visual:PivotTo(current:Lerp(destination,1-math.exp(-12*dt))) end
        end
    end
    local visibleBoat = renderBoats[math.max(boatNumber,1)]
    local cf = visibleBoat:GetPivot()
    camera.CameraType = Enum.CameraType.Scriptable
    local desired = cf.Position - cf.LookVector*15 + Vector3.new(0,7,0)
    local target = CFrame.lookAt(desired,cf.Position+cf.LookVector*15+Vector3.new(0,1,0))
    camera.CFrame = camera.CFrame:Lerp(target,1-math.exp(-5*dt))
    local time = world:GetAttribute("Time") or -8
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
    nextSend += dt
    if nextSend >= 0.1 then
        nextSend = 0
        if boatNumber > 0 then remote:FireServer(throttle,steer) end
    end
end)
