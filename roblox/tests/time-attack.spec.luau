-- T17 ②: タイムアタックの記録の確かめ(入力の列から走りを再現して、同じタイムになるか)
local Step=require("../src/RaceStep")
local AI=require("../src/RaceAI")
local collision=require("../src/BoatCollision")
local M=require("../src/Meta")
local Rules=require("../src/ResultRules")

-- 会場のサーバーと同じやり方で1艇を走らせ、実際に使った入力(1000分の1)とチルトの変化を記録する
local function drive(lane, tiltChanges)
    local b=Step.soloBoat(lane,2)
    AI.init(b,lane,4242+lane,{skill=1,st=0.12,sashi=0},AI.DIFFS[2])
    local record={lane=lane,tilt=2,inputs={}}
    local last
    local elapsed=-14
    for n=0,math.floor(Step.SOLO_LIMIT/Step.DT) do
        if tiltChanges and tiltChanges[n] then Step.applyTilt(b,tiltChanges[n],0) end
        elapsed+=Step.DT
        local th,st=0,0
        if not b.finished and not b.flying then th,st=AI.update(b,{b},elapsed,Step.DT,collision.units) end
        local tq,sq=math.floor(Step.quantize(math.clamp(th,0,1))*1000+0.5),math.floor(Step.quantize(st)*1000+0.5)
        if not last or last[1]~=tq or last[2]~=sq or last[3]~=b.tilt then
            last={tq,sq,b.tilt}
            table.insert(record.inputs,{n,tq,sq,b.tilt})
        end
        local event=Step.advance(b,tq/1000,sq/1000,elapsed,Step.DT)
        if event then return record,b,event end
    end
    return record,b,nil
end

for lane=0,5 do
    local record,b,event=drive(lane)
    assert(event=="finish","lane "..lane.." solo run finishes ("..tostring(b.out)..")")
    local replayed=Step.replay(record)
    assert(replayed==b.finishTime,"lane "..lane.." replay gives exactly the same time")
    assert(b.finishTime>80 and b.finishTime<140,"plausible 3-lap time "..b.finishTime)
end

-- チルトをスタート前に変えても、記録から同じ走りになる
local record,b,ev=drive(2,{[120]=3,[400]=1})
assert(ev=="finish" and b.finishTime,"run with tilt changes finishes ("..tostring(b.out)..")")
assert(Step.replay(record)==b.finishTime,"tilt changes before the start are replayed")

-- 記録を書き換えると同じタイムにならない(登録されない)
local tampered=table.clone(record)
tampered.inputs=table.clone(record.inputs)
-- タイムは1/120秒きざみなので、はっきり違う操作に書き換える(途中の2秒間ハンドルを切り続ける)
local k=#tampered.inputs//2
local from=tampered.inputs[k][1]
table.insert(tampered.inputs,k+1,{from,1000,-1000,tampered.inputs[k][4]})
for i=k+2,#tampered.inputs do
    if tampered.inputs[i][1]<from+240 then tampered.inputs[i]={tampered.inputs[i][1],1000,-1000,tampered.inputs[i][4]} end
end
local t=Step.replay(tampered)
assert(t==nil or math.abs(t-b.finishTime)>0.001,"edited inputs change the result")

-- おかしな記録は受け付けない
assert(Step.replay(nil)==nil)
assert(Step.replay({lane=6,tilt=2,inputs={}})==nil,"lane out of range")
assert(Step.replay({lane=0,tilt=9,inputs={}})==nil,"tilt out of range")
assert(Step.replay({lane=0,tilt=2,inputs={{0,"x",0}}})==nil,"non-number input")
assert(Step.replay({lane=0,tilt=2,inputs={{0,0,0,7}}})==nil,"bad tilt change")
local _,why=Step.replay({lane=0,tilt=2,inputs={}})
assert(why=="ゴールしていません","no throttle never finishes")
-- 大時計より早く全開で出るとフライング
local _,flying=Step.replay({lane=0,tilt=2,inputs={{0,1000,0}}})
assert(flying=="フライング","full throttle from -14s is a flying start")
assert(Step.quantize(0.12345)==0.123 and Step.quantize(-2)==-1 and Step.quantize(0.9996)==1)

-- 成績: タイムアタックは出走数・1着・ベストタイムに入れず、コースの自己ベストとコインだけ
local saved=Rules.apply({meta=M.new()},{userId=1,mode="ta",lane=2,place=1,won=true,time=101.25,day="2026-11-15"},"ta-1",0)
assert(saved.races==0 and saved.wins==0 and saved.bestTime==nil and saved.rating==1500)
assert(saved.meta.ta["2"]==101.25 and saved.meta.coins==50,"course best and coins")
local again=Rules.apply(saved,{userId=1,mode="ta",lane=2,place=1,won=true,time=101.25,day="2026-11-15"},"ta-1",0)
assert(again.meta.coins==50,"same run is applied once")
print("time attack checks passed")
