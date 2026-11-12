-- Racing line and pursuit adapted from the browser simulation's ai.js.
local AI = {}
local pi = math.pi
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function smooth(t) t=clamp(t,0,1); return t*t*(3-2*t) end
local function lerp(a,b,t) return a+(b-a)*t end
local function wrap(a) return (a+pi)%(2*pi)-pi end
local function distance(x,z) return math.sqrt(x*x+z*z) end
local function rand(ai)
    ai.seed = (1664525*ai.seed+1013904223)%4294967296
    return ai.seed/4294967296
end
function AI.init(boat, lane, seed)
    local ai = {lane=lane,seed=seed,skill=1,going=false,firstTurn=true,planMark=0,refined=false,effLane=lane,makuri=0,k=1,dodge=0,wob=0,stuck=0}
    ai.skill = 0.985+0.03*rand(ai)
    ai.stTarget = math.max(0.02,0.16+(rand(ai)-0.4)*0.17)
    ai.sashi = lane > 0 and rand(ai) < 0.4
    boat.ai = ai
end
local function countInside(b, boats, markZ)
    local n = 0
    for _,other in ipairs(boats) do
        if other ~= b and math.abs(other.x-b.x)<7 and distance(other.x-b.x,other.z-b.z)<28 and math.abs(other.z-markZ)<math.abs(b.z-markZ) then n=n+1 end
    end
    return n
end
local function makePlan(b, mark, boats)
    local ai=b.ai
    local sign=mark==1 and 1 or -1
    local mx,mz=mark==1 and 150 or -150,mark==1 and 8 or 0
    local u0,v0=(b.x-mx)*sign,(b.z-mz)*sign
    local maxV=(mark==1 and 79-mz or mz+79)-5
    local n=countInside(b,boats,mz)
    local approach,close,exit
    if ai.firstTurn and mark==1 then
        n=math.max(n,ai.refined and 0 or ai.effLane)
        approach=8+3.4*ai.effLane
        if ai.sashi then close=3.8+math.min(n,2)+rand(ai); exit=12+2*n+rand(ai)*4
        else close=3.8+1.7*n+rand(ai); exit=14+2.4*n+rand(ai)*4 end
    else
        approach=clamp(math.max(v0,6),11+1.5*n,20+2*n)+(rand(ai)-0.5)*3
        close=3.8+2*n+rand(ai)*1.2
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
    for i=0,14 do local th=pi*i/14; push(ux+rho*math.sin(th),center+rho*math.cos(th)) end
    local vEnd=center-rho
    for u=ux-5,-175,-5 do push(u,lerp(vEnd,-math.max(exit,-vEnd),smooth((ux-u)/60))) end
    ai.plan={xs=xs,zs=zs,ux=ux,sign=sign,mx=mx,vArc=math.sqrt(11.6*ai.skill*(b.gripSet or 1)*rho)}
    ai.planMark=mark
    local best=math.huge
    for i=1,#xs do
        local d=(xs[i]-b.x)^2+(zs[i]-b.z)^2
        if d<best then best=d; ai.k=i end
    end
end
local function timeToCover(distanceLeft, velocity)
    local t,d=0,0
    while d<distanceLeft and t<30 do
        velocity=velocity+(7.08-0.08*velocity-0.01014*velocity*velocity)*0.02
        d=d+velocity*0.02
        t=t+0.02
    end
    return t-(d-distanceLeft)/math.max(velocity,0.1)
end
function AI.update(b, boats, clock, dt)
    local ai=b.ai
    ai.wob=ai.wob+dt
    if not b.started then
        local heading=clamp((b.laneZ-b.z)*0.05,-0.2,0.2)
        local steer=clamp(-(heading-b.h)*3,-1,1)
        local remain=-clock+ai.stTarget-0.15
        local vf=b.vx*math.cos(b.h)+b.vz*math.sin(b.h)
        local arrival=timeToCover(math.max(-b.x,0),math.max(vf,0))
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
            if other~=b and not other.flying and other.started and other.z<b.z then inner[#inner+1]=other end
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
    if b.checkpoint==0 or b.checkpoint==3 then
        for _,other in ipairs(boats) do
            if other~=b then
                local rx,rz=other.x-b.x,other.z-b.z
                local ahead,side=rx*ch+rz*sh,-rx*sh+rz*ch
                if ahead>0.5 and ahead<12 and math.abs(side)<3.2 and b.speed>other.speed-1 then dodge=side>0 and -3.2 or 3.2 end
            end
        end
    end
    ai.dodge=ai.dodge+clamp(dodge-ai.dodge,-7*dt,7*dt)
    tx,tz=clamp(tx-sh*ai.dodge,-270,270),clamp(tz+ch*ai.dodge,-75,75)
    local dx,dz=tx-b.x,tz-b.z
    local dist=math.max(distance(dx,dz),0.001)
    local err=wrap(math.atan2(dz,dx)-b.h)
    local noise=math.sin(ai.wob*2.3+ai.lane)*0.03*(1.15-ai.skill*0.6)
    local steer=clamp(-(err+noise)*3.2,-1,1)
    local curvature=2*math.sin(math.min(math.abs(err),pi/2))/dist
    local targetSpeed=math.max(9.5,math.sqrt(11.6*ai.skill*(b.gripF or 1)*(b.gripSet or 1)/math.max(curvature,0.0001)))
    local throttle=clamp(0.55+(targetSpeed-b.speed)*0.45,0.1,1)
    local dTurn=plan.ux-uNow
    if dTurn>0 and dTurn<60 then
        local entry=plan.vArc*1.16
        if ai.firstTurn and ai.sashi then entry=entry*0.93 end
        if b.speed*b.speed-entry*entry>2*6.2*dTurn then throttle=0.05 end
    end
    for _,other in ipairs(boats) do
        if other~=b then
            local rx,rz=other.x-b.x,other.z-b.z
            local ahead,side=rx*ch+rz*sh,-rx*sh+rz*ch
            if ahead>0.3 and ahead<6 and math.abs(side)<3.2 then throttle=math.min(throttle,0.25+0.1*ahead) end
        end
    end
    if b.speed<1.5 then ai.stuck=ai.stuck+dt; if ai.stuck>1.2 then throttle=1 end else ai.stuck=0 end
    return throttle,steer
end
return AI
