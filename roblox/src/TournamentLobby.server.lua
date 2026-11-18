-- ロビーの大会(T17 ③): 一覧・作る・参加・やめる・開始を早める・中止・得点表・観戦。
-- クライアントから受け取るのは操作の名前と、大会の番号・5項目・合言葉だけ。参加や進行はサーバーが決める。
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local TextService = game:GetService("TextService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local config = require(script.Parent:WaitForChild("LobbyConfig"))
local Rules = require(script.Parent:WaitForChild("TournamentRules"))
local Store = require(script.Parent:WaitForChild("TournamentStore"))
local live = game.GameId ~= 0 and type(config.racePlaceId) == "number" and config.racePlaceId > 0
local remote = Instance.new("RemoteFunction")
remote.Name = "MinatoTournament"
remote.Parent = ReplicatedStorage
local notice = Instance.new("RemoteEvent")
notice.Name = "MinatoTournamentNotice"
notice.Parent = ReplicatedStorage
local random = Random.new()
local last, sent, told = {}, {}, {}

-- 画面に出す名前(Studio では画面写真にアカウント名が写らないよう伏せる)
local function displayName(player)
    return RunService:IsStudio() and "テストレーサー" or player.DisplayName
end

-- 大会名を Roblox の文字フィルターに通す(全員に見せる文字として)。失敗したら nil
local function filterName(name, userId)
    local ok, result = pcall(function()
        local filtered = TextService:FilterStringAsync(name, userId, Enum.TextFilterContext.PublicChat)
        return filtered:GetNonChatStringForBroadcastAsync()
    end)
    if ok and type(result) == "string" then
        return result
    end
    -- 公開していない Studio ではフィルターが使えないことがあるので、その時だけそのまま使う
    return Store.localOnly and name or nil
end

-- 自分が主催している進行中の大会があるか(1人が同時に作れるのは1つまで)
local function hosting(userId)
    for _, record in ipairs(Store.list() or {}) do
        if record.host == userId and Rules.ACTIVE[record.status] then
            return true
        end
    end
    return false
end

-- 一覧をタブごとに分けて返す
local function listFor(player)
    local tabs = { open = {}, running = {}, done = {} }
    for _, record in ipairs(Store.list() or {}) do
        local view = Rules.view(record, player.UserId)
        if record.status == "open" or record.status == "starting" then
            table.insert(tabs.open, view)
        elseif record.status == "running" or record.status == "final" then
            table.insert(tabs.running, view)
        else
            table.insert(tabs.done, view)
        end
    end
    for _, list in pairs(tabs) do
        table.sort(list, function(a, b)
            return (a.startAt or math.huge) < (b.startAt or math.huge)
        end)
    end
    return tabs
end

-- 会場へ送る(大会の番号・段階・組だけを渡す。会場のサーバーが大会の記録で確かめる)
local function teleport(player, access, data)
    if not live or type(access) ~= "string" then
        return false
    end
    local options = Instance.new("TeleportOptions")
    options.ReservedServerAccessCode = access
    options:SetTeleportData(data)
    return pcall(TeleportService.TeleportAsync, TeleportService, config.racePlaceId, { player }, options)
end

local actions = {}

function actions.list(player)
    return { ok = true, tabs = listFor(player), canHost = not hosting(player.UserId) }
end

function actions.create(player, params)
    local clean, err = Rules.validate(params)
    if not clean then
        return { ok = false, message = err }
    end
    if hosting(player.UserId) then
        return { ok = false, message = "主催できる大会は1つまでです" }
    end
    local name = filterName(clean.name, player.UserId)
    if not name then
        return { ok = false, message = "大会名を確かめられませんでした。別の名前にしてください" }
    end
    clean.name = name
    local id = HttpService:GenerateGUID(false)
    local code = clean.private and Rules.newCode(function(n)
        return random:NextInteger(1, n)
    end) or nil
    local record = Rules.new(id, player.UserId, displayName(player), clean, os.time(), code)
    local saved = Store.update(id, function(old)
        if old ~= nil then
            return nil
        end
        return record
    end)
    if not saved then
        return { ok = false, message = "大会を作れませんでした。もう一度お試しください" }
    end
    return { ok = true, message = "大会を開催しました", view = Rules.view(saved, player.UserId) }
end

-- 参加・やめる・開始を早める・中止は、同じやり方で記録を書き換える
local function change(player, id, fn)
    local reason = nil
    local saved = Store.update(id, function(old)
        if type(old) ~= "table" then
            reason = "大会が見つかりません"
            return nil
        end
        local ok, why = fn(old)
        if not ok then
            reason = why or "できませんでした"
            return nil
        end
        return old
    end)
    if not saved then
        return { ok = false, message = reason or "通信を確かめられません。もう一度お試しください" }
    end
    return { ok = true, view = Rules.view(saved, player.UserId) }
end

function actions.join(player, arg)
    if type(arg) ~= "table" or type(arg.id) ~= "string" or (arg.code ~= nil and (type(arg.code) ~= "string" or #arg.code > 6)) then
        return nil
    end
    local code = arg.code and string.upper(arg.code) or nil
    local res = change(player, arg.id, function(record)
        return Rules.join(record, player.UserId, displayName(player), code, os.time())
    end)
    res.message = res.ok and "参加しました" or res.message
    return res
end

function actions.leave(player, id)
    local res = change(player, id, function(record)
        return Rules.leave(record, player.UserId), "やめられません"
    end)
    res.message = res.ok and "参加をやめました" or res.message
    return res
end

function actions.startNow(player, id)
    local res = change(player, id, function(record)
        if record.host ~= player.UserId or record.status ~= "open" then
            return false, "主催者だけが受付中に開始を早められます"
        end
        record.startNow = true
        return true
    end)
    res.message = res.ok and "まもなく開始します" or res.message
    return res
end

function actions.cancel(player, id)
    local res = change(player, id, function(record)
        if record.host ~= player.UserId or not Rules.ACTIVE[record.status] then
            return false, "主催者だけが中止できます"
        end
        record.status, record.canceledAt = "canceled", os.time()
        return true
    end)
    res.message = res.ok and "大会を中止しました" or res.message
    return res
end

function actions.board(player, id)
    local record = Store.get(id)
    if type(record) ~= "table" then
        return { ok = false, message = "大会が見つかりません" }
    end
    return { ok = true, view = Rules.view(record, player.UserId) }
end

-- 開催中の大会を観戦する(走っている組の会場へ、観戦する人として入る)
function actions.watch(player, id)
    local record = Store.get(id)
    if type(record) ~= "table" or (record.status ~= "running" and record.status ~= "final") then
        return { ok = false, message = "いま走っている組はありません" }
    end
    if record.private and not Rules.findEntrant(record, player.UserId) then
        return { ok = false, message = "合言葉の大会は参加者だけが観戦できます" }
    end
    if not live then
        return { ok = false, message = "Studio では会場へ移動しません" }
    end
    local access, data
    if record.status == "final" and record.finalAccess then
        access, data = record.finalAccess, { mode = "gp", tid = id, stage = "final", watch = true }
    else
        for k, g in ipairs(record.groups or {}) do
            if g.access and g.heatsDone < Rules.heatsPerGroup(record) then
                access, data = g.access, { mode = "gp", tid = id, stage = "heat", group = k, watch = true }
                break
            end
        end
    end
    if not access then
        return { ok = false, message = "いま走っている組はありません" }
    end
    if not teleport(player, access, data) then
        return { ok = false, message = "会場へ移動できませんでした" }
    end
    return { ok = true, message = "観戦の会場へ移動します" }
end

remote.OnServerInvoke = function(player, action, arg)
    local handler = type(action) == "string" and actions[action]
    if not handler then
        return nil
    end
    if action ~= "list" and action ~= "board" and action ~= "create" and action ~= "join" and type(arg) ~= "string" then
        return nil
    end
    -- 大会の番号などの文字は短い物だけ(長すぎる文字で保存先を読ませない)
    if type(arg) == "string" and #arg > 64 then
        return nil
    end
    -- 書き換える操作は0.6秒に1回まで(一覧と得点表を読むのは0.2秒に1回まで)
    local now = os.clock()
    local readOnly = action == "list" or action == "board"
    local key = readOnly and "read" or "write"
    last[player] = last[player] or {}
    if last[player][key] and now - last[player][key] < (readOnly and 0.2 or 0.6) then
        return { ok = false, busy = true, message = not readOnly and "少し待ってからもう一度押してください" or nil }
    end
    last[player][key] = now
    local ok, result = pcall(handler, player, arg)
    if not ok then
        warn("Minato tournament action failed: " .. tostring(result))
        return { ok = false, message = "できませんでした。もう一度お試しください" }
    end
    return result
end

-- 始める時刻になった大会の会場を予約する(先に印を付けたロビーだけが予約する)
local function startTournament(record)
    local now = os.time()
    local claimed = Store.update(record.id, function(old)
        if type(old) ~= "table" then
            return nil
        end
        local stale = old.status == "starting" and now - (old.claimedAt or 0) >= Rules.CLAIM_TIMEOUT
        if not (Rules.shouldStart(old, now) or stale) then
            return nil
        end
        old.status, old.claimedBy, old.claimedAt = "starting", game.JobId, now
        return old
    end)
    if not claimed then
        return
    end
    local groups = Rules.makeGroups(claimed)
    if live then
        for _, g in ipairs(groups) do
            local ok, access, privateId = pcall(TeleportService.ReserveServerAsync, TeleportService, config.racePlaceId)
            if not ok or type(access) ~= "string" or type(privateId) ~= "string" then
                -- 予約できなければ受付に戻して、次の見回りでやり直す
                Store.update(record.id, function(old)
                    if type(old) == "table" and old.status == "starting" and old.claimedBy == game.JobId then
                        old.status = "open"
                        return old
                    end
                    return nil
                end)
                return
            end
            g.access, g.privateId = access, privateId
        end
    end
    Store.update(record.id, function(old)
        if type(old) ~= "table" or old.status ~= "starting" or old.claimedBy ~= game.JobId then
            return nil
        end
        old.groups, old.points, old.history, old.best = claimed.groups, claimed.points, claimed.history, claimed.best
        old.status, old.runningAt = "running", now
        return old
    end)
end

-- このロビーにいる人へ一度だけ知らせる
local function tell(player, key, message)
    told[player] = told[player] or {}
    if told[player][key] then
        return
    end
    told[player][key] = true
    notice:FireClient(player, message)
end

-- 見回り(5秒ごと): 始める・会場へ送る・中止や優勝を知らせる・古い受付を中止する
local function patrol()
    local now = os.time()
    for _, record in ipairs(Store.list() or {}) do
        if Rules.expired(record, now) then
            Store.update(record.id, function(old)
                if type(old) ~= "table" or not Rules.expired(old, now) then
                    return nil
                end
                old.status, old.canceledAt = "canceled", now
                return old
            end)
        elseif Rules.shouldStart(record, now) or (record.status == "starting" and now - (record.claimedAt or 0) >= Rules.CLAIM_TIMEOUT) then
            startTournament(record)
        end
        for _, player in ipairs(Players:GetPlayers()) do
            local _, entrant = Rules.findEntrant(record, player.UserId)
            if record.status == "running" and entrant and record.groups then
                for k, g in ipairs(record.groups) do
                    if table.find(g.members, player.UserId) and g.heatsDone == 0 then
                        tell(player, record.id .. ":start", "大会「" .. record.name .. "」が始まりました。会場へ移動します")
                        sent[player] = sent[player] or {}
                        if not sent[player][record.id] then
                            sent[player][record.id] = true
                            if live then
                                teleport(player, g.access, { mode = "gp", tid = record.id, stage = "heat", group = k })
                            end
                        end
                    end
                end
            elseif record.status == "canceled" and entrant then
                tell(player, record.id .. ":cancel", "大会「" .. record.name .. "」は主催者により中止されました")
            elseif record.status == "done" and record.champion and now - (record.finishedAt or 0) < 600 then
                tell(player, record.id .. ":done", "大会「" .. record.name .. "」優勝 " .. record.champion.name)
            end
        end
    end
end

task.spawn(function()
    while true do
        task.wait(5)
        local ok, err = pcall(patrol)
        if not ok then
            warn("Minato tournament patrol failed: " .. tostring(err))
        end
    end
end)

Players.PlayerRemoving:Connect(function(player)
    last[player], sent[player], told[player] = nil, nil, nil
end)
