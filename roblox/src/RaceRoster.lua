-- Fictional competitors and medium difficulty from src/sim/roster.js.
local roster = {
    {id=1,name="青波 隼人",st=0.13,skill=1.03,sashi=0.3},
    {id=2,name="水城 拓海",st=0.15,skill=1.01,sashi=0.8},
    {id=3,name="潮見 蓮",st=0.14,skill=0.99,sashi=0.15},
    {id=4,name="汐崎 航",st=0.16,skill=0.985,sashi=0.55},
    {id=5,name="風間 颯太",st=0.18,skill=0.965,sashi=0.7},
    {id=6,name="帆足 大河",st=0.17,skill=0.955,sashi=0.2},
}

local function create(raceNumber)
    local seed = 1000 + raceNumber*19937
    local function random()
        seed = (1664525*seed+1013904223)%4294967296
        return seed/4294967296
    end
    local shuffled = {1,2,3,4,5,6}
    for i=6,2,-1 do
        local j=math.floor(random()*i)+1
        shuffled[i],shuffled[j]=shuffled[j],shuffled[i]
    end
    local result={}
    for i=1,6 do
        local rate=28+random()*20
        result[i]={racer=roster[shuffled[i]],motor=0.985+(rate-30)/18*0.03-0.02}
    end
    return result
end
return create
