--!strict
-- 画面の土台。画面サイズに合わせた拡大縮小と、パネルの開閉(同時に1つだけ)を管理する。
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Kit = require(script.Parent.Kit)

local Root = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local panels: { [string]: { root: GuiObject, onOpen: ((any) -> ())? } } = {}
local openName: string? = nil
local openChanged = Instance.new("BindableEvent")
Root.OpenChanged = openChanged.Event
local relayout: () -> () -- 下で決める(画面の大きさが変わった時)

function Root.init(): ScreenGui
	gui = Kit.new("ScreenGui", {
		Name = "YokaiUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local scale = Kit.new("UIScale", { Parent = gui })
	local function rescale()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local v = cam.ViewportSize
		scale.Scale = math.clamp(math.min(v.X / 1280, v.Y / 720), 0.55, 1.25)
		relayout()
	end
	rescale()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(rescale)
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end
	return gui
end

function Root.gui(): ScreenGui
	return gui
end

-- Roblox の上のバー(メニュー・チャットのボタン)の高さ。この画面は全体に描く(IgnoreGuiInset)ので、上に置く物はこれより下へ
function Root.topInset(): number
	local scale = gui and gui:FindFirstChildOfClass("UIScale")
	local s = if scale then scale.Scale else 1
	local ok, topLeft = pcall(function()
		return GuiService:GetGuiInset()
	end)
	local y = if ok and typeof(topLeft) == "Vector2" then topLeft.Y else 36
	return y / math.max(0.1, s)
end

-- Roblox のチャット窓(左上)の大きさ(画面のピクセル)。PC では最初から開いている
Root.CHAT_SIZE = Vector2.new(400, 280)

-- スマホ(タッチだけ)では、チャットは上のバーのボタンを押した時だけ開く
function Root.chatOpenByDefault(): boolean
	return not (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
end

-- 左の列(お金・魚籠・エサ・スタンプ・対戦の札)の上端。PC ではチャット窓の下から始める
function Root.leftTop(): number
	local scale = gui and gui:FindFirstChildOfClass("UIScale")
	local s = math.max(0.1, if scale then scale.Scale else 1)
	if Root.chatOpenByDefault() then
		local ok, inset = pcall(function()
			return GuiService:GetGuiInset()
		end)
		local y = if ok and typeof(inset) == "Vector2" then inset.Y else 58
		return (y + Root.CHAT_SIZE.Y) / s + 12
	end
	return math.max(70, Root.topInset() + 8)
end

-- 画面の大きさが変わった時(と今すぐ)に呼ぶ。置き場所を計算し直す物に使う
local layoutCallbacks: { () -> () } = {}
function Root.onLayout(fn: () -> ())
	table.insert(layoutCallbacks, fn)
	fn()
end
function relayout()
	for _, fn in layoutCallbacks do
		fn()
	end
end

-- 上端が top の物を、上のバーに重ならないように下げる量
function Root.topShift(top: number): number
	return math.max(0, Root.topInset() + 8 - top)
end

function Root.register(name: string, root: GuiObject, onOpen: ((any) -> ())?)
	panels[name] = { root = root, onOpen = onOpen }
end

-- バトルの間は、ほかの画面を開かない(世界の「調べる」ボタンやキーで、バトルの上に重ならないように)
local locked = false
function Root.setLocked(on: boolean)
	locked = on
end

function Root.open(name: string, arg: any?)
	if locked then
		return
	end
	for n, p in panels do
		if n ~= name then
			p.root.Visible = false
		end
	end
	local p = panels[name]
	if not p then
		return
	end
	p.root.Visible = true
	local s = p.root:FindFirstChildOfClass("UIScale") or Kit.new("UIScale", { Parent = p.root })
	s.Scale = 0.85
	TweenService:Create(s, TweenInfo.new(0.22, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	openName = name
	if p.onOpen then
		p.onOpen(arg)
	end
	openChanged:Fire(name)
end

function Root.close(name: string?)
	if name and openName ~= name then
		return
	end
	for _, p in panels do
		p.root.Visible = false
	end
	openName = nil
	openChanged:Fire(nil)
end

function Root.toggle(name: string, arg: any?)
	if openName == name then
		Root.close()
	else
		Root.open(name, arg)
	end
end

function Root.isOpen(name: string?): boolean
	if name then
		return openName == name
	end
	return openName ~= nil
end

return Root
