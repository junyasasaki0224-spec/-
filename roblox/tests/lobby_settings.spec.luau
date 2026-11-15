local Meta=require("../src/Meta")
local Step=require("../src/RaceStep")
local m=Meta.normalize({coins=300})
assert(m.quality=="auto" and m.volume==80 and m.lever==40)
for _,arg in {"volume=0","lever=140","quality=medium"} do Meta.action(m,"settings",arg) end
for _,arg in {"volume=105","lever=15","quality=nil","coins=99999","volume=nan"} do Meta.action(m,"settings",arg) end
assert(m.volume==0 and m.lever==140 and m.quality=="medium" and m.coins==300)
local function trial(start,lane)
    local boat=Step.soloBoat(lane,2)
    for tick=1,22*120 do
        local t=tick/120-14
        Step.advance(boat,t>=start and 1 or 0,0,t,Step.DT)
        if boat.started then return boat.startTime,boat.out end
    end
end
local early,cause=trial(-14,0)
assert(early<0 and cause=="F")
local ontime,out=trial(-14-early+.35,0)
assert(ontime>=0 and ontime<1 and not out, tostring(ontime))
assert(trial(12,5)==nil)
print("Settings ranges, older profiles and three practice outcomes OK")
