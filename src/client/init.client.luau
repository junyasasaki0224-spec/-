--!strict
-- クライアントの起動スクリプト
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Locale = require(Shared.Locale)

local player = Players.LocalPlayer
Locale.set(Locale.detect(player.LocaleId))

local Root = require(script.UI.Root)
local State = require(script.ClientState)
local Controllers = script.Controllers
local Input = require(Controllers.Input)
local Notify = require(Controllers.Notify)
local HUD = require(Controllers.HUD)
local Fishing = require(Controllers.Fishing)
local Result = require(Controllers.Result)
local Shop = require(Controllers.Shop)
local Codex = require(Controllers.Codex)
local Quests = require(Controllers.Quests)
local Settings = require(Controllers.Settings)
local WorldFX = require(Controllers.WorldFX)
local LightingFX = require(Controllers.LightingFX)
local Nushi = require(Controllers.Nushi)
local Tutorial = require(Controllers.Tutorial)

local gui = Root.init()
State.init()
Input.init()
Notify.init(gui)
HUD.init(gui)
Fishing.init(gui)
Result.init(gui)
Shop.init(gui)
Codex.init(gui)
Quests.init(gui)
Settings.init(gui, function()
	-- 言語を切り替えたら、見えている文字をすべて更新
	HUD.relabel()
	WorldFX.relocalize()
end)
WorldFX.init()
LightingFX.init()
Nushi.init(gui)
Tutorial.init(gui)

-- パネルを開いている間は釣りの入力を止める
Root.OpenChanged:Connect(function(name)
	Input.setEnabled(name == nil)
end)

-- 最初のデータが届いたら: 保存された言語設定を反映し、毎日のごほうびを表示
local first = true
State.Changed:Connect(function()
	if not first or not State.profile then
		return
	end
	first = false
	local lang = State.profile.settings.lang
	if lang == "ja" or lang == "en" then
		Locale.set(lang)
		HUD.relabel()
		WorldFX.relocalize()
	end
	task.delay(3, Quests.showDailyIfPending)
end)

-- リセットボタンは残す(水に落ちた時など)。バックパックは使わないので隠す
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)
