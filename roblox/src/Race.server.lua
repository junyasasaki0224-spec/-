-- Minato Grand Prix: server-authoritative prototype.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local input = Instance.new("RemoteEvent")
input.Name = "MinatoInput"
input.Parent = ReplicatedStorage
local world = Instance.new("Folder")
world.Name = "Minato"
world.Parent = workspace

local function part(parent, name, size, cf, color, material, shape)
    local p = Instance.new("Part")
    p.Name, p.Size, p.CFrame, p.Color = name, size, cf, color
    p.Material = material or Enum.Material.SmoothPlastic
    p.Anchored, p.CanCollide = true, false
    if shape then p.Shape = shape end
    p.Parent = parent
    return p
end
local function c(r,g,b) return Color3.fromRGB(r,g,b) end
Lighting.ClockTime = 14
Lighting.Brightness = 2
Lighting.Ambient = c(135,150,160)
part(world,"Water",Vector3.new(560,1,170),CFrame.new(0,-1,0),c(39,104,124),Enum.Material.Glass).Transparency = 0.24
part(world,"Stand",Vector3.new(440,14,35),CFrame.new(0,5,101),c(96,106,110),Enum.Material.Concrete)
for i = 0, 5 do
    part(world,"Terrace",Vector3.new(440,2,5),CFrame.new(0,12+i*2,90+i*5),c(169,176,173),Enum.Material.Concrete)
end
for _, z in ipairs({-83,83}) do
    part(world,"Breakwater",Vector3.new(560,3,2),CFrame.new(0,0,z),c(231,229,213),Enum.Material.Concrete)
end
for _, x in ipairs({-278,278}) do
    part(world,"Breakwater",Vector3.new(2,3,166),CFrame.new(x,0,0),c(231,229,213),Enum.Material.Concrete)
end
for _, mark in ipairs({Vector3.new(150,0,8),Vector3.new(-150,0,0)}) do
    part(world,"TurnMark",Vector3.new(3,3,3),CFrame.new(mark.X,1,mark.Z),c(240,104,45),Enum.Material.SmoothPlastic,Enum.PartType.Ball)
    part(world,"MarkFlag",Vector3.new(0.3,7,0.3),CFrame.new(mark.X,4,mark.Z),c(240,240,235))
end
part(world,"StartLine",Vector3.new(0.3,0.1,40),CFrame.new(0,-0.4,28),c(238,235,210),Enum.Material.Neon)

local colors = {c(245,245,238),c(32,37,42),c(222,59,47),c(49,102,202),c(239,213,54),c(67,170,101)}
local boats = {}
for i=1,6 do
    local model = Instance.new("Model")
    model.Name = "Boat"..i
    local hull = part(model,"Hull",Vector3.new(3.1,0.8,7),CFrame.new(),colors[i],Enum.Material.SmoothPlastic)
    model.PrimaryPart = hull
    part(model,"Bow",Vector3.new(2.5,0.5,2),CFrame.new(0,0.15,-3.5),colors[i])
    part(model,"Deck",Vector3.new(2.5,0.3,3.8),CFrame.new(0,0.5,0.2),c(220,219,201))
    part(model,"Motor",Vector3.new(1.1,1.3,1.2),CFrame.new(0,0.5,3.3),c(45,48,50),Enum.Material.Metal)
    part(model,"Racer",Vector3.new(1.4,1.3,1.5),CFrame.new(0,1.2,0.5),colors[i])
    part(model,"Helmet",Vector3.new(1.2,1.2,1.2),CFrame.new(0,2,0.2),colors[i],Enum.Material.SmoothPlastic,Enum.PartType.Ball)
    model.Parent = world
    boats[i] = {model=model, x=-95, z=14+i*5, h=0, vx=0, vz=0, w=0, throttle=0, steer=0, lap=0, checkpoint=0, finished=false, speed=0}
end

local commands = {}
local nextFirst = 1
local function preparePlayer(player)
    player:SetAttribute("MinatoBoat", 0)
end
Players.PlayerAdded:Connect(preparePlayer)
Players.PlayerRemoving:Connect(function(player)
    commands[player] = nil
    for _, boat in ipairs(boats) do
        if boat.player == player then boat.player = nil end
    end
end)
for _, player in ipairs(Players:GetPlayers()) do preparePlayer(player) end
local function assignPlayers()
    local players = Players:GetPlayers()
    table.sort(players, function(a,b) return a.UserId < b.UserId end)
    commands = {}
    for _, player in ipairs(players) do player:SetAttribute("MinatoBoat", 0) end
    for i, boat in ipairs(boats) do
        local player = nil
        if i <= #players then player = players[((nextFirst+i-2) % #players)+1] end
        boat.player = player
        if player then
            commands[player] = {throttle=0, steer=0, last=0}
            player:SetAttribute("MinatoBoat", i)
        end
    end
    if #players > 6 then nextFirst = ((nextFirst+5) % #players)+1 else nextFirst = 1 end
end
input.OnServerEvent:Connect(function(player, throttle, steer)
    local command = commands[player]
    if not command or type(throttle) ~= "number" or type(steer) ~= "number" then return end
    if throttle ~= throttle or steer ~= steer or math.abs(throttle) > 1 or math.abs(steer) > 1 then return end
    local now = os.clock()
    if now - command.last < 0.04 then return end
    command.throttle, command.steer, command.last = math.clamp(throttle,0,1), steer, now
end)

local function wrap(a) return (a + math.pi) % (2*math.pi) - math.pi end
local function smooth(a,b,x)
    local t = math.clamp((x-a)/(b-a),0,1)
    return t*t*(3-2*t)
end
local function target(b, i)
    local r = 17 + i*2
    if b.checkpoint == 0 then return 150, 8+r end
    if b.checkpoint == 1 then return 150+r, 8 end
    if b.checkpoint == 2 then return 150, 8-r end
    if b.checkpoint == 3 then return -150, -r end
    if b.checkpoint == 4 then return -150-r, 0 end
    return -150, r
end
local function reset()
    for i,b in ipairs(boats) do
        b.x,b.z,b.h,b.vx,b.vz,b.w = -95,14+i*5,0,0,0,0
        b.throttle,b.steer,b.lap,b.checkpoint,b.finished,b.speed = 0,0,0,0,false,0
        b.started,b.flying,b.place = false,false,0
        b.player = nil
    end
    commands = {}
    for _, player in ipairs(Players:GetPlayers()) do player:SetAttribute("MinatoBoat", 0) end
end
reset()
local elapsed = -25
local finishTime = nil
local finishCount = 0
local assigned = false
local accumulator = 0
local dt = 1/120
local function step()
    elapsed += dt
    if not assigned and elapsed >= -8 then
        assigned = true
        assignPlayers()
    end
    if not assigned then return end
    for i,b in ipairs(boats) do
        local previousX, previousZ = b.x, b.z
        local throttle, steer = 0,0
        if not b.finished and not b.flying then
            if b.player then
                local command = commands[b.player]
                if command and os.clock()-command.last < 0.6 then throttle,steer = command.throttle,command.steer end
            elseif assigned then
                local tx,tz = target(b,i)
                local desired = math.atan2(tz-b.z,tx-b.x)
                local errorAngle = wrap(desired-b.h)
                steer = math.clamp(-errorAngle*1.8,-1,1)
                throttle = math.abs(errorAngle)>0.5 and 0.48 or 1
            end
        end
        if not b.player and elapsed < -6.4 then throttle = 0 end
        b.throttle += math.clamp(throttle-b.throttle,-5*dt,3.2*dt)
        b.steer += math.clamp(steer-b.steer,-5*dt,5*dt)
        local ch,sh = math.cos(b.h),math.sin(b.h)
        local vf,vl = b.vx*ch+b.vz*sh,-b.vx*sh+b.vz*ch
        local sp = math.abs(vf)
        local hull = smooth(0.5,6,sp)
        local auth = hull*(1-0.24*math.min(1,sp/22.6))+0.3*b.throttle*(1-hull)
        local yaw = -b.steer*1.6*auth + 1.3*vl/math.max(sp,4)*hull
        b.w += (yaw-b.w)*(1-math.exp(-7*dt))
        b.h += b.w*dt
        ch,sh = math.cos(b.h),math.sin(b.h)
        vf,vl = b.vx*ch+b.vz*sh,-b.vx*sh+b.vz*ch
        local af = b.throttle*7+0.08-0.08*vf-0.01014*vf*math.abs(vf)-0.3*math.abs(vl)
        vf += af*dt
        vl -= math.clamp(9*vl,-13.5,13.5)*dt
        b.vx,b.vz = vf*ch-vl*sh,vf*sh+vl*ch
        b.x,b.z = b.x+b.vx*dt,b.z+b.vz*dt
        b.speed = math.sqrt(b.vx*b.vx+b.vz*b.vz)
        if not b.started and previousX < 0 and b.x >= 0 and b.z > 4 then
            b.started = true
            if elapsed < 0 then b.flying = true end
        end
        if b.x < -274 or b.x > 274 then b.x=math.clamp(b.x,-274,274); b.vx *= -0.25 end
        if b.z < -79 or b.z > 79 then b.z=math.clamp(b.z,-79,79); b.vz *= -0.25 end
        -- The mark crossings enforce the correct side and sequence.
        if b.checkpoint == 0 and previousX < 150 and b.x >= 150 and b.z > 8 then b.checkpoint=1 end
        if b.checkpoint == 1 and previousZ > 8 and b.z <= 8 and b.x > 150 then b.checkpoint=2 end
        if b.checkpoint == 2 and previousX > 150 and b.x <= 150 and b.z < 8 then b.checkpoint=3 end
        if b.checkpoint == 3 and previousX > -150 and b.x <= -150 and b.z < 0 then b.checkpoint=4 end
        if b.checkpoint == 4 and previousZ < 0 and b.z >= 0 and b.x < -150 then b.checkpoint=5 end
        if b.checkpoint == 5 and previousX < -150 and b.x >= -150 and b.z > 0 then b.checkpoint=0; b.lap += 1 end
        if not b.finished and not b.flying and b.lap >= 3 and previousX < 0 and b.x >= 0 and b.z > 4 then
            b.finished=true
            finishCount += 1
            b.place = finishCount
            finishTime=finishTime or elapsed
        end
    end
    if (finishTime and elapsed-finishTime > 45) or elapsed > 240 then
        reset(); elapsed=-25; finishTime=nil; finishCount=0; assigned=false
    end
end
RunService.Heartbeat:Connect(function(frame)
    accumulator = math.min(accumulator+frame,0.25)
    while accumulator >= dt do step(); accumulator -= dt end
    for i,b in ipairs(boats) do
        local pos = Vector3.new(b.x,0.5,b.z)
        b.model:PivotTo(CFrame.lookAt(pos,pos+Vector3.new(math.cos(b.h),0,math.sin(b.h))) * CFrame.Angles(0,0,math.clamp(-b.w*0.12,-0.18,0.18)))
        b.model:SetAttribute("Speed",math.floor(b.speed*3.6+0.5))
        b.model:SetAttribute("Lap",math.min(b.lap+1,3))
        b.model:SetAttribute("Finished",b.finished)
        b.model:SetAttribute("Flying",b.flying)
        b.model:SetAttribute("Place",b.place)
    end
    world:SetAttribute("Time",math.floor(elapsed*10)/10)
end)
