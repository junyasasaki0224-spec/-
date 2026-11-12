local policy=require("../src/MatchPolicy")
local function candidate(rating,session) return {rating=rating,session=session} end
local six={}
for n=1,6 do six[tostring(n)]=candidate(1500,"s"..n) end
local state=policy.update(nil,100,six,{},"group-a")
for n=1,6 do assert(state.players[tostring(n)].match=="group-a","six players match atomically") end
local after=policy.update(state,101,six,{},"group-b")
for n=1,6 do assert(after.players[tostring(n)].match=="group-a","already matched cannot be matched again") end
assert(policy.accept(state,101,1,"wrong")==nil,"wrong server rejected")
local consumed=policy.accept(state,101,1,"group-a")
assert(consumed and consumed.players["1"].used,"participant accepted")
assert(policy.accept(consumed,101,1,"group-a")==nil,"ticket cannot be replayed")
assert(policy.accept(state,220,1,"group-a")==nil,"expired match rejected")
local single=policy.update(nil,100,{["1"]=candidate(1500,"s1")},{},"unused")
assert(not single.players["1"].match,"must wait initially")
single=policy.update(single,120,{["1"]=candidate(1500,"s1")},{},"unused")
single=policy.update(single,129,{["1"]=candidate(1500,"s1")},{},"unused")
assert(not single.players["1"].match,"must wait at least 30 seconds")
single=policy.update(single,130,{["1"]=candidate(1500,"s1")},{},"solo")
assert(single.players["1"].match=="solo","solo starts with AI after 30 seconds")
local pair=policy.update(nil,100,{["1"]=candidate(1500,"s1"),["2"]=candidate(1750,"s2")},{},"unused")
pair=policy.update(pair,120,{["1"]=candidate(1500,"s1"),["2"]=candidate(1750,"s2")},{},"unused")
assert(not pair.players["1"].match,"wait until race deadline")
pair=policy.update(pair,130,{["1"]=candidate(1500,"s1"),["2"]=candidate(1750,"s2")},{},"pair")
assert(pair.players["1"].match=="pair" and pair.players["2"].match=="pair","range expands after 20 seconds")
local cancel=policy.update(nil,100,{["1"]=candidate(1500,"s1")},{},"unused")
cancel=policy.update(cancel,101,{}, {["1"]="wrong"},"unused")
assert(cancel.players["1"],"another session cannot cancel")
cancel=policy.update(cancel,102,{}, {["1"]="s1"},"unused")
assert(not cancel.players["1"],"owner can cancel")
local expired=policy.update(nil,100,{["1"]=candidate(1500,"s1")},{},"unused")
expired=policy.update(expired,126,{}, {},"unused")
assert(not expired.players["1"],"disconnected waiter expires")
local tooFar=policy.update(nil,100,{["1"]=candidate(1500,"s1"),["2"]=candidate(2100,"s2")},{},"unused")
tooFar=policy.update(tooFar,120,{["1"]=candidate(1500,"s1"),["2"]=candidate(2100,"s2")},{},"unused")
tooFar=policy.update(tooFar,130,{["1"]=candidate(1500,"s1"),["2"]=candidate(2100,"s2")},{},"first")
assert(tooFar.players["1"].match=="first" and not tooFar.players["2"].match,"distant opponent stays in queue")
local protected=policy.update(consumed,102,{}, {["1"]="s1"},"unused")
assert(protected.players["1"].used,"a consumed ticket cannot be canceled")
local many={}
for n=1,61 do many[tostring(n)]=candidate(1500,"s"..n) end
local capped=policy.update(nil,100,many,{},"one")
local count=0
for _ in pairs(capped.players) do count += 1 end
assert(count==60,"queue capacity is bounded")
print("match policy checks passed")
