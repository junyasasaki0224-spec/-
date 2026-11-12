-- Shared motion model for server simulation and client-side presentation.
local function smooth(a, b, x)
    local t = math.clamp((x-a)/(b-a),0,1)
    return t*t*(3-2*t)
end

local function step(b, throttle, steer, dt)
    b.throttle += math.clamp(throttle-b.throttle,-5*dt,3.2*dt)
    b.steer += math.clamp(steer-b.steer,-5*dt,5*dt)
    local ch,sh = math.cos(b.h),math.sin(b.h)
    local vf,vl = b.vx*ch+b.vz*sh,-b.vx*sh+b.vz*ch
    local sp = math.abs(vf)
    local hull = smooth(0.5,6,sp)
    local auth = hull*(1-0.24*math.min(1,sp/22.6))+0.3*b.throttle*(1-hull)
    local yaw = -b.steer*1.6*auth*(0.75+0.25*(b.gripF or 1)) + 1.3*vl/math.max(sp,4)*hull
    b.w += (yaw-b.w)*(1-math.exp(-7*dt))
    b.h += b.w*dt
    ch,sh = math.cos(b.h),math.sin(b.h)
    vf,vl = b.vx*ch+b.vz*sh,-b.vx*sh+b.vz*ch
    local mix = (b.accF or 1)+((b.topF or 1)-(b.accF or 1))*smooth(0.4,0.975,math.min(1.2,sp/22.6))
    local direction = vf>=0 and 1 or -1
    local hump = 2.4*(1-smooth(0.15,0.5,b.throttle))*smooth(1.5,4.5,sp)*(1-smooth(9,13,sp))
    local af = b.throttle*7*(b.motor or 1)*(b.thrustF or 1)*mix+0.08-0.08*vf-0.01014*vf*math.abs(vf)-direction*(0.3*math.abs(vl)+hump)
    af += 0.045*((b.windX or 0)*ch+(b.windZ or 0)*sh)*smooth(2,10,sp)
    vf += af*dt
    local grip = 13.5*(b.gripF or 1)*(b.gripSet or 1)
    vl -= math.clamp(9*vl,-grip,grip)*dt
    b.vx,b.vz = vf*ch-vl*sh,vf*sh+vl*ch
    b.x,b.z = b.x+b.vx*dt,b.z+b.vz*dt
end

return step
