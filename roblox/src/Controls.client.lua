local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("MinatoInput")
local world = workspace:WaitForChild("Minato")
local boat = world:WaitForChild("Boat1")
local camera = workspace.CurrentCamera

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
local help = label("Help","W / ↑ 加速　A・D / ←・→ 旋回",UDim2.fromOffset(330,34),UDim2.new(0.5,-165,1,-48),15)
local controls = {left=false,right=false,throttle=false}
local function button(name, text, position, key)
    local item = Instance.new("TextButton")
    item.Name, item.Text = name,text
    item.Size, item.Position = UDim2.fromOffset(90,90),position
    item.BackgroundColor3 = Color3.fromRGB(20,52,67)
    item.BackgroundTransparency = 0.25
    item.TextColor3, item.TextSize, item.Font = Color3.new(1,1,1),27,Enum.Font.GothamBold
    item.Parent = gui
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1,0)
    corner.Parent = item
    item.InputBegan:Connect(function(obj)
        if obj.UserInputType == Enum.UserInputType.Touch or obj.UserInputType == Enum.UserInputType.MouseButton1 then controls[key]=true end
    end)
    item.InputEnded:Connect(function(obj)
        if obj.UserInputType == Enum.UserInputType.Touch or obj.UserInputType == Enum.UserInputType.MouseButton1 then controls[key]=false end
    end)
end
button("Left","◀",UDim2.new(0,18,1,-112),"left")
button("Right","▶",UDim2.new(0,118,1,-112),"right")
button("Throttle","加速",UDim2.new(1,-108,1,-112),"throttle")
if UserInputService.TouchEnabled then help.Text = "左で旋回　右を押して加速" end
local function held(key) return UserInputService:IsKeyDown(key) end
local nextSend = 0
RunService.RenderStepped:Connect(function(dt)
    local boatNumber = player:GetAttribute("MinatoBoat") or 0
    boat = world:FindFirstChild("Boat"..math.max(boatNumber,1)) or boat
    if not boat.PrimaryPart then return end
    local cf = boat.PrimaryPart.CFrame
    camera.CameraType = Enum.CameraType.Scriptable
    local desired = cf.Position - cf.LookVector*15 + Vector3.new(0,7,0)
    local target = CFrame.lookAt(desired,cf.Position+cf.LookVector*15+Vector3.new(0,1,0))
    camera.CFrame = camera.CFrame:Lerp(target,1-math.exp(-5*dt))
    local time = world:GetAttribute("Time") or -8
    local speed = boat:GetAttribute("Speed") or 0
    local lap = boat:GetAttribute("Lap") or 1
    local message = time < -8 and string.format("参加受付中　あと %d 秒",math.ceil(-8-time)) or (time < 0 and string.format("スタートまで %.1f",-time) or string.format("%d / 3 周　　%d km/h",lap,speed))
    if boat:GetAttribute("Finished") then message=string.format("ゴール！　%d 着",boat:GetAttribute("Place") or 0) end
    if boat:GetAttribute("Flying") then message="フライング失格" end
    if boatNumber == 0 and time >= -8 then message="観戦中・次のレースから参加\n"..message end
    if boatNumber > 0 then message=boatNumber.."号艇　"..message end
    status.Text = "みなとグランプリ\n"..message
    nextSend += dt
    if nextSend >= 0.1 then
        nextSend = 0
        local left = controls.left or held(Enum.KeyCode.A) or held(Enum.KeyCode.Left)
        local right = controls.right or held(Enum.KeyCode.D) or held(Enum.KeyCode.Right)
        local throttle = controls.throttle or held(Enum.KeyCode.W) or held(Enum.KeyCode.Up)
        if boatNumber > 0 then remote:FireServer(throttle and 1 or 0,(left and 1 or 0)-(right and 1 or 0)) end
    end
end)
