--!strict
-- なかま: このサーバーの釣り人の一覧(対戦を申し込む・水槽を見に行く・友達申請)、
-- ほかのサーバーで遊んでいるフレンドのところへ行く、友達を招待する、スタンプ。
-- 文字を自由に送る機能は作らない(会話は Roblox の標準チャット。Roblox が検閲する)。
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local SocialService = game:GetService("SocialService")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Locale = require(Shared.Locale)
local Remotes = require(Shared.Lib.Remotes)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Root = require(script.Parent.Parent.UI.Root)
local State = require(script.Parent.Parent.ClientState)
local Online = require(script.Parent.Online)
local Notify = require(script.Parent.Notify)
local Sound = require(script.Parent.Sound)
local C = Theme.Colors

local O = Config.Online
local player = Players.LocalPlayer

local Social = {}

local panel: Kit.Panel
local countLabel: TextLabel
local listFrame: ScrollingFrame
local emptyBox: Frame
local friendsFrame: ScrollingFrame
local stampButton: TextButton
local stampPicker: Frame

-- フレンドかどうか(問い合わせは時間がかかるので覚えておく)
local friendCache: { [number]: boolean } = {}
local friendAsking: { [number]: boolean } = {}

local function isFriend(userId: number): boolean?
	local v = friendCache[userId]
	if v ~= nil or friendAsking[userId] then
		return v
	end
	friendAsking[userId] = true
	task.spawn(function()
		local ok, res = pcall(function()
			return player:IsFriendsWith(userId)
		end)
		friendAsking[userId] = nil
		friendCache[userId] = ok and res == true
		Social.refresh()
	end)
	return nil
end

-- 1人分の行 ----------------------------------------------------------------------
type Row = {
	frame: Frame,
	name: TextLabel,
	badge: TextLabel,
	info: TextLabel,
	challenge: TextButton,
	tank: TextButton,
	friend: TextButton,
}
local rows: { [number]: Row } = {}

-- 行の右の操作ボタン(上に絵、下に短い言葉。指でも押しやすい大きさ)
local function actionButton(
	parent: Instance,
	order: number,
	icon: string,
	color: Color3,
	fn: () -> ()
): TextButton
	local b = Kit.button({
		Size = UDim2.fromOffset(74, 62),
		Color = color,
		MaxTextSize = 13,
		LayoutOrder = order,
		Parent = parent,
	}, fn)
	b.TextYAlignment = Enum.TextYAlignment.Bottom
	Kit.label({
		Name = "Icon",
		Size = UDim2.new(1, 0, 0, 28),
		Text = icon,
		MaxTextSize = 24,
		Parent = b,
	})
	return b
end

local function setIcon(b: TextButton, icon: string)
	local l = b:FindFirstChild("Icon") :: TextLabel?
	if l then
		l.Text = icon
	end
end

local function makeRow(other: Player): Row
	local f = Kit.row(listFrame, 84)
	Online.avatar(f, other.UserId, 60, { Position = UDim2.fromOffset(12, 12) })
	local nameLabel = Kit.label({
		Size = UDim2.new(1, -340, 0, 28),
		Position = UDim2.fromOffset(84, 12),
		Text = other.DisplayName,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Fonts.title,
		MaxTextSize = 20,
		Parent = f,
	})
	local badge = Kit.label({
		Size = UDim2.fromOffset(60, 20),
		Position = UDim2.fromOffset(12, 60),
		BackgroundTransparency = 0,
		BackgroundColor3 = C.jade,
		Text = Locale.t("social_friend"),
		MaxTextSize = 13,
		Visible = false,
		ZIndex = 2,
		Parent = f,
	})
	Kit.corner(badge, UDim.new(1, 0))
	local info = Kit.label({
		Size = UDim2.new(1, -340, 0, 20),
		Position = UDim2.fromOffset(84, 46),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.textDim,
		MaxTextSize = 15,
		Parent = f,
	})
	local buttons = Kit.new("Frame", {
		Size = UDim2.fromOffset(238, 62),
		Position = UDim2.new(1, -11, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		Parent = f,
	})
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = buttons,
	})
	local uid = other.UserId
	local challenge = actionButton(buttons, 1, "⚔", C.vermilion, function()
		if Online.sent and Online.sent.to == uid then
			Online.withdraw()
		else
			Online.challenge(uid)
		end
	end)
	local tank = actionButton(buttons, 2, "🐟", C.indigo, function()
		State.request("visitTank", uid)
		Root.close()
	end)
	tank.Text = Locale.t("social_tank")
	local friend = actionButton(buttons, 3, "➕", C.jadeDark, function()
		local target = Players:GetPlayerByUserId(uid)
		if target then
			pcall(function()
				StarterGui:SetCore("PromptSendFriendRequest", target)
			end)
		end
	end)
	friend.Text = Locale.t("social_add_friend")
	return {
		frame = f,
		name = nameLabel,
		badge = badge,
		info = info,
		challenge = challenge,
		tank = tank,
		friend = friend,
	}
end

local function updateRow(r: Row, other: Player)
	local uid = other.UserId
	local friendNow = isFriend(uid)
	r.name.Text = other.DisplayName
	r.badge.Visible = friendNow == true
	r.friend.Visible = friendNow == false
	local titleId = other:GetAttribute("TitleId")
	local title = if type(titleId) == "string" and titleId ~= ""
		then Locale.t("title_" .. titleId)
		else Locale.t("title_none")
	r.info.Text = Locale.t("social_info", {
		title = title,
		codex = tonumber(other:GetAttribute("Codex")) or 0,
		rating = tonumber(other:GetAttribute("PvpRating")) or O.RatingStart,
	})

	-- 対戦ボタン: 申し込み中なら「取り消す」、受け付けていない人・対戦中の人は押せない
	local sent = Online.sent
	local pref = other:GetAttribute("ChallengePref")
	local closed = pref == "off" or (pref == "friends" and friendNow ~= true)
	local busy = other:GetAttribute("InBattle") == true
	if sent and sent.to == uid then
		r.challenge.Text =
			Locale.t("social_you_sent", { s = math.max(0, math.ceil(sent.expires - os.clock())) })
		setIcon(r.challenge, "↩")
		Kit.setEnabled(r.challenge, true, C.panelDark)
	elseif busy then
		r.challenge.Text = Locale.t("social_in_battle")
		setIcon(r.challenge, "⏳")
		Kit.setEnabled(r.challenge, false)
	elseif closed then
		r.challenge.Text = Locale.t("social_closed")
		setIcon(r.challenge, "🔒")
		Kit.setEnabled(r.challenge, false)
	else
		r.challenge.Text = Locale.t("social_challenge")
		setIcon(r.challenge, "⚔")
		local mine = State.profile
		local canFight = mine ~= nil and #mine.team > 0 and sent == nil
		Kit.setEnabled(r.challenge, canFight, C.vermilion)
	end
end

function Social.refresh()
	if not panel or not panel.root.Visible then
		return
	end
	local others = {}
	for _, p in Players:GetPlayers() do
		if p ~= player then
			table.insert(others, p)
		end
	end
	-- フレンドを上に、あとは名前順
	table.sort(others, function(a, b)
		local fa, fb = friendCache[a.UserId] == true, friendCache[b.UserId] == true
		if fa ~= fb then
			return fa
		end
		return a.DisplayName < b.DisplayName
	end)
	local seen = {}
	for i, p in others do
		seen[p.UserId] = true
		local r = rows[p.UserId] or makeRow(p)
		rows[p.UserId] = r
		r.frame.LayoutOrder = i
		updateRow(r, p)
	end
	for uid, r in rows do
		if not seen[uid] then
			r.frame:Destroy()
			rows[uid] = nil
		end
	end
	countLabel.Text = Locale.t("social_here", { n = #others + 1, max = O.MaxPlayers })
	emptyBox.Visible = #others == 0
	listFrame.Visible = #others > 0
end

-- ほかのサーバーのフレンド -------------------------------------------------------
local friendsAt = -math.huge

local function renderFriendsOnline()
	Kit.clear(friendsFrame)
	Kit.label({
		Size = UDim2.new(1, 0, 0, 40),
		Text = Locale.t("social_friends_loading"),
		TextColor3 = C.textDim,
		MaxTextSize = 15,
		Parent = friendsFrame,
	})
	task.spawn(function()
		local ok, list = pcall(function()
			return player:GetFriendsOnline(50)
		end)
		Kit.clear(friendsFrame)
		local shown = 0
		if ok and type(list) == "table" then
			for _, f in list do
				-- 同じゲームの別のサーバーにいるフレンドだけ
				if f.PlaceId == game.PlaceId and type(f.GameId) == "string" and f.GameId ~= game.JobId then
					shown += 1
					local row = Kit.row(friendsFrame, 64, shown)
					Online.avatar(row, f.VisitorId, 46, { Position = UDim2.fromOffset(9, 9) })
					Kit.label({
						Size = UDim2.new(1, -190, 1, -16),
						Position = UDim2.fromOffset(64, 8),
						Text = tostring(f.DisplayName or f.UserName or "?"),
						TextXAlignment = Enum.TextXAlignment.Left,
						MaxTextSize = 17,
						Parent = row,
					})
					local jobId = f.GameId
					Kit.button({
						Text = Locale.t("social_join"),
						Size = UDim2.fromOffset(116, 42),
						Position = UDim2.new(1, -10, 0.5, 0),
						AnchorPoint = Vector2.new(1, 0.5),
						Color = C.jade,
						MaxTextSize = 15,
						Parent = row,
					}, function()
						local tok = pcall(function()
							TeleportService:TeleportToPlaceInstance(game.PlaceId, jobId, player)
						end)
						if not tok then
							Notify.key("social_join_failed", nil, C.danger)
						end
					end)
				end
			end
		end
		if shown == 0 then
			Kit.label({
				Size = UDim2.new(1, 0, 0, 60),
				Text = Locale.t("social_none_online"),
				TextColor3 = C.textDim,
				TextWrapped = true,
				MaxTextSize = 15,
				Parent = friendsFrame,
			})
		end
	end)
end

local function invite()
	local ok, can = pcall(function()
		return SocialService:CanSendGameInviteAsync(player)
	end)
	if ok and can then
		pcall(function()
			SocialService:PromptGameInvite(player)
		end)
	end
end

-- スタンプ --------------------------------------------------------------------------
local bubbles: { [number]: BillboardGui } = {}

local function showStamp(userId: number, id: string)
	local who = Players:GetPlayerByUserId(userId)
	local char = who and who.Character
	local head = char and char:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local old = bubbles[userId]
	if old then
		old:Destroy()
	end
	local text = Locale.t("stamp_" .. id)
	local bb = Kit.new("BillboardGui", {
		Name = "Stamp",
		Adornee = head,
		Size = UDim2.fromOffset(28 + (utf8.len(text) or #text) * 17, 44),
		StudsOffset = Vector3.new(0, 3.3, 0),
		AlwaysOnTop = false,
		MaxDistance = 140,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local l = Kit.label({
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0.05,
		BackgroundColor3 = C.text,
		TextColor3 = C.textDark,
		Font = Theme.Fonts.title,
		Text = text,
		MaxTextSize = 22,
		Parent = bb,
	})
	Kit.corner(l, UDim.new(1, 0))
	Kit.padding(l, 6)
	local stroke = Kit.stroke(l, C.gold, 2, 0.1)
	local s = Kit.new("UIScale", { Scale = 0.2, Parent = l })
	TweenService:Create(s, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	bubbles[userId] = bb
	task.delay(3.2, function()
		if bb.Parent then
			local fade = TweenInfo.new(0.35)
			TweenService:Create(l, fade, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
			TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
			task.wait(0.4)
			bb:Destroy()
			if bubbles[userId] == bb then
				bubbles[userId] = nil
			end
		end
	end)
	if who ~= player then
		Sound.play("click", 0.25, 1.4)
	end
end

local stampRemote: RemoteEvent
local stampReadyAt = 0

local function sendStamp(id: string)
	if os.clock() < stampReadyAt then
		return
	end
	stampReadyAt = os.clock() + 1.5
	stampRemote:FireServer(id)
	stampPicker.Visible = false
	Kit.setEnabled(stampButton, false, C.panel)
	task.delay(1.5, function()
		Kit.setEnabled(stampButton, true, C.panel)
	end)
end

local function buildStamps(gui: ScreenGui)
	stampButton = Kit.button({
		Name = "StampButton",
		Text = "💬",
		Size = UDim2.fromOffset(48, 48),
		Color = C.panel,
		Corner = UDim.new(1, 0),
		MaxTextSize = 26,
		Parent = gui,
	}, function()
		stampPicker.Visible = not stampPicker.Visible
	end)
	stampPicker = Kit.new("Frame", {
		Name = "StampPicker",
		Size = UDim2.fromOffset(372, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.04,
		Visible = false,
		ZIndex = 25,
		Parent = gui,
	})
	-- 左の列(お金・魚籠の下)。PC ではチャット窓の下
	Root.onLayout(function()
		local y = Root.leftTop() + 100
		stampButton.Position = UDim2.fromOffset(20, y)
		stampPicker.Position = UDim2.fromOffset(76, y)
	end)
	Kit.corner(stampPicker)
	Kit.stroke(stampPicker, C.gold, 2)
	Kit.padding(stampPicker, 8)
	Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(174, 42),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = stampPicker,
	})
	for i, id in O.Stamps do
		local b = Kit.button({
			Name = id,
			Text = Locale.t("stamp_" .. id),
			Color = C.panelLight,
			MaxTextSize = 16,
			LayoutOrder = i,
			Parent = stampPicker,
		}, function()
			sendStamp(id)
		end)
		b.ZIndex = 26
		b:SetAttribute("LocKey", "stamp_" .. id)
	end
end

-- 言語を切り替えた時
function Social.relabel()
	if stampPicker then
		for _, b in stampPicker:GetChildren() do
			local key = b:GetAttribute("LocKey")
			if b:IsA("TextButton") and type(key) == "string" then
				b.Text = Locale.t(key)
			end
		end
	end
end

-- パネル ----------------------------------------------------------------------------
local function onOpen()
	panel.title.Text = Locale.t("social_title")
	stampPicker.Visible = false
	for _, r in rows do
		r.frame:Destroy()
	end
	table.clear(rows) -- 言語が変わっていても作り直す
	Social.refresh()
	if os.clock() - friendsAt > 30 then
		friendsAt = os.clock()
		renderFriendsOnline()
	end
end

function Social.init(gui: ScreenGui)
	stampRemote = Remotes.event("Stamp")
	panel = Kit.panel(gui, "Social", UDim2.fromScale(0.86, 0.84))
	panel.close.Activated:Connect(function()
		Root.close()
	end)
	local body = panel.body

	-- 上の段: 人数・招待・申し込みの受け方
	local top = Kit.new("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, Parent = body })
	countLabel = Kit.label({
		Size = UDim2.new(0.4, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Fonts.title,
		MaxTextSize = 20,
		Parent = top,
	})
	Kit.button({
		Text = Locale.t("social_invite"),
		Size = UDim2.fromOffset(190, 42),
		Position = UDim2.new(1, 0, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Color = C.jade,
		MaxTextSize = 17,
		Parent = top,
	}, invite)
	local prefHolder = Kit.new("Frame", {
		Size = UDim2.new(0.6, 0, 0, 40),
		Position = UDim2.fromOffset(0, 50),
		BackgroundTransparency = 1,
		Parent = body,
	})
	Online.prefControl(prefHolder)

	-- 左: このサーバーの人 / 右: ほかのサーバーのフレンド
	local left = Kit.new("Frame", {
		Size = UDim2.new(0.64, -8, 1, -100),
		Position = UDim2.fromOffset(0, 100),
		BackgroundTransparency = 1,
		Parent = body,
	})
	listFrame = Kit.list(left, 8)
	emptyBox = Kit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = left })
	Kit.label({
		Size = UDim2.new(1, -40, 0, 60),
		Position = UDim2.new(0.5, 0, 0.35, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = Locale.t("social_alone"),
		TextColor3 = C.textDim,
		TextWrapped = true,
		MaxTextSize = 18,
		Parent = emptyBox,
	})
	Kit.button({
		Text = Locale.t("social_invite"),
		Size = UDim2.fromOffset(240, 56),
		Position = UDim2.new(0.5, 0, 0.55, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = C.jade,
		MaxTextSize = 20,
		Parent = emptyBox,
	}, invite)

	local right = Kit.new("Frame", {
		Size = UDim2.new(0.36, -8, 1, -100),
		Position = UDim2.new(0.64, 8, 0, 100),
		BackgroundColor3 = C.panelDark,
		BackgroundTransparency = 0.3,
		Parent = body,
	})
	Kit.corner(right, Theme.CornerSmall)
	Kit.label({
		Size = UDim2.new(1, -16, 0, 30),
		Position = UDim2.fromOffset(8, 6),
		Text = Locale.t("social_others"),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.goldLight,
		MaxTextSize = 16,
		Parent = right,
	})
	local fl = Kit.new("Frame", {
		Size = UDim2.new(1, -12, 1, -46),
		Position = UDim2.fromOffset(6, 40),
		BackgroundTransparency = 1,
		Parent = right,
	})
	friendsFrame = Kit.list(fl, 6)

	buildStamps(gui)
	Root.register("social", panel.root, onOpen)

	-- 表示を新しくする
	Players.PlayerAdded:Connect(Social.refresh)
	Players.PlayerRemoving:Connect(function(p)
		friendCache[p.UserId] = nil
		task.defer(Social.refresh)
	end)
	Online.Changed:Connect(Social.refresh)
	State.Changed:Connect(Social.refresh)
	task.spawn(function()
		while true do
			task.wait(1)
			Social.refresh() -- 申し込みの残り秒・ほかの人の点数や対戦中の表示
		end
	end)

	Remotes.event("StampShown").OnClientEvent:Connect(function(userId, id)
		if type(userId) == "number" and type(id) == "string" and table.find(O.Stamps, id) then
			showStamp(userId, id)
		end
	end)
	TeleportService.TeleportInitFailed:Connect(function(p)
		if p == player then
			Notify.key("social_join_failed", nil, C.danger)
		end
	end)
	-- フレンドになった/やめた時に覚え直す
	player.FriendStatusChanged:Connect(function(other)
		friendCache[other.UserId] = nil
		Social.refresh()
	end)
end

return Social
