-- レース中の表示(HUD)。ブラウザ版(style.css の #hud)と同じ配置・色・大きさにそろえる。
-- 左上: 順位と周回・時間 / 上中央: スタート前の大時計と予想ST / 右上: 順位表 / 左上の下: ミニマップ
-- 右下: 速度計(スロットルレバーの横) / 下中央: 風と波 / 中央上寄り: 大きな知らせ(ST・周回・ゴール・失格)
local Hud = {}
Hud.__index = Hud
-- 毎コマ書き換える文字は、その場で今の言語に訳す(画面の見張りの訳が描くのに間に合わず、日本語がちらつかないように)
local T = require(game:GetService("ReplicatedStorage"):WaitForChild("Lang")).translate

local NAVY = Color3.fromRGB(11, 29, 58)
local GOLD = Color3.fromRGB(255, 210, 60)
local WHITE = Color3.new(1, 1, 1)
local SUB = Color3.fromRGB(207, 220, 243)
local RED = Color3.fromRGB(255, 90, 77)
local GREEN = Color3.fromRGB(109, 255, 168)
local LANE = {
    { Color3.fromRGB(242, 242, 240), Color3.fromRGB(17, 17, 17) },
    { Color3.fromRGB(22, 22, 26), WHITE },
    { Color3.fromRGB(217, 30, 46), WHITE },
    { Color3.fromRGB(27, 80, 212), WHITE },
    { Color3.fromRGB(243, 210, 27), Color3.fromRGB(17, 17, 17) },
    { Color3.fromRGB(24, 162, 76), WHITE },
}
-- 数字は太字の斜体(ブラウザ版の font-weight 900 / italic)。日本語は自動で日本語の書体になる
local NUMBER_FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
local BOLD_FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
-- コースの範囲(ミニマップ用。メートル)
local MIN_X, MAX_X, MIN_Z, MAX_Z = -262, 252, -78, 58

local function corner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = parent
    return c
end

local function stroke(parent, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Color, s.Thickness, s.Transparency = color, thickness, transparency or 0
    s.Parent = parent
    return s
end

-- 半透明の紺の板
local function panel(parent, name, transparency)
    local f = Instance.new("Frame")
    f.Name = name
    f.BackgroundColor3 = Color3.fromRGB(8, 24, 48)
    f.BackgroundTransparency = transparency or 0.38
    f.BorderSizePixel = 0
    f.Parent = parent
    return f
end

-- 文字(影の代わりに暗い縁取りを薄く付けて、水面の上でも読めるようにする)
local function text(parent, name, size, font, color)
    local t = Instance.new("TextLabel")
    t.Name = name
    t.BackgroundTransparency = 1
    t.FontFace = font or BOLD_FONT
    t.TextSize = size
    t.TextColor3 = color or WHITE
    t.TextStrokeColor3 = Color3.fromRGB(0, 10, 30)
    t.TextStrokeTransparency = 0.55
    t.Text = ""
    t.Parent = parent
    return t
end

-- 艇番の色の四角(ブラウザ版の .chip)
local function chip(parent, lane, size)
    local c = text(parent, "Chip", math.floor(size * 0.62), NUMBER_FONT, LANE[lane][2])
    c.BackgroundTransparency = 0
    c.BackgroundColor3 = LANE[lane][1]
    c.Size = UDim2.fromOffset(size, size)
    c.Text = tostring(lane)
    c.TextStrokeTransparency = 1
    corner(c, 5)
    stroke(c, WHITE, 1, 0.15)
    return c
end

-- タイムを 1'40"2 の形にする
local function formatTime(t)
    local tenths = math.floor(math.max(0, t) * 10 + 0.5)
    return string.format("%d'%02d\"%d", tenths // 600, (tenths // 10) % 60, tenths % 10)
end
Hud.formatTime = formatTime

function Hud.new(gui)
    local self = setmetatable({ gui = gui, flashUntil = 0, chips = {} }, Hud)
    local root = Instance.new("Frame")
    root.Name = "RaceHud"
    root.BackgroundTransparency = 1
    root.Size = UDim2.fromScale(1, 1)
    root.Parent = gui
    self.root = root

    -- 左上: 順位(1着は金)と、周回・時間
    local pos = Instance.new("Frame")
    pos.Name = "Position"
    pos.Position = UDim2.fromOffset(16, 14)
    pos.Size = UDim2.fromOffset(92, 64)
    pos.BackgroundColor3 = WHITE
    pos.Parent = root
    corner(pos, 14)
    stroke(pos, WHITE, 2, 0.15)
    self.posGradient = Instance.new("UIGradient")
    self.posGradient.Rotation = 70
    self.posGradient.Parent = pos
    self.posN = text(pos, "Number", 46, NUMBER_FONT)
    self.posN.Size = UDim2.new(0, 56, 1, 0)
    self.posN.Position = UDim2.fromOffset(6, -2)
    self.posN.TextXAlignment = Enum.TextXAlignment.Right
    self.posUnit = text(pos, "Unit", 18)
    self.posUnit.Size = UDim2.fromOffset(24, 30)
    self.posUnit.Position = UDim2.fromOffset(62, 26)
    self.posUnit.Text = "着"
    self.pos = pos
    self.lap = text(root, "Lap", 20)
    self.lap.Position = UDim2.fromOffset(120, 16)
    self.lap.Size = UDim2.fromOffset(240, 26)
    self.lap.TextXAlignment = Enum.TextXAlignment.Left
    self.time = text(root, "Time", 26, NUMBER_FONT)
    self.time.Position = UDim2.fromOffset(120, 44)
    self.time.Size = UDim2.fromOffset(200, 30)
    self.time.TextXAlignment = Enum.TextXAlignment.Left

    -- 左上の下: 前後の艇との秒差(前は暖色、後ろは寒色。ブラウザ版の #gap)
    self.gaps = {}
    for k, color in ipairs({ Color3.fromRGB(255, 217, 168), Color3.fromRGB(191, 227, 255) }) do
        local row = panel(root, k == 1 and "GapAhead" or "GapBehind")
        row.Position = UDim2.fromOffset(16, 86 + (k - 1) * 25)
        row.Size = UDim2.fromOffset(150, 22)
        corner(row, 7)
        local label = text(row, "Label", 14, BOLD_FONT, color)
        label.Position = UDim2.fromOffset(7, 0)
        label.Size = UDim2.fromOffset(20, 22)
        label.Text = k == 1 and "前" or "後"
        local c = chip(row, 1, 18)
        c.Position = UDim2.fromOffset(28, 2)
        local value = text(row, "Value", 13, NUMBER_FONT, color)
        value.Position = UDim2.fromOffset(52, 0)
        value.Size = UDim2.fromOffset(94, 22)
        value.TextXAlignment = Enum.TextXAlignment.Left
        row.Visible = false
        self.gaps[k] = { frame = row, chip = c, value = value }
    end

    -- 左上の下: ミニマップ(コースの形、ターンマーク、各艇の点。自分は三角)
    local map = panel(root, "Minimap", 0.28)
    map.BackgroundColor3 = Color3.fromRGB(8, 40, 60)
    map.ClipsDescendants = true
    corner(map, 10)
    stroke(map, WHITE, 1.5, 0.45)
    self.map = map
    local line = Instance.new("Frame")
    line.Name = "StartLine"
    line.BackgroundColor3 = WHITE
    line.BackgroundTransparency = 0.3
    line.BorderSizePixel = 0
    line.Parent = map
    self.mapLine = line
    self.mapMarks = {}
    for i, m in ipairs({ { 150, 8 }, { -150, 0 } }) do
        local d = Instance.new("Frame")
        d.Name = "Mark" .. i
        d.AnchorPoint = Vector2.new(0.5, 0.5)
        d.Size = UDim2.fromOffset(8, 8)
        d.BackgroundColor3 = Color3.fromRGB(255, 75, 62)
        d.Parent = map
        corner(d, 4)
        stroke(d, WHITE, 1)
        self.mapMarks[i] = { frame = d, x = m[1], z = m[2] }
    end
    self.mapDots = {}
    for lane = 1, 6 do
        local d = Instance.new("Frame")
        d.Name = "Boat" .. lane
        d.AnchorPoint = Vector2.new(0.5, 0.5)
        d.Size = UDim2.fromOffset(9, 9)
        d.BackgroundColor3 = LANE[lane][1]
        d.Parent = map
        corner(d, 5)
        stroke(d, WHITE, 1)
        self.mapDots[lane] = d
    end
    local me = text(map, "Me", 14, BOLD_FONT, GOLD)
    me.AnchorPoint = Vector2.new(0.5, 0.5)
    me.Size = UDim2.fromOffset(18, 18)
    me.Text = "▲"
    me.TextStrokeTransparency = 0.2
    me.ZIndex = 3
    self.mapMe = me

    -- 右上: 順位表(自分の行は金)
    local order = Instance.new("Frame")
    order.Name = "Order"
    order.BackgroundTransparency = 1
    order.Parent = root
    self.order = order
    self.orderRows = {}
    for i = 1, 6 do
        local row = panel(order, "Row" .. i)
        corner(row, 8)
        local mark = text(row, "Mark", 14)
        mark.Size = UDim2.fromOffset(16, 26)
        mark.Position = UDim2.fromOffset(4, 0)
        local c = chip(row, 1, 20)
        c.Position = UDim2.fromOffset(22, 3)
        local name = text(row, "Name", 14)
        name.Position = UDim2.fromOffset(48, 0)
        name.Size = UDim2.new(1, -52, 1, 0)
        name.TextXAlignment = Enum.TextXAlignment.Left
        name.TextTruncate = Enum.TextTruncate.AtEnd
        self.orderRows[i] = { frame = row, mark = mark, chip = c, name = name }
    end

    -- 上中央: スタート前の大時計。スタート練習だけ、右に予想STのバー(スタートアシスト)を並べる
    -- 大時計: 黒に近い文字盤・シャンパンゴールドの縁・細い目盛り(1秒ごとに金、0.2秒ごとに細い白)。12秒で1周、0秒で真上
    local FACE = Color3.fromRGB(16, 19, 26)
    local CHAMPAGNE = Color3.fromRGB(222, 190, 128)
    local IVORY = Color3.fromRGB(240, 236, 226)
    local DIAL_FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium, Enum.FontStyle.Normal)
    local start = Instance.new("Frame")
    start.Name = "StartBox"
    start.BackgroundTransparency = 1
    start.AnchorPoint = Vector2.new(0.5, 0)
    start.Position = UDim2.new(0.5, 0, 0, 10)
    start.Parent = root
    self.start = start
    -- 画面が細い時(スマホの縦持ち)は、枠ごと縮めて画面に収める
    self.startScale = Instance.new("UIScale")
    self.startScale.Parent = start
    -- 練習用の板(バーと文字を載せる)
    local plate = panel(start, "AssistPlate", 0.15)
    plate.BackgroundColor3 = Color3.fromRGB(12, 15, 22)
    plate.Size = UDim2.fromScale(1, 1)
    corner(plate, 18)
    stroke(plate, CHAMPAGNE, 1, 0.55)
    self.plate = plate
    -- 文字盤(大きさは枠に合わせて伸び縮みするよう、中身はすべて割合で置く)
    local dial = Instance.new("Frame")
    dial.Name = "Dial"
    dial.BackgroundTransparency = 1
    dial.Parent = start
    self.dial = dial
    local round = Instance.new("UICorner")
    round.CornerRadius = UDim.new(0.5, 0)
    local shadow = Instance.new("Frame")
    shadow.Name = "Shadow"
    shadow.AnchorPoint = Vector2.new(0.5, 0.5)
    shadow.Position = UDim2.new(0.5, 0, 0.5, 3)
    shadow.Size = UDim2.fromScale(1.04, 1.04)
    shadow.BackgroundColor3 = Color3.new(0, 0, 0)
    shadow.BackgroundTransparency = 0.6
    shadow.BorderSizePixel = 0
    shadow.Parent = dial
    round:Clone().Parent = shadow
    self.shadow = shadow
    -- 文字盤: 観客席の大時計(VenueDecor の clock)と同じ形。黒い縁・白い面・60の目盛り・0〜11の数字・
    -- オレンジの長い針(12秒で1周)と黒い短い針(60秒で1周)・黒い真ん中
    local DIAL_DARK = Color3.fromHex("232d36")
    local DIAL_WHITE = Color3.fromHex("f6f4eb")
    local DIAL_ORANGE = Color3.fromHex("e9a20d")
    local face = Instance.new("Frame")
    face.Name = "Clock"
    face.Size = UDim2.fromScale(1, 1)
    face.BackgroundColor3 = DIAL_DARK
    face.BorderSizePixel = 0
    face.ZIndex = 2
    face.Parent = dial
    round:Clone().Parent = face
    local white = Instance.new("Frame")
    white.Name = "Face"
    white.AnchorPoint = Vector2.new(0.5, 0.5)
    white.Position = UDim2.fromScale(0.5, 0.5)
    white.Size = UDim2.fromScale(0.954, 0.954)
    white.BackgroundColor3 = DIAL_WHITE
    white.BorderSizePixel = 0
    white.ZIndex = 2
    white.Parent = face
    round:Clone().Parent = white
    -- 中心から角度 angle の方向へ、割合 radius の位置に置く(部品は自分の真ん中で回すので、向きもそろう)
    local function onRim(item, angle, radius)
        local r = math.rad(angle)
        item.AnchorPoint = Vector2.new(0.5, 0.5)
        item.Position = UDim2.fromScale(0.5 + math.sin(r) * radius, 0.5 - math.cos(r) * radius)
        item.Rotation = angle
    end
    -- 0〜1秒(スタートしてよい範囲): 縁のすぐ内側の細い緑の弧(大時計にはないが、目安として残す)
    for k = 0, 20 do
        local seg = Instance.new("Frame")
        seg.Size = UDim2.fromScale(0.026, 0.026)
        seg.BackgroundColor3 = Color3.fromRGB(40, 170, 95)
        seg.BorderSizePixel = 0
        seg.ZIndex = 3
        onRim(seg, k * 30 / 20, 0.462)
        seg.Parent = face
    end
    -- 目盛り(大時計と同じ太さ・長さ)と数字
    for i = 0, 59 do
        local major = i % 5 == 0
        local tick = Instance.new("Frame")
        tick.Name = "Tick" .. i
        tick.Size = major and UDim2.fromScale(0.017, 0.075) or UDim2.fromScale(0.006, 0.033)
        tick.BackgroundColor3 = DIAL_DARK
        tick.BorderSizePixel = 0
        tick.ZIndex = 4
        onRim(tick, i * 6, 0.431)
        tick.Parent = face
        if major then
            local number = text(face, "Number" .. i, 14, nil, DIAL_DARK)
            number.Text = tostring(i // 5)
            number.TextScaled = true
            number.TextStrokeTransparency = 1
            number.TextXAlignment = Enum.TextXAlignment.Center
            number.Size = UDim2.fromScale(0.11, 0.092)
            number.ZIndex = 4
            local r = math.rad(i * 6)
            number.AnchorPoint = Vector2.new(0.5, 0.5)
            number.Position = UDim2.fromScale(0.5 + math.sin(r) * 0.326, 0.5 - math.cos(r) * 0.326)
        end
    end
    -- 残り秒数の小さな字(真ん中と「6」の間)
    local digital = text(face, "Digital", 14, DIAL_FONT, DIAL_DARK)
    digital.TextStrokeTransparency = 1
    digital.TextScaled = true
    digital.AnchorPoint = Vector2.new(0.5, 0.5)
    digital.Position = UDim2.fromScale(0.5, 0.66)
    digital.Size = UDim2.fromScale(0.3, 0.09)
    digital.TextXAlignment = Enum.TextXAlignment.Center
    digital.ZIndex = 4
    self.digital = digital
    -- 針: 文字盤と同じ大きさの透明な枠ごと回す(Frame の Rotation は自分の真ん中で回るため)。
    -- 大時計と同じく、根元が真ん中より少し先まで出る
    local function makeHand(name, length, width, color, z)
        local holder = Instance.new("Frame")
        holder.Name = name
        holder.AnchorPoint = Vector2.new(0.5, 0.5)
        holder.Position = UDim2.fromScale(0.5, 0.5)
        holder.Size = UDim2.fromScale(1, 1)
        holder.BackgroundTransparency = 1
        holder.ZIndex = z
        holder.Parent = face
        local bar = Instance.new("Frame")
        bar.AnchorPoint = Vector2.new(0.5, 0)
        bar.Position = UDim2.fromScale(0.5, 0.5 - length)
        bar.Size = UDim2.fromScale(width, length + 0.06)
        bar.BackgroundColor3 = color
        bar.BorderSizePixel = 0
        bar.ZIndex = z
        bar.Parent = holder
        return holder
    end
    self.slowHand = makeHand("SlowHand", 0.31, 0.018, DIAL_DARK, 5)
    local hand = makeHand("Hand", 0.415, 0.032, DIAL_ORANGE, 6)
    local cap = Instance.new("Frame")
    cap.AnchorPoint = Vector2.new(0.5, 0.5)
    cap.Position = UDim2.fromScale(0.5, 0.5)
    cap.Size = UDim2.fromScale(0.044, 0.044)
    cap.BackgroundColor3 = DIAL_DARK
    cap.BorderSizePixel = 0
    cap.ZIndex = 7
    cap.Parent = face
    round:Clone().Parent = cap
    self.hand = hand
    self.champagne, self.ivory = DIAL_ORANGE, DIAL_DARK
    -- 練習用の文字とバー
    local info = Instance.new("Frame")
    info.Name = "AssistInfo"
    info.BackgroundTransparency = 1
    info.Position = UDim2.fromOffset(134, 12)
    info.Size = UDim2.new(1, -146, 1, -24)
    info.Parent = start
    self.assistInfo = info
    self.cd = text(info, "Countdown", 22, NUMBER_FONT)
    self.cd.Size = UDim2.new(1, 0, 0, 26)
    self.cd.TextXAlignment = Enum.TextXAlignment.Left
    self.dist = text(info, "Distance", 13, BOLD_FONT, SUB)
    self.dist.Position = UDim2.fromOffset(0, 28)
    self.dist.Size = UDim2.new(1, 0, 0, 18)
    self.dist.TextXAlignment = Enum.TextXAlignment.Left
    local bar = Instance.new("Frame")
    bar.Name = "AssistBar"
    bar.Position = UDim2.fromOffset(0, 58)
    bar.Size = UDim2.new(1, -6, 0, 10)
    bar.BackgroundColor3 = WHITE
    bar.ClipsDescendants = false
    bar.Parent = info
    corner(bar, 5)
    -- 色の帯: フライング(赤) / ST 0〜0.25(緑) / 0.25〜0.5(黄) / 遅い(灰)。ブラウザ版と同じ割合
    local g = Instance.new("UIGradient")
    local red, green, yellow, gray = Color3.fromRGB(200, 52, 44), Color3.fromRGB(56, 178, 110), Color3.fromRGB(214, 172, 40), Color3.fromRGB(92, 98, 112)
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, red), ColorSequenceKeypoint.new(0.332, red),
        ColorSequenceKeypoint.new(0.334, green), ColorSequenceKeypoint.new(0.499, green),
        ColorSequenceKeypoint.new(0.501, yellow), ColorSequenceKeypoint.new(0.659, yellow),
        ColorSequenceKeypoint.new(0.661, gray), ColorSequenceKeypoint.new(1, gray),
    })
    g.Parent = bar
    local marker = Instance.new("Frame")
    marker.Name = "Marker"
    marker.AnchorPoint = Vector2.new(0.5, 0.5)
    marker.Position = UDim2.fromScale(0.5, 0.5)
    marker.Size = UDim2.fromOffset(4, 22)
    marker.BackgroundColor3 = IVORY
    marker.ZIndex = 2
    marker.Parent = bar
    corner(marker, 2)
    stroke(marker, Color3.new(0, 0, 0), 1, 0.4)
    self.marker = marker
    self.assist = text(info, "Assist", 14)
    self.assist.Position = UDim2.fromOffset(0, 80)
    self.assist.Size = UDim2.new(1, 0, 0, 20)
    self.assist.TextXAlignment = Enum.TextXAlignment.Left
    self:setAssist(false)

    -- 右下: 速度計(大きな斜体の数字と、色の付いた棒)
    local speed = Instance.new("Frame")
    speed.Name = "Speedo"
    speed.BackgroundTransparency = 1
    speed.AnchorPoint = Vector2.new(1, 1)
    speed.Size = UDim2.fromOffset(200, 74)
    speed.Parent = root
    self.speedo = speed
    self.spd = text(speed, "Speed", 56, NUMBER_FONT)
    self.spd.Size = UDim2.new(1, -52, 0, 56)
    self.spd.TextXAlignment = Enum.TextXAlignment.Right
    local unit = text(speed, "Unit", 16)
    unit.Size = UDim2.fromOffset(48, 20)
    unit.Position = UDim2.new(1, -48, 0, 34)
    unit.Text = "km/h"
    local track = Instance.new("Frame")
    track.Name = "Track"
    track.Position = UDim2.new(0, 10, 0, 62)
    track.Size = UDim2.new(1, -10, 0, 8)
    track.BackgroundColor3 = WHITE
    track.BackgroundTransparency = 0.78
    track.ClipsDescendants = true
    track.Parent = speed
    corner(track, 4)
    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.Size = UDim2.fromScale(0, 1)
    fill.BackgroundColor3 = WHITE
    fill.Parent = track
    corner(fill, 4)
    local fg = Instance.new("UIGradient")
    fg.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(77, 210, 255)),
        ColorSequenceKeypoint.new(0.7, Color3.fromRGB(255, 225, 77)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 90, 60)),
    })
    fg.Parent = fill
    self.spdFill = fill

    -- 下中央: 風と波
    local wx = panel(root, "Weather", 0.45)
    wx.AnchorPoint = Vector2.new(0.5, 1)
    wx.Position = UDim2.new(0.5, 0, 1, -14)
    wx.Size = UDim2.fromOffset(220, 26)
    corner(wx, 8)
    self.wxArrow = text(wx, "Arrow", 13, BOLD_FONT, Color3.fromRGB(127, 216, 255))
    self.wxArrow.Size = UDim2.fromOffset(22, 26)
    self.wxArrow.Position = UDim2.fromOffset(8, 0)
    self.wxArrow.Text = "▲"
    self.wxText = text(wx, "Text", 14)
    self.wxText.Position = UDim2.fromOffset(32, 0)
    self.wxText.Size = UDim2.new(1, -40, 1, 0)
    self.wxText.TextXAlignment = Enum.TextXAlignment.Left
    self.wx = wx

    -- 中央上寄り: 大きな知らせ
    local msg = text(root, "Message", 54, NUMBER_FONT)
    msg.AnchorPoint = Vector2.new(0.5, 0.5)
    msg.Position = UDim2.fromScale(0.5, 0.27)
    msg.Size = UDim2.fromOffset(600, 64)
    msg.TextStrokeTransparency = 0.25
    msg.TextStrokeColor3 = Color3.fromRGB(0, 20, 60)
    self.msg = msg
    local sub = text(root, "MessageSub", 22)
    -- 明るい看板や空の上でも読めるように、縁取りを濃くする
    sub.TextStrokeTransparency = 0.15
    sub.TextStrokeColor3 = Color3.fromRGB(0, 20, 60)
    sub.AnchorPoint = Vector2.new(0.5, 0)
    sub.Position = UDim2.new(0.5, 0, 0.27, 34)
    sub.Size = UDim2.fromOffset(600, 30)
    self.msgSub = sub
    msg.Visible, sub.Visible = false, false
    return self
end

-- 大きな知らせを数秒だけ出す(ST、周回、ゴール、フライング、沈没)
function Hud:flash(big, small, color, seconds)
    self.msg.Text, self.msgSub.Text = big or "", small or ""
    self.msg.TextColor3 = color or WHITE
    self.flashUntil = os.clock() + (seconds or 2.2)
end

-- 画面の大きさに合わせて配置を変える(スマホの横持ち・縦持ちでは小さく)
function Hud:layout()
    local size = self.gui.AbsoluteSize
    local compact = size.X < 760 or size.Y < 460
    local portrait = size.X < size.Y
    self.compact = compact
    self.map.Position = UDim2.fromOffset(16, 142)
    self.map.Size = compact and UDim2.fromOffset(170, 45) or UDim2.fromOffset(230, 61)
    self.order.Position = UDim2.new(1, compact and -16 or -166, 0, compact and 52 or 62)
    self.order.AnchorPoint = compact and Vector2.new(1, 0) or Vector2.new(0, 0)
    self.order.Size = compact and UDim2.fromOffset(6 * 27, 26) or UDim2.fromOffset(150, 6 * 30)
    for i, row in ipairs(self.orderRows) do
        if compact then
            row.frame.Position = UDim2.fromOffset((i - 1) * 27, 0)
            row.frame.Size = UDim2.fromOffset(24, 26)
            row.frame.BackgroundTransparency = 1
            row.chip.Position = UDim2.fromOffset(2, 3)
        else
            row.frame.Position = UDim2.fromOffset(0, (i - 1) * 30)
            row.frame.Size = UDim2.fromOffset(150, 26)
            row.frame.BackgroundTransparency = 0.38
            row.chip.Position = UDim2.fromOffset(22, 3)
        end
        row.mark.Visible, row.name.Visible = not compact, not compact
    end
    -- 速度計はスロットルレバー(右下、幅74)の左。縦持ちはレバーの上
    self.speedo.Position = portrait and UDim2.new(1, -14, 1, -200) or UDim2.new(1, -106, 1, -14)
    self.speedo.Size = compact and UDim2.fromOffset(150, 60) or UDim2.fromOffset(200, 74)
    self.spd.TextSize = compact and 42 or 56
    -- スタートの枠は、縦持ちでは順位の下へ
    self.start.Position = portrait and UDim2.new(0.5, 0, 0, 140) or UDim2.new(0.5, 0, 0, 10)
    self:fitStart()
    self.wx.Position = UDim2.new(0.5, 0, 1, portrait and -100 or -14)
end

-- スタートの枠が画面の幅に入るように縮める(入る時はそのまま)
function Hud:fitStart()
    local full = self.assistMode and 400 or 136
    self.startScale.Scale = math.min(1, (self.gui.AbsoluteSize.X - 16) / full)
end

-- スタート前の枠の形: 練習(時計 + 予想STのバー)か、時計だけ(ランク戦・オンライン・大会など)
function Hud:setAssist(on)
    self.assistMode = on
    self.plate.Visible = on
    self.assistInfo.Visible = on
    self.shadow.Visible = not on
    if on then
        self.start.Size = UDim2.fromOffset(400, 128)
        self.dial.Position = UDim2.fromOffset(8, 8)
        self.dial.Size = UDim2.fromOffset(112, 112)
    else
        self.start.Size = UDim2.fromOffset(136, 136)
        self.dial.Position = UDim2.fromOffset(0, 0)
        self.dial.Size = UDim2.fromOffset(136, 136)
    end
    self:fitStart()
end

-- 毎フレームの更新。info の中身は Controls.client.lua が作る
function Hud:update(info)
    self.root.Visible = info.visible
    if not info.visible then
        return
    end
    -- 順位(1着は金、失格は赤)
    local rank = info.rank
    if info.out then
        self.posN.Text, self.posUnit.Text = T(info.out), ""
        self.posGradient.Color = ColorSequence.new(Color3.fromRGB(150, 30, 30), Color3.fromRGB(90, 10, 10))
    else
        self.posN.Text, self.posUnit.Text = tostring(rank or "-"), T("着")
        if rank == 1 then
            self.posGradient.Color = ColorSequence.new(Color3.fromRGB(226, 164, 0), Color3.fromRGB(165, 95, 0))
        else
            self.posGradient.Color = ColorSequence.new(Color3.fromRGB(23, 58, 122), NAVY)
        end
    end
    self.pos.Visible = info.rank ~= nil or info.out ~= nil
    self.lap.Text = T(info.lapText or "")
    self.time.Text = info.time and formatTime(info.time) or ""
    -- スタート前の枠
    self.start.Visible = info.pre == true
    -- スタート前は大時計が残り時間を出す。左上の「スタート前」と時間が大時計の枠と重なる時(スマホの横持ちなど)は隠す
    local hideTop = false
    if info.pre then
        local left = self.start.AbsolutePosition.X
        local right = self.lap.AbsolutePosition.X + math.max(self.lap.TextBounds.X, self.time.TextBounds.X) + 12
        hideTop = left < right and self.start.AbsolutePosition.Y < self.time.AbsolutePosition.Y + self.time.AbsoluteSize.Y
    end
    self.lap.Visible, self.time.Visible = not hideTop, not hideTop
    if info.pre then
        local t = info.clock or 0
        if (info.assist == true) ~= self.assistMode then
            self:setAssist(info.assist == true)
        end
        -- 針の角度は観客席の大時計と同じ式(VenueBoard.angles)
        self.hand.Rotation = (t % 12) * 30
        self.slowHand.Rotation = (t % 60) * 6
        self.digital.Text = t < 0 and string.format("%.1f", -t) or string.format("+%.1f", t)
        self.digital.TextColor3 = t > -3 and self.champagne or self.ivory
        self.cd.Text = t < 0 and T(string.format("スタートまで %.1f", -t)) or string.format("+%.2f", t)
        self.cd.TextColor3 = t > -3 and GOLD or WHITE
        self.dist.Text = info.dist and T(string.format("スタートラインまで %d m", math.max(0, math.floor(info.dist + 0.5)))) or ""
        local st = info.st
        self.marker.Visible = st ~= nil
        if st then
            self.marker.Position = UDim2.fromScale(math.clamp((st + 0.5) / 1.5, 0, 1), 0.5)
            if st < 0 then
                self.assist.Text, self.assist.TextColor3 = T(string.format("全開だと %.2f秒 早い(フライング)", -st)), Color3.fromRGB(255, 138, 122)
            elseif st < 0.25 then
                self.assist.Text, self.assist.TextColor3 = T(string.format("今だ！ 全開で ST %.2f", st)), GREEN
            else
                self.assist.Text, self.assist.TextColor3 = T(string.format("全開で ST %.2f", st)), WHITE
            end
        else
            self.assist.Text = T(info.hint or "")
            self.assist.TextColor3 = SUB
        end
    end
    -- 順位表
    self.order.Visible = info.order ~= nil
    if info.order then
        for i, row in ipairs(self.orderRows) do
            local o = info.order[i]
            row.frame.Visible = o ~= nil
            if o then
                row.chip.Text = tostring(o.lane)
                row.chip.BackgroundColor3, row.chip.TextColor3 = LANE[o.lane][1], LANE[o.lane][2]
                row.mark.Text = o.mark
                row.name.Text = T(o.name)
                local me = o.me
                if not self.compact then
                    row.frame.BackgroundColor3 = me and GOLD or Color3.fromRGB(8, 24, 48)
                    row.frame.BackgroundTransparency = me and 0.08 or 0.38
                end
                row.name.TextColor3 = me and Color3.fromRGB(17, 17, 17) or WHITE
                row.mark.TextColor3 = me and Color3.fromRGB(17, 17, 17) or (o.out and RED or WHITE)
                row.name.TextStrokeTransparency = me and 1 or 0.55
                row.mark.TextStrokeTransparency = me and 1 or 0.55
                local outline = row.chip:FindFirstChildOfClass("UIStroke")
                outline.Color = (self.compact and me) and GOLD or WHITE
                outline.Thickness = (self.compact and me) and 2 or 1
            end
        end
    end
    -- 前後との秒差
    for k, g in ipairs(self.gaps) do
        local item = info.gaps and info.gaps[k]
        g.frame.Visible = item ~= nil
        if item then
            g.chip.Text = tostring(item.lane)
            g.chip.BackgroundColor3, g.chip.TextColor3 = LANE[item.lane][1], LANE[item.lane][2]
            g.value.Text = T(item.text)
        end
    end
    -- ミニマップ
    self.map.Visible = info.boats ~= nil and not (self.compact and info.pre)
    if info.boats then
        local w, h = self.map.AbsoluteSize.X, self.map.AbsoluteSize.Y
        local function at(x, z)
            return UDim2.fromOffset((x - MIN_X) / (MAX_X - MIN_X) * w, (z - MIN_Z) / (MAX_Z - MIN_Z) * h)
        end
        local lineTop = (4 - MIN_Z) / (MAX_Z - MIN_Z) * h
        self.mapLine.Position = UDim2.fromOffset((0 - MIN_X) / (MAX_X - MIN_X) * w, lineTop)
        self.mapLine.Size = UDim2.fromOffset(1, h - lineTop)
        for _, m in ipairs(self.mapMarks) do
            m.frame.Position = at(m.x, m.z)
        end
        for lane, dot in ipairs(self.mapDots) do
            local b = info.boats[lane]
            dot.Visible = b ~= nil and not b.hidden and not b.me
            if b then
                dot.Position = at(b.x, b.z)
            end
            if b and b.me and not b.hidden then
                self.mapMe.Position = at(b.x, b.z)
                -- ▲ は上向きなので、右向き(向き 0)に合わせて90°足す
                self.mapMe.Rotation = math.deg(b.h) + 90
            end
        end
        self.mapMe.Visible = info.myLane ~= nil
    end
    -- 速度計
    self.speedo.Visible = info.speed ~= nil
    if info.speed then
        self.spd.Text = tostring(math.floor(info.speed + 0.5))
        self.spdFill.Size = UDim2.fromScale(math.clamp(info.speed / 82, 0, 1), 1)
    end
    -- 風と波
    self.wx.Visible = info.wind ~= nil
    if info.wind then
        self.wxText.Text = T(info.wind)
        self.wxArrow.Rotation = (info.windRotation or 0) + 90
        self.wx.Size = UDim2.fromOffset(math.max(160, 56 + game:GetService("TextService"):GetTextSize(T(info.wind), 14, Enum.Font.GothamBold, Vector2.new(2000, 100)).X), 26)
    end
    -- 大きな知らせ
    local showing = os.clock() < self.flashUntil
    self.msg.Visible, self.msgSub.Visible = showing, showing and self.msgSub.Text ~= ""
end

return Hud
