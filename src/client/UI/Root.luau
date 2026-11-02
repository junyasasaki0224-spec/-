--!strict
-- 画面の土台。画面サイズに合わせた拡大縮小と、パネルの開閉(同時に1つだけ)を管理する。
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Kit = require(script.Parent.Kit)

local Root = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local panels: { [string]: { root: GuiObject, onOpen: ((any) -> ())? } } = {}
local openName: string? = nil
local openChanged = Instance.new("BindableEvent")
Root.OpenChanged = openChanged.Event

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

function Root.register(name: string, root: GuiObject, onOpen: ((any) -> ())?)
	panels[name] = { root = root, onOpen = onOpen }
end

function Root.open(name: string, arg: any?)
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
