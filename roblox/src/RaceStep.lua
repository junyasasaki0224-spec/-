-- 1艇を1歩(1/120秒)進める計算。レース会場のサーバーと、タイムアタックの記録の確かめ(走りの再現)で同じ物を使う。
-- Roblox に依存しない(公式 Luau CLI の単体テストでも動く)。
local stepBoat = if script
    then require(game:GetService("ReplicatedStorage"):WaitForChild("BoatPhysics"))
    else require("./BoatPhysics")
local collision = if script then require(script.Parent:WaitForChild("BoatCollision")) else require("./BoatCollision")

local Step = {}
Step.DT = 1 / 120
-- チルト4段階(-0.5°・0°・+1.5°・+3.0°)の加速・最高速・旋回の強さ
Step.TILTS = {
    { acc = 1.085, top = 0.965, grip = 1.065 },
    { acc = 1, top = 1, grip = 1 },
    { acc = 0.94, top = 1.035, grip = 0.945 },
    { acc = 0.88, top = 1.075, grip = 0.89 },
}
-- タイムアタックで記録を確かめる時の上限(大時計の -14秒から数えて)
Step.SOLO_LIMIT = 240

-- 枠なり進入の位置(lane は 0〜5)。1〜3コースはスロー、4〜6コースはダッシュ
function Step.startPosition(lane)
    local x = lane < 3 and -106 - lane * 4 or -182 - (lane - 3) * 5
    return x, 11 + lane * 5.5
end

-- チルトを当てる(wave は波の高さ。波があるほど旋回の強さが少し落ちる)
function Step.applyTilt(boat, index, wave)
    local tilt = Step.TILTS[index]
    boat.tilt = index
    boat.accF, boat.topF = tilt.acc, tilt.top
    boat.gripSet = tilt.grip * (1 - (wave or 0) * 0.006)
end

-- 1艇を1歩進める。戻り値: "out"(失格した)/ "finish"(ゴールした)/ nil
-- 呼ぶ側は、失格・ゴールした艇の入力を止め、着順を付ける
function Step.advance(b, throttle, steer, elapsed, dt)
    local previousX, previousZ = b.x, b.z
    stepBoat(b, throttle, steer, dt)
    collision.walls(b, elapsed)
    collision.obstacles(b, elapsed)
    if b.out then
        return "out"
    end
    b.speed = math.sqrt(b.vx * b.vx + b.vz * b.vz)
    b.trailTimer += dt
    if b.trailTimer >= 0.06 then
        b.trailTimer -= 0.06
        b.trail[#b.trail + 1] = { x = b.x - math.cos(b.h) * 2, z = b.z - math.sin(b.h) * 2, time = elapsed }
        while #b.trail > 0 and elapsed - b.trail[1].time > 2.6 do
            table.remove(b.trail, 1)
        end
    end
    if not b.started and previousX < 0 and b.x >= 0 and b.z > 4 then
        b.started = true
        local fraction = (0 - previousX) / math.max(b.x - previousX, 0.000001)
        b.startTime = elapsed - dt * (1 - fraction)
        if b.startTime < 0 then
            collision.disqualify(b, "F", elapsed)
            return "out"
        end
    end
    -- The mark crossings enforce the correct side and sequence.
    if b.checkpoint == 0 and previousX < 150 and b.x >= 150 and b.z > 8 then
        b.checkpoint = 1
    end
    if b.checkpoint == 1 and previousZ > 8 and b.z <= 8 and b.x > 150 then
        b.checkpoint = 2
    end
    if b.checkpoint == 2 and previousX > 150 and b.x <= 150 and b.z < 8 then
        b.checkpoint = 3
    end
    if b.checkpoint == 3 and previousX > -150 and b.x <= -150 and b.z < 0 then
        b.checkpoint = 4
    end
    if b.checkpoint == 4 and previousZ < 0 and b.z >= 0 and b.x < -150 then
        b.checkpoint = 5
    end
    if b.checkpoint == 5 and previousX < -150 and b.x >= -150 and b.z > 0 then
        b.checkpoint = 0
        b.lap += 1
    end
    if not b.finished and not b.flying and b.lap >= 3 and previousX < 0 and b.x >= 0 and b.z > 4 then
        b.finished = true
        b.finishTime = math.max(0.001, elapsed - (b.startTime or 0))
        return "finish"
    end
    return nil
end

-- タイムアタックの艇を作る(1艇・無風・波なし。モーターは全員同じ 1.0 にして記録を比べられるようにする)
function Step.soloBoat(lane, tilt)
    local x, z = Step.startPosition(lane)
    local b = {
        x = x, z = z, h = 0, vx = 0, vz = 0, w = 0, throttle = 0, steer = 0, lap = 0, checkpoint = 0,
        finished = false, speed = 0, started = false, flying = false, place = 0, laneZ = z,
        windX = 0, windZ = 0, motor = 1, gripF = 1, thrustF = 1, inWake = 0, trail = {}, trailTimer = 0,
    }
    Step.applyTilt(b, tilt, 0)
    return b
end

-- 入力を整数にそろえる(保存して読み直しても同じ値になるように)。1000分の1単位
function Step.quantize(value)
    return math.floor(math.clamp(value, -1, 1) * 1000 + 0.5) / 1000
end

-- 記録した入力の列からタイムアタックの走りを再現する(サーバーが記録を登録する前に確かめる・ゴーストを走らせる)
-- record = { lane = 0〜5, tilt = 1〜4, inputs = { {歩の番号, スロットル×1000, ハンドル×1000, チルト}, ... } }
-- 歩の番号は大時計の -14秒を 0 とする。戻り値: タイム(秒)、または nil と理由
function Step.replay(record, onStep)
    if type(record) ~= "table" or type(record.inputs) ~= "table" then
        return nil, "記録がありません"
    end
    local lane, tilt = record.lane, record.tilt
    if type(lane) ~= "number" or lane % 1 ~= 0 or lane < 0 or lane > 5 then
        return nil, "コースが正しくありません"
    end
    if type(tilt) ~= "number" or not Step.TILTS[tilt] then
        return nil, "チルトが正しくありません"
    end
    local b = Step.soloBoat(lane, tilt)
    local dt = Step.DT
    local elapsed = -14
    local index, throttle, steer = 1, 0, 0
    local inputs = record.inputs
    local limit = math.floor(Step.SOLO_LIMIT / dt)
    for n = 0, limit do
        local item = inputs[index]
        while item and item[1] <= n do
            if type(item[2]) ~= "number" or type(item[3]) ~= "number" then
                return nil, "入力が正しくありません"
            end
            throttle, steer = math.clamp(item[2] / 1000, 0, 1), math.clamp(item[3] / 1000, -1, 1)
            -- 4つ目はチルト(スタート前に変えられるので、変わった歩から当てる)
            if item[4] ~= nil then
                if not Step.TILTS[item[4]] then
                    return nil, "チルトが正しくありません"
                end
                if item[4] ~= b.tilt then
                    Step.applyTilt(b, item[4], 0)
                end
            end
            index += 1
            item = inputs[index]
        end
        elapsed += dt
        local event = Step.advance(b, (b.finished or b.flying) and 0 or throttle, (b.finished or b.flying) and 0 or steer, elapsed, dt)
        if onStep then
            onStep(b, n, elapsed)
        end
        if event == "finish" then
            return b.finishTime
        elseif event == "out" then
            return nil, b.out == "F" and "フライング" or "沈没"
        end
    end
    return nil, "ゴールしていません"
end

return Step
