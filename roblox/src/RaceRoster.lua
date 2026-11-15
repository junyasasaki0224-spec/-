-- Fictional competitors and medium difficulty from src/sim/roster.js.
-- 級別(cls)と得意(style)はブラウザ版の ROSTER と同じ。出走表に出すために、ロビーと会場の両方で使う
local roster = {
    {id=1,name="青波 隼人",st=0.13,skill=1.03,sashi=0.3,cls="A1",style="逃げ"},
    {id=2,name="水城 拓海",st=0.15,skill=1.01,sashi=0.8,cls="A1",style="差し"},
    {id=3,name="潮見 蓮",st=0.14,skill=0.99,sashi=0.15,cls="A2",style="まくり"},
    {id=4,name="汐崎 航",st=0.16,skill=0.985,sashi=0.55,cls="A2",style="まくり差し"},
    {id=5,name="風間 颯太",st=0.18,skill=0.965,sashi=0.7,cls="B1",style="差し"},
    {id=6,name="帆足 大河",st=0.17,skill=0.955,sashi=0.2,cls="B1",style="まくり"},
}

-- 番号(レースの番号、またはフリーレースの種)から、6艇の選手とモーターを決める。
-- rate はモーター2連率(%)。motor はその出力(中級の値 -0.02 を含む)
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
        result[i]={racer=roster[shuffled[i]],motor=0.985+(rate-30)/18*0.03-0.02,rate=rate}
    end
    return result
end

-- 同じ番号から水面(風の強さ m/s・風向き・波)を決める(会場の reset と同じ式)
local function weather(raceNumber)
    local wave = ((raceNumber*7)%16)/10
    local wind = ((raceNumber*13)%41)/10
    local windAngle = ((raceNumber*47)%360)*math.pi/180
    return wind, windAngle, wave
end

return setmetatable({create=create, weather=weather, roster=roster}, {__call=function(_, n) return create(n) end})
