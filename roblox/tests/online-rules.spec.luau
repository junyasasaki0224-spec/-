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

-- ランク戦の RATE(meta.rate): AI も含めた6艇の中の着順で +25/+15/+8/-10/-15/-20、失格 -25(人間の数は関係ない)
for p,d in ipairs({25,15,8,-10,-15,-20}) do assert(M.seasonDelta({place=p})==d and M.seasonDelta({place=p,humans=1,humanPlace=1})==d) end
assert(M.seasonDelta({place=6,out="沈",humans=4,humanPlace=4})==-25 and M.seasonDelta({place=3,out="F"})==-25)
-- 級は D3 から A1 の12段。S は別枠
assert(#M.GRADES==12 and M.GRADES[1].name=="D3" and M.GRADES[12].name=="A1" and M.grade(0)==1 and M.grade(99)==1 and M.grade(100)==2 and M.grade(1500)==12)
-- D3 の間は下がらない
local low=M.new();M.result(low,{mode="season",place=6,day="2026-11-15"})
assert(low.rate==0)
-- 昇級した後の5レースは、その級のいちばん下より下がらない(6レース目からは下がる)
local g=M.new();g.rate=95
M.result(g,{mode="season",place=1,day="2026-11-15"})
assert(g.rate==120 and M.grade(g.rate)==2 and g.guard==5 and table.find(g.badges,"D2"))
for _=1,5 do M.result(g,{mode="season",place=6,day="2026-11-15"}) end
assert(g.rate==100 and g.guard==0)
M.result(g,{mode="season",place=6,day="2026-11-15"})
assert(g.rate==80 and M.grade(g.rate)==1)

-- 保存の通し: 1人 + AI 5艇のランク戦で1着 → RATE も動く(AI に勝てば上がる)
local p={meta=M.new()}
local solo=Rules.rankHumans({{userId=1,place=1,st=.1,mode="season",day="2026-11-15"}})[1]
local saved=Rules.apply(p,solo,"race-1",changes({{rating=1500,place=1}})[1])
assert(saved.meta.rate==25 and saved.meta.coins==60 and saved.meta.seasonRaces==1 and saved.rating==1500)
-- 内部レート: AI(1500)も相手に数える。1人で AI 5艇に勝つと +16
assert(changes({{rating=1500,place=1},{rating=1500,place=2},{rating=1500,place=3},{rating=1500,place=4},{rating=1500,place=5},{rating=1500,place=6}})[1]==16)
-- 2人 + AI のランク戦: 全体で2着と5着(5着の人は D3 なので下がらない)
local a,b=table.unpack(Rules.rankHumans({{userId=1,place=2,mode="season",day="2026-11-15"},{userId=2,place=5,mode="season",day="2026-11-15"}}))
local elo=changes({{rating=1500,place=a.place},{rating=1500,place=b.place}})
local savedA=Rules.apply({meta=M.new()},a,"race-2",elo[1])
local savedB=Rules.apply({meta=M.new()},b,"race-2",elo[2])
assert(savedA.meta.rate==15 and savedB.meta.rate==0 and savedA.rating==1516 and savedB.rating==1484)

-- S: A1 で、今シーズンのランキングの線(上位200人目の RATE)以上。初めての時は称号・S のバッジ・コイン
local s=M.new();M.daily(s,"2026-11-20");s.rate=1520;s.seasonRaces=3
assert(not M.updateS(s,1600) and not M.isS(s) and M.gradeName(s)=="A1")
assert(M.updateS(s,1500) and M.isS(s) and M.gradeName(s)=="S" and table.find(s.titles,"Sランカー") and table.find(s.badges,"S") and s.mail[1].coins==1000)
assert(not M.updateS(s,1500),"S rewards only once")
-- 線がわからない時(会場のサーバー)は S の印を変えない。A1 から落ちたら S ではない(バッジと称号は残る)
M.updateS(s,nil);assert(M.isS(s))
s.rate=1450;M.updateS(s,0)
assert(not M.isS(s) and table.find(s.badges,"S") and table.find(s.titles,"Sランカー"))
-- シーズンが変わると: 前のシーズンの最高ランクを記録し、コインをメールで渡し、RATE は半分から
local q=M.new();M.daily(q,"2026-11-20");q.rate=1000;q.peak=1200;q.seasonRaces=4;q.seasonWins=1
M.daily(q,"2026-12-01")
assert(q.season=="2026-12" and q.rate==500 and q.peak==500 and q.seasonRaces==0 and q.history[1].season=="2026-11" and q.history[1].grade=="A3")
local seasonMail=false
for _,v in ipairs(q.mail) do if v.title=="2026-11 シーズンの結果" and v.coins==300 then seasonMail=true end end
assert(seasonMail)
-- ランク戦を走っていないシーズンは記録もコインもない
local idle=M.new();M.daily(idle,"2026-11-20");local mails=#idle.mail
M.daily(idle,"2026-12-01")
assert(#idle.history==0 and #idle.mail==mails+1,"only the login bonus")
-- イベント: コイン2倍、レートは動かない
local ev=Rules.apply({meta=M.new()},{userId=1,place=1,mode="race",event=true,humans=1,humanPlace=1,day="2026-11-15"},"race-3",0)
assert(ev.meta.coins==120 and ev.meta.rate==0,"event doubles coins")
print("online rules checks passed")
