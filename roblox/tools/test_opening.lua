-- Run from a Studio client playtest where ReplicatedStorage.Opening is installed.
local Opening=require(game.ReplicatedStorage.Opening)
local player=game.Players.LocalPlayer
local camera=workspace.CurrentCamera
local fixture=Instance.new("Folder")
fixture.Name="OpeningTest"
fixture.Parent=workspace
local boats,goals={},{}
for i=1,6 do
    local boat=Instance.new("Model")
    local hull=Instance.new("Part")
    hull.Anchored=true
    hull.Parent=boat
    boat.PrimaryPart=hull
    boat.Parent=fixture
    boats[i]=boat
    goals[i]=CFrame.new(i*12,2,30)*CFrame.Angles(0,.3*i,0)
end
local dock=Instance.new("Part")
dock.Name="Pit__Blue__01"
dock.Anchored=true
dock.Position=Vector3.new(-200,2,0)
dock.Parent=fixture
local ok,err=pcall(function()
    for _,mode in {"normal","skip","destroy"} do
        local visible=table.clone(boats)
        if mode=="skip" then visible[4]=nil end
        local show=Opening.play({camera=camera,venue=mode=="normal" and fixture or nil,boats=visible,finalCFrames=goals,
            gui=player.PlayerGui,rows={{number=1,name="テスト選手",cls="A1"}},duration=mode=="normal" and 10 or 24})
        local initial=boats[1]:GetPivot()
        local done=0
        show.Done:Connect(function() done+=1 end)
        if mode=="normal" then
            task.wait(6.2)
            assert((boats[1]:GetPivot().Position-initial.Position).Magnitude>1,"boat must move during the shot")
        end
        if mode~="normal" then task.wait(.1);show[mode](show) end
        local deadline=os.clock()+8
        repeat task.wait(.05) until done==1 or os.clock()>deadline
        show:destroy()
        assert(done==1,mode.." done="..done)
        assert(camera.CameraType==Enum.CameraType.Custom,mode.." camera="..tostring(camera.CameraType))
        assert(not player.PlayerGui:FindFirstChild("MinatoOpening"),mode.." gui")
        assert(not workspace:FindFirstChild("MinatoOpeningSpray"),mode.." spray")
        for i,boat in visible do assert(boat:GetPivot():FuzzyEq(goals[i],.0001),mode.." boat "..i) end
    end
end)
fixture:Destroy()
assert(ok,err)
return "normal, skip, destroy OK"
