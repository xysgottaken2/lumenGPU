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
local oldFov=70
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
    local cam=workspace.CurrentCamera; if cam then cam.CameraType=oldCameraType or Enum.CameraType.Custom;cam.FieldOfView=oldFov end
    local hum=player.Character and player.Character:FindFirstChildOfClass('Humanoid'); if hum then hum:Move(Vector3.zero,false) end
end
remote.OnClientEvent:Connect(function(kind,c)
    if kind=='status' and active then
        status=tostring(c);lastAck=os.clock();return
    end
    if kind~='input' or not active or type(c)~='table' then return end
    lastAck=os.clock();status=(c.transport or 'HTTP')..(c.active and string.format(' Input [%d,%d]',c.x or 0,c.z or 0) or ' Connected')
    if not c.active then release();return end
    lastInput=os.clock()
    if os.clock()-lastControlLog>2 then lastControlLog=os.clock();print('[LumenGPU] Input received: ',c.x,c.z,c.dx,c.dy) end
    local cam=workspace.CurrentCamera; if not cam then return end
    if not external then
        local look=cam.CFrame.LookVector; yaw=math.atan2(-look.X,-look.Z); pitch=math.asin(math.clamp(look.Y,-1,1))
        local char=player.Character;local head=char and char:FindFirstChild('Head')
        if head then orbitDistance=math.clamp((cam.CFrame.Position-head.Position).Magnitude,6,20) end
        oldCameraType=cam.CameraType;oldFov=cam.FieldOfView; external=true
        if controls then pcall(function() controls:Disable() end) end
        cam.CameraType=Enum.CameraType.Scriptable
    end
    local sensitivity=math.clamp(c.sensitivity or 1,.1,5)*.0025
    if (c.distance or 0)>0 then orbitDistance=math.clamp(c.distance,2,40) end
    if (c.fov or 0)>0 then cam.FieldOfView=math.clamp(c.fov,35,110) end
    yaw-=math.clamp(c.dx or 0,-2000,2000)*sensitivity; pitch=math.clamp(pitch-math.clamp(c.dy or 0,-2000,2000)*sensitivity,-1.15,1.15)
    input=c;lastInput=os.clock()
    local hum=player.Character and player.Character:FindFirstChildOfClass('Humanoid'); if hum and c.jump then hum.Jump=true end
end)
local function vec(v) return {v.X,v.Y,v.Z} end
local function materialPart(obj)
    local function num(k,v,lo,hi)
        local x=obj:GetAttribute(k);if type(x)~='number' or x~=x then return v end;return math.clamp(x,lo,hi)
    end
    local mat=obj.Material
    local metal=(mat==Enum.Material.Metal or mat==Enum.Material.CorrodedMetal or mat==Enum.Material.DiamondPlate or mat==Enum.Material.Foil) and 1 or 0
    local rough=metal==1 and .28 or .65
    if mat==Enum.Material.Glass or mat==Enum.Material.Ice then rough=.08 end
    if mat~=Enum.Material.Glass then local r=math.clamp(obj.Reflectance,0,1);rough=rough+(.045-rough)*r;metal=math.max(metal,r) end
    local color=obj:GetAttribute('PathBaseColor');if typeof(color)~='Color3' then color=obj.Color end
    local ec=obj:GetAttribute('PathEmissionColor');if typeof(ec)~='Color3' then ec=color end
    local c=obj.CFrame;local shape=0
    if obj:IsA('Part') then if obj.Shape==Enum.PartType.Ball then shape=1 elseif obj.Shape==Enum.PartType.Cylinder then shape=2 end end
    return {p=vec(c.Position),r=vec(c.RightVector),u=vec(c.UpVector),b=vec(c.ZVector),s=vec(obj.Size),c={color.R,color.G,color.B},metal=num('PathMetallic',metal,0,1),rough=num('PathRoughness',rough,.025,1),emit=num('PathEmission',(obj:GetAttribute('PathEmissive')==true or mat==Enum.Material.Neon) and 4 or 0,0,50),transmission=num('PathTransmission',mat==Enum.Material.Glass and 1 or obj.Transparency,0,1),ior=num('PathIOR',1.5,1.001,3),shape=shape,specular=num('PathSpecular',1,0,1),emissionColor={ec.R,ec.G,ec.B}}
end
local function avatarSnapshot()
    local list={};local char=player.Character;if not char then return list end
    for _,obj in char:GetDescendants() do
        if obj:IsA('BasePart') and obj.Name~='HumanoidRootPart' and obj.Transparency<.95 and obj:GetAttribute('PathIgnore')~=true and #list<64 then
            list[#list+1]=materialPart(obj)
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
    elapsed+=dt; if elapsed<1/60 then return end; elapsed=0
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
local ws=nil;local wsOpen=false;local retryAt=0;local wsGeneration=0
local function closeWS()
    wsGeneration+=1;local old=ws;ws=nil;wsOpen=false
    if old then pcall(function() old:Close() end) end
end
local function connectWS()
    if ws or os.clock()<retryAt then return end
    retryAt=os.clock()+5
    local ok,c=pcall(function() return HTTP:CreateWebStreamClient(Enum.WebStreamClientType.WebSocket,{Url='ws://127.0.0.1:8765/api/ws'}) end)
    if not ok or not c then warn('[LumenGPU] WebSocket unavailable; HTTP fallback: '..tostring(c));return end
    ws=c;wsGeneration+=1;local generation=wsGeneration
    c.Opened:Connect(function() if generation~=wsGeneration then return end;wsOpen=true;lastSnapshot=-100;lastPartsJSON=nil;print('[LumenGPU] WebSocket open') end)
    c.MessageReceived:Connect(function(msg)
        if generation~=wsGeneration or not owner then return end
        local good,ctrl=pcall(function() return HTTP:JSONDecode(msg) end)
        if good and type(ctrl)=='table' and not ctrl.error then ctrl.transport='WS';remote:FireClient(owner,'input',ctrl) elseif good then warn('[LumenGPU] WebSocket update rejected: '..tostring(ctrl.error)) end
    end)
    local function failed() if generation==wsGeneration then closeWS();retryAt=os.clock()+5;lastPartsJSON=nil end end
    c.Closed:Connect(failed);c.Error:Connect(function(code,msg) warn('[LumenGPU] WS: '..tostring(code)..' '..tostring(msg));failed() end)
    if c.ConnectionState.Name=='Open' then wsOpen=true;lastSnapshot=-100;lastPartsJSON=nil end
    task.delay(3,function() if generation==wsGeneration and not wsOpen then failed() end end)
end
local function vec(v) return {v.X,v.Y,v.Z} end
local function materialPart(obj)
    local function num(k,v,lo,hi)
        local x=obj:GetAttribute(k);if type(x)~='number' or x~=x then return v end;return math.clamp(x,lo,hi)
    end
    local mat=obj.Material
    local metal=(mat==Enum.Material.Metal or mat==Enum.Material.CorrodedMetal or mat==Enum.Material.DiamondPlate or mat==Enum.Material.Foil) and 1 or 0
    local rough=metal==1 and .28 or .65
    if mat==Enum.Material.Glass or mat==Enum.Material.Ice then rough=.08 end
    if mat~=Enum.Material.Glass then local r=math.clamp(obj.Reflectance,0,1);rough=rough+(.045-rough)*r;metal=math.max(metal,r) end
    local color=obj:GetAttribute('PathBaseColor');if typeof(color)~='Color3' then color=obj.Color end
    local ec=obj:GetAttribute('PathEmissionColor');if typeof(ec)~='Color3' then ec=color end
    local c=obj.CFrame;local shape=0
    if obj:IsA('Part') then if obj.Shape==Enum.PartType.Ball then shape=1 elseif obj.Shape==Enum.PartType.Cylinder then shape=2 end end
    return {p=vec(c.Position),r=vec(c.RightVector),u=vec(c.UpVector),b=vec(c.ZVector),s=vec(obj.Size),c={color.R,color.G,color.B},metal=num('PathMetallic',metal,0,1),rough=num('PathRoughness',rough,.025,1),emit=num('PathEmission',(obj:GetAttribute('PathEmissive')==true or mat==Enum.Material.Neon) and 4 or 0,0,50),transmission=num('PathTransmission',mat==Enum.Material.Glass and 1 or obj.Transparency,0,1),ior=num('PathIOR',1.5,1.001,3),shape=shape,specular=num('PathSpecular',1,0,1),emissionColor={ec.R,ec.G,ec.B}}
end
-- Promote physics and scripted moving parts out of the slow world snapshot.
local tracked={};local dynamic={};local order={};local dirty=true
local function eligible(obj)
 return obj:IsA('BasePart') and not obj:IsA('Terrain') and obj.Name~='HumanoidRootPart' and (obj.Transparency<.95 or obj.Material==Enum.Material.Glass) and obj.Size.Magnitude>0 and obj:GetAttribute('PathIgnore')~=true and not (owner and owner.Character and obj:IsDescendantOf(owner.Character))
end
local function track(obj)
 if not obj:IsA('BasePart') or obj:IsA('Terrain') or tracked[obj] then return end
 order[#order+1]=obj
 tracked[obj]={}
 local function promote() if not dynamic[obj] then dynamic[obj]=true;dirty=true end end
 tracked[obj][1]=obj:GetPropertyChangedSignal('CFrame'):Connect(promote)
 tracked[obj][2]=obj:GetPropertyChangedSignal('Anchored'):Connect(promote)
 if not obj.Anchored then dynamic[obj]=true end
 dirty=true
end
for _,obj in workspace:GetDescendants() do track(obj) end
workspace.DescendantAdded:Connect(track)
workspace.DescendantRemoving:Connect(function(obj)
 if tracked[obj] then for _,c in tracked[obj] do c:Disconnect() end;tracked[obj]=nil;dynamic[obj]=nil;dirty=true end
end)
local function snapshot()
 local out={};local compact={};local seen={}
 for _,obj in order do
  if tracked[obj] and not seen[obj] then seen[obj]=true;compact[#compact+1]=obj
   if not dynamic[obj] and eligible(obj) and #out<15360 then out[#out+1]=materialPart(obj) end
  end
 end
 order=compact
 return out
end
local function dynamicSnapshot()
 local out={}
 for _,obj in order do
  if dynamic[obj] and eligible(obj) and #out<960 then out[#out+1]=materialPart(obj) end
 end
 for _,part in latestAvatar do if #out<1024 then out[#out+1]=part end end
 return out
end
remote.OnServerEvent:Connect(function(player,cmd,data,avatar)
    if cmd=='start' and (not owner or owner==player) then
        if not owner then owner=player; latest=nil; latestAvatar={}; lastSnapshot=-100; lastPartsJSON=nil; print('[LumenGPU] Local bridge started') end
        remote:FireClient(player,'status','Waiting for HTTP')
    elseif cmd=='stop' and owner==player then owner=nil; latest=nil;closeWS()
    elseif cmd=='camera' and owner==player and type(data)=='table' then
        if type(data.p)=='table' and #data.p==3 and type(data.r)=='table' and #data.r==3 and type(data.u)=='table' and #data.u==3 and type(data.f)=='table' and #data.f==3 and type(data.fov)=='number' then latest=data; if type(avatar)=='table' and #avatar<=64 then latestAvatar=avatar end end
    end
end)
Players.PlayerRemoving:Connect(function(p) if p==owner then owner=nil; latest=nil;closeWS() end end)
local lastError=-100
local lastHTTP=-100
while task.wait(1/60) do
    if owner and latest then
        local ok,err=pcall(function()
            local now=os.clock();connectWS()
            if not wsOpen and now-lastHTTP<.15 then return end
            local update={camera=latest,sun=vec(Lighting:GetSunDirection()),avatar=dynamicSnapshot()}; local newJSON=nil
            if dirty or now-lastSnapshot>=1.0 then
                dirty=false
                lastSnapshot=now
                local parts=snapshot(); newJSON=HTTP:JSONEncode(parts)
                if newJSON~=lastPartsJSON then update.parts=parts end
            end
            if wsOpen and ws then
                ws:Send(HTTP:JSONEncode(update))
                if newJSON then lastPartsJSON=newJSON end
                return
            end
            lastHTTP=now
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
print('LUMEN GPU 0.4 installed. Enable HTTP Requests, start LumenBridge.exe and the native renderer, Play locally and press P. Existing LUMEN installations are not removed; stop their renderer.')
