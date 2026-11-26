-- ロビーの出走受付(シーズン / オンライン / イベント)。待ち行列は MatchQueue、決まりは MatchPolicy。
-- クライアントから受け取るのは「どのモードに並ぶか」と「取り消し」だけ。レートや人数はサーバーが決める。
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local config = require(script.Parent:WaitForChild("LobbyConfig"))
local queue = require(script.Parent:WaitForChild("MatchQueue"))
local policy = require(script.Parent:WaitForChild("MatchPolicy"))
local live = game.GameId ~= 0 and type(config.racePlaceId) == "number" and config.racePlaceId > 0
local Stats = live and require(script.Parent:WaitForChild("PlayerStats"))
local Meta = require(ReplicatedStorage:WaitForChild("Meta"))
local MetaService = require(script.Parent:WaitForChild("MetaService"))
-- 公開していない Studio では会場へ移動できないので、組が決まるところまでを確かめられるようにする
local rehearsal = queue.localOnly
local remote = Instance.new("RemoteEvent")
remote.Name = "MinatoRankedLobby"
remote.Parent = ReplicatedStorage
local MODES = { "ranked", "online", "event" }
local ACTIONS = { join = "ranked", online = "online", event = "event" }
local active, last, loading = {}, {}, {}
local cancellations = { ranked = {}, online = {}, event = {} }

-- ランク戦は1日 Meta.RANKED_DAILY 回まで(VIP 会員なら無制限)。もう出られなければ true
-- 会員かどうかは、ShopService が Roblox に確かめて付けた MinatoVip を先に使う(まだ確かめていなければ保存の印)
local function rankedUsedUp(player, meta)
    local m = Meta.normalize(meta)
    local live = player:GetAttribute("MinatoVip")
    if type(live) == "boolean" then
        m.vip = live
    end
    local left = Meta.rankedLeft(m, Meta.today())
    return left ~= nil and left <= 0
end
local USED_UP = "今日のランク戦は" .. Meta.RANKED_DAILY .. "回走りました。日本時間0時にまた走れます(VIP 会員なら無制限)"

-- 待機をやめる(行列からは次の更新で消える)
local function cancel(player, notify)
    local entry = active[player]
    if entry then
        cancellations[entry.mode][tostring(player.UserId)] = entry.session
        active[player] = nil
    end
    if notify and player.Parent == Players then
        remote:FireClient(player, "待機を終了しました", false)
    end
end

remote.OnServerEvent:Connect(function(player, action)
    if action ~= "cancel" and not ACTIONS[action] then
        return
    end
    if action == "cancel" then
        if (active[player] and not active[player].teleporting) or loading[player] then
            loading[player] = nil
            cancel(player, true)
        end
        return
    end
    if last[player] and os.clock() - last[player] < 2 then
        return
    end
    last[player] = os.clock()
    if active[player] or loading[player] then
        return
    end
    if not live and not rehearsal then
        remote:FireClient(player, "レース会場は準備中です", false)
        return
    end
    local mode = ACTIONS[action]
    local token = HttpService:GenerateGUID(false)
    if mode ~= "ranked" or not Stats then
        -- Studio の試しのランク戦も、今日の回数を確かめる(試しの成績は保存しない)
        if mode == "ranked" then
            local ok, meta = pcall(MetaService.get, player.UserId)
            if not ok or not meta then
                remote:FireClient(player, "成績を取得できません。もう一度お試しください", false)
                return
            end
            if rankedUsedUp(player, meta) then
                remote:FireClient(player, USED_UP, false)
                return
            end
        end
        -- オンライン・イベントはレートで相手を選ばない。Studio の試しではレート1500として扱う
        active[player] = { session = token, rating = 1500, mode = mode }
        remote:FireClient(player, "参加者を集めています", true, mode, 1, policy.SOLO_WAIT)
        return
    end
    loading[player] = token
    remote:FireClient(player, "成績を確認しています", true, mode)
    task.spawn(function()
        local profile = Stats.load(player.UserId)
        if loading[player] ~= token then
            return
        end
        loading[player] = nil
        if player.Parent ~= Players then
            return
        end
        if not profile then
            remote:FireClient(player, "成績を取得できません。もう一度お試しください", false)
            return
        end
        if rankedUsedUp(player, profile.meta) then
            remote:FireClient(player, USED_UP, false)
            return
        end
        active[player] = { session = token, rating = profile.rating, mode = mode }
        remote:FireClient(player, "近いレートの選手を探しています", true, mode, 1, policy.SOLO_WAIT)
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    local entry = active[player]
    if entry and not entry.teleporting then
        cancel(player, false)
    end
    active[player] = nil
    last[player] = nil
    loading[player] = nil
end)

TeleportService.TeleportInitFailed:Connect(function(player, _, _, _, options)
    local data = options and options:GetTeleportData()
    if
        type(data) == "table"
        and policy.MODES[data.mode]
        and active[player]
        and active[player].session == data.session
    then
        cancel(player, false)
        if player.Parent == Players then
            remote:FireClient(player, "移動できませんでした。もう一度お試しください", false)
        end
    end
end)

-- 組が決まった人を会場へ送る(Studio の試しでは、決まった内容を知らせて待機を終える)
local function send(player, entry, record, mode, humans)
    entry.teleporting = true
    if rehearsal then
        active[player] = nil
        remote:FireClient(
            player,
            string.format("出走が決まりました（人 %d・AI %d）。Studio では会場へ移動しません", humans, 6 - humans),
            false,
            mode
        )
        return
    end
    remote:FireClient(player, "出走が決まりました。会場へ移動します", true, mode, humans, 0)
    task.spawn(function()
        local options = Instance.new("TeleportOptions")
        options.ReservedServerAccessCode = record.access
        options:SetTeleportData({ mode = mode, session = entry.session })
        local ok = pcall(TeleportService.TeleportAsync, TeleportService, config.racePlaceId, { player }, options)
        if not ok and active[player] == entry then
            cancel(player, false)
            if player.Parent == Players then
                remote:FireClient(player, "移動できませんでした。もう一度お試しください", false)
            end
        end
    end)
end

-- 1つのモードの待ち行列を1回ぶん進め、待っている人に人数と残り秒数を知らせる
local function poll(mode)
    local entries = {}
    for player, entry in pairs(active) do
        if entry.mode == mode and player.Parent == Players and not entry.teleporting then
            entries[tostring(player.UserId)] = { session = entry.session, rating = entry.rating }
        end
    end
    if not next(entries) and not next(cancellations[mode]) then
        return
    end
    local pending = cancellations[mode]
    cancellations[mode] = {}
    local state, matchId = queue.update(entries, pending, mode)
    if not state then
        for id, token in pairs(pending) do
            cancellations[mode][id] = token
        end
        for player, entry in pairs(active) do
            if entry.mode == mode then
                remote:FireClient(player, "通信を確認しています", true, mode)
            end
        end
        return
    end
    -- この呼び出しで組が決まった場合は、このロビーが会場を1つ予約して、組の全員に鍵を配る
    local humans = 0
    for _, record in pairs(state.players) do
        if record.match == matchId and not record.access then
            humans += 1
        end
    end
    if humans > 0 and not rehearsal then
        local ok, access, privateId =
            pcall(TeleportService.ReserveServerAsync, TeleportService, config.racePlaceId)
        if
            ok
            and type(access) == "string"
            and type(privateId) == "string"
            and privateId ~= ""
            and queue.assign(matchId, access, privateId, mode)
        then
            for _, record in pairs(state.players) do
                if record.match == matchId then
                    record.access, record.privateId = access, privateId
                end
            end
        else
            queue.release(matchId, mode)
            for _, record in pairs(state.players) do
                if record.match == matchId then
                    record.match = nil
                end
            end
        end
    end
    local now = os.time()
    for player, entry in pairs(active) do
        local id = tostring(player.UserId)
        if entry.mode ~= mode or not entries[id] or entries[id].session ~= entry.session then
            continue
        end
        local record = state.players[id]
        if not record or record.session ~= entry.session then
            active[player] = nil
            remote:FireClient(player, "参加できません。少し待ってからお試しください", false)
        elseif record.match and (record.access or rehearsal) and not entry.teleporting then
            local group = 0
            for _, other in pairs(state.players) do
                if other.match == record.match then
                    group += 1
                end
            end
            send(player, entry, record, mode, group)
        elseif not record.match then
            local status = policy.status(state, id, now, mode)
            if status then
                remote:FireClient(player, "参加者を集めています", true, mode, status.count, status.remaining)
            end
        end
    end
    -- Studio の試しでは、決まった組を次の更新で行列から消す(会場に入る人がいないため)
    if rehearsal and humans > 0 then
        for id, record in pairs(state.players) do
            if record.match == matchId then
                cancellations[mode][id] = record.session
            end
        end
    end
end

for _, mode in ipairs(MODES) do
    task.spawn(function()
        while true do
            task.wait(3)
            poll(mode)
        end
    end)
end
