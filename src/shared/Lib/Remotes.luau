--!strict
-- 通信の名前の一覧。サーバーが ReplicatedStorage.Remotes に作成し、クライアントは待って取得する。
-- クライアント→サーバー(C2S)の通信はすべてサーバー側で型・回数・状態を検証する。

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

Remotes.Events = {
	-- クライアント → サーバー
	"Cast", -- (power: number, dirX: number, dirZ: number)
	"Hook", -- ()
	"ReelResult", -- (success: boolean)
	"CancelFishing", -- ()
	"NushiReel", -- (inZoneSeconds: number)
	"Request", -- (action: string, payload: table) 店・水槽・設定などの操作
	-- サーバー → クライアント
	"FishingState", -- (state: string, data: table)
	"Profile", -- (snapshot: table) 自分のデータの差分
	"Notify", -- (key: string, args: table)
	"Announce", -- (key: string, args: table) サーバー全体へのお知らせ
	"CatchResult", -- (result: table)
	"NushiState", -- (state: table)
}

Remotes.Functions = {
	"Query", -- (what: string) -> table 読み取り専用の問い合わせ(ランキングなど)
}

local folder: Folder? = nil

function Remotes.setupServer(): Folder
	assert(RunService:IsServer(), "server only")
	local f = Instance.new("Folder")
	f.Name = "Remotes"
	for _, name in Remotes.Events do
		local e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = f
	end
	for _, name in Remotes.Functions do
		local fn = Instance.new("RemoteFunction")
		fn.Name = name
		fn.Parent = f
	end
	f.Parent = ReplicatedStorage
	folder = f
	return f
end

local function getFolder(): Folder
	if folder then
		return folder
	end
	local f = ReplicatedStorage:WaitForChild("Remotes", 60) :: Folder
	assert(f, "Remotes folder missing")
	folder = f
	return f
end

function Remotes.event(name: string): RemoteEvent
	return getFolder():WaitForChild(name) :: RemoteEvent
end

function Remotes.func(name: string): RemoteFunction
	return getFolder():WaitForChild(name) :: RemoteFunction
end

return Remotes
