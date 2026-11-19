-- Catalog values match src/meta.js. Rules below are service-independent.
local Meta = {["ITEMS"]={{["id"]="s0",["name"]="スタンダード",["r"]="N",["hull"]=15921902,["trim"]=13114922,["deck"]=15329764,["cowl"]=13114922,["kind"]="skin"},
    {["id"]="s1",["name"]="マリンブルー",["r"]="N",["hull"]=15921902,["trim"]=1790164,["deck"]=14674162,["cowl"]=1790164,["kind"]="skin"},
    {["id"]="s2",["name"]="フォレスト",["r"]="N",["hull"]=15790054,["trim"]=1605692,["deck"]=15133919,["cowl"]=1605692,["kind"]="skin"},
    {["id"]="s3",["name"]="サンセット",["r"]="N",["hull"]=16773596,["trim"]=15759890,["deck"]=16769725,["cowl"]=15759890,["kind"]="skin"},
    {["id"]="s4",["name"]="グラファイト",["r"]="R",["hull"]=3817287,["trim"]=14278114,["deck"]=2764340,["cowl"]=9278620,["kind"]="skin"},
    {["id"]="s5",["name"]="チェリーレッド",["r"]="R",["hull"]=12983083,["trim"]=16777215,["deck"]=11015202,["cowl"]=1710622,["kind"]="skin"},
    {["id"]="s6",["name"]="ディープシー",["r"]="R",["hull"]=1063546,["trim"]=3786472,["deck"]=797790,["cowl"]=3786472,["kind"]="skin"},
    {["id"]="s7",["name"]="ライムフラッシュ",["r"]="R",["hull"]=1447964,["trim"]=11989562,["deck"]=2106153,["cowl"]=11989562,["kind"]="skin"},
    {["id"]="s8",["name"]="ミッドナイト",["r"]="SR",["hull"]=856096,["trim"]=9067775,["deck"]=1382963,["cowl"]=9067775,["kind"]="skin"},
    {["id"]="s9",["name"]="パールホワイト",["r"]="SR",["hull"]=16513781,["trim"]=14072176,["deck"]=15986658,["cowl"]=14072176,["kind"]="skin"},
    {["id"]="s10",["name"]="クリムゾンゴールド",["r"]="SR",["hull"]=7999260,["trim"]=16765500,["deck"]=6032149,["cowl"]=16765500,["kind"]="skin"},
    {["id"]="s11",["name"]="みなとゴールド",["r"]="SSR",["hull"]=14856762,["trim"]=16774340,["deck"]=13212194,["cowl"]=1708544,["kind"]="skin"},
    {["id"]="s12",["name"]="オーロラ",["r"]="SSR",["hull"]=1229488,["trim"]=16736168,["deck"]=954268,["cowl"]=6966527,["kind"]="skin"},
    {["id"]="h0",["name"]="オレンジ",["r"]="N",["base"]=16742938,["stripe"]=1052688,["kind"]="helmet"},
    {["id"]="h1",["name"]="ホワイト",["r"]="N",["base"]=16053490,["stripe"]=1986512,["kind"]="helmet"},
    {["id"]="h2",["name"]="ブラック",["r"]="N",["base"]=1447707,["stripe"]=15909376,["kind"]="helmet"},
    {["id"]="h3",["name"]="スカイ",["r"]="N",["base"]=3778792,["stripe"]=16777215,["kind"]="helmet"},
    {["id"]="h4",["name"]="ファイア",["r"]="R",["base"]=14229038,["stripe"]=16765500,["kind"]="helmet"},
    {["id"]="h5",["name"]="ミント",["r"]="R",["base"]=3528352,["stripe"]=735788,["kind"]="helmet"},
    {["id"]="h6",["name"]="バイオレット",["r"]="R",["base"]=6959016,["stripe"]=16777215,["kind"]="helmet"},
    {["id"]="h7",["name"]="カーボン",["r"]="SR",["base"]=2369324,["stripe"]=14694970,["kind"]="helmet"},
    {["id"]="h8",["name"]="シャンパン",["r"]="SR",["base"]=15326388,["stripe"]=9071132,["kind"]="helmet"},
    {["id"]="h9",["name"]="チャンピオン",["r"]="SSR",["base"]=16765500,["stripe"]=13114922,["kind"]="helmet"}},["MISSIONS"]={{["id"]="race1",["name"]="レースに1回出る",["goal"]=1,["coins"]=50},
    {["id"]="top3",["name"]="3着以内に入る",["goal"]=1,["coins"]=80},
    {["id"]="st20",["name"]="ST 0.20 以内でスタートする",["goal"]=1,["coins"]=80},
    {["id"]="race3",["name"]="レースに3回出る",["goal"]=3,["coins"]=120}},["GRADES"]={{["name"]="B2",["rate"]=0,["diff"]=0},{["name"]="B1",["rate"]=300,["diff"]=1},{["name"]="A2",["rate"]=800,["diff"]=2},{["name"]="A1",["rate"]=1500,["diff"]=3}},["RARITY"]={["N"]={["name"]="N",["rate"]=0.6,["dupe"]=15},["R"]={["name"]="R",["rate"]=0.28,["dupe"]=40},["SR"]={["name"]="SR",["rate"]=0.1,["dupe"]=120},["SSR"]={["name"]="SSR",["rate"]=0.02,["dupe"]=400}}}
-- Roblox 版だけの品: VIP パスの特典。ランダムではなく、ガチャには出ない(ガチャの確率は今までと同じ)。速さや強さは変わらない見た目だけ
for _,it in ipairs({
    {id="v1",name="VIPゴールド",r="SSR",hull=1710618,trim=15911244,deck=1118481,cowl=15911244,kind="skin",shop=true,vip=true},
    {id="v2",name="VIPゴールド",r="SSR",base=15911244,stripe=1710618,kind="helmet",shop=true,vip=true},
}) do table.insert(Meta.ITEMS,it) end
local function clone(v)
    if type(v)~="table" then return v end
    local out={}
    for k,x in pairs(v) do out[k]=clone(x) end
    return out
end
Meta.clone=clone
-- ランク戦は1日(日本時間)5回まで。VIP パスがあれば無制限
Meta.RANKED_DAILY=5
-- 今日あと何回ランク戦に出られるか。VIP は nil(無制限)
function Meta.rankedLeft(m,day)
    if m.vip==true then return nil end
    local used=(m.rankDay==day and type(m.rankCount)=="number") and m.rankCount or 0
    return math.max(0,Meta.RANKED_DAILY-used)
end
-- ガチャの1つあたりの確率(表示と抽選は同じ Meta.RARITY と品の数から計算する)
function Meta.pool(rar)
    local pool={}
    for _,it in ipairs(Meta.ITEMS) do if it.r==rar and not it.shop then table.insert(pool,it) end end
    return pool
end
function Meta.item(id)
    for _,it in ipairs(Meta.ITEMS) do if it.id==id then return it end end
end
function Meta.grade(rate)
    local index=1
    for i,g in ipairs(Meta.GRADES) do if rate>=g.rate then index=i end end
    return index
end
function Meta.new()
    return {volume=80,lever=40,quality="auto",assist=true,shake=true,opening=true,visor=false,coins=0,own={"s0","h0"},skin="s0",helmet="h0",rate=0,peak=0,seasonRaces=0,
        seasonWins=0,xp=0,tier=0,ta={},day="",mis={},misDone={},pulls=0,mailSeq=1,
        mail={{id="welcome",title="ようこそ みなとグランプリへ",body="出走の記念に、ガチャ5回ぶんのコインを贈ります。",coins=500}}}
end
function Meta.normalize(v)
    local m=Meta.new()
    if type(v)=="table" then for k,x in pairs(v) do m[k]=clone(x) end end
    return m
end
function Meta.sendMail(m,title,body,coins)
    table.insert(m.mail,1,{id="m"..m.mailSeq,title=title,body=body,coins=coins})
    m.mailSeq+=1
    if #m.mail>30 then table.remove(m.mail) end
end
function Meta.daily(m,day)
    day=day or m.day
    if day=="" or m.day>=day then return end
    m.day,m.mis,m.misDone=day,{},{}
    Meta.sendMail(m,"ログインボーナス",day.." の出走ボーナスです。",100)
end
function Meta.action(m,action,arg,rnd)
    if action=="settings" and type(arg)=="string" then
        local key,value=arg:match("^(%a+)=(%w+)$")
        local n=tonumber(value)
        if key=="volume" and n and n>=0 and n<=100 and n%5==0 then m.volume=n
        elseif key=="lever" and n and n>=0 and n<=140 and n%10==0 then m.lever=n
        elseif key=="quality" and ({auto=true,high=true,medium=true,low=true})[value] then m.quality=value
        elseif (key=="assist" or key=="shake" or key=="opening" or key=="visor") and (value=="on" or value=="off") then m[key]=value=="on"
        else return "設定を確認してください" end
        return "設定を保存しました"
    elseif action=="mail" then
        for i,v in ipairs(m.mail) do
            if v.id==arg then m.coins+=v.coins;table.remove(m.mail,i);return "受け取りました" end
        end
    elseif action=="mission" then
        for _,v in ipairs(Meta.MISSIONS) do
            if v.id==arg and not m.misDone[arg] and (m.mis[arg] or 0)>=v.goal then
                m.misDone[arg]=true;m.coins+=v.coins;return "受け取りました"
            end
        end
    elseif action=="equip" then
        local it=Meta.item(arg)
        if it and table.find(m.own,arg) then
            m[it.kind=="skin" and "skin" or "helmet"]=arg
            return it.name.."を装備しました"
        end
    elseif action=="pull" and (arg==1 or arg==10) then
        local cost=arg==10 and 900 or 100
        if m.coins<cost then return "コインが足りません" end
        m.coins-=cost
        local results={}
        for _=1,arg do
            local x,rar=rnd(),"N"
            for _,r in ipairs({"SSR","SR","R","N"}) do
                if x<Meta.RARITY[r].rate then rar=r;break end
                x-=Meta.RARITY[r].rate
            end
            -- VIP の品はガチャに出さない
            local pool=Meta.pool(rar)
            local it=pool[math.min(#pool,math.floor(rnd()*#pool)+1)]
            local dupe=0
            if table.find(m.own,it.id) then dupe=Meta.RARITY[rar].dupe;m.coins+=dupe
            else table.insert(m.own,it.id) end
            m.pulls+=1;table.insert(results,{id=it.id,dupe=dupe})
        end
        return results
    end
    return "受け取れる報酬・持ち物を選んでください"
end
-- 日替わりイベント(src/meta.js の EVENTS と同じ)。wind は m/s、wave は cm、windDir はラジアン
Meta.EVENTS={
    {id="night-gale",name="ナイター強風戦",desc="夜・向かい風7mの荒れた水面",env="night",weather={wind=7,windDir=math.pi,wave=7}},
    {id="outside",name="大外まくり指令",desc="6コースから勝負。薄暮・追い風",env="evening",lane=5,weather={wind=4,windDir=0,wave=3}},
    {id="glass",name="無風スピード戦",desc="無風・波なし。タイムが出る水面",env="day",weather={wind=0,windDir=0,wave=0}},
    {id="rough",name="荒水面サバイバル",desc="横風6m・波高8cm。沈没に注意",env="evening",weather={wind=6,windDir=math.pi/2,wave=8}},
    {id="inside",name="イン逃げ指令",desc="1コースを守り切れ。達人が相手",env="night",lane=0,weather={wind=2,windDir=math.pi,wave=2}},
}
-- 日付(日本時間の "YYYY-MM-DD")からその日のイベントを選ぶ(ブラウザ版の eventOf と同じ計算)
function Meta.eventOf(day)
    local h=0
    for i=1,#day do h=(h*31+string.byte(day,i))%4294967296 end
    return Meta.EVENTS[h%#Meta.EVENTS+1]
end
-- 日本時間の今日の日付
function Meta.today(now)
    return os.date("!%Y-%m-%d",(now or os.time())+9*3600)
end
-- シーズンのレートの増減。オンライン(人間の数 humans がある時)は人間どうしの着順だけで決める:
-- 人間が1人なら動かない。2人以上なら、人間の中の順位を1〜6着の表に広げて当てはめる(AI に勝っても負けても変わらない)
local SEASON_DELTA={30,20,10,0,-10,-15}
function Meta.seasonDelta(r)
    if type(r.humans)=="number" then
        if r.humans<2 then return 0 end
        if r.out then return -20 end
        local p=math.clamp(r.humanPlace or r.humans,1,r.humans)
        return SEASON_DELTA[math.floor(1+(p-1)*5/(r.humans-1)+0.5)]
    end
    if r.out then return -20 end
    return SEASON_DELTA[math.clamp(r.place or 6,1,6)]
end
function Meta.result(m,r)
    if r.mode=="practice" then return end
    local pi=math.clamp(r.place or 6,1,6)
    local coins,xp
    if r.mode=="ta" then
        coins=(r.out or not r.time) and 5 or 20
        xp=r.out and 5 or 12
        local lane=tostring(r.lane or 0)
        if not r.out and r.time and r.time>0 and (not m.ta[lane] or r.time<m.ta[lane]) then m.ta[lane]=r.time;coins+=30 end
    else
        coins=r.out and 5 or ({60,40,30,20,15,15})[pi]
        xp=r.out and 6 or ({30,24,20,16,12,12})[pi]
        if r.event then coins*=2 end
        if r.mode=="season" then
            -- 今日のランク戦の回数(出走した時点で1回。日本時間の日付ごと)
            local day=r.day or m.day
            if m.rankDay~=day then m.rankDay,m.rankCount=day,0 end
            m.rankCount=(type(m.rankCount)=="number" and m.rankCount or 0)+1
            local before=Meta.grade(m.rate)
            m.rate=math.max(0,m.rate+Meta.seasonDelta(r))
            m.peak=math.max(m.peak,m.rate);m.seasonRaces+=1
            if not r.out and pi==1 then m.seasonWins+=1 end
            local after=Meta.grade(m.rate)
            if after>before then Meta.sendMail(m,Meta.GRADES[after].name.." 級に昇級","昇級おめでとうございます。記念のコインです。",200*(after-1)) end
        end
        for _,id in ipairs({"race1","race3"}) do m.mis[id]=(m.mis[id] or 0)+1 end
        if not r.out and pi<=3 then m.mis.top3=(m.mis.top3 or 0)+1 end
        if not r.out and r.st and r.st>=0 and r.st<=.2 then m.mis.st20=(m.mis.st20 or 0)+1 end
    end
    m.coins+=coins;m.xp+=xp
    while m.xp>=(m.tier+1)*100 do
        m.tier+=1
        Meta.sendMail(m,"シーズンパス "..m.tier.."段 到達","ごほうびのコインです。",m.tier%5==0 and 300 or 100)
    end
end
-- Robux の購入(コインの袋・VIP パス)で品とコインを渡す。purchaseId ごとに1回だけ
-- (ProcessReceipt は同じ購入が何度も届くことがあるため)。戻り値: "granted" / "already"
function Meta.grantPurchase(m,purchaseId,ids,coins)
    if type(m.receipts)~="table" then m.receipts={} end
    if table.find(m.receipts,purchaseId) then return "already" end
    if type(coins)=="number" and coins>0 and coins<=100000 then m.coins+=math.floor(coins) end
    for _,id in ipairs(ids) do
        local it=Meta.item(id)
        if it and it.shop and not table.find(m.own,id) then table.insert(m.own,id) end
    end
    if string.sub(purchaseId,1,5)=="pass:" then m.vip=true end
    table.insert(m.receipts,purchaseId)
    -- 古い記録は消す(パスの記録は残す)
    while #m.receipts>200 do
        local removed=false
        for i,r in ipairs(m.receipts) do
            if string.sub(r,1,5)~="pass:" then table.remove(m.receipts,i);removed=true;break end
        end
        if not removed then break end
    end
    return "granted"
end
-- VIP の毎日のボーナス(1日1回、メールで届く)
function Meta.vipDaily(m,day,coins)
    if m.vip~=true or type(day)~="string" or m.vipDay==day then return false end
    m.vipDay=day
    Meta.sendMail(m,"VIP の毎日のボーナス",day.." の VIP ボーナスです。",coins)
    return true
end
function Meta.transact(value,token,action,arg,day,randoms,nextToken)
    local data=clone(value or {})
    data.meta=Meta.normalize(data.meta)
    local m=data.meta
    if token~=m.token then return data end
    Meta.daily(m,day)
    local n=0
    m.last=Meta.action(m,action,arg,function() n+=1;return randoms[n] end)
    m.token=nextToken
    return data
end
return Meta
