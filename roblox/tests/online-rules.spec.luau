-- T17: オンライン対戦の決まり(AI 入りのレース、イベント、人間どうしのレート)
local M=require("../src/Meta")
local Rules=require("../src/ResultRules")
local changes=require("../src/Rating")

-- 日替わりイベントはブラウザ版の eventOf と同じ物を選ぶ(node で src/meta.js から求めた答え)
for day,id in pairs({["2026-11-15"]="outside",["2026-11-16"]="glass",["2026-12-01"]="glass",["2027-01-01"]="outside",["2026-02-28"]="night-gale"}) do
    assert(M.eventOf(day).id==id,"event of "..day)
end
assert(#M.EVENTS==5 and M.today(0)=="1970-01-01" and M.today(15*3600)=="1970-01-02","JST day key")

-- 人間の中の順位: 全体の着順に並んだ結果に、人数と順位を付ける
local rows=Rules.rankHumans({{userId=1,place=2},{userId=2,place=5},{userId=3,place=6,out="F"}})
assert(rows[1].humans==3 and rows[1].humanPlace==1 and rows[2].humanPlace==2 and rows[3].humanPlace==3)

-- シーズンのレート(meta.rate): 人間が1人なら AI に勝っても負けても動かない
assert(M.seasonDelta({place=1,humans=1,humanPlace=1})==0,"lone human beats AI: no change")
assert(M.seasonDelta({place=6,humans=1,humanPlace=1})==0,"lone human loses to AI: no change")
assert(M.seasonDelta({place=6,out="F",humans=1,humanPlace=1})==0,"lone human flying: no change")
-- 2人: 上の人が1着ぶん、下の人が6着ぶん(AI の着順は関係ない)
assert(M.seasonDelta({place=5,humans=2,humanPlace=1})==30 and M.seasonDelta({place=6,humans=2,humanPlace=2})==-15)
-- 3人: 1・4(3.5を四捨五入)・6着ぶん
assert(M.seasonDelta({place=2,humans=3,humanPlace=1})==30 and M.seasonDelta({place=3,humans=3,humanPlace=2})==0
    and M.seasonDelta({place=4,humans=3,humanPlace=3})==-15)
-- 6人(AI なし)は今までどおり
for p,d in ipairs({30,20,10,0,-10,-15}) do assert(M.seasonDelta({place=p,humans=6,humanPlace=p})==d) end
assert(M.seasonDelta({place=6,out="沈",humans=4,humanPlace=4})==-20,"disqualified human loses 20")
-- ブラウザ版(人数なし)は今までどおり全体の着順
assert(M.seasonDelta({place=1})==30 and M.seasonDelta({place=6,out="F"})==-20)

-- 保存の通し: 1人 + AI 5艇のシーズン戦で1着 → コイン・経験値は入るがレートは動かない
local p={meta=M.new()}
local solo=Rules.rankHumans({{userId=1,place=1,st=.1,mode="season",day="2026-11-15"}})[1]
local saved=Rules.apply(p,solo,"race-1",changes({{rating=1500,place=1}})[1])
assert(saved.meta.rate==0 and saved.meta.coins==60 and saved.meta.seasonRaces==1 and saved.rating==1500)
-- 2人 + AI のシーズン戦: 人間の上位がレートを得る(全体では2着と5着)
local a,b=table.unpack(Rules.rankHumans({{userId=1,place=2,mode="season",day="2026-11-15"},{userId=2,place=5,mode="season",day="2026-11-15"}}))
local elo=changes({{rating=1500,place=a.place},{rating=1500,place=b.place}})
local savedA=Rules.apply({meta=M.new()},a,"race-2",elo[1])
local savedB=Rules.apply({meta=M.new()},b,"race-2",elo[2])
assert(savedA.meta.rate==30 and savedB.meta.rate==0 and savedA.rating==1516 and savedB.rating==1484)
-- イベント: コイン2倍、レートは動かない
local ev=Rules.apply({meta=M.new()},{userId=1,place=1,mode="race",event=true,humans=1,humanPlace=1,day="2026-11-15"},"race-3",0)
assert(ev.meta.coins==120 and ev.meta.rate==0,"event doubles coins")
print("online rules checks passed")
