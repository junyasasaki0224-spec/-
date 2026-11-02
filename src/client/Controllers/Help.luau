--!strict
-- 遊び方(設定から開く)。初めての人が迷ったときの短い説明。
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Locale = require(Shared.Locale)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Root = require(script.Parent.Parent.UI.Root)
local C = Theme.Colors

local Help = {}

local KEYS =
	{ "help_fish", "help_sell", "help_codex", "help_partner", "help_battle", "help_nushi", "help_time" }

function Help.init(gui: ScreenGui)
	local panel = Kit.panel(gui, "Help", UDim2.fromScale(0.66, 0.74))
	panel.close.Activated:Connect(function()
		Root.close()
	end)
	local list = Kit.list(panel.body, 8)
	Root.register("help", panel.root, function()
		panel.title.Text = Locale.t("help_title")
		Kit.clear(list)
		for i, key in KEYS do
			local row = Kit.row(list, 64, i)
			Kit.label({
				Size = UDim2.new(1, -24, 1, -12),
				Position = UDim2.fromOffset(12, 6),
				Text = Locale.t(key),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
				Font = Theme.Fonts.body,
				TextColor3 = C.text,
				MaxTextSize = 18,
				Parent = row,
			})
		end
	end)
end

return Help
