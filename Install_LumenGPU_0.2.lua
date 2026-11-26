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
print('[LumenGPU] Client starting (0.9.4)')
local remote=game:GetService('ReplicatedStorage'):WaitForChild('LumenGPU_Camera',10)
assert(remote,'LumenGPU_Camera missing: reinstall in Edit mode')
local UIS=game:GetService('UserInputService')
local LocalLighting=game:GetService('Lighting')
local active=false
local player=game:GetService('Players').LocalPlayer
local external=false
local input={}
local lastInput=0
local yaw,pitch=0,0
local orbitDistance=10
local firstPerson=false
local previousAutoRotate=nil
local rotatedHumanoid=nil
local function restoreRotation()
    if rotatedHumanoid and rotatedHumanoid.Parent and previousAutoRotate~=nil then rotatedHumanoid.AutoRotate=previousAutoRotate end
    rotatedHumanoid=nil;previousAutoRotate=nil
end
local oldFov=70
local controls=nil
local oldCameraType=nil
local virtualInput=nil
local pointerHeld={}
local keyHeld={}
local keyNames={ [8]='Backspace',[9]='Tab',[13]='Return',[19]='Pause',[20]='CapsLock',[32]='Space',[33]='PageUp',[34]='PageDown',[35]='End',[36]='Home',[37]='Left',[38]='Up',[39]='Right',[40]='Down',[45]='Insert',[46]='Delete',[91]='LeftSuper',[92]='RightSuper',[96]='KeypadZero',[97]='KeypadOne',[98]='KeypadTwo',[99]='KeypadThree',[100]='KeypadFour',[101]='KeypadFive',[102]='KeypadSix',[103]='KeypadSeven',[104]='KeypadEight',[105]='KeypadNine',[106]='KeypadMultiply',[107]='KeypadPlus',[109]='KeypadMinus',[110]='KeypadPeriod',[111]='KeypadDivide',[144]='NumLock',[145]='ScrollLock',[160]='LeftShift',[161]='RightShift',[162]='LeftControl',[163]='RightControl',[164]='LeftAlt',[165]='RightAlt',[186]='Semicolon',[187]='Equals',[188]='Comma',[189]='Minus',[190]='Period',[191]='Slash',[192]='Backquote',[219]='LeftBracket',[220]='BackSlash',[221]='RightBracket',[222]='Quote',[226]='BackSlash' }
for i,name in {'Zero','One','Two','Three','Four','Five','Six','Seven','Eight','Nine'} do keyNames[47+i]=name end
for i=65,90 do keyNames[i]=string.char(i) end
for i=112,126 do keyNames[i]='F'..tostring(i-111) end
local keyCodes={};for _,item in Enum.KeyCode:GetEnumItems() do keyCodes[item.Name]=item end
local pointerPositions={}
local lastVirtualWarning=0
local function ensureVirtualInput()
    if not virtualInput then local ok,v=pcall(function() return UIS:CreateVirtualInput() end);if ok then virtualInput=v end end
    if not virtualInput and os.clock()-lastVirtualWarning>5 then lastVirtualWarning=os.clock();warn('[LumenGPU] VirtualInput unavailable in this Studio session') end
    return virtualInput~=nil
end
local function forwardKeys(events)
    if type(events)~='table' or #events==0 or not ensureVirtualInput() then return end
    for _,e in events do
        local key=keyCodes[keyNames[e.vk]]
        if key then
            local down=e.down==true;local repeated=e['repeat']==true
            if repeated or (keyHeld[key]==true)~=down then
                local ok,err=pcall(function() virtualInput:SendKey(down,key,repeated) end)
                if ok then keyHeld[key]=down elseif os.clock()-lastVirtualWarning>5 then lastVirtualWarning=os.clock();warn('[LumenGPU] SendKey: '..tostring(err)) end
            end
        end
    end
end
local function forwardPointer(events)
    if type(events)~='table' or #events==0 or not ensureVirtualInput() then return end
    local cam=workspace.CurrentCamera;if not cam then return end
    for _,e in events do
        if type(e)=='table' and type(e.x)=='number' and type(e.y)=='number' then
            local pos=Vector2.new(math.clamp(e.x,0,1)*cam.ViewportSize.X,math.clamp(e.y,0,1)*cam.ViewportSize.Y)
            local key=e.button==1 and Enum.UserInputType.MouseButton1 or e.button==2 and Enum.UserInputType.MouseButton2 or e.button==3 and Enum.UserInputType.MouseButton3 or nil
            local ok,err=pcall(function()
                if key then if (pointerHeld[key]==true)~=(e.down==true) then virtualInput:SendMouseButton(pos,key,e.down==true,0);pointerHeld[key]=e.down==true;pointerPositions[key]=pos end else virtualInput:SendMousePosition(pos) end
            end)
            if not ok and os.clock()-lastVirtualWarning>5 then lastVirtualWarning=os.clock();warn('[LumenGPU] VirtualInput: '..tostring(err)) end
        end
    end
end
local function releasePointer()
    if virtualInput then for key,held in pointerHeld do if held then pcall(function() virtualInput:SendMouseButton(pointerPositions[key] or Vector2.zero,key,false,0) end) end end end
    if virtualInput then for key,held in keyHeld do if held then pcall(function() virtualInput:SendKey(false,key,false) end) end end end
    table.clear(keyHeld);table.clear(pointerHeld);table.clear(pointerPositions)
end
local gui=Instance.new('ScreenGui'); gui.Name='LumenGPUConnection';gui.ResetOnSpawn=false;gui.DisplayOrder=100;gui.Parent=player:WaitForChild('PlayerGui')
local button=Instance.new('TextButton');button.Name='Toggle';button.Size=UDim2.fromOffset(240,34);button.Position=UDim2.new(1,-252,0,12);button.BackgroundColor3=Color3.fromRGB(35,45,57);button.TextColor3=Color3.new(1,1,1);button.TextSize=14;button.Font=Enum.Font.GothamMedium;button.Text='LUMEN GPU: Start (P)';button.Parent=gui
print('[LumenGPU] Connection UI created')
local lastAck=0
local lastRetry=0
local status='Waiting for bridge'
local lastControlLog=0
-- PlayerModule can be inserted after this script starts. Do not block UI startup.
local function disableDefaultControls()
    if not controls then return end
    local ok,err=pcall(function() controls:Disable() end)
    if not ok then warn('[LumenGPU] Default controls disable failed: '..tostring(err)) end
end
task.spawn(function()
    local scripts=player:WaitForChild('PlayerScripts',15)
    local module=scripts and scripts:WaitForChild('PlayerModule',15)
    if not module then warn('[LumenGPU] PlayerModule not found; using priority movement override');return end
    local ok,result=pcall(function() return require(module):GetControls() end)
    if ok then
        controls=result
        if external then disableDefaultControls() end
        print('[LumenGPU] PlayerModule controls ready')
    else warn('[LumenGPU] PlayerModule: '..tostring(result)) end
end)
local function release(reason)
    if not external then return end
    external=false; input={};firstPerson=false;restoreRotation();releasePointer()
    print('[LumenGPU] External controls released: '..tostring(reason or 'stopped'))
    if controls then pcall(function() controls:Enable() end) end
    local cam=workspace.CurrentCamera; if cam then cam.CameraType=oldCameraType or Enum.CameraType.Custom;cam.FieldOfView=oldFov end
    player:Move(Vector3.zero,false)
end
remote.OnClientEvent:Connect(function(kind,c)
    if kind=='status' and active then
        status=tostring(c);lastAck=os.clock();return
    end
    if kind~='input' or not active or type(c)~='table' then return end
    lastAck=os.clock();status=(c.transport or 'HTTP')..(c.active and string.format(' Input [%d,%d]',c.x or 0,c.z or 0) or ' Connected')
    if not c.active then release('native input inactive');return end
    lastInput=os.clock()
    if os.clock()-lastControlLog>2 then lastControlLog=os.clock();print('[LumenGPU] Input received: ',c.x,c.z,c.dx,c.dy) end
    local cam=workspace.CurrentCamera; if not cam then return end
    if not external then
        local look=cam.CFrame.LookVector; yaw=math.atan2(-look.X,-look.Z); pitch=math.asin(math.clamp(look.Y,-1,1))
        local char=player.Character;local head=char and char:FindFirstChild('Head')
        if head then orbitDistance=math.clamp((cam.CFrame.Position-head.Position).Magnitude,.5,40) end
        oldCameraType=cam.CameraType;oldFov=cam.FieldOfView; external=true
        disableDefaultControls()
        print('[LumenGPU] External controls captured')
        cam.CameraType=Enum.CameraType.Scriptable
    end
    local sensitivity=math.clamp(c.sensitivity or 1,.1,5)*.0025
    if (c.distance or 0)>0 then orbitDistance=math.clamp(c.distance,.5,40) end
    if (c.fov or 0)>0 then cam.FieldOfView=math.clamp(c.fov,35,110) end
    yaw-=math.clamp(c.dx or 0,-2000,2000)*sensitivity; pitch=math.clamp(pitch-math.clamp(c.dy or 0,-2000,2000)*sensitivity,-1.553,1.553)
    input=c;lastInput=os.clock();forwardPointer(c.pointer);forwardKeys(c.keys)
    local hum=player.Character and player.Character:FindFirstChildOfClass('Humanoid'); if hum and c.jump then hum.Jump=true end
end)
local function vec(v) return {v.X,v.Y,v.Z} end
-- Cache readable asset geometry once. Asset loads and uploads run outside Heartbeat.
local Assets=game:GetService('AssetService')
local meshCache,meshQueue,usedMeshIds={},{},{}
local meshRandom=Random.new()
local meshReadyVersion=0
local meshCount=0
local externalImages={}
local imageCount=0
local imageQueue={}
local resolvedImages={}
local imageScanned=setmetatable({},{__mode='k'})
local function numericAsset(uri)
    if type(uri)~='string' then return nil end
    local id=uri:match('^rbxassetid://(%d+)$') or uri:match('^(%d+)$')
    if not id then id=uri:match('^https?://www%.roblox%.com/asset/?%?id=(%d+)$') or uri:match('^https?://www%.roblox%.com/asset/?%?id=(%d+)&') or uri:match('^https?://assetdelivery%.roblox%.com/v1/asset/?%?id=(%d+)$') end
    if id and #id<=20 and not id:match('^0') then return id end
    return nil
end
local function discoverImage(uri)
    local id=numericAsset(uri)
    if id and not externalImages[id] and imageCount<128 then
        imageCount+=1;externalImages[id]=imageCount;imageQueue[#imageQueue+1]={asset=id,slot=imageCount}
    end
    return id and resolvedImages[id] or 0
end
local faceCode={[Enum.NormalId.Right]=1,[Enum.NormalId.Left]=2,[Enum.NormalId.Top]=3,[Enum.NormalId.Bottom]=4,[Enum.NormalId.Back]=5,[Enum.NormalId.Front]=6}
local bodyNames={Head='Head',Torso='Torso',LeftArm='Left Arm',RightArm='Right Arm',LeftLeg='Left Leg',RightLeg='Right Leg'}
local function characterMesh(obj)
    if obj.Name~='Head' and obj.Name~='Torso' and obj.Name~='Left Arm' and obj.Name~='Right Arm' and obj.Name~='Left Leg' and obj.Name~='Right Leg' then return nil end
    local char=obj.Parent
    if not char or not char:FindFirstChildOfClass('Humanoid') then return nil end
    for _,item in char:GetChildren() do
        if item:IsA('CharacterMesh') and bodyNames[item.BodyPart.Name]==obj.Name then return item end
    end
    return nil
end
local function discoverImages(obj)
    local slot=0
    if obj:IsA('MeshPart') then slot=discoverImage(obj.TextureID) end
    local special=obj:FindFirstChildOfClass('SpecialMesh')
    if special and special.MeshType==Enum.MeshType.FileMesh then slot=discoverImage(special.TextureId) end
    local surface=obj:FindFirstChildOfClass('SurfaceAppearance')
    if surface then local color=discoverImage(surface.ColorMap);if color>0 then slot=color end end
    local cm=characterMesh(obj)
    if cm then local base=discoverImage('rbxassetid://'..tostring(cm.BaseTextureId));local overlay=discoverImage('rbxassetid://'..tostring(cm.OverlayTextureId));if base>0 then slot=base elseif overlay>0 then slot=overlay end end
    if slot>0 then return {slot,0,1,1,0,0,1,0} end
    if (obj:IsA('Part') and obj.Shape==Enum.PartType.Block) or obj:IsA('SpawnLocation') then
        for _,child in obj:GetChildren() do
            if child:IsA('Decal') or child:IsA('Texture') then
                slot=discoverImage(child.Texture)
                local face=faceCode[child.Face]
                if slot>0 and face then
                    local su,sv,ou,ov,wrap=1,1,0,0,0
                    if child:IsA('Texture') then
                        local w=face<=2 and obj.Size.Z or obj.Size.X
                        local h=(face==3 or face==4) and obj.Size.Z or obj.Size.Y
                        su=math.clamp(w/math.max(child.StudsPerTileU,.001),.0001,4096)
                        sv=math.clamp(h/math.max(child.StudsPerTileV,.001),.0001,4096)
                        ou=math.clamp(-child.OffsetStudsU/math.max(child.StudsPerTileU,.001),-4096,4096)
                        ov=math.clamp(-child.OffsetStudsV/math.max(child.StudsPerTileV,.001),-4096,4096)
                        wrap=1
                    end
                    return {slot,face,su,sv,ou,ov,1-child.Transparency,wrap}
                end
            end
        end
    end
    return nil
end
remote.OnClientEvent:Connect(function(kind,id,slot)
    if kind=='lumenusImageAck' and type(slot)=='number' and slot>0 then resolvedImages[id]=slot;imageScanned=setmetatable({},{__mode='k'});meshReadyVersion+=1 end
end)
task.spawn(function()
    while task.wait(.5) do
        if active and #imageQueue>0 then local q=table.remove(imageQueue,1);remote:FireServer('lumenusImage',q.asset,q.slot) end
    end
end)
local function meshEntry(obj)
    local content,key,special
    local cm=characterMesh(obj)
    if cm and tonumber(cm.MeshId) and tonumber(cm.MeshId)>0 then
        key='rbxassetid://'..tostring(cm.MeshId)
    elseif obj:IsA('MeshPart') then
        key=obj.MeshId~='' and obj.MeshId or obj
        local ok,value=pcall(function() return obj.MeshContent end);if ok then content=value end
    else
        special=obj:FindFirstChildOfClass('SpecialMesh')
        if not special or special.MeshType~=Enum.MeshType.FileMesh or special.MeshId=='' then return nil end
        key=special.MeshId
    end
    if not content and type(key)=='string' then local ok,value=pcall(function() return Content.fromUri(key) end);if ok then content=value end end
    if not key then return nil end
    local entry=meshCache[key]
    if not entry and meshCount<256 then
        local id
        repeat id=meshRandom:NextInteger(3,16777215) until not usedMeshIds[id]
        usedMeshIds[id]=true;meshCount+=1
        entry={id=id,key=key,content=content,state='queued',bodyPackage=cm~=nil}
        meshCache[key]=entry;meshQueue[#meshQueue+1]=entry
    end
    return entry,special
end
local function extractMesh(entry)
    if not entry.content then error('No readable mesh Content; using authorized asset fallback') end
    local editable=Assets:CreateEditableMeshAsync(entry.content,{FixedSize=true})
    if not editable then error('EditableMesh allocation failed') end
    local ok,verts,size=pcall(function()
        local faces=editable:GetFaces()
        if #faces==0 or #faces>20000 then error('mesh exceeds 20000 triangles or is empty') end
        local dimensions=editable:GetSize()
        local scale=Vector3.new(math.max(dimensions.X,.0001),math.max(dimensions.Y,.0001),math.max(dimensions.Z,.0001))
        local rows={}
        for i,face in faces do
            local ids=editable:GetFaceVertices(face)
            if #ids==3 then
                local uvOK,faceUVs=pcall(function() return editable:GetFaceUVs(face) end)
                if not uvOK then faceUVs={} end
                local nOK,faceNormals=pcall(function() return editable:GetFaceNormals(face) end);if not nOK then faceNormals={} end
                for j,id in ids do
                    local v=editable:GetPosition(id)/scale
                    local uv=faceUVs[j] and editable:GetUV(faceUVs[j]) or Vector2.zero
                    local normal=faceNormals[j] and editable:GetNormal(faceNormals[j])*scale or Vector3.zero
                    if normal.Magnitude>0 then normal=normal.Unit end
                    rows[#rows+1]={v.X,v.Y,v.Z,uv.X,uv.Y,normal.X,normal.Y,normal.Z}
                end
            end
            if i%128==0 then task.wait() end
        end
        return rows,scale
    end)
    editable:Destroy()
    if not ok then error(verts) end
    if #verts==0 then error('no triangle vertices') end
    entry.vertices=verts;entry.size=size
end
remote.OnClientEvent:Connect(function(kind,id,success)
    if kind=='lumenusMeshAck' then
        for _,e in meshCache do
            if e.id==id and e.state=='external' then
                if type(success)=='table' and #success==3 then
                    e.size=Vector3.new(success[1],success[2],success[3])
                    e.state='ready';meshReadyVersion+=1
                    print('[Lumenus] External mesh ready '..tostring(e.key))
                else e.state='failed';warn('[Lumenus] External mesh unavailable '..tostring(e.key)) end
                break
            end
        end
        return
    end
    if kind~='meshAck' then return end
    for _,e in meshCache do
        if e.id==id and e.state=='sending' then
            if success then e.state='ready';meshReadyVersion+=1;print('[LumenGPU] Mesh ready '..id..' ('..tostring(#e.vertices / 3)..' triangles)');e.vertices=nil
            else e.state='failed';e.vertices=nil;warn('[LumenGPU] Mesh upload rejected '..id..'; using box fallback') end
            break
        end
    end
end)
task.spawn(function()
    while true do
        if active and #meshQueue>0 then
            local e=table.remove(meshQueue,1)
            local ok,err=true,nil
            if not e.terrain then ok,err=pcall(extractMesh,e) end
            if ok then
                -- Small paced chunks; server uploads via a separate request.
                while not active do task.wait(.25) end
                e.state='sending';remote:FireServer('meshBegin',e.id,#e.vertices)
                for first=1,#e.vertices,384 do
                    if not active then break end
                    local rows={};for i=first,math.min(first+383,#e.vertices) do rows[#rows+1]=e.vertices[i] end
                    remote:FireServer('meshChunk',e.id,rows);task.wait()
                end
                if active then remote:FireServer('meshEnd',e.id) end
                local deadline=os.clock()+30
                while active and e.state=='sending' and os.clock()<deadline do task.wait(.1) end
                if e.state=='sending' then e.state='failed';e.vertices=nil;warn('[LumenGPU] Mesh upload interrupted; fallback') end
            else
                local id=numericAsset(e.key)
                if id and active then
                    e.state='external';remote:FireServer('lumenusMesh',e.id,id)
                    local deadline=os.clock()+120
                    while active and e.state=='external' and os.clock()<deadline do task.wait(.25) end
                    if e.state=='external' then e.state='failed' end
                else e.state='failed';warn('[LumenGPU] Mesh unavailable: '..tostring(e.key)..'; using box fallback') end
            end
            task.wait(.25)
        else task.wait(.15) end
    end
end)
-- Probe a real queryable wedge once per type to match Roblox's local high edge/corner.
local wedgeOrientation={}
local function orientWedge(obj,c,size,shape)
    local key=obj.ClassName..tostring(shape)
    local rotation=wedgeOrientation[key]
    if rotation==nil and obj.CanQuery and obj:IsDescendantOf(workspace) then
        local rp=RaycastParams.new();rp.FilterType=Enum.RaycastFilterType.Include;rp.FilterDescendantsInstances={obj};rp.RespectCanCollide=false
        local best=-math.huge;local sx,sz=1,1
        for _,x in {-1,1} do for _,z in {-1,1} do
            local hit=workspace:Raycast(c:PointToWorldSpace(Vector3.new(x*size.X*.4,size.Y*.6,z*size.Z*.4)),-c.UpVector*size.Y*1.2,rp)
            if hit then local h=c:PointToObjectSpace(hit.Position).Y;if h>best+size.Y*.001 then best=h;sx=x;sz=z end end
        end end
        if best>-math.huge then
            if shape==-1 then rotation=sz==1 and 0 or math.pi
            else rotation=sx==1 and (sz==1 and 0 or math.pi/2) or (sz==1 and -math.pi/2 or math.pi) end
            wedgeOrientation[key]=rotation
        end
    end
    rotation=rotation or 0
    if math.abs(rotation)==math.pi/2 then size=Vector3.new(size.Z,size.Y,size.X) end
    return c*CFrame.Angles(0,rotation,0),size
end
local surfaceNames={'RightSurface','LeftSurface','TopSurface','BottomSurface','BackSurface','FrontSurface'}
local surfaceKinds={[Enum.SurfaceType.Studs]=1,[Enum.SurfaceType.Inlet]=2,[Enum.SurfaceType.Universal]=3}
local function extraMaterial(obj,tex)
    local packed=0
    if obj:IsA('Part') or obj:IsA('SpawnLocation') then
        for i,k in surfaceNames do packed+=(surfaceKinds[obj[k]] or 0)*4^(i-1) end
    end
    local n,r,m=0,0,0
    local surface=obj:FindFirstChildOfClass('SurfaceAppearance')
    if surface then n=discoverImage(surface.NormalMap);r=discoverImage(surface.RoughnessMap);m=discoverImage(surface.MetalnessMap) end
    local gen=obj:GetAttribute('LumenPBRStrength')
    if type(gen)~='number' or gen~=gen then gen=.35 end
    local spawn=obj:IsA('SpawnLocation') and not tex and 1 or 0
    return {packed,n,r,m,tex and math.clamp(gen,0,1) or 0,spawn,0,0}
end
local extraScanned=setmetatable({},{__mode='k'})
-- Classic garment atlas: torso=1, right limb=2, left limb=3.
local garmentRegions={
 ['Torso']={1,0,1},['Right Arm']={2,0,1},['Left Arm']={3,0,1},['Right Leg']={2,0,1},['Left Leg']={3,0,1},
 UpperTorso={1,0,.6},LowerTorso={1,.6,.4},
 RightUpperArm={2,0,.4},RightLowerArm={2,.4,.4},RightHand={2,.8,.2},LeftUpperArm={3,0,.4},LeftLowerArm={3,.4,.4},LeftHand={3,.8,.2},
 RightUpperLeg={2,0,.4},RightLowerLeg={2,.4,.4},RightFoot={2,.8,.2},LeftUpperLeg={3,0,.4},LeftLowerLeg={3,.4,.4},LeftFoot={3,.8,.2}
}
local function garmentData(obj)
    local region=garmentRegions[obj.Name]
    local char=obj.Parent
    if not char or not char:FindFirstChildOfClass('Humanoid') then return nil end
    local cm=characterMesh(obj)
    local overlay=cm and discoverImage('rbxassetid://'..tostring(cm.OverlayTextureId)) or 0
    if not region then return overlay>0 and {0,0,0,overlay,0,0,0,0} or nil end
    local shirt,pants,graphic=0,0,0
    local torso=region[1]==1
    local leg=obj.Name:find('Leg')~=nil or obj.Name:find('Foot')~=nil
    local sh=char:FindFirstChildOfClass('Shirt');local pa=char:FindFirstChildOfClass('Pants');local gr=char:FindFirstChildOfClass('ShirtGraphic')
    if sh and not leg then shirt=discoverImage(sh.ShirtTemplate) end
    if pa and (torso or leg) then pants=discoverImage(pa.PantsTemplate) end
    if gr and torso then graphic=discoverImage(gr.Graphic) end
    if shirt==0 and pants==0 and graphic==0 and overlay==0 then return nil end
    return {shirt,pants,graphic,overlay,region[1],region[2],region[3],0}
end
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
    local c=obj.CFrame;local size=obj.Size;local shape=0
    if obj:IsA('WedgePart') then shape=-1
    elseif obj:IsA('CornerWedgePart') then shape=-2
    elseif obj:IsA('TrussPart') then
        shape=obj.Style==Enum.Style.NoSupports and -5 or obj.Style==Enum.Style.BridgeStyleSupports and -4 or -3
        if size.X>size.Y and size.X>=size.Z then c=c*CFrame.Angles(0,0,-math.pi/2);size=Vector3.new(size.Y,size.X,size.Z)
        elseif size.Z>size.Y and size.Z>=size.X then c=c*CFrame.Angles(math.pi/2,0,0);size=Vector3.new(size.X,size.Z,size.Y) end
    elseif obj:IsA('Part') then
        if obj.Shape==Enum.PartType.Ball then shape=1 elseif obj.Shape==Enum.PartType.Cylinder then shape=2 elseif obj.Shape==Enum.PartType.Wedge then shape=-1 elseif obj.Shape==Enum.PartType.CornerWedge then shape=-2 end
    end
    if shape==-1 or shape==-2 then c,size=orientWedge(obj,c,size,shape) end
    local tex=imageScanned[obj];if tex==nil then tex=discoverImages(obj) or false;imageScanned[obj]=tex end
    local cached=extraScanned[obj];local ex
    if cached and cached.rev==meshReadyVersion and cached.tex==tex and os.clock()-cached.at<3 then ex=cached.ex else ex=extraMaterial(obj,tex);extraScanned[obj]={rev=meshReadyVersion,tex=tex,ex=ex,at=os.clock()} end
    local e,special=meshEntry(obj)
    if e and e.state=='ready' then
        shape=e.id
        if special then
            c=c*CFrame.new(special.Offset);size=e.size*special.Scale
        elseif obj:IsA('MeshPart') then
            local ok,ms=pcall(function() return obj.MeshSize end)
            if ok and typeof(ms)=='Vector3' and ms.Magnitude>.001 then size=Vector3.new(size.X*e.size.X/math.max(ms.X,.0001),size.Y*e.size.Y/math.max(ms.Y,.0001),size.Z*e.size.Z/math.max(ms.Z,.0001)) end
        elseif e.bodyPackage then
            local standard=obj.Name=='Torso' and Vector3.new(2,2,1) or obj.Name=='Head' and Vector3.new(2,1,1) or Vector3.new(1,2,1)
            size=e.size*(obj.Size/standard)
        end
        size=Vector3.new(math.max(size.X,.0001),math.max(size.Y,.0001),math.max(size.Z,.0001))
    end
    return {p=vec(c.Position),r=vec(c.RightVector),u=vec(c.UpVector),b=vec(c.ZVector),s=vec(size),c={color.R,color.G,color.B},metal=num('PathMetallic',metal,0,1),rough=num('PathRoughness',rough,.025,1),emit=num('PathEmission',(obj:GetAttribute('PathEmissive')==true or mat==Enum.Material.Neon) and 4 or 0,0,50),transmission=num('PathTransmission',mat==Enum.Material.Glass and 1 or obj.Transparency,0,1),ior=num('PathIOR',1.5,1.001,3),shape=shape,specular=num('PathSpecular',1,0,1),emissionColor={ec.R,ec.G,ec.B},tex=tex or nil,extra=ex,cloth=garmentData(obj)}
end
local cachedCharacter={}
local lastAvatarWarning=setmetatable({},{__mode='k'})
local function avatarFallback(obj)
    local c,s,col=obj.CFrame,obj.Size,obj.Color
    return {p=vec(c.Position),r=vec(c.RightVector),u=vec(c.UpVector),b=vec(c.ZVector),s=vec(s),c={col.R,col.G,col.B},metal=0,rough=.65,emit=0,transmission=0,ior=1.5,shape=0,specular=1,emissionColor={0,0,0}}
end
local function avatarSnapshot()
    local list={};local char=player.Character;if not char then return list end
    for _,obj in char:GetDescendants() do
        if obj:IsA('BasePart') and obj.Name~='HumanoidRootPart' and obj.Transparency<.95 and obj:GetAttribute('PathIgnore')~=true and #list<64 then
            local ok,row=pcall(materialPart,obj)
            if not ok then
                local now=os.clock()
                if now-(lastAvatarWarning[obj] or -100)>10 then lastAvatarWarning[obj]=now;warn('[LumenGPU] Avatar part '..obj.Name..': '..tostring(row)) end
                ok,row=pcall(avatarFallback,obj)
            end
            if ok and row then list[#list+1]=row end
        end
    end
    return list
end
-- Avatar capture runs independently. Camera packets never wait for body conversion.
task.spawn(function()
    local lastScan=-100
    while task.wait(1/30) do
        if active then
            if os.clock()-lastScan>3 then
                lastScan=os.clock()
                local char=player.Character
                if char then for _,obj in char:GetDescendants() do if obj:IsA('BasePart') then imageScanned[obj]=nil end end end
            end
            local ok,rows=pcall(avatarSnapshot)
            if ok then cachedCharacter=rows end
        else cachedCharacter={} end
    end
end)
player.CharacterAdded:Connect(function() cachedCharacter={} end)
player.CharacterRemoving:Connect(function() cachedCharacter={} end)
-- Capture the actual local viewport's world, including client-only parts.
local HTTP=game:GetService('HttpService')
local order,tracked,dynamic={},{},{}
local dirty=true
local serial=0
local lastWorldJSON=nil
local lastScan=-100
local capturedMeshVersion=-1
local fastParts={}
local captureGeneration=0
local function invalidateCapture()
    captureGeneration+=1;lastWorldJSON=nil;dirty=true
end
local function eligible(obj)
    return obj:IsDescendantOf(workspace) and obj:IsA('BasePart') and not obj:IsA('Terrain') and obj.Name~='HumanoidRootPart' and (obj.Transparency<.95 or obj.Material==Enum.Material.Glass) and obj.Size.Magnitude>0 and obj:GetAttribute('PathIgnore')~=true and not (player.Character and obj:IsDescendantOf(player.Character))
end
local function track(obj)
    if not obj:IsA('BasePart') or obj:IsA('Terrain') or tracked[obj] then return end
    order[#order+1]=obj;tracked[obj]={}
    local function promote()
        if not dynamic[obj] then dynamic[obj]=true;dirty=true end
    end
    tracked[obj][1]=obj:GetPropertyChangedSignal('CFrame'):Connect(promote)
    tracked[obj][2]=obj:GetPropertyChangedSignal('Anchored'):Connect(promote)
    tracked[obj][3]=obj.Changed:Connect(function(prop)
        if not dynamic[obj] and (prop=='Size' or prop=='Color' or prop=='Material' or prop=='Reflectance' or prop=='Transparency' or prop=='Shape' or prop=='Style' or prop=='Name') then dirty=true end
    end)
    tracked[obj][4]=obj.AttributeChanged:Connect(function() if not dynamic[obj] then dirty=true end end)
    if not obj.Anchored then dynamic[obj]=true end
    dirty=true
end
task.defer(function()
    for i,obj in workspace:GetDescendants() do
        local ok,err=pcall(track,obj)
        if not ok then warn('[LumenGPU] Track: '..tostring(err)) end
        if i%128==0 then task.wait() end
    end
end)
workspace.DescendantAdded:Connect(track)
workspace.DescendantRemoving:Connect(function(obj)
    if tracked[obj] then
        for _,connection in tracked[obj] do connection:Disconnect() end
        tracked[obj]=nil;dynamic[obj]=nil;dirty=true
    end
end)
player.CharacterAdded:Connect(function() dirty=true end)
player.CharacterRemoving:Connect(function() dirty=true end)

-- Terrain preview: mesh occupancy at Roblox's 4-stud voxel resolution.
-- One bounded region, captured once per Play session; no scene-instance changes.
local terrainRows={}
local terrainStarted=false
local terrainMeshBudget=64
local terrainCorners={Vector3.new(0,0,0),Vector3.new(1,0,0),Vector3.new(1,1,0),Vector3.new(0,1,0),Vector3.new(0,0,1),Vector3.new(1,0,1),Vector3.new(1,1,1),Vector3.new(0,1,1)}
local terrainTets={{1,2,3,7},{1,3,4,7},{1,4,8,7},{1,8,5,7},{1,5,6,7},{1,6,2,7}}
local function terrainChunk(origin)
    local terrain=workspace.Terrain
    local side=64
    local region=Region3.new(origin,origin+Vector3.new(side+4,side+4,side+4))
    local materials,occupancy=terrain:ReadVoxels(region,4)
    local groups={}
    local function emit(mat,a,b,c,inside)
        local g=groups[mat];if not g then g={};groups[mat]=g end
        if #g>=60000 then return end
        local cross=(b-a):Cross(c-a)
        if cross.Magnitude<.00001 then return end
        if cross:Dot(inside-a)>0 then b,c=c,b end
        for _,v in {a,b,c} do g[#g+1]={v.X/side,v.Y/side,v.Z/side,0,0} end
    end
    for x=1,16 do
        for y=1,16 do for z=1,16 do
            local p,d,m={},{},{}
            local allIn,allOut=true,true
            for i,off in terrainCorners do
                local ix,iy,iz=x+off.X,y+off.Y,z+off.Z
                local mat=materials[ix][iy][iz]
                local val=(mat==Enum.Material.Air or mat==Enum.Material.Water) and 0 or occupancy[ix][iy][iz]
                p[i]=Vector3.new((x-1+off.X)*4-30,(y-1+off.Y)*4-30,(z-1+off.Z)*4-30)
                d[i]=val;m[i]=mat
                if val>=.5 then allOut=false else allIn=false end
            end
            if not allIn and not allOut then
                for _,tet in terrainTets do
                    local inside,outside={},{}
                    for _,i in tet do if d[i]>=.5 then inside[#inside+1]=i else outside[#outside+1]=i end end
                    if #inside>0 and #outside>0 then
                        local function edge(i,j) return p[i]:Lerp(p[j],math.clamp((.5-d[i])/(d[j]-d[i]),0,1)) end
                        local a=inside[1];local mat=m[a]
                        if #inside==1 then emit(mat,edge(a,outside[1]),edge(a,outside[2]),edge(a,outside[3]),p[a])
                        elseif #inside==3 then
                            local o=outside[1];emit(mat,edge(a,o),edge(inside[2],o),edge(inside[3],o),p[a])
                        else
                            local b=inside[2];local c,e=outside[1],outside[2]
                            local ac,ae,bc,be=edge(a,c),edge(a,e),edge(b,c),edge(b,e)
                            emit(mat,ac,ae,be,p[a]);emit(mat,ac,be,bc,p[b])
                        end
                    end
                end
            end
        end end
        if x%2==0 then task.wait() end
    end
    for mat,verts in groups do
        if #verts>=3 and terrainMeshBudget>0 and meshCount<256 then
            local id;repeat id=meshRandom:NextInteger(3,16777215) until not usedMeshIds[id]
            usedMeshIds[id]=true;meshCount+=1;terrainMeshBudget-=1
            local entry={id=id,key='terrain:'..id,vertices=verts,size=Vector3.new(side,side,side),state='queued',terrain=true}
            meshCache[entry.key]=entry;meshQueue[#meshQueue+1]=entry
            local color=terrain:GetMaterialColor(mat)
            terrainRows[#terrainRows+1]={entry=entry,part={p=vec(origin+Vector3.new(32,32,32)),r={1,0,0},u={0,1,0},b={0,0,1},s={side,side,side},c={color.R,color.G,color.B},metal=0,rough=.85,emit=0,transmission=0,ior=1.5,shape=id,specular=.3,emissionColor={0,0,0}}}
        end
    end
end
task.spawn(function()
    while task.wait(.3) do
        if active and not terrainStarted then
            terrainStarted=true
            local terrain=workspace.Terrain
            if terrain:GetAttribute('LumenTerrainEnabled')==false then continue end
            local cam=workspace.CurrentCamera
            if not cam then terrainStarted=false;continue end
            local center=terrain:GetAttribute('LumenTerrainCenter')
            if typeof(center)~='Vector3' then center=cam.CFrame.Position end
            local radius=terrain:GetAttribute('LumenTerrainRadius')
            radius=type(radius)=='number' and math.clamp(math.floor(radius/64),1,3) or 2
            local base=Vector3.new(math.floor(center.X/64)*64,math.floor(center.Y/64)*64,math.floor(center.Z/64)*64)
            local total=0
            for r=0,radius do
                for dx=-r,r do for dz=-r,r do
                    if math.max(math.abs(dx),math.abs(dz))==r then
                        for dy=-1,0 do
                            while not active do task.wait(.25) end
                            if terrainMeshBudget<=0 then break end
                            local ok,err=pcall(terrainChunk,base+Vector3.new(dx*64,dy*64,dz*64))
                            if not ok then warn('[LumenGPU] Terrain chunk: '..tostring(err)) end
                            total+=1;task.wait()
                        end
                    end
                end end
            end
            print('[LumenGPU] Terrain sampled '..total..' chunks; '..#terrainRows..' material meshes queued')
        end
    end
end)

-- Static snapshots are built outside the camera Heartbeat and paced over frames.
-- Capture the nearest 64 enabled Roblox lights as non-geometric records.
local lightObjects=setmetatable({},{__mode='k'})
local function trackLight(o)
    if o:IsA('PointLight') or o:IsA('SpotLight') or o:IsA('SurfaceLight') then lightObjects[o]=true end
end
for _,o in workspace:GetDescendants() do trackLight(o) end
workspace.DescendantAdded:Connect(trackLight)
workspace.DescendantRemoving:Connect(function(o) lightObjects[o]=nil end)
local faceVector={ [Enum.NormalId.Right]=Vector3.xAxis,[Enum.NormalId.Left]=-Vector3.xAxis,[Enum.NormalId.Top]=Vector3.yAxis,[Enum.NormalId.Bottom]=-Vector3.yAxis,[Enum.NormalId.Back]=Vector3.zAxis,[Enum.NormalId.Front]=-Vector3.zAxis }
local function lightRows()
    local cam=workspace.CurrentCamera;if not cam then return {} end
    local candidates={}
    for o in lightObjects do
        if o.Parent and o.Enabled and o.Range>0 and o.Brightness>0 then
            local parent=o.Parent;local cf=parent:IsA('Attachment') and parent.WorldCFrame or parent:IsA('BasePart') and parent.CFrame or nil
            if cf then
                local kind=o:IsA('PointLight') and 1 or o:IsA('SpotLight') and 2 or 3
                local localDir=kind==1 and Vector3.zAxis or (faceVector[o.Face] or -Vector3.zAxis)
                local dir=cf:VectorToWorldSpace(localDir);local pos=cf.Position
                if kind~=1 and parent:IsA('BasePart') then pos+=cf:VectorToWorldSpace(localDir*parent.Size*.5)+dir*.015 end
                local cone=kind==1 and -1 or math.cos(math.rad(o.Angle*.5))
                local col=o.Color
                candidates[#candidates+1]={d=(pos-cam.CFrame.Position).Magnitude,row={p=vec(pos),r={1,0,0},u={0,1,0},b={0,0,1},s={math.clamp(o.Range,.01,100000),1,1},c={col.R,col.G,col.B},emit=math.clamp(o.Brightness,0,50),emissionColor={col.R,col.G,col.B},shape=0,extra={0,0,0,0,0,0,kind,cone},tex={0,0,0,0,0,0,0,0},metal=0,rough=1,specular=0,transmission=0,ior=1.5,lightDir=dir}}
            end
        end
    end
    table.sort(candidates,function(a,b) return a.d<b.d end)
    local rows={}
    for i=1,math.min(#candidates,64) do
        local row=candidates[i].row
        local dir=row.lightDir;row.lightDir=nil
        local cf=CFrame.lookAt(Vector3.zero,dir,math.abs(dir.Y)>.99 and Vector3.xAxis or Vector3.yAxis)
        row.r=vec(cf.RightVector);row.u=vec(cf.UpVector);row.b=vec(cf.LookVector)
        rows[#rows+1]=row
    end
    return rows
end
local function refreshWorld()
    local generation=captureGeneration
    capturedMeshVersion=meshReadyVersion
    local now=os.clock()
    if now-lastScan>=5 then
        lastScan=now
        local n=0
        for _,obj in workspace:GetDescendants() do
            track(obj);n+=1
            if n%128==0 then task.wait();if not active or generation~=captureGeneration then return end end
        end
    end
    dirty=false
    local static,fast,compact,seen={},{},{},{}
    local overflow=0
    local n=0
    -- Snapshot the order so add/remove callbacks may safely run while yielding.
    local source=table.clone(order)
    for _,obj in source do
        if tracked[obj] and not seen[obj] then
            seen[obj]=true;compact[#compact+1]=obj
            if eligible(obj) then
                if dynamic[obj] and #fast<960 then fast[#fast+1]=obj
                elseif #static<15360 then static[#static+1]=materialPart(obj)
                else overflow+=1 end
            end
        end
        n+=1
        if n%64==0 then task.wait();if not active or generation~=captureGeneration then return end end
    end
    if not active or generation~=captureGeneration then return end
    -- Preserve entries added during this build.
    for _,obj in order do if tracked[obj] and not seen[obj] then seen[obj]=true;compact[#compact+1]=obj;dirty=true end end
    order=compact
    for _,row in terrainRows do if row.entry.state=='ready' and #static<15360 then static[#static+1]=row.part end end
    for _,row in lightRows() do if #static<15360 then static[#static+1]=row end end
    local encoded=HTTP:JSONEncode(static)
    if encoded~=lastWorldJSON then
        serial+=1;local id=serial
        remote:FireServer('worldBegin',id,#static)
        for first=1,#static,64 do
            if not active or generation~=captureGeneration then return end
            local rows={}
            for i=first,math.min(first+63,#static) do rows[#rows+1]=static[i] end
            remote:FireServer('worldChunk',id,rows)
            task.wait()
        end
        if not active or generation~=captureGeneration then return end
        remote:FireServer('worldEnd',id)
        lastWorldJSON=encoded
        print('[LumenGPU] Client world snapshot '..id..': '..#static..' static parts, '..#fast..' moving parts')
    end
    fastParts=fast
    if overflow>0 then warn('[LumenGPU] World capacity exceeded; '..overflow..' parts omitted') end
end
task.spawn(function()
    while true do
        if active and (dirty or capturedMeshVersion~=meshReadyVersion or lastWorldJSON==nil or os.clock()-lastScan>=5) then
            local ok,err=pcall(refreshWorld)
            if not ok then dirty=true;warn('[LumenGPU] World capture: '..tostring(err)) end
        end
        task.wait(.1)
    end
end)
-- Only traverse moving objects here; the camera loop never scans the world.
local cachedMoving={}
task.spawn(function()
    while true do
        if active then
            local rows={}
            for i,obj in fastParts do
                if eligible(obj) then rows[#rows+1]=materialPart(obj) end
                if i%64==0 then task.wait();if not active then break end end
            end
            if active then cachedMoving=rows end
        else cachedMoving={} end
        task.wait(1/30)
    end
end)
local function fastSnapshot()
    return cachedMoving
end
local function toggle()
    active=not active
    invalidateCapture()
    if not active then release('stream stopped') else status='Connecting';lastAck=0;lastRetry=os.clock() end
    remote:FireServer(active and 'start' or 'stop')
    button.Text=active and 'LUMEN GPU: Connecting...' or 'LUMEN GPU: Start (P)'
    print('[LumenGPU] '..(active and 'Streaming on' or 'Streaming off'))
end
button.Activated:Connect(toggle)
UIS.InputBegan:Connect(function(i,processed)
    if i.KeyCode==Enum.KeyCode.P and not external and not UIS:GetFocusedTextBox() then toggle() end
end)
-- Input is held state, not an individual key press per network packet.
-- Override default PlayerModule movement after its Input-priority update.
local function applyMovement()
    if not active or not external then return end
    if os.clock()-lastInput>.65 then release('input timeout');return end
    local rot=CFrame.fromOrientation(0,yaw,0)
    local char=player.Character;local hum=char and char:FindFirstChildOfClass('Humanoid');local root=char and char:FindFirstChild('HumanoidRootPart')
    if firstPerson and hum and root and hum.Health>0 and not hum.SeatPart then
        if rotatedHumanoid~=hum then restoreRotation();rotatedHumanoid=hum;previousAutoRotate=hum.AutoRotate end
        hum.AutoRotate=false
        root.CFrame=CFrame.new(root.Position)*rot
    else restoreRotation() end
    local move=rot.RightVector*math.clamp(input.x or 0,-1,1)+rot.LookVector*math.clamp(input.z or 0,-1,1)
    player:Move(move.Magnitude>1 and move.Unit or move,false)
end
local function updateCamera()
    if not active or not external then return end
    local char=player.Character;local head=char and char:FindFirstChild('Head');local cam=workspace.CurrentCamera
    if not head or not cam then return end
    local rot=CFrame.fromOrientation(0,yaw,0);local look=rot*CFrame.Angles(pitch,0,0)
    local pivot=head.Position+Vector3.new(0,.15,0)
    local minZoom=math.clamp(player.CameraMinZoomDistance,.5,40)
    local maxZoom=math.clamp(player.CameraMaxZoomDistance,minZoom,40)
    local distance=math.clamp(orbitDistance,minZoom,maxZoom)
    firstPerson=player.CameraMode==Enum.CameraMode.LockFirstPerson or distance<=.75
    cam.CameraType=Enum.CameraType.Scriptable
    if firstPerson then cam.CFrame=CFrame.new(pivot)*look;cam.Focus=CFrame.new(pivot+look.LookVector*12);return end
    local offset=-look.LookVector*distance
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={char};params.RespectCanCollide=true
    local hit=workspace:Raycast(pivot,offset,params)
    if hit then offset=offset.Unit*math.max(.35,hit.Distance-.35) end
    if offset.Magnitude<=.75 then firstPerson=true;cam.CFrame=CFrame.new(pivot)*look;cam.Focus=CFrame.new(pivot+look.LookVector*12);return end
    cam.CameraType=Enum.CameraType.Scriptable
    cam.CFrame=CFrame.new(pivot+offset)*look;cam.Focus=CFrame.new(pivot)
end
RunService:BindToRenderStep('LumenGPU_ExternalMovement',Enum.RenderPriority.Input.Value+1,applyMovement)
-- Reassert immediately before simulation as well, so physics sees held input.
RunService.PreSimulation:Connect(applyMovement)
-- ScreenGui snapshot: normalized viewport layout, not a second 3D render.
local GuiService=game:GetService('GuiService')
local function packColor(c,t)
    local function b(v) return math.clamp(math.floor(v*255+.5),0,255) end
    return b(c.R)+b(c.G)*256+b(c.B)*65536+b(1-t)*16777216
end
local function hudSnapshot(cam)
    local size=cam.ViewportSize;if size.X<1 or size.Y<1 then return {} end
    local inset=GuiService:GetGuiInset();local entries={};local pg=player:FindFirstChildOfClass('PlayerGui')
    if not pg then return entries end
    local roots={}
    for _,root in pg:GetChildren() do if root:IsA('ScreenGui') and root.Enabled and root~=gui then roots[#roots+1]=root end end
    table.sort(roots,function(a,b) return a.DisplayOrder<b.DisplayOrder end)
    local function visit(obj,clip,offset,depth)
        if #entries>=256 or depth>32 or not obj:IsA('GuiObject') or not obj.Visible then return end
        local pos=obj.AbsolutePosition+offset;local sz=obj.AbsoluteSize
        local x,y,w,h=pos.X/size.X,pos.Y/size.Y,sz.X/size.X,sz.Y/size.Y
        local text='';local fg=0;local ts=0;local ax,ay=1,1
        if obj:IsA('TextLabel') or obj:IsA('TextButton') or obj:IsA('TextBox') then
            text=obj.ContentText or obj.Text; if #text>1024 then text=string.sub(text,1,1024) end
            fg=packColor(obj.TextColor3,obj.TextTransparency);ts=obj.TextSize/size.Y
            if obj.TextScaled then ts=math.min(sz.Y*.75,sz.X/math.max(1,#text)*1.6)/size.Y end
            ax=obj.TextXAlignment==Enum.TextXAlignment.Left and 0 or obj.TextXAlignment==Enum.TextXAlignment.Right and 2 or 1
            ay=obj.TextYAlignment==Enum.TextYAlignment.Top and 0 or obj.TextYAlignment==Enum.TextYAlignment.Bottom and 2 or 1
        end
        local corner=obj:FindFirstChildOfClass('UICorner');local radius=corner and math.min(sz.X,sz.Y)*corner.CornerRadius.Scale+corner.CornerRadius.Offset or 0
        if w>0 and h>0 then
            entries[#entries+1]={x=x,y=y,w=w,h=h,cx=clip[1],cy=clip[2],cw=math.max(0,clip[3]-clip[1]),ch=math.max(0,clip[4]-clip[2]),size=math.max(0,ts),border=obj.BorderSizePixel/size.Y,round=math.max(0,radius/size.Y),bg=packColor(obj.BackgroundColor3,obj.BackgroundTransparency),fg=fg,bc=packColor(obj.BorderColor3,0),ax=ax,ay=ay,text=text}
        end
        local nextClip=clip
        if obj.ClipsDescendants or obj:IsA('ScrollingFrame') then nextClip={math.max(x,clip[1]),math.max(y,clip[2]),math.min(x+w,clip[3]),math.min(y+h,clip[4])} end
        local children={};for _,child in obj:GetChildren() do if child:IsA('GuiObject') then children[#children+1]=child end end
        table.sort(children,function(a,b) return a.ZIndex<b.ZIndex end)
        for _,child in children do visit(child,nextClip,offset,depth+1) end
    end
    for _,root in roots do
        local children={};for _,child in root:GetChildren() do if child:IsA('GuiObject') then children[#children+1]=child end end
        table.sort(children,function(a,b) return a.ZIndex<b.ZIndex end)
        local offset=root.IgnoreGuiInset and Vector2.zero or inset
        for _,child in children do visit(child,{0,0,1,1},offset,0) end
    end
    return entries
end
local hudElapsed=0
local hudLast=''
local hudLastSend=-100
local elapsed=0
local fastElapsed=0
RunService:BindToRenderStep('LumenGPU_ExternalCamera',Enum.RenderPriority.Camera.Value+1,function(dt)
    if not active then return end
    pcall(updateCamera)
    hudElapsed+=dt
    if hudElapsed>=.1 then
        hudElapsed=0;local cam=workspace.CurrentCamera
        if cam then local ok,rows=pcall(hudSnapshot,cam);if ok then local encoded=HTTP:JSONEncode(rows);if encoded~=hudLast or os.clock()-hudLastSend>1 then hudLast=encoded;hudLastSend=os.clock();remote:FireServer('hud',rows) end end end
    end
    elapsed+=dt;fastElapsed+=dt;if elapsed<1/60 then return end;elapsed=elapsed%(1/60)
    local cam=workspace.CurrentCamera;if not cam then return end
    local c=cam.CFrame;local fast=nil
    local sky=LocalLighting:FindFirstChildOfClass('Sky')
    local head=player.Character and player.Character:FindFirstChild('Head')
    local hideAvatar=external and firstPerson or (not external and (player.CameraMode==Enum.CameraMode.LockFirstPerson or (head and (c.Position-head.Position).Magnitude<=.9)))
    local environment={clock=LocalLighting.ClockTime,sunSize=sky and sky.SunAngularSize or 11,brightness=LocalLighting.Brightness,celestial=not sky or sky.CelestialBodiesShown,firstPerson=hideAvatar==true}
    if fastElapsed>=1/30 then fastElapsed=fastElapsed%(1/30);fast=fastSnapshot() end
    -- Character and camera are sampled during the same render step.
    remote:FireServer('camera',{p=vec(c.Position),r=vec(c.RightVector),u=vec(c.UpVector),f=vec(c.LookVector),fov=cam.FieldOfView,sun=vec(LocalLighting:GetSunDirection()),environment=environment},cachedCharacter,fast)
end)
RunService.Heartbeat:Connect(function()
    if not active then return end
    local now=os.clock()
    if now-lastAck>2 and now-lastRetry>2 then lastRetry=now;invalidateCapture();remote:FireServer('start') end
    button.Text='LUMEN GPU: '..(now-lastAck>2 and 'Connecting...' or status)..' (Stop)'
end)
player.CharacterAdded:Connect(function()
    if external then disableDefaultControls() end
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
local latestAvatar={} -- other moving objects
local latestCharacter={}
local latestEnvironment=nil;local latestSun=nil
local latestHUD={};local hudSerial=0;local sentHUD=-1
local cameraSerial=0;local sentCamera=-1;local cameraSentAt=0
local avatarSerial=0;local sentAvatar=-1
local latestWorld=nil
local worldSerial=0
local pending=nil
local pendingMesh=nil
local lastMeshUpload=-100
local lastSnapshot=-100
local lastPartsJSON=nil
local cameraWS=nil;local geometryWS=nil
local cameraOpen=false;local geometryOpen=false
local cameraRetry=0;local geometryRetry=0
local outstanding=0;local lastCameraAck=0
local geometryPending=nil
local geometryRejectedUntil=0;local lastGeometryWarning=-100;local lastCameraWarning=-100
local function closeCamera()
 local old=cameraWS;cameraWS=nil;cameraOpen=false;outstanding=0;sentCamera=-1
 if old then pcall(function() old:Close() end) end
end
local function closeGeometry()
 local old=geometryWS;geometryWS=nil;geometryOpen=false;geometryPending=nil;sentAvatar=-1;lastPartsJSON=nil
 if old then pcall(function() old:Close() end) end
end
local function closeWS() closeCamera();closeGeometry() end
local function connectCamera()
 if cameraWS or os.clock()<cameraRetry then return end
 cameraRetry=os.clock()+2
 local ok,c=pcall(function() return HTTP:CreateWebStreamClient(Enum.WebStreamClientType.WebSocket,{Url='ws://127.0.0.1:8765/api/ws'}) end)
 if not ok or not c then return end
 cameraWS=c
 local function opened() if cameraWS==c then cameraOpen=true;outstanding=0;sentCamera=-1;sentHUD=-1;lastCameraAck=os.clock() end end
 c.Opened:Connect(opened)
 c.MessageReceived:Connect(function(msg)
  if cameraWS~=c or not owner then return end
  outstanding=math.max(0,outstanding-1);lastCameraAck=os.clock()
  local good,ctrl=pcall(function() return HTTP:JSONDecode(msg) end)
  if good and type(ctrl)=='table' and not ctrl.error then ctrl.transport='WS';remote:FireClient(owner,'input',ctrl)
  elseif os.clock()-lastCameraWarning>=2 then lastCameraWarning=os.clock();warn('[LumenGPU] Camera update rejected: '..tostring(good and type(ctrl)=='table' and ctrl.error or 'invalid reply')) end
 end)
 local function failed() if cameraWS==c then closeCamera();cameraRetry=os.clock()+1 end end
 c.Closed:Connect(failed);c.Error:Connect(failed)
 if c.ConnectionState.Name=='Open' then opened() end
 task.delay(3,function() if cameraWS==c and not cameraOpen then failed() end end)
end
local function connectGeometry()
 if geometryWS or os.clock()<geometryRetry then return end
 geometryRetry=os.clock()+2
 local ok,c=pcall(function() return HTTP:CreateWebStreamClient(Enum.WebStreamClientType.WebSocket,{Url='ws://127.0.0.1:8765/api/geometry-ws'}) end)
 if not ok or not c then return end
 geometryWS=c
 local function opened() if geometryWS==c then geometryOpen=true;geometryPending=nil;lastPartsJSON=nil;sentAvatar=-1 end end
 c.Opened:Connect(opened)
 c.MessageReceived:Connect(function(msg)
  if geometryWS~=c then return end
  local packet=geometryPending;geometryPending=nil
  local good,reply=pcall(function() return HTTP:JSONDecode(msg) end)
  if good and type(reply)=='table' and not reply.error then
   if packet then if packet.world then lastPartsJSON=packet.world end;if packet.avatar then sentAvatar=packet.avatar end end
  else
   lastPartsJSON=nil;sentAvatar=-1;geometryRejectedUntil=os.clock()+.5
   if os.clock()-lastGeometryWarning>=2 then lastGeometryWarning=os.clock();warn('[LumenGPU] Geometry update rejected: '..tostring(good and type(reply)=='table' and reply.error or 'invalid reply')) end
  end
 end)
 local function failed() if geometryWS==c then closeGeometry();geometryRetry=os.clock()+1 end end
 c.Closed:Connect(failed);c.Error:Connect(failed)
 if c.ConnectionState.Name=='Open' then opened() end
 task.delay(3,function() if geometryWS==c and not geometryOpen then failed() end end)
end
local function vec(v) return {v.X,v.Y,v.Z} end
remote.OnServerEvent:Connect(function(player,cmd,data,avatar,moving)
    if cmd=='start' and (not owner or owner==player) then
        if not owner then owner=player; latest=nil; latestAvatar={};latestCharacter={};latestHUD={};hudSerial+=1;sentHUD=-1;cameraSerial=0;sentCamera=-1;avatarSerial=0;sentAvatar=-1; latestWorld=nil;worldSerial=0;pending=nil;lastSnapshot=-100; lastPartsJSON=nil; print('[LumenGPU] Local bridge started') end
        remote:FireClient(player,'status','Waiting for HTTP')
    elseif cmd=='stop' and owner==player then owner=nil; latest=nil;pending=nil;closeWS()
    elseif cmd=='lumenusMesh' and owner==player then
        if type(data)~='number' or data%1~=0 or data<3 or data>16777215 or type(avatar)~='string' or #avatar>20 or not avatar:match('^[1-9]%d*$') then return end
        local meshId,assetId=data,avatar
        task.spawn(function()
            local deadline=os.clock()+110
            local result=nil
            repeat
                local ok,res=pcall(function() return HTTP:RequestAsync({Url='http://127.0.0.1:8765/api/lumenus',Method='POST',Headers={['Content-Type']='application/json'},Body=HTTP:JSONEncode({kind='mesh',asset=assetId,id=meshId})}) end)
                if not ok or not res.Success then break end
                local decoded,info=pcall(function() return HTTP:JSONDecode(res.Body) end)
                if not decoded or type(info)~='table' then break end
                if info.status=='ready' then result=info.size;break end
                if info.status~='queued' then warn('[Lumenus] '..assetId..': '..tostring(info.detail));break end
                task.wait(2)
            until owner~=player or os.clock()>deadline
            if owner==player then remote:FireClient(player,'lumenusMeshAck',meshId,result or false) end
        end)
    elseif cmd=='lumenusImage' and owner==player then
        if type(data)~='string' or #data>20 or not data:match('^[1-9]%d*$') or type(avatar)~='number' or avatar%1~=0 or avatar<1 or avatar>128 then return end
        local asset=data
        task.spawn(function()
            local ok,res=pcall(function() return HTTP:RequestAsync({Url='http://127.0.0.1:8765/api/lumenus',Method='POST',Headers={['Content-Type']='application/json'},Body=HTTP:JSONEncode({kind='image',asset=asset,id=0})}) end)
            if ok and res.Success and owner==player then
                local good,info=pcall(function() return HTTP:JSONDecode(res.Body) end)
                if good and info.slot then remote:FireClient(player,'lumenusImageAck',asset,info.slot) end
            end
        end)
    elseif cmd=='meshBegin' and owner==player then
        if type(data)=='number' and data%1==0 and data>=3 and data<=16777215 and type(avatar)=='number' and avatar%3==0 and avatar>=3 and avatar<=60000 then pendingMesh={id=data,count=avatar,rows={}} end
    elseif cmd=='meshChunk' and owner==player and pendingMesh and pendingMesh.id==data then
        if type(avatar)~='table' or #avatar>384 or #pendingMesh.rows+#avatar>pendingMesh.count then pendingMesh=nil else for _,v in avatar do pendingMesh.rows[#pendingMesh.rows+1]=v end end
    elseif cmd=='meshEnd' and owner==player and pendingMesh and pendingMesh.id==data then
        local batch=pendingMesh;pendingMesh=nil
        if #batch.rows~=batch.count then remote:FireClient(player,'meshAck',data,false);return end
        task.spawn(function()
            -- One asset at a time; pace requests under HTTP limits.
            local waitFor=math.max(0,2-(os.clock()-lastMeshUpload));if waitFor>0 then task.wait(waitFor) end
            lastMeshUpload=os.clock()
            local vertices,uvs,normals={},{},{}
            for _,row in batch.rows do
                if type(row)~='table' or (#row~=5 and #row~=8) then remote:FireClient(player,'meshAck',batch.id,false);return end
                vertices[#vertices+1]={row[1],row[2],row[3]};uvs[#uvs+1]={row[4],row[5]};normals[#normals+1]={row[6] or 0,row[7] or 0,row[8] or 0}
            end
            local ok,res=pcall(function() return HTTP:RequestAsync({Url='http://127.0.0.1:8765/api/mesh',Method='POST',Headers={['Content-Type']='application/json'},Body=HTTP:JSONEncode({id=batch.id,vertices=vertices,uvs=uvs,normals=normals})}) end)
            if owner==player then remote:FireClient(player,'meshAck',batch.id,ok and res.Success) end
            if not ok or not res.Success then warn('[LumenGPU] Mesh HTTP upload failed: '..tostring(ok and res.StatusCode or res)) end
        end)
    elseif cmd=='worldBegin' and owner==player then
        if type(data)=='number' and data>worldSerial and type(avatar)=='number' and avatar>=0 and avatar<=15360 and avatar%1==0 then pending={serial=data,count=avatar,rows={}} end
    elseif cmd=='worldChunk' and owner==player and pending and data==pending.serial then
        if type(avatar)~='table' or #avatar>128 or #pending.rows+#avatar>pending.count then pending=nil else for _,part in avatar do pending.rows[#pending.rows+1]=part end end
    elseif cmd=='worldEnd' and owner==player and pending and data==pending.serial then
        if #pending.rows==pending.count then latestWorld=pending.rows;worldSerial=pending.serial;print('[LumenGPU] Accepted client world '..worldSerial..': '..#latestWorld..' static parts') end;pending=nil
    elseif cmd=='hud' and owner==player and type(data)=='table' and #data<=256 then latestHUD=data;hudSerial+=1
    elseif cmd=='camera' and owner==player and type(data)=='table' then
        if type(data.p)=='table' and #data.p==3 and type(data.r)=='table' and #data.r==3 and type(data.u)=='table' and #data.u==3 and type(data.f)=='table' and #data.f==3 and type(data.fov)=='number' then
            latest=data;cameraSerial+=1
            latestEnvironment=data.environment;latestSun=data.sun
            if type(avatar)=='table' and #avatar<=64 then latestCharacter=avatar end
            if type(moving)=='table' and #moving<=1024 then latestAvatar=moving;avatarSerial+=1 end
        end
    end
end)
Players.PlayerRemoving:Connect(function(p) if p==owner then owner=nil; latest=nil;closeWS() end end)
-- Camera/control and geometry use independent persistent channels.
-- A small window permits pipelining without an unbounded queue.
local lastHTTP=-100
local lastError=-100
task.spawn(function()
 while task.wait(1/120) do
  if owner and latest then
   local ok,err=pcall(function()
    connectCamera()
    local now=os.clock()
    if cameraOpen then
     if outstanding>0 and now-lastCameraAck>.75 then closeCamera();return end
     if outstanding>=4 then return end
     if sentCamera==cameraSerial and now-cameraSentAt<.1 then return end
     local serial=cameraSerial
     local hud=sentHUD~=hudSerial and latestHUD or nil
     local payload=HTTP:JSONEncode({camera=latest,character=latestCharacter,sun=latestSun or vec(Lighting:GetSunDirection()),environment=latestEnvironment,hud=hud})
     outstanding+=1
     local sent,e=pcall(function() cameraWS:Send(payload) end)
     if not sent then closeCamera();error(e) end
     sentCamera=serial;cameraSentAt=now;if hud then sentHUD=hudSerial end
    elseif now-lastHTTP>=.15 then
     -- Compatibility fallback retains geometry when both sockets are unavailable.
     lastHTTP=now
     local hud=sentHUD~=hudSerial and latestHUD or nil
     local update={camera=latest,character=latestCharacter,sun=latestSun or vec(Lighting:GetSunDirection()),environment=latestEnvironment,hud=hud}
     -- Geometry fallback is owned by the independent geometry task.
     local res=HTTP:RequestAsync({Url='http://127.0.0.1:8765/api/update-controls',Method='POST',Headers={['Content-Type']='application/json'},Body=HTTP:JSONEncode(update)})
     if not res.Success then error('HTTP '..res.StatusCode..': '..tostring(res.Body):sub(1,180)) end
     if hud then sentHUD=hudSerial end
     if owner then local ctrl=HTTP:JSONDecode(res.Body);ctrl.transport='HTTP';remote:FireClient(owner,'input',ctrl) end
    end
   end)
   if not ok and os.clock()-lastError>2 then lastError=os.clock();warn('[LumenGPU] Camera: '..tostring(err)) end
  end
 end
end)
local lastGeom=0
local lastGeomHTTP=-100
while task.wait(1/60) do
 if owner and latest then
  local ok,err=pcall(function()
   connectGeometry()
   local now=os.clock()
   if now<geometryRejectedUntil then return end
   if not geometryOpen then
    if now-lastGeomHTTP<1 then return end
    local update={camera=latest,sun=vec(Lighting:GetSunDirection())};local w,a=nil,nil
    if latestWorld and lastPartsJSON~=worldSerial then update.parts=latestWorld;w=worldSerial end
    if sentAvatar~=avatarSerial then update.avatar=latestAvatar;a=avatarSerial end
    if not w and not a then return end
    lastGeomHTTP=now
    local res=HTTP:RequestAsync({Url='http://127.0.0.1:8765/api/geometry-update',Method='POST',Headers={['Content-Type']='application/json'},Body=HTTP:JSONEncode(update)})
    if not res.Success then geometryRejectedUntil=os.clock()+.5;error('Geometry HTTP '..res.StatusCode..': '..tostring(res.Body):sub(1,180)) end
    if w then lastPartsJSON=w end;if a then sentAvatar=a end
    return
   end
   if geometryPending then if now-geometryPending.at>2 then closeGeometry() end;return end
   local update={camera=latest,sun=vec(Lighting:GetSunDirection())};local w,a=nil,nil
   if latestWorld and lastPartsJSON~=worldSerial then update.parts=latestWorld;w=worldSerial end
   if sentAvatar~=avatarSerial then update.avatar=latestAvatar;a=avatarSerial end
   if not w and not a and now-lastGeom<1 then return end
   lastGeom=now;geometryPending={at=now,world=w,avatar=a}
   local sent,e=pcall(function() geometryWS:Send(HTTP:JSONEncode(update)) end)
   if not sent then closeGeometry();error(e) end
  end)
  if not ok then warn('[LumenGPU] Geometry: '..tostring(err)) end
 end
end
]====])
print('LUMEN GPU 0.9.4 Lumenus asset discovery installed. Enable HTTP Requests, start LumenBridge.exe and the native renderer, Play locally and press P. Existing LUMEN installations are not removed; stop their renderer.')
