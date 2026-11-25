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
local function vec(v) return {v.X,v.Y,v.Z} end
UIS.InputBegan:Connect(function(i,processed)
    if not processed and i.KeyCode==Enum.KeyCode.P and not UIS:GetFocusedTextBox() then
        active=not active; remote:FireServer(active and 'start' or 'stop'); print('[LumenGPU] '..(active and 'Streaming on' or 'Streaming off'))
    end
end)
local elapsed=0
RunService.RenderStepped:Connect(function(dt)
    if not active then return end
    elapsed+=dt; if elapsed<.2 then return end; elapsed=0
    local cam=workspace.CurrentCamera; if not cam then return end
    local c=cam.CFrame; remote:FireServer('camera',{p=vec(c.Position),r=vec(c.RightVector),u=vec(c.UpVector),f=vec(c.LookVector),fov=cam.FieldOfView})
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
local lastSnapshot=-100
local lastPartsJSON=nil
local function vec(v) return {v.X,v.Y,v.Z} end
local function numeric(a,default,lo,hi) if type(a)~='number' or a~=a then return default end; return math.clamp(a,lo,hi) end
local function snapshot(pos)
    local items={}
    for _,obj in workspace:GetDescendants() do
        if obj:IsA('BasePart') and obj.Transparency<.95 and obj.Size.Magnitude>0 then
            local c=obj.CFrame; local size=obj.Size; local color=obj.Color
            local distance=(c.Position-pos).Magnitude-math.max(size.X,size.Y,size.Z)*.5
            local metal=numeric(obj:GetAttribute('PathMetallic'),obj.Reflectance,0,1)
            local rough=numeric(obj:GetAttribute('PathRoughness'),.45,0,1)
            local emit=numeric(obj:GetAttribute('PathEmission'),obj.Material==Enum.Material.Neon and 3 or 0,0,50)
            items[#items+1]={distance=distance,data={p=vec(c.Position),r=vec(c.RightVector),u=vec(c.UpVector),b=vec(c.ZVector),s=vec(size),c={color.R,color.G,color.B},metal=metal,rough=rough,emit=emit}}
        end
    end
    table.sort(items,function(a,b) return a.distance<b.distance end)
    local out={}; for i=1,math.min(1024,#items) do out[i]=items[i].data end; return out
end
remote.OnServerEvent:Connect(function(player,cmd,data)
    if cmd=='start' and not owner then owner=player; latest=nil; lastSnapshot=-100; lastPartsJSON=nil; print('[LumenGPU] Local bridge started')
    elseif cmd=='stop' and owner==player then owner=nil; latest=nil
    elseif cmd=='camera' and owner==player and type(data)=='table' then
        if type(data.p)=='table' and #data.p==3 and type(data.r)=='table' and #data.r==3 and type(data.u)=='table' and #data.u==3 and type(data.f)=='table' and #data.f==3 and type(data.fov)=='number' then latest=data end
    end
end)
Players.PlayerRemoving:Connect(function(p) if p==owner then owner=nil; latest=nil end end)
local lastError=-100
while task.wait(.2) do
    if owner and latest then
        local ok,err=pcall(function()
            local now=os.clock(); local update={camera=latest,sun=vec(Lighting:GetSunDirection())}; local newJSON=nil
            if now-lastSnapshot>=1 then
                lastSnapshot=now
                local p=latest.p; local parts=snapshot(Vector3.new(p[1],p[2],p[3])); newJSON=HTTP:JSONEncode(parts)
                if newJSON~=lastPartsJSON then update.parts=parts end
            end
            local result=HTTP:RequestAsync({Url='http://127.0.0.1:8765/api/update',Method='POST',Headers={['Content-Type']='application/json'},Body=HTTP:JSONEncode(update)})
            if not result.Success then error('HTTP '..result.StatusCode..' '..result.Body) end
            if newJSON then lastPartsJSON=newJSON end
        end)
        if not ok and os.clock()-lastError>5 then lastError=os.clock(); warn('[LumenGPU] '..tostring(err)..' | Start EXE, enable HTTP Requests, use local Studio Play.') end
    end
end
]====])
print('LUMEN GPU 0.2 installed. Enable HTTP Requests, start LumenBridge.exe and the native renderer, Play locally and press P. Existing LUMEN installations are not removed; stop their renderer.')
