--!strict
-- UIの色・文字・角丸。和風(藍・金・朱)で統一する。
local Theme = {}

Theme.Colors = {
	panel = Color3.fromRGB(27, 24, 48),
	panelLight = Color3.fromRGB(42, 37, 70),
	panelDark = Color3.fromRGB(16, 14, 30),
	gold = Color3.fromRGB(232, 194, 106),
	goldLight = Color3.fromRGB(255, 227, 160),
	vermilion = Color3.fromRGB(217, 72, 59),
	vermilionDark = Color3.fromRGB(150, 40, 34),
	jade = Color3.fromRGB(76, 170, 120),
	jadeDark = Color3.fromRGB(40, 110, 76),
	indigo = Color3.fromRGB(60, 80, 160),
	text = Color3.fromRGB(255, 244, 222),
	textDim = Color3.fromRGB(185, 178, 208),
	textDark = Color3.fromRGB(40, 30, 24),
	disabled = Color3.fromRGB(90, 86, 104),
	water = Color3.fromRGB(32, 84, 110),
	waterDeep = Color3.fromRGB(14, 40, 62),
	danger = Color3.fromRGB(255, 90, 90),
	success = Color3.fromRGB(120, 230, 140),
}

Theme.Fonts = {
	title = Enum.Font.GothamBlack,
	bold = Enum.Font.GothamBold,
	body = Enum.Font.GothamMedium,
}

Theme.Corner = UDim.new(0, 14)
Theme.CornerSmall = UDim.new(0, 8)

return Theme
