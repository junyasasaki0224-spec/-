-- Racing line and pursuit adapted from the browser simulation's ai.js.
local AI = {}
local pi = math.pi
local GRIP = 15.5
local GRIP_USE = 0.86
local ARC_THR = 0.55
local TURN_IN = 9
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function smooth(t) t=clamp(t,0,1); return t*t*(3-2*t) end
local function lerp(a,b,t) return a+(b-a)*t end
local function wrap(a) return (a+pi)%(2*pi)-pi end
local function distance(x,z) return math.sqrt(x*x+z*z) end
local function rand(ai)
    ai.seed = (1664525*ai.seed+1013904223)%4294967296
    return ai.seed/4294967296
end
-- 難易度(src/sim/roster.js の DIFFS と同じ数字)。motor は RaceRoster の中級の値(-0.02)との差を Race 側で足す
AI.DIFFS = {
    {name="初級",skill=0.88,st=0.1,motor=-0.055},
    {name="中級",skill=0.955,st=0.04,motor=-0.02},
    {name="上級",skill=1.015,st=-0.01,motor=0.006},
    {name="達人",skill=1.08,st=-0.06,motor=0.035},
}
-- Seconds of start-line margin for slow and dash approaches (by course).
local START_MARGIN={-.014,.075,.018,-.003,.036,-.025}
local FAST_MARGIN={-.008,.004,-.01,.037,.004,.003}
function AI.init(boat, lane, seed, racer, diff)
    local ai = {lane=lane,seed=seed,skill=1,going=false,firstTurn=true,planMark=0,refined=false,effLane=lane,makuri=0,k=1,dodge=0,wob=0,stuck=0}
    racer = racer or {skill=1,st=0.12,sashi=0.4}
    diff = diff or AI.DIFFS[2]
    ai.skill = racer.skill*diff.skill*(0.985+0.03*rand(ai))
    -- The inner boat can line up early. Outside boats judge a longer approach.
    local caution=START_MARGIN[lane+1]
    -- Fast entries leave less room to cross three inside boats on the first dash lane.
    local pace=math.clamp((diff.skill-AI.DIFFS[2].skill)/(AI.DIFFS[4].skill-AI.DIFFS[2].skill),0,1)
    caution+=pace*FAST_MARGIN[lane+1]
    ai.headway=12+2*pace
    local spread = lane==0 and .18 or 1
    ai.stTarget=math.max(lane>=3 and .025 or .07,racer.st+diff.st+rand(ai)^2*spread-.06+caution)
    ai.sashi = lane > 0 and rand(ai) < racer.sashi
    boat.ai = ai
end
local function countInside(b, boats, markZ)
    local n = 0
    for _,other in ipairs(boats) do
        if other ~= b and not other.out and math.abs(other.x-b.x)<7 and distance(other.x-b.x,other.z-b.z)<28 and math.abs(other.z-markZ)<math.abs(b.z-markZ) then n=n+1 end
    end
    return n
end
local function makePlan(b, mark, boats)
    local ai=b.ai
    local sign=mark==1 and 1 or -1
    local mx,mz=mark==1 and 150 or -150,mark==1 and 8 or 0
    local u0,v0=(b.x-mx)*sign,(b.z-mz)*sign
    local maxV=(mark==1 and 58-mz or mz+78)-5
    local n=countInside(b,boats,mz)
    local approach,close,exit
    if ai.firstTurn and mark==1 then
        n=math.max(n,ai.refined and 0 or ai.effLane)
        approach=8+2.6*ai.effLane
        if ai.sashi then close=1.8+math.min(n,2)+rand(ai); exit=12+2*n+rand(ai)*4
        else close=3.8+1.7*n+rand(ai); exit=14+2.4*n+rand(ai)*4 end
    else
        approach=clamp(math.max(v0,6),11+1.5*n,20+2*n)+(rand(ai)-0.5)*3
        close=(ai.sashi and (1.00-.40*math.clamp((ai.skill-1)*8,0,1)) or 3.8)+2*n+rand(ai)*1.2
        exit=14+2.8*n+rand(ai)*6
    end
    if ai.refined then approach=clamp(v0,7,maxV) end
    approach=math.min(approach,maxV)
    local rho=math.max(9.3+rand(ai)*1.2,(approach+close)/2+0.4)
    local center=approach-rho
    local ux=-math.sqrt(math.max(0,(rho-close)^2-center^2))
    local xs,zs={},{}
    local function push(u,v) xs[#xs+1]=mx+sign*u; zs[#zs+1]=mz+sign*v end
    if u0<ux-3 then
        local length=ux-u0
        local steps=math.max(2,math.ceil(length/5))
        for i=0,steps-1 do local t=i/steps; push(u0+length*t,lerp(v0,approach,smooth(t/0.75))) end
    end
    local turnStart = #xs+1
    for i=0,14 do local th=pi*i/14; push(ux+rho*math.sin(th),center+rho*math.cos(th)) end
    local vEnd=center-rho
    for u=ux-5,-175,-5 do push(u,lerp(vEnd,-math.max(exit,-vEnd),smooth((ux-u)/60))) end
    ai.plan={xs=xs,zs=zs,turnStart=turnStart,ux=ux,sign=sign,mx=mx,mz=mz,vArc=math.sqrt(GRIP_USE*GRIP*ai.skill*(b.gripSet or 1)*rho)}
    ai.planMark=mark
    local best=math.huge
    for i=1,#xs do
        local d=(xs[i]-b.x)^2+(zs[i]-b.z)^2
        if d<best then best=d; ai.k=i end
    end
end
local function timeToCover(distanceLeft, velocity, boat)
    local t,d=0,0
    while d<distanceLeft and t<30 do
        local ratio=math.min(1.2,velocity/22.6)
        local mix=(boat.accF or 1)+((boat.topF or 1)-(boat.accF or 1))*smooth((ratio-0.4)/0.575)
        local wind=0.045*(boat.windX or 0)*smooth((velocity-2)/8)
        velocity=velocity+(7*(boat.motor or 1)*mix+0.08-0.08*velocity-0.01014*velocity*velocity+wind)*0.02
        d=d+velocity*0.02
        t=t+0.02
    end
    return t-(d-distanceLeft)/math.max(velocity,0.1)
end
function AI.update(b, boats, clock, dt, units)
    local ai=b.ai
    ai.wob=ai.wob+dt
    if not b.started then
        local heading=clamp((b.laneZ-b.z)*0.05,-0.2,0.2)
        local steer=clamp(-(heading-b.h)*3,-1,1)
        local remain=-clock+ai.stTarget-0.15
        local vf=b.vx*math.cos(b.h)+b.vz*math.sin(b.h)
        local arrival=timeToCover(math.max(-b.x,0),math.max(vf,0),b)
        if not ai.going and arrival>=remain then ai.going=true end
        local throttle=0
        if ai.going then throttle=arrival<remain-0.04 and 0.5 or 1 end
        return throttle,steer
    end
    local target=b.checkpoint<=2 and 1 or 2
    local keep=ai.plan and ai.planMark~=target and ((b.checkpoint==3 and b.x>0) or (b.checkpoint==0 and b.x<0))
    local wanted=keep and ai.planMark or target
    if ai.firstTurn and b.checkpoint==0 and ai.lane>0 and b.x>20 and b.x<100 then
        local inner={}
        for _,other in ipairs(boats) do
            if other~=b and not other.out and other.started and other.z<b.z then inner[#inner+1]=other end
        end
        table.sort(inner,function(a,c) return a.z>c.z end)
        local beaten=0
        for _,other in ipairs(inner) do if b.x-other.x>=2.2 then beaten=beaten+1 else break end end
        if beaten>ai.makuri then
            ai.makuri=beaten; ai.effLane=math.max(0,ai.lane-beaten)
            if beaten==#inner then ai.sashi=false end
            ai.refined=false; makePlan(b,1,boats)
        end
    end
    if wanted~=ai.planMark or not ai.plan then ai.refined=false; makePlan(b,wanted,boats) end
    local plan=ai.plan
    local uNow=(b.x-plan.mx)*plan.sign
    if not ai.refined and uNow> -42 and uNow<plan.ux-8 then ai.refined=true; makePlan(b,wanted,boats); plan=ai.plan end
    if ai.firstTurn and b.checkpoint==3 then ai.firstTurn=false end
    local xs,zs=plan.xs,plan.zs
    local k=ai.k
    local best=(xs[k]-b.x)^2+(zs[k]-b.z)^2
    for i=k+1,math.min(#xs,k+7) do
        local d=(xs[i]-b.x)^2+(zs[i]-b.z)^2
        if d<best then best=d; k=i end
    end
    ai.k=k
    if k >= #xs-2 and ai.planMark == target then
        ai.refined=false
        makePlan(b,target,boats)
        return 0.5,0
    end
    if best>900 then ai.refined=false; makePlan(b,target,boats); return 0.5,0 end
    local lookahead=6.5+b.speed*0.5
    local j,tx,tz=k,xs[k],zs[k]
    while j<#xs do
        local d=distance(xs[j+1]-b.x,zs[j+1]-b.z)
        if d>=lookahead then
            local d0=distance(xs[j]-b.x,zs[j]-b.z)
            local t=d0>=lookahead and 0 or (lookahead-d0)/math.max(d-d0,0.001)
            tx,tz=lerp(xs[j],xs[j+1],t),lerp(zs[j],zs[j+1],t)
            break
        end
        j=j+1; tx,tz=xs[j],zs[j]
    end
    local ch,sh=math.cos(b.h),math.sin(b.h)
    local dodge=0
    local risk=0
    for _,other in ipairs(boats) do
        if other~=b and not other.out then
            local rx,rz=other.x-b.x,other.z-b.z
            local ahead,side=rx*ch+rz*sh,-rx*sh+rz*ch
            if ahead>0 and ahead<20 then
                local dvx,dvz=other.vx-b.vx,other.vz-b.vz
                local futureSide=side+.65*(-dvx*sh+dvz*ch)
                local futureAhead=ahead+.65*(dvx*ch+dvz*sh)
                local headway=ai.firstTurn and 12 or ai.headway
                local proximity=clamp((headway-futureAhead)/8,0,1)*clamp((4.5-math.abs(futureSide))/3,0,1)
                if proximity>risk then
                    risk=proximity
                    dodge=(side>=0 and -1 or 1)*5*proximity
                end
            end
        end
    end
    ai.dodge=ai.dodge+clamp(dodge-ai.dodge,-7*dt,7*dt)
    tx,tz=clamp(tx-sh*ai.dodge,-258,248),clamp(tz+ch*ai.dodge,-74,54)
    local ox,oz = b.x+1.05*ch, b.z+1.05*sh
    local mx,mz = plan.mx-ox,plan.mz-oz
    local d = distance(mx,mz)
    local markClearance=ai.sashi and 1.52 or 2
    if uNow < 1.5 and d > markClearance and d < 45 then
        local alpha,beta = math.asin(markClearance/d), math.atan2(mz,mx)
        local delta = wrap(math.atan2(tz-oz,tx-ox)-beta)
        if delta < alpha and delta > -alpha*0.5 then
            local reach = distance(tx-ox,tz-oz)
            tx,tz = ox+math.cos(beta+alpha)*reach,oz+math.sin(beta+alpha)*reach
        end
    end
    local clearance=ai.sashi and 1.65 or 2.6
    for _,u in ipairs(units) do
        local rx,rz = tx-u.x,tz-u.z
        if math.abs(rx*u.dx+rz*u.dz) <= u.length/2+2 then
            local lateral = -rx*u.dz+rz*u.dx
            local side = -(b.x-u.x)*u.dz+(b.z-u.z)*u.dx >= 0 and 1 or -1
            if side*lateral < clearance then
                local push = clearance*side-lateral
                tx,tz = tx-u.dz*push,tz+u.dx*push
            end
        end
    end
    local dx,dz=tx-b.x,tz-b.z
    local dist=math.max(distance(dx,dz),0.001)
    local err=wrap(math.atan2(dz,dx)-b.h)
    local noise=math.sin(ai.wob*2.3+ai.lane)*0.03*(1.15-ai.skill*0.6)
    local steer=clamp(-(err+noise)*3.2,-1,1)
    local curvature=2*math.sin(math.min(math.abs(err),pi/2))/dist
    local targetSpeed=math.max(9.5,math.sqrt(GRIP_USE*GRIP*ai.skill*(b.gripF or 1)*(b.gripSet or 1)/math.max(curvature,0.0001)))
    local throttle=clamp(0.55+(targetSpeed-b.speed)*0.45,0.1,1)
    local dTurn=plan.ux-uNow
    if dTurn>0 and dTurn<60 then
        local entry=plan.vArc*1.16
        if ai.firstTurn and ai.sashi then entry=entry*0.93 end
        if b.speed*b.speed-entry*entry>2*6.2*dTurn then throttle=dTurn>TURN_IN and 0.05 or ARC_THR end
    end
    if k >= plan.turnStart-1 and k <= plan.turnStart+12 then throttle=math.max(throttle,ARC_THR) end
    for _,other in ipairs(boats) do
        if other~=b and not other.out then
            local rx,rz=other.x-b.x,other.z-b.z
            local ahead,side=rx*ch+rz*sh,-rx*sh+rz*ch
            local dvx,dvz=other.vx-b.vx,other.vz-b.vz
            local closing=-(dvx*ch+dvz*sh)
            local crossing=side+clamp(ahead/math.max(1,closing),0,0.75)*(-dvx*sh+dvz*ch)
            if ahead>0.1 and ahead<6.8+math.max(0,closing)*1.2 and math.abs(crossing)<3.2 then
                throttle=math.min(throttle,0.08)
            end
        end
    end
    throttle=math.min(throttle,1-.95*risk)
    if b.speed<3.5 then
        ai.stuck+=dt
        if ai.stuck>1 and (risk<.6 or ai.stuck>2+ai.lane*.25) then throttle=1 end
    else ai.stuck=0 end
    return throttle,steer
end
return AI
