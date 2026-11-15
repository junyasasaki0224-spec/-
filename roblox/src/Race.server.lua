-- Minato Grand Prix: server-authoritative prototype.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local collision = require(script.Parent:WaitForChild("BoatCollision"))
local RaceAI = require(script.Parent:WaitForChild("RaceAI"))
local createRoster = require(script.Parent:WaitForChild("RaceRoster"))
local RaceStep = require(script.Parent:WaitForChild("RaceStep"))
local Rules = require(script.Parent:WaitForChild("ResultRules"))
-- Unpublished Studio places cannot open a DataStore. Only a live result needs it.
local localPractice = RunService:IsStudio() and game.GameId == 0
local PlayerStats = not localPractice and require(script.Parent:WaitForChild("PlayerStats"))
local isRoom = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
-- タイムアタックの記録の保存(世界ランキングとゴースト)。公開していない Studio では使わない
local TimeTrial = not localPractice and require(script.Parent:WaitForChild("TimeTrialStore"))
local RoomService = isRoom and require(script.Parent:WaitForChild("RoomService"))
local MatchQueue = isRoom and require(script.Parent:WaitForChild("MatchQueue"))
local roomMembers, roomHost, roomCode = {}, nil, nil
local roomWaiting = isRoom
local roomKind, rankedStartAt, rankedStarted = nil, nil, false
-- 待ち合わせで来る予定の人数(全員そろえば20秒を待たずに始める)
local rankedExpected = 0
-- オンライン対戦のモード(シーズン・オンライン・イベント)。空きは AI の達人が走り、結果に「AI」と付ける
local ONLINE = {ranked=true, online=true, event=true}
local Meta = require(ReplicatedStorage:WaitForChild("Meta"))
-- 公開していない Studio では、ワークスペースの属性 MinatoTestMode(ranked / online / event)で
-- オンライン対戦の会場と同じ AI・イベント・結果の表示を確かめられる(保存はしない)
-- タイムアタックは ta(コースは属性 MinatoTestLane = 1〜6)
local TEST_MODES = {ranked=true, online=true, event=true, ta=true}
local studioMode = localPractice and TEST_MODES[workspace:GetAttribute("MinatoTestMode")] and workspace:GetAttribute("MinatoTestMode") or nil
local function matchKind() return roomKind or studioMode end
-- タイムアタック: 走るコース(0〜5)、入力の記録、次の走りを待っているか、ゴースト(世界1位の走りの再現)
local taLane = studioMode == "ta" and math.clamp(math.floor(tonumber(workspace:GetAttribute("MinatoTestLane")) or 1),1,6)-1 or 0
local taPending = studioMode == "ta"
local taRecord, taStep, taLast = nil, 0, nil
local ghostRecord, ghostBoat, ghostIndex, ghostInput = nil, nil, 1, {0,0}
-- Studio のタイムアタックも、会場と同じく「走る人がいたら -14秒から始める」流れにする
if studioMode == "ta" then roomWaiting = true end
local todayEvent = nil
local rankedLobbyPlace = nil
local returning = {}
local roomRemote = Instance.new("RemoteEvent")
roomRemote.Name = "MinatoRoomRace"
roomRemote.Parent = ReplicatedStorage
local roomInfo = Instance.new("RemoteFunction")
roomInfo.Name = "MinatoRoomInfo"
roomInfo.Parent = ReplicatedStorage
roomInfo.OnServerInvoke = function(player)
    if roomMembers[player] then return roomCode end
    return nil
end

local input = Instance.new("RemoteEvent")
input.Name = "MinatoInput"
input.Parent = ReplicatedStorage
local snapshots = Instance.new("RemoteEvent")
snapshots.Name = "MinatoSnapshots"
snapshots.Parent = ReplicatedStorage
local setup = Instance.new("RemoteEvent")
setup.Name = "MinatoSetup"
setup.Parent = ReplicatedStorage
local world = Instance.new("Folder")
world.Name = "Minato"
world.Parent = workspace
world:SetAttribute("RoomMode", isRoom)
world:SetAttribute("RoomWaiting", roomWaiting)

local STUDS_PER_METRE = 3.5
local BOAT_SCALE = STUDS_PER_METRE * (2.9 / 7)
local function part(parent, name, size, cf, color, material, shape, scale)
    local p = Instance.new("Part")
    scale = scale or STUDS_PER_METRE
    p.Name, p.Size, p.CFrame, p.Color = name, size * scale, cf - cf.Position + cf.Position * scale, color
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
for _, z in ipairs({-79,59}) do
    part(world,"Breakwater",Vector3.new(516,3,2),CFrame.new(-5,0,z),c(231,229,213),Enum.Material.Concrete)
end
for _, x in ipairs({-263,253}) do
    part(world,"Breakwater",Vector3.new(2,3,138),CFrame.new(x,0,-10),c(231,229,213),Enum.Material.Concrete)
end
for _, mark in ipairs({Vector3.new(150,0,8),Vector3.new(-150,0,0)}) do
    part(world,"TurnMark",Vector3.new(1.6,1.6,1.6),CFrame.new(mark.X,0.8,mark.Z),c(240,104,45),Enum.Material.SmoothPlastic,Enum.PartType.Ball)
    part(world,"MarkFlag",Vector3.new(0.3,7,0.3),CFrame.new(mark.X,4,mark.Z),c(240,240,235))
end
for _, u in ipairs(collision.units) do
    local center = Vector3.new(u.x,0.15,u.z)
    part(world,"MarkFloat",Vector3.new(u.width,0.5,u.length),
        CFrame.lookAt(center,center+Vector3.new(u.dx,0,u.dz)),c(32,98,192))
end
part(world,"StartLine",Vector3.new(0.3,0.1,40),CFrame.new(0,-0.4,28),c(238,235,210),Enum.Material.Neon)
part(world,"CenterPole",Vector3.new(1.2,8,1.2),CFrame.new(0,3.5,4),c(244,220,48),Enum.Material.Metal)

local templates = Instance.new("Folder")
templates.Name = "MinatoTemplates"
templates.Parent = ReplicatedStorage
local colors = {c(245,245,238),c(32,37,42),c(222,59,47),c(49,102,202),c(239,213,54),c(67,170,101)}
local visuals=require(ReplicatedStorage:WaitForChild("VisualModels"))
local venue=visuals.venue(world)
if venue then
    for _,p in ipairs(world:GetChildren()) do
        if p.Name=="Stand" or p.Name=="Terrace" or p.Name=="Breakwater" then p:Destroy() end
    end
end
local boats = {}
for i=1,6 do
    local model = Instance.new("Model")
    model.Name = "Boat"..i
    local hull = part(model,"Hull",Vector3.new(3.1,0.8,7),CFrame.new(),colors[i],Enum.Material.SmoothPlastic,nil,BOAT_SCALE)
    model.PrimaryPart = hull
    part(model,"Bow",Vector3.new(2.5,0.5,2),CFrame.new(0,0.15,-3.5),colors[i],nil,nil,BOAT_SCALE)
    part(model,"Deck",Vector3.new(2.5,0.3,3.8),CFrame.new(0,0.5,0.2),c(220,219,201),nil,nil,BOAT_SCALE)
    part(model,"Motor",Vector3.new(1.1,1.3,1.2),CFrame.new(0,0.5,3.3),c(45,48,50),Enum.Material.Metal,nil,BOAT_SCALE)
    part(model,"Racer",Vector3.new(1.4,1.3,1.5),CFrame.new(0,1.2,0.5),colors[i],nil,nil,BOAT_SCALE)
    part(model,"Helmet",Vector3.new(1.2,1.2,1.2),CFrame.new(0,2,0.2),colors[i],Enum.Material.SmoothPlastic,Enum.PartType.Ball,BOAT_SCALE)
    local detailed=visuals.boat(nil,i)
    if detailed then
        model:Destroy()
        model=detailed
        model.Name="Boat"..i
    end
    model.Parent = templates
    boats[i] = {number=i,model=model, x=-95, z=14+i*5, h=0, vx=0, vz=0, w=0, throttle=0, steer=0, lap=0, checkpoint=0, finished=false, speed=0}
end

local MetaService=require(script.Parent:WaitForChild("MetaService"))
local commands = {}
local raceNumber = 0
local tilts = RaceStep.TILTS
local raceClock = -31
local wave = 0
local function applyTilt(boat, index)
    RaceStep.applyTilt(boat, index, wave)
end
local nextFirst = 1
local saveResults
local function preparePlayer(player)
    player:SetAttribute("MinatoBoat", 0)
    if not isRoom then return end
    task.spawn(function()
        local join = player:GetJoinData()
        local data = join and join.TeleportData
        -- タイムアタック: 予約した会場に1人だけ。コース(1〜6)はロビーのサーバーが決めて渡す
        if type(data) == "table" and data.mode == "ta" then
            local lane = data.lane
            if (roomKind and roomKind ~= "ta") or next(roomMembers) or type(lane) ~= "number" or lane % 1 ~= 0 or lane < 1 or lane > 6 then
                player:Kick("タイムアタックの会場に入れません。ロビーから入り直してください")
                return
            end
            roomKind, taLane = "ta", lane - 1
            if type(join.SourcePlaceId)=="number" and join.SourcePlaceId>0 then rankedLobbyPlace=rankedLobbyPlace or join.SourcePlaceId end
            roomMembers[player] = true
            world:SetAttribute("MatchMode","ta")
            world:SetAttribute("RoomMode",false)
            world:SetAttribute("RankedPhase","waiting")
            -- 世界1位の走りを読んでおき、ゴーストとして一緒に走らせる
            local ghost = TimeTrial and TimeTrial.ghost(taLane)
            if ghost and RaceStep.replay(ghost) then ghostRecord = ghost end
            -- ゴーストを読み終えてから走り始める
            taPending = true
            return
        end
        if type(data) == "table" and ONLINE[data.mode] then
            if rankedStarted or (roomKind and roomKind ~= data.mode) then
                player:Kick("対戦会場に入れません。ロビーから入り直してください")
                return
            end
            local admitted, expected = MatchQueue.accept(player.UserId,game.PrivateServerId,data.mode)
            if not admitted or rankedStarted or (roomKind and roomKind ~= data.mode) then
                if player.Parent == Players then player:Kick("対戦会場に入れません。ロビーから入り直してください") end
                return
            end
            if player.Parent ~= Players then return end
            rankedExpected = math.max(rankedExpected, math.min(expected, 6))
            roomKind=data.mode
            world:SetAttribute("MatchMode",roomKind)
            if type(join.SourcePlaceId)=="number" and join.SourcePlaceId>0 then rankedLobbyPlace=rankedLobbyPlace or join.SourcePlaceId end
            roomMembers[player]=true
            rankedStartAt=rankedStartAt or os.clock()+20
            world:SetAttribute("RoomMode",false)
            world:SetAttribute("RankedPhase","waiting")
            return
        end
        local code = type(data) == "table" and data.mode == "room" and data.code or nil
        local owner
        if code then
            owner = RoomService.accept(code,player.UserId,game.PrivateServerId)
        else
            -- Invitations may arrive directly in this server; launch data can be delayed.
            for _ = 1, 10 do
                if player.Parent ~= Players then return end
                local incoming = player:GetJoinData().LaunchData
                if type(incoming) == "string" and #incoming == 6 then
                    code = incoming
                    owner = RoomService.acceptInvite(code,game.PrivateServerId)
                    break
                end
                task.wait(1)
            end
        end
        if player.Parent ~= Players then return end
        if not owner or (roomKind and roomKind ~= "room") or (roomCode and roomCode ~= code) or (roomHost and roomHost ~= owner) then
            player:Kick("部屋に入れません。ロビーから入り直してください")
            return
        end
        roomKind = "room"
        roomHost, roomCode = owner, code
        roomMembers[player] = true
        world:SetAttribute("RoomHost", owner)
    end)
end
Players.PlayerAdded:Connect(preparePlayer)
Players.PlayerRemoving:Connect(function(player)
    commands[player] = nil
    roomMembers[player] = nil
    for _, boat in ipairs(boats) do
        if boat.player == player then
            collision.disqualify(boat,"退出",raceClock)
            boat.player = nil
        end
    end
    if saveResults then
        local remaining = false
        for _, other in ipairs(Players:GetPlayers()) do
            if other ~= player then remaining = true; break end
        end
        if not remaining then saveResults() end
    end
end)
for _, player in ipairs(Players:GetPlayers()) do preparePlayer(player) end
local function assignPlayers()
    local players = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if not isRoom or roomMembers[player] then table.insert(players,player) end
    end
    table.sort(players, function(a,b) return a.UserId < b.UserId end)
    commands = {}
    for _, player in ipairs(players) do player:SetAttribute("MinatoBoat", 0) end
    -- イベント「大外まくり指令」では、人間を6号艇から順に乗せる(ほかは1号艇から)
    local seats = {1,2,3,4,5,6}
    if todayEvent and todayEvent.lane == 5 then seats = {6,5,4,3,2,1} end
    if matchKind() == "ta" then seats = {taLane+1} end
    for k, i in ipairs(seats) do
        local boat = boats[i]
        local player = nil
        if k <= #players then player = players[((nextFirst+k-2) % #players)+1] end
        boat.player = player
        boat.humanUserId = player and player.UserId or nil
        boat.model:SetAttribute("IsAI", player == nil)
        if player then
            -- 名前はサーバーが決めて配る。Studio では画面写真にアカウント名が写らないよう伏せる
            boat.model:SetAttribute("Racer", RunService:IsStudio() and ("テストレーサー"..k) or player.DisplayName)
            commands[player] = {throttle=0, steer=0, last=0, sequence=0, applied=0}
            player:SetAttribute("MinatoBoat", i)
            local round=raceNumber
            task.spawn(function()
                local outfit=MetaService.get(player.UserId)
                if outfit and raceNumber==round and boat.player==player then
                    boat.model:SetAttribute("Skin",outfit.skin)
                    boat.model:SetAttribute("HelmetStyle",outfit.helmet)
                end
            end)
        end
    end
    if #players > 6 then nextFirst = ((nextFirst+5) % #players)+1 else nextFirst = 1 end
end
input.OnServerEvent:Connect(function(player, throttle, steer, sequence, round)
    local command = commands[player]
    if roomWaiting or round ~= raceNumber then return end
    if not command or type(throttle) ~= "number" or type(steer) ~= "number" or type(sequence) ~= "number" then return end
    if throttle ~= throttle or steer ~= steer or math.abs(throttle) > 1 or math.abs(steer) > 1 then return end
    if sequence ~= sequence or sequence%1 ~= 0 or sequence <= command.sequence or sequence > 2147483647 then return end
    local now = os.clock()
    if now - command.last < 0.04 then return end
    -- 1000分の1にそろえる(タイムアタックの入力を保存して読み直しても同じ走りになるように)
    command.throttle, command.steer, command.last, command.sequence = RaceStep.quantize(math.clamp(throttle,0,1)), RaceStep.quantize(steer), now, sequence
end)
setup.OnServerEvent:Connect(function(player, index, round)
    if roomWaiting or round ~= raceNumber then return end
    if type(index) ~= "number" or index ~= index or index%1 ~= 0 or not tilts[index] or raceClock >= 0 then return end
    local command = commands[player]
    if not command or os.clock()-(command.setupLast or 0)<0.2 then return end
    command.setupLast = os.clock()
    for _,boat in ipairs(boats) do
        if boat.player == player and not boat.started then applyTilt(boat,index); return end
    end
end)

local function progress(b)
    local cp = b.checkpoint
    if cp == 0 then return b.lap*720 + math.clamp(b.x+150,0,300) end
    if cp == 1 or cp == 2 then
        local angle = math.atan2(b.x-150,b.z-8)
        return b.lap*720 + 300 + 60*math.clamp(angle,0,math.pi)/math.pi
    end
    if cp == 3 then return b.lap*720 + 360 + math.clamp(150-b.x,0,300) end
    local angle = math.atan2(-(b.x+150),-b.z)
    return b.lap*720 + 660 + 60*math.clamp(angle,0,math.pi)/math.pi
end
local function orderBoats()
    local order = table.clone(boats)
    table.sort(order,function(a,b)
        local outA,outB = a.out ~= nil, b.out ~= nil
        if outA ~= outB then return not outA end
        if a.finished ~= b.finished then return a.finished end
        if a.finished and b.finished then return a.place < b.place end
        local ap,bp = progress(a),progress(b)
        if ap == bp then return a.model.Name < b.model.Name end
        return ap > bp
    end)
    return order
end

local function reset()
    raceNumber += 1
    wave = ((raceNumber*7)%16)/10
    local wind = ((raceNumber*13)%41)/10
    local windAngle = ((raceNumber*47)%360)*math.pi/180
    local racers = createRoster(raceNumber)
    local kind = matchKind()
    local ta = kind == "ta"
    if ta then wind, windAngle, wave = 0, 0, 0 end
    -- オンライン対戦の空きは達人、フリーレースは今までどおり中級
    local diff = ONLINE[kind] and RaceAI.DIFFS[4] or RaceAI.DIFFS[2]
    todayEvent = kind == "event" and Meta.eventOf(Meta.today()) or nil
    if todayEvent then
        wind, windAngle, wave = todayEvent.weather.wind, todayEvent.weather.windDir, todayEvent.weather.wave
    end
    Lighting.ClockTime = todayEvent and ({day=14, evening=17.4, night=20.5})[todayEvent.env] or 14
    world:SetAttribute("MatchMode", kind)
    world:SetAttribute("EventName", todayEvent and todayEvent.name or nil)
    world:SetAttribute("Wind",wind)
    world:SetAttribute("Wave",wave)
    for i,b in ipairs(boats) do
        local lane = i-1
        local startX, startZ = RaceStep.startPosition(lane)
        b.x,b.z,b.h,b.vx,b.vz,b.w = startX,startZ,0,0,0,0
        b.laneZ = b.z
        b.throttle,b.steer,b.lap,b.checkpoint,b.finished,b.speed = 0,0,0,0,false,0
        b.started,b.flying,b.place,b.startTime = false,false,0,nil
        b.out,b.outAt,b.sunk = nil,nil,false
        b.model:SetAttribute("Skin",nil)
        b.model:SetAttribute("HelmetStyle",nil)
        b.player = nil
        b.humanUserId,b.finishTime = nil,nil
        b.windX,b.windZ = math.cos(windAngle)*wind,math.sin(windAngle)*wind
        b.motor,b.gripF,b.thrustF,b.inWake = racers[i].motor+(diff.motor-RaceAI.DIFFS[2].motor),1,1,0
        b.model:SetAttribute("Racer",racers[i].racer.name)
        b.model:SetAttribute("IsAI",true)
        b.trail,b.trailTimer = {},0
        applyTilt(b,2)
        RaceAI.init(b,i-1,1000+raceNumber*37+i*7919,racers[i].racer,diff)
        -- タイムアタックは自分の1艇だけ。ほかの艇は最初からいない扱い(当たらず、映らない)。モーターは全員同じ
        local absent = ta and i ~= taLane+1
        b.model:SetAttribute("Absent", absent or nil)
        if absent then b.out, b.outAt = "TA", 0 end
        if ta and not absent then b.motor = 1 end
    end
    commands = {}
    for _, player in ipairs(Players:GetPlayers()) do player:SetAttribute("MinatoBoat", 0) end
end
reset()
local elapsed = -31
local finishTime = nil
local finishCount = 0
local assigned = false
local raceId = HttpService:GenerateGUID(false)
local resultsSaved = false
local aloneSince, finalRows = nil,nil
local accumulator = 0
local dt = RaceStep.DT
-- タイムアタックを始める(大時計の -14秒から)。記録とゴーストも最初から
local function startTA()
    reset()
    roomWaiting = false
    world:SetAttribute("RoomWaiting", false)
    world:SetAttribute("RankedPhase", "racing")
    elapsed, finishTime, finishCount, assigned = -14, nil, 0, false
    raceClock = elapsed
    raceId = HttpService:GenerateGUID(false)
    resultsSaved, aloneSince, finalRows = false, nil, nil
    taRecord, taStep, taLast = {lane=taLane, tilt=2, inputs={}}, 0, nil
    ghostBoat, ghostIndex, ghostInput = nil, 1, {0,0}
    if ghostRecord and ghostRecord.lane == taLane then ghostBoat = RaceStep.soloBoat(ghostRecord.lane, ghostRecord.tilt) end
    world:SetAttribute("Ghost", ghostBoat ~= nil)
end
-- タイムを 1'40"2 の形にする
local function formatTime(t)
    local tenths = math.floor(t*10+0.5)
    return string.format("%d'%02d\"%d", tenths//600, (tenths//10)%60, tenths%10)
end
-- タイムアタックのゴール後: 記録した入力から走りを再現して同じタイムになるか確かめ、合えば登録する
local function submitTA(human)
    local record, player = taRecord, human.player
    local replayed, reason = RaceStep.replay(record)
    local matches = replayed ~= nil and math.abs(replayed - human.finishTime) < 1e-6
    task.spawn(function()
        local text
        if not matches then
            warn("Minato time attack replay mismatch: "..tostring(replayed).." / "..tostring(human.finishTime).." "..tostring(reason))
            text = formatTime(human.finishTime).."　記録を確かめられませんでした（登録していません）"
        elseif TimeTrial then
            local result = TimeTrial.submit(human.humanUserId, taLane, human.finishTime, record)
            if result then
                text = formatTime(human.finishTime)..(result.improved and "　自己ベスト更新" or "")
                    ..(result.rank and ("　世界 "..result.rank.."位") or "　世界 100位より下")
            else
                text = formatTime(human.finishTime).."　記録の保存を確認できません"
            end
        else
            text = formatTime(human.finishTime).."　記録を確かめました（Studio では登録しません）"
            -- Studio では世界1位の代わりに、確かめた直前の走りを次のゴーストにする
            if not ghostRecord or replayed < (ghostRecord.time or math.huge) then
                ghostRecord = {lane=record.lane, tilt=record.tilt, inputs=record.inputs, time=replayed}
            end
        end
        if player and player.Parent == Players then roomRemote:FireClient(player, "ta", text) end
    end)
end
saveResults = function()
    if resultsSaved or not assigned then return end
    resultsSaved = true
    local results = {}
    finalRows = {}
    for _, boat in ipairs(orderBoats()) do
        if boat.out == "TA" then continue end
        local position = #finalRows + 1
        -- 結果の表: 艇番、着(または F・沈・退出)、名前、AI か、塗装、ヘルメット
        finalRows[position] = {boat.number,boat.out or (boat.finished and tostring(boat.place) or "未完走"),
            boat.model:GetAttribute("Racer") or "",boat.humanUserId == nil,
            boat.model:GetAttribute("Skin") or "",boat.model:GetAttribute("HelmetStyle") or ""}
        if boat.humanUserId then table.insert(results,Rules.entry(boat,position)) end
    end
    -- レートは人間どうしの着順だけで決める(人間の数と、人間の中の順位をサーバーが付ける)
    Rules.rankHumans(results)
    if #results > 0 and not localPractice then
        -- The mode was established only after server-side admission.
        PlayerStats.recordRace(raceId,results,roomKind)
    end
    if matchKind() == "ta" and taRecord then
        for _, boat in ipairs(boats) do
            if boat.humanUserId and boat.finished then submitTA(boat) end
        end
    end
end
roomRemote.OnServerEvent:Connect(function(player, action)
    -- タイムアタック: 同じ会場でもう一度走る
    if action == "again" and matchKind() == "ta" and roomWaiting and not taPending
        and world:GetAttribute("RankedPhase") == "finished" and (not isRoom or roomMembers[player]) then
        taPending = true
        world:SetAttribute("RankedPhase","waiting")
        return
    end
    if action == "return" and (ONLINE[roomKind] or roomKind == "ta") and (world:GetAttribute("RankedPhase") == "finished" or world:GetAttribute("RankedPhase") == "incomplete")
        and roomMembers[player] and rankedLobbyPlace and not returning[player] then
        returning[player]=true
        task.spawn(function()
            local ok=pcall(TeleportService.TeleportAsync,TeleportService,rankedLobbyPlace,{player})
            if not ok and player.Parent == Players then roomRemote:FireClient(player,"ロビーへ戻れません。もう一度お試しください") end
            returning[player]=nil
        end)
        return
    end
    if not isRoom or roomKind ~= "room" or action ~= "start" or not roomWaiting or not roomMembers[player] or player.UserId ~= roomHost then return end
    roomWaiting = false
    world:SetAttribute("RoomWaiting", false)
    elapsed = -14
    raceClock = elapsed
end)
local function step()
    if roomWaiting and matchKind() == "ta" then
        -- タイムアタックは、走る人がいて「もう一度」を待っている時に始める
        local present = false
        for _, p in ipairs(Players:GetPlayers()) do
            if not isRoom or roomMembers[p] then present = true; break end
        end
        if not taPending or not present then return end
        taPending = false
        startTA()
    end
    if roomWaiting then
        local arrived = 0
        for member in pairs(roomMembers) do
            if member.Parent == Players then arrived += 1 end
        end
        -- 予定の全員が来たら、または最初の人の到着から20秒で、来た人だけで出走する(空きは AI)
        if ONLINE[roomKind] and not rankedStarted and rankedStartAt
            and (os.clock() >= rankedStartAt or (rankedExpected > 0 and arrived >= rankedExpected)) then
            rankedStarted = true
            if arrived == 0 then
                world:SetAttribute("RankedPhase","incomplete")
                return
            end
            -- 会場のモードが決まったので、AI の強さとイベントの水面を決め直す
            reset()
            roomWaiting = false
            elapsed = -14
            raceClock = elapsed
            world:SetAttribute("RoomWaiting",false)
            world:SetAttribute("RankedPhase","racing")
        else return end
    end
    elapsed += dt
    raceClock = elapsed
    if not assigned and elapsed >= -14 then
        assigned = true
        finalRows = nil
        assignPlayers()
    end
    if not assigned then return end
    for i,b in ipairs(boats) do
        if b.out then continue end
        local throttle, steer = 0,0
        if not b.finished and not b.flying then
            if b.player then
                local command = commands[b.player]
                if command then
                    if os.clock()-command.last < 0.6 then throttle,steer = command.throttle,command.steer end
                    command.applied = command.sequence
                end
            else
                throttle,steer = RaceAI.update(b,boats,elapsed,dt,collision.units)
            end
        end
        -- タイムアタック: 実際に使った入力とチルトが変わった時だけ記録する(歩の番号つき)
        if taRecord and b.player then
            local tq, sq = math.floor(throttle*1000+0.5), math.floor(steer*1000+0.5)
            if not taLast or taLast[1] ~= tq or taLast[2] ~= sq or taLast[3] ~= b.tilt then
                taLast = {tq, sq, b.tilt}
                table.insert(taRecord.inputs, {taStep, tq, sq, b.tilt})
            end
        end
        local event = RaceStep.advance(b, throttle, steer, elapsed, dt)
        if event == "out" then
            if b.player then commands[b.player]=nil end
            continue
        elseif event == "finish" then
            if b.player then commands[b.player]=nil end
            finishCount += 1
            b.place = finishCount
            finishTime=finishTime or elapsed
        end
    end
    -- ゴースト: 世界1位の記録を同じ歩の番号で進める(ほかの艇には当たらない)
    if ghostBoat and not ghostBoat.finished and not ghostBoat.out then
        local item = ghostRecord.inputs[ghostIndex]
        while item and item[1] <= taStep do
            ghostInput = {item[2]/1000, item[3]/1000}
            if item[4] and item[4] ~= ghostBoat.tilt and tilts[item[4]] then RaceStep.applyTilt(ghostBoat, item[4], 0) end
            ghostIndex += 1
            item = ghostRecord.inputs[ghostIndex]
        end
        RaceStep.advance(ghostBoat, ghostInput[1], ghostInput[2], elapsed, dt)
    end
    if taRecord then taStep += 1 end
    for i = 1, #boats - 1 do
        for j = i + 1, #boats do
            collision.boats(boats[i], boats[j])
        end
    end
    for _, boat in ipairs(boats) do
        if boat.out then continue end
        boat.speed = math.sqrt(boat.vx * boat.vx + boat.vz * boat.vz)
        local wake = 0
        for _, other in ipairs(boats) do
            if other ~= boat and not other.out then
                for index = #other.trail, 1, -2 do
                    local point = other.trail[index]
                    local age = elapsed-point.time
                    local radius = 1.1+age*0.45
                    if age >= 0.25 and (point.x-boat.x)^2+(point.z-boat.z)^2 < radius*radius then wake=1; break end
                end
            end
            if wake==1 then break end
        end
        boat.inWake += math.clamp(wake-boat.inWake,-4*dt,6*dt)
        boat.gripF = 1-0.22*boat.inWake
        boat.thrustF = 1-0.05*boat.inWake
    end
    local endEarly
    endEarly, aloneSince = Rules.shouldEnd(boats,elapsed,aloneSince)
    if endEarly or (finishTime and elapsed-finishTime > 45) or elapsed > 240 then
        saveResults()
        if ONLINE[roomKind] or matchKind() == "ta" then
            roomWaiting=true
            world:SetAttribute("RoomWaiting",true)
            world:SetAttribute("RankedPhase","finished")
            return
        end
        reset(); elapsed=-31; raceClock=elapsed; finishTime=nil; finishCount=0; assigned=false
        raceId = HttpService:GenerateGUID(false)
        resultsSaved = false
        aloneSince = nil
        if isRoom then
            roomWaiting = true
            world:SetAttribute("RoomWaiting", true)
        end
    end
end
game:BindToClose(function()
    saveResults()
    if PlayerStats then PlayerStats.waitForPending(25) end
end)
local snapshotTimer = 0
RunService.Heartbeat:Connect(function(frame)
    accumulator = math.min(accumulator+frame,0.25)
    while accumulator >= dt do step(); accumulator -= dt end
    for i,b in ipairs(boats) do
        b.model:SetAttribute("Speed",math.floor(b.speed*3.6+0.5))
        b.model:SetAttribute("Lap",math.min(b.lap+1,3))
        b.model:SetAttribute("Finished",b.finished)
        b.model:SetAttribute("Flying",b.flying)
        b.model:SetAttribute("Place",b.place)
        b.model:SetAttribute("Tilt",b.tilt)
        b.model:SetAttribute("StartTime",b.startTime)
    end
    local order = orderBoats()
    for rank,b in ipairs(order) do b.model:SetAttribute("Rank",rank) end
    world:SetAttribute("Time",math.floor(elapsed*10)/10)
    snapshotTimer += frame
    if snapshotTimer >= 1/15 then
        snapshotTimer %= 1/15
        local states = {}
        -- ゴーストの位置(x, z, 向き, ハンドル, ゴールしたか)
        local ghost = ghostBoat and {ghostBoat.x, ghostBoat.z, ghostBoat.h, ghostBoat.steer, ghostBoat.finished or ghostBoat.out ~= nil} or nil
        for i, b in ipairs(boats) do
            states[i] = {b.x,b.z,b.h,b.vx,b.vz,b.w,b.throttle,b.steer,b.accF,b.topF,b.gripSet,b.gripF,b.thrustF,b.windX,b.windZ,b.motor,b.out or "",b.outAt or 0,b.finished,b.place}
        end
        for _, player in ipairs(Players:GetPlayers()) do
            local command = commands[player]
            snapshots:FireClient(player, states, assigned and not roomWaiting, command and command.applied or 0, raceNumber, elapsed, player:GetAttribute("MinatoBoat") or 0, finalRows, ghost)
        end
    end
end)
