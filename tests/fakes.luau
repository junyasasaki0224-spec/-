-- テスト用の「偽物の Roblox」: 自分で進める時計(task / os.clock)、偽物の Instance、画面を調べる道具、画面の写し。
-- tests/client_sim.luau と tests/client_boot.luau が使う。
-- F.validating = true の間は、偽物の Instance へのプロパティの読み書きを、本物の Roblox の定義(Lune の反射データ)で確かめ、
-- 存在しない名前・型の違う値を F.problems に集める(Studio を開かずに、名前の打ち間違いや型の取り違えを見つける)。
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local F = {}
F.validating = false
F.problems = {} :: { { class: string, key: string, kind: string, msg: string, where: string } }
local seenProblem: { [string]: boolean } = {}
local realCache: { [string]: any } = {}

local function realOf(className: string): any
	local r = realCache[className]
	if r == nil then
		local ok, inst = pcall(roblox.Instance.new, className)
		r = if ok then inst else false
		realCache[className] = r
	end
	return r or nil
end

-- 初期値を読むための、何も書き込まない本物(書き込みの確かめに使う方と分ける。混ぜると初期値が汚れる)
local pristineCache: { [string]: any } = {}
local function pristineOf(className: string): any
	local r = pristineCache[className]
	if r == nil then
		local ok, inst = pcall(roblox.Instance.new, className)
		r = if ok then inst else false
		pristineCache[className] = r
	end
	return r or nil
end

-- 本物の Roblox にはあるのに、Lune の定義に無いもの(誤検出にしない)
local LUNE_GAPS: { [string]: boolean } = {
	["ViewportFrame.CurrentCamera"] = true,
}

local function record(className: string, k: string, kind: string, msg: string)
	local key = className .. "." .. k .. ":" .. kind
	if seenProblem[key] or LUNE_GAPS[className .. "." .. k] then
		return
	end
	-- どこで起きたか(テストの道具の行を飛ばして、ゲームのコードの行を探す)
	local where = ""
	for line in debug.traceback("", 3):gmatch("[^\n]+") do
		if line:find("src/", 1, true) then
			where = line:gsub("^%s+", "")
			break
		end
	end
	-- テストの道具が全部の部品を調べる時の読み込みは数えない(ゲームのコードからの読み書きだけ)
	if where == "" then
		return
	end
	seenProblem[key] = true
	table.insert(F.problems, { class = className, key = k, kind = kind, msg = msg, where = where })
end

local function isFakeInstance(v: any): boolean
	return type(v) == "table" and rawget(v, "__props") ~= nil
end

-- 書き込み: 名前があるか、値の型が合うか
local function checkWrite(className: string, k: string, v: any)
	if not F.validating or type(k) ~= "string" or type(v) == "function" then
		return
	end
	local real = realOf(className)
	if not real then
		return
	end
	if v == nil or isFakeInstance(v) or type(v) == "table" then
		-- Instance を入れる場所(Parent など)は、名前があるかだけ見る
		local ok, err = pcall(function()
			return real[k]
		end)
		if not ok and not tostring(err):find("missing default value", 1, true) then
			record(className, k, "write", tostring(err):match("^[^\n]*") or "")
		end
		return
	end
	local ok, err = pcall(function()
		real[k] = v
	end)
	if not ok then
		record(className, k, "write", tostring(err):match("[^\n]+") or "")
	end
end

-- 読み込み: 名前があるか(値が無いだけの時は本物でも nil を返す)
local function checkRead(className: string, k: string)
	if not F.validating or type(k) ~= "string" then
		return
	end
	local real = realOf(className)
	if not real then
		return
	end
	local ok, err = pcall(function()
		return real[k]
	end)
	-- 「既定値が無い」は、名前はある(Lune が初期値を持っていないだけ)
	if not ok and not tostring(err):find("missing default value", 1, true) then
		record(className, k, "read", tostring(err):match("[^\n]+") or "")
	end
end

-- 時間(os.clock と task は、この時計で動く) -------------------------------------
local now = 1000
local sleeping: { { co: thread, at: number, args: { any }? } } = {}

local function resume(co: thread, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		error(debug.traceback(co, tostring(err)), 0)
	end
end

local fakeTask = {}
function fakeTask.spawn(fn: any, ...): thread
	local co = if type(fn) == "thread" then fn else coroutine.create(fn)
	resume(co, ...)
	return co
end
function fakeTask.defer(fn: any, ...)
	table.insert(sleeping, { co = coroutine.create(fn), at = now, args = { ... } })
end
function fakeTask.delay(t: number?, fn: any, ...)
	table.insert(sleeping, { co = coroutine.create(fn), at = now + (t or 0), args = { ... } })
end
function fakeTask.wait(t: number?): number
	if not coroutine.isyieldable() then
		return 0
	end
	table.insert(sleeping, { co = coroutine.running(), at = now + (t or 0.03) })
	coroutine.yield()
	return t or 0.03
end

local function advance(dt: number)
	local target = now + dt
	local steps = 0
	while true do
		-- 同じ時刻に自分を入れ直し続ける処理があると止まらなくなるので、テストの失敗にする
		steps += 1
		if steps > 200000 then
			error("scheduler runaway: something keeps waking at the same time", 2)
		end
		local bestI, best = nil, nil
		for i, s in sleeping do
			if s.at <= target and (best == nil or s.at < best.at) then
				bestI, best = i, s
			end
		end
		if not bestI or not best then
			break
		end
		table.remove(sleeping, bestI)
		now = math.max(now, best.at)
		resume(best.co, table.unpack(best.args or {}))
	end
	now = target
end

local fakeOs = table.clone(os)
fakeOs.clock = function()
	return now
end

-- 偽物の Instance ------------------------------------------------------------------
local function Signal()
	local s: any = { handlers = {} }
	function s:Connect(fn)
		local h = { fn = fn, Connected = true }
		table.insert(self.handlers, h)
		function h.Disconnect()
			h.Connected = false
		end
		return h
	end
	s.Once = s.Connect
	function s:Fire(...)
		for _, h in table.clone(self.handlers) do
			if h.Connected then
				fakeTask.spawn(h.fn, ...)
			end
		end
	end
	function s:Wait() end
	return s
end

local EVENTS = {
	Activated = true,
	MouseButton1Down = true,
	MouseButton1Up = true,
	MouseButton1Click = true,
	MouseLeave = true,
	MouseEnter = true,
	Changed = true,
	Destroying = true,
	OnClientEvent = true,
	Event = true,
	Heartbeat = true,
	RenderStepped = true,
	FocusLost = true,
	InputBegan = true,
	InputEnded = true,
	TeleportInitFailed = true,
	FriendStatusChanged = true,
	PlayerAdded = true,
	PlayerRemoving = true,
	-- 本物の Roblox のイベント(使っているもの)
	CharacterAdded = true,
	CharacterRemoving = true,
	Died = true,
	Ended = true,
	Played = true,
	Loaded = true,
	Triggered = true,
	TriggerEnded = true,
	PromptShown = true,
	Touched = true,
	ChildAdded = true,
	ChildRemoved = true,
	DescendantAdded = true,
	AncestryChanged = true,
	Completed = true,
	InputChanged = true,
	MouseButton2Click = true,
	MouseWheelForward = true,
	MouseWheelBackward = true,
	TouchTap = true,
}
local IS_A = {
	Part = { BasePart = true, Instance = true },
	TextButton = { GuiButton = true, GuiObject = true, TextButton = true },
	ImageButton = { GuiButton = true, GuiObject = true },
	TextLabel = { GuiObject = true },
	ImageLabel = { GuiObject = true },
	Frame = { GuiObject = true },
	ScrollingFrame = { GuiObject = true },
	ViewportFrame = { GuiObject = true },
	BillboardGui = { LayerCollector = true },
	ScreenGui = { LayerCollector = true },
}

local methods: any = {}
local mt: any = {}
local function newInstance(className: string): any
	local self = setmetatable({
		__props = { ClassName = className, Name = className },
		__children = {},
		__attrs = {},
		__signals = {},
		__attrSignals = {},
	}, mt)
	return self
end
mt.__index = function(t, k)
	local props = rawget(t, "__props")
	local v = props[k]
	if v ~= nil then
		return v
	end
	if methods[k] then
		return methods[k]
	end
	if EVENTS[k] then
		local sigs = rawget(t, "__signals")
		sigs[k] = sigs[k] or Signal()
		return sigs[k]
	end
	-- まだ入れていないプロパティは、本物の Roblox の初期値を返す(Rotation = 0、Visible = true など)
	local real = type(k) == "string" and pristineOf(props.ClassName)
	if real then
		local ok, value = pcall(function()
			return real[k]
		end)
		if ok then
			if typeof(value) == "Instance" then
				return nil -- 本物の Instance は渡さない(偽物の木に混ざらないように)
			end
			return value
		end
	end
	checkRead(props.ClassName, k)
	return nil
end
mt.__newindex = function(t, k, v)
	local props = rawget(t, "__props")
	checkWrite(props.ClassName, k, v)
	if k == "Parent" then
		local old = props.Parent
		if old then
			local list = rawget(old, "__children")
			local i = table.find(list, t)
			if i then
				table.remove(list, i)
			end
		end
		if v then
			table.insert(rawget(v, "__children"), t)
		end
	end
	props[k] = v
end
mt.__tostring = function(t)
	return "Fake" .. rawget(t, "__props").ClassName
end

-- BindableEvent
function methods:Fire(...)
	self.Event:Fire(...)
end
function methods:GetChildren()
	return table.clone(rawget(self, "__children"))
end
function methods:GetDescendants()
	local out = {}
	local function walk(n)
		for _, c in rawget(n, "__children") do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function methods:FindFirstChild(name)
	for _, c in rawget(self, "__children") do
		if c.Name == name then
			return c
		end
	end
	return nil
end
function methods:WaitForChild(name)
	return self:FindFirstChild(name)
end
function methods:FindFirstChildOfClass(cls)
	for _, c in rawget(self, "__children") do
		if c.ClassName == cls then
			return c
		end
	end
	return nil
end
function methods:IsA(cls)
	local own = self.ClassName
	return own == cls or (IS_A[own] ~= nil and IS_A[own][cls] == true) or cls == "Instance"
end
function methods:Destroy()
	for _, c in self:GetChildren() do
		c:Destroy()
	end
	self.Destroying:Fire()
	self.Parent = nil
	rawget(self, "__props").Destroyed = true
end
function methods:ClearAllChildren()
	for _, c in self:GetChildren() do
		c:Destroy()
	end
end
function methods:SetAttribute(k, v)
	rawget(self, "__attrs")[k] = v
	local s = rawget(self, "__attrSignals")[k]
	if s then
		s:Fire()
	end
end
function methods:GetAttribute(k)
	return rawget(self, "__attrs")[k]
end
function methods:GetAttributeChangedSignal(k)
	local sigs = rawget(self, "__attrSignals")
	sigs[k] = sigs[k] or Signal()
	return sigs[k]
end
function methods:GetPropertyChangedSignal()
	return Signal()
end
function methods:PivotTo(cf)
	rawget(self, "__props").Pivot = cf
end
function methods:Emit() end
-- Sound
function methods:Play() end
function methods:Stop() end
function methods:Pause() end
function methods:Resume() end
function methods:Clone()
	local c = newInstance(self.ClassName)
	for k, v in rawget(self, "__props") do
		if k ~= "Parent" then
			rawget(c, "__props")[k] = v
		end
	end
	for _, child in self:GetChildren() do
		child:Clone().Parent = c
	end
	return c
end
function methods:GetPivot()
	return rawget(self, "__props").Pivot or rawget(self, "__props").CFrame
end
function methods:IsDescendantOf(other)
	local n = self.Parent
	while n do
		if n == other then
			return true
		end
		n = n.Parent
	end
	return false
end
function methods:FindFirstAncestorOfClass(cls)
	local n = self.Parent
	while n do
		if n.ClassName == cls then
			return n
		end
		n = n.Parent
	end
	return nil
end
function methods:FindFirstChildWhichIsA(cls)
	for _, c in rawget(self, "__children") do
		if c:IsA(cls) then
			return c
		end
	end
	return nil
end
function methods:GetFullName()
	return self.Name
end
function methods:GetScale()
	return rawget(self, "__props").Scale or 1
end
function methods:ScaleTo(x)
	rawget(self, "__props").Scale = x
end
function methods:BulkMoveTo(parts, cfs)
	for i, p in parts do
		p.CFrame = cfs[i]
	end
end
function methods:GetBoundingBox()
	return roblox.CFrame.new(), roblox.Vector3.new(4, 2, 1)
end

local created = 0
local function fakeNew(className: string): any
	created += 1
	return newInstance(className)
end

local function walkFind(root: any, pred: (any) -> boolean): { any }
	local out = {}
	for _, d in root:GetDescendants() do
		if pred(d) then
			table.insert(out, d)
		end
	end
	return out
end

local function visible(inst: any): boolean
	local n = inst
	while n do
		if n.Visible == false then
			return false
		end
		n = n.Parent
	end
	return true
end

-- 画面に見えている、その文字のボタン
local function button(root: any, text: string): any
	for _, b in
		walkFind(root, function(d)
			return d.ClassName == "TextButton" and d.Text == text and visible(d)
		end)
	do
		return b
	end
	return nil
end

-- 中の文字にその言葉を含むボタン(技のお札など、文字を子のラベルに書くボタン)
local function cardFor(root: any, text: string): any
	local buttons = walkFind(root, function(d)
		return d.ClassName == "TextButton" and visible(d)
	end)
	for _, b in buttons do
		if type(b.Text) == "string" and b.Text:find(text, 1, true) then
			return b
		end
	end
	for _, b in buttons do
		for _, d in b:GetDescendants() do
			if d.ClassName == "TextLabel" and type(d.Text) == "string" and d.Text:find(text, 1, true) then
				-- いちばん近いボタンがこのボタンのものだけ(外側の大きなボタンを拾わない)
				local n = d.Parent
				while n and n.ClassName ~= "TextButton" do
					n = n.Parent
				end
				if n == b then
					return b
				end
			end
		end
	end
	return nil
end

local function enabled(b: any): boolean
	return b ~= nil and b:GetAttribute("Disabled") ~= true
end

local function visibleButtons(root: any): string
	local names = {}
	for _, d in
		walkFind(root, function(d)
			return d.ClassName == "TextButton" and visible(d) and d.Text ~= ""
		end)
	do
		table.insert(names, d.Text .. (if enabled(d) then "" else "(off)"))
	end
	return table.concat(names, " | ")
end

local function click(b: any)
	if not b then
		error("button not found; visible: " .. visibleButtons(rawget(_G, "__gui")), 2)
	end
	if not enabled(b) then
		error("button disabled: " .. tostring(b.Text), 2)
	end
	b.Activated:Fire()
end

local function hasText(root: any, pattern: string): boolean
	for _, d in
		walkFind(root, function(d)
			return type(d.Text) == "string" and visible(d)
		end)
	do
		if d.Text:find(pattern, 1, true) then
			return true
		end
	end
	return false
end

-- 画面の写し(UI_SNAPSHOTS=フォルダ を付けて実行すると、場面ごとに画面の木を JSON で書き出す。
-- node tools/ui/render_ui.js で PNG にできる)
local snapshotDir = process.env.UI_SNAPSHOTS
local function ser(v: any): any
	local ty = typeof(v)
	if ty == "UDim2" then
		return { xs = v.X.Scale, xo = v.X.Offset, ys = v.Y.Scale, yo = v.Y.Offset }
	elseif ty == "UDim" then
		return { s = v.Scale, o = v.Offset }
	elseif ty == "Vector2" then
		return { x = v.X, y = v.Y }
	elseif ty == "Color3" then
		return { r = v.R, g = v.G, b = v.B }
	elseif ty == "EnumItem" then
		return { name = v.Name }
	elseif ty == "NumberSequence" then
		local ks = {}
		for _, k in v.Keypoints do
			table.insert(ks, { k.Time, k.Value })
		end
		return { ks = ks }
	elseif ty == "CFrame" then
		return { x = v.Position.X, y = v.Position.Y, z = v.Position.Z, lx = v.LookVector.X }
	elseif ty == "ColorSequence" then
		local k = v.Keypoints
		return { c0 = ser(k[1].Value), c1 = ser(k[#k].Value) }
	elseif ty == "number" or ty == "string" or ty == "boolean" then
		return v
	end
	return nil
end
local function dumpTree(inst: any): any
	local props = {}
	for k, v in rawget(inst, "__props") do
		if k ~= "Parent" then
			local x = ser(v)
			if x ~= nil then
				props[k] = x
			end
		end
	end
	local kids = {}
	for _, c in rawget(inst, "__children") do
		table.insert(kids, dumpTree(c))
	end
	return { c = inst.ClassName, p = props, k = kids }
end
local snapshotGui: any = nil
local function snapshot(name: string)
	if not snapshotDir or not snapshotGui then
		return
	end
	-- ゲームでは毎フレーム動いているので、写す前に1フレーム進める
	local before = rawget(_G, "__beforeSnapshot")
	if before then
		before()
	end
	if not fs.isDir(snapshotDir) then
		fs.writeDir(snapshotDir)
	end
	fs.writeFile(snapshotDir .. "/" .. name .. ".json", serde.encode("json", dumpTree(snapshotGui)))
end

F.roblox = roblox
F.Signal = Signal
F.task = fakeTask
F.os = fakeOs
F.advance = advance
F.now = function()
	return now
end
F.EVENTS = EVENTS
F.methods = methods
F.new = fakeNew
F.walkFind = walkFind
F.visible = visible
F.button = button
F.cardFor = cardFor
F.enabled = enabled
F.visibleButtons = visibleButtons
F.click = click
F.hasText = hasText
F.snapshot = snapshot
F.setSnapshotRoot = function(root: any)
	snapshotGui = root
end

return F
