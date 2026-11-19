-- ロビーのフリーレース(1人用・AI 相手): 出走表で選んだ値を確かめて、自分だけの会場へ送る
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local config = require(script.Parent:WaitForChild("LobbyConfig"))
local live = game.GameId ~= 0 and type(config.racePlaceId) == "number" and config.racePlaceId > 0
local remote = Instance.new("RemoteFunction")
remote.Name = "MinatoFreeRace"
remote.Parent = ReplicatedStorage
local ENVS = { day = true, evening = true, night = true }
local last, moving = {}, {}

-- 整数で範囲の中か
local function int(v, lo, hi)
    return type(v) == "number" and v == v and v % 1 == 0 and v >= lo and v <= hi
end

remote.OnServerInvoke = function(player, cfg)
    if type(cfg) ~= "table" then
        return nil
    end
    local now = os.clock()
    if last[player] and now - last[player] < 1 then
        return { message = "少し待ってからもう一度押してください" }
    end
    last[player] = now
    -- スタート練習はコースだけを受け取る。フリーレースは出走表の値をすべて確かめる
    local practice = cfg.practice == true
    if practice then
        if not int(cfg.lane, 1, 6) then
            return { message = "コースを選び直してください" }
        end
    elseif not int(cfg.lane, 1, 6) or not int(cfg.tilt, 1, 4) or not int(cfg.diff, 1, 4) or not ENVS[cfg.env] or not int(cfg.seed, 1, 1000000) then
        return { message = "出走表を開き直してください" }
    end
    if not live then
        -- 検証用(Studio で、ロビーと会場をまとめた場所 dev.project.json): 移動せずに、この場所の中で走る
        local devStart = game:GetService("RunService"):IsStudio()
            and ReplicatedStorage:FindFirstChild("MinatoDevCombined")
            and game:GetService("ServerStorage"):FindFirstChild("MinatoDevRace")
        if devStart then
            local ok, started, message = pcall(devStart.Invoke, devStart, player, {
                practice = practice, lane = cfg.lane, tilt = cfg.tilt, diff = cfg.diff, env = cfg.env, seed = cfg.seed,
            })
            return { message = ok and message or "レースを始められませんでした", started = ok and started == true }
        end
        return { message = "Studio では会場へ移動しません（dev.project.json の検証用の場所なら、その場で走れます）" }
    end
    if moving[player] then
        return { message = "移動の準備をしています" }
    end
    moving[player] = true
    local ok, access = pcall(TeleportService.ReserveServerAsync, TeleportService, config.racePlaceId)
    if ok and type(access) == "string" then
        local options = Instance.new("TeleportOptions")
        options.ReservedServerAccessCode = access
        options:SetTeleportData(practice and { mode = "practice", lane = cfg.lane }
            or { mode = "single", lane = cfg.lane, tilt = cfg.tilt, diff = cfg.diff, env = cfg.env, seed = cfg.seed })
        ok = pcall(TeleportService.TeleportAsync, TeleportService, config.racePlaceId, { player }, options)
    end
    moving[player] = nil
    return { message = ok and "会場へ移動します" or "会場へ移動できませんでした。もう一度お試しください" }
end

Players.PlayerRemoving:Connect(function(player)
    last[player], moving[player] = nil, nil
end)
