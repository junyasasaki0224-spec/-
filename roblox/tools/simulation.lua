local wins={0,0,0,0,0,0}
local startSums,startCounts={0,0,0,0,0,0},{0,0,0,0,0,0}
local racerSums,racerCounts={0,0,0,0,0,0},{0,0,0,0,0,0}
local finishes,flights=0,0
local contacts=0
local dt=1/120
for race=1,NUM_RACES do
    local boats={}
    local wave=((race*7)%16)/10
    local wind=((race*13)%41)/10
    local angle=((race*47)%360)*math.pi/180
    local racers=createRoster(race)
    for i=1,6 do
        local lane=i-1
        local x=lane<3 and -106-lane*4 or -182-(lane-3)*5
        local b={x=x,z=11+lane*5.5,h=0,vx=0,vz=0,w=0,throttle=0,steer=0,lap=0,checkpoint=0,speed=0,started=false,flying=false,
            windX=math.cos(angle)*wind,windZ=math.sin(angle)*wind,gripSet=1-wave*0.006,gripF=1,thrustF=1,inWake=0,trail={},trailTimer=0,motor=racers[i].motor}
        b.laneZ=b.z
        AI.init(b,lane,1000+race*37+i*7919,racers[i].racer)
        boats[i]=b
    end
    local clock=-14
    local firstTime=nil
    local count=0
    for step=1,120*254 do
        clock=clock+dt
        for i,b in ipairs(boats) do
            local oldX,oldZ=b.x,b.z
            local throttle,steer=0,0
            if not b.flying and not b.finished then throttle,steer=AI.update(b,boats,clock,dt) end
            physics(b,throttle,steer,dt)
            collision.obstacles(b)
            b.speed=math.sqrt(b.vx*b.vx+b.vz*b.vz)
            b.trailTimer=b.trailTimer+dt
            if b.trailTimer>=0.06 then
                b.trailTimer=b.trailTimer-0.06
                b.trail[#b.trail+1]={x=b.x-math.cos(b.h)*2,z=b.z-math.sin(b.h)*2,time=clock}
                while #b.trail>0 and clock-b.trail[1].time>2.6 do table.remove(b.trail,1) end
            end
            if not b.started and oldX<0 and b.x>=0 and b.z>4 then
                b.started=true
                local fraction=(0-oldX)/math.max(b.x-oldX,0.000001)
                local startTime=clock-dt*(1-fraction)
                b.flying=startTime<0
                startSums[i]=startSums[i]+startTime
                startCounts[i]=startCounts[i]+1
                local racerId=racers[i].racer.id
                racerSums[racerId]=racerSums[racerId]+startTime
                racerCounts[racerId]=racerCounts[racerId]+1
                if b.flying then flights=flights+1 end
            end
            if b.x< -274 or b.x>274 then b.x=math.clamp(b.x,-274,274); b.vx=b.vx*-0.25 end
            if b.z< -79 or b.z>79 then b.z=math.clamp(b.z,-79,79); b.vz=b.vz*-0.25 end
            if b.checkpoint==0 and oldX<150 and b.x>=150 and b.z>8 then b.checkpoint=1 end
            if b.checkpoint==1 and oldZ>8 and b.z<=8 and b.x>150 then b.checkpoint=2 end
            if b.checkpoint==2 and oldX>150 and b.x<=150 and b.z<8 then b.checkpoint=3 end
            if b.checkpoint==3 and oldX> -150 and b.x<= -150 and b.z<0 then b.checkpoint=4 end
            if b.checkpoint==4 and oldZ<0 and b.z>=0 and b.x< -150 then b.checkpoint=5 end
            if b.checkpoint==5 and oldX< -150 and b.x>= -150 and b.z>0 then b.checkpoint=0; b.lap=b.lap+1 end
            if not b.finished and not b.flying and b.lap>=3 and oldX<0 and b.x>=0 and b.z>4 then
                b.finished=true; count=count+1; finishes=finishes+1
                if not firstTime then wins[i]=wins[i]+1; firstTime=clock end
            end
        end
        for i=1,5 do
            for j=i+1,6 do
                local impulse=collision.boats(boats[i],boats[j])
                if impulse and impulse>0.35 then contacts=contacts+1 end
            end
        end
        for _,b in ipairs(boats) do
            b.x=math.clamp(b.x,-274,274); b.z=math.clamp(b.z,-79,79)
            b.speed=math.sqrt(b.vx*b.vx+b.vz*b.vz)
            local wake=0
            for _,other in ipairs(boats) do
                if other~=b then
                    for index=#other.trail,1,-2 do
                        local point=other.trail[index]
                        local age=clock-point.time
                        local radius=1.1+age*0.45
                        if age>=0.25 and (point.x-b.x)^2+(point.z-b.z)^2<radius*radius then wake=1; break end
                    end
                end
                if wake==1 then break end
            end
            b.inWake=b.inWake+math.clamp(wake-b.inWake,-4*dt,6*dt)
            b.gripF=1-0.22*b.inWake
            b.thrustF=1-0.05*b.inWake
        end
        if count==6 or (firstTime and clock-firstTime>45) then break end
    end
    for i,b in ipairs(boats) do
        if not b.finished then print("unfinished",race,i,b.checkpoint,math.floor(b.x),math.floor(b.z),b.flying) end
    end
end
print(string.format("Races: %d",NUM_RACES))
for i=1,6 do
    local mean = startCounts[i]>0 and startSums[i]/startCounts[i] or 0
    print(string.format("Lane %d: %d wins (%.1f%%), mean ST %.3f",i,wins[i],wins[i]*100/NUM_RACES,mean))
end
print(string.format("Finished: %d/%d; flying: %d",finishes,NUM_RACES*6,flights))
print(string.format("Strong contacts per race: %.2f",contacts/NUM_RACES))
for i=1,6 do
    if racerCounts[i]>0 then print(string.format("Racer %d mean ST: %.3f",i,racerSums[i]/racerCounts[i])) end
end
