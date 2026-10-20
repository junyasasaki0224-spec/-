-- コインを生成して、触ったプレイヤーにポイントを加算するモジュール
local Players = game:GetService("Players")

local Coins = {}

local function randomPosition(radius: number): Vector3
	return Vector3.new(math.random(-radius, radius), 3, math.random(-radius, radius))
end

local function createCoin(config, folder: Folder)
	local coin = Instance.new("Part")
	coin.Name = "Coin"
	coin.Shape = Enum.PartType.Cylinder
	coin.Size = Vector3.new(0.4, 2, 2)
	coin.Color = Color3.fromRGB(255, 200, 0)
	coin.Material = Enum.Material.Neon
	coin.Anchored = true
	coin.CanCollide = false
	coin.Position = randomPosition(config.SPAWN_RADIUS)
	coin.Parent = folder

	local collected = false
	coin.Touched:Connect(function(hit)
		if collected then
			return
		end
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if not player then
			return
		end
		local leaderstats = player:FindFirstChild("leaderstats")
		local coins = leaderstats and leaderstats:FindFirstChild("Coins")
		if not coins then
			return
		end

		collected = true
		coins.Value += config.COIN_VALUE
		coin.Transparency = 1

		task.delay(config.RESPAWN_SECONDS, function()
			coin.Position = randomPosition(config.SPAWN_RADIUS)
			coin.Transparency = 0
			collected = false
		end)
	end)
end

function Coins.spawnAll(config)
	local folder = Instance.new("Folder")
	folder.Name = "Coins"
	folder.Parent = workspace

	for _ = 1, config.COIN_COUNT do
		createCoin(config, folder)
	end
end

return Coins
