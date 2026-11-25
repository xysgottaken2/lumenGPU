-- Run in Studio Edit mode Command Bar, then enable HTTP and start a local Play test.
local RS=game:GetService('RunService')
assert(RS:IsStudio() and not RS:IsRunning(),'Stop Play mode before installing')
local ss=game:GetService('ServerScriptService')
local rp=game:GetService('ReplicatedStorage')
local sp=game:GetService('StarterPlayer'):WaitForChild('StarterPlayerScripts')
for _,pair in {{ss,'LumenGPU_Server'},{rp,'LumenGPU_Camera'},{sp,'LumenGPU_Client'}} do
    local old=pair[1]:FindFirstChild(pair[2]); assert(not old or old:GetAttribute('LumenGPUInstaller')==true,'Name collision: '..pair[2])
end
local function make(parent,class,name,source)
    local old=parent:FindFirstChild(name); if old then old:Destroy() end
    local obj=Instance.new(class); obj.Name=name; obj:SetAttribute('LumenGPUInstaller',true); if source then obj.Source=source end; obj.Parent=parent; return obj
end
make(rp,'RemoteEvent','LumenGPU_Camera')
make(sp,'LocalScript','LumenGPU_Client',[====[
local RunService=game:GetService('RunService')
if not RunService:IsStudio() then return end
local remote=game:GetService('ReplicatedStorage'):WaitForChild('LumenGPU_Camera')
local UIS=game:GetService('UserInputService')
local active=false
local player=game:GetService('Players').LocalPlayer
local external=false
local input={}
local lastInput=0
local yaw,pitch=0,0
local orbitDistance=10
local controls=nil
local oldCameraType=nil
local gui=Instance.new('ScreenGui'); gui.Name='LumenGPUConnection';gui.ResetOnSpawn=false;gui.DisplayOrder=100;gui.Parent=player:WaitForChild('PlayerGui')
local button=Instance.new('TextButton');button.Name='Toggle';button.Size=UDim2.fromOffset(240,34);button.Position=UDim2.new(1,-252,0,12);button.BackgroundColor3=Color3.fromRGB(35,45,57);button.TextColor3=Color3.new(1,1,1);button.TextSize=14;button.Font=Enum.Font.GothamMedium;button.Text='LUMEN GPU: Start (P)';button.Parent=gui
local lastAck=0
local lastRetry=0
local status='Waiting for bridge'
local lastControlLog=0
local playerModule=player:WaitForChild('PlayerScripts'):FindFirstChild('PlayerModule')
if playerModule then local ok,m=pcall(require,playerModule); if ok then local success,ctrl=pcall(function() return m:GetControls() end); if success then controls=ctrl end end end
local function release()
    if not external then return end
    external=false; input={}
    if controls then pcall(function() controls:Enable() end) end
    local cam=workspace.CurrentCamera; if cam then cam.CameraType=oldCameraType or Enum.CameraType.Custom end
    local hum=player.Character and player.Character:FindFirstChildOfClass('Humanoid'); if hum then hum:Move(Vector3.zero,false) end
end
remote.OnClientEvent:Connect(function(kind,c)
    if kind=='status' and active then
        status=tostring(c);lastAck=os.clock();return
    end
    if kind~='input' or not active or type(c)~='table' then return end
    lastAck=os.clock();status=c.active and string.format('Input ON [%d,%d]',c.x or 0,c.z or 0) or 'Connected / Input OFF'
    if not c.active then release();return end
    lastInput=os.clock()
    if os.clock()-lastControlLog>2 then lastControlLog=os.clock();print('[LumenGPU] Input received: ',c.x,c.z,c.dx,c.dy) end
    local cam=workspace.CurrentCamera; if not cam then return end
    if not external then
        local look=cam.CFrame.LookVector; yaw=math.atan2(-look.X,-look.Z); pitch=math.asin(math.clamp(look.Y,-1,1))
        local char=player.Character;local head=char and char:FindFirstChild('Head')
        if head then orbitDistance=math.clamp((cam.CFrame.Position-head.Position).Magnitude,6,20) end
        oldCameraType=cam.CameraType; external=true
        if controls then pcall(function() controls:Disable() end) end
        cam.CameraType=Enum.CameraType.Scriptable
    end
    yaw-=math.clamp(c.dx or 0,-2000,2000)*.0025; pitch=math.clamp(pitch-math.clamp(c.dy or 0,-2000,2000)*.0025,-1.15,1.15)
    input=c;lastInput=os.clock()
    local hum=player.Character and player.Character:FindFirstChildOfClass('Humanoid'); if hum and c.jump then hum.Jump=true end
end)
local function vec(v) return {v.X,v.Y,v.Z} end
local function avatarSnapshot()
    local list={};local char=player.Character;if not char then return list end
    for _,obj in char:GetDescendants() do
        if obj:IsA('BasePart') and obj.Name~='HumanoidRootPart' and obj.Transparency<.95 and obj:GetAttribute('PathIgnore')~=true and #list<64 then
            local c=obj.CFrame;local color=obj.Color
            list[#list+1]={p=vec(c.Position),r=vec(c.RightVector),u=vec(c.UpVector),b=vec(c.ZVector),s=vec(obj.Size),c={color.R,color.G,color.B},metal=math.clamp(obj.Reflectance,0,1),rough=.55,emit=0}
        end
    end
    return list
end
local function toggle()
    active=not active
    if not active then release() else status='Connecting';lastAck=0;lastRetry=os.clock() end
    remote:FireServer(active and 'start' or 'stop')
    button.Text=active and 'LUMEN GPU: Connecting...' or 'LUMEN GPU: Start (P)'
    print('[LumenGPU] '..(active and 'Streaming on' or 'Streaming off'))
end
button.Activated:Connect(toggle)
UIS.InputBegan:Connect(function(i,processed)
    if i.KeyCode==Enum.KeyCode.P and not UIS:GetFocusedTextBox() then toggle() end
end)
local elapsed=0
-- Heartbeat continues independently of presentation/render-step scheduling.
RunService.Heartbeat:Connect(function(dt)
    if not active then return end
    local now=os.clock()
    if now-lastAck>2 and now-lastRetry>2 then lastRetry=now;remote:FireServer('start') end
    button.Text='LUMEN GPU: '..(now-lastAck>2 and 'Connecting...' or status)..' (Stop)'
    if external then
        if os.clock()-lastInput>.65 then release() else
            local char=player.Character;local head=char and char:FindFirstChild('Head');local hum=char and char:FindFirstChildOfClass('Humanoid');local cam=workspace.CurrentCamera
            if head and hum and cam then
                local rot=CFrame.fromOrientation(0,yaw,0);local look=rot*CFrame.Angles(pitch,0,0)
                local move=rot.RightVector*math.clamp(input.x or 0,-1,1)+rot.LookVector*math.clamp(input.z or 0,-1,1)
                hum:Move(move.Magnitude>1 and move.Unit or move,false)
                local pivot=head.Position+Vector3.new(0,.5,0)
                local offset=-look.LookVector*orbitDistance
                local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={char};params.RespectCanCollide=true
                local hit=workspace:Raycast(pivot,offset,params)
                if hit then offset=offset.Unit*math.max(.35,hit.Distance-.35) end
                cam.CFrame=CFrame.new(pivot+offset)*look;cam.Focus=CFrame.new(pivot)
            end
        end
    end
    elapsed+=dt; if elapsed<.10 then return end; elapsed=0
    local cam=workspace.CurrentCamera; if not cam then return end
    local c=cam.CFrame; remote:FireServer('camera',{p=vec(c.Position),r=vec(c.RightVector),u=vec(c.UpVector),f=vec(c.LookVector),fov=cam.FieldOfView},avatarSnapshot())
end)
print('[LumenGPU] Press P to toggle local scene streaming')
]====])
make(ss,'Script','LumenGPU_Server',[====[
local RunService=game:GetService('RunService')
if not RunService:IsStudio() then return end
local HTTP=game:GetService('HttpService')
local Lighting=game:GetService('Lighting')
local Players=game:GetService('Players')
local remote=game:GetService('ReplicatedStorage'):WaitForChild('LumenGPU_Camera')
local owner,latest=nil,nil
local latestAvatar={}
local lastSnapshot=-100
local lastPartsJSON=nil
local function vec(v) return {v.X,v.Y,v.Z} end
local function numeric(a,default,lo,hi) if type(a)~='number' or a~=a then return default end; return math.clamp(a,lo,hi) end
local function snapshot(pos)
    local items={}
    for _,obj in workspace:GetDescendants() do
        if obj:IsA('BasePart') and obj.Transparency<.95 and obj.Size.Magnitude>0 and obj:GetAttribute('PathIgnore')~=true and not (owner and owner.Character and obj:IsDescendantOf(owner.Character)) then
            local localPos=obj.CFrame:PointToObjectSpace(pos);local half=obj.Size*.5
            -- A mesh approximated as a box can incorrectly enclose the entire camera.
            if math.abs(localPos.X)<half.X and math.abs(localPos.Y)<half.Y and math.abs(localPos.Z)<half.Z then continue end
            local c=obj.CFrame; local size=obj.Size; local color=obj.Color
            local distance=(c.Position-pos).Magnitude-math.max(size.X,size.Y,size.Z)*.5
            local metal=numeric(obj:GetAttribute('PathMetallic'),obj.Reflectance,0,1)
            local rough=numeric(obj:GetAttribute('PathRoughness'),.45,0,1)
            local emit=numeric(obj:GetAttribute('PathEmission'),obj.Material==Enum.Material.Neon and 3 or 0,0,50)
            items[#items+1]={distance=distance,data={p=vec(c.Position),r=vec(c.RightVector),u=vec(c.UpVector),b=vec(c.ZVector),s=vec(size),c={color.R,color.G,color.B},metal=metal,rough=rough,emit=emit}}
        end
    end
    table.sort(items,function(a,b) return a.distance<b.distance end)
    local out={}; for i=1,math.min(960,#items) do out[i]=items[i].data end; return out
end
remote.OnServerEvent:Connect(function(player,cmd,data,avatar)
    if cmd=='start' and (not owner or owner==player) then
        if not owner then owner=player; latest=nil; latestAvatar={}; lastSnapshot=-100; lastPartsJSON=nil; print('[LumenGPU] Local bridge started') end
        remote:FireClient(player,'status','Waiting for HTTP')
    elseif cmd=='stop' and owner==player then owner=nil; latest=nil
    elseif cmd=='camera' and owner==player and type(data)=='table' then
        if type(data.p)=='table' and #data.p==3 and type(data.r)=='table' and #data.r==3 and type(data.u)=='table' and #data.u==3 and type(data.f)=='table' and #data.f==3 and type(data.fov)=='number' then latest=data; if type(avatar)=='table' and #avatar<=64 then latestAvatar=avatar end end
    end
end)
Players.PlayerRemoving:Connect(function(p) if p==owner then owner=nil; latest=nil end end)
local lastError=-100
while task.wait(.135) do
    if owner and latest then
        local ok,err=pcall(function()
            local now=os.clock(); local update={camera=latest,sun=vec(Lighting:GetSunDirection()),avatar=latestAvatar}; local newJSON=nil
            if now-lastSnapshot>=.65 then
                lastSnapshot=now
                local p=latest.p; local parts=snapshot(Vector3.new(p[1],p[2],p[3])); newJSON=HTTP:JSONEncode(parts)
                if newJSON~=lastPartsJSON then update.parts=parts end
            end
            local result=HTTP:RequestAsync({Url='http://127.0.0.1:8765/api/update-controls',Method='POST',Headers={['Content-Type']='application/json'},Body=HTTP:JSONEncode(update)})
            if not result.Success then error('HTTP '..result.StatusCode..' '..result.Body) end
            if owner then
                if result.StatusCode==204 or result.Body=='' then remote:FireClient(owner,'status','Old bridge - update EXE')
                else local ctrl=HTTP:JSONDecode(result.Body);remote:FireClient(owner,'input',ctrl) end
            end
            if newJSON then lastPartsJSON=newJSON end
        end)
        if not ok and os.clock()-lastError>2 then
            lastError=os.clock();warn('[LumenGPU] '..tostring(err)..' | Start EXE, enable HTTP Requests, use local Studio Play.')
            if owner then remote:FireClient(owner,'status','HTTP error - see Output') end
        end
    end
end
]====])
print('LUMEN GPU 0.2.3 installed. Enable HTTP Requests, start LumenBridge.exe and the native renderer, Play locally and press P. Existing LUMEN installations are not removed; stop their renderer.')
