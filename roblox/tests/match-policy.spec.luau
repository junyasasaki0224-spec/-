local policy=require("../src/MatchPolicy")
local function candidate(rating,session) return {rating=rating,session=session} end
-- 同じ顔ぶれで、時刻を進めながら行列を更新する(25秒以内に更新しないと消えるので、20秒ごとに)
local function run(state,from,to,entries,id,mode)
    for now=from,to,20 do state=policy.update(state,now,entries,{},id,mode) end
    return policy.update(state,to,entries,{},id,mode)
end
local six={}
for n=1,6 do six[tostring(n)]=candidate(1500,"s"..n) end
local state=policy.update(nil,100,six,{},"group-a")
for n=1,6 do assert(state.players[tostring(n)].match=="group-a","six players match atomically") end
local after=policy.update(state,101,six,{},"group-b")
for n=1,6 do assert(after.players[tostring(n)].match=="group-a","already matched cannot be matched again") end
assert(policy.accept(state,101,1,"server-a")==nil,"no server assigned yet")
local assigned=policy.assign(state,"group-a","access-a","server-a")
for n=1,6 do assert(assigned.players[tostring(n)].access=="access-a" and assigned.players[tostring(n)].privateId=="server-a","whole group gets the reserved server") end
assert(policy.assign(assigned,"group-a","access-b","server-b")==nil,"a group is assigned only once")
assert(policy.accept(assigned,101,1,"server-b")==nil,"wrong server rejected")
local consumed=policy.accept(assigned,101,1,"server-a")
assert(consumed and consumed.players["1"].used,"participant accepted")
assert(policy.accept(consumed,101,1,"server-a")==nil,"ticket cannot be replayed")
assert(policy.accept(assigned,220,1,"server-a")==nil,"expired match rejected")
assert(policy.expected(assigned,"server-a")==6 and policy.expected(assigned,"server-b")==0,"venue knows how many are coming")
local released=policy.release(state,"group-a",102)
for n=1,6 do assert(not released.players[tostring(n)].match and released.players[tostring(n)].joined==100,"failed reservation returns players to the queue with their wait time") end
local stale=policy.update(state,100+policy.ASSIGN_TTL,{},{},"unused")
assert(stale.players["1"] and stale.players["1"].match=="unused","group without a server is released after the grace period and may be regrouped")
local kept=policy.update(assigned,100+policy.ASSIGN_TTL,{},{},"unused")
assert(kept.players["1"].match=="group-a","assigned group is kept")

-- 1人だけ: 60秒まで待ってから AI で埋める
local solo={["1"]=candidate(1500,"s1")}
local single=run(nil,100,159,solo,"unused")
assert(not single.players["1"].match,"a lone racer waits up to 60 seconds")
local status=policy.status(single,1,159)
assert(status.count==1 and status.remaining==1,"lone racer sees 1/6 and the 60 second limit")
single=policy.update(single,160,solo,{},"solo")
assert(single.players["1"].match=="solo","solo starts with AI after 60 seconds")
assert(policy.status(single,1,160)==nil,"no waiting status once matched")
-- 組が決まったが会場の鍵が来ない時は、待ち直しになり、もう一度組み直せる
local staleSolo=policy.update(single,161+policy.ASSIGN_TTL,solo,{},"retry")
assert(staleSolo.players["1"].match=="retry","stale solo match is retried, not stuck")

-- 2人以上: 最初の人が30秒待った時点で出走(シーズンはレートの差が待ち時間に応じて広がる)
local two={["1"]=candidate(1500,"s1"),["2"]=candidate(1750,"s2")}
local pair=run(nil,100,129,two,"unused")
assert(not pair.players["1"].match,"wait until the 30 second deadline")
local seen=policy.status(pair,2,129)
assert(seen.count==2 and seen.remaining==1,"two compatible racers see 2/6 and the oldest racer's 30 seconds")
pair=policy.update(pair,130,two,{},"pair")
assert(pair.players["1"].match=="pair" and pair.players["2"].match=="pair","two humans start together, the rest is AI")
-- 遠すぎるレートの相手は組まない(1人ずつ60秒で AI と走る)
local far={["1"]=candidate(1500,"s1"),["2"]=candidate(2600,"s2")}
local tooFar=run(nil,100,159,far,"unused")
assert(not tooFar.players["1"].match and not tooFar.players["2"].match,"distant ratings do not form a pair at 30 seconds")
assert(policy.status(tooFar,1,159).count==1,"distant opponent is not counted")
tooFar=policy.update(tooFar,160,far,{},"first")
assert(tooFar.players["1"].match=="first" and not tooFar.players["2"].match,"distant opponent stays in queue")

-- 取り消し・切断・上限
local cancel=policy.update(nil,100,{["1"]=candidate(1500,"s1")},{},"unused")
cancel=policy.update(cancel,101,{}, {["1"]="wrong"},"unused")
assert(cancel.players["1"],"another session cannot cancel")
cancel=policy.update(cancel,102,{}, {["1"]="s1"},"unused")
assert(not cancel.players["1"],"owner can cancel")
local expired=policy.update(nil,100,{["1"]=candidate(1500,"s1")},{},"unused")
expired=policy.update(expired,126,{}, {},"unused")
assert(not expired.players["1"],"disconnected waiter expires")
local protected=policy.update(consumed,102,{}, {["1"]="s1"},"unused")
assert(protected.players["1"].used,"a consumed ticket cannot be canceled")
local many={}
for n=1,61 do many[tostring(n)]=candidate(1500,"s"..n) end
local capped=policy.update(nil,100,many,{},"one")
local count=0
for _ in pairs(capped.players) do count += 1 end
assert(count==60,"queue capacity is bounded")

-- オンライン・イベントはレートを見ない。5人なら30秒で出走(空き1つは AI)
for _,mode in ipairs({"online","event"}) do
    local entrants={}
    for i=1,5 do entrants[tostring(i)]=candidate(1000*i,mode..i) end
    local online=run(nil,0,29,entrants,"too-early",mode)
    for _,entry in pairs(online.players) do assert(not entry.match,mode.." waits 30 seconds") end
    assert(policy.status(online,5,29,mode).count==5,mode.." counts everyone regardless of rating")
    online=policy.update(online,30,entrants,{},"five",mode)
    for _,entry in pairs(online.players) do assert(entry.match=="five",mode.." starts five humans at 30 seconds") end
    local admitted=policy.assign(online,"five","key","venue")
    assert(not policy.accept(admitted,31,1,"other-venue"))
    assert(not policy.accept(admitted,31,7,"venue"))
    local once=assert(policy.accept(admitted,31,1,"venue"))
    assert(not policy.accept(once,31,1,"venue"))
end
-- 7人目は次の組へ回る
local seven={}
for i=1,7 do seven[tostring(i)]=candidate(1500,"o"..i) end
local crowd=policy.update(nil,0,seven,{},"g1","online")
local matched=0
for _,entry in pairs(crowd.players) do if entry.match=="g1" then matched+=1 end end
assert(matched==6 and policy.status(crowd,7,0,"online").count==1,"six race now, the seventh keeps waiting")
assert(policy.ready(6,0) and policy.ready(2,30) and not policy.ready(2,29) and policy.ready(1,60) and not policy.ready(1,59))
print("match policy checks passed")
