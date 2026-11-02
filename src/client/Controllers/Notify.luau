--!strict
-- 画面上部の通知と、サーバー全体のお知らせ(チャット欄にもシステムメッセージで表示)。
local TweenService = game:GetService("TweenService")
local TextChatService = game:GetService("TextChatService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Locale = require(Shared.Locale)
local Remotes = require(Shared.Lib.Remotes)
local Format = require(Shared.Lib.Format)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Sound = require(script.Parent.Sound)
local C = Theme.Colors

local Notify = {}
local stack: Frame

-- サーバーから来た引数を表示用に変換("...Key" は翻訳キー、coins は数値を整形)
function Notify.localizeArgs(args: any): { [string]: any }
	local out = {}
	if type(args) ~= "table" then
		return out
	end
	for k, v in args do
		if type(k) ~= "string" then
			continue
		end
		if k:sub(-3) == "Key" and type(v) == "string" then
			out[k:sub(1, -4)] = Locale.t(v, args)
		elseif k == "coins" and type(v) == "number" then
			out[k] = Format.coins(v, Locale.get())
		elseif k == "weather" and type(v) == "string" then
			out[k] = Locale.t("weather_" .. v)
		elseif type(v) == "string" then
			out[k] = v:sub(1, 40)
		elseif type(v) == "number" then
			out[k] = v
		end
	end
	return out
end

function Notify.show(text: string, color: Color3?, duration: number?)
	if not stack then
		return
	end
	local toast = Kit.new("Frame", {
		Size = UDim2.fromOffset(460, 46),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.08,
		LayoutOrder = -os.clock() * 100,
		Parent = stack,
	})
	Kit.corner(toast, UDim.new(1, 0))
	Kit.stroke(toast, color or C.gold, 2)
	local label = Kit.label({
		Size = UDim2.new(1, -24, 1, -10),
		Position = UDim2.fromOffset(12, 5),
		Text = text,
		TextColor3 = color or C.text,
		MaxTextSize = 22,
		Parent = toast,
	})
	local s = Kit.new("UIScale", { Scale = 0.6, Parent = toast })
	TweenService:Create(s, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(duration or 2.8, function()
		TweenService:Create(toast, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		task.wait(0.32)
		toast:Destroy()
	end)
end

function Notify.key(key: string, args: any?, color: Color3?)
	Notify.show(Locale.t(key, Notify.localizeArgs(args)), color)
end

-- リッチテキスト用のエスケープ(名前などに記号が入っていても表示が崩れないように)
local function escape(s: string): string
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function systemChat(text: string)
	text = escape(text)
	pcall(function()
		local channels = TextChatService:FindFirstChild("TextChannels")
		local system = channels and channels:FindFirstChild("RBXSystem")
		if system and system:IsA("TextChannel") then
			system:DisplaySystemMessage(('<font color="#E8C26A">%s</font>'):format(text))
		end
	end)
end

function Notify.init(gui: ScreenGui)
	stack = Kit.new("Frame", {
		Name = "Toasts",
		Size = UDim2.fromOffset(460, 300),
		Position = UDim2.new(0.5, 0, 0, 172),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Kit.new("UIListLayout", {
		Padding = UDim.new(0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = stack,
	})
	Remotes.event("Notify").OnClientEvent:Connect(function(key, args)
		if type(key) ~= "string" then
			return
		end
		local color = nil
		if key == "notify_coins" or key == "daily_got" then
			color = C.goldLight
			Sound.play("coins", 0.4, 1.3)
		elseif
			key == "fish_too_far"
			or key == "fish_creel_full"
			or key == "shop_not_enough"
			or key == "tank_full"
		then
			color = C.danger
		end
		Notify.key(key, args, color)
	end)
	Remotes.event("Announce").OnClientEvent:Connect(function(key, args)
		if type(key) ~= "string" then
			return
		end
		local text = Locale.t(key, Notify.localizeArgs(args))
		Notify.show(text, C.goldLight, 5)
		systemChat(text)
	end)
end

return Notify
