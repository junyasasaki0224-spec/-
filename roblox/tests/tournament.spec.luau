-- T17 ③: 大会の決まり(作る5項目、参加、組分け、予選の得点、優勝戦の顔ぶれ、優勝)
local R=require("../src/TournamentRules")

-- 作る時の5項目
local good={name="  週末みなと杯  ",size=12,format="heats2",start=15,private=true}
local clean=assert(R.validate(good))
assert(clean.name=="週末みなと杯","name is trimmed")
assert(R.validate({name=string.rep("あ",20),size=6,format="single",start=0,private=false}),"20 characters allowed")
assert(not R.validate({name=string.rep("あ",21),size=6,format="single",start=0,private=false}),"21 characters rejected")
assert(not R.validate({name="",size=6,format="single",start=0,private=false}),"empty name rejected")
assert(not R.validate({name=string.rep("a",100000),size=6,format="single",start=0,private=false}),"huge name rejected early")
assert(not R.validate({name="a\n",size=7,format="single",start=0,private=false}),"size must be 6/12/18/24")
assert(not R.validate({name="a",size=6,format="x",start=0,private=false}),"unknown format")
assert(not R.validate({name="a",size=6,format="single",start=10,private=false}),"start must be 0/5/15/30")
assert(not R.validate({name="a",size=6,format="single",start=0,private="yes"}),"private must be boolean")
assert(not R.validate(nil))
local code=R.newCode(function(n) return n end)
assert(#code==6 and code=="999999","code uses the safe alphabet")

-- 合言葉の大会: 主催者が最初の参加者。コードが合う人だけ、満員まで
local t=R.new("t1",1,"主催",clean,1000,"ABCDEF")
assert(t.status=="open" and #t.entrants==1 and t.startAt==1000+15*60)
assert(not R.join(t,2,"B","WRONG1",1001),"wrong code")
assert(R.join(t,2,"B","ABCDEF",1001))
assert(not R.join(t,2,"B","ABCDEF",1002),"no double entry")
for id=3,12 do assert(R.join(t,id,"P"..id,"ABCDEF",1002)) end
assert(not R.join(t,13,"P13","ABCDEF",1003),"full")
assert(not R.leave(t,1),"host cannot leave")
assert(R.leave(t,12) and #t.entrants==11)
assert(not R.shouldStart(t,1100),"not full and not time yet")
assert(R.shouldStart(t,1000+15*60),"start time reached (AI fills)")
t.startNow=true
assert(R.shouldStart(t,1100),"host started early")

-- 組分け: 11人 → 6人と5人
local groups=R.makeGroups(t)
assert(#groups==2 and #groups[1].members==6 and #groups[2].members==5)
t.status="running"
assert(not R.join(t,20,"late","ABCDEF",1200),"closed after start")

-- 予選の得点(10・8・6・4・2・1、失格0)。同じ走りを二度足さない
assert(R.addHeat(t,1,1,{{userId=1,place=1},{userId=3,place=2},{userId=5,place=4},{userId=7,place=6,out="F"}}))
assert(not R.addHeat(t,1,1,{{userId=1,place=1}}),"same heat is not added twice")
assert(t.points["1"]==10 and t.points["3"]==8 and t.points["5"]==4 and t.points["7"]==0)
assert(t.history["7"][1]=="F")
assert(R.addHeat(t,1,2,{{userId=1,place=3},{userId=3,place=1}}))
assert(not R.allHeatsDone(t),"group 2 still racing")
assert(R.addHeat(t,2,1,{{userId=2,place=1},{userId=4,place=2}}))
assert(R.addHeat(t,2,2,{{userId=2,place=1},{userId=4,place=5}}))
assert(R.allHeatsDone(t))
-- 1: 16点(best1) 3: 18点 2: 20点 4: 10点(best2) 5: 4点 → 上位6人
local finals=R.finalists(t)
assert(#finals==6 and finals[1]==2 and finals[2]==3 and finals[3]==1 and finals[4]==4 and finals[5]==5)
assert(R.needsFinal(t))
-- 優勝戦: いちばん良い着の人間が優勝(AI がその上でも人間の中で決める)
t.status="final"
local champion=R.finish(t,{{userId=3,place=2},{userId=2,place=3},{userId=1,place=1,out="沈"}},2000)
assert(champion.userId==3 and t.status=="done" and t.champion.name=="P3")

-- 1レース勝負で6人以下: 優勝戦なし、得点の1位が優勝
local s=R.new("t2",10,"H",{name="一発",size=6,format="single",start=0,private=false},0)
assert(R.join(s,11,"B",nil,1))
assert(not R.shouldStart(s,5),"waits until full when start=0")
R.makeGroups(s)
assert(R.heatsPerGroup(s)==1 and not R.needsFinal(s))
assert(R.addHeat(s,1,1,{{userId=11,place=1},{userId=10,place=2}}))
assert(R.allHeatsDone(s))
assert(R.finish(s,nil,10).userId==11,"single race winner")
-- 1レース勝負で7人以上は優勝戦あり
local big=R.new("t3",1,"H",{name="大",size=12,format="single",start=0,private=false},0)
for id=2,7 do R.join(big,id,"P"..id,nil,0) end
assert(R.needsFinal(big))

-- 受付のまま2時間で中止
assert(R.expired({status="open",created=0},R.OPEN_LIFETIME) and not R.expired({status="open",created=0},10))

-- 画面に送る形: 会場の鍵は出さない。合言葉は参加者だけ
t.groups[1].access,t.groups[1].privateId,t.finalAccess="secret","pid","secret2"
local outsider=R.view(t,99)
local insider=R.view(t,2)
assert(outsider.code==nil and insider.code=="ABCDEF")
local function noSecrets(v)
    for k,x in pairs(v) do
        assert(k~="access" and k~="privateId" and k~="finalAccess" and k~="finalPrivateId" and x~="secret" and x~="secret2","no server credentials in view")
        if type(x)=="table" then noSecrets(x) end
    end
end
noSecrets(outsider);noSecrets(insider)
assert(#insider.standings==11 and insider.standings[1].name=="B")
print("tournament checks passed")
