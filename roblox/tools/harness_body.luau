-- run_sim.py が物理・衝突・AI のモジュールと N を先頭に足して実行する
local tilts = { {acc=1.085,top=0.965,grip=1.065}, {acc=1,top=1,grip=1}, {acc=0.94,top=1.035,grip=0.945}, {acc=0.88,top=1.075,grip=0.89} }
local wins = {0,0,0,0,0,0}
local flyTotal, hitTotal, wallTotal, unfinished = 0, 0, 0, 0
local stSum, stN = {0,0,0,0,0,0}, {0,0,0,0,0,0}
-- Race.server.lua の reset()/step() と同じ手順(Roblox の API 部分を除く)
for raceNumber = 1, N do
  local wave = ((raceNumber*7)%16)/10
  local wind = ((raceNumber*13)%41)/10
  local windAngle = ((raceNumber*47)%360)*math.pi/180
  local boats = {}
  for i = 1, 6 do
    local lane = i-1
    local b = {x = lane < 3 and -106-lane*4 or -182-(lane-3)*5, z = 11+lane*5.5, h=0, vx=0, vz=0, w=0, throttle=0, steer=0, lap=0, checkpoint=0, finished=false, speed=0, started=false, flying=false, place=0}
    b.laneZ = b.z
    b.windX, b.windZ = math.cos(windAngle)*wind, math.sin(windAngle)*wind
    b.motor, b.gripF, b.thrustF, b.inWake = 1,1,1,0
    b.trail, b.trailTimer = {}, 0
    local t = tilts[2]; b.tilt=2; b.accF, b.topF = t.acc, t.top; b.gripSet = t.grip*(1-wave*0.006)
    RaceAI.init(b, i-1, 1000+raceNumber*37+i*7919)
    boats[i] = b
  end
  local elapsed, dt, finishCount, finishTime = -14, 1/120, 0, nil
  local hits = 0
  while elapsed < 240 do
    elapsed += dt
    for i, b in ipairs(boats) do
      local px, pz = b.x, b.z
      local throttle, steer = 0, 0
      if not b.finished and not b.flying then throttle, steer = RaceAI.update(b, boats, elapsed, dt) end
      stepBoat(b, throttle, steer, dt)
      collision.obstacles(b)
      b.speed = math.sqrt(b.vx*b.vx+b.vz*b.vz)
      b.trailTimer += dt
      if b.trailTimer >= 0.06 then
        b.trailTimer -= 0.06
        b.trail[#b.trail+1] = {x=b.x-math.cos(b.h)*2, z=b.z-math.sin(b.h)*2, time=elapsed}
        while #b.trail>0 and elapsed-b.trail[1].time>2.6 do table.remove(b.trail,1) end
      end
      if not b.started and px < 0 and b.x >= 0 and b.z > 4 then
        b.started = true; b.st = elapsed
        if elapsed < 0 then b.flying = true end
      end
      if b.x < -274 or b.x > 274 or b.z < -79 or b.z > 79 then wallTotal += 1 end
      if b.x < -274 or b.x > 274 then b.x=math.clamp(b.x,-274,274); b.vx *= -0.25 end
      if b.z < -79 or b.z > 79 then b.z=math.clamp(b.z,-79,79); b.vz *= -0.25 end
      if b.checkpoint == 0 and px < 150 and b.x >= 150 and b.z > 8 then b.checkpoint=1 end
      if b.checkpoint == 1 and pz > 8 and b.z <= 8 and b.x > 150 then b.checkpoint=2 end
      if b.checkpoint == 2 and px > 150 and b.x <= 150 and b.z < 8 then b.checkpoint=3 end
      if b.checkpoint == 3 and px > -150 and b.x <= -150 and b.z < 0 then b.checkpoint=4 end
      if b.checkpoint == 4 and pz < 0 and b.z >= 0 and b.x < -150 then b.checkpoint=5 end
      if b.checkpoint == 5 and px < -150 and b.x >= -150 and b.z > 0 then b.checkpoint=0; b.lap += 1 end
      if not b.finished and not b.flying and b.lap >= 3 and px < 0 and b.x >= 0 and b.z > 4 then
        b.finished = true; finishCount += 1; b.place = finishCount; b.finishTime = elapsed
        finishTime = finishTime or elapsed
      end
    end
    for i = 1, 5 do for j = i+1, 6 do
      local a, c = boats[i], boats[j]
      local va = a.vx*a.vx + a.vz*a.vz + c.vx*c.vx + c.vz*c.vz
      collision.boats(a, c)
      if math.abs((a.vx*a.vx + a.vz*a.vz + c.vx*c.vx + c.vz*c.vz) - va) > 1 then hits += 1 end
    end end
    for _, b in ipairs(boats) do
      b.speed = math.sqrt(b.vx*b.vx+b.vz*b.vz)
      local wake = 0
      for _, o in ipairs(boats) do
        if o ~= b then
          for k = #o.trail, 1, -2 do
            local p = o.trail[k]; local age = elapsed-p.time; local r = 1.1+age*0.45
            if age >= 0.25 and (p.x-b.x)^2+(p.z-b.z)^2 < r*r then wake=1; break end
          end
        end
        if wake == 1 then break end
      end
      b.inWake += math.clamp(wake-b.inWake,-4*dt,6*dt)
      b.gripF = 1-0.22*b.inWake; b.thrustF = 1-0.05*b.inWake
    end
    if finishCount == 6 or (finishTime and elapsed-finishTime > 45) then break end
  end
  local winner, best = 0, math.huge
  for i, b in ipairs(boats) do
    if b.flying then flyTotal += 1 end
    if b.st and not b.flying then stSum[i] += b.st; stN[i] += 1 end
    if b.finished and b.finishTime < best then best = b.finishTime; winner = i end
    if not b.finished and not b.flying then unfinished += 1 end
  end
  if winner > 0 then wins[winner] += 1 end
  hitTotal += hits
end
local st = {}
for i = 1, 6 do st[i] = stN[i] > 0 and string.format("%.2f", stSum[i]/stN[i]) or "-" end
print(string.format("races %d | wins by lane %s | avg ST %s | flying %d | unfinished boats %d | strong hits/race %.1f | wall steps %d",
  N, table.concat(wins, " "), table.concat(st, " "), flyTotal, unfinished, hitTotal/N, wallTotal))
