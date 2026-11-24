local M=require("../src/Meta")
local Rules=require("../src/ResultRules")
-- スタンダード5品(s0・h0・c0・w0・f0)+ VIP の2品 + ガチャの着せ替え150品(5種類×30)
assert(#M.ITEMS==157 and #M.MISSIONS==4)
local m=M.new()
M.daily(m,"2026-11-15")
assert(#m.mail==2)
M.daily(m,"2026-11-15")
M.daily(m,"2026-11-14")
assert(#m.mail==2 and m.day=="2026-11-15")
M.action(m,"mail","welcome")
M.action(m,"mail","welcome")
assert(m.coins==500)
m.token="a"
local data={meta=m}
local first=M.transact(data,"a","pull","1","2026-11-15",{0,.01},"b")
local replay=M.transact(first,"a","pull","1","2026-11-15",{.9,.9},"c")
assert(first.meta.pulls==1 and replay.meta.pulls==1 and replay.meta.token=="b")
assert(data.meta.pulls==0 and first.meta.coins==400)
-- 乱数 0 は UR、2つ目の乱数で UR の15点(5種類×3点)から1点目(hull28)
assert(first.meta.last[1].id=="hull28")
local dupe=M.transact(first,"b","pull","1","2026-11-15",{0,0},"c")
assert(dupe.meta.coins==1300 and dupe.meta.last[1].dupe==1000)
local before=m.coins
M.action(m,"pull","0")
M.action(m,"pull",10)
M.action(m,"pull","skin:1")
assert(m.coins==before and m.pulls==0)
assert(M.pullArg("10")==10 and M.pullArg("1")==1 and not M.pullArg("5") and not M.pullArg(1) and not M.pullArg("helmet:10"))
assert(not M.item("forged"))
-- 持っていない品は装備できない。スタンダードはいつでも装備できる
M.action(m,"equip","hull05")
assert(m.skin=="s0")
M.action(m,"equip","c0")
assert(m.cowl=="c0")
-- 乱数 .99 は N(N は 50%)。N 40点(5種類×8点)の40点目 = flag08。初めの1つ以外はかぶり(N は 10 コイン)
m.coins=900
local rolls=M.action(m,"pull","10",function() return .99 end)
assert(#rolls==10 and m.pulls==10 and m.coins==90 and rolls[1].id=="flag08" and rolls[2].dupe==10)
-- 5種類がまとめて1つのガチャ: 乱数を変えると、ちがう種類の品が出る
local h=M.new();h.coins=900
local seq,n={.3,0,.3,.026,.3,.051,.3,.076,.3,.101},0
local kinds={}
for _,v in ipairs(M.action(h,"pull","10",function() n=n%#seq+1;return seq[n] end)) do kinds[M.item(v.id).kind]=true end
assert(kinds.skin and kinds.helmet and kinds.cowl and kinds.wheel and kinds.flag)
-- 持っている品は装備できる(種類ごとの場所に入る)
local got=M.item(h.own[#h.own])
M.action(h,"equip",got.id)
assert(h[got.kind]==got.id)
local poor=M.new()
assert(type(M.action(poor,"pull","10"))=="string" and poor.pulls==0)
-- 今はない品(前の色だけのガチャの品)を装備していた記録は、スタンダードに戻す
local old=M.normalize({skin="s5",helmet="h9",own={"s0","h0","s5"}})
assert(old.skin=="s0" and old.helmet=="h0" and old.cowl=="c0" and old.wheel=="w0" and old.flag=="f0")
-- 持っていない品を装備した記録も、スタンダードに戻す(検証用の解放がオンの間だけはそのまま)
local borrowed=M.normalize({skin="hull28",flag="flag01",own={"s0","h0","flag01"}})
assert(borrowed.skin=="s0" and borrowed.flag=="flag01")
assert(M.normalize({skin="hull28",own={"s0","h0"},testUnlock=true}).skin=="hull28")
-- 持ち物の記録が壊れていても止まらない
assert(M.normalize({own="broken",skin="hull28"}).skin=="s0")
for i,coins in ipairs({60,40,30,20,15,15}) do
 local n=M.new();M.result(n,{mode="race",place=i,st=.2})
 assert(n.coins==coins and n.mis.race1==1 and n.mis.st20==1)
end
local n=M.new();n.rate=290;n.xp=90
M.result(n,{mode="season",place=1,st=.1})
assert(n.rate==320 and n.tier==1 and #n.mail==3 and n.mail[2].coins==200)
M.action(n,"mission","race1");M.action(n,"mission","race1")
assert(n.coins==110)
local p={meta=M.new()}
local r={mode="season",out="沈",place=6,day="2026-11-15"}
local a=Rules.apply(p,r,"race",0)
local b=Rules.apply(a,r,"race",0)
assert(a.meta.coins==5 and a.meta.xp==6 and b.meta.coins==5)
assert(p.meta.coins==0)
local t=M.new();M.result(t,{mode="ta",place=1,lane=0,time=100})
M.result(t,{mode="ta",place=1,lane=0,time=101})
assert(t.coins==70 and t.ta["0"]==100)
M.result(t,{mode="practice",place=1})
assert(t.coins==70)
-- ランク戦は1日5回まで(日付が変わると戻る。VIP は無制限)
local q=M.new()
assert(M.rankedLeft(q,"2026-11-15")==5)
for _=1,5 do M.result(q,{mode="season",place=3,day="2026-11-15"}) end
assert(M.rankedLeft(q,"2026-11-15")==0 and M.rankedLeft(q,"2026-11-16")==5)
M.result(q,{mode="race",place=1,day="2026-11-15"})
assert(q.rankCount==5)
M.result(q,{mode="season",place=1,day="2026-11-16"})
assert(M.rankedLeft(q,"2026-11-16")==4)
q.vip=true
assert(M.rankedLeft(q,"2026-11-16")==nil)
-- 購入: コインは購入番号ごとに1回だけ。VIP パスで品と VIP の印
local s=M.new()
assert(M.grantPurchase(s,"p:1",{},1100)=="granted" and s.coins==1100)
assert(M.grantPurchase(s,"p:1",{},1100)=="already" and s.coins==1100)
assert(M.grantPurchase(s,"p:2",{},-5)=="granted" and s.coins==1100)
assert(M.grantPurchase(s,"pass:9",{"v1","v2","s1"},1000)=="granted" and s.vip and s.coins==2100)
assert(table.find(s.own,"v1") and table.find(s.own,"v2") and not table.find(s.own,"s1"))
-- VIP の毎日のボーナスは1日1回、メールで届く(VIP でなければ届かない)
local mails=#s.mail
assert(M.vipDaily(s,"2026-11-15",100) and not M.vipDaily(s,"2026-11-15",100) and #s.mail==mails+1 and s.mail[1].coins==100)
assert(not M.vipDaily(M.new(),"2026-11-15",100))
-- ガチャに VIP の品・スタンダードは出ない。1つあたりの確率の元(品の数)。どの種類も 8/8/7/4/3、まとめて 40/40/35/20/15
for _,slot in ipairs(M.SLOTS) do
 assert(#M.pool("N",slot.kind)==8 and #M.pool("R",slot.kind)==8 and #M.pool("SR",slot.kind)==7 and #M.pool("SSR",slot.kind)==4 and #M.pool("UR",slot.kind)==3)
end
assert(#M.pool("N")==40 and #M.pool("R")==40 and #M.pool("SR")==35 and #M.pool("SSR")==20 and #M.pool("UR")==15)
-- 確率の合計は 100%(表示と抽選は同じ Meta.RARITY)
local sum=0
for _,r in ipairs(M.RARITIES) do sum+=M.RARITY[r].rate end
assert(math.abs(sum-1)<1e-9)
-- 色見本: 色だけの品はその色、着せ替えは模様の色
assert(M.swatch(M.item("s0"))==M.item("s0").hull and M.swatch(M.item("hull01"))==M.item("hull01").color)
print("meta catalog, rewards, transactions and retry checks passed")
