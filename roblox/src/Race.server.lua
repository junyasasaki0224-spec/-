-- Minato Grand Prix: server-authoritative prototype.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local water = require(ReplicatedStorage:WaitForChild("CourseWater"))
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local collision = require(script.Parent:WaitForChild("BoatCollision"))
local RaceAI = require(script.Parent:WaitForChild("RaceAI"))
local createRoster = require(ReplicatedStorage:WaitForChild("RaceRoster"))
local RaceStep = require(script.Parent:WaitForChild("RaceStep"))
local Rules = require(script.Parent:WaitForChild("ResultRules"))
-- Studio では保存しない(Roblox に保存した開発用の場所でも)。保存を試す時だけ Workspace の属性 MinatoLiveData を true にする
local localPractice = RunService:IsStudio() and (game.GameId == 0 or not workspace:GetAttribute("MinatoLiveData"))
local PlayerStats = not localPractice and require(script.Parent:WaitForChild("PlayerStats"))
local isRoom = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
-- 会場へはいつもロビーが予約したサーバーで送る。予約していないサーバー(公開・VIP サーバー)は、
-- ロビーを通らずに入った人だけなので、本番では入れない(Studio の試しは除く。PUBLISH.md 手順6の設定と二重の守り)
local strayServer = not RunService:IsStudio() and not isRoom
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
-- 人間の艇には、その人の Roblox のアバターをレーサーとして乗せる(見た目は動いている間だけ持ち、保存しない)
local RacerAvatar = require(ReplicatedStorage:WaitForChild("RacerAvatar"))
-- 検証用の、ロビーと会場をまとめた場所(dev.project.json)では、ロビーと同じ入れ物を使う
local avatarFolder = ReplicatedStorage:FindFirstChild("RacerAvatars") or Instance.new("Folder")
avatarFolder.Name = "RacerAvatars"
avatarFolder.Parent = ReplicatedStorage
local avatarCache, avatarPending = {}, {}
-- その人のアバターの人形(1回だけ作って使い回す)。作れない時は false
local function avatarFor(player)
    local userId = player.UserId
    while avatarPending[userId] do task.wait(0.1) end
    if avatarCache[userId] == nil then
        avatarPending[userId] = true
        avatarCache[userId] = RacerAvatar.build(userId) or false
        avatarPending[userId] = nil
    end
    return avatarCache[userId]
end
-- 艇 lane のアバターを降ろす
local function clearAvatar(lane)
    local old = avatarFolder:FindFirstChild("Lane"..lane)
    if old then old:Destroy() end
end
-- 公開していない Studio では、ワークスペースの属性 MinatoTestMode(ranked / online / event)で
-- オンライン対戦の会場と同じ AI・イベント・結果の表示を確かめられる(保存はしない)
-- タイムアタックは ta(コースは属性 MinatoTestLane = 1〜6)
local TEST_MODES = {ranked=true, online=true, event=true, ta=true, gp=true, single=true, practice=true}
-- 検証用(Studio だけ): ロビーと会場をまとめた場所。ホームの「出走」を待って、この場所の中でフリーレースを始める
local devCombined = localPractice and ReplicatedStorage:FindFirstChild("MinatoDevCombined") ~= nil
local studioMode = devCombined and "single"
    or localPractice and TEST_MODES[workspace:GetAttribute("MinatoTestMode")] and workspace:GetAttribute("MinatoTestMode") or nil
-- スタート練習は、フリーレース(1人用)の仕組みを使い、スタートだけで終わる(成績・報酬なし)
local practiceMode = studioMode == "practice"
if practiceMode then studioMode = "single" end
local practiceEnd = nil
local function matchKind() return roomKind or studioMode end
-- タイムアタック: 走るコース(0〜5)、入力の記録、次の走りを待っているか、ゴースト(世界1位の走りの再現)
local taLane = studioMode == "ta" and math.clamp(math.floor(tonumber(workspace:GetAttribute("MinatoTestLane")) or 1),1,6)-1 or 0
local taPending = studioMode == "ta"
local taRecord, taStep, taLast = nil, 0, nil
local ghostRecord, ghostBoat, ghostIndex, ghostInput = nil, nil, 1, {0,0}
-- Studio のタイムアタックも、会場と同じく「走る人がいたら -14秒から始める」流れにする
if studioMode == "ta" or studioMode == "gp" or studioMode == "single" then roomWaiting = true end
-- フリーレース(1人用): 乗る艇(1〜6)、チルト(1〜4)、難易度(1〜4)、時間帯、出走表の種。ロビーのサーバーが決めて渡す
local ENVS = {day=14, evening=17.4, night=20.5}
local singleCfg = studioMode == "single" and {
    lane = math.clamp(math.floor(tonumber(workspace:GetAttribute("MinatoTestLane")) or 1),1,6),
    tilt = 2, diff = 2, seed = 1,
    -- Studio の試し: 属性 MinatoTestEnv(day / evening / night)で時間帯を選べる
    env = ({day="day", evening="evening", night="night"})[workspace:GetAttribute("MinatoTestEnv")] or "day",
} or nil
local singlePending = studioMode == "single" and not devCombined
-- 大会(T17 ③): 大会の番号、段階(heat = 予選 / final = 優勝戦)、組、この会場で走り終えた数、次を始めてよいか、最新の記録
local TRules = require(script.Parent:WaitForChild("TournamentRules"))
local TStore = require(script.Parent:WaitForChild("TournamentStore"))
local gpTid, gpStage, gpGroup, gpRace, gpPending, gpArrived, gpRecord = nil, nil, nil, 0, false, false, nil
local todayEvent = nil
-- イベント内のランキング(日替わり。得点を足すのはこのサーバーだけ)
local EventBoard = require(script.Parent:WaitForChild("EventBoard"))
local eventDay = nil
local rankedLobbyPlace = nil
local returning = {}
local roomRemote = Instance.new("RemoteEvent")
roomRemote.Name = "MinatoRoomRace"
roomRemote.Parent = ReplicatedStorage
-- 一時停止(1人で走るフリーレースだけ。対戦では止められない)
local racePaused = false
-- フリーレースのやり直しを待っているか(始める時にオープニングを飛ばす)
local quickRestart = false
-- 走行ガイド: AI が考えたこの艇の理想のライン(点の並び)を、本人の画面にだけ送る(練習の補助と同じモードだけ)
local guideRemote = Instance.new("RemoteEvent")
guideRemote.Name = "MinatoGuide"
guideRemote.Parent = ReplicatedStorage
local GUIDE_MODES = {single=true, room=true, ta=true}
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
-- 検証用: ロビーのサーバー(FreeRaceLobby)から「この人がこの出走表で走る」を受け取る(サーバーの中だけの合図)
if devCombined then
    local devStart = Instance.new("BindableFunction")
    devStart.Name = "MinatoDevRace"
    devStart.OnInvoke = function(player, cfg)
        if not roomWaiting or singlePending or world:GetAttribute("RankedPhase") == "racing" then
            return false, "レースの準備中です。少し待ってからもう一度押してください"
        end
        practiceMode = cfg.practice == true
        practiceEnd = nil
        singleCfg = practiceMode and {lane=cfg.lane, tilt=2, diff=2, env="day", seed=math.random(1,1000000)}
            or {lane=cfg.lane, tilt=cfg.tilt, diff=cfg.diff, env=cfg.env, seed=cfg.seed}
        world:SetAttribute("MatchMode","single")
        world:SetAttribute("Practice",practiceMode or nil)
        world:SetAttribute("RankedPhase","waiting")
        singlePending = true
        player:SetAttribute("MinatoDevRace", true)
        return true, practiceMode and "スタート練習を始めます" or "フリーレースを始めます"
    end
    devStart.Parent = game:GetService("ServerStorage")
end


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
water.fill()
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
    -- ブラウザ版と同じターンマーク: 白い台の上に、赤白6段の縞の円すい、てっぺんに赤い玉(円柱を6段重ねて円すいにする)
    local function cylinder(name, diameter, height, y, color)
        local p = part(world,name,Vector3.new(height,diameter,diameter),CFrame.new(mark.X,y,mark.Z)*CFrame.Angles(0,0,math.pi/2),color,Enum.Material.SmoothPlastic,Enum.PartType.Cylinder)
        p.CastShadow = true
        return p
    end
    cylinder("TurnMarkBase",1.72,0.34,0.1,c(242,242,238))
    for k = 0, 5 do
        local t0 = (k+0.5)/6
        cylinder("TurnMark",2*(0.78+(0.16-0.78)*t0),1.7/6+0.01,0.2+1.7*t0,k%2==0 and c(220,37,48) or c(246,246,242))
    end
    part(world,"TurnMarkTop",Vector3.new(0.4,0.4,0.4),CFrame.new(mark.X,1.95,mark.Z),c(220,37,48),Enum.Material.SmoothPlastic,Enum.PartType.Ball)
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
local setEnvironment = water.configure(venue)
setEnvironment("day", 1)
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
    if strayServer then
        player:Kick("ロビーから入り直してください")
        return
    end
    player:SetAttribute("MinatoBoat", 0)
    if not isRoom then return end
    task.spawn(function()
        local join = player:GetJoinData()
        local data = join and join.TeleportData
        -- 大会: 大会の記録で、この会場の組(または優勝戦)の人かを確かめる。ほかの人は観戦として入る
        if type(data) == "table" and data.mode == "gp" then
            -- 記録が一時的に読めない時は、少し待って3回まで読み直す
            local record = nil
            for attempt = 1, 3 do
                record = type(data.tid) == "string" and TStore.get(data.tid) or nil
                if record or player.Parent ~= Players then break end
                task.wait(attempt)
            end
            local role = nil
            if type(record) == "table" then
                if data.stage == "final" then
                    if record.status == "final" and record.finalPrivateId == game.PrivateServerId then
                        role = (table.find(record.finalists or {}, player.UserId) and not data.watch) and "racer" or "watch"
                    end
                else
                    local g = type(data.group) == "number" and record.groups and record.groups[data.group]
                    if record.status == "running" and g and g.privateId == game.PrivateServerId then
                        role = (table.find(g.members, player.UserId) and not data.watch) and "racer" or "watch"
                    end
                end
                if role == "watch" and record.private and not TRules.findEntrant(record, player.UserId) then role = nil end
            end
            if not role or (roomKind and roomKind ~= "gp") or (gpTid and gpTid ~= data.tid) then
                if player.Parent == Players then player:Kick("大会の会場に入れません。ロビーから入り直してください") end
                return
            end
            if player.Parent ~= Players then return end
            roomKind, gpTid, gpRecord = "gp", data.tid, record
            gpStage = data.stage == "final" and "final" or "heat"
            gpGroup = gpStage == "heat" and data.group or nil
            if type(join.SourcePlaceId)=="number" and join.SourcePlaceId>0 then rankedLobbyPlace=rankedLobbyPlace or join.SourcePlaceId end
            world:SetAttribute("MatchMode","gp")
            world:SetAttribute("RoomMode",false)
            world:SetAttribute("TournamentName",record.name)
            if role == "racer" then
                roomMembers[player] = true
                rankedExpected = gpStage == "final" and #(record.finalists or {}) or #record.groups[gpGroup].members
                rankedStartAt = rankedStartAt or os.clock()+20
                if world:GetAttribute("RankedPhase") == nil then world:SetAttribute("RankedPhase","waiting") end
            end
            return
        end
        -- スタート練習: 予約した会場に1人だけ。コース(1〜6)だけを受け取る
        if type(data) == "table" and data.mode == "practice" then
            local lane = data.lane
            if roomKind or next(roomMembers) or type(lane) ~= "number" or lane % 1 ~= 0 or lane < 1 or lane > 6 then
                player:Kick("スタート練習の会場に入れません。ロビーから入り直してください")
                return
            end
            roomKind, practiceMode = "single", true
            singleCfg = {lane=lane, tilt=2, diff=2, env="day", seed=math.random(1,1000000)}
            if type(join.SourcePlaceId)=="number" and join.SourcePlaceId>0 then rankedLobbyPlace=rankedLobbyPlace or join.SourcePlaceId end
            roomMembers[player] = true
            world:SetAttribute("MatchMode","single")
            world:SetAttribute("Practice",true)
            world:SetAttribute("RoomMode",false)
            world:SetAttribute("RankedPhase","waiting")
            singlePending = true
            return
        end
        -- フリーレース: 予約した会場に1人だけ。値はすべて範囲を確かめる
        if type(data) == "table" and data.mode == "single" then
            local function int(v, lo, hi) return type(v) == "number" and v % 1 == 0 and v >= lo and v <= hi end
            if (roomKind and roomKind ~= "single") or next(roomMembers) or not int(data.lane,1,6) or not int(data.tilt,1,4)
                or not int(data.diff,1,4) or not ENVS[data.env] or not int(data.seed,1,1000000) then
                player:Kick("フリーレースの会場に入れません。ロビーから入り直してください")
                return
            end
            roomKind = "single"
            singleCfg = {lane=data.lane, tilt=data.tilt, diff=data.diff, env=data.env, seed=data.seed}
            if type(join.SourcePlaceId)=="number" and join.SourcePlaceId>0 then rankedLobbyPlace=rankedLobbyPlace or join.SourcePlaceId end
            roomMembers[player] = true
            world:SetAttribute("MatchMode","single")
            world:SetAttribute("RoomMode",false)
            world:SetAttribute("RankedPhase","waiting")
            singlePending = true
            return
        end
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
    local cached = avatarCache[player.UserId]
    if cached then cached:Destroy() end
    avatarCache[player.UserId] = nil
    for lane, boat in ipairs(boats) do
        if boat.player == player then
            clearAvatar(lane)
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
    if matchKind() == "single" and singleCfg then seats = {singleCfg.lane} end
    -- 大会: 予選2走目は艇番を逆から、優勝戦は得点の高い順に1号艇から
    if matchKind() == "gp" and gpStage == "heat" and gpRace == 1 then seats = {6,5,4,3,2,1} end
    if matchKind() == "gp" and gpStage == "final" and gpRecord and gpRecord.finalists then
        local order = gpRecord.finalists
        table.sort(players, function(a,b) return (table.find(order,a.UserId) or 99) < (table.find(order,b.UserId) or 99) end)
    end
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
            boat.model:SetAttribute("Class", nil)
            commands[player] = {throttle=0, steer=0, last=0, sequence=0, applied=0}
            player:SetAttribute("MinatoBoat", i)
            -- フリーレースは出走表で選んだチルトで出る
            if matchKind() == "single" and singleCfg then applyTilt(boat, singleCfg.tilt) end
            -- 人間の艇には AI の難易度の差を付けない(タイムアタックは全員 1.0 のまま)
            if matchKind() ~= "ta" and boat.baseMotor then boat.motor = boat.baseMotor end
            local round=raceNumber
            task.spawn(function()
                local outfit=MetaService.get(player.UserId)
                if outfit and raceNumber==round and boat.player==player then
                    player:SetAttribute("MinatoVolume",outfit.volume)
                    player:SetAttribute("MinatoLever",outfit.lever)
                    player:SetAttribute("MinatoQuality",outfit.quality)
                    player:SetAttribute("MinatoAssist",outfit.assist~=false)
                    player:SetAttribute("MinatoShake",outfit.shake~=false)
                    player:SetAttribute("MinatoOpening",outfit.opening~=false)
                    boat.model:SetAttribute("Skin",outfit.skin)
                    boat.model:SetAttribute("HelmetStyle",outfit.helmet)
                    boat.model:SetAttribute("CowlStyle",outfit.cowl)
                    boat.model:SetAttribute("WheelStyle",outfit.wheel)
                    boat.model:SetAttribute("FlagStyle",outfit.flag)
                    -- ヘルメットのシールドを上げて目元を見せる(設定。見た目だけ)
                    boat.model:SetAttribute("VisorUp",outfit.visor==true)
                end
            end)
            -- アバターを乗せる(届くまでは共通のレーサー人形のまま)
            local lane = i
            task.spawn(function()
                local template = avatarFor(player)
                if template and raceNumber==round and boat.player==player then
                    clearAvatar(lane)
                    local copy = template:Clone()
                    copy.Name = "Lane"..lane
                    copy.Parent = avatarFolder
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
    -- アクセルを1度でも踏んだら、そのレースの間はチルトを変えられない(艇の札に TiltLocked を付けて画面にも知らせる)
    if command.throttle > 0 and command.tiltLocked ~= raceNumber then
        command.tiltLocked = raceNumber
        for _, boat in ipairs(boats) do
            if boat.player == player then boat.model:SetAttribute("TiltLocked", true) end
        end
    end
end)
setup.OnServerEvent:Connect(function(player, index, round)
    if roomWaiting or round ~= raceNumber then return end
    if type(index) ~= "number" or index ~= index or index%1 ~= 0 or not tilts[index] or raceClock >= 0 then return end
    local command = commands[player]
    if not command or os.clock()-(command.setupLast or 0)<0.2 then return end
    if command.tiltLocked == raceNumber then return end
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
    local kind = matchKind()
    -- フリーレースは出走表の種で選手・モーター・水面を決める(ロビーで見せた出走表と同じになる)
    local racers = createRoster(kind == "single" and singleCfg and singleCfg.seed or raceNumber)
    if kind == "single" and singleCfg then
        wind, windAngle, wave = createRoster.weather(singleCfg.seed)
    end
    local ta = kind == "ta"
    if ta then wind, windAngle, wave = 0, 0, 0 end
    -- オンライン対戦の空きは達人、フリーレースは今までどおり中級
    local diff = (ONLINE[kind] or kind == "gp") and RaceAI.DIFFS[4] or RaceAI.DIFFS[(kind == "single" and singleCfg) and singleCfg.diff or 2]
    eventDay = kind == "event" and Meta.today() or nil
    todayEvent = eventDay and Meta.eventOf(eventDay) or nil
    if todayEvent then
        wind, windAngle, wave = todayEvent.weather.wind, todayEvent.weather.windDir, todayEvent.weather.wave
    end
    local env = todayEvent and todayEvent.env or ((kind == "single" and singleCfg) and singleCfg.env) or "day"
    setEnvironment(env, wave)
    world:SetAttribute("Environment", env)
    world:SetAttribute("MatchMode", kind)
    world:SetAttribute("Practice", practiceMode or nil)
    practiceEnd = nil
    world:SetAttribute("EventName", todayEvent and todayEvent.name or nil)
    world:SetAttribute("Wind",wind)
    world:SetAttribute("WindDir",windAngle)
    world:SetAttribute("Wave",wave)
    for i,b in ipairs(boats) do
        local lane = i-1
        local startX, startZ = RaceStep.startPosition(lane)
        b.x,b.z,b.h,b.vx,b.vz,b.w = startX,startZ,0,0,0,0
        b.laneZ = b.z
        b.throttle,b.steer,b.lap,b.checkpoint,b.finished,b.speed = 0,0,0,0,false,0
        b.passed = 0
        b.started,b.flying,b.place,b.startTime = false,false,0,nil
        b.out,b.outAt,b.sunk = nil,nil,false
        b.model:SetAttribute("TiltLocked",nil)
        b.model:SetAttribute("AdviceLift",nil)
        b.adviceLift = nil
        b.sentPlan = nil
        racePaused = false
        world:SetAttribute("Paused", nil)
        b.model:SetAttribute("SinkCause",nil)
        b.sinkCause = nil
        b.model:SetAttribute("Skin",nil)
        b.model:SetAttribute("HelmetStyle",nil)
        b.model:SetAttribute("CowlStyle",nil)
        b.model:SetAttribute("WheelStyle",nil)
        b.model:SetAttribute("FlagStyle",nil)
        b.model:SetAttribute("VisorUp",nil)
        clearAvatar(i)
        b.player = nil
        b.humanUserId,b.finishTime = nil,nil
        b.windX,b.windZ = math.cos(windAngle)*wind,math.sin(windAngle)*wind
        -- AI のモーターには難易度の差を足す。人間が乗った時は元のモーター(baseMotor)に戻す(ブラウザ版と同じ)
        b.baseMotor = racers[i].motor
        b.motor,b.gripF,b.thrustF,b.inWake = racers[i].motor+(diff.motor-RaceAI.DIFFS[2].motor),1,1,0
        b.model:SetAttribute("Racer",racers[i].racer.name)
        b.model:SetAttribute("Class",racers[i].racer.cls)
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
-- 出走前のオープニング(見た目だけ。プレイヤー側の Opening.lua が見せる)。
-- この間は艇を出走の位置に止めておき、-14秒から大時計が回る。最初のレースは長く、2走目からは短く
local OPENING_FULL, OPENING_SHORT = 24, 10
local openingShown = false
local assignAt = -14
-- 会場に1人だけの時は、その人の画面のオープニングが終わるまで -14秒の手前で待つ(読み込みで前半を見逃さないように)。
-- 待つのは長くても「オープニングの長さ + 20秒」まで
local openingHold = nil
-- オープニングのスキップの票(押した人)。全員そろったら、みんな一緒に -14秒へ進む
local openingVotes = {}
local function countOpeningVotes()
    local votes, total = 0, 0
    for _, p in ipairs(Players:GetPlayers()) do
        total += 1
        if openingVotes[p] then votes += 1 end
    end
    world:SetAttribute("OpeningVotes", votes)
    world:SetAttribute("OpeningPlayers", total)
    return votes, total
end
local function skipOpeningIfAgreed()
    if not assigned or elapsed >= -14 then return end
    local votes, total = countOpeningVotes()
    if total > 0 and votes >= total then
        elapsed = -14
        raceClock = elapsed
        openingHold = nil
    end
end
local function beginOpening()
    local length = 0
    if not (practiceMode or matchKind() == "ta") then
        length = openingShown and OPENING_SHORT or OPENING_FULL
    end
    openingShown = openingShown or length > 0
    elapsed = -14 - length
    raceClock = elapsed
    -- 出走表の名前を最初から出すため、艇への割り当てはオープニングの初めに行う
    assignAt = elapsed
    world:SetAttribute("Opening", length > 0 and length or nil)
    openingHold = length > 0 and os.clock() + length + 20 or nil
    table.clear(openingVotes)
    countOpeningVotes()
end
-- タイムアタックを始める(大時計の -14秒から)。記録とゴーストも最初から
-- 同じ会場で次のレースを始める(タイムアタックの「もう一度」、大会の予選2走目・優勝戦)
local function startRoomRace()
    reset()
    roomWaiting = false
    world:SetAttribute("RoomWaiting", false)
    world:SetAttribute("RankedPhase", "racing")
    finishTime, finishCount, assigned = nil, 0, false
    beginOpening()
    raceId = HttpService:GenerateGUID(false)
    resultsSaved, aloneSince, finalRows = false, nil, nil
end
local function startTA()
    startRoomRace()
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
-- 大会の得点表(この組、または優勝戦の人だけ。得点の高い順)を文字にする
local function boardText(rec, title)
    local lines = {"大会「"..rec.name.."」　"..title}
    local only = {}
    if gpStage == "heat" and rec.groups and rec.groups[gpGroup] then
        for _, id in ipairs(rec.groups[gpGroup].members) do only[id] = true end
    else
        for _, id in ipairs(rec.finalists or {}) do only[id] = true end
    end
    local n = 0
    for _, st in ipairs(TRules.standings(rec)) do
        if only[st.userId] and n < 6 then
            n += 1
            local marks = {}
            for _, h in ipairs(st.history) do table.insert(marks, tostring(h)) end
            table.insert(lines, string.format("%d. %s　%d点　%s", n, st.name, st.points, table.concat(marks,"・")))
        end
    end
    return table.concat(lines, "\n")
end
local function announce(text)
    world:SetAttribute("GpBoard", text)
end
-- 大会を終える(優勝戦の着順、または得点で優勝を決め、結果を残して全員に知らせる)
local function finishTournament(finalList)
    local rec = TStore.update(gpTid, function(old)
        if type(old) ~= "table" or old.status == "done" or old.status == "canceled" then return nil end
        TRules.finish(old, finalList, os.time())
        return old
    end) or TStore.get(gpTid)
    if rec then gpRecord = rec end
    if rec and rec.status == "done" then TStore.saveResult(rec) end
    local champion = gpRecord and gpRecord.champion
    announce(boardText(gpRecord, "結果")..(champion and ("\n優勝 "..champion.name) or ""))
    world:SetAttribute("RankedPhase", "finished")
end
-- 予選を終えた組: ほかの組を待って優勝戦の会場を用意し、優勝戦に出る人を送る
local function gatherFinal()
    world:SetAttribute("RankedPhase", "between")
    announce(boardText(gpRecord, "予選終了　ほかの組を待っています"))
    local waitedFrom, rec = os.clock(), nil
    while true do
        rec = TStore.get(gpTid)
        if type(rec) ~= "table" then break end
        if rec.status ~= "running" then break end
        if TRules.allHeatsDone(rec) or os.clock() - waitedFrom >= TRules.HEAT_WAIT then
            local access, privateId = "studio", "studio-final"
            if not localPractice then
                local ok, a, pid = pcall(TeleportService.ReserveServerAsync, TeleportService, game.PlaceId)
                access, privateId = ok and a or nil, ok and pid or nil
            end
            if access then
                rec = TStore.update(gpTid, function(old)
                    if type(old) ~= "table" or old.status ~= "running" then return nil end
                    old.finalists = TRules.finalists(old)
                    old.finalAccess, old.finalPrivateId, old.status = access, privateId, "final"
                    return old
                end) or TStore.get(gpTid)
                break
            end
        end
        task.wait(5)
    end
    if type(rec) ~= "table" or rec.status == "canceled" then
        announce("大会は主催者により中止されました")
        world:SetAttribute("RankedPhase", "finished")
        return
    end
    gpRecord = rec
    if rec.status ~= "final" then
        world:SetAttribute("RankedPhase", "finished")
        return
    end
    gpStage = "final"
    announce(boardText(rec, "優勝戦に進む人"))
    if localPractice then
        -- Studio では会場を移らず、同じ会場で優勝戦を走る
        gpGroup, gpRace = nil, 0
        task.delay(12, function() gpPending = true end)
        return
    end
    world:SetAttribute("RankedPhase", "finished")
    for _, p in ipairs(Players:GetPlayers()) do
        if roomMembers[p] and table.find(rec.finalists, p.UserId) then
            local options = Instance.new("TeleportOptions")
            options.ReservedServerAccessCode = rec.finalAccess
            options:SetTeleportData({mode="gp", tid=gpTid, stage="final"})
            task.spawn(pcall, TeleportService.TeleportAsync, TeleportService, game.PlaceId, {p}, options)
        else
            p:SetAttribute("MinatoGp", "eliminated")
        end
    end
end
-- 大会の1レースが終わった後(予選なら得点を足して次へ、優勝戦なら大会を終える)
local function gpAfterRace(list)
    gpRace += 1
    if gpStage == "final" then
        finishTournament(list)
        return
    end
    local heat = gpRace
    local rec = TStore.update(gpTid, function(old)
        if type(old) ~= "table" or old.status ~= "running" then return nil end
        if not TRules.addHeat(old, gpGroup, heat, list) then return nil end
        return old
    end) or TStore.get(gpTid)
    if type(rec) == "table" then gpRecord = rec end
    if not gpRecord or gpRecord.status == "canceled" then
        announce("大会は主催者により中止されました")
        world:SetAttribute("RankedPhase", "finished")
        return
    end
    announce(boardText(gpRecord, "予選 "..heat.."走目まで"))
    if heat < TRules.heatsPerGroup(gpRecord) then
        world:SetAttribute("RankedPhase", "between")
        task.delay(12, function()
            local latest = TStore.get(gpTid)
            if type(latest) == "table" and latest.status == "canceled" then
                announce("大会は主催者により中止されました")
                world:SetAttribute("RankedPhase", "finished")
                return
            end
            gpPending = true
        end)
        return
    end
    if not TRules.needsFinal(gpRecord) then
        finishTournament(nil)
        return
    end
    gatherFinal()
end
saveResults = function()
    if resultsSaved or not assigned then return end
    resultsSaved = true
    local results = {}
    finalRows = {}
    if practiceMode then
        -- スタート練習の結果: ST の早い順(フライングと、通過しなかった艇は後ろ)。成績・報酬には入れない
        local list = table.clone(boats)
        local function key(b) return b.flying and 8 or (b.startTime == nil and 9 or b.startTime) end
        table.sort(list, function(a, b)
            if key(a) == key(b) then return a.number < b.number end
            return key(a) < key(b)
        end)
        for k, boat in ipairs(list) do
            finalRows[k] = {boat.number, boat.flying and "F" or (boat.out == "沈" and "沈" or (boat.startTime and tostring(k) or "—")),
                boat.model:GetAttribute("Racer") or "", boat.humanUserId == nil,
                boat.model:GetAttribute("Skin") or "", boat.model:GetAttribute("HelmetStyle") or "", false, boat.startTime or false}
        end
        return
    end
    for _, boat in ipairs(orderBoats()) do
        if boat.out == "TA" then continue end
        local position = #finalRows + 1
        -- 結果の表: 艇番、着(または F・沈・退出)、名前、AI か、塗装、ヘルメット
        finalRows[position] = {boat.number,boat.out or (boat.finished and tostring(boat.place) or "未完走"),
            boat.model:GetAttribute("Racer") or "",boat.humanUserId == nil,
            boat.model:GetAttribute("Skin") or "",boat.model:GetAttribute("HelmetStyle") or "",
            (not boat.out and boat.finished) and boat.finishTime or false, boat.startTime or false}
        if boat.humanUserId then table.insert(results,Rules.entry(boat,position)) end
    end
    -- レートは人間どうしの着順だけで決める(人間の数と、人間の中の順位をサーバーが付ける)
    Rules.rankHumans(results)
    -- 本番では、サーバーが入場を確かめてモード(roomKind)が決まった会場の結果だけを保存する
    if #results > 0 and not localPractice and (roomKind or RunService:IsStudio()) then
        -- The mode was established only after server-side admission.
        PlayerStats.recordRace(raceId,results,roomKind)
    end
    if matchKind() == "ta" and taRecord then
        for _, boat in ipairs(boats) do
            if boat.humanUserId and boat.finished then submitTA(boat) end
        end
    end
    -- イベント: その日のイベント内のランキングに得点を足す(レースを始めた日の分)
    if matchKind() == "event" and eventDay then
        local day = eventDay
        for _, r in ipairs(results) do
            local name = "選手"
            for _, boat in ipairs(boats) do
                if boat.humanUserId == r.userId then name = boat.model:GetAttribute("Racer") or name end
            end
            task.spawn(EventBoard.add, day, r.userId, name, EventBoard.points(r.place, r.out))
        end
    end
    -- 大会: 人間の着順(失格は0点)を大会の記録へ
    if matchKind() == "gp" and gpTid then
        local list = {}
        for _, r in ipairs(results) do table.insert(list, {userId=r.userId, place=r.place, out=r.out}) end
        task.spawn(gpAfterRace, list)
    end
end
roomRemote.OnServerEvent:Connect(function(player, action)
    -- 一時停止: 会場に1人だけのフリーレース(スタート練習を含む)で、大時計が回り始めてから・ゴール前だけ
    -- (メニューを開くと止まる。スタート前に止めても、大時計ごと止まるのでフライングにはならない)
    local soloSingle = matchKind() == "single" and #Players:GetPlayers() == 1 and (roomMembers[player] or not isRoom)
    if action == "pause" or action == "resume" then
        local solo = soloSingle
        if action == "pause" and solo and assigned and not roomWaiting and elapsed >= -14
            and world:GetAttribute("RankedPhase") ~= "finished" then
            racePaused = true
            world:SetAttribute("Paused", true)
        elseif action == "resume" and racePaused then
            racePaused = false
            world:SetAttribute("Paused", nil)
        end
        return
    end
    -- オープニングのスキップ: 会場に1人だけの時は、すぐ大時計の場面へ進める(大勢の時は各自の画面だけ飛ばす)
    if action == "skipOpening" then
        -- スキップは票。1人なら押した時点で、大勢なら全員(見ない設定の人も自動で票になる)がそろった時に進む
        if assigned and elapsed < -14 then
            openingVotes[player] = true
            skipOpeningIfAgreed()
        end
        return
    end
    -- フリーレースのやり直し(メニューから。いつでも): 今の走りは結果を付けずに止め、同じ出走表で大時計の場面から走り直す
    if action == "restart" and soloSingle and not singlePending and world:GetAttribute("RankedPhase") ~= "waiting" then
        racePaused = false
        world:SetAttribute("Paused", nil)
        roomWaiting = true
        world:SetAttribute("RoomWaiting", true)
        world:SetAttribute("RankedPhase", "waiting")
        singlePending, quickRestart = true, true
        return
    end
    -- タイムアタック: 同じ会場でもう一度走る
    if action == "again" and (matchKind() == "ta" or matchKind() == "single") and roomWaiting and not taPending and not singlePending
        and world:GetAttribute("RankedPhase") == "finished" and (not isRoom or roomMembers[player]) then
        if matchKind() == "ta" then taPending = true else singlePending = true end
        world:SetAttribute("RankedPhase","waiting")
        return
    end
    -- 大会: 予選で敗れた人・観戦の人が、優勝戦を観戦しに行く
    if action == "watchFinal" and roomKind == "gp" and gpRecord and gpRecord.status == "final" and gpRecord.finalAccess
        and not returning[player] then
        returning[player] = true
        task.spawn(function()
            local options = Instance.new("TeleportOptions")
            options.ReservedServerAccessCode = gpRecord.finalAccess
            options:SetTeleportData({mode="gp", tid=gpTid, stage="final", watch=true})
            local ok = pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, {player}, options)
            if not ok and player.Parent == Players then roomRemote:FireClient(player,"優勝戦の会場へ移動できません") end
            returning[player] = nil
        end)
        return
    end
    local phase = world:GetAttribute("RankedPhase")
    local over = phase == "finished" or phase == "incomplete"
    -- 自分の艇が沈没・フライングで失格しているか(失格した人は、レースの途中でもロビーへ戻れる。着は失格のまま)
    local myBoat, myBoatOut = nil, false
    for _, b in ipairs(boats) do
        if b.player == player then myBoat, myBoatOut = b, b.out ~= nil end
    end
    local mayReturn = ((ONLINE[roomKind] or roomKind == "ta") and over and roomMembers[player])
        -- 対戦: 失格した後(観戦中)か、艇に乗っていない観戦の人は、途中でも戻れる
        or ((ONLINE[roomKind] or roomKind == "room") and roomMembers[player] and (myBoatOut or not myBoat))
        -- フリーレース(1人): いつでもタイトル(ロビー)へ戻れる。途中なら結果は付かない
        or (roomKind == "single" and roomMembers[player])
        or (roomKind == "gp" and (over or not roomMembers[player]))
    -- 対戦の後の「もう一度レース」: ロビーへ戻り、同じモードの待ち合わせに自動で入る(入れるかはロビーが確かめる)
    if action == "requeue" and ONLINE[roomKind] and over and roomMembers[player] and rankedLobbyPlace and not returning[player] then
        returning[player] = true
        task.spawn(function()
            local options = Instance.new("TeleportOptions")
            options:SetTeleportData({again = roomKind})
            local ok = pcall(TeleportService.TeleportAsync, TeleportService, rankedLobbyPlace, {player}, options)
            if not ok and player.Parent == Players then roomRemote:FireClient(player,"ロビーへ戻れません。もう一度お試しください") end
            returning[player] = nil
        end)
        return
    end
    -- 検証用: 「ロビーへ」でホームに戻る(走っている途中なら、結果を付けずに止めて待ちに戻す)
    if devCombined and action == "return" then
        if racePaused then
            racePaused = false
            world:SetAttribute("Paused", nil)
        end
        if not over then
            roomWaiting = true
            world:SetAttribute("RoomWaiting", true)
            world:SetAttribute("RankedPhase", "finished")
        end
        player:SetAttribute("MinatoDevRace", false)
        return
    end
    if action == "return" and mayReturn and rankedLobbyPlace and not returning[player] then
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
    beginOpening()
end)
local function step()
    if roomWaiting and (matchKind() == "ta" or matchKind() == "single") then
        -- タイムアタックとフリーレースは、走る人がいて「もう一度」を待っている時に始める
        local present = false
        for _, p in ipairs(Players:GetPlayers()) do
            if not isRoom or roomMembers[p] then present = true; break end
        end
        if matchKind() == "ta" then
            if not taPending or not present then return end
            taPending = false
            startTA()
        else
            if not singlePending or not present then return end
            singlePending = false
            startRoomRace()
            -- やり直しはオープニングを飛ばして、すぐ大時計の場面(-14秒)から
            if quickRestart then
                quickRestart = false
                elapsed, assignAt, openingHold = -14, -14, nil
                raceClock = elapsed
                world:SetAttribute("Opening", nil)
            end
        end
    end
    if roomWaiting and matchKind() == "gp" then
        -- Studio の大会: 自分1人の大会をこの会場の中だけに作る(保存しない)
        if studioMode == "gp" and not gpTid then
            local p = Players:GetPlayers()[1]
            if not p then return end
            local rec = TRules.new("studio-gp", p.UserId, "テストレーサー1", {name="Studio の大会", size=6, format="heats2", start=0, private=false}, os.time())
            TRules.makeGroups(rec)
            rec.status, rec.groups[1].privateId = "running", "studio"
            TStore.update("studio-gp", function() return rec end)
            gpTid, gpStage, gpGroup, gpRecord = "studio-gp", "heat", 1, rec
            world:SetAttribute("TournamentName", rec.name)
        end
        -- 最初のレースは、予定の全員が来たら(または最初の人の到着から20秒で)始める
        if not gpArrived and gpTid then
            local arrived = 0
            for _, p in ipairs(Players:GetPlayers()) do
                if not isRoom or roomMembers[p] then arrived += 1 end
            end
            if studioMode == "gp" then
                gpArrived, gpPending = arrived > 0, arrived > 0
            elseif rankedStartAt and (os.clock() >= rankedStartAt or (rankedExpected > 0 and arrived >= rankedExpected)) then
                gpArrived = true
                if arrived == 0 then
                    world:SetAttribute("RankedPhase","incomplete")
                    return
                end
                gpPending = true
            end
        end
        if not gpPending then return end
        gpPending = false
        startRoomRace()
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
            beginOpening()
            world:SetAttribute("RoomWaiting",false)
            world:SetAttribute("RankedPhase","racing")
        else return end
    end
    elapsed += dt
    raceClock = elapsed
    if not assigned and elapsed >= assignAt then
        assigned = true
        finalRows = nil
        assignPlayers()
    end
    if not assigned then return end
    -- 押していない人が抜けて、残りが全員押していれば進む
    if elapsed < -14 and next(openingVotes) then skipOpeningIfAgreed() end
    -- オープニング中は艇を止めておく
    if elapsed < -14 then return end
    if openingHold then
        if os.clock() < openingHold and #Players:GetPlayers() == 1 then
            elapsed = -14 - dt
            raceClock = elapsed
            return
        end
        openingHold = nil
    end
    if world:GetAttribute("Opening") then world:SetAttribute("Opening", nil) end
    for i,b in ipairs(boats) do
        if b.out then continue end
        local throttle, steer = 0,0
        if not b.finished and not b.flying then
            if b.player then
                local command = commands[b.player]
                if command then
                    if os.clock()-command.last < 0.6 then throttle,steer = command.throttle,command.steer end
                    -- 練習の合図「レバーを落とす」: AI がこの艇を走らせるなら、ターンの手前でスロットルを戻す所か
                    -- (ブラウザ版 ai.js の advice.lift と同じ決まり。AI の計算は艇を動かさず、答えだけ使う)
                    if b.ai and b.started then
                        local advised = RaceAI.update(b,boats,elapsed,dt,collision.units)
                        local lift = advised < 0.5 and (b.speed or 0) > 11
                        if b.adviceLift ~= lift then
                            b.adviceLift = lift
                            b.model:SetAttribute("AdviceLift", lift)
                        end
                        -- ラインを引き直した時だけ送る(1周に数回)
                        local plan = b.ai.plan
                        if plan and b.sentPlan ~= plan and GUIDE_MODES[matchKind() or ""] and b.player:GetAttribute("MinatoAssist") ~= false then
                            b.sentPlan = plan
                            guideRemote:FireClient(b.player, raceNumber, plan.xs, plan.zs, plan.turnStart)
                        end
                    end
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
            -- 沈没した時は、何に当たったかを艇の札に書く(結果の画面で出す)
            if b.out == "沈" then b.model:SetAttribute("SinkCause", b.sinkCause or "mark") end
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
    -- スタート練習: 自分がスタートラインを通過(または失格)したら2.2秒走って終わる。8秒たっても通過しなければ打ち切り
    local practiceDone = false
    if practiceMode and singleCfg then
        local mine = boats[singleCfg.lane]
        if mine.started or mine.out or elapsed > 8 then
            practiceEnd = practiceEnd or elapsed
            practiceDone = elapsed - practiceEnd > 2.2 or not (mine.started or mine.out)
        end
    end
    if practiceDone or endEarly or (finishTime and elapsed-finishTime > 45) or elapsed > 240 then
        -- 大会は、次の段階(予選2走目・優勝戦・終わり)を大会の処理が決めるので、先に待ちにしておく
        if matchKind() == "gp" then
            roomWaiting=true
            world:SetAttribute("RoomWaiting",true)
            world:SetAttribute("RankedPhase","between")
        end
        saveResults()
        if ONLINE[roomKind] or matchKind() == "ta" or matchKind() == "single" then
            roomWaiting=true
            world:SetAttribute("RoomWaiting",true)
            world:SetAttribute("RankedPhase","finished")
            return
        end
        if matchKind() == "gp" then return end
        reset(); elapsed=-31; raceClock=elapsed; finishTime=nil; finishCount=0; assigned=false; assignAt=-14
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
    -- 一時停止中(1人で走るフリーレースだけ)は、時計も艇も進めない
    if racePaused then accumulator = 0 end
    while accumulator >= dt do step(); accumulator -= dt end
    for i,b in ipairs(boats) do
        b.model:SetAttribute("Speed",math.floor(b.speed*3.6+0.5))
        b.model:SetAttribute("Lap",math.min((b.passed or 0)+1,3))
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
            states[i] = {b.x,b.z,b.h,b.vx,b.vz,b.w,b.throttle,b.steer,b.accF,b.topF,b.gripSet,b.gripF,b.thrustF,b.windX,b.windZ,b.motor,b.out or "",b.outAt or 0,b.finished,b.place,progress(b)}
        end
        for _, player in ipairs(Players:GetPlayers()) do
            local command = commands[player]
            snapshots:FireClient(player, states, assigned and not roomWaiting and elapsed >= -14, command and command.applied or 0, raceNumber, elapsed, player:GetAttribute("MinatoBoat") or 0, finalRows, ghost)
        end
    end
end)
