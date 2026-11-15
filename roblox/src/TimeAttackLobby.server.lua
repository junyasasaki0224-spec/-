-- ロビーのタイムアタック: コースごとの世界ランキング・フレンドのランキングを見せ、1人用の会場へ送る。
-- クライアントから受け取るのは「操作の名前」と「コース(1〜6)」だけ。記録はレース会場のサーバーが確かめて書く。
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local config = require(script.Parent:WaitForChild("LobbyConfig"))
local live = game.GameId ~= 0 and type(config.racePlaceId) == "number" and config.racePlaceId > 0
local Store = game.GameId ~= 0 and require(script.Parent:WaitForChild("TimeTrialStore"))
local remote = Instance.new("RemoteFunction")
remote.Name = "MinatoTimeAttack"
remote.Parent = ReplicatedStorage
local last, friends, moving = {}, {}, {}

-- フレンドの一覧(最初に聞いた時だけ調べる。失敗したら空)
local function friendSet(player)
    if friends[player] then
        return friends[player]
    end
    local set = {}
    local ok, pages = pcall(Players.GetFriendsAsync, Players, player.UserId)
    while ok and pages do
        for _, item in ipairs(pages:GetCurrentPage()) do
            set[item.Id] = true
        end
        if pages.IsFinished then
            break
        end
        ok = pcall(pages.AdvanceToNextPageAsync, pages)
    end
    friends[player] = set
    return set
end

-- コースのランキングを画面用にまとめる(上位100件、自分の順位、世界1位、フレンド1位)
local function board(player, lane)
    if not Store then
        return { offline = true }
    end
    local rows = Store.top(lane - 1)
    if not rows then
        return { failed = true }
    end
    local set = friendSet(player)
    local list, mine, friendTop = {}, nil, nil
    for index, row in ipairs(rows) do
        local me, friend = row.userId == player.UserId, set[row.userId] == true
        local rank = Store.rankOf(rows, row.ms) or index
        table.insert(list, { rank = rank, name = row.name, ms = row.ms, me = me, friend = friend })
        if me then
            mine = { rank = rank, ms = row.ms }
        end
        if friend and not friendTop then
            friendTop = { rank = rank, name = row.name, ms = row.ms }
        end
    end
    return { top = list, mine = mine, friendTop = friendTop, worldTop = list[1] }
end

remote.OnServerInvoke = function(player, action, lane)
    if action ~= "board" and action ~= "run" then
        return nil
    end
    if type(lane) ~= "number" or lane % 1 ~= 0 or lane < 1 or lane > 6 then
        return nil
    end
    local now = os.clock()
    if last[player] and now - last[player] < 0.8 then
        return { busy = true }
    end
    last[player] = now
    if action == "board" then
        return board(player, lane)
    end
    if not live then
        return { message = "Studio では会場へ移動しません（会場の place で MinatoTestMode=ta を使って確かめます）" }
    end
    if moving[player] then
        return { message = "移動の準備をしています" }
    end
    moving[player] = true
    -- 1人用の会場を予約して送る(コースはロビーのサーバーが決めた値だけを渡す)
    local ok, access = pcall(TeleportService.ReserveServerAsync, TeleportService, config.racePlaceId)
    if ok and type(access) == "string" then
        local options = Instance.new("TeleportOptions")
        options.ReservedServerAccessCode = access
        options:SetTeleportData({ mode = "ta", lane = lane })
        ok = pcall(TeleportService.TeleportAsync, TeleportService, config.racePlaceId, { player }, options)
    end
    moving[player] = nil
    if not ok then
        return { message = "会場へ移動できませんでした。もう一度お試しください" }
    end
    return { message = "会場へ移動します" }
end

Players.PlayerRemoving:Connect(function(player)
    last[player], friends[player], moving[player] = nil, nil, nil
end)
