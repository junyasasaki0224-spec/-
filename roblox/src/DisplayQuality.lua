local input=game:GetService("UserInputService")
local lighting=game:GetService("Lighting")
local Quality={scale=1}
local connections={}
local function effective(choice)
    if choice=="auto" or not choice then return input.TouchEnabled and "low" or "high" end
    return choice
end
function Quality.apply(choice)
    local level=effective(choice)
    Quality.scale=level=="low" and .35 or level=="medium" and .65 or 1
    local function apply(obj)
        if obj:IsA("BloomEffect") then obj.Enabled=level~="low"
        elseif obj:IsA("SunRaysEffect") then obj.Enabled=level=="high"
        elseif obj:IsA("PointLight") and obj.Name=="QuayFlood" then
            local function refresh()
                local enabled=Quality.scale>.35 and obj.Brightness>0
                if obj.Enabled~=enabled then obj.Enabled=enabled end
            end
            refresh()
            if not connections[obj] then
                connections[obj]=true
                obj:GetPropertyChangedSignal("Brightness"):Connect(refresh)
                obj:GetPropertyChangedSignal("Enabled"):Connect(refresh)
                obj.Destroying:Once(function() connections[obj]=nil end)
            end
        end
    end
    for _,obj in lighting:GetChildren() do apply(obj) end
    for _,obj in workspace.Terrain:GetDescendants() do apply(obj) end
    if not Quality.watch then
        Quality.watch=workspace.Terrain.DescendantAdded:Connect(function(obj)
            if obj:IsA("PointLight") and obj.Name=="QuayFlood" then
                task.defer(function() if obj.Parent then Quality.apply(Quality.choice) end end)
            end
        end)
    end
    Quality.choice=choice
end
return Quality
