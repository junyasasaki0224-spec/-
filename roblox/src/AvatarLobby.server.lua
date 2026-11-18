-- ロビー: ホームの艇に、その人の Roblox のアバターをレーサーとして乗せるための人形を作って配る。
-- ReplicatedStorage.RacerAvatars に「Home<ユーザー ID>」の名前で置き、抜けたら消す(見た目は保存しない)。
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RacerAvatar = require(ReplicatedStorage:WaitForChild("RacerAvatar"))

local folder = Instance.new("Folder")
folder.Name = "RacerAvatars"
folder.Parent = ReplicatedStorage

-- 1人分の人形を作って置く(作れない時は何もしない。ホームは共通のレーサー人形のまま)
local function prepare(player)
	local model = RacerAvatar.build(player.UserId)
	if not model then
		return
	end
	if player.Parent ~= Players then
		model:Destroy()
		return
	end
	model.Name = "Home" .. player.UserId
	model.Parent = folder
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(prepare, player)
end)
for _, player in Players:GetPlayers() do
	task.spawn(prepare, player)
end
Players.PlayerRemoving:Connect(function(player)
	local old = folder:FindFirstChild("Home" .. player.UserId)
	if old then
		old:Destroy()
	end
end)
