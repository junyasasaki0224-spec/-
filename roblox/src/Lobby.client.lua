local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("MinatoLeaderboard")
local practice = ReplicatedStorage:WaitForChild("MinatoPractice")
local roomRemote = ReplicatedStorage:WaitForChild("MinatoRoomLobby")

local gui = Instance.new("ScreenGui")
gui.Name="MinatoLobby"
gui.ResetOnSpawn=false
gui.Parent=player:WaitForChild("PlayerGui")
local panel=Instance.new("Frame")
panel.Size=UDim2.new(0.9,0,0.9,0)
panel.Position=UDim2.new(0.05,0,0.05,0)
panel.BackgroundColor3=Color3.fromRGB(17,35,48)
panel.Parent=gui
local corner=Instance.new("UICorner")
corner.CornerRadius=UDim.new(0,12)
corner.Parent=panel

local function text(parent, value, position, size, fontSize)
    local label=Instance.new("TextLabel")
    label.BackgroundTransparency=1
    label.TextColor3=Color3.fromRGB(239,246,246)
    label.Font=Enum.Font.Gotham
    label.TextSize=fontSize
    label.Text=value
    label.Position=position
    label.Size=size
    label.Parent=parent
    return label
end
local title=text(panel,"みなとグランプリ",UDim2.new(0,12,0,8),UDim2.new(1,-24,0,30),20)
title.Font=Enum.Font.GothamBold
local mine=text(panel,"成績を読み込み中",UDim2.new(0,12,0,42),UDim2.new(1,-24,0,42),14)
mine.TextWrapped=true
local tabs=Instance.new("Frame")
tabs.Position=UDim2.new(0,8,0,88)
tabs.Size=UDim2.new(1,-16,0,38)
tabs.BackgroundTransparency=1
tabs.Parent=panel
local buttons={}
local kinds={{"rating","レート"},{"wins","１着数"},{"bestTime","ベストタイム"}}
local selected="rating"
for index,item in ipairs(kinds) do
    local button=Instance.new("TextButton")
    button.Size=UDim2.new(1/3,-4,1,0)
    button.Position=UDim2.new((index-1)/3,2,0,0)
    button.Text=item[2]
    button.TextSize=14
    button.Font=Enum.Font.GothamBold
    button.TextColor3=Color3.new(1,1,1)
    button.BackgroundColor3=Color3.fromRGB(49,89,103)
    button.Parent=tabs
    buttons[item[1]]=button
end
local own=text(panel,"順位を読み込み中",UDim2.new(0,12,0,130),UDim2.new(1,-24,0,30),14)
local list=Instance.new("ScrollingFrame")
list.Position=UDim2.new(0,8,0,164)
list.Size=UDim2.new(1,-16,1,-312)
list.BackgroundTransparency=1
list.ScrollBarThickness=6
list.CanvasSize=UDim2.new()
list.Parent=panel
local layout=Instance.new("UIListLayout")
layout.SortOrder=Enum.SortOrder.LayoutOrder
layout.Parent=list
layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    list.CanvasSize=UDim2.fromOffset(0,layout.AbsoluteContentSize.Y)
end)
local play=Instance.new("TextButton")
play.Size=UDim2.new(1,-24,0,40)
play.Position=UDim2.new(0,12,1,-48)
play.BackgroundColor3=Color3.fromRGB(35,122,137)
play.TextColor3=Color3.new(1,1,1)
play.TextSize=16
play.Font=Enum.Font.GothamBold
play.Text="練習レースへ"
play.Parent=panel
play.Activated:Connect(function() practice:FireServer() end)
practice.OnClientEvent:Connect(function(message) play.Text=message; task.delay(4,function() if play.Parent then play.Text="練習レースへ" end end) end)

local roomRow=Instance.new("Frame")
roomRow.Size=UDim2.new(1,-24,0,38)
roomRow.Position=UDim2.new(0,12,1,-96)
roomRow.BackgroundTransparency=1
roomRow.Parent=panel
local codeBox=Instance.new("TextBox")
codeBox.Size=UDim2.new(0.32,-4,1,0)
codeBox.PlaceholderText="合言葉６文字"
codeBox.Text=player:GetAttribute("MinatoInviteCode") or ""
codeBox.ClearTextOnFocus=false
codeBox.TextSize=14
codeBox.Font=Enum.Font.Gotham
codeBox.Parent=roomRow
player:GetAttributeChangedSignal("MinatoInviteCode"):Connect(function()
    codeBox.Text=player:GetAttribute("MinatoInviteCode") or ""
end)
local function roomButton(caption,x,action)
    local button=Instance.new("TextButton")
    button.Size=UDim2.new(0.34,-4,1,0)
    button.Position=UDim2.new(x,2,0,0)
    button.BackgroundColor3=Color3.fromRGB(49,89,103)
    button.TextColor3=Color3.new(1,1,1)
    button.Font=Enum.Font.GothamBold
    button.TextSize=14
    button.Text=caption
    button.Parent=roomRow
    button.Activated:Connect(function() roomRemote:FireServer(action,codeBox.Text) end)
end
roomButton("部屋を作る",0.32,"create")
roomButton("部屋に入る",0.66,"join")
local roomMessage=text(panel,"合言葉でフレンドと対戦",UDim2.new(0,12,1,-126),UDim2.new(1,-24,0,25),13)
roomRemote.OnClientEvent:Connect(function(message) roomMessage.Text=message end)

local data
local function valueText(kind,value)
    if value == nil then return "未記録" end
    if kind == "bestTime" then
        return string.format("%d:%05.2f",math.floor(value/60),value%60)
    end
    return tostring(value)
end
local function render()
    for kind,button in pairs(buttons) do
        button.BackgroundColor3=kind==selected and Color3.fromRGB(41,139,151) or Color3.fromRGB(49,89,103)
    end
    for _,child in ipairs(list:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
    if not data or not data.profile then
        mine.Text="成績を取得できません。しばらくしてから再確認します"
    else
        local p=data.profile
        mine.Text=string.format("レート %d   出走 %d   １着 %d   ベスト %s",p.rating,p.races,p.wins,valueText("bestTime",p.bestTime))
    end
    local board=data and data.boards[selected]
    if not board or not board.ready then
        own.Text=board and board.error and "ランキングを取得できません" or "ランキングを読み込み中"
        return
    end
    local profile=data.profile
    local score=profile and profile[selected]
    if selected=="bestTime" and score==nil then own.Text="あなたの順位・ベストタイムは未記録です"
    elseif not profile then own.Text="あなたの順位を取得できません"
    elseif board.rank then own.Text="あなたの順位 "..board.rank.."位　"..valueText(selected,score)
    elseif board.below then own.Text="あなたの順位 "..board.below.."位以下　"..valueText(selected,score)
    elseif board.error then own.Text="あなたの順位を取得できません"
    elseif board.busy then own.Text="あなたの順位を集計中"
    else own.Text="あなたの順位は更新待ち" end
    for i,entry in ipairs(board.entries) do
        local row=Instance.new("Frame")
        row.BackgroundTransparency=1
        row.Size=UDim2.new(1,-8,0,32)
        row.LayoutOrder=i
        row.Parent=list
        local name=text(row,string.format("%2d位  %s",i,entry.name or ("選手 "..entry.userId)),UDim2.new(),UDim2.new(0.65,0,1,0),14)
        name.TextXAlignment=Enum.TextXAlignment.Left
        name.TextTruncate=Enum.TextTruncate.AtEnd
        local score=text(row,valueText(selected,entry.value),UDim2.new(0.65,0,0,0),UDim2.new(0.35,-8,1,0),14)
        score.TextXAlignment=Enum.TextXAlignment.Right
    end
end
for kind,button in pairs(buttons) do button.Activated:Connect(function() selected=kind; render() end) end
task.spawn(function()
    while gui.Parent do
        local ok,result=pcall(function() return remote:InvokeServer() end)
        if ok and result then data=result end
        render()
        task.wait(10)
    end
end)
